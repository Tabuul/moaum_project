-- ═══════════════════════════════════════
-- V476 — A student's own progression counts as evidence for their level
--
--   V475 raised a record below the cohort engine's level by default only when the student is in spillover or the student's
--   own latest registration is at that very level; every other record waited for the office to choose it, as "sessions
--   counted only". But a student who registered last session one level below has shown the progression the engine counts:
--   Gurgur Japheth Terwase (BSU/LAW/DE/22/63751, LL.B, Direct Entry 2022/2023 at 200) registered at 400 in 2024/2025 and is
--   at 500 in 2025/2026, the programme's final year, while the record still says 400. On the live-shaped copy 78 of the
--   537 records waiting for review are such students.
--
--   people.level_correction is restated: the REGISTRATION basis also holds when the latest registration was in the session
--   just before the current one at one level below the computed level. A student whose latest registration is in the current
--   session at a lower level (a repeated year, a gap) is not taken: the engine's count is wrong for them and they stay for
--   review; so is a student who registered two levels below, or long ago. Nothing else changes — people.apply_level_corrections
--   reads the view, never lowers a level, and records each change on the cohort decision history.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V476: a student''s own progression counts as evidence for their level', true);

CREATE OR REPLACE VIEW people.level_correction AS
SELECT s.id AS student_id, s.current_level, ap.computed_level AS proposed_level,
       CASE WHEN ap.spillover_years > 0 THEN 'SPILLOVER'
            WHEN lr.level = ap.computed_level THEN 'REGISTRATION'
            WHEN lr.level + 100 = ap.computed_level AND policy.sessions_elapsed(lr.session, ap.current_session) = 1 THEN 'REGISTRATION'
            ELSE 'ARITHMETIC' END AS basis,
       ap.spillover_state, ap.spillover_years, ap.expected_completion, ap.final_level, ap.effective_cohort, ap.current_session,
       lr.session AS last_registration_session, lr.level AS last_registration_level
  FROM people.student s
  JOIN people.academic_position ap ON ap.student_id = s.id
  LEFT JOIN LATERAL (
      SELECT r.session, max(r.level) AS level FROM registration.course_registration r
       WHERE r.student_id = s.id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
       GROUP BY r.session ORDER BY r.session DESC LIMIT 1) lr ON true
 WHERE s.status IN ('ACTIVE', 'PROBATION') AND s.duplicate_of IS NULL AND s.entry_mode <> 'POSTGRADUATE'
   AND ap.computed_level IS NOT NULL AND s.current_level < ap.computed_level;
COMMENT ON VIEW people.level_correction IS
  'V475, restated by V476: every record in study below the level the cohort engine computes, with the basis — SPILLOVER (past the programme''s length: its final level), REGISTRATION (the student''s own latest registration is at that level, or was one level below in the session just before) or ARITHMETIC (the count of sessions only, for review)';

COMMIT;
