-- ═══════════════════════════════════════
-- V515 — The examination cards withheld worked out in one pass
--
-- registration.exam_cards_withheld (V505) asked the Bursary's clearance one student at a time (finance.clears_or_null) for every
-- approved registration: 14 to 19 seconds for 2025/2026 on the live-shaped copy (4,196 students). Each call is cheap at first,
-- but after some 3,000 calls in a session PostgreSQL's cached plan for the per-student fee functions settles on one five times
-- slower, so a large session costs more than the sum of its students. The University's fee positions are already worked out
-- for a whole session at once (finance.session_fee_positions, V308; 1.2 s for 54,573 students), and finance.session_clears
-- turns them into the clearance with the rule of finance.clears (V494).
--   · finance.session_clears_for(session, purpose, students) — V494's body, for the students named (all when none are), so the
--     list asks finance.fee_stated only of its own students with nothing due; finance.session_clears is that, for everyone.
--   · registration.exam_cards_withheld reads the clearance from it, once for the session's approved students; with no clearance
--     scheme in force the clearance is unknown (as finance.clears_or_null says it) and no card is withheld for it.
-- The answers are the card's own: on the live-shaped copy the one-pass clearance agreed with finance.clears_or_null for every
-- one of the 4,196 students. Nothing is written by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V515: the examination cards withheld worked out in one pass', true);

