-- ═══════════════════════════════════════════════════════════════════════════
-- V292 — the property suite's findings, once it ran whole again
--
-- db/check.sql had three blocks closed with `END $;` and two opened with `DO $`,
-- so from §17a onward it parsed as one long error: 16 of its 149 properties
-- ran, and the CI gate passed because it matched "FOUNDATION GREEN" in the
-- script's own text echoed inside an error message. Run whole, it found two
-- faults in the portal itself, corrected here:
--
--   1. platform.reset_operational_data, the Super Administrator's clean slate
--      behind POST /api/v1/platform/reset-data and a step of the go-live
--      runbook, was last written in V108. Fifty-one tables added since hang on
--      what it clears without ON DELETE CASCADE: postgraduate applications,
--      registration and research; the College's enrolments, scores and
--      postings; deferments; matriculation batches and history; screening
--      forms and events; external examiners' projects; hostel transfers and
--      (V291) discipline and swaps. On any database where one of them held a
--      row the reset failed with a foreign-key violation and cleared nothing.
--      It now clears them first, children before parents, the write-once
--      histories under the maintenance flag their triggers honour, and the
--      deferment's circular reference to its fee, and an issued document's to
--      its transcript request (the reset already cleared both, in an order that
--      failed once a transcript had been issued), broken before either goes.
--      check.sql gains a property computed from the catalogue, so a table
--      added later that would block the reset fails CI the day it is added.
--   2. admissions.programme_change_reason (V284) was never attached to the
--      audit spine: a change to the list of reasons went unrecorded.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V292: reset coverage and audit attachment', true);

SELECT audit.attach('admissions.programme_change_reason');

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
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    -- ── V292: everything added since V108 that hangs on what the reset clears, children first ──
    -- the write-once histories (screening, PUTME, deferment, matric, external examiners) are cleared
    -- under the maintenance flag every one of their triggers honours; it is lifted again below
    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;   -- the deferment and its fee refer to each other
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;   -- an issued document and its transcript request refer to each other (V262)
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

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
    -- the O'Level sittings are derived from the attachments and reference them,
    -- so they (and the grades that hang on them) go before the attachments.
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $$;

COMMENT ON FUNCTION platform.reset_operational_data(text, text) IS
'The Super Administrator''s clean slate: clears operational data (admissions, students, results, courses, fees, payments, wallets, staff profiles) and keeps reference data, configuration, staff logins and the audit trail. V292: covers every table added since V108 that hangs on what it clears (postgraduate, College, deferment, matriculation management, screening, external examiners, hostel discipline). Guarded by an actor, the word RESET, and a reason; runs in one transaction.';

COMMIT;
