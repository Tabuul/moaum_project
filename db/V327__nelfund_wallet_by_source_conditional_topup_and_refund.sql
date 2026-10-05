-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V327 — the funding wallet keeps every naira to its source: a top-up only for a school-fee shortfall, a refund only of
--        what may be refunded, and the old portal's NELFUND payments reconciled onto the same ledger
--
--   What existed (V033, V079): one append-only ledger, finance.wallet_entry, whose credits carry a funding source (NELFUND
--   a LOAN, a scholarship a GRANT, a top-up the student's own SELF money), a balance derived from it, a remittance split
--   against the register, the wallet applied to the session charge through the same confirmation as every payment, a
--   free top-up reference, and a withdrawal of the leftover balance requested by the student, approved by the Bursary
--   and paid by a second officer. What it did not do: the balance was one pool — applying it and withdrawing it took no
--   notice of the source, so a scholarship could have left the University as a "refund", a student's own top-up could
--   have been counted as the Fund's money, and nothing stopped a student topping the wallet up for no reason at all.
--
--   Now, on the same ledger, the same tables, the same desks:
--     · finance.wallet_balances(student) and finance.wallet_balances_session(student, session) say, per source, what
--       was credited, applied, reversed, refunded, held for a pending refund, and what is available; the pooled
--       finance.wallet_balance stays as the sum of them;
--     · finance.apply_wallet settles the charge source by source in the order the Bursar's policy states (loan first,
--       then grants, then the student's own money by default), writing one APPLIED entry per source consumed, so every
--       naira that paid a fee is traceable to where it came from;
--     · a top-up is a conditional act: finance.topup_eligibility(student, session) works out the fees due, what is
--       paid, what the wallet can still cover and the exact shortfall, and finance.wallet_topup_reference refuses a
--       reference when nothing is short, when the amount exceeds the shortfall (unless the policy says otherwise), or
--       when the school-fees window is closed — recomputed at the moment of the request under a per-student lock, an
--       earlier unpaid top-up reference expired, the reasoning written on the reference for the record;
--     · a refund (the withdrawal of V079) is of ONE source: NELFUND money that arrived after the session's fees were
--       settled, or the student's own leftover — never a grant; finance.withdrawal_eligibility says, per source and for
--       that session alone, what is refundable and why not otherwise; the paid refund debits that source; the student
--       is told at each step;
--     · a Bursary hand credit names its source: a credit of unknown source is no longer written (what is already on the
--       ledger without one is reported as unattributed, applied last, never refundable);
--     · the old portal's NELFUND payments: staged as the export gives them (written once), matched by strong
--       identifiers only — never a name — validated by status, amount and session, posted to the wallet as NELFUND
--       credits of the session they belong to, once, with the old reference and date kept; what cannot be reconciled
--       waits in a queue for a Finance officer; the student sees the funding, its source and its date;
--     · finance.nelfund_desk_figures and finance.nelfund_student_rows answer the Bursary's questions — received, funded,
--       applied, remaining, refundable, refunds by state, old-portal money posted or waiting, who is short and by how
--       much — set-based, over the funded population.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V327: the funding wallet by source — conditional top-up, refund of what may be refunded, old-portal NELFUND payments reconciled', true);

-- ── 1 · the policy, a setting the Bursar keeps ─────────────────────────────────────────────────────────────────
CREATE TABLE finance.wallet_setting (
    one                   boolean PRIMARY KEY DEFAULT true CHECK (one),
    apply_order           text[]  NOT NULL DEFAULT ARRAY['LOAN', 'GRANT', 'SELF'],
    topup_over_shortfall  boolean NOT NULL DEFAULT false,
    refund_natures        text[]  NOT NULL DEFAULT ARRAY['LOAN', 'SELF'],
    updated_by            uuid NULL,
    updated_office        text NULL,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ws_order CHECK (apply_order <@ ARRAY['LOAN', 'GRANT', 'SELF'] AND cardinality(apply_order) = 3),
    CONSTRAINT ck_ws_refund CHECK (refund_natures <@ ARRAY['LOAN', 'GRANT', 'SELF'])
);
COMMENT ON TABLE finance.wallet_setting IS
  'The wallet policy (V327), one row: the order the sources settle a charge in (by nature — LOAN, GRANT, SELF), whether a top-up may exceed the school-fee shortfall (no, by default), and which natures a student may have refunded (the loan that arrived after the fees were settled, and their own money; never a grant).';
INSERT INTO finance.wallet_setting (one) VALUES (true);
SELECT audit.attach('finance.wallet_setting');

CREATE OR REPLACE FUNCTION finance.set_wallet_policy(p_order text[], p_over boolean, p_refund text[])
RETURNS finance.wallet_setting LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_setting; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'WALLET_ACTOR_REQUIRED: the wallet policy is set by a person' USING ERRCODE = '23514'; END IF;
    UPDATE finance.wallet_setting
       SET apply_order = coalesce(p_order, apply_order), topup_over_shortfall = coalesce(p_over, topup_over_shortfall),
           refund_natures = coalesce(p_refund, refund_natures), updated_by = v_actor, updated_office = nullif(current_setting('moaum.actor_office', true), ''), updated_at = now()
     WHERE one RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 2 · the ledger rows say more: where a credit came from, which source a refund draws on ─────────────────────
ALTER TABLE finance.wallet_withdrawal ADD COLUMN IF NOT EXISTS source_code text NULL REFERENCES finance.funding_source(code);
COMMENT ON COLUMN finance.wallet_withdrawal.source_code IS 'V327: the one source this refund draws on (NELFUND, SELF…); NULL on requests made before V327, read as the pooled balance.';

-- ── 3 · the balances, by source ────────────────────────────────────────────────────────────────────────────────
-- credits and top-ups count for their source; an entry without a source is "UNATTRIBUTED" (a hand credit made before
-- V327 named one) — it is money the student may apply, never money that is refunded
CREATE OR REPLACE FUNCTION finance.wallet_balances(p_student uuid)
RETURNS TABLE (source_code text, source_name text, nature text, credited numeric, applied numeric, reversed numeric, refunded numeric, held numeric, available numeric)
LANGUAGE sql STABLE AS $$
    WITH e AS (
        SELECT coalesce(e.source_code, 'UNATTRIBUTED') AS src, e.kind, e.amount
          FROM finance.wallet_entry e WHERE e.student_id = p_student),
    holds AS (
        SELECT coalesce(w.source_code, 'NELFUND') AS src, sum(w.amount) AS held
          FROM finance.wallet_withdrawal w WHERE w.student_id = p_student AND w.state IN ('REQUESTED', 'APPROVED') GROUP BY 1),
    s AS (
        SELECT e.src,
               coalesce(sum(e.amount) FILTER (WHERE e.kind IN ('CREDIT', 'TOPUP')), 0) AS credited,
               coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied,
               coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REVERSED'), 0) AS reversed,
               coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded
          FROM e GROUP BY e.src)
    SELECT s.src, coalesce(fs.name, 'Unattributed credit'), coalesce(fs.nature, 'UNKNOWN'),
           s.credited, s.applied, s.reversed, s.refunded, coalesce(h.held, 0),
           greatest(s.credited - s.applied - s.reversed - s.refunded, 0)
      FROM s LEFT JOIN finance.funding_source fs ON fs.code = s.src LEFT JOIN holds h ON h.src = s.src
     ORDER BY CASE coalesce(fs.nature, 'UNKNOWN') WHEN 'LOAN' THEN 0 WHEN 'GRANT' THEN 1 WHEN 'SELF' THEN 2 ELSE 3 END, (s.src = 'NELFUND') DESC, s.src
$$;
COMMENT ON FUNCTION finance.wallet_balances(uuid) IS 'The wallet by source (V327): credited, applied to fees, reversed, refunded, held for a pending refund, available — one row per source the ledger names, plus UNATTRIBUTED for credits made without one.';

-- the same, for the entries of ONE session: a refund is session-aware (the Fund''s money for 2026/2027 is not the
-- leftover of 2025/2026), and the desk reads a session at a time
CREATE OR REPLACE FUNCTION finance.wallet_balances_session(p_student uuid, p_session text)
RETURNS TABLE (source_code text, source_name text, nature text, credited numeric, applied numeric, reversed numeric, refunded numeric, held numeric, available numeric)
LANGUAGE sql STABLE AS $$
    WITH e AS (
        SELECT coalesce(e.source_code, 'UNATTRIBUTED') AS src, e.kind, e.amount
          FROM finance.wallet_entry e WHERE e.student_id = p_student AND e.session = p_session),
    holds AS (
        SELECT coalesce(w.source_code, 'NELFUND') AS src, sum(w.amount) AS held
          FROM finance.wallet_withdrawal w WHERE w.student_id = p_student AND w.session = p_session AND w.state IN ('REQUESTED', 'APPROVED') GROUP BY 1),
    s AS (
        SELECT e.src,
               coalesce(sum(e.amount) FILTER (WHERE e.kind IN ('CREDIT', 'TOPUP')), 0) AS credited,
               coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied,
               coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REVERSED'), 0) AS reversed,
               coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded
          FROM e GROUP BY e.src)
    SELECT s.src, coalesce(fs.name, 'Unattributed credit'), coalesce(fs.nature, 'UNKNOWN'),
           s.credited, s.applied, s.reversed, s.refunded, coalesce(h.held, 0),
           greatest(s.credited - s.applied - s.reversed - s.refunded, 0)
      FROM s LEFT JOIN finance.funding_source fs ON fs.code = s.src LEFT JOIN holds h ON h.src = s.src
     ORDER BY CASE coalesce(fs.nature, 'UNKNOWN') WHEN 'LOAN' THEN 0 WHEN 'GRANT' THEN 1 WHEN 'SELF' THEN 2 ELSE 3 END, (s.src = 'NELFUND') DESC, s.src
$$;

-- ── 4 · applying the wallet: source by source, in the policy's order; one reference, one confirmation ─────────
CREATE OR REPLACE FUNCTION finance.apply_wallet(p_student uuid, p_session text, p_amount numeric)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE pos record; v_bal numeric; v_amount numeric; v_ref text; v_left numeric; b record; v_take numeric; v_split text := '';
        v_order text[];
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || p_student::text));
    SELECT apply_order INTO v_order FROM finance.wallet_setting WHERE one;
    v_bal := finance.wallet_balance(p_student);
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    v_amount := least(coalesce(p_amount, v_bal), v_bal, pos.balance);
    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION 'WALLET_NOTHING_TO_APPLY: nothing to apply: the wallet holds NGN % and the balance for % is NGN %', v_bal, p_session, pos.balance USING ERRCODE = '23514',
            HINT = 'The wallet pays the session charge, and only what is outstanding on it.';
    END IF;
    v_ref := finance.new_reference(p_student, p_session, v_amount, NULL);
    v_left := v_amount;
    FOR b IN
        SELECT w.source_code, w.available, w.nature FROM finance.wallet_balances(p_student) w
         WHERE w.available > 0
         ORDER BY coalesce(array_position(v_order, w.nature), 9), (w.source_code = 'NELFUND') DESC, w.source_code
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := least(b.available, v_left);
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
        VALUES (p_student, p_session, 'APPLIED', v_take, v_ref, 'Applied to the ' || p_session || ' charge from ' || b.source_code,
                CASE WHEN b.source_code = 'UNATTRIBUTED' THEN NULL ELSE b.source_code END);
        v_split := v_split || CASE WHEN v_split = '' THEN '' ELSE '; ' END || b.source_code || ' ' || v_take::text;
        v_left := v_left - v_take;
    END LOOP;
    IF v_left > 0 THEN
        RAISE EXCEPTION 'WALLET_SHORT: the wallet''s sources add up to less than NGN %', v_amount USING ERRCODE = '23514';
    END IF;
    PERFORM finance.confirm_payment(v_ref, 'NELFUND wallet', 'applied by the student from the wallet: ' || v_split);
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION finance.apply_wallet(uuid, text, numeric) IS
  'The wallet applied to the session charge (V033, by source since V327): what is outstanding, up to the balance, taken source by source in the policy''s order (loan, grant, own money by default) — one APPLIED entry per source consumed, one reference, confirmed through the same path as every payment, the split on the note.';

