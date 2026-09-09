-- ═══════════════════════════════════════════════════════════════════════════
-- V049 — a friendlier course code
--
--   catalogue.course requires the code to be three letters, a space and three
--   digits (CSC 311). create_course now normalises what is typed — uppercases
--   it and fixes the spacing, so "csc311" and "csc  311" both become "CSC 311"
--   — and, when it still cannot be made to fit, refuses with a message that
--   says what a code looks like rather than the raw constraint name.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION catalogue.create_course(p_code text, p_title text, p_units int, p_semester int, p_level int, p_dept text, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; m text[]; v_code text;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is created by a person' USING ERRCODE = '23514';
    END IF;
    m := regexp_match(upper(btrim(coalesce(p_code, ''))), '^([A-Z]{3})\s*([0-9]{3})$');
    IF m IS NULL THEN
        RAISE EXCEPTION 'a course code is three letters, a space and three digits, like CSC 311 — % does not fit', coalesce(p_code, '')
            USING ERRCODE = '23514', HINT = 'Three letters for the subject and a three-digit number, e.g. MTH 212 or LAW 301.';
    END IF;
    v_code := m[1] || ' ' || m[2];
    IF p_units IS NULL OR p_units < 0 OR p_units > 12 THEN
        RAISE EXCEPTION 'a course is worth between 0 and 12 units' USING ERRCODE = '23514',
            HINT = 'Most courses are 2 or 3 units; the approved teaching maximum for a lecturer is 12.';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
        RAISE EXCEPTION 'a course with the code % already exists', v_code USING ERRCODE = '23505',
            HINT = 'A code is unique across the University; pick another.';
    END IF;
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
    VALUES (v_code, btrim(p_title), p_units, p_semester, p_level, p_dept, coalesce(nullif(btrim(p_kind), ''), 'Compulsory'), 'BOARD');
    RETURN v_code;
END $$;
