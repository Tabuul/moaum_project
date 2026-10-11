-- ═══════════════════════════════════════
-- V392 — the database's own refusals and hints say less
--
--   The follow-up to e1e7d671 for the texts the database writes itself: 31
--   refusals and hints in 26 functions lose the clause that explained how the
--   system works ("nothing is assumed to be free", "money of no known source
--   is never written to a wallet", "the reconciliation record carries what the
--   portal made of it"). Each function is restated from its definition as V391
--   left it, and only those string literals differ: every error code, ERRCODE,
--   condition, signature and grant stands, and a remedy keeps what the person
--   must do and the office that does it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V392: the database''s refusals and hints shortened', true);

CREATE OR REPLACE FUNCTION finance.new_gst_reference(p_student uuid, p_session text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE e record;
BEGIN
    SELECT * INTO e FROM finance.gst_entitlement(p_student, p_session);
    IF e.state = 'PAID' THEN
        RAISE EXCEPTION 'GST_ALREADY_PAID: the GST fee for % is paid in full (receipt %)', p_session, coalesce(e.receipt_no, e.reference) USING ERRCODE = '23514',
            HINT = 'It is paid once and covers both GST and EPS.';
    END IF;
    IF NOT e.required THEN
        RAISE EXCEPTION 'GST_NOT_REQUIRED: no GST or EPS course requires the GST fee of you in %', p_session USING ERRCODE = '23514',
            HINT = 'The fee is owed for a GST or EPS course offered to your programme at your level, or a GST/EPS carryover. If a course is missing, ask ICT Support.';
    END IF;
    IF e.stated AND e.fee = 0 THEN
        RAISE EXCEPTION 'GST_EXEMPT: the GST fee stated for you in % is nothing; there is nothing to pay', p_session USING ERRCODE = '23514';
    END IF;
    IF NOT e.stated THEN
        RAISE EXCEPTION 'GST_FEE_NOT_STATED: no GST fee is stated for %', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the GST fee for the session before it is paid.';
    END IF;
    IF e.open_reference IS NOT NULL THEN RETURN e.open_reference; END IF;
    RETURN finance.new_purpose_reference(p_student, p_session, e.fee - e.paid, 'GST fee ' || p_session);
END $function$
;

CREATE OR REPLACE FUNCTION admissions.cce_register(p_jamb text, p_dob date, p_email text, p_phone text, p_hash text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE f record; l admissions.cce_candidate; v_candidate uuid := gen_random_uuid(); v_account uuid := gen_random_uuid(); v_app uuid := gen_random_uuid();
        v_no text; v_terms record; fee record;
BEGIN
    SELECT * INTO f FROM admissions.cce_lookup(p_jamb, p_dob);
    IF f.state = 'nomatch' THEN
        RAISE EXCEPTION 'CCE_NOT_LISTED: that JAMB number and date of birth are not together on the CCE list' USING ERRCODE = '23514',
            HINT = 'Type the JAMB number exactly as JAMB gave it and your date of birth as on the list. If both are right, ask the Centre for Continuing Education.';
    ELSIF f.state = 'registered' THEN
        RAISE EXCEPTION 'CCE_REGISTERED: an application account already exists for this JAMB number' USING ERRCODE = '23514',
            HINT = 'Sign in with the email and password you chose; a forgotten password is reset from the sign-in page.';
    ELSIF f.state = 'closed' THEN
        RAISE EXCEPTION 'CCE_PROGRAMME_CLOSED: the Centre is not admitting into % at present', f.programme USING ERRCODE = '23514';
    END IF;
    IF coalesce(f.window_state, 'CLOSED') <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: the CCE application for % is %', f.session, lower(coalesce(f.window_state, 'closed')) USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email) USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;
    SELECT * INTO l FROM admissions.cce_candidate WHERE id = f.cce_candidate_id FOR UPDATE;
    SELECT * INTO v_terms FROM ref.programme_route_terms(l.programme_code, 'CCE');
    -- the candidate's JAMB number is the list's, as the list's key reads it (the candidate's own key is generated from it)
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, cce_candidate_id)
    VALUES (v_candidate, l.session, l.jamb_key, l.surname, btrim(l.first_name || coalesce(' ' || l.middle_name, '')),
            (SELECT p.name FROM ref.programme p WHERE p.code = l.programme_code), 'CCE', v_terms.entry_level, 'PROPOSED', l.id);
    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, l.session, v_candidate, l.jamb_key, btrim(p_email), p_phone, p_hash);
    v_no := 'APP/' || substr(l.session, 3, 2) || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', l.session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (v_app, v_account, v_candidate, l.session, v_no);
    INSERT INTO admissions.cce_review (application_id, state) VALUES (v_app, 'DRAFT');
    -- what the list gave is carried into the form; the applicant confirms or completes it
    INSERT INTO admissions.screening_answer (application_id, field, value)
    SELECT v_app, x.field, x.value FROM (VALUES ('date_of_birth', l.date_of_birth::text), ('state_of_origin', l.state_of_origin), ('lga', l.lga),
                                                ('nationality', l.nationality), ('mobile', coalesce(p_phone, l.phone)), ('personal_email', btrim(p_email))) x(field, value)
     WHERE nullif(btrim(coalesce(x.value, '')), '') IS NOT NULL;
    -- an application fee stated as nothing is nothing to pay
    SELECT * INTO fee FROM admissions.route_fee_rule(l.session, 'CCE');
    IF coalesce(fee.application_fee, -1) + coalesce(fee.portal_charge, 0) = 0 THEN
        UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = v_app;
    END IF;
    PERFORM admissions.cce_log(v_app, 'REGISTERED', NULL, 'DRAFT', 'The application account was opened from the CCE list');
    RETURN v_account;
