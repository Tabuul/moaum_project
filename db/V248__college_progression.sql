-- ═══════════════════════════════════════════════════════════════════════════
-- V248 — the College's progression: the enrolment by level, the attendance
--        at result entry, the rule applied provisionally, the Board's confirmation
--
--   For MBBS students only (a programme under the College of Health
--   Sciences), from 200 Level; 100 Level runs on the University's courses
--   and GPA sheet, and the College's own 100 Level rule (pass every C-group
--   course at 50, no resit) decides promotion to 200 — read from those
--   results, never re-entered.
--
--   · college.enrolment — the student's year at a level: first attempt,
--     repeat year or Senate-approved final attempt; registered once the
--     level's fees are cleared (the first semester's, as the main portal's
--     gate; the second semester's is due before its results); RESIT while
--     a resit is pending; CLOSED by the Board's confirmation.
--   · college.exam_result gains the attendance the examiner types, and
--     BARRED: below the examination's minimum, the subject is failed.
--   · college.decide is the prospectus's rule for the whole examination:
--     promote (graduate at 600), resit, repeat, withdraw, appeal. It is
--     applied PROVISIONALLY the moment the last subject's marks are saved,
--     and CONFIRMED by the College Academic Board in one act, which moves
--     the student: the next level, the repeat year, the resit, the
--     withdrawal (a change of status on the Board's minute), graduation
--     with or without Honours.
--   · a Senate-approved appeal opens the fourth and final attempt at 600.
--   · college.register_level is the student's act: the fixed curriculum,
--     once the fees are cleared; EPS owed is carried until passed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the enrolment ────────────────────────────────────────────────────────────
CREATE TABLE college.enrolment (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL REFERENCES people.student(id),
    level            int  NOT NULL REFERENCES college.level(level),
    session          text NOT NULL REFERENCES policy.academic_session(name),
    attempt_no       int  NOT NULL DEFAULT 1,
    kind             text NOT NULL DEFAULT 'REGULAR',
    state            text NOT NULL DEFAULT 'OPEN',
    registered_at    timestamptz NULL,
    registered_items int  NULL,
    resit_subjects   uuid[] NOT NULL DEFAULT '{}',
    opened_on        date NOT NULL DEFAULT current_date,
    closed_on        date NULL,
    UNIQUE (student_id, level, session),
    CONSTRAINT ck_college_enrolment_kind  CHECK (kind IN ('REGULAR','REPEAT','APPEAL')),
    CONSTRAINT ck_college_enrolment_state CHECK (state IN ('OPEN','RESIT','CLOSED'))
);
SELECT audit.attach('college.enrolment');
COMMENT ON TABLE college.enrolment IS 'A College student''s year at a level: first attempt, repeat year or Senate-approved final attempt; registered once the fees are cleared; RESIT while a resit is pending; CLOSED by the Board''s confirmation.';

-- a course owed across levels (EPS): carried until passed
CREATE TABLE college.carry_over (
    student_id   uuid NOT NULL REFERENCES people.student(id),
    code         text NOT NULL,
    from_session text NOT NULL,
    note         text NULL,
    cleared_on   date NULL,
    PRIMARY KEY (student_id, code)
);
SELECT audit.attach('college.carry_over');

-- ── attendance at result entry; a barred subject ─────────────────────────────
ALTER TABLE college.exam_result ADD COLUMN attendance_pct numeric(5,2) NULL
    CONSTRAINT ck_college_result_attendance CHECK (attendance_pct IS NULL OR (attendance_pct >= 0 AND attendance_pct <= 100));
ALTER TABLE college.exam_result ADD COLUMN barred boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN college.exam_result.attendance_pct IS 'The attendance the examiner enters with the marks; below the examination''s minimum the candidate is barred and the subject failed.';

-- the judgement of one subject: passed, and whether barred by attendance
CREATE OR REPLACE FUNCTION college.judge(p_subject uuid, p_ca numeric, p_exam numeric, p_clinical numeric, p_attendance numeric)
RETURNS TABLE (passed boolean, barred boolean)
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_ca IS NULL AND p_exam IS NULL THEN NULL
                WHEN e.min_attendance_pct IS NOT NULL AND p_attendance IS NOT NULL AND p_attendance < e.min_attendance_pct THEN false
                ELSE college.passes(p_subject, p_ca, p_exam, p_clinical) END,
           e.min_attendance_pct IS NOT NULL AND p_attendance IS NOT NULL AND p_attendance < e.min_attendance_pct
      FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id
     WHERE s.id = p_subject
$$;

-- ── the decision: provisional, then confirmed ────────────────────────────────
ALTER TABLE college.progression_decision DROP CONSTRAINT ck_college_decision;
ALTER TABLE college.progression_decision ADD CONSTRAINT ck_college_decision
    CHECK (outcome IN ('PROMOTE','RESIT','REPEAT','WITHDRAW_ADVISED','WITHDRAW_REQUIRED','APPEAL','GRADUATE'));
ALTER TABLE college.progression_decision ADD COLUMN state text NOT NULL DEFAULT 'PROVISIONAL'
    CONSTRAINT ck_college_decision_state CHECK (state IN ('PROVISIONAL','CONFIRMED'));
ALTER TABLE college.progression_decision ADD COLUMN resit_subjects uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE college.progression_decision ADD COLUMN honours boolean NULL;
ALTER TABLE college.progression_decision ADD COLUMN confirmed_on date NULL;
ALTER TABLE college.progression_decision ADD COLUMN confirmed_by uuid NULL;

-- which attempt a result entered now is, from the enrolment: first, resit, repeat, or the Senate-approved final
CREATE OR REPLACE FUNCTION college.attempt_of(p_student uuid, p_level int, p_session text)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT CASE e.kind WHEN 'APPEAL' THEN 'SENATE_APPEAL' WHEN 'REPEAT' THEN 'REPEAT'
                                        ELSE CASE WHEN e.state = 'RESIT' THEN 'RESIT' ELSE 'FIRST' END END
                       FROM college.enrolment e WHERE e.student_id = p_student AND e.level = p_level AND e.session = p_session), 'FIRST')
