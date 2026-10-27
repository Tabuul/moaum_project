-- ═══════════════════════════════════════
-- V670 — Payments archived for review: a duplicate, wrongly credited or unverified payment kept, out of every figure, until the
-- Bursary settles it
--
--   The University's master prompt of 27 October 2026 ("PAYMENT ARCHIVE, DUPLICATE PAYMENT DETECTION & PAYMENT OWNERSHIP
--   RECONCILIATION"): the same payment shows twice; a payment sits on a student who did not make it; such a payment is never
--   deleted — it is archived, kept for the audit, left out of income and of the student's paid figures until it is verified, and
--   then credited to its true owner through the controlled finance workflow.
--
--   Nothing is rebuilt. A student payment stays the one row of finance.payment_reference it always was; every balance, clearance,
--   entitlement, report and the ledger read it live. V670 adds:
--     · finance.payment_reference.archived_at — the one mark: set while the payment is archived (and for good once it is confirmed
--       a duplicate or never received), and every reader of confirmed payments now reads "confirmed and not archived" (the
--       readers restated below: positions, the registration and results gates, GST, the spillover panel, the historical fees,
--       reports, the day book, the Bursary's collections, the ledger sync, the master report, reporting.payments). The payment's
--       reference, amount, student, purpose, session, channel, receipt and dates are kept as they stood while it is archived: a
--       trigger refuses any change to them, and refuses a delete, outside the archive's own settling;
--     · finance.payment_archive — the archive record (PAR/<year>/<number>): the payment as it stood, why it was archived (the
--       Bursary's list, finance.payment_archive_reason), the payment it repeats and the duplicate signals read from the gateway's
--       and the old portal's identifiers (finance.payment_duplicate_signals: a shared gateway or transaction reference, an old
--       payment number — never the amount, the student, the day or the purpose alone), the investigation's evidence (each item
--       strong or supporting), the proposal (restore to the student it stands on, reallocate to its true owner through the
--       payment swap of V527, confirm it a duplicate, or confirm it never reached the bank), the Bursar's decision, the ledger
--       journals and the accounts before and after; its files and its timeline (written once);
--     · the workflow: the Students Account Officer or the Bursar archives a payment (a reason and a note; a payment tied to
--       something that stands — a refund, a wallet, an open swap or correction, an overpayment decision, a deferment request, a
--       transfer application — is settled first), records the investigation, and proposes; a Bursar officer other than the one
--       who proposed approves, returns or rejects; an approval is executed at once — restored or reallocated (the payment counts
--       again, for its owner), or excluded for good (a duplicate, or never received) — or nothing changes;
--     · the ledger: an archived payment already posted is reclassified out of income into 2400 Payments under review (Dr income,
--       Cr 2400: the bank keeps the money received); restored or reallocated, back into income (Dr 2400, Cr income); a duplicate
--       or a payment never received has both its posting and the reclassification reversed; an archived payment not yet posted
--       is left unposted until it is settled;
--     · the old portal's withdrawals (V448 records twice, V498 doubles, V502 doubles under an item, V561 never received) archive
--       the record for good instead of deleting it: a payment is never deleted;
--     · the student told in plain words (never another student's details), the Bursar's office told what waits;
--     · finance.payment_archive_figures (verified active revenue against what is archived), finance.payment_duplicate_suspects,
--       finance.payment_archives_of (a student's archived payments, apart from the verified ones).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V670: payments archived for review (the University, 27 October 2026)', true);

-- ── 1 · the mark on the payment ─────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.payment_reference ADD COLUMN archived_at timestamptz NULL;
COMMENT ON COLUMN finance.payment_reference.archived_at IS
  'V670: when the payment was archived for review (finance.payment_archive); while set, the payment counts nowhere — not as income, not towards a fee, not for any entitlement — and nothing of it changes; cleared only when the Bursary restores or reallocates it';
CREATE INDEX ix_pref_archived ON finance.payment_reference (student_id, session) WHERE archived_at IS NOT NULL;

-- ── 2 · where an archived payment's income waits ────────────────────────────────────────────────────────────────────────
INSERT INTO finance.gl_account (code, name, type, normal_side, parent_code, postable, active, ord)
VALUES ('2400', 'Payments under review', 'LIABILITY', 'C', '2000', true, true, 24)
ON CONFLICT (code) DO NOTHING;

-- ── 3 · why a payment is archived ───────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.payment_archive_reason (
    code          text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z_]{2,39}$'),
    label         text NOT NULL,
    explanation   text NOT NULL,
    needs_related boolean NOT NULL DEFAULT false,
    ord           int NOT NULL DEFAULT 0,
    active        boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE finance.payment_archive_reason IS
  'V670: the reasons the Bursary archives a payment for review; needs_related: the archive names the payment this one repeats';
SELECT audit.attach('finance.payment_archive_reason');
INSERT INTO finance.payment_archive_reason (code, label, explanation, needs_related, ord) VALUES
('DUPLICATE_PAYMENT',               'Duplicate payment',                  'The same payment is on record twice; this record repeats another', true, 10),
('DUPLICATE_GATEWAY_REFERENCE',     'Duplicate gateway reference',        'The gateway''s reference of this payment is on another payment record', true, 20),
('DUPLICATE_TRANSACTION_REFERENCE', 'Duplicate transaction reference',    'The transaction reference of this payment is on another payment record', true, 30),
('WRONG_STUDENT',                   'Wrong student',                      'The payment stands on a student who did not make it', false, 40),
('UNKNOWN_OWNER',                   'Owner unknown',                      'Whose payment this is has not been established', false, 50),
('PAYMENT_OWNERSHIP_DISPUTE',       'Ownership disputed',                 'More than one student claims the payment', false, 60),
('INCORRECT_ALLOCATION',            'Incorrect allocation',               'The payment was applied where it does not belong', false, 70),
('INCORRECT_PURPOSE',               'Incorrect purpose',                  'The payment counts towards a purpose it was not made for', false, 80),
('INCORRECT_SESSION',               'Incorrect session',                  'The payment counts towards a session it was not made for', false, 90),
('INCORRECT_SEMESTER',              'Incorrect semester',                 'The payment counts towards a semester it was not made for', false, 100),
('MIGRATION_ERROR',                 'Migration error',                    'The payment came from the old portal''s data wrongly', false, 110),
('LEGACY_RECONCILIATION',           'Old-portal reconciliation',          'The old portal''s payment is being reconciled', false, 120),
('UNVERIFIED_PAYMENT',              'Payment not verified',               'Whether the money reached the University''s account has not been verified', false, 130),
('OTHER',                           'Other',                              'Another reason, given in the note', false, 900);

-- ── 4 · the archive, its files and its timeline ─────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.payment_archive (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_ref          text NOT NULL UNIQUE,
    payment_id           uuid NOT NULL REFERENCES finance.payment_reference (id) ON DELETE CASCADE,
    -- the payment as it stood when it was archived
    reference            text NOT NULL,
    amount               numeric(14, 2) NOT NULL CHECK (amount > 0),
    purpose              text NOT NULL,
    session              text NOT NULL,
    channel              text NULL,
    receipt_no           text NULL,
    payment_confirmed_at timestamptz NOT NULL,
    legacy               boolean NOT NULL DEFAULT false,
    student_id           uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    source               text NOT NULL DEFAULT 'DESK' CHECK (source IN ('DESK', 'DUPLICATE_WITHDRAWAL', 'NOT_RECEIVED_WITHDRAWAL')),
    reason_code          text NOT NULL REFERENCES finance.payment_archive_reason (code),
    related_payment_id   uuid NULL REFERENCES finance.payment_reference (id) ON DELETE SET NULL,
    related_reference    text NULL,
    signals              jsonb NOT NULL DEFAULT '{}'::jsonb,
    archive_note         text NOT NULL CHECK (length(btrim(archive_note)) >= 10),
    held                 jsonb NOT NULL DEFAULT '{}'::jsonb,
    archived_by          uuid NOT NULL,
    archived_office      text NOT NULL,
    archived_at          timestamptz NOT NULL DEFAULT now(),
    state                text NOT NULL DEFAULT 'ARCHIVED'
                          CHECK (state IN ('ARCHIVED', 'UNDER_REVIEW', 'PENDING_BURSAR_APPROVAL', 'RETURNED', 'RECONCILED', 'DUPLICATE_CONFIRMED', 'NOT_RECEIVED')),
    -- the investigation and the proposal
    evidence             jsonb NOT NULL DEFAULT '[]'::jsonb,
    outcome              text NULL CHECK (outcome IN ('RESTORE', 'REALLOCATE', 'DUPLICATE', 'NOT_RECEIVED')),
    owner_student_id     uuid NULL REFERENCES people.student (id) ON DELETE SET NULL,
    proposal_note        text NULL,
    proposed_by          uuid NULL,
    proposed_office      text NULL,
    proposed_at          timestamptz NULL,
    swap_id              uuid NULL REFERENCES finance.payment_swap (id),
    returned_by          uuid NULL,
    returned_at          timestamptz NULL,
    returned_note        text NULL,
    -- the Bursar's decision
    decision             text NULL CHECK (decision IN ('APPROVE', 'REJECT', 'RETURN')),
    decided_by           uuid NULL,
    decided_office       text NULL,
    decided_at           timestamptz NULL,
    decision_note        text NULL,
    settled_at           timestamptz NULL,
    -- the ledger and the accounts
    archive_journal      uuid NULL REFERENCES finance.gl_journal (id),
    settle_journal       uuid NULL REFERENCES finance.gl_journal (id),
    payment_journal      uuid NULL REFERENCES finance.gl_journal (id),
    payment_reversal     uuid NULL REFERENCES finance.gl_journal (id),
    before_state         jsonb NULL,
    after_state          jsonb NULL,
    failure              text NULL,
    CONSTRAINT ck_par_settled CHECK ((state IN ('RECONCILED', 'DUPLICATE_CONFIRMED', 'NOT_RECEIVED')) = (settled_at IS NOT NULL)),
    CONSTRAINT ck_par_owner CHECK (outcome IS DISTINCT FROM 'REALLOCATE' OR owner_student_id IS NOT NULL),
    CONSTRAINT ck_par_two_officers CHECK (source <> 'DESK' OR decision IS DISTINCT FROM 'APPROVE' OR decided_by IS DISTINCT FROM proposed_by),
    CONSTRAINT ck_par_related CHECK (related_payment_id IS DISTINCT FROM payment_id)
);
-- one archive stands on a payment at a time; a payment restored or reallocated may be archived again later
CREATE UNIQUE INDEX ux_payment_archive_standing ON finance.payment_archive (payment_id) WHERE state <> 'RECONCILED';
CREATE INDEX ix_payment_archive_state ON finance.payment_archive (state, archived_at DESC);
CREATE INDEX ix_payment_archive_student ON finance.payment_archive (student_id);
CREATE INDEX ix_payment_archive_owner ON finance.payment_archive (owner_student_id) WHERE owner_student_id IS NOT NULL;
CREATE INDEX ix_payment_archive_reference ON finance.payment_archive (upper(reference));
CREATE INDEX ix_payment_archive_payment ON finance.payment_archive (payment_id);
CREATE INDEX ix_payment_archive_swap ON finance.payment_archive (swap_id) WHERE swap_id IS NOT NULL;
COMMENT ON TABLE finance.payment_archive IS
  'V670: a payment archived for review — the payment as it stood, why, the payment it repeats and the duplicate signals, the investigation''s evidence, the proposal (restore, reallocate to its owner, duplicate, never received), the Bursar''s decision, the ledger journals and the accounts before and after; kept for good';
SELECT audit.attach('finance.payment_archive');

CREATE TABLE finance.payment_archive_file (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_id   uuid NOT NULL REFERENCES finance.payment_archive (id) ON DELETE CASCADE,
    filename     text NOT NULL,
    content_type text NOT NULL,
    size_bytes   bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content      bytea NULL,
    object_id    uuid NULL REFERENCES platform.file_object (id),
    added_by     uuid NOT NULL,
    added_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_archive_file_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_payment_archive_file ON finance.payment_archive_file (archive_id);
COMMENT ON TABLE finance.payment_archive_file IS 'V670: a file supporting an archived payment''s investigation — in the file store where there is one, else here';
SELECT audit.exempt('finance.payment_archive_file',
    'The files supporting an archived payment''s investigation; their adding is on the archive''s timeline and the archive itself is on the spine.');

CREATE TABLE finance.payment_archive_event (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    archive_id uuid NOT NULL REFERENCES finance.payment_archive (id) ON DELETE CASCADE,
    action     text NOT NULL CHECK (action IN ('ARCHIVED', 'INVESTIGATION_RECORDED', 'EVIDENCE_ADDED', 'PROPOSED', 'RESUBMITTED', 'RETURNED', 'REJECTED',
                                               'APPROVED', 'RESTORED', 'REALLOCATED', 'DUPLICATE_CONFIRMED', 'NOT_RECEIVED_CONFIRMED',
                                               'LEDGER_RECLASSIFIED', 'LEDGER_REVERSED', 'FAILED', 'WITHDRAWN_AS_DOUBLE', 'WITHDRAWN_NOT_RECEIVED')),
    note       text NULL,
    actor_id   uuid NULL,
    actor_office text NULL,
    source_ip  text NULL,
    at         timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_payment_archive_event ON finance.payment_archive_event (archive_id, at);
COMMENT ON TABLE finance.payment_archive_event IS 'V670: the timeline of an archived payment, written once';
SELECT audit.exempt('finance.payment_archive_event', 'The timeline of an archived payment, written once; the archive and the payment are on the spine.');
CREATE FUNCTION finance.payment_archive_event_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'PAR_EVENT_WRITTEN_ONCE: the timeline of an archived payment is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_payment_archive_event_once BEFORE UPDATE ON finance.payment_archive_event
    FOR EACH ROW EXECUTE FUNCTION finance.payment_archive_event_written_once();

CREATE FUNCTION finance.payment_archive_note(p_id uuid, p_action text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO finance.payment_archive_event (archive_id, action, note, actor_id, actor_office, source_ip)
    VALUES (p_id, p_action, p_note, nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''), nullif(current_setting('moaum.source_ip', true), ''))
$$;

-- the archive record is kept as it was written: the payment as it stood is never changed, and the record never removed (but by
-- the go-live reset, moaum.maintenance)
CREATE FUNCTION finance.payment_archive_kept()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF coalesce(current_setting('moaum.maintenance', true), '') <> 'on' THEN
            RAISE EXCEPTION 'PAR_KEPT: archive % is kept for good', OLD.archive_ref USING ERRCODE = '23514';
        END IF;
        RETURN OLD;
    END IF;
    IF (NEW.archive_ref, NEW.payment_id, NEW.reference, NEW.amount, NEW.purpose, NEW.session, NEW.channel, NEW.receipt_no, NEW.payment_confirmed_at,
        NEW.legacy, NEW.student_id, NEW.source, NEW.archived_by, NEW.archived_office, NEW.archived_at)
       IS DISTINCT FROM
       (OLD.archive_ref, OLD.payment_id, OLD.reference, OLD.amount, OLD.purpose, OLD.session, OLD.channel, OLD.receipt_no, OLD.payment_confirmed_at,
        OLD.legacy, OLD.student_id, OLD.source, OLD.archived_by, OLD.archived_office, OLD.archived_at) THEN
        RAISE EXCEPTION 'PAR_KEPT: archive % keeps the payment as it stood when it was archived', OLD.archive_ref USING ERRCODE = '23514';
    END IF;
    IF OLD.state IN ('DUPLICATE_CONFIRMED', 'NOT_RECEIVED') AND NEW.state IS DISTINCT FROM OLD.state THEN
        RAISE EXCEPTION 'PAR_SETTLED: archive % is settled (%)', OLD.archive_ref, lower(replace(OLD.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_payment_archive_kept BEFORE UPDATE OR DELETE ON finance.payment_archive
    FOR EACH ROW EXECUTE FUNCTION finance.payment_archive_kept();

-- ── 5 · the payment kept as it stood while it is archived, and never deleted ────────────────────────────────────────────
-- the archive's own functions settle a payment inside moaum.payment_archive = 'settling'; nothing else sets or clears the mark,
-- changes an archived payment, or deletes a payment the archive holds (but the go-live reset, moaum.maintenance)
CREATE FUNCTION finance.payment_archive_settling(p_on boolean)
RETURNS void LANGUAGE sql AS $$
    SELECT set_config('moaum.payment_archive', CASE WHEN p_on THEN 'settling' ELSE '' END, true)
$$;

CREATE FUNCTION finance.payment_archive_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_settling boolean := coalesce(current_setting('moaum.payment_archive', true), '') = 'settling'; v_ref text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF coalesce(current_setting('moaum.maintenance', true), '') <> 'on' THEN
            SELECT a.archive_ref INTO v_ref FROM finance.payment_archive a WHERE a.payment_id = OLD.id ORDER BY a.archived_at DESC LIMIT 1;
            IF v_ref IS NOT NULL OR OLD.archived_at IS NOT NULL THEN
                RAISE EXCEPTION 'PAYMENT_ARCHIVE_KEPT: payment % is held in the payment archive (%); a payment is never deleted', OLD.reference, coalesce(v_ref, 'archived')
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.archived_at IS NOT NULL AND NOT v_settling THEN
            RAISE EXCEPTION 'PAYMENT_ARCHIVE_DESK: a payment is archived on the Archived payments desk, never written archived' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.archived_at IS DISTINCT FROM OLD.archived_at AND NOT v_settling THEN
        RAISE EXCEPTION 'PAYMENT_ARCHIVE_DESK: payment % is archived or restored only on the Archived payments desk', OLD.reference USING ERRCODE = '23514';
    END IF;
    IF OLD.archived_at IS NOT NULL AND NOT v_settling
       AND (NEW.student_id, NEW.session, NEW.reference, NEW.purpose, NEW.amount, NEW.confirmed_at, NEW.confirmed_by, NEW.channel, NEW.receipt_no, NEW.generated_at)
           IS DISTINCT FROM
           (OLD.student_id, OLD.session, OLD.reference, OLD.purpose, OLD.amount, OLD.confirmed_at, OLD.confirmed_by, OLD.channel, OLD.receipt_no, OLD.generated_at) THEN
        SELECT a.archive_ref INTO v_ref FROM finance.payment_archive a WHERE a.payment_id = OLD.id AND a.state <> 'RECONCILED' LIMIT 1;
        RAISE EXCEPTION 'PAYMENT_ARCHIVED: payment % is archived for review (%); it is kept as it stood until the Bursary settles it', OLD.reference, coalesce(v_ref, 'archived')
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_pref_archive_guard BEFORE INSERT OR UPDATE OR DELETE ON finance.payment_reference
    FOR EACH ROW EXECUTE FUNCTION finance.payment_archive_guard();

-- the graduates' historical fees summary (V654) is marked stale when a payment is archived or restored, as when it changes
DROP TRIGGER trg_historical_stale_payment_upd ON finance.payment_reference;
CREATE TRIGGER trg_historical_stale_payment_upd AFTER UPDATE OF confirmed_at, amount, purpose, session, student_id, archived_at ON finance.payment_reference
    FOR EACH ROW WHEN (new.confirmed_at IS DISTINCT FROM old.confirmed_at OR new.amount IS DISTINCT FROM old.amount OR new.purpose IS DISTINCT FROM old.purpose
                       OR new.session IS DISTINCT FROM old.session OR new.student_id IS DISTINCT FROM old.student_id OR new.archived_at IS DISTINCT FROM old.archived_at)
    EXECUTE FUNCTION finance.trg_historical_stale_payment();

-- ── 6 · evidence and duplicate signals ──────────────────────────────────────────────────────────────────────────────────
-- the kinds of evidence an investigation records: strong evidence may establish who owns a payment, or that it repeats another;
-- supporting evidence never does on its own (a name alone never moves a payment)
CREATE FUNCTION finance.payment_evidence_kinds()
RETURNS TABLE (code text, label text, strength text) LANGUAGE sql IMMUTABLE AS $$
    VALUES ('GATEWAY_PAYER', 'Payer details the gateway holds', 'STRONG'),
           ('GATEWAY_REFERENCE', 'Gateway transaction reference', 'STRONG'),
           ('PAYMENT_METADATA', 'Payment metadata', 'STRONG'),
           ('INVOICE', 'Invoice or payment reference generated for the student', 'STRONG'),
           ('PAYMENT_INTENT', 'Payment intent (the reference the student generated)', 'STRONG'),
           ('STUDENT_ID', 'Student record', 'STRONG'),
           ('JAMB_NUMBER', 'JAMB registration number', 'STRONG'),
           ('MATRIC_NUMBER', 'Matriculation number', 'STRONG'),
           ('APPLICATION_NUMBER', 'Application number', 'STRONG'),
           ('LEGACY_CROSSWALK', 'Old-portal payment crosswalk', 'STRONG'),
           ('BANK_REFERENCE', 'Bank or payment provider reference', 'STRONG'),
           ('BANK_STATEMENT', 'Bank statement entry', 'STRONG'),
           ('NAME', 'Name', 'SUPPORTING'),
           ('PHONE', 'Phone number', 'SUPPORTING'),
           ('EMAIL', 'Email address', 'SUPPORTING'),
           ('DATE', 'Date', 'SUPPORTING'),
           ('AMOUNT', 'Amount', 'SUPPORTING'),
           ('OTHER', 'Other', 'SUPPORTING')
$$;
COMMENT ON FUNCTION finance.payment_evidence_kinds() IS
  'V670: the evidence an archived payment''s investigation records, each strong (may establish ownership or a duplicate) or supporting (never on its own)';

-- what two payment records share: the authoritative identifiers (the gateway''s reference, a transaction reference, an old-portal
-- payment number) — each proof the records are one payment — and the supporting signals (the student, the amount, the purpose,
-- the session, the day), which never are on their own
CREATE FUNCTION finance.payment_duplicate_signals(p_payment uuid, p_related uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE a finance.payment_reference; b finance.payment_reference; v_auth text[] := '{}'; v_sup text[] := '{}'; v_ids_a text[]; v_ids_b text[];
BEGIN
    SELECT * INTO a FROM finance.payment_reference WHERE id = p_payment;
    SELECT * INTO b FROM finance.payment_reference WHERE id = p_related;
    IF a.id IS NULL OR b.id IS NULL OR a.id = b.id THEN
        RETURN jsonb_build_object('authoritative', '[]'::jsonb, 'supporting', '[]'::jsonb);
    END IF;
    IF EXISTS (SELECT 1 FROM finance.gateway_event ea JOIN finance.gateway_event eb ON eb.gateway_ref = ea.gateway_ref
                WHERE ea.reference = a.reference AND eb.reference = b.reference AND ea.gateway_ref IS NOT NULL AND btrim(ea.gateway_ref) <> '') THEN
        v_auth := v_auth || 'SAME_GATEWAY_REFERENCE'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.gateway_attempt ga JOIN finance.gateway_attempt gb ON gb.txn_ref = ga.txn_ref
                WHERE ga.reference = a.reference AND gb.reference = b.reference AND ga.txn_ref IS NOT NULL AND btrim(ga.txn_ref) <> '') THEN
        v_auth := v_auth || 'SAME_TRANSACTION_REFERENCE'::text;
    END IF;
    -- an old-portal payment number: carried by one record (its number, or kept as its reference or receipt by an earlier upload)
    -- and by the other
    v_ids_a := ARRAY(SELECT upper(btrim(k.payref)) FROM finance.legacy_payref k WHERE k.reference = a.reference
                     UNION SELECT upper(btrim(a.reference)) WHERE a.reference NOT LIKE 'MOAUM-%'
                     UNION SELECT upper(btrim(regexp_replace(a.receipt_no, '^(LEG|RCT)-', ''))) WHERE a.receipt_no IS NOT NULL AND a.reference NOT LIKE 'MOAUM-%');
    v_ids_b := ARRAY(SELECT upper(btrim(k.payref)) FROM finance.legacy_payref k WHERE k.reference = b.reference
                     UNION SELECT upper(btrim(b.reference)) WHERE b.reference NOT LIKE 'MOAUM-%'
                     UNION SELECT upper(btrim(regexp_replace(b.receipt_no, '^(LEG|RCT)-', ''))) WHERE b.receipt_no IS NOT NULL AND b.reference NOT LIKE 'MOAUM-%');
    IF v_ids_a && v_ids_b THEN
        v_auth := v_auth || 'SAME_OLD_PORTAL_NUMBER'::text;
    END IF;
    IF a.student_id = b.student_id THEN v_sup := v_sup || 'SAME_STUDENT'::text; END IF;
    IF abs(a.amount - b.amount) < 1 THEN v_sup := v_sup || 'SAME_AMOUNT'::text; END IF;
    IF finance.payment_category(a.purpose) = finance.payment_category(b.purpose) THEN v_sup := v_sup || 'SAME_PURPOSE'::text; END IF;
    IF a.session = b.session THEN v_sup := v_sup || 'SAME_SESSION'::text; END IF;
    IF a.confirmed_at IS NOT NULL AND b.confirmed_at IS NOT NULL
       AND (a.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (b.confirmed_at AT TIME ZONE 'Africa/Lagos')::date THEN
        v_sup := v_sup || 'SAME_DAY'::text;
    END IF;
    RETURN jsonb_build_object('authoritative', to_jsonb(v_auth), 'supporting', to_jsonb(v_sup));
END $$;
COMMENT ON FUNCTION finance.payment_duplicate_signals(uuid, uuid) IS
  'V670: what two payment records share — authoritative identifiers (gateway reference, transaction reference, old-portal payment number), each proof they are one payment, and supporting signals (student, amount, purpose, session, day), never proof on their own';

-- a student's fees in a session with the archived payments apart: assessed, verified paid, outstanding, and what is archived
CREATE FUNCTION finance.payment_archive_account(p_student uuid, p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'session', p_session,
        'stated', finance.fee_stated(p_student, p_session),
        'assessed', pos.due,
        'verifiedPaid', pos.paid,
        'outstanding', greatest(pos.due - pos.paid, 0),
        'archived', (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                      WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NOT NULL
                        AND r.purpose LIKE 'School fees%'),
        'verifiedAll', (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL),
        'archivedAll', (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NOT NULL),
        'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'))
      FROM finance.position(p_student, p_session) pos
$$;
COMMENT ON FUNCTION finance.payment_archive_account(uuid, text) IS
  'V670: a student''s school fees in a session as the finance engine reads them (assessed, verified paid, outstanding), with what is archived for review apart and never in the paid figure';

-- ── 7 · whether a payment may be archived ───────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.payment_archive_refusals(p_payment uuid)
RETURNS text[] LANGUAGE plpgsql STABLE AS $$
DECLARE r finance.payment_reference; refusals text[] := '{}'; v text;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment;
    IF NOT FOUND THEN RETURN ARRAY['PAR_NOT_FOUND: no such payment']; END IF;
    IF r.confirmed_at IS NULL THEN
        refusals := refusals || 'PAR_NOT_CONFIRMED: the payment is not confirmed (pending, failed or expired); it counts nowhere and is not archived'::text;
    END IF;
    SELECT a.archive_ref || ' (' || lower(replace(a.state, '_', ' ')) || ')' INTO v FROM finance.payment_archive a WHERE a.payment_id = r.id AND a.state <> 'RECONCILED' LIMIT 1;
    IF v IS NOT NULL OR r.archived_at IS NOT NULL THEN
        refusals := refusals || ('PAR_ALREADY: the payment is already in the payment archive as ' || coalesce(v, 'archived'));
    END IF;
    IF EXISTS (SELECT 1 FROM finance.refund x WHERE x.source_reference = r.reference AND x.state <> 'REJECTED') THEN
        refusals := refusals || 'PAR_REFUNDED: a refund stands against this payment; it is settled on Refunds & Credits first'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.paydirect_inbox x WHERE x.reference = r.reference AND x.is_reversal) THEN
        refusals := refusals || 'PAR_REVERSED: Interswitch reported this payment reversed; the reversal settles it'::text;
    END IF;
    IF r.channel = 'NELFUND wallet' OR r.purpose ~* '^(e-?)?wallet top-?up' OR EXISTS (SELECT 1 FROM finance.wallet_entry x WHERE x.reference = r.reference) THEN
        refusals := refusals || 'PAR_WALLET: the payment was made from or into the student''s wallet; the wallet keeps it'::text;
    END IF;
    IF r.purpose ILIKE 'gateway test%' OR EXISTS (SELECT 1 FROM finance.gateway_test_reference x WHERE x.reference = r.reference) THEN
        refusals := refusals || 'PAR_NOT_A_FEE: the payment is a gateway test by the Bursary, not a fee'::text;
    END IF;
    IF r.channel = 'CARRIED' THEN
        refusals := refusals || 'PAR_CARRIED: the record is an overpayment carried from an earlier session, not money received; the overpayment decision is set aside instead'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment x WHERE x.payment_id = r.id AND x.status IN ('VERIFIED', 'CREDITED')) THEN
        refusals := refusals || 'PAR_LINKED: the payment is an old-portal outstanding fees payment verified for, or credited to, the wallet; the Bursary returns it on that desk first'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM people.deferment_fee x WHERE x.reference = r.reference AND x.used_by IS NOT NULL) THEN
        refusals := refusals || 'PAR_LINKED: the payment is the fee of a deferment request already made; the request is settled first'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM people.transfer_application t WHERE t.fee_reference = r.reference
                 AND t.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED', 'EFFECTED')) THEN
        refusals := refusals || 'PAR_LINKED: the payment is the fee of an inter-departmental transfer application that stands; it is withdrawn first'::text;
    END IF;
    SELECT x.swap_ref INTO v FROM finance.payment_swap x WHERE x.payment_id = r.id AND x.status = 'PENDING_APPROVAL' LIMIT 1;
    IF v IS NOT NULL THEN
        refusals := refusals || ('PAR_OPEN: payment swap ' || v || ' of this payment waits for a decision; it is decided or cancelled first');
    END IF;
    SELECT x.realloc_ref INTO v FROM finance.payment_reallocation x WHERE x.payment_id = r.id AND x.status IN ('PENDING_APPROVAL', 'RETURNED') LIMIT 1;
    IF v IS NOT NULL THEN
        refusals := refusals || ('PAR_OPEN: payment correction ' || v || ' of this payment is open; it is decided or cancelled first');
    END IF;
    IF r.purpose LIKE 'School fees%' AND EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = r.student_id AND d.session = r.session AND d.superseded_at IS NULL) THEN
        refusals := refusals || 'PAR_OVERPAYMENT_DECISION: an overpayment decision stands on the student''s school fees for the session (carried or refunded); the Bursary sets it aside first'::text;
    END IF;
    RETURN refusals;
END $$;
COMMENT ON FUNCTION finance.payment_archive_refusals(uuid) IS
  'V670: why a payment may not be archived — not confirmed, already archived, or tied to something that stands (a refund, an Interswitch reversal, a wallet, a gateway test, a carried overpayment, a verified or credited outstanding-fees payment, a deferment request, a transfer application, an open swap or correction, an overpayment decision); empty when it may';

-- ── 8 · the ledger ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- archived: a payment the sync has posted is reclassified out of income into 2400 Payments under review (the bank keeps the money)
CREATE FUNCTION finance.payment_archive_ledger_out(p_archive uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a finance.payment_archive; v_acc text; v_journal uuid;
BEGIN
    SELECT * INTO a FROM finance.payment_archive WHERE id = p_archive;
    IF NOT EXISTS (SELECT 1 FROM finance.gl_journal g WHERE g.source_type = 'PAYMENT' AND g.source_ref = a.reference AND g.status = 'POSTED') THEN
        RETURN NULL;   -- not on the ledger yet: the sync leaves an archived payment unposted
    END IF;
    v_acc := finance.gl_income_account(finance.payment_category(a.purpose));
    v_journal := finance.gl_post((now() AT TIME ZONE 'Africa/Lagos')::date,
        'Payment archived for review ' || a.archive_ref || ' — fee receipt ' || a.reference || ' (' || a.purpose || ')', 'AUTO', 'PAYMENT_ARCHIVE', a.archive_ref,
        jsonb_build_array(
            jsonb_build_object('account', v_acc, 'debit', a.amount, 'narration', a.purpose, 'session', a.session),
            jsonb_build_object('account', '2400', 'credit', a.amount, 'narration', 'Archived for review ' || a.archive_ref, 'session', a.session)));
    UPDATE finance.payment_archive SET archive_journal = v_journal WHERE id = a.id;
    PERFORM finance.payment_archive_note(a.id, 'LEDGER_RECLASSIFIED', 'Dr ' || v_acc || ' Cr 2400 NGN ' || to_char(a.amount, 'FM999,999,999,990.00') || '; the bank unchanged');
    RETURN v_journal;
END $$;

-- restored or reallocated: back into income under the payment's purpose; confirmed a duplicate or never received: the payment's
-- posting and the reclassification both reversed (the money was never received twice)
CREATE FUNCTION finance.payment_archive_ledger_settle(p_archive uuid, p_counts boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a finance.payment_archive; r finance.payment_reference; v_acc text; v_journal uuid; gf record;
BEGIN
    SELECT * INTO a FROM finance.payment_archive WHERE id = p_archive;
    SELECT * INTO r FROM finance.payment_reference WHERE id = a.payment_id;
    IF p_counts THEN
        IF a.archive_journal IS NULL THEN RETURN; END IF;   -- never reclassified: the sync posts it once it counts again
        v_acc := finance.gl_income_account(finance.payment_category(r.purpose));
        v_journal := finance.gl_post((now() AT TIME ZONE 'Africa/Lagos')::date,
            'Payment settled ' || a.archive_ref || ' — fee receipt ' || a.reference || ' counts again (' || r.purpose || ')', 'AUTO', 'PAYMENT_ARCHIVE', a.archive_ref || '#SETTLED',
            jsonb_build_array(
                jsonb_build_object('account', '2400', 'debit', a.amount, 'narration', 'Settled ' || a.archive_ref, 'session', a.session),
                jsonb_build_object('account', v_acc, 'credit', a.amount, 'narration', r.purpose, 'session', r.session)));
        UPDATE finance.payment_archive SET settle_journal = v_journal WHERE id = a.id;
        PERFORM finance.payment_archive_note(a.id, 'LEDGER_RECLASSIFIED', 'Dr 2400 Cr ' || v_acc || ' NGN ' || to_char(a.amount, 'FM999,999,999,990.00'));
    ELSE
        SELECT * INTO gf FROM finance.gl_free_payment(a.reference, a.payment_id, 'PAYMENT_ARCHIVED',
            'the payment ' || a.reference || ' is excluded for good (' || a.archive_ref || ')');
        IF a.archive_journal IS NOT NULL AND EXISTS (SELECT 1 FROM finance.gl_journal g WHERE g.id = a.archive_journal AND g.status = 'POSTED') THEN
            v_journal := finance.gl_reverse(a.archive_journal, 'archive ' || a.archive_ref || ' settled: the payment is excluded for good');
        END IF;
        UPDATE finance.payment_archive SET payment_journal = gf.journal, payment_reversal = gf.reversal, settle_journal = v_journal WHERE id = a.id;
        IF gf.reversal IS NOT NULL OR v_journal IS NOT NULL THEN
            PERFORM finance.payment_archive_note(a.id, 'LEDGER_REVERSED', 'the payment''s posting and its reclassification reversed; the money was not received as recorded');
        END IF;
    END IF;
END $$;

-- ── 9 · archiving a payment ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.payment_archive_new_ref()
RETURNS text LANGUAGE sql AS $$
    SELECT 'PAR/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/'
           || lpad(platform.next_number('PAYMENT_ARCHIVE', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 6, '0')
$$;

CREATE FUNCTION finance.archive_payment(p_payment uuid, p_reason text, p_related uuid, p_note text, p_confirmed boolean)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.payment_reference; rel finance.payment_reference; rs finance.payment_archive_reason; v_refusals text[]; v_id uuid; v_ref text;
        v_note text := btrim(coalesce(p_note, '')); v_signals jsonb := '{}'::jsonb; v_held jsonb := '{}'::jsonb; v_before jsonb; p uuid;
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('studentaccounts', 'bursar') THEN
        RAISE EXCEPTION 'PAR_OFFICE: a payment is archived by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO rs FROM finance.payment_archive_reason WHERE code = upper(btrim(coalesce(p_reason, ''))) AND active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAR_REASON: choose why the payment is archived from the Bursary''s list' USING ERRCODE = '23514';
    END IF;
    IF length(v_note) < 20 THEN
        RAISE EXCEPTION 'PAR_NOTE: say what was found, in twenty characters or more; it is kept with the archive' USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'PAR_CONFIRM: confirm that the payment is to be taken out of the student''s paid figures and of income until it is verified' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;   -- one archiving of a payment at a time
    v_refusals := finance.payment_archive_refusals(p_payment);
    IF cardinality(v_refusals) > 0 THEN RAISE EXCEPTION '%', v_refusals[1] USING ERRCODE = '23514'; END IF;
    IF rs.needs_related AND p_related IS NULL THEN
        RAISE EXCEPTION 'PAR_RELATED: name the payment this one repeats' USING ERRCODE = '23514';
    END IF;
    IF p_related IS NOT NULL THEN
        SELECT * INTO rel FROM finance.payment_reference WHERE id = p_related;
        IF NOT FOUND OR rel.id = r.id THEN
            RAISE EXCEPTION 'PAR_RELATED: the payment this one repeats is another payment on record' USING ERRCODE = '23514';
        END IF;
        IF rel.confirmed_at IS NULL OR rel.archived_at IS NOT NULL THEN
            RAISE EXCEPTION 'PAR_RELATED: the payment kept (%) must be a confirmed payment that counts; one archived or not confirmed is not what this one repeats', rel.reference
                USING ERRCODE = '23514';
        END IF;
        v_signals := finance.payment_duplicate_signals(r.id, rel.id);
    END IF;
    v_before := finance.payment_archive_account(r.student_id, r.session);

    v_ref := finance.payment_archive_new_ref();
    PERFORM finance.payment_archive_settling(true);
    UPDATE finance.payment_reference SET archived_at = now() WHERE id = r.id;
    -- an unspent deferment fee the payment was is set aside while it is archived, and given back if it is restored
    UPDATE people.deferment_fee SET state = 'CANCELLED' WHERE reference = r.reference AND state = 'CONFIRMED' AND used_by IS NULL;
    IF FOUND THEN v_held := v_held || jsonb_build_object('defermentFee', true); END IF;
    PERFORM finance.payment_archive_settling(false);
    INSERT INTO finance.payment_archive (archive_ref, payment_id, reference, amount, purpose, session, channel, receipt_no, payment_confirmed_at, legacy, student_id,
                                         reason_code, related_payment_id, related_reference, signals, archive_note, held, archived_by, archived_office, before_state)
    VALUES (v_ref, r.id, r.reference, r.amount, r.purpose, r.session, r.channel, r.receipt_no, r.confirmed_at,
            r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%', r.student_id, rs.code, rel.id, rel.reference, v_signals, v_note, v_held, who, office, v_before)
    RETURNING id INTO v_id;
    PERFORM finance.payment_archive_note(v_id, 'ARCHIVED', rs.label || ': ' || v_note || coalesce(' · repeats ' || rel.reference, ''));
    PERFORM finance.payment_archive_ledger_out(v_id);

    -- the student told that a payment on their account is under review (nothing of anyone else); the Bursar's office told
    BEGIN
        PERFORM platform.tell_student(r.student_id, 'PAYMENT_UNDER_REVIEW', NULL,
            jsonb_build_object('REFERENCE', r.reference, 'ARCHIVE', v_ref, 'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,999,990.00'),
                               'PURPOSE', r.purpose, 'SESSION', r.session),
            'PAYMENT_UNDER_REVIEW:' || v_id);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'payment archive %: the student could not be told (%)', v_ref, SQLERRM;
    END;
    FOR p IN SELECT * FROM finance.bursar_holders() LOOP
        CONTINUE WHEN p = who;
        BEGIN
            PERFORM platform.tell_person(p, 'PAYMENT_ARCHIVED_FOR_REVIEW', NULL,
                jsonb_build_object('ARCHIVE', v_ref, 'REFERENCE', r.reference, 'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,999,990.00'), 'REASON', rs.label,
                                   'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                'payment-archive:archived:' || v_id || ':' || p::text);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'payment archive %: the Bursar could not be told (%)', v_ref, SQLERRM;
        END;
    END LOOP;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION finance.archive_payment(uuid, text, uuid, text, boolean) IS
  'V670: the Students Account Officer or the Bursar archives a confirmed payment for review — the reason from the Bursary''s list, the payment it repeats where the reason asks, a note and the confirmation; the payment marked and kept as it stood, out of every figure, its posting reclassified to 2400, an unspent deferment fee set aside, the student and the Bursar told';

-- ── 10 · the investigation ──────────────────────────────────────────────────────────────────────────────────────────────
-- evidence items as the officer gives them ([{kind, value}]), each checked against the kinds and stamped with its strength,
-- who added it and when
CREATE FUNCTION finance.payment_archive_items(p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE it jsonb; k record; v_out jsonb := '[]'::jsonb; v_value text;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) = 'null' THEN RETURN '[]'::jsonb; END IF;
    IF jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'PAR_EVIDENCE: evidence is a list of items, each a kind and what it shows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_items) > 30 THEN
        RAISE EXCEPTION 'PAR_EVIDENCE: thirty evidence items at most at a time' USING ERRCODE = '23514';
    END IF;
    FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        SELECT * INTO k FROM finance.payment_evidence_kinds() e WHERE e.code = upper(btrim(coalesce(it->>'kind', '')));
        IF NOT FOUND THEN
            RAISE EXCEPTION 'PAR_EVIDENCE_KIND: % is not a kind of evidence the Bursary records', coalesce(it->>'kind', 'no kind') USING ERRCODE = '23514';
        END IF;
        v_value := btrim(coalesce(it->>'value', ''));
        IF length(v_value) < 2 OR length(v_value) > 500 THEN
            RAISE EXCEPTION 'PAR_EVIDENCE_VALUE: say what the % shows (two to five hundred characters)', lower(k.label) USING ERRCODE = '23514';
        END IF;
        v_out := v_out || jsonb_build_object('kind', k.code, 'label', k.label, 'strength', k.strength, 'value', v_value,
                                             'addedBy', nullif(current_setting('moaum.actor_id', true), ''), 'addedAt', now());
    END LOOP;
    RETURN v_out;
END $$;

CREATE FUNCTION finance.payment_archive_record(p_id uuid, p_note text, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        a finance.payment_archive; v_items jsonb; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('studentaccounts', 'bursar') THEN
        RAISE EXCEPTION 'PAR_OFFICE: an archived payment is investigated by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO a FROM finance.payment_archive WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAR_NOT_FOUND: no such archived payment' USING ERRCODE = 'P0002'; END IF;
    IF a.state NOT IN ('ARCHIVED', 'UNDER_REVIEW', 'RETURNED') THEN
        RAISE EXCEPTION 'PAR_STATE: archive % is %; the investigation is recorded while it is open', a.archive_ref, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    v_items := finance.payment_archive_items(p_items);
    IF v_note IS NULL AND jsonb_array_length(v_items) = 0 THEN
        RAISE EXCEPTION 'PAR_EVIDENCE: record what was found — a note or an item of evidence' USING ERRCODE = '23514';
    END IF;
    IF v_note IS NOT NULL AND length(v_note) < 10 THEN
        RAISE EXCEPTION 'PAR_NOTE: say what was found, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.payment_archive SET evidence = evidence || v_items, state = CASE WHEN state = 'ARCHIVED' THEN 'UNDER_REVIEW' ELSE state END WHERE id = a.id;
    PERFORM finance.payment_archive_note(a.id, 'INVESTIGATION_RECORDED',
        concat_ws(' · ', v_note, CASE WHEN jsonb_array_length(v_items) > 0 THEN
            (SELECT string_agg(x->>'label' || ': ' || (x->>'value'), '; ') FROM jsonb_array_elements(v_items) x) END));
    RETURN jsonb_build_object('archiveRef', a.archive_ref, 'evidence', jsonb_array_length(a.evidence) + jsonb_array_length(v_items));
END $$;
COMMENT ON FUNCTION finance.payment_archive_record(uuid, text, jsonb) IS
  'V670: the investigation of an archived payment recorded — a note and evidence items (each strong or supporting), kept on the archive and its timeline';

-- ── 11 · the proposal ───────────────────────────────────────────────────────────────────────────────────────────────────
--   RESTORE       the payment is genuine and belongs to the student it stands on: it counts again;
--   REALLOCATE    it belongs to another student: moved to them through the payment swap (V527), which the Bursar's approval executes;
--   DUPLICATE     it repeats another payment: excluded for good (an authoritative signal, or strong evidence, is needed);
--   NOT_RECEIVED  the money never reached the University: excluded for good (strong evidence is needed).
CREATE FUNCTION finance.payment_archive_propose(p_id uuid, p_outcome text, p_owner uuid, p_note text, p_items jsonb, p_confirmed boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        a finance.payment_archive; r finance.payment_reference; v_outcome text := upper(btrim(coalesce(p_outcome, ''))); v_note text := btrim(coalesce(p_note, ''));
        v_items jsonb; v_all jsonb; v_strong int; v_auth int; v_swap uuid; t people.student; p uuid; v_resubmit boolean;
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('studentaccounts', 'bursar') THEN
        RAISE EXCEPTION 'PAR_OFFICE: an archived payment''s settlement is proposed by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF v_outcome NOT IN ('RESTORE', 'REALLOCATE', 'DUPLICATE', 'NOT_RECEIVED') THEN
        RAISE EXCEPTION 'PAR_OUTCOME: propose to restore the payment, reallocate it to its owner, confirm it a duplicate or confirm it never received' USING ERRCODE = '23514';
    END IF;
    IF length(v_note) < 20 THEN
        RAISE EXCEPTION 'PAR_NOTE: say what the investigation established, in twenty characters or more' USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'PAR_CONFIRM: confirm that you have verified what you propose against the evidence' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM finance.payment_archive WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAR_NOT_FOUND: no such archived payment' USING ERRCODE = 'P0002'; END IF;
    IF a.state NOT IN ('ARCHIVED', 'UNDER_REVIEW', 'RETURNED') THEN
        RAISE EXCEPTION 'PAR_STATE: archive % is %; a settlement is proposed while it is open', a.archive_ref, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    v_resubmit := a.state = 'RETURNED';
    SELECT * INTO r FROM finance.payment_reference WHERE id = a.payment_id FOR UPDATE;
    v_items := finance.payment_archive_items(p_items);
    v_all := a.evidence || v_items;
    SELECT count(*) INTO v_strong FROM jsonb_array_elements(v_all) x WHERE x->>'strength' = 'STRONG';
    v_auth := coalesce(jsonb_array_length(a.signals->'authoritative'), 0);

    IF v_outcome = 'RESTORE' THEN
        IF jsonb_array_length(v_all) = 0 THEN
            RAISE EXCEPTION 'PAR_EVIDENCE: record the evidence that the payment is genuine and the student''s before it is restored' USING ERRCODE = '23514';
        END IF;
        p_owner := NULL;
    ELSIF v_outcome = 'REALLOCATE' THEN
        IF v_strong = 0 THEN
            RAISE EXCEPTION 'PAR_EVIDENCE_STRONG: a payment is moved to another student only on strong evidence (the gateway''s payer, a transaction or bank reference, the reference the student generated, a JAMB, matriculation or application number, the old portal''s crosswalk) — never on a name alone'
                USING ERRCODE = '23514';
        END IF;
        SELECT * INTO t FROM people.student WHERE id = p_owner;
        IF NOT FOUND THEN RAISE EXCEPTION 'PAR_OWNER: choose the student the payment belongs to' USING ERRCODE = '23514'; END IF;
        IF t.id = r.student_id THEN
            RAISE EXCEPTION 'PAR_OWNER: the payment already stands on that student; propose to restore it instead' USING ERRCODE = '23514';
        END IF;
        -- the move is the payment swap's (V527): its check and request, initiated now, executed by the Bursar's approval here
        PERFORM set_config('moaum.payment_archive_payment', r.id::text, true);
        v_swap := finance.initiate_payment_swap(r.id, t.id, a.archive_ref || ': ' || v_note,
                      (SELECT string_agg(x->>'label' || ': ' || (x->>'value'), '; ') FROM jsonb_array_elements(v_all) x), true);
        PERFORM set_config('moaum.payment_archive_payment', '', true);
    ELSE
        IF v_outcome = 'DUPLICATE' AND v_auth = 0 AND v_strong = 0 THEN
            RAISE EXCEPTION 'PAR_DUPLICATE_PROOF: the same amount, student, day or purpose is no proof that a payment repeats another; an authoritative identifier the two share, or strong evidence (a bank statement, the gateway''s or the bank''s reference), is'
                USING ERRCODE = '23514';
        END IF;
        IF v_outcome = 'DUPLICATE' AND a.related_payment_id IS NULL THEN
            RAISE EXCEPTION 'PAR_RELATED: a duplicate repeats a payment kept on record; this archive names none' USING ERRCODE = '23514';
        END IF;
        IF v_outcome = 'NOT_RECEIVED' AND v_strong = 0 THEN
            RAISE EXCEPTION 'PAR_EVIDENCE_STRONG: that the money never reached the University is shown by strong evidence (a bank statement, the gateway''s or the bank''s reference)'
                USING ERRCODE = '23514';
        END IF;
        p_owner := NULL;
    END IF;

    UPDATE finance.payment_archive
       SET evidence = v_all, outcome = v_outcome, owner_student_id = p_owner, proposal_note = v_note, proposed_by = who, proposed_office = office,
           proposed_at = now(), swap_id = v_swap, state = 'PENDING_BURSAR_APPROVAL', decision = NULL, failure = NULL
     WHERE id = a.id;
    PERFORM finance.payment_archive_note(a.id, CASE WHEN v_resubmit THEN 'RESUBMITTED' ELSE 'PROPOSED' END,
        CASE v_outcome WHEN 'RESTORE' THEN 'Restore to the student it stands on'
                       WHEN 'REALLOCATE' THEN 'Reallocate to ' || coalesce(t.matric_no, t.admission_no) || ' (' || (SELECT swap_ref FROM finance.payment_swap WHERE id = v_swap) || ')'
                       WHEN 'DUPLICATE' THEN 'Confirm a duplicate of ' || coalesce(a.related_reference, 'the payment kept')
                       ELSE 'Confirm never received' END || ': ' || v_note);
    FOR p IN SELECT * FROM finance.bursar_holders() LOOP
        CONTINUE WHEN p = who;
        BEGIN
            PERFORM platform.tell_person(p, 'PAYMENT_ARCHIVE_WAITING', NULL,
                jsonb_build_object('ARCHIVE', a.archive_ref, 'REFERENCE', a.reference, 'AMOUNT', 'NGN ' || to_char(a.amount, 'FM999,999,999,990.00'),
                                   'OUTCOME', CASE v_outcome WHEN 'RESTORE' THEN 'restore it' WHEN 'REALLOCATE' THEN 'reallocate it to its owner'
                                                             WHEN 'DUPLICATE' THEN 'confirm it a duplicate' ELSE 'confirm it never received' END,
                                   'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                'payment-archive:waiting:' || a.id || ':' || p::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'payment archive %: the Bursar could not be told (%)', a.archive_ref, SQLERRM;
        END;
    END LOOP;
    RETURN jsonb_build_object('archiveRef', a.archive_ref, 'state', 'PENDING_BURSAR_APPROVAL', 'outcome', v_outcome,
                              'swapRef', (SELECT swap_ref FROM finance.payment_swap WHERE id = v_swap));
END $$;
COMMENT ON FUNCTION finance.payment_archive_propose(uuid, text, uuid, text, jsonb, boolean) IS
  'V670: the Students Account Officer or the Bursar proposes how an archived payment is settled — restore, reallocate to its true owner (a payment swap initiated, strong evidence required), duplicate (an authoritative identifier or strong evidence) or never received (strong evidence); the Bursar''s office told';

-- ── 12 · the Bursar's decision, executed at once ─────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.payment_archive_decide(p_id uuid, p_decision text, p_note text, p_confirmed boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        a finance.payment_archive; r finance.payment_reference; v_decision text := upper(btrim(coalesce(p_decision, ''))); v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_before jsonb; v_after jsonb; v_owner_before jsonb; v_owner_after jsonb; v_swap jsonb; v_state text; v_failure text; v_was timestamptz;
BEGIN
    IF who IS NULL OR coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'PAR_OFFICE: an archived payment''s settlement is decided by a Bursar officer other than the one who proposed it' USING ERRCODE = '42501';
    END IF;
    IF v_decision NOT IN ('APPROVE', 'REJECT', 'RETURN') THEN
        RAISE EXCEPTION 'PAR_DECISION: a proposal is approved, returned for correction or rejected' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM finance.payment_archive WHERE id = p_id FOR UPDATE;   -- one decision at a time
    IF NOT FOUND THEN RAISE EXCEPTION 'PAR_NOT_FOUND: no such archived payment' USING ERRCODE = 'P0002'; END IF;
    IF a.state <> 'PENDING_BURSAR_APPROVAL' THEN
        RAISE EXCEPTION 'PAR_DECIDED: archive % is %; there is no proposal waiting', a.archive_ref, lower(replace(a.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF a.proposed_by = who THEN
        RAISE EXCEPTION 'PAR_SAME_OFFICER: the officer who proposed a settlement does not decide it; another Bursar officer does' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE id = a.payment_id FOR UPDATE;

    IF v_decision IN ('REJECT', 'RETURN') THEN
        IF v_note IS NULL OR length(v_note) < 10 THEN
            RAISE EXCEPTION 'PAR_REASON: say why the proposal is %', CASE v_decision WHEN 'REJECT' THEN 'rejected' ELSE 'returned' END USING ERRCODE = '23514';
        END IF;
        -- the swap the proposal opened goes with it
        IF a.swap_id IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_swap s WHERE s.id = a.swap_id AND s.status = 'PENDING_APPROVAL') THEN
            PERFORM set_config('moaum.payment_archive_payment', a.payment_id::text, true);
            PERFORM finance.decide_payment_swap(a.swap_id, false, a.archive_ref || ' ' || lower(v_decision) || 'ed: ' || v_note, false);
            PERFORM set_config('moaum.payment_archive_payment', '', true);
        END IF;
        UPDATE finance.payment_archive
           SET state = CASE v_decision WHEN 'RETURN' THEN 'RETURNED' ELSE 'UNDER_REVIEW' END, decision = v_decision, decided_by = who, decided_office = office,
               decided_at = now(), decision_note = v_note,
               returned_by = CASE v_decision WHEN 'RETURN' THEN who ELSE returned_by END,
               returned_at = CASE v_decision WHEN 'RETURN' THEN now() ELSE returned_at END,
               returned_note = CASE v_decision WHEN 'RETURN' THEN v_note ELSE returned_note END
         WHERE id = a.id;
        PERFORM finance.payment_archive_note(a.id, CASE v_decision WHEN 'RETURN' THEN 'RETURNED' ELSE 'REJECTED' END, v_note);
        PERFORM finance.payment_archive_told(a.id, v_decision, v_note);
        RETURN jsonb_build_object('archiveRef', a.archive_ref, 'state', CASE v_decision WHEN 'RETURN' THEN 'RETURNED' ELSE 'UNDER_REVIEW' END);
    END IF;

    IF NOT coalesce(p_confirmed, false) THEN
        RAISE EXCEPTION 'PAR_CONFIRM: confirm that you have checked the evidence and approve the settlement proposed' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.payment_archive_note(a.id, 'APPROVED', v_note);
    v_was := r.archived_at;
    v_before := finance.payment_archive_account(r.student_id, r.session);

    IF a.outcome IN ('RESTORE', 'REALLOCATE') THEN
        -- the payment counts again: on the student it stands on, or — through the swap — on its true owner
        PERFORM finance.payment_archive_settling(true);
        UPDATE finance.payment_reference SET archived_at = NULL WHERE id = r.id;
        IF a.held ? 'defermentFee' THEN
            UPDATE people.deferment_fee SET state = 'CONFIRMED' WHERE reference = r.reference AND state = 'CANCELLED' AND used_by IS NULL;
        END IF;
        PERFORM finance.payment_archive_settling(false);
        IF a.outcome = 'REALLOCATE' THEN
            v_owner_before := finance.payment_archive_account(a.owner_student_id, r.session);
            PERFORM set_config('moaum.payment_archive_payment', r.id::text, true);
            v_swap := finance.decide_payment_swap(a.swap_id, true, a.archive_ref || ' approved' || coalesce(': ' || v_note, ''), true);
            PERFORM set_config('moaum.payment_archive_payment', '', true);
            IF v_swap->>'status' IS DISTINCT FROM 'COMPLETED' THEN
                -- the swap found something no longer holds: the payment archived again as it was, the proposal back for correction
                v_failure := coalesce(v_swap->>'failure', 'the payment swap did not complete');
                PERFORM finance.payment_archive_settling(true);
                UPDATE finance.payment_reference SET archived_at = v_was WHERE id = r.id;
                IF a.held ? 'defermentFee' THEN
                    UPDATE people.deferment_fee SET state = 'CANCELLED' WHERE reference = r.reference AND state = 'CONFIRMED' AND used_by IS NULL;
                END IF;
                PERFORM finance.payment_archive_settling(false);
                UPDATE finance.payment_archive SET state = 'RETURNED', decision = 'RETURN', decided_by = who, decided_office = office, decided_at = now(),
                       decision_note = v_note, returned_by = who, returned_at = now(), returned_note = v_failure, failure = v_failure
                 WHERE id = a.id;
                PERFORM finance.payment_archive_note(a.id, 'FAILED', v_failure);
                PERFORM finance.payment_archive_told(a.id, 'RETURN', v_failure);
                RETURN jsonb_build_object('archiveRef', a.archive_ref, 'state', 'RETURNED', 'failure', v_failure);
            END IF;
            v_owner_after := finance.payment_archive_account(a.owner_student_id, r.session);
        END IF;
        PERFORM finance.payment_archive_ledger_settle(a.id, true);
        v_state := 'RECONCILED';
        PERFORM finance.payment_archive_note(a.id, CASE a.outcome WHEN 'RESTORE' THEN 'RESTORED' ELSE 'REALLOCATED' END,
            CASE a.outcome WHEN 'RESTORE' THEN r.reference || ' counts again for the student it stands on'
                           ELSE r.reference || ' counts for its owner (' || (v_swap->>'swapRef') || ')' END);
    ELSE
        PERFORM finance.payment_archive_ledger_settle(a.id, false);
        v_state := CASE a.outcome WHEN 'DUPLICATE' THEN 'DUPLICATE_CONFIRMED' ELSE 'NOT_RECEIVED' END;
        PERFORM finance.payment_archive_note(a.id, CASE a.outcome WHEN 'DUPLICATE' THEN 'DUPLICATE_CONFIRMED' ELSE 'NOT_RECEIVED_CONFIRMED' END,
            r.reference || ' is excluded for good' || CASE WHEN a.outcome = 'DUPLICATE' THEN '; it repeats ' || coalesce(a.related_reference, 'the payment kept') ELSE '' END);
    END IF;
    v_after := finance.payment_archive_account(r.student_id, r.session);

    -- reconciled, or nothing: restored, the student's verified payments up by exactly the amount; excluded, unchanged; reallocated,
    -- the owner's up by exactly the amount (the swap reconciled the move itself)
    IF (a.outcome = 'RESTORE' AND (v_after->>'verifiedAll')::numeric - (v_before->>'verifiedAll')::numeric <> a.amount)
       OR (a.outcome IN ('DUPLICATE', 'NOT_RECEIVED') AND (v_after->>'verifiedAll')::numeric <> (v_before->>'verifiedAll')::numeric)
       OR (a.outcome = 'REALLOCATE' AND (v_owner_after->>'verifiedAll')::numeric - (v_owner_before->>'verifiedAll')::numeric <> a.amount)
       OR (SELECT count(*) FROM finance.payment_reference x WHERE x.reference = a.reference) <> 1 THEN
        RAISE EXCEPTION 'PAR_RECONCILIATION: the accounts did not reconcile after the settlement (verified % then %); nothing was changed',
            v_before->>'verifiedAll', v_after->>'verifiedAll' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.payment_archive
       SET state = v_state, decision = 'APPROVE', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note, settled_at = now(),
           after_state = jsonb_build_object('student', v_after, 'owner', v_owner_after),
           before_state = coalesce(before_state, '{}'::jsonb) || jsonb_build_object('atDecision', v_before, 'ownerAtDecision', v_owner_before)
     WHERE id = a.id;
    PERFORM finance.payment_archive_told(a.id, 'APPROVE', v_note);
    RETURN jsonb_build_object('archiveRef', a.archive_ref, 'state', v_state, 'outcome', a.outcome, 'swapRef', v_swap->>'swapRef',
                              'before', v_before, 'after', v_after, 'owner', v_owner_after);
END $$;
COMMENT ON FUNCTION finance.payment_archive_decide(uuid, text, text, boolean) IS
  'V670: a Bursar officer other than the proposer decides an archived payment''s settlement: returned or rejected with a reason (the swap it opened rejected), or approved and executed at once — restored or reallocated through the payment swap (the payment counts again, its income back from 2400), or excluded for good as a duplicate or never received (its posting reversed); the accounts reconciled, or nothing';

-- the people told of a decision: the officer who proposed it, and the student in plain words (a reallocation is told by the swap)
CREATE FUNCTION finance.payment_archive_told(p_id uuid, p_decision text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a finance.payment_archive; r finance.payment_reference; v_key text;
BEGIN
    SELECT * INTO a FROM finance.payment_archive WHERE id = p_id;
    SELECT * INTO r FROM finance.payment_reference WHERE id = a.payment_id;
    IF a.proposed_by IS NOT NULL THEN
        BEGIN
            PERFORM platform.tell_person(a.proposed_by, 'PAYMENT_ARCHIVE_DECIDED', NULL,
                jsonb_build_object('ARCHIVE', a.archive_ref, 'REFERENCE', a.reference,
                                   'ACTION', CASE p_decision WHEN 'APPROVE' THEN 'approved and settled' WHEN 'RETURN' THEN 'returned for correction' ELSE 'rejected' END,
                                   'REASON', coalesce(p_note, '—'), 'BURSAR', coalesce(helpdesk.person_name(nullif(current_setting('moaum.actor_id', true), '')::uuid), 'the Bursar')),
                'payment-archive:decided:' || a.id || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'payment archive %: the officer could not be told (%)', a.archive_ref, SQLERRM;
        END;
    END IF;
    IF p_decision = 'APPROVE' AND a.outcome IN ('RESTORE', 'DUPLICATE', 'NOT_RECEIVED') THEN
        v_key := CASE a.outcome WHEN 'RESTORE' THEN 'PAYMENT_REVIEW_RESTORED' WHEN 'DUPLICATE' THEN 'PAYMENT_REVIEW_DUPLICATE' ELSE 'PAYMENT_REVIEW_NOT_RECEIVED' END;
        BEGIN
            PERFORM platform.tell_student(r.student_id, v_key, NULL,
                jsonb_build_object('REFERENCE', a.reference, 'ARCHIVE', a.archive_ref, 'AMOUNT', 'NGN ' || to_char(a.amount, 'FM999,999,999,990.00'),
                                   'PURPOSE', a.purpose, 'SESSION', a.session),
                v_key || ':' || a.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'payment archive %: the student could not be told (%)', a.archive_ref, SQLERRM;
        END;
    END IF;
END $$;

-- ── 13 · the old portal's withdrawals archive the record for good instead of deleting it ────────────────────────────────
-- called by the withdrawal tools (restated below) once their own checks and approvals have held and the ledger is let go
CREATE FUNCTION finance.payment_archive_withdrawn(p_payment uuid, p_source text, p_reason text, p_related_reference text, p_note text,
                                                  p_proposed_by uuid, p_journal uuid, p_reversal uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r finance.payment_reference; v_id uuid; v_ref text; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := coalesce(nullif(current_setting('moaum.actor_office', true), ''), 'bursar'); v_rel uuid;
        v_note text := CASE p_source WHEN 'NOT_RECEIVED_WITHDRAWAL' THEN 'Withdrawn, never received: ' ELSE 'Withdrawn, recorded twice: ' END
                       || coalesce(nullif(btrim(p_note), ''), 'by the old portal''s withdrawal');
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;
    IF NOT FOUND THEN RETURN NULL; END IF;
    p_note := v_note;
    SELECT x.id INTO v_rel FROM finance.payment_reference x WHERE x.reference = p_related_reference AND x.id <> r.id;
    v_ref := finance.payment_archive_new_ref();
    PERFORM finance.payment_archive_settling(true);
    UPDATE finance.payment_reference SET archived_at = coalesce(archived_at, now()) WHERE id = r.id;
    PERFORM finance.payment_archive_settling(false);
    INSERT INTO finance.payment_archive (archive_ref, payment_id, reference, amount, purpose, session, channel, receipt_no, payment_confirmed_at, legacy, student_id,
                                         source, reason_code, related_payment_id, related_reference, signals, archive_note, archived_by, archived_office,
                                         state, outcome, proposal_note, proposed_by, proposed_office, proposed_at,
                                         decision, decided_by, decided_office, decided_at, decision_note, settled_at, payment_journal, payment_reversal)
    VALUES (v_ref, r.id, r.reference, r.amount, r.purpose, r.session, r.channel, r.receipt_no, coalesce(r.confirmed_at, r.generated_at),
            r.channel = 'Legacy' OR r.reference LIKE 'MOAUM-LEG-%', r.student_id, p_source, p_reason, v_rel, p_related_reference,
            CASE WHEN v_rel IS NOT NULL THEN finance.payment_duplicate_signals(r.id, v_rel) ELSE '{}'::jsonb END,
            p_note, coalesce(p_proposed_by, who, '00000000-0000-0000-0000-000000000000'::uuid), office,
            CASE p_source WHEN 'NOT_RECEIVED_WITHDRAWAL' THEN 'NOT_RECEIVED' ELSE 'DUPLICATE_CONFIRMED' END,
            CASE p_source WHEN 'NOT_RECEIVED_WITHDRAWAL' THEN 'NOT_RECEIVED' ELSE 'DUPLICATE' END,
            p_note, coalesce(p_proposed_by, who), office, now(),
            'APPROVE', who, office, now(), p_note, now(), p_journal, p_reversal)
    RETURNING id INTO v_id;
    PERFORM finance.payment_archive_note(v_id, CASE p_source WHEN 'NOT_RECEIVED_WITHDRAWAL' THEN 'WITHDRAWN_NOT_RECEIVED' ELSE 'WITHDRAWN_AS_DOUBLE' END,
        p_note || coalesce(' · repeats ' || p_related_reference, ''));
    RETURN v_id;
END $$;
COMMENT ON FUNCTION finance.payment_archive_withdrawn(uuid, text, text, text, text, uuid, uuid, uuid) IS
  'V670: an old-portal record withdrawn by its own tool (recorded twice, a double, never received) archived for good — kept, out of every figure — instead of deleted';

-- ── 14 · what is read ───────────────────────────────────────────────────────────────────────────────────────────────────
-- a student's archived payments, apart from the verified ones: what stands on their account (open, or excluded for good), and what
-- was settled; to the student, nothing of another student
CREATE FUNCTION finance.payment_archives_of(p_student uuid)
RETURNS TABLE (archive_id uuid, archive_ref text, reference text, amount numeric, purpose text, session text, paid_at timestamptz, channel text,
               reason_code text, reason text, state text, outcome text, archived_at timestamptz, settled_at timestamptz, counts boolean, on_account boolean)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.archive_ref, a.reference, a.amount, a.purpose, a.session, a.payment_confirmed_at, a.channel, a.reason_code, rs.label, a.state, a.outcome,
           a.archived_at, a.settled_at, r.archived_at IS NULL AS counts, r.student_id = p_student AS on_account
      FROM finance.payment_archive a
      JOIN finance.payment_reference r ON r.id = a.payment_id
      JOIN finance.payment_archive_reason rs ON rs.code = a.reason_code
     WHERE a.student_id = p_student OR r.student_id = p_student
     ORDER BY a.archived_at DESC
$$;
COMMENT ON FUNCTION finance.payment_archives_of(uuid) IS
  'V670: the archived payments of a student — those that stood on their account when archived and those that stand on it now — each with whether it counts (settled back) or not';

-- the archive in figures, for a session or all: what is archived and what it is worth, by state and reason; the student payments
-- recorded, archived and verified active (the income the reports count)
CREATE FUNCTION finance.payment_archive_figures(p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT x.* FROM finance.payment_archive x WHERE p_session IS NULL OR x.session = p_session),
         pay AS (SELECT count(*) AS n, coalesce(sum(r.amount), 0) AS amount,
                        count(*) FILTER (WHERE r.archived_at IS NOT NULL) AS n_arch, coalesce(sum(r.amount) FILTER (WHERE r.archived_at IS NOT NULL), 0) AS arch
                   FROM finance.payment_reference r WHERE r.confirmed_at IS NOT NULL AND (p_session IS NULL OR r.session = p_session))
    SELECT jsonb_build_object(
        'session', p_session,
        'recordedCount', (SELECT n FROM pay), 'recordedAmount', (SELECT amount FROM pay),
        'archivedCount', (SELECT n_arch FROM pay), 'archivedAmount', (SELECT arch FROM pay),
        'activeCount', (SELECT n - n_arch FROM pay), 'activeAmount', (SELECT amount - arch FROM pay),
        'total', (SELECT count(*) FROM a), 'totalAmount', (SELECT coalesce(sum(amount), 0) FROM a),
        'open', (SELECT count(*) FROM a WHERE state IN ('ARCHIVED', 'UNDER_REVIEW', 'PENDING_BURSAR_APPROVAL', 'RETURNED')),
        'openAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state IN ('ARCHIVED', 'UNDER_REVIEW', 'PENDING_BURSAR_APPROVAL', 'RETURNED')),
        'duplicates', (SELECT count(*) FROM a WHERE state = 'DUPLICATE_CONFIRMED' OR (reason_code LIKE 'DUPLICATE%' AND state <> 'RECONCILED')),
        'duplicateAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state = 'DUPLICATE_CONFIRMED' OR (reason_code LIKE 'DUPLICATE%' AND state <> 'RECONCILED')),
        'wrongStudent', (SELECT count(*) FROM a WHERE reason_code = 'WRONG_STUDENT'),
        'wrongStudentAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE reason_code = 'WRONG_STUDENT'),
        'ownershipPending', (SELECT count(*) FROM a WHERE state IN ('ARCHIVED', 'UNDER_REVIEW', 'RETURNED')
                                                      AND reason_code IN ('WRONG_STUDENT', 'UNKNOWN_OWNER', 'PAYMENT_OWNERSHIP_DISPUTE')),
        'ownershipPendingAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state IN ('ARCHIVED', 'UNDER_REVIEW', 'RETURNED')
                                                      AND reason_code IN ('WRONG_STUDENT', 'UNKNOWN_OWNER', 'PAYMENT_OWNERSHIP_DISPUTE')),
        'awaitingBursar', (SELECT count(*) FROM a WHERE state = 'PENDING_BURSAR_APPROVAL'),
        'awaitingBursarAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state = 'PENDING_BURSAR_APPROVAL'),
        'reconciled', (SELECT count(*) FROM a WHERE state = 'RECONCILED'),
        'reconciledAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state = 'RECONCILED'),
        'reallocated', (SELECT count(*) FROM a WHERE state = 'RECONCILED' AND outcome = 'REALLOCATE'),
        'reallocatedAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state = 'RECONCILED' AND outcome = 'REALLOCATE'),
        'notReceived', (SELECT count(*) FROM a WHERE state = 'NOT_RECEIVED'),
        'notReceivedAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state = 'NOT_RECEIVED'),
        'unresolved', (SELECT count(*) FROM a WHERE state IN ('ARCHIVED', 'UNDER_REVIEW', 'RETURNED')),
        'unresolvedAmount', (SELECT coalesce(sum(amount), 0) FROM a WHERE state IN ('ARCHIVED', 'UNDER_REVIEW', 'RETURNED')),
        'byState', (SELECT coalesce(jsonb_object_agg(state, jsonb_build_object('n', n, 'amount', amt)), '{}'::jsonb)
                      FROM (SELECT state, count(*) AS n, sum(amount) AS amt FROM a GROUP BY state) s),
        'byReason', (SELECT coalesce(jsonb_object_agg(reason_code, jsonb_build_object('n', n, 'amount', amt)), '{}'::jsonb)
                       FROM (SELECT reason_code, count(*) AS n, sum(amount) AS amt FROM a GROUP BY reason_code) s))
$$;
COMMENT ON FUNCTION finance.payment_archive_figures(text) IS
  'V670: the payment archive in figures for a session (or all) — open, duplicate, wrong student, ownership pending, awaiting the Bursar, reconciled, reallocated, never received, unresolved, each with its value — and the student payments recorded, archived and verified active';

-- payments that may be one payment recorded twice: those that share an authoritative identifier (the gateway's reference, a
-- transaction reference, an old-portal payment number) — and, apart, those that share only the supporting signals (student,
-- session, purpose, amount, day), which an officer checks before archiving anything
CREATE FUNCTION finance.payment_duplicate_suspects(p_session text, p_limit int DEFAULT 200)
RETURNS TABLE (payment_id uuid, reference text, related_id uuid, related_reference text, student_id uuid, session text, amount numeric, purpose text,
               paid_on date, basis text, authoritative boolean)
LANGUAGE sql STABLE AS $$
    WITH live AS (SELECT r.* FROM finance.payment_reference r
                   WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND (p_session IS NULL OR r.session = p_session)),
    gw AS (SELECT DISTINCT ON (b.id) b.id AS pid, a.id AS rid, 'SAME_GATEWAY_REFERENCE'::text AS basis
             FROM finance.gateway_event ea JOIN finance.gateway_event eb ON eb.gateway_ref = ea.gateway_ref AND eb.reference > ea.reference
             JOIN live a ON a.reference = ea.reference JOIN live b ON b.reference = eb.reference
            WHERE ea.gateway_ref IS NOT NULL AND btrim(ea.gateway_ref) <> ''
            ORDER BY b.id, a.confirmed_at),
    tx AS (SELECT DISTINCT ON (b.id) b.id AS pid, a.id AS rid, 'SAME_TRANSACTION_REFERENCE'::text AS basis
             FROM finance.gateway_attempt ga JOIN finance.gateway_attempt gb ON gb.txn_ref = ga.txn_ref AND gb.reference > ga.reference
             JOIN live a ON a.reference = ga.reference JOIN live b ON b.reference = gb.reference
            WHERE ga.txn_ref IS NOT NULL AND btrim(ga.txn_ref) <> ''
            ORDER BY b.id, a.confirmed_at),
    -- an old-portal number kept as one record's reference (an earlier upload) and as another's payment number
    num AS (SELECT DISTINCT ON (b.id) b.id AS pid, a.id AS rid, 'SAME_OLD_PORTAL_NUMBER'::text AS basis
              FROM finance.legacy_payref k JOIN live a ON a.reference = k.reference
              JOIN live b ON (upper(btrim(b.reference)) = upper(btrim(k.payref)) OR upper(btrim(b.receipt_no)) = upper(btrim(k.payref))) AND b.id <> a.id
             ORDER BY b.id, a.confirmed_at),
    auth AS (SELECT * FROM gw UNION ALL SELECT * FROM tx UNION ALL SELECT * FROM num),
    sup AS (SELECT x.id AS pid, first_value(x.id) OVER w AS rid, 'SAME_STUDENT_AMOUNT_PURPOSE_DAY'::text AS basis, row_number() OVER w AS k
              FROM live x
            WINDOW w AS (PARTITION BY x.student_id, x.session, finance.payment_category(x.purpose), round(x.amount), (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
                         ORDER BY x.confirmed_at, x.reference)),
    pairs AS (SELECT pid, rid, basis, true AS authoritative FROM auth
              UNION ALL
              SELECT s.pid, s.rid, s.basis, false FROM sup s WHERE s.k > 1 AND NOT EXISTS (SELECT 1 FROM auth WHERE auth.pid = s.pid))
    SELECT b.id, b.reference, a.id, a.reference, b.student_id, b.session, b.amount, b.purpose, (b.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, p.basis, p.authoritative
      FROM pairs p JOIN finance.payment_reference b ON b.id = p.pid JOIN finance.payment_reference a ON a.id = p.rid
     ORDER BY p.authoritative DESC, b.confirmed_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 200), 2000))
$$;
COMMENT ON FUNCTION finance.payment_duplicate_suspects(text, int) IS
  'V670: payment records that may be one payment recorded twice — by an authoritative identifier they share (gateway reference, transaction reference, old-portal number), or (marked not authoritative) by the student, session, purpose, amount and day alone, for an officer to check';

-- ── 15 · the notices ────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYMENT_UNDER_REVIEW', 'A payment on your account is under review',
 'To a student when the Bursary archives a payment on their account for review: it is kept, and not counted in their verified payments until it is verified',
 'A payment on your account is under review',
 E'Dear [FIRST_NAME],\n\nThe payment [REFERENCE] ([AMOUNT], [PURPOSE], [SESSION]) on your portal account is under review by the Bursary ([ARCHIVE]). Until the review is finished it is not counted in your verified payments, so your fees page may show a balance. Nothing has been deleted, and you have not been charged. If you made this payment, keep your bank or gateway receipt; the Bursary may ask for it.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: payment [REFERENCE] ([AMOUNT]) on your account is under review by the Bursary ([ARCHIVE]) and is not counted until verified.',
 'A payment is under review',
 'The payment [REFERENCE] ([AMOUNT], [PURPOSE]) is under review by the Bursary ([ARCHIVE]) and is not counted in your verified payments until it is verified.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','PURPOSE','SESSION','ARCHIVE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PAYMENT_REVIEW_RESTORED', 'A payment under review is verified',
 'To a student when the Bursary verifies a payment it had archived for review and restores it to their account',
 'Your payment has been verified',
 E'Dear [FIRST_NAME],\n\nThe Bursary has verified the payment [REFERENCE] ([AMOUNT], [PURPOSE], [SESSION]) that was under review ([ARCHIVE]). It counts in your verified payments again. Your fees page shows where you stand: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: payment [REFERENCE] ([AMOUNT]) has been verified by the Bursary and counts again ([ARCHIVE]).',
 'Your payment was verified',
 'The payment [REFERENCE] ([AMOUNT], [PURPOSE]) that was under review ([ARCHIVE]) is verified and counts in your verified payments again.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','PURPOSE','SESSION','ARCHIVE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PAYMENT_REVIEW_DUPLICATE', 'A payment record found to be a duplicate',
 'To a student when the Bursary confirms that a payment record on their account repeats another payment record: it is kept but never counted',
 'A duplicate payment record on your account',
 E'Dear [FIRST_NAME],\n\nThe Bursary has found that the payment record [REFERENCE] ([AMOUNT], [PURPOSE], [SESSION]) repeats another record of the same payment ([ARCHIVE]). The same money is not counted twice: the record is kept but no longer counted. Your verified payments are unchanged by this. If you believe you paid twice, contact the Bursary with your bank or gateway receipts.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: payment record [REFERENCE] ([AMOUNT]) repeats another record of the same payment and is not counted twice ([ARCHIVE]).',
 'A duplicate payment record',
 'The payment record [REFERENCE] ([AMOUNT]) repeats another record of the same payment ([ARCHIVE]); it is kept but not counted twice.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','PURPOSE','SESSION','ARCHIVE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PAYMENT_REVIEW_NOT_RECEIVED', 'A payment record the bank never received',
 'To a student when the Bursary confirms that a payment record on their account was never received by the University''s bank',
 'A payment record on your account was not received',
 E'Dear [FIRST_NAME],\n\nThe Bursary has found that the money for the payment record [REFERENCE] ([AMOUNT], [PURPOSE], [SESSION]) never reached the University''s account ([ARCHIVE]). The record is kept but not counted in your payments. If you hold a bank or gateway receipt for it, bring it to the Bursary.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: the money for payment record [REFERENCE] ([AMOUNT]) was not received by the University ([ARCHIVE]); it is not counted. Contact the Bursary with your receipt.',
 'A payment record was not received',
 'The money for the payment record [REFERENCE] ([AMOUNT]) never reached the University''s account ([ARCHIVE]); it is kept but not counted.',
 ARRAY['FIRST_NAME','REFERENCE','AMOUNT','PURPOSE','SESSION','ARCHIVE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('PAYMENT_ARCHIVED_FOR_REVIEW', 'A payment archived for review',
 'To the Bursar''s office holders when an officer archives a payment for review',
 'Payment [REFERENCE] archived for review ([ARCHIVE])',
 E'[OFFICER] has archived the payment [REFERENCE] ([AMOUNT]) for review as [REASON] ([ARCHIVE]). It counts nowhere until it is settled on Archived payments.',
 '[UNIVERSITY_SHORT]: [OFFICER] archived payment [REFERENCE] ([AMOUNT]) for review: [REASON] ([ARCHIVE]).',
 'A payment was archived for review',
 '[OFFICER] archived [REFERENCE] ([AMOUNT]) as [REASON] ([ARCHIVE]).',
 ARRAY['ARCHIVE','REFERENCE','AMOUNT','REASON','OFFICER','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('PAYMENT_ARCHIVE_WAITING', 'An archived payment''s settlement waits for the Bursar',
 'To the Bursar''s office holders when an officer proposes how an archived payment is settled',
 'Archived payment [ARCHIVE] waits for your decision',
 E'[OFFICER] proposes to [OUTCOME] for the archived payment [REFERENCE] ([AMOUNT], [ARCHIVE]). A Bursar officer other than the proposer approves, returns or rejects it on Archived payments.',
 '[UNIVERSITY_SHORT]: [OFFICER] proposes to [OUTCOME] for archived payment [REFERENCE] ([AMOUNT], [ARCHIVE]); it waits for your decision.',
 'An archived payment waits for your decision',
 '[OFFICER] proposes to [OUTCOME] for [REFERENCE] ([AMOUNT], [ARCHIVE]).',
 ARRAY['ARCHIVE','REFERENCE','AMOUNT','OUTCOME','OFFICER','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('PAYMENT_ARCHIVE_DECIDED', 'An archived payment''s settlement decided',
 'To the officer who proposed how an archived payment is settled when the Bursar approves, returns or rejects it',
 'Archived payment [ARCHIVE] [ACTION]',
 E'Your proposal for the archived payment [REFERENCE] ([ARCHIVE]) was [ACTION] by [BURSAR].\n\nNote: [REASON]',
 '[UNIVERSITY_SHORT]: your proposal for archived payment [REFERENCE] ([ARCHIVE]) was [ACTION] by the Bursar.',
 'Archived payment [ACTION]',
 'Your proposal for [REFERENCE] ([ARCHIVE]) was [ACTION] by [BURSAR]: [REASON]',
 ARRAY['ARCHIVE','REFERENCE','ACTION','REASON','BURSAR','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL');

-- ── 16 · every reader of confirmed payments reads those that count: confirmed and not archived ─────────────────────────────
-- each restated from its definition as it stood, with only what V670 changes

-- admissions.admission_stage: an applicant's school fees paid only by a payment that counts
CREATE OR REPLACE FUNCTION admissions.admission_stage(p_app uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE
             WHEN a.decision_released_at IS NULL THEN 'AWAITING_DECISION'
             WHEN coalesce(a.decision, '') <> 'OFFERED' THEN 'NOT_OFFERED'
             WHEN a.declined_at IS NOT NULL THEN 'DECLINED'
             WHEN st.matric_no IS NOT NULL THEN 'MATRICULATED'
             WHEN st.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = st.id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN 'COURSES_REGISTERED'
             WHEN st.id IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = st.id AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%') THEN 'SCHOOL_FEES_PAID'
             WHEN st.id IS NOT NULL THEN 'ON_REGISTER'
             WHEN EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'SUCCESSFUL') THEN 'SCREENED'
             WHEN a.accepted_at IS NOT NULL THEN 'ACCEPTED'
             ELSE 'OFFERED'
           END
      FROM admissions.application a
      LEFT JOIN LATERAL (SELECT s.id, s.matric_no FROM people.student s WHERE s.candidate_id = a.candidate_id ORDER BY s.matric_no NULLS LAST LIMIT 1) st ON true
     WHERE a.id = p_app;
$function$;

-- admissions.pg_stage_counts: a postgraduate's school fees paid only by a payment that counts
CREATE OR REPLACE FUNCTION admissions.pg_stage_counts(p_session text, p_faculty text DEFAULT NULL::text, p_dept text DEFAULT NULL::text)
 RETURNS TABLE(qualification text, stage_code text, stage_label text, sequence integer, is_extension boolean, students bigint, male bigint, female bigint, fresh bigint, returning_ bigint, official bigint, registered bigint, paid bigint)
 LANGUAGE sql
 STABLE
AS $function$
    WITH x AS MATERIALIZED (
        SELECT g.*, s.sex,
               EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = g.student_id AND cr.session = p_session) AS registered,
               EXISTS (SELECT 1 FROM finance.payment_reference pr WHERE pr.student_id = g.student_id AND pr.session = p_session
                         AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.purpose LIKE 'School fees%') AS paid
          FROM admissions.pg_stages_of(p_session, NULL) g
          JOIN people.student s ON s.id = g.student_id
          JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_dept IS NULL OR p.dept_code = p_dept))
    SELECT st.qualification, st.code, st.label, st.sequence, st.extension_number IS NOT NULL,
           count(x.student_id), count(x.student_id) FILTER (WHERE upper(left(x.sex, 1)) = 'M'), count(x.student_id) FILTER (WHERE upper(left(x.sex, 1)) = 'F'),
           count(x.student_id) FILTER (WHERE x.category = 'FRESH'), count(x.student_id) FILTER (WHERE x.category = 'RETURNING'),
           count(x.student_id) FILTER (WHERE x.official), count(x.student_id) FILTER (WHERE x.registered), count(x.student_id) FILTER (WHERE x.paid)
      FROM admissions.pg_stage st
      LEFT JOIN x ON x.stage_code = st.code AND x.cycle_status IN ('ACTIVE', 'NOT_RECORDED')
     WHERE st.active
     GROUP BY st.qualification, st.code, st.label, st.sequence, st.extension_number
    UNION ALL
    -- the students past the maximum, and the cycles closed as exhausted awaiting a restart, under their qualification
    SELECT x.qualification, NULL, CASE x.recommendation WHEN 'MAXIMUM_PERIOD_REACHED' THEN 'Past the maximum period' ELSE 'Restart required' END, 99, false,
           count(*), count(*) FILTER (WHERE upper(left(x.sex, 1)) = 'M'), count(*) FILTER (WHERE upper(left(x.sex, 1)) = 'F'),
           0, count(*), count(*) FILTER (WHERE x.official), count(*) FILTER (WHERE x.registered), count(*) FILTER (WHERE x.paid)
      FROM x WHERE x.recommendation IN ('MAXIMUM_PERIOD_REACHED', 'RESTART_REQUIRED')
     GROUP BY x.qualification, x.recommendation
$function$;

-- assessment.cbt_candidates: a GST/EPS candidate's fee paid only by a payment that counts
CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
 RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, student_status text, entitled boolean, eligible boolean, attempts integer, attempt_id uuid, attempt_status text, connection text, started_at timestamp with time zone, ends_at timestamp with time zone, submitted_at timestamp with time zone, time_left integer, last_activity_at timestamp with time zone, violations integer, answered integer, score numeric, max_marks integer, percentage numeric, grade text, passed boolean, outcome text, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH e AS (SELECT x.*, c.general_office, c.kind FROM assessment.cbt_exam x LEFT JOIN catalogue.course c ON c.code = x.course_code WHERE x.id = p_exam),
    cfg AS (SELECT * FROM finance.gst_setting WHERE id = 1),
    reg AS (SELECT DISTINCT cr.student_id FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE e.office NOT IN ('JUPEB', 'POST_UTME') AND en.offering_id IN (SELECT catalogue.offering_family(e.offering_id)) AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    base AS (SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex, s.status, s.current_level AS level, s.entry_mode,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty
               FROM reg JOIN people.student s ON s.id = reg.student_id
               JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code),
    pays AS (SELECT r.student_id, count(*) AS n FROM e, finance.payment_reference r
              WHERE e.office IN ('GST', 'EPS') AND r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.student_id IN (SELECT id FROM base)
                AND r.amount > finance.gst_refunded(r.reference)   -- V367
              GROUP BY r.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM e, finance.gst_fee f WHERE e.office IN ('GST', 'EPS') AND f.session = e.session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
    cnt AS (SELECT a.candidate_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam GROUP BY a.candidate_id),
    ent AS (SELECT b.id,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS entitled,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN NOT (fr.id IS NOT NULL AND fr.amount > 0 AND NOT (coalesce(py.n, 0) > 0)
                                  AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND e.general_office IS NOT NULL AND (e.general_office = 'GST' OR cfg.covers_eps))   -- V367
                                       OR (cfg.required_for_all AND finance.gst_required(b.id, e.session))))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS paid_up
              FROM e CROSS JOIN cfg CROSS JOIN base b
              LEFT JOIN pays py ON py.student_id = b.id
              LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                  WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                    AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                  ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                  LIMIT 1) fr ON true),
    -- V365: a JUPEB examination's candidates â€” the JUPEB students registered for the subject in the session
    jreg AS (SELECT a.id, coalesce(a.exam_no, a.application_no) AS number, upper(a.surname) AS surname,
                    a.first_name || coalesce(' ' || a.middle_name, '') AS other_names, a.sex, a.state, cb.code AS combination, cb.name AS combination_name,
                    assessment.cbt_jupeb_fees_paid(a.id, e.semester) AS paid_up
               FROM e JOIN jupeb.subject_registration r ON r.subject_id = e.jupeb_subject_id AND r.session = e.session
               JOIN jupeb.application a ON a.id = r.application_id
               LEFT JOIN jupeb.combination cb ON cb.id = a.combination_id
              WHERE e.office = 'JUPEB'),
    -- V385: a Post-UTME examination's candidates â€” the session's submitted applicants, eligible on the record (V260) and not yet scored
    preg AS (SELECT a.id, c.jamb_reg_no AS number, upper(c.surname) AS surname, c.other_names, x.sex, el.status,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty,
                    a.fee_confirmed_at IS NOT NULL AS paid,
                    el.status IN ('READY_FOR_SCHEDULING', 'SCHEDULED', 'RESCHEDULED', 'RESCHEDULE_REQUIRED', 'ABSENT') AND a.screening_score IS NULL AS ok
               FROM e JOIN admissions.application a ON a.session = e.putme_session AND a.submitted_at IS NOT NULL
               JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode <> 'CCE'
               LEFT JOIN admissions.caps_row x ON x.id = c.admitted_from
               LEFT JOIN ref.programme p ON p.code = admissions.putme_programme_code(c.programme)
               LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
               CROSS JOIN LATERAL admissions.putme_eligibility(a.id) el
              WHERE e.office = 'POST_UTME'),
    everyone AS (
        SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
               en.entitled, en.paid_up AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION') AS eligible
          FROM base b JOIN ent en ON en.id = b.id
        UNION ALL
        SELECT j.id, j.number, j.surname, j.other_names, j.sex, 'JUPEB', 'JUPEB programme', NULL, NULL, j.combination, j.combination_name, NULL::int, j.state,
               j.paid_up, j.paid_up AND j.state = 'STUDENT'
          FROM jreg j
        UNION ALL
        SELECT q.id, q.number, q.surname, q.other_names, q.sex, q.faculty_code, q.faculty, q.dept_code, q.department, q.programme_code, q.programme, NULL::int, q.status,
               q.paid, q.ok
          FROM preg q)
    SELECT v.id, v.number, v.surname, v.other_names, v.sex, v.faculty_code, v.faculty, v.dept_code, v.department, v.programme_code, v.programme, v.level, v.status,
           v.entitled, v.eligible,
           coalesce(cn.attempts, 0), a.id,
           coalesce(a.status, 'NOT_STARTED'),
           CASE WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED' WHEN a.status = 'IN_PROGRESS' THEN 'ONLINE' ELSE NULL END,
           a.started_at, a.ends_at, a.submitted_at,
           CASE WHEN a.status = 'IN_PROGRESS' THEN greatest(0, extract(epoch FROM a.ends_at - now()))::int ELSE NULL END,
           a.last_activity_at, coalesce(a.violations, 0), coalesce(a.answered, 0), a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at
      FROM everyone v
      LEFT JOIN att a ON a.candidate_id = v.id
      LEFT JOIN cnt cn ON cn.candidate_id = v.id
$function$;

-- credentials.office_dashboard: transcript fees collected: payments that count
CREATE OR REPLACE FUNCTION credentials.office_dashboard()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS (SELECT * FROM credentials.request_rows(NULL)), i AS (SELECT * FROM credentials.document_rows())
    SELECT jsonb_build_object(
        'requests', jsonb_build_object(
            'new', (SELECT count(*) FROM r WHERE stage IN ('READY','HELD_AT_CLEARANCE') AND started_at IS NULL),
            'payment_pending', (SELECT count(*) FROM r WHERE stage = 'AWAITING_PAYMENT'),
            'paid', (SELECT count(*) FROM r WHERE paid_at IS NOT NULL AND stage NOT IN ('COMPLETED','REJECTED','CANCELLED')),
            'held', (SELECT count(*) FROM r WHERE stage = 'HELD_AT_CLEARANCE'),
            'processing', (SELECT count(*) FROM r WHERE stage IN ('PROCESSING','CORRECTION')),
            'generated', (SELECT count(*) FROM r WHERE stage = 'GENERATED'),
            'quality_check', (SELECT count(*) FROM r WHERE stage = 'GENERATED'),
            'approved', (SELECT count(*) FROM r WHERE stage = 'VERIFIED'),
            'ready_for_delivery', (SELECT count(*) FROM r WHERE stage = 'RELEASED'),
            'delivered', (SELECT count(*) FROM r WHERE stage = 'DELIVERED'),
            'completed', (SELECT count(*) FROM r WHERE stage = 'COMPLETED'),
            'rejected', (SELECT count(*) FROM r WHERE stage = 'REJECTED'),
            'cancelled', (SELECT count(*) FROM r WHERE stage = 'CANCELLED'),
            'breaching', (SELECT count(*) FROM r WHERE breaching),
            'total', (SELECT count(*) FROM r)),
        'documents', jsonb_build_object(
            'certificates', (SELECT count(*) FROM i WHERE kind = 'DEGREE_CERTIFICATE' AND status = 'ACTIVE'),
            'transcripts', (SELECT count(*) FROM i WHERE kind = 'TRANSCRIPT' AND status = 'ACTIVE'),
            'sessional', (SELECT count(*) FROM i WHERE kind = 'SESSIONAL_TRANSCRIPT' AND status = 'ACTIVE'),
            'mini', (SELECT count(*) FROM i WHERE kind = 'MINI_TRANSCRIPT' AND status = 'ACTIVE'),
            'statements', (SELECT count(*) FROM i WHERE kind = 'ACADEMIC_STATEMENT' AND status = 'ACTIVE'),
            'revoked', (SELECT count(*) FROM i WHERE status = 'REVOKED'),
            'reissued', (SELECT count(*) FROM i WHERE version > 1),
            'flagged', (SELECT count(*) FROM i WHERE flagged_at IS NOT NULL AND status = 'ACTIVE'),
            'certificates_pending', (SELECT count(*) FROM records.graduand g JOIN people.student s ON s.id = g.student_id WHERE g.senate_state = 'APPROVED' AND s.status = 'GRADUATED'
                                       AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.student_id = g.student_id AND x.kind = 'DEGREE_CERTIFICATE' AND credentials.document_status(x.id) = 'ACTIVE'))),
        'verification', jsonb_build_object(
            'last30', (SELECT count(*) FROM credentials.verification WHERE at > now() - interval '30 days'),
            'valid30', (SELECT count(*) FROM credentials.verification WHERE at > now() - interval '30 days' AND status = 'VALID'),
            'notFound30', (SELECT count(*) FROM credentials.verification WHERE at > now() - interval '30 days' AND status = 'NOT_FOUND'),
            'downloads30', (SELECT count(*) FROM credentials.download_log WHERE at > now() - interval '30 days'),
            'suspected', (SELECT count(*) FROM credentials.suspected_forgeries())),
        'revenue', jsonb_build_object(
            'collected', (SELECT coalesce(sum(pf.amount), 0) FROM finance.payment_reference pf WHERE pf.purpose LIKE 'Transcript TRN-%' AND pf.confirmed_at IS NOT NULL AND pf.archived_at IS NULL),
            'collected30', (SELECT coalesce(sum(pf.amount), 0) FROM finance.payment_reference pf WHERE pf.purpose LIKE 'Transcript TRN-%' AND pf.confirmed_at > now() - interval '30 days' AND pf.archived_at IS NULL),
            'outstanding', (SELECT coalesce(sum(t.fee), 0) FROM credentials.transcript_request t WHERE t.stage = 'AWAITING_PAYMENT'),
            'byKind', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', k, 'label', l, 'amount', a, 'n', n) ORDER BY l), '[]')
                         FROM (SELECT t.kind AS k, p.label AS l, sum(pf.amount) AS a, count(*) AS n FROM finance.payment_reference pf JOIN credentials.transcript_request t ON t.reference = pf.reference JOIN credentials.document_policy p ON p.kind = t.kind
                                WHERE pf.confirmed_at IS NOT NULL AND pf.archived_at IS NULL GROUP BY t.kind, p.label) q),
            'byMonth', (SELECT coalesce(jsonb_agg(jsonb_build_object('month', m, 'amount', a, 'n', n) ORDER BY m), '[]')
                          FROM (SELECT to_char(pf.confirmed_at, 'YYYY-MM') AS m, sum(pf.amount) AS a, count(*) AS n FROM finance.payment_reference pf WHERE pf.purpose LIKE 'Transcript TRN-%' AND pf.confirmed_at > now() - interval '12 months' AND pf.archived_at IS NULL GROUP BY 1) q)),
        'processing', jsonb_build_object(
            'avgDays', (SELECT round(avg(extract(epoch FROM (released_at - paid_at)) / 86400)::numeric, 1) FROM r WHERE released_at IS NOT NULL AND paid_at IS NOT NULL),
            'byKind', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'label', kind_label, 'n', n, 'open', o) ORDER BY kind_label), '[]')
                         FROM (SELECT kind, kind_label, count(*) AS n, count(*) FILTER (WHERE stage NOT IN ('COMPLETED','REJECTED','CANCELLED','DELIVERED')) AS o FROM r GROUP BY kind, kind_label) q),
            'byStage', (SELECT coalesce(jsonb_agg(jsonb_build_object('stage', stage, 'n', n) ORDER BY stage), '[]') FROM (SELECT stage, count(*) AS n FROM r GROUP BY stage) q),
            'deliveries', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'state', state, 'n', n) ORDER BY kind, state), '[]') FROM (SELECT kind, state, count(*) AS n FROM credentials.delivery GROUP BY kind, state) q))
    );
$function$;

-- finance.cancel_payment_swap: a swap settling an archived payment goes with the archive's decision
CREATE OR REPLACE FUNCTION finance.cancel_payment_swap(p_swap uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s finance.payment_swap;
BEGIN
    SELECT * INTO s FROM finance.payment_swap WHERE id = p_swap FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SWAP_NOT_FOUND: no such swap' USING ERRCODE = 'P0002'; END IF;
    IF s.status <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'SWAP_DECIDED: this swap is %; it is not cancelled', lower(s.status) USING ERRCODE = '23514'; END IF;
    -- V670: a swap that settles an archived payment is decided with the archive, on the Archived payments desk
    IF EXISTS (SELECT 1 FROM finance.payment_archive a WHERE a.swap_id = s.id AND a.state = 'PENDING_BURSAR_APPROVAL')
       AND current_setting('moaum.payment_archive_payment', true) IS DISTINCT FROM s.payment_id::text THEN
        RAISE EXCEPTION 'SWAP_ARCHIVE_LINKED: swap % settles archived payment % (%); it is cancelled by a decision on the Archived payments desk', s.swap_ref, s.reference,
            (SELECT a.archive_ref FROM finance.payment_archive a WHERE a.swap_id = s.id LIMIT 1) USING ERRCODE = '23514';
    END IF;
    IF who IS DISTINCT FROM s.initiated_by AND coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'SWAP_OFFICE: a swap is cancelled by the officer who initiated it, or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'SWAP_REASON: say why the swap is cancelled' USING ERRCODE = '23514'; END IF;
    UPDATE finance.payment_swap SET status = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason) WHERE id = s.id;
    PERFORM finance.payment_swap_note(s.id, 'PAYMENT_SWAP_CANCELLED', NULL, btrim(p_reason));
END $function$;

-- finance.collection_by_faculty: school fees collected by faculty: payments that count
CREATE OR REPLACE FUNCTION finance.collection_by_faculty(p_session text)
 RETURNS TABLE(faculty_code text, faculty_name text, students bigint, paid_students bigint, collected numeric, due numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH enrolled AS MATERIALIZED (
        SELECT s.id, p.faculty_code FROM people.enrolment e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
         WHERE e.session = p_session),
    paid AS MATERIALIZED (
        SELECT r.student_id, sum(r.amount) AS amount FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%' GROUP BY r.student_id),
    -- V537: each read once and held, not planned into one another (the session's charges are read for every student)
    charged AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c)
    SELECT f.code, f.name, count(en.id), count(pd.student_id), coalesce(sum(pd.amount), 0), coalesce(sum(coalesce(ch.total, 0)), 0)
      FROM ref.faculty f LEFT JOIN enrolled en ON en.faculty_code = f.code LEFT JOIN paid pd ON pd.student_id = en.id
      LEFT JOIN charged ch ON ch.student_id = en.id
     GROUP BY f.code, f.name HAVING count(en.id) > 0 ORDER BY f.name
$function$;

-- finance.day_book: the day book: payments that count
CREATE OR REPLACE FUNCTION finance.day_book(p_from date, p_to date)
 RETURNS TABLE(reference text, confirmed_at timestamp with time zone, payer text, number text, purpose text, amount numeric, channel text, receipt_no text, note text, session text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.reference, r.confirmed_at, s.surname || ', ' || s.other_names, coalesce(s.matric_no, s.admission_no), r.purpose, r.amount, r.channel, r.receipt_no, r.note, r.session
      FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id
     WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT f.reference, f.confirmed_at, c.surname || ', ' || c.other_names, a.application_no,
           CASE f.kind WHEN 'APPLICATION' THEN 'Application fee' ELSE 'Acceptance fee' END, f.amount, f.channel, NULL, f.note, a.session
      FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE f.confirmed_at IS NOT NULL AND f.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT j.reference, j.confirmed_at, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), a.application_no,
           CASE j.kind WHEN 'APPLICATION' THEN 'JUPEB application fee' WHEN 'STATUS_CHECKING' THEN 'JUPEB admission status checking fee'
                       WHEN 'ACCEPTANCE' THEN 'JUPEB acceptance fee' WHEN 'SCHOOL_FIRST' THEN 'JUPEB school fee (first semester)'
                       WHEN 'SCHOOL_SECOND' THEN 'JUPEB school fee (second semester)' WHEN 'SCHOOL_FULL' THEN 'JUPEB school fee (full)'
                       ELSE 'JUPEB ' || lower(replace(j.kind, '_', ' ')) END,
           j.amount, j.channel, NULL, NULL, j.session
      FROM jupeb.fee_reference j JOIN jupeb.application a ON a.id = j.application_id
     WHERE j.confirmed_at IS NOT NULL AND j.confirmed_at::date BETWEEN p_from AND p_to
    ORDER BY 2 DESC
$function$;

-- finance.decide_gst_payment: an archived GST payment is not decided here
CREATE OR REPLACE FUNCTION finance.decide_gst_payment(p_reference text, p_decision text, p_note text, p_payer text DEFAULT NULL::text, p_bank text DEFAULT NULL::text, p_account_name text DEFAULT NULL::text, p_account_last4 text DEFAULT NULL::text)
 RETURNS finance.gst_payment_review
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        v_dec text := upper(btrim(coalesce(p_decision, '')));
        v_note text := nullif(btrim(coalesce(p_note, '')), '');
        r finance.payment_reference; e record; v_net numeric; v_payer text; v_rf text; v_refund uuid; d finance.gst_payment_review;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a GST payment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF v_dec NOT IN ('KEEP', 'REFUND') THEN
        RAISE EXCEPTION 'GST_REVIEW_DECISION: a payment no course requires is kept or refunded' USING ERRCODE = '23514';
    END IF;
    IF v_note IS NULL THEN RAISE EXCEPTION 'GST_REVIEW_NOTE: the decision carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(coalesce(p_reference, ''))) FOR UPDATE;
    IF NOT FOUND OR r.purpose NOT LIKE 'GST fee %' OR r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'GST_REVIEW_NOT_A_PAYMENT: % is not a confirmed GST payment', p_reference USING ERRCODE = '23503';
    END IF;
    IF r.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'GST_REVIEW_ARCHIVED: the GST payment % is archived for review; it is settled on Archived payments first', r.reference USING ERRCODE = '23514';
    END IF;
    SELECT * INTO e FROM finance.gst_entitlement(r.student_id, r.session);
    IF NOT coalesce(e.review, false)
       OR EXISTS (SELECT 1 FROM finance.gst_payment_review d2 LEFT JOIN finance.refund rf ON rf.id = d2.refund_id
                   WHERE d2.reference = r.reference AND (d2.decision = 'KEEP' OR rf.state <> 'REJECTED')) THEN
        RAISE EXCEPTION 'GST_REVIEW_NOT_PENDING: the GST payment % is not awaiting a decision: a GST/EPS course requires it, or it is decided already', r.reference
            USING ERRCODE = '23514';
    END IF;
    v_net := r.amount - finance.gst_refunded(r.reference);
    IF v_dec = 'REFUND' THEN
        SELECT s.surname || ', ' || s.other_names INTO v_payer FROM people.student s WHERE s.id = r.student_id;
        -- the existing maker–checker workflow: proposed here, approved by another officer on the refunds desk, paid there
        v_rf := finance.propose_refund(r.student_id, coalesce(nullif(btrim(coalesce(p_payer, '')), ''), v_payer),
                                       'GST fee paid for ' || r.session || ' though no GST/EPS course requires it: ' || v_note,
                                       v_net, p_bank, p_account_name, p_account_last4, r.reference);
        SELECT id INTO v_refund FROM finance.refund WHERE reference = v_rf;
    END IF;
    INSERT INTO finance.gst_payment_review (reference, student_id, session, decision, note, refund_id, decided_by, decided_office)
    VALUES (r.reference, r.student_id, r.session, v_dec, v_note, v_refund, who, office)
    ON CONFLICT (reference) DO UPDATE SET decision = EXCLUDED.decision, note = EXCLUDED.note, refund_id = EXCLUDED.refund_id,
                                           decided_by = EXCLUDED.decided_by, decided_office = EXCLUDED.decided_office, decided_at = now()
    RETURNING * INTO d;
    RETURN d;
END $function$;

-- finance.decide_not_received: the record the bank never received is archived for good, never deleted
CREATE OR REPLACE FUNCTION finance.decide_not_received(p_request text, p_approve boolean, p_note text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := finance.bursary_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        q finance.payment_not_received; r finance.payment_reference; gf record; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO q FROM finance.payment_not_received WHERE request_ref = upper(btrim(p_request)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAY_NOT_RECEIVED_NO_REQUEST: no withdrawal %', p_request USING ERRCODE = '23514'; END IF;
    IF q.state <> 'PROPOSED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_SETTLED: % is already %', q.request_ref, lower(q.state) USING ERRCODE = '23514';
    END IF;
    IF q.raised_by = who THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_SAME_OFFICER: another Bursary officer decides the withdrawal you raised' USING ERRCODE = '42501';
    END IF;
    IF NOT coalesce(p_approve, false) THEN
        IF v_note IS NULL OR length(v_note) < 5 THEN
            RAISE EXCEPTION 'PAY_NOT_RECEIVED_NOTE: say why the withdrawal is rejected' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.payment_not_received SET state = 'REJECTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note
         WHERE id = q.id;
        RETURN 'REJECTED';
    END IF;

    SELECT * INTO r FROM finance.payment_reference WHERE id = q.payment_id FOR UPDATE;
    PERFORM finance.raise_not_received(finance.not_received_refusal(r.id));
    PERFORM set_config('moaum.reason', left('Payment ' || r.reference || ' withdrawn: the bank never received it (' || q.request_ref || ') — ' || q.evidence, 2000), true);
    -- the payment number stays known, so the export loaded again never records it again
    INSERT INTO finance.legacy_payref_withdrawn (payref, reference, request_id, amount)
    SELECT k.payref, k.reference, q.id, k.amount FROM finance.legacy_payref k WHERE k.reference = r.reference
    ON CONFLICT (payref) DO NOTHING;
    SELECT * INTO gf FROM finance.gl_free_payment(r.reference, r.id, 'PAYMENT_WITHDRAWN',
                                                 'the payment ' || r.reference || ' never reached the bank (' || q.request_ref || '): ' || q.evidence);
    INSERT INTO finance.old_payment_withdrawn (id, reference, double_kind, kept_reference, student_id, session, purpose, amount, confirmed_at, channel,
                                               receipt_no, note, ledger_journal, reversal_journal, withdrawn_by, reason)
    VALUES (r.id, r.reference, 'NOT_RECEIVED', coalesce(q.kept_reference, r.reference), r.student_id, r.session, r.purpose, r.amount, r.confirmed_at, r.channel,
            r.receipt_no, r.note, gf.journal, gf.reversal, who, q.request_ref || ': ' || q.reason || coalesce(' — ' || v_note, ''));
    -- V670: archived for good (never received) — kept, counted nowhere — instead of deleted
    PERFORM finance.payment_archive_withdrawn(r.id, 'NOT_RECEIVED_WITHDRAWAL', 'UNVERIFIED_PAYMENT', q.kept_reference,
        q.request_ref || ': ' || q.evidence, q.raised_by, gf.journal, gf.reversal);
    UPDATE finance.payment_not_received SET state = 'APPROVED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
                                            ledger_journal = gf.journal, reversal_journal = gf.reversal
     WHERE id = q.id;
    PERFORM platform.tell_student(q.student_id, 'PAYMENT_NOT_RECEIVED_REMOVED', NULL,
        jsonb_build_object('AMOUNT', 'NGN ' || to_char(q.amount, 'FM999,999,990.00'), 'PAID_ON', coalesce(to_char(q.paid_on, 'DD Mon YYYY'), 'the date recorded'),
                           'SESSION', q.session, 'REFERENCE', q.reference),
        'payment-not-received:' || q.id);
    RETURN 'APPROVED';
END $function$;

-- finance.decide_overpayments: a refund's source: a payment that counts
CREATE OR REPLACE FUNCTION finance.decide_overpayments(p_session text, p_decision text, p_students uuid[], p_reason text, p_limit integer DEFAULT 2000)
 RETURNS TABLE(carried integer, refunds integer, held integer, remaining integer)
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, '')); v_decision text := upper(btrim(coalesce(p_decision, '')));
        v_next text; o record; v_ref text; v_src text; v_journal uuid; v_rf text; v_id uuid; nc int := 0; nr int := 0; v_left int; nh int;
        v_held uuid[];
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'OVERPAY_ACTOR: an overpayment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF v_decision NOT IN ('CARRY', 'REFUND') THEN
        RAISE EXCEPTION 'OVERPAY_DECISION: an overpayment is carried into the next session (CARRY) or refunded (REFUND)' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'OVERPAY_REASON: say why (at least ten characters); it is kept with each decision' USING ERRCODE = '23514';
    END IF;
    IF v_decision = 'CARRY' THEN
        v_next := finance.next_session(p_session);
        IF v_next IS NULL THEN
            RAISE EXCEPTION 'OVERPAY_NO_NEXT_SESSION: no session follows % on the calendar to carry the excess into', p_session USING ERRCODE = '23514',
                HINT = 'Add the next session on the academic calendar, or refund the excess instead.';
        END IF;
    END IF;
    -- V561: a student whose school fees may have been charged twice by the bank waits until the Bursary has checked with it
    v_held := ARRAY(SELECT DISTINCT d.student_id FROM finance.possible_double_charges(p_session) d
                     WHERE d.purpose LIKE 'School fees%' AND (d.verdict IS NULL OR d.open_requests > 0));
    FOR o IN SELECT * FROM finance.overpaid(p_session) x
              WHERE x.decision IS NULL AND x.excess >= 1 AND (p_students IS NULL OR x.student_id = ANY (p_students))
                AND NOT (x.student_id = ANY (v_held))
              ORDER BY x.number LIMIT greatest(1, coalesce(p_limit, 2000)) LOOP
        PERFORM pg_advisory_xact_lock(hashtext('overpay:' || o.student_id::text || ':' || p_session));
        IF EXISTS (SELECT 1 FROM finance.overpayment_settled(o.student_id, p_session)) THEN CONTINUE; END IF;
        -- a refund the desk rejected leaves the excess to be decided again
        UPDATE finance.overpayment_decision SET superseded_at = now()
         WHERE student_id = o.student_id AND session = p_session AND superseded_at IS NULL;
        IF v_decision = 'CARRY' THEN
            v_ref := 'MOAUM-CF-' || regexp_replace(upper(o.number), '[^0-9A-Z]', '', 'g') || '-' || replace(p_session, '/', '-');
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref OR receipt_no = 'RCT-' || v_ref) THEN
                v_ref := v_ref || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
            END IF;
            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                   channel, note, receipt_no)
            VALUES (o.student_id, v_next, v_ref, 'School fees ' || v_next || ' (carried from ' || p_session || ')', o.excess, now(), now(), now(), v_actor,
                    'CARRIED', 'Overpaid on ' || p_session || ' (paid ' || to_char(o.paid, 'FM999,999,999,990.00') || ', due ' || to_char(o.due, 'FM999,999,999,990.00')
                               || '), carried into ' || v_next || ': ' || v_reason, 'RCT-' || v_ref);
            -- no new money: the school-fees income moves from the overpaid session to the next
            v_journal := finance.gl_post(current_date, 'School fees overpaid on ' || p_session || ' carried into ' || v_next || ' — ' || v_ref,
                                         'AUTO', 'PAYMENT', v_ref,
                jsonb_build_array(
                    jsonb_build_object('account', finance.gl_income_account('School fees'), 'debit', o.excess,
                                       'narration', 'Overpaid on ' || p_session || ', carried into ' || v_next, 'session', p_session),
                    jsonb_build_object('account', finance.gl_income_account('School fees'), 'credit', o.excess,
                                       'narration', 'Carried from ' || p_session, 'session', v_next)));
            INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, to_session, reference, journal, decided_by, reason)
            VALUES (o.student_id, p_session, o.due, o.paid, o.excess, 'CARRY', v_next, v_ref, v_journal, v_actor, v_reason)
            RETURNING id INTO v_id;
            -- V519: the student told
            PERFORM platform.tell_student(o.student_id, 'OVERPAYMENT_CARRIED', NULL,
                jsonb_build_object('SESSION_FROM', p_session, 'SESSION_TO', v_next, 'AMOUNT', 'NGN ' || to_char(o.excess, 'FM999,999,990.00'), 'REFERENCE', v_ref),
                'overpayment-carried:' || v_id);
            nc := nc + 1;
        ELSE
            -- against the latest school-fees payment of the session that covers the excess, when one does
            v_src := (SELECT r.reference FROM finance.payment_reference r
                       WHERE r.student_id = o.student_id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
                         AND r.amount - coalesce((SELECT sum(f.amount) FROM finance.refund f WHERE f.source_reference = r.reference AND f.state <> 'REJECTED'), 0) >= o.excess
                       ORDER BY r.confirmed_at DESC, r.reference LIMIT 1);
            v_rf := finance.propose_refund(o.student_id, o.name,
                        'School fees overpaid on ' || p_session || ' (paid ' || to_char(o.paid, 'FM999,999,999,990.00') || ', due '
                        || to_char(o.due, 'FM999,999,999,990.00') || '): ' || v_reason, o.excess, NULL, NULL, NULL, v_src);
            INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, reference, decided_by, reason)
            VALUES (o.student_id, p_session, o.due, o.paid, o.excess, 'REFUND', v_rf, v_actor, v_reason);
            -- V519: the student told
            PERFORM platform.tell_student(o.student_id, 'OVERPAYMENT_REFUND_RAISED', NULL,
                jsonb_build_object('SESSION_FROM', p_session, 'AMOUNT', 'NGN ' || to_char(o.excess, 'FM999,999,990.00'), 'REFUND', v_rf),
                'overpayment-refund:' || v_rf);
            nr := nr + 1;
        END IF;
    END LOOP;
    SELECT count(*) FILTER (WHERE x.student_id = ANY (v_held)), count(*) FILTER (WHERE NOT (x.student_id = ANY (v_held)))
      INTO nh, v_left
      FROM finance.overpaid(p_session) x
     WHERE x.decision IS NULL AND x.excess >= 1 AND (p_students IS NULL OR x.student_id = ANY (p_students));
    RETURN QUERY SELECT nc, nr, nh, v_left;
