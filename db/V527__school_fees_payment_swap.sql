-- ═══════════════════════════════════════
-- V527 — School fees payment swap: a verified payment credited to the wrong student, moved to the right one
--
--   Some students paid school fees on another student's account — on the old portal above all, where the payment came across
--   under the number it was paid on. The payment is verified and counts for the wrong student; the right student owes it.
--
--   A swap moves the payment's credit from one student to the other as a controlled correction:
--     · finance.payment_swap — the swap (SWAP/<year>/<number>): the payment as it stood (reference, amount, session, purpose,
--       channel, receipt, when it was confirmed, whether it came from the old portal), the student it was credited to and the one
--       it belongs to, the reason, the evidence, the officer's confirmation that the payment is the other student's, who initiated
--       and who decided, the accounts before and after, and what to look at afterwards; finance.payment_swap_evidence (files) and
--       finance.payment_swap_event (the timeline: initiated, approved, execution started, allocation removed, allocation created,
--       completed — or rejected, cancelled, failed, reversed);
--     · finance.payment_swap_check — whether a payment may be swapped to a student: a confirmed school-fees payment (purpose
--       School fees…), not refunded, not reversed by Interswitch, not paid from a NELFUND wallet, not already swapped, not under
--       another open swap, no overpayment decision standing on either student's session, two distinct students, the target not a
--       merged record and with the session's school fees stated;
--     · finance.initiate_payment_swap — the Students Account Officer or the Bursar, with a reason of twenty characters or more and
--       the confirmation, for the whole payment (never part of it);
--     · finance.decide_payment_swap — a Bursar officer other than the one who initiated it
--       rejects it with a reason, or approves it with the ownership confirmation: approved, it is executed in the same transaction —
--       the payment locked and checked again, its student changed and nothing else (reference, amount, gateway, date, receipt,
--       ledger untouched: the books hold the University's money, not whose it is), the two accounts read before and after, the
--       totals reconciled (the session's school fees received unchanged, the one student's paid down by exactly the amount, the
--       other's up by it) — or nothing at all; a check that no longer holds marks it FAILED with the reason;
--     · a completed swap is never edited: it is reversed by a swap of its own (kind REVERSAL) under the same approval;
--     · the Finance Controller's office is the College of Health Sciences' own (V227) and reads its college: it is not given a
--       University-wide swap; Internal Audit reads every swap and decides none;
--     · the balances, the clearances and every entitlement read the payments as they stand (finance.position, finance.clears), so
--       they follow the swap; a course registration is never touched — one the first student made that their fees no longer clear
--       is flagged on the swap for the Bursary, and so is an owner left paid beyond the session's fees (an overpayment to carry
--       forward or refund through the Bursary's own overpayment and refund screens);
--     · both students are told (FEE_PAYMENT_REALLOCATED_AWAY, FEE_PAYMENT_REALLOCATED_TO);
--     · the old-portal reset (V499) keeps a swapped payment, so a reload of the export can neither undo nor double it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V527: school fees payment swap', true);

CREATE SEQUENCE finance.payment_swap_no;

CREATE TABLE finance.payment_swap (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    swap_ref             text NOT NULL UNIQUE,
    kind                 text NOT NULL DEFAULT 'SWAP' CHECK (kind IN ('SWAP', 'REVERSAL')),
    reverses             uuid NULL REFERENCES finance.payment_swap (id),
    payment_id           uuid NOT NULL,
    reference            text NOT NULL,
    amount               numeric(14, 2) NOT NULL CHECK (amount > 0),
    session              text NOT NULL,
    purpose              text NOT NULL,
    channel              text NULL,
    receipt_no           text NULL,
    payment_confirmed_at timestamptz NULL,
    legacy               boolean NOT NULL DEFAULT false,
    from_student         uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    to_student           uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    reason               text NOT NULL CHECK (length(btrim(reason)) >= 20),
    evidence             text NULL,
    status               text NOT NULL DEFAULT 'PENDING_APPROVAL'
                          CHECK (status IN ('PENDING_APPROVAL', 'COMPLETED', 'REJECTED', 'CANCELLED', 'FAILED', 'REVERSED')),
    initiated_by         uuid NOT NULL,
    initiated_office     text NOT NULL,
    initiated_at         timestamptz NOT NULL DEFAULT now(),
    decided_by           uuid NULL,
    decided_office       text NULL,
    decided_at           timestamptz NULL,
    decision_note        text NULL,
    executed_at          timestamptz NULL,
    before_state         jsonb NULL,
    after_state          jsonb NULL,
    flags                text[] NOT NULL DEFAULT '{}',
    failure              text NULL,
    CONSTRAINT ck_payment_swap_students CHECK (from_student <> to_student),
    CONSTRAINT ck_payment_swap_reversal CHECK ((kind = 'REVERSAL') = (reverses IS NOT NULL))
);
-- one open swap of a payment at a time, and one completed swap standing (a reversal frees it)
CREATE UNIQUE INDEX ux_payment_swap_open ON finance.payment_swap (payment_id) WHERE status = 'PENDING_APPROVAL';
CREATE UNIQUE INDEX ux_payment_swap_done ON finance.payment_swap (payment_id) WHERE status = 'COMPLETED' AND kind = 'SWAP';
CREATE INDEX ix_payment_swap_from ON finance.payment_swap (from_student);
CREATE INDEX ix_payment_swap_to ON finance.payment_swap (to_student);
CREATE INDEX ix_payment_swap_status ON finance.payment_swap (status, initiated_at DESC);
COMMENT ON TABLE finance.payment_swap IS
  'V527: a school-fees payment moved from the student it was credited to onto the student it belongs to — the payment as it stood, both students, reason, evidence, initiation, decision and execution, the accounts before and after; a completed swap is reversed by a swap of kind REVERSAL, never edited';
SELECT audit.attach('finance.payment_swap');

CREATE TABLE finance.payment_swap_evidence (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    swap_id      uuid NOT NULL REFERENCES finance.payment_swap (id) ON DELETE CASCADE,
    filename     text NOT NULL,
    content_type text NOT NULL,
    size_bytes   bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content      bytea NULL,
    object_id    uuid NULL REFERENCES platform.file_object (id),   -- held while the row shows it (V348)
    added_by     uuid NOT NULL,
    added_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_swap_evidence_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_payment_swap_evidence ON finance.payment_swap_evidence (swap_id);
COMMENT ON TABLE finance.payment_swap_evidence IS 'V527: a file supporting a payment swap — in the file store where there is one, else here';
SELECT audit.exempt('finance.payment_swap_evidence',
    'The files supporting a payment swap; their adding is on the swap''s timeline and the swap itself is on the spine.');

CREATE TABLE finance.payment_swap_event (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    swap_id      uuid NOT NULL REFERENCES finance.payment_swap (id) ON DELETE CASCADE,
    action       text NOT NULL CHECK (action IN ('PAYMENT_SWAP_INITIATED', 'PAYMENT_SWAP_APPROVED', 'PAYMENT_SWAP_REJECTED',
                                                 'PAYMENT_SWAP_EXECUTION_STARTED', 'PAYMENT_SWAP_COMPLETED', 'PAYMENT_SWAP_FAILED',
                                                 'PAYMENT_SWAP_CANCELLED', 'PAYMENT_SWAP_REVERSED', 'PAYMENT_ALLOCATION_REMOVED',
                                                 'PAYMENT_ALLOCATION_CREATED', 'PAYMENT_SWAP_EVIDENCE_ADDED')),
    student_id   uuid NULL,
    note         text NULL,
    actor_id     uuid NULL,
    actor_office text NULL,
    source_ip    text NULL,
    at           timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_payment_swap_event ON finance.payment_swap_event (swap_id, at);
COMMENT ON TABLE finance.payment_swap_event IS 'V527: the timeline of a payment swap, written once';
SELECT audit.exempt('finance.payment_swap_event', 'The timeline of a payment swap, written once; the swap and the payment are on the spine.');
CREATE FUNCTION finance.payment_swap_event_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'PAYMENT_SWAP_EVENT_WRITTEN_ONCE: the timeline of a payment swap is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_payment_swap_event_once BEFORE UPDATE ON finance.payment_swap_event
    FOR EACH ROW EXECUTE FUNCTION finance.payment_swap_event_written_once();

CREATE FUNCTION finance.payment_swap_note(p_swap uuid, p_action text, p_student uuid, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO finance.payment_swap_event (swap_id, action, student_id, note, actor_id, actor_office, source_ip)
    VALUES (p_swap, p_action, p_student, p_note, nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''), nullif(current_setting('moaum.source_ip', true), ''))
$$;

-- a student's school-fees account for a session, as finance reads it (a clearance null where no clearance scheme is in force)
CREATE FUNCTION finance.payment_swap_account(p_student uuid, p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('due', p.due, 'paid', p.paid, 'balance', p.due - p.paid,
                              'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'),
                              'clearsExamination', finance.clears_or_null(p_student, p_session, 'EXAMINATION'))
      FROM finance.position(p_student, p_session) p
$$;

-- ── whether a payment may be swapped, and to whom ──
CREATE FUNCTION finance.payment_swap_check(p_payment uuid, p_to uuid, p_ignore_swap uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE r finance.payment_reference; f people.student; t people.student; refusals text[] := '{}'; v_done text; v_open text;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'refusals', jsonb_build_array('SWAP_NOT_FOUND: no such payment'));
    END IF;
    SELECT * INTO f FROM people.student WHERE id = r.student_id;
    IF r.purpose NOT LIKE 'School fees%' THEN
        refusals := refusals || ('SWAP_NOT_SCHOOL_FEES: the payment is ' || r.purpose || ', not school fees');
    END IF;
    IF r.confirmed_at IS NULL THEN
        refusals := refusals || 'SWAP_NOT_VERIFIED: the payment is not confirmed (pending, failed or expired); only a verified payment is swapped'::text;
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
    IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = r.student_id AND d.session = r.session AND d.superseded_at IS NULL) THEN
        refusals := refusals || 'SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the credited student''s fees for this session; the Bursary sets it aside first'::text;
    END IF;
    IF p_to IS NOT NULL THEN
        SELECT * INTO t FROM people.student WHERE id = p_to;
        IF NOT FOUND THEN
            refusals := refusals || 'SWAP_TARGET_UNKNOWN: no such student'::text;
        ELSE
            IF t.id = r.student_id THEN refusals := refusals || 'SWAP_SAME_STUDENT: Original and target student cannot be the same.'::text; END IF;
            IF t.duplicate_of IS NOT NULL THEN refusals := refusals || 'SWAP_TARGET_MERGED: the target record was merged into another; choose the student''s current record'::text; END IF;
            IF NOT finance.fee_stated(t.id, r.session) THEN
                refusals := refusals || ('SWAP_TARGET_FEES_NOT_STATED: no school fees are stated for the target student in ' || r.session || ', so the payment would count against nothing');
            END IF;
            IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = t.id AND d.session = r.session AND d.superseded_at IS NULL) THEN
                refusals := refusals || 'SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the target student''s fees for this session; the Bursary sets it aside first'::text;
            END IF;
        END IF;
    END IF;
    RETURN jsonb_build_object('ok', cardinality(refusals) = 0, 'refusals', to_jsonb(refusals),
        'payment', jsonb_build_object('id', r.id, 'reference', r.reference, 'amount', r.amount, 'session', r.session, 'purpose', r.purpose,
                                      'channel', r.channel, 'receiptNo', r.receipt_no, 'confirmedAt', r.confirmed_at, 'generatedAt', r.generated_at,
                                      'note', r.note, 'legacy', r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%',
                                      'legacyPayref', (SELECT lp.payref FROM finance.legacy_payref lp WHERE lp.reference = r.reference LIMIT 1)),
        'from', jsonb_build_object('id', f.id, 'matricNo', f.matric_no, 'name', f.surname || ', ' || f.other_names),
        'to', CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object('id', t.id, 'matricNo', t.matric_no, 'name', t.surname || ', ' || t.other_names) END);
END $$;
COMMENT ON FUNCTION finance.payment_swap_check(uuid, uuid, uuid) IS
  'V527: whether a payment may be swapped (to a student, when one is named): ok, the refusals in words (SWAP_…), the payment, the credited student and the target';

-- ── initiated: the Students Account Officer or the Bursar, for the whole payment ──
CREATE FUNCTION finance.initiate_payment_swap(p_payment uuid, p_to uuid, p_reason text, p_evidence text, p_confirmed boolean,
                                              p_reverses uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.payment_reference; chk jsonb; v uuid; v_ref text; rv finance.payment_swap; v_to uuid := p_to; v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('studentaccounts', 'bursar') THEN
        RAISE EXCEPTION 'SWAP_OFFICE: a payment swap is initiated by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_reverses IS NOT NULL THEN
        IF office <> 'bursar' THEN
            RAISE EXCEPTION 'SWAP_OFFICE: a completed swap is reversed by the Bursar' USING ERRCODE = '42501';
        END IF;
        SELECT * INTO rv FROM finance.payment_swap WHERE id = p_reverses;
        IF NOT FOUND OR rv.status <> 'COMPLETED' OR rv.kind <> 'SWAP' THEN
            RAISE EXCEPTION 'SWAP_NOT_REVERSIBLE: only a completed swap is reversed' USING ERRCODE = '23514';
        END IF;
        p_payment := rv.payment_id;
        v_to := rv.from_student;   -- the reversal takes the payment back to the student it was credited to
    END IF;
    IF length(v_reason) < 20 OR lower(v_reason) ~ '^(wrong|fix|swap|error|mistake|correction|test)[ .!]*$' THEN
        RAISE EXCEPTION 'SWAP_REASON: say why the payment belongs to the other student, in twenty characters or more' USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'SWAP_CONFIRM: confirm that you have verified the payment belongs to the target student' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;
    chk := finance.payment_swap_check(p_payment, v_to, CASE WHEN p_reverses IS NOT NULL THEN p_reverses END);
    IF NOT (chk->>'ok')::boolean THEN
        RAISE EXCEPTION '%', chk->'refusals'->>0 USING ERRCODE = '23514';
    END IF;
    v_ref := 'SWAP/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.payment_swap_no')::text, 6, '0');
    INSERT INTO finance.payment_swap (swap_ref, kind, reverses, payment_id, reference, amount, session, purpose, channel, receipt_no, payment_confirmed_at,
                                      legacy, from_student, to_student, reason, evidence, initiated_by, initiated_office)
    VALUES (v_ref, CASE WHEN p_reverses IS NULL THEN 'SWAP' ELSE 'REVERSAL' END, p_reverses, r.id, r.reference, r.amount, r.session, r.purpose,
            r.channel, r.receipt_no, r.confirmed_at, r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%', r.student_id, v_to, v_reason,
            nullif(btrim(coalesce(p_evidence, '')), ''), who, office)
    RETURNING id INTO v;
    PERFORM finance.payment_swap_note(v, 'PAYMENT_SWAP_INITIATED', r.student_id,
        coalesce('Reversal of ' || rv.swap_ref || '. ', '') || 'From ' || (chk->'from'->>'matricNo') || ' to ' || (chk->'to'->>'matricNo') || ': ' || v_reason);
    RETURN v;
END $$;
COMMENT ON FUNCTION finance.initiate_payment_swap(uuid, uuid, text, text, boolean, uuid) IS
  'V527: a payment swap initiated (the Students Account Officer or the Bursar) for the whole payment, with a reason and the confirmation, waiting for another officer''s decision; with p_reverses, the reversal of a completed swap (the Bursar)';

-- ── cancelled before a decision: by the officer who initiated it, or the Bursar ──
CREATE FUNCTION finance.cancel_payment_swap(p_swap uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s finance.payment_swap;
BEGIN
    SELECT * INTO s FROM finance.payment_swap WHERE id = p_swap FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SWAP_NOT_FOUND: no such swap' USING ERRCODE = 'P0002'; END IF;
    IF s.status <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'SWAP_DECIDED: this swap is %; it is not cancelled', lower(s.status) USING ERRCODE = '23514'; END IF;
    IF who IS DISTINCT FROM s.initiated_by AND coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'SWAP_OFFICE: a swap is cancelled by the officer who initiated it, or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'SWAP_REASON: say why the swap is cancelled' USING ERRCODE = '23514'; END IF;
    UPDATE finance.payment_swap SET status = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason) WHERE id = s.id;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_CANCELLED', NULL, btrim(p_reason));
END $$;

-- ── decided: rejected, or approved and executed at once — all of it, or nothing ──
CREATE FUNCTION finance.decide_payment_swap(p_swap uuid, p_approve boolean, p_note text, p_confirmed boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s finance.payment_swap; r finance.payment_reference; chk jsonb; v_from_before jsonb; v_to_before jsonb; v_from_after jsonb; v_to_after jsonb;
        v_total_before numeric; v_total_after numeric; v_flags text[] := '{}'; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_failure text;
        v_from people.student; v_to people.student;
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
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_EXECUTION_STARTED', NULL, NULL);
    SELECT * INTO v_from FROM people.student WHERE id = s.from_student;
    SELECT * INTO v_to FROM people.student WHERE id = s.to_student;
    v_from_before := finance.payment_swap_account(s.from_student, s.session);
    v_to_before := finance.payment_swap_account(s.to_student, s.session);
    SELECT coalesce(sum(x.amount), 0) INTO v_total_before FROM finance.payment_reference x
     WHERE x.session = s.session AND x.confirmed_at IS NOT NULL AND x.purpose LIKE 'School fees%';

    -- the credit moves; the payment itself — reference, amount, gateway, date, receipt, ledger — is untouched
    UPDATE finance.payment_reference SET student_id = s.to_student WHERE id = r.id;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_ALLOCATION_REMOVED', s.from_student, s.reference || ' no longer counts for ' || coalesce(v_from.matric_no, v_from.admission_no));
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_ALLOCATION_CREATED', s.to_student, s.reference || ' counts for ' || coalesce(v_to.matric_no, v_to.admission_no));

    v_from_after := finance.payment_swap_account(s.from_student, s.session);
    v_to_after := finance.payment_swap_account(s.to_student, s.session);
    SELECT coalesce(sum(x.amount), 0) INTO v_total_after FROM finance.payment_reference x
     WHERE x.session = s.session AND x.confirmed_at IS NOT NULL AND x.purpose LIKE 'School fees%';
    -- reconciled, or nothing: the University's school fees received unchanged, one account down and the other up by exactly the amount
    IF v_total_after <> v_total_before
       OR (v_from_before->>'paid')::numeric - (v_from_after->>'paid')::numeric <> s.amount
       OR (v_to_after->>'paid')::numeric - (v_to_before->>'paid')::numeric <> s.amount
       OR (SELECT count(*) FROM finance.payment_reference x WHERE x.reference = s.reference) <> 1 THEN
        RAISE EXCEPTION 'SWAP_RECONCILIATION: the accounts did not reconcile after the swap (received % then %, % paid % then %, % paid % then %); nothing was changed',
            v_total_before, v_total_after, v_from.matric_no, v_from_before->>'paid', v_from_after->>'paid', v_to.matric_no, v_to_before->>'paid', v_to_after->>'paid'
            USING ERRCODE = '23514';
    END IF;
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
    UPDATE finance.payment_swap SET status = 'COMPLETED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
           executed_at = now(), flags = v_flags,
           before_state = jsonb_build_object('from', v_from_before, 'to', v_to_before, 'sessionReceived', v_total_before),
           after_state = jsonb_build_object('from', v_from_after, 'to', v_to_after, 'sessionReceived', v_total_after)
     WHERE id = s.id;
    IF s.kind = 'REVERSAL' THEN
        UPDATE finance.payment_swap SET status = 'REVERSED' WHERE id = s.reverses;
        PERFORM finance.payment_swap_note(s.reverses, 'PAYMENT_SWAP_REVERSED', NULL, 'Reversed by ' || s.swap_ref || ': ' || s.reason);
    END IF;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_COMPLETED', NULL,
        to_char(s.amount, 'FM999,999,999,990.00') || ' moved from ' || coalesce(v_from.matric_no, v_from.admission_no) || ' to ' || coalesce(v_to.matric_no, v_to.admission_no));

    -- both students are told, in plain words: the reference and the swap, never the other student's details
    PERFORM platform.tell_student(s.from_student, 'FEE_PAYMENT_REALLOCATED_AWAY', NULL,
        jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00')),
        'FEE_PAYMENT_REALLOCATED_AWAY:' || s.id);
    PERFORM platform.tell_student(s.to_student, 'FEE_PAYMENT_REALLOCATED_TO', NULL,
        jsonb_build_object('REFERENCE', s.reference, 'SWAP', s.swap_ref, 'SESSION', s.session, 'AMOUNT', 'NGN ' || to_char(s.amount, 'FM999,999,999,990.00')),
        'FEE_PAYMENT_REALLOCATED_TO:' || s.id);
    RETURN jsonb_build_object('status', 'COMPLETED', 'swapRef', s.swap_ref, 'flags', to_jsonb(v_flags),
                              'before', jsonb_build_object('from', v_from_before, 'to', v_to_before),
                              'after', jsonb_build_object('from', v_from_after, 'to', v_to_after));
END $$;
COMMENT ON FUNCTION finance.decide_payment_swap(uuid, boolean, text, boolean) IS
  'V527: a payment swap decided by a Bursar officer other than the one who initiated it: rejected with a reason, or approved with the ownership confirmation and executed in the same transaction — the payment locked and checked again, its student changed and nothing else, the two accounts read before and after and the totals reconciled, or nothing; a check that no longer holds marks it FAILED';

-- ── the swaps a student's account carries, either way ──
CREATE FUNCTION finance.payment_swaps_of(p_student uuid)
RETURNS TABLE (swap_ref text, kind text, reference text, amount numeric, session text, direction text, other_matric text, executed_at timestamptz, status text)
LANGUAGE sql STABLE AS $$
    SELECT s.swap_ref, s.kind, s.reference, s.amount, s.session,
           CASE WHEN s.from_student = p_student THEN 'AWAY' ELSE 'TO' END,
           (SELECT coalesce(o.matric_no, o.admission_no) FROM people.student o WHERE o.id = CASE WHEN s.from_student = p_student THEN s.to_student ELSE s.from_student END),
           s.executed_at, s.status
      FROM finance.payment_swap s
     WHERE (s.from_student = p_student OR s.to_student = p_student) AND s.status IN ('COMPLETED', 'REVERSED')
     ORDER BY s.executed_at DESC
$$;
COMMENT ON FUNCTION finance.payment_swaps_of(uuid) IS
  'V527: the completed swaps a student''s account carries — a payment reallocated away from it (AWAY) or onto it (TO), with the other student''s number';

-- ── the notices ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('FEE_PAYMENT_REALLOCATED_AWAY', 'School fees payment reallocated away from a student',
 'To a student a school-fees payment was credited to in error, once the Bursary has moved it to the student it belongs to',
 'A school fees payment on your account has been corrected',
 E'Dear [FIRST_NAME],\n\nThe school fees payment [REFERENCE] ([AMOUNT], [SESSION]) was credited to your account in error. The Bursary has reallocated it to the student it belongs to, as payment correction [SWAP]. It no longer counts towards your [SESSION] school fees; your balance is on your fees page: [PORTAL_URL]\n\nIf you believe this is wrong, contact the Bursary with your own receipt.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: school fees payment [REFERENCE] ([AMOUNT]) credited to your account in error has been reallocated by the Bursary ([SWAP]). See your fees page.',
 'A payment on your account was corrected',
 'The school fees payment [REFERENCE] ([AMOUNT], [SESSION]) was credited to your account in error and has been reallocated by the Bursary (correction [SWAP]). It no longer counts towards your fees.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','SESSION','SWAP','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('FEE_PAYMENT_REALLOCATED_TO', 'School fees payment reallocated to a student',
 'To the student a school-fees payment belongs to, once the Bursary has moved it from the account it was credited to in error',
 'Your school fees payment has been credited to your account',
 E'Dear [FIRST_NAME],\n\nThe school fees payment [REFERENCE] ([AMOUNT], [SESSION]) was credited to another account in error. The Bursary has reallocated it to your account, as payment correction [SWAP]. It now counts towards your [SESSION] school fees; your balance is on your fees page: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your school fees payment [REFERENCE] ([AMOUNT]) has been credited to your account by the Bursary ([SWAP]). See your fees page.',
 'Your payment was credited to your account',
 'The school fees payment [REFERENCE] ([AMOUNT], [SESSION]) was credited to another account in error and has been reallocated to yours by the Bursary (correction [SWAP]). It now counts towards your fees.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','SESSION','SWAP','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL');


-- ── the old-portal reset (V499) keeps a payment under a swap — completed, reversed or waiting ──
CREATE OR REPLACE FUNCTION finance.reset_legacy_payments(p_session text, p_confirm text, p_limit integer DEFAULT 5000)
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
                   -- V527: a payment swapped to the student it belongs to stays: a reload of the export neither undoes nor doubles it
                   AND NOT EXISTS (SELECT 1 FROM finance.payment_swap w WHERE w.payment_id = r.id AND w.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL'))
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
                    OR r.id IN (SELECT g.payment_reference_id FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id IS NOT NULL)
                    OR r.id IN (SELECT w.payment_id FROM finance.payment_swap w WHERE w.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL'))) AS linked
              FROM finance.payment_reference r
             WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)) s;

    RETURN QUERY SELECT n, v_kept, nr, v_left;
END $$;

COMMIT;
