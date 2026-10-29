-- V695: a spillover student's registration of the current session never makes it their final year — the University's word of
-- 29 October 2026, on a 400 Level B.Sc. Mass Communication student (entered 2019/2020, cohort 2020/2021 after V661, in spillover year 2)
-- who paid the second semester's spillover fee (₦22,350) and was then asked for ₦59,350: "spill over student who did not register for
-- first semester is been asked to pay for first semester, do this for all the affected spill over student".
--
-- V595 reads the final year as the later of the count of sessions and the first session the register shows the student at the final
-- level (a registration submitted, approved or locked, or the old portal's enrolment). A student whose earlier years are not on the
-- portal has no final-level record until they register in the current session; that registration then becomes "the first session at
-- the final level", the current session their final year, and the student is out of spillover: charged the whole session's ordinary
-- lines (the 400 Level first and second semester, ₦57,190 + ₦24,510 for a Social Sciences indigene) instead of the semester they
-- registered — ₦81,700 less the ₦22,350 paid is the ₦59,350 asked. Every spillover student with no earlier record on the portal who
-- registers falls into it. On the copy of 22 October 2026, 1,594 active students counted in spillover were read in their final year by
-- a first final-level record of 2025/2026: 211 with no record of any kind before 2025/2026, 22 whose last record before it is two or
-- more sessions back; 1,361 registered or enrolled the session before (1,336 at 300 Level in 2024/2025) — those are in their final
-- year as V595 has it, and stay so.
--
-- V695: people.academic_position_rows_of — a final-level record in the current session shows the final year only when the register
-- shows the student in the session just before it (a registration or an enrolment, policy.sessions_elapsed ≤ 1); with nothing there the
-- count of sessions decides, as before V595. A final-level record of an earlier session counts as V595 has it. Every position is
-- recomputed in one pass (as V595); the fees follow the position (finance.spill, V637): the student is charged the spillover lines of the
-- semesters they register. A student who paid more than that is shown it on the overpaid desk (PAID_ABOVE, V506/V519); nothing is
-- refunded or moved here.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V695: a spillover student''s registration of the current session never makes it their final year (the University, 29 October 2026)', true);

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
               co.effective_cohort AS override_cohort, cx.expected_completion AS override_completion, a.name AS entry_on_calendar, a.merged_into,
               -- V638: graduated by status reconciliation (outside the maximum academic period), never corrected since
               EXISTS (SELECT 1 FROM people.graduation_reconciliation gr WHERE gr.student_id = s.id AND gr.corrected_at IS NULL) AS reconciled_graduate
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
               min(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED') AND r.level >= st.final_level) AS first_final_reg,
               -- V695: the latest session before the current one with a registration (for the session just before the final year)
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED') AND r.session < cur.name) AS before_cur_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED') AND r.session < (SELECT name FROM cce)) AS before_cce_reg
          FROM registration.course_registration r JOIN st ON st.id = r.student_id LEFT JOIN cur ON true
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, bool_or(e.session = (SELECT name FROM cce)) AS cce_enr, max(e.session) AS last_enr,
               -- V595: and as the old portal's enrolment history shows it
               min(e.session) FILTER (WHERE e.level >= st.final_level) AS first_final_enr,
               -- V695: and the latest session before the current one with an enrolment
               max(e.session) FILTER (WHERE e.session < cur.name) AS before_cur_enr,
               max(e.session) FILTER (WHERE e.session < (SELECT name FROM cce)) AS before_cce_enr
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
               -- V695: a final-level record in the current session shows the final year only when the register shows the student in the
               -- session just before it; with nothing there (no history on the portal, or a gap) the count of sessions decides — a
               -- spillover student's first registration of the session never makes it their final year
               CASE WHEN least(r.first_final_reg, e.first_final_enr) = (CASE WHEN st.entry_mode = 'CCE' THEN (SELECT name FROM cce) ELSE (SELECT name FROM cur) END)
                         AND NOT coalesce(policy.sessions_elapsed(greatest(CASE WHEN st.entry_mode = 'CCE' THEN r.before_cce_reg ELSE r.before_cur_reg END,
                                                                           CASE WHEN st.entry_mode = 'CCE' THEN e.before_cce_enr ELSE e.before_cur_enr END),
                                                                  CASE WHEN st.entry_mode = 'CCE' THEN (SELECT name FROM cce) ELSE (SELECT name FROM cur) END) <= 1, false)
                    THEN NULL ELSE least(r.first_final_reg, e.first_final_enr) END AS first_final,
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
                   CASE WHEN m.status = 'GRADUATED' AND m.graduation_state IS DISTINCT FROM 'APPROVED' AND NOT m.reconciled_graduate THEN 'GRADUATED_WITHOUT_APPROVAL' END,
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
             WHEN r.rule = 'R1' AND (r.graduation_state = 'APPROVED' OR (r.reconciled_graduate AND r.status = 'GRADUATED')) AND r.status IN ('GRADUATED','ACTIVE','PROBATION') THEN 'VALIDATED'
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
    'V463/V595/V695: the academic position of the students given (every student when null) as the cohort engine computes it — the cohort, the '
    'programme''s length, the final year (the later of the count of sessions and the first session the register shows the student at the final '
    'level; a record of the current session counts only when the register shows the student in the session before it, V695), the spillover '
    'years beyond it, the level the cohort implies, the rule, the classification and the issues; one set-based pass';

-- every position recomputed on the rule in one set-based pass (as V595: people.refresh_academic_positions is quadratic for the whole
-- register); the students who move are counted first
CREATE TEMP TABLE v695_before ON COMMIT DROP AS
SELECT ap.student_id, ap.expected_completion, ap.spillover_state FROM people.academic_position ap;

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

DO $$
DECLARE n_spill int; n_final int;
BEGIN
    SELECT count(*) FILTER (WHERE coalesce(b.spillover_state, '') NOT LIKE 'SPILLOVER%' AND ap.spillover_state LIKE 'SPILLOVER%'),
           count(*) FILTER (WHERE b.spillover_state LIKE 'SPILLOVER%' AND coalesce(ap.spillover_state, '') NOT LIKE 'SPILLOVER%')
      INTO n_spill, n_final
      FROM people.academic_position ap JOIN v695_before b ON b.student_id = ap.student_id;
    RAISE NOTICE 'V695: % students back in spillover (their final year read from this session''s first record alone), % out of it', n_spill, n_final;
END $$;

COMMIT;
