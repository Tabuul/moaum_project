-- ═══════════════════════════════════════════════════════════════════════════════
-- V640 — The Database Operations office, the Database Operator, and examination readiness reporting
--
--   The University's brief of 23 October 2026: a first-class Database Operations office whose Database Operators query, analyse,
--   reconcile, classify and report from the University's operational database — never its administrators — and, before the
--   examinations that start on Monday, examination readiness reports ICT can generate at once: students who have paid school fees
--   and registered, who have paid and not registered, and who have not paid, by course, programme, department, faculty, level,
--   session and semester, every figure opening the students behind it, each official report with its own reference.
--
--   What the portal already had (reused, not rebuilt):
--     · the office register and the grants (ref.office, iam.office_assignment, the scope trigger) — Users & Roles assigns an office
--       to the person already on the register; every endpoint names the offices it admits (the portal's permissions);
--     · ONE classification engine: people.student_classification and people.learner (V469) — programme type, admission route,
--       study mode, centre, faculty, department, programme, level, status, spillover state; Student Query on top of it;
--     · the student statistics engine, reporting.student_positions(session, semester) (V257, read by Student Statistics and every
--       dashboard): the students in study, each with the fee obligation (finance.session_positions — what the student is charged for
--       the session or the semester, what was paid against it, FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE) and the
--       registration across the three registers — the School of Postgraduate Studies', the College of Health Sciences' from 200
--       Level and the University's course registration;
--     · the examination card's own rule (V501, V567): a school-fees payment confirmed for the session (registration.exam_card_paid
--       — reporting.payments, purpose SCHOOL_FEES, confirmed, amount above nil) and a course registration that is not DRAFT and
--       carries a course (registration.exam_card_state);
--     · the cohort engine (people.academic_position: SP1, SP2, beyond the maximum; its issues) and the programme structure
--       (catalogue.course_offer) and the course offerings (catalogue.offering).
--
--   What V640 adds:
--     · the office dbops ("Database Operator, Database Operations"), held over the University or bounded to a faculty, a
--       department or a programme (iam.dbops_scope); the API holds every read to it;
--     · reporting.exam_readiness — on reporting.student_positions, one row a student of the scope for a session and semester, with
--       the fee position, school fees paid by the card's own test (rule CARD, the default) or paid in full (rule FULL), the
--       registration and its register, the courses and units, the carry-overs, and the readiness:
--       PAID_REGISTERED, PAID_NOT_REGISTERED, NOT_PAID (a fee is charged and nothing is paid) and NO_FEE_STATED (nothing charged and
--       nothing paid — never counted as not paid); for a course, registered for the course or expected by the programme structure;
--       reporting.exam_readiness_summary (by faculty, department, programme, level, programme type, academic status) and
--       reporting.course_readiness_summary (each course offered in the semester: registered, paid, not paid, expected and not
--       registered);
--     · official report references DBO/<KIND>/YYYY/NNNNNN (reporting.issue_report, reporting.official_report) — a per-year counter,
--       never a table's own key;
--     · saved and shared queries and reports (reporting.saved_query: the definition — source, filters, columns, grouping, sort —
--       never SQL), and the query log (reporting.query_log: every run, export, print, save, share and report issued);
--     · data quality (reporting.data_quality_rows, reporting.data_quality): records without a valid programme, faculty or department,
--       a missing or invalid entry session, an invalid level, a missing or duplicate matriculation number, a duplicate JAMB number,
--       an unclassified record, conflicting statuses, a graduate still kept active, the level on record against the computed one,
--       a student beyond the maximum academic period, and, for a session and semester, paid and not registered or registered and
--       not paid.
--   Nothing here writes a payment, a result, a registration, a level, a programme or a status.
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V640: the Database Operations office and examination readiness reporting', true);

-- ── 1 · the office ───────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind)
VALUES ('dbops', 'Database Operator, Database Operations', 'institution')
ON CONFLICT (code) DO NOTHING;

-- the scope a Database Operator is held to: the University where any live grant is not bounded to a faculty, department or
-- programme; else the narrowest bounded grant (a faculty before a department before a programme — never wider than a grant);
-- 'none' where no grant is live (an unresolved scoped grant reads nothing)
CREATE FUNCTION iam.dbops_scope(p_person uuid) RETURNS TABLE (kind text, code text)
LANGUAGE sql STABLE AS $fn$
    WITH g AS (
        SELECT a.scope_kind,
               CASE WHEN a.scope_kind IN ('faculty', 'department', 'programme') THEN iam.scope_code(a.scope_kind, a.scope_id) END AS code
          FROM iam.office_assignment a
         WHERE a.person_id = p_person AND a.office_code = 'dbops'
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)),
    bounded AS (
        SELECT g.scope_kind, g.code FROM g WHERE g.scope_kind IN ('faculty', 'department', 'programme')
         ORDER BY CASE g.scope_kind WHEN 'programme' THEN 1 WHEN 'department' THEN 2 ELSE 3 END, g.code NULLS FIRST LIMIT 1)
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM g) THEN 'none'
                WHEN EXISTS (SELECT 1 FROM g WHERE g.scope_kind NOT IN ('faculty', 'department', 'programme')) THEN 'institution'
                ELSE (SELECT b.scope_kind FROM bounded b) END,
           CASE WHEN EXISTS (SELECT 1 FROM g) AND NOT EXISTS (SELECT 1 FROM g WHERE g.scope_kind NOT IN ('faculty', 'department', 'programme'))
                THEN coalesce((SELECT b.code FROM bounded b), '__none__') END
