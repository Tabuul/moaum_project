-- ═══════════════════════════════════════════════════════════════════════════
-- V175 — make reset_migrated_applicants fast and light
--
--   V174's reset deleted the migration's ~13,000 candidate/account/application
--   records with the audit trigger firing on every row of every attached table
--   — hundreds of thousands of audit inserts in one transaction, which locked
--   the admissions tables and saturated the database (the portal went slow and
--   sign-in timed out). A bulk office action like this is audit-light, the same
--   way opening registration and the backfills are: the triggers are disabled
--   around the one operation, and the action itself is attributed at the request.
--
--   Same effect as V174, only fast: clears only the migration's records (marked
--   by the 'Old-portal migration' fee channel), keeps the CAPS rows, O'Level and
--   passports (a passport is unlinked, not deleted, and re-attaches by JAMB no).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.reset_migrated_applicants(p_session text)
RETURNS TABLE (candidates int, applications int, accounts int, passports_kept int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, admissions, finance, people
AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        n_cand int; n_app int; n_acc int; n_pass int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the migration is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_session IS NULL OR btrim(p_session) = '' THEN RAISE EXCEPTION 'a reset names the session it clears' USING ERRCODE = '23514'; END IF;

    CREATE TEMP TABLE _mig ON COMMIT DROP AS
        SELECT DISTINCT a.id AS app_id, a.account_id, a.candidate_id
          FROM admissions.application a
          JOIN admissions.fee_reference fr ON fr.application_id = a.id
         WHERE a.session = p_session AND fr.channel = 'Old-portal migration';

    -- audit-light bulk: disable the row triggers on the attached tables this touches
    ALTER TABLE admissions.candidate           DISABLE TRIGGER trg_audit_admissions_candidate;
    ALTER TABLE admissions.candidate_photo     DISABLE TRIGGER trg_audit_admissions_candidate_photo;
    ALTER TABLE admissions.application         DISABLE TRIGGER trg_audit_admissions_application;
    ALTER TABLE admissions.fee_reference       DISABLE TRIGGER trg_audit_admissions_fee_reference;
    ALTER TABLE admissions.application_document DISABLE TRIGGER trg_audit_admissions_application_document;
    ALTER TABLE admissions.clearance_document  DISABLE TRIGGER trg_audit_admissions_clearance_document;

    -- preserve passports: unlink (do not delete) so they re-attach by JAMB number after re-migration
    UPDATE admissions.attachment SET candidate_id = NULL, matched_at = NULL
     WHERE candidate_id IN (SELECT candidate_id FROM _mig);
    GET DIAGNOSTICS n_pass = ROW_COUNT;

    DELETE FROM finance.gateway_event WHERE reference IN (SELECT reference FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig));
    DELETE FROM finance.gateway_attempt WHERE reference IN (SELECT reference FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig));
    DELETE FROM finance.payment_reconciliation WHERE reference IN (SELECT reference FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig));

    DELETE FROM admissions.application_document_blob
     WHERE document_id IN (SELECT id FROM admissions.application_document WHERE application_id IN (SELECT app_id FROM _mig));
    DELETE FROM admissions.application_document WHERE application_id IN (SELECT app_id FROM _mig);
    DELETE FROM admissions.clearance_document WHERE application_id IN (SELECT app_id FROM _mig);
    DELETE FROM admissions.fee_reference WHERE application_id IN (SELECT app_id FROM _mig);
    DELETE FROM admissions.applicant_event WHERE account_id IN (SELECT account_id FROM _mig);
    DELETE FROM admissions.password_reset WHERE account_id IN (SELECT account_id FROM _mig);
    DELETE FROM admissions.application WHERE id IN (SELECT app_id FROM _mig);
    GET DIAGNOSTICS n_app = ROW_COUNT;
    DELETE FROM admissions.applicant_account WHERE id IN (SELECT account_id FROM _mig);
    GET DIAGNOSTICS n_acc = ROW_COUNT;
    DELETE FROM admissions.candidate_photo WHERE candidate_id IN (SELECT candidate_id FROM _mig);
    DELETE FROM admissions.candidate c
     WHERE c.id IN (SELECT candidate_id FROM _mig)
       AND NOT EXISTS (SELECT 1 FROM admissions.application a2 WHERE a2.candidate_id = c.id)
       AND NOT EXISTS (SELECT 1 FROM admissions.applicant_account ac2 WHERE ac2.candidate_id = c.id)
       AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = c.id);
    GET DIAGNOSTICS n_cand = ROW_COUNT;

    ALTER TABLE admissions.candidate           ENABLE TRIGGER trg_audit_admissions_candidate;
    ALTER TABLE admissions.candidate_photo     ENABLE TRIGGER trg_audit_admissions_candidate_photo;
    ALTER TABLE admissions.application         ENABLE TRIGGER trg_audit_admissions_application;
    ALTER TABLE admissions.fee_reference       ENABLE TRIGGER trg_audit_admissions_fee_reference;
    ALTER TABLE admissions.application_document ENABLE TRIGGER trg_audit_admissions_application_document;
    ALTER TABLE admissions.clearance_document  ENABLE TRIGGER trg_audit_admissions_clearance_document;

    RETURN QUERY SELECT n_cand, n_app, n_acc, n_pass;
END $$;

COMMIT;
