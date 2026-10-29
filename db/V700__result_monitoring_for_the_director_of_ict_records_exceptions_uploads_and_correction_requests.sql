-- ═══════════════════════════════════════
-- V700 — result monitoring for the Director of ICT: the result records, their exceptions, the uploads, and correction requests
--
-- The University's master prompt of 29 October 2026 ("ICT Director — complete result viewer, result correction and result
-- broadsheet monitoring"): one place where the Director of ICT sees every uploaded and processed result by faculty, department,
-- programme, level, session and semester, opens the result records and the broadsheet, finds what is wrong, and has it corrected
-- through the University's own correction workflow — never a second result system.
--
-- What was there: the score sheets and their chain (ENTRY … PUBLISHED), every mark kept as versions (assessment.score), a course's
-- result read by assessment.course_final (a published special or re-sit over the Main), the broadsheet built from the approved
-- registrations and course_final (ResultsRepository.broadsheet), the pipeline, the approval chain, and amendments — a correction
-- of a published mark raised by the course's desk of entry, taken through the desks to Senate and applied as a new version
-- (V358). The Director of ICT reads all of it (ResultsController.READERS) but raises no amendment: the desk of entry does.
--
-- What this adds, reading the same tables:
--   · assessment.result_records(session, semester, faculty, department, programme, level, course): every course on an approved
--     registration in scope — the rows the broadsheet is made of — with the student, the course, the units, the registration's
--     level, the main sitting's sheet and its stage (NO_SHEET when there is none) and whether the student has a mark on it.
--   · assessment.result_monitor_groups(session, semester, faculty, department): those records counted by faculty, by department
--     of a faculty, or by programme and level of a department — the students, the records, the results in, those awaiting a
--     result, at entry, at verification, in approval, published, and missing (a sheet past entry with no mark for the student).
--   · assessment.result_exceptions(session, semester, faculty, department, programme, level): what needs a look —
--       RESULT_WITHOUT_REGISTRATION   a mark with no approved registration of the course;
--       DUPLICATE_RESULT              marks for one course (its BSU-/MOAU- twin, or a second course under the code) on two classes;
--       MISSING_SCORE                 a registered student with no mark on a sheet past entry;
--       INVALID_SCORE                 a mark entered on the portal above the course's CA, or its examination, maximum;
--       COURSE_ABOVE_LEVEL            a course of a higher level than the registration with a mark;
--       COURSE_OTHER_SEMESTER         a course taught in the other semester with a mark in this one;
--       COURSE_OUTSIDE_PROGRAMME      a course with a mark the programme neither registered under its structure nor binds, not a
--                                     general course, and not taken off its broadsheet (V624);
--       PASSED_STILL_CARRIED          a carry-over registered for a course passed on a published result before;
--       RESULT_HELD_NO_STUDENT        an uploaded result held for a number no student holds (University-wide only).
--   · assessment.result_uploads(session, semester): the uploads of marks — a score sheet's (assessment.sheet_upload) and the old
--     portal's past results (imported versions, by who loaded them and when).
--   · assessment.correction_request: a correction the Director of ICT (or super) asks for — the result as it stood, the reason
--     (Lecturer upload error, Data entry error, Incorrect score, Missing score, Wrong student, Wrong course, Wrong session, Wrong
--     semester, Wrong programme, Approved academic correction, Migration correction, Other) with a note, the marks proposed. It goes
--     to the course's desk of entry: they correct the mark on the sheet while it is at entry, or raise the amendment once it is
--     published (the request then follows it), or decline it with their reason. A new version of the mark resolves it; a refused
--     amendment declines it; a withdrawn one leaves it open. Nothing changes a mark but the desks' own workflow.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V700: result monitoring for the Director of ICT', true);

-- ── the result records: the courses on approved registrations, as the broadsheet reads them ──
CREATE OR REPLACE FUNCTION assessment.result_records(p_session text, p_sem integer, p_fac text, p_dept text, p_prog text, p_level integer, p_course text)
RETURNS TABLE (registration_id uuid, student_id uuid, number text, jamb_reg_no text, surname text, other_names text, programme_code text,
               dept_code text, faculty_code text, level integer, offering_id uuid, course_code text, course_title text, units integer,
               course_level integer, course_semester integer, both_semesters boolean, entry_type text, basis text, stream text,
               sheet_id uuid, stage text, has_score boolean, lecturer_id uuid)
