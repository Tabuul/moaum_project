-- V599: an e-mail or phone saved to a student record from the sign-in help (V596) reaches no notice until it is confirmed, the
-- ICT Support desk confirms or refuses it, and the student numbers checked on the sign-in page are logged, capped a day and watched.
--
--   * Held from notices. Since V596 a request from the sign-in page names a student by the number typed, and the e-mail or phone
--     it gives is saved to a record that holds none, unconfirmed: reset links waited for a confirmation (V575), but every other
--     notice went to it, so whoever typed another student's number heard what the University tells that student. The contact
--     is now marked as the sign-in help's (people.student_contact.email_from_sign_in / phone_from_sign_in, with the request that
--     saved it), and people.student_reach — the one address every notice reads, 33 functions and the API — leaves it out while
--     it is unconfirmed, falling back to the applicant account's as before. Confirmed by the student's code at sign-in (V575) or
--     by the desk, it reaches notices like any other; the mark goes with the value it marked (anyone writing another value
--     clears it, as the unconfirmed mark is cleared).
--   * The desk. helpdesk.sign_in_contacts lists the unconfirmed contacts the sign-in help saved, within the agent's EDIT_CONTACT
--     scope, with the request and who asked; the desk confirms one (people.contact_confirm_desk, restated to name the request)
--     or refuses it (people.contact_refuse_desk: the field emptied, the outcome kept as DESK_REFUSED, the uploader told when
--     it came from a department's upload, as a student's own refusal tells them, V580).
--   * Number checks watched. Each student number the sign-in help checks (V596: it names the student) is logged
--     (helpdesk.sign_in_lookup: the connection's address, the number, whether a student holds it; 180 days kept). A connection
--     past the day's figure (helpdesk.setting.sign_in_lookups_daily, 200 by default, empty for none) is refused until the next
--     Lagos day; one checking the alert figure of different numbers in a day (sign_in_lookups_alert, 50, empty for never) is
--     told to the Head of the ICT Support Desk (the Director of ICT where no Head is in office) once a day, notice
--     SIGN_IN_LOOKUP_ALERT. A University network shares one address among many students: the Head and the Director set both
--     figures on Sign-In Help Contacts.
--     The in-memory limit of 30 checks in fifteen minutes (V359's throttle) stands beside it.
--   * Contacts already saved from the sign-in help since V596 (the audit trail's reason "sign-in help asked from the sign-in
--     page") are marked, with their request.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V599: sign-in help contacts held until confirmed, number checks watched', true);

-- ── the contact the sign-in help saved, marked ──────────────────────────────────────────────────────────────────────────────
ALTER TABLE people.student_contact
    ADD COLUMN email_from_sign_in   boolean NOT NULL DEFAULT false,
    ADD COLUMN email_sign_in_ticket uuid REFERENCES helpdesk.ticket (id) ON DELETE SET NULL,
    ADD COLUMN phone_from_sign_in   boolean NOT NULL DEFAULT false,
    ADD COLUMN phone_sign_in_ticket uuid REFERENCES helpdesk.ticket (id) ON DELETE SET NULL;
COMMENT ON COLUMN people.student_contact.email_from_sign_in IS
  'V599: the e-mail was saved from a request on the sign-in page (V596); while it is also unconfirmed no notice goes to it (people.student_reach)';
COMMENT ON COLUMN people.student_contact.phone_from_sign_in IS
  'V599: the phone was saved from a request on the sign-in page (V596); while it is also unconfirmed no notice goes to it (people.student_reach)';
COMMENT ON COLUMN people.student_contact.email_sign_in_ticket IS 'V599: the sign-in help request that saved the e-mail';
COMMENT ON COLUMN people.student_contact.phone_sign_in_ticket IS 'V599: the sign-in help request that saved the phone';
CREATE INDEX ix_student_contact_sign_in ON people.student_contact (student_id)
    WHERE (email_pending AND email_from_sign_in) OR (phone_pending AND phone_from_sign_in);

-- the marks go with the value they marked: a value anyone else writes is neither unconfirmed (V575) nor the sign-in help's
CREATE OR REPLACE FUNCTION people.student_contact_pending_kept()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.email IS DISTINCT FROM OLD.email AND NOT (NEW.email_pending AND NOT OLD.email_pending) THEN
            NEW.email_pending := false;
        END IF;
        IF NEW.phone IS DISTINCT FROM OLD.phone AND NOT (NEW.phone_pending AND NOT OLD.phone_pending) THEN
            NEW.phone_pending := false;
        END IF;
        -- V599
        IF NEW.email IS DISTINCT FROM OLD.email AND NOT (NEW.email_from_sign_in AND NOT OLD.email_from_sign_in) THEN
            NEW.email_from_sign_in := false;
            NEW.email_sign_in_ticket := NULL;
        END IF;
        IF NEW.phone IS DISTINCT FROM OLD.phone AND NOT (NEW.phone_from_sign_in AND NOT OLD.phone_from_sign_in) THEN
            NEW.phone_from_sign_in := false;
            NEW.phone_sign_in_ticket := NULL;
        END IF;
    END IF;
    IF nullif(btrim(coalesce(NEW.email, '')), '') IS NULL THEN
        NEW.email_pending := false;
        NEW.email_from_sign_in := false;
        NEW.email_sign_in_ticket := NULL;
    END IF;
    IF nullif(btrim(coalesce(NEW.phone, '')), '') IS NULL THEN
        NEW.phone_pending := false;
        NEW.phone_from_sign_in := false;
        NEW.phone_sign_in_ticket := NULL;
    END IF;
    RETURN NEW;
END $fn$;

-- the contact saved as the sign-in help's, with the request that saved it (V596's text; the request named, a fourth argument
-- with a default so the three-argument call of the API being replaced still finds it)
DROP FUNCTION people.contact_from_sign_in(uuid, text, text);
CREATE FUNCTION people.contact_from_sign_in(p_student uuid, p_email text, p_phone text, p_ticket uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE c people.student_contact; v_email text := lower(btrim(coalesce(p_email, ''))); v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
        v_phone text; v_new_email text; v_new_phone text; v_saved text[] := ARRAY[]::text[];
BEGIN
    IF p_student IS NULL THEN
        RETURN '';
    END IF;
    -- the phone as the record keeps it: 0 and ten digits (+234 and 234 read as 0)
    v_phone := CASE WHEN v_digits ~ '^0[0-9]{10}$' THEN v_digits
                    WHEN v_digits ~ '^234[0-9]{10}$' THEN '0' || right(v_digits, 10)
                    WHEN v_digits ~ '^[1-9][0-9]{9}$' THEN '0' || v_digits END;
    IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := NULL; END IF;
    SELECT * INTO c FROM people.student_contact WHERE student_id = p_student FOR UPDATE;
    v_new_email := CASE WHEN v_email IS NOT NULL AND nullif(btrim(coalesce(c.email, '')), '') IS NULL THEN v_email END;
    v_new_phone := CASE WHEN v_phone IS NOT NULL AND nullif(btrim(coalesce(c.phone, '')), '') IS NULL THEN v_phone END;
    IF v_new_email IS NULL AND v_new_phone IS NULL THEN
        RETURN '';
    END IF;
    IF c.student_id IS NULL THEN
        INSERT INTO people.student_contact (student_id, email, email_pending, email_from_sign_in, email_sign_in_ticket,
                                            phone, phone_pending, phone_from_sign_in, phone_sign_in_ticket, updated_at)
        VALUES (p_student, v_new_email, v_new_email IS NOT NULL, v_new_email IS NOT NULL, CASE WHEN v_new_email IS NOT NULL THEN p_ticket END,
                v_new_phone, v_new_phone IS NOT NULL, v_new_phone IS NOT NULL, CASE WHEN v_new_phone IS NOT NULL THEN p_ticket END, now());
    ELSE
        UPDATE people.student_contact
           SET email = coalesce(v_new_email, email), email_pending = CASE WHEN v_new_email IS NOT NULL THEN true ELSE email_pending END,
               email_upload_id = CASE WHEN v_new_email IS NOT NULL THEN NULL ELSE email_upload_id END,
               email_from_sign_in = CASE WHEN v_new_email IS NOT NULL THEN true ELSE email_from_sign_in END,
               email_sign_in_ticket = CASE WHEN v_new_email IS NOT NULL THEN p_ticket ELSE email_sign_in_ticket END,
               phone = coalesce(v_new_phone, phone), phone_pending = CASE WHEN v_new_phone IS NOT NULL THEN true ELSE phone_pending END,
               phone_upload_id = CASE WHEN v_new_phone IS NOT NULL THEN NULL ELSE phone_upload_id END,
               phone_from_sign_in = CASE WHEN v_new_phone IS NOT NULL THEN true ELSE phone_from_sign_in END,
               phone_sign_in_ticket = CASE WHEN v_new_phone IS NOT NULL THEN p_ticket ELSE phone_sign_in_ticket END,
               updated_at = now()
         WHERE student_id = p_student;
    END IF;
    IF v_new_email IS NOT NULL THEN v_saved := array_append(v_saved, 'EMAIL'); END IF;
    IF v_new_phone IS NOT NULL THEN v_saved := array_append(v_saved, 'PHONE'); END IF;
    RETURN array_to_string(v_saved, ',');
END $fn$;
COMMENT ON FUNCTION people.contact_from_sign_in(uuid, text, text, uuid) IS
  'V596, V599: the e-mail and phone a sign-in help request gives, saved to a record that holds none — unconfirmed, marked as the sign-in help''s with the request, and reaching no notice until confirmed';

-- the address every notice reads: never a contact the sign-in help saved and nobody has confirmed (V599)
CREATE OR REPLACE FUNCTION people.student_reach(p_student uuid)
RETURNS TABLE (email text, phone text) LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(CASE WHEN c.email_pending AND c.email_from_sign_in THEN NULL ELSE c.email END, a.email),
           coalesce(CASE WHEN c.phone_pending AND c.phone_from_sign_in THEN NULL ELSE c.phone END, a.phone)
      FROM people.student s
      LEFT JOIN people.student_contact c ON c.student_id = s.id
      LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id
     WHERE s.id = p_student;
$fn$;
COMMENT ON FUNCTION people.student_reach(uuid) IS
  'The e-mail and phone the University reaches a student at: the record''s, else the applicant account''s; V599: never one the sign-in help saved that nobody has confirmed';

-- ── the desk's decisions ────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE people.contact_confirmation
    ADD COLUMN sign_in_ticket uuid REFERENCES helpdesk.ticket (id) ON DELETE SET NULL;
COMMENT ON COLUMN people.contact_confirmation.sign_in_ticket IS 'V599: the sign-in help request that saved the contact decided on';
ALTER TABLE people.contact_confirmation DROP CONSTRAINT contact_confirmation_outcome_check;
ALTER TABLE people.contact_confirmation ADD CONSTRAINT contact_confirmation_outcome_check
    CHECK (outcome IN ('CONFIRMED', 'REFUSED', 'DESK', 'DESK_REFUSED', 'EXPIRED', 'REPLACED'));

/* the request that saved an unconfirmed contact, or NULL */
CREATE FUNCTION people.contact_sign_in_ticket(p_student uuid, p_field text)
RETURNS uuid LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN upper(p_field) = 'EMAIL' THEN c.email_sign_in_ticket ELSE c.phone_sign_in_ticket END
      FROM people.student_contact c
     WHERE c.student_id = p_student
       AND CASE WHEN upper(p_field) = 'EMAIL' THEN c.email_pending AND c.email_from_sign_in ELSE c.phone_pending AND c.phone_from_sign_in END
$fn$;

-- V575's text, the request named on the outcome
CREATE OR REPLACE FUNCTION people.contact_confirm_desk(p_student uuid, p_field text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v record; v_field text := upper(coalesce(p_field, ''));
BEGIN
    SELECT * INTO v FROM people.contact_pending_value(p_student, v_field);
    IF v.value IS NULL THEN
        RAISE EXCEPTION 'CONTACT_NOT_PENDING: there is no unconfirmed contact of that kind on the record' USING ERRCODE = '23514';
    END IF;
    UPDATE people.contact_confirmation SET outcome = 'REPLACED', decided_at = now()
     WHERE student_id = p_student AND field = v_field AND outcome IS NULL;
    INSERT INTO people.contact_confirmation (student_id, field, value, upload_id, sign_in_ticket, outcome, decided_at, decided_by)
    VALUES (p_student, v_field, v.value, v.upload_id, people.contact_sign_in_ticket(p_student, v_field), 'DESK', now(),
            nullif(current_setting('moaum.actor_id', true), '')::uuid);
    IF v_field = 'EMAIL' THEN
        UPDATE people.student_contact SET email_pending = false, updated_at = now() WHERE student_id = p_student;
    ELSE
        UPDATE people.student_contact SET phone_pending = false, updated_at = now() WHERE student_id = p_student;
    END IF;
    RETURN 'DESK';
END $fn$;

/* the desk refuses an unconfirmed contact the student says is not theirs (or that came from someone else's request): the field
   emptied, the outcome kept, and a department that uploaded it told so the class list is put right (as V580 tells it of a
   student's own refusal) */
CREATE FUNCTION people.contact_refuse_desk(p_student uuid, p_field text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v record; v_field text := upper(coalesce(p_field, '')); v_id uuid; u record;
BEGIN
    IF v_field NOT IN ('EMAIL', 'PHONE') THEN
        RAISE EXCEPTION 'CONTACT_FIELD: the field is the e-mail or the phone' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v FROM people.contact_pending_value(p_student, v_field);
    IF v.value IS NULL THEN
        RAISE EXCEPTION 'CONTACT_NOT_PENDING: there is no unconfirmed contact of that kind on the record' USING ERRCODE = '23514';
    END IF;
    UPDATE people.contact_confirmation SET outcome = 'REPLACED', decided_at = now()
     WHERE student_id = p_student AND field = v_field AND outcome IS NULL;
    INSERT INTO people.contact_confirmation (student_id, field, value, upload_id, sign_in_ticket, outcome, decided_at, decided_by)
    VALUES (p_student, v_field, v.value, v.upload_id, people.contact_sign_in_ticket(p_student, v_field), 'DESK_REFUSED', now(),
            nullif(current_setting('moaum.actor_id', true), '')::uuid)
    RETURNING id INTO v_id;
    SELECT x.uploaded_by, x.file_name, x.uploaded_at, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS student,
           coalesce(s.matric_no, s.admission_no, s.jamb_reg_no) AS number
      INTO u FROM people.contact_upload x CROSS JOIN people.student s WHERE x.id = v.upload_id AND s.id = p_student;
    IF u.uploaded_by IS NOT NULL THEN
        PERFORM platform.tell_person(u.uploaded_by, 'CONTACT_UPLOAD_REJECTED', NULL, jsonb_build_object(
                    'STUDENT', u.student, 'NUMBER', coalesce(u.number, ''), 'FIELD', CASE v_field WHEN 'EMAIL' THEN 'e-mail address' ELSE 'phone number' END,
                    'VALUE', v.value, 'FILE', coalesce(u.file_name, 'without a file name'),
                    'UPLOADED', to_char(u.uploaded_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY')),
                'contact-rejected:' || v_id);
    END IF;
    IF v_field = 'EMAIL' THEN
        UPDATE people.student_contact SET email = NULL, updated_at = now() WHERE student_id = p_student;
    ELSE
        UPDATE people.student_contact SET phone = NULL, updated_at = now() WHERE student_id = p_student;
    END IF;
    RETURN 'DESK_REFUSED';
END $fn$;
COMMENT ON FUNCTION people.contact_refuse_desk(uuid, text) IS
  'V599: an unconfirmed contact refused at the ICT Support desk: emptied, kept as DESK_REFUSED, the uploading department told';

-- an upload's refusals count the desk's as well as the students' own (V575's text)
CREATE OR REPLACE FUNCTION people.contact_upload_outcomes(p_upload uuid)
RETURNS TABLE (waiting bigint, confirmed bigint, refused bigint) LANGUAGE sql STABLE AS $fn$
    SELECT (SELECT count(*) FILTER (WHERE c.email_pending AND c.email_upload_id = p_upload) + count(*) FILTER (WHERE c.phone_pending AND c.phone_upload_id = p_upload)
              FROM people.student_contact c WHERE c.email_upload_id = p_upload OR c.phone_upload_id = p_upload),
           (SELECT count(*) FROM people.contact_confirmation x WHERE x.upload_id = p_upload AND x.outcome IN ('CONFIRMED', 'DESK')),
           (SELECT count(*) FROM people.contact_confirmation x WHERE x.upload_id = p_upload AND x.outcome IN ('REFUSED', 'DESK_REFUSED'))
$fn$;

/* the unconfirmed contacts the sign-in help saved, within the agent's contact-editing scope (every one for a Head), newest
   request first, with who asked */
CREATE FUNCTION helpdesk.sign_in_contacts(p_agent uuid, p_head boolean)
RETURNS TABLE (student_id uuid, name text, number text, programme text, department text, faculty text, level integer, status text,
               field text, value text, ticket_id uuid, ticket_number text, ticket_status text, asked_by text, asked_email text, saved_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(p_agent, 'EDIT_CONTACT')),
    x AS (
        SELECT c.student_id, 'EMAIL'::text AS field, c.email AS value, c.email_sign_in_ticket AS ticket_id, c.updated_at
          FROM people.student_contact c WHERE c.email_pending AND c.email_from_sign_in
        UNION ALL
        SELECT c.student_id, 'PHONE', c.phone, c.phone_sign_in_ticket, c.updated_at
          FROM people.student_contact c WHERE c.phone_pending AND c.phone_from_sign_in)
    SELECT s.id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), coalesce(s.matric_no, s.admission_no),
           p.name, d.name, f.name, s.current_level, s.status,
           x.field, x.value, t.id, t.number, t.status, t.requester_name, t.requester_email, coalesce(t.created_at, x.updated_at)
      FROM x
      JOIN people.student s ON s.id = x.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN helpdesk.ticket t ON t.id = x.ticket_id
     WHERE p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments))
     ORDER BY coalesce(t.created_at, x.updated_at) DESC, s.surname, x.field
$fn$;
COMMENT ON FUNCTION helpdesk.sign_in_contacts(uuid, boolean) IS
  'V599: the unconfirmed e-mails and phones the sign-in help saved, within the agent''s EDIT_CONTACT scope, with the request and who asked';

-- ── the student numbers checked on the sign-in page ─────────────────────────────────────────────────────────────────────────
ALTER TABLE helpdesk.setting
    ADD COLUMN sign_in_lookups_daily integer DEFAULT 200,
    ADD COLUMN sign_in_lookups_alert integer DEFAULT 50,
    ADD CONSTRAINT ck_hd_setting_lookups_daily CHECK (sign_in_lookups_daily IS NULL OR sign_in_lookups_daily BETWEEN 1 AND 10000),
    ADD CONSTRAINT ck_hd_setting_lookups_alert CHECK (sign_in_lookups_alert IS NULL OR sign_in_lookups_alert BETWEEN 1 AND 10000);
COMMENT ON COLUMN helpdesk.setting.sign_in_lookups_daily IS
  'V599: the student numbers one connection may check on the sign-in page in a Lagos day; past it the check is refused until the next day. NULL: no daily figure (the fifteen-minute limit stands)';
COMMENT ON COLUMN helpdesk.setting.sign_in_lookups_alert IS
  'V599: the different student numbers one connection checks in a day at which the Head of the ICT Support Desk is told (once a connection a day). NULL: no one is told';

CREATE TABLE helpdesk.sign_in_lookup (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at         timestamptz NOT NULL DEFAULT now(),
    source     text NOT NULL,
    number     text NOT NULL,
    found      boolean NOT NULL,
    student_id uuid REFERENCES people.student (id) ON DELETE SET NULL
);
CREATE INDEX ix_sign_in_lookup_source ON helpdesk.sign_in_lookup (source, at DESC);
CREATE INDEX ix_sign_in_lookup_at ON helpdesk.sign_in_lookup (at);
COMMENT ON TABLE helpdesk.sign_in_lookup IS
  'V599: each student number checked on the sign-in page (V596: a number found names its student) — the connection''s address, the number as typed (upper case, no spaces), whether a student holds it; 180 days kept';
SELECT audit.exempt('helpdesk.sign_in_lookup',
  'the append-only log of student numbers checked on the sign-in page by people not signed in: no actor for the spine, and the log is itself the record of who checked what');

/* the day's figure the connection has reached — the check refused — or NULL while it may check */
CREATE FUNCTION helpdesk.sign_in_lookup_refused(p_source text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT g.sign_in_lookups_daily
      FROM helpdesk.setting g
     WHERE g.row_no AND g.sign_in_lookups_daily IS NOT NULL AND p_source IS NOT NULL
       AND (SELECT count(*) FROM helpdesk.sign_in_lookup l
             WHERE l.source = p_source AND l.at >= ((now() AT TIME ZONE 'Africa/Lagos')::date)::timestamp AT TIME ZONE 'Africa/Lagos') >= g.sign_in_lookups_daily
$fn$;

/* a check logged; the Head told once a day when the connection's different numbers reach the alert figure */
CREATE FUNCTION helpdesk.sign_in_lookup_record(p_source text, p_number text, p_found boolean, p_student uuid)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_day date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_from timestamptz; v_alert int; n_numbers int; n_found int; n_checks int;
        v_first timestamptz; v_key text; v_vars jsonb; p record; v_heads int := 0;
BEGIN
    IF p_source IS NULL THEN
        RETURN 0;
    END IF;
    v_from := v_day::timestamp AT TIME ZONE 'Africa/Lagos';
    INSERT INTO helpdesk.sign_in_lookup (source, number, found, student_id)
    VALUES (left(p_source, 64), left(upper(regexp_replace(coalesce(p_number, ''), '\s', '', 'g')), 60), coalesce(p_found, false), p_student);
    -- 180 days kept, a few hundred older ones cleared at a time
    DELETE FROM helpdesk.sign_in_lookup WHERE id IN (SELECT l.id FROM helpdesk.sign_in_lookup l WHERE l.at < now() - interval '180 days' LIMIT 500);
    SELECT g.sign_in_lookups_alert INTO v_alert FROM helpdesk.setting g WHERE g.row_no;
    IF v_alert IS NULL THEN
        RETURN 0;
    END IF;
    v_key := 'sign-in-lookups:' || left(p_source, 64) || ':' || v_day;
    IF EXISTS (SELECT 1 FROM platform.notice x WHERE x.event_key = v_key) THEN
        RETURN 0;
    END IF;
    SELECT count(DISTINCT l.number), count(DISTINCT l.number) FILTER (WHERE l.found), count(*), min(l.at)
      INTO n_numbers, n_found, n_checks, v_first
      FROM helpdesk.sign_in_lookup l WHERE l.source = left(p_source, 64) AND l.at >= v_from;
    IF n_numbers < v_alert THEN
        RETURN 0;
    END IF;
    v_vars := jsonb_build_object('SOURCE', left(p_source, 64), 'NUMBERS', n_numbers::text, 'FOUND', n_found::text, 'CHECKS', n_checks::text,
                                 'FIRST', to_char(v_first AT TIME ZONE 'Africa/Lagos', 'HH24:MI'), 'DAY', to_char(v_day, 'FMDD FMMonth YYYY'));
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code = 'helpdeskhead' AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day) LOOP
        v_heads := v_heads + platform.tell_person(p.person_id, 'SIGN_IN_LOOKUP_ALERT', NULL, v_vars, v_key);
    END LOOP;
    IF v_heads = 0 THEN
        FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
                  WHERE oa.office_code = 'ict' AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day) LOOP
            v_heads := v_heads + platform.tell_person(p.person_id, 'SIGN_IN_LOOKUP_ALERT', NULL, v_vars, v_key);
        END LOOP;
    END IF;
    RETURN v_heads;
END $fn$;

/* a Lagos day's checks by connection: how many, how many different numbers, how many of them a student holds, the first and the
   last, whether the Head was told and whether the connection reached the day's figure */
CREATE FUNCTION helpdesk.sign_in_lookups_by_source(p_day date)
RETURNS TABLE (source text, checks bigint, numbers bigint, found bigint, first_at timestamptz, last_at timestamptz, told boolean, refused boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT l.source, count(*), count(DISTINCT l.number), count(DISTINCT l.number) FILTER (WHERE l.found), min(l.at), max(l.at),
           EXISTS (SELECT 1 FROM platform.notice x WHERE x.event_key = 'sign-in-lookups:' || l.source || ':' || p_day),
           coalesce((SELECT g.sign_in_lookups_daily FROM helpdesk.setting g WHERE g.row_no) <= count(*), false)
      FROM helpdesk.sign_in_lookup l
     WHERE l.at >= p_day::timestamp AT TIME ZONE 'Africa/Lagos' AND l.at < (p_day + 1)::timestamp AT TIME ZONE 'Africa/Lagos'
     GROUP BY l.source
     ORDER BY count(DISTINCT l.number) DESC, count(*) DESC, l.source
$fn$;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('SIGN_IN_LOOKUP_ALERT', 'Many student numbers checked from one connection',
 'To the Head of the ICT Support Desk when one connection checks the figure set on Sign-In Help Contacts of different student numbers on the sign-in page in a day',
 '[NUMBERS] student numbers checked from one connection today',
 E'Dear [FIRST_NAME],\n\nThe connection [SOURCE] has checked [NUMBERS] different student numbers on the sign-in help page today ([DAY]), since [FIRST]; [FOUND] of them are students'' numbers, and each of those showed the student''s name. That is the figure set on Sign-In Help Contacts for this notice ([CHECKS] checks in all).\n\nA University network shares one address among many students; a connection stepping through numbers is someone collecting names. The day''s checks by connection are on Sign-In Help Contacts: [PORTAL_URL]\n\nMOAUM Portal',
 NULL,
 'Many student numbers checked from [SOURCE]',
 '[SOURCE] has checked [NUMBERS] different student numbers on the sign-in page today ([DAY]); [FOUND] of them are students'' numbers.',
 ARRAY['FIRST_NAME','SOURCE','NUMBERS','FOUND','CHECKS','FIRST','DAY','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH');

-- ── the contacts saved since V596, marked with their request ────────────────────────────────────────────────────────────────
WITH saved AS (
    SELECT DISTINCT ON ((e.after_state->>'student_id')::uuid, f.field) (e.after_state->>'student_id')::uuid AS student_id, f.field,
           e.after_state->>lower(f.field) AS value, e.occurred_at
      FROM audit.entries e
      CROSS JOIN (VALUES ('EMAIL'), ('PHONE')) f (field)
     WHERE e.occurred_at >= timestamptz '2026-10-20 00:00+01' AND e.subject_type = 'people.student_contact'
       AND e.reason = 'sign-in help asked from the sign-in page'
       AND nullif(btrim(coalesce(e.after_state->>lower(f.field), '')), '') IS NOT NULL
       AND nullif(btrim(coalesce(e.before_state->>lower(f.field), '')), '') IS NULL
     ORDER BY (e.after_state->>'student_id')::uuid, f.field, e.occurred_at DESC),
marked AS (
    SELECT sv.*, (SELECT t.id FROM helpdesk.ticket t
                   WHERE t.requester_kind = 'PUBLIC' AND t.created_at BETWEEN sv.occurred_at - interval '2 minutes' AND sv.occurred_at + interval '1 second'
                     AND helpdesk.ticket_student(t.requester_kind, t.requester_id, t.requester_number, t.details) = sv.student_id
                   ORDER BY t.created_at DESC LIMIT 1) AS ticket_id
      FROM saved sv)
UPDATE people.student_contact c
   SET email_from_sign_in = CASE WHEN EXISTS (SELECT 1 FROM marked m WHERE m.student_id = c.student_id AND m.field = 'EMAIL' AND m.value = c.email) THEN true ELSE c.email_from_sign_in END,
       email_sign_in_ticket = coalesce((SELECT m.ticket_id FROM marked m WHERE m.student_id = c.student_id AND m.field = 'EMAIL' AND m.value = c.email), c.email_sign_in_ticket),
       phone_from_sign_in = CASE WHEN EXISTS (SELECT 1 FROM marked m WHERE m.student_id = c.student_id AND m.field = 'PHONE' AND m.value = c.phone) THEN true ELSE c.phone_from_sign_in END,
       phone_sign_in_ticket = coalesce((SELECT m.ticket_id FROM marked m WHERE m.student_id = c.student_id AND m.field = 'PHONE' AND m.value = c.phone), c.phone_sign_in_ticket)
 WHERE c.student_id IN (SELECT m.student_id FROM marked m);

COMMIT;
