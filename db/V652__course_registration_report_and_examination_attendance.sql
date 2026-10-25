-- ═══════════════════════════════════════
-- V652 — The course registration report and examination attendance
--
-- The University's master prompt of 25 October 2026 ("central course registration, GST, EPS & examination attendance reporting
-- engine"), with its answers: this round builds what the portal did not have — the course registration report (one row per student
-- and course), the examination attendance sheet with its manual / late-registration rows, the attendance recorded after the paper
-- (the list marked, the handwritten rows entered, those not identified held for verification) and the reconciliation — and lists on
-- the sheet every student with the course on a submitted or approved registration, marking who holds the examination card or the
-- GST & EPS permit. The statistics, the payment-versus-registration figures and the director dashboards stay the master report's
-- (V650); the registration engine, the card (V567) and the permit (V589) stay what they are.
--
--   · reporting.course_registration_rows(session, semester, filters): one row a student and course — the student, where they sit,
--     the registration and its status, the course by its own key (catalogue.shown_code for the code shown, V646), units, category
--     (GST, EPS, departmental, faculty, other), curriculum, carry-over, whether the card or the permit is held; filtered by faculty,
--     department, programme, level, course, category, the GST or EPS office's own courses, curriculum, sex, registration status,
--     carry-over, eligibility, dates and a search. reporting.course_registration_summary counts them once by every dimension;
--     reporting.course_registration_courses gives each course its registered, sex, eligibility and attendance figures.
--   · assessment.exam_attendance_sheet: an attendance sheet issued for a course (its class, catalogue.offering) within a scope
--     (faculty, department, programme, or the whole class), with its reference ATT/<code>/<year>/<nnnnn>/V<k>; a later sheet for the
--     same course and scope is a new version, the earlier kept as printed (the list held as it was, the examination date, time and
--     venue from assessment.exam_timetable where stated, the manual lines, who and when). assessment.issue_attendance_sheet.
--   · assessment.exam_attendance: one record a student and course — PRESENT, ABSENT, LATE, MANUAL_PRESENT, EXCUSED or
--     INVALID_ATTENDANCE, from the list (LIST) or a handwritten row (MANUAL), the sheet it was taken on, the invigilator, who recorded
--     and who verified it. assessment.exam_attendance_pending: a handwritten row whose student is not identified yet (PENDING), then
--     matched or found invalid. assessment.record_attendance, assessment.manual_attendance (matched by people.resolve_student, V647:
--     matriculation, admission, JAMB or application number), assessment.decide_manual_attendance. No student, registration or
--     result is created by an attendance.
--   · assessment.attendance_reconciliation(offering, scope): each student registered, listed or recorded, with what the record shows
--     and the finding — OK, REGISTERED_NOT_ON_LIST (registered after the sheet), ON_LIST_NOT_REGISTERED (dropped since), PRESENT_NOT_
--     REGISTERED (marked present, no registration and not on the latest sheet), PRESENT_NOT_ELIGIBLE, MANUAL_NOT_REGISTERED, NOT_MARKED.
-- The attendance tables go with their class and student (ON DELETE CASCADE), as the go-live data reset clears both.
-- The three report functions run with jit = off: on the live-shaped copy the JIT compile took 1–2 s of a 0.3 s read.
-- The offices who issue sheets and record attendance: the Examinations Officers (programme), the Faculty Examinations Officer, Exams
-- and Records, the Head of Department, the GST and EPS offices (their own courses), the Academic Office and the Registry; the API
-- holds each to its scope (OfficeScope).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V652: the course registration report and examination attendance', true);

-- ── 1 · the course registration report ──────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION reporting.course_registration_rows(p_session text, p_semester int, p_f jsonb)
RETURNS TABLE (
    student_id uuid, matric_no text, jamb_no text, full_name text, sex text,
    faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, programme_category text,
    admission_route text, study_mode text, centre_code text, level int, session text, semester int,
    registration_id uuid, registration_status text, submitted_at timestamptz, approved_at timestamptz,
    offering_id uuid, course_code text, shown_code text, course_title text, units int, category text, course_kind text, curriculum text,
    course_dept text, entry_type text, entry_status text, carry_over boolean, added_as text,
    holds_card boolean, holds_permit boolean, eligible boolean)
