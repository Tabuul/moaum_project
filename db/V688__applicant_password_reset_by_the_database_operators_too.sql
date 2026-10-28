-- ════════════════════════════════════════════════════════════════════════
--  V688 · Applicant password reset by the Database Operators too
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 28 October 2026, on V687's Applicant Password Reset: "add applicant password reset to the database
--  operators too". V687 let the Director of ICT, the Academic Office and ICT Support (and super) reset a Post-UTME applicant's
--  password; now a Database Operator (dbops) does too, from the Academic menu — on a grant over the whole University only (the API's
--  OfficeScope.requireUniversityOperator, SCOPE_UNIVERSITY, as V679 and V680): an applicant belongs to no faculty, department or
--  programme of the register yet.
--
--  · admissions.applicant_password_officer restated: dbops beside V687's offices.
--  · admissions.applicant_password_reset.reset_office takes dbops.
--  Everything else as V687.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.applicant_password_reset DROP CONSTRAINT IF EXISTS applicant_password_reset_reset_office_check;
ALTER TABLE admissions.applicant_password_reset ADD CONSTRAINT applicant_password_reset_reset_office_check
    CHECK (reset_office IN ('ict', 'academic', 'ictagent', 'helpdeskhead', 'dbops', 'super'));

CREATE OR REPLACE FUNCTION admissions.applicant_password_officer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'APW_ACTOR: a password is reset by a person' USING ERRCODE = '23514'; END IF;
    -- V688: and the Database Operators (one over the whole University: the API's check)
    IF v_office NOT IN ('ict', 'academic', 'ictagent', 'helpdeskhead', 'dbops', 'super') THEN
        RAISE EXCEPTION 'APW_OFFICE: the Director of ICT, the Academic Office, ICT Support or a Database Operator resets an applicant''s password, not %', v_office USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;
COMMENT ON FUNCTION admissions.applicant_password_officer() IS
  'V687, V688: the person resetting an applicant''s password, in an office that may — ict, academic, ictagent, helpdeskhead, dbops (over the whole University, the API''s check) or super; APW_OFFICE otherwise.';

COMMIT;
