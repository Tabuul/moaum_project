-- V361: course registration refuses a student whose school fees for the session are not stated.
--
-- A semester's fees were "cleared" when what was paid reached what was due — and with no fee line stated for the
-- student's programme and level, nothing was due, so nothing paid was enough: 2026/2027 was open for registration with
-- eleven fee lines stated against 460 the session before, and students registered without paying. Now a session's fees
-- must be stated for the student (a line of the fee schedule that applies to them, ₦0 if the Bursary means free) before
-- they can be cleared; course registration refuses until then, saying so. Registrations already made stay as they are.
BEGIN;

/* whether the Bursary has stated a school fee that applies to the student for the session — the same matching as
   finance.due_for_semester (programme, faculty, level, entry mode, fee group, indigene, spillover), any semester */
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
    SELECT EXISTS (
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
COMMENT ON FUNCTION finance.fee_stated(uuid, text) IS 'V361: whether a school-fee line of the session applies to the student; until one does, nothing is cleared against it.';

/* a semester's fees are cleared when they are stated and what is paid reaches what is due */
CREATE OR REPLACE FUNCTION finance.semester_cleared(p_student uuid, p_session text, p_semester integer)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT finance.fee_stated(p_student, p_session)
       AND coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                      WHERE r.student_id = p_student AND r.session = p_session
                        AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'), 0)
           >= finance.due_for_semester(p_student, p_session, p_semester);
$$;

-- the student's own submission says why, rather than "not fully paid" when nothing could be paid
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; lim policy.level_limit; units int; st record; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared
    IF NOT finance.fee_stated(r.student_id, r.session) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid; nothing is assumed to be free.';
    END IF;
    IF NOT finance.semester_cleared(r.student_id, r.session, r.semester) THEN
        RAISE EXCEPTION 'the % semester school fees for % are not fully paid',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for a semester opens when that semester''s school fees are cleared in full; the position updates the moment a payment is confirmed.';
    END IF;
    -- V314: where the University holds the whole registration on the GST fee, an unpaid student does not submit
    v_gate := registration.gst_gate(r.student_id, r.session, NULL);
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; submission opens the moment the payment is confirmed.';
    END IF;
    -- and a GST/EPS course already on the draft is not submitted unpaid either
    SELECT registration.gst_gate(r.student_id, r.session, o.course_code) INTO v_gate
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
     WHERE e.registration_id = p_registration AND e.status <> 'DROPPED' AND registration.gst_gate(r.student_id, r.session, o.course_code) IS NOT NULL
     LIMIT 1;
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS, or remove the GST/EPS courses from the registration.';
    END IF;
    units := registration.units_of(p_registration);
    SELECT * INTO lim FROM policy.level_limit WHERE level = r.level;
    IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    SELECT * INTO st FROM assessment.student_standing(r.student_id);
    IF FOUND AND st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % % semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, CASE st.pronounced_semester WHEN 1 THEN 'first' ELSE 'second' END, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $function$;

COMMIT;