$fn$;
COMMENT ON FUNCTION iam.dbops_scope(uuid) IS
  'V640: the scope a Database Operator is held to — institution (a grant not bounded), else the narrowest bounded grant (programme, department, faculty), else none; an unresolved scope reads nothing';

-- ── 2 · the period a readiness report reads when none is chosen ──────────────────────────────────────────────────────
CREATE FUNCTION reporting.readiness_period() RETURNS TABLE (session text, semester int)
LANGUAGE sql STABLE AS $fn$
    SELECT x.s,
           coalesce((SELECT m.number FROM policy.semester m WHERE m.session = x.s AND m.state = 'OPEN' ORDER BY m.number DESC LIMIT 1),
                    (SELECT max(m.number) FROM policy.semester m WHERE m.session = x.s AND m.state = 'CLOSED'), 1)
      FROM (SELECT policy.university_current_session() AS s) x
$fn$;
COMMENT ON FUNCTION reporting.readiness_period() IS 'V640: the University''s current session and its open semester (else the last closed one, else the first)';

-- ── 3 · examination readiness ────────────────────────────────────────────────────────────────────────────────────────
-- built on reporting.student_positions (V257, the one engine Student Statistics and every dashboard read): its population, its fee
-- position (finance.session_positions) and its registration across the three registers — the School of Postgraduate Studies'
-- (admissions.pg_registration), the College of Health Sciences' from 200 Level (college.enrolment) and the University's course
-- registration (registration.course_registration); to it are added the examination card's own payment test, the classification,
-- the academic status, and the University course registration's courses, units and carry-overs
CREATE FUNCTION reporting.exam_readiness(p_session text, p_semester int, p_fac text, p_dept text, p_prog text, p_level int, p_type text,
                                         p_course text, p_rule text)
RETURNS TABLE (
    student_id uuid, matric_no text, jamb_no text, surname text, other_names text, sex text, status text, academic_status text,
    programme_type text, admission_route text, study_mode text,
    faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level int, entry_session text,
    fee_status text, payable numeric, paid_amount numeric, outstanding numeric, last_paid_at timestamptz, fully_paid boolean, school_fees_paid boolean,
    registration_stream text, registration_status text, registration_level int, courses int, units int, carryovers int,
    course_registered boolean, course_entry_type text, course_expected text,
    paid boolean, registered boolean, exam_card boolean, readiness text, exception text)
