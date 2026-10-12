-- ═══════════════════════════════════════
-- V407 — a notification received while no service credentials are set is logged as that
--
--   Interswitch's PAYDirect payment notifications are believed only with the service username and password the University
--   agreed with Interswitch. Until those are set on the portal, every notification — Interswitch's certification run among
--   them — is kept and not believed, and the log called that a bad signature, as if a wrong secret had been presented. It is a
--   different thing, with a different remedy: set the credentials. The log now says so (outcome NO_CREDENTIALS).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V407: a notification received with no service credentials set is logged as that', true);

ALTER TABLE finance.gateway_event DROP CONSTRAINT IF EXISTS ck_ge_outcome;
ALTER TABLE finance.gateway_event ADD CONSTRAINT ck_ge_outcome CHECK (outcome IN
    ('SETTLED', 'ALREADY_SETTLED', 'UNKNOWN_REFERENCE', 'SHORT_PAID', 'NOT_SUCCESSFUL', 'IGNORED', 'BAD_SIGNATURE', 'GATEWAY_ERROR',
     'REVERSED', 'VALID', 'INVALID', 'NO_CREDENTIALS'));

COMMIT;
