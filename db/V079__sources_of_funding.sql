-- ═══════════════════════════════════════════════════════════════════════════
-- V079 — sources of funding: the wallet is fed from many sources, not NELFUND alone
--
--   A student's fees can be met from more than one source at once. NELFUND is a
--   LOAN the student repays the Fund after graduation; a scholarship or bursary
--   is a GRANT that is never repaid; a top-up is the student's OWN money. The
--   sources are a setting the Bursary keeps — NELFUND is seeded as one of them.
--
--   Every wallet credit now carries the source it came from, so the ledger and
--   the reports can say where each naira came from and whether it is repayable.
--   Students do not apply for NELFUND here (that is the Fund's own portal); the
--   University only records the crediting.
--
--   Money can also leave the wallet to a student's own bank account: once the
--   session's fees are cleared (both semesters) and nothing is owed, the balance
--   left over is the student's to withdraw — a student who paid ahead before the
--   Fund's money landed has genuinely paid twice. A withdrawal is requested by
--   the student, approved by the Bursary, and paid by a second officer; the
--   portal records the payout, it does not move the money itself.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · the sources, as a setting ───────────────────────────────────────────
CREATE TABLE finance.funding_source (
    code       text PRIMARY KEY,
    name       text NOT NULL,
    nature     text NOT NULL,
    sponsor    text NULL,
    account    text NULL,          -- the holding account the money arrives into; NULL is the main school account
    active     boolean NOT NULL DEFAULT true,
    note       text NULL,
    sort       int NOT NULL DEFAULT 100,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fsrc_nature CHECK (nature IN ('LOAN','GRANT','SELF')),
    CONSTRAINT ck_fsrc_code CHECK (btrim(code) <> '' AND code = upper(code))
);
SELECT audit.attach('finance.funding_source');

INSERT INTO finance.funding_source (code, name, nature, sponsor, account, sort, note) VALUES
    ('NELFUND', 'NELFUND institutional loan', 'LOAN', 'Nigerian Education Loan Fund',
        'NELFUND collection account', 10, 'Repaid by the student to the Fund after graduation; the money reaches a separate account and is moved to the main account when applied.'),
    ('SCHOLARSHIP', 'Scholarship / bursary award', 'GRANT', NULL, NULL, 20, 'A grant that is never repaid — add the specific scheme (TETFund, state, sponsor) as its own source.'),
    ('SELF', 'Self top-up', 'SELF', NULL, NULL, 90, 'The student''s own money, paid into the wallet.')
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION finance.upsert_funding_source(
    p_code text, p_name text, p_nature text, p_sponsor text, p_account text, p_active boolean, p_note text, p_sort int)
RETURNS finance.funding_source
LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); r finance.funding_source;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a funding source is stated by a person' USING ERRCODE = '23514';
    END IF;
    IF v_code = '' THEN RAISE EXCEPTION 'a funding source has a code' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'a funding source has a name' USING ERRCODE = '23514'; END IF;
    IF upper(coalesce(p_nature, '')) NOT IN ('LOAN','GRANT','SELF') THEN
        RAISE EXCEPTION 'a source is a LOAN (repaid), a GRANT (never repaid) or SELF (the student''s own money)' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.funding_source (code, name, nature, sponsor, account, active, note, sort)
    VALUES (v_code, btrim(p_name), upper(p_nature), nullif(btrim(p_sponsor), ''), nullif(btrim(p_account), ''),
            coalesce(p_active, true), nullif(btrim(p_note), ''), coalesce(p_sort, 100))
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, nature = EXCLUDED.nature, sponsor = EXCLUDED.sponsor,
        account = EXCLUDED.account, active = EXCLUDED.active, note = EXCLUDED.note, sort = EXCLUDED.sort
    RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 2 · every wallet credit carries its source ──────────────────────────────
ALTER TABLE finance.wallet_entry ADD COLUMN source_code text NULL REFERENCES finance.funding_source(code);

-- what is already on the ledger: NELFUND credits, and top-ups are the student's own
UPDATE finance.wallet_entry SET source_code = 'NELFUND'
 WHERE source_code IS NULL AND kind = 'CREDIT' AND note ILIKE 'NELFUND%';
