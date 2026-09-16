-- ═══════════════════════════════════════════════════════════════════════════
-- V145 — the Bursary's books: a proper double-entry general ledger
--
--   The Bursary already records cash: confirmed payments, refunds, paid
--   vouchers. What it lacked was bookkeeping — a chart of accounts, balanced
--   journals, a ledger per account, a trial balance and financial statements.
--   This adds that, cash-basis (income when money is received, expenditure when
--   paid) but structured so accrual can be layered on later (receivable and
--   payable accounts already exist in the chart, simply unused for now).
--
--   Money reaches the ledger two ways:
--     • Automatically — finance.gl_sync() sweeps every confirmed payment, paid
--       refund and paid voucher not yet on the books and posts a balanced
--       journal for it. It is idempotent: a transaction is posted once, keyed
--       by (source_type, source_ref). Run it on a schedule or from the screen.
--     • By hand — finance.gl_post(...) lets the Bursar enter opening balances,
--       adjustments and corrections as balanced journals; a mistake is undone
--       by finance.gl_reverse(), never by editing a posted line.
--
--   Nothing here touches the existing cash tables; the ledger is a faithful
--   second view of them, kept in balance by construction.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the chart of accounts ──────────────────────────────────────────────────
CREATE TABLE finance.gl_account (
    code        text PRIMARY KEY,
    name        text NOT NULL,
    type        text NOT NULL CHECK (type IN ('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE')),
    normal_side char(1) NOT NULL CHECK (normal_side IN ('D','C')),
    parent_code text NULL REFERENCES finance.gl_account(code),
    postable    boolean NOT NULL DEFAULT true,   -- false = a heading that only rolls up its children
    active      boolean NOT NULL DEFAULT true,
    ord         int NOT NULL DEFAULT 0,
    CONSTRAINT ck_gl_acct_code CHECK (btrim(code) <> ''),
    CONSTRAINT ck_gl_acct_name CHECK (btrim(name) <> '')
);
COMMENT ON TABLE finance.gl_account IS 'Chart of accounts: assets, liabilities, fund, income and expenditure.';

-- ── the journal (a balanced set of postings) ───────────────────────────────
CREATE SEQUENCE finance.gl_journal_no START 1;

CREATE TABLE finance.gl_journal (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_no  bigint NOT NULL UNIQUE DEFAULT nextval('finance.gl_journal_no'),
    entry_date  date NOT NULL,
    memo        text NOT NULL,
    source      text NOT NULL DEFAULT 'MANUAL' CHECK (source IN ('MANUAL','AUTO')),
    source_type text NULL,   -- PAYMENT · REFUND · VOUCHER · OPENING · ADJUSTMENT · REVERSAL
    source_ref  text NULL,   -- the originating transaction's reference/id, for idempotency
    status      text NOT NULL DEFAULT 'POSTED' CHECK (status IN ('POSTED','REVERSED')),
    reverses    uuid NULL REFERENCES finance.gl_journal(id),
    posted_by   uuid NULL,
    posted_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_gl_jrn_memo CHECK (btrim(memo) <> '')
);
-- a given source transaction is posted at most once
CREATE UNIQUE INDEX uq_gl_journal_source ON finance.gl_journal(source_type, source_ref)
    WHERE source_type IS NOT NULL AND source_ref IS NOT NULL;
CREATE INDEX ix_gl_journal_date ON finance.gl_journal(entry_date);

-- ── the postings (the debit/credit lines) ──────────────────────────────────
CREATE TABLE finance.gl_posting (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_id uuid NOT NULL REFERENCES finance.gl_journal(id) ON DELETE CASCADE,
    line       int  NOT NULL,
    account    text NOT NULL REFERENCES finance.gl_account(code),
    debit      numeric(16,2) NOT NULL DEFAULT 0,
    credit     numeric(16,2) NOT NULL DEFAULT 0,
    narration  text NULL,
    session    text NULL,
    fund       text NULL,
    -- a line is a debit or a credit, never both, never neither, never negative
    CONSTRAINT ck_gl_post_amt CHECK (debit >= 0 AND credit >= 0 AND (debit = 0) <> (credit = 0))
);
CREATE INDEX ix_gl_posting_journal ON finance.gl_posting(journal_id);
CREATE INDEX ix_gl_posting_account ON finance.gl_posting(account);

