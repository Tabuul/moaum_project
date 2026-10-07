-- ═══════════════════════════════════════════════════════════════════════════
-- V345 — JUPEB: the students already registered on the old portal, uploaded with their logins
--
--   The JUPEB Office uploads the old portal's export (App No, names, sex, LGA, phone, state, date of birth, NIN, email; a
--   programme and a combination where the file has them). Every row is judged first and nothing is written on a preview:
--     · App No, surname, first name and a valid email are required; the App No and the email each once in the file; an
--       email another JUPEB account already holds is refused; such a row is skipped and listed for correction;
--     · a student already on the portal (the same App No) is skipped — the same file uploaded again adds nothing twice;
--     · a phone, NIN, sex or date of birth that cannot be read is left blank and said, the row still imported.
--   On the upload each importable row becomes a JUPEB account and a student record of the session chosen, with the old App
--   No as the application number (the student signs in with it, or the email) and the old portal named as its source. The
--   API hashes a temporary password for each (never stored readable, never emailed); the account must change it at first
--   sign-in. Nothing is announced to the student while the records are written; the API then emails each a link to set a
--   password, when the office asks. Fees paid on the old portal are not known here: no fee reminder goes to these students.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V345: JUPEB students from the old portal', true);

ALTER TABLE jupeb.account ADD COLUMN must_change_password boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN jupeb.account.must_change_password IS 'V345: the account signed in with a temporary password the JUPEB Office handed out; the portal asks for a new one first';

ALTER TABLE jupeb.application ADD COLUMN legacy_source text NULL CHECK (legacy_source IS NULL OR legacy_source = 'OLD_PORTAL');
ALTER TABLE jupeb.application ADD COLUMN legacy_ref text NULL;
ALTER TABLE jupeb.application ADD COLUMN legacy_batch text NULL;
CREATE UNIQUE INDEX ux_jupeb_app_legacy_ref ON jupeb.application (upper(legacy_ref)) WHERE legacy_ref IS NOT NULL;
COMMENT ON COLUMN jupeb.application.legacy_source IS 'V345: OLD_PORTAL for a student uploaded from the old portal''s register (legacy_ref: the old App No; legacy_batch: the upload)';

ALTER TABLE jupeb.import_batch DROP CONSTRAINT import_batch_kind_check;
ALTER TABLE jupeb.import_batch ADD CONSTRAINT import_batch_kind_check CHECK (kind IN ('EXAM_NUMBERS', 'RESULTS', 'COMBINATIONS', 'OLD_PORTAL_STUDENTS'));

