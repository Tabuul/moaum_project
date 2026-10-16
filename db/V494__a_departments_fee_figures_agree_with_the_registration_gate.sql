-- ═══════════════════════════════════════
-- V494 — A department's fee figures agree with the registration gate
--
-- The Head of Department's dashboard counts the department's students cleared for registration, and owing, from
-- finance.session_clears (every student's position for the session, read at once). The gate itself (finance.clears) refuses a
-- student for whom no fee is stated for the session (V361); session_clears read such a student, with nothing due, as paid in
-- full and cleared — 32 of Biological Sciences' 4,807 students on the live-shaped copy were counted cleared whom registration
-- refuses. finance.session_clears is restated from its current definition with that one rule, asked only of a student with
-- nothing due. Nothing is written by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V494: a department''s fee figures agree with the registration gate', true);

CREATE OR REPLACE FUNCTION finance.session_clears(p_session text, p_purpose text)
 RETURNS TABLE(student_id uuid, clears boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_version uuid; v_at text; v_arrears boolean;
BEGIN
    -- the same refusals as policy.clears, from policy.clears itself: no scheme in force, no rule for the purpose
    PERFORM policy.clears(p_purpose, 0, false, false, current_date, 'UNIVERSITY');
    v_version := policy.in_force('clearance', 'UNIVERSITY', current_date);
    SELECT r.releases_at, s.arrears_block_all INTO v_at, v_arrears
      FROM policy.clearance_rule r JOIN policy.clearance_scheme s ON s.version_id = r.version_id
     WHERE r.version_id = v_version AND r.purpose = p_purpose;

    RETURN QUERY
    SELECT p.student_id,
           -- V494: as finance.clears — a student with no fee stated for the session is not cleared (V361), however nothing is due
           CASE WHEN p.due <= 0 AND NOT finance.fee_stated(p.student_id, p_session) THEN false
                WHEN v_at = 'NEVER_GATED' THEN true
                WHEN v_arrears AND p.has_arrears THEN false
                ELSE CASE v_at WHEN 'INSTALMENT_1' THEN p.instalments_paid >= 1
                               WHEN 'INSTALMENT_2' THEN p.instalments_paid >= 2
                               WHEN 'PAID_IN_FULL' THEN p.paid_in_full END END
      FROM finance.session_fee_positions(p_session) p;
END $function$;
COMMENT ON FUNCTION finance.session_clears(text, text) IS
  'Every student''s clearance for a purpose in a session, read at once from the session''s fee positions; V494: a student with no fee stated is not cleared, as finance.clears.';

COMMIT;
