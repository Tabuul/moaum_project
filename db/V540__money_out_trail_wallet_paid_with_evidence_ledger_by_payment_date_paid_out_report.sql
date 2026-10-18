-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V540 — The money-out trail finished: a wallet withdrawal paid with its evidence, the ledger dating a refund by the day the
--        money left, and the Paid-out report for Internal Audit
--
--   1 · A NELFUND wallet withdrawal was marked paid with an optional reference. Like a refund (V534) it is now paid with the bank
--       transfer reference (4 to 60 letters and digits) and the date the money left — not after today, not before it was
--       approved (finance.pay_withdrawal(id, reference, paid on); the database refuses PAID without them, WALLET_PAID_EVIDENCE).
--       The student is told both; the Bursary's queue and the student's wallet show them.
--   2 · The general ledger posted a paid refund on the day Mark paid was pressed. It now posts it on the day the money left
--       (finance.refund.paid_on, V534), the day it was recorded where that is not known. Journals already posted are not moved.
--   3 · finance.paid_out(from, to): every refund and wallet withdrawal paid between two dates (by the day the money left) with the
--       payee, the account it went to, the amount, the bank transfer reference, who approved and who paid it, and how many other
--       payments carry the same reference — for Internal Audit to tick against the bank statement.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V540: the money-out trail — wallet withdrawals paid with evidence, the ledger by the payment date, the Paid-out report', true);

-- ── 1 · a wallet withdrawal paid with its evidence ────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.wallet_withdrawal ADD COLUMN paid_on date NULL;
COMMENT ON COLUMN finance.wallet_withdrawal.paid_on IS 'V540: the date the money left the University''s account; paid_at is when it was recorded, paid_ref the bank transfer reference.';

