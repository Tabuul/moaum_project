-- ═══════════════════════════════════════════════════════════════════════════
-- V129 — remove the demo OPERATIONAL data, keep the demo LOGIN accounts
--
--   db/demo.sql seeds a walkthrough: demo students (surname 'DEMO', matric
--   …/990[1-6]), five 'DMO ' courses, two demo JAMB candidates (202699…D%), and
--   everything hanging off them. This purges exactly those rows — nothing else.
--   Real uploaded students/courses/payments/results are matched by their own
--   identifiers and are untouched, and the demo STAFF sign-ins (iam.person with
--   staff_number 'MOAUM/DEMO/…', credentials 'demo.<office>') are kept so an
--   operator can still walk the portal.
--
--   It runs as one transaction, so if a demo row is referenced by a table this
--   function does not clear, the whole thing rolls back and nothing changes —
--   safe to run, and safe to re-run (idempotent once the demo rows are gone).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION platform.remove_demo_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a demo purge is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'REMOVE DEMO' THEN
        RAISE EXCEPTION 'type REMOVE DEMO to confirm removing the demo data' USING ERRCODE = '23514';
    END IF;

    -- the demo sets, by their seed markers
    CREATE TEMP TABLE _ds ON COMMIT DROP AS
        SELECT id FROM people.student
         WHERE surname = 'DEMO' AND matric_no ~ '^MOAUM/[A-Z]{2,6}/[0-9]{2}/990[1-6]$';
    CREATE TEMP TABLE _dc ON COMMIT DROP AS
        SELECT code FROM catalogue.course WHERE code LIKE 'DMO %';
    CREATE TEMP TABLE _do ON COMMIT DROP AS
        SELECT id FROM catalogue.offering WHERE course_code IN (SELECT code FROM _dc);
    CREATE TEMP TABLE _dcand ON COMMIT DROP AS
        SELECT id FROM admissions.candidate WHERE jamb_reg_no LIKE '202699%D_';
    CREATE TEMP TABLE _dreg ON COMMIT DROP AS
        SELECT id FROM registration.course_registration WHERE student_id IN (SELECT id FROM _ds);
    CREATE TEMP TABLE _dsheet ON COMMIT DROP AS
        SELECT id FROM assessment.score_sheet WHERE offering_id IN (SELECT id FROM _do);

    r := jsonb_build_object(
        'demo_students', (SELECT count(*) FROM _ds),
        'demo_courses',  (SELECT count(*) FROM _dc),
        'demo_offerings',(SELECT count(*) FROM _do),
        'demo_candidates',(SELECT count(*) FROM _dcand));

    -- learning, services and clearance hung on the demo students
    DELETE FROM lms.submission_blob WHERE submission_id IN (SELECT id FROM lms.submission WHERE student_id IN (SELECT id FROM _ds));
    DELETE FROM lms.submission WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM lms.access WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM lms.material_blob WHERE material_id IN (SELECT id FROM lms.material WHERE offering_id IN (SELECT id FROM _do));
    DELETE FROM lms.material WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM lms.assignment WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM platform.request_document_blob WHERE document_id IN (SELECT id FROM platform.request_document WHERE request_id IN (SELECT id FROM platform.service_request WHERE student_id IN (SELECT id FROM _ds)));
    DELETE FROM platform.request_document WHERE request_id IN (SELECT id FROM platform.service_request WHERE student_id IN (SELECT id FROM _ds));
    DELETE FROM platform.service_request WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM health.note WHERE visit_id IN (SELECT id FROM health.visit WHERE student_id IN (SELECT id FROM _ds));
    DELETE FROM health.record_access WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM health.visit WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM health.appointment WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM health.profile WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.paydirect_collection WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.wallet_withdrawal WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.wallet_entry WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.nelfund_row WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM library.reservation WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM library.loan WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM hostel.maintenance_request WHERE allocation_id IN (SELECT id FROM hostel.allocation WHERE student_id IN (SELECT id FROM _ds));
    DELETE FROM hostel.allocation WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM hostel.application WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM credentials.identity_card WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM clearance.item WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM credentials.transcript_request WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM records.graduand WHERE student_id IN (SELECT id FROM _ds);

    -- the money trail of the demo students
    DELETE FROM finance.payment_reference WHERE student_id IN (SELECT id FROM _ds);

    -- results and registration of the demo students and the demo courses
    DELETE FROM assessment.result_query WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM assessment.score WHERE student_id IN (SELECT id FROM _ds) OR sheet_id IN (SELECT id FROM _dsheet);
    DELETE FROM assessment.decision WHERE sheet_id IN (SELECT id FROM _dsheet);
    DELETE FROM assessment.score_sheet WHERE id IN (SELECT id FROM _dsheet);
    DELETE FROM registration.attendance WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM catalogue.class_slot WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM registration.entry WHERE registration_id IN (SELECT id FROM _dreg) OR offering_id IN (SELECT id FROM _do);
    DELETE FROM registration.course_registration WHERE id IN (SELECT id FROM _dreg);
    DELETE FROM catalogue.offering WHERE id IN (SELECT id FROM _do);
    DELETE FROM catalogue.course_offer WHERE course_code IN (SELECT code FROM _dc);
    DELETE FROM catalogue.course WHERE code IN (SELECT code FROM _dc);

    -- the demo students' identity and record
    DELETE FROM iam.student_account WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM iam.student_event WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.student_contact WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.biodata_change WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.biodata WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.document WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.status_change WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.enrolment WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.transfer_application WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.student WHERE id IN (SELECT id FROM _ds);

    -- the demo admission candidates
    DELETE FROM admissions.clearance_document WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.application_document_blob WHERE document_id IN (SELECT id FROM admissions.application_document WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand)));
    DELETE FROM admissions.application_document WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.fee_reference WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.suggestion_sent WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.applicant_account WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.olevel_grade WHERE sitting_id IN (SELECT id FROM admissions.olevel_sitting WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.olevel_sitting WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.candidate_photo WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.attachment WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.jamb_admission WHERE session IN (SELECT session FROM admissions.candidate WHERE id IN (SELECT id FROM _dcand)) AND jamb_reg_no LIKE '202699%D_';
    DELETE FROM admissions.candidate WHERE id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.caps_row WHERE jamb_reg_no LIKE '202699%D_';

    RETURN r || jsonb_build_object('removed', true);
END $$;

COMMENT ON FUNCTION platform.remove_demo_data(text) IS
  'Remove only the db/demo.sql operational data (demo students, DMO courses, demo '
  'candidates and their dependents), keeping demo staff logins and all real data. '
  'One transaction: rolls back whole if any demo row is still referenced elsewhere.';

COMMIT;
