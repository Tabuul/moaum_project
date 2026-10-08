-- V359: a late score sheet chased for real; a hostel letter checked by a code of its own.
--
-- 1. Remind and Escalate on a score sheet still waiting for its marks sent nothing: the API answered 202 "the notification
--    module is not on the portal yet". Now the desk's reminder goes to the lecturer of record, and an escalation to the
--    Head of Department of the course's department in its first five days late and to the Dean of its faculty after (the
--    rule the monitor has always shown; a GST or EPS course to its own office), the lecturer told it was escalated. Each is
--    sent by email and by text to whatever the person has on record — the staff register carries phones, few emails — and
--    each is kept: who chased, from which office, when, how late, how many marks were missing, and how many were told, so
--    the sheet lists show it and the lecturer sees it on their own sheets. Only a sheet at entry is chased; an escalation
--    only once it is past its due date; each kind at most once a day on a sheet. Nothing about a sheet or a mark changes.
-- 2. The public hostel verification page answered the student's name, photograph, hall, room and bed for any allocation
--    reference — and the references run in sequence. Each allocation now has a random check code; the letter and the
--    clearance certificate carry it in their QR, and the page shows the record only when the code matches. Without it the
--    page names no one and does not say whether the reference exists. A letter printed before this has no code: the
--    student prints it again from the portal.
BEGIN;

-- ── 1 · a late score sheet chased ────────────────────────────────────────────────────────────────────────────────
CREATE TABLE assessment.sheet_chase (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id     uuid NOT NULL REFERENCES assessment.score_sheet(id),
    kind         text NOT NULL CHECK (kind IN ('REMIND', 'ESCALATE')),
    due_on       date NULL,
    days_late    int NULL CHECK (days_late IS NULL OR days_late > 0),
    expected     int NOT NULL,
    missing      int NOT NULL,
    to_office    text NULL REFERENCES ref.office(code),
    told         int NOT NULL CHECK (told >= 0),
    told_names   text NULL,
    note         text NULL CHECK (note IS NULL OR length(note) <= 500),
    sent_by      uuid NOT NULL,
    sent_office  text NOT NULL,
    sent_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_chase_escalation CHECK ((kind = 'ESCALATE') = (to_office IS NOT NULL)),
    CONSTRAINT ck_chase_late CHECK (kind = 'REMIND' OR days_late IS NOT NULL)
);
CREATE INDEX ix_sheet_chase ON assessment.sheet_chase (sheet_id, sent_at DESC);
SELECT audit.attach('assessment.sheet_chase');
COMMENT ON TABLE assessment.sheet_chase IS 'V359: a score sheet at entry reminded to its lecturer, or escalated to the Head of Department or the Dean — what was sent, to how many, by whom.';

/* the office a late sheet is escalated to: its general office (GST, EPS) when it has one; otherwise the Head of
   Department in the first five days late and the Dean after — the rule the monitor has always shown */
