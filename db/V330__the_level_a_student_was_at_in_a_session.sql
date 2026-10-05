-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V330 — the level a student was at in a session, for the records of that session
--
--   A result statement, its verification page and the student's own results read the student's CURRENT level, so a
--   300-level student's 2023/2024 statement said "300 Level" over 100-level courses. The level that belongs on a record
--   is the level the student held in that session: the approved registration's level for that session and semester
--   (the register's own word), else the enrolment of that session, else the entry level carried forward one hundred a
--   session from the entry session, else — for a student with no history at all — the current level.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V330: the level a student was at in a session', true);

CREATE OR REPLACE FUNCTION people.level_in(p_student uuid, p_session text, p_semester int DEFAULT NULL)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT r.level FROM registration.course_registration r
          WHERE r.student_id = p_student AND r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
          ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
        (SELECT r.level FROM registration.course_registration r
          WHERE r.student_id = p_student AND r.session = p_session
          ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
        (SELECT e.level FROM people.enrolment e WHERE e.student_id = p_student AND e.session = p_session),
        (SELECT CASE WHEN es.starts_on IS NOT NULL AND cs.starts_on IS NOT NULL AND cs.starts_on >= es.starts_on
                     THEN least(600, st.entry_level + 100 * (SELECT count(*)::int FROM policy.academic_session a WHERE a.starts_on > es.starts_on AND a.starts_on <= cs.starts_on))
                END
           FROM people.student st
           LEFT JOIN policy.academic_session es ON es.name = st.entry_session
           LEFT JOIN policy.academic_session cs ON cs.name = p_session
          WHERE st.id = p_student),
        (SELECT st.current_level FROM people.student st WHERE st.id = p_student))
$$;
COMMENT ON FUNCTION people.level_in(uuid, text, int) IS 'The level a student was at in a session (V330): the registration of that session and semester, else of that session, else the enrolment, else the entry level carried forward a hundred a session, else the current level. For every record of a past session: statements, verification, transcripts.';

COMMIT;
