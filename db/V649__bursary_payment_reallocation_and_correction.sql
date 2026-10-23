-- ═══════════════════════════════════════
-- V649 — Bursary payment reallocation and correction: a verified payment applied to the wrong purpose, session or semester,
-- moved to the obligation it was meant for
--
--   The University's master prompt of 23 October 2026 ("BURSARY PAYMENT REALLOCATION, PURPOSE, SESSION, SEMESTER & LEVEL
--   CORRECTION"): a student meant to pay school fees and paid under Inter-Departmental Transfer; the payment is verified; the
--   Bursary moves it to the student's school fees, and the student pays only what is left.
--
--   Nothing is rebuilt. A student's obligations are read live — school fees from the fee lines (finance.position), the GST fee
--   from the Bursar's statement (finance.gst_entitlement), the deferment application fee from its setting — and each counts
--   the confirmed payments of its purpose and session. So a payment counts towards an obligation by its purpose and its session,
--   and a correction is a change of those two, made only inside an approved correction that keeps the payment as it stood:
--     · finance.payment_reallocation — the correction (REA/<year>/<number>): the payment as it stood (reference, amount, purpose,
--       session, semester, channel, receipt, when it was confirmed, whether it came from the old portal), the student and where
--       they sit, the destination (purpose, session, semester), the level the student is at in each session, the destination's
--       fee, what was paid towards it before, the balance after and any surplus, the reason (its kind and twenty characters or
--       more), the evidence, who initiated, returned, decided and when, the accounts before and after, the ledger journal, what to
--       follow up; finance.payment_reallocation_evidence (files) and finance.payment_reallocation_event (the timeline, written
--       once);
--     · finance.payment_reallocation_check — whether a payment may be moved there: a verified payment of the student (never a
--       pending, failed or expired one), not refunded, not reversed by Interswitch, not from or into a wallet, not a gateway
--       test, not the fee of a request that stands (a deferment request, a live transfer application, a hostel bed, a transcript,
--       an old-portal GST reconciliation, a GST payment the Bursary decided, an old-portal outstanding payment credited to the
--       wallet), not under an open swap or correction, not already corrected (a correction is reversed, never edited), no
--       overpayment decision standing on the session's school fees; the destination a purpose the finance engine keeps an account
--       for — school fees (any amount: a balance is paid as usual), the GST fee or the deferment application fee (each paid in one:
--       the payment covers what is left of it) — in a session on the calendar, a semester of that session, with the fee stated,
--       and for the GST fee owed or shown to the student, for the deferment fee the student eligible and holding no unspent fee;
--     · finance.initiate_payment_reallocation — the Students Account Officer or the Bursar, with the reason and the confirmation;
--       finance.resubmit_payment_reallocation (one returned for correction) and finance.cancel_payment_reallocation;
--     · finance.decide_payment_reallocation — a Bursar officer other than the one who initiated it returns it for correction,
--       rejects it, or approves it, and an approval is executed in the same transaction: the correction and the payment locked,
--       everything checked again; the payment's purpose and session changed and nothing else (its reference, amount, student,
--       channel, gateway record, dates and receipt untouched); a deferment fee given or set aside as the move asks; the ledger
--       reclassified where the payment is on it (Dr the income account it was booked to, Cr the one it belongs to — no bank line,
--       so no new money and no revenue counted twice); the accounts read before and after and reconciled (the student's money
--       received unchanged, the source down and the destination up by exactly the amount) — or nothing at all; a check that no
--       longer holds marks it FAILED;
--     · a completed correction is reversed by one of its own (kind REVERSAL) under the same approval, the payment back where it
--       was;
--     · the balances, clearances and entitlements read the payments as they stand, so they follow the correction and nothing
--       else: a balance left is paid through the normal payment page; a surplus is an overpayment for the Bursary's own
--       overpayment and refund screens (Refunds & Credits), flagged; the student is told (FEE_PAYMENT_PURPOSE_CORRECTED);
--     · the old-portal reset (V499, V631) keeps a corrected payment, so a reload neither undoes nor doubles it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V649: Bursary payment reallocation and correction (the University, 23 October 2026)', true);

-- ── 1 · the purpose, semester and wording a payment's label carries ─────────────────────────────────────────────────────
CREATE FUNCTION finance.purpose_code_of(p_purpose text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT c.purpose FROM finance.payment_category c WHERE c.code = finance.categorise(NULL, p_purpose)), 'OTHER')
$$;
COMMENT ON FUNCTION finance.purpose_code_of(text) IS 'V649: the purpose (finance.payment_purpose) a payment of this label is for, as the reports read it';

