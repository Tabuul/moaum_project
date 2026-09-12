-- ── V108 — the operational-data reset covers the tables added since V089 ─────
-- Two gaps had opened up in platform.reset_operational_data since it was written:
--
--   1. admissions.suggestion_sent (V106) references admissions.application, but
--      the reset deleted the applications without first clearing the log. On any
--      database where a suggestion had been sent (the demo, or a real cycle that
--      used the feature) the reset would have failed with a foreign-key
--      violation. It is deleted here BEFORE admissions.application.
--   2. hrm.staff_profile / hrm.staff_photo (V107) are operational data a member
--      of staff enters about themselves; the clean slate now clears them too.
--      They hang on iam.person, which the reset keeps, so this only removes the
--      profile, never the person or their offices.
--
-- The rest of the body is V089's, unchanged. V089 stays exactly as applied; the
-- correction is this new file (the migrate ledger must not be rewritten).

CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    -- what is about to go, for the record the caller gets back
    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile)
    ) INTO r;

    -- credentials and graduation hung on students
    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;

    -- course spaces (V035) and service requests (V036)
    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    -- health records
    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES, a setting, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    -- library loans (the catalogue of items/copies is kept)
    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    -- hostel allocations (the halls and rooms are kept)
    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- the student's services, timetables, cards
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    -- the Bursary's transaction trail (gateway credentials/billers, a setting, are kept)
    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    -- the student's account and identity on the portal
    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    -- staff profiles a member of staff entered about themselves (V107); the
    -- person and their offices are kept, only the CV they typed is cleared
    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    -- results, registration and the uploaded course structure
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    -- the register itself
    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    -- credentials issued (the signing key, a setting, is kept)
    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    -- the admissions intake (the admission POLICY and O'Level grading, settings, are kept)
    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;   -- V106: hangs on application, must go first
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;

    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $$;

COMMENT ON FUNCTION platform.reset_operational_data(text, text) IS
'The Super Administrator''s clean slate: clears operational data (admissions, students, results, courses, fees, payments, wallets, staff profiles) and keeps reference data, configuration, staff logins and the audit trail. Guarded by an actor, the word RESET, and a reason; runs in one transaction.';
