-- ═══════════════════════════════════════════════════════════════════════════
-- V232 — the migrated student's clearance is the import's act, not a trigger's
--
--   V231 cleared a migrated student by a trigger on every insert into
--   people.student that carried a matriculation number and no run. The
--   register is written that way by more than the import — the demo, the
--   checks, an integration fixture — and each of those students was cleared
--   at eight units without anyone meaning it. The act belongs to the one
--   path that brings a student over from the old portal: people.import_students.
--
--   So the trigger goes, and the import is wrapped: the rows are loaded as
--   before, then every student the payload names who has a matriculation
--   number, no matriculation run and a level from 100 to 400 is cleared by
--   clearance.clear_on_migration (idempotent — a unit with a word already on
--   file is left alone). The backfill V231 ran stands; it only reached
--   migrated students.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP TRIGGER IF EXISTS trg_student_migrated_cleared ON people.student;
DROP FUNCTION IF EXISTS clearance.trg_clear_migrated_student();

-- the loader as V117 wrote it keeps its body under a new name; the public name wraps it
ALTER FUNCTION people.import_students(jsonb) RENAME TO import_students_rows;

CREATE FUNCTION people.import_students(p_rows jsonb)
RETURNS TABLE (rows int, created int, updated int, no_programme int, bad_number int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM people.import_students_rows(p_rows) LOOP
        rows := r.rows; created := r.created; updated := r.updated; no_programme := r.no_programme;
        bad_number := r.bad_number; skipped := r.skipped; first_error := r.first_error;
        -- the students this payload brought over from the old portal arrive cleared (V231)
        PERFORM clearance.clear_on_migration(s.id)
           FROM people.student s
          WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
            AND s.current_level BETWEEN 100 AND 400
            AND upper(s.matric_no) IN (
                SELECT upper(btrim(coalesce(x->>'matric', x->>'matricNo', x->>'matric_no', x->>'matno', x->>'regNo', '')))
                  FROM jsonb_array_elements(p_rows) x);
        RETURN NEXT;
    END LOOP;
END $$;

COMMENT ON FUNCTION people.import_students(jsonb) IS
  'Loads students exported from the old portal (people.import_students_rows, V117) and clears each one at every unit for every purpose — the old portal''s clearance, carried over.';

COMMIT;