CREATE OR REPLACE FUNCTION assessment.chase_office(p_days_late int, p_general_office text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_days_late IS NULL OR p_days_late <= 0 THEN NULL
                WHEN nullif(btrim(p_general_office), '') IS NOT NULL THEN lower(btrim(p_general_office))
                WHEN p_days_late < 6 THEN 'hod'
                ELSE 'dean' END
$$;

/* the email and phone a member of staff has on record: the person's own, else the staff profile's */
CREATE OR REPLACE FUNCTION assessment.staff_reach(p_person uuid)
RETURNS TABLE (name text, email text, phone text) LANGUAGE sql STABLE AS $$
    SELECT trim(coalesce(p.given_names, '') || ' ' || p.surname),
           coalesce(nullif(btrim(p.email), ''), nullif(btrim(sp.email), '')),
           coalesce(nullif(btrim(p.phone), ''), nullif(btrim(sp.phone), ''))
      FROM iam.person p LEFT JOIN hrm.staff_profile sp ON sp.person_id = p.id
     WHERE p.id = p_person
$$;

/* the reminder or the escalation, sent and kept; the desk's office and person from the audit context */
CREATE OR REPLACE FUNCTION assessment.chase_sheet(p_sheet uuid, p_kind text, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office text := nullif(current_setting('moaum.actor_office', true), '');
    s record; cov record; r record; lr record;
    v_late int; v_to text; v_to_label text; v_last timestamptz; v_sem text; v_what text; v_note text := nullif(btrim(p_note), '');
    v_told int := 0; v_names text[] := ARRAY[]::text[]; v_holders int := 0; v_body text; v_sms text; v_id uuid;
BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('REMIND', 'ESCALATE') THEN
        RAISE EXCEPTION 'RESULT_CHASE_KIND: a late score sheet is reminded or escalated' USING ERRCODE = 'check_violation';
    END IF;
    IF v_actor IS NULL OR v_office IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_ACTOR: a reminder is sent by a desk, signed in' USING ERRCODE = 'check_violation';
    END IF;
    IF v_office = 'lecturer' THEN
        RAISE EXCEPTION 'RESULT_CHASE_DESK: a lecturer is reminded by the desks and does not chase a sheet' USING ERRCODE = 'check_violation';
    END IF;
    IF v_note IS NOT NULL AND length(v_note) > 500 THEN
        RAISE EXCEPTION 'RESULT_CHASE_NOTE: a note to the reminder is at most five hundred characters' USING ERRCODE = 'check_violation';
    END IF;
    SELECT sh.id, sh.stage, sh.due_on, o.course_code, coalesce(o.title, cr.title) AS title, o.session, o.semester, o.lecturer_id,
           cr.dept_code, d.name AS dept_name, d.faculty_code, f.name AS faculty_name, cr.general_office
      INTO s
      FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id JOIN catalogue.course cr ON cr.code = o.course_code
      LEFT JOIN ref.department d ON d.code = cr.dept_code LEFT JOIN ref.faculty f ON f.code = d.faculty_code
     WHERE sh.id = p_sheet
       FOR UPDATE OF sh;
    IF s.id IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_SHEET: no such score sheet' USING ERRCODE = 'check_violation';
    END IF;
    IF s.stage <> 'ENTRY' THEN
        RAISE EXCEPTION 'RESULT_CHASE_NOT_AT_ENTRY: % is at % — only a sheet still waiting for its marks is chased', s.course_code, lower(replace(s.stage, '_', ' '))
            USING ERRCODE = 'check_violation';
    END IF;
    IF s.lecturer_id IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_NO_LECTURER: no lecturer is allocated to % in %; allocate one, and the sheet is theirs to fill', s.course_code, s.session
            USING ERRCODE = 'check_violation';
    END IF;
    v_late := CASE WHEN s.due_on IS NOT NULL AND s.due_on < current_date THEN current_date - s.due_on END;
    IF p_kind = 'ESCALATE' AND v_late IS NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_NOT_LATE: % is not past its due date (%) — remind the lecturer; a sheet is escalated only once it is late',
            s.course_code, coalesce(to_char(s.due_on, 'DD Mon YYYY'), 'none set') USING ERRCODE = 'check_violation';
    END IF;
    SELECT max(c.sent_at) INTO v_last FROM assessment.sheet_chase c WHERE c.sheet_id = p_sheet AND c.kind = p_kind AND c.sent_at > now() - interval '1 day';
    IF v_last IS NOT NULL THEN
        RAISE EXCEPTION 'RESULT_CHASE_TOO_SOON: % was % at % today or yesterday; a sheet is % at most once a day',
            s.course_code, CASE p_kind WHEN 'REMIND' THEN 'reminded' ELSE 'escalated' END,
            to_char(v_last AT TIME ZONE 'Africa/Lagos', 'HH24:MI DD Mon'), CASE p_kind WHEN 'REMIND' THEN 'reminded' ELSE 'escalated' END
            USING ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO cov FROM assessment.sheet_coverage(p_sheet);
    v_sem := CASE s.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE s.semester::text END;
    v_what := s.course_code || ' — ' || s.title || ' (' || s.session || ', ' || v_sem || ' semester)';
    SELECT * INTO lr FROM assessment.staff_reach(s.lecturer_id);

    IF p_kind = 'REMIND' THEN
        v_body := 'Dear ' || coalesce(lr.name, 'colleague') || E',\n\n'
            || 'The score sheet for ' || v_what || ' is '
            || CASE WHEN v_late IS NOT NULL THEN v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' past its due date of ' || to_char(s.due_on, 'DD Mon YYYY')
                    WHEN s.due_on IS NOT NULL THEN 'due on ' || to_char(s.due_on, 'DD Mon YYYY')
                    ELSE 'waiting for its marks' END
            || '. ' || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || ' candidates are still without a mark.'
            || E'\n\nPlease enter the marks and submit the sheet on the University portal (Results › My score sheets).'
            || CASE WHEN v_note IS NOT NULL THEN E'\n\nFrom the desk: ' || v_note ELSE '' END
            || E'\n\nExaminations and Records';
        v_sms := 'MOAUM: your ' || s.course_code || ' score sheet (' || s.session || ', ' || v_sem || ' sem.) '
            || CASE WHEN v_late IS NOT NULL THEN 'is ' || v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' late' ELSE 'is awaited' END
            || '; ' || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || ' marks not in. Please submit it on the portal.';
        IF lr.email IS NOT NULL THEN PERFORM platform.queue_notice('EMAIL', lr.email, 'Your score sheet for ' || s.course_code || ' is awaited', v_body, 'score_sheet', p_sheet); END IF;
        IF lr.phone IS NOT NULL THEN PERFORM platform.queue_notice('SMS', lr.phone, 'Score sheet reminder', v_sms, 'score_sheet', p_sheet); END IF;
        IF lr.email IS NOT NULL OR lr.phone IS NOT NULL THEN v_told := 1; v_names := ARRAY[lr.name]; END IF;
    ELSE
        v_to := assessment.chase_office(v_late, s.general_office);
        SELECT coalesce(label, v_to) INTO v_to_label FROM ref.office WHERE code = v_to;
        v_body := 'The score sheet for ' || v_what || ', lecturer ' || coalesce(lr.name, 'of record') || ', is '
            || v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' past its due date of ' || to_char(s.due_on, 'DD Mon YYYY') || '. '
            || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || ' candidates are still without a mark'
            || coalesce(' (reminded ' || (SELECT count(*) FROM assessment.sheet_chase c WHERE c.sheet_id = p_sheet AND c.kind = 'REMIND')::text || ' time(s), last on '
                        || (SELECT to_char(max(c.sent_at) AT TIME ZONE 'Africa/Lagos', 'DD Mon') FROM assessment.sheet_chase c WHERE c.sheet_id = p_sheet AND c.kind = 'REMIND') || ')', '')
            || E'.\n\nThe desk asks you to follow it up with the lecturer, so the department''s results are not held.'
            || CASE WHEN v_note IS NOT NULL THEN E'\n\nFrom the desk: ' || v_note ELSE '' END
            || E'\n\nExaminations and Records';
        v_sms := 'MOAUM: the ' || s.course_code || ' score sheet (' || coalesce(lr.name, 'lecturer') || ') is ' || v_late || ' day'
            || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' late; ' || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0)
            || ' marks not in. Please follow it up.';
        FOR r IN SELECT DISTINCT a.person_id FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
                  WHERE a.office_code = v_to AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND p.ended_on IS NULL
                    AND (v_to NOT IN ('hod', 'dean')
                         OR (v_to = 'hod' AND a.scope_kind = 'department' AND a.scope_id = s.dept_code)
                         OR (v_to = 'dean' AND a.scope_kind = 'faculty' AND a.scope_id = s.faculty_code)) LOOP
            DECLARE h record;
            BEGIN
                SELECT * INTO h FROM assessment.staff_reach(r.person_id);
                v_holders := v_holders + 1;
                IF h.email IS NOT NULL THEN
                    PERFORM platform.queue_notice('EMAIL', h.email, 'A late score sheet: ' || s.course_code, 'Dear ' || coalesce(h.name, 'colleague') || E',\n\n' || v_body, 'score_sheet', p_sheet);
                END IF;
                IF h.phone IS NOT NULL THEN PERFORM platform.queue_notice('SMS', h.phone, 'Late score sheet', v_sms, 'score_sheet', p_sheet); END IF;
                IF h.email IS NOT NULL OR h.phone IS NOT NULL THEN v_told := v_told + 1; v_names := v_names || h.name; END IF;
            END;
        END LOOP;
        IF v_holders = 0 THEN
            RAISE EXCEPTION 'RESULT_CHASE_NO_HOLDER: no % is posted over % — the escalation would reach no one; post one on Users & Roles',
                coalesce(v_to_label, v_to), CASE v_to WHEN 'hod' THEN coalesce(s.dept_name, s.dept_code) WHEN 'dean' THEN coalesce(s.faculty_name, s.faculty_code) ELSE 'the course' END
                USING ERRCODE = 'check_violation';
        END IF;
        -- the lecturer is told it was escalated, and to whom
        IF lr.email IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', lr.email, 'Your score sheet for ' || s.course_code || ' has been escalated',
                'Dear ' || coalesce(lr.name, 'colleague') || E',\n\nThe score sheet for ' || v_what || ' is ' || v_late || ' day' || CASE WHEN v_late = 1 THEN '' ELSE 's' END
                || ' past its due date, and the desk has referred it to the ' || coalesce(v_to_label, v_to) || '. '
                || coalesce(cov.missing, 0) || ' of ' || coalesce(cov.expected, 0) || E' candidates are still without a mark.\n\nPlease enter the marks and submit the sheet on the University portal.'
                || E'\n\nExaminations and Records', 'score_sheet', p_sheet);
        END IF;
        IF lr.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', lr.phone, 'Score sheet escalated', 'MOAUM: your ' || s.course_code || ' score sheet is ' || v_late || ' day'
                || CASE WHEN v_late = 1 THEN '' ELSE 's' END || ' late and has been referred to the ' || coalesce(v_to_label, v_to) || '. Please submit it on the portal.', 'score_sheet', p_sheet);
        END IF;
    END IF;

    INSERT INTO assessment.sheet_chase (sheet_id, kind, due_on, days_late, expected, missing, to_office, told, told_names, note, sent_by, sent_office)
    VALUES (p_sheet, p_kind, s.due_on, v_late, coalesce(cov.expected, 0), coalesce(cov.missing, 0), v_to, v_told,
            nullif(array_to_string(v_names, ', '), ''), v_note, v_actor, v_office)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id, 'kind', p_kind, 'courseCode', s.course_code, 'daysLate', v_late, 'expected', coalesce(cov.expected, 0),
        'missing', coalesce(cov.missing, 0), 'toOffice', v_to, 'toOfficeLabel', v_to_label, 'told', v_told, 'toldNames', nullif(array_to_string(v_names, ', '), ''),
        'lecturer', lr.name, 'lecturerReachable', lr.email IS NOT NULL OR lr.phone IS NOT NULL);
