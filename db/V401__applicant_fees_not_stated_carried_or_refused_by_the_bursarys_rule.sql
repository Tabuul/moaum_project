-- ═══════════════════════════════════════
-- V401 — a session whose applicant fees are not stated: carried forward, or refused, by the Bursary's rule
--
--   admissions.applicant_fee_rule (V272) carries the last stated session's applicant fees forward where a session has none of
--   its own, so an applicant was never charged nought — and, since V378 files Post-UTME under the coming session, candidates
--   of a session the Bursary has not reached yet were quietly charged the previous session's amounts (or the built-in ones).
--   The Bursary now chooses, once for the University (finance.fee_setting.applicant_fee_unstated):
--     CARRY  — as before: the last stated session's amounts apply until the session's own are stated (the default);
--     REFUSE — no fee reference is issued for a session whose applicant fees are not stated (APPLICANT_FEE_NOT_STATED);
--              the amounts shown stay the carried ones, marked as not stated, and the readiness names the gap.
--   Only admissions.new_fee_reference changes behaviour, under REFUSE; it is restated from its definition after V398.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V401: applicant fees not stated, carried or refused by the Bursary''s rule', true);

ALTER TABLE finance.fee_setting ADD COLUMN IF NOT EXISTS applicant_fee_unstated text NOT NULL DEFAULT 'CARRY';
ALTER TABLE finance.fee_setting DROP CONSTRAINT IF EXISTS ck_fee_setting_applicant_unstated;
ALTER TABLE finance.fee_setting ADD CONSTRAINT ck_fee_setting_applicant_unstated CHECK (applicant_fee_unstated IN ('CARRY', 'REFUSE'));
COMMENT ON COLUMN finance.fee_setting.applicant_fee_unstated IS
  'V401: for a session whose applicant fees are not stated — CARRY the last stated session''s forward (the default) or REFUSE a fee reference until they are stated.';

CREATE OR REPLACE FUNCTION admissions.applicant_fee_policy()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT f.applicant_fee_unstated FROM finance.fee_setting f WHERE f.id = 1), 'CARRY')
$fn$;
COMMENT ON FUNCTION admissions.applicant_fee_policy() IS 'V401: CARRY or REFUSE — the Bursary''s rule for a session whose applicant fees are not stated.';

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
        -- admission status checking open â€” admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already paid; nothing more is owed' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_CLOSED: admission status checking is closed' USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
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
    -- V401: where the Bursary refuses to carry a session's applicant fees forward, nothing is paid until they are stated
    IF NOT fee.stated AND admissions.applicant_fee_policy() = 'REFUSE' THEN
        RAISE EXCEPTION 'APPLICANT_FEE_NOT_STATED: the % fee for % is not stated yet', lower(p_kind), a.session USING ERRCODE = '23514',
            HINT = 'The Bursary states the applicant fees for the session on Fee Setup.';
    END IF;
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

COMMIT;
