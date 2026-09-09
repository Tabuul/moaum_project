-- ═══════════════════════════════════════════════════════════════════════════
-- V052 — Quickteller Business (Interswitch) as a third payment gateway
--
--   Paystack and Flutterwave were the two gateways a key could be set for
--   (V039). This admits a third — Quickteller Business, Interswitch's
--   merchant collections product (https://business.quickteller.com/). Its
--   credentials are more than one string (a client id and secret for the
--   requery API, and a merchant code and pay-item id for the hosted page),
--   so the whole set is kept as one JSON document in the same encrypted
--   secret slot every gateway uses; it is written and read exactly as the
--   others are, and is never selected back to any screen.
--
--   Nothing else about the store changes: the key is encrypted at rest with
--   the server passphrase, the act of setting or clearing it is on the spine
--   (finance.gateway_credential_event), and finance.gateway_config() still
--   returns only that a key is configured, its mode and last four — never it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- admit 'quickteller' to the set a credential may be stored for
ALTER TABLE finance.gateway_credential DROP CONSTRAINT ck_gc_gateway;
ALTER TABLE finance.gateway_credential
    ADD CONSTRAINT ck_gc_gateway CHECK (gateway IN ('paystack','flutterwave','quickteller'));

-- set_gateway_secret refused any gateway but the first two; admit the third
CREATE OR REPLACE FUNCTION finance.set_gateway_secret(p_gateway text, p_secret text, p_hash text, p_mode text, p_last4 text, p_key text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_existed boolean; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_gateway NOT IN ('paystack','flutterwave','quickteller') THEN RAISE EXCEPTION 'no such gateway %', p_gateway USING ERRCODE = '23514'; END IF;
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

-- the screen's view of the three gateways: configured, mode, last four — never the key
CREATE OR REPLACE FUNCTION finance.gateway_config()
RETURNS TABLE (gateway text, configured boolean, has_hash boolean, mode text, last4 text, set_at timestamptz, set_by_name text)
LANGUAGE sql STABLE AS $$
    SELECT g.gateway, c.secret_enc IS NOT NULL, c.hash_enc IS NOT NULL, c.mode, c.last4, c.set_at,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
      FROM (VALUES ('paystack'), ('flutterwave'), ('quickteller')) g(gateway)
      LEFT JOIN finance.gateway_credential c ON c.gateway = g.gateway
      LEFT JOIN iam.person p ON p.id = c.set_by
     ORDER BY g.gateway
$$;

COMMIT;