LANGUAGE sql STABLE AS $fn$
    WITH sp AS MATERIALIZED (
        SELECT x.* FROM reporting.student_positions(p_session, p_semester) x
         WHERE (p_fac IS NULL OR x.faculty_code = p_fac)
           AND (p_dept IS NULL OR x.dept_code = p_dept)
           AND (p_prog IS NULL OR x.programme_code = p_prog)),
    st AS MATERIALIZED (
        SELECT sp.*, s.matric_no, s.jamb_reg_no, s.current_level AS cur_level, sc.programme_type, sc.admission_route, sc.study_mode,
               CASE WHEN sp.is_pg THEN 'POSTGRADUATE' WHEN sp.is_chs AND s.current_level >= 200 THEN 'COLLEGE' ELSE 'UNIVERSITY' END AS stream
          FROM sp
          JOIN people.student s ON s.id = sp.student_id
          LEFT JOIN people.student_classification sc ON sc.student_id = sp.student_id
         WHERE s.duplicate_of IS NULL
           AND (p_type IS NULL OR sc.programme_type = p_type)),
    -- the University course registration of the semester and its live courses (never a dropped or withdrawn one), as the card counts them
    reg AS MATERIALIZED (
        SELECT r.student_id, r.id, r.status, r.level,
               count(e.offering_id) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN'))::int AS courses,
               coalesce(sum(e.units) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')), 0)::int AS units,
               count(e.offering_id) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.entry_type = 'CARRYOVER')::int AS carryovers,
               max(e.entry_type) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = p_course) AS course_entry_type
          FROM registration.course_registration r
          LEFT JOIN registration.entry e ON e.registration_id = r.id
          LEFT JOIN catalogue.offering o ON o.id = e.offering_id
         WHERE r.session = p_session AND r.semester = p_semester
           AND r.student_id IN (SELECT st.student_id FROM st)
         GROUP BY r.student_id, r.id, r.status, r.level),
    -- school fees paid by the examination card's own test (registration.exam_card_paid): a confirmed school-fees payment for the
    -- session, of any amount and on any channel — never a pending, expired or unconfirmed reference
    cardpaid AS MATERIALIZED (
        SELECT DISTINCT x.student_id FROM reporting.payments x
         WHERE x.session = p_session AND x.confirmed_at IS NOT NULL AND x.purpose_code = 'SCHOOL_FEES' AND x.amount > 0
           AND x.student_id IS NOT NULL),
    pop AS (
        SELECT st.*, rg.id AS reg_id, rg.status AS reg_status, rg.level AS reg_level, coalesce(rg.courses, 0) AS n_courses,
               coalesce(rg.units, 0) AS n_units, coalesce(rg.carryovers, 0) AS n_carry, rg.course_entry_type AS c_entry,
               coalesce(rg.level, st.cur_level) AS lvl,
               (cp.student_id IS NOT NULL) AS card_paid,
               (rg.id IS NOT NULL AND rg.status <> 'DRAFT' AND coalesce(rg.courses, 0) > 0) AS card_reg
          FROM st
          LEFT JOIN reg rg ON rg.student_id = st.student_id
          LEFT JOIN cardpaid cp ON cp.student_id = st.student_id
         -- in study, a fresh student of the session, or anyone registered or paid for it (an admitted student of an earlier
         -- session who never came is not counted as owing, as the School Fees Report counts them)
         WHERE st.status IN ('ACTIVE', 'PROBATION')
            OR (st.status = 'ADMITTED' AND st.entry_session = p_session)
            OR st.registered OR cp.student_id IS NOT NULL),
    -- for a course: the programmes and levels the structure makes it compulsory for (never an elective)
    offer AS MATERIALIZED (
        SELECT co.programme_code, co.level, co.basis FROM catalogue.course_offer co
         WHERE p_course IS NOT NULL AND co.course_code = p_course AND co.basis <> 'Elective'),
    judged AS (
        SELECT pop.*,
               CASE WHEN coalesce(p_rule, 'CARD') = 'FULL' THEN pop.paid ELSE pop.card_paid END AS is_paid,
               (pop.c_entry IS NOT NULL AND coalesce(pop.reg_status, 'DRAFT') <> 'DRAFT') AS c_reg,
               (SELECT 'Programme structure: ' || o.level || ' Level (' || o.basis || ')' FROM offer o
                 WHERE o.programme_code = pop.programme_code AND o.level = pop.lvl LIMIT 1) AS c_expected
          FROM pop
         WHERE (p_level IS NULL OR pop.lvl = p_level)
           -- a course's readiness reads the University course registration; the College's and the School of Postgraduate
           -- Studies' courses are registered in their own registers
           AND (p_course IS NULL OR pop.stream = 'UNIVERSITY')),
    decided AS (
        SELECT j.*, CASE WHEN p_course IS NULL THEN j.registered ELSE j.c_reg END AS is_reg
          FROM judged j
         WHERE p_course IS NULL OR j.c_reg OR j.c_expected IS NOT NULL)
    SELECT d.student_id, d.matric_no, d.jamb_reg_no, d.surname, d.other_names, d.sex, d.status,
           CASE WHEN ap.spillover_state ~ '^SPILLOVER_YEAR_[0-9]+$' THEN 'SP' || substr(ap.spillover_state, 16)
                WHEN ap.spillover_state = 'SPILLOVER_LIMIT_REACHED' THEN 'BEYOND_MAXIMUM'
                ELSE d.status END,
           d.programme_type, d.admission_route, d.study_mode,
           d.faculty_code, d.faculty, d.dept_code, d.department, d.programme_code, d.programme, d.lvl, d.entry_session,
           d.pay_status, d.payable, d.paid_amount, d.outstanding, d.last_paid_at, d.paid, d.card_paid,
           d.stream, coalesce(d.registration_status, 'NONE'),
           CASE WHEN d.stream = 'UNIVERSITY' THEN d.reg_level END,
           CASE WHEN d.stream = 'UNIVERSITY' THEN d.n_courses END, CASE WHEN d.stream = 'UNIVERSITY' THEN d.n_units END,
           CASE WHEN d.stream = 'UNIVERSITY' THEN d.n_carry END,
           CASE WHEN p_course IS NULL THEN NULL ELSE d.c_reg END, CASE WHEN d.c_reg THEN d.c_entry END, d.c_expected,
           d.is_paid, d.is_reg,
           -- the examination card's own rule (registration.exam_card_state): paid and a submitted registration with a course
           CASE WHEN d.stream = 'UNIVERSITY' THEN d.card_paid AND d.card_reg END,
           CASE WHEN d.is_paid AND d.is_reg THEN 'PAID_REGISTERED'
                WHEN d.is_paid THEN 'PAID_NOT_REGISTERED'
                WHEN d.payable > 0 THEN 'NOT_PAID'
                ELSE 'NO_FEE_STATED' END,
           CASE WHEN d.stream = 'UNIVERSITY' AND d.reg_status = 'DRAFT' THEN 'REGISTRATION_NOT_SUBMITTED'
                WHEN d.stream = 'UNIVERSITY' AND d.reg_status = 'RETURNED' THEN 'REGISTRATION_RETURNED'
                WHEN d.stream = 'UNIVERSITY' AND d.registered AND d.n_courses = 0 THEN 'REGISTRATION_WITHOUT_COURSES'
                WHEN d.registered AND NOT d.is_paid AND d.payable > 0 THEN 'REGISTERED_NOT_PAID'
                WHEN d.registered AND NOT d.is_paid THEN 'REGISTERED_NO_FEE_STATED'
                WHEN NOT d.card_paid AND d.paid AND d.payable > 0 THEN 'FEES_SETTLED_NO_SCHOOL_FEES_PAYMENT'
                WHEN d.stream = 'UNIVERSITY' AND d.registered AND d.reg_status = 'SUBMITTED' THEN 'REGISTRATION_AWAITING_APPROVAL'
                WHEN d.is_paid AND d.pay_status = 'PART_PAYMENT' THEN 'PART_PAYMENT'
           END
      FROM decided d
      LEFT JOIN people.academic_position ap ON ap.student_id = d.student_id
     ORDER BY d.surname, d.other_names, d.matric_no
