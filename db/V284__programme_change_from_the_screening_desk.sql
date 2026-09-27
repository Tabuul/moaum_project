-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V284 — the screening officer changes the programme on the engine's word
--
--   A candidate admitted to one programme is found, during the University's screening, not to
--   meet its requirements. The screening desk now asks the eligibility engine (V266) the
--   question the officer has: which programmes does this candidate actually qualify for under
--   the session's admission settings? The engine's current run already holds the answer — the
--   applied programme's verdict with every check, and every alternative evaluated with its
--   checks — so the desk shows it, and the officer recommends one of the eligible programmes
--   with a configured reason (admissions.programme_change_reason). The recommendation is a
--   programme_change_request from the OFFICE, allowed while the screening is open or after an
--   unsuccessful one; the approval re-reads eligibility at that moment, changes the candidate's
--   and the student's programme (the original stays on the request and the trail), records the
--   screening as SUCCESSFUL on the new programme, generates the screening forms for it, keeps
--   the acceptance fee paid once, opens school fees and tells the applicant. An authorised
--   override (Registrar, Deputy Registrar, DVC, VC) may recommend a programme the engine refuses;
--   the engine's verdict, the reason and the officer stay on the request and the log.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V284: programme change from the screening desk on the engine''s word', true);

-- ── 1 · the configured reasons ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admissions.programme_change_reason (
    code          text PRIMARY KEY,
    label         text NOT NULL,
    ord           integer NOT NULL DEFAULT 0,
    active        boolean NOT NULL DEFAULT true,
    requires_note boolean NOT NULL DEFAULT false
);
COMMENT ON TABLE admissions.programme_change_reason IS 'The reasons an officer may give for recommending a change of programme (V284); OTHER requires a description. Deactivated, never deleted.';
INSERT INTO admissions.programme_change_reason (code, label, ord, requires_note) VALUES
    ('OLEVEL_NOT_MET',     'O''Level requirement not satisfied', 1, false),
    ('UTME_COMBINATION',   'UTME combination mismatch',          2, false),
    ('SCREENING_DECISION', 'Screening decision',                 3, false),
    ('ADMISSION_POLICY',   'University admission policy',        4, false),
    ('SUITABILITY',        'Programme suitability',              5, false),
    ('OTHER',              'Other (describe)',                   9, true)
ON CONFLICT (code) DO NOTHING;
GRANT SELECT ON admissions.programme_change_reason TO app_student;

-- ── 2 · what the request records ─────────────────────────────────────────────────────────────
ALTER TABLE admissions.programme_change_request
    ADD COLUMN IF NOT EXISTS reason_code text REFERENCES admissions.programme_change_reason(code),
    ADD COLUMN IF NOT EXISTS recommended_office text,
    ADD COLUMN IF NOT EXISTS override boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS override_reason text,
    ADD COLUMN IF NOT EXISTS original_eligibility text,
    ADD COLUMN IF NOT EXISTS screening_state_at_request text;
COMMENT ON COLUMN admissions.programme_change_request.override IS 'V284: recommended by an authorised office although the engine found the candidate not eligible; the verdict stays in original_eligibility and the reason in override_reason.';

-- ── 3 · the officer's recommendation ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.recommend_programme_change(p_app uuid, p_to text, p_reason text, p_note text, p_actor uuid, p_office text, p_override boolean, p_override_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
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
            USING ERRCODE = '23514', HINT = 'A screening already successful is not reopened by a change of programme.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q0 WHERE q0.application_id = p_app AND q0.state = 'APPROVED' AND f.decided_at IS NOT NULL AND q0.decided_at >= f.decided_at) THEN
        RAISE EXCEPTION 'a change of programme has already been approved after the screening' USING ERRCODE = '23514';
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
                  HINT = 'Only a programme the engine finds the candidate eligible for on the session''s admission settings is recommended; an override is reserved to the Registrar.';
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
END $fn$;
COMMENT ON FUNCTION admissions.recommend_programme_change(uuid, text, text, text, uuid, text, boolean, text) IS
  'The screening officer''s recommendation (V284): a configured reason, the engine read again now, an authorised override recorded as such; awaits approval.';

