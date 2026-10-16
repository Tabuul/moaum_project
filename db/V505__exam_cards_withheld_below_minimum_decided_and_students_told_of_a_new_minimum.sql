-- ═══════════════════════════════════════
-- V505 — Examination cards withheld, approved registrations below the minimum decided, and students told of a new minimum
--
--   1 · Who cannot have the examination card, and why. registration.exam_cards_withheld(session, semester) lists every approved
--       registration whose card the card's own rule (registration.exam_card_state, V501) would refuse, with its code and words:
--       a student not in study, a registration with no course, the Bursary's clearance refused, the card not released. The
--       clearance is the card's own (finance.clears_or_null), asked once for each student with an approved registration (some 12 s
--       for the 4,389 of 2025/2026 on the live-shaped copy, against 31 s for the whole register's finance.session_clears); the
--       screen keeps the list a few minutes. registration.remind_exam_cards_withheld tells those students on the
--       notification engine, once a day at most (EXAM_CARD_WITHHELD; no amount in the notice, P9).
--   2 · An approved registration below the minimum that binds it (1,207 on the live-shaped copy, most brought from the old
--       portal) is decided by the Academic Office, the Registry or super, with a reason (registration.load_decision): ACCEPTED as it
--       stands — it leaves the below-minimum list while it carries the same units — or RETURNED to the student, who adds courses
--       and submits again (REG_LOAD_RETURNED). Never a registration with a mark entered, or a locked one.
--   3 · A raised minimum is told to the students it now leaves short. registration.unit_minimum_impact(curriculum, session,
--       semester, units) counts, by status, the registrations a minimum would leave below it — for the Director of ICT before the
--       change is confirmed; registration.tell_unit_minimum_change tells the students whose draft, returned or submitted
--       registration the minimum in force now leaves short (REG_MIN_UNITS_RAISED), once for each minimum. A registration approved
--       earlier is never rewritten and not told.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V505: examination cards withheld, registrations below the minimum decided, students told of a new minimum', true);

