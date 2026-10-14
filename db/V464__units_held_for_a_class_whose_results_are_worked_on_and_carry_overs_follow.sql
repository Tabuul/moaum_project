-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V464 — Units held for a class whose results are worked on; a programme's change reaching its carry-overs; what a change
--        reaches counted before it is made
--
--   · V460 let a change of units reach a registration while the student had no score of their own on the class. On the
--     live-shaped copy of 13 Oct 2026, 189 registrations of 2025/2026 sit on classes whose results are published while the
--     student has no score (absent, for one): a change would have moved their units under a published broadsheet. And a
--     change made while a sheet is half entered would have left one class at two numbers — the scored at the old, the rest
--     at the new. Now a class whose results are being worked on — a score entered on any of its sheets, or a sheet past
--     ENTRY — keeps every registration's units (catalogue.class_examined).
--   · A programme's units, set at one level, reached only the registrations made at that level. A carry-over taken at a
--     later level reads the programme's units through catalogue.units_for, but was not moved: 3,199 registrations of
--     2025/2026 on the copy are of a course the student's programme binds at another level. Now a programme's change
--     reaches all its registrations of the course, each at what units_for says for it.
--   · catalogue.units_change_impact(course, programme, level, units): before the programme's units are set, how many
--     registrations would follow and how many keep theirs (a closed session, or the class examined) — so the review's
--     report says it before anyone saves.
--   · Nothing is moved by this migration; it changes what a later change reaches.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V464: units held for a class whose results are worked on', true);

-- a class whose results are being worked on: a score entered on any of its sheets (the main sitting or a resit), or a sheet
-- that has left ENTRY on its way to publication
CREATE OR REPLACE FUNCTION catalogue.class_examined(p_offering uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM assessment.score_sheet sh
                    WHERE sh.offering_id = p_offering
                      AND (sh.stage <> 'ENTRY' OR EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = sh.id)))
$fn$;
COMMENT ON FUNCTION catalogue.class_examined(uuid) IS
  'V464: a class whose results are being worked on — a score entered on any of its sheets, or a sheet past ENTRY. A change of units leaves its registrations as they are.';

-- restated from V460: the class, not the student alone, decides
CREATE OR REPLACE FUNCTION catalogue.reflect_units(p_course text, p_programme text, p_level int)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    UPDATE registration.entry e
       SET units = catalogue.units_for(o.course_code, s.programme_code, r.level)
      FROM registration.course_registration r, people.student s, catalogue.offering o
     WHERE e.registration_id = r.id AND r.student_id = s.id AND e.offering_id = o.id
       AND o.course_code = p_course
       AND (p_programme IS NULL OR s.programme_code = p_programme)
       AND (p_level IS NULL OR r.level = p_level)
       AND e.units IS DISTINCT FROM catalogue.units_for(o.course_code, s.programme_code, r.level)
       AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state = 'CLOSED')
       AND NOT catalogue.class_examined(o.id);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION catalogue.reflect_units(text, text, int) IS
  'V460, V464: a change of units reaches the registrations of the course (of one programme, or every programme) not yet examined — in a session not closed, on a class whose results are not being worked on.';

-- restated from V460: a programme's change reaches its registrations of the course at every level, carry-overs included
CREATE OR REPLACE FUNCTION catalogue.offer_units_reflect()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.units IS NULL THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND OLD.units IS NOT DISTINCT FROM NEW.units THEN RETURN NEW; END IF;
    PERFORM catalogue.reflect_units(NEW.course_code, NEW.programme_code, NULL);
    RETURN NEW;
END $fn$;

-- what setting a programme's units for a course at a level would reach, worked out as units_for would read it afterwards:
-- the units the programme takes the course at now and after, the registrations that would follow, and those that would
-- keep units other than the new number because their session is closed or their class examined
CREATE OR REPLACE FUNCTION catalogue.units_change_impact(p_course text, p_programme text, p_level int, p_units int)
RETURNS TABLE(now_units int, new_units int, follow int, kept int)
LANGUAGE sql STABLE AS $fn$
    WITH c AS (SELECT x.units FROM catalogue.course x WHERE x.code = p_course),
    b AS (SELECT co.level,
                 CASE WHEN co.level = p_level THEN nullif(p_units, (SELECT c.units FROM c)) ELSE co.units END AS units
            FROM catalogue.course_offer co WHERE co.course_code = p_course AND co.programme_code = p_programme),
    any_own AS (SELECT b.units FROM b WHERE b.units IS NOT NULL ORDER BY b.level LIMIT 1),
    reg AS (
        SELECT e.units AS old_units,
               coalesce((SELECT b.units FROM b WHERE b.level = r.level),
                        CASE WHEN NOT EXISTS (SELECT 1 FROM b WHERE b.level = r.level) THEN (SELECT a.units FROM any_own a) END,
                        (SELECT c.units FROM c)) AS to_units,
               (EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state = 'CLOSED')
                OR catalogue.class_examined(o.id)) AS held
          FROM registration.entry e
          JOIN registration.course_registration r ON r.id = e.registration_id
          JOIN people.student s ON s.id = r.student_id
          JOIN catalogue.offering o ON o.id = e.offering_id
         WHERE o.course_code = p_course AND s.programme_code = p_programme)
    SELECT catalogue.units_for(p_course, p_programme, p_level),
           coalesce(p_units, (SELECT c.units FROM c)),
           (count(*) FILTER (WHERE NOT held AND old_units IS DISTINCT FROM to_units))::int,
           (count(*) FILTER (WHERE held AND old_units IS DISTINCT FROM to_units))::int
      FROM reg
$fn$;
COMMENT ON FUNCTION catalogue.units_change_impact(text, text, int, int) IS
  'V464: before a programme''s units for a course at a level are set — the units now and after, the registrations that would follow, and those that keep other units (closed session, or the class examined).';

COMMIT;
