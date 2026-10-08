-- V365: JUPEB examined on the University's one CBT engine.
--
-- The brief: "JUPEB subjects/courses should also be able to use the CBT engine where configured … DO NOT create a separate JUPEB CBT
-- engine." V355 had kept JUPEB's timed mocks on its practice engine because the CBT engine served only University students. From V365
-- the engine has a second kind of candidate — a JUPEB student (jupeb.application) — beside the University's (people.student), and an
-- examination may be of a JUPEB subject instead of a course offering:
--
--   * a JUPEB subject is examined by CBT only when the JUPEB Office says so (jupeb.subject.cbt_enabled), as a course is (V364);
--   * the JUPEB Office creates, runs, monitors and reviews the subject's examinations on the same tables, functions and screens;
--   * the subject has its own question bank on assessment.question (jupeb_subject_id instead of course_code), frozen by version as every
--     bank is (V364);
--   * a JUPEB student may sit it when admitted (state STUDENT), registered for the subject in the session, and the Bursary's share of
--     the school fee for the semester paid (jupeb.school_fees: the first share for the first semester; the whole fee after);
--   * the result goes, where the office says, into the JUPEB continuous assessment (a part the office set, scaled to its maximum,
--     through jupeb.ca_save and its lock) — never invented as a Board mark;
--   * the attempt names its candidate (student_id or jupeb_application_id; candidate_id is whichever it is).
--
-- JUPEB's practice tests (V348) stay what they are: self-study with answers shown afterwards, not examinations.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V365: JUPEB examined on the University CBT engine', true);

-- ── 1 · a JUPEB subject examined by CBT only when the JUPEB Office says so ──────────────────────────────────────

ALTER TABLE jupeb.subject ADD COLUMN cbt_enabled boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN jupeb.subject.cbt_enabled IS 'V365: the subject may be examined by the University CBT engine; set by the JUPEB Office. No subject is assumed to be one.';

CREATE FUNCTION jupeb.set_subject_cbt(p_subject uuid, p_on boolean)
RETURNS jupeb.subject
LANGUAGE plpgsql AS $$
DECLARE s jupeb.subject;
BEGIN
    SELECT * INTO s FROM jupeb.subject WHERE id = p_subject FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SUBJECT_NOT_FOUND: no such JUPEB subject' USING ERRCODE = '23503'; END IF;
    IF p_on AND NOT s.active THEN RAISE EXCEPTION 'CBT_SUBJECT_INACTIVE: % is not an active subject', s.title USING ERRCODE = '23514'; END IF;
    IF NOT p_on AND EXISTS (SELECT 1 FROM assessment.cbt_exam e WHERE e.jupeb_subject_id = s.id AND e.state IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'CLOSED')) THEN
        RAISE EXCEPTION 'CBT_COURSE_IN_USE: % has a CBT examination not yet completed or cancelled', s.title USING ERRCODE = '23514',
            HINT = 'Complete or cancel it first. Examinations already sat keep their record either way.';
    END IF;
    UPDATE jupeb.subject SET cbt_enabled = p_on, updated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, updated_at = now() WHERE id = s.id RETURNING * INTO s;
    RETURN s;
END $$;

-- ── 2 · an examination of a JUPEB subject ───────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.cbt_exam DROP CONSTRAINT cbt_exam_office_check;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT cbt_exam_office_check CHECK (office IN ('GST', 'EPS', 'EXAMS', 'JUPEB'));
ALTER TABLE assessment.cbt_exam
    ALTER COLUMN course_code DROP NOT NULL,
    ALTER COLUMN offering_id DROP NOT NULL,
    ADD COLUMN jupeb_subject_id uuid NULL REFERENCES jupeb.subject(id),
    ADD COLUMN jupeb_ca_component_id uuid NULL REFERENCES jupeb.ca_component(id);
ALTER TABLE assessment.cbt_exam
    ADD CONSTRAINT ck_cbt_exam_what CHECK (CASE WHEN office = 'JUPEB'
                                                THEN jupeb_subject_id IS NOT NULL AND course_code IS NULL AND offering_id IS NULL
                                                ELSE jupeb_subject_id IS NULL AND jupeb_ca_component_id IS NULL AND course_code IS NOT NULL AND offering_id IS NOT NULL END),
    ADD CONSTRAINT ck_cbt_exam_jupeb_sheet CHECK (office <> 'JUPEB' OR sheet_component IN ('CA', 'NONE'));
CREATE UNIQUE INDEX ux_cbt_exam_jupeb_title ON assessment.cbt_exam (jupeb_subject_id, session, title) WHERE jupeb_subject_id IS NOT NULL;
COMMENT ON COLUMN assessment.cbt_exam.jupeb_subject_id IS 'V365: the JUPEB subject a JUPEB Office examination examines (instead of a course offering).';
COMMENT ON COLUMN assessment.cbt_exam.jupeb_ca_component_id IS 'V365: the part of the JUPEB continuous assessment the result goes into, scaled to that part''s maximum (sheet_component CA).';

-- ── 3 · a JUPEB subject's question bank ─────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.question ALTER COLUMN course_code DROP NOT NULL, ADD COLUMN jupeb_subject_id uuid NULL REFERENCES jupeb.subject(id);
ALTER TABLE assessment.question ADD CONSTRAINT ck_question_bank CHECK ((course_code IS NULL) <> (jupeb_subject_id IS NULL));
CREATE INDEX ix_question_jupeb_active ON assessment.question (jupeb_subject_id, active) WHERE jupeb_subject_id IS NOT NULL;
COMMENT ON COLUMN assessment.question.jupeb_subject_id IS 'V365: the JUPEB subject whose bank the question is in (instead of a course).';

-- ── 4 · the attempt names its candidate: a University student or a JUPEB student ────────────────────────────────

ALTER TABLE assessment.cbt_attempt ALTER COLUMN student_id DROP NOT NULL, ADD COLUMN jupeb_application_id uuid NULL REFERENCES jupeb.application(id);
ALTER TABLE assessment.cbt_attempt ADD CONSTRAINT ck_cbt_attempt_candidate CHECK ((student_id IS NULL) <> (jupeb_application_id IS NULL));
ALTER TABLE assessment.cbt_attempt ADD COLUMN candidate_id uuid GENERATED ALWAYS AS (coalesce(student_id, jupeb_application_id)) STORED;
ALTER TABLE assessment.cbt_attempt DROP CONSTRAINT cbt_attempt_exam_id_student_id_number_key;
ALTER TABLE assessment.cbt_attempt ADD CONSTRAINT cbt_attempt_exam_candidate_number_key UNIQUE (exam_id, candidate_id, number);
DROP INDEX assessment.ux_cbt_attempt_active;
CREATE UNIQUE INDEX ux_cbt_attempt_active ON assessment.cbt_attempt (exam_id, candidate_id) WHERE status = 'IN_PROGRESS';
CREATE INDEX ix_cbt_attempt_jupeb ON assessment.cbt_attempt (jupeb_application_id, exam_id) WHERE jupeb_application_id IS NOT NULL;
COMMENT ON COLUMN assessment.cbt_attempt.candidate_id IS 'V365: the candidate, whichever kind — the University student (student_id) or the JUPEB student (jupeb_application_id).';

