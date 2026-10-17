-- ═══════════════════════════════════════
-- V508 — Overload approval: the student asks, the Head of Department grants a higher maximum for one semester
--
--   A registration above the maximum is refused "obtain an overload approval from the Head of Department", and no such approval
--   existed (PRD FR-REG-07): a final-year student with carry-overs met a dead end. Now:
--   · registration.overload_request — a student's request for a higher maximum in one session and semester, with the reason;
--     REQUESTED, then GRANTED (with the ceiling granted, which may be lower than asked) or REFUSED by the Head of Department of the
--     student's department (super as break-glass), with a reason; WITHDRAWN by the student while it waits. One live request (waiting
--     or granted) for a student and semester.
--   · registration.overload_policy — the Academic Office's rule (the Registry, the Directorate of ICT or super may set it too):
--     whether students may ask, and how far above the maximum a grant may go (6 credit units unless set).
--   · registration.unit_rule is now the rule of V495/V503 (kept as registration.unit_rule_base) with the semester's granted ceiling
--     as its maximum. Every check that reads the maximum — the submission, Add Other Course, add and drop, ICT Support's override,
--     the office's approval and the student's screen — honours a grant without a change of its own. A SIWES semester keeps exactly
--     the SIWES course; the probation ceiling is not lifted (a student on probation does not ask).
--   · The Head of Department is told of a request; the student of the decision (OVERLOAD_REQUESTED, OVERLOAD_GRANTED,
--     OVERLOAD_REFUSED).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V508: overload approval, asked by the student and granted by the Head of Department', true);

-- ── the rule: whether students ask, and how far above the maximum a grant may go ──
CREATE TABLE registration.overload_policy (
    id          integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    open        boolean NOT NULL DEFAULT true,
    max_extra   integer NOT NULL DEFAULT 6 CHECK (max_extra BETWEEN 1 AND 12),
    reason      text    NOT NULL CHECK (length(btrim(reason)) >= 10),
    set_by      uuid    NULL,
    set_office  text    NULL,
    set_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE registration.overload_policy IS
  'V508: whether students may ask for an overload, and the most a Head of Department may grant above the maximum that binds the student (credit units); one row, set by the Academic Office, the Registry, the Directorate of ICT or super with a reason';
SELECT audit.attach('registration.overload_policy');
INSERT INTO registration.overload_policy (id, reason) VALUES (1, 'V508: students may ask; a grant goes at most 6 credit units above the maximum');

CREATE FUNCTION registration.overload_rule()
RETURNS registration.overload_policy LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p FROM registration.overload_policy p WHERE p.id = 1),
                    ROW(1, true, 6, 'the default', NULL, NULL, now())::registration.overload_policy)
$$;

CREATE FUNCTION registration.set_overload_policy(p_open boolean, p_max_extra integer, p_reason text)
RETURNS registration.overload_policy LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v registration.overload_policy;
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_POLICY_OFFICE: the overload rule is set by the Academic Office, the Registry or the Directorate of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'REG_OVERLOAD_POLICY_REASON: say why the rule changes, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_max_extra IS NULL OR p_max_extra NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'REG_OVERLOAD_POLICY_EXTRA: a grant goes 1 to 12 credit units above the maximum' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    INSERT INTO registration.overload_policy (id, open, max_extra, reason, set_by, set_office, set_at)
    VALUES (1, coalesce(p_open, true), p_max_extra, btrim(p_reason), nullif(current_setting('moaum.actor_id', true), '')::uuid, v_office, now())
    ON CONFLICT (id) DO UPDATE SET open = EXCLUDED.open, max_extra = EXCLUDED.max_extra, reason = EXCLUDED.reason,
        set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = EXCLUDED.set_at
    RETURNING * INTO v;
    RETURN v;
END $$;

