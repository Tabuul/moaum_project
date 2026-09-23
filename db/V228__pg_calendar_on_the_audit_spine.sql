-- ═══════════════════════════════════════════════════════════════════════════
-- V228 — the PG calendar tables go on the audit spine
--
--   V224 created admissions.pg_academic_session and admissions.pg_semester and
--   was applied as written. The tables hold real state the School edits — like
--   policy.academic_session and policy.semester — so they belong on the audit
--   spine (attached, not exempt): every write then carries the actor the
--   request runs as. That correction was first made by editing V224 after it
--   had been applied, which the migration ledger rightly refuses; it lives here
--   instead, as its own step. Idempotent: a table already carrying its audit
--   trigger is left alone.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = 'admissions.pg_academic_session'::regclass
                      AND NOT tgisinternal AND tgname LIKE 'trg_audit_%') THEN
        PERFORM audit.attach('admissions.pg_academic_session');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid = 'admissions.pg_semester'::regclass
                      AND NOT tgisinternal AND tgname LIKE 'trg_audit_%') THEN
        PERFORM audit.attach('admissions.pg_semester');
    END IF;
END $$;

COMMIT;