END $function$;

-- finance.decide_payment_reallocation: the student's money received: payments that count
CREATE OR REPLACE FUNCTION finance.decide_payment_reallocation(p_id uuid, p_decision text, p_note text, p_confirmed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    SELECT coalesce(sum(p.amount), 0) INTO v_cash_before FROM finance.payment_reference p WHERE p.student_id = x.student_id AND p.confirmed_at IS NOT NULL AND p.archived_at IS NULL;

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
    SELECT coalesce(sum(p.amount), 0) INTO v_cash_after FROM finance.payment_reference p WHERE p.student_id = x.student_id AND p.confirmed_at IS NOT NULL AND p.archived_at IS NULL;
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
END $function$;

-- finance.decide_payment_swap: the session's receipts: payments that count; a swap settling an archived payment decided with it
CREATE OR REPLACE FUNCTION finance.decide_payment_swap(p_swap uuid, p_approve boolean, p_note text, p_confirmed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
END $function$;

-- finance.gl_sync: an archived payment is left unposted until it is settled
CREATE OR REPLACE FUNCTION finance.gl_sync(p_limit integer)
 RETURNS TABLE(payments integer, refunds integer, vouchers integer, remaining bigint, wallet integer)
 LANGUAGE plpgsql
AS $function$
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
         WHERE pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL
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
END $function$;

-- finance.gl_unposted: an archived payment is not waiting to be posted
CREATE OR REPLACE FUNCTION finance.gl_unposted()
 RETURNS TABLE(payments bigint, refunds bigint, vouchers bigint, wallet bigint)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT (SELECT count(*) FROM finance.payment_reference pr
             WHERE pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL
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
$function$;

-- finance.gl_unposted_until: an archived payment is not waiting to be posted
CREATE OR REPLACE FUNCTION finance.gl_unposted_until(p_to date)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
    SELECT (SELECT count(*) FROM finance.payment_reference pr
             WHERE pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.confirmed_at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference))
         + (SELECT count(*) FROM reporting.payments v
             WHERE v.source <> 'STUDENT' AND v.confirmed_at IS NOT NULL AND v.amount > 0 AND v.confirmed_at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = v.reference))
         + (SELECT count(*) FROM finance.refund rf
             WHERE rf.state = 'PAID' AND rf.paid_at IS NOT NULL AND coalesce(rf.paid_on, rf.paid_at::date) <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'REFUND' AND j.source_ref = rf.reference))
         + (SELECT count(*) FROM expenditure.voucher v
             WHERE v.stage = 'PAID' AND v.paid_at IS NOT NULL AND v.paid_at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference))
         + (SELECT count(*) FROM finance.wallet_entry e
             WHERE e.recorded_at IS NOT NULL AND e.kind IN ('CREDIT', 'REVERSED', 'REFUND') AND e.at::date <= p_to
               AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'WALLET' AND j.source_ref = 'WALLET-' || e.id))
