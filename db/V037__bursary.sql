-- ═══════════════════════════════════════════════════════════════════════════
-- V037 — the Bursary's desk: gateway events, hanging payments, bank credits
--
--   A callback is a hint, not an instruction (proto/part18): the portal
--   never credits a student because a gateway said so without keeping what
--   it said. Every webhook that reaches the portal is written here —
--   signature good or bad, reference known or not, settled, short, or
--   ignored — so the Bursary can read the gateway's own words beside what
--   the portal did with them. A checkout the student opened is an attempt;
--   an attempt with no confirmation behind it is a hanging payment, and the
--   reconciler asks the gateway about it rather than the student.
--
--   Money that arrives at a bank counter with no reference quoted is a
--   bank credit: recorded as it came, proposed against a reference by one
--   officer with the reason, approved by a second, and only then posted —
--   as the same confirmation every payment passes. The bank record is never
--   altered; the posting is a new entry that points at it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE finance.gateway_event (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway       text NOT NULL,
    source        text NOT NULL DEFAULT 'WEBHOOK',
    event         text NULL,
    reference     text NULL,
    gateway_ref   text NULL,
    amount        numeric(12,2) NULL,
    status        text NULL,
    signature_ok  boolean NOT NULL,
    outcome       text NOT NULL,
    payload       jsonb NULL,
    received_at   timestamptz NOT NULL DEFAULT now(),
    resolved_at   timestamptz NULL,
    resolved_by   uuid NULL,
    resolution    text NULL,
    CONSTRAINT ck_ge_source CHECK (source IN ('WEBHOOK','VERIFY','SWEEP','TEST')),
    CONSTRAINT ck_ge_outcome CHECK (outcome IN ('SETTLED','ALREADY_SETTLED','UNKNOWN_REFERENCE','SHORT_PAID','NOT_SUCCESSFUL','IGNORED','BAD_SIGNATURE','GATEWAY_ERROR')),
    CONSTRAINT ck_ge_resolved CHECK (resolved_at IS NULL OR resolution IS NOT NULL)
);
CREATE INDEX ix_ge_received ON finance.gateway_event (received_at DESC);
CREATE INDEX ix_ge_reference ON finance.gateway_event (reference);
SELECT audit.attach('finance.gateway_event');

CREATE TABLE finance.gateway_attempt (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference   text NOT NULL,
    gateway     text NOT NULL,
    kind        text NOT NULL,
    account_id  uuid NOT NULL,
    opened_at   timestamptz NOT NULL DEFAULT now(),
    checked_at  timestamptz NULL,
    checks      int NOT NULL DEFAULT 0
);
CREATE INDEX ix_ga_reference ON finance.gateway_attempt (reference, opened_at DESC);
SELECT audit.attach('finance.gateway_attempt');

CREATE TABLE finance.bank_credit (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    received_on   date NOT NULL,
    bank          text NOT NULL,
    instrument    text NOT NULL,
    amount        numeric(12,2) NOT NULL,
    payer         text NULL,
    note          text NULL,
    recorded_by   uuid NOT NULL,
    recorded_at   timestamptz NOT NULL DEFAULT now(),
    state         text NOT NULL DEFAULT 'UNMATCHED',
    proposed_reference text NULL,
    proposed_by   uuid NULL,
    proposed_why  text NULL,
    proposed_at   timestamptz NULL,
    approved_by   uuid NULL,
    approved_at   timestamptz NULL,
    posted_reference text NULL,
    rejected_why  text NULL,
    CONSTRAINT ck_bc_amount CHECK (amount > 0),
    CONSTRAINT ck_bc_state CHECK (state IN ('UNMATCHED','PROPOSED','POSTED','REVERSED')),
    CONSTRAINT ck_bc_instrument CHECK (btrim(instrument) <> ''),
    CONSTRAINT ck_bc_two_people CHECK (approved_by IS NULL OR proposed_by IS NULL OR approved_by <> proposed_by)
);
CREATE UNIQUE INDEX uq_bc_instrument ON finance.bank_credit (bank, instrument) WHERE state <> 'REVERSED';
SELECT audit.attach('finance.bank_credit');

