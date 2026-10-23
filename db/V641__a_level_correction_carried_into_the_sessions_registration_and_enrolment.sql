-- ═══════════════════════════════════════
-- V641 — A level correction carries into the session's course registration and enrolment; the rollover never promotes a
-- student into their own entry session
--
-- The University's report of 23 October 2026: a 100 Level student (entered 2025/2026 by UTME) whose GST & EPS examination
-- permit card and payment receipt read 200 Level. The examination card and the permit print the level on the session's course
-- registration, and the receipt the session's level (the enrolment for it, else the arithmetic from the entry session); a
-- registration takes the record's level when the student starts it (registration.student_draft) and nothing wrote it again:
--
--   · a level corrected at the level desk (people.support_set_level, V500/V628) or by the Academic Office's level corrections
--     (people.apply_level_corrections, V475/V598) changed the record alone — the desk told the agent "the registration is not
--     deleted or changed; correct it afterwards through Course Registration support", and no support path changes a
--     registration's level (a reset keeps the row and its level), so a student corrected after registering printed the old
--     level on every document of the session;
--   · the session rollover (people.roll_over_session, V110) promoted every active, matriculated student below the final level
--     without an enrolment in the target session — a student matriculated at admission (as every fresh student here is) and one
--     already at the level that session reaches included: rolled into their own entry session, a fresh student went to 200
--     Level with a 200 Level enrolment.
--
-- Now:
--   1. people.carry_level_to_session(student, from, to, session): the session's course registrations and enrolment still at
--      the level corrected from are set to the corrected level (registration.entry, results and fees untouched; the cohort
--      position and the CGPA follow by their own triggers).
--   2. people.support_set_level: a CORRECTION carries into the desk's session (a progression does not); the answer names what
--      was carried. people.apply_level_corrections: each correction carries into the University's current session.
--   3. people.roll_over_session: never promotes a student into their entry session or one before it, nor past the level their
--      entry reaches by the target session (entry level + 100 a session); those held are counted ('held').
--   4. people.repair_session_levels(session): once now for the current session, safe to run again — the session's rows left
--      at the level of a correction made this session that the record still holds, and the rows of a student in their entry
--      session whose record holds the entry level, set to the record's level.
-- The receipt reads the session's course registration first, as the examination card and the permit do, then the enrolment,
-- then the arithmetic (StudentPortalRepository.levelForSession).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V641: the session''s course registration and enrolment at the level the record holds after a correction', true);