$fn$;
COMMENT ON FUNCTION reporting.exam_readiness(text, int, text, text, text, int, text, text, text) IS
  'V640: examination readiness, on reporting.student_positions (its population, fee position and registration across the postgraduate, College and University registers) — each student of the scope for a session and semester, paid by the examination card''s own test (rule CARD) or paid in full (rule FULL), registered or not, and the readiness PAID_REGISTERED / PAID_NOT_REGISTERED / NOT_PAID (a fee charged, not paid) / NO_FEE_STATED (nothing charged, never counted as not paid); for a course, registered for it on the University course registration or expected by the programme structure; exam_card is the card''s own rule';

CREATE FUNCTION reporting.exam_readiness_summary(p_session text, p_semester int, p_fac text, p_dept text, p_prog text, p_level int,
                                                 p_type text, p_course text, p_rule text, p_by text)
RETURNS TABLE (key text, label text, total bigint, paid_registered bigint, paid_not_registered bigint, not_paid bigint,
               not_paid_registered bigint, no_fee_stated bigint, part_paid bigint, exam_cards bigint, exceptions bigint)
LANGUAGE sql STABLE AS $fn$
    WITH r AS (
        SELECT x.*,
               CASE p_by WHEN 'faculty' THEN x.faculty_code WHEN 'department' THEN x.dept_code WHEN 'programme' THEN x.programme_code
                         WHEN 'level' THEN x.level::text WHEN 'type' THEN coalesce(x.programme_type, 'UNCLASSIFIED')
                         WHEN 'status' THEN x.academic_status ELSE 'ALL' END AS k,
               CASE p_by WHEN 'faculty' THEN x.faculty WHEN 'department' THEN x.department WHEN 'programme' THEN x.programme
                         WHEN 'level' THEN x.level || ' Level'
                         WHEN 'type' THEN coalesce((SELECT t.label FROM finance.programme_type t WHERE t.code = x.programme_type), 'Unclassified')
                         WHEN 'status' THEN initcap(replace(x.academic_status, '_', ' ')) ELSE 'All students' END AS l
          FROM reporting.exam_readiness(p_session, p_semester, p_fac, p_dept, p_prog, p_level, p_type, p_course, p_rule) x)
    SELECT r.k, max(r.l), count(*),
           count(*) FILTER (WHERE r.readiness = 'PAID_REGISTERED'),
           count(*) FILTER (WHERE r.readiness = 'PAID_NOT_REGISTERED'),
           count(*) FILTER (WHERE r.readiness = 'NOT_PAID'),
           count(*) FILTER (WHERE r.readiness = 'NOT_PAID' AND r.registered),
           count(*) FILTER (WHERE r.readiness = 'NO_FEE_STATED'),
           count(*) FILTER (WHERE r.paid AND r.fee_status = 'PART_PAYMENT'),
           count(*) FILTER (WHERE r.exam_card),
           count(*) FILTER (WHERE r.exception IS NOT NULL AND r.exception <> 'PART_PAYMENT')
      FROM r
     GROUP BY r.k
     ORDER BY CASE WHEN p_by = 'level' THEN lpad(r.k, 4, '0') ELSE max(r.l) END
$fn$;
COMMENT ON FUNCTION reporting.exam_readiness_summary(text, int, text, text, text, int, text, text, text, text) IS
  'V640: the readiness counted by faculty, department, programme, level, programme type or academic status — every number the students reporting.exam_readiness lists with the same filters';

CREATE FUNCTION reporting.course_readiness_summary(p_session text, p_semester int, p_fac text, p_dept text, p_prog text,
                                                   p_course_fac text, p_course_dept text, p_level int, p_rule text)
RETURNS TABLE (course_code text, title text, units int, dept_code text, department text,
               registered bigint, registered_paid bigint, registered_not_paid bigint, registered_no_fee bigint,
               expected bigint, expected_not_registered bigint, expected_not_registered_paid bigint, not_paid bigint)
