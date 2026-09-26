-- ═══════════════════════════════════════════════════════════════════════════
-- V265 · Deferment: the Deputy Vice-Chancellor's approval is the final approval
--
--   The Registry's procedure of September 2026, as settled: the chain ends at
--   the DVC. There is no Senate Business Committee stage after it. The DVC's
--   approval (with its comment) is the final act — the request is APPROVED,
--   the academic effect applied in the same transaction, the letter issued and
--   the student told. The state DVC_APPROVED is retired: any request that sat
--   at it is carried to APPROVED here, with the effect applied and the trail
--   saying so. The approval timeline ends at the DVC's approval; the period
--   in force and the return remain on the record and its own screens.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V265: the DVC''s approval is final', true);

-- ── 1 · the words ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION people.deferment_stage_label(p_state text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state
        WHEN 'DRAFT' THEN 'DRAFT'
        WHEN 'SUBMITTED' THEN 'WAITING BURSARY ACTION'
        WHEN 'BURSARY_APPROVED' THEN 'WAITING HOD ACTION'
        WHEN 'DEPT_RECOMMENDED' THEN 'WAITING FACULTY ACTION'
        WHEN 'FAC_RECOMMENDED' THEN 'WAITING ACADEMIC OFFICE ACTION'
        WHEN 'FORWARDED_TO_DVC' THEN 'WAITING DVC ACTION'
        WHEN 'DVC_APPROVED' THEN 'APPROVED'
        WHEN 'APPROVED' THEN 'APPROVED'
        WHEN 'ACTIVE' THEN 'APPROVED · IN FORCE'
        WHEN 'COMPLETED' THEN 'COMPLETED'
        WHEN 'REJECTED' THEN 'REJECTED'
        WHEN 'CORRECTION_REQUIRED' THEN 'RETURNED FOR CORRECTION'
        WHEN 'CANCELLED' THEN 'CANCELLED'
        ELSE p_state END;
$$;

CREATE OR REPLACE FUNCTION people.deferment_stage_offices(p_state text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state
        WHEN 'SUBMITTED' THEN ARRAY['bursar']
        WHEN 'BURSARY_APPROVED' THEN ARRAY['hod']
        WHEN 'DEPT_RECOMMENDED' THEN ARRAY['dean','facultyofficer']
        WHEN 'FAC_RECOMMENDED' THEN ARRAY['academic','registrar','dregistrar']
        WHEN 'FORWARDED_TO_DVC' THEN ARRAY['dvc']
        ELSE ARRAY[]::text[] END;
$$;

CREATE OR REPLACE FUNCTION people.deferment_stage_office_label(p_state text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_state
        WHEN 'SUBMITTED' THEN 'Bursary' WHEN 'BURSARY_APPROVED' THEN 'Head of Department' WHEN 'DEPT_RECOMMENDED' THEN 'Faculty'
        WHEN 'FAC_RECOMMENDED' THEN 'Academic Office' WHEN 'FORWARDED_TO_DVC' THEN 'Deputy Vice-Chancellor (Academic)'
        WHEN 'CORRECTION_REQUIRED' THEN 'Student' WHEN 'DRAFT' THEN 'Student' ELSE NULL END;
$$;

-- ── 2 · the decision: the DVC's approval is final ────────────────────────

CREATE OR REPLACE FUNCTION people.deferment_decide(p_id uuid, p_action text, p_note text, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
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
                USING ERRCODE = '23514', HINT = 'Act at your own stage; the request reaches the next desk on its own.';
        ELSE RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM people.deferment_log(d.id, p_action, v_from, v_to, v_note);
    RETURN v_to;
END $$;


-- ── 3 · a request that sat at the retired state is carried to APPROVED ───

DO $$
DECLARE d record;
BEGIN
    FOR d IN SELECT * FROM people.deferment WHERE state = 'DVC_APPROVED' LOOP
        UPDATE people.deferment SET state = 'APPROVED', decided_at = coalesce(decided_at, dvc_at, now()), decided_by = coalesce(decided_by, dvc_by), decision_note = coalesce(decision_note, dvc_note), updated_at = now() WHERE id = d.id;
        PERFORM people.deferment_apply_effect(d.id);
        PERFORM people.deferment_log(d.id, 'APPROVE', 'DVC_APPROVED', 'APPROVED', 'Carried to APPROVED: the DVC''s approval is the final approval (V265)');
        PERFORM people.deferment_tell(d.id, 'DEFERMENT APPROVED · ' || d.reference, 'Your deferment request approved by the Deputy Vice-Chancellor (Academic) is final; the period is held on the record and your approval letter is on the portal.');
    END LOOP;
    PERFORM people.deferments_tick();
END $$;

COMMIT;
