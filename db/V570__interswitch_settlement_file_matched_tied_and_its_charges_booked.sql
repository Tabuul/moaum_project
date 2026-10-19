-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V570 — Interswitch's settlement file: each payment it settled matched, each day tied to the bank's credit, the charges booked
--
--   A gateway pays a day's payments into the collections account in one credit, less its charges. Until now the Bursary chose the
--   channel and day a credit settled (V552) and booked the difference as charges by hand (V562). Interswitch's per-transaction
--   settlement report now does it:
--     · finance.load_settlement_file reads the report (each row: the day settled, the customer reference, the transaction
--       reference or Payment Log Id, the amount, Interswitch's fee, what was paid over) and matches every row to the portal — by
--       the reference written with or without its hyphens, by WebPAY's transaction reference (finance.gateway_attempt.txn_ref),
--       or by the Payment Log Id Interswitch reported: MATCHED, AMOUNT_DIFFERS, NOT_CONFIRMED (Interswitch settled money for a
--       reference the portal never confirmed — a payer who paid and may still be blocked), UNKNOWN (not a reference the portal
--       issued), DUPLICATE (settled before), REVERSAL (a negative row); and totals each day (finance.settlement_day);
--     · finance.settlement_candidates offers, for each day, the unmatched credits on the collections statements of exactly the
--       day's net within a week after it; finance.tie_settlement_day ties the day to one: the line becomes the day's settlement,
--       its payments count as received (finance.collections_not_received and finance.bank_reconciliation_items restated: a
--       payment in a tied day is in the bank), and Interswitch's fees are booked against 5250 Bank charges in the same press,
--       tied to the line (finance.book_statement_line_to, V562); finance.tie_settlement_days ties every day with one candidate
--       only; finance.untie_settlement_day takes a tie back (the charges' journal reversed on its own day, V562);
--     · finance.settlement_item_to_bank_credit sends a NOT_CONFIRMED row to the bank credits, proposed against its reference, for
--       a second officer to approve (V037), as V552 does for a statement's credit.
--   Nothing is tied or booked in a signed month (RECON_SIGNED_PERIOD).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V570: Interswitch''s settlement file matched, tied and its charges booked', true);

CREATE TABLE finance.settlement_file (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    label           text NOT NULL,
    file_name       text NULL,
    rows            int NOT NULL DEFAULT 0,
    gross           numeric(16,2) NOT NULL DEFAULT 0,
    fees            numeric(16,2) NOT NULL DEFAULT 0,
    net             numeric(16,2) NOT NULL DEFAULT 0,
    first_day       date NULL,
    last_day        date NULL,
    uploaded_by     uuid NOT NULL,
    uploaded_office text NULL,
    uploaded_at     timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('finance.settlement_file');
COMMENT ON TABLE finance.settlement_file IS 'V570: an Interswitch settlement report uploaded — its rows, what was settled, Interswitch''s fees and what was paid over.';

CREATE TABLE finance.settlement_item (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id            uuid NOT NULL REFERENCES finance.settlement_file(id) ON DELETE CASCADE,
    row_no             int NOT NULL,
    settled_on         date NOT NULL,
    paid_on            date NULL,
    reference          text NULL,
    txn_ref            text NULL,
    log_id             text NULL,
    payment_ref        text NULL,
    channel            text NULL,
    payer              text NULL,
    amount             numeric(14,2) NOT NULL,
    fee                numeric(14,2) NOT NULL DEFAULT 0,
    net                numeric(14,2) NOT NULL,
    state              text NOT NULL CHECK (state IN ('MATCHED', 'AMOUNT_DIFFERS', 'NOT_CONFIRMED', 'UNKNOWN', 'DUPLICATE', 'REVERSAL')),
    matched_reference  text NULL,
    matched_by         text NULL CHECK (matched_by IS NULL OR matched_by IN ('REFERENCE', 'TXN_REF', 'LOG_ID')),
    expected           numeric(14,2) NULL,
    bank_credit_id     uuid NULL REFERENCES finance.bank_credit(id) ON DELETE SET NULL,
    UNIQUE (file_id, row_no)
);
CREATE INDEX ix_settlement_item_reference ON finance.settlement_item (matched_reference) WHERE matched_reference IS NOT NULL;
CREATE INDEX ix_settlement_item_day ON finance.settlement_item (file_id, settled_on);
CREATE INDEX ix_settlement_item_log ON finance.settlement_item (finance.log_id_key(log_id)) WHERE log_id IS NOT NULL;
SELECT audit.attach('finance.settlement_item');
COMMENT ON TABLE finance.settlement_item IS
  'V570: a row of an Interswitch settlement report — the day settled, the payment it names (by reference, transaction reference or Payment Log Id), the amount, the fee, what was paid over — and how it matched the portal.';

CREATE TABLE finance.settlement_day (
    file_id     uuid NOT NULL REFERENCES finance.settlement_file(id) ON DELETE CASCADE,
    settled_on  date NOT NULL,
    payments    int NOT NULL,
    gross       numeric(16,2) NOT NULL,
    fees        numeric(16,2) NOT NULL,
    net         numeric(16,2) NOT NULL,
    line_id     uuid NULL REFERENCES finance.bank_statement_line(id) ON DELETE SET NULL,
    tied_by     uuid NULL,
    tied_at     timestamptz NULL,
    PRIMARY KEY (file_id, settled_on)
);
CREATE UNIQUE INDEX ux_settlement_day_line ON finance.settlement_day (line_id) WHERE line_id IS NOT NULL;
SELECT audit.attach('finance.settlement_day');
COMMENT ON TABLE finance.settlement_day IS
  'V570: a day of an Interswitch settlement report — its payments, what they came to, the fees and what was paid over — and the collections statement''s credit it is tied to.';

/* the references Interswitch settled in a day tied to the bank's credit: these are in the bank */
CREATE FUNCTION finance.settled_in_bank(p_lines uuid[] DEFAULT NULL)
RETURNS TABLE (reference text)
LANGUAGE sql STABLE AS $fn$
    SELECT DISTINCT i.matched_reference
      FROM finance.settlement_day d
      JOIN finance.settlement_item i ON i.file_id = d.file_id AND i.settled_on = d.settled_on
     WHERE d.line_id IS NOT NULL AND (p_lines IS NULL OR d.line_id = ANY (p_lines))
       AND i.matched_reference IS NOT NULL AND i.state IN ('MATCHED', 'AMOUNT_DIFFERS', 'NOT_CONFIRMED', 'DUPLICATE')
$fn$;
COMMENT ON FUNCTION finance.settled_in_bank(uuid[]) IS
  'V570: the portal references Interswitch settled in a day tied to a collections statement''s credit (of the lines given, or any) — in the bank.';

/* the report read and matched: [{settledOn, paidOn, reference, txnRef, logId, paymentRef, channel, payer, amount, fee, net}] */
CREATE FUNCTION finance.load_settlement_file(p_label text, p_file text, p_rows jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; r jsonb; i int := 0; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_day date; v_paid date; v_amount numeric; v_fee numeric; v_net numeric; v_ref text; v_by text; v_expected numeric; v_confirmed boolean;
        v_state text; v_token text; v_txn text; v_log text; v_min date; v_max date; v_seen text[] := '{}'; v_logs text[] := '{}'; v_dups int := 0;
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a settlement report is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_label, '')) = '' THEN
        RAISE EXCEPTION 'SETTLEMENT_LABEL: name the report (the gateway and the period)' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'SETTLEMENT_EMPTY: the report has no rows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 50000 THEN
        RAISE EXCEPTION 'SETTLEMENT_TOO_LONG: a report of up to 50,000 rows at a time' USING ERRCODE = '23514';
    END IF;
    SELECT min(coalesce(nullif(x->>'paidOn', ''), x->>'settledOn')::date), max((x->>'settledOn')::date) INTO v_min, v_max
      FROM jsonb_array_elements(p_rows) x WHERE coalesce(x->>'settledOn', '') ~ '^\d{4}-\d{2}-\d{2}$' AND coalesce(x->>'paidOn', '') ~ '^(\d{4}-\d{2}-\d{2})?$';
    INSERT INTO finance.settlement_file (label, file_name, uploaded_by, uploaded_office)
    VALUES (btrim(p_label), nullif(btrim(coalesce(p_file, '')), ''), v_actor, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    -- every reference the portal issued around the report's days, as the report may write it (with or without its hyphens)
    CREATE TEMP TABLE IF NOT EXISTS pg_temp.settle_key (token text, reference text, amount numeric, confirmed boolean) ON COMMIT DROP;
    DELETE FROM pg_temp.settle_key;
    INSERT INTO pg_temp.settle_key
    SELECT DISTINCT ON (k.token) k.token, k.reference, k.amount, k.confirmed
      FROM (SELECT regexp_replace(upper(p.reference), '[^A-Z0-9]', '', 'g') AS token, upper(p.reference) AS reference, p.amount,
                   p.confirmed_at IS NOT NULL AS confirmed, p.confirmed_at
              FROM reporting.payments p
             WHERE p.generated_at >= coalesce(v_min, v_today) - 180 AND p.generated_at < coalesce(v_max, v_today) + 2) k
     WHERE length(k.token) >= 8
     ORDER BY k.token, k.confirmed DESC, k.confirmed_at DESC NULLS LAST;
    CREATE INDEX IF NOT EXISTS ix_pg_temp_settle_key ON pg_temp.settle_key (token);
    ANALYZE pg_temp.settle_key;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        i := i + 1;
        IF coalesce(r->>'settledOn', '') !~ '^\d{4}-\d{2}-\d{2}$' THEN
            RAISE EXCEPTION 'SETTLEMENT_ROW_DATE: row % has no day it was settled', i USING ERRCODE = '23514';
        END IF;
        v_day := (r->>'settledOn')::date;
        v_paid := CASE WHEN coalesce(r->>'paidOn', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (r->>'paidOn')::date END;
        v_amount := round(nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.\-]', '', 'g'), '')::numeric, 2);
        IF v_amount IS NULL OR v_amount = 0 THEN
            RAISE EXCEPTION 'SETTLEMENT_ROW_AMOUNT: row % has no amount', i USING ERRCODE = '23514';
        END IF;
        v_fee := round(abs(nullif(regexp_replace(coalesce(r->>'fee', ''), '[^0-9.\-]', '', 'g'), '')::numeric), 2);
        v_net := round(nullif(regexp_replace(coalesce(r->>'net', ''), '[^0-9.\-]', '', 'g'), '')::numeric, 2);
        IF v_fee IS NULL AND v_net IS NULL THEN v_fee := 0; END IF;
        IF v_fee IS NULL THEN v_fee := v_amount - v_net; END IF;
        IF v_net IS NULL THEN v_net := v_amount - v_fee; END IF;
        IF v_amount - v_fee <> v_net THEN
            RAISE EXCEPTION 'SETTLEMENT_ROW_NET: row % pays over % for % less a fee of %', i, v_net, v_amount, v_fee USING ERRCODE = '23514';
        END IF;
        v_token := regexp_replace(upper(coalesce(r->>'reference', '')), '[^A-Z0-9]', '', 'g');
        v_txn := nullif(btrim(coalesce(r->>'txnRef', '')), '');
        v_log := nullif(btrim(coalesce(r->>'logId', '')), '');
        v_ref := NULL; v_by := NULL; v_expected := NULL; v_confirmed := NULL;
        -- the reference the report names, written with or without its hyphens
        IF length(v_token) >= 8 THEN
            SELECT k.reference, k.amount, k.confirmed INTO v_ref, v_expected, v_confirmed FROM pg_temp.settle_key k WHERE k.token = v_token;
            IF v_ref IS NOT NULL THEN v_by := 'REFERENCE'; END IF;
        END IF;
        -- WebPAY's transaction reference, rendered on the payment page for one of the portal's references
        IF v_ref IS NULL AND v_txn IS NOT NULL THEN
            SELECT a.reference INTO v_ref FROM finance.gateway_attempt a WHERE a.txn_ref = v_txn ORDER BY a.opened_at DESC LIMIT 1;
            IF v_ref IS NOT NULL THEN v_by := 'TXN_REF'; END IF;
        END IF;
        -- the Payment Log Id Interswitch reported for one of them
        IF v_ref IS NULL AND v_log IS NOT NULL THEN
            SELECT upper(e.reference) INTO v_ref FROM finance.gateway_event e
             WHERE e.gateway = 'paydirect' AND e.gateway_ref IS NOT NULL AND finance.log_id_key(e.gateway_ref) = finance.log_id_key(v_log) AND e.reference IS NOT NULL
             ORDER BY e.received_at DESC LIMIT 1;
            IF v_ref IS NULL THEN
                SELECT upper(c.reference) INTO v_ref FROM finance.paydirect_collection c
                 WHERE c.rrn IS NOT NULL AND finance.log_id_key(c.rrn) = finance.log_id_key(v_log) AND c.reference IS NOT NULL LIMIT 1;
            END IF;
            IF v_ref IS NOT NULL THEN v_by := 'LOG_ID'; END IF;
        END IF;
        IF v_ref IS NOT NULL AND v_by <> 'REFERENCE' THEN
            SELECT st.amount, st.confirmed_at IS NOT NULL INTO v_expected, v_confirmed FROM finance.reference_state(v_ref) st LIMIT 1;
        END IF;
        -- settled before (this report, or one uploaded before): by its reference and amount, or its Payment Log Id
        v_state := CASE WHEN v_amount < 0 THEN 'REVERSAL'
                        WHEN v_ref = ANY (v_seen) OR (v_log IS NOT NULL AND finance.log_id_key(v_log) = ANY (v_logs))
                             OR EXISTS (SELECT 1 FROM finance.settlement_item o WHERE o.file_id <> v_id AND o.state <> 'REVERSAL'
                                         AND (o.matched_reference = v_ref AND o.amount = v_amount
                                              OR v_log IS NOT NULL AND o.log_id IS NOT NULL AND finance.log_id_key(o.log_id) = finance.log_id_key(v_log))) THEN 'DUPLICATE'
                        WHEN v_ref IS NULL THEN 'UNKNOWN'
                        WHEN NOT coalesce(v_confirmed, false) THEN 'NOT_CONFIRMED'
                        WHEN v_expected = v_amount THEN 'MATCHED'
                        ELSE 'AMOUNT_DIFFERS' END;
        IF v_state = 'DUPLICATE' THEN v_dups := v_dups + 1; END IF;
        IF v_ref IS NOT NULL AND v_amount > 0 THEN v_seen := v_seen || v_ref; END IF;
        IF v_log IS NOT NULL THEN v_logs := v_logs || finance.log_id_key(v_log); END IF;
        INSERT INTO finance.settlement_item (file_id, row_no, settled_on, paid_on, reference, txn_ref, log_id, payment_ref, channel, payer, amount, fee, net,
                                             state, matched_reference, matched_by, expected)
        VALUES (v_id, i, v_day, v_paid, nullif(btrim(coalesce(r->>'reference', '')), ''), v_txn, v_log, nullif(btrim(coalesce(r->>'paymentRef', '')), ''),
                nullif(btrim(coalesce(r->>'channel', '')), ''), nullif(btrim(coalesce(r->>'payer', '')), ''), v_amount, v_fee, v_net,
                v_state, v_ref, v_by, v_expected);
    END LOOP;
    IF v_dups = i THEN
        RAISE EXCEPTION 'SETTLEMENT_FILE_AGAIN: every row of this report was settled in a report uploaded before' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.settlement_day (file_id, settled_on, payments, gross, fees, net)
    SELECT v_id, x.settled_on, count(*), sum(x.amount), sum(x.fee), sum(x.net) FROM finance.settlement_item x WHERE x.file_id = v_id GROUP BY x.settled_on;
    UPDATE finance.settlement_file f SET rows = i, gross = t.gross, fees = t.fees, net = t.net, first_day = t.first_day, last_day = t.last_day
      FROM (SELECT sum(x.amount) AS gross, sum(x.fee) AS fees, sum(x.net) AS net, min(x.settled_on) AS first_day, max(x.settled_on) AS last_day
              FROM finance.settlement_item x WHERE x.file_id = v_id) t
     WHERE f.id = v_id;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION finance.load_settlement_file(text, text, jsonb) IS
  'V570: an Interswitch settlement report uploaded — every row matched to the portal by its reference, WebPAY transaction reference or Payment Log Id (MATCHED, AMOUNT_DIFFERS, NOT_CONFIRMED, UNKNOWN, DUPLICATE, REVERSAL) and each day totalled; returns the report.';

/* for each day of a report not yet tied, the unmatched credits on the collections statements of exactly its net, dated from the day
   before it to a week after */
CREATE FUNCTION finance.settlement_candidates(p_file uuid)
RETURNS TABLE (settled_on date, line_id uuid, statement text, line_no int, value_date date, credit numeric, description text)
LANGUAGE sql STABLE AS $fn$
    SELECT d.settled_on, l.id, s.label, l.line_no, l.value_date, l.credit, coalesce(nullif(btrim(coalesce(l.reference, '')), ''), l.description)
      FROM finance.settlement_day d
      JOIN finance.bank_statement_line l ON l.credit = d.net AND l.status = 'UNMATCHED' AND l.ledger_journal IS NULL
      JOIN finance.bank_statement s ON s.id = l.statement_id AND s.account_kind = 'COLLECTIONS'
     WHERE d.file_id = p_file AND d.line_id IS NULL AND d.net > 0
       AND coalesce(l.value_date, s.period_to) BETWEEN d.settled_on - 1 AND d.settled_on + 7
       AND NOT EXISTS (SELECT 1 FROM finance.settlement_day o WHERE o.line_id = l.id)
     ORDER BY d.settled_on, abs(coalesce(l.value_date, s.period_to) - d.settled_on), s.label, l.line_no
$fn$;
COMMENT ON FUNCTION finance.settlement_candidates(uuid) IS
  'V570: for each untied day of a settlement report, the unmatched collections credits of exactly the day''s net, dated the day before to a week after.';

/* a day tied to the bank's credit: the line becomes the day's settlement, its payments are in the bank, and Interswitch's fees are
   booked against 5250 Bank charges, tied to the line */
CREATE FUNCTION finance.tie_settlement_day(p_file uuid, p_day date, p_line uuid)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; d finance.settlement_day; l finance.bank_statement_line;
        s finance.bank_statement; f finance.settlement_file; v_no bigint;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a settlement is tied by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO d FROM finance.settlement_day WHERE file_id = p_file AND settled_on = p_day FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SETTLEMENT_DAY: the report settled nothing on %', to_char(p_day, 'FMDD FMMonth YYYY') USING ERRCODE = '23514'; END IF;
    IF d.line_id IS NOT NULL THEN
        RAISE EXCEPTION 'SETTLEMENT_DAY_TIED: % is tied to a credit already; take it back first', to_char(p_day, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO f FROM finance.settlement_file WHERE id = p_file;
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = p_line FOR UPDATE;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    IF l.id IS NULL OR s.account_kind <> 'COLLECTIONS' OR l.credit <= 0 OR l.status <> 'UNMATCHED' OR l.ledger_journal IS NOT NULL THEN
        RAISE EXCEPTION 'SETTLEMENT_LINE: only an unmatched credit of a collections statement, not yet accounted for, is a day''s settlement' USING ERRCODE = '23514';
    END IF;
    IF l.credit <> d.net THEN
        RAISE EXCEPTION 'SETTLEMENT_AMOUNT: the line credits NGN %, the day''s settlement pays over NGN %', to_char(l.credit, 'FM999,999,999,990.00'),
            to_char(d.net, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    IF (finance.gl_closed_by('1010', coalesce(l.value_date, s.period_to))).id IS NOT NULL THEN
        RAISE EXCEPTION 'RECON_SIGNED_PERIOD: line % falls in a signed reconciliation of 1010', l.line_no USING ERRCODE = '23514';
    END IF;
    UPDATE finance.bank_statement_line SET status = 'SETTLEMENT', matched_kind = 'SETTLEMENT', settlement_channel = 'Interswitch settlement',
           settlement_day = d.settled_on, expected_amount = d.gross, matched_payouts = d.payments, matched_reference = NULL, settled_by = v_actor, settled_at = now()
     WHERE id = l.id;
    IF d.fees <> 0 THEN
        v_no := finance.book_statement_line_to(l.id, '5250', 'Interswitch''s charges on the settlement of ' || to_char(d.settled_on, 'FMDD FMMonth YYYY')
                                                             || ' (' || f.label || ', ' || d.payments || ' payment' || CASE WHEN d.payments = 1 THEN '' ELSE 's' END || ')');
    END IF;
    UPDATE finance.settlement_day SET line_id = l.id, tied_by = v_actor, tied_at = now() WHERE file_id = p_file AND settled_on = p_day;
    RETURN jsonb_build_object('payments', d.payments, 'gross', d.gross, 'fees', d.fees, 'net', d.net, 'journalNo', v_no);
END $fn$;
COMMENT ON FUNCTION finance.tie_settlement_day(uuid, date, uuid) IS
  'V570: a day of a settlement report tied to the collections credit of exactly its net — the line marked the day''s settlement, its payments in the bank, Interswitch''s fees booked against 5250 Bank charges and tied to the line (V562); never in a signed month.';

/* every day of a report with exactly one candidate credit, that credit a candidate for no other day, tied */
CREATE FUNCTION finance.tie_settlement_days(p_file uuid)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE c record; n int := 0;
BEGIN
    FOR c IN WITH k AS MATERIALIZED (SELECT x.settled_on, x.line_id FROM finance.settlement_candidates(p_file) x),
                  one AS (SELECT k.settled_on, min(k.line_id::text)::uuid AS line_id FROM k GROUP BY k.settled_on HAVING count(*) = 1),
                  lonely AS (SELECT k.line_id FROM k GROUP BY k.line_id HAVING count(*) = 1)
             SELECT one.settled_on, one.line_id FROM one JOIN lonely ON lonely.line_id = one.line_id ORDER BY one.settled_on LOOP
        PERFORM finance.tie_settlement_day(p_file, c.settled_on, c.line_id);
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION finance.tie_settlement_days(uuid) IS
  'V570: each day of a settlement report that has exactly one candidate credit, a credit no other day could take, tied to it (finance.tie_settlement_day); returns how many.';

/* a tie taken back: the charges' journal reversed on its own day, the line unmatched again */
CREATE FUNCTION finance.untie_settlement_day(p_file uuid, p_day date)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; d finance.settlement_day; l finance.bank_statement_line; s finance.bank_statement;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a settlement is taken back by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO d FROM finance.settlement_day WHERE file_id = p_file AND settled_on = p_day FOR UPDATE;
    IF NOT FOUND OR d.line_id IS NULL THEN
        RAISE EXCEPTION 'SETTLEMENT_DAY_NOT_TIED: % is not tied to a credit', to_char(p_day, 'FMDD FMMonth YYYY') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO l FROM finance.bank_statement_line WHERE id = d.line_id FOR UPDATE;
    SELECT * INTO s FROM finance.bank_statement WHERE id = l.statement_id;
    IF (finance.gl_closed_by('1010', coalesce(l.value_date, s.period_to))).id IS NOT NULL THEN
        RAISE EXCEPTION 'RECON_SIGNED_PERIOD: line % falls in a signed reconciliation of 1010', l.line_no USING ERRCODE = '23514';
    END IF;
    IF l.ledger_journal IS NOT NULL THEN
        PERFORM finance.book_statement_line(l.id, NULL, NULL);
    END IF;
    UPDATE finance.bank_statement_line SET status = 'UNMATCHED', matched_kind = NULL, settlement_channel = NULL, settlement_day = NULL, expected_amount = NULL,
           matched_payouts = 0, settled_by = NULL, settled_at = NULL
     WHERE id = l.id;
    UPDATE finance.settlement_day SET line_id = NULL, tied_by = NULL, tied_at = NULL WHERE file_id = p_file AND settled_on = p_day;
END $fn$;
COMMENT ON FUNCTION finance.untie_settlement_day(uuid, date) IS
  'V570: a settlement day''s tie taken back — the charges'' journal reversed on its own day (V562), the line an unmatched credit again; never in a signed month.';

/* a row Interswitch settled for a reference the portal never confirmed, sent to the bank credits for a second officer to approve */
CREATE FUNCTION finance.settlement_item_to_bank_credit(p_item uuid)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE x finance.settlement_item; f finance.settlement_file; v_credit uuid;
BEGIN
    SELECT * INTO x FROM finance.settlement_item WHERE id = p_item FOR UPDATE;
    IF x.id IS NULL OR x.state <> 'NOT_CONFIRMED' THEN
        RAISE EXCEPTION 'SETTLEMENT_ITEM_NOT_UNCONFIRMED: only a row Interswitch settled for a reference the portal never confirmed goes to the bank credits' USING ERRCODE = '23514';
    END IF;
    IF x.bank_credit_id IS NOT NULL THEN
        RAISE EXCEPTION 'SETTLEMENT_ITEM_SENT: row % is already a bank credit', x.row_no USING ERRCODE = '23514';
    END IF;
    IF (SELECT st.confirmed_at FROM finance.reference_state(x.matched_reference) st LIMIT 1) IS NOT NULL THEN
        RAISE EXCEPTION 'SETTLEMENT_ITEM_CONFIRMED: % is confirmed now; nothing to send', x.matched_reference USING ERRCODE = '23514';
    END IF;
    SELECT * INTO f FROM finance.settlement_file WHERE id = x.file_id;
    v_credit := finance.record_bank_credit(x.settled_on, 'Interswitch settlement', 'Settlement row ' || x.row_no || coalesce(' · ' || x.log_id, ''),
                                           x.amount, x.payer, 'From the Interswitch settlement report ' || f.label);
    PERFORM finance.propose_bank_credit(v_credit, x.matched_reference,
        'Interswitch settled NGN ' || to_char(x.amount, 'FM999,999,999,990.00') || ' for ' || x.matched_reference || ' on ' || to_char(x.settled_on, 'FMDD FMMonth YYYY')
        || coalesce(' (Payment Log Id ' || x.log_id || ')', '') || ' in the report ' || f.label || ', a reference the portal never confirmed');
    UPDATE finance.settlement_item SET bank_credit_id = v_credit WHERE id = x.id;
    RETURN v_credit;
END $fn$;
COMMENT ON FUNCTION finance.settlement_item_to_bank_credit(uuid) IS
  'V570: a settlement row for a reference the portal never confirmed, recorded as a bank credit and proposed against that reference; a second officer approves it (V037).';

-- ── a payment Interswitch settled in a day tied to the bank's credit is in the bank ─────────────────────────────────────────
/* V552's payments confirmed and not seen in the bank, restated: not one Interswitch settled in a tied day */
CREATE OR REPLACE FUNCTION finance.collections_not_received(p_statement uuid)
RETURNS TABLE (reference text, channel text, day date, amount numeric, purpose text, payer text, number text, confirmed_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT period_from, period_to FROM finance.bank_statement WHERE id = p_statement AND account_kind = 'COLLECTIONS'),
    found AS (
        SELECT DISTINCT l.matched_reference AS ref FROM finance.bank_statement_line l JOIN finance.bank_statement b ON b.id = l.statement_id
         WHERE b.account_kind = 'COLLECTIONS' AND l.matched_kind = 'PAYMENT' AND l.matched_reference IS NOT NULL),
    settled AS (
        SELECT DISTINCT l.settlement_channel, l.settlement_day FROM finance.bank_statement_line l JOIN finance.bank_statement b ON b.id = l.statement_id
         WHERE b.account_kind = 'COLLECTIONS' AND l.status = 'SETTLEMENT'),
    -- V570: what Interswitch settled in a day tied to the bank's credit
    tied AS MATERIALIZED (SELECT t.reference AS ref FROM finance.settled_in_bank() t)
    SELECT p.reference, p.channel, (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, p.amount, p.purpose,
           nullif(btrim(coalesce(p.surname, '') || ' ' || coalesce(p.other_names, '')), ''), p.number, p.confirmed_at
      FROM reporting.payments p CROSS JOIN s
     WHERE p.confirmed_at IS NOT NULL AND p.amount > 0 AND finance.receipt_through_bank(p.channel)
       AND p.confirmed_at >= (s.period_from::timestamp AT TIME ZONE 'Africa/Lagos') AND p.confirmed_at < ((s.period_to + 1)::timestamp AT TIME ZONE 'Africa/Lagos')
       AND NOT EXISTS (SELECT 1 FROM found f WHERE f.ref = upper(p.reference))
       AND NOT EXISTS (SELECT 1 FROM settled x WHERE x.settlement_channel = p.channel AND x.settlement_day = (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date)
       AND NOT EXISTS (SELECT 1 FROM finance.payment_reconciliation pr WHERE pr.reference = upper(p.reference) AND pr.result = 'MATCHED')
       AND NOT EXISTS (SELECT 1 FROM tied t WHERE t.ref = upper(p.reference))
     ORDER BY 3, 2, p.confirmed_at
$fn$;
COMMENT ON FUNCTION finance.collections_not_received(uuid) IS
  'V552, V570: the payments confirmed in a collections statement''s period, through the bank, that no line found (one by one, as a day''s settlement, or in a settlement report''s day tied to a credit) and no one has reconciled — confirmed on the portal, not seen in the bank.';

/* V557's reconciling items, restated: a payment Interswitch settled in a day tied to one of the period's lines is no item */
CREATE OR REPLACE FUNCTION finance.bank_reconciliation_items(p_account text, p_from date, p_to date)
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
-- V570: the payments Interswitch settled in a day tied to one of these lines
tied AS MATERIALIZED (SELECT t.reference AS ref FROM finance.settled_in_bank(ARRAY(SELECT ln.id FROM ln)) t),
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
             OR EXISTS (SELECT 1 FROM tied WHERE tied.ref = upper(jr.source_ref))
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
  'V557, V570: every reconciling item of 1010 or 1020 at the end of a period, from the start of the account''s first reconciliation — on the ledger and not yet in the bank, in the bank and not on the ledger, a difference, a gateway''s charges — with its effect on the bank''s balance (+ the ledger holds more); a payment in a settlement report''s day tied to one of the period''s lines is in the bank.';

COMMIT;