-- ── every journal balances (debits = credits), enforced at commit ──────────
CREATE OR REPLACE FUNCTION finance.gl_balance_check() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_j uuid; v_d numeric; v_c numeric;
BEGIN
    v_j := coalesce(NEW.journal_id, OLD.journal_id);
    -- the journal may have been deleted (cascade); nothing to check then
    IF NOT EXISTS (SELECT 1 FROM finance.gl_journal WHERE id = v_j) THEN RETURN NULL; END IF;
    SELECT coalesce(sum(debit),0), coalesce(sum(credit),0) INTO v_d, v_c
      FROM finance.gl_posting WHERE journal_id = v_j;
    IF v_d = 0 AND v_c = 0 THEN
        RAISE EXCEPTION 'Journal % has no postings', v_j;
    END IF;
    IF v_d <> v_c THEN
        RAISE EXCEPTION 'Journal % is out of balance: debits % <> credits %', v_j, v_d, v_c;
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER gl_balance
    AFTER INSERT OR UPDATE OR DELETE ON finance.gl_posting
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION finance.gl_balance_check();

-- ═══ the posting engine ════════════════════════════════════════════════════

-- Post one balanced journal from a JSON array of lines
-- [{"account":"1010","debit":1000,"narration":"...","session":"2025/2026"}, {"account":"4010","credit":1000}]
CREATE OR REPLACE FUNCTION finance.gl_post(
    p_date date, p_memo text, p_source text, p_source_type text, p_source_ref text, p_lines jsonb
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_line jsonb; i int := 0;
BEGIN
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) < 2 THEN
        RAISE EXCEPTION 'A journal needs at least two lines';
    END IF;
    INSERT INTO finance.gl_journal (entry_date, memo, source, source_type, source_ref, posted_by)
    VALUES (coalesce(p_date, current_date), p_memo, coalesce(p_source,'MANUAL'), p_source_type, p_source_ref,
            nullif(current_setting('moaum.actor_id', true), '')::uuid)
    RETURNING id INTO v_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        i := i + 1;
        INSERT INTO finance.gl_posting (journal_id, line, account, debit, credit, narration, session, fund)
        VALUES (v_id, i, btrim(v_line->>'account'),
                round(coalesce((v_line->>'debit')::numeric, 0), 2),
                round(coalesce((v_line->>'credit')::numeric, 0), 2),
                nullif(btrim(coalesce(v_line->>'narration','')), ''),
                nullif(btrim(coalesce(v_line->>'session','')), ''),
                nullif(btrim(coalesce(v_line->>'fund','')), ''));
    END LOOP;
    RETURN v_id;   -- the deferred trigger checks the balance at commit
END $$;

-- Reverse a posted journal by mirroring its lines into a new one
CREATE OR REPLACE FUNCTION finance.gl_reverse(p_journal uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_new uuid; v_lines jsonb; v_memo text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM finance.gl_journal WHERE id = p_journal AND status = 'POSTED') THEN
        RAISE EXCEPTION 'Journal not found or already reversed';
    END IF;
    SELECT 'Reversal of #' || journal_no || ' — ' || coalesce(p_reason, memo) INTO v_memo
      FROM finance.gl_journal WHERE id = p_journal;
    SELECT jsonb_agg(jsonb_build_object(
                'account', account,
                'debit',  credit,          -- swap: a debit becomes a credit
                'credit', debit,
                'narration', narration, 'session', session, 'fund', fund) ORDER BY line)
      INTO v_lines FROM finance.gl_posting WHERE journal_id = p_journal;

    v_new := finance.gl_post(current_date, v_memo, 'MANUAL', 'REVERSAL', p_journal::text, v_lines);
    UPDATE finance.gl_journal SET reverses = p_journal WHERE id = v_new;
    UPDATE finance.gl_journal SET status = 'REVERSED' WHERE id = p_journal;
    RETURN v_new;
END $$;

