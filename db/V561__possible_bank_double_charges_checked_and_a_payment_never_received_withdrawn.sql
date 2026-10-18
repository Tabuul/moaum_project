-- ═══════════════════════════════════════
-- V561 — Possible bank double charges checked against the bank; an old-portal payment the bank never received withdrawn on evidence
--
--   Seen on AWS, 18 Oct 2026: a 200 Level student shown "Paid more than due" by ₦48,738.20 — two old-portal school-fees records
--   of ₦85,294 for the first semester of 2025/2026, both of 23 Mar 2026, under two of the old portal's payment numbers. Old Fees
--   History rightly keeps a payment number it has not seen as a payment of its own (V498), so the excess is real if both payments
--   reached the University's account — and nothing if the bank charged the student twice and sent one back. Nothing asked which
--   before the Bursary carried or refunded the excess, and a numbered record the bank never received could not be withdrawn.
--
--   1 · finance.possible_double_charges(session): the old-portal records of one student, session, item, Lagos day and amount (to
--       the naira) under two or more payment numbers — the case above — with the Bursary's check of each against the bank.
--       (A record without a number beside a numbered one is a double on the record, listed and withdrawn by V498's tool.)
--   2 · finance.check_double_charge: a Bursary officer records what the bank statement or the gateway's report shows — RECEIVED
--       (every payment arrived: the excess is real) or NOT_RECEIVED (naming the records that did not arrive; at least one did) —
--       with the evidence; a NOT_RECEIVED check raises the withdrawals below.
--   3 · finance.payment_not_received (PNR/YYYY/NNNNNN): an old-portal payment record the bank shows never arrived, raised by one
--       Bursary officer on evidence and approved by another (or rejected, or cancelled by the one who raised it). Approved, it is
--       withdrawn as V498 withdraws a double: its ledger journal reversed and freed, the record kept on finance.old_payment_withdrawn
--       (kind NOT_RECEIVED), then removed; its payment number kept on finance.legacy_payref_withdrawn so a later upload of the
--       same export never brings it back; the student told. Refused for a record holding several payments, one a deferment fee,
--       a refund, the GST desk or a payment swap points at, and one whose session's overpayment was already carried or refunded.
--   4 · finance.decide_overpayments (V519) holds back a student with a possible school-fees double charge not yet checked (or
--       with a withdrawal waiting): carried or refunded only once the bank has answered. It returns those held.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V561: possible bank double charges checked; a payment the bank never received withdrawn on evidence', true);

-- ── 0 · who acts: a Bursary officer, by name ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.bursary_actor()
RETURNS uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PAY_CHECK_PERSON: a payment is checked or withdrawn by a person' USING ERRCODE = '42501'; END IF;
    IF coalesce(office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'PAY_CHECK_OFFICE: old-portal payments are checked against the bank and withdrawn by the Bursary' USING ERRCODE = '42501';
    END IF;
    RETURN who;
END $$;

-- ── 1 · the checks and the withdrawals ───────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.double_charge_check (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session       text NOT NULL,
    purpose       text NOT NULL,
    paid_on       date NOT NULL,
    amount        numeric(14,2) NOT NULL,
    verdict       text NOT NULL CHECK (verdict IN ('RECEIVED', 'NOT_RECEIVED')),
    evidence      text NOT NULL CHECK (length(btrim(evidence)) >= 5),
    note          text NULL,
    not_received  text[] NOT NULL DEFAULT '{}',
    checked_by    uuid NOT NULL,
    actor_office  text NULL,
    checked_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, session, purpose, paid_on, amount)
);
COMMENT ON TABLE finance.double_charge_check IS
  'V561: the Bursary''s check against the bank of old-portal payments of one student, session, item, day and amount under several payment numbers — RECEIVED (each arrived: the excess is real) or NOT_RECEIVED (the records named did not), with the evidence.';
SELECT audit.attach('finance.double_charge_check');

CREATE SEQUENCE finance.payment_not_received_seq;
CREATE TABLE finance.payment_not_received (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_ref      text NOT NULL UNIQUE CHECK (request_ref ~ '^PNR/[0-9]{4}/[0-9]{6}$'),
    reference        text NOT NULL,
    payment_id       uuid NOT NULL,
    student_id       uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session          text NOT NULL,
    purpose          text NOT NULL,
    amount           numeric(14,2) NOT NULL,
    paid_on          date NULL,
    payref           text NULL,
    check_id         uuid NULL REFERENCES finance.double_charge_check(id) ON DELETE SET NULL,
    kept_reference   text NULL,
    evidence         text NOT NULL CHECK (length(btrim(evidence)) >= 5),
    reason           text NOT NULL CHECK (length(btrim(reason)) >= 10),
    state            text NOT NULL DEFAULT 'PROPOSED' CHECK (state IN ('PROPOSED', 'APPROVED', 'REJECTED', 'CANCELLED')),
    raised_by        uuid NOT NULL,
    raised_office    text NULL,
    raised_at        timestamptz NOT NULL DEFAULT now(),
    decided_by       uuid NULL,
    decided_office   text NULL,
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    ledger_journal   uuid NULL,
    reversal_journal uuid NULL,
    CONSTRAINT ck_pnr_two_people CHECK (decided_by IS NULL OR state = 'CANCELLED' OR decided_by <> raised_by)
);
CREATE UNIQUE INDEX ux_pnr_open ON finance.payment_not_received (reference) WHERE state = 'PROPOSED';
CREATE INDEX ix_pnr_student ON finance.payment_not_received (student_id, session);
CREATE INDEX ix_pnr_check ON finance.payment_not_received (check_id) WHERE check_id IS NOT NULL;
CREATE INDEX ix_pnr_state ON finance.payment_not_received (state, raised_at DESC);
COMMENT ON TABLE finance.payment_not_received IS
  'V561: an old-portal payment record the bank shows never arrived, withdrawn on evidence — raised by one Bursary officer, approved (or rejected) by another, or cancelled by the one who raised it; approved, the record is withdrawn (finance.old_payment_withdrawn, kind NOT_RECEIVED) with its ledger journal reversed.';
SELECT audit.attach('finance.payment_not_received');

CREATE TABLE finance.legacy_payref_withdrawn (
    payref       text PRIMARY KEY CHECK (payref = upper(btrim(payref)) AND payref <> ''),
    reference    text NOT NULL,
    request_id   uuid NOT NULL REFERENCES finance.payment_not_received(id),
    amount       numeric(14,2) NULL,
    withdrawn_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_legacy_payref_withdrawn_request ON finance.legacy_payref_withdrawn (request_id);
COMMENT ON TABLE finance.legacy_payref_withdrawn IS
  'V561: the old portal''s payment numbers of records withdrawn because the bank never received them; Old Fees History never records them again.';
SELECT audit.attach('finance.legacy_payref_withdrawn');

ALTER TABLE finance.old_payment_withdrawn DROP CONSTRAINT old_payment_withdrawn_double_kind_check;
ALTER TABLE finance.old_payment_withdrawn ADD CONSTRAINT old_payment_withdrawn_double_kind_check
    CHECK (double_kind IN ('PAYMENT_HISTORY', 'WHOLE_SESSION', 'UNNUMBERED', 'MISLABELLED', 'NOT_RECEIVED'));

-- ── 2 · possible double charges ──────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.possible_double_charges(p_session text)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, session text, purpose text, paid_on date, amount numeric,
               payments int, refs text[], payrefs text[], check_id uuid, verdict text, evidence text, checked_by text, checked_at timestamptz,
               open_requests int)
LANGUAGE sql STABLE AS $$
    WITH lg AS MATERIALIZED (
        SELECT r.student_id, r.session, r.purpose, r.amount, r.reference, (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date AS day
          FROM finance.payment_reference r
         WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND r.confirmed_at IS NOT NULL
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
$$;
COMMENT ON FUNCTION finance.possible_double_charges(text) IS
  'V561: old-portal payment records of one student, session, item, Lagos day and amount (to the naira) under two or more payment numbers — possibly the bank charging twice — for the session (every session when NULL), with the Bursary''s check against the bank and the withdrawals waiting.';

-- ── 3 · a payment the bank never received ────────────────────────────────────────────────────────────────────────────────
-- why an old-portal record cannot be withdrawn as not received, or NULL
CREATE FUNCTION finance.not_received_refusal(p_payment uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE
             WHEN r.id IS NULL THEN 'PAY_NOT_RECEIVED_NO_RECORD'
             WHEN r.channel IS DISTINCT FROM 'Legacy' OR r.reference NOT LIKE 'MOAUM-LEG-%' OR r.confirmed_at IS NULL THEN 'PAY_NOT_RECEIVED_NOT_OLD_PORTAL'
             WHEN (SELECT count(*) FROM finance.legacy_payref k WHERE k.reference = r.reference) > 1
                  OR r.note ~ '^[2-9][0-9]* school-fees payment\(s\), migrated' THEN 'PAY_NOT_RECEIVED_SUMMED'
             WHEN finance.payment_reference_linked(r.reference, r.id) THEN 'PAY_NOT_RECEIVED_LINKED'
             WHEN EXISTS (SELECT 1 FROM finance.payment_swap w WHERE w.reference = r.reference AND w.status IN ('PENDING_APPROVAL', 'COMPLETED')) THEN 'PAY_NOT_RECEIVED_SWAPPED'
             WHEN r.purpose LIKE 'School fees%' AND EXISTS (SELECT 1 FROM finance.overpayment_settled(r.student_id, r.session)) THEN 'PAY_NOT_RECEIVED_DECIDED'
           END
      FROM (SELECT 1) one LEFT JOIN finance.payment_reference r ON r.id = p_payment
$$;

CREATE FUNCTION finance.raise_not_received(p_code text)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    CASE p_code
      WHEN 'PAY_NOT_RECEIVED_NO_RECORD' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_NO_RECORD: no such payment record (it may already be withdrawn)' USING ERRCODE = '23514';
      WHEN 'PAY_NOT_RECEIVED_NOT_OLD_PORTAL' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_NOT_OLD_PORTAL: only an old-portal payment record (MOAUM-LEG-…) is withdrawn here; a portal payment is settled with the gateway' USING ERRCODE = '23514';
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
END $$;

CREATE FUNCTION finance.propose_not_received(p_reference text, p_evidence text, p_reason text, p_check uuid DEFAULT NULL, p_kept text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.bursary_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.payment_reference; v_ref text; v_kept text; v_payref text;
BEGIN
    IF length(btrim(coalesce(p_evidence, ''))) < 5 THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_EVIDENCE: name the evidence — the bank statement and its date, or the gateway''s report' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_REASON: say why (at least ten characters); it is kept with the withdrawal' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(p_reference)) FOR UPDATE;
    PERFORM finance.raise_not_received(finance.not_received_refusal(r.id));
    IF EXISTS (SELECT 1 FROM finance.payment_not_received w WHERE w.reference = r.reference AND w.state = 'PROPOSED') THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_OPEN: a withdrawal of % is already waiting for approval', r.reference USING ERRCODE = '23514';
    END IF;
    SELECT k.payref INTO v_payref FROM finance.legacy_payref k WHERE k.reference = r.reference;
    -- the record of the same day that stands, when the withdrawal comes from a bank check
    v_kept := nullif(upper(btrim(coalesce(p_kept, ''))), '');
    v_ref := 'PNR/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.payment_not_received_seq')::text, 6, '0');
    INSERT INTO finance.payment_not_received (request_ref, reference, payment_id, student_id, session, purpose, amount, paid_on, payref, check_id, kept_reference,
                                              evidence, reason, raised_by, raised_office)
    VALUES (v_ref, r.reference, r.id, r.student_id, r.session, r.purpose, r.amount, (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, v_payref, p_check, v_kept,
            btrim(p_evidence), btrim(p_reason), who, office);
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION finance.propose_not_received(text, text, text, uuid, text) IS
  'V561: a Bursary officer raises the withdrawal of an old-portal payment record the bank shows never arrived, on evidence and a reason (PNR/YYYY/NNNNNN); another officer approves it.';

CREATE FUNCTION finance.check_double_charge(p_student uuid, p_session text, p_purpose text, p_paid_on date, p_amount numeric,
                                            p_verdict text, p_evidence text, p_note text, p_not_received text[])
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.bursary_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        d record; v_id uuid; v_verdict text := upper(btrim(coalesce(p_verdict, ''))); v_list text[] := coalesce(p_not_received, '{}'); x text;
BEGIN
    IF v_verdict NOT IN ('RECEIVED', 'NOT_RECEIVED') THEN
        RAISE EXCEPTION 'PAY_CHECK_VERDICT: the bank either received every payment (RECEIVED) or not all of them (NOT_RECEIVED)' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_evidence, ''))) < 5 THEN
        RAISE EXCEPTION 'PAY_CHECK_EVIDENCE: name the evidence — the bank statement and its date, or the gateway''s report' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO d FROM finance.possible_double_charges(p_session) g
     WHERE g.student_id = p_student AND g.purpose = p_purpose AND g.paid_on = p_paid_on AND g.amount = round(p_amount);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAY_CHECK_NOT_LISTED: those payments are not a possible double charge (any more)' USING ERRCODE = '23514';
    END IF;
    IF d.open_requests > 0 THEN
        RAISE EXCEPTION 'PAY_CHECK_OPEN_REQUEST: a withdrawal of one of these payments waits for approval; decide or cancel it first' USING ERRCODE = '23514';
    END IF;
    v_list := ARRAY(SELECT DISTINCT upper(btrim(y)) FROM unnest(v_list) y WHERE btrim(y) <> '');
    IF v_verdict = 'RECEIVED' AND cardinality(v_list) > 0 THEN
        RAISE EXCEPTION 'PAY_CHECK_NOT_RECEIVED_LIST: payments the bank received are not withdrawn' USING ERRCODE = '23514';
    END IF;
    IF v_verdict = 'NOT_RECEIVED' AND (cardinality(v_list) = 0 OR cardinality(v_list) >= d.payments
                                       OR EXISTS (SELECT 1 FROM unnest(v_list) y WHERE NOT (y = ANY (d.refs)))) THEN
        RAISE EXCEPTION 'PAY_CHECK_NOT_RECEIVED_LIST: name the records of this group the bank did not receive — at least one, and not all' USING ERRCODE = '23514',
            HINT = 'When the bank received none of them, withdraw each on its own from Payments not received.';
    END IF;
    PERFORM set_config('moaum.reason', left('Bank check of a possible double charge: ' || v_verdict || ' — ' || btrim(p_evidence), 2000), true);
    INSERT INTO finance.double_charge_check (student_id, session, purpose, paid_on, amount, verdict, evidence, note, not_received, checked_by, actor_office)
    VALUES (p_student, d.session, d.purpose, d.paid_on, d.amount, v_verdict, btrim(p_evidence), nullif(btrim(coalesce(p_note, '')), ''), v_list, who, office)
    ON CONFLICT (student_id, session, purpose, paid_on, amount) DO UPDATE SET
        verdict = EXCLUDED.verdict, evidence = EXCLUDED.evidence, note = EXCLUDED.note, not_received = EXCLUDED.not_received,
        checked_by = EXCLUDED.checked_by, actor_office = EXCLUDED.actor_office, checked_at = now()
    RETURNING id INTO v_id;
    FOREACH x IN ARRAY v_list LOOP
        PERFORM finance.propose_not_received(x, p_evidence,
            coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'The bank shows this payment never arrived; the other payment of the same day stands'), v_id,
            (SELECT min(y) FROM unnest(d.refs) y WHERE NOT (y = ANY (v_list))));
    END LOOP;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION finance.check_double_charge(uuid, text, text, date, numeric, text, text, text, text[]) IS
  'V561: a Bursary officer records what the bank shows for a possible double charge — RECEIVED, or NOT_RECEIVED naming the records that did not arrive (at least one did), each then raised for withdrawal on the same evidence.';

