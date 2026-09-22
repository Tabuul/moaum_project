-- ═══════════════════════════════════════════════════════════════════════════
-- V220 — postgraduate applicants can reset their password
--
--   The self-service reset (V058) covers staff, students and undergraduate
--   applicants. A postgraduate applicant's account lives in admissions.pg_applicant,
--   so the reset's subject kinds are widened to admit PGAPPLICANT — the service
--   resolves a PG applicant by email or application number, e-mails a one-hour
--   link, and sets the new hash on admissions.pg_applicant.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE iam.password_reset DROP CONSTRAINT IF EXISTS ck_pwreset_kind;
ALTER TABLE iam.password_reset ADD  CONSTRAINT ck_pwreset_kind
    CHECK (subject_kind IN ('STAFF', 'STUDENT', 'APPLICANT', 'PGAPPLICANT'));

COMMIT;
