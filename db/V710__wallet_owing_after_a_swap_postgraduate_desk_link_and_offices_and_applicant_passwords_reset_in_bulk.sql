-- ════════════════════════════════════════════════════════════════════════
--  V710 · Follow-ups to V706 and V708: the wallet left owing by a swap, the postgraduate desk's link and offices, applicants'
--  passwords reset in bulk
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 30 October 2026 ("do 1-6"; the spent wallet: "Swap anyway, they owe it").
--
--  1 · A credited outstanding-fees payment whose wallet was used (V708 refused it, SWAP_OUTSTANDING_SPENT): the swap goes through,
--      the whole credit moving to the owner; the credited student's wallet is left owing the rest (a balance below nought, settled
--      first by what is credited to that wallet later; their fees stay as they were paid). finance.payment_swap_check and
--      finance.decide_payment_swap restated from V708: payment.walletCredit.owesAfter; the flag FROM_WALLET_OWES and the student told
--      (WALLET_OWED_AFTER_SWAP); the result's walletOwes. finance.wallet_debts(q, limit): every wallet owing, with the swap that left
--      it so, for the Bursary and the Students Account Officer.
--  3 · The postgraduate desk sends the applicant's own one-hour link too (admissions.pg_applicant_password_link: the token kept as a
--      hash on iam.password_reset, PGAPPLICANT — the sign-in page's "Forgot password" link — at most three an hour; the reset written
--      down as RESET_LINK with where it went). admissions.pg_applicant_password_reset gains sent_to, expires_at.
--  4 · The Academic Office (academic) and the Database Operators (dbops, on a grant over the whole University: the API's check) reset
--      a postgraduate applicant's password too (admissions.pg_applicant_password_officer restated).
--  5 · Passwords reset in bulk, back to the default number: admissions.applicant_password_bulk_reset(kind, numbers, reason, commit) —
--      undergraduate (the JAMB number, else the application number, V706) or postgraduate (the application number, or the old
--      portal's, V709) — each number found by the JAMB number, the application number (the old portal's), or the email: checked first
--      (WILL_RESET, NOT_FOUND, AMBIGUOUS, REPEATED, REFUSED), then reset one by one under one reference (APW-BULK/YYYY/NNNNNN on
--      admissions.applicant_password_bulk), each written down as the desk's own reset is and the applicant told; at most 2,000.
--      admissions.applicant_password_default restated: the applicant told by email and SMS here (the API told them before), and the
--      reset carries its bulk. admissions.pg_applicant_password_default restated: a password sealed for the bulk — the door opens on
--      either number while the change is required (V709), so no number is hashed into each account — and the reset carries its bulk.
--  (2 and 6 are the API's and the portal's: the applicant held on Change password reads the session policy and the manual's help;
--  applicant passwords on the Director of ICT's dashboard.)
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V710: the follow-ups to V706 and V708', true);

-- ── 1 · a credited outstanding-fees payment whose wallet was used: swapped, the credited student's wallet owing ──

CREATE OR REPLACE FUNCTION finance.payment_swap_check(p_payment uuid, p_to uuid, p_ignore_swap uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r finance.payment_reference; f people.student; t people.student; refusals text[] := '{}'; v_done text; v_open text; v_kind text;
        lop finance.legacy_outstanding_payment; we finance.wallet_entry; v_wallet numeric;
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
        -- V708: one verified for the wallet moves with its desk record (credited, later, to the owner's wallet); one credited moves its
        -- wallet credit with it, so long as the credited student's wallet still holds it
        IF lop.status = 'CREDITED' THEN
            SELECT * INTO we FROM finance.wallet_entry e WHERE e.id = lop.wallet_entry_id;
            IF we.id IS NULL OR we.student_id IS DISTINCT FROM r.student_id OR we.kind <> 'CREDIT' OR we.amount <> r.amount THEN
                refusals := refusals || ('SWAP_OUTSTANDING_WALLET: the wallet credit of this outstanding-fees payment (' || coalesce(lop.batch_ref, 'credited')
                    || ') no longer stands, as credited, on the wallet of the student it is on; the Bursary looks into it first');
            ELSE
                -- V710: a wallet that no longer holds it (the money used, for the student's own fees) no longer holds the swap up: the credit
                -- moves whole and the credited student's wallet owes the rest (finance.wallet_debts, for the Bursary)
                v_wallet := finance.wallet_balance(r.student_id);
            END IF;
        END IF;
    END IF;
    IF r.archived_at IS NOT NULL AND current_setting('moaum.payment_archive_payment', true) IS DISTINCT FROM r.id::text THEN
        refusals := refusals || ('SWAP_ARCHIVED: the payment is archived for review ('
            || coalesce((SELECT a.archive_ref FROM finance.payment_archive a WHERE a.payment_id = r.id AND a.state <> 'RECONCILED' LIMIT 1), 'archived')
            || '); its owner is settled on Archived payments');
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
                                      'kind', v_kind, 'outstandingStatus', CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN coalesce(lop.status, 'WAITING') END,
                                      -- V708: the wallet credit that moves with a credited one
                                      'walletCredit', CASE WHEN v_kind = 'OUTSTANDING_FEES' AND lop.status = 'CREDITED'
                                                           THEN jsonb_build_object('batchRef', lop.batch_ref, 'walletBalance', coalesce(v_wallet, finance.wallet_balance(r.student_id)),
                                                                                   -- V710: what the credited student's wallet owes once the credit has moved
                                                                                   'owesAfter', greatest(r.amount - coalesce(v_wallet, finance.wallet_balance(r.student_id)), 0)) END),
        'from', jsonb_build_object('id', f.id, 'matricNo', f.matric_no, 'name', f.surname || ', ' || f.other_names),
        'to', CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object('id', t.id, 'matricNo', t.matric_no, 'name', t.surname || ', ' || t.other_names) END);
END $function$;

CREATE OR REPLACE FUNCTION finance.decide_payment_swap(p_swap uuid, p_approve boolean, p_note text, p_confirmed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s finance.payment_swap; r finance.payment_reference; chk jsonb; v_from_before jsonb; v_to_before jsonb; v_from_after jsonb; v_to_after jsonb;
        v_total_before numeric; v_total_after numeric; v_flags text[] := '{}'; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_failure text;
        v_from people.student; v_to people.student; v_kind text; v_field text;
        lop finance.legacy_outstanding_payment; v_moved int; v_wallet_entry uuid;
BEGIN
    IF who IS NULL OR coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'SWAP_OFFICE: a payment swap is decided by a Bursar officer other than the one who initiated it' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO s FROM finance.payment_swap WHERE id = p_swap FOR UPDATE;   -- one decision at a time
    IF NOT FOUND THEN RAISE EXCEPTION 'SWAP_NOT_FOUND: no such swap' USING ERRCODE = 'P0002'; END IF;
    IF s.status <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'SWAP_DECIDED: this swap is already %', lower(s.status) USING ERRCODE = '23514';
    END IF;
    -- V670: a swap that settles an archived payment is decided with the archive, on the Archived payments desk
    IF EXISTS (SELECT 1 FROM finance.payment_archive a WHERE a.swap_id = s.id AND a.state = 'PENDING_BURSAR_APPROVAL')
       AND current_setting('moaum.payment_archive_payment', true) IS DISTINCT FROM s.payment_id::text THEN
        RAISE EXCEPTION 'SWAP_ARCHIVE_LINKED: swap % settles archived payment % (%); it is decided on the Archived payments desk', s.swap_ref, s.reference,
            (SELECT a.archive_ref FROM finance.payment_archive a WHERE a.swap_id = s.id LIMIT 1) USING ERRCODE = '23514';
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
    -- V708: an outstanding-fees payment may carry a wallet credit: both wallets are held while it moves (in one order: no deadlock)
    IF finance.payment_swap_kind(s.payment_id) = 'OUTSTANDING_FEES' THEN
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || least(s.from_student::text, s.to_student::text)));
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || greatest(s.from_student::text, s.to_student::text)));
        SELECT * INTO lop FROM finance.legacy_outstanding_payment x WHERE x.payment_id = s.payment_id FOR UPDATE;
    END IF;
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
     WHERE x.session = s.session AND x.confirmed_at IS NOT NULL AND x.archived_at IS NULL
       AND CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN x.channel = 'Legacy' AND x.purpose ~* '^outstanding' ELSE x.purpose LIKE 'School fees%' END;

    -- the credit moves; the payment itself — reference, amount, gateway, date, receipt, ledger — is untouched
    UPDATE finance.payment_reference SET student_id = s.to_student WHERE id = r.id;
    -- an outstanding-fees payment returned or rejected on the wallet desk (V631) keeps its record there, now on the student it belongs to
    IF v_kind = 'OUTSTANDING_FEES' THEN
        UPDATE finance.legacy_outstanding_payment SET student_id = s.to_student WHERE payment_id = r.id;
        -- V708: one credited to the wallet takes its wallet credit with it — the same entry, now on the owner's wallet (the ledger books
        -- by account, never by student, so nothing is posted again); the credited student's wallet down and the owner's up by the amount
        IF lop.status = 'CREDITED' THEN
            UPDATE finance.wallet_entry
               SET student_id = s.to_student,
                   note = coalesce(note, '') || ' · moved to ' || coalesce(v_to.matric_no, v_to.admission_no) || ' by payment swap ' || s.swap_ref
             WHERE id = lop.wallet_entry_id AND student_id = s.from_student AND kind = 'CREDIT' AND amount = s.amount;
            GET DIAGNOSTICS v_moved = ROW_COUNT;
            IF v_moved <> 1 THEN
                RAISE EXCEPTION 'SWAP_RECONCILIATION: the wallet credit % of % is not on the wallet it was credited to; nothing was changed', lop.batch_ref, s.reference
                    USING ERRCODE = '23514';
            END IF;
            v_wallet_entry := lop.wallet_entry_id;
            PERFORM finance.payment_swap_note(s.id, 'PAYMENT_WALLET_CREDIT_MOVED', s.to_student,
                to_char(s.amount, 'FM999,999,999,990.00') || ' wallet credit ' || coalesce(lop.batch_ref, '') || ' moved from the wallet of '
                || coalesce(v_from.matric_no, v_from.admission_no) || ' to the wallet of ' || coalesce(v_to.matric_no, v_to.admission_no));
        END IF;
    END IF;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_ALLOCATION_REMOVED', s.from_student, s.reference || ' no longer counts for ' || coalesce(v_from.matric_no, v_from.admission_no));
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_ALLOCATION_CREATED', s.to_student, s.reference || ' counts for ' || coalesce(v_to.matric_no, v_to.admission_no));

    v_from_after := finance.payment_swap_account(s.from_student, s.session);
    v_to_after := finance.payment_swap_account(s.to_student, s.session);
    SELECT coalesce(sum(x.amount), 0) INTO v_total_after FROM finance.payment_reference x
     WHERE x.session = s.session AND x.confirmed_at IS NOT NULL AND x.archived_at IS NULL
       AND CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN x.channel = 'Legacy' AND x.purpose ~* '^outstanding' ELSE x.purpose LIKE 'School fees%' END;
    -- reconciled, or nothing: the University's receipts of the kind unchanged, one account down and the other up by exactly the amount
    IF v_total_after <> v_total_before
       OR (v_from_before->>v_field)::numeric - (v_from_after->>v_field)::numeric <> s.amount
       OR (v_to_after->>v_field)::numeric - (v_to_before->>v_field)::numeric <> s.amount
       OR (SELECT count(*) FROM finance.payment_reference x WHERE x.reference = s.reference) <> 1
       -- V708: and a wallet credit moved: the credited student's wallet down and the owner's up by exactly the amount
       OR (v_wallet_entry IS NOT NULL AND ((v_from_before->>'wallet')::numeric - (v_from_after->>'wallet')::numeric <> s.amount
                                           OR (v_to_after->>'wallet')::numeric - (v_to_before->>'wallet')::numeric <> s.amount)) THEN
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
    -- V710: the credited student's wallet left owing — the credit used for their own fees — is flagged for the Bursary
    IF v_wallet_entry IS NOT NULL AND (v_from_after->>'wallet')::numeric < 0 THEN
        v_flags := v_flags || 'FROM_WALLET_OWES'::text;
    END IF;
    UPDATE finance.payment_swap SET status = 'COMPLETED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
           executed_at = now(), flags = v_flags, wallet_entry_id = v_wallet_entry,
           before_state = jsonb_build_object('from', v_from_before, 'to', v_to_before, 'sessionReceived', v_total_before, 'kind', v_kind),
           after_state = jsonb_build_object('from', v_from_after, 'to', v_to_after, 'sessionReceived', v_total_after, 'kind', v_kind)
     WHERE id = s.id;
    IF s.kind = 'REVERSAL' THEN
        UPDATE finance.payment_swap SET status = 'REVERSED' WHERE id = s.reverses;
        PERFORM finance.payment_swap_note(s.reverses, 'PAYMENT_SWAP_REVERSED', NULL, 'Reversed by ' || s.swap_ref || ': ' || s.reason);
    END IF;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_COMPLETED', NULL,
        to_char(s.amount, 'FM999,999,999,990.00') || ' moved from ' || coalesce(v_from.matric_no, v_from.admission_no) || ' to ' || coalesce(v_to.matric_no, v_to.admission_no)
        || CASE WHEN v_kind = 'OUTSTANDING_FEES'
                THEN ' (old-portal outstanding fees' || CASE WHEN v_wallet_entry IS NOT NULL THEN ', with its wallet credit' ELSE '' END || ')' ELSE '' END);

    -- both students are told, in plain words: the reference and the swap, never the other student's details
    PERFORM platform.tell_student(s.from_student, 'FEE_PAYMENT_REALLOCATED_AWAY', NULL,
        jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00')),
        'FEE_PAYMENT_REALLOCATED_AWAY:' || s.id);
    IF 'FROM_WALLET_OWES' = ANY (v_flags) THEN
        PERFORM platform.tell_student(s.from_student, 'WALLET_OWED_AFTER_SWAP', NULL,
            jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00'),
                               'OWED', 'NGN ' || to_char(-(v_from_after->>'wallet')::numeric, 'FM999,999,999,990.00')),
            'WALLET_OWED_AFTER_SWAP:' || s.id);
    END IF;
    PERFORM platform.tell_student(s.to_student, 'FEE_PAYMENT_REALLOCATED_TO', NULL,
        jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00')),
        'FEE_PAYMENT_REALLOCATED_TO:' || s.id);
    RETURN jsonb_build_object('status', 'COMPLETED', 'swapRef', s.swap_ref, 'flags', to_jsonb(v_flags), 'kind', v_kind, 'walletMoved', v_wallet_entry IS NOT NULL,
                              'walletOwes', CASE WHEN 'FROM_WALLET_OWES' = ANY (v_flags) THEN -(v_from_after->>'wallet')::numeric END,
                              'before', jsonb_build_object('from', v_from_before, 'to', v_to_before),
                              'after', jsonb_build_object('from', v_from_after, 'to', v_to_after));
