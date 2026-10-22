-- V628: Student Level Management offers the spillover years (the University's word of 22 October 2026: "on the level management
-- include levels above 400 — SP1 and SP2 for 4 year courses, 500 level for Nursing, URP, and 600 for MBBS").
--   · The levels themselves already run to each programme's final level (finance.final_level): 500 for Nursing (C35147) and Urban
--     and Regional Planning (C30468) since V598, 600 for MBBS (C00061). Nothing about them changes.
--   · A spillover year is not a level: the record stays at the final level and the cohort engine counts the sessions past the
--     programme's length from the expected completion (V331, V595), which the Registry may pin (V612). The desk now sets it the
--     same way: people.level_options lists spilloverChoices — SP1 (the expected completion pinned to the session before the
--     current one), SP2 (two before) and, for a student in spillover, the final year again (pinned to the current session) — and
--     people.support_set_spillover sets one: the record put at the final level where it reads lower, the completion pinned through
--     people.set_completion_override, a LEVEL_SPILLOVER_YEAR decision on the history. For every undergraduate programme, past its
--     own final level (400 SP1/SP2 on a four-year course, 500 SP1/SP2 on Nursing, 600 SP1/SP2 on MBBS).
--   · A correction to a level below the final level lifts an expected completion pinned before the current session: below the
--     final level the student is not past the programme's length.
--   · The two functions are restated exactly as they stand (V601, V591) with those additions.

BEGIN;

CREATE OR REPLACE FUNCTION people.level_options(p_student uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; p ref.programme; v_pg boolean; v_final int; v_levels int[]; v_next int; v_progress text; v_correct text; v_status text;
        v_spill text; v_spill_years int;
        v_cur text; v_cohort text; v_choices jsonb := '[]'::jsonb;  -- V628
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
    SELECT ap.spillover_state, ap.spillover_years, ap.current_session, ap.effective_cohort INTO v_spill, v_spill_years, v_cur, v_cohort
      FROM people.academic_position ap WHERE ap.student_id = p_student;
    v_cur := coalesce(v_cur, policy.university_current_session());
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
    -- V628: the spillover years the desk may set — SP1 and SP2, and the final year again for a student in spillover — each by the
    -- expected completion it pins (people.completion_override): the session before this one makes this one SP1, two before SP2,
    -- this one the final year. Offered for an undergraduate in study, a session on the calendar not before the cohort; never the
    -- year the student is in now.
    IF NOT v_pg AND v_correct IS NULL AND v_cur IS NOT NULL THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('year', z.y, 'completion', z.c) ORDER BY z.y), '[]'::jsonb) INTO v_choices
          FROM (SELECT y, CASE WHEN y = 0 THEN v_cur ELSE policy.session_before(v_cur, y) END AS c FROM unnest(ARRAY[0, 1, 2]) y) z
         WHERE (z.y > 0 OR v_spill LIKE 'SPILLOVER%')
           AND NOT (s.current_level = v_final AND coalesce(v_spill, '') = CASE WHEN z.y = 0 THEN '' ELSE 'SPILLOVER_YEAR_' || z.y END)
           AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = z.c AND a.state <> 'CANCELLED')
           AND (v_cohort IS NULL OR policy.session_year(z.c) >= policy.session_year(v_cohort));
    END IF;
    RETURN jsonb_build_object(
        'currentLevel', s.current_level, 'entryLevel', s.entry_level, 'finalLevel', v_final, 'postgraduate', v_pg, 'levels', to_jsonb(v_levels),
        'nextLevel', v_next, 'status', s.status, 'progressRefusal', v_progress, 'correctRefusal', v_correct, 'spilloverState', v_spill,
        'otherLevels', to_jsonb(ARRAY(SELECT l FROM unnest(v_levels) l WHERE l <> s.current_level ORDER BY l)),
        'currentSession', v_cur, 'spilloverChoices', v_choices);
END $function$;
COMMENT ON FUNCTION people.level_options(uuid) IS
  'V500, V601, V628: the levels a student may hold as the programme states them (100 to the programme''s final level — the CCE route''s where configured; a postgraduate student the programme''s own level), the next level, and why a progression or a correction may not be made — a student past the programme''s length is not progressed a level at a time (LEVEL_IN_SPILLOVER) but corrected to the final level; and the spillover years the desk may set (spilloverChoices: SP1, SP2, the final year again), each with the expected completion it pins';

