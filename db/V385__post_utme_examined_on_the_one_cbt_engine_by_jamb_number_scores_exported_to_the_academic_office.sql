-- ═══════════════════════════════════════════════════════════════════════════
-- V385 — Post-UTME examined on the one CBT engine: the candidate by JAMB
--        number at a controlled door, the scores exported to the Academic Office
--
--   V260 gave Post-UTME its scheduling (centres, rooms, batches, slips, the
--   door's check-in) and left the score to be entered or uploaded. V322–V376
--   built the University's CBT engine and V365 opened it to a second kind of
--   candidate (a JUPEB student). This migration opens it to a third — a
--   Post-UTME applicant (admissions.application) — without a second engine, a
--   second bank, a second candidate table or a second result system:
--
--   1 · an examination of office POST_UTME examines an admission session
--       (cbt_exam.putme_session), with a question bank of its own on
--       assessment.question (putme_session; bank key "PUTME:<session>"), frozen
--       by version like every bank (V364), moderated like every bank (V374);
--   2 · the attempt names its candidate: a student, a JUPEB student, or an
--       application (application_id; candidate_id is whichever it is);
--   3 · the candidate's door is public — the JAMB registration number plus a
--       second factor the examination names (the application number, the slip
--       token, the registered phone or the date of birth on record) — never the
--       dashboard, never the JAMB number alone; eligibility is judged here on
--       the record (V260's putme_eligibility: the programme screened by
--       examination, the fee confirmed, the application submitted, not
--       disqualified, not already scored) and on the Director of ICT's window;
--   4 · two windows of the Director of ICT: POST_UTME_CBT (may candidates sit)
--       and POST_UTME_RESULT_CHECKING (may candidates read a released score),
--       both closed until first opened, independent of Post-UTME registration;
--   5 · the score stays in the engine: a Post-UTME result is never published to
--       the candidate through the examination door (score_on_submit refused,
--       results 'publish' refused). The Director reviews and approves, exports
--       an official batch (a snapshot with its hash and reference), sends it to
--       the Academic Office through the portal, and the Academic Office
--       receives, previews and imports it into admissions.application
--       .screening_score — the same column the admission has always read — with
--       a released score never overwritten and an existing one replaced only by
--       an authorised act with its reason, the previous value kept;
--   6 · the candidate reads a score only on the result-checking page, only
--       while that window is open, and only once the Academic Office has
--       released the scores (admissions.release_scores, as before).
--
--   The admission itself does not change: the merit list, the eligibility
--   engine and the template read screening_score as they did.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V385: Post-UTME examined on the one CBT engine', true);

-- ── 1 · the Post-UTME CBT candidate: an office of their own, so the examination token opens no dashboard ──
-- A token the gateway issues carries this office alone: the applicant's dashboard (OFFICE_applicant) stays closed to it,
-- and the CBT door (OFFICE_putmecbt) stays closed to an applicant's ordinary sign-in.
INSERT INTO ref.office (code, label, scope_kind) VALUES ('putmecbt', 'Post-UTME CBT candidate', 'institution') ON CONFLICT (code) DO NOTHING;

-- ── 2 · the Director of ICT's two windows ──────────────────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check CHECK (window_type = ANY (ARRAY[
    'SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
    'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
    'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION',    -- V380
    'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING']));
ALTER TABLE policy.portal_window DROP CONSTRAINT ck_window_application_session;
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_application_session
    CHECK (window_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')
           OR (semester IS NULL AND late_until IS NULL AND NOT late_fee_enabled));
ALTER TABLE policy.portal_window_message DROP CONSTRAINT IF EXISTS portal_window_message_window_type_check;
ALTER TABLE policy.portal_window_message ADD CONSTRAINT portal_window_message_window_type_check
    CHECK (window_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING'));
INSERT INTO policy.portal_window_message (window_type, message) VALUES
  ('POST_UTME_CBT',
   E'THE POST-UTME CBT EXAMINATION IS NOT OPEN\n\nThe computer-based Post-UTME examination is not open to candidates at this time.\nYour examination date, time and centre are on your screening slip; the examination opens on the portal at the time announced by the University.'),
  ('POST_UTME_RESULT_CHECKING',
   E'POST-UTME RESULT CHECKING IS CLOSED\n\nThe Post-UTME scores are not yet available for checking. The University announces when results may be checked on the portal.')
ON CONFLICT (window_type) DO NOTHING;

CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamptz, closes_at timestamptz, late_until timestamptz, late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
LANGUAGE sql STABLE AS $$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING') THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING') THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$$;

-- V380 verbatim, with the two Post-UTME windows: session-wide, no semester, no late period
CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamptz, p_closes timestamptz, p_late_until timestamptz, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
                      'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')
       AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: this window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $$;

-- ── 3 · a Post-UTME question bank: the session's, on the one question table ──
ALTER TABLE assessment.question ADD COLUMN putme_session text NULL REFERENCES policy.academic_session(name);
ALTER TABLE assessment.question DROP CONSTRAINT ck_question_bank;
ALTER TABLE assessment.question ADD CONSTRAINT ck_question_bank
    CHECK ((course_code IS NOT NULL)::int + (jupeb_subject_id IS NOT NULL)::int + (putme_session IS NOT NULL)::int = 1);
CREATE INDEX ix_question_putme_active ON assessment.question (putme_session, active) WHERE putme_session IS NOT NULL;
COMMENT ON COLUMN assessment.question.putme_session IS 'V385: the admission session whose Post-UTME bank the question is in (bank key PUTME:<session>), instead of a course or a JUPEB subject.';

-- ── 4 · an examination of office POST_UTME examines an admission session ────
ALTER TABLE assessment.cbt_exam DROP CONSTRAINT cbt_exam_office_check;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT cbt_exam_office_check CHECK (office IN ('GST', 'EPS', 'EXAMS', 'JUPEB', 'POST_UTME'));
ALTER TABLE assessment.cbt_exam
    ADD COLUMN putme_session text NULL REFERENCES policy.academic_session(name),
    ADD COLUMN putme_verify  text NOT NULL DEFAULT 'APPLICATION_NO'
        CONSTRAINT ck_cbt_exam_putme_verify CHECK (putme_verify IN ('APPLICATION_NO', 'SLIP_TOKEN', 'PHONE', 'DATE_OF_BIRTH'));
ALTER TABLE assessment.cbt_exam DROP CONSTRAINT ck_cbt_exam_what;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT ck_cbt_exam_what
    CHECK (CASE WHEN office = 'JUPEB'     THEN jupeb_subject_id IS NOT NULL AND course_code IS NULL AND offering_id IS NULL AND putme_session IS NULL
                WHEN office = 'POST_UTME' THEN putme_session IS NOT NULL AND course_code IS NULL AND offering_id IS NULL AND jupeb_subject_id IS NULL AND jupeb_ca_component_id IS NULL
                ELSE jupeb_subject_id IS NULL AND jupeb_ca_component_id IS NULL AND putme_session IS NULL AND course_code IS NOT NULL AND offering_id IS NOT NULL END);
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT ck_cbt_exam_putme_sheet CHECK (office <> 'POST_UTME' OR (sheet_component = 'NONE' AND NOT score_on_submit));
CREATE UNIQUE INDEX ux_cbt_exam_putme_title ON assessment.cbt_exam (putme_session, title) WHERE putme_session IS NOT NULL;
COMMENT ON COLUMN assessment.cbt_exam.putme_session IS 'V385: the admission session a Post-UTME examination (office POST_UTME) examines; its candidates are that session''s submitted applicants.';
COMMENT ON COLUMN assessment.cbt_exam.putme_verify IS 'V385: the second factor a Post-UTME candidate gives beside the JAMB registration number at the examination door: the application number, the screening slip token, the phone they registered with, or the date of birth on record.';