LANGUAGE sql STABLE AS $fn$
    -- the students of the scope on the University course registration, read once with what each paid; the courses the owning
    -- faculty or department offers in the semester
    WITH pop AS MATERIALIZED (
        SELECT x.student_id, x.programme_code, x.level, x.paid, x.payable
          FROM reporting.exam_readiness(p_session, p_semester, p_fac, p_dept, p_prog, NULL, NULL, NULL, p_rule) x
         WHERE x.registration_stream = 'UNIVERSITY'),
    crs AS MATERIALIZED (
        SELECT DISTINCT c.code, c.title, c.units, c.dept_code, d.name AS department
          FROM catalogue.offering o
          JOIN catalogue.course c ON c.code = o.course_code
          LEFT JOIN ref.department d ON d.code = c.dept_code
         WHERE o.session = p_session AND o.semester = p_semester
           AND (p_course_dept IS NULL OR c.dept_code = p_course_dept)
           AND (p_course_fac IS NULL OR d.faculty_code = p_course_fac)),
    ent AS MATERIALIZED (
        SELECT DISTINCT r.student_id, o.course_code
          FROM registration.course_registration r
          JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
          JOIN catalogue.offering o ON o.id = e.offering_id AND o.session = p_session AND o.semester = p_semester
         WHERE r.session = p_session AND r.semester = p_semester AND r.status <> 'DRAFT'
           AND o.course_code IN (SELECT crs.code FROM crs)
           AND r.student_id IN (SELECT pop.student_id FROM pop)),
    exp AS MATERIALIZED (
        SELECT DISTINCT p.student_id, co.course_code
          FROM pop p
          JOIN catalogue.course_offer co ON co.programme_code = p.programme_code AND co.level = p.level AND co.basis <> 'Elective'
         WHERE co.course_code IN (SELECT crs.code FROM crs)
           AND (p_level IS NULL OR p.level = p_level)),
    cs AS (
        SELECT u.course_code, u.student_id,
               EXISTS (SELECT 1 FROM ent e WHERE e.student_id = u.student_id AND e.course_code = u.course_code) AS reg,
               EXISTS (SELECT 1 FROM exp x WHERE x.student_id = u.student_id AND x.course_code = u.course_code) AS expd
          FROM (SELECT ent.student_id, ent.course_code FROM ent UNION SELECT exp.student_id, exp.course_code FROM exp) u)
    SELECT c.code, c.title, c.units, c.dept_code, c.department,
           count(cs.student_id) FILTER (WHERE cs.reg),
           count(cs.student_id) FILTER (WHERE cs.reg AND p.paid),
           count(cs.student_id) FILTER (WHERE cs.reg AND NOT p.paid AND p.payable > 0),
           count(cs.student_id) FILTER (WHERE cs.reg AND NOT p.paid AND p.payable = 0),
           count(cs.student_id) FILTER (WHERE cs.expd),
           count(cs.student_id) FILTER (WHERE cs.expd AND NOT cs.reg),
           count(cs.student_id) FILTER (WHERE cs.expd AND NOT cs.reg AND p.paid),
           count(cs.student_id) FILTER (WHERE NOT p.paid AND p.payable > 0)
      FROM crs c
      LEFT JOIN cs ON cs.course_code = c.code
      LEFT JOIN pop p ON p.student_id = cs.student_id
     GROUP BY c.code, c.title, c.units, c.dept_code, c.department
     ORDER BY c.code
$fn$;
COMMENT ON FUNCTION reporting.course_readiness_summary(text, int, text, text, text, text, text, int, text) IS
  'V640: each course a faculty or department offers in the semester — registered, of them paid, not paid and no fee stated; expected by the programme structure, and of them not registered (and paid); the students those numbers count are reporting.exam_readiness with the course';

-- ── 4 · official report references: DBO/<KIND>/YYYY/NNNNNN ────────────────────────────────────────────────────────────
CREATE TABLE reporting.report_counter (
    kind text NOT NULL,
    year int  NOT NULL,
    last int  NOT NULL DEFAULT 0,
    PRIMARY KEY (kind, year)
);
COMMENT ON TABLE reporting.report_counter IS 'V640: the counter behind the official report references, one a kind and year';
SELECT audit.exempt('reporting.report_counter', 'The counter behind official report references; every reference issued is a row of reporting.official_report on the spine.');

CREATE TABLE reporting.official_report (
    reference    text PRIMARY KEY CHECK (reference ~ '^DBO/[A-Z]{2,10}/[0-9]{4}/[0-9]{6}$'),
    kind         text NOT NULL CHECK (kind IN ('EXAM', 'STUDENT', 'PAYMENT', 'REG', 'COURSE', 'QUERY', 'QUALITY')),
    title        text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 300),
    filters      jsonb NOT NULL DEFAULT '{}'::jsonb,
    scope        text,
    figures      jsonb,
    row_count    int,
    parts        jsonb,
    generated_by uuid NOT NULL,
    actor_office text NOT NULL,
    generated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_official_report_at ON reporting.official_report (generated_at DESC);
COMMENT ON TABLE reporting.official_report IS
  'V640: an official report issued — its reference (DBO/<KIND>/YYYY/NNNNNN), title, the filters and scope it was drawn with, the figures, the number of rows, the parts of a package, who issued it and when; the data is read at that moment';
SELECT audit.attach('reporting.official_report');

