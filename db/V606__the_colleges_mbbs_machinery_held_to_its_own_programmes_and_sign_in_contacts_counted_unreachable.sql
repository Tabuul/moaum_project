-- V606: the College's MBBS machinery held to the programmes the College runs, and a contact the sign-in help saved counted as no
-- contact on Students We Cannot Reach.
--
--   * The College's own years are MBBS years. V603 held the College's student area and its registration to the programmes the
--     College runs (college.programme_rule, college.runs_programme). Three more of its functions still read every College of
--     Health Sciences student:
--       - college.open_enrolment (V249) opened a College year for any of them;
--       - college.confirm_100 (V285), the Board's 100 Level act, applied the College's 100 Level rule to every College entrant at
--         100 Level, so it would have moved Nursing, Biochemistry or Radiography students to 200 Level (and recorded MBBS
--         progression decisions for them);
--       - college.confirm_decisions (V285) promoted on a decision.
--     Each now asks college.runs_programme. On the live-shaped copy no College year or progression decision is recorded yet, so
--     nothing recorded needs putting right.
--   * Students We Cannot Reach. helpdesk.reach_gaps (V565's text) counts an e-mail or phone the sign-in help saved and nobody has
--     confirmed as no contact: since V599 no notice goes to it. The list (StudentSupportController) reads it the same way.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'V606: the College''s MBBS machinery held to its own programmes; sign-in contacts counted unreachable', true);