CREATE OR REPLACE FUNCTION assessment.cbt_exam_name(e assessment.cbt_exam)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(e.course_code, (SELECT 'JUPEB ' || s.code FROM jupeb.subject s WHERE s.id = e.jupeb_subject_id),
                    CASE WHEN e.office = 'POST_UTME' THEN 'Post-UTME ' || e.putme_session END, 'CBT')
$$;

-- the pool and the live-bank rule (V374 verbatim: a whole-bank pool draws approved questions only) read the third kind of bank
CREATE OR REPLACE FUNCTION assessment.cbt_pool(p_exam uuid)
RETURNS TABLE(question_id uuid, ordinal integer, marks integer)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
         own AS (SELECT eq.question_id, eq.ordinal, coalesce(eq.marks, q.marks) AS marks
                   FROM assessment.cbt_exam_question eq JOIN assessment.question q ON q.id = eq.question_id AND q.active
                  WHERE eq.exam_id = p_exam)
    SELECT * FROM own
    UNION ALL
    SELECT q.id, 0, q.marks FROM e JOIN assessment.question q ON (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id OR q.putme_session = e.putme_session) AND q.active
                                                              AND q.moderation = 'APPROVED'
     WHERE e.selection = 'RANDOM' AND NOT EXISTS (SELECT 1 FROM own)
$$;

CREATE OR REPLACE FUNCTION assessment.question_in_live_exam(p_question uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT e.reference FROM assessment.cbt_exam e
      JOIN assessment.question q ON q.id = p_question AND (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id OR q.putme_session = e.putme_session)
     WHERE e.state = 'PUBLISHED' AND e.ends_at > now()
       AND (EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id AND eq.question_id = p_question)
            OR (e.selection = 'RANDOM' AND q.moderation = 'APPROVED' AND NOT EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id)))
     LIMIT 1
$$;

CREATE FUNCTION assessment.cbt_new_putme_exam(p_session text, p_title text, p_instructions text, p_duration integer, p_total integer,
                                              p_selection text, p_random_q boolean, p_random_o boolean, p_pass numeric, p_attempts integer, p_security text, p_venue text,
                                              p_violation_limit integer, p_violation_action text, p_second_session text, p_starts timestamptz, p_ends timestamptz)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam;
