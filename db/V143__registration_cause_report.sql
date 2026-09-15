-- ═══════════════════════════════════════════════════════════════════════════
-- V143 — registration.registration_cause: why students are not registered
--
--   A per faculty/programme return that splits the students who have NOT
--   registered for a session/semester into the two causes that call for
--   different action:
--     · fee-blocked   — the Bursary has not cleared them for registration
--                       (they owe the instalment the clearance rule requires,
--                       or no clearance scheme is in force at all)
--     · cleared, idle — cleared for registration but have not registered;
--                       a reminder or a window extension actually helps here
--
--   Read-only. Expected is the active, matriculated cohort. finance.clears is
--   only called when a clearance scheme is in force (it raises otherwise), so
--   with no scheme every non-registrant is counted as fee-blocked — which is
--   itself the finding: nobody can clear until the Bursar puts a scheme in force.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION registration.registration_cause(p_session text, p_semester int)
RETURNS TABLE (faculty_code text, faculty text, programme_code text, programme text,
               expected int, registered int, not_registered int, fee_blocked int, cleared_idle int,
               scheme_in_force boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_force boolean := policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL;
BEGIN
    RETURN QUERY
    WITH pop AS (
        SELECT s.id, s.programme_code,
               EXISTS (SELECT 1 FROM registration.course_registration r
                        WHERE r.student_id = s.id AND r.session = p_session AND r.semester = p_semester
                          AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS reg
          FROM people.student s
         WHERE s.matric_no IS NOT NULL AND s.status IN ('ACTIVE', 'PROBATION')
    ),
    marked AS (
        SELECT pop.*,
               CASE WHEN pop.reg THEN false
                    WHEN v_force THEN NOT finance.clears(pop.id, p_session, 'REGISTRATION')
                    ELSE true END AS blocked
          FROM pop
    )
    SELECT f.code, f.name, pg.code, pg.name,
           count(*)::int AS expected,
           count(*) FILTER (WHERE m.reg)::int AS registered,
           count(*) FILTER (WHERE NOT m.reg)::int AS not_registered,
           count(*) FILTER (WHERE NOT m.reg AND m.blocked)::int AS fee_blocked,
           count(*) FILTER (WHERE NOT m.reg AND NOT m.blocked)::int AS cleared_idle,
           v_force
      FROM marked m
      JOIN ref.programme pg ON pg.code = m.programme_code
      JOIN ref.faculty f ON f.code = pg.faculty_code
     GROUP BY f.code, f.name, pg.code, pg.name
     ORDER BY f.name, pg.name;
END $$;

COMMENT ON FUNCTION registration.registration_cause(text, int) IS
  'Per faculty/programme, the not-registered students split into fee-blocked vs '
  'cleared-but-idle for a session/semester. Read-only; guides whether the fix is '
  'a payment plan (fees) or a reminder/window extension (registration).';

COMMIT;
