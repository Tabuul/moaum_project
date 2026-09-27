-- ═══════════════════════════════════════════════════════════════════════════
-- V276 — Quickteller rebuilt on Interswitch WebPAY: the attempt keeps its txn_ref
--
--   The card gateway "Quickteller" is now the University's Interswitch WebPAY
--   set-up: two merchants (the University, product 6498, and the College of
--   Health Sciences, product 6207), each with its pay item and its MAC key,
--   chosen by the payer's College. WebPAY refuses a transaction reference it
--   has seen before, so each visit to the payment page is its own attempt
--   with its own txn_ref (the fee reference, then the reference with -A2,
--   -A3 …); the attempt row remembers which, so the requery, the return and
--   the sweep find the payment whichever attempt paid. The gateway's return
--   to the portal is logged as its own source.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V276: Quickteller on Interswitch WebPAY', true);

ALTER TABLE finance.gateway_attempt ADD COLUMN IF NOT EXISTS txn_ref text NULL;
CREATE INDEX IF NOT EXISTS ix_gateway_attempt_txn_ref ON finance.gateway_attempt (txn_ref) WHERE txn_ref IS NOT NULL;

ALTER TABLE finance.gateway_event DROP CONSTRAINT IF EXISTS ck_ge_source;
ALTER TABLE finance.gateway_event ADD CONSTRAINT ck_ge_source CHECK (source IN ('WEBHOOK', 'VERIFY', 'SWEEP', 'TEST', 'RETURN'));

COMMIT;
