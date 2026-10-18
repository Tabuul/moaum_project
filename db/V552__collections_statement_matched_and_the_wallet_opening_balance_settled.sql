-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V552 — The collections account's statement matched to what was received; the wallet's opening balance settled
--
--   1 · V545 matched the disbursement account's statement to what was paid out. The collections account's statement is matched now
--       to what was received (finance.load_collections_statement): each credit by a portal reference found in its reference or
--       narration (written with or without its hyphens) — a payment the portal confirmed with the same amount: MATCHED (and its reconciliation recorded
--       MATCHED, V068); another amount: AMOUNT_DIFFERS (recorded a DISCREPANCY); a reference the portal issued and never
--       confirmed: RECEIVED_NOT_CONFIRMED — a student who paid and may still be blocked, sent to the Bursary as a bank credit proposed
--       against that reference (finance.collections_line_to_bank_credit), which a second officer approves (V037); a NELFUND
--       remittance by its reference or its amount within seven days: MATCHED; a reference credited twice in one statement: DUPLICATE.
--       The payments confirmed in the period that no line found and no one reconciled are listed — confirmed on the portal, not in
--       the bank (finance.collections_not_received) — and, as a gateway settles in one sum for many payments, by channel and day
--       (finance.collections_unmatched): a credit is marked the settlement of a channel's day (finance.settle_collections_line), the
--       difference shown as charges and each payment of the day reconciled. Payments that never pass through the bank (the old portal's, a migration, the wallet
--       applied, an overpayment carried) are not looked for on the statement (finance.receipt_through_bank).
--   2 · V545 opened what students held in their wallets against 3900 Opening balance / suspense. finance.wallet_opening_breakdown
--       shows it by source and session with the account each part belongs in (a loan such as NELFUND: the bank, its money never
--       booked; a grant: Grants, research & scholarships; own top-ups: Other income, where a top-up was booked before; a credit
--       with no source: the Bursary names it), and finance.reclassify_wallet_opening posts the Bursary's reclassification out of
--       suspense, never more than remains in it.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V552: the collections statement matched; the wallet opening balance settled', true);

-- ── 1 · the collections account's statement ──────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.bank_statement ADD COLUMN account_kind text NOT NULL DEFAULT 'DISBURSEMENT' CHECK (account_kind IN ('DISBURSEMENT', 'COLLECTIONS'));
COMMENT ON COLUMN finance.bank_statement.account_kind IS 'V552: DISBURSEMENT (matched to what was paid out, V545) or COLLECTIONS (matched to what was received).';

ALTER TABLE finance.bank_statement_line DROP CONSTRAINT bank_statement_line_status_check;
ALTER TABLE finance.bank_statement_line
    ADD CONSTRAINT ck_bsl_status CHECK (status IN ('MATCHED', 'AMOUNT_DIFFERS', 'UNMATCHED', 'CREDIT', 'DEBIT', 'RECEIVED_NOT_CONFIRMED', 'DUPLICATE', 'SETTLEMENT')),
    ADD COLUMN matched_kind text NULL CHECK (matched_kind IS NULL OR matched_kind IN ('PAYOUT', 'PAYMENT', 'NELFUND', 'SETTLEMENT')),
    ADD COLUMN settlement_channel text NULL,
    ADD COLUMN settlement_day date NULL,
    ADD COLUMN settled_by uuid NULL,
    ADD COLUMN settled_at timestamptz NULL,
    ADD COLUMN bank_credit_id uuid NULL REFERENCES finance.bank_credit(id) ON DELETE SET NULL;
UPDATE finance.bank_statement_line SET matched_kind = 'PAYOUT' WHERE status IN ('MATCHED', 'AMOUNT_DIFFERS') AND matched_kind IS NULL;
COMMENT ON COLUMN finance.bank_statement_line.matched_kind IS
  'V552: what a line matched — PAYOUT (a refund or withdrawal, V545), PAYMENT (a payment the portal confirmed or issued), NELFUND (a remittance), SETTLEMENT (a gateway''s sum for a channel''s day).';

/* whether a confirmed payment's money passes through the collections account: not the old portal's, a migration, the wallet applied,
   an overpayment carried, nor the demo's */