LANGUAGE sql STABLE AS $$
    SELECT r.id, st.id, coalesce(st.matric_no, st.admission_no), st.jamb_reg_no, st.surname, st.other_names, st.programme_code, p.dept_code, p.faculty_code, r.level,
           o.id, o.course_code, coalesce(o.title, c.title), e.units, c.level, c.semester, c.both_semesters, e.entry_type, e.basis, o.stream,
           ms.id, coalesce(ms.stage, 'NO_SHEET'),
           ms.id IS NOT NULL AND EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = ms.id AND sc.student_id = st.id),
           o.lecturer_id
      FROM registration.course_registration r
      JOIN people.student st ON st.id = r.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN registration.entry e ON e.registration_id = r.id AND e.status = 'APPROVED'
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      -- the main sitting's sheet (a special or re-sit is read by assessment.course_final when the result is shown)
      LEFT JOIN LATERAL (SELECT sh.id, sh.stage FROM assessment.score_sheet sh LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                          WHERE sh.offering_id = o.id ORDER BY (coalesce(es.kind, 'MAIN') = 'MAIN') DESC, sh.id LIMIT 1) ms ON true
     WHERE r.session = p_session AND r.semester = p_sem AND r.status IN ('APPROVED', 'LOCKED')
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)
       AND (p_level IS NULL OR r.level = p_level) AND (p_course IS NULL OR o.course_code = p_course)
$$;
COMMENT ON FUNCTION assessment.result_records(text, integer, text, text, text, integer, text) IS
  'V700: every course on an approved registration of a session''s semester in scope — the rows the broadsheet is made of — with the main sitting''s sheet, its stage (NO_SHEET when there is none) and whether the student has a mark on it.';

