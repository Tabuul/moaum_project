-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V595 — Spillover counted from the final year as the register shows it (the University's instruction, 20 Oct 2026)
--
--   The cohort engine (V331) counted a student's spillover years from the admission session alone: expected completion = cohort +
--   (length − 1) + deferments, spillover years = sessions elapsed beyond it. A student admitted in 2020/2021 to a four-year programme
--   was therefore in "spillover year 2 (SP2)" in 2025/2026 whatever the register showed — and the register shows thousands of them
--   at the final level for the first time in 2024/2025 (the 2020 set lost a year to the closures, others repeated a level or came over
--   with a thin record): on the live-shaped copy, 4,598 of the 5,543 students the engine called SP2 first registered at 400 Level in
--   2024/2025, and the University reads them as SP1 — the first session beyond the final year. The instruction: the student is SP1,
--   not SP2; correct every student so affected.
--   The final year is now the later of the year the count of sessions gives and the first session the register shows the student at
--   the programme's final level — a registration submitted, approved or locked, or the old portal's enrolment history (people.enrolment)
--   — and spillover years are the sessions elapsed beyond it; an approved deferment after that year still pushes the completion on;
--   nothing is counted from before the counted year (a wrong level on an early registration cannot make a spillover student).
--   A student with no registration or enrolment at the final level is counted as before. The level the cohort implies, the rules,
--   the limit, the fees by the cohort basis (V571), the lifecycle reconciliation (V558) and the level corrections (V475, V593) all
--   read the position and follow. Every position is recomputed here in one set-based pass, the rows that change rewritten (the pass itself now seconds, not minutes: the
--   intermediate steps are materialised so the session arithmetic runs once a row).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V595: spillover counted from the final year as the register shows it', true);

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
               co.effective_cohort AS override_cohort, a.name AS entry_on_calendar, a.merged_into
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN LATERAL ref.programme_route_terms(s.programme_code, 'CCE') rt ON s.entry_mode = 'CCE'
          LEFT JOIN people.cohort_override co ON co.student_id = s.id
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
        SELECT a.*,
               CASE WHEN a.first_final IS NOT NULL AND (a.counted_completion IS NULL OR policy.session_year(a.first_final) > policy.session_year(a.counted_completion))
                    THEN policy.session_after(a.first_final, coalesce((SELECT ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int
                                                                         FROM people.deferment d
                                                                        WHERE d.student_id = a.id AND d.state IN ('APPROVED','ACTIVE','COMPLETED')
                                                                          AND policy.session_year(d.session) > policy.session_year(a.first_final)), 0))
                    ELSE a.counted_completion END AS expected_completion
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
$function$
;

COMMENT ON FUNCTION people.academic_position_rows_of(uuid[]) IS
    'V463/V595: the academic position of the students given (every student when null) as the cohort engine computes it — the cohort, the '
    'programme''s length, the final year (the later of the count of sessions and the first session the register shows the student at the final '
    'level), the spillover years beyond it, the level the cohort implies, the rule, the classification and the issues; one set-based pass';

-- every position recomputed on the new rule in one set-based pass (people.refresh_academic_positions takes a batch and tests each row
-- against the whole array, which for the whole register would be quadratic); the triggers keep them from here
INSERT INTO people.academic_position AS ap
SELECT * FROM people.academic_position_rows_of(NULL)
ON CONFLICT (student_id) DO UPDATE SET
    jamb_year = EXCLUDED.jamb_year, matric_year = EXCLUDED.matric_year, entry_session = EXCLUDED.entry_session, effective_cohort = EXCLUDED.effective_cohort,
    cohort_source = EXCLUDED.cohort_source, entry_level = EXCLUDED.entry_level, programme_code = EXCLUDED.programme_code, final_level = EXCLUDED.final_level,
    duration_years = EXCLUDED.duration_years, current_session = EXCLUDED.current_session, current_level = EXCLUDED.current_level, computed_level = EXCLUDED.computed_level,
    expected_completion = EXCLUDED.expected_completion, deferred_sessions = EXCLUDED.deferred_sessions, elapsed_sessions = EXCLUDED.elapsed_sessions,
    spillover_years = EXCLUDED.spillover_years, spillover_state = EXCLUDED.spillover_state, registered_current = EXCLUDED.registered_current,
    enrolled_current = EXCLUDED.enrolled_current, last_session = EXCLUDED.last_session, graduation_state = EXCLUDED.graduation_state,
    graduation_session = EXCLUDED.graduation_session, existing_status = EXCLUDED.existing_status, classification = EXCLUDED.classification,
    proposed_status = EXCLUDED.proposed_status, rule = EXCLUDED.rule, confidence = EXCLUDED.confidence, issues = EXCLUDED.issues, computed_at = EXCLUDED.computed_at
WHERE (ap.expected_completion, ap.spillover_years, ap.spillover_state, ap.classification, ap.rule, ap.confidence, ap.issues)
      IS DISTINCT FROM (EXCLUDED.expected_completion, EXCLUDED.spillover_years, EXCLUDED.spillover_state, EXCLUDED.classification, EXCLUDED.rule, EXCLUDED.confidence, EXCLUDED.issues);

COMMIT;
