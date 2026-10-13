-- ═══════════════════════════════════════
-- V416 — clearance read for whole lists at once, and the offices told what waits on them
--
--   V415 made final clearance a workflow on the convocation purpose, so clearance.position works out the student's
--   stages (which apply, which are open) where it used to read eight rows. The graduation list, the certificates office's
--   list of graduands awaiting a certificate and the Records clearance list asked it once per student — a convocation list
--   of thousands, or the whole register, one workflow at a time. And an office learnt of a student waiting on it only by
--   opening its desk. So:
--
--     · clearance.unit_states(purpose, students[]) — the word of every unit or stage on many students in one pass, as
--       clearance.position reads it (the workflow's stages when the purpose has an active one, the eight units otherwise),
--       with whether each holds the student; clearance.cleared_many(purpose, students[]) — cleared or not, and how many
--       hold, for each. The lists read these instead of a call per row;
--     · clearance.office_people(unit, student) — who signs a stage for a student: the unit's office (and the Faculty
--       Officer beside the Dean, Housing beside Student Services for the hostel), a Head of Department over the student's
--       department, a Dean or Faculty Officer over their faculty, the others over the University;
--     · clearance.add_document — as V415's, and a student's upload is now told to the office that asked for it, by e-mail;
--     · clearance.chase_offices() — once a day: a stage open past its deadline (the workflow stage's deadline_days from the
--       clearance's start) and undecided is told to the people who sign it, one e-mail each listing their overdue
--       students, and not again for the same stage within seven days (clearance.chase keeps what was sent).
--
--   platform.reset_operational_data clears clearance.chase with the processes it hangs on (V415's definition otherwise).
--   Nothing is decided, deleted or released here.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V416: clearance read for whole lists, and the offices told of uploads and overdue stages', true);

-- ── 1 · many students at once, as every gate reads one ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.unit_states(p_purpose text, p_students uuid[])
RETURNS TABLE (student_id uuid, unit text, label text, ord int, state text, holds boolean)
LANGUAGE sql STABLE AS $$
    SELECT r.student_id, r.unit, r.label, r.ord, r.state, (r.required AND r.applies AND r.state <> 'CLEARED')
      FROM clearance.stage_rows(p_purpose, NULL, p_students) r
     WHERE EXISTS (SELECT 1 FROM clearance.workflow w WHERE w.purpose = p_purpose AND w.active)
    UNION ALL
    SELECT x.id, u.code, u.label, u.ord, coalesce(l.state, 'HELD'), coalesce(l.state, 'HELD') <> 'CLEARED'
      FROM unnest(p_students) x(id)
     CROSS JOIN clearance.unit u
      LEFT JOIN LATERAL (SELECT c.state FROM clearance.item c
                          WHERE c.student_id = x.id AND c.purpose = p_purpose AND c.unit = u.code AND c.superseded_by IS NULL
                          ORDER BY c.decided_at DESC LIMIT 1) l ON true
     WHERE NOT EXISTS (SELECT 1 FROM clearance.workflow w WHERE w.purpose = p_purpose AND w.active)
$$;
COMMENT ON FUNCTION clearance.unit_states(text, uuid[]) IS
  'V416: the word of every stage (a purpose with an active workflow — NOT_APPLICABLE included, holding only when required, applicable and not cleared) or of the eight units (any other purpose — HELD until a unit clears) on each student given, in one pass; what clearance.position says of one student, for a list.';

CREATE OR REPLACE FUNCTION clearance.cleared_many(p_purpose text, p_students uuid[])
RETURNS TABLE (student_id uuid, cleared boolean, holding int)
LANGUAGE sql STABLE AS $$
    SELECT x.id, coalesce(sum(s.holds::int), 0) = 0, coalesce(sum(s.holds::int), 0)::int
      FROM unnest(p_students) x(id)
      LEFT JOIN clearance.unit_states(p_purpose, p_students) s ON s.student_id = x.id
     GROUP BY x.id
$$;
COMMENT ON FUNCTION clearance.cleared_many(text, uuid[]) IS
  'V416: clearance.is_clear for a list — each student given, whether cleared for the purpose and how many stages or units hold them, in one pass.';

-- ── 2 · who signs a stage for a student ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.office_people(p_unit text, p_student uuid)
RETURNS TABLE (person_id uuid, name text, email text, phone text, office text)
LANGUAGE sql STABLE AS $$
    WITH st AS (
        SELECT p.dept_code, p.faculty_code FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student
    ),
    offices AS (
        SELECT office_code AS o FROM clearance.unit WHERE code = upper(p_unit) AND office_code IS NOT NULL
        UNION SELECT 'facultyofficer' WHERE upper(p_unit) = 'FACULTY'
        UNION SELECT 'housing' WHERE upper(p_unit) = 'HOSTEL'
    )
    SELECT DISTINCT ON (a.person_id) a.person_id, h.name, h.email, h.phone, a.office_code
      FROM iam.office_assignment a
      JOIN iam.person pe ON pe.id = a.person_id
     CROSS JOIN st
     CROSS JOIN LATERAL assessment.staff_reach(a.person_id) h
     WHERE a.office_code IN (SELECT o FROM offices)
       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.ended_on IS NULL
       AND (a.office_code NOT IN ('hod', 'dean', 'facultyofficer')
            OR (a.office_code = 'hod' AND a.scope_kind = 'department' AND a.scope_id = st.dept_code)
            OR (a.office_code IN ('dean', 'facultyofficer') AND a.scope_kind = 'faculty' AND a.scope_id = st.faculty_code))
     ORDER BY a.person_id
$$;
COMMENT ON FUNCTION clearance.office_people(text, uuid) IS
  'V416: who gives a stage''s word on a student — the holders of the unit''s office (with the Faculty Officer for the Faculty stage and Housing for the hostel), a Head of Department only over the student''s department, a Dean or Faculty Officer only over their faculty — with the e-mail and phone their staff record keeps.';

-- ── 3 · a student's upload, told to the office that asked for it ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.add_document(p_process uuid, p_unit text, p_label text, p_file text, p_type text, p_size int,
                                                  p_object uuid, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE q record; v_id uuid; v_unit text := upper(btrim(p_unit)); h record; v_who text; v_number text; v_stage text;
BEGIN
    SELECT p.*, w.purpose, w.label AS wf_label FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process INTO q;
    IF q.id IS NULL OR q.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance under way' USING ERRCODE = '23514'; END IF;
    IF q.completed_at IS NOT NULL THEN RAISE EXCEPTION 'CLR_COMPLETED: % is complete', q.reference USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM clearance.workflow_stage ws WHERE ws.workflow = q.workflow AND ws.unit = v_unit AND ws.active) THEN
        RAISE EXCEPTION 'CLR_NO_STAGE: no % stage', lower(v_unit) USING ERRCODE = '23514';
    END IF;
    INSERT INTO clearance.document (process_id, unit, label, file_name, content_type, size_bytes, object_id, uploaded_by, uploaded_office)
    VALUES (p_process, v_unit, btrim(p_label), btrim(p_file), p_type, p_size, p_object, p_actor, p_office)
    RETURNING id INTO v_id;
    UPDATE clearance.document SET superseded_by = v_id
     WHERE process_id = p_process AND unit = v_unit AND label = btrim(p_label) AND id <> v_id AND superseded_by IS NULL;
    -- V416: the office that asked for it is told a student has uploaded it, and to review it on its desk
    IF p_office = 'student' THEN
        SELECT s.surname || ', ' || s.other_names, coalesce(s.matric_no, s.admission_no) INTO v_who, v_number FROM people.student s WHERE s.id = q.student_id;
        SELECT label INTO v_stage FROM clearance.unit WHERE code = v_unit;
        FOR h IN SELECT * FROM clearance.office_people(v_unit, q.student_id) LOOP
            CONTINUE WHEN h.email IS NULL;
            PERFORM platform.queue_notice('EMAIL', h.email, 'Clearance document to review: ' || btrim(p_label) || ' (' || q.reference || ')',
                'Dear ' || coalesce(h.name, 'colleague') || ',' || E'\n\n' || coalesce(v_who, 'A student') || ' (' || coalesce(v_number, '—') || ') uploaded '
                || btrim(p_label) || ' for the ' || coalesce(v_stage, lower(v_unit)) || ' stage of their ' || lower(q.wf_label) || ' (' || q.reference || ').'
                || E'\n\n' || 'Review it under Student Clearance on the portal.' || E'\n\n' || clearance.signature(),
                'clearance_document', v_id);
        END LOOP;
    END IF;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION clearance.add_document(uuid, text, text, text, text, int, uuid, uuid, text) IS
  'V415: a document for a stage, by the student or an office; one of the same label already there is superseded (kept). V416: a student''s upload is told by e-mail to the people who sign the stage for them.';

-- ── 4 · a stage open past its deadline, chased with the office ───────────────────────────────────────────────────────
CREATE TABLE clearance.chase (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    process_id  uuid NOT NULL REFERENCES clearance.process(id),
    unit        text NOT NULL REFERENCES clearance.unit(code),
    told        int  NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_clr_chase ON clearance.chase (process_id, unit, sent_at DESC);
SELECT audit.exempt('clearance.chase', 'a stage past its deadline told to the office that signs it; written once, read to keep from telling twice in a week');

CREATE OR REPLACE FUNCTION clearance.chase_offices(p_every_days int DEFAULT 7)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE w record; n int := 0; p record;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS clr_overdue (process_id uuid, reference text, student_id uuid, workflow text, unit text, label text, due date) ON COMMIT DROP;
    TRUNCATE clr_overdue;
    FOR w IN SELECT * FROM clearance.workflow WHERE active
               AND EXISTS (SELECT 1 FROM clearance.workflow_stage ws WHERE ws.workflow = code AND ws.active AND ws.deadline_days IS NOT NULL) LOOP
        INSERT INTO clr_overdue
        SELECT q.id, q.reference, q.student_id, w.label, r.unit, r.label, q.started_at::date + r.deadline_days
          FROM clearance.process q
          JOIN clearance.stage_rows(w.purpose, NULL, ARRAY(SELECT x.student_id FROM clearance.process x
                                                             WHERE x.workflow = w.code AND x.cancelled_at IS NULL AND x.completed_at IS NULL)) r
            ON r.student_id = q.student_id AND r.process_id = q.id
         WHERE q.workflow = w.code AND q.cancelled_at IS NULL AND q.completed_at IS NULL
           AND r.deadline_days IS NOT NULL AND r.opened AND r.applies AND r.state IN ('PENDING', 'UNDER_REVIEW')
           AND q.started_at::date + r.deadline_days < current_date
           AND NOT EXISTS (SELECT 1 FROM clearance.chase c WHERE c.process_id = q.id AND c.unit = r.unit
                            AND c.sent_at > now() - make_interval(days => greatest(1, p_every_days)));
    END LOOP;
    -- one e-mail to each person who signs an overdue stage, listing their students
    FOR p IN
        SELECT op.person_id, op.name, op.email, count(*) AS n,
               string_agg(o.workflow || ' · ' || o.label || ': ' || s.surname || ', ' || s.other_names || ' (' || o.reference || ', due ' || to_char(o.due, 'DD Mon') || ')',
                          E'\n' ORDER BY o.due, s.surname) AS lines
          FROM clr_overdue o
          JOIN people.student s ON s.id = o.student_id
         CROSS JOIN LATERAL clearance.office_people(o.unit, o.student_id) op
         WHERE op.email IS NOT NULL
         GROUP BY op.person_id, op.name, op.email
    LOOP
        PERFORM platform.queue_notice('EMAIL', p.email, 'Clearance past its deadline: ' || p.n || ' student' || CASE WHEN p.n = 1 THEN '' ELSE 's' END || ' at your stage',
            'Dear ' || coalesce(p.name, 'colleague') || ',' || E'\n\n' || 'These clearances are waiting on your office past the deadline the Registry set:' || E'\n\n'
            || p.lines || E'\n\n' || 'Give your word under Student Clearance on the portal.' || E'\n\n' || clearance.signature(),
            'clearance_chase', p.person_id);
        n := n + 1;
    END LOOP;
    INSERT INTO clearance.chase (process_id, unit, told)
    SELECT o.process_id, o.unit, (SELECT count(*) FROM clearance.office_people(o.unit, o.student_id) op WHERE op.email IS NOT NULL) FROM clr_overdue o;
    RETURN n;
END $$;
COMMENT ON FUNCTION clearance.chase_offices(int) IS
  'V416: tells each person who signs a clearance stage that is open, undecided and past its deadline (deadline_days from the clearance''s start) — one e-mail each, listing their students — and records the chase so a stage is not chased again within p_every_days (7). Returns how many people were told.';

-- ── 5 · the go-live data reset clears the chases too (V415's definition, restated from the database, with clearance.chase) ──
CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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

    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;
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

    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;
    DELETE FROM clearance.reminder;
    DELETE FROM clearance.document_blob;
    DELETE FROM clearance.document;
    DELETE FROM clearance.chase;
    DELETE FROM clearance.process;
    DELETE FROM clearance.alumni_profile;

    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES and the wallet POLICY, settings, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.legacy_nelfund_reconciliation;   -- V327: the reconciliation hangs on the wallet entries and the students
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.legacy_nelfund_payment;
    DELETE FROM finance.legacy_nelfund_import;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- V358: the amendments of published results, and their decisions, before the queries and sheets they hang on
    DELETE FROM assessment.amendment_decision;
    DELETE FROM assessment.amendment;
    -- V359: the reminders and escalations of score sheets, before the sheets
    DELETE FROM assessment.sheet_chase;
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.legacy_gst_reconciliation;
    DELETE FROM finance.legacy_gst_payment;
    DELETE FROM finance.legacy_gst_import;
    DELETE FROM finance.legacy_student_crosswalk;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    DELETE FROM assessment.sheet_upload;
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_alias;   -- V386: a merged code goes with the course it answers for
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

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

    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $function$;

COMMIT;
