-- ═══════════════════════════════════════
-- V499 — The old-portal fees reset reverses the ledger, keeps what it deleted, and leaves a reloaded payment free to be posted
--
--   finance.reset_legacy_payments (V305, V309) deleted the old-portal payment records (channel 'Legacy', reference MOAUM-LEG-…)
--   and nothing else: payments made on the portal — the gateways, the bank, the Bursary desk — were never in scope, and still
--   are not. But the general ledger had posted many of those records (67,490 on the 13 Oct copy of the live data), and the reset
--   left their journals standing: the books kept income no record stood behind. And a reload of the same export could never
--   reach the ledger again: the ledger's sync (finance.gl_sync, gl_unposted) takes a payment as posted while any journal of
--   source PAYMENT names its reference, and the ledger holds one such journal a reference (uq_gl_journal_source).
--
--   Restated, the reset now does for each record what V449 did for the duplicates it withdrew:
--     · its posted journal is reversed (finance.gl_reverse), so the books lose the income with the record;
--     · that journal (and any reversed earlier) is marked as the journal of a reset payment (source_type PAYMENT_RESET,
--       source_ref the reference and the record's id), so the reference is free: the same payment loaded again is posted
--       afresh by the sync, once;
--     · the record is kept on finance.legacy_payment_reset (what it said, its journal and the reversal, who, when, why), then
--       removed — the removal on the audit spine as before;
--     · a record a deferment fee, a refund or the GST reconciliation points at is left and counted (V305 left only a deferment
--       fee's; a GST reconciliation's made the whole reset fail, a refund's was left pointing at nothing);
--     · in batches (5,000 by default): the screen asks again until none is left, so no single request runs for minutes.
--   The guards are unchanged: a person, the word RESET, an optional session, and only the import's own records.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V499: the old-portal fees reset reverses the ledger and keeps what it deleted', true);

-- ── what a reset deleted ──
CREATE TABLE finance.legacy_payment_reset (
    id                uuid PRIMARY KEY,           -- the payment record's own id
    reference         text NOT NULL,
    student_id        uuid NOT NULL,
    session           text NOT NULL,
    purpose           text NOT NULL,
    amount            numeric NOT NULL,
    confirmed_at      timestamptz NULL,
    receipt_no        text NULL,
    note              text NULL,
    ledger_journal    uuid NULL,
    reversal_journal  uuid NULL,
    reset_at          timestamptz NOT NULL DEFAULT now(),
    reset_by          uuid NULL,
    reason            text NOT NULL
);
COMMENT ON TABLE finance.legacy_payment_reset IS
  'V499: every old-portal payment record the fees reset deleted — what it said, the ledger journal it had and the reversal posted for it, who reset it, when and why.';
CREATE INDEX ix_legacy_payment_reset_ref ON finance.legacy_payment_reset (reference);
CREATE INDEX ix_legacy_payment_reset_student ON finance.legacy_payment_reset (student_id, session);
SELECT audit.attach('finance.legacy_payment_reset');

-- ── the reset ──
DROP FUNCTION finance.reset_legacy_payments(text, text);
CREATE FUNCTION finance.reset_legacy_payments(p_session text, p_confirm text, p_limit integer DEFAULT 5000)
RETURNS TABLE (deleted bigint, kept_in_use bigint, ledger_reversed bigint, remaining bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, finance, people, public, pg_temp
AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := coalesce(nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), 'old-portal fees history reset to be loaded again');
        n bigint; nr bigint; v_kept bigint; v_left bigint;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'the imported payment history is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm that the imported payment history is to be deleted' USING ERRCODE = '23514';
    END IF;
    IF p_session IS NOT NULL AND p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'a session looks like 2022/2023' USING ERRCODE = '23514';
    END IF;
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 20000 THEN
        RAISE EXCEPTION 'a reset batch is from 1 to 20,000 records' USING ERRCODE = '23514';
    END IF;

    -- the batch: the import's own records nothing points at, each with the ledger journal of its reference (if any), set apart
    -- and locked; the whole batch is worked at once (a record at a time took 7 ms each on the live-shaped copy)
    IF to_regclass('pg_temp.legacy_reset_batch') IS NOT NULL THEN DROP TABLE pg_temp.legacy_reset_batch; END IF;   -- an earlier batch of this transaction
    CREATE TEMP TABLE legacy_reset_batch ON COMMIT DROP AS
        SELECT r.*, j.id AS journal_id, j.journal_no, (j.status = 'POSTED') AS posted, gen_random_uuid() AS reversal_id
          FROM (SELECT r.* FROM finance.payment_reference r
                 WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)
                   AND NOT EXISTS (SELECT 1 FROM people.deferment_fee d WHERE d.reference = r.reference)
                   AND NOT EXISTS (SELECT 1 FROM finance.refund f WHERE f.source_reference = r.reference)
                   AND NOT EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = r.id)
                 ORDER BY r.id
                 LIMIT p_limit
                 FOR UPDATE OF r) r
          LEFT JOIN finance.gl_journal j ON j.source_type = 'PAYMENT' AND j.source_ref = r.reference;

    -- the income the ledger posted for each, reversed as finance.gl_reverse reverses a journal: a journal of the same lines with
    -- debit and credit swapped, dated today, 'Reversal of #<n> — <reason>', pointing at the one it reverses, which is REVERSED
    INSERT INTO finance.gl_journal (id, entry_date, memo, source, source_type, source_ref, posted_by, reverses)
    SELECT b.reversal_id, current_date, 'Reversal of #' || b.journal_no || ' — old-portal payment ' || b.reference || ' reset: ' || v_reason,
           'MANUAL', 'REVERSAL', b.journal_id::text, v_actor, b.journal_id
      FROM legacy_reset_batch b WHERE b.posted;
    GET DIAGNOSTICS nr = ROW_COUNT;
    INSERT INTO finance.gl_posting (journal_id, line, account, debit, credit, narration, session, fund)
    SELECT b.reversal_id, p.line, p.account, p.credit, p.debit, p.narration, p.session, p.fund
      FROM legacy_reset_batch b JOIN finance.gl_posting p ON p.journal_id = b.journal_id
     WHERE b.posted;
    -- and every such journal no longer holds the reference, so the same payment loaded again is posted afresh, once
    UPDATE finance.gl_journal j
       SET status = CASE WHEN b.posted THEN 'REVERSED' ELSE j.status END,
           source_type = 'PAYMENT_RESET', source_ref = b.reference || '#' || b.id
      FROM legacy_reset_batch b
     WHERE j.id = b.journal_id;

    -- the records kept, then removed (the removal on the audit spine in the caller's name)
    INSERT INTO finance.legacy_payment_reset (id, reference, student_id, session, purpose, amount, confirmed_at, receipt_no, note,
                                             ledger_journal, reversal_journal, reset_by, reason)
    SELECT b.id, b.reference, b.student_id, b.session, b.purpose, b.amount, b.confirmed_at, b.receipt_no, b.note,
           b.journal_id, CASE WHEN b.posted THEN b.reversal_id END, v_actor, v_reason
      FROM legacy_reset_batch b
    ON CONFLICT (id) DO NOTHING;
    DELETE FROM finance.payment_reference r USING legacy_reset_batch b WHERE r.id = b.id;
    GET DIAGNOSTICS n = ROW_COUNT;
    DROP TABLE pg_temp.legacy_reset_batch;

    -- what is kept and what is left, in one pass: the few records something points at looked up by hash, not row by row (6 s
    -- over the 85,000 records of a session on the live-shaped copy as row-by-row checks)
    SELECT count(*) FILTER (WHERE linked), count(*) FILTER (WHERE NOT linked) INTO v_kept, v_left
      FROM (SELECT (r.reference IN (SELECT d.reference FROM people.deferment_fee d)
                    OR r.reference IN (SELECT f.source_reference FROM finance.refund f WHERE f.source_reference IS NOT NULL)
                    OR r.id IN (SELECT g.payment_reference_id FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id IS NOT NULL)) AS linked
              FROM finance.payment_reference r
             WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)) s;

    RETURN QUERY SELECT n, v_kept, nr, v_left;
END $$;
COMMENT ON FUNCTION finance.reset_legacy_payments(text, text, integer) IS
  'V305/V499: deletes up to p_limit old-portal payment records (channel Legacy, MOAUM-LEG-…; a session or all) on the word RESET: each one''s posted ledger journal reversed and freed for a reload, the record kept on finance.legacy_payment_reset; one a deferment fee, a refund or the GST reconciliation points at is left and counted. Returns what was deleted, kept, reversed on the ledger, and what remains to delete.';

COMMIT;
