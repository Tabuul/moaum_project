-- V576: the spillover fee lines made ready for the cohort basis, and the fee effect of a level change shown before it is made.
--
-- V571 lets the Bursary charge the spillover lines by the cohort engine's spillover. On the live-shaped copy of 20 October 2026,
-- by the cohort 358 spillover students had no line for 2025/2026 (81 by the level) and 13,068 none for 2026/2027 (249 by the
-- level), whose fees state no spillover line yet. And the Registry's level corrections and Reconciliation change what a student
-- is charged — a spillover student raised from 100 to 400 Level is charged as a 400-Level student — with nothing saying so first.
--
--   * finance.spill_readiness(session): the spillover students with no line stated for the session, by the level and by the
--     cohort (each read with that basis set for the transaction), and the groups they fall in — beside the Bursary's basis,
--     for the current session and the next. (The session copy already carries spillover lines: finance.fee_line_same_scope
--     tells a spillover line from an ordinary one, so a copy never takes one for the other.)
--   * finance.level_fee_effect(session, students, levels): what each student is charged for the session now and with the
--     level given — the levels raised in a sub-transaction that is always undone, the charges read before and after
--     (finance.session_charges). Read by Student Cohorts → Level corrections before a batch is applied, and by
--     Reconciliation's preview for the levels it raises. Nothing is changed.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V576: spillover fee readiness and the fee effect of level changes', true);

-- the spillover students with no line for a session, under each basis (the basis read for this transaction, then put back)
CREATE FUNCTION finance.spill_readiness(p_session text)
RETURNS TABLE (basis text, students bigint, groups bigint)
LANGUAGE plpgsql AS $fn$
DECLARE v_was text := current_setting('moaum.spill_basis', true); b text;
BEGIN
    FOREACH b IN ARRAY ARRAY['LEVEL', 'COHORT'] LOOP
        PERFORM set_config('moaum.spill_basis', b, true);
        RETURN QUERY SELECT b, coalesce(sum(g.students), 0)::bigint, count(*)::bigint
                       FROM finance.fee_gaps(p_session) g WHERE g.spillover AND NOT g.stated;
    END LOOP;
    PERFORM set_config('moaum.spill_basis', coalesce(v_was, ''), true);
END $fn$;
COMMENT ON FUNCTION finance.spill_readiness(text) IS
  'V576: the spillover students with no fee line stated for a session, by the level and by the cohort, and the groups they fall in';

-- what each student is charged for the session now, and with the level given; nothing changed
CREATE FUNCTION finance.level_fee_effect(p_session text, p_students uuid[], p_levels integer[])
RETURNS TABLE (student_id uuid, current_level integer, new_level integer, charged_now numeric, charged_after numeric)
LANGUAGE plpgsql AS $fn$
DECLARE v_before jsonb := '{}'; v_after jsonb := '{}'; v_levels jsonb := '{}';
BEGIN
    IF coalesce(cardinality(p_students), 0) <> coalesce(cardinality(p_levels), 0) THEN
        RAISE EXCEPTION 'FEE_EFFECT_ARGS: a level is given for each student' USING ERRCODE = '22023';
    END IF;
    IF coalesce(cardinality(p_students), 0) > 1000 THEN
        RAISE EXCEPTION 'FEE_EFFECT_SIZE: the fee effect is read for 1,000 students at most' USING ERRCODE = '23514';
    END IF;
    IF coalesce(cardinality(p_students), 0) = 0 THEN
        RETURN;
    END IF;
    SELECT coalesce(jsonb_object_agg(c.student_id, c.total), '{}') INTO v_before
      FROM finance.session_charges(p_session) c WHERE c.student_id = ANY (p_students);
    SELECT coalesce(jsonb_object_agg(s.id, s.current_level), '{}') INTO v_levels
      FROM people.student s WHERE s.id = ANY (p_students);
    -- the levels raised, the charges read, all undone
    BEGIN
        PERFORM people.defer_positions();
        UPDATE people.student s SET current_level = x.lvl
          FROM unnest(p_students, p_levels) x(id, lvl)
         WHERE s.id = x.id AND x.lvl IS NOT NULL AND s.current_level IS DISTINCT FROM x.lvl;
        SELECT coalesce(jsonb_object_agg(c.student_id, c.total), '{}') INTO v_after
          FROM finance.session_charges(p_session) c WHERE c.student_id = ANY (p_students);
        RAISE EXCEPTION 'FEE_EFFECT_UNDONE' USING ERRCODE = 'P0099';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;
    RETURN QUERY
    SELECT x.id, (v_levels->>x.id::text)::int, coalesce(x.lvl, (v_levels->>x.id::text)::int),
           coalesce((v_before->>x.id::text)::numeric, 0), coalesce((v_after->>x.id::text)::numeric, 0)
      FROM unnest(p_students, p_levels) x(id, lvl);
END $fn$;
COMMENT ON FUNCTION finance.level_fee_effect(text, uuid[], integer[]) IS
  'V576: what each student is charged for a session now and with the level given — the levels raised in a sub-transaction always undone';

COMMIT;