-- ── 5 · the pool and the bank read by subject as by course ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_pool(p_exam uuid)
RETURNS TABLE(question_id uuid, ordinal integer, marks integer)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
         own AS (SELECT eq.question_id, eq.ordinal, coalesce(eq.marks, q.marks) AS marks
                   FROM assessment.cbt_exam_question eq JOIN assessment.question q ON q.id = eq.question_id AND q.active
                  WHERE eq.exam_id = p_exam)
    SELECT * FROM own
    UNION ALL
    SELECT q.id, 0, q.marks FROM e JOIN assessment.question q ON (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id) AND q.active
     WHERE e.selection = 'RANDOM' AND NOT EXISTS (SELECT 1 FROM own)
$$;

CREATE OR REPLACE FUNCTION assessment.question_in_live_exam(p_question uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT e.reference FROM assessment.cbt_exam e
      JOIN assessment.question q ON q.id = p_question AND (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id)
     WHERE e.state = 'PUBLISHED' AND e.ends_at > now()
       AND (EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id AND eq.question_id = p_question)
            OR (e.selection = 'RANDOM' AND NOT EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id)))
     LIMIT 1
$$;

-- ── 6 · creating a JUPEB examination ────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION assessment.cbt_new_jupeb_exam(p_subject uuid, p_session text, p_semester integer, p_title text, p_instructions text, p_duration integer, p_total integer,
                                              p_selection text, p_random_q boolean, p_random_o boolean, p_pass numeric, p_attempts integer, p_security text, p_venue text,
                                              p_violation_limit integer, p_violation_action text, p_second_session text, p_starts timestamptz, p_ends timestamptz)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE s jupeb.subject; e assessment.cbt_exam;
