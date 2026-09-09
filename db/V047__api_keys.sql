-- ═══════════════════════════════════════════════════════════════════════════
-- V047 — API consumers and their keys (API)
--
--   Every client of the University's API is named, scoped and rate-limited, and
--   no key lives longer than a year. A key is shown once, at issue, and only its
--   hash is kept — the same rule as a password. Rotation is overlapping: a new
--   key is issued while the old one still works, the consumer confirms, then the
--   old one is revoked. A credential with an end date stops working by itself.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE apimgmt.consumer (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    owner       text NOT NULL,
    scopes      text NOT NULL,
    quota_day   int  NULL,
    status      text NOT NULL DEFAULT 'ACTIVE',
    created_by  uuid NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_consumer_status CHECK (status IN ('ACTIVE','DEPRECATED'))
);
SELECT audit.attach('apimgmt.consumer');

CREATE TABLE apimgmt.key (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    consumer_id uuid NOT NULL REFERENCES apimgmt.consumer(id),
    key_hash    bytea NOT NULL,
    last4       text NOT NULL,
    issued_by   uuid NOT NULL,
    issued_at   timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz NULL
);
CREATE INDEX ix_key_consumer ON apimgmt.key (consumer_id);
SELECT audit.attach('apimgmt.key');

CREATE OR REPLACE FUNCTION apimgmt.register_consumer(p_name text, p_owner text, p_scopes text, p_quota int)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_id uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a consumer is registered by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' OR coalesce(btrim(p_owner), '') = '' OR coalesce(btrim(p_scopes), '') = '' THEN
        RAISE EXCEPTION 'a consumer is named, owned and scoped' USING ERRCODE = '23514';
    END IF;
    INSERT INTO apimgmt.consumer (name, owner, scopes, quota_day, created_by)
    VALUES (btrim(p_name), btrim(p_owner), btrim(p_scopes), p_quota, who) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- issue a key: generate it, keep only its hash and last four, return the key ONCE
CREATE OR REPLACE FUNCTION apimgmt.issue_key(p_consumer uuid, p_days int)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_key text; v_days int := least(greatest(coalesce(p_days, 365), 1), 366);
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a key is issued by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM apimgmt.consumer WHERE id = p_consumer AND status = 'ACTIVE') THEN
        RAISE EXCEPTION 'no active consumer to issue a key to' USING ERRCODE = '23503';
    END IF;
    v_key := 'mk_' || encode(gen_random_bytes(24), 'hex');
    INSERT INTO apimgmt.key (consumer_id, key_hash, last4, issued_by, expires_at)
    VALUES (p_consumer, digest(v_key, 'sha256'), right(v_key, 4), who, now() + make_interval(days => v_days));
    RETURN v_key;
END $$;

CREATE OR REPLACE FUNCTION apimgmt.revoke_key(p_key uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a key is revoked by a person' USING ERRCODE = '23514'; END IF;
    UPDATE apimgmt.key SET revoked_at = now() WHERE id = p_key AND revoked_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'no live key to revoke' USING ERRCODE = '23514'; END IF;
END $$;

CREATE OR REPLACE FUNCTION apimgmt.deprecate_consumer(p_consumer uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a consumer is deprecated by a person' USING ERRCODE = '23514'; END IF;
    UPDATE apimgmt.consumer SET status = 'DEPRECATED' WHERE id = p_consumer AND status = 'ACTIVE';
    UPDATE apimgmt.key SET revoked_at = now() WHERE consumer_id = p_consumer AND revoked_at IS NULL;
END $$;