CREATE OR REPLACE FUNCTION people.support_set_level(p_student uuid, p_action text, p_level integer, p_expected integer, p_reason text, p_session text, p_semester integer, p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_action text := upper(btrim(coalesce(p_action, '')));
        s people.student; o jsonb; v_target int; v_refusal text; v_last people.cohort_decision; ap people.academic_position; v_id uuid; v_rule text;
BEGIN
    -- V591: the Students Account Officer holds the level desk beside ICT Support
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super', 'studentaccounts') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed here by ICT Support or the Students Account Officer' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('PROGRESS', 'CORRECTION') THEN
        RAISE EXCEPTION 'LEVEL_ACTION: a level is progressed (PROGRESS) or corrected (CORRECTION)' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEVEL_REASON: say why the level is changed, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    -- one change at a time on a student: the row is held until the change is written
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    o := people.level_options(p_student);
    v_target := CASE WHEN v_action = 'PROGRESS' THEN (o->>'nextLevel')::int ELSE p_level END;
    v_rule := CASE WHEN v_action = 'PROGRESS' THEN 'LEVEL_PROGRESS' ELSE 'LEVEL_CORRECTION' END;

    -- the level read on the screen is no longer the record's: the same change a moment ago by the same person is that change,
    -- anything else is refused, so a stale screen never moves a student twice
    IF p_expected IS DISTINCT FROM s.current_level THEN
        SELECT * INTO v_last FROM people.cohort_decision d
         WHERE d.student_id = p_student AND d.rule IN ('LEVEL_PROGRESS', 'LEVEL_CORRECTION') ORDER BY d.decided_at DESC LIMIT 1;
        IF v_last.id IS NOT NULL AND v_last.decided_at > now() - interval '1 minute' AND v_last.officer IS NOT DISTINCT FROM v_actor
           AND v_last.previous_level = p_expected AND v_last.new_level = s.current_level
           AND v_last.rule = v_rule AND (v_action = 'PROGRESS' OR p_level = s.current_level) THEN
            RETURN jsonb_build_object('alreadyDone', true, 'previousLevel', v_last.previous_level, 'newLevel', v_last.new_level, 'decisionId', v_last.id,
                                      'action', v_last.rule);
        END IF;
        RAISE EXCEPTION 'LEVEL_CHANGED: the record''s level is now %, not %; read the student again', s.current_level, coalesce(p_expected::text, 'what was shown')
            USING ERRCODE = '23514';
    END IF;

    v_refusal := CASE WHEN v_action = 'PROGRESS' THEN o->>'progressRefusal' ELSE o->>'correctRefusal' END;
    IF v_refusal IS NOT NULL THEN RAISE EXCEPTION '%', v_refusal USING ERRCODE = '23514'; END IF;
    IF v_action = 'PROGRESS' AND p_level IS NOT NULL AND p_level IS DISTINCT FROM v_target THEN
        RAISE EXCEPTION 'LEVEL_NOT_NEXT: the next level after % is %, not %; a different level is a correction', s.current_level, v_target, p_level USING ERRCODE = '23514';
    END IF;
    IF v_target IS NULL OR NOT (v_target = ANY (SELECT jsonb_array_elements_text(o->'levels')::int)) THEN
        RAISE EXCEPTION 'LEVEL_NOT_IN_PROGRAMME: % is not one of the levels of the student''s programme (%)', coalesce(v_target::text, 'no level'),
            (SELECT string_agg(x, ', ') FROM jsonb_array_elements_text(o->'levels') x) USING ERRCODE = '23514';
    END IF;
    IF v_target = s.current_level THEN
        RAISE EXCEPTION 'LEVEL_UNCHANGED: the student is already at % Level', v_target USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('moaum.reason', v_reason, true);
    SELECT * INTO ap FROM people.academic_position WHERE student_id = p_student;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, session, semester, ticket_id)
    VALUES (p_student, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
            s.current_level, v_target, v_rule, v_reason, v_actor, v_office,
            p_session, p_semester, p_ticket)
    RETURNING id INTO v_id;
    UPDATE people.student SET current_level = v_target WHERE id = p_student;
    -- V628: below the final level the student is not past the programme's length, so an expected completion pinned before this
    -- session (by the level desk's spillover year or the Registry) no longer stands
    IF v_target < (o->>'finalLevel')::int AND EXISTS (
            SELECT 1 FROM people.completion_override c
             WHERE c.student_id = p_student
               AND policy.session_year(c.expected_completion) < policy.session_year(coalesce(ap.current_session, policy.university_current_session()))) THEN
        PERFORM people.set_completion_override(p_student, NULL, 'Level corrected to ' || v_target || ', below the final level: ' || v_reason);
    END IF;
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_target, 'decisionId', v_id, 'action', v_rule);
END $function$;
COMMENT ON FUNCTION people.support_set_level(uuid, text, integer, integer, text, text, integer, uuid) IS
  'V500/V591/V628: ICT Support or the Students Account Officer progresses a student to the next level or corrects the level to another of the programme''s levels, with a reason (and the ticket), refused with the reason (not in study, merged, not the programme''s level, at the final level, postgraduate, changed meanwhile); a repeat within a minute does nothing; on the cohort decision history; a correction below the final level lifts an expected completion pinned before the current session. Registrations, results, transcripts and the graduation status are not written.';