$function$;

-- finance.gst_course_stats: GST payers: payments that count
CREATE OR REPLACE FUNCTION finance.gst_course_stats(p_session text, p_semester integer, p_office text)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, level integer, semester integer, general_office text, dept_code text, department text, lecturer_id uuid, lecturer text, state text, registered bigint, entitled bigint, sheet_id uuid, stage text, graded bigint, published_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pays AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
                   WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL)
    SELECT o.id, c.code, c.title, c.units, c.level, o.semester, c.general_office, c.dept_code, d.name, o.lecturer_id,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END, c.state,
           (SELECT count(*) FROM registration.entry e WHERE e.offering_id = o.id AND e.status <> 'DROPPED'),
           (SELECT count(*) FROM registration.entry e JOIN registration.course_registration cr ON cr.id = e.registration_id
              JOIN pays py ON py.student_id = cr.student_id WHERE e.offering_id = o.id AND e.status <> 'DROPPED'),
           sh.id, sh.stage,
           CASE WHEN sh.id IS NULL THEN 0 ELSE (SELECT count(*) FROM assessment.latest_scores(sh.id) WHERE outcome = 'GRADED') END,
           sh.published_at
      FROM catalogue.offering o
      JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
      JOIN ref.department d ON d.code = c.dept_code
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
      LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
     WHERE o.session = p_session AND o.stream = 'REGULAR' AND (p_semester IS NULL OR o.semester = p_semester) AND (p_office IS NULL OR c.general_office = p_office)
     ORDER BY o.semester, c.level, c.code