-- ── the requests ──
CREATE TABLE registration.overload_request (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid    NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session         text    NOT NULL,
    semester        integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    level           integer NOT NULL,
    regular_max     integer NOT NULL,
    requested_max   integer NOT NULL CHECK (requested_max > regular_max),
    reason          text    NOT NULL CHECK (length(btrim(reason)) >= 10),
    status          text    NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED', 'GRANTED', 'REFUSED', 'WITHDRAWN')),
    granted_max     integer NULL,
    decision_reason text    NULL,
    decided_by      uuid    NULL,
    decided_office  text    NULL,
    decided_at      timestamptz NULL,
    requested_at    timestamptz NOT NULL DEFAULT now(),
    requested_by    uuid    NULL,
    CONSTRAINT ck_overload_granted CHECK (status <> 'GRANTED' OR (granted_max IS NOT NULL AND granted_max > regular_max)),
    CONSTRAINT ck_overload_decided CHECK (status NOT IN ('GRANTED', 'REFUSED') OR (decided_at IS NOT NULL AND length(btrim(coalesce(decision_reason, ''))) >= 10))
);
COMMENT ON TABLE registration.overload_request IS
  'V508: a student''s request for a higher maximum course load in one session and semester, and the Head of Department''s decision: GRANTED (granted_max, the ceiling for that semester, read by registration.unit_rule), REFUSED, or WITHDRAWN by the student while it waited';
-- one live request (waiting or granted) for a student and semester
CREATE UNIQUE INDEX uq_overload_live ON registration.overload_request (student_id, session, semester) WHERE status IN ('REQUESTED', 'GRANTED');
CREATE INDEX ix_overload_session ON registration.overload_request (session, semester, status);
SELECT audit.attach('registration.overload_request');

-- ── the load rule: V495/V503's, with the semester's granted ceiling as the maximum ──
CREATE FUNCTION registration.unit_rule_base(p_student uuid, p_level integer, p_session text, p_semester integer)
RETURNS TABLE(level integer, min_units integer, max_units integer, probation_max_units integer, carryover_counts boolean,
              curriculum text, basis text, level_min_units integer, rule_session text, rule_semester integer, instrument text)
LANGUAGE sql STABLE AS $$
    WITH st AS (
        SELECT s.entry_mode, s.programme_code,
               -- the curriculum binds an undergraduate; a postgraduate carries a label from the entry session, not a CCMAS/BMAS load
               CASE WHEN s.entry_mode IS DISTINCT FROM 'POSTGRADUATE' AND g.category IS DISTINCT FROM 'POST GRADUATE' THEN s.curriculum_version END AS curriculum
          FROM people.student s LEFT JOIN ref.programme g ON g.code = s.programme_code
         WHERE s.id = p_student),
    -- V503: the industrial-training (SIWES) semester carries exactly the SIWES course's units, as the student's screen and the
    -- Head of Department's approval already say: the SIWES course alone, no other course and no carry-over
    siw AS (SELECT registration.siwes_units(st.programme_code, p_level, p_semester) AS units FROM st WHERE p_semester IS NOT NULL),
    lv AS (SELECT l.* FROM policy.level_limit l WHERE l.level = p_level),
    cce AS (SELECT r.* FROM policy.route_level_limit r JOIN st ON st.entry_mode = 'CCE' WHERE r.route = 'CCE' AND r.level = p_level),
    cur AS (SELECT u.* FROM st CROSS JOIN LATERAL registration.unit_minimum_rule(st.curriculum, p_session, p_semester) u
             WHERE st.curriculum IS NOT NULL AND u.id IS NOT NULL)
    SELECT coalesce(c.level, l.level),
           coalesce(w.units, c.min_units, u.min_units, l.min_units),
           coalesce(w.units, c.max_units, l.max_units),
           CASE WHEN w.units IS NOT NULL THEN NULL WHEN c.level IS NOT NULL THEN c.probation_max_units ELSE l.probation_max_units END,
           coalesce(l.carryover_counts, true),
           (SELECT st.curriculum FROM st),
           CASE WHEN w.units IS NOT NULL THEN 'SIWES' WHEN c.level IS NOT NULL THEN 'CCE' WHEN u.id IS NOT NULL THEN 'CURRICULUM' ELSE 'LEVEL' END,
           l.min_units,
           CASE WHEN w.units IS NULL AND c.level IS NULL THEN u.session END,
           CASE WHEN w.units IS NULL AND c.level IS NULL THEN u.semester END,
           CASE WHEN c.level IS NOT NULL THEN c.instrument ELSE l.instrument END
      FROM (SELECT 1) one
      LEFT JOIN cce c ON true
      LEFT JOIN lv l ON true
      LEFT JOIN cur u ON true
      LEFT JOIN siw w ON true
     WHERE c.level IS NOT NULL OR l.level IS NOT NULL
