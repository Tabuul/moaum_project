-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V715 · Postgraduate record management: the School of Postgraduate Studies and the Director of ICT search, open and correct
--         postgraduate applicant and student records from one place
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompt of 30 October 2026, "PG APPLICANT & PG STUDENT FULL EDIT MANAGEMENT": one search over
--  postgraduate applicants and students; a full edit page for each; the School (pgschool, pgsecretary) and the Director of ICT
--  (ict) authorised, under explicit permissions; every change validated, confirmed with a reason, written in one transaction,
--  kept with its old and new value, and read everywhere the record is read. Nothing rebuilt: the student edit page (V642), the
--  programme swap (V578/V633), the matriculation correction (V579), the stages and cycles desk (V651), the screening and the
--  decisions (V337), the finance workflows and the notices stay the owners of what they own.
--
--  1 · admissions.pg_edit_grant: what each office may do on the postgraduate record pages. EDIT_PG_RECORD is the major permission
--      and carries the ordinary ones; the sensitive ones (an admission decision, a matriculation number, a financial record, a
--      published result, graduation) are never carried — each is its own workflow's, and only granted apart. pgschool, pgsecretary,
--      ict and super hold EDIT_PG_RECORD; pgschool EDIT_PG_ADMISSION_DECISION (it decides already); the Academic Office, the Registry,
--      Records, Audit and the platform administration read the history.
--  2 · A postgraduate student's record is corrected on the student edit page (V642), which already holds the identity, admission,
--      placement (the swap), status, matriculation (the correction), registration, graduation, finance and history of any
--      student. people.student_edit_permissions(office, student) and student_edit_may(office, permission, student): for a
--      postgraduate student, an office holding EDIT_PG_STUDENT holds the page's ordinary permissions — never the matriculation
--      number, graduation, the level desk (a postgraduate's level is a stage, the stages desk's, V651) or the registration override.
--      people.student_edit_apply reads them for the student it corrects.
--  3 · The applicant's record is corrected here (admissions.pg_applicant_edit_apply): the identity and contacts of
--      admissions.pg_applicant, the programme, specialisation, session and previous education of admissions.pg_application —
--      each field checked (the permission, the value, its uniqueness, the application's state), then all written or none; the
--      version read must be the record's own (PG_EDIT_STALE); a reason of fifteen characters and three words (the student edit's
--      rule); a critical change (the e-mail the applicant signs in with, the programme, the session) confirmed. An application on
--      the register is the student's record: its names and placement are corrected on the student edit page (PG_EDIT_ON_REGISTER);
--      the programme is corrected before the School's decision, afterwards by the swap once on the register (PG_EDIT_DECIDED); the
--      session not after a fee was paid for it (PG_EDIT_SESSION_PAID). The application number never changes. Every change is a row
--      on admissions.pg_applicant_edit (PG-EDIT/YYYY/NNNNNN, kept: never updated or deleted) and an event on the application's
--      history (RECORD_CORRECTED). admissions.pg_prior_degrees_set replaces the previous degrees as one change.
--  4 · admissions.pg_record_search: applicants and students in one list, read on the server — by application number (this portal's
--      or the old portal's), matriculation, admission or JAMB number, e-mail, phone or name; narrowed by faculty, department,
--      programme, session, kind, state and award. admissions.pg_edit_recent: the latest corrections, applicants' and students'.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V715: postgraduate record management for the School and the Director of ICT (the University''s master prompt of 30 October 2026)', true);

CREATE FUNCTION pg_temp.v715_swap(p_text text, p_old text, p_new text, p_times integer) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE n integer := (length(p_text) - length(replace(p_text, p_old, ''))) / length(p_old);
BEGIN
    IF n <> p_times THEN
        RAISE EXCEPTION 'V715: "%" found % time(s), expected %', left(p_old, 90), n, p_times;
    END IF;
    RETURN replace(p_text, p_old, p_new);
END $fn$;

-- ── 1 · who may do what on the postgraduate record pages ──
CREATE TABLE admissions.pg_edit_grant (
    office_code text NOT NULL,
    permission  text NOT NULL CHECK (permission IN (
        'EDIT_PG_RECORD', 'VIEW_PG_APPLICANTS', 'VIEW_PG_STUDENTS', 'EDIT_PG_APPLICANT', 'EDIT_PG_STUDENT', 'EDIT_PG_BIODATA',
        'EDIT_PG_ADMISSION', 'EDIT_PG_PROGRAMME', 'EDIT_PG_ACADEMIC_PLACEMENT', 'EDIT_PG_STAGE', 'EDIT_PG_STATUS', 'EDIT_PG_DOCUMENTS',
        'VIEW_PG_CHANGE_HISTORY', 'EXPORT_PG_RECORDS',
        'EDIT_PG_ADMISSION_DECISION', 'EDIT_PG_MATRICULATION', 'EDIT_PG_FINANCIAL_RECORD', 'EDIT_PG_PUBLISHED_RESULT', 'EDIT_PG_GRADUATION')),
    granted_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (office_code, permission)
);
SELECT audit.attach('admissions.pg_edit_grant');
COMMENT ON TABLE admissions.pg_edit_grant IS
  'V715: what each office may do on the postgraduate record pages. EDIT_PG_RECORD is the major permission and carries the ordinary ones; the sensitive ones (EDIT_PG_ADMISSION_DECISION, EDIT_PG_MATRICULATION, EDIT_PG_FINANCIAL_RECORD, EDIT_PG_PUBLISHED_RESULT, EDIT_PG_GRADUATION) are each their own workflow''s and only ever granted apart.';

INSERT INTO admissions.pg_edit_grant (office_code, permission) VALUES
    ('pgschool', 'EDIT_PG_RECORD'), ('pgsecretary', 'EDIT_PG_RECORD'), ('ict', 'EDIT_PG_RECORD'), ('super', 'EDIT_PG_RECORD'),
    ('pgschool', 'EDIT_PG_ADMISSION_DECISION'), ('super', 'EDIT_PG_ADMISSION_DECISION'),
    ('academic', 'VIEW_PG_CHANGE_HISTORY'), ('registrar', 'VIEW_PG_CHANGE_HISTORY'), ('dregistrar', 'VIEW_PG_CHANGE_HISTORY'),
    ('records', 'VIEW_PG_CHANGE_HISTORY'), ('admin', 'VIEW_PG_CHANGE_HISTORY'), ('audit', 'VIEW_PG_CHANGE_HISTORY'), ('deputyaudit', 'VIEW_PG_CHANGE_HISTORY')
ON CONFLICT DO NOTHING;

CREATE FUNCTION admissions.pg_edit_permissions(p_office text) RETURNS text[] LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM admissions.pg_edit_grant g WHERE g.office_code = p_office AND g.permission = 'EDIT_PG_RECORD')
                THEN ARRAY['EDIT_PG_RECORD', 'VIEW_PG_APPLICANTS', 'VIEW_PG_STUDENTS', 'EDIT_PG_APPLICANT', 'EDIT_PG_STUDENT', 'EDIT_PG_BIODATA',
                           'EDIT_PG_ADMISSION', 'EDIT_PG_PROGRAMME', 'EDIT_PG_ACADEMIC_PLACEMENT', 'EDIT_PG_STAGE', 'EDIT_PG_STATUS', 'EDIT_PG_DOCUMENTS',
                           'VIEW_PG_CHANGE_HISTORY', 'EXPORT_PG_RECORDS']
                     || coalesce((SELECT array_agg(g.permission ORDER BY g.permission) FROM admissions.pg_edit_grant g
                                   WHERE g.office_code = p_office AND g.permission IN ('EDIT_PG_ADMISSION_DECISION', 'EDIT_PG_MATRICULATION',
                                                                                     'EDIT_PG_FINANCIAL_RECORD', 'EDIT_PG_PUBLISHED_RESULT', 'EDIT_PG_GRADUATION')), '{}')
                ELSE coalesce((SELECT array_agg(g.permission ORDER BY g.permission) FROM admissions.pg_edit_grant g WHERE g.office_code = p_office), '{}') END
