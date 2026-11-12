-- ═══════════════════════════════════════════════════════════
-- V730 — the department-change hold of V696 released: a student who changed department continues from the level they reached
--
--   The University's word of 12 November 2026: "release this policy (Changed department: held one level behind the entry cohort
--   (V696)) — most students continue from the level they stopped from the other department; the ones that step down level are the
--   ones that their result was bad or not good enough to continue with the former department". And its decisions the same day:
--   every automatic hold is released and what it lowered put back; a student who changed department reads the level their record
--   shows — the level reached, as the old portal or an office recorded it — never a year added above it by the count from entry, and
--   never lowered by a rule; a step down for weak results is an office's decision with a reason (the level desk, the transfer
--   committee's recommended level, a swap's or a bulk transfer's level), and every reader follows it.
--
--   What stood (V696, V702): every active undergraduate whose matric names another department, or whose transfer was recorded, was
--   given an effective cohort one session after their entry (people.cohort_override, decision COHORT_DEPARTMENT_CHANGE); a record above
--   the level that cohort reaches was lowered (LEVEL_DEPARTMENT_CHANGE), with the current session's registrations and enrolment; a
--   transfer, a swap or a restored old-portal transfer held the student as it was made (two triggers); any later raise was clamped to
--   the hold (trg_student_hold_level, LEVEL_HELD_DEPARTMENT_CHANGE); the level desk withheld every level above it; the roll-over
--   promoted nobody past it. On the live copy of 21 October 2026: 566 held, 87 records, 277 enrolments and 8 registrations lowered,
--   85 students charged ₦3.01m more for 2025/2026 — 66 of the 72 who paid had paid their own level's fee.
--
--   1 · Nothing holds a student for changing department any more: the three triggers and the hold's functions go; the level desk's
--       options and its setter are restated without it; people.department_hold_of answers no hold for everyone (kept, not dropped: the
--       roll-over and V733's own-session roll-over still name it, and V733 edits the roll-over in place); the Bursary's reading of the
--       hold's fees goes with it.
--   2 · The level reached: people.align_level_reached(student) gives a student who changed department, and whose record is below the
--       level their entry cohort reaches this session (and below the programme's final level), an effective cohort that reaches exactly
--       their record — so receipts, the level in a session, the academic position, spillover and the level desk read the record and
--       never a year above it; a record at or above that level needs none. Its cohort follows the record whenever an office, a
--       transfer or the roll-over changes the level or the programme (trigger trg_student_level_reached); a cohort the desk sets by
--       hand is the desk's and is never touched.
--   3 · The release: every record V696 lowered, and still lowered, put back (LEVEL_DEPARTMENT_CHANGE_RELEASED) with the session's
--       registrations and enrolment it lowered with it; every raise the guard refused, and still refused, made
--       (LEVEL_HELD_RELEASED); every hold either lifted (COHORT_DEPARTMENT_CHANGE_RELEASED: the record reaches the cohort's level) or
--       turned into the level reached (COHORT_LEVEL_REACHED: the record as the old portal left it, a level behind). V696's decisions
--       are kept as history.
--   4 · An old-portal transfer freed from the queue (V686) at the level the committee recommended, where it did.
-- ═══════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V730: the department-change hold of V696 released; a student continues from the level reached', true);

-- ── 1 · nothing holds a student for changing department ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_student_department_change ON people.student;
DROP TRIGGER IF EXISTS trg_prior_transfer_department_change ON people.prior_transfer;
DROP TRIGGER IF EXISTS trg_student_hold_level ON people.student;
DROP FUNCTION IF EXISTS people.hold_on_department_change();
DROP FUNCTION IF EXISTS people.hold_on_prior_transfer();
DROP FUNCTION IF EXISTS people.hold_level_guard();
DROP FUNCTION IF EXISTS people.hold_department_changes(text, text);
DROP FUNCTION IF EXISTS people.hold_department_change(uuid, text, text);
DROP FUNCTION IF EXISTS finance.department_change_fee_effect(text);
-- restated from V702 (people.level_options): no level withheld for a change of department
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

-- restated from V702 (people.support_set_level): the level the office sets, never refused for a change of department
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
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super', 'studentaccounts', 'academic', 'registrar', 'dregistrar') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed by ICT Support, the Students Account Officer, the Academic Office or the Registry' USING ERRCODE = '42501';
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
    -- V730: a progression is the next session's level (V673): the level reached is aligned against that session
    IF v_action = 'PROGRESS' THEN
        PERFORM set_config('moaum.level_session', (left(coalesce(p_session, policy.university_current_session()), 4)::int + 1) || '/'
                                                  || (left(coalesce(p_session, policy.university_current_session()), 4)::int + 2), true);
    END IF;
    UPDATE people.student SET current_level = v_target WHERE id = p_student;
    IF v_action = 'PROGRESS' THEN PERFORM set_config('moaum.level_session', '', true); END IF;
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

-- restated from V686 (people.free_old_portal_transfers): the level the committee recommended, where it did
CREATE OR REPLACE FUNCTION people.free_old_portal_transfers(p_applications uuid[], p_reason text, p_reference text, p_approved_on date)
RETURNS TABLE(application_id uuid, student_id uuid, matric_no text, name text, from_programme text, to_programme text, to_level integer,
              outcome text, swap_ref text, detail text)
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := btrim(coalesce(p_reason, '')); v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
        a record; res jsonb; v_err text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PTR_ACTOR: an approved transfer is restored by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PTR_OFFICE: an approved transfer is restored by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PTR_REASON: say why the applications leave the queue (the old portal''s approval, the memo), in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_applications IS NULL OR cardinality(p_applications) = 0 THEN
        RAISE EXCEPTION 'PTQ_NONE: choose the applications the old portal approved' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_applications) > 2000 THEN
        RAISE EXCEPTION 'PTQ_MANY: free up to 2,000 applications at a time' USING ERRCODE = '23514';
    END IF;
    IF p_approved_on IS NOT NULL AND p_approved_on > (now() AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'PTR_APPROVED_ON: the transfers cannot have been approved in the future' USING ERRCODE = '23514';
    END IF;
    -- each application once, in the order chosen
    FOR a IN
        SELECT x.* FROM (
            SELECT DISTINCT ON (u.id) u.id AS asked, u.n, t.id, t.student_id, t.state, t.session, t.from_programme_code, t.to_programme_code,
                   s.matric_no, s.surname || ', ' || s.other_names AS name,
                   coalesce(t.recommended_level, s.current_level) AS current_level,   -- V730: a step down the committee recommended stands
                   fp.name AS from_name, tp.name AS to_name
              FROM unnest(p_applications) WITH ORDINALITY u(id, n)
              LEFT JOIN people.transfer_application t ON t.id = u.id
              LEFT JOIN people.student s ON s.id = t.student_id
              LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
              LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
             ORDER BY u.id, u.n) x
         ORDER BY x.n
    LOOP
        application_id := a.asked; student_id := a.student_id; matric_no := a.matric_no; name := a.name;
        from_programme := coalesce(a.from_name, a.from_programme_code); to_programme := coalesce(a.to_name, a.to_programme_code); to_level := a.current_level;
        swap_ref := NULL; detail := NULL;
        IF a.id IS NULL THEN
            outcome := 'REFUSED'; detail := 'PTQ_NOT_FOUND: no such transfer application';
        ELSIF a.state NOT IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED') THEN
            outcome := 'REFUSED'; detail := 'PTQ_NOT_QUEUED: the application is ' || lower(replace(a.state, '_', ' ')) || ', not in the queue';
        ELSE
            BEGIN
                -- the transfer's session the application's, where it is a session of the University (else the restoration's own)
                res := people.restore_approved_transfer(a.student_id, a.to_programme_code, a.current_level, NULL, v_reason, a.from_programme_code,
                                                        CASE WHEN EXISTS (SELECT 1 FROM policy.academic_session z WHERE z.name = a.session) THEN a.session END,
                                                        NULL, p_approved_on, v_ref, NULL);
                -- this application leaves the queue, whichever of the student's was the latest
                UPDATE people.transfer_application x SET state = 'WITHDRAWN',
                       withdrawn_why = 'Withdrawn by the ' || initcap(office) || ' office: the transfer was approved on the old portal'
                                       || coalesce(' (' || v_ref || ')', '') || ' and is restored without a new application'
                 WHERE x.id = a.id AND x.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED');
                outcome := CASE WHEN (res ->> 'recordOnly')::boolean THEN 'RECORDED' ELSE 'MOVED' END;
                swap_ref := res ->> 'swapRef';
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
                outcome := 'REFUSED'; detail := v_err; swap_ref := NULL;
            END;
        END IF;
        RETURN NEXT;
    END LOOP;
END $fn$;

-- no student is held for a change of department: the hold's reading answers none for everyone (the roll-over and V733's own-session
-- roll-over still ask it)
CREATE OR REPLACE FUNCTION people.department_hold_of(p_student uuid, p_session text)
RETURNS integer LANGUAGE sql STABLE AS $$ SELECT NULL::integer $$;
COMMENT ON FUNCTION people.department_hold_of(uuid, text) IS
  'V730: the department-change hold of V696 and V702 is released — no student is held, so this answers NULL for everyone; kept for the callers that still name it (people.roll_over_session, V733''s own-session roll-over).';

-- ── 2 · the level reached ──────────────────────────────────────────────────────────────────────────
-- the cohort standing is one set for the level reached (V730) or by the department-change hold (V696), not one the desk set by hand:
-- the reason and the cohort are those of the decision that set it
CREATE FUNCTION people.level_reached_cohort_of(p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM people.cohort_override o
                    WHERE o.student_id = p_student
                      AND EXISTS (SELECT 1 FROM people.cohort_decision d
                                   WHERE d.student_id = p_student AND d.rule IN ('COHORT_LEVEL_REACHED', 'COHORT_DEPARTMENT_CHANGE')
                                     AND d.effective_cohort = o.effective_cohort AND d.reason IS NOT DISTINCT FROM o.reason))
$$;
COMMENT ON FUNCTION people.level_reached_cohort_of(uuid) IS
  'V730: whether the student''s effective cohort is one set for the level reached (V730) or by the department-change hold it replaces (V696) — '
  'false for a cohort the desk set by hand, which is the desk''s.';

CREATE FUNCTION people.align_level_reached(p_student uuid, p_reason text, p_session text DEFAULT NULL, p_refresh boolean DEFAULT true)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s people.student; v_pg boolean; v_cur text; v_ses text; v_final int; v_target int; v_at text; v_m int; v_cohort text; v_ours boolean;
        v_row_ses text; v_row_level int; v_why text; v_out text;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RETURN 'NOT_FOUND'; END IF;
    v_ours := people.level_reached_cohort_of(p_student);
    -- a cohort the desk set by hand is the desk's
    IF NOT v_ours AND EXISTS (SELECT 1 FROM people.cohort_override o WHERE o.student_id = p_student) THEN RETURN 'DESK'; END IF;
    SELECT people.is_postgraduate(s.entry_mode, p.category) INTO v_pg FROM ref.programme p WHERE p.code = s.programme_code;
    v_cur := coalesce(people.student_current_session(s.id), policy.university_current_session());
    -- the session the record is for: the one a roll-over rolls into or a progression is for (they say so), else the latest session
    -- the student is enrolled in after the current one (a correction after the roll-over), else the current session
    v_ses := coalesce(p_session, nullif(current_setting('moaum.level_session', true), ''),
                      (SELECT e.session FROM people.enrolment e
                         JOIN policy.academic_session a ON a.name = e.session JOIN policy.academic_session c ON c.name = v_cur
                        WHERE e.student_id = s.id AND a.starts_on > c.starts_on ORDER BY a.starts_on DESC LIMIT 1),
                      v_cur);
    v_final := coalesce(records.final_level_of(s.id), 400);
    IF NOT coalesce(v_pg, true) AND s.entry_mode IS DISTINCT FROM 'CCE' AND s.current_level IS NOT NULL AND s.entry_level IS NOT NULL
       AND people.counted_sessions(s.entry_session, v_ses) IS NULL THEN
        RETURN 'NO_SESSION';   -- nothing to count from, or a session not on the calendar: left as it is
    END IF;
    IF NOT coalesce(v_pg, true) AND s.entry_mode IS DISTINCT FROM 'CCE' AND s.current_level IS NOT NULL AND s.entry_level IS NOT NULL THEN
        -- the level reached, and the session it is reached in: below the final level, the record in the session it is for; at the
        -- final level — where the record cannot tell a first final year from a spillover year — the first session the register shows
        -- at it, else a level a session on from the last session the register shows below it, never later than the record's
        IF s.current_level < v_final THEN
            v_target := s.current_level; v_at := v_ses;
        ELSE
            v_target := v_final;
            SELECT x.session INTO v_at
              FROM (SELECT r.session FROM registration.course_registration r WHERE r.student_id = s.id AND r.level >= v_final
                    UNION SELECT e.session FROM people.enrolment e WHERE e.student_id = s.id AND e.level >= v_final) x
              JOIN policy.academic_session a ON a.name = x.session
             ORDER BY a.starts_on LIMIT 1;
            IF v_at IS NULL THEN
                SELECT x.session, x.level INTO v_row_ses, v_row_level
                  FROM (SELECT r.session, r.level FROM registration.course_registration r WHERE r.student_id = s.id AND r.level < v_final
                        UNION SELECT e.session, e.level FROM people.enrolment e WHERE e.student_id = s.id AND e.level < v_final) x
                  JOIN policy.academic_session a ON a.name = x.session
                 WHERE people.counted_sessions(x.session, v_ses) >= 0
                 ORDER BY a.starts_on DESC, x.level DESC LIMIT 1;
                IF v_row_ses IS NOT NULL AND v_row_level >= s.entry_level THEN
                    v_at := policy.session_after(policy.effective_session(v_row_ses), (v_final - v_row_level) / 100);
                    IF v_at IS NULL OR coalesce(people.counted_sessions(v_at, v_ses), -1) < 0 THEN v_at := v_ses; END IF;
                END IF;
            END IF;
        END IF;
        -- how many sessions behind the entry cohort the student reaches it
        v_m := CASE WHEN v_at IS NULL OR v_target < s.entry_level THEN NULL
                    ELSE people.counted_sessions(s.entry_session, v_at) - (v_target - s.entry_level) / 100 END;
    END IF;
    IF v_m IS NULL OR v_m < 1 THEN
        -- the record reaches the level the entry cohort reaches, or there is nothing to go by (a final-level record with no register,
        -- read as every spillover student is): no cohort set (one set for the level reached, or by the hold, is lifted)
        IF v_ours THEN
            DELETE FROM people.cohort_override WHERE student_id = p_student;
            INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office, session)
            VALUES (s.id, s.status, s.status, s.entry_session, policy.effective_session(s.entry_session),
                    CASE WHEN EXISTS (SELECT 1 FROM people.cohort_decision d WHERE d.student_id = s.id AND d.rule = 'COHORT_LEVEL_REACHED')
                         THEN 'COHORT_LEVEL_REACHED_LIFTED' ELSE 'COHORT_DEPARTMENT_CHANGE_RELEASED' END,
                    btrim(p_reason), v_actor, v_office, v_ses);
            IF p_refresh THEN PERFORM people.refresh_academic_position(s.id); END IF;
            RETURN 'LIFTED';
        END IF;
        RETURN 'NONE';
    END IF;
    -- the cohort that reaches the level reached in that session
    v_cohort := policy.session_after(policy.effective_session(s.entry_session), v_m);
    IF v_cohort IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_cohort AND a.state <> 'CANCELLED')
       OR people.counted_sessions(v_cohort, v_at) IS DISTINCT FROM (v_target - s.entry_level) / 100 THEN
        RETURN 'NO_SESSION';   -- no session on the calendar to set it at: left as it is
    END IF;
    IF v_ours AND EXISTS (SELECT 1 FROM people.cohort_override o JOIN people.cohort_decision d ON d.student_id = o.student_id
                           AND d.effective_cohort = o.effective_cohort AND d.reason IS NOT DISTINCT FROM o.reason AND d.rule = 'COHORT_LEVEL_REACHED'
                          WHERE o.student_id = p_student AND o.effective_cohort = v_cohort) THEN
        v_out := 'UNCHANGED';
    ELSE
        v_out := CASE WHEN v_ours THEN 'ALIGNED' ELSE 'SET' END;
        v_why := CASE WHEN s.current_level < v_final
                      THEN 'Changed department: continues at the level reached, ' || s.current_level || ' Level in ' || v_ses || ' (V730)'
                      ELSE 'Changed department: reached the final level, ' || v_final || ' Level, in ' || v_at || ' (V730)' END;
        INSERT INTO people.cohort_override (student_id, effective_cohort, reason, set_by, actor_office)
        VALUES (s.id, v_cohort, v_why, v_actor, v_office)
        ON CONFLICT (student_id) DO UPDATE SET effective_cohort = EXCLUDED.effective_cohort, reason = EXCLUDED.reason, set_by = EXCLUDED.set_by,
                                               actor_office = EXCLUDED.actor_office, set_at = now();
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, rule, reason, officer, actor_office, session)
        VALUES (s.id, s.status, s.status, s.entry_session, v_cohort, 'COHORT_LEVEL_REACHED', v_why, v_actor, v_office, v_ses);
    END IF;
    -- the current session keeps the level reached once it closes: an enrolment at the record's level where the student has none for it
    -- (the cohort caps the current session only; a past session is read from its own rows)
    IF v_ses = v_cur AND s.status IN ('ACTIVE', 'PROBATION')
       AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_cur)
       AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = v_cur) THEN
        INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), s.id, v_cur, s.current_level)
        ON CONFLICT (student_id, session) DO NOTHING;
    END IF;
    IF p_refresh AND v_out <> 'UNCHANGED' THEN PERFORM people.refresh_academic_position(s.id); END IF;
    RETURN v_out;
