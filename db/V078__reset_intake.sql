-- ═══════════════════════════════════════════════════════════════════════════
-- V078 — reset the JAMB list for a session, from the portal
--
--   The Academic Office needs to clear a CAPS upload and start again (a test
--   load, a wrong file) without dropping to the database. This function deletes,
--   for one session, the JAMB (CAPS) list, the candidates on it, their O'Level,
--   photos and attachments, and the applicant intake built on them (accounts,
--   applications, documents, fee references, screening). It KEEPS the admission
--   policy/config and every student already on the register — each student is
--   simply detached from the candidate row being deleted. One attributed act.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.reset_intake(p_session text)
RETURNS TABLE (candidates int, applications int, caps_rows int, olevel int, students_detached int)
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        n_cand int; n_app int; n_caps int; n_ol int; n_stu int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the JAMB list is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_session IS NULL OR btrim(p_session) = '' THEN RAISE EXCEPTION 'a reset names the session it clears' USING ERRCODE = '23514'; END IF;

    -- keep students on the register; detach them from the candidates being deleted
    UPDATE people.student SET candidate_id = NULL
     WHERE candidate_id IN (SELECT id FROM admissions.candidate WHERE session = p_session);
    GET DIAGNOSTICS n_stu = ROW_COUNT;

    -- the gateway trail for the applicant fee references (linked by reference text, not a key)
    DELETE FROM finance.gateway_event
     WHERE reference IN (SELECT reference FROM admissions.fee_reference
                          WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session));
    DELETE FROM finance.gateway_attempt
     WHERE reference IN (SELECT reference FROM admissions.fee_reference
                          WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session));
    DELETE FROM finance.payment_reconciliation
     WHERE reference IN (SELECT reference FROM admissions.fee_reference
                          WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session));

    -- the applicant intake, children first
    DELETE FROM admissions.application_document_blob
     WHERE document_id IN (SELECT d.id FROM admissions.application_document d
                             JOIN admissions.application a ON a.id = d.application_id WHERE a.session = p_session);
    DELETE FROM admissions.application_document
     WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session);
    DELETE FROM admissions.fee_reference
     WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session);
    DELETE FROM admissions.clearance_document
     WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session);
    DELETE FROM admissions.password_reset
     WHERE account_id IN (SELECT id FROM admissions.applicant_account WHERE session = p_session);
    DELETE FROM admissions.applicant_event
     WHERE account_id IN (SELECT id FROM admissions.applicant_account WHERE session = p_session);
    DELETE FROM admissions.application WHERE session = p_session;
    GET DIAGNOSTICS n_app = ROW_COUNT;
    DELETE FROM admissions.applicant_account WHERE session = p_session;
    DELETE FROM admissions.screening_batch WHERE session = p_session;

    -- the O'Level, then the candidate data
    DELETE FROM admissions.olevel_grade
     WHERE sitting_id IN (SELECT id FROM admissions.olevel_sitting WHERE session = p_session);
    DELETE FROM admissions.olevel_sitting WHERE session = p_session;
    GET DIAGNOSTICS n_ol = ROW_COUNT;
    DELETE FROM admissions.candidate_photo
     WHERE candidate_id IN (SELECT id FROM admissions.candidate WHERE session = p_session);
    DELETE FROM admissions.attachment WHERE session = p_session;
    DELETE FROM admissions.candidate WHERE session = p_session;
    GET DIAGNOSTICS n_cand = ROW_COUNT;

    -- the JAMB (CAPS) list itself
    DELETE FROM admissions.caps_row WHERE session = p_session;
    GET DIAGNOSTICS n_caps = ROW_COUNT;
    DELETE FROM admissions.caps_row_excluded WHERE session = p_session;
    DELETE FROM admissions.caps_batch WHERE session = p_session;

    RETURN QUERY SELECT n_cand, n_app, n_caps, n_ol, n_stu;
END $$;

COMMIT;
