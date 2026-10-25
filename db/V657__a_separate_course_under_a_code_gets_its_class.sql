-- ═══════════════════════════════════════
-- V657 — a separate course under a code gets its class
--
-- The word of 25 October 2026 ("why are they showing No class yet"): on a programme's structure LIN 402 Syntactic Theories read
-- "Class open" and LIN 402 BMAS Stylistics II, the separate course the BMAS structure upload made under the same code (V646),
-- read "No class yet" — so it could not be allocated or timetabled. A course uploaded while a semester's classes are open gets its
-- class by the upload's own act (V405/V406), but the upload asked for the classes of the codes as the sheet wrote them, resolved:
-- "LIN 402" is the course first held under the code, which had its class; the separate course the same row made or chose
-- (LIN 402 BMAS, or the one a "same course" row named) was never asked for. Now:
--   · catalogue.open_classes_for_upload(programme, codes): the classes of the courses the programme binds under the codes the sheet
--     named — every course whose code shown (catalogue.shown_code) is one of them, the separate ones with the first — and of the
--     courses the codes resolve to, by catalogue.open_classes_for_courses (the semesters already open, the structure's rule); the
--     upload calls it.
--   · catalogue.open_classes_for_separate_courses(): the same for every separate course under a code that a structure binds; run
--     once here for those already made (by the upload, Department courses or "Separate"), and by hand when needed.
-- Nothing else changes: a course of a semester whose registration has not opened still waits for it; V655 opens a class when a
-- student adds a course that has none.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V657: a separate course under a code gets its class', true);

CREATE FUNCTION catalogue.open_classes_for_upload(p_programme text, p_codes text[])
RETURNS integer LANGUAGE sql AS $$
    WITH named AS (
        SELECT DISTINCT coalesce(catalogue.resolve_course_code(x), regexp_replace(upper(btrim(x)), '\s+', ' ', 'g')) AS code
          FROM unnest(coalesce(p_codes, '{}'::text[])) x
         WHERE nullif(btrim(x), '') IS NOT NULL),
    courses AS (
        SELECT n.code FROM named n JOIN catalogue.course c ON c.code = n.code
        UNION
        SELECT co.course_code
          FROM catalogue.course_offer co
         WHERE co.programme_code = upper(btrim(p_programme))
           AND catalogue.shown_code(co.course_code) IN (SELECT catalogue.shown_code(n.code) FROM named n))
    SELECT catalogue.open_classes_for_courses(ARRAY(SELECT code FROM courses))
$$;
COMMENT ON FUNCTION catalogue.open_classes_for_upload(text, text[]) IS
  'V657: the classes a structure upload asks for — the courses the programme binds under the codes the sheet named (a separate course under a code with the first, catalogue.shown_code) and the courses the codes resolve to — opened by catalogue.open_classes_for_courses in the semesters already open. Returns the classes opened.';

CREATE FUNCTION catalogue.open_classes_for_separate_courses()
RETURNS integer LANGUAGE sql AS $$
    SELECT catalogue.open_classes_for_courses(ARRAY(
        SELECT c.code FROM catalogue.course c
         WHERE catalogue.code_variant(c.code) IS NOT NULL
           AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)))
$$;
COMMENT ON FUNCTION catalogue.open_classes_for_separate_courses() IS
  'V657: the classes of every separate course under a code (CSC 401 BMAS, CSC 401 V2) that a programme''s structure binds, in the semesters already open, by catalogue.open_classes_for_courses. Returns the classes opened.';

-- the separate courses made before: their classes in the semesters already open
DO $$
DECLARE n int;
BEGIN
    n := catalogue.open_classes_for_separate_courses();
    RAISE NOTICE 'V657: % class(es) opened for separate courses under a code', n;
END $$;

COMMIT;
