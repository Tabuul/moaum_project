-- ═══════════════════════════════════════════════════════════════════════════
-- V234 — the biography import clears its students on arrival too
--
--   V232 wrapped people.import_students (the core list) so that a student
--   brought over from the old portal arrives cleared. The migration desk's
--   first step is the fuller people.import_biography (V098/V111/V188) — the
--   same students with contact, guardian, sponsor and next-of-kin and a
--   sign-in account — and it inserts the same way: a matriculation number,
--   no matriculation run. It gets the same wrap, so whichever list the ICT
--   Directorate uploads, the students it brings in at 100 to 400 level are
--   cleared at every unit for every purpose by clearance.clear_on_migration.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER FUNCTION people.import_biography(jsonb) RENAME TO import_biography_rows;

CREATE FUNCTION people.import_biography(p_rows jsonb)
RETURNS TABLE (rows int, created int, updated int, no_programme int, bad_number int,
               contacts int, biography int, accounts int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM people.import_biography_rows(p_rows) LOOP
        rows := r.rows; created := r.created; updated := r.updated; no_programme := r.no_programme;
        bad_number := r.bad_number; contacts := r.contacts; biography := r.biography; accounts := r.accounts;
        skipped := r.skipped; first_error := r.first_error;
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

COMMENT ON FUNCTION people.import_biography(jsonb) IS
  'Loads the full student biography exported from the old portal (people.import_biography_rows, V188) and clears each student brought in at every unit — the old portal''s clearance, carried over.';

COMMIT;
