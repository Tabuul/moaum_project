-- ═══════════════════════════════════════════════════════════════════════════
-- V218 — a Readmission payment category
--
--   A student who has run past their maximum duration, or lapsed on probation,
--   may be readmitted by the School to continue from where they stopped — against
--   a readmission fee. This adds "Readmission" to the managed payment categories
--   (ref.fee_item) so the Bursary can state a readmission charge on the fee
--   schedule, which the readmitted student then pays through the shared finance
--   engine on their fees page like any other charge.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Readmission payment category (V218)', true);

INSERT INTO ref.fee_item (code, name, ord) VALUES ('READMISSION', 'Readmission', 170)
ON CONFLICT (code) DO NOTHING;

COMMIT;
