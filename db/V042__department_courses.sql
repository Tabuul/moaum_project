-- ═══════════════════════════════════════════════════════════════════════════
-- V042 — a department creates and ends its own courses
--
--   A course belongs to exactly one department: the one that teaches it, sets
--   its score sheet and answers a query about a mark in it. So the department
--   adds it here — but into BOARD state, not live. Making it live is a
--   curriculum change the Faculty Board sees and Senate approves, because the
--   NUC accredits a programme on the courses it says it teaches.
--
--   Ending a course is not deleting it. A course no longer taught is ENDED with
--   a date; it leaves next session's registration and stays on every transcript
--   that carries it, because a degree earned in 2019 was earned on the courses
--   that existed in 2019.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION catalogue.create_course(p_code text, p_title text, p_units int, p_semester int, p_level int, p_dept text, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text := upper(btrim(p_code));
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is created by a person' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
        RAISE EXCEPTION 'a course with the code % already exists', v_code USING ERRCODE = '23505',
            HINT = 'A code is unique across the University; pick another.';
    END IF;
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
    VALUES (v_code, btrim(p_title), p_units, p_semester, p_level, p_dept, coalesce(nullif(btrim(p_kind), ''), 'Compulsory'), 'BOARD');
    RETURN v_code;
END $$;

CREATE OR REPLACE FUNCTION catalogue.end_course(p_code text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is ended by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course SET state = 'ENDED', ended_on = current_date WHERE code = p_code AND state <> 'ENDED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no course % to end', p_code USING ERRCODE = '23503',
            HINT = 'It may already be ended; an ended course stays on the records it belongs to.';
    END IF;
END $$;
