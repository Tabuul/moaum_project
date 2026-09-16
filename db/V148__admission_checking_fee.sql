-- ═══════════════════════════════════════════════════════════════════════════
-- V148 — the admission checking fee, charged at acceptance
--
--   The applicant fee setup (V021) stated three amounts: the application fee,
--   the portal charge and the acceptance fee. The Office asked for a fourth —
--   an admission checking fee, paid by admitted candidates at the acceptance
--   stage. It is a stated amount of its own, added to what the candidate pays
--   to accept the offer (acceptance fee + checking fee, on the one reference).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.applicant_fee ADD COLUMN IF NOT EXISTS checking_fee numeric(12,2) NOT NULL DEFAULT 0;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_afee_checking') THEN
        ALTER TABLE admissions.applicant_fee ADD CONSTRAINT ck_afee_checking CHECK (checking_fee >= 0);
    END IF;
END $$;

-- the rule now carries the checking fee (RETURNS TABLE changes → drop then create)
DROP FUNCTION IF EXISTS admissions.applicant_fee_rule(text);
CREATE FUNCTION admissions.applicant_fee_rule(p_session text)
RETURNS TABLE (stated boolean, application_fee numeric, portal_charge numeric, acceptance_fee numeric, checking_fee numeric)
LANGUAGE sql STABLE AS $$
    SELECT true, f.application_fee, f.portal_charge, f.acceptance_fee, f.checking_fee
      FROM admissions.applicant_fee f WHERE f.session = p_session
    UNION ALL
    SELECT false, 2000, 300, 25000, 0
     WHERE NOT EXISTS (SELECT 1 FROM admissions.applicant_fee f WHERE f.session = p_session);
$$;

-- acceptance now charges the acceptance fee plus the checking fee, on one reference
CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    ELSE fee.acceptance_fee + coalesce(fee.checking_fee, 0) END;
    v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
             || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
    VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours');
    RETURN v_ref;
END $$;

COMMIT;
