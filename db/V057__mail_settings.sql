-- ═══════════════════════════════════════════════════════════════════════════
-- V057 — manual mail server settings (Microsoft 365): IMAP, POP and SMTP
--
--   The portal can now be given the IMAP, POP and SMTP parameters of a mail
--   account — for Microsoft 365, the standard servers — from a screen, the way
--   a payment gateway key is (V039). The host, port and encryption of each are
--   plain settings; the account password is encrypted at rest with the server
--   passphrase (pgcrypto) and never read back to any screen, exactly as a
--   gateway secret. The act of setting or clearing it is on the audit spine.
--
--   The row is a singleton (id = true). It is seeded with the Microsoft 365
--   servers so an operator supplies only the account and password; changing a
--   host or port is still allowed for another provider.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE platform.mail_settings (
    id              boolean PRIMARY KEY DEFAULT true,
    smtp_host       text NULL,
    smtp_port       int  NULL,
    smtp_encryption text NULL,   -- STARTTLS | SSL | NONE
    imap_host       text NULL,
    imap_port       int  NULL,
    imap_encryption text NULL,
    pop_host        text NULL,
    pop_port        int  NULL,
    pop_encryption  text NULL,
    username        text NULL,   -- the full email address
    from_address    text NULL,   -- what recipients see in From
    password_enc    bytea NULL,
    set_by          uuid NULL,
    set_at          timestamptz NULL,
    CONSTRAINT ck_mail_singleton  CHECK (id = true),
    CONSTRAINT ck_mail_smtp_enc   CHECK (smtp_encryption IS NULL OR smtp_encryption IN ('STARTTLS','SSL','NONE')),
    CONSTRAINT ck_mail_imap_enc   CHECK (imap_encryption IS NULL OR imap_encryption IN ('SSL','STARTTLS','NONE')),
    CONSTRAINT ck_mail_pop_enc    CHECK (pop_encryption  IS NULL OR pop_encryption  IN ('SSL','STARTTLS','NONE')),
    CONSTRAINT ck_mail_ports      CHECK (
        (smtp_port IS NULL OR smtp_port BETWEEN 1 AND 65535)
        AND (imap_port IS NULL OR imap_port BETWEEN 1 AND 65535)
        AND (pop_port IS NULL OR pop_port BETWEEN 1 AND 65535))
);

-- seeded with the Microsoft 365 servers; the account and password are supplied on the screen
INSERT INTO platform.mail_settings
       (id, smtp_host, smtp_port, smtp_encryption, imap_host, imap_port, imap_encryption, pop_host, pop_port, pop_encryption)
VALUES (true, 'smtp.office365.com', 587, 'STARTTLS', 'outlook.office365.com', 993, 'SSL', 'outlook.office365.com', 995, 'SSL');

SELECT audit.exempt('platform.mail_settings',
    'Carries the mail account password encrypted at rest; copying it into the audit '
    'trail would put the secret in a second, longer-lived place. The act of setting or '
    'clearing it is recorded in platform.mail_settings_event, which is on the spine, and '
    'the password is never selected back to any screen.');

CREATE TABLE platform.mail_settings_event (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind      text NOT NULL,
    by_person uuid NOT NULL,
    at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_mse_kind CHECK (kind IN ('SET','CLEARED'))
);
SELECT audit.attach('platform.mail_settings_event');

-- set the servers and (optionally) the account + password; the password is encrypted with the server passphrase
CREATE OR REPLACE FUNCTION platform.set_mail_settings(
        p_smtp_host text, p_smtp_port int, p_smtp_enc text,
        p_imap_host text, p_imap_port int, p_imap_enc text,
        p_pop_host text, p_pop_port int, p_pop_enc text,
        p_username text, p_from text, p_password text, p_key text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'mail settings are set by a person' USING ERRCODE = '23514'; END IF;
    IF p_password IS NOT NULL AND btrim(p_password) <> '' AND (p_key IS NULL OR length(p_key) < 8) THEN
        RAISE EXCEPTION 'no server passphrase to encrypt the mail password with' USING ERRCODE = '23514',
            HINT = 'Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service; the password is never stored in the clear.';
    END IF;
    UPDATE platform.mail_settings SET
        smtp_host = p_smtp_host, smtp_port = p_smtp_port, smtp_encryption = p_smtp_enc,
        imap_host = p_imap_host, imap_port = p_imap_port, imap_encryption = p_imap_enc,
        pop_host = p_pop_host, pop_port = p_pop_port, pop_encryption = p_pop_enc,
        username = nullif(btrim(p_username), ''), from_address = nullif(btrim(p_from), ''),
        password_enc = CASE WHEN p_password IS NULL OR btrim(p_password) = '' THEN password_enc
                            ELSE pgp_sym_encrypt(btrim(p_password), p_key) END,
        set_by = v_actor, set_at = now()
     WHERE id = true;
    INSERT INTO platform.mail_settings_event (kind, by_person) VALUES ('SET', v_actor);
END $$;

-- what a screen may see: the servers, the account, whether a password is set — never the password
CREATE OR REPLACE FUNCTION platform.mail_config()
RETURNS TABLE (smtp_host text, smtp_port int, smtp_encryption text, imap_host text, imap_port int, imap_encryption text,
               pop_host text, pop_port int, pop_encryption text, username text, from_address text,
               password_set boolean, set_at timestamptz, set_by_name text)
LANGUAGE sql STABLE AS $$
    SELECT m.smtp_host, m.smtp_port, m.smtp_encryption, m.imap_host, m.imap_port, m.imap_encryption,
           m.pop_host, m.pop_port, m.pop_encryption, m.username, m.from_address,
           m.password_enc IS NOT NULL, m.set_at,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
      FROM platform.mail_settings m LEFT JOIN iam.person p ON p.id = m.set_by WHERE m.id = true
$$;

-- the password, decrypted, for the sender's own use only
CREATE OR REPLACE FUNCTION platform.mail_password(p_key text)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE v bytea;
BEGIN
    SELECT password_enc INTO v FROM platform.mail_settings WHERE id = true;
    IF v IS NULL OR p_key IS NULL OR p_key = '' THEN RETURN NULL; END IF;
    RETURN pgp_sym_decrypt(v, p_key);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION platform.clear_mail_password()
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'mail settings are cleared by a person' USING ERRCODE = '23514'; END IF;
    UPDATE platform.mail_settings SET password_enc = NULL, set_by = v_actor, set_at = now() WHERE id = true;
    INSERT INTO platform.mail_settings_event (kind, by_person) VALUES ('CLEARED', v_actor);
END $$;

COMMIT;