CREATE FUNCTION reporting.issue_report(p_kind text, p_title text, p_filters jsonb, p_scope text, p_figures jsonb, p_rows int, p_parts jsonb)
RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        y int := extract(year FROM (now() AT TIME ZONE 'Africa/Lagos'))::int; n int; v_ref text;
BEGIN
    IF who IS NULL OR office IS NULL THEN
        RAISE EXCEPTION 'REPORT_PERSON: an official report is issued by a person acting in an office' USING ERRCODE = '42501';
    END IF;
    IF p_kind IS NULL OR p_kind NOT IN ('EXAM', 'STUDENT', 'PAYMENT', 'REG', 'COURSE', 'QUERY', 'QUALITY') THEN
        RAISE EXCEPTION 'REPORT_KIND: % is not a kind of official report', coalesce(p_kind, 'nothing') USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_title, ''))) < 3 THEN
        RAISE EXCEPTION 'REPORT_TITLE: an official report says what it is' USING ERRCODE = '23514';
    END IF;
    INSERT INTO reporting.report_counter AS c (kind, year, last) VALUES (p_kind, y, 1)
    ON CONFLICT (kind, year) DO UPDATE SET last = c.last + 1
    RETURNING c.last INTO n;
    v_ref := 'DBO/' || p_kind || '/' || y || '/' || lpad(n::text, 6, '0');
    INSERT INTO reporting.official_report (reference, kind, title, filters, scope, figures, row_count, parts, generated_by, actor_office)
    VALUES (v_ref, p_kind, btrim(p_title), coalesce(p_filters, '{}'::jsonb), p_scope, p_figures, p_rows, p_parts, who, office);
    RETURN v_ref;
END $fn$;
COMMENT ON FUNCTION reporting.issue_report(text, text, jsonb, text, jsonb, int, jsonb) IS
  'V640: an official report''s reference issued and its register row written — DBO/<KIND>/YYYY/NNNNNN from a per-year counter, never a table''s own key';

-- ── 5 · saved and shared queries and reports; the query log ─────────────────────────────────────────────────────────────
CREATE TABLE reporting.saved_query (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name           text NOT NULL CHECK (length(btrim(name)) BETWEEN 3 AND 150),
    description    text CHECK (description IS NULL OR length(description) <= 1000),
    kind           text NOT NULL CHECK (kind IN ('QUERY', 'EXAM_READINESS')),
    source         text NOT NULL CHECK (source ~ '^[A-Z_]{3,40}$'),
    definition     jsonb NOT NULL CHECK (jsonb_typeof(definition) = 'object'),
    owner_id       uuid NOT NULL,
    owner_office   text NOT NULL,
    shared_offices text[] NOT NULL DEFAULT '{}',
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    archived_at    timestamptz
);
CREATE UNIQUE INDEX ux_saved_query_name ON reporting.saved_query (owner_id, lower(btrim(name))) WHERE archived_at IS NULL;
CREATE INDEX ix_saved_query_shared ON reporting.saved_query USING gin (shared_offices) WHERE archived_at IS NULL;
COMMENT ON TABLE reporting.saved_query IS
  'V640: a saved query or report — the definition (source, filters, columns, grouping, sort, layout), never SQL and never a credential; kept by its owner, shared with offices by its owner, archived and never deleted';
SELECT audit.attach('reporting.saved_query');

-- the owner alone changes or shares a saved query; it is archived, never deleted; the offices it is shared with are on the register
CREATE FUNCTION reporting.guard_saved_query() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; bad text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'SAVED_QUERY_KEPT: a saved query is archived, never deleted' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND (who IS NULL OR who <> OLD.owner_id) THEN
        RAISE EXCEPTION 'SAVED_QUERY_OWNER: a saved query is changed by its owner alone' USING ERRCODE = '42501';
    END IF;
    IF TG_OP = 'UPDATE' AND (NEW.owner_id <> OLD.owner_id OR NEW.created_at <> OLD.created_at) THEN
        RAISE EXCEPTION 'SAVED_QUERY_OWNER: a saved query keeps its owner' USING ERRCODE = '42501';
    END IF;
    SELECT string_agg(x, ', ') INTO bad FROM unnest(NEW.shared_offices) x WHERE NOT EXISTS (SELECT 1 FROM ref.office o WHERE o.code = x);
    IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'SAVED_QUERY_OFFICE: % is not an office of the University', bad USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_guard_saved_query BEFORE INSERT OR UPDATE OR DELETE ON reporting.saved_query
    FOR EACH ROW EXECUTE FUNCTION reporting.guard_saved_query();

CREATE TABLE reporting.query_log (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at             timestamptz NOT NULL DEFAULT now(),
    actor_id       uuid NOT NULL,
    actor_office   text NOT NULL,
    action         text NOT NULL CHECK (action IN ('RUN', 'EXPORT', 'PRINT', 'SAVE', 'SHARE', 'ARCHIVE', 'ISSUE')),
    source         text NOT NULL,
    title          text,
    definition     jsonb,
    scope          text,
    row_count      int,
    reference      text,
    format         text CHECK (format IS NULL OR format IN ('XLSX', 'PDF', 'PRINT', 'SCREEN')),
    -- the saved query the line is about; no foreign key: the line is written in its own transaction, ahead of the act it records
    saved_query_id uuid
);
CREATE INDEX ix_query_log_actor ON reporting.query_log (actor_id, at DESC);
CREATE INDEX ix_query_log_at ON reporting.query_log (at DESC);
COMMENT ON TABLE reporting.query_log IS
  'V640: every query run, report exported or printed, query saved or shared and official report issued by the Database Operations office and the offices reading its reports — who, as which office, what source, which filters, the scope, how many rows, the reference; never a credential';
