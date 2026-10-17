-- ═══════════════════════════════════════
-- V516 — Late registration by the Registry, on the student's behalf
--
-- The office-created registration (POST /registration/course-registrations) had no screen (PRD FR-REG-07), and a student whose
-- registration window closed — a late admission, a fees case settled after the deadline, a medical case — had no way back but an
-- ICT Support ticket. Now the Registry (registrar, dregistrar; super) registers the student late, with a reason:
--   · registration.registry_late_checks(student, session, semester, offering) — the ICT Support engine's checks for the course
--     (registration.support_add_checks, V346), reporting which would block it. Only the registration window and the add and drop
--     period are set aside for a late registration; every other rule holds: the student in study, the session, a semester not
--     closed, the course on the student's own list (carry-overs and deferred courses with it), the maximum load (with a granted
--     overload, V508), the fees, the GST/EPS fee, the prerequisites where enforced.
--   · registration.registry_register(student, session, semester, offerings, reason) — each course added by the engine
--     (registration.support_add, its entry naming the override and the Registry's reason), then the registration submitted by the
--     engine (registration.support_submit → student_submit: the fees, the GST gate, the minimum and maximum load, the probation
--     ceiling), approved by the semester's rule (V491) or left for the Head of Department; recorded on
--     registration.late_registration and told to the student (REG_LATE_BY_REGISTRY). A registration submitted after the window
--     closes carries the late registration fee where the Bursary set one (finance.charges, as before).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V516: late registration by the Registry on the student''s behalf', true);

CREATE TABLE registration.late_registration (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_id uuid NOT NULL REFERENCES registration.course_registration(id) ON DELETE CASCADE,
    student_id      uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session         text NOT NULL,
    semester        integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    offerings       uuid[] NOT NULL,
    units           integer NOT NULL,
    status          text NOT NULL,
    reason          text NOT NULL CHECK (length(btrim(reason)) >= 10),
    by_person       uuid NULL,
    by_office       text NOT NULL,
    at              timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE registration.late_registration IS
  'V516: a registration made late by the Registry on the student''s behalf — the courses it added, the units and status it ended with, the reason, who and when';
CREATE INDEX ix_late_reg_session ON registration.late_registration (session, semester, at DESC);
SELECT audit.attach('registration.late_registration');

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('REG_LATE_BY_REGISTRY', 'Registered late by the Registry',
 'To the student the Registry registers late, on their behalf (V516)',
 'You are registered for [SESSION] [SEMESTER]',
 E'Dear [FIRST_NAME],\n\nThe Registry has registered you for [SESSION] [SEMESTER] after the registration window closed: [COURSES] course(s), [UNITS] credit units. The registration is [STATUS].\n\nThe reason recorded: [REASON]\n\nYour courses are on Course registration: [PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: the Registry registered you for [SESSION] [SEMESTER] ([UNITS] units, [STATUS]). See Course registration.',
 'Registered late by the Registry',
 'The Registry registered you for [SESSION] [SEMESTER]: [COURSES] course(s), [UNITS] credit units, [STATUS]. [REASON]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','COURSES','UNITS','STATUS','REASON','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL');

-- the engine's checks for one course, and whether the late registration may set each aside (the window and add and drop only)
CREATE FUNCTION registration.registry_late_checks(p_student uuid, p_session text, p_semester integer, p_offering uuid)
RETURNS TABLE(ord integer, rule text, label text, passed boolean, set_aside boolean, blocks boolean, message text)
LANGUAGE sql STABLE AS $$
    SELECT k.ord, k.rule, k.label, k.passed,
           NOT k.passed AND k.rule IN ('REGISTRATION_WINDOW', 'ADD_DROP_PERIOD'),
           NOT k.passed AND NOT k.advisory AND k.rule NOT IN ('REGISTRATION_WINDOW', 'ADD_DROP_PERIOD'),
           k.message
      FROM registration.support_add_checks(p_student, p_session, p_semester, p_offering) k
$$;
COMMENT ON FUNCTION registration.registry_late_checks(uuid, text, integer, uuid) IS
  'V516: the ICT Support engine''s checks for a course (registration.support_add_checks), with whether a late registration by the Registry sets each aside (the registration window and the add and drop period only) or is blocked by it';

CREATE FUNCTION registration.registry_register(p_student uuid, p_session text, p_semester integer, p_offerings uuid[], p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, '')); o uuid; k record; v_reg uuid; v_out jsonb; v_status text; v_units int; v_courses int; v_added uuid[] := '{}';
BEGIN
    IF coalesce(v_office, '') NOT IN ('registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'REG_LATE_OFFICE: a late registration is made by the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'REG_LATE_REASON: say why the student is registered late (ten characters or more)' USING ERRCODE = '23514';
    END IF;
    IF p_offerings IS NULL OR cardinality(p_offerings) = 0 THEN
        RAISE EXCEPTION 'REG_LATE_NO_COURSE: choose the courses to register' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    FOREACH o IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(p_offerings) x) LOOP
        -- already on the registration: nothing to add
        IF EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                    WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester AND e.offering_id = o AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) THEN
            CONTINUE;
        END IF;
        SELECT * INTO k FROM registration.registry_late_checks(p_student, p_session, p_semester, o) c WHERE c.blocks ORDER BY c.ord LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'REG_LATE_BLOCKED: % — %', (SELECT x.course_code FROM catalogue.offering x WHERE x.id = o), k.message USING ERRCODE = '23514',
                HINT = 'A late registration sets aside the registration window and the add and drop period only; the other rules hold.';
        END IF;
        v_out := registration.support_add(p_student, p_session, p_semester, o, true, v_actor, 'Late registration by the Registry: ' || v_reason);
        v_added := v_added || o;
    END LOOP;
    SELECT r.id, r.status INTO v_reg, v_status FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = p_semester;
    IF v_reg IS NULL THEN
        RAISE EXCEPTION 'REG_LATE_NO_COURSE: no course was added' USING ERRCODE = '23514';
    END IF;
    IF v_status IN ('DRAFT', 'RETURNED') THEN
        v_out := registration.support_submit(p_student, p_session, p_semester, true, v_actor, 'Late registration by the Registry: ' || v_reason);
    END IF;
    SELECT r.status INTO v_status FROM registration.course_registration r WHERE r.id = v_reg;
    v_units := registration.units_of(v_reg);
    v_courses := (SELECT count(*) FROM registration.entry e WHERE e.registration_id = v_reg AND e.status NOT IN ('DROPPED', 'WITHDRAWN'));
    INSERT INTO registration.late_registration (registration_id, student_id, session, semester, offerings, units, status, reason, by_person, by_office)
    VALUES (v_reg, p_student, p_session, p_semester, v_added, v_units, v_status, v_reason, v_actor, v_office);
    PERFORM platform.tell_student(p_student, 'REG_LATE_BY_REGISTRY', NULL,
        jsonb_build_object('SESSION', p_session, 'SEMESTER', registration.semester_words(p_semester), 'COURSES', v_courses, 'UNITS', v_units,
                           'STATUS', CASE v_status WHEN 'APPROVED' THEN 'approved' WHEN 'SUBMITTED' THEN 'submitted for approval' ELSE lower(v_status) END,
                           'REASON', v_reason),
        'REG_LATE_BY_REGISTRY:' || v_reg || ':' || floor(extract(epoch FROM now()))::bigint);
    RETURN jsonb_build_object('registrationId', v_reg, 'status', v_status, 'units', v_units, 'courses', v_courses, 'added', cardinality(v_added));
END $$;
COMMENT ON FUNCTION registration.registry_register(uuid, text, integer, uuid[], text) IS
  'V516: the Registry registers a student late — each course added by the support engine with the window and add and drop set aside (every other rule holds), then submitted by the engine (approved by the semester''s rule or left for the Head of Department); recorded on registration.late_registration, the student told';

COMMIT;
