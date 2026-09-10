-- ═══════════════════════════════════════════════════════════════════════════
-- reset-admissions.sql — clear the admission cycle and the students it produced,
--                        so a fresh CAPS list can be uploaded and walked
--
--   WHAT IT CLEARS (all sessions):
--     • the whole admission pipeline: CAPS uploads, candidates and their photos,
--       attachments and O'Level, applicant accounts, applications and documents,
--       fee references, screening batches, clearance documents;
--     • every student that admission produced, and everything hung on a student:
--       enrolment, biodata, documents, course registration, attendance, scores
--       and queries, fees and payment references, the wallet and NELFUND rows,
--       hostel, library loans, health, ID cards, transcripts, certificates,
--       graduands, service requests, the student's sign-in account;
--     • the gateway day-book that named those references (events, attempts, bank
--       credits, refunds, reconciliations) and the notices sent about them.
--
--   WHAT IT KEEPS (configuration and structure — you do NOT re-enter it):
--     • the admission policy: cut-offs, faculty quotas, selection criteria,
--       programme and subject rules, closed programmes, catchment LGAs, the
--       O'Level grading scale and compulsory subjects, the application-fee amount
--       and which programmes require post-UTME;
--     • the academic structure: sessions and semesters, programmes, courses and
--       offerings, the fee schedule and clearance scheme;
--     • staff, their offices and credentials, and the whole payroll (hrm.*);
--     • the encrypted payment-gateway keys and the mail/SMS settings;
--     • the audit spine — every deletion below is recorded on it, attributed.
--
--   IT IS NOT A MIGRATION. Flyway does not run it. An operator runs it by hand
--   against a database they mean to reset, AFTER TAKING A BACKUP:
--
--       psql "$DATABASE_URL" -v confirm=WIPE -f db/reset-admissions.sql
--
--   Then reload the demo accounts and, on the portal, upload the real CAPS list:
--
--       psql "$DATABASE_URL" -f db/demo.sql          (or:  bash db/demo.sh)
--
--   Running it without -v confirm=WIPE refuses and changes nothing. Everything
--   runs in ONE transaction: any error rolls the whole thing back, so a wrong
--   run leaves the database exactly as it was.
-- ═══════════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on

\if :{?confirm}
\else
  \echo ''
  \echo '****  REFUSING TO RUN  ****'
  \echo 'This clears the admission cycle and every student it produced.'
  \echo 'Take a backup, then re-run with:'
  \echo '    psql "$DATABASE_URL" -v confirm=WIPE -f db/reset-admissions.sql'
  \echo ''
  \quit
\endif

SELECT (:'confirm' = 'WIPE') AS ok \gset
\if :ok
\else
  \echo 'The confirm value must be exactly WIPE. Nothing was changed.'
  \quit
\endif

BEGIN;

-- every deletion is an attributed act on the audit spine (V002)
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'super', true);
SELECT set_config('moaum.reason', 'reset-admissions.sql: cleared the admission cycle and its students for a fresh upload', true);

-- ── credentials, records and services hung on a student (children first) ──
DELETE FROM credentials.certificate;
DELETE FROM credentials.transcript_request;
DELETE FROM records.graduand;
DELETE FROM clearance.item;
DELETE FROM lms.submission_blob;
DELETE FROM lms.submission;
DELETE FROM lms.access;
DELETE FROM platform.request_document_blob;
DELETE FROM platform.request_document;
DELETE FROM platform.service_request;
DELETE FROM health.note;
DELETE FROM health.record_access;
DELETE FROM health.visit;
DELETE FROM health.appointment;
DELETE FROM health.profile;
DELETE FROM finance.wallet_entry;
DELETE FROM finance.nelfund_row;
DELETE FROM finance.nelfund_batch;
DELETE FROM finance.nelfund_status;
DELETE FROM library.reservation;
DELETE FROM library.loan;
DELETE FROM hostel.maintenance_request;
DELETE FROM hostel.allocation;
DELETE FROM hostel.application;
DELETE FROM assessment.result_query;
DELETE FROM registration.attendance;
DELETE FROM credentials.identity_card;

-- ── the gateway day-book that named the students' references (keep the keys) ──
DELETE FROM finance.gateway_event;
DELETE FROM finance.gateway_attempt;
DELETE FROM finance.bank_credit;
DELETE FROM finance.payment_reconciliation;
DELETE FROM finance.refund;

-- ── the student's fees and sign-in ──
DELETE FROM finance.payment_reference;
DELETE FROM iam.student_account;
DELETE FROM iam.student_event;
DELETE FROM people.student_contact;
DELETE FROM platform.session WHERE active_office IN ('applicant', 'student');

-- ── the student's academic record (keep courses, offerings, sheets) ──
DELETE FROM assessment.score;
DELETE FROM registration.entry;
DELETE FROM registration.course_registration;
DELETE FROM people.faculty_list_query;
DELETE FROM people.faculty_list;
DELETE FROM people.biodata_change;
DELETE FROM people.biodata;
DELETE FROM people.document;
DELETE FROM people.status_change;
DELETE FROM people.enrolment;
DELETE FROM people.search_log;
DELETE FROM people.student;
DELETE FROM people.matriculation_run;

-- ── credential issuance artefacts (keep the signing key and blank stock) ──
DELETE FROM credentials.revocation;
DELETE FROM credentials.issued;
DELETE FROM credentials.lookup_miss;

-- ── the admission pipeline itself (keep the policy and the fee amount) ──
DELETE FROM platform.notice;
DELETE FROM admissions.password_reset;
DELETE FROM admissions.clearance_document;
DELETE FROM admissions.application_document_blob;
DELETE FROM admissions.application_document;
DELETE FROM admissions.fee_reference;
DELETE FROM admissions.application;
DELETE FROM admissions.applicant_account;
DELETE FROM admissions.applicant_event;
DELETE FROM admissions.screening_batch;
DELETE FROM admissions.olevel_grade;
DELETE FROM admissions.olevel_sitting;
DELETE FROM admissions.candidate_photo;
DELETE FROM admissions.attachment;
DELETE FROM admissions.candidate;
DELETE FROM admissions.caps_row;
DELETE FROM admissions.caps_row_excluded;
DELETE FROM admissions.caps_batch;

-- ── OPTIONAL: uncomment to restart the admission/matriculation/receipt numbers
--    from one. Leave commented to keep them continuing from the last issued.
-- DELETE FROM platform.number_series
--  WHERE kind IN ('ADMISSION', 'MATRICULATION', 'RECEIPT');

DO $$
BEGIN
    RAISE NOTICE 'admissions reset complete: % candidates, % applications, % students remain',
        (SELECT count(*) FROM admissions.candidate),
        (SELECT count(*) FROM admissions.application),
        (SELECT count(*) FROM people.student);
END $$;

COMMIT;
