-- ═══════════════════════════════════════
-- V417 — the keyed notification address shown again, each viewing on the record
--
--   The key in the Pay on Quickteller notification address is shown once, when generated. Lost before Interswitch has it, the
--   only way back was a new key and telling Interswitch again. The Directorate of ICT may now have the address shown again;
--   each viewing is a row here, and the audit spine records who, when and why — a secret read is a fact on the record like a
--   secret written.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V417: the keyed notification address shown again, each viewing on the record', true);

CREATE TABLE IF NOT EXISTS finance.gateway_secret_view (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway    text NOT NULL,
    what       text NOT NULL,
    viewed_by  uuid NOT NULL,
    viewed_at  timestamptz NOT NULL DEFAULT now(),
    reason     text NOT NULL CHECK (btrim(reason) <> '')
);
COMMENT ON TABLE finance.gateway_secret_view IS 'V417: each time a stored gateway secret (the keyed PAYDirect notification address) was shown to a person — who, when, why; the audit spine carries the row.';
SELECT audit.attach('finance.gateway_secret_view') WHERE NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_finance_gateway_secret_view');

/* the viewing recorded by the person asking, with their reason; the row's id */
CREATE OR REPLACE FUNCTION finance.note_secret_view(p_gateway text, p_what text, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'SECRET_VIEW_ACTOR: a secret is shown to a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'SECRET_VIEW_REASON: say why the secret is shown' USING ERRCODE = '23514'; END IF;
    INSERT INTO finance.gateway_secret_view (gateway, what, viewed_by, reason) VALUES (p_gateway, p_what, who, btrim(p_reason)) RETURNING id INTO v;
    RETURN v;
END $fn$;

COMMIT;