$$;
COMMENT ON FUNCTION registration.unit_rule_base(uuid, integer, text, integer) IS
  'V495/V503 (kept by V508): the course load that binds a student before any overload — in a SIWES semester exactly the SIWES course''s units; else the CCE load, the curriculum''s minimum or the level''s; the maximum and probation ceiling the level''s (or the CCE load''s)';

CREATE OR REPLACE FUNCTION registration.unit_rule(p_student uuid, p_level integer, p_session text, p_semester integer)
RETURNS TABLE(level integer, min_units integer, max_units integer, probation_max_units integer, carryover_counts boolean,
              curriculum text, basis text, level_min_units integer, rule_session text, rule_semester integer, instrument text)
LANGUAGE sql STABLE AS $$
    SELECT b.level, b.min_units,
           -- V508: the Head of Department's grant for the semester raises the maximum (never in a SIWES semester)
           CASE WHEN b.basis = 'SIWES' THEN b.max_units ELSE greatest(b.max_units, g.granted_max) END,
           b.probation_max_units, b.carryover_counts, b.curriculum, b.basis, b.level_min_units, b.rule_session, b.rule_semester, b.instrument
      FROM registration.unit_rule_base(p_student, p_level, p_session, p_semester) b
      LEFT JOIN registration.overload_request g
             ON g.student_id = p_student AND g.session = p_session AND g.semester = p_semester AND g.status = 'GRANTED'
$$;
COMMENT ON FUNCTION registration.unit_rule(uuid, integer, text, integer) IS
  'V495/V503/V508: the course load that binds a student at a level in a session and semester — registration.unit_rule_base, with the overload the Head of Department granted for the semester as the maximum (not in a SIWES semester). basis says which minimum binds: SIWES, CCE, CURRICULUM or LEVEL';

-- ── notices ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('OVERLOAD_REQUESTED', 'Overload request waiting',
 'To the Head of Department of a student who asks for a higher maximum course load (V508)',
 'Overload request: [STUDENT], [SESSION] [SEMESTER]',
 E'Dear [FIRST_NAME],\n\n[STUDENT] ([MATRIC]) asks for a maximum course load of [UNITS] credit units in [SESSION] [SEMESTER]; the maximum that binds the student is [MAXIMUM].\n\nThe student''s reason: [REASON]\n\nGrant or refuse it on Overload Requests: [PORTAL_URL]\n\nMOAUM Portal',
 'MOAUM: [STUDENT] asks for an overload to [UNITS] units in [SESSION] [SEMESTER]. Decide on Overload Requests in the portal.',
 'Overload request waiting',
 '[STUDENT] ([MATRIC]) asks for a maximum of [UNITS] credit units in [SESSION] [SEMESTER] (the maximum is [MAXIMUM]): [REASON]',
 ARRAY['FIRST_NAME','STUDENT','MATRIC','SESSION','SEMESTER','UNITS','MAXIMUM','REASON','PORTAL_URL'], false, 'NORMAL'),
('OVERLOAD_GRANTED', 'Overload granted',
 'To the student whose overload request the Head of Department grants (V508)',
 'Your overload for [SESSION] [SEMESTER] is granted',
 E'Dear [FIRST_NAME],\n\nYour Head of Department has granted you a maximum course load of [UNITS] credit units for [SESSION] [SEMESTER]: [REASON]\n\nAdd the courses on Course registration and submit: [PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your overload for [SESSION] [SEMESTER] is granted: up to [UNITS] credit units. Add the courses and submit.',
 'Overload granted',
 'Your Head of Department granted you up to [UNITS] credit units for [SESSION] [SEMESTER]. [REASON]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','UNITS','REASON','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL'),