END $function$
;

CREATE OR REPLACE FUNCTION people.matriculate(p_session text)
 RETURNS TABLE(run_ref text, issued integer)
 LANGUAGE plpgsql
AS $function$
DECLARE v_missing text; v_run uuid := gen_random_uuid(); v_ref text; v_n int := 0; r record; v_no text;
BEGIN
    SELECT string_agg(f.name, ', ' ORDER BY f.name) INTO v_missing
      FROM ref.faculty f
     WHERE EXISTS (SELECT 1 FROM people.faculty_list_rows(p_session, f.code))
       AND NOT EXISTS (SELECT 1 FROM people.faculty_list l WHERE l.session = p_session AND l.faculty_code = f.code AND l.state = 'CONFIRMED');
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'the run cannot start: % has not confirmed its list', v_missing USING ERRCODE = 'check_violation',
              HINT = 'Confirm every faculty''s list first.';
    END IF;
    v_ref := 'MAT/' || substr(p_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', p_session)::text, 3, '0');
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (v_run, v_ref, p_session, 0);
    FOR r IN
        SELECT x.student_id, x.dept_code
          FROM ref.faculty f
          CROSS JOIN LATERAL people.faculty_list_rows(p_session, f.code) x
         WHERE x.query_reason IS NULL
           AND (SELECT fp.paid_in_full FROM finance.position(x.student_id, p_session) fp)
         ORDER BY x.dept_code, x.surname, x.other_names
    LOOP
        v_no := people.next_matric(r.student_id, v_run, 'Matriculation run ' || v_ref);
        UPDATE people.student SET matric_no = v_no, matriculated_at = now(), matriculation_run = v_run, status = 'ACTIVE' WHERE id = r.student_id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), r.student_id, 'ADMITTED', 'ACTIVE', v_ref, current_date, 'Matriculated');
        PERFORM people.matric_tell(r.student_id, v_no);
        v_n := v_n + 1;
    END LOOP;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'nobody on a confirmed list has both paid the fees and registered for %; there is nothing to matriculate', p_session USING ERRCODE = 'no_data_found';
    END IF;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = v_run;
    RETURN QUERY SELECT v_ref, v_n;
END $function$
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
        RAISE EXCEPTION 'CBT_SETTING: a JUPEB examination is the Board''s; a CBT result goes into the JUPEB continuous assessment, or nowhere' USING ERRCODE = '23514';
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

