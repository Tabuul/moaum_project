-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V545 — The bank statement matched to what was paid out; the NELFUND wallet on the general ledger; approved but unpaid refunds
--        and withdrawals watched; the check digit for the newer banks whose codes are confirmed
--
--   1 · Internal Audit or the Bursary uploads the disbursement account's statement (finance.load_bank_statement). Each debit line
--       is matched to what the portal paid out (V540's Paid out) by the bank transfer reference found in the line's reference or
--       description and by the amount — a single refund or withdrawal, or every payment that carries that reference together:
--       MATCHED; the reference found but the amount different: AMOUNT_DIFFERS; nothing: UNMATCHED; a credit line is not a payout.
--       finance.statement_missing lists what the portal paid out in the statement's period that no line matched.
--   2 · The NELFUND wallet on the general ledger, from now on (the Bursary chose it, 18 Oct 2026); journals already posted stay as
--       they are. Money in the wallet is held for students in 2100 Student deposits & wallet:
--         a credit — Dr Bank — Fees collection (a loan such as NELFUND, or own money), Dr Grants, research & scholarships (a grant),
--                    Dr Opening balance / suspense (a credit brought from the old portal); Cr 2100
--         a top-up paid — Dr Bank — Fees collection, Cr 2100 (no longer Other income)
--         the wallet applied to fees — Dr 2100 (no longer the bank again), Cr the income account
--         a reversal to the Fund, a withdrawal paid — Dr 2100, Cr Bank — Disbursements (a withdrawal on the day the money left)
--       What students held in their wallets before this is opened once against Opening balance / suspense, for the Bursary to
--       settle. A wallet entry is "from now on" when it is recorded after this migration (wallet_entry.recorded_at).
--   3 · A refund or withdrawal approved and not paid within the days the Bursary sets (7 by default) is listed for the Bursary
--       (finance.unpaid_payouts) and told to the Bursar and the Students Account Officer once a day (UNPAID_PAYOUTS).
--   4 · The NUBAN check digit is switched on for Providus (101), Jaiz (301), PremiumTrust (105), Lotus (303) and Globus (103),
--       whose Central Bank codes two independent published lists agree on. Titan Trust, SunTrust and Parallex (one list only),
--       TAJ (the lists disagree: 302 or 321), Optimus and Signature (not listed) stay unchecked. finance.bank_evidence counts, for
--       each bank, the accounts paid into and how many pass the check digit — the Bursary's evidence before switching one on.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V545: bank statement matched, the wallet on the ledger, unpaid payouts watched, banks checked', true);