-- ═══ account mapping (which income/expense account a transaction hits) ═══════
CREATE OR REPLACE FUNCTION finance.gl_income_account(p_category text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_category
        WHEN 'School fees'          THEN '4010'
        WHEN 'Acceptance fee'       THEN '4020'
        WHEN 'Application fee'       THEN '4030'
        WHEN 'Hostel'               THEN '4040'
        WHEN 'Transcript'           THEN '4050'
        WHEN 'Portal and ICT charge' THEN '4060'
        WHEN 'Identity card'        THEN '4070'
        WHEN 'Transfer fee'         THEN '4080'
        ELSE '4090' END
$$;

CREATE OR REPLACE FUNCTION finance.gl_expense_account(p_kind text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_kind ILIKE '%salar%' OR p_kind ILIKE '%payroll%' OR p_kind ILIKE '%personnel%'
             OR p_kind ILIKE '%allowance%' OR p_kind ILIKE '%wage%'            THEN '5100'
        WHEN p_kind ILIKE '%capital%' OR p_kind ILIKE '%asset%' OR p_kind ILIKE '%equipment%'
             OR p_kind ILIKE '%vehicle%' OR p_kind ILIKE '%building%' OR p_kind ILIKE '%furniture%' THEN '5300'
        WHEN p_kind ILIKE '%maintenance%' OR p_kind ILIKE '%repair%'          THEN '5210'
        WHEN p_kind ILIKE '%utilit%' OR p_kind ILIKE '%electric%' OR p_kind ILIKE '%diesel%'
             OR p_kind ILIKE '%fuel%' OR p_kind ILIKE '%water%' OR p_kind ILIKE '%power%' THEN '5220'
        WHEN p_kind ILIKE '%travel%' OR p_kind ILIKE '%estacode%' OR p_kind ILIKE '%duty tour%'
             OR p_kind ILIKE '%transport%'                                    THEN '5230'
        WHEN p_kind ILIKE '%grant%' OR p_kind ILIKE '%research%' OR p_kind ILIKE '%bursary%'
             OR p_kind ILIKE '%scholarship%'                                  THEN '5240'
        ELSE '5900' END
$$;

-- ═══ auto-post: sweep unposted cash into the books (idempotent) ═════════════
CREATE OR REPLACE FUNCTION finance.gl_sync() RETURNS TABLE (payments int, refunds int, vouchers int)
LANGUAGE plpgsql AS $$
DECLARE r record; v_p int := 0; v_r int := 0; v_v int := 0;
BEGIN
    -- confirmed student payments → Dr Bank (Collections), Cr the income account
    FOR r IN
        SELECT pr.reference, pr.confirmed_at::date AS d, pr.amount, pr.session,
               finance.payment_category(pr.purpose) AS cat, pr.purpose
          FROM finance.payment_reference pr
         WHERE pr.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'PAYMENT' AND j.source_ref = pr.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Fee receipt ' || r.reference || ' — ' || r.cat, 'AUTO', 'PAYMENT', r.reference,
            jsonb_build_array(
                jsonb_build_object('account','1010','debit', r.amount, 'narration', r.purpose, 'session', r.session),
                jsonb_build_object('account', finance.gl_income_account(r.cat), 'credit', r.amount, 'narration', r.purpose, 'session', r.session)));
        v_p := v_p + 1;
    END LOOP;

    -- paid refunds → Dr Refunds of fees, Cr Bank (Disbursements)
    FOR r IN
        SELECT rf.reference, rf.paid_at::date AS d, rf.amount, rf.reason
          FROM finance.refund rf
         WHERE rf.state = 'PAID' AND rf.paid_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'REFUND' AND j.source_ref = rf.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Refund ' || r.reference || ' — ' || r.reason, 'AUTO', 'REFUND', r.reference,
            jsonb_build_array(
                jsonb_build_object('account','4990','debit', r.amount, 'narration', r.reason),
                jsonb_build_object('account','1020','credit', r.amount, 'narration', r.reason)));
        v_r := v_r + 1;
    END LOOP;

    -- paid vouchers → Dr the expense account, Cr Bank (Disbursements)
    FOR r IN
        SELECT v.reference, v.paid_at::date AS d, v.amount, v.title, v.kind, v.payee
          FROM expenditure.voucher v
         WHERE v.stage = 'PAID' AND v.paid_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.gl_journal j WHERE j.source_type = 'VOUCHER' AND j.source_ref = v.reference)
    LOOP
        PERFORM finance.gl_post(r.d, 'Voucher ' || r.reference || ' — ' || r.title || ' (' || r.payee || ')',
            'AUTO', 'VOUCHER', r.reference,
            jsonb_build_array(
                jsonb_build_object('account', finance.gl_expense_account(r.kind), 'debit', r.amount, 'narration', r.title),
                jsonb_build_object('account','1020','credit', r.amount, 'narration', r.payee)));
        v_v := v_v + 1;
    END LOOP;

    payments := v_p; refunds := v_r; vouchers := v_v; RETURN NEXT;
END $$;

-- ═══ reports ════════════════════════════════════════════════════════════════

