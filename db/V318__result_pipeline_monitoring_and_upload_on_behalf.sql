-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V318 — result pipeline monitoring, live broadsheet coverage, and a score sheet uploaded on behalf
--
--   The nine-stage chain (V013: ENTRY → VERIFICATION → DEPT_BOARD → FACULTY_SCRUTINY →
--   FACULTY_COMPILATION → FACULTY_BOARD → RECORDS → SENATE → PUBLISHED) is kept exactly as it is.
--   This migration adds what monitoring it needs and what an upload on behalf of a lecturer records:
--
--     · assessment.sheet_coverage(sheet) — what a sheet expects (its roll), has received (a mark or an
--       outcome on the latest version) and still lacks: the figures the pipeline, the live broadsheet
--       and the Head of Department's monitor read, counted from the roll, never typed;
--     · assessment.sheet_stage_since(sheet) — when the sheet arrived at its present stage, so a set
--       that has stalled on a desk can be seen for how long;
--     · assessment.score.entered_by / entered_office — who actually wrote each version of a mark, in
--       which office, filled by a trigger from the attributed transaction; on_behalf and
--       on_behalf_reason — true, with its reason, when the writer is not a teacher of the course;
--     · assessment.sheet_upload — the record of each upload on behalf: the uploader, their office,
--       the lecturer of record at the time (the academic owner), the mandatory reason, the rows written;
--     · assessment.teaches(sheet, person) — the lecturer, the second examiner or a co-lecturer of the
--       sheet's offering: the rule that says whether an entry is the lecturer's own or on their behalf.
--
--   Nothing bypasses the chain: an upload on behalf writes marks at ENTRY and the sheet moves on only
--   by the same assessment.advance, under the same rule that no two consecutive stages are one
--   person's (BR-006).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V318: result pipeline monitoring and upload on behalf', true);

/* ── 1 · who wrote each mark, and on whose behalf ───────────────────────────────────────────────── */
ALTER TABLE assessment.score
    ADD COLUMN IF NOT EXISTS entered_by       uuid    NULL,
    ADD COLUMN IF NOT EXISTS entered_office   text    NULL,
    ADD COLUMN IF NOT EXISTS on_behalf        boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS on_behalf_reason text    NULL;
ALTER TABLE assessment.score DROP CONSTRAINT IF EXISTS ck_score_on_behalf_says_why;
ALTER TABLE assessment.score ADD CONSTRAINT ck_score_on_behalf_says_why
    CHECK (NOT on_behalf OR (on_behalf_reason IS NOT NULL AND btrim(on_behalf_reason) <> ''));
COMMENT ON COLUMN assessment.score.entered_by IS 'V318: the person who wrote this version of the mark (the attributed actor), whoever the lecturer of record is';
COMMENT ON COLUMN assessment.score.entered_office IS 'V318: the office the writer acted in';
COMMENT ON COLUMN assessment.score.on_behalf IS 'V318: true when the writer is not a teacher of the course — an upload on behalf of the lecturer, which carries its reason';
COMMENT ON COLUMN assessment.score.on_behalf_reason IS 'V318: why the mark was entered on the lecturer''s behalf; required when on_behalf';

CREATE OR REPLACE FUNCTION assessment.score_writer()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.entered_by IS NULL THEN
        NEW.entered_by := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    END IF;
    IF NEW.entered_office IS NULL THEN
        NEW.entered_office := nullif(current_setting('moaum.actor_office', true), '');
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_score_writer ON assessment.score;
CREATE TRIGGER trg_score_writer BEFORE INSERT ON assessment.score
    FOR EACH ROW EXECUTE FUNCTION assessment.score_writer();

/* ── 2 · a teacher of the sheet's offering: the lecturer, the second examiner, a co-lecturer ────── */
CREATE OR REPLACE FUNCTION assessment.teaches(p_sheet uuid, p_person uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id
         WHERE s.id = p_sheet AND p_person IS NOT NULL
           AND (o.lecturer_id = p_person OR o.second_examiner_id = p_person
                OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = p_person)))
$$;
COMMENT ON FUNCTION assessment.teaches(uuid, uuid) IS
  'V318: true when the person is the lecturer, the second examiner or a co-lecturer of the sheet''s offering — an entry by anyone else is on the lecturer''s behalf.';

/* ── 3 · the record of an upload on behalf ──────────────────────────────────────────────────────── */
CREATE TABLE IF NOT EXISTS assessment.sheet_upload (
    id              uuid        PRIMARY KEY,
    sheet_id        uuid        NOT NULL REFERENCES assessment.score_sheet(id),
    uploaded_by     uuid        NOT NULL,
    uploader_office text        NOT NULL,
    owner_id        uuid        NULL,
    reason          text        NOT NULL,
    rows_written    int         NOT NULL DEFAULT 0,
    uploaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sheet_upload_says_why CHECK (btrim(reason) <> '')
);
CREATE INDEX IF NOT EXISTS ix_sheet_upload_sheet ON assessment.sheet_upload (sheet_id, uploaded_at DESC);
COMMENT ON TABLE assessment.sheet_upload IS
  'V318: each upload of marks on behalf of a lecturer — who uploaded (the actual uploader), in which office, the lecturer of record at the time (the academic owner), why, and how many rows. The marks themselves are on assessment.score with on_behalf and the reason.';