$function$;

-- finance.gst_entitlement: the GST fee paid only by payments that count
CREATE OR REPLACE FUNCTION finance.gst_entitlement(p_student uuid, p_session text)
 RETURNS TABLE(required boolean, stated boolean, fee numeric, covers_eps boolean, paid numeric, entitled boolean, state text, reference text, receipt_no text, paid_at timestamp with time zone, open_reference text, open_amount numeric, open_expires_at timestamp with time zone, source text, channel text, legacy_reference text, gst_required boolean, eps_required boolean, reason text, gst_reason text, eps_reason text, review boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH f AS (SELECT * FROM finance.gst_fee_for(p_student, p_session)),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    -- V367: a payment counts net of the refunds approved or paid against it (finance.refund.source_reference); refunded in full, it entitles no more
    pays AS (SELECT r.id, r.reference, r.receipt_no, r.amount - x.refunded AS amount, r.confirmed_at, r.channel
               FROM finance.payment_reference r
               CROSS JOIN LATERAL (SELECT finance.gst_refunded(r.reference) AS refunded) x
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                AND r.amount > x.refunded),
    agg AS (SELECT coalesce(sum(amount), 0) AS paid, max(confirmed_at) AS paid_at, count(*) AS n FROM pays),
    last AS (SELECT p.id, p.reference, p.receipt_no, p.channel FROM pays p ORDER BY p.confirmed_at DESC LIMIT 1),
    open AS (SELECT r.reference, r.amount, r.expires_at
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()
              ORDER BY r.generated_at DESC LIMIT 1),
    el AS (SELECT * FROM finance.gst_eps_eligibility(p_student, p_session)),
    -- whether this portal runs GST/EPS in the session at all: a payment no course requires is only questioned where it does
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session AND o.stream = 'REGULAR') AS gst_run)
    SELECT el.required, f.stated, f.amount, cfg.covers_eps, agg.paid,
           -- a confirmed reference was generated for the fee as it stood: a later change of the fee does not unmake the payment
           (agg.n > 0 OR (f.stated AND f.amount = 0)) AS entitled,
           CASE WHEN agg.n > 0 THEN 'PAID'
                WHEN NOT el.required THEN 'NOT_REQUIRED'
                WHEN f.stated AND f.amount = 0 THEN 'EXEMPT'
                WHEN NOT f.stated THEN 'NOT_STATED'
                WHEN open.reference IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           last.reference, last.receipt_no, agg.paid_at, open.reference, open.amount, open.expires_at,
           CASE WHEN last.id IS NULL THEN NULL WHEN last.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           last.channel,
           (SELECT coalesce(lp.source_reference, lp.source_transaction_id) FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment lp ON lp.id = rc.payment_id WHERE rc.payment_reference_id = last.id),
           el.gst_required, el.eps_required, el.reason, el.gst_reason, el.eps_reason,
           -- V367: until the Bursary decides it — kept, or refunded through the refund workflow
           (agg.n > 0 AND NOT el.required AND run.gst_run AND NOT finance.gst_review_settled(p_student, p_session))
      FROM f CROSS JOIN cfg CROSS JOIN agg CROSS JOIN el CROSS JOIN run LEFT JOIN last ON true LEFT JOIN open ON true
$function$;

-- finance.gst_population: GST payers: payments that count
CREATE OR REPLACE FUNCTION finance.gst_population(p_session text, p_semester integer)
 RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, status text, entry_mode text, required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamp with time zone, gst_registered boolean, eps_registered boolean, gst_courses integer, eps_courses integer, registered_at timestamp with time zone, pay_source text, gst_required boolean, eps_required boolean, gst_reason text, eps_reason text, gst_carryover boolean, eps_carryover boolean, gst_completed boolean, eps_completed boolean, gst_owed text, eps_owed text, review boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH base AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex,
               p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.programme_code, p.name AS programme,
               s.current_level AS level, s.status, s.entry_mode
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = d.faculty_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session AND o.stream = 'REGULAR') AS gst_run),
    -- the engine over the whole register at once; a semester asked for narrows what is owed to the courses run in it
    eng AS (SELECT r.student_id, r.office, r.source, r.status, r.course_code,
                   (r.counts AND (p_semester IS NULL OR p_semester = ANY (r.semesters))) AS due
              FROM finance.gst_eps_rows_all(p_session) r),   -- V468: the whole register, planned without nested loops
    req AS (SELECT x.student_id,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'GST'), false) AS g_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'GST'), false) AS g_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'GST'), false) AS g_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'GST'), false) AS g_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'GST'), false) AS g_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'GST' AND x.due), false) AS g_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'GST' AND x.due) AS g_owed,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'EPS'), false) AS e_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'EPS'), false) AS e_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'EPS'), false) AS e_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'EPS'), false) AS e_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'EPS'), false) AS e_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'EPS' AND x.due), false) AS e_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'EPS' AND x.due) AS e_owed
              FROM eng x GROUP BY x.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM finance.gst_fee f WHERE f.session = p_session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    -- V573: the fee each (programme, faculty, level, entry mode) is charged, matched once a combination (some 600) rather than once a
    -- student (some 51,000): the same lateral match, read by key
    fkeys AS MATERIALIZED (
        SELECT k.programme_code, k.faculty_code, k.level, k.entry_mode, fr.id, fr.amount
          FROM (SELECT DISTINCT s.programme_code, p.faculty_code, s.current_level AS level, s.entry_mode
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
                 WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND s.entry_mode IS DISTINCT FROM 'CCE') k
          LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                              WHERE (f.programme_code IS NULL OR f.programme_code = k.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = k.faculty_code)
                                AND (f.level IS NULL OR f.level = k.level) AND (f.entry_mode IS NULL OR f.entry_mode = k.entry_mode)
                              ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                              LIMIT 1) fr ON true),
    -- V367: net of the refunds approved or paid against each payment; a payment refunded in full no longer counts
    refunded AS (SELECT rf.source_reference AS reference, sum(rf.amount) AS amount FROM finance.refund rf
                  WHERE rf.state IN ('APPROVED', 'PAID') AND rf.source_reference IS NOT NULL GROUP BY rf.source_reference),
    net AS (SELECT r.student_id, r.reference, r.channel, r.confirmed_at, r.amount - coalesce(x.amount, 0) AS amount
              FROM finance.payment_reference r LEFT JOIN refunded x ON x.reference = r.reference
             WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.amount > coalesce(x.amount, 0)),
    pays AS (SELECT r.student_id, sum(r.amount) AS paid, max(r.confirmed_at) AS paid_at, count(*) AS n,
                    (array_agg(r.reference ORDER BY r.confirmed_at DESC))[1] AS reference,
                    (array_agg(r.channel ORDER BY r.confirmed_at DESC))[1] AS channel
               FROM net r
              GROUP BY r.student_id),
    -- V367: a payment no course requires stays in review until the Bursary decides it
    undecided AS (SELECT DISTINCT r.student_id FROM net r
                   WHERE NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                                      WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED'))),
    pend AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()),
    regs AS (SELECT cr.student_id,
                    count(*) FILTER (WHERE c.general_office = 'GST') AS gst_courses,
                    count(*) FILTER (WHERE c.general_office = 'EPS') AS eps_courses,
                    min(cr.submitted_at) AS registered_at
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
               JOIN catalogue.offering o ON o.id = e.offering_id
               JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
              WHERE cr.session = p_session AND (p_semester IS NULL OR cr.semester = p_semester)
              GROUP BY cr.student_id),
    j AS (SELECT b.*, coalesce(q.g_req, false) AS g_req, coalesce(q.e_req, false) AS e_req,
                 (coalesce(q.g_req, false) OR (coalesce(q.e_req, false) AND cfg.covers_eps)) AS req,
                 q.g_off, q.g_carry, q.g_reg, q.g_done, q.g_none, q.g_complete, q.g_owed,
                 q.e_off, q.e_carry, q.e_reg, q.e_done, q.e_none, q.e_complete, q.e_owed,
                 fr.id AS fee_id, fr.amount AS fee_amount, py.paid, py.paid_at, py.n, py.reference, py.channel, pd.student_id AS pending,
                 rg.gst_courses, rg.eps_courses, rg.registered_at, run.gst_run AS run_on, (ud.student_id IS NOT NULL) AS undecided
            FROM base b
            CROSS JOIN cfg CROSS JOIN run
            LEFT JOIN req q ON q.student_id = b.id
            LEFT JOIN fkeys fr ON fr.programme_code = b.programme_code AND coalesce(fr.faculty_code, '') = coalesce(b.faculty_code, '')
                              AND coalesce(fr.level, -1) = coalesce(b.level, -1) AND coalesce(fr.entry_mode, '') = coalesce(b.entry_mode, '')
            LEFT JOIN pays py ON py.student_id = b.id
            LEFT JOIN pend pd ON pd.student_id = b.id
            LEFT JOIN regs rg ON rg.student_id = b.id
            LEFT JOIN undecided ud ON ud.student_id = b.id)
    SELECT j.id, j.number, j.surname, j.other_names, j.sex, j.faculty_code, j.faculty, j.dept_code, j.department, j.programme_code, j.programme,
           j.level, j.status, j.entry_mode,
           j.req,
           coalesce(j.fee_amount, 0), (j.fee_id IS NOT NULL),
           coalesce(j.paid, 0),
           (coalesce(j.n, 0) > 0 OR (j.fee_id IS NOT NULL AND j.fee_amount = 0)),
           CASE WHEN coalesce(j.n, 0) > 0 THEN 'PAID'
                WHEN NOT j.req THEN 'NOT_REQUIRED'
                WHEN j.fee_id IS NOT NULL AND j.fee_amount = 0 THEN 'EXEMPT'
                WHEN j.fee_id IS NULL THEN 'NOT_STATED'
                WHEN j.pending IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           j.reference, j.paid_at,
           coalesce(j.gst_courses, 0) > 0, coalesce(j.eps_courses, 0) > 0, coalesce(j.gst_courses, 0)::int, coalesce(j.eps_courses, 0)::int, j.registered_at,
           CASE WHEN j.n IS NULL THEN NULL WHEN j.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           j.g_req, j.e_req,
           finance.gst_eps_reason('GST', coalesce(j.g_off, false), coalesce(j.g_carry, false), coalesce(j.g_reg, false), coalesce(j.g_done, false), coalesce(j.g_none, false)),
           finance.gst_eps_reason('EPS', coalesce(j.e_off, false), coalesce(j.e_carry, false), coalesce(j.e_reg, false), coalesce(j.e_done, false), coalesce(j.e_none, false)),
           coalesce(j.g_carry, false), coalesce(j.e_carry, false), coalesce(j.g_complete, false), coalesce(j.e_complete, false),
           j.g_owed, j.e_owed,
           (coalesce(j.n, 0) > 0 AND NOT j.req AND j.run_on AND j.undecided)
      FROM j
$function$;