DROP FUNCTION finance.pay_withdrawal(uuid, text);
CREATE FUNCTION finance.pay_withdrawal(p_id uuid, p_ref text, p_paid_on date)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal; v_actor uuid; v_entry uuid; v_avail numeric; reach record; v_ref text := btrim(coalesce(p_ref, ''));
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_day text;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payout is made by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'withdrawal % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF r.decided_by = v_actor THEN
        RAISE EXCEPTION 'the officer who approved a withdrawal does not also pay it' USING ERRCODE = '23514',
            HINT = 'A second officer records the payout.';
    END IF;
    -- V540: the evidence — the bank transfer reference and the date the money left
    IF length(v_ref) NOT BETWEEN 4 AND 60 OR v_ref !~ '^[A-Za-z0-9][A-Za-z0-9/._: -]*$' THEN
        RAISE EXCEPTION 'WALLET_PAID_REFERENCE: give the bank transfer reference the refund was paid with (4 to 60 letters and digits)' USING ERRCODE = '23514',
            HINT = 'It is on the bank''s confirmation of the transfer; Internal Audit matches it to the bank statement.';
    END IF;
    IF p_paid_on IS NULL OR p_paid_on > v_today THEN
        RAISE EXCEPTION 'WALLET_PAID_DATE: give the date the money left, today or before' USING ERRCODE = '23514';
    END IF;
    IF p_paid_on < (r.decided_at AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'WALLET_PAID_DATE: the withdrawal was approved on %; it was not paid before that', to_char(r.decided_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY')
            USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
    IF r.source_code IS NULL THEN
        v_avail := finance.wallet_balance(r.student_id);
    ELSE
        SELECT coalesce(sum(b.available), 0) INTO v_avail FROM finance.wallet_balances(r.student_id) b WHERE b.source_code = r.source_code;
    END IF;
    IF v_avail < r.amount THEN
        RAISE EXCEPTION 'the wallet no longer holds NGN % of %', r.amount, coalesce(r.source_code, 'funding') USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
    VALUES (r.student_id, r.session, 'REFUND', r.amount, v_ref,
            'Refunded to ' || r.bank_name || ' ' || r.account_no || CASE WHEN r.source_code IS NOT NULL THEN ' from ' || r.source_code ELSE '' END, r.source_code)
    RETURNING id INTO v_entry;
    UPDATE finance.wallet_withdrawal SET state = 'PAID', paid_at = now(), paid_by = v_actor, paid_ref = v_ref, paid_on = p_paid_on, entry_id = v_entry
     WHERE id = p_id
    RETURNING * INTO r;
    v_day := to_char(p_paid_on, 'FMDD FMMonth YYYY');
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund is paid',
        'NGN ' || r.amount::text || ' for ' || r.session || ' was paid to ' || r.bank_name || ' ' || r.account_no || ' on ' || v_day
        || ' (bank transfer reference ' || v_ref || '). Quote the reference to your bank if the money has not arrived.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your refund is paid',
        'MOAUM: refund of NGN ' || r.amount::text || ' paid to ' || r.bank_name || ' on ' || v_day || ', ref ' || v_ref || '.', 'student', r.student_id);
    RETURN r;
END $$;
COMMENT ON FUNCTION finance.pay_withdrawal(uuid, text, date) IS
  'V079, V327, V540: an approved wallet withdrawal paid by a second officer — the money leaves the wallet as a REFUND of its source — with the bank transfer reference and the date the money left (not after today, not before approval); the student told both.';

/* paid only with its evidence, whatever records it */
CREATE FUNCTION finance.trg_withdrawal_paid_evidence()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID' AND (NEW.paid_ref IS NULL OR NEW.paid_on IS NULL) THEN
        RAISE EXCEPTION 'WALLET_PAID_EVIDENCE: a withdrawal is marked paid with the bank transfer reference and the date the money left' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_withdrawal_paid_evidence BEFORE UPDATE OF state ON finance.wallet_withdrawal
    FOR EACH ROW EXECUTE FUNCTION finance.trg_withdrawal_paid_evidence();

-- the Bursary's queue (V327), with the date the money left
DROP FUNCTION finance.withdrawal_queue(text);
CREATE FUNCTION finance.withdrawal_queue(p_session text)
RETURNS TABLE (id uuid, student_id uuid, matric_no text, student_name text, session text, amount numeric, source_code text,
               bank_name text, account_no text, account_name text, state text, reason text,
               requested_at timestamptz, decided_at timestamptz, paid_at timestamptz, paid_ref text, paid_on date)
LANGUAGE sql STABLE AS $$
    SELECT w.id, w.student_id, s.matric_no, s.surname || ', ' || s.other_names, w.session, w.amount, coalesce(w.source_code, 'NELFUND'),
           w.bank_name, w.account_no, w.account_name, w.state, w.reason,
           w.requested_at, w.decided_at, w.paid_at, w.paid_ref, w.paid_on
      FROM finance.wallet_withdrawal w JOIN people.student s ON s.id = w.student_id
     WHERE p_session IS NULL OR w.session = p_session
     ORDER BY CASE w.state WHEN 'REQUESTED' THEN 0 WHEN 'APPROVED' THEN 1 ELSE 2 END, w.requested_at DESC
$$;

-- ── 2 · the ledger dates a paid refund by the day the money left ─────────────────────────────────────────────────────────
-- finance.gl_sync(int) as V410 left it, but for the date a paid refund is posted on
CREATE OR REPLACE FUNCTION finance.gl_sync(p_limit int)
RETURNS TABLE (payments int, refunds int, vouchers int, remaining bigint)
LANGUAGE plpgsql AS $$
DECLARE r record; v_p int := 0; v_r int := 0; v_v int := 0; v_room int;
BEGIN
    IF p_limit IS NOT NULL AND p_limit < 1 THEN
        RAISE EXCEPTION 'A ledger sync posts at least one transaction at a time' USING ERRCODE = '22023';
    END IF;
    -- two syncs at once take turns: the second finds what the first posted and carries on from there
    PERFORM pg_advisory_xact_lock(hashtext('finance.gl_sync'));
    v_room := coalesce(p_limit, 2147483647);

    -- confirmed student payments → Dr Bank (Collections), Cr the income account
    FOR r IN
        SELECT pr.reference, pr.confirmed_at::date AS d, pr.amount, pr.session,
               finance.payment_category(pr.purpose) AS cat, pr.purpose
          FROM finance.payment_reference pr
         WHERE pr.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference)
         ORDER BY pr.confirmed_at, pr.reference
         LIMIT v_room
    LOOP
        PERFORM finance.gl_post(r.d, 'Fee receipt ' || r.reference || ' — ' || r.cat, 'AUTO', 'PAYMENT', r.reference,
            jsonb_build_array(
                jsonb_build_object('account','1010','debit', r.amount, 'narration', r.purpose, 'session', r.session),
                jsonb_build_object('account', finance.gl_income_account(r.cat), 'credit', r.amount, 'narration', r.purpose, 'session', r.session)));
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

    -- paid refunds → Dr Refunds of fees, Cr Bank (Disbursements); V540: on the day the money left (V534), else the day recorded
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
    END IF;

    payments := v_p; refunds := v_r; vouchers := v_v;
    SELECT u.payments + u.refunds + u.vouchers INTO remaining FROM finance.gl_unposted() u;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION finance.gl_sync(int) IS
  'Posts at most p_limit transactions the ledger has not yet posted (V410; NULL is every one): confirmed payments oldest first — a student''s by its purpose words (V145), every other on the one ledger by the income account of its purpose (V409) — then paid refunds (V540: on the day the money left) and paid vouchers, each once by (source type, reference); returns what it posted and how many remain. Each batch commits whole; two syncs at once take turns.';