$fn$;
COMMENT ON FUNCTION admissions.pg_edit_permissions(text) IS
  'V715: the permissions an office holds on the postgraduate record pages — EDIT_PG_RECORD with the ordinary ones it carries, the sensitive ones only as granted apart.';

CREATE FUNCTION admissions.pg_edit_may(p_office text, p_permission text) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT p_permission = ANY (admissions.pg_edit_permissions(coalesce(p_office, '')))
$fn$;

-- ── 2 · a postgraduate student's record on the student edit page ──
CREATE FUNCTION people.student_edit_permissions(p_office text, p_student uuid) RETURNS text[] LANGUAGE sql STABLE AS $fn$
    WITH base AS (SELECT people.student_edit_permissions(p_office) AS p),
         pg AS (SELECT EXISTS (SELECT 1 FROM people.student s JOIN ref.programme g ON g.code = s.programme_code
                                WHERE s.id = p_student AND people.is_postgraduate(s.entry_mode, g.category)) AS yes)
    SELECT CASE WHEN 'EDIT_STUDENT_ACADEMIC_RECORD' = ANY (base.p) THEN base.p
                WHEN pg.yes AND admissions.pg_edit_may(p_office, 'EDIT_PG_STUDENT')
                     THEN (SELECT array_agg(DISTINCT x ORDER BY x) FROM unnest(base.p || ARRAY[
                               'EDIT_STUDENT_BIODATA', 'EDIT_STUDENT_ADMISSION', 'EDIT_STUDENT_ACADEMIC_PLACEMENT', 'EDIT_STUDENT_PROGRAMME',
                               'EDIT_STUDENT_DEPARTMENT', 'EDIT_STUDENT_FACULTY', 'EDIT_STUDENT_SESSION', 'EDIT_STUDENT_STATUS',
                               'EDIT_STUDENT_CLASSIFICATION', 'EDIT_STUDENT_ENROLLMENT', 'EDIT_STUDENT_ACADEMIC_HISTORY', 'EDIT_STUDENT_CARRYOVER',
                               'EDIT_STUDENT_REGISTRATION', 'VIEW_STUDENT_EDIT_HISTORY']) x)
                ELSE base.p END
      FROM base CROSS JOIN pg
$fn$;
COMMENT ON FUNCTION people.student_edit_permissions(text, uuid) IS
  'V715: the student edit page''s permissions an office holds for one student — its own (V642), and for a postgraduate student those EDIT_PG_STUDENT carries: identity, admission, placement, session, status, classification, carry-overs and registration, never the matriculation number, graduation, the level desk (a postgraduate''s level is a stage) or the registration override.';

