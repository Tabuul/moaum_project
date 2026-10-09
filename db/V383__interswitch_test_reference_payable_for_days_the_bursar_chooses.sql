-- V383: an Interswitch test reference — a small reference the Bursary issues against a named student for Interswitch's testers,
--       payable for the days the Bursar chooses (1 to 14, 7 unless said), so a certification test that runs over several days
--       does not fail on expiry.
--
-- Interswitch is certifying Pay on Quickteller (PayDirect, V299). Its testers check the same reference over several days, and a
-- school-fee reference expires 24 hours after it is generated (V288): by the second day the portal rightly answers Status 1, and
-- the test fails. The Bursary now issues a reference for the test itself:
--
-- 1  finance.new_gateway_test_reference(student, session, amount, days): a payment reference with the purpose of the existing test
--    checkout, 'Gateway test by the Bursary' — category GATEWAY_TEST (V279), which counts for nothing against the student's fees —
--    for an amount of at most NGN 10,000, payable for 1 to 14 days. Who issued it, from which office and for how many days is kept
--    in finance.gateway_test_reference. Only the Bursary's desk issues one (the Bursar, the Directorate of ICT, the administrators).
-- 2  finance.withdraw_gateway_test_reference(reference): an open test reference closed before its time — it expires now, so
--    Quickteller is answered Status 1 for it from then on; one already paid is not withdrawn.
-- 3  Nothing else changes. Quickteller's question about a reference (finance.paydirect_customer, V299) is answered as before, from
--    the reference: Status 0 with the payer's name and the amount while it is unpaid and unexpired, Status 1 once it is paid or
--    expired. Every other reference keeps its own expiry — a school-fee reference still 24 hours.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V383: an Interswitch test reference payable for the days the Bursar chooses', true);

-- ── 1 · the test references and who issued them ───────────────────────────────────────────────────────────────

CREATE TABLE finance.gateway_test_reference (
    reference     text PRIMARY KEY REFERENCES finance.payment_reference(reference) ON DELETE CASCADE,
    days          int NOT NULL CHECK (days BETWEEN 1 AND 14),
    issued_by     uuid NOT NULL,
    issued_office text NOT NULL,
    issued_at     timestamptz NOT NULL DEFAULT now(),
    withdrawn_at  timestamptz NULL,
    withdrawn_by  uuid NULL,
    CONSTRAINT ck_gtr_withdrawn CHECK ((withdrawn_at IS NULL) = (withdrawn_by IS NULL))
);
COMMENT ON TABLE finance.gateway_test_reference IS
  'V383: a reference the Bursary issued for a gateway''s testers (Interswitch''s certification of Pay on Quickteller): payable for the days chosen (1 to 14), purpose ''Gateway test by the Bursary'', counting for nothing against the student''s fees; withdrawn = expired early by the Bursary.';
SELECT audit.attach('finance.gateway_test_reference');
GRANT SELECT ON finance.gateway_test_reference TO app_auditor;

-- ── 2 · issued by the Bursary's desk ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION finance.new_gateway_test_reference(p_student uuid, p_session text, p_amount numeric, p_days int)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_days int := coalesce(p_days, 7); v_ref text;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'GATEWAY_TEST_ACTOR: a test reference is issued by a person' USING ERRCODE = '23514';
    END IF;
    IF v_office IS NULL OR v_office NOT IN ('bursar', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'GATEWAY_TEST_OFFICE: a test reference is issued from the Bursary''s desk' USING ERRCODE = '23514',
            HINT = 'The Bursar issues it on Payment Gateways (the Directorate of ICT and the administrators may too).';
    END IF;
    IF v_days < 1 OR v_days > 14 THEN
        RAISE EXCEPTION 'GATEWAY_TEST_DAYS: a test reference stays payable for 1 to 14 days' USING ERRCODE = '23514',
            HINT = 'Seven days covers a test that runs over a week; issue a new one if the test runs longer.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 10000 THEN
        RAISE EXCEPTION 'GATEWAY_TEST_AMOUNT: a test reference is for a small amount, above zero and at most NGN 10,000' USING ERRCODE = '23514',
            HINT = 'NGN 100 is enough to test a payment.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN
        RAISE EXCEPTION 'GATEWAY_TEST_STUDENT: a test reference is issued against a student on the register' USING ERRCODE = '23514';
    END IF;
    -- the shape of every student reference (V027), with the test checkout's purpose; then the days the Bursar chose
    v_ref := finance.new_purpose_reference(p_student, p_session, p_amount, 'Gateway test by the Bursary');
    UPDATE finance.payment_reference SET expires_at = generated_at + make_interval(days => v_days) WHERE reference = v_ref;
    INSERT INTO finance.gateway_test_reference (reference, days, issued_by, issued_office) VALUES (v_ref, v_days, v_actor, v_office);
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION finance.new_gateway_test_reference(uuid, text, numeric, int) IS
  'V383: a test reference for a gateway''s testers — purpose ''Gateway test by the Bursary'' (counts for nothing against the fees), at most NGN 10,000, payable for 1 to 14 days (7 when not given); issued from the Bursary''s desk only.';

-- ── 3 · withdrawn early: it expires now ───────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION finance.withdraw_gateway_test_reference(p_reference text)
RETURNS finance.payment_reference
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ref text := upper(btrim(coalesce(p_reference, ''))); t finance.gateway_test_reference; r finance.payment_reference;
BEGIN
    IF v_actor IS NULL OR v_office IS NULL OR v_office NOT IN ('bursar', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'GATEWAY_TEST_OFFICE: a test reference is withdrawn from the Bursary''s desk' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO t FROM finance.gateway_test_reference WHERE reference = v_ref FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GATEWAY_TEST_NOT_ONE: % is not a test reference the Bursary issued', v_ref USING ERRCODE = '23514',
            HINT = 'Only a test reference is withdrawn here; a payer''s own reference expires on its own.';
    END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE reference = v_ref;
    IF r.confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'GATEWAY_TEST_PAID: % is paid already; a paid reference is not withdrawn', v_ref USING ERRCODE = '23514';
    END IF;
    IF t.withdrawn_at IS NOT NULL OR r.expires_at <= now() THEN
        RAISE EXCEPTION 'GATEWAY_TEST_CLOSED: % has expired already', v_ref USING ERRCODE = '23514';
    END IF;
    UPDATE finance.payment_reference SET expires_at = now() WHERE reference = v_ref RETURNING * INTO r;
    UPDATE finance.gateway_test_reference SET withdrawn_at = now(), withdrawn_by = v_actor WHERE reference = v_ref;
    RETURN r;
END $$;
COMMENT ON FUNCTION finance.withdraw_gateway_test_reference(text) IS
  'V383: an open test reference closed early by the Bursary''s desk: it expires now, so Quickteller is answered Status 1 for it; a paid one is not withdrawn.';

COMMIT;
