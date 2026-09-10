-- ═══════════════════════════════════════════════════════════════════════════
-- V066 — the Bursary credits a student's wallet directly
--
--   Until now a wallet was credited only by a NELFUND remittance (a batch or a
--   matched row) or a confirmed top-up. This lets the Bursary put a credit on a
--   student's wallet by hand — a correction, a sponsor's payment received off
--   the gateway, a goodwill credit — naming the amount and the reason. It is an
--   attributed act (finance.wallet_entry is on the spine); it counts toward the
--   balance like any other CREDIT, and the reason travels on the entry's note.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.credit_wallet(p_student uuid, p_session text, p_amount numeric, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a wallet credit is made by a person' USING ERRCODE = '23514';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a wallet credit is for an amount above zero' USING ERRCODE = '23514';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'a wallet credit names its reason' USING ERRCODE = '23514',
            HINT = 'Say why the wallet is credited; the student sees it on the statement.';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note)
    VALUES (p_student, p_session, 'CREDIT', p_amount, 'BURSARY', 'Bursary credit: ' || btrim(p_reason))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

COMMIT;