$$;

-- the prospectus's rule for the whole examination, from the latest result in each subject this session
CREATE OR REPLACE FUNCTION college.decide(p_student uuid, p_exam text, p_session text)
RETURNS TABLE (outcome text, failed int, n_subjects int, latest_attempt text, failed_subjects uuid[], failed_names text, rule_ref text)
LANGUAGE plpgsql STABLE AS $$
DECLARE e college.professional_exam; n int; have int; nfail int; la text; fs uuid[]; fn text; o text;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = upper(p_exam);
    IF NOT FOUND THEN RETURN; END IF;
    SELECT count(*) INTO n FROM college.exam_subject s WHERE s.exam_id = e.id;
    WITH latest AS (
        SELECT DISTINCT ON (r.subject_id) r.subject_id, s.name, r.attempt, r.passed
          FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id
         WHERE r.student_id = p_student AND r.session = p_session AND s.exam_id = e.id AND r.passed IS NOT NULL
         ORDER BY r.subject_id, CASE r.attempt WHEN 'FIRST' THEN 1 WHEN 'RESIT' THEN 2 WHEN 'REPEAT' THEN 3 ELSE 4 END DESC)
    SELECT count(*), count(*) FILTER (WHERE NOT l.passed),
           (SELECT l2.attempt FROM latest l2 ORDER BY CASE l2.attempt WHEN 'FIRST' THEN 1 WHEN 'RESIT' THEN 2 WHEN 'REPEAT' THEN 3 ELSE 4 END DESC LIMIT 1),
           coalesce(array_agg(l.subject_id ORDER BY l.name) FILTER (WHERE NOT l.passed), '{}'),
           string_agg(l.name, ', ' ORDER BY l.name) FILTER (WHERE NOT l.passed)
      INTO have, nfail, la, fs, fn FROM latest l;
    IF have < n THEN
        RETURN QUERY SELECT NULL::text, nfail, n, coalesce(la, 'FIRST'), fs, fn, NULL::text; RETURN;
    END IF;
    o := CASE WHEN nfail = 0 THEN CASE WHEN e.level = 600 THEN 'GRADUATE' ELSE 'PROMOTE' END
              WHEN la = 'RESIT' THEN 'REPEAT'
              WHEN la = 'SENATE_APPEAL' THEN 'WITHDRAW_REQUIRED'
              WHEN la = 'REPEAT' THEN CASE WHEN e.appeal_to_senate THEN 'APPEAL'
                                           WHEN e.code IN ('CPE','PE1') THEN 'WITHDRAW_ADVISED' ELSE 'WITHDRAW_REQUIRED' END
              ELSE college.next_attempt(e.code, nfail, n) END;
    RETURN QUERY SELECT o, nfail, n, la, fs, fn,
        CASE o WHEN 'PROMOTE' THEN 'Passed every subject at 50 or more' || CASE WHEN la = 'RESIT' THEN ', at the resit' ELSE '' END
               WHEN 'GRADUATE' THEN 'Passed the Final MBBS'
               ELSE e.name || ': ' || e.on_failure END;