SELECT audit.exempt('reporting.query_log', 'The query log is itself the record of every query and report; it is append-only.');

CREATE FUNCTION reporting.guard_query_log() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    RAISE EXCEPTION 'QUERY_LOG_KEPT: the query log is kept as written' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_guard_query_log BEFORE UPDATE OR DELETE ON reporting.query_log
    FOR EACH ROW EXECUTE FUNCTION reporting.guard_query_log();

-- ── 6 · data quality ─────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION reporting.data_quality_rows(p_fac text, p_dept text, p_prog text, p_session text, p_semester int)
RETURNS TABLE (kind text, student_id uuid, detail text)
LANGUAGE sql STABLE AS $fn$
    WITH st AS MATERIALIZED (
        SELECT s.id, s.status, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.current_level, s.programme_code,
               p.code AS p_code, p.archived AS p_archived, p.dept_code, p.faculty_code, d.code AS d_code, f.code AS f_code,
               s.status <> ALL (ARRAY['GRADUATED', 'COMPLETED', 'WITHDRAWN', 'VOLUNTARY_WITHDRAWAL', 'EXPELLED', 'TRANSFERRED_OUT', 'DECEASED', 'PROGRESSED', 'MERGED']) AS live
          FROM people.student s
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN ref.faculty f ON f.code = p.faculty_code
         WHERE s.duplicate_of IS NULL
           AND (p_fac IS NULL OR p.faculty_code = p_fac)
           AND (p_dept IS NULL OR p.dept_code = p_dept)
           AND (p_prog IS NULL OR p.code = p_prog)),
    ap AS MATERIALIZED (
        SELECT a.student_id, a.issues, a.spillover_years, a.current_session, a.current_level, a.computed_level
          FROM people.academic_position a WHERE a.student_id IN (SELECT st.id FROM st)),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting WHERE row_no)
    SELECT 'INVALID_PROGRAMME', st.id, coalesce('programme ' || st.programme_code || ' is archived', 'programme ' || coalesce(st.programme_code, '—') || ' is not on the register')
      FROM st WHERE st.live AND (st.p_code IS NULL OR st.p_archived)
    UNION ALL
    SELECT 'MISSING_FACULTY_DEPARTMENT', st.id, 'programme ' || st.programme_code || ' has ' || CASE WHEN st.d_code IS NULL THEN 'no department' ELSE 'no faculty' END
      FROM st WHERE st.live AND st.p_code IS NOT NULL AND (st.d_code IS NULL OR st.f_code IS NULL)
    UNION ALL
    SELECT 'MISSING_ENTRY_SESSION', st.id, coalesce('entry session ' || st.entry_session || ' is not a session of the University', 'no entry session')
      FROM st WHERE st.live AND (st.entry_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = st.entry_session))
    UNION ALL
    SELECT 'INVALID_LEVEL', st.id, 'level on record ' || coalesce(st.current_level::text, 'none') || coalesce(', entry level ' || st.entry_level, '')
      FROM st WHERE st.live AND (st.current_level IS NULL OR st.current_level % 100 <> 0 OR st.current_level NOT BETWEEN 100 AND 900
                                 OR (st.entry_level IS NOT NULL AND st.current_level < st.entry_level))
    UNION ALL
    SELECT 'MISSING_MATRIC', st.id, 'in study as ' || lower(st.status) || ' with no matriculation number'
      FROM st WHERE st.status IN ('ACTIVE', 'PROBATION') AND nullif(btrim(coalesce(st.matric_no, '')), '') IS NULL
    UNION ALL
    SELECT 'DUPLICATE_MATRIC', st.id, 'matriculation number ' || st.matric_no || ' is held by ' || x.n || ' records'
      FROM st JOIN (SELECT upper(btrim(s2.matric_no)) AS k, count(*) AS n FROM people.student s2
                     WHERE s2.duplicate_of IS NULL AND nullif(btrim(coalesce(s2.matric_no, '')), '') IS NOT NULL
                     GROUP BY 1 HAVING count(*) > 1) x ON x.k = upper(btrim(st.matric_no))
    UNION ALL
    SELECT 'DUPLICATE_JAMB', st.id, 'JAMB number ' || st.jamb_reg_no || ' is held by ' || x.n || ' records'
      FROM st JOIN (SELECT upper(btrim(s2.jamb_reg_no)) AS k, count(*) AS n FROM people.student s2
                     WHERE s2.duplicate_of IS NULL AND nullif(btrim(coalesce(s2.jamb_reg_no, '')), '') IS NOT NULL
                     GROUP BY 1 HAVING count(*) > 1) x ON x.k = upper(btrim(st.jamb_reg_no))
    UNION ALL
    SELECT 'UNCLASSIFIED', st.id, coalesce('requires classification: ' || sc.classification_issue, 'no programme type')
      FROM st LEFT JOIN people.student_classification sc ON sc.student_id = st.id
     WHERE st.live AND (sc.student_id IS NULL OR sc.programme_type IS NULL)
    UNION ALL
    SELECT 'CONFLICTING_STATUS', st.id, array_to_string(ARRAY(SELECT i FROM unnest(ap.issues) i WHERE i IN ('GRADUATED_WITHOUT_APPROVAL', 'DEFERRED_WITHOUT_LIVE_DEFERMENT')), ', ')
      FROM st JOIN ap ON ap.student_id = st.id
     WHERE ap.issues && ARRAY['GRADUATED_WITHOUT_APPROVAL', 'DEFERRED_WITHOUT_LIVE_DEFERMENT']
    UNION ALL
    SELECT 'GRADUATED_STILL_ACTIVE', st.id, 'the award is approved and the record reads ' || lower(st.status)
      FROM st JOIN ap ON ap.student_id = st.id WHERE 'APPROVED_NOT_GRADUATED' = ANY (ap.issues)
    UNION ALL
    SELECT 'LEVEL_INCONSISTENT', st.id, 'level on record ' || coalesce(ap.current_level::text, '—') || ', computed ' || coalesce(ap.computed_level::text, '—')
      FROM st JOIN ap ON ap.student_id = st.id WHERE st.live AND 'LEVEL_CONFLICT' = ANY (ap.issues)
    UNION ALL
    SELECT 'BEYOND_MAXIMUM_PERIOD', st.id, ap.spillover_years || ' sessions beyond the expected completion; ' || cfg.max_spillover_years || ' allowed'
      FROM st JOIN ap ON ap.student_id = st.id CROSS JOIN cfg
     WHERE st.status IN ('ACTIVE', 'PROBATION') AND ap.current_session IS NOT NULL AND ap.spillover_years > cfg.max_spillover_years
    UNION ALL
    SELECT CASE r.readiness WHEN 'PAID_NOT_REGISTERED' THEN 'PAID_NOT_REGISTERED' ELSE 'REGISTERED_NOT_PAID' END, r.student_id,
           p_session || ' semester ' || p_semester || ': ' || CASE r.readiness WHEN 'PAID_NOT_REGISTERED' THEN 'school fees paid, no registration with courses'
                                                                ELSE 'registered, no school-fees payment (₦' || r.outstanding || ' outstanding)' END
      FROM reporting.exam_readiness(p_session, p_semester, p_fac, p_dept, p_prog, NULL, NULL, NULL, 'CARD') r
     WHERE p_session IS NOT NULL AND p_semester IS NOT NULL
       AND (r.readiness = 'PAID_NOT_REGISTERED' OR (r.readiness = 'NOT_PAID' AND r.registered))