END $$;
COMMENT ON FUNCTION people.align_level_reached(uuid, text, text, boolean) IS
  'V730: a student who changed department reads the level reached. Below the final level that is the record, in the session it is for; at '
  'the final level (where the record cannot tell a first final year from a spillover year) the register says when it was reached — the first '
  'session it shows at the final level, else a level a session on from the last it shows below. Where that is behind the entry cohort the '
  'student is given the effective cohort that reaches exactly it (COHORT_LEVEL_REACHED), so receipts, people.level_in, the academic position, '
  'spillover and the level desk read it and never a year above it, and the current session is pinned by an enrolment at the record''s level '
  'where it has none (a closed session is read from its rows); otherwise none (a cohort set for it is lifted). Never changes the record; a '
  'cohort the desk set by hand is left (DESK). Returns SET, ALIGNED, UNCHANGED, LIFTED, NONE, NO_SESSION or DESK.';

-- the cohort follows the record: an office's level, a transfer, a swap, the roll-over — and a step down an office decides is read everywhere
CREATE FUNCTION people.level_reached_follows()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_dept_changed boolean;
BEGIN
    -- the release aligns every cohort once, at its end
    IF coalesce(current_setting('moaum.level_release', true), '') = 'on' THEN RETURN NULL; END IF;
    IF people.level_reached_cohort_of(NEW.id) THEN
        PERFORM people.align_level_reached(NEW.id, 'The record moved: the level reached followed (V730)');
        RETURN NULL;
    END IF;
    -- no cohort set yet: a change of department; or, for a student who changed department, a step down or a change of what the level
    -- is counted from (the entry, the matric, the status)
    v_dept_changed := (SELECT p.dept_code FROM ref.programme p WHERE p.code = OLD.programme_code)
                      IS DISTINCT FROM (SELECT p.dept_code FROM ref.programme p WHERE p.code = NEW.programme_code);
    IF v_dept_changed
       OR ((NEW.current_level < OLD.current_level OR NEW.entry_level IS DISTINCT FROM OLD.entry_level OR NEW.entry_session IS DISTINCT FROM OLD.entry_session
            OR NEW.matric_no IS DISTINCT FROM OLD.matric_no OR NEW.status IS DISTINCT FROM OLD.status)
           AND people.department_changed(NEW.id)) THEN
        PERFORM people.align_level_reached(NEW.id, CASE WHEN v_dept_changed THEN 'Changed department: continues at the level reached (V730)'
                                                       ELSE 'Stepped down after a change of department: the level reached (V730)' END);
    END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION people.level_reached_follows() IS
  'V730: the cohort set for the level reached follows the record (people.align_level_reached) whenever the level, the programme, the entry, '
  'the matric or the status changes; a change of department — or, for a student who changed department, a step down or a change of what the '
  'level is counted from — sets one where the level reached is behind the entry cohort. The record itself is never changed here.';