CREATE FUNCTION people.student_edit_may(p_office text, p_permission text, p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT p_permission = ANY (people.student_edit_permissions(coalesce(p_office, ''), p_student))
$fn$;

DO $do$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('people.student_edit_apply(uuid,jsonb,text,text,boolean,text,integer,text)'::regprocedure);
    d := pg_temp.v715_swap(d, $o$IF NOT people.student_edit_may(v_office, v_perm) THEN$o$,
                              $n$IF NOT people.student_edit_may(v_office, v_perm, p_student) THEN   -- V715: for this student (a postgraduate's, the School's and ICT's)$n$, 1);
    EXECUTE d;
END $do$;

-- ── 3 · the applicant's record corrected ──
CREATE TABLE admissions.pg_applicant_edit (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference      text NOT NULL,
    application_id uuid NOT NULL REFERENCES admissions.pg_application (id) ON DELETE CASCADE,
    section        text NOT NULL CHECK (section IN ('BIODATA', 'CONTACT', 'PROGRAMME', 'ADMISSION', 'QUALIFICATION')),
    field          text NOT NULL,
    old_value      text,
    new_value      text,
    reason         text NOT NULL,
    severity       text NOT NULL CHECK (severity IN ('IMPORTANT', 'CRITICAL')),
    evidence       text,
    actor          uuid,
    actor_office   text,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pg_applicant_edit_app ON admissions.pg_applicant_edit (application_id, at DESC);
CREATE INDEX ix_pg_applicant_edit_at ON admissions.pg_applicant_edit (at DESC);
SELECT audit.attach('admissions.pg_applicant_edit');
COMMENT ON TABLE admissions.pg_applicant_edit IS
  'V715: every correction of a postgraduate applicant''s record made on the record page — the field, the value before and after, the reason, how serious, who and when — under PG-EDIT/YYYY/NNNNNN; kept as written, never updated or deleted.';

CREATE FUNCTION admissions.pg_applicant_edit_kept() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN coalesce(NEW, OLD); END IF;
    RAISE EXCEPTION 'PG_EDIT_KEPT: a correction once written is kept as it was; a wrong correction is corrected by another' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_pg_applicant_edit_kept BEFORE UPDATE OR DELETE ON admissions.pg_applicant_edit
    FOR EACH ROW EXECUTE FUNCTION admissions.pg_applicant_edit_kept();

CREATE FUNCTION admissions.pg_edit_reference() RETURNS text LANGUAGE sql AS $fn$
    SELECT 'PG-EDIT/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/'
           || lpad(platform.next_number('PG_EDIT', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 6, '0')
$fn$;

-- the record as read: the applicant, the application and the previous degrees — a save made on another reading is refused
CREATE FUNCTION admissions.pg_edit_version(p_app uuid) RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT md5(coalesce((SELECT row(p.*)::text || row(a.*)::text FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id WHERE a.id = p_app), '')
               || coalesce((SELECT string_agg(row(d.*)::text, '|' ORDER BY d.id) FROM admissions.pg_prior_degree d WHERE d.application_id = p_app), ''))
$fn$;

CREATE FUNCTION admissions.pg_applicant_edit_note(p_app uuid, p_section text, p_field text, p_old text, p_new text, p_reason text, p_severity text, p_evidence text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_ref text := admissions.pg_edit_reference();
BEGIN
    INSERT INTO admissions.pg_applicant_edit (reference, application_id, section, field, old_value, new_value, reason, severity, evidence, actor, actor_office)
    VALUES (v_ref, p_app, p_section, p_field, p_old, p_new, btrim(p_reason), p_severity, nullif(btrim(coalesce(p_evidence, '')), ''),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    RETURN v_ref;
END $fn$;

CREATE FUNCTION admissions.pg_applicant_edit_apply(p_app uuid, p_changes jsonb, p_reason text, p_version text, p_confirm_critical boolean, p_evidence text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        a admissions.pg_application; p admissions.pg_applicant; g ref.programme;
        k text; v text; v_new text; v_old text; v_perm text; v_sev text; v_section text; v_refused text; v_ref text;
        v_refs jsonb := '[]'::jsonb; v_critical boolean := false; v_code text; v_fields text := '';
        v_known constant text[] := ARRAY['surname', 'other_names', 'sex', 'date_of_birth', 'state_of_origin', 'lga', 'nationality',
                                         'email', 'phone', 'contact_address', 'programme_code', 'specialisation_id', 'session',
                                         'prior_institution', 'prior_award', 'prior_class', 'prior_cgpa', 'prior_year', 'proposal_title'];
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PG_EDIT_APPLICATION: no such postgraduate application' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id FOR UPDATE;
    IF p_version IS NULL OR p_version <> admissions.pg_edit_version(p_app) THEN
        RAISE EXCEPTION 'PG_EDIT_STALE: this record was updated by another user; refresh the record before saving your changes' USING ERRCODE = '23514';
    END IF;
    IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'object' OR p_changes = '{}'::jsonb THEN
        RAISE EXCEPTION 'PG_EDIT_NOTHING: nothing was changed' USING ERRCODE = '23514';
    END IF;
    -- what each field asks: the permission, how serious a change it is, where it may be made
    FOR k IN SELECT jsonb_object_keys(p_changes) LOOP
        IF NOT k = ANY (v_known) THEN
            RAISE EXCEPTION 'PG_EDIT_FIELD: % is not corrected here (the application number, the state, the fees, the screening and the decisions have their own workflows)', k USING ERRCODE = '23514';
        END IF;
        v_perm := CASE WHEN k IN ('surname', 'other_names', 'sex', 'date_of_birth', 'state_of_origin', 'lga', 'nationality', 'email', 'phone', 'contact_address') THEN 'EDIT_PG_BIODATA'
                       WHEN k IN ('programme_code', 'specialisation_id') THEN 'EDIT_PG_PROGRAMME'
                       WHEN k = 'session' THEN 'EDIT_PG_ADMISSION'
                       ELSE 'EDIT_PG_APPLICANT' END;
        IF NOT admissions.pg_edit_may(v_office, v_perm) THEN
            RAISE EXCEPTION 'PG_EDIT_PERMISSION: your office does not hold % for %', v_perm, k USING ERRCODE = '42501';
        END IF;
        IF a.student_id IS NOT NULL AND k IN ('surname', 'other_names', 'sex', 'date_of_birth', 'programme_code', 'session') THEN
            RAISE EXCEPTION 'PG_EDIT_ON_REGISTER: the applicant is on the University register; their % is corrected on the student edit page (the programme by the programme swap), where the student''s record is', k USING ERRCODE = '23514';
        END IF;
        IF k IN ('email', 'programme_code', 'session') THEN v_critical := true; END IF;
    END LOOP;
    v_refused := people.student_edit_reason_refused(p_reason);
    IF v_refused IS NOT NULL THEN RAISE EXCEPTION 'PG_EDIT_REASON: %', v_refused USING ERRCODE = '23514'; END IF;
    IF v_critical AND NOT coalesce(p_confirm_critical, false) THEN
        RAISE EXCEPTION 'PG_EDIT_CONFIRM: the e-mail, the programme or the session is a critical change; confirm it to go on' USING ERRCODE = '23514';
    END IF;

    -- the programme first, so a specialisation given with it is read against the new programme
    FOR k, v IN SELECT key, value #>> '{}' FROM jsonb_each(p_changes) ORDER BY CASE key WHEN 'programme_code' THEN 0 ELSE 1 END, key LOOP
        v_new := nullif(btrim(coalesce(v, '')), '');
        v_section := CASE WHEN k IN ('surname', 'other_names', 'sex', 'date_of_birth', 'state_of_origin', 'lga', 'nationality') THEN 'BIODATA'
                          WHEN k IN ('email', 'phone', 'contact_address') THEN 'CONTACT'
                          WHEN k IN ('programme_code', 'specialisation_id') THEN 'PROGRAMME'
                          WHEN k = 'session' THEN 'ADMISSION' ELSE 'QUALIFICATION' END;
        v_sev := CASE WHEN k IN ('email', 'programme_code', 'session') THEN 'CRITICAL' ELSE 'IMPORTANT' END;
        CASE k
            WHEN 'surname' THEN
                v_old := p.surname;
                IF v_new IS NULL OR length(v_new) > 80 OR v_new !~ '^[A-Za-z][A-Za-z'' .-]*$' THEN
                    RAISE EXCEPTION 'PG_EDIT_NAME: a surname is letters, with a hyphen, apostrophe or space, up to 80' USING ERRCODE = '23514';
                END IF;
                v_new := upper(v_new);
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET surname = v_new WHERE id = p.id; END IF;
            WHEN 'other_names' THEN
                v_old := p.other_names;
                IF v_new IS NULL OR length(v_new) > 120 OR v_new !~ '^[A-Za-z][A-Za-z'' .-]*$' THEN
                    RAISE EXCEPTION 'PG_EDIT_NAME: other names are letters, with a hyphen, apostrophe or space, up to 120' USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET other_names = v_new WHERE id = p.id; END IF;
            WHEN 'sex' THEN
                v_old := p.sex; v_new := upper(v_new);
                IF v_new IS NOT NULL AND v_new NOT IN ('F', 'M') THEN RAISE EXCEPTION 'PG_EDIT_SEX: sex is F or M' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET sex = v_new WHERE id = p.id; END IF;
            WHEN 'date_of_birth' THEN
                v_old := p.date_of_birth::text;
                IF v_new IS NULL OR v_new !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'PG_EDIT_DOB: a date of birth is YYYY-MM-DD' USING ERRCODE = '23514'; END IF;
                IF v_new::date < DATE '1930-01-01' OR v_new::date > (current_date - interval '15 years')::date THEN
                    RAISE EXCEPTION 'PG_EDIT_DOB: % is not a date of birth for a postgraduate applicant', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET date_of_birth = v_new::date WHERE id = p.id; END IF;
            WHEN 'state_of_origin' THEN
                v_old := p.state_of_origin;
                IF v_new IS NOT NULL AND length(v_new) > 80 THEN RAISE EXCEPTION 'PG_EDIT_STATE: a state is up to 80 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET state_of_origin = v_new WHERE id = p.id; END IF;
            WHEN 'lga' THEN
                v_old := p.lga;
                IF v_new IS NOT NULL AND length(v_new) > 80 THEN RAISE EXCEPTION 'PG_EDIT_LGA: a local government area is up to 80 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET lga = v_new WHERE id = p.id; END IF;
            WHEN 'nationality' THEN
                v_old := p.nationality;
                IF v_new IS NOT NULL AND length(v_new) > 80 THEN RAISE EXCEPTION 'PG_EDIT_NATIONALITY: a nationality is up to 80 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET nationality = v_new WHERE id = p.id; END IF;
            WHEN 'email' THEN
                v_old := p.email; v_new := lower(v_new);
                IF v_new IS NULL OR v_new !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
                    RAISE EXCEPTION 'PG_EDIT_EMAIL: % is not an e-mail address', coalesce(v_new, 'nothing') USING ERRCODE = '23514';
                END IF;
                IF EXISTS (SELECT 1 FROM admissions.pg_applicant x WHERE lower(x.email) = v_new AND x.id <> p.id) THEN
                    RAISE EXCEPTION 'PG_EDIT_EMAIL_TAKEN: % is another applicant''s e-mail address', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET email = v_new WHERE id = p.id; END IF;
            WHEN 'phone' THEN
                v_old := p.phone; v_new := coalesce(admissions.pg_phone_key(v_new), v_new);
                IF v_new IS NOT NULL AND v_new !~ '^0[0-9]{10}$' THEN
                    RAISE EXCEPTION 'PG_EDIT_PHONE: a phone number is eleven digits (0…), or +234…' USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET phone = v_new WHERE id = p.id; END IF;
            WHEN 'contact_address' THEN
                v_old := p.contact_address;
                IF v_new IS NOT NULL AND length(v_new) > 300 THEN RAISE EXCEPTION 'PG_EDIT_ADDRESS: an address is up to 300 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_applicant SET contact_address = v_new WHERE id = p.id; END IF;
            WHEN 'programme_code' THEN
                v_old := a.programme_code; v_new := upper(v_new);
                IF a.spgs_decided_at IS NOT NULL THEN
                    RAISE EXCEPTION 'PG_EDIT_DECIDED: the School has decided this application for %; the programme is corrected before the decision, or by the programme swap once the applicant is on the register', v_old USING ERRCODE = '23514';
                END IF;
                SELECT * INTO g FROM ref.programme WHERE code = v_new;
                IF g.code IS NULL OR g.category <> 'POST GRADUATE' OR coalesce(g.archived, false) THEN
                    RAISE EXCEPTION 'PG_EDIT_PROGRAMME: % is not a postgraduate programme in use', coalesce(v_new, 'nothing') USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN
                    UPDATE admissions.pg_application
                       SET programme_code = v_new, entry_level = admissions.pg_award_level(admissions.pg_award_of(g.pg_award, g.name)),
                           specialisation_id = CASE WHEN EXISTS (SELECT 1 FROM catalogue.programme_specialisation ps WHERE ps.id = specialisation_id AND ps.programme_code = v_new)
                                                    THEN specialisation_id END
                     WHERE id = p_app;
                    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app;
                END IF;
            WHEN 'specialisation_id' THEN
                v_old := a.specialisation_id::text;
                IF v_new IS NOT NULL AND NOT EXISTS (SELECT 1 FROM catalogue.programme_specialisation ps WHERE ps.id::text = v_new AND ps.programme_code = a.programme_code AND ps.active) THEN
                    RAISE EXCEPTION 'PG_EDIT_SPECIALISATION: that is not a running specialisation of %', a.programme_code USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET specialisation_id = v_new::uuid WHERE id = p_app; END IF;
            WHEN 'session' THEN
                v_old := a.session;
                IF v_new IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session x WHERE x.name = v_new) THEN
                    RAISE EXCEPTION 'PG_EDIT_SESSION: % is not a session on the calendar', coalesce(v_new, 'nothing') USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old AND EXISTS (SELECT 1 FROM admissions.pg_fee_reference f WHERE f.application_id = p_app AND f.confirmed_at IS NOT NULL) THEN
                    RAISE EXCEPTION 'PG_EDIT_SESSION_PAID: a fee was paid for the % session; the Bursary''s reallocation moves a payment to another session', v_old USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET session = v_new WHERE id = p_app; UPDATE admissions.pg_applicant SET session = v_new WHERE id = p.id; END IF;
            WHEN 'prior_institution' THEN
                v_old := a.prior_institution;
                IF v_new IS NOT NULL AND length(v_new) > 200 THEN RAISE EXCEPTION 'PG_EDIT_PRIOR: an institution is up to 200 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET prior_institution = v_new WHERE id = p_app; END IF;
            WHEN 'prior_award' THEN
                v_old := a.prior_award;
                IF v_new IS NOT NULL AND length(v_new) > 80 THEN RAISE EXCEPTION 'PG_EDIT_PRIOR: an award is up to 80 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET prior_award = v_new WHERE id = p_app; END IF;
            WHEN 'prior_class' THEN
                v_old := a.prior_class;
                IF v_new IS NOT NULL AND length(v_new) > 80 THEN RAISE EXCEPTION 'PG_EDIT_PRIOR: a class of degree is up to 80 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET prior_class = v_new WHERE id = p_app; END IF;
            WHEN 'prior_cgpa' THEN
                v_old := a.prior_cgpa::text;
                IF v_new IS NOT NULL AND (v_new !~ '^[0-5](\.[0-9]{1,2})?$' OR v_new::numeric > 5) THEN RAISE EXCEPTION 'PG_EDIT_PRIOR: a CGPA is 0.00 to 5.00' USING ERRCODE = '23514'; END IF;
                IF v_new::numeric IS DISTINCT FROM v_old::numeric THEN UPDATE admissions.pg_application SET prior_cgpa = v_new::numeric WHERE id = p_app; ELSE v_new := v_old; END IF;
            WHEN 'prior_year' THEN
                v_old := a.prior_year::text;
                IF v_new IS NOT NULL AND (v_new !~ '^(19|20)[0-9]{2}$' OR v_new::int > extract(year FROM now())::int) THEN
                    RAISE EXCEPTION 'PG_EDIT_PRIOR: a year of graduation is 1900 to this year' USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET prior_year = v_new::int WHERE id = p_app; END IF;
            WHEN 'proposal_title' THEN
                v_old := a.proposal_title;
                IF v_new IS NOT NULL AND length(v_new) > 300 THEN RAISE EXCEPTION 'PG_EDIT_PROPOSAL: a proposal title is up to 300 characters' USING ERRCODE = '23514'; END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE admissions.pg_application SET proposal_title = v_new WHERE id = p_app; END IF;
        END CASE;
        IF v_new IS DISTINCT FROM v_old THEN
            v_ref := admissions.pg_applicant_edit_note(p_app, v_section, k, v_old, v_new, p_reason, v_sev, p_evidence);
            v_refs := v_refs || jsonb_build_object('field', k, 'from', v_old, 'to', v_new, 'severity', v_sev, 'reference', v_ref);
            v_fields := v_fields || CASE WHEN v_fields = '' THEN '' ELSE ', ' END || k;
        END IF;
    END LOOP;
    IF jsonb_array_length(v_refs) = 0 THEN
        RAISE EXCEPTION 'PG_EDIT_NOTHING: every value given is the record''s own already' USING ERRCODE = '23514';
    END IF;
    PERFORM admissions.pg_app_event(p_app, 'RECORD_CORRECTED', 'Record corrected on the postgraduate record page: ' || v_fields || ' — ' || btrim(p_reason));
    RETURN jsonb_build_object('changed', jsonb_array_length(v_refs), 'edits', v_refs, 'version', admissions.pg_edit_version(p_app));
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_edit_apply(uuid, jsonb, text, text, boolean, text) IS
  'V715: the identity, contacts, programme, specialisation, session and previous education of a postgraduate application corrected on the record page — each field checked (the permission, the value, its uniqueness, the application''s state), then all written or none; the version read must be the record''s (PG_EDIT_STALE); a reason as the student edit asks; the e-mail, programme and session confirmed as critical. On the register, the names and placement are the student edit page''s (PG_EDIT_ON_REGISTER); the programme is corrected before the School''s decision (PG_EDIT_DECIDED); the session before a fee was paid for it (PG_EDIT_SESSION_PAID).';

-- the previous degrees replaced as one change
CREATE FUNCTION admissions.pg_prior_degrees_set(p_app uuid, p_rows jsonb, p_reason text, p_version text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); a admissions.pg_application; r jsonb; v_old text; v_new text;
        v_refused text; v_ref text; n integer := 0;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PG_EDIT_APPLICATION: no such postgraduate application' USING ERRCODE = 'P0002'; END IF;
    IF NOT admissions.pg_edit_may(v_office, 'EDIT_PG_APPLICANT') THEN
        RAISE EXCEPTION 'PG_EDIT_PERMISSION: your office does not hold EDIT_PG_APPLICANT for the previous degrees' USING ERRCODE = '42501';
    END IF;
    IF p_version IS NULL OR p_version <> admissions.pg_edit_version(p_app) THEN
        RAISE EXCEPTION 'PG_EDIT_STALE: this record was updated by another user; refresh the record before saving your changes' USING ERRCODE = '23514';
    END IF;
    v_refused := people.student_edit_reason_refused(p_reason);
    IF v_refused IS NOT NULL THEN RAISE EXCEPTION 'PG_EDIT_REASON: %', v_refused USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RAISE EXCEPTION 'PG_EDIT_PRIOR: the previous degrees are a list' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x LOOP
        IF coalesce(r->>'kind', '') NOT IN ('NCE', 'ND', 'HND', 'FIRST', 'PGD', 'MASTERS', 'PHD', 'OTHER') THEN
            RAISE EXCEPTION 'PG_EDIT_PRIOR: a previous degree is NCE, ND, HND, FIRST (degree), PGD, MASTERS, PHD or OTHER' USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(r->>'institution', '')), '') IS NULL OR length(r->>'institution') > 200 THEN
            RAISE EXCEPTION 'PG_EDIT_PRIOR: each previous degree names its institution, up to 200 characters' USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(r->>'award', '')), '') IS NULL OR length(r->>'award') > 80 THEN
            RAISE EXCEPTION 'PG_EDIT_PRIOR: each previous degree names its award, up to 80 characters' USING ERRCODE = '23514';
        END IF;
        IF length(coalesce(r->>'field', '')) > 120 OR length(coalesce(r->>'class_of_degree', '')) > 80 THEN
            RAISE EXCEPTION 'PG_EDIT_PRIOR: a field of study is up to 120 characters and a class of degree up to 80' USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(r->>'cgpa', '')), '') IS NOT NULL AND ((r->>'cgpa') !~ '^[0-5](\.[0-9]{1,2})?$' OR (r->>'cgpa')::numeric > 5) THEN
            RAISE EXCEPTION 'PG_EDIT_PRIOR: a CGPA is 0.00 to 5.00' USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(r->>'year', '')), '') IS NOT NULL AND ((r->>'year') !~ '^(19|20)[0-9]{2}$' OR (r->>'year')::int > extract(year FROM now())::int) THEN
            RAISE EXCEPTION 'PG_EDIT_PRIOR: a year of graduation is 1900 to this year' USING ERRCODE = '23514';
        END IF;
    END LOOP;
    SELECT coalesce(string_agg(d.kind || ' ' || d.award || ' · ' || d.institution || coalesce(' · ' || d.field, '') || coalesce(' · ' || d.class_of_degree, '')
                               || coalesce(' · ' || d.cgpa::text, '') || coalesce(' · ' || d.year::text, ''), E'\n' ORDER BY CASE d.kind WHEN 'FIRST' THEN 0 ELSE 1 END, d.year, d.award), '')
      INTO v_old FROM admissions.pg_prior_degree d WHERE d.application_id = p_app;
    DELETE FROM admissions.pg_prior_degree WHERE application_id = p_app;
    FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x LOOP
        INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, field, class_of_degree, cgpa, year)
        VALUES (p_app, r->>'kind', btrim(r->>'institution'), btrim(r->>'award'), nullif(btrim(coalesce(r->>'field', '')), ''),
                nullif(btrim(coalesce(r->>'class_of_degree', '')), ''), nullif(btrim(coalesce(r->>'cgpa', '')), '')::numeric, nullif(btrim(coalesce(r->>'year', '')), '')::int);
        n := n + 1;
    END LOOP;
    SELECT coalesce(string_agg(d.kind || ' ' || d.award || ' · ' || d.institution || coalesce(' · ' || d.field, '') || coalesce(' · ' || d.class_of_degree, '')
                               || coalesce(' · ' || d.cgpa::text, '') || coalesce(' · ' || d.year::text, ''), E'\n' ORDER BY CASE d.kind WHEN 'FIRST' THEN 0 ELSE 1 END, d.year, d.award), '')
      INTO v_new FROM admissions.pg_prior_degree d WHERE d.application_id = p_app;
    IF v_new = v_old THEN RAISE EXCEPTION 'PG_EDIT_NOTHING: the previous degrees given are the record''s own already' USING ERRCODE = '23514'; END IF;
    v_ref := admissions.pg_applicant_edit_note(p_app, 'QUALIFICATION', 'prior_degrees', nullif(v_old, ''), nullif(v_new, ''), p_reason, 'IMPORTANT', NULL);
    PERFORM admissions.pg_app_event(p_app, 'RECORD_CORRECTED', 'Previous degrees corrected on the postgraduate record page (' || n || ') — ' || btrim(p_reason));
    RETURN jsonb_build_object('changed', 1, 'degrees', n, 'reference', v_ref, 'version', admissions.pg_edit_version(p_app));
