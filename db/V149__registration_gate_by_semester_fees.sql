-- ═══════════════════════════════════════════════════════════════════════════
-- V149 — course registration gated by the semester's school fees, paid in full
--
--   Registration used to open on the clearance scheme's first instalment (half
--   the session charge). The University now wants it per semester: a student
--   cannot register a semester's courses until that semester's school fees are
--   cleared in full. Fees accumulate across the session (V144), so registering
--   the second semester requires the first and second semesters both paid.
--
--     · finance.due_for_semester — the charge up to and including a semester
--       (whole-session items always count), using the same matching as
--       finance.charges (level, entry mode, faculty, programme, fee group,
--       indigeneship, spillover).
--     · finance.semester_cleared — the confirmed school-fee payments for the
--       session meet that cumulative due.
--     · registration.student_submit now gates on it instead of the scheme.
--
--   The clearance scheme still governs the examination, results, transcript and
--   convocation; only registration moved to the per-semester fee rule.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.due_for_semester(p_student uuid, p_session text, p_semester int)
RETURNS numeric LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND (f.entry_mode IS NULL OR f.entry_mode = me.entry_mode)
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$$;

CREATE OR REPLACE FUNCTION finance.semester_cleared(p_student uuid, p_session text, p_semester int)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                      WHERE r.student_id = p_student AND r.session = p_session
                        AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'), 0)
           >= finance.due_for_semester(p_student, p_session, p_semester);
$$;

COMMENT ON FUNCTION finance.semester_cleared(uuid, text, int) IS
'True when the student''s confirmed school-fee payments for the session cover the charge up to and including the semester.';

-- registration now opens per semester, on that semester's fees paid in full
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; lim policy.level_limit; units int;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    IF NOT finance.semester_cleared(r.student_id, r.session, r.semester) THEN
        RAISE EXCEPTION 'the % semester school fees for % are not fully paid',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for a semester opens when that semester''s school fees are cleared in full; the position updates the moment a payment is confirmed.';
    END IF;
    units := registration.units_of(p_registration);
    SELECT * INTO lim FROM policy.level_limit WHERE level = r.level;
    IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $$;

COMMIT;
