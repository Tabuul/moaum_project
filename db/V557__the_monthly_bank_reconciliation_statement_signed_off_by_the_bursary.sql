-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V557 — The bank reconciliation statement for a period, for the fees collection and the disbursement accounts, signed off
--
--   The ledger's balance of 1010 Bank — Fees collection or 1020 Bank — Disbursements at the end of a period is set beside the
--   balance on the bank's statement, with the items that explain the difference, found from what V545 and V552 matched
--   (finance.bank_reconciliation_items):
--     · on the ledger, not yet in the bank — a payment confirmed (through the bank, or through a channel that never passes it: the
--       old portal's, a migration), a refund, a withdrawal or a voucher paid and not yet on the statement, another journal;
--     · in the bank, not on the ledger — a credit the portal never confirmed, a payment received twice, a credit or debit no one
--       found, a NELFUND remittance not yet credited to students, a gateway's charges, an amount that differs.
--   A statement line the Bursary has accounted for with a journal (bank charges, a transfer between the accounts) is tied to it
--   (finance.book_statement_line), and neither is an item. The items run from the start of the account's first reconciliation
--   (what came before is the opening position) to the end of the period.
--   A reconciliation is prepared by the Bursary with the closing balance on the statement (finance.prepare_bank_reconciliation) and
--   signed by another officer (finance.sign_bank_reconciliation) — once the period has ended, the bank's statements cover every
--   day of it, nothing of it waits to be posted on the ledger, and any difference left is explained; it is then kept as signed,
--   its items with it.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V557: the bank reconciliation statement', true);

-- ── a statement line accounted for with a journal ──────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.bank_statement_line
    ADD COLUMN ledger_journal uuid NULL REFERENCES finance.gl_journal(id) ON DELETE SET NULL,
    ADD COLUMN booked_by uuid NULL,
    ADD COLUMN booked_at timestamptz NULL,
    ADD COLUMN booked_note text NULL;
CREATE INDEX ix_bsl_ledger_journal ON finance.bank_statement_line (ledger_journal) WHERE ledger_journal IS NOT NULL;
COMMENT ON COLUMN finance.bank_statement_line.ledger_journal IS
  'V557: the journal the Bursary accounted for this line with (bank charges, a transfer between the accounts, a difference put right): the line and the journal are then no reconciling item.';

/* the account a statement's kind is reconciled with */
CREATE FUNCTION finance.bank_account_of(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_kind WHEN 'COLLECTIONS' THEN '1010' WHEN 'DISBURSEMENT' THEN '1020' END
$fn$;

-- ── the reconciliations ──────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.bank_reconciliation (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account           text NOT NULL CHECK (account IN ('1010', '1020')),
    period_from       date NOT NULL,
    period_to         date NOT NULL,
    statement_closing numeric(16,2) NOT NULL,
    ledger_balance    numeric(16,2) NOT NULL,
    items_effect      numeric(16,2) NOT NULL,
    difference        numeric(16,2) NOT NULL,
    summary           jsonb NOT NULL,
    items             jsonb NULL,
    note              text NULL,
    state             text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'SIGNED')),
    prepared_by       uuid NOT NULL,
    prepared_at       timestamptz NOT NULL DEFAULT now(),
    signed_by         uuid NULL,
    signed_at         timestamptz NULL,
    CONSTRAINT ck_brec_period CHECK (period_to >= period_from),
    CONSTRAINT ck_brec_signed CHECK (state <> 'SIGNED' OR (signed_by IS NOT NULL AND signed_at IS NOT NULL AND items IS NOT NULL)),
    CONSTRAINT ex_brec_no_overlap EXCLUDE USING gist (account WITH =, daterange(period_from, period_to, '[]') WITH &&)
);
SELECT audit.attach('finance.bank_reconciliation');
COMMENT ON TABLE finance.bank_reconciliation IS
  'V557: a bank reconciliation statement of 1010 or 1020 for a period — the statement''s closing balance, the ledger''s balance, the reconciling items and what is left unexplained; prepared by the Bursary, signed by another officer and then kept as signed with its items.';