END $fn$;
COMMENT ON FUNCTION admissions.pg_prior_degrees_set(uuid, jsonb, text, text) IS
  'V715: a postgraduate application''s previous degrees replaced as one change — each row checked, the set before and after kept on admissions.pg_applicant_edit.';

-- the record's history: the corrections, and the application's own events (decisions, fees, screening, migration)
CREATE FUNCTION admissions.pg_applicant_edit_history(p_app uuid)
RETURNS TABLE (at timestamptz, reference text, change_type text, severity text, section text, field text, old_value text, new_value text,
               reason text, by_name text, office text, source text)
LANGUAGE sql STABLE AS $fn$
    SELECT e.at, e.reference, 'EDIT', e.severity, e.section, e.field, e.old_value, e.new_value, e.reason,
           people.officer_name(e.actor), e.actor_office, 'Postgraduate record page'
      FROM admissions.pg_applicant_edit e WHERE e.application_id = p_app
    UNION ALL
    SELECT v.at, NULL, v.kind, CASE WHEN v.kind IN ('OFFERED', 'NOT_OFFERED', 'ADMITTED', 'ADMITTED_ON_OLD_PORTAL', 'MIGRATED') THEN 'CRITICAL' ELSE 'IMPORTANT' END,
           'APPLICATION', lower(replace(v.kind, '_', ' ')), NULL, v.note, NULL, people.officer_name(v.actor_id), v.actor_office, 'Application history'
      FROM admissions.pg_application_event v WHERE v.application_id = p_app AND v.kind <> 'RECORD_CORRECTED'