-- ── 1 · the bank statement matched to what was paid out ──────────────────────────────────────────────────────────────────
CREATE TABLE finance.bank_statement (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    label           text NOT NULL CHECK (btrim(label) <> ''),
    file_name       text NULL,
    period_from     date NULL,
    period_to       date NULL,
    lines           int NOT NULL DEFAULT 0,
    uploaded_by     uuid NULL,
    uploaded_office text NULL,
    uploaded_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.bank_statement IS
  'V545: a statement of the University''s disbursement account, uploaded to be matched to what the portal paid out (refunds and wallet withdrawals) by the bank transfer reference and the amount.';
SELECT audit.attach('finance.bank_statement');

CREATE TABLE finance.bank_statement_line (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_id      uuid NOT NULL REFERENCES finance.bank_statement(id) ON DELETE CASCADE,
    line_no           int NOT NULL,
    value_date        date NULL,
    description       text NULL,
    reference         text NULL,
    debit             numeric(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit            numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    status            text NOT NULL CHECK (status IN ('MATCHED', 'AMOUNT_DIFFERS', 'UNMATCHED', 'CREDIT')),
    matched_reference text NULL,
    expected_amount   numeric(14,2) NULL,
    matched_payouts   int NOT NULL DEFAULT 0,
    UNIQUE (statement_id, line_no)
);
COMMENT ON TABLE finance.bank_statement_line IS
  'V545: one line of an uploaded bank statement and how it matched: MATCHED (the transfer reference and the amount of a payout, or of every payout carrying that reference), AMOUNT_DIFFERS (the reference, another amount), UNMATCHED, or CREDIT (money in, not a payout).';
SELECT audit.attach('finance.bank_statement_line');

/* every payout on record with a transfer reference, by reference: the amounts, their sum and their number */
CREATE FUNCTION finance.payout_references()
RETURNS TABLE (ref text, total numeric, payouts int, amounts numeric[])
LANGUAGE sql STABLE AS $fn$
    SELECT upper(btrim(x.r)), sum(x.amount), count(*)::int, array_agg(x.amount)
      FROM (SELECT rf.paid_reference AS r, rf.amount FROM finance.refund rf WHERE rf.state = 'PAID' AND rf.paid_reference IS NOT NULL
            UNION ALL
            SELECT w.paid_ref, w.amount FROM finance.wallet_withdrawal w WHERE w.state = 'PAID' AND w.paid_ref IS NOT NULL) x
     WHERE length(btrim(x.r)) >= 4
     GROUP BY upper(btrim(x.r))
$fn$;

/* a statement uploaded: [{date, description, reference, debit, credit}] — each debit matched by the longest transfer reference found
   in its reference or description, and the amount */
CREATE FUNCTION finance.load_bank_statement(p_label text, p_file text, p_rows jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; r jsonb; i int := 0; v_text text; v_debit numeric; v_credit numeric; v_date date; v_status text;
        v_ref text; v_total numeric; v_payouts int; v_amounts numeric[];
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
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
    INSERT INTO finance.bank_statement (label, file_name, uploaded_by, uploaded_office)
    VALUES (btrim(p_label), nullif(btrim(coalesce(p_file, '')), ''), v_actor, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    CREATE TEMP TABLE IF NOT EXISTS pg_temp.payout_ref (ref text, total numeric, payouts int, amounts numeric[]) ON COMMIT DROP;
    DELETE FROM pg_temp.payout_ref;
    INSERT INTO pg_temp.payout_ref SELECT * FROM finance.payout_references();
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        i := i + 1;
        v_debit := round(abs(coalesce(nullif(regexp_replace(coalesce(r->>'debit', ''), '[^0-9.]', '', 'g'), '')::numeric, 0)), 2);
        v_credit := round(abs(coalesce(nullif(regexp_replace(coalesce(r->>'credit', ''), '[^0-9.]', '', 'g'), '')::numeric, 0)), 2);
        v_date := CASE WHEN coalesce(r->>'date', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (r->>'date')::date END;
        v_text := upper(coalesce(r->>'reference', '') || ' ' || coalesce(r->>'description', ''));
        v_ref := NULL; v_total := NULL; v_payouts := NULL; v_amounts := NULL; v_status := 'CREDIT';
        IF v_debit > 0 THEN
            SELECT p.ref, p.total, p.payouts, p.amounts INTO v_ref, v_total, v_payouts, v_amounts
              FROM pg_temp.payout_ref p WHERE position(p.ref IN v_text) > 0 ORDER BY length(p.ref) DESC LIMIT 1;
            v_status := CASE WHEN v_ref IS NULL THEN 'UNMATCHED'
                             WHEN v_debit = v_total OR v_debit = ANY (v_amounts) THEN 'MATCHED'
                             ELSE 'AMOUNT_DIFFERS' END;
        END IF;
        INSERT INTO finance.bank_statement_line (statement_id, line_no, value_date, description, reference, debit, credit, status,
                                                 matched_reference, expected_amount, matched_payouts)
        VALUES (v_id, i, v_date, nullif(btrim(coalesce(r->>'description', '')), ''), nullif(btrim(coalesce(r->>'reference', '')), ''), v_debit, v_credit, v_status,
                v_ref, CASE WHEN v_ref IS NOT NULL THEN CASE WHEN v_debit = ANY (v_amounts) AND v_debit <> v_total THEN v_debit ELSE v_total END END,
                CASE WHEN v_status = 'MATCHED' THEN CASE WHEN v_debit = v_total THEN v_payouts ELSE 1 END ELSE 0 END);
    END LOOP;
    UPDATE finance.bank_statement s SET lines = i,
           period_from = (SELECT min(l.value_date) FROM finance.bank_statement_line l WHERE l.statement_id = v_id),
           period_to = (SELECT max(l.value_date) FROM finance.bank_statement_line l WHERE l.statement_id = v_id)
     WHERE s.id = v_id;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION finance.load_bank_statement(text, text, jsonb) IS
  'V545: a disbursement-account statement uploaded and each debit matched to what was paid out by transfer reference and amount; returns the statement.';

/* what the portal paid out in the statement's period that no line of it matched */
CREATE FUNCTION finance.statement_missing(p_statement uuid)
RETURNS TABLE (kind text, reference text, payee text, number text, bank_name text, account_number text, amount numeric, paid_on date, transfer_reference text)
LANGUAGE sql STABLE AS $fn$
    SELECT p.kind, p.reference, p.payee, p.number, p.bank_name, p.account_number, p.amount, p.paid_on, p.transfer_reference
      FROM finance.bank_statement s
      CROSS JOIN LATERAL finance.paid_out(s.period_from, s.period_to) p
     WHERE s.id = p_statement AND s.period_from IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM finance.bank_statement_line l
                        WHERE l.statement_id = s.id AND l.status = 'MATCHED' AND l.matched_reference = upper(btrim(coalesce(p.transfer_reference, ''))))
     ORDER BY p.paid_on, p.reference
$fn$;
COMMENT ON FUNCTION finance.statement_missing(uuid) IS
  'V545: the refunds and wallet withdrawals paid in a statement''s period (by the day the money left) that no line of the statement matched.';

-- ── 2 · the NELFUND wallet on the general ledger, from now on ────────────────────────────────────────────────────────────
ALTER TABLE finance.wallet_setting ADD COLUMN gl_from timestamptz NOT NULL DEFAULT now();
COMMENT ON COLUMN finance.wallet_setting.gl_from IS 'V545: when wallet money began to be posted on the general ledger; payments confirmed from then are posted on the wallet''s terms.';
ALTER TABLE finance.wallet_entry ADD COLUMN recorded_at timestamptz NULL;
ALTER TABLE finance.wallet_entry ALTER COLUMN recorded_at SET DEFAULT now();
COMMENT ON COLUMN finance.wallet_entry.recorded_at IS 'V545: when the entry was recorded (at may carry an older date, as an old-portal credit does); empty for an entry recorded before the wallet was on the general ledger, which the opening balance holds.';
CREATE INDEX ix_wallet_entry_recorded ON finance.wallet_entry (recorded_at) WHERE recorded_at IS NOT NULL;

/* what students held in their wallets when the wallet came onto the ledger (every entry recorded before) */
CREATE FUNCTION finance.wallet_opening_balance()
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(sum(CASE WHEN e.kind IN ('CREDIT', 'TOPUP') THEN e.amount ELSE -e.amount END), 0)
      FROM finance.wallet_entry e WHERE e.recorded_at IS NULL
$fn$;

/* the account a wallet credit is drawn from: a credit from the old portal against the opening balance; a grant as a grant; a loan
   (NELFUND) or own money as money into the bank */
CREATE FUNCTION finance.gl_wallet_credit_account(p_source text, p_legacy boolean)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_legacy THEN '3900'
                WHEN (SELECT fs.nature FROM finance.funding_source fs WHERE fs.code = p_source) = 'GRANT' THEN '5240'
                ELSE '1010' END
$fn$;

DROP FUNCTION finance.gl_sync();
DROP FUNCTION finance.gl_sync(int);
DROP FUNCTION finance.gl_unposted();

CREATE FUNCTION finance.gl_unposted() RETURNS TABLE (payments bigint, refunds bigint, vouchers bigint, wallet bigint)
LANGUAGE sql STABLE AS $$
    SELECT (SELECT count(*) FROM finance.payment_reference pr
             WHERE pr.confirmed_at IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference))
         + (SELECT count(*) FROM reporting.payments v
             WHERE v.source <> 'STUDENT' AND v.confirmed_at IS NOT NULL AND v.amount > 0
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = v.reference)),
           (SELECT count(*) FROM finance.refund rf
             WHERE rf.state = 'PAID' AND rf.paid_at IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'REFUND' AND j.source_ref = rf.reference)),
           (SELECT count(*) FROM expenditure.voucher v
             WHERE v.stage = 'PAID' AND v.paid_at IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference)),
           (SELECT count(*) FROM finance.wallet_entry e
             WHERE e.recorded_at IS NOT NULL AND e.kind IN ('CREDIT', 'REVERSED', 'REFUND')
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || e.id))
         + CASE WHEN finance.wallet_opening_balance() <> 0
                     AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-OPENING') THEN 1 ELSE 0 END