-- finance.gst_review_settled: a GST payment under review: one that counts
CREATE OR REPLACE FUNCTION finance.gst_review_settled(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT NOT EXISTS (
        SELECT 1 FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND r.amount > finance.gst_refunded(r.reference)
           AND NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                            WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED')))
$function$;

-- finance.historical_other_payments: other payments of a graduate: those that count
CREATE OR REPLACE FUNCTION finance.historical_other_payments(p_students uuid[])
 RETURNS TABLE(student_id uuid, payment_id uuid, reference text, session text, purpose text, amount numeric, confirmed_at timestamp with time zone, channel text, kind text, desk_status text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH owe AS (SELECT DISTINCT x.student_id, x.session FROM finance.historical_rows(p_students) x WHERE x.outstanding > 0)
    SELECT r.student_id, r.id, r.reference, r.session, r.purpose, r.amount, r.confirmed_at, r.channel,
           CASE WHEN r.channel = 'Legacy' AND r.purpose ~* '^outstanding' THEN 'OUTSTANDING_FEES' ELSE 'OTHER' END,
           lo.status
      FROM finance.payment_reference r
      JOIN owe o ON o.student_id = r.student_id AND o.session = r.session
      LEFT JOIN finance.legacy_outstanding_payment lo ON lo.payment_id = r.id
     WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
       AND r.purpose NOT LIKE 'School fees%'
       AND r.purpose ~* '(outstanding|tuition|school|jamb|utme)'
$function$;

-- finance.historical_refresh: a graduate's last payment: one that counts
CREATE OR REPLACE FUNCTION finance.historical_refresh(p_students uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_ids uuid[]; n int;
BEGIN
    v_ids := coalesce(p_students, (SELECT array_agg(s.id) FROM people.student s
                                    WHERE s.status = 'GRADUATED'
                                       OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')));
    IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
        IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
        RETURN 0;
    END IF;
    WITH hr AS (SELECT * FROM finance.historical_rows(v_ids)),
    agg AS (
        SELECT r.student_id, min(r.session) AS first_session, max(r.session) AS last_session, count(*)::int AS periods,
               coalesce(sum(r.assessed), 0) AS assessed, coalesce(sum(r.paid), 0) AS paid, coalesce(sum(r.outstanding), 0) AS outstanding,
               coalesce(sum(r.credit), 0) AS credit, coalesce(sum(r.waived), 0) AS waived,
               count(*) FILTER (WHERE r.outstanding > 0)::int AS owing_periods,
               count(*) FILTER (WHERE r.status = 'REQUIRES_REVIEW')::int AS review_periods,
               count(*) FILTER (WHERE r.status = 'PENDING_APPROVAL')::int AS pending_periods,
               count(*) FILTER (WHERE r.status = 'PARTIALLY_PAID')::int AS partial_periods,
               string_agg(r.session || ' S' || r.semester, ', ' ORDER BY r.session, r.semester) FILTER (WHERE r.outstanding > 0) AS owing
          FROM hr r GROUP BY r.student_id),
    ids AS (SELECT DISTINCT unnest(v_ids) AS student_id),
    up AS (
        INSERT INTO finance.historical_summary AS h (student_id, first_session, last_session, periods, assessed, paid, outstanding, credit, owing_periods,
                                                     review_periods, pending_periods, partial_periods, owing, financial_status, last_payment_at, refreshed_at, waived)
        SELECT i.student_id, a.first_session, a.last_session, coalesce(a.periods, 0), coalesce(a.assessed, 0), coalesce(a.paid, 0), coalesce(a.outstanding, 0),
               coalesce(a.credit, 0), coalesce(a.owing_periods, 0), coalesce(a.review_periods, 0), coalesce(a.pending_periods, 0), coalesce(a.partial_periods, 0), a.owing,
               CASE WHEN coalesce(a.periods, 0) = 0 THEN 'NO_HISTORICAL_PERIOD'
                    WHEN a.review_periods > 0 THEN 'HISTORICAL_FEE_REVIEW_REQUIRED'
                    WHEN a.pending_periods > 0 THEN 'FINANCIAL_CLEARANCE_PENDING'
                    WHEN a.outstanding > 0 THEN 'FINANCIAL_OBLIGATION'
                    ELSE 'FINANCIALLY_CLEARED' END,
               (SELECT max(r.confirmed_at) FROM finance.payment_reference r WHERE r.student_id = i.student_id AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
               now(), coalesce(a.waived, 0)
          FROM ids i LEFT JOIN agg a ON a.student_id = i.student_id
        ON CONFLICT (student_id) DO UPDATE SET first_session = EXCLUDED.first_session, last_session = EXCLUDED.last_session, periods = EXCLUDED.periods,
            assessed = EXCLUDED.assessed, paid = EXCLUDED.paid, outstanding = EXCLUDED.outstanding, credit = EXCLUDED.credit,
            owing_periods = EXCLUDED.owing_periods, review_periods = EXCLUDED.review_periods, pending_periods = EXCLUDED.pending_periods,
            partial_periods = EXCLUDED.partial_periods, owing = EXCLUDED.owing, financial_status = EXCLUDED.financial_status,
            last_payment_at = EXCLUDED.last_payment_at, refreshed_at = EXCLUDED.refreshed_at, waived = EXCLUDED.waived
        RETURNING 1)
    SELECT count(*) INTO n FROM up;
    DELETE FROM finance.historical_stale x WHERE x.student_id = ANY (v_ids);
    IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
    RETURN n;
END $function$;

-- finance.historical_rows_read: a graduate's payments: those that count
CREATE OR REPLACE FUNCTION finance.historical_rows_read(p_students uuid[])
 RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text, assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric, paid numeric, outstanding numeric, credit numeric, status text, waived numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS MATERIALIZED (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    bounds AS MATERIALIZED (SELECT finance.historical_start() AS start,
                                   (SELECT max(a.name) FROM policy.academic_session a
                                     WHERE a.state NOT IN ('CANCELLED', 'DRAFT') AND a.name < coalesce(policy.university_current_session(), '9999/9999')) AS before_current),
    -- the calendar's order, as people.level_in counts the sessions since admission (every session row, by its start)
    cal AS MATERIALIZED (SELECT a.name, a.state, a.semesters, row_number() OVER (ORDER BY a.starts_on, a.name) AS idx FROM policy.academic_session a),
    st AS MATERIALIZED (
        SELECT s.id, s.programme_code, p.faculty_code, p.category, s.entry_mode, s.entry_session, s.entry_level, s.current_level,
               people.is_postgraduate(s.entry_mode, p.category) AS pg,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               greatest(s.entry_session, b.start) AS first_session,
               CASE WHEN s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                    THEN records.graduation_session(s.id) ELSE b.before_current END AS last_session
          FROM unnest(p_students) u(id)
          JOIN people.student s ON s.id = u.id
          JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN bounds b
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.entry_session IS NOT NULL),
    -- the programme's final level read once a programme
    fl AS MATERIALIZED (SELECT d.programme_code, finance.final_level(d.programme_code) AS final_level FROM (SELECT DISTINCT st.programme_code FROM st) d),
    per0 AS MATERIALIZED (
        -- the sessions of the record, each semester of each, a deferred session or semester left out
        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester, a.idx AS ses_idx
          FROM st
          JOIN fl ON fl.programme_code = st.programme_code
          JOIN cal a ON a.name >= st.first_session AND a.name <= st.last_session AND a.state NOT IN ('CANCELLED', 'DRAFT')
          CROSS JOIN LATERAL generate_series(1, a.semesters) sm(n)
         WHERE st.last_session IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM people.deferment d
                            WHERE d.student_id = st.id AND d.session = a.name AND d.state IN ('APPROVED', 'ACTIVE', 'COMPLETED')
                              AND (d.kind = 'SESSION' OR d.semester = sm.n))),
    -- the level of each period, read as people.level_in reads it — the semester's registration, else the session's, else the
    -- enrolment, else counted from admission (a postgraduate's own level) — for every student at once
    reg AS MATERIALIZED (SELECT r.student_id, r.session, r.semester, r.level, r.status IN ('APPROVED', 'LOCKED') AS ok
                           FROM registration.course_registration r WHERE r.student_id = ANY (p_students)),
    reg_sem AS (SELECT DISTINCT ON (g.student_id, g.session, g.semester) g.student_id, g.session, g.semester, g.level FROM reg g
                 ORDER BY g.student_id, g.session, g.semester, g.ok DESC),
    reg_ses AS (SELECT DISTINCT ON (g.student_id, g.session) g.student_id, g.session, g.level FROM reg g ORDER BY g.student_id, g.session, g.ok DESC, g.semester),
    enr AS (SELECT DISTINCT ON (e.student_id, e.session) e.student_id, e.session, e.level FROM people.enrolment e WHERE e.student_id = ANY (p_students)
             ORDER BY e.student_id, e.session),
    per AS MATERIALIZED (
        SELECT p0.*, coalesce(rs.level, rx.level, en.level,
                              CASE WHEN p0.pg THEN p0.current_level
                                   WHEN es.idx IS NOT NULL AND p0.ses_idx >= es.idx THEN least(600, p0.entry_level + 100 * (p0.ses_idx - es.idx)::int) END,
                              p0.current_level) AS level
          FROM per0 p0
          LEFT JOIN cal es ON es.name = p0.entry_session
          LEFT JOIN reg_sem rs ON rs.student_id = p0.id AND rs.session = p0.session AND rs.semester = p0.semester
          LEFT JOIN reg_ses rx ON rx.student_id = p0.id AND rx.session = p0.session
          LEFT JOIN enr en ON en.student_id = p0.id AND en.session = p0.session),
    ses AS MATERIALIZED (
        -- one profile a session: the student as they were in its first semester on the record
        SELECT DISTINCT ON (pe.id, pe.session) pe.* FROM per pe ORDER BY pe.id, pe.session, pe.semester),
    -- the faculty a faculty is charged as, read once a faculty and session; a PG student's stage read once a session
    src AS MATERIALIZED (SELECT d.faculty_code, d.session, finance.fee_source_of(d.faculty_code, d.session) AS src
                           FROM (SELECT DISTINCT x.faculty_code, x.session FROM ses x WHERE x.entry_mode IS DISTINCT FROM 'CCE' AND NOT x.pg) d),
    pgs AS MATERIALIZED (SELECT y.student_id, d.session, y.stage_code, y.category
                           FROM (SELECT x.session, array_agg(x.id) AS ids FROM ses x WHERE x.pg GROUP BY x.session) d
                           CROSS JOIN LATERAL admissions.pg_stages_of(d.session, d.ids) y),
    prof AS MATERIALIZED (
        -- the student as they were in the session: spillover read from its level against the programme's final level
        SELECT pe.*, coalesce(pe.level > pe.final_level, false) AS is_spill,
               CASE WHEN pe.level > pe.final_level THEN least((pe.level - pe.final_level) / 100, 3) END AS spill_year,
               CASE WHEN pe.level > pe.final_level THEN finance.reg_semesters(pe.id, pe.session) END AS reg_sems,   -- V616: read for a spillover student only
               sr.src, pg.stage_code AS pg_stage, pg.category AS pg_category
          FROM ses pe
          LEFT JOIN src sr ON sr.faculty_code = pe.faculty_code AND sr.session = pe.session AND pe.entry_mode IS DISTINCT FROM 'CCE' AND NOT pe.pg
          LEFT JOIN pgs pg ON pg.student_id = pe.id AND pg.session = pe.session),
    matched AS (
        -- the session's fee lines that reach the student as they were; a whole-session line is due with the first semester
        SELECT pr.id AS student_id, pr.session, coalesce(f.semester, 1) AS semester, f.amount
          FROM prof pr
          JOIN finance.fee_schedule f ON f.session = pr.session AND f.ended_at IS NULL AND f.kind = 'FEE'
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN pr.is_spill THEN pr.final_level ELSE pr.level END)
           AND (f.spill_year IS NULL OR f.spill_year = pr.spill_year)
           AND finance.spill_line_applies(pr.is_spill, f.semester, pr.reg_sems)
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND finance.pg_line(pr.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, pr.pg_stage, pr.pg_category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = pr.indigene)),
    struct AS (SELECT m.student_id, m.session, m.semester, sum(m.amount) AS amount, count(*)::int AS lines FROM matched m GROUP BY 1, 2, 3),
    stated AS (SELECT DISTINCT m.student_id, m.session FROM matched m),
    apr AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
             WHERE a.student_id = ANY (p_students) AND a.state = 'APPROVED'),
    pend AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
              WHERE a.student_id = ANY (p_students) AND a.state IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'DRAFT')),
    -- V665: the approved waivers and adjustments of each period
    wv AS (SELECT w.student_id, w.session, w.semester, sum(w.amount) AS waived FROM finance.historical_waiver w
            WHERE w.student_id = ANY (p_students) AND w.state = 'APPROVED' GROUP BY 1, 2, 3),
    pay AS (SELECT r.student_id, r.session, sum(r.amount) AS paid FROM finance.payment_reference r
             WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
             GROUP BY 1, 2),
    base0 AS (
        SELECT pr.id AS student_id, pr.session, pr.semester, pr.level, pr.programme_code,
               coalesce(ap.amount, CASE WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,
               CASE WHEN ap.id IS NOT NULL THEN 'ASSESSMENT' WHEN sd.session IS NOT NULL THEN 'STRUCTURE' ELSE 'NONE' END AS source,
               CASE WHEN ap.id IS NOT NULL THEN ap.reference
                    WHEN sd.session IS NOT NULL THEN pr.session || ' fee structure' || CASE WHEN sr.lines IS NULL THEN ' (nothing due this semester)'
                                                                                          ELSE ' (' || sr.lines || CASE WHEN sr.lines = 1 THEN ' line)' ELSE ' lines)' END END END AS source_ref,
               ap.id AS assessment_id, sr.amount AS structure_amount, coalesce(sr.lines, 0) AS structure_lines,
               pn.id AS pending_id, pn.reference AS pending_ref, pn.amount AS pending_amount,
               coalesce(py.paid, 0) AS session_paid, coalesce(w.waived, 0) AS waived
          FROM per pr
          LEFT JOIN struct sr ON sr.student_id = pr.id AND sr.session = pr.session AND sr.semester = pr.semester
          LEFT JOIN stated sd ON sd.student_id = pr.id AND sd.session = pr.session
          LEFT JOIN apr ap ON ap.student_id = pr.id AND ap.session = pr.session AND ap.semester = pr.semester
          LEFT JOIN pend pn ON pn.student_id = pr.id AND pn.session = pr.session AND pn.semester = pr.semester
          LEFT JOIN pay py ON py.student_id = pr.id AND py.session = pr.session
          LEFT JOIN wv w ON w.student_id = pr.id AND w.session = pr.session AND w.semester = pr.semester),
    -- what the period is owed on: the amount assessed less the approved waivers (never below nothing)
    base AS (SELECT b0.*, CASE WHEN b0.assessed IS NULL THEN NULL ELSE greatest(b0.assessed - b0.waived, 0) END AS net FROM base0 b0),
    alloc AS (
        -- the session's payments fill the assessed semesters in order (each on what it is owed on); what is left goes to the first
        -- semester not yet assessed, else stands as a credit on the session's last semester
        SELECT b.*,
               coalesce(sum(b.net) OVER (PARTITION BY b.student_id, b.session ORDER BY b.semester ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS before_me,
               coalesce(sum(b.net) OVER (PARTITION BY b.student_id, b.session), 0) AS session_assessed,
               min(b.semester) FILTER (WHERE b.assessed IS NULL) OVER (PARTITION BY b.student_id, b.session) AS first_unassessed,
               max(b.semester) OVER (PARTITION BY b.student_id, b.session) AS last_semester
          FROM base b),
    fin AS (
        SELECT a.*,
               CASE WHEN a.net IS NOT NULL THEN least(greatest(a.session_paid - a.before_me, 0), a.net)
                    WHEN a.semester = a.first_unassessed THEN greatest(a.session_paid - a.session_assessed, 0)
                    ELSE 0 END AS paid_here,
               CASE WHEN a.first_unassessed IS NULL AND a.semester = a.last_semester THEN greatest(a.session_paid - a.session_assessed, 0) ELSE 0 END AS credit_here
          FROM alloc a)
    SELECT f.student_id, f.session, f.semester, f.level, f.programme_code, f.assessed, f.source, f.source_ref, f.assessment_id,
           f.structure_amount, f.structure_lines, f.pending_id, f.pending_ref, f.pending_amount,
           f.paid_here + f.credit_here AS paid,
           CASE WHEN f.net IS NULL THEN NULL ELSE finance.fee_owed(f.net, f.paid_here) END AS outstanding,
           f.credit_here AS credit,
           CASE WHEN f.net IS NULL THEN CASE WHEN f.pending_id IS NOT NULL THEN 'PENDING_APPROVAL' ELSE 'REQUIRES_REVIEW' END
                WHEN f.credit_here >= 1 THEN 'CREDIT'
                WHEN finance.fee_owed(f.net, f.paid_here) = 0 THEN 'CLEARED'
                WHEN f.paid_here > 0 THEN 'PARTIALLY_PAID'
                ELSE 'OUTSTANDING' END AS status,
           f.waived
      FROM fin f
$function$;

-- finance.import_legacy_payments: an archived record is on record: never changed, never recorded again
CREATE OR REPLACE FUNCTION finance.import_legacy_payments(p_rows jsonb)
 RETURNS TABLE(rows integer, cleared integer, no_student integer, no_due integer, duplicates integer, duplicate_sample text, corrected integer, undated integer, matched integer, separate integer, taken_over integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_payref text; v_channel text; v_separate boolean; st people.student; ex finance.payment_reference;
        ph finance.payment_reference; gf record; rs record; v_purpose text;
        v_reason text := coalesce(nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), 'the old portal''s export names this payment');
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; nm int := 0; nsep int := 0; ntk int := 0;
        v_dups text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a legacy payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the payments are rows: matriculation number, session, amount (or blank for cleared in full)' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        v_session := btrim(coalesce(r->>'session', ''));
        IF v_matric = '' OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN CONTINUE; END IF;
        IF v_matric ~* '^mat(ric|no)' THEN CONTINUE; END IF;   -- a header row
        n := n + 1;

        -- V647: the payer's number resolved by the authoritative records — the matriculation number, an old one a correction
        -- replaced, the admission number, and (not for an applicant's payment) the JAMB registration or application number naming
        -- one student; a row the records give no student, or several, is held for the reconciliation instead of dropped
        v_purpose := finance.legacy_row_purpose(r);
        SELECT * INTO rs FROM people.resolve_student(v_matric, v_purpose <> 'APPLICANT');
        IF rs.student_id IS NULL THEN
            PERFORM finance.legacy_hold(r, v_matric, v_purpose, rs.identifier_type, rs.status, rs.candidates);
            nns := nns + 1; CONTINUE;
        END IF;
        SELECT * INTO st FROM people.student WHERE id = rs.student_id;
        v_sid := st.id;

        v_sem := finance.legacy_semester(coalesce(r->>'semester', r->>'sem'));

        -- what the money was for: the old portal's payment item when the file carries one (it is what it says);
        -- else the free-text Note, which is another purpose only when it names one
        v_item := finance.legacy_item_of(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', ''));   -- V498: a code is the item it names
        v_free := btrim(coalesce(r->>'note', ''));
        v_text := CASE WHEN v_item <> '' THEN v_item ELSE v_free END;
        v_gst := coalesce(finance.legacy_gst_type_of(v_text), '') = 'GST';
        v_other := NOT v_gst AND v_text <> '' AND v_text !~* '(school|tuition|semester fee|session fee)'
                   AND (v_item <> ''
                        OR v_text ~* '(^|[^a-z])(gst|gns|general stud|hostel|accommodation|transcript|library|deferment|transfer|wallet|acceptance|application|post-?utme|screening|medical|id card|convocation|late registration|clearance|siwes|certificate|verification|result|change of|add(-| )?drop|carry-?over|exam|fine|penalty|levy|dues|insurance|sports|development|laboratory|lab|studio|field|excursion|matriculation|thesis|project|supervision|bench|departmental|faculty)');
        v_slug := CASE WHEN v_gst THEN 'GST' WHEN v_other THEN left(regexp_replace(upper(v_text), '[^0-9A-Z]', '', 'g'), 20) END;

        v_key := replace(v_session, '/', '-');
        v_base0 := 'MOAUM-LEG-' || regexp_replace(v_matric, '[^0-9A-Z]', '', 'g') || '-' || v_key;      -- the whole-session school-fees reference
        v_base := v_base0 || CASE WHEN v_sem IS NOT NULL THEN '-S' || v_sem ELSE '' END;                -- this row's school-fees reference
        v_ref := v_base || CASE WHEN v_slug IS NOT NULL THEN '-' || v_slug ELSE '' END;

        -- the date the student paid, as the file gives it
        v_given := finance.legacy_date(coalesce(r->>'paidOn', r->>'paid_on', r->>'date'));
        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;

        -- the purpose as the ledger names it: the GST fee is one per session, and is what the GST desk counts
        v_tag := CASE WHEN v_gst THEN 'GST fee ' || v_session
                      ELSE (CASE WHEN v_other THEN v_text ELSE 'School fees' END) || ' (legacy)'
                           || CASE WHEN v_sem IS NOT NULL THEN ' · semester ' || v_sem ELSE '' END END;

        v_old_ref := btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', r->>'payref', ''));
        v_payref := nullif(upper(v_old_ref), '');
        v_channel := btrim(coalesce(r->>'channel', ''));
        v_note := coalesce(nullif(v_free, ''), 'Imported from the old portal')
                  || CASE WHEN v_channel <> '' AND v_channel !~* '^(old record|legacy)$' THEN ' · ' || v_channel ELSE '' END
                  || CASE WHEN v_old_ref <> '' THEN ' · old ref ' || v_old_ref ELSE '' END;
        v_separate := false;

        IF v_payref IS NOT NULL THEN
            -- V498: the old portal's payment number decides. Seen before: that payment again, never a second one
            -- V561: and a payment withdrawn because the bank never received it stays withdrawn when the export names it again
            IF EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = v_payref)
               OR EXISTS (SELECT 1 FROM finance.legacy_payref_withdrawn w WHERE w.payref = v_payref) THEN
                nd := nd + 1; v_dups := v_dups || v_payref;
                CONTINUE;
            END IF;
            -- a record already there for this key that this payment is (part of), recorded by an upload that did not keep the
            -- number: what the record holds beyond the payments already attached to it is this payment's amount (the same day
            -- first) — or, on a record the 15 Sep 2026 migration summed from several payments, has room for it. The same amount
            -- is within a naira: that migration kept whole naira (36,556.00 for the export's 36,555.80), as finance.fee_short reads
            SELECT x.* INTO ex FROM finance.payment_reference x
              LEFT JOIN LATERAL (SELECT count(*) AS n, coalesce(sum(coalesce(k.amount, x.amount)), 0) AS held
                                   FROM finance.legacy_payref k WHERE k.reference = x.reference) c ON true
             WHERE x.student_id = v_sid AND x.channel = 'Legacy'
               AND (x.reference = v_ref
                    OR (v_sem IS NULL AND v_slug IS NULL AND x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')))
               AND CASE WHEN v_amount IS NULL THEN c.n = 0
                        WHEN x.note ~ '^[2-9][0-9]* school-fees payment\(s\), migrated' THEN x.amount - c.held - v_amount > -1
                        ELSE abs(x.amount - c.held - v_amount) < 1 END
             ORDER BY (v_given IS NOT NULL AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date) DESC,
                      abs(x.amount - c.held - coalesce(v_amount, x.amount - c.held)), (x.reference = v_ref) DESC
             LIMIT 1;
            IF ex.id IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, ex.reference, coalesce(v_amount, ex.amount));
                -- a summed record keeps its day; one payment's record takes the day the file gives
                IF ex.archived_at IS NOT NULL THEN
                    NULL;   -- V670: an archived record keeps its day and note; its number is known now
                ELSIF v_given IS NOT NULL AND ex.note !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'
                   AND (ex.confirmed_at AT TIME ZONE 'Africa/Lagos')::date IS DISTINCT FROM (v_given AT TIME ZONE 'Africa/Lagos')::date THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given,
                           note = CASE WHEN note LIKE '%old ref %' THEN note ELSE v_note END
                     WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSIF ex.note NOT LIKE '%old ref %' AND ex.archived_at IS NULL THEN
                    UPDATE finance.payment_reference SET note = v_note WHERE id = ex.id;
                END IF;
                nm := nm + 1;
                CONTINUE;
            END IF;
            -- the key is held by another payment (one with its own number, or another amount): this one is its own record
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN
                v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                v_separate := true;
            END IF;
        ELSE
            -- a file without payment numbers, read as before: already on record, skip and report; the amount is never touched
            -- (a wrong date is put right)
            SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
            -- V670: the key held by a record archived for good of another amount: this payment is its own record beside it
            IF ex.id IS NOT NULL AND ex.archived_at IS NOT NULL AND v_amount IS NOT NULL AND abs(ex.amount - v_amount) >= 1 THEN
                v_ref := v_ref || '-A' || to_char(round(v_amount), 'FM999999999990');
                ex := NULL;
                SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
            END IF;
            IF ex.id IS NOT NULL THEN
                IF ex.channel = 'Legacy' AND ex.archived_at IS NULL AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
                   AND (v_amount IS NULL OR v_amount = ex.amount) THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSE
                    nd := nd + 1; v_dups := v_dups || v_ref;
                END IF;
                CONTINUE;
            END IF;

            -- V449: this row names no semester and no other item, and an earlier upload already put the same money on the ledger
            -- per semester (this reference with -S1, -S2 or -S3), for the same amount and, when the file gives one, the same day
            IF v_sem IS NULL AND v_slug IS NULL AND v_amount IS NOT NULL
               AND EXISTS (SELECT 1 FROM finance.payment_reference x
                            WHERE x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')
                              AND x.channel = 'Legacy' AND x.amount = v_amount
                              AND (v_given IS NULL OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date)) THEN
                nd := nd + 1; v_dups := v_dups || v_ref;
                CONTINUE;
            END IF;
        END IF;

        -- the same money already on the ledger as school fees from an upload that could not tell more — without this row's
        -- semester, or without its item: put the semester on it, or relabel it; one row, not two (never for a payment that is
        -- its own record beside another of the same key, and never a record that already carries a payment number)
        IF NOT v_separate AND v_amount IS NOT NULL AND (v_sem IS NOT NULL OR v_slug IS NOT NULL) THEN
            SELECT * INTO ex FROM finance.payment_reference x
             WHERE x.reference IN (v_base0, v_base) AND x.reference <> v_ref AND x.channel = 'Legacy'
               AND x.purpose LIKE 'School fees%' AND abs(x.amount - v_amount) < 1
               AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = x.reference)
             ORDER BY (x.reference = v_base) DESC LIMIT 1;
            IF ex.id IS NOT NULL AND ex.archived_at IS NOT NULL THEN
                nd := nd + 1; v_dups := v_dups || v_ref;   -- V670: the same money is on record, archived for review
                CONTINUE;
            END IF;
            IF ex.id IS NOT NULL THEN
                v_when := coalesce(v_given, ex.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, confirmed_at = v_when, expires_at = v_when,
                       note = CASE WHEN v_free <> '' OR v_old_ref <> '' THEN v_note ELSE note END
                 WHERE id = ex.id;
                IF v_payref IS NOT NULL THEN
                    INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, ex.amount);
                END IF;
                nfix := nfix + 1;
                CONTINUE;
            END IF;
        END IF;

        -- V502: the retired Payment History Upload recorded this payment under its number (as the reference, or the receipt) and
        -- no Old Fees History record has it: that record becomes the one this row makes — the item, the semester, the day paid,
        -- the session — so the payment is on record once. That door read every row as school fees whatever it was, without a
        -- semester, and dated a row it could not read with the day of the upload. Its ledger posting is let go (reversed and
        -- freed), so the sync posts the payment again under its item; a record something points at by its reference is left.
        IF v_payref IS NOT NULL THEN
            ph := NULL;
            SELECT x.* INTO ph FROM finance.payment_reference x
             WHERE x.student_id = v_sid AND x.reference NOT LIKE 'MOAUM-%' AND x.confirmed_at IS NOT NULL
               AND (upper(btrim(x.reference)) = v_payref OR upper(btrim(x.receipt_no)) = v_payref)
               AND NOT finance.payment_reference_linked(x.reference, x.id)
             ORDER BY (upper(btrim(x.reference)) = v_payref) DESC, x.reference
             LIMIT 1;
            IF ph.id IS NOT NULL AND ph.archived_at IS NOT NULL THEN
                nd := nd + 1; v_dups := v_dups || v_ref;   -- V670: recorded already, archived for review
                CONTINUE;
            END IF;
            IF ph.id IS NOT NULL THEN
                IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE (x.reference = v_ref OR x.receipt_no = 'LEG-' || v_ref) AND x.id <> ph.id) THEN
                    v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                END IF;
                SELECT * INTO gf FROM finance.gl_free_payment(ph.reference, ph.id, 'PAYMENT_CORRECTED',
                    'the payment ' || ph.reference || ' recorded by Payment History Upload is ' || v_tag || ' (' || v_ref || '): ' || v_reason);
                v_when := coalesce(v_given, ph.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, session = v_session,
                       amount = coalesce(v_amount, amount), confirmed_at = v_when, expires_at = v_when, channel = 'Legacy',
                       note = v_note || ' · first recorded by Payment History Upload as ' || ph.reference
                 WHERE id = ph.id;
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, coalesce(v_amount, ph.amount));
                INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action,
                                                           ledger_journal, reversal_journal, corrected_by, reason)
                VALUES (ph.id, ph.reference, v_ref, ph.purpose, v_tag, 'TAKEN_OVER', gf.journal, gf.reversal, v_actor, v_reason);
                ntk := ntk + 1;
                CONTINUE;
            END IF;
        END IF;

        IF v_amount IS NULL THEN
            -- the level the student was at in THAT session, unless the file says
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NULL OR v_level NOT IN (100, 200, 300, 400, 500, 600) THEN
                v_level := reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session);
            END IF;
            SELECT coalesce(sum(f.amount), 0) INTO v_amount
              FROM finance.fee_schedule f
              JOIN ref.programme p ON p.code = st.programme_code
             WHERE f.session = v_session AND f.ended_at IS NULL
               AND (f.level IS NULL OR f.level = v_level)
               AND (f.entry_mode IS NULL OR f.entry_mode = st.entry_mode)
               AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
               AND (f.programme_code IS NULL OR f.programme_code = st.programme_code)
               AND (v_sem IS NULL OR f.semester IS NULL OR f.semester = v_sem)
               AND CASE WHEN v_gst THEN f.item ~* '(gst|gns|general stud)'
                        WHEN v_other THEN f.item ILIKE '%' || v_text || '%'
                        ELSE f.item ILIKE 'school fee%' END;
            IF v_gst AND (v_amount IS NULL OR v_amount <= 0) THEN
                SELECT g.amount INTO v_amount FROM finance.gst_fee_for(v_sid, v_session) g WHERE g.stated;
            END IF;
        END IF;
        IF v_amount IS NULL OR v_amount <= 0 THEN nnd := nnd + 1; CONTINUE; END IF;

        v_when := v_given;
        IF v_when IS NULL THEN v_when := now(); nund := nund + 1; END IF;
        v_rcpt := 'LEG-' || v_ref;

        INSERT INTO finance.payment_reference
            (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (v_sid, v_session, v_ref, v_tag, v_amount, v_when, v_when, v_actor, 'Legacy', v_rcpt, v_note)
        ON CONFLICT (reference) DO NOTHING;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        IF v_cnt > 0 THEN
            nc := nc + 1;
            IF v_separate THEN nsep := nsep + 1; END IF;
            IF v_payref IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, v_amount);
            END IF;
            -- V647: paid under another number (a JAMB registration, application or admission number, an old matriculation number):
            -- the number kept beside the payment, which is the same payment, counted once
            IF upper(coalesce(st.matric_no, '')) <> v_matric THEN
                INSERT INTO finance.payment_identity (payment_id, original_identifier, original_identifier_type, resolved_student_id, resolved_matric_no,
                                                      match_method, source, batch_ref, recorded_by)
                SELECT pr.id, v_matric, rs.identifier_type, v_sid, st.matric_no, rs.method,
                       CASE WHEN nullif(current_setting('moaum.recon_batch', true), '') IS NULL THEN 'OLD_FEES_IMPORT' ELSE 'FEE_HISTORY_RECONCILIATION' END,
                       nullif(current_setting('moaum.recon_batch', true), ''), v_actor
                  FROM finance.payment_reference pr WHERE pr.reference = v_ref
                ON CONFLICT (payment_id) DO NOTHING;
            END IF;
            -- a row held before, recorded now
            UPDATE finance.legacy_payment_held h
               SET status = 'RECONCILED', payment_id = (SELECT pr.id FROM finance.payment_reference pr WHERE pr.reference = v_ref), reconciled_at = now(),
                   batch_ref = coalesce(nullif(current_setting('moaum.recon_batch', true), ''), h.batch_ref)
             WHERE h.row_key = coalesce('PAYREF:' || v_payref, 'ROW:' || md5(r::text)) AND h.status <> 'RECONCILED';
        ELSE
            nd := nd + 1; v_dups := v_dups || coalesce(v_payref, v_ref);
        END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund, nm, nsep, ntk;
END $function$;

-- finance.late_payment_applies: paid on time: payments that count
CREATE OR REPLACE FUNCTION finance.late_payment_applies(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT w.late_fee_enabled AND w.phase = 'LATE'
       AND coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                      WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
                        AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)), 0)
         < (SELECT coalesce(sum(c.amount), 0) FROM finance.charges_of(p_student, p_session, ARRAY['FEE']) c)
      FROM policy.window_state(policy.window_type_for(p_student, 'SCHOOL_FEES_PAYMENT'), p_session, NULL) w   -- V380: a CCE student's own window
$function$;

-- finance.legacy_duplicate_pairs: records twice: two that count
CREATE OR REPLACE FUNCTION finance.legacy_duplicate_pairs()
 RETURNS TABLE(duplicate_id uuid, duplicate_reference text, kept_reference text, student_id uuid, session text, amount numeric, confirmed_at timestamp with time zone, linked text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT DISTINCT ON (a.id) a.id, a.reference, b.reference, a.student_id, a.session, a.amount, a.confirmed_at,
           CASE WHEN EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = a.reference) THEN 'DEFERMENT_FEE'
                WHEN EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = a.reference) THEN 'REFUND'
                WHEN EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = a.id) THEN 'GST_RECONCILIATION'
           END
      FROM finance.payment_reference a
      JOIN finance.payment_reference b
        ON b.reference IN (a.reference || '-S1', a.reference || '-S2', a.reference || '-S3')
       AND b.student_id = a.student_id AND b.session = a.session
     WHERE a.channel = 'Legacy' AND b.channel = 'Legacy'
       AND a.reference LIKE 'MOAUM-LEG-%' AND a.purpose = 'School fees (legacy)'
       AND b.purpose LIKE 'School fees (legacy) _ semester _'
       AND a.amount = b.amount
       AND a.confirmed_at IS NOT NULL AND b.confirmed_at IS NOT NULL AND a.archived_at IS NULL AND b.archived_at IS NULL
       AND (a.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (b.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
     ORDER BY a.id, b.reference
$function$;

-- finance.legacy_gst_resolve: the GST payment held and the school-fees row relabelled: payments that count
CREATE OR REPLACE FUNCTION finance.legacy_gst_resolve(p_payment uuid, p_action text, p_student uuid, p_reason text)
 RETURNS finance.legacy_gst_reconciliation
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; i finance.legacy_gst_import; v_act text := upper(btrim(coalesce(p_action, ''))); v_other uuid; v_id uuid; v_ref text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is resolved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_PAYMENT_NOT_FOUND: no such old-portal payment' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment FOR UPDATE;
    SELECT * INTO i FROM finance.legacy_gst_import WHERE id = rc.import_id;
    IF rc.status = 'RECONCILED' THEN RAISE EXCEPTION 'LEGACY_ALREADY_RECONCILED: this payment is already on the ledger as %', (SELECT reference FROM finance.payment_reference WHERE id = rc.payment_reference_id) USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'LEGACY_REASON_REQUIRED: resolving a payment names its reason' USING ERRCODE = '23514'; END IF;

    IF v_act = 'MATCH' THEN
        IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: name the current student' USING ERRCODE = '23514'; END IF;
        -- the identifiers on the row must not point at somebody else: ownership is never moved by guesswork
        IF (p.matric_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = p.matric_no AND s.id <> p_student))
           OR (p.jamb_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.jamb_reg_no) = p.jamb_no AND s.id <> p_student)) THEN
            RAISE EXCEPTION 'LEGACY_IDENTIFIER_CONFLICT: the matriculation or JAMB number on the row belongs to another student' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'MATCHED', reason_code = NULL, reason = NULL, student_id = p_student, match_method = 'MANUAL', match_confidence = 'MANUAL',
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
        PERFORM finance.legacy_gst_validate_one(p_payment);
        -- the old id, once resolved by hand, is on the crosswalk for the next file
        IF p.source_student_id IS NOT NULL AND p.source_student_id !~ '^[0-9a-f]{8}-' THEN
            INSERT INTO finance.legacy_student_crosswalk (legacy_student_id, student_id, note, set_by)
            VALUES (upper(p.source_student_id), p_student, 'set when ' || coalesce(p.source_reference, p.source_transaction_id) || ' was resolved: ' || btrim(p_reason), v_actor)
            ON CONFLICT (legacy_student_id) DO NOTHING;
        END IF;
    ELSIF v_act = 'RECONCILE' THEN
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        IF rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW') THEN RAISE EXCEPTION 'LEGACY_STATE: a % payment is not reconciled by hand', lower(replace(rc.status, '_', ' ')) USING ERRCODE = '23514'; END IF;
        IF p.normalized_status <> 'SUCCESS' THEN RAISE EXCEPTION 'LEGACY_NOT_SUCCESSFUL: the old portal did not record this payment as successful; it cannot establish an entitlement' USING ERRCODE = '23514'; END IF;
        IF p.session IS NULL OR p.amount IS NULL OR p.amount <= 0 THEN RAISE EXCEPTION 'LEGACY_INCOMPLETE: the row needs a session and an amount' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                      AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.source_reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))) THEN
            RAISE EXCEPTION 'LEGACY_DUPLICATE: the student already holds a confirmed GST payment for %', p.session USING ERRCODE = '23514';
        END IF;
        v_ref := finance.legacy_gst_ledger_reference(p);
        IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN RAISE EXCEPTION 'LEGACY_DUPLICATE: a ledger row already carries the old-portal reference %', v_ref USING ERRCODE = '23514'; END IF;
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (rc.student_id, p.session, v_ref, 'GST fee ' || p.session, p.amount, coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), v_actor, 'Legacy', 'LEG-' || v_ref,
                'Old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', reconciled by hand under ' || i.reference || ': ' || btrim(p_reason))
        RETURNING id INTO v_id;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = NULL, reason = NULL, payment_reference_id = v_id, reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office,
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'RELABEL' THEN
        -- the money is already on the ledger as school fees from the old portal: it was for the GST fee
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        SELECT r.id INTO v_other FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%' AND r.amount = p.amount AND r.archived_at IS NULL
         ORDER BY abs(extract(epoch FROM (r.confirmed_at - coalesce(p.paid_at, r.confirmed_at)))) LIMIT 1;
        IF v_other IS NULL THEN RAISE EXCEPTION 'LEGACY_NOTHING_TO_RELABEL: no old-portal school-fees row of that amount is on the ledger for the student and session' USING ERRCODE = '23514'; END IF;
        UPDATE finance.payment_reference
           SET purpose = 'GST fee ' || p.session,
               note = coalesce(note || ' · ', '') || 'relabelled from school fees: old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', under ' || i.reference || ': ' || btrim(p_reason)
         WHERE id = v_other;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = 'RELABELLED', reason = 'the old-portal school-fees row was relabelled as the GST fee', payment_reference_id = v_other,
               reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office, resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'REJECT' THEN
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'REJECTED', reason_code = 'REJECTED_BY_OFFICER', reason = btrim(p_reason), resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSE
        RAISE EXCEPTION 'LEGACY_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    RETURN rc;
END $function$;

-- finance.legacy_gst_summary: GST payers: payments that count
CREATE OR REPLACE FUNCTION finance.legacy_gst_summary(p_import uuid, p_session text)
 RETURNS TABLE(legacy_rows bigint, successful bigint, failed bigint, gst_rows bigint, unprocessed bigint, matched bigint, reconciled bigint, requires_review bigint, duplicates bigint, rejected bigint, unmatched bigint, legacy_amount numeric, legacy_successful_amount numeric, reconciled_amount numeric, variance numeric, legacy_students bigint, reconciled_students bigint, entitled_students bigint)
 LANGUAGE sql
 STABLE
AS $function$
    WITH p AS (SELECT lp.*, rc.status, rc.student_id AS matched_student, rc.payment_reference_id
                 FROM finance.legacy_gst_payment lp JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = lp.id
                WHERE (p_import IS NULL OR lp.import_id = p_import) AND (p_session IS NULL OR lp.session = p_session)),
    gst AS (SELECT * FROM p WHERE finance.legacy_gst_type_of(payment_type) IS NOT NULL),
    led AS (SELECT coalesce(sum(r.amount), 0) AS amt, count(DISTINCT r.student_id) AS students FROM p JOIN finance.payment_reference r ON r.id = p.payment_reference_id WHERE p.status = 'RECONCILED')
    SELECT count(*), count(*) FILTER (WHERE normalized_status = 'SUCCESS'), count(*) FILTER (WHERE normalized_status <> 'SUCCESS'), (SELECT count(*) FROM gst),
           count(*) FILTER (WHERE status = 'UNPROCESSED'), count(*) FILTER (WHERE status = 'MATCHED'), count(*) FILTER (WHERE status = 'RECONCILED'), count(*) FILTER (WHERE status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE status = 'DUPLICATE'), count(*) FILTER (WHERE status = 'REJECTED'), count(*) FILTER (WHERE status = 'UNMATCHED'),
           coalesce(sum(amount), 0), coalesce(sum(amount) FILTER (WHERE normalized_status = 'SUCCESS' AND finance.legacy_gst_type_of(payment_type) IS NOT NULL), 0),
           led.amt, coalesce(sum(amount) FILTER (WHERE normalized_status = 'SUCCESS' AND finance.legacy_gst_type_of(payment_type) IS NOT NULL), 0) - led.amt,
           count(DISTINCT coalesce(matric_no, jamb_no, application_no, source_student_id)) FILTER (WHERE normalized_status = 'SUCCESS'),
           led.students,
           (SELECT count(DISTINCT r.student_id) FROM finance.payment_reference r WHERE r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND (p_session IS NULL OR r.session = p_session))
      FROM p CROSS JOIN led GROUP BY led.amt, led.students
    UNION ALL
    SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
           (SELECT count(DISTINCT r.student_id) FROM finance.payment_reference r WHERE r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND (p_session IS NULL OR r.session = p_session))
     WHERE NOT EXISTS (SELECT 1 FROM p)
$function$;

-- finance.legacy_gst_validate_one: the GST payment held and the school-fees row of the same money: payments that count
CREATE OR REPLACE FUNCTION finance.legacy_gst_validate_one(p_payment uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; f record; v_dup uuid; v_other uuid; v_code text; v_reason text; v_status text; v_fee numeric := NULL;
BEGIN
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    IF rc.student_id IS NULL OR rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE') THEN RETURN; END IF;
    IF rc.status = 'RECONCILED' THEN RETURN; END IF;
    v_status := 'MATCHED'; v_code := NULL; v_reason := NULL;
    IF p.normalized_status <> 'SUCCESS' THEN
        v_status := 'REJECTED';
        v_code := CASE p.normalized_status WHEN 'REFUNDED' THEN 'PAYMENT_REFUNDED' WHEN 'REVERSED' THEN 'PAYMENT_REVERSED' WHEN 'PENDING' THEN 'PAYMENT_PENDING' WHEN 'FAILED' THEN 'PAYMENT_FAILED' ELSE 'PAYMENT_STATUS_UNKNOWN' END;
        v_reason := 'the old portal recorded the payment as "' || coalesce(p.legacy_status, '—') || '"; only a successful payment establishes anything';
    ELSIF finance.legacy_gst_type_of(p.payment_type) IS NULL THEN
        v_status := 'REJECTED'; v_code := 'UNKNOWN_PAYMENT_TYPE';
        v_reason := 'the payment type "' || coalesce(p.payment_type, '—') || '" is not one the Bursary reads as the GST fee';
    ELSIF p.session IS NULL THEN
        v_status := 'REJECTED'; v_code := 'MISSING_SESSION'; v_reason := 'the row names no session the payment belongs to';
    ELSIF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p.session) THEN
        v_status := 'REJECTED'; v_code := 'INVALID_SESSION'; v_reason := 'the session ' || p.session || ' is not on the calendar';
    ELSIF p.amount IS NULL OR p.amount <= 0 THEN
        v_status := 'REJECTED'; v_code := 'MISSING_AMOUNT'; v_reason := 'the row carries no amount';
    ELSE
        -- an entitlement already on the ledger for this student and session: the new portal''s, or an earlier reconciliation''s
        SELECT r.id INTO v_dup FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.source_reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
         ORDER BY r.confirmed_at LIMIT 1;
        IF v_dup IS NOT NULL THEN
            v_status := 'DUPLICATE'; v_code := 'EXISTING_ENTITLEMENT';
            v_reason := 'the student already holds a confirmed GST payment for ' || p.session || ' on the ledger (' || (SELECT reference || ' · ' || coalesce(channel, '') FROM finance.payment_reference WHERE id = v_dup) || '); one entitlement stands, both histories are kept';
        ELSE
            SELECT * INTO f FROM finance.gst_fee_for(rc.student_id, p.session);
            IF f.stated THEN v_fee := f.amount; END IF;
            IF NOT f.stated THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'NO_FEE_FOR_SESSION';
                v_reason := 'no GST fee is stated for ' || p.session || ' for this student, so the amount cannot be judged; the Bursar states the fee of that session first';
            ELSIF p.amount < f.amount THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'PARTIAL_PAYMENT';
                v_reason := 'the old portal shows NGN ' || to_char(p.amount, 'FM999,999,990.00') || ' against a fee of NGN ' || to_char(f.amount, 'FM999,999,990.00') || ' for ' || p.session;
            ELSIF p.amount > f.amount THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'AMOUNT_ABOVE_FEE';
                v_reason := 'the old portal shows NGN ' || to_char(p.amount, 'FM999,999,990.00') || ' against a fee of NGN ' || to_char(f.amount, 'FM999,999,990.00') || ' for ' || p.session;
            END IF;
            -- the same money may already sit on the ledger as school fees from the Old Fees History import: an officer decides
            IF v_status = 'MATCHED' THEN
                SELECT r.id INTO v_other FROM finance.payment_reference r
                 WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%' AND r.archived_at IS NULL
                   AND r.amount = p.amount AND (p.paid_at IS NULL OR r.confirmed_at::date = p.paid_at::date)
                 LIMIT 1;
                IF v_other IS NOT NULL THEN
                    v_status := 'REQUIRES_REVIEW'; v_code := 'POSSIBLE_RELABEL';
                    v_reason := 'the same amount on the same day already sits on the ledger as school fees imported from the old portal (' || (SELECT reference FROM finance.payment_reference WHERE id = v_other) || '); relabel it as the GST fee, or record this payment separately';
                END IF;
            END IF;
        END IF;
    END IF;
    UPDATE finance.legacy_gst_reconciliation
       SET status = v_status, reason_code = v_code, reason = v_reason, fee_amount = coalesce(v_fee, fee_amount)
     WHERE payment_id = p_payment;
END $function$;

-- finance.legacy_mislabelled: records to put right: those that count
CREATE OR REPLACE FUNCTION finance.legacy_mislabelled()
 RETURNS TABLE(id uuid, reference text, student_id uuid, number text, name text, session text, amount numeric, paid_on date, stored_purpose text, item text, known boolean, target_reference text, target_purpose text, action text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS (
        -- Old Fees History records under a code, or an older importer's label (V498)
        SELECT p.*, regexp_replace(p.purpose, ' \(legacy\)( · semester [0-9])?$', '') AS text0,
               substring(p.purpose FROM ' · semester ([0-9])$')::int AS sem,
               substring(p.reference FROM '^(MOAUM-LEG-[0-9A-Z]+-[0-9]{4}-[0-9]{4})') AS base0, false AS door
          FROM finance.payment_reference p
         WHERE p.reference LIKE 'MOAUM-LEG-%' AND p.reference NOT LIKE 'MOAUM-LEG-GST-%' AND p.channel = 'Legacy' AND p.confirmed_at IS NOT NULL AND p.archived_at IS NULL
           AND p.purpose LIKE '% (legacy)%' AND p.purpose NOT LIKE 'School fees%' AND p.purpose NOT LIKE 'GST fee %'
        UNION ALL
        -- V502: the retired Payment History Upload's records under the old portal's item name or code ("SCHOOL FEES", "GST FEES",
        -- "10048") — not read as school fees by the fee gate; one that repeats another record (withdrawn as a double, by the
        -- same test finance.old_payment_doubles makes) is not relabelled
        SELECT p.*, btrim(p.purpose), NULL::int, NULL::text, true
          FROM finance.payment_reference p
         WHERE p.reference NOT LIKE 'MOAUM-%' AND p.confirmed_at IS NOT NULL AND p.archived_at IS NULL
           AND p.purpose NOT LIKE 'School fees%' AND p.purpose NOT LIKE 'GST fee %'
           AND NOT EXISTS (SELECT 1 FROM finance.payment_reference x
                            WHERE x.student_id = p.student_id AND x.session = p.session AND x.id <> p.id AND x.confirmed_at IS NOT NULL AND x.archived_at IS NULL
                              AND abs(x.amount - p.amount) < 1
                              AND ((x.reference LIKE 'MOAUM-LEG-%' AND x.channel = 'Legacy') OR (x.reference NOT LIKE 'MOAUM-%' AND x.reference < p.reference))
                              AND ((x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
                                   OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = finance.payref_day(p.reference)
                                   OR EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = upper(btrim(p.reference)) AND k.reference = x.reference)))),
    c AS (
        SELECT r.*, (r.text0 ~ '^[0-9]+$') AS coded,
               CASE WHEN r.text0 ~ '^[0-9]+$' THEN (SELECT k.description FROM finance.legacy_item_code k WHERE k.code = r.text0) ELSE r.text0 END AS item0
          FROM r WHERE r.base0 IS NOT NULL OR r.door),
    -- V502: what each item is, read once an item (some 90,000 records of a few dozen other items took 19 s read a record at a
    -- time on a live-sized copy: finance.legacy_gst_type_of matches the item against every pattern of the map)
    i AS MATERIALIZED (
        SELECT d.item0, coalesce(finance.legacy_gst_type_of(d.item0), '') = 'GST' AS gst,
               coalesce(finance.legacy_gst_type_of(d.item0), '') <> 'GST' AND d.item0 ~* '(school|tuition|semester fee|session fee)' AS school
          FROM (SELECT DISTINCT c.item0 FROM c WHERE c.item0 IS NOT NULL) d),
    k AS (
        SELECT c.*, coalesce(i.gst, false) AS gst, coalesce(i.school, false) AS school
          FROM c LEFT JOIN i ON i.item0 = c.item0),
    t AS (
        SELECT k.*,
               CASE WHEN k.item0 IS NULL THEN NULL
                    WHEN k.door THEN k.reference
                    ELSE k.base0 || CASE WHEN k.sem IS NOT NULL THEN '-S' || k.sem ELSE '' END
                         || CASE WHEN k.gst THEN '-GST' WHEN k.school THEN '' ELSE '-' || left(regexp_replace(upper(k.item0), '[^0-9A-Z]', '', 'g'), 20) END END AS target_ref,
               CASE WHEN k.item0 IS NULL THEN NULL
                    WHEN k.gst THEN 'GST fee ' || k.session
                    -- the retired door's own form for school fees (what it wrote when the file named no item)
                    WHEN k.door AND k.school THEN 'School fees ' || k.session
                    WHEN k.door THEN k.item0
                    ELSE (CASE WHEN k.school THEN 'School fees' ELSE k.item0 END) || ' (legacy)' || CASE WHEN k.sem IS NOT NULL THEN ' · semester ' || k.sem ELSE '' END END AS target_purpose
          FROM k WHERE k.coded OR k.gst OR k.school)
    SELECT t.id, t.reference, t.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, t.session, t.amount,
           (t.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, t.purpose, t.item0, t.item0 IS NOT NULL, t.target_ref, t.target_purpose,
           CASE WHEN t.item0 IS NULL THEN 'UNKNOWN_CODE'
                WHEN t.target_ref = t.reference THEN 'RELABEL'
                WHEN x.id IS NOT NULL AND abs(x.amount - t.amount) < 1
                     AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (t.confirmed_at AT TIME ZONE 'Africa/Lagos')::date THEN 'DOUBLE'
                -- V502: a record something points at keeps its reference: relabelled, not renamed
                WHEN x.id IS NULL AND NOT finance.payment_reference_linked(t.reference, t.id) THEN 'RENAME'
                ELSE 'RELABEL' END
      FROM t
      JOIN people.student s ON s.id = t.student_id
      LEFT JOIN finance.payment_reference x ON x.reference = t.target_ref AND x.id <> t.id
$function$;

-- finance.legacy_outstanding_payment_credit: an archived payment is not credited to the wallet
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_credit(p_ids uuid[], p_note text)
 RETURNS TABLE(batch_ref text, credited integer, amount numeric, skipped integer, skipped_why jsonb)
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ref text; w record; v_entry uuid; n int := 0; v_sum numeric := 0; nk int := 0; why jsonb := '[]'::jsonb; v_reason text; v_balance numeric;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTOR: payments are credited by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_OFFICE: verified outstanding fees payments are credited to the wallet by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF coalesce(array_length(p_ids, 1), 0) = 0 THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_NONE: tick the verified payments to credit' USING ERRCODE = '23514'; END IF;
    FOR w IN
        SELECT c.*, r.id AS pay_id, r.amount AS pay_amount, r.student_id AS pay_student, r.purpose AS pay_purpose, r.channel AS pay_channel, r.confirmed_at AS pay_confirmed, r.archived_at AS pay_archived,
               r.reference AS pay_reference, lp.payref, s.surname, s.other_names, s.matric_no, s.admission_no, s.status AS student_status, s.duplicate_of
          FROM finance.legacy_outstanding_payment c
          JOIN finance.payment_reference r ON r.id = c.payment_id
          JOIN people.student s ON s.id = c.student_id
          LEFT JOIN LATERAL (SELECT k.payref FROM finance.legacy_payref k WHERE k.reference = r.reference ORDER BY k.recorded_at LIMIT 1) lp ON true
         WHERE c.payment_id = ANY (p_ids)
         ORDER BY s.surname, s.other_names, r.reference
         FOR UPDATE OF c, r
    LOOP
        v_reason := CASE WHEN w.status = 'CREDITED' OR w.wallet_entry_id IS NOT NULL THEN 'already credited (' || coalesce(w.batch_ref, 'on the wallet') || ')'
                         WHEN w.status <> 'VERIFIED' THEN 'not verified (' || lower(w.status) || ')'
                         WHEN w.verified_by = who THEN 'verified by you: another Bursar officer credits it'
                         WHEN w.pay_archived IS NOT NULL THEN 'archived for review: it is settled on Archived payments first'
                         WHEN w.pay_channel <> 'Legacy' OR w.pay_purpose !~* '^outstanding' OR w.pay_confirmed IS NULL THEN 'no longer an old-portal OUTSTANDING FEES payment'
                         WHEN w.pay_student <> w.student_id THEN 'the payment now stands on another student: return it to the officer'
                         WHEN w.pay_amount <> w.amount THEN 'the amount changed since it was verified: return it to the officer'
                         WHEN w.duplicate_of IS NOT NULL THEN 'a duplicate record, merged into another'
                         WHEN w.student_status = 'DECEASED' THEN 'the student is recorded as deceased'
                         END;
        IF v_reason IS NOT NULL THEN
            nk := nk + 1;
            why := why || jsonb_build_object('id', w.payment_id, 'student', w.surname || ', ' || w.other_names, 'number', coalesce(w.matric_no, w.admission_no),
                                             'reference', w.pay_reference, 'why', v_reason);
            CONTINUE;
        END IF;
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || w.student_id::text));
        -- the batch number is drawn with the first credit, so a call that credits nothing uses none
        IF v_ref IS NULL THEN
            v_ref := 'LEGACY-OUTSTANDING/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.legacy_outstanding_batch_seq')::text, 6, '0');
        END IF;
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code, at)
        VALUES (w.student_id, w.session, 'CREDIT', w.amount, v_ref,
                'Old-portal OUTSTANDING FEES payment ' || w.pay_reference || coalesce(' (old payment ' || w.payref || ')', '') || ', ' || w.session
                || coalesce(' semester ' || substring(w.pay_purpose FROM 'semester ([0-9])'), '') || ', credited to the wallet · verified by '
                || coalesce(helpdesk.person_name(w.verified_by), w.verified_office) || ' · ' || v_ref
                || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
                'LEGACY_OUTSTANDING', now())
        RETURNING id INTO v_entry;
        UPDATE finance.legacy_outstanding_payment
           SET status = 'CREDITED', decided_by = who, decided_office = office, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''),
               batch_ref = v_ref, wallet_entry_id = v_entry
         WHERE id = w.id;
        n := n + 1; v_sum := v_sum + w.amount;
        BEGIN
            v_balance := finance.wallet_balance(w.student_id);
            PERFORM platform.tell_student(w.student_id, 'LEGACY_OUTSTANDING_CREDITED', NULL,
                jsonb_build_object('AMOUNT', 'NGN ' || to_char(w.amount, 'FM999,999,999,990.00'), 'SESSION', w.session, 'REFERENCE', w.pay_reference,
                                   'BALANCE', 'NGN ' || to_char(coalesce(v_balance, 0), 'FM999,999,999,990.00')),
                'legacy-outstanding:credited:' || w.payment_id::text);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'legacy outstanding fees %: the student could not be told (%)', w.pay_reference, SQLERRM;
        END;
    END LOOP;
    -- the ids that are no payment on the list at all are said too
    SELECT nk + count(*), why || coalesce(jsonb_agg(jsonb_build_object('id', x, 'student', '', 'number', '', 'reference', '', 'why', 'not verified (waiting)')), '[]'::jsonb)
      INTO nk, why
      FROM unnest(p_ids) x
     WHERE NOT EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment c WHERE c.payment_id = x);
    RETURN QUERY SELECT v_ref, n, v_sum, nk, why;