LANGUAGE sql STABLE SET jit = off AS $$
    WITH f AS (SELECT nullif(btrim(p_f->>'fac'), '') AS fac, nullif(btrim(p_f->>'dept'), '') AS dept, nullif(btrim(p_f->>'prog'), '') AS prog,
                      (nullif(btrim(p_f->>'level'), ''))::int AS lvl, nullif(btrim(p_f->>'course'), '') AS course,
                      (nullif(btrim(p_f->>'offering'), ''))::uuid AS offering, upper(nullif(btrim(p_f->>'category'), '')) AS category,
                      upper(nullif(btrim(p_f->>'office'), '')) AS office, upper(nullif(btrim(p_f->>'curriculum'), '')) AS curriculum,
                      upper(nullif(btrim(p_f->>'sex'), '')) AS sex, upper(nullif(btrim(p_f->>'reg'), '')) AS reg,
                      upper(nullif(btrim(p_f->>'eligible'), '')) AS eligible, (nullif(btrim(p_f->>'from'), ''))::date AS d_from,
                      (nullif(btrim(p_f->>'to'), ''))::date AS d_to, nullif(btrim(p_f->>'q'), '') AS q,
                      coalesce((p_f->>'dropped')::boolean, false) AS with_dropped),
    x AS (
        SELECT s.id AS student_id, s.matric_no, coalesce(s.jamb_reg_no, (SELECT c2.jamb_reg_no FROM admissions.candidate c2 WHERE c2.id = s.candidate_id)) AS jamb_no,
               upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, upper(left(coalesce(s.sex, ''), 1)) AS sex,
               d.faculty_code, fa.name AS faculty, p.dept_code, d.name AS department, p.code AS programme_code, p.name AS programme, p.category AS programme_category,
               s.entry_mode AS admission_route, s.study_mode, s.centre_code, r.level, r.session, r.semester,
               r.id AS registration_id, r.status AS registration_status, r.submitted_at, r.approved_at,
               o.id AS offering_id, c.code AS course_code, catalogue.shown_code(c.code) AS shown_code, c.title AS course_title, e.units,
               CASE WHEN c.kind = 'GST' AND c.general_office = 'GST' THEN 'GST'
                    WHEN c.kind = 'GST' AND c.general_office = 'EPS' THEN 'EPS'
                    WHEN c.dept_code = p.dept_code THEN 'DEPARTMENTAL'
                    WHEN cd.faculty_code = d.faculty_code THEN 'FACULTY'
                    ELSE 'OTHER' END AS category,
               c.kind AS course_kind, c.curriculum, c.dept_code AS course_dept, e.entry_type, e.status AS entry_status,
               e.entry_type = 'CARRYOVER' AS carry_over, e.added_as,
               EXISTS (SELECT 1 FROM registration.exam_card_issue ci WHERE ci.student_id = s.id AND ci.session = r.session AND ci.semester = r.semester) AS holds_card,
               EXISTS (SELECT 1 FROM registration.gst_eps_permit pm WHERE pm.student_id = s.id AND pm.session = r.session AND pm.semester = r.semester
                          AND pm.revoked_at IS NULL) AS holds_permit
          FROM f
          JOIN registration.course_registration r ON r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
          JOIN registration.entry e ON e.registration_id = r.id
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN ref.faculty fa ON fa.code = d.faculty_code
          LEFT JOIN ref.department cd ON cd.code = c.dept_code
         WHERE (f.with_dropped OR e.status NOT IN ('DROPPED', 'WITHDRAWN'))
           AND (f.fac IS NULL OR d.faculty_code = f.fac) AND (f.dept IS NULL OR p.dept_code = f.dept) AND (f.prog IS NULL OR p.code = f.prog)
           AND (f.lvl IS NULL OR r.level = f.lvl)
           AND (f.offering IS NULL OR o.id = f.offering)
           AND (f.course IS NULL OR c.code = upper(f.course) OR catalogue.shown_code(c.code) = upper(f.course))
           AND (f.office IS NULL OR (c.kind = 'GST' AND c.general_office = f.office))
           AND (f.curriculum IS NULL OR c.curriculum = f.curriculum)
           AND (f.reg IS NULL OR r.status = f.reg)
           AND (f.d_from IS NULL OR coalesce(r.submitted_at, r.approved_at)::date >= f.d_from)
           AND (f.d_to IS NULL OR coalesce(r.submitted_at, r.approved_at)::date <= f.d_to))
    SELECT x.*, CASE WHEN x.category IN ('GST', 'EPS') THEN x.holds_permit ELSE x.holds_card END AS eligible
      FROM x CROSS JOIN f
     WHERE (f.category IS NULL OR CASE f.category
                WHEN 'CARRY_OVER' THEN x.carry_over
                WHEN 'OTHER_COURSES' THEN x.category NOT IN ('GST', 'EPS')
                ELSE x.category = f.category END)
       AND (f.sex IS NULL OR CASE f.sex WHEN 'U' THEN x.sex NOT IN ('M', 'F') ELSE x.sex = f.sex END)
       AND (f.eligible IS NULL OR (f.eligible = 'YES') = CASE WHEN x.category IN ('GST', 'EPS') THEN x.holds_permit ELSE x.holds_card END)
       AND (f.q IS NULL OR x.full_name ILIKE '%' || f.q || '%' OR coalesce(x.matric_no, '') ILIKE '%' || f.q || '%'
            OR coalesce(x.jamb_no, '') ILIKE '%' || f.q || '%' OR x.course_code ILIKE '%' || f.q || '%' OR x.course_title ILIKE '%' || f.q || '%')
$$;
COMMENT ON FUNCTION reporting.course_registration_rows(text, int, jsonb) IS
  'V652: the course registration report — one row a student and course registered in the session (and semester), the dropped and withdrawn left out unless asked for: the student, faculty, department, programme, level, the registration and its status, the course by its own key with the code shown, units, category (GST, EPS, DEPARTMENTAL, FACULTY, OTHER), curriculum, carry-over, and whether the examination card or the GST & EPS permit is held (eligible: the permit for a GST/EPS course, the card for any other). Filters: fac, dept, prog, level, course (key or code shown), offering, category (also CARRY_OVER, OTHER_COURSES), office (GST or EPS: that office''s courses), curriculum, sex (M, F, U), reg (status), eligible (YES, NO), from, to, q, dropped.';