CREATE OR REPLACE FUNCTION helpdesk.transition(p_ticket uuid, p_to text, p_actor_kind text, p_actor uuid, p_actor_name text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE t helpdesk.ticket; v_from text; ok boolean := false; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    v_from := t.status;
    IF p_to = v_from THEN RAISE EXCEPTION 'the ticket is already %', lower(replace(p_to, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF p_actor_kind = 'AGENT' THEN
        ok := (v_from, p_to) IN (('SUBMITTED','OPENED'), ('OPENED','IN_PROGRESS'), ('REOPENED','IN_PROGRESS'), ('RESOLVED','CLOSED'),
                                 ('IN_PROGRESS','WAITING_FOR_STUDENT'), ('WAITING_FOR_STUDENT','IN_PROGRESS'), ('WAITING_FOR_OFFICE','IN_PROGRESS'))
              OR (p_to = 'REOPENED' AND v_from IN ('RESOLVED','CLOSED'))
              OR (p_to = 'CLOSED' AND v_from <> 'CLOSED');
        IF p_to = 'CLOSED' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'a closure by the desk records its reason' USING ERRCODE = '23514', HINT = 'Say why the ticket is closed.';
        END IF;
        IF p_to = 'WAITING_FOR_STUDENT' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'HELPDESK_REASON_REQUIRED: waiting on the requester says what is needed from them' USING ERRCODE = '23514', HINT = 'Say what the requester should send or confirm.';
        END IF;
    ELSIF p_actor_kind = 'REQUESTER' THEN
        ok := (v_from = 'RESOLVED' AND p_to IN ('CLOSED','REOPENED'))
              OR (p_to = 'CLOSED' AND v_from IN ('SUBMITTED','OPENED','IN_PROGRESS','REOPENED','WAITING_FOR_STUDENT','WAITING_FOR_OFFICE'));
    ELSIF p_actor_kind = 'SYSTEM' THEN
        ok := (v_from = 'RESOLVED' AND p_to = 'CLOSED') OR (v_from = 'WAITING_FOR_STUDENT' AND p_to = 'IN_PROGRESS');
    END IF;
    IF p_to = 'REOPENED' AND v_reason IS NULL THEN
        RAISE EXCEPTION 'reopening a ticket says what is still wrong' USING ERRCODE = '23514', HINT = 'Say why the ticket is reopened, in a line.';
    END IF;
    IF NOT ok THEN
        RAISE EXCEPTION 'a ticket does not go from % to % this way', lower(replace(v_from, '_', ' ')), lower(replace(p_to, '_', ' '))
            USING ERRCODE = '23514', HINT = 'Submitted → opened → in progress → resolved → closed; a resolved or closed ticket is reopened with a reason.';
    END IF;
    UPDATE helpdesk.ticket SET
        status = p_to,
        opened_at = CASE WHEN p_to IN ('OPENED','REOPENED') AND opened_at IS NULL THEN now() ELSE opened_at END,
        opened_by = CASE WHEN p_to IN ('OPENED','REOPENED') AND opened_by IS NULL THEN p_actor ELSE opened_by END,
        in_progress_at = CASE WHEN p_to = 'IN_PROGRESS' THEN now() ELSE in_progress_at END,
        first_response_at = CASE WHEN p_to IN ('IN_PROGRESS','WAITING_FOR_STUDENT') AND first_response_at IS NULL AND p_actor_kind = 'AGENT' THEN now() ELSE first_response_at END,
        waiting_since = CASE WHEN p_to IN ('WAITING_FOR_STUDENT','WAITING_FOR_OFFICE') THEN now() ELSE NULL END,
        escalated_office = CASE WHEN v_from = 'WAITING_FOR_OFFICE' THEN NULL ELSE escalated_office END,
        resolved_at = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolved_at END,
        resolved_by = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolved_by END,
        resolution_summary = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolution_summary END,
        resolution_details = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolution_details END,
        closed_at = CASE WHEN p_to = 'CLOSED' THEN now() ELSE NULL END,
        closed_by = CASE WHEN p_to = 'CLOSED' THEN p_actor ELSE NULL END,
        closed_by_kind = CASE WHEN p_to = 'CLOSED' THEN p_actor_kind ELSE NULL END,
        closure_reason = CASE WHEN p_to = 'CLOSED' THEN coalesce(v_reason, CASE WHEN p_actor_kind = 'REQUESTER' AND v_from = 'RESOLVED' THEN 'The requester confirmed the resolution' WHEN p_actor_kind = 'REQUESTER' THEN 'Withdrawn by the requester' END) ELSE NULL END,
        reopen_count = CASE WHEN p_to = 'REOPENED' THEN reopen_count + 1 ELSE reopen_count END
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, p_actor_kind, p_actor, p_actor_name,
        CASE WHEN p_to = 'OPENED' THEN 'OPENED' WHEN p_to = 'REOPENED' THEN 'REOPENED' WHEN p_to = 'CLOSED' THEN 'CLOSED' WHEN p_to = 'WAITING_FOR_STUDENT' THEN 'WAITING' ELSE 'STATUS_CHANGED' END,
        v_from, p_to,
        coalesce(v_reason, CASE WHEN p_to = 'CLOSED' AND p_actor_kind = 'REQUESTER' AND v_from = 'RESOLVED' THEN 'The requester confirmed the resolution'
                                WHEN p_to = 'CLOSED' AND p_actor_kind = 'REQUESTER' THEN 'Withdrawn by the requester'
                                WHEN p_to = 'IN_PROGRESS' AND p_actor_kind = 'SYSTEM' THEN 'The requester replied' END));
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
        RAISE EXCEPTION 'PAY_NOT_CONFIRMED: reference % is not confirmed; an entitlement follows only a confirmed payment', r.reference USING ERRCODE = '23514',
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

CREATE OR REPLACE FUNCTION finance.legacy_gst_resolve(p_payment uuid, p_action text, p_student uuid, p_reason text)
 RETURNS finance.legacy_gst_reconciliation
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; i finance.legacy_gst_import; v_act text := upper(btrim(coalesce(p_action, ''))); v_other uuid; v_id uuid; v_ref text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is resolved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_PAYMENT_NOT_FOUND: no such old-portal payment' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment FOR UPDATE;
    SELECT * INTO i FROM finance.legacy_gst_import WHERE id = rc.import_id;
    IF rc.status = 'RECONCILED' THEN RAISE EXCEPTION 'LEGACY_ALREADY_RECONCILED: this payment is already on the ledger as %', (SELECT reference FROM finance.payment_reference WHERE id = rc.payment_reference_id) USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'LEGACY_REASON_REQUIRED: resolving a payment names its reason' USING ERRCODE = '23514'; END IF;

    IF v_act = 'MATCH' THEN
        IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: name the current student' USING ERRCODE = '23514'; END IF;
        -- the identifiers on the row must not point at somebody else: ownership is never moved by guesswork
        IF (p.matric_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = p.matric_no AND s.id <> p_student))
           OR (p.jamb_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.jamb_reg_no) = p.jamb_no AND s.id <> p_student)) THEN
            RAISE EXCEPTION 'LEGACY_IDENTIFIER_CONFLICT: the matriculation or JAMB number on the row belongs to another student' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'MATCHED', reason_code = NULL, reason = NULL, student_id = p_student, match_method = 'MANUAL', match_confidence = 'MANUAL',
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
        PERFORM finance.legacy_gst_validate_one(p_payment);
        -- the old id, once resolved by hand, is on the crosswalk for the next file
        IF p.source_student_id IS NOT NULL AND p.source_student_id !~ '^[0-9a-f]{8}-' THEN
            INSERT INTO finance.legacy_student_crosswalk (legacy_student_id, student_id, note, set_by)
            VALUES (upper(p.source_student_id), p_student, 'set when ' || coalesce(p.source_reference, p.source_transaction_id) || ' was resolved: ' || btrim(p_reason), v_actor)
            ON CONFLICT (legacy_student_id) DO NOTHING;
        END IF;
    ELSIF v_act = 'RECONCILE' THEN
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        IF rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW') THEN RAISE EXCEPTION 'LEGACY_STATE: a % payment is not reconciled by hand', lower(replace(rc.status, '_', ' ')) USING ERRCODE = '23514'; END IF;
        IF p.normalized_status <> 'SUCCESS' THEN RAISE EXCEPTION 'LEGACY_NOT_SUCCESSFUL: the old portal did not record this payment as successful; it cannot establish an entitlement' USING ERRCODE = '23514'; END IF;
        IF p.session IS NULL OR p.amount IS NULL OR p.amount <= 0 THEN RAISE EXCEPTION 'LEGACY_INCOMPLETE: the row needs a session and an amount' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.source_reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))) THEN
            RAISE EXCEPTION 'LEGACY_DUPLICATE: the student already holds a confirmed GST payment for %', p.session USING ERRCODE = '23514';
        END IF;
        v_ref := finance.legacy_gst_ledger_reference(p);
        IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN RAISE EXCEPTION 'LEGACY_DUPLICATE: a ledger row already carries the old-portal reference %', v_ref USING ERRCODE = '23514'; END IF;
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (rc.student_id, p.session, v_ref, 'GST fee ' || p.session, p.amount, coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), v_actor, 'Legacy', 'LEG-' || v_ref,
                'Old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', reconciled by hand under ' || i.reference || ': ' || btrim(p_reason))
        RETURNING id INTO v_id;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = NULL, reason = NULL, payment_reference_id = v_id, reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office,
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'RELABEL' THEN
        -- the money is already on the ledger as school fees from the old portal: it was for the GST fee
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        SELECT r.id INTO v_other FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%' AND r.amount = p.amount
         ORDER BY abs(extract(epoch FROM (r.confirmed_at - coalesce(p.paid_at, r.confirmed_at)))) LIMIT 1;
        IF v_other IS NULL THEN RAISE EXCEPTION 'LEGACY_NOTHING_TO_RELABEL: no old-portal school-fees row of that amount is on the ledger for the student and session' USING ERRCODE = '23514'; END IF;
        UPDATE finance.payment_reference
           SET purpose = 'GST fee ' || p.session,
               note = coalesce(note || ' · ', '') || 'relabelled from school fees: old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', under ' || i.reference || ': ' || btrim(p_reason)
         WHERE id = v_other;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = 'RELABELLED', reason = 'the old-portal school-fees row was relabelled as the GST fee', payment_reference_id = v_other,
               reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office, resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'REJECT' THEN
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'REJECTED', reason_code = 'REJECTED_BY_OFFICER', reason = btrim(p_reason), resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSE
        RAISE EXCEPTION 'LEGACY_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    RETURN rc;
