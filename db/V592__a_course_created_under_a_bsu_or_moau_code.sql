-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V592 — A course created under a BSU- or MOAU- code
--
--   The University's courses run under the plain code (CSC 311) and, for its two cohorts, under the BSU- and MOAU- codes
--   (BSU-PHY 106, MOAU-PHY 106 — V396, V402: the same course taught once, the results kept per code). A course could be renamed
--   to such a code (catalogue.rename_course, V333, through catalogue.normal_code) and arrive under one from an upload, but a
--   department creating one on the New course form was refused: catalogue.create_course (V049) still took three letters, a space
--   and three digits alone. It now takes, through the same catalogue.normal_code:
--     · three letters, a space and three digits (CSC 311), as before;
--     · BSU- or MOAU-, then the same (BSU-PHY 106, MOAU-PHY 106) — written loosely (bsu-phy106, MOAU - PHY 106) it is put right;
--   and nothing else (another prefix, a fourth letter, a letter after the number are refused as before). A code already held, or
--   held under another spelling, is refused as before (the key and catalogue.course_code_guard); the owner follows the subject
--   behind the prefix (catalogue.code_prefix reads PHY in BSU-PHY 106, V443).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V592: a course created under a BSU- or MOAU- code', true);

CREATE OR REPLACE FUNCTION catalogue.create_course(p_code text, p_title text, p_units integer, p_semester integer, p_level integer, p_dept text, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is created by a person' USING ERRCODE = '23514';
    END IF;
    -- V592: the plain code, or the plain code after BSU- or MOAU-, written loosely or not
    v_code := catalogue.normal_code(p_code);
    IF v_code IS NULL OR v_code !~ '^((BSU|MOAU)-)?[A-Z]{3} [0-9]{3}$' THEN
        RAISE EXCEPTION 'CAT_CODE: a course code is three letters, a space and three digits (CSC 311), or the same after BSU- or MOAU- (BSU-PHY 106, MOAU-PHY 106) — % fits neither', coalesce(p_code, '')
            USING ERRCODE = '23514', HINT = 'Three letters for the subject and a three-digit number, e.g. MTH 212; for a BSU- or MOAU- course the prefix and a hyphen first, e.g. BSU-PHY 106.';
    END IF;
    IF p_units IS NULL OR p_units < 0 OR p_units > 12 THEN
        RAISE EXCEPTION 'a course is worth between 0 and 12 units' USING ERRCODE = '23514',
            HINT = 'Most courses are 2 or 3 units; the approved teaching maximum for a lecturer is 12.';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
        RAISE EXCEPTION 'a course with the code % already exists', v_code USING ERRCODE = '23505',
            HINT = 'A code is unique across the University; pick another.';
    END IF;
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
    VALUES (v_code, btrim(p_title), p_units, p_semester, p_level, p_dept, coalesce(nullif(btrim(p_kind), ''), 'Core'), 'BOARD');
    RETURN v_code;
END $function$;
COMMENT ON FUNCTION catalogue.create_course(text, text, integer, integer, integer, text, text) IS
  'V049, V592: a course created — its code three letters, a space and three digits (CSC 311), or the same after BSU- or MOAU- (BSU-PHY 106), put right when written loosely; a code held, under any spelling, refused.';

COMMIT;