CREATE OR REPLACE FUNCTION jupeb.batch_ref(p_kind text)
RETURNS text LANGUAGE sql AS $$
    SELECT 'JUPEB-' || CASE p_kind WHEN 'EXAM_NUMBERS' THEN 'EXAMNO' WHEN 'RESULTS' THEN 'RESULT' WHEN 'OLD_PORTAL_STUDENTS' THEN 'OLDPORTAL' ELSE 'COMB' END || '-'
           || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('JUPEB_' || p_kind, 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0')
$$;

/* V339's, holding its tongue while the records of an upload are written (moaum.jupeb_quiet), so a student is not told to pay
   an application fee for an application made on the old portal */
CREATE OR REPLACE FUNCTION jupeb.tell(p_app uuid, p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application;
BEGIN
    IF coalesce(current_setting('moaum.jupeb_quiet', true), '') = 'on' THEN RETURN; END IF;
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN; END IF;
    PERFORM platform.queue_notice('EMAIL', a.email, p_subject,
        'Dear ' || a.first_name || ',' || E'\n\n' || p_body || E'\n\n' || 'Application number: ' || a.application_no || E'\n'
        || 'JUPEB Office, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'jupeb_application', p_app);
    IF a.phone IS NOT NULL THEN
        PERFORM platform.queue_notice('SMS', a.phone, p_subject, 'MOAUM JUPEB ' || a.application_no || ': ' || p_subject || '. Sign in to the JUPEB portal for details.', 'jupeb_application', p_app);
    END IF;
END $$;

/* a date as the old portal wrote it: an Excel day number, an ISO date, or day/month/year (month/day/year when p_dmy is false,
   and whichever the numbers allow when one part exceeds 12); NULL when it cannot be read */
CREATE OR REPLACE FUNCTION jupeb.legacy_date(p text, p_dmy boolean)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s text := btrim(coalesce(p, '')); m text[]; d int; mo int; y int;
BEGIN
    IF s = '' THEN RETURN NULL; END IF;
    IF s ~ '^[0-9]{5}(\.[0-9]+)?$' THEN RETURN date '1899-12-30' + floor(s::numeric)::int; END IF;
    IF s ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}' THEN
        BEGIN RETURN substr(s, 1, 10)::date; EXCEPTION WHEN others THEN RETURN NULL; END;
    END IF;
    m := regexp_match(s, '^([0-9]{1,2})[/.\-]([0-9]{1,2})[/.\-]([0-9]{2}|[0-9]{4})$');
    IF m IS NULL THEN RETURN NULL; END IF;
    y := m[3]::int;
    IF y < 100 THEN y := y + CASE WHEN y > 30 THEN 1900 ELSE 2000 END; END IF;
    IF m[1]::int > 12 THEN d := m[1]::int; mo := m[2]::int;
    ELSIF m[2]::int > 12 THEN mo := m[1]::int; d := m[2]::int;
    ELSIF p_dmy THEN d := m[1]::int; mo := m[2]::int;
    ELSE mo := m[1]::int; d := m[2]::int;
    END IF;
    BEGIN RETURN make_date(y, mo, d); EXCEPTION WHEN others THEN RETURN NULL; END;
END $$;

/* a Nigerian mobile number as the portal keeps it: 0 and ten digits (7052428202, 2347052428202 and +234 705… all read) */
CREATE OR REPLACE FUNCTION jupeb.legacy_phone(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN d ~ '^0[0-9]{10}$' THEN d WHEN d ~ '^[789][0-9]{9}$' THEN '0' || d WHEN d ~ '^234[789][0-9]{9}$' THEN '0' || substr(d, 4) END
      FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) x
$$;

/* the upload: judged row by row; on p_commit (with a password hash on each row the API judged importable) the accounts and
   records are written quietly and the batch is kept. Returns the judgement of every row and, on commit, each new record */
CREATE OR REPLACE FUNCTION jupeb.import_old_portal_students(p_rows jsonb, p_session text, p_dmy boolean, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; v_status text; v_notes text[]; v_app text; v_email text; v_sur text; v_first text; v_mid text;
        v_phone text; v_nin text; v_sex text; v_dob date; v_state text; v_lga text; v_stream text; v_comb uuid; v_comb_code text;
        n_valid int := 0; n_review int := 0; n_invalid int := 0; n_exists int := 0; n_applied int := 0; v_ref text; v_acc uuid; v_id uuid; v_created jsonb := '[]'::jsonb;
        seen_app text[] := '{}'; seen_email text[] := '{}';
BEGIN
    IF p_session IS NULL OR p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'JUPEB_SESSION: choose the session the students are in' USING ERRCODE = '23514';
    END IF;
    IF p_commit THEN
        v_ref := jupeb.batch_ref('OLD_PORTAL_STUDENTS');
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
    END IF;
    FOR r IN SELECT x FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x LOOP
        v_notes := '{}'; v_status := 'VALID';
        v_app := nullif(upper(regexp_replace(btrim(coalesce(r->>'appNo', '')), '\s+', '', 'g')), '');
        v_email := nullif(lower(btrim(coalesce(r->>'email', ''))), '');
        v_sur := nullif(initcap(btrim(coalesce(r->>'surname', ''))), '');
        v_first := nullif(initcap(btrim(coalesce(r->>'firstName', ''))), '');
        v_mid := nullif(initcap(btrim(coalesce(r->>'middleName', ''))), '');
        v_sex := CASE upper(left(btrim(coalesce(r->>'sex', '')), 1)) WHEN 'F' THEN 'F' WHEN 'M' THEN 'M' END;
        IF v_sex IS NULL AND btrim(coalesce(r->>'sex', '')) <> '' THEN v_notes := v_notes || ('sex "' || (r->>'sex') || '" not read'); END IF;
        v_phone := jupeb.legacy_phone(r->>'phone');
        IF v_phone IS NULL AND btrim(coalesce(r->>'phone', '')) <> '' THEN v_notes := v_notes || ('phone "' || (r->>'phone') || '" not read'); END IF;
        v_nin := nullif(regexp_replace(coalesce(r->>'nin', ''), '[^0-9]', '', 'g'), '');
        IF v_nin IS NOT NULL AND v_nin !~ '^[0-9]{11}$' THEN v_notes := v_notes || ('NIN "' || (r->>'nin') || '" is not eleven digits'); v_nin := NULL; END IF;
        v_dob := jupeb.legacy_date(r->>'dob', coalesce(p_dmy, true));
        IF v_dob IS NOT NULL AND (v_dob > current_date - interval '10 years' OR v_dob < current_date - interval '70 years') THEN
            v_notes := v_notes || ('date of birth ' || to_char(v_dob, 'DD Mon YYYY') || ' is not likely'); v_dob := NULL;
        ELSIF v_dob IS NULL AND btrim(coalesce(r->>'dob', '')) <> '' THEN
            v_notes := v_notes || ('date of birth "' || (r->>'dob') || '" not read');
        END IF;
        v_state := nullif(initcap(btrim(coalesce(r->>'state', ''))), '');
        v_lga := nullif(initcap(btrim(coalesce(r->>'lga', ''))), '');
        v_stream := CASE upper(regexp_replace(btrim(coalesce(r->>'programme', '')), '[- ]', '_', 'g'))
                        WHEN 'SCIENCE' THEN 'SCIENCE' WHEN 'NON_SCIENCE' THEN 'NON_SCIENCE' WHEN 'ARTS' THEN 'NON_SCIENCE' END;
        v_comb := NULL; v_comb_code := NULL;
        IF nullif(btrim(coalesce(r->>'combination', '')), '') IS NOT NULL THEN
            SELECT c.id, c.code INTO v_comb, v_comb_code FROM jupeb.combination c WHERE upper(c.code) = upper(btrim(r->>'combination'));
            IF v_comb IS NULL THEN v_notes := v_notes || ('combination "' || (r->>'combination') || '" is not on the catalogue'); END IF;
        END IF;

        IF v_app IS NULL THEN v_status := 'INVALID'; v_notes := ARRAY['the App No is missing'];
        ELSIF v_app = ANY (seen_app) THEN v_status := 'INVALID'; v_notes := ARRAY['the App No ' || v_app || ' is twice in the file'];
        ELSIF EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.application_no) = v_app OR upper(x.legacy_ref) = v_app) THEN
            v_status := 'EXISTS'; v_notes := ARRAY['already on the portal — skipped'];
        ELSIF v_sur IS NULL OR v_first IS NULL THEN v_status := 'INVALID'; v_notes := ARRAY['the surname and first name are required'];
        ELSIF v_email IS NULL OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
            v_status := 'INVALID'; v_notes := ARRAY['the email "' || coalesce(r->>'email', '') || '" is not valid — correct it in the file'];
        ELSIF v_email = ANY (seen_email) THEN v_status := 'INVALID'; v_notes := ARRAY['the email ' || v_email || ' is twice in the file'];
        ELSIF EXISTS (SELECT 1 FROM jupeb.account x WHERE lower(x.email) = v_email) THEN
            v_status := 'INVALID'; v_notes := ARRAY['the email ' || v_email || ' already has a JUPEB account'];
        ELSIF cardinality(v_notes) > 0 THEN v_status := 'REVIEW';
        END IF;
        IF v_app IS NOT NULL THEN seen_app := seen_app || v_app; END IF;
        IF v_email IS NOT NULL THEN seen_email := seen_email || v_email; END IF;

        IF v_status = 'VALID' THEN n_valid := n_valid + 1; ELSIF v_status = 'REVIEW' THEN n_review := n_review + 1;
        ELSIF v_status = 'EXISTS' THEN n_exists := n_exists + 1; ELSE n_invalid := n_invalid + 1; END IF;

        v_id := NULL;
        IF p_commit AND v_status IN ('VALID', 'REVIEW') THEN
            IF coalesce(r->>'passwordHash', '') !~ '^\$2[aby]?\$12\$' THEN
                RAISE EXCEPTION 'JUPEB_IMPORT_PASSWORD: row % has no temporary password', r->>'row' USING ERRCODE = '23514';
            END IF;
            INSERT INTO jupeb.account (email, password_hash, must_change_password) VALUES (v_email, r->>'passwordHash', true) RETURNING id INTO v_acc;
            INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, middle_name, sex, date_of_birth, nin, email, phone,
                                           nationality, state_of_origin, lga, stream, combination_id, state, fee_confirmed_at, submitted_at, activated_at,
                                           legacy_source, legacy_ref, legacy_batch)
            VALUES (v_acc, p_session, v_app, upper(v_sur), v_first, v_mid, v_sex, v_dob, v_nin, v_email, v_phone,
                    CASE WHEN v_state IS NOT NULL THEN 'Nigerian' END, v_state, v_lga, v_stream, v_comb, 'STUDENT', now(), now(), now(),
                    'OLD_PORTAL', v_app, v_ref)
            RETURNING id INTO v_id;
            PERFORM jupeb.app_event(v_id, 'IMPORTED', 'Registered on the old portal as ' || v_app || '; uploaded in ' || v_ref);
            n_applied := n_applied + 1;
            v_created := v_created || jsonb_build_object('row', r->'row', 'applicationId', v_id, 'applicationNo', v_app, 'email', v_email,
                                                         'name', upper(v_sur) || ', ' || v_first || coalesce(' ' || v_mid, ''));
        END IF;
        v_out := v_out || jsonb_build_object('row', r->'row', 'status', v_status, 'message', array_to_string(v_notes, '; '),
            'appNo', v_app, 'name', coalesce(upper(v_sur), '') || ', ' || coalesce(v_first, '') || coalesce(' ' || v_mid, ''), 'email', v_email,
            'sex', v_sex, 'phone', v_phone, 'nin', v_nin, 'dob', v_dob, 'state', v_state, 'lga', v_lga, 'programme', v_stream, 'combination', v_comb_code,
            'applicationId', v_id);
    END LOOP;
    IF p_commit THEN
        PERFORM set_config('moaum.jupeb_quiet', 'off', true);
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'OLD_PORTAL_STUDENTS', p_file, jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), n_applied,
                jsonb_build_object('valid', n_valid, 'review', n_review, 'invalid', n_invalid, 'exists', n_exists, 'session', p_session),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'valid', n_valid, 'review', n_review, 'invalid', n_invalid, 'exists', n_exists,
                              'committed', p_commit, 'ref', v_ref, 'applied', n_applied, 'created', v_created);
