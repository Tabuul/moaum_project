-- ═══════════════════════════════════════════════════════════════════════════
-- V018 — JAMB names a programme more than one way
--
-- ref.jamb_alias holds ONE name per code, and the first real CAPS download
-- showed why that is not enough: the UTME list and the Direct Entry list can
-- name the same programme differently, and a name mapped on the intake
-- screen replaced the one before it. A programme now keeps every name JAMB
-- has used for it; the alias list stays the primary one, and the rest are
-- beside it, each added by a person, recorded against their office.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'V018: further JAMB names for a programme', true);
END $seed$;

CREATE TABLE ref.jamb_alias_name (
    jamb_key  text PRIMARY KEY,               -- the name, lower-cased and stripped, which is what a file is matched on
    jamb_name text NOT NULL,                  -- the name as JAMB wrote it
    code      text NOT NULL,
    added_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_alias_name_code CHECK (code ~ '^C[0-9]{5}$'),
    CONSTRAINT ck_alias_name_key  CHECK (jamb_key = lower(regexp_replace(jamb_name, '[^A-Za-z0-9]', '', 'g')) AND length(jamb_key) > 0)
);

COMMENT ON TABLE ref.jamb_alias_name IS
  'Every further name JAMB has used for a programme, beside the primary one in '
  'ref.jamb_alias. One name means one programme — the key is the name — but one '
  'programme may carry many names, because JAMB does.';

SELECT audit.attach('ref.jamb_alias_name');

GRANT SELECT, INSERT, UPDATE ON ref.jamb_alias_name TO app_admissions;
GRANT SELECT ON ref.jamb_alias_name TO app_auditor;

COMMIT;
