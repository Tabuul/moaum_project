-- ═══════════════════════════════════════════════════════════════════════════
-- V171 — restore an ended course to Live
--
--   Ending a course (V042) is deliberately not deleting it, and until now it was
--   also one-directional: an ENDED course showed "On old records" with no way
--   back. But a course is sometimes ended by mistake — most often when the
--   duplicate-ender keeps the wrong code, ending the one the department actually
--   wants to keep (e.g. two "Computer Programming II" rows, BSU-COS 202 and
--   COS 202, both ended while the department still teaches it).
--
--   restore_course reverses an end: it returns the course to LIVE and clears
--   ended_on, so it re-enters next session's registration. It is a curriculum
--   correction, so it is worked from the same desk that ends a course; the audit
--   spine records who did it. It refuses anything that is not ENDED.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION catalogue.restore_course(p_code text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text := upper(btrim(p_code));
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is restored by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course SET state = 'LIVE', ended_on = NULL WHERE code = v_code AND state = 'ENDED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no ended course % to restore', v_code USING ERRCODE = '23503',
            HINT = 'Only an ended course can be restored; a live course is already live.';
    END IF;
    RETURN v_code;
END $$;

COMMENT ON FUNCTION catalogue.restore_course(text) IS
'Reverse an end: return an ENDED course to LIVE and clear ended_on, so it re-enters registration. Refuses a course that is not ended.';

COMMIT;