END $function$
;

CREATE OR REPLACE FUNCTION finance.legacy_nelfund_resolve(p_payment uuid, p_action text, p_student uuid, p_reason text)
 RETURNS finance.legacy_nelfund_reconciliation
 LANGUAGE plpgsql
AS $function$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p finance.legacy_nelfund_payment; rc finance.legacy_nelfund_reconciliation; v_act text := upper(btrim(coalesce(p_action, '')));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is resolved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM finance.legacy_nelfund_payment WHERE id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_PAYMENT_NOT_FOUND: no such old-portal payment' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM finance.legacy_nelfund_reconciliation WHERE payment_id = p_payment FOR UPDATE;
    IF rc.status = 'POSTED' THEN RAISE EXCEPTION 'LEGACY_ALREADY_POSTED: this payment is already on a wallet' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'LEGACY_REASON_REQUIRED: resolving a payment names its reason' USING ERRCODE = '23514'; END IF;
    IF v_act = 'MATCH' THEN
        IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: name the current student' USING ERRCODE = '23514'; END IF;
        IF (p.matric_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = p.matric_no AND s.id <> p_student))
           OR (p.jamb_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.jamb_reg_no) = p.jamb_no AND s.id <> p_student)) THEN
            RAISE EXCEPTION 'LEGACY_IDENTIFIER_CONFLICT: the matriculation or JAMB number on the row belongs to another student' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.legacy_nelfund_reconciliation
           SET status = 'MATCHED', reason_code = NULL, reason = NULL, student_id = p_student, match_method = 'MANUAL', match_confidence = 'MANUAL',
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
        PERFORM finance.legacy_nelfund_validate_one(p_payment);
        IF p.source_student_id IS NOT NULL AND p.source_student_id !~ '^[0-9a-f]{8}-' THEN
            INSERT INTO finance.legacy_student_crosswalk (legacy_student_id, student_id, source_system, note, set_by)
            VALUES (upper(p.source_student_id), p_student, 'OLD_NELFUND_PORTAL', 'set when ' || coalesce(p.source_reference, p.source_transaction_id) || ' was resolved: ' || btrim(p_reason), v_actor)
            ON CONFLICT (legacy_student_id) DO NOTHING;
        END IF;
    ELSIF v_act = 'REJECT' THEN
        UPDATE finance.legacy_nelfund_reconciliation
           SET status = 'REJECTED', reason_code = 'REJECTED_BY_OFFICER', reason = btrim(p_reason), resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSE
        RAISE EXCEPTION 'LEGACY_ACTION_UNKNOWN: an old-portal payment is matched or rejected' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rc FROM finance.legacy_nelfund_reconciliation WHERE payment_id = p_payment;
    RETURN rc;
END $function$
;

CREATE OR REPLACE FUNCTION assessment.cbt_results_action(p_exam uuid, p_action text)
 RETURNS assessment.cbt_exam
 LANGUAGE plpgsql
AS $function$
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
            RAISE EXCEPTION 'CBT_PUTME_NOT_PUBLISHED_HERE: Post-UTME scores are released by the Academic Office through result checking, not here' USING ERRCODE = '23514',
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
END $function$
;

