-- ═══════════════════════════════════════════════════════════════════════════
-- V060 — a staff member's email and phone on the record
--
--   iam.person carried a name and a staff number but no contact of its own, so
--   a staff password reset (V058) could only be delivered when the username
--   happened to be an email. This gives a person an email and a phone the
--   Registry sets, so a reset — and any notice — reaches staff the same way it
--   reaches students and applicants.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE iam.person ADD COLUMN IF NOT EXISTS email text NULL;
ALTER TABLE iam.person ADD COLUMN IF NOT EXISTS phone text NULL;

COMMENT ON COLUMN iam.person.email IS 'The staff member''s email, set by the Registry; where password resets and notices are sent.';
COMMENT ON COLUMN iam.person.phone IS 'The staff member''s phone, set by the Registry; where an SMS notice is sent.';