-- ── 1 · the examination cards withheld ──
CREATE FUNCTION registration.exam_cards_withheld(p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, faculty_code text,
              level integer, semester integer, code text, reason text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH r AS MATERIALIZED (
        SELECT g.id, g.student_id, g.level, g.semester, s.status AS student_status, s.entry_mode, s.programme_code,
               upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, s.matric_no
          FROM registration.course_registration g JOIN people.student s ON s.id = g.student_id
         WHERE g.session = p_session AND (p_semester IS NULL OR g.semester = p_semester) AND g.status IN ('APPROVED', 'LOCKED')),
    n AS MATERIALIZED (
        SELECT e.registration_id, count(*) AS courses FROM registration.entry e
         WHERE e.registration_id IN (SELECT id FROM r) AND e.status NOT IN ('DROPPED', 'WITHDRAWN') GROUP BY 1),
    -- the Bursary's answer as the card reads it (finance.clears_or_null), once for each student with an approved registration
    cl AS MATERIALIZED (
        SELECT q.student_id, finance.clears_or_null(q.student_id, p_session, 'EXAMINATION') AS clears
          FROM (SELECT DISTINCT r.student_id FROM r) q),
    -- the card released for a semester and stream: on approval where the semester's rule offers it, or with the cards
    rel AS MATERIALIZED (
        SELECT sm.sem, st.stream,
               coalesce((registration.approval_rule(p_session, sm.sem)).card_on_approval, true)
               OR EXISTS (SELECT 1 FROM assessment.exam_session x WHERE x.session = p_session AND x.semester = sm.sem AND x.state <> 'DRAFT'
                             AND x.cards_released_at IS NOT NULL AND x.stream = st.stream) AS released
          FROM (SELECT DISTINCT r.semester AS sem FROM r) sm CROSS JOIN (VALUES ('REGULAR'), ('CCE'), ('PG')) st(stream)),
    j AS (
        SELECT r.*, coalesce(n.courses, 0) AS courses, cl.clears, rel.released
          FROM r LEFT JOIN n ON n.registration_id = r.id LEFT JOIN cl ON cl.student_id = r.student_id
          LEFT JOIN rel ON rel.sem = r.semester
                       AND rel.stream = CASE r.entry_mode WHEN 'CCE' THEN 'CCE' WHEN 'POSTGRADUATE' THEN 'PG' ELSE 'REGULAR' END),
    k AS (
        SELECT j.*,
               CASE WHEN j.student_status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'EXAM_CARD_NOT_IN_STUDY'
                    WHEN j.courses = 0 THEN 'EXAM_CARD_NO_COURSES'
                    WHEN j.clears IS FALSE THEN 'EXAM_CARD_NOT_CLEARED'
                    WHEN NOT coalesce(j.released, true) THEN 'EXAM_CARD_NOT_RELEASED' END AS code
          FROM j)
    SELECT k.id, k.student_id, k.full_name, k.matric_no, p.name, p.dept_code, coalesce(d.faculty_code, p.faculty_code), k.level, k.semester, k.code,
           CASE k.code WHEN 'EXAM_CARD_NOT_IN_STUDY' THEN 'The student record is ' || lower(replace(k.student_status, '_', ' '))
                       WHEN 'EXAM_CARD_NO_COURSES' THEN 'The registration carries no course'
                       WHEN 'EXAM_CARD_NOT_CLEARED' THEN 'Not cleared by the Bursary for the examination'
                       ELSE 'Cards are released with the examination timetable' END
      FROM k
      LEFT JOIN ref.programme p ON p.code = k.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
     WHERE k.code IS NOT NULL;
END $$;
COMMENT ON FUNCTION registration.exam_cards_withheld(text, integer) IS
  'V505: every approved registration of a session (and semester) whose examination card the card''s rule (registration.exam_card_state) refuses, with its code and words — not in study, no course, the Bursary''s clearance refused (finance.clears_or_null, once a student), not released';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('EXAM_CARD_WITHHELD', 'Examination card not yet available',
 'To a student whose course registration is approved but whose examination card the card''s rule withholds (V505)',
 'Your examination card for [SESSION] [SEMESTER] is not yet available',
 E'Dear [FIRST_NAME],\n\nYour course registration for [SESSION] [SEMESTER] is approved, but your examination card is not yet available: [REASON].\n\nSee Examinations in the portal for what to do: [PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your examination card for [SESSION] [SEMESTER] is not yet available: [REASON]. See Examinations in the portal.',
 'Examination card not yet available',
 'Your examination card for [SESSION] [SEMESTER] is not yet available: [REASON]. See Examinations for what to do.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','REASON','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL'),
('REG_LOAD_RETURNED', 'Course registration returned: below the minimum',
 'To the student whose approved registration below the minimum the Academic Office returns (V505)',
 'Your course registration for [SESSION] [SEMESTER] was returned to you',
 E'Dear [FIRST_NAME],\n\nYour course registration for [SESSION] [SEMESTER] carries [UNITS] credit units, below the minimum of [MINIMUM] that applies to you. The Academic Office has returned it to you: [REASON]\n\nAdd courses to reach the minimum and submit it again: [PORTAL_URL]\n\nAcademic Office, [UNIVERSITY_NAME]',
 'MOAUM: your course registration for [SESSION] [SEMESTER] ([UNITS] units) was returned to you: the minimum is [MINIMUM]. Add courses and submit again.',
 'Course registration returned',
 'Your course registration for [SESSION] [SEMESTER] carries [UNITS] credit units, below the minimum of [MINIMUM]. Add courses and submit it again. [REASON]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','UNITS','MINIMUM','REASON','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL'),
('REG_MIN_UNITS_RAISED', 'The minimum course load changed',
 'To a student whose course registration not yet approved a raised minimum course load leaves short (V505)',
 'The minimum course load for [SESSION] [SEMESTER] is now [MINIMUM] credit units',
 E'Dear [FIRST_NAME],\n\nThe minimum course registration load for your curriculum ([CURRICULUM]) in [SESSION] [SEMESTER] is now [MINIMUM] credit units. Your registration carries [UNITS]. Add courses to reach the minimum (through add and drop if you have already submitted it): [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 'MOAUM: the minimum course load for [SESSION] [SEMESTER] ([CURRICULUM]) is now [MINIMUM] units; your registration carries [UNITS]. Add courses (add and drop if already submitted).',
 'The minimum course load changed',
 'The minimum course registration load for [CURRICULUM] in [SESSION] [SEMESTER] is now [MINIMUM] credit units; your registration carries [UNITS]. Add courses to reach it, through add and drop if you have already submitted.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','CURRICULUM','MINIMUM','UNITS','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL');

CREATE FUNCTION registration.remind_exam_cards_withheld(p_session text, p_semester integer, p_code text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); x record; n int := 0;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('records', 'bursar', 'registrar', 'dregistrar', 'academic', 'super') THEN
        RAISE EXCEPTION 'EXAM_CARD_REMIND_OFFICE: the students whose cards are withheld are reminded by Exams & Records, the Bursary or the Registry' USING ERRCODE = '42501';
    END IF;
    FOR x IN SELECT * FROM registration.exam_cards_withheld(p_session, p_semester) w
              WHERE (p_code IS NULL OR w.code = p_code) AND w.code <> 'EXAM_CARD_NOT_IN_STUDY'
    LOOP
        PERFORM platform.tell_student(x.student_id, 'EXAM_CARD_WITHHELD', NULL,
            jsonb_build_object('SESSION', p_session, 'SEMESTER', CASE x.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END,
                               'REASON', CASE x.code WHEN 'EXAM_CARD_NOT_CLEARED' THEN 'the Bursary has not yet cleared you for the examination; settle the fees the scheme requires'
                                                     WHEN 'EXAM_CARD_NO_COURSES' THEN 'your registration carries no course'
                                                     ELSE 'cards are released with the examination timetable' END),
            'EXAM_CARD_WITHHELD:' || x.registration_id || ':' || x.code || ':' || current_date);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION registration.remind_exam_cards_withheld(text, integer, text) IS
  'V505: tells each student whose examination card is withheld (of one code, or all but those not in study) why, once a day at most; returns how many were told';

-- ── 2 · approved registrations below the minimum, decided ──
CREATE TABLE registration.load_decision (
    registration_id uuid PRIMARY KEY REFERENCES registration.course_registration (id) ON DELETE CASCADE,
    decision        text NOT NULL CHECK (decision IN ('ACCEPTED', 'RETURNED')),
    units           integer NOT NULL,
    min_units       integer NOT NULL,
    reason          text NOT NULL CHECK (length(btrim(reason)) >= 10),
    decided_by      uuid NULL,
    decided_office  text NULL REFERENCES ref.office (code),
    decided_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE registration.load_decision IS
  'V505: the Academic Office''s decision on a registration below the minimum that binds it — ACCEPTED as it stands (while it carries the same units), or RETURNED to the student — with the units and minimum at the time and the reason';
SELECT audit.attach('registration.load_decision');

CREATE FUNCTION registration.decide_below_minimum(p_registration uuid, p_decision text, p_reason text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_reason text := btrim(coalesce(p_reason, ''));
        v_decision text := upper(btrim(coalesce(p_decision, ''))); lim record; v_units int;
BEGIN
    IF v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'REG_LOAD_OFFICE: a registration below the minimum is decided by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF v_decision NOT IN ('ACCEPTED', 'RETURNED') THEN
        RAISE EXCEPTION 'REG_LOAD_DECISION: the decision is ACCEPTED or RETURNED' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'REG_LOAD_REASON: the decision states its reason (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_LOAD_NOT_FOUND: no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status = 'LOCKED' THEN
        RAISE EXCEPTION 'REG_LOAD_LOCKED: a locked registration is examination history and is not decided again' USING ERRCODE = '23514';
    END IF;
    IF r.status NOT IN ('SUBMITTED', 'APPROVED') THEN
        RAISE EXCEPTION 'REG_LOAD_STATUS: only a submitted or approved registration is decided; this one is %', lower(r.status) USING ERRCODE = '23514';
    END IF;
    v_units := registration.units_of(r.id);
    SELECT * INTO lim FROM registration.unit_rule(r.student_id, r.level, r.session, r.semester);
    IF NOT FOUND OR v_units >= lim.min_units THEN
        RAISE EXCEPTION 'REG_LOAD_NOT_BELOW: the registration carries % units, not below the minimum of %', v_units, lim.min_units USING ERRCODE = '23514';
    END IF;
    IF v_decision = 'RETURNED' THEN
        IF EXISTS (SELECT 1 FROM registration.entry e JOIN assessment.score_sheet sh ON sh.offering_id = e.offering_id
                     JOIN assessment.score sc ON sc.sheet_id = sh.id AND sc.student_id = r.student_id
                    WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) THEN
            RAISE EXCEPTION 'REG_LOAD_MARKED: a mark is entered against a course of this registration; it is examination history and is not returned' USING ERRCODE = '23514';
        END IF;
        UPDATE registration.course_registration SET status = 'RETURNED', returned_comment = v_reason, approved_at = NULL, approved_by = NULL, approval_mode = NULL
         WHERE id = r.id;
        UPDATE registration.entry SET status = 'REGISTERED' WHERE registration_id = r.id AND status = 'APPROVED';
        UPDATE registration.approval_review SET cleared_at = now() WHERE registration_id = r.id AND cleared_at IS NULL;
        PERFORM platform.tell_student(r.student_id, 'REG_LOAD_RETURNED', NULL,
            jsonb_build_object('SESSION', r.session, 'SEMESTER', CASE r.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END,
                               'UNITS', v_units, 'MINIMUM', lim.min_units, 'REASON', v_reason),
            'REG_LOAD_RETURNED:' || r.id || ':' || floor(extract(epoch FROM now()))::bigint);
    END IF;
    INSERT INTO registration.load_decision (registration_id, decision, units, min_units, reason, decided_by, decided_office)
    VALUES (r.id, v_decision, v_units, lim.min_units, v_reason, v_actor, (SELECT o.code FROM ref.office o WHERE o.code = v_office))
    ON CONFLICT (registration_id) DO UPDATE SET decision = EXCLUDED.decision, units = EXCLUDED.units, min_units = EXCLUDED.min_units, reason = EXCLUDED.reason,
        decided_by = EXCLUDED.decided_by, decided_office = EXCLUDED.decided_office, decided_at = now();
    RETURN v_decision;
END $$;
COMMENT ON FUNCTION registration.decide_below_minimum(uuid, text, text) IS
  'V505: the Academic Office''s (or the Registry''s) decision on a submitted or approved registration below the minimum that binds it: ACCEPTED as it stands, or RETURNED to the student (never a locked one, or one with a mark entered), with a reason; the student told of a return';

-- the below-minimum list leaves out a registration accepted as it stands while it carries the units it was accepted with
CREATE OR REPLACE FUNCTION registration.below_minimum(p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, level integer, semester integer,
              status text, curriculum text, basis text, min_units integer, max_units integer, units integer)
LANGUAGE sql STABLE AS $$
    WITH r AS MATERIALIZED (
        SELECT g.id, g.student_id, g.level, g.semester, g.status, coalesce(sum(e.units), 0)::int AS units
          FROM registration.course_registration g
          JOIN registration.entry e ON e.registration_id = g.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
         WHERE g.session = p_session AND (p_semester IS NULL OR g.semester = p_semester)
         GROUP BY g.id),
    -- only a registration under the highest floor that could bind anyone is judged one by one
    top AS (SELECT greatest((SELECT max(min_units) FROM registration.unit_minimum), (SELECT max(min_units) FROM policy.level_limit),
                            (SELECT max(min_units) FROM policy.route_level_limit)) AS m),
    c AS MATERIALIZED (
        SELECT r.* FROM r, top WHERE r.units < top.m
           AND NOT EXISTS (SELECT 1 FROM registration.load_decision d WHERE d.registration_id = r.id AND d.decision = 'ACCEPTED' AND d.units = r.units))
    SELECT c.id, c.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), s.matric_no, p.name, p.dept_code,
           c.level, c.semester, c.status, u.curriculum, u.basis, u.min_units, u.max_units, c.units
      FROM c
      JOIN people.student s ON s.id = c.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      CROSS JOIN LATERAL registration.unit_rule(c.student_id, c.level, p_session, c.semester) u
     WHERE c.units < u.min_units
$$;
COMMENT ON FUNCTION registration.below_minimum(text, integer) IS
  'V495/V505: the course registrations of a session (and semester) carrying fewer units than the minimum that binds the student — a draft that cannot be submitted yet, or one approved before (never rewritten) — less one the Academic Office accepted as it stands while it carries the same units';

-- ── 3 · a new minimum: who it leaves short, and telling them ──
-- the registrations a curriculum's rule for a session (and semester), or its standing rule, reaches: those of the curriculum's
-- undergraduates in the session(s) and semester(s) that read that rule
CREATE FUNCTION registration.unit_minimum_reach(p_curriculum text, p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, session text, semester integer, level integer, status text, units integer)
LANGUAGE sql STABLE AS $$
    WITH ses AS (
        SELECT a.name FROM policy.academic_session a
         WHERE CASE WHEN p_session IS NOT NULL THEN a.name = p_session
                    -- the standing rule reaches the current session and later ones that state no rule of their own
                    ELSE a.name >= coalesce(policy.university_current_session(), '')
                         AND NOT EXISTS (SELECT 1 FROM registration.unit_minimum u WHERE u.curriculum = upper(p_curriculum) AND u.session = a.name AND u.semester IS NULL) END)
    SELECT g.id, g.student_id, g.session, g.semester, g.level, g.status, registration.units_of(g.id)
      FROM registration.course_registration g
      JOIN ses ON ses.name = g.session
      JOIN people.student s ON s.id = g.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
     WHERE s.curriculum_version = upper(p_curriculum) AND s.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AND pr.category IS DISTINCT FROM 'POST GRADUATE'
       AND (p_semester IS NULL OR g.semester = p_semester)
       -- a semester with a rule of its own reads that one, not a session's or the standing rule
       AND (p_semester IS NOT NULL OR NOT EXISTS (SELECT 1 FROM registration.unit_minimum u WHERE u.curriculum = upper(p_curriculum)
                                                     AND u.session = g.session AND u.semester = g.semester))
       AND g.status IN ('DRAFT', 'RETURNED', 'SUBMITTED', 'APPROVED', 'LOCKED')
$$;
COMMENT ON FUNCTION registration.unit_minimum_reach(text, text, integer) IS
  'V505: the course registrations a curriculum''s minimum for a session (and semester), or its standing rule, reaches — the curriculum''s undergraduates in the sessions and semesters that read that rule';

CREATE FUNCTION registration.unit_minimum_impact(p_curriculum text, p_session text, p_semester integer, p_min integer)
RETURNS TABLE(status text, registrations integer)
LANGUAGE sql STABLE AS $$
    SELECT x.status, count(*)::int
      FROM registration.unit_minimum_reach(p_curriculum, p_session, p_semester) x
      -- the curriculum's minimum binds only where no SIWES or CCE load does
      CROSS JOIN LATERAL registration.unit_rule(x.student_id, x.level, x.session, x.semester) u
     WHERE x.units < p_min AND u.basis IN ('CURRICULUM', 'LEVEL')
     GROUP BY x.status
     ORDER BY x.status
$$;
COMMENT ON FUNCTION registration.unit_minimum_impact(text, text, integer, integer) IS
  'V505: by status, the registrations a curriculum''s minimum of p_min for a session (and semester), or its standing rule, would leave below it — read before the change is confirmed';

CREATE FUNCTION registration.tell_unit_minimum_change(p_curriculum text, p_session text, p_semester integer)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE x record; n int := 0;
BEGIN
    FOR x IN
        SELECT r.*, u.min_units, u.curriculum
          FROM registration.unit_minimum_reach(p_curriculum, p_session, p_semester) r
          CROSS JOIN LATERAL registration.unit_rule(r.student_id, r.level, r.session, r.semester) u
         WHERE r.status IN ('DRAFT', 'RETURNED', 'SUBMITTED') AND u.basis = 'CURRICULUM' AND r.units < u.min_units
    LOOP
        PERFORM platform.tell_student(x.student_id, 'REG_MIN_UNITS_RAISED', NULL,
            jsonb_build_object('SESSION', x.session, 'SEMESTER', CASE x.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END,
                               'CURRICULUM', x.curriculum, 'MINIMUM', x.min_units, 'UNITS', x.units),
            'REG_MIN_UNITS_RAISED:' || x.registration_id || ':' || x.min_units);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION registration.tell_unit_minimum_change(text, text, integer) IS
  'V505: tells each student whose draft, returned or submitted registration the curriculum''s minimum in force now leaves short, once for each minimum; a registration approved earlier is not told (nor rewritten); returns how many were told';

COMMIT;