('OVERLOAD_REFUSED', 'Overload refused',
 'To the student whose overload request the Head of Department refuses (V508)',
 'Your overload request for [SESSION] [SEMESTER] was refused',
 E'Dear [FIRST_NAME],\n\nYour Head of Department has refused your request for a maximum of [UNITS] credit units in [SESSION] [SEMESTER]: [REASON]\n\nRegister within the maximum of [MAXIMUM] credit units: [PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your overload request for [SESSION] [SEMESTER] was refused. Register within [MAXIMUM] credit units.',
 'Overload refused',
 'Your request for up to [UNITS] credit units in [SESSION] [SEMESTER] was refused: [REASON] Register within [MAXIMUM] credit units.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','UNITS','MAXIMUM','REASON','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL');

-- the semester in words, as the notices say it
CREATE FUNCTION registration.semester_words(p_semester integer)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' WHEN 3 THEN 'third semester' ELSE 'semester ' || p_semester END
$$;

-- ── where a student stands: the request of the semester, the maximum, the ceiling a grant may reach, and whether they may ask ──
CREATE FUNCTION registration.overload_state(p_student uuid, p_session text, p_semester integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s record; v_level int; b record; pol registration.overload_policy := registration.overload_rule(); q registration.overload_request;
        st record; v_why text;
BEGIN
    SELECT x.id, x.status, x.current_level, x.programme_code INTO s FROM people.student x WHERE x.id = p_student;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_level := coalesce((SELECT r.level FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester),
                        s.current_level);
    SELECT * INTO b FROM registration.unit_rule_base(p_student, v_level, p_session, p_semester);
    SELECT * INTO q FROM registration.overload_request r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester
     ORDER BY (r.status IN ('REQUESTED', 'GRANTED')) DESC, r.requested_at DESC LIMIT 1;
    SELECT * INTO st FROM assessment.student_standing(p_student);
    v_why := CASE WHEN NOT pol.open THEN 'Overload requests are closed by the Academic Office.'
                  WHEN s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'Only a student in study asks for an overload.'
                  WHEN b.level IS NULL THEN 'No course load is stated for your level.'
                  WHEN b.basis = 'SIWES' THEN 'The industrial-training (SIWES) semester carries the SIWES course alone.'
                  WHEN st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') THEN 'A student on probation registers within the probation limit; an overload does not lift it.'
                  WHEN q.status IN ('REQUESTED', 'GRANTED') THEN NULL
                  END;
    RETURN jsonb_build_object(
        'session', p_session, 'semester', p_semester, 'level', v_level,
        'regular_max', b.max_units, 'ceiling', b.max_units + pol.max_extra, 'max_extra', pol.max_extra,
        'may_ask', v_why IS NULL AND coalesce(q.status, '') NOT IN ('REQUESTED', 'GRANTED'), 'why_not', v_why,
        'request', CASE WHEN q.id IS NULL THEN NULL ELSE jsonb_build_object(
            'id', q.id, 'status', q.status, 'requested_max', q.requested_max, 'granted_max', q.granted_max, 'reason', q.reason,
            'decision_reason', q.decision_reason, 'requested_at', q.requested_at, 'decided_at', q.decided_at) END);
END $$;
COMMENT ON FUNCTION registration.overload_state(uuid, text, integer) IS
  'V508: for the student''s screen — the semester''s overload request (the live one first), the maximum before any overload, the ceiling a grant may reach, and whether the student may ask (and why not)';

-- ── the student asks ──
CREATE FUNCTION registration.request_overload(p_student uuid, p_session text, p_semester integer, p_units integer, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); s record; v_level int; b record; st record;
        pol registration.overload_policy := registration.overload_rule(); v_reason text := btrim(coalesce(p_reason, '')); v_id uuid; h record;
BEGIN
    IF coalesce(v_office, '') NOT IN ('student', 'super') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_STUDENT: the student asks for an overload, from Course registration' USING ERRCODE = '42501';
    END IF;
    IF NOT pol.open THEN
        RAISE EXCEPTION 'REG_OVERLOAD_CLOSED: overload requests are closed by the Academic Office' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'REG_OVERLOAD_REASON: say why you need the overload, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT x.id, x.status, x.current_level, x.programme_code, x.surname, x.other_names, x.matric_no, x.admission_no, p.dept_code INTO s
      FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code WHERE x.id = p_student FOR UPDATE OF x;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_OVERLOAD_STUDENT_UNKNOWN: no such student' USING ERRCODE = '23503'; END IF;
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_NOT_IN_STUDY: only a student in study asks for an overload' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) OR p_semester NOT BETWEEN 1 AND 3 THEN
        RAISE EXCEPTION 'REG_OVERLOAD_SESSION: no such session and semester' USING ERRCODE = '23514';
    END IF;
    v_level := coalesce((SELECT r.level FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester),
                        s.current_level);
    SELECT * INTO b FROM registration.unit_rule_base(p_student, v_level, p_session, p_semester);
    IF b.level IS NULL THEN
        RAISE EXCEPTION 'REG_OVERLOAD_NO_LIMIT: no course load is stated for % level', v_level USING ERRCODE = '23514';
    END IF;
    IF b.basis = 'SIWES' THEN
        RAISE EXCEPTION 'REG_OVERLOAD_SIWES: the industrial-training (SIWES) semester carries the SIWES course alone' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO st FROM assessment.student_standing(p_student);
    IF st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_PROBATION: a student on probation registers within the probation limit; an overload does not lift it' USING ERRCODE = '23514';
    END IF;
    IF p_units IS NULL OR p_units <= b.max_units OR p_units > b.max_units + pol.max_extra THEN
        RAISE EXCEPTION 'REG_OVERLOAD_UNITS: ask for more than your maximum of % and at most % credit units', b.max_units, b.max_units + pol.max_extra USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM registration.overload_request r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester AND r.status = 'GRANTED') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_GRANTED: an overload is already granted for this semester' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM registration.overload_request r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester AND r.status = 'REQUESTED') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_WAITING: your request for this semester is with your Head of Department; withdraw it to ask again' USING ERRCODE = '23514';
    END IF;
    INSERT INTO registration.overload_request (student_id, session, semester, level, regular_max, requested_max, reason, requested_by)
    VALUES (p_student, p_session, p_semester, v_level, b.max_units, p_units, v_reason, nullif(current_setting('moaum.actor_id', true), '')::uuid)
    RETURNING id INTO v_id;
    -- the Head (or Heads) of the student's department told
    FOR h IN SELECT DISTINCT a.person_id FROM iam.office_assignment a
              WHERE a.office_code = 'hod' AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                AND iam.acting_department(a.person_id, 'hod') = s.dept_code
    LOOP
        PERFORM platform.tell_person(h.person_id, 'OVERLOAD_REQUESTED', NULL,
            jsonb_build_object('STUDENT', upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
                               'MATRIC', coalesce(s.matric_no, s.admission_no), 'SESSION', p_session, 'SEMESTER', registration.semester_words(p_semester),
                               'UNITS', p_units, 'MAXIMUM', b.max_units, 'REASON', v_reason),
            'OVERLOAD_REQUESTED:' || v_id, NULL);
    END LOOP;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION registration.request_overload(uuid, text, integer, integer, text) IS
  'V508: a student in study asks for a higher maximum for one session and semester (more than the maximum, at most the maximum plus the rule''s max_extra), with a reason; never in a SIWES semester or on probation, one live request a semester; the Head of Department told';