CREATE FUNCTION finance.decide_not_received(p_request text, p_approve boolean, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
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
    DELETE FROM finance.payment_reference WHERE id = r.id;
    UPDATE finance.payment_not_received SET state = 'APPROVED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
                                            ledger_journal = gf.journal, reversal_journal = gf.reversal
     WHERE id = q.id;
    PERFORM platform.tell_student(q.student_id, 'PAYMENT_NOT_RECEIVED_REMOVED', NULL,
        jsonb_build_object('AMOUNT', 'NGN ' || to_char(q.amount, 'FM999,999,990.00'), 'PAID_ON', coalesce(to_char(q.paid_on, 'DD Mon YYYY'), 'the date recorded'),
                           'SESSION', q.session, 'REFERENCE', q.reference),
        'payment-not-received:' || q.id);
    RETURN 'APPROVED';
END $$;
COMMENT ON FUNCTION finance.decide_not_received(text, boolean, text) IS
  'V561: another Bursary officer approves (the record withdrawn: ledger journal reversed and freed, kept on finance.old_payment_withdrawn as NOT_RECEIVED, its payment number on finance.legacy_payref_withdrawn, the student told) or rejects (with a note) a withdrawal of a payment the bank never received.';

CREATE FUNCTION finance.cancel_not_received(p_request text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.bursary_actor(); office text := nullif(current_setting('moaum.actor_office', true), ''); q finance.payment_not_received;
BEGIN
    SELECT * INTO q FROM finance.payment_not_received WHERE request_ref = upper(btrim(p_request)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAY_NOT_RECEIVED_NO_REQUEST: no withdrawal %', p_request USING ERRCODE = '23514'; END IF;
    IF q.state <> 'PROPOSED' THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_SETTLED: % is already %', q.request_ref, lower(q.state) USING ERRCODE = '23514';
    END IF;
    IF q.raised_by <> who THEN
        RAISE EXCEPTION 'PAY_NOT_RECEIVED_NOT_YOURS: only the officer who raised a withdrawal cancels it; another officer rejects it' USING ERRCODE = '42501';
    END IF;
    UPDATE finance.payment_not_received SET state = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now() WHERE id = q.id;
    RETURN 'CANCELLED';
END $$;

-- ── 4 · the export loaded again never brings a withdrawn payment back ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.import_legacy_payments(p_rows jsonb)
 RETURNS TABLE(rows integer, cleared integer, no_student integer, no_due integer, duplicates integer, duplicate_sample text, corrected integer, undated integer, matched integer, separate integer, taken_over integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_payref text; v_channel text; v_separate boolean; st people.student; ex finance.payment_reference;
        ph finance.payment_reference; gf record;
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

        SELECT * INTO st FROM people.student WHERE upper(matric_no) = v_matric OR upper(admission_no) = v_matric LIMIT 1;
        IF st.id IS NULL THEN nns := nns + 1; CONTINUE; END IF;
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
                IF v_given IS NOT NULL AND ex.note !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'
                   AND (ex.confirmed_at AT TIME ZONE 'Africa/Lagos')::date IS DISTINCT FROM (v_given AT TIME ZONE 'Africa/Lagos')::date THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given,
                           note = CASE WHEN note LIKE '%old ref %' THEN note ELSE v_note END
                     WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSIF ex.note NOT LIKE '%old ref %' THEN
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
            IF ex.id IS NOT NULL THEN
                IF ex.channel = 'Legacy' AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
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
        ELSE
            nd := nd + 1; v_dups := v_dups || coalesce(v_payref, v_ref);
        END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund, nm, nsep, ntk;
END $function$;
COMMENT ON FUNCTION finance.import_legacy_payments(jsonb) IS
  'V498, V502, V561: Old Fees History''s import — the old portal''s payment number decides (a number seen before, or withdrawn because the bank never received it, is never recorded again); restated by V561 from V502''s definition with that one change.';

-- ── 5 · an overpayment decided only once the bank has answered ────────────────────────────────────────────────────────────
DROP FUNCTION finance.decide_overpayments(text, text, uuid[], text, int);
CREATE FUNCTION finance.decide_overpayments(p_session text, p_decision text, p_students uuid[], p_reason text, p_limit int DEFAULT 2000)
RETURNS TABLE (carried int, refunds int, held int, remaining int)
LANGUAGE plpgsql AS $fn$
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
                       WHERE r.student_id = o.student_id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
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
END $fn$;
COMMENT ON FUNCTION finance.decide_overpayments(text, text, uuid[], text, int) IS
  'V506, V519, V561: the Bursary''s decision for up to p_limit overpaid students of a session not yet decided (all, or those named): CARRY — a confirmed CARRIED school-fees record of the excess in the next session, its journal moving the income across (no cash) — or REFUND — a refund raised on the Refunds & Credits desk against the payment that covers the excess; each kept on finance.overpayment_decision with the reason, the student told (V519). V561: a student with a possible school-fees double charge not yet checked against the bank, or a withdrawal waiting, is held. Returns what was carried, refunded, held, and what remains undecided.';

-- ── 6 · the student told ─────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYMENT_NOT_RECEIVED_REMOVED', 'An old-portal payment the bank never received removed',
 'To a student when the Bursary removes an old-portal payment record that the bank statement shows never reached the University',
 'A payment record of [AMOUNT] has been removed from your [SESSION] fees',
 E'Dear [FIRST_NAME],\n\nThe old portal recorded a payment of [AMOUNT] on [PAID_ON] for [SESSION] (reference [REFERENCE]). The University''s bank statement shows that this payment never reached the University, so the Bursary has removed the record. Your other payments are unchanged.\n\nYour fees page shows what is now paid and what is still owed: [PORTAL_URL]\n\nIf your bank debited you for it, keep the debit alert and write to the Bursary.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: a [AMOUNT] payment record of [PAID_ON] ([SESSION], ref [REFERENCE]) was removed: the bank shows it never reached the University. See your fees page.',
 'A payment record was removed',
 'The [AMOUNT] payment recorded on [PAID_ON] for [SESSION] (reference [REFERENCE]) never reached the University''s bank, so the Bursary removed it. Your fees page shows what is now owed.',
 ARRAY['FIRST_NAME','AMOUNT','PAID_ON','SESSION','REFERENCE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL');

-- ── 7 · grants, as V498 gives the old-fees tables ────────────────────────────────────────────────────────────────────────
GRANT SELECT ON finance.double_charge_check, finance.payment_not_received, finance.legacy_payref_withdrawn TO app_auditor, app_reporting;

COMMIT;
