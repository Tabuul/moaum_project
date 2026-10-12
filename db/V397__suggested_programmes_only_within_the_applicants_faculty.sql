-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V397 — a refused candidate is suggested programmes of their own faculty only
--
--   The eligibility engine (V266) evaluates a refused candidate against every open programme with a rule, and V281 marked
--   the best-ranked eligible ones as suggested — the candidate's own faculty first, but any faculty after it. So a candidate
--   for Architecture could be suggested Religious Studies or English in the Faculty of Arts. The Office's rule: a suggestion
--   is a programme in the faculty of the programme the candidate applied for, never another faculty's.
--
--   admissions.rank_alternatives now marks as suggested only the eligible alternatives whose faculty is the faculty of the
--   run's applied programme (eligibility_run.applied_programme_code → ref.programme.faculty_code), the best-ranked first,
--   up to the session's max_alternatives; a candidate whose applied programme has no faculty on the register is suggested
--   nothing rather than anything. Every reader of the suggestions reads eligibility_result.suggested — the Programme
--   Eligibility desk, the applicant's own page, the change-of-programme check, the JAMB template, the reconsiderations and
--   their emails, the screening desk and the unsuccessful-screening notice — so all of them follow. The engine still
--   evaluates and records every alternative, of every faculty, for the desk's full view; nothing is deleted. Current runs
--   are re-ranked here, and their alternatives count follows.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V397: suggested programmes only within the applicant''s faculty', true);

CREATE OR REPLACE FUNCTION admissions.rank_alternatives(p_run uuid, p_cap integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n integer; v_faculty text;
BEGIN
    -- V397: the faculty of the programme the candidate applied for; a suggestion is never another faculty's programme
    SELECT p.faculty_code INTO v_faculty
      FROM admissions.eligibility_run r JOIN ref.programme p ON p.code = r.applied_programme_code
     WHERE r.id = p_run;
    UPDATE admissions.eligibility_result SET suggested = false WHERE run_id = p_run AND suggested;
    WITH top AS (
        SELECT id FROM admissions.eligibility_result
         WHERE run_id = p_run AND kind = 'ALTERNATIVE' AND result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING')
           AND faculty_code = v_faculty
         ORDER BY ord, programme LIMIT greatest(1, least(5, coalesce(p_cap, 3))))
    UPDATE admissions.eligibility_result x SET suggested = true FROM top WHERE x.id = top.id;
    SELECT count(*) INTO n FROM admissions.eligibility_result WHERE run_id = p_run AND suggested;
    RETURN n;
END $function$;

COMMENT ON FUNCTION admissions.rank_alternatives(uuid, integer) IS
  'Marks a run''s suggested alternatives (V281): the best-ranked eligible programmes of the faculty the candidate applied to (V397), at most the session''s max_alternatives; returns how many. Other faculties'' programmes are evaluated and kept, never suggested.';

-- ── current runs re-ranked; the count on the run follows ──
DO $do$
DECLARE r record; n integer;
BEGIN
    PERFORM set_config('moaum.maintenance', 'on', true);
    FOR r IN SELECT x.id, coalesce(p.max_alternatives, 3) AS cap
               FROM admissions.eligibility_run x
               LEFT JOIN admissions.session_policy p ON p.session = x.session
              WHERE x.superseded_at IS NULL
    LOOP
        n := admissions.rank_alternatives(r.id, r.cap);
        UPDATE admissions.eligibility_run SET alternatives = n WHERE id = r.id AND alternatives IS DISTINCT FROM n;
    END LOOP;
    PERFORM set_config('moaum.maintenance', 'off', true);
END $do$;

COMMIT;