$fn$;
COMMENT ON FUNCTION admissions.pg_applicant_edit_history(uuid) IS
  'V715: every change of a postgraduate application''s record — the record page''s corrections (PG-EDIT references) beside the application''s own events: the decisions, the fees, the screening, the migration.';

-- ── 4 · applicants and students in one search; the latest corrections ──
CREATE FUNCTION admissions.pg_record_search(p_q text, p_faculty text, p_dept text, p_programme text, p_session text, p_kind text, p_state text, p_award text, p_limit integer)
RETURNS TABLE (kind text, application_id uuid, student_id uuid, name text, application_no text, legacy_no text, matric_no text, admission_no text, jamb_reg_no text,
               email text, phone text, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, award text,
               session text, level integer, stage text, status text, at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT nullif(btrim(coalesce(p_q, '')), '') AS t, upper(nullif(btrim(coalesce(p_q, '')), '')) AS u,
                      admissions.pg_phone_key(p_q) AS d, lower(nullif(btrim(coalesce(p_q, '')), '')) AS l, least(greatest(coalesce(p_limit, 100), 1), 500) AS lim),
    cur AS (SELECT admissions.pg_current_session() AS s),
    applicants AS (
        SELECT 'APPLICANT'::text AS kind, a.id AS application_id, NULL::uuid AS student_id,
               upper(btrim(p.surname)) || coalesce(', ' || nullif(btrim(p.other_names), ''), '') AS name, a.application_no, l.legacy_application_no AS legacy_no,
               NULL::text AS matric_no, NULL::text AS admission_no, NULL::text AS jamb_reg_no, p.email, p.phone,
               g.code AS programme_code, g.name AS programme, g.dept_code, d.name AS department, g.faculty_code, f.name AS faculty,
               admissions.pg_award_of(g.pg_award, g.name) AS award, a.session, a.entry_level AS level, NULL::text AS stage, a.state AS status,
               coalesce(a.submitted_at, a.created_at) AS at
          FROM admissions.pg_application a
          JOIN admissions.pg_applicant p ON p.id = a.applicant_id
          JOIN ref.programme g ON g.code = a.programme_code
          LEFT JOIN ref.department d ON d.code = g.dept_code
          LEFT JOIN ref.faculty f ON f.code = g.faculty_code
          LEFT JOIN admissions.pg_legacy_application l ON l.application_id = a.id
          CROSS JOIN q
         WHERE a.student_id IS NULL
           AND (q.t IS NULL OR a.id::text = q.l OR upper(a.application_no) = q.u OR upper(btrim(coalesce(l.legacy_application_no, ''))) = q.u
                OR lower(p.email) = q.l OR (q.d IS NOT NULL AND p.phone = q.d)
                OR (upper(p.surname) || ' ' || upper(coalesce(p.other_names, ''))) LIKE '%' || q.u || '%'
                OR (upper(coalesce(p.other_names, '')) || ' ' || upper(p.surname)) LIKE '%' || q.u || '%')),
    students AS (
        SELECT 'STUDENT'::text, a.id, s.id,
               upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), a.application_no,
               coalesce(l.legacy_application_no, (SELECT b.value FROM people.biodata b WHERE b.student_id = s.id AND b.field = 'legacy_appno')),
               s.matric_no, s.admission_no, s.jamb_reg_no, coalesce(k.email, p.email), coalesce(k.phone, p.phone),
               g.code, g.name, g.dept_code, d.name, g.faculty_code, f.name,
               admissions.pg_award_of(g.pg_award, g.name), coalesce(a.session, s.entry_session), s.current_level,
               (SELECT x.stage_code FROM admissions.pg_stages_of(cur.s, ARRAY[s.id]) x LIMIT 1), s.status, coalesce(a.submitted_at, a.created_at, s.matriculated_at)
          FROM people.student s
          JOIN ref.programme g ON g.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = g.dept_code
          LEFT JOIN ref.faculty f ON f.code = g.faculty_code
          LEFT JOIN admissions.pg_application a ON a.student_id = s.id
          LEFT JOIN admissions.pg_applicant p ON p.id = a.applicant_id
          LEFT JOIN admissions.pg_legacy_application l ON l.application_id = a.id
          LEFT JOIN people.student_contact k ON k.student_id = s.id
          CROSS JOIN q CROSS JOIN cur
         WHERE s.duplicate_of IS NULL AND people.is_postgraduate(s.entry_mode, g.category)
           AND (q.t IS NULL OR s.id::text = q.l OR upper(s.matric_no) LIKE q.u || '%' OR upper(s.admission_no) = q.u OR upper(s.jamb_reg_no) = q.u
                OR upper(coalesce(a.application_no, '')) = q.u OR upper(btrim(coalesce(l.legacy_application_no, ''))) = q.u
                OR EXISTS (SELECT 1 FROM people.biodata b WHERE b.student_id = s.id AND b.field = 'legacy_appno' AND upper(btrim(b.value)) = q.u)
                OR lower(coalesce(k.email, p.email, '')) = q.l OR (q.d IS NOT NULL AND coalesce(k.phone, p.phone) = q.d)
                OR (upper(s.surname) || ' ' || upper(coalesce(s.other_names, ''))) LIKE '%' || q.u || '%'
                OR (upper(coalesce(s.other_names, '')) || ' ' || upper(s.surname)) LIKE '%' || q.u || '%')),
    all_rows AS (SELECT * FROM applicants UNION ALL SELECT * FROM students)
    SELECT r.* FROM all_rows r CROSS JOIN q
     WHERE (p_kind IS NULL OR r.kind = upper(p_kind))
       AND (p_faculty IS NULL OR r.faculty_code = p_faculty) AND (p_dept IS NULL OR r.dept_code = p_dept) AND (p_programme IS NULL OR r.programme_code = p_programme)
       AND (p_session IS NULL OR r.session = p_session) AND (p_state IS NULL OR r.status = upper(p_state)) AND (p_award IS NULL OR r.award = upper(p_award))
     ORDER BY (q.u IS NOT NULL AND (r.application_no = q.u OR r.matric_no = q.u OR r.admission_no = q.u OR upper(coalesce(r.legacy_no, '')) = q.u)) DESC, r.name, r.kind
     LIMIT (SELECT lim FROM q)
