-- V575: student contacts a department uploads are held unconfirmed until the student confirms them; reset links go only to
-- confirmed contacts.
--
-- V572 lets the Registry and the departments fill a student's empty phone or e-mail from a class list. A mistyped address
-- would have received that student's password reset link: the reset and the desk's link went to whatever the record held.
--
--   * people.student_contact.email_pending / phone_pending (with the upload that filled it): set when an upload fills the
--     field (people.load_contacts, restated from V572's text with the upload named), cleared when the student confirms it,
--     when the desk confirms it with the student, or when anyone else changes the value (the student's own save, the desk's
--     edit) — a trigger keeps the mark only on the write that set it.
--   * people.student_reset_reach(student): the e-mail and phone a reset link may go to — the contact the student gave, the
--     desk keyed or the student confirmed, else their applicant account's; never an unconfirmed upload. The unconfirmed ones
--     are named beside them. Notices and announcements still reach an uploaded contact; only reset links do not.
--   * The student confirms: a six-digit code sent to the contact (people.contact_code_issue: at most three an hour, fifteen
--     minutes each), entered while signed in (people.contact_code_check: five tries); or says it is not theirs
--     (people.contact_refuse: the field is emptied). The desk confirms after checking with the student
--     (people.contact_confirm_desk). Each outcome kept in people.contact_confirmation with the upload, and counted per upload
--     (people.contact_upload_outcomes).
--   * Contacts uploaded since V572 are marked unconfirmed from the audit trail (the upload's reason and office, within minutes
--     of it, the value still on the record).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'V575: uploaded contacts held unconfirmed', true);

ALTER TABLE people.student_contact
    ADD COLUMN email_pending   boolean NOT NULL DEFAULT false,
    ADD COLUMN email_upload_id uuid REFERENCES people.contact_upload (id) ON DELETE SET NULL,
    ADD COLUMN phone_pending   boolean NOT NULL DEFAULT false,
    ADD COLUMN phone_upload_id uuid REFERENCES people.contact_upload (id) ON DELETE SET NULL;
CREATE INDEX ix_student_contact_email_upload ON people.student_contact (email_upload_id) WHERE email_upload_id IS NOT NULL;
CREATE INDEX ix_student_contact_phone_upload ON people.student_contact (phone_upload_id) WHERE phone_upload_id IS NOT NULL;
COMMENT ON COLUMN people.student_contact.email_pending IS
  'V575: the e-mail came from a department''s upload and the student has not confirmed it: no reset link goes to it';
COMMENT ON COLUMN people.student_contact.phone_pending IS
  'V575: the phone came from a department''s upload and the student has not confirmed it: no reset link goes to it';

-- the mark is kept only on the write that sets it: any other change of the value (the student's save, the desk's edit) is the
-- student's or the desk's own, and an emptied field has nothing to confirm
CREATE FUNCTION people.student_contact_pending_kept()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.email IS DISTINCT FROM OLD.email AND NOT (NEW.email_pending AND NOT OLD.email_pending) THEN
            NEW.email_pending := false;
        END IF;
        IF NEW.phone IS DISTINCT FROM OLD.phone AND NOT (NEW.phone_pending AND NOT OLD.phone_pending) THEN
            NEW.phone_pending := false;
        END IF;
    END IF;
    IF nullif(btrim(coalesce(NEW.email, '')), '') IS NULL THEN NEW.email_pending := false; END IF;
    IF nullif(btrim(coalesce(NEW.phone, '')), '') IS NULL THEN NEW.phone_pending := false; END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_student_contact_pending BEFORE INSERT OR UPDATE ON people.student_contact
    FOR EACH ROW EXECUTE FUNCTION people.student_contact_pending_kept();

-- ── where a reset link may go ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.student_reset_reach(p_student uuid)
RETURNS TABLE (email text, phone text, unconfirmed_email text, unconfirmed_phone text)
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(CASE WHEN c.email_pending THEN NULL ELSE c.email END, a.email),
           coalesce(CASE WHEN c.phone_pending THEN NULL ELSE c.phone END, a.phone),
           CASE WHEN c.email_pending THEN c.email END,
           CASE WHEN c.phone_pending THEN c.phone END
      FROM people.student s
      LEFT JOIN people.student_contact c ON c.student_id = s.id
      LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id
     WHERE s.id = p_student