-- Trial balance as at a date: every postable account with a movement, its debit
-- and credit put on the account's normal side.
CREATE OR REPLACE FUNCTION finance.trial_balance(p_as_of date)
RETURNS TABLE (code text, name text, type text, debit numeric, credit numeric)
LANGUAGE sql STABLE AS $$
    WITH bal AS (
        SELECT a.code, a.name, a.type, a.normal_side,
               coalesce(sum(p.debit),0) - coalesce(sum(p.credit),0) AS net
          FROM finance.gl_account a
          LEFT JOIN finance.gl_posting p ON p.account = a.code
          LEFT JOIN finance.gl_journal j ON j.id = p.journal_id AND j.entry_date <= p_as_of
         WHERE a.postable
         GROUP BY a.code, a.name, a.type, a.normal_side)
    SELECT code, name, type,
           CASE WHEN net > 0 THEN net ELSE 0 END AS debit,
           CASE WHEN net < 0 THEN -net ELSE 0 END AS credit
      FROM bal
     WHERE net <> 0
     ORDER BY code;
$$;

-- One account's ledger between two dates, with a running balance (on its normal side)
CREATE OR REPLACE FUNCTION finance.gl_ledger(p_account text, p_from date, p_to date)
RETURNS TABLE (entry_date date, journal_no bigint, memo text, narration text, debit numeric, credit numeric, balance numeric)
LANGUAGE sql STABLE AS $$
    WITH opening AS (
        SELECT coalesce(sum(p.debit - p.credit),0)
                 * CASE (SELECT normal_side FROM finance.gl_account WHERE code = p_account) WHEN 'C' THEN -1 ELSE 1 END AS bal
          FROM finance.gl_posting p JOIN finance.gl_journal j ON j.id = p.journal_id
         WHERE p.account = p_account AND j.entry_date < p_from),
    lines AS (
        SELECT j.entry_date, j.journal_no, j.memo, p.narration, p.debit, p.credit, p.id,
               (p.debit - p.credit) * CASE (SELECT normal_side FROM finance.gl_account WHERE code = p_account) WHEN 'C' THEN -1 ELSE 1 END AS delta
          FROM finance.gl_posting p JOIN finance.gl_journal j ON j.id = p.journal_id
         WHERE p.account = p_account AND j.entry_date BETWEEN p_from AND p_to)
    SELECT l.entry_date, l.journal_no, l.memo, l.narration, l.debit, l.credit,
           (SELECT bal FROM opening) + sum(l.delta) OVER (ORDER BY l.entry_date, l.journal_no, l.id) AS balance
      FROM lines l
     ORDER BY l.entry_date, l.journal_no, l.id;
$$;

-- Income & expenditure for a period, ending in the surplus or deficit
CREATE OR REPLACE FUNCTION finance.income_expenditure(p_from date, p_to date)
RETURNS TABLE (section text, code text, name text, amount numeric)
LANGUAGE sql STABLE AS $$
    WITH mv AS (
        SELECT a.code, a.name, a.type,
               CASE a.type WHEN 'INCOME'  THEN coalesce(sum(p.credit - p.debit),0)
                           WHEN 'EXPENSE' THEN coalesce(sum(p.debit - p.credit),0) END AS amount
          FROM finance.gl_account a
          LEFT JOIN finance.gl_posting p ON p.account = a.code
          LEFT JOIN finance.gl_journal j ON j.id = p.journal_id AND j.entry_date BETWEEN p_from AND p_to
         WHERE a.postable AND a.type IN ('INCOME','EXPENSE')
         GROUP BY a.code, a.name, a.type)
    SELECT type AS section, code, name, amount FROM mv WHERE amount <> 0
    UNION ALL
    SELECT 'INCOME_TOTAL', NULL, 'Total income',      coalesce(sum(amount),0) FROM mv WHERE type = 'INCOME'
    UNION ALL
    SELECT 'EXPENSE_TOTAL', NULL, 'Total expenditure', coalesce(sum(amount),0) FROM mv WHERE type = 'EXPENSE'
    UNION ALL
    SELECT 'SURPLUS', NULL, 'Surplus / (deficit) for the period',
           coalesce(sum(amount) FILTER (WHERE type='INCOME'),0) - coalesce(sum(amount) FILTER (WHERE type='EXPENSE'),0)
      FROM mv
    ORDER BY 1, 2;
$$;