END $$;
COMMENT ON FUNCTION college.decide(uuid, text, text) IS 'The prospectus''s rule for the whole examination from the latest result in each subject this session: NULL outcome while a subject is unresulted.';

-- the rule applied provisionally the moment every subject has a result; a confirmed decision is not touched
CREATE OR REPLACE FUNCTION college.apply_provisional(p_student uuid, p_exam text, p_session text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE d record; e college.professional_exam;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = upper(p_exam);
    SELECT * INTO d FROM college.decide(p_student, p_exam, p_session);
    IF d.outcome IS NULL THEN RETURN NULL; END IF;
    INSERT INTO college.progression_decision (student_id, from_level, session, outcome, rule_ref, resit_subjects, state)
    VALUES (p_student, e.level, p_session, d.outcome, d.rule_ref, CASE WHEN d.outcome = 'RESIT' THEN d.failed_subjects ELSE '{}' END, 'PROVISIONAL')
    ON CONFLICT (student_id, from_level, session) DO UPDATE
       SET outcome = EXCLUDED.outcome, rule_ref = EXCLUDED.rule_ref, resit_subjects = EXCLUDED.resit_subjects, decided_on = current_date,
           state = 'PROVISIONAL', confirmed_on = NULL, confirmed_by = NULL
     -- a provisional decision follows the marks; a confirmed RESIT is re-opened by the resit's own results, for the Board to confirm again
     WHERE college.progression_decision.state = 'PROVISIONAL'
        OR (college.progression_decision.state = 'CONFIRMED' AND college.progression_decision.outcome = 'RESIT' AND d.latest_attempt = 'RESIT');
    RETURN d.outcome;
END $$;

-- the Board's act: every provisional decision of the examination in the session confirmed, and the student moved
CREATE OR REPLACE FUNCTION college.confirm_decisions(p_exam text, p_session text, p_minute text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE e college.professional_exam; d record; n int := 0; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_hon boolean; v_instrument text;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = upper(p_exam);
    IF NOT FOUND THEN RAISE EXCEPTION 'no such examination %', p_exam USING ERRCODE = '23503'; END IF;
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'the Board confirms on a minute, and none was cited' USING ERRCODE = '23514';
    END IF;
    v_instrument := 'College Academic Board minute ' || btrim(p_minute) || ' (' || e.name || ', ' || p_session || ')';
    FOR d IN SELECT * FROM college.progression_decision WHERE session = p_session AND from_level = e.level AND state = 'PROVISIONAL' LOOP
        v_hon := CASE WHEN d.outcome = 'GRADUATE' THEN college.honours(d.student_id) END;
        UPDATE college.progression_decision SET state = 'CONFIRMED', confirmed_on = current_date, confirmed_by = who,
               minute = coalesce(minute, btrim(p_minute)), honours = v_hon WHERE id = d.id;
        IF d.outcome = 'RESIT' THEN
            UPDATE college.enrolment SET state = 'RESIT', resit_subjects = d.resit_subjects
             WHERE student_id = d.student_id AND level = e.level AND session = p_session;
        ELSE
            UPDATE college.enrolment SET state = 'CLOSED', closed_on = current_date
             WHERE student_id = d.student_id AND level = e.level AND session = p_session;
        END IF;
        IF d.outcome = 'PROMOTE' THEN
            UPDATE people.student st SET current_level = e.level + 100
              FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
             WHERE st.id = d.student_id AND p.code = st.programme_code AND f.college_code = 'CHS';
        ELSIF d.outcome IN ('WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED') THEN
            PERFORM people.change_status(d.student_id, 'WITHDRAWN', v_instrument, current_date,
                CASE d.outcome WHEN 'WITHDRAW_ADVISED' THEN 'Advised to withdraw from the MBBS programme: ' ELSE 'Required to withdraw from the MBBS programme: ' END || coalesce(d.rule_ref, ''));
        ELSIF d.outcome = 'GRADUATE' THEN
            PERFORM people.change_status(d.student_id, 'GRADUATED', v_instrument, current_date,
                'Passed the Final MBBS' || CASE WHEN v_hon THEN ' with Honours (a distinction in each of the four Professional examinations)' ELSE '' END);
        END IF;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- Senate's approval of an appeal: the fourth and final attempt at 600 Level opens as an enrolment to register
CREATE OR REPLACE FUNCTION college.grant_appeal(p_student uuid, p_session text, p_minute text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_last text; v_prior int; v_id uuid;
BEGIN
    SELECT outcome INTO v_last FROM college.progression_decision
     WHERE student_id = p_student AND from_level = 600 AND state = 'CONFIRMED' ORDER BY session DESC, decided_on DESC LIMIT 1;
    IF v_last IS DISTINCT FROM 'APPEAL' THEN
        RAISE EXCEPTION 'no appeal stands for this student: the last confirmed decision at 600 Level is %', coalesce(v_last, 'none') USING ERRCODE = '23514';
    END IF;
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN RAISE EXCEPTION 'Senate''s approval is recorded on its minute, and none was cited' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_prior FROM college.enrolment WHERE student_id = p_student AND level = 600;
    INSERT INTO college.enrolment (student_id, level, session, attempt_no, kind)
    VALUES (p_student, 600, p_session, v_prior + 1, 'APPEAL')
    ON CONFLICT (student_id, level, session) DO UPDATE SET kind = 'APPEAL', state = 'OPEN', attempt_no = EXCLUDED.attempt_no
    RETURNING id INTO v_id;
    UPDATE college.progression_decision SET minute = coalesce(minute, '') || ' · Senate: ' || btrim(p_minute)
     WHERE student_id = p_student AND from_level = 600 AND state = 'CONFIRMED' AND outcome = 'APPEAL';
    RETURN v_id;
END $$;

-- ── 100 Level by the College's rule, read from the University's results ──────
-- promote when every published C-group course (not GST) is at 50 or more; GST failed is carried; a C-group fail is advice to withdraw
CREATE OR REPLACE FUNCTION college.decide_100(p_student uuid)
RETURNS TABLE (outcome text, failed text, carried text, published int, registered int)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    r AS (SELECT x.* FROM assessment.student_results(p_student) x CROSS JOIN s WHERE x.session = s.entry_session AND s.entry_level = 100)
    SELECT CASE WHEN (SELECT count(*) FROM r) = 0 THEN NULL
                WHEN (SELECT count(*) FROM r WHERE NOT published) > 0 THEN 'INCOMPLETE'
                WHEN EXISTS (SELECT 1 FROM r WHERE published AND course_code NOT LIKE 'GST%' AND coalesce(total, 0) < 50) THEN 'WITHDRAW_ADVISED'
                ELSE 'PROMOTE' END,
           (SELECT string_agg(course_code, ', ' ORDER BY course_code) FROM r WHERE published AND course_code NOT LIKE 'GST%' AND coalesce(total, 0) < 50),
           (SELECT string_agg(course_code, ', ' ORDER BY course_code) FROM r WHERE published AND course_code LIKE 'GST%' AND coalesce(total, 0) < 50),
           (SELECT count(*) FROM r WHERE published)::int, (SELECT count(*) FROM r)::int
$$;

-- ── the student's act: register the level's fixed curriculum once the fees are cleared ──
CREATE OR REPLACE FUNCTION college.register_level(p_student uuid, p_session text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE s people.student; v_chs boolean; v_e college.enrolment; v_last text; v_prior int; v_kind text; v_items int; d100 record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    SELECT f.college_code = 'CHS' INTO v_chs FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.code = s.programme_code;
    IF NOT coalesce(v_chs, false) THEN RAISE EXCEPTION 'not a College of Health Sciences student' USING ERRCODE = '23514'; END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION', 'ADMITTED') THEN
        RAISE EXCEPTION 'a student who is % does not register', lower(s.status) USING ERRCODE = '23514';
    END IF;
    IF s.current_level < 200 THEN
        RAISE EXCEPTION '100 Level registers on the University''s form, by semester' USING ERRCODE = '23514';
    END IF;
    IF NOT finance.semester_cleared(p_student, p_session, 1) THEN
        RAISE EXCEPTION 'the % Level fees for % are not yet cleared', s.current_level, p_session USING ERRCODE = '23514',
            HINT = 'Registration opens the moment the session''s first semester fees are confirmed; the second semester''s are due before its results.';
    END IF;
    IF s.current_level = 200 THEN
        SELECT * INTO d100 FROM college.decide_100(p_student);
        IF d100.outcome = 'WITHDRAW_ADVISED' THEN
            RAISE EXCEPTION 'the College''s 100 Level rule does not promote: % below 50', d100.failed USING ERRCODE = '23514',
                HINT = 'Every C-group course (Mathematics, Physics, Chemistry, Biology) is passed at 50 or more, with no resit; the College advises withdrawal.';
        END IF;
    END IF;
    SELECT * INTO v_e FROM college.enrolment WHERE student_id = p_student AND level = s.current_level AND session = p_session;
    IF FOUND THEN
        IF v_e.registered_at IS NOT NULL THEN RETURN 'already registered'; END IF;
    ELSE
        SELECT outcome INTO v_last FROM college.progression_decision
         WHERE student_id = p_student AND from_level = s.current_level AND state = 'CONFIRMED' ORDER BY session DESC, decided_on DESC LIMIT 1;
        IF v_last = 'APPEAL' THEN RAISE EXCEPTION 'the appeal to Senate is not yet granted' USING ERRCODE = '23514'; END IF;
        IF v_last IN ('WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED') THEN RAISE EXCEPTION 'the record at this level is closed by withdrawal' USING ERRCODE = '23514'; END IF;
        SELECT count(*) INTO v_prior FROM college.enrolment WHERE student_id = p_student AND level = s.current_level;
        v_kind := CASE WHEN v_last = 'REPEAT' THEN 'REPEAT' ELSE 'REGULAR' END;
        INSERT INTO college.enrolment (student_id, level, session, attempt_no, kind) VALUES (p_student, s.current_level, p_session, v_prior + 1, v_kind)
        RETURNING * INTO v_e;
    END IF;
    SELECT (SELECT count(*) FROM college.posting p WHERE p.level = s.current_level)
         + (SELECT count(*) FROM college.semester_template t WHERE t.level = s.current_level)
         + (SELECT count(*) FROM college.carry_over c WHERE c.student_id = p_student AND c.cleared_on IS NULL) INTO v_items;
    UPDATE college.enrolment SET registered_at = now(), registered_items = v_items WHERE id = v_e.id;
    RETURN 'registered';
END $$;

GRANT SELECT, INSERT, UPDATE ON college.enrolment, college.carry_over TO app_results, app_registration, app_student;
GRANT SELECT ON college.enrolment, college.carry_over TO app_auditor;

COMMIT;
