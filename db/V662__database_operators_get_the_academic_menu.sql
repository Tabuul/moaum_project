-- ═══════════════════════════════════════
-- V662 — Database Operators get the Academic menu
--
-- The word of 26 October 2026 ("add academic menu on the director ict to Database operators too"), with its answer — everything the
-- Director of ICT does there. The Database Operator (V640) read and wrote nothing; the Academic menu is six screens that write:
-- Upload or Create Faculties, Programmes, Departments and Courses, Course Allocation, and Migrate from Old Portal. The API now admits
-- the office to them (CatalogueController, the allocation desk and its imports and templates, ResultsController's old-portal
-- migration, clearing the migrated students), holding an operator to its grant (iam.dbops_scope): one granted over the whole
-- University does what the Director does; one held to a faculty, department or programme uploads its own programmes' course
-- structures and allocates within its reach (AllocationReach), and is refused the University's register (faculties, departments,
-- programmes), opening registration and the old-portal migration (OfficeScope.requireUniversityOperator, SCOPE_UNIVERSITY).
-- The one rule the database keeps itself: past results are uploaded by the Directorate of ICT (V627, assessment.past_results_office)
-- — and now by a Database Operator granted over the whole University.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V662: Database Operators get the Academic menu', true);

CREATE OR REPLACE FUNCTION assessment.past_results_office()
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF coalesce(current_setting('moaum.legacy_reconcile', true), '') = 'on' OR v_office IS NULL THEN
        RETURN;
    END IF;
    -- V662: a Database Operator granted over the whole University uploads them as the Directorate does
    IF v_office = 'dbops' AND coalesce((SELECT s.kind FROM iam.dbops_scope(v_actor) s), '') = 'institution' THEN
        RETURN;
    END IF;
    IF v_office NOT IN ('ict', 'super') THEN
        RAISE EXCEPTION 'PAST_RESULTS_OFFICE: past results are uploaded by the Directorate of ICT or a Database Operator granted over the whole University'
              USING ERRCODE = '42501';
    END IF;
END $$;
COMMENT ON FUNCTION assessment.past_results_office() IS
  'V627, V662: refuses a past results load (or its preview) by an acting office other than ict, super or a Database Operator granted over the whole University (iam.dbops_scope); posting held results '
  '(moaum.legacy_reconcile on, set by the reconcile functions for their own transaction) and a load with no acting office pass.';

COMMIT;