/* a signed reconciliation is kept as signed */
CREATE FUNCTION finance.bank_reconciliation_kept() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    IF OLD.state = 'SIGNED' THEN
        RAISE EXCEPTION 'RECON_SIGNED: the reconciliation of % for % to % is signed and kept as it was signed', OLD.account,
            to_char(OLD.period_from, 'FMDD FMMonth YYYY'), to_char(OLD.period_to, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $fn$;
CREATE TRIGGER trg_bank_reconciliation_kept BEFORE UPDATE OR DELETE ON finance.bank_reconciliation
    FOR EACH ROW EXECUTE FUNCTION finance.bank_reconciliation_kept();

/* where an account's items begin: the start of its first reconciliation (what came before is the opening position) */
CREATE FUNCTION finance.bank_reconciliation_start(p_account text, p_from date)
RETURNS date LANGUAGE sql STABLE AS $fn$
    SELECT least(p_from, coalesce((SELECT min(r.period_from) FROM finance.bank_reconciliation r WHERE r.account = p_account), p_from))
$fn$;

-- ── the reconciling items ────────────────────────────────────────────────────────────────────────────────────────────────
/* every item between the bank's statement and the ledger for an account at the end of a period: effect is what is added to the
   statement's balance to reach the ledger's (+ the ledger holds more, − the bank holds more) */
CREATE FUNCTION finance.bank_reconciliation_items(p_account text, p_from date, p_to date)
RETURNS TABLE (kind text, reference text, day date, description text, amount numeric, effect numeric, line_id uuid, journal_no bigint)
LANGUAGE sql STABLE AS $fn$
WITH k AS (SELECT CASE p_account WHEN '1010' THEN 'COLLECTIONS' WHEN '1020' THEN 'DISBURSEMENT' END AS statement_kind,
                  finance.bank_reconciliation_start(p_account, p_from) AS start),
-- the account's statement lines dated in the items' span
ln AS MATERIALIZED (
    SELECT l.id, l.line_no, l.status, l.matched_kind, l.matched_reference, l.expected_amount, l.settlement_channel, l.settlement_day,
           l.debit, l.credit, l.ledger_journal, coalesce(l.value_date, s.period_to) AS d, s.label,
           upper(coalesce(l.reference, '') || ' ' || coalesce(l.description, '')) AS txt,
           coalesce(nullif(btrim(coalesce(l.reference, '')), ''), l.description, 'line ' || l.line_no) AS what
      FROM finance.bank_statement_line l JOIN finance.bank_statement s ON s.id = l.statement_id CROSS JOIN k
     WHERE s.account_kind = k.statement_kind AND coalesce(l.value_date, s.period_to) BETWEEN k.start AND p_to),
-- the journals moving the account in the span; a reversed journal and its reversal both in it cancel and are left out
jr AS MATERIALIZED (
    SELECT j.id, j.journal_no, j.entry_date, j.memo, j.source_type, j.source_ref, sum(p.debit) - sum(p.credit) AS net,
           CASE WHEN j.source_type = 'WALLET' AND j.source_ref ~ '^WALLET-[0-9a-f-]{36}$' THEN substr(j.source_ref, 8)::uuid END AS wallet_entry
      FROM finance.gl_journal j JOIN finance.gl_posting p ON p.journal_id = j.id CROSS JOIN k
     WHERE p.account = p_account AND j.entry_date BETWEEN k.start AND p_to
       -- a journal that corrects the position brought forward (an opening balance, the wallet's opening reclassified) is no item
       AND coalesce(j.source_type, '') <> 'OPENING' AND NOT (j.source_type = 'WALLET' AND coalesce(j.source_ref, '') LIKE 'WALLET-OPENING%')
       AND NOT (j.status = 'REVERSED' AND EXISTS (SELECT 1 FROM finance.gl_journal r CROSS JOIN k k2
                                                   WHERE r.source_type = 'REVERSAL' AND r.source_ref = j.id::text AND r.entry_date BETWEEN k2.start AND p_to))
       AND NOT (j.source_type = 'REVERSAL' AND EXISTS (SELECT 1 FROM finance.gl_journal o CROSS JOIN k k2
                                                        WHERE o.id = CASE WHEN j.source_ref ~ '^[0-9a-f-]{36}$' THEN j.source_ref::uuid END
                                                          AND o.entry_date BETWEEN k2.start AND p_to))
     GROUP BY j.id
    HAVING sum(p.debit) - sum(p.credit) <> 0),
-- the payments behind the payment journals
pay AS MATERIALIZED (
    SELECT DISTINCT ON (upper(p.reference)) upper(p.reference) AS ref, p.channel, p.purpose, (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date AS day
      FROM reporting.payments p
     WHERE p_account = '1010' AND p.reference IN (SELECT jr.source_ref FROM jr WHERE jr.source_type = 'PAYMENT')
     ORDER BY upper(p.reference), p.confirmed_at DESC NULLS LAST),
booked AS (SELECT DISTINCT ln.ledger_journal AS id FROM ln WHERE ln.ledger_journal IS NOT NULL),
-- a collections line's payment on the ledger by the end of the period
coll_posted AS (
    SELECT DISTINCT upper(j.source_ref) AS ref FROM finance.gl_journal j
     WHERE p_account = '1010' AND j.source_type = 'PAYMENT' AND j.entry_date <= p_to
       AND upper(j.source_ref) IN (SELECT ln.matched_reference FROM ln WHERE ln.matched_kind = 'PAYMENT')),
-- the transfer references of the payouts on the ledger by the end of the period
payout_journal AS (
    SELECT upper(btrim(rf.paid_reference)) AS ref FROM finance.refund rf
      JOIN finance.gl_journal j ON j.source_type = 'REFUND' AND j.source_ref = rf.reference AND j.entry_date <= p_to
     WHERE p_account = '1020' AND rf.paid_reference IS NOT NULL
    UNION
    SELECT upper(btrim(w.paid_ref)) FROM finance.wallet_withdrawal w
      JOIN finance.gl_journal j ON j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || w.entry_id AND j.entry_date <= p_to
     WHERE p_account = '1020' AND w.paid_ref IS NOT NULL),
-- ── 1010: the journals not yet seen in the bank ──
coll_ledger AS (
    SELECT CASE WHEN jr.source_type = 'PAYMENT' AND finance.receipt_through_bank(py.channel) THEN 'RECEIPT_NOT_IN_BANK'
                WHEN jr.source_type = 'PAYMENT' THEN 'RECEIPT_OUTSIDE_BANK'
                WHEN jr.net > 0 THEN 'LEDGER_DEBIT_NOT_IN_BANK' ELSE 'LEDGER_CREDIT_NOT_IN_BANK' END AS kind,
           coalesce(jr.source_ref, '#' || jr.journal_no) AS reference, jr.entry_date AS day,
           CASE WHEN jr.source_type = 'PAYMENT' THEN concat_ws(' · ', py.purpose, py.channel) ELSE jr.memo END AS description,
           abs(jr.net) AS amount, jr.net AS effect, NULL::uuid AS line_id, jr.journal_no
      FROM jr LEFT JOIN pay py ON jr.source_type = 'PAYMENT' AND py.ref = upper(jr.source_ref)
      LEFT JOIN finance.wallet_entry we ON we.id = jr.wallet_entry
     WHERE p_account = '1010'
       AND NOT EXISTS (SELECT 1 FROM booked b WHERE b.id = jr.id)
       -- a payment found by a line, settled in a gateway's day, or reconciled by hand (V068; not the matching's own record)
       AND NOT (coalesce(jr.source_type, '') = 'PAYMENT' AND (
                EXISTS (SELECT 1 FROM ln WHERE ln.matched_kind = 'PAYMENT' AND ln.status IN ('MATCHED', 'AMOUNT_DIFFERS', 'RECEIVED_NOT_CONFIRMED')
                                           AND ln.matched_reference = upper(jr.source_ref))
             OR EXISTS (SELECT 1 FROM ln WHERE ln.status = 'SETTLEMENT' AND ln.settlement_channel = py.channel AND ln.settlement_day = py.day)
             OR EXISTS (SELECT 1 FROM finance.payment_reconciliation pr
                         WHERE pr.reference = upper(jr.source_ref) AND pr.result = 'MATCHED'
                           AND coalesce(pr.note, '') NOT LIKE 'Collections statement %' AND coalesce(pr.note, '') NOT LIKE 'Settled in the collections statement %')))
       -- a wallet credit from a NELFUND remittance the statement shows
       AND NOT (we.id IS NOT NULL AND EXISTS (SELECT 1 FROM ln WHERE ln.matched_kind = 'NELFUND' AND ln.status IN ('MATCHED', 'AMOUNT_DIFFERS')
                                                                AND ln.matched_reference = we.reference))),
-- ── 1010: the lines not yet on the ledger, or not wholly ──
coll_raw AS (
    SELECT ln.*,
           CASE WHEN ln.status IN ('UNMATCHED', 'DUPLICATE') THEN 'BANK_CREDIT_NOT_IN_LEDGER'
                WHEN ln.status = 'DEBIT' THEN 'BANK_DEBIT_NOT_IN_LEDGER'
                WHEN ln.status = 'SETTLEMENT' THEN 'GATEWAY_CHARGES'
                WHEN ln.matched_kind = 'NELFUND' THEN 'NELFUND_NOT_CREDITED'
                WHEN ln.matched_kind = 'PAYMENT' AND NOT EXISTS (SELECT 1 FROM coll_posted cp WHERE cp.ref = ln.matched_reference) THEN 'BANK_CREDIT_NOT_IN_LEDGER'
                WHEN ln.status = 'AMOUNT_DIFFERS' THEN 'AMOUNT_DIFFERENCE' END AS kind,
           CASE WHEN ln.matched_kind = 'NELFUND' THEN
                    (SELECT coalesce(sum(p.debit - p.credit), 0) FROM finance.wallet_entry we
                       JOIN finance.gl_journal j ON j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || we.id AND j.entry_date <= p_to
                       JOIN finance.gl_posting p ON p.journal_id = j.id AND p.account = '1010'
                      WHERE we.reference = ln.matched_reference) END AS credited
      FROM ln WHERE p_account = '1010' AND ln.ledger_journal IS NULL),
coll_lines AS (
    SELECT c.kind, coalesce(c.matched_reference, c.what) AS reference, c.d AS day,
           concat_ws(' · ', c.label || ', line ' || c.line_no, CASE WHEN c.matched_reference IS NOT NULL THEN c.what END,
                     CASE c.status WHEN 'DUPLICATE' THEN 'received twice' WHEN 'RECEIVED_NOT_CONFIRMED' THEN 'never confirmed'
                                   WHEN 'SETTLEMENT' THEN c.settlement_channel || ' of ' || to_char(c.settlement_day, 'FMDD FMMon YYYY') END) AS description,
           abs(a.amount) AS amount,
           CASE WHEN c.kind IN ('BANK_DEBIT_NOT_IN_LEDGER', 'GATEWAY_CHARGES') THEN a.amount ELSE -a.amount END AS effect,
           c.id AS line_id, NULL::bigint AS journal_no
      FROM coll_raw c
     CROSS JOIN LATERAL (SELECT CASE c.kind WHEN 'BANK_DEBIT_NOT_IN_LEDGER' THEN c.debit
                                            WHEN 'GATEWAY_CHARGES' THEN c.expected_amount - c.credit
                                            WHEN 'NELFUND_NOT_CREDITED' THEN c.credit - c.credited
                                            WHEN 'AMOUNT_DIFFERENCE' THEN c.credit - c.expected_amount
                                            ELSE c.credit END AS amount) a
     WHERE c.kind IS NOT NULL AND a.amount <> 0),
-- ── 1020: the journals not yet seen in the bank ──
disb_ledger AS (
    SELECT CASE WHEN jr.net < 0 THEN 'PAYOUT_NOT_IN_BANK' ELSE 'LEDGER_DEBIT_NOT_IN_BANK' END AS kind,
           coalesce(rf.reference, CASE WHEN w.id IS NOT NULL THEN 'WALLET/' || w.session || '/' || upper(left(w.id::text, 8)) END, jr.source_ref, '#' || jr.journal_no) AS reference,
           jr.entry_date AS day,
           concat_ws(' · ', jr.memo, coalesce(rf.paid_reference, w.paid_ref)) AS description,
           abs(jr.net) AS amount, jr.net AS effect, NULL::uuid AS line_id, jr.journal_no
      FROM jr
      LEFT JOIN finance.refund rf ON jr.source_type = 'REFUND' AND rf.reference = jr.source_ref
      LEFT JOIN finance.wallet_withdrawal w ON jr.wallet_entry IS NOT NULL AND w.entry_id = jr.wallet_entry
      LEFT JOIN expenditure.voucher v ON jr.source_type = 'VOUCHER' AND v.reference = jr.source_ref
     WHERE p_account = '1020'
       AND NOT EXISTS (SELECT 1 FROM booked b WHERE b.id = jr.id)
       AND NOT EXISTS (SELECT 1 FROM ln WHERE ln.status IN ('MATCHED', 'AMOUNT_DIFFERS') AND ln.matched_reference = upper(btrim(coalesce(rf.paid_reference, w.paid_ref))))
       -- a voucher paid, its reference in an otherwise unmatched debit of its amount
       AND NOT (v.id IS NOT NULL AND EXISTS (SELECT 1 FROM ln WHERE ln.status = 'UNMATCHED' AND ln.debit = v.amount AND position(upper(v.reference) IN ln.txt) > 0))),
-- ── 1020: the lines not yet on the ledger, or not wholly ──
disb_raw AS (
    SELECT ln.*,
           CASE WHEN ln.status = 'CREDIT' THEN 'BANK_CREDIT_NOT_IN_LEDGER'
                WHEN ln.status = 'UNMATCHED' AND NOT EXISTS (
                         SELECT 1 FROM expenditure.voucher v JOIN finance.gl_journal j ON j.source_type = 'VOUCHER' AND j.source_ref = v.reference AND j.entry_date <= p_to
                          WHERE v.stage = 'PAID' AND v.amount = ln.debit AND position(upper(v.reference) IN ln.txt) > 0) THEN 'BANK_DEBIT_NOT_IN_LEDGER'
                WHEN ln.status IN ('MATCHED', 'AMOUNT_DIFFERS') AND NOT EXISTS (SELECT 1 FROM payout_journal pj WHERE pj.ref = ln.matched_reference) THEN 'BANK_DEBIT_NOT_IN_LEDGER'
                WHEN ln.status = 'AMOUNT_DIFFERS' THEN 'AMOUNT_DIFFERENCE' END AS kind
      FROM ln WHERE p_account = '1020' AND ln.ledger_journal IS NULL),
disb_lines AS (
    SELECT c.kind, coalesce(c.matched_reference, c.what) AS reference, c.d AS day,
           concat_ws(' · ', c.label || ', line ' || c.line_no, CASE WHEN c.matched_reference IS NOT NULL THEN c.what END) AS description,
           abs(a.amount) AS amount, CASE WHEN c.kind = 'BANK_CREDIT_NOT_IN_LEDGER' THEN -a.amount ELSE a.amount END AS effect,
           c.id AS line_id, NULL::bigint AS journal_no
      FROM disb_raw c
     CROSS JOIN LATERAL (SELECT CASE c.kind WHEN 'BANK_CREDIT_NOT_IN_LEDGER' THEN c.credit
                                            WHEN 'AMOUNT_DIFFERENCE' THEN c.debit - c.expected_amount
                                            ELSE c.debit END AS amount) a
     WHERE c.kind IS NOT NULL AND a.amount <> 0)
SELECT * FROM coll_ledger UNION ALL SELECT * FROM coll_lines UNION ALL SELECT * FROM disb_ledger UNION ALL SELECT * FROM disb_lines
 ORDER BY 1, 3, 2
$fn$;
COMMENT ON FUNCTION finance.bank_reconciliation_items(text, date, date) IS
  'V557: every reconciling item of 1010 or 1020 at the end of a period, from the start of the account''s first reconciliation — on the ledger and not yet in the bank, in the bank and not on the ledger, a difference, a gateway''s charges — with its effect on the bank''s balance (+ the ledger holds more).';

/* what waits to be posted on the ledger and belongs to a day up to the end of the period */
CREATE FUNCTION finance.gl_unposted_until(p_to date)
RETURNS bigint LANGUAGE sql STABLE AS $fn$
    SELECT (SELECT count(*) FROM finance.payment_reference pr
             WHERE pr.confirmed_at IS NOT NULL AND pr.confirmed_at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference))
         + (SELECT count(*) FROM reporting.payments v
             WHERE v.source <> 'STUDENT' AND v.confirmed_at IS NOT NULL AND v.amount > 0 AND v.confirmed_at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = v.reference))
         + (SELECT count(*) FROM finance.refund rf
             WHERE rf.state = 'PAID' AND rf.paid_at IS NOT NULL AND coalesce(rf.paid_on, rf.paid_at::date) <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'REFUND' AND j.source_ref = rf.reference))
         + (SELECT count(*) FROM expenditure.voucher v
             WHERE v.stage = 'PAID' AND v.paid_at IS NOT NULL AND v.paid_at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference))
         + (SELECT count(*) FROM finance.wallet_entry e
             WHERE e.recorded_at IS NOT NULL AND e.kind IN ('CREDIT', 'REVERSED', 'REFUND') AND e.at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || e.id))