CREATE OR REPLACE FUNCTION people.support_set_spillover(p_student uuid, p_year integer, p_expected integer, p_reason text, p_session text,
                                                         p_semester integer, p_ticket uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        s people.student; o jsonb; v_final int; v_completion text; v_word text; v_last people.cohort_decision; ap people.academic_position; v_id uuid;
BEGIN
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super', 'studentaccounts') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed here by ICT Support or the Students Account Officer' USING ERRCODE = '42501';
    END IF;
    IF p_year IS NULL OR p_year NOT IN (0, 1, 2) THEN
        RAISE EXCEPTION 'LEVEL_SPILLOVER_YEAR: the desk sets spillover year 1 (SP1), year 2 (SP2), or the final year (0)' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEVEL_REASON: say why the level is changed, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    o := people.level_options(p_student);
    v_final := (o->>'finalLevel')::int;
    v_word := CASE p_year WHEN 0 THEN 'the final year' ELSE 'SP' || p_year END;

    -- a stale screen never moves a student twice: the same act a moment ago by the same person is that act
    IF p_expected IS DISTINCT FROM s.current_level THEN
        SELECT * INTO v_last FROM people.cohort_decision d WHERE d.student_id = p_student AND d.rule = 'LEVEL_SPILLOVER_YEAR'
         ORDER BY d.decided_at DESC LIMIT 1;
        IF v_last.id IS NOT NULL AND v_last.decided_at > now() - interval '1 minute' AND v_last.officer IS NOT DISTINCT FROM v_actor
           AND v_last.previous_level = p_expected AND v_last.new_level = s.current_level AND v_last.reason LIKE v_word || ' %' THEN
            RETURN jsonb_build_object('alreadyDone', true, 'previousLevel', v_last.previous_level, 'newLevel', v_last.new_level, 'decisionId', v_last.id,
                                      'action', v_last.rule, 'spilloverYear', p_year);
        END IF;
        RAISE EXCEPTION 'LEVEL_CHANGED: the record''s level is now %, not %; read the student again', s.current_level, coalesce(p_expected::text, 'what was shown')
            USING ERRCODE = '23514';
    END IF;
    IF o->>'correctRefusal' IS NOT NULL THEN RAISE EXCEPTION '%', o->>'correctRefusal' USING ERRCODE = '23514'; END IF;
    IF (o->>'postgraduate')::boolean THEN
        RAISE EXCEPTION 'LEVEL_PG_SPILLOVER: a postgraduate student has no spillover year on this desk' USING ERRCODE = '23514';
    END IF;
    SELECT (c->>'completion') INTO v_completion FROM jsonb_array_elements(o->'spilloverChoices') c WHERE (c->>'year')::int = p_year;
    IF v_completion IS NULL THEN
        RAISE EXCEPTION 'LEVEL_SPILLOVER_UNAVAILABLE: % cannot be set for this student now (already so, or no session on the calendar to count it from)', v_word
            USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('moaum.reason', v_reason, true);
    SELECT * INTO ap FROM people.academic_position WHERE student_id = p_student;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, session, semester, ticket_id)
    VALUES (p_student, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
            s.current_level, v_final, 'LEVEL_SPILLOVER_YEAR',
            v_word || ' (expected completion pinned to ' || v_completion || '): ' || v_reason, v_actor, v_office, p_session, p_semester, p_ticket)
    RETURNING id INTO v_id;
    IF s.current_level IS DISTINCT FROM v_final THEN
        UPDATE people.student SET current_level = v_final WHERE id = p_student;
    END IF;
    PERFORM people.set_completion_override(p_student, v_completion, v_word || ' set on the level desk: ' || v_reason);
    PERFORM people.refresh_academic_position(p_student);
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_final, 'decisionId', v_id,
                              'action', 'LEVEL_SPILLOVER_YEAR', 'spilloverYear', p_year, 'expectedCompletion', v_completion,
                              'spilloverState', (SELECT spillover_state FROM people.academic_position WHERE student_id = p_student));
END $function$;
COMMENT ON FUNCTION people.support_set_spillover(uuid, integer, integer, text, text, integer, uuid) IS
  'V628: ICT Support or the Students Account Officer sets a student''s spillover year (1 = SP1, 2 = SP2) or the final year again (0): '
  'the record put at the programme''s final level, the expected completion pinned (people.set_completion_override) so the cohort '
  'engine counts this session as that year, a LEVEL_SPILLOVER_YEAR decision on the history; refused with the reason (office, not in '
  'study, merged, postgraduate, not offered now, changed meanwhile); a repeat within a minute does nothing.';

COMMIT;
