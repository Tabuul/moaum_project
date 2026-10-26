-- ═══════════════════════════════════════
-- V660 — outstanding-fees payments swapped to the student they belong to
--
-- The word of 26 October 2026 ("add Outstanding Fee to swap too, allow them to be able to swap Outstanding Fee too, because the
-- OUTSTANDING fee too most of them wrongly went to other students account too"). The payment swap (V527) moves a verified
-- school-fees payment credited to the wrong student, whole, to the student it belongs to — initiated by the Students Account
-- Officer or the Bursar, decided by another Bursar officer — and refused every other payment (SWAP_NOT_SCHOOL_FEES). The old
-- portal's OUTSTANDING FEES payments (channel Legacy, purpose "OUTSTANDING FEES …", V631) were credited to the wrong students as
-- often, and could not be moved. Now:
--   · finance.payment_swap_kind(payment): SCHOOL_FEES (purpose "School fees…"), OUTSTANDING_FEES (the old portal's outstanding
--     fees, as V631 reads them: channel Legacy and a purpose beginning "outstanding"), else NULL — not swapped;
--   · finance.payment_swap_outstanding(student, session): the confirmed outstanding-fees payments credited to a student in a session,
--     and finance.payment_swap_account restated to carry it (outstandingPaid) beside the school fees due, paid and balance;
--   · finance.payment_swap_check restated: an outstanding-fees payment is swapped like a school-fees one (verified, not refunded or
--     reversed, not from the wallet, not already swapped or waiting), except that it is never counted against a session's school
--     fees — so the target's school fees need not be stated for its session and an overpayment decision on school fees is no reason
--     to refuse — and that it is refused once the Bursary has acted on it for the wallet: SWAP_OUTSTANDING_CREDITED (credited to the
--     credited student's wallet, V631: the money is in that wallet), SWAP_OUTSTANDING_VERIFIED (verified for crediting to the student
--     it is on: returned on the Outstanding fees payments desk first); one returned or rejected there is swapped and its record
--     there follows the payment to the student it belongs to; the payment's kind is said (payment.kind);
--   · finance.decide_payment_swap restated: an outstanding-fees swap reconciles on the outstanding-fees payments — the session's
--     total unchanged, the credited student's down and the owner's up by exactly the amount, the reference held once — or nothing;
--     no school-fee flag is raised for it (its school fees did not move); the school-fees swap is as it was.
-- Nothing else changes: the reference, amount, date, receipt, gateway record and ledger stay as they were; the two officers, the
-- reasons, the evidence, the reversal by the Bursar and the notices to both students are the swap's own.
-- ═══════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.payment_swap_kind(p_payment uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN r.purpose LIKE 'School fees%' THEN 'SCHOOL_FEES'
                WHEN r.channel = 'Legacy' AND r.purpose ~* '^outstanding' THEN 'OUTSTANDING_FEES' END
      FROM finance.payment_reference r WHERE r.id = p_payment
$$;
COMMENT ON FUNCTION finance.payment_swap_kind(uuid) IS
  'V660: what a payment swap moves — SCHOOL_FEES, OUTSTANDING_FEES (the old portal''s outstanding fees, channel Legacy, V631), else NULL (not swapped)';

CREATE OR REPLACE FUNCTION finance.payment_swap_outstanding(p_student uuid, p_session text) RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.channel = 'Legacy' AND r.purpose ~* '^outstanding'
$$;
COMMENT ON FUNCTION finance.payment_swap_outstanding(uuid, text) IS
  'V660: the confirmed outstanding-fees payments (the old portal''s, V631) credited to a student in a session';

-- the account as the swap shows it: the school fees, and now the outstanding-fees payments
CREATE OR REPLACE FUNCTION finance.payment_swap_account(p_student uuid, p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('due', p.due, 'paid', p.paid, 'balance', p.due - p.paid,
                              'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'),
                              'clearsExamination', finance.clears_or_null(p_student, p_session, 'EXAMINATION'),
                              'outstandingPaid', finance.payment_swap_outstanding(p_student, p_session))
      FROM finance.position(p_student, p_session) p
$$;

-- ── whether a payment may be swapped, and to whom (V527, with the outstanding-fees payments) ──
CREATE OR REPLACE FUNCTION finance.payment_swap_check(p_payment uuid, p_to uuid, p_ignore_swap uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE r finance.payment_reference; f people.student; t people.student; refusals text[] := '{}'; v_done text; v_open text; v_kind text;
        lop finance.legacy_outstanding_payment;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'refusals', jsonb_build_array('SWAP_NOT_FOUND: no such payment'));
    END IF;
    SELECT * INTO f FROM people.student WHERE id = r.student_id;
    v_kind := finance.payment_swap_kind(r.id);
    IF v_kind IS NULL THEN
        refusals := refusals || ('SWAP_NOT_SCHOOL_FEES: the payment is ' || r.purpose || ', not school fees or the old portal''s outstanding fees');
    END IF;
    IF r.confirmed_at IS NULL THEN
        refusals := refusals || 'SWAP_NOT_VERIFIED: the payment is not confirmed (pending, failed or expired); only a verified payment is swapped'::text;
    END IF;
    IF v_kind = 'OUTSTANDING_FEES' THEN
        SELECT * INTO lop FROM finance.legacy_outstanding_payment x WHERE x.payment_id = r.id;
        IF lop.status = 'CREDITED' THEN
            refusals := refusals || ('SWAP_OUTSTANDING_CREDITED: this outstanding-fees payment is already credited to the wallet of the student it is on ('
                || coalesce(lop.batch_ref, 'credited') || '); the money is in that wallet and the payment is not moved');
        ELSIF lop.status = 'VERIFIED' THEN
            refusals := refusals || 'SWAP_OUTSTANDING_VERIFIED: this outstanding-fees payment is verified for crediting to the wallet of the student it is on; the Bursary returns it on the Outstanding fees payments desk first'::text;
        END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.refund x WHERE x.source_reference = r.reference AND x.state <> 'REJECTED') THEN
        refusals := refusals || 'SWAP_REFUNDED: a refund stands against this payment'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.paydirect_inbox x WHERE x.reference = r.reference AND x.is_reversal) THEN
        refusals := refusals || 'SWAP_REVERSED: Interswitch reported this payment reversed'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.wallet_entry x WHERE x.reference = r.reference) THEN
        refusals := refusals || 'SWAP_WALLET: the payment was made from the student''s NELFUND wallet; it is not moved to another student'::text;
    END IF;
    SELECT x.swap_ref INTO v_done FROM finance.payment_swap x WHERE x.payment_id = r.id AND x.status = 'COMPLETED' AND x.kind = 'SWAP'
       AND x.id IS DISTINCT FROM p_ignore_swap;
    IF v_done IS NOT NULL THEN
        refusals := refusals || ('SWAP_ALREADY_SWAPPED: This payment has already been reallocated (' || v_done || '); a correction is a reversal of that swap');
    END IF;
    SELECT x.swap_ref INTO v_open FROM finance.payment_swap x WHERE x.payment_id = r.id AND x.status = 'PENDING_APPROVAL' AND x.id IS DISTINCT FROM p_ignore_swap;
    IF v_open IS NOT NULL THEN
        refusals := refusals || ('SWAP_OPEN: swap ' || v_open || ' of this payment waits for a decision');
    END IF;
    -- an outstanding-fees payment is never counted against a session's school fees: an overpayment decision there is no reason to refuse it
    IF v_kind IS DISTINCT FROM 'OUTSTANDING_FEES' AND EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = r.student_id AND d.session = r.session AND d.superseded_at IS NULL) THEN
        refusals := refusals || 'SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the credited student''s fees for this session; the Bursary sets it aside first'::text;
    END IF;
    IF p_to IS NOT NULL THEN
        SELECT * INTO t FROM people.student WHERE id = p_to;
        IF NOT FOUND THEN
            refusals := refusals || 'SWAP_TARGET_UNKNOWN: no such student'::text;
        ELSE
            IF t.id = r.student_id THEN refusals := refusals || 'SWAP_SAME_STUDENT: Original and target student cannot be the same.'::text; END IF;
            IF t.duplicate_of IS NOT NULL THEN refusals := refusals || 'SWAP_TARGET_MERGED: the target record was merged into another; choose the student''s current record'::text; END IF;
            IF v_kind IS DISTINCT FROM 'OUTSTANDING_FEES' THEN
                IF NOT finance.fee_stated(t.id, r.session) THEN
                    refusals := refusals || ('SWAP_TARGET_FEES_NOT_STATED: no school fees are stated for the target student in ' || r.session || ', so the payment would count against nothing');
                END IF;
                IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = t.id AND d.session = r.session AND d.superseded_at IS NULL) THEN
                    refusals := refusals || 'SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the target student''s fees for this session; the Bursary sets it aside first'::text;
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN jsonb_build_object('ok', cardinality(refusals) = 0, 'refusals', to_jsonb(refusals),
        'payment', jsonb_build_object('id', r.id, 'reference', r.reference, 'amount', r.amount, 'session', r.session, 'purpose', r.purpose,
                                      'channel', r.channel, 'receiptNo', r.receipt_no, 'confirmedAt', r.confirmed_at, 'generatedAt', r.generated_at,
                                      'note', r.note, 'legacy', r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%',
                                      'legacyPayref', (SELECT lp.payref FROM finance.legacy_payref lp WHERE lp.reference = r.reference LIMIT 1),
                                      'kind', v_kind, 'outstandingStatus', CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN coalesce(lop.status, 'WAITING') END),
        'from', jsonb_build_object('id', f.id, 'matricNo', f.matric_no, 'name', f.surname || ', ' || f.other_names),
        'to', CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object('id', t.id, 'matricNo', t.matric_no, 'name', t.surname || ', ' || t.other_names) END);