-- a reversal to the Fund takes only the Fund''s own money that is still available
CREATE OR REPLACE FUNCTION finance.reverse_nelfund_row(p_row uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r finance.nelfund_row; b finance.nelfund_batch; v_avail numeric;
BEGIN
    SELECT * INTO r FROM finance.nelfund_row WHERE id = p_row FOR UPDATE;
    IF NOT FOUND OR r.state = 'REVERSED' THEN RAISE EXCEPTION 'row % is not reversible', p_row USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a reversal to the Fund says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO b FROM finance.nelfund_batch WHERE id = r.batch_id;
    IF r.state = 'MATCHED' AND r.student_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
        SELECT coalesce(sum(w.available - w.held), 0) INTO v_avail FROM finance.wallet_balances(r.student_id) w WHERE w.source_code = 'NELFUND';
        IF v_avail < r.amount THEN
            RAISE EXCEPTION 'the Fund''s money has been applied; NGN % cannot be reversed from it', r.amount USING ERRCODE = '23514',
                HINT = 'A credit already applied to an invoice is recovered from the student, not reversed to the Fund.';
        END IF;
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
        VALUES (r.student_id, b.session, 'REVERSED', r.amount, b.ref, 'Reversed to the Fund: ' || btrim(p_why), 'NELFUND');
    END IF;
    UPDATE finance.nelfund_row SET state = 'REVERSED', why = btrim(p_why), decided_at = now() WHERE id = p_row;
END $$;

-- ── 5 · the conditional top-up ─────────────────────────────────────────────────────────────────────────────────
-- the one calculation: fees due, paid, outstanding; what the wallet can still cover; the shortfall; whether a top-up
-- is allowed now and, if not, the one reason; the window the school-fees payment is in
CREATE OR REPLACE FUNCTION finance.topup_eligibility(p_student uuid, p_session text)
RETURNS TABLE (allowed boolean, reason text, due numeric, paid numeric, outstanding numeric, wallet_available numeric, nelfund_available numeric,
               other_available numeric, self_available numeric, shortfall numeric, max_topup numeric, window_state text, over_shortfall_allowed boolean,
               open_reference text)
LANGUAGE plpgsql STABLE AS $$
DECLARE pos record; win record; v_status text; v_wallet numeric; v_nelfund numeric; v_other numeric; v_self numeric; v_short numeric; v_over boolean;
        v_reason text; v_open text;
BEGIN
    SELECT s.status INTO v_status FROM people.student s WHERE s.id = p_student;
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    SELECT * INTO win FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL);
    SELECT coalesce(sum(w.available), 0),
           coalesce(sum(w.available) FILTER (WHERE w.source_code = 'NELFUND'), 0),
           coalesce(sum(w.available) FILTER (WHERE w.source_code <> 'NELFUND' AND w.nature <> 'SELF'), 0),
           coalesce(sum(w.available) FILTER (WHERE w.nature = 'SELF'), 0)
      INTO v_wallet, v_nelfund, v_other, v_self
      FROM finance.wallet_balances(p_student) w;
    SELECT topup_over_shortfall INTO v_over FROM finance.wallet_setting WHERE one;
    v_short := greatest(coalesce(pos.balance, 0) - v_wallet, 0);
    SELECT r.reference INTO v_open FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Wallet top-up%' AND r.confirmed_at IS NULL AND r.expires_at > now()
     ORDER BY r.generated_at DESC LIMIT 1;
    v_reason := CASE
        WHEN v_status IS NULL THEN 'NO_SUCH_STUDENT'
        WHEN v_status IN ('WITHDRAWN', 'EXPELLED', 'TRANSFERRED_OUT', 'DECEASED', 'GRADUATED', 'RUSTICATED') THEN 'STUDENT_INACTIVE'
        WHEN coalesce(pos.due, 0) = 0 THEN 'NO_CHARGE_STATED'
        WHEN coalesce(pos.balance, 0) <= 0 THEN 'FEES_SETTLED'
        WHEN v_short <= 0 THEN 'NO_SHORTFALL'
        WHEN win.state <> 'OPEN' THEN 'WINDOW_CLOSED'
        ELSE 'ALLOWED' END;
    RETURN QUERY SELECT v_reason = 'ALLOWED', v_reason, coalesce(pos.due, 0), coalesce(pos.paid, 0), coalesce(pos.balance, 0),
                        v_wallet, v_nelfund, v_other, v_self, v_short,
                        CASE WHEN v_reason = 'ALLOWED' THEN v_short ELSE 0 END, win.state, coalesce(v_over, false), v_open;
END $$;
COMMENT ON FUNCTION finance.topup_eligibility(uuid, text) IS
  'Whether a student may top the wallet up for a session, and why not otherwise (V327): the fees due and paid (finance.position), what the wallet''s sources can still cover, the exact shortfall — a top-up is allowed only for a shortfall, only while the school-fees window is open, and only up to the shortfall unless the policy allows more. Reasons: STUDENT_INACTIVE, NO_CHARGE_STATED, FEES_SETTLED, NO_SHORTFALL, WINDOW_CLOSED, ALLOWED.';

