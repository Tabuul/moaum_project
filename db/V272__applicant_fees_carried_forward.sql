-- ═══════════════════════════════════════════════════════════════════════════
-- V272 — the applicant fees of a session not yet stated are the last stated
--
--   V148's rule fell back to built-in figures — and a checking fee of nought —
--   for a session the Bursary had not yet stated. So 2026/2027, with the fees
--   stated for 2025/2026 and none of its own, charged no admission checking
--   fee and opened the released decision for nothing. A session not yet
--   stated now carries the most recently stated session's fees forward, and
--   says so; only where nothing was ever stated do the built-in figures apply,
--   with the checking fee at ₦3,000 as the Registry charges it.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V272: applicant fees carried forward', true);

DROP FUNCTION IF EXISTS admissions.applicant_fee_rule(text);
CREATE FUNCTION admissions.applicant_fee_rule(p_session text)
RETURNS TABLE (stated boolean, application_fee numeric, portal_charge numeric, acceptance_fee numeric, checking_fee numeric, carried_from text)
LANGUAGE sql STABLE AS $$
    WITH own AS (
        SELECT true AS stated, f.application_fee, f.portal_charge, f.acceptance_fee, f.checking_fee, NULL::text AS carried_from
          FROM admissions.applicant_fee f WHERE f.session = p_session
    ), carried AS (
        SELECT false, f.application_fee, f.portal_charge, f.acceptance_fee, f.checking_fee, f.session
          FROM admissions.applicant_fee f
         WHERE NOT EXISTS (SELECT 1 FROM own)
         ORDER BY f.stated_at DESC, f.session DESC LIMIT 1
    )
    SELECT * FROM own
    UNION ALL
    SELECT * FROM carried
    UNION ALL
    -- the built-in figures, only where nothing was ever stated
    SELECT false, 2000, 300, 25000, 3000, NULL WHERE NOT EXISTS (SELECT 1 FROM own) AND NOT EXISTS (SELECT 1 FROM carried);
$$;
COMMENT ON FUNCTION admissions.applicant_fee_rule(text) IS
    'The applicant fees of a session (V021, V148, V272), always one row: the session''s own where stated; else the most recently stated session''s, carried forward and named in carried_from; else the built-in figures, with the checking fee at 3,000.';

COMMIT;