-- ── 4 · the approval: the screening path, the override honoured, the screening closed successful on the new programme ──
CREATE OR REPLACE FUNCTION admissions.decide_programme_change(p_req uuid, p_decision text, p_note text, p_actor uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $fn$
DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; r record; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_prog text; v_fac text; v_dept text;
BEGIN
    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the request is already %', lower(q.state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;
    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;
    IF p_decision = 'REJECT' THEN
        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decision_note = v_note WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_REJECTED', q.to_programme_code, NULL, v_note);
        PERFORM admissions.notify_applicant(q.application_id, 'Your request to change programme was not approved', 'Your request to move to ' || q.to_programme || ' was not approved by the Admissions Office. Reason: ' || v_note || ' Your application for ' || q.from_programme || ' stands as it was.', NULL);
        RETURN 'REJECTED';
    ELSIF p_decision = 'APPROVE' THEN
        -- after the release a change is a screening decision (V269, V284): while the screening is open, or after an unsuccessful one
        IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
            RAISE EXCEPTION 'the Board''s decision has been released; the programme is not changed under it' USING ERRCODE = '23514';
        END IF;
        -- eligibility read again at the moment of decision
        SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') AND NOT q.override THEN
            RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';
        END IF;
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
            -- the authorised override (V284): approved with the engine's verdict on the record, never hidden
            PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'ELIGIBILITY_OVERRIDE_APPLIED', q.to_programme_code, r.result, 'Approved by override: ' || coalesce(q.override_reason, '') || ' · engine: ' || array_to_string(r.reasons, '; '));
        END IF;
        UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;
        -- the student on the register, not yet matriculated, follows the programme (V269); the original stays on the request and the trail
        UPDATE people.student SET programme_code = q.to_programme_code WHERE candidate_id = c.id AND matric_no IS NULL;
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
            -- the change is the screening's decision (V284): the record is screened successful on the new programme, the acceptance
            -- fee paid once stands, the forms are generated for the new programme, school fees open
            UPDATE admissions.screening_form
               SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = 'academic', decision_reason = NULL, returned_note = NULL,
                   remarks = concat_ws(' · ', nullif(remarks, ''), 'Programme changed from ' || q.from_programme || ' to ' || q.to_programme || ' on the approval of the change request'
                             || coalesce(' (' || (SELECT rs.label FROM admissions.programme_change_reason rs WHERE rs.code = q.reason_code) || ')', '')),
                   updated_at = now()
             WHERE application_id = a.id;
            UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = a.id;
            PERFORM admissions.screening_log(a.id, 'PROGRAMME_CHANGED', 'From ' || q.from_programme || ' to ' || q.to_programme || ' on the approval of the change request; screened successful on the new programme; acceptance fee already paid, not charged again');
            SELECT p.name, f.name, d.name INTO v_prog, v_fac, v_dept FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = q.to_programme_code;
            PERFORM admissions.notify_applicant(a.id, 'Programme change approved — next step: school fees',
                'Your programme change has been approved.' || E'\n\nPrevious programme: ' || q.from_programme || E'\nNew programme: ' || coalesce(v_prog, q.to_programme)
                || coalesce(E'\nFaculty: ' || v_fac, '') || coalesce(E'\nDepartment: ' || v_dept, '')
                || E'\n\nYour screening is recorded as successful on the new programme and your screening forms are available on your dashboard. Your acceptance fee, already paid, remains valid and is not paid again. Next step: pay your school fees on the portal.',
                'MOAUM: your change to ' || q.to_programme || ' is approved. Acceptance fee not charged again; next, school fees.');
        END IF;
        UPDATE admissions.programme_change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decision_note = v_note, eligibility_at_decision = r.result WHERE id = q.id;
        -- an approved change after an unsuccessful screening opens school fees: the register follows it (V278)
        PERFORM admissions.register_when_due(a.id);
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'SUCCESSFUL' AND f.decided_at >= now() - interval '1 minute') THEN
            PERFORM admissions.issue_screening_forms(a.id);
        END IF;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_APPROVED', q.to_programme_code, r.result, 'From ' || q.from_programme || ' to ' || q.to_programme || coalesce(' · ' || v_note, ''));
        PERFORM admissions.evaluate_application(q.application_id, 'PROGRAMME_CHANGE', p_actor);
        PERFORM admissions.notify_applicant(q.application_id, 'Your programme has been changed to ' || q.to_programme,
            'The Admissions Office has approved your request: your application is now for ' || q.to_programme || ' (' || r.result || ' on the current admission policy). This is not an offer of admission; the Admissions Board decides in the normal way.' || coalesce(' Note: ' || v_note, ''),
            'MOAUM: your application is now for ' || q.to_programme || '. This is not yet an offer of admission.');
        RETURN 'APPROVED';
    ELSE
        RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';
    END IF;
