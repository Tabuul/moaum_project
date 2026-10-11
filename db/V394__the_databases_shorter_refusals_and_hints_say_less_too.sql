-- ═══════════════════════════════════════
-- V394 — the database's shorter refusals and hints say less too
--
--   V392 shortened the long texts; this is the review of the rest. Of about
--   770 refusals and hints in the live functions, most already state only what
--   is needed and stay as they are. 42 texts in 36 functions lose a clause that
--   explained the system ("the request reaches the next desk on its own",
--   "examinations already sat keep their record either way", an internal
--   reference to D-Q4 and its memorandum), including seven hints written as
--   literals continued over several lines. Each function is restated from its
--   definition as V393 left it, and only those literals differ: every error
--   code, ERRCODE, condition, signature and grant stands.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V394: the database''s shorter refusals and hints reviewed', true);

CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text, p_basis text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; v_has boolean; v_missing text[];
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'the decision was released on % and stands', a.decision_released_at::date USING ERRCODE = '23514',
            HINT = 'The Board minutes a new decision.';
    END IF;
    IF a.score_released_at IS NULL THEN
        RAISE EXCEPTION 'the screening score has not been released' USING ERRCODE = '23514', HINT = 'The Board decides on released scores.';
    END IF;
    IF p_decision = 'OFFERED' AND p_basis IS NULL THEN
        RAISE EXCEPTION 'an offer is made on a basis' USING ERRCODE = '23514',
            HINT = 'National Merit, State Merit, Equality of Local Government, Locality or Persons Living With Disability.';
    END IF;
    IF p_decision = 'OFFERED' THEN
        SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
        -- the rule applies to the O'Level on record: when a candidate has sittings but no
        -- credit in a compulsory subject, the offer is refused; when none is on record, the
        -- rule cannot be read and does not block (that is a data-completeness matter).
        SELECT EXISTS (SELECT 1 FROM admissions.olevel_sitting st
                        WHERE st.session = a.session AND st.jamb_key = c.jamb_key) INTO v_has;
        IF v_has THEN
            v_missing := admissions.olevel_compulsory_missing(a.session, c.jamb_key, c.programme);
            IF array_length(v_missing, 1) IS NOT NULL THEN
                RAISE EXCEPTION 'a compulsory O''Level credit is missing: %', array_to_string(v_missing, ', ')
                    USING ERRCODE = '23514',
                    HINT = 'Credit passes in English and Mathematics are compulsory for all programmes; a pass does not count. '
                           'If this programme admits on a pass in a subject, record that exception in the admission settings.';
            END IF;
        END IF;
    END IF;
    UPDATE admissions.application SET decision = p_decision, decision_note = p_note, decision_basis = p_basis, decided_at = now() WHERE id = p_app;
    RETURN p_decision;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.recommend_admission_correction(p_app uuid, p_to text, p_reason text, p_note text, p_actor uuid, p_office text, p_override boolean, p_override_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; rs admissions.programme_change_reason; f admissions.screening_form; r record; rt record;
        v_run uuid; v_id uuid; v_from text; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_to text := upper(btrim(coalesce(p_to, ''))); o text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF coalesce(p_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'CORRECTION_RECOMMENDER: an admission correction is recommended by the Academic Office or the Registrar''s office' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rt FROM admissions.programme_change_route(p_app);
    IF rt.route = 'CHANGE' THEN
        RAISE EXCEPTION 'CORRECTION_NOT_NEEDED: %', rt.detail USING ERRCODE = '23514',
              HINT = 'Use Request Change on Programme Eligibility, or the change of programme on the screening desk.';
    ELSIF rt.route = 'TRANSFER' THEN
        RAISE EXCEPTION 'CORRECTION_TRANSFER: %', rt.detail USING ERRCODE = '23514', HINT = 'The student applies through Inter-Departmental Transfer.';
    ELSIF rt.route IS DISTINCT FROM 'CORRECTION' THEN
        RAISE EXCEPTION 'CORRECTION_NO_ADMISSION: %', coalesce(rt.detail, 'there is no admission to correct') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rs FROM admissions.programme_change_reason WHERE code = upper(btrim(coalesce(p_reason, ''))) AND active;
    IF rs.code IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON: an admission correction carries one of the configured reasons' USING ERRCODE = '23514'; END IF;
    IF v_note IS NULL THEN
        RAISE EXCEPTION 'CORRECTION_NOTE_REQUIRED: describe the error found in the admission and how it was found' USING ERRCODE = '23514',
              HINT = 'The Registrar decides on this note.';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = v_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', v_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = v_to THEN RAISE EXCEPTION 'that is the programme the candidate holds' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already recommended and awaits approval' USING ERRCODE = '23514';
    END IF;
    -- the engine, read again now against the session's settings
    v_run := admissions.eligibility_current(p_app, p_actor);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, v_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        IF NOT coalesce(p_override, false) THEN
            RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
                  HINT = 'Only a programme the engine finds the candidate eligible for is recommended; an override is reserved to the Registrar.';
        END IF;
        IF nullif(btrim(coalesce(p_override_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an eligibility override carries its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request,
                                                     requested_by_kind, requested_by, note, reason_code, recommended_office, override, override_reason, original_eligibility,
                                                     screening_state_at_request, kind, admission_stage)
    VALUES (p_app, c.id, a.session, v_from, c.programme, v_to, g.name, v_run, r.result, 'OFFICE', p_actor, v_note, rs.code, p_office,
            r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING'), nullif(btrim(coalesce(p_override_reason, '')), ''), r.result, f.state, 'CORRECTION', rt.stage)
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'ADMISSION_CORRECTION_RECOMMENDED', v_to, r.result,
        'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · ' || v_note || ' · by the ' || p_office || ' · admission ' || lower(replace(rt.stage, '_', ' '))
        || CASE WHEN r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN ' · OVERRIDE: ' || coalesce(p_override_reason, '') ELSE '' END);
    IF f.application_id IS NOT NULL THEN
        PERFORM admissions.screening_log(p_app, 'ADMISSION_CORRECTION_RECOMMENDED', 'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · awaiting the Registrar''s approval');
    END IF;
    -- the applicant is told when it is decided, not while it may yet be refused; the Registrar's office is told now
    FOREACH o IN ARRAY ARRAY['registrar', 'dregistrar'] LOOP
        PERFORM admissions.tell_office(o, 'An admission correction awaits approval',
            'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ', ' || a.application_no || '): the ' || p_office
            || ' recommends correcting the admission from ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · ' || v_note
            || ' · the admission stands at: ' || lower(replace(rt.stage, '_', ' ')) || ' · the engine finds the candidate ' || lower(replace(r.result, '_', ' '))
            || CASE WHEN coalesce(p_override, false) THEN ' (override)' ELSE '' END || '. Decide it on Programme Changes.', p_app);
    END LOOP;
    RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.screening_refuse_student(p_student uuid, p_what text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('moaum.screening_override', true) = 'on' THEN RETURN; END IF;
    IF NOT admissions.screening_ok_student(p_student) THEN
        RAISE EXCEPTION '% UNAVAILABLE: the University''s screening must be successful first (or a change of programme approved)', p_what
            USING ERRCODE = '23514', HINT = 'Wait for the screening officers'' decision.';
    END IF;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.screening_submit(p_app uuid, p_declaration boolean, p_ip text)
 RETURNS admissions.screening_form
 LANGUAGE plpgsql
AS $function$
DECLARE f admissions.screening_form; c admissions.candidate; a admissions.application;
BEGIN
    f := admissions.screening_open(p_app);
    IF f.state <> 'CORRECTION_REQUIRED' THEN
        RAISE EXCEPTION 'SCREENING NOT FILLED: nothing is submitted by the applicant' USING ERRCODE = '23514',
              HINT = 'Wait for the outcome of the screening; you are told here and by email.';
    END IF;
    UPDATE admissions.screening_form SET state = 'PENDING', version = version + 1, submitted_at = now(), submitted_ip = p_ip, declaration_at = now(), updated_at = now()
     WHERE application_id = p_app RETURNING * INTO f;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    PERFORM admissions.screening_log(p_app, 'CORRECTED', 'Correction provided (version ' || f.version || ') from ' || coalesce(p_ip, '?') || ': ' || coalesce(f.returned_note, ''));
    PERFORM admissions.notify_applicant(p_app, 'Your correction has been received',
        'The correction you provided on screening ' || f.screening_no || ' was received on ' || to_char(now(), 'DD Mon YYYY HH24:MI') || '. Your admission is back with the screening officers; you will be told the outcome here and by email.',
        'MOAUM: correction received on screening ' || f.screening_no || '. You will be told the outcome.');
    PERFORM admissions.tell_office('academic', 'A correction awaits the screening officers', c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ') provided the correction asked for on screening ' || f.screening_no || ' for ' || c.programme || '.', p_app);
    RETURN f;
END $function$
;

CREATE OR REPLACE FUNCTION assessment.advance(p_sheet uuid, p_comment text, p_minute text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_stage text; v_next text; v_actor uuid; v_office text; v_last uuid; v_missing int;
BEGIN
    v_actor  := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = p_sheet FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    v_next := assessment.stage_after(v_stage);
    IF v_next IS NULL THEN
        RAISE EXCEPTION 'this sheet is published; there is no stage after publication'
            USING ERRCODE = 'check_violation';
    END IF;
    PERFORM assessment.require_stage_desk(v_stage, v_office, CASE WHEN v_stage = 'ENTRY' THEN 'submitted' ELSE 'approved' END);
    IF v_stage = 'ENTRY' THEN
        -- a sheet leaves the lecturer only when every candidate on its roster has an outcome (I-RES-4)
        SELECT count(*) INTO v_missing
          FROM assessment.sheet_candidates(p_sheet) c
         WHERE NOT EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = p_sheet AND sc.student_id = c.student_id);
        IF v_missing > 0 THEN
            RAISE EXCEPTION '% registered candidate(s) on this sheet have no mark and no outcome', v_missing
                USING ERRCODE = 'check_violation',
                      HINT = 'Every candidate on the register is graded, absent, withheld, incomplete, malpractice or exempted. A blank is not an outcome.';
        END IF;
    END IF;
    SELECT d.actor_id INTO v_last FROM assessment.decision d
     WHERE d.sheet_id = p_sheet AND d.kind IN ('SUBMIT','ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you approved the previous stage of this sheet; another desk must approve this one'
            USING ERRCODE = 'check_violation',
                  HINT = 'BR-006. One person does not approve two consecutive stages, even holding both offices.';
    END IF;
    IF v_next = 'PUBLISHED' AND (p_minute IS NULL OR btrim(p_minute) = '') THEN
        RAISE EXCEPTION 'a result reaches a student on the Senate minute that approved it, and none was cited'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.decision (id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (gen_random_uuid(), p_sheet, v_stage, v_next,
            CASE WHEN v_stage = 'ENTRY' THEN 'SUBMIT' ELSE 'ADVANCE' END, v_actor, v_office, p_comment);
    UPDATE assessment.score_sheet
       SET stage = v_next,
           submitted_at = CASE WHEN v_stage = 'ENTRY' THEN now() ELSE submitted_at END,
           senate_minute = CASE WHEN v_next = 'PUBLISHED' THEN p_minute ELSE senate_minute END,
           published_at  = CASE WHEN v_next = 'PUBLISHED' THEN now() ELSE published_at END,
           engine_version = CASE WHEN v_next = 'PUBLISHED' THEN 'GpaCalculator 2.1' ELSE engine_version END
     WHERE id = p_sheet;
    IF v_next = 'PUBLISHED' THEN
        PERFORM assessment.tell_published(p_sheet);
    END IF;
    RETURN v_next;
END;
$function$
;

CREATE OR REPLACE FUNCTION assessment.cbt_configure(p_exam uuid, p jsonb)
 RETURNS assessment.cbt_exam
 LANGUAGE plpgsql
AS $function$
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
        RAISE EXCEPTION 'CBT_SETTING: a JUPEB CBT result goes into the JUPEB continuous assessment, or nowhere' USING ERRCODE = '23514';
    END IF;
    -- V385: a Post-UTME score goes to no sheet and is never shown on submission; the Academic Office imports it
    IF e.office = 'POST_UTME' AND p ? 'sheetComponent' AND upper(p->>'sheetComponent') <> 'NONE' THEN
        RAISE EXCEPTION 'CBT_SETTING: a Post-UTME score goes to no score sheet; the Academic Office imports the exported scores' USING ERRCODE = '23514';
    END IF;
    IF e.office = 'POST_UTME' AND p ? 'scoreOnSubmit' AND (p->>'scoreOnSubmit')::boolean THEN
        RAISE EXCEPTION 'CBT_PUTME_NO_SCORE_ON_SUBMIT: a Post-UTME candidate is never shown a score on submission' USING ERRCODE = '23514';
    END IF;
    IF p ? 'putmeVerify' THEN
        IF e.office <> 'POST_UTME' THEN RAISE EXCEPTION 'CBT_SETTING: what the door asks for is a Post-UTME examination''s setting' USING ERRCODE = '23514'; END IF;
        IF upper(p->>'putmeVerify') NOT IN ('NONE', 'APPLICATION_NO', 'SLIP_TOKEN', 'PHONE', 'DATE_OF_BIRTH') THEN
            RAISE EXCEPTION 'CBT_SETTING: the door asks for the JAMB registration number alone (NONE), or with the application number, the slip token, the registered phone or the date of birth' USING ERRCODE = '23514';
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
END $function$
;

CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
 RETURNS assessment.cbt_attempt
 LANGUAGE plpgsql
AS $function$
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
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514', HINT = 'Eligibility reads your registration, your payments and the examination window.';
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
END $function$
;

CREATE OR REPLACE FUNCTION assessment.chase_sheet(p_sheet uuid, p_kind text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    s record; cov record; r record; lr record;
    v_late int; v_to text; v_to_label text; v_last timestamptz; v_sem text; v_what text; v_note text := nullif(btrim(p_note), '');
    v_told int := 0; v_names text[] := ARRAY[]::text[]; v_holders int := 0; v_body text; v_sms text; v_id uuid;
BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('REMIND', 'ESCALATE') THEN
        RAISE EXCEPTION 'RESULT_CHASE_KIND: a late score sheet is reminded or escalated' USING ERRCODE = 'check_violation';
    END IF;
    IF v_actor IS NULL OR v_office IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_ACTOR: a reminder is sent by a desk, signed in' USING ERRCODE = 'check_violation';
    END IF;
    IF v_office = 'lecturer' THEN
        RAISE EXCEPTION 'RESULT_CHASE_DESK: a lecturer is reminded by the desks and does not chase a sheet' USING ERRCODE = 'check_violation';
    END IF;
    IF v_note IS NOT NULL AND length(v_note) > 500 THEN
        RAISE EXCEPTION 'RESULT_CHASE_NOTE: a note to the reminder is at most five hundred characters' USING ERRCODE = 'check_violation';
    END IF;
    SELECT sh.id, sh.stage, sh.due_on, o.course_code, coalesce(o.title, cr.title) AS title, o.session, o.semester, o.lecturer_id,
           cr.dept_code, d.name AS dept_name, d.faculty_code, f.name AS faculty_name, cr.general_office
      INTO s
      FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id JOIN catalogue.course cr ON cr.code = o.course_code
      LEFT JOIN ref.department d ON d.code = cr.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
     WHERE sh.id = p_sheet
       FOR UPDATE OF sh;
    IF s.id IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_SHEET: no such score sheet' USING ERRCODE = 'check_violation';
    END IF;
    IF s.stage <> 'ENTRY' THEN
        RAISE EXCEPTION 'RESULT_CHASE_NOT_AT_ENTRY: % is at % — only a sheet still waiting for its marks is chased', s.course_code, lower(replace(s.stage, '_', ' '))
            USING ERRCODE = 'check_violation';
    END IF;
    IF s.lecturer_id IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_NO_LECTURER: no lecturer is allocated to % in %; allocate one', s.course_code, s.session
            USING ERRCODE = 'check_violation';
    END IF;
    v_late := CASE WHEN s.due_on IS NOT NULL AND s.due_on < current_date THEN current_date - s.due_on END;
    IF p_kind = 'ESCALATE' AND v_late IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_NOT_LATE: % is not past its due date (%) — remind the lecturer',
            s.course_code, coalesce(to_char(s.due_on, 'DD Mon YYYY'), 'none set') USING ERRCODE = 'check_violation';
    END IF;
    SELECT max(c.sent_at) INTO v_last FROM assessment.sheet_chase c WHERE c.sheet_id = p_sheet AND c.kind = p_kind AND c.sent_at > now() - interval '1 day';
    IF v_last IS NOT NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_TOO_SOON: % was % at % today or yesterday; a sheet is % at most once a day',
            s.course_code, CASE p_kind WHEN 'REMIND' THEN 'reminded' ELSE 'escalated' END,
            to_char(v_last AT TIME ZONE 'Africa/Lagos', 'HH24:MI DD Mon'), CASE p_kind WHEN 'REMIND' THEN 'reminded' ELSE 'escalated' END
            USING ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO cov FROM assessment.sheet_coverage(p_sheet);
    v_sem := CASE s.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE s.semester::text END;
    v_what := s.course_code || ' — ' || s.title || ' (' || s.session || ', ' || v_sem || ' semester)';
    SELECT * INTO lr FROM assessment.staff_reach(s.lecturer_id);

    IF p_kind = 'REMIND' THEN
        v_body := 'Dear ' || coalesce(lr.name, 'colleague') || E',\n\n'
            || 'The score sheet for ' || v_what || ' is '
            || CASE WHEN v_late IS NOT NULL THEN v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' past its due date of ' || to_char(s.due_on, 'DD Mon YYYY')
                    WHEN s.due_on IS NOT NULL THEN 'due on ' || to_char(s.due_on, 'DD Mon YYYY')
                    ELSE 'waiting for its marks' END
            || '. ' || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || ' candidates are still without a mark.'
            || E'\n\nPlease enter the marks and submit the sheet on the University portal (Results › My score sheets).'
            || CASE WHEN v_note IS NOT NULL THEN E'\n\nFrom the desk: ' || v_note ELSE '' END
            || E'\n\nExaminations and Records';
        v_sms := 'MOAUM: your ' || s.course_code || ' score sheet (' || s.session || ', ' || v_sem || ' sem.) '
            || CASE WHEN v_late IS NOT NULL THEN 'is ' || v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' late' ELSE 'is awaited' END
            || '; ' || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || ' marks not in. Please submit it on the portal.';
        IF lr.email IS NOT NULL THEN PERFORM platform.queue_notice('EMAIL', lr.email, 'Your score sheet for ' || s.course_code || ' is awaited', v_body, 'score_sheet', p_sheet); END IF;
        IF lr.phone IS NOT NULL THEN PERFORM platform.queue_notice('SMS', lr.phone, 'Score sheet reminder', v_sms, 'score_sheet', p_sheet); END IF;
        IF lr.email IS NOT NULL OR lr.phone IS NOT NULL THEN v_told := 1; v_names := ARRAY[lr.name]; END IF;
    ELSE
        v_to := assessment.chase_office(v_late, s.general_office);
        SELECT coalesce(label, v_to) INTO v_to_label FROM ref.office WHERE code = v_to;
        v_body := 'The score sheet for ' || v_what || ', lecturer ' || coalesce(lr.name, 'of record') || ', is '
            || v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' past its due date of ' || to_char(s.due_on, 'DD Mon YYYY') || '. '
            || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || ' candidates are still without a mark'
            || coalesce(' (reminded ' || (SELECT count(*) FROM assessment.sheet_chase c WHERE c.sheet_id = p_sheet AND c.kind = 'REMIND')::text || ' time(s), last on '
                        || (SELECT to_char(max(c.sent_at) AT TIME ZONE 'Africa/Lagos', 'DD Mon') FROM assessment.sheet_chase c WHERE c.sheet_id = p_sheet AND c.kind = 'REMIND') || ')', '')
            || E'.\n\nThe desk asks you to follow it up with the lecturer, so the department''s results are not held.'
            || CASE WHEN v_note IS NOT NULL THEN E'\n\nFrom the desk: ' || v_note ELSE '' END
            || E'\n\nExaminations and Records';
        v_sms := 'MOAUM: the ' || s.course_code || ' score sheet (' || coalesce(lr.name, 'lecturer') || ') is ' || v_late || ' day'
            || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' late; ' || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0)
            || ' marks not in. Please follow it up.';
        FOR r IN SELECT DISTINCT a.person_id FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
                  WHERE a.office_code = v_to AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND p.ended_on IS NULL
                    AND (v_to NOT IN ('hod', 'dean')
                         OR (v_to = 'hod' AND a.scope_kind = 'department' AND a.scope_id = s.dept_code)
                         OR (v_to = 'dean' AND a.scope_kind = 'faculty' AND a.scope_id = s.faculty_code)) LOOP
            DECLARE h record;
            BEGIN
                SELECT * INTO h FROM assessment.staff_reach(r.person_id);
                v_holders := v_holders + 1;
                IF h.email IS NOT NULL THEN
                    PERFORM platform.queue_notice('EMAIL', h.email, 'A late score sheet: ' || s.course_code, 'Dear ' || coalesce(h.name, 'colleague') || E',\n\n' || v_body, 'score_sheet', p_sheet);
                END IF;
                IF h.phone IS NOT NULL THEN PERFORM platform.queue_notice('SMS', h.phone, 'Late score sheet', v_sms, 'score_sheet', p_sheet); END IF;
                IF h.email IS NOT NULL OR h.phone IS NOT NULL THEN v_told := v_told + 1; v_names := v_names || h.name; END IF;
            END;
        END LOOP;
        IF v_holders = 0 THEN
            RAISE EXCEPTION 'RESULT_CHASE_NO_HOLDER: no % is posted over % — the escalation would reach no one; post one on Users & Roles',
                coalesce(v_to_label, v_to), CASE v_to WHEN 'hod' THEN coalesce(s.dept_name, s.dept_code) WHEN 'dean' THEN coalesce(s.faculty_name, s.faculty_code) ELSE 'the course' END
                USING ERRCODE = 'check_violation';
        END IF;
        -- the lecturer is told it was escalated, and to whom
        IF lr.email IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', lr.email, 'Your score sheet for ' || s.course_code || ' has been escalated',
                'Dear ' || coalesce(lr.name, 'colleague') || E',\n\nThe score sheet for ' || v_what || ' is ' || v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END
                || ' past its due date, and the desk has referred it to the ' || coalesce(v_to_label, v_to) || '. '
                || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || E' candidates are still without a mark.\n\nPlease enter the marks and submit the sheet on the University portal.'
                || E'\n\nExaminations and Records', 'score_sheet', p_sheet);
        END IF;
        IF lr.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', lr.phone, 'Score sheet escalated', 'MOAUM: your ' || s.course_code || ' score sheet is ' || v_late || ' day'
                || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' late and has been referred to the ' || coalesce(v_to_label, v_to) || '. Please submit it on the portal.', 'score_sheet', p_sheet);
        END IF;
    END IF;

    INSERT INTO assessment.sheet_chase (sheet_id, kind, due_on, days_late, expected, missing, to_office, told, told_names, note, sent_by, sent_office)
    VALUES (p_sheet, p_kind, s.due_on, v_late, coalesce(cov.expected, 0), coalesce(cov.missing, 0), v_to, v_told,
            nullif(array_to_string(v_names, ', '), ''), v_note, v_actor, v_office)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id, 'kind', p_kind, 'courseCode', s.course_code, 'daysLate', v_late, 'expected', coalesce(cov.expected, 0),
        'missing', coalesce(cov.missing, 0), 'toOffice', v_to, 'toOfficeLabel', v_to_label, 'told', v_told, 'toldNames', nullif(array_to_string(v_names, ', '), ''),
        'lecturer', lr.name, 'lecturerReachable', lr.email IS NOT NULL OR lr.phone IS NOT NULL);
END $function$
;

CREATE OR REPLACE FUNCTION assessment.hold_script(p_sheet uuid, p_number text, p_ca integer, p_exam integer, p_outcome text, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_student uuid; v_offering uuid; v_code text; v_ca_max int; v_close date; v_outcome text; v_id uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a script is held by a person' USING ERRCODE = '23514'; END IF;
    SELECT o.id, c.code, c.ca_max INTO v_offering, v_code, v_ca_max
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id JOIN catalogue.course c ON c.code = o.course_code
     WHERE s.id = p_sheet;
    IF v_offering IS NULL THEN RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found'; END IF;
    SELECT st.id INTO v_student FROM people.student st
     WHERE upper(btrim(p_number)) IN (upper(st.matric_no), upper(st.admission_no))
     ORDER BY (upper(st.matric_no) = upper(btrim(p_number))) DESC LIMIT 1;
    IF v_student IS NULL THEN
        RAISE EXCEPTION 'no student on the register is numbered %', btrim(p_number)
            USING ERRCODE = '23514', HINT = 'Check the number on the script against the register.';
    END IF;
    IF assessment.on_roll(v_student, v_offering) THEN
        RAISE EXCEPTION '% is on the roll of %; enter the mark on the sheet', btrim(p_number), v_code
            USING ERRCODE = '23514', HINT = 'A held script is for a candidate who is not registered for the course.';
    END IF;
    v_close := assessment.held_scripts_close(p_sheet);
    IF v_close IS NOT NULL AND v_close < current_date THEN
        RAISE EXCEPTION 'late registration for this semester closed on %; a script can no longer be held for %', to_char(v_close, 'DD Month YYYY'), v_code
            USING ERRCODE = '23514', HINT = 'The Registry sets the late-registration date on the calendar.';
    END IF;
    v_outcome := coalesce(nullif(upper(btrim(p_outcome)), ''), 'GRADED');
    IF v_outcome = 'GRADED' THEN
        IF p_ca IS NULL OR p_exam IS NULL THEN RAISE EXCEPTION 'a graded script carries both the CA and the examination mark' USING ERRCODE = '23514'; END IF;
        IF p_ca > v_ca_max THEN RAISE EXCEPTION 'continuous assessment in % is out of %, not %', v_code, v_ca_max, p_ca USING ERRCODE = '23514'; END IF;
        IF p_exam > 100 - v_ca_max THEN RAISE EXCEPTION 'the examination in % is out of %, not %', v_code, 100 - v_ca_max, p_exam USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO assessment.held_script (sheet_id, student_id, ca, exam, outcome, note, entered_by)
    VALUES (p_sheet, v_student, CASE WHEN v_outcome = 'GRADED' THEN p_ca END, CASE WHEN v_outcome = 'GRADED' THEN p_exam END, v_outcome, nullif(btrim(p_note), ''), v_actor)
    RETURNING id INTO v_id;
    RETURN v_id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'a script is already held for % on %', btrim(p_number), v_code USING ERRCODE = '23514',
        HINT = 'Withdraw the held script first if the mark on it is wrong.';
END $function$
;

CREATE OR REPLACE FUNCTION assessment.record_upload_on_behalf(p_sheet uuid, p_reason text, p_rows integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_owner uuid; v_stage text; v_id uuid := gen_random_uuid();
BEGIN
    SELECT o.lecturer_id, s.stage INTO v_owner, v_stage
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id WHERE s.id = p_sheet;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    IF v_stage <> 'ENTRY' THEN
        RAISE EXCEPTION 'RES_SHEET_NOT_AT_ENTRY: the sheet is at %; marks are entered only at entry', lower(v_stage)
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'RES_UPLOAD_ON_BEHALF_SAYS_WHY: an upload on behalf of the lecturer carries its reason'
            USING ERRCODE = 'check_violation',
                  HINT = 'Say why the lecturer is not entering the marks.';
    END IF;
    IF assessment.teaches(p_sheet, v_actor) THEN
        RAISE EXCEPTION 'RES_NOT_ON_BEHALF: you teach this course; the marks are entered as its lecturer, not on behalf'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.sheet_upload (id, sheet_id, uploaded_by, uploader_office, owner_id, reason, rows_written)
    VALUES (v_id, p_sheet, v_actor, v_office, v_owner, btrim(p_reason), coalesce(p_rows, 0));
    RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION assessment.require_stage_desk(p_stage text, p_office text, p_act text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    IF p_office IS NULL OR NOT (p_office = ANY (assessment.stage_offices(p_stage))) THEN
        RAISE EXCEPTION 'RES_NOT_YOUR_STAGE: a sheet at % is % by %, not by the % office',
            lower(replace(p_stage, '_', ' ')), p_act, assessment.stage_desk_name(p_stage), coalesce(p_office, 'unnamed')
            USING ERRCODE = '23514', HINT = 'Each stage of the chain belongs to one desk.';
    END IF;
END $function$
;

CREATE OR REPLACE FUNCTION catalogue.allocate_offering(p_offering uuid, p_lecturer uuid, p_second uuid, p_overload_ok boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    o        catalogue.offering;
    who      uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_units  int;
    v_load   int;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a teaching allocation is made by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such offering' USING ERRCODE = '23503';
    END IF;
    IF p_lecturer IS NULL THEN
        RAISE EXCEPTION 'an allocation names the lecturer who teaches it' USING ERRCODE = '23514';
    END IF;
    IF p_second IS NOT NULL AND p_second = p_lecturer THEN
        RAISE EXCEPTION 'the second examiner cannot be the lecturer' USING ERRCODE = '23514',
            HINT = 'The person who enters the marks may not be the person who verifies them.';
    END IF;

    SELECT c.units INTO v_units FROM catalogue.course c WHERE c.code = o.course_code;
    SELECT coalesce(sum(c2.units), 0) INTO v_load
      FROM catalogue.offering o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
     WHERE o2.lecturer_id = p_lecturer AND o2.session = o.session AND o2.semester = o.semester AND o2.stream = o.stream AND o2.id <> p_offering;
    IF v_load + coalesce(v_units, 0) > 12 AND NOT p_overload_ok THEN
        RAISE EXCEPTION 'this assignment puts the lecturer at % units, over the approved maximum of 12', v_load + coalesce(v_units, 0)
            USING ERRCODE = '23514', HINT = 'Assign it as an overload (reported to the Dean) if the department intends it.';
    END IF;

    UPDATE catalogue.offering
       SET lecturer_id = p_lecturer, second_examiner_id = p_second, allocated_on = current_date
     WHERE id = p_offering;

    -- assigning the lecturer opens the score sheet, if the examination session is open, its sheets released, and none exists yet
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), p_offering, es.id, es.sheets_due
      FROM assessment.exam_session es
     WHERE es.session = o.session AND es.semester = o.semester AND es.state = 'OPEN' AND es.sheets_released_at IS NOT NULL
       AND es.stream = o.stream   -- V381: the examination session of the class's own stream
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = p_offering);
END $function$
;

CREATE OR REPLACE FUNCTION catalogue.end_course(p_code text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is ended by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course SET state = 'ENDED', ended_on = current_date WHERE code = p_code AND state <> 'ENDED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no course % to end', p_code USING ERRCODE = '23503',
            HINT = 'It may already be ended.';
    END IF;
END $function$
;

CREATE OR REPLACE FUNCTION catalogue.merge_course(p_keep text, p_merge text, p_reason text, p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE k catalogue.course; m catalogue.course; v_evidence text; v_block text; v_warn text[] := '{}'; v_moved jsonb := '{}'::jsonb;
        v_clash text; n int; v_bind int := 0; v_pre int := 0; fk record; v_out jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO k FROM catalogue.course WHERE code = upper(btrim(coalesce(p_keep, '')));
    SELECT * INTO m FROM catalogue.course WHERE code = upper(btrim(coalesce(p_merge, '')));
    IF k.code IS NULL THEN RAISE EXCEPTION 'MERGE_KEEP_UNKNOWN: no course is coded %', p_keep USING ERRCODE = '23514'; END IF;
    IF m.code IS NULL THEN RAISE EXCEPTION 'MERGE_UNKNOWN: no course is coded %', p_merge USING ERRCODE = '23514'; END IF;
    IF k.code = m.code THEN RAISE EXCEPTION 'MERGE_SAME: a course is not merged into itself' USING ERRCODE = '23514'; END IF;

    -- the evidence that the two are one course
    v_evidence := CASE
        WHEN catalogue.code_key(k.code) = catalogue.code_key(m.code) THEN 'SAME_CODE_WRITTEN_DIFFERENTLY'
        WHEN catalogue.code_key(catalogue.session_copy_base(m.code)) = catalogue.code_key(k.code) THEN 'SESSION_COPY'
        WHEN lower(regexp_replace(btrim(k.title), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(m.title), '\s+', ' ', 'g'))
             AND k.level = m.level AND k.semester = m.semester AND k.dept_code IS NOT DISTINCT FROM m.dept_code THEN 'SAME_TITLE_AND_LEVEL' END;

    -- what keeps two codes apart on purpose, or blocks the merge
    v_block := CASE
        WHEN v_evidence IS NULL THEN format('MERGE_NOT_SAME: %s and %s are not one course by their codes, nor by title, level, semester and owner', k.code, m.code)
        WHEN (k.code ~ '^BSU-' AND m.code ~ '^MOAU-') OR (k.code ~ '^MOAU-' AND m.code ~ '^BSU-') THEN 'MERGE_FAMILY: the BSU- and MOAU- codes of a course are kept apart on purpose'
        WHEN k.curriculum IS NOT NULL AND m.curriculum IS NOT NULL AND k.curriculum <> m.curriculum THEN format('MERGE_CURRICULUM: %s is %s and %s is %s; the two curricula are kept apart', k.code, k.curriculum, m.code, m.curriculum)
        WHEN k.general_office IS DISTINCT FROM m.general_office AND k.general_office IS NOT NULL AND m.general_office IS NOT NULL THEN 'MERGE_GENERAL_OFFICE: the two are held by different general-studies offices'
        WHEN k.state = 'ENDED' THEN format('MERGE_KEEP_ENDED: %s is ended; keep the live course', k.code) END;
    IF v_block IS NULL THEN
        SELECT string_agg(DISTINCT format('%s %s semester %s', mo.session, CASE WHEN mo.stream = 'CCE' THEN 'CCE' ELSE '' END, mo.semester), '; ') INTO v_clash
          FROM catalogue.offering mo JOIN catalogue.offering ko ON ko.course_code = k.code AND ko.session = mo.session AND ko.semester = mo.semester AND ko.stream = mo.stream
         WHERE mo.course_code = m.code;
        IF v_clash IS NOT NULL THEN
            v_block := format('MERGE_CLASS_CLASH: both codes have a class in %s; two classes are not joined here', v_clash);
        END IF;
    END IF;
    IF NOT p_dry AND v_block IS NULL AND NOT catalogue.merge_office_ok() THEN
        v_block := 'MERGE_OFFICE: a course is merged by the Academic Office or the Registry';
    END IF;
    IF NOT p_dry AND v_block IS NULL AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        v_block := 'MERGE_REASON: a merge is recorded with its reason';
    END IF;
    v_warn := array_remove(ARRAY[
        CASE WHEN lower(btrim(k.title)) <> lower(btrim(m.title)) THEN format('the titles differ: %s / %s', k.title, m.title) END,
        CASE WHEN k.units <> m.units THEN format('the units differ: %s / %s (each registration and result keeps its own)', k.units, m.units) END,
        CASE WHEN k.semester <> m.semester OR k.both_semesters <> m.both_semesters THEN 'the semesters differ' END,
        CASE WHEN k.level <> m.level THEN format('the levels differ: %s / %s', k.level, m.level) END,
        CASE WHEN k.dept_code IS DISTINCT FROM m.dept_code THEN format('the owners differ: %s / %s', k.dept_code, m.dept_code) END,
        CASE WHEN m.state <> 'ENDED' AND k.state <> m.state THEN format('%s is %s and %s is %s', k.code, k.state, m.code, m.state) END], NULL);
    v_out := jsonb_build_object('keep', k.code, 'merge', m.code, 'keepTitle', k.title, 'mergeTitle', m.title, 'evidence', v_evidence,
                                'warnings', to_jsonb(v_warn), 'dry', p_dry, 'blocked', v_block);
    IF v_block IS NOT NULL THEN
        IF p_dry THEN RETURN v_out; END IF;
        RAISE EXCEPTION '%', v_block USING ERRCODE = '23514';
    END IF;

    BEGIN
        -- a binding the course kept already holds (the same programme and level) stays the kept course's own
        DELETE FROM catalogue.course_offer mo WHERE mo.course_code = m.code
           AND EXISTS (SELECT 1 FROM catalogue.course_offer ko WHERE ko.course_code = k.code AND ko.programme_code = mo.programme_code AND ko.level = mo.level);
        GET DIAGNOSTICS v_bind = ROW_COUNT;
        -- a prerequisite that would make the course require itself, or that the course kept holds already
        DELETE FROM catalogue.course_prerequisite p
         WHERE (p.course_code = m.code AND p.requires_code = k.code) OR (p.course_code = k.code AND p.requires_code = m.code)
            OR (p.course_code = m.code AND EXISTS (SELECT 1 FROM catalogue.course_prerequisite q WHERE q.course_code = k.code AND q.requires_code = p.requires_code))
            OR (p.requires_code = m.code AND EXISTS (SELECT 1 FROM catalogue.course_prerequisite q WHERE q.course_code = p.course_code AND q.requires_code = k.code));
        GET DIAGNOSTICS v_pre = ROW_COUNT;
        -- every record that names the merged course names the course kept
        FOR fk IN SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col
                    FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
                   WHERE c.contype = 'f' AND c.confrelid = 'catalogue.course'::regclass AND cardinality(c.conkey) = 1
                   ORDER BY 1, 2 LOOP
            BEGIN
                EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = $2', fk.tbl, fk.col, fk.col) USING k.code, m.code;
                GET DIAGNOSTICS n = ROW_COUNT;
            EXCEPTION WHEN unique_violation THEN
                RAISE EXCEPTION 'MERGE_CONFLICT: % holds both % and % where only one may stand (%)', fk.tbl, k.code, m.code, SQLERRM USING ERRCODE = '23514';
            END;
            IF n > 0 THEN v_moved := v_moved || jsonb_build_object(fk.tbl || '.' || fk.col, n); END IF;
        END LOOP;
        UPDATE assessment.legacy_result_holding SET course_code = k.code WHERE course_code = m.code;
        GET DIAGNOSTICS n = ROW_COUNT;
        IF n > 0 THEN v_moved := v_moved || jsonb_build_object('assessment.legacy_result_holding.course_code', n); END IF;
        UPDATE catalogue.course_owner_history SET course_code = k.code WHERE course_code = m.code;
        GET DIAGNOSTICS n = ROW_COUNT;
        IF n > 0 THEN v_moved := v_moved || jsonb_build_object('catalogue.course_owner_history.course_code', n); END IF;
        UPDATE catalogue.course_reset_item SET course_code = k.code WHERE course_code = m.code;
        v_moved := v_moved || jsonb_build_object('bindingsAlreadyHeld', v_bind, 'prerequisitesAlreadyHeld', v_pre);

        -- the merged code stays an alias of the course kept, with the merged record as it was; the twin record goes
        INSERT INTO catalogue.course_alias (alias_code, course_code, absorbed_id, absorbed, evidence, moved, reason, merged_by, merged_office)
        VALUES (m.code, k.code, m.id, to_jsonb(m), v_evidence, v_moved, coalesce(nullif(btrim(p_reason), ''), 'dry run'), v_actor,
                nullif(current_setting('moaum.actor_office', true), ''));
        DELETE FROM catalogue.course WHERE code = m.code;
        v_out := v_out || jsonb_build_object('moved', v_moved);
        IF p_dry THEN RAISE EXCEPTION 'MERGE_DRY_RUN' USING ERRCODE = 'P0001'; END IF;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'MERGE_DRY_RUN' THEN RAISE; END IF;
    END;
    RETURN v_out;
END $function$
;

CREATE OR REPLACE FUNCTION catalogue.restore_course(p_code text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text := upper(btrim(p_code));
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a course is restored by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course SET state = 'LIVE', ended_on = NULL WHERE code = v_code AND state = 'ENDED';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no ended course % to restore', v_code USING ERRCODE = '23503',
            HINT = 'Only an ended course can be restored.';
    END IF;
    RETURN v_code;
END $function$
;

CREATE OR REPLACE FUNCTION catalogue.set_cbt_enabled(p_code text, p_on boolean)
 RETURNS catalogue.course
 LANGUAGE plpgsql
AS $function$
DECLARE c catalogue.course;
BEGIN
    SELECT * INTO c FROM catalogue.course WHERE upper(code) = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_COURSE_NOT_FOUND: no course %', p_code USING ERRCODE = '23503'; END IF;
    IF p_on AND c.state = 'ENDED' THEN
        RAISE EXCEPTION 'CBT_COURSE_ENDED: % has ended and is not examined', c.code USING ERRCODE = '23514';
    END IF;
    IF NOT p_on AND EXISTS (SELECT 1 FROM assessment.cbt_exam e WHERE e.course_code = c.code AND e.state IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'CLOSED')) THEN
        RAISE EXCEPTION 'CBT_COURSE_IN_USE: % has a CBT examination not yet completed or cancelled', c.code USING ERRCODE = '23514',
            HINT = 'Complete or cancel it first.';
    END IF;
    UPDATE catalogue.course SET cbt_enabled = p_on WHERE id = c.id RETURNING * INTO c;
    RETURN c;
END $function$
;

CREATE OR REPLACE FUNCTION jupeb.set_subject_cbt(p_subject uuid, p_on boolean)
 RETURNS jupeb.subject
 LANGUAGE plpgsql
AS $function$
DECLARE s jupeb.subject;
BEGIN
    SELECT * INTO s FROM jupeb.subject WHERE id = p_subject FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SUBJECT_NOT_FOUND: no such JUPEB subject' USING ERRCODE = '23503'; END IF;
    IF p_on AND NOT s.active THEN RAISE EXCEPTION 'CBT_SUBJECT_INACTIVE: % is not an active subject', s.title USING ERRCODE = '23514'; END IF;
    IF NOT p_on AND EXISTS (SELECT 1 FROM assessment.cbt_exam e WHERE e.jupeb_subject_id = s.id AND e.state IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'CLOSED')) THEN
        RAISE EXCEPTION 'CBT_COURSE_IN_USE: % has a CBT examination not yet completed or cancelled', s.title USING ERRCODE = '23514',
            HINT = 'Complete or cancel it first.';
    END IF;
    UPDATE jupeb.subject SET cbt_enabled = p_on, updated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, updated_at = now() WHERE id = s.id RETURNING * INTO s;
    RETURN s;
END $function$
;

CREATE OR REPLACE FUNCTION credentials.produce_transcript(p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE t credentials.transcript_request; v jsonb; v_id uuid; prev uuid;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no transcript request %', p_request USING ERRCODE = 'no_data_found'; END IF;
    IF t.paid_at IS NULL THEN
        RAISE EXCEPTION 'request % is not payable yet: the SLA clock runs from payment, and production does', t.ref USING ERRCODE = 'check_violation';
    END IF;
    IF t.kind = 'TRANSCRIPT' AND NOT clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN
        RAISE EXCEPTION 'request % is held at clearance', t.ref USING ERRCODE = 'check_violation',
              HINT = 'A clearance unit holds the candidate; the student sees which.';
    END IF;
    IF t.stage NOT IN ('READY','HELD_AT_CLEARANCE','PROCESSING','CORRECTION') THEN
        RAISE EXCEPTION 'request % is %', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = 'check_violation';
    END IF;
    v := credentials.validate_record(t.student_id, t.kind, t.session, t.semester);
    IF NOT (v->>'ok')::boolean THEN RAISE EXCEPTION 'the record does not validate: %', (SELECT string_agg(e->>'message', '; ') FROM jsonb_array_elements(v->'findings') e WHERE e->>'severity' = 'ERROR') USING ERRCODE = '23514'; END IF;
    prev := t.issued_id;
    v_id := credentials.issue(t.student_id, t.kind, t.id, t.session, t.semester, prev, CASE WHEN prev IS NULL THEN NULL ELSE 'Regenerated after correction' END);
    UPDATE credentials.transcript_request SET stage = 'GENERATED', produced_at = now(), produced_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           validated_at = coalesce(validated_at, now()), validation = coalesce(validation, v), started_at = coalesce(started_at, now()), issued_id = v_id WHERE id = t.id;
    PERFORM credentials.log(t.id, v_id, t.student_id, 'GENERATED', t.stage, 'GENERATED', 'Version ' || (SELECT version FROM credentials.issued WHERE id = v_id));
    PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ': document generated', 'The document for your request ' || t.ref || ' has been generated and is with the quality check before authorisation.', 'MOAUM: request ' || t.ref || ' generated; quality check next.');
    RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION finance.new_gateway_test_reference(p_student uuid, p_session text, p_amount numeric, p_days integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_days int := coalesce(p_days, 7); v_ref text;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'GATEWAY_TEST_ACTOR: a test reference is issued by a person' USING ERRCODE = '23514';
    END IF;
    IF v_office IS NULL OR v_office NOT IN ('bursar', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'GATEWAY_TEST_OFFICE: a test reference is issued from the Bursary''s desk' USING ERRCODE = '23514',
            HINT = 'The Bursar issues it on Payment Gateways (the Directorate of ICT and the administrators may too).';
    END IF;
    IF v_days < 1 OR v_days > 14 THEN
        RAISE EXCEPTION 'GATEWAY_TEST_DAYS: a test reference stays payable for 1 to 14 days' USING ERRCODE = '23514',
            HINT = 'Issue a new one if the test runs longer.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 10000 THEN
        RAISE EXCEPTION 'GATEWAY_TEST_AMOUNT: a test reference is for a small amount, above zero and at most NGN 10,000' USING ERRCODE = '23514',
            HINT = 'NGN 100 is enough to test a payment.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN
        RAISE EXCEPTION 'GATEWAY_TEST_STUDENT: a test reference is issued against a student on the register' USING ERRCODE = '23514';
    END IF;
    -- the shape of every student reference (V027), with the test checkout's purpose; then the days the Bursar chose
    v_ref := finance.new_purpose_reference(p_student, p_session, p_amount, 'Gateway test by the Bursary');
    UPDATE finance.payment_reference SET expires_at = generated_at + make_interval(days => v_days) WHERE reference = v_ref;
    INSERT INTO finance.gateway_test_reference (reference, days, issued_by, issued_office) VALUES (v_ref, v_days, v_actor, v_office);
    RETURN v_ref;
END $function$
;

CREATE OR REPLACE FUNCTION finance.refresh_entitlement(p_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r finance.payment_reference; v_applied text[] := '{}'; v_problems text[] := '{}'; v_trn text; v_n int; v_before jsonb;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAY_REFERENCE: no student payment reference % was generated by this portal', p_reference USING ERRCODE = '23514';
    END IF;
    IF r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'PAY_NOT_CONFIRMED: reference % is not confirmed', r.reference USING ERRCODE = '23514',
            HINT = 'Verify it with the gateway first; if it does not confirm, escalate to the Bursary with the evidence.';
    END IF;
    v_before := finance.entitlement_state(r.student_id, r.session);
    IF r.purpose LIKE 'Transcript TRN-%' THEN
        v_trn := substr(r.purpose, 12, 14);
        UPDATE credentials.transcript_request t SET paid_at = now(),
               stage = CASE WHEN clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN 'READY' ELSE 'HELD_AT_CLEARANCE' END
         WHERE t.ref = v_trn AND t.paid_at IS NULL;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_applied := v_applied || CASE WHEN v_n > 0 THEN 'The transcript request is marked paid.' ELSE 'The transcript request already stood paid.' END;
    ELSIF r.purpose LIKE 'Hostel accommodation%' THEN
        BEGIN
            PERFORM hostel.confirm_by_reference(r.reference);
            v_applied := v_applied || 'The hostel booking stands confirmed against the payment.'::text;
        EXCEPTION WHEN check_violation THEN
            v_problems := v_problems || ('Hostel: ' || SQLERRM || ' — escalate to the Bursary and the Dean of Student Affairs.');
        END;
    ELSIF r.purpose LIKE 'Library fine%' THEN
        PERFORM library.settle_by_reference(r.reference);
        v_applied := v_applied || 'The library fine stands settled.'::text;
    ELSIF r.purpose LIKE 'Wallet top-up%' AND NOT EXISTS (SELECT 1 FROM finance.wallet_entry w WHERE w.reference = r.reference) THEN
        v_problems := v_problems || 'Wallet: the top-up is confirmed but no wallet credit stands against it; a credit is the Bursary''s to write — escalate the ticket to the Bursary.'::text;
    END IF;
    PERFORM people.refresh_academic_position(r.student_id);
    v_applied := v_applied || 'The academic position was recomputed from the record.'::text;
    RETURN jsonb_build_object('reference', r.reference, 'session', r.session, 'purpose', r.purpose, 'applied', to_jsonb(v_applied), 'problems', to_jsonb(v_problems),
                              'before', v_before, 'after', finance.entitlement_state(r.student_id, r.session));
END $function$
;

CREATE OR REPLACE FUNCTION hostel.draw(p_session text, p_seed text)
 RETURNS TABLE(allocated integer, unsuccessful integer, priority integer)
 LANGUAGE plpgsql
AS $function$
DECLARE s hostel.session_setting; a record; v_bed uuid; pos int := 0; n_alloc int := 0; n_pri int := 0; n_un int := 0;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_seed text; v_alloc uuid; r record;
BEGIN
    SELECT * INTO s FROM hostel.session_setting WHERE session = p_session FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'accommodation for % is not open', p_session USING ERRCODE = '23514'; END IF;
    IF s.allocation_method = 'MANUAL' THEN RAISE EXCEPTION 'allocation for % is manual: seat each student from the applications desk', p_session USING ERRCODE = '23514'; END IF;
    v_seed := CASE WHEN s.allocation_method = 'BALLOT' THEN btrim(p_seed) ELSE coalesce(nullif(btrim(p_seed), ''), s.allocation_method) END;
    IF s.allocation_method = 'BALLOT' AND (p_seed IS NULL OR length(btrim(p_seed)) < 6) THEN
        RAISE EXCEPTION 'the draw runs from a published seed of at least six characters' USING ERRCODE = '23514',
            HINT = 'Publish the seed before the draw.';
    END IF;
    IF s.drawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the draw for % was run on % from seed %', p_session, s.drawn_at::date, s.seed USING ERRCODE = '23514',
            HINT = 'A draw is run once.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hostel.free_beds(p_session)) THEN RAISE EXCEPTION 'no bed is free to allocate' USING ERRCODE = '23514', HINT = 'Add rooms, or return beds to service, before the draw.'; END IF;
    UPDATE hostel.session_setting SET seed = v_seed, drawn_at = now(), drawn_by = v_actor, state = 'ALLOCATED', updated_at = now() WHERE session = p_session;
    -- the order: priority categories first, by the time they applied; then everybody else by the session's method
    FOR a IN
        SELECT ap.id, ap.student_id, ap.hall_code, ap.category, ap.room_type_pref, ap.block_pref, st.sex,
               (ap.category <> 'NONE' OR (s.allocation_method = 'SPECIAL_NEEDS' AND ap.special_need IS NOT NULL)) AS is_priority
          FROM hostel.application ap JOIN people.student st ON st.id = ap.student_id
          LEFT JOIN ref.programme p ON p.code = st.programme_code
         WHERE ap.session = p_session AND ap.state = 'APPLIED' AND (NOT s.requires_review OR ap.review = 'APPROVED') AND ap.review IS DISTINCT FROM 'REJECTED'
         ORDER BY (ap.category <> 'NONE' OR (s.allocation_method = 'SPECIAL_NEEDS' AND ap.special_need IS NOT NULL)) DESC,
                  CASE WHEN ap.category <> 'NONE' THEN ap.applied_at END,
                  CASE s.allocation_method
                      WHEN 'FIRST_COME' THEN to_char(ap.applied_at, 'YYYYMMDDHH24MISSUS')
                      WHEN 'LEVEL' THEN lpad((1000 - st.current_level)::text, 4, '0') || to_char(ap.applied_at, 'YYYYMMDDHH24MISSUS')
                      WHEN 'FACULTY' THEN coalesce(p.faculty_code, 'ZZZ') || coalesce(p.dept_code, 'ZZZ') || st.surname || st.other_names
                      WHEN 'PROGRAMME' THEN coalesce(p.code, 'ZZZ') || st.surname || st.other_names
                      ELSE md5(v_seed || ap.student_id::text) END,
                  md5(v_seed || ap.student_id::text)
    LOOP
        pos := pos + 1;
        v_bed := hostel.pick_bed(p_session, a.sex, a.hall_code, a.room_type_pref, a.block_pref, s.eligible_kinds);
        IF v_bed IS NOT NULL THEN
            v_alloc := hostel.hold(a.id, v_bed, CASE WHEN a.is_priority THEN 'PRIORITY' ELSE 'BALLOT' END, pos, 'Allocation of ' || p_session || ' by ' || lower(s.allocation_method));
            n_alloc := n_alloc + 1;
            IF a.is_priority THEN n_pri := n_pri + 1; END IF;
        ELSE
            -- a reserve, in the order the draw put them: a lapsed bed follows this order, not a telephone call
            UPDATE hostel.application SET state = 'UNSUCCESSFUL', draw_position = pos WHERE id = a.id;
            PERFORM hostel.log(a.id, NULL, a.student_id, NULL, NULL, NULL, 'WAITLISTED', 'APPLIED', 'UNSUCCESSFUL', 'Position ' || pos || ': no bed free when the turn came');
            n_un := n_un + 1;
        END IF;
    END LOOP;
    -- everyone told, from the record the draw wrote
    FOR r IN
        SELECT al.id, al.student_id, al.state, al.held_until, h.name AS hall, rm.block, rm.room_no, b.label, al.reference_no
          FROM hostel.allocation al JOIN hostel.room rm ON rm.id = al.room_id JOIN hostel.hall h ON h.code = rm.hall_code JOIN hostel.bed b ON b.id = al.bed_id
         WHERE al.session = p_session AND al.lapsed_at IS NULL AND al.ended_at IS NULL AND al.allocated_at >= now() - interval '1 minute'
    LOOP
        PERFORM hostel.tell_student(r.student_id, 'You have been allocated a bed',
            'Allocation ' || r.reference_no || ' for ' || p_session || ': ' || r.hall || ', Block ' || r.block || ', Room ' || r.room_no || ', ' || r.label || '. '
            || CASE WHEN r.state = 'HELD' THEN 'The bed is held until ' || to_char(r.held_until AT TIME ZONE 'Africa/Lagos', 'FMDay DD FMMonth HH24:MI') || ' for payment of the accommodation fee; unpaid, it goes to the next name.'
                    ELSE 'Accept the allocation on the portal under the hostel rules, then check in at the porter''s lodge.' END,
            'MOAUM: bed allocated — ' || r.hall || ' ' || r.block || '-' || r.room_no || ' ' || r.label || '. See the portal.');
    END LOOP;
    FOR r IN SELECT ap.student_id, ap.draw_position FROM hostel.application ap WHERE ap.session = p_session AND ap.state = 'UNSUCCESSFUL' LOOP
        PERFORM hostel.tell_student(r.student_id, 'Your hostel application is on the waiting list',
            'Every bed was taken before your turn (position ' || r.draw_position || ') came up for ' || p_session || '. Waitlisted students are offered a bed in order when one becomes free.',
            'MOAUM: hostel waiting list position ' || r.draw_position || ' for ' || p_session || '.');
    END LOOP;
    RETURN QUERY SELECT n_alloc, n_un, n_pri;
END $function$
;

CREATE OR REPLACE FUNCTION hostel.new_fee_reference(p_application uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE ap hostel.application; al hostel.allocation; v_ref text;
BEGIN
    SELECT * INTO ap FROM hostel.application WHERE id = p_application;
    IF NOT FOUND THEN RAISE EXCEPTION 'no application %', p_application USING ERRCODE = 'no_data_found'; END IF;
    SELECT * INTO al FROM hostel.allocation WHERE application_id = ap.id AND lapsed_at IS NULL AND ended_at IS NULL ORDER BY allocated_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'no bed is held against this application' USING ERRCODE = '23514',
        HINT = 'The accommodation fee is paid against an allocated bed.'; END IF;
    IF al.fee_status = 'PAID' THEN RAISE EXCEPTION 'this allocation is already paid and confirmed' USING ERRCODE = '23505'; END IF;
    IF al.fee_status = 'NO_CHARGE' OR coalesce(al.fee_amount, 0) = 0 THEN RAISE EXCEPTION 'HOSTEL_NO_CHARGE: no hostel charge applies to this allocation' USING ERRCODE = '23514'; END IF;
    IF al.state = 'HELD' AND al.held_until < now() THEN RAISE EXCEPTION 'HOSTEL_RESERVATION_EXPIRED: the reservation of this bed expired at %', to_char(al.held_until AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') USING ERRCODE = '23514',
        HINT = 'The bed is released; reserve again if applications are open and a bed is free.'; END IF;
    IF al.reference IS NOT NULL AND EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = al.reference AND expires_at > now() AND confirmed_at IS NULL) THEN
        RETURN al.reference;
    END IF;
    v_ref := finance.new_purpose_reference(ap.student_id, ap.session, al.fee_amount, 'Hostel accommodation ' || ap.session || ' ' || al.id::text);
    UPDATE hostel.allocation SET reference = v_ref WHERE id = al.id;
    RETURN v_ref;
END $function$
;

CREATE OR REPLACE FUNCTION jupeb.propose_claim_refund(p_claim uuid, p_reference text, p_amount numeric, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c jupeb.refund_claim; a jupeb.application; v_ref text := upper(btrim(coalesce(p_reference, ''))); v_rf text; v_id uuid;
BEGIN
    SELECT * INTO c FROM jupeb.refund_claim WHERE id = p_claim FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'JUPEB_REFUND_CLAIM: no such refund claim' USING ERRCODE = '23514'; END IF;
    IF c.declined_at IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_REFUND_DECLINED: this claim was declined' USING ERRCODE = '23514'; END IF;
    IF c.account_number IS NULL THEN
        RAISE EXCEPTION 'JUPEB_REFUND_DETAILS: the candidate has not given the account a refund is paid into' USING ERRCODE = '23514',
            HINT = 'The candidate gives it on the JUPEB portal.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.application_id = c.application_id AND f.reference = v_ref AND f.confirmed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'JUPEB_REFUND_REFERENCE: % is not a confirmed payment of this candidate', v_ref USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'JUPEB_REFUND_REASON: say why the refund is owed' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM jupeb.application WHERE id = c.application_id;
    v_rf := finance.propose_refund(NULL, upper(a.surname) || ' ' || a.first_name || coalesce(' ' || a.middle_name, '') || ' (JUPEB ' || a.application_no || ')',
                                   btrim(p_reason), p_amount, c.bank_name, c.account_name, right(c.account_number, 4), v_ref);
    v_id := (SELECT id FROM finance.refund WHERE reference = v_rf);
    INSERT INTO jupeb.refund_claim_refund (claim_id, refund_id, reference) VALUES (c.id, v_id, v_ref);
    PERFORM jupeb.app_event(c.application_id, 'REFUND_PROPOSED', 'Refund ' || v_rf || ' raised by the Bursary against ' || v_ref || ', awaiting approval');
    RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION library.issue(p_accession text, p_student uuid, p_person uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c library.copy; s library.setting; v uuid := gen_random_uuid(); n_open int; n_over int; v_item uuid;
BEGIN
    SELECT * INTO s FROM library.setting WHERE row_no = 1;
    SELECT * INTO c FROM library.copy WHERE accession = upper(btrim(p_accession)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no copy % on the shelf list', p_accession USING ERRCODE = '23503'; END IF;
    IF c.state <> 'AVAILABLE' AND c.state <> 'RESERVED' THEN
        RAISE EXCEPTION 'copy % is %', c.accession, lower(replace(c.state, '_', ' ')) USING ERRCODE = '23514',
            HINT = 'A copy on loan is returned before it is issued again; a lost or withdrawn copy is not issued.';
    END IF;
    IF (p_student IS NULL) = (p_person IS NULL) THEN
        RAISE EXCEPTION 'a loan is to one patron: a student or a member of staff' USING ERRCODE = '23514';
    END IF;
    IF p_student IS NOT NULL THEN
        SELECT count(*), count(*) FILTER (WHERE due_on < current_date) INTO n_open, n_over
          FROM library.loan WHERE student_id = p_student AND returned_at IS NULL;
        IF n_over > 0 THEN
            RAISE EXCEPTION 'the patron has % overdue item(s); nothing is issued until they are returned', n_over USING ERRCODE = '23514',
                HINT = 'Return the overdue items first.';
        END IF;
        IF n_open >= s.max_loans THEN
            RAISE EXCEPTION 'the patron already has % items on loan, the most the rule allows', n_open USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM library.loan l WHERE l.student_id = p_student AND l.returned_at IS NOT NULL
                    AND l.fine IS NOT NULL AND l.fine > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL) THEN
            RAISE EXCEPTION 'an unpaid fine stands against the patron' USING ERRCODE = '23514',
                HINT = 'The fine is settled against its payment reference, or waived by the Librarian with the reason on the record.';
        END IF;
        -- a reserved copy goes to the patron who reserved it
        IF c.state = 'RESERVED' THEN
            IF NOT EXISTS (SELECT 1 FROM library.reservation r WHERE r.item_id = c.item_id AND r.student_id = p_student AND r.state = 'READY') THEN
                RAISE EXCEPTION 'copy % is held for the patron who reserved it', c.accession USING ERRCODE = '23514';
            END IF;
            UPDATE library.reservation SET state = 'FULFILLED', decided_at = now() WHERE item_id = c.item_id AND student_id = p_student AND state = 'READY';
        END IF;
    END IF;
    INSERT INTO library.loan (id, accession, student_id, person_id, due_on) VALUES (v, c.accession, p_student, p_person, current_date + s.loan_days);
    UPDATE library.copy SET state = 'ON_LOAN' WHERE accession = c.accession;
    RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION lms.submit(p_assignment uuid, p_student uuid, p_text text, p_filename text, p_content_type text, p_bytes bigint)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE a lms.assignment; v uuid := gen_random_uuid(); v_late boolean;
BEGIN
    SELECT * INTO a FROM lms.assignment WHERE id = p_assignment AND ended_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such assignment' USING ERRCODE = '23503'; END IF;
    IF NOT lms.on_roll(a.offering_id, p_student) THEN
        RAISE EXCEPTION 'you are not registered and approved for this course' USING ERRCODE = '23514',
            HINT = 'Only a student with an approved registration for the course submits.';
    END IF;
    IF now() < a.opens_at THEN RAISE EXCEPTION 'the assignment opens on %', a.opens_at::date USING ERRCODE = '23514'; END IF;
    v_late := now() > a.closes_at;
    IF v_late AND now() > a.closes_at + make_interval(hours => a.late_hours) THEN
        RAISE EXCEPTION 'the assignment closed on % and the late window of % hours has passed', a.closes_at::date, a.late_hours USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM lms.submission WHERE assignment_id = p_assignment AND student_id = p_student AND mark IS NOT NULL) THEN
        RAISE EXCEPTION 'this submission is marked; it is not replaced' USING ERRCODE = '23514';
    END IF;
    DELETE FROM lms.submission_blob WHERE submission_id IN (SELECT id FROM lms.submission WHERE assignment_id = p_assignment AND student_id = p_student);
    DELETE FROM lms.submission WHERE assignment_id = p_assignment AND student_id = p_student;
    INSERT INTO lms.submission (id, assignment_id, student_id, text, filename, content_type, bytes, late)
    VALUES (v, p_assignment, p_student, nullif(btrim(p_text), ''), p_filename, p_content_type, p_bytes, v_late);
    RETURN v;
END $function$
;

CREATE OR REPLACE FUNCTION people.deferment_decide(p_id uuid, p_action text, p_note text, p_actor uuid, p_office text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE d people.deferment; v_from text; v_to text; v_note text := nullif(btrim(coalesce(p_note, '')), ''); fin record; tl record; v_off text := lower(coalesce(p_office, ''));
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such deferment request' USING ERRCODE = '23503'; END IF;
    v_from := d.state;
    CASE p_action
        WHEN 'BURSARY_APPROVE' THEN
            IF d.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'the Bursary verifies a submitted request; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the Bursary''s approval is the Bursary''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            SELECT * INTO fin FROM people.deferment_financials(d.student_id, d.session);
            v_to := 'BURSARY_APPROVED';
            UPDATE people.deferment SET state = v_to, bursary_at = now(), bursary_by = p_actor, bursary_note = v_note,
                   bursary_last_fee_amount = fin.last_fee_amount, bursary_last_fee_ref = fin.last_fee_ref, bursary_last_fee_at = fin.last_fee_at, bursary_last_fee_session = fin.last_fee_session,
                   bursary_balance = fin.balance, bursary_balance_session = fin.balance_session, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request has passed financial verification', 'The Bursary has verified your financial record and approved your request; it is now with your Head of Department.');
            PERFORM people.deferment_tell_desk(d.id, 'hod', 'A deferment request awaits the department', 'The Bursary has approved a deferment request of a student of your department. Open the deferments desk on the portal to review and decide.');
        WHEN 'RECOMMEND' THEN
            IF d.state <> 'BURSARY_APPROVED' THEN RAISE EXCEPTION 'the department decides after the Bursary; this request is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the department''s approval is the Head of Department''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            v_to := 'DEPT_RECOMMENDED';
            UPDATE people.deferment SET state = v_to, dept_at = now(), dept_by = p_actor, dept_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is approved by the department', 'Your Head of Department has approved your request; it is now with the faculty.');
            PERFORM people.deferment_tell_desk(d.id, 'dean', 'A deferment request awaits the faculty', 'The department has approved a student''s deferment request; the faculty''s decision is next on the deferments desk.');
        WHEN 'FAC_RECOMMEND' THEN
            IF d.state <> 'DEPT_RECOMMENDED' THEN RAISE EXCEPTION 'the faculty decides after the department; this request is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the faculty''s approval is the Dean''s or the Faculty Officer''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            v_to := 'FAC_RECOMMENDED';
            UPDATE people.deferment SET state = v_to, fac_at = now(), fac_by = p_actor, fac_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request is approved by the faculty', 'The faculty has approved your request; it is with the Academic Office, which forwards approved requests to the Deputy Vice-Chancellor (Academic).');
            PERFORM people.deferment_tell_desk(d.id, 'academic', 'A faculty-approved deferment request is ready to forward', 'A deferment request approved by the Bursary, the department and the faculty awaits the Academic Office; it may be downloaded and forwarded to the DVC.');
        WHEN 'DVC_APPROVE' THEN
            IF d.state <> 'FORWARDED_TO_DVC' THEN RAISE EXCEPTION 'the DVC decides a request the Academic Office has forwarded; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'the DVC''s approval is the Deputy Vice-Chancellor''s; % does not give it', v_off USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'the DVC''s decision carries a comment' USING ERRCODE = '23514', HINT = 'Write the recommendation or observation that goes on the record with the approval.'; END IF;
            -- the DVC's approval is the final approval: the request is APPROVED and the academic effect applied in this transaction
            v_to := 'APPROVED';
            UPDATE people.deferment SET state = v_to, dvc_at = now(), dvc_by = p_actor, dvc_note = v_note, decided_at = now(), decided_by = p_actor, decision_note = v_note, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_apply_effect(d.id);
            SELECT * INTO tl FROM people.programme_timeline(d.student_id);
            SELECT * INTO d FROM people.deferment WHERE id = p_id;
            PERFORM people.deferment_tell(d.id, 'DEFERMENT APPROVED · ' || d.reference,
                'Your deferment request has been approved by the Deputy Vice-Chancellor (Academic)' || coalesce(': ' || v_note, '') || '.'
                || E'\nDeferred period: ' || d.session || coalesce(' — semester ' || d.semester, ' — the whole session')
                || E'\nDuration: ' || d.extension_semesters || ' semester(s)'
                || E'\nExpected return: ' || d.return_session || ' — semester ' || d.return_semester
                || E'\nCourses affected: ' || d.courses_affected
                || E'\nYour programme completion timeline has automatically been extended by ' || d.extension_semesters || ' semester(s); your expected completion is now '
                || tl.adjusted_completion_session || ' semester ' || tl.adjusted_completion_semester || '. Your CGPA is not affected; the deferred courses are not failed.'
                || E'\nYour deferred courses will become available as deferred courses on your registration form when you resume. You cannot register for the deferred period. Download your approval letter from the portal.');
            PERFORM people.deferment_tell_desk(d.id, 'registrar', 'A deferment has been approved by the DVC', 'The Deputy Vice-Chancellor (Academic) has approved deferment ' || d.reference || '; the period is held on the record and the student told.');
            -- the period already begun holds at once
            PERFORM people.deferments_tick();
        WHEN 'SBC_APPROVE' THEN
            RAISE EXCEPTION 'the Deputy Vice-Chancellor''s approval is the final approval; there is no further stage' USING ERRCODE = '23514';
        WHEN 'REJECT' THEN
            IF d.state NOT IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC') THEN RAISE EXCEPTION 'a request in review is rejected; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'this request is %; % does not decide it at this stage', lower(people.deferment_stage_label(d.state)), v_off USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514', HINT = 'Say why the request is refused; the student reads it.'; END IF;
            v_to := 'REJECTED';
            UPDATE people.deferment SET state = v_to, decided_at = now(), decided_by = p_actor, decision_note = v_note, returned_from_state = d.state, returned_by_office = v_off, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request has been rejected', 'Your request to defer ' || d.session || coalesce(' semester ' || d.semester, '') || ' was not approved by the ' || coalesce(people.deferment_stage_office_label(d.state), 'desk') || '. Reason: ' || v_note);
        WHEN 'CORRECTION' THEN
            IF d.state NOT IN ('SUBMITTED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC') THEN RAISE EXCEPTION 'a request in review is returned for correction; this one is %', lower(people.deferment_stage_label(d.state)) USING ERRCODE = '23514'; END IF;
            IF NOT people.deferment_office_may(v_off, d.state) THEN RAISE EXCEPTION 'this request is %; % does not decide it at this stage', lower(people.deferment_stage_label(d.state)), v_off USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'say what the student must correct' USING ERRCODE = '23514'; END IF;
            v_to := 'CORRECTION_REQUIRED';
            UPDATE people.deferment SET state = v_to, correction_note = v_note, returned_from_state = d.state, returned_by_office = v_off, updated_at = now() WHERE id = d.id;
            PERFORM people.deferment_tell(d.id, 'Your deferment request requires correction', 'Your request has been returned to you by the ' || coalesce(people.deferment_stage_office_label(d.state), 'desk') || ': ' || v_note || ' Correct it on the portal and submit it again; it returns to the same desk.');
        WHEN 'CANCEL' THEN
            IF d.state NOT IN ('DRAFT','SUBMITTED','CORRECTION_REQUIRED','BURSARY_APPROVED','DEPT_RECOMMENDED','FAC_RECOMMENDED','FORWARDED_TO_DVC','APPROVED') THEN
                RAISE EXCEPTION 'a deferment in force is not cancelled; the student returns from it' USING ERRCODE = '23514';
            END IF;
            IF v_off NOT IN ('student','academic','registrar','dregistrar','super') THEN RAISE EXCEPTION 'a request is cancelled by the student or the Registry' USING ERRCODE = '23514'; END IF;
            IF v_note IS NULL THEN RAISE EXCEPTION 'a cancellation carries its reason' USING ERRCODE = '23514'; END IF;
            v_to := 'CANCELLED';
            UPDATE people.deferment SET state = v_to, cancel_note = v_note, updated_at = now() WHERE id = d.id;
            IF d.state <> 'DRAFT' THEN
                PERFORM people.deferment_tell(d.id, 'Your deferment request has been cancelled', 'The deferment request ' || d.reference || ' is cancelled: ' || v_note);
            END IF;
        WHEN 'APPROVE' THEN
            RAISE EXCEPTION 'a deferment is approved in its order: the Bursary, the department, the faculty, the Academic Office''s forwarding, then the Deputy Vice-Chancellor; no stage is skipped'
                USING ERRCODE = '23514', HINT = 'Act at your own stage.';
        ELSE RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM people.deferment_log(d.id, p_action, v_from, v_to, v_note);
    RETURN v_to;
END $function$
;

CREATE OR REPLACE FUNCTION people.matric_batch_cancel(p_batch uuid, p_reason text, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE b people.matric_batch;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state = 'ISSUED' THEN RAISE EXCEPTION 'an issued batch is not cancelled: its numbers are permanent' USING ERRCODE = '23514', HINT = 'An issued number is corrected through the Registry''s revocation procedure.'; END IF;
    IF b.state = 'CANCELLED' THEN RETURN; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'cancelling a batch carries its reason' USING ERRCODE = '23514'; END IF;
    -- the reserved numbers were never issued: released, as the numbering policy allows; nothing issued is ever reused
    UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Batch cancelled: ' || btrim(p_reason) WHERE batch_id = p_batch AND released_at IS NULL;
    UPDATE people.matric_batch_row SET state = 'DROPPED', drop_reason = coalesce(drop_reason, 'Batch cancelled: ' || btrim(p_reason)) WHERE batch_id = p_batch AND state = 'PROPOSED';
    UPDATE people.matric_batch SET state = 'CANCELLED', cancelled_by = p_actor, cancelled_at = now(), cancel_reason = btrim(p_reason), students = 0, valid = 0, conflicts = 0 WHERE id = p_batch;
END $function$
;

CREATE OR REPLACE FUNCTION people.matric_batch_issue(p_batch uuid, p_actor uuid, p_office text)
 RETURNS TABLE(issued integer, username_updates integer, run_ref text)
 LANGUAGE plpgsql
AS $function$
DECLARE b people.matric_batch; v record; r record; s people.student; c record; v_taken text; v_n int := 0; v_prev text; mf people.matric_format;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'READY_FOR_ISSUANCE' THEN RAISE EXCEPTION 'only a batch marked READY FOR ISSUANCE is issued; this one is %', lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514', HINT = 'Review the numbers and mark the batch ready first.'; END IF;
    SELECT * INTO mf FROM people.matric_format WHERE id = 'UNIVERSITY';
    IF mf.separate_duties AND p_actor IS NOT NULL AND (b.prepared_by = p_actor OR b.reviewed_by = p_actor) THEN
        RAISE EXCEPTION 'the officer who prepared or reviewed a batch does not issue it' USING ERRCODE = '23514', HINT = 'Another authorised officer issues the batch, or the Registry turns the separation off under Matriculation number format.';
    END IF;
    SELECT * INTO v FROM people.matric_batch_validate(p_batch);
    IF v.conflicts > 0 THEN RAISE EXCEPTION 'cannot issue matriculation numbers: % record(s) require attention', v.conflicts USING ERRCODE = '23514', HINT = 'Resolve every conflict before final issuance; nothing was issued.'; END IF;
    IF v.students = 0 THEN RAISE EXCEPTION 'the batch has no student on it' USING ERRCODE = '23514'; END IF;
    -- the run of this reference, so the register reads the batch like any run
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (b.id, b.ref, b.session, 0);
    FOR r IN SELECT br.* FROM people.matric_batch_row br WHERE br.batch_id = p_batch AND br.state = 'PROPOSED' ORDER BY br.series_code, br.sequence LOOP
        SELECT * INTO s FROM people.student WHERE id = r.student_id FOR UPDATE;
        -- verified again at the moment of issue; any failure rolls the whole batch back
        IF s.matric_no IS NOT NULL THEN RAISE EXCEPTION '% already holds %; nothing was issued', s.surname, s.matric_no USING ERRCODE = '23514'; END IF;
        IF s.status <> 'ADMITTED' THEN RAISE EXCEPTION '% is %, not admitted; nothing was issued', s.surname, lower(s.status) USING ERRCODE = '23514'; END IF;
        v_taken := people.matric_number_taken(r.proposed_no, r.series_code, r.sequence, r.id);
        IF v_taken IS NOT NULL THEN RAISE EXCEPTION '% for %; nothing was issued', v_taken, r.proposed_no USING ERRCODE = '23505'; END IF;
        PERFORM 1 FROM people.matric_series WHERE code = r.series_code FOR UPDATE;
        INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, run_id, issued_by, actor_office, reason)
        VALUES (r.student_id, r.proposed_no, r.series_code, r.sequence, coalesce(r.components, '{}'::jsonb) || jsonb_build_object('batch', b.ref, 'edited', r.edited),
                b.id, p_actor, p_office, 'Matriculation batch ' || b.ref || CASE WHEN r.edited THEN ' (number corrected: ' || coalesce(r.edit_reason, '') || ')' ELSE '' END);
        UPDATE people.matric_series SET last_issued = greatest(last_issued, r.sequence), updated_at = now() WHERE code = r.series_code;
        v_prev := coalesce(s.jamb_reg_no, s.admission_no);   -- the JAMB number is the sign-in an entrant has used since application (V282)
        UPDATE people.student SET matric_no = r.proposed_no, matriculated_at = now(), matriculation_run = b.id, status = 'ACTIVE' WHERE id = s.id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), s.id, s.status, 'ACTIVE', b.ref, current_date, 'Matriculated (batch ' || b.ref || ')');
        INSERT INTO people.student_username_change (student_id, previous_username, new_username, reason, changed_by, office, batch_id)
        VALUES (s.id, v_prev, r.proposed_no, 'Student matriculated', p_actor, p_office, b.id);
        UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Issued' WHERE row_id = r.id AND released_at IS NULL;
        UPDATE people.matric_batch_row SET state = 'ISSUED', issued_no = r.proposed_no, issued_at = now() WHERE id = r.id;
        PERFORM people.matric_tell(s.id, r.proposed_no);
        v_n := v_n + 1;
    END LOOP;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = b.id;
    UPDATE people.matric_batch SET state = 'ISSUED', issued_by = p_actor, issued_office = p_office, issued_at = now(), issued = v_n, run_id = b.id WHERE id = p_batch;
    RETURN QUERY SELECT v_n, v_n, b.ref;
END $function$
;

CREATE OR REPLACE FUNCTION platform.set_institution_profile(p_name text, p_short text, p_motto text, p_address text, p_city text, p_state text, p_country text, p_phone text, p_email text, p_website text, p_footer text, p_generated_by boolean, p_page_numbers boolean, p_date_format text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'INSTITUTION_NAME_REQUIRED: the University''s name cannot be blank' USING ERRCODE = 'check_violation';
    END IF;
    IF p_short IS NULL OR btrim(p_short) = '' THEN
        RAISE EXCEPTION 'INSTITUTION_SHORT_NAME_REQUIRED: the short name cannot be blank' USING ERRCODE = 'check_violation';
    END IF;
    IF nullif(btrim(coalesce(p_email, '')), '') IS NOT NULL AND btrim(p_email) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'INSTITUTION_EMAIL_INVALID: % is not an e-mail address', btrim(p_email) USING ERRCODE = 'check_violation';
    END IF;
    IF nullif(btrim(coalesce(p_website, '')), '') IS NOT NULL AND btrim(p_website) !~ '^(https?://)?[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/.*)?$' THEN
        RAISE EXCEPTION 'INSTITUTION_WEBSITE_INVALID: % is not a web address', btrim(p_website) USING ERRCODE = 'check_violation';
    END IF;
    IF coalesce(p_date_format, 'LONG') NOT IN ('LONG', 'SHORT') THEN
        RAISE EXCEPTION 'INSTITUTION_DATE_FORMAT: the date style is LONG (04 October 2026) or SHORT (04/10/2026)' USING ERRCODE = 'check_violation';
    END IF;
    UPDATE platform.institution_profile
       SET name = btrim(p_name), short_name = btrim(p_short), motto = nullif(btrim(coalesce(p_motto, '')), ''),
           address = nullif(btrim(coalesce(p_address, '')), ''), city = nullif(btrim(coalesce(p_city, '')), ''),
           state = nullif(btrim(coalesce(p_state, '')), ''), country = nullif(btrim(coalesce(p_country, '')), ''),
           phone = nullif(btrim(coalesce(p_phone, '')), ''), email = nullif(btrim(coalesce(p_email, '')), ''),
           website = nullif(btrim(coalesce(p_website, '')), ''), footer_note = nullif(btrim(coalesce(p_footer, '')), ''),
           show_generated_by = coalesce(p_generated_by, true), show_page_numbers = coalesce(p_page_numbers, true),
           date_format = coalesce(p_date_format, 'LONG'), updated_at = now(), updated_by = v_actor
     WHERE id;
    RETURN platform.institution();
END $function$
;

CREATE OR REPLACE FUNCTION policy.clears(p_purpose text, p_instalments_paid integer, p_paid_in_full boolean, p_has_arrears boolean, p_at date DEFAULT CURRENT_DATE, p_scope text DEFAULT 'UNIVERSITY'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_version uuid;
    v_at      text;
    v_arrears boolean;
BEGIN
    v_version := policy.in_force('clearance', p_scope, p_at);

    -- FAIL CLOSED. This is the branch D-Q4 is sitting in.
    IF v_version IS NULL THEN
        RAISE EXCEPTION
            'no clearance scheme in force for % on %',
            p_scope, p_at
        USING ERRCODE = '23514',
              HINT = 'The Bursar records which services each fee instalment unlocks; until then, clearance refuses.';
    END IF;

    SELECT r.releases_at, s.arrears_block_all INTO v_at, v_arrears
      FROM policy.clearance_rule r
      JOIN policy.clearance_scheme s ON s.version_id = r.version_id
     WHERE r.version_id = v_version AND r.purpose = p_purpose;

    IF v_at IS NULL THEN
        RAISE EXCEPTION 'no clearance rule for purpose % in the scheme in force', p_purpose
        USING ERRCODE = '23514';
    END IF;

    IF v_at = 'NEVER_GATED' THEN
        RETURN true;                       -- not withheld for money at all
    END IF;

    IF v_arrears AND p_has_arrears THEN
        RETURN false;                      -- a balance carried forward blocks everything
    END IF;

    RETURN CASE v_at
        WHEN 'INSTALMENT_1' THEN p_instalments_paid >= 1
        WHEN 'INSTALMENT_2' THEN p_instalments_paid >= 2
        WHEN 'PAID_IN_FULL' THEN p_paid_in_full
    END;
END $function$
;

CREATE OR REPLACE FUNCTION policy.assert_scheme_complete(p_version uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE missing text;
BEGIN
    SELECT string_agg(p.code, ', ' ORDER BY p.code) INTO missing
      FROM ref.clearance_purpose p
     WHERE NOT EXISTS (SELECT 1 FROM policy.clearance_rule r
                        WHERE r.version_id = p_version AND r.purpose = p.code);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'incomplete clearance scheme — no rule for: %', missing
        USING ERRCODE = '23514',
              HINT = 'Name every purpose in ref.clearance_purpose.';
    END IF;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.assert_row_matches_batch()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE k text;
BEGIN
    SELECT list_kind INTO k FROM admissions.caps_batch WHERE id = NEW.batch_id;
    IF (k = 'UTME' AND NEW.entry_mode <> 'UTME')
       OR (k = 'DIRECT_ENTRY' AND NEW.entry_mode = 'UTME') THEN
        RAISE EXCEPTION
            'a % row in a batch declared %', NEW.entry_mode, k
        USING ERRCODE = '23514',
              HINT = 'The list kind is declared before the file is read; upload the file that matches it.';
    END IF;
    -- A UTME candidate without a score is a row from the wrong file that
    -- happens to carry the right word.
    IF k = 'UTME' AND NEW.aggregate IS NULL THEN
        RAISE EXCEPTION 'a UTME row with no aggregate' USING ERRCODE = '23514';
    END IF;
    IF k = 'DIRECT_ENTRY' AND NEW.aggregate IS NOT NULL THEN
        RAISE EXCEPTION 'a Direct Entry row carrying an aggregate of %', NEW.aggregate
        USING ERRCODE = '23514',
              HINT = 'Direct Entry candidates do not sit the UTME. An aggregate '
                     'here means the two files have been mixed.';
    END IF;
    RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.withdraw_batch(p_batch uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    b admissions.caps_batch;
    v_actor uuid;
    v_on_register bigint;
BEGIN
    SELECT * INTO b FROM admissions.caps_batch WHERE id = p_batch;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503';
    END IF;
    IF b.withdrawn_at IS NOT NULL THEN
        RETURN 'already withdrawn';           -- idempotent, not an error
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'a list is withdrawn for a reason, and none was given'
        USING ERRCODE = '23514',
              HINT = 'Say why the list is withdrawn: the wrong file, the wrong kind of list, the wrong session.';
    END IF;

    SELECT count(*) INTO v_on_register
      FROM people.student s
      JOIN admissions.candidate c ON c.id = s.candidate_id
      JOIN admissions.caps_row r ON r.id = c.admitted_from
     WHERE r.batch_id = p_batch;
    IF v_on_register > 0 THEN
        RAISE EXCEPTION '% student(s) admitted from this list already hold an admission number', v_on_register
        USING ERRCODE = '23514',
              HINT = 'Change each student''s status on the register, one at a time with its reason.';
    END IF;

    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'a list is withdrawn by a person, and none is acting'
        USING ERRCODE = '23514', HINT = 'The request must carry the person and office withdrawing the list.';
    END IF;

    -- offers that stood only on this list are withdrawn with it
    UPDATE admissions.candidate c
       SET offer_state = 'WITHDRAWN'
      FROM admissions.caps_row r
     WHERE r.id = c.admitted_from AND r.batch_id = p_batch
       AND c.offer_state NOT IN ('DECLINED','LAPSED','WITHDRAWN');

    UPDATE admissions.caps_row SET withdrawn = true WHERE batch_id = p_batch;
    UPDATE admissions.caps_batch
       SET withdrawn_at = now(), withdrawn_by = v_actor, withdrawn_reason = btrim(p_reason)
     WHERE id = p_batch;
    RETURN 'withdrawn';
END $function$
;

CREATE OR REPLACE FUNCTION admissions.commit_batch(p_batch uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    b admissions.caps_batch;
    outstanding text;
    blocking bigint;
    pending bigint;
BEGIN
    SELECT * INTO b FROM admissions.caps_batch WHERE id = p_batch;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503';
    END IF;
    IF b.committed_at IS NOT NULL THEN
        RETURN 'already committed';           -- idempotent, not an error
    END IF;
    IF b.withdrawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the list was withdrawn on %: %', b.withdrawn_at::date, b.withdrawn_reason
        USING ERRCODE = '23514',
              HINT = 'A withdrawn list is never committed. Load the right list and commit that.';
    END IF;

    -- admitted people not yet registered do not block; they are recorded, not hidden
    SELECT coalesce(sum(x.n) FILTER (WHERE x.finding = 'On the CAPS list, no candidate record'), 0)
      INTO pending
      FROM admissions.reconcile(b.session) x;

    -- the dangerous findings still block
    SELECT string_agg(x.finding || ' (' || x.n || ')', '; '), coalesce(sum(x.n), 0)
      INTO outstanding, blocking
      FROM admissions.reconcile(b.session) x
     WHERE x.n > 0 AND x.finding <> 'On the CAPS list, no candidate record';

    IF blocking > 0 THEN
        RAISE EXCEPTION 'the admission list does not reconcile: %', outstanding
        USING ERRCODE = '23514',
              HINT = 'These are errors, not candidates yet to register: a ghost admission, a programme that differs from CAPS, a course code the University does not run, or a Direct Entry candidate at the wrong level. Fix or withdraw those rows; candidates not yet registered do not block the commit.';
    END IF;

    -- the count of admitted-but-not-registered is recorded on the batch (committed_pending),
    -- not in the return value, which stays 'committed' as every caller and test expects
    UPDATE admissions.caps_batch SET committed_at = now(), committed_pending = pending WHERE id = p_batch;
    RETURN 'committed';
END $function$
;

CREATE OR REPLACE FUNCTION registration.support_drop(p_student uuid, p_session text, p_semester integer, p_offering uuid, p_override boolean, p_by uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE k record; v_rules jsonb := '[]'::jsonb; v_hard text; v_soft text[] := '{}'; r registration.course_registration;
BEGIN
    FOR k IN SELECT * FROM registration.support_drop_checks(p_student, p_session, p_semester, p_offering) LOOP
        v_rules := v_rules || jsonb_build_array(jsonb_build_object('ord', k.ord, 'rule', k.rule, 'label', k.label, 'passed', k.passed,
                                                                   'overridable', k.overridable, 'advisory', k.advisory, 'message', k.message));
        IF NOT k.passed AND NOT k.overridable AND v_hard IS NULL THEN v_hard := k.message; END IF;
        IF NOT k.passed AND k.overridable THEN v_soft := v_soft || k.message; END IF;
    END LOOP;
    IF v_hard IS NOT NULL THEN
        RAISE EXCEPTION 'REG_RULE: %', v_hard USING ERRCODE = '23514',
            HINT = 'A support override does not set this rule aside.';
    END IF;
    IF cardinality(v_soft) > 0 AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', array_to_string(v_soft, ' ') USING ERRCODE = '23514',
            HINT = 'After a genuine portal fault, an agent with the support override may set it aside on the student''s ticket, with the reason.';
    END IF;
    IF cardinality(v_soft) > 0 AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF cardinality(v_soft) = 0 AND r.status IN ('SUBMITTED', 'APPROVED') THEN
        PERFORM registration.student_drop(p_student, p_session, p_semester, p_offering);
    ELSE
        -- a draft's course, or the add/drop gate set aside on the record: marked DROPPED, as the engine's drop marks it — never deleted
        UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = r.id AND offering_id = p_offering;
    END IF;
    UPDATE registration.entry SET support_override_at = NULL, support_override_by = NULL, support_override_reason = NULL
     WHERE registration_id = r.id AND offering_id = p_offering AND status = 'DROPPED' AND support_override_at IS NOT NULL;
    RETURN jsonb_build_object('registrationId', r.id, 'status', r.status, 'units', registration.units_of(r.id), 'overridden', cardinality(v_soft) > 0,
                              'normalRule', nullif(array_to_string(v_soft, ' '), ''), 'rules', v_rules);
END $function$
;

CREATE OR REPLACE FUNCTION registration.support_submit(p_student uuid, p_session text, p_semester integer, p_override boolean, p_by uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; v_closed text; s people.student; v_gate text; v_out text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT coalesce(s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'), false) THEN
        RAISE EXCEPTION 'REG_RULE: a student who is % does not register', lower(coalesce(s.status, 'unknown')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_RULE: no registration for % semester % to submit', p_session, p_semester USING ERRCODE = '23514'; END IF;
    v_closed := registration.semester_closed(p_student, p_session, p_semester);   -- V380: by the student's calendar
    IF v_closed IS NOT NULL THEN
        RAISE EXCEPTION 'REG_RULE: the semester is %; its registrations are not changed', v_closed USING ERRCODE = '23514';
    END IF;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    IF v_gate IS NOT NULL AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', v_gate USING ERRCODE = '23514',
            HINT = 'After a portal fault, an agent with the support override may set the window aside on the student''s ticket.';
    END IF;
    IF v_gate IS NOT NULL AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    v_out := registration.student_submit(r.id);   -- the fees, the GST gate, the unit range and the probation ceiling: the engine's
    RETURN jsonb_build_object('registrationId', r.id, 'status', (SELECT x.status FROM registration.course_registration x WHERE x.id = r.id), 'result', v_out,
                              'units', registration.units_of(r.id), 'overridden', v_gate IS NOT NULL, 'normalRule', v_gate);
END $function$
;

COMMIT;
