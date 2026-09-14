-- ═══════════════════════════════════════════════════════════════════════════
-- V128 — make student sign-in fast (index the number it is looked up by)
--
--   StudentPortalRepository.byMatric finds the student with
--       upper(matric_no) = upper(:m) OR upper(admission_no) = upper(:m)
--                                     OR upper(jamb_reg_no) = upper(:m)
--   Wrapping the columns in upper() means the plain unique indexes on matric_no
--   and admission_no cannot be used, and jamb_reg_no has no index at all — so
--   every sign-in sequentially scanned the whole student table (tens of
--   thousands of rows) and sign-in crawled, worse under load.
--
--   Functional indexes on upper(...) let that exact query use a bitmap-OR of
--   three index scans instead of a full scan. No code change; the query already
--   matches these expressions.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE INDEX IF NOT EXISTS ix_student_upper_matric    ON people.student (upper(matric_no));
CREATE INDEX IF NOT EXISTS ix_student_upper_admission ON people.student (upper(admission_no));
CREATE INDEX IF NOT EXISTS ix_student_upper_jamb      ON people.student (upper(jamb_reg_no));

COMMIT;
