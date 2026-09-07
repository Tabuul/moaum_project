-- ═══════════════════════════════════════════════════════════════════════════
-- V005 — issued credentials, and the signature the design set requires but
--        never designed
--
-- FR-CTP-005 is mandatory and says a delivered transcript carries "a
-- tamper-evident digital signature". Searching all 166 documents for a
-- mechanism returns one open question that has never been circulated to
-- anybody:
--
--   T8 — "Is an HSM available for signing certificates and transcripts, or
--         is a software key store acceptable?"   (ARC §23, unanswered)
--
-- There is no signing key, no key custody, no rotation, no certificate
-- profile, no timestamping, and nothing that says what a verifier checks.
-- What exists is `document_hash bytea NOT NULL` with no endpoint that accepts
-- a document to compare against it — a mechanism stated and never realised.
--
-- Four decisions are taken here. Each is the Directorate's and each is
-- recorded so a later reader can tell it from a requirement.
--
-- ── 1. THE SIGNED OBJECT IS THE AWARD, NOT THE PDF ───────────────────────
--
-- A PDF re-rendered next year with a different font is a different byte
-- stream and the same degree. Sign the bytes and the signature breaks on a
-- template change; sign the AWARD — a canonical statement of who, what, which
-- class, when, under which name — and the PDF becomes a rendering of a signed
-- fact rather than the fact itself.
--
-- This also settles a question the set left open in two directions at once.
-- ARC §10.7 keeps generated PDFs in object storage, implying the bytes are
-- the artefact; P9 promises "any historical output can be regenerated under
-- the rules that applied at the time". Both cannot be true of a hash over
-- rendered bytes. Signing the statement makes them both true: regenerate the
-- document as often as you like, and the signature still holds.
--
-- ── 2. VERIFICATION MUST WORK WITHOUT US ─────────────────────────────────
--
-- The design puts a QR on every document resolving at moaum.edu.ng/verify.
-- That domain is itself W-Q1 — "is it registered?" — and a graduate must be
-- able to prove a degree in 2071. An endpoint is a promise about an
-- organisation's infrastructure fifty years out; a signature is a
-- mathematical fact. So the QR carries the SIGNED STATEMENT, not merely a
-- link, and a verifier who holds the University's published public key can
-- check it with no network and no cooperation from us.
--
-- The endpoint does not go away — it answers the one question a signature
-- cannot (below) — but it stops being the thing the credential depends on.
--
-- ── 3. A SIGNATURE CANNOT BE WITHDRAWN, SO STATUS STAYS ONLINE ───────────
--
-- Ed25519 over a statement is true for ever, including for a degree revoked
-- for malpractice. Authenticity and standing are two questions and only the
-- first is cryptographic. Offline answers "the University issued this";
-- online answers "and it still stands".
--
-- ── 4. THE KEY ROTATES; NO KEY IS EVER RETIRED ───────────────────────────
--
-- A 2027 signing key must not still be signing in 2047, and a 2027
-- certificate must still verify in 2047. So keys are effective-dated exactly
-- as policy is (V004) — one key signs at any moment, every key is published
-- for ever, and nothing is deleted.
--
-- The private key is NOT IN THIS DATABASE and there is no column for it.
-- `custody_ref` is a handle into the HSM or KMS. A schema with somewhere to
-- put a private key eventually has one in it.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the keys ──────────────────────────────────────────────────────────────
CREATE TABLE credentials.signing_key (
    id           uuid      PRIMARY KEY,
    algorithm    text      NOT NULL,
    public_key   bytea     NOT NULL,          -- published, for ever
    custody_ref  text      NOT NULL,          -- HSM/KMS handle. Never the key.
    validity     daterange NOT NULL,          -- when it may SIGN
    instrument   text      NOT NULL,          -- the ceremony that created it
    retired_on   date      NULL,
    retired_why  text      NULL,
    CONSTRAINT ck_key_alg      CHECK (algorithm IN ('Ed25519','ECDSA-P256')),
    CONSTRAINT ck_key_custody  CHECK (length(btrim(custody_ref)) > 0),
    CONSTRAINT ck_key_retired  CHECK (retired_on IS NULL OR retired_why IS NOT NULL),
    -- One key signs at any moment. Two overlapping keys means "which key
    -- signed this" is answered by trying both, and a compromised key cannot
    -- then be spoken about precisely.
    CONSTRAINT ex_key_one_at_a_time EXCLUDE USING gist (validity WITH &&)
);

