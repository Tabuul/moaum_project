-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V709 · A postgraduate applicant migrated from the old portal signs in on either number first
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 30 October 2026, with the sign-in page refusing an old-portal number (S00220260204082731, "Wrong
--  username or password"): "pg admitted programme cant login from the migrated lagacy data". Asked what a migrated applicant's first
--  password should be: either number — the old portal's or this portal's PG/YY/NNNNNN — and they choose their own straight after.
--
--  Why they could not: V675 opens a migrated applicant's sign-in sealed (a cost-12 hash of a secret nobody holds; they were to use
--  "Forgot password" on their email, which many do not have or did not read), and the sign-in page sent a number of no shape it
--  knows (the old portal's) to the staff door alone, though the postgraduate door finds an applicant by it. One the old portal had
--  screened was admitted to the register on the same sealed password, so the student portal did not open either.
--
--  1 · An applicant the migration creates (admissions.pg_applicant written while moaum.pg_migration is set, V675) is to choose their
--      own password (must_change_password, V706's flag): while it holds, the API opens the account on the application number or the
--      old portal's, however typed, and the change is required before anything else (ApplicantPasswordGate). No number is hashed
--      here: bcrypt at cost 12 for each of thousands of rows would hold a deploy and an import for minutes.
--  2 · A student account opened from an applicant still on a number (admissions.pg_admit copies the applicant's hash) is to choose
--      its own too (iam.student_account.must_change): the student door's first password is the number signed in with (V178, V267),
--      here the admission number. Set when the application gains its student (trg_pg_application_student_first_password).
--  3 · The password the applicant chooses — on the applicant portal or by the reset link — is carried to a student account that has
--      never been signed into and still holds what it was opened with (trg_pg_applicant_password_carried), so "sign in to the
--      student portal with the admission number and the password you chose here" holds.
--  4 · The migration's notice (admissions.pg_mig_tell, restated from V675) says how to sign in: the old number, the new number or
--      the email, and either number as the first password; the admitted, the admission number as both. An applicant the migration
--      linked rather than created keeps their own password and is told as before.
--  5 · The applicants the migration has created already, never signed in, never reset (by the School, V706, or by the link), are
--      put on either number; their student accounts never signed into, on the admission number. The migration names both counts.
--  The sign-in page's own part (an unknown number tried at the postgraduate door after the staff door) is in the frontend.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V709: a migrated postgraduate applicant signs in on either number first (the University''s word of 30 October 2026)', true);

-- ── 1 · an applicant the migration creates is to choose their own password; a number opens the account until then ──
CREATE OR REPLACE FUNCTION admissions.pg_applicant_first_password() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF nullif(current_setting('moaum.pg_migration', true), '') IS NOT NULL THEN
        NEW.must_change_password := true;
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_first_password() IS
  'V709: an applicant written by the old portal''s migration (moaum.pg_migration set, V675) opens on a number — the application number or the old portal''s — and chooses their own password at the first sign-in.';
DROP TRIGGER IF EXISTS trg_pg_applicant_first_password ON admissions.pg_applicant;
CREATE TRIGGER trg_pg_applicant_first_password BEFORE INSERT ON admissions.pg_applicant
    FOR EACH ROW EXECUTE FUNCTION admissions.pg_applicant_first_password();

COMMENT ON COLUMN admissions.pg_applicant.must_change_password IS
  'V706, V709: the applicant chooses their own password at the next sign-in, before anything else; until then the application number or the old portal''s opens the account. Set by a reset (V706) and for an applicant the old portal''s migration created (V709).';

-- ── 2 · a student account opened from an applicant still on a number opens on the admission number first ──
CREATE OR REPLACE FUNCTION admissions.pg_student_first_password() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE iam.student_account s
       SET must_change = true
      FROM admissions.pg_applicant p
     WHERE p.id = NEW.applicant_id AND p.must_change_password
       AND s.student_id = NEW.student_id AND s.password_hash = p.password_hash
       AND s.last_signed_in_at IS NULL AND NOT s.must_change AND s.temp_expires_at IS NULL;
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION admissions.pg_student_first_password() IS
  'V709: an application admitted to the register while its applicant is still on a number: the student account, opened with the applicant''s hash (admissions.pg_admit), opens on the admission number first and the student chooses their own (the student door''s first password).';
DROP TRIGGER IF EXISTS trg_pg_application_student_first_password ON admissions.pg_application;
CREATE TRIGGER trg_pg_application_student_first_password AFTER UPDATE OF student_id ON admissions.pg_application
    FOR EACH ROW WHEN (OLD.student_id IS NULL AND NEW.student_id IS NOT NULL)
    EXECUTE FUNCTION admissions.pg_student_first_password();

-- ── 3 · the applicant's own password carried to a student account never signed into ──
CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_carried() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE iam.student_account s
       SET password_hash = NEW.password_hash, must_change = false, failed_attempts = 0, locked_until = NULL
      FROM admissions.pg_application ap
     WHERE ap.applicant_id = NEW.id AND ap.student_id IS NOT NULL AND s.student_id = ap.student_id
       AND s.password_hash = OLD.password_hash AND s.last_signed_in_at IS NULL AND s.temp_expires_at IS NULL;
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_carried() IS
  'V709: the password a postgraduate applicant chooses (on the applicant portal, or by the reset link) carried to their student account while that account has never been signed into and still holds the hash it was opened with.';
DROP TRIGGER IF EXISTS trg_pg_applicant_password_carried ON admissions.pg_applicant;
CREATE TRIGGER trg_pg_applicant_password_carried AFTER UPDATE OF password_hash ON admissions.pg_applicant
    FOR EACH ROW WHEN (NEW.password_hash IS DISTINCT FROM OLD.password_hash AND NOT NEW.must_change_password)
    EXECUTE FUNCTION admissions.pg_applicant_password_carried();

-- ── 4 · the migration's notice says how to sign in (restated from V675; only the sign-in words change) ──
CREATE OR REPLACE FUNCTION admissions.pg_mig_tell(p_app uuid) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE a admissions.pg_application; p admissions.pg_applicant; lg admissions.pg_legacy_application; st people.student;
        v_url text; v_sub text; v_where text; v_body text; v_review boolean; v_first boolean; v_student_first boolean;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app;
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
    SELECT * INTO lg FROM admissions.pg_legacy_application WHERE application_id = p_app;
    IF a.id IS NULL OR lg.application_id IS NULL THEN RETURN; END IF;
    v_url := coalesce(nullif(platform.portal_url(), ''), 'the University portal');
    v_review := EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_app AND x.state = 'REQUIRES_REVIEW');
    v_first := coalesce(p.must_change_password, false);   -- V709: on a number until they choose their own
    IF a.state = 'ADMITTED' THEN
        SELECT * INTO st FROM people.student WHERE id = a.student_id;
        v_student_first := EXISTS (SELECT 1 FROM iam.student_account s WHERE s.student_id = a.student_id AND s.must_change AND s.temp_expires_at IS NULL);
        v_sub := 'Your postgraduate admission is on the new University portal';
        v_where := 'Your admission has been brought to the new portal as it stood: you are on the University register, admission number '
                   || coalesce(st.admission_no, '') || coalesce(', matriculation number ' || st.matric_no, '') || '. Sign in to the student portal at '
                   || v_url || ' with your admission number'
                   || CASE WHEN v_student_first
                           THEN ', which is also your first password; you choose your own password at once. '
                           ELSE '; if you have not set a password on the new portal, choose "Forgot password" to set one. ' END
                   || 'Your school fees and course registration are there.';
    ELSIF a.state IN ('OFFERED', 'ACCEPTED') THEN
        v_sub := 'Your postgraduate admission record is on the new University portal';
        v_where := 'Your admission has been brought to the new portal as it stood: '
                   || CASE WHEN a.state = 'ACCEPTED' THEN 'your offer of admission is accepted'
                           WHEN v_review THEN 'your offer of admission stands, and the acceptance fee you paid on the old portal is being verified by the Bursary — you are not asked to pay it again meanwhile'
                           ELSE 'your offer of admission stands; accept it on the applicant portal' END
                   || '. You do not apply or get admitted again.';
    ELSE
        v_sub := 'Your postgraduate application is on the new University portal';
        v_where := 'Your application has been brought to the new portal as it stood; you do not apply again'
                   || CASE WHEN v_review THEN ', and the fee you paid on the old portal is being verified by the Bursary — you are not asked to pay it again meanwhile' ELSE '' END || '.';
    END IF;
    v_body := 'Dear ' || p.other_names || ',' || E'\n\n'
              || 'Your postgraduate application on the University''s old portal (application number ' || lg.legacy_application_no || ') is now on the new portal. '
              || v_where || E'\n\n'
              || 'Your new application number is ' || a.application_no || '; your old number stays on your record and finds it too. '
              || CASE WHEN v_first
                      THEN 'Sign in to the applicant portal at ' || v_url || '/pg/portal with your old number (' || lg.legacy_application_no || '), your new number ('
                           || a.application_no || ') or your email, ' || p.email || '. Your first password is either application number, old or new; '
                           || 'you choose your own password at once.'
                      ELSE 'Sign in to the applicant portal at ' || v_url || '/pg/portal with your email, ' || p.email
                           || '; if you have not set a password on the new portal, choose "Forgot password" to set one.' END
              || E'\n\n'
              || 'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi';
    PERFORM platform.queue_notice('EMAIL', p.email, v_sub, v_body, 'pg_application', p_app, 'pg-migrated:' || p_app, NULL, 'NORMAL');
    PERFORM platform.queue_notice('SMS', p.phone, v_sub,
            'MOAUM PG: your application ' || lg.legacy_application_no || ' is now ' || a.application_no || ' on the new portal. '
            || CASE WHEN v_first THEN 'Sign in with either number, and either number as your first password; then choose your own.'
                    ELSE 'Sign in with your email; use Forgot password to set a password.' END,
            'pg_application', p_app, 'pg-migrated:' || p_app, NULL, 'NORMAL');
END $fn$;
COMMENT ON FUNCTION admissions.pg_mig_tell(uuid) IS
  'V675, V709: a migrated applicant told once, by email and SMS, where the migration left them and how to sign in — on a number (the old portal''s or this portal''s, either as the first password) while they are to choose their own; no fee figure.';

-- ── 5 · the applicants the migration has created already, and their students ──
DO $$
DECLARE n_app int; n_stu int;
BEGIN
    UPDATE admissions.pg_applicant p
       SET must_change_password = true
     WHERE NOT p.must_change_password AND p.last_signed_in_at IS NULL AND p.password_reset_at IS NULL
       AND EXISTS (SELECT 1 FROM admissions.pg_migration_row r JOIN admissions.pg_application ap ON ap.id = r.application_id
                    WHERE ap.applicant_id = p.id AND r.action = 'CREATE' AND r.result = 'CREATED')
       AND NOT EXISTS (SELECT 1 FROM iam.password_reset x WHERE x.subject_kind = 'PGAPPLICANT' AND x.subject_id = p.id AND x.used_at IS NOT NULL);
    GET DIAGNOSTICS n_app = ROW_COUNT;
    UPDATE iam.student_account s
       SET must_change = true
      FROM admissions.pg_application ap JOIN admissions.pg_applicant p ON p.id = ap.applicant_id
     WHERE s.student_id = ap.student_id AND p.must_change_password AND s.password_hash = p.password_hash
       AND s.last_signed_in_at IS NULL AND NOT s.must_change AND s.temp_expires_at IS NULL;
    GET DIAGNOSTICS n_stu = ROW_COUNT;
    RAISE NOTICE 'V709: % migrated postgraduate applicant(s) open on either number first; % student account(s) on the admission number first', n_app, n_stu;
END $$;

COMMIT;
