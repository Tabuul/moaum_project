-- ═══════════════════════════════════════
-- V493 — Graduation follows the register: each programme's own final level, and postgraduate graduands
--
-- The graduation list took a programme's final year from a rule written into the query — 600 for C00061, 500 for a law or
-- pharmacy programme, 400 for every other — although the register states each programme's final level (ref.programme.
-- final_level, kept on Student Cohorts, read by finance.final_level) and each route's (ref.programme_route_terms: the CCE
-- route runs longer). They agree today for all 92 undergraduate programmes; a change on the register was not followed, the
-- CCE route's longer course never was, and a postgraduate student never appeared as a finalist at all.
--
--   records.final_level_of(student)       the register's final level: the CCE route's for a CCE student where the route is
--                                         configured, else the programme's (finance.final_level).
--   records.pg_finalist_basis(student, session)   RESEARCH, COURSEWORK or none, as below.
--   records.graduation_finalists(session) the session's finalists, each with the basis it is one on:
--       LEVEL       an undergraduate (or CCE) student enrolled in the session at their final level;
--       RESEARCH    a postgraduate whose research was recommended for the award or awarded within the session's dates;
--       COURSEWORK  a postgraduate on a programme without research, registered in the session, whose required courses
--                   (admissions.pg_coursework_audit) are all passed or on the registration.
--   records.student_graduation           restated: finalist by the same rules.
--
-- The audit (the API) judges a postgraduate graduand by the required coursework rather than by the undergraduate CGPA
-- threshold, and a postgraduate award is not put in an undergraduate class. Nothing is written by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V493: graduation follows the register', true);

CREATE FUNCTION records.final_level_of(p_student uuid) RETURNS integer
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN s.entry_mode = 'CCE'
                THEN coalesce((SELECT t.final_level FROM ref.programme_route_terms(s.programme_code, 'CCE') t WHERE t.configured AND t.final_level IS NOT NULL),
                              finance.final_level(s.programme_code))
                ELSE finance.final_level(s.programme_code) END
      FROM people.student s WHERE s.id = p_student
$$;
COMMENT ON FUNCTION records.final_level_of(uuid) IS
  'V493: a student''s final level as the register states it — the CCE route''s for a CCE student where configured, else the programme''s (finance.final_level).';

CREATE FUNCTION records.pg_finalist_basis(p_student uuid, p_session text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN EXISTS (SELECT 1 FROM admissions.pg_research r JOIN policy.academic_session a ON a.name = p_session
                      WHERE r.student_id = p_student AND coalesce(r.awarded_at, r.award_recommended_at) IS NOT NULL
                        AND (coalesce(r.awarded_at, r.award_recommended_at) AT TIME ZONE 'Africa/Lagos')::date BETWEEN a.starts_on AND a.ends_on)
             THEN 'RESEARCH'
        WHEN NOT coalesce(p.pg_research, false) AND s.status IN ('ACTIVE', 'PROBATION', 'GRADUATED')
             AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session)
             AND EXISTS (SELECT 1 FROM admissions.pg_coursework_audit(p_student) a)
             AND NOT EXISTS (SELECT 1 FROM admissions.pg_coursework_audit(p_student) a WHERE a.state = 'OUTSTANDING')
             THEN 'COURSEWORK' END
      FROM people.student s JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'POST GRADUATE'
     WHERE s.id = p_student
$$;
COMMENT ON FUNCTION records.pg_finalist_basis(uuid, text) IS
  'V493: why a postgraduate is a finalist in a session — RESEARCH (recommended for the award or awarded within it), COURSEWORK (a programme without research, registered in it, no required course outstanding) — or NULL.';