$$;
COMMENT ON FUNCTION finance.gl_unposted() IS
  'What the general ledger has not yet posted (V410, V545): confirmed payments — a student''s and every other on the one ledger, on the terms finance.gl_sync posts them — paid refunds, paid vouchers, and the wallet''s credits, reversals and withdrawals recorded since it came onto the ledger (with its opening balance, once).';

CREATE FUNCTION finance.gl_sync(p_limit int)
RETURNS TABLE (payments int, refunds int, vouchers int, remaining bigint, wallet int)
LANGUAGE plpgsql AS $$
DECLARE r record; v_p int := 0; v_r int := 0; v_v int := 0; v_w int := 0; v_room int; v_from timestamptz; v_open numeric;
BEGIN
    IF p_limit IS NOT NULL AND p_limit < 1 THEN
        RAISE EXCEPTION 'A ledger sync posts at least one transaction at a time' USING ERRCODE = '22023';
    END IF;
    -- two syncs at once take turns: the second finds what the first posted and carries on from there
    PERFORM pg_advisory_xact_lock(hashtext('finance.gl_sync'));
    v_room := coalesce(p_limit, 2147483647);
    SELECT ws.gl_from INTO v_from FROM finance.wallet_setting ws WHERE ws.one;
    v_from := coalesce(v_from, 'infinity'::timestamptz);

    -- confirmed student payments → Dr Bank (Collections), Cr the income account; V545, from when the wallet came onto the ledger:
    -- the wallet applied to fees is Dr Student deposits & wallet (no new money in the bank), a top-up is Cr Student deposits & wallet
    FOR r IN
        SELECT pr.reference, pr.confirmed_at::date AS d, pr.amount, pr.session,
               finance.payment_category(pr.purpose) AS cat, pr.purpose,
               (pr.confirmed_at >= v_from AND pr.channel = 'NELFUND wallet') AS from_wallet,
               (pr.confirmed_at >= v_from AND pr.purpose LIKE 'Wallet top-up%') AS to_wallet
          FROM finance.payment_reference pr
         WHERE pr.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference)
         ORDER BY pr.confirmed_at, pr.reference
         LIMIT v_room
    LOOP
        PERFORM finance.gl_post(r.d, 'Fee receipt ' || r.reference || ' — ' || CASE WHEN r.to_wallet THEN 'Wallet top-up' ELSE r.cat END, 'AUTO', 'PAYMENT', r.reference,
            jsonb_build_array(
                jsonb_build_object('account', CASE WHEN r.from_wallet THEN '2100' ELSE '1010' END, 'debit', r.amount, 'narration', r.purpose, 'session', r.session),
                jsonb_build_object('account', CASE WHEN r.to_wallet THEN '2100' ELSE finance.gl_income_account(r.cat) END, 'credit', r.amount, 'narration', r.purpose, 'session', r.session)));
        v_p := v_p + 1;
    END LOOP;
    v_room := v_room - v_p;

    -- every other confirmed payment of the one ledger — an applicant's, the School's, JUPEB's (V409)
    IF v_room > 0 THEN
        FOR r IN
            SELECT v.reference, v.confirmed_at::date AS d, v.amount, v.session, pp.gl_account,
                   concat_ws(' ', t.label, lower(pp.label)) AS narration
              FROM reporting.payments v
              LEFT JOIN finance.payment_purpose pp ON pp.code = v.purpose_code
              LEFT JOIN finance.programme_type t ON t.code = v.programme_type
             WHERE v.source <> 'STUDENT' AND v.confirmed_at IS NOT NULL AND v.amount > 0
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = v.reference)
             ORDER BY v.confirmed_at, v.reference
             LIMIT v_room
        LOOP
            PERFORM finance.gl_post(r.d, 'Fee receipt ' || r.reference || ' — ' || r.narration, 'AUTO', 'PAYMENT', r.reference,
                jsonb_build_array(
                    jsonb_build_object('account','1010','debit', r.amount, 'narration', r.narration, 'session', r.session),
                    jsonb_build_object('account', coalesce(r.gl_account, '4090'), 'credit', r.amount, 'narration', r.narration, 'session', r.session)));
            v_p := v_p + 1;
            v_room := v_room - 1;
        END LOOP;
    END IF;

    -- paid refunds → Dr Refunds of fees, Cr Bank (Disbursements); on the day the money left (V540), else the day recorded
    IF v_room > 0 THEN
        FOR r IN
            SELECT rf.reference, coalesce(rf.paid_on, rf.paid_at::date) AS d, rf.amount, rf.reason
              FROM finance.refund rf
             WHERE rf.state = 'PAID' AND rf.paid_at IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'REFUND' AND j.source_ref = rf.reference)
             ORDER BY rf.paid_at, rf.reference
             LIMIT v_room
        LOOP
            PERFORM finance.gl_post(r.d, 'Refund ' || r.reference || ' — ' || r.reason, 'AUTO', 'REFUND', r.reference,
                jsonb_build_array(
                    jsonb_build_object('account','4990','debit', r.amount, 'narration', r.reason),
                    jsonb_build_object('account','1020','credit', r.amount, 'narration', r.reason)));
            v_r := v_r + 1;
        END LOOP;
        v_room := v_room - v_r;
    END IF;

    -- paid vouchers → Dr the expense account, Cr Bank (Disbursements)
    IF v_room > 0 THEN
        FOR r IN
            SELECT v.reference, v.paid_at::date AS d, v.amount, v.title, v.kind, v.payee
              FROM expenditure.voucher v
             WHERE v.stage = 'PAID' AND v.paid_at IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference)
             ORDER BY v.paid_at, v.reference
             LIMIT v_room
        LOOP
            PERFORM finance.gl_post(r.d, 'Voucher ' || r.reference || ' — ' || r.title || ' (' || r.payee || ')',
                'AUTO', 'VOUCHER', r.reference,
                jsonb_build_array(
                    jsonb_build_object('account', finance.gl_expense_account(r.kind), 'debit', r.amount, 'narration', r.title),
                    jsonb_build_object('account','1020','credit', r.amount, 'narration', r.payee)));
            v_v := v_v + 1;
        END LOOP;
        v_room := v_room - v_v;
    END IF;

    -- V545: the wallet — first what students held when it came onto the ledger, once, against Opening balance / suspense
    IF v_room > 0 AND v_from < 'infinity'::timestamptz
       AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-OPENING') THEN
        v_open := finance.wallet_opening_balance();
        IF v_open <> 0 THEN
            PERFORM finance.gl_post(v_from::date, 'Wallet balances held when the wallet came onto the ledger (to settle from opening balance / suspense)',
                'AUTO', 'WALLET', 'WALLET-OPENING',
                jsonb_build_array(
                    jsonb_build_object('account', CASE WHEN v_open > 0 THEN '3900' ELSE '2100' END, 'debit', abs(v_open), 'narration', 'Wallet balances brought onto the ledger'),
                    jsonb_build_object('account', CASE WHEN v_open > 0 THEN '2100' ELSE '3900' END, 'credit', abs(v_open), 'narration', 'Wallet balances brought onto the ledger')));
            v_w := v_w + 1;
            v_room := v_room - 1;
        END IF;
    END IF;
    -- then each credit (Cr Student deposits & wallet), reversal to the Fund and withdrawal paid (Dr Student deposits & wallet, Cr Bank)
    IF v_room > 0 THEN
        FOR r IN
            SELECT e.id, e.kind, e.amount, e.session, e.note, e.reference, e.source_code,
                   CASE WHEN e.kind = 'REFUND' THEN coalesce(w.paid_on, e.at::date)
                        WHEN e.legacy_payment_id IS NOT NULL THEN e.recorded_at::date
                        ELSE e.at::date END AS d,
                   finance.gl_wallet_credit_account(e.source_code, e.legacy_payment_id IS NOT NULL) AS credit_from
              FROM finance.wallet_entry e
              LEFT JOIN finance.wallet_withdrawal w ON w.entry_id = e.id
             WHERE e.recorded_at IS NOT NULL AND e.kind IN ('CREDIT', 'REVERSED', 'REFUND')
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || e.id)
             ORDER BY e.recorded_at, e.id
             LIMIT v_room
        LOOP
            PERFORM finance.gl_post(r.d,
                CASE r.kind WHEN 'CREDIT' THEN 'Wallet credit' WHEN 'REVERSED' THEN 'Wallet reversed to the Fund' ELSE 'Wallet withdrawal paid' END
                    || coalesce(' ' || r.reference, '') || ' — ' || coalesce(r.note, ''),
                'AUTO', 'WALLET', 'WALLET-' || r.id,
                CASE WHEN r.kind = 'CREDIT' THEN
                    jsonb_build_array(
                        jsonb_build_object('account', r.credit_from, 'debit', r.amount, 'narration', r.note, 'session', r.session, 'fund', r.source_code),
                        jsonb_build_object('account', '2100', 'credit', r.amount, 'narration', r.note, 'session', r.session, 'fund', r.source_code))
                ELSE
                    jsonb_build_array(
                        jsonb_build_object('account', '2100', 'debit', r.amount, 'narration', r.note, 'session', r.session, 'fund', r.source_code),
                        jsonb_build_object('account', '1020', 'credit', r.amount, 'narration', r.note, 'session', r.session, 'fund', r.source_code))
                END);
            v_w := v_w + 1;
        END LOOP;
    END IF;

    payments := v_p; refunds := v_r; vouchers := v_v; wallet := v_w;
    SELECT u.payments + u.refunds + u.vouchers + u.wallet INTO remaining FROM finance.gl_unposted() u;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION finance.gl_sync(int) IS
  'Posts at most p_limit transactions the ledger has not yet posted (V410; NULL is every one): confirmed payments oldest first (V545: the wallet applied to fees Dr Student deposits & wallet, a top-up Cr it), every other payment on the one ledger, paid refunds (on the day the money left, V540), paid vouchers, then the wallet (V545: its opening balance once, each credit, reversal and withdrawal paid), each once by (source type, reference); returns what it posted and how many remain.';