-- a top-up reference is issued only for the shortfall the server itself works out at that moment, under a per-student
-- lock; any earlier unpaid top-up reference for the session is expired so a stale one cannot be paid; the reasoning
-- is written on the reference
CREATE OR REPLACE FUNCTION finance.wallet_topup_reference(p_student uuid, p_session text, p_amount numeric)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE e record; v_ref text; v_amount numeric;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || p_student::text));
    SELECT * INTO e FROM finance.topup_eligibility(p_student, p_session);
    IF NOT e.allowed THEN
        RAISE EXCEPTION 'WALLET_TOPUP_NOT_REQUIRED: % — %', e.reason,
            CASE e.reason WHEN 'FEES_SETTLED' THEN 'your school fees for ' || p_session || ' are settled; nothing is owed'
                          WHEN 'NO_SHORTFALL' THEN 'your funding of NGN ' || e.wallet_available::text || ' already covers the NGN ' || e.outstanding::text || ' outstanding; apply it instead'
                          WHEN 'NO_CHARGE_STATED' THEN 'no charge is stated for ' || p_session || ' yet'
                          WHEN 'WINDOW_CLOSED' THEN 'school fees payment is ' || lower(coalesce(e.window_state, 'closed')) || ' for ' || p_session
                          WHEN 'STUDENT_INACTIVE' THEN 'the student is not in study'
                          ELSE 'a top-up is not required' END
            USING ERRCODE = '23514',
                  HINT = CASE e.reason WHEN 'NO_SHORTFALL' THEN 'Apply the wallet to the charge from the Wallet screen; a top-up is only for what the wallet cannot cover.'
                                       ELSE 'A top-up is only for a school-fee shortfall the wallet cannot cover.' END;
    END IF;
    v_amount := coalesce(p_amount, e.max_topup);
    IF v_amount <= 0 THEN RAISE EXCEPTION 'WALLET_TOPUP_AMOUNT: a top-up is for an amount above zero' USING ERRCODE = '23514'; END IF;
    IF v_amount > e.max_topup AND NOT e.over_shortfall_allowed THEN
        RAISE EXCEPTION 'WALLET_TOPUP_ABOVE_SHORTFALL: the shortfall is NGN %; a top-up of NGN % is more than is required', e.max_topup, v_amount USING ERRCODE = '23514',
            HINT = 'Top up exactly the shortfall; the University''s policy does not allow more.';
    END IF;
    -- an earlier unpaid top-up reference for this session is retired: the shortfall is worked out afresh each time
    UPDATE finance.payment_reference SET expires_at = now()
     WHERE student_id = p_student AND session = p_session AND purpose LIKE 'Wallet top-up%' AND confirmed_at IS NULL AND expires_at > now();
    v_ref := finance.new_purpose_reference(p_student, p_session, v_amount, 'Wallet top-up ' || p_session);
    UPDATE finance.payment_reference
       SET note = 'Shortfall top-up: fees ' || e.due::text || ', paid ' || e.paid::text || ', NELFUND available ' || e.nelfund_available::text
                  || ', other funding ' || e.other_available::text || ', own money ' || e.self_available::text || ', outstanding ' || e.outstanding::text
                  || ', shortfall ' || e.shortfall::text || ', top-up ' || v_amount::text
     WHERE reference = v_ref;
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION finance.wallet_topup_reference(uuid, text, numeric) IS
  'A top-up reference for a school-fee shortfall (V327): issued only when finance.topup_eligibility allows it, for at most the shortfall unless the policy says otherwise, recomputed under a per-student lock at the moment of the request; earlier unpaid top-up references for the session are expired; the calculation is written on the reference. Confirmed, it credits the wallet as the student''s own money (SELF), never as the Fund''s.';

-- ── 6 · a hand credit names its source ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.credit_wallet(p_student uuid, p_session text, p_amount numeric, p_reason text, p_source text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_src text := nullif(upper(btrim(coalesce(p_source, ''))), '');
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
    IF v_src IS NULL THEN
        RAISE EXCEPTION 'WALLET_SOURCE_REQUIRED: a wallet credit names the source the money came from' USING ERRCODE = '23514',
            HINT = 'NELFUND, a scholarship, a sponsor — choose the source from the settings, or add it first. Money of no known source is never written to a wallet.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.funding_source WHERE code = v_src AND active) THEN
        RAISE EXCEPTION 'no funding source is coded %', v_src USING ERRCODE = '23503',
            HINT = 'Choose a source from the settings, or add it first.';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
    VALUES (p_student, p_session, 'CREDIT', p_amount, v_src, 'Bursary credit: ' || btrim(p_reason), v_src)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- ── 7 · the refund: of one source, for one session, only what may be refunded ──────────────────────────────────
DROP FUNCTION IF EXISTS finance.withdrawal_eligibility(uuid, text);
CREATE OR REPLACE FUNCTION finance.withdrawal_eligibility(p_student uuid, p_session text)
RETURNS TABLE (eligible boolean, balance numeric, cleared boolean, arrears boolean, pending boolean, reason text,
               nelfund_refundable numeric, self_refundable numeric, grant_held numeric, nelfund_after_settlement boolean, refund_natures text[])
LANGUAGE plpgsql STABLE AS $$
DECLARE pos record; v_pending boolean; v_nel numeric := 0; v_self numeric := 0; v_grant numeric := 0; v_natures text[]; v_after boolean := false;
        v_total numeric;
BEGIN
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    SELECT ws.refund_natures INTO v_natures FROM finance.wallet_setting ws WHERE ws.one;
    v_pending := EXISTS (SELECT 1 FROM finance.wallet_withdrawal w WHERE w.student_id = p_student AND w.state IN ('REQUESTED', 'APPROVED'));
    SELECT coalesce(sum(greatest(b.available - b.held, 0)) FILTER (WHERE b.nature = 'LOAN' AND 'LOAN' = ANY (v_natures)), 0),
           coalesce(sum(greatest(b.available - b.held, 0)) FILTER (WHERE b.nature = 'SELF' AND 'SELF' = ANY (v_natures)), 0),
           coalesce(sum(b.available) FILTER (WHERE b.nature = 'GRANT'), 0)
      INTO v_nel, v_self, v_grant
      FROM finance.wallet_balances_session(p_student, p_session) b;
    -- the Fund's money arrived after the session's fees were settled by other means: nothing of it was applied
    v_after := pos.paid_in_full AND v_nel > 0
               AND NOT EXISTS (SELECT 1 FROM finance.wallet_entry e WHERE e.student_id = p_student AND e.session = p_session AND e.kind = 'APPLIED' AND e.source_code = 'NELFUND');
    -- nothing is refundable until the session's fees are settled and nothing is in arrears: the wallet pays them first
    IF NOT pos.paid_in_full OR pos.has_arrears THEN v_nel := 0; v_self := 0; END IF;
    v_total := v_nel + v_self;
    RETURN QUERY SELECT
        (pos.paid_in_full AND NOT pos.has_arrears AND v_total > 0 AND NOT v_pending),
        v_total, pos.paid_in_full, pos.has_arrears, v_pending,
        CASE WHEN v_pending THEN 'A refund is already awaiting the Bursary.'
             WHEN NOT pos.paid_in_full THEN 'The ' || p_session || ' fees are not yet cleared in full; the wallet pays them first.'
             WHEN pos.has_arrears THEN 'There are fees owed from a previous session.'
             WHEN v_total <= 0 AND v_grant > 0 THEN 'What remains in the wallet is a grant, which is not refunded to the student.'
             WHEN v_total <= 0 THEN 'The wallet holds nothing that may be refunded for ' || p_session || '.'
             ELSE 'NGN ' || v_total::text || ' may be refunded to your own bank account.' END,
        v_nel, v_self, v_grant, v_after, v_natures;
END $$;
COMMENT ON FUNCTION finance.withdrawal_eligibility(uuid, text) IS
  'What a student may have refunded for a session, by source (V327): the Fund''s money left after that session''s fees are settled (NELFUND) and their own leftover (SELF) — the natures the policy names — never a grant; only once the fees are cleared and nothing is in arrears, net of a refund already pending.';

DROP FUNCTION IF EXISTS finance.request_withdrawal(uuid, text, numeric, text, text, text);
CREATE OR REPLACE FUNCTION finance.request_withdrawal(
    p_student uuid, p_session text, p_amount numeric, p_bank text, p_account_no text, p_account_name text, p_source text DEFAULT NULL)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE elig record; v_amount numeric; r finance.wallet_withdrawal; v_src text := nullif(upper(btrim(coalesce(p_source, ''))), ''); v_cap numeric; reach record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is requested by a person' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || p_student::text));
    SELECT * INTO elig FROM finance.withdrawal_eligibility(p_student, p_session);
    IF NOT elig.eligible THEN RAISE EXCEPTION 'WALLET_REFUND_NOT_AVAILABLE: %', elig.reason USING ERRCODE = '23514'; END IF;
    -- the source: NELFUND when the Fund's money is refundable, else the student's own; a grant is never one
    IF v_src IS NULL THEN v_src := CASE WHEN elig.nelfund_refundable > 0 THEN 'NELFUND' ELSE 'SELF' END; END IF;
    v_cap := CASE WHEN v_src = 'NELFUND' THEN elig.nelfund_refundable WHEN v_src = 'SELF' THEN elig.self_refundable ELSE 0 END;
    IF v_cap <= 0 THEN
        RAISE EXCEPTION 'WALLET_REFUND_SOURCE: nothing from % may be refunded for %', v_src, p_session USING ERRCODE = '23514',
            HINT = 'Only the Fund''s money left after the fees were settled, and your own leftover, are refunded; a scholarship or a sponsor''s grant is not.';
    END IF;
    v_amount := coalesce(p_amount, v_cap);
    IF v_amount <= 0 THEN RAISE EXCEPTION 'a withdrawal is for an amount above zero' USING ERRCODE = '23514'; END IF;
    IF v_amount > v_cap THEN
        RAISE EXCEPTION 'WALLET_REFUND_ABOVE_REFUNDABLE: NGN % of % may be refunded; not NGN %', v_cap, v_src, v_amount USING ERRCODE = '23514',
            HINT = 'Request up to the refundable amount, not more.';
    END IF;
    IF coalesce(btrim(p_bank), '') = '' OR coalesce(btrim(p_account_no), '') = '' OR coalesce(btrim(p_account_name), '') = '' THEN
        RAISE EXCEPTION 'a withdrawal names the bank, the account number and the account name' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.wallet_withdrawal (student_id, session, amount, bank_name, account_no, account_name, requested_by, source_code)
    VALUES (p_student, p_session, v_amount, btrim(p_bank), btrim(p_account_no), btrim(p_account_name), current_setting('moaum.actor_id', true)::uuid, v_src)
    RETURNING * INTO r;
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund request is with the Bursary',
        'Your request for a refund of NGN ' || v_amount::text || ' of ' || v_src || ' funding for ' || p_session || ' to ' || btrim(p_bank) || ' ' || btrim(p_account_no)
        || ' is recorded. The Bursary reviews it; you will be told the decision.', 'student', p_student);
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION finance.approve_withdrawal(p_id uuid)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal; elig record; v_cap numeric; reach record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is approved by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'REQUESTED' THEN RAISE EXCEPTION 'withdrawal % is not awaiting a decision', p_id USING ERRCODE = '23514'; END IF;
    IF r.requested_by = current_setting('moaum.actor_id', true)::uuid THEN
        RAISE EXCEPTION 'WALLET_REFUND_TWO_PEOPLE: the person who requested a refund does not approve it' USING ERRCODE = '23514';
    END IF;
    -- the money and the clearance must still hold at the moment of approval, for this source and this session
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
    SELECT * INTO elig FROM finance.withdrawal_eligibility(r.student_id, r.session);
    v_cap := CASE WHEN r.source_code = 'SELF' THEN elig.self_refundable WHEN r.source_code IS NULL THEN finance.wallet_balance(r.student_id) ELSE elig.nelfund_refundable END + r.amount;   -- its own hold is counted back
    IF NOT elig.cleared OR elig.arrears THEN
        RAISE EXCEPTION 'WALLET_REFUND_NOT_AVAILABLE: %', elig.reason USING ERRCODE = '23514';
    END IF;
    IF v_cap < r.amount THEN
        RAISE EXCEPTION 'WALLET_REFUND_ABOVE_REFUNDABLE: the wallet no longer holds NGN % of %', r.amount, coalesce(r.source_code, 'funding') USING ERRCODE = '23514';
    END IF;
    UPDATE finance.wallet_withdrawal SET state = 'APPROVED', decided_at = now(),
           decided_by = current_setting('moaum.actor_id', true)::uuid WHERE id = p_id
    RETURNING * INTO r;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund is approved',
        'Your refund of NGN ' || r.amount::text || ' for ' || r.session || ' is approved and awaits payment to ' || r.bank_name || ' ' || r.account_no || '.', 'student', r.student_id);
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION finance.reject_withdrawal(p_id uuid, p_why text)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal; reach record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is decided by a person' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_why), '') = '' THEN RAISE EXCEPTION 'a rejection says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state NOT IN ('REQUESTED', 'APPROVED') THEN RAISE EXCEPTION 'withdrawal % cannot be rejected', p_id USING ERRCODE = '23514'; END IF;
    UPDATE finance.wallet_withdrawal SET state = 'REJECTED', reason = btrim(p_why), decided_at = now(),
           decided_by = current_setting('moaum.actor_id', true)::uuid WHERE id = p_id
    RETURNING * INTO r;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund request was not approved',
        'Your refund request of NGN ' || r.amount::text || ' for ' || r.session || ' was not approved: ' || btrim(p_why) || '.', 'student', r.student_id);
    RETURN r;
