-- ═══════════════════════════════════════════════════════════════════════════
-- V241 — held scripts in bulk: every line holds, or none does and each refusal is named
--
--   When the unregistered candidates are many, the lecturer fills a sheet
--   of them and uploads it. Each line goes through assessment.hold_script
--   with all its checks; a line that fails is noted and the rest are still
--   tried, so the lecturer hears every problem at once; if any failed, the
--   whole upload is refused and nothing is held.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.hold_scripts_bulk(p_sheet uuid, p_rows jsonb)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r jsonb; i int := 0; n int := 0; problems text[] := '{}'; v_num text; v_line text;
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the upload has no lines' USING ERRCODE = '23514',
            HINT = 'Fill the held-scripts template — matriculation number, CA, examination, outcome — and upload it.';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        i := i + 1;
        v_line := coalesce(r->>'line', i::text);
        v_num := btrim(coalesce(r->>'number', ''));
        BEGIN
            IF v_num = '' THEN RAISE EXCEPTION 'no matriculation number' USING ERRCODE = '23514'; END IF;
            PERFORM assessment.hold_script(p_sheet, v_num,
                                           nullif(btrim(coalesce(r->>'ca', '')), '')::int,
                                           nullif(btrim(coalesce(r->>'exam', '')), '')::int,
                                           r->>'outcome', r->>'note');
            n := n + 1;
        EXCEPTION WHEN OTHERS THEN
            problems := problems || format('Line %s (%s): %s', v_line, coalesce(nullif(v_num, ''), 'blank'), SQLERRM);
        END;
    END LOOP;
    IF array_length(problems, 1) > 0 THEN
        RAISE EXCEPTION '% of % line(s) refused — nothing held', array_length(problems, 1), i
            USING ERRCODE = '23514',
                  HINT = array_to_string(problems[1:12], ' · ') || CASE WHEN array_length(problems, 1) > 12 THEN ' · …' ELSE '' END;
    END IF;
    RETURN n;
END $$;

COMMENT ON FUNCTION assessment.hold_scripts_bulk(uuid, jsonb) IS
  'Holds every line of an upload through assessment.hold_script; if any line fails, names each failure and holds none.';

COMMIT;
