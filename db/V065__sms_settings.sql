-- ═══════════════════════════════════════════════════════════════════════════
-- V065 — SMS settings: eBulkSMS, the API key supplied on the dashboard
--
--   SMS notices went out only through the generic relay (MOAUM_NOTICES_SMS_URL).
--   This lets the Directorate of ICT supply an eBulkSMS account on the portal —
--   username, sender ID and API key — so the portal sends SMS directly. The API
--   key is encrypted at rest with the server passphrase (as the mail password
--   is, V057) and is never read back to any screen; the act of setting or
--   clearing it is recorded on the spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE platform.sms_settings (
    id          boolean PRIMARY KEY DEFAULT true,
    provider    text NOT NULL DEFAULT 'EBULKSMS',
    username    text NULL,          -- the eBulkSMS account username
    sender      text NULL,          -- the sender ID shown on the handset (<= 11 chars)
    api_key_enc bytea NULL,
    enabled     boolean NOT NULL DEFAULT false,
    set_by      uuid NULL,
    set_at      timestamptz NULL,
    CONSTRAINT ck_sms_singleton CHECK (id = true),
    CONSTRAINT ck_sms_provider  CHECK (provider IN ('EBULKSMS')),
    CONSTRAINT ck_sms_sender    CHECK (sender IS NULL OR length(btrim(sender)) BETWEEN 1 AND 11)
);
INSERT INTO platform.sms_settings (id) VALUES (true);

SELECT audit.exempt('platform.sms_settings',
    'Carries the SMS gateway API key encrypted at rest; copying it into the audit trail would '
    'put the secret in a second, longer-lived place. The act of setting or clearing it is '
    'recorded in platform.sms_settings_event, which is on the spine, and the key is never selected back.');

CREATE TABLE platform.sms_settings_event (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind      text NOT NULL,
    by_person uuid NOT NULL,
    at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sse_kind CHECK (kind IN ('SET','CLEARED'))
);
SELECT audit.attach('platform.sms_settings_event');

-- set the account and (optionally) the API key; the key is encrypted with the server passphrase
CREATE OR REPLACE FUNCTION platform.set_sms_settings(
        p_provider text, p_username text, p_sender text, p_enabled boolean, p_api_key text, p_key text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'SMS settings are set by a person' USING ERRCODE = '23514'; END IF;
    IF p_api_key IS NOT NULL AND btrim(p_api_key) <> '' AND (p_key IS NULL OR length(p_key) < 8) THEN
        RAISE EXCEPTION 'no server passphrase to encrypt the SMS API key with' USING ERRCODE = '23514',
            HINT = 'Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; the key is never stored in the clear.';
    END IF;
    UPDATE platform.sms_settings SET
        provider = coalesce(nullif(btrim(p_provider), ''), 'EBULKSMS'),
        username = nullif(btrim(p_username), ''),
        sender   = nullif(btrim(p_sender), ''),
        enabled  = coalesce(p_enabled, false),
        api_key_enc = CASE WHEN p_api_key IS NULL OR btrim(p_api_key) = '' THEN api_key_enc
                           ELSE pgp_sym_encrypt(btrim(p_api_key), p_key) END,
        set_by = v_actor, set_at = now()
     WHERE id = true;
    INSERT INTO platform.sms_settings_event (kind, by_person) VALUES ('SET', v_actor);
END $$;

-- what a screen may see: the account, sender, whether a key is set and whether it is enabled — never the key
CREATE OR REPLACE FUNCTION platform.sms_config()
RETURNS TABLE (provider text, username text, sender text, enabled boolean, api_key_set boolean,
               set_at timestamptz, set_by_name text)
LANGUAGE sql STABLE AS $$
    SELECT s.provider, s.username, s.sender, s.enabled, s.api_key_enc IS NOT NULL, s.set_at,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
      FROM platform.sms_settings s LEFT JOIN iam.person p ON p.id = s.set_by WHERE s.id = true
$$;

-- the API key, decrypted, for the sender's own use only
CREATE OR REPLACE FUNCTION platform.sms_api_key(p_key text)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE v bytea;
BEGIN
    SELECT api_key_enc INTO v FROM platform.sms_settings WHERE id = true;
    IF v IS NULL OR p_key IS NULL OR p_key = '' THEN RETURN NULL; END IF;
    RETURN pgp_sym_decrypt(v, p_key);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION platform.clear_sms_api_key()
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'SMS settings are cleared by a person' USING ERRCODE = '23514'; END IF;
    UPDATE platform.sms_settings SET api_key_enc = NULL, enabled = false, set_by = v_actor, set_at = now() WHERE id = true;
    INSERT INTO platform.sms_settings_event (kind, by_person) VALUES ('CLEARED', v_actor);
END $$;

COMMIT;