-- ── 3 · the release ─────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.department_hold_release (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ran_at             timestamptz NOT NULL DEFAULT now(),
    holds              int NOT NULL,
    records_restored   int NOT NULL,
    rows_restored      int NOT NULL,
    raises_made        int NOT NULL,
    lifted             int NOT NULL,
    level_reached      int NOT NULL,
    left_as_they_were  int NOT NULL,
    detail             jsonb NOT NULL
);
SELECT audit.attach('people.department_hold_release');
COMMENT ON TABLE people.department_hold_release IS
  'V730: the release of the department-change hold, with its counts as it ran — the holds standing, the records it lowered put back, the session '
  'rows put back, the raises the guard had refused made, the holds lifted, those turned into the level reached, and the students left as they were.';

CREATE FUNCTION people.release_department_holds(p_reason text, p_batch text)
RETURNS people.department_hold_release LANGUAGE plpgsql AS $$
DECLARE r record; v_records int := 0; v_rows int := 0; v_raises int := 0; v_lifted int := 0; v_reached int := 0; v_left int := 0;
        v_out text; v_res jsonb; v_asked int; v_held uuid[]; v_ids uuid[] := '{}'; v_outcomes jsonb := '{}'::jsonb; v_run people.department_hold_release;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_OFFICE: levels are corrected by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEVEL_CORRECTION_REASON: a level correction is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    -- the holds standing: V696's cohort, still as it set it
    v_held := ARRAY(SELECT o.student_id FROM people.cohort_override o
                     WHERE EXISTS (SELECT 1 FROM people.cohort_decision d WHERE d.student_id = o.student_id AND d.rule = 'COHORT_DEPARTMENT_CHANGE'
                                     AND d.effective_cohort = o.effective_cohort AND d.reason IS NOT DISTINCT FROM o.reason)
                     ORDER BY o.student_id);

    -- the cohort is aligned once, at the end, not record by record (people.level_reached_follows waits)
    PERFORM set_config('moaum.level_release', 'on', true);
    -- a record the hold lowered, and still lowered, put back — with the session's registrations and enrolment it lowered with it —
    -- whether or not the hold still stands (the cohort desk's removal never put the level back), unless an office set the level since
    FOR r IN
        SELECT DISTINCT ON (d.student_id) d.student_id, d.previous_level, d.new_level, d.session, d.decided_at, s.status, s.entry_session
          FROM people.cohort_decision d JOIN people.student s ON s.id = d.student_id
         WHERE d.rule = 'LEVEL_DEPARTMENT_CHANGE'
         ORDER BY d.student_id, d.decided_at DESC
    LOOP
        CONTINUE WHEN r.previous_level IS NULL OR (SELECT current_level FROM people.student WHERE id = r.student_id) IS DISTINCT FROM r.new_level;
        CONTINUE WHEN EXISTS (SELECT 1 FROM people.cohort_decision x WHERE x.student_id = r.student_id AND x.decided_at > r.decided_at
                                 AND (x.rule IN ('LEVEL_CORRECTION', 'LEVEL_PROGRESS', 'LEVEL_SPILLOVER_YEAR', 'LEVEL_DEPARTMENT_CHANGE_RELEASED')
                                      OR (x.rule = 'COHORT' AND x.reason NOT LIKE 'Cohort override removed:%')));
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, previous_level, new_level,
                                            rule, reason, officer, actor_office, batch_ref, session)
        VALUES (r.student_id, r.status, r.status, r.entry_session, policy.effective_session(r.entry_session), r.new_level, r.previous_level,
                'LEVEL_DEPARTMENT_CHANGE_RELEASED', v_reason, v_actor, v_office, p_batch, r.session);
        UPDATE people.student SET current_level = r.previous_level WHERE id = r.student_id;
        v_records := v_records + 1;
        v_ids := v_ids || r.student_id;
        v_res := people.carry_level_to_session(r.student_id, r.new_level, r.previous_level, r.session);
        v_rows := v_rows + coalesce((v_res->>'registrations')::int, 0) + coalesce((v_res->>'enrolment')::int, 0);
    END LOOP;

    -- a raise the guard refused (V702), and the record still at what it was held at, made
    FOR r IN
        SELECT DISTINCT ON (d.student_id) d.student_id, d.new_level, d.reason, d.session, d.decided_at, s.status, s.entry_session
          FROM people.cohort_decision d JOIN people.student s ON s.id = d.student_id
         WHERE d.rule = 'LEVEL_HELD_DEPARTMENT_CHANGE'
         ORDER BY d.student_id, d.decided_at DESC
    LOOP
        v_asked := substring(r.reason FROM '; ([0-9]{3}) asked for')::int;
        CONTINUE WHEN v_asked IS NULL OR v_asked <= r.new_level OR (SELECT current_level FROM people.student WHERE id = r.student_id) IS DISTINCT FROM r.new_level;
        CONTINUE WHEN EXISTS (SELECT 1 FROM people.cohort_decision x WHERE x.student_id = r.student_id AND x.decided_at > r.decided_at
                                 AND (x.rule IN ('LEVEL_CORRECTION', 'LEVEL_PROGRESS', 'LEVEL_SPILLOVER_YEAR', 'LEVEL_HELD_RELEASED')
                                      OR (x.rule = 'COHORT' AND x.reason NOT LIKE 'Cohort override removed:%')));
        INSERT INTO people.cohort_decision (student_id, previous_status, final_status, previous_cohort, effective_cohort, previous_level, new_level,
                                            rule, reason, officer, actor_office, batch_ref, session)
        VALUES (r.student_id, r.status, r.status, r.entry_session, policy.effective_session(r.entry_session), r.new_level, v_asked,
                'LEVEL_HELD_RELEASED', v_reason || ' — the ' || v_asked || ' Level asked for and held', v_actor, v_office, p_batch, r.session);
        UPDATE people.student SET current_level = v_asked WHERE id = r.student_id;
        v_raises := v_raises + 1;
        v_ids := v_ids || r.student_id;
    END LOOP;

    PERFORM set_config('moaum.level_release', '', true);
    -- every hold lifted, or turned into the level reached where the record is behind the entry cohort (the record is never changed here)
    FOR r IN SELECT DISTINCT x AS student_id FROM unnest(v_held || v_ids) x ORDER BY 1 LOOP
        v_out := people.align_level_reached(r.student_id, v_reason, NULL, false);
        v_outcomes := jsonb_set(v_outcomes, ARRAY[v_out], to_jsonb(coalesce((v_outcomes->>v_out)::int, 0) + 1));
        IF v_out IN ('LIFTED', 'NONE') THEN v_lifted := v_lifted + 1;
        ELSIF v_out IN ('SET', 'ALIGNED', 'UNCHANGED') THEN v_reached := v_reached + 1;
        ELSE v_left := v_left + 1;
        END IF;
    END LOOP;
    PERFORM people.refresh_academic_positions(ARRAY(SELECT DISTINCT x FROM unnest(v_held || v_ids) x));

    INSERT INTO people.department_hold_release (holds, records_restored, rows_restored, raises_made, lifted, level_reached, left_as_they_were, detail)
    VALUES (coalesce(array_length(v_held, 1), 0), v_records, v_rows, v_raises, v_lifted, v_reached, v_left, v_outcomes)
    RETURNING * INTO v_run;
    RETURN v_run;