-- ── where a record stands, in one word ──
CREATE OR REPLACE FUNCTION assessment.result_state(p_stage text, p_has_score boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_stage = 'NO_SHEET' OR (p_stage = 'ENTRY' AND NOT p_has_score) THEN 'AWAITING'   -- no result yet: never a fail
                WHEN NOT p_has_score THEN 'MISSING'                                                    -- a sheet past entry without the student's mark
                WHEN p_stage = 'ENTRY' THEN 'ENTRY'
                WHEN p_stage = 'VERIFICATION' THEN 'VERIFICATION'
                WHEN p_stage = 'PUBLISHED' THEN 'PUBLISHED'
                ELSE 'APPROVAL' END
$$;
COMMENT ON FUNCTION assessment.result_state(text, boolean) IS
  'V700: AWAITING (no sheet, or no mark while the sheet is at entry: no result, never a fail), MISSING (a sheet past entry without the student''s mark), ENTRY, VERIFICATION, APPROVAL (the Departmental Board to Senate) or PUBLISHED.';

-- ── counted by faculty, by department, or by programme and level ──
CREATE OR REPLACE FUNCTION assessment.result_monitor_groups(p_session text, p_sem integer, p_fac text, p_dept text)
RETURNS TABLE (faculty_code text, dept_code text, programme_code text, level integer, students bigint, results bigint, with_result bigint,
               awaiting bigint, at_entry bigint, verification bigint, approval bigint, published bigint, missing bigint)
LANGUAGE sql STABLE AS $$
    SELECT x.k_fac, x.k_dept, x.k_prog, x.k_level,
           count(DISTINCT x.student_id), count(*), count(*) FILTER (WHERE x.has_score),
           count(*) FILTER (WHERE x.state = 'AWAITING'), count(*) FILTER (WHERE x.state = 'ENTRY'), count(*) FILTER (WHERE x.state = 'VERIFICATION'),
           count(*) FILTER (WHERE x.state = 'APPROVAL'), count(*) FILTER (WHERE x.state = 'PUBLISHED'), count(*) FILTER (WHERE x.state = 'MISSING')
      FROM (SELECT r.faculty_code AS k_fac,                                                       -- by faculty
                   CASE WHEN p_fac IS NOT NULL OR p_dept IS NOT NULL THEN r.dept_code END AS k_dept,   -- by department of a faculty
                   CASE WHEN p_dept IS NOT NULL THEN r.programme_code END AS k_prog,             -- by programme and level of a department
                   CASE WHEN p_dept IS NOT NULL THEN r.level END AS k_level,
                   r.student_id, r.has_score, assessment.result_state(r.stage, r.has_score) AS state
              FROM assessment.result_records(p_session, p_sem, p_fac, p_dept, NULL, NULL, NULL) r) x
     GROUP BY x.k_fac, x.k_dept, x.k_prog, x.k_level
$$;
COMMENT ON FUNCTION assessment.result_monitor_groups(text, integer, text, text) IS
  'V700: the result records of a session''s semester counted by faculty (no faculty given), by department (a faculty), or by programme and level (a department): students, records, results in, awaiting, at entry, verification, approval, published, missing.';

-- ── what needs a look ──
CREATE OR REPLACE FUNCTION assessment.result_exceptions(p_session text, p_sem integer, p_fac text, p_dept text, p_prog text, p_level integer)
RETURNS TABLE (kind text, student_id uuid, offering_id uuid, sheet_id uuid, course_code text, level integer, detail text)
LANGUAGE sql STABLE AS $$
    WITH rec AS MATERIALIZED (
        SELECT * FROM assessment.result_records(p_session, p_sem, p_fac, p_dept, p_prog, p_level, NULL)),
    scoped AS MATERIALIZED (
        SELECT st.id, st.programme_code, st.current_level
          FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
         WHERE (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)),
    marks AS MATERIALIZED (   -- the latest mark of each student in scope on each sheet of the session's semester
        SELECT DISTINCT ON (sc.sheet_id, sc.student_id) sc.sheet_id, sc.student_id, sc.version, sc.ca, sc.exam, sc.total, sc.outcome, sc.imported,
               o.id AS offering_id, o.course_code, c.ca_max,
               regexp_replace(catalogue.shown_code(o.course_code), '^(BSU|MOAU)-', '') AS base_code,
               coalesce((SELECT r.level FROM registration.course_registration r
                          WHERE r.student_id = sc.student_id AND r.session = p_session AND r.semester = p_sem LIMIT 1), s.current_level) AS level
          FROM assessment.score sc
          JOIN scoped s ON s.id = sc.student_id
          JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
          JOIN catalogue.offering o ON o.id = sh.offering_id
          JOIN catalogue.course c ON c.code = o.course_code
         WHERE o.session = p_session AND o.semester = p_sem
         ORDER BY sc.sheet_id, sc.student_id, sc.version DESC),
    lv AS MATERIALIZED (SELECT * FROM marks WHERE p_level IS NULL OR level = p_level),
    -- one course with marks on two classes: grouped once, never each mark against every other
    dup AS MATERIALIZED (
        SELECT d.student_id, d.base_code, string_agg(DISTINCT d.course_code, ', ' ORDER BY d.course_code) AS codes
          FROM lv d GROUP BY d.student_id, d.base_code HAVING count(DISTINCT d.offering_id) > 1)
    -- a mark with no approved registration of the course
    SELECT 'RESULT_WITHOUT_REGISTRATION'::text, m.student_id, m.offering_id, m.sheet_id, m.course_code, m.level,
           'A mark for ' || m.course_code || ' with no approved registration of the course in ' || p_session || ', semester ' || p_sem
      FROM lv m
     WHERE NOT EXISTS (SELECT 1 FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                        WHERE e.offering_id = m.offering_id AND r.student_id = m.student_id AND e.status = 'APPROVED' AND r.status IN ('APPROVED', 'LOCKED'))
    UNION ALL
    -- marks for one course on two classes
    SELECT 'DUPLICATE_RESULT', m.student_id, m.offering_id, m.sheet_id, m.course_code, m.level, 'Marks for the same course on ' || d.codes
      FROM lv m JOIN dup d ON d.student_id = m.student_id AND d.base_code = m.base_code
    UNION ALL
    -- a registered student with no mark on a sheet past entry
    SELECT 'MISSING_SCORE', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           'Registered for ' || r.course_code || '; its sheet is at ' || r.stage || ' with no mark for the student'
      FROM rec r WHERE assessment.result_state(r.stage, r.has_score) = 'MISSING'
    UNION ALL
    -- a mark entered on the portal above the course's CA or its examination maximum (an old portal's total is read whole, V614)
    SELECT 'INVALID_SCORE', m.student_id, m.offering_id, m.sheet_id, m.course_code, m.level,
           m.course_code || ': CA ' || coalesce(m.ca::text, '–') || ' and examination ' || coalesce(m.exam::text, '–') || ' against a CA of '
           || coalesce(m.ca_max, 40) || ' and an examination of ' || (100 - coalesce(m.ca_max, 40))
      FROM lv m
     WHERE m.outcome = 'GRADED' AND NOT m.imported
       AND (coalesce(m.ca, 0) > coalesce(m.ca_max, 40) OR coalesce(m.exam, 0) > 100 - coalesce(m.ca_max, 40))
    UNION ALL
    -- a course of a higher level than the registration, with a mark
    SELECT 'COURSE_ABOVE_LEVEL', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is a ' || r.course_level || ' Level course on a ' || r.level || ' Level registration'
      FROM rec r WHERE r.has_score AND r.course_level > r.level
    UNION ALL
    -- a course taught in the other semester, with a mark in this one
    SELECT 'COURSE_OTHER_SEMESTER', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is taught in semester ' || r.course_semester || ', with a mark in semester ' || p_sem
      FROM rec r WHERE r.has_score AND r.course_semester IS NOT NULL AND NOT catalogue.runs_in(r.course_semester, coalesce(r.both_semesters, false), p_sem)
    UNION ALL
    -- a course with a mark the programme neither registered under its structure nor binds (the broadsheet's rule, V624)
    SELECT 'COURSE_OUTSIDE_PROGRAMME', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is not in the structure of ' || r.programme_code
      FROM rec r
     WHERE r.has_score AND r.basis IS NULL
       AND regexp_replace(r.course_code, '^(BSU|MOAU)-', '') !~ '^(GST|EPS) '
       AND NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = r.course_code AND c.kind = 'GST')
       AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co
                        WHERE co.programme_code = r.programme_code
                          AND co.course_code IN (r.course_code, regexp_replace(r.course_code, '^(BSU|MOAU)-', ''),
                                                 'BSU-' || regexp_replace(r.course_code, '^(BSU|MOAU)-', ''),
                                                 'MOAU-' || regexp_replace(r.course_code, '^(BSU|MOAU)-', '')))
       AND NOT EXISTS (SELECT 1 FROM assessment.broadsheet_omission bo
                        WHERE bo.programme_code = r.programme_code AND bo.level = r.level AND bo.session = p_session AND bo.semester = p_sem
                          AND bo.course_code = r.course_code)
    UNION ALL
    -- a carry-over registered for a course passed on a published result before
    SELECT 'PASSED_STILL_CARRIED', r.student_id, r.offering_id, r.sheet_id, r.course_code, r.level,
           r.course_code || ' is registered as a carry-over, passed in ' || pr.session || ' (' || pr.grade || ')'
      FROM rec r
      CROSS JOIN LATERAL (
          SELECT o2.session, cf.grade
            FROM registration.course_registration r2
            JOIN registration.entry e2 ON e2.registration_id = r2.id AND e2.status = 'APPROVED'
            JOIN catalogue.offering o2 ON o2.id = e2.offering_id
            CROSS JOIN LATERAL assessment.course_final(r2.student_id, o2.id) cf
           WHERE r2.student_id = r.student_id AND r2.status IN ('APPROVED', 'LOCKED')
             AND regexp_replace(catalogue.shown_code(o2.course_code), '^(BSU|MOAU)-', '') = regexp_replace(catalogue.shown_code(r.course_code), '^(BSU|MOAU)-', '')
             AND (left(o2.session, 4)::int < left(p_session, 4)::int OR (o2.session = p_session AND o2.semester < p_sem))
             AND cf.stage = 'PUBLISHED' AND coalesce(cf.points, 0) > 0
           ORDER BY o2.session DESC LIMIT 1) pr
     WHERE r.entry_type = 'CARRYOVER'
    UNION ALL
    -- an uploaded result held for a number no student holds (no programme to scope it by: University-wide only)
    SELECT 'RESULT_HELD_NO_STUDENT', NULL::uuid, NULL::uuid, NULL::uuid, h.course_code, NULL::integer,
           'Uploaded for ' || h.matric || ' on ' || to_char(h.loaded_at, 'DD Mon YYYY') || '; no student holds that number'
      FROM assessment.legacy_result_holding h
     WHERE h.session = p_session AND h.semester = p_sem AND p_fac IS NULL AND p_dept IS NULL AND p_prog IS NULL AND p_level IS NULL
