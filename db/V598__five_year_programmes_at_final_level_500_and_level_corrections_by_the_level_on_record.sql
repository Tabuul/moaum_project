-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V598 — Five-year programmes at final level 500, and level corrections by the level on record
--
--   A programme's length is its final level (ref.programme.final_level, V331): every level list, the next level, the session
--   rollover, the cohort engine's expected completion and spillover, and the graduation candidates read it. At V331 the lengths
--   were seeded from the rule then in force — four years unless Law, Pharmacy or Medicine — and six programmes the University
--   runs over five years kept 400: Nursing (C35147), Urban and Regional Planning (C30468), Radiography and Radiation Science
--   (C49411), Medical Laboratory Science (C49412), Architecture (C51900) and Environmental Management and Toxicology (C52395).
--   Their students at 500 stood above the programme's last level, and a 400-level student in the fifth session was read as in
--   spillover. On the Academic Office's word (21 October 2026) they end at 500, set in one statement so the cohort engine
--   recomputes every position once (policy.position_recompute_all); the levels a student may be progressed or corrected to, the
--   rollover and the spillover follow (100 → … → 500, then SP1, SP2). The Bursary states the 500-level fee lines where missing
--   (Student Cohorts → Level corrections → fee lines missing at the corrected level, V584).
--
--   Level corrections may also be found by the level on record (p_from_level: "at 400, should be at 500").
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V598: five-year programmes at final level 500 (the Academic Office, 21 October 2026)', true);

-- ── 1 · the six programmes' length, in one statement (one recomputation of the positions) ──────────────────────────────
UPDATE ref.programme
   SET final_level = 500,
       final_level_note = 'V598: five years, as the University runs the programme (the Academic Office, 21 October 2026); was 400 from the rule seeded at V331'
 WHERE code IN ('C35147', 'C30468', 'C49411', 'C49412', 'C51900', 'C52395')
   AND final_level IS DISTINCT FROM 500;

-- ── 2 · level corrections by the level on record ────────────────────────────────────────────────────────────────────────
DROP FUNCTION people.apply_level_corrections(uuid[], text[], text, text, text, text, text, integer, boolean, integer, text, text);

