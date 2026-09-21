-- ═══════════════════════════════════════════════════════════════════════════
-- V208 — the postgraduate checking fee
--
--   Alongside the application fee (to apply) and the acceptance fee (an offer
--   carries), the School charges a checking fee — paid on acceptance, as the
--   undergraduate side does. It joins admissions.pg_fee so the Bursary states it
--   per session, and pg_fee_rule returns it beside the others (a sensible ₦3,000
--   default until a session's fees are stated). pg_fee is a plain table (not on
--   the audit spine), so this is ordinary DDL.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.pg_fee ADD COLUMN IF NOT EXISTS checking_fee numeric(12,2) NOT NULL DEFAULT 3000;

-- the return shape widens by one column, so the function is dropped and recreated
DROP FUNCTION IF EXISTS admissions.pg_fee_rule(text);
CREATE FUNCTION admissions.pg_fee_rule(p_session text)
RETURNS TABLE (application_fee numeric, acceptance_fee numeric, checking_fee numeric)
LANGUAGE sql STABLE AS $$
    SELECT f.application_fee, f.acceptance_fee, f.checking_fee
      FROM admissions.pg_fee f WHERE f.session = p_session
    UNION ALL
    SELECT 20000, 50000, 3000
     WHERE NOT EXISTS (SELECT 1 FROM admissions.pg_fee f WHERE f.session = p_session)
$$;

COMMIT;
