-- ═══════════════════════════════════════
-- V406 — classes opened on request, not on every structure row
--
--   V405 opened a course's class the moment a row of a programme's structure was added (a trigger on catalogue.course_offer)
--   and when an ended course was restored. That collides with every path that adds a structure row and then opens the class
--   itself under an id of its own — the property suite does it in fourteen places, and so may an upload that names its classes.
--   The opening stays, and stays explicit: catalogue.open_classes_for_courses(codes) for a named course, and the allocation
--   desk's "Open the classes" (registration.open_course_registration for the session's opened semesters), which is what the
--   desk shows against catalogue.courses_without_class. Nothing is opened unasked.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V406: classes opened on request, not on every structure row', true);

DROP TRIGGER IF EXISTS trg_course_offer_opens_classes ON catalogue.course_offer;
DROP FUNCTION IF EXISTS catalogue.classes_for_new_offers();
DROP TRIGGER IF EXISTS trg_course_restored_opens_classes ON catalogue.course;
DROP FUNCTION IF EXISTS catalogue.classes_for_restored_course();

COMMENT ON FUNCTION catalogue.open_classes_for_courses(text[]) IS
  'V405/V406: a class for each named course in every session and semester whose classes are already open, by the rule registration.open_course_registration applies; called on request (the desk, an office), never by a trigger. The number opened.';

COMMIT;
