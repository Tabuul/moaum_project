-- ════════════════════════════════════════════════════════════════════════
--  V687 · Post-UTME applicant passwords reset by the Director of ICT, the Academic Office and ICT Support
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 28 October 2026: "i want password reset for postutme applicants, let the ict director, academic office
--  and ICT support staff to reset postutme applicants password".
--
--  An applicant (admissions.applicant_account: Post-UTME, Direct Entry, and the Centre's and Preliminary Science applicants who sign
--  in the same way) could only ask for a link on the sign-in page; nobody at the University could reset one. Now the Director of ICT
--  (ict), the Academic Office (academic), ICT Support (ictagent, helpdeskhead) and super reset it on Applicant Passwords, saying why:
--
--  · TEMPORARY_PASSWORD: a random temporary password (made and hashed by the API, shown to the officer once), good for 24 hours; the
--    account is unlocked, its open sessions ended, and the applicant must choose their own password at the sign-in — the portal
--    refuses everything else until they do (the API's ApplicantPasswordGate, PASSWORD_CHANGE_REQUIRED).
--  · RESET_LINK: the applicant's own one-hour link (admissions.password_reset), sent by the API to the email and phone they registered.
--
--  admissions.applicant_account gains must_change_password, temp_expires_at and password_reset_at; every reset is written once on
--  admissions.applicant_password_reset (method, reason of ten characters or more, where a link went, the officer and office).
--  admissions.applicant_password_set(account, hash) is the applicant's own new password (a link, the change, the forced change):
--  the change no longer required, the temporary password spent, the account unlocked.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.applicant_account
    ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS temp_expires_at timestamptz,
    ADD COLUMN IF NOT EXISTS password_reset_at timestamptz;
COMMENT ON COLUMN admissions.applicant_account.must_change_password IS
  'V687: a temporary password from the University stands; the applicant chooses their own at the next sign-in before anything else.';
COMMENT ON COLUMN admissions.applicant_account.temp_expires_at IS 'V687: when the temporary password stops opening the account.';

CREATE TABLE admissions.applicant_password_reset (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES admissions.applicant_account (id) ON DELETE CASCADE,   -- the go-live reset clears accounts
    method text NOT NULL CHECK (method IN ('TEMPORARY_PASSWORD', 'RESET_LINK')),
    reason text NOT NULL CHECK (length(btrim(reason)) >= 10),
    sent_to text,
    expires_at timestamptz NOT NULL,
    was_locked boolean NOT NULL DEFAULT false,
    sessions_ended integer NOT NULL DEFAULT 0,
    reset_by uuid NOT NULL,
    reset_office text NOT NULL CHECK (reset_office IN ('ict', 'academic', 'ictagent', 'helpdeskhead', 'super')),
    reset_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_applicant_password_reset_account ON admissions.applicant_password_reset (account_id, reset_at DESC);
CREATE INDEX ix_applicant_password_reset_at ON admissions.applicant_password_reset (reset_at DESC);
COMMENT ON TABLE admissions.applicant_password_reset IS
  'V687: every reset of an applicant''s password by the University — temporary password or link, the reason, where a link went, the officer and office — written once.';
SELECT audit.attach('admissions.applicant_password_reset');

CREATE OR REPLACE FUNCTION admissions.applicant_password_reset_kept() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    -- the platform's own maintenance (the go-live reset, platform.reset_operational_data) clears it with the accounts
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    RAISE EXCEPTION 'APW_KEPT: a password reset is written once and kept' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_applicant_password_reset_kept BEFORE UPDATE OR DELETE ON admissions.applicant_password_reset
    FOR EACH ROW EXECUTE FUNCTION admissions.applicant_password_reset_kept();

-- who resets: a person, in one of the offices the University named
CREATE OR REPLACE FUNCTION admissions.applicant_password_officer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'APW_ACTOR: a password is reset by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('ict', 'academic', 'ictagent', 'helpdeskhead', 'super') THEN
        RAISE EXCEPTION 'APW_OFFICE: the Director of ICT, the Academic Office or ICT Support resets an applicant''s password, not %', v_office USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.applicant_password_reason(p_reason text) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $fn$
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'APW_REASON: say why the password is reset, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    RETURN btrim(p_reason);
END $fn$;

-- a temporary password set (its bcrypt hash made by the API, the password shown to the officer once)
CREATE OR REPLACE FUNCTION admissions.applicant_password_temporary(p_account uuid, p_hash text, p_reason text, p_hours integer DEFAULT 24)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        a admissions.applicant_account; v_until timestamptz := now() + make_interval(hours => greatest(coalesce(p_hours, 24), 1));
        v_locked boolean; v_ended integer; v_id uuid;
BEGIN
    SELECT * INTO a FROM admissions.applicant_account WHERE id = p_account FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'APW_NO_ACCOUNT: no applicant account %', p_account USING ERRCODE = '23503'; END IF;
    v_locked := coalesce(a.locked_until > now(), false);
    UPDATE admissions.applicant_account
       SET password_hash = p_hash, must_change_password = true, temp_expires_at = v_until, failed_attempts = 0, locked_until = NULL, password_reset_at = now()
     WHERE id = p_account;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = p_account AND ended_at IS NULL;
    GET DIAGNOSTICS v_ended = ROW_COUNT;
    INSERT INTO admissions.applicant_password_reset (account_id, method, reason, expires_at, was_locked, sessions_ended, reset_by, reset_office)
    VALUES (p_account, 'TEMPORARY_PASSWORD', v_reason, v_until, v_locked, v_ended, v_by, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    INSERT INTO admissions.applicant_event (account_id, identifier, outcome) VALUES (p_account, '', 'TEMP_PASSWORD_ISSUED');
    RETURN jsonb_build_object('id', v_id, 'expiresAt', v_until, 'wasLocked', v_locked, 'sessionsEnded', v_ended);
END $fn$;
COMMENT ON FUNCTION admissions.applicant_password_temporary(uuid, text, text, integer) IS
  'V687: a temporary password the University set for an applicant (the hash the API made): good for the hours given (24), the account unlocked and its sessions ended, the change required at the next sign-in; the reset written down.';

-- a link sent to the applicant (the token made, kept as a hash and sent by the API); the reset written down
CREATE OR REPLACE FUNCTION admissions.applicant_password_link(p_account uuid, p_token_hash text, p_reason text, p_sent_to text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        v_until timestamptz := now() + interval '1 hour'; v_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admissions.applicant_account WHERE id = p_account) THEN
        RAISE EXCEPTION 'APW_NO_ACCOUNT: no applicant account %', p_account USING ERRCODE = '23503';
    END IF;
    IF (SELECT count(*) FROM admissions.password_reset r WHERE r.account_id = p_account AND r.created_at > now() - interval '1 hour') >= 3 THEN
        RAISE EXCEPTION 'APW_LINK_LIMIT: three reset links went to this applicant in the last hour' USING ERRCODE = '23514',
            HINT = 'Ask the applicant to use the latest link, or issue a temporary password.';
    END IF;
    INSERT INTO admissions.password_reset (account_id, token_hash, expires_at) VALUES (p_account, p_token_hash, v_until);
    INSERT INTO admissions.applicant_password_reset (account_id, method, reason, sent_to, expires_at, reset_by, reset_office)
    VALUES (p_account, 'RESET_LINK', v_reason, p_sent_to, v_until, v_by, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    INSERT INTO admissions.applicant_event (account_id, identifier, outcome) VALUES (p_account, '', 'RESET_LINK_SENT_BY_UNIVERSITY');
    RETURN jsonb_build_object('id', v_id, 'expiresAt', v_until);
END $fn$;
COMMENT ON FUNCTION admissions.applicant_password_link(uuid, text, text, text) IS
  'V687: a one-hour reset link the University sent an applicant (at most three an hour, with the applicant''s own); the reset written down.';

-- the applicant's own new password (a link, the change, the forced change): the change no longer required, the account unlocked
CREATE OR REPLACE FUNCTION admissions.applicant_password_set(p_account uuid, p_hash text) RETURNS void LANGUAGE sql AS $fn$
    UPDATE admissions.applicant_account
       SET password_hash = p_hash, must_change_password = false, temp_expires_at = NULL, failed_attempts = 0, locked_until = NULL
     WHERE id = p_account;
$fn$;

-- the desk's finder: by JAMB number, application number, email, phone, or a name
CREATE OR REPLACE FUNCTION admissions.applicant_password_find(p_q text, p_limit integer DEFAULT 50)
RETURNS TABLE (account_id uuid, session text, jamb_key text, application_no text, surname text, other_names text, email text, phone text,
               failed_attempts integer, locked boolean, must_change boolean, temp_expires_at timestamptz, last_signed_in_at timestamptz,
               created_at timestamptz, last_reset_at timestamptz, last_reset_method text, resets bigint)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS raw, upper(btrim(coalesce(p_q, ''))) AS up,
                      CASE WHEN regexp_replace(coalesce(p_q, ''), '[^0-9+]', '', 'g') ~ '^\+?234[0-9]{10}$'
                           THEN '0' || right(regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g'), 10)
                           ELSE regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g') END AS digits)
    SELECT a.id, a.session, a.jamb_key, p.application_no, c.surname, c.other_names, a.email, a.phone,
           a.failed_attempts, coalesce(a.locked_until > now(), false), a.must_change_password, a.temp_expires_at, a.last_signed_in_at, a.created_at,
           (SELECT max(r.reset_at) FROM admissions.applicant_password_reset r WHERE r.account_id = a.id),
           (SELECT r.method FROM admissions.applicant_password_reset r WHERE r.account_id = a.id ORDER BY r.reset_at DESC LIMIT 1),
           (SELECT count(*) FROM admissions.applicant_password_reset r WHERE r.account_id = a.id)
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
  'V687: applicant accounts for the password desk — by JAMB number, application number, email, phone (0… or +234…) or a name (three characters or more).';

COMMIT;
