-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V591 — The Students Account Officer holds Student Level Management and Old Fees History (20 Oct 2026)
--
--   The Bursary's Students Account Officer (V520) is given two desks the office did not hold:
--     · Student Level Management and its Level Change History (V500): the officer reaches every student there, progresses a
--       student to the next level or corrects the level with a reason, exactly as ICT Support does — the same rules
--       (people.support_set_level: in study, the programme's levels, the final level, a stale screen), the same record (the
--       cohort decision history and the support ledger, under the officer's own office), nothing else of the ICT Support
--       Desk (tickets, password resets, the student's portal, support overrides stay the desk's: the API admits the office to the
--       level doors and the student finder only, with the level capabilities and no other);
--     · Old Fees History (V087, V498): the old portal's school-fees history imported, what is loaded, item codes, records put
--       right and doubles withdrawn — the acts of the import; what needs the bank's word or moves money (a double charge checked,
--       a payment never received, an excess carried or refunded), the ledger posted and the go-live reset stay the Bursar's.
--   Here: people.support_set_level admits the office. The rest is the API's gates and the menus.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V591: the Students Account Officer holds Student Level Management and Old Fees History', true);

/* V500's rule, admitting the Students Account Officer (V591) */
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
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_target, 'decisionId', v_id, 'action', v_rule);
END $function$;

COMMENT ON FUNCTION people.support_set_level(uuid, text, integer, integer, text, text, integer, uuid) IS
    'V500/V591: ICT Support or the Students Account Officer progresses a student to the next level or corrects the level to another of the '
    'programme''s levels, with a reason (and the ticket), refused with the reason (not in study, merged, not the programme''s level, at the '
    'final level, postgraduate, changed meanwhile); a repeat within a minute does nothing; on the cohort decision history. Registrations, '
    'results, transcripts and the graduation status are not written.';

COMMIT;