CREATE FUNCTION finance.receipt_through_bank(p_channel text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT NOT (coalesce(p_channel, '') ~* '(legacy|migration|old.portal|nelfund wallet|^carried$|^demo)')
$fn$;
COMMENT ON FUNCTION finance.receipt_through_bank(text) IS
  'V552: false for a payment whose money never passes through the collections account — the old portal''s history, a migration, the wallet applied to fees, an overpayment carried, the demo''s.';

/* the collections statement uploaded: [{date, description, reference, debit, credit}] — each credit matched */
CREATE FUNCTION finance.load_collections_statement(p_label text, p_file text, p_rows jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; r jsonb; i int := 0; v_text text; v_debit numeric; v_credit numeric; v_date date; v_status text; v_kind text;
        v_ref text; v_amount numeric; v_confirmed boolean; v_min date; v_max date; v_line uuid; v_seen text[] := '{}';
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a statement is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_label, '')) = '' THEN
        RAISE EXCEPTION 'STATEMENT_LABEL: name the statement (the account and the period)' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'STATEMENT_EMPTY: the statement has no lines' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 20000 THEN
        RAISE EXCEPTION 'STATEMENT_TOO_LONG: a statement of up to 20,000 lines at a time' USING ERRCODE = '23514';
    END IF;
    SELECT min((x->>'date')::date), max((x->>'date')::date) INTO v_min, v_max
      FROM jsonb_array_elements(p_rows) x WHERE coalesce(x->>'date', '') ~ '^\d{4}-\d{2}-\d{2}$';
    INSERT INTO finance.bank_statement (label, file_name, uploaded_by, uploaded_office, account_kind)
    VALUES (btrim(p_label), nullif(btrim(coalesce(p_file, '')), ''), v_actor, nullif(current_setting('moaum.actor_office', true), ''), 'COLLECTIONS')
    RETURNING id INTO v_id;
    -- every reference the portal issued around the statement's dates, unconfirmed or confirmed through the bank, as a bank may write it
    -- (with or without its hyphens)
    CREATE TEMP TABLE IF NOT EXISTS pg_temp.collection_key (token text, reference text, amount numeric, confirmed boolean) ON COMMIT DROP;
    DELETE FROM pg_temp.collection_key;
    INSERT INTO pg_temp.collection_key
    SELECT DISTINCT ON (k.token) k.token, k.reference, k.amount, k.confirmed
      FROM (SELECT regexp_replace(upper(p.reference), '[^A-Z0-9]', '', 'g') AS token, upper(p.reference) AS reference, p.amount,
                   p.confirmed_at IS NOT NULL AS confirmed, p.confirmed_at
              FROM reporting.payments p
             WHERE p.generated_at >= coalesce(v_min, v_today) - 180 AND p.generated_at < coalesce(v_max, v_today) + 2
               AND (p.confirmed_at IS NULL OR finance.receipt_through_bank(p.channel))) k
     WHERE length(k.token) >= 8
     ORDER BY k.token, k.confirmed DESC, k.confirmed_at DESC NULLS LAST;
    CREATE INDEX IF NOT EXISTS ix_pg_temp_collection_key ON pg_temp.collection_key (token);
    ANALYZE pg_temp.collection_key;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        i := i + 1;
        v_debit := round(abs(coalesce(nullif(regexp_replace(coalesce(r->>'debit', ''), '[^0-9.]', '', 'g'), '')::numeric, 0)), 2);
        v_credit := round(abs(coalesce(nullif(regexp_replace(coalesce(r->>'credit', ''), '[^0-9.]', '', 'g'), '')::numeric, 0)), 2);
        v_date := CASE WHEN coalesce(r->>'date', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (r->>'date')::date END;
        v_text := upper(coalesce(r->>'reference', '') || ' ' || coalesce(r->>'description', ''));
        v_ref := NULL; v_amount := NULL; v_confirmed := NULL; v_kind := NULL; v_status := 'DEBIT';
        IF v_credit > 0 THEN
            -- the words of the line, and any portal reference written into one (TRF/MOAUM-FEE-123456-1234/…, MOAUMFEE1234561234)
            SELECT k.reference, k.amount, k.confirmed INTO v_ref, v_amount, v_confirmed
              FROM (SELECT regexp_replace(t, '[^A-Z0-9]', '', 'g') AS t FROM unnest(regexp_split_to_array(v_text, '[^A-Z0-9-]+')) t
                    UNION
                    SELECT regexp_replace(m[1], '[^A-Z0-9]', '', 'g') FROM regexp_matches(v_text, '(MOAUM[-_ /]?[A-Z]{2,6}[-_ /]?[0-9]{6}(?:[-_ /]?[0-9]{4})?)', 'g') m) w
              JOIN pg_temp.collection_key k ON k.token = w.t
             ORDER BY k.confirmed DESC, length(w.t) DESC LIMIT 1;
            IF v_ref IS NOT NULL THEN
                v_kind := 'PAYMENT';
                v_status := CASE WHEN v_ref = ANY (v_seen) THEN 'DUPLICATE' WHEN NOT v_confirmed THEN 'RECEIVED_NOT_CONFIRMED'
                                 WHEN v_amount = v_credit THEN 'MATCHED' ELSE 'AMOUNT_DIFFERS' END;
                v_seen := v_seen || v_ref;
            ELSE
                -- a NELFUND remittance: its reference in the line, or its amount within seven days
                SELECT b.ref, b.amount INTO v_ref, v_amount FROM finance.nelfund_batch b
                 WHERE (length(b.ref) >= 4 AND position(upper(b.ref) IN v_text) > 0)
                    OR (b.amount = v_credit AND v_date IS NOT NULL AND abs(b.received_on - v_date) <= 7)
                 ORDER BY (position(upper(b.ref) IN v_text) > 0) DESC, abs(b.received_on - coalesce(v_date, b.received_on)) LIMIT 1;
                IF v_ref IS NOT NULL THEN
                    v_kind := 'NELFUND';
                    v_status := CASE WHEN v_amount = v_credit THEN 'MATCHED' ELSE 'AMOUNT_DIFFERS' END;
                ELSE
                    v_status := 'UNMATCHED';
                END IF;
            END IF;
        END IF;
        INSERT INTO finance.bank_statement_line (statement_id, line_no, value_date, description, reference, debit, credit, status,
                                                 matched_reference, expected_amount, matched_payouts, matched_kind)
        VALUES (v_id, i, v_date, nullif(btrim(coalesce(r->>'description', '')), ''), nullif(btrim(coalesce(r->>'reference', '')), ''), v_debit, v_credit, v_status,
                v_ref, v_amount, CASE WHEN v_status = 'MATCHED' THEN 1 ELSE 0 END, v_kind)
        RETURNING id INTO v_line;
        -- the reconciliation of a confirmed payment (V068), recorded once by the matching
        IF v_kind = 'PAYMENT' AND v_status IN ('MATCHED', 'AMOUNT_DIFFERS')
           AND NOT EXISTS (SELECT 1 FROM finance.payment_reconciliation pr WHERE pr.reference = v_ref AND pr.result = 'MATCHED') THEN
            INSERT INTO finance.payment_reconciliation (reference, result, bank_reference, note, checked_by)
            VALUES (v_ref, CASE WHEN v_status = 'MATCHED' THEN 'MATCHED' ELSE 'DISCREPANCY' END,
                    coalesce(nullif(btrim(coalesce(r->>'reference', '')), ''), 'line ' || i),
                    'Collections statement ' || btrim(p_label) || ', line ' || i
                        || CASE WHEN v_status = 'AMOUNT_DIFFERS' THEN ': the statement shows NGN ' || to_char(v_credit, 'FM999,999,999,990.00') || ', the portal confirmed NGN ' || to_char(v_amount, 'FM999,999,999,990.00') ELSE '' END,
                    v_actor);
        END IF;
    END LOOP;
    UPDATE finance.bank_statement s SET lines = i, period_from = v_min, period_to = v_max WHERE s.id = v_id;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION finance.load_collections_statement(text, text, jsonb) IS
  'V552: the collections account''s statement uploaded and each credit matched to what was received — a confirmed payment (reconciled), a reference never confirmed, a NELFUND remittance — or left for a gateway''s settlement; returns the statement.';

/* the payments confirmed in a statement's period, through the bank, that no collections line found — neither one by one nor in a day's
   settlement — and no one has reconciled (V068) */
CREATE FUNCTION finance.collections_not_received(p_statement uuid)
RETURNS TABLE (reference text, channel text, day date, amount numeric, purpose text, payer text, number text, confirmed_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT period_from, period_to FROM finance.bank_statement WHERE id = p_statement AND account_kind = 'COLLECTIONS'),
    found AS (
        SELECT DISTINCT l.matched_reference AS ref FROM finance.bank_statement_line l JOIN finance.bank_statement b ON b.id = l.statement_id
         WHERE b.account_kind = 'COLLECTIONS' AND l.matched_kind = 'PAYMENT' AND l.matched_reference IS NOT NULL),
    settled AS (
        SELECT DISTINCT l.settlement_channel, l.settlement_day FROM finance.bank_statement_line l JOIN finance.bank_statement b ON b.id = l.statement_id
         WHERE b.account_kind = 'COLLECTIONS' AND l.status = 'SETTLEMENT')
    SELECT p.reference, p.channel, (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, p.amount, p.purpose,
           nullif(btrim(coalesce(p.surname, '') || ' ' || coalesce(p.other_names, '')), ''), p.number, p.confirmed_at
      FROM reporting.payments p CROSS JOIN s
     WHERE p.confirmed_at IS NOT NULL AND p.amount > 0 AND finance.receipt_through_bank(p.channel)
       AND p.confirmed_at >= (s.period_from::timestamp AT TIME ZONE 'Africa/Lagos') AND p.confirmed_at < ((s.period_to + 1)::timestamp AT TIME ZONE 'Africa/Lagos')
       AND NOT EXISTS (SELECT 1 FROM found f WHERE f.ref = upper(p.reference))
       AND NOT EXISTS (SELECT 1 FROM settled x WHERE x.settlement_channel = p.channel AND x.settlement_day = (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date)
       AND NOT EXISTS (SELECT 1 FROM finance.payment_reconciliation pr WHERE pr.reference = upper(p.reference) AND pr.result = 'MATCHED')
     ORDER BY 3, 2, p.confirmed_at
$fn$;
COMMENT ON FUNCTION finance.collections_not_received(uuid) IS
  'V552: the payments confirmed in a collections statement''s period, through the bank, that no line found (one by one or as a day''s settlement) and no one has reconciled — confirmed on the portal, not seen in the bank.';

/* the same by channel and day, the totals a gateway's settlement is compared with */
CREATE FUNCTION finance.collections_unmatched(p_statement uuid)
RETURNS TABLE (channel text, day date, payments int, total numeric)
LANGUAGE sql STABLE AS $fn$
    SELECT n.channel, n.day, count(*)::int, sum(n.amount) FROM finance.collections_not_received(p_statement) n GROUP BY 1, 2 ORDER BY 2, 1
$fn$;
COMMENT ON FUNCTION finance.collections_unmatched(uuid) IS
  'V552: finance.collections_not_received by channel and day — what a gateway''s one credit for a day is compared with.';

/* a credit marked the settlement of a channel's day: each payment of the day reconciled against it, the difference shown */
CREATE FUNCTION finance.settle_collections_line(p_line uuid, p_channel text, p_day date)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE l finance.bank_statement_line; s finance.bank_statement; v_n int; v_total numeric; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a settlement is marked by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = p_line FOR UPDATE;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    IF l.id IS NULL OR s.account_kind <> 'COLLECTIONS' OR l.credit <= 0 OR l.status <> 'UNMATCHED' THEN
        RAISE EXCEPTION 'SETTLEMENT_LINE: only an unmatched credit of a collections statement is marked a settlement' USING ERRCODE = '23514';
    END IF;
    SELECT u.payments, u.total INTO v_n, v_total FROM finance.collections_unmatched(s.id) u WHERE u.channel = p_channel AND u.day = p_day;
    IF v_n IS NULL THEN
        RAISE EXCEPTION 'SETTLEMENT_DAY: no unmatched payment by % on % in this statement''s period', p_channel, to_char(p_day, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    -- each payment of the day reconciled against the line (before the line is marked, while the day is still unmatched)
    INSERT INTO finance.payment_reconciliation (reference, result, bank_reference, note, checked_by)
    SELECT upper(n.reference), 'MATCHED', coalesce(l.reference, 'line ' || l.line_no),
           'Settled in the collections statement ' || s.label || ', line ' || l.line_no || ', with the ' || p_channel || ' payments of ' || to_char(p_day, 'FMDD FMMonth YYYY')
               || ' (' || v_n || ' for NGN ' || to_char(v_total, 'FM999,999,999,990.00') || '; credited NGN ' || to_char(l.credit, 'FM999,999,999,990.00') || ')',
           v_actor
      FROM finance.collections_not_received(s.id) n WHERE n.channel = p_channel AND n.day = p_day;
    UPDATE finance.bank_statement_line SET status = 'SETTLEMENT', matched_kind = 'SETTLEMENT', settlement_channel = p_channel, settlement_day = p_day,
           expected_amount = v_total, matched_payouts = v_n, matched_reference = NULL, settled_by = v_actor, settled_at = now()
     WHERE id = l.id;
    RETURN jsonb_build_object('payments', v_n, 'total', v_total, 'credited', l.credit, 'difference', v_total - l.credit);
END $fn$;
COMMENT ON FUNCTION finance.settle_collections_line(uuid, text, date) IS
  'V552: an unmatched credit of a collections statement marked the settlement of a channel''s day — every confirmed payment of the day reconciled against it, the difference (the gateway''s charges) returned.';

/* a credit for a reference the portal issued and never confirmed: a bank credit recorded and proposed against it (V037), for a second
   officer to approve */
CREATE FUNCTION finance.collections_line_to_bank_credit(p_line uuid)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE l finance.bank_statement_line; s finance.bank_statement; v_credit uuid;
BEGIN
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = p_line FOR UPDATE;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    IF l.id IS NULL OR s.account_kind <> 'COLLECTIONS' OR l.status <> 'RECEIVED_NOT_CONFIRMED' THEN
        RAISE EXCEPTION 'STATEMENT_LINE_NOT_UNCONFIRMED: only a credit for a reference the portal never confirmed goes to the bank credits' USING ERRCODE = '23514';
    END IF;
    IF l.bank_credit_id IS NOT NULL THEN
        RAISE EXCEPTION 'STATEMENT_LINE_SENT: line % is already a bank credit', l.line_no USING ERRCODE = '23514';
    END IF;
    v_credit := finance.record_bank_credit(coalesce(l.value_date, (now() AT TIME ZONE 'Africa/Lagos')::date), s.label, 'Statement line ' || l.line_no || coalesce(' · ' || l.reference, ''),
                                           l.credit, NULL, 'From the collections statement ' || s.label || coalesce(': ' || l.description, ''));
    PERFORM finance.propose_bank_credit(v_credit, l.matched_reference,
        'On the collections statement ' || s.label || ', line ' || l.line_no || ', with the reference ' || l.matched_reference || ' the portal issued and never confirmed');
    UPDATE finance.bank_statement_line SET bank_credit_id = v_credit WHERE id = l.id;
    RETURN v_credit;
END $fn$;
COMMENT ON FUNCTION finance.collections_line_to_bank_credit(uuid) IS
  'V552: a collections credit for a reference the portal issued and never confirmed, recorded as a bank credit and proposed against that reference; a second officer approves it on the bank credits (V037).';

-- ── 2 · the wallet's opening balance settled ─────────────────────────────────────────────────────────────────────────────
/* what students held when the wallet came onto the ledger, by source and session, with the account each part belongs in */
CREATE FUNCTION finance.wallet_opening_breakdown()
RETURNS TABLE (source_code text, source_name text, nature text, session text, amount numeric, suggested_account text)
LANGUAGE sql STABLE AS $fn$
    SELECT x.src, coalesce(fs.name, 'Unattributed credit'), coalesce(fs.nature, 'UNKNOWN'), x.session, x.amount,
           CASE fs.nature WHEN 'LOAN' THEN '1010' WHEN 'GRANT' THEN '5240' WHEN 'SELF' THEN '4090' END
      FROM (SELECT coalesce(e.source_code, 'UNATTRIBUTED') AS src, e.session,
                   sum(CASE WHEN e.kind IN ('CREDIT', 'TOPUP') THEN e.amount ELSE -e.amount END) AS amount
              FROM finance.wallet_entry e WHERE e.recorded_at IS NULL
             GROUP BY 1, 2) x
      LEFT JOIN finance.funding_source fs ON fs.code = x.src
     WHERE x.amount <> 0
     ORDER BY CASE coalesce(fs.nature, 'UNKNOWN') WHEN 'LOAN' THEN 0 WHEN 'GRANT' THEN 1 WHEN 'SELF' THEN 2 ELSE 3 END, x.src, x.session
$fn$;
COMMENT ON FUNCTION finance.wallet_opening_breakdown() IS
  'V552: the wallet''s opening balance (V545) by source and session, with the account each part belongs in — a loan (NELFUND) the bank, its money never booked; a grant Grants, research & scholarships; own top-ups Other income, where a top-up was booked; a credit with no source is left for the Bursary to name.';

/* where the opening balance stands: posted, reclassified so far, remaining in suspense */
CREATE FUNCTION finance.wallet_opening_state()
RETURNS TABLE (posted numeric, reclassified numeric, remaining numeric, opening_date date)
LANGUAGE sql STABLE AS $fn$
    WITH o AS (SELECT j.entry_date, coalesce(sum(p.credit) FILTER (WHERE p.account = '2100'), 0) - coalesce(sum(p.debit) FILTER (WHERE p.account = '2100'), 0) AS amt
                 FROM finance.gl_journal j JOIN finance.gl_posting p ON p.journal_id = j.id
                WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-OPENING' AND j.status = 'POSTED' GROUP BY j.entry_date),
    r AS (SELECT coalesce(sum(p.credit) FILTER (WHERE p.account = '3900'), 0) AS amt
            FROM finance.gl_journal j JOIN finance.gl_posting p ON p.journal_id = j.id
           WHERE j.source_type = 'WALLET' AND j.source_ref LIKE 'WALLET-OPENING-RECLASS-%' AND j.status = 'POSTED')
    SELECT coalesce((SELECT amt FROM o), 0), (SELECT amt FROM r), coalesce((SELECT amt FROM o), 0) - (SELECT amt FROM r), (SELECT entry_date FROM o)
$fn$;
COMMENT ON FUNCTION finance.wallet_opening_state() IS
  'V552: the wallet''s opening balance on the ledger (WALLET-OPENING), what reclassification journals still posted have moved out of suspense, and what remains.';

/* the Bursary's reclassification out of suspense: [{account, amount, narration}] — Dr each account, Cr 3900 */
CREATE FUNCTION finance.reclassify_wallet_opening(p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE st record; v_total numeric := 0; x jsonb; v_lines jsonb := '[]'::jsonb; v_n int; v_account text; v_amount numeric;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN RAISE EXCEPTION 'a journal is posted by a person' USING ERRCODE = '23514'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('finance.wallet_opening_reclass'));
    SELECT * INTO st FROM finance.wallet_opening_state();
    IF st.posted <= 0 THEN
        RAISE EXCEPTION 'WALLET_OPENING_NOT_POSTED: the wallet''s opening balance is not on the ledger yet' USING ERRCODE = '23514',
            HINT = 'Post what is waiting on the ledger first (Accounting, Post them now).';
    END IF;
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'WALLET_RECLASS_EMPTY: name at least one account and amount' USING ERRCODE = '23514';
    END IF;
    FOR x IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        v_account := btrim(coalesce(x->>'account', ''));
        v_amount := round(coalesce((x->>'amount')::numeric, 0), 2);
        IF v_amount <= 0 THEN CONTINUE; END IF;
        IF v_account IN ('2100', '3900') OR NOT EXISTS (SELECT 1 FROM finance.gl_account a WHERE a.code = v_account AND a.postable AND a.active) THEN
            RAISE EXCEPTION 'WALLET_RECLASS_ACCOUNT: % is not an account the opening balance is reclassified to', v_account USING ERRCODE = '23514';
        END IF;
        v_total := v_total + v_amount;
        v_lines := v_lines || jsonb_build_object('account', v_account, 'debit', v_amount,
                                                 'narration', coalesce(nullif(btrim(coalesce(x->>'narration', '')), ''), 'Wallet opening balance reclassified'));
    END LOOP;
    IF v_total <= 0 THEN RAISE EXCEPTION 'WALLET_RECLASS_EMPTY: name at least one account and amount' USING ERRCODE = '23514'; END IF;
    IF v_total > st.remaining THEN
        RAISE EXCEPTION 'WALLET_RECLASS_TOO_MUCH: NGN % is more than the NGN % still in suspense', to_char(v_total, 'FM999,999,999,990.00'), to_char(st.remaining, 'FM999,999,999,990.00')
            USING ERRCODE = '23514';
    END IF;
    v_lines := v_lines || jsonb_build_object('account', '3900', 'credit', v_total, 'narration', 'Wallet opening balance reclassified out of suspense');
    v_n := (SELECT count(*) + 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref LIKE 'WALLET-OPENING-RECLASS-%');
    RETURN finance.gl_post((now() AT TIME ZONE 'Africa/Lagos')::date, 'Wallet opening balance reclassified out of opening balance / suspense', 'MANUAL', 'WALLET',
                           'WALLET-OPENING-RECLASS-' || v_n, v_lines);
END $fn$;
COMMENT ON FUNCTION finance.reclassify_wallet_opening(jsonb) IS
  'V552: the Bursary''s reclassification of the wallet''s opening balance out of 3900 Opening balance / suspense to the accounts it belongs in, never more than remains; one journal, Dr each account, Cr 3900.';

COMMIT;
