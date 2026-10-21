-- ═══════════════════════════════════════
-- V612 — the expected completion pinned by the Registry: a spillover override beside the cohort override
--
--   Spillover is a classification the cohort engine derives (V331, V475, V595): expected completion = the effective cohort plus the
--   programme's length and the approved deferments, or the first session the register shows the student at the final level if that
--   is later; SP1 is the session after it, SP2 the one after that, the limit the policy's. When the record is right and the
--   University still reads a student differently — a Senate directive, a case decided on paper, a history the register does not
--   carry — the Registry had no way to say so except by moving the cohort, which is not what happened. Now, beside the cohort
--   override: people.completion_override pins the student's expected completion session on a reason; the engine reads the pin before
--   any count (the count of sessions and the final-year rule are set aside while it stands; deferments are in the pin as the
--   Registry made it), so the spillover state, the lifecycle reconciliation (V558), the level corrections (V475, V601) and every
--   screen that reads people.academic_position follow it. people.set_completion_override(student, session, reason): a person, a
--   reason, a session on the calendar that was not cancelled and not before the student's cohort; NULL removes the pin; every act a
--   row on people.cohort_decision (rule COMPLETION) and the row itself on the audit spine. The entry session, the level, the
--   status and the history are never touched. API: POST /api/v1/cohorts/students/{id}/completion (the Registry's offices, as the
--   cohort override); Student Cohorts → the student → "Pin the expected completion".
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V612: the expected completion pinned by the Registry — a spillover override beside the cohort override', true);

CREATE TABLE people.completion_override (
    student_id          uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    expected_completion text NOT NULL,
    reason              text NOT NULL,
    set_by              uuid,
    actor_office        text,
    set_at              timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE people.completion_override IS
    'V612: the expected completion session the Registry pins for a student on evidence, read by the cohort engine before any count; spillover is counted from it (SP1 the session after). The entry session, the cohort and the level are untouched; removing the pin returns the student to the counted completion';
SELECT audit.attach('people.completion_override');
CREATE TRIGGER trg_position_completion AFTER INSERT OR UPDATE ON people.completion_override FOR EACH ROW EXECUTE FUNCTION people.position_touch();
GRANT SELECT ON people.completion_override TO app_auditor, app_acrecords, app_reporting;

CREATE OR REPLACE FUNCTION people.set_completion_override(p_student uuid, p_session text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; v_cohort text; v_before text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an expected completion is pinned by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'COMPLETION_REASON: a pinned expected completion says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found'; END IF;
    SELECT effective_cohort, expected_completion INTO v_cohort, v_before FROM people.academic_position WHERE student_id = p_student;
    IF p_session IS NULL THEN
        DELETE FROM people.completion_override WHERE student_id = p_student;
        IF NOT FOUND THEN RAISE EXCEPTION 'COMPLETION_NOT_PINNED: no pinned expected completion stands for this student' USING ERRCODE = '23514'; END IF;
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office)
        VALUES (p_student, s.status, s.status, v_cohort, v_cohort, 'COMPLETION', 'Pinned expected completion removed (was ' || coalesce(v_before, '—') || '): ' || btrim(p_reason), who, office);
        PERFORM people.refresh_academic_position(p_student);
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session AND state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'COMPLETION_SESSION: % is not a session in force', p_session USING ERRCODE = '23514',
            HINT = 'An expected completion is a session on the calendar that was not cancelled.';
    END IF;
    IF v_cohort IS NOT NULL AND policy.session_year(p_session) < policy.session_year(v_cohort) THEN
        RAISE EXCEPTION 'COMPLETION_BEFORE_COHORT: % is before the student''s cohort %', p_session, v_cohort USING ERRCODE = '23514',
            HINT = 'A programme is not completed before it is begun; correct the cohort first where the cohort is wrong.';
    END IF;
    INSERT INTO people.completion_override (student_id, expected_completion, reason, set_by, actor_office)
    VALUES (p_student, p_session, btrim(p_reason), who, office)
    ON CONFLICT (student_id) DO UPDATE SET expected_completion = EXCLUDED.expected_completion, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by, actor_office = EXCLUDED.actor_office, set_at = now();
    INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office)
    VALUES (p_student, s.status, s.status, v_cohort, v_cohort, 'COMPLETION', 'Expected completion pinned to ' || p_session || ' (was ' || coalesce(v_before, '—') || '): ' || btrim(p_reason), who, office);
END $function$;
COMMENT ON FUNCTION people.set_completion_override(uuid, text, text) IS
    'V612: the Registry pins (or, with NULL, unpins) a student''s expected completion session on a reason; the cohort engine reads the pin before any count and the position is refreshed at once; each act is a COMPLETION row on people.cohort_decision';