END $$;

-- paid by a second officer: the money leaves the wallet as a REFUND of its source, the payout reference on the record
CREATE OR REPLACE FUNCTION finance.pay_withdrawal(p_id uuid, p_ref text)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal; v_actor uuid; v_entry uuid; v_avail numeric; reach record;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payout is made by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'withdrawal % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF r.decided_by = v_actor THEN
        RAISE EXCEPTION 'the officer who approved a withdrawal does not also pay it' USING ERRCODE = '23514',
            HINT = 'A second officer records the payout.';
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
    VALUES (r.student_id, r.session, 'REFUND', r.amount, nullif(btrim(p_ref), ''),
            'Refunded to ' || r.bank_name || ' ' || r.account_no || CASE WHEN r.source_code IS NOT NULL THEN ' from ' || r.source_code ELSE '' END, r.source_code)
    RETURNING id INTO v_entry;
    UPDATE finance.wallet_withdrawal SET state = 'PAID', paid_at = now(), paid_by = v_actor,
           paid_ref = nullif(btrim(p_ref), ''), entry_id = v_entry WHERE id = p_id
    RETURNING * INTO r;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your refund is paid',
        'NGN ' || r.amount::text || ' for ' || r.session || ' was paid to ' || r.bank_name || ' ' || r.account_no || CASE WHEN r.paid_ref IS NOT NULL THEN ' (reference ' || r.paid_ref || ')' ELSE '' END || '.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your refund is paid', 'MOAUM: refund of NGN ' || r.amount::text || ' paid to ' || r.bank_name || '.', 'student', r.student_id);
    RETURN r;
END $$;

DROP FUNCTION IF EXISTS finance.withdrawal_queue(text);
CREATE OR REPLACE FUNCTION finance.withdrawal_queue(p_session text)
RETURNS TABLE (id uuid, student_id uuid, matric_no text, student_name text, session text, amount numeric, source_code text,
               bank_name text, account_no text, account_name text, state text, reason text,
               requested_at timestamptz, decided_at timestamptz, paid_at timestamptz, paid_ref text)
LANGUAGE sql STABLE AS $$
    SELECT w.id, w.student_id, s.matric_no, s.surname || ', ' || s.other_names, w.session, w.amount, coalesce(w.source_code, 'NELFUND'),
           w.bank_name, w.account_no, w.account_name, w.state, w.reason,
           w.requested_at, w.decided_at, w.paid_at, w.paid_ref
      FROM finance.wallet_withdrawal w JOIN people.student s ON s.id = w.student_id
     WHERE p_session IS NULL OR w.session = p_session
     ORDER BY CASE w.state WHEN 'REQUESTED' THEN 0 WHEN 'APPROVED' THEN 1 ELSE 2 END, w.requested_at DESC
$$;

-- ── 8 · the old portal's NELFUND payments: staged once, matched by identifiers, posted once ─────────────────────
CREATE TABLE finance.legacy_nelfund_import (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference        text NOT NULL UNIQUE,
    source_system    text NOT NULL DEFAULT 'OLD_NELFUND_PORTAL',
    file_name        text NULL,
    session          text NULL,
    uploaded_by      uuid NULL,
    uploader_office  text NULL,
    uploaded_at      timestamptz NOT NULL DEFAULT now(),
    total_rows       int NOT NULL DEFAULT 0,
    staged           int NOT NULL DEFAULT 0,
    already_staged   int NOT NULL DEFAULT 0,
    skipped          int NOT NULL DEFAULT 0,
    status           text NOT NULL DEFAULT 'STAGED' CHECK (status IN ('STAGED', 'APPLIED')),
    applied_at       timestamptz NULL,
    applied_by       uuid NULL,
    note             text NULL
);
COMMENT ON TABLE finance.legacy_nelfund_import IS 'One upload of old-portal NELFUND payments (V327): its reference, file, uploader, counts, and whether its matched rows have been posted to the wallets.';
SELECT audit.attach('finance.legacy_nelfund_import');