CREATE FUNCTION people.apply_level_corrections(p_students uuid[], p_bases text[], p_fac text, p_dept text, p_prog text, p_reason text, p_batch text,
                                               p_limit integer, p_dry_run boolean, p_to_level integer DEFAULT NULL, p_spillover text DEFAULT NULL,
                                               p_q text DEFAULT NULL, p_from_level integer DEFAULT NULL)
 RETURNS TABLE(selected integer, corrected integer, spillover integer, registration integer, arithmetic integer, remaining integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_bases  text[] := coalesce(p_bases, ARRAY['SPILLOVER', 'REGISTRATION']);
    v_spill  text := nullif(upper(btrim(coalesce(p_spillover, ''))), '');
    v_like   text := CASE WHEN nullif(btrim(coalesce(p_q, '')), '') IS NULL THEN NULL ELSE '%' || btrim(p_q) || '%' END;
    v_deferred boolean;
    n_sel int; n_done int := 0; n_sp int; n_reg int; n_ar int; n_left int;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_OFFICE: levels are corrected by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF NOT p_dry_run AND v_reason IS NULL THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_REASON: a level correction is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_bases) b WHERE b NOT IN ('SPILLOVER', 'REGISTRATION', 'ARITHMETIC')) THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_BASIS: a basis is SPILLOVER, REGISTRATION or ARITHMETIC' USING ERRCODE = '23514';
    END IF;
    IF v_spill IS NOT NULL AND v_spill NOT IN ('SPILLOVER_YEAR_1', 'SPILLOVER_YEAR_2', 'SPILLOVER_LIMIT_REACHED', 'NONE') THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_SPILLOVER: a spillover position is SPILLOVER_YEAR_1, SPILLOVER_YEAR_2, SPILLOVER_LIMIT_REACHED or NONE' USING ERRCODE = '23514';
    END IF;
    IF (p_to_level IS NOT NULL AND p_to_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900))
       OR (p_from_level IS NOT NULL AND p_from_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900)) THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_LEVEL: a level is 100 to 900' USING ERRCODE = '23514';
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS pg_temp.level_pick (student_id uuid PRIMARY KEY, current_level int, proposed_level int, basis text) ON COMMIT DROP;
    TRUNCATE pg_temp.level_pick;
    INSERT INTO pg_temp.level_pick
    SELECT c.student_id, c.current_level, c.proposed_level, c.basis
      FROM people.level_correction c
      JOIN people.student s ON s.id = c.student_id
      JOIN ref.programme p ON p.code = s.programme_code
     WHERE c.basis = ANY (v_bases)
       AND (p_students IS NULL OR c.student_id = ANY (p_students))
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
       -- V593: the level it should be at, the spillover position, the search
       AND (p_to_level IS NULL OR c.proposed_level = p_to_level)
       AND (p_from_level IS NULL OR c.current_level = p_from_level)   -- V598: the level on record
       AND (v_spill IS NULL OR (v_spill = 'NONE' AND coalesce(c.spillover_state, '') NOT LIKE 'SPILLOVER%') OR c.spillover_state = v_spill)
       AND (v_like IS NULL OR s.matric_no ILIKE v_like OR s.surname ILIKE v_like OR s.other_names ILIKE v_like OR (s.surname || ' ' || s.other_names) ILIKE v_like);
    SELECT count(*), count(*) FILTER (WHERE basis = 'SPILLOVER'), count(*) FILTER (WHERE basis = 'REGISTRATION'), count(*) FILTER (WHERE basis = 'ARITHMETIC')
      INTO n_sel, n_sp, n_reg, n_ar FROM pg_temp.level_pick;

    IF NOT p_dry_run AND n_sel > 0 THEN
        -- a batch at a time: the first p_limit of the selection, in a stable order
        DELETE FROM pg_temp.level_pick WHERE student_id NOT IN (
            SELECT student_id FROM pg_temp.level_pick ORDER BY student_id LIMIT greatest(1, coalesce(p_limit, 500)));
        PERFORM set_config('moaum.reason', v_reason, true);
        v_deferred := people.defer_positions();
        INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                            previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
        SELECT s.id, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
               k.current_level, k.proposed_level, 'LEVEL_' || k.basis, v_reason, v_actor, v_office, nullif(btrim(coalesce(p_batch, '')), '')
          FROM pg_temp.level_pick k
          JOIN people.student s ON s.id = k.student_id
          JOIN people.academic_position ap ON ap.student_id = k.student_id
         WHERE s.current_level < k.proposed_level;
        UPDATE people.student s SET current_level = k.proposed_level
          FROM pg_temp.level_pick k
         WHERE s.id = k.student_id AND s.current_level < k.proposed_level;   -- never lowers
        GET DIAGNOSTICS n_done = ROW_COUNT;
        IF v_deferred THEN PERFORM people.refresh_deferred_positions(); END IF;
    END IF;

    SELECT count(*) INTO n_left FROM people.level_correction c
      JOIN people.student s ON s.id = c.student_id JOIN ref.programme p ON p.code = s.programme_code
     WHERE c.basis = ANY (v_bases) AND (p_students IS NULL OR c.student_id = ANY (p_students))
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
       AND (p_to_level IS NULL OR c.proposed_level = p_to_level)
       AND (p_from_level IS NULL OR c.current_level = p_from_level)   -- V598: the level on record
       AND (v_spill IS NULL OR (v_spill = 'NONE' AND coalesce(c.spillover_state, '') NOT LIKE 'SPILLOVER%') OR c.spillover_state = v_spill)
       AND (v_like IS NULL OR s.matric_no ILIKE v_like OR s.surname ILIKE v_like OR s.other_names ILIKE v_like OR (s.surname || ' ' || s.other_names) ILIKE v_like);
    RETURN QUERY SELECT n_sel, n_done, n_sp, n_reg, n_ar, n_left;
END $function$;
COMMENT ON FUNCTION people.apply_level_corrections(uuid[], text[], text, text, text, text, text, integer, boolean, integer, text, text, integer) IS
  'V475, V593, V598: the Academic Office or the Registry raises records below the computed level to it — chosen students, or by basis (SPILLOVER and REGISTRATION by default) within a faculty, department or programme, and (V593) only those the engine places at a level, in a spillover position, found by a search or (V598) at a level on record; a dry run counts, a run applies a batch read again from the engine; never lowers, each change on the cohort decision history.';

COMMIT;
