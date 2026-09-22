-- ═══════════════════════════════════════════════════════════════════════════
-- V222 — the postgraduate applicant's documents, one per type
--
--   Instead of one combined credentials PDF, an applicant uploads each document
--   on its own: higher degree, undergraduate certificate, O'Level, birth
--   certificate / declaration of age, NYSC, LGA / indigene certificate, and a
--   change-of-name / marriage certificate (optional). The School downloads them
--   merged into one PDF. This widens the document-kind check to name each type;
--   the older CREDENTIALS (a single combined PDF) is kept so existing uploads
--   still read and still merge.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.pg_document DROP CONSTRAINT IF EXISTS ck_pg_doc_kind;
ALTER TABLE admissions.pg_document ADD CONSTRAINT ck_pg_doc_kind
    CHECK (kind IN ('TRANSCRIPT','DEGREE_CERTIFICATE','CV','PROPOSAL','NYSC','CREDENTIALS','PASSPORT','OTHER',
                    'HIGHER_DEGREE','UNDERGRAD_CERT','OLEVEL','BIRTH_CERTIFICATE','LGA_CERTIFICATE','NAME_CHANGE'));

COMMIT;