CREATE FUNCTION finance.purpose_semester(p_purpose text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_purpose ~* '\msemester\s*1\M|\m(first|1st)\s+semester' THEN 1
                WHEN p_purpose ~* '\msemester\s*2\M|\m(second|2nd)\s+semester' THEN 2 END
$$;
COMMENT ON FUNCTION finance.purpose_semester(text) IS 'V649: the semester a payment''s label names (the old portal''s "· semester 2", "first semester"), or NULL';

CREATE FUNCTION finance.reallocation_purpose_text(p_code text, p_session text, p_semester int)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_code
        WHEN 'SCHOOL_FEES' THEN 'School fees ' || p_session || CASE p_semester WHEN 1 THEN ' · first semester' WHEN 2 THEN ' · second semester' ELSE '' END
        WHEN 'GST_FEE' THEN 'GST fee ' || p_session
        WHEN 'DEFERMENT_FEE' THEN 'Deferment application fee' END
$$;
COMMENT ON FUNCTION finance.reallocation_purpose_text(text, text, int) IS
  'V649: the label a payment corrected to a purpose carries — the one every reader of that obligation counts (School fees…, GST fee…, Deferment application fee)';

-- the purposes of the University's catalogue (V409), each saying whether a payment can be moved onto it and how it counts
CREATE FUNCTION finance.reallocation_destinations()
RETURNS TABLE (code text, label text, supported boolean, how text) LANGUAGE sql STABLE AS $$
    SELECT p.code, p.label, p.code IN ('SCHOOL_FEES', 'GST_FEE', 'DEFERMENT_FEE'),
           CASE p.code
               WHEN 'SCHOOL_FEES' THEN 'Counts towards the session''s school fees; any balance is paid through the normal payment page'
               WHEN 'GST_FEE' THEN 'Pays the session''s GST fee (and EPS, where the GST fee covers it); the payment must cover what is left of the fee'
               WHEN 'DEFERMENT_FEE' THEN 'Pays the deferment application fee; the payment must cover the fee'
               ELSE 'Paid through its own request (' || lower(p.label) || '); a payment is not moved onto it here' END
      FROM finance.payment_purpose p
     WHERE p.active AND p.code <> 'GATEWAY_TEST'
     ORDER BY p.ord, p.code
$$;
COMMENT ON FUNCTION finance.reallocation_destinations() IS
  'V649: the payment purposes (finance.payment_purpose), each with whether a payment may be reallocated onto it and how it then counts';

-- ── 2 · an obligation as the finance engine reads it: the fee, what is paid towards it, the balance ─────────────────────
-- p_exclude: a payment left out of what is paid (the one being moved, where it already counts there)
CREATE FUNCTION finance.reallocation_account(p_student uuid, p_code text, p_session text, p_exclude uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE pos record; g record; v_less numeric := 0; v_fee numeric; v_held numeric;
BEGIN
    IF p_code = 'SCHOOL_FEES' THEN
        SELECT * INTO pos FROM finance.position(p_student, p_session);
        SELECT coalesce(sum(r.amount), 0) INTO v_less FROM finance.payment_reference r
         WHERE r.id = p_exclude AND r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%';
        RETURN jsonb_build_object('code', p_code, 'kind', 'SESSION_ACCOUNT', 'stated', finance.fee_stated(p_student, p_session),
            'fee', pos.due, 'paid', pos.paid - v_less, 'balance', finance.fee_owed(pos.due, pos.paid - v_less),
            'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'),
            'clearsExamination', finance.clears_or_null(p_student, p_session, 'EXAMINATION'));
    ELSIF p_code = 'GST_FEE' THEN
        SELECT * INTO g FROM finance.gst_entitlement(p_student, p_session);
        SELECT coalesce(sum(r.amount - finance.gst_refunded(r.reference)), 0) INTO v_less FROM finance.payment_reference r
         WHERE r.id = p_exclude AND r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'GST fee %';
        RETURN jsonb_build_object('code', p_code, 'kind', 'SINGLE_FEE', 'stated', coalesce(g.stated, false), 'fee', coalesce(g.fee, 0),
            'paid', coalesce(g.paid, 0) - v_less, 'balance', greatest(coalesce(g.fee, 0) - (coalesce(g.paid, 0) - v_less), 0),
            'required', coalesce(g.required, false),
            'shown', EXISTS (SELECT 1 FROM finance.gst_payable_courses(p_student, p_session)),
            'entitled', coalesce(g.entitled, false));
    ELSIF p_code = 'DEFERMENT_FEE' THEN
        v_fee := coalesce((SELECT s.fee FROM people.deferment_setting s WHERE s.id = 1), 0);
        SELECT coalesce(sum(f.amount), 0) INTO v_held FROM people.deferment_fee f
          JOIN finance.payment_reference r ON r.reference = f.reference
         WHERE f.student_id = p_student AND f.state = 'CONFIRMED' AND f.used_by IS NULL AND r.id IS DISTINCT FROM p_exclude;
        RETURN jsonb_build_object('code', p_code, 'kind', 'SINGLE_FEE', 'stated', v_fee > 0, 'fee', v_fee, 'paid', v_held,
            'balance', greatest(v_fee - v_held, 0), 'held', v_held > 0);
    END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION finance.reallocation_account(uuid, text, text, uuid) IS
  'V649: a student''s obligation of a purpose in a session as the finance engine reads it — the fee, what is paid towards it (one payment left out where asked), the balance; NULL for a purpose the engine keeps no account of';

-- ── 3 · the correction, its evidence and its timeline ───────────────────────────────────────────────────────────────────
CREATE SEQUENCE finance.payment_reallocation_no;

CREATE TABLE finance.payment_reallocation (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    realloc_ref          text NOT NULL UNIQUE,
    kind                 text NOT NULL DEFAULT 'REALLOCATION' CHECK (kind IN ('REALLOCATION', 'REVERSAL')),
    reverses             uuid NULL REFERENCES finance.payment_reallocation (id),
    payment_id           uuid NOT NULL,
    reference            text NOT NULL,
    amount               numeric(14, 2) NOT NULL CHECK (amount > 0),
    channel              text NULL,
    receipt_no           text NULL,
    payment_confirmed_at timestamptz NULL,
    legacy               boolean NOT NULL DEFAULT false,
    student_id           uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    programme_code       text NULL,
    dept_code            text NULL,
    faculty_code         text NULL,
    from_purpose         text NOT NULL,
    from_purpose_code    text NOT NULL,
    from_session         text NOT NULL,
    from_semester        int NULL CHECK (from_semester IN (1, 2, 3)),
    from_level           int NULL,
    to_purpose_code      text NOT NULL,
    to_purpose           text NOT NULL,
    to_session           text NOT NULL,
    to_semester          int NULL CHECK (to_semester IN (1, 2, 3)),
    to_level             int NULL,
    destination_fee      numeric(14, 2) NULL,
    paid_before          numeric(14, 2) NULL,
    balance_after        numeric(14, 2) NULL,
    surplus              numeric(14, 2) NOT NULL DEFAULT 0,
    reason_code          text NOT NULL CHECK (reason_code IN ('WRONG_PURPOSE', 'WRONG_SESSION', 'WRONG_SEMESTER', 'WRONG_LEVEL',
                                                              'LEGACY_MIGRATION', 'RECONCILIATION', 'OTHER')),
    reason               text NOT NULL CHECK (length(btrim(reason)) >= 20),
    evidence             text NULL,
    status               text NOT NULL DEFAULT 'PENDING_APPROVAL'
                          CHECK (status IN ('PENDING_APPROVAL', 'RETURNED', 'COMPLETED', 'REJECTED', 'CANCELLED', 'FAILED', 'REVERSED')),
    initiated_by         uuid NOT NULL,
    initiated_office     text NOT NULL,
    initiated_at         timestamptz NOT NULL DEFAULT now(),
    submitted_at         timestamptz NOT NULL DEFAULT now(),
    returned_by          uuid NULL,
    returned_at          timestamptz NULL,
    returned_note        text NULL,
    decided_by           uuid NULL,
    decided_office       text NULL,
    decided_at           timestamptz NULL,
    decision_note        text NULL,
    executed_at          timestamptz NULL,
    before_state         jsonb NULL,
    after_state          jsonb NULL,
    gl_journal           uuid NULL,
    flags                text[] NOT NULL DEFAULT '{}',
    failure              text NULL,
    CONSTRAINT ck_payment_reallocation_reversal CHECK ((kind = 'REVERSAL') = (reverses IS NOT NULL))
);
-- one open correction of a payment at a time, and one completed correction standing (a reversal frees it)
CREATE UNIQUE INDEX ux_payment_reallocation_open ON finance.payment_reallocation (payment_id) WHERE status IN ('PENDING_APPROVAL', 'RETURNED');
CREATE UNIQUE INDEX ux_payment_reallocation_done ON finance.payment_reallocation (payment_id) WHERE status = 'COMPLETED' AND kind = 'REALLOCATION';
CREATE INDEX ix_payment_reallocation_student ON finance.payment_reallocation (student_id);
CREATE INDEX ix_payment_reallocation_status ON finance.payment_reallocation (status, initiated_at DESC);
CREATE INDEX ix_payment_reallocation_reference ON finance.payment_reallocation (upper(reference));
COMMENT ON TABLE finance.payment_reallocation IS
  'V649: a verified payment moved from the purpose, session or semester it was applied to onto the one it was meant for — the payment as it stood, the destination with its fee and balance, reason, evidence, initiation, return, decision and execution, the accounts before and after and the ledger journal; a completed correction is reversed by one of kind REVERSAL, never edited';
SELECT audit.attach('finance.payment_reallocation');

CREATE TABLE finance.payment_reallocation_evidence (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reallocation_id uuid NOT NULL REFERENCES finance.payment_reallocation (id) ON DELETE CASCADE,
    filename        text NOT NULL,
    content_type    text NOT NULL,
    size_bytes      bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content         bytea NULL,
    object_id       uuid NULL REFERENCES platform.file_object (id),   -- held while the row shows it (V348)
    added_by        uuid NOT NULL,
    added_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_reallocation_evidence_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_payment_reallocation_evidence ON finance.payment_reallocation_evidence (reallocation_id);
COMMENT ON TABLE finance.payment_reallocation_evidence IS 'V649: a file supporting a payment correction — in the file store where there is one, else here';
SELECT audit.exempt('finance.payment_reallocation_evidence',
    'The files supporting a payment correction; their adding is on the correction''s timeline and the correction itself is on the spine.');

CREATE TABLE finance.payment_reallocation_event (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reallocation_id uuid NOT NULL REFERENCES finance.payment_reallocation (id) ON DELETE CASCADE,
    action          text NOT NULL CHECK (action IN ('REALLOCATION_INITIATED', 'REALLOCATION_RESUBMITTED', 'REALLOCATION_RETURNED',
                                                    'REALLOCATION_EVIDENCE_ADDED', 'REALLOCATION_APPROVED', 'REALLOCATION_REJECTED',
                                                    'REALLOCATION_CANCELLED', 'REALLOCATION_EXECUTION_STARTED', 'PAYMENT_ALLOCATION_REMOVED',
                                                    'PAYMENT_ALLOCATION_CREATED', 'LEDGER_RECLASSIFIED', 'REALLOCATION_COMPLETED',
                                                    'REALLOCATION_FAILED', 'REALLOCATION_REVERSED')),
    note            text NULL,
    actor_id        uuid NULL,
    actor_office    text NULL,
    source_ip       text NULL,
    at              timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_payment_reallocation_event ON finance.payment_reallocation_event (reallocation_id, at);
COMMENT ON TABLE finance.payment_reallocation_event IS 'V649: the timeline of a payment correction, written once';
SELECT audit.exempt('finance.payment_reallocation_event', 'The timeline of a payment correction, written once; the correction and the payment are on the spine.');
CREATE FUNCTION finance.payment_reallocation_event_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'REALLOC_EVENT_WRITTEN_ONCE: the timeline of a payment correction is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_payment_reallocation_event_once BEFORE UPDATE ON finance.payment_reallocation_event
    FOR EACH ROW EXECUTE FUNCTION finance.payment_reallocation_event_written_once();

CREATE FUNCTION finance.payment_reallocation_note(p_id uuid, p_action text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO finance.payment_reallocation_event (reallocation_id, action, note, actor_id, actor_office, source_ip)
    VALUES (p_id, p_action, p_note, nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''), nullif(current_setting('moaum.source_ip', true), ''))
$$;

-- ── 4 · whether a payment may be moved, and where ──────────────────────────────────────────────────────────────────────
-- p_ignore: the correction being decided or resubmitted (with the one a reversal reverses), never a reason to refuse itself;
-- p_restore: a reversal's destination — the label the payment carried before the correction it reverses
CREATE FUNCTION finance.payment_reallocation_check(p_payment uuid, p_code text, p_session text, p_semester int,
                                                   p_ignore uuid DEFAULT NULL, p_restore text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE r finance.payment_reference; s people.student; refusals text[] := '{}'; v_text text; v_open text; v_done text; v_code text;
        v_from_code text; v_from_sem int; v_from_level int; v_to_level int; v_sem int := p_semester; v_ignore uuid[];
        v_src jsonb; v_dst jsonb; v_src_after numeric; v_paid_before numeric; v_fee numeric; v_paid_after numeric; v_balance numeric;
        v_surplus numeric; v_how text; v_supported boolean; v_ta record; el record; v_session text := btrim(coalesce(p_session, ''));
        v_prog record;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'refusals', jsonb_build_array('REALLOC_NOT_FOUND: no such payment'));
    END IF;
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    v_ignore := ARRAY[p_ignore, (SELECT x.reverses FROM finance.payment_reallocation x WHERE x.id = p_ignore)];
    v_from_code := finance.purpose_code_of(r.purpose);
    v_from_sem := finance.purpose_semester(r.purpose);
    v_from_level := people.level_in(s.id, r.session, coalesce(v_from_sem, 1));

    -- the payment: verified, standing, the student's own money, not tied to anything else
    IF r.confirmed_at IS NULL THEN
        refusals := refusals || 'REALLOC_NOT_VERIFIED: the payment is not confirmed (pending, failed or expired); only a verified payment is corrected'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.refund x WHERE x.source_reference = r.reference AND x.state <> 'REJECTED') THEN
        refusals := refusals || 'REALLOC_REFUNDED: a refund stands against this payment'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.paydirect_inbox x WHERE x.reference = r.reference AND x.is_reversal) THEN
        refusals := refusals || 'REALLOC_REVERSED: Interswitch reported this payment reversed'::text;
    END IF;
    IF r.channel = 'NELFUND wallet' OR r.purpose ~* '^(e-?)?wallet top-?up' OR EXISTS (SELECT 1 FROM finance.wallet_entry x WHERE x.reference = r.reference) THEN
        refusals := refusals || 'REALLOC_WALLET: the payment was made from or into the student''s wallet; the wallet keeps it'::text;
    END IF;
    IF r.purpose ILIKE 'gateway test%' OR EXISTS (SELECT 1 FROM finance.gateway_test_reference x WHERE x.reference = r.reference) THEN
        refusals := refusals || 'REALLOC_NOT_A_FEE: the payment is a gateway test by the Bursary, not a fee'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation x WHERE x.payment_reference_id = r.id) THEN
        refusals := refusals || 'REALLOC_LINKED: the payment is reconciled as an old-portal GST payment (Old GST Payments)'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.gst_payment_review x WHERE x.reference = r.reference) THEN
        refusals := refusals || 'REALLOC_LINKED: the Bursary has decided this GST payment (kept or refunded) on the GST fee review'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment x WHERE x.payment_id = r.id AND x.status = 'CREDITED') THEN
        refusals := refusals || 'REALLOC_LINKED: the payment is an old-portal outstanding fees payment already credited to the wallet'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM people.deferment_fee x WHERE x.reference = r.reference AND x.used_by IS NOT NULL) THEN
        refusals := refusals || 'REALLOC_LINKED: the payment is the fee of a deferment request already made'::text;
    END IF;
    SELECT t.id, t.state INTO v_ta FROM people.transfer_application t
     WHERE t.fee_reference = r.reference AND t.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED', 'EFFECTED') LIMIT 1;
    IF v_ta.id IS NOT NULL THEN
        refusals := refusals || ('REALLOC_LINKED: the payment is the fee of an inter-departmental transfer application that stands (' || lower(replace(v_ta.state, '_', ' '))
                                 || '); it is withdrawn first');
    END IF;
    IF r.channel IS DISTINCT FROM 'Legacy' AND r.purpose ~* '^(hostel accommodation|transcript)' THEN
        refusals := refusals || 'REALLOC_LINKED: the payment is tied to its own request (a hostel bed space or a transcript); it is not moved'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.payment_swap x WHERE x.payment_id = r.id AND x.status = 'PENDING_APPROVAL') THEN
        refusals := refusals || 'REALLOC_OPEN: a payment swap of this payment waits for a decision'::text;
    END IF;
    SELECT x.realloc_ref INTO v_open FROM finance.payment_reallocation x
     WHERE x.payment_id = r.id AND x.status IN ('PENDING_APPROVAL', 'RETURNED') AND x.id <> ALL (array_remove(v_ignore, NULL));
    IF v_open IS NOT NULL THEN
        refusals := refusals || ('REALLOC_OPEN: correction ' || v_open || ' of this payment is open');
    END IF;
    SELECT x.realloc_ref INTO v_done FROM finance.payment_reallocation x
     WHERE x.payment_id = r.id AND x.status = 'COMPLETED' AND x.kind = 'REALLOCATION' AND x.id <> ALL (array_remove(v_ignore, NULL));
    IF v_done IS NOT NULL THEN
        refusals := refusals || ('REALLOC_ALREADY: This payment has already been reallocated (' || v_done || '); a further correction is a reversal of it');
    END IF;
    IF s.duplicate_of IS NOT NULL THEN
        refusals := refusals || 'REALLOC_STUDENT_MERGED: the student''s record was merged into another; the payment is corrected on the record it now belongs to'::text;
    END IF;

    -- the destination
    IF p_restore IS NOT NULL THEN
        v_text := p_restore;
        v_code := finance.purpose_code_of(p_restore);
        v_sem := finance.purpose_semester(p_restore);
        v_supported := true;
    ELSIF p_code IS NOT NULL THEN
        v_code := upper(btrim(p_code));
        SELECT d.supported, d.how INTO v_supported, v_how FROM finance.reallocation_destinations() d WHERE d.code = v_code;
        IF v_supported IS NULL THEN
            refusals := refusals || ('REALLOC_PURPOSE_UNKNOWN: ' || v_code || ' is not a payment purpose of the University''s catalogue');
        ELSIF NOT v_supported THEN
            refusals := refusals || ('REALLOC_PURPOSE_UNSUPPORTED: ' || v_how);
        END IF;
        IF v_code <> 'SCHOOL_FEES' THEN v_sem := NULL; END IF;   -- the GST and deferment fees are the session's, not a semester's
        IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_session) THEN
            refusals := refusals || ('REALLOC_SESSION_UNKNOWN: ' || coalesce(nullif(v_session, ''), 'no session') || ' is not a session of the University''s calendar');
        ELSIF v_sem IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.semester m WHERE m.session = v_session AND m.number = v_sem) THEN
            refusals := refusals || ('REALLOC_SEMESTER_UNKNOWN: ' || v_session || ' has no semester ' || v_sem);
        END IF;
        IF coalesce(v_supported, false) THEN
            v_text := finance.reallocation_purpose_text(v_code, v_session, v_sem);
        END IF;
    END IF;

    IF v_text IS NOT NULL THEN
        IF p_restore IS NULL THEN
            IF v_code = v_from_code AND v_session = r.session AND v_sem IS NOT DISTINCT FROM v_from_sem THEN
                refusals := refusals || ('REALLOC_SAME: the payment already counts as ' || r.purpose || ' (' || r.session || ')');
            END IF;
        END IF;
        IF EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_session) THEN
            v_to_level := people.level_in(s.id, v_session, coalesce(v_sem, 1));
        END IF;
        -- the obligation the payment lands on, without this payment, and what it leaves
        v_dst := finance.reallocation_account(s.id, v_code, v_session, r.id);
        IF v_dst IS NOT NULL THEN
            v_fee := (v_dst->>'fee')::numeric;
            v_paid_before := (v_dst->>'paid')::numeric;
            v_paid_after := v_paid_before + r.amount;
            v_balance := CASE WHEN v_code = 'SCHOOL_FEES' THEN finance.fee_owed(v_fee, v_paid_after) ELSE greatest(v_fee - v_paid_after, 0) END;
            v_surplus := greatest(v_paid_after - v_fee, 0);
        END IF;
        IF p_restore IS NULL AND coalesce(v_supported, false) THEN
            IF v_code = 'SCHOOL_FEES' AND NOT (v_dst->>'stated')::boolean THEN
                refusals := refusals || ('REALLOC_FEES_NOT_STATED: no school fees are stated for this student in ' || v_session || ', so the payment would count against nothing');
            ELSIF v_code = 'GST_FEE' THEN
                IF NOT (v_dst->>'stated')::boolean OR v_fee <= 0 THEN
                    refusals := refusals || ('REALLOC_GST_NOT_STATED: the Bursar has stated no GST fee for this student in ' || v_session);
                ELSIF NOT (v_dst->>'required')::boolean AND NOT (v_dst->>'shown')::boolean THEN
                    refusals := refusals || ('REALLOC_GST_NOT_OWED: no GST fee is owed for ' || v_session || ' (no GST or EPS course requires it of this student or is offered to them)');
                ELSIF v_paid_before >= v_fee THEN
                    refusals := refusals || ('REALLOC_GST_PAID: the GST fee for ' || v_session || ' is already paid');
                ELSIF r.amount < v_fee - v_paid_before THEN
                    refusals := refusals || ('REALLOC_GST_SHORT: the GST fee is paid in one: NGN ' || to_char(v_fee - v_paid_before, 'FM999,999,999,990.00')
                                             || ' is left of it and this payment is NGN ' || to_char(r.amount, 'FM999,999,999,990.00'));
                END IF;
            ELSIF v_code = 'DEFERMENT_FEE' THEN
                IF v_fee <= 0 THEN
                    refusals := refusals || 'REALLOC_DEFERMENT_NO_FEE: no deferment application fee is stated'::text;
                ELSIF (v_dst->>'held')::boolean THEN
                    refusals := refusals || 'REALLOC_DEFERMENT_HELD: the student already holds a paid deferment application fee not yet used'::text;
                ELSIF r.amount < v_fee THEN
                    refusals := refusals || ('REALLOC_DEFERMENT_SHORT: the deferment application fee is NGN ' || to_char(v_fee, 'FM999,999,999,990.00')
                                             || ', paid in one; this payment is NGN ' || to_char(r.amount, 'FM999,999,999,990.00'));
                ELSE
                    SELECT * INTO el FROM people.deferment_eligibility(s.id);
                    IF NOT coalesce(el.eligible, false) THEN
                        refusals := refusals || ('REALLOC_DEFERMENT_NOT_ELIGIBLE: ' || coalesce(el.reason, 'the student may not request a deferment'));
                    END IF;
                END IF;
            END IF;
        END IF;
        -- an overpayment decision is taken on the session's school fees as they stood: set aside before they change
        IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = s.id AND d.superseded_at IS NULL
                     AND ((v_from_code = 'SCHOOL_FEES' AND d.session = r.session) OR (v_code = 'SCHOOL_FEES' AND d.session = v_session))) THEN
            refusals := refusals || 'REALLOC_OVERPAYMENT_DECISION: an overpayment decision stands on the student''s school fees for the session; the Bursary sets it aside first'::text;
        END IF;
    END IF;

    -- the obligation the payment leaves
    v_src := finance.reallocation_account(s.id, v_from_code, r.session, NULL);
    IF v_src IS NOT NULL THEN
        v_src_after := (v_src->>'paid')::numeric - CASE WHEN r.confirmed_at IS NOT NULL THEN r.amount ELSE 0 END;
    END IF;
    SELECT p.code, p.name, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty INTO v_prog
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
     WHERE p.code = s.programme_code;

    RETURN jsonb_build_object('ok', cardinality(refusals) = 0, 'refusals', to_jsonb(refusals),
        'payment', jsonb_build_object('id', r.id, 'reference', r.reference, 'amount', r.amount, 'session', r.session, 'purpose', r.purpose,
                                      'channel', r.channel, 'receiptNo', r.receipt_no, 'confirmedAt', r.confirmed_at, 'generatedAt', r.generated_at,
                                      'legacy', r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%',
                                      'legacyPayref', (SELECT lp.payref FROM finance.legacy_payref lp WHERE lp.reference = r.reference LIMIT 1)),
        'student', jsonb_build_object('id', s.id, 'matricNo', s.matric_no, 'admissionNo', s.admission_no, 'jambRegNo', s.jamb_reg_no,
                                      'name', s.surname || ', ' || s.other_names, 'status', s.status, 'level', s.current_level,
                                      'entryMode', s.entry_mode, 'studyMode', s.study_mode,
                                      'programmeType', finance.programme_type_for(s.entry_mode, (SELECT p.category FROM ref.programme p WHERE p.code = s.programme_code)),
                                      'programmeCode', v_prog.code, 'programme', v_prog.name, 'deptCode', v_prog.dept_code, 'department', v_prog.department,
                                      'facultyCode', v_prog.faculty_code, 'faculty', v_prog.faculty),
        'source', jsonb_build_object('code', v_from_code, 'label', (SELECT p.label FROM finance.payment_purpose p WHERE p.code = v_from_code),
                                     'purpose', r.purpose, 'session', r.session, 'semester', v_from_sem, 'level', v_from_level,
                                     'account', v_src, 'paidAfter', v_src_after),
        'destination', CASE WHEN v_text IS NULL THEN NULL ELSE jsonb_build_object(
                                     'code', v_code, 'label', (SELECT p.label FROM finance.payment_purpose p WHERE p.code = v_code),
                                     'purpose', v_text, 'session', v_session, 'semester', v_sem, 'level', v_to_level, 'account', v_dst,
                                     'fee', v_fee, 'paidBefore', v_paid_before, 'applied', r.amount, 'paidAfter', v_paid_after,
                                     'balance', v_balance, 'surplus', v_surplus,
                                     'outcome', CASE WHEN v_fee IS NULL THEN NULL WHEN v_surplus > 0 THEN 'OVERPAID' WHEN v_balance > 0 THEN 'PART_PAID' ELSE 'FULLY_PAID' END) END);