CREATE FUNCTION finance.session_clears_for(p_session text, p_purpose text, p_students uuid[])
 RETURNS TABLE(student_id uuid, clears boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_version uuid; v_at text; v_arrears boolean;
BEGIN
    -- the same refusals as policy.clears, from policy.clears itself: no scheme in force, no rule for the purpose
    PERFORM policy.clears(p_purpose, 0, false, false, current_date, 'UNIVERSITY');
    v_version := policy.in_force('clearance', 'UNIVERSITY', current_date);
    SELECT r.releases_at, s.arrears_block_all INTO v_at, v_arrears
      FROM policy.clearance_rule r JOIN policy.clearance_scheme s ON s.version_id = r.version_id
     WHERE r.version_id = v_version AND r.purpose = p_purpose;

    RETURN QUERY
    SELECT p.student_id,
           -- V494: as finance.clears — a student with no fee stated for the session is not cleared (V361), however nothing is due
           CASE WHEN p.due <= 0 AND NOT finance.fee_stated(p.student_id, p_session) THEN false
                WHEN v_at = 'NEVER_GATED' THEN true
                WHEN v_arrears AND p.has_arrears THEN false
                ELSE CASE v_at WHEN 'INSTALMENT_1' THEN p.instalments_paid >= 1
                               WHEN 'INSTALMENT_2' THEN p.instalments_paid >= 2
                               WHEN 'PAID_IN_FULL' THEN p.paid_in_full END END
      FROM finance.session_fee_positions(p_session) p
     WHERE p_students IS NULL OR p.student_id = ANY (p_students);
END $function$;
COMMENT ON FUNCTION finance.session_clears_for(text, text, uuid[]) IS
  'V515: the clearance for a purpose in a session of the students named (everyone when none are), read at once from the session''s fee positions with the rule of finance.clears (V494); refuses as policy.clears does when no scheme or rule is in force';

CREATE OR REPLACE FUNCTION finance.session_clears(p_session text, p_purpose text)
 RETURNS TABLE(student_id uuid, clears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT * FROM finance.session_clears_for(p_session, p_purpose, NULL)
$function$;
COMMENT ON FUNCTION finance.session_clears(text, text) IS
  'Every student''s clearance for a purpose in a session, read at once from the session''s fee positions; V494: a student with no fee stated is not cleared, as finance.clears; V515: finance.session_clears_for for everyone.';

-- the clearance of the students named, or unknown for all of them when no scheme is in force (as finance.clears_or_null says it)
CREATE FUNCTION finance.session_clears_or_null(p_session text, p_purpose text, p_students uuid[])
 RETURNS TABLE(student_id uuid, clears boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM finance.session_clears_for(p_session, p_purpose, p_students);
EXCEPTION WHEN check_violation THEN
    RETURN QUERY SELECT x, NULL::boolean FROM unnest(p_students) x;
END $function$;

CREATE OR REPLACE FUNCTION registration.exam_cards_withheld(p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, faculty_code text,
              level integer, semester integer, code text, reason text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH r AS MATERIALIZED (
        SELECT g.id, g.student_id, g.level, g.semester, s.status AS student_status, s.entry_mode, s.programme_code,
               upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, s.matric_no
          FROM registration.course_registration g JOIN people.student s ON s.id = g.student_id
         WHERE g.session = p_session AND (p_semester IS NULL OR g.semester = p_semester) AND g.status IN ('APPROVED', 'LOCKED')),
    n AS MATERIALIZED (
        SELECT e.registration_id, count(*) AS courses FROM registration.entry e
         WHERE e.registration_id IN (SELECT id FROM r) AND e.status NOT IN ('DROPPED', 'WITHDRAWN') GROUP BY 1),
    -- V515: the Bursary's answer as the card reads it, for every student with an approved registration in one pass
    cl AS MATERIALIZED (
        SELECT c.student_id, c.clears
          FROM finance.session_clears_or_null(p_session, 'EXAMINATION', ARRAY(SELECT DISTINCT r.student_id FROM r)) c),
    -- the card released for a semester and stream: on approval where the semester's rule offers it, or with the cards
    rel AS MATERIALIZED (
        SELECT sm.sem, st.stream,
               coalesce((registration.approval_rule(p_session, sm.sem)).card_on_approval, true)
               OR EXISTS (SELECT 1 FROM assessment.exam_session x WHERE x.session = p_session AND x.semester = sm.sem AND x.state <> 'DRAFT'
                             AND x.cards_released_at IS NOT NULL AND x.stream = st.stream) AS released
          FROM (SELECT DISTINCT r.semester AS sem FROM r) sm CROSS JOIN (VALUES ('REGULAR'), ('CCE'), ('PG')) st(stream)),
    j AS (
        SELECT r.*, coalesce(n.courses, 0) AS courses, cl.clears, rel.released
          FROM r LEFT JOIN n ON n.registration_id = r.id LEFT JOIN cl ON cl.student_id = r.student_id
          LEFT JOIN rel ON rel.sem = r.semester
                       AND rel.stream = CASE r.entry_mode WHEN 'CCE' THEN 'CCE' WHEN 'POSTGRADUATE' THEN 'PG' ELSE 'REGULAR' END),
    k AS (
        SELECT j.*,
               CASE WHEN j.student_status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'EXAM_CARD_NOT_IN_STUDY'
                    WHEN j.courses = 0 THEN 'EXAM_CARD_NO_COURSES'
                    WHEN j.clears IS FALSE THEN 'EXAM_CARD_NOT_CLEARED'
                    WHEN NOT coalesce(j.released, true) THEN 'EXAM_CARD_NOT_RELEASED' END AS code
          FROM j)
    SELECT k.id, k.student_id, k.full_name, k.matric_no, p.name, p.dept_code, coalesce(d.faculty_code, p.faculty_code), k.level, k.semester, k.code,
           CASE k.code WHEN 'EXAM_CARD_NOT_IN_STUDY' THEN 'The student record is ' || lower(replace(k.student_status, '_', ' '))
                       WHEN 'EXAM_CARD_NO_COURSES' THEN 'The registration carries no course'
                       WHEN 'EXAM_CARD_NOT_CLEARED' THEN 'Not cleared by the Bursary for the examination'
                       ELSE 'Cards are released with the examination timetable' END
      FROM k
      LEFT JOIN ref.programme p ON p.code = k.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
     WHERE k.code IS NOT NULL;
END $$;
COMMENT ON FUNCTION registration.exam_cards_withheld(text, integer) IS
  'V505/V515: every approved registration of a session (and semester) whose examination card the card''s rule (registration.exam_card_state) refuses, with its code and words — not in study, no course, the Bursary''s clearance refused (finance.session_clears_or_null, the session''s approved students in one pass), not released';

COMMIT;