$$;
COMMENT ON FUNCTION assessment.result_exceptions(text, integer, text, text, text, integer) IS
  'V700: the results of a session''s semester in scope that need a look (each with the level it was registered at) — RESULT_WITHOUT_REGISTRATION, DUPLICATE_RESULT, MISSING_SCORE, INVALID_SCORE, COURSE_ABOVE_LEVEL, COURSE_OTHER_SEMESTER, COURSE_OUTSIDE_PROGRAMME, PASSED_STILL_CARRIED, RESULT_HELD_NO_STUDENT — each with the record it is about.';

-- ── the uploads of marks ──
CREATE OR REPLACE FUNCTION assessment.result_uploads(p_session text, p_sem integer)
RETURNS TABLE (kind text, uploaded_at timestamptz, uploaded_by uuid, office text, session text, semester integer, course_code text, sheet_id uuid,
               records integer, replaced integer, sheets integer, students integer, reason text)
LANGUAGE sql STABLE AS $$
    SELECT 'SCORE_SHEET'::text, u.uploaded_at, u.uploaded_by, u.uploader_office, o.session, o.semester, o.course_code, u.sheet_id,
           u.rows_written, NULL::integer, 1, NULL::integer, u.reason
      FROM assessment.sheet_upload u
      JOIN assessment.score_sheet sh ON sh.id = u.sheet_id
      JOIN catalogue.offering o ON o.id = sh.offering_id
     WHERE (p_session IS NULL OR o.session = p_session) AND (p_sem IS NULL OR o.semester = p_sem)
    UNION ALL
    -- the old portal's past results: each load one transaction, its marks written at one moment by one person
    SELECT 'PAST_RESULTS', sc.entered_at, sc.entered_by, min(sc.entered_office), o.session, o.semester, NULL, NULL,
           count(*)::int, count(*) FILTER (WHERE sc.version > 1)::int, count(DISTINCT sc.sheet_id)::int, count(DISTINCT sc.student_id)::int, NULL
      FROM assessment.score sc
      JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
      JOIN catalogue.offering o ON o.id = sh.offering_id
     WHERE sc.imported AND (p_session IS NULL OR o.session = p_session) AND (p_sem IS NULL OR o.semester = p_sem)
     GROUP BY sc.entered_at, sc.entered_by, o.session, o.semester