CREATE FUNCTION reporting.course_registration_summary(p_session text, p_semester int, p_f jsonb)
RETURNS TABLE (dimension text, key text, label text, registrations int, students int, male int, female int, other_sex int, carry_over int, eligible int)
LANGUAGE sql STABLE SET jit = off AS $$
    WITH r AS (SELECT * FROM reporting.course_registration_rows(p_session, p_semester, p_f))
    SELECT CASE WHEN GROUPING(r.category) = 0 THEN 'CATEGORY' WHEN GROUPING(r.faculty_code) = 0 THEN 'FACULTY' WHEN GROUPING(r.dept_code) = 0 THEN 'DEPARTMENT'
                WHEN GROUPING(r.programme_code) = 0 THEN 'PROGRAMME' WHEN GROUPING(r.level) = 0 THEN 'LEVEL' WHEN GROUPING(r.sex) = 0 THEN 'SEX'
                WHEN GROUPING(r.offering_id) = 0 THEN 'COURSE' ELSE 'TOTAL' END,
           coalesce(r.category, r.faculty_code, r.dept_code, r.programme_code, r.level::text, r.sex, r.offering_id::text, ''),
           coalesce(CASE WHEN GROUPING(r.category) = 0 THEN r.category END, r.faculty, r.department, r.programme, r.level::text,
                    CASE WHEN GROUPING(r.sex) = 0 THEN CASE r.sex WHEN 'M' THEN 'Male' WHEN 'F' THEN 'Female' ELSE 'Not stated' END END,
                    CASE WHEN GROUPING(r.offering_id) = 0 THEN max(r.shown_code) || ' — ' || max(r.course_title) END, 'All'),
           count(*)::int, count(DISTINCT r.student_id)::int,
           count(DISTINCT r.student_id) FILTER (WHERE r.sex = 'M')::int, count(DISTINCT r.student_id) FILTER (WHERE r.sex = 'F')::int,
           count(DISTINCT r.student_id) FILTER (WHERE r.sex NOT IN ('M', 'F'))::int,
           count(*) FILTER (WHERE r.carry_over)::int, count(*) FILTER (WHERE r.eligible)::int
      FROM r
     GROUP BY GROUPING SETS ((), (r.category), (r.faculty_code, r.faculty), (r.dept_code, r.department), (r.programme_code, r.programme), (r.level), (r.sex), (r.offering_id))
$$;
COMMENT ON FUNCTION reporting.course_registration_summary(text, int, jsonb) IS
  'V652: the course registration report counted once by every dimension — the whole, category, faculty, department, programme, level, sex and course: registrations, students (each once), male, female, not stated, carry-overs, registrations whose card or permit is held.';

-- ── 2 · the examination attendance sheet ────────────────────────────────────────────────────────────────────────────────
CREATE TABLE assessment.exam_attendance_sheet (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id     uuid NOT NULL REFERENCES catalogue.offering (id) ON DELETE CASCADE,
    scope_fac       text NULL,
    scope_dept      text NULL,
    scope_prog      text NULL,
    scope_key       text NOT NULL,
    series          text NOT NULL,
    version         integer NOT NULL CHECK (version >= 1),
    reference       text NOT NULL UNIQUE,
    manual_lines    integer NOT NULL CHECK (manual_lines BETWEEN 0 AND 60),
    students        integer NOT NULL,
    list            jsonb NOT NULL,
    exam_on         date NULL,
    starts_at       time NULL,
    ends_at         time NULL,
    venue           text NULL,
    reason          text NULL,
    generated_by    uuid NULL,
    generated_office text NULL,
    generated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (offering_id, scope_key, version),
    UNIQUE (series, version)
);
COMMENT ON TABLE assessment.exam_attendance_sheet IS
  'V652: an examination attendance sheet issued for a course (its class) within a scope — the students as they were listed, the examination''s date, time and venue where the timetable stated them, the manual lines printed — ATT/<code>/<year>/<nnnnn>/V<k>; a later sheet of the same course and scope is a new version, never the old one rewritten.';
CREATE INDEX ix_exam_attendance_sheet_offering ON assessment.exam_attendance_sheet (offering_id, scope_key, version DESC);
SELECT audit.attach('assessment.exam_attendance_sheet');

CREATE TABLE assessment.exam_attendance (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id     uuid NOT NULL REFERENCES catalogue.offering (id) ON DELETE CASCADE,
    student_id      uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    status          text NOT NULL CHECK (status IN ('PRESENT', 'ABSENT', 'LATE', 'MANUAL_PRESENT', 'EXCUSED', 'INVALID_ATTENDANCE')),
    source          text NOT NULL CHECK (source IN ('LIST', 'MANUAL')),
    sheet_reference text NULL,
    invigilator     text NULL,
    reason          text NULL,
    recorded_by     uuid NULL,
    recorded_office text NULL,
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    verified_by     uuid NULL,
    verified_at     timestamptz NULL,
    UNIQUE (offering_id, student_id)
);
COMMENT ON TABLE assessment.exam_attendance IS
  'V652: a student''s attendance at a course''s examination — PRESENT, ABSENT, LATE, MANUAL_PRESENT, EXCUSED or INVALID_ATTENDANCE, from the list or a handwritten row, the sheet, the invigilator, who recorded and who verified it. Never a registration or a result.';