-- ── the gateway's words, kept ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.log_gateway_event(p_gateway text, p_source text, p_event text, p_reference text, p_gateway_ref text,
                                                     p_amount numeric, p_status text, p_signature_ok boolean, p_outcome text, p_payload jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    INSERT INTO finance.gateway_event (id, gateway, source, event, reference, gateway_ref, amount, status, signature_ok, outcome, payload)
    VALUES (v, p_gateway, coalesce(p_source, 'WEBHOOK'), p_event, nullif(upper(btrim(p_reference)), ''), p_gateway_ref, p_amount, p_status, p_signature_ok, p_outcome, p_payload);
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION finance.resolve_gateway_event(p_event uuid, p_resolution text)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_resolution IS NULL OR btrim(p_resolution) = '' THEN RAISE EXCEPTION 'an event is resolved with a reason on the record' USING ERRCODE = '23514'; END IF;
    UPDATE finance.gateway_event SET resolved_at = now(), resolved_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, resolution = btrim(p_resolution)
     WHERE id = p_event AND resolved_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'no open event %', p_event USING ERRCODE = 'no_data_found'; END IF;
END $$;

-- ── what stands for a reference, whoever generated it ──────────────────
CREATE OR REPLACE FUNCTION finance.reference_state(p_reference text)
RETURNS TABLE (kind text, amount numeric, confirmed_at timestamptz, expires_at timestamptz, channel text, receipt_no text)
LANGUAGE sql STABLE AS $$
    SELECT 'STUDENT', r.amount, r.confirmed_at, r.expires_at, r.channel, r.receipt_no FROM finance.payment_reference r WHERE r.reference = upper(btrim(p_reference))
    UNION ALL
    SELECT f.kind, f.amount, f.confirmed_at, f.expires_at, f.channel, NULL FROM admissions.fee_reference f WHERE f.reference = upper(btrim(p_reference))
    LIMIT 1
$$;

-- ── the day book: every confirmation, whoever paid ──────────────────────
CREATE OR REPLACE FUNCTION finance.day_book(p_from date, p_to date)
RETURNS TABLE (reference text, confirmed_at timestamptz, payer text, number text, purpose text, amount numeric, channel text, receipt_no text, note text, session text)
LANGUAGE sql STABLE AS $$
    SELECT r.reference, r.confirmed_at, s.surname || ', ' || s.other_names, coalesce(s.matric_no, s.admission_no), r.purpose, r.amount, r.channel, r.receipt_no, r.note, r.session
      FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id
     WHERE r.confirmed_at IS NOT NULL AND r.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT f.reference, f.confirmed_at, c.surname || ', ' || c.other_names, a.application_no,
           CASE f.kind WHEN 'APPLICATION' THEN 'Application fee' ELSE 'Acceptance fee' END, f.amount, f.channel, NULL, f.note, a.session
      FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE f.confirmed_at IS NOT NULL AND f.confirmed_at::date BETWEEN p_from AND p_to
    ORDER BY 2 DESC
$$;