SELECT audit.attach('assessment.sheet_upload');

CREATE OR REPLACE FUNCTION assessment.record_upload_on_behalf(p_sheet uuid, p_reason text, p_rows int)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_owner uuid; v_stage text; v_id uuid := gen_random_uuid();
BEGIN
    SELECT o.lecturer_id, s.stage INTO v_owner, v_stage
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id WHERE s.id = p_sheet;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    IF v_stage <> 'ENTRY' THEN
        RAISE EXCEPTION 'RES_SHEET_NOT_AT_ENTRY: the sheet is at %; marks are entered only at entry', lower(v_stage)
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'RES_UPLOAD_ON_BEHALF_SAYS_WHY: an upload on behalf of the lecturer carries its reason'
            USING ERRCODE = 'check_violation',
                  HINT = 'Say why the lecturer is not entering the marks themselves; it is written on the record beside your name.';
    END IF;
    IF assessment.teaches(p_sheet, v_actor) THEN
        RAISE EXCEPTION 'RES_NOT_ON_BEHALF: you teach this course; the marks are entered as its lecturer, not on behalf'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.sheet_upload (id, sheet_id, uploaded_by, uploader_office, owner_id, reason, rows_written)
    VALUES (v_id, p_sheet, v_actor, v_office, v_owner, btrim(p_reason), coalesce(p_rows, 0));
    RETURN v_id;
END $$;
COMMENT ON FUNCTION assessment.record_upload_on_behalf(uuid, text, int) IS
  'V318: records an upload of marks on behalf of the lecturer: refused without a reason, refused when the actor teaches the course, refused off entry. Returns the upload id.';

/* ── 4 · coverage: what a sheet expects, has received, and still lacks ──────────────────────────── */
CREATE OR REPLACE FUNCTION assessment.sheet_coverage(p_sheet uuid)
RETURNS TABLE (expected bigint, received bigint, missing bigint, graded bigint)
LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT student_id FROM assessment.sheet_candidates(p_sheet)),
         l AS (SELECT student_id, outcome FROM assessment.latest_scores(p_sheet))
    SELECT (SELECT count(*) FROM c),
           (SELECT count(*) FROM c JOIN l USING (student_id)),
           (SELECT count(*) FROM c WHERE NOT EXISTS (SELECT 1 FROM l WHERE l.student_id = c.student_id)),
           (SELECT count(*) FROM c JOIN l USING (student_id) WHERE l.outcome = 'GRADED')
$$;
COMMENT ON FUNCTION assessment.sheet_coverage(uuid) IS
  'V318: the sheet''s roll (expected), the candidates on it with a mark or an outcome (received), those still without (missing), and those graded — counted from the roll and the latest version of each mark.';

/* ── 5 · an offering serves a programme: offered to it on the structure, or a student of it is on the roll ─── */
CREATE OR REPLACE FUNCTION catalogue.offering_serves(p_offering uuid, p_prog text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course_offer cf ON cf.course_code = o.course_code
                    WHERE o.id = p_offering AND cf.programme_code = p_prog)
        OR EXISTS (SELECT 1 FROM registration.entry e
                     JOIN registration.course_registration r ON r.id = e.registration_id
                     JOIN people.student st ON st.id = r.student_id
                    WHERE e.offering_id = p_offering AND st.programme_code = p_prog
                      AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED'))
$$;
COMMENT ON FUNCTION catalogue.offering_serves(uuid, text) IS
  'V318: true when the offering is the programme''s business — its course is offered to the programme on the structure, or a student of the programme holds an approved registration on it (a borrowed course). The Programme Examinations Officer''s scope, and the programme filter of the result desks.';

/* ── 6 · when the sheet arrived at its present stage ────────────────────────────────────────────── */
CREATE OR REPLACE FUNCTION assessment.sheet_stage_since(p_sheet uuid)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT max(d.decided_at) FROM assessment.decision d JOIN assessment.score_sheet s ON s.id = d.sheet_id
          WHERE d.sheet_id = p_sheet AND d.to_stage = s.stage),
        (SELECT es.opened_at FROM assessment.score_sheet s JOIN assessment.exam_session es ON es.id = s.exam_session_id
          WHERE s.id = p_sheet))
$$;
COMMENT ON FUNCTION assessment.sheet_stage_since(uuid) IS
  'V318: when the sheet reached the stage it is at now — the last decision into that stage, or, for a sheet still at entry, when its examination session was opened.';


/* ── 7 · the Super Administrator's data reset clears the uploads on behalf with the sheets they hang on ──
   The reset (V292) names every operational table it clears; a table that references one of them and is not
   named would stop it on a foreign key, and the property suite checks exactly that. The function is restated
   here as V292 left it, with assessment.sheet_upload cleared before assessment.score. */
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
    DELETE FROM assessment.sheet_upload;   -- V318: the uploads on behalf hang on the sheets
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

COMMIT;
