-- ═══════════════════════════════════════════════════════════
-- V727 — inter-departmental transfers begun on the old portal continued on this one, the ₦20,000 fee read against every
--         verified payment (the old portal's and this portal's), final approval only when nothing is owed, and the
--         reconciliation the Bursary, ICT and the Academic Office read
--
--   The University's master prompt of 11 November 2026 ("LEGACY INTER-DEPARTMENTAL TRANSFER PAYMENT RECONCILIATION AND
--   OUTSTANDING BALANCE RECOVERY") and its decisions of 12 November 2026: the old portal's transfer payments made from
--   1 September 2025 belong to the current exercise; the transfer FORM, the PROVISIONAL LETTER and the TRANSFER items count
--   toward the one ₦20,000 fee (CHANGE OF COURSE does not; it is listed for the Bursary); the old portal's applications come
--   in by an upload of its export, and old-portal payments also credit an application made here; a part-paid application
--   moves through the desks, and only the Academic Office's final approval waits for the whole fee.
--
--   What stood: one fee_reference per application, returned unchanged forever, and "paid" meant that one reference
--   confirmed, whatever its amount — so the 2 applications paid here (one at ₦10,000) and every old-portal payment (336 of
--   them, ₦5.19m, imported as confirmed payments on the students' records with channel 'Legacy') were never read against the
--   ₦20,000 the Bursary states; the old portal's applications themselves were never brought in.
--
--   1 · finance.transfer_fee_revision: every statement of the transfer fee, kept (trigger on finance.fee_setting); a revision
--       closes the open transfer references drawn at another figure.
--   2 · people.legacy_transfer_setting (from which date old-portal payments count) and people.legacy_transfer_item (which of the
--       old portal's items count), both stated, never written into a rule.
--   3 · people.transfer_payment: every payment counted toward an application, this portal's and the old portal's — one payment
--       serves one application (payment_id UNIQUE); the old portal's rows are read where they are, never re-posted.
--   4 · people.transfer_entitlement(application): the fee as stated now, what is paid (this portal / the old portal), the
--       balance, any excess, whether a payment awaits the bank, the open reference and a band.
--   5 · people.transfer_fee_reference draws the reference for the balance (the whole fee before anything is paid), returns the
--       one still open for that amount, closes one drawn for another figure, refuses once settled (TRANSFER_FEE_SETTLED).
--   6 · people.approve_transfer: the current HOD acts once any verified payment stands; the Academic Office's final approval is
--       refused while anything is owed (TRANSFER_FEE_OUTSTANDING) or the payment that would settle it awaits the bank
--       (TRANSFER_PAYMENT_PENDING); people.effect_transfer (the V070 route) refuses alike. The stages are unchanged.
--   7 · people.legacy_transfer_payment: the reconciliation list — each old-portal transfer payment LINKED to an application,
--       AWAITING_APPLICATION (linked when the student applies), UNMATCHED (with the reason), NOT_COUNTED or OUT_OF_SCOPE; an
--       officer's decision (link, not counted, reject) is kept and never rebuilt over.
--   8 · people.transfer_legacy and the upload (check, then commit): the old portal's export brought in as applications at the
--       stage they reached, the old reference, dates, approvals and documents kept as received; its payment numbers link the
--       old-portal payments.
--   9 · people.transfer_fee_monitor(session) and people.legacy_transfer_report(): the monitor and the reconciliation report.
-- ═══════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V727: old-portal transfers continued, the ₦20,000 fee against every verified payment', true);

-- ── 1 · every statement of the transfer fee is kept ────────────────────────────────────────────────────
CREATE TABLE finance.transfer_fee_revision (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    fee           numeric(12,2) NULL,
    previous_fee  numeric(12,2) NULL,
    stated_at     timestamptz NOT NULL DEFAULT now(),
    stated_by     uuid NULL,
    stated_office text NULL,
    reason        text NULL
);
SELECT audit.attach('finance.transfer_fee_revision');
COMMENT ON TABLE finance.transfer_fee_revision IS
  'V727: every statement of the inter-departmental transfer fee (finance.fee_setting.transfer_fee, overwritten in place): the figure, the one before, '
  'who stated it, from which office, why. Written by the trigger; never changed or removed.';
CREATE FUNCTION finance.transfer_fee_revision_kept()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'TRANSFER_FEE_REVISION_KEPT: a statement of the transfer fee is kept as it was made' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_transfer_fee_revision_kept BEFORE UPDATE OR DELETE ON finance.transfer_fee_revision
    FOR EACH ROW EXECUTE FUNCTION finance.transfer_fee_revision_kept();
INSERT INTO finance.transfer_fee_revision (fee, stated_at, reason)
SELECT s.transfer_fee, now(), 'As stated before V727' FROM finance.fee_setting s WHERE s.id = 1;

-- ── 2 · which old-portal payments belong to the current exercise, stated ─────────────────────────────────
CREATE TABLE people.legacy_transfer_setting (
    id          int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    counts_from date NOT NULL,
    set_at      timestamptz NOT NULL DEFAULT now(),
    set_by      uuid NULL,
    set_office  text NULL,
    reason      text NULL
);
SELECT audit.attach('people.legacy_transfer_setting');
INSERT INTO people.legacy_transfer_setting (id, counts_from, reason)
VALUES (1, date '2025-09-01', 'The University''s decision of 12 November 2026: old-portal transfer payments made from 1 September 2025 belong to the current exercise');
COMMENT ON TABLE people.legacy_transfer_setting IS
  'V727: the date from which the old portal''s inter-departmental transfer payments count toward the current exercise (paid before it, they are OUT_OF_SCOPE on '
  'the reconciliation list). Set by the Academic Office, the Registry, the Bursary or ICT (people.set_legacy_transfer_scope); every change on the audit spine.';

CREATE TABLE people.legacy_transfer_item (
    item       text PRIMARY KEY,
    kind       text NOT NULL CHECK (kind IN ('FORM', 'LETTER', 'TRANSFER', 'CHANGE_OF_COURSE')),
    counts     boolean NOT NULL,
    set_at     timestamptz NOT NULL DEFAULT now(),
    reason     text NULL
);
SELECT audit.attach('people.legacy_transfer_item');
INSERT INTO people.legacy_transfer_item (item, kind, counts, reason) VALUES
    ('INTER DEPARTMENTAL TRANFER FORM', 'FORM', true, 'The University''s decision of 12 November 2026'),
    ('INTER DEPT. TRANSFER  PROVISIONAL LETTER', 'LETTER', true, 'The University''s decision of 12 November 2026'),
    ('INTER DEPT. TRANSFER', 'TRANSFER', true, 'The University''s decision of 12 November 2026'),
    ('CHANGE OF COURSE', 'CHANGE_OF_COURSE', false, 'The University''s decision of 12 November 2026: listed for the Bursary, not counted toward the transfer fee');
COMMENT ON TABLE people.legacy_transfer_item IS
  'V727: the old portal''s items, as its export named them (the purpose of an imported payment before " (legacy)"), that are inter-departmental transfer '
  'payments, and whether each counts toward the transfer fee. The inter-university items are a different process and are not here.';

CREATE FUNCTION people.set_legacy_transfer_scope(p_from date, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('academic', 'registrar', 'dregistrar', 'bursar', 'ict', 'super') THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_OFFICE: the Academic Office, the Registry, the Bursary or ICT states which old-portal payments count' USING ERRCODE = '23514';
    END IF;
    IF p_from IS NULL THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_SCOPE: a date is stated' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_REASON: say why (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    UPDATE people.legacy_transfer_setting SET counts_from = p_from, set_at = now(), set_by = p_actor, set_office = p_office, reason = btrim(p_reason) WHERE id = 1;
    PERFORM people.legacy_transfer_reconcile(NULL);
END $$;

-- ── 3 · every payment counted toward an application ─────────────────────────────────────────────────
CREATE TABLE people.transfer_payment (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES people.transfer_application(id) ON DELETE CASCADE,
    payment_id     uuid NOT NULL UNIQUE REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    source         text NOT NULL CHECK (source IN ('PORTAL', 'OLD_PORTAL')),
    stated_fee     numeric(12,2) NULL,
    linked_at      timestamptz NOT NULL DEFAULT now(),
    linked_by      uuid NULL,
    linked_office  text NULL,
    note           text NULL
);
CREATE INDEX ix_transfer_payment_application ON people.transfer_payment (application_id);
SELECT audit.attach('people.transfer_payment');
COMMENT ON TABLE people.transfer_payment IS
  'V727: every payment counted toward an inter-departmental transfer application — the references drawn on this portal (PORTAL) and the old portal''s imported '
  'payments (OLD_PORTAL, read where they are, never re-posted). One payment serves one application.';
-- this portal's references so far
INSERT INTO people.transfer_payment (application_id, payment_id, source, stated_fee, linked_at, note)
SELECT t.id, r.id, 'PORTAL', r.amount, coalesce(r.generated_at, now()), 'Linked by V727 from the application''s fee reference'
  FROM people.transfer_application t JOIN finance.payment_reference r ON r.reference = t.fee_reference
 WHERE t.fee_reference IS NOT NULL
ON CONFLICT (payment_id) DO NOTHING;

-- the fee a transfer was completed against, kept: a later revision of the fee never reopens a finished transfer
CREATE TABLE people.transfer_fee_settlement (
    application_id uuid PRIMARY KEY REFERENCES people.transfer_application(id) ON DELETE CASCADE,
    fee            numeric(12,2) NOT NULL,
    paid_total     numeric(12,2) NOT NULL,
    payments       int NOT NULL,
    settled_at     timestamptz NOT NULL DEFAULT now(),
    settled_by     uuid NULL
);
SELECT audit.attach('people.transfer_fee_settlement');
COMMENT ON TABLE people.transfer_fee_settlement IS
  'V727: the fee an inter-departmental transfer was completed against and what had been paid, written at the final approval: an effected transfer is '
  'read against it, never against a fee revised afterwards. Transfers effected before V727 have none and are read as settled by what they paid.';

-- ── 7 (table) · the reconciliation list of the old portal's transfer payments ─────────────────────────
CREATE TABLE people.legacy_transfer_payment (
    payment_id     uuid PRIMARY KEY REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    student_id     uuid NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session_label  text NULL,
    item           text NOT NULL,
    item_kind      text NOT NULL,
    amount         numeric(12,2) NOT NULL,
    payref         text NULL,
    paid_on        date NULL,
    channel        text NULL,
    status         text NOT NULL CHECK (status IN ('LINKED', 'AWAITING_APPLICATION', 'USED', 'UNMATCHED', 'NOT_COUNTED', 'OUT_OF_SCOPE', 'REJECTED')),
    match_method   text NULL CHECK (match_method IS NULL OR match_method IN ('IMPORT_MATRIC_PAYREF', 'OLD_PORTAL_EXPORT', 'MANUAL')),
    application_id uuid NULL REFERENCES people.transfer_application(id) ON DELETE SET NULL,
    reason         text NULL,
    moved_hint     boolean NOT NULL DEFAULT false,
    decided_at     timestamptz NULL,
    decided_by     uuid NULL,
    decided_office text NULL,
    decided_note   text NULL,
    built_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_legacy_transfer_payment_student ON people.legacy_transfer_payment (student_id);
CREATE INDEX ix_legacy_transfer_payment_status ON people.legacy_transfer_payment (status);
SELECT audit.attach('people.legacy_transfer_payment');
COMMENT ON TABLE people.legacy_transfer_payment IS
  'V727: the reconciliation list — one row per old-portal inter-departmental transfer payment (an imported payment on a student''s record whose item is in '
  'people.legacy_transfer_item): LINKED to an application, AWAITING_APPLICATION (the student has none yet; linked when one is made or loaded), UNMATCHED '
  '(with the reason: the record does not answer to the payment''s matric, no old payment number, a duplicate or inactive record…), NOT_COUNTED (an item that '
  'does not count, or an officer''s decision), OUT_OF_SCOPE (paid before the stated date), USED (it paid for the transfer the old portal approved, '
  'restored here: never a credit for another), REJECTED (an officer''s decision: it never counts). A decided '
  'row (decided_at) is never rebuilt over; moved_hint says the student already sits on a programme moved to (a transfer, a restored one or a swap) — a hint, '
  'never a decision.';

-- ── 8 (tables) · the old portal's applications, as its export gives them ──────────────────────────────
CREATE TABLE people.legacy_transfer_load (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    filename         text NULL,
    rows_read        int NOT NULL,
    loaded           int NOT NULL DEFAULT 0,
    attached         int NOT NULL DEFAULT 0,
    left_out         int NOT NULL DEFAULT 0,
    committed_at     timestamptz NOT NULL DEFAULT now(),
    committed_by     uuid NULL,
    committed_office text NULL
);
SELECT audit.attach('people.legacy_transfer_load');
COMMENT ON TABLE people.legacy_transfer_load IS
  'V727: an upload of the old portal''s inter-departmental transfer export — what was read, loaded as applications, attached to an application already here, left out.';

CREATE TABLE people.legacy_transfer_load_row (
    load_id        uuid NOT NULL REFERENCES people.legacy_transfer_load(id) ON DELETE CASCADE,
    row_no         int NOT NULL,
    legacy_ref     text NULL,
    raw            jsonb NOT NULL,
    status         text NOT NULL,
    reason         text NULL,
    student_id     uuid NULL REFERENCES people.student(id) ON DELETE CASCADE,
    application_id uuid NULL REFERENCES people.transfer_application(id) ON DELETE SET NULL,
    PRIMARY KEY (load_id, row_no)
);
SELECT audit.exempt('people.legacy_transfer_load_row', 'every row of an upload as read and what became of it; the load itself and the applications it made are audited');

CREATE TABLE people.transfer_legacy (
    application_id uuid PRIMARY KEY REFERENCES people.transfer_application(id) ON DELETE CASCADE,
    legacy_ref     text NOT NULL UNIQUE,
    applied_on     date NULL,
    stage          text NULL,
    approvals      text NULL,
    documents      text NULL,
    payrefs        text[] NOT NULL DEFAULT '{}',
    load_id        uuid NULL REFERENCES people.legacy_transfer_load(id) ON DELETE SET NULL,
    raw            jsonb NOT NULL,
    loaded_at      timestamptz NOT NULL DEFAULT now(),
    loaded_by      uuid NULL
);
SELECT audit.attach('people.transfer_legacy');
COMMENT ON TABLE people.transfer_legacy IS
  'V727: the old portal''s record of an inter-departmental transfer application continued here — its reference, the date applied, the stage it reached, the '
  'approvals and documents as the export gave them, its payment numbers — kept as received beside the application (people.transfer_application gains no column).';
CREATE FUNCTION people.transfer_legacy_kept()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN coalesce(NEW, OLD); END IF;
    RAISE EXCEPTION 'TRANSFER_LEGACY_KEPT: the old portal''s record of a transfer is kept as received' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_transfer_legacy_kept BEFORE UPDATE ON people.transfer_legacy
    FOR EACH ROW EXECUTE FUNCTION people.transfer_legacy_kept();

-- ── 4 · the fee as stated now, what is paid, the balance ──────────────────────────────────────────────
CREATE FUNCTION people.transfer_live_states()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT ARRAY['APPLIED','FROM_OK','TO_OK','REG_OK','RECOMMENDED','APPROVED'] $$;

CREATE FUNCTION people.transfer_entitlement(p_app uuid)
RETURNS TABLE (fee_due numeric, portal_paid numeric, old_portal_paid numeric, paid_total numeric, balance numeric, excess numeric, payments int,
               settled boolean, pending boolean, open_reference text, open_amount numeric, open_expires_at timestamptz, band text)
LANGUAGE sql STABLE AS $$
    WITH app AS (SELECT t.state FROM people.transfer_application t WHERE t.id = p_app),
    paid AS (
        -- verified: confirmed and not archived for review (V670), net of the refunds approved or paid against it (as V367 for GST); an
        -- old-portal payment only while its reconciliation row is LINKED
        SELECT coalesce(sum(r.amount - x.refunded) FILTER (WHERE tp.source = 'PORTAL'), 0) AS portal,
               coalesce(sum(r.amount - x.refunded) FILTER (WHERE tp.source = 'OLD_PORTAL'), 0) AS old,
               count(*)::int AS n
          FROM people.transfer_payment tp
          JOIN finance.payment_reference r ON r.id = tp.payment_id
          CROSS JOIN LATERAL (SELECT finance.gst_refunded(r.reference) AS refunded) x
         WHERE tp.application_id = p_app AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.amount > x.refunded
           AND (tp.source = 'PORTAL' OR EXISTS (SELECT 1 FROM people.legacy_transfer_payment l WHERE l.payment_id = tp.payment_id AND l.status = 'LINKED'))),
    open_ref AS (
        SELECT r.reference, r.amount, r.expires_at
          FROM people.transfer_payment tp JOIN finance.payment_reference r ON r.id = tp.payment_id
         WHERE tp.application_id = p_app AND tp.source = 'PORTAL' AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
         ORDER BY r.generated_at DESC LIMIT 1),
    -- the fee as stated now; an effected transfer is read against the fee it was completed against (before V727: what it paid); a closed
    -- application (declined, not recommended, withdrawn) owes nothing more
    fee AS (SELECT CASE WHEN app.state = 'EFFECTED'
                        THEN coalesce((SELECT f.fee FROM people.transfer_fee_settlement f WHERE f.application_id = p_app), paid.portal + paid.old)
                        ELSE people.transfer_fee() END AS fee,
                   app.state IN ('DECLINED', 'NOT_RECOMMENDED', 'WITHDRAWN') AS closed
              FROM app, paid),
    x AS (SELECT fee.fee, fee.closed, paid.portal, paid.old, paid.portal + paid.old AS total, paid.n,
                 CASE WHEN fee.fee IS NULL THEN NULL WHEN fee.closed THEN 0 ELSE greatest(fee.fee - paid.portal - paid.old, 0) END AS balance
            FROM fee, paid)
    SELECT x.fee, x.portal, x.old, x.total, x.balance,
           CASE WHEN x.fee IS NULL OR x.closed THEN 0 ELSE greatest(x.total - x.fee, 0) END,
           x.n,
           x.fee IS NOT NULL AND (x.closed OR x.total >= x.fee),
           -- a payment awaits the bank: a reference open for what is owed now
           coalesce(x.balance > 0 AND o.amount = x.balance, false),
           o.reference, o.amount, o.expires_at,
           CASE WHEN x.closed THEN 'CLOSED'
                WHEN x.fee IS NULL THEN 'FEE_NOT_STATED'
                WHEN x.fee = 0 THEN 'NO_FEE'
                WHEN x.total = 0 AND x.balance > 0 AND o.amount = x.balance THEN 'PENDING'
                WHEN x.total = 0 THEN 'NOT_PAID'
                WHEN x.total < x.fee THEN 'PART_PAID'
                WHEN x.total > x.fee THEN 'OVERPAID'
                WHEN x.n > 1 THEN 'SETTLED_IN_PARTS'
                ELSE 'PAID_IN_FULL' END
      FROM x LEFT JOIN open_ref o ON true
$$;
COMMENT ON FUNCTION people.transfer_entitlement(uuid) IS
  'V727: an inter-departmental transfer application''s fee as stated now (people.transfer_fee; an effected one, the fee it was completed against), what is paid — '
  'this portal''s references and the old portal''s linked payments, verified only and net of refunds — the balance, any excess, the payments, whether a '
  'reference open for the balance awaits the bank (pending), the newest open reference and a band (CLOSED for a declined, not recommended or withdrawn '
  'application, which owes nothing more; FEE_NOT_STATED; NO_FEE (effected before V727 with nothing paid); NOT_PAID, PENDING, PART_PAID, SETTLED_IN_PARTS, '
  'PAID_IN_FULL, OVERPAID).';

-- a reference open for another figure than what is owed now is closed: a link, a decision, a revised fee or the application's end
CREATE FUNCTION people.transfer_close_stale_references(p_app uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_state text; v_balance numeric; n int;
BEGIN
    SELECT t.state INTO v_state FROM people.transfer_application t WHERE t.id = p_app;
    IF v_state = ANY (people.transfer_live_states()) THEN
        v_balance := (SELECT e.balance FROM people.transfer_entitlement(p_app) e);
    END IF;
    UPDATE finance.payment_reference r SET expires_at = now()
      FROM people.transfer_payment tp
     WHERE tp.payment_id = r.id AND tp.application_id = p_app AND tp.source = 'PORTAL' AND r.confirmed_at IS NULL AND r.expires_at > now()
       AND (v_balance IS NULL OR v_balance < 1 OR r.amount <> v_balance);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION people.transfer_close_stale_references(uuid) IS
  'V727: closes an application''s open transfer references that are no longer for what is owed (the balance changed, nothing is owed, or the application '
  'is no longer live), so a stale reference is never paid. Run on every change of the links, on a revised fee and when the application leaves the desks.';

-- the revision trigger, now that the balance can be read: a revised fee closes the open references drawn at another figure
CREATE FUNCTION finance.transfer_fee_revised()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.transfer_fee IS NOT DISTINCT FROM OLD.transfer_fee THEN RETURN NULL; END IF;
    INSERT INTO finance.transfer_fee_revision (fee, previous_fee, stated_by, stated_office, reason)
    VALUES (NEW.transfer_fee, OLD.transfer_fee, nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''), nullif(btrim(current_setting('moaum.reason', true)), ''));
    PERFORM people.transfer_close_stale_references(a.application_id)
       FROM (SELECT DISTINCT tp.application_id FROM people.transfer_payment tp JOIN finance.payment_reference r ON r.id = tp.payment_id
              WHERE tp.source = 'PORTAL' AND r.confirmed_at IS NULL AND r.expires_at > now()) a;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_transfer_fee_revised AFTER UPDATE OF transfer_fee ON finance.fee_setting
    FOR EACH ROW EXECUTE FUNCTION finance.transfer_fee_revised();

-- a transfer reference confirmed (late at the bank, or by the Bursary) leaves no other reference open for the old balance
CREATE FUNCTION finance.transfer_reference_confirmed()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM people.transfer_close_stale_references(tp.application_id) FROM people.transfer_payment tp WHERE tp.payment_id = NEW.id;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_transfer_reference_confirmed AFTER UPDATE OF confirmed_at ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.confirmed_at IS NULL AND NEW.confirmed_at IS NOT NULL AND NEW.purpose LIKE 'Inter-departmental transfer%')
    EXECUTE FUNCTION finance.transfer_reference_confirmed();

-- an application that leaves the desks (effected, declined, withdrawn) leaves no reference payable
CREATE FUNCTION people.transfer_application_closes_references()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state IS DISTINCT FROM OLD.state AND NOT (NEW.state = ANY (people.transfer_live_states())) THEN
        PERFORM people.transfer_close_stale_references(NEW.id);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_transfer_application_closes_references AFTER UPDATE OF state ON people.transfer_application
    FOR EACH ROW EXECUTE FUNCTION people.transfer_application_closes_references();

-- ── 5 · the reference for the balance ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.transfer_fee_reference(p_id uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE t people.transfer_application; v_name text; v_ref text; v_fee numeric; ent record;
BEGIN
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state NOT IN ('APPLIED','FROM_OK','TO_OK','REG_OK','RECOMMENDED','APPROVED') THEN
        RAISE EXCEPTION 'application % is not open for payment', p_id USING ERRCODE = '23514';
    END IF;
    v_fee := people.transfer_fee();
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'the inter-departmental transfer fee has not been set by the Bursary'
            USING ERRCODE = '23514',
                  HINT = 'The Bursary sets it on Finance → Fees before a transfer can be paid.';
    END IF;
    -- V727: what is owed is the fee as stated now less every verified payment (this portal's and the old portal's): the balance,
    -- which is the whole fee before anything is paid
    SELECT * INTO ent FROM people.transfer_entitlement(p_id);
    IF ent.balance <= 0 THEN
        RAISE EXCEPTION 'TRANSFER_FEE_SETTLED: the transfer fee of ₦% is paid in full; nothing more is owed', to_char(v_fee, 'FM999,999,990')
            USING ERRCODE = '23514', HINT = 'Nothing more is owed for the transfer.';
    END IF;
    -- a reference still open for what is owed is the one to pay, never a second; one drawn for another figure is closed
    SELECT r.reference INTO v_ref
      FROM people.transfer_payment tp JOIN finance.payment_reference r ON r.id = tp.payment_id
     WHERE tp.application_id = p_id AND tp.source = 'PORTAL' AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
       AND r.amount = ent.balance
     ORDER BY r.generated_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    UPDATE finance.payment_reference r SET expires_at = least(r.expires_at, now())
      FROM people.transfer_payment tp
     WHERE tp.payment_id = r.id AND tp.application_id = p_id AND tp.source = 'PORTAL' AND r.confirmed_at IS NULL AND r.expires_at > now();
    SELECT name INTO v_name FROM ref.programme WHERE code = t.to_programme_code;
    v_ref := finance.new_purpose_reference(t.student_id, t.session, ent.balance,
                'Inter-departmental transfer to ' || coalesce(v_name, t.to_programme_code));
    INSERT INTO people.transfer_payment (application_id, payment_id, source, stated_fee, linked_by, linked_office)
    SELECT p_id, r.id, 'PORTAL', v_fee, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), '')
      FROM finance.payment_reference r WHERE r.reference = v_ref;
    IF t.fee_reference IS NULL THEN
        UPDATE people.transfer_application SET fee_reference = v_ref WHERE id = p_id;
    END IF;
    RETURN v_ref;
END $function$;

-- ── 6 · the desks: the HOD once anything is paid; the final approval only when nothing is owed ─────────────
CREATE OR REPLACE FUNCTION people.approve_transfer(p_id uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application; ent record;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a transfer is approved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such transfer application' USING ERRCODE = '23503'; END IF;
    -- V727: what is paid, verified, this portal's and the old portal's, against the fee as stated now
    SELECT * INTO ent FROM people.transfer_entitlement(p_id);
    IF t.state = 'APPLIED' THEN
        -- the University's decision of 12 November 2026: any verified payment lets the desks act; the balance waits for the final approval
        IF coalesce(ent.paid_total, 0) <= 0 THEN
            RAISE EXCEPTION 'TRANSFER_FEE_UNPAID: the non-refundable processing fee has not been paid' USING ERRCODE = '23514',
                HINT = 'The student pays the fee before the current department approves.';
        END IF;
        UPDATE people.transfer_application SET state = 'FROM_OK', from_dept_at = now(), from_dept_by = who WHERE id = p_id;
        RETURN 'FROM_OK';
    ELSIF t.state = 'FROM_OK' THEN
        UPDATE people.transfer_application SET state = 'TO_OK', to_dept_at = now(), to_dept_by = who WHERE id = p_id;
        RETURN 'TO_OK';
    ELSIF t.state = 'TO_OK' THEN
        UPDATE people.transfer_application SET state = 'REG_OK', reg_at = now(), reg_by = who WHERE id = p_id;
        RETURN 'REG_OK';
    ELSIF t.state = 'REG_OK' THEN
        PERFORM people.transfer_fee_settled_or_refuse(p_id, ent);
        INSERT INTO people.transfer_fee_settlement (application_id, fee, paid_total, payments, settled_by) VALUES (p_id, ent.fee_due, ent.paid_total, ent.payments, who);
        UPDATE people.student SET programme_code = t.to_programme_code,
               current_level = coalesce(t.recommended_level, current_level)
         WHERE id = t.student_id;
        UPDATE people.transfer_application SET state = 'EFFECTED', acad_at = now(), acad_by = who,
               effected_at = now(), effected_by = who WHERE id = p_id;
        RETURN 'EFFECTED';
    ELSE
        RAISE EXCEPTION 'application % has no approval pending at this stage (%).', p_id, t.state USING ERRCODE = '23514';
    END IF;
END $function$;

-- the one refusal both final doors give: the fee not stated, owed, or awaiting the bank
CREATE FUNCTION people.transfer_fee_settled_or_refuse(p_id uuid, ent record)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF ent.fee_due IS NULL THEN
        RAISE EXCEPTION 'TRANSFER_FEE_NOT_STATED: the Bursary has not stated the inter-departmental transfer fee' USING ERRCODE = '23514';
    END IF;
    IF ent.balance > 0 AND ent.pending THEN
        RAISE EXCEPTION 'TRANSFER_PAYMENT_PENDING: the transfer is completed once the fee of ₦% is paid in full; ₦% remains, and a payment of ₦% awaits the bank''s confirmation',
            to_char(ent.fee_due, 'FM999,999,990'), to_char(ent.balance, 'FM999,999,990'), to_char(ent.open_amount, 'FM999,999,990')
            USING ERRCODE = '23514', HINT = 'The final approval follows the bank''s confirmation of the payment.';
    END IF;
    IF ent.balance > 0 THEN
        RAISE EXCEPTION 'TRANSFER_FEE_OUTSTANDING: the transfer is completed once the fee of ₦% is paid in full; ₦% remains',
            to_char(ent.fee_due, 'FM999,999,990'), to_char(ent.balance, 'FM999,999,990')
            USING ERRCODE = '23514', HINT = 'The student pays the balance on the transfer page; the final approval follows.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION people.effect_transfer(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application; ent record;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the register is changed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state <> 'APPROVED' THEN RAISE EXCEPTION 'application % is not approved', p_id USING ERRCODE = '23514'; END IF;
    -- V727: the fee as stated now, paid in full and verified (this portal's and the old portal's payments), as at the Academic Office's desk
    SELECT * INTO ent FROM people.transfer_entitlement(p_id);
    PERFORM people.transfer_fee_settled_or_refuse(p_id, ent);
    INSERT INTO people.transfer_fee_settlement (application_id, fee, paid_total, payments, settled_by) VALUES (p_id, ent.fee_due, ent.paid_total, ent.payments, who);
    UPDATE people.student SET programme_code = t.to_programme_code, current_level = coalesce(t.recommended_level, current_level)
     WHERE id = t.student_id;
    UPDATE people.transfer_application SET state = 'EFFECTED', effected_at = now(), effected_by = who WHERE id = p_id;
END $function$;

-- the desk's list, with what is owed and the old portal's record of it (V185's columns, then V727's)
DROP FUNCTION IF EXISTS people.transfer_list(text, text);
CREATE FUNCTION people.transfer_list(p_session text, p_state text)
 RETURNS TABLE(id uuid, student_id uuid, name text, matric_no text, from_programme text, from_dept text, from_level integer, to_programme text, to_dept text,
               mode_of_entry text, utme_score integer, cgpa numeric, reason text, state text, recommended_level integer, committee_note text, senate_note text,
               decline_note text, withdrawn_why text, applied_at timestamptz, from_dept_at timestamptz, to_dept_at timestamptz, reg_at timestamptz,
               acad_at timestamptz, effected_at timestamptz, fee_reference text, fee_confirmed_at timestamptz, session text,
               fee_due numeric, paid_total numeric, old_portal_paid numeric, balance numeric, pending boolean, band text, legacy_ref text,
               legacy_applied_on date, legacy_stage text, legacy_approvals text, legacy_documents text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT t.id, t.student_id, s.surname || ', ' || s.other_names, s.matric_no,
           fp.name, fp.dept_code, t.from_level, tp.name, tp.dept_code,
           t.mode_of_entry, t.utme_score, t.cgpa, t.reason, t.state,
           t.recommended_level, t.committee_note, t.senate_note, t.decline_note, t.withdrawn_why,
           t.applied_at, t.from_dept_at, t.to_dept_at, t.reg_at, t.acad_at, t.effected_at,
           t.fee_reference, fs.confirmed_at, t.session,
           e.fee_due, e.paid_total, e.old_portal_paid, e.balance, e.pending, e.band, lg.legacy_ref,
           lg.applied_on, lg.stage, lg.approvals, lg.documents
      FROM people.transfer_application t
      JOIN people.student s ON s.id = t.student_id
      LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
      LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
      LEFT JOIN LATERAL finance.reference_state(t.fee_reference) fs ON t.fee_reference IS NOT NULL
      LEFT JOIN LATERAL people.transfer_entitlement(t.id) e ON true
      LEFT JOIN people.transfer_legacy lg ON lg.application_id = t.id
     WHERE (p_session IS NULL OR t.session = p_session)
       AND (p_state IS NULL OR t.state = p_state)
     ORDER BY t.applied_at
$function$;

-- ── 6b · the reference renewed, archived or corrected only as the links allow ──────────────────────────────
-- V727: renewed while still for the balance (from V690)
CREATE OR REPLACE FUNCTION finance.renew_reference(p_student uuid, p_reference text)
 RETURNS TABLE(reference_out text, amount_out numeric, until_out timestamp with time zone, purpose_out text, outcome text)
 LANGUAGE plpgsql
AS $function$
DECLARE v_transfer uuid; te record; r finance.payment_reference; o finance.payment_reference; v_until timestamptz := now() + interval '24 hours'; v_new text;
        pos record; win record; e record; t record; al hostel.allocation; v_ref text := upper(btrim(coalesce(p_reference, '')));
BEGIN
    SELECT * INTO r FROM finance.payment_reference x WHERE x.reference = v_ref FOR UPDATE;
    IF NOT FOUND OR r.student_id IS DISTINCT FROM p_student THEN
        RAISE EXCEPTION 'REFERENCE_NOT_FOUND: no payment reference % of yours', v_ref USING ERRCODE = 'P0002';
    END IF;
    IF r.confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'REFERENCE_PAID: reference % is paid (receipt %); there is nothing to pay again', r.reference, coalesce(r.receipt_no, '—') USING ERRCODE = '23514';
    END IF;
    -- still payable: nothing to renew
    IF r.expires_at > now() THEN
        RETURN QUERY SELECT r.reference, r.amount, r.expires_at, r.purpose, 'OPEN'::text;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('renew-reference:' || p_student::text));

    IF r.purpose LIKE 'School fees%' THEN
        -- as for a new school-fees reference (finance.new_reference, V602, V269, V288)
        IF finance.closed_for_fees(p_student, r.session) THEN
            RAISE EXCEPTION 'SCHOOL_FEES_CLOSED_GRADUATED: This academic record has been marked as graduated. New school-fee payments are not available for this academic enrollment.'
                USING ERRCODE = '23514';
        END IF;
        PERFORM admissions.screening_refuse_student(p_student, 'SCHOOL FEES');
        SELECT * INTO win FROM policy.window_state('SCHOOL_FEES_PAYMENT', r.session, NULL);
        IF win.state <> 'OPEN' THEN
            RAISE EXCEPTION 'SCHOOL_FEES_PAYMENT_CLOSED: school fees payment is currently % for %', lower(win.state), r.session USING ERRCODE = '23514',
                HINT = CASE WHEN win.state = 'SCHEDULED' THEN 'It opens on ' || to_char(win.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' ELSE 'The Directorate of ICT opens the payment window.' END;
        END IF;
        SELECT * INTO o FROM finance.payment_reference x
         WHERE x.student_id = p_student AND x.session = r.session AND x.purpose LIKE 'School fees%' AND x.confirmed_at IS NULL AND x.expires_at > now()
         ORDER BY x.generated_at DESC LIMIT 1;
        IF FOUND THEN
            RETURN QUERY SELECT o.reference, o.amount, o.expires_at, o.purpose, 'OPEN'::text;
            RETURN;
        END IF;
        SELECT * INTO pos FROM finance.position(p_student, r.session);
        IF coalesce(pos.balance, 0) < 1 THEN
            RAISE EXCEPTION 'REFERENCE_NOTHING_OWED: the school fees for % are paid; reference % is not needed', r.session, r.reference USING ERRCODE = '23514';
        END IF;
        IF r.amount > pos.balance THEN
            v_new := finance.new_reference(p_student, r.session, pos.balance, r.purpose);
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'NEW'::text FROM finance.payment_reference x WHERE x.reference = v_new;
            RETURN;
        END IF;
    ELSIF r.purpose LIKE 'GST fee %' THEN
        SELECT * INTO e FROM finance.gst_entitlement(p_student, r.session);
        IF e.state = 'PAID' THEN
            RAISE EXCEPTION 'GST_ALREADY_PAID: the GST fee for % is paid in full (receipt %)', r.session, coalesce(e.receipt_no, e.reference) USING ERRCODE = '23514';
        END IF;
        -- V643: owed, or shown a GST/EPS course on the registration page (finance.gst_payable_courses)
        -- V690: or a GST/EPS course they may add as a carry-over
        IF (NOT e.required AND NOT EXISTS (SELECT 1 FROM finance.gst_payable_courses(p_student, r.session))
                           AND NOT EXISTS (SELECT 1 FROM finance.gst_carry_payable(p_student, r.session)))
           OR NOT e.stated OR coalesce(e.fee, 0) - coalesce(e.paid, 0) < 1 THEN
            RAISE EXCEPTION 'REFERENCE_NOTHING_OWED: no GST fee is owed for %; reference % is not needed', r.session, r.reference USING ERRCODE = '23514';
        END IF;
        IF e.open_reference IS NOT NULL THEN
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'OPEN'::text FROM finance.payment_reference x WHERE x.reference = e.open_reference;
            RETURN;
        END IF;
        IF r.amount <> e.fee - e.paid THEN
            v_new := finance.new_gst_reference(p_student, r.session);
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'NEW'::text FROM finance.payment_reference x WHERE x.reference = v_new;
            RETURN;
        END IF;
    ELSIF r.purpose LIKE 'Wallet top-up%' THEN
        SELECT * INTO t FROM finance.topup_eligibility(p_student, r.session);
        IF t.open_reference IS NOT NULL THEN
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'OPEN'::text FROM finance.payment_reference x WHERE x.reference = t.open_reference;
            RETURN;
        END IF;
        IF NOT t.allowed THEN
            RAISE EXCEPTION 'REFERENCE_TOPUP_REFUSED: the wallet takes no top-up for % now (%)', r.session, lower(replace(coalesce(t.reason, 'not allowed'), '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.amount > t.max_topup THEN
            RAISE EXCEPTION 'REFERENCE_TOPUP_AMOUNT: the wallet takes at most NGN % for % now; start a top-up of that on the wallet page', to_char(t.max_topup, 'FM999,999,999,990.00'), r.session USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Transcript %' THEN
        IF NOT EXISTS (SELECT 1 FROM credentials.transcript_request q WHERE q.reference = r.reference AND q.paid_at IS NULL AND q.closed_at IS NULL) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the request reference % pays for is paid, cancelled or closed', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Hostel accommodation fine %' THEN
        IF NOT EXISTS (SELECT 1 FROM hostel.sanction sn WHERE sn.id::text = split_part(r.purpose, ' ', 5) AND sn.settled_at IS NULL AND sn.waived_at IS NULL AND sn.state = 'IN_FORCE') THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the hostel fine reference % pays for is settled, waived or quashed', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Hostel accommodation damage%' THEN
        IF NOT EXISTS (SELECT 1 FROM hostel.damage_charge dc WHERE dc.reference = r.reference AND dc.settled_at IS NULL AND dc.waived_at IS NULL) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the damage charge reference % pays for is settled or waived', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Hostel accommodation%' THEN
        SELECT * INTO al FROM hostel.allocation a WHERE a.reference = r.reference ORDER BY a.allocated_at DESC LIMIT 1;
        IF NOT FOUND OR coalesce(al.fee_status, 'PAYABLE') = 'PAID' OR al.ended_at IS NOT NULL OR al.lapsed_at IS NOT NULL
           OR al.state IN ('DECLINED', 'CANCELLED', 'TRANSFERRED', 'LAPSED', 'CHECKED_OUT') THEN
            RAISE EXCEPTION 'REFERENCE_HOSTEL_HOLD_ENDED: the bed reference % paid for is no longer held for you; reserve again on Hostel', r.reference USING ERRCODE = '23514';
        END IF;
        -- a held bed is paid for within its hold, never after it: the reference lasts no longer than the hold
        IF al.state = 'HELD' AND al.held_until IS NOT NULL THEN
            IF al.held_until <= now() THEN
                RAISE EXCEPTION 'REFERENCE_HOSTEL_HOLD_ENDED: the hold on the bed reference % paid for ended on %; reserve again on Hostel', r.reference,
                    to_char(al.held_until AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI') USING ERRCODE = '23514';
            END IF;
            v_until := least(v_until, al.held_until);
        END IF;
    ELSIF r.purpose LIKE 'Library fine%' THEN
        IF NOT EXISTS (SELECT 1 FROM library.loan l WHERE l.fine_reference = r.reference AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the library fine reference % pays for is settled or waived', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Deferment application fee%' THEN
        IF NOT EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = r.reference AND f.state = 'PENDING') THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the deferment fee reference % pays for is no longer pending', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Inter-departmental transfer%' THEN
        -- V727: the application it is linked to stands; the reference is for what is owed now (the fee as stated now less every verified
        -- payment) — the one open for that is returned, one for another figure is replaced by the reference for the balance
        SELECT tp.application_id INTO v_transfer FROM people.transfer_payment tp JOIN people.transfer_application ta ON ta.id = tp.application_id
         WHERE tp.payment_id = r.id AND tp.source = 'PORTAL' AND ta.state = ANY (people.transfer_live_states());
        IF v_transfer IS NULL THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the transfer reference % pays for is withdrawn, declined or done', r.reference USING ERRCODE = '23514';
        END IF;
        SELECT * INTO te FROM people.transfer_entitlement(v_transfer);
        IF te.balance IS NULL OR te.balance < 1 THEN
            RAISE EXCEPTION 'REFERENCE_NOTHING_OWED: the transfer fee is paid; reference % is not needed', r.reference USING ERRCODE = '23514';
        END IF;
        IF te.pending AND te.open_reference IS NOT NULL THEN
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'OPEN'::text FROM finance.payment_reference x WHERE x.reference = te.open_reference;
            RETURN;
        END IF;
        IF r.amount <> te.balance THEN
            v_new := people.transfer_fee_reference(v_transfer);
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'NEW'::text FROM finance.payment_reference x WHERE x.reference = v_new;
            RETURN;
        END IF;
    ELSE
        RAISE EXCEPTION 'REFERENCE_NOT_RENEWABLE: reference % (%) is renewed by the office that raised it', r.reference, r.purpose USING ERRCODE = '23514',
            HINT = 'Ask the Bursary.';
    END IF;

    -- the same reference, payable again
    UPDATE finance.payment_reference x SET expires_at = v_until WHERE x.id = r.id;
    RETURN QUERY SELECT r.reference, r.amount, v_until, r.purpose, 'REOPENED'::text;
END $function$;

-- V727: every payment counted toward a transfer that stands (from V670)
CREATE OR REPLACE FUNCTION finance.payment_archive_refusals(p_payment uuid)
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
    IF EXISTS (SELECT 1 FROM people.legacy_transfer_payment l WHERE l.payment_id = r.id AND l.status IN ('LINKED', 'AWAITING_APPLICATION', 'USED')) THEN
        refusals := refusals || 'PAR_LINKED: the payment is an old-portal inter-departmental transfer payment that counts toward a transfer (Old-portal transfers); it is decided there first'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM people.transfer_application t
                WHERE (t.fee_reference = r.reference OR t.id IN (SELECT tp.application_id FROM people.transfer_payment tp WHERE tp.payment_id = r.id))
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

-- V727: the same for a correction (from V670)
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
    IF EXISTS (SELECT 1 FROM people.legacy_transfer_payment l WHERE l.payment_id = r.id AND l.status IN ('LINKED', 'AWAITING_APPLICATION', 'USED')) THEN
        refusals := refusals || 'REALLOC_LINKED: the payment is an old-portal inter-departmental transfer payment that counts toward a transfer (Old-portal transfers); it is decided there first'::text;
    END IF;
    SELECT t.id, t.state INTO v_ta FROM people.transfer_application t
     WHERE (t.fee_reference = r.reference OR t.id IN (SELECT tp.application_id FROM people.transfer_payment tp WHERE tp.payment_id = r.id)) AND t.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED', 'EFFECTED') LIMIT 1;
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

-- ── 7 · the reconciliation of the old portal's transfer payments ─────────────────────────────────────
CREATE FUNCTION people.legacy_transfer_reconcile(p_student uuid)
RETURNS TABLE (status text, payments int) LANGUAGE plpgsql AS $$
DECLARE v_from date := (SELECT s.counts_from FROM people.legacy_transfer_setting s WHERE s.id = 1);
        r record; s people.student; v_status text; v_reason text; v_app uuid; v_payref text; v_paid_on date; v_kind text; v_counts boolean;
        v_method text; v_moved boolean; v_named uuid; v_existing uuid; v_existing_state text; v_restored text;
BEGIN
    FOR r IN
        SELECT p.id, p.student_id, p.session, p.amount, p.reference, p.confirmed_at, p.archived_at, p.note,
               regexp_replace(p.purpose, ' \(legacy\).*$', '') AS item,
               (SELECT lp.payref FROM finance.legacy_payref lp WHERE lp.reference = p.reference ORDER BY lp.recorded_at LIMIT 1) AS payref
          FROM finance.payment_reference p
         WHERE p.channel = 'Legacy' AND p.confirmed_at IS NOT NULL
           AND (p_student IS NULL OR p.student_id = p_student)
           AND regexp_replace(p.purpose, ' \(legacy\).*$', '') IN (SELECT i.item FROM people.legacy_transfer_item i)
         ORDER BY p.student_id, p.confirmed_at
    LOOP
        -- one student's payments are decided by one run at a time (a run for everyone and a student's new application)
        IF r.student_id IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtext('legacy-transfer:' || r.student_id::text)); END IF;
        -- an officer's decision stands; the list is never rebuilt over it
        CONTINUE WHEN EXISTS (SELECT 1 FROM people.legacy_transfer_payment l WHERE l.payment_id = r.id AND l.decided_at IS NOT NULL);
        SELECT i.kind, i.counts INTO v_kind, v_counts FROM people.legacy_transfer_item i WHERE i.item = r.item;
        s := NULL;
        SELECT * INTO s FROM people.student st WHERE st.id = r.student_id;
        v_payref := upper(coalesce(r.payref, substring(r.note FROM 'old ref (PR[0-9A-Za-z]+)')));
        v_paid_on := (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date;
        v_app := NULL; v_reason := NULL; v_method := NULL; v_named := NULL; v_existing := NULL; v_existing_state := NULL; v_restored := NULL;
        v_moved := s.id IS NOT NULL AND (
                   EXISTS (SELECT 1 FROM people.transfer_application x WHERE x.student_id = s.id AND x.state = 'EFFECTED')
                OR EXISTS (SELECT 1 FROM people.prior_transfer x WHERE x.student_id = s.id)
                OR EXISTS (SELECT 1 FROM people.programme_swap x WHERE x.student_id = s.id AND x.status = 'COMPLETED'));
        -- the application it already counts toward: a payment once counted stays with that application, whatever became of it (a
        -- completed, declined or withdrawn transfer used it, as this portal's own fee) — an officer moves it, never a run
        SELECT tp.application_id, t.state INTO v_existing, v_existing_state
          FROM people.transfer_payment tp JOIN people.transfer_application t ON t.id = tp.application_id
         WHERE tp.payment_id = r.id AND tp.source = 'OLD_PORTAL';
        -- the application the old portal's own export names this payment for (its payment numbers), while that application stands
        IF s.id IS NOT NULL AND v_payref IS NOT NULL THEN
            SELECT t.id INTO v_named
              FROM people.transfer_legacy lg JOIN people.transfer_application t ON t.id = lg.application_id
             WHERE t.student_id = s.id AND v_payref = ANY (lg.payrefs)
               AND (t.state = ANY (people.transfer_live_states()) OR t.state = 'EFFECTED')
             ORDER BY lg.loaded_at DESC LIMIT 1;
        END IF;
        -- a transfer the old portal approved in the current exercise and this portal restored (V669, V686): the student's payments of the
        -- exercise paid for it. Its date as V669 reads it — approved, else the start of its session, else recorded; one of an earlier
        -- exercise leaves the payments as credit
        IF s.id IS NOT NULL THEN
            SELECT coalesce(p.name, x.to_programme) INTO v_restored
              FROM people.prior_transfer x
              LEFT JOIN ref.programme p ON p.code = x.to_programme
              LEFT JOIN policy.academic_session a ON a.name = x.effective_session
             WHERE x.student_id = s.id
               AND coalesce(x.approved_on, a.starts_on, (x.recorded_at AT TIME ZONE 'Africa/Lagos')::date) >= v_from
             ORDER BY x.recorded_at DESC LIMIT 1;
        END IF;
        IF NOT v_counts THEN
            v_status := 'NOT_COUNTED'; v_reason := 'This item does not count toward the transfer fee; the Bursary decides what it was for';
        ELSIF v_existing_state = 'EFFECTED' THEN
            -- a completed transfer keeps what paid for it
            v_status := 'LINKED'; v_app := v_existing;
        ELSIF s.id IS NULL THEN
            v_status := 'UNMATCHED'; v_reason := 'The payment is on no student record';
        ELSIF s.duplicate_of IS NOT NULL THEN
            v_status := 'UNMATCHED'; v_reason := 'The record it is filed under is a duplicate of another';
        ELSIF s.matric_no IS NULL OR position(regexp_replace(upper(s.matric_no), '[^A-Z0-9]', '', 'g') IN upper(r.reference)) = 0 THEN
            v_status := 'UNMATCHED'; v_reason := 'The payment names another matriculation number than the record it is filed under';
        ELSIF v_payref IS NULL THEN
            v_status := 'UNMATCHED'; v_reason := 'The payment carries no old-portal payment number';
        ELSIF r.archived_at IS NOT NULL THEN
            v_status := 'UNMATCHED'; v_reason := 'The payment is archived for review';
        ELSIF v_existing IS NOT NULL THEN
            v_status := 'LINKED'; v_app := v_existing;
        ELSIF v_named IS NOT NULL THEN
            v_status := 'LINKED'; v_app := v_named;
        ELSIF v_paid_on < v_from THEN
            v_status := 'OUT_OF_SCOPE'; v_reason := 'Paid on ' || to_char(v_paid_on, 'FMDD FMMonth YYYY') || ', before ' || to_char(v_from, 'FMDD FMMonth YYYY') || ', the start of the current exercise';
        ELSIF s.status NOT IN ('ACTIVE', 'PROBATION') THEN
            v_status := 'UNMATCHED'; v_reason := 'The student''s record is ' || lower(s.status);
        ELSIF v_restored IS NOT NULL THEN
            v_status := 'USED'; v_reason := 'Paid for the transfer to ' || v_restored || ' the old portal approved, restored here; it is not a credit for another transfer';
        ELSE
            SELECT t.id INTO v_app FROM people.transfer_application t WHERE t.student_id = s.id AND t.state = ANY (people.transfer_live_states()) LIMIT 1;
            v_status := CASE WHEN v_app IS NULL THEN 'AWAITING_APPLICATION' ELSE 'LINKED' END;
        END IF;
        IF v_status = 'LINKED' THEN
            v_method := CASE WHEN v_app = v_named THEN 'OLD_PORTAL_EXPORT'
                             ELSE coalesce((SELECT l.match_method FROM people.legacy_transfer_payment l WHERE l.payment_id = r.id AND l.application_id = v_app),
                                           'IMPORT_MATRIC_PAYREF') END;
            -- the link follows the status: a LINKED payment counts toward its application
            INSERT INTO people.transfer_payment (application_id, payment_id, source, stated_fee, note)
            VALUES (v_app, r.id, 'OLD_PORTAL', people.transfer_fee(), 'Old-portal payment ' || v_payref)
            ON CONFLICT (payment_id) DO NOTHING;
        ELSE
            -- any other loses its old-portal link
            DELETE FROM people.transfer_payment tp WHERE tp.payment_id = r.id AND tp.source = 'OLD_PORTAL';
        END IF;
        INSERT INTO people.legacy_transfer_payment AS l (payment_id, student_id, session_label, item, item_kind, amount, payref, paid_on, channel, status,
                                                         match_method, application_id, reason, moved_hint, built_at)
        VALUES (r.id, r.student_id, r.session, r.item, v_kind, r.amount, v_payref, v_paid_on,
                nullif(btrim(substring(r.note FROM 'portal · ([^·]+) · old ref')), ''), v_status, v_method, v_app, v_reason, v_moved, now())
        ON CONFLICT (payment_id) DO UPDATE SET student_id = EXCLUDED.student_id, session_label = EXCLUDED.session_label, item = EXCLUDED.item,
               item_kind = EXCLUDED.item_kind, amount = EXCLUDED.amount, payref = EXCLUDED.payref, paid_on = EXCLUDED.paid_on, channel = EXCLUDED.channel,
               status = EXCLUDED.status, match_method = EXCLUDED.match_method, application_id = EXCLUDED.application_id, reason = EXCLUDED.reason,
               moved_hint = EXCLUDED.moved_hint, built_at = now()
         -- written only when the rule's answer changed: a run that changes nothing writes nothing
         WHERE l.decided_at IS NULL
           AND (l.student_id, l.session_label, l.item, l.item_kind, l.amount, l.payref, l.paid_on, l.channel, l.status, l.match_method, l.application_id, l.reason, l.moved_hint)
               IS DISTINCT FROM
               (EXCLUDED.student_id, EXCLUDED.session_label, EXCLUDED.item, EXCLUDED.item_kind, EXCLUDED.amount, EXCLUDED.payref, EXCLUDED.paid_on,
                EXCLUDED.channel, EXCLUDED.status, EXCLUDED.match_method, EXCLUDED.application_id, EXCLUDED.reason, EXCLUDED.moved_hint);
    END LOOP;
    -- a row whose payment is no longer an old-portal transfer payment (its purpose corrected, its record changed, unconfirmed) stops counting
    WITH gone AS (
        UPDATE people.legacy_transfer_payment l
           SET status = 'NOT_COUNTED', application_id = NULL, match_method = NULL, built_at = now(),
               reason = 'No longer an old-portal transfer payment: its purpose or record was changed'
         WHERE l.decided_at IS NULL AND l.status <> 'NOT_COUNTED' AND (p_student IS NULL OR l.student_id = p_student)
           AND NOT EXISTS (SELECT 1 FROM finance.payment_reference p
                            WHERE p.id = l.payment_id AND p.channel = 'Legacy' AND p.confirmed_at IS NOT NULL AND p.student_id IS NOT DISTINCT FROM l.student_id
                              AND regexp_replace(p.purpose, ' \(legacy\).*$', '') IN (SELECT i.item FROM people.legacy_transfer_item i))
        RETURNING l.payment_id)
    DELETE FROM people.transfer_payment tp USING gone WHERE tp.payment_id = gone.payment_id AND tp.source = 'OLD_PORTAL';
    -- a balance changed by the run leaves no reference open for the old figure
    PERFORM people.transfer_close_stale_references(t.id)
       FROM people.transfer_application t
      WHERE (p_student IS NULL OR t.student_id = p_student)
        AND EXISTS (SELECT 1 FROM people.transfer_payment tp JOIN finance.payment_reference pr ON pr.id = tp.payment_id
                     WHERE tp.application_id = t.id AND tp.source = 'PORTAL' AND pr.confirmed_at IS NULL AND pr.expires_at > now());
    RETURN QUERY SELECT l.status, count(*)::int FROM people.legacy_transfer_payment l
                  WHERE p_student IS NULL OR l.student_id = p_student GROUP BY l.status ORDER BY l.status;
END $$;
COMMENT ON FUNCTION people.legacy_transfer_reconcile(uuid) IS
  'V727: builds or refreshes the reconciliation list of the old portal''s inter-departmental transfer payments (all, or one student''s) and the links that let '
  'them count. A payment is matched on its own record only — the record answers to the matriculation number the payment names, it carries an old payment '
  'number, the record is no duplicate and is active, it was paid on or after the stated date, its item counts. It counts toward the application it already '
  'counts toward (a payment once counted stays with that application — completed, declined or withdrawn — as this portal''s own fee does), else the one the '
  'old portal''s export names it for, else the student''s live application; the payments of a student whose transfer the old portal approved in the '
  'current exercise and this portal restored are USED; with none it awaits an application. Never moves money, never re-posts a payment; an officer''s decision is kept; a run that changes nothing writes '
  'nothing; references left open for an old balance are closed. Safe to run again.';

-- a new application (made here, recorded by an office or loaded from the old portal) picks up the student's old-portal payments
CREATE FUNCTION people.transfer_application_links_legacy()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM people.legacy_transfer_reconcile(NEW.student_id);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_transfer_application_links_legacy AFTER INSERT ON people.transfer_application
    FOR EACH ROW EXECUTE FUNCTION people.transfer_application_links_legacy();

-- an officer's decision on a row of the list
CREATE FUNCTION people.decide_legacy_transfer_payment(p_payment uuid, p_decision text, p_application uuid, p_note text, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE l people.legacy_transfer_payment; t people.transfer_application;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('academic', 'registrar', 'dregistrar', 'bursar', 'ict', 'super') THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_OFFICE: the Academic Office, the Registry, the Bursary or ICT decides an old-portal transfer payment' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_REASON: say why (ten characters at least)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO l FROM people.legacy_transfer_payment WHERE payment_id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_TRANSFER_UNKNOWN: no such old-portal transfer payment on the list' USING ERRCODE = '23503'; END IF;
    -- one student's payments are decided by one run or one officer at a time
    IF l.student_id IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtext('legacy-transfer:' || l.student_id::text)); END IF;
    SELECT * INTO l FROM people.legacy_transfer_payment WHERE payment_id = p_payment FOR UPDATE;
    IF p_decision IN ('LINK', 'NOT_COUNTED', 'REJECT')
       AND EXISTS (SELECT 1 FROM people.transfer_payment tp JOIN people.transfer_application ta ON ta.id = tp.application_id
                    WHERE tp.payment_id = p_payment AND tp.source = 'OLD_PORTAL' AND ta.state = 'EFFECTED' AND ta.id IS DISTINCT FROM p_application) THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_EFFECTED: the payment paid for a transfer already completed; it stays with it' USING ERRCODE = '23514';
    END IF;
    IF p_decision = 'LINK' THEN
        SELECT * INTO t FROM people.transfer_application WHERE id = p_application;
        IF t.id IS NULL OR t.student_id IS DISTINCT FROM l.student_id THEN
            RAISE EXCEPTION 'LEGACY_TRANSFER_NOT_THEIRS: a payment counts only toward an application of the student it was paid by' USING ERRCODE = '23514';
        END IF;
        IF t.state IN ('DECLINED', 'WITHDRAWN', 'NOT_RECOMMENDED') THEN
            RAISE EXCEPTION 'LEGACY_TRANSFER_CLOSED: that application is %', lower(t.state) USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.id = p_payment AND r.archived_at IS NOT NULL) THEN
            RAISE EXCEPTION 'LEGACY_TRANSFER_ARCHIVED: the payment is archived for review; the Bursary restores it first' USING ERRCODE = '23514';
        END IF;
        DELETE FROM people.transfer_payment WHERE payment_id = p_payment AND source = 'OLD_PORTAL';
        INSERT INTO people.transfer_payment (application_id, payment_id, source, stated_fee, linked_by, linked_office, note)
        VALUES (p_application, p_payment, 'OLD_PORTAL', people.transfer_fee(), p_actor, p_office, btrim(p_note));
        UPDATE people.legacy_transfer_payment SET status = 'LINKED', match_method = 'MANUAL', application_id = p_application, reason = NULL,
               decided_at = now(), decided_by = p_actor, decided_office = p_office, decided_note = btrim(p_note) WHERE payment_id = p_payment;
        PERFORM people.transfer_close_stale_references(x) FROM unnest(ARRAY[p_application, l.application_id]) x WHERE x IS NOT NULL;
        RETURN 'LINKED';
    ELSIF p_decision IN ('NOT_COUNTED', 'REJECT') THEN
        DELETE FROM people.transfer_payment WHERE payment_id = p_payment AND source = 'OLD_PORTAL';
        UPDATE people.legacy_transfer_payment SET status = CASE p_decision WHEN 'REJECT' THEN 'REJECTED' ELSE 'NOT_COUNTED' END, application_id = NULL,
               match_method = NULL, decided_at = now(), decided_by = p_actor, decided_office = p_office, decided_note = btrim(p_note)
         WHERE payment_id = p_payment;
        IF l.application_id IS NOT NULL THEN PERFORM people.transfer_close_stale_references(l.application_id); END IF;
        RETURN CASE p_decision WHEN 'REJECT' THEN 'REJECTED' ELSE 'NOT_COUNTED' END;
    ELSIF p_decision = 'RELEASE' THEN
        IF l.decided_at IS NULL THEN
            RAISE EXCEPTION 'LEGACY_TRANSFER_NOT_DECIDED: the payment follows the rule already' USING ERRCODE = '23514';
        END IF;
        UPDATE people.legacy_transfer_payment SET decided_at = NULL, decided_by = NULL, decided_office = NULL,
               decided_note = 'Released by ' || p_office || ': ' || btrim(p_note) WHERE payment_id = p_payment;
        PERFORM people.legacy_transfer_reconcile(l.student_id);
        IF l.application_id IS NOT NULL THEN PERFORM people.transfer_close_stale_references(l.application_id); END IF;
        RETURN (SELECT x.status FROM people.legacy_transfer_payment x WHERE x.payment_id = p_payment);
    END IF;
    RAISE EXCEPTION 'LEGACY_TRANSFER_DECISION: LINK, NOT_COUNTED, REJECT or RELEASE' USING ERRCODE = '23514';
END $$;
COMMENT ON FUNCTION people.decide_legacy_transfer_payment(uuid, text, uuid, text, uuid, text) IS
  'V727: an officer''s decision on an old-portal transfer payment (the Academic Office, the Registry, the Bursary or ICT, with a reason): LINK it to an application '
  'of the same student, NOT_COUNTED, REJECT (it never counts), or RELEASE (back to the rule). Kept; the list is never rebuilt over it.';

-- ── 8 · the old portal's applications, uploaded: checked first, then committed ──────────────────────────
CREATE FUNCTION people.legacy_transfer_stage(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(btrim(regexp_replace(coalesce(p, ''), '[^A-Za-z]+', '_', 'g'), '_'))
        WHEN '' THEN 'APPLIED' WHEN 'APPLIED' THEN 'APPLIED' WHEN 'SUBMITTED' THEN 'APPLIED' WHEN 'PENDING' THEN 'APPLIED' WHEN 'NEW' THEN 'APPLIED'
        WHEN 'FROM_OK' THEN 'FROM_OK' WHEN 'HOD' THEN 'FROM_OK' WHEN 'CURRENT_HOD' THEN 'FROM_OK' WHEN 'HOD_APPROVED' THEN 'FROM_OK'
        WHEN 'CURRENT_DEPARTMENT' THEN 'FROM_OK' WHEN 'RELEASED' THEN 'FROM_OK'
        WHEN 'TO_OK' THEN 'TO_OK' WHEN 'NEW_HOD' THEN 'TO_OK' WHEN 'RECEIVING_HOD' THEN 'TO_OK' WHEN 'NEW_DEPARTMENT' THEN 'TO_OK' WHEN 'ACCEPTED' THEN 'TO_OK'
        WHEN 'REG_OK' THEN 'REG_OK' WHEN 'REGISTRY' THEN 'REG_OK' WHEN 'REGISTRAR' THEN 'REG_OK' WHEN 'REGISTRY_APPROVED' THEN 'REG_OK'
        END
$$;
COMMENT ON FUNCTION people.legacy_transfer_stage(text) IS
  'V727: the stage an old-portal transfer reached, as its export words it, read as this portal''s stage (APPLIED, FROM_OK, TO_OK, REG_OK); NULL when unknown. '
  'A transfer the old portal completed is restored, never loaded as an application.';

CREATE FUNCTION people.legacy_transfer_upload_check(p_rows jsonb)
RETURNS TABLE (row_no int, legacy_ref text, matric_no text, student_id uuid, to_programme_code text, stage text, session text, status text, reason text, application_id uuid)
LANGUAGE plpgsql STABLE AS $$
DECLARE r record; v_ref text; v_matric text; v_to_raw text; v_to text; v_from_raw text; v_from text; v_stage text; v_ses_row text; v_ses text; v_date text;
        s people.student; v_rs_status text; v_rs_id uuid; v_status text; v_reason text; v_app uuid; v_live uuid; v_live_to text; v_dups int[];
        a_ref text[] := '{}'; a_matric text[] := '{}'; a_student uuid[] := '{}'; a_to text[] := '{}'; a_stage text[] := '{}'; a_ses text[] := '{}';
        a_status text[] := '{}'; a_reason text[] := '{}'; a_app uuid[] := '{}'; i int;
        v_cur text := policy.university_current_session();
        v_from_date date := (SELECT x.counts_from FROM people.legacy_transfer_setting x WHERE x.id = 1);
BEGIN
    -- each row on its own
    FOR r IN SELECT x.value AS j, x.ordinality::int AS n FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY x LOOP
        v_ref := people.transfer_cell(r.j, 'legacy_ref', 'application_ref', 'application_no', 'reference', 'ref');
        v_matric := people.transfer_cell(r.j, 'matric_no', 'matric', 'matric_number', 'matriculation_number');
        v_to_raw := people.transfer_cell(r.j, 'to_programme', 'to_programme_code', 'new_programme', 'destination', 'to_department', 'new_department');
        v_from_raw := people.transfer_cell(r.j, 'from_programme', 'from_programme_code', 'old_programme', 'current_programme');
        v_stage := people.legacy_transfer_stage(people.transfer_cell(r.j, 'stage', 'status', 'stage_reached'));
        v_ses_row := people.transfer_cell(r.j, 'session');
        -- the old portal's session labels lag its dates: an application of the current exercise is continued in the current session
        v_ses := CASE WHEN v_cur IS NOT NULL AND (v_ses_row IS NULL OR v_ses_row < v_cur) THEN v_cur ELSE v_ses_row END;
        v_date := people.transfer_cell(r.j, 'applied_on', 'date_applied', 'application_date', 'date');
        v_app := NULL; v_status := NULL; v_reason := NULL; s := NULL; v_live := NULL; v_live_to := NULL; v_rs_status := NULL; v_rs_id := NULL;
        -- the programme named, by its code or by the University's name for it
        v_to := (SELECT p.code FROM ref.programme p WHERE NOT p.archived AND (upper(p.code) = upper(v_to_raw) OR upper(p.name) = upper(v_to_raw))
                  ORDER BY (upper(p.code) = upper(v_to_raw)) DESC LIMIT 1);
        v_from := CASE WHEN v_from_raw IS NULL THEN NULL
                       ELSE coalesce((SELECT p.code FROM ref.programme p WHERE upper(p.code) = upper(v_from_raw) OR upper(p.name) = upper(v_from_raw)
                                       ORDER BY (upper(p.code) = upper(v_from_raw)) DESC LIMIT 1), '?') END;
        IF v_ref IS NULL THEN v_status := 'INVALID'; v_reason := 'No old-portal application reference';
        ELSIF v_matric IS NULL THEN v_status := 'INVALID'; v_reason := 'No matriculation number';
        ELSIF v_to IS NULL THEN v_status := 'INVALID'; v_reason := 'The programme transferred to (' || coalesce(v_to_raw, 'none given') || ') is not one the University runs';
        ELSIF v_stage IS NULL THEN v_status := 'INVALID'; v_reason := 'The stage reached is not one of APPLIED, FROM_OK (current HOD), TO_OK (new HOD), REG_OK (Registry)';
        ELSIF v_date IS NOT NULL AND platform.read_date(v_date) IS NULL THEN v_status := 'INVALID'; v_reason := 'The date applied (' || v_date || ') is not a date';
        ELSIF v_ses_row IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_ses_row) THEN
            v_status := 'INVALID'; v_reason := 'The session ' || v_ses_row || ' is not on the calendar';
        ELSIF v_ses IS NULL THEN v_status := 'INVALID'; v_reason := 'No session is given, and the calendar has no current session';
        ELSIF v_date IS NOT NULL AND platform.read_date(v_date) < v_from_date THEN
            v_status := 'OUT_OF_SCOPE'; v_reason := 'Applied before ' || to_char(v_from_date, 'FMDD FMMonth YYYY') || ', the start of the current exercise';
        ELSIF EXISTS (SELECT 1 FROM people.transfer_legacy lg WHERE upper(lg.legacy_ref) = upper(v_ref)) THEN
            v_status := 'EXISTS'; v_reason := 'Already loaded';
            v_app := (SELECT lg.application_id FROM people.transfer_legacy lg WHERE upper(lg.legacy_ref) = upper(v_ref));
        END IF;
        IF v_status IS NULL THEN
            -- the student by the matriculation number alone (or the one a correction replaced), never by name
            SELECT x.status, x.student_id INTO v_rs_status, v_rs_id FROM people.resolve_student(v_matric, false) x LIMIT 1;
            IF v_rs_status IS DISTINCT FROM 'MATCHED' THEN
                v_status := 'NO_STUDENT'; v_reason := 'No student answers to ' || v_matric;
            ELSE
                SELECT * INTO s FROM people.student st WHERE st.id = v_rs_id;
                IF s.matric_no IS NULL OR s.status NOT IN ('ACTIVE', 'PROBATION') THEN
                    v_status := 'NOT_ELIGIBLE'; v_reason := 'The student''s record is ' || lower(s.status) || '; only a matriculated, active student transfers';
                ELSIF s.current_level IS NULL OR s.current_level NOT IN (100, 200, 300, 400, 500, 600) THEN
                    v_status := 'NOT_ELIGIBLE'; v_reason := 'The student''s level (' || coalesce(s.current_level::text, 'none') || ') is not one a transfer is made from';
                ELSIF s.programme_code = v_to THEN
                    v_status := 'ALREADY_MOVED'; v_reason := 'The student is already on the programme transferred to: the old portal''s transfer is restored instead (no fee)';
                ELSIF v_from IS NOT NULL AND v_from <> s.programme_code THEN
                    v_status := 'FROM_MISMATCH'; v_reason := 'The programme transferred from (' || v_from_raw || ') is not the one on the student''s record';
                ELSE
                    SELECT t.id, t.to_programme_code INTO v_live, v_live_to FROM people.transfer_application t
                     WHERE t.student_id = s.id AND t.state = ANY (people.transfer_live_states()) LIMIT 1;
                    IF v_live IS NOT NULL AND v_live_to <> v_to THEN
                        v_status := 'CONFLICT'; v_reason := 'The student has an application here to another programme';
                    ELSIF v_live IS NOT NULL AND EXISTS (SELECT 1 FROM people.transfer_legacy lg WHERE lg.application_id = v_live) THEN
                        v_status := 'CONFLICT'; v_reason := 'The student''s application here already carries another old-portal reference';
                    ELSIF v_live IS NOT NULL THEN
                        v_status := 'ATTACH'; v_reason := 'Joins the student''s application already here (one application a student)'; v_app := v_live;
                    ELSE
                        v_status := 'NEW';
                    END IF;
                END IF;
            END IF;
        END IF;
        a_ref := a_ref || v_ref; a_matric := a_matric || v_matric; a_student := a_student || s.id; a_to := a_to || v_to; a_stage := a_stage || v_stage;
        a_ses := a_ses || v_ses; a_status := a_status || v_status; a_reason := a_reason || v_reason; a_app := a_app || v_app;
    END LOOP;
    -- then the file as a whole: among the rows that would load, one reference and one student once (an earlier declined or refused row of the
    -- same student never blocks the one that loads)
    SELECT coalesce(array_agg(d.i), '{}') INTO v_dups
      FROM (SELECT u.i, count(*) OVER (PARTITION BY upper(u.ref)) AS by_ref, count(*) OVER (PARTITION BY u.student) AS by_student
              FROM unnest(a_ref, a_student, a_status) WITH ORDINALITY u(ref, student, st, i) WHERE u.st IN ('NEW', 'ATTACH')) d
     WHERE d.by_ref > 1 OR d.by_student > 1;
    FOR i IN 1 .. coalesce(array_length(a_status, 1), 0) LOOP
        IF i = ANY (v_dups) THEN
            a_status[i] := 'DUPLICATE_ROW'; a_reason[i] := 'The file names this application or this student more than once among the rows that would load'; a_app[i] := NULL;
        END IF;
        RETURN QUERY SELECT i, a_ref[i], a_matric[i], a_student[i], a_to[i], a_stage[i], a_ses[i], a_status[i], a_reason[i], a_app[i];
    END LOOP;
END $$;
COMMENT ON FUNCTION people.legacy_transfer_upload_check(jsonb) IS
  'V727: reads the old portal''s inter-departmental transfer export row by row without writing — the reference, the matriculation number (the student found by '
  'it alone), the programme transferred to (code or name), the stage reached, the session and date — and says what would become of each: NEW (an application '
  'at that stage, in the current session), ATTACH (joins the student''s application here, moved on to the stage the old portal reached), EXISTS, '
  'ALREADY_MOVED (restore instead), FROM_MISMATCH, CONFLICT, NOT_ELIGIBLE, NO_STUDENT, OUT_OF_SCOPE (applied before the stated date), DUPLICATE_ROW (one '
  'reference or one student more than once among the rows that would load) or INVALID, with the reason.';

CREATE FUNCTION people.legacy_transfer_upload_commit(p_rows jsonb, p_filename text, p_partial boolean, p_actor uuid, p_office text)
RETURNS TABLE (row_no int, legacy_ref text, status text, reason text, application_id uuid, linked_payments int)
LANGUAGE plpgsql AS $$
DECLARE c record; j jsonb; v_checked jsonb; v_load uuid; v_app uuid; v_payrefs text[]; v_applied timestamptz; v_reason text; v_cgpa numeric;
        s people.student; t people.transfer_application; v_rank int;
        n_loaded int := 0; n_attached int := 0; n_left int := 0; v_links int; v_bad int;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_OFFICE: the Academic Office, the Registry or ICT loads the old portal''s transfers' USING ERRCODE = '23514';
    END IF;
    IF p_actor IS NULL THEN RAISE EXCEPTION 'a load is made by a person' USING ERRCODE = '23514'; END IF;
    IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) = 0 OR jsonb_array_length(p_rows) > 2000 THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_ROWS: between one and 2,000 rows at a time' USING ERRCODE = '23514';
    END IF;
    -- the file read once, as the check reads it
    v_checked := (SELECT jsonb_agg(to_jsonb(k) ORDER BY k.row_no) FROM people.legacy_transfer_upload_check(p_rows) k);
    SELECT count(*) INTO v_bad FROM jsonb_array_elements(v_checked) k WHERE k.value ->> 'status' NOT IN ('NEW', 'ATTACH', 'EXISTS');
    IF v_bad > 0 AND NOT coalesce(p_partial, false) THEN
        RAISE EXCEPTION 'LEGACY_TRANSFER_ROWS_REFUSED: % row(s) cannot be loaded; correct them, or load the others alone', v_bad USING ERRCODE = '23514';
    END IF;
    -- the students' locks taken first, in the order a run for everyone takes them
    PERFORM pg_advisory_xact_lock(hashtext('legacy-transfer:' || x.sid::text))
       FROM (SELECT DISTINCT (k.value ->> 'student_id')::uuid AS sid FROM jsonb_array_elements(v_checked) k
              WHERE k.value ->> 'status' IN ('NEW', 'ATTACH') ORDER BY 1) x;
    INSERT INTO people.legacy_transfer_load (filename, rows_read, committed_by, committed_office)
    VALUES (nullif(btrim(p_filename), ''), jsonb_array_length(p_rows), p_actor, p_office)
    RETURNING id INTO v_load;
    FOR c IN SELECT * FROM jsonb_to_recordset(v_checked) AS k(row_no int, legacy_ref text, matric_no text, student_id uuid, to_programme_code text, stage text,
                                                              session text, status text, reason text, application_id uuid) ORDER BY k.row_no LOOP
        j := p_rows -> (c.row_no - 1);
        v_app := c.application_id; v_links := 0;
        v_payrefs := ARRAY(SELECT DISTINCT upper(btrim(x))
                             FROM regexp_split_to_table(coalesce(people.transfer_cell(j, 'payrefs', 'payment_refs', 'payment_reference', 'payref', 'payment_ref'), ''), '[,;[:space:]]+') x
                            WHERE btrim(x) <> '');
        v_applied := coalesce((platform.read_date(people.transfer_cell(j, 'applied_on', 'date_applied', 'application_date', 'date'))::timestamp
                               AT TIME ZONE 'Africa/Lagos'), now());
        IF c.status = 'NEW' THEN
            SELECT * INTO s FROM people.student WHERE id = c.student_id;
            v_reason := coalesce(people.transfer_cell(j, 'reason'), 'Continued from the old portal (' || c.legacy_ref || ')');
            v_cgpa := NULL;
            SELECT g.cgpa INTO v_cgpa FROM assessment.student_gpa(s.id) g WHERE g.cgpa IS NOT NULL ORDER BY g.session DESC, g.semester DESC LIMIT 1;
            INSERT INTO people.transfer_application (student_id, session, from_programme_code, from_level, to_programme_code, reason, mode_of_entry, cgpa, state,
                                                     applied_at, applied_by, from_dept_at, to_dept_at, reg_at)
            VALUES (s.id, c.session, s.programme_code, s.current_level, c.to_programme_code, v_reason, s.entry_mode, v_cgpa, c.stage, v_applied, p_actor,
                    CASE WHEN c.stage IN ('FROM_OK', 'TO_OK', 'REG_OK') THEN v_applied END,
                    CASE WHEN c.stage IN ('TO_OK', 'REG_OK') THEN v_applied END,
                    CASE WHEN c.stage = 'REG_OK' THEN v_applied END)
            RETURNING id INTO v_app;
            n_loaded := n_loaded + 1;
        ELSIF c.status = 'ATTACH' THEN
            -- the application here moves on to the stage the old portal reached, never back
            SELECT * INTO t FROM people.transfer_application WHERE id = v_app FOR UPDATE;
            v_rank := array_position(ARRAY['APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK'], c.stage);
            IF t.state IN ('APPLIED', 'FROM_OK', 'TO_OK') AND v_rank > array_position(ARRAY['APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK'], t.state) THEN
                UPDATE people.transfer_application
                   SET state = c.stage,
                       from_dept_at = CASE WHEN v_rank >= 2 THEN coalesce(from_dept_at, v_applied) ELSE from_dept_at END,
                       to_dept_at = CASE WHEN v_rank >= 3 THEN coalesce(to_dept_at, v_applied) ELSE to_dept_at END,
                       reg_at = CASE WHEN v_rank >= 4 THEN coalesce(reg_at, v_applied) ELSE reg_at END
                 WHERE id = v_app;
            END IF;
            n_attached := n_attached + 1;
        END IF;
        IF c.status IN ('NEW', 'ATTACH') THEN
            INSERT INTO people.transfer_legacy (application_id, legacy_ref, applied_on, stage, approvals, documents, payrefs, load_id, raw, loaded_by)
            VALUES (v_app, c.legacy_ref, platform.read_date(people.transfer_cell(j, 'applied_on', 'date_applied', 'application_date', 'date')),
                    coalesce(people.transfer_cell(j, 'stage', 'status', 'stage_reached'), c.stage),
                    people.transfer_cell(j, 'approvals', 'approval_history', 'history'), people.transfer_cell(j, 'documents', 'document', 'attachments'),
                    v_payrefs, v_load, j, p_actor);
            -- the payments its payment numbers name now count toward it (the rule reads the old record's numbers)
            PERFORM people.legacy_transfer_reconcile(c.student_id);
            SELECT count(*) INTO v_links FROM people.transfer_payment tp WHERE tp.application_id = v_app AND tp.source = 'OLD_PORTAL';
        ELSIF c.status <> 'EXISTS' THEN
            n_left := n_left + 1;
        END IF;
        INSERT INTO people.legacy_transfer_load_row (load_id, row_no, legacy_ref, raw, status, reason, student_id, application_id)
        VALUES (v_load, c.row_no, c.legacy_ref, j, c.status, c.reason, c.student_id, v_app);
        RETURN QUERY SELECT c.row_no, c.legacy_ref, c.status, c.reason, v_app, v_links;
    END LOOP;
    UPDATE people.legacy_transfer_load SET loaded = n_loaded, attached = n_attached, left_out = n_left WHERE id = v_load;
END $$;
COMMENT ON FUNCTION people.legacy_transfer_upload_commit(jsonb, text, boolean, uuid, text) IS
  'V727: loads the old portal''s inter-departmental transfer export (the Academic Office, the Registry or ICT): each NEW row becomes an application at the stage the '
  'old portal reached, in the current session (never a second one: ATTACH joins the student''s application here and moves it on to that stage, never back), the '
  'old record is kept beside it, and the payments its payment numbers name count toward it when they are the student''s own. Refused while any row cannot be '
  'loaded unless p_partial; every row is kept with what became of it.';

-- ── 9 · the monitor and the reconciliation report ─────────────────────────────────────────────────
CREATE FUNCTION people.transfer_fee_monitor(p_session text)
RETURNS TABLE (application_id uuid, student_id uuid, matric_no text, name text, session text, from_programme text, to_programme text, faculty_code text,
               from_dept text, to_dept text, state text, awaiting text, legacy_ref text, fee_due numeric, portal_paid numeric, old_portal_paid numeric, paid_total numeric, balance numeric,
               excess numeric, payments int, pending boolean, band text, applied_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH apps AS (
        SELECT t.*, e.fee_due, e.portal_paid, e.old_portal_paid, e.paid_total, e.balance, e.excess, e.payments, e.pending, e.band
          FROM people.transfer_application t CROSS JOIN LATERAL people.transfer_entitlement(t.id) e
         WHERE (p_session IS NULL OR t.session = p_session) AND t.state <> 'WITHDRAWN'),
    credit AS (
        SELECT l.student_id, sum(l.amount - finance.gst_refunded(r.reference)) AS paid, count(*)::int AS n
          FROM people.legacy_transfer_payment l
          JOIN finance.payment_reference r ON r.id = l.payment_id AND r.archived_at IS NULL
         WHERE l.status = 'AWAITING_APPLICATION' AND l.amount > finance.gst_refunded(r.reference) GROUP BY l.student_id)
    SELECT a.id, a.student_id, s.matric_no, s.surname || ', ' || s.other_names, a.session, fp.name, tp.name, tp.faculty_code, fp.dept_code, tp.dept_code, a.state,
           CASE WHEN a.state = 'EFFECTED' THEN 'DONE'
                WHEN a.state IN ('DECLINED', 'NOT_RECOMMENDED') THEN NULL
                WHEN a.state = 'APPLIED' AND coalesce(a.paid_total, 0) <= 0 THEN 'PAYMENT'
                WHEN a.state IN ('REG_OK', 'APPROVED') AND coalesce(a.balance, 0) > 0 THEN 'PAYMENT'
                WHEN a.state = 'APPLIED' THEN 'CURRENT_HOD' WHEN a.state = 'FROM_OK' THEN 'NEW_HOD' WHEN a.state = 'TO_OK' THEN 'REGISTRY'
                WHEN a.state = 'REG_OK' THEN 'ACADEMIC_OFFICE' WHEN a.state = 'RECOMMENDED' THEN 'SENATE' WHEN a.state = 'APPROVED' THEN 'REGISTRY_EFFECT' END,
           lg.legacy_ref, a.fee_due, a.portal_paid, a.old_portal_paid, a.paid_total, a.balance, a.excess, a.payments, a.pending, a.band, a.applied_at
      FROM apps a
      JOIN people.student s ON s.id = a.student_id
      LEFT JOIN ref.programme fp ON fp.code = a.from_programme_code
      LEFT JOIN ref.programme tp ON tp.code = a.to_programme_code
      LEFT JOIN people.transfer_legacy lg ON lg.application_id = a.id
    UNION ALL
    -- a student who paid on the old portal and has no application yet: the credit waits for one
    SELECT NULL::uuid, c.student_id, s.matric_no, s.surname || ', ' || s.other_names, NULL::text, cp.name, NULL::text, cp.faculty_code, cp.dept_code, NULL::text, NULL::text,
           'APPLICATION', NULL::text, people.transfer_fee(), 0::numeric, c.paid, c.paid,
           CASE WHEN people.transfer_fee() IS NULL THEN NULL ELSE greatest(people.transfer_fee() - c.paid, 0) END,
           CASE WHEN people.transfer_fee() IS NULL THEN 0 ELSE greatest(c.paid - people.transfer_fee(), 0) END,
           c.n, false, 'AWAITING_APPLICATION', NULL::timestamptz
      FROM credit c JOIN people.student s ON s.id = c.student_id LEFT JOIN ref.programme cp ON cp.code = s.programme_code
     WHERE p_session IS NULL OR p_session = policy.university_current_session()
$$;
COMMENT ON FUNCTION people.transfer_fee_monitor(text) IS
  'V727: every inter-departmental transfer application (of a session, or all; not the withdrawn) with the fee as stated now, what is paid here and on the old portal, '
  'the balance, the band and what it awaits (PAYMENT, a desk, DONE) — and every student whose old-portal payments await an application (band AWAITING_APPLICATION, '
  'shown with the current session).';

CREATE FUNCTION people.legacy_transfer_report()
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH fee AS (SELECT people.transfer_fee() AS fee),
    l AS (SELECT * FROM people.legacy_transfer_payment),
    -- per student, the old-portal payments that count (linked, or awaiting an application), never one archived for review
    net AS (SELECT l.student_id, l.status, l.amount - finance.gst_refunded(p.reference) AS amount
              FROM l JOIN finance.payment_reference p ON p.id = l.payment_id AND p.archived_at IS NULL
             WHERE l.status IN ('LINKED', 'AWAITING_APPLICATION') AND l.amount > finance.gst_refunded(p.reference)),
    per AS (SELECT net.student_id, sum(net.amount) AS paid FROM net GROUP BY net.student_id),
    -- the students whose old-portal payments await an application (as the monitor's credit rows): nothing is owed until they apply
    waiting AS (SELECT net.student_id, sum(net.amount) AS paid FROM net WHERE net.status = 'AWAITING_APPLICATION' GROUP BY net.student_id),
    -- the old portal's applications named in any upload, by reference, and what last became of each
    refs AS (SELECT DISTINCT ON (upper(lr.legacy_ref)) upper(lr.legacy_ref) AS ref, lr.status
               FROM people.legacy_transfer_load_row lr JOIN people.legacy_transfer_load ld ON ld.id = lr.load_id
              WHERE lr.legacy_ref IS NOT NULL ORDER BY upper(lr.legacy_ref), ld.committed_at DESC, lr.row_no DESC),
    apps AS (SELECT m.* FROM people.transfer_fee_monitor(NULL) m WHERE m.application_id IS NOT NULL AND m.state = ANY (people.transfer_live_states())),
    -- the live applications of students who paid on the old portal, read against every verified payment
    payers AS (SELECT apps.* FROM apps WHERE coalesce(apps.old_portal_paid, 0) > 0)
    SELECT jsonb_build_object(
        'countsFrom', (SELECT counts_from FROM people.legacy_transfer_setting WHERE id = 1),
        'fee', (SELECT fee FROM fee),
        'loads', (SELECT count(*) FROM people.legacy_transfer_load),
        'legacyApplicationsIdentified', (SELECT count(*) FROM refs),
        'legacyApplicationsMatched', (SELECT count(*) FROM people.transfer_legacy),
        'legacyApplicationsUnmatched', (SELECT count(*) FROM refs WHERE NOT EXISTS (SELECT 1 FROM people.transfer_legacy lg WHERE upper(lg.legacy_ref) = refs.ref)),
        'legacyUnmatchedByStatus', (SELECT coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb)
                                      FROM (SELECT refs.status, count(*) AS n FROM refs
                                             WHERE NOT EXISTS (SELECT 1 FROM people.transfer_legacy lg WHERE upper(lg.legacy_ref) = refs.ref)
                                             GROUP BY refs.status) x),
        'paymentsRead', (SELECT count(*) FROM l),
        'paymentsLinked', (SELECT count(*) FROM l WHERE l.status = 'LINKED'),
        'paymentsAwaitingApplication', (SELECT count(*) FROM l WHERE l.status = 'AWAITING_APPLICATION'),
        'paymentsUsed', (SELECT count(*) FROM l WHERE l.status = 'USED'),
        'paymentsUnmatched', (SELECT count(*) FROM l WHERE l.status = 'UNMATCHED'),
        'paymentsNotCounted', (SELECT count(*) FROM l WHERE l.status = 'NOT_COUNTED'),
        'paymentsOutOfScope', (SELECT count(*) FROM l WHERE l.status = 'OUT_OF_SCOPE'),
        'paymentsRejected', (SELECT count(*) FROM l WHERE l.status = 'REJECTED'),
        'paymentsDecided', (SELECT count(*) FROM l WHERE l.decided_at IS NOT NULL),
        'unmatchedByReason', (SELECT coalesce(jsonb_object_agg(x.reason, x.n), '{}'::jsonb)
                                FROM (SELECT coalesce(l.reason, 'No reason recorded') AS reason, count(*) AS n FROM l WHERE l.status = 'UNMATCHED' GROUP BY 1) x),
        'students', (SELECT count(*) FROM per),
        'studentsPaidInFull', (SELECT count(*) FROM per, fee WHERE per.paid = fee.fee),
        'studentsPaidOverFee', (SELECT count(*) FROM per, fee WHERE per.paid > fee.fee),
        'studentsPaidHalf', (SELECT count(*) FROM per, fee WHERE per.paid * 2 = fee.fee),
        'studentsOtherPartial', (SELECT count(*) FROM per, fee WHERE per.paid < fee.fee AND per.paid * 2 <> fee.fee),
        'oldPortalCollected', (SELECT coalesce(sum(per.paid), 0) FROM per),
        'oldPortalExcess', (SELECT coalesce(sum(greatest(per.paid - fee.fee, 0)), 0) FROM per, fee),
        'studentsAwaitingApplication', (SELECT count(*) FROM waiting),
        'creditAwaitingApplication', (SELECT coalesce(sum(waiting.paid), 0) FROM waiting),
        'owedWhenTheyApply', (SELECT coalesce(sum(greatest(fee.fee - waiting.paid, 0)), 0) FROM waiting, fee),
        'studentsOwingWhenTheyApply', (SELECT count(*) FROM waiting, fee WHERE waiting.paid < fee.fee),
        'payerApplicationsLive', (SELECT count(*) FROM payers),
        'outstandingOldPortalPayers', (SELECT coalesce(sum(payers.balance), 0) FROM payers),
        'applicationsLive', (SELECT count(*) FROM apps),
        'applicationsNotPaid', (SELECT count(*) FROM apps WHERE coalesce(apps.paid_total, 0) = 0),
        'applicationsPartPaid', (SELECT count(*) FROM apps WHERE apps.paid_total > 0 AND apps.balance > 0),
        'applicationsAwaitingPayment', (SELECT count(*) FROM apps WHERE apps.awaiting = 'PAYMENT'),
        'applicationsAwaitingApproval', (SELECT count(*) FROM apps WHERE apps.awaiting NOT IN ('PAYMENT', 'DONE')),
        'outstandingApplications', (SELECT coalesce(sum(apps.balance), 0) FROM apps)
    )
$$;
COMMENT ON FUNCTION people.legacy_transfer_report() IS
  'V727: the reconciliation report, read from the records as they stand (never estimated): the scope, the old portal''s applications named in the uploads and '
  'what became of them, its transfer payments read and what became of them (unmatched by reason), the students by what they paid on the old portal against the '
  'fee (in full, above it, half, another part), collected and excess; the students whose payments await an application, their credit and what they will owe '
  'when they apply (nothing is owed before); the balance still owed on the live applications of old-portal payers after every verified payment '
  '(outstandingOldPortalPayers); and the live applications by what they await.';

COMMENT ON FUNCTION people.transfer_live_states() IS 'V727: the states in which an inter-departmental transfer application is live (uq_ta_live: one at a time).';
COMMENT ON FUNCTION people.transfer_fee_settled_or_refuse(uuid, record) IS
  'V727: the refusal both final doors give (approve_transfer at REG_OK, effect_transfer): the fee not stated (TRANSFER_FEE_NOT_STATED), the balance owed while a '
  'payment awaits the bank (TRANSFER_PAYMENT_PENDING), or owed (TRANSFER_FEE_OUTSTANDING).';
COMMENT ON FUNCTION people.set_legacy_transfer_scope(date, text, uuid, text) IS
  'V727: states the date from which the old portal''s transfer payments count (the Academic Office, the Registry, the Bursary or ICT, with a reason) and rebuilds the list.';
COMMENT ON FUNCTION finance.transfer_fee_revised() IS
  'V727: a statement of the transfer fee kept as a revision; the open transfer references drawn at another figure than what is now owed are closed.';
COMMENT ON FUNCTION people.transfer_application_links_legacy() IS
  'V727: a new transfer application picks up the student''s old-portal transfer payments (people.legacy_transfer_reconcile).';
COMMENT ON FUNCTION finance.transfer_reference_confirmed() IS
  'V727: a transfer reference confirmed (late at the bank, or by the Bursary) closes the application''s other references left open for the old balance.';
COMMENT ON FUNCTION people.transfer_application_closes_references() IS
  'V727: an application that leaves the desks (effected, declined, withdrawn) leaves no transfer reference payable.';
COMMENT ON FUNCTION people.transfer_legacy_kept() IS 'V727: the old portal''s record of a transfer is kept as received.';
COMMENT ON FUNCTION finance.transfer_fee_revision_kept() IS 'V727: a statement of the transfer fee is kept as it was made.';

-- the list built once, now
SELECT * FROM people.legacy_transfer_reconcile(NULL);

COMMIT;