-- ── collection by faculty, this session: what the register says was paid ──
CREATE OR REPLACE FUNCTION finance.collection_by_faculty(p_session text)
RETURNS TABLE (faculty_code text, faculty_name text, students bigint, paid_students bigint, collected numeric, due numeric)
LANGUAGE sql STABLE AS $$
    WITH enrolled AS (
        SELECT s.id, p.faculty_code FROM people.enrolment e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
         WHERE e.session = p_session),
    paid AS (
        SELECT r.student_id, sum(r.amount) AS amount FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%' GROUP BY r.student_id)
    SELECT f.code, f.name, count(en.id), count(pd.student_id), coalesce(sum(pd.amount), 0),
           coalesce(sum((SELECT coalesce(sum(c.amount), 0) FROM finance.charges(en.id, p_session) c)), 0)
      FROM ref.faculty f LEFT JOIN enrolled en ON en.faculty_code = f.code LEFT JOIN paid pd ON pd.student_id = en.id
     GROUP BY f.code, f.name HAVING count(en.id) > 0 ORDER BY f.name
$$;

-- ── a bank credit: recorded as it came, proposed by one, approved by another, then posted ──
CREATE OR REPLACE FUNCTION finance.record_bank_credit(p_received date, p_bank text, p_instrument text, p_amount numeric, p_payer text, p_note text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN RAISE EXCEPTION 'a bank credit is recorded by a person' USING ERRCODE = '23514'; END IF;
    INSERT INTO finance.bank_credit (id, received_on, bank, instrument, amount, payer, note, recorded_by)
    VALUES (v, coalesce(p_received, current_date), btrim(p_bank), btrim(p_instrument), p_amount, nullif(btrim(p_payer), ''), nullif(btrim(p_note), ''),
            current_setting('moaum.actor_id', true)::uuid);
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION finance.propose_bank_credit(p_credit uuid, p_reference text, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE c finance.bank_credit; st record; v_ref text := upper(btrim(p_reference));
BEGIN
    SELECT * INTO c FROM finance.bank_credit WHERE id = p_credit FOR UPDATE;
    IF NOT FOUND OR c.state NOT IN ('UNMATCHED','PROPOSED') THEN RAISE EXCEPTION 'credit % is not open', p_credit USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a proposal says on what evidence the money belongs there' USING ERRCODE = '23514'; END IF;
    SELECT * INTO st FROM finance.reference_state(v_ref);
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', v_ref USING ERRCODE = '23503'; END IF;
    IF st.confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'reference % is already confirmed', v_ref USING ERRCODE = '23505',
        HINT = 'Money against a settled reference is a duplicate: raise a credit for the student, not a second posting.'; END IF;
    IF st.amount > c.amount THEN RAISE EXCEPTION 'the credit of % is less than the % the reference asks', c.amount, st.amount USING ERRCODE = '23514',
        HINT = 'A part payment is applied against a reference for the part; generate one for the amount received.'; END IF;
    UPDATE finance.bank_credit SET state = 'PROPOSED', proposed_reference = v_ref, proposed_why = btrim(p_why),
           proposed_by = current_setting('moaum.actor_id', true)::uuid, proposed_at = now(), approved_by = NULL, approved_at = NULL
     WHERE id = p_credit;
END $$;

CREATE OR REPLACE FUNCTION finance.approve_bank_credit(p_credit uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE c finance.bank_credit; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_out text; st record;
BEGIN
    SELECT * INTO c FROM finance.bank_credit WHERE id = p_credit FOR UPDATE;
    IF NOT FOUND OR c.state <> 'PROPOSED' THEN RAISE EXCEPTION 'credit % has no proposal to approve', p_credit USING ERRCODE = '23514'; END IF;
    IF v_actor IS NULL OR v_actor = c.proposed_by THEN
        RAISE EXCEPTION 'the officer who proposed a posting does not approve it' USING ERRCODE = '23514',
            HINT = 'Money moves onto a student record only when two people have independently agreed that it belongs there.';
    END IF;
    SELECT * INTO st FROM finance.reference_state(c.proposed_reference);
    IF st.kind = 'STUDENT' THEN
        v_out := finance.confirm_payment(c.proposed_reference, 'Bank branch', c.bank || ' ' || c.instrument || ' · proposed: ' || c.proposed_why);
    ELSE
        v_out := admissions.confirm_fee(c.proposed_reference, 'Bank branch', c.bank || ' ' || c.instrument || ' · proposed: ' || c.proposed_why);
    END IF;
    UPDATE finance.bank_credit SET state = 'POSTED', approved_by = v_actor, approved_at = now(), posted_reference = c.proposed_reference WHERE id = p_credit;
    RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION finance.reject_bank_credit(p_credit uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a rejection says why' USING ERRCODE = '23514'; END IF;
    UPDATE finance.bank_credit SET state = 'UNMATCHED', rejected_why = btrim(p_why), proposed_reference = NULL, proposed_why = NULL, proposed_by = NULL, proposed_at = NULL
     WHERE id = p_credit AND state = 'PROPOSED';
    IF NOT FOUND THEN RAISE EXCEPTION 'credit % has no proposal', p_credit USING ERRCODE = 'no_data_found'; END IF;
END $$;

COMMIT;