CREATE OR REPLACE FUNCTION people.deferment_refuse(p_student uuid, p_session text, p_semester integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('moaum.deferment_override', true) = 'on' THEN RETURN; END IF;
    IF people.deferment_covers(p_student, p_session, p_semester) THEN
        RAISE EXCEPTION 'REGISTRATION UNAVAILABLE: your deferment for % is approved; you cannot register for the deferred period',
            p_session || coalesce(' semester ' || p_semester, '')
            USING ERRCODE = '23514', HINT = 'Registration resumes in your return session, or when the Registry lifts a cancelled deferment.';
    END IF;
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
        RAISE EXCEPTION 'REG_RULE: the semester is %; its registrations are history and are not changed', v_closed USING ERRCODE = '23514';
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

CREATE OR REPLACE FUNCTION finance.legacy_nelfund_payment_written_once()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'LEGACY_PAYMENT_WRITTEN_ONCE: an old-portal payment is staged once and never corrected in place' USING ERRCODE = '23514';
END $function$
;

CREATE OR REPLACE FUNCTION finance.legacy_gst_payment_written_once()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'LEGACY_PAYMENT_WRITTEN_ONCE: an old-portal payment is staged once and never corrected in place' USING ERRCODE = '23514';
END $function$
;

CREATE OR REPLACE FUNCTION admissions.recommend_programme_change(p_app uuid, p_to text, p_reason text, p_note text, p_actor uuid, p_office text, p_override boolean, p_override_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; rs admissions.programme_change_reason; f admissions.screening_form; r record;
        v_run uuid; v_id uuid; v_from text; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rs FROM admissions.programme_change_reason WHERE code = p_reason AND active;
    IF rs.code IS NULL THEN RAISE EXCEPTION 'a change of programme carries one of the configured reasons' USING ERRCODE = '23514'; END IF;
    IF rs.requires_note AND v_note IS NULL THEN RAISE EXCEPTION 'the reason "%" is described in a note', rs.label USING ERRCODE = '23514'; END IF;
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    -- after the Board's decision the change is a screening act: while the screening is open, or after an unsuccessful one, once
    IF a.decision_released_at IS NOT NULL AND (f.application_id IS NULL OR f.state NOT IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
        RAISE EXCEPTION 'the Board''s decision on this application has been released; the programme is changed only during the University''s screening'
            USING ERRCODE = '23514', HINT = 'Correct an error in the admission on Programme Changes.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q0 WHERE q0.application_id = p_app AND q0.state = 'APPROVED' AND f.decided_at IS NOT NULL AND q0.decided_at >= f.decided_at) THEN
        RAISE EXCEPTION 'a change of programme has already been approved after the screening' USING ERRCODE = '23514',
              HINT = 'An error found in the admission since is corrected on Programme Changes.';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = p_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', p_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = p_to THEN RAISE EXCEPTION 'that is the programme the candidate holds' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already recommended and awaits approval' USING ERRCODE = '23514';
    END IF;
    -- the engine, read again now against the session's settings, never from a stale screen
    v_run := admissions.eligibility_current(p_app, p_actor);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, p_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        IF NOT coalesce(p_override, false) THEN
            RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
                  HINT = 'Recommend a programme the candidate is eligible for; an override is reserved to the Registrar.';
        END IF;
        IF nullif(btrim(coalesce(p_override_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an eligibility override carries its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request,
                                                     requested_by_kind, requested_by, note, reason_code, recommended_office, override, override_reason, original_eligibility, screening_state_at_request)
    VALUES (p_app, c.id, a.session, v_from, c.programme, p_to, g.name, v_run, r.result, 'OFFICE', p_actor, v_note, rs.code, p_office,
            r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING'), nullif(btrim(coalesce(p_override_reason, '')), ''), r.result, f.state)
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'PROGRAMME_CHANGE_RECOMMENDED', p_to, r.result,
        'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || coalesce(' · ' || v_note, '') || ' · by the ' || coalesce(p_office, 'office')
        || CASE WHEN r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN ' · OVERRIDE: ' || coalesce(p_override_reason, '') ELSE '' END);
    IF f.application_id IS NOT NULL THEN
        PERFORM admissions.screening_log(p_app, 'PROGRAMME_CHANGE_RECOMMENDED', 'From ' || c.programme || ' to ' || g.name || ' · ' || rs.label || ' · awaiting approval');
    END IF;
    PERFORM admissions.notify_applicant(p_app, 'Your programme change is under review',
        'During the University''s screening the Academic Office has recommended that your admission be changed from ' || c.programme || ' to ' || g.name
        || ' (' || rs.label || '). The change takes effect only when it is approved; you will be told. Your acceptance fee, already paid, is not paid again.',
        'MOAUM: a change of your programme to ' || g.name || ' is under review; you will be told when it is decided.');
    PERFORM admissions.tell_office('academic', 'A programme change awaits approval',
        'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || '): the ' || coalesce(p_office, 'office') || ' recommends ' || g.name || ' in place of ' || c.programme
        || ' · ' || rs.label || ' · the engine finds them ' || lower(replace(r.result, '_', ' ')) || CASE WHEN coalesce(p_override, false) THEN ' (override)' ELSE '' END, p_app);
    RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION registration.student_submit(p_registration uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; lim policy.level_limit; units int; st record; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT', 'RETURNED') THEN RETURN 'already ' || lower(r.status); END IF;
    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared
    IF NOT finance.fee_stated(r.student_id, r.session) THEN
        SELECT p.name AS programme, s.current_level AS level INTO st
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = r.student_id;
        RAISE EXCEPTION 'REG_FEES_NOT_STATED: the school fees of % at % level for % are not stated yet, so they cannot be paid or cleared',
            coalesce(st.programme, 'the programme'), st.level, r.session
            USING ERRCODE = '23514',
            HINT = 'Course registration opens when the Bursary states the session''s school fees on Fee Setup and they are paid.';
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
    UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = p_registration;
    RETURN 'submitted';
END $function$
;

CREATE OR REPLACE FUNCTION registration.support_add(p_student uuid, p_session text, p_semester integer, p_offering uuid, p_override boolean, p_by uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE k record; v_rules jsonb := '[]'::jsonb; v_hard text; v_soft text[] := '{}'; r registration.course_registration; v_reg uuid; v_restored boolean;
        m record; o catalogue.offering; c catalogue.course; s people.student; v_type text; v_units int; v_status text; v_choice uuid[];
BEGIN
    FOR k IN SELECT * FROM registration.support_add_checks(p_student, p_session, p_semester, p_offering) LOOP
        v_rules := v_rules || jsonb_build_array(jsonb_build_object('ord', k.ord, 'rule', k.rule, 'label', k.label, 'passed', k.passed,
                                                                   'overridable', k.overridable, 'advisory', k.advisory, 'message', k.message));
        IF NOT k.passed AND NOT k.overridable AND v_hard IS NULL THEN v_hard := k.message; END IF;
        IF NOT k.passed AND k.overridable THEN v_soft := v_soft || k.message; END IF;
    END LOOP;
    IF v_hard IS NOT NULL THEN
        RAISE EXCEPTION 'REG_RULE: %', v_hard USING ERRCODE = '23514',
            HINT = 'A support override does not set this rule aside; escalate the ticket to the office that owns it.';
    END IF;
    IF cardinality(v_soft) > 0 AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', array_to_string(v_soft, ' ') USING ERRCODE = '23514',
            HINT = 'After a genuine portal fault, an agent with the support override may set it aside on the student''s ticket, with the reason.';
    END IF;
    IF cardinality(v_soft) > 0 AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    v_restored := r.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering AND e.status = 'DROPPED');
    IF cardinality(v_soft) = 0 THEN
        -- nothing in the way: exactly what the student's own form or add/drop does
        IF r.id IS NULL OR r.status IN ('DRAFT', 'RETURNED') THEN
            v_reg := registration.student_draft(p_student, p_session, p_semester);
            v_choice := ARRAY(SELECT e.offering_id FROM registration.entry e
                               WHERE e.registration_id = v_reg AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED') AND e.status <> 'DROPPED' AND e.support_override_at IS NULL);
            PERFORM registration.student_choose(v_reg, v_choice || p_offering);
            IF NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = v_reg AND e.offering_id = p_offering AND e.status <> 'DROPPED') THEN
                RAISE EXCEPTION 'REG_RULE: the engine did not place the course on the draft' USING ERRCODE = '23514';
            END IF;
        ELSE
            PERFORM registration.student_add(p_student, p_session, p_semester, p_offering);
            v_reg := r.id;
        END IF;
    ELSE
        -- the window or the menu set aside, on the record: the engine's draft, the engine's entry, the override named on it
        v_reg := registration.student_draft(p_student, p_session, p_semester);
        SELECT * INTO r FROM registration.course_registration WHERE id = v_reg;
        SELECT * INTO s FROM people.student WHERE id = p_student;
        SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
        SELECT * INTO c FROM catalogue.course WHERE code = o.course_code;
        SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) x WHERE x.offering_id = p_offering LIMIT 1;
        v_units := coalesce(m.units, o.units, c.units);
        v_type := CASE WHEN m.offering_id IS NOT NULL AND m.carryover THEN CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END
                       WHEN c.kind = 'GST' OR m.basis = 'GST' THEN 'GST'
                       WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                       WHEN c.kind = 'Elective' OR m.basis = 'Elective' THEN 'ELECTIVE'
                       WHEN m.offering_id IS NULL AND c.dept_code IS DISTINCT FROM (SELECT p.dept_code FROM ref.programme p WHERE p.code = s.programme_code) THEN 'BORROWED'
                       ELSE 'CURRENT' END;
        v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, support_override_at, support_override_by, support_override_reason)
        VALUES (v_reg, p_offering, v_units, v_type, v_status, now(), p_by, btrim(p_reason))
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = EXCLUDED.status, units = EXCLUDED.units, entry_type = EXCLUDED.entry_type,
            support_override_at = EXCLUDED.support_override_at, support_override_by = EXCLUDED.support_override_by,
            support_override_reason = EXCLUDED.support_override_reason;
    END IF;
    RETURN jsonb_build_object('registrationId', v_reg, 'status', (SELECT x.status FROM registration.course_registration x WHERE x.id = v_reg),
                              'units', registration.units_of(v_reg), 'overridden', cardinality(v_soft) > 0, 'restored', v_restored,
                              'normalRule', nullif(array_to_string(v_soft, ' '), ''), 'rules', v_rules);
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
            HINT = 'The registration engine''s rule stands; a support override does not set it aside.';
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

CREATE OR REPLACE FUNCTION admissions.register_applicant(p_session text, p_jamb_key text, p_email text, p_phone text, p_hash text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE key text := upper(btrim(p_jamb_key)); f record; v_candidate uuid; v_account uuid := gen_random_uuid();
        v_app uuid := gen_random_uuid(); v_no text; v_yy text := substr(p_session, 3, 2);
BEGIN
    SELECT * INTO f FROM admissions.applicant_lookup(p_session, key);
    IF f.state = 'nolist' THEN
        RAISE EXCEPTION 'nobody can be verified: no admission list is loaded for %', p_session
        USING ERRCODE = '23514', HINT = 'Try again once the Academic Office has loaded the JAMB admission list.';
    ELSIF f.state = 'none' THEN
        RAISE EXCEPTION 'the number % is not on the list JAMB sent the University for %', key, p_session
        USING ERRCODE = '23514', HINT = 'A digit may be wrong, the University may not have been chosen on CAPS, or the tranche has not reached us yet. Do not travel to the campus over this.';
    ELSIF f.state = 'registered' THEN
        RAISE EXCEPTION 'an application account already exists for %', key
        USING ERRCODE = '23505', HINT = 'Sign in with the email and password you chose. A second account would invalidate both.';
    ELSIF f.state = 'closed' THEN
        RAISE EXCEPTION 'the University is not admitting into % this session', coalesce(f.programme, f.programme_code)
        USING ERRCODE = '23514', HINT = 'Change your programme with JAMB to one the University admits into this session.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email)
        USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;

    SELECT c.id INTO v_candidate FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = key;
    IF v_candidate IS NULL THEN
        v_candidate := gen_random_uuid();
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
        VALUES (v_candidate, p_session, key, f.surname, f.other_names, coalesce(f.programme, f.programme_code),
                CASE WHEN f.entry_mode IN ('UTME','DIRECT_ENTRY','TRANSFER') THEN f.entry_mode ELSE 'UTME' END,
                CASE WHEN f.entry_mode = 'UTME' THEN 100 ELSE 200 END, 'PROPOSED', f.row_id);
    END IF;

    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, p_session, v_candidate, key, btrim(p_email), p_phone, p_hash);

    v_no := 'APP/' || v_yy || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no)
    VALUES (v_app, v_account, v_candidate, p_session, v_no);
    RETURN v_account;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean; v_try int;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    IF v_cce AND p_kind = 'CHECKING' THEN
        RAISE EXCEPTION 'CCE_NO_CHECKING_FEE: a CCE applicant reads the published outcome without a checking fee' USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'CHECKING' THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already paid; nothing more is owed' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_CLOSED: admission status checking is closed' USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce THEN
        -- V379: the CCE fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, 0::numeric AS checking_fee INTO fee FROM admissions.route_fee_rule(a.session, 'CCE') r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION 'CCE_FEE_NOT_STATED: the Bursary has not stated the CCE % fee for %', lower(p_kind), a.session USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    -- V390: the four random digits may repeat a reference another application drew (the last six digits of an application
    -- number are the session's running number, shared across sessions); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
                 || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
        VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free % reference was found for % in fifty draws', lower(p_kind), a.application_no USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$
;

CREATE OR REPLACE FUNCTION admissions.sign_undertaking(p_app uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
        RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
    END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
        RAISE EXCEPTION 'there is nothing to accept yet' USING ERRCODE = '23514', HINT = 'This opens when the Admissions Board publishes an offer.';
    END IF;
    IF a.declined_at IS NOT NULL THEN
        RAISE EXCEPTION 'this offer was declined on %', a.declined_at::date USING ERRCODE = '23514', HINT = 'A declined offer is not reinstated.';
    END IF;
    UPDATE admissions.application SET undertaking_at = coalesce(undertaking_at, now()) WHERE id = p_app;
    PERFORM admissions.settle_acceptance(p_app);
    RETURN CASE WHEN (SELECT accepted_at FROM admissions.application WHERE id = p_app) IS NULL THEN 'undertaking signed' ELSE 'accepted' END;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.decline_offer(p_app uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
        RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
    END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
        RAISE EXCEPTION 'there is no offer to decline' USING ERRCODE = '23514';
    END IF;
    IF a.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION 'the offer was accepted on %; withdrawing is a change of status on the register', a.accepted_at::date USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.application SET declined_at = coalesce(declined_at, now()) WHERE id = p_app;
    UPDATE admissions.candidate SET offer_state = 'DECLINED' WHERE id = a.candidate_id AND offer_state IN ('PROPOSED','ADMITTED');
    RETURN 'declined';
END $function$
;

CREATE OR REPLACE FUNCTION finance.credit_wallet(p_student uuid, p_session text, p_amount numeric, p_reason text, p_source text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_src text := nullif(upper(btrim(coalesce(p_source, ''))), '');
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a wallet credit is made by a person' USING ERRCODE = '23514';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a wallet credit is for an amount above zero' USING ERRCODE = '23514';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'a wallet credit names its reason' USING ERRCODE = '23514',
            HINT = 'Say why the wallet is credited; the student sees it on the statement.';
    END IF;
    IF v_src IS NULL THEN
        RAISE EXCEPTION 'WALLET_SOURCE_REQUIRED: a wallet credit names the source the money came from' USING ERRCODE = '23514',
            HINT = 'NELFUND, a scholarship, a sponsor — choose the source from the settings, or add it first.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.funding_source WHERE code = v_src AND active) THEN
        RAISE EXCEPTION 'no funding source is coded %', v_src USING ERRCODE = '23503',
            HINT = 'Choose a source from the settings, or add it first.';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code)
    VALUES (p_student, p_session, 'CREDIT', p_amount, v_src, 'Bursary credit: ' || btrim(p_reason), v_src)
    RETURNING id INTO v_id;
    RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION admissions.screening_save(p_app uuid, p_answers jsonb, p_institutions jsonb, p_olevel jsonb, p_membership text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$

DECLARE f admissions.screening_form; r record; n int := 0;

BEGIN

    f := admissions.screening_open(p_app);

    -- V280: the applicant enters only the schools attended with their dates (and a membership) while the screening is awaited;
    -- an answer or an O'Level change is taken only as the one correction an officer asked for; nothing after the decision
    IF (p_answers IS NOT NULL OR p_olevel IS NOT NULL) AND f.state <> 'CORRECTION_REQUIRED' THEN
        RAISE EXCEPTION 'SCREENING NOT FILLED: nothing is entered unless an officer asks for a correction' USING ERRCODE = '23514', HINT = 'Wait for the outcome of the screening.';
    END IF;
    IF f.state IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN

        RAISE EXCEPTION 'the screening is % and nothing more is entered', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514', HINT = 'An officer returns it for correction if something must change.';

    END IF;

    IF p_answers IS NOT NULL THEN

        FOR r IN SELECT key, value FROM jsonb_each_text(p_answers) LOOP

            IF NOT EXISTS (SELECT 1 FROM ref.biodata_field bf WHERE bf.field = r.key) THEN CONTINUE; END IF;

            INSERT INTO admissions.screening_answer (application_id, field, value) VALUES (p_app, r.key, left(btrim(coalesce(r.value, '')), 400))

            ON CONFLICT (application_id, field) DO UPDATE SET value = EXCLUDED.value;

        END LOOP;

    END IF;

    IF p_institutions IS NOT NULL THEN

        UPDATE admissions.screening_institution SET active = false WHERE application_id = p_app AND active;

        FOR r IN SELECT x.* FROM jsonb_to_recordset(p_institutions) AS x(name text, from_year int, to_year int, certificate text, award_year int) LOOP

            IF nullif(btrim(coalesce(r.name, '')), '') IS NULL THEN CONTINUE; END IF;

            n := n + 1;

            INSERT INTO admissions.screening_institution (application_id, ord, name, from_year, to_year, certificate, award_year, active)

            VALUES (p_app, n, left(btrim(r.name), 200), r.from_year, r.to_year, nullif(left(btrim(coalesce(r.certificate, '')), 100), ''), r.award_year, true)

            ON CONFLICT (application_id, ord) DO UPDATE SET name = EXCLUDED.name, from_year = EXCLUDED.from_year, to_year = EXCLUDED.to_year, certificate = EXCLUDED.certificate, award_year = EXCLUDED.award_year, active = true;

        END LOOP;

    END IF;

    IF p_olevel IS NOT NULL THEN

        UPDATE admissions.screening_olevel SET active = false WHERE application_id = p_app AND active;

        n := 0;

        FOR r IN SELECT x.* FROM jsonb_to_recordset(p_olevel) AS x(exam_body text, exam_number text, exam_year int, subject text, grade text) LOOP

            IF nullif(btrim(coalesce(r.subject, '')), '') IS NULL OR nullif(btrim(coalesce(r.grade, '')), '') IS NULL THEN CONTINUE; END IF;

            n := n + 1;

            INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_number, exam_year, subject, grade, active)

            VALUES (p_app, n, CASE WHEN upper(btrim(coalesce(r.exam_body, ''))) IN ('WAEC', 'NECO', 'NABTEB') THEN upper(btrim(r.exam_body)) ELSE 'OTHER' END,

                    nullif(left(btrim(coalesce(r.exam_number, '')), 40), ''), r.exam_year, left(btrim(r.subject), 80), upper(left(btrim(r.grade), 4)), true)

            ON CONFLICT (application_id, ord) DO UPDATE SET exam_body = EXCLUDED.exam_body, exam_number = EXCLUDED.exam_number, exam_year = EXCLUDED.exam_year, subject = EXCLUDED.subject, grade = EXCLUDED.grade, active = true;

        END LOOP;

    END IF;

    UPDATE admissions.screening_form SET membership = coalesce(nullif(btrim(coalesce(p_membership, '')), ''), membership), updated_at = now() WHERE application_id = p_app;

    PERFORM admissions.screening_log(p_app, 'SAVED', 'Draft saved');

END $function$
;

CREATE OR REPLACE FUNCTION catalogue.course_code_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_twin text; v_base text; v_alias text;
BEGIN
    IF TG_OP = 'INSERT' AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = NEW.code) THEN RETURN NEW; END IF;   -- an upsert of a course held
    IF TG_OP = 'UPDATE' AND NEW.code = OLD.code THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = NEW.code AND id <> NEW.id) THEN RETURN NEW; END IF;   -- the code is taken: the key says so
    SELECT a.course_code INTO v_alias FROM catalogue.course_alias a WHERE a.alias_code = NEW.code;
    IF v_alias IS NOT NULL THEN
        RAISE EXCEPTION 'COURSE_CODE_MERGED: % was merged into %; the pool holds that course once', NEW.code, v_alias USING ERRCODE = '23514';
    END IF;
    SELECT c.code INTO v_twin FROM catalogue.course c
     WHERE catalogue.code_key(c.code) = catalogue.code_key(NEW.code) AND c.code <> NEW.code AND (TG_OP = 'INSERT' OR c.id <> NEW.id) LIMIT 1;
    IF v_twin IS NOT NULL THEN
        RAISE EXCEPTION 'COURSE_DUPLICATE_CODE: % is % written differently; the pool holds a course once', NEW.code, v_twin USING ERRCODE = '23514';
    END IF;
    v_base := catalogue.session_copy_base(NEW.code);
    IF v_base IS NOT NULL THEN
        SELECT c.code INTO v_twin FROM catalogue.course c WHERE catalogue.code_key(c.code) = catalogue.code_key(v_base) AND (TG_OP = 'INSERT' OR c.id <> NEW.id) LIMIT 1;
        IF v_twin IS NOT NULL THEN
            RAISE EXCEPTION 'COURSE_SESSION_COPY: % copies % for a session; a course is held once', NEW.code, v_twin
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $function$
;

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
            HINT = 'A released decision is not quietly changed; the Board minutes a new one.';
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

CREATE OR REPLACE FUNCTION policy.session_same_start()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE other text;
BEGIN
    IF NEW.state = 'CANCELLED' THEN RETURN NEW; END IF;
    SELECT s.name INTO other FROM policy.academic_session s
     WHERE s.starts_on = NEW.starts_on AND s.name <> NEW.name AND s.state <> 'CANCELLED' LIMIT 1;
    IF other IS NOT NULL THEN
        RAISE EXCEPTION 'SESSION_SAME_START: % cannot begin on %, the day % begins; give it another day',
            NEW.name, to_char(NEW.starts_on, 'FMDD Mon YYYY'), other USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $function$
;

COMMIT;
