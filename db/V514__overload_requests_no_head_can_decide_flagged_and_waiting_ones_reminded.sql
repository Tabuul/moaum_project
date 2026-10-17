-- ═══════════════════════════════════════
-- V514 — Overload requests no Head of Department can decide are flagged, and requests left waiting are reminded
--
-- An overload request (V508) is told to, and decided by, the Head of Department of the student's department alone. Where the
-- department has no Head on the portal (no live hod grant resolving to it), the request waits unseen. Now:
--   · registration.department_heads(dept) — the people who are Head of a department today (as decide_overload reads them);
--     Overload Requests marks each waiting request whose department has none.
--   · registration.remind_overloads(days) — each morning: every waiting request older than the given days (3 by the job) is
--     reminded to its department's Head (OVERLOAD_WAITING, once in that many days a request); and the Academic Office is told, once a
--     day, how many requests wait in departments with no Head, and which (OVERLOAD_NO_HEAD), so a Head is assigned on Users &
--     roles. Nothing is decided for the Head.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V514: overload requests no Head can decide flagged, waiting ones reminded', true);

CREATE FUNCTION registration.department_heads(p_dept text)
RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
    SELECT DISTINCT a.person_id FROM iam.office_assignment a
     WHERE a.office_code = 'hod' AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND p_dept IS NOT NULL AND iam.acting_department(a.person_id, 'hod') = p_dept
$$;
COMMENT ON FUNCTION registration.department_heads(text) IS
  'V514: the people who are Head of the department today — a live hod grant whose department (iam.acting_department) is it; the people an overload request is told to and decided by';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('OVERLOAD_WAITING', 'Overload request still waiting',
 'To the Head of Department while a student''s overload request waits for a decision (V514)',
 'Still waiting: overload request of [STUDENT]',
 E'Dear [FIRST_NAME],\n\n[STUDENT] ([MATRIC]) asked [DAYS] days ago for a maximum course load of [UNITS] credit units in [SESSION] [SEMESTER] (the maximum is [MAXIMUM]). The student cannot add the courses until you decide.\n\nGrant or refuse it on Overload Requests: [PORTAL_URL]\n\nMOAUM Portal',
 'MOAUM: [STUDENT]''s overload request ([UNITS] units, [SESSION] [SEMESTER]) has waited [DAYS] days. Decide on Overload Requests.',
 'Overload request still waiting',
 '[STUDENT] ([MATRIC]) asked [DAYS] days ago for [UNITS] credit units in [SESSION] [SEMESTER]. Grant or refuse it.',
 ARRAY['FIRST_NAME','STUDENT','MATRIC','DAYS','UNITS','MAXIMUM','SESSION','SEMESTER','PORTAL_URL'], false, 'NORMAL'),
('OVERLOAD_NO_HEAD', 'Overload requests no Head of Department can decide',
 'To the Academic Office, once a day, while overload requests wait in departments with no Head of Department on the portal (V514)',
 '[COUNT] overload request(s) wait in departments with no Head of Department',
 E'Dear [FIRST_NAME],\n\n[COUNT] overload request(s) wait for a Head of Department who is not on the portal: [DEPARTMENTS].\n\nAn overload is granted or refused by the Head of the student''s department alone. Have the Head assigned on Users & roles (the Directorate of ICT), and the requests reach them. The list: [PORTAL_URL]\n\nMOAUM Portal',
 'MOAUM: [COUNT] overload request(s) wait in departments with no Head of Department on the portal: [DEPARTMENTS].',
 'Overload requests with no Head of Department',
 '[COUNT] overload request(s) wait in departments with no Head on the portal: [DEPARTMENTS]. Have the Head assigned on Users & roles.',
 ARRAY['FIRST_NAME','COUNT','DEPARTMENTS','PORTAL_URL'], false, 'NORMAL');

CREATE FUNCTION registration.remind_overloads(p_days integer)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE q record; h uuid; v_heads int := 0; v_told int := 0; v_no_head int := 0; v_depts text; a uuid; v_academic int := 0; v_every int := greatest(coalesce(p_days, 3), 1);
BEGIN
    FOR q IN
        SELECT r.*, s.surname, s.other_names, coalesce(s.matric_no, s.admission_no) AS matric, p.dept_code,
               (current_date - (r.requested_at AT TIME ZONE 'Africa/Lagos')::date) AS waited
          FROM registration.overload_request r
          JOIN people.student s ON s.id = r.student_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
         WHERE r.status = 'REQUESTED'
    LOOP
        IF NOT EXISTS (SELECT 1 FROM registration.department_heads(q.dept_code)) THEN
            v_no_head := v_no_head + 1;
            CONTINUE;
        END IF;
        IF q.waited < v_every THEN CONTINUE; END IF;
        v_heads := v_heads + 1;
        FOR h IN SELECT registration.department_heads(q.dept_code) LOOP
            v_told := v_told + platform.tell_person(h, 'OVERLOAD_WAITING', NULL,
                jsonb_build_object('STUDENT', upper(btrim(q.surname)) || coalesce(', ' || nullif(btrim(q.other_names), ''), ''), 'MATRIC', q.matric,
                                   'DAYS', q.waited, 'UNITS', q.requested_max, 'MAXIMUM', q.regular_max, 'SESSION', q.session,
                                   'SEMESTER', registration.semester_words(q.semester)),
                -- once in every p_days days a request
                'OVERLOAD_WAITING:' || q.id || ':' || (q.waited / v_every), NULL);
        END LOOP;
    END LOOP;
    IF v_no_head > 0 THEN
        SELECT string_agg(DISTINCT coalesce(d.name || ' (' || p.dept_code || ')', coalesce(p.dept_code, 'no department')), ', ') INTO v_depts
          FROM registration.overload_request r JOIN people.student s ON s.id = r.student_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
         WHERE r.status = 'REQUESTED' AND NOT EXISTS (SELECT 1 FROM registration.department_heads(p.dept_code));
        FOR a IN SELECT DISTINCT x.person_id FROM iam.office_assignment x
                  WHERE x.office_code = 'academic' AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date) LOOP
            v_academic := v_academic + platform.tell_person(a, 'OVERLOAD_NO_HEAD', NULL,
                jsonb_build_object('COUNT', v_no_head, 'DEPARTMENTS', v_depts), 'OVERLOAD_NO_HEAD:' || current_date, NULL);
        END LOOP;
    END IF;
    RETURN jsonb_build_object('reminded_requests', v_heads, 'heads_told', v_told, 'no_head', v_no_head, 'academic_told', v_academic);
END $$;
COMMENT ON FUNCTION registration.remind_overloads(integer) IS
  'V514: the morning reminder — each waiting overload request older than the given days reminded to its department''s Head (once in that many days a request), and the Academic Office told once a day how many wait in departments with no Head, and which';

COMMIT;
