-- ═══════════════════════════════════════════════════════════════════════════
-- V249 — the College year as its own thing: cohorts, semesters, the calendar
--
--   The 100 Level year is the University's and is shorter than the College's
--   200 Level year, so a cohort promoted from 100 opens its 200 Level year
--   while the cohort before it is still in its second semester. Two cohorts
--   stand at one level, each in its own year, each sitting its own
--   examination once, at the end.
--
--   · a College year is the enrolment (V248) in the session it began; the
--     student's CURRENT year is their open enrolment, whatever the
--     University's session says (college.current_enrolment);
--   · the year's semesters (the prospectus template: two at 200, the Third
--     Semester at 300) are registered one at a time, each on its own fees —
--     college.enrolment_semester, college.register_semester. No result, no
--     standing comes of a semester: the one sitting is at the end of the year;
--   · a cohort is the enrolments at a level in a session (college.cohort):
--     the candidates for that cohort's examination, and nobody else;
--   · the College dates its years on college.semester (V245): the desk
--     refuses results for a cohort whose final semester has not begun
--     (college.year_reached_final), where dated; undated, nothing blocks;
--   · a level's next cohort opens in the latest session the College has
--     dated for it (college.level_session), independent of the University's
--     rollover; the College Secretary may open a student's enrolment from
--     the desk (college.open_enrolment).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the year's semesters, registered one at a time ──────────────────────────
CREATE TABLE college.enrolment_semester (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    enrolment_id  uuid NOT NULL REFERENCES college.enrolment(id),
    ordinal       int  NOT NULL,
    name          text NOT NULL,
    length_weeks  int  NULL,
    subjects      text NULL,
    registered_at timestamptz NULL,
    registered_by uuid NULL,
    UNIQUE (enrolment_id, ordinal)
);
SELECT audit.attach('college.enrolment_semester');
COMMENT ON TABLE college.enrolment_semester IS 'A semester of a College year (the prospectus template), registered on its own fees; nothing is graded at its end — the one sitting is the year''s.';

ALTER TABLE college.enrolment ADD COLUMN opened_by uuid NULL;
COMMENT ON COLUMN college.enrolment.opened_by IS 'The desk officer who opened the enrolment on the student''s behalf; NULL when the student registered it.';

-- the semesters of every year already open, from the template (nothing to do on a fresh database)
INSERT INTO college.enrolment_semester (enrolment_id, ordinal, name, length_weeks, subjects, registered_at)
SELECT e.id, t.ordinal, t.name, t.length_weeks, t.subjects, e.registered_at
  FROM college.enrolment e JOIN college.semester_template t ON t.level = e.level
 WHERE NOT EXISTS (SELECT 1 FROM college.enrolment_semester s WHERE s.enrolment_id = e.id AND s.ordinal = t.ordinal);

-- ── the student's current year ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION college.current_enrolment(p_student uuid)
RETURNS college.enrolment
LANGUAGE sql STABLE AS $$
    SELECT e FROM college.enrolment e WHERE e.student_id = p_student AND e.state IN ('OPEN', 'RESIT')
     ORDER BY e.session DESC, e.level DESC, e.attempt_no DESC LIMIT 1
$$;

-- the session a level's next cohort opens in: the latest the College has dated for it, else the University's current
CREATE OR REPLACE FUNCTION college.level_session(p_level int)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT s.session FROM college.semester s WHERE s.level = p_level AND s.starts_on IS NOT NULL AND s.starts_on <= current_date + 120
                       ORDER BY s.session DESC LIMIT 1),
                    (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'),
                    (SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1))
$$;

-- a cohort: the years open or closed at a level in a session, with the registration standing of each
CREATE OR REPLACE FUNCTION college.cohort(p_level int, p_session text)
RETURNS TABLE (student_id uuid, enrolment_id uuid, kind text, attempt_no int, state text, registered_at timestamptz,
               semesters int, semesters_registered int, fully_registered boolean)
LANGUAGE sql STABLE AS $$
    SELECT e.student_id, e.id, e.kind, e.attempt_no, e.state, e.registered_at,
           (SELECT count(*) FROM college.enrolment_semester s WHERE s.enrolment_id = e.id)::int,
           (SELECT count(*) FROM college.enrolment_semester s WHERE s.enrolment_id = e.id AND s.registered_at IS NOT NULL)::int,
           e.registered_at IS NOT NULL
      FROM college.enrolment e
     WHERE e.level = p_level AND e.session = p_session
$$;

-- the cohort's year has reached its final semester: the last dated semester has begun; undated, nothing blocks
CREATE OR REPLACE FUNCTION college.year_reached_final(p_level int, p_session text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT s.starts_on <= current_date FROM college.semester s
                      WHERE s.level = p_level AND s.session = p_session AND s.starts_on IS NOT NULL
                      ORDER BY s.ordinal DESC LIMIT 1), true)
$$;