CREATE FUNCTION finance.gl_sync() RETURNS TABLE (payments int, refunds int, vouchers int)
LANGUAGE sql AS $$
    SELECT s.payments, s.refunds, s.vouchers + s.wallet FROM finance.gl_sync(NULL::int) s
$$;
COMMENT ON FUNCTION finance.gl_sync() IS
  'Posts everything the ledger has not yet posted (V145; V409; V410, V545: by finance.gl_sync(NULL)) — the wallet''s postings counted with the vouchers here.';

-- ── 3 · approved but not paid ────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.payout_watch (
    row_no      boolean PRIMARY KEY DEFAULT true CHECK (row_no),
    unpaid_days int NOT NULL DEFAULT 7 CHECK (unpaid_days BETWEEN 1 AND 365),
    updated_by  uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.payout_watch IS 'V545: the days a refund or wallet withdrawal may wait, approved, before the Bursary is told it is not yet paid.';
SELECT audit.attach('finance.payout_watch');
INSERT INTO finance.payout_watch (row_no) VALUES (true);

CREATE FUNCTION finance.unpaid_payouts()
RETURNS TABLE (kind text, id uuid, reference text, payee text, number text, amount numeric, approved_on date, days_waiting int,
               account_ready boolean, overdue boolean)
LANGUAGE sql STABLE AS $fn$
    WITH d AS (SELECT (now() AT TIME ZONE 'Africa/Lagos')::date AS today, (SELECT unpaid_days FROM finance.payout_watch WHERE row_no) AS days),
    x AS (
        SELECT 'REFUND'::text AS kind, rf.id, rf.reference, rf.payer AS payee, coalesce(st.matric_no, st.admission_no) AS number, rf.amount,
               (rf.approved_at AT TIME ZONE 'Africa/Lagos')::date AS approved_on,
               EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = rf.id) AS account_ready
          FROM finance.refund rf LEFT JOIN people.student st ON st.id = rf.student_id
         WHERE rf.state = 'APPROVED'
        UNION ALL
        SELECT 'WALLET', w.id, 'WALLET/' || w.session || '/' || upper(left(w.id::text, 8)), s.surname || ', ' || s.other_names, coalesce(s.matric_no, s.admission_no),
               w.amount, (w.decided_at AT TIME ZONE 'Africa/Lagos')::date, true
          FROM finance.wallet_withdrawal w JOIN people.student s ON s.id = w.student_id
         WHERE w.state = 'APPROVED')
    SELECT x.kind, x.id, x.reference, x.payee, x.number, x.amount, x.approved_on, (d.today - x.approved_on)::int, x.account_ready,
           (d.today - x.approved_on) >= d.days
      FROM x CROSS JOIN d
     ORDER BY (d.today - x.approved_on) DESC, x.reference
