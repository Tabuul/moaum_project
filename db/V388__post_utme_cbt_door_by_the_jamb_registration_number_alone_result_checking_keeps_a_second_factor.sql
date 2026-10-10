-- V388: the Post-UTME CBT door opens on the JAMB registration number alone.
--
-- V385 asked a candidate at /post-utme/cbt for the JAMB registration number and a second factor the examination named (the
-- application number by default). The University's decision: the candidate signs in to the examination with the JAMB registration
-- number only. That is a new factor value, NONE, made the default of every Post-UTME examination and set on the ones already made;
-- the other factors stay available, examination by examination.
--
-- What it does not change: the Director's POST_UTME_CBT window still gates the door; the sitting is still judged on the record
-- (submitted application, programme screened by examination, no score yet); one active attempt per candidate and the examination's
-- second-screen rule stand; a wrong JAMB number still counts against the connection; the candidate still sees no score.
-- The result-checking page shows a score, so it keeps a second factor: when the examination's door asks for nothing more than the
-- JAMB number, the result check asks for the application number (admissions.putme_result_factor).

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V388: the Post-UTME CBT door asks for the JAMB registration number alone', true);

-- ── 1 · the factor NONE: the JAMB registration number alone; the default, and the setting of the examinations already made ──
ALTER TABLE assessment.cbt_exam DROP CONSTRAINT ck_cbt_exam_putme_verify;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT ck_cbt_exam_putme_verify
    CHECK (putme_verify IN ('NONE', 'APPLICATION_NO', 'SLIP_TOKEN', 'PHONE', 'DATE_OF_BIRTH'));
ALTER TABLE assessment.cbt_exam ALTER COLUMN putme_verify SET DEFAULT 'NONE';
UPDATE assessment.cbt_exam SET putme_verify = 'NONE' WHERE office = 'POST_UTME' AND putme_verify <> 'NONE';
COMMENT ON COLUMN assessment.cbt_exam.putme_verify IS 'V385, V388: what a Post-UTME candidate gives at the examination door: the JAMB registration number alone (NONE, the default), or with the application number, the screening slip token, the phone they registered with, or the date of birth on record.';

-- ── 2 · the settings accept NONE ──
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
END $$;

-- ── 3 · the door: the application a JAMB registration number names, with the factor asked for ──
/* the application a JAMB registration number and a factor name, for the session's Post-UTME — or NULL, with no word on which part failed.
   NONE: the JAMB registration number alone. Otherwise the application number, the screening slip's token, the phone registered with, or
   the date of birth on the attachment the Academic Office uploaded (yyyy-mm-dd). */
CREATE FUNCTION admissions.putme_verify_as(p_session text, p_jamb text, p_proof text, p_kind text)
RETURNS uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE a record; v_kind text := upper(coalesce(p_kind, 'APPLICATION_NO')); v_proof text := upper(regexp_replace(coalesce(p_proof, ''), '\s+', '', 'g')); v_ok boolean := false;
BEGIN
    IF coalesce(btrim(p_jamb), '') = '' THEN RETURN NULL; END IF;
    IF v_kind <> 'NONE' AND v_proof = '' THEN RETURN NULL; END IF;
    SELECT ap.id, ap.application_no, ap.putme_token, ac.phone, c.id AS candidate_id INTO a
      FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id JOIN admissions.applicant_account ac ON ac.id = ap.account_id
     WHERE ap.session = p_session AND c.jamb_key = upper(btrim(p_jamb)) AND c.entry_mode <> 'CCE';
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_ok := CASE v_kind
              WHEN 'NONE'           THEN true
              WHEN 'APPLICATION_NO' THEN upper(regexp_replace(coalesce(a.application_no, ''), '\s+', '', 'g')) = v_proof
              WHEN 'SLIP_TOKEN'     THEN upper(coalesce(a.putme_token, '')) = v_proof
              WHEN 'PHONE'          THEN regexp_replace(coalesce(a.phone, ''), '\D', '', 'g') <> '' AND right(regexp_replace(coalesce(a.phone, ''), '\D', '', 'g'), 10) = right(regexp_replace(v_proof, '\D', '', 'g'), 10)
              WHEN 'DATE_OF_BIRTH'  THEN EXISTS (SELECT 1 FROM admissions.attachment x WHERE x.candidate_id = a.candidate_id AND x.kind = 'DATE_OF_BIRTH'
                                                    AND regexp_replace(coalesce(x.payload ->> 'dob', ''), '\D', '', 'g') = regexp_replace(v_proof, '\D', '', 'g')
                                                    AND regexp_replace(v_proof, '\D', '', 'g') <> '')
              ELSE false END;
    RETURN CASE WHEN v_ok THEN a.id END;
