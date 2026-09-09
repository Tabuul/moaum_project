-- ═══════════════════════════════════════════════════════════════════════════
-- V039 — payment gateway keys, set from the dashboard, encrypted at rest,
--        never read back
--
--   The gateway secret and the Flutterwave hash could only be set as service
--   variables. The Bursary can now set them from the Gateways screen instead.
--   A key written here is encrypted with a server passphrase (pgcrypto), so a
--   database dump alone does not leak it; it is decrypted only in the API's
--   own process to call the gateway, and no screen and no endpoint ever
--   returns it — exactly as a password hash is never shown (iam.credential).
--   The act of setting or rotating a key is on the audit spine, with the
--   person, the mode and the last four characters, and nothing more.
--
--   Service variables still work and take precedence is NOT assumed: the
--   dashboard value wins when present, and the variable is the fallback, so
--   an operator can move from one to the other without an outage.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE finance.gateway_credential (
    gateway     text PRIMARY KEY,
    secret_enc  bytea NULL,
    hash_enc    bytea NULL,
    mode        text NULL,
    last4       text NULL,
    set_by      uuid NULL,
    set_at      timestamptz NULL,
    CONSTRAINT ck_gc_gateway CHECK (gateway IN ('paystack','flutterwave')),
    CONSTRAINT ck_gc_mode CHECK (mode IS NULL OR mode IN ('TEST','LIVE'))
);
SELECT audit.exempt('finance.gateway_credential',
    'Carries encrypted gateway secrets. Copying them into the audit trail '
    'would put the secret in a second, longer-lived place; the act of setting '
    'or rotating one is recorded in finance.gateway_credential_event, which is '
    'on the spine, and the secret is never selected back to any screen.');

CREATE TABLE finance.gateway_credential_event (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway    text NOT NULL,
    kind       text NOT NULL,
    mode       text NULL,
    last4      text NULL,
    by_person  uuid NOT NULL,
    at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_gce_kind CHECK (kind IN ('SET','ROTATED','CLEARED'))
);
SELECT audit.attach('finance.gateway_credential_event');

-- set or rotate a key: encrypt with the server passphrase, and record the act
CREATE OR REPLACE FUNCTION finance.set_gateway_secret(p_gateway text, p_secret text, p_hash text, p_mode text, p_last4 text, p_key text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_existed boolean; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_gateway NOT IN ('paystack','flutterwave') THEN RAISE EXCEPTION 'no such gateway %', p_gateway USING ERRCODE = '23514'; END IF;
    IF p_key IS NULL OR length(p_key) < 8 THEN
        RAISE EXCEPTION 'no server passphrase to encrypt the key with' USING ERRCODE = '23514',
            HINT = 'Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; a key is never stored in the clear.';
    END IF;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a gateway key is set by a person' USING ERRCODE = '23514'; END IF;
    IF p_secret IS NULL OR btrim(p_secret) = '' THEN RAISE EXCEPTION 'the secret key is blank' USING ERRCODE = '23514'; END IF;
    SELECT EXISTS (SELECT 1 FROM finance.gateway_credential WHERE gateway = p_gateway AND secret_enc IS NOT NULL) INTO v_existed;
    INSERT INTO finance.gateway_credential (gateway, secret_enc, hash_enc, mode, last4, set_by, set_at)
    VALUES (p_gateway, pgp_sym_encrypt(btrim(p_secret), p_key),
            CASE WHEN nullif(btrim(p_hash), '') IS NULL THEN NULL ELSE pgp_sym_encrypt(btrim(p_hash), p_key) END,
            p_mode, p_last4, v_actor, now())
    ON CONFLICT (gateway) DO UPDATE SET secret_enc = EXCLUDED.secret_enc,
        hash_enc = coalesce(EXCLUDED.hash_enc, finance.gateway_credential.hash_enc),
        mode = EXCLUDED.mode, last4 = EXCLUDED.last4, set_by = EXCLUDED.set_by, set_at = EXCLUDED.set_at;
    INSERT INTO finance.gateway_credential_event (gateway, kind, mode, last4, by_person)
    VALUES (p_gateway, CASE WHEN v_existed THEN 'ROTATED' ELSE 'SET' END, p_mode, p_last4, v_actor);
END $$;

-- read the secret, decrypted, for the API's own use only
CREATE OR REPLACE FUNCTION finance.gateway_secret(p_gateway text, p_key text)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE v bytea;
BEGIN
    SELECT secret_enc INTO v FROM finance.gateway_credential WHERE gateway = p_gateway;
    IF v IS NULL OR p_key IS NULL OR p_key = '' THEN RETURN NULL; END IF;
    RETURN pgp_sym_decrypt(v, p_key);
EXCEPTION WHEN OTHERS THEN RETURN NULL;   -- wrong passphrase: fall back to the service variable
END $$;

CREATE OR REPLACE FUNCTION finance.gateway_hash(p_gateway text, p_key text)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE v bytea;
BEGIN
    SELECT hash_enc INTO v FROM finance.gateway_credential WHERE gateway = p_gateway;
    IF v IS NULL OR p_key IS NULL OR p_key = '' THEN RETURN NULL; END IF;
    RETURN pgp_sym_decrypt(v, p_key);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;

-- what a screen may see: that a key is configured, its mode, its last four, when and by whom — never the key
CREATE OR REPLACE FUNCTION finance.gateway_config()
RETURNS TABLE (gateway text, configured boolean, has_hash boolean, mode text, last4 text, set_at timestamptz, set_by_name text)
LANGUAGE sql STABLE AS $$
    SELECT g.gateway, c.secret_enc IS NOT NULL, c.hash_enc IS NOT NULL, c.mode, c.last4, c.set_at,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
      FROM (VALUES ('paystack'), ('flutterwave')) g(gateway)
      LEFT JOIN finance.gateway_credential c ON c.gateway = g.gateway
      LEFT JOIN iam.person p ON p.id = c.set_by
     ORDER BY g.gateway
$$;

CREATE OR REPLACE FUNCTION finance.clear_gateway_secret(p_gateway text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a gateway key is cleared by a person' USING ERRCODE = '23514'; END IF;
    DELETE FROM finance.gateway_credential WHERE gateway = p_gateway;
    INSERT INTO finance.gateway_credential_event (gateway, kind, by_person) VALUES (p_gateway, 'CLEARED', v_actor);
END $$;

COMMIT;