-- the engine, restated from its definition with the pin read before the count (V595's materialised steps kept)
CREATE OR REPLACE FUNCTION people.academic_position_rows_of(p_students uuid[])
 RETURNS SETOF people.academic_position
 LANGUAGE sql
 STABLE
AS $function$
    WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1),
    -- V381: a CCE student stands in the CCE session, for the CCE duration of the programme (six years unless stated)
    cce AS (SELECT policy.route_session('CCE') AS name),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting),
    st AS (
        SELECT s.id, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.programme_code, s.current_level, s.status, s.candidate_id, s.entry_mode,
               s.duplicate_of IS NOT NULL AS ended_duplicate,
               c.session AS candidate_session,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE p.final_level END AS configured_final,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.duration_years ELSE p.duration_years END AS configured_years,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE finance.final_level(s.programme_code) END AS final_level,
               co.effective_cohort AS override_cohort, cx.expected_completion AS override_completion, a.name AS entry_on_calendar, a.merged_into
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN LATERAL ref.programme_route_terms(s.programme_code, 'CCE') rt ON s.entry_mode = 'CCE'
          LEFT JOIN people.cohort_override co ON co.student_id = s.id
          LEFT JOIN people.completion_override cx ON cx.student_id = s.id
          LEFT JOIN policy.academic_session a ON a.name = s.entry_session
         WHERE p_students IS NULL OR s.id = ANY (p_students)),
    dups AS (SELECT matric_no FROM people.student WHERE matric_no IS NOT NULL GROUP BY matric_no HAVING count(*) > 1),
    defs AS (
        SELECT d.student_id,
               ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int AS sessions,
               bool_or(d.state = 'ACTIVE') AS live
          FROM people.deferment d
         WHERE d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (p_students IS NULL OR d.student_id = ANY (p_students))
         GROUP BY d.student_id),
    reg AS (
        SELECT r.student_id,
               bool_or(r.session = cur.name AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cur_reg,
               bool_or(r.session = (SELECT name FROM cce) AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cce_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS last_reg,
               -- V595: the final year as the register shows it — the first session registered at the programme's final level
               min(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED') AND r.level >= st.final_level) AS first_final_reg
          FROM registration.course_registration r JOIN st ON st.id = r.student_id LEFT JOIN cur ON true
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, bool_or(e.session = (SELECT name FROM cce)) AS cce_enr, max(e.session) AS last_enr,
               -- V595: and as the old portal's enrolment history shows it
               min(e.session) FILTER (WHERE e.level >= st.final_level) AS first_final_enr
          FROM people.enrolment e JOIN st ON st.id = e.student_id LEFT JOIN cur ON true
         GROUP BY e.student_id),
    grad AS (
        SELECT DISTINCT ON (g.student_id) g.student_id, g.session, g.senate_state, g.unmet
          FROM records.graduand g
         WHERE p_students IS NULL OR g.student_id = ANY (p_students)
         ORDER BY g.student_id, (g.senate_state = 'APPROVED') DESC, g.session DESC),
    base AS (
        SELECT st.*,
               coalesce(policy.session_year(st.candidate_session),
                        CASE WHEN st.jamb_reg_no ~ '^20[0-9]{2}[0-9]{8}[A-Z]{2}$' THEN left(st.jamb_reg_no, 4)::int END,
                        policy.session_year(st.entry_session)) AS jamb_year,
               CASE WHEN st.matric_no ~ '/[0-9]{2}/' THEN 2000 + (regexp_match(st.matric_no, '/([0-9]{2})/'))[1]::int END AS matric_year,
               coalesce(st.override_cohort, policy.effective_session(st.entry_session)) AS effective_cohort,
               CASE WHEN st.override_cohort IS NOT NULL THEN 'OVERRIDE' WHEN st.merged_into IS NOT NULL THEN 'MERGED' ELSE 'ENTRY' END AS cohort_source,
               coalesce(st.configured_years, CASE WHEN st.configured_final IS NOT NULL THEN greatest((st.configured_final - coalesce(st.entry_level, 100)) / 100 + 1, 1) END) AS duration_years,
               st.configured_final IS NOT NULL AS level_based,
               coalesce(d.sessions, 0) AS deferred_sessions, coalesce(d.live, false) AS live_deferment,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN r.cce_reg ELSE r.cur_reg END, false) AS registered_current, greatest(r.last_reg, e.last_enr) AS last_session,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN e.cce_enr ELSE e.cur_enr END, false) AS enrolled_current,
               least(r.first_final_reg, e.first_final_enr) AS first_final,
               g.senate_state AS graduation_state, g.session AS graduation_session, g.unmet AS graduation_unmet, g.student_id IS NOT NULL AS has_graduand,
               st.matric_no IN (SELECT matric_no FROM dups) AS dup_matric,
               CASE WHEN st.entry_mode = 'CCE' THEN (SELECT name FROM cce) ELSE (SELECT name FROM cur) END AS current_session, (SELECT max_spillover_years FROM cfg) AS max_spill
          FROM st LEFT JOIN defs d ON d.student_id = st.id LEFT JOIN reg r ON r.student_id = st.id
               LEFT JOIN enr e ON e.student_id = st.id LEFT JOIN grad g ON g.student_id = st.id),
    -- V595: these three are materialised so the session arithmetic (policy.session_after, policy.sessions_elapsed) runs once a row —
    -- inlined, every later reference to expected_completion and spillover_years (the rule, the issues, the classification, the
    -- confidence) evaluated it again, and a pass over the whole register took ten minutes instead of seconds
    arith AS MATERIALIZED (
        SELECT b.*,
               CASE WHEN b.duration_years IS NOT NULL THEN policy.session_after(b.effective_cohort, b.duration_years - 1 + b.deferred_sessions) END AS counted_completion,
               policy.sessions_elapsed(b.effective_cohort, b.current_session) AS elapsed_sessions
          FROM base b),
    timed AS MATERIALIZED (
        -- V595: the final year is the later of the one the count of sessions gives and the first session the register (a registration,
        -- or the old portal's enrolment) shows the student at the final level — a session repeated or lost before the final level is not
        -- a spillover year; a deferment after that year still pushes the completion on; nothing is counted from before the counted year
        -- V612: an expected completion the Registry pinned on evidence is read before any count — the count of sessions and the
        -- final-year rule are set aside while it stands; deferments are in the pin as the Registry made it
        SELECT a.*,
               coalesce(a.override_completion,
               CASE WHEN a.first_final IS NOT NULL AND (a.counted_completion IS NULL OR policy.session_year(a.first_final) > policy.session_year(a.counted_completion))
                    THEN policy.session_after(a.first_final, coalesce((SELECT ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int
                                                                         FROM people.deferment d
                                                                        WHERE d.student_id = a.id AND d.state IN ('APPROVED','ACTIVE','COMPLETED')
                                                                          AND policy.session_year(d.session) > policy.session_year(a.first_final)), 0))
                    ELSE a.counted_completion END) AS expected_completion
          FROM arith a),
    measured AS MATERIALIZED (
        SELECT t.*,
               greatest(0, coalesce(policy.sessions_elapsed(t.expected_completion, t.current_session), 0)) AS spillover_years,
               CASE WHEN t.elapsed_sessions IS NULL THEN NULL
                    WHEN NOT t.level_based THEN coalesce(t.entry_level, t.current_level)
                    ELSE least(t.configured_final, coalesce(t.entry_level, 100) + 100 * greatest(0, t.elapsed_sessions - t.deferred_sessions)) END AS computed_level
          FROM timed t),
    ruled AS (
        SELECT m.*,
               CASE
                 WHEN m.graduation_state = 'APPROVED' OR m.status = 'GRADUATED' THEN 'R1'
                 WHEN m.status IN ('WITHDRAWN','VOLUNTARY_WITHDRAWAL','EXPELLED','DECEASED','TRANSFERRED_OUT','RUSTICATED','SUSPENDED','DORMANT','DEFERRED','ADMITTED') THEN 'R2'
                 WHEN m.entry_session IS NULL OR policy.session_year(m.effective_cohort) IS NULL OR m.duration_years IS NULL OR m.current_session IS NULL THEN 'R6'
                 WHEN m.has_graduand AND m.graduation_unmet IS NULL AND m.graduation_state <> 'APPROVED' THEN 'R5'
                 WHEN m.spillover_years > m.max_spill THEN 'R4L'
                 WHEN m.spillover_years > 0 THEN 'R4'
                 WHEN m.registered_current OR m.enrolled_current THEN 'R3'
                 WHEN m.last_session IS NULL THEN 'R6'
                 ELSE 'R3L' END AS rule,
               array_remove(ARRAY[
                   CASE WHEN m.entry_session IS NULL THEN 'MISSING_ENTRY_SESSION' END,
                   CASE WHEN m.entry_session IS NOT NULL AND policy.session_year(m.entry_session) IS NULL THEN 'ENTRY_SESSION_INVALID' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.elapsed_sessions < 0 THEN 'ENTRY_SESSION_AHEAD' END,
                   CASE WHEN m.matric_no IS NULL AND m.status <> 'ADMITTED' AND NOT m.ended_duplicate THEN 'MISSING_MATRIC' END,
                   CASE WHEN m.jamb_reg_no IS NULL THEN 'MISSING_JAMB' END,
                   CASE WHEN m.duration_years IS NULL THEN 'DURATION_NOT_CONFIGURED' END,
                   CASE WHEN m.dup_matric THEN 'DUPLICATE_MATRIC' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.computed_level IS NOT NULL AND m.computed_level <> m.current_level THEN 'LEVEL_CONFLICT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND NOT m.registered_current AND NOT m.enrolled_current THEN 'NO_CURRENT_REGISTRATION' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.last_session IS NULL THEN 'NO_REGISTRATION_HISTORY' END,
                   CASE WHEN m.status = 'GRADUATED' AND m.graduation_state IS DISTINCT FROM 'APPROVED' THEN 'GRADUATED_WITHOUT_APPROVAL' END,
                   CASE WHEN m.status <> 'GRADUATED' AND m.graduation_state = 'APPROVED' THEN 'APPROVED_NOT_GRADUATED' END,
                   CASE WHEN m.status = 'DEFERRED' AND NOT m.live_deferment THEN 'DEFERRED_WITHOUT_LIVE_DEFERMENT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > m.max_spill THEN 'SPILLOVER_LIMIT_REACHED' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > 0 THEN 'BEYOND_PROGRAMME_LENGTH' END
               ]::text[], NULL) AS issues
          FROM measured m)
    SELECT r.id,
           r.jamb_year, r.matric_year, r.entry_session, r.effective_cohort, r.cohort_source, r.entry_level, r.programme_code, r.final_level, r.duration_years,
           r.current_session, r.current_level, r.computed_level, r.expected_completion, r.deferred_sessions, r.elapsed_sessions, r.spillover_years,
           CASE WHEN r.status NOT IN ('ACTIVE','PROBATION') THEN 'NOT_APPLICABLE'
                WHEN r.spillover_years = 0 THEN 'NORMAL'
                WHEN r.spillover_years > r.max_spill THEN 'SPILLOVER_LIMIT_REACHED'
                ELSE 'SPILLOVER_YEAR_' || least(r.spillover_years, 3) END,
           r.registered_current, r.enrolled_current, r.last_session, r.graduation_state, r.graduation_session,
           r.status,
           CASE r.rule
             WHEN 'R1'  THEN 'GRADUATED'
             WHEN 'R2'  THEN r.status
             WHEN 'R5'  THEN 'GRADUATION_ELIGIBLE'
             WHEN 'R4L' THEN 'SPILLOVER_LIMIT_REACHED'
             WHEN 'R4'  THEN 'SPILLOVER'
             WHEN 'R3'  THEN 'ACTIVE'
             WHEN 'R3L' THEN 'ACTIVE'
             ELSE 'REQUIRES_REVIEW' END,
           CASE r.rule WHEN 'R1' THEN 'GRADUATED' WHEN 'R3' THEN CASE WHEN r.status IN ('ACTIVE','PROBATION') THEN r.status ELSE 'ACTIVE' END
                       WHEN 'R3L' THEN r.status WHEN 'R4' THEN r.status WHEN 'R5' THEN r.status ELSE r.status END,
           r.rule,
           CASE
             WHEN r.rule = 'R1' AND r.graduation_state = 'APPROVED' AND r.status IN ('GRADUATED','ACTIVE','PROBATION') THEN 'VALIDATED'
             WHEN r.rule = 'R1' THEN 'REVIEW'
             WHEN r.rule = 'R2' AND NOT (r.status = 'DEFERRED' AND NOT r.live_deferment) THEN 'VALIDATED'
             WHEN r.rule IN ('R6', 'R4L') THEN 'REVIEW'
             WHEN r.dup_matric OR (r.status IN ('ACTIVE','PROBATION') AND r.computed_level IS NOT NULL AND r.computed_level <> r.current_level AND r.spillover_years = 0) THEN 'REVIEW'
             WHEN r.rule IN ('R3', 'R5') THEN 'VALIDATED'
             WHEN r.rule = 'R4' AND (r.registered_current OR r.enrolled_current) THEN 'VALIDATED'
             ELSE 'LIKELY' END,
           r.issues,
           now()
      FROM ruled r
$function$;

COMMENT ON FUNCTION people.academic_position_rows_of(uuid[]) IS
    'V331, V463, V475, V595, V612: a student''s derived academic position — cohort, expected completion (the Registry''s pin first, else the later of the count of sessions and the first final-level record, with deferments), spillover, level, rule, confidence, issues — for the students named, or every student when NULL';

COMMIT;