-- Balance sheet as at a date. Cash basis: the accumulated surplus is income less
-- expenditure to date, carried into the fund.
CREATE OR REPLACE FUNCTION finance.balance_sheet(p_as_of date)
RETURNS TABLE (section text, code text, name text, amount numeric)
LANGUAGE sql STABLE AS $$
    WITH mv AS (
        SELECT a.code, a.name, a.type, a.normal_side,
               coalesce(sum(p.debit - p.credit),0) AS net
          FROM finance.gl_account a
          LEFT JOIN finance.gl_posting p ON p.account = a.code
          LEFT JOIN finance.gl_journal j ON j.id = p.journal_id AND j.entry_date <= p_as_of
         WHERE a.postable
         GROUP BY a.code, a.name, a.type, a.normal_side),
    surplus AS (
        SELECT coalesce(sum(CASE type WHEN 'INCOME' THEN -net WHEN 'EXPENSE' THEN -net END),0) AS amt FROM mv)
    SELECT 'ASSET' AS section, code, name, net FROM mv WHERE type='ASSET' AND net <> 0
    UNION ALL
    SELECT 'LIABILITY', code, name, -net FROM mv WHERE type='LIABILITY' AND net <> 0
    UNION ALL
    SELECT 'EQUITY', code, name, -net FROM mv WHERE type='EQUITY' AND net <> 0
    UNION ALL
    SELECT 'EQUITY', NULL, 'Accumulated surplus / (deficit)', (SELECT amt FROM surplus)
    UNION ALL
    SELECT 'ASSET_TOTAL', NULL, 'Total assets', coalesce(sum(net) FILTER (WHERE type='ASSET'),0) FROM mv
    UNION ALL
    SELECT 'FUNDS_TOTAL', NULL, 'Total liabilities and fund',
           coalesce(sum(-net) FILTER (WHERE type IN ('LIABILITY','EQUITY')),0) + (SELECT amt FROM surplus) FROM mv
    ORDER BY 1, 2;
$$;

-- ═══ seed the chart of accounts ════════════════════════════════════════════
INSERT INTO finance.gl_account (code, name, type, normal_side, parent_code, postable, ord) VALUES
    -- Assets
    ('1000','ASSETS','ASSET','D',NULL,false,10),
    ('1010','Bank — Fees collection','ASSET','D','1000',true,11),
    ('1020','Bank — Disbursements','ASSET','D','1000',true,12),
    ('1050','Cash on hand','ASSET','D','1000',true,13),
    ('1200','Student fees receivable','ASSET','D','1000',true,14),   -- accrual-ready, unused cash-basis
    -- Liabilities
    ('2000','LIABILITIES','LIABILITY','C',NULL,false,20),
    ('2100','Student deposits & wallet','LIABILITY','C','2000',true,21),
    ('2200','Accounts payable','LIABILITY','C','2000',true,22),      -- accrual-ready
    ('2300','Funds held for third parties','LIABILITY','C','2000',true,23),
    -- Fund / equity
    ('3000','FUND','EQUITY','C',NULL,false,30),
    ('3100','Accumulated fund','EQUITY','C','3000',true,31),
    ('3900','Opening balance / suspense','EQUITY','C','3000',true,39),
    -- Income
    ('4000','INCOME','INCOME','C',NULL,false,40),
    ('4010','School fees','INCOME','C','4000',true,41),
    ('4020','Acceptance fees','INCOME','C','4000',true,42),
    ('4030','Application & Post-UTME fees','INCOME','C','4000',true,43),
    ('4040','Hostel & accommodation','INCOME','C','4000',true,44),
    ('4050','Transcript fees','INCOME','C','4000',true,45),
    ('4060','Portal & ICT charges','INCOME','C','4000',true,46),
    ('4070','Identity card fees','INCOME','C','4000',true,47),
    ('4080','Transfer fees','INCOME','C','4000',true,48),
    ('4090','Other income','INCOME','C','4000',true,49),
    ('4990','Refunds of fees','INCOME','D','4000',true,50),          -- contra-income (normal side D)
    -- Expenditure
    ('5000','EXPENDITURE','EXPENSE','D',NULL,false,60),
    ('5100','Personnel costs','EXPENSE','D','5000',true,61),
    ('5200','Overheads','EXPENSE','D','5000',false,62),
    ('5210','Maintenance & repairs','EXPENSE','D','5200',true,63),
    ('5220','Utilities & energy','EXPENSE','D','5200',true,64),
    ('5230','Travel & transport','EXPENSE','D','5200',true,65),
    ('5240','Grants, research & scholarships','EXPENSE','D','5000',true,66),
    ('5300','Capital expenditure','EXPENSE','D','5000',true,67),
    ('5900','Other overheads','EXPENSE','D','5000',true,69);

-- attach the audit spine (after the seed, so seeding needs no actor context)
SELECT audit.attach('finance.gl_account');
SELECT audit.attach('finance.gl_journal');

COMMIT;