END $function$;

COMMENT ON FUNCTION finance.payment_swap_check(uuid, uuid, uuid) IS
  'V527, V660, V670, V708, V710: whether a payment may be swapped, and to whom — an outstanding-fees payment verified or credited for the wallet too (a credited one with its wallet credit; a wallet that no longer holds it left owing, walletCredit.owesAfter)';
COMMENT ON FUNCTION finance.decide_payment_swap(uuid, boolean, text, boolean) IS
  'V527, V660, V670, V708, V710: a swap decided by another Bursar officer and executed, reconciled — a credited outstanding-fees payment moving its wallet credit too, the credited student''s wallet left owing flagged (FROM_WALLET_OWES) and the student told';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('WALLET_OWED_AFTER_SWAP', 'A wallet left owing by a payment correction',
 'To a student whose wallet was credited with another student''s payment, already used, once the Bursary has moved the credit to the student it belongs to',
 'Your wallet owes [OWED] after a payment correction',
 E'Dear [FIRST_NAME],\n\nThe old portal''s payment [REFERENCE] ([AMOUNT], [SESSION]) was credited to your wallet in error. The Bursary has moved it to the student it belongs to, as payment correction [SWAP]. Part of that money had already been used from your wallet, so your wallet now owes [OWED]. What is credited to your wallet from now on settles it first; your fees stay as they were paid. Your wallet is on your portal: [PORTAL_URL]\n\nIf you believe this is wrong, contact the Bursary with your own receipt.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: payment [REFERENCE] credited to your wallet in error was moved to its owner ([SWAP]); your wallet now owes [OWED]. See your wallet.',
 'Your wallet owes [OWED]',
 'The payment [REFERENCE] ([AMOUNT], [SESSION]) was credited to your wallet in error and has been moved to the student it belongs to (correction [SWAP]). Part of it had been used, so your wallet now owes [OWED]; what is credited to it from now on settles it first.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','SESSION','SWAP','OWED','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH')
