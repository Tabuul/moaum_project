-- ═══════════════════════════════════════
-- V667 — results released by the semester paid for
--
-- The University's word of 26 October 2026, on a student (BSU/AR/ENG/23/67165) who had paid his school fees and could see none of his
-- results: "check the conditions for this and release the student result for view", with its answer — a semester's results show once
-- the fees up to that semester are paid. Until now the student's results read one rule for the session (finance.clears(…, 'RESULTS'):
-- the Bursar's scheme, PAID_IN_FULL on the live portal) and the results page, the broadsheet and both PDFs hid every result whenever
-- the University's current session was not paid in full: on the live-shaped copy the student had paid the first semester of 2025/2026
-- (₦66,745.00) and ₦14,000.00 of the second (₦28,605.00), and his 2023/2024 and 2024/2025 results and his 2025/2026 first-semester
-- results were all withheld for the ₦14,605.00 left on the second semester — as were those of 315 of the 643 300 Level Arts students
-- who had paid the first semester alone.
--
--   · finance.results_cleared(student, session, semester): a semester's results are released where the session's own rule releases them
--     (as before: finance.clears), or else where the fees up to that semester are paid (finance.semester_cleared — stated, the cumulative
--     due paid, the semester's own fees stated), unless a balance carried from an earlier session blocks everything (the scheme's
--     arrears_block_all, as before); never where the session's fees are not stated (V361). NEVER_GATED releases them, as before.
--   · The API reads it semester by semester (the results page, the statement, the broadsheet and their PDFs); a withheld semester is
--     redacted on the server as before, and named with what is outstanding on it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V667: results released by the semester paid for', true);

CREATE OR REPLACE FUNCTION finance.results_cleared(p_student uuid, p_session text, p_semester integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    WITH rule AS (
        SELECT r.releases_at, s.arrears_block_all
          FROM policy.clearance_rule r JOIN policy.clearance_scheme s ON s.version_id = r.version_id
         WHERE r.version_id = policy.in_force('clearance', 'UNIVERSITY', current_date) AND r.purpose = 'RESULTS')
    SELECT CASE WHEN NOT finance.fee_stated(p_student, p_session) THEN false
                WHEN (SELECT releases_at FROM rule) = 'NEVER_GATED' THEN true
                -- the session's own rule, as before (it fails closed where no scheme is in force)
                WHEN finance.clears(p_student, p_session, 'RESULTS') THEN true
                -- a balance carried from an earlier session blocks everything, as before
                WHEN coalesce((SELECT arrears_block_all FROM rule), false)
                     AND (SELECT pos.has_arrears FROM finance.position(p_student, p_session) pos) THEN false
                -- the semester's own: its results show once the fees up to it are paid
                ELSE finance.semester_cleared(p_student, p_session, p_semester) END
$function$;
COMMENT ON FUNCTION finance.results_cleared(uuid, text, integer) IS
  'V667: whether a semester''s results are released to the student — where the session''s RESULTS rule releases them (finance.clears), or else where the fees up to that semester are paid (finance.semester_cleared), unless a balance carried from an earlier session blocks everything (arrears_block_all); never where the session''s fees are not stated';

COMMIT;
