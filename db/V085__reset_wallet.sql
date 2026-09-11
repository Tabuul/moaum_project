-- ═══════════════════════════════════════════════════════════════════════════
-- V085 — reset a single student's wallet to zero (wipe the ledger, start afresh)
--
--   The Bursary can wipe one student's wallet: every credit, top-up, applied
--   entry, reversal and refund, and any withdrawal request, are deleted, so the
--   balance returns to zero and the statement is empty. It is one student at a
--   time and deliberate — the number is looked up first.
--
--   The delete is not silent: finance.wallet_entry and finance.wallet_withdrawal
--   are on the audit spine, so every deleted row is recorded against the officer
--   who reset the wallet and the reason they gave. Withdrawals are removed first
--   because a withdrawal may reference the entry that paid it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'Reset a student wallet: wipe the ledger to start afresh (V085)', true);

CREATE OR REPLACE FUNCTION finance.reset_wallet(p_student uuid)
RETURNS TABLE (entries int, withdrawals int)
LANGUAGE plpgsql AS $$
DECLARE ne int; nw int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a wallet reset is made by a person' USING ERRCODE = '23514';
    END IF;
    IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN
        RAISE EXCEPTION 'no student on the register to reset' USING ERRCODE = '23503';
    END IF;
    DELETE FROM finance.wallet_withdrawal WHERE student_id = p_student;
    GET DIAGNOSTICS nw = ROW_COUNT;
    DELETE FROM finance.wallet_entry WHERE student_id = p_student;
    GET DIAGNOSTICS ne = ROW_COUNT;
    RETURN QUERY SELECT ne, nw;
END $$;

COMMIT;
