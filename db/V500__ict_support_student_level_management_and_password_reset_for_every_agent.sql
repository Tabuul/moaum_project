-- ═══════════════════════════════════════
-- V500 — ICT Support: a student's academic level progressed or corrected, and the password reset, by every agent in service
--
--   ICT Support resolves the common student problems at the desk without escalating each one. Two capabilities join the
--   baseline every ICT support agent in service holds across the University (V453): the reset of a student's password to the
--   default credential (V485 — the matriculation number, changed at the next sign-in, no e-mail), and a student's academic level,
--   progressed to the next level or corrected. Heads of the desk (helpdeskhead, ict, admin, super) hold every capability, as before.
--   The agent does not become an administrator: results, fees, payments, admission and matriculation stay out of reach.
--
--     · helpdesk.support_capabilities / agent_baseline: PROGRESS_LEVEL, CORRECT_LEVEL, VIEW_LEVEL_HISTORY and VIEW_RESET_HISTORY are
--       new; the baseline gains them and RESET_PASSWORD;
--     · the support ledger (helpdesk.support_action) takes LEVEL_PROGRESSED and LEVEL_CORRECTED, in the module ACADEMIC_LEVEL. The
--       list is restated from V490's (which added PAYMENT_RECEIPT_REPORTED), so either may be applied first;
--     · people.cohort_decision — the level history the Registry's decisions and the V475 corrections already write — records the
--       session, the semester and the support ticket of a change;
--     · people.level_options(student): the student's levels as the programme states them (100 to the programme's final level, the
--       CCE route's where it has one; a postgraduate student is held at the programme's own level), the next one, and why a
--       progression or a correction may not be made;
--     · people.support_set_level(student, PROGRESS|CORRECTION, level, expected, reason, session, semester, ticket): the change on the
--       record's current level, refused with the reason — not in study, a merged record, not one of the programme's levels, already
--       at the final level, a postgraduate level, the level changed meanwhile. A second click within a minute does nothing. It is on
--       the cohort decision history (rule LEVEL_PROGRESS or LEVEL_CORRECTION) beside the change itself. Registrations, results,
--       grade points, transcripts, earlier sessions and the graduation status are not written.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V500: ICT Support student level management and password reset for every agent in service', true);

-- ── the capabilities ──
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY']
$$;
COMMENT ON FUNCTION helpdesk.support_capabilities() IS
  'V334, V346, V408, V471, V500: what a support posting may carry. V500 adds a student''s academic level — progressed to the next level, corrected to another of the programme''s levels — and reading the level-change and password-reset histories. Results, refunds, fees, amounts, matriculation and admission decisions are never among them.';

CREATE OR REPLACE FUNCTION helpdesk.agent_baseline()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT ARRAY['ALLOCATE_COURSES', 'CORRECT_LEVEL', 'INVESTIGATE_PAYMENT', 'MANAGE_REGISTRATION', 'PROGRESS_LEVEL', 'REGENERATE_RECEIPT',
                 'REMOVE_ALLOCATIONS', 'RESET_PASSWORD', 'SYNC_ENTITLEMENT', 'VERIFY_PAYMENT', 'VIEW_ALLOCATIONS', 'VIEW_LEVEL_HISTORY',
                 'VIEW_PAYMENTS', 'VIEW_PROGRAMME_STRUCTURE', 'VIEW_RESET_HISTORY', 'VIEW_STUDENT']::text[]
$fn$;
COMMENT ON FUNCTION helpdesk.agent_baseline() IS
  'V453, V471, V500: what every ICT support agent in service may do across the University — open a student in support mode, manage course registration, payment support (V453); view the programme structure and allocate courses (V471); reset a student''s password to the default credential, progress or correct a student''s academic level, and read the level-change and password-reset histories (V500). The bulk allocation import, editing the structure, the registration override, record edits, exports and the whole support audit are granted with a posting.';

