-- ═══════════════════════════════════════════════════════════════════════════
-- V086 — attach finance.fee_setting to the audit spine
--
--   V083 created finance.fee_setting. The line that attaches it to the audit
--   spine was added to V083 AFTER V083 had already been applied to production,
--   which the migration ledger correctly refuses (an applied migration must not
--   change). The attachment therefore belongs in its own file, here.
--
--   Idempotent: it attaches only if the table has no audit trigger yet, so it is
--   safe on a database that already carries the attachment and on one that does
--   not (production, where V083 shipped without it).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Attach finance.fee_setting to the audit spine (V086; V083 shipped without the line)', true);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'finance.fee_setting'::regclass
           AND NOT tgisinternal
           AND tgname LIKE 'trg_audit_%'
    ) THEN
        PERFORM audit.attach('finance.fee_setting');
    END IF;
END $$;

COMMIT;
