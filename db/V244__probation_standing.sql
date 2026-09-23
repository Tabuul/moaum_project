-- ═══════════════════════════════════════════════════════════════════════════
-- V244 — a student's standing, and what probation does
--
--   The broadsheet pronounces probation in the first semester of every
--   level above 100: a CGPA under 1.0 there is TO GO ON PROBATION. Until
--   now nothing followed. The standing is now a function of the record —
--   assessment.student_standing — read by the student's dashboard, the
--   registration form and the submit gate: a student on probation
--   registers no more than the probation ceiling the Registry sets on the
--   level's limits (policy.level_limit.probation_max_units), and is told
--   so. The ceiling is the Registry's to set; until it is set for a level,
--   probation is pronounced and shown but does not cut the units.
--
--   The standing is judged by the latest first semester at 200 level or
--   above with a published CGPA; a Direct Entry student's first semester
--   (200 level first) does not judge them. It holds until the next first
--   semester pronounces again.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE policy.level_limit ADD COLUMN probation_max_units int NULL
    CONSTRAINT ck_level_limit_probation CHECK (probation_max_units IS NULL OR probation_max_units >= 0);
COMMENT ON COLUMN policy.level_limit.probation_max_units IS
  'The most units a student on probation registers at this level; NULL until the Registry sets it (then probation is shown, not enforced).';

CREATE OR REPLACE FUNCTION assessment.student_standing(p_student uuid)
RETURNS TABLE (standing text, cgpa numeric, pronounced_session text, pronounced_semester int, pronounced_level int)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    firsts AS (
        SELECT g.session, g.semester, g.cgpa, r.level
          FROM assessment.student_gpa(p_student) g
          JOIN registration.course_registration r ON r.student_id = p_student AND r.session = g.session AND r.semester = g.semester
          CROSS JOIN s
         WHERE g.semester = 1 AND r.level >= 200 AND g.cgpa IS NOT NULL AND g.published_count > 0
           AND NOT (s.entry_mode = 'DIRECT_ENTRY' AND g.session = s.entry_session AND r.level = 200)
    ),
    latest AS (SELECT * FROM firsts ORDER BY session DESC, semester DESC LIMIT 1)
    SELECT CASE WHEN l.cgpa < 1.0 THEN 'PROBATION' ELSE 'GOOD' END, l.cgpa, l.session, l.semester, l.level
      FROM latest l
    UNION ALL
    SELECT 'GOOD', NULL, NULL, NULL, NULL WHERE NOT EXISTS (SELECT 1 FROM latest)
$$;

COMMENT ON FUNCTION assessment.student_standing(uuid) IS
  'PROBATION when the latest first semester at 200 level or above (a Direct Entry student''s first excluded) left the CGPA under 1.0; GOOD otherwise, and before any such semester.';

-- the submit gate: on probation, the registration is held to the level's probation ceiling where one is set
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
    IF FOUND AND st.standing = 'PROBATION' AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % first semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $$;

COMMIT;