$fn$;
COMMENT ON FUNCTION reporting.data_quality_rows(text, text, text, text, int) IS
  'V640: each record of the scope with a data fault, by kind — invalid programme, missing faculty or department, missing or invalid entry session, invalid level, missing or duplicate matriculation number, duplicate JAMB number, unclassified, conflicting statuses, graduated still active, level inconsistent, beyond the maximum period, and for a session and semester paid not registered and registered not paid';

CREATE FUNCTION reporting.data_quality(p_fac text, p_dept text, p_prog text, p_session text, p_semester int)
RETURNS TABLE (kind text, label text, area text, n bigint)
LANGUAGE sql STABLE AS $fn$
    WITH k(kind, label, area, ord) AS (VALUES
        ('INVALID_PROGRAMME', 'Programme not valid', 'Academic structure', 1),
        ('MISSING_FACULTY_DEPARTMENT', 'Programme without faculty or department', 'Academic structure', 2),
        ('MISSING_ENTRY_SESSION', 'Missing or invalid entry session', 'Academic record', 3),
        ('INVALID_LEVEL', 'Invalid level', 'Academic record', 4),
        ('LEVEL_INCONSISTENT', 'Level on record differs from the computed level (SP1/SP2)', 'Academic record', 5),
        ('MISSING_MATRIC', 'In study without a matriculation number', 'Identity', 6),
        ('DUPLICATE_MATRIC', 'Duplicate matriculation number', 'Identity', 7),
        ('DUPLICATE_JAMB', 'Duplicate JAMB number', 'Identity', 8),
        ('UNCLASSIFIED', 'Unclassified (no programme type)', 'Classification', 9),
        ('CONFLICTING_STATUS', 'Conflicting status', 'Status', 10),
        ('GRADUATED_STILL_ACTIVE', 'Award approved, still kept in study', 'Status', 11),
        ('BEYOND_MAXIMUM_PERIOD', 'Beyond the maximum academic period', 'Status', 12),
        ('PAID_NOT_REGISTERED', 'Paid school fees, not registered', 'Payment and registration', 13),
        ('REGISTERED_NOT_PAID', 'Registered, school fees not paid', 'Payment and registration', 14)),
    r AS (SELECT q.kind, count(*) AS n FROM reporting.data_quality_rows(p_fac, p_dept, p_prog, p_session, p_semester) q GROUP BY q.kind)
    SELECT k.kind, k.label, k.area, coalesce(r.n, 0) FROM k LEFT JOIN r ON r.kind = k.kind ORDER BY k.ord
$fn$;
COMMENT ON FUNCTION reporting.data_quality(text, text, text, text, int) IS 'V640: the data quality figures of a scope, every kind with its count (nil included), each opening reporting.data_quality_rows';

GRANT SELECT ON reporting.official_report, reporting.saved_query, reporting.query_log TO app_auditor, app_reporting;

COMMIT;
