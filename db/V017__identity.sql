-- ═══════════════════════════════════════════════════════════════════════════
-- V017 — signing in
--
-- The person (V003) held offices under instruments but had no way to sign
-- in: the portal ran on a token minted by the Directorate of ICT. This
-- migration gives a person a credential — a username and a password hash,
-- never the password — and records every attempt to use it.
--
-- What is deliberately NOT here: a password in clear, a password in the
-- audit trail, a role called "admin". The offices a person holds are still
-- the dated, instrumented grants of iam.office_assignment; the token a
-- sign-in issues carries whichever of them are live today, and nothing else.
-- Keycloak, when it arrives (FR-IAM-013), issues the same claims from the
-- same grants; the screens do not change.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'V017: credentials and sign-in events', true);
END $seed$;

-- ── the credential ─────────────────────────────────────────────────────────
-- One per person. The hash is bcrypt at cost 12 (FR-IAM-011); the username is
-- the staff number or an email, lower-cased, and is what the person types.
CREATE TABLE iam.credential (
    person_id       uuid PRIMARY KEY REFERENCES iam.person(id),
    username        text NOT NULL UNIQUE,
    password_hash   text NOT NULL,
    must_change     boolean NOT NULL DEFAULT true,
    failed_attempts int  NOT NULL DEFAULT 0,
    locked_until    timestamptz NULL,
    set_at          timestamptz NOT NULL DEFAULT now(),
    set_by          uuid NOT NULL,
    last_sign_in_at timestamptz NULL,
    CONSTRAINT ck_credential_username CHECK (username = lower(btrim(username)) AND length(username) BETWEEN 3 AND 200),
    CONSTRAINT ck_credential_hash CHECK (password_hash LIKE '$2%$12$%')
);

-- The row carries a hash, and the spine copies whole rows into the trail. The
-- hash is not a fact the trail needs; the ACT of setting it is, and that is
-- recorded next door without the hash.
SELECT audit.exempt('iam.credential',
    'Carries a password hash. Copying it into the audit trail would put the hash '
    'in a second, longer-lived place; the act of setting or resetting it is '
    'recorded in iam.credential_event, which is on the spine.');

CREATE TABLE iam.credential_event (
    id         uuid PRIMARY KEY,
    person_id  uuid NOT NULL REFERENCES iam.person(id),
    kind       text NOT NULL,
    at         timestamptz NOT NULL DEFAULT now(),
    by_person  uuid NOT NULL,
    note       text NULL,
    CONSTRAINT ck_credential_event_kind CHECK (kind IN ('SET','RESET','CHANGED','LOCKED','UNLOCKED'))
);
SELECT audit.attach('iam.credential_event');

-- ── every attempt, either way ──────────────────────────────────────────────
-- Thirty-eight attempts against fourteen accounts from one address is a
-- security alert only if the attempts were written down.
CREATE TABLE iam.sign_in_event (
    id         uuid PRIMARY KEY,
    at         timestamptz NOT NULL DEFAULT now(),
    username   text NOT NULL,
    person_id  uuid NULL,
    outcome    text NOT NULL,
    source_ip  inet NULL,
    session_id bytea NULL,
    CONSTRAINT ck_sign_in_outcome CHECK (outcome IN ('SIGNED_IN','BAD_PASSWORD','UNKNOWN','LOCKED','MUST_CHANGE','SIGNED_OUT','ENDED'))
);
CREATE INDEX ix_sign_in_recent ON iam.sign_in_event (at DESC);
SELECT audit.exempt('iam.sign_in_event',
    'The sign-in log is itself the record, written once per attempt at request '
    'rate, and carries no state anybody decides. Reviewed, not audited twice.');

-- ── the offices a person holds today ───────────────────────────────────────
-- What goes into the token: live grants only. An acting appointment that
-- ended yesterday is not an office today, whoever forgot to say so.
CREATE OR REPLACE FUNCTION iam.live_offices(p_person uuid)
RETURNS TABLE (office_code text, label text, scope_kind text, scope_id text, valid_to date)
LANGUAGE sql
STABLE
AS $$
    SELECT a.office_code, o.label, a.scope_kind, a.scope_id, a.valid_to
      FROM iam.office_assignment a
      JOIN ref.office o ON o.code = a.office_code
     WHERE a.person_id = p_person
       AND a.valid_from <= current_date
       AND (a.valid_to IS NULL OR a.valid_to >= current_date)
     ORDER BY a.valid_from, a.office_code
$$;

-- A grant is ended, not deleted: the date goes on, and everything done while
-- it was held stands, because it was validly done at the time.
CREATE OR REPLACE FUNCTION iam.end_grant(p_grant uuid, p_on date, p_reason text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'an office is ended with the reason on the record, and none was given'
            USING ERRCODE = 'check_violation';
    END IF;
    UPDATE iam.office_assignment SET valid_to = p_on WHERE id = p_grant AND (valid_to IS NULL OR valid_to > p_on);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no live grant %', p_grant USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

GRANT SELECT, INSERT, UPDATE ON iam.credential, iam.credential_event, iam.sign_in_event TO app_iam;
GRANT SELECT ON iam.credential_event, iam.sign_in_event TO app_auditor;

COMMIT;