$$;
COMMENT ON FUNCTION assessment.result_uploads(text, integer) IS
  'V700: the uploads of marks — each score sheet''s (assessment.sheet_upload) and each load of the old portal''s past results (its imported marks, written in one transaction by one person), with the records written and those that replaced an earlier mark.';

-- ── a correction the Director of ICT asks of the course's desk of entry ──
CREATE TABLE assessment.correction_request (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref            text NOT NULL UNIQUE CHECK (ref ~ '^CRQ-[0-9]{4}-[0-9]{5}$'),
    -- it goes with its sheet, its student or its amendment (the go-live reset, platform.reset_operational_data, clears those)
    sheet_id       uuid NOT NULL REFERENCES assessment.score_sheet (id) ON DELETE CASCADE,
    student_id     uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    reason_kind    text NOT NULL CHECK (reason_kind IN ('LECTURER_UPLOAD_ERROR', 'DATA_ENTRY_ERROR', 'INCORRECT_SCORE', 'MISSING_SCORE', 'WRONG_STUDENT',
                                                        'WRONG_COURSE', 'WRONG_SESSION', 'WRONG_SEMESTER', 'WRONG_PROGRAMME',
                                                        'APPROVED_ACADEMIC_CORRECTION', 'MIGRATION_CORRECTION', 'OTHER')),
    note           text NOT NULL CHECK (length(btrim(note)) >= 10),
    -- the result as it stood when asked
    was_version    integer, was_ca integer, was_exam integer, was_total integer, was_grade text, was_outcome text, was_stage text NOT NULL,
    -- the marks proposed (none for a wrong student, course, session, semester or programme: the desk removes or moves it)
    ca             integer CHECK (ca IS NULL OR ca BETWEEN 0 AND 100),
    exam           integer CHECK (exam IS NULL OR exam BETWEEN 0 AND 100),
    outcome        text CHECK (outcome IS NULL OR outcome IN ('GRADED', 'ABSENT', 'WITHHELD', 'INCOMPLETE', 'MALPRACTICE', 'EXEMPTED')),
    state          text NOT NULL DEFAULT 'OPEN' CHECK (state IN ('OPEN', 'IN_AMENDMENT', 'RESOLVED', 'DECLINED', 'WITHDRAWN')),
    amendment_id   uuid REFERENCES assessment.amendment (id) ON DELETE CASCADE,
    resolved_version integer,
    requested_by   uuid NOT NULL,
    requested_office text NOT NULL,
    requested_at   timestamptz NOT NULL DEFAULT now(),
    closed_by      uuid,
    closed_office  text,
    closed_at      timestamptz,
    closed_note    text,
    CHECK ((ca IS NULL AND exam IS NULL) OR (ca IS NOT NULL AND exam IS NOT NULL AND ca + exam <= 100)),
    CHECK ((state IN ('OPEN', 'IN_AMENDMENT')) = (closed_at IS NULL)),
    CHECK ((state = 'IN_AMENDMENT') <= (amendment_id IS NOT NULL))
);
CREATE UNIQUE INDEX ux_correction_request_open ON assessment.correction_request (sheet_id, student_id) WHERE state IN ('OPEN', 'IN_AMENDMENT');
CREATE INDEX ix_correction_request_state ON assessment.correction_request (state, requested_at DESC);
CREATE INDEX ix_correction_request_amendment ON assessment.correction_request (amendment_id) WHERE amendment_id IS NOT NULL;
SELECT audit.attach('assessment.correction_request');
COMMENT ON TABLE assessment.correction_request IS
  'V700: a correction of one student''s result on one sheet, asked of the course''s desk of entry by the Director of ICT (or super) — the result as it stood, the reason and note, the marks proposed; resolved by a new version of the mark, followed through an amendment, declined by the desk or withdrawn.';

