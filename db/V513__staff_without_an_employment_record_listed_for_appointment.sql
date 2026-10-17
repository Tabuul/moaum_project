-- ═══════════════════════════════════════
-- V513 — The staff on the portal without an employment record, listed with what the portal already knows of each
--
-- Payroll, identity cards, the Head of Department's staff list and the staff registers read hrm.employment, and the live-shaped
-- copy has none for its 1,544 people with a staff number (V510 made the appointment itself). hrm.staff_without_employment lists
-- every person with a staff number and no employment record in service, with what an appointment would carry that the portal
-- already holds: the names, e-mail and phone (iam.person); the category — ACADEMIC for a lecturer on the establishment of a
-- department (V135/V137), else the establishment record's; the department — the establishment record's, else the lecturer
-- grant's; the unit, rank, sex and date of first appointment from the establishment record (hrm.staff_record). Human Resources
-- downloads it as the appointment template filled in, adds the grade, step and date, and uploads it (hrm.appoint_many, V510).
-- Nothing is written by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'hrm', true),
       set_config('moaum.reason', 'V513: the staff without an employment record listed for appointment', true);

CREATE FUNCTION hrm.staff_without_employment()
RETURNS TABLE(person_id uuid, staff_no text, surname text, given_names text, email text, phone text, category text,
              department text, department_name text, unit text, unit_name text, rank text, sex text, first_appointment date, source text)
LANGUAGE sql STABLE AS $$
    WITH p AS (
        SELECT x.id, btrim(x.staff_number) AS staff_no, x.surname, x.given_names, x.email, x.phone
          FROM iam.person x
         WHERE x.staff_number IS NOT NULL AND btrim(x.staff_number) <> '' AND x.ended_on IS NULL
           AND NOT EXISTS (SELECT 1 FROM hrm.employment e WHERE e.person_id = x.id AND e.status <> 'ENDED')),
    -- the department a lecturer's standing grant names (V135/V137: every teacher is on the establishment of a department)
    lect AS (
        SELECT DISTINCT ON (a.person_id) a.person_id, iam.live_scope_code('department', a.scope_id) AS dept
          FROM iam.office_assignment a JOIN p ON p.id = a.person_id
         WHERE a.office_code = 'lecturer' AND a.scope_kind = 'department'
           AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
         ORDER BY a.person_id, a.valid_from DESC)
    SELECT p.id, p.staff_no, upper(btrim(p.surname)), btrim(p.given_names), p.email, p.phone,
           coalesce(CASE WHEN l.dept IS NOT NULL THEN 'ACADEMIC' END, sr.category),
           coalesce(sr.home_department, l.dept), d.name, sr.home_unit, u.name, sr.present_rank, sr.sex, sr.date_first_appointment,
           CASE WHEN sr.person_id IS NOT NULL AND l.dept IS NOT NULL THEN 'ESTABLISHMENT_AND_LECTURER'
                WHEN sr.person_id IS NOT NULL THEN 'ESTABLISHMENT' WHEN l.dept IS NOT NULL THEN 'LECTURER' ELSE 'PERSON_ONLY' END
      FROM p
      LEFT JOIN hrm.staff_record sr ON sr.person_id = p.id
      LEFT JOIN lect l ON l.person_id = p.id
      LEFT JOIN ref.department d ON d.code = coalesce(sr.home_department, l.dept)
      LEFT JOIN ref.unit u ON u.code = sr.home_unit
$$;
COMMENT ON FUNCTION hrm.staff_without_employment() IS
  'V513: every person with a staff number and no employment record in service, with what an appointment would carry that the portal already holds (names, contact, category, department or unit, rank, sex, first appointment) and where it came from (ESTABLISHMENT, LECTURER, both, or PERSON_ONLY)';

COMMIT;
