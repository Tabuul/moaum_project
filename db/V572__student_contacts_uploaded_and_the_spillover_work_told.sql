-- V572: student contacts uploaded by the Registry and the departments; the spillover work waiting told to the Academic Office and
-- the Registrar.
--
-- On the live-shaped copy of 19 October 2026 the University holds neither an e-mail address nor a phone number for 13,576 current
-- students (V565's list): they receive no notice and no reset link. The ICT Support Desk takes a contact one ticket at a time; the
-- Registry and the departments hold class lists with the numbers. Now they upload them:
--
--   * people.contact_phone(text): a phone as the record keeps it — 0 and ten digits (234… and a number that lost its leading 0 in
--     Excel are read as such); people.contacts_missing(faculty, department): the current students missing a phone, an e-mail or both,
--     the upload's template.
--   * people.load_contacts(rows, faculty, department): each row (student number, phone, e-mail) matched to one student by matric,
--     admission or JAMB number and FILLED only where the student holds no phone or no e-mail (the contact they gave, else their
--     applicant account's, as people.student_reach reads it); a contact the student holds is KEPT, never overwritten. A phone or
--     e-mail another student holds is refused (TAKEN) — a reset link sent there would reach someone else — as is a malformed one
--     (INVALID), a student outside the uploader's faculty or department (OUTSIDE_SCOPE), a number matching no student or more than
--     one, and a second row for the same student. The preview runs it and rolls back.
--   * people.contact_upload: each upload kept (who, which office and scope, the file, the counts, the reason); audited.
--
-- The spillover work (V475's level corrections, V558's reconciliation) waits: 10,748 spillover level corrections and 19,291
-- reconcilable recommendations, and Reconciliation has never been run. people.spillover_work() counts it for the Academic Office's
-- and the Registrar's homes, and people.tell_spillover_work() tells the holders of both offices each Monday while any waits
-- (template SPILLOVER_WORK_WAITING, once a week each; ICT may switch the template off).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'V572: student contacts uploaded; the spillover work told', true);

-- ── a phone as the record keeps it ──────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.contact_phone(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN d = '' THEN NULL
                WHEN d ~ '^234[0-9]{10}$' THEN '0' || substr(d, 4)
                WHEN d ~ '^[789][0-9]{9}$' THEN '0' || d          -- the leading 0 a spreadsheet drops
                ELSE d END
      FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) x
$fn$;
COMMENT ON FUNCTION people.contact_phone(text) IS
  'V572: a phone number as student contacts keep it (0 and ten digits): +234/234 and a number missing its leading 0 read as such';

-- ── the current students missing a contact (the upload's template) ─────────────────────────────────────────────────────────
CREATE FUNCTION people.contacts_missing(p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL)
RETURNS TABLE (student_id uuid, number text, name text, faculty text, department text, programme text, level integer, status text,
               no_phone boolean, no_email boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT x.id, x.number, x.name, x.faculty, x.department, x.programme, x.level, x.status, x.no_phone, x.no_email
      FROM (SELECT s.id, coalesce(s.matric_no, s.admission_no, s.jamb_reg_no) AS number,
                   upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name,
                   f.name AS faculty, d.name AS department, p.name AS programme, s.current_level AS level, s.status,
                   nullif(btrim(coalesce(c.phone, a.phone, '')), '') IS NULL AS no_phone,
                   nullif(btrim(coalesce(c.email, a.email, '')), '') IS NULL AS no_email
              FROM people.student s
              JOIN ref.programme p ON p.code = s.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN people.student_contact c ON c.student_id = s.id
              LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id
             WHERE s.duplicate_of IS NULL AND s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED', 'DEFERRED')
               AND (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_dept IS NULL OR p.dept_code = p_dept)) x
     WHERE x.no_phone OR x.no_email
     ORDER BY x.faculty, x.department, x.programme, x.level, x.name
$fn$;
COMMENT ON FUNCTION people.contacts_missing(text, text) IS
  'V572: the current students (active, on probation, admitted, deferred) the University holds no phone or no e-mail for, within a faculty or department';

-- ── each upload kept ────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.contact_upload (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name       text,
    office          text NOT NULL,
    faculty_code    text,
    department_code text,
    rows_read       integer NOT NULL DEFAULT 0,
    students_filled integer NOT NULL DEFAULT 0,
    phones_filled   integer NOT NULL DEFAULT 0,
    emails_filled   integer NOT NULL DEFAULT 0,
    refused         integer NOT NULL DEFAULT 0,
    reason          text NOT NULL,
    uploaded_by     uuid,
    uploaded_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_contact_upload_at ON people.contact_upload (uploaded_at DESC);
COMMENT ON TABLE people.contact_upload IS
  'V572: an upload of student phone numbers and e-mail addresses by the Registry or a department — who, the scope, the file and what it filled';
SELECT audit.attach('people.contact_upload');

-- ── the rows matched, checked and the empty contacts filled ────────────────────────────────────────────────────────────────
CREATE FUNCTION people.load_contacts(p_rows jsonb, p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL)
RETURNS TABLE (row_no integer, number_in text, phone_in text, email_in text, student_id uuid, name text, number text, programme text,
               phone text, email text, phone_outcome text, email_outcome text, outcome text, message text)
LANGUAGE plpgsql AS $fn$
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
        INSERT INTO people.student_contact AS c (student_id, phone, email, updated_at)
        SELECT d.sid, CASE WHEN d.po = 'FILL' THEN d.ph END, CASE WHEN d.eo = 'FILL' THEN d.em END, now()
          FROM d WHERE d.oc = 'FILLED'
        ON CONFLICT ON CONSTRAINT student_contact_pkey DO UPDATE
           SET phone = coalesce(nullif(btrim(c.phone), ''), EXCLUDED.phone), email = coalesce(nullif(btrim(c.email), ''), EXCLUDED.email), updated_at = now()
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
END $fn$;
COMMENT ON FUNCTION people.load_contacts(jsonb, text, text) IS
  'V572: uploaded (number, phone, e-mail) rows matched to one student each and filled only where the student holds no phone or e-mail; a contact held is kept, one another student holds refused';

-- ── the spillover work waiting ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.spillover_work()
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH lc AS (SELECT count(*) AS n, count(*) FILTER (WHERE basis = 'SPILLOVER') AS sp, count(*) FILTER (WHERE basis = 'REGISTRATION') AS rg,
                       count(*) FILTER (WHERE basis = 'ARITHMETIC') AS ar
                  FROM people.level_correction),
         lr AS (SELECT count(*) FILTER (WHERE actionable) AS n,
                       count(*) FILTER (WHERE recommendation = 'GRADUATION_CANDIDATE') AS grad,
                       count(*) FILTER (WHERE recommendation = 'MAXIMUM_SPILLOVER_REACHED') AS lim,
                       count(*) FILTER (WHERE recommendation LIKE 'SPILLOVER\_YEAR\_%') AS spy,
                       count(*) FILTER (WHERE recommendation = 'REQUIRES_REVIEW') AS rev,
                       count(*) FILTER (WHERE recommendation = 'DATA_INCOMPLETE') AS inc
                  FROM people.lifecycle_recommendation WHERE reconciliation_id IS NULL),
         rc AS (SELECT count(*) AS n, max(reconciled_at) AS last FROM people.lifecycle_reconciliation)
    SELECT jsonb_build_object('levelCorrections', lc.n, 'spilloverCorrections', lc.sp, 'registrationCorrections', lc.rg, 'arithmeticCorrections', lc.ar,
                              'toReconcile', lr.n, 'graduationCandidates', lr.grad, 'limitReached', lr.lim, 'spilloverYears', lr.spy,
                              'review', lr.rev, 'incomplete', lr.inc, 'reconciled', rc.n, 'lastReconciledAt', rc.last)
      FROM lc, lr, rc
$fn$;
COMMENT ON FUNCTION people.spillover_work() IS
  'V572: the spillover work waiting — level corrections by basis, the recommendations not yet reconciled by kind, and when Reconciliation last ran';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('SPILLOVER_WORK_WAITING', 'The spillover work waiting',
 'Each Monday to the Academic Office and the Registrar while level corrections or reconcilable recommendations wait on Student Cohorts',
 '[TOTAL] student records wait on Student Cohorts',
 E'Dear [FIRST_NAME],\n\nThe spillover work on Student Cohorts is waiting:\n\n- Level corrections: [CORRECTIONS] ([SPILLOVER_CORRECTIONS] spillover students whose record still reads a level below their programme''s final level).\n- Reconciliation: [TO_RECONCILE] recommendations not yet reconciled — [CANDIDATES] graduation candidates, [LIMIT] at the spillover limit for the Registry''s decision and [SPILLOVER] in a spillover year.\n\n[LAST_RUN]. Until the levels are corrected and the recommendations reconciled, these students are charged, registered and listed at the wrong level, and graduation candidates do not reach the graduation list.\n\nOpen Student Cohorts, Level corrections and Reconciliation: [PORTAL_URL]\n\nThis notice comes each Monday while work waits.\n\nMOAUM Portal',
 NULL,
 '[TOTAL] student records wait on Student Cohorts',
 '[CORRECTIONS] level corrections and [TO_RECONCILE] recommendations wait ([CANDIDATES] graduation candidates, [LIMIT] at the spillover limit). [LAST_RUN]. Open Student Cohorts, Level corrections and Reconciliation.',
 ARRAY['FIRST_NAME','TOTAL','CORRECTIONS','SPILLOVER_CORRECTIONS','TO_RECONCILE','CANDIDATES','LIMIT','SPILLOVER','LAST_RUN','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

-- the holders of the Academic Office and the Registrar told, once a week each, while any of the work waits
CREATE FUNCTION people.tell_spillover_work()
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE w jsonb := people.spillover_work(); v_week text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW');
        v_day date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_vars jsonb; p record; v_told int := 0;
BEGIN
    IF (w->>'levelCorrections')::bigint + (w->>'toReconcile')::bigint = 0 THEN
        RETURN 0;
    END IF;
    v_vars := jsonb_build_object(
        'TOTAL', to_char((w->>'levelCorrections')::bigint + (w->>'toReconcile')::bigint, 'FM999,999,990'),
        'CORRECTIONS', to_char((w->>'levelCorrections')::bigint, 'FM999,999,990'),
        'SPILLOVER_CORRECTIONS', to_char((w->>'spilloverCorrections')::bigint, 'FM999,999,990'),
        'TO_RECONCILE', to_char((w->>'toReconcile')::bigint, 'FM999,999,990'),
        'CANDIDATES', to_char((w->>'graduationCandidates')::bigint, 'FM999,999,990'),
        'LIMIT', to_char((w->>'limitReached')::bigint, 'FM999,999,990'),
        'SPILLOVER', to_char((w->>'spilloverYears')::bigint, 'FM999,999,990'),
        'LAST_RUN', CASE WHEN w->>'lastReconciledAt' IS NULL THEN 'Reconciliation has never been run'
                         ELSE 'Reconciliation last ran on ' || to_char((w->>'lastReconciledAt')::timestamptz AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY') END);
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code IN ('academic', 'registrar') AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day) LOOP
        v_told := v_told + platform.tell_person(p.person_id, 'SPILLOVER_WORK_WAITING', NULL, v_vars, 'spillover-work:' || v_week || ':' || p.person_id);
    END LOOP;
    RETURN v_told;
END $fn$;
COMMENT ON FUNCTION people.tell_spillover_work() IS
  'V572: the holders of the Academic Office and the Registrar told each week, while level corrections or reconcilable recommendations wait';

COMMIT;