END $fn$;

-- ── 5 · the status and the tracker name the change recommended during the screening ─────────
CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $fn$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN RETURN QUERY SELECT 'PENDING', 'Admission pending', 'Wait for the Admissions Board', '/applicant/status', 'The decision is published here and by email.'; RETURN; END IF;
    -- the admission checking fee, its own payment, opens the released decision (V271); an acceptance already confirmed under the old rule counts as checked
    IF admissions.checking_due(p_app) THEN
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission decision released', 'Pay the admission checking fee to view your admission status', '/applicant/admission',
            'The Admissions Board''s decision on your application has been released. It opens once the admission checking fee is confirmed; it is paid once, whatever follows.'; RETURN;
    END IF;
    IF a.decision <> 'OFFERED' THEN RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL, '/applicant/status', a.decision_note; RETURN; END IF;
    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)
    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;
    END IF;
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.'; RETURN;
    END IF;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;
    IF req AND NOT admissions.screening_ok(p_app) THEN
        -- the University screens on the record it holds (V280): the applicant waits (entering only the schools attended), or provides the one correction asked for
        -- V284: a change the Academic Office recommended during the screening awaits approval
        IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND f.application_id IS NOT NULL AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Programme change under review', 'Wait for the Academic Office', '/applicant/admission',
                'During the screening the Academic Office recommended ' || q.to_programme || ' in place of ' || q.from_programme || '; the change takes effect when it is approved, and you will be told. Your acceptance fee is not paid again.';
            RETURN;
        END IF;
        IF f.application_id IS NULL OR f.state = 'PENDING' THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted - awaiting screening', 'Wait for the University''s screening', '/applicant/clearance', 'Your information has been received. The University screens your admission on the information JAMB and your application already gave; the schools you attended are the only thing you enter. You will be told the outcome here and by email.'; RETURN; END IF;
        IF f.state = 'IN_REVIEW' THEN RETURN QUERY SELECT 'SCREENING_IN_REVIEW', 'Screening in progress', 'Wait for the screening officers', '/applicant/clearance', 'A screening officer opened your record' || coalesce(' on ' || to_char(f.review_started_at, 'DD Mon YYYY'), '') || '.'; RETURN; END IF;
        IF f.state = 'CORRECTION_REQUIRED' THEN RETURN QUERY SELECT 'SCREENING_CORRECTION', 'Screening: one correction required', 'Provide the correction', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state = 'UNSUCCESSFUL' THEN
            IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND q.requested_at >= f.decided_at THEN RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Change of programme requested', 'Wait for the Admissions Office', '/applicant/clearance', 'Requested ' || q.to_programme || ' on ' || to_char(q.requested_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_REQUIRED', 'Screening unsuccessful', 'Apply for a change of programme', '/applicant/clearance', f.decision_reason; RETURN;
        END IF;
    END IF;
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    IF s.id IS NULL THEN RETURN QUERY SELECT 'REGISTER_PENDING', CASE WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Wait for the Registry to bring you onto the register', '/applicant/matric', 'School fees open once you are on the register under your admission number.'; RETURN; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN QUERY SELECT 'MATRICULATED', 'Matriculated', NULL, '/applicant/matric', 'Matriculation number ' || s.matric_no || ', issued ' || to_char(s.matriculated_at, 'DD Mon YYYY') || '. It is now your sign-in.'; RETURN; END IF;
    paid := coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    IF NOT paid THEN RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Pay school fees', '/student/fees', 'Sign in to the student portal with your admission number ' || coalesce(s.admission_no, '') || ' to pay.'; RETURN; END IF;
    IF NOT reg THEN RETURN QUERY SELECT 'COURSE_REGISTRATION_PENDING', 'School fees paid', 'Register your courses', '/student/registration', 'Registration is on the student portal.'; RETURN; END IF;
    RETURN QUERY SELECT 'MATRICULATION_PENDING', 'Ready for matriculation', 'Wait for the Academic Office to issue your number', '/applicant/matric', 'Your number is issued over the list of students who paid and registered.';
