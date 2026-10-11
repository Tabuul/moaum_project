-- ═══════════════════════════════════════
-- V390 — an applicant's fee reference is drawn until a free one is found
--
--   A fee reference reads MOAUM-APP-000123-4821: the kind, the last six digits
--   of the application number and four random digits (V021), unique across
--   the table. The last six digits are the session's running number, so the
--   first applicant of 2025/2026 and the first of 2026/2027 share them, and
--   one draw in ten thousand gave the second the first's reference — a 409 at
--   the door, "ALREADY_EXISTS", on an afternoon when nothing else was wrong
--   (CI met it once in a few hundred runs: PaymentsIT). The reference is now
--   inserted ON CONFLICT DO NOTHING and drawn again when taken, up to fifty
--   times; the format, the amount, the expiry and every refusal of V379 stand.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V390: fee references drawn until free', true);

CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean; v_try int;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    IF v_cce AND p_kind = 'CHECKING' THEN
        RAISE EXCEPTION 'CCE_NO_CHECKING_FEE: a CCE applicant reads the published outcome without a checking fee' USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'CHECKING' THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already confirmed; it is paid once, and nothing more is owed to check your admission status' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_CLOSED: admission status checking is closed; the admission checking fee is paid while the University has it open' USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: an offer is paid for, accepted or declined only after you have checked your admission status and read it' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce THEN
        -- V379: the CCE fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, 0::numeric AS checking_fee INTO fee FROM admissions.route_fee_rule(a.session, 'CCE') r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION 'CCE_FEE_NOT_STATED: the Bursary has not stated the CCE % fee for %', lower(p_kind), a.session USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    -- V390: the four random digits may repeat a reference another application drew (the last six digits of an application
    -- number are the session's running number, shared across sessions); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
                 || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
        VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free % reference was found for % in fifty draws', lower(p_kind), a.application_no USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;
COMMENT ON FUNCTION admissions.new_fee_reference(uuid, text) IS
    'V021, V271, V295, V379, V390: an applicant''s fee reference — the kind, the last six digits of the application number and four random digits, drawn again when the reference is already taken';

COMMIT;