CREATE TABLE finance.legacy_nelfund_payment (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id             uuid NOT NULL REFERENCES finance.legacy_nelfund_import(id),
    row_no                int NOT NULL,
    source_system         text NOT NULL DEFAULT 'OLD_NELFUND_PORTAL',
    source_transaction_id text NULL,
    source_reference      text NULL,
    source_student_id     text NULL,
    matric_no             text NULL,
    jamb_no               text NULL,
    application_no        text NULL,
    student_name          text NULL,
    amount                numeric(12,2) NULL,
    currency              text NOT NULL DEFAULT 'NGN',
    paid_at               timestamptz NULL,
    paid_at_text          text NULL,
    session               text NULL,
    legacy_status         text NULL,
    normalized_status     text NOT NULL DEFAULT 'UNKNOWN' CHECK (normalized_status IN ('SUCCESS', 'FAILED', 'REVERSED', 'REFUNDED', 'PENDING', 'UNKNOWN')),
    raw                   jsonb NOT NULL,
    imported_at           timestamptz NOT NULL DEFAULT now(),
    imported_by           uuid NULL
);
COMMENT ON TABLE finance.legacy_nelfund_payment IS 'An old-portal NELFUND payment as the old portal recorded it (V327): reference, date, amount, status, session, the identifiers it carried and the whole row — written once, never corrected in place.';
CREATE UNIQUE INDEX ux_legacy_nelfund_source_tx ON finance.legacy_nelfund_payment (source_system, upper(source_transaction_id)) WHERE source_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX ux_legacy_nelfund_source_ref ON finance.legacy_nelfund_payment (source_system, upper(source_reference)) WHERE source_reference IS NOT NULL;
CREATE INDEX ix_legacy_nelfund_import ON finance.legacy_nelfund_payment (import_id, row_no);
CREATE INDEX ix_legacy_nelfund_matric ON finance.legacy_nelfund_payment (upper(matric_no)) WHERE matric_no IS NOT NULL;
CREATE INDEX ix_legacy_nelfund_session ON finance.legacy_nelfund_payment (session, normalized_status);
SELECT audit.attach('finance.legacy_nelfund_payment');
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_payment_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'LEGACY_PAYMENT_WRITTEN_ONCE: an old-portal payment is staged once and never corrected in place; the reconciliation record carries what the portal made of it' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_legacy_nelfund_payment_written_once BEFORE UPDATE OR DELETE ON finance.legacy_nelfund_payment
    FOR EACH ROW EXECUTE FUNCTION finance.legacy_nelfund_payment_written_once();

