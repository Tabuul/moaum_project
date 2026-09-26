-- ═══════════════════════════════════════════════════════════════════════════
-- V271 — the admission checking fee is its own payment, before the status;
--        the status is read before the offer is accepted; fees count as
--        settled only when something was due
--
--   V148 folded the admission checking fee into the acceptance reference
--   ("paid at acceptance, alongside the acceptance fee"). That was wrong: the
--   checking fee is paid on its own, once, to view the released admission
--   status; the acceptance fee follows, alone. The journey after the JAMB
--   list therefore reads: pay the checking fee → view the admission status
--   (the offer and its details) → accept and pay the acceptance fee → the
--   letter → the online screening. A CHECKING reference of its own confirms
--   the checking fee and opens the decision; an acceptance confirmed under
--   the old rule (fee included) counts as checked, and nobody pays twice —
--   whatever programme the admission ends on. The applicant's first reading
--   of the status is on the record and precedes the acceptance fee. And a
--   session whose fee schedule is not yet stated owes nothing, which the
--   tracker read as "school fees paid": fees are settled only when due.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V271: the admission checking fee on its own, before the status', true);

ALTER TABLE admissions.application ADD COLUMN IF NOT EXISTS checking_confirmed_at timestamptz NULL;
ALTER TABLE admissions.application ADD COLUMN IF NOT EXISTS status_checked_at timestamptz NULL;
COMMENT ON COLUMN admissions.application.checking_confirmed_at IS 'When the admission checking fee was confirmed (V271): the released decision opens to the applicant from this moment.';
COMMENT ON COLUMN admissions.application.status_checked_at IS 'When the applicant first read the released admission status on the portal (V271).';

ALTER TABLE admissions.fee_reference DROP CONSTRAINT IF EXISTS ck_fref_kind;
ALTER TABLE admissions.fee_reference ADD CONSTRAINT ck_fref_kind CHECK (kind IN ('APPLICATION', 'CHECKING', 'ACCEPTANCE'));

/* is the checking fee still owed before the decision is shown: a fee stated, a decision released, neither the checking nor an (old-rule) acceptance confirmed */
CREATE OR REPLACE FUNCTION admissions.checking_due(p_app uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT a.decision_released_at IS NOT NULL AND a.checking_confirmed_at IS NULL AND a.acceptance_confirmed_at IS NULL
                            AND coalesce((SELECT f.checking_fee FROM admissions.applicant_fee_rule(a.session) f), 0) > 0
                       FROM admissions.application a WHERE a.id = p_app), false);
$$;

/* the applicant's own act of reading the status, once */
CREATE OR REPLACE FUNCTION admissions.admission_status_checked(p_app uuid)
RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE v timestamptz;
BEGIN
    UPDATE admissions.application SET status_checked_at = coalesce(status_checked_at, now()) WHERE id = p_app AND decision_released_at IS NOT NULL AND NOT admissions.checking_due(id) RETURNING status_checked_at INTO v;
    RETURN v;
END $$;

/* the acceptance and the checking fees belong to the admission, paid once each; the checking fee paid inside an old-rule acceptance counts */
DROP FUNCTION IF EXISTS admissions.acceptance_entitlement(uuid);
CREATE FUNCTION admissions.acceptance_entitlement(p_app uuid)
RETURNS TABLE (paid boolean, reference text, confirmed_at timestamptz, amount numeric, checking_paid boolean, checking_reference text, checking_confirmed_at timestamptz, checking_amount numeric)
LANGUAGE sql STABLE AS $$
    SELECT (a.acceptance_confirmed_at IS NOT NULL OR fr.confirmed_at IS NOT NULL), fr.reference, coalesce(a.acceptance_confirmed_at, fr.confirmed_at), fr.amount,
           (a.checking_confirmed_at IS NOT NULL OR ck.confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL OR fr.confirmed_at IS NOT NULL), ck.reference, coalesce(a.checking_confirmed_at, ck.confirmed_at), ck.amount
      FROM admissions.application a
      LEFT JOIN LATERAL (SELECT r.reference, r.confirmed_at, r.amount FROM admissions.fee_reference r WHERE r.application_id = a.id AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NOT NULL ORDER BY r.confirmed_at LIMIT 1) fr ON true
      LEFT JOIN LATERAL (SELECT r.reference, r.confirmed_at, r.amount FROM admissions.fee_reference r WHERE r.application_id = a.id AND r.kind = 'CHECKING' AND r.confirmed_at IS NOT NULL ORDER BY r.confirmed_at LIMIT 1) ck ON true
     WHERE a.id = p_app;
$$;

