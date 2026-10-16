-- ═══════════════════════════════════════
-- V491 — Course registration approved automatically, reset by the student and registered again
--
--   Students wait on their Head of Department to approve each course registration, and many current registrations carry
--   courses brought over from the old portal. The University suspends the Head's approval: a registration that passes every
--   rule the engine already applies is approved the moment it is submitted, the examination card follows on the same
--   conditions as before (an approved registration and the Bursary's clearance for the examination), and a student whose
--   registration carries the wrong courses clears it and registers again. Nothing is rebuilt and nothing historical goes.
--
--   The approval rule (registration.approval_policy) is set by session, and by semester where a semester differs:
--   HOD_APPROVAL_REQUIRED (the standing rule, the row with no session) or AUTO_APPROVAL; with it, whether a student may reset
--   the registration, and whether the examination card is offered as soon as the registration is approved. The Academic
--   Office, the Registry, the Directorate of ICT and super change it, with a reason, on the audit spine. The current session
--   of each route (the University's, the Centre for Continuing Education's, the School of Postgraduate Studies') is set to
--   AUTO_APPROVAL with the reset allowed. The Head's approval stays in the portal and returns when the rule is set back.
--
--     · registration.submit_checks — the checks a submission already passed (the fees stated and cleared, the GST gate, the
--       unit range, the probation ceiling), taken out of registration.student_submit so the pending registrations are judged
--       by the very same rules;
--     · registration.auto_approve — under AUTO_APPROVAL a submitted registration is approved: the student in study, a course
--       on it, and every course one the student may take that semester (on the student's menu, or added by ICT Support on a
--       ticket). It records approval_mode AUTO with no approver and tells the student once; when a rule fails, the reason;
--     · registration.student_submit restated: under AUTO_APPROVAL it approves at once, or files the reason for review;
--     · registration.auto_approve_pending — the registrations already waiting on a Head, judged again by the same rules:
--       approved where they hold, kept for review with the reason where they do not (registration.approval_review), never
--       approved blindly. Run here for the sessions set to AUTO_APPROVAL;
--     · registration.student_reset — the student's own registration for the semester, while the window is open and the rule
--       allows it, never a LOCKED one, a closed semester's, or one with a mark entered against any of its courses: the
--       courses kept on registration.registration_reset (status, approval, every course with its units), the chosen courses
--       removed exactly as choosing courses again removes them (carryovers, deferred courses and ICT Support's ticketed
--       additions stay), the registration back to DRAFT. Results, payments, GST/EPS entitlement and earlier semesters are
--       not read for writing. A student's reset waits until the semester's school fees are cleared, so a student who could not
--       submit again is never left with no registration;
--     · registration.exam_card_issue — each student's examination card, counted when it is issued (once a student and
--       semester, with how many times);
--     · notices REG_AUTO_APPROVED and REG_RESET on the notification engine, once per event.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V491: course registration approved automatically, reset by the student and registered again', true);

-- ── the rule ──
CREATE TABLE registration.approval_policy (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session             text NULL REFERENCES policy.academic_session (name),
    semester            integer NULL CHECK (semester BETWEEN 1 AND 3),
    mode                text NOT NULL CHECK (mode IN ('HOD_APPROVAL_REQUIRED', 'AUTO_APPROVAL')),
    allow_student_reset boolean NOT NULL DEFAULT false,
    card_on_approval    boolean NOT NULL DEFAULT true,
    reason              text NOT NULL CHECK (length(btrim(reason)) >= 10),
    set_by              uuid NULL,
    set_office          text NULL REFERENCES ref.office (code),
    set_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_reg_policy_semester CHECK (semester IS NULL OR session IS NOT NULL),
    CONSTRAINT uq_reg_policy UNIQUE NULLS NOT DISTINCT (session, semester)
);
COMMENT ON TABLE registration.approval_policy IS
  'V491: how a course registration is approved — HOD_APPROVAL_REQUIRED or AUTO_APPROVAL — by session (and semester where it differs), with whether a student may reset the registration and whether the examination card is offered on approval; the row with no session is the standing rule';
SELECT audit.attach('registration.approval_policy');

CREATE FUNCTION registration.approval_rule(p_session text, p_semester integer)
RETURNS registration.approval_policy LANGUAGE sql STABLE AS $$
    SELECT p.* FROM registration.approval_policy p
     WHERE (p.session = p_session AND (p.semester = p_semester OR p.semester IS NULL)) OR p.session IS NULL
     ORDER BY (p.session IS NULL), (p.semester IS NULL) LIMIT 1
$$;
CREATE FUNCTION registration.approval_mode(p_session text, p_semester integer)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((registration.approval_rule(p_session, p_semester)).mode, 'HOD_APPROVAL_REQUIRED')
$$;
COMMENT ON FUNCTION registration.approval_mode(text, integer) IS 'V491: HOD_APPROVAL_REQUIRED or AUTO_APPROVAL for a session and semester — the semester''s rule, else the session''s, else the standing rule';

-- how each registration was approved: by the Head (HOD) or by the rule (AUTO); earlier approvals keep NULL
ALTER TABLE registration.course_registration ADD COLUMN approval_mode text NULL CHECK (approval_mode IN ('HOD', 'AUTO'));

-- ── what is left for review ──
CREATE TABLE registration.approval_review (
    registration_id uuid PRIMARY KEY REFERENCES registration.course_registration (id) ON DELETE CASCADE,
    reason          text NOT NULL,
    found_at        timestamptz NOT NULL DEFAULT now(),
    checked_at      timestamptz NOT NULL DEFAULT now(),
    cleared_at      timestamptz NULL
);
COMMENT ON TABLE registration.approval_review IS
  'V491: a submitted registration the automatic approval did not approve, with the rule it failed, for the Academic Office and the Directorate of ICT; cleared when it is approved or reset';
SELECT audit.attach('registration.approval_review');

-- ── the resets ──
CREATE TABLE registration.registration_reset (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_id        uuid NOT NULL REFERENCES registration.course_registration (id) ON DELETE CASCADE,
    student_id             uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session                text NOT NULL,
    semester               integer NOT NULL,
    previous_status        text NOT NULL,
    previous_approval_mode text NULL,
    level                  integer NULL,
    courses                jsonb NOT NULL,
    course_count           integer NOT NULL,
    units                  integer NOT NULL,
    kept                   jsonb NOT NULL DEFAULT '[]'::jsonb,
    reason                 text NOT NULL CHECK (btrim(reason) <> ''),
    source                 text NOT NULL CHECK (source IN ('STUDENT_PORTAL', 'ICT_SUPPORT', 'ACADEMIC_OFFICE')),
    reset_by               uuid NULL,
    reset_office           text NULL,
    reset_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_registration_reset_student ON registration.registration_reset (student_id, session, semester, reset_at DESC);
COMMENT ON TABLE registration.registration_reset IS
  'V491: each reset of a course registration — the registration as it stood (status, approval, every course with its units and type), what was kept (carryovers, deferred courses, ICT Support''s ticketed additions), who reset it, from where and why';
SELECT audit.attach('registration.registration_reset');

-- ── the examination cards issued ──
CREATE TABLE registration.exam_card_issue (
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session    text NOT NULL,
    semester   integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    first_at   timestamptz NOT NULL DEFAULT now(),
    last_at    timestamptz NOT NULL DEFAULT now(),
    times      integer NOT NULL DEFAULT 1,
    PRIMARY KEY (student_id, session, semester)
);
SELECT audit.exempt('registration.exam_card_issue',
    'A count of a student''s own examination card being issued (viewed, downloaded, printed); the card itself is the approved registration, which is on the spine.');

CREATE FUNCTION registration.record_exam_card(p_student uuid, p_session text, p_semester integer)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO registration.exam_card_issue (student_id, session, semester) VALUES (p_student, p_session, p_semester)
    ON CONFLICT (student_id, session, semester) DO UPDATE SET last_at = now(), times = registration.exam_card_issue.times + 1
$$;

-- ── the notices ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('REG_AUTO_APPROVED', 'Course registration approved',
 'To the student when a course registration is approved automatically (V491)',
 'Your course registration for [SESSION] [SEMESTER] is approved',
 E'Dear [FIRST_NAME],\n\nYour course registration for [SESSION] [SEMESTER] has been successfully approved ([UNITS] units).\n\n[CARD_NOTE]\n\nSign in to the portal: [PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your course registration for [SESSION] [SEMESTER] is approved. [CARD_NOTE]',
 'Course registration approved',
 'Your course registration for [SESSION] [SEMESTER] has been successfully approved. [CARD_NOTE]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','UNITS','CARD_NOTE','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL'),
('REG_RESET', 'Course registration reset',
 'To the student when a course registration is reset (V491)',
 'Your course registration for [SESSION] [SEMESTER] was reset',
 E'Dear [FIRST_NAME],\n\nYour course registration for [SESSION] [SEMESTER] has been reset. You may now register your courses again.\n\nIf you did not do this, contact ICT Support.\n\n[PORTAL_URL]\n\nOffice of the Registrar, [UNIVERSITY_NAME]',
 'MOAUM: your course registration for [SESSION] [SEMESTER] was reset. You may now register your courses again.',
 'Course registration reset',
 'Your course registration for [SESSION] [SEMESTER] has been reset. You may now register your courses again.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── the checks a submission passes, in one place ──
CREATE FUNCTION registration.submit_checks(p_registration uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; lim policy.level_limit; units int; st record; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared
    IF NOT finance.fee_stated(r.student_id, r.session) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid.';
    END IF;
    -- V461: and the semester's own: while no school-fee line of this semester (or of the whole session) reaches the
    -- student, though another semester's does, the semester reads as paid when it is not stated — refused until it is
    IF r.semester = ANY (finance.fee_unstated_semesters(r.student_id, r.session)) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_SEMESTER_FEES_NOT_STATED: the % semester school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END,
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for the semester opens when the Bursary states its school fees on Fee Setup and they are paid.';
    END IF;
    IF NOT finance.semester_cleared(r.student_id, r.session, r.semester) THEN
        RAISE EXCEPTION 'the % semester school fees for % are not fully paid',
            CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' WHEN 3 THEN 'third' ELSE r.semester::text END, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration for a semester opens when that semester''s school fees are cleared in full.';
    END IF;
    -- V314: where the University holds the whole registration on the GST fee, an unpaid student does not submit
    v_gate := registration.gst_gate(r.student_id, r.session, NULL);
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; submission opens the moment the payment is confirmed.';
    END IF;
    -- and a GST/EPS course already on the draft is not submitted unpaid either
    SELECT registration.gst_gate(r.student_id, r.session, o.course_code) INTO v_gate
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
     WHERE e.registration_id = p_registration AND e.status <> 'DROPPED' AND registration.gst_gate(r.student_id, r.session, o.course_code) IS NOT NULL
     LIMIT 1;
    IF v_gate IS NOT NULL THEN
        RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS, or remove the GST/EPS courses from the registration.';
    END IF;
    units := registration.units_of(p_registration);
    SELECT * INTO lim FROM registration.unit_limit(r.student_id, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND (units < lim.min_units OR units > lim.max_units) THEN
        RAISE EXCEPTION 'the registration carries % units; at % level the range is % to %', units, r.level, lim.min_units, lim.max_units
        USING ERRCODE = '23514', HINT = 'Add or drop courses to bring it within the range, or obtain an overload approval from the Head of Department.';
    END IF;
    SELECT * INTO st FROM assessment.student_standing(r.student_id);
    IF FOUND AND st.standing IN ('PROBATION', 'ADVISED_TO_WITHDRAW') AND lim.probation_max_units IS NOT NULL AND units > lim.probation_max_units THEN
        RAISE EXCEPTION 'you are on probation (CGPA % after % % semester); the registration carries % units and the limit on probation at % level is %',
            st.cgpa, st.pronounced_session, CASE st.pronounced_semester WHEN 1 THEN 'first' ELSE 'second' END, units, r.level, lim.probation_max_units
        USING ERRCODE = '23514', HINT = 'Drop courses to bring the registration within the probation limit. The carryovers stay; choose fewer new courses.';
    END IF;
END $$;
COMMENT ON FUNCTION registration.submit_checks(uuid) IS
  'V491: the checks a course registration passes to be submitted — the fees stated and cleared, the GST gate, the unit range, the probation ceiling — raised as each refusal; registration.student_submit and the review of pending registrations both apply them';

-- ── the automatic approval ──
CREATE FUNCTION registration.auto_approve(p_registration uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; v_status text; n int; v_units int; bad text; v_card text; v_sem text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration FOR UPDATE;
    IF NOT FOUND THEN RETURN 'REG_NOT_FOUND: no such registration'; END IF;
    IF r.status IN ('APPROVED', 'LOCKED') THEN RETURN 'approved'; END IF;
    IF r.status <> 'SUBMITTED' THEN RETURN 'REG_NOT_SUBMITTED: the registration is ' || lower(r.status); END IF;
    SELECT s.status INTO v_status FROM people.student s WHERE s.id = r.student_id;
    IF v_status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        RETURN 'REG_STUDENT_NOT_ELIGIBLE: a student who is ' || lower(v_status) || ' does not register';
    END IF;
    SELECT count(*), coalesce(sum(e.units), 0) INTO n, v_units FROM registration.entry e
     WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN');
    IF n = 0 THEN RETURN 'REG_NO_COURSES: the registration carries no course'; END IF;
    -- every course one the student may take this semester: on the student's menu (offered to the programme and level, a
    -- carryover, a GST/EPS course, an elective or a borrowed course), or added by ICT Support on the student's ticket
    WITH menu AS MATERIALIZED (SELECT m.offering_id FROM registration.student_menu(r.student_id, r.session, r.semester) m)
    SELECT o.course_code INTO bad FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.support_override_at IS NULL
       AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED')
       AND NOT EXISTS (SELECT 1 FROM menu WHERE menu.offering_id = e.offering_id)
     ORDER BY o.course_code LIMIT 1;
    IF bad IS NOT NULL THEN
        RETURN 'REG_COURSE_NOT_OFFERED: ' || bad || ' is not offered to this student''s programme and level for ' || r.session || ' semester ' || r.semester;
    END IF;
    UPDATE registration.course_registration SET status = 'APPROVED', approved_at = now(), approved_by = NULL, approval_mode = 'AUTO'
     WHERE id = r.id;
    UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = r.id AND status = 'REGISTERED';
    UPDATE registration.approval_review SET cleared_at = now() WHERE registration_id = r.id AND cleared_at IS NULL;
    v_sem := CASE r.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END;
    v_card := CASE WHEN NOT coalesce((registration.approval_rule(r.session, r.semester)).card_on_approval, true)
                   THEN 'Your examination card is released with the examination timetable.'
                   WHEN policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL OR finance.clears(r.student_id, r.session, 'EXAMINATION')
                   THEN 'Your examination card is now available for printing.'
                   ELSE 'Your examination card follows when your fees are cleared for the examination.' END;
    PERFORM platform.tell_student(r.student_id, 'REG_AUTO_APPROVED', NULL,
        jsonb_build_object('SESSION', r.session, 'SEMESTER', v_sem, 'UNITS', v_units, 'CARD_NOTE', v_card),
        'REG_AUTO_APPROVED:' || r.id || ':' || floor(extract(epoch FROM coalesce(r.submitted_at, now())))::bigint);
    RETURN 'approved';
END $$;
COMMENT ON FUNCTION registration.auto_approve(uuid) IS
  'V491: a submitted registration approved by the rule — the student in study, a course on it, every course on the student''s menu or added by ICT Support on a ticket; approval_mode AUTO, no approver, the student told once. Returns ''approved'' or the reason it is not';

-- ── a submission, approved at once where the rule says so ──
CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; v text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    PERFORM registration.submit_checks(p_registration);
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    -- V491: where the Head's approval is suspended, the registration is approved now, or kept for review with the reason
    IF registration.approval_mode(r.session, r.semester) = 'AUTO_APPROVAL' THEN
        v := registration.auto_approve(p_registration);
        IF v = 'approved' THEN RETURN 'approved'; END IF;
        INSERT INTO registration.approval_review (registration_id, reason) VALUES (p_registration, v)
        ON CONFLICT (registration_id) DO UPDATE SET reason = EXCLUDED.reason, checked_at = now(), cleared_at = NULL;
    END IF;
    RETURN 'submitted';
END $$;

-- ── a submitted registration judged again: the submission's own checks, then the automatic approval ──
CREATE FUNCTION registration.auto_approve_checked(p_registration uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
    BEGIN
        PERFORM registration.submit_checks(p_registration);
        v := registration.auto_approve(p_registration);
    EXCEPTION WHEN OTHERS THEN
        -- any refusal (or fault) keeps the registration for review with its words; one never stops the rest
        GET STACKED DIAGNOSTICS v = MESSAGE_TEXT;
    END;
    IF v <> 'approved' THEN
        INSERT INTO registration.approval_review (registration_id, reason) VALUES (p_registration, v)
        ON CONFLICT (registration_id) DO UPDATE SET reason = EXCLUDED.reason, checked_at = now(), cleared_at = NULL;
    END IF;
    RETURN v;
END $$;
COMMENT ON FUNCTION registration.auto_approve_checked(uuid) IS
  'V491: a submitted registration judged again by the submission''s own checks and the automatic approval: ''approved'', or the reason, kept for review';

-- ── the registrations already waiting on a Head ──
CREATE FUNCTION registration.auto_approve_pending(p_session text, p_semester integer)
RETURNS TABLE(considered integer, approved integer, review integer) LANGUAGE plpgsql AS $$
DECLARE x record; n_all int := 0; n_ok int := 0;
BEGIN
    FOR x IN SELECT r.id FROM registration.course_registration r
              WHERE r.status = 'SUBMITTED' AND (p_session IS NULL OR r.session = p_session) AND (p_semester IS NULL OR r.semester = p_semester)
                AND registration.approval_mode(r.session, r.semester) = 'AUTO_APPROVAL'
              ORDER BY r.submitted_at NULLS LAST, r.id
    LOOP
        n_all := n_all + 1;
        IF registration.auto_approve_checked(x.id) = 'approved' THEN n_ok := n_ok + 1; END IF;
    END LOOP;
    RETURN QUERY SELECT n_all, n_ok, n_all - n_ok;
END $$;
COMMENT ON FUNCTION registration.auto_approve_pending(text, integer) IS
  'V491: the submitted registrations of a session (and semester) under AUTO_APPROVAL judged again by the submission''s own checks and the automatic approval: approved where they hold, kept for review with the reason where they do not — never approved blindly';

-- ── the student's reset ──
CREATE FUNCTION registration.reset_refusal(p_student uuid, p_session text, p_semester integer, p_source text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE r registration.course_registration; v_closed text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN
        RETURN 'REG_RESET_NOTHING: there is no course registration for ' || p_session || ' semester ' || p_semester || ' to reset';
    END IF;
    IF p_source = 'STUDENT_PORTAL' AND NOT coalesce((registration.approval_rule(r.session, r.semester)).allow_student_reset, false) THEN
        RETURN 'REG_RESET_OFF: resetting a course registration is not open to students for ' || r.session || ' semester ' || r.semester;
    END IF;
    IF r.status = 'LOCKED' THEN
        RETURN 'REG_RESET_LOCKED: the ' || r.session || ' semester ' || r.semester || ' registration is locked; it is the examined record';
    END IF;
    v_closed := registration.semester_closed(r.student_id, r.session, r.semester);
    IF v_closed IS NOT NULL THEN
        RETURN 'REG_RESET_CLOSED: the semester is ' || v_closed || '; its registration is history';
    END IF;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN assessment.score_sheet ss ON ss.offering_id = e.offering_id
                 JOIN assessment.score sc ON sc.sheet_id = ss.id AND sc.student_id = r.student_id
                WHERE e.registration_id = r.id) THEN
        RETURN 'REG_RESET_HAS_RESULTS: a mark is already entered against a course on this registration';
    END IF;
    -- a student who could not submit again (the semester's school fees not stated, or not cleared) would be left with no
    -- registration at all: the reset waits until they could register again
    IF p_source = 'STUDENT_PORTAL' AND (NOT finance.fee_stated(r.student_id, r.session) OR NOT finance.semester_cleared(r.student_id, r.session, r.semester)) THEN
        RETURN 'REG_RESET_FEES: the ' || CASE r.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END || ' semester school fees for ' || r.session
               || ' are not cleared, so the courses could not be registered again after a reset';
    END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION registration.reset_refusal(uuid, text, integer, text) IS
  'V491: why a course registration may not be reset (no registration, the rule closed to students, locked, the semester closed, a mark entered, or — for the student — the semester''s fees not cleared, which would leave them unable to register again), or NULL; the window is the portal''s own check';

CREATE FUNCTION registration.student_reset(p_student uuid, p_session text, p_semester integer, p_reason text, p_source text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; v_courses jsonb; v_kept jsonb; n int; u int; removable int; v_id uuid; v_sem text; v_why text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester FOR UPDATE;
    v_why := registration.reset_refusal(p_student, p_session, p_semester, p_source);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514',
            HINT = 'A registration with marks, a locked one or a closed semester''s is part of the record; ICT Support adds or drops a course on a ticket.';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('courseCode', o.course_code, 'title', c.title, 'units', e.units, 'entryType', e.entry_type,
                                                 'status', e.status, 'offeringId', e.offering_id, 'supportOverride', e.support_override_at IS NOT NULL)
                              ORDER BY o.course_code), '[]'::jsonb),
           count(*) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')),
           coalesce(sum(e.units) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')), 0),
           count(*) FILTER (WHERE e.entry_type NOT IN ('CARRYOVER', 'DEFERRED') AND e.support_override_at IS NULL)
      INTO v_courses, n, u, removable
      FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id LEFT JOIN catalogue.course c ON c.code = o.course_code
     WHERE e.registration_id = r.id;
    -- a second reset of a registration already clear does nothing (a second click, a retried request)
    IF r.status = 'DRAFT' AND removable = 0 THEN
        RETURN jsonb_build_object('reset', false, 'alreadyClear', true, 'registrationId', r.id, 'courses', n);
    END IF;
    -- the chosen courses go exactly as choosing courses again removes them; carryovers, deferred courses and ICT Support's
    -- ticketed additions stay, back to REGISTERED
    DELETE FROM registration.entry WHERE registration_id = r.id AND entry_type NOT IN ('CARRYOVER', 'DEFERRED') AND support_override_at IS NULL;
    UPDATE registration.entry SET status = 'REGISTERED' WHERE registration_id = r.id AND status = 'APPROVED';
    SELECT coalesce(jsonb_agg(jsonb_build_object('courseCode', o.course_code, 'units', e.units, 'entryType', e.entry_type) ORDER BY o.course_code), '[]'::jsonb)
      INTO v_kept FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id WHERE e.registration_id = r.id;
    UPDATE registration.course_registration
       SET status = 'DRAFT', submitted_at = NULL, approved_at = NULL, approved_by = NULL, approval_mode = NULL, returned_comment = NULL
     WHERE id = r.id;
    UPDATE registration.approval_review SET cleared_at = now() WHERE registration_id = r.id AND cleared_at IS NULL;
    INSERT INTO registration.registration_reset (registration_id, student_id, session, semester, previous_status, previous_approval_mode, level,
                                                 courses, course_count, units, kept, reason, source, reset_by, reset_office)
    VALUES (r.id, r.student_id, r.session, r.semester, r.status, r.approval_mode, r.level, v_courses, n, u, v_kept,
            coalesce(nullif(btrim(p_reason), ''), 'Reset to register the courses again'), p_source,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    v_sem := CASE r.semester WHEN 1 THEN 'first semester' WHEN 2 THEN 'second semester' ELSE 'third semester' END;
    PERFORM platform.tell_student(r.student_id, 'REG_RESET', NULL, jsonb_build_object('SESSION', r.session, 'SEMESTER', v_sem), 'REG_RESET:' || v_id);
    RETURN jsonb_build_object('reset', true, 'resetId', v_id, 'registrationId', r.id, 'previousStatus', r.status, 'courses', n, 'units', u,
                              'kept', jsonb_array_length(v_kept));
END $$;
COMMENT ON FUNCTION registration.student_reset(uuid, text, integer, text, text) IS
  'V491: a course registration cleared to register again — never a locked one, a closed semester''s, or one with a mark entered; the registration as it stood kept on registration.registration_reset; the chosen courses removed as choosing again removes them (carryovers, deferred courses and ticketed additions stay); back to DRAFT; the student told';

-- ── the figures for the Academic Office and the Directorate of ICT ──
CREATE FUNCTION registration.approval_overview(p_session text, p_semester integer)
RETURNS TABLE(registration_id uuid, student_id uuid, full_name text, matric_no text, programme text, dept_code text, faculty_code text, level integer,
              session text, semester integer, status text, approval_mode text, submitted_at timestamptz, approved_at timestamptz,
              review_reason text, resets integer, last_reset_at timestamptz, reregistered boolean, card_times integer, courses integer)
LANGUAGE sql STABLE AS $$
    SELECT r.id, r.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), s.matric_no, p.name, p.dept_code,
           p.faculty_code, r.level, r.session, r.semester, r.status, r.approval_mode, r.submitted_at, r.approved_at,
           CASE WHEN ar.cleared_at IS NULL THEN ar.reason END, coalesce(rs.n, 0), rs.last_at,
           rs.n > 0 AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED') AND r.submitted_at > rs.last_at,
           ci.times, coalesce(en.n, 0)
      FROM registration.course_registration r
      JOIN people.student s ON s.id = r.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN registration.approval_review ar ON ar.registration_id = r.id
      LEFT JOIN LATERAL (SELECT count(*)::int AS n, max(x.reset_at) AS last_at FROM registration.registration_reset x WHERE x.registration_id = r.id) rs ON true
      LEFT JOIN registration.exam_card_issue ci ON ci.student_id = r.student_id AND ci.session = r.session AND ci.semester = r.semester
      LEFT JOIN LATERAL (SELECT count(*)::int AS n FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) en ON true
     WHERE r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
$$;
COMMENT ON FUNCTION registration.approval_overview(text, integer) IS
  'V491: every course registration of a session (and semester) with how it was approved, what holds it for review, its resets and whether it was registered again since, and how often its examination card was issued';

-- ── the rule now: the standing rule is the Head's approval; the current session of each route is approved automatically ──
INSERT INTO registration.approval_policy (session, semester, mode, allow_student_reset, card_on_approval, reason)
VALUES (NULL, NULL, 'HOD_APPROVAL_REQUIRED', false, true, 'The standing rule: the Head of Department approves each course registration');
INSERT INTO registration.approval_policy (session, semester, mode, allow_student_reset, card_on_approval, reason)
SELECT DISTINCT x, NULL::integer, 'AUTO_APPROVAL', true, true,
       'V491: HOD course registration approval suspended; a registration that passes the registration rules is approved on submission, and a student may reset it and register again'
  FROM unnest(ARRAY[policy.university_current_session(), policy.route_session('CCE'), admissions.pg_current_session()]) x
 WHERE x IS NOT NULL AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x);

-- the registrations already waiting on a Head in those sessions: approved where they hold, kept for review where they do not
SELECT * FROM registration.auto_approve_pending(NULL, NULL);

COMMIT;
