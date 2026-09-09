-- ═══════════════════════════════════════════════════════════════════════════
-- V058 — self-service password reset for staff and students (and applicants)
--
--   An applicant could already reset a forgotten password by email
--   (admissions.password_reset, V025). This adds the same for the main
--   sign-in: a staff member (iam.credential) or a student (iam.student_account)
--   asks for a reset, a one-hour token is emailed to the address on file, kept
--   only as a hash, and used once to set a new password. One table serves all
--   three, keyed by the kind of subject and its id.
--
--   Staff have no email of their own on the record — only a username that is
--   sometimes an email — so a staff reset can be delivered only when the
--   username is an email; the answer to the request is the same either way, so
--   nothing is revealed about whether an account exists.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE iam.password_reset (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_kind text NOT NULL,
    subject_id   uuid NOT NULL,
    token_hash   text NOT NULL,
    expires_at   timestamptz NOT NULL,
    used_at      timestamptz NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pwreset_kind CHECK (subject_kind IN ('STAFF', 'STUDENT', 'APPLICANT'))
);
CREATE INDEX ix_pwreset_token ON iam.password_reset (token_hash);
CREATE INDEX ix_pwreset_subject ON iam.password_reset (subject_kind, subject_id);

SELECT audit.exempt('iam.password_reset',
    'Holds a password-reset token hash and nothing that changes state on the record; '
    'the token is kept only as a hash, used once, and expires within the hour. The '
    'password change it authorises is itself on the spine (iam.credential_event and '
    'the account tables).');
