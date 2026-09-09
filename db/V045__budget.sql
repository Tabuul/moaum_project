-- ═══════════════════════════════════════════════════════════════════════════
-- V045 — the budget, and commitment accounting
--
--   A budget is set per cost centre for a financial year. It is consumed at
--   approval, not at payment: an approved voucher commits its amount against the
--   cost centre immediately, which is what stops a cost centre committing money
--   it has already promised elsewhere. Available = budget − committed − spent,
--   where committed is the cleared-but-unpaid vouchers and spent is the paid.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE expenditure.budget (
    cost_centre    text NOT NULL,
    financial_year int  NOT NULL,
    amount         numeric(16,2) NOT NULL,
    set_by         uuid NOT NULL,
    set_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (cost_centre, financial_year),
    CONSTRAINT ck_budget_amount CHECK (amount >= 0)
);
SELECT audit.attach('expenditure.budget');

CREATE OR REPLACE FUNCTION expenditure.set_budget(p_cost_centre text, p_year int, p_amount numeric)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_cc text := btrim(coalesce(p_cost_centre, ''));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a budget is set by a person' USING ERRCODE = '23514'; END IF;
    IF v_cc = '' THEN RAISE EXCEPTION 'a budget names its cost centre' USING ERRCODE = '23514'; END IF;
    IF p_amount IS NULL OR p_amount < 0 THEN RAISE EXCEPTION 'a budget is an amount, not less than zero' USING ERRCODE = '23514'; END IF;
    INSERT INTO expenditure.budget (cost_centre, financial_year, amount, set_by)
    VALUES (v_cc, p_year, p_amount, who)
    ON CONFLICT (cost_centre, financial_year) DO UPDATE SET amount = EXCLUDED.amount, set_by = EXCLUDED.set_by, set_at = now();
END $$;

-- budget performance: each cost centre's allocation against what vouchers have committed and spent
CREATE OR REPLACE FUNCTION expenditure.budget_performance(p_year int)
RETURNS TABLE (cost_centre text, budget numeric, committed numeric, spent numeric, available numeric)
LANGUAGE sql STABLE AS $$
    WITH v AS (
        SELECT cost_centre,
               coalesce(sum(amount) FILTER (WHERE stage = 'CLEARED'), 0) AS committed,
               coalesce(sum(amount) FILTER (WHERE stage = 'PAID'), 0) AS spent
          FROM expenditure.voucher
         WHERE cost_centre IS NOT NULL AND extract(year FROM raised_at) = p_year
         GROUP BY cost_centre
    )
    SELECT cc.cost_centre,
           coalesce(b.amount, 0) AS budget,
           coalesce(v.committed, 0) AS committed,
           coalesce(v.spent, 0) AS spent,
           coalesce(b.amount, 0) - coalesce(v.committed, 0) - coalesce(v.spent, 0) AS available
      FROM (SELECT cost_centre FROM expenditure.budget WHERE financial_year = p_year
             UNION SELECT cost_centre FROM v) cc
      LEFT JOIN expenditure.budget b ON b.cost_centre = cc.cost_centre AND b.financial_year = p_year
      LEFT JOIN v ON v.cost_centre = cc.cost_centre
     ORDER BY cc.cost_centre;
$$;
