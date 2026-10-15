-- ═══════════════════════════════════════
-- V475 — Spillover students brought to their level, and the spillover named where a student's level is read
--
--   The cohort engine (V331, people.academic_position) knows where every student stands: a student past the programme's
--   length is in spillover year 1 or 2 (SP1, SP2 — each a session, both semesters; the limit policy.progression_setting.
--   max_spillover_years, 2 by default; approved deferments push the expected completion on), and the level such a student
--   is at is the programme's final level. But nothing moved the record's own level (people.student.current_level) to it:
--   the old portal's students came over at the level the upload stated, often 100, and a cohort decision changes a status,
--   never a level. On the live-shaped copy about 10,400 spillover students read 100 Level on their record while the engine
--   puts them at 400 to 600 — Gloria Adegahi (BSU/SS/COM/20/58957, B.Sc. Mass Communication, 2020/2021, SP2) among them,
--   though her own 2024/2025 registration is at 400 — and every screen, list, registration menu and level-based fee line
--   reading the record read 100.
--
--   people.level_correction lists every record below the level the engine computes, with the basis of the correction:
--     SPILLOVER     the student is past the programme's length, so at its final level — certain;
--     REGISTRATION  not in spillover, and the student's own latest registration is at the computed level — evidenced;
--     ARITHMETIC    only the count of sessions says so (a repeated year, a transfer, a gap would read the same) — for review.
--   people.apply_level_corrections raises the chosen records to that level (never lowers one), in batches, on a reason,
--   each change on the student's cohort decision history (people.cohort_decision: previous and new level, the basis as the
--   rule, the batch) and on the audit spine; the academic positions are refreshed once a batch. Only the Academic Office,
--   the Registry and the platform apply it. Postgraduate students (whose level does not advance) and students not in study
--   are left out.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V475: spillover students brought to their level', true);

CREATE VIEW people.level_correction AS
SELECT s.id AS student_id, s.current_level, ap.computed_level AS proposed_level,
       CASE WHEN ap.spillover_years > 0 THEN 'SPILLOVER'
            WHEN lr.level = ap.computed_level THEN 'REGISTRATION'
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
  'V475: every record in study below the level the cohort engine computes, with the basis — SPILLOVER (past the programme''s length: its final level), REGISTRATION (the student''s own latest registration is at that level) or ARITHMETIC (the count of sessions only, for review)';

CREATE FUNCTION people.apply_level_corrections(p_students uuid[], p_bases text[], p_fac text, p_dept text, p_prog text,
                                               p_reason text, p_batch text, p_limit integer, p_dry_run boolean)
RETURNS TABLE(selected integer, corrected integer, spillover integer, registration integer, arithmetic integer, remaining integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_bases  text[] := coalesce(p_bases, ARRAY['SPILLOVER', 'REGISTRATION']);
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

    CREATE TEMP TABLE IF NOT EXISTS pg_temp.level_pick (student_id uuid PRIMARY KEY, current_level int, proposed_level int, basis text) ON COMMIT DROP;
    TRUNCATE pg_temp.level_pick;
    INSERT INTO pg_temp.level_pick
    SELECT c.student_id, c.current_level, c.proposed_level, c.basis
      FROM people.level_correction c
      JOIN people.student s ON s.id = c.student_id
      JOIN ref.programme p ON p.code = s.programme_code
     WHERE c.basis = ANY (v_bases)
       AND (p_students IS NULL OR c.student_id = ANY (p_students))
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog);
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
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog);
    RETURN QUERY SELECT n_sel, n_done, n_sp, n_reg, n_ar, n_left;
END $$;
COMMENT ON FUNCTION people.apply_level_corrections(uuid[], text[], text, text, text, text, text, integer, boolean) IS
  'V475: the Academic Office or the Registry raises records below the computed level to it — chosen students, or by basis (SPILLOVER and REGISTRATION by default) within a faculty, department or programme — a batch at a time, never lowering, each change on the cohort decision history with the reason; a dry run counts';

COMMIT;
