-- ═══════════════════════════════════════════════════════════════════════════
-- V246 — Senate's rule on probation and withdrawal, as one function
--
--   Senate's wording (24 September 2026):
--     · at the end of 100 level second semester, a CGPA under 1.0 is
--       TO GO ON PROBATION;
--     · at 200 level first semester, a CGPA still under 1.0 puts the name
--       on the PROBATION LIST;
--     · at the end of 200 level second semester, a CGPA still under 1.0 is
--       ADVISED TO WITHDRAW.
--   The pattern repeats at every level above 100: the first semester
--   pronounces the probation list, the second semester advises withdrawal
--   of a student who was on that list and is still under 1.0. A student
--   under 1.0 at a second semester who was NOT on the list at the first
--   (a fresh fall, or a Direct Entry student's 200 level whose first
--   semester has no standing) goes on probation instead. Nothing is
--   pronounced at 100 level first semester.
--
--   assessment.standing_of is the rule, pure, so the broadsheet remark
--   (the API), the student's standing (below) and the checks all read
--   the one function. assessment.student_standing now judges by the
--   latest semester with a published CGPA, so probation pronounced at
--   100 level second semester holds through the 200 level first semester
--   registration, and a student advised to withdraw is held to the
--   probation ceiling too until Senate decides.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the rule: what a semester's cumulative standing pronounces — NULL when nothing is
CREATE OR REPLACE FUNCTION assessment.standing_of(p_level int, p_semester int, p_cgpa numeric, p_prev_cgpa numeric, p_de_at_200 boolean)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_cgpa IS NULL OR p_cgpa >= 1.0 THEN NULL
        -- a first semester: the probation list, from 200 level, never a Direct Entry student's 200 level
        WHEN p_semester = 1 THEN CASE WHEN p_level >= 200 AND NOT coalesce(p_de_at_200, false) THEN 'PROBATION' END
        -- a second semester: still under 1.0 after that level's probation list is advice to withdraw;
        -- otherwise (100 level, a fresh fall, a Direct Entry student's 200 level) probation
        WHEN p_level >= 200 AND NOT coalesce(p_de_at_200, false) AND p_prev_cgpa IS NOT NULL AND p_prev_cgpa < 1.0 THEN 'ADVISED_TO_WITHDRAW'
        ELSE 'PROBATION'
    END
$$;
COMMENT ON FUNCTION assessment.standing_of(int, int, numeric, numeric, boolean) IS
  'Senate''s rule: PROBATION at 100 level second semester or any first semester from 200 level with the CGPA under 1.0; ADVISED_TO_WITHDRAW at a second semester from 200 level still under 1.0 after that level''s first semester was; NULL when nothing is pronounced. p_prev_cgpa is the CGPA after the semester before; p_de_at_200 marks a Direct Entry student''s 200 level, whose first semester has no standing.';

-- the student's standing: the latest semester with a published CGPA, judged by the rule
CREATE OR REPLACE FUNCTION assessment.student_standing(p_student uuid)
RETURNS TABLE (standing text, cgpa numeric, pronounced_session text, pronounced_semester int, pronounced_level int)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    sems AS (
        SELECT g.session, g.semester, g.cgpa, g.lcgpa, r.level
          FROM assessment.student_gpa(p_student) g
          JOIN registration.course_registration r ON r.student_id = p_student AND r.session = g.session AND r.semester = g.semester
         WHERE g.cgpa IS NOT NULL AND g.published_count > 0
    ),
    latest AS (SELECT * FROM sems ORDER BY session DESC, semester DESC LIMIT 1)
    SELECT coalesce(assessment.standing_of(l.level, l.semester, l.cgpa, l.lcgpa, s.entry_mode = 'DIRECT_ENTRY' AND l.level = 200), 'GOOD'),
           l.cgpa, l.session, l.semester, l.level
      FROM latest l CROSS JOIN s
    UNION ALL
    SELECT 'GOOD', NULL, NULL, NULL, NULL WHERE NOT EXISTS (SELECT 1 FROM latest)
$$;
COMMENT ON FUNCTION assessment.student_standing(uuid) IS
  'PROBATION or ADVISED_TO_WITHDRAW as Senate''s rule (assessment.standing_of) pronounces on the latest semester with a published CGPA; GOOD otherwise, and before any result.';

-- the submit gate: on probation, or advised to withdraw and awaiting Senate, the registration is held to the level's probation ceiling where one is set
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; lim policy.level_limit; units int; st record;
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
    SELECT * INTO st FROM assessment.student_standing(r.student_id);
    IF FOUND AND st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % % semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, CASE st.pronounced_semester WHEN 1 THEN 'first' ELSE 'second' END, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $$;

COMMIT;
