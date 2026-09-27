-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V285 — every College policy enforced, configurable and told
--
--   The College's rules were in its tables (V245, V248): attendance by phase and by block, the
--   pass mark and weights of each subject, the resit window, the distinction mark, the carry-over
--   rule, the minimum years, the 100 Level rule. Some were read for display and never applied.
--   Now each one acts:
--   · attendance — the strictest rule that reaches the subject bars the candidate: the examination's
--     own minimum, the phase's (75% preclinical, 70% clinical) and a block's (Surgery 80%);
--   · the distinction mark and honours read the programme rule, not a literal;
--   · a resit is recorded only within the resit window after the first attempt;
--   · the carry-overs a decision names are written to the register (GST and EPS only), and the
--     Final is held — CARRY_OVER_PENDING — until they are cleared; graduation also waits on the
--     minimum years of study — MIN_YEARS_PENDING;
--   · the College's 100 Level rule has its Board act: college.confirm_100 promotes to 200 or
--     records the advice to withdraw on the Board's minute;
--   · the CA of a subject may be composed from the assessment items collected during the year,
--     and an item flagged as an eligibility gate must have its score before the candidate sits;
--   · a year whose calendar is not dated does not take results;
--   · every Board decision, appeal and 100 Level act is told to the student.
--   The thresholds are edited on the College Rules desk (the API), on the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'collegesecretary', true),
       set_config('moaum.reason', 'V285: every College policy enforced, configurable and told', true);

-- ── 1 · attendance: the strictest rule that reaches the subject ──────────────────────────────
CREATE OR REPLACE FUNCTION college.min_attendance_for(p_subject uuid)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT greatest(
             e.min_attendance_pct,
             (SELECT max(a.min_pct) FROM college.attendance_rule a JOIN college.level l ON l.level = e.level WHERE a.scope = 'PHASE' AND a.phase = l.phase),
             (SELECT max(a.min_pct) FROM college.attendance_rule a JOIN college.block b ON b.id = a.block_id
               WHERE a.scope = 'BLOCK' AND (lower(b.name) = lower(s.name) OR position(lower(b.name) IN lower(coalesce(s.departments, ''))) > 0)))
      FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id
     WHERE s.id = p_subject
$fn$;
COMMENT ON FUNCTION college.min_attendance_for(uuid) IS 'The attendance a candidate needs to sit a subject: the strictest of the examination''s minimum, the phase rule and any block rule that names the subject (V285).';

DROP FUNCTION IF EXISTS college.judge(uuid, numeric, numeric, numeric, numeric);
CREATE FUNCTION college.judge(p_subject uuid, p_ca numeric, p_exam numeric, p_clinical numeric, p_attendance numeric)
RETURNS TABLE(passed boolean, barred boolean, min_attendance integer) LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_ca IS NULL AND p_exam IS NULL THEN NULL
                WHEN m.pct IS NOT NULL AND p_attendance IS NOT NULL AND p_attendance < m.pct THEN false
                ELSE college.passes(p_subject, p_ca, p_exam, p_clinical) END,
           m.pct IS NOT NULL AND p_attendance IS NOT NULL AND p_attendance < m.pct,
           m.pct
      FROM (SELECT college.min_attendance_for(p_subject) AS pct) m
$fn$;

-- ── 2 · honours and distinction from the programme rule ──────────────────────────────────────
CREATE OR REPLACE FUNCTION college.honours(p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT (SELECT count(DISTINCT e.code)
              FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id JOIN college.professional_exam e ON e.id = s.exam_id
              JOIN people.student st ON st.id = r.student_id LEFT JOIN college.programme_rule pr ON pr.programme_code = st.programme_code
             WHERE r.student_id = p_student AND r.passed AND e.code IN ('PE1','PE2','PE3','PE4') AND r.total >= coalesce(pr.distinction_mark, 70)) = 4
$fn$;

-- ── 3 · the resit window ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION college.resit_window_open(p_student uuid, p_subject uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT r.decided_on + make_interval(months => coalesce(pr.resit_window_months, e.resit_window_months, 3)) >= current_date
                       FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id JOIN college.professional_exam e ON e.id = s.exam_id
                       JOIN people.student st ON st.id = r.student_id LEFT JOIN college.programme_rule pr ON pr.programme_code = st.programme_code
                      WHERE r.student_id = p_student AND r.subject_id = p_subject AND r.session = p_session AND r.attempt = 'FIRST' AND r.decided_on IS NOT NULL), true)
$fn$;
COMMENT ON FUNCTION college.resit_window_open(uuid, uuid, text) IS 'Whether a resit may still be recorded: within the resit window (programme rule, else the examination''s) after the first attempt was decided (V285).';

