-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V601 — Records above their programme's final level brought to it; a spillover student not progressed a level at a time
--
--   1 · A record above its programme's final level holds a level the programme does not have: 500 or 600 on a four-year
--       programme, mostly from the old portal (37 on the live-shaped copy once V598 set the five-year programmes at 500).
--       Level corrections (V475, V593) never lower a level, so nothing listed them. people.level_above_final lists every
--       student in study (not postgraduate) whose level on record is above the programme's final level as the cohort engine
--       reads it (people.academic_position.final_level: the programme's, or the CCE route's), with the engine's own level, the
--       latest registration and whether the student holds a registration above the final level in the current session.
--       people.lower_to_final_level brings them to the final level — the highest level the programme has, never further — on a
--       reason, in batches, each change on the cohort decision history (rule LEVEL_ABOVE_FINAL, the levels before and after,
--       the batch); a dry run counts first; a student registered above the final level this session is left for review unless
--       included in so many words (the registration keeps its level; Course Registration support puts it right). The Academic
--       Office or the Registry acts; the engine's own level, where lower, is a separate correction.
--   2 · Level Management (V500) progressed a spillover student a level at a time — a spillover record at 100 could be moved to
--       200 — though the screen offered the correction to the final level instead. people.level_options now refuses the
--       progression on the server too (LEVEL_IN_SPILLOVER): a student past the programme's length belongs at its final level, by a
--       correction; the next level is still shown, and the spillover state is returned for the screen.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V601: records above the final level brought to it; a spillover student not progressed a level at a time', true);