CREATE OR REPLACE FUNCTION assessment.request_correction(p_sheet uuid, p_student uuid, p_kind text, p_note text, p_ca integer, p_exam integer, p_outcome text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_kind text := upper(btrim(coalesce(p_kind, ''))); v_outcome text := nullif(upper(btrim(coalesce(p_outcome, ''))), '');
        sh assessment.score_sheet; o catalogue.offering; cur record; v_id uuid; v_ref text;
BEGIN
    IF coalesce(v_office, '') NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'CRQ_OFFICE: a correction is asked for by the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'CRQ_OFFICE: a correction is asked for by a person' USING ERRCODE = '42501'; END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'CRQ_NOTE: say what is wrong, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF v_kind NOT IN ('LECTURER_UPLOAD_ERROR', 'DATA_ENTRY_ERROR', 'INCORRECT_SCORE', 'MISSING_SCORE', 'WRONG_STUDENT', 'WRONG_COURSE', 'WRONG_SESSION',
                      'WRONG_SEMESTER', 'WRONG_PROGRAMME', 'APPROVED_ACADEMIC_CORRECTION', 'MIGRATION_CORRECTION', 'OTHER') THEN
        RAISE EXCEPTION 'CRQ_KIND: % is not a reason for a correction', coalesce(p_kind, '') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO sh FROM assessment.score_sheet WHERE id = p_sheet;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRQ_NOT_ON_SHEET: no such sheet' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = sh.offering_id;
    SELECT * INTO cur FROM assessment.latest_scores(p_sheet) l WHERE l.student_id = p_student;
    IF cur.student_id IS NULL AND NOT EXISTS (
        SELECT 1 FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
         WHERE e.offering_id = sh.offering_id AND r.student_id = p_student AND e.status IN ('APPROVED', 'REGISTERED')) THEN
        RAISE EXCEPTION 'CRQ_NOT_ON_SHEET: the student has neither a mark nor a registration on this sheet' USING ERRCODE = '23514';
    END IF;
    IF (p_ca IS NULL) <> (p_exam IS NULL) OR (p_ca IS NOT NULL AND (p_ca < 0 OR p_exam < 0 OR p_ca + p_exam > 100)) THEN
        RAISE EXCEPTION 'CRQ_MARKS: a CA and an examination mark together, from 0 to 100 between them' USING ERRCODE = '23514';
    END IF;
    IF v_outcome IS NOT NULL AND v_outcome NOT IN ('GRADED', 'ABSENT', 'WITHHELD', 'INCOMPLETE', 'MALPRACTICE', 'EXEMPTED') THEN
        RAISE EXCEPTION 'CRQ_MARKS: % is not an outcome', p_outcome USING ERRCODE = '23514';
    END IF;
    IF coalesce(v_outcome, 'GRADED') = 'GRADED' AND p_ca IS NULL AND v_kind IN ('INCORRECT_SCORE', 'MISSING_SCORE', 'DATA_ENTRY_ERROR', 'LECTURER_UPLOAD_ERROR') THEN
        RAISE EXCEPTION 'CRQ_MARKS: an incorrect or missing score names the marks it should be' USING ERRCODE = '23514';
    END IF;
    IF p_ca IS NOT NULL AND cur.student_id IS NOT NULL AND p_ca = cur.ca AND p_exam = cur.exam AND coalesce(v_outcome, 'GRADED') = cur.outcome THEN
        RAISE EXCEPTION 'CRQ_SAME: the marks proposed are the marks on record' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.correction_request q WHERE q.sheet_id = p_sheet AND q.student_id = p_student AND q.state IN ('OPEN', 'IN_AMENDMENT')) THEN
        RAISE EXCEPTION 'CRQ_OPEN: a correction of this result is already open' USING ERRCODE = '23514';
    END IF;
    v_ref := 'CRQ-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('CORRECTION_REQUEST', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
    INSERT INTO assessment.correction_request (ref, sheet_id, student_id, reason_kind, note, was_version, was_ca, was_exam, was_total, was_grade, was_outcome, was_stage,
                                               ca, exam, outcome, requested_by, requested_office)
    VALUES (v_ref, p_sheet, p_student, v_kind, btrim(p_note), cur.version, cur.ca, cur.exam, cur.total, cur.grade, cur.outcome, sh.stage,
            p_ca, p_exam, CASE WHEN p_ca IS NOT NULL THEN coalesce(v_outcome, 'GRADED') ELSE v_outcome END, v_actor, v_office)
    RETURNING id INTO v_id;
    -- an amendment already open for the result: the request follows it
    UPDATE assessment.correction_request q SET state = 'IN_AMENDMENT', amendment_id = m.id
      FROM assessment.amendment m
     WHERE q.id = v_id AND m.sheet_id = p_sheet AND m.student_id = p_student AND m.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN');
    RETURN v_id;
