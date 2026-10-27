-- ═══════════════════════════════════════
-- V673 — The current session's course registrations below the level on the student's record raised to it
--
-- The University's word of 27 October 2026 after V672 ("correct those 35 registrations"): V672 made a receipt of the session the
-- student is in now print no level below the record's, and stopped the old portal's registration and results upload registering
-- a student below it; it changed nothing on record. The registrations the upload had made at a course's level stood — on the
-- live-shaped copy of 21 October 2026, 35 students' 2025/2026 registrations below the level their record holds — and the
-- examination card and the GST & EPS permit print the registration's level, so those students' cards still read the lower level.
--
-- Now:
--   1. people.record_level_in (V672) restated: the record's level stands for the session the student is in now unless the record
--      reached it by a progression made in that session (people.cohort_decision LEVEL_PROGRESS): V641 leaves the session's
--      registration as it was on a progression — the student was at the earlier level for the session — and the receipt now
--      agrees with it.
--   2. people.raise_registrations_to_record(): every course registration of an undergraduate's current session (the University's,
--      or the Centre's for a CCE student) below the level people.record_level_in gives is raised to it through V641's
--      people.carry_level_to_session — the session's enrolment at the same level with it. A registration above the record stands
--      (10,441 active records entered before 2024/2025 still hold 100 Level on the copy); an earlier session, a postgraduate, a
--      student already enrolled in a later session and a level reached by a progression this session are left as they are. The
--      courses, units, statuses and results are untouched. Returns the students, registrations and enrolments raised. Run once
--      now; safe to run again.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V673: the current session''s course registrations below the level on record raised to it', true);

-- ── 1. the record's level, unless a progression this session reached it ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.record_level_in(p_student uuid, p_session text)
RETURNS integer
LANGUAGE sql STABLE AS $fn$
    SELECT s.current_level
      FROM people.student s
     WHERE s.id = p_student
       AND p_session = coalesce(people.student_current_session(s.id), policy.university_current_session())
       AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session > p_session)
       -- V673: a progression made this session leaves the session at the level before it (V641)
       AND NOT EXISTS (SELECT 1 FROM people.cohort_decision d
                        WHERE d.student_id = s.id AND d.rule = 'LEVEL_PROGRESS' AND d.session = p_session AND d.new_level = s.current_level)
$fn$;
COMMENT ON FUNCTION people.record_level_in(uuid, text) IS
  'V672/V673: the level the student''s record holds, when the session is the one the student is in now (people.student_current_session, '
  'else policy.university_current_session), no later session is enrolled and no progression made in the session reached it; NULL '
  'otherwise. The least a document or an upload of the current session gives the student, whatever level an uploaded registration or '
  'a course carries.';

-- ── 2. the put-right ────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.raise_registrations_to_record()
RETURNS TABLE(students integer, registrations integer, enrolments integer)
LANGUAGE plpgsql AS $fn$
DECLARE t record; c jsonb; v_ids uuid[] := '{}'; n_reg int := 0; n_enr int := 0;
BEGIN
    FOR t IN
        SELECT DISTINCT x.student_id, x.session, x.level AS from_level, x.to_level
          FROM (SELECT r.student_id, r.session, r.level, people.record_level_in(r.student_id, r.session) AS to_level
                  FROM registration.course_registration r
                 WHERE r.session IN (policy.university_current_session(), policy.route_session('CCE'))
                   AND people.student_stream(r.student_id) <> 'PG') x
         WHERE x.to_level > x.level
         ORDER BY x.student_id, x.level
    LOOP
        c := people.carry_level_to_session(t.student_id, t.from_level, t.to_level, t.session);
        IF (c->>'registrations')::int + (c->>'enrolment')::int > 0 THEN
            n_reg := n_reg + (c->>'registrations')::int;
            n_enr := n_enr + (c->>'enrolment')::int;
            IF NOT t.student_id = ANY (v_ids) THEN v_ids := v_ids || t.student_id; END IF;
        END IF;
    END LOOP;
    students := coalesce(array_length(v_ids, 1), 0);
    registrations := n_reg;
    enrolments := n_enr;
    RETURN NEXT;
END $fn$;
COMMENT ON FUNCTION people.raise_registrations_to_record() IS
  'V673: every course registration of an undergraduate''s current session below the level people.record_level_in gives raised to it '
  '(people.carry_level_to_session, the session''s enrolment at the same level with it); a registration above the record, an earlier '
  'session, a postgraduate, a later session enrolled and a progression made this session left as they are; courses, units, statuses '
  'and results untouched. Returns the students, registrations and enrolments raised. Run once by V673; safe to run again.';

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.raise_registrations_to_record();
    RAISE NOTICE 'V673: % student(s): % course registration(s) and % enrolment(s) raised to the level on record',
        r.students, r.registrations, r.enrolments;
END $$;

COMMIT;