-- ── 3 · the Paid-out report ───────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.paid_out(p_from date, p_to date)
RETURNS TABLE (kind text, reference text, payee text, number text, bank_name text, account_number text, account_name text, amount numeric,
               paid_on date, transfer_reference text, approved_by_name text, paid_by_name text, recorded_at timestamptz, same_reference int)
LANGUAGE sql STABLE AS $fn$
    WITH x AS (
        -- refunds: the full account on record, else what was kept when it was raised
        SELECT 'REFUND'::text AS kind, rf.reference, rf.payer AS payee,
               coalesce(st.matric_no, st.admission_no, ja.application_no) AS number,
               coalesce(ra.bank_name, rf.bank_name) AS bank_name,
               coalesce(ra.account_number, CASE WHEN rf.account_last4 IS NULL THEN NULL ELSE '••••••' || rf.account_last4 END) AS account_number,
               coalesce(ra.account_name, rf.account_name) AS account_name, rf.amount,
               coalesce(rf.paid_on, (rf.paid_at AT TIME ZONE 'Africa/Lagos')::date) AS paid_on, rf.paid_reference AS transfer_reference,
               rf.approved_by, rf.paid_by, rf.paid_at AS recorded_at
          FROM finance.refund rf
          LEFT JOIN finance.refund_account ra ON ra.refund_id = rf.id
          LEFT JOIN people.student st ON st.id = rf.student_id
          LEFT JOIN jupeb.refund_claim_refund xr ON xr.refund_id = rf.id
          LEFT JOIN jupeb.refund_claim jc ON jc.id = xr.claim_id
          LEFT JOIN jupeb.application ja ON ja.id = jc.application_id
         WHERE rf.state = 'PAID'
        UNION ALL
        -- wallet withdrawals: the student's own account, given when it was requested
        SELECT 'WALLET', 'WALLET/' || w.session || '/' || upper(left(w.id::text, 8)), s.surname || ', ' || s.other_names,
               coalesce(s.matric_no, s.admission_no), w.bank_name, w.account_no, w.account_name, w.amount,
               coalesce(w.paid_on, (w.paid_at AT TIME ZONE 'Africa/Lagos')::date), w.paid_ref,
               w.decided_by, w.paid_by, w.paid_at
          FROM finance.wallet_withdrawal w JOIN people.student s ON s.id = w.student_id
         WHERE w.state = 'PAID'),
    y AS (SELECT x.*, CASE WHEN x.transfer_reference IS NULL THEN 0
                           ELSE (count(*) OVER (PARTITION BY upper(x.transfer_reference)) - 1)::int END AS same_reference
            FROM x)
    SELECT y.kind, y.reference, y.payee, y.number, y.bank_name, y.account_number, y.account_name, y.amount, y.paid_on, y.transfer_reference,
           CASE WHEN ap.id IS NULL THEN NULL ELSE ap.surname || ', ' || ap.given_names END,
           CASE WHEN pp.id IS NULL THEN NULL ELSE pp.surname || ', ' || pp.given_names END,
           y.recorded_at, y.same_reference
      FROM y
      LEFT JOIN iam.person ap ON ap.id = y.approved_by
      LEFT JOIN iam.person pp ON pp.id = y.paid_by
     WHERE y.paid_on BETWEEN p_from AND p_to
     ORDER BY y.paid_on, y.transfer_reference NULLS LAST, y.reference
$fn$;
COMMENT ON FUNCTION finance.paid_out(date, date) IS
  'V540: every refund and wallet withdrawal paid between two dates (by the day the money left): the payee, the account it went to, the amount, the bank transfer reference, who approved and who paid it, when it was recorded, and how many other payments carry the same reference — for Internal Audit to match to the bank statement.';

COMMIT;
