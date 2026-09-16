-- ===========================================================================
-- V157 - a SIWES semester is one industrial-training course, not the sum of them
--
--   V155 summed every industrial-training course a programme offers that semester,
--   so a department that lists two (e.g. CMP 360 Industrial Training and COS 398
--   SIWES, 6 units each) got a 12-unit requirement and both had to be registered.
--   Only one is registered. Take a single course's units instead, so the SIWES
--   semester carries exactly that (6), one course is valid and two exceeds it.
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION registration.siwes_units(p_programme text, p_level int, p_semester int)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT max(c.units)::int
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
     WHERE co.programme_code = p_programme AND co.level = p_level
       AND c.semester = p_semester AND c.industrial_training AND c.state <> 'ENDED';
$$;

COMMIT;
