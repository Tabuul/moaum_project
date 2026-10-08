-- V362: clearance for the examination, results, the identity card and the rest refuses until the session's fees are
--       stated; the registrations made without a fee paid are listed for the Bursary and the Registry.
--
-- 1. finance.clears asked the Bursar's clearance scheme with the student's fee position, and a student with no fee line
--    stated for the session was "paid in full" on ₦0 — the examination card, the results and the identity card opened
--    for them without a payment, as course registration did until V361. Now a session's fees must be stated for the
--    student before anything is cleared against them.
-- 2. The portal's fee schedule began with a session (2025/2026 on the University's record); the sessions before it were
--    paid on the old portal and carry no fee lines here. Their clearance stays as it was — a student's old results and
--    transcript are not withheld because the old portal kept no fee schedule. V361's registration check follows the
--    same line.
-- 3. finance.registrations_without_fees(session): the registrations of a session whose semester's fees are not cleared —
--    not stated for the student, or not paid — read for the Bursary and the Registry to act on. Nothing is changed or
--    deleted by it.
BEGIN;

/* the first session the portal's fee schedule covers, or null when it covers none */
CREATE OR REPLACE FUNCTION finance.schedule_from()
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT min(session) FROM finance.fee_schedule WHERE ended_at IS NULL
$$;

/* whether the school fees of a session are stated for the student: a session before the portal's fee schedule began is
   taken as stated (its fees were the old portal's); from it on, a school-fee line must apply to the student */
CREATE OR REPLACE FUNCTION finance.fee_stated(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT p_session < coalesce(finance.schedule_from(), p_session)
        OR EXISTS (
        SELECT 1
          FROM finance.fee_schedule f
          CROSS JOIN me
          JOIN ref.programme p ON p.code = me.programme_code
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
          LEFT JOIN home ON true
         WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
           AND f.spillover = me.is_spill
           AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
           AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
           AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state))))
$$;
COMMENT ON FUNCTION finance.fee_stated(uuid, text) IS 'V361/V362: whether a school-fee line of the session applies to the student (a session before the portal''s fee schedule began is taken as stated); until it does, nothing is cleared against it.';

/* clearance for a purpose (examination, results, identity card, …): the Bursar's scheme on the student's fee position —
   and nothing at all while the session's fees are not stated for the student */
CREATE OR REPLACE FUNCTION finance.clears(p_student uuid, p_session text, p_purpose text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN NOT finance.fee_stated(p_student, p_session) THEN false
                ELSE (SELECT policy.clears(p_purpose, pos.instalments_paid, pos.paid_in_full, pos.has_arrears, current_date, 'UNIVERSITY')
                        FROM finance.position(p_student, p_session) pos) END
$$;

/* the registrations of a session whose semester's school fees are not cleared — not stated for the student, or not
   paid — with what is due and what is paid; read only */
CREATE OR REPLACE FUNCTION finance.registrations_without_fees(p_session text)
RETURNS TABLE (registration_id uuid, student_id uuid, number text, name text, programme text, faculty text, level int, semester int,
               status text, submitted_at timestamptz, approved_at timestamptz, stated boolean, due numeric, paid numeric)
LANGUAGE sql STABLE AS $$
    SELECT r.id, s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.name, f.name, r.level, r.semester,
           r.status, r.submitted_at, r.approved_at, x.stated,
           CASE WHEN x.stated THEN finance.due_for_semester(s.id, r.session, r.semester) END,
           coalesce((SELECT sum(pr.amount) FROM finance.payment_reference pr
                      WHERE pr.student_id = s.id AND pr.session = r.session AND pr.confirmed_at IS NOT NULL AND pr.purpose LIKE 'School fees%'), 0)
      FROM registration.course_registration r
      JOIN people.student s ON s.id = r.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      CROSS JOIN LATERAL (SELECT finance.fee_stated(s.id, r.session) AS stated) x
     WHERE r.session = p_session AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
       AND NOT finance.semester_cleared(s.id, r.session, r.semester)
     ORDER BY f.name, p.name, s.surname, s.other_names, r.semester
$$;
COMMENT ON FUNCTION finance.registrations_without_fees(text) IS 'V362: the registrations of a session made without the semester''s school fees cleared — for the Bursary and the Registry to act on; nothing is changed by reading it.';

COMMIT;