BEGIN
    SELECT * INTO s FROM jupeb.subject WHERE id = p_subject;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SUBJECT_NOT_FOUND: no such JUPEB subject' USING ERRCODE = '23503'; END IF;
    IF NOT s.active THEN RAISE EXCEPTION 'CBT_SUBJECT_INACTIVE: % is not an active subject', s.title USING ERRCODE = '23514'; END IF;
    IF NOT s.cbt_enabled THEN
        RAISE EXCEPTION 'CBT_COURSE_NOT_ENABLED: % is not examined by CBT', s.title USING ERRCODE = '23514',
            HINT = 'The JUPEB Office allows a subject to be examined by CBT.';
    END IF;
    IF p_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'CBT_SESSION: % is not a session on the University calendar', coalesce(p_session, 'no session') USING ERRCODE = '23514';
    END IF;
    IF p_semester IS NULL OR p_semester NOT IN (1, 2) THEN RAISE EXCEPTION 'CBT_SEMESTER: a JUPEB examination is of the first or the second semester' USING ERRCODE = '23514'; END IF;
    INSERT INTO assessment.cbt_exam (reference, office, course_code, offering_id, jupeb_subject_id, session, semester, title, instructions, duration_minutes, total_questions,
                                     selection, randomize_questions, randomize_options, pass_mark, attempt_limit, security_mode, venue, violation_limit,
                                     violation_action, second_session, starts_at, ends_at, sheet_component, created_by, created_office)
    VALUES ('CBT/' || replace(p_session, '/', '-') || '/' || lpad(platform.next_number('cbt_exam', 'UNIVERSITY', p_session)::text, 5, '0'),
            'JUPEB', NULL, NULL, s.id, p_session, p_semester, btrim(p_title), nullif(btrim(coalesce(p_instructions, '')), ''),
            coalesce(p_duration, 60), coalesce(p_total, 0), coalesce(upper(p_selection), 'FIXED'), coalesce(p_random_q, true), coalesce(p_random_o, false),
            coalesce(p_pass, 40), coalesce(p_attempts, 1), coalesce(upper(p_security), 'STANDARD'), coalesce(upper(p_venue), 'REMOTE'),
            coalesce(p_violation_limit, 2), coalesce(upper(p_violation_action), 'WARN'), coalesce(upper(p_second_session), 'CONTINUE'),
            p_starts, p_ends, 'NONE', nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING * INTO e;
    RETURN e;
END $$;
COMMENT ON FUNCTION assessment.cbt_new_jupeb_exam IS 'V365: a JUPEB Office examination of a JUPEB subject in a session and semester; the result goes nowhere until the office names a part of the continuous assessment.';

/** the further settings (V364), with a JUPEB examination's own: its result goes into a part of the JUPEB continuous assessment, or nowhere */
CREATE OR REPLACE FUNCTION assessment.cbt_configure(p_exam uuid, p jsonb)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_bad text; v_comp jupeb.ca_component;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RETURN e; END IF;
    IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN
        RAISE EXCEPTION 'CBT_STATE: the settings of a % examination are kept as they were published', lower(e.state) USING ERRCODE = '23514';
    END IF;
    IF p ? 'examType' AND upper(p->>'examType') NOT IN ('EXAMINATION', 'TEST', 'QUIZ', 'MOCK', 'RESIT') THEN
        RAISE EXCEPTION 'CBT_SETTING: an examination is an Examination, a Test, a Quiz, a Mock or a Resit' USING ERRCODE = '23514';
    END IF;
    IF p ? 'negativeMarks' AND ((p->>'negativeMarks')::numeric < 0 OR (p->>'negativeMarks')::numeric > 100) THEN
        RAISE EXCEPTION 'CBT_SETTING: negative marking deducts between 0 and 100 marks for a wrong answer' USING ERRCODE = '23514';
    END IF;
    IF p ? 'detectors' THEN
        SELECT string_agg(x, ', ') INTO v_bad FROM jsonb_array_elements_text(p->'detectors') x
         WHERE upper(x) NOT IN ('TAB', 'BLUR', 'FULLSCREEN', 'COPY', 'PASTE', 'RIGHT_CLICK', 'NETWORK');
        IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CBT_SETTING: % is not a signal the screen watches', v_bad USING ERRCODE = '23514'; END IF;
    END IF;
    IF p ? 'countedEvents' THEN
        SELECT string_agg(x, ', ') INTO v_bad FROM jsonb_array_elements_text(p->'countedEvents') x
         WHERE upper(x) NOT IN ('TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT', 'RIGHT_CLICK', 'NETWORK_DISCONNECT',
                                'EXAM_PAGE_EXIT', 'UNUSUAL_NAVIGATION', 'TIME_MANIPULATION_ATTEMPT', 'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME',
                                'PROLONGED_LOOK_AWAY', 'CAMERA_STOPPED');
        IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CBT_SETTING: % is not an event that can count as a violation', v_bad USING ERRCODE = '23514'; END IF;
    END IF;
    IF p ? 'sheetComponent' AND upper(p->>'sheetComponent') NOT IN ('EXAM', 'CA', 'NONE') THEN
        RAISE EXCEPTION 'CBT_SETTING: the result goes onto the score sheet as the Examination, as continuous assessment, or not at all' USING ERRCODE = '23514';
    END IF;
    IF e.office = 'JUPEB' AND p ? 'sheetComponent' AND upper(p->>'sheetComponent') = 'EXAM' THEN
        RAISE EXCEPTION 'CBT_SETTING: a JUPEB examination is the Board''s; a CBT result goes into the JUPEB continuous assessment, or nowhere' USING ERRCODE = '23514';
    END IF;
    IF p ? 'jupebCaComponentId' AND jsonb_typeof(p->'jupebCaComponentId') = 'string' THEN
        IF e.office <> 'JUPEB' THEN RAISE EXCEPTION 'CBT_SETTING: a part of the JUPEB assessment is for a JUPEB examination' USING ERRCODE = '23514'; END IF;
        SELECT * INTO v_comp FROM jupeb.ca_component WHERE id = (p->>'jupebCaComponentId')::uuid;
        IF NOT FOUND OR v_comp.session <> e.session OR NOT v_comp.active THEN
            RAISE EXCEPTION 'CBT_SETTING: no such part of the % JUPEB continuous assessment', e.session USING ERRCODE = '23514';
        END IF;
    END IF;
    IF p ? 'proctoring' AND upper(p->>'proctoring') NOT IN ('NONE', 'CAMERA') THEN
        RAISE EXCEPTION 'CBT_SETTING: proctoring is NONE or CAMERA' USING ERRCODE = '23514';
    END IF;
    IF p ? 'disconnectMinutes' AND jsonb_typeof(p->'disconnectMinutes') = 'number' AND (p->>'disconnectMinutes')::int NOT BETWEEN 2 AND 120 THEN
        RAISE EXCEPTION 'CBT_SETTING: an attempt out of contact is submitted after between 2 and 120 minutes, or never' USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.cbt_exam SET
        exam_type = CASE WHEN p ? 'examType' THEN upper(p->>'examType') ELSE exam_type END,
        negative_marks = CASE WHEN p ? 'negativeMarks' THEN round((p->>'negativeMarks')::numeric, 2) ELSE negative_marks END,
        allow_back = CASE WHEN p ? 'allowBack' THEN (p->>'allowBack')::boolean ELSE allow_back END,
        allow_review = CASE WHEN p ? 'allowReview' THEN (p->>'allowReview')::boolean ELSE allow_review END,
        fullscreen_required = CASE WHEN p ? 'fullscreenRequired' THEN (p->>'fullscreenRequired')::boolean ELSE fullscreen_required END,
        detectors = CASE WHEN p ? 'detectors' THEN ARRAY(SELECT DISTINCT upper(x) FROM jsonb_array_elements_text(p->'detectors') x ORDER BY 1) ELSE detectors END,
        counted_events = CASE WHEN p ? 'countedEvents' THEN ARRAY(SELECT DISTINCT upper(x) FROM jsonb_array_elements_text(p->'countedEvents') x ORDER BY 1) ELSE counted_events END,
        warn_at = CASE WHEN p ? 'warnAt' THEN (p->>'warnAt')::int ELSE warn_at END,
        final_warn_at = CASE WHEN p ? 'finalWarnAt' THEN (p->>'finalWarnAt')::int ELSE final_warn_at END,
        disconnect_minutes = CASE WHEN p ? 'disconnectMinutes' THEN (p->>'disconnectMinutes')::int ELSE disconnect_minutes END,
        proctoring = CASE WHEN p ? 'proctoring' THEN upper(p->>'proctoring') ELSE proctoring END,
        score_on_submit = CASE WHEN p ? 'scoreOnSubmit' THEN (p->>'scoreOnSubmit')::boolean ELSE score_on_submit END,
        sheet_component = CASE WHEN p ? 'sheetComponent' THEN upper(p->>'sheetComponent') ELSE sheet_component END,
        jupeb_ca_component_id = CASE WHEN p ? 'jupebCaComponentId' THEN nullif(p->>'jupebCaComponentId', '')::uuid ELSE jupeb_ca_component_id END
     WHERE id = e.id RETURNING * INTO e;
    IF NOT e.allow_back AND e.allow_review THEN
        UPDATE assessment.cbt_exam SET allow_review = false WHERE id = e.id RETURNING * INTO e;
    END IF;
    RETURN e;
END $$;

-- ── 7 · eligibility: a JUPEB student by the JUPEB rules ─────────────────────────────────────────────────────────

CREATE FUNCTION assessment.cbt_jupeb_eligibility(p_exam uuid, p_app uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; a jupeb.application; s jupeb.subject; f record; v_ready text; n int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT * INTO s FROM jupeb.subject WHERE id = e.jupeb_subject_id;
    IF NOT coalesce(s.cbt_enabled, false) THEN RETURN format('CBT_COURSE_NOT_ENABLED: %s is not examined by CBT', s.title); END IF;
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF NOT FOUND OR a.state <> 'STUDENT' THEN RETURN 'CBT_JUPEB_NOT_STUDENT: only an admitted JUPEB student sits a JUPEB examination'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.subject_registration r WHERE r.application_id = p_app AND r.subject_id = e.jupeb_subject_id AND r.session = e.session) THEN
        RETURN format('CBT_JUPEB_SUBJECT_NOT_REGISTERED: %s is not one of your registered subjects for %s', s.title, e.session);
    END IF;
    SELECT * INTO f FROM jupeb.school_fees(p_app);
    IF e.semester = 1 AND NOT (coalesce(f.first_paid, false) OR coalesce(f.full_paid, false)) THEN
        RETURN 'CBT_JUPEB_FEES: the first-semester share of your JUPEB school fee is not paid';
    ELSIF e.semester >= 2 AND NOT (coalesce(f.full_paid, false) OR (coalesce(f.first_paid, false) AND coalesce(f.second_paid, false))) THEN
        RETURN 'CBT_JUPEB_FEES: your JUPEB school fee for the session is not paid in full';
    END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_app AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_eligibility(p_exam uuid, p_student uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; st people.student; v_gate text; v_ready text; n int; v_enabled boolean;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    -- V365: a JUPEB examination's candidate is a JUPEB student, judged by the JUPEB rules
    IF e.office = 'JUPEB' THEN RETURN assessment.cbt_jupeb_eligibility(p_exam, p_student); END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT cbt_enabled INTO v_enabled FROM catalogue.course WHERE code = e.course_code;
    IF NOT coalesce(v_enabled, false) THEN RETURN format('CBT_COURSE_NOT_ENABLED: %s is not a CBT course', e.course_code); END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF NOT FOUND OR st.status NOT IN ('ACTIVE', 'ADMITTED', 'PROBATION') THEN
        RETURN 'CBT_STUDENT_INACTIVE: only an active student sits an examination';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE cr.student_id = p_student AND en.offering_id = e.offering_id
                      AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
        RETURN format('CBT_COURSE_NOT_REGISTERED: %s is not on your submitted registration for %s', e.course_code, e.session);
    END IF;
    IF e.office IN ('GST', 'EPS') THEN
        v_gate := registration.gst_gate(p_student, e.session, e.course_code);
        IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    ELSIF NOT coalesce(finance.clears(p_student, e.session, 'EXAMINATION'), false) THEN
        RETURN format('CBT_FEES_NOT_CLEARED: your %s school fees are not cleared for examinations', e.session);
    END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $$;

-- ── 8 · the start: the attempt of whichever candidate the examination examines ─────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; a assessment.cbt_attempt; v_why text; v_seed int; v_paper uuid[]; v_versions int[]; v_marks int[]; v_n int; v_jupeb boolean;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(p_exam::text || ':' || p_student::text));
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    v_jupeb := e.office = 'JUPEB';
    SELECT * INTO a FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student AND status = 'IN_PROGRESS';
    IF FOUND THEN
        IF a.ends_at <= now() THEN
            a := assessment.cbt_finalize(a.id, 'TIME_EXPIRED', 'time expired before the candidate returned');
        ELSE
            IF e.second_session = 'DENY' THEN
                PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', true, 'a second sign-in was refused', p_ip);
                UPDATE assessment.cbt_attempt SET violations = violations + 1, last_activity_at = now() WHERE id = a.id;
                RAISE EXCEPTION 'CBT_SECOND_SESSION_DENIED: your examination is already open on another browser or device' USING ERRCODE = '23514',
                    HINT = 'Return to the screen where you started it. The attempt is recorded.';
            END IF;
            IF e.second_session = 'MONITOR' THEN
                PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', false, 'the examination was opened again; allowed and recorded', p_ip);
                UPDATE assessment.cbt_attempt SET last_activity_at = now() WHERE id = a.id RETURNING * INTO a;
                RETURN a;
            END IF;
            PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', true, 'the examination was opened again; the earlier screen is replaced', p_ip);
            PERFORM assessment.cbt_log(a.id, 'SESSION_REPLACED', false, 'the earlier screen no longer holds the attempt', p_ip);
            UPDATE assessment.cbt_attempt SET token = gen_random_uuid(), violations = violations + 1, last_activity_at = now(), ip = coalesce(p_ip, ip), user_agent = coalesce(p_agent, user_agent)
             WHERE id = a.id RETURNING * INTO a;
            RETURN a;
        END IF;
    END IF;
    v_why := assessment.cbt_eligibility(p_exam, p_student);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514', HINT = 'Eligibility is judged on the record: the registration, the payments on the ledger, the examination window.';
    END IF;
    v_seed := (('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 7))::bit(28))::int;
    v_paper := assessment.cbt_paper(p_exam, v_seed);
    IF coalesce(cardinality(v_paper), 0) = 0 THEN RAISE EXCEPTION 'CBT_PAPER_EMPTY: the paper has no questions' USING ERRCODE = '23514'; END IF;
    SELECT array_agg(q.version ORDER BY u.n), array_agg(p.marks ORDER BY u.n) INTO v_versions, v_marks
      FROM unnest(v_paper) WITH ORDINALITY u(qid, n)
      JOIN assessment.question q ON q.id = u.qid
      JOIN assessment.cbt_pool(p_exam) p ON p.question_id = u.qid;
    IF coalesce(cardinality(v_versions), 0) <> cardinality(v_paper) THEN
        RAISE EXCEPTION 'CBT_PAPER_CHANGED: the paper changed as the attempt began; start again' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student;
    INSERT INTO assessment.cbt_attempt (exam_id, student_id, jupeb_application_id, number, ends_at, question_ids, question_versions, question_marks, seed, max_marks, ip, user_agent)
    VALUES (p_exam, CASE WHEN v_jupeb THEN NULL ELSE p_student END, CASE WHEN v_jupeb THEN p_student END, v_n + 1,
            least(now() + make_interval(mins => e.duration_minutes), e.ends_at), v_paper, v_versions, v_marks, v_seed,
            greatest((SELECT sum(m) FROM unnest(v_marks) m), 1), p_ip, p_agent)
    RETURNING * INTO a;
    PERFORM assessment.cbt_log(a.id, 'STARTED', false, format('%s questions, %s marks, ends %s', cardinality(v_paper), a.max_marks, to_char(a.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI:SS')), p_ip);
    RETURN a;
END $$;

-- ── 9 · the candidates of an examination, of either kind ───────────────────────────────────────────────────────

/** a JUPEB candidate's standing on the semester's share of the school fee: paid for the first semester by the first share, after it by the whole fee */
CREATE FUNCTION assessment.cbt_jupeb_fees_paid(p_app uuid, p_semester integer)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_semester = 1 THEN coalesce(f.first_paid, false) OR coalesce(f.full_paid, false)
                ELSE coalesce(f.full_paid, false) OR (coalesce(f.first_paid, false) AND coalesce(f.second_paid, false)) END
      FROM jupeb.school_fees(p_app) f
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
              programme_code text, programme text, level integer, student_status text, entitled boolean, eligible boolean, attempts integer, attempt_id uuid,
              attempt_status text, connection text, started_at timestamp with time zone, ends_at timestamp with time zone, submitted_at timestamp with time zone,
              time_left integer, last_activity_at timestamp with time zone, violations integer, answered integer, score numeric, max_marks integer, percentage numeric,
              grade text, passed boolean, outcome text, updated_at timestamp with time zone)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT x.*, c.general_office, c.kind FROM assessment.cbt_exam x LEFT JOIN catalogue.course c ON c.code = x.course_code WHERE x.id = p_exam),
    cfg AS (SELECT * FROM finance.gst_setting WHERE id = 1),
    reg AS (SELECT DISTINCT cr.student_id FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE e.office <> 'JUPEB' AND en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    base AS (SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex, s.status, s.current_level AS level, s.entry_mode,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty
               FROM reg JOIN people.student s ON s.id = reg.student_id
               JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code),
    pays AS (SELECT r.student_id, count(*) AS n FROM e, finance.payment_reference r
              WHERE e.office IN ('GST', 'EPS') AND r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.student_id IN (SELECT id FROM base)
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
              GROUP BY r.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM e, finance.gst_fee f WHERE e.office IN ('GST', 'EPS') AND f.session = e.session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
    cnt AS (SELECT a.candidate_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam GROUP BY a.candidate_id),
    ent AS (SELECT b.id,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS entitled,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN NOT (fr.id IS NOT NULL AND fr.amount > 0 AND NOT (coalesce(py.n, 0) > 0)
                                  AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND (coalesce(e.general_office, 'GST') = 'GST' OR cfg.covers_eps))
                                       OR (cfg.required_for_all AND finance.gst_required(b.id, e.session))))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS paid_up
              FROM e CROSS JOIN cfg CROSS JOIN base b
              LEFT JOIN pays py ON py.student_id = b.id
              LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                  WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                    AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                  ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                  LIMIT 1) fr ON true),
    -- V365: a JUPEB examination's candidates — the JUPEB students registered for the subject in the session
    jreg AS (SELECT a.id, coalesce(a.exam_no, a.application_no) AS number, upper(a.surname) AS surname,
                    a.first_name || coalesce(' ' || a.middle_name, '') AS other_names, a.sex, a.state, cb.code AS combination, cb.name AS combination_name,
                    assessment.cbt_jupeb_fees_paid(a.id, e.semester) AS paid_up
               FROM e JOIN jupeb.subject_registration r ON r.subject_id = e.jupeb_subject_id AND r.session = e.session
               JOIN jupeb.application a ON a.id = r.application_id
               LEFT JOIN jupeb.combination cb ON cb.id = a.combination_id
              WHERE e.office = 'JUPEB'),
    everyone AS (
        SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
               en.entitled, en.paid_up AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION') AS eligible
          FROM base b JOIN ent en ON en.id = b.id
        UNION ALL
        SELECT j.id, j.number, j.surname, j.other_names, j.sex, 'JUPEB', 'JUPEB programme', NULL, NULL, j.combination, j.combination_name, NULL::int, j.state,
               j.paid_up, j.paid_up AND j.state = 'STUDENT'
          FROM jreg j)
    SELECT v.id, v.number, v.surname, v.other_names, v.sex, v.faculty_code, v.faculty, v.dept_code, v.department, v.programme_code, v.programme, v.level, v.status,
           v.entitled, v.eligible,
           coalesce(cn.attempts, 0), a.id,
           coalesce(a.status, 'NOT_STARTED'),
           CASE WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED' WHEN a.status = 'IN_PROGRESS' THEN 'ONLINE' ELSE NULL END,
           a.started_at, a.ends_at, a.submitted_at,
           CASE WHEN a.status = 'IN_PROGRESS' THEN greatest(0, extract(epoch FROM a.ends_at - now()))::int ELSE NULL END,
           a.last_activity_at, coalesce(a.violations, 0), coalesce(a.answered, 0), a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at
      FROM everyone v
      LEFT JOIN att a ON a.candidate_id = v.id
      LEFT JOIN cnt cn ON cn.candidate_id = v.id
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_monitor_counts(p_exam uuid)
RETURNS TABLE(candidates bigint, eligible bigint, not_started bigint, in_progress bigint, submitted bigint, time_expired bigint, terminated bigint, disconnected bigint,
              warned bigint, critical bigint, scored bigint, live_state text, now timestamp with time zone)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    reg AS (SELECT (SELECT count(DISTINCT cr.student_id) FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                     WHERE e.office <> 'JUPEB' AND en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
                 + (SELECT count(DISTINCT r.application_id) FROM e, jupeb.subject_registration r WHERE e.office = 'JUPEB' AND r.subject_id = e.jupeb_subject_id AND r.session = e.session) AS n),
    el AS (SELECT count(*) FILTER (WHERE c.eligible) AS n FROM assessment.cbt_candidates(p_exam) c),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
    agg AS (SELECT count(*) AS started,
                   count(*) FILTER (WHERE status = 'IN_PROGRESS') AS in_progress,
                   count(*) FILTER (WHERE status = 'SUBMITTED') AS submitted,
                   count(*) FILTER (WHERE status = 'TIME_EXPIRED') AS time_expired,
                   count(*) FILTER (WHERE status = 'TERMINATED') AS terminated,
                   count(*) FILTER (WHERE status = 'IN_PROGRESS' AND last_activity_at < now() - interval '60 seconds') AS disconnected,
                   count(*) FILTER (WHERE violations > 0) AS warned,
                   count(*) FILTER (WHERE violations >= (SELECT violation_limit FROM e)) AS critical,
                   count(*) FILTER (WHERE score IS NOT NULL) AS scored
              FROM att)
    SELECT reg.n, el.n, reg.n - agg.started, agg.in_progress, agg.submitted, agg.time_expired, agg.terminated, agg.disconnected, agg.warned, agg.critical, agg.scored,
           assessment.cbt_live_state(e), now()
      FROM e CROSS JOIN reg CROSS JOIN el CROSS JOIN agg
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_office_summary(p_office text, p_session text)
RETURNS TABLE(exams bigint, upcoming bigint, open bigint, completed bigint, draft bigint, writing bigint, scores bigint, results_pending bigint, results_published bigint, candidates bigint)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT x.*, assessment.cbt_live_state(x) AS live FROM assessment.cbt_exam x WHERE x.office = upper(p_office) AND (p_session IS NULL OR x.session = p_session)),
    a AS (SELECT a.exam_id, count(*) FILTER (WHERE a.status = 'IN_PROGRESS') AS writing, count(*) FILTER (WHERE a.score IS NOT NULL) AS scored
            FROM assessment.cbt_attempt a WHERE a.exam_id IN (SELECT id FROM e) GROUP BY a.exam_id),
    reg AS (SELECT e.id, count(DISTINCT cr.student_id) AS n FROM e JOIN registration.entry en ON en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED')
              JOIN registration.course_registration cr ON cr.id = en.registration_id AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED') GROUP BY e.id
            UNION ALL
            SELECT e.id, count(DISTINCT r.application_id) FROM e JOIN jupeb.subject_registration r ON r.subject_id = e.jupeb_subject_id AND r.session = e.session GROUP BY e.id)
    SELECT count(*), count(*) FILTER (WHERE live IN ('SCHEDULED', 'UPCOMING')), count(*) FILTER (WHERE live = 'OPEN'), count(*) FILTER (WHERE live = 'COMPLETED'),
           count(*) FILTER (WHERE live = 'DRAFT'),
           coalesce(sum(a.writing), 0), coalesce(sum(a.scored), 0),
           count(*) FILTER (WHERE e.state = 'COMPLETED' AND e.results_state <> 'PUBLISHED'), count(*) FILTER (WHERE e.results_state = 'PUBLISHED'),
           coalesce(sum(reg.n), 0)
      FROM e LEFT JOIN a ON a.exam_id = e.id LEFT JOIN reg ON reg.id = e.id
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_notify_candidates(p_exam uuid, p_subject text, p_body text, p_only_sat boolean)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; r record; n int := 0;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF e.office = 'JUPEB' THEN
        -- V365: a JUPEB examination's candidates, at the email they applied with
        FOR r IN
            SELECT DISTINCT a.id, a.email FROM jupeb.subject_registration sr JOIN jupeb.application a ON a.id = sr.application_id
             WHERE sr.subject_id = e.jupeb_subject_id AND sr.session = e.session AND a.state = 'STUDENT' AND a.email IS NOT NULL
               AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.exam_id = p_exam AND t.candidate_id = a.id AND t.status <> 'IN_PROGRESS'))
        LOOP
            PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body || E'\n\nJUPEB Office, ' || (platform.institution() ->> 'name'), 'jupeb_application', r.id);
            n := n + 1;
        END LOOP;
        RETURN n;
    END IF;
    FOR r IN
        SELECT DISTINCT cr.student_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
         WHERE en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
           AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam AND a.student_id = cr.student_id AND a.status <> 'IN_PROGRESS'))
    LOOP
        PERFORM platform.queue_notice('EMAIL', x.email, p_subject, p_body || E'\n\n' || CASE e.office WHEN 'EXAMS' THEN 'Examinations Office' ELSE e.office || ' Office' END || ', ' || (platform.institution() ->> 'name'), 'student', r.student_id)
          FROM people.student_reach(r.student_id) x WHERE x.email IS NOT NULL;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- ── 10 · the lifecycle: a JUPEB examination's subject still examined by CBT, and its words ─────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_exam_action(p_exam uuid, p_action text, p_reason text)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_act text := lower(btrim(coalesce(p_action, ''))); v_ready text; r record; v_fees text; v_what text; v_where text;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    v_fees := CASE WHEN e.office IN ('GST', 'EPS') THEN 'Your GST fee must be paid and the course on your registration'
                   WHEN e.office = 'JUPEB' THEN 'The semester''s share of your JUPEB school fee must be paid and the subject on your registration'
                   ELSE 'Your school fees must be cleared for examinations and the course on your registration' END;
    v_what := coalesce(e.course_code, (SELECT s.code FROM jupeb.subject s WHERE s.id = e.jupeb_subject_id));
    v_where := CASE WHEN e.office = 'JUPEB' THEN 'the JUPEB portal' ELSE 'the portal' END;
    IF v_act = 'schedule' THEN
        IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not scheduled', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF e.starts_at IS NULL OR e.ends_at IS NULL THEN RAISE EXCEPTION 'CBT_WINDOW_REQUIRED: set the date and time the examination opens and closes first' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'SCHEDULED' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'publish' THEN
        IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not published', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF e.starts_at IS NULL OR e.ends_at IS NULL THEN RAISE EXCEPTION 'CBT_WINDOW_REQUIRED: set the date and time the examination opens and closes first' USING ERRCODE = '23514'; END IF;
        IF e.ends_at <= now() THEN RAISE EXCEPTION 'CBT_WINDOW_PAST: the examination window has already passed' USING ERRCODE = '23514'; END IF;
        IF e.office = 'JUPEB' THEN
            IF NOT coalesce((SELECT cbt_enabled FROM jupeb.subject WHERE id = e.jupeb_subject_id), false) THEN
                RAISE EXCEPTION 'CBT_COURSE_NOT_ENABLED: % is not examined by CBT', v_what USING ERRCODE = '23514';
            END IF;
        ELSIF NOT coalesce((SELECT cbt_enabled FROM catalogue.course WHERE code = e.course_code), false) THEN
            RAISE EXCEPTION 'CBT_COURSE_NOT_ENABLED: % is not a CBT course', e.course_code USING ERRCODE = '23514';
        END IF;
        v_ready := assessment.cbt_paper_ready(e.id);
        IF v_ready IS NOT NULL THEN RAISE EXCEPTION '%', v_ready USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'PUBLISHED', published_at = coalesce(published_at, now()) WHERE id = e.id RETURNING * INTO e;
        PERFORM assessment.cbt_notify_candidates(e.id, v_what || ' CBT examination: ' || e.title,
            'Your ' || v_what || ' computer-based examination, ' || e.title || ', is scheduled for ' || to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY')
            || ' from ' || to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI') || ' to ' || to_char(e.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI')
            || ' (' || e.duration_minutes || ' minutes once you start). Sign in to ' || v_where || ', open CBT Examinations, read the instructions and start within the window. '
            || v_fees || '.', false);
    ELSIF v_act = 'unpublish' THEN
        IF e.state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_STATE: only a published examination is withdrawn' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM assessment.cbt_attempt WHERE exam_id = e.id) THEN RAISE EXCEPTION 'CBT_HAS_ATTEMPTS: candidates have sat this examination; close or cancel it instead' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'SCHEDULED' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'close' THEN
        IF e.state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_STATE: only a published examination is closed' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'CLOSED', closed_at = now(), ends_at = least(ends_at, now()) WHERE id = e.id RETURNING * INTO e;
        FOR r IN SELECT id FROM assessment.cbt_attempt WHERE exam_id = e.id AND status = 'IN_PROGRESS' LOOP
            PERFORM assessment.cbt_log(r.id, 'AUTO_SUBMITTED', false, 'the examination was closed by the office', NULL);
            PERFORM assessment.cbt_finalize(r.id, 'SUBMITTED', 'the examination was closed by the office');
        END LOOP;
    ELSIF v_act = 'complete' THEN
        IF NOT (e.state = 'CLOSED' OR (e.state = 'PUBLISHED' AND e.ends_at <= now())) THEN
            RAISE EXCEPTION 'CBT_STATE: an examination is completed once its window has passed or it is closed' USING ERRCODE = '23514';
        END IF;
        PERFORM assessment.cbt_finalize(id, 'TIME_EXPIRED', 'time expired') FROM assessment.cbt_attempt WHERE exam_id = e.id AND status = 'IN_PROGRESS';
        UPDATE assessment.cbt_exam SET state = 'COMPLETED', completed_at = now(), closed_at = coalesce(closed_at, now()),
               results_state = CASE WHEN results_state = 'PENDING' THEN 'AUTO_SCORED' ELSE results_state END
         WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'cancel' THEN
        IF e.state IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not cancelled', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'CBT_REASON_REQUIRED: cancelling an examination names its reason' USING ERRCODE = '23514'; END IF;
        FOR r IN SELECT id FROM assessment.cbt_attempt WHERE exam_id = e.id AND status = 'IN_PROGRESS' LOOP
            PERFORM assessment.cbt_finalize(r.id, 'TERMINATED', 'the examination was cancelled: ' || btrim(p_reason));
        END LOOP;
        UPDATE assessment.cbt_exam SET state = 'CANCELLED', cancelled_at = now(), cancel_reason = btrim(p_reason) WHERE id = e.id RETURNING * INTO e;
        IF e.published_at IS NOT NULL THEN
            PERFORM assessment.cbt_notify_candidates(e.id, v_what || ' CBT examination cancelled: ' || e.title,
                'The ' || v_what || ' computer-based examination, ' || e.title || ', is cancelled. Reason: ' || btrim(p_reason) || '. You will be told when it is rescheduled.', false);
        END IF;
    ELSIF v_act = 'archive' THEN
        IF e.state NOT IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: an examination is archived once it is completed or cancelled' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET archived_at = coalesce(archived_at, now()) WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'unarchive' THEN
        UPDATE assessment.cbt_exam SET archived_at = NULL WHERE id = e.id RETURNING * INTO e;
    ELSE
        RAISE EXCEPTION 'CBT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN e;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_results_action(p_exam uuid, p_action text)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_act text := lower(btrim(coalesce(p_action, ''))); v_what text;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    v_what := coalesce(e.course_code, (SELECT s.code FROM jupeb.subject s WHERE s.id = e.jupeb_subject_id));
    IF v_act = 'review' THEN
        IF e.results_state NOT IN ('PENDING', 'AUTO_SCORED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are %', lower(replace(e.results_state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'UNDER_REVIEW' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'approve' THEN
        IF e.state <> 'COMPLETED' THEN RAISE EXCEPTION 'CBT_NOT_COMPLETED: complete the examination before its results are approved' USING ERRCODE = '23514'; END IF;
        IF e.results_state NOT IN ('AUTO_SCORED', 'UNDER_REVIEW') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are %', lower(replace(e.results_state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'APPROVED', results_approved_at = now(), results_approved_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
         WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'publish' THEN
        IF e.results_state <> 'APPROVED' THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: results are published once approved' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'PUBLISHED', results_published_at = now() WHERE id = e.id RETURNING * INTO e;
        PERFORM assessment.cbt_notify_candidates(e.id, v_what || ' CBT result published: ' || e.title,
            'Your result for the ' || v_what || ' computer-based examination, ' || e.title || ', is published. Sign in to ' || CASE WHEN e.office = 'JUPEB' THEN 'the JUPEB portal' ELSE 'the portal' END
            || ' and open CBT Examinations to see it.', true);
    ELSIF v_act = 'unpublish' THEN
        IF e.results_state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are not published' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'APPROVED', results_published_at = NULL WHERE id = e.id RETURNING * INTO e;
    ELSE
        RAISE EXCEPTION 'CBT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN e;
END $$;

-- ── 11 · the JUPEB candidate's own list ─────────────────────────────────────────────────────────────────────────

CREATE FUNCTION assessment.cbt_jupeb_exams(p_app uuid, p_session text)
RETURNS TABLE(exam_id uuid, reference text, office text, course_code text, course_title text, title text, session text, semester integer, instructions text,
              live_state text, starts_at timestamp with time zone, ends_at timestamp with time zone, duration_minutes integer, questions integer, security_mode text,
              venue text, attempt_limit integer, violation_limit integer, violation_action text, eligibility text, attempts integer, attempt_id uuid, attempt_status text,
              attempt_ends_at timestamp with time zone, submitted_at timestamp with time zone, result_published boolean, score numeric, max_marks integer,
              percentage numeric, grade text, passed boolean, pass_mark numeric, outcome text, partial_credit boolean,
              exam_type text, negative_marks numeric, allow_back boolean, allow_review boolean, fullscreen_required boolean, proctoring text, score_on_submit boolean)
LANGUAGE sql STABLE AS $$
    WITH mine AS (SELECT DISTINCT r.subject_id, r.session FROM jupeb.subject_registration r WHERE r.application_id = p_app AND (p_session IS NULL OR r.session = p_session)),
    att AS (SELECT DISTINCT ON (a.exam_id) a.* FROM assessment.cbt_attempt a WHERE a.jupeb_application_id = p_app ORDER BY a.exam_id, a.number DESC),
    cnt AS (SELECT a.exam_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.jupeb_application_id = p_app GROUP BY a.exam_id),
    v AS (SELECT e.*, assessment.cbt_live_state(e) AS live,
                 (e.results_state = 'PUBLISHED' OR (e.score_on_submit AND a.status IS NOT NULL AND a.status <> 'IN_PROGRESS')) AS shown, a.id AS a_id, a.status AS a_status,
                 a.ends_at AS a_ends_at, a.submitted_at AS a_submitted_at, a.score AS a_score, a.max_marks AS a_max, a.percentage AS a_pct, a.grade AS a_grade,
                 a.passed AS a_passed, a.outcome AS a_outcome, cn.attempts AS a_attempts
            FROM assessment.cbt_exam e JOIN mine m ON m.subject_id = e.jupeb_subject_id AND m.session = e.session
            LEFT JOIN att a ON a.exam_id = e.id LEFT JOIN cnt cn ON cn.exam_id = e.id
           WHERE e.office = 'JUPEB' AND e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED'))
    SELECT v.id, v.reference, v.office, s.code, s.title, v.title, v.session, v.semester, v.instructions,
           v.live, v.starts_at, v.ends_at, v.duration_minutes,
           CASE WHEN v.selection = 'RANDOM' THEN v.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(v.id)) END,
           v.security_mode, v.venue, v.attempt_limit, v.violation_limit, v.violation_action,
           CASE WHEN v.a_status = 'IN_PROGRESS' THEN NULL ELSE assessment.cbt_jupeb_eligibility(v.id, p_app) END,
           coalesce(v.a_attempts, 0), v.a_id, v.a_status, v.a_ends_at, v.a_submitted_at,
           (v.results_state = 'PUBLISHED'),
           CASE WHEN v.shown THEN v.a_score END, CASE WHEN v.shown THEN v.a_max END, CASE WHEN v.shown THEN v.a_pct END, CASE WHEN v.shown THEN v.a_grade END,
           CASE WHEN v.shown THEN v.a_passed END, v.pass_mark, CASE WHEN v.shown THEN v.a_outcome END, v.partial_credit,
           v.exam_type, v.negative_marks, v.allow_back, v.allow_review, v.fullscreen_required, v.proctoring, v.score_on_submit
      FROM v JOIN jupeb.subject s ON s.id = v.jupeb_subject_id
     ORDER BY v.starts_at DESC NULLS LAST, v.title
$$;

-- ── 12 · a JUPEB result into the JUPEB continuous assessment; the University's score sheet is not a JUPEB one ────

CREATE FUNCTION assessment.cbt_to_jupeb_ca(p_exam uuid)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; c jupeb.ca_component; r record; n int := 0; v_score numeric;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.office <> 'JUPEB' THEN RAISE EXCEPTION 'CBT_NOT_JUPEB: a University examination goes onto the course''s score sheet' USING ERRCODE = '23514'; END IF;
    IF e.sheet_component <> 'CA' OR e.jupeb_ca_component_id IS NULL THEN
        RAISE EXCEPTION 'CBT_NOT_FOR_SHEET: name the part of the JUPEB continuous assessment this examination counts towards first' USING ERRCODE = '23514';
    END IF;
    IF e.results_state NOT IN ('APPROVED', 'PUBLISHED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: approve the results before they go into the continuous assessment' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM jupeb.ca_component WHERE id = e.jupeb_ca_component_id;
    FOR r IN
        SELECT DISTINCT ON (a.jupeb_application_id) a.jupeb_application_id AS app, a.percentage, a.outcome
          FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status <> 'IN_PROGRESS' AND a.percentage IS NOT NULL
         ORDER BY a.jupeb_application_id, a.percentage DESC, a.number DESC
    LOOP
        v_score := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * c.max_score / 100.0, 2) END;
        -- through the JUPEB Office's own door: the registration, the part's session and range, and the lock are judged there
        PERFORM jupeb.ca_save(r.app, e.jupeb_subject_id, c.id, v_score, nullif(current_setting('moaum.actor_id', true), '')::uuid,
                              coalesce(nullif(current_setting('moaum.actor_office', true), ''), 'jupeb'));
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION assessment.cbt_to_jupeb_ca(uuid) IS 'V365: each JUPEB candidate''s best approved result, scaled to the named part''s maximum, written into the JUPEB continuous assessment through jupeb.ca_save (its registration, range and lock rules).';

CREATE OR REPLACE FUNCTION assessment.cbt_to_sheet(p_exam uuid)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; sh assessment.score_sheet; v_ca_max int; r record; n int := 0; v_version int; v_ca int; v_old_exam int; v_new_ca int; v_new_exam int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.office = 'JUPEB' THEN RETURN assessment.cbt_to_jupeb_ca(p_exam); END IF;
    IF e.sheet_component = 'NONE' THEN
        RAISE EXCEPTION 'CBT_NOT_FOR_SHEET: this examination is set not to count on the score sheet' USING ERRCODE = '23514';
    END IF;
    IF e.results_state NOT IN ('APPROVED', 'PUBLISHED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: approve the results before they go onto the score sheet' USING ERRCODE = '23514'; END IF;
    SELECT * INTO sh FROM assessment.score_sheet WHERE offering_id = e.offering_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_NO_SHEET: the course has no score sheet yet; it opens with the examination session' USING ERRCODE = '23514'; END IF;
    IF sh.stage <> 'ENTRY' THEN RAISE EXCEPTION 'CBT_SHEET_NOT_AT_ENTRY: the score sheet is at %; scores are entered at entry', lower(replace(sh.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    SELECT ca_max INTO v_ca_max FROM catalogue.course WHERE code = e.course_code;
    FOR r IN
        SELECT DISTINCT ON (a.student_id) a.student_id, a.percentage, a.outcome
          FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status <> 'IN_PROGRESS' AND a.percentage IS NOT NULL
         ORDER BY a.student_id, a.percentage DESC, a.number DESC
    LOOP
        v_version := NULL; v_ca := NULL; v_old_exam := NULL;
        SELECT l.version, l.ca, l.exam INTO v_version, v_ca, v_old_exam FROM assessment.latest_scores(sh.id) l WHERE l.student_id = r.student_id;
        IF e.sheet_component = 'CA' THEN
            v_new_ca := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * v_ca_max / 100.0)::int END;
            v_new_exam := v_old_exam;
        ELSE
            v_new_ca := v_ca;
            v_new_exam := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * (100 - v_ca_max) / 100.0)::int END;
        END IF;
        IF v_version IS NOT NULL AND EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = sh.id AND s.student_id = r.student_id AND s.version = v_version
                                               AND s.ca IS NOT DISTINCT FROM v_new_ca AND s.exam IS NOT DISTINCT FROM v_new_exam AND s.reason LIKE 'CBT ' || e.reference || '%') THEN
            CONTINUE;
        END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (sh.id, r.student_id, coalesce(v_version, 0) + 1, v_new_ca, v_new_exam,
                CASE WHEN v_new_ca IS NULL OR v_new_exam IS NULL THEN 'INCOMPLETE' ELSE 'GRADED' END,
                'CBT ' || e.reference || ': ' || e.title || ' — ' || CASE e.sheet_component WHEN 'CA' THEN 'continuous assessment' ELSE 'examination component' END
                || ' from the computer-based test');
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

COMMIT;
