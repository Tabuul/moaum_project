-- ═══════════════════════════════════════════════════════════════════════════
-- V133 — platform.remove_demo_data: purge the last FK children before parents
--
--   V132 fixed the column bugs, so the purge finally ran far enough to hit a
--   foreign key: deleting a DMO course violated question_course_code_fkey — a
--   demo question referenced it. FK violations, like the earlier column bugs,
--   surface one at a time at run time (db/demo.sql seeds but never CALLS the
--   purge, so CI cannot catch them). Rather than chase them one by one, this
--   audits every FK into every parent the function deletes and clears the last
--   children that were being left behind, each before its parent:
--     - assessment.question       -> catalogue.course  (course_code)
--     - assessment.exam_timetable -> catalogue.offering (offering_id)
--     - credentials.certificate   -> people.student     (student_id)
--     - finance.nelfund_status    -> people.student     (student_id)
--     - finance.refund            -> people.student     (student_id)
--     - people.faculty_list_query -> people.student     (student_id)
--     - admissions.password_reset -> admissions.applicant_account (account_id)
--   and it widens registration.attendance to student_id as well, so a demo
--   student's attendance on any offering is cleared. With these, every FK into
--   a deleted parent is now covered. V132 is applied, so this is a new file.
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
    -- paydirect settlements are tied to a student through the PRN / reference, not a student_id column
    DELETE FROM finance.paydirect_collection
     WHERE prn       IN (SELECT reference FROM finance.payment_reference WHERE student_id IN (SELECT id FROM _ds))
        OR reference IN (SELECT reference FROM finance.payment_reference WHERE student_id IN (SELECT id FROM _ds));
    DELETE FROM finance.wallet_withdrawal WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.wallet_entry WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.nelfund_row WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.nelfund_status WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM finance.refund WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM library.reservation WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM library.loan WHERE student_id IN (SELECT id FROM _ds);
    -- a maintenance request is raised BY a student (raised_by); a hostel
    -- allocation is tied to a student through its application. Neither has a
    -- student_id column.
    DELETE FROM hostel.maintenance_request WHERE raised_by IN (SELECT id FROM _ds);
    DELETE FROM hostel.allocation WHERE application_id IN (SELECT id FROM hostel.application WHERE student_id IN (SELECT id FROM _ds));
    DELETE FROM hostel.application WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM credentials.identity_card WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM clearance.item WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM credentials.transcript_request WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM credentials.certificate WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM records.graduand WHERE student_id IN (SELECT id FROM _ds);

    -- the money trail of the demo students
    DELETE FROM finance.payment_reference WHERE student_id IN (SELECT id FROM _ds);

    -- results and registration of the demo students and the demo courses
    DELETE FROM assessment.result_query WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM assessment.score WHERE student_id IN (SELECT id FROM _ds) OR sheet_id IN (SELECT id FROM _dsheet);
    DELETE FROM assessment.decision WHERE sheet_id IN (SELECT id FROM _dsheet);
    DELETE FROM assessment.score_sheet WHERE id IN (SELECT id FROM _dsheet);
    DELETE FROM registration.attendance WHERE offering_id IN (SELECT id FROM _do) OR student_id IN (SELECT id FROM _ds);
    DELETE FROM assessment.exam_timetable WHERE offering_id IN (SELECT id FROM _do);
    DELETE FROM assessment.question WHERE course_code IN (SELECT code FROM _dc);
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
    DELETE FROM people.faculty_list_query WHERE student_id IN (SELECT id FROM _ds);
    DELETE FROM people.student WHERE id IN (SELECT id FROM _ds);

    -- the demo admission candidates
    DELETE FROM admissions.clearance_document WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.application_document_blob WHERE document_id IN (SELECT id FROM admissions.application_document WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand)));
    DELETE FROM admissions.application_document WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.fee_reference WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.suggestion_sent WHERE application_id IN (SELECT id FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.application WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.password_reset WHERE account_id IN (SELECT id FROM admissions.applicant_account WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.applicant_account WHERE candidate_id IN (SELECT id FROM _dcand);
    -- an O'Level sitting is tied to a candidate through its attachment, not a candidate_id column
    DELETE FROM admissions.olevel_grade WHERE sitting_id IN (SELECT id FROM admissions.olevel_sitting WHERE attachment_id IN (SELECT id FROM admissions.attachment WHERE candidate_id IN (SELECT id FROM _dcand)));
    DELETE FROM admissions.olevel_sitting WHERE attachment_id IN (SELECT id FROM admissions.attachment WHERE candidate_id IN (SELECT id FROM _dcand));
    DELETE FROM admissions.candidate_photo WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.attachment WHERE candidate_id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.jamb_admission WHERE session IN (SELECT session FROM admissions.candidate WHERE id IN (SELECT id FROM _dcand)) AND jamb_reg_no LIKE '202699%D_';
    DELETE FROM admissions.candidate WHERE id IN (SELECT id FROM _dcand);
    DELETE FROM admissions.caps_row WHERE jamb_reg_no LIKE '202699%D_';

    RETURN r || jsonb_build_object('removed', true);
END $$;

COMMIT;