-- ── 1 · records above the final level ────────────────────────────────────────────────────────────────────────────────────
CREATE VIEW people.level_above_final AS
SELECT s.id AS student_id, s.programme_code, s.current_level, ap.final_level, ap.computed_level, ap.spillover_state, ap.current_session,
       lr.session AS last_registration_session, lr.level AS last_registration_level,
       EXISTS (SELECT 1 FROM registration.course_registration r
                WHERE r.student_id = s.id AND r.session = ap.current_session AND r.level > ap.final_level
                  AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS registered_above_now
  FROM people.student s
  JOIN people.academic_position ap ON ap.student_id = s.id
  JOIN ref.programme p ON p.code = s.programme_code
  LEFT JOIN LATERAL (SELECT r.session, max(r.level) AS level
                       FROM registration.course_registration r
                      WHERE r.student_id = s.id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
                      GROUP BY r.session ORDER BY r.session DESC LIMIT 1) lr ON true
 WHERE s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED') AND s.duplicate_of IS NULL
   AND NOT (s.entry_mode IS DISTINCT FROM 'CCE' AND (s.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE'))   -- as level_options reads it
   AND ap.final_level IS NOT NULL AND s.current_level > ap.final_level;
COMMENT ON VIEW people.level_above_final IS
  'V601: every student in study (not postgraduate) whose level on record is above the programme''s final level as the cohort engine reads it — with the engine''s level, the latest registration and whether a registration above the final level stands in the current session';

CREATE FUNCTION people.lower_to_final_level(p_students uuid[], p_fac text, p_dept text, p_prog text, p_q text, p_reason text, p_batch text,
                                            p_limit integer, p_include_registered boolean, p_dry_run boolean)
 RETURNS TABLE(selected integer, corrected integer, registered_now integer, remaining integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_like   text := CASE WHEN nullif(btrim(coalesce(p_q, '')), '') IS NULL THEN NULL ELSE '%' || btrim(p_q) || '%' END;
    v_deferred boolean;
    n_sel int; n_reg int; n_done int := 0; n_left int;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_OFFICE: levels are corrected by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF NOT p_dry_run AND v_reason IS NULL THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_REASON: a level correction is recorded with its reason' USING ERRCODE = '23514';
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS pg_temp.above_pick (student_id uuid PRIMARY KEY, current_level int, final_level int, registered boolean) ON COMMIT DROP;
    TRUNCATE pg_temp.above_pick;
    INSERT INTO pg_temp.above_pick
    SELECT a.student_id, a.current_level, a.final_level, a.registered_above_now
      FROM people.level_above_final a
      JOIN people.student s ON s.id = a.student_id
      JOIN ref.programme p ON p.code = s.programme_code
     WHERE (p_students IS NULL OR a.student_id = ANY (p_students))
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
       AND (v_like IS NULL OR s.matric_no ILIKE v_like OR s.surname ILIKE v_like OR s.other_names ILIKE v_like OR (s.surname || ' ' || s.other_names) ILIKE v_like);
    SELECT count(*), count(*) FILTER (WHERE registered) INTO n_sel, n_reg FROM pg_temp.above_pick;
    -- a student registered above the final level this session is left for review unless included in so many words
    IF NOT coalesce(p_include_registered, false) THEN DELETE FROM pg_temp.above_pick WHERE registered; END IF;

    IF NOT p_dry_run AND EXISTS (SELECT 1 FROM pg_temp.above_pick) THEN
        DELETE FROM pg_temp.above_pick WHERE student_id NOT IN (
            SELECT student_id FROM pg_temp.above_pick ORDER BY student_id LIMIT greatest(1, coalesce(p_limit, 500)));
        PERFORM set_config('moaum.reason', v_reason, true);
        v_deferred := people.defer_positions();
        INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                            previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
        SELECT s.id, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
               s.current_level, k.final_level, 'LEVEL_ABOVE_FINAL', v_reason, v_actor, v_office, nullif(btrim(coalesce(p_batch, '')), '')
          FROM pg_temp.above_pick k
          JOIN people.student s ON s.id = k.student_id
          JOIN people.academic_position ap ON ap.student_id = k.student_id
         WHERE s.current_level > k.final_level;
        UPDATE people.student s SET current_level = k.final_level
          FROM pg_temp.above_pick k
         WHERE s.id = k.student_id AND s.current_level > k.final_level;   -- to the final level, never below it
        GET DIAGNOSTICS n_done = ROW_COUNT;
        IF v_deferred THEN PERFORM people.refresh_deferred_positions(); END IF;
    END IF;

    SELECT count(*) INTO n_left FROM people.level_above_final a
      JOIN people.student s ON s.id = a.student_id JOIN ref.programme p ON p.code = s.programme_code
     WHERE (p_students IS NULL OR a.student_id = ANY (p_students))
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
       AND (v_like IS NULL OR s.matric_no ILIKE v_like OR s.surname ILIKE v_like OR s.other_names ILIKE v_like OR (s.surname || ' ' || s.other_names) ILIKE v_like)
       AND (coalesce(p_include_registered, false) OR NOT a.registered_above_now);
    RETURN QUERY SELECT n_sel, n_done, n_reg, n_left;
END $function$;
COMMENT ON FUNCTION people.lower_to_final_level(uuid[], text, text, text, text, text, text, integer, boolean, boolean) IS
  'V601: records above the programme''s final level brought to it — chosen students or every one within a faculty, department, programme or search — by the Academic Office or the Registry on a reason, a batch at a time, on the cohort decision history (LEVEL_ABOVE_FINAL); a student registered above the final level this session left unless included; a dry run counts';

-- ── 2 · a spillover student is not progressed a level at a time ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.level_options(p_student uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; p ref.programme; v_pg boolean; v_final int; v_levels int[]; v_next int; v_progress text; v_correct text; v_status text;
        v_spill text; v_spill_years int;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO p FROM ref.programme WHERE code = s.programme_code;
    v_pg := s.entry_mode IS DISTINCT FROM 'CCE' AND (s.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE');
    IF v_pg THEN
        -- a postgraduate student is held at the programme's own level (V455): a Master's 800, a PhD 900, a PGD 700
        v_final := coalesce(people.pg_level_of(s.programme_code), 800);
        v_levels := ARRAY[v_final];
    ELSE
        v_final := coalesce(records.final_level_of(p_student), 400);
        SELECT array_agg(l ORDER BY l) INTO v_levels FROM generate_series(100, v_final, 100) l;
        v_next := CASE WHEN s.current_level < v_final THEN s.current_level + 100 END;
    END IF;
    -- V601: the cohort engine's spillover reading — past the programme's length, the student belongs at the final level
    SELECT ap.spillover_state, ap.spillover_years INTO v_spill, v_spill_years FROM people.academic_position ap WHERE ap.student_id = p_student;
    v_status := lower(replace(s.status, '_', ' '));
    -- what holds either change, then what holds a progression
    v_correct := CASE
        WHEN s.duplicate_of IS NOT NULL THEN 'LEVEL_MERGED_RECORD: this record was merged into another; change the level on the record it was merged into'
        WHEN s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'LEVEL_STATUS: the student is ' || v_status || '; a level is changed only for a student in study (admitted, active or on probation)'
        END;
    v_progress := coalesce(v_correct, CASE
        WHEN v_pg THEN 'LEVEL_PG_PROGRESSION: a postgraduate student stays at the programme''s level (' || v_final || '); there is no next level'
        WHEN s.current_level >= v_final THEN 'LEVEL_AT_FINAL: the student is at the programme''s final level (' || v_final || '); a further session there is a spillover year, not a new level'
        WHEN v_spill LIKE 'SPILLOVER%' THEN 'LEVEL_IN_SPILLOVER: the student is past the programme''s length ('
             || CASE WHEN v_spill = 'SPILLOVER_LIMIT_REACHED' THEN 'beyond the spillover limit' ELSE 'SP' || coalesce(v_spill_years, 1) END
             || '); the record belongs at the final level (' || v_final || ') — correct it there rather than progress it a level at a time'
        END);
    RETURN jsonb_build_object(
        'currentLevel', s.current_level, 'entryLevel', s.entry_level, 'finalLevel', v_final, 'postgraduate', v_pg, 'levels', to_jsonb(v_levels),
        'nextLevel', v_next, 'status', s.status, 'progressRefusal', v_progress, 'correctRefusal', v_correct, 'spilloverState', v_spill,
        'otherLevels', to_jsonb(ARRAY(SELECT l FROM unnest(v_levels) l WHERE l <> s.current_level ORDER BY l)));
END $$;
COMMENT ON FUNCTION people.level_options(uuid) IS
  'V500, V601: the levels a student may hold as the programme states them (100 to the programme''s final level — the CCE route''s where configured; a postgraduate student the programme''s own level), the next level, and why a progression or a correction may not be made — a student past the programme''s length is not progressed a level at a time (LEVEL_IN_SPILLOVER) but corrected to the final level';

GRANT SELECT ON people.level_above_final TO app_auditor, app_reporting;

COMMIT;