$fn$;
COMMENT ON FUNCTION admissions.pg_record_search(text, text, text, text, text, text, text, text, integer) IS
  'V715: postgraduate applicants (not yet on the register) and postgraduate students in one list — by application number (this portal''s or the old portal''s), matriculation, admission or JAMB number, e-mail, phone or name; narrowed by faculty, department, programme, session, kind, state and award; a student''s stage from the stages desk (V651); at most 500.';

CREATE FUNCTION admissions.pg_edit_recent(p_limit integer)
RETURNS TABLE (at timestamptz, reference text, kind text, record_id uuid, name text, number text, section text, field text, old_value text, new_value text,
               reason text, severity text, by_name text, office text)
LANGUAGE sql STABLE AS $fn$
    SELECT * FROM (
        SELECT e.at, e.reference, 'APPLICANT'::text, e.application_id, upper(btrim(p.surname)) || coalesce(', ' || nullif(btrim(p.other_names), ''), ''), a.application_no,
               e.section, e.field, e.old_value, e.new_value, e.reason, e.severity, people.officer_name(e.actor), e.actor_office
          FROM admissions.pg_applicant_edit e JOIN admissions.pg_application a ON a.id = e.application_id JOIN admissions.pg_applicant p ON p.id = a.applicant_id
        UNION ALL
        SELECT e.at, e.reference, 'STUDENT', e.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), coalesce(s.matric_no, s.admission_no),
               e.section, e.field, e.old_value, e.new_value, e.reason, e.severity, people.officer_name(e.actor), e.actor_office
          FROM people.student_edit e JOIN people.student s ON s.id = e.student_id JOIN ref.programme g ON g.code = s.programme_code
         WHERE people.is_postgraduate(s.entry_mode, g.category)) x
     ORDER BY x.at DESC LIMIT least(greatest(coalesce(p_limit, 200), 1), 1000)
$fn$;
COMMENT ON FUNCTION admissions.pg_edit_recent(integer) IS
  'V715: the latest corrections of postgraduate records — applicants'' (admissions.pg_applicant_edit) and students'' (people.student_edit) — newest first.';

COMMIT;
