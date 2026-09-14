-- ═══════════════════════════════════════════════════════════════════════════
-- V125 — set_migrated_default_passwords runs as its owner (SECURITY DEFINER)
--
--   The migration desk (results module) may INSERT iam.student_account when it
--   imports a biography, but it may not UPDATE it — password changes are the
--   student-portal module's ground. So set_migrated_default_passwords (an
--   UPDATE) was refused with "permission denied". It is a deliberate, scoped
--   bootstrap, so it runs as the function's owner, which holds the privilege,
--   with a fixed search_path so the definer rights cannot be hijacked.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION iam.set_migrated_default_passwords()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, iam, people
AS $$
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

COMMIT;