END $$;
COMMENT ON FUNCTION people.release_department_holds(text, text) IS
  'V730: the department-change hold of V696 released — every record it lowered and still lowered put back with the session''s registrations and '
  'enrolment (LEVEL_DEPARTMENT_CHANGE_RELEASED), every raise the guard refused and still refused made (LEVEL_HELD_RELEASED), unless an office set '
  'the level since; then every hold lifted, or turned into the level reached where the record is behind the entry cohort '
  '(people.align_level_reached). The Academic Office, the Registry or super, with a reason; counted in people.department_hold_release. Safe to '
  'run again: a record put back, a cohort lifted or aligned is not touched twice.';

-- run once, now (the cohort follows the record only after it: the trigger below)
DO $$
DECLARE v people.department_hold_release;
BEGIN
    v := people.release_department_holds('The University''s word of 12 November 2026: a student who changed department continues from the level reached; the hold of V696 released (V730)',
                                         'V730-DEPARTMENT-CHANGE-RELEASED');
    RAISE NOTICE 'V730 department-change hold released on %: % holds; % records and % session rows put back; % raises made; % lifted, % at the level reached, % left as they were (%)',
        current_database(), v.holds, v.records_restored, v.rows_restored, v.raises_made, v.lifted, v.level_reached, v.left_as_they_were, v.detail;