END $$;
COMMENT ON FUNCTION finance.payment_reallocation_check(uuid, text, text, int, uuid, text) IS
  'V649: whether a payment may be reallocated to a purpose, session and semester: ok, the refusals in words (REALLOC_…), the payment, the student and where they sit, the source obligation (before and after) and the destination (its fee, what is paid without this payment, applied, the balance and any surplus)';

-- ── 5 · initiated: the Students Account Officer or the Bursar ───────────────────────────────────────────────────────────
CREATE FUNCTION finance.reallocation_reason_refused(p_reason text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT length(btrim(coalesce(p_reason, ''))) < 20
        OR lower(btrim(p_reason)) ~ '^(wrong|fix|error|mistake|correction|reallocation|reallocate|test|update)[ .!]*$'
$$;

CREATE FUNCTION finance.initiate_payment_reallocation(p_payment uuid, p_code text, p_session text, p_semester int, p_reason_code text,
                                                      p_reason text, p_evidence text, p_confirmed boolean, p_reverses uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.payment_reference; chk jsonb; v uuid; v_ref text; rv finance.payment_reallocation; v_reason text := btrim(coalesce(p_reason, ''));
        v_restore text; d jsonb; st jsonb;
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('studentaccounts', 'bursar') THEN
        RAISE EXCEPTION 'REALLOC_OFFICE: a payment correction is initiated by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_reverses IS NOT NULL THEN
        IF office <> 'bursar' THEN
            RAISE EXCEPTION 'REALLOC_OFFICE: a completed correction is reversed by the Bursar' USING ERRCODE = '42501';
        END IF;
        SELECT * INTO rv FROM finance.payment_reallocation WHERE id = p_reverses;
        IF NOT FOUND OR rv.status <> 'COMPLETED' OR rv.kind <> 'REALLOCATION' THEN
            RAISE EXCEPTION 'REALLOC_NOT_REVERSIBLE: only a completed correction is reversed' USING ERRCODE = '23514';
        END IF;
        p_payment := rv.payment_id;
        v_restore := rv.from_purpose;
        p_session := rv.from_session;
        p_reason_code := coalesce(p_reason_code, 'OTHER');
    END IF;
    IF coalesce(p_reason_code, '') NOT IN ('WRONG_PURPOSE', 'WRONG_SESSION', 'WRONG_SEMESTER', 'WRONG_LEVEL', 'LEGACY_MIGRATION', 'RECONCILIATION', 'OTHER') THEN
        RAISE EXCEPTION 'REALLOC_REASON: choose what was wrong — the purpose, the session, the semester, the level, an old-portal migration, a reconciliation, or other' USING ERRCODE = '23514';
    END IF;
    IF finance.reallocation_reason_refused(v_reason) THEN
        RAISE EXCEPTION 'REALLOC_REASON: say why the payment belongs to the other purpose or period, in twenty characters or more' USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'REALLOC_CONFIRM: confirm that you have checked the payment and the obligation it is moved to' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;
    chk := finance.payment_reallocation_check(p_payment, p_code, p_session, p_semester, p_reverses, v_restore);
    IF NOT (chk->>'ok')::boolean THEN
        RAISE EXCEPTION '%', chk->'refusals'->>0 USING ERRCODE = '23514';
    END IF;
    d := chk->'destination';
    st := chk->'student';
    v_ref := 'REA/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.payment_reallocation_no')::text, 6, '0');
    INSERT INTO finance.payment_reallocation (realloc_ref, kind, reverses, payment_id, reference, amount, channel, receipt_no, payment_confirmed_at, legacy,
                                              student_id, programme_code, dept_code, faculty_code,
                                              from_purpose, from_purpose_code, from_session, from_semester, from_level,
                                              to_purpose_code, to_purpose, to_session, to_semester, to_level,
                                              destination_fee, paid_before, balance_after, surplus, reason_code, reason, evidence, initiated_by, initiated_office)
    VALUES (v_ref, CASE WHEN p_reverses IS NULL THEN 'REALLOCATION' ELSE 'REVERSAL' END, p_reverses, r.id, r.reference, r.amount, r.channel, r.receipt_no,
            r.confirmed_at, r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%', r.student_id, st->>'programmeCode', st->>'deptCode', st->>'facultyCode',
            r.purpose, chk->'source'->>'code', r.session, (chk->'source'->>'semester')::int, (chk->'source'->>'level')::int,
            d->>'code', d->>'purpose', d->>'session', (d->>'semester')::int, (d->>'level')::int,
            (d->>'fee')::numeric, (d->>'paidBefore')::numeric, (d->>'balance')::numeric, coalesce((d->>'surplus')::numeric, 0),
            p_reason_code, v_reason, nullif(btrim(coalesce(p_evidence, '')), ''), who, office)
    RETURNING id INTO v;
    PERFORM finance.payment_reallocation_note(v, 'REALLOCATION_INITIATED',
        coalesce('Reversal of ' || rv.realloc_ref || '. ', '') || r.purpose || ' (' || r.session || ') to ' || (d->>'purpose') || ' (' || (d->>'session') || '): ' || v_reason);
    RETURN v;