UPDATE finance.wallet_entry SET source_code = 'SELF'
 WHERE source_code IS NULL AND kind = 'TOPUP';

-- a credit with no source named is tagged from what is known, so the reports never lose money into a blank
CREATE OR REPLACE FUNCTION finance.wallet_entry_source() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.source_code IS NULL THEN
        IF NEW.kind = 'TOPUP' THEN NEW.source_code := 'SELF';
        ELSIF NEW.kind = 'CREDIT' AND NEW.note ILIKE 'NELFUND%' THEN NEW.source_code := 'NELFUND';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_wallet_entry_source BEFORE INSERT ON finance.wallet_entry
    FOR EACH ROW EXECUTE FUNCTION finance.wallet_entry_source();

-- the Bursary's hand credit now names the source (a scholarship, a sponsor, a correction)
DROP FUNCTION IF EXISTS finance.credit_wallet(uuid, text, numeric, text);
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
    IF v_src IS NOT NULL AND NOT EXISTS (SELECT 1 FROM finance.funding_source WHERE code = v_src) THEN
        RAISE EXCEPTION 'no funding source is coded %', v_src USING ERRCODE = '23503',
            HINT = 'Choose a source from the settings, or add it first.';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
    VALUES (p_student, p_session, 'CREDIT', p_amount, coalesce(v_src, 'BURSARY'), 'Bursary credit: ' || btrim(p_reason), v_src)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- the statement now says the source and whether it is repayable (a new return shape, so drop and recreate)
DROP FUNCTION IF EXISTS finance.wallet_statement(uuid);
CREATE OR REPLACE FUNCTION finance.wallet_statement(p_student uuid)
RETURNS TABLE (id uuid, at timestamptz, session text, kind text, amount numeric, reference text, note text,
               source_code text, source_name text, nature text, balance numeric)
LANGUAGE sql STABLE AS $$
    SELECT e.id, e.at, e.session, e.kind, e.amount, e.reference, e.note,
           e.source_code, fs.name, fs.nature,
           sum(CASE WHEN e.kind IN ('CREDIT','TOPUP') THEN e.amount ELSE -e.amount END) OVER (ORDER BY e.at, e.id)
      FROM finance.wallet_entry e
      LEFT JOIN finance.funding_source fs ON fs.code = e.source_code
     WHERE e.student_id = p_student ORDER BY e.at, e.id
$$;

-- ── 3 · withdrawing the balance to a personal bank account ───────────────────
CREATE TABLE finance.wallet_withdrawal (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES people.student(id),
    session      text NOT NULL,
    amount       numeric(12,2) NOT NULL,
    bank_name    text NOT NULL,
    account_no   text NOT NULL,
    account_name text NOT NULL,
    state        text NOT NULL DEFAULT 'REQUESTED',
    reason       text NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    requested_by uuid NULL,
    decided_at   timestamptz NULL,
    decided_by   uuid NULL,
    paid_at      timestamptz NULL,
    paid_by      uuid NULL,
    paid_ref     text NULL,
    entry_id     uuid NULL REFERENCES finance.wallet_entry(id),
    CONSTRAINT ck_ww_amount CHECK (amount > 0),
    CONSTRAINT ck_ww_state CHECK (state IN ('REQUESTED','APPROVED','REJECTED','PAID')),
    CONSTRAINT ck_ww_two_people CHECK (paid_by IS NULL OR decided_by IS NULL OR paid_by <> decided_by)
);
CREATE INDEX ix_ww_student ON finance.wallet_withdrawal (student_id, requested_at);
CREATE INDEX ix_ww_state ON finance.wallet_withdrawal (session, state);
SELECT audit.attach('finance.wallet_withdrawal');

