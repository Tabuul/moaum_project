-- ═══════════════════════════════════════
-- V458 — A postgraduate student's registrations and enrolments at their own level
--
-- V455 kept a postgraduate student at 700/800/900 and restored those the old-portal uploads had set to 100 Level. What a
-- student's level was in a session is read first from their course registration and enrolment for it (people.level_in,
-- V330), and those rows keep the level they were written at: a postgraduate student who registered (the registration
-- engine writes the student's current level) while sitting at 100 still read 100 on their results and transcript for that
-- session. (The old-portal undergraduate results import cannot write a postgraduate student's registration at all — the
-- class stream guard refuses it — so it needs no change; the postgraduate uploads keep their own tables.)
--
--   people.repair_postgraduate_session_levels(): every course registration and enrolment of a postgraduate student (at
--   700/800/900) below 700 set to the student's level, on the audit spine; run once here (none on the Railway register,
--   where no postgraduate registration sits below 700), safe to run again.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V458: a postgraduate student''s registrations and enrolments at their own level', true);

CREATE FUNCTION people.repair_postgraduate_session_levels()
RETURNS TABLE (registrations integer, enrolments integer) LANGUAGE plpgsql AS $fn$
DECLARE n_reg int; n_enr int;
BEGIN
    WITH pg AS (
        SELECT s.id, s.current_level
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
         WHERE people.is_postgraduate(s.entry_mode, p.category) AND s.current_level IN (700, 800, 900)),
    fixed AS (
        UPDATE registration.course_registration r SET level = pg.current_level
          FROM pg
         WHERE r.student_id = pg.id AND r.level < 700
        RETURNING 1)
    SELECT count(*) INTO n_reg FROM fixed;
    WITH pg AS (
        SELECT s.id, s.current_level
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
         WHERE people.is_postgraduate(s.entry_mode, p.category) AND s.current_level IN (700, 800, 900)),
    fixed AS (
        UPDATE people.enrolment e SET level = pg.current_level
          FROM pg
         WHERE e.student_id = pg.id AND e.level < 700
        RETURNING 1)
    SELECT count(*) INTO n_enr FROM fixed;
    registrations := n_reg;
    enrolments := n_enr;
    RETURN NEXT;
END $fn$;
COMMENT ON FUNCTION people.repair_postgraduate_session_levels() IS
  'V458: every course registration and enrolment of a postgraduate student (at 700/800/900) below 700 set to the student''s '
  'level. Returns how many of each. Run once by V458; safe to run again.';

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.repair_postgraduate_session_levels();
    RAISE NOTICE 'V458: % course registration(s) and % enrolment(s) of postgraduate students set to their own level', r.registrations, r.enrolments;
END $$;

COMMIT;