END $$;
COMMENT ON FUNCTION admissions.putme_verify_as(text, text, text, text) IS 'V388: the Post-UTME application a JAMB registration number names, with the factor asked for (NONE: the JAMB number alone), or NULL — never which part was wrong.';

/* the factor the examination door asks for: the open (or latest published) Post-UTME examination's; NONE when none is published */
CREATE OR REPLACE FUNCTION admissions.putme_cbt_factor(p_session text)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT e.putme_verify FROM assessment.cbt_exam e
                      WHERE e.office = 'POST_UTME' AND e.putme_session = p_session AND e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED')
                      ORDER BY (assessment.cbt_live_state(e) = 'OPEN') DESC, e.starts_at DESC NULLS LAST LIMIT 1), 'NONE')
$$;
COMMENT ON FUNCTION admissions.putme_cbt_factor(text) IS 'V385, V388: what the Post-UTME examination door asks for beside the JAMB registration number: the open (or latest published) examination''s setting; NONE (the JAMB number alone) when none is published.';

CREATE OR REPLACE FUNCTION admissions.putme_cbt_verify(p_session text, p_jamb text, p_proof text)
RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT admissions.putme_verify_as(p_session, p_jamb, p_proof, admissions.putme_cbt_factor(p_session))
$$;
COMMENT ON FUNCTION admissions.putme_cbt_verify(text, text, text) IS 'V385, V388: the Post-UTME application the examination door''s answer names (the JAMB registration number, with the examination''s factor when it asks for one), or NULL — never which part was wrong.';

-- ── 4 · the result-checking page shows a score, so it always asks for a second factor ──
/* the examination's factor; the application number when the examination's door asks for the JAMB number alone */
CREATE FUNCTION admissions.putme_result_factor(p_session text)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN f = 'NONE' THEN 'APPLICATION_NO' ELSE f END FROM (SELECT admissions.putme_cbt_factor(p_session) AS f) x
$$;
COMMENT ON FUNCTION admissions.putme_result_factor(text) IS 'V388: what the Post-UTME result-checking page asks for beside the JAMB registration number: the examination''s factor, or the application number when the examination asks for the JAMB number alone. A score is never read on the JAMB number alone.';

CREATE OR REPLACE FUNCTION admissions.putme_result_check(p_session text, p_jamb text, p_proof text)
RETURNS TABLE(outcome text, candidate_name text, jamb_reg_no text, application_no text, programme text, score numeric, released_at timestamptz)
LANGUAGE plpgsql STABLE AS $$
DECLARE w record; v_app uuid; a admissions.application; c admissions.candidate;
BEGIN
    SELECT * INTO w FROM policy.window_state('POST_UTME_RESULT_CHECKING', p_session, NULL);
    IF w.state <> 'OPEN' THEN RETURN QUERY SELECT 'CLOSED'::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::numeric, NULL::timestamptz; RETURN; END IF;
    v_app := admissions.putme_verify_as(p_session, p_jamb, p_proof, admissions.putme_result_factor(p_session));
    IF v_app IS NULL THEN RETURN QUERY SELECT 'NOT_VERIFIED'::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::numeric, NULL::timestamptz; RETURN; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = v_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    IF a.score_released_at IS NULL OR a.screening_score IS NULL THEN
        RETURN QUERY SELECT 'NOT_RELEASED'::text, upper(c.surname) || ', ' || c.other_names, c.jamb_reg_no, a.application_no, c.programme, NULL::numeric, NULL::timestamptz; RETURN;
    END IF;
    RETURN QUERY SELECT 'RELEASED'::text, upper(c.surname) || ', ' || c.other_names, c.jamb_reg_no, a.application_no, c.programme, a.screening_score, a.score_released_at;
END $$;
COMMENT ON FUNCTION admissions.putme_result_check(text, text, text) IS 'V385, V388: what a candidate reads on the result-checking page: CLOSED while the Director''s window is not open, NOT_VERIFIED when the JAMB number and the result factor (admissions.putme_result_factor) do not name an applicant, NOT_RELEASED until the Academic Office releases the scores, else the released score.';