-- who may withdraw, and how much: fees cleared for the session, nothing in arrears, and a balance to spare
CREATE OR REPLACE FUNCTION finance.withdrawal_eligibility(p_student uuid, p_session text)
RETURNS TABLE (eligible boolean, balance numeric, cleared boolean, arrears boolean, pending boolean, reason text)
LANGUAGE plpgsql STABLE AS $$
DECLARE pos record; v_bal numeric; v_pending boolean;
BEGIN
    v_bal := finance.wallet_balance(p_student);
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    v_pending := EXISTS (SELECT 1 FROM finance.wallet_withdrawal
                          WHERE student_id = p_student AND state IN ('REQUESTED','APPROVED'));
    RETURN QUERY SELECT
        (pos.paid_in_full AND NOT pos.has_arrears AND v_bal > 0 AND NOT v_pending),
        v_bal, pos.paid_in_full, pos.has_arrears, v_pending,
        CASE WHEN v_pending THEN 'A withdrawal is already awaiting the Bursary.'
             WHEN NOT pos.paid_in_full THEN 'The ' || p_session || ' fees are not yet cleared in full.'
             WHEN pos.has_arrears THEN 'There are fees owed from a previous session.'
             WHEN v_bal <= 0 THEN 'The wallet has no balance to withdraw.'
             ELSE 'The balance may be withdrawn to a bank account.' END;
END $$;

CREATE OR REPLACE FUNCTION finance.request_withdrawal(
    p_student uuid, p_session text, p_amount numeric, p_bank text, p_account_no text, p_account_name text)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE elig record; v_amount numeric; r finance.wallet_withdrawal;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is requested by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO elig FROM finance.withdrawal_eligibility(p_student, p_session);
    IF NOT elig.eligible THEN RAISE EXCEPTION '%', elig.reason USING ERRCODE = '23514'; END IF;
    v_amount := coalesce(p_amount, elig.balance);
    IF v_amount <= 0 THEN RAISE EXCEPTION 'a withdrawal is for an amount above zero' USING ERRCODE = '23514'; END IF;
    IF v_amount > elig.balance THEN
        RAISE EXCEPTION 'the wallet holds NGN %; only that much may be withdrawn', elig.balance USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_bank), '') = '' OR coalesce(btrim(p_account_no), '') = '' OR coalesce(btrim(p_account_name), '') = '' THEN
        RAISE EXCEPTION 'a withdrawal names the bank, the account number and the account name' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.wallet_withdrawal (student_id, session, amount, bank_name, account_no, account_name, requested_by)
    VALUES (p_student, p_session, v_amount, btrim(p_bank), btrim(p_account_no), btrim(p_account_name),
            current_setting('moaum.actor_id', true)::uuid)
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION finance.approve_withdrawal(p_id uuid)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal; elig record;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is approved by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'REQUESTED' THEN RAISE EXCEPTION 'withdrawal % is not awaiting a decision', p_id USING ERRCODE = '23514'; END IF;
    -- the balance and clearance must still hold at the moment of approval
    SELECT * INTO elig FROM finance.withdrawal_eligibility(r.student_id, r.session);
    IF finance.wallet_balance(r.student_id) < r.amount THEN
        RAISE EXCEPTION 'the wallet no longer holds NGN %', r.amount USING ERRCODE = '23514';
    END IF;
    UPDATE finance.wallet_withdrawal SET state = 'APPROVED', decided_at = now(),
           decided_by = current_setting('moaum.actor_id', true)::uuid WHERE id = p_id
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION finance.reject_withdrawal(p_id uuid, p_why text)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a withdrawal is decided by a person' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_why), '') = '' THEN RAISE EXCEPTION 'a rejection says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state NOT IN ('REQUESTED','APPROVED') THEN RAISE EXCEPTION 'withdrawal % cannot be rejected', p_id USING ERRCODE = '23514'; END IF;
    UPDATE finance.wallet_withdrawal SET state = 'REJECTED', reason = btrim(p_why), decided_at = now(),
           decided_by = current_setting('moaum.actor_id', true)::uuid WHERE id = p_id
    RETURNING * INTO r;
    RETURN r;
END $$;