END $fn$;

CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $fn$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; st record; req boolean; ent record; steps jsonb := '[]'::jsonb;
        paid boolean; reg boolean; offered boolean; accepted boolean; scr_done boolean; scr_failed boolean; chg_approved boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO st FROM admissions.admission_status(p_app);
    offered := a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    accepted := a.accepted_at IS NOT NULL;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app AND x.state IN ('REQUESTED', 'APPROVED') ORDER BY x.requested_at DESC LIMIT 1;
    scr_done := coalesce(f.state = 'SUCCESSFUL', false); scr_failed := coalesce(f.state = 'UNSUCCESSFUL', false);
    chg_approved := scr_failed AND coalesce(q.state = 'APPROVED' AND q.decided_at >= f.decided_at, false);
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    paid := s.id IS NOT NULL AND coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    steps := steps || admissions.tracker_step('ADMISSION', 'JAMB admission', CASE WHEN offered THEN 'done' WHEN a.decision_released_at IS NULL THEN 'now' ELSE 'failed' END);
    steps := steps || admissions.tracker_step('ADMISSION_STATUS', 'Admission status checked', CASE WHEN ent.checking_paid OR a.status_checked_at IS NOT NULL OR accepted OR ent.paid OR a.undertaking_at IS NOT NULL THEN 'done' WHEN a.decision_released_at IS NOT NULL THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_PAYMENT', 'Acceptance payment', CASE WHEN ent.paid THEN 'done' WHEN offered AND NOT admissions.checking_due(p_app) AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL) THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_LETTER', 'Acceptance letter', CASE WHEN accepted THEN 'done' WHEN ent.paid THEN 'now' ELSE 'todo' END);
    IF req THEN
        steps := steps || admissions.tracker_step('SCREENING', 'University screening', CASE WHEN coalesce(f.state, '') IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);
        IF scr_failed THEN
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');
            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);
            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
        ELSE
            -- V284: a change recommended during the screening is a step of it, approved or awaiting approval
            IF q.id IS NOT NULL AND f.application_id IS NOT NULL AND q.requested_at >= f.opened_at THEN
                steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme' || CASE WHEN q.state = 'APPROVED' THEN ' · ' || q.to_programme ELSE '' END, CASE WHEN q.state = 'APPROVED' THEN 'done' ELSE 'now' END);
                steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN q.state = 'APPROVED' THEN 'done' WHEN q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
            END IF;
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening successful', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN 'now' ELSE 'todo' END);
            steps := steps || admissions.tracker_step('SCREENING_FORMS', 'Screening forms generated', CASE WHEN scr_done THEN 'done' ELSE 'todo' END);
        END IF;
    END IF;
    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status = 'SCHOOL_FEES_PENDING' OR st.status = 'REGISTER_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('STUDENT_ACCOUNT', 'Student portal active', CASE WHEN paid THEN 'done' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('USERNAME', 'Sign-in changed to the matriculation number', CASE WHEN s.matric_no IS NOT NULL THEN 'done' ELSE 'todo' END);
    RETURN steps;
END $fn$;

COMMIT;