ON CONFLICT (key) DO NOTHING;

-- every wallet owing, the most first, with the swap that left it so (when one did)
CREATE OR REPLACE FUNCTION finance.wallet_debts(p_q text DEFAULT NULL, p_limit integer DEFAULT 200)
RETURNS TABLE (student_id uuid, matric_no text, student text, programme text, owed numeric, swap_id uuid, swap_ref text, swapped_at timestamptz,
               reference text, moved_to text, last_credit_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH b AS (SELECT e.student_id, sum(CASE WHEN e.kind IN ('CREDIT', 'TOPUP') THEN e.amount ELSE -e.amount END) AS bal
                 FROM finance.wallet_entry e GROUP BY e.student_id
               HAVING sum(CASE WHEN e.kind IN ('CREDIT', 'TOPUP') THEN e.amount ELSE -e.amount END) < 0)
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, pr.name, -b.bal,
           w.id, w.swap_ref, w.executed_at, w.reference, coalesce(t.matric_no, t.admission_no),
           (SELECT max(e.at) FROM finance.wallet_entry e WHERE e.student_id = s.id AND e.kind IN ('CREDIT', 'TOPUP'))
      FROM b
      JOIN people.student s ON s.id = b.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN LATERAL (SELECT x.* FROM finance.payment_swap x
                          WHERE x.from_student = s.id AND x.wallet_entry_id IS NOT NULL AND x.status = 'COMPLETED'
                          ORDER BY x.executed_at DESC NULLS LAST LIMIT 1) w ON true
      LEFT JOIN people.student t ON t.id = w.to_student
     WHERE nullif(btrim(coalesce(p_q, '')), '') IS NULL
        OR upper(coalesce(s.matric_no, '')) LIKE '%' || upper(btrim(p_q)) || '%' OR upper(coalesce(s.admission_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
        OR (s.surname || ' ' || s.other_names) ILIKE '%' || btrim(p_q) || '%' OR upper(coalesce(w.swap_ref, '')) = upper(btrim(p_q))
     ORDER BY -b.bal DESC, s.surname, s.other_names
     LIMIT greatest(least(coalesce(p_limit, 200), 5000), 1)
$fn$;
COMMENT ON FUNCTION finance.wallet_debts(text, integer) IS
  'V710: every student wallet owing (a balance below nought), the most first, with the payment swap that moved a credit already used away from it (V708, V710)';

-- ── 3, 4 · the postgraduate desk: the applicant's own link; the Academic Office and the Database Operators ──

ALTER TABLE admissions.pg_applicant_password_reset DROP CONSTRAINT IF EXISTS pg_applicant_password_reset_method_check;
ALTER TABLE admissions.pg_applicant_password_reset ADD CONSTRAINT pg_applicant_password_reset_method_check CHECK (method IN ('DEFAULT_NUMBER', 'RESET_LINK'));
ALTER TABLE admissions.pg_applicant_password_reset DROP CONSTRAINT IF EXISTS pg_applicant_password_reset_reset_office_check;
ALTER TABLE admissions.pg_applicant_password_reset ADD CONSTRAINT pg_applicant_password_reset_reset_office_check
    CHECK (reset_office IN ('pgschool', 'pgsecretary', 'ict', 'ictagent', 'helpdeskhead', 'academic', 'dbops', 'super'));
ALTER TABLE admissions.pg_applicant_password_reset
    ADD COLUMN IF NOT EXISTS sent_to text,
    ADD COLUMN IF NOT EXISTS expires_at timestamptz;
COMMENT ON COLUMN admissions.pg_applicant_password_reset.sent_to IS 'V710: where a link went (masked), for RESET_LINK';
COMMENT ON COLUMN admissions.pg_applicant_password_reset.expires_at IS 'V710: when a link stops working, for RESET_LINK';

CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_officer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'APW_ACTOR: a password is reset by a person' USING ERRCODE = '23514'; END IF;
    -- V710: and the Academic Office and the Database Operators (one over the whole University: the API's check)
    IF v_office NOT IN ('pgschool', 'pgsecretary', 'ict', 'ictagent', 'helpdeskhead', 'academic', 'dbops', 'super') THEN
        RAISE EXCEPTION 'PGPW_OFFICE: the School of Postgraduate Studies, the Director of ICT, ICT Support, the Academic Office or a Database Operator resets a postgraduate applicant''s password, not %', v_office
            USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_officer() IS
  'V706, V710: the person resetting a postgraduate applicant''s password, in an office that may — pgschool, pgsecretary, ict, ictagent, helpdeskhead, academic, dbops (over the whole University, the API''s check) or super; PGPW_OFFICE otherwise.';

-- a link sent to the applicant (the token made, kept as a hash and sent by the API) on the sign-in page's own reset (V220); the reset written down
CREATE OR REPLACE FUNCTION admissions.pg_applicant_password_link(p_applicant uuid, p_token_hash text, p_reason text, p_sent_to text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.pg_applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        v_until timestamptz := now() + interval '1 hour'; v_app uuid; v_no text; v_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admissions.pg_applicant WHERE id = p_applicant) THEN
        RAISE EXCEPTION 'PGPW_NO_ACCOUNT: no postgraduate applicant %', p_applicant USING ERRCODE = '23503';
    END IF;
    SELECT a.id, a.application_no INTO v_app, v_no FROM admissions.pg_application a WHERE a.applicant_id = p_applicant ORDER BY a.created_at DESC LIMIT 1;
    IF v_no IS NULL THEN
        RAISE EXCEPTION 'PGPW_NO_APPLICATION: the applicant has no application' USING ERRCODE = '23514';
    END IF;
    IF (SELECT count(*) FROM iam.password_reset r WHERE r.subject_kind = 'PGAPPLICANT' AND r.subject_id = p_applicant AND r.created_at > now() - interval '1 hour') >= 3 THEN
        RAISE EXCEPTION 'PGPW_LINK_LIMIT: three reset links went to this applicant in the last hour' USING ERRCODE = '23514',
            HINT = 'Ask the applicant to use the latest link, or reset the password to the application number.';
    END IF;
    INSERT INTO iam.password_reset (subject_kind, subject_id, token_hash, expires_at) VALUES ('PGAPPLICANT', p_applicant, p_token_hash, v_until);
    INSERT INTO admissions.pg_applicant_password_reset (applicant_id, method, application_no, reason, sent_to, expires_at, reset_by, reset_office)
    VALUES (p_applicant, 'RESET_LINK', v_no, v_reason, p_sent_to, v_until, v_by, current_setting('moaum.actor_office', true))
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id, 'expiresAt', v_until, 'applicationNo', v_no, 'applicationId', v_app);
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_link(uuid, text, text, text) IS
  'V710: a one-hour reset link the University sent a postgraduate applicant (iam.password_reset, PGAPPLICANT; at most three an hour, with the applicant''s own); the reset written down.';

DROP FUNCTION IF EXISTS admissions.pg_applicant_password_find(text, integer);
CREATE FUNCTION admissions.pg_applicant_password_find(p_q text, p_limit integer DEFAULT 50)
RETURNS TABLE (applicant_id uuid, session text, application_no text, legacy_application_no text, surname text, other_names text, email text, phone text,
               programme text, state text, failed_attempts integer, locked boolean, must_change boolean, last_signed_in_at timestamptz,
               created_at timestamptz, last_reset_at timestamptz, last_reset_method text, resets bigint)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS raw, upper(btrim(coalesce(p_q, ''))) AS up,
                      CASE WHEN regexp_replace(coalesce(p_q, ''), '[^0-9+]', '', 'g') ~ '^\+?234[0-9]{10}$'
                           THEN '0' || right(regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g'), 10)
                           ELSE regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g') END AS digits)
    SELECT p.id, coalesce(a.session, p.session), a.application_no, lg.legacy_application_no, p.surname, p.other_names, p.email, p.phone,
           pr.name, a.state, p.failed_attempts, coalesce(p.locked_until > now(), false), p.must_change_password, p.last_signed_in_at, p.created_at,
           (SELECT max(r.reset_at) FROM admissions.pg_applicant_password_reset r WHERE r.applicant_id = p.id),
           (SELECT r.method FROM admissions.pg_applicant_password_reset r WHERE r.applicant_id = p.id ORDER BY r.reset_at DESC LIMIT 1),
           (SELECT count(*) FROM admissions.pg_applicant_password_reset r WHERE r.applicant_id = p.id)
      FROM admissions.pg_applicant p
      LEFT JOIN admissions.pg_application a ON a.applicant_id = p.id
      LEFT JOIN admissions.pg_legacy_application lg ON lg.application_id = a.id
      LEFT JOIN ref.programme pr ON pr.code = a.programme_code
      CROSS JOIN q
     WHERE length(q.raw) >= 3
       AND (a.application_no = q.up OR upper(btrim(lg.legacy_application_no)) = q.up OR lower(p.email) = lower(q.raw)
            OR (length(q.digits) = 11 AND p.phone = q.digits)
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (p.surname || ' ' || p.other_names) ILIKE '%' || q.raw || '%')
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (p.other_names || ' ' || p.surname) ILIKE '%' || q.raw || '%'))
     ORDER BY coalesce(a.session, p.session) DESC, p.surname, p.other_names
     LIMIT greatest(least(coalesce(p_limit, 50), 200), 1)
$fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_find(text, integer) IS
  'V706, V710: postgraduate applicant accounts for the password desk — by application number, the old portal''s number, email, phone (0… or +234…) or a name; the last reset''s method.';

-- ── 5 · passwords reset in bulk ──

CREATE SEQUENCE IF NOT EXISTS admissions.applicant_password_bulk_seq;
CREATE TABLE admissions.applicant_password_bulk (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^APW-BULK/[0-9]{4}/[0-9]{6}$'),
    kind text NOT NULL CHECK (kind IN ('UNDERGRADUATE', 'POSTGRADUATE')),
    reason text NOT NULL CHECK (length(btrim(reason)) >= 10),
    asked integer NOT NULL DEFAULT 0,
    reset integer NOT NULL DEFAULT 0,
    passed_over integer NOT NULL DEFAULT 0,
    done_by uuid NOT NULL,
    done_office text NOT NULL,
    done_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_applicant_password_bulk_at ON admissions.applicant_password_bulk (done_at DESC);
COMMENT ON TABLE admissions.applicant_password_bulk IS
  'V710: applicants'' passwords reset in bulk back to the default number — the reference, undergraduate or postgraduate, the reason, how many asked, reset and passed over, the officer and office; each reset on its own record (bulk_id).';
SELECT audit.attach('admissions.applicant_password_bulk');
ALTER TABLE admissions.applicant_password_reset ADD COLUMN IF NOT EXISTS bulk_id uuid REFERENCES admissions.applicant_password_bulk (id) ON DELETE SET NULL;
ALTER TABLE admissions.pg_applicant_password_reset ADD COLUMN IF NOT EXISTS bulk_id uuid REFERENCES admissions.applicant_password_bulk (id) ON DELETE SET NULL;

-- the undergraduate reset (V706), the applicant told here, and carrying its bulk
CREATE OR REPLACE FUNCTION admissions.applicant_password_default(p_account uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        a admissions.applicant_account; v_number text; v_locked boolean; v_ended integer; v_id uuid; v_jamb boolean; v_app uuid; v_appno text;
BEGIN
    SELECT * INTO a FROM admissions.applicant_account WHERE id = p_account FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'APW_NO_ACCOUNT: no applicant account %', p_account USING ERRCODE = '23503'; END IF;
    v_number := admissions.applicant_default_number(p_account);
    IF v_number IS NULL THEN
        RAISE EXCEPTION 'APW_NO_NUMBER: the applicant has neither a JAMB number nor an application number to sign in with' USING ERRCODE = '23514',
            HINT = 'Send the applicant a reset link instead.';
    END IF;
    v_jamb := nullif(btrim(a.jamb_key), '') IS NOT NULL;
    v_locked := coalesce(a.locked_until > now(), false);
    UPDATE admissions.applicant_account
       SET password_hash = 'SET_ON_FIRST_LOGIN', must_change_password = true, temp_expires_at = NULL, failed_attempts = 0, locked_until = NULL,
           password_reset_at = now()
     WHERE id = p_account;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = p_account AND ended_at IS NULL;
    GET DIAGNOSTICS v_ended = ROW_COUNT;
    INSERT INTO admissions.applicant_password_reset (account_id, method, reason, expires_at, was_locked, sessions_ended, reset_by, reset_office, bulk_id)
    VALUES (p_account, 'DEFAULT_NUMBER', v_reason, NULL, v_locked, v_ended, v_by, current_setting('moaum.actor_office', true),
            nullif(current_setting('moaum.applicant_password_bulk', true), '')::uuid)
    RETURNING id INTO v_id;
    INSERT INTO admissions.applicant_event (account_id, identifier, outcome) VALUES (p_account, '', 'DEFAULT_PASSWORD_RESTORED');
    -- V710: the applicant told here (the desk and the bulk alike), by email and SMS, in the words the API used
    SELECT p.id, p.application_no INTO v_app, v_appno FROM admissions.application p WHERE p.account_id = p_account ORDER BY p.created_at DESC NULLS LAST LIMIT 1;
    IF nullif(btrim(coalesce(a.email, '')), '') IS NOT NULL THEN
        PERFORM platform.queue_notice('EMAIL', a.email, 'Your MOAUM application password was reset',
            'The password of your application ' || coalesce(v_appno || ' ', '') || 'was reset by the University at your request. Sign in with your '
            || CASE WHEN v_jamb THEN 'JAMB registration number' ELSE 'application number' END
            || ' as the password; you will choose your own password at once. If you did not ask for this, contact ICT Support.', 'application', v_app);
    END IF;
    IF nullif(btrim(coalesce(a.phone, '')), '') IS NOT NULL THEN
        PERFORM platform.queue_notice('SMS', a.phone, 'Your MOAUM application password was reset',
            'MOAUM: your application password was reset. Sign in with your ' || CASE WHEN v_jamb THEN 'JAMB number' ELSE 'application number' END
            || ' as the password and choose your own.', 'application', v_app);
    END IF;
    RETURN jsonb_build_object('id', v_id, 'number', v_number, 'numberKind', CASE WHEN v_jamb THEN 'JAMB' ELSE 'APPLICATION' END,
                              'wasLocked', v_locked, 'sessionsEnded', v_ended);
END $fn$;
COMMENT ON FUNCTION admissions.applicant_password_default(uuid, text) IS
  'V706, V710: an applicant''s password put back to the first password — the JAMB number, or the application number — by the University: the account unlocked, its sessions ended, the change required at the next sign-in; the reset written down (DEFAULT_NUMBER, its bulk when in one) and the applicant told by email and SMS.';

-- the postgraduate reset (V706): a password sealed for a bulk — while the change is required the door opens on either number (V709) —
-- and carrying its bulk
DROP FUNCTION IF EXISTS admissions.pg_applicant_password_default(uuid, text);
CREATE FUNCTION admissions.pg_applicant_password_default(p_applicant uuid, p_reason text, p_sealed text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_by uuid := admissions.pg_applicant_password_officer(); v_reason text := admissions.applicant_password_reason(p_reason);
        p admissions.pg_applicant; v_app uuid; v_no text; v_locked boolean; v_ended integer; v_id uuid;
BEGIN
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = p_applicant FOR UPDATE;
    IF p.id IS NULL THEN RAISE EXCEPTION 'PGPW_NO_ACCOUNT: no postgraduate applicant %', p_applicant USING ERRCODE = '23503'; END IF;
    SELECT a.id, a.application_no INTO v_app, v_no FROM admissions.pg_application a WHERE a.applicant_id = p_applicant ORDER BY a.created_at DESC LIMIT 1;
    IF v_no IS NULL THEN
        RAISE EXCEPTION 'PGPW_NO_APPLICATION: the applicant has no application number to sign in with' USING ERRCODE = '23514',
            HINT = 'The applicant uses "Forgot password" on the sign-in page instead.';
    END IF;
    v_locked := coalesce(p.locked_until > now(), false);
    -- one at the desk: the application number, hashed; a bulk passes one sealed hash for all (nobody holds its secret)
    UPDATE admissions.pg_applicant
       SET password_hash = coalesce(p_sealed, crypt(v_no, gen_salt('bf', 12))), must_change_password = true, failed_attempts = 0, locked_until = NULL,
           password_reset_at = now()
     WHERE id = p_applicant;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'password reset' WHERE person_id = p_applicant AND ended_at IS NULL;
    GET DIAGNOSTICS v_ended = ROW_COUNT;
    INSERT INTO admissions.pg_applicant_password_reset (applicant_id, application_no, reason, was_locked, sessions_ended, reset_by, reset_office, bulk_id)
    VALUES (p_applicant, v_no, v_reason, v_locked, v_ended, v_by, current_setting('moaum.actor_office', true),
            nullif(current_setting('moaum.applicant_password_bulk', true), '')::uuid)
    RETURNING id INTO v_id;
    PERFORM admissions.pg_tell_applicant(v_app, 'Your application password was reset',
        'The password of your postgraduate application was reset by the University at your request. Sign in with your email or your application number, '
        || 'and your application number (' || v_no || ') as the password; you will choose your own password at once. '
        || 'If you did not ask for this, contact the School of Postgraduate Studies or ICT Support.');
    RETURN jsonb_build_object('id', v_id, 'applicationNo', v_no, 'wasLocked', v_locked, 'sessionsEnded', v_ended);
END $fn$;
COMMENT ON FUNCTION admissions.pg_applicant_password_default(uuid, text, text) IS
  'V706, V710: a postgraduate applicant''s password put back to the application number by the University (a bulk passes one sealed hash; the door opens on either number while the change is required, V709): the account unlocked, its sessions ended, the change required; the reset written down and the applicant told.';

CREATE OR REPLACE FUNCTION admissions.applicant_password_bulk_reset(p_kind text, p_numbers text[], p_reason text, p_commit boolean DEFAULT false)
RETURNS TABLE (row_no integer, given text, outcome text, account_id uuid, applicant text, default_number text, detail text, bulk_ref text)
LANGUAGE plpgsql AS $fn$
DECLARE v_kind text := upper(btrim(coalesce(p_kind, ''))); v_by uuid; v_reason text; v_bulk uuid; v_ref text; v_sealed text;
        v_keys text[] := '{}'; v_accounts uuid[] := '{}'; i integer := 0; v_n text; v_k text; v_ids uuid[]; v_id uuid;
        v_asked integer := 0; v_reset integer := 0; v_over integer := 0; v_err text;
BEGIN
    IF v_kind NOT IN ('UNDERGRADUATE', 'POSTGRADUATE') THEN
        RAISE EXCEPTION 'APW_BULK_KIND: a bulk reset is of undergraduate or postgraduate applicants, not %', p_kind USING ERRCODE = '22023';
    END IF;
    v_by := CASE WHEN v_kind = 'UNDERGRADUATE' THEN admissions.applicant_password_officer() ELSE admissions.pg_applicant_password_officer() END;
    v_reason := admissions.applicant_password_reason(p_reason);
    IF coalesce(cardinality(array_remove(array_remove(p_numbers, NULL), '')), 0) = 0 THEN
        RAISE EXCEPTION 'APW_BULK_EMPTY: give the numbers to reset, one to a line' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_numbers) > 2000 THEN
        RAISE EXCEPTION 'APW_BULK_TOO_MANY: at most 2,000 numbers at a time, not %', cardinality(p_numbers) USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_commit, false) THEN
        v_ref := 'APW-BULK/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('admissions.applicant_password_bulk_seq')::text, 6, '0');
        INSERT INTO admissions.applicant_password_bulk (reference, kind, reason, done_by, done_office)
        VALUES (v_ref, v_kind, v_reason, v_by, current_setting('moaum.actor_office', true)) RETURNING id INTO v_bulk;
        PERFORM set_config('moaum.applicant_password_bulk', v_bulk::text, true);
        -- one sealed hash for the postgraduate bulk: the door opens on either number while the change is required (V709)
        IF v_kind = 'POSTGRADUATE' THEN v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12)); END IF;
    END IF;
    FOREACH v_n IN ARRAY p_numbers LOOP
        i := i + 1;
        v_n := btrim(coalesce(v_n, ''));
        CONTINUE WHEN v_n = '';
        v_asked := v_asked + 1;
        v_k := upper(regexp_replace(v_n, '\s+', '', 'g'));
        row_no := i; given := v_n; outcome := NULL; account_id := NULL; applicant := NULL; default_number := NULL; detail := NULL; bulk_ref := v_ref;
        IF v_k = ANY (v_keys) THEN
            outcome := 'REPEATED'; detail := 'already in the list'; v_over := v_over + 1; RETURN NEXT; CONTINUE;
        END IF;
        v_keys := v_keys || v_k;
        IF v_kind = 'UNDERGRADUATE' THEN
            SELECT array_agg(DISTINCT x.id) INTO v_ids
              FROM admissions.applicant_account x LEFT JOIN admissions.application ap ON ap.account_id = x.id
             WHERE upper(x.jamb_key) = v_k OR upper(ap.application_no) = v_k OR lower(x.email) = lower(v_n);
        ELSE
            SELECT array_agg(DISTINCT x.id) INTO v_ids
              FROM admissions.pg_applicant x
              LEFT JOIN admissions.pg_application ap ON ap.applicant_id = x.id
              LEFT JOIN admissions.pg_legacy_application lg ON lg.application_id = ap.id
             WHERE upper(ap.application_no) = v_k OR upper(regexp_replace(lg.legacy_application_no, '\s+', '', 'g')) = v_k OR lower(x.email) = lower(v_n);
        END IF;
        IF v_ids IS NULL THEN
            outcome := 'NOT_FOUND'; detail := 'no applicant has this number or email'; v_over := v_over + 1; RETURN NEXT; CONTINUE;
        END IF;
        IF cardinality(v_ids) > 1 THEN
            outcome := 'AMBIGUOUS'; detail := cardinality(v_ids) || ' applicants have it: reset each on the desk'; v_over := v_over + 1; RETURN NEXT; CONTINUE;
        END IF;
        v_id := v_ids[1];
        account_id := v_id;
        IF v_kind = 'UNDERGRADUATE' THEN
            SELECT c.surname || ', ' || c.other_names, admissions.applicant_default_number(x.id) INTO applicant, default_number
              FROM admissions.applicant_account x JOIN admissions.candidate c ON c.id = x.candidate_id WHERE x.id = v_id;
        ELSE
            SELECT x.surname || ', ' || x.other_names,
                   (SELECT ap.application_no FROM admissions.pg_application ap WHERE ap.applicant_id = x.id ORDER BY ap.created_at DESC LIMIT 1)
              INTO applicant, default_number
              FROM admissions.pg_applicant x WHERE x.id = v_id;
        END IF;
        IF v_id = ANY (v_accounts) THEN
            outcome := 'REPEATED'; detail := 'the same applicant is already in the list'; v_over := v_over + 1; RETURN NEXT; CONTINUE;
        END IF;
        v_accounts := v_accounts || v_id;
        IF default_number IS NULL THEN
            outcome := 'REFUSED';
            detail := CASE WHEN v_kind = 'UNDERGRADUATE' THEN 'neither a JAMB number nor an application number to reset to: send a link on the desk'
                           ELSE 'no application number to reset to' END;
            v_over := v_over + 1; RETURN NEXT; CONTINUE;
        END IF;
        IF NOT coalesce(p_commit, false) THEN
            outcome := 'WILL_RESET'; RETURN NEXT; CONTINUE;
        END IF;
        BEGIN
            IF v_kind = 'UNDERGRADUATE' THEN
                PERFORM admissions.applicant_password_default(v_id, v_reason);
            ELSE
                PERFORM admissions.pg_applicant_password_default(v_id, v_reason, v_sealed);
            END IF;
            outcome := 'RESET'; v_reset := v_reset + 1;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            outcome := 'REFUSED'; detail := v_err; v_over := v_over + 1;
        END;
        RETURN NEXT;
    END LOOP;
    IF coalesce(p_commit, false) THEN
        UPDATE admissions.applicant_password_bulk SET asked = v_asked, reset = v_reset, passed_over = v_over WHERE id = v_bulk;
        PERFORM set_config('moaum.applicant_password_bulk', '', true);
    END IF;
END $fn$;
COMMENT ON FUNCTION admissions.applicant_password_bulk_reset(text, text[], text, boolean) IS
  'V710: applicants'' passwords reset in bulk back to the default number — UNDERGRADUATE (the JAMB number, else the application number) or POSTGRADUATE (the application number) — each number found by the JAMB number, the application number (the old portal''s) or the email: checked (WILL_RESET, NOT_FOUND, AMBIGUOUS, REPEATED, REFUSED) or, committed, reset one by one under one APW-BULK reference (RESET, REFUSED); at most 2,000.';

COMMIT;
