-- ═══════════════════════════════════════════════════════════════════════════
-- V122 — a default first password for migrated students (their own number)
--
--   Students carried over from the old portal were given a random, unusable
--   password (must_change = true) — they cannot sign in until it is set. This
--   provides a controlled bootstrap: set each such account's password to the
--   student's own number (matriculation, else admission, else JAMB), so they
--   can sign in the first time, and keep must_change = true so the portal makes
--   them choose a real password immediately.
--
--   SAFETY. A matriculation number is semi-public, so this default is a
--   ONE-TIME bootstrap, never a resting state — must_change stays true. It
--   touches ONLY accounts still on the random password (must_change = true), so
--   a student who has already chosen a password is never overwritten. It is a
--   function, invoked deliberately from the migration desk, not run on deploy.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION iam.set_migrated_default_passwords()
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'default passwords are set by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE iam.student_account a
       SET password_hash   = crypt(coalesce(s.matric_no, s.admission_no, s.jamb_reg_no), gen_salt('bf', 12)),
           must_change     = true,      -- the student must replace it on first sign-in
           failed_attempts = 0,
           locked_until    = NULL
      FROM people.student s
     WHERE s.id = a.student_id
       AND a.must_change = true          -- only accounts still on the random password; never a chosen one
       AND coalesce(s.matric_no, s.admission_no, s.jamb_reg_no) IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;

COMMENT ON FUNCTION iam.set_migrated_default_passwords() IS
  'Bootstrap: set each not-yet-activated student account''s password to the '
  'student''s own number, keeping must_change so it is replaced on first '
  'sign-in. Never overwrites a password a student has already chosen.';

COMMIT;
