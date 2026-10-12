-- ═══════════════════════════════════════
-- V410 — the general-ledger sync posted in batches, with what remains counted
--
--   Since V409 the sync posts every confirmed payment of the one ledger — an applicant's, the School's, JUPEB's — not only
--   a student's. On the live register the first sync after V409 finds every earlier such payment unposted at once, and one
--   request posting tens of thousands of journals in one transaction is slow to answer and, if it fails late, posts nothing.
--   So:
--
--     · finance.gl_unposted() — what is not yet on the books: payments (a student's and every other on the ledger, on the
--       same terms the sync posts them), paid refunds and paid vouchers; the accounting overview reads it, so its count
--       now includes V409's payments too;
--     · finance.gl_sync(p_limit) — posts at most p_limit transactions, oldest first, and says how many remain; each batch
--       commits whole, each transaction posts once (by source type and reference), so an interrupted run is carried on by
--       the next, never half-posted; two syncs at once take turns;
--     · finance.gl_sync() — as it was: everything, with the same three counts.
--
--   No payment, refund, voucher or journal already posted is changed.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V410: the general-ledger sync posted in batches, with what remains counted', true);

-- ── 1 · what is not yet on the books ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.gl_unposted() RETURNS TABLE (payments bigint, refunds bigint, vouchers bigint)
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
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference))
$$;
COMMENT ON FUNCTION finance.gl_unposted() IS
  'What the general ledger has not yet posted (V410): confirmed payments — a student''s and every other on the one ledger, on the terms finance.gl_sync posts them — paid refunds and paid vouchers.';

-- ── 2 · the sync, at most p_limit at a time ──────────────────────────────────────────────────────────────────────
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

    -- paid refunds → Dr Refunds of fees, Cr Bank (Disbursements)
    IF v_room > 0 THEN
        FOR r IN
            SELECT rf.reference, rf.paid_at::date AS d, rf.amount, rf.reason
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
  'Posts at most p_limit transactions the ledger has not yet posted (V410; NULL is every one): confirmed payments oldest first — a student''s by its purpose words (V145), every other on the one ledger by the income account of its purpose (V409) — then paid refunds and paid vouchers, each once by (source type, reference); returns what it posted and how many remain. Each batch commits whole; two syncs at once take turns.';

-- ── 3 · the sync as it was: everything at once ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.gl_sync() RETURNS TABLE (payments int, refunds int, vouchers int)
LANGUAGE sql AS $$
    SELECT s.payments, s.refunds, s.vouchers FROM finance.gl_sync(NULL::int) s
$$;
COMMENT ON FUNCTION finance.gl_sync() IS
  'Posts everything the ledger has not yet posted (V145; V409; V410: by finance.gl_sync(NULL)) — every confirmed payment, paid refund and paid voucher, each once by (source type, reference).';

COMMIT;
