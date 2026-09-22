-- ═══════════════════════════════════════════════════════════════════════════
-- V219 — a postgraduate applicant's passport photograph
--
--   After paying the application fee, an applicant uploads their credentials
--   (V210) and now also a passport photograph. It is stored on the existing
--   admissions.pg_document store as a PASSPORT document (a JPEG/PNG rather than
--   the credentials PDF), so this widens the document-kind check to admit it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.pg_document DROP CONSTRAINT IF EXISTS ck_pg_doc_kind;
ALTER TABLE admissions.pg_document ADD CONSTRAINT ck_pg_doc_kind
    CHECK (kind IN ('TRANSCRIPT','DEGREE_CERTIFICATE','CV','PROPOSAL','NYSC','CREDENTIALS','PASSPORT','OTHER'));

COMMIT;