END $$;
COMMENT ON FUNCTION assessment.chase_sheet(uuid, text, text) IS 'V359: a score sheet at entry reminded to its lecturer, or (late) escalated to the Head of Department, the Dean or its general office — sent by email and text to what each has on record, and kept.';

/* each sheet's chasing in one row: how often reminded and escalated, when last, and to which office */
CREATE OR REPLACE FUNCTION assessment.chase_summary(p_sheets uuid[])
RETURNS TABLE (sheet_id uuid, reminders int, reminded_at timestamptz, escalations int, escalated_at timestamptz, escalated_to text)
LANGUAGE sql STABLE AS $$
    SELECT c.sheet_id,
           (count(*) FILTER (WHERE c.kind = 'REMIND'))::int, max(c.sent_at) FILTER (WHERE c.kind = 'REMIND'),
           (count(*) FILTER (WHERE c.kind = 'ESCALATE'))::int, max(c.sent_at) FILTER (WHERE c.kind = 'ESCALATE'),
           (SELECT coalesce(o.label, x.to_office) FROM assessment.sheet_chase x LEFT JOIN ref.office o ON o.code = x.to_office
             WHERE x.sheet_id = c.sheet_id AND x.kind = 'ESCALATE' ORDER BY x.sent_at DESC LIMIT 1)
      FROM assessment.sheet_chase c
     WHERE c.sheet_id = ANY(p_sheets)
     GROUP BY c.sheet_id
$$;

-- ── 2 · a hostel letter checked by its own code ─────────────────────────────────────────────────────────────────
ALTER TABLE hostel.allocation ADD COLUMN verify_code text NOT NULL DEFAULT encode(gen_random_bytes(9), 'hex');
ALTER TABLE hostel.allocation ADD CONSTRAINT ck_allocation_verify_code CHECK (verify_code ~ '^[0-9a-f]{18}$');
COMMENT ON COLUMN hostel.allocation.verify_code IS 'V359: the random check code the allocation letter and the clearance certificate carry in their QR; the public page shows the record only when it matches.';

GRANT SELECT ON assessment.sheet_chase TO app_auditor;

-- the University's reset (V327, last V358) clears the chasing of score sheets with the sheets
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
