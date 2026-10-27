-- ════════════════════════════════════════════════════════════════════════
--  V679 · The old-portal PG migration desk opened to the Director of ICT and the Database Operators
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 27 October 2026, on V675's Legacy Migration desk (/admissions/postgraduate/migration): "all this
--  should be on ict director and database operators dashboard". V675 let the School of Postgraduate Studies, its Secretary
--  and the Academic Office (and super) migrate old-portal PG applicants; now the Director of ICT (ict) and the Database
--  Operators (dbops) do too — the desk in their menus, its figures on their dashboards.
--
--  · admissions.pg_mig_writer() restated: ict and dbops beside V675's offices. Every write of the migration (opening a batch,
--    staging, the check, the import, finishing or setting aside, the programme mapping, a row confirmed as new, a document's
--    file) asks it, as before.
--  · A Database Operator migrates only on a grant over the whole University (the API's OfficeScope.requireUniversityOperator,
--    SCOPE_UNIVERSITY, as V662's University-level acts): one held to a faculty, department or programme is refused.
--  · Unchanged: verifying a fee paid on the old portal stays the Bursary's or the PG Secretary's (admissions.pg_legacy_fee_decide,
--    PGMIG_FEE_OFFICE) — the officer who uploads never verifies; ICT Support (ictagent) has no access.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.pg_mig_writer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PGMIG_ACTOR: a migration is made by a person' USING ERRCODE = '23514'; END IF;
    -- V679: the Director of ICT and the Database Operators beside the School, its Secretary and the Academic Office
    IF v_office NOT IN ('pgschool', 'pgsecretary', 'academic', 'ict', 'dbops', 'super') THEN
        RAISE EXCEPTION 'PGMIG_OFFICE: the School of Postgraduate Studies, its Secretary, the Academic Office, the Director of ICT or a Database Operator migrates old-portal applicants, not %', v_office USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;
COMMENT ON FUNCTION admissions.pg_mig_writer() IS
  'V675, V679: the person making a migration write, in an office that migrates old-portal PG applicants — pgschool, pgsecretary, academic, ict, dbops (a Database Operator over the whole University, the API''s check) or super; PGMIG_OFFICE otherwise.';

COMMIT;