$fn$;
COMMENT ON FUNCTION people.student_reset_reach(uuid) IS
  'V575: the e-mail and phone a password reset link may go to (never a contact uploaded and not yet confirmed), with the unconfirmed ones beside them';

-- ── each confirmation, refusal and code ────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.contact_confirmation (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    field       text NOT NULL CHECK (field IN ('EMAIL', 'PHONE')),
    value       text NOT NULL,
    upload_id   uuid REFERENCES people.contact_upload (id) ON DELETE SET NULL,
    code_hash   text,
    expires_at  timestamptz,
    attempts    integer NOT NULL DEFAULT 0,
    outcome     text CHECK (outcome IN ('CONFIRMED', 'REFUSED', 'DESK', 'EXPIRED', 'REPLACED')),
    decided_at  timestamptz,
    decided_by  uuid,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_contact_confirmation_student ON people.contact_confirmation (student_id, field, created_at DESC);
CREATE INDEX ix_contact_confirmation_upload ON people.contact_confirmation (upload_id) WHERE upload_id IS NOT NULL;
COMMENT ON TABLE people.contact_confirmation IS
  'V575: an uploaded contact confirmed by the student''s code or by the desk, or refused by the student; the codes issued (kept only as a hash)';
SELECT audit.attach('people.contact_confirmation');

CREATE FUNCTION people.contact_pending_value(p_student uuid, p_field text)
RETURNS TABLE (value text, upload_id uuid)
LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN upper(p_field) = 'EMAIL' THEN c.email ELSE c.phone END,
           CASE WHEN upper(p_field) = 'EMAIL' THEN c.email_upload_id ELSE c.phone_upload_id END
      FROM people.student_contact c
     WHERE c.student_id = p_student AND CASE WHEN upper(p_field) = 'EMAIL' THEN c.email_pending ELSE c.phone_pending END
$fn$;

-- a code is issued for the unconfirmed contact (the API makes it, sends it and keeps only its hash): at most three an hour
CREATE FUNCTION people.contact_code_issue(p_student uuid, p_field text, p_code_hash text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v record; v_field text := upper(coalesce(p_field, ''));
BEGIN
    IF v_field NOT IN ('EMAIL', 'PHONE') THEN
        RAISE EXCEPTION 'CONTACT_FIELD: an e-mail address or a phone number is confirmed' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO v FROM people.contact_pending_value(p_student, v_field);
    IF v.value IS NULL THEN
        RAISE EXCEPTION 'CONTACT_NOT_PENDING: there is no unconfirmed % on your record', CASE v_field WHEN 'EMAIL' THEN 'e-mail address' ELSE 'phone number' END
            USING ERRCODE = '23514';
    END IF;
    IF (SELECT count(*) FROM people.contact_confirmation x WHERE x.student_id = p_student AND x.field = v_field AND x.code_hash IS NOT NULL
          AND x.created_at > now() - interval '1 hour') >= 3 THEN
        RAISE EXCEPTION 'CONTACT_CODE_LIMIT: three codes have been sent in the last hour' USING ERRCODE = '23514';
    END IF;
    UPDATE people.contact_confirmation x SET outcome = 'REPLACED', decided_at = now()
     WHERE x.student_id = p_student AND x.field = v_field AND x.outcome IS NULL AND x.code_hash IS NOT NULL;
    INSERT INTO people.contact_confirmation (student_id, field, value, upload_id, code_hash, expires_at)
    VALUES (p_student, v_field, v.value, v.upload_id, p_code_hash, now() + interval '15 minutes');
    RETURN v.value;
END $fn$;

-- the code entered: CONFIRMED, WRONG (a try used), EXPIRED (none open, or five tries spent) — answered, never raised, so a try is counted
CREATE FUNCTION people.contact_code_check(p_student uuid, p_field text, p_code_hash text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE x people.contact_confirmation; v_field text := upper(coalesce(p_field, '')); v_now text;
BEGIN
    SELECT * INTO x FROM people.contact_confirmation c
     WHERE c.student_id = p_student AND c.field = v_field AND c.outcome IS NULL AND c.code_hash IS NOT NULL
     ORDER BY c.created_at DESC LIMIT 1 FOR UPDATE;
    IF NOT FOUND OR x.expires_at <= now() THEN
        IF FOUND THEN UPDATE people.contact_confirmation SET outcome = 'EXPIRED', decided_at = now() WHERE id = x.id; END IF;
        RETURN 'EXPIRED';
    END IF;
    IF x.code_hash <> coalesce(p_code_hash, '') THEN
        UPDATE people.contact_confirmation SET attempts = attempts + 1,
               outcome = CASE WHEN attempts + 1 >= 5 THEN 'EXPIRED' END, decided_at = CASE WHEN attempts + 1 >= 5 THEN now() END
         WHERE id = x.id;
        RETURN CASE WHEN x.attempts + 1 >= 5 THEN 'EXPIRED' ELSE 'WRONG' END;
    END IF;
    SELECT value INTO v_now FROM people.contact_pending_value(p_student, v_field);
    IF v_now IS DISTINCT FROM x.value THEN
        UPDATE people.contact_confirmation SET outcome = 'EXPIRED', decided_at = now() WHERE id = x.id;
        RETURN 'EXPIRED';
    END IF;
    IF v_field = 'EMAIL' THEN
        UPDATE people.student_contact SET email_pending = false, updated_at = now() WHERE student_id = p_student;
    ELSE
        UPDATE people.student_contact SET phone_pending = false, updated_at = now() WHERE student_id = p_student;
    END IF;
    UPDATE people.contact_confirmation SET outcome = 'CONFIRMED', decided_at = now(), decided_by = p_student WHERE id = x.id;
    RETURN 'CONFIRMED';
END $fn$;

-- not theirs: the field is emptied (the University no longer writes to it), the refusal kept against the upload
CREATE FUNCTION people.contact_refuse(p_student uuid, p_field text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v record; v_field text := upper(coalesce(p_field, ''));
BEGIN
    SELECT * INTO v FROM people.contact_pending_value(p_student, v_field);
    IF v.value IS NULL THEN
        RAISE EXCEPTION 'CONTACT_NOT_PENDING: there is no unconfirmed contact of that kind on the record' USING ERRCODE = '23514';
    END IF;
    UPDATE people.contact_confirmation SET outcome = 'REPLACED', decided_at = now()
     WHERE student_id = p_student AND field = v_field AND outcome IS NULL;
    INSERT INTO people.contact_confirmation (student_id, field, value, upload_id, outcome, decided_at, decided_by)
    VALUES (p_student, v_field, v.value, v.upload_id, 'REFUSED', now(), nullif(current_setting('moaum.actor_id', true), '')::uuid);
    IF v_field = 'EMAIL' THEN
        UPDATE people.student_contact SET email = NULL, updated_at = now() WHERE student_id = p_student;
    ELSE
        UPDATE people.student_contact SET phone = NULL, updated_at = now() WHERE student_id = p_student;
    END IF;
    RETURN 'REFUSED';
END $fn$;

-- the desk, having checked with the student, confirms it (the agent named)
CREATE FUNCTION people.contact_confirm_desk(p_student uuid, p_field text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v record; v_field text := upper(coalesce(p_field, ''));
BEGIN
    SELECT * INTO v FROM people.contact_pending_value(p_student, v_field);
    IF v.value IS NULL THEN
        RAISE EXCEPTION 'CONTACT_NOT_PENDING: there is no unconfirmed contact of that kind on the record' USING ERRCODE = '23514';
    END IF;
    UPDATE people.contact_confirmation SET outcome = 'REPLACED', decided_at = now()
     WHERE student_id = p_student AND field = v_field AND outcome IS NULL;
    INSERT INTO people.contact_confirmation (student_id, field, value, upload_id, outcome, decided_at, decided_by)
    VALUES (p_student, v_field, v.value, v.upload_id, 'DESK', now(), nullif(current_setting('moaum.actor_id', true), '')::uuid);
    IF v_field = 'EMAIL' THEN
        UPDATE people.student_contact SET email_pending = false, updated_at = now() WHERE student_id = p_student;
    ELSE
        UPDATE people.student_contact SET phone_pending = false, updated_at = now() WHERE student_id = p_student;
    END IF;
    RETURN 'DESK';
END $fn$;

-- what became of an upload's contacts: still waiting, confirmed (by the student or the desk), refused
CREATE FUNCTION people.contact_upload_outcomes(p_upload uuid)
RETURNS TABLE (waiting bigint, confirmed bigint, refused bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT (SELECT count(*) FILTER (WHERE c.email_pending AND c.email_upload_id = p_upload) + count(*) FILTER (WHERE c.phone_pending AND c.phone_upload_id = p_upload)
              FROM people.student_contact c WHERE c.email_upload_id = p_upload OR c.phone_upload_id = p_upload),
           (SELECT count(*) FROM people.contact_confirmation x WHERE x.upload_id = p_upload AND x.outcome IN ('CONFIRMED', 'DESK')),
           (SELECT count(*) FROM people.contact_confirmation x WHERE x.upload_id = p_upload AND x.outcome = 'REFUSED')
$fn$;

-- ── the load, restated from V572's text: the upload named, the fields it fills held unconfirmed ─────────────────────────────
DROP FUNCTION people.load_contacts(jsonb, text, text);
CREATE FUNCTION people.load_contacts(p_rows jsonb, p_faculty text DEFAULT NULL::text, p_dept text DEFAULT NULL::text, p_upload uuid DEFAULT NULL::uuid)
 RETURNS TABLE(row_no integer, number_in text, phone_in text, email_in text, student_id uuid, name text, number text, programme text, phone text, email text, phone_outcome text, email_outcome text, outcome text, message text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'CONTACT_ROWS: the upload carries a list of rows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 20000 THEN
        RAISE EXCEPTION 'CONTACT_TOO_MANY: % rows; one upload holds 20,000 at most', jsonb_array_length(p_rows) USING ERRCODE = '23514';
    END IF;
    RETURN QUERY
    WITH r AS (
        SELECT o.ord::int AS row_no, btrim(coalesce(o.v->>'number', '')) AS number_in, btrim(coalesce(o.v->>'phone', '')) AS phone_in,
               btrim(coalesce(o.v->>'email', '')) AS email_in
          FROM jsonb_array_elements(p_rows) WITH ORDINALITY o(v, ord)),
    n AS (
        SELECT r.*, people.contact_phone(r.phone_in) AS ph, nullif(lower(r.email_in), '') AS em,
               (SELECT array_agg(DISTINCT s.id) FROM people.student s
                 WHERE r.number_in <> '' AND s.duplicate_of IS NULL
                   AND (upper(s.matric_no) = upper(r.number_in) OR upper(s.admission_no) = upper(r.number_in) OR upper(s.jamb_reg_no) = upper(r.number_in))) AS ids
          FROM r),
    k AS (
        SELECT n.*, s.id AS sid, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS who,
               coalesce(s.matric_no, s.admission_no, s.jamb_reg_no) AS num, p.name AS prog, p.faculty_code AS fac, p.dept_code AS dept,
               nullif(btrim(coalesce(c.phone, a.phone, '')), '') AS held_phone, nullif(btrim(coalesce(c.email, a.email, '')), '') AS held_email,
               row_number() OVER (PARTITION BY s.id ORDER BY n.row_no) AS nth
          FROM n
          LEFT JOIN people.student s ON s.id = CASE WHEN cardinality(n.ids) = 1 THEN n.ids[1] END
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN people.student_contact c ON c.student_id = s.id
          LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id),
    -- the row itself: matched to one student, within the uploader's reach, the first row for that student
    b AS (
        SELECT k.*,
               CASE WHEN k.number_in = '' OR (k.phone_in = '' AND k.email_in = '') THEN 'INCOMPLETE'
                    WHEN k.ids IS NULL THEN 'NO_STUDENT'
                    WHEN cardinality(k.ids) > 1 THEN 'AMBIGUOUS'
                    WHEN (p_faculty IS NOT NULL AND k.fac IS DISTINCT FROM p_faculty) OR (p_dept IS NOT NULL AND k.dept IS DISTINCT FROM p_dept) THEN 'OUTSIDE_SCOPE'
                    WHEN k.nth > 1 THEN 'DUPLICATE_ROW' END AS blocked
          FROM k),
    -- the same phone or e-mail on an earlier row of the file (for another student: a student is on one row)
    b1 AS (
        SELECT b.*, row_number() OVER (PARTITION BY b.blocked IS NULL, b.ph ORDER BY b.row_no) AS ph_nth,
               row_number() OVER (PARTITION BY b.blocked IS NULL, b.em ORDER BY b.row_no) AS em_nth
          FROM b),
    -- each field: a malformed one, one the student holds, one another student holds (or an earlier row gives another student)
    f AS (
        SELECT b.*,
               CASE WHEN b.blocked IS NOT NULL OR b.phone_in = '' THEN 'NONE'
                    WHEN NOT platform.phone_valid(b.ph) THEN 'INVALID'
                    WHEN b.held_phone IS NOT NULL THEN 'KEPT'
                    WHEN EXISTS (SELECT 1 FROM people.student_contact oc WHERE oc.phone = b.ph AND oc.student_id <> b.sid) THEN 'TAKEN'
                    WHEN b.ph_nth > 1 THEN 'TAKEN'
                    ELSE 'FILL' END AS po,
               CASE WHEN b.blocked IS NOT NULL OR b.email_in = '' THEN 'NONE'
                    WHEN NOT platform.email_valid(b.em) THEN 'INVALID'
                    WHEN b.held_email IS NOT NULL THEN 'KEPT'
                    WHEN EXISTS (SELECT 1 FROM people.student_contact oc WHERE lower(oc.email) = b.em AND oc.student_id <> b.sid) THEN 'TAKEN'
                    WHEN EXISTS (SELECT 1 FROM admissions.applicant_account oa JOIN people.student os ON os.candidate_id = oa.candidate_id
                                  WHERE lower(oa.email) = b.em AND os.id <> b.sid AND os.duplicate_of IS NULL) THEN 'TAKEN'
                    WHEN b.em_nth > 1 THEN 'TAKEN'
                    ELSE 'FILL' END AS eo
          FROM b1 b),
    d AS (
        SELECT f.*,
               coalesce(f.blocked, CASE WHEN 'FILL' IN (f.po, f.eo) THEN 'FILLED'
                                        WHEN f.po IN ('INVALID', 'TAKEN') OR f.eo IN ('INVALID', 'TAKEN') THEN 'REFUSED'
                                        ELSE 'ALREADY' END) AS oc
          FROM f),
    w AS (
        -- V575: a field the upload fills is held unconfirmed (pending) until the student confirms it, with the upload named
        INSERT INTO people.student_contact AS c (student_id, phone, email, updated_at, phone_pending, phone_upload_id, email_pending, email_upload_id)
        SELECT d.sid, CASE WHEN d.po = 'FILL' THEN d.ph END, CASE WHEN d.eo = 'FILL' THEN d.em END, now(),
               d.po = 'FILL', CASE WHEN d.po = 'FILL' THEN p_upload END, d.eo = 'FILL', CASE WHEN d.eo = 'FILL' THEN p_upload END
          FROM d WHERE d.oc = 'FILLED'
        ON CONFLICT ON CONSTRAINT student_contact_pkey DO UPDATE
           SET phone = coalesce(nullif(btrim(c.phone), ''), EXCLUDED.phone), email = coalesce(nullif(btrim(c.email), ''), EXCLUDED.email), updated_at = now(),
               phone_pending = CASE WHEN nullif(btrim(c.phone), '') IS NULL AND EXCLUDED.phone IS NOT NULL THEN true ELSE c.phone_pending END,
               phone_upload_id = CASE WHEN nullif(btrim(c.phone), '') IS NULL AND EXCLUDED.phone IS NOT NULL THEN EXCLUDED.phone_upload_id ELSE c.phone_upload_id END,
               email_pending = CASE WHEN nullif(btrim(c.email), '') IS NULL AND EXCLUDED.email IS NOT NULL THEN true ELSE c.email_pending END,
               email_upload_id = CASE WHEN nullif(btrim(c.email), '') IS NULL AND EXCLUDED.email IS NOT NULL THEN EXCLUDED.email_upload_id ELSE c.email_upload_id END
        RETURNING c.student_id)
    SELECT d.row_no, d.number_in, d.phone_in, d.email_in, d.sid, d.who, d.num, d.prog,
           CASE WHEN d.po = 'FILL' THEN d.ph END, CASE WHEN d.eo = 'FILL' THEN d.em END, d.po, d.eo, d.oc,
           CASE d.oc
                WHEN 'INCOMPLETE' THEN 'A row names a student number and a phone or an e-mail address'
                WHEN 'NO_STUDENT' THEN 'No student holds this matriculation, admission or JAMB number'
                WHEN 'AMBIGUOUS' THEN 'More than one student holds this number: use the matriculation number'
                WHEN 'OUTSIDE_SCOPE' THEN 'The student is outside your ' || CASE WHEN p_dept IS NOT NULL THEN 'department' ELSE 'faculty' END
                WHEN 'DUPLICATE_ROW' THEN 'The student is on an earlier row of the file'
                ELSE concat_ws('; ',
                       CASE d.po WHEN 'FILL' THEN 'Phone filled' WHEN 'KEPT' THEN 'Phone kept: the student holds one'
                                 WHEN 'INVALID' THEN 'Phone not a Nigerian mobile number (0 and ten digits)' WHEN 'TAKEN' THEN 'Phone held by another student' END,
                       CASE d.eo WHEN 'FILL' THEN 'E-mail filled' WHEN 'KEPT' THEN 'E-mail kept: the student holds one'
                                 WHEN 'INVALID' THEN 'E-mail address malformed' WHEN 'TAKEN' THEN 'E-mail held by another student' END) END
      FROM d
     ORDER BY d.row_no;
END $function$;

COMMENT ON FUNCTION people.load_contacts(jsonb, text, text, uuid) IS
  'V572, V575: uploaded (number, phone, e-mail) rows matched to one student each and filled only where the student holds none, the filled fields held unconfirmed with the upload named';

-- ── contacts uploaded since V572, marked unconfirmed from the audit trail ──────────────────────────────────────────────────
WITH filled AS (
    SELECT DISTINCT ON ((e.after_state->>'student_id')) (e.after_state->>'student_id')::uuid AS student_id, u.id AS upload_id, e.before_state, e.after_state
      FROM people.contact_upload u
      -- the audit names a row by its own key: the student is the row's student_id
      JOIN audit.entries e ON e.subject_type = 'people.student_contact' AND e.reason = u.reason AND e.actor_office = u.office
                          AND e.occurred_at >= timestamptz '2026-10-19 00:00+01'
                          AND e.occurred_at BETWEEN u.uploaded_at - interval '10 minutes' AND u.uploaded_at + interval '10 minutes'
     ORDER BY (e.after_state->>'student_id'), e.occurred_at DESC)
UPDATE people.student_contact c
   SET email_pending = c.email_pending OR (c.email IS NOT NULL AND c.email = f.after_state->>'email' AND nullif(f.before_state->>'email', '') IS NULL),
       email_upload_id = CASE WHEN c.email IS NOT NULL AND c.email = f.after_state->>'email' AND nullif(f.before_state->>'email', '') IS NULL
                              THEN f.upload_id ELSE c.email_upload_id END,
       phone_pending = c.phone_pending OR (c.phone IS NOT NULL AND c.phone = f.after_state->>'phone' AND nullif(f.before_state->>'phone', '') IS NULL),
       phone_upload_id = CASE WHEN c.phone IS NOT NULL AND c.phone = f.after_state->>'phone' AND nullif(f.before_state->>'phone', '') IS NULL
                              THEN f.upload_id ELSE c.phone_upload_id END
  FROM filled f
 WHERE c.student_id = f.student_id;

COMMIT;