CREATE FUNCTION registration.withdraw_overload(p_student uuid, p_request uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE q registration.overload_request;
BEGIN
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('student', 'super') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_STUDENT: the student withdraws their own request' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO q FROM registration.overload_request WHERE id = p_request AND student_id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_OVERLOAD_NOT_FOUND: no such request of yours' USING ERRCODE = '23503'; END IF;
    IF q.status <> 'REQUESTED' THEN
        RAISE EXCEPTION 'REG_OVERLOAD_DECIDED: the request is % and is no longer withdrawn', lower(q.status) USING ERRCODE = '23514';
    END IF;
    UPDATE registration.overload_request SET status = 'WITHDRAWN', decided_at = now(), decided_office = 'student' WHERE id = q.id;
    RETURN 'WITHDRAWN';
END $$;

-- ── the Head of Department decides ──
CREATE FUNCTION registration.decide_overload(p_request uuid, p_decision text, p_units integer, p_reason text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_decision text := upper(btrim(coalesce(p_decision, ''))); v_reason text := btrim(coalesce(p_reason, '')); q registration.overload_request;
        v_dept text; b record; pol registration.overload_policy := registration.overload_rule();
BEGIN
    IF coalesce(v_office, '') NOT IN ('hod', 'super') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_HOD: an overload is granted or refused by the Head of Department' USING ERRCODE = '42501';
    END IF;
    IF v_decision NOT IN ('GRANTED', 'REFUSED') THEN
        RAISE EXCEPTION 'REG_OVERLOAD_DECISION: the decision is GRANTED or REFUSED' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'REG_OVERLOAD_DECISION_REASON: the decision states its reason (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO q FROM registration.overload_request WHERE id = p_request FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_OVERLOAD_NOT_FOUND: no such overload request' USING ERRCODE = '23503'; END IF;
    SELECT p.dept_code INTO v_dept FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = q.student_id;
    IF v_office = 'hod' AND iam.acting_department(v_actor, 'hod') IS DISTINCT FROM v_dept THEN
        RAISE EXCEPTION 'REG_OVERLOAD_OTHER_DEPT: the student is in another department; their own Head of Department decides' USING ERRCODE = '42501';
    END IF;
    IF q.status <> 'REQUESTED' THEN
        RAISE EXCEPTION 'REG_OVERLOAD_DECIDED: the request is already %', lower(q.status) USING ERRCODE = '23514';
    END IF;
    -- the maximum is read again: the level or the curriculum may have changed since the student asked
    SELECT * INTO b FROM registration.unit_rule_base(q.student_id, q.level, q.session, q.semester);
    IF v_decision = 'GRANTED' THEN
        IF b.basis = 'SIWES' THEN
            RAISE EXCEPTION 'REG_OVERLOAD_SIWES: the industrial-training (SIWES) semester carries the SIWES course alone' USING ERRCODE = '23514';
        END IF;
        IF p_units IS NULL OR p_units <= b.max_units OR p_units > b.max_units + pol.max_extra THEN
            RAISE EXCEPTION 'REG_OVERLOAD_UNITS: grant more than the maximum of % and at most % credit units', b.max_units, b.max_units + pol.max_extra USING ERRCODE = '23514';
        END IF;
        UPDATE registration.overload_request SET status = 'GRANTED', granted_max = p_units, regular_max = b.max_units, decision_reason = v_reason,
               decided_by = v_actor, decided_office = v_office, decided_at = now()
         WHERE id = q.id;
        PERFORM platform.tell_student(q.student_id, 'OVERLOAD_GRANTED', NULL,
            jsonb_build_object('SESSION', q.session, 'SEMESTER', registration.semester_words(q.semester), 'UNITS', p_units, 'REASON', v_reason),
            'OVERLOAD_GRANTED:' || q.id);
    ELSE
        UPDATE registration.overload_request SET status = 'REFUSED', decision_reason = v_reason, decided_by = v_actor, decided_office = v_office, decided_at = now()
         WHERE id = q.id;
        PERFORM platform.tell_student(q.student_id, 'OVERLOAD_REFUSED', NULL,
            jsonb_build_object('SESSION', q.session, 'SEMESTER', registration.semester_words(q.semester), 'UNITS', q.requested_max,
                               'MAXIMUM', b.max_units, 'REASON', v_reason),
            'OVERLOAD_REFUSED:' || q.id);
    END IF;
    RETURN v_decision;
END $$;
COMMENT ON FUNCTION registration.decide_overload(uuid, text, integer, text) IS
  'V508: the Head of Department of the student''s department (super as break-glass) grants a waiting overload request — a ceiling above the maximum, at most the maximum plus the rule''s max_extra, never in a SIWES semester — or refuses it, with a reason; the student told';

COMMIT;