$fn$;
COMMENT ON FUNCTION finance.unpaid_payouts() IS
  'V545: every refund and wallet withdrawal approved and not yet paid, with the days it has waited and whether that is past the days the Bursary set.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('UNPAID_PAYOUTS', 'Refunds and withdrawals approved and not yet paid',
 'To the Bursar and the Students Account Officer, once a day, when a refund or wallet withdrawal has waited approved longer than the days set',
 '[COUNT] approved refunds and withdrawals are not yet paid',
 E'Dear [FIRST_NAME],\n\n[COUNT] refunds and wallet withdrawals, [TOTAL] in all, were approved [DAYS] days or more ago and are not yet paid; the oldest has waited [OLDEST] days. Students are owed this money.\n\nThey are listed on Refunds & Credits, under Approved, not yet paid: [PORTAL_URL]\n\nMOAUM Portal',
 '[UNIVERSITY_SHORT]: [COUNT] approved refunds/withdrawals ([TOTAL]) not yet paid after [DAYS] days. See Refunds & Credits.',
 'Approved refunds not yet paid',
 '[COUNT] refunds and wallet withdrawals ([TOTAL]) were approved [DAYS] days or more ago and are not yet paid; the oldest has waited [OLDEST] days.',
 ARRAY['FIRST_NAME','COUNT','TOTAL','DAYS','OLDEST','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

/* told once a day, while any is overdue */
CREATE FUNCTION finance.watch_unpaid_payouts()
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE v_count int; v_total numeric; v_oldest int; v_days int; v_vars jsonb; p record; told int := 0;
BEGIN
    SELECT count(*), coalesce(sum(u.amount), 0), coalesce(max(u.days_waiting), 0) INTO v_count, v_total, v_oldest FROM finance.unpaid_payouts() u WHERE u.overdue;
    IF v_count = 0 THEN RETURN 0; END IF;
    SELECT unpaid_days INTO v_days FROM finance.payout_watch WHERE row_no;
    v_vars := jsonb_build_object('COUNT', v_count, 'TOTAL', 'NGN ' || to_char(v_total, 'FM999,999,999,990.00'), 'DAYS', v_days, 'OLDEST', v_oldest);
    FOR p IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
              WHERE a.office_code IN ('bursar', 'studentaccounts') AND pe.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        told := told + platform.tell_person(p.person_id, 'UNPAID_PAYOUTS', NULL, v_vars,
                                            'unpaid-payouts:' || (now() AT TIME ZONE 'Africa/Lagos')::date, ARRAY['EMAIL', 'PORTAL']);
    END LOOP;
    RETURN told;
END $fn$;
COMMENT ON FUNCTION finance.watch_unpaid_payouts() IS
  'V545: the Bursar and the Students Account Officer told, once a day, of the refunds and wallet withdrawals approved longer ago than the days set and not yet paid.';

-- ── 4 · the check digit for the newer banks whose codes are confirmed ────────────────────────────────────────────────────
UPDATE finance.bank SET nuban_check = true WHERE code IN ('101', '301', '105', '303', '103');

/* each bank's evidence: the accounts money was paid into (refunds and withdrawals paid) and how many pass its check digit */
CREATE FUNCTION finance.bank_evidence()
RETURNS TABLE (code text, paid_accounts int, passing int)
LANGUAGE sql STABLE AS $fn$
    WITH a AS (
        SELECT DISTINCT coalesce(ra.bank_code, (finance.bank_of(ra.bank_name)).code) AS code, ra.account_number AS n
          FROM finance.refund_account ra JOIN finance.refund rf ON rf.id = ra.refund_id WHERE rf.state = 'PAID'
        UNION
        SELECT DISTINCT (finance.bank_of(w.bank_name)).code, w.account_no
          FROM finance.wallet_withdrawal w WHERE w.state = 'PAID' AND w.account_no ~ '^[0-9]{10}$')
    SELECT b.code, count(a.n)::int,
           CASE WHEN b.code ~ '^[0-9]{3}$'
                THEN count(a.n) FILTER (WHERE finance.nuban_check_digit(b.code, left(a.n, 9)) = right(a.n, 1)::int)::int END
      FROM finance.bank b LEFT JOIN a ON a.code = b.code
     GROUP BY b.code
$fn$;
COMMENT ON FUNCTION finance.bank_evidence() IS
  'V545: for each bank, the accounts refunds and wallet withdrawals were paid into and, for a three-digit code, how many pass its NUBAN check digit — the Bursary''s evidence before it switches a bank''s check on.';

COMMIT;