END $$;

/* V344's due list, sparing the students uploaded from the old portal every fee reminder (what they paid there is not known here) */
CREATE OR REPLACE FUNCTION jupeb.reminder_exempt(p_app uuid, p_kind text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_kind IN ('FEE_UNPAID', 'SUBMIT_PENDING', 'CHECKING_OPEN', 'ACCEPTANCE_UNPAID', 'SCHOOL_FEE_UNPAID')
       AND EXISTS (SELECT 1 FROM jupeb.application a WHERE a.id = p_app AND a.legacy_source IS NOT NULL)
$$;

CREATE OR REPLACE FUNCTION jupeb.due_reminders(p_now timestamptz, p_kind text DEFAULT NULL)
RETURNS TABLE (application_id uuid, application_no text, name text, kind text, sent_before int, last_sent timestamptz, detail jsonb)
LANGUAGE sql STABLE AS $$
    WITH a AS (
        SELECT x.id, x.state, x.session, x.created_at, x.fee_confirmed_at, x.returned_at, x.submitted_at, x.activated_at, x.screening_state,
               w.state AS app_window, w.closes_at AS app_closes, ck.valid, ck.window_open AS chk_open, ck.paid AS chk_paid, ck.paid_at AS chk_paid_at,
               ck.may_check, ck.status AS adm_status, jupeb.paid_at(x.id, 'ACCEPTANCE') AS acc_at
          FROM jupeb.application x
          CROSS JOIN LATERAL policy.window_state('JUPEB_APPLICATION', x.session, NULL) w
          CROSS JOIN LATERAL jupeb.status_checking(x.id) ck
         WHERE x.state IN ('DRAFT', 'RETURNED', 'SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'STUDENT')
    ), cand AS (
        SELECT a.id, 'FEE_UNPAID'::text AS kind, a.created_at AS anchor, jsonb_build_object('closes', a.app_closes) AS detail
          FROM a WHERE a.state = 'DRAFT' AND a.fee_confirmed_at IS NULL AND a.app_window = 'OPEN'
        UNION ALL
        SELECT a.id, 'SUBMIT_PENDING', greatest(a.fee_confirmed_at, coalesce(a.returned_at, a.fee_confirmed_at)), jsonb_build_object('closes', a.app_closes, 'returned', a.state = 'RETURNED')
          FROM a WHERE a.state IN ('DRAFT', 'RETURNED') AND a.fee_confirmed_at IS NOT NULL AND a.app_window = 'OPEN'
        UNION ALL
        SELECT a.id, 'PASSPORT_MISSING', a.created_at, jsonb_build_object('closes', a.app_closes)
          FROM a WHERE a.state IN ('DRAFT', 'RETURNED') AND a.app_window = 'OPEN'
           AND NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED'))
        UNION ALL
        SELECT a.id, 'CHECKING_OPEN', a.submitted_at, '{}'::jsonb
          FROM a WHERE a.valid AND a.chk_open AND NOT a.chk_paid AND a.state NOT IN ('STUDENT')
        UNION ALL
        SELECT a.id, 'ACCEPTANCE_UNPAID', a.chk_paid_at, '{}'::jsonb
          FROM a WHERE a.state = 'ADMITTED' AND a.may_check AND a.adm_status = 'ADMITTED' AND a.acc_at IS NULL
        UNION ALL
        SELECT a.id, 'SCHOOL_FEE_UNPAID', a.acc_at, jsonb_build_object('first', true)
          FROM a WHERE a.state = 'ADMITTED' AND a.acc_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.application_id = a.id AND f.kind LIKE 'SCHOOL%' AND f.confirmed_at IS NOT NULL)
           AND (NOT (jupeb.setting_of(a.session)).screening_required OR a.screening_state = 'CLEARED')
        UNION ALL
        SELECT a.id, 'SCHOOL_FEE_UNPAID', a.activated_at, jsonb_build_object('first', false, 'outstanding', sf.outstanding)
          FROM a CROSS JOIN LATERAL jupeb.school_fees(a.id) sf WHERE a.state = 'STUDENT' AND sf.outstanding > 0
        UNION ALL
        /* V344: below the attendance minimum in a subject, once enough classes are counted */
        SELECT a.id, 'ATTENDANCE_LOW', coalesce(a.activated_at, a.submitted_at, a.created_at), '{}'::jsonb
          FROM a WHERE a.state = 'STUDENT' AND EXISTS (SELECT 1 FROM attendance.member_summary('JUPEB', a.id, a.session) m WHERE m.warnable)
    ), due AS (
        SELECT DISTINCT ON (c.id) c.id, c.kind, c.detail, s.n, s.last
          FROM cand c
          JOIN jupeb.reminder_rule r ON r.kind = c.kind AND r.enabled
          CROSS JOIN LATERAL (SELECT count(*)::int AS n, max(l.sent_at) AS last FROM jupeb.reminder_log l WHERE l.application_id = c.id AND l.kind = c.kind) s
         WHERE (p_kind IS NULL OR c.kind = p_kind)
           AND NOT jupeb.reminder_exempt(c.id, c.kind)
           AND c.anchor IS NOT NULL AND c.anchor + make_interval(days => r.first_after_days) <= p_now
           AND s.n < r.max_count AND (s.last IS NULL OR s.last + make_interval(days => r.every_days) <= p_now)
           AND NOT EXISTS (SELECT 1 FROM jupeb.reminder_log l WHERE l.application_id = c.id AND l.sent_at > p_now - interval '20 hours')
         ORDER BY c.id, r.ord
    )
    SELECT d.id, x.application_no, x.surname || ', ' || x.first_name || coalesce(' ' || x.middle_name, ''), d.kind, d.n, d.last, d.detail
      FROM due d JOIN jupeb.application x ON x.id = d.id
     ORDER BY x.application_no
$$;

/* V343's registration, the programme taken from the combination where none is recorded (the old portal's students) */
CREATE OR REPLACE FUNCTION jupeb.register_subjects(p_app uuid, p_actor uuid, p_combination uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.combination; n int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('STUDENT') THEN RAISE EXCEPTION 'JUPEB_NOT_STUDENT: subjects are registered by an active JUPEB student' USING ERRCODE = '23514',
        HINT = 'Pay the school fee the Bursary requires for activation first.'; END IF;
    IF a.subjects_registered_at IS NOT NULL THEN RETURN 0; END IF;
    SELECT * INTO c FROM jupeb.combination WHERE id = coalesce(p_combination, a.combination_id);
    IF c.id IS NULL THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION_CHOOSE: choose your subject combination to register' USING ERRCODE = '23514';
    END IF;
    IF NOT jupeb.combination_offered(c.id) THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION: % is not offered: choose one of the subject combinations the University offers', c.code USING ERRCODE = '23514';
    END IF;
    IF NOT jupeb.combination_suits(c.area, a.stream) THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a combination for % students', c.code, CASE a.stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
    END IF;
    /* V345: a student from the old portal has no programme recorded: the combination they register decides it */
    UPDATE jupeb.application SET combination_id = c.id,
           stream = coalesce(stream, CASE WHEN c.area IN ('Science', 'Engineering') THEN 'SCIENCE' WHEN c.area IS NOT NULL THEN 'NON_SCIENCE' END)
     WHERE id = p_app AND (combination_id IS DISTINCT FROM c.id OR stream IS NULL);
    INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
    SELECT p_app, s, a.session, p_actor FROM unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s
    ON CONFLICT (application_id, subject_id) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE jupeb.application SET subjects_registered_at = now() WHERE id = p_app;
    RETURN n;
END $$;

COMMIT;
