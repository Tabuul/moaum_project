-- ═══════════════════════════════════════════════════════════════════════════
-- V016 — a query on a faculty list is withdrawn, not deleted
--
-- V013 let a Faculty Officer put a name under query with the reason. When
-- the reason is cleared, the query has to come off — and nothing in this
-- database is deleted, so it is withdrawn with a time, stays readable, and
-- stops counting. The list and the run both ignore a withdrawn query.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'V016: a query is withdrawn, not deleted', true);
END $seed$;

ALTER TABLE people.faculty_list_query ADD COLUMN withdrawn_at timestamptz NULL;

CREATE OR REPLACE FUNCTION people.faculty_list_rows(p_session text, p_faculty text)
RETURNS TABLE (student_id uuid, admission_no text, surname text, other_names text, dept_code text,
               dept_name text, units int, registration_status text, query_reason text, query_office text)
LANGUAGE sql
STABLE
AS $$
    SELECT s.id, s.admission_no, s.surname, s.other_names, p.dept_code, d.name,
           registration.units_of(r.id), r.status, q.reason, q.office
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.department d ON d.code = p.dept_code
      JOIN registration.course_registration r ON r.student_id = s.id AND r.session = p_session
      LEFT JOIN people.faculty_list l ON l.session = p_session AND l.faculty_code = p.faculty_code
      LEFT JOIN people.faculty_list_query q ON q.list_id = l.id AND q.student_id = s.id AND q.withdrawn_at IS NULL
     WHERE p.faculty_code = p_faculty AND s.status = 'ADMITTED' AND r.status IN ('APPROVED','LOCKED')
     ORDER BY d.name, s.surname, s.other_names
$$;

COMMIT;