$fn$;
COMMENT ON FUNCTION finance.gl_unposted_until(date) IS
  'V557: the transactions of a day up to the given one that the ledger has not posted yet (finance.gl_unposted''s, by date) — a reconciliation is signed only once there are none.';

/* the reconciliation statement worked out: the balances, the items by kind, the difference left, and what stands in the way of
   signing it */
CREATE FUNCTION finance.bank_reconciliation_figures(p_account text, p_from date, p_to date, p_closing numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_kind text := CASE p_account WHEN '1010' THEN 'COLLECTIONS' WHEN '1020' THEN 'DISBURSEMENT' END;
        v_ledger numeric; v_effect numeric; v_summary jsonb; v_statements jsonb; v_missing int; v_ranges text; v_start date;
BEGIN
    IF v_kind IS NULL THEN RAISE EXCEPTION 'RECON_ACCOUNT: a bank reconciliation is of 1010 or 1020' USING ERRCODE = '23514'; END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION 'RECON_PERIOD: give the first and the last day of the period' USING ERRCODE = '23514'; END IF;
    v_start := finance.bank_reconciliation_start(p_account, p_from);
    SELECT coalesce(sum(p.debit - p.credit), 0) INTO v_ledger
      FROM finance.gl_posting p JOIN finance.gl_journal j ON j.id = p.journal_id WHERE p.account = p_account AND j.entry_date <= p_to;
    SELECT coalesce(jsonb_agg(jsonb_build_object('kind', s.kind, 'items', s.n, 'amount', s.amount, 'effect', s.effect) ORDER BY s.kind), '[]'::jsonb),
           coalesce(sum(s.effect), 0)
      INTO v_summary, v_effect
      FROM (SELECT i.kind, count(*) AS n, sum(i.amount) AS amount, sum(i.effect) AS effect
              FROM finance.bank_reconciliation_items(p_account, p_from, p_to) i GROUP BY i.kind) s;
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'period_from', s.period_from, 'period_to', s.period_to, 'lines', s.lines)
                              ORDER BY s.period_from, s.uploaded_at), '[]'::jsonb)
      INTO v_statements
      FROM finance.bank_statement s
     WHERE s.account_kind = v_kind AND s.period_from <= p_to AND s.period_to >= p_from;
    -- the days of the period no statement of the account covers, as runs of days
    WITH d AS (SELECT g::date AS day FROM generate_series(p_from, p_to, interval '1 day') g
                WHERE NOT EXISTS (SELECT 1 FROM finance.bank_statement s WHERE s.account_kind = v_kind AND g::date BETWEEN s.period_from AND s.period_to)),
         r AS (SELECT min(day) AS a, max(day) AS b FROM (SELECT day, day - (row_number() OVER (ORDER BY day))::int AS grp FROM d) x GROUP BY grp)
    SELECT (SELECT count(*) FROM d)::int,
           string_agg(CASE WHEN a = b THEN to_char(a, 'FMDD FMMon YYYY') ELSE to_char(a, 'FMDD FMMon') || '–' || to_char(b, 'FMDD FMMon YYYY') END, ', ' ORDER BY a)
      INTO v_missing, v_ranges FROM r;
    RETURN jsonb_build_object(
        'account', p_account, 'account_name', (SELECT a.name FROM finance.gl_account a WHERE a.code = p_account),
        'period_from', p_from, 'period_to', p_to, 'items_from', v_start,
        'statement_closing', p_closing, 'ledger_balance', v_ledger, 'items_effect', v_effect,
        'adjusted_bank', CASE WHEN p_closing IS NULL THEN NULL ELSE p_closing + v_effect END,
        'difference', CASE WHEN p_closing IS NULL THEN NULL ELSE v_ledger - (p_closing + v_effect) END,
        'summary', v_summary, 'statements', v_statements, 'missing_days', v_missing, 'missing', v_ranges,
        'unposted', finance.gl_unposted_until(p_to),
        'period_ended', p_to < (now() AT TIME ZONE 'Africa/Lagos')::date);