CREATE OR REPLACE FUNCTION college.open_enrolment(p_student uuid, p_level integer, p_session text, p_by uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $fn$
DECLARE s people.student; v_id uuid; v_last text; v_prior int; v_kind text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    -- V606: a year of the College's own programmes (MBBS), never of every College of Health Sciences student
    IF NOT college.runs_programme(s.programme_code) THEN
        RAISE EXCEPTION 'COLLEGE_NOT_MBBS: the College opens the years of its own programmes (MBBS); this programme registers on the University''s form'
            USING ERRCODE = '23514';
    END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION', 'ADMITTED') THEN RAISE EXCEPTION 'a student who is % does not enrol', lower(s.status) USING ERRCODE = '23514'; END IF;
    IF p_level < 200 THEN RAISE EXCEPTION '100 Level is the University''s year, registered by semester on its form' USING ERRCODE = '23514'; END IF;
    IF p_level <> s.current_level THEN RAISE EXCEPTION 'the student is at % Level, not %', s.current_level, p_level USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_id FROM college.enrolment WHERE student_id = p_student AND level = p_level AND session = p_session;
    IF FOUND THEN RETURN v_id; END IF;
    IF EXISTS (SELECT 1 FROM college.enrolment e WHERE e.student_id = p_student AND e.state IN ('OPEN', 'RESIT')) THEN
        RAISE EXCEPTION 'the student has a College year still open; it closes by the Board''s decision before another opens' USING ERRCODE = '23514';
    END IF;
    SELECT outcome INTO v_last FROM college.progression_decision
     WHERE student_id = p_student AND from_level = p_level AND state = 'CONFIRMED' ORDER BY session DESC, decided_on DESC LIMIT 1;
    IF v_last = 'APPEAL' THEN RAISE EXCEPTION 'the appeal to Senate is not yet granted' USING ERRCODE = '23514'; END IF;
    IF v_last IN ('WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED') THEN RAISE EXCEPTION 'the record at this level is closed by withdrawal' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_prior FROM college.enrolment WHERE student_id = p_student AND level = p_level;
    v_kind := CASE WHEN v_last = 'REPEAT' THEN 'REPEAT' ELSE 'REGULAR' END;
    INSERT INTO college.enrolment (student_id, level, session, attempt_no, kind, opened_by)
    VALUES (p_student, p_level, p_session, v_prior + 1, v_kind, p_by) RETURNING id INTO v_id;
    INSERT INTO college.enrolment_semester (enrolment_id, ordinal, name, length_weeks, subjects)
    SELECT v_id, t.ordinal, t.name, t.length_weeks, t.subjects FROM college.semester_template t WHERE t.level = p_level ORDER BY t.ordinal;
    RETURN v_id;
END $fn$;

CREATE OR REPLACE FUNCTION college.confirm_100(p_session text, p_minute text)
 RETURNS TABLE(promoted integer, withdrawn integer, waiting integer)
 LANGUAGE plpgsql
AS $fn$
DECLARE r record; d record; np int := 0; nw int := 0; nk int := 0; v_instrument text;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN RAISE EXCEPTION 'the Board acts on a minute, and none was cited' USING ERRCODE = '23514'; END IF;
    v_instrument := 'College Academic Board minute ' || btrim(p_minute) || ' (100 Level, ' || p_session || ')';
    -- V606: the College's 100 Level rule promotes its own programmes' entrants (MBBS) — never a Nursing or Biochemistry student
    FOR r IN SELECT st.id FROM people.student st
              WHERE college.runs_programme(st.programme_code) AND st.current_level = 100 AND st.entry_session = p_session AND st.status IN ('ACTIVE', 'PROBATION', 'ADMITTED')
    LOOP
        SELECT * INTO d FROM college.decide_100(r.id);
        IF d.outcome = 'PROMOTE' THEN
            UPDATE people.student SET current_level = 200 WHERE id = r.id;
            INSERT INTO college.progression_decision (student_id, from_level, session, outcome, carry_overs, rule_ref, minute, state, confirmed_on, confirmed_by)
            VALUES (r.id, 100, p_session, 'PROMOTE', CASE WHEN d.carried IS NULL THEN '{}' ELSE string_to_array(replace(d.carried, ' ', ''), ',') END,
                    'College 100 Level rule: every C-group course at 50 or more' || coalesce('; GST carried: ' || d.carried, ''), btrim(p_minute), 'CONFIRMED', current_date,
                    nullif(current_setting('moaum.actor_id', true), '')::uuid)
            ON CONFLICT (student_id, from_level, session) DO NOTHING;
            INSERT INTO college.carry_over (student_id, code, from_session, note)
            SELECT r.id, upper(btrim(x)), p_session, 'GST carried from 100 Level · ' || v_instrument FROM unnest(string_to_array(coalesce(d.carried, ''), ',')) x WHERE btrim(x) <> ''
            ON CONFLICT (student_id, code) DO NOTHING;
            PERFORM college.tell_student(r.id, 'College Academic Board: 100 Level ' || p_session,
                'The College Academic Board, on its minute ' || btrim(p_minute) || ', confirmed your promotion to 200 Level of the MBBS programme.' || coalesce(E'\nGST course(s) carried over, to be passed before graduation: ' || d.carried, '') || E'\n\nRegister for the 200 Level year on the portal when your fees are cleared.',
                'MOAUM College: you are promoted to 200 Level MBBS. Register on the portal.');
            np := np + 1;
        ELSIF d.outcome = 'WITHDRAW_ADVISED' THEN
            INSERT INTO college.progression_decision (student_id, from_level, session, outcome, rule_ref, minute, state, confirmed_on, confirmed_by)
            VALUES (r.id, 100, p_session, 'WITHDRAW_ADVISED', 'College 100 Level rule: below 50 in ' || coalesce(d.failed, ''), btrim(p_minute), 'CONFIRMED', current_date,
                    nullif(current_setting('moaum.actor_id', true), '')::uuid)
            ON CONFLICT (student_id, from_level, session) DO NOTHING;
            PERFORM people.change_status(r.id, 'WITHDRAWN', v_instrument, current_date, 'Advised to withdraw from the MBBS programme: the College''s 100 Level rule, below 50 in ' || coalesce(d.failed, ''));
            PERFORM college.tell_student(r.id, 'College Academic Board: 100 Level ' || p_session,
                'The College Academic Board, on its minute ' || btrim(p_minute) || ', recorded that you did not meet the College''s 100 Level rule (every C-group course passed at 50 or more, no resit): ' || coalesce(d.failed, '') || '. On the regulations you are advised to withdraw from the MBBS programme; the Registry writes to you.',
                'MOAUM College: the 100 Level rule was not met; the Registry writes to you.');
            nw := nw + 1;
        ELSE
            nk := nk + 1;
        END IF;
    END LOOP;
    RETURN QUERY SELECT np, nw, nk;
END $fn$;

CREATE OR REPLACE FUNCTION college.confirm_decisions(p_exam text, p_session text, p_minute text)
 RETURNS integer
 LANGUAGE plpgsql
AS $fn$
DECLARE e college.professional_exam; d record; n int := 0; who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_hon boolean; v_instrument text;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = upper(p_exam);
    IF NOT FOUND THEN RAISE EXCEPTION 'no such examination %', p_exam USING ERRCODE = '23503'; END IF;
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'the Board confirms on a minute, and none was cited' USING ERRCODE = '23514';
    END IF;
    v_instrument := 'College Academic Board minute ' || btrim(p_minute) || ' (' || e.name || ', ' || p_session || ')';
    FOR d IN SELECT * FROM college.progression_decision WHERE session = p_session AND from_level = e.level AND state = 'PROVISIONAL'
                AND outcome NOT IN ('CARRY_OVER_PENDING', 'MIN_YEARS_PENDING') LOOP   -- a held graduation is confirmed once what holds it is cleared (V285)
        v_hon := CASE WHEN d.outcome = 'GRADUATE' THEN college.honours(d.student_id) END;
        UPDATE college.progression_decision SET state = 'CONFIRMED', confirmed_on = current_date, confirmed_by = who,
               minute = coalesce(minute, btrim(p_minute)), honours = v_hon WHERE id = d.id;
        IF d.outcome = 'RESIT' THEN
            UPDATE college.enrolment SET state = 'RESIT', resit_subjects = d.resit_subjects
             WHERE student_id = d.student_id AND level = e.level AND session = p_session;
        ELSE
            UPDATE college.enrolment SET state = 'CLOSED', closed_on = current_date
             WHERE student_id = d.student_id AND level = e.level AND session = p_session;
        END IF;
        IF d.outcome = 'PROMOTE' THEN
            UPDATE people.student st SET current_level = e.level + 100
             WHERE st.id = d.student_id AND college.runs_programme(st.programme_code);   -- V606: the College's own programmes
        ELSIF d.outcome IN ('WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED') THEN
            PERFORM people.change_status(d.student_id, 'WITHDRAWN', v_instrument, current_date,
                CASE d.outcome WHEN 'WITHDRAW_ADVISED' THEN 'Advised to withdraw from the MBBS programme: ' ELSE 'Required to withdraw from the MBBS programme: ' END || coalesce(d.rule_ref, ''));
        ELSIF d.outcome = 'GRADUATE' THEN
            PERFORM people.change_status(d.student_id, 'GRADUATED', v_instrument, current_date,
                'Passed the Final MBBS' || CASE WHEN v_hon THEN ' with Honours (a distinction in each of the four Professional examinations)' ELSE '' END);
        END IF;
        -- the carry-overs the decision names go on the register (V285): GST and EPS only, cleared when passed
        INSERT INTO college.carry_over (student_id, code, from_session, note)
        SELECT d.student_id, upper(btrim(x)), p_session, 'Carried from ' || e.name || ' · ' || v_instrument
          FROM unnest(coalesce(d.carry_overs, '{}')) x WHERE btrim(x) <> ''
        ON CONFLICT (student_id, code) DO NOTHING;
        PERFORM college.tell_decision(d.student_id, e.code, d.outcome, coalesce(v_hon, false), p_session, btrim(p_minute));
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;

CREATE OR REPLACE FUNCTION helpdesk.reach_gaps(p_agent uuid, p_head boolean)
 RETURNS TABLE(faculty_code text, faculty text, students bigint, no_email bigint, no_phone bigint, neither bigint)
 LANGUAGE sql
 STABLE
AS $fn$
    WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(p_agent, 'VIEW_STUDENT')),
    r AS (
        -- V606: a contact the sign-in help saved and nobody has confirmed reaches no notice (V599), so it is not counted as a contact
        SELECT p.faculty_code,
               nullif(btrim(coalesce(CASE WHEN c.email_pending AND c.email_from_sign_in THEN NULL ELSE c.email END, a.email, '')), '') IS NULL AS no_email,
               nullif(btrim(coalesce(CASE WHEN c.phone_pending AND c.phone_from_sign_in THEN NULL ELSE c.phone END, a.phone, '')), '') IS NULL AS no_phone
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN people.student_contact c ON c.student_id = s.id
          LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id
         WHERE s.duplicate_of IS NULL AND s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED', 'DEFERRED')
           AND (p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments))))
    SELECT r.faculty_code, f.name, count(*), count(*) FILTER (WHERE r.no_email), count(*) FILTER (WHERE r.no_phone),
           count(*) FILTER (WHERE r.no_email AND r.no_phone)
      FROM r LEFT JOIN ref.faculty f ON f.code = r.faculty_code
     GROUP BY r.faculty_code, f.name
     ORDER BY count(*) FILTER (WHERE r.no_email AND r.no_phone) DESC, f.name
$fn$;

COMMIT;
