-- ═══════════════════════════════════════════════════════════════════════════
-- V043 — refunds and credits, maker–checker controlled
--
--   The University pays money out on a refund: an overpayment, a duplicate
--   payment after a timeout, a withdrawal, an over-remittance by a sponsor. The
--   officer who raises a refund cannot approve it — the database refuses the
--   second click rather than relying on anyone to remember the rule, exactly as
--   a bank credit is posted (V037). A refund is paid only after it is approved,
--   and the account it pays into is snapshotted at proposal so a later edit of
--   the student's bank details cannot redirect money already approved.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE finance.refund (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference     text NOT NULL UNIQUE,
    student_id    uuid NULL REFERENCES people.student(id),
    payer         text NOT NULL,
    reason        text NOT NULL,
    amount        numeric(14,2) NOT NULL,
    bank_name     text NULL,
    account_name  text NULL,
    account_last4 text NULL,
    state         text NOT NULL DEFAULT 'PROPOSED',
    proposed_by   uuid NOT NULL,
    proposed_at   timestamptz NOT NULL DEFAULT now(),
    approved_by   uuid NULL,
    approved_at   timestamptz NULL,
    rejected_why  text NULL,
    paid_at       timestamptz NULL,
    paid_by       uuid NULL,
    CONSTRAINT ck_rf_amount CHECK (amount > 0),
    CONSTRAINT ck_rf_state CHECK (state IN ('PROPOSED','APPROVED','REJECTED','PAID')),
    CONSTRAINT ck_rf_two_people CHECK (approved_by IS NULL OR approved_by <> proposed_by)
);
CREATE INDEX ix_refund_state ON finance.refund (state, proposed_at DESC);
SELECT audit.attach('finance.refund');

CREATE OR REPLACE FUNCTION finance.propose_refund(p_student uuid, p_payer text, p_reason text, p_amount numeric,
                                                  p_bank text, p_account_name text, p_account_last4 text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a refund is raised by a person' USING ERRCODE = '23514'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'a refund is for an amount' USING ERRCODE = '23514'; END IF;
    IF p_payer IS NULL OR btrim(p_payer) = '' THEN RAISE EXCEPTION 'a refund names who it is paid to' USING ERRCODE = '23514'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'a refund carries the reason it is owed' USING ERRCODE = '23514'; END IF;
    v_ref := 'RF-' || to_char(current_date, 'YYYY') || '-' ||
             lpad(platform.next_number('REFUND', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    INSERT INTO finance.refund (reference, student_id, payer, reason, amount, bank_name, account_name, account_last4, proposed_by)
    VALUES (v_ref, p_student, btrim(p_payer), btrim(p_reason), p_amount,
            nullif(btrim(coalesce(p_bank, '')), ''), nullif(btrim(coalesce(p_account_name, '')), ''), nullif(btrim(coalesce(p_account_last4, '')), ''), who);
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION finance.approve_refund(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r finance.refund; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO r FROM finance.refund WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'PROPOSED' THEN RAISE EXCEPTION 'refund % has no proposal to approve', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL OR who = r.proposed_by THEN
        RAISE EXCEPTION 'the officer who raised a refund does not approve it' USING ERRCODE = '23514',
            HINT = 'Money leaves the University only when two people have independently agreed it is owed.';
    END IF;
    UPDATE finance.refund SET state = 'APPROVED', approved_by = who, approved_at = now() WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION finance.reject_refund(p_id uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a refund is decided by a person' USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a rejection is recorded with its reason' USING ERRCODE = '23514'; END IF;
    UPDATE finance.refund SET state = 'REJECTED', rejected_why = btrim(p_why) WHERE id = p_id AND state = 'PROPOSED';
    IF NOT FOUND THEN RAISE EXCEPTION 'refund % has no proposal to reject', p_id USING ERRCODE = '23514'; END IF;
END $$;

CREATE OR REPLACE FUNCTION finance.pay_refund(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r finance.refund; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO r FROM finance.refund WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'refund % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'a disbursement is recorded by a person' USING ERRCODE = '23514'; END IF;
    UPDATE finance.refund SET state = 'PAID', paid_at = now(), paid_by = who WHERE id = p_id;
END $$;