END $fn$;
COMMENT ON FUNCTION finance.bank_reconciliation_figures(text, date, date, numeric) IS
  'V557: the bank reconciliation statement of 1010 or 1020 for a period worked out — the statement''s closing balance, the ledger''s balance at the end of the period, the reconciling items by kind and their effect, the difference left, the statements that cover the period and the days none covers, and what waits to be posted.';

/* the Bursary prepares the reconciliation of a period with the closing balance on the bank's statement (again, while unsigned) */
CREATE FUNCTION finance.prepare_bank_reconciliation(p_account text, p_from date, p_to date, p_closing numeric, p_note text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; f jsonb; v_id uuid; o finance.bank_reconciliation;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a reconciliation is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF p_closing IS NULL THEN RAISE EXCEPTION 'RECON_CLOSING: give the closing balance on the bank''s statement at the end of the period' USING ERRCODE = '23514'; END IF;
    f := finance.bank_reconciliation_figures(p_account, p_from, p_to, round(p_closing, 2));
    SELECT * INTO o FROM finance.bank_reconciliation r
     WHERE r.account = p_account AND daterange(r.period_from, r.period_to, '[]') && daterange(p_from, p_to, '[]') FOR UPDATE;
    IF o.id IS NOT NULL AND (o.state = 'SIGNED' OR o.period_from <> p_from OR o.period_to <> p_to) THEN
        RAISE EXCEPTION 'RECON_PERIOD_TAKEN: % already has a % reconciliation for % to %', p_account, lower(o.state),
            to_char(o.period_from, 'FMDD FMMonth YYYY'), to_char(o.period_to, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    IF o.id IS NULL THEN
        INSERT INTO finance.bank_reconciliation (account, period_from, period_to, statement_closing, ledger_balance, items_effect, difference, summary, note, prepared_by)
        VALUES (p_account, p_from, p_to, round(p_closing, 2), (f->>'ledger_balance')::numeric, (f->>'items_effect')::numeric, (f->>'difference')::numeric,
                f - 'statements', nullif(btrim(coalesce(p_note, '')), ''), v_actor)
        RETURNING id INTO v_id;
    ELSE
        UPDATE finance.bank_reconciliation SET statement_closing = round(p_closing, 2), ledger_balance = (f->>'ledger_balance')::numeric,
               items_effect = (f->>'items_effect')::numeric, difference = (f->>'difference')::numeric, summary = f - 'statements',
               note = nullif(btrim(coalesce(p_note, '')), ''), prepared_by = v_actor, prepared_at = now()
         WHERE id = o.id RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION finance.prepare_bank_reconciliation(text, date, date, numeric, text) IS
  'V557: the Bursary''s reconciliation of 1010 or 1020 for a period, with the closing balance on the bank''s statement — prepared, or prepared again while unsigned; a period overlapping another reconciliation of the account is refused.';

/* another officer signs it: the period has ended, the statements cover it, the ledger holds all of it, any difference is explained */
CREATE FUNCTION finance.sign_bank_reconciliation(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r finance.bank_reconciliation; f jsonb; v_items jsonb;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a reconciliation is signed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.bank_reconciliation WHERE id = p_id FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no reconciliation %', p_id USING ERRCODE = 'P0002'; END IF;
    IF r.state = 'SIGNED' THEN RAISE EXCEPTION 'RECON_SIGNED: the reconciliation is signed already' USING ERRCODE = '23514'; END IF;
    IF r.prepared_by = v_actor THEN
        RAISE EXCEPTION 'RECON_SAME_OFFICER: the officer who prepared the reconciliation does not sign it' USING ERRCODE = '23514',
            HINT = 'Another officer of the Bursary signs it.';
    END IF;
    f := finance.bank_reconciliation_figures(r.account, r.period_from, r.period_to, r.statement_closing);
    IF NOT (f->>'period_ended')::boolean THEN
        RAISE EXCEPTION 'RECON_PERIOD_OPEN: the period ends on %; it is signed once it has ended', to_char(r.period_to, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    IF (f->>'missing_days')::int > 0 THEN
        RAISE EXCEPTION 'RECON_STATEMENT_GAP: no bank statement of the account covers %', f->>'missing' USING ERRCODE = '23514',
            HINT = 'Upload the statement for those days first.';
    END IF;
    IF (f->>'unposted')::bigint > 0 THEN
        RAISE EXCEPTION 'RECON_LEDGER_NOT_POSTED: % transaction(s) of the period wait to be posted on the ledger', f->>'unposted' USING ERRCODE = '23514',
            HINT = 'Post them on Accounting first.';
    END IF;
    IF (f->>'difference')::numeric <> 0 AND btrim(coalesce(r.note, '')) = '' THEN
        RAISE EXCEPTION 'RECON_DIFFERENCE_UNEXPLAINED: NGN % is left unexplained; say why in the note before it is signed', to_char((f->>'difference')::numeric, 'FM999,999,999,990.00')
            USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.kind, i.day, i.reference), '[]'::jsonb) INTO v_items
      FROM finance.bank_reconciliation_items(r.account, r.period_from, r.period_to) i;
    UPDATE finance.bank_reconciliation SET ledger_balance = (f->>'ledger_balance')::numeric, items_effect = (f->>'items_effect')::numeric,
           difference = (f->>'difference')::numeric, summary = f - 'statements', items = v_items, state = 'SIGNED', signed_by = v_actor, signed_at = now()
     WHERE id = r.id;
    RETURN f;
END $fn$;
COMMENT ON FUNCTION finance.sign_bank_reconciliation(uuid) IS
  'V557: a prepared reconciliation signed by an officer other than its preparer — once the period has ended, the account''s statements cover every day of it, nothing of it waits to be posted and any difference is explained in the note; it is then kept with its items as signed.';

/* the Bursary accounts for a statement line with a journal (or takes it back): the line and the journal are no item then */
CREATE FUNCTION finance.book_statement_line(p_line uuid, p_journal_no bigint, p_note text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; l finance.bank_statement_line; s finance.bank_statement;
        j finance.gl_journal; v_account text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a line is accounted for by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = p_line FOR UPDATE;
    IF l.id IS NULL THEN RAISE EXCEPTION 'no statement line %', p_line USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    v_account := finance.bank_account_of(s.account_kind);
    IF EXISTS (SELECT 1 FROM finance.bank_reconciliation r WHERE r.account = v_account AND r.state = 'SIGNED'
                AND coalesce(l.value_date, s.period_to) BETWEEN r.period_from AND r.period_to) THEN
        RAISE EXCEPTION 'RECON_SIGNED_PERIOD: line % falls in a signed reconciliation of %', l.line_no, v_account USING ERRCODE = '23514';
    END IF;
    IF p_journal_no IS NULL THEN
        UPDATE finance.bank_statement_line SET ledger_journal = NULL, booked_by = NULL, booked_at = NULL, booked_note = NULL WHERE id = l.id;
        RETURN;
    END IF;
    IF l.status IN ('MATCHED', 'RECEIVED_NOT_CONFIRMED') THEN
        RAISE EXCEPTION 'LINE_NOT_FOR_JOURNAL: a line matched to the portal, or one the portal is to confirm, is not accounted for with a journal' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_note, '')) = '' THEN RAISE EXCEPTION 'LINE_JOURNAL_NOTE: say what the journal records for the line' USING ERRCODE = '23514'; END IF;
    SELECT * INTO j FROM finance.gl_journal WHERE journal_no = p_journal_no;
    IF j.id IS NULL OR j.status <> 'POSTED' THEN
        RAISE EXCEPTION 'LINE_JOURNAL: journal #% is not a posted journal', p_journal_no USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.gl_posting p WHERE p.journal_id = j.id AND p.account = v_account) THEN
        RAISE EXCEPTION 'LINE_JOURNAL_ACCOUNT: journal #% does not move %, the account of this statement', p_journal_no, v_account USING ERRCODE = '23514';
    END IF;
    UPDATE finance.bank_statement_line SET ledger_journal = j.id, booked_by = v_actor, booked_at = now(), booked_note = btrim(p_note) WHERE id = l.id;
END $fn$;
COMMENT ON FUNCTION finance.book_statement_line(uuid, bigint, text) IS
  'V557: a statement line accounted for with a posted journal moving the statement''s account (bank charges, a transfer between the accounts, a difference put right), or taken back with no journal — never a line in a signed reconciliation.';

COMMIT;