CREATE TABLE finance.legacy_nelfund_reconciliation (
    payment_id        uuid PRIMARY KEY REFERENCES finance.legacy_nelfund_payment(id),
    import_id         uuid NOT NULL REFERENCES finance.legacy_nelfund_import(id),
    status            text NOT NULL DEFAULT 'UNPROCESSED' CHECK (status IN ('UNPROCESSED', 'MATCHED', 'POSTED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE', 'UNMATCHED')),
    reason_code       text NULL,
    reason            text NULL,
    student_id        uuid NULL REFERENCES people.student(id),
    match_method      text NULL CHECK (match_method IS NULL OR match_method IN ('STUDENT_ID', 'MATRIC_NO', 'JAMB_NO', 'APPLICATION_NO', 'LEGACY_ID_CROSSWALK', 'MANUAL')),
    match_confidence  text NULL CHECK (match_confidence IS NULL OR match_confidence IN ('HIGH', 'REVIEW', 'MANUAL')),
    candidates        jsonb NULL,
    wallet_entry_id   uuid NULL UNIQUE REFERENCES finance.wallet_entry(id),
    posted_at         timestamptz NULL,
    posted_by         uuid NULL,
    posted_office     text NULL,
    resolved_at       timestamptz NULL,
    resolved_by       uuid NULL,
    resolved_office   text NULL,
    override_reason   text NULL,
    updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.legacy_nelfund_reconciliation IS 'The portal''s judgement on a staged old-portal NELFUND payment (V327): the student it was matched to and by what, its validation, and the wallet credit it was posted as — or the reason it waits, was rejected, or is a duplicate.';
CREATE INDEX ix_legacy_nelfund_rec_import ON finance.legacy_nelfund_reconciliation (import_id, status);
CREATE INDEX ix_legacy_nelfund_rec_status ON finance.legacy_nelfund_reconciliation (status);
CREATE INDEX ix_legacy_nelfund_rec_student ON finance.legacy_nelfund_reconciliation (student_id) WHERE student_id IS NOT NULL;
SELECT audit.attach('finance.legacy_nelfund_reconciliation');
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_rec_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_legacy_nelfund_rec_touch BEFORE UPDATE ON finance.legacy_nelfund_reconciliation FOR EACH ROW EXECUTE FUNCTION finance.legacy_nelfund_rec_touch();

-- a wallet credit posted from the old portal points at the staged payment, so the statement can say so and a payment is posted once
ALTER TABLE finance.wallet_entry ADD COLUMN IF NOT EXISTS legacy_payment_id uuid NULL REFERENCES finance.legacy_nelfund_payment(id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_wallet_entry_legacy ON finance.wallet_entry (legacy_payment_id) WHERE legacy_payment_id IS NOT NULL;
COMMENT ON COLUMN finance.wallet_entry.legacy_payment_id IS 'V327: the old-portal NELFUND payment this credit was posted from, when it was; one credit per payment.';

CREATE OR REPLACE FUNCTION finance.legacy_nelfund_new_import(p_file text, p_session text, p_note text)
RETURNS finance.legacy_nelfund_import LANGUAGE plpgsql AS $$
DECLARE i finance.legacy_nelfund_import; v_scope text := coalesce(replace(p_session, '/', '-'), 'ALL');
BEGIN
    INSERT INTO finance.legacy_nelfund_import (reference, file_name, session, uploaded_by, uploader_office, note)
    VALUES ('NELFUND-MIGRATION-' || v_scope || '-' || lpad(platform.next_number('legacy_nelfund_import', 'UNIVERSITY', coalesce(p_session, 'ALL'))::text, 5, '0'),
            nullif(btrim(coalesce(p_file, '')), ''), p_session, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''),
            nullif(btrim(coalesce(p_note, '')), ''))
    RETURNING * INTO i;
    RETURN i;
END $$;

-- staging: the rows as the file gives them; a reference already staged (this file or an earlier one) is never staged twice
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_stage(p_import uuid, p_rows jsonb)
RETURNS TABLE (total_rows int, staged int, already_staged int, skipped int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; n int := 0; ns int := 0; na int := 0; nk int := 0; v_id uuid; v_tx text; v_ref text; v_session text;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: old-portal payments are staged by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RAISE EXCEPTION 'LEGACY_ROWS_REQUIRED: the payments are rows' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        n := n + 1;
        v_tx := nullif(btrim(coalesce(r ->> 'transactionId', '')), '');
        v_ref := nullif(btrim(coalesce(r ->> 'reference', '')), '');
        IF v_tx IS NULL AND v_ref IS NULL THEN nk := nk + 1; CONTINUE; END IF;
        IF EXISTS (SELECT 1 FROM finance.legacy_nelfund_payment p
                    WHERE (v_tx IS NOT NULL AND upper(p.source_transaction_id) = upper(v_tx)) OR (v_ref IS NOT NULL AND upper(p.source_reference) = upper(v_ref))) THEN
            na := na + 1; CONTINUE;
        END IF;
        -- the session the payment belongs to: the row's, else the one its date falls in; never the current one by default
        v_session := finance.legacy_session_of(r ->> 'session');
        IF v_session IS NULL AND finance.legacy_date(r ->> 'paidAt') IS NOT NULL THEN
            SELECT a.name INTO v_session FROM policy.academic_session a
             WHERE finance.legacy_date(r ->> 'paidAt')::date BETWEEN a.starts_on AND a.ends_on ORDER BY a.starts_on DESC LIMIT 1;
        END IF;
        INSERT INTO finance.legacy_nelfund_payment (import_id, row_no, source_transaction_id, source_reference, source_student_id, matric_no, jamb_no, application_no,
                                                    student_name, amount, paid_at, paid_at_text, session, legacy_status, normalized_status, raw, imported_by)
        VALUES (p_import, coalesce((r ->> 'row')::int, n), v_tx, v_ref,
                nullif(btrim(coalesce(r ->> 'legacyStudentId', '')), ''), nullif(upper(btrim(coalesce(r ->> 'matric', ''))), ''), nullif(upper(btrim(coalesce(r ->> 'jamb', ''))), ''),
                nullif(upper(btrim(coalesce(r ->> 'applicationNo', ''))), ''), nullif(btrim(coalesce(r ->> 'name', '')), ''),
                nullif(regexp_replace(coalesce(r ->> 'amount', ''), '[^0-9.]', '', 'g'), '')::numeric,
                finance.legacy_date(r ->> 'paidAt'), nullif(btrim(coalesce(r ->> 'paidAt', '')), ''), v_session,
                nullif(btrim(coalesce(r ->> 'status', '')), ''), finance.legacy_status_of(coalesce(nullif(btrim(coalesce(r ->> 'status', '')), ''), 'success')), r, v_actor)
        RETURNING id INTO v_id;
        INSERT INTO finance.legacy_nelfund_reconciliation (payment_id, import_id) VALUES (v_id, p_import);
        ns := ns + 1;
    END LOOP;
    UPDATE finance.legacy_nelfund_import i SET total_rows = i.total_rows + n, staged = i.staged + ns, already_staged = i.already_staged + na, skipped = i.skipped + nk WHERE i.id = p_import;
    RETURN QUERY SELECT n, ns, na, nk;
END $$;

-- matching: strong identifiers only, in order; one student or nothing; a name is a suggestion for an officer, never a match
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_match(p_import uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    WITH p AS (
        SELECT lp.* FROM finance.legacy_nelfund_payment lp JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = lp.id
         WHERE lp.import_id = p_import AND rc.status = 'UNPROCESSED'),
    hits AS (
        SELECT p.id, s.id AS student_id, 'STUDENT_ID'::text AS method, 1 AS rank FROM p JOIN people.student s ON p.source_student_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND s.id = p.source_student_id::uuid
        UNION ALL
        SELECT p.id, s.id, 'MATRIC_NO', 2 FROM p JOIN people.student s ON p.matric_no IS NOT NULL AND upper(s.matric_no) = p.matric_no
        UNION ALL
        SELECT p.id, s.id, 'JAMB_NO', 3 FROM p JOIN people.student s ON p.jamb_no IS NOT NULL AND upper(s.jamb_reg_no) = p.jamb_no
        UNION ALL
        SELECT p.id, s.id, 'APPLICATION_NO', 4 FROM p JOIN people.student s ON p.application_no IS NOT NULL AND (upper(s.admission_no) = p.application_no OR upper(s.matric_no) = p.application_no)
        UNION ALL
        SELECT p.id, x.student_id, 'LEGACY_ID_CROSSWALK', 5 FROM p JOIN finance.legacy_student_crosswalk x ON p.source_student_id IS NOT NULL AND x.legacy_student_id = upper(p.source_student_id)),
    agg AS (
        SELECT h.id, count(DISTINCT h.student_id) AS students, (array_agg(h.student_id ORDER BY h.rank))[1] AS student_id, (array_agg(h.method ORDER BY h.rank))[1] AS method,
               jsonb_agg(DISTINCT jsonb_build_object('student_id', h.student_id, 'method', h.method)) AS cands
          FROM hits h GROUP BY h.id),
    judged AS (
        SELECT p.id,
               CASE WHEN a.students = 1 THEN 'MATCHED' WHEN a.students > 1 THEN 'REQUIRES_REVIEW' ELSE 'UNMATCHED' END AS status,
               CASE WHEN a.students = 1 THEN NULL WHEN a.students > 1 THEN 'AMBIGUOUS_STUDENT' ELSE 'STUDENT_NOT_FOUND' END AS code,
               CASE WHEN a.students = 1 THEN NULL WHEN a.students > 1 THEN 'the identifiers on the row point to ' || a.students || ' different students'
                    ELSE 'no student carries the matriculation, JAMB, application or old-portal number on the row' END AS reason,
               CASE WHEN a.students = 1 THEN a.student_id END AS student_id,
               CASE WHEN a.students = 1 THEN a.method END AS method,
               CASE WHEN a.students = 1 THEN 'HIGH' END AS confidence,
               CASE WHEN a.students > 1 THEN (SELECT jsonb_agg(jsonb_build_object('student_id', s.id, 'number', coalesce(s.matric_no, s.admission_no), 'name', s.surname || ', ' || s.other_names, 'programme', s.programme_code, 'method', c ->> 'method'))
                                               FROM jsonb_array_elements(a.cands) c JOIN people.student s ON s.id = (c ->> 'student_id')::uuid)
                    WHEN a.students IS NULL AND p.student_name IS NOT NULL THEN
                         (SELECT jsonb_agg(jsonb_build_object('student_id', s.id, 'number', coalesce(s.matric_no, s.admission_no), 'name', s.surname || ', ' || s.other_names, 'programme', s.programme_code, 'method', 'NAME_SUGGESTION'))
                            FROM (SELECT s.* FROM people.student s
                                   WHERE lower(regexp_replace(s.surname || ' ' || s.other_names, '[^a-z0-9 ]', '', 'gi')) = lower(regexp_replace(p.student_name, '[^a-z0-9 ]', '', 'gi'))
                                      OR lower(regexp_replace(s.other_names || ' ' || s.surname, '[^a-z0-9 ]', '', 'gi')) = lower(regexp_replace(p.student_name, '[^a-z0-9 ]', '', 'gi'))
                                   LIMIT 5) s)
                    END AS cands
          FROM p LEFT JOIN agg a ON a.id = p.id)
    UPDATE finance.legacy_nelfund_reconciliation rc
       SET status = j.status, reason_code = j.code, reason = j.reason, student_id = j.student_id, match_method = j.method, match_confidence = j.confidence, candidates = j.cands
      FROM judged j WHERE rc.payment_id = j.id;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- validation: only a successful payment of a positive amount for a known session is posted; a payment already on a
-- wallet is a duplicate
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_validate_one(p_payment uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p finance.legacy_nelfund_payment; rc finance.legacy_nelfund_reconciliation; v_status text; v_code text; v_reason text; v_entry uuid;
BEGIN
    SELECT * INTO p FROM finance.legacy_nelfund_payment WHERE id = p_payment;
    SELECT * INTO rc FROM finance.legacy_nelfund_reconciliation WHERE payment_id = p_payment;
    IF rc.student_id IS NULL OR rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE') THEN RETURN; END IF;
    v_status := 'MATCHED'; v_code := NULL; v_reason := NULL;
    IF p.normalized_status <> 'SUCCESS' THEN
        v_status := 'REJECTED';
        v_code := CASE p.normalized_status WHEN 'REFUNDED' THEN 'PAYMENT_REFUNDED' WHEN 'REVERSED' THEN 'PAYMENT_REVERSED' WHEN 'PENDING' THEN 'PAYMENT_PENDING' WHEN 'FAILED' THEN 'PAYMENT_FAILED' ELSE 'PAYMENT_STATUS_UNKNOWN' END;
        v_reason := 'the old portal recorded the payment as "' || coalesce(p.legacy_status, '—') || '"; only a successful payment credits a wallet';
    ELSIF p.amount IS NULL OR p.amount <= 0 THEN
        v_status := 'REJECTED'; v_code := 'MISSING_AMOUNT'; v_reason := 'the row carries no amount above zero';
    ELSIF p.session IS NULL THEN
        v_status := 'REJECTED'; v_code := 'MISSING_SESSION'; v_reason := 'the row names no session, and its date falls in none';
    ELSE
        SELECT e.id INTO v_entry FROM finance.wallet_entry e
         WHERE e.student_id = rc.student_id AND e.kind = 'CREDIT' AND e.source_code = 'NELFUND'
           AND (e.legacy_payment_id = p.id OR upper(e.reference) = 'NELFUND-LEG-' || upper(coalesce(p.source_reference, p.source_transaction_id)))
         LIMIT 1;
        IF v_entry IS NOT NULL THEN
            v_status := 'DUPLICATE'; v_code := 'REFERENCE_ON_LEDGER'; v_reason := 'this old-portal payment is already on the student''s wallet';
        END IF;
    END IF;
    UPDATE finance.legacy_nelfund_reconciliation
       SET status = v_status, reason_code = v_code, reason = v_reason, wallet_entry_id = CASE WHEN v_status = 'DUPLICATE' THEN v_entry ELSE wallet_entry_id END
     WHERE payment_id = p_payment AND status <> 'POSTED';
END $$;

CREATE OR REPLACE FUNCTION finance.legacy_nelfund_validate(p_import uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int := 0; v_id uuid;
BEGIN
    FOR v_id IN SELECT rc.payment_id FROM finance.legacy_nelfund_reconciliation rc WHERE rc.import_id = p_import AND rc.status IN ('MATCHED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE') AND rc.student_id IS NOT NULL LOOP
        PERFORM finance.legacy_nelfund_validate_one(v_id); n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- posting: every MATCHED row becomes one NELFUND credit on the student's wallet for the session it names, carrying the
-- old reference and the old date; twice changes nothing
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_apply(p_import uuid)
RETURNS TABLE (posted int, amount numeric, skipped int)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        rc record; v_entry uuid; n int := 0; v_sum numeric := 0; nk int := 0; reach record;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: old-portal payments are posted by a person' USING ERRCODE = '23514'; END IF;
    FOR rc IN
        SELECT r.payment_id, r.student_id, p.amount, p.session, p.paid_at, coalesce(p.source_reference, p.source_transaction_id) AS old_ref
          FROM finance.legacy_nelfund_reconciliation r JOIN finance.legacy_nelfund_payment p ON p.id = r.payment_id
         WHERE r.import_id = p_import AND r.status = 'MATCHED' ORDER BY p.row_no
         FOR UPDATE OF r
    LOOP
        IF EXISTS (SELECT 1 FROM finance.wallet_entry e WHERE e.legacy_payment_id = rc.payment_id) THEN nk := nk + 1; CONTINUE; END IF;
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code, legacy_payment_id, at)
        VALUES (rc.student_id, rc.session, 'CREDIT', rc.amount, 'NELFUND-LEG-' || upper(rc.old_ref),
                'NELFUND funding from the old portal, ' || rc.session || ' · paid ' || coalesce(to_char(rc.paid_at, 'DD Mon YYYY'), 'on a date the old portal did not give') || ' · old reference ' || rc.old_ref,
                'NELFUND', rc.payment_id, coalesce(rc.paid_at, now()))
        RETURNING id INTO v_entry;
        UPDATE finance.legacy_nelfund_reconciliation SET status = 'POSTED', wallet_entry_id = v_entry, posted_at = now(), posted_by = v_actor, posted_office = v_office WHERE payment_id = rc.payment_id;
        n := n + 1; v_sum := v_sum + rc.amount;
        SELECT * INTO reach FROM people.student_reach(rc.student_id);
        PERFORM platform.queue_notice('EMAIL', reach.email, 'Your NELFUND funding is reconciled',
            'NGN ' || rc.amount::text || ' of NELFUND funding paid on the old portal for ' || rc.session || ' (reference ' || rc.old_ref || ') is now on your wallet. Sign in to apply it to your fees, or to see what may be refunded.', 'student', rc.student_id);
    END LOOP;
    UPDATE finance.legacy_nelfund_import SET status = 'APPLIED', applied_at = now(), applied_by = v_actor WHERE id = p_import;
    RETURN QUERY SELECT n, v_sum, nk;
END $$;

-- an officer's hand: a match on evidence (never past the identifiers on the row), or a rejection with its reason
CREATE OR REPLACE FUNCTION finance.legacy_nelfund_resolve(p_payment uuid, p_action text, p_student uuid, p_reason text)
RETURNS finance.legacy_nelfund_reconciliation LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p finance.legacy_nelfund_payment; rc finance.legacy_nelfund_reconciliation; v_act text := upper(btrim(coalesce(p_action, '')));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is resolved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM finance.legacy_nelfund_payment WHERE id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_PAYMENT_NOT_FOUND: no such old-portal payment' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM finance.legacy_nelfund_reconciliation WHERE payment_id = p_payment FOR UPDATE;
    IF rc.status = 'POSTED' THEN RAISE EXCEPTION 'LEGACY_ALREADY_POSTED: this payment is already on a wallet' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'LEGACY_REASON_REQUIRED: resolving a payment names its reason' USING ERRCODE = '23514'; END IF;
    IF v_act = 'MATCH' THEN
        IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: name the current student' USING ERRCODE = '23514'; END IF;
        IF (p.matric_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = p.matric_no AND s.id <> p_student))
           OR (p.jamb_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.jamb_reg_no) = p.jamb_no AND s.id <> p_student)) THEN
            RAISE EXCEPTION 'LEGACY_IDENTIFIER_CONFLICT: the matriculation or JAMB number on the row belongs to another student; a payment is not moved to a student its identifiers do not name' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.legacy_nelfund_reconciliation
           SET status = 'MATCHED', reason_code = NULL, reason = NULL, student_id = p_student, match_method = 'MANUAL', match_confidence = 'MANUAL',
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
        PERFORM finance.legacy_nelfund_validate_one(p_payment);
        IF p.source_student_id IS NOT NULL AND p.source_student_id !~ '^[0-9a-f]{8}-' THEN
            INSERT INTO finance.legacy_student_crosswalk (legacy_student_id, student_id, source_system, note, set_by)
            VALUES (upper(p.source_student_id), p_student, 'OLD_NELFUND_PORTAL', 'set when ' || coalesce(p.source_reference, p.source_transaction_id) || ' was resolved: ' || btrim(p_reason), v_actor)
            ON CONFLICT (legacy_student_id) DO NOTHING;
        END IF;
    ELSIF v_act = 'REJECT' THEN
        UPDATE finance.legacy_nelfund_reconciliation
           SET status = 'REJECTED', reason_code = 'REJECTED_BY_OFFICER', reason = btrim(p_reason), resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSE
        RAISE EXCEPTION 'LEGACY_ACTION_UNKNOWN: an old-portal payment is matched or rejected' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rc FROM finance.legacy_nelfund_reconciliation WHERE payment_id = p_payment;
    RETURN rc;
END $$;

CREATE OR REPLACE FUNCTION finance.legacy_nelfund_summary(p_import uuid, p_session text)
RETURNS TABLE (total_rows bigint, matched bigint, posted bigint, requires_review bigint, unmatched bigint, duplicates bigint, rejected bigint, unprocessed bigint,
               amount_received numeric, amount_posted numeric, amount_review numeric, students_posted bigint)
LANGUAGE sql STABLE AS $$
    SELECT count(*), count(*) FILTER (WHERE rc.status = 'MATCHED'), count(*) FILTER (WHERE rc.status = 'POSTED'),
           count(*) FILTER (WHERE rc.status = 'REQUIRES_REVIEW'), count(*) FILTER (WHERE rc.status = 'UNMATCHED'),
           count(*) FILTER (WHERE rc.status = 'DUPLICATE'), count(*) FILTER (WHERE rc.status = 'REJECTED'), count(*) FILTER (WHERE rc.status = 'UNPROCESSED'),
           coalesce(sum(p.amount) FILTER (WHERE p.normalized_status = 'SUCCESS'), 0),
           coalesce(sum(p.amount) FILTER (WHERE rc.status = 'POSTED'), 0),
           coalesce(sum(p.amount) FILTER (WHERE rc.status IN ('REQUIRES_REVIEW', 'UNMATCHED', 'MATCHED')), 0),
           count(DISTINCT rc.student_id) FILTER (WHERE rc.status = 'POSTED')
      FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id
     WHERE (p_import IS NULL OR p.import_id = p_import) AND (p_session IS NULL OR p.session = p_session)
$$;

-- ── 9 · the statement says where each credit came from ────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS finance.wallet_statement(uuid);
CREATE OR REPLACE FUNCTION finance.wallet_statement(p_student uuid)
RETURNS TABLE (id uuid, at timestamptz, session text, kind text, amount numeric, reference text, note text,
               source_code text, source_name text, nature text, balance numeric, origin text, legacy_reference text, legacy_paid_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT e.id, e.at, e.session, e.kind, e.amount, e.reference, e.note,
           e.source_code, fs.name, fs.nature,
           sum(CASE WHEN e.kind IN ('CREDIT', 'TOPUP') THEN e.amount ELSE -e.amount END) OVER (ORDER BY e.at, e.id),
           CASE WHEN e.legacy_payment_id IS NOT NULL THEN 'OLD_PORTAL'
                WHEN e.kind = 'TOPUP' THEN 'GATEWAY'
                WHEN e.kind = 'CREDIT' AND EXISTS (SELECT 1 FROM finance.nelfund_batch b WHERE b.ref = e.reference) THEN 'REMITTANCE'
                WHEN e.kind = 'CREDIT' THEN 'BURSARY'
                ELSE 'WALLET' END,
           coalesce(lp.source_reference, lp.source_transaction_id), lp.paid_at
      FROM finance.wallet_entry e
      LEFT JOIN finance.funding_source fs ON fs.code = e.source_code
      LEFT JOIN finance.legacy_nelfund_payment lp ON lp.id = e.legacy_payment_id
     WHERE e.student_id = p_student ORDER BY e.at, e.id
$$;

-- ── 10 · the Bursary's questions, answered over the funded population ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.nelfund_student_rows(p_session text, p_q text, p_filter text)
RETURNS TABLE (student_id uuid, name text, number text, programme_code text, programme text, faculty_code text, dept_code text, level int, status text,
               nelfund_credited numeric, nelfund_applied numeric, nelfund_available numeric, nelfund_refundable numeric, other_credited numeric, self_credited numeric,
               due numeric, paid numeric, outstanding numeric, shortfall numeric, topup_allowed boolean, topup_reason text,
               refund_state text, refund_amount numeric, legacy_posted numeric, nelfund_after_settlement boolean)
LANGUAGE sql STABLE AS $$
    WITH funded AS (
        SELECT DISTINCT e.student_id FROM finance.wallet_entry e WHERE e.session = p_session
        UNION SELECT n.student_id FROM finance.nelfund_status n WHERE n.session = p_session AND n.student_id IS NOT NULL AND n.state = 'APPROVED'),
    rows_ AS (
        SELECT s.id AS student_id, s.surname || ', ' || s.other_names AS name, coalesce(s.matric_no, s.admission_no) AS number, s.programme_code, pr.name AS programme,
               pr.faculty_code, pr.dept_code, s.current_level AS level, s.status,
               coalesce((SELECT sum(b.credited) FROM finance.wallet_balances_session(s.id, p_session) b WHERE b.source_code = 'NELFUND'), 0) AS nelfund_credited,
               coalesce((SELECT sum(b.applied) FROM finance.wallet_balances_session(s.id, p_session) b WHERE b.source_code = 'NELFUND'), 0) AS nelfund_applied,
               coalesce((SELECT sum(b.available) FROM finance.wallet_balances_session(s.id, p_session) b WHERE b.source_code = 'NELFUND'), 0) AS nelfund_available,
               coalesce((SELECT sum(b.credited) FROM finance.wallet_balances_session(s.id, p_session) b WHERE b.nature = 'GRANT'), 0) AS other_credited,
               coalesce((SELECT sum(b.credited) FROM finance.wallet_balances_session(s.id, p_session) b WHERE b.nature = 'SELF'), 0) AS self_credited,
               t.due, t.paid, t.outstanding, t.shortfall, t.allowed, t.reason,
               w.nelfund_refundable, w.nelfund_after_settlement,
               (SELECT x.state FROM finance.wallet_withdrawal x WHERE x.student_id = s.id AND x.session = p_session ORDER BY x.requested_at DESC LIMIT 1) AS refund_state,
               (SELECT x.amount FROM finance.wallet_withdrawal x WHERE x.student_id = s.id AND x.session = p_session ORDER BY x.requested_at DESC LIMIT 1) AS refund_amount,
               coalesce((SELECT sum(e.amount) FROM finance.wallet_entry e WHERE e.student_id = s.id AND e.session = p_session AND e.legacy_payment_id IS NOT NULL), 0) AS legacy_posted
          FROM funded f JOIN people.student s ON s.id = f.student_id JOIN ref.programme pr ON pr.code = s.programme_code
          CROSS JOIN LATERAL finance.topup_eligibility(s.id, p_session) t
          CROSS JOIN LATERAL finance.withdrawal_eligibility(s.id, p_session) w
         WHERE p_q IS NULL OR lower(s.surname || ' ' || s.other_names) LIKE '%' || lower(p_q) || '%' OR lower(coalesce(s.matric_no, '')) LIKE '%' || lower(p_q) || '%' OR lower(coalesce(s.admission_no, '')) LIKE '%' || lower(p_q) || '%')
    SELECT r.student_id, r.name, r.number, r.programme_code, r.programme, r.faculty_code, r.dept_code, r.level, r.status,
           r.nelfund_credited, r.nelfund_applied, r.nelfund_available, r.nelfund_refundable, r.other_credited, r.self_credited,
           r.due, r.paid, r.outstanding, r.shortfall, r.allowed, r.reason, r.refund_state, r.refund_amount, r.legacy_posted, r.nelfund_after_settlement
      FROM rows_ r
     WHERE coalesce(p_filter, 'ALL') = 'ALL'
        OR (p_filter = 'SHORTFALL' AND r.shortfall > 0)
        OR (p_filter = 'TOPUP' AND r.allowed)
        OR (p_filter = 'REFUNDABLE' AND r.nelfund_refundable > 0)
        OR (p_filter = 'PAID_BEFORE_FUND' AND r.nelfund_after_settlement)
        OR (p_filter = 'REFUND_PENDING' AND r.refund_state IN ('REQUESTED', 'APPROVED'))
        OR (p_filter = 'LEGACY' AND r.legacy_posted > 0)
        OR (p_filter = 'OUTSTANDING' AND r.outstanding > 0)
     ORDER BY r.name
$$;
COMMENT ON FUNCTION finance.nelfund_student_rows(text, text, text) IS
  'The funded population of a session, one row per student (V327): NELFUND credited, applied, available and refundable; other funding; the fees due, paid, outstanding and the shortfall; whether a top-up is allowed and why not; the refund request''s state; what came from the old portal. Filters: ALL, SHORTFALL, TOPUP, REFUNDABLE, PAID_BEFORE_FUND, REFUND_PENDING, LEGACY, OUTSTANDING.';

CREATE OR REPLACE FUNCTION finance.nelfund_desk_figures(p_session text)
RETURNS TABLE (received numeric, students_funded bigint, nelfund_credited numeric, nelfund_applied numeric, nelfund_remaining numeric, nelfund_refundable numeric,
               students_refundable bigint, refunds_pending bigint, refunds_pending_amount numeric, refunds_approved bigint, refunds_paid bigint, refunds_paid_amount numeric,
               refunds_rejected bigint, legacy_posted numeric, legacy_posted_rows bigint, legacy_review_rows bigint, legacy_review_amount numeric,
               students_shortfall bigint, shortfall_amount numeric, students_topup bigint, students_paid_before_fund bigint, grants_credited numeric, self_credited numeric)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM finance.wallet_entry WHERE session = p_session),
         r AS (SELECT * FROM finance.nelfund_student_rows(p_session, NULL, 'ALL')),
         w AS (SELECT * FROM finance.wallet_withdrawal WHERE session = p_session),
         l AS (SELECT * FROM finance.legacy_nelfund_summary(NULL, p_session))
    SELECT (SELECT coalesce(sum(amount), 0) FROM finance.nelfund_batch WHERE session = p_session) + (SELECT amount_posted FROM l),
           (SELECT count(DISTINCT student_id) FROM e WHERE kind = 'CREDIT' AND source_code = 'NELFUND'),
           (SELECT coalesce(sum(amount), 0) FROM e WHERE kind = 'CREDIT' AND source_code = 'NELFUND'),
           (SELECT coalesce(sum(amount), 0) FROM e WHERE kind = 'APPLIED' AND source_code = 'NELFUND'),
           (SELECT coalesce(sum(nelfund_available), 0) FROM r),
           (SELECT coalesce(sum(nelfund_refundable), 0) FROM r),
           (SELECT count(*) FROM r WHERE nelfund_refundable > 0),
           (SELECT count(*) FROM w WHERE state = 'REQUESTED'), (SELECT coalesce(sum(amount), 0) FROM w WHERE state = 'REQUESTED'),
           (SELECT count(*) FROM w WHERE state = 'APPROVED'),
           (SELECT count(*) FROM w WHERE state = 'PAID'), (SELECT coalesce(sum(amount), 0) FROM w WHERE state = 'PAID'),
           (SELECT count(*) FROM w WHERE state = 'REJECTED'),
           (SELECT amount_posted FROM l), (SELECT posted FROM l), (SELECT requires_review + unmatched FROM l), (SELECT amount_review FROM l),
           (SELECT count(*) FROM r WHERE shortfall > 0), (SELECT coalesce(sum(shortfall), 0) FROM r),
           (SELECT count(*) FROM r WHERE topup_allowed), (SELECT count(*) FROM r WHERE nelfund_after_settlement),
           (SELECT coalesce(sum(e.amount), 0) FROM e JOIN finance.funding_source fs ON fs.code = e.source_code WHERE e.kind = 'CREDIT' AND fs.nature = 'GRANT'),
           (SELECT coalesce(sum(amount), 0) FROM e WHERE kind = 'TOPUP')
$$;

-- ── 11 · the Super Administrator's data reset clears the old-portal NELFUND tables with the wallet ─────────────
-- Restated as V323 left it, with the three V327 tables cleared before finance.wallet_entry (the staged rows are written once; the reset runs under the maintenance flag their trigger honours).
CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;

    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES and the wallet POLICY, settings, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.legacy_nelfund_reconciliation;   -- V327: the reconciliation hangs on the wallet entries and the students
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.legacy_nelfund_payment;
    DELETE FROM finance.legacy_nelfund_import;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.legacy_gst_reconciliation;
    DELETE FROM finance.legacy_gst_payment;
    DELETE FROM finance.legacy_gst_import;
    DELETE FROM finance.legacy_student_crosswalk;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    DELETE FROM assessment.sheet_upload;
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $$;

COMMIT;