-- ── opening a year, registering its semesters ───────────────────────────────
CREATE OR REPLACE FUNCTION college.open_enrolment(p_student uuid, p_level int, p_session text, p_by uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE s people.student; v_chs boolean; v_id uuid; v_last text; v_prior int; v_kind text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    SELECT f.college_code = 'CHS' INTO v_chs FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.code = s.programme_code;
    IF NOT coalesce(v_chs, false) THEN RAISE EXCEPTION 'not a College of Health Sciences student' USING ERRCODE = '23514'; END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION', 'ADMITTED') THEN RAISE EXCEPTION 'a student who is % does not enrol', lower(s.status) USING ERRCODE = '23514'; END IF;
    IF p_level < 200 THEN RAISE EXCEPTION '100 Level is the University''s year, registered by semester on its form' USING ERRCODE = '23514'; END IF;
    IF p_level <> s.current_level THEN RAISE EXCEPTION 'the student is at % Level, not %', s.current_level, p_level USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_id FROM college.enrolment WHERE student_id = p_student AND level = p_level AND session = p_session;
    IF FOUND THEN RETURN v_id; END IF;
    IF EXISTS (SELECT 1 FROM college.enrolment e WHERE e.student_id = p_student AND e.state IN ('OPEN', 'RESIT')) THEN
        RAISE EXCEPTION 'the student has a College year still open; it closes by the Board''s decision before another opens' USING ERRCODE = '23514';
    END IF;
    SELECT outcome INTO v_last FROM college.progression_decision
     WHERE student_id = p_student AND from_level = p_level AND state = 'CONFIRMED' ORDER BY session DESC, decided_on DESC LIMIT 1;
    IF v_last = 'APPEAL' THEN RAISE EXCEPTION 'the appeal to Senate is not yet granted' USING ERRCODE = '23514'; END IF;
    IF v_last IN ('WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED') THEN RAISE EXCEPTION 'the record at this level is closed by withdrawal' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_prior FROM college.enrolment WHERE student_id = p_student AND level = p_level;
    v_kind := CASE WHEN v_last = 'REPEAT' THEN 'REPEAT' ELSE 'REGULAR' END;
    INSERT INTO college.enrolment (student_id, level, session, attempt_no, kind, opened_by)
    VALUES (p_student, p_level, p_session, v_prior + 1, v_kind, p_by) RETURNING id INTO v_id;
    INSERT INTO college.enrolment_semester (enrolment_id, ordinal, name, length_weeks, subjects)
    SELECT v_id, t.ordinal, t.name, t.length_weeks, t.subjects FROM college.semester_template t WHERE t.level = p_level ORDER BY t.ordinal;
    RETURN v_id;
END $$;

-- a semester registered on its own fees (the whole session paid clears every semester); the year is registered when its last is
CREATE OR REPLACE FUNCTION college.register_semester(p_student uuid, p_enrolment uuid, p_ordinal int)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE e college.enrolment; sm college.enrolment_semester; v_left int; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO e FROM college.enrolment WHERE id = p_enrolment AND student_id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such enrolment' USING ERRCODE = '23503'; END IF;
    IF e.state = 'CLOSED' THEN RAISE EXCEPTION 'this College year is closed' USING ERRCODE = '23514'; END IF;
    SELECT * INTO sm FROM college.enrolment_semester WHERE enrolment_id = e.id AND ordinal = p_ordinal;
    IF NOT FOUND THEN RAISE EXCEPTION 'no semester % in this year', p_ordinal USING ERRCODE = '23503'; END IF;
    IF sm.registered_at IS NOT NULL THEN RETURN 'already registered'; END IF;
    IF EXISTS (SELECT 1 FROM college.enrolment_semester x WHERE x.enrolment_id = e.id AND x.ordinal < p_ordinal AND x.registered_at IS NULL) THEN
        RAISE EXCEPTION 'the earlier semester is registered first' USING ERRCODE = '23514';
    END IF;
    IF NOT finance.semester_cleared(p_student, e.session, p_ordinal) THEN
        RAISE EXCEPTION 'the % Level fees for % semester % are not yet cleared', e.level, e.session, p_ordinal USING ERRCODE = '23514',
            HINT = 'Each semester registers on its own fees; the whole session paid at once clears every semester.';
    END IF;
    UPDATE college.enrolment_semester SET registered_at = now(), registered_by = who WHERE id = sm.id;
    SELECT count(*) INTO v_left FROM college.enrolment_semester WHERE enrolment_id = e.id AND registered_at IS NULL;
    IF v_left = 0 THEN
        UPDATE college.enrolment SET registered_at = now(),
               registered_items = (SELECT count(*) FROM college.posting p WHERE p.level = e.level)
                                + (SELECT count(*) FROM college.enrolment_semester s WHERE s.enrolment_id = e.id)
                                + (SELECT count(*) FROM college.carry_over c WHERE c.student_id = p_student AND c.cleared_on IS NULL)
         WHERE id = e.id;
    END IF;
    RETURN 'registered semester ' || p_ordinal;
END $$;

-- the student's act, rewritten (V248 → V249): open the year in the session the College has dated for the level, then register
-- its next semester on that semester's fees; a level with no template semesters (the clinical years) registers whole on the first semester's fees
CREATE OR REPLACE FUNCTION college.register_level(p_student uuid, p_session text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE s people.student; v_chs boolean; v_session text; v_id uuid; d100 record; v_next int; e college.enrolment;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT f.college_code = 'CHS' INTO v_chs FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code WHERE p.code = s.programme_code;
    IF NOT coalesce(v_chs, false) THEN RAISE EXCEPTION 'not a College of Health Sciences student' USING ERRCODE = '23514'; END IF;
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
END $$;

GRANT SELECT, INSERT, UPDATE ON college.enrolment_semester TO app_results, app_registration, app_student;
GRANT SELECT ON college.enrolment_semester TO app_auditor;

COMMIT;