BEGIN
    IF p_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'CBT_SESSION: % is not a session on the University calendar', coalesce(p_session, 'no session') USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.cbt_exam (reference, office, course_code, offering_id, putme_session, session, semester, title, instructions, duration_minutes, total_questions,
                                     selection, randomize_questions, randomize_options, pass_mark, attempt_limit, security_mode, venue, violation_limit,
                                     violation_action, second_session, starts_at, ends_at, sheet_component, score_on_submit, created_by, created_office)
    VALUES ('CBT/' || replace(p_session, '/', '-') || '/' || lpad(platform.next_number('cbt_exam', 'UNIVERSITY', p_session)::text, 5, '0'),
            'POST_UTME', NULL, NULL, p_session, p_session, 1, btrim(p_title), nullif(btrim(coalesce(p_instructions, '')), ''),
            coalesce(p_duration, 60), coalesce(p_total, 0), coalesce(upper(p_selection), 'RANDOM'), coalesce(p_random_q, true), coalesce(p_random_o, true),
            coalesce(p_pass, 0), coalesce(p_attempts, 1), coalesce(upper(p_security), 'STANDARD'), coalesce(upper(p_venue), 'LAB'),
            coalesce(p_violation_limit, 3), coalesce(upper(p_violation_action), 'WARN'), coalesce(upper(p_second_session), 'DENY'),
            p_starts, p_ends, 'NONE', false, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING * INTO e;
    RETURN e;
END $$;
COMMENT ON FUNCTION assessment.cbt_new_putme_exam IS 'V385: a Post-UTME CBT examination of an admission session; its result goes to no score sheet and is never shown on submission — the Academic Office imports the exported scores.';

-- the further settings, with a Post-UTME examination's own: the second factor at its door; a score shown on submission refused
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
    -- V385: a Post-UTME score goes to no sheet and is never shown on submission; the Academic Office imports it
    IF e.office = 'POST_UTME' AND p ? 'sheetComponent' AND upper(p->>'sheetComponent') <> 'NONE' THEN
        RAISE EXCEPTION 'CBT_SETTING: a Post-UTME score goes to no score sheet; the Academic Office imports the exported scores' USING ERRCODE = '23514';
    END IF;
    IF e.office = 'POST_UTME' AND p ? 'scoreOnSubmit' AND (p->>'scoreOnSubmit')::boolean THEN
        RAISE EXCEPTION 'CBT_PUTME_NO_SCORE_ON_SUBMIT: a Post-UTME candidate is never shown a score on submission; results reach candidates through the Academic Office''s release and the result-checking window' USING ERRCODE = '23514';
    END IF;
    IF p ? 'putmeVerify' THEN
        IF e.office <> 'POST_UTME' THEN RAISE EXCEPTION 'CBT_SETTING: the second factor at the door is a Post-UTME examination''s setting' USING ERRCODE = '23514'; END IF;
        IF upper(p->>'putmeVerify') NOT IN ('APPLICATION_NO', 'SLIP_TOKEN', 'PHONE', 'DATE_OF_BIRTH') THEN
            RAISE EXCEPTION 'CBT_SETTING: the second factor is the application number, the slip token, the registered phone or the date of birth' USING ERRCODE = '23514';
        END IF;
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
        jupeb_ca_component_id = CASE WHEN p ? 'jupebCaComponentId' THEN nullif(p->>'jupebCaComponentId', '')::uuid ELSE jupeb_ca_component_id END,
        putme_verify = CASE WHEN p ? 'putmeVerify' THEN upper(p->>'putmeVerify') ELSE putme_verify END
     WHERE id = e.id RETURNING * INTO e;
    IF NOT e.allow_back AND e.allow_review THEN
        UPDATE assessment.cbt_exam SET allow_review = false WHERE id = e.id RETURNING * INTO e;
    END IF;
    RETURN e;
END $$;

-- ── 5 · the attempt names its candidate: a student, a JUPEB student, or an application ──
ALTER TABLE assessment.cbt_attempt DROP CONSTRAINT cbt_attempt_exam_candidate_number_key;
DROP INDEX assessment.ux_cbt_attempt_active;
ALTER TABLE assessment.cbt_attempt DROP CONSTRAINT ck_cbt_attempt_candidate;
ALTER TABLE assessment.cbt_attempt DROP COLUMN candidate_id;
ALTER TABLE assessment.cbt_attempt ADD COLUMN application_id uuid NULL REFERENCES admissions.application(id);
ALTER TABLE assessment.cbt_attempt ADD COLUMN candidate_id uuid GENERATED ALWAYS AS (coalesce(student_id, jupeb_application_id, application_id)) STORED;
ALTER TABLE assessment.cbt_attempt ADD CONSTRAINT ck_cbt_attempt_candidate
    CHECK ((student_id IS NOT NULL)::int + (jupeb_application_id IS NOT NULL)::int + (application_id IS NOT NULL)::int = 1);
ALTER TABLE assessment.cbt_attempt ADD CONSTRAINT cbt_attempt_exam_candidate_number_key UNIQUE (exam_id, candidate_id, number);
CREATE UNIQUE INDEX ux_cbt_attempt_active ON assessment.cbt_attempt (exam_id, candidate_id) WHERE status = 'IN_PROGRESS';
CREATE INDEX ix_cbt_attempt_application ON assessment.cbt_attempt (application_id, exam_id) WHERE application_id IS NOT NULL;
COMMENT ON COLUMN assessment.cbt_attempt.application_id IS 'V385: the Post-UTME application whose candidate sat this attempt (office POST_UTME); candidate_id is whichever of the three kinds it is.';

-- ── 6 · eligibility: a Post-UTME applicant on the record and on the Director's window ──
CREATE FUNCTION assessment.cbt_putme_eligibility(p_exam uuid, p_app uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; a admissions.application; c admissions.candidate; el record; w record; v_ready text; n int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT * INTO w FROM policy.window_state('POST_UTME_CBT', e.putme_session, NULL);
    IF w.state <> 'OPEN' THEN RETURN format('CBT_PUTME_WINDOW: the Post-UTME CBT for %s is %s', e.putme_session, lower(w.state)); END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND OR a.session <> e.putme_session THEN RETURN format('CBT_PUTME_NOT_CANDIDATE: you are not a Post-UTME applicant of %s', e.putme_session); END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    IF c.entry_mode = 'CCE' THEN RETURN 'CBT_PUTME_NOT_CANDIDATE: the Centre for Continuing Education''s applicants do not sit the Post-UTME examination'; END IF;
    SELECT * INTO el FROM admissions.putme_eligibility(p_app);
    IF el.status = 'NOT_ELIGIBLE' THEN RETURN 'CBT_PUTME_NOT_ELIGIBLE: ' || el.why; END IF;
    IF el.status = 'DISQUALIFIED' THEN RETURN 'CBT_PUTME_DISQUALIFIED: ' || el.why; END IF;
    IF el.status = 'PAYMENT_PENDING' THEN RETURN 'CBT_PUTME_FEE: the Post-UTME screening fee is not confirmed on your application'; END IF;
    IF el.status = 'DOCUMENT_PENDING' THEN RETURN 'CBT_PUTME_NOT_SUBMITTED: your Post-UTME application is not yet submitted'; END IF;
    IF a.screening_score IS NOT NULL THEN RETURN 'CBT_PUTME_SCORED: a Post-UTME score is already on your record'; END IF;
    IF el.status = 'EXAM_COMPLETED' THEN RETURN 'CBT_PUTME_SAT: the examination is recorded as sat'; END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_app AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION assessment.cbt_putme_eligibility(uuid, uuid) IS 'V385: why a Post-UTME applicant may not sit an examination now — ''CODE: message'' — or NULL: published, the Director''s POST_UTME_CBT window open, an applicant of the session, eligible on the record (V260), not already scored, the paper ready, the window and the attempt limit.';

-- ── 7 · the start: V375 verbatim, the attempt owned by whichever kind the examination examines ──
-- (assessment.cbt_eligibility stays as it is: a Post-UTME examination's candidate is judged by cbt_putme_eligibility here, at the start)
CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; a assessment.cbt_attempt; v_why text; v_seed int; v_paper uuid[]; v_versions int[]; v_marks int[]; v_n int;
        v_sit assessment.cbt_sitting; v_extra int; v_mark assessment.cbt_attendance;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(p_exam::text || ':' || p_student::text));
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
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
    -- V385: a Post-UTME applicant is judged by the admission's rules and the Director's window; every other candidate as before
    v_why := CASE WHEN e.office = 'POST_UTME' THEN assessment.cbt_putme_eligibility(p_exam, p_student) ELSE assessment.cbt_eligibility(p_exam, p_student) END;
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514', HINT = 'Eligibility is judged on the record: the registration, the payments on the ledger, the examination window.';
    END IF;
    -- V373: an examination sat in sittings opens to a candidate only in their own sitting
    IF EXISTS (SELECT 1 FROM assessment.cbt_sitting s WHERE s.exam_id = p_exam) THEN
        SELECT s.* INTO v_sit FROM assessment.cbt_seat x JOIN assessment.cbt_sitting s ON s.id = x.sitting_id WHERE x.exam_id = p_exam AND x.candidate_id = p_student;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'CBT_NO_SITTING: you have no seat in this examination''s sittings' USING ERRCODE = '23514',
                HINT = 'The examination office seats every candidate; ask it for your sitting.';
        END IF;
        IF now() < v_sit.starts_at OR now() >= v_sit.ends_at THEN
            RAISE EXCEPTION 'CBT_NOT_YOUR_SITTING: your sitting is % at %, % to %', v_sit.label, v_sit.venue,
                to_char(v_sit.starts_at AT TIME ZONE 'Africa/Lagos', 'Dy DD Mon YYYY HH24:MI'), to_char(v_sit.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI') USING ERRCODE = '23514';
        END IF;
    END IF;
    -- V374: in a sitting, a candidate the invigilator marked absent does not start; past the office's late-entry limit, one starts once admitted
    IF v_sit.id IS NOT NULL THEN
        SELECT m.* INTO v_mark FROM assessment.cbt_attendance m WHERE m.sitting_id = v_sit.id AND m.candidate_id = p_student;
        IF v_mark.status = 'ABSENT' THEN
            RAISE EXCEPTION 'CBT_MARKED_ABSENT: the invigilator has marked you absent from %', v_sit.label USING ERRCODE = '23514',
                HINT = 'If you are in the examination hall, ask the invigilator to admit you.';
        END IF;
        -- V375: when the office requires it, a candidate starts once an invigilator has checked them in (or admitted them late)
        IF e.require_check_in AND coalesce(v_mark.status, '') NOT IN ('PRESENT', 'LATE') THEN
            RAISE EXCEPTION 'CBT_NOT_CHECKED_IN: the invigilator has not checked you in to %', v_sit.label USING ERRCODE = '23514',
                HINT = 'Show your CBT slip to the invigilator at the door.';
        END IF;
        IF e.late_entry_minutes IS NOT NULL AND v_mark.status IS DISTINCT FROM 'LATE'
           AND NOT coalesce(v_mark.checked_in_at <= v_sit.starts_at + make_interval(mins => e.late_entry_minutes), false)   -- V375: at the door in time
           AND now() > v_sit.starts_at + make_interval(mins => e.late_entry_minutes)
           AND NOT EXISTS (SELECT 1 FROM assessment.cbt_attempt x WHERE x.exam_id = p_exam AND x.candidate_id = p_student) THEN
            RAISE EXCEPTION 'CBT_LATE_ENTRY: entry to % closed % minutes after it began, at %', v_sit.label, e.late_entry_minutes,
                to_char((v_sit.starts_at + make_interval(mins => e.late_entry_minutes)) AT TIME ZONE 'Africa/Lagos', 'HH24:MI') USING ERRCODE = '23514',
                HINT = 'Ask the invigilator to admit you.';
        END IF;
    END IF;
    -- V373: extra time the office granted the candidate, on top of the time every candidate has
    SELECT x.minutes INTO v_extra FROM assessment.cbt_extra_time x WHERE x.exam_id = p_exam AND x.candidate_id = p_student;
    v_extra := coalesce(v_extra, 0);
    -- V374: and the minutes the invigilator gave back to a candidate admitted late
    IF v_mark.status = 'LATE' THEN v_extra := v_extra + v_mark.minutes_given; END IF;
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
    INSERT INTO assessment.cbt_attempt (exam_id, student_id, jupeb_application_id, application_id, number, ends_at, question_ids, question_versions, question_marks, seed, max_marks, ip, user_agent)
    VALUES (p_exam, CASE WHEN e.office IN ('JUPEB', 'POST_UTME') THEN NULL ELSE p_student END, CASE WHEN e.office = 'JUPEB' THEN p_student END,
            CASE WHEN e.office = 'POST_UTME' THEN p_student END, v_n + 1,
            least(now() + make_interval(mins => e.duration_minutes), e.ends_at, coalesce(v_sit.ends_at, 'infinity'::timestamptz)) + make_interval(mins => v_extra),
            v_paper, v_versions, v_marks, v_seed,
            greatest((SELECT sum(m) FROM unnest(v_marks) m), 1), p_ip, p_agent)
    RETURNING * INTO a;
    PERFORM assessment.cbt_log(a.id, 'STARTED', false, format('%s questions, %s marks, ends %s%s%s', cardinality(v_paper), a.max_marks, to_char(a.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI:SS'),
                               CASE WHEN v_sit.id IS NULL THEN '' ELSE format(' · %s, %s', v_sit.label, v_sit.venue) END,
                               CASE WHEN v_extra > 0 THEN format(' · %s minutes extra time', v_extra) ELSE '' END
                               || CASE WHEN v_mark.status = 'LATE' THEN format(' · admitted %s minutes late', v_mark.minutes_late) ELSE '' END), p_ip);
    RETURN a;
END $$;

-- ── 8 · the candidates of an examination, of all three kinds (V367 verbatim, with the third) ─────────────────
CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
              programme_code text, programme text, level integer, student_status text, entitled boolean, eligible boolean, attempts integer, attempt_id uuid,
              attempt_status text, connection text, started_at timestamptz, ends_at timestamptz, submitted_at timestamptz,
              time_left integer, last_activity_at timestamptz, violations integer, answered integer, score numeric, max_marks integer, percentage numeric,
              grade text, passed boolean, outcome text, updated_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT x.*, c.general_office, c.kind FROM assessment.cbt_exam x LEFT JOIN catalogue.course c ON c.code = x.course_code WHERE x.id = p_exam),
    cfg AS (SELECT * FROM finance.gst_setting WHERE id = 1),
    reg AS (SELECT DISTINCT cr.student_id FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE e.office NOT IN ('JUPEB', 'POST_UTME') AND en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    base AS (SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex, s.status, s.current_level AS level, s.entry_mode,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty
               FROM reg JOIN people.student s ON s.id = reg.student_id
               JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code),
    pays AS (SELECT r.student_id, count(*) AS n FROM e, finance.payment_reference r
              WHERE e.office IN ('GST', 'EPS') AND r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.student_id IN (SELECT id FROM base)
                AND r.amount > finance.gst_refunded(r.reference)   -- V367
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
                                  AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND e.general_office IS NOT NULL AND (e.general_office = 'GST' OR cfg.covers_eps))   -- V367
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
    -- V385: a Post-UTME examination's candidates — the session's submitted applicants, eligible on the record (V260) and not yet scored
    preg AS (SELECT a.id, c.jamb_reg_no AS number, upper(c.surname) AS surname, c.other_names, x.sex, el.status,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty,
                    a.fee_confirmed_at IS NOT NULL AS paid,
                    el.status IN ('READY_FOR_SCHEDULING', 'SCHEDULED', 'RESCHEDULED', 'RESCHEDULE_REQUIRED', 'ABSENT') AND a.screening_score IS NULL AS ok
               FROM e JOIN admissions.application a ON a.session = e.putme_session AND a.submitted_at IS NOT NULL
               JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode <> 'CCE'
               LEFT JOIN admissions.caps_row x ON x.id = c.admitted_from
               LEFT JOIN ref.programme p ON p.code = admissions.putme_programme_code(c.programme)
               LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
               CROSS JOIN LATERAL admissions.putme_eligibility(a.id) el
              WHERE e.office = 'POST_UTME'),
    everyone AS (
        SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
               en.entitled, en.paid_up AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION') AS eligible
          FROM base b JOIN ent en ON en.id = b.id
        UNION ALL
        SELECT j.id, j.number, j.surname, j.other_names, j.sex, 'JUPEB', 'JUPEB programme', NULL, NULL, j.combination, j.combination_name, NULL::int, j.state,
               j.paid_up, j.paid_up AND j.state = 'STUDENT'
          FROM jreg j
        UNION ALL
        SELECT q.id, q.number, q.surname, q.other_names, q.sex, q.faculty_code, q.faculty, q.dept_code, q.department, q.programme_code, q.programme, NULL::int, q.status,
               q.paid, q.ok
          FROM preg q)
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

/* V385: how many candidates an examination has — registered students, JUPEB students registered for the subject, or the session's submitted Post-UTME applicants */
CREATE FUNCTION assessment.cbt_candidate_count(e assessment.cbt_exam)
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT CASE e.office
             WHEN 'JUPEB' THEN (SELECT count(DISTINCT r.application_id) FROM jupeb.subject_registration r WHERE r.subject_id = e.jupeb_subject_id AND r.session = e.session)
             WHEN 'POST_UTME' THEN (SELECT count(*) FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                                     WHERE a.session = e.putme_session AND a.submitted_at IS NOT NULL AND c.entry_mode <> 'CCE')
             ELSE (SELECT count(DISTINCT cr.student_id) FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
           END
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_monitor_counts(p_exam uuid)
RETURNS TABLE(candidates bigint, eligible bigint, not_started bigint, in_progress bigint, submitted bigint, time_expired bigint, terminated bigint, disconnected bigint,
              warned bigint, critical bigint, scored bigint, live_state text, now timestamptz)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    reg AS (SELECT assessment.cbt_candidate_count(e) AS n FROM e),
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

CREATE OR REPLACE FUNCTION assessment.cbt_monitor_live_counts(p_exam uuid)
RETURNS TABLE(candidates bigint, eligible bigint, not_started bigint, in_progress bigint, submitted bigint, time_expired bigint, terminated bigint, disconnected bigint,
              warned bigint, critical bigint, scored bigint, live_state text, now timestamptz)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    reg AS (SELECT assessment.cbt_candidate_count(e) AS n FROM e),
    el AS (SELECT NULL::bigint AS n),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.status, a.last_activity_at, a.violations, a.score
              FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
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
    reg AS (SELECT x.id, assessment.cbt_candidate_count(x) AS n FROM assessment.cbt_exam x WHERE x.id IN (SELECT id FROM e))
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
    IF e.office = 'POST_UTME' THEN
        -- V385: the session's submitted Post-UTME applicants, by the e-mail and phone they registered with
        FOR r IN
            SELECT a.id FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
             WHERE a.session = e.putme_session AND a.submitted_at IS NOT NULL AND c.entry_mode <> 'CCE'
               AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.exam_id = p_exam AND t.candidate_id = a.id AND t.status <> 'IN_PROGRESS'))
        LOOP
            PERFORM admissions.notify_applicant(r.id, p_subject, p_body || E'\n\nDirectorate of ICT, ' || (platform.institution() ->> 'name'), NULL);
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

-- ── 9 · the lifecycle: V365 verbatim, with a Post-UTME examination's words and doors ──
CREATE OR REPLACE FUNCTION assessment.cbt_exam_action(p_exam uuid, p_action text, p_reason text)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_act text := lower(btrim(coalesce(p_action, ''))); v_ready text; r record; v_fees text; v_what text; v_where text; v_how text;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    v_fees := CASE WHEN e.office IN ('GST', 'EPS') THEN 'Your GST fee must be paid and the course on your registration'
                   WHEN e.office = 'JUPEB' THEN 'The semester''s share of your JUPEB school fee must be paid and the subject on your registration'
                   WHEN e.office = 'POST_UTME' THEN 'Your Post-UTME application must be submitted with the screening fee confirmed'
                   ELSE 'Your school fees must be cleared for examinations and the course on your registration' END;
    v_what := coalesce(e.course_code, (SELECT s.code FROM jupeb.subject s WHERE s.id = e.jupeb_subject_id), CASE WHEN e.office = 'POST_UTME' THEN 'Post-UTME' END);
    v_where := CASE WHEN e.office = 'JUPEB' THEN 'the JUPEB portal' ELSE 'the portal' END;
    v_how := CASE WHEN e.office = 'POST_UTME'
                  THEN 'Open the Post-UTME CBT page of the portal, enter your JAMB registration number and the verification the page asks for, read the instructions and start within the window. '
                  ELSE 'Sign in to ' || v_where || ', open CBT Examinations, read the instructions and start within the window. ' END;
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
        ELSIF e.office = 'POST_UTME' THEN
            IF NOT EXISTS (SELECT 1 FROM admissions.screening_exam_programme x WHERE x.session = e.putme_session) THEN
                RAISE EXCEPTION 'CBT_PUTME_NO_PROGRAMME: no programme is named as screened by the Post-UTME examination for %', e.putme_session USING ERRCODE = '23514',
                    HINT = 'The admission settings of the session name the programmes screened by examination.';
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
            || ' (' || e.duration_minutes || ' minutes once you start). ' || v_how || v_fees || '.', false);
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
    v_what := coalesce(e.course_code, (SELECT s.code FROM jupeb.subject s WHERE s.id = e.jupeb_subject_id), CASE WHEN e.office = 'POST_UTME' THEN 'Post-UTME' END);
    IF v_act = 'review' THEN
        IF e.results_state NOT IN ('PENDING', 'AUTO_SCORED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are %', lower(replace(e.results_state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'UNDER_REVIEW' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'approve' THEN
        IF e.state <> 'COMPLETED' THEN RAISE EXCEPTION 'CBT_NOT_COMPLETED: complete the examination before its results are approved' USING ERRCODE = '23514'; END IF;
        IF e.results_state NOT IN ('AUTO_SCORED', 'UNDER_REVIEW') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are %', lower(replace(e.results_state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'APPROVED', results_approved_at = now(), results_approved_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
         WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'publish' THEN
        -- V385: a Post-UTME score is never published to candidates through the examination; the Academic Office imports and releases it
        IF e.office = 'POST_UTME' THEN
            RAISE EXCEPTION 'CBT_PUTME_NOT_PUBLISHED_HERE: Post-UTME scores reach candidates through the Academic Office''s release and the result-checking window, not through the examination' USING ERRCODE = '23514',
                HINT = 'Approve the results, export the official score file and send it to the Academic Office.';
        END IF;
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

-- ── 10 · the Post-UTME candidate's own list: the session's examinations, never a score ──
CREATE FUNCTION assessment.cbt_putme_exams(p_app uuid, p_session text)
RETURNS TABLE(exam_id uuid, reference text, office text, course_code text, course_title text, title text, session text, semester integer, instructions text,
              live_state text, starts_at timestamptz, ends_at timestamptz, duration_minutes integer, questions integer, security_mode text,
              venue text, attempt_limit integer, violation_limit integer, violation_action text, eligibility text, attempts integer, attempt_id uuid, attempt_status text,
              attempt_ends_at timestamptz, submitted_at timestamptz, result_published boolean, score numeric, max_marks integer,
              percentage numeric, grade text, passed boolean, pass_mark numeric, outcome text, partial_credit boolean,
              exam_type text, negative_marks numeric, allow_back boolean, allow_review boolean, fullscreen_required boolean, proctoring text, score_on_submit boolean)
LANGUAGE sql STABLE AS $$
    WITH mine AS (SELECT a.session FROM admissions.application a WHERE a.id = p_app AND (p_session IS NULL OR a.session = p_session)),
    att AS (SELECT DISTINCT ON (a.exam_id) a.* FROM assessment.cbt_attempt a WHERE a.application_id = p_app ORDER BY a.exam_id, a.number DESC),
    cnt AS (SELECT a.exam_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.application_id = p_app GROUP BY a.exam_id),
    v AS (SELECT e.*, assessment.cbt_live_state(e) AS live, a.id AS a_id, a.status AS a_status, a.ends_at AS a_ends_at, a.submitted_at AS a_submitted_at, cn.attempts AS a_attempts
            FROM assessment.cbt_exam e JOIN mine m ON m.session = e.putme_session
            LEFT JOIN att a ON a.exam_id = e.id LEFT JOIN cnt cn ON cn.exam_id = e.id
           WHERE e.office = 'POST_UTME' AND e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED'))
    SELECT v.id, v.reference, v.office, 'POST-UTME', 'Post-UTME ' || v.putme_session, v.title, v.session, v.semester, v.instructions,
           v.live, v.starts_at, v.ends_at, v.duration_minutes,
           CASE WHEN v.selection = 'RANDOM' THEN v.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(v.id)) END,
           v.security_mode, v.venue, v.attempt_limit, v.violation_limit, v.violation_action,
           CASE WHEN v.a_status = 'IN_PROGRESS' THEN NULL ELSE assessment.cbt_putme_eligibility(v.id, p_app) END,
           coalesce(v.a_attempts, 0), v.a_id, v.a_status, v.a_ends_at, v.a_submitted_at,
           false, NULL::numeric, NULL::int, NULL::numeric, NULL::text, NULL::boolean, v.pass_mark, NULL::text, v.partial_credit,
           v.exam_type, v.negative_marks, v.allow_back, v.allow_review, v.fullscreen_required, v.proctoring, false
      FROM v
     ORDER BY v.starts_at DESC NULLS LAST, v.title
$$;
COMMENT ON FUNCTION assessment.cbt_putme_exams(uuid, text) IS 'V385: a Post-UTME applicant''s examinations of their session, with their attempt; the score, grade and pass are never on this list.';

-- ── 11 · the door: the JAMB number and the examination's second factor, judged on the record ──
/* the application a JAMB registration number and a second factor name, for the session's Post-UTME CBT — or NULL, with no word on which part failed.
   The factor is the open (or latest published) Post-UTME examination's: the application number, the screening slip's token, the phone registered
   with, or the date of birth on the attachment the Academic Office uploaded (yyyy-mm-dd). */
CREATE FUNCTION admissions.putme_cbt_verify(p_session text, p_jamb text, p_proof text)
RETURNS uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE a record; v_kind text; v_proof text := upper(regexp_replace(coalesce(p_proof, ''), '\s+', '', 'g')); v_ok boolean := false;
BEGIN
    IF v_proof = '' OR coalesce(btrim(p_jamb), '') = '' THEN RETURN NULL; END IF;
    SELECT e.putme_verify INTO v_kind FROM assessment.cbt_exam e
     WHERE e.office = 'POST_UTME' AND e.putme_session = p_session AND e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED')
     ORDER BY (assessment.cbt_live_state(e) = 'OPEN') DESC, e.starts_at DESC NULLS LAST LIMIT 1;
    v_kind := coalesce(v_kind, 'APPLICATION_NO');
    SELECT ap.id, ap.application_no, ap.putme_token, ac.phone, c.id AS candidate_id INTO a
      FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id JOIN admissions.applicant_account ac ON ac.id = ap.account_id
     WHERE ap.session = p_session AND c.jamb_key = upper(btrim(p_jamb)) AND c.entry_mode <> 'CCE';
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_ok := CASE v_kind
              WHEN 'APPLICATION_NO' THEN upper(regexp_replace(coalesce(a.application_no, ''), '\s+', '', 'g')) = v_proof
              WHEN 'SLIP_TOKEN'     THEN upper(coalesce(a.putme_token, '')) = v_proof
              WHEN 'PHONE'          THEN regexp_replace(coalesce(a.phone, ''), '\D', '', 'g') <> '' AND right(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g'), 10) = right(regexp_replace(v_proof, '\D', '', 'g'), 10)
              WHEN 'DATE_OF_BIRTH'  THEN EXISTS (SELECT 1 FROM admissions.attachment x WHERE x.candidate_id = a.candidate_id AND x.kind = 'DATE_OF_BIRTH'
                                                    AND regexp_replace(coalesce(x.payload ->> 'dob', ''), '\D', '', 'g') = regexp_replace(v_proof, '\D', '', 'g')
                                                    AND regexp_replace(v_proof, '\D', '', 'g') <> '')
              ELSE false END;
    RETURN CASE WHEN v_ok THEN a.id END;
END $$;
COMMENT ON FUNCTION admissions.putme_cbt_verify(text, text, text) IS 'V385: the Post-UTME application a JAMB registration number and the examination''s second factor name, or NULL — never which of the two was wrong.';

/* the factor the door asks for, so the page can say which to enter */
CREATE FUNCTION admissions.putme_cbt_factor(p_session text)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT e.putme_verify FROM assessment.cbt_exam e
                      WHERE e.office = 'POST_UTME' AND e.putme_session = p_session AND e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED')
                      ORDER BY (assessment.cbt_live_state(e) = 'OPEN') DESC, e.starts_at DESC NULLS LAST LIMIT 1), 'APPLICATION_NO')
$$;

-- ── 12 · the official score: the engine's, snapshotted, sent, received, imported ──
CREATE TABLE admissions.putme_score_export (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference      text NOT NULL UNIQUE,
    session        text NOT NULL REFERENCES policy.academic_session(name),
    exam_id        uuid NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    exam_title     text NULL,
    state          text NOT NULL DEFAULT 'GENERATED',
    rows_count     int  NOT NULL DEFAULT 0,
    sha256         text NOT NULL,
    message        text NULL,
    generated_by   uuid NULL,
    generated_office text NULL,
    generated_at   timestamptz NOT NULL DEFAULT now(),
    sent_by        uuid NULL,
    sent_at        timestamptz NULL,
    received_by    uuid NULL,
    received_at    timestamptz NULL,
    downloaded_by  uuid NULL,
    downloaded_at  timestamptz NULL,
    imported_by    uuid NULL,
    imported_at    timestamptz NULL,
    rejected_by    uuid NULL,
    rejected_at    timestamptz NULL,
    cancelled_by   uuid NULL,
    cancelled_at   timestamptz NULL,
    closing_note   text NULL,
    CONSTRAINT ck_putme_export_state CHECK (state IN ('GENERATED', 'SENT_TO_ACADEMIC', 'RECEIVED', 'DOWNLOADED', 'IMPORTED', 'REJECTED', 'CANCELLED'))
);
CREATE INDEX ix_putme_export_session ON admissions.putme_score_export (session, generated_at DESC);
SELECT audit.attach('admissions.putme_score_export');
COMMENT ON TABLE admissions.putme_score_export IS 'V385: an official Post-UTME score file — a snapshot of approved CBT scores of a session, with its reference and hash; generated by the Directorate of ICT, sent through the portal to the Academic Office, received, downloaded and imported there (or rejected, or cancelled before import).';

CREATE TABLE admissions.putme_score_export_row (
    export_id       uuid NOT NULL REFERENCES admissions.putme_score_export(id) ON DELETE CASCADE,
    sn              int  NOT NULL,
    application_id  uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    attempt_id      uuid NULL REFERENCES assessment.cbt_attempt(id) ON DELETE SET NULL,
    jamb_reg_no     text NOT NULL,
    application_no  text NULL,
    candidate_name  text NOT NULL,
    faculty         text NULL,
    department      text NULL,
    programme       text NULL,
    exam_title      text NULL,
    questions       int  NULL,
    attempted       int  NULL,
    max_marks       int  NULL,
    score           numeric(8,2) NULL,
    percentage      numeric(5,2) NOT NULL,
    exam_date       timestamptz NULL,
    attempt_status  text NULL,
    outcome         text NULL,
    PRIMARY KEY (export_id, sn),
    UNIQUE (export_id, application_id)
);
SELECT audit.exempt('admissions.putme_score_export_row', 'the rows of an official score file, written once as a snapshot and never changed; the file itself (its reference, hash, every state it passes through and the import of each row) is on the audited export, and a copy of thousands of rows on the chain for each file would say nothing the hash does not');
COMMENT ON TABLE admissions.putme_score_export_row IS 'V385: one candidate''s line of an official Post-UTME score file, as it was generated. The percentage is the score the admission reads (admissions.application.screening_score is out of 100).';

CREATE TABLE admissions.putme_score_import (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    export_id      uuid NOT NULL REFERENCES admissions.putme_score_export(id) ON DELETE CASCADE,
    session        text NOT NULL,
    mode           text NOT NULL CHECK (mode IN ('KEEP', 'REPLACE')),
    reason         text NULL,
    received       int NOT NULL DEFAULT 0,
    applied        int NOT NULL DEFAULT 0,
    unchanged      int NOT NULL DEFAULT 0,
    replaced       int NOT NULL DEFAULT 0,
    kept           int NOT NULL DEFAULT 0,
    released       int NOT NULL DEFAULT 0,
    not_found      int NOT NULL DEFAULT 0,
    imported_by    uuid NULL,
    imported_office text NULL,
    imported_at    timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('admissions.putme_score_import');
COMMENT ON TABLE admissions.putme_score_import IS 'V385: an import of an official Post-UTME score file into the applications'' screening scores — how many were entered, unchanged, replaced (with the reason), kept, left as released, or not found.';

CREATE TABLE admissions.putme_score_history (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    import_id      uuid NULL REFERENCES admissions.putme_score_import(id) ON DELETE SET NULL,
    export_id      uuid NULL REFERENCES admissions.putme_score_export(id) ON DELETE SET NULL,
    previous_score numeric(5,2) NULL,
    new_score      numeric(5,2) NOT NULL,
    action         text NOT NULL CHECK (action IN ('ENTERED', 'REPLACED')),
    reason         text NULL,
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_putme_score_history_app ON admissions.putme_score_history (application_id, changed_at);
SELECT audit.attach('admissions.putme_score_history');
COMMENT ON TABLE admissions.putme_score_history IS 'V385: every Post-UTME score an import entered or replaced on an application, with the previous value, the file it came from, the reason and the officer; nothing is deleted.';

/* each submitted applicant of a session with their best Post-UTME CBT result — the engine's own, official once the examination's results are approved */
CREATE FUNCTION admissions.putme_cbt_scores(p_session text, p_exam uuid)
RETURNS TABLE(application_id uuid, jamb_reg_no text, application_no text, surname text, other_names text, faculty text, department text, programme text, programme_code text,
              exam_id uuid, exam_title text, exam_reference text, results_state text, official boolean, attempt_id uuid, attempt_status text, outcome text,
              questions int, attempted int, max_marks int, score numeric, percentage numeric, violations int, submitted_at timestamptz,
              existing_score numeric, score_released_at timestamptz, exported_in text)
LANGUAGE sql STABLE AS $$
    WITH best AS (
        SELECT DISTINCT ON (a.application_id) a.*, e.title AS exam_title, e.reference AS exam_reference, e.results_state
          FROM assessment.cbt_attempt a JOIN assessment.cbt_exam e ON e.id = a.exam_id
         WHERE e.office = 'POST_UTME' AND e.putme_session = p_session AND (p_exam IS NULL OR e.id = p_exam)
           AND a.application_id IS NOT NULL AND a.status <> 'IN_PROGRESS' AND a.percentage IS NOT NULL
         ORDER BY a.application_id, (a.outcome = 'SCORED') DESC, a.percentage DESC, a.number DESC)
    SELECT ap.id, c.jamb_reg_no, ap.application_no, upper(c.surname), c.other_names, f.name, d.name, p.name, p.code,
           b.exam_id, b.exam_title, b.exam_reference, b.results_state, b.results_state IN ('APPROVED', 'PUBLISHED'),
           b.id, b.status, b.outcome, cardinality(b.question_ids), b.answered, b.max_marks, b.score,
           CASE WHEN b.outcome = 'VOID' THEN 0 ELSE b.percentage END, b.violations, b.submitted_at,
           ap.screening_score, ap.score_released_at,
           (SELECT x.reference FROM admissions.putme_score_export x JOIN admissions.putme_score_export_row r ON r.export_id = x.id
             WHERE r.application_id = ap.id AND x.state NOT IN ('CANCELLED', 'REJECTED') ORDER BY x.generated_at DESC LIMIT 1)
      FROM best b
      JOIN admissions.application ap ON ap.id = b.application_id
      JOIN admissions.candidate c ON c.id = ap.candidate_id
      LEFT JOIN ref.programme p ON p.code = admissions.putme_programme_code(c.programme)
      LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
$$;
COMMENT ON FUNCTION admissions.putme_cbt_scores(text, uuid) IS 'V385: each applicant''s best finished Post-UTME CBT attempt of a session (or of one examination), with whether the examination''s results are approved (official), what the application already holds, and the file it was last exported in.';

/* the official file: the approved scores of a session (or one examination) snapshotted with their hash, one reference each */
CREATE FUNCTION admissions.putme_export_scores(p_session text, p_exam uuid, p_actor uuid, p_office text)
RETURNS admissions.putme_score_export
LANGUAGE plpgsql AS $$
DECLARE x admissions.putme_score_export; v_ref text; v_n int; v_unapproved int; v_title text; v_hash text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'CBT_SESSION: % is not a session on the University calendar', p_session USING ERRCODE = '23514'; END IF;
    IF p_exam IS NOT NULL THEN
        SELECT e.title INTO v_title FROM assessment.cbt_exam e WHERE e.id = p_exam AND e.office = 'POST_UTME' AND e.putme_session = p_session;
        IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such Post-UTME examination of %', p_session USING ERRCODE = '23503'; END IF;
    END IF;
    SELECT count(*) INTO v_unapproved FROM assessment.cbt_exam e
     WHERE e.office = 'POST_UTME' AND e.putme_session = p_session AND (p_exam IS NULL OR e.id = p_exam)
       AND e.results_state NOT IN ('APPROVED', 'PUBLISHED') AND EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status <> 'IN_PROGRESS');
    IF v_unapproved > 0 THEN
        RAISE EXCEPTION 'PUTME_EXPORT_UNAPPROVED: % examination% of % still ha% results not approved; review and approve them, or export one examination', v_unapproved,
            CASE WHEN v_unapproved = 1 THEN '' ELSE 's' END, p_session, CASE WHEN v_unapproved = 1 THEN 's' ELSE 've' END USING ERRCODE = '23514';
    END IF;
    v_ref := 'PUTME-SCORE-' || left(p_session, 4) || '-' || lpad(platform.next_number('putme_score_export', 'UNIVERSITY', p_session)::text, 5, '0');
    INSERT INTO admissions.putme_score_export (reference, session, exam_id, exam_title, sha256, generated_by, generated_office)
    VALUES (v_ref, p_session, p_exam, v_title, 'pending', p_actor, p_office) RETURNING * INTO x;
    INSERT INTO admissions.putme_score_export_row (export_id, sn, application_id, attempt_id, jamb_reg_no, application_no, candidate_name, faculty, department, programme,
                                                   exam_title, questions, attempted, max_marks, score, percentage, exam_date, attempt_status, outcome)
    SELECT x.id, row_number() OVER (ORDER BY s.jamb_reg_no), s.application_id, s.attempt_id, s.jamb_reg_no, s.application_no, s.surname || ', ' || s.other_names,
           s.faculty, s.department, s.programme, s.exam_title, s.questions, s.attempted, s.max_marks, s.score, s.percentage, s.submitted_at, s.attempt_status, s.outcome
      FROM admissions.putme_cbt_scores(p_session, p_exam) s WHERE s.official;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN
        DELETE FROM admissions.putme_score_export WHERE id = x.id;
        RAISE EXCEPTION 'PUTME_EXPORT_EMPTY: no approved Post-UTME CBT score of % to export', p_session USING ERRCODE = '23514';
    END IF;
    SELECT encode(digest(string_agg(r.jamb_reg_no || '|' || coalesce(r.application_no, '') || '|' || r.percentage::text, E'\n' ORDER BY r.sn), 'sha256'), 'hex')
      INTO v_hash FROM admissions.putme_score_export_row r WHERE r.export_id = x.id;
    UPDATE admissions.putme_score_export SET rows_count = v_n, sha256 = v_hash WHERE id = x.id RETURNING * INTO x;
    RETURN x;
END $$;
COMMENT ON FUNCTION admissions.putme_export_scores(text, uuid, uuid, text) IS 'V385: the official Post-UTME score file of a session (or one examination): every approved best attempt snapshotted in JAMB-number order with the file''s hash and reference. Refused while an examination with attempts has results not approved.';

/* sent to the Academic Office through the portal: its officers are told; the file is theirs to receive, download and import */
CREATE FUNCTION admissions.putme_send_export(p_export uuid, p_message text, p_actor uuid)
RETURNS admissions.putme_score_export
LANGUAGE plpgsql AS $$
DECLARE x admissions.putme_score_export; r record; n int := 0;
BEGIN
    SELECT * INTO x FROM admissions.putme_score_export WHERE id = p_export FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PUTME_EXPORT_NOT_FOUND: no such score file' USING ERRCODE = '23503'; END IF;
    IF x.state <> 'GENERATED' THEN RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is %', x.reference, lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    UPDATE admissions.putme_score_export SET state = 'SENT_TO_ACADEMIC', sent_by = p_actor, sent_at = now(), message = nullif(btrim(coalesce(p_message, '')), '')
     WHERE id = x.id RETURNING * INTO x;
    FOR r IN
        SELECT DISTINCT p.id, p.email FROM iam.office_assignment oa JOIN iam.person p ON p.id = oa.person_id
         WHERE oa.office_code = 'academic' AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date) AND p.ended_on IS NULL
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, 'Post-UTME scores ' || x.reference || ' sent to the Academic Office',
            'The Directorate of ICT has sent the official Post-UTME score file ' || x.reference || ' for ' || x.session || ' (' || x.rows_count || ' candidates'
            || coalesce(', ' || x.exam_title, '') || ') to the Academic Office. Open Post-UTME scores on the portal to receive, download and import it.'
            || coalesce(E'\n\nMessage: ' || x.message, ''), 'putme_score_export', x.id);
        n := n + 1;
    END LOOP;
    RETURN x;
END $$;

/* the Academic Office's acts on a file it was sent: received, downloaded, rejected with a reason */
CREATE FUNCTION admissions.putme_export_act(p_export uuid, p_action text, p_note text, p_actor uuid)
RETURNS admissions.putme_score_export
LANGUAGE plpgsql AS $$
DECLARE x admissions.putme_score_export; v_act text := upper(btrim(coalesce(p_action, '')));
BEGIN
    SELECT * INTO x FROM admissions.putme_score_export WHERE id = p_export FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PUTME_EXPORT_NOT_FOUND: no such score file' USING ERRCODE = '23503'; END IF;
    IF v_act = 'RECEIVE' THEN
        IF x.state <> 'SENT_TO_ACADEMIC' THEN RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is %', x.reference, lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE admissions.putme_score_export SET state = 'RECEIVED', received_by = p_actor, received_at = now() WHERE id = x.id RETURNING * INTO x;
    ELSIF v_act = 'DOWNLOAD' THEN
        IF x.state NOT IN ('SENT_TO_ACADEMIC', 'RECEIVED', 'DOWNLOADED', 'IMPORTED') THEN RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is %', x.reference, lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE admissions.putme_score_export
           SET state = CASE WHEN state IN ('SENT_TO_ACADEMIC', 'RECEIVED') THEN 'DOWNLOADED' ELSE state END,
               received_by = coalesce(received_by, p_actor), received_at = coalesce(received_at, now()), downloaded_by = p_actor, downloaded_at = now()
         WHERE id = x.id RETURNING * INTO x;
    ELSIF v_act = 'REJECT' THEN
        IF x.state NOT IN ('SENT_TO_ACADEMIC', 'RECEIVED', 'DOWNLOADED') THEN RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is %', x.reference, lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        IF coalesce(btrim(p_note), '') = '' THEN RAISE EXCEPTION 'PUTME_EXPORT_REASON: rejecting a score file names the reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.putme_score_export SET state = 'REJECTED', rejected_by = p_actor, rejected_at = now(), closing_note = btrim(p_note) WHERE id = x.id RETURNING * INTO x;
    ELSIF v_act = 'CANCEL' THEN
        IF x.state = 'IMPORTED' THEN RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is imported; its scores are on the record', x.reference USING ERRCODE = '23514'; END IF;
        IF x.state IN ('CANCELLED', 'REJECTED') THEN RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is %', x.reference, lower(x.state) USING ERRCODE = '23514'; END IF;
        IF coalesce(btrim(p_note), '') = '' THEN RAISE EXCEPTION 'PUTME_EXPORT_REASON: cancelling a score file names the reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.putme_score_export SET state = 'CANCELLED', cancelled_by = p_actor, cancelled_at = now(), closing_note = btrim(p_note) WHERE id = x.id RETURNING * INTO x;
    ELSE
        RAISE EXCEPTION 'PUTME_EXPORT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN x;
END $$;

/* what an import of a file would do to each line: entered new, the same again, a different score already held, released (never touched), or the applicant gone */
CREATE FUNCTION admissions.putme_import_preview(p_export uuid)
RETURNS TABLE(sn int, application_id uuid, jamb_reg_no text, application_no text, candidate_name text, programme text, percentage numeric,
              existing_score numeric, score_released_at timestamptz, outcome text)
LANGUAGE sql STABLE AS $$
    SELECT r.sn, r.application_id, r.jamb_reg_no, r.application_no, r.candidate_name, r.programme, r.percentage,
           a.screening_score, a.score_released_at,
           CASE WHEN a.id IS NULL OR c.offer_state IN ('WITHDRAWN', 'DECLINED', 'LAPSED') THEN 'NOT_FOUND'
                WHEN r.percentage < 0 OR r.percentage > 100 THEN 'OUT_OF_RANGE'
                WHEN a.score_released_at IS NOT NULL THEN 'RELEASED'
                WHEN a.screening_score IS NULL THEN 'NEW'
                WHEN a.screening_score = r.percentage THEN 'SAME'
                ELSE 'DIFFERENT' END
      FROM admissions.putme_score_export_row r
      LEFT JOIN admissions.application a ON a.id = r.application_id
      LEFT JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE r.export_id = p_export
     ORDER BY r.sn
$$;

/* the import: each line in its own right — a new score entered, the same left alone, a different one kept or (with the reason) replaced with the old value on the history,
   a released score never touched; the file is then IMPORTED and the import recorded. Idempotent: a file imported again enters nothing twice. */
CREATE FUNCTION admissions.putme_import_scores(p_export uuid, p_mode text, p_reason text, p_actor uuid, p_office text)
RETURNS admissions.putme_score_import
LANGUAGE plpgsql AS $$
DECLARE x admissions.putme_score_export; v_mode text := upper(btrim(coalesce(p_mode, 'KEEP'))); imp admissions.putme_score_import; r record;
        n_applied int := 0; n_same int := 0; n_replaced int := 0; n_kept int := 0; n_released int := 0; n_missing int := 0; n_total int := 0;
BEGIN
    SELECT * INTO x FROM admissions.putme_score_export WHERE id = p_export FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PUTME_EXPORT_NOT_FOUND: no such score file' USING ERRCODE = '23503'; END IF;
    IF x.state NOT IN ('SENT_TO_ACADEMIC', 'RECEIVED', 'DOWNLOADED', 'IMPORTED') THEN
        RAISE EXCEPTION 'PUTME_EXPORT_STATE: the file % is %; only a file sent to the Academic Office is imported', x.reference, lower(replace(x.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF v_mode NOT IN ('KEEP', 'REPLACE') THEN RAISE EXCEPTION 'PUTME_IMPORT_MODE: an existing score is KEPT or REPLACED' USING ERRCODE = '23514'; END IF;
    IF v_mode = 'REPLACE' AND coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'PUTME_IMPORT_REASON: replacing scores already on the record names the reason' USING ERRCODE = '23514'; END IF;
    INSERT INTO admissions.putme_score_import (export_id, session, mode, reason, imported_by, imported_office)
    VALUES (x.id, x.session, v_mode, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office) RETURNING * INTO imp;
    FOR r IN SELECT * FROM admissions.putme_import_preview(p_export) LOOP
        n_total := n_total + 1;
        IF r.outcome = 'NEW' THEN
            UPDATE admissions.application SET screening_score = r.percentage, score_entered_at = now() WHERE id = r.application_id AND score_released_at IS NULL;
            INSERT INTO admissions.putme_score_history (application_id, import_id, export_id, previous_score, new_score, action, changed_by, changed_office)
            VALUES (r.application_id, imp.id, x.id, NULL, r.percentage, 'ENTERED', p_actor, p_office);
            n_applied := n_applied + 1;
        ELSIF r.outcome = 'SAME' THEN n_same := n_same + 1;
        ELSIF r.outcome = 'DIFFERENT' THEN
            IF v_mode = 'REPLACE' THEN
                INSERT INTO admissions.putme_score_history (application_id, import_id, export_id, previous_score, new_score, action, reason, changed_by, changed_office)
                VALUES (r.application_id, imp.id, x.id, r.existing_score, r.percentage, 'REPLACED', btrim(p_reason), p_actor, p_office);
                UPDATE admissions.application SET screening_score = r.percentage, score_entered_at = now() WHERE id = r.application_id AND score_released_at IS NULL;
                n_replaced := n_replaced + 1;
            ELSE n_kept := n_kept + 1;
            END IF;
        ELSIF r.outcome = 'RELEASED' THEN n_released := n_released + 1;
        ELSE n_missing := n_missing + 1;
        END IF;
    END LOOP;
    UPDATE admissions.putme_score_import SET received = n_total, applied = n_applied, unchanged = n_same, replaced = n_replaced, kept = n_kept, released = n_released, not_found = n_missing
     WHERE id = imp.id RETURNING * INTO imp;
    UPDATE admissions.putme_score_export SET state = 'IMPORTED', imported_by = p_actor, imported_at = now(),
           received_by = coalesce(received_by, p_actor), received_at = coalesce(received_at, now())
     WHERE id = x.id;
    RETURN imp;
END $$;
COMMENT ON FUNCTION admissions.putme_import_scores(uuid, text, text, uuid, text) IS 'V385: the Academic Office''s import of an official Post-UTME score file into admissions.application.screening_score: new scores entered, a released score never touched, a different score kept or replaced only with a reason (the previous value on putme_score_history). Idempotent.';

-- ── 13 · the candidate's reading of a released score, on the Director's result-checking window ──
CREATE FUNCTION admissions.putme_result_check(p_session text, p_jamb text, p_proof text)
RETURNS TABLE(outcome text, candidate_name text, jamb_reg_no text, application_no text, programme text, score numeric, released_at timestamptz)
LANGUAGE plpgsql STABLE AS $$
DECLARE w record; v_app uuid; a admissions.application; c admissions.candidate;
BEGIN
    SELECT * INTO w FROM policy.window_state('POST_UTME_RESULT_CHECKING', p_session, NULL);
    IF w.state <> 'OPEN' THEN RETURN QUERY SELECT 'CLOSED'::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::numeric, NULL::timestamptz; RETURN; END IF;
    v_app := admissions.putme_cbt_verify(p_session, p_jamb, p_proof);
    IF v_app IS NULL THEN RETURN QUERY SELECT 'NOT_VERIFIED'::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::numeric, NULL::timestamptz; RETURN; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = v_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    IF a.score_released_at IS NULL OR a.screening_score IS NULL THEN
        RETURN QUERY SELECT 'NOT_RELEASED'::text, upper(c.surname) || ', ' || c.other_names, c.jamb_reg_no, a.application_no, c.programme, NULL::numeric, NULL::timestamptz; RETURN;
    END IF;
    RETURN QUERY SELECT 'RELEASED'::text, upper(c.surname) || ', ' || c.other_names, c.jamb_reg_no, a.application_no, c.programme, a.screening_score, a.score_released_at;
END $$;
COMMENT ON FUNCTION admissions.putme_result_check(text, text, text) IS 'V385: what a candidate reads on the result-checking page: CLOSED while the Director''s window is not open, NOT_VERIFIED when the JAMB number and the second factor do not name an applicant, NOT_RELEASED until the Academic Office releases the scores, else the released score.';

-- ── 14 · rights ───────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON admissions.putme_score_export, admissions.putme_score_export_row, admissions.putme_score_import, admissions.putme_score_history TO app_admissions;
GRANT SELECT ON admissions.putme_score_export, admissions.putme_score_export_row, admissions.putme_score_import, admissions.putme_score_history TO app_auditor;

COMMIT;
