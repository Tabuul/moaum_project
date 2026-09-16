-- ===========================================================================
-- V155 - the industrial-training (SIWES) semester
--
--   In the science programmes the whole of 300 level second semester is spent on
--   SIWES / Industrial Training: one course, 6 credit units, and nothing else.
--   The University's flat 18-24 range (V151) does not apply to it, and a student
--   with a carryover does NOT register it that semester - it is registered when
--   the course is next offered (400 level second semester).
--
--   Rather than hard-code programmes, the semester is recognised from the
--   catalogue: a course marked industrial_training that the programme offers at a
--   level and semester makes that a SIWES semester of that course's units.
--
--     · catalogue.course.industrial_training - the marker (seeded from the title:
--       SIWES / Industrial Training / Industrial Attachment / Industrial Work).
--     · registration.siwes_units(programme, level, semester) - the SIWES units for
--       that programme at that level and semester, else NULL.
--     · registration.student_menu no longer offers carryovers in a SIWES semester.
--     · registration.student_submit requires exactly the SIWES units there, and
--       the 18-24 range everywhere else.
--
--   catalogue.course is on the audit spine; the marker is seeded with the trigger
--   lifted (a migration has no acting person). The other objects are functions.
-- ===========================================================================

BEGIN;

-- 1. the marker, and seed it from the course title
ALTER TABLE catalogue.course ADD COLUMN IF NOT EXISTS industrial_training boolean NOT NULL DEFAULT false;

ALTER TABLE catalogue.course DISABLE TRIGGER USER;
UPDATE catalogue.course
   SET industrial_training = true
 WHERE NOT industrial_training
   AND (title ILIKE '%siwes%'
     OR title ILIKE '%industrial training%'
     OR title ILIKE '%industrial attachment%'
     OR title ILIKE '%industrial work%'
     OR title ILIKE '%students industrial work experience%');
ALTER TABLE catalogue.course ENABLE TRIGGER USER;

-- 2. the SIWES units for a programme's level and semester (NULL when it is not a SIWES semester)
CREATE OR REPLACE FUNCTION registration.siwes_units(p_programme text, p_level int, p_semester int)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT nullif(sum(c.units), 0)::int
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
     WHERE co.programme_code = p_programme AND co.level = p_level
       AND c.semester = p_semester AND c.industrial_training AND c.state <> 'ENDED';
$$;

-- 3. the eligible set for the form: in a SIWES semester the carryovers are not offered
CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, kind text, basis text, owner_dept text,
               carryover boolean, failed_in text, lecturer text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL)
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis = 'Carryover'), x.failed_in, p.surname || ', ' || p.given_names
      FROM (SELECT e.*, NULL::text AS failed_in FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
            UNION ALL SELECT * FROM carry) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, x.kind, x.code;
$$;

-- 4. the gate: a SIWES semester carries exactly the SIWES units; everywhere else the 18-24 range
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; lim policy.level_limit; units int; prog text; siwes int;
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
    SELECT programme_code INTO prog FROM people.student WHERE id = r.student_id;
    siwes := registration.siwes_units(prog, r.level, r.semester);
    IF siwes IS NOT NULL THEN
        IF units <> siwes THEN
            RAISE EXCEPTION 'the industrial training semester carries exactly % units', siwes
            USING ERRCODE = '23514',
            HINT = 'This is the SIWES / industrial training semester: register only the industrial training course. A carryover is registered when the course is next offered, not this semester.';
        END IF;
    ELSE
        SELECT * INTO lim FROM policy.level_limit WHERE level = r.level;
        IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
            RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
            USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
        END IF;
    END IF;
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $$;

COMMIT;