-- ── 4 · graduation: the minimum years, the carry-overs ───────────────────────────────────────
CREATE OR REPLACE FUNCTION college.min_years_met(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((left(p_session, 4)::int - left(s.entry_session, 4)::int + 1)
                    >= CASE WHEN s.entry_mode = 'DIRECT_ENTRY' THEN coalesce(r.min_years_de, 5) ELSE coalesce(r.min_years_utme, 6) END, true)
      FROM people.student s LEFT JOIN college.programme_rule r ON r.programme_code = s.programme_code WHERE s.id = p_student
$fn$;

ALTER TABLE college.progression_decision DROP CONSTRAINT IF EXISTS ck_college_decision;
ALTER TABLE college.progression_decision ADD CONSTRAINT ck_college_decision
    CHECK (outcome IN ('PROMOTE', 'RESIT', 'REPEAT', 'WITHDRAW_ADVISED', 'WITHDRAW_REQUIRED', 'APPEAL', 'GRADUATE', 'CARRY_OVER_PENDING', 'MIN_YEARS_PENDING'));

CREATE OR REPLACE FUNCTION college.clear_carry_over(p_student uuid, p_code text, p_minute text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN RAISE EXCEPTION 'a carry-over is cleared on the Board''s minute, and none was cited' USING ERRCODE = '23514'; END IF;
    UPDATE college.carry_over SET cleared_on = current_date, note = concat_ws(' · ', note, 'Cleared: ' || btrim(p_minute))
     WHERE student_id = p_student AND upper(code) = upper(p_code) AND cleared_on IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n = 0 THEN RAISE EXCEPTION 'no open carry-over % for this student', p_code USING ERRCODE = '23503'; END IF;
    -- a Final held on it is decided again
    PERFORM college.apply_provisional(p_student, 'PE4', d.session)
       FROM (SELECT session FROM college.progression_decision WHERE student_id = p_student AND from_level = 600 AND outcome = 'CARRY_OVER_PENDING' ORDER BY session DESC LIMIT 1) d;
    RETURN n;
END $fn$;

-- ── 5 · the CA composed from the year's assessment items; the gates ──────────────────────────
CREATE OR REPLACE FUNCTION college.ca_from_items(p_student uuid, p_subject uuid)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    WITH latest AS (
        SELECT DISTINCT ON (sc.item_id) sc.item_id, sc.score FROM college.assessment_score sc JOIN college.assessment_item i ON i.id = sc.item_id
         WHERE sc.student_id = p_student AND i.subject_id = p_subject ORDER BY sc.item_id, sc.attempt_no DESC, sc.scored_on DESC),
    w AS (SELECT sum(i.weight_within_ca * l.score / nullif(i.max_score, 0)) AS got, sum(i.weight_within_ca) AS of_w
            FROM latest l JOIN college.assessment_item i ON i.id = l.item_id)
    SELECT CASE WHEN w.of_w IS NULL OR w.of_w = 0 THEN NULL ELSE round(s.ca_weight * w.got / w.of_w, 2) END
      FROM w CROSS JOIN college.exam_subject s WHERE s.id = p_subject
$fn$;
COMMENT ON FUNCTION college.ca_from_items(uuid, uuid) IS 'The subject''s CA composed from the assessment items scored during the year, weighted within the CA and scaled to the subject''s CA weight; NULL when nothing was scored (V285).';

CREATE OR REPLACE FUNCTION college.gates_missing(p_student uuid, p_subject uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT string_agg(i.name, ', ' ORDER BY i.name) FROM college.assessment_item i
     WHERE i.subject_id = p_subject AND i.eligibility_gate
       AND NOT EXISTS (SELECT 1 FROM college.assessment_score sc WHERE sc.item_id = i.id AND sc.student_id = p_student)
$fn$;

-- ── 6 · a year whose calendar is not dated takes no results ──────────────────────────────────
CREATE OR REPLACE FUNCTION college.year_reached_final(p_level integer, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT s.starts_on <= current_date FROM college.semester s
                      WHERE s.level = p_level AND s.session = p_session AND s.starts_on IS NOT NULL
                      ORDER BY s.ordinal DESC LIMIT 1), false)
$fn$;
COMMENT ON FUNCTION college.year_reached_final(integer, text) IS 'Whether a level''s year in a session has reached its final semester by the College calendar; false until the calendar is dated (V285).';

-- ── 7 · the College tells its students ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION college.tell_student(p_student uuid, p_subject text, p_body text, p_sms text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE reach record;
BEGIN
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, p_subject, p_body || E'\n\nCollege of Health Sciences, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', p_student);
    IF p_sms IS NOT NULL THEN PERFORM platform.queue_notice('SMS', reach.phone, p_subject, p_sms, 'student', p_student); END IF;
END $fn$;

CREATE OR REPLACE FUNCTION college.tell_decision(p_student uuid, p_exam text, p_outcome text, p_honours boolean, p_session text, p_minute text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE e college.professional_exam; subj text; nxt text;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = p_exam;
    SELECT string_agg(s.name, ', ' ORDER BY s.name) INTO subj FROM college.progression_decision d JOIN college.exam_subject s ON s.id = ANY (d.resit_subjects)
     WHERE d.student_id = p_student AND d.from_level = e.level AND d.session = p_session;
    nxt := CASE p_outcome
        WHEN 'PROMOTE' THEN 'You passed the ' || e.name || ' and are promoted to ' || (e.level + 100) || ' Level. Register for the year on the portal when your fees are cleared.'
        WHEN 'RESIT' THEN 'You are to resit ' || coalesce(subj, 'the failed subject(s)') || ' of the ' || e.name || ' within ' || e.resit_window_months || ' months, with fresh continuous assessment. The resit registers on the portal.'
        WHEN 'REPEAT' THEN 'You are to repeat ' || e.level || ' Level and sit the ' || e.name || ' again, with fresh continuous assessment.'
        WHEN 'WITHDRAW_ADVISED' THEN 'On the College''s regulations you are advised to withdraw from the MBBS programme. The Registry writes to you on the Board''s minute.'
        WHEN 'WITHDRAW_REQUIRED' THEN 'On the College''s regulations you are required to withdraw from the MBBS programme. The Registry writes to you on the Board''s minute.'
        WHEN 'APPEAL' THEN 'You did not pass the Final MBBS at this attempt; the regulations allow an appeal to Senate for a fourth and final attempt. Write to the Provost through the College Secretary.'
        WHEN 'GRADUATE' THEN 'Congratulations: you passed the Final MBBS' || CASE WHEN p_honours THEN ' with Honours' ELSE '' END || '. The Registry proceeds to your graduation and induction.'
        ELSE p_outcome END;
    PERFORM college.tell_student(p_student, 'College Academic Board: ' || e.name || ' ' || p_session,
        'The College Academic Board, on its minute ' || p_minute || ', confirmed your result in the ' || e.name || ' for ' || p_session || '.' || E'\n\n' || nxt,
        'MOAUM College: ' || e.name || ' ' || p_session || ' - ' || replace(lower(p_outcome), '_', ' ') || '. See the portal.');
END $fn$;

-- ── 8 · the 100 Level rule has its Board act ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION college.confirm_100(p_session text, p_minute text)
RETURNS TABLE(promoted integer, withdrawn integer, waiting integer) LANGUAGE plpgsql AS $fn$
DECLARE r record; d record; np int := 0; nw int := 0; nk int := 0; v_instrument text;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN RAISE EXCEPTION 'the Board acts on a minute, and none was cited' USING ERRCODE = '23514'; END IF;
    v_instrument := 'College Academic Board minute ' || btrim(p_minute) || ' (100 Level, ' || p_session || ')';
    FOR r IN SELECT st.id FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
              WHERE f.college_code = 'CHS' AND st.current_level = 100 AND st.entry_session = p_session AND st.status IN ('ACTIVE', 'PROBATION', 'ADMITTED')
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
COMMENT ON FUNCTION college.confirm_100(text, text) IS 'The Board''s act on the College''s 100 Level rule for a session''s entrants: promotion to 200 Level with GST carried, or the advice to withdraw, on its minute; students with results still unpublished wait (V285).';

-- ── 9 · the rules, patched ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION college.decide(p_student uuid, p_exam text, p_session text)
 RETURNS TABLE(outcome text, failed integer, n_subjects integer, latest_attempt text, failed_subjects uuid[], failed_names text, rule_ref text)
 LANGUAGE plpgsql
 STABLE
AS $fn$
DECLARE e college.professional_exam; n int; have int; nfail int; la text; fs uuid[]; fn text; o text;
BEGIN
    SELECT * INTO e FROM college.professional_exam WHERE code = upper(p_exam);
    IF NOT FOUND THEN RETURN; END IF;
    SELECT count(*) INTO n FROM college.exam_subject s WHERE s.exam_id = e.id;
    WITH latest AS (
        SELECT DISTINCT ON (r.subject_id) r.subject_id, s.name, r.attempt, r.passed
          FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id
         WHERE r.student_id = p_student AND r.session = p_session AND s.exam_id = e.id AND r.passed IS NOT NULL
         ORDER BY r.subject_id, CASE r.attempt WHEN 'FIRST' THEN 1 WHEN 'RESIT' THEN 2 WHEN 'REPEAT' THEN 3 ELSE 4 END DESC)
    SELECT count(*), count(*) FILTER (WHERE NOT l.passed),
           (SELECT l2.attempt FROM latest l2 ORDER BY CASE l2.attempt WHEN 'FIRST' THEN 1 WHEN 'RESIT' THEN 2 WHEN 'REPEAT' THEN 3 ELSE 4 END DESC LIMIT 1),
           coalesce(array_agg(l.subject_id ORDER BY l.name) FILTER (WHERE NOT l.passed), '{}'),
           string_agg(l.name, ', ' ORDER BY l.name) FILTER (WHERE NOT l.passed)
      INTO have, nfail, la, fs, fn FROM latest l;
    IF have < n THEN
        RETURN QUERY SELECT NULL::text, nfail, n, coalesce(la, 'FIRST'), fs, fn, NULL::text; RETURN;
    END IF;
    o := CASE WHEN nfail = 0 THEN CASE WHEN e.level = 600 THEN 'GRADUATE' ELSE 'PROMOTE' END
              WHEN la = 'RESIT' THEN 'REPEAT'
              WHEN la = 'SENATE_APPEAL' THEN 'WITHDRAW_REQUIRED'
              WHEN la = 'REPEAT' THEN CASE WHEN e.appeal_to_senate THEN 'APPEAL'
                                           WHEN e.code IN ('CPE','PE1') THEN 'WITHDRAW_ADVISED' ELSE 'WITHDRAW_REQUIRED' END
              ELSE college.next_attempt(e.code, nfail, n) END;
    -- the programme's own rules on graduation (V285): no carry-over outstanding, and the minimum years of study met
    IF o = 'GRADUATE' THEN
        IF EXISTS (SELECT 1 FROM college.carry_over c WHERE c.student_id = p_student AND c.cleared_on IS NULL) THEN o := 'CARRY_OVER_PENDING';
        ELSIF NOT college.min_years_met(p_student, p_session) THEN o := 'MIN_YEARS_PENDING';
        END IF;
    END IF;
    RETURN QUERY SELECT o, nfail, n, la, fs, fn,
        CASE o WHEN 'PROMOTE' THEN 'Passed every subject at 50 or more' || CASE WHEN la = 'RESIT' THEN ', at the resit' ELSE '' END
               WHEN 'GRADUATE' THEN 'Passed the Final MBBS'
               WHEN 'CARRY_OVER_PENDING' THEN 'Passed the Final MBBS; graduation waits on the carry-over(s) still owed: '
                    || (SELECT string_agg(c.code, ', ' ORDER BY c.code) FROM college.carry_over c WHERE c.student_id = p_student AND c.cleared_on IS NULL)
                    || ' — ' || coalesce((SELECT r.carry_over_note FROM college.programme_rule r JOIN people.student st ON st.programme_code = r.programme_code WHERE st.id = p_student), '')
               WHEN 'MIN_YEARS_PENDING' THEN 'Passed the Final MBBS; graduation waits on the minimum years of study the programme rule states'
               ELSE e.name || ': ' || e.on_failure END;
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
              FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
             WHERE st.id = d.student_id AND p.code = st.programme_code AND f.college_code = 'CHS';
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

CREATE OR REPLACE FUNCTION college.grant_appeal(p_student uuid, p_session text, p_minute text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $fn$
DECLARE v_last text; v_prior int; v_id uuid;
BEGIN
    SELECT outcome INTO v_last FROM college.progression_decision
     WHERE student_id = p_student AND from_level = 600 AND state = 'CONFIRMED' ORDER BY session DESC, decided_on DESC LIMIT 1;
    IF v_last IS DISTINCT FROM 'APPEAL' THEN
        RAISE EXCEPTION 'no appeal stands for this student: the last confirmed decision at 600 Level is %', coalesce(v_last, 'none') USING ERRCODE = '23514';
    END IF;
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN RAISE EXCEPTION 'Senate''s approval is recorded on its minute, and none was cited' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_prior FROM college.enrolment WHERE student_id = p_student AND level = 600;
    INSERT INTO college.enrolment (student_id, level, session, attempt_no, kind)
    VALUES (p_student, 600, p_session, v_prior + 1, 'APPEAL')
    ON CONFLICT (student_id, level, session) DO UPDATE SET kind = 'APPEAL', state = 'OPEN', attempt_no = EXCLUDED.attempt_no
    RETURNING id INTO v_id;
    UPDATE college.progression_decision SET minute = coalesce(minute, '') || ' · Senate: ' || btrim(p_minute)
     WHERE student_id = p_student AND from_level = 600 AND state = 'CONFIRMED' AND outcome = 'APPEAL';
    PERFORM college.tell_student(p_student, 'Senate has approved your appeal: a fourth and final attempt at the Final MBBS',
        'Senate approved your appeal on its minute ' || btrim(p_minute) || '. A fourth and final attempt at the 4th Professional (Final) MBBS is open to you in ' || p_session || '; register for the year on the portal when your fees are cleared.',
        'MOAUM: Senate approved your appeal; a final attempt at the Final MBBS is open to you in ' || p_session || '.');
    RETURN v_id;
END $fn$;

COMMIT;