/* V148's reference, each fee on its own; V062's confirmation, the checking fee opening the decision */
CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'CHECKING' THEN
        IF a.decision_released_at IS NULL THEN
            RAISE EXCEPTION 'there is no decision to check yet' USING ERRCODE = '23514', HINT = 'The admission checking fee follows the release of the decision.';
        END IF;
        IF a.checking_confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the admission checking fee is already confirmed' USING ERRCODE = '23514', HINT = 'It is paid once; nothing more is owed to view the admission status.';
        END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        IF admissions.checking_due(p_app) THEN
            RAISE EXCEPTION 'the admission checking fee comes first' USING ERRCODE = '23514', HINT = 'Pay the admission checking fee and view your admission status; the acceptance fee follows.';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
             || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
    VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours');
    RETURN v_ref;
END $$;


CREATE OR REPLACE FUNCTION admissions.confirm_fee(p_reference text, p_channel text, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r admissions.fee_reference; a admissions.application; v_no text; v_purpose text; v_action text; v_sms_action text;
BEGIN
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id;

    v_no := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
    UPDATE admissions.fee_reference SET confirmed_at = now(), confirmed_by = admissions.acting_person(),
           channel = p_channel, note = p_note, receipt_no = v_no WHERE id = r.id;

    IF r.kind = 'APPLICATION' THEN
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = a.id;
        v_purpose := 'Application & Post-UTME';
        v_action := 'Your application form is now open: sign in and complete it.';
        v_sms_action := 'Your application form is open.';
    ELSIF r.kind = 'CHECKING' THEN
        -- the decision opens; the reading is on the record (V271)
        UPDATE admissions.application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()), status_checked_at = coalesce(status_checked_at, now()) WHERE id = a.id;
        v_purpose := 'Admission checking';
        v_action := 'Your admission status is now open: sign in and view it under Admission Progress.';
        v_sms_action := 'Your admission status is open on the portal.';
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        v_purpose := 'Acceptance';
        v_action := 'Your acceptance of the offer is settled. Sign in to continue to clearance.';
        v_sms_action := 'Acceptance settled.';
        PERFORM admissions.settle_acceptance(a.id);
    END IF;

    PERFORM admissions.notify_applicant(a.id, 'Your payment receipt · ' || v_no,
        'This is your official receipt from Rev. Fr. Moses Orshio Adasu University, Makurdi.' || chr(10) || chr(10)
        || 'Receipt no:  ' || v_no || chr(10)
        || 'Reference:   ' || r.reference || chr(10)
        || 'Purpose:     ' || v_purpose || ' fee' || chr(10)
        || 'Session:     ' || a.session || chr(10)
        || 'Amount:      NGN ' || to_char(r.amount, 'FM999,999,990.00') || chr(10)
        || 'Confirmed:   ' || to_char(now(), 'FMDD FMMonth YYYY') || chr(10)
        || 'Channel:     ' || coalesce(p_channel, 'Bank') || chr(10) || chr(10)
        || v_action || chr(10) || chr(10)
        || 'Keep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
        'MOAUM receipt ' || v_no || ': NGN ' || to_char(r.amount, 'FM999,999,990.00') || ' for ' || v_purpose || ' confirmed. ' || v_sms_action);

    RETURN 'confirmed';
END $$;


CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
RETURNS TABLE (status text, label text, next_action text, next_href text, detail text)
LANGUAGE plpgsql STABLE AS $$
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
        IF f.application_id IS NULL THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted — screening to complete', 'Complete the online screening', '/applicant/clearance', 'Your acceptance letter is ready; the online screening is the next step.'; RETURN; END IF;
        IF f.state = 'DRAFT' THEN RETURN QUERY SELECT 'SCREENING_IN_PROGRESS', 'Screening form in progress', 'Complete and submit the screening form', '/applicant/clearance', NULL; RETURN; END IF;
        IF f.state = 'RETURNED' THEN RETURN QUERY SELECT 'SCREENING_RETURNED', 'Screening form returned for correction', 'Correct and resubmit the screening form', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state IN ('SUBMITTED', 'UNDER_REVIEW') THEN RETURN QUERY SELECT 'SCREENING_SUBMITTED', 'Screening under review', 'Wait for the screening officers', '/applicant/clearance', 'Submitted ' || to_char(f.submitted_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
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
END $$;

CREATE OR REPLACE FUNCTION admissions.tracker_step(k text, l text, st text)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('key', k, 'label', l, 'state', st) $$;

/* the tracker: only the steps that concern this applicant, each done, now, todo or failed */
CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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
        steps := steps || admissions.tracker_step('SCREENING', 'Online screening', CASE WHEN coalesce(f.state, '') IN ('SUBMITTED', 'UNDER_REVIEW', 'SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);
        IF scr_failed THEN
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');
            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);
            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
        ELSE
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening approval', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('SUBMITTED', 'UNDER_REVIEW') THEN 'now' ELSE 'todo' END);
        END IF;
    END IF;
    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status = 'SCHOOL_FEES_PENDING' OR st.status = 'REGISTER_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);
    RETURN steps;
END $$;


COMMIT;
