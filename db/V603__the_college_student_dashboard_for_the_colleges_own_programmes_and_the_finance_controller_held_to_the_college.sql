-- V603: the College student dashboard for the College's own programmes (MBBS) only, resolved on the server; the College of Health
-- Sciences' Finance Controller held to the College.
--
--   * The student's dashboard. The login gate sent every student of a College of Health Sciences programme at 200 Level or above
--     to the College's own student area (/college/student: the MBBS ladder, the Professional examinations, postings and
--     logbooks), read in the browser from the faculty's college. On the live-shaped copy that was 3,359 students of Nursing,
--     Medical Laboratory Science, Radiography, Biochemistry, Anatomy, Physiology and MSc Anatomy beside the 653 MBBS students the
--     area is for. The College's own programmes are the ones its machinery runs — college.programme_rule (V245: MB.BS, C00061)
--     — so college.runs_programme reads that record (no programme name or code in the code), and people.student_dashboard
--     gives the student's landing from the student's own programme and level: COLLEGE for a programme the College runs from
--     200 Level (100 Level registers on the University's form, as before), UNIVERSITY for every other student. A programme
--     change (V578, V587) changes it with the record; nothing is stored.
--   * The College's student area enforced on the server: college.register_level (V249's text) registers a year only for a
--     programme the College runs (COLLEGE_NOT_MBBS), and the API's student doors of the College refuse anyone else the same way.
--     A College of Health Sciences student remains the College's in every College report, finance figure and desk.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'V603: the College student dashboard for the College''s own programmes', true);

CREATE FUNCTION college.runs_programme(p_programme text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM college.programme_rule r WHERE r.programme_code = p_programme)
$fn$;
COMMENT ON FUNCTION college.runs_programme(text) IS
  'V603: whether the College of Health Sciences runs the programme on its own machinery (a college.programme_rule: MBBS) — the programmes whose students use the College''s own student area';

CREATE FUNCTION people.student_dashboard(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN college.runs_programme(st.programme_code) AND st.current_level >= 200 THEN 'COLLEGE' ELSE 'UNIVERSITY' END
      FROM people.student st
     WHERE st.id = p_student
$fn$;
COMMENT ON FUNCTION people.student_dashboard(uuid) IS
  'V603: the dashboard a student lands on — COLLEGE (the College''s own student area) for a programme the College runs, from 200 Level; UNIVERSITY for every other student, College of Health Sciences or not';

CREATE OR REPLACE FUNCTION college.register_level(p_student uuid, p_session text)
 RETURNS text
 LANGUAGE plpgsql
AS $fn$
DECLARE s people.student; v_session text; v_id uuid; d100 record; v_next int; e college.enrolment;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    -- V603: the College's own years are its own programmes' (college.programme_rule: MBBS), not every College of Health Sciences
    -- student's — Nursing, Medical Laboratory Science and the rest register on the University's form
    IF NOT college.runs_programme(s.programme_code) THEN
        RAISE EXCEPTION 'COLLEGE_NOT_MBBS: the College registers the years of its own programmes (MBBS); this programme registers on the University''s form'
            USING ERRCODE = '23514';
    END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION', 'ADMITTED') THEN RAISE EXCEPTION 'a student who is % does not register', lower(s.status) USING ERRCODE = '23514'; END IF;
    IF s.current_level < 200 THEN RAISE EXCEPTION '100 Level registers on the University''s form, by semester' USING ERRCODE = '23514'; END IF;
    IF s.current_level = 200 THEN
        SELECT * INTO d100 FROM college.decide_100(p_student);
        IF d100.outcome = 'WITHDRAW_ADVISED' THEN
            RAISE EXCEPTION 'the College''s 100 Level rule does not promote: % below 50', d100.failed USING ERRCODE = '23514',
                HINT = 'Every C-group course (Mathematics, Physics, Chemistry, Biology) is passed at 50 or more, with no resit; the College advises withdrawal.';
        END IF;
    END IF;
    -- the year in hand, or the one to open
    SELECT * INTO e FROM college.enrolment WHERE student_id = p_student AND state IN ('OPEN', 'RESIT') ORDER BY session DESC, level DESC LIMIT 1;
    IF NOT FOUND THEN
        v_session := coalesce(nullif(btrim(p_session), ''), college.level_session(s.current_level));
        v_id := college.open_enrolment(p_student, s.current_level, v_session, NULL);
        SELECT * INTO e FROM college.enrolment WHERE id = v_id;
    ELSIF e.level <> s.current_level THEN
        RAISE EXCEPTION 'the % Level year is still open; it closes by the Board''s decision before % Level opens', e.level, s.current_level USING ERRCODE = '23514';
    END IF;
    SELECT min(ordinal) INTO v_next FROM college.enrolment_semester WHERE enrolment_id = e.id AND registered_at IS NULL;
    IF v_next IS NOT NULL THEN
        RETURN college.register_semester(p_student, e.id, v_next);
    END IF;
    IF e.registered_at IS NOT NULL THEN RETURN 'already registered'; END IF;
    -- a clinical year: whole, on the first semester's fees
    IF NOT finance.semester_cleared(p_student, e.session, 1) THEN
        RAISE EXCEPTION 'the % Level fees for % are not yet cleared', e.level, e.session USING ERRCODE = '23514',
            HINT = 'Registration opens the moment the session''s first semester fees are confirmed; the second semester''s are due before its results.';
    END IF;
    UPDATE college.enrolment SET registered_at = now(),
           registered_items = (SELECT count(*) FROM college.posting p WHERE p.level = e.level)
                            + (SELECT count(*) FROM college.carry_over c WHERE c.student_id = p_student AND c.cleared_on IS NULL)
     WHERE id = e.id;
    RETURN 'registered';
END $fn$;

COMMIT;