COMMENT ON TABLE credentials.signing_key IS
  'Signing keys, effective-dated. A key stops signing and is never retired '
  'from verification: a 2027 certificate must verify in 2071 against the 2027 '
  'key. There is deliberately no column for a private key.';

COMMENT ON COLUMN credentials.signing_key.retired_on IS
  'Set when a key is withdrawn early — compromise, or an ageing algorithm. '
  'Withdrawing a key does NOT invalidate what it signed: that is what the '
  'revocation register is for, one credential at a time and with a reason. '
  'Treating a key withdrawal as a mass revocation would void thousands of '
  'honest degrees to answer one dishonest one.';

-- ── the credential ────────────────────────────────────────────────────────
CREATE TABLE credentials.issued (
    id                uuid  PRIMARY KEY,
    kind              text  NOT NULL,
    student_id        uuid  NOT NULL,
    verification_code text  NOT NULL UNIQUE,
    statement         jsonb NOT NULL,       -- exactly what was signed
    signature         bytea NOT NULL,
    signed_with       uuid  NOT NULL REFERENCES credentials.signing_key(id),
    issuing_name      text  NOT NULL,       -- BR-013: the name AT ISSUE
    issued_on         date  NOT NULL,
    issued_by         uuid  NOT NULL,
    issued_office     text  NOT NULL REFERENCES ref.office(code),
    supersedes        uuid  NULL REFERENCES credentials.issued(id),
    duplicate_of      uuid  NULL REFERENCES credentials.issued(id),
    CONSTRAINT ck_issued_kind CHECK (kind IN
        ('DEGREE_CERTIFICATE','TRANSCRIPT','STATEMENT_OF_RESULT','MATRICULATION')),
    -- The verification code is 128 bits of randomness shown to strangers
    -- (DBD §12.1), rendered in Crockford base32 — no I, L, O or U, so it
    -- cannot be mis-transcribed into a different valid code and cannot spell
    -- anything. Grouped in fives because it is read aloud down a telephone
    -- to a registry clerk in another country.
    CONSTRAINT ck_issued_code CHECK (verification_code ~
        '^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{5}(-[0-9ABCDEFGHJKMNPQRSTVWXYZ]{5}){4}$'),
    CONSTRAINT ck_issued_duplicate CHECK (duplicate_of IS NULL OR duplicate_of <> id)
);

CREATE INDEX ix_issued_student ON credentials.issued (student_id, kind);

COMMENT ON COLUMN credentials.issued.statement IS
  'The canonical award statement, byte for byte as signed. Kept because a '
  'signature over a statement nobody kept is a signature over nothing.';

-- ── revocation, which is an act like any other ────────────────────────────
-- Everything consequential in this design carries its authority: an office
-- assignment cites an instrument, a fee schedule a Council minute, a returned
-- result set a reason that cannot be empty. Withdrawing a degree is among the
-- gravest acts the University can take and, as the set stands, needs none of
-- them — FR-CTP-010 gives one endpoint and one permission string.
CREATE TABLE credentials.revocation (
    credential_id uuid        PRIMARY KEY REFERENCES credentials.issued(id),
    revoked_on    date        NOT NULL,
    reason        text        NOT NULL,
    instrument    text        NOT NULL,     -- the Senate or Council minute
    revoked_by    uuid        NOT NULL,
    revoked_office text       NOT NULL REFERENCES ref.office(code),
    recorded_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_revoke_reason     CHECK (length(btrim(reason)) > 0),
    CONSTRAINT ck_revoke_instrument CHECK (length(btrim(instrument)) > 0),
    -- The Registrar signs and the Registrar revokes; Council and Senate
    -- decide. Nobody else, and not the Super Administrator, who ARC §9
    -- already bars from signing a transcript and did not think to bar here.
    CONSTRAINT ck_revoke_office CHECK (revoked_office IN ('registrar','vc'))
);