END $function$;

-- finance.legacy_outstanding_payment_decide: an archived payment is not decided here
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_decide(p_payment uuid, p_action text, p_reason text)
 RETURNS finance.legacy_outstanding_payment
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_action text := upper(btrim(coalesce(p_action, ''))); r finance.payment_reference; c finance.legacy_outstanding_payment; v_verifier uuid; v_name text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTOR: a payment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_OFFICE: an outstanding fees payment is rejected, returned or reopened by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('REJECT', 'RETURN', 'REOPEN') THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTION: reject, return to the officer or reopen' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_REASON: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;
    IF NOT FOUND OR r.channel <> 'Legacy' OR r.purpose !~* '^outstanding' OR r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_NOT_FOUND: no old-portal OUTSTANDING FEES payment %', p_payment USING ERRCODE = 'P0002';
    END IF;
    IF r.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_ARCHIVED: payment % is archived for review; it is settled on Archived payments first', r.reference USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM finance.legacy_outstanding_payment WHERE payment_id = p_payment FOR UPDATE;
    IF c.status = 'CREDITED' THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_CREDITED: payment % is on the student''s wallet (%); it is not decided again', r.reference, c.batch_ref USING ERRCODE = '23514';
    END IF;
    v_verifier := c.verified_by;
    IF v_action = 'RETURN' THEN
        IF c.status IS DISTINCT FROM 'VERIFIED' THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_STATE: only a verified payment waiting to be credited is returned to the officer' USING ERRCODE = '23514';
        END IF;
        IF c.verified_by = who THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_SAME_OFFICER: you verified payment %; another Bursar officer returns or credits it', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF v_action = 'REOPEN' THEN
        IF c.status IS DISTINCT FROM 'REJECTED' THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_STATE: only a rejected payment is reopened' USING ERRCODE = '23514';
        END IF;
    ELSIF c.status = 'REJECTED' THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_STATE: payment % is already rejected' , r.reference USING ERRCODE = '23514';
    END IF;
    -- returned and reopened both go back to the officer to verify again; rejected stays until reopened
    INSERT INTO finance.legacy_outstanding_payment AS x (payment_id, reference, student_id, session, amount, status, decided_by, decided_office, decided_at, decision_note)
    VALUES (r.id, r.reference, r.student_id, r.session, r.amount, CASE v_action WHEN 'REJECT' THEN 'REJECTED' ELSE 'RETURNED' END, who, office, now(), btrim(p_reason))
    ON CONFLICT (payment_id) DO UPDATE
       SET status = EXCLUDED.status, reference = EXCLUDED.reference, student_id = EXCLUDED.student_id, session = EXCLUDED.session, amount = EXCLUDED.amount,
           decided_by = EXCLUDED.decided_by, decided_office = EXCLUDED.decided_office, decided_at = EXCLUDED.decided_at, decision_note = EXCLUDED.decision_note,
           verified_by = NULL, verified_office = NULL, verified_at = NULL, verify_note = NULL
    RETURNING * INTO c;
    SELECT s.surname || ', ' || s.other_names INTO v_name FROM people.student s WHERE s.id = r.student_id;
    BEGIN
        IF v_verifier IS NOT NULL AND v_verifier <> who THEN
            PERFORM platform.tell_person(v_verifier, 'LEGACY_OUTSTANDING_DECIDED', NULL,
                jsonb_build_object('STUDENT', coalesce(v_name, 'the student'), 'REFERENCE', r.reference,
                                   'ACTION', CASE v_action WHEN 'REJECT' THEN 'rejected' ELSE 'returned to you' END,
                                   'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,999,990.00'), 'REASON', btrim(p_reason), 'BURSAR', coalesce(helpdesk.person_name(who), 'the Bursar')),
                'legacy-outstanding:decided:' || r.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        END IF;
        IF v_action = 'REJECT' THEN
            PERFORM platform.tell_student(r.student_id, 'LEGACY_OUTSTANDING_REJECTED', NULL,
                jsonb_build_object('AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,999,990.00'), 'SESSION', r.session, 'REFERENCE', r.reference),
                'legacy-outstanding:rejected:' || r.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'legacy outstanding fees %: the decision could not be told (%)', r.reference, SQLERRM;
    END;
    RETURN c;
END $function$;

-- finance.legacy_outstanding_payment_figures: outstanding fees payments: those that count
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_figures()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH p AS (
        SELECT r.id, r.student_id, r.session, r.amount, coalesce(c.status, 'WAITING') AS state, c.wallet_entry_id
          FROM finance.payment_reference r
          LEFT JOIN finance.legacy_outstanding_payment c ON c.payment_id = r.id
         WHERE r.channel = 'Legacy' AND r.purpose ~* '^outstanding' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL),
    used AS (
        SELECT coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded
          FROM finance.wallet_entry e WHERE e.source_code = 'LEGACY_OUTSTANDING' AND e.kind IN ('APPLIED', 'REFUND'))
    SELECT jsonb_build_object(
        'payments', (SELECT count(*) FROM p), 'amount', (SELECT coalesce(sum(amount), 0) FROM p), 'students', (SELECT count(DISTINCT student_id) FROM p),
        'waiting', (SELECT count(*) FROM p WHERE state = 'WAITING'), 'waitingAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'WAITING'),
        'returned', (SELECT count(*) FROM p WHERE state = 'RETURNED'), 'returnedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'RETURNED'),
        'verified', (SELECT count(*) FROM p WHERE state = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'VERIFIED'),
        'credited', (SELECT count(*) FROM p WHERE state = 'CREDITED'), 'creditedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'CREDITED'),
        'creditedStudents', (SELECT count(DISTINCT student_id) FROM p WHERE state = 'CREDITED'),
        'rejected', (SELECT count(*) FROM p WHERE state = 'REJECTED'), 'rejectedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'REJECTED'),
        'applied', (SELECT applied FROM used), 'refunded', (SELECT refunded FROM used),
        'sessions', (SELECT coalesce(jsonb_agg(x ORDER BY x.session DESC), '[]'::jsonb) FROM (
                        SELECT p.session, count(*) AS payments, sum(p.amount) AS amount, count(*) FILTER (WHERE p.state = 'CREDITED') AS credited,
                               coalesce(sum(p.amount) FILTER (WHERE p.state = 'CREDITED'), 0) AS "creditedAmount"
                          FROM p GROUP BY p.session) x),
        'batches', (SELECT coalesce(jsonb_agg(b ORDER BY b.credited_at DESC), '[]'::jsonb) FROM (
                        SELECT c.batch_ref AS ref, max(c.decided_at) AS credited_at, count(*) AS payments, sum(c.amount) AS amount,
                               helpdesk.person_name((array_agg(c.decided_by))[1]) AS credited_by, max(c.decided_office) AS office
                          FROM finance.legacy_outstanding_payment c WHERE c.status = 'CREDITED'
                         GROUP BY c.batch_ref ORDER BY max(c.decided_at) DESC LIMIT 50) b))
$function$;