SELECT audit.attach('assessment.exam_attendance');

CREATE TABLE assessment.exam_attendance_pending (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id      uuid NOT NULL REFERENCES catalogue.offering (id) ON DELETE CASCADE,
    written_name     text NOT NULL CHECK (btrim(written_name) <> ''),
    written_number   text NULL,
    written_programme text NULL,
    written_level    text NULL,
    reason           text NULL,
    sheet_reference  text NULL,
    invigilator      text NULL,
    state            text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'MATCHED', 'INVALID')),
    student_id       uuid NULL REFERENCES people.student (id) ON DELETE SET NULL,
    decided_by       uuid NULL,
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    entered_by       uuid NULL,
    entered_office   text NULL,
    entered_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE assessment.exam_attendance_pending IS
  'V652: a handwritten row of an attendance sheet whose student is not identified yet — PENDING VERIFICATION until an examinations officer matches it to the student (an attendance then recorded) or finds it invalid.';
SELECT audit.attach('assessment.exam_attendance_pending');

-- the offices that issue sheets and record attendance; the GST and EPS offices for their own courses
CREATE FUNCTION assessment.attendance_office_check(p_offering uuid) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_general text;
BEGIN
    IF coalesce(v_office, '') NOT IN ('exams', 'facultyexams', 'records', 'hod', 'gst', 'eps', 'academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'ATTENDANCE_OFFICE: examination attendance is kept by the examinations officers, Exams and Records, the Head of Department and the GST and EPS offices'
            USING ERRCODE = '42501';
    END IF;
    IF v_office IN ('gst', 'eps') THEN
        SELECT c.general_office INTO v_general FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.id = p_offering;
        IF v_general IS DISTINCT FROM upper(v_office) THEN
            RAISE EXCEPTION 'ATTENDANCE_NOT_OFFICE_COURSE: the % office keeps the attendance of its own courses', upper(v_office) USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN v_office;
END $$;

-- the students of a course's class, within a scope: every one with it on a submitted or approved registration, eligibility marked
CREATE FUNCTION assessment.attendance_list(p_offering uuid, p_fac text DEFAULT NULL, p_dept text DEFAULT NULL, p_prog text DEFAULT NULL)
RETURNS TABLE (student_id uuid, matric_no text, jamb_no text, full_name text, sex text, programme_code text, programme text, dept_code text,
               faculty_code text, level int, registration_status text, entry_type text, eligible boolean, eligibility text)
LANGUAGE sql STABLE AS $$
    WITH o AS (SELECT o.id, o.session, o.semester, c.kind = 'GST' AND c.general_office IN ('GST', 'EPS') AS general
                 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = p_offering)
    SELECT s.id, s.matric_no, coalesce(s.jamb_reg_no, (SELECT c2.jamb_reg_no FROM admissions.candidate c2 WHERE c2.id = s.candidate_id)),
           upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), upper(left(coalesce(s.sex, ''), 1)),
           p.code, p.name, p.dept_code, d.faculty_code, r.level, r.status, e.entry_type,
           CASE WHEN o.general THEN pm.student_id IS NOT NULL ELSE ci.student_id IS NOT NULL END,
           CASE WHEN o.general THEN CASE WHEN pm.student_id IS NOT NULL THEN 'PERMIT' ELSE 'NO_PERMIT' END
                ELSE CASE WHEN ci.student_id IS NOT NULL THEN 'CARD' ELSE 'NO_CARD' END END
      FROM o
      JOIN registration.entry e ON e.offering_id = o.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
      JOIN registration.course_registration r ON r.id = e.registration_id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
      JOIN people.student s ON s.id = r.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN registration.exam_card_issue ci ON ci.student_id = s.id AND ci.session = o.session AND ci.semester = o.semester
      LEFT JOIN registration.gst_eps_permit pm ON pm.student_id = s.id AND pm.session = o.session AND pm.semester = o.semester AND pm.revoked_at IS NULL
     WHERE (p_fac IS NULL OR d.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
     ORDER BY s.matric_no NULLS LAST, 4
$$;
COMMENT ON FUNCTION assessment.attendance_list(uuid, text, text, text) IS
  'V652: the students of a course''s class within a scope (faculty, department, programme) — every one with the course on a submitted or approved registration, the dropped and withdrawn left out — with whether they hold the GST & EPS permit (a GST/EPS course) or the examination card (any other).';

CREATE FUNCTION assessment.issue_attendance_sheet(p_offering uuid, p_manual_lines int, p_reason text, p_fac text DEFAULT NULL, p_dept text DEFAULT NULL, p_prog text DEFAULT NULL)
RETURNS assessment.exam_attendance_sheet LANGUAGE plpgsql AS $$
DECLARE v_office text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        o record; v_key text := coalesce(upper(p_fac), '') || '|' || coalesce(upper(p_dept), '') || '|' || coalesce(upper(p_prog), '');
        v_last assessment.exam_attendance_sheet; v_series text; v_version int; v_list jsonb; v_n int; t record; out assessment.exam_attendance_sheet;
BEGIN
    v_office := assessment.attendance_office_check(p_offering);
    SELECT x.id, x.session, x.semester, x.course_code INTO o FROM catalogue.offering x WHERE x.id = p_offering;
    IF NOT FOUND THEN RAISE EXCEPTION 'ATTENDANCE_NO_CLASS: no class %', p_offering USING ERRCODE = 'P0002'; END IF;
    IF p_manual_lines IS NULL OR p_manual_lines < 0 OR p_manual_lines > 60 THEN
        RAISE EXCEPTION 'ATTENDANCE_MANUAL_LINES: the manual lines are 0 to 60' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('attendance-sheet:' || p_offering::text || ':' || v_key));
    SELECT * INTO v_last FROM assessment.exam_attendance_sheet s WHERE s.offering_id = p_offering AND s.scope_key = v_key ORDER BY s.version DESC LIMIT 1;
    IF v_last.id IS NOT NULL AND length(btrim(coalesce(p_reason, ''))) < 5 THEN
        RAISE EXCEPTION 'ATTENDANCE_REISSUE_REASON: % is already issued; say why a new version is printed (late registration, a correction…)', v_last.reference
            USING ERRCODE = '23514';
    END IF;
    IF v_last.id IS NOT NULL THEN
        v_series := v_last.series; v_version := v_last.version + 1;
    ELSE
        v_series := 'ATT/' || regexp_replace(catalogue.shown_code(o.course_code), '[^A-Z0-9-]', '', 'g') || '/' || left(o.session, 4) || '/'
                    || lpad(platform.next_number('EXAM_ATTENDANCE_SHEET', 'UNIVERSITY', o.session)::text, 5, '0');
        v_version := 1;
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('student', l.student_id, 'matric', l.matric_no, 'jamb', l.jamb_no, 'name', l.full_name,
                                                 'programme', l.programme, 'programmeCode', l.programme_code, 'level', l.level,
                                                 'registration', l.registration_status, 'carryOver', l.entry_type = 'CARRYOVER',
                                                 'eligible', l.eligible, 'eligibility', l.eligibility)), '[]'::jsonb), count(*)
      INTO v_list, v_n FROM assessment.attendance_list(p_offering, upper(p_fac), upper(p_dept), upper(p_prog)) l;
    SELECT tt.held_on, tt.starts_at, tt.ends_at, tt.venue INTO t FROM assessment.exam_timetable tt WHERE tt.offering_id = p_offering ORDER BY tt.held_on LIMIT 1;
    INSERT INTO assessment.exam_attendance_sheet (offering_id, scope_fac, scope_dept, scope_prog, scope_key, series, version, reference, manual_lines,
                                                  students, list, exam_on, starts_at, ends_at, venue, reason, generated_by, generated_office)
    VALUES (p_offering, upper(p_fac), upper(p_dept), upper(p_prog), v_key, v_series, v_version, v_series || '/V' || v_version, p_manual_lines,
            v_n, v_list, t.held_on, t.starts_at, t.ends_at, t.venue, nullif(btrim(coalesce(p_reason, '')), ''), v_actor, v_office)
    RETURNING * INTO out;
    RETURN out;