-- ── 1 · the carry ───────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.carry_level_to_session(p_student uuid, p_from integer, p_to integer, p_session text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE n_reg int := 0; n_enr int := 0;
BEGIN
    IF p_student IS NULL OR p_session IS NULL OR p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RETURN jsonb_build_object('session', p_session, 'registrations', 0, 'enrolment', 0);
    END IF;
    UPDATE registration.course_registration SET level = p_to
     WHERE student_id = p_student AND session = p_session AND level = p_from;
    GET DIAGNOSTICS n_reg = ROW_COUNT;
    UPDATE people.enrolment SET level = p_to
     WHERE student_id = p_student AND session = p_session AND level = p_from;
    GET DIAGNOSTICS n_enr = ROW_COUNT;
    RETURN jsonb_build_object('session', p_session, 'registrations', n_reg, 'enrolment', n_enr);
END $fn$;
COMMENT ON FUNCTION people.carry_level_to_session(uuid, integer, integer, text) IS
  'V641: a level correction carried into the session — the student''s course registrations and enrolment for the session still at '
  'the level corrected from set to the corrected level (the examination card, the GST & EPS permit, the receipt, the results and '
  'the transcript read the session''s level from them). Courses, results and fees are not touched. Returns the session and how '
  'many registrations and enrolments were set.';

-- ── 2 · the level desk and the level corrections carry ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.support_set_level(p_student uuid, p_action text, p_level integer, p_expected integer, p_reason text, p_session text, p_semester integer, p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_action text := upper(btrim(coalesce(p_action, '')));
        s people.student; o jsonb; v_target int; v_refusal text; v_last people.cohort_decision; ap people.academic_position; v_id uuid; v_rule text; v_carried jsonb;
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
    -- V641: a correction carries into the session's course registrations and enrolment still at the level corrected from — the
    -- level the examination card, the GST & EPS permit, the receipt, the results and the transcript read for the session
    IF v_action = 'CORRECTION' THEN
        v_carried := people.carry_level_to_session(p_student, s.current_level, v_target, coalesce(p_session, policy.university_current_session()));
    END IF;
    -- V628: below the final level the student is not past the programme's length, so an expected completion pinned before this
    -- session (by the level desk's spillover year or the Registry) no longer stands
    IF v_target < (o->>'finalLevel')::int AND EXISTS (
            SELECT 1 FROM people.completion_override c
             WHERE c.student_id = p_student
               AND policy.session_year(c.expected_completion) < policy.session_year(coalesce(ap.current_session, policy.university_current_session()))) THEN
        PERFORM people.set_completion_override(p_student, NULL, 'Level corrected to ' || v_target || ', below the final level: ' || v_reason);
    END IF;
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_target, 'decisionId', v_id, 'action', v_rule,
                              'carried', v_carried);
END $function$;
COMMENT ON FUNCTION people.support_set_level(uuid, text, integer, integer, text, text, integer, uuid) IS
  'V500/V591/V628/V641: ICT Support or the Students Account Officer progresses a student to the next level or corrects the level to another of the programme''s levels, with a reason (and the ticket), refused with the reason (not in study, merged, not the programme''s level, at the final level, postgraduate, changed meanwhile); a repeat within a minute does nothing; on the cohort decision history; a correction below the final level lifts an expected completion pinned before the current session; (V641) a correction carries into the session''s course registrations and enrolment still at the level corrected from (''carried''), a progression does not. Courses, results, transcripts and the graduation status are not written.';

CREATE OR REPLACE FUNCTION people.apply_level_corrections(p_students uuid[], p_bases text[], p_fac text, p_dept text, p_prog text, p_reason text, p_batch text,
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
        -- V641: each correction carries into the current session's course registrations and enrolment still at the level corrected from
        PERFORM people.carry_level_to_session(k.student_id, k.current_level, k.proposed_level, policy.university_current_session())
           FROM pg_temp.level_pick k
           JOIN people.student s ON s.id = k.student_id
          WHERE k.current_level < k.proposed_level AND s.current_level = k.proposed_level;
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
  'V475, V593, V598, V641: the Academic Office or the Registry raises records below the computed level to it — chosen students, or by basis (SPILLOVER and REGISTRATION by default) within a faculty, department or programme, and (V593) only those the engine places at a level, in a spillover position, found by a search or (V598) at a level on record; a dry run counts, a run applies a batch read again from the engine; never lowers, each change on the cohort decision history; (V641) each correction carries into the current session''s course registrations and enrolment still at the level corrected from.';

-- ── 3 · the rollover never promotes a student into their own entry session ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.roll_over_session(p_to_session text, p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_created boolean := false; v_promoted int := 0; v_held int := 0; v_to int; r record;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a session roll-over is made by a person' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'ROLLOVER' THEN
        RAISE EXCEPTION 'type ROLLOVER to confirm promoting continuing students into %', p_to_session USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a session roll-over names its reason' USING ERRCODE = '23514';
    END IF;
    v_to := policy.session_year(p_to_session);
    IF v_to IS NULL THEN
        RAISE EXCEPTION 'a session is named YYYY/YYYY, not %', p_to_session USING ERRCODE = '23514';
    END IF;

    -- open the target session (and its two semesters) if it is not there yet, as PLANNED
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to_session) THEN
        PERFORM assessment.ensure_session(p_to_session);
        UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = p_to_session;
        v_created := true;
    END IF;

    -- V641: a student enters a session at their entry level — never promoted into their entry session (or one before it), nor
    -- past the level the entry reaches by the target session; counted, before anyone moves
    SELECT count(*) INTO v_held
      FROM people.student s
     WHERE s.status IN ('ACTIVE', 'PROBATION')
       AND s.matric_no IS NOT NULL
       AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
       AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
       AND NOT coalesce(policy.session_year(s.entry_session) < v_to
                        AND s.current_level + 100 <= s.entry_level + 100 * (v_to - policy.session_year(s.entry_session)), false);

    FOR r IN
        SELECT s.id, s.current_level + 100 AS new_level
          FROM people.student s
         WHERE s.status IN ('ACTIVE', 'PROBATION')
           AND s.matric_no IS NOT NULL
           AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
           AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
           AND policy.session_year(s.entry_session) < v_to
           AND s.current_level + 100 <= s.entry_level + 100 * (v_to - policy.session_year(s.entry_session))
    LOOP
        UPDATE people.student SET current_level = r.new_level WHERE id = r.id;
        INSERT INTO people.enrolment (id, student_id, session, level)
        VALUES (gen_random_uuid(), r.id, p_to_session, r.new_level)
        ON CONFLICT (student_id, session) DO NOTHING;
        v_promoted := v_promoted + 1;
    END LOOP;

    RETURN jsonb_build_object('session', p_to_session, 'created_session', v_created,
                             'promoted', v_promoted, 'held', v_held, 'reason', btrim(p_reason));
END $$;

COMMENT ON FUNCTION people.roll_over_session(text, text, text) IS
'V110/V641: promote continuing students one level into a new session and enrol them; opens the session as PLANNED if new. Guarded by an actor, the word ROLLOVER and a reason; idempotent. (V641) Never promotes a student into their entry session or one before it, nor past the level their entry reaches by the target session (entry level + 100 a session); those are counted as held.';

-- ── 4 · the session's rows put right ────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.repair_session_levels(p_session text DEFAULT NULL)
RETURNS TABLE (students integer, registrations integer, enrolments integer) LANGUAGE plpgsql AS $fn$
DECLARE v_session text := coalesce(p_session, policy.university_current_session());
        v_starts date; t record; c jsonb; v_ids uuid[] := '{}'; n_reg int := 0; n_enr int := 0;
BEGIN
    SELECT a.starts_on INTO v_starts FROM policy.academic_session a WHERE a.name = v_session;
    FOR t IN
        -- a correction made this session whose level the record still holds: the session's rows at the level it corrected from
        SELECT d.student_id, d.previous_level AS from_level, d.new_level AS to_level
          FROM (SELECT DISTINCT ON (x.student_id) x.student_id, x.previous_level, x.new_level, x.rule, x.session, x.decided_at
                  FROM people.cohort_decision x
                 WHERE x.rule LIKE 'LEVEL\_%' AND x.new_level IS NOT NULL AND x.previous_level IS NOT NULL
                 ORDER BY x.student_id, x.decided_at DESC) d
          JOIN people.student s ON s.id = d.student_id AND s.current_level = d.new_level
         WHERE d.rule IN ('LEVEL_CORRECTION', 'LEVEL_SPILLOVER', 'LEVEL_REGISTRATION', 'LEVEL_ARITHMETIC')
           AND d.previous_level <> d.new_level
           AND (d.session = v_session OR (d.session IS NULL AND v_starts IS NOT NULL AND d.decided_at >= v_starts))
        UNION
        -- a student in their entry session whose record holds the entry level: the session's rows at any other level
        SELECT s.id, x.level, s.current_level
          FROM people.student s
          JOIN (SELECT r.student_id, r.level FROM registration.course_registration r WHERE r.session = v_session
                UNION
                SELECT e.student_id, e.level FROM people.enrolment e WHERE e.session = v_session) x ON x.student_id = s.id
         WHERE s.entry_session = v_session AND s.current_level = s.entry_level AND x.level <> s.current_level
    LOOP
        c := people.carry_level_to_session(t.student_id, t.from_level, t.to_level, v_session);
        IF (c->>'registrations')::int + (c->>'enrolment')::int > 0 THEN
            n_reg := n_reg + (c->>'registrations')::int;
            n_enr := n_enr + (c->>'enrolment')::int;
            IF NOT t.student_id = ANY (v_ids) THEN v_ids := v_ids || t.student_id; END IF;
        END IF;
    END LOOP;
    students := coalesce(array_length(v_ids, 1), 0);
    registrations := n_reg;
    enrolments := n_enr;
    RETURN NEXT;
END $fn$;
COMMENT ON FUNCTION people.repair_session_levels(text) IS
  'V641: a session''s course registrations and enrolments set to the level the record holds where they were left behind — at the '
  'level of a correction made in the session that the record still holds, or (a student in their entry session whose record holds '
  'the entry level) at any other level. The current session when none is named. Returns the students, registrations and enrolments '
  'set. Run once by V641; safe to run again.';

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.repair_session_levels();
    RAISE NOTICE 'V641: % student(s): % course registration(s) and % enrolment(s) set to the level on record for %',
        r.students, r.registrations, r.enrolments, policy.university_current_session();
END $$;

COMMIT;