END $$;
COMMENT ON FUNCTION finance.initiate_payment_reallocation(uuid, text, text, int, text, text, text, boolean, uuid) IS
  'V649: a payment correction initiated (the Students Account Officer or the Bursar) for the whole payment, with what was wrong, a reason and the confirmation, waiting for another officer''s decision; with p_reverses, the reversal of a completed correction (the Bursar), the payment back to the purpose and session it carried';

-- returned for correction: changed and sent again by the officer who initiated it, or the Bursar
CREATE FUNCTION finance.resubmit_payment_reallocation(p_id uuid, p_code text, p_session text, p_semester int, p_reason_code text,
                                                      p_reason text, p_evidence text, p_confirmed boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        x finance.payment_reallocation; chk jsonb; d jsonb; v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    SELECT * INTO x FROM finance.payment_reallocation WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'REALLOC_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF x.status <> 'RETURNED' THEN RAISE EXCEPTION 'REALLOC_DECIDED: this correction is %; only one returned for correction is sent again', lower(replace(x.status, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF who IS DISTINCT FROM x.initiated_by AND coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'REALLOC_OFFICE: a returned correction is sent again by the officer who initiated it, or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF x.kind = 'REVERSAL' THEN
        RAISE EXCEPTION 'REALLOC_NOT_REVERSIBLE: a reversal is not changed; cancel it and reverse again' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_reason_code, '') NOT IN ('WRONG_PURPOSE', 'WRONG_SESSION', 'WRONG_SEMESTER', 'WRONG_LEVEL', 'LEGACY_MIGRATION', 'RECONCILIATION', 'OTHER') THEN
        RAISE EXCEPTION 'REALLOC_REASON: choose what was wrong' USING ERRCODE = '23514';
    END IF;
    IF finance.reallocation_reason_refused(v_reason) THEN
        RAISE EXCEPTION 'REALLOC_REASON: say why the payment belongs to the other purpose or period, in twenty characters or more' USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'REALLOC_CONFIRM: confirm that you have checked the payment and the obligation it is moved to' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM finance.payment_reference WHERE id = x.payment_id FOR UPDATE;
    chk := finance.payment_reallocation_check(x.payment_id, p_code, p_session, p_semester, x.id, NULL);
    IF NOT (chk->>'ok')::boolean THEN RAISE EXCEPTION '%', chk->'refusals'->>0 USING ERRCODE = '23514'; END IF;
    d := chk->'destination';
    UPDATE finance.payment_reallocation
       SET to_purpose_code = d->>'code', to_purpose = d->>'purpose', to_session = d->>'session', to_semester = (d->>'semester')::int, to_level = (d->>'level')::int,
           destination_fee = (d->>'fee')::numeric, paid_before = (d->>'paidBefore')::numeric, balance_after = (d->>'balance')::numeric,
           surplus = coalesce((d->>'surplus')::numeric, 0), reason_code = p_reason_code, reason = v_reason,
           evidence = coalesce(nullif(btrim(coalesce(p_evidence, '')), ''), evidence), status = 'PENDING_APPROVAL', submitted_at = now()
     WHERE id = x.id;
    PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_RESUBMITTED', (d->>'purpose') || ' (' || (d->>'session') || '): ' || v_reason);