-- paid by a second officer: the money leaves the wallet as a REFUND, and the payout reference is on the record
CREATE OR REPLACE FUNCTION finance.pay_withdrawal(p_id uuid, p_ref text)
RETURNS finance.wallet_withdrawal
LANGUAGE plpgsql AS $$
DECLARE r finance.wallet_withdrawal; v_actor uuid; v_entry uuid;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a payout is made by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.wallet_withdrawal WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'withdrawal % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF r.decided_by = v_actor THEN
        RAISE EXCEPTION 'the officer who approved a withdrawal does not also pay it' USING ERRCODE = '23514',
            HINT = 'A second officer records the payout.';
    END IF;
    IF finance.wallet_balance(r.student_id) < r.amount THEN
        RAISE EXCEPTION 'the wallet no longer holds NGN %', r.amount USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
    VALUES (r.student_id, r.session, 'REFUND', r.amount, nullif(btrim(p_ref), ''),
            'Withdrawn to ' || r.bank_name || ' ' || r.account_no, NULL)
    RETURNING id INTO v_entry;
    UPDATE finance.wallet_withdrawal SET state = 'PAID', paid_at = now(), paid_by = v_actor,
           paid_ref = nullif(btrim(p_ref), ''), entry_id = v_entry WHERE id = p_id
    RETURNING * INTO r;
    RETURN r;
END $$;

CREATE OR REPLACE FUNCTION finance.withdrawal_queue(p_session text)
RETURNS TABLE (id uuid, student_id uuid, matric_no text, student_name text, session text, amount numeric,
               bank_name text, account_no text, account_name text, state text, reason text,
               requested_at timestamptz, decided_at timestamptz, paid_at timestamptz, paid_ref text)
LANGUAGE sql STABLE AS $$
    SELECT w.id, w.student_id, s.matric_no, s.surname || ', ' || s.other_names, w.session, w.amount,
           w.bank_name, w.account_no, w.account_name, w.state, w.reason,
           w.requested_at, w.decided_at, w.paid_at, w.paid_ref
      FROM finance.wallet_withdrawal w JOIN people.student s ON s.id = w.student_id
     WHERE p_session IS NULL OR w.session = p_session
     ORDER BY CASE w.state WHEN 'REQUESTED' THEN 0 WHEN 'APPROVED' THEN 1 ELSE 2 END, w.requested_at DESC
$$;

-- ── 4 · the reports ─────────────────────────────────────────────────────────
-- what came in, by source and nature, for the session
CREATE OR REPLACE FUNCTION finance.funding_summary(p_session text)
RETURNS TABLE (code text, name text, nature text, sponsor text, account text, students bigint, credited numeric)
LANGUAGE sql STABLE AS $$
    SELECT fs.code, fs.name, fs.nature, fs.sponsor, fs.account,
           count(DISTINCT e.student_id) AS students,
           coalesce(sum(e.amount), 0) AS credited
      FROM finance.funding_source fs
      LEFT JOIN finance.wallet_entry e
             ON e.source_code = fs.code AND e.kind IN ('CREDIT','TOPUP')
            AND (p_session IS NULL OR e.session = p_session)
     GROUP BY fs.code, fs.name, fs.nature, fs.sponsor, fs.account, fs.sort
     ORDER BY fs.sort, fs.name
$$;

-- the wallet's cash flow for the session, and the reconciliation with school payments
CREATE OR REPLACE FUNCTION finance.wallet_cashflow(p_session text)
RETURNS TABLE (credited numeric, topped_up numeric, applied numeric, reversed numeric, withdrawn numeric,
               held numeric, loans_in numeric, grants_in numeric, self_in numeric,
               settled_to_fees numeric, applied_matches boolean)
LANGUAGE sql STABLE AS $$
    WITH e AS (
        SELECT e.*, fs.nature FROM finance.wallet_entry e
          LEFT JOIN finance.funding_source fs ON fs.code = e.source_code
         WHERE p_session IS NULL OR e.session = p_session),
    settled AS (
        SELECT coalesce(sum(amount), 0) AS s FROM finance.payment_reference
         WHERE channel = 'NELFUND wallet' AND confirmed_at IS NOT NULL AND (p_session IS NULL OR session = p_session))
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
$$;

COMMIT;
