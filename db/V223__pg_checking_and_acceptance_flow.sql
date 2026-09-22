-- ═══════════════════════════════════════════════════════════════════════════
-- V223 — the postgraduate checking-fee gate and acceptance flow
--
--   After the School decides, the applicant pays a checking fee (₦3,000) to see
--   their admission status. If admitted (offered), they pay the acceptance fee,
--   which accepts the offer, and can then print the offer of admission. This adds
--   a CHECKING fee reference, records when the checking and acceptance fees are
--   confirmed, and makes paying the acceptance fee accept the offer.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.pg_application ADD COLUMN IF NOT EXISTS checking_confirmed_at   timestamptz NULL;
ALTER TABLE admissions.pg_application ADD COLUMN IF NOT EXISTS acceptance_confirmed_at timestamptz NULL;

ALTER TABLE admissions.pg_fee_reference DROP CONSTRAINT IF EXISTS ck_pg_feeref_kind;
ALTER TABLE admissions.pg_fee_reference ADD  CONSTRAINT ck_pg_feeref_kind
    CHECK (kind IN ('APPLICATION', 'CHECKING', 'ACCEPTANCE'));

-- the fee reference of a kind, at the session's rate (application / checking / acceptance)
CREATE OR REPLACE FUNCTION admissions.pg_new_fee_reference(p_application uuid, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_session text; v_amt numeric; v_ref text; v_rule record;
BEGIN
    SELECT session INTO v_session FROM admissions.pg_application WHERE id = p_application;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'no such postgraduate application';
    END IF;
    SELECT * INTO v_rule FROM admissions.pg_fee_rule(v_session);
    v_amt := CASE p_kind WHEN 'ACCEPTANCE' THEN v_rule.acceptance_fee
                         WHEN 'CHECKING'   THEN v_rule.checking_fee
                         ELSE v_rule.application_fee END;
    v_ref := 'MOAUM-PG' || CASE p_kind WHEN 'ACCEPTANCE' THEN 'ACC' WHEN 'CHECKING' THEN 'CHK' ELSE 'APP' END || '-'
             || lpad(platform.next_number('PG_FEEREF', 'UNIVERSITY', v_session)::text, 6, '0');
    INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, expires_at)
    VALUES (p_application, p_kind, v_ref, v_amt, now() + interval '24 hours');
    RETURN v_ref;
END;
$$;

-- confirming a reference: the application fee opens screening; the checking fee releases the status;
-- the acceptance fee accepts the offer (moving an OFFERED application to ACCEPTED)
CREATE OR REPLACE FUNCTION admissions.pg_confirm_fee(p_reference text, p_channel text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_app uuid; v_kind text;
BEGIN
    UPDATE admissions.pg_fee_reference
       SET confirmed_at = now(), channel = p_channel
     WHERE reference = p_reference AND confirmed_at IS NULL
     RETURNING application_id, kind INTO v_app, v_kind;
    IF v_app IS NULL THEN
        RETURN;                                   -- unknown or already confirmed: nothing to do
    END IF;
    IF v_kind = 'APPLICATION' THEN
        UPDATE admissions.pg_application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = v_app;
    ELSIF v_kind = 'CHECKING' THEN
        UPDATE admissions.pg_application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()) WHERE id = v_app;
    ELSIF v_kind = 'ACCEPTANCE' THEN
        UPDATE admissions.pg_application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = v_app;
        -- paying the acceptance fee accepts the offer
        UPDATE admissions.pg_application SET state = 'ACCEPTED', accepted_at = coalesce(accepted_at, now())
         WHERE id = v_app AND state = 'OFFERED';
    END IF;
END;
$$;

COMMIT;