END $$;
COMMENT ON FUNCTION assessment.request_correction(uuid, uuid, text, text, integer, integer, text) IS
  'V700: the Director of ICT (or super) asks the course''s desk of entry to correct one student''s result on a sheet — the reason and a note of ten characters or more, the marks proposed (CA and examination together; an incorrect or missing score names them), the result as it stood kept. CRQ_OFFICE, CRQ_NOTE, CRQ_KIND, CRQ_NOT_ON_SHEET, CRQ_MARKS, CRQ_SAME, CRQ_OPEN.';

CREATE OR REPLACE FUNCTION assessment.withdraw_correction_request(p_id uuid, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; q assessment.correction_request;
BEGIN
    IF coalesce(v_office, '') NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'CRQ_OFFICE: a correction is withdrawn by the office that asked for it' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN RAISE EXCEPTION 'CRQ_NOTE: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO q FROM assessment.correction_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRQ_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF q.state <> 'OPEN' THEN
        RAISE EXCEPTION 'CRQ_STATE: only an open correction is withdrawn (this one is %)', q.state USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.correction_request SET state = 'WITHDRAWN', closed_by = v_actor, closed_office = v_office, closed_at = now(), closed_note = btrim(p_note)
     WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION assessment.decline_correction_request(p_id uuid, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; q assessment.correction_request;
BEGIN
    IF coalesce(v_office, '') NOT IN ('lecturer', 'exams', 'gst', 'eps', 'super') THEN
        RAISE EXCEPTION 'CRQ_OFFICE: a correction is declined by the course''s desk of entry' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN RAISE EXCEPTION 'CRQ_NOTE: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO q FROM assessment.correction_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRQ_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF q.state <> 'OPEN' THEN
        RAISE EXCEPTION 'CRQ_STATE: only an open correction is declined (this one is %)', q.state USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.correction_request SET state = 'DECLINED', closed_by = v_actor, closed_office = v_office, closed_at = now(), closed_note = btrim(p_note)
     WHERE id = p_id;
END $$;

-- ── the request follows the desks' own workflow ──
-- an amendment raised for the result: the request follows it
CREATE OR REPLACE FUNCTION assessment.correction_follows_amendment()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.student_id IS NOT NULL AND NEW.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN') THEN
            UPDATE assessment.correction_request SET state = 'IN_AMENDMENT', amendment_id = NEW.id
             WHERE sheet_id = NEW.sheet_id AND student_id = NEW.student_id AND state = 'OPEN';
        END IF;
    ELSIF NEW.stage IS DISTINCT FROM OLD.stage THEN
        IF NEW.stage = 'REFUSED' THEN
            UPDATE assessment.correction_request
               SET state = 'DECLINED', closed_at = now(), closed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
                   closed_office = nullif(current_setting('moaum.actor_office', true), ''),
                   closed_note = 'The amendment ' || NEW.ref || ' was refused: ' || coalesce(NEW.closed_reason, '')
             WHERE amendment_id = NEW.id AND state = 'IN_AMENDMENT';
        ELSIF NEW.stage = 'WITHDRAWN' THEN
            UPDATE assessment.correction_request SET state = 'OPEN', amendment_id = NULL
             WHERE amendment_id = NEW.id AND state = 'IN_AMENDMENT';
        END IF;
    END IF;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_correction_follows_amendment ON assessment.amendment;
CREATE TRIGGER trg_correction_follows_amendment AFTER INSERT OR UPDATE OF stage ON assessment.amendment
    FOR EACH ROW EXECUTE FUNCTION assessment.correction_follows_amendment();

-- a new version of the mark (entered on the sheet, or an amendment applied): the request is resolved
CREATE OR REPLACE FUNCTION assessment.correction_resolved_by_score()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE assessment.correction_request
       SET state = 'RESOLVED', resolved_version = NEW.version, closed_at = now(), closed_by = NEW.entered_by, closed_office = NEW.entered_office,
           closed_note = 'The mark was corrected: version ' || NEW.version
     WHERE sheet_id = NEW.sheet_id AND student_id = NEW.student_id AND state IN ('OPEN', 'IN_AMENDMENT')
       AND NEW.version > coalesce(was_version, 0);
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_correction_resolved_by_score ON assessment.score;
CREATE TRIGGER trg_correction_resolved_by_score AFTER INSERT ON assessment.score
    FOR EACH ROW EXECUTE FUNCTION assessment.correction_resolved_by_score();

COMMIT;