-- finance.legacy_outstanding_payment_rows: outstanding fees payments: those that count
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_rows(p_status text, p_session text, p_q text, p_fac text, p_dept text, p_limit integer DEFAULT 500, p_student uuid DEFAULT NULL::uuid)
 RETURNS TABLE(payment_id uuid, reference text, old_reference text, student_id uuid, student text, matric_no text, jamb_reg_no text, admission_no text, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, current_level integer, student_status text, merged boolean, session text, semester integer, purpose text, amount numeric, paid_at timestamp with time zone, method text, note text, status text, due numeric, paid numeric, owed numeric, verified_by text, verified_office text, verified_at timestamp with time zone, verify_note text, decided_by text, decided_office text, decided_at timestamp with time zone, decision_note text, batch_ref text, wallet_reference text, credited_amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pay AS (
        SELECT r.*, coalesce(c.status, 'WAITING') AS state, c.verified_by AS v_by, c.verified_office AS v_office, c.verified_at AS v_at, c.verify_note AS v_note,
               c.decided_by AS d_by, c.decided_office AS d_office, c.decided_at AS d_at, c.decision_note AS d_note, c.batch_ref AS b_ref, c.wallet_entry_id AS w_id
          FROM finance.payment_reference r
          LEFT JOIN finance.legacy_outstanding_payment c ON c.payment_id = r.id
         WHERE r.channel = 'Legacy' AND r.purpose ~* '^outstanding' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND (p_student IS NULL OR r.student_id = p_student)
           AND (p_session IS NULL OR r.session = p_session)
           AND (p_status IS NULL OR coalesce(c.status, 'WAITING') = p_status
                OR (p_status = 'TO_VERIFY' AND coalesce(c.status, 'WAITING') IN ('WAITING', 'RETURNED')))),
    picked AS (
        SELECT pay.*, s.surname || ', ' || s.other_names AS s_name, s.matric_no AS s_matric, s.jamb_reg_no AS s_jamb, s.admission_no AS s_adm,
               s.programme_code AS s_prog, pr.name AS prog_name, pr.dept_code AS s_dept, d.name AS dept_name, pr.faculty_code AS s_fac, f.name AS fac_name,
               s.current_level AS s_level, s.status AS s_status, (s.duplicate_of IS NOT NULL) AS s_merged, lp.payref
          FROM pay
          JOIN people.student s ON s.id = pay.student_id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
          LEFT JOIN LATERAL (SELECT k.payref FROM finance.legacy_payref k WHERE k.reference = pay.reference ORDER BY k.recorded_at LIMIT 1) lp ON true
         WHERE (p_fac IS NULL OR pr.faculty_code = p_fac)
           AND (p_dept IS NULL OR pr.dept_code = p_dept)
           AND (p_q IS NULL OR btrim(p_q) = ''
                OR (s.surname || ' ' || s.other_names) ILIKE '%' || btrim(p_q) || '%'
                OR upper(coalesce(s.matric_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(s.jamb_reg_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(s.admission_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(pay.reference) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(lp.payref, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(pay.b_ref, '')) LIKE '%' || upper(btrim(p_q)) || '%')
         ORDER BY CASE pay.state WHEN 'VERIFIED' THEN 0 WHEN 'RETURNED' THEN 1 WHEN 'WAITING' THEN 2 WHEN 'REJECTED' THEN 3 ELSE 4 END,
                  pay.session DESC, s.surname, s.other_names, pay.reference
         LIMIT greatest(1, least(coalesce(p_limit, 500), 5000)))
    SELECT p.id, p.reference, p.payref, p.student_id, p.s_name, p.s_matric, p.s_jamb, p.s_adm, p.s_prog, p.prog_name, p.s_dept, p.dept_name, p.s_fac, p.fac_name,
           p.s_level, p.s_status, p.s_merged, p.session, substring(p.purpose FROM 'semester ([0-9])')::int, p.purpose, p.amount, p.confirmed_at,
           CASE WHEN p.note LIKE 'Imported from the old portal · %' THEN nullif(btrim(split_part(p.note, ' · ', 2)), '') END, p.note, p.state,
           pos.due, pos.paid, greatest(coalesce(pos.balance, 0), 0),
           helpdesk.person_name(p.v_by), p.v_office, p.v_at, p.v_note, helpdesk.person_name(p.d_by), p.d_office, p.d_at, p.d_note, p.b_ref,
           e.reference, e.amount
      FROM picked p
      LEFT JOIN LATERAL finance.position(p.student_id, p.session) pos ON true
      LEFT JOIN finance.wallet_entry e ON e.id = p.w_id
     ORDER BY CASE p.state WHEN 'VERIFIED' THEN 0 WHEN 'RETURNED' THEN 1 WHEN 'WAITING' THEN 2 WHEN 'REJECTED' THEN 3 ELSE 4 END,
              p.session DESC, p.s_name, p.reference
$function$;

-- finance.legacy_outstanding_payment_verify: outstanding fees payments: those that count
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_verify(p_ids uuid[], p_note text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        n int; v_sum numeric; p uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTOR: a payment is verified by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_verifies(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_OFFICE: an outstanding fees payment is verified by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    -- a payment nothing was done with, or one the Bursar returned to the officer; never one credited or rejected
    WITH cand AS (
        SELECT r.id, r.reference, r.student_id, r.session, r.amount
          FROM finance.payment_reference r
         WHERE r.id = ANY (p_ids) AND r.channel = 'Legacy' AND r.purpose ~* '^outstanding' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment c WHERE c.payment_id = r.id AND c.status <> 'RETURNED')
         FOR UPDATE OF r),
    done AS (
        INSERT INTO finance.legacy_outstanding_payment AS c (payment_id, reference, student_id, session, amount, status, verified_by, verified_office, verified_at, verify_note)
        SELECT cand.id, cand.reference, cand.student_id, cand.session, cand.amount, 'VERIFIED', who, office, now(), nullif(btrim(coalesce(p_note, '')), '')
          FROM cand
        ON CONFLICT (payment_id) DO UPDATE
           SET status = 'VERIFIED', reference = EXCLUDED.reference, student_id = EXCLUDED.student_id, session = EXCLUDED.session, amount = EXCLUDED.amount,
               verified_by = EXCLUDED.verified_by, verified_office = EXCLUDED.verified_office, verified_at = EXCLUDED.verified_at, verify_note = EXCLUDED.verify_note
         WHERE c.status = 'RETURNED'
        RETURNING c.amount)
    SELECT count(*), coalesce(sum(amount), 0) INTO n, v_sum FROM done;
    -- the Bursar told that verified payments wait to be credited (once a minute at most for each holder)
    IF n > 0 THEN
        FOR p IN SELECT * FROM finance.bursar_holders() LOOP
            BEGIN
                PERFORM platform.tell_person(p, 'LEGACY_OUTSTANDING_WAITING', NULL,
                    jsonb_build_object('PAYMENTS', n, 'AMOUNT', 'NGN ' || to_char(v_sum, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                    'legacy-outstanding:waiting:' || p::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'legacy outstanding fees: the Bursar could not be told (%)', SQLERRM;
            END;
        END LOOP;
    END IF;
    RETURN n;
END $function$;

-- finance.legacy_wallet_compute: the old e-wallet: payments that count
CREATE OR REPLACE FUNCTION finance.legacy_wallet_compute(p_student uuid DEFAULT NULL::uuid)
 RETURNS TABLE(students integer, with_balance integer, review integer, no_balance integer, posted integer, available numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE n_students int; n_with int; n_review int; n_none int; n_posted int; v_avail numeric;
BEGIN
    WITH legacy AS MATERIALIZED (
        SELECT pr.student_id, pr.amount, pr.confirmed_at, pr.session, pr.note, pr.reference,
               finance.legacy_wallet_is_topup(pr.purpose) AS is_topup,
               finance.legacy_wallet_method(pr.note) = 'E-Wallet' AS from_wallet
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.student_id IS NOT NULL
           AND (p_student IS NULL OR pr.student_id = p_student)
           AND (finance.legacy_wallet_is_topup(pr.purpose) OR finance.legacy_wallet_method(pr.note) = 'E-Wallet')),
    per AS (
        SELECT l.student_id,
               coalesce(sum(l.amount) FILTER (WHERE l.is_topup), 0) AS topups, count(*) FILTER (WHERE l.is_topup) AS topup_count,
               coalesce(sum(l.amount) FILTER (WHERE l.from_wallet AND NOT l.is_topup), 0) AS used, count(*) FILTER (WHERE l.from_wallet AND NOT l.is_topup) AS used_count,
               min(l.confirmed_at) FILTER (WHERE l.is_topup) AS first_topup_at, max(l.confirmed_at) FILTER (WHERE l.is_topup) AS last_topup_at,
               (array_agg(l.reference ORDER BY l.confirmed_at DESC) FILTER (WHERE l.is_topup))[1] AS last_topup_ref,
               (array_agg(l.session ORDER BY l.confirmed_at DESC) FILTER (WHERE l.is_topup))[1] AS session
          FROM legacy l GROUP BY l.student_id
        HAVING count(*) FILTER (WHERE l.is_topup) > 0),
    credited AS (   -- a credit already on the wallet (posted here, or by hand under the same source): the row reads POSTED
        SELECT e.student_id, e.id AS entry FROM finance.wallet_entry e WHERE e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET'),
    up AS (
        INSERT INTO finance.legacy_wallet AS w (student_id, topups, topup_count, used, used_count, first_topup_at, last_topup_at, last_topup_ref, session, available, status, reason_code, reason, computed_at, wallet_entry_id)
        SELECT p.student_id, p.topups, p.topup_count, p.used, p.used_count, p.first_topup_at, p.last_topup_at, p.last_topup_ref, p.session,
               CASE WHEN c.entry IS NOT NULL THEN greatest(p.topups - p.used, 0) WHEN p.used > p.topups THEN 0 ELSE p.topups - p.used END,
               CASE WHEN c.entry IS NOT NULL THEN 'POSTED' WHEN p.used > p.topups THEN 'REQUIRES_REVIEW' WHEN p.topups - p.used <= 0 THEN 'NO_BALANCE' ELSE 'COMPUTED' END,
               CASE WHEN c.entry IS NOT NULL THEN NULL WHEN p.used > p.topups THEN 'USED_EXCEEDS_TOPUPS' END,
               CASE WHEN c.entry IS NOT NULL THEN NULL WHEN p.used > p.topups THEN format('%s paid from the old wallet against %s topped up on file: the old wallet held money the export does not show', p.used, p.topups) END,
               now(), c.entry
          FROM per p LEFT JOIN credited c ON c.student_id = p.student_id
        ON CONFLICT (student_id) DO UPDATE SET
               topups = EXCLUDED.topups, topup_count = EXCLUDED.topup_count, used = EXCLUDED.used, used_count = EXCLUDED.used_count,
               first_topup_at = EXCLUDED.first_topup_at, last_topup_at = EXCLUDED.last_topup_at, last_topup_ref = EXCLUDED.last_topup_ref, session = EXCLUDED.session,
               computed_at = now(),
               -- the old portal's own statement governs the balance where the Bursary holds it
               available = CASE WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.available
                                WHEN w.stated_balance IS NOT NULL THEN greatest(w.stated_balance, 0)
                                ELSE EXCLUDED.available END,
               wallet_entry_id = coalesce(w.wallet_entry_id, EXCLUDED.wallet_entry_id),
               status = CASE WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.status
                             WHEN EXCLUDED.wallet_entry_id IS NOT NULL THEN 'POSTED'
                             WHEN w.stated_balance IS NOT NULL THEN CASE WHEN w.stated_balance > 0 THEN CASE WHEN w.status = 'VERIFIED' AND (w.topups, w.used) = (EXCLUDED.topups, EXCLUDED.used) THEN 'VERIFIED' ELSE 'COMPUTED' END ELSE 'NO_BALANCE' END
                             WHEN w.status = 'VERIFIED' AND (w.topups, w.used) = (EXCLUDED.topups, EXCLUDED.used) THEN 'VERIFIED'
                             ELSE EXCLUDED.status END,
               reason_code = CASE WHEN w.status = 'POSTED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'CHANGED_AFTER_POSTING'
                                  WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.reason_code
                                  WHEN w.status = 'VERIFIED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'CHANGED_AFTER_VERIFICATION'
                                  WHEN w.stated_balance IS NOT NULL AND w.stated_balance <> EXCLUDED.available THEN 'STATEMENT_DIFFERS'
                                  ELSE EXCLUDED.reason_code END,
               reason = CASE WHEN w.status = 'POSTED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used)
                                  THEN format('the imported payments changed after the posting (top-ups %s, used %s now)', EXCLUDED.topups, EXCLUDED.used)
                             WHEN w.status IN ('POSTED', 'REJECTED', 'FROZEN') THEN w.reason
                             WHEN w.status = 'VERIFIED' AND (w.topups, w.used) <> (EXCLUDED.topups, EXCLUDED.used) THEN 'the imported payments changed after the verification; verify again'
                             WHEN w.stated_balance IS NOT NULL AND w.stated_balance <> EXCLUDED.available
                                  THEN format('the old portal''s statement says %s; the imported payments leave %s', w.stated_balance, EXCLUDED.available)
                             ELSE EXCLUDED.reason END
        RETURNING w.status, w.available)
    SELECT count(*), count(*) FILTER (WHERE u.status IN ('COMPUTED', 'VERIFIED')), count(*) FILTER (WHERE u.status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE u.status = 'NO_BALANCE'), count(*) FILTER (WHERE u.status = 'POSTED'), coalesce(sum(u.available) FILTER (WHERE u.status IN ('COMPUTED', 'VERIFIED')), 0)
      INTO n_students, n_with, n_review, n_none, n_posted, v_avail
      FROM up u;
    RETURN QUERY SELECT n_students, n_with, n_review, n_none, n_posted, v_avail;
END $function$;

-- finance.legacy_wallet_figures: the old e-wallet: payments that count
CREATE OR REPLACE FUNCTION finance.legacy_wallet_figures()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (SELECT * FROM finance.legacy_wallet),
    applied AS (SELECT coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded,
                       coalesce(sum(e.amount) FILTER (WHERE e.kind = 'CREDIT'), 0) AS credited
                  FROM finance.wallet_entry e WHERE e.source_code = 'LEGACY_WALLET'),
    orphan AS (   -- paid from the old wallet with no top-up on file
        SELECT count(DISTINCT pr.student_id) AS students, coalesce(sum(pr.amount), 0) AS amount
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND finance.legacy_wallet_method(pr.note) = 'E-Wallet' AND NOT finance.legacy_wallet_is_topup(pr.purpose)
           AND NOT EXISTS (SELECT 1 FROM finance.legacy_wallet lw WHERE lw.student_id = pr.student_id AND lw.topup_count > 0))
    SELECT jsonb_build_object(
        'students', (SELECT count(*) FROM w),
        'topups', (SELECT coalesce(sum(topups), 0) FROM w), 'topupCount', (SELECT coalesce(sum(topup_count), 0) FROM w),
        'used', (SELECT coalesce(sum(used), 0) FROM w),
        'computed', (SELECT count(*) FROM w WHERE status = 'COMPUTED'), 'computedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'COMPUTED'),
        'verified', (SELECT count(*) FROM w WHERE status = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'VERIFIED'),
        'returned', (SELECT count(*) FROM w WHERE status = 'RETURNED'), 'returnedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'RETURNED'),
        'posted', (SELECT count(*) FROM w WHERE status = 'POSTED'), 'postedAmount', (SELECT credited FROM applied),
        'applied', (SELECT applied FROM applied), 'refunded', (SELECT refunded FROM applied),
        'remaining', (SELECT credited - applied - refunded FROM applied),
        'review', (SELECT count(*) FROM w WHERE status = 'REQUIRES_REVIEW'), 'reviewUsed', (SELECT coalesce(sum(used - topups), 0) FROM w WHERE status = 'REQUIRES_REVIEW'),
        'noBalance', (SELECT count(*) FROM w WHERE status = 'NO_BALANCE'),
        'rejected', (SELECT count(*) FROM w WHERE status = 'REJECTED'), 'frozen', (SELECT count(*) FROM w WHERE status = 'FROZEN'),
        'stated', (SELECT count(*) FROM w WHERE stated_balance IS NOT NULL), 'differs', (SELECT count(*) FROM w WHERE reason_code = 'STATEMENT_DIFFERS'),
        'changed', (SELECT count(*) FROM w WHERE reason_code IN ('CHANGED_AFTER_POSTING', 'CHANGED_AFTER_VERIFICATION')),
        'orphanStudents', (SELECT students FROM orphan), 'orphanAmount', (SELECT amount FROM orphan),
        'lastComputed', (SELECT max(computed_at) FROM w),
        'batches', (SELECT coalesce(json_agg(b ORDER BY b.posted_at DESC), '[]'::json)::jsonb FROM (
                        SELECT b.ref, b.posted_at, b.students, b.amount, b.skipped, helpdesk.person_name(b.posted_by) AS posted_by, b.office FROM finance.legacy_wallet_batch b ORDER BY b.posted_at DESC LIMIT 50) b))
$function$;

-- finance.not_received_refusal: an archived payment is settled on Archived payments
CREATE OR REPLACE FUNCTION finance.not_received_refusal(p_payment uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE
             WHEN r.id IS NULL THEN 'PAY_NOT_RECEIVED_NO_RECORD'
             WHEN r.archived_at IS NOT NULL THEN 'PAY_NOT_RECEIVED_ARCHIVED'
             WHEN r.channel IS DISTINCT FROM 'Legacy' OR r.reference NOT LIKE 'MOAUM-LEG-%' OR r.confirmed_at IS NULL THEN 'PAY_NOT_RECEIVED_NOT_OLD_PORTAL'
             WHEN (SELECT count(*) FROM finance.legacy_payref k WHERE k.reference = r.reference) > 1
                  OR r.note ~ '^[2-9][0-9]* school-fees payment\(s\), migrated' THEN 'PAY_NOT_RECEIVED_SUMMED'
             WHEN finance.payment_reference_linked(r.reference, r.id) THEN 'PAY_NOT_RECEIVED_LINKED'
             WHEN EXISTS (SELECT 1 FROM finance.payment_swap w WHERE w.reference = r.reference AND w.status IN ('PENDING_APPROVAL', 'COMPLETED')) THEN 'PAY_NOT_RECEIVED_SWAPPED'
             WHEN r.purpose LIKE 'School fees%' AND EXISTS (SELECT 1 FROM finance.overpayment_settled(r.student_id, r.session)) THEN 'PAY_NOT_RECEIVED_DECIDED'
           END
      FROM (SELECT 1) one LEFT JOIN finance.payment_reference r ON r.id = p_payment
$function$;

-- finance.old_fees_reconciliation: old fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.old_fees_reconciliation(p_session text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, faculty_code text, level integer, due numeric, paid numeric, paid_old_s1 numeric, paid_old_s2 numeric, paid_old_session numeric, paid_payment_history numeric, paid_portal numeric, old_payments integer, difference numeric, state text, carried_in numeric, settled numeric, decision text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pay AS MATERIALIZED (
        SELECT r.student_id,
               sum(r.amount) AS paid,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 1'), 0) AS s1,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 2'), 0) AS s2,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose NOT LIKE '% semester _'), 0) AS whole,
               coalesce(sum(r.amount) FILTER (WHERE r.reference NOT LIKE 'MOAUM-%'), 0) AS hist,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-%' AND r.reference NOT LIKE 'MOAUM-LEG-%' AND r.channel IS DISTINCT FROM 'CARRIED'), 0) AS portal,
               coalesce(sum(r.amount) FILTER (WHERE r.channel = 'CARRIED'), 0) AS carried,
               count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%')::int AS old_n
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id
        HAVING count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%') > 0),
    ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c),
    dec AS MATERIALIZED (
        SELECT d.student_id, sum(d.amount) AS settled, string_agg(d.decision, ', ' ORDER BY d.decision) AS decision
          FROM finance.overpayment_decision d
          LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
         WHERE d.session = p_session AND d.superseded_at IS NULL AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
         GROUP BY d.student_id)
    SELECT p.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session),
           coalesce(ch.total, 0), p.paid, p.s1, p.s2, p.whole, p.hist, p.portal, p.old_n, p.paid - coalesce(ch.total, 0),
           CASE WHEN coalesce(ch.total, 0) <= 0 THEN 'NO_FEE_STATED'
                WHEN finance.fee_short(ch.total, p.paid) THEN 'UNDER'
                WHEN p.paid - ch.total >= 1 AND p.paid - ch.total - coalesce(dec.settled, 0) < 1 THEN 'OVER_SETTLED'
                WHEN p.paid - ch.total >= 1 THEN 'OVER'
                ELSE 'MATCHED' END,
           p.carried, coalesce(dec.settled, 0), dec.decision
      FROM pay p
      JOIN people.student s ON s.id = p.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ch ON ch.student_id = p.student_id
      LEFT JOIN dec ON dec.student_id = p.student_id
$function$;

-- finance.old_payment_doubles: doubles: records that count
CREATE OR REPLACE FUNCTION finance.old_payment_doubles()
 RETURNS TABLE(double_id uuid, double_reference text, double_kind text, kept_reference text, kept_kind text, student_id uuid, number text, name text, session text, amount numeric, paid_on date, purpose text, kept_purpose text, linked text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT o.id, o.reference, o.kind, k.reference, k.kind, o.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names,
           o.session, o.amount, (o.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, o.purpose, k.purpose,
           CASE WHEN EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = o.reference) THEN 'DEFERMENT_FEE'
                WHEN EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = o.reference) THEN 'REFUND'
                WHEN EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = o.id) THEN 'GST_RECONCILIATION'
           END
      FROM (
            -- the retired Payment History Upload's records
            SELECT r.*, 'PAYMENT_HISTORY'::text AS kind FROM finance.payment_reference r
             WHERE r.reference NOT LIKE 'MOAUM-%' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
            UNION ALL
            -- numbered whole-session school-fees records (a per-semester record of the same key may stand for them)
            SELECT r.*, 'WHOLE_SESSION'::text FROM finance.payment_reference r
             WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.reference NOT LIKE 'MOAUM-LEG-GST-%' AND r.channel = 'Legacy'
               AND r.purpose = 'School fees (legacy)' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
               AND EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.reference = r.reference)
            UNION ALL
            -- Old Fees History school-fees records that carry no payment number
            SELECT r.*, 'UNNUMBERED'::text FROM finance.payment_reference r
             WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.reference NOT LIKE 'MOAUM-LEG-GST-%' AND r.channel = 'Legacy'
               AND r.purpose LIKE 'School fees%' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
               AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.reference = r.reference)) o
      JOIN people.student s ON s.id = o.student_id
      CROSS JOIN LATERAL (
            SELECT x.reference, x.purpose,
                   CASE WHEN x.reference LIKE 'MOAUM-LEG-%' THEN 'OLD_FEES_HISTORY' ELSE 'PAYMENT_HISTORY' END AS kind
              FROM finance.payment_reference x
             WHERE x.student_id = o.student_id AND x.session = o.session AND x.id <> o.id AND x.confirmed_at IS NOT NULL AND x.archived_at IS NULL
               AND ((x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (o.confirmed_at AT TIME ZONE 'Africa/Lagos')::date
                    -- the retired door dated a row it could not read the date of with the day of the upload; the old portal's
                    -- payment number carries the day paid (PR202610077052390: 7 Oct 2026), and names the payment outright
                    OR (o.kind = 'PAYMENT_HISTORY' AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = finance.payref_day(o.reference))
                    OR (o.kind = 'PAYMENT_HISTORY' AND EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.payref = upper(btrim(o.reference)) AND p.reference = x.reference)))
               AND CASE WHEN o.kind = 'PAYMENT_HISTORY'
                        -- what the retired door wrote repeats an Old Fees History record, or an earlier copy of its own
                        THEN abs(x.amount - o.amount) < 1
                             AND ((x.reference LIKE 'MOAUM-LEG-%' AND x.channel = 'Legacy') OR (x.reference NOT LIKE 'MOAUM-%' AND x.reference < o.reference))
                        -- a numbered whole-session record repeats the per-semester record of its own key that has no number
                        WHEN o.kind = 'WHOLE_SESSION'
                        THEN x.reference IN (o.reference || '-S1', o.reference || '-S2', o.reference || '-S3') AND x.channel = 'Legacy'
                             AND abs(x.amount - o.amount) < 1
                             AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref p WHERE p.reference = x.reference)
                        -- a record without a number repeats a payment the export numbered (its part of a summed record counts) —
                        -- not the per-semester record a numbered whole-session record of its key repeats (that one stays)
                        ELSE x.reference LIKE 'MOAUM-LEG-%' AND x.channel = 'Legacy' AND x.purpose LIKE 'School fees%'
                             AND NOT (o.reference ~ '-S[123]$' AND x.reference = regexp_replace(o.reference, '-S[123]$', ''))
                             AND EXISTS (SELECT 1 FROM finance.legacy_payref p
                                          WHERE p.reference = x.reference AND abs(coalesce(p.amount, x.amount) - o.amount) < 1) END
             ORDER BY (x.reference LIKE 'MOAUM-LEG-%') DESC, x.reference
             LIMIT 1) k
$function$;

-- finance.overpaid: overpaid: payments that count
CREATE OR REPLACE FUNCTION finance.overpaid(p_session text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, faculty_code text, level integer, due numeric, paid numeric, excess numeric, decision text, decided numeric, reference text, to_session text, decided_at timestamp with time zone, refund_state text, old_portal boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c WHERE c.total > 0),
    pay AS MATERIALIZED (SELECT p.student_id, p.total FROM finance.session_payments(p_session) p),
    old AS MATERIALIZED (
        SELECT DISTINCT r.student_id FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND (r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%'))
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session),
           ch.total, pay.total, pay.total - ch.total,
           d.decision, d.amount, d.reference, d.to_session, d.decided_at, d.refund_state, old.student_id IS NOT NULL
      FROM ch
      JOIN pay ON pay.student_id = ch.student_id AND pay.total - ch.total >= 1
      JOIN people.student s ON s.id = ch.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN old ON old.student_id = ch.student_id
      LEFT JOIN LATERAL finance.overpayment_settled(ch.student_id, p_session) d ON true
$function$;

-- finance.payment_history_left: what the retired upload recorded alone: records that count
CREATE OR REPLACE FUNCTION finance.payment_history_left()
 RETURNS TABLE(id uuid, reference text, student_id uuid, number text, name text, session text, amount numeric, paid_on date, number_day date, purpose text, counts_as text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH d AS MATERIALIZED (SELECT x.double_id FROM finance.old_payment_doubles() x WHERE x.double_kind = 'PAYMENT_HISTORY')
    SELECT p.id, p.reference, p.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.session, p.amount,
           (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, finance.payref_day(p.reference), p.purpose,
           CASE WHEN p.purpose LIKE 'School fees%' THEN 'SCHOOL_FEES' WHEN p.purpose LIKE 'GST fee %' THEN 'GST' ELSE 'OTHER' END
      FROM finance.payment_reference p
      JOIN people.student s ON s.id = p.student_id
     WHERE p.reference NOT LIKE 'MOAUM-%' AND p.confirmed_at IS NOT NULL AND p.archived_at IS NULL
       AND p.id NOT IN (SELECT d.double_id FROM d)
$function$;

-- finance.payment_position: a student's school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.payment_position(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(payable numeric, paid numeric, outstanding numeric, status text, last_paid_at timestamp with time zone, last_reference text, last_channel text, payments integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH due AS (
        SELECT finance.due_for_semester(p_student, p_session, 3) AS total,
               CASE WHEN p_semester IS NULL OR p_semester <= 1 THEN 0 ELSE finance.due_for_semester(p_student, p_session, p_semester - 1) END AS before,
               CASE WHEN p_semester IS NULL THEN finance.due_for_semester(p_student, p_session, 3) ELSE finance.due_for_semester(p_student, p_session, p_semester) END AS upto
    ),
    pay AS (
        SELECT coalesce(sum(r.amount), 0) AS total, count(*)::int AS n
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
    ),
    last AS (
        SELECT r.confirmed_at, r.reference, r.channel
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.confirmed_at DESC, r.reference DESC LIMIT 1   -- V537: of two confirmed at once, the later reference
    ),
    pos AS (
        SELECT greatest(due.upto - due.before, 0) AS payable,
               -- the session's payments cover the earlier semesters first; what is left applies to this one
               least(greatest(pay.total - due.before, 0), greatest(due.upto - due.before, 0)) AS applied,
               pay.total AS paid_all, pay.n
          FROM due, pay
    )
    SELECT pos.payable,
           CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END,
           finance.fee_owed(pos.payable, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END),
           CASE WHEN pos.payable = 0 THEN 'NO_CHARGE'
                WHEN NOT finance.fee_short(pos.payable, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) THEN 'FULLY_PAID'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           last.confirmed_at, last.reference, last.channel, pos.n
      FROM pos LEFT JOIN last ON true;
$function$;

-- finance.payment_reallocation_check: an archived payment is not corrected here
CREATE OR REPLACE FUNCTION finance.payment_reallocation_check(p_payment uuid, p_code text, p_session text, p_semester integer, p_ignore uuid DEFAULT NULL::uuid, p_restore text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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
    IF r.archived_at IS NOT NULL THEN
        refusals := refusals || ('REALLOC_ARCHIVED: the payment is archived for review ('
            || coalesce((SELECT a.archive_ref FROM finance.payment_archive a WHERE a.payment_id = r.id AND a.state <> 'RECONCILED' LIMIT 1), 'archived')
            || '); it is settled on Archived payments first');
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
END $function$;

-- finance.payment_swap_check: an archived payment is moved only by the archive's own proposal
CREATE OR REPLACE FUNCTION finance.payment_swap_check(p_payment uuid, p_to uuid, p_ignore_swap uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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
                                      'kind', v_kind, 'outstandingStatus', CASE WHEN v_kind = 'OUTSTANDING_FEES' THEN coalesce(lop.status, 'WAITING') END),
        'from', jsonb_build_object('id', f.id, 'matricNo', f.matric_no, 'name', f.surname || ', ' || f.other_names),
        'to', CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object('id', t.id, 'matricNo', t.matric_no, 'name', t.surname || ', ' || t.other_names) END);
END $function$;

-- finance.payment_swap_outstanding: outstanding fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.payment_swap_outstanding(p_student uuid, p_session text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.channel = 'Legacy' AND r.purpose ~* '^outstanding'
$function$;

-- finance.payment_term: the payments before this one: those that count
CREATE OR REPLACE FUNCTION finance.payment_term(p_ref uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE r record; sem1 numeric; total numeric; prior numeric; tol numeric := 1;
BEGIN
    SELECT pr.student_id, pr.session, pr.amount, pr.purpose, pr.confirmed_at, pr.generated_at
      INTO r FROM finance.payment_reference pr WHERE pr.id = p_ref;
    IF r.student_id IS NULL OR coalesce(r.purpose, '') NOT ILIKE 'School fees%' THEN
        RETURN NULL;                                  -- not a school-fees payment (e.g. acceptance)
    END IF;

    -- a legacy purpose that already names the semester is authoritative
    IF r.purpose ~* 'semester\s*1' THEN RETURN 'First Semester'; END IF;
    IF r.purpose ~* 'semester\s*2' THEN RETURN 'Second Semester'; END IF;
    IF r.purpose ~* 'semester\s*3' THEN RETURN 'Third Semester'; END IF;

    sem1  := coalesce(finance.due_for_semester(r.student_id, r.session, 1), 0);
    total := coalesce((SELECT due FROM finance.position(r.student_id, r.session)), 0);

    -- confirmed school-fees paid before this one (ordered by when it confirmed, then minted)
    SELECT coalesce(sum(pr2.amount), 0) INTO prior
      FROM finance.payment_reference pr2
     WHERE pr2.student_id = r.student_id AND pr2.session = r.session
       AND pr2.purpose ILIKE 'School fees%' AND pr2.confirmed_at IS NOT NULL AND pr2.archived_at IS NULL AND pr2.id <> p_ref
       AND (pr2.confirmed_at, pr2.generated_at, pr2.id)
           < (coalesce(r.confirmed_at, r.generated_at), r.generated_at, p_ref);

    IF prior <= tol AND r.amount >= total - tol THEN RETURN 'Full session'; END IF;
    IF prior + r.amount <= sem1 + tol THEN RETURN 'First Semester'; END IF;
    IF prior >= sem1 - tol THEN RETURN 'Second Semester'; END IF;
    RETURN 'Full session';                            -- one payment spanning both semesters
END $function$;

-- finance.payments_breakdown: payments: those that count
CREATE OR REPLACE FUNCTION finance.payments_breakdown(p_session text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text, p_dept text DEFAULT NULL::text, p_programme text DEFAULT NULL::text, p_level integer DEFAULT NULL::integer, p_category text DEFAULT NULL::text, p_channel text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(dim text, label text, cnt bigint, total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    -- V573: each purpose's category worked out once (some eighty), not once a confirmed payment (some 264,000)
    WITH cat AS MATERIALIZED (SELECT x.purpose, finance.payment_category(x.purpose) AS category
                                FROM (SELECT DISTINCT r.purpose FROM finance.payment_reference r WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL) x)
    -- V573: the matches totalled once by category and faculty (a few hundred groups), each list summed from those
    , base AS MATERIALIZED (
        SELECT coalesce(cat.category, 'Other') AS category, f.name AS faculty, count(*) AS n, sum(r.amount) AS amount
          FROM finance.payment_reference r
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN cat ON cat.purpose = r.purpose
         WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND (p_session   IS NULL OR r.session = p_session)
           AND (p_faculty   IS NULL OR f.code = p_faculty)
           AND (p_dept      IS NULL OR d.code = p_dept)
           AND (p_programme IS NULL OR p.code = p_programme)
           AND (p_level     IS NULL OR s.current_level = p_level)
           AND (p_channel   IS NULL OR r.channel = p_channel)
           AND (p_category  IS NULL OR coalesce(cat.category, 'Other') = p_category)
           AND (p_from      IS NULL OR r.confirmed_at::date >= p_from)
           AND (p_to        IS NULL OR r.confirmed_at::date <= p_to)
         GROUP BY 1, 2)
    SELECT 'category', category, sum(n)::bigint, coalesce(sum(amount), 0) FROM base GROUP BY category
    UNION ALL
    SELECT 'faculty', faculty, sum(n)::bigint, coalesce(sum(amount), 0) FROM base GROUP BY faculty
    ORDER BY 1, 4 DESC
$function$;

-- finance.payments_query: payments: those that count
CREATE OR REPLACE FUNCTION finance.payments_query(p_session text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text, p_dept text DEFAULT NULL::text, p_programme text DEFAULT NULL::text, p_level integer DEFAULT NULL::integer, p_category text DEFAULT NULL::text, p_channel text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 500)
 RETURNS TABLE(reference text, confirmed_at timestamp with time zone, payer text, number text, programme_code text, programme text, dept_code text, dept text, faculty_code text, faculty text, level integer, purpose text, category text, channel text, amount numeric, receipt_no text, session text, match_count bigint, match_total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    -- V573: each purpose's category worked out once (some eighty), not once a confirmed payment (some 264,000)
    WITH cat AS MATERIALIZED (SELECT x.purpose, finance.payment_category(x.purpose) AS category
                                FROM (SELECT DISTINCT r.purpose FROM finance.payment_reference r WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL) x)
    -- V573: the payments matching, read narrow (reference, time, amount); the count and the total from them, and only the page's
    -- rows (500 by default) joined to the student and the programme — not every match built in full and sorted for the newest
    , hit AS MATERIALIZED (
        SELECT r.reference, r.confirmed_at, r.amount, coalesce(cat.category, 'Other') AS category
          FROM finance.payment_reference r
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN cat ON cat.purpose = r.purpose
         WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND (p_session   IS NULL OR r.session = p_session)
           AND (p_faculty   IS NULL OR f.code = p_faculty)
           AND (p_dept      IS NULL OR d.code = p_dept)
           AND (p_programme IS NULL OR p.code = p_programme)
           AND (p_level     IS NULL OR s.current_level = p_level)
           AND (p_channel   IS NULL OR r.channel = p_channel)
           AND (p_category  IS NULL OR coalesce(cat.category, 'Other') = p_category)
           AND (p_from      IS NULL OR r.confirmed_at::date >= p_from)
           AND (p_to        IS NULL OR r.confirmed_at::date <= p_to)),
    tot AS (SELECT count(*) AS n, coalesce(sum(h.amount), 0) AS total FROM hit h),
    -- the newest first; payments confirmed at the same moment (an old-portal load) in a stable order
    top AS (SELECT h.reference, h.confirmed_at, h.category FROM hit h
             ORDER BY h.confirmed_at DESC, h.reference DESC
             LIMIT greatest(1, least(coalesce(p_limit, 500), 2000)))
    SELECT r.reference, r.confirmed_at,
           s.surname || ', ' || s.other_names AS payer,
           coalesce(s.matric_no, s.admission_no) AS number,
           p.code, p.name, d.code, d.name, f.code, f.name, s.current_level,
           r.purpose, t.category, r.channel, r.amount, r.receipt_no, r.session,
           tot.n AS match_count, tot.total AS match_total
      FROM top t
      JOIN finance.payment_reference r ON r.reference = t.reference
      JOIN people.student s ON s.id = r.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.department d ON d.code = p.dept_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      CROSS JOIN tot
     ORDER BY t.confirmed_at DESC, t.reference DESC
$function$;

-- finance.pg_fee_review: a postgraduate's school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.pg_fee_review(p_session text)
 RETURNS TABLE(student_id uuid, admission_no text, matric_no text, surname text, other_names text, status text, programme_code text, programme text, level integer, due numeric, paid numeric, excess numeric, payments jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pg AS (
        SELECT s.id, s.admission_no, s.matric_no, s.surname, s.other_names, s.status, s.programme_code, p.name AS programme, s.current_level
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND EXISTS (SELECT 1 FROM finance.payment_reference r
                        WHERE r.student_id = s.id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'))
    SELECT pg.id, pg.admission_no, pg.matric_no, pg.surname, pg.other_names, pg.status, pg.programme_code, pg.programme, pg.current_level,
           fp.due, fp.paid, fp.paid - fp.due,
           (SELECT jsonb_agg(jsonb_build_object('reference', r.reference, 'amount', r.amount, 'purpose', r.purpose, 'confirmedAt', r.confirmed_at,
                                                'channel', r.channel, 'receiptNo', r.receipt_no) ORDER BY r.confirmed_at)
              FROM finance.payment_reference r
             WHERE r.student_id = pg.id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%')
      FROM pg CROSS JOIN LATERAL finance.position(pg.id, p_session) fp
     WHERE fp.paid > fp.due
     ORDER BY fp.paid - fp.due DESC, pg.surname, pg.other_names;
$function$;

-- finance.position: a student's school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance."position"(p_student uuid, p_session text)
 RETURNS TABLE(due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH d AS (SELECT coalesce(sum(c.amount), 0) AS due FROM finance.charges(p_student, p_session) c),
         p AS (SELECT coalesce(sum(r.amount), 0) AS paid FROM finance.payment_reference r
                WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
         arrears AS (
             SELECT EXISTS (
                 SELECT 1 FROM (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL) past
                  WHERE finance.fee_short((SELECT coalesce(sum(c.amount), 0) FROM finance.charges(p_student, past.session) c),
                                          (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                                            WHERE r.student_id = p_student AND r.session = past.session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'))) AS yes)
    -- V454: short by under one naira is paid (the half that is the first instalment likewise)
    SELECT d.due, p.paid, finance.fee_owed(d.due, p.paid),
           CASE WHEN d.due = 0 THEN 2 WHEN NOT finance.fee_short(d.due, p.paid) THEN 2 WHEN NOT finance.fee_short(d.due / 2, p.paid) THEN 1 ELSE 0 END,
           d.due = 0 OR NOT finance.fee_short(d.due, p.paid),
           arrears.yes
      FROM d, p, arrears;
$function$;

-- finance.possible_double_charges: possible double charges: records that count
CREATE OR REPLACE FUNCTION finance.possible_double_charges(p_session text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, session text, purpose text, paid_on date, amount numeric, payments integer, refs text[], payrefs text[], check_id uuid, verdict text, evidence text, checked_by text, checked_at timestamp with time zone, open_requests integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH lg AS MATERIALIZED (
        SELECT r.student_id, r.session, r.purpose, r.amount, r.reference, (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date AS day
          FROM finance.payment_reference r
         WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND (p_session IS NULL OR r.session = p_session)
           -- a record holding several payments is not one payment to compare
           AND coalesce(r.note, '') !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'),
    -- the same student, session, item, day and amount twice or more: only these are looked at further
    cand AS MATERIALIZED (
        SELECT lg.* FROM lg
          JOIN (SELECT x.student_id, x.session, x.purpose, x.day, round(x.amount) AS amt FROM lg x
                 GROUP BY x.student_id, x.session, x.purpose, x.day, round(x.amount) HAVING count(*) >= 2) d
            ON d.student_id = lg.student_id AND d.session = lg.session AND d.purpose = lg.purpose AND d.day = lg.day AND d.amt = round(lg.amount)),
    numbered AS (
        SELECT cand.*, k.payref FROM cand
          LEFT JOIN LATERAL (SELECT min(p.payref) AS payref, count(*) AS n FROM finance.legacy_payref p WHERE p.reference = cand.reference) k ON true
         WHERE coalesce(k.n, 0) <= 1),
    g AS (
        SELECT n.student_id, n.session, n.purpose, n.day, round(n.amount) AS amt, count(*)::int AS n,
               array_agg(n.reference ORDER BY n.reference) AS refs, array_agg(coalesce(n.payref, '') ORDER BY n.reference) AS payrefs
          FROM numbered n
         GROUP BY n.student_id, n.session, n.purpose, n.day, round(n.amount)
        HAVING count(*) >= 2 AND count(DISTINCT n.payref) >= 2)
    SELECT g.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, g.session, g.purpose, g.day, g.amt,
           g.n, g.refs, g.payrefs, c.id, c.verdict, c.evidence, helpdesk.person_name(c.checked_by), c.checked_at,
           (SELECT count(*)::int FROM finance.payment_not_received w WHERE w.reference = ANY (g.refs) AND w.state = 'PROPOSED')
      FROM g
      JOIN people.student s ON s.id = g.student_id
      LEFT JOIN finance.double_charge_check c
             ON c.student_id = g.student_id AND c.session = g.session AND c.purpose = g.purpose AND c.paid_on = g.day AND c.amount = g.amt
$function$;

-- finance.propose_refund: nothing is refunded on an archived payment
CREATE OR REPLACE FUNCTION finance.propose_refund(p_student uuid, p_payer text, p_reason text, p_amount numeric, p_bank text, p_account_name text, p_account_last4 text, p_source text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_ref text; v_src text; st record; v_raised numeric;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a refund is raised by a person' USING ERRCODE = '23514'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'a refund is for an amount' USING ERRCODE = '23514'; END IF;
    IF p_payer IS NULL OR btrim(p_payer) = '' THEN RAISE EXCEPTION 'a refund names who it is paid to' USING ERRCODE = '23514'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'a refund carries the reason it is owed' USING ERRCODE = '23514'; END IF;

    v_src := nullif(upper(btrim(coalesce(p_source, ''))), '');
    IF v_src IS NOT NULL THEN
        SELECT * INTO st FROM finance.reference_state(v_src);
        IF st IS NULL OR st.amount IS NULL THEN
            RAISE EXCEPTION 'no transaction % was generated by this portal', v_src USING ERRCODE = '23503',
                HINT = 'Refund against a reference this portal issued; a slip from elsewhere is not a transaction here.';
        END IF;
        IF st.confirmed_at IS NULL THEN
            RAISE EXCEPTION 'transaction % is not a confirmed payment; there is nothing paid to refund', v_src USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE x.reference = v_src AND x.archived_at IS NOT NULL) THEN
            RAISE EXCEPTION 'REFUND_ARCHIVED: payment % is archived for review; nothing is refunded on it until the Bursary settles it', v_src USING ERRCODE = '23514';
        END IF;
        -- V350: with the refunds already raised against it and not rejected
        PERFORM 1 FROM finance.refund WHERE source_reference = v_src FOR UPDATE;
        v_raised := (SELECT coalesce(sum(amount), 0) FROM finance.refund WHERE source_reference = v_src AND state <> 'REJECTED');
        IF p_amount + v_raised > st.amount THEN
            RAISE EXCEPTION 'a refund of NGN % with the NGN % already raised exceeds the NGN % paid on %', p_amount, v_raised, st.amount, v_src USING ERRCODE = '23514',
                HINT = 'Refund up to what was received on the transaction, less what is already refunded on it.';
        END IF;
    END IF;

    v_ref := 'RF-' || to_char(current_date, 'YYYY') || '-' ||
             lpad(platform.next_number('REFUND', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    INSERT INTO finance.refund (reference, student_id, payer, reason, amount, bank_name, account_name, account_last4, proposed_by, source_reference)
    VALUES (v_ref, p_student, btrim(p_payer), btrim(p_reason), p_amount,
            nullif(btrim(coalesce(p_bank, '')), ''), nullif(btrim(coalesce(p_account_name, '')), ''), nullif(btrim(coalesce(p_account_last4, '')), ''), who, v_src);
    RETURN v_ref;
END $function$;

-- finance.put_right_legacy_items: a double under an item is archived for good, never deleted
CREATE OR REPLACE FUNCTION finance.put_right_legacy_items(p_reason text, p_limit integer DEFAULT 5000)
 RETURNS TABLE(renamed integer, relabelled integer, withdrawn integer, ledger_reversed integer, unknown_codes integer, remaining integer)
 LANGUAGE plpgsql
AS $function$
DECLARE m record; pr finance.payment_reference; gf record; nre int := 0; nrl int := 0; nw int := 0; nr int := 0; nu int := 0; v_left int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PAY_DOUBLE_ACTOR: a payment record is put right by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PAY_DOUBLE_REASON: say why the records are put right (at least ten characters); it is kept with each one' USING ERRCODE = '23514';
    END IF;
    FOR m IN SELECT * FROM finance.legacy_mislabelled() x WHERE x.action IN ('RENAME', 'RELABEL', 'DOUBLE') LIMIT greatest(1, coalesce(p_limit, 5000)) LOOP
        SELECT * INTO pr FROM finance.payment_reference WHERE id = m.id FOR UPDATE;
        IF pr.id IS NULL THEN CONTINUE; END IF;
        IF m.action = 'DOUBLE' THEN
            -- the same payment is on record under its item: this one goes, as a double does
            IF EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = pr.reference)
               OR EXISTS (SELECT 1 FROM finance.refund r WHERE r.source_reference = pr.reference)
               OR EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = pr.id) THEN CONTINUE; END IF;
            SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_WITHDRAWN',
                                                         'the payment ' || pr.reference || ' repeats ' || m.target_reference || ': ' || v_reason);
            IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
            UPDATE finance.legacy_payref SET reference = m.target_reference
             WHERE reference = pr.reference AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = m.target_reference);
            INSERT INTO finance.old_payment_withdrawn (id, reference, double_kind, kept_reference, student_id, session, purpose, amount, confirmed_at, channel,
                                                       receipt_no, note, ledger_journal, reversal_journal, withdrawn_by, reason)
            VALUES (pr.id, pr.reference, 'MISLABELLED', m.target_reference, pr.student_id, pr.session, pr.purpose, pr.amount, pr.confirmed_at, pr.channel,
                    pr.receipt_no, pr.note, gf.journal, gf.reversal, v_actor, v_reason);
            -- V670: archived for good (recorded twice) — kept, counted nowhere — instead of deleted
            PERFORM finance.payment_archive_withdrawn(pr.id, 'DUPLICATE_WITHDRAWAL', 'DUPLICATE_PAYMENT', m.target_reference, v_reason, v_actor, gf.journal, gf.reversal);
            nw := nw + 1;
        ELSIF m.action = 'RENAME' THEN
            -- taken since the list was read (two records of one item in this batch): the next batch reads it again
            IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE x.reference = m.target_reference OR x.receipt_no = 'LEG-' || m.target_reference) THEN CONTINUE; END IF;
            -- V502: pointed at by its reference since the list was read: the next batch reads it again (as a relabel)
            IF finance.payment_reference_linked(pr.reference, pr.id) THEN CONTINUE; END IF;
            -- posted under the income account the code read as, and under the old reference: let go, so the sync posts the
            -- renamed record under its item, once (left standing, the renamed reference would have been posted a second time)
            SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_CORRECTED',
                                                         'the payment ' || pr.reference || ' is ' || m.target_purpose || ' (' || m.target_reference || '): ' || v_reason);
            IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
            UPDATE finance.payment_reference SET reference = m.target_reference, receipt_no = 'LEG-' || m.target_reference, purpose = m.target_purpose
             WHERE id = pr.id;
            INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action, ledger_journal, reversal_journal, corrected_by, reason)
            VALUES (pr.id, pr.reference, m.target_reference, pr.purpose, m.target_purpose, 'RENAME', gf.journal, gf.reversal, v_actor, v_reason);
            nre := nre + 1;
        ELSE
            -- the same reference under another item: posted afresh under its account
            SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_CORRECTED',
                                                         'the payment ' || pr.reference || ' is ' || m.target_purpose || ': ' || v_reason);
            IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
            UPDATE finance.payment_reference SET purpose = m.target_purpose WHERE id = pr.id;
            INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action, ledger_journal, reversal_journal, corrected_by, reason)
            VALUES (pr.id, pr.reference, pr.reference, pr.purpose, m.target_purpose, 'RELABEL', gf.journal, gf.reversal, v_actor, v_reason);
            nrl := nrl + 1;
        END IF;
    END LOOP;
    SELECT count(*) FILTER (WHERE x.action = 'UNKNOWN_CODE'), count(*) FILTER (WHERE x.action <> 'UNKNOWN_CODE') INTO nu, v_left FROM finance.legacy_mislabelled() x;
    RETURN QUERY SELECT nre, nrl, nw, nr, nu, v_left;
END $function$;

-- finance.raise_not_received: an archived payment is settled on Archived payments
CREATE OR REPLACE FUNCTION finance.raise_not_received(p_code text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    CASE p_code
      WHEN 'PAY_NOT_RECEIVED_NO_RECORD' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_NO_RECORD: no such payment record (it may already be withdrawn)' USING ERRCODE = '23514';
      WHEN 'PAY_NOT_RECEIVED_NOT_OLD_PORTAL' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_NOT_OLD_PORTAL: only an old-portal payment record (MOAUM-LEG-…) is withdrawn here; a portal payment is settled with the gateway' USING ERRCODE = '23514';
      WHEN 'PAY_NOT_RECEIVED_ARCHIVED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_ARCHIVED: the payment is archived for review; it is settled on Archived payments' USING ERRCODE = '23514';
      WHEN 'PAY_NOT_RECEIVED_SUMMED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_SUMMED: the record holds several payments; withdrawing it would take the others with it' USING ERRCODE = '23514',
            HINT = 'Correct it on Old Fees History: reset the session and load the export again, which records each payment by its number.';
      WHEN 'PAY_NOT_RECEIVED_LINKED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_LINKED: a deferment fee, a refund, the GST desk or a gateway test points at the record' USING ERRCODE = '23514';
      WHEN 'PAY_NOT_RECEIVED_SWAPPED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_SWAPPED: the payment is in a school-fees payment swap' USING ERRCODE = '23514';
      WHEN 'PAY_NOT_RECEIVED_DECIDED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_DECIDED: the session''s overpayment was already carried into the next session or refunded' USING ERRCODE = '23514',
            HINT = 'A withdrawal now would leave that excess carried or refunded twice; settle it with the student''s account first.';
      ELSE NULL;
    END CASE;
END $function$;

-- finance.reallocation_account: an obligation's paid figure: payments that count
CREATE OR REPLACE FUNCTION finance.reallocation_account(p_student uuid, p_code text, p_session text, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE pos record; g record; v_less numeric := 0; v_fee numeric; v_held numeric;
BEGIN
    IF p_code = 'SCHOOL_FEES' THEN
        SELECT * INTO pos FROM finance.position(p_student, p_session);
        SELECT coalesce(sum(r.amount), 0) INTO v_less FROM finance.payment_reference r
         WHERE r.id = p_exclude AND r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%';
        RETURN jsonb_build_object('code', p_code, 'kind', 'SESSION_ACCOUNT', 'stated', finance.fee_stated(p_student, p_session),
            'fee', pos.due, 'paid', pos.paid - v_less, 'balance', finance.fee_owed(pos.due, pos.paid - v_less),
            'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'),
            'clearsExamination', finance.clears_or_null(p_student, p_session, 'EXAMINATION'));
    ELSIF p_code = 'GST_FEE' THEN
        SELECT * INTO g FROM finance.gst_entitlement(p_student, p_session);
        SELECT coalesce(sum(r.amount - finance.gst_refunded(r.reference)), 0) INTO v_less FROM finance.payment_reference r
         WHERE r.id = p_exclude AND r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'GST fee %';
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
END $function$;

-- finance.refresh_entitlement: an archived payment grants nothing
CREATE OR REPLACE FUNCTION finance.refresh_entitlement(p_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r finance.payment_reference; v_applied text[] := '{}'; v_problems text[] := '{}'; v_trn text; v_n int; v_before jsonb;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAY_REFERENCE: no student payment reference % was generated by this portal', p_reference USING ERRCODE = '23514';
    END IF;
    IF r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'PAY_NOT_CONFIRMED: reference % is not confirmed', r.reference USING ERRCODE = '23514',
            HINT = 'Verify it with the gateway first; if it does not confirm, escalate to the Bursary with the evidence.';
    END IF;
    IF r.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'PAY_ARCHIVED: reference % is archived for review by the Bursary; it grants nothing until it is settled', r.reference USING ERRCODE = '23514';
    END IF;
    v_before := finance.entitlement_state(r.student_id, r.session);
    IF r.purpose LIKE 'Transcript TRN-%' THEN
        v_trn := substr(r.purpose, 12, 14);
        UPDATE credentials.transcript_request t SET paid_at = now(),
               stage = CASE WHEN clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN 'READY' ELSE 'HELD_AT_CLEARANCE' END
         WHERE t.ref = v_trn AND t.paid_at IS NULL;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_applied := v_applied || CASE WHEN v_n > 0 THEN 'The transcript request is marked paid.' ELSE 'The transcript request already stood paid.' END;
    ELSIF r.purpose LIKE 'Hostel accommodation%' THEN
        BEGIN
            PERFORM hostel.confirm_by_reference(r.reference);
            v_applied := v_applied || 'The hostel booking stands confirmed against the payment.'::text;
        EXCEPTION WHEN check_violation THEN
            v_problems := v_problems || ('Hostel: ' || SQLERRM || ' — escalate to the Bursary and the Dean of Student Affairs.');
        END;
    ELSIF r.purpose LIKE 'Library fine%' THEN
        PERFORM library.settle_by_reference(r.reference);
        v_applied := v_applied || 'The library fine stands settled.'::text;
    ELSIF r.purpose LIKE 'Wallet top-up%' AND NOT EXISTS (SELECT 1 FROM finance.wallet_entry w WHERE w.reference = r.reference) THEN
        v_problems := v_problems || 'Wallet: the top-up is confirmed but no wallet credit stands against it; a credit is the Bursary''s to write — escalate the ticket to the Bursary.'::text;
    END IF;
    PERFORM people.refresh_academic_position(r.student_id);
    v_applied := v_applied || 'The academic position was recomputed from the record.'::text;
    RETURN jsonb_build_object('reference', r.reference, 'session', r.session, 'purpose', r.purpose, 'applied', to_jsonb(v_applied), 'problems', to_jsonb(v_problems),
                              'before', v_before, 'after', finance.entitlement_state(r.student_id, r.session));
END $function$;

-- finance.registrations_without_fees: registrations without fees: payments that count
CREATE OR REPLACE FUNCTION finance.registrations_without_fees(p_session text)
 RETURNS TABLE(registration_id uuid, student_id uuid, number text, name text, programme text, faculty text, level integer, semester integer, status text, submitted_at timestamp with time zone, approved_at timestamp with time zone, stated boolean, due numeric, paid numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH reg AS MATERIALIZED (
        SELECT r.id, r.student_id, r.session, r.level, r.semester, r.status, r.submitted_at, r.approved_at
          FROM registration.course_registration r
         WHERE r.session = p_session AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    -- V524: the fee profile of each registered student (what the schedule's answers depend on)
    prof AS MATERIALIZED (
        SELECT DISTINCT r.student_id,
               CASE WHEN fp.student_id IS NULL THEN r.student_id::text
                    ELSE row(fp.programme_code, fp.current_level, fp.entry_mode, fp.state, fp.is_spill, fp.spill_year, fp.reg_sems)::text END AS k   -- V613/V616
          FROM reg r LEFT JOIN finance.fee_profiles(p_session) fp ON fp.student_id = r.student_id),
    rep AS MATERIALIZED (SELECT DISTINCT ON (p.k) p.k, p.student_id FROM prof p ORDER BY p.k, p.student_id),
    said AS MATERIALIZED (
        SELECT rp.k, finance.fee_stated(rp.student_id, p_session) AS stated,
               finance.fee_unstated_semesters(rp.student_id, p_session) AS unstated
          FROM rep rp),
    owed AS MATERIALIZED (
        SELECT ks.k, ks.semester, finance.due_for_semester(rp.student_id, p_session, ks.semester) AS due
          FROM (SELECT DISTINCT p.k, r.semester FROM reg r JOIN prof p ON p.student_id = r.student_id) ks
          JOIN rep rp ON rp.k = ks.k),
    paid AS MATERIALIZED (
        SELECT pr.student_id, sum(pr.amount) AS paid
          FROM finance.payment_reference pr
         WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.purpose LIKE 'School fees%'
           AND pr.student_id IN (SELECT p.student_id FROM prof p)
         GROUP BY pr.student_id),
    open_ AS (SELECT coalesce(array_agg(sm.number), '{}'::int[]) AS n FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN')
    SELECT r.id, s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.name, f.name, r.level, r.semester,
           r.status, r.submitted_at, r.approved_at, sd.stated,
           CASE WHEN sd.stated THEN ow.due END,
           coalesce(pd.paid, 0)
      FROM reg r
      JOIN people.student s ON s.id = r.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN prof pf ON pf.student_id = r.student_id
      JOIN said sd ON sd.k = pf.k
      JOIN owed ow ON ow.k = pf.k AND ow.semester = r.semester
      LEFT JOIN paid pd ON pd.student_id = r.student_id
      CROSS JOIN open_ o
     -- not cleared, as finance.semester_cleared decides it
     WHERE NOT (sd.stated
                AND NOT finance.fee_short(ow.due, coalesce(pd.paid, 0))
                AND NOT (r.semester = ANY (o.n) AND r.semester = ANY (sd.unstated)))
     ORDER BY f.name, p.name, s.surname, s.other_names, r.semester
$function$;

-- finance.reset_legacy_payments: a payment the archive holds stays
CREATE OR REPLACE FUNCTION finance.reset_legacy_payments(p_session text, p_confirm text, p_limit integer DEFAULT 5000)
 RETURNS TABLE(deleted bigint, kept_in_use bigint, ledger_reversed bigint, remaining bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'finance', 'people', 'public', 'pg_temp'
AS $function$
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
                   -- V670: a payment the archive holds (archived, or settled) stays: it is never deleted
                   AND r.archived_at IS NULL AND NOT EXISTS (SELECT 1 FROM finance.payment_archive pa WHERE pa.payment_id = r.id)
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
                    OR r.id IN (SELECT x.payment_id FROM finance.payment_reallocation x WHERE x.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL', 'RETURNED'))
                    OR r.id IN (SELECT pa.payment_id FROM finance.payment_archive pa)) AS linked
              FROM finance.payment_reference r
             WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)) s;

    RETURN QUERY SELECT n, v_kept, nr, v_left;
END $function$;

-- finance.semester_cleared: a semester's fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.semester_cleared(p_student uuid, p_session text, p_semester integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    -- V454: short of the semester's cumulative due by under one naira is cleared
    -- V461: and never a semester whose own fees are not stated for the student while another semester's are; every
    -- gate that reads this (course registration, the College's, ICT Support's, entitlements, the fees page) holds it.
    -- Asked in this order so the semester's own lines are read only for an open semester the student has paid up to
    SELECT CASE WHEN NOT finance.fee_stated(p_student, p_session) THEN false
                WHEN finance.fee_short(finance.due_for_semester(p_student, p_session, p_semester),
                                 coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                                            WHERE r.student_id = p_student AND r.session = p_session
                                              AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'), 0)) THEN false
                WHEN EXISTS (SELECT 1 FROM policy.semester sm WHERE sm.session = p_session AND sm.number = p_semester AND sm.state = 'OPEN')
                     AND p_semester = ANY (finance.fee_unstated_semesters(p_student, p_session)) THEN false
                ELSE true END;
$function$;

-- finance.semester_position: a semester's fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.semester_position(p_student uuid, p_session text, p_semester integer, p_registering boolean DEFAULT false)
 RETURNS TABLE(due numeric, paid numeric, outstanding numeric, cleared boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE v_before text := current_setting('moaum.registering', true);
BEGIN
    -- with p_registering, the semester read as registered: its spillover lines (and a whole-session one) owed as they are once a course of
    -- it is on the registration — the setting is this call's alone, put back before it returns
    IF p_registering THEN
        PERFORM set_config('moaum.registering', p_student::text || '|' || p_session || '|' || p_semester::text, true);
    END IF;
    due := finance.due_for_semester(p_student, p_session, p_semester);
    paid := coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                       WHERE r.student_id = p_student AND r.session = p_session
                         AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'), 0);
    outstanding := CASE WHEN finance.fee_short(due, paid) THEN due - paid ELSE 0 END;
    cleared := finance.semester_cleared(p_student, p_session, p_semester);
    IF p_registering THEN
        PERFORM set_config('moaum.registering', coalesce(v_before, ''), true);
    END IF;
    RETURN NEXT;
END $function$;

-- finance.session_charges: school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.session_charges(p_session text)
 RETURNS TABLE(student_id uuid, fee numeric, late_payment boolean, late_registration boolean, total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS MATERIALIZED (SELECT * FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL)),
    -- V537: read once, not inside the check made for every student
    reg_windows AS MATERIALIZED (
        SELECT sem, rw.phase, rw.closes_at
          FROM generate_series(1, 3) sem
          CROSS JOIN LATERAL policy.window_state('COURSE_REGISTRATION', p_session, sem) rw
         WHERE rw.configured AND rw.late_fee_enabled),
    paid_in_time AS MATERIALIZED (
        SELECT r.student_id, sum(r.amount) AS total
          FROM finance.payment_reference r CROSS JOIN w
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)
         GROUP BY r.student_id),
    prof AS MATERIALIZED (SELECT fp.student_id, fp.profile_key FROM finance.fee_profiles(p_session) fp),
    sums AS MATERIALIZED (SELECT x.profile_key, x.fee, x.late_payment, x.late_registration FROM finance.fee_sums(p_session, NULL) x),
    each AS (
        SELECT pr.student_id, coalesce(s.fee, 0) AS fee, coalesce(s.late_payment, 0) AS lp, coalesce(s.late_registration, 0) AS lr,
               (SELECT w.late_fee_enabled AND w.phase = 'LATE' FROM w) AND coalesce(pit.total, 0) < coalesce(s.fee, 0) AS late_payment,
               EXISTS (
                   SELECT 1 FROM reg_windows rw
                    WHERE (rw.phase = 'LATE' AND NOT EXISTS (
                               SELECT 1 FROM registration.course_registration cr
                                WHERE cr.student_id = pr.student_id AND cr.session = p_session AND cr.semester = rw.sem
                                  AND cr.submitted_at IS NOT NULL AND (rw.closes_at IS NULL OR cr.submitted_at <= rw.closes_at))
                          OR EXISTS (
                               SELECT 1 FROM registration.course_registration cr
                                WHERE cr.student_id = pr.student_id AND cr.session = p_session AND cr.semester = rw.sem
                                  AND cr.submitted_at IS NOT NULL AND rw.closes_at IS NOT NULL AND cr.submitted_at > rw.closes_at))) AS late_registration
          FROM prof pr
          LEFT JOIN sums s ON s.profile_key = pr.profile_key
          LEFT JOIN paid_in_time pit ON pit.student_id = pr.student_id)
    SELECT e.student_id, e.fee, coalesce(e.late_payment, false), e.late_registration,
           e.fee + CASE WHEN coalesce(e.late_payment, false) THEN e.lp ELSE 0 END + CASE WHEN e.late_registration THEN e.lr ELSE 0 END
      FROM each e
$function$;

-- finance.session_fee_positions: school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.session_fee_positions(p_session text)
 RETURNS TABLE(student_id uuid, due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH past AS (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL),
    past_paid AS (
        SELECT r.student_id, r.session, sum(r.amount) AS total
          FROM finance.payment_reference r JOIN past ON past.session = r.session
         WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id, r.session),
    arrears AS (
        SELECT DISTINCT c.student_id
          FROM past CROSS JOIN LATERAL finance.session_charges(past.session) c
          LEFT JOIN past_paid pp ON pp.student_id = c.student_id AND pp.session = past.session
         WHERE finance.fee_short(c.total, coalesce(pp.total, 0))),
    now_ AS (
        SELECT c.student_id, c.total AS due, coalesce(pay.total, 0) AS paid
          FROM finance.session_charges(p_session) c
          LEFT JOIN finance.session_payments(p_session) pay ON pay.student_id = c.student_id)
    -- V454: as finance.position, short by under one naira is paid
    SELECT n.student_id, n.due, n.paid, finance.fee_owed(n.due, n.paid),
           CASE WHEN n.due = 0 THEN 2 WHEN NOT finance.fee_short(n.due, n.paid) THEN 2 WHEN NOT finance.fee_short(n.due / 2, n.paid) THEN 1 ELSE 0 END,
           n.due = 0 OR NOT finance.fee_short(n.due, n.paid),
           EXISTS (SELECT 1 FROM arrears a WHERE a.student_id = n.student_id)
      FROM now_ n
$function$;

-- finance.session_payments: school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.session_payments(p_session text)
 RETURNS TABLE(student_id uuid, total numeric, n integer, last_paid_at timestamp with time zone, last_reference text, last_channel text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH p AS (
        SELECT r.student_id, r.amount, r.confirmed_at, r.reference, r.channel
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
    agg AS (SELECT p.student_id, sum(p.amount) AS total, count(*)::int AS n FROM p GROUP BY p.student_id),
    last AS (SELECT DISTINCT ON (p.student_id) p.student_id, p.confirmed_at, p.reference, p.channel FROM p ORDER BY p.student_id, p.confirmed_at DESC, p.reference DESC)
    SELECT agg.student_id, agg.total, agg.n, last.confirmed_at, last.reference, last.channel
      FROM agg JOIN last ON last.student_id = agg.student_id
$function$;

-- finance.spillover_panel: school fees paid: payments that count
CREATE OR REPLACE FUNCTION finance.spillover_panel(p_student uuid, p_session text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH s AS (
        SELECT st.id, finance.spill(st.id, st.current_level, st.programme_code, st.status) AS spill,
               finance.spill_year(st.id, st.current_level, st.programme_code, st.status) AS yr
          FROM people.student st WHERE st.id = p_student),
    ap AS (SELECT a.spillover_state FROM people.academic_position a WHERE a.student_id = p_student),
    rs AS (SELECT coalesce(finance.reg_semesters(p_student, p_session), '{}'::int[]) AS sems),
    -- each semester's spillover lines as they would apply once a course is registered in it (V616: p_any_semester)
    lines AS (
        SELECT f.semester, sum(c.amount) AS amount
          FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], NULL, true) c
          JOIN finance.fee_schedule f ON f.id = c.id
         GROUP BY f.semester),
    -- the carry-overs the published results state, by the session and semester they were failed in
    co AS (
        SELECT split_part(c.failed_in, ' semester ', 1) AS session, nullif(split_part(c.failed_in, ' semester ', 2), '')::int AS semester,
               c.course_code, c.title, c.units
          FROM registration.carryovers(p_student) c),
    pos AS (SELECT * FROM finance.position(p_student, p_session)),
    -- V664: what the registration gate reads — the session's confirmed school-fee payments against the cumulative due: the whole-session
    -- item (semester 0) first, then the first semester, then the second; each semester's own amount is its step in that sum
    paid AS (SELECT coalesce(sum(r.amount), 0) AS p FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
    cum AS (SELECT n, finance.due_for_semester(p_student, p_session, n) AS c FROM unnest(ARRAY[0, 1, 2]) n),
    sem AS (
        SELECT k.n, c1.c - c0.c AS owed,
               least(greatest(paid.p - c0.c, 0), c1.c - c0.c) AS applied,
               CASE WHEN finance.fee_short(c1.c, paid.p) THEN (c1.c - c0.c) - least(greatest(paid.p - c0.c, 0), c1.c - c0.c) ELSE 0 END AS left_over,
               -- what is still to pay for the semester to be cleared: anything earlier left unpaid, and its own
               CASE WHEN finance.fee_short(c1.c, paid.p) THEN c1.c - paid.p ELSE 0 END AS to_clear
          FROM unnest(ARRAY[1, 2]) AS k(n)
          JOIN cum c1 ON c1.n = k.n
          JOIN cum c0 ON c0.n = k.n - 1
          CROSS JOIN paid)
    SELECT CASE WHEN NOT s.spill THEN NULL ELSE jsonb_build_object(
        'session', p_session,
        'state', (SELECT ap.spillover_state FROM ap),
        'year', s.yr,
        'label', CASE WHEN s.yr IS NOT NULL THEN 'SP' || s.yr ELSE 'Spillover' END,
        'registeredSemesters', to_jsonb(rs.sems),
        'semesters', (SELECT jsonb_agg(jsonb_build_object(
                          'semester', x.n,
                          'fee', coalesce((SELECT l.amount FROM lines l WHERE l.semester = x.n), 0),
                          'registered', x.n = ANY (rs.sems),
                          'carryovers', (SELECT count(*) FROM co WHERE co.semester = x.n),
                          'courses', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', co.course_code, 'title', co.title, 'units', co.units, 'session', co.session)
                                                                ORDER BY co.session, co.course_code), '[]'::jsonb) FROM co WHERE co.semester = x.n),
                          -- V664: the semester's own obligation, the payments applied to it, what is left, and where it stands
                          'owed', CASE WHEN x.n = ANY (rs.sems) THEN x.owed ELSE 0 END,
                          'paid', CASE WHEN x.n = ANY (rs.sems) THEN x.applied ELSE 0 END,
                          'outstanding', CASE WHEN x.n = ANY (rs.sems) THEN x.left_over ELSE 0 END,
                          'toClear', CASE WHEN x.n = ANY (rs.sems) THEN x.to_clear ELSE 0 END,
                          'cleared', CASE WHEN x.n = ANY (rs.sems) THEN finance.semester_cleared(p_student, p_session, x.n) ELSE true END,
                          -- registered: ready only when the gate clears it (a whole-session item unpaid holds every semester); a semester
                          -- with no line of its own and no whole-session item is not stated
                          'status', CASE WHEN x.n = ANY (rs.sems) THEN
                                             CASE WHEN x.owed <= 0 AND coalesce((SELECT l.amount FROM lines l WHERE l.semester = x.n), 0) <= 0
                                                       AND coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0) <= 0 THEN 'NOT_STATED'
                                                  WHEN finance.semester_cleared(p_student, p_session, x.n) THEN 'PAID'
                                                  WHEN x.applied > 0 THEN 'PART_PAID'
                                                  ELSE 'PAYMENT_REQUIRED' END
                                         WHEN (SELECT count(*) FROM co WHERE co.semester = x.n) > 0 THEN 'NOT_REGISTERED'
                                         ELSE 'NOTHING_OWED' END)
                          ORDER BY x.n) FROM sem x),
        'sessionFee', coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0),
        'sessionOwed', (SELECT c FROM cum WHERE n = 0),
        'sessionPaid', least((SELECT p FROM paid), (SELECT c FROM cum WHERE n = 0)),
        'due', pos.due, 'paid', pos.paid, 'balance', greatest(pos.balance, 0)) END
      FROM s CROSS JOIN rs CROSS JOIN pos
$function$;

-- finance.wallet_cashflow: the wallet settled to fees: payments that count
CREATE OR REPLACE FUNCTION finance.wallet_cashflow(p_session text)
 RETURNS TABLE(credited numeric, topped_up numeric, applied numeric, reversed numeric, withdrawn numeric, held numeric, loans_in numeric, grants_in numeric, self_in numeric, settled_to_fees numeric, applied_matches boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH e AS (
        SELECT e.*, fs.nature FROM finance.wallet_entry e
          LEFT JOIN finance.funding_source fs ON fs.code = e.source_code
         WHERE p_session IS NULL OR e.session = p_session),
    settled AS (
        SELECT coalesce(sum(amount), 0) AS s FROM finance.payment_reference
         WHERE channel = 'NELFUND wallet' AND confirmed_at IS NOT NULL AND archived_at IS NULL AND (p_session IS NULL OR session = p_session))
    SELECT
        coalesce(sum(amount) FILTER (WHERE kind = 'CREDIT'), 0),
        coalesce(sum(amount) FILTER (WHERE kind = 'TOPUP'), 0),
        coalesce(sum(amount) FILTER (WHERE kind = 'APPLIED'), 0),
        coalesce(sum(amount) FILTER (WHERE kind = 'REVERSED'), 0),
        coalesce(sum(amount) FILTER (WHERE kind = 'REFUND'), 0),
        coalesce(sum(CASE WHEN kind IN ('CREDIT','TOPUP') THEN amount ELSE -amount END), 0),
        coalesce(sum(amount) FILTER (WHERE kind IN ('CREDIT','TOPUP') AND nature = 'LOAN'), 0),
        coalesce(sum(amount) FILTER (WHERE kind IN ('CREDIT','TOPUP') AND nature = 'GRANT'), 0),
        coalesce(sum(amount) FILTER (WHERE kind IN ('CREDIT','TOPUP') AND nature = 'SELF'), 0),
        (SELECT s FROM settled),
        coalesce(sum(amount) FILTER (WHERE kind = 'APPLIED'), 0) = (SELECT s FROM settled)
      FROM e
$function$;

-- finance.withdraw_legacy_duplicates: a record twice is archived for good, never deleted
CREATE OR REPLACE FUNCTION finance.withdraw_legacy_duplicates(p_reason text)
 RETURNS TABLE(withdrawn integer, ledger_reversed integer, left_linked integer)
 LANGUAGE plpgsql
AS $function$
DECLARE d record; pr finance.payment_reference; v_journal uuid; v_reversal uuid; n int := 0; nr int := 0; nl int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'recorded twice by the Old Fees History import');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payment record is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    FOR d IN SELECT * FROM finance.legacy_duplicate_pairs() LOOP
        IF d.linked IS NOT NULL THEN nl := nl + 1; CONTINUE; END IF;
        SELECT * INTO pr FROM finance.payment_reference WHERE id = d.duplicate_id FOR UPDATE;
        v_journal := NULL; v_reversal := NULL;
        SELECT g.id INTO v_journal FROM finance.gl_journal g
         WHERE g.source_type = 'PAYMENT' AND g.source_ref = d.duplicate_reference AND g.status = 'POSTED'
         ORDER BY g.posted_at LIMIT 1;
        IF v_journal IS NOT NULL THEN
            v_reversal := finance.gl_reverse(v_journal, 'the payment ' || d.duplicate_reference || ' repeats ' || d.kept_reference || ': ' || v_reason);
            nr := nr + 1;
        END IF;
        INSERT INTO finance.legacy_duplicate_withdrawn (id, reference, kept_reference, student_id, session, purpose, amount, confirmed_at, receipt_no, note,
                                                       ledger_journal, reversal_journal, withdrawn_by, reason)
        VALUES (pr.id, pr.reference, d.kept_reference, pr.student_id, pr.session, pr.purpose, pr.amount, pr.confirmed_at, pr.receipt_no, pr.note,
                v_journal, v_reversal, v_actor, v_reason);
        -- V670: archived for good (recorded twice) — kept, counted nowhere — instead of deleted
        PERFORM finance.payment_archive_withdrawn(pr.id, 'DUPLICATE_WITHDRAWAL', 'DUPLICATE_PAYMENT', d.kept_reference, v_reason, v_actor, v_journal, v_reversal);
        n := n + 1;
    END LOOP;
    RETURN QUERY SELECT n, nr, nl;
END $function$;

-- finance.withdraw_old_payment_doubles: a double is archived for good, never deleted
CREATE OR REPLACE FUNCTION finance.withdraw_old_payment_doubles(p_reason text, p_limit integer DEFAULT 5000)
 RETURNS TABLE(withdrawn integer, ledger_reversed integer, left_linked integer, remaining integer)
 LANGUAGE plpgsql
AS $function$
DECLARE d record; pr finance.payment_reference; gf record; n int := 0; nr int := 0; nl int := 0; v_left int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PAY_DOUBLE_ACTOR: a payment record is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PAY_DOUBLE_REASON: say why the records are withdrawn (at least ten characters); it is kept with each one' USING ERRCODE = '23514';
    END IF;
    -- in batches (the screen asks again until none is left): a whole export loaded through the retired door is some 300,000
    FOR d IN SELECT * FROM finance.old_payment_doubles() x WHERE x.linked IS NULL LIMIT greatest(1, coalesce(p_limit, 5000)) LOOP
        -- the record it repeats is still there (an earlier copy may itself have gone as a double, the record it repeated then
        -- standing for both)
        IF NOT EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = d.kept_reference) THEN CONTINUE; END IF;
        SELECT * INTO pr FROM finance.payment_reference WHERE id = d.double_id FOR UPDATE;
        IF pr.id IS NULL THEN CONTINUE; END IF;
        SELECT * INTO gf FROM finance.gl_free_payment(pr.reference, pr.id, 'PAYMENT_WITHDRAWN',
                                                     'the payment ' || pr.reference || ' repeats ' || d.kept_reference || ': ' || v_reason);
        IF gf.reversal IS NOT NULL THEN nr := nr + 1; END IF;
        -- a whole-session record's payment number goes to the per-semester record that stands for it
        IF d.double_kind = 'WHOLE_SESSION' THEN
            UPDATE finance.legacy_payref SET reference = d.kept_reference WHERE reference = d.double_reference;
            UPDATE finance.payment_reference SET note = pr.note WHERE reference = d.kept_reference AND note NOT LIKE '%old ref %';
        END IF;
        INSERT INTO finance.old_payment_withdrawn (id, reference, double_kind, kept_reference, student_id, session, purpose, amount, confirmed_at, channel,
                                                   receipt_no, note, ledger_journal, reversal_journal, withdrawn_by, reason)
        VALUES (pr.id, pr.reference, d.double_kind, d.kept_reference, pr.student_id, pr.session, pr.purpose, pr.amount, pr.confirmed_at, pr.channel,
                pr.receipt_no, pr.note, gf.journal, gf.reversal, v_actor, v_reason);
        -- V670: archived for good (recorded twice) — kept, counted nowhere — instead of deleted
        PERFORM finance.payment_archive_withdrawn(pr.id, 'DUPLICATE_WITHDRAWAL', 'DUPLICATE_PAYMENT', d.kept_reference, v_reason, v_actor, gf.journal, gf.reversal);
        n := n + 1;
    END LOOP;
    SELECT count(*) FILTER (WHERE x.linked IS NOT NULL), count(*) FILTER (WHERE x.linked IS NULL) INTO nl, v_left FROM finance.old_payment_doubles() x;
    RETURN QUERY SELECT n, nr, nl, v_left;
END $function$;

-- hostel.finance_summary: hostel fees collected: payments that count
CREATE OR REPLACE FUNCTION hostel.finance_summary(p_session text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH live AS (
        SELECT al.*, r.hall_code, h.name AS hall_name, coalesce(al.category, r.category) AS cat
          FROM hostel.allocation al JOIN hostel.room r ON r.id = al.room_id JOIN hostel.hall h ON h.code = r.hall_code
         WHERE al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL),
        tx AS (SELECT count(*) AS n, coalesce(sum(pr.amount), 0) AS amount FROM finance.payment_reference pr
                WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.purpose ~* '^hostel accommodation(?! damage| fine)'),
        fines AS (SELECT * FROM hostel.sanction WHERE session = p_session AND kind = 'FINE')
    SELECT jsonb_build_object(
        'session', p_session,
        'totals', jsonb_build_object(
            'charges', coalesce((SELECT sum(fee_amount) FROM live WHERE fee_status IN ('PAYABLE', 'PAID')), 0),
            'paid', coalesce((SELECT sum(fee_amount) FROM live WHERE fee_status = 'PAID'), 0),
            'outstanding', coalesce((SELECT sum(fee_amount) FROM live WHERE fee_status = 'PAYABLE'), 0),
            'transactions', (SELECT n FROM tx), 'transactions_amount', (SELECT amount FROM tx),
            'paid_occupants', (SELECT count(*) FROM live WHERE fee_status = 'PAID'),
            'unpaid_occupants', (SELECT count(*) FROM live WHERE fee_status = 'PAYABLE'),
            'exempt_allocations', (SELECT count(*) FROM live WHERE fee_status = 'NO_CHARGE'),
            'refunds', 0,
            'fines_imposed', coalesce((SELECT sum(amount) FROM fines WHERE state = 'IN_FORCE'), 0),
            'fines_paid', coalesce((SELECT sum(amount) FROM fines WHERE settled_at IS NOT NULL), 0),
            'fines_outstanding', coalesce((SELECT sum(amount) FROM fines WHERE state = 'IN_FORCE' AND settled_at IS NULL AND waived_at IS NULL), 0),
            'fines_waived', coalesce((SELECT sum(amount) FROM fines WHERE waived_at IS NOT NULL AND settled_at IS NULL), 0)),
        'byHall', coalesce((SELECT jsonb_agg(jsonb_build_object('hall', g.hall_name, 'code', g.hall_code, 'charges', g.charges, 'paid', g.paid, 'outstanding', g.outstanding, 'exempt', g.exempt, 'occupants', g.occupants) ORDER BY g.hall_name)
                             FROM (SELECT hall_name, hall_code, coalesce(sum(fee_amount) FILTER (WHERE fee_status IN ('PAYABLE','PAID')), 0) AS charges, coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAID'), 0) AS paid,
                                          coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAYABLE'), 0) AS outstanding, count(*) FILTER (WHERE fee_status = 'NO_CHARGE') AS exempt, count(*) AS occupants
                                     FROM live GROUP BY hall_name, hall_code) g), '[]'::jsonb),
        'byCategory', coalesce((SELECT jsonb_agg(jsonb_build_object('category', g.cat, 'label', g.label, 'charges', g.charges, 'paid', g.paid, 'outstanding', g.outstanding, 'exempt', g.exempt, 'occupants', g.occupants) ORDER BY g.cat)
                                 FROM (SELECT live.cat, rc.label, coalesce(sum(fee_amount) FILTER (WHERE fee_status IN ('PAYABLE','PAID')), 0) AS charges, coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAID'), 0) AS paid,
                                              coalesce(sum(fee_amount) FILTER (WHERE fee_status = 'PAYABLE'), 0) AS outstanding, count(*) FILTER (WHERE fee_status = 'NO_CHARGE') AS exempt, count(*) AS occupants
                                         FROM live JOIN hostel.room_category rc ON rc.code = live.cat GROUP BY live.cat, rc.label) g), '[]'::jsonb),
        'byStatus', coalesce((SELECT jsonb_agg(jsonb_build_object('status', g.fee_status, 'occupants', g.occupants, 'amount', g.amount) ORDER BY g.fee_status)
                               FROM (SELECT fee_status, count(*) AS occupants, coalesce(sum(fee_amount), 0) AS amount FROM live GROUP BY fee_status) g), '[]'::jsonb))
$function$;

-- people.deferment_financials: the last school fees payment: one that counts
CREATE OR REPLACE FUNCTION people.deferment_financials(p_student uuid, p_session text)
 RETURNS TABLE(last_fee_amount numeric, last_fee_ref text, last_fee_at timestamp with time zone, last_fee_session text, last_fee_channel text, last_fee_receipt text, balance numeric, due numeric, paid numeric, balance_session text, position_status text, has_arrears boolean, found boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH last AS (
        SELECT r.amount, r.reference, r.confirmed_at, r.session, r.channel, r.receipt_no
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.confirmed_at DESC LIMIT 1),
    ses AS (SELECT coalesce(p_session, (SELECT name FROM policy.academic_session WHERE state = 'CURRENT')) AS name),
    pos AS (SELECT p.* FROM ses, LATERAL finance.position(p_student, ses.name) p)
    SELECT last.amount, last.reference, last.confirmed_at, last.session, last.channel, last.receipt_no,
           pos.balance, pos.due, pos.paid, ses.name,
           CASE WHEN pos.due = 0 THEN 'NO_CHARGE' WHEN pos.paid_in_full THEN 'FULLY_PAID' WHEN pos.paid > 0 THEN 'PART_PAYMENT' ELSE 'NOT_PAID' END,
           pos.has_arrears, last.reference IS NOT NULL
      FROM ses LEFT JOIN last ON true LEFT JOIN pos ON true;
$function$;

-- reporting.master_rows: EPS paid: payments that count
CREATE OR REPLACE FUNCTION reporting.master_rows(p_session text, p_semester integer, p_f jsonb)
 RETURNS TABLE(student_id uuid, matric_no text, jamb_no text, surname text, other_names text, sex text, status text, academic_status text, programme_type text, admission_route text, study_mode text, centre_code text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, entry_session text, fee_status text, payable numeric, paid_amount numeric, outstanding numeric, last_paid_at timestamp with time zone, school_fees_paid boolean, registered boolean, registration_status text, carryovers integer, courses integer, units integer, paid_not_registered boolean, gst_status text, gst_registered boolean, gst_required boolean, gst_fee numeric, gst_paid_amount numeric, gst_outstanding numeric, gst_paid_at timestamp with time zone, gst_reference text, eps_status text, eps_registered boolean, eps_required boolean, card_eligible boolean, card_issued boolean, card_issued_at timestamp with time zone, card_times integer, permit_eligible boolean, permit_generated boolean, permit_printed boolean, permit_reference text, permit_generated_at timestamp with time zone, permit_printed_times integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH f AS (SELECT nullif(btrim(p_f->>'fac'), '') AS fac, nullif(btrim(p_f->>'dept'), '') AS dept, nullif(btrim(p_f->>'prog'), '') AS prog,
                      (nullif(btrim(p_f->>'level'), ''))::int AS lvl, nullif(btrim(p_f->>'type'), '') AS typ),
         cfg AS (SELECT coalesce((SELECT covers_eps FROM finance.gst_setting WHERE id = 1), true) AS covers_eps),
         r AS (SELECT x.* FROM f CROSS JOIN LATERAL reporting.exam_readiness(p_session, p_semester, f.fac, f.dept, f.prog, f.lvl, f.typ, NULL, 'CARD') x),
         g AS (SELECT * FROM finance.gst_population(p_session, p_semester)),
         -- a payment of the EPS fee of its own, where the GST fee does not cover it
         eps_pay AS (SELECT pr.student_id, sum(pr.amount) AS paid FROM finance.payment_reference pr
                      WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL AND pr.purpose ~* '^eps'
                        AND NOT (SELECT covers_eps FROM cfg) GROUP BY pr.student_id),
         card AS (SELECT c.student_id, c.first_at, c.times FROM registration.exam_card_issue c WHERE c.session = p_session AND c.semester = p_semester),
         pm AS (SELECT p.student_id, p.reference, p.generated_at, p.printed FROM registration.gst_eps_permit p
                 WHERE p.session = p_session AND p.semester = p_semester AND p.revoked_at IS NULL),
         m AS (
            SELECT r.student_id, r.matric_no, r.jamb_no, r.surname, r.other_names, r.sex, r.status, r.academic_status, r.programme_type, r.admission_route,
                   r.study_mode, st.centre_code, r.faculty_code, r.faculty, r.dept_code, r.department, r.programme_code, r.programme, r.level, r.entry_session,
                   r.fee_status, r.payable, r.paid_amount, r.outstanding, r.last_paid_at, coalesce(r.school_fees_paid, false) AS school_fees_paid,
                   coalesce(r.registered, false) AS registered, r.registration_status, coalesce(r.carryovers, 0) AS carryovers, coalesce(r.courses, 0) AS courses,
                   coalesce(r.units, 0) AS units,
                   coalesce(r.school_fees_paid, false) AND NOT coalesce(r.registered, false) AS paid_not_registered,
                   CASE WHEN g.student_id IS NULL OR NOT (coalesce(g.gst_required, false) OR coalesce(g.gst_registered, false) OR coalesce(g.paid, 0) > 0) THEN 'NOT_APPLICABLE'
                        WHEN g.entitled THEN 'PAID' WHEN coalesce(g.paid, 0) > 0 THEN 'PART_PAID' ELSE 'NOT_PAID' END AS gst_status,
                   coalesce(g.gst_registered, false) AS gst_registered, coalesce(g.gst_required, false) AS gst_required,
                   CASE WHEN coalesce(g.required, false) OR coalesce(g.paid, 0) > 0 THEN g.fee END AS gst_fee,
                   coalesce(g.paid, 0) AS gst_paid_amount,
                   CASE WHEN coalesce(g.required, false) AND NOT coalesce(g.entitled, false) THEN greatest(coalesce(g.fee, 0) - coalesce(g.paid, 0), 0) ELSE 0 END AS gst_outstanding,
                   g.paid_at AS gst_paid_at, g.reference AS gst_reference,
                   CASE WHEN g.student_id IS NULL OR NOT (coalesce(g.eps_required, false) OR coalesce(g.eps_registered, false)) THEN 'NOT_APPLICABLE'
                        WHEN (SELECT covers_eps FROM cfg) AND coalesce(g.entitled, false) THEN 'PAID'
                        WHEN NOT (SELECT covers_eps FROM cfg) AND ep.paid > 0 THEN 'PAID'
                        ELSE 'NOT_PAID' END AS eps_status,
                   coalesce(g.eps_registered, false) AS eps_registered, coalesce(g.eps_required, false) AS eps_required,
                   coalesce(r.exam_card, false) AS card_eligible, c.student_id IS NOT NULL AS card_issued, c.first_at AS card_issued_at, coalesce(c.times, 0) AS card_times,
                   -- the permit's own rule read on the register: a GST/EPS course on a submitted registration of the semester, the school fees
                   -- paid by the card's test, the GST fee paid where it is owed (V492, V589)
                   (coalesce(g.gst_registered, false) OR coalesce(g.eps_registered, false)) AND coalesce(r.school_fees_paid, false)
                       AND (NOT coalesce(g.required, false) OR coalesce(g.entitled, false)) AS permit_eligible,
                   pm.student_id IS NOT NULL AS permit_generated, coalesce(pm.printed, 0) > 0 AS permit_printed, pm.reference AS permit_reference,
                   pm.generated_at AS permit_generated_at, coalesce(pm.printed, 0) AS permit_printed_times
              FROM r
              JOIN people.student st ON st.id = r.student_id
              LEFT JOIN g ON g.student_id = r.student_id
              LEFT JOIN eps_pay ep ON ep.student_id = r.student_id
              LEFT JOIN card c ON c.student_id = r.student_id
              LEFT JOIN pm ON pm.student_id = r.student_id)
    SELECT m.* FROM m
     WHERE (nullif(p_f->>'sex', '') IS NULL OR upper(coalesce(m.sex, 'U')) = upper(p_f->>'sex'))
       AND (nullif(p_f->>'astatus', '') IS NULL OR m.academic_status = upper(p_f->>'astatus'))
       AND (nullif(p_f->>'route', '') IS NULL OR m.admission_route = upper(p_f->>'route'))
       AND (nullif(p_f->>'mode', '') IS NULL OR upper(coalesce(m.study_mode, '')) = upper(p_f->>'mode'))
       AND (nullif(p_f->>'centre', '') IS NULL OR upper(coalesce(m.centre_code, '')) = upper(p_f->>'centre'))
       AND (nullif(p_f->>'fee', '') IS NULL OR CASE upper(p_f->>'fee')
                WHEN 'PAID' THEN m.fee_status = 'FULLY_PAID' WHEN 'PART_PAID' THEN m.fee_status = 'PART_PAYMENT'
                WHEN 'NOT_PAID' THEN m.fee_status = 'NOT_PAID' WHEN 'NO_FEE_STATED' THEN m.fee_status = 'NO_CHARGE'
                WHEN 'ANY_PAYMENT' THEN m.school_fees_paid ELSE true END)
       AND (nullif(p_f->>'reg', '') IS NULL OR CASE upper(p_f->>'reg')
                WHEN 'REGISTERED' THEN m.registered WHEN 'NOT_REGISTERED' THEN NOT m.registered
                WHEN 'PAID_NOT_REGISTERED' THEN m.paid_not_registered WHEN 'CARRYOVER' THEN m.registered AND m.carryovers > 0 ELSE true END)
       AND (nullif(p_f->>'gst', '') IS NULL OR CASE upper(p_f->>'gst')
                WHEN 'PAID' THEN m.gst_status = 'PAID' WHEN 'NOT_PAID' THEN m.gst_status IN ('NOT_PAID', 'PART_PAID')
                WHEN 'REGISTERED' THEN m.gst_registered WHEN 'NOT_REGISTERED' THEN m.gst_status <> 'NOT_APPLICABLE' AND NOT m.gst_registered
                WHEN 'APPLICABLE' THEN m.gst_status <> 'NOT_APPLICABLE' ELSE true END)
       AND (nullif(p_f->>'eps', '') IS NULL OR CASE upper(p_f->>'eps')
                WHEN 'PAID' THEN m.eps_status = 'PAID' WHEN 'NOT_PAID' THEN m.eps_status = 'NOT_PAID'
                WHEN 'REGISTERED' THEN m.eps_registered WHEN 'NOT_REGISTERED' THEN m.eps_status <> 'NOT_APPLICABLE' AND NOT m.eps_registered
                WHEN 'APPLICABLE' THEN m.eps_status <> 'NOT_APPLICABLE' ELSE true END)
       AND (nullif(p_f->>'card', '') IS NULL OR CASE upper(p_f->>'card')
                WHEN 'ELIGIBLE' THEN m.card_eligible WHEN 'NOT_ELIGIBLE' THEN NOT m.card_eligible
                WHEN 'ISSUED' THEN m.card_issued WHEN 'NOT_ISSUED' THEN m.card_eligible AND NOT m.card_issued ELSE true END)
       AND (nullif(p_f->>'permit', '') IS NULL OR CASE upper(p_f->>'permit')
                WHEN 'ELIGIBLE' THEN m.permit_eligible WHEN 'GENERATED' THEN m.permit_generated WHEN 'PRINTED' THEN m.permit_printed
                WHEN 'NOT_PRINTED' THEN m.permit_eligible AND NOT m.permit_printed ELSE true END)
$function$;

-- reporting.payments: the one ledger of payments counts a student payment only while it is not archived
CREATE OR REPLACE VIEW reporting.payments AS  SELECT 'STUDENT'::text AS source,
    r.id AS payment_id,
    r.reference,
    r.receipt_no,
    r.purpose,
    NULL::text AS kind,
    k.code AS category_code,
    r.amount,
    r.generated_at,
    r.confirmed_at,
    r.expires_at,
    r.channel,
    r.session,
    st.id AS student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    st.id::text AS payer_key,
    st.surname,
    st.other_names,
    COALESCE(st.matric_no, st.admission_no) AS number,
    st.sex,
    st.entry_mode,
    st.entry_session,
    st.status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session) AS level,
    st.entry_mode = 'POSTGRADUATE'::text OR p.category = 'POST GRADUATE'::text AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    finance.admission_route_of(st.entry_mode) AS admission_route,
    st.study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
        CASE
            WHEN r.purpose ~* '(first|1st) semester'::text THEN 1
            WHEN r.purpose ~* '(second|2nd) semester'::text THEN 2
            ELSE NULL::integer
        END AS semester,
    st.jamb_reg_no,
    NULL::text AS application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN r.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN r.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM finance.payment_reference r
     JOIN people.student st ON st.id = r.student_id
     JOIN ref.programme p ON p.code = st.programme_code
     JOIN ref.faculty f ON f.code = p.faculty_code
     JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN finance.category_memo km ON km.kind = ''::text AND km.purpose = COALESCE(r.purpose, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(km.code, finance.categorise(NULL::text, r.purpose)) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     LEFT JOIN finance.programme_type_memo ptm ON ptm.entry_mode = COALESCE(st.entry_mode, ''::text) AND ptm.category = COALESCE(p.category, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(ptm.code, finance.programme_type_for(st.entry_mode, p.category)) AS code) pt
     LEFT JOIN finance.owner_memo om ON om.purpose = COALESCE(cat.purpose, 'OTHER'::text) AND om.programme_type = pt.code
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.source_module
                    ELSE ( SELECT o.source_module
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS source_module,
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.responsible_office
                    ELSE ( SELECT o.responsible_office
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS responsible_office) own
  WHERE r.archived_at IS NULL
UNION ALL
 SELECT 'APPLICANT'::text AS source,
    fr.id AS payment_id,
    fr.reference,
    fr.receipt_no,
    NULL::text AS purpose,
    fr.kind,
    k.code AS category_code,
    fr.amount,
    fr.generated_at,
    fr.confirmed_at,
    fr.expires_at,
    fr.channel,
    a.session,
    s.id AS student_id,
    a.id AS application_id,
    NULL::uuid AS pg_application_id,
    COALESCE(s.id::text, a.id::text) AS payer_key,
    c.surname,
    c.other_names,
    COALESCE(s.matric_no, s.admission_no, a.application_no) AS number,
    COALESCE(s.sex, cr.sex) AS sex,
    c.entry_mode,
    a.session AS entry_session,
    COALESCE(s.status, 'APPLICANT'::text) AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    c.entry_level AS level,
    false AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    finance.admission_route_of(c.entry_mode) AS admission_route,
        CASE
            WHEN c.entry_mode = 'CCE'::text THEN 'PART_TIME'::text
            ELSE 'FULL_TIME'::text
        END AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    c.jamb_reg_no,
    a.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN fr.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN fr.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM admissions.fee_reference fr
     JOIN admissions.application a ON a.id = fr.application_id
     JOIN admissions.candidate c ON c.id = a.candidate_id
     LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
     LEFT JOIN people.student s ON s.candidate_id = c.id
     LEFT JOIN ( SELECT DISTINCT ON (pn.name) pn.name,
            pn.code
           FROM ref.programme pn
          ORDER BY pn.name, pn.archived, pn.code) pnm ON pnm.name = c.programme
     LEFT JOIN ref.programme p ON p.code = pnm.code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN finance.category_memo km ON km.kind = COALESCE(fr.kind, ''::text) AND km.purpose = ''::text
     CROSS JOIN LATERAL ( SELECT COALESCE(km.code, finance.categorise(fr.kind, NULL::text)) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     LEFT JOIN finance.programme_type_memo ptm ON ptm.entry_mode = COALESCE(c.entry_mode, ''::text) AND ptm.category = COALESCE(p.category, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(ptm.code, finance.programme_type_for(c.entry_mode, p.category)) AS code) pt
     LEFT JOIN finance.owner_memo om ON om.purpose = COALESCE(cat.purpose, 'OTHER'::text) AND om.programme_type = pt.code
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.source_module
                    ELSE ( SELECT o.source_module
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS source_module,
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.responsible_office
                    ELSE ( SELECT o.responsible_office
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS responsible_office) own
UNION ALL
 SELECT 'PG'::text AS source,
    fr.id AS payment_id,
    fr.reference,
    NULL::text AS receipt_no,
    NULL::text AS purpose,
    'PG_'::text || fr.kind AS kind,
    k.code AS category_code,
    fr.amount,
    fr.generated_at,
    fr.confirmed_at,
    fr.expires_at,
    fr.channel,
    pa.session,
    pa.student_id,
    NULL::uuid AS application_id,
    pa.id AS pg_application_id,
    COALESCE(pa.student_id::text, pa.id::text) AS payer_key,
    ap.surname,
    ap.other_names,
    COALESCE(s.matric_no, s.admission_no, pa.application_no) AS number,
    COALESCE(s.sex, ap.sex) AS sex,
    'POSTGRADUATE'::text AS entry_mode,
    pa.session AS entry_session,
    COALESCE(s.status, pa.state) AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    COALESCE(s.current_level, pa.entry_level) AS level,
    true AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'POSTGRADUATE'::text AS admission_route,
    s.study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    NULL::text AS jamb_reg_no,
    pa.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN fr.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN fr.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM admissions.pg_fee_reference fr
     JOIN admissions.pg_application pa ON pa.id = fr.application_id
     JOIN admissions.pg_applicant ap ON ap.id = pa.applicant_id
     LEFT JOIN people.student s ON s.id = pa.student_id
     LEFT JOIN ref.programme p ON p.code = pa.programme_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('PG_'::text || fr.kind, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('POSTGRADUATE'::text, 'POST GRADUATE'::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true
UNION ALL
 SELECT 'JUPEB'::text AS source,
    jf.id AS payment_id,
    jf.reference,
    NULL::text AS receipt_no,
    NULL::text AS purpose,
    'JUPEB_'::text || jf.kind AS kind,
    k.code AS category_code,
    jf.amount,
    jf.created_at AS generated_at,
    jf.confirmed_at,
    jf.expires_at,
    jf.channel,
    jf.session,
    NULL::uuid AS student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    ja.id::text AS payer_key,
    ja.surname,
    concat_ws(' '::text, NULLIF(btrim(ja.first_name), ''::text), NULLIF(btrim(ja.middle_name), ''::text)) AS other_names,
    ja.application_no AS number,
    ja.sex,
    'JUPEB'::text AS entry_mode,
    ja.session AS entry_session,
    ja.state AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    NULL::integer AS level,
    false AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'JUPEB'::text AS admission_route,
    'FULL_TIME'::text AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    jf.semester,
    NULL::text AS jamb_reg_no,
    ja.application_no,
    ja.exam_no,
    ja.id AS jupeb_application_id,
        CASE
            WHEN jf.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN jf.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM jupeb.fee_reference jf
     JOIN jupeb.application ja ON ja.id = jf.application_id
     LEFT JOIN ref.programme p ON p.code = ja.programme_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('JUPEB_'::text || jf.kind, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('JUPEB'::text, NULL::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true;

COMMIT;
