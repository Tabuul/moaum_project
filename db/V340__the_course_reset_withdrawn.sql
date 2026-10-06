-- ═══════════════════════════════════════════════════════════════════════════
-- V340 — the course catalogue reset is withdrawn
--
--   The reset V338 added (catalogue.course_reset, with its preview, scope and helpers, and the Course Catalogue Reset &
--   Upload page) is rolled back at the University's request. On the live database it was never run: catalogue.course_reset
--   and catalogue.course_reset_item hold no row and no course carries a reset_batch_id.
--
--   What this does: drops the reset's functions, so no path — the API, a page, or SQL — can reset the catalogue.
--   What it deliberately leaves:
--     · the tables catalogue.course_reset and catalogue.course_reset_item, and catalogue.course.reset_batch_id with its key.
--       They are empty and harmless; the course uploads (catalogue.import_catalogue and the existing per-programme
--       catalogue.import_courses_rows) still read reset_batch_id, which now stays NULL, so removing the column would mean
--       rewriting the existing Course Upload. Dropping them gains nothing and risks the upload.
--     · everything else V338 added: the owner programme and Change owner with its history, the offering's title snapshot
--       read by results, transcripts, sheets and slips, prerequisites, and the owner/offering upload's functions.
--   No row of any table is written, changed or deleted.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP FUNCTION IF EXISTS catalogue.course_reset(text, text, text, text);
DROP FUNCTION IF EXISTS catalogue.course_reset_preview(text, text);
DROP FUNCTION IF EXISTS catalogue.reset_courses(text[], text[], text);
DROP FUNCTION IF EXISTS catalogue.reset_scope(text, text);
-- the two helpers existed only to tell the reset what to keep
DROP FUNCTION IF EXISTS catalogue.course_has_history(text);
DROP FUNCTION IF EXISTS catalogue.offering_has_history(uuid);

COMMENT ON TABLE catalogue.course_reset IS 'V338, withdrawn by V340: the record of a course catalogue reset. The reset no longer exists; the table is kept empty and unused.';
COMMENT ON TABLE catalogue.course_reset_item IS 'V338, withdrawn by V340: what a course catalogue reset did, item by item. The reset no longer exists; the table is kept empty and unused.';
COMMENT ON COLUMN catalogue.course.reset_batch_id IS 'V338, withdrawn by V340: the reset that archived the course. No reset exists any more; always NULL. Kept because the course uploads still read it.';

COMMIT;