-- ── what a stranger sees ──────────────────────────────────────────────────
-- Never raises. A revoked award resolves to REVOKED and an unknown code to
-- NOT_FOUND, because a failure looks like a fault, and a fault produces the
-- telephone call this endpoint exists to prevent.
CREATE OR REPLACE FUNCTION credentials.verify(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    c   credentials.issued;
    r   credentials.revocation;
    now_name text := 'Rev. Fr. Moses Orshio Adasu University, Makurdi';
BEGIN
    SELECT * INTO c FROM credentials.issued
     WHERE verification_code = upper(btrim(p_code));

    IF NOT FOUND THEN
        -- A code nobody issued is the fingerprint of a fabricated document.
        -- The design already alarms on three BR-006 blocks in seven days; it
        -- simply never applied the same thinking to the one document that
        -- leaves the University and is worth forging.
        INSERT INTO credentials.lookup_miss (code, looked_up_at)
        VALUES (left(upper(btrim(p_code)), 40), now());
        RETURN jsonb_build_object(
            'status', 'NOT_FOUND',
            'currentInstitutionName', now_name,
            'remedy', 'No credential bears this code. If you hold a document '
                   || 'showing it, it was not issued by this University. '
                   || 'The Registry will take a report.',
            'verifiedAt', to_jsonb(now()));
    END IF;

    SELECT * INTO r FROM credentials.revocation WHERE credential_id = c.id;

    RETURN c.statement
        || jsonb_build_object(
            'status', CASE WHEN r.credential_id IS NULL THEN 'VALID' ELSE 'REVOKED' END,
            'issuingInstitution', c.issuing_name,      -- BR-013, the name at issue
            'currentInstitutionName', now_name,        -- and the name today
            'verifiedAt', to_jsonb(now()))
        || CASE WHEN r.credential_id IS NULL THEN '{}'::jsonb ELSE
             jsonb_build_object('revokedOn', r.revoked_on, 'revokedUnder', r.instrument)
           END;
END $$;

CREATE TABLE credentials.lookup_miss (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code         text        NOT NULL,
    looked_up_at timestamptz NOT NULL
);

-- A code queried repeatedly and never issued is a fabricated certificate
-- being checked by successive employers. It is the only signal the University
-- gets that one is in circulation, and it costs one query to have.
CREATE OR REPLACE FUNCTION credentials.suspected_forgeries(p_since interval DEFAULT '30 days')
RETURNS TABLE (code text, attempts bigint, first_seen timestamptz, last_seen timestamptz)
LANGUAGE sql
STABLE
AS $$
    SELECT m.code, count(*), min(m.looked_up_at), max(m.looked_up_at)
      FROM credentials.lookup_miss m
     WHERE m.looked_up_at > now() - p_since
     GROUP BY m.code
    HAVING count(*) >= 3
     ORDER BY count(*) DESC;
$$;

COMMENT ON FUNCTION credentials.suspected_forgeries(interval) IS
  'Reported to the Registrar, not to ICT alone — a forged certificate is a '
  'records matter before it is a technical one, exactly as a broken audit '
  'chain is (I-SEC-2).';

-- ── the guard the set requires and enforces nowhere ───────────────────────
-- FR-CTP-009: no certificate to a student who is not GRADUATED with a
-- Senate-approved award and complete clearance. There is no invariant for it
-- anywhere in the module pack — the certificate is the only major aggregate
-- in the design with no rule attached to it at all.
CREATE OR REPLACE FUNCTION credentials.assert_issuable(
    p_kind text, p_graduated boolean, p_senate_approved boolean, p_cleared boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_kind <> 'DEGREE_CERTIFICATE' THEN RETURN; END IF;
    IF NOT p_graduated THEN
        RAISE EXCEPTION 'the student record is not GRADUATED' USING ERRCODE='23514';
    END IF;
    IF NOT p_senate_approved THEN
        RAISE EXCEPTION 'the award is not Senate-approved' USING ERRCODE='23514';
    END IF;
    IF NOT p_cleared THEN
        RAISE EXCEPTION 'clearance is incomplete' USING ERRCODE='23514',
            HINT='BR-001. No office may clear another office''s item.';
    END IF;
END $$;

SELECT audit.exempt('credentials.lookup_miss',
    'Written by the public verification endpoint on behalf of an anonymous '
    'stranger, so there is no acting office to record and the spine would '
    'refuse the write — correctly. It is telemetry about people outside the '
    'University, not a record of an act inside it.');

SELECT audit.attach('credentials.signing_key');
SELECT audit.attach('credentials.issued');
SELECT audit.attach('credentials.revocation');

GRANT SELECT, INSERT, UPDATE ON credentials.signing_key, credentials.issued,
      credentials.revocation, credentials.lookup_miss TO app_credentials;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA credentials TO app_credentials;
GRANT SELECT ON ALL TABLES IN SCHEMA credentials TO app_auditor;
