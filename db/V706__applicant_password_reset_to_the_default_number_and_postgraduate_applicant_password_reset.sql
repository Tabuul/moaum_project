-- ════════════════════════════════════════════════════════════════════════
--  V706 · An applicant's password reset back to the default number; postgraduate applicants' passwords reset too
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 30 October 2026: "Applicant password reset, should reset to default jamb no and not … also add password
--  reset for pg school too, it should be on pg dean dashboard and all it support staff, also ict director".
--
--  1 · Post-UTME and the other undergraduate applicants (admissions.applicant_account). V687's desk gave the officer a random temporary
--      password for 24 hours. A reset now puts the account back on its first password — the JAMB number, as at the first sign-in (V178;
--      the account holds the sentinel SET_ON_FIRST_LOGIN), or the application number for an applicant with no JAMB number (Preliminary
--      Science, Preliminary Technology, the proficiency courses: V446, V701) — and the applicant chooses their own password at the
--      sign-in before anything else (must_change_password; the API's ApplicantPasswordGate). The account is unlocked and its open
--      sessions end. admissions.applicant_password_default(account, reason); the reset written down as DEFAULT_NUMBER, with no expiry.
--      The reset link (V687) stays; the API no longer issues a random temporary password (applicant_password_temporary is kept for the
--      resets already made and V687's check).
--
--  2 · Postgraduate applicants (admissions.pg_applicant), who could only ask for a link (V220). The Dean of the School of Postgraduate
--      Studies (pgschool), its Secretary (pgsecretary), the Director of ICT (ict), ICT Support (ictagent, helpdeskhead) and super reset
--      one, saying why: the password becomes the postgraduate application number (hashed here, bcrypt cost 12), the account is unlocked,
--      its sessions end, and the applicant chooses their own at the next sign-in (pg_applicant.must_change_password; the same gate).
--      admissions.pg_applicant_password_default(applicant, reason); every reset written once on admissions.pg_applicant_password_reset;
--      the applicant told (admissions.pg_tell_applicant: email and SMS). admissions.pg_applicant_password_set(applicant, hash, keep) is
--      the applicant's own new password; admissions.pg_applicant_password_find(q) the desk's finder (the application number, the old
--      portal's number, the email, the phone or a name).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · undergraduate applicants: back to the JAMB number (or the application number) ──

ALTER TABLE admissions.applicant_password_reset ALTER COLUMN expires_at DROP NOT NULL;
ALTER TABLE admissions.applicant_password_reset DROP CONSTRAINT IF EXISTS applicant_password_reset_method_check;
ALTER TABLE admissions.applicant_password_reset ADD CONSTRAINT applicant_password_reset_method_check
    CHECK (method IN ('TEMPORARY_PASSWORD', 'RESET_LINK', 'DEFAULT_NUMBER'));
COMMENT ON COLUMN admissions.applicant_password_reset.expires_at IS
  'V687: when the temporary password or the link stops working; V706: none for DEFAULT_NUMBER (the first password stands until the applicant chooses their own).';

-- the number an applicant's first password is: the JAMB number, or the application number where there is none
CREATE OR REPLACE FUNCTION admissions.applicant_default_number(p_account uuid) RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(nullif(btrim(a.jamb_key), ''),
                    (SELECT p.application_no FROM admissions.application p WHERE p.account_id = a.id ORDER BY p.created_at DESC NULLS LAST LIMIT 1))
      FROM admissions.applicant_account a WHERE a.id = p_account
$fn$;
COMMENT ON FUNCTION admissions.applicant_default_number(uuid) IS
  'V706: an applicant''s first password — the JAMB number, or the application number for an applicant with none (the preliminary and proficiency routes).';

CREATE OR REPLACE FUNCTION admissions.applicant_password_default(p_account uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        a admissions.applicant_account; v_number text; v_locked boolean; v_ended integer; v_id uuid;
BEGIN
    SELECT * INTO a FROM admissions.applicant_account WHERE id = p_account FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'APW_NO_ACCOUNT: no applicant account %', p_account USING ERRCODE = '23503'; END IF;
    v_number := admissions.applicant_default_number(p_account);
    IF v_number IS NULL THEN
        RAISE EXCEPTION 'APW_NO_NUMBER: the applicant has neither a JAMB number nor an application number to sign in with' USING ERRCODE = '23514',
            HINT = 'Send the applicant a reset link instead.';
    END IF;
    v_locked := coalesce(a.locked_until > now(), false);
    -- the sentinel: the sign-in takes the first password (the number) directly, as at the first sign-in (V178)
    UPDATE admissions.applicant_account
       SET password_hash = 'SET_ON_FIRST_LOGIN', must_change_password = true, temp_expires_at = NULL, failed_attempts = 0, locked_until = NULL,
           password_reset_at = now()
     WHERE id = p_account;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = p_account AND ended_at IS NULL;
    GET DIAGNOSTICS v_ended = ROW_COUNT;
    INSERT INTO admissions.applicant_password_reset (account_id, method, reason, expires_at, was_locked, sessions_ended, reset_by, reset_office)
    VALUES (p_account, 'DEFAULT_NUMBER', v_reason, NULL, v_locked, v_ended, v_by, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    INSERT INTO admissions.applicant_event (account_id, identifier, outcome) VALUES (p_account, '', 'DEFAULT_PASSWORD_RESTORED');
    RETURN jsonb_build_object('id', v_id, 'number', v_number, 'numberKind', CASE WHEN nullif(btrim(a.jamb_key), '') IS NOT NULL THEN 'JAMB' ELSE 'APPLICATION' END,
                              'wasLocked', v_locked, 'sessionsEnded', v_ended);
END $fn$;
COMMENT ON FUNCTION admissions.applicant_password_default(uuid, text) IS
  'V706: an applicant''s password put back to the first password — the JAMB number, or the application number — by the University: the account unlocked, its sessions ended, the change required at the next sign-in; the reset written down (DEFAULT_NUMBER).';

-- the desk's finder, restated from V687: whether the account is on its first password, and that number
DROP FUNCTION IF EXISTS admissions.applicant_password_find(text, integer);
CREATE FUNCTION admissions.applicant_password_find(p_q text, p_limit integer DEFAULT 50)
RETURNS TABLE (account_id uuid, session text, jamb_key text, application_no text, surname text, other_names text, email text, phone text,
               failed_attempts integer, locked boolean, must_change boolean, temp_expires_at timestamptz, last_signed_in_at timestamptz,
               created_at timestamptz, last_reset_at timestamptz, last_reset_method text, resets bigint, on_default boolean, default_number text)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS raw, upper(btrim(coalesce(p_q, ''))) AS up,
                      CASE WHEN regexp_replace(coalesce(p_q, ''), '[^0-9+]', '', 'g') ~ '^\+?234[0-9]{10}$'
                           THEN '0' || right(regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g'), 10)
                           ELSE regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g') END AS digits)
    SELECT a.id, a.session, a.jamb_key, p.application_no, c.surname, c.other_names, a.email, a.phone,
           a.failed_attempts, coalesce(a.locked_until > now(), false), a.must_change_password, a.temp_expires_at, a.last_signed_in_at, a.created_at,
           (SELECT max(r.reset_at) FROM admissions.applicant_password_reset r WHERE r.account_id = a.id),
           (SELECT r.method FROM admissions.applicant_password_reset r WHERE r.account_id = a.id ORDER BY r.reset_at DESC LIMIT 1),
           (SELECT count(*) FROM admissions.applicant_password_reset r WHERE r.account_id = a.id),
           a.password_hash = 'SET_ON_FIRST_LOGIN',
           coalesce(nullif(btrim(a.jamb_key), ''), p.application_no)
      FROM admissions.applicant_account a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.application p ON p.account_id = a.id
      CROSS JOIN q
     WHERE length(q.raw) >= 3
       AND (a.jamb_key = q.up OR p.application_no = q.up OR lower(a.email) = lower(q.raw)
            OR (length(q.digits) = 11 AND a.phone = q.digits)
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (c.surname || ' ' || c.other_names) ILIKE '%' || q.raw || '%')
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (c.other_names || ' ' || c.surname) ILIKE '%' || q.raw || '%'))
     ORDER BY a.session DESC, c.surname, c.other_names
     LIMIT greatest(least(coalesce(p_limit, 50), 200), 1)
$fn$;
COMMENT ON FUNCTION admissions.applicant_password_find(text, integer) IS
  'V687, V706: applicant accounts for the password desk — by JAMB number, application number, email, phone (0… or +234…) or a name (three characters or more); on_default when the account is on its first password, default_number that number.';

-- ── 2 · postgraduate applicants ──

ALTER TABLE admissions.pg_applicant
    ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS password_reset_at timestamptz;
COMMENT ON COLUMN admissions.pg_applicant.must_change_password IS
  'V706: the University reset the password to the application number; the applicant chooses their own at the next sign-in before anything else.';

CREATE TABLE admissions.pg_applicant_password_reset (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_id uuid NOT NULL REFERENCES admissions.pg_applicant (id) ON DELETE CASCADE,   -- the go-live reset clears applicants
    method text NOT NULL DEFAULT 'DEFAULT_NUMBER' CHECK (method IN ('DEFAULT_NUMBER')),
    application_no text NOT NULL,
    reason text NOT NULL CHECK (length(btrim(reason)) >= 10),
    was_locked boolean NOT NULL DEFAULT false,
    sessions_ended integer NOT NULL DEFAULT 0,
    reset_by uuid NOT NULL,
    reset_office text NOT NULL CHECK (reset_office IN ('pgschool', 'pgsecretary', 'ict', 'ictagent', 'helpdeskhead', 'super')),
    reset_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pg_applicant_password_reset_applicant ON admissions.pg_applicant_password_reset (applicant_id, reset_at DESC);
CREATE INDEX ix_pg_applicant_password_reset_at ON admissions.pg_applicant_password_reset (reset_at DESC);
COMMENT ON TABLE admissions.pg_applicant_password_reset IS
  'V706: every reset of a postgraduate applicant''s password by the University — back to the application number, the reason, the officer and office — written once.';
SELECT audit.attach('admissions.pg_applicant_password_reset');
CREATE TRIGGER trg_pg_applicant_password_reset_kept BEFORE UPDATE OR DELETE ON admissions.pg_applicant_password_reset
    FOR EACH ROW EXECUTE FUNCTION admissions.applicant_password_reset_kept();

CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_officer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'APW_ACTOR: a password is reset by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('pgschool', 'pgsecretary', 'ict', 'ictagent', 'helpdeskhead', 'super') THEN
        RAISE EXCEPTION 'PGPW_OFFICE: the Dean or the Secretary of the School of Postgraduate Studies, the Director of ICT or ICT Support resets a postgraduate applicant''s password, not %', v_office
            USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_officer() IS
  'V706: the person resetting a postgraduate applicant''s password, in an office that may — pgschool, pgsecretary, ict, ictagent, helpdeskhead or super; PGPW_OFFICE otherwise.';

CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_default(p_applicant uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.pg_applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        p admissions.pg_applicant; v_app uuid; v_no text; v_locked boolean; v_ended integer; v_id uuid;
BEGIN
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = p_applicant FOR UPDATE;
    IF p.id IS NULL THEN RAISE EXCEPTION 'PGPW_NO_ACCOUNT: no postgraduate applicant %', p_applicant USING ERRCODE = '23503'; END IF;
    SELECT a.id, a.application_no INTO v_app, v_no FROM admissions.pg_application a WHERE a.applicant_id = p_applicant ORDER BY a.created_at DESC LIMIT 1;
    IF v_no IS NULL THEN
        RAISE EXCEPTION 'PGPW_NO_APPLICATION: the applicant has no application number to sign in with' USING ERRCODE = '23514',
            HINT = 'The applicant uses "Forgot password" on the sign-in page instead.';
    END IF;
    v_locked := coalesce(p.locked_until > now(), false);
    UPDATE admissions.pg_applicant
       SET password_hash = crypt(v_no, gen_salt('bf', 12)), must_change_password = true, failed_attempts = 0, locked_until = NULL, password_reset_at = now()
     WHERE id = p_applicant;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = p_applicant AND ended_at IS NULL;
    GET DIAGNOSTICS v_ended = ROW_COUNT;
    INSERT INTO admissions.pg_applicant_password_reset (applicant_id, application_no, reason, was_locked, sessions_ended, reset_by, reset_office)
    VALUES (p_applicant, v_no, v_reason, v_locked, v_ended, v_by, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    PERFORM admissions.pg_tell_applicant(v_app, 'Your application password was reset',
        'The password of your postgraduate application was reset by the University at your request. Sign in with your email or your application number, '
        || 'and your application number (' || v_no || ') as the password; you will choose your own password at once. '
        || 'If you did not ask for this, contact the School of Postgraduate Studies or ICT Support.');
    RETURN jsonb_build_object('id', v_id, 'applicationNo', v_no, 'wasLocked', v_locked, 'sessionsEnded', v_ended);
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_default(uuid, text) IS
  'V706: a postgraduate applicant''s password put back to the application number by the University: the account unlocked, its sessions ended, the change required at the next sign-in; the reset written down and the applicant told.';

-- the applicant's own new password (the change at the sign-in, or at will): the change no longer required, the account unlocked; every
-- other open session ends (p_keep, the session the change was made in, stays)
CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_set(p_applicant uuid, p_hash text, p_keep bytea DEFAULT NULL) RETURNS void LANGUAGE sql AS $fn$
    UPDATE admissions.pg_applicant
       SET password_hash = p_hash, must_change_password = false, failed_attempts = 0, locked_until = NULL
     WHERE id = p_applicant;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'password changed'
     WHERE person_id = p_applicant AND ended_at IS NULL AND (p_keep IS NULL OR id <> p_keep);
$fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_set(uuid, text, bytea) IS
  'V706: a postgraduate applicant''s own new password: the change no longer required, the account unlocked, every other session ended.';

CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_find(p_q text, p_limit integer DEFAULT 50)
RETURNS TABLE (applicant_id uuid, session text, application_no text, legacy_application_no text, surname text, other_names text, email text, phone text,
               programme text, state text, failed_attempts integer, locked boolean, must_change boolean, last_signed_in_at timestamptz,
               created_at timestamptz, last_reset_at timestamptz, resets bigint)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS raw, upper(btrim(coalesce(p_q, ''))) AS up,
                      CASE WHEN regexp_replace(coalesce(p_q, ''), '[^0-9+]', '', 'g') ~ '^\+?234[0-9]{10}$'
                           THEN '0' || right(regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g'), 10)
                           ELSE regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g') END AS digits)
    SELECT p.id, coalesce(a.session, p.session), a.application_no, lg.legacy_application_no, p.surname, p.other_names, p.email, p.phone,
           pr.name, a.state, p.failed_attempts, coalesce(p.locked_until > now(), false), p.must_change_password, p.last_signed_in_at, p.created_at,
           (SELECT max(r.reset_at) FROM admissions.pg_applicant_password_reset r WHERE r.applicant_id = p.id),
           (SELECT count(*) FROM admissions.pg_applicant_password_reset r WHERE r.applicant_id = p.id)
      FROM admissions.pg_applicant p
      LEFT JOIN admissions.pg_application a ON a.applicant_id = p.id
      LEFT JOIN admissions.pg_legacy_application lg ON lg.application_id = a.id
      LEFT JOIN ref.programme pr ON pr.code = a.programme_code
      CROSS JOIN q
     WHERE length(q.raw) >= 3
       AND (a.application_no = q.up OR upper(btrim(lg.legacy_application_no)) = q.up OR lower(p.email) = lower(q.raw)
            OR (length(q.digits) = 11 AND p.phone = q.digits)
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (p.surname || ' ' || p.other_names) ILIKE '%' || q.raw || '%')
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (p.other_names || ' ' || p.surname) ILIKE '%' || q.raw || '%'))
     ORDER BY coalesce(a.session, p.session) DESC, p.surname, p.other_names
     LIMIT greatest(least(coalesce(p_limit, 50), 200), 1)
$fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_find(text, integer) IS
  'V706: postgraduate applicant accounts for the password desk — by application number, the old portal''s number, email, phone (0… or +234…) or a name (three characters or more).';

COMMIT;
