-- ═══════════════════════════════════════════════════════════════════════════
-- V193 — the inter-departmental transfer fee is the Bursary's number, no default
--
--   V185 gave people.transfer_fee() a static ₦10,000 fallback for when the
--   Bursary had not set a value. The fee should be the Bursary's alone, so the
--   fallback is removed: transfer_fee() returns the set value or NULL, and the
--   payment reference cannot be generated until the Bursary has set the fee on
--   Finance → Fees. A student can still apply; they simply cannot pay (and so the
--   approvals cannot start) until the fee is stated — with a clear message, not a
--   crash.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V193: transfer fee is Bursary-set only', true);
END $seed$;

-- no static fallback: whatever the Bursary has set, or NULL when they have not set one yet
CREATE OR REPLACE FUNCTION people.transfer_fee()
RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT transfer_fee FROM finance.fee_setting WHERE id = 1
$$;

COMMENT ON FUNCTION people.transfer_fee() IS
  'The inter-departmental transfer processing fee the Bursary has set (finance.fee_setting.transfer_fee), '
  'or NULL when it has not been set. There is no default — a transfer cannot be paid until the Bursary sets it.';

-- generating the payment reference now requires the Bursary to have set the fee
CREATE OR REPLACE FUNCTION people.transfer_fee_reference(p_id uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE t people.transfer_application; v_name text; v_ref text; v_fee numeric;
BEGIN
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state NOT IN ('APPLIED','FROM_OK','TO_OK','REG_OK','RECOMMENDED','APPROVED') THEN
        RAISE EXCEPTION 'application % is not open for payment', p_id USING ERRCODE = '23514';
    END IF;
    IF t.fee_reference IS NOT NULL THEN RETURN t.fee_reference; END IF;
    v_fee := people.transfer_fee();
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'the inter-departmental transfer fee has not been set by the Bursary'
            USING ERRCODE = '23514',
                  HINT = 'The Bursary sets it on Finance → Fees before a transfer can be paid.';
    END IF;
    SELECT name INTO v_name FROM ref.programme WHERE code = t.to_programme_code;
    v_ref := finance.new_purpose_reference(t.student_id, t.session, v_fee,
                'Inter-departmental transfer to ' || coalesce(v_name, t.to_programme_code));
    UPDATE people.transfer_application SET fee_reference = v_ref WHERE id = p_id;
    RETURN v_ref;
END $$;

COMMIT;