CREATE FUNCTION records.graduation_finalists(p_session text)
RETURNS TABLE(student_id uuid, programme_code text, programme_name text, level integer, basis text)
LANGUAGE sql STABLE AS $$
    -- the register's final level of each programme, and of the CCE route where it is configured: read once a programme
    WITH prog AS MATERIALIZED (
        SELECT p.code, p.name, p.category, finance.final_level(p.code) AS final_level,
               (SELECT t.final_level FROM ref.programme_route_terms(p.code, 'CCE') t WHERE t.configured AND t.final_level IS NOT NULL) AS cce_final
          FROM ref.programme p),
    by_level AS (
        SELECT s.id, s.programme_code, g.name, e.level, 'LEVEL'::text AS basis, s.surname, s.other_names
          FROM people.enrolment e
          JOIN people.student s ON s.id = e.student_id
          JOIN prog g ON g.code = s.programme_code
         WHERE e.session = p_session AND g.category IS DISTINCT FROM 'POST GRADUATE'
           AND e.level = CASE WHEN s.entry_mode = 'CCE' THEN coalesce(g.cce_final, g.final_level) ELSE g.final_level END),
    -- a postgraduate: only one with research decided, or registered in the session, is asked (records.pg_finalist_basis) —
    -- the candidates set apart first, so the question is never put to the whole register
    pg_cand AS MATERIALIZED (
        SELECT s.id, s.programme_code, g.name, s.current_level AS level, s.surname, s.other_names
          FROM people.student s
          JOIN prog g ON g.code = s.programme_code AND g.category = 'POST GRADUATE'
         WHERE s.id IN (SELECT r.student_id FROM admissions.pg_research r WHERE coalesce(r.awarded_at, r.award_recommended_at) IS NOT NULL
                        UNION SELECT r.student_id FROM registration.course_registration r WHERE r.session = p_session)),
    by_pg AS (
        SELECT c.id, c.programme_code, c.name, c.level, b.basis, c.surname, c.other_names
          FROM pg_cand c
          CROSS JOIN LATERAL (SELECT records.pg_finalist_basis(c.id, p_session) AS basis OFFSET 0) b
         WHERE b.basis IS NOT NULL)
    SELECT x.id, x.programme_code, x.name, x.level, x.basis
      FROM (SELECT * FROM by_level UNION ALL SELECT * FROM by_pg) x
     ORDER BY x.surname, x.other_names
$$;
COMMENT ON FUNCTION records.graduation_finalists(text) IS
  'V493: a session''s finalists — LEVEL (enrolled at the register''s final level), RESEARCH or COURSEWORK (a postgraduate, records.pg_finalist_basis).';

CREATE OR REPLACE FUNCTION records.student_graduation(p_student uuid)
 RETURNS TABLE(finalist boolean, final_level integer, session text, audited boolean, cgpa numeric, award text, unmet text, senate_state text, senate_minute text, class_of_degree text, status text, cleared boolean, units_holding integer, certificate_no text, certificate_status text, convocation text, printed_on date, collected_on date, held_reason text, verification_code text, issued_on date)
 LANGUAGE sql
 STABLE
AS $function$
    -- V493: the final level the register states for the programme (and the CCE route), not a rule written here; a
    -- postgraduate is a finalist by graduation's own rule (records.graduation_finalists), not by a level
    WITH st AS (
        SELECT s.id, s.status, s.programme_code, s.current_level, p.name AS programme_name,
               records.final_level_of(s.id) AS final_level, p.category = 'POST GRADUATE' AS pg
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.id = p_student),
    cur AS (SELECT a.name FROM policy.academic_session a WHERE a.state = 'CURRENT'),
    g AS (SELECT gg.* FROM records.graduand gg WHERE gg.student_id = p_student ORDER BY gg.session DESC LIMIT 1),
    c AS (SELECT cc.* FROM credentials.certificate cc WHERE cc.student_id = p_student AND cc.status <> 'REISSUED' ORDER BY cc.printed_on DESC LIMIT 1),
    i AS (SELECT ii.* FROM credentials.issued ii WHERE ii.student_id = p_student AND ii.kind = 'DEGREE_CERTIFICATE' ORDER BY ii.issued_on DESC LIMIT 1),
    clr AS (SELECT count(*) FILTER (WHERE cp.state <> 'CLEARED')::int AS holding FROM clearance.position(p_student, 'CONVOCATION') cp)
    SELECT st.status = 'GRADUATED' OR g.student_id IS NOT NULL
               OR (st.pg AND EXISTS (SELECT 1 FROM cur WHERE records.pg_finalist_basis(st.id, cur.name) IS NOT NULL))
               OR (NOT st.pg AND EXISTS (SELECT 1 FROM people.enrolment e, cur WHERE e.student_id = st.id AND e.session = cur.name AND e.level = st.final_level))
               OR (NOT st.pg AND st.current_level = st.final_level),
           st.final_level,
           coalesce(g.session, (SELECT name FROM cur)),
           g.student_id IS NOT NULL,
           g.cgpa, g.award, g.unmet, g.senate_state, g.senate_minute,
           CASE WHEN g.cgpa IS NULL OR st.pg THEN NULL ELSE coalesce(policy.class_of(g.cgpa), 'Pass') END,   -- V493: a postgraduate award is not classed
           st.status,
           clr.holding = 0, clr.holding,
           c.number, c.status, c.convocation, c.printed_on, c.collected_on, c.held_reason,
           i.verification_code, i.issued_on
      FROM st LEFT JOIN g ON true LEFT JOIN c ON true LEFT JOIN i ON true, clr;
$function$;
COMMENT ON FUNCTION records.student_graduation(uuid) IS
  'The student''s own graduation, computed: finalist or not, the audit, Senate, the class, the convocation clearance, the certificate, the verification code. V493: the register''s final level; a postgraduate a finalist by graduation''s own rule.';

COMMIT;