END $$;

-- from here the cohort follows the record
CREATE TRIGGER trg_student_level_reached AFTER UPDATE OF current_level, programme_code, entry_level, entry_session, matric_no, status ON people.student
    FOR EACH ROW WHEN (OLD.current_level IS DISTINCT FROM NEW.current_level OR OLD.programme_code IS DISTINCT FROM NEW.programme_code
                       OR OLD.entry_level IS DISTINCT FROM NEW.entry_level OR OLD.entry_session IS DISTINCT FROM NEW.entry_session
                       OR OLD.matric_no IS DISTINCT FROM NEW.matric_no OR OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION people.level_reached_follows();

-- an old-portal transfer recorded for a student already on the programme (V669, V686: RECORDED) is evidence of the change
CREATE FUNCTION people.level_reached_on_prior_transfer()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(current_setting('moaum.level_release', true), '') <> 'on' AND people.department_changed(NEW.student_id) THEN
        PERFORM people.align_level_reached(NEW.student_id, 'Changed department on the old portal: continues at the level reached (V730)');
    END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION people.level_reached_on_prior_transfer() IS
  'V730: an old-portal transfer recorded (V669, V686) aligns the student to the level reached (people.align_level_reached); never changes the record.';
CREATE TRIGGER trg_prior_transfer_level_reached AFTER INSERT ON people.prior_transfer
    FOR EACH ROW EXECUTE FUNCTION people.level_reached_on_prior_transfer();

COMMIT;