END $$;
COMMENT ON FUNCTION finance.payment_swap_check(uuid, uuid, uuid) IS
  'V527, V660: whether a payment may be swapped (to a student, when one is named): a school-fees payment or the old portal''s outstanding-fees payment (not once verified or credited for the wallet); ok, the refusals in words (SWAP_…), the payment with its kind, the credited student and the target';

-- ── decided by another Bursar officer and executed (V527, with the outstanding-fees payments' own reconciliation) ──
CREATE OR REPLACE FUNCTION finance.decide_payment_swap(p_swap uuid, p_approve boolean, p_note text, p_confirmed boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s finance.payment_swap; r finance.payment_reference; chk jsonb; v_from_before jsonb; v_to_before jsonb; v_from_after jsonb; v_to_after jsonb;
        v_total_before numeric; v_total_after numeric; v_flags text[] := '{}'; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_failure text;
        v_from people.student; v_to people.student; v_kind text; v_field text;
BEGIN
    IF who IS NULL OR coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'SWAP_OFFICE: a payment swap is decided by a Bursar officer other than the one who initiated it' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO s FROM finance.payment_swap WHERE id = p_swap FOR UPDATE;   -- one decision at a time
    IF NOT FOUND THEN RAISE EXCEPTION 'SWAP_NOT_FOUND: no such swap' USING ERRCODE = 'P0002'; END IF;
    IF s.status <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'SWAP_DECIDED: this swap is already %', lower(s.status) USING ERRCODE = '23514';
    END IF;
    IF s.initiated_by = who THEN
        RAISE EXCEPTION 'SWAP_SAME_OFFICER: the officer who initiated a swap does not decide it; another officer does' USING ERRCODE = '42501';
    END IF;
    IF NOT coalesce(p_approve, false) THEN
        IF v_note IS NULL OR length(v_note) < 10 THEN RAISE EXCEPTION 'SWAP_REASON: say why the swap is rejected' USING ERRCODE = '23514'; END IF;
        UPDATE finance.payment_swap SET status = 'REJECTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note WHERE id = s.id;
        PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_REJECTED', NULL, v_note);
        RETURN jsonb_build_object('status', 'REJECTED', 'swapRef', s.swap_ref);
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'SWAP_CONFIRM: confirm that the payment belongs to the target student and was credited to the other in error' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_APPROVED', NULL, v_note);

    -- execution: the payment locked and everything checked again
    SELECT * INTO r FROM finance.payment_reference WHERE id = s.payment_id FOR UPDATE;
    chk := finance.payment_swap_check(s.payment_id, s.to_student, CASE WHEN s.kind = 'REVERSAL' THEN s.reverses END);
    -- this swap is the open one: its own pending row is not a reason to refuse it
    chk := jsonb_set(chk, '{refusals}', coalesce((SELECT jsonb_agg(x) FROM jsonb_array_elements_text(chk->'refusals') x WHERE x NOT LIKE 'SWAP_OPEN:%'), '[]'::jsonb));
    v_failure := CASE WHEN r.id IS NULL THEN 'the payment is no longer on record'
                      WHEN r.student_id <> s.from_student THEN 'the payment is no longer credited to the student it was swapped from'
                      WHEN r.amount <> s.amount OR r.reference <> s.reference OR r.session <> s.session THEN 'the payment changed since the swap was initiated'
                      WHEN jsonb_array_length(chk->'refusals') > 0 THEN chk->'refusals'->>0 END;
    IF v_failure IS NOT NULL THEN
        UPDATE finance.payment_swap SET status = 'FAILED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
               failure = v_failure WHERE id = s.id;
        PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_FAILED', NULL, v_failure);
        RETURN jsonb_build_object('status', 'FAILED', 'swapRef', s.swap_ref, 'failure', v_failure);
    END IF;
    v_kind := finance.payment_swap_kind(r.id);
    -- the figure the swap moves: the school fees paid, or the outstanding-fees payments
    v_field := CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN 'outstandingPaid' ELSE 'paid' END;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_EXECUTION_STARTED', NULL, NULL);
    SELECT * INTO v_from FROM people.student WHERE id = s.from_student;
    SELECT * INTO v_to FROM people.student WHERE id = s.to_student;
    v_from_before := finance.payment_swap_account(s.from_student, s.session);
    v_to_before := finance.payment_swap_account(s.to_student, s.session);
    SELECT coalesce(sum(x.amount), 0) INTO v_total_before FROM finance.payment_reference x
     WHERE x.session = s.session AND x.confirmed_at IS NOT NULL
       AND CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN x.channel = 'Legacy' AND x.purpose ~* '^outstanding' ELSE x.purpose LIKE 'School fees%' END;

    -- the credit moves; the payment itself — reference, amount, gateway, date, receipt, ledger — is untouched
    UPDATE finance.payment_reference SET student_id = s.to_student WHERE id = r.id;
    -- an outstanding-fees payment returned or rejected on the wallet desk (V631) keeps its record there, now on the student it belongs to
    IF v_kind = 'OUTSTANDING_FEES' THEN
        UPDATE finance.legacy_outstanding_payment SET student_id = s.to_student WHERE payment_id = r.id;
    END IF;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_ALLOCATION_REMOVED', s.from_student, s.reference || ' no longer counts for ' || coalesce(v_from.matric_no, v_from.admission_no));
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_ALLOCATION_CREATED', s.to_student, s.reference || ' counts for ' || coalesce(v_to.matric_no, v_to.admission_no));

    v_from_after := finance.payment_swap_account(s.from_student, s.session);
    v_to_after := finance.payment_swap_account(s.to_student, s.session);
    SELECT coalesce(sum(x.amount), 0) INTO v_total_after FROM finance.payment_reference x
     WHERE x.session = s.session AND x.confirmed_at IS NOT NULL
       AND CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN x.channel = 'Legacy' AND x.purpose ~* '^outstanding' ELSE x.purpose LIKE 'School fees%' END;
    -- reconciled, or nothing: the University's receipts of the kind unchanged, one account down and the other up by exactly the amount
    IF v_total_after <> v_total_before
       OR (v_from_before->>v_field)::numeric - (v_from_after->>v_field)::numeric <> s.amount
       OR (v_to_after->>v_field)::numeric - (v_to_before->>v_field)::numeric <> s.amount
       OR (SELECT count(*) FROM finance.payment_reference x WHERE x.reference = s.reference) <> 1 THEN
        RAISE EXCEPTION 'SWAP_RECONCILIATION: the accounts did not reconcile after the swap (received % then %, % paid % then %, % paid % then %); nothing was changed',
            v_total_before, v_total_after, v_from.matric_no, v_from_before->>v_field, v_from_after->>v_field, v_to.matric_no, v_to_before->>v_field, v_to_after->>v_field
            USING ERRCODE = '23514';
    END IF;
    IF v_kind = 'SCHOOL_FEES' THEN
        -- a course registration is never touched: one the first student's fees no longer clear is flagged for the Bursary
        IF NOT coalesce((v_from_after->>'clearsRegistration')::boolean, true) AND EXISTS (
                SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = s.from_student AND cr.session = s.session
                   AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
            v_flags := v_flags || 'FROM_REGISTRATION_UNCLEARED'::text;
        END IF;
        -- the payment may leave its owner paid beyond the session's fees: an overpayment for the Bursary to carry forward or refund
        IF (v_to_after->>'paid')::numeric > coalesce((v_to_after->>'due')::numeric, 0) THEN
            v_flags := v_flags || 'TO_OVERPAID'::text;
        END IF;
    END IF;
    UPDATE finance.payment_swap SET status = 'COMPLETED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
           executed_at = now(), flags = v_flags,
           before_state = jsonb_build_object('from', v_from_before, 'to', v_to_before, 'sessionReceived', v_total_before, 'kind', v_kind),
           after_state = jsonb_build_object('from', v_from_after, 'to', v_to_after, 'sessionReceived', v_total_after, 'kind', v_kind)
     WHERE id = s.id;
    IF s.kind = 'REVERSAL' THEN
        UPDATE finance.payment_swap SET status = 'REVERSED' WHERE id = s.reverses;
        PERFORM finance.payment_swap_note(s.reverses, 'PAYMENT_SWAP_REVERSED', NULL, 'Reversed by ' || s.swap_ref || ': ' || s.reason);
    END IF;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_COMPLETED', NULL,
        to_char(s.amount, 'FM999,999,999,990.00') || ' moved from ' || coalesce(v_from.matric_no, v_from.admission_no) || ' to ' || coalesce(v_to.matric_no, v_to.admission_no)
        || CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN ' (old-portal outstanding fees)' ELSE '' END);

    -- both students are told, in plain words: the reference and the swap, never the other student's details
    PERFORM platform.tell_student(s.from_student, 'FEE_PAYMENT_REALLOCATED_AWAY', NULL,
        jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00')),
        'FEE_PAYMENT_REALLOCATED_AWAY:' || s.id);
    PERFORM platform.tell_student(s.to_student, 'FEE_PAYMENT_REALLOCATED_TO', NULL,
        jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00')),
        'FEE_PAYMENT_REALLOCATED_TO:' || s.id);
    RETURN jsonb_build_object('status', 'COMPLETED', 'swapRef', s.swap_ref, 'flags', to_jsonb(v_flags), 'kind', v_kind,
                              'before', jsonb_build_object('from', v_from_before, 'to', v_to_before),
                              'after', jsonb_build_object('from', v_from_after, 'to', v_to_after));
END $$;
COMMENT ON FUNCTION finance.decide_payment_swap(uuid, boolean, text, boolean) IS
  'V527, V660: a payment swap decided by a Bursar officer other than the one who initiated it: rejected with a reason, or approved with the ownership confirmation and executed in the same transaction — the payment locked and checked again, its student changed and nothing else, the two accounts read before and after and reconciled on the school fees paid, or for the old portal''s outstanding-fees payments on those payments (its wallet-desk record following it), or nothing; a check that no longer holds marks it FAILED';

COMMIT;
