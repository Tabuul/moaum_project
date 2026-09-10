-- ═══════════════════════════════════════════════════════════════════════════
-- V069 — the payroll: the establishment, the salary structure, monthly runs
--
--   A member of staff (iam.person, with a staff number) holds one employment on
--   a grade and step; the grade carries the monthly salary components. A pay run
--   is built once a month over the active establishment: each staff's payslip is
--   a snapshot — the components as they stood, the statutory deductions computed
--   from them, and the net. Pension is the employee's 8% (Pension Reform Act);
--   PAYE follows the Personal Income Tax bands after the consolidated relief and
--   the pension relief. A run is built by one officer and approved by another —
--   the database refuses the second click by the same person, as every money act
--   on this portal does — and only an approved run is marked paid. Nothing is
--   deleted; a run wrongly built is cancelled, a staff member ended, not removed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SCHEMA IF NOT EXISTS hrm;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'V069: payroll schema and salary structure', true);
END $seed$;

-- ── the salary structure: grade + step → monthly components (reference data) ──
CREATE TABLE hrm.grade (
    grade            text NOT NULL,
    step             int  NOT NULL,
    category         text NOT NULL,
    basic            numeric(12,2) NOT NULL,
    housing          numeric(12,2) NOT NULL DEFAULT 0,
    transport        numeric(12,2) NOT NULL DEFAULT 0,
    other_allowances numeric(12,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (grade, step),
    CONSTRAINT ck_grade_category CHECK (category IN ('ACADEMIC','NON_ACADEMIC')),
    CONSTRAINT ck_grade_amounts CHECK (basic >= 0 AND housing >= 0 AND transport >= 0 AND other_allowances >= 0),
    CONSTRAINT ck_grade_step CHECK (step >= 1)
);
SELECT audit.attach('hrm.grade');

-- ── the establishment: one person's employment ──
CREATE TABLE hrm.employment (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id        uuid NOT NULL REFERENCES iam.person(id),
    staff_no         text NOT NULL UNIQUE,
    grade            text NOT NULL,
    step             int  NOT NULL,
    category         text NOT NULL,
    appointment_date date NOT NULL,
    status           text NOT NULL DEFAULT 'ACTIVE',
    bank_name        text NULL,
    account_name     text NULL,
    account_last4    text NULL,
    pension_pin      text NULL,
    ended_on         date NULL,
    ended_reason     text NULL,
    FOREIGN KEY (grade, step) REFERENCES hrm.grade(grade, step),
    CONSTRAINT ck_emp_status CHECK (status IN ('ACTIVE','SUSPENDED','ENDED')),
    CONSTRAINT ck_emp_category CHECK (category IN ('ACADEMIC','NON_ACADEMIC')),
    CONSTRAINT ck_emp_ended CHECK (status <> 'ENDED' OR ended_on IS NOT NULL)
);
CREATE UNIQUE INDEX uq_emp_person_live ON hrm.employment (person_id) WHERE status <> 'ENDED';
CREATE INDEX ix_emp_status ON hrm.employment (status);
SELECT audit.attach('hrm.employment');

-- ── a monthly pay run, maker–checker controlled ──
CREATE TABLE hrm.pay_run (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    period          date NOT NULL UNIQUE,
    state           text NOT NULL DEFAULT 'DRAFT',
    staff_count     int NOT NULL DEFAULT 0,
    gross_total     numeric(16,2) NOT NULL DEFAULT 0,
    deduction_total numeric(16,2) NOT NULL DEFAULT 0,
    net_total       numeric(16,2) NOT NULL DEFAULT 0,
    note            text NULL,
    built_by        uuid NOT NULL,
    built_at        timestamptz NOT NULL DEFAULT now(),
    approved_by     uuid NULL,
    approved_at     timestamptz NULL,
    cancelled_why   text NULL,
    paid_by         uuid NULL,
    paid_at         timestamptz NULL,
    CONSTRAINT ck_run_state CHECK (state IN ('DRAFT','APPROVED','PAID','CANCELLED')),
    CONSTRAINT ck_run_two_people CHECK (approved_by IS NULL OR approved_by <> built_by),
    CONSTRAINT ck_run_first_of_month CHECK (extract(day FROM period) = 1)
);
SELECT audit.attach('hrm.pay_run');

-- ── one payslip per staff per run: a snapshot of the components and deductions ──
CREATE TABLE hrm.payslip (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id           uuid NOT NULL REFERENCES hrm.pay_run(id),
    employment_id    uuid NOT NULL REFERENCES hrm.employment(id),
    person_id        uuid NOT NULL REFERENCES iam.person(id),
    staff_no         text NOT NULL,
    name             text NOT NULL,
    grade            text NOT NULL,
    step             int NOT NULL,
    category         text NOT NULL,
    basic            numeric(12,2) NOT NULL,
    allowances       numeric(12,2) NOT NULL,
    gross            numeric(12,2) NOT NULL,
    pension          numeric(12,2) NOT NULL,
    paye             numeric(12,2) NOT NULL,
    other_deductions numeric(12,2) NOT NULL DEFAULT 0,
    net              numeric(12,2) NOT NULL,
    bank_name        text NULL,
    account_last4    text NULL,
    CONSTRAINT uq_payslip UNIQUE (run_id, employment_id)
);
CREATE INDEX ix_payslip_person ON hrm.payslip (person_id, run_id);
CREATE INDEX ix_payslip_run ON hrm.payslip (run_id);
SELECT audit.attach('hrm.payslip');

-- ── the statutory computations ──

-- the employee's pension: 8% of (basic + housing + transport), per the PRA
CREATE OR REPLACE FUNCTION hrm.pension_monthly(p_basic numeric, p_housing numeric, p_transport numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT round(0.08 * (coalesce(p_basic, 0) + coalesce(p_housing, 0) + coalesce(p_transport, 0)), 2)
$$;

-- PAYE for a month, from the annual gross and the annual pension: the
-- consolidated relief (the greater of 200,000 or 1% of gross, plus 20% of
-- gross) and the pension are removed, then the progressive bands are applied.
CREATE OR REPLACE FUNCTION hrm.paye_monthly(p_annual_gross numeric, p_annual_pension numeric)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE cra numeric; taxable numeric; t numeric := 0; rem numeric;
        bands numeric[] := ARRAY[300000, 300000, 500000, 500000, 1600000];
        rates numeric[] := ARRAY[0.07, 0.11, 0.15, 0.19, 0.21];
        i int;
BEGIN
    IF p_annual_gross IS NULL OR p_annual_gross <= 0 THEN RETURN 0; END IF;
    cra := greatest(200000, 0.01 * p_annual_gross) + 0.20 * p_annual_gross;
    taxable := greatest(p_annual_gross - coalesce(p_annual_pension, 0) - cra, 0);
    rem := taxable;
    FOR i IN 1 .. array_length(bands, 1) LOOP
        EXIT WHEN rem <= 0;
        t := t + least(rem, bands[i]) * rates[i];
        rem := rem - bands[i];
    END LOOP;
    IF rem > 0 THEN t := t + rem * 0.24; END IF;
    RETURN round(t / 12, 2);
END $$;

-- ── building, approving and paying a run ──

-- build the run for a month over the active establishment; each payslip a snapshot
CREATE OR REPLACE FUNCTION hrm.build_pay_run(p_period date, p_note text)
RETURNS TABLE (run_id uuid, staff_count int, gross_total numeric, net_total numeric)
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_period date := date_trunc('month', p_period)::date; v_run uuid; e record;
        v_gross numeric; v_pension numeric; v_paye numeric; v_net numeric;
        n int := 0; g numeric := 0; d numeric := 0; nt numeric := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a pay run is built by a person' USING ERRCODE = '23514'; END IF;
    IF p_period IS NULL THEN RAISE EXCEPTION 'a pay run is for a month' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hrm.pay_run WHERE period = v_period AND state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'a pay run for % already exists', to_char(v_period, 'FMMonth YYYY') USING ERRCODE = '23505',
            HINT = 'Open the existing run; a month is run once.';
    END IF;
    INSERT INTO hrm.pay_run (period, note, built_by) VALUES (v_period, nullif(btrim(coalesce(p_note, '')), ''), who) RETURNING id INTO v_run;
    FOR e IN
        SELECT em.id AS emp_id, em.person_id, em.staff_no, em.grade, em.step, em.category,
               em.bank_name, em.account_last4, gr.basic, gr.housing, gr.transport, gr.other_allowances,
               p.surname || ', ' || p.given_names AS name
          FROM hrm.employment em
          JOIN hrm.grade gr ON gr.grade = em.grade AND gr.step = em.step
          JOIN iam.person p ON p.id = em.person_id
         WHERE em.status = 'ACTIVE'
         ORDER BY em.staff_no
    LOOP
        v_gross := e.basic + e.housing + e.transport + e.other_allowances;
        v_pension := hrm.pension_monthly(e.basic, e.housing, e.transport);
        v_paye := hrm.paye_monthly(v_gross * 12, v_pension * 12);
        v_net := v_gross - v_pension - v_paye;
        INSERT INTO hrm.payslip (run_id, employment_id, person_id, staff_no, name, grade, step, category,
                                 basic, allowances, gross, pension, paye, other_deductions, net, bank_name, account_last4)
        VALUES (v_run, e.emp_id, e.person_id, e.staff_no, e.name, e.grade, e.step, e.category,
                e.basic, e.housing + e.transport + e.other_allowances, v_gross, v_pension, v_paye, 0, v_net, e.bank_name, e.account_last4);
        n := n + 1; g := g + v_gross; d := d + v_pension + v_paye; nt := nt + v_net;
    END LOOP;
    UPDATE hrm.pay_run SET staff_count = n, gross_total = g, deduction_total = d, net_total = nt WHERE id = v_run;
    RETURN QUERY SELECT v_run, n, g, nt;
END $$;

CREATE OR REPLACE FUNCTION hrm.approve_pay_run(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r hrm.pay_run; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO r FROM hrm.pay_run WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'DRAFT' THEN RAISE EXCEPTION 'pay run % has no draft to approve', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL OR who = r.built_by THEN
        RAISE EXCEPTION 'the officer who built a pay run does not approve it' USING ERRCODE = '23514',
            HINT = 'A payroll is released only when a second officer has agreed it.';
    END IF;
    UPDATE hrm.pay_run SET state = 'APPROVED', approved_by = who, approved_at = now() WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.pay_pay_run(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r hrm.pay_run; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO r FROM hrm.pay_run WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'APPROVED' THEN RAISE EXCEPTION 'pay run % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'a payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    UPDATE hrm.pay_run SET state = 'PAID', paid_by = who, paid_at = now() WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.cancel_pay_run(p_id uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r hrm.pay_run; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO r FROM hrm.pay_run WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state = 'PAID' THEN RAISE EXCEPTION 'pay run % cannot be cancelled', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL THEN RAISE EXCEPTION 'a cancellation is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a cancellation says why' USING ERRCODE = '23514'; END IF;
    UPDATE hrm.pay_run SET state = 'CANCELLED', cancelled_why = btrim(p_why) WHERE id = p_id;
END $$;

-- ── the variance: a run against the one before it, for the audit directorate ──
CREATE OR REPLACE FUNCTION hrm.pay_run_variance(p_period date)
RETURNS TABLE (kind text, staff_no text, name text, grade text, this_net numeric, prev_net numeric, delta numeric)
LANGUAGE plpgsql AS $$
DECLARE v_period date := date_trunc('month', p_period)::date; v_this uuid; v_prev uuid;
BEGIN
    SELECT id INTO v_this FROM hrm.pay_run WHERE period = v_period AND state <> 'CANCELLED';
    SELECT id INTO v_prev FROM hrm.pay_run WHERE period < v_period AND state <> 'CANCELLED' ORDER BY period DESC LIMIT 1;
    RETURN QUERY
    WITH t AS (SELECT * FROM hrm.payslip WHERE v_this IS NOT NULL AND run_id = v_this),
         p AS (SELECT * FROM hrm.payslip WHERE v_prev IS NOT NULL AND run_id = v_prev)
    SELECT CASE WHEN p.employment_id IS NULL THEN 'JOINED'
                WHEN t.employment_id IS NULL THEN 'LEFT'
                WHEN t.net <> p.net THEN 'CHANGED' ELSE 'SAME' END,
           coalesce(t.staff_no, p.staff_no), coalesce(t.name, p.name), coalesce(t.grade, p.grade),
           t.net, p.net, coalesce(t.net, 0) - coalesce(p.net, 0)
      FROM t FULL OUTER JOIN p ON p.employment_id = t.employment_id
     ORDER BY 1, 2;
END $$;

-- ── the salary structure (reference data) ──
INSERT INTO hrm.grade (grade, step, category, basic, housing, transport, other_allowances) VALUES
 ('CONTISS 6',  1, 'NON_ACADEMIC',  90000, 30000, 15000, 10000),
 ('CONTISS 6',  2, 'NON_ACADEMIC',  95000, 31000, 15500, 10000),
 ('CONTISS 7',  1, 'NON_ACADEMIC', 110000, 35000, 18000, 12000),
 ('CONTISS 7',  2, 'NON_ACADEMIC', 116000, 36000, 18500, 12000),
 ('CONTISS 9',  1, 'NON_ACADEMIC', 150000, 45000, 22000, 15000),
 ('CONTISS 9',  2, 'NON_ACADEMIC', 158000, 46500, 22500, 15000),
 ('CONTISS 13', 1, 'NON_ACADEMIC', 240000, 70000, 30000, 25000),
 ('CONTISS 13', 2, 'NON_ACADEMIC', 252000, 72000, 31000, 25000),
 ('CONTISS 15', 1, 'NON_ACADEMIC', 340000, 95000, 40000, 35000),
 ('CONTISS 15', 2, 'NON_ACADEMIC', 356000, 98000, 41000, 35000),
 ('CONUASS 1',  1, 'ACADEMIC',     130000, 40000, 20000, 15000),
 ('CONUASS 1',  2, 'ACADEMIC',     137000, 41000, 20500, 15000),
 ('CONUASS 3',  1, 'ACADEMIC',     190000, 55000, 26000, 20000),
 ('CONUASS 3',  2, 'ACADEMIC',     200000, 57000, 27000, 20000),
 ('CONUASS 5',  1, 'ACADEMIC',     300000, 85000, 38000, 30000),
 ('CONUASS 5',  2, 'ACADEMIC',     315000, 88000, 39000, 30000),
 ('CONUASS 7',  1, 'ACADEMIC',     480000,130000, 55000, 50000),
 ('CONUASS 7',  2, 'ACADEMIC',     504000,134000, 56500, 50000);

COMMIT;