END $$;

-- cancelled before a decision: by the officer who initiated it, or the Bursar
CREATE FUNCTION finance.cancel_payment_reallocation(p_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        x finance.payment_reallocation;
BEGIN
    SELECT * INTO x FROM finance.payment_reallocation WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'REALLOC_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF x.status NOT IN ('PENDING_APPROVAL', 'RETURNED') THEN
        RAISE EXCEPTION 'REALLOC_DECIDED: this correction is %; it is not cancelled', lower(replace(x.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF who IS DISTINCT FROM x.initiated_by AND coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'REALLOC_OFFICE: a correction is cancelled by the officer who initiated it, or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'REALLOC_REASON: say why the correction is cancelled' USING ERRCODE = '23514'; END IF;
    UPDATE finance.payment_reallocation SET status = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason) WHERE id = x.id;
    PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_CANCELLED', btrim(p_reason));
END $$;

-- ── 6 · decided: returned, rejected, or approved and executed at once — all of it, or nothing ──────────────────────────
CREATE FUNCTION finance.decide_payment_reallocation(p_id uuid, p_decision text, p_note text, p_confirmed boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        x finance.payment_reallocation; r finance.payment_reference; chk jsonb; d jsonb; v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_failure text; v_decision text := upper(btrim(coalesce(p_decision, ''))); v_src_before jsonb; v_dst_before jsonb; v_src_after jsonb; v_dst_after jsonb;
        v_cash_before numeric; v_cash_after numeric; v_flags text[] := '{}'; v_journal uuid; v_from_acc text; v_to_acc text; v_posted uuid;
        v_same boolean; v_fee numeric; v_student people.student; v_balance numeric; v_surplus numeric; v_dfee numeric;
BEGIN
    IF who IS NULL OR coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'REALLOC_OFFICE: a payment correction is decided by a Bursar officer other than the one who initiated it' USING ERRCODE = '42501';
    END IF;
    IF v_decision NOT IN ('APPROVE', 'REJECT', 'RETURN') THEN
        RAISE EXCEPTION 'REALLOC_DECISION: a correction is approved, returned for correction or rejected' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM finance.payment_reallocation WHERE id = p_id FOR UPDATE;   -- one decision at a time
    IF NOT FOUND THEN RAISE EXCEPTION 'REALLOC_NOT_FOUND: no such correction' USING ERRCODE = 'P0002'; END IF;
    IF x.status <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'REALLOC_DECIDED: this correction is %', lower(replace(x.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF x.initiated_by = who THEN
        RAISE EXCEPTION 'REALLOC_SAME_OFFICER: the officer who initiated a correction does not decide it; another officer does' USING ERRCODE = '42501';
    END IF;
    IF v_decision IN ('REJECT', 'RETURN') THEN
        IF v_note IS NULL OR length(v_note) < 10 THEN
            RAISE EXCEPTION 'REALLOC_REASON: say why the correction is %', CASE v_decision WHEN 'REJECT' THEN 'rejected' ELSE 'returned' END USING ERRCODE = '23514';
        END IF;
        IF v_decision = 'REJECT' THEN
            UPDATE finance.payment_reallocation SET status = 'REJECTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note WHERE id = x.id;
            PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_REJECTED', v_note);
            RETURN jsonb_build_object('status', 'REJECTED', 'reallocationRef', x.realloc_ref);
        END IF;
        UPDATE finance.payment_reallocation SET status = 'RETURNED', returned_by = who, returned_at = now(), returned_note = v_note WHERE id = x.id;
        PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_RETURNED', v_note);
        RETURN jsonb_build_object('status', 'RETURNED', 'reallocationRef', x.realloc_ref);
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'REALLOC_CONFIRM: confirm that the payment belongs to the obligation it is moved to' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_APPROVED', v_note);

    -- execution: the payment locked and everything checked again
    SELECT * INTO r FROM finance.payment_reference WHERE id = x.payment_id FOR UPDATE;
    chk := finance.payment_reallocation_check(x.payment_id, x.to_purpose_code, x.to_session, x.to_semester, x.id,
                                              CASE WHEN x.kind = 'REVERSAL' THEN x.to_purpose END);
    v_failure := CASE WHEN r.id IS NULL THEN 'the payment is no longer on record'
                      WHEN r.student_id <> x.student_id THEN 'the payment is no longer the student''s (it was swapped since the correction was initiated)'
                      WHEN r.amount <> x.amount OR r.reference <> x.reference THEN 'the payment changed since the correction was initiated'
                      WHEN r.purpose <> x.from_purpose OR r.session <> x.from_session THEN 'the payment''s purpose or session changed since the correction was initiated'
                      WHEN (chk->'destination'->>'purpose') IS DISTINCT FROM x.to_purpose THEN 'the destination is no longer the one approved'
                      WHEN jsonb_array_length(chk->'refusals') > 0 THEN chk->'refusals'->>0 END;
    IF v_failure IS NOT NULL THEN
        UPDATE finance.payment_reallocation SET status = 'FAILED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
               failure = v_failure WHERE id = x.id;
        PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_FAILED', v_failure);
        RETURN jsonb_build_object('status', 'FAILED', 'reallocationRef', x.realloc_ref, 'failure', v_failure);
    END IF;
    PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_EXECUTION_STARTED', NULL);
    d := chk->'destination';
    SELECT * INTO v_student FROM people.student WHERE id = x.student_id;
    v_same := x.from_purpose_code = x.to_purpose_code AND x.from_session = x.to_session;
    v_src_before := finance.reallocation_account(x.student_id, x.from_purpose_code, x.from_session, NULL);
    v_dst_before := finance.reallocation_account(x.student_id, x.to_purpose_code, x.to_session, NULL);
    SELECT coalesce(sum(p.amount), 0) INTO v_cash_before FROM finance.payment_reference p WHERE p.student_id = x.student_id AND p.confirmed_at IS NOT NULL;

    -- the payment counts towards the purpose and session it was meant for; nothing else of it changes
    UPDATE finance.payment_reference SET purpose = x.to_purpose, session = x.to_session WHERE id = r.id;
    INSERT INTO finance.category_memo (kind, purpose, code)   -- the reports' memo of each label's category (V427), as a new payment's label is
    SELECT '', x.to_purpose, finance.categorise(NULL, x.to_purpose)
     WHERE NOT EXISTS (SELECT 1 FROM finance.category_memo m WHERE m.kind = '' AND m.purpose = x.to_purpose)
    ON CONFLICT DO NOTHING;
    PERFORM finance.payment_reallocation_note(x.id, 'PAYMENT_ALLOCATION_REMOVED', x.reference || ' no longer counts as ' || x.from_purpose || ' (' || x.from_session || ')');
    -- a deferment fee the payment was (unspent) is set aside; one it becomes is given, confirmed as the payment was
    UPDATE people.deferment_fee SET state = 'CANCELLED' WHERE reference = r.reference AND used_by IS NULL AND x.to_purpose_code <> 'DEFERMENT_FEE';
    IF x.to_purpose_code = 'DEFERMENT_FEE' THEN
        v_dfee := coalesce((SELECT s.fee FROM people.deferment_setting s WHERE s.id = 1), 0);
        INSERT INTO people.deferment_fee (student_id, session, reference, amount, state, confirmed_at, receipt_no)
        VALUES (x.student_id, x.to_session, r.reference, least(v_dfee, r.amount), 'CONFIRMED', r.confirmed_at, r.receipt_no)
        ON CONFLICT (reference) DO UPDATE SET state = 'CONFIRMED', session = EXCLUDED.session, amount = EXCLUDED.amount,
                                              confirmed_at = EXCLUDED.confirmed_at, receipt_no = EXCLUDED.receipt_no
            WHERE people.deferment_fee.used_by IS NULL;
    END IF;
    PERFORM finance.payment_reallocation_note(x.id, 'PAYMENT_ALLOCATION_CREATED', x.reference || ' counts as ' || x.to_purpose || ' (' || x.to_session || ')');

    -- the ledger: income moved from the account the payment was booked to onto the one it belongs to, the bank untouched
    v_from_acc := finance.gl_income_account(finance.payment_category(x.from_purpose));
    v_to_acc := finance.gl_income_account(finance.payment_category(x.to_purpose));
    SELECT g.id INTO v_posted FROM finance.gl_journal g WHERE g.source_type = 'PAYMENT' AND g.source_ref = r.reference AND g.status = 'POSTED';
    IF v_posted IS NOT NULL AND (v_from_acc <> v_to_acc OR x.from_session <> x.to_session) THEN
        v_journal := finance.gl_post((now() AT TIME ZONE 'Africa/Lagos')::date,
            'Payment correction ' || x.realloc_ref || ' of fee receipt ' || x.reference || ' — ' || x.from_purpose || ' to ' || x.to_purpose,
            'AUTO', 'REALLOCATION', x.realloc_ref,
            jsonb_build_array(
                jsonb_build_object('account', v_from_acc, 'debit', x.amount, 'narration', x.from_purpose, 'session', x.from_session),
                jsonb_build_object('account', v_to_acc, 'credit', x.amount, 'narration', x.to_purpose, 'session', x.to_session)));
        PERFORM finance.payment_reallocation_note(x.id, 'LEDGER_RECLASSIFIED',
            'Dr ' || v_from_acc || ' Cr ' || v_to_acc || ' NGN ' || to_char(x.amount, 'FM999,999,999,990.00') || '; no bank line');
    END IF;

    v_src_after := finance.reallocation_account(x.student_id, x.from_purpose_code, x.from_session, NULL);
    v_dst_after := finance.reallocation_account(x.student_id, x.to_purpose_code, x.to_session, NULL);
    SELECT coalesce(sum(p.amount), 0) INTO v_cash_after FROM finance.payment_reference p WHERE p.student_id = x.student_id AND p.confirmed_at IS NOT NULL;
    -- reconciled, or nothing: the student's money received unchanged, the obligation left down and the one met up by exactly the amount
    IF v_cash_after <> v_cash_before
       OR (SELECT count(*) FROM finance.payment_reference p WHERE p.reference = x.reference) <> 1
       OR (NOT v_same AND x.from_purpose_code IN ('SCHOOL_FEES', 'GST_FEE')
           AND (v_src_before->>'paid')::numeric - (v_src_after->>'paid')::numeric <> x.amount)
       OR (NOT v_same AND x.to_purpose_code IN ('SCHOOL_FEES', 'GST_FEE')
           AND (v_dst_after->>'paid')::numeric - (v_dst_before->>'paid')::numeric <> x.amount)
       OR (v_same AND v_dst_before IS NOT NULL AND (v_dst_after->>'paid')::numeric <> (v_dst_before->>'paid')::numeric)
       OR (x.to_purpose_code = 'DEFERMENT_FEE' AND NOT EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = x.reference AND f.state = 'CONFIRMED')) THEN
        RAISE EXCEPTION 'REALLOC_RECONCILIATION: the accounts did not reconcile after the correction (received % then %; % paid % then %; % paid % then %); nothing was changed',
            v_cash_before, v_cash_after, x.from_purpose, v_src_before->>'paid', v_src_after->>'paid', x.to_purpose, v_dst_before->>'paid', v_dst_after->>'paid'
            USING ERRCODE = '23514';
    END IF;

    -- the destination as it now stands, and what to follow up
    v_fee := (d->>'fee')::numeric;
    v_balance := (d->>'balance')::numeric;
    v_surplus := coalesce((d->>'surplus')::numeric, 0);
    IF v_surplus > 0 THEN v_flags := v_flags || 'DESTINATION_OVERPAID'::text; END IF;
    IF coalesce(v_balance, 0) > 0 THEN v_flags := v_flags || 'BALANCE_TO_PAY'::text; END IF;
    IF x.from_purpose_code = 'SCHOOL_FEES' AND NOT v_same AND NOT coalesce((v_src_after->>'clearsRegistration')::boolean, true)
       AND EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = x.student_id AND cr.session = x.from_session
                     AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
        v_flags := v_flags || 'SOURCE_REGISTRATION_UNCLEARED'::text;
    END IF;
    IF x.from_purpose_code = 'GST_FEE' AND NOT v_same AND (v_src_after->>'required')::boolean AND NOT (v_src_after->>'entitled')::boolean THEN
        v_flags := v_flags || 'SOURCE_GST_UNPAID'::text;
    END IF;
    UPDATE finance.payment_reallocation
       SET status = 'COMPLETED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note, executed_at = now(),
           destination_fee = v_fee, paid_before = (d->>'paidBefore')::numeric, balance_after = v_balance, surplus = v_surplus,
           gl_journal = v_journal, flags = v_flags,
           before_state = jsonb_build_object('source', v_src_before, 'destination', v_dst_before, 'received', v_cash_before),
           after_state = jsonb_build_object('source', v_src_after, 'destination', v_dst_after, 'received', v_cash_after)
     WHERE id = x.id;
    IF x.kind = 'REVERSAL' THEN
        UPDATE finance.payment_reallocation SET status = 'REVERSED' WHERE id = x.reverses;
        PERFORM finance.payment_reallocation_note(x.reverses, 'REALLOCATION_REVERSED', 'Reversed by ' || x.realloc_ref || ': ' || x.reason);
    END IF;
    PERFORM finance.payment_reallocation_note(x.id, 'REALLOCATION_COMPLETED',
        'NGN ' || to_char(x.amount, 'FM999,999,999,990.00') || ' moved from ' || x.from_purpose || ' (' || x.from_session || ') to ' || x.to_purpose || ' (' || x.to_session || ')'
        || CASE WHEN coalesce(v_balance, 0) > 0 THEN '; NGN ' || to_char(v_balance, 'FM999,999,999,990.00') || ' left to pay' ELSE '' END
        || CASE WHEN v_surplus > 0 THEN '; NGN ' || to_char(v_surplus, 'FM999,999,999,990.00') || ' paid beyond the fee' ELSE '' END);

    -- the student is told, once the money has moved
    PERFORM platform.tell_student(x.student_id, 'FEE_PAYMENT_PURPOSE_CORRECTED', NULL,
        jsonb_build_object('REFERENCE', x.reference, 'REALLOCATION', x.realloc_ref, 'AMOUNT', 'NGN ' || to_char(x.amount, 'FM999,999,999,990.00'),
                           'FROM_PURPOSE', x.from_purpose || ' (' || x.from_session || ')', 'TO_PURPOSE', x.to_purpose || ' (' || x.to_session || ')',
                           'BALANCE', CASE WHEN v_fee IS NULL THEN 'see your fees page'
                                           WHEN coalesce(v_balance, 0) > 0 THEN 'NGN ' || to_char(v_balance, 'FM999,999,999,990.00') || ' left to pay'
                                           ELSE 'nothing left to pay' END),
        'FEE_PAYMENT_PURPOSE_CORRECTED:' || x.id);
    RETURN jsonb_build_object('status', 'COMPLETED', 'reallocationRef', x.realloc_ref, 'flags', to_jsonb(v_flags), 'balance', v_balance, 'surplus', v_surplus,
                              'journal', v_journal, 'before', jsonb_build_object('source', v_src_before, 'destination', v_dst_before),
                              'after', jsonb_build_object('source', v_src_after, 'destination', v_dst_after));
END $$;
COMMENT ON FUNCTION finance.decide_payment_reallocation(uuid, text, text, boolean) IS
  'V649: a payment correction decided by a Bursar officer other than the one who initiated it: returned for correction or rejected with a reason, or approved with the confirmation and executed in the same transaction — the payment locked and checked again, its purpose and session changed and nothing else, a deferment fee given or set aside, the ledger reclassified (no bank line), the accounts read before and after and reconciled, or nothing; a check that no longer holds marks it FAILED';

-- ── 7 · the corrections a student's account carries ────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.payment_reallocations_of(p_student uuid)
RETURNS TABLE (realloc_ref text, kind text, reference text, amount numeric, from_purpose text, from_session text, to_purpose text, to_session text,
               balance_after numeric, executed_at timestamptz, status text)
LANGUAGE sql STABLE AS $$
    SELECT x.realloc_ref, x.kind, x.reference, x.amount, x.from_purpose, x.from_session, x.to_purpose, x.to_session, x.balance_after, x.executed_at, x.status
      FROM finance.payment_reallocation x
     WHERE x.student_id = p_student AND x.status IN ('COMPLETED', 'REVERSED')
     ORDER BY x.executed_at DESC
$$;
COMMENT ON FUNCTION finance.payment_reallocations_of(uuid) IS 'V649: the completed corrections of a student''s payments — from which purpose and session to which';

-- ── 8 · the notice ─────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('FEE_PAYMENT_PURPOSE_CORRECTED', 'Payment reallocated to the right purpose or period',
 'To a student whose verified payment the Bursary has moved from the purpose, session or semester it was applied to onto the one it was meant for',
 'Your payment has been reallocated',
 E'Dear [FIRST_NAME],\n\nYour payment [REFERENCE] ([AMOUNT]) was applied to [FROM_PURPOSE]. The Bursary has reallocated it to [TO_PURPOSE], as payment correction [REALLOCATION]. Your payment, its reference and its receipt are unchanged; you have not been charged again. Balance: [BALANCE]. Your fees page shows where you stand: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your payment [REFERENCE] ([AMOUNT]) has been reallocated by the Bursary to [TO_PURPOSE] ([REALLOCATION]). Balance: [BALANCE].',
 'Your payment was reallocated',
 'Your payment [REFERENCE] ([AMOUNT]) was applied to [FROM_PURPOSE] and has been reallocated by the Bursary to [TO_PURPOSE] (correction [REALLOCATION]). Balance: [BALANCE].',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','FROM_PURPOSE','TO_PURPOSE','REALLOCATION','BALANCE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL');

-- ── 9 · the old-portal reset (V499, V631) keeps a payment under a correction — completed, reversed or open ──────────────
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
                   -- V631: an OUTSTANDING FEES payment credited to the student's wallet stays
                   AND NOT EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment c WHERE c.payment_id = r.id AND c.status = 'CREDITED')
                   -- V649: a payment the Bursary corrected (or is correcting) to another purpose or period stays
                   AND NOT EXISTS (SELECT 1 FROM finance.payment_reallocation x WHERE x.payment_id = r.id AND x.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL', 'RETURNED'))
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
                    OR r.id IN (SELECT w.payment_id FROM finance.payment_swap w WHERE w.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL'))
                    OR r.id IN (SELECT c.payment_id FROM finance.legacy_outstanding_payment c WHERE c.status = 'CREDITED')
                    OR r.id IN (SELECT x.payment_id FROM finance.payment_reallocation x WHERE x.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL', 'RETURNED'))) AS linked
              FROM finance.payment_reference r
             WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)) s;

    RETURN QUERY SELECT n, v_kept, nr, v_left;
END $$;

COMMIT;