END $$;
COMMENT ON FUNCTION assessment.issue_attendance_sheet(uuid, int, text, text, text, text) IS
  'V652: an attendance sheet issued for a course''s class within a scope — the students listed now, eligibility marked, the timetable''s date, time and venue where stated, the manual lines asked for (0–60); a sheet already issued for the course and scope gives the next version (a reason required), the earlier kept as printed.';

-- ── 3 · attendance recorded ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION assessment.record_attendance(p_offering uuid, p_marks jsonb, p_sheet text, p_invigilator text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_office text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; m jsonb; v_status text; v_student uuid; n int := 0;
BEGIN
    v_office := assessment.attendance_office_check(p_offering);
    FOR m IN SELECT * FROM jsonb_array_elements(coalesce(p_marks, '[]'::jsonb)) LOOP
        v_student := (m->>'student')::uuid;
        v_status := upper(btrim(coalesce(m->>'status', '')));
        IF v_status NOT IN ('PRESENT', 'ABSENT', 'LATE', 'EXCUSED', 'INVALID_ATTENDANCE') THEN
            RAISE EXCEPTION 'ATTENDANCE_STATUS: % is not an attendance of the list (PRESENT, ABSENT, LATE, EXCUSED, INVALID_ATTENDANCE)', coalesce(m->>'status', '')
                USING ERRCODE = '23514';
        END IF;
        -- the list's students: registered for the class now, or printed on one of its sheets
        IF NOT EXISTS (SELECT 1 FROM assessment.attendance_list(p_offering) l WHERE l.student_id = v_student)
           AND NOT EXISTS (SELECT 1 FROM assessment.exam_attendance_sheet s, jsonb_array_elements(s.list) x
                            WHERE s.offering_id = p_offering AND (x->>'student')::uuid = v_student) THEN
            RAISE EXCEPTION 'ATTENDANCE_NOT_ON_LIST: the student is not registered for the course nor on its sheet; enter a handwritten row instead'
                USING ERRCODE = '23514';
        END IF;
        INSERT INTO assessment.exam_attendance (offering_id, student_id, status, source, sheet_reference, invigilator, reason, recorded_by, recorded_office)
        VALUES (p_offering, v_student, v_status, 'LIST', nullif(btrim(coalesce(p_sheet, '')), ''), nullif(btrim(coalesce(p_invigilator, '')), ''),
                nullif(btrim(coalesce(m->>'reason', '')), ''), v_actor, v_office)
        ON CONFLICT (offering_id, student_id) DO UPDATE SET status = EXCLUDED.status, source = CASE WHEN assessment.exam_attendance.source = 'MANUAL'
                    AND EXCLUDED.status IN ('PRESENT', 'LATE') THEN 'MANUAL' ELSE 'LIST' END,
               sheet_reference = coalesce(EXCLUDED.sheet_reference, assessment.exam_attendance.sheet_reference),
               invigilator = coalesce(EXCLUDED.invigilator, assessment.exam_attendance.invigilator), reason = EXCLUDED.reason,
               recorded_by = EXCLUDED.recorded_by, recorded_office = EXCLUDED.recorded_office, recorded_at = now();
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION assessment.record_attendance(uuid, jsonb, text, text) IS
  'V652: the list marked after the paper — [{student, status, reason}] for students registered for the class or printed on its sheet: PRESENT, ABSENT, LATE, EXCUSED, INVALID_ATTENDANCE; a record kept, changed in place on the audit trail. Returns the number recorded.';

CREATE FUNCTION assessment.manual_attendance(p_offering uuid, p_number text, p_name text, p_programme text, p_level text, p_reason text,
                                             p_sheet text, p_invigilator text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; m record; v_id uuid; v_pending uuid; v_prior text;
BEGIN
    v_office := assessment.attendance_office_check(p_offering);
    IF nullif(btrim(coalesce(p_name, '')), '') IS NULL AND nullif(btrim(coalesce(p_number, '')), '') IS NULL THEN
        RAISE EXCEPTION 'ATTENDANCE_MANUAL_EMPTY: a handwritten row has a name or a number' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO m FROM people.resolve_student(p_number, true);
    IF m.status = 'MATCHED' THEN
        SELECT a.status INTO v_prior FROM assessment.exam_attendance a WHERE a.offering_id = p_offering AND a.student_id = m.student_id;
        INSERT INTO assessment.exam_attendance (offering_id, student_id, status, source, sheet_reference, invigilator, reason, recorded_by, recorded_office)
        VALUES (p_offering, m.student_id, 'MANUAL_PRESENT', 'MANUAL', nullif(btrim(coalesce(p_sheet, '')), ''), nullif(btrim(coalesce(p_invigilator, '')), ''),
                nullif(btrim(coalesce(p_reason, '')), ''), v_actor, v_office)
        ON CONFLICT (offering_id, student_id) DO UPDATE SET
               -- a student already marked present on the list stays so; any other mark becomes the handwritten attendance
               status = CASE WHEN assessment.exam_attendance.status IN ('PRESENT', 'LATE') THEN assessment.exam_attendance.status ELSE 'MANUAL_PRESENT' END,
               source = CASE WHEN assessment.exam_attendance.status IN ('PRESENT', 'LATE') THEN assessment.exam_attendance.source ELSE 'MANUAL' END,
               reason = coalesce(EXCLUDED.reason, assessment.exam_attendance.reason), recorded_by = EXCLUDED.recorded_by,
               recorded_office = EXCLUDED.recorded_office, recorded_at = now()
        RETURNING id INTO v_id;
        RETURN jsonb_build_object('outcome', 'MATCHED', 'student', m.student_id, 'method', m.method, 'attendance', v_id, 'before', v_prior,
                                  'registered', EXISTS (SELECT 1 FROM assessment.attendance_list(p_offering) l WHERE l.student_id = m.student_id));
    END IF;
    INSERT INTO assessment.exam_attendance_pending (offering_id, written_name, written_number, written_programme, written_level, reason, sheet_reference,
                                                    invigilator, entered_by, entered_office)
    VALUES (p_offering, coalesce(nullif(btrim(coalesce(p_name, '')), ''), btrim(p_number)), nullif(btrim(coalesce(p_number, '')), ''),
            nullif(btrim(coalesce(p_programme, '')), ''), nullif(btrim(coalesce(p_level, '')), ''), nullif(btrim(coalesce(p_reason, '')), ''),
            nullif(btrim(coalesce(p_sheet, '')), ''), nullif(btrim(coalesce(p_invigilator, '')), ''), v_actor, v_office)
    RETURNING id INTO v_pending;
    RETURN jsonb_build_object('outcome', 'PENDING', 'pending', v_pending, 'why', coalesce(m.status, 'NO_MATCH'), 'candidates', to_jsonb(m.candidates));
END $$;
COMMENT ON FUNCTION assessment.manual_attendance(uuid, text, text, text, text, text, text, text) IS
  'V652: a handwritten row of an attendance sheet entered — the student found by the number written (people.resolve_student: matriculation, admission, JAMB or application number): attendance MANUAL_PRESENT (one already present on the list kept so); not found, or more than one, held PENDING VERIFICATION. No student or registration is created.';

CREATE FUNCTION assessment.decide_manual_attendance(p_pending uuid, p_student uuid, p_valid boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; pe assessment.exam_attendance_pending; v_id uuid;
BEGIN
    SELECT * INTO pe FROM assessment.exam_attendance_pending x WHERE x.id = p_pending FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'ATTENDANCE_PENDING_NOT_FOUND: no handwritten row %', p_pending USING ERRCODE = 'P0002'; END IF;
    v_office := assessment.attendance_office_check(pe.offering_id);
    IF pe.state <> 'PENDING' THEN
        RAISE EXCEPTION 'ATTENDANCE_PENDING_DECIDED: the row is already %', lower(pe.state) USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_valid, false) THEN
        IF length(btrim(coalesce(p_note, ''))) < 5 THEN
            RAISE EXCEPTION 'ATTENDANCE_INVALID_NOTE: say why the row is invalid' USING ERRCODE = '23514';
        END IF;
        UPDATE assessment.exam_attendance_pending SET state = 'INVALID', decided_by = v_actor, decided_at = now(), decision_note = btrim(p_note) WHERE id = p_pending;
        RETURN jsonb_build_object('outcome', 'INVALID');
    END IF;
    IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student) THEN
        RAISE EXCEPTION 'ATTENDANCE_STUDENT: name the student the row is' USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.exam_attendance (offering_id, student_id, status, source, sheet_reference, invigilator, reason, recorded_by, recorded_office, verified_by, verified_at)
    VALUES (pe.offering_id, p_student, 'MANUAL_PRESENT', 'MANUAL', pe.sheet_reference, pe.invigilator, pe.reason, pe.entered_by, pe.entered_office, v_actor, now())
    ON CONFLICT (offering_id, student_id) DO UPDATE SET
           -- a student already marked present on the list stays so; any other mark becomes the handwritten attendance
           status = CASE WHEN assessment.exam_attendance.status IN ('PRESENT', 'LATE') THEN assessment.exam_attendance.status ELSE 'MANUAL_PRESENT' END,
           source = CASE WHEN assessment.exam_attendance.status IN ('PRESENT', 'LATE') THEN assessment.exam_attendance.source ELSE 'MANUAL' END,
           sheet_reference = coalesce(EXCLUDED.sheet_reference, assessment.exam_attendance.sheet_reference),
           reason = coalesce(EXCLUDED.reason, assessment.exam_attendance.reason),
           verified_by = v_actor, verified_at = now()
    RETURNING id INTO v_id;
    UPDATE assessment.exam_attendance_pending SET state = 'MATCHED', student_id = p_student, decided_by = v_actor, decided_at = now(),
           decision_note = nullif(btrim(coalesce(p_note, '')), '') WHERE id = p_pending;
    RETURN jsonb_build_object('outcome', 'MATCHED', 'attendance', v_id);
END $$;
COMMENT ON FUNCTION assessment.decide_manual_attendance(uuid, uuid, boolean, text) IS
  'V652: a handwritten row pending verification decided — matched to the student named (attendance MANUAL_PRESENT, verified) or invalid with a reason.';

-- ── 4 · the reconciliation ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION assessment.attendance_reconciliation(p_offering uuid, p_fac text DEFAULT NULL, p_dept text DEFAULT NULL, p_prog text DEFAULT NULL)
RETURNS TABLE (student_id uuid, matric_no text, full_name text, programme text, level int, registered boolean, eligible boolean, on_list boolean,
               list_version int, status text, source text, finding text)
LANGUAGE sql STABLE AS $$
    WITH reg AS (SELECT * FROM assessment.attendance_list(p_offering, upper(p_fac), upper(p_dept), upper(p_prog))),
    sheet AS (SELECT s.* FROM assessment.exam_attendance_sheet s
               WHERE s.offering_id = p_offering AND s.scope_key = coalesce(upper(p_fac), '') || '|' || coalesce(upper(p_dept), '') || '|' || coalesce(upper(p_prog), '')
               ORDER BY s.version DESC LIMIT 1),
    listed AS (SELECT (x->>'student')::uuid AS student_id, sheet.version FROM sheet, jsonb_array_elements(sheet.list) x),
    att AS (SELECT a.* FROM assessment.exam_attendance a JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code
              JOIN ref.department d ON d.code = p.dept_code
             WHERE a.offering_id = p_offering AND (p_fac IS NULL OR d.faculty_code = upper(p_fac)) AND (p_dept IS NULL OR p.dept_code = upper(p_dept))
               AND (p_prog IS NULL OR p.code = upper(p_prog))),
    who AS (SELECT reg.student_id FROM reg UNION SELECT listed.student_id FROM listed UNION SELECT att.student_id FROM att)
    SELECT w.student_id, s.matric_no, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), p.name,
           coalesce(reg.level, s.current_level), reg.student_id IS NOT NULL, coalesce(reg.eligible, false), l.student_id IS NOT NULL, l.version,
           a.status, a.source,
           CASE WHEN a.status = 'MANUAL_PRESENT' AND reg.student_id IS NULL THEN 'MANUAL_NOT_REGISTERED'
                WHEN l.student_id IS NOT NULL AND reg.student_id IS NULL THEN 'ON_LIST_NOT_REGISTERED'
                WHEN a.status IN ('PRESENT', 'LATE') AND reg.student_id IS NULL THEN 'PRESENT_NOT_REGISTERED'
                WHEN a.status IN ('PRESENT', 'LATE', 'MANUAL_PRESENT') AND NOT coalesce(reg.eligible, false) THEN 'PRESENT_NOT_ELIGIBLE'
                WHEN reg.student_id IS NOT NULL AND l.student_id IS NULL AND (SELECT count(*) FROM sheet) > 0 THEN 'REGISTERED_NOT_ON_LIST'
                WHEN a.status IS NULL THEN 'NOT_MARKED'
                ELSE 'OK' END
      FROM who w
      JOIN people.student s ON s.id = w.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN reg ON reg.student_id = w.student_id
      LEFT JOIN listed l ON l.student_id = w.student_id
      LEFT JOIN att a ON a.student_id = w.student_id
     ORDER BY s.matric_no NULLS LAST