-- ── the support ledger: the level acts (the list restated from V490's) ──
ALTER TABLE helpdesk.support_action DROP CONSTRAINT ck_hd_sa_action;
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_action CHECK (action IN (
    'CONTACT_EDITED', 'PERSONAL_EDITED', 'FAMILY_EDITED', 'PHOTO_REPLACED', 'CHANGE_REQUESTED', 'REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED',
    'COURSE_RESTORED', 'REGISTRATION_SUBMITTED', 'RECORD_EXPORTED', 'PASSWORD_RESET', 'ACCOUNT_UNLOCKED', 'PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED',
    'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'PAYMENT_RECEIPT_REPORTED', 'ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED',
    'LEVEL_PROGRESSED', 'LEVEL_CORRECTED'));
CREATE OR REPLACE FUNCTION helpdesk.support_module(p_action text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_action IN ('REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED') THEN 'COURSE_REGISTRATION'
                WHEN p_action IN ('PASSWORD_RESET', 'ACCOUNT_UNLOCKED') THEN 'AUTHENTICATION'
                WHEN p_action IN ('PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED', 'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'PAYMENT_RECEIPT_REPORTED') THEN 'PAYMENT'
                WHEN p_action IN ('ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED') THEN 'TICKET'
                WHEN p_action IN ('LEVEL_PROGRESSED', 'LEVEL_CORRECTED') THEN 'ACADEMIC_LEVEL'
                WHEN p_action = 'RECORD_EXPORTED' THEN 'REPORTS'
                ELSE 'STUDENT_RECORD' END
$$;

-- ── the level history: the session, the semester and the ticket of a change ──
ALTER TABLE people.cohort_decision
    ADD COLUMN session   text    NULL,
    ADD COLUMN semester  integer NULL CHECK (semester IS NULL OR semester BETWEEN 1 AND 3),
    ADD COLUMN ticket_id uuid    NULL REFERENCES helpdesk.ticket (id) ON DELETE SET NULL;
CREATE INDEX ix_cohort_decision_ticket ON people.cohort_decision (ticket_id) WHERE ticket_id IS NOT NULL;
CREATE INDEX ix_cohort_decision_level_rule ON people.cohort_decision (decided_at DESC) WHERE rule LIKE 'LEVEL\_%';
COMMENT ON COLUMN people.cohort_decision.ticket_id IS 'V500: the support ticket a level change was made on (ICT Support), where it was';
COMMENT ON COLUMN people.cohort_decision.session IS 'V500: the academic session the student stood in when the change was made';

-- ── the levels a student may hold, the next one, and why a change may not be made ──
CREATE FUNCTION people.level_options(p_student uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; p ref.programme; v_pg boolean; v_final int; v_levels int[]; v_next int; v_progress text; v_correct text; v_status text;
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
    v_status := lower(replace(s.status, '_', ' '));
    -- what holds either change, then what holds a progression
    v_correct := CASE
        WHEN s.duplicate_of IS NOT NULL THEN 'LEVEL_MERGED_RECORD: this record was merged into another; change the level on the record it was merged into'
        WHEN s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'LEVEL_STATUS: the student is ' || v_status || '; a level is changed only for a student in study (admitted, active or on probation)'
        END;
    v_progress := coalesce(v_correct, CASE
        WHEN v_pg THEN 'LEVEL_PG_PROGRESSION: a postgraduate student stays at the programme''s level (' || v_final || '); there is no next level'
        WHEN s.current_level >= v_final THEN 'LEVEL_AT_FINAL: the student is at the programme''s final level (' || v_final || '); a further session there is a spillover year, not a new level'
        END);
    RETURN jsonb_build_object(
        'currentLevel', s.current_level, 'entryLevel', s.entry_level, 'finalLevel', v_final, 'postgraduate', v_pg, 'levels', to_jsonb(v_levels),
        'nextLevel', v_next, 'status', s.status, 'progressRefusal', v_progress, 'correctRefusal', v_correct,
        'otherLevels', to_jsonb(ARRAY(SELECT l FROM unnest(v_levels) l WHERE l <> s.current_level ORDER BY l)));
END $$;
COMMENT ON FUNCTION people.level_options(uuid) IS
  'V500: the levels a student may hold as the programme states them (100 to the programme''s final level — the CCE route''s where configured; a postgraduate student the programme''s own level), the next level, and why a progression or a correction may not be made';

-- ── the change: the record's current level, on the level history; refused with the reason ──
CREATE FUNCTION people.support_set_level(p_student uuid, p_action text, p_level integer, p_expected integer, p_reason text,
                                         p_session text, p_semester integer, p_ticket uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_action text := upper(btrim(coalesce(p_action, '')));
        s people.student; o jsonb; v_target int; v_refusal text; v_last people.cohort_decision; ap people.academic_position; v_id uuid; v_rule text;
BEGIN
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed here by ICT Support' USING ERRCODE = '42501';
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
END $$;
COMMENT ON FUNCTION people.support_set_level(uuid, text, integer, integer, text, text, integer, uuid) IS
  'V500: ICT Support progresses a student to the next level or corrects the level to another of the programme''s levels, with a reason (and the ticket), refused with the reason (not in study, merged, not the programme''s level, at the final level, postgraduate, changed meanwhile); a repeat within a minute does nothing; on the cohort decision history. Registrations, results, transcripts and the graduation status are not written.';

COMMIT;