$$;
COMMENT ON FUNCTION assessment.attendance_reconciliation(uuid, text, text, text) IS
  'V652: a course''s attendance reconciled within a scope — every student registered now, printed on the latest sheet or recorded, with whether they are registered, eligible and listed, the attendance recorded, and the finding: OK, REGISTERED_NOT_ON_LIST, ON_LIST_NOT_REGISTERED, PRESENT_NOT_REGISTERED, PRESENT_NOT_ELIGIBLE, MANUAL_NOT_REGISTERED, NOT_MARKED. A report: nothing is written.';

-- each course of the report with its registration, sex, eligibility and attendance figures
CREATE FUNCTION reporting.course_registration_courses(p_session text, p_semester int, p_f jsonb)
RETURNS TABLE (offering_id uuid, course_code text, shown_code text, course_title text, units int, category text, curriculum text, course_dept text,
               semester int, students int, male int, female int, other_sex int, carry_over int, eligible int,
               sheet_reference text, sheets int, present int, absent int, manual_present int, pending int)
LANGUAGE sql STABLE SET jit = off AS $$
    WITH r AS (SELECT * FROM reporting.course_registration_rows(p_session, p_semester, p_f)),
    c AS (SELECT r.offering_id, max(r.course_code) AS course_code, max(r.shown_code) AS shown_code, max(r.course_title) AS course_title, max(r.units) AS units,
                 max(r.category) AS category, max(r.curriculum) AS curriculum, max(r.course_dept) AS course_dept, max(r.semester) AS semester,
                 count(DISTINCT r.student_id)::int AS students, count(DISTINCT r.student_id) FILTER (WHERE r.sex = 'M')::int AS male,
                 count(DISTINCT r.student_id) FILTER (WHERE r.sex = 'F')::int AS female, count(DISTINCT r.student_id) FILTER (WHERE r.sex NOT IN ('M', 'F'))::int AS other_sex,
                 count(*) FILTER (WHERE r.carry_over)::int AS carry_over, count(DISTINCT r.student_id) FILTER (WHERE r.eligible)::int AS eligible,
                 array_agg(DISTINCT r.student_id) AS ids
            FROM r GROUP BY r.offering_id)
    SELECT c.offering_id, c.course_code, c.shown_code, c.course_title, c.units, c.category, c.curriculum, c.course_dept, c.semester,
           c.students, c.male, c.female, c.other_sex, c.carry_over, c.eligible,
           (SELECT s.reference FROM assessment.exam_attendance_sheet s WHERE s.offering_id = c.offering_id ORDER BY s.generated_at DESC LIMIT 1),
           (SELECT count(*)::int FROM assessment.exam_attendance_sheet s WHERE s.offering_id = c.offering_id),
           (SELECT count(*)::int FROM assessment.exam_attendance a WHERE a.offering_id = c.offering_id AND a.student_id = ANY (c.ids) AND a.status IN ('PRESENT', 'LATE')),
           (SELECT count(*)::int FROM assessment.exam_attendance a WHERE a.offering_id = c.offering_id AND a.student_id = ANY (c.ids) AND a.status = 'ABSENT'),
           (SELECT count(*)::int FROM assessment.exam_attendance a WHERE a.offering_id = c.offering_id AND a.status = 'MANUAL_PRESENT'),
           (SELECT count(*)::int FROM assessment.exam_attendance_pending pe WHERE pe.offering_id = c.offering_id AND pe.state = 'PENDING')
      FROM c
     ORDER BY c.shown_code, c.course_code
$$;
COMMENT ON FUNCTION reporting.course_registration_courses(text, int, jsonb) IS
  'V652: the course-by-course report — each course (its class) of the registrations the filters reach, with students, male, female, not stated, carry-overs, holding the card or permit, the latest attendance sheet and the number issued, present, absent, manual present and handwritten rows pending verification.';

COMMIT;
