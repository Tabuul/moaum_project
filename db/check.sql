-- ═══════════════════════════════════════════════════════════════════════════
-- The foundation asserts its own properties. Each block prints PASS or FAIL
-- with the property in words, because a check whose failure is a stack trace
-- is a check somebody switches off.
-- ═══════════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP off
\pset pager off
\pset tuples_only on
\pset format unaligned

CREATE OR REPLACE FUNCTION pg_temp.assert(p_name text, p_ok boolean, p_detail text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '%  %  %', CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END,
                 rpad(p_name, 62), p_detail;
    INSERT INTO pg_temp.ran VALUES (p_name);
    IF NOT p_ok THEN
        INSERT INTO pg_temp.failures VALUES (p_name, p_detail);
    END IF;
END $$;

CREATE TEMP TABLE failures (name text, detail text);
-- ── clean up after any previous run ───────────────────────────────────────
-- This script is not read-only: it creates people, policies, credentials and
-- an admission list, and check 10 deliberately tampers with an audit row. Run
-- twice against one database it collided with itself and produced six
-- confusing constraint errors that looked like defects in the schema.
--
-- Rather than require a fresh database and fail obscurely when it does not
-- get one, it removes exactly what it made. Anything the MIGRATIONS seeded —
-- the offices, the 2015 grading scheme — is left alone.
DO $$
BEGIN
    -- The spine refuses an unattributed change, including this one — which is
    -- the mechanism working. The cleanup is an act like any other and says so.
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);

    DELETE FROM audit.entries;
    DELETE FROM audit.chain_head;
    DELETE FROM ref.jamb_alias_name;

    -- V013: the student record the checks build, and nothing the migrations seeded
    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;
    -- course spaces (V035) and requests (V036), before the offerings and students they hang on
    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;
    -- the ticket history is written once; the cleanup is the one maintenance act that removes it (V251)
    PERFORM set_config('moaum.maintenance', 'on', true);
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM extexam.appointment;
    DELETE FROM extexam.invitation;
    DELETE FROM extexam.examiner_file_blob;
    DELETE FROM extexam.examiner_file;
    DELETE FROM extexam.examiner;
    DELETE FROM helpdesk.ticket_attachment_blob;
    DELETE FROM helpdesk.ticket_attachment;
    DELETE FROM helpdesk.ticket_event;
    DELETE FROM helpdesk.ticket_comment;
    DELETE FROM helpdesk.ticket;
    PERFORM set_config('moaum.maintenance', '', true);
    -- health (V032) and the wallet (V033), before the students they name
    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;
    -- payroll (V069), leave (V071), movements (V072), recruitment (V073), appraisal (V074)
    DELETE FROM hrm.applicant;
    DELETE FROM hrm.vacancy;
    DELETE FROM hrm.appraisal;
    DELETE FROM hrm.leave_request;
    DELETE FROM hrm.movement;
    DELETE FROM hrm.payslip;
    DELETE FROM hrm.pay_run;
    DELETE FROM hrm.employment WHERE staff_no LIKE 'CHK-%';
    -- library (V031): loans and reservations before copies and items, before the students they name
    DELETE FROM library.reservation;
    DELETE FROM library.loan;
    DELETE FROM library.copy WHERE accession LIKE 'CHK/%';
    DELETE FROM library.item WHERE title LIKE 'CHECK %';
    -- hostel (V030): allocations before applications, before the students and rooms they hang on
    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;
    DELETE FROM hostel.session_setting WHERE session LIKE '99%';
    DELETE FROM hostel.room WHERE hall_code LIKE 'CHK%';
    DELETE FROM hostel.hall WHERE code LIKE 'CHK%';
    -- the student's services (V027), before the students, sheets and offerings they hang on
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    -- the Bursary's desk (V037/V039): events, attempts, bank credits and gateway keys, before the references and persons they name
    DELETE FROM finance.gateway_credential_event;
    DELETE FROM finance.gateway_credential;
    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    -- payment vouchers (V044): queries and acts before the vouchers they hang on
    DELETE FROM expenditure.voucher_query;
    DELETE FROM expenditure.voucher_act;
    DELETE FROM expenditure.voucher;
    DELETE FROM expenditure.budget;
    DELETE FROM expenditure.bid;
    DELETE FROM expenditure.tender;
    -- procurement, stores and grants (V076)
    DELETE FROM expenditure.requisition;
    DELETE FROM expenditure.store_item;
    DELETE FROM expenditure.asset;
    DELETE FROM expenditure.research_grant;
    -- API consumers and their keys (V047)
    DELETE FROM apimgmt.key;
    DELETE FROM apimgmt.consumer;
    -- the student's side (V026): accounts, contact, fees and references, before the students they hang on
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule WHERE session LIKE '99%';
    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office = 'student';
    DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version WHERE instrument LIKE 'CHECK%');
    DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version WHERE instrument LIKE 'CHECK%');
    DELETE FROM policy.version WHERE instrument LIKE 'CHECK%';

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
    DELETE FROM policy.semester WHERE session IN ('9999/0000', '9998/9999', '9994/9995', '9991/9992', '9992/9993');
    DELETE FROM policy.academic_session WHERE name IN ('9999/0000', '9998/9999', '9994/9995', '9991/9992', '9992/9993');
    DELETE FROM catalogue.course WHERE code = 'ARC 999';
    DELETE FROM platform.number_series WHERE session = '9999/0000';

    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.signing_key;
    DELETE FROM credentials.lookup_miss;

    -- the test session's own policy; the 2025/2026 settings come from a
    -- migration and are left exactly as the Committee issued them
    DELETE FROM admissions.rule_subject WHERE group_id IN (
        SELECT g.id FROM admissions.rule_subject_group g
          JOIN admissions.session_policy p ON p.id = g.policy_id
         WHERE p.session = '9999/0000');
    DELETE FROM admissions.rule_subject_group WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session = '9999/0000');
    DELETE FROM admissions.programme_rule WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session = '9999/0000');
    DELETE FROM admissions.faculty_quota WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session = '9999/0000');
    DELETE FROM admissions.selection_criterion WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session = '9999/0000');
    DELETE FROM admissions.session_policy WHERE session = '9999/0000';

    -- the applicant's journey (V021): the application and everything hung on it, before the candidate
    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;
    DELETE FROM platform.session WHERE active_office = 'applicant';
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.applicant_fee WHERE session IN ('9998/9999', '9999/0000');
    DELETE FROM admissions.screening_exam_programme WHERE session IN ('9997/9998', '9998/9999', '9999/0000');
    DELETE FROM admissions.load_cutoff WHERE session IN ('9996/9997', '9997/9998', '9998/9999', '9999/0000');
    DELETE FROM admissions.programme_closed WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session IN ('9997/9998', '9998/9999', '9999/0000'));
    DELETE FROM admissions.programme_rule WHERE policy_id IN (SELECT id FROM admissions.session_policy WHERE session = '9997/9998');
    DELETE FROM admissions.faculty_quota WHERE policy_id IN (SELECT id FROM admissions.session_policy WHERE session = '9997/9998');
    DELETE FROM admissions.session_policy WHERE session = '9997/9998';

    -- the property session of V020, and the sittings derived from attachments
    DELETE FROM admissions.rule_subject WHERE group_id IN (
        SELECT g.id FROM admissions.rule_subject_group g
          JOIN admissions.session_policy p ON p.id = g.policy_id
         WHERE p.session = '9998/9999');
    DELETE FROM admissions.rule_subject_group WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session = '9998/9999');
    DELETE FROM admissions.programme_rule WHERE policy_id IN
        (SELECT id FROM admissions.session_policy WHERE session = '9998/9999');
    DELETE FROM admissions.session_policy WHERE session = '9998/9999';
    -- the merit-basis fixture's own session (V105 property)
    DELETE FROM admissions.programme_olevel_allowance WHERE policy_id IN (SELECT id FROM admissions.session_policy WHERE session = '9994/9995');
    DELETE FROM admissions.selection_criterion WHERE policy_id IN (SELECT id FROM admissions.session_policy WHERE session = '9994/9995');
    DELETE FROM admissions.programme_rule WHERE policy_id IN (SELECT id FROM admissions.session_policy WHERE session = '9994/9995');
    DELETE FROM admissions.session_policy WHERE session = '9994/9995';
    DELETE FROM admissions.olevel_grade_point WHERE session IN ('9998/9999', '9999/0000', '9994/9995');
    DELETE FROM admissions.olevel_grading WHERE session IN ('9998/9999', '9999/0000', '9994/9995');
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;

    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    DELETE FROM iam.credential_event;
    DELETE FROM iam.credential;
    DELETE FROM iam.sign_in_event;
    DELETE FROM platform.session;
    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;
    DELETE FROM iam.office_assignment;
    DELETE FROM iam.person;

    DELETE FROM policy.clearance_rule;
    DELETE FROM policy.clearance_scheme;
    DELETE FROM policy.grade_band
     WHERE version_id IN (SELECT id FROM policy.version
                           WHERE instrument IN ('SEN/1990/12'));
    DELETE FROM policy.version
     WHERE kind = 'clearance' OR instrument IN ('SEN/1990/12');
END $$;


CREATE TEMP TABLE ran (name text);
\set EXPECTED 175

-- ── 1. no application role holds DELETE, anywhere ─────────────────────────
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM information_schema.role_table_grants
     WHERE privilege_type = 'DELETE' AND grantee LIKE 'app\_%';
    PERFORM pg_temp.assert('No application role holds DELETE on any table', n = 0,
                           n || ' grants found');
END $$;

-- ── 2. no application role can write to the audit spine ───────────────────
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM information_schema.role_table_grants
     WHERE table_schema = 'audit'
       AND privilege_type IN ('INSERT','UPDATE','DELETE')
       AND grantee LIKE 'app\_%';
    PERFORM pg_temp.assert('No application role may write to audit.*', n = 0,
                           n || ' grants found');
END $$;

-- ── 3. all twenty-five offices ────────────────────────────────────────────
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM ref.office;
    PERFORM pg_temp.assert('The office register carries every office',
                           n = 37, n || ' offices (35 staff offices incl. the SIWES Coordinator V156, the School of Postgraduate Studies'' Dean and Secretary V201, the College Finance Controller V227, the MBBS Coordinator V250, the ICT Support Agent V251, the External Examiner V254, the Dean of Student Affairs V290 and the GST and EPS offices V314; the applicant V021 and the student V026)');
END $$;

-- ── 4. a state change with no audit context is REFUSED ────────────────────
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    BEGIN
        INSERT INTO iam.person (id, staff_number, surname, given_names)
        VALUES (gen_random_uuid(), 'STAFF/0001', 'ABUUL', 'Terna');
    EXCEPTION WHEN check_violation THEN
        ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('An unattributed state change is refused by the database',
                           ok, left(msg, 70));
END $$;

-- ── 5. an unknown acting office is refused ────────────────────────────────
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'chancellor', true);
    BEGIN
        INSERT INTO iam.person (id, staff_number, surname, given_names)
        VALUES (gen_random_uuid(), 'STAFF/0002', 'TEST', 'Two');
    EXCEPTION WHEN check_violation THEN
        ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('An acting office not in the register is refused',
                           ok, left(msg, 70));
END $$;

-- ── 6. with context, the write succeeds and is recorded with the office ───
DO $$
DECLARE
    v_actor uuid := gen_random_uuid();
    v_p     uuid := gen_random_uuid();
    n int; office text;
BEGIN
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'A&PC of 18 September', true);

    INSERT INTO iam.person (id, staff_number, surname, given_names)
    VALUES (v_p, 'MOAUM/STAFF/2026/0417', 'IORPUU', 'Terwase David');

    SELECT count(*), max(actor_office) INTO n, office
      FROM audit.entries WHERE subject_id = v_p;

    PERFORM pg_temp.assert('A recorded change carries the office it was made in',
                           n = 1 AND office = 'hrm', n || ' entries, office=' || coalesce(office,'-'));
END $$;

-- ── 7. an office cannot be granted without an instrument ──────────────────
DO $$
DECLARE ok boolean := false; v_p uuid;
BEGIN
    SELECT id INTO v_p FROM iam.person WHERE staff_number = 'MOAUM/STAFF/2026/0417';
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    BEGIN
        INSERT INTO iam.office_assignment
            (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
        VALUES (gen_random_uuid(), v_p, 'hod', 'department', 'MTC', '   ',   -- V325: a department office carries its department
                gen_random_uuid(), current_date);
    EXCEPTION WHEN check_violation OR not_null_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('An office cannot be granted citing no instrument', ok);
END $$;

-- ── 8. an office is ADDED to a person, never substituted ──────────────────
DO $$
DECLARE v_p uuid; n int;
BEGIN
    SELECT id INTO v_p FROM iam.person WHERE staff_number = 'MOAUM/STAFF/2026/0417';
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);

    INSERT INTO iam.office_assignment
        (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
    VALUES (gen_random_uuid(), v_p, 'lecturer', 'course', 'CSC311',
            'APP/2019/0442', gen_random_uuid(), date '2019-10-01'),
           (gen_random_uuid(), v_p, 'hod', 'department', 'MTC',   -- V316: a department scope is a code on the register
            'CNL/2026/91',   gen_random_uuid(), date '2026-09-01');

    SELECT count(*) INTO n FROM iam.office_assignment
     WHERE person_id = v_p AND valid_to IS NULL;
    PERFORM pg_temp.assert('A Head of Department keeps the lecturer office too',
                           n = 2, n || ' live offices');
END $$;

-- ── 9. the chain verifies ─────────────────────────────────────────────────
DO $$
DECLARE bad int; tot bigint;
BEGIN
    SELECT count(*) FILTER (WHERE NOT ok), coalesce(sum(entries), 0)
      INTO bad, tot FROM audit.verify_chain();
    PERFORM pg_temp.assert('The hash chain verifies across every shard',
                           bad = 0, tot || ' entries, ' || bad || ' broken chains');
END $$;

-- ── 10. tampering is DETECTED ─────────────────────────────────────────────
-- Prevention against a superuser is not achievable. Detection is, and this is
-- the check that has to fail on demand or the chain is decoration.
DO $$
DECLARE bad int; broke uuid;
BEGIN
    UPDATE audit.entries
       SET actor_office = 'vc'
     WHERE id = (SELECT id FROM audit.entries ORDER BY occurred_at LIMIT 1);

    SELECT count(*) FILTER (WHERE NOT ok),
           (array_agg(first_break) FILTER (WHERE NOT ok))[1]
      INTO bad, broke FROM audit.verify_chain();
    PERFORM pg_temp.assert('A row altered by a superuser is detected by the chain',
                           bad = 1, 'break at ' || coalesce(broke::text, 'none'));
END $$;

-- ── 11. a state table with no trigger is enumerated ───────────────────────
DO $$
DECLARE n int; lst text;
BEGIN
    SELECT count(*), string_agg(missing, ', ') INTO n, lst FROM audit.unattached();
    PERFORM pg_temp.assert('Every state table is attached to the spine',
                           n = 0, coalesce(lst, 'none unattached'));
END $$;

-- ── 12. a module cannot read another module's schema ──────────────────────
-- ADR-006's headline claim, and the reason the roles exist at all. A query
-- against finance from the registration pool fails with a permission error in
-- development, long before it can fail in production.
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    SET LOCAL ROLE app_registration;
    BEGIN
        PERFORM count(*) FROM iam.person;
    EXCEPTION WHEN insufficient_privilege THEN ok := true; msg := SQLERRM;
    END;
    RESET ROLE;
    PERFORM pg_temp.assert('A module cannot read another module''s schema',
                           ok, left(msg, 60));
END $$;

-- ── 13. an application role cannot forge an audit row ─────────────────────
-- The trigger writes as the schema owner. The calling role must not be able
-- to write a FALSE entry, which is the failure an aspect-with-INSERT allows
-- and a SECURITY DEFINER trigger does not.
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    SET LOCAL ROLE app_iam;
    BEGIN
        INSERT INTO audit.entries (id, occurred_at, period, shard, seq, actor_id,
            actor_office, action, subject_type, subject_id, after_state, entry_hash)
        VALUES (gen_random_uuid(), now(), date_trunc('month', now())::date, 0, 999,
                gen_random_uuid(), 'vc', 'FORGED', 'iam.person',
                gen_random_uuid(), '{}'::jsonb, '\xdead'::bytea);
    EXCEPTION WHEN insufficient_privilege THEN ok := true; msg := SQLERRM;
    END;
    RESET ROLE;
    PERFORM pg_temp.assert('An application role cannot forge an audit entry',
                           ok, left(msg, 60));
END $$;

-- ── 14. nor amend one ─────────────────────────────────────────────────────
DO $$
DECLARE ok boolean := false;
BEGIN
    SET LOCAL ROLE app_iam;
    BEGIN
        UPDATE audit.entries SET actor_office = 'vc';
    EXCEPTION WHEN insufficient_privilege THEN ok := true;
    END;
    RESET ROLE;
    PERFORM pg_temp.assert('An application role cannot amend an audit entry', ok);
END $$;

-- ── 15. policy fails CLOSED while D-Q4 is unanswered ──────────────────────
-- The branch that matters. An empty clearance table defaulting to "allowed"
-- would mean four weeks of Bursary silence had quietly let unpaid students
-- register — and it would look exactly like the system working.
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    BEGIN
        PERFORM policy.clears('REGISTRATION', 2, true, false);
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('With D-Q4 unanswered, clearance refuses rather than assumes',
                           ok, left(msg, 62));
END $$;

-- ── 16. two versions of one policy cannot overlap in time ─────────────────
-- Without this, "which scheme was in force on 14 March" has two answers, and
-- the transcript printed that day cannot be reproduced.
DO $$
DECLARE ok boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    BEGIN
        INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
        VALUES (gen_random_uuid(), 'grading', 'UNIVERSITY',
                daterange(date '2020-01-01', NULL), 'SEN/2020/09', 'registrar');
    EXCEPTION WHEN exclusion_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('Two versions of one policy cannot overlap in time', ok);
END $$;

-- ── 17. a mark falls in exactly one band ──────────────────────────────────
DO $$
DECLARE ok boolean := false; n int;
BEGIN
    SELECT count(*) INTO n FROM generate_series(0,100) m
     WHERE (SELECT count(*) FROM policy.grade_of(m)) <> 1;
    PERFORM pg_temp.assert('Every mark 0-100 resolves to exactly one grade', n = 0,
                           n || ' marks resolve to none or many');
END $$;

-- ── 17a. a mark is held to its course's CA/examination split (V239) ────────
DO $$
DECLARE dept text; o uuid := gen_random_uuid(); sh uuid := gen_random_uuid(); st uuid := gen_random_uuid();
        ca_high boolean := false; ex_high boolean := false; within boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    SELECT code INTO dept FROM ref.department ORDER BY code LIMIT 1;
    -- the suite's session, made here because this check runs before §69 would make it (same dates; §69 tolerates it)
    INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '9999/0000', date '9999-01-01', date '9999-12-31') ON CONFLICT (name) DO NOTHING;
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state, ca_max)
    VALUES ('CHK 901', 'Check Split Thirty Seventy', 3, 1, 100, dept, 'Core', 'LIVE', 30);
    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (o, 'CHK 901', '9999/0000', 1);
    INSERT INTO assessment.score_sheet (id, offering_id) VALUES (sh, o);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990901', 'MOAUM/CHK/99/0901', 'CHECKSPLIT', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    BEGIN INSERT INTO assessment.score (sheet_id, student_id, ca, exam) VALUES (sh, st, 35, 10); EXCEPTION WHEN check_violation THEN ca_high := true; END;
    BEGIN INSERT INTO assessment.score (sheet_id, student_id, ca, exam) VALUES (sh, st, 20, 71); EXCEPTION WHEN check_violation THEN ex_high := true; END;
    INSERT INTO assessment.score (sheet_id, student_id, ca, exam) VALUES (sh, st, 30, 70);
    within := (SELECT total = 100 FROM assessment.latest_scores(sh) WHERE student_id = st);
    PERFORM pg_temp.assert('A mark is held to its course''s CA/examination split: 35 CA on a 30/70 course is refused, 71 examination is refused, 30 + 70 stands',
                           ca_high AND ex_high AND within,
                           format('ca_refused=%s exam_refused=%s within=%s', ca_high, ex_high, within));
END $$;

-- ── 17b. the grace mark: one short of the pass mark is the pass mark ──────
DO $$
DECLARE pass int; g_low text; g_pass text;
BEGIN
    SELECT min(b.low) INTO pass FROM policy.grade_band b
     WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date) AND b.points > 0;
    SELECT grade INTO g_low  FROM policy.grade_of(assessment.grace_total(pass - 2));
    SELECT grade INTO g_pass FROM policy.grade_of(assessment.grace_total(pass - 1));
    PERFORM pg_temp.assert('A total one short of the pass mark is graced to it; two short is not',
                           assessment.grace_total(pass - 1) = pass AND assessment.grace_total(pass - 2) = pass - 2
                           AND assessment.grace_total(pass) = pass AND assessment.grace_total(100) = 100
                           AND g_pass <> g_low,
                           pass - 1 || ' graces to ' || assessment.grace_total(pass - 1) || ' (' || g_pass || '), ' || (pass - 2) || ' stays (' || g_low || ')');
END $$;

-- ── 18. the answer is the one in force on the DATE ASKED ABOUT ────────────
-- A 1994 degree is classified under the 1994 scheme, in 2041.
DO $$
DECLARE v uuid := gen_random_uuid(); g_old text; g_now text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'grading', 'UNIVERSITY', daterange(date '1990-10-01', date '2015-10-01'),
            'SEN/1990/12', 'registrar');
    INSERT INTO policy.grade_band (version_id, grade, low, high, points) VALUES
        (v, 'A', 75, 100, 5.00), (v, 'B', 65, 74, 4.00), (v, 'C', 55, 64, 3.00),
        (v, 'D', 45, 54, 2.00),  (v, 'F',  0, 44, 0.00);

    SELECT grade INTO g_old FROM policy.grade_of(72, date '1994-06-01');
    SELECT grade INTO g_now FROM policy.grade_of(72, date '2026-06-01');

    PERFORM pg_temp.assert('A historical question gets the historical answer',
                           g_old = 'B' AND g_now = 'A',
                           '72 marks: 1994 => ' || g_old || ', 2026 => ' || g_now);
END $$;

-- ── 19. an incomplete clearance scheme is refused ─────────────────────────
-- A purpose left unnamed would resolve to whatever the loader assumes, and an
-- assumption is what the table exists to replace.
DO $$
DECLARE v uuid := gen_random_uuid(); ok boolean := false; msg text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'clearance', 'TEST', daterange(date '2026-10-01', NULL), 'BUR/2026/01', 'bursar');
    INSERT INTO policy.clearance_scheme VALUES (v, true);
    INSERT INTO policy.clearance_rule VALUES (v, 'REGISTRATION', 'INSTALMENT_1');
    BEGIN
        PERFORM policy.assert_scheme_complete(v);
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('A clearance scheme naming only some purposes is refused',
                           ok, left(msg, 58));
END $$;

-- ── 20. once answered, the recommendation behaves as the memo describes ───
-- The August recommendation loaded as data, to show the answer is an INSERT
-- and not a build. If the Bursar marks the page differently, this row set
-- changes and nothing else does.
DO $$
DECLARE v uuid := gen_random_uuid(); r1 boolean; r2 boolean; r3 boolean; r4 boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'clearance', 'UNIVERSITY', daterange(date '2026-10-01', NULL),
            'ICT/MOAUMPP/2026/02 (Directorate assumption, pending the Bursar)', 'bursar');
    INSERT INTO policy.clearance_scheme VALUES (v, true);
    INSERT INTO policy.clearance_rule VALUES
        (v,'REGISTRATION','INSTALMENT_1'), (v,'ID_CARD','INSTALMENT_1'),
        (v,'LIBRARY','INSTALMENT_1'),      (v,'HOSTEL','INSTALMENT_1'),
        (v,'EXAMINATION','INSTALMENT_2'),  (v,'RESULTS','PAID_IN_FULL'),
        (v,'TRANSCRIPT','PAID_IN_FULL'),   (v,'CONVOCATION','PAID_IN_FULL');
    PERFORM policy.assert_scheme_complete(v);

    r1 := policy.clears('REGISTRATION', 1, false, false, date '2026-11-01');
    r2 := policy.clears('EXAMINATION',  1, false, false, date '2026-11-01');
    r3 := policy.clears('RESULTS',      2, true,  false, date '2026-11-01');
    r4 := policy.clears('REGISTRATION', 2, true,  true,  date '2026-11-01');

    PERFORM pg_temp.assert('The recommendation, loaded as data, gates as the memo says',
                           r1 AND NOT r2 AND r3 AND NOT r4,
                           'inst1=>reg ' || r1 || ', inst1=>exam ' || r2 ||
                           ', full=>results ' || r3 || ', arrears=>reg ' || r4);
END $$;

-- ── 21-26. the credential, and what a stranger sees ───────────────────────
DO $$
DECLARE
    k uuid := gen_random_uuid();
    c1 uuid := gen_random_uuid();   -- a good degree
    c2 uuid := gen_random_uuid();   -- one revoked for malpractice
    v jsonb; ok boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);

    INSERT INTO credentials.signing_key (id, algorithm, public_key, custody_ref,
        validity, instrument)
    VALUES (k, 'Ed25519', '\x00'::bytea, 'hsm://moaum-registry/signing/2027',
            daterange(date '2027-01-01', date '2030-01-01'), 'CNL/2026/КEY-01');

    INSERT INTO credentials.issued (id, kind, student_id, verification_code,
        statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office)
    VALUES
     (c1, 'DEGREE_CERTIFICATE', gen_random_uuid(), '1VHBQ-P4CSE-44M5R-ABV9D-F16AM',
      jsonb_build_object('holder','ADAMU, Grace Mwuese','award','B.Sc. (Hons) Computer Science',
                         'classOfDegree','Second Class Honours (Upper Division)'),
      '\xaa'::bytea, k, 'Benue State University, Makurdi', date '2011-11-18',
      gen_random_uuid(), 'registrar'),
     (c2, 'DEGREE_CERTIFICATE', gen_random_uuid(), 'ZZNKF-QGFGX-60BM3-YJ66E-A6TW8',
      jsonb_build_object('holder','OGBU, Terkula Emmanuel','award','LL.B. (Hons) Law',
                         'classOfDegree','Second Class Honours (Lower Division)'),
      '\xbb'::bytea, k, 'Rev. Fr. Moses Orshio Adasu University, Makurdi',
      date '2025-11-18', gen_random_uuid(), 'registrar');

    -- 21. BR-013: a 2011 degree says Benue State University, for ever
    v := credentials.verify('1VHBQ-P4CSE-44M5R-ABV9D-F16AM');
    PERFORM pg_temp.assert('A degree issued under the former name verifies under both',
        v->>'status' = 'VALID'
        AND v->>'issuingInstitution' = 'Benue State University, Makurdi'
        AND v->>'currentInstitutionName' LIKE 'Rev. Fr. Moses%',
        v->>'issuingInstitution');

    -- 22. revoking a degree requires the minute it rests on
    ok := false;
    BEGIN
        INSERT INTO credentials.revocation (credential_id, revoked_on, reason,
            instrument, revoked_by, revoked_office)
        VALUES (c2, current_date, 'Entry qualification found to be forged', '  ',
                gen_random_uuid(), 'registrar');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A degree cannot be revoked citing no instrument', ok);

    -- 23. and no office but the Registrar or the Vice-Chancellor may
    ok := false;
    BEGIN
        INSERT INTO credentials.revocation (credential_id, revoked_on, reason,
            instrument, revoked_by, revoked_office)
        VALUES (c2, current_date, 'Entry qualification found to be forged',
                'SEN/2026/118', gen_random_uuid(), 'super');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('The Super Administrator cannot revoke a degree', ok);

    INSERT INTO credentials.revocation (credential_id, revoked_on, reason,
        instrument, revoked_by, revoked_office)
    VALUES (c2, current_date, 'Entry qualification found to be forged',
            'SEN/2026/118', gen_random_uuid(), 'registrar');

    -- 24. a revoked award RESOLVES to revoked; it does not fail
    v := credentials.verify('ZZNKF-QGFGX-60BM3-YJ66E-A6TW8');
    PERFORM pg_temp.assert('A revoked degree resolves to REVOKED, naming the minute',
        v->>'status' = 'REVOKED' AND v->>'revokedUnder' = 'SEN/2026/118',
        'a failure looks like a fault, and a fault produces a telephone call');

    -- 25. so does a code nobody issued
    v := credentials.verify('AAAAA-BBBBB-CCCCC-DDDDD-EEEEE');
    PERFORM pg_temp.assert('A fabricated code resolves to NOT_FOUND with a remedy',
        v->>'status' = 'NOT_FOUND' AND v ? 'remedy',
        left(v->>'remedy', 46));
END $$;

-- 26. a code checked again and again and never issued is a forged
-- certificate doing the rounds of employers. It is the only signal the
-- University gets, and it costs one query to have.
DO $$
DECLARE n int;
BEGIN
    PERFORM credentials.verify('AAAAA-BBBBB-CCCCC-DDDDD-EEEEE');
    PERFORM credentials.verify('AAAAA-BBBBB-CCCCC-DDDDD-EEEEE');
    SELECT count(*) INTO n FROM credentials.suspected_forgeries();
    PERFORM pg_temp.assert('A code checked repeatedly and never issued is reported',
        n = 1, n || ' suspected forgeries, reported to the Registrar');
END $$;

-- 27. FR-CTP-009, which the module pack requires and enforces nowhere
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    BEGIN
        PERFORM credentials.assert_issuable('DEGREE_CERTIFICATE', true, true, false);
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('No certificate while a clearance item stands', ok, msg);
END $$;

-- ── 28-33. the JAMB admission list ────────────────────────────────────────
DO $$
DECLARE dummy int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    -- JAMB's names are real, from the University's own 2026 workbook. Note
    -- C00019 is Accounting to JAMB, not Computer Science — the codes cannot
    -- be guessed from anything.
    NULL;  -- the programme table is real reference data, seeded by V006
END $$;

DO $$
DECLARE
    b1 uuid := gen_random_uuid(); b2 uuid := gen_random_uuid();
    ok boolean; v_total bigint; msg text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- the Directorate of ICT operates the door; it does not decide who came through
    ok := false;
    BEGIN
        INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
            rows_read, downloaded_on, uploaded_by, uploaded_office)
        VALUES (gen_random_uuid(), '2026/2027', 'CAPS_DOWNLOAD', 'UTME', '\x01'::bytea,
                3, current_date, gen_random_uuid(), 'ict');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('ICT cannot upload an admission list', ok,
        'the Directorate operates the door, it does not decide who came through');

    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
        rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b1, '2026/2027', 'CAPS_DOWNLOAD', 'UTME', '\xAA'::bytea, 3,
            date '2026-09-04', gen_random_uuid(), 'academic');

    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
        surname, other_names, jamb_code, aggregate, entry_mode) VALUES
     (gen_random_uuid(), b1, '2026/2027', '20261184AF', '{}'::jsonb,
      'ODEH', 'Blessing Ngodoo', 'C00019', 281, 'UTME'),
     (gen_random_uuid(), b1, '2026/2027', '20263390BC', '{}'::jsonb,
      'SAAKA', 'Terhemba John', 'C00024', 264, 'UTME'),
     (gen_random_uuid(), b1, '2026/2027', '20261902KD', '{}'::jsonb,
      'ENEJE', 'Onyeka Grace', 'C00033', 298, 'UTME');

    -- 29. the same list downloaded again, as it is every week of the season
    ok := false;
    BEGIN
        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
            surname, other_names, jamb_code, aggregate, entry_mode)
        VALUES (gen_random_uuid(), b1, '2026/2027', '20261184AF', '{}'::jsonb,
                'ODEH', 'Blessing N.', 'C00019', 281, 'UTME');
    EXCEPTION WHEN unique_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('Re-uploading a candidate already on the list is refused',
        ok, 'the list is downloaded again every week; it must not make a second cohort');

    -- 30. nobody is admitted without a CAPS row behind them
    ok := false;
    BEGIN
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
            other_names, programme, entry_mode, entry_level, offer_state)
        VALUES (gen_random_uuid(), '2026/2027', '20269999ZZ', 'GHOST', 'Candidate',
                'B.Sc. Computer Science', 'UTME', 100, 'ADMITTED');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('Nobody is ADMITTED without a CAPS row behind them', ok,
        'this is how an unadmitted person acquires a permanent matriculation number');

    -- 31. the list counts in both directions
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
        other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
    SELECT gen_random_uuid(), r.session, r.jamb_reg_no, r.surname, r.other_names,
           j.name, r.entry_mode, 100, 'ADMITTED', r.id
      FROM admissions.caps_row r JOIN ref.programme j ON j.code = r.jamb_code
     WHERE r.jamb_reg_no <> '20261902KD';

    -- and one the University offered that JAMB never approved
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
        rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b2, '2026/2027', 'CAPS_DOWNLOAD', 'UTME', '\xBB'::bytea, 0,
            date '2026-09-11', gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
        surname, other_names, jamb_code, aggregate, entry_mode)
    VALUES (gen_random_uuid(), b2, '2026/2027', '20265555XY', '{}'::jsonb,
            'ADAKOLE', 'Ene Blessing', 'C00061', 245, 'UTME');
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
        other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
    SELECT gen_random_uuid(), '2026/2027', '20267777QQ', 'UNAPPROVED', 'Offer',
           'B.Sc. Accounting', 'UTME', 100, 'ADMITTED', r.id
      FROM admissions.caps_row r JOIN ref.programme j ON j.code = r.jamb_code
     WHERE r.jamb_reg_no = '20265555XY';

    SELECT sum(x.n) INTO v_total FROM admissions.reconcile('2026/2027') x;
    PERFORM pg_temp.assert('The list is counted in both directions', v_total = 3,
        (SELECT string_agg(x.finding || '=' || x.n, ', ' ORDER BY x.finding)
           FROM admissions.reconcile('2026/2027') x WHERE x.n > 0));

    -- 32. and does not become the record until both counts close
    ok := false;
    BEGIN
        PERFORM admissions.commit_batch(b1);
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('A list that does not reconcile cannot be committed',
        ok, left(msg, 58));
END $$;

-- 33. worked through, it commits — and committing twice is a no-op, because
-- an officer who clicks again must not create a second cohort
DO $$
DECLARE b uuid; r1 text; r2 text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    UPDATE admissions.candidate SET offer_state = 'WITHDRAWN'
     WHERE jamb_reg_no = '20267777QQ';                      -- JAMB never approved it
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
        other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
    SELECT gen_random_uuid(), r.session, r.jamb_reg_no, r.surname, r.other_names,
           j.name, r.entry_mode, 100, 'ADMITTED', r.id
      FROM admissions.caps_row r JOIN ref.programme j ON j.code = r.jamb_code
     WHERE r.jamb_reg_no IN ('20261902KD','20265555XY');    -- the two we had missed

    SELECT id INTO b FROM admissions.caps_batch WHERE file_sha256 = '\xAA'::bytea;
    r1 := admissions.commit_batch(b);
    r2 := admissions.commit_batch(b);
    PERFORM pg_temp.assert('Once worked it commits, and committing twice is a no-op',
        r1 = 'committed' AND r2 = 'already committed', r1 || ' / ' || r2);
END $$;

-- ── 34-36. UTME and Direct Entry are two lists, and must stay two ─────────
DO $$
DECLARE b uuid := gen_random_uuid(); ok boolean; msg text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
        rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b, '2026/2027', 'CAPS_DOWNLOAD', 'DIRECT_ENTRY', '\xDE'::bytea, 1,
            date '2026-10-02', gen_random_uuid(), 'academic');

    -- 34. a UTME row inside a batch declared Direct Entry
    ok := false;
    BEGIN
        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
            surname, other_names, jamb_code, aggregate, entry_mode)
        VALUES (gen_random_uuid(), b, '2026/2027', '20268888UT', '{}'::jsonb,
                'WRONG', 'List Entirely', 'C51900', 271, 'UTME');
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('A UTME row in a Direct Entry batch is refused', ok, msg);

    -- 35. a DE row carrying a UTME score means the files were mixed
    ok := false;
    BEGIN
        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
            surname, other_names, jamb_code, aggregate, entry_mode)
        VALUES (gen_random_uuid(), b, '2026/2027', '20265502DE', '{}'::jsonb,
                'TSAVNANDE', 'Doosuur Patience', 'C49412',
                240, 'DIRECT_ENTRY');
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('A Direct Entry row carrying a UTME score is refused',
        ok, 'DE candidates do not sit the UTME');

    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
        surname, other_names, jamb_code, entry_mode)
    VALUES (gen_random_uuid(), b, '2026/2027', '20265502DE', '{}'::jsonb,
            'TSAVNANDE', 'Doosuur Patience', 'C49412', 'DIRECT_ENTRY');

    -- 36. and a DE candidate cannot be placed at 100 Level
    ok := false;
    BEGIN
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
            other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
        SELECT gen_random_uuid(), r.session, r.jamb_reg_no, r.surname, r.other_names,
               j.name, r.entry_mode, 100, 'ADMITTED', r.id
          FROM admissions.caps_row r JOIN ref.programme j ON j.code = r.jamb_code
         WHERE r.jamb_reg_no = '20265502DE';
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A Direct Entry candidate cannot be placed at 100 Level',
        ok, 'they would repeat a year the University admitted them past');
END $$;

-- ── 37-38. a code the University does not run ────────────────────────────
DO $$
DECLARE b uuid := gen_random_uuid(); v_n bigint; nm text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- C99256 is on JAMB's alias list and is a POSTGRADUATE programme, so it is
    -- not in the University's undergraduate table. It is a real code from the
    -- real file, and it is the case the reconciliation exists for.
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
        rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b, '2026/2027', 'CAPS_DOWNLOAD', 'DIRECT_ENTRY', 'PG'::bytea, 1,
            date '2026-10-02', gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
        surname, other_names, jamb_code, entry_mode)
    VALUES (gen_random_uuid(), b, '2026/2027', '202699307120BGU', '{}'::jsonb,
            'ABAH', 'Cecilia Ehi', 'C99256', 'DIRECT_ENTRY');

    SELECT x.n INTO v_n FROM admissions.reconcile('2026/2027') x
     WHERE x.finding = 'JAMB course code the University does not run';
    PERFORM pg_temp.assert('A code the University does not run is a finding',
        v_n = 1, 'C99256 is postgraduate and not on the undergraduate table');

    SELECT jamb_name INTO nm FROM ref.jamb_alias WHERE code = 'C99256';
    PERFORM pg_temp.assert('The alias can still name a code we do not run',
        nm = 'MA RELIGION AND PEACE STUDIES', nm);
END $$;

-- ── 39-40. the two names, on one code ────────────────────────────────────
DO $$
DECLARE v_jamb text; v_ours text; v_fac text; v_dept text; n int;
BEGIN
    SELECT a.jamb_name, p.name, p.faculty_code, p.dept_code
      INTO v_jamb, v_ours, v_fac, v_dept
      FROM ref.programme p JOIN ref.jamb_alias a ON a.code = p.code
     WHERE p.code = 'C00061';
    PERFORM pg_temp.assert('One code, two names — JAMB''s and the University''s',
        v_jamb = 'Medicine & Surgery' AND v_ours = 'MBBS',
        'C00061  JAMB: ' || v_jamb || '  |  MOAUM: ' || v_ours
        || '  (' || v_dept || ', faculty ' || v_fac || ')');

    SELECT count(*) INTO n
      FROM ref.programme p JOIN ref.jamb_alias a ON a.code = p.code
     WHERE upper(btrim(p.name)) <> upper(btrim(a.jamb_name));
    PERFORM pg_temp.assert('The two names differ for most programmes',
        n = 60, n || ' of 92 differ (56 named by the 2025/2026 guidelines, four more by the first 2026/2027 CAPS download, V012) — a name cannot be used as the join');
END $$;

-- ══ V007 · what arrives ATTACHED to a candidate ═════════════════════════
-- The two ways a match silently fails: a key wrapped in something else
-- (202699168863AH_Face.jpg) and a key that is not quite itself
-- ('202440000065EA '). Both would report "0 matched", which reads as a
-- broken import rather than as one stray character.

-- ── 41-44. the number is FOUND, not assumed ──────────────────────────────
DO $$
DECLARE v text;
BEGIN
    v := admissions.reg_no_in('202699168863AH_Face.jpg');
    PERFORM pg_temp.assert('JAMB''s real filename yields the registration number',
        v = '202699168863AH', '202699168863AH_Face.jpg -> ' || coalesce(v, 'NULL'));

    v := admissions.reg_no_in('C:\JAMB\2026\Copy of 202699307120BGU_face (1).JPG');
    PERFORM pg_temp.assert('A path, a copy, a lower-case suffix and a 15-character number',
        v = '202699307120BGU', coalesce(v, 'NULL') ||
        ' — 12 digits then TWO OR THREE letters: DE numbers are longer');

    v := admissions.reg_no_in('IMG-20260904-WA0031.jpg');
    PERFORM pg_temp.assert('A name with no registration number in it returns NOTHING',
        v IS NULL, 'not guessed at, not matched on a name, not discarded');

    PERFORM pg_temp.assert('Stripping only the extension would have matched nobody',
        upper(regexp_replace('202699168863AH_Face.jpg', '\.[^.]+$', ''))
            <> admissions.reg_no_in('202699168863AH_Face.jpg'),
        'the bug this exists to make impossible: every photograph an orphan');
END $$;

-- ── 45-46. the raw key is not joinable ───────────────────────────────────
DO $$
DECLARE k text; ok boolean := false;
BEGIN
    SELECT jamb_key INTO k FROM admissions.candidate LIMIT 1;
    PERFORM pg_temp.assert('Every candidate carries a generated join key',
        k IS NOT NULL AND k = upper(btrim(k)), coalesce(k, 'NULL'));

    -- the trailing space, as the date-of-birth file really sends it
    BEGIN
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
            other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
        SELECT gen_random_uuid(), c.session, c.jamb_reg_no || ' ', c.surname,
               c.other_names, c.programme, c.entry_mode, c.entry_level,
               c.offer_state, c.admitted_from
          FROM admissions.candidate c LIMIT 1;
    EXCEPTION WHEN unique_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('''202440000065EA '' and ''202440000065EA'' are one person', ok,
        'the unique index is on the generated key, so the space cannot make a twin');
END $$;

-- ── 47-50. held, not discarded ───────────────────────────────────────────
DO $$
DECLARE c_id uuid := gen_random_uuid(); c_key text := '202699176777GF'; b_id uuid := gen_random_uuid();
        v_n bigint; unread bigint; pending bigint;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- a candidate with a REAL registration number, on a COMMITTED admission
    -- list: a file attaches only once the list it belongs to is committed (V038)
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office, committed_at)
    VALUES (b_id, '2026/2027', 'CAPS_DOWNLOAD', 'UTME', '\xF1'::bytea, 1, current_date, gen_random_uuid(), 'academic', now());
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode)
    VALUES (gen_random_uuid(), b_id, '2026/2027', c_key, '{}'::jsonb, 'IORFA', 'Msendoo Blessing', 'C00023', 220, 'UTME');
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname,
        other_names, programme, entry_mode, entry_level, offer_state)
    VALUES (c_id, '2026/2027', c_key, 'IORFA', 'Msendoo Blessing',
            'B.Sc. Computer Science', 'UTME', 100, 'PROPOSED');

    -- three arrivals: one whose name IS the number, one wrapped in _Face,
    -- one that no number can be read out of, and one for a candidate who
    -- is not on any list yet.
    INSERT INTO admissions.attachment (id, session, kind, source_name,
        jamb_key, read_as, bytes, width_px, height_px)
    VALUES
      (gen_random_uuid(), '2026/2027', 'PASSPORT', c_key || '.jpg',
       admissions.reg_no_in(c_key || '.jpg'), 'EXACT', 3775, 132, 151),
      (gen_random_uuid(), '2026/2027', 'PASSPORT', '202699168863AH_Face.jpg',
       admissions.reg_no_in('202699168863AH_Face.jpg'), 'EMBEDDED', 3775, 132, 151),
      (gen_random_uuid(), '2026/2027', 'PASSPORT', 'IMG-20260904-WA0031.jpg',
       admissions.reg_no_in('IMG-20260904-WA0031.jpg'), 'UNREADABLE', 3885, 132, 151);

    SELECT sum(newly_attached) INTO v_n FROM admissions.attach_pending('2026/2027');
    PERFORM pg_temp.assert('The sweep attaches what it can and nothing else',
        v_n = 1, coalesce(v_n, 0) || ' attached — the one candidate actually on the list');

    SELECT count(*) INTO pending FROM admissions.attachment
     WHERE candidate_id IS NULL AND jamb_key IS NOT NULL;
    PERFORM pg_temp.assert('A photograph for nobody yet is HELD, not discarded',
        pending = 1, '202699168863AH arrives before its tranche of the list does');

    SELECT s.n INTO unread FROM admissions.attachment_state('2026/2027') s
     WHERE s.finding = 'Files with no readable registration number';
    PERFORM pg_temp.assert('The unreadable file is reported, not swallowed',
        unread = 1, 'named, with its filename, for a person to look at');

    -- and the constraint that stops the damage
    BEGIN
        INSERT INTO admissions.attachment (id, session, kind, source_name,
            jamb_key, read_as)
        VALUES (gen_random_uuid(), '2026/2027', 'PASSPORT', 'guess.jpg',
                c_key, 'UNREADABLE');
        PERFORM pg_temp.assert('An unreadable file cannot carry a key anyway',
            false, 'a guessed key on an unreadable name is how a face lands on the wrong person');
    EXCEPTION WHEN check_violation THEN
        PERFORM pg_temp.assert('An unreadable file cannot carry a key anyway', true,
            'no row can say both "I could not read it" and "here is the number"');
    END;
END $$;


-- ══ V008 · ADMISSION SETTINGS, PER SESSION ══════════════════════════════
-- Built from the Central Admissions Committee's own guidelines. The
-- numbers change every year, and today they live in a Word file.

-- ── 51-53. the guidelines as issued, and what they leave undone ─────────
DO $$
DECLARE v_q int; v_n int; v_pct int; v_cut int;
BEGIN
    SELECT nuc_quota INTO v_q FROM admissions.session_policy WHERE session = '2025/2026';
    PERFORM pg_temp.assert('The 2025/2026 NUC approved quota is carried as data',
        v_q = 10198, 'ten thousand, one hundred and ninety eight');

    SELECT sum(percent) INTO v_pct FROM admissions.selection_criterion c
      JOIN admissions.session_policy p ON p.id = c.policy_id
     WHERE p.session = '2025/2026';
    PERFORM pg_temp.assert('The four selection criteria total one hundred per cent',
        v_pct = 100, 'NM 10 + SM 35 + ELG 30 + Locality 25');

    SELECT count(*) INTO v_n FROM admissions.policy_findings('2025/2026');
    PERFORM pg_temp.assert('The settings as issued do not yet pass their own checks',
        v_n = 1, v_n || ' findings: no faculty quota distribution (a programme with no rule '
        'is skipped, not a finding, since V022)');
END $$;

-- ── 54-55. it cannot be put in force ────────────────────────────────────
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    BEGIN
        PERFORM admissions.put_in_force('2025/2026', 'CAC/2025/07');
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('Settings with findings against them cannot be put in force',
        ok, left(msg, 78));

    ok := false;
    BEGIN
        PERFORM admissions.put_in_force('2025/2026', '   ');
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('Nor can they be put in force citing no minute', ok,
        'the Committee''s minute is what makes settings real');
END $$;

-- ── 56. nothing works without settings in force ─────────────────────────
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    BEGIN
        PERFORM admissions.policy_in_force('2025/2026');
    EXCEPTION WHEN no_data_found THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('With no settings in force, admission FAILS CLOSED', ok,
        left(msg, 78));
END $$;

-- ── 57-60. a complete session, and what it then computes ────────────────
DO $$
DECLARE v_id uuid := gen_random_uuid(); v_n int; v_agg numeric; v_cut int;
        ok boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    INSERT INTO admissions.session_policy
        (id, session, nuc_quota, weight_utme, weight_putme)
    VALUES (v_id, '9999/0000', 1200, 70, 30);

    INSERT INTO admissions.selection_criterion (policy_id, criterion, percent)
    VALUES (v_id, 'NATIONAL_MERIT', 10), (v_id, 'STATE_MERIT', 35),
           (v_id, 'ELG', 30), (v_id, 'LOCALITY', 25);

    /* twelve faculties, a hundred places each, every one with a cut-off */
    INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff)
    SELECT v_id, code, 100, 160 FROM ref.faculty;

    /* every programme the University runs has a rule; the 1,200 places are
       distributed across the programmes so they total the NUC quota (V096:
       the distribution is per programme, not per faculty) */
    INSERT INTO admissions.programme_rule
        (policy_id, programme_code, cutoff, quota, olevel_text, utme_text, de_text)
    SELECT v_id, q.code, NULL,
           (1200 / q.cnt) + CASE WHEN q.rn <= 1200 % q.cnt THEN 1 ELSE 0 END,
           'five credits including English and Mathematics', 'as JAMB prescribes', 'two A Level passes'
      FROM (SELECT code, row_number() OVER (ORDER BY code) AS rn, count(*) OVER () AS cnt FROM ref.programme) q;

    SELECT count(*) INTO v_n FROM admissions.policy_findings('9999/0000');
    PERFORM pg_temp.assert('A complete session has nothing outstanding against it',
        v_n = 0, v_n || ' findings');

    PERFORM admissions.put_in_force('9999/0000', 'CAC/9999/01');

    /* 2.6 · UTME 70%, Post-UTME 30%. UTME is out of 400 and Post-UTME out
       of 100, so the UTME mark is scaled before it is weighted. */
    v_agg := admissions.aggregate_score('9999/0000', 247, 68.5);
    PERFORM pg_temp.assert('The aggregate is weighted 70/30, and the UTME mark is scaled',
        v_agg = 63.78, '247 of 400 and 68.5 of 100 give ' || v_agg ||
        ' — under an even 50/50 it would be 65.13, and a different candidate is admitted');

    /* absent is not zero, here as everywhere else */
    PERFORM pg_temp.assert('A missing Post-UTME score is not scored as zero',
        admissions.aggregate_score('9999/0000', 247, NULL) IS NULL,
        'a candidate who has not sat the screening is not a candidate who failed it');

    /* 2.13 · MBBS sits inside a College whose other programmes are at 180 */
    UPDATE admissions.programme_rule SET cutoff = 220
     WHERE policy_id = v_id AND programme_code = 'C00061';
    UPDATE admissions.faculty_quota SET cutoff = 180
     WHERE policy_id = v_id AND faculty_code = 'BAMS';
    PERFORM pg_temp.assert('A programme cut-off overrides its faculty''s',
        admissions.cutoff_for('9999/0000', 'C00061') = 220,
        'MBBS at 220 inside a College at 180');
    PERFORM pg_temp.assert('A programme with no cut-off of its own takes its faculty''s',
        admissions.cutoff_for('9999/0000', 'C18115') = 180,
        'Human Physiology, at the College''s 180');
END $$;

-- ── 61c. the merit engine runs against the in-force policy ─────────────
DO $$
DECLARE n int; m int;
BEGIN
    -- merit_list executes end to end: policy in force, faculty ratio, cut-off,
    -- the eligible pool, the UTME:DE split and the flexible fill. With no
    -- application for the programme the pool is empty — a computed list of zero,
    -- not an error — and an empty pool fills no seat.
    SELECT count(*), count(*) FILTER (WHERE proposed_offer) INTO n, m
      FROM admissions.merit_list('9999/0000', 'C18115');
    PERFORM pg_temp.assert('The merit engine runs against the in-force policy, and an empty pool fills no seat',
        n = 0 AND m = 0, 'no application for the programme yet — an empty list, computed, not an error');
END $$;

-- ── 61d. National Merit is the top by score (any origin); State Merit only below the merit line; sized off the UTME quota (V105) ──
DO $$
DECLARE
    v_pol uuid := gen_random_uuid();
    v_batch uuid := gen_random_uuid();
    prog text := 'C00019'; pname text := 'B.Sc. ACCOUNTING';
    r record; nm_min numeric; sm_max numeric;
    b_u1 text; b_u2 text; b_u3 text; b_u4 text; off_u4 boolean; n_nm int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'CHECK merit basis fixture (V105)', true);

    -- an in-force policy: programme quota 5, UTME:DE 80:20 (UTME quota 4), criteria NM50/SM30/ELG10/LOC10
    -- so the UTME National Merit share is round(4 * 50%) = 2 seats; sized off the WHOLE quota it would be 3
    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, instrument, in_force, state)
    VALUES (v_pol, '9994/9995', 5, 70, 30, 80, 20, 'CHECK CAC/9994/1', tstzrange(now(), NULL), 'IN_FORCE');
    INSERT INTO admissions.selection_criterion (policy_id, criterion, percent) VALUES
        (v_pol, 'NATIONAL_MERIT', 50), (v_pol, 'STATE_MERIT', 30), (v_pol, 'ELG', 10), (v_pol, 'LOCALITY', 10);
    INSERT INTO admissions.programme_rule (policy_id, programme_code, quota, olevel_text, utme_text, de_text)
    VALUES (v_pol, prog, 5, 'check', 'check', 'check');
    -- this fixture tests the merit allocation, not O'Level: waive the default compulsory subjects so the pool is eligible
    INSERT INTO admissions.programme_olevel_allowance (policy_id, programme_code, subject) VALUES
        (v_pol, prog, 'English Language'), (v_pol, prog, 'Mathematics');
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (v_batch, '9994/9995', 'CAPS_DOWNLOAD', 'UTME', '\xB1'::bytea, 4, current_date, gen_random_uuid(), 'academic');

    -- U1 non-indigene 300, U2 Benue 290 (both above the merit line), U3 Benue 280, U4 Benue 270 (below it)
    FOR r IN SELECT * FROM (VALUES
        ('U1', '20949990001', 'Kano',  'Nassarawa', 300, '000001'),
        ('U2', '20949990002', 'Benue', 'Makurdi',   290, '000002'),
        ('U3', '20949990003', 'Benue', 'Gboko',     280, '000003'),
        ('U4', '20949990004', 'Benue', 'Vandeikya', 270, '000004')
    ) AS t(tag, jamb, state, lga, utme, seq)
    LOOP
        DECLARE cr uuid := gen_random_uuid(); cand uuid := gen_random_uuid(); acct uuid := gen_random_uuid();
        BEGIN
            INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
            VALUES (cr, v_batch, '9994/9995', r.jamb, '{}'::jsonb, 'CHECKMERIT', r.tag, prog, r.utme, 'UTME', 'M', r.state, r.lga);
            INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
            VALUES (cand, '9994/9995', r.jamb, 'CHECKMERIT', r.tag, pname, 'UTME', 100, 'ADMITTED', cr);
            INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
            VALUES (acct, '9994/9995', cand, r.jamb, lower(r.jamb) || '@example.com', '08030000001', crypt('x', gen_salt('bf', 12)));
            INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, submitted_at, screening_score, score_entered_at, score_released_at)
            VALUES (gen_random_uuid(), acct, cand, '9994/9995', 'APP/94/' || r.seq, now(), 50, now(), now());
        END;
    END LOOP;

    SELECT basis INTO b_u1 FROM admissions.merit_list('9994/9995', prog) WHERE other_names = 'U1';
    SELECT basis INTO b_u2 FROM admissions.merit_list('9994/9995', prog) WHERE other_names = 'U2';
    SELECT basis INTO b_u3 FROM admissions.merit_list('9994/9995', prog) WHERE other_names = 'U3';
    SELECT basis, proposed_offer INTO b_u4, off_u4 FROM admissions.merit_list('9994/9995', prog) WHERE other_names = 'U4';
    SELECT count(*) INTO n_nm FROM admissions.merit_list('9994/9995', prog) WHERE basis = 'NM';
    SELECT min(aggregate) INTO nm_min FROM admissions.merit_list('9994/9995', prog) WHERE basis = 'NM';
    SELECT max(aggregate) INTO sm_max FROM admissions.merit_list('9994/9995', prog) WHERE basis = 'SM';

    PERFORM pg_temp.assert('National Merit is the top by score, any origin; State Merit only below the merit line; sized off the UTME quota',
        b_u1 = 'NM' AND b_u2 = 'NM'          -- top non-indigene AND top indigene both National Merit
        AND n_nm = 2                          -- exactly the UTME National Merit share (2), not the whole-quota share (3)
        AND b_u3 = 'SM'                       -- the next indigene, below the merit line, is State Merit
        AND b_u4 IS NULL AND NOT off_u4       -- below the line, no reserved category: waiting list
        AND sm_max < nm_min,                  -- no State Merit candidate outranks a National Merit one
        format('u1=%s u2=%s u3=%s u4=%s(off=%s) n_nm=%s sm_max=%s nm_min=%s',
               b_u1, b_u2, b_u3, b_u4, off_u4, n_nm, sm_max, nm_min));
END $$;

-- ── 61e. a non-qualified candidate with five O'Level credits is suggested an open programme they qualify for (V106) ──
DO $$
DECLARE v_pol uuid; att uuid := gen_random_uuid(); n int; has_target boolean; has_current boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'CHECK suggestion fixture (V106)', true);
    SELECT id INTO v_pol FROM admissions.session_policy WHERE session = '9994/9995';

    -- a second programme with an open seat and no cut-off of its own, to be the suggestion
    INSERT INTO admissions.programme_rule (policy_id, programme_code, quota, olevel_text, utme_text, de_text)
    VALUES (v_pol, 'C00023', 5, 'check', 'check', 'check');
    -- the session's O'Level grading, and U4's five credits (English, Mathematics and three others)
    INSERT INTO admissions.olevel_grading (session, subjects_counted, bonus_one_sitting, bonus_two_sittings)
    VALUES ('9994/9995', 5, 10, 6);
    INSERT INTO admissions.olevel_grade_point (session, grade, points)
    SELECT '9994/9995', v.g, v.p FROM (VALUES ('A1',10),('B2',8),('B3',6),('C4',4),('C5',3),('C6',2),('D7',0),('E8',0),('F9',0)) v(g, p);
    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload)
    VALUES (att, '9994/9995', 'OLEVEL', 'check-suggestion', '20949990004', 'COLUMN',
      '{"sittings":[{"type":"WAEC","year":"2024","examNumber":"S1","subjects":[
         {"subject":"English Language","grade":"B3"},{"subject":"Mathematics","grade":"B3"},
         {"subject":"Physics","grade":"C4"},{"subject":"Chemistry","grade":"C5"},{"subject":"Biology","grade":"C6"}]}]}'::jsonb);
    PERFORM admissions.olevel_from_attachment(att);

    SELECT count(*), bool_or(code = 'C00023'), bool_or(code = 'C00019')
      INTO n, has_target, has_current
      FROM admissions.programme_suggestions('9994/9995', '20949990004', 'C00019');
    PERFORM pg_temp.assert('A non-qualified candidate with five O''Level credits is suggested an open programme they qualify for, never their own',
        n = 1 AND has_target AND NOT coalesce(has_current, false),
        format('suggestions=%s target(C00023)=%s current(C00019)=%s', n, has_target, has_current));
END $$;

-- ── 62. the database refuses a weighting that does not total 100 ────────
DO $$
DECLARE ok boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    BEGIN
        INSERT INTO admissions.session_policy
            (id, session, nuc_quota, weight_utme, weight_putme)
        VALUES (gen_random_uuid(), '9998/0000', 100, 70, 40);
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A weighting that does not total 100 is refused', ok,
        '70 + 40 is not a weighting, it is a typing error nobody would ever see');
END $$;

-- ══ V013 · THE STUDENT RECORD SPINE ═════════════════════════════════════
-- Eighteen screens stand on one chain: faculty, department, programme,
-- student, registration, sheet, decision, clearance, credential. These are
-- the properties the chain refuses to lose.

-- ── 64-65. the structure holds together, and every table is on the spine ─
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM ref.programme p
     WHERE NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code);
    PERFORM pg_temp.assert('Every programme''s department is on the register',
        n = 0, n || ' programmes name a department the register does not have');

    SELECT count(*) INTO n
      FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
     WHERE c.relkind = 'r'
       AND ns.nspname IN ('people','catalogue','registration','assessment','clearance','records')
       AND NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgname LIKE 'trg_audit_%')
       AND NOT EXISTS (SELECT 1 FROM audit.exemption e WHERE e.relid = c.oid);
    PERFORM pg_temp.assert('Every table of the student record is on the audit spine',
        n = 0, n || ' tables hold state and are neither attached nor exempted');
END $$;

-- ── 66-68. the calendar: no overlap, one current, on a minute ───────────
DO $$
DECLARE ok boolean := false; msg text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
    VALUES (gen_random_uuid(), '9999/0000', date '9999-01-01', date '9999-12-31') ON CONFLICT (name) DO NOTHING;   -- §17a may have made it

    BEGIN
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
        VALUES (gen_random_uuid(), '9998/9999', date '9998-09-01', date '9999-03-31');
    EXCEPTION WHEN exclusion_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('Two academic sessions cannot overlap', ok,
        'an exclusion constraint, not a check on a form');

    ok := false;
    BEGIN
        UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = '9999/0000';
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A session is not current without its Senate minute', ok,
        'opening one early would let students register into a session the University has not resolved to run');

    UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = 'SEN/9999/01' WHERE name = '9999/0000';
    ok := false;
    BEGIN
        UPDATE policy.academic_session SET state = 'CURRENT', senate_minute = 'SEN/2026/02' WHERE name = '2026/2027';
    EXCEPTION WHEN unique_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('Exactly one session is current at a time', ok,
        '9999/0000 is current; 2026/2027 cannot also be');
    UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = '9999/0000';
END $$;

-- ── 69-73. the register, the list and the run ───────────────────────────
DO $$
DECLARE ok boolean := false; msg text; n int; l uuid; v_ref text; m1 text; m2 text;
        s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid();
        o uuid := gen_random_uuid();
        r1 uuid := gen_random_uuid(); r2 uuid := gen_random_uuid(); r3 uuid := gen_random_uuid();
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    INSERT INTO people.student (id, admission_no, surname, other_names, programme_code, entry_mode,
                                entry_session, entry_level, current_level)
    VALUES (s1, 'MOAUM/ADM/99/000001', 'CHECKSURNAME', 'Invented One',   'C00023', 'UTME', '9999/0000', 100, 100),
           (s2, 'MOAUM/ADM/99/000002', 'CHECKSURNAME', 'Invented Two',   'C00023', 'UTME', '9999/0000', 100, 100),
           (s3, 'MOAUM/ADM/99/000003', 'CHECKSURNAME', 'Invented Three', 'C00023', 'UTME', '9999/0000', 100, 100);
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state)
    VALUES ('ZZC 101', 'A course for the check', 3, 1, 100, 'MTC', 'LIVE');
    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (o, 'ZZC 101', '9999/0000', 1);
    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at)
    VALUES (r1, s1, '9999/0000', 1, 100, 'APPROVED', now()),
           (r2, s2, '9999/0000', 1, 100, 'APPROVED', now()),
           (r3, s3, '9999/0000', 1, 100, 'DRAFT', NULL);
    INSERT INTO registration.entry (registration_id, offering_id, units, status)
    VALUES (r1, o, 3, 'APPROVED'), (r2, o, 3, 'APPROVED'), (r3, o, 3, 'REGISTERED');

    SELECT count(*) INTO n FROM people.faculty_list_rows('9999/0000', 'SC');
    PERFORM pg_temp.assert('The faculty list is generated from approved registrations, not typed',
        n = 2, 'two approved and one draft registration; the draft is not on the list');

    BEGIN
        PERFORM people.matriculate('9999/0000');
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('The run cannot start while a faculty list is unconfirmed', ok, left(msg, 78));

    INSERT INTO people.faculty_list (id, session, faculty_code, state, confirmed_at, confirmed_by)
    VALUES (gen_random_uuid(), '9999/0000', 'SC', 'CONFIRMED', now(), gen_random_uuid())
    RETURNING id INTO l;
    INSERT INTO people.faculty_list_query (list_id, student_id, reason, office)
    VALUES (l, s2, 'Registered 3 units; the minimum at 100 level is 15', 'Faculty Officer');

    SELECT run_ref, issued INTO v_ref, n FROM people.matriculate('9999/0000');
    PERFORM pg_temp.assert('Numbers are issued in one run over the confirmed list',
        n = 1 AND v_ref = 'MAT/9999/001', v_ref || ' issued ' || n);

    SELECT matric_no INTO m1 FROM people.student WHERE id = s1;
    SELECT matric_no INTO m2 FROM people.student WHERE id = s2;
    PERFORM pg_temp.assert('A queried student keeps the admission number and is not matriculated',
        m2 IS NULL AND m1 IS NOT NULL, coalesce(m1, '—') || ' issued in the configured format (V263); the queried one waits for the next run');

    ok := false;
    BEGIN
        UPDATE people.student SET matric_no = 'MOAUM/MTC/99/0009' WHERE id = s1;
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A matriculation number, once issued, is never changed', ok, 'BR-007');
END $$;

-- ── 74-78. the chain a sheet passes ─────────────────────────────────────
DO $$
DECLARE ok boolean := false; msg text; n int; st text; g text; o uuid; s1 uuid; s2 uuid;
        sh uuid := gen_random_uuid(); a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
BEGIN
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    SELECT id INTO o FROM catalogue.offering WHERE course_code = 'ZZC 101';
    SELECT id INTO s1 FROM people.student WHERE admission_no = 'MOAUM/ADM/99/000001';
    SELECT id INTO s2 FROM people.student WHERE admission_no = 'MOAUM/ADM/99/000002';
    INSERT INTO assessment.score_sheet (id, offering_id) VALUES (sh, o);
    INSERT INTO assessment.score (sheet_id, student_id, ca, exam) VALUES (sh, s1, 30, 45);

    BEGIN
        PERFORM assessment.advance(sh, NULL);
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('A sheet does not leave the lecturer while a candidate has no outcome',
        ok, left(msg, 78));

    INSERT INTO assessment.score (sheet_id, student_id, outcome) VALUES (sh, s2, 'ABSENT');
    st := assessment.advance(sh, NULL);
    ok := false;
    BEGIN
        PERFORM assessment.advance(sh, 'and again');
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('No two consecutive stages of a sheet by one person', ok, left(msg, 78));

    PERFORM set_config('moaum.actor_id', a2::text, true);
    PERFORM set_config('moaum.actor_office', 'exams', true);
    st := assessment.advance(sh, NULL);
    PERFORM assessment.return_sheet(sh, 'two candidates recorded as absent had in fact sat the paper');
    SELECT stage, returned_times INTO st, n FROM assessment.score_sheet WHERE id = sh;
    PERFORM pg_temp.assert('A returned sheet goes back to entry, and the return is on the record',
        st = 'ENTRY' AND n = 1, 'returned once, with the reason');

    FOR i IN 1..7 LOOP
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        st := assessment.advance(sh, NULL);
    END LOOP;
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    ok := false;
    BEGIN
        PERFORM assessment.advance(sh, NULL);
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    st := assessment.advance(sh, NULL, 'SEN/9999/02');
    PERFORM pg_temp.assert('A result is published on the Senate minute and not before',
        ok AND st = 'PUBLISHED', 'eight desks, then the minute');

    SELECT grade INTO g FROM assessment.latest_scores(sh) WHERE student_id = s1;
    PERFORM pg_temp.assert('The grade is computed from the marks under the scheme in force, never typed',
        g = 'A' AND policy.class_of(4.62) = 'First Class Honours',
        '30 + 45 = 75 is an A under SEN/2015/44; 4.62 is a First');
END $$;

-- ── 79-81. clearance holds, and the transcript it releases ──────────────
DO $$
DECLARE ok boolean := false; msg text; st text; s1 uuid; t uuid := gen_random_uuid();
        a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
BEGIN
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    SELECT id INTO s1 FROM people.student WHERE admission_no = 'MOAUM/ADM/99/000001';

    BEGIN
        INSERT INTO clearance.item (id, student_id, purpose, unit, state)
        VALUES (gen_random_uuid(), s1, 'TRANSCRIPT', 'LIBRARY', 'HELD');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A hold names the item outstanding, or it is not a hold', ok,
        'a hold with no item against it is leverage, not clearance');

    INSERT INTO credentials.transcript_request (id, ref, student_id, destination, paid_at, stage)
    VALUES (t, 'TRN-9999-00001', s1, 'EMPLOYER', now(), 'READY');
    ok := false;
    BEGIN
        PERFORM credentials.produce_transcript(t);
    EXCEPTION WHEN check_violation THEN ok := true; msg := SQLERRM;
    END;
    PERFORM pg_temp.assert('A transcript is not produced while any unit holds the candidate', ok, left(msg, 78));

    INSERT INTO clearance.item (id, student_id, purpose, unit, state, officer_id)
    SELECT gen_random_uuid(), s1, 'TRANSCRIPT', code, 'CLEARED', a1 FROM clearance.unit;
    PERFORM credentials.produce_transcript(t);
    -- V262: a produced document passes the quality check before anyone may release it
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM credentials.qc_transcript(t, 'APPROVED', NULL);
    PERFORM set_config('moaum.actor_id', a1::text, true);
    ok := false;
    BEGIN
        PERFORM credentials.release_transcript(t);
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM set_config('moaum.actor_id', a2::text, true);
    PERFORM credentials.release_transcript(t);
    SELECT stage INTO st FROM credentials.transcript_request WHERE id = t;
    PERFORM pg_temp.assert('The officer who produced a transcript does not sign it',
        ok AND st = 'RELEASED', 'produced by one officer, released by another');
END $$;

-- ══ V017 · SIGNING IN ═══════════════════════════════════════════════════

-- ── 82-83. the hash stays out of the trail; the offices in a token are live ─
DO $$
DECLARE n int; v_p uuid := gen_random_uuid(); v_g uuid := gen_random_uuid();
BEGIN
    SELECT count(*) INTO n FROM audit.exemption e WHERE e.relid = 'iam.credential'::regclass;
    PERFORM pg_temp.assert('The credential is off the spine with a reason, and the act of setting it is on it',
        n = 1 AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'iam.credential_event'::regclass AND t.tgname LIKE 'trg_audit_%'),
        'a hash copied into a longer-lived trail is a second place to steal it from');

    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (v_p, 'CHECK/V017', 'CHECKSIGNIN', 'Invented');
    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to)
    VALUES (v_g, v_p, 'dean', 'faculty', 'SC', 'check', gen_random_uuid(), current_date - 30, current_date - 1),   -- V325: a bounded office carries its bound
           (gen_random_uuid(), v_p, 'hod', 'department', 'MTC', 'check', gen_random_uuid(), current_date, NULL);
    SELECT count(*) INTO n FROM iam.live_offices(v_p);
    PERFORM pg_temp.assert('A token carries only the offices held today',
        n = 1 AND (SELECT office_code FROM iam.live_offices(v_p)) = 'hod',
        'the deanship that ended yesterday is not an office today, whoever forgot to say so');
END $$;

-- ══ V018 · JAMB NAMES A PROGRAMME MORE THAN ONE WAY ═════════════════════

-- ── 84. a further name is kept beside the first ─────────────────────────
DO $$
DECLARE n int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO ref.jamb_alias_name (jamb_key, jamb_name, code) VALUES ('medicineandsurgerymbbs', 'Medicine and Surgery (MBBS)', 'C00061');
    SELECT count(DISTINCT code) INTO n FROM (
        SELECT code FROM ref.jamb_alias WHERE lower(regexp_replace(jamb_name, '[^A-Za-z0-9]', '', 'g')) = 'medicinesurgery'
        UNION ALL
        SELECT code FROM ref.jamb_alias_name WHERE jamb_key = 'medicineandsurgerymbbs') x;
    PERFORM pg_temp.assert('A second JAMB name for a programme is kept beside the first',
        n = 1 AND (SELECT jamb_name FROM ref.jamb_alias WHERE code = 'C00061') = 'Medicine & Surgery',
        'both names resolve to MBBS; neither replaced the other');
END $$;

-- ══ V019 · A LIST LOADED IN ERROR IS WITHDRAWN, NOT DELETED ══════════════

-- ── 85–87. a withdrawn list is kept, counts for nothing, and frees its numbers ──
DO $$
DECLARE b uuid := gen_random_uuid(); b2 uuid := gen_random_uuid();
        n bigint; ok boolean; outcome text; again text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
        rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b, '9998/9999', 'CAPS_DOWNLOAD', 'DIRECT_ENTRY', '\xB9'::bytea, 1,
            current_date, gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
        surname, other_names, jamb_code, aggregate, entry_mode)
    VALUES (gen_random_uuid(), b, '9998/9999', '20269999ZZ', '{}'::jsonb,
            'CHECKWITHDRAWN', 'Invented', 'C00061', NULL, 'DIRECT_ENTRY');

    -- 85. without a reason, refused
    ok := false;
    BEGIN
        PERFORM admissions.withdraw_batch(b, '  ');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A list is withdrawn for a reason, never silently', ok,
        'the record must explain the space the withdrawal leaves');

    -- 86. withdrawn: kept, marked, out of every count, and not committed
    outcome := admissions.withdraw_batch(b, 'the office''s own layout was loaded before the CAPS download');
    again := admissions.withdraw_batch(b, 'once more');
    SELECT x.n INTO n FROM admissions.reconcile('9998/9999') x
     WHERE x.finding = 'On the CAPS list, no candidate record';
    ok := false;
    BEGIN
        PERFORM admissions.commit_batch(b);
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM pg_temp.assert('A withdrawn list is kept, counts for nothing, and is never committed',
        outcome = 'withdrawn' AND again = 'already withdrawn' AND n = 0 AND ok
        AND (SELECT count(*) FROM admissions.caps_row WHERE batch_id = b AND withdrawn) = 1
        AND (SELECT withdrawn_by IS NOT NULL AND withdrawn_reason LIKE 'the office%'
               FROM admissions.caps_batch WHERE id = b),
        'the upload happened and the record says so; nothing of it counts again');

    -- 87. the registration numbers on it are free for the list that replaces it
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256,
        rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b2, '9998/9999', 'CAPS_DOWNLOAD', 'DIRECT_ENTRY', '\xBA'::bytea, 1,
            current_date, gen_random_uuid(), 'academic');
    ok := true;
    BEGIN
        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw,
            surname, other_names, jamb_code, aggregate, entry_mode)
        VALUES (gen_random_uuid(), b2, '9998/9999', '20269999ZZ', '{}'::jsonb,
                'CHECKWITHDRAWN', 'Invented', 'C00061', NULL, 'DIRECT_ENTRY');
    EXCEPTION WHEN unique_violation THEN ok := false;
    END;
    PERFORM pg_temp.assert('The numbers on a withdrawn list are free for the list that replaces it', ok,
        'a candidate is on one standing list, and the withdrawn rows are evidence, not a cohort');
END $$;

-- ══ V020 · THE O'LEVEL RESULTS JAMB SENDS, AND THE SCREENING SCORE ═══════

-- ── 88–90. two sittings read apart; the score under the defaults; the rule as the session states it ──
DO $$
DECLARE att uuid := gen_random_uuid(); pid uuid := gen_random_uuid(); gid uuid := gen_random_uuid();
        dup uuid := gen_random_uuid(); r record; n int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- one candidate, two sittings: WAEC 2024 and NECO 2025, as the screen records them
    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload)
    VALUES (att, '9998/9999', 'OLEVEL', 'check-two-sittings', '20269999OL', 'COLUMN',
      '{"sittings":[
         {"type":"WAEC Only","year":"2024","examNumber":"4110001","subjects":[
            {"subject":"English Language","grade":"C6"},{"subject":"Mathematics","grade":"B3"},
            {"subject":"Physics","grade":"D7"},{"subject":"Chemistry","grade":"C5"},
            {"subject":"Biology","grade":"A1"},{"subject":"Geography","grade":"C4"}]},
         {"type":"NECO","year":"2025","examNumber":"9920002","subjects":[
            {"subject":"English Language","grade":"B2"},{"subject":"Physics","grade":"C4"},
            {"subject":"Agricultural Science","grade":"B3"}]}]}'::jsonb);
    n := admissions.olevel_from_attachment(att);

    -- 88. read apart, each under its examining body
    PERFORM pg_temp.assert('Two sittings are kept apart, each under its examining body',
        n = 2
        AND (SELECT string_agg(exam_body, ',' ORDER BY ord) FROM admissions.olevel_sitting WHERE attachment_id = att) = 'WAEC,NECO'
        AND (SELECT count(*) FROM admissions.olevel_grade g JOIN admissions.olevel_sitting s ON s.id = g.sitting_id
              WHERE s.attachment_id = att) = 9,
        'a WAEC result and a NECO result are two results, shown as JAMB sent them');

    -- 89. under the defaults: the best grade per subject across the sittings, the top five, the two-sitting bonus
    -- best: English B2 5 · Mathematics B3 4 · Physics C4 3 · Chemistry C5 2 · Biology A1 6 · Geography C4 3 · Agric B3 4
    -- top five: 6 + 5 + 4 + 4 + 3 = 22, and 6 for two sittings = 28
    SELECT * INTO r FROM admissions.olevel_score('9998/9999', '20269999OL', 'C00061');
    PERFORM pg_temp.assert('The score takes the best grade per subject across two sittings, the top five, and the two-sitting bonus',
        r.sittings = 2 AND r.points = 22 AND r.bonus = 6 AND r.total = 28 AND r.relevant_known = false,
        'B2 beats C6 in English and C4 beats D7 in Physics; five subjects count; two sittings earn 6');

    -- 90. the rule is the session's to state, and the programme's relevant subjects are the ones that count
    INSERT INTO admissions.olevel_grading (session, subjects_counted, bonus_one_sitting, bonus_two_sittings)
    VALUES ('9998/9999', 4, 12, 3);
    INSERT INTO admissions.olevel_grade_point (session, grade, points)
    SELECT '9998/9999', v.g, v.p FROM (VALUES ('A1',10),('B2',8),('B3',6),('C4',4),('C5',2),('C6',1),('D7',0),('E8',0),('F9',0)) v(g, p);
    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme) VALUES (pid, '9998/9999', 100, 70, 30);
    INSERT INTO admissions.programme_rule (policy_id, programme_code, olevel_text, utme_text, de_text)
    VALUES (pid, 'C00061', 'check', 'check', 'check');
    INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose) VALUES (gid, pid, 'C00061', 'OLEVEL', 4);
    INSERT INTO admissions.rule_subject (group_id, subject)
    VALUES (gid, 'English Language'), (gid, 'Mathematics'), (gid, 'Physics'), (gid, 'Chemistry'), (gid, 'Biology');
    -- relevant, best: English B2 8 · Mathematics B3 6 · Physics C4 4 · Chemistry C5 2 · Biology A1 10 → top four 10 + 8 + 6 + 4 = 28, and 3 = 31
    SELECT * INTO r FROM admissions.olevel_score('9998/9999', '20269999OL', 'C00061');
    PERFORM pg_temp.assert('The grading is the session''s to state, and the programme''s relevant subjects are the ones that count',
        r.relevant_known AND r.points = 28 AND r.bonus = 3 AND r.total = 31
        AND admissions.olevel_points('9998/9999', 'A1') = 10 AND admissions.olevel_points('2026/2027', 'A1') = 6,
        'Agricultural Science is not relevant to MBBS and is not counted; the stated points and bonus replace the defaults');

    -- 90b. the same WAEC result uploaded a second time is not recorded a second time — deduped by its
    -- identity on import, so no duplicate row is kept and the score still counts it once (V099, V147)
    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload)
    VALUES (dup, '9998/9999', 'OLEVEL', 'check-duplicate-sitting', '20269999OL', 'COLUMN',
      '{"sittings":[
         {"type":"WAEC Only","year":"2024","examNumber":"4110001","subjects":[
            {"subject":"English Language","grade":"C6"},{"subject":"Mathematics","grade":"B3"},
            {"subject":"Physics","grade":"D7"},{"subject":"Chemistry","grade":"C5"},
            {"subject":"Biology","grade":"A1"},{"subject":"Geography","grade":"C4"}]}]}'::jsonb);
    PERFORM admissions.olevel_from_attachment(dup);
    SELECT * INTO r FROM admissions.olevel_score('9998/9999', '20269999OL', 'C00061');
    PERFORM pg_temp.assert('The same O''Level result uploaded twice is deduped on import: the score counts it once and no duplicate row is kept',
        r.sittings = 2 AND r.points = 28 AND r.bonus = 3 AND r.total = 31
        AND admissions.olevel_sittings('9998/9999', '20269999OL') = 2
        AND (SELECT count(*) FROM admissions.olevel_sitting WHERE session = '9998/9999' AND jamb_key = '20269999OL') = 2,
        format('sittings=%s points=%s bonus=%s total=%s rows=%s', r.sittings, r.points, r.bonus, r.total,
               (SELECT count(*) FROM admissions.olevel_sitting WHERE session = '9998/9999' AND jamb_key = '20269999OL')));
END $$;

-- ══ V021 · THE APPLICANT'S JOURNEY ═══════════════════════════════════════

-- ── 91–94. the number against the list; the stage from the facts; the fee gate; the offer accepted ──
DO $$
DECLARE b uuid := gen_random_uuid(); acct uuid; app uuid; ref text; ok boolean; f record; st int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- 91. nobody is verified while no list is loaded; then the number is found and the name is read, never typed
    SELECT * INTO f FROM admissions.applicant_lookup('9997/9998', '20269999AP');
    ok := f.state = 'nolist';
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b, '9997/9998', 'CAPS_DOWNLOAD', 'UTME', '\xC1'::bytea, 1, current_date, gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
    VALUES (gen_random_uuid(), b, '9997/9998', '20269999AP', '{}'::jsonb, 'CHECKAPPLICANT', 'Invented Person', 'C00061', 287, 'UTME', 'F', 'Benue', 'Gwer West');
    SELECT * INTO f FROM admissions.applicant_lookup('9997/9998', '20269999AP');
    PERFORM pg_temp.assert('The JAMB number is verified against the list the Academic Office loaded, and the name is read from it',
        ok AND f.state = 'found' AND f.surname = 'CHECKAPPLICANT' AND f.programme = 'MBBS'
        AND (SELECT x.state FROM admissions.applicant_lookup('9997/9998', '20269999ZZ') x) = 'none',
        'a Post-UTME roll that anybody may join is not a roll; a typed name is a different person from the one JAMB holds');

    -- 92. registering makes the candidate record from the CAPS row and opens the application under a number
    PERFORM set_config('moaum.actor_office', 'applicant', true);
    acct := admissions.register_applicant('9997/9998', '20269999AP', 'check.applicant@example.com', '08034117725',
        '$2a$12$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ab');
    SELECT a.id INTO app FROM admissions.application a WHERE a.account_id = acct;
    PERFORM pg_temp.assert('Registering creates the candidate from the CAPS row and opens the application under a number',
        EXISTS (SELECT 1 FROM admissions.candidate c JOIN admissions.applicant_account a ON a.candidate_id = c.id
                 WHERE a.id = acct AND c.offer_state = 'PROPOSED' AND c.admitted_from IS NOT NULL AND c.programme = 'MBBS')
        AND (SELECT application_no FROM admissions.application WHERE id = app) ~ '^APP/97/[0-9]{6}$'
        AND admissions.application_stage(app) = 0
        AND (SELECT x.state FROM admissions.applicant_lookup('9997/9998', '20269999AP') x) = 'registered',
        'the reconciliation has a candidate record to find, and the applicant has one account');

    -- 93. the form opens when the fee is confirmed by an office against the bank's record, not before
    ok := false;
    BEGIN
        PERFORM admissions.submit_application(app, '127.0.0.1');
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    ref := admissions.new_fee_reference(app, 'APPLICATION');
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM admissions.confirm_fee(ref, 'Bank transfer', 'check');
    PERFORM pg_temp.assert('The form opens when the application fee is confirmed against the reference this portal generated',
        ok AND ref LIKE 'MOAUM-APP-%' AND admissions.application_stage(app) = 1
        AND (SELECT amount FROM admissions.fee_reference WHERE reference = ref) = 2300
        AND admissions.confirm_fee(ref, 'Bank transfer', 'again') = 'already confirmed',
        'nothing is submitted until the bank''s record says the fee arrived; a reference is confirmed once');

    -- 94. the Board's released offer makes the candidate ADMITTED; the undertaking and the acceptance fee make them ACCEPTED
    PERFORM set_config('moaum.actor_office', 'academic', true);
    UPDATE admissions.application SET next_of_kin = 'CHECK Next of Kin · 08030000000', submitted_at = now() WHERE id = app;
    INSERT INTO admissions.screening_batch (id, session, label, held_on, starts_at, ends_at, venue, capacity)
    VALUES (gen_random_uuid(), '9997/9998', 'C', current_date + 10, '11:00', '12:00', 'CBT Hall B', 120);
    st := admissions.assign_screening((SELECT id FROM admissions.screening_batch WHERE session = '9997/9998' AND label = 'C'));
    UPDATE admissions.application SET screening_score = 68.5, score_entered_at = now() WHERE id = app;
    PERFORM admissions.release_scores('9997/9998');
    PERFORM admissions.decide_application(app, 'OFFERED', 'check');
    PERFORM admissions.release_decisions('9997/9998');
    -- V295: admission status checking is the Director of ICT's window, closed until opened for the session
    INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state) VALUES (gen_random_uuid(), '9997/9998', date '9997-09-01', date '9998-08-31', 'DRAFT') ON CONFLICT DO NOTHING;
    PERFORM policy.window_act('ADMISSION_STATUS_CHECKING', '9997/9998', NULL, 'OPEN', NULL, NULL, NULL, false, 'check', gen_random_uuid(), 'ict');
    -- the admission checking fee first, on its own (V271): the applicant checks and reads the offer, the acceptance follows (V295)
    PERFORM set_config('moaum.actor_office', 'applicant', true);
    ref := admissions.new_fee_reference(app, 'CHECKING');
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM admissions.confirm_fee(ref, 'Card', NULL);
    PERFORM set_config('moaum.actor_office', 'applicant', true);
    PERFORM admissions.admission_status_checked(app);
    PERFORM admissions.sign_undertaking(app);
    ref := admissions.new_fee_reference(app, 'ACCEPTANCE');
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM admissions.confirm_fee(ref, 'Card', NULL);
    SELECT * INTO f FROM admissions.screening_result(app);
    PERFORM pg_temp.assert('A released offer makes the candidate ADMITTED, and the undertaking with the acceptance fee makes them ACCEPTED',
        st = 1 AND (SELECT seat FROM admissions.application WHERE id = app) = 'C-001'
        AND f.aggregate = round((287 / 400.0 * 100 * 0.7 + 68.5 * 0.3)::numeric, 2) AND f.merit_position = 1
        AND (SELECT offer_state FROM admissions.candidate c JOIN admissions.application a ON a.candidate_id = c.id WHERE a.id = app) = 'ACCEPTED'
        AND admissions.application_stage(app) = 6,
        'the same candidate the Academic Office brings onto the register with people.intake, and the same aggregate rule as its settings');
END $$;

-- ══ V022 · SCREENED BY EXAMINATION, AND THE PASSPORT AT ANY TIME ═════════

-- ── 95–96. an examination programme is scored on the examination alone; the passport is no gate ──
DO $$
DECLARE app uuid; f record; g record; ok boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    -- the application of 91–94 (MBBS, session 9997/9998) has a CBT score of 68.5 and an O'Level result would not change it;
    -- name MBBS as screened by examination and the source says so; take the score away and there is no O'Level fallback
    SELECT a.id INTO app FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE a.session = '9997/9998' AND c.jamb_reg_no = '20269999AP';
    INSERT INTO admissions.screening_exam_programme (session, programme_code) VALUES ('9997/9998', 'C00061');
    SELECT * INTO f FROM admissions.screening_component(app);
    UPDATE admissions.application SET screening_score = NULL WHERE id = app;
    SELECT * INTO g FROM admissions.screening_component(app);
    UPDATE admissions.application SET screening_score = 68.5 WHERE id = app;
    PERFORM pg_temp.assert('A programme screened by examination is scored on the examination alone, never on O''Level grading',
        f.source = 'EXAM' AND f.screening = 68.5 AND f.olevel_total IS NULL AND g.source = 'EXAM' AND g.screening IS NULL,
        'the departments that sit the post-UTME examination are not included in the O''Level screening');

    -- 96. the passport photograph is not a gate on submitting
    PERFORM set_config('moaum.actor_office', 'applicant', true);
    UPDATE admissions.application SET submitted_at = NULL WHERE id = app;
    INSERT INTO admissions.application_document (id, application_id, kind, filename, content_type, bytes)
    SELECT gen_random_uuid(), app, k, lower(k) || '.pdf', 'application/pdf', 10
      FROM unnest(ARRAY['OLEVEL_STATEMENT','BIRTH_CERT','LGA_ID','JAMB_SLIP']) k;
    ok := admissions.submit_application(app, '127.0.0.1') = 'submitted';
    PERFORM pg_temp.assert('The four documents are needed to submit; the passport photograph can come at any time',
        ok AND (SELECT submitted_at FROM admissions.application WHERE id = app) IS NOT NULL,
        'a photograph arrives whenever the applicant has one, and is the one document outside the declaration');
END $$;

-- ══ V023 · A PROGRAMME CLOSED FOR A SESSION ═════════════════════════════

-- ── 97. closed: needs no rule, and a candidate JAMB sent for it is told so at registration ──
DO $$
DECLARE pid uuid := gen_random_uuid(); b uuid := gen_random_uuid(); f record; n int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme) VALUES (pid, '9997/9998', 100, 70, 30);
    -- a candidate JAMB sent for Computer Science, which the session then closes
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b, '9997/9998', 'CAPS_DOWNLOAD', 'UTME', '\xC2'::bytea, 1, current_date, gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode)
    VALUES (gen_random_uuid(), b, '9997/9998', '20269999CL', '{}'::jsonb, 'CHECKCLOSED', 'Invented', 'C00023', 250, 'UTME');
    SELECT * INTO f FROM admissions.applicant_lookup('9997/9998', '20269999CL');
    n := CASE WHEN f.state = 'found' THEN 1 ELSE 0 END;
    INSERT INTO admissions.programme_closed (policy_id, programme_code, reason) VALUES (pid, 'C00023', 'no intake this session');
    SELECT * INTO f FROM admissions.applicant_lookup('9997/9998', '20269999CL');
    PERFORM pg_temp.assert('A programme closed for the session needs no rule, and a candidate JAMB sent for it is told so at registration',
        n = 1 AND f.state = 'closed' AND f.surname = 'CHECKCLOSED'
        AND admissions.programme_is_closed('9997/9998', 'C00023')
        AND NOT admissions.programme_is_closed('9998/9999', 'C00023')
        AND NOT EXISTS (SELECT 1 FROM admissions.policy_findings('9997/9998') x WHERE x.finding LIKE 'Programmes with no%'),
        'closed is a decision on the record, not an omission; the applicant is sent back to JAMB, not let through to nowhere');
END $$;

-- ══ V024 · THE GENERAL CUT-OFF FOR LOADING ══════════════════════════════

-- ── 98. one cut-off for loading, stated per session; none while it is not ──
DO $$
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO admissions.load_cutoff (session, cutoff) VALUES ('9996/9997', 150);
    PERFORM pg_temp.assert('The JAMB lists load under one general cut-off, stated per session before the upload',
        admissions.load_cutoff_for('9996/9997') = 150 AND admissions.load_cutoff_for('9995/9996') IS NULL,
        'a candidate under it is read and held back, whatever the programme; the faculty and programme cut-offs are the screening''s');
END $$;

-- ══ V025 · NOTICES ON THE RECORD, AND THE BASIS OF AN OFFER ═════════════

-- ── 99. a fact written is a notice queued, in the same transaction; an offer names its basis ──
DO $$
DECLARE app uuid; ok boolean; before int; after int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    SELECT a.id INTO app FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE a.session = '9997/9998' AND c.jamb_reg_no = '20269999AP';
    -- the acts of 91–96 queued notices: the fee, the seat, the result, the offer, the place held
    SELECT count(*) INTO before FROM platform.notice WHERE about_id = app;
    -- an offer with no basis is refused; with one it is recorded, and the basis is what goes back to JAMB
    UPDATE admissions.application SET decision_released_at = NULL, decision = NULL, decision_basis = NULL WHERE id = app;
    ok := false;
    BEGIN
        PERFORM admissions.decide_application(app, 'OFFERED', 'check', NULL);
    EXCEPTION WHEN check_violation THEN ok := true;
    END;
    PERFORM admissions.decide_application(app, 'OFFERED', 'check', 'SM');
    PERFORM admissions.release_decisions('9997/9998');
    SELECT count(*) INTO after FROM platform.notice WHERE about_id = app;
    PERFORM pg_temp.assert('A fact written is a notice queued in the same transaction, and an offer names its basis',
        before >= 8 AND after = before + 2 AND ok
        AND (SELECT decision_basis FROM admissions.application WHERE id = app) = 'SM'
        AND (SELECT count(*) FROM platform.notice WHERE about_id = app AND state = 'QUEUED' AND channel = 'SMS') >= 5,
        'the applicant is told the moment the record changes, by email and by SMS, and the outbox says whether it went');
END $$;

-- ══ V026 · THE STUDENT'S SIDE ═══════════════════════════════════════════

-- ── 100–101. the charge is computed, the payment is a reference, the receipt is issued, and the scheme decides what it releases ──
DO $$
DECLARE st uuid := gen_random_uuid(); dept text; o1 uuid := gen_random_uuid(); o2 uuid := gen_random_uuid(); reg uuid;
        v uuid := gen_random_uuid(); until date; pos record; ok boolean; ref text; rcpt text; reach record; units int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    SELECT code INTO dept FROM ref.department ORDER BY code LIMIT 1;
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session,
                                entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990001', 'MOAUM/CHK/99/0001', 'CHECKSTUDENT', 'Invented', 'C00061', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
        ('CHK 101', 'Check Course One', 12, 1, 100, dept, 'Core', 'LIVE'),
        ('CHK 102', 'Check Course Two', 6, 1, 100, dept, 'Elective', 'LIVE');
    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('CHK 101', 'C00061', 100, 'Core'), ('CHK 102', 'C00061', 100, 'Elective');
    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (o1, 'CHK 101', '9999/0000', 1), (o2, 'CHK 102', '9999/0000', 1);

    -- 100. the fees: a charge from the schedule, a reference, a receipt on confirmation, and the position that follows
    PERFORM set_config('moaum.actor_office', 'student', true);
    INSERT INTO people.student_contact (student_id, email, phone) VALUES (st, 'check.student@example.com', '08030000001');
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    INSERT INTO finance.fee_schedule (session, item, amount, level) VALUES ('9999/0000', 'School fees', 100000, 100);
    INSERT INTO finance.fee_schedule (session, item, amount, level) VALUES ('9999/0000', 'Not for 100 level', 999999, 400);
    SELECT * INTO pos FROM finance.position(st, '9999/0000');
    ok := pos.due = 100000 AND pos.balance = 100000 AND pos.instalments_paid = 0;
    ref := finance.new_reference(st, '9999/0000', 50000, NULL);
    PERFORM finance.confirm_payment(ref, 'Bank transfer', 'check');
    SELECT receipt_no INTO rcpt FROM finance.payment_reference WHERE reference = ref;
    SELECT * INTO pos FROM finance.position(st, '9999/0000');
    PERFORM pg_temp.assert('The charge is computed from the schedule, the payment is a reference, and the receipt is issued on confirmation',
        ok AND ref LIKE 'MOAUM-FEE-%' AND rcpt LIKE 'RCT-9999-%' AND pos.paid = 50000 AND pos.balance = 50000 AND pos.instalments_paid = 1
        AND NOT pos.paid_in_full
        AND EXISTS (SELECT 1 FROM platform.notice WHERE about_kind = 'student' AND about_id = st),
        format('before ok=%s ref=%s receipt=%s due=%s paid=%s balance=%s instalments=%s full=%s notices=%s',
               ok, ref, rcpt, pos.due, pos.paid, pos.balance, pos.instalments_paid, pos.paid_in_full,
               (SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = st)));

    -- 101. registration: refused until this semester's school fees are paid in full (V149).
    -- Only half is paid so far, so a submission is refused; paying the balance opens it.
    PERFORM set_config('moaum.actor_office', 'student', true);
    reg := registration.student_draft(st, '9999/0000', 1);
    units := registration.student_choose(reg, ARRAY[o1, o2]);
    ok := false;
    BEGIN
        PERFORM registration.student_submit(reg);   -- 50,000 of 100,000 paid: refused
    EXCEPTION WHEN OTHERS THEN ok := true;
    END;
    -- the clearance scheme is still put in force here for the examination/results gates the later blocks rely on
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    SELECT min(lower(validity)) INTO until FROM policy.version WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND lower(validity) > current_date;
    -- once today reaches the date the earlier block's scheme starts (2026-10-01), that scheme overlaps this one: replace it
    DELETE FROM policy.clearance_rule WHERE version_id IN (SELECT id FROM policy.version
        WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND validity && daterange(current_date, until));
    DELETE FROM policy.clearance_scheme WHERE version_id IN (SELECT id FROM policy.version
        WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND validity && daterange(current_date, until));
    DELETE FROM policy.version
     WHERE kind = 'clearance' AND scope = 'UNIVERSITY' AND validity && daterange(current_date, until);
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'clearance', 'UNIVERSITY', daterange(current_date, until), 'CHECK BUR/9999/1', 'bursar');
    INSERT INTO policy.clearance_scheme VALUES (v, true);
    INSERT INTO policy.clearance_rule VALUES (v, 'REGISTRATION', 'INSTALMENT_1'), (v, 'ID_CARD', 'INSTALMENT_1'), (v, 'LIBRARY', 'INSTALMENT_1'),
        (v, 'HOSTEL', 'NEVER_GATED'), (v, 'EXAMINATION', 'PAID_IN_FULL'), (v, 'RESULTS', 'PAID_IN_FULL'), (v, 'TRANSCRIPT', 'PAID_IN_FULL'), (v, 'CONVOCATION', 'PAID_IN_FULL');
    -- pay the balance so the first semester's fees are cleared in full
    ref := finance.new_reference(st, '9999/0000', 50000, NULL);
    PERFORM finance.confirm_payment(ref, 'Bank transfer', 'balance');
    PERFORM set_config('moaum.actor_office', 'student', true);
    DECLARE sem_ok boolean; sub text; st_after text;
    BEGIN
        sem_ok := finance.semester_cleared(st, '9999/0000', 1);
        sub := registration.student_submit(reg);
        SELECT status INTO st_after FROM registration.course_registration WHERE id = reg;
        PERFORM pg_temp.assert('Course registration for a semester is refused until that semester''s school fees are paid in full',
            units = 18 AND ok AND sem_ok AND sub = 'submitted' AND st_after = 'SUBMITTED',
            format('units=%s refused_when_half_paid=%s semester_cleared=%s submit=%s status=%s',
                   units, ok, sem_ok, sub, st_after));
    END;
END $$;

-- ── 128. results end to end: legacy semesters publish, a carryover is repeated and both attempts count in the CGPA, and the fee gate withholds results until fees are paid in full ──
-- Builds on the clearance scheme the block above put in force (RESULTS is
-- PAID_IN_FULL). One student sits two sessions: a course failed at the first
-- sitting and repeated at the second, so the cumulative must carry both.
DO $$
DECLARE
    st uuid := gen_random_uuid();
    dept text;
    cum record; sem1_gpa numeric; last_cgpa numeric;
    attempts int; before_gate boolean; after_gate boolean;
    ref text; pos record;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'records', true);
    PERFORM set_config('moaum.reason', 'CHECK results pipeline', true);
    SELECT code INTO dept FROM ref.department ORDER BY code LIMIT 1;

    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode,
                                entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990002', 'MOAUM/CHK/99/0002', 'CHECKRESULT', 'Invented', 'C00061', 'UTME',
            '9991/9992', 100, 200, 'ACTIVE', now());

    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
        ('CHK 201', 'Check Result One',   3, 1, 100, dept, 'Core', 'LIVE'),
        ('CHK 202', 'Check Result Two',   3, 1, 100, dept, 'Elective',   'LIVE'),
        ('CHK 203', 'Check Result Three', 3, 1, 200, dept, 'Core', 'LIVE');

    -- first session: CHK 201 failed (30 → F, 0.0), CHK 202 passed (70 → A, 5.0)
    PERFORM assessment.import_legacy_semester('9991/9992', 1, $rows$[
        {"matric":"MOAUM/CHK/99/0002","course":"CHK 201","total":"30"},
        {"matric":"MOAUM/CHK/99/0002","course":"CHK 202","total":"70"}
    ]$rows$::jsonb, true);
    -- second session: CHK 201 repeated and passed (55 → C, 3.0), CHK 203 taken (60 → B, 4.0)
    PERFORM assessment.import_legacy_semester('9992/9993', 1, $rows$[
        {"matric":"MOAUM/CHK/99/0002","course":"CHK 201","total":"55"},
        {"matric":"MOAUM/CHK/99/0002","course":"CHK 203","total":"60"}
    ]$rows$::jsonb, true);

    -- the carryover shows as two attempts of the same course
    SELECT count(*) INTO attempts FROM assessment.student_results(st) WHERE course_code = 'CHK 201' AND published;

    -- semester GPA (first session) and cumulative to the second session
    SELECT gpa INTO sem1_gpa FROM assessment.student_gpa(st) WHERE session = '9991/9992' AND semester = 1;
    SELECT cgpa INTO last_cgpa FROM assessment.student_gpa(st) WHERE session = '9992/9993' AND semester = 1;
    SELECT * INTO cum FROM assessment.student_cumulative(st, '9992/9993', 1);

    -- the fee gate: charge 100,000, RESULTS is PAID_IN_FULL, so results are withheld until fully paid
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    INSERT INTO finance.fee_schedule (session, item, amount, level) VALUES ('9992/9993', 'School fees', 100000, 200);
    before_gate := finance.clears(st, '9992/9993', 'RESULTS');       -- nothing paid → withheld
    ref := finance.new_reference(st, '9992/9993', 100000, NULL);
    PERFORM finance.confirm_payment(ref, 'Bank transfer', 'check');
    SELECT * INTO pos FROM finance.position(st, '9992/9993');
    after_gate := finance.clears(st, '9992/9993', 'RESULTS');        -- paid in full → released

    PERFORM pg_temp.assert(
        'Results publish end to end: a repeated course counts both attempts in the CGPA, and the fee gate withholds results until fees are paid in full',
        attempts = 2
        AND sem1_gpa = 2.50 AND last_cgpa = 3.00
        AND cum.tcr = 12 AND cum.tce = 9 AND cum.twgp = 36 AND cum.cgpa = 3.00 AND cum.prev_cgpa = 2.50
        AND pos.paid_in_full AND before_gate = false AND after_gate = true,
        format('attempts=%s sem1_gpa=%s cgpa=%s tcr=%s tce=%s twgp=%s cum_cgpa=%s prev=%s full=%s gate_before=%s gate_after=%s',
               attempts, sem1_gpa, last_cgpa, cum.tcr, cum.tce, cum.twgp, cum.cgpa, cum.prev_cgpa, pos.paid_in_full, before_gate, after_gate));
END $$;

-- ══ V027 · THE LOOPS THE STUDENT SEES CLOSED ═══════════════════════════

-- ── 102. attendance over the class list, the timetable from the slots, the card on the matriculation number ──
DO $$
DECLARE st uuid; o1 uuid; n int; rate record; card text; tt int; ok boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'hod', true);
    SELECT id INTO st FROM people.student WHERE surname = 'CHECKSTUDENT';
    SELECT o.id INTO o1 FROM catalogue.offering o WHERE o.course_code = 'CHK 101' AND o.session = '9999/0000';
    -- the registration of 101 approved, so the class list carries the student
    UPDATE registration.course_registration SET status = 'APPROVED', approved_at = now(), approved_by = gen_random_uuid()
     WHERE student_id = st AND session = '9999/0000';
    INSERT INTO catalogue.class_slot (offering_id, weekday, starts_at, ends_at, venue) VALUES (o1, 3, '08:00', '10:00', 'LT 2');
    SELECT count(*) INTO tt FROM registration.student_timetable(st, '9999/0000', 1);
    -- attendance: two lectures, present at one
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    n := registration.mark_attendance(o1, current_date - 7, ARRAY[st]);
    n := n + registration.mark_attendance(o1, current_date, ARRAY[]::uuid[]);
    SELECT * INTO rate FROM registration.attendance_rate(st, '9999/0000', 1) WHERE course_code = 'CHK 101';
    -- the card: refused before a scheme releases ID_CARD? the scheme of 101 is in force today and releases it at instalment 1, which is paid
    PERFORM set_config('moaum.actor_office', 'library', true);
    card := credentials.issue_identity_card(st, NULL);
    ok := false;
    BEGIN
        PERFORM credentials.issue_identity_card(gen_random_uuid(), NULL);
    EXCEPTION WHEN OTHERS THEN ok := true;
    END;
    PERFORM pg_temp.assert('The register is marked over the class list, the timetable comes from the slots, and the card is issued on the matriculation number',
        tt = 1 AND n = 2 AND rate.attended = 1 AND rate.held = 2 AND rate.rate = 50
        AND card ~ '^MOAUM/ID/[0-9]{2}/[0-9]{5}$' AND ok
        AND (SELECT count(*) FROM credentials.identity_card WHERE student_id = st AND state = 'ISSUED') = 1,
        'nothing typed against the student: the lecturer marks the roll, the department gives the slot, the Library issues the card the scheme released');
END $$;

-- ── 103. a course with no sheet is unpublished, not unknown (V028) ──
DO $$
DECLARE st uuid; v_total int; v_unknown int; v_leaked int;
BEGIN
    SELECT id INTO st FROM people.student WHERE surname = 'CHECKSTUDENT';
    SELECT count(*), count(*) FILTER (WHERE published IS NULL),
           count(*) FILTER (WHERE NOT published AND (ca IS NOT NULL OR exam IS NOT NULL OR total IS NOT NULL OR grade IS NOT NULL))
      INTO v_total, v_unknown, v_leaked
      FROM assessment.student_results(st);
    PERFORM pg_temp.assert('A registered course with no published sheet reads as unpublished, never as unknown, and carries no mark',
        v_total >= 1 AND v_unknown = 0 AND v_leaked = 0,
        format('%s rows, %s with published NULL, %s unpublished rows carrying a mark', v_total, v_unknown, v_leaked));
END $$;

-- ── 104. Senate's approval of the list changes the status on the minute, tells the graduand, and the student sees it (V029) ──
DO $$
DECLARE st uuid := gen_random_uuid(); n int; v_status text; v_notices int; g record;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session,
                                entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990104', 'MOAUM/CHK/99/0104', 'CHECKGRADUAND', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 400, 'ACTIVE', now());
    PERFORM set_config('moaum.actor_office', 'student', true);
    INSERT INTO people.student_contact (student_id, email, phone) VALUES (st, 'check.graduand@example.com', '08030000104');
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet) VALUES (gen_random_uuid(), st, '9999/0000', 3.61, 'B.Sc. COMPUTER SCIENCE', NULL);
    SELECT * INTO g FROM records.student_graduation(st);
    IF g.senate_state <> 'AWAITING' OR g.status <> 'ACTIVE' THEN RAISE EXCEPTION 'before approval: % %', g.senate_state, g.status; END IF;
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    n := records.approve_awards('9999/0000', 'CHECK SEN/9999/7');
    SELECT status INTO v_status FROM people.student WHERE id = st;
    SELECT count(*) INTO v_notices FROM platform.notice WHERE about_kind = 'student' AND about_id = st;
    SELECT * INTO g FROM records.student_graduation(st);
    PERFORM pg_temp.assert('Senate''s approval of the list changes the status on the minute, tells the graduand, and the student sees the class and the units still holding',
        -- four notices: Senate's approval by email and SMS, and the change of status on the register by email and SMS
        n >= 1 AND v_status = 'GRADUATED' AND v_notices = 4 AND g.senate_state = 'APPROVED' AND g.senate_minute = 'CHECK SEN/9999/7'
        AND g.class_of_degree = 'Second Class Honours (Upper)' AND NOT g.cleared AND g.units_holding = 8 AND g.certificate_no IS NULL
        AND EXISTS (SELECT 1 FROM people.status_change WHERE student_id = st AND to_status = 'GRADUATED' AND instrument = 'CHECK SEN/9999/7'),
        format('approved=%s status=%s notices=%s state=%s class=%s cleared=%s holding=%s', n, v_status, v_notices, g.senate_state, g.class_of_degree, g.cleared, g.units_holding));
END $$;

-- ── 105. the hostel draw is a function of the seed; a hold lapses to the next name; the fee confirms the bed (V030) ──
DO $$
DECLARE s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid(); r record; d record; v1 record; v2 record; v3 record;
        v_ref text; v_lapsed int; ok boolean; before_pos int[]; after_pos int[];
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at, sex) VALUES
        (s1, 'MOAUM/ADM/99/990105', 'MOAUM/CHK/99/0105', 'CHECKHOSTEL', 'Invented One', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now(), 'F'),
        (s2, 'MOAUM/ADM/99/990106', 'MOAUM/CHK/99/0106', 'CHECKHOSTEL', 'Invented Two', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now(), 'F'),
        (s3, 'MOAUM/ADM/99/990107', 'MOAUM/CHK/99/0107', 'CHECKHOSTEL', 'Invented Three', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now(), 'F');
    PERFORM set_config('moaum.actor_office', 'student', true);
    INSERT INTO people.student_contact (student_id, email, phone) VALUES (s1, 'check.hostel1@example.com', '08030000105');
    PERFORM set_config('moaum.actor_office', 'services', true);
    INSERT INTO hostel.hall (code, name, sex) VALUES ('CHKH', 'Check Hall', 'F');
    INSERT INTO hostel.room (hall_code, block, room_no, beds) VALUES ('CHKH', 'A', '1', 2);   -- two beds for three applicants
    -- the V030 draw on its own: V290's two prerequisites (school fees paid, registration submitted) are the window's to switch, and off here
    INSERT INTO hostel.session_setting (session, fee, hold_hours, require_school_fees, require_registration) VALUES ('9999/0000', 40000, 72, false, false);
    PERFORM set_config('moaum.actor_office', 'student', true);
    PERFORM hostel.apply(s1, '9999/0000', 'CHKH', 'NONE', NULL);
    PERFORM hostel.apply(s2, '9999/0000', NULL, 'NONE', NULL);
    PERFORM hostel.apply(s3, '9999/0000', 'CHKH', 'NONE', NULL);
    ok := false;
    BEGIN PERFORM hostel.apply(s1, '9999/0000', NULL, 'NONE', NULL); EXCEPTION WHEN OTHERS THEN ok := true; END;   -- one application per session
    PERFORM set_config('moaum.actor_office', 'services', true);
    SELECT * INTO d FROM hostel.draw('9999/0000', 'CHECK-SEED-9999');
    SELECT array_agg(ap.draw_position ORDER BY ap.student_id) INTO before_pos FROM hostel.application ap WHERE ap.session = '9999/0000';
    -- the order is the seed's: the same seed over the same applicants gives the same positions
    SELECT array_agg(rank ORDER BY sid) INTO after_pos FROM (
        SELECT ap.student_id AS sid, row_number() OVER (ORDER BY md5('CHECK-SEED-9999' || ap.student_id::text))::int AS rank
          FROM hostel.application ap WHERE ap.session = '9999/0000') q;
    SELECT * INTO v1 FROM hostel.student_view(s1, '9999/0000');
    SELECT * INTO v2 FROM hostel.student_view(s2, '9999/0000');
    SELECT * INTO v3 FROM hostel.student_view(s3, '9999/0000');
    -- the third position has no bed and is the reserve; a hold that expires goes to it
    UPDATE hostel.allocation SET held_until = now() - interval '1 hour' WHERE session = '9999/0000' AND draw_position = 1;
    v_lapsed := hostel.lapse_holds('9999/0000');
    -- the fee: a reference for a held bed, confirmed by the Bursary, makes it CONFIRMED
    PERFORM set_config('moaum.actor_office', 'student', true);
    SELECT ap.id INTO r FROM hostel.application ap WHERE ap.session = '9999/0000' AND ap.state = 'ALLOCATED' AND ap.draw_position = 2;
    v_ref := hostel.new_fee_reference(r.id);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM finance.confirm_payment(v_ref, 'Bank transfer', 'check');
    PERFORM pg_temp.assert('The hostel draw is a function of the published seed, a lapsed hold passes to the next name, and the confirmed fee makes the bed a room',
        d.allocated = 2 AND d.unsuccessful = 1 AND d.priority = 0 AND ok AND before_pos = after_pos
        AND v_lapsed = 1
        AND (SELECT count(*) FROM hostel.application ap WHERE ap.session = '9999/0000' AND ap.state = 'LAPSED') = 1
        AND (SELECT count(*) FROM hostel.allocation al WHERE al.session = '9999/0000' AND al.basis = 'RESERVE' AND al.lapsed_at IS NULL) = 1
        AND v_ref LIKE 'MOAUM-FEE-%'
        AND (SELECT ap.state FROM hostel.application ap WHERE ap.id = r.id) = 'CONFIRMED'
        AND (SELECT count(*) FROM hostel.allocation al WHERE al.session = '9999/0000' AND al.lapsed_at IS NULL AND al.ended_at IS NULL) = 2,
        format('drawn=%s/%s/%s dup_refused=%s order=%s lapsed=%s ref=%s states=%s', d.allocated, d.unsuccessful, d.priority, ok, before_pos = after_pos, v_lapsed, v_ref,
               (SELECT string_agg(ap.state || '@' || coalesce(ap.draw_position::text, '-'), ',' ORDER BY ap.draw_position) FROM hostel.application ap WHERE ap.session = '9999/0000')));
END $$;

-- ── 106. a loan has a due date; a late return posts the fine at the rate in force; an overdue patron is issued nothing; the fine settles on its reference (V031) ──
DO $$
DECLARE st uuid := gen_random_uuid(); it uuid := gen_random_uuid(); l1 uuid; ret record; stg record; ok1 boolean := false; ok2 boolean := false; v_ref text; v_due date;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990108', 'MOAUM/CHK/99/0108', 'CHECKREADER', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 200, 'ACTIVE', now());
    PERFORM set_config('moaum.actor_office', 'library', true);
    UPDATE library.setting SET loan_days = 14, fine_per_day = 50, max_loans = 3, max_renewals = 1 WHERE row_no = 1;
    INSERT INTO library.item (id, title, author) VALUES (it, 'CHECK Introduction to Algorithms', 'Invented');
    INSERT INTO library.copy (accession, item_id) VALUES ('CHK/000001', it), ('CHK/000002', it);
    l1 := library.issue('CHK/000001', st, NULL);
    v_due := (SELECT due_on FROM library.loan WHERE id = l1);
    -- the same copy cannot be issued twice
    BEGIN PERFORM library.issue('CHK/000001', st, NULL); EXCEPTION WHEN OTHERS THEN ok1 := true; END;
    -- time passes: the loan is three days overdue, so nothing else is issued and a renewal is refused
    UPDATE library.loan SET due_on = current_date - 3 WHERE id = l1;
    BEGIN PERFORM library.issue('CHK/000002', st, NULL); EXCEPTION WHEN OTHERS THEN ok2 := true; END;
    SELECT * INTO ret FROM library.give_back('CHK/000001');
    SELECT * INTO stg FROM library.standing(st);
    -- the fine is a reference like every other; confirming it settles the fine and clears the patron
    PERFORM set_config('moaum.actor_office', 'student', true);
    v_ref := library.fine_reference(l1);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM finance.confirm_payment(v_ref, 'Card', 'check');
    PERFORM pg_temp.assert('A loan has a due date, a late return posts the fine at the rate in force, an overdue patron is issued nothing, and the fine settles on its reference',
        v_due = current_date + 14 AND ok1 AND ok2 AND ret.days_overdue = 3 AND ret.fine = 150
        AND stg.on_loan = 0 AND stg.fines_unpaid = 150 AND NOT stg.clear
        AND v_ref LIKE 'MOAUM-FEE-%'
        AND (SELECT fine_settled_at IS NOT NULL FROM library.loan WHERE id = l1)
        AND (SELECT clear FROM library.standing(st))
        AND (SELECT state FROM library.copy WHERE accession = 'CHK/000001') = 'AVAILABLE',
        format('due=%s twice_refused=%s overdue_refused=%s days=%s fine=%s standing=%s/%s/%s ref=%s', v_due, ok1, ok2, ret.days_overdue, ret.fine, stg.on_loan, stg.fines_unpaid, stg.clear, v_ref));
END $$;

-- ── 107. the clinic: the student sees the outcome and never the note; the record's opening is logged; the Registry sees the fitness and nothing else (V032) ──
DO $$
DECLARE st uuid := gen_random_uuid(); cl uuid := gen_random_uuid(); ap uuid; vi uuid; sv record; ft record; n_notes int; n_access int; ok boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', cl::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990109', 'MOAUM/CHK/99/0109', 'CHECKPATIENT', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (cl, 'CHK-CLIN', 'CHECKCLINICIAN', 'Invented');
    PERFORM set_config('moaum.actor_office', 'student', true);
    ap := health.book(st, 'Persistent headache, 4 days', now() + interval '1 day');
    BEGIN PERFORM health.book(st, 'Again', now() + interval '2 days'); EXCEPTION WHEN OTHERS THEN ok := true; END;   -- one appointment stands
    PERFORM health.consent(st, 'O+', 'AA', 'Penicillin');
    PERFORM set_config('moaum.actor_office', 'services', true);
    vi := health.arrive(st, 'Persistent headache, 4 days', 'STANDARD', ap);
    PERFORM health.see(vi, cl);
    PERFORM health.conclude(vi, cl, 'Treated, analgesic dispensed', NULL, 'BP 120/80, no photophobia; review in a week if it persists', 'FIT');
    SELECT * INTO sv FROM health.student_visits(st) LIMIT 1;
    SELECT * INTO ft FROM health.fitness_of(st);
    SELECT count(*) INTO n_notes FROM health.note WHERE visit_id = vi;
    SELECT count(*) INTO n_access FROM health.record_access WHERE student_id = st AND person_id = cl;
    PERFORM pg_temp.assert('The student sees the outcome of a visit and never the note, the opening of the record is logged against the clinician, and the Registry sees the fitness and nothing else',
        ok AND sv.state = 'DONE' AND sv.outcome = 'Treated, analgesic dispensed' AND sv.clinician = 'CHECKCLINICIAN, Invented'
        AND n_notes = 1 AND n_access >= 1 AND ft.fitness = 'FIT' AND ft.fitness_on = current_date
        AND (SELECT state FROM health.appointment WHERE id = ap) = 'SEEN'
        AND (SELECT blood_group FROM health.profile WHERE student_id = st) = 'O+',
        format('dup_refused=%s state=%s outcome=%s notes=%s access=%s fitness=%s', ok, sv.state, sv.outcome, n_notes, n_access, ft.fitness));
END $$;

-- ── 108. a remittance is split against the register; suspense is owned; the wallet is append-only and applies through the same confirmation (V033) ──
DO $$
DECLARE s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); r record; v_row uuid; v_ref text; pos record; bal numeric; ok boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
        (s1, 'MOAUM/ADM/99/990110', 'MOAUM/CHK/99/0110', 'CHECKWALLET', 'Invented One', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now()),
        (s2, 'MOAUM/ADM/99/990111', 'MOAUM/CHK/99/0111', 'CHECKWALLET', 'Invented Two', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    -- the schedule of 100 charges 100,000 at 100 level in 9999/0000; the Fund remits 60,000 for one student on the register and one number that is not
    SELECT * INTO r FROM finance.load_nelfund_batch('CHECK NLF/9999/1', '9999/0000', current_date, NULL,
        '[{"matricNo":"MOAUM/CHK/99/0110","name":"CHECKWALLET, Invented One","amount":"60000"},{"matricNo":"MOAUM/CHK/99/9999","name":"NOBODY, Invented","amount":"60000"}]'::jsonb);
    bal := finance.wallet_balance(s1);
    -- suspense is owned: the Registry matches the unmatched row to the second student, on evidence
    SELECT id INTO v_row FROM finance.nelfund_row WHERE batch_id = r.batch_id AND state = 'UNMATCHED';
    BEGIN PERFORM finance.match_nelfund_row(v_row, s2, NULL); EXCEPTION WHEN OTHERS THEN ok := true; END;   -- not on a guess
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    PERFORM finance.match_nelfund_row(v_row, s2, 'Number in the prior format; identity confirmed in person');
    -- the student applies the wallet: the invoice settles through the same confirmation as every payment, with the wallet as the channel
    PERFORM set_config('moaum.actor_office', 'student', true);
    v_ref := finance.apply_wallet(s1, '9999/0000', NULL);
    SELECT * INTO pos FROM finance.position(s1, '9999/0000');
    PERFORM pg_temp.assert('A remittance is split against the register, suspense is owned and matched on evidence, and the wallet applies to the invoice through the same confirmation as every payment',
        r.matched = 1 AND r.unmatched = 1 AND r.amount = 120000 AND bal = 60000 AND ok
        AND finance.wallet_balance(s2) = 60000
        AND v_ref LIKE 'MOAUM-FEE-%' AND finance.wallet_balance(s1) = 0 AND pos.paid = 60000 AND pos.instalments_paid = 1
        AND (SELECT channel FROM finance.payment_reference WHERE reference = v_ref) = 'NELFUND wallet'
        AND (SELECT count(*) FROM finance.wallet_statement(s1)) = 2,
        format('matched=%s unmatched=%s amount=%s bal=%s guess_refused=%s ref=%s paid=%s inst=%s', r.matched, r.unmatched, r.amount, bal, ok, v_ref, pos.paid, pos.instalments_paid));
END $$;

-- ── 109. a course space is the roll: material reaches the registered, a submission is theirs, the gradebook promotes into the sheet's CA as a version with its reason (V035) ──
DO $$
DECLARE st uuid; o1 uuid; sh uuid; lect uuid := gen_random_uuid(); m uuid; a uuid; sub uuid; ok boolean := false; gb record; n int; l record; other uuid := gen_random_uuid();
BEGIN
    PERFORM set_config('moaum.actor_id', lect::text, true);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    SELECT id INTO st FROM people.student WHERE surname = 'CHECKSTUDENT';
    SELECT o.id INTO o1 FROM catalogue.offering o WHERE o.course_code = 'CHK 101' AND o.session = '9999/0000';
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (other, 'MOAUM/ADM/99/990112', 'MOAUM/CHK/99/0112', 'CHECKOUTSIDER', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    INSERT INTO lms.material (id, offering_id, week, title, kind, link, published_at, published_by) VALUES (gen_random_uuid(), o1, 1, 'CHECK week 1', 'READING', 'https://example.com/w1', now(), lect) RETURNING id INTO m;
    INSERT INTO lms.assignment (id, offering_id, title, kind, closes_at, weight, out_of, created_by) VALUES (gen_random_uuid(), o1, 'CHECK problem set', 'INDIVIDUAL', now() + interval '7 days', 20, 100, lect) RETURNING id INTO a;
    PERFORM set_config('moaum.actor_office', 'student', true);
    BEGIN PERFORM lms.submit(a, other, 'I am not on this roll', NULL, NULL, NULL); EXCEPTION WHEN OTHERS THEN ok := true; END;   -- the roll, nobody else
    sub := lms.submit(a, st, 'My answer', NULL, NULL, NULL);
    INSERT INTO lms.access (material_id, student_id) VALUES (m, st);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    UPDATE lms.submission SET mark = 80, marked_at = now(), marked_by = lect WHERE id = sub;
    SELECT * INTO gb FROM lms.gradebook(o1) WHERE student_id = st;
    -- the sheet of 102 stands at entry on this offering; promoting writes the CA as a version with its reason
    SELECT id INTO sh FROM assessment.score_sheet WHERE offering_id = o1;
    IF sh IS NULL THEN INSERT INTO assessment.score_sheet (id, offering_id) VALUES (gen_random_uuid(), o1) RETURNING id INTO sh; END IF;
    n := lms.promote_ca(o1);
    SELECT * INTO l FROM assessment.latest_scores(sh) x WHERE x.student_id = st;
    PERFORM pg_temp.assert('A course space is the roll: an outsider cannot submit, the gradebook is weighted from the marks, and promoting it writes the CA into the score sheet as a version',
        ok AND gb.submitted = 1 AND gb.marked = 1 AND gb.total = 16 AND gb.weight_marked = 20 AND n >= 1 AND l.ca = 16
        AND (SELECT count(*) FROM lms.access WHERE material_id = m) = 1,
        format('outsider_refused=%s submitted=%s marked=%s total=%s weight=%s promoted=%s ca=%s', ok, gb.submitted, gb.marked, gb.total, gb.weight_marked, n, l.ca));
END $$;

-- ── 110. a request carries a reference and an office; the answer is on the record and the student is told (V036) ──
DO $$
DECLARE st uuid; v_ref text; rq record; n_notices int; ok boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'student', true);
    SELECT id INTO st FROM people.student WHERE surname = 'CHECKSTUDENT';
    v_ref := platform.raise_request(st, 'bursar', 'Payment not reflecting after 3 days', 'Reference MOAUM-FEE-990001');
    BEGIN PERFORM platform.raise_request(st, 'chancellor', 'Nobody', NULL); EXCEPTION WHEN OTHERS THEN ok := true; END;
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    SELECT count(*) INTO n_notices FROM platform.notice WHERE about_kind = 'student' AND about_id = st;
    PERFORM platform.answer_request((SELECT id FROM platform.service_request WHERE ref = v_ref), 'The payment was matched this morning; your receipt is on the Fees page.', true);
    SELECT * INTO rq FROM platform.service_request WHERE ref = v_ref;
    PERFORM pg_temp.assert('A request carries a reference and an office, the answer is on the record in the officer''s name, and the student is told',
        v_ref ~ '^SR-[0-9]{4}-[0-9]{5}$' AND ok AND rq.state = 'RESOLVED' AND rq.answered_by IS NOT NULL AND rq.office_code = 'bursar'
        AND (SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = st) = n_notices + 2,
        format('ref=%s bad_office_refused=%s state=%s notices=+%s', v_ref, ok, rq.state, (SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = st) - n_notices));
END $$;

-- ── 111. a bank credit is posted only when two officers have agreed; the day book carries every confirmation; the gateway's words are kept (V037) ──
DO $$
DECLARE st uuid := gen_random_uuid(); one uuid := gen_random_uuid(); two uuid := gen_random_uuid(); cr uuid; v_ref text; ok1 boolean := false; ok2 boolean := false; v_out text; n_book int; ev uuid;
BEGIN
    PERFORM set_config('moaum.actor_id', one::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990113', 'MOAUM/CHK/99/0113', 'CHECKPAYER', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    PERFORM set_config('moaum.actor_office', 'student', true);
    v_ref := finance.new_reference(st, '9999/0000', 40000, NULL);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    cr := finance.record_bank_credit(current_date, 'Zenith Bank', 'BR/44821', 40000, 'A GUARANTOR', 'teller slip, no reference quoted');
    BEGIN PERFORM finance.propose_bank_credit(cr, v_ref, NULL); EXCEPTION WHEN OTHERS THEN ok1 := true; END;   -- a proposal says on what evidence
    PERFORM finance.propose_bank_credit(cr, v_ref, 'Payer named on the slip is the guarantor of record on this student''s file');
    BEGIN PERFORM finance.approve_bank_credit(cr); EXCEPTION WHEN OTHERS THEN ok2 := true; END;   -- not by the same officer
    PERFORM set_config('moaum.actor_id', two::text, true);
    v_out := finance.approve_bank_credit(cr);
    SELECT count(*) INTO n_book FROM finance.day_book(current_date, current_date) b WHERE b.reference = v_ref AND b.channel = 'Bank branch';
    ev := finance.log_gateway_event('paystack', 'WEBHOOK', 'charge.success', 'MOAUM-FEE-NOBODY-0000', '1', 100, 'success', true, 'UNKNOWN_REFERENCE', '{"forged": true}'::jsonb);
    PERFORM finance.resolve_gateway_event(ev, 'A reference this portal never generated; discarded');
    PERFORM pg_temp.assert('A bank credit is posted only when two officers have independently agreed, the day book carries the posting, and the gateway''s words are kept and resolved on the record',
        ok1 AND ok2 AND v_out = 'confirmed' AND n_book = 1
        AND (SELECT state FROM finance.bank_credit WHERE id = cr) = 'POSTED'
        AND (SELECT approved_by <> proposed_by FROM finance.bank_credit WHERE id = cr)
        AND (SELECT confirmed_at IS NOT NULL FROM finance.payment_reference WHERE reference = v_ref)
        AND (SELECT resolved_by = two AND resolution IS NOT NULL FROM finance.gateway_event WHERE id = ev),
        format('why_required=%s same_officer_refused=%s posted=%s in_day_book=%s', ok1, ok2, v_out, n_book));
END $$;

-- ── 112. passport, date of birth and O'Level attach only once the candidate's admission list is committed (V038) ──
DO $$
DECLARE b_id uuid := gen_random_uuid(); c_id uuid := gen_random_uuid(); c_key text := '202612340001XX';
        before_attach bigint; after_attach bigint; held bigint;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    -- a list loaded but NOT committed, and a candidate record standing against it
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b_id, '9995/9996', 'CAPS_DOWNLOAD', 'UTME', '\xF2'::bytea, 1, current_date, gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode)
    VALUES (gen_random_uuid(), b_id, '9995/9996', c_key, '{}'::jsonb, 'CHECKUNCOMMITTED', 'Invented', 'C00023', 210, 'UTME');
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
    VALUES (c_id, '9995/9996', c_key, 'CHECKUNCOMMITTED', 'Invented', 'B.Sc. COMPUTER SCIENCE', 'UTME', 100, 'PROPOSED');
    -- the passport, the date of birth and the O'Level all arrive, readable
    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, bytes, width_px, height_px)
    VALUES (gen_random_uuid(), '9995/9996', 'PASSPORT', c_key || '.jpg', c_key, 'EXACT', 4000, 132, 151);
    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload)
    VALUES (gen_random_uuid(), '9995/9996', 'DATE_OF_BIRTH', c_key || ' dob', c_key, 'COLUMN', '{"dob":"05-07-2004"}'::jsonb),
           (gen_random_uuid(), '9995/9996', 'OLEVEL', c_key || ' ol', c_key, 'COLUMN', '{"sittings":[]}'::jsonb);
    -- the sweep attaches NOTHING while the list is not committed
    SELECT coalesce(sum(newly_attached), 0) INTO before_attach FROM admissions.attach_pending('9995/9996');
    SELECT count(*) INTO held FROM admissions.attachment_state('9995/9996') s WHERE s.finding = 'Held for a candidate not yet committed' AND s.n = 3;
    -- the Academic Office commits the list; now the three attach
    UPDATE admissions.caps_batch SET committed_at = now() WHERE id = b_id;
    SELECT coalesce(sum(newly_attached), 0) INTO after_attach FROM admissions.attach_pending('9995/9996');
    PERFORM pg_temp.assert('A candidate''s passport, date of birth and O''Level are held until the admission list is committed, then attach',
        before_attach = 0 AND held = 1 AND after_attach = 3
        AND (SELECT count(*) FROM admissions.attachment WHERE session = '9995/9996' AND candidate_id = c_id) = 3
        AND admissions.candidate_is_committed('9995/9996', c_key),
        format('before_commit=%s held_finding=%s after_commit=%s', before_attach, held, after_attach));
END $$;

-- ── 113. a gateway key set from the dashboard is encrypted at rest, decrypts only with the passphrase, is never carried by the config, and the act is on the spine (V039) ──
DO $$
DECLARE key text := 'a check config passphrase'; enc bytea; back text; cfg record; ev int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM finance.set_gateway_secret('paystack', 'sk_test_check_secret_key_1234', NULL, 'TEST', '1234', key);
    SELECT secret_enc INTO enc FROM finance.gateway_credential WHERE gateway = 'paystack';
    SELECT finance.gateway_secret('paystack', key) INTO back;
    SELECT * INTO cfg FROM finance.gateway_config() WHERE gateway = 'paystack';
    SELECT count(*) INTO ev FROM finance.gateway_credential_event WHERE gateway = 'paystack' AND kind = 'SET';
    PERFORM pg_temp.assert('A dashboard gateway key is encrypted at rest, decrypts only with the passphrase, is never carried by the config, and the act is on the spine',
        enc IS NOT NULL AND enc::text <> 'sk_test_check_secret_key_1234' AND back = 'sk_test_check_secret_key_1234'
        AND finance.gateway_secret('paystack', 'the wrong passphrase') IS NULL
        AND cfg.configured AND cfg.mode = 'TEST' AND cfg.last4 = '1234' AND ev = 1,
        format('encrypted=%s decrypts=%s config_last4=%s events=%s', enc IS NOT NULL, back IS NOT NULL, cfg.last4, ev));
END $$;

-- ── 114. a pay run computes gross and the statutory deductions, and only a second officer approves it (V069) ──
DO $$
DECLARE p uuid := gen_random_uuid(); a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
        v_run uuid; v_slips int; s record; ok_two boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'check: payroll run', true);
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (p, 'CHK-PAY', 'CHECKSTAFF', 'Invented');
    INSERT INTO hrm.employment (person_id, staff_no, grade, step, category, appointment_date, status)
        VALUES (p, 'CHK-PAY-001', 'CONTISS 9', 1, 'NON_ACADEMIC', current_date, 'ACTIVE');
    SELECT run_id INTO v_run FROM hrm.build_pay_run('2999-01-01', 'check');
    SELECT count(*) INTO v_slips FROM hrm.payslip WHERE run_id = v_run AND staff_no = 'CHK-PAY-001';
    SELECT * INTO s FROM hrm.payslip WHERE run_id = v_run AND staff_no = 'CHK-PAY-001';
    -- the builder cannot approve; a second officer can
    BEGIN
        PERFORM hrm.approve_pay_run(v_run);            -- still actor a1, the builder — must be refused
    EXCEPTION WHEN others THEN
        PERFORM set_config('moaum.actor_id', a2::text, true);
        PERFORM hrm.approve_pay_run(v_run);            -- a different officer — must pass
        ok_two := true;
    END;
    PERFORM pg_temp.assert('A pay run computes gross and deductions, and only a second officer approves it',
        v_slips = 1 AND s.gross = 232000 AND s.pension = 17360.00 AND s.paye > 0
        AND s.net = s.gross - s.pension - s.paye
        AND ok_two AND (SELECT state FROM hrm.pay_run WHERE id = v_run) = 'APPROVED',
        format('slips=%s gross=%s pension=%s paye=%s net=%s two_officer=%s', v_slips, s.gross, s.pension, s.paye, s.net, ok_two));
    DELETE FROM hrm.payslip WHERE run_id = v_run;
    DELETE FROM hrm.pay_run WHERE id = v_run;
    DELETE FROM hrm.employment WHERE person_id = p;
    DELETE FROM iam.person WHERE id = p;
END $$;

-- ── 116. an inter-departmental transfer is recommended, approved by Senate, guarded to one live case, and raises a non-refundable fee (V070) ──
DO $$
DECLARE stu uuid := gen_random_uuid(); a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
        v_app uuid; v_state text; v_ref text; ok_guard boolean := false; prog text; prog2 text;
BEGIN
    SELECT code INTO prog FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1;
    SELECT code INTO prog2 FROM ref.programme WHERE NOT archived AND code <> prog ORDER BY code LIMIT 1;
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'check: transfer', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (stu, 'MOAUM/ADM/20/999123', 'MOAUM/XX/20/9123', 'CHECKXFER', 'Invented', prog, 'UTME', '2020/2021', 100, 200, 'ACTIVE', now());
    -- the student applies
    PERFORM set_config('moaum.actor_id', stu::text, true);
    PERFORM set_config('moaum.actor_office', 'student', true);
    v_app := people.apply_transfer(stu, prog2, 'Passion for the field', 210);
    -- a second live application is refused
    BEGIN PERFORM people.apply_transfer(stu, prog2, 'again', NULL); EXCEPTION WHEN others THEN ok_guard := true; END;
    -- the committee recommends for 200, Senate (a different officer) approves
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM people.review_transfer(v_app, true, 200, 'In good standing');
    PERFORM set_config('moaum.actor_id', a2::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    PERFORM people.senate_transfer(v_app, true, NULL);
    SELECT state INTO v_state FROM people.transfer_application WHERE id = v_app;
    -- the fee has no default: the Bursary sets it, then the reference carries that amount
    UPDATE finance.fee_setting SET transfer_fee = 10000 WHERE id = 1;
    v_ref := people.transfer_fee_reference(v_app);
    PERFORM pg_temp.assert('An inter-departmental transfer reaches Senate approval, guards one live case, and raises the Bursary-set fee',
        v_state = 'APPROVED' AND ok_guard AND v_ref IS NOT NULL
        AND (SELECT amount FROM finance.payment_reference WHERE reference = v_ref) = 10000,
        format('state=%s guard=%s ref=%s', v_state, ok_guard, v_ref));
    UPDATE finance.fee_setting SET transfer_fee = NULL WHERE id = 1;
    DELETE FROM finance.payment_reference WHERE reference = v_ref;
    DELETE FROM people.transfer_application WHERE student_id = stu;
    DELETE FROM people.student WHERE id = stu;
END $$;

-- ── 117. staff leave: a request is approved by a second officer and draws down the annual balance (V071) ──
DO $$
DECLARE p uuid := gen_random_uuid(); a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
        prog text; v_req uuid; v_state text; v_bal_before int; v_bal_after int;
BEGIN
    SELECT code INTO prog FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1;
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'check: leave', true);
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (p, 'CHK-LV', 'CHECKLEAVE', 'Invented');
    INSERT INTO hrm.employment (person_id, staff_no, grade, step, category, appointment_date, status)
    VALUES (p, 'CHK-LV-001', 'CONTISS 9', 1, 'NON_ACADEMIC', current_date, 'ACTIVE');
    v_bal_before := hrm.leave_balance(p, extract(year FROM current_date)::int);
    -- the staff member requests annual leave
    PERFORM set_config('moaum.actor_id', p::text, true);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    v_req := hrm.request_leave(p, 'ANNUAL', date_trunc('year', current_date)::date + 40, date_trunc('year', current_date)::date + 44, NULL, 'check');
    -- a second officer approves
    PERFORM set_config('moaum.actor_id', a2::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM hrm.decide_leave(v_req, true, NULL);
    SELECT state INTO v_state FROM hrm.leave_request WHERE id = v_req;
    v_bal_after := hrm.leave_balance(p, extract(year FROM current_date)::int);
    PERFORM pg_temp.assert('Staff leave is approved and draws down the annual balance',
        v_state = 'APPROVED' AND v_bal_before = 30 AND v_bal_after = 25,
        format('state=%s before=%s after=%s', v_state, v_bal_before, v_bal_after));
    DELETE FROM hrm.leave_request WHERE person_id = p;
    DELETE FROM hrm.employment WHERE person_id = p;
    DELETE FROM iam.person WHERE id = p;
END $$;

-- ── 118. a staff movement is real only when the instrument is issued, which changes the record (V072) ──
DO $$
DECLARE p uuid := gen_random_uuid(); a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid();
        v_mv uuid; v_state text; v_grade_before text; v_grade_after text; v_ref text;
BEGIN
    PERFORM set_config('moaum.actor_id', a1::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'check: movement', true);
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (p, 'CHK-MV', 'CHECKMOVE', 'Invented');
    INSERT INTO hrm.employment (person_id, staff_no, grade, step, category, appointment_date, status)
    VALUES (p, 'CHK-MV-001', 'CONTISS 9', 1, 'NON_ACADEMIC', current_date, 'ACTIVE');
    SELECT grade INTO v_grade_before FROM hrm.employment WHERE person_id = p;
    v_mv := hrm.raise_movement(p, 'PROMOTION', current_date, NULL, 'Due for promotion', 'CONTISS 13', 1);
    -- the record is unchanged while only requested
    v_grade_after := (SELECT grade FROM hrm.employment WHERE person_id = p);
    -- a second officer approves; the requester cannot
    PERFORM set_config('moaum.actor_id', a2::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    PERFORM hrm.approve_movement(v_mv);
    -- still unchanged: approved is not real
    IF (SELECT grade FROM hrm.employment WHERE person_id = p) <> 'CONTISS 9' THEN RAISE EXCEPTION 'record changed before the instrument'; END IF;
    v_ref := hrm.issue_movement_instrument(v_mv);
    SELECT state INTO v_state FROM hrm.movement WHERE id = v_mv;
    v_grade_after := (SELECT grade FROM hrm.employment WHERE person_id = p);
    PERFORM pg_temp.assert('A staff movement changes the record only when the instrument is issued',
        v_grade_before = 'CONTISS 9' AND v_state = 'IMPLEMENTED' AND v_grade_after = 'CONTISS 13' AND v_ref IS NOT NULL,
        format('before=%s state=%s after=%s ref=%s', v_grade_before, v_state, v_grade_after, v_ref));
    DELETE FROM hrm.movement WHERE person_id = p;
    DELETE FROM hrm.employment WHERE person_id = p;
    DELETE FROM iam.person WHERE id = p;
END $$;

-- ── 119. the JAMB-list reset runs end to end and reports its counts (V078) ──
DO $$
DECLARE r record;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'check: reset intake', true);
    SELECT * INTO r FROM admissions.reset_intake('9990/9991');
    PERFORM pg_temp.assert('Resetting a session''s JAMB list runs across every related table and reports its counts',
        r.candidates = 0 AND r.applications = 0 AND r.caps_rows = 0 AND r.olevel = 0 AND r.students_detached = 0,
        format('candidates=%s applications=%s caps=%s olevel=%s detached=%s', r.candidates, r.applications, r.caps_rows, r.olevel, r.students_detached));
END $$;

-- ── 120. funding has many sources; a credit carries its source; a balance withdraws to a bank only once fees clear, capped, under two people (V079) ──
DO $$
DECLARE s3 uuid := gen_random_uuid(); a_appr uuid := gen_random_uuid(); a_pay uuid := gen_random_uuid();
        v_entry uuid; w record; elig record; ok_early boolean := false; ok_over boolean := false; ok_samepay boolean := false; v_bal numeric;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (s3, 'MOAUM/ADM/99/990120', 'MOAUM/CHK/99/0120', 'CHECKFUND', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    -- the Fund's 150,000 (a loan) credited by the Bursary, tagged with its source — V327: a leftover grant is never refunded to the student, a leftover loan is
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    v_entry := finance.credit_wallet(s3, '9999/0000', 150000, 'CHECK NELFUND remittance', 'NELFUND');
    -- not yet clear: the 100,000 charge is outstanding, so a withdrawal is refused
    BEGIN PERFORM finance.request_withdrawal(s3, '9999/0000', NULL, 'Bank', '0123456789', 'CHECKFUND Invented'); EXCEPTION WHEN OTHERS THEN ok_early := true; END;
    -- the student applies the wallet to clear the fee; 50,000 is left over
    PERFORM set_config('moaum.actor_office', 'student', true);
    PERFORM finance.apply_wallet(s3, '9999/0000', 100000);
    v_bal := finance.wallet_balance(s3);
    SELECT * INTO elig FROM finance.withdrawal_eligibility(s3, '9999/0000');
    -- more than the balance is refused
    BEGIN PERFORM finance.request_withdrawal(s3, '9999/0000', 90000, 'Bank', '0123456789', 'CHECKFUND Invented'); EXCEPTION WHEN OTHERS THEN ok_over := true; END;
    -- the excess is requested, approved and paid by a second officer
    SELECT * INTO w FROM finance.request_withdrawal(s3, '9999/0000', 50000, 'Zenith', '0123456789', 'CHECKFUND Invented');
    PERFORM set_config('moaum.actor_id', a_appr::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    PERFORM finance.approve_withdrawal(w.id);
    -- the officer who approved cannot also pay
    BEGIN PERFORM finance.pay_withdrawal(w.id, 'TRX-CHK'); EXCEPTION WHEN OTHERS THEN ok_samepay := true; END;
    PERFORM set_config('moaum.actor_id', a_pay::text, true);
    PERFORM finance.pay_withdrawal(w.id, 'TRX-CHK');
    SELECT * INTO w FROM finance.wallet_withdrawal WHERE id = w.id;
    PERFORM pg_temp.assert('Funding carries its source (NELFUND is a loan), a credit is tagged, and a wallet balance withdraws to a bank only after fees clear, capped, and under two people',
        (SELECT nature FROM finance.funding_source WHERE code = 'NELFUND') = 'LOAN'
        AND (SELECT source_code FROM finance.wallet_entry WHERE id = v_entry) = 'NELFUND'
        AND ok_early AND elig.eligible AND v_bal = 50000 AND ok_over AND ok_samepay
        AND w.state = 'PAID' AND finance.wallet_balance(s3) = 0,
        format('early_refused=%s eligible=%s bal=%s over_refused=%s samepay_refused=%s state=%s final=%s',
               ok_early, elig.eligible, v_bal, ok_over, ok_samepay, w.state, finance.wallet_balance(s3)));
END $$;

-- ── 121. Quickteller PayDirect billers route by College, and the collections import confirms a PRN (V080) ──
DO $$
DECLARE s_main uuid := gen_random_uuid(); s_chs uuid := gen_random_uuid(); v_ref text; r record; b_main text; b_chs text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
        (s_main, 'MOAUM/ADM/99/990130', 'MOAUM/CHK/99/0130', 'CHECKPD', 'Main', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now()),
        (s_chs,  'MOAUM/ADM/99/990131', 'MOAUM/CHK/99/0131', 'CHECKPD', 'Health', 'C00061', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    SELECT biller_code INTO b_main FROM finance.paydirect_biller_for(s_main);
    SELECT biller_code INTO b_chs FROM finance.paydirect_biller_for(s_chs);
    -- a reference (the PRN) for the main student, then the collections import matches and confirms it; an unknown PRN does not
    v_ref := finance.new_reference(s_main, '9999/0000', 50000, NULL);
    SELECT * INTO r FROM finance.import_paydirect(
        ('[{"prn":"' || v_ref || '","amount":"50000","rrn":"RRNCHK001"},{"prn":"NOPRN-CHK-9999","amount":"1000","rrn":"RRNCHK002"}]')::jsonb);
    PERFORM pg_temp.assert('PayDirect routes a Health Sciences programme to the CHS biller and every other programme to the main biller, and the collections import matches a PRN and confirms it through the same confirmation as every payment',
        b_main = '04255101' AND b_chs = '04263001' AND r.matched = 1 AND r.unmatched = 1
        AND (SELECT confirmed_at IS NOT NULL FROM finance.payment_reference WHERE reference = v_ref)
        AND (SELECT channel FROM finance.payment_reference WHERE reference = v_ref) = 'Quickteller PayDirect',
        format('main=%s chs=%s matched=%s unmatched=%s', b_main, b_chs, r.matched, r.unmatched));
END $$;

-- ── 122. the JAMB admission-status list, uploaded back: matched by reg number, the accepted offered and released (V081) ──
DO $$
DECLARE b uuid := gen_random_uuid(); acct uuid; app uuid; r record; a admissions.application;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
    VALUES (b, '9995/9996', 'CAPS_DOWNLOAD', 'UTME', '\xC2'::bytea, 1, current_date, gen_random_uuid(), 'academic');
    INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
    VALUES (gen_random_uuid(), b, '9995/9996', '20269995JA', '{}'::jsonb, 'CHECKJAMB', 'Invented', 'C00061', 250, 'UTME', 'M', 'Benue', 'Makurdi');
    PERFORM set_config('moaum.actor_office', 'applicant', true);
    acct := admissions.register_applicant('9995/9996', '20269995JA', 'check.jamb@example.com', '08034117726',
        '$2a$12$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ab');
    SELECT id INTO app FROM admissions.application WHERE account_id = acct;
    PERFORM set_config('moaum.actor_office', 'academic', true);
    SELECT * INTO r FROM admissions.load_jamb_admissions('9995/9996',
        '[{"RG_NUM":"20269995JA","RG_CANDNAME":"CHECKJAMB Invented","CO_NAME":"MBBS","AdmissionStatus":"Accepted","AdmissionCategoryName":"Merit","Total":"55"},{"RG_NUM":"20269995ZZ","AdmissionStatus":"Accepted"}]'::jsonb);
    SELECT * INTO a FROM admissions.application WHERE id = app;
    PERFORM pg_temp.assert('The JAMB admission list matches by registration number, offers and releases the accepted, and holds a number not on the register',
        r.loaded = 2 AND r.matched = 1 AND r.accepted = 1 AND r.offered = 1 AND r.unmatched = 1
        AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL
        AND (SELECT offer_state FROM admissions.candidate c JOIN admissions.applicant_account ac ON ac.candidate_id = c.id WHERE ac.id = acct) = 'ADMITTED'
        AND (SELECT matched AND offered FROM admissions.jamb_admission WHERE session = '9995/9996' AND jamb_reg_no = '20269995JA')
        AND NOT (SELECT matched FROM admissions.jamb_admission WHERE session = '9995/9996' AND jamb_reg_no = '20269995ZZ'),
        format('loaded=%s matched=%s accepted=%s offered=%s unmatched=%s decision=%s', r.loaded, r.matched, r.accepted, r.offered, r.unmatched, a.decision));
END $$;

-- ── 123. the legacy migration: students, then a registration and a published result the GPA reads (V082) ──
DO $$
DECLARE r record; g record; stu uuid;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'exams', true);
    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code)
    VALUES ('ARC 999', 'Migration Test Course', 3, 1, 100, 'ARC') ON CONFLICT (code) DO NOTHING;
    -- 1. the students, exported from the old portal
    SELECT * INTO r FROM people.import_students('[{"matric":"MOAUM/MIG/22/0001","name":"CHECKMIG, Invented","programme":"C00023","level":"200","sex":"M"}]'::jsonb);
    SELECT id INTO stu FROM people.student WHERE matric_no = 'MOAUM/MIG/22/0001';
    -- 3. a past result imported as final (creating the registration), plus a number that is not a student
    SELECT * INTO g FROM assessment.import_legacy_semester('9994/9995', 1,
        '[{"matric":"MOAUM/MIG/22/0001","course":"ARC 999","units":"3","ca":"30","exam":"45"},{"matric":"MOAUM/NOPE/22/0009","course":"ARC 999","total":"50"}]'::jsonb, true);
    PERFORM pg_temp.assert('The legacy migration creates the student, an approved registration, and a PUBLISHED result the transcript and GPA read (a row for a student not loaded yet is HELD)',
        r.created = 1 AND stu IS NOT NULL
        AND g.results = 1 AND g.held = 1 AND g.registrations = 1
        AND (SELECT total FROM assessment.student_results(stu) WHERE course_code = 'ARC 999') = 75
        AND (SELECT published FROM assessment.student_results(stu) WHERE course_code = 'ARC 999')
        AND (SELECT gpa FROM assessment.student_gpa(stu) WHERE session = '9994/9995' AND semester = 1) IS NOT NULL,
        format('created=%s results=%s held=%s regs=%s', r.created, g.results, g.held, g.registrations));
END $$;

-- ── 123b. a held result posts once its student is loaded, and reconcile clears the hold (V204) ──
DO $$
DECLARE h record; stu2 uuid;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM people.import_students('[{"matric":"MOAUM/NOPE/22/0009","name":"CHECKHOLD, Invented","programme":"C00023","level":"100","sex":"F"}]'::jsonb);
    SELECT * INTO h FROM assessment.reconcile_legacy_holding();
    SELECT id INTO stu2 FROM people.student WHERE matric_no = 'MOAUM/NOPE/22/0009';
    PERFORM pg_temp.assert('A past result held for a student not loaded yet posts on reconcile, and the hold is cleared',
        h.reconciled >= 1 AND stu2 IS NOT NULL
        AND (SELECT total FROM assessment.student_results(stu2) WHERE course_code = 'ARC 999') = 50
        AND NOT EXISTS (SELECT 1 FROM assessment.legacy_result_holding WHERE matric = 'MOAUM/NOPE/22/0009'),
        format('reconciled=%s', h.reconciled));
END $$;

-- ── 124. the approved fees import charges by faculty, level and indigeneship (V083) ──
DO $$
DECLARE s_ind uuid := gen_random_uuid(); s_non uuid := gen_random_uuid(); r record;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    INSERT INTO people.student (id, matric_no, surname, other_names, state_of_origin, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
        (s_ind, 'MOAUM/FEE/23/0001', 'CHECKFEE', 'Indigene', 'Benue', 'C00023', 'UTME', '2023/2024', 100, 100, 'ACTIVE', now()),
        (s_non, 'MOAUM/FEE/23/0002', 'CHECKFEE', 'Stranger', 'Kano', 'C00023', 'UTME', '2023/2024', 100, 100, 'ACTIVE', now());
    SELECT * INTO r FROM finance.import_fee_structure('9993/9994',
        '[{"faculty":"SC","level":"100","indigene":"INDIGENE","amount":"50000"},{"faculty":"SC","level":"100","indigene":"NON_INDIGENE","amount":"80000"}]'::jsonb);
    PERFORM pg_temp.assert('The approved fees import charges an indigene and a non-indigene of the same faculty and level their own cell',
        r.lines = 2 AND r.faculties = 1 AND r.no_faculty = 0
        AND (SELECT coalesce(sum(amount), 0) FROM finance.charges(s_ind, '9993/9994')) = 50000
        AND (SELECT coalesce(sum(amount), 0) FROM finance.charges(s_non, '9993/9994')) = 80000
        AND finance.session_fee_total(s_ind, '9993/9994') = 50000,
        format('lines=%s faculties=%s no_faculty=%s ind=%s non=%s', r.lines, r.faculties, r.no_faculty,
               (SELECT coalesce(sum(amount), 0) FROM finance.charges(s_ind, '9993/9994')),
               (SELECT coalesce(sum(amount), 0) FROM finance.charges(s_non, '9993/9994'))));
END $$;

-- ── 124b. the approved fees import keeps a spillover line, a programme's own line, its fee group and its kind (V313) ──
DO $$
DECLARE s_ind uuid; s_spill uuid := gen_random_uuid(); r record; v_other text; v_sp numeric; v_norm numeric; v_prog numeric;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    SELECT id INTO s_ind FROM people.student WHERE matric_no = 'MOAUM/FEE/23/0001';
    -- a spillover student of the same programme: beyond the programme's final level, not graduated
    INSERT INTO people.student (id, matric_no, surname, other_names, state_of_origin, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
        (s_spill, 'MOAUM/FEE/23/0003', 'CHECKFEE', 'Spillover', 'Benue', 'C00023', 'UTME', '2019/2020', 100, finance.final_level('C00023') + 100, 'ACTIVE', now());
    -- an undergraduate programme of another faculty, for a line of its own
    SELECT code INTO v_other FROM ref.programme WHERE NOT archived AND category = 'UNDER GRADUATE' AND faculty_code <> 'SC' ORDER BY code LIMIT 1;
    SELECT * INTO r FROM finance.import_fee_structure('9993/9994', jsonb_build_array(
        jsonb_build_object('faculty', 'SC', 'level', '100', 'indigene', 'Indigene', 'amount', '50000'),
        jsonb_build_object('faculty', 'SC', 'indigene', 'Indigene', 'amount', '70000', 'spillover', 'Yes'),
        jsonb_build_object('programme', v_other, 'level', '100', 'indigene', 'Indigene', 'amount', '112000', 'feeGroup', 'UG', 'item', 'School Fees'),
        jsonb_build_object('faculty', 'SC', 'amount', '5000', 'kind', 'Late payment')));
    SELECT coalesce(sum(amount), 0) INTO v_norm FROM finance.charges_of_as(s_ind, '9993/9994', ARRAY['FEE'], NULL);
    SELECT coalesce(sum(amount), 0) INTO v_sp FROM finance.charges_of_as(s_spill, '9993/9994', ARRAY['FEE'], NULL);
    SELECT coalesce(sum(amount), 0) INTO v_prog FROM finance.charges_of_as(s_ind, '9993/9994', ARRAY['FEE'], v_other);
    PERFORM pg_temp.assert('The approved fees import keeps a spillover line for spillover students alone, a programme''s line for that programme alone, its fee group and its kind',
        coalesce(r.lines = 4 AND r.spillover = 1 AND r.programmes = 1 AND r.no_programme = 0 AND r.no_group = 0
        AND v_norm = 50000 AND v_sp = 70000 AND v_prog = 112000
        AND EXISTS (SELECT 1 FROM finance.fee_schedule WHERE session = '9993/9994' AND ended_at IS NULL AND spillover AND level IS NULL AND item = 'School fees (spillover)')
        AND EXISTS (SELECT 1 FROM finance.fee_schedule WHERE session = '9993/9994' AND ended_at IS NULL AND programme_code = v_other AND fee_group = 'UG')
        AND EXISTS (SELECT 1 FROM finance.fee_schedule WHERE session = '9993/9994' AND ended_at IS NULL AND kind = 'LATE_PAYMENT' AND item = 'Late payment fee'), false),
        format('lines=%s spill=%s progs=%s no_prog=%s no_group=%s normal=%s spillover=%s programme=%s other=%s', r.lines, r.spillover, r.programmes, r.no_programme, r.no_group, v_norm, v_sp, v_prog, v_other));
END $$;

-- ── 125. a department's course structure uploads, accepting CCMAS codes, and offers to the programme (V084) ──
DO $$
DECLARE r record; v_prog text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    SELECT p.code INTO v_prog FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code WHERE NOT p.archived ORDER BY p.code LIMIT 1;
    SELECT * INTO r FROM catalogue.import_courses(v_prog,
        '[{"code":"BSU-ZZZ-901","title":"Group Dynamics","units":"3","status":"C","level":"100","semester":"1","lh":"45"},{"code":"ZZZ 901","title":"Intro Course","units":"2","status":"C","level":"100","semester":"1"},{"code":"Course Code","title":"header"},{"code":"","title":"Total"}]'::jsonb);
    PERFORM pg_temp.assert('A course structure uploads: the relaxed CCMAS code is accepted, courses are created and offered to the programme, header and total rows skipped',
        r.courses = 2 AND r.offers = 2 AND r.bad_code = 0
        AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = 'BSU-ZZZ-901' AND units = 3 AND lecture_hours = 45)
        AND EXISTS (SELECT 1 FROM catalogue.course_offer WHERE course_code = 'BSU-ZZZ-901' AND programme_code = v_prog AND level = 100),
        format('courses=%s offers=%s bad=%s', r.courses, r.offers, r.bad_code));
END $$;

-- ── 126. a full old-portal biography imports whole: the matric as issued, the contact, the biography and a sign-in account (V098) ──
DO $$
DECLARE res record; v_student uuid; v_hobby text; v_acct boolean; v_phone text;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    PERFORM set_config('moaum.reason', 'CHECK biography import', true);
    SELECT * INTO res FROM people.import_biography($json$[
      {"matno":"BSU/BM/RAD/21/2204","surname":"CHECKBIO","otherNames":"Legacy One","programme":"C00061",
       "sex":"Male","dob":"2003-08-05","yoe":"2021/2022","level":"400","phone":"7032357502",
       "email":"CHECKBIO@example.com","address":"KM 8 Lafia Road","nationality":"Nigeria","state":"Benue",
       "lga":"Makurdi","guardianName":"MR CHECK","nokName":"CHECK KIN","sponsorName":"MR CHECK",
       "extracurricular":"READING","appno":"10000259GC"},
      {"matno":"not a matric","surname":"BAD","programme":"C00061"}
    ]$json$::jsonb);
    SELECT id INTO v_student FROM people.student WHERE matric_no = 'BSU/BM/RAD/21/2204';
    SELECT value INTO v_hobby FROM people.biodata WHERE student_id = v_student AND field = 'extracurricular';
    SELECT exists(SELECT 1 FROM iam.student_account WHERE student_id = v_student AND must_change) INTO v_acct;
    SELECT phone INTO v_phone FROM people.student_contact WHERE student_id = v_student;
    PERFORM pg_temp.assert('A legacy old-portal biography imports whole: the matric kept as issued, the contact, the biography and a sign-in account',
        res.rows = 2 AND res.created = 1 AND res.bad_number = 1 AND res.contacts = 1 AND res.accounts = 1
        AND v_hobby = 'READING' AND v_acct AND v_phone = '07032357502',
        format('rows=%s created=%s bad=%s contacts=%s accounts=%s biography=%s hobby=%s phone=%s',
               res.rows, res.created, res.bad_number, res.contacts, res.accounts, res.biography, v_hobby, v_phone));
END $$;

-- ── 127. a lecturer keeps their own profile: scalars, list sections and a photograph, upserted whole and read back (V107) ──
DO $$
DECLARE
    v_person uuid := '00000000-0000-0000-0000-0000000000c7';
    r        hrm.staff_profile;
    v_pubs   int; v_ct text; v_dept text;
BEGIN
    PERFORM set_config('moaum.actor_id', v_person::text, true);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    PERFORM set_config('moaum.reason', 'CHECK staff profile', true);

    INSERT INTO iam.person (id, staff_number, surname, given_names)
    VALUES (v_person, 'MOAUM/CHK/PROF', 'CHECKPROF', 'Ada Lovelace')
    ON CONFLICT (id) DO NOTHING;

    -- first save
    r := hrm.save_my_staff_profile($json$
        {"email":"ada@example.com","phone":"08030000000","department":"Mathematics",
         "faculty":"Science","responsibility":"Examinations Officer",
         "scholarUrl":"https://scholar.google.com/citations?user=ADA",
         "researchInterests":"Numerical analysis, computability",
         "mastersGraduated":"7","phdGraduated":"2",
         "publications":["A note on engines, J. Analytical Eng., 1843"],
         "grants":["TETFund IBR 2024 — 5,000,000"],
         "collaborations":["University of Turin (international)"],
         "conferences":["ICM 2022, attended"],
         "assignments":["NUC accreditation panel (national)"],
         "innovations":["A teaching abacus"],"patents":["NG/PAT/2023/1"],
         "achievements":["Best lecturer 2021"],"contributions":["STEM outreach, rural schools"]}
    $json$::jsonb);

    -- upsert again with fewer fields: the row is replaced whole, not merged
    r := hrm.save_my_staff_profile('{"department":"Applied Mathematics","phdGraduated":"3"}'::jsonb);
    PERFORM hrm.set_my_staff_photo('image/png', 3, E'\\x89504e'::bytea);
    PERFORM hrm.set_my_staff_photo('image/jpeg', 2, E'\\xffd8'::bytea);  -- replaces, one row

    SELECT jsonb_array_length(publications), department INTO v_pubs, v_dept
      FROM hrm.staff_profile WHERE person_id = v_person;
    SELECT content_type INTO v_ct FROM hrm.staff_photo WHERE person_id = v_person;

    PERFORM pg_temp.assert(
      'A lecturer keeps their own profile: it upserts whole, the list sections are read back, and one photograph is held',
      r.person_id = v_person AND r.phd_graduated = 3 AND r.department = 'Applied Mathematics'
      AND v_dept = 'Applied Mathematics' AND v_pubs = 0
      AND (SELECT count(*) FROM hrm.staff_profile WHERE person_id = v_person) = 1
      AND (SELECT count(*) FROM hrm.staff_photo WHERE person_id = v_person) = 1
      AND v_ct = 'image/jpeg',
      format('phd=%s dept=%s pubs=%s photo=%s', r.phd_graduated, v_dept, v_pubs, v_ct));
END $$;

-- ── 129. the operational-data reset runs to completion, clearing suggestion_sent before the applications it hangs on (V089/V108) ──
-- Runs the real reset inside a savepoint and rolls it back, so it proves the
-- function executes end to end without disturbing the suite's data. With a
-- suggestion_sent row present it also guards the delete order: the pre-V108
-- reset would fail here with a foreign-key violation.
DO $$
DECLARE app uuid; res jsonb; ran boolean := false; had_app boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'super', true);
    PERFORM set_config('moaum.reason', 'CHECK reset validation', true);

    SELECT id INTO app FROM admissions.application LIMIT 1;
    had_app := app IS NOT NULL;

    BEGIN
        IF had_app THEN
            INSERT INTO admissions.suggestion_sent (application_id, programmes, sent_by)
            VALUES (app, 'CHK suggestion', nullif(current_setting('moaum.actor_id', true), '')::uuid)
            ON CONFLICT (application_id) DO NOTHING;
        END IF;
        res := platform.reset_operational_data('RESET', 'CHECK reset validation');
        ran := (res->>'reset')::boolean;
        RAISE EXCEPTION 'chk_reset_rollback';   -- undo every delete; the point is only that it ran
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'chk_reset_rollback' THEN RAISE; END IF;   -- a real failure (e.g. FK order) propagates
    END;

    PERFORM pg_temp.assert(
        'The operational-data reset runs to completion, clearing suggestion_sent before the applications it references',
        ran,
        format('ran=%s had_application=%s', ran, had_app));
END $$;

-- ── 130. the session roll-over promotes active continuing students one level and enrols them, leaving final-year and withdrawn students (V110) ──
-- Runs the real roll-over inside a savepoint and rolls it back, so it neither
-- promotes the suite's other fixtures nor leaves a session behind.
DO $$
DECLARE
    v_active uuid := gen_random_uuid(); v_final uuid := gen_random_uuid(); v_wd uuid := gen_random_uuid();
    res jsonb; ran boolean := false; lvl_active int; lvl_final int; lvl_wd int; enrolled boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    PERFORM set_config('moaum.reason', 'CHECK session rollover', true);

    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode,
                                entry_session, entry_level, current_level, status, matriculated_at) VALUES
      (v_active, 'MOAUM/ADM/99/970001', 'MOAUM/RLA/99/0001', 'ROLLACTIVE', 'Two Hundred', 'C00061', 'UTME', '9990/9991', 100, 200, 'ACTIVE', now()),
      (v_final,  'MOAUM/ADM/99/970002', 'MOAUM/RLF/99/0002', 'ROLLFINAL',  'Final Year',  'C00019', 'UTME', '9990/9991', 100, 400, 'ACTIVE', now()),
      (v_wd,     'MOAUM/ADM/99/970003', 'MOAUM/RLW/99/0003', 'ROLLGONE',   'Withdrawn',   'C00061', 'UTME', '9990/9991', 100, 200, 'WITHDRAWN', now());

    BEGIN
        res := people.roll_over_session('9989/9990', 'ROLLOVER', 'CHECK session rollover');
        ran := (res->>'session') = '9989/9990';
        SELECT current_level INTO lvl_active FROM people.student WHERE id = v_active;
        SELECT current_level INTO lvl_final  FROM people.student WHERE id = v_final;
        SELECT current_level INTO lvl_wd     FROM people.student WHERE id = v_wd;
        SELECT EXISTS (SELECT 1 FROM people.enrolment WHERE student_id = v_active AND session = '9989/9990' AND level = 300) INTO enrolled;
        RAISE EXCEPTION 'chk_rollover_rollback';   -- undo the promotion and the created session
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'chk_rollover_rollback' THEN RAISE; END IF;
    END;

    PERFORM pg_temp.assert(
        'The session roll-over promotes an active continuing student one level and enrols them, and leaves a final-year and a withdrawn student where they are',
        ran AND lvl_active = 300 AND enrolled AND lvl_final = 400 AND lvl_wd = 200,
        format('ran=%s active=%s enrolled=%s final=%s withdrawn=%s', ran, lvl_active, enrolled, lvl_final, lvl_wd));
END $$;

-- ── 133. a re-sit replaces a failed Main capped at the pass mark; a Special is uncapped (V197–V199) ──
DO $$
DECLARE
    a uuid := gen_random_uuid();
    stu1 uuid := gen_random_uuid();   -- fails the Main, passes the re-sit
    stu2 uuid := gen_random_uuid();   -- absent in the Main, sits the Special
    prog text; dept text; sess text := '2093/2094';
    offR uuid := gen_random_uuid(); offS uuid := gen_random_uuid();
    regR uuid := gen_random_uuid(); regS uuid := gen_random_uuid();
    esMain uuid := gen_random_uuid(); esResit uuid := gen_random_uuid(); esSpecial uuid := gen_random_uuid();
    shRmain uuid := gen_random_uuid(); shSmain uuid := gen_random_uuid();
    shRresit uuid := gen_random_uuid(); shSspecial uuid := gen_random_uuid();
    v_pts numeric; v_out text; v_tot int; v_on_roll boolean; v_pts2 numeric; v_tot2 int;
BEGIN
    PERFORM set_config('moaum.actor_id', a::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'check: resit/special', true);
    SELECT code INTO prog FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1;
    SELECT code INTO dept FROM ref.department ORDER BY code LIMIT 1;
    -- the session an offering hangs on (a far-future range so it cannot overlap another)
    INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
    VALUES (gen_random_uuid(), sess, DATE '2093-10-01', DATE '2094-08-31') ON CONFLICT (name) DO NOTHING;

    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES
        ('ZZR 401', 'Re-sit Test', 3, 1, 400, dept, 'LIVE'),
        ('ZZS 401', 'Special Test', 3, 1, 400, dept, 'LIVE');
    INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES
        (offR, 'ZZR 401', sess, 1), (offS, 'ZZS 401', sess, 1);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
        (stu1, 'MOAUM/ADM/20/990001', 'MOAUM/XX/20/9001', 'RESITONE', 'Invented', prog, 'UTME', '2020/2021', 100, 400, 'ACTIVE', now()),
        (stu2, 'MOAUM/ADM/20/990002', 'MOAUM/XX/20/9002', 'SPECIALTWO', 'Invented', prog, 'UTME', '2020/2021', 100, 400, 'ACTIVE', now());
    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES
        (regR, stu1, sess, 1, 400, 'APPROVED', now()), (regS, stu2, sess, 1, 400, 'APPROVED', now());
    INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES
        (regR, offR, 3, 'APPROVED'), (regS, offS, 3, 'APPROVED');
    INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due, state, opened_at) VALUES
        (esMain, sess, 1, 'MAIN', DATE '2094-01-08', DATE '2094-01-19', DATE '2094-02-16', 'OPEN', now()),
        (esResit, sess, 1, 'RESIT', DATE '2094-03-08', DATE '2094-03-19', DATE '2094-04-16', 'OPEN', now()),
        (esSpecial, sess, 1, 'SPECIAL', DATE '2094-03-08', DATE '2094-03-19', DATE '2094-04-16', 'OPEN', now());

    -- Main sittings published: stu1 fails ZZR 401 (25), stu2 absent in ZZS 401
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, stage, senate_minute, published_at, submitted_at) VALUES
        (shRmain, offR, esMain, 'PUBLISHED', 'SEN/2094/01', now(), now()),
        (shSmain, offS, esMain, 'PUBLISHED', 'SEN/2094/01', now(), now());
    INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES
        (shRmain, stu1, 10, 15, 'GRADED'), (shSmain, stu2, NULL, NULL, 'ABSENT');

    -- before the re-sit, the failed course is a fail on the record
    SELECT points, outcome INTO v_pts, v_out FROM assessment.student_results(stu1) WHERE course_code = 'ZZR 401';
    PERFORM pg_temp.assert('A failed Main sitting shows as a fail (0 points) before any re-sit',
        v_out = 'GRADED' AND coalesce(v_pts, -1) = 0, format('points=%s outcome=%s', v_pts, v_out));

    -- the re-sit sheet: its roster is the failed candidate, and a pass replaces the fail capped at the pass mark
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, stage, senate_minute, published_at, submitted_at)
        VALUES (shRresit, offR, esResit, 'ENTRY', NULL, NULL, NULL);
    SELECT EXISTS (SELECT 1 FROM assessment.sheet_candidates(shRresit) WHERE student_id = stu1) INTO v_on_roll;
    INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (shRresit, stu1, 30, 35, 'GRADED');  -- 65, a clear pass
    UPDATE assessment.score_sheet SET stage = 'PUBLISHED', senate_minute = 'SEN/2094/07', published_at = now(), submitted_at = now() WHERE id = shRresit;
    SELECT points, total INTO v_pts, v_tot FROM assessment.student_results(stu1) WHERE course_code = 'ZZR 401';
    PERFORM pg_temp.assert('A passed re-sit is on the failed candidate''s roster and replaces the Main, capped at the pass mark (E/40/1.0)',
        v_on_roll AND coalesce(v_pts, -1) = 1.0 AND v_tot = 40, format('on_roll=%s points=%s total=%s', v_on_roll, v_pts, v_tot));

    -- the Special sitting: an absent candidate sits it, and the mark counts uncapped
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, stage, senate_minute, published_at, submitted_at)
        VALUES (shSspecial, offS, esSpecial, 'PUBLISHED', 'SEN/2094/08', now(), now());
    INSERT INTO assessment.score (sheet_id, student_id, ca, exam, outcome) VALUES (shSspecial, stu2, 30, 35, 'GRADED');  -- 65
    SELECT points, total INTO v_pts2, v_tot2 FROM assessment.student_results(stu2) WHERE course_code = 'ZZS 401';
    PERFORM pg_temp.assert('A Special sitting replaces an absence uncapped (65 -> B/4.0)',
        coalesce(v_pts2, -1) = 4.0 AND v_tot2 = 65, format('points=%s total=%s', v_pts2, v_tot2));

    -- cleanup
    DELETE FROM assessment.score WHERE sheet_id IN (shRmain, shSmain, shRresit, shSspecial);
    DELETE FROM assessment.score_sheet WHERE id IN (shRmain, shSmain, shRresit, shSspecial);
    DELETE FROM assessment.exam_session WHERE id IN (esMain, esResit, esSpecial);
    DELETE FROM registration.entry WHERE registration_id IN (regR, regS);
    DELETE FROM registration.course_registration WHERE id IN (regR, regS);
    DELETE FROM people.student WHERE id IN (stu1, stu2);
    DELETE FROM catalogue.offering WHERE id IN (offR, offS);
    DELETE FROM catalogue.course WHERE code IN ('ZZR 401', 'ZZS 401');
    DELETE FROM policy.academic_session WHERE name = sess;
END $$;

-- ── 17c. a script from a candidate not on the roll is held, released by an approved registration, lapsed past the date (V240) ──
DO $$
DECLARE sh uuid; o uuid; st uuid := gen_random_uuid(); st2 uuid := gen_random_uuid(); reg uuid := gen_random_uuid();
        hid uuid; hid2 uuid; refused boolean := false; l record; had_sem boolean; old_late date; lapsed int; rel_state text; lap_state text;
        held_before boolean;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    SELECT s.id, o2.id INTO sh, o FROM assessment.score_sheet s JOIN catalogue.offering o2 ON o2.id = s.offering_id WHERE o2.course_code = 'CHK 901';
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st,  'MOAUM/ADM/99/990902', 'MOAUM/CHK/99/0902', 'CHECKHELD',  'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now()),
           (st2, 'MOAUM/ADM/99/990903', 'MOAUM/CHK/99/0903', 'CHECKLAPSE', 'Invented', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
    -- a mark over the course's split is refused even while held; the number is read whatever its case
    BEGIN PERFORM assessment.hold_script(sh, 'MOAUM/CHK/99/0902', 35, 10, NULL, NULL); EXCEPTION WHEN check_violation THEN refused := true; END;
    hid := assessment.hold_script(sh, 'moaum/chk/99/0902', 25, 40, NULL, 'script 7');
    held_before := NOT EXISTS (SELECT 1 FROM assessment.latest_scores(sh) x WHERE x.student_id = st);
    -- the registration approved: the register releases the script into the sheet
    PERFORM set_config('moaum.actor_office', 'hod', true);
    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (reg, st, '9999/0000', 1, 100, 'APPROVED', now());
    INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (reg, o, 3, 'APPROVED');
    SELECT state INTO rel_state FROM assessment.held_script WHERE id = hid;
    SELECT * INTO l FROM assessment.latest_scores(sh) x WHERE x.student_id = st;
    -- past the semester's late-registration date, a held script lapses
    SELECT EXISTS (SELECT 1 FROM policy.semester WHERE session = '9999/0000' AND number = 1) INTO had_sem;
    IF NOT had_sem THEN INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), '9999/0000', 1, 'CLOSED'); END IF;
    SELECT late_registration_closes INTO old_late FROM policy.semester WHERE session = '9999/0000' AND number = 1;
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    hid2 := assessment.hold_script(sh, 'MOAUM/CHK/99/0903', 20, 30, NULL, NULL);
    UPDATE policy.semester SET late_registration_closes = current_date - 1 WHERE session = '9999/0000' AND number = 1;
    lapsed := assessment.lapse_held_scripts();
    SELECT state INTO lap_state FROM assessment.held_script WHERE id = hid2;
    UPDATE policy.semester SET late_registration_closes = old_late WHERE session = '9999/0000' AND number = 1;
    IF NOT had_sem THEN DELETE FROM policy.semester WHERE session = '9999/0000' AND number = 1; END IF;
    PERFORM pg_temp.assert('A script from a candidate not on the roll is held (a mark over the split refused), stays off the sheet until the registration is approved, is then released as the mark, and lapses past the late-registration date',
        refused AND held_before AND rel_state = 'RELEASED' AND l.total = 65 AND l.version = 1 AND lapsed >= 1 AND lap_state = 'LAPSED',
        format('refused=%s held_before=%s released=%s total=%s version=%s lapsed=%s lapse_state=%s', refused, held_before, rel_state, l.total, l.version, lapsed, lap_state));
END $$;

-- ── 17d. the College of Health Sciences' tables hold the prospectus, and its rules answer as it says (V245) ──
DO $$
DECLARE n_blocks int; n_postings int; n_exams int; n_subjects int; n_slots int; n_procs int; n_rules int; med_weeks int;
        pe3_paed uuid; pe1_anat uuid; ok_pass boolean; ok_clin boolean; ok_fail boolean; ok_dist boolean; nxt1 text; nxt2 text; nxt3 text;
BEGIN
    SELECT count(*) INTO n_blocks FROM college.block;
    SELECT count(*) INTO n_postings FROM college.posting;
    SELECT count(*) INTO n_exams FROM college.professional_exam;
    SELECT count(*) INTO n_subjects FROM college.exam_subject;
    SELECT count(*) INTO n_slots FROM college.timetable_slot t JOIN college.posting p ON p.id = t.posting_id WHERE p.code = 'PSY';
    SELECT count(*) INTO n_procs FROM college.procedure_requirement;
    SELECT count(*) INTO n_rules FROM college.attendance_rule;
    SELECT sum(duration_weeks)::int INTO med_weeks FROM college.posting p JOIN college.block b ON b.id = p.block_id WHERE b.code = 'MED';
    SELECT s.id INTO pe3_paed FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id WHERE e.code = 'PE3' AND s.name = 'Paediatrics';
    SELECT s.id INTO pe1_anat FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id WHERE e.code = 'PE1' AND s.name = 'Anatomy';
    ok_pass := college.passes(pe1_anat, 20, 30);                 -- 50: a pass
    ok_fail := NOT college.passes(pe1_anat, 20, 29);             -- 49: not
    ok_clin := NOT college.passes(pe3_paed, 25, 40, 45) AND college.passes(pe3_paed, 25, 40, 50);   -- the clinical component must be 50 too
    ok_dist := college.distinction('C00061', 70) AND NOT college.distinction('C00061', 69);
    nxt1 := college.next_attempt('PE1', 3, 3);                   -- all three failed: repeat, no resit
    nxt2 := college.next_attempt('PE1', 1, 3);                   -- one failed: resit
    nxt3 := college.next_attempt('CPE', 1, 3);                   -- the CPE has no resit
    PERFORM pg_temp.assert('The College tables hold the prospectus — eight blocks, the postings, Internal Medicine 34 weeks, the CPE and four Professionals with 13 subjects, Psychiatry''s 200 slots, nine Paediatrics procedures, three attendance rules — and its rules answer as it says',
        n_blocks = 8 AND n_postings = 24 AND med_weeks = 34 AND n_exams = 5 AND n_subjects = 13 AND n_slots = 200 AND n_procs = 9 AND n_rules = 3
        AND ok_pass AND ok_fail AND ok_clin AND ok_dist AND nxt1 = 'REPEAT' AND nxt2 = 'RESIT' AND nxt3 = 'REPEAT',
        format('blocks=%s postings=%s med_weeks=%s exams=%s subjects=%s slots=%s procs=%s rules=%s pass=%s fail=%s clin=%s dist=%s next=%s/%s/%s',
               n_blocks, n_postings, med_weeks, n_exams, n_subjects, n_slots, n_procs, n_rules, ok_pass, ok_fail, ok_clin, ok_dist, nxt1, nxt2, nxt3));
END $$;

-- ── 17e. Senate's rule on probation and withdrawal answers as worded (V246) ──
DO $$
DECLARE a text; b text; c text; d text; e text; f text; g text; h text; i text;
BEGIN
    a := assessment.standing_of(100, 1, 0.80, NULL, false);    -- 100 level first semester: nothing pronounced
    b := assessment.standing_of(100, 2, 0.80, 0.90, false);    -- 100 level second semester under 1.0: to go on probation
    c := assessment.standing_of(200, 1, 0.90, 0.80, false);    -- 200 level first semester still under: the probation list
    d := assessment.standing_of(200, 1, 0.90, NULL, true);     -- a Direct Entry student's first semester: no standing
    e := assessment.standing_of(200, 2, 0.95, 0.90, false);    -- 200 level second semester still under: advised to withdraw
    f := assessment.standing_of(200, 2, 0.95, 1.20, false);    -- fell under only now: probation, not withdrawal
    g := assessment.standing_of(200, 2, 0.95, 0.90, true);     -- Direct Entry at 200 level: probation, their first year
    h := assessment.standing_of(300, 2, 0.95, 0.90, false);    -- the pattern repeats at every level
    i := assessment.standing_of(200, 2, 1.00, 0.90, false);    -- at 1.0 nothing is pronounced
    PERFORM pg_temp.assert('Senate''s rule: probation at 100 level second semester and every first semester from 200 under 1.0; advised to withdraw at the second semester still under 1.0; nothing for a Direct Entry first semester or at 1.0',
        a IS NULL AND b = 'PROBATION' AND c = 'PROBATION' AND d IS NULL AND e = 'ADVISED_TO_WITHDRAW' AND f = 'PROBATION' AND g = 'PROBATION' AND h = 'ADVISED_TO_WITHDRAW' AND i IS NULL,
        format('100/1=%s 100/2=%s 200/1=%s DE=%s 200/2=%s fresh=%s DE200/2=%s 300/2=%s at1=%s', a, b, c, d, e, f, g, h, i));
END $$;

-- ── 17f. four consecutive closed semesters without a registration make a voluntary withdrawal (V247) ──
DO $$
DECLARE st uuid := gen_random_uuid(); reg uuid := gen_random_uuid(); n0 int; n1 int; n2 int; due0 boolean; due1 boolean; closed int; st_status text; changed int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
    VALUES (gen_random_uuid(), '9990/9991', date '9990-10-01', date '9991-08-31'), (gen_random_uuid(), '9991/9992', date '9991-10-01', date '9992-08-31')
    ON CONFLICT (name) DO NOTHING;   -- §101's legacy import may already have made 9991/9992
    INSERT INTO policy.semester (id, session, number, state)
    SELECT gen_random_uuid(), v.s, n, 'CLOSED' FROM (VALUES ('9990/9991'), ('9991/9992')) v(s) CROSS JOIN generate_series(1, 2) n
    ON CONFLICT (session, number) DO UPDATE SET state = 'CLOSED';
    -- the later test sessions other checks closed are set aside while this one counts (they are dated centuries ahead, so not yet open is true), and restored below
    CREATE TEMP TABLE IF NOT EXISTS vw_set_aside AS SELECT id FROM policy.semester WHERE false;
    INSERT INTO vw_set_aside SELECT id FROM policy.semester WHERE session > '9991/9992' AND state = 'CLOSED';
    UPDATE policy.semester SET state = 'NOT_YET_OPEN' WHERE id IN (SELECT id FROM vw_set_aside);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990904', 'MOAUM/CHK/99/0904', 'CHECKVOLUNTARY', 'Invented', 'C00023', 'UTME', '9990/9991', 100, 100, 'ACTIVE', now());
    SELECT semesters INTO n0 FROM registration.semesters_unregistered(st);                         -- four closed since entry, none registered
    due0 := EXISTS (SELECT 1 FROM registration.voluntary_withdrawals_due() d WHERE d.student_id = st);
    -- an approved registration in the third semester: only one closed semester follows it
    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (reg, st, '9991/9992', 1, 100, 'APPROVED', now());
    SELECT semesters INTO n1 FROM registration.semesters_unregistered(st);
    due1 := EXISTS (SELECT 1 FROM registration.voluntary_withdrawals_due() d WHERE d.student_id = st);
    DELETE FROM registration.course_registration WHERE id = reg;
    SELECT semesters INTO n2 FROM registration.semesters_unregistered(st);
    -- the Registry closes the record due: the status changes on the regulation as its instrument, and the change is on the record
    closed := registration.effect_voluntary_withdrawals('University regulation: four consecutive semesters without course registration', st);
    SELECT status INTO st_status FROM people.student WHERE id = st;
    SELECT count(*) INTO changed FROM people.status_change WHERE student_id = st AND to_status = 'VOLUNTARY_WITHDRAWAL';
    DELETE FROM people.status_change WHERE student_id = st;
    DELETE FROM people.student WHERE id = st;
    UPDATE policy.semester SET state = 'CLOSED' WHERE id IN (SELECT id FROM vw_set_aside);
    DROP TABLE vw_set_aside;
    BEGIN   -- the sessions stay where another check's records still hang on them
        DELETE FROM policy.semester WHERE session IN ('9990/9991', '9991/9992');
        DELETE FROM policy.academic_session WHERE name IN ('9990/9991', '9991/9992');
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    PERFORM pg_temp.assert('Four consecutive closed semesters without an approved registration make a voluntary withdrawal: due at four, not after a registration in the third, closed by the Registry on the regulation, on the record',
        n0 = 4 AND due0 AND n1 = 1 AND NOT due1 AND n2 = 4 AND closed = 1 AND st_status = 'VOLUNTARY_WITHDRAWAL' AND changed = 1,
        format('missed=%s due=%s after_reg=%s due_after=%s again=%s closed=%s status=%s changes=%s', n0, due0, n1, due1, n2, closed, st_status, changed));
END $$;

-- ── 17g. the College's progression: barred by attendance, the rule applied provisionally, the Board's confirmation moves the student (V248) ──
DO $$
DECLARE st uuid := gen_random_uuid(); ses text; anat uuid; bcm uuid; phs uuid; j record; barred_ok boolean; pass_ok boolean;
        o1 text; o2 text; st1 text; en_state text; n_conf int; o3 text; lvl int; en2_state text; hist int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'collegesecretary', true);
    SELECT name INTO ses FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1;
    IF ses IS NULL THEN SELECT name INTO ses FROM policy.academic_session ORDER BY name DESC LIMIT 1; END IF;
    SELECT s.id INTO anat FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id WHERE e.code = 'PE1' AND s.name = 'Anatomy';
    SELECT s.id INTO bcm  FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id WHERE e.code = 'PE1' AND s.name = 'Medical Biochemistry';
    SELECT s.id INTO phs  FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id WHERE e.code = 'PE1' AND s.name = 'Physiology';
    -- attendance below the 1st Professional's 75% bars the candidate; at 75 the marks decide
    SELECT * INTO j FROM college.judge(anat, 20, 40, NULL, 60);  barred_ok := j.barred AND j.passed = false;
    SELECT * INTO j FROM college.judge(anat, 20, 40, NULL, 80);  pass_ok := NOT j.barred AND j.passed;
    -- a College student at 300 Level, registered for the year
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990905', 'MOAUM/CHK/99/0905', 'CHECKCOLLEGE', 'Invented', 'C00061', 'UTME', ses, 100, 300, 'ACTIVE', now());
    INSERT INTO college.enrolment (student_id, level, session, registered_at, registered_items) VALUES (st, 300, ses, now(), 5);
    -- two subjects passed, Physiology failed at the first attempt: the rule says resit, applied provisionally
    INSERT INTO college.exam_result (student_id, subject_id, session, attempt, ca_score, exam_score, attendance_pct, passed, decided_on) VALUES
        (st, anat, ses, 'FIRST', 22, 45, 90, true, current_date), (st, bcm, ses, 'FIRST', 20, 40, 88, true, current_date);
    o1 := college.apply_provisional(st, 'PE1', ses);                                   -- incomplete: nothing applied
    INSERT INTO college.exam_result (student_id, subject_id, session, attempt, ca_score, exam_score, attendance_pct, passed, decided_on) VALUES
        (st, phs, ses, 'FIRST', 12, 25, 85, false, current_date);
    o2 := college.apply_provisional(st, 'PE1', ses);
    SELECT state INTO st1 FROM college.progression_decision WHERE student_id = st AND from_level = 300 AND session = ses;
    -- the Board confirms: the enrolment waits on the resit, the student stays at 300
    n_conf := college.confirm_decisions('PE1', ses, 'CAB/CHK/1');
    SELECT state INTO en_state FROM college.enrolment WHERE student_id = st AND level = 300 AND session = ses;
    -- the resit passed: the rule says promote; confirmed, the student is at 400 and the year is closed
    INSERT INTO college.exam_result (student_id, subject_id, session, attempt, ca_score, exam_score, attendance_pct, passed, decided_on) VALUES
        (st, phs, ses, 'RESIT', 18, 40, 85, true, current_date);
    o3 := college.apply_provisional(st, 'PE1', ses);
    PERFORM college.confirm_decisions('PE1', ses, 'CAB/CHK/2');
    SELECT current_level INTO lvl FROM people.student WHERE id = st;
    SELECT state INTO en2_state FROM college.enrolment WHERE student_id = st AND level = 300 AND session = ses;
    SELECT count(*) INTO hist FROM college.exam_result WHERE student_id = st;
    DELETE FROM college.progression_decision WHERE student_id = st;
    DELETE FROM college.exam_result WHERE student_id = st;
    DELETE FROM college.enrolment WHERE student_id = st;
    DELETE FROM people.status_change WHERE student_id = st;
    DELETE FROM people.student WHERE id = st;
    PERFORM pg_temp.assert('The College''s progression: attendance under the minimum bars; nothing applies until every subject is resulted; one fail at the first attempt is a provisional resit the Board confirms; the resit passed is a promotion that moves the student to 400 and closes the year',
        barred_ok AND pass_ok AND o1 IS NULL AND o2 = 'RESIT' AND st1 = 'PROVISIONAL' AND n_conf = 1 AND en_state = 'RESIT' AND o3 = 'PROMOTE' AND lvl = 400 AND en2_state = 'CLOSED' AND hist = 4,
        format('barred=%s pass=%s first=%s then=%s state=%s confirmed=%s enrolment=%s resit=%s level=%s closed=%s results=%s', barred_ok, pass_ok, o1, o2, st1, n_conf, en_state, o3, lvl, en2_state, hist));
END $$;

-- ── 17h. two cohorts at one level, each its own year: the cohort is the session's enrolments; the year's semesters; the end-of-year guard (V249) ──
DO $$
DECLARE a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); s_old text; s_new text; ea uuid; eb uuid; n_old int; n_new int; sems int;
        cur_level int; cur_session text; reached_undated boolean; reached_ahead boolean; reached_now boolean; ls text; refused boolean := false;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'collegesecretary', true);
    SELECT name INTO s_new FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1;
    IF s_new IS NULL THEN SELECT name INTO s_new FROM policy.academic_session ORDER BY name DESC LIMIT 1; END IF;
    SELECT name INTO s_old FROM policy.academic_session WHERE name < s_new ORDER BY name DESC LIMIT 1;
    IF s_old IS NULL THEN s_old := s_new; END IF;
    -- cohort A began 200 Level in the earlier session; cohort B, promoted from 100, begins it in the current one
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
        (a, 'MOAUM/ADM/99/990906', 'MOAUM/CHK/99/0906', 'CHECKCOHORT', 'Earlier', 'C00061', 'UTME', s_old, 100, 200, 'ACTIVE', now()),
        (b, 'MOAUM/ADM/99/990907', 'MOAUM/CHK/99/0907', 'CHECKCOHORT', 'Later',   'C00061', 'UTME', s_new, 100, 200, 'ACTIVE', now());
    ea := college.open_enrolment(a, 200, s_old, NULL);
    eb := college.open_enrolment(b, 200, s_new, NULL);
    SELECT count(*) INTO sems FROM college.enrolment_semester WHERE enrolment_id = ea;                    -- the two semesters of 200 Level
    SELECT count(*) INTO n_old FROM college.cohort(200, s_old);                                          -- A's cohort holds A, not B
    SELECT count(*) INTO n_new FROM college.cohort(200, s_new) c WHERE c.student_id IN (a, b);           -- B's holds B, not A
    SELECT (college.current_enrolment(a)).level, (college.current_enrolment(a)).session INTO cur_level, cur_session;   -- A's current year is the old session's
    -- a second year cannot open while one is open
    BEGIN PERFORM college.open_enrolment(a, 200, s_new, NULL); EXCEPTION WHEN check_violation THEN refused := true; END;
    -- the end-of-year guard: undated, it blocks (V285: false until the calendar is dated); the final semester ahead blocks; begun, it opens
    reached_undated := college.year_reached_final(200, s_old);
    INSERT INTO college.semester (session, level, ordinal, length_weeks, starts_on, ends_on) VALUES (s_old, 200, 1, 17, current_date - 200, current_date - 80), (s_old, 200, 2, 17, current_date + 10, current_date + 130);
    reached_ahead := college.year_reached_final(200, s_old);
    UPDATE college.semester SET starts_on = current_date - 5 WHERE session = s_old AND level = 200 AND ordinal = 2;
    reached_now := college.year_reached_final(200, s_old);
    ls := college.level_session(200);                                                                    -- the latest session the College dated for the level
    DELETE FROM college.semester WHERE session = s_old AND level = 200;
    DELETE FROM college.enrolment_semester WHERE enrolment_id IN (ea, eb);
    DELETE FROM college.enrolment WHERE id IN (ea, eb);
    DELETE FROM people.student WHERE id IN (a, b);
    PERFORM pg_temp.assert('Two cohorts at one level each keep their own year: a cohort is the session''s enrolments, the year carries the prospectus''s two semesters, the current year is the open one whatever the University''s session, one year at a time, and results open only once the final semester has begun, and not while the calendar is undated',
        sems = 2 AND n_old = 1 AND n_new = 1 AND cur_level = 200 AND cur_session = s_old AND refused AND NOT reached_undated AND NOT reached_ahead AND reached_now AND ls = s_old,
        format('semesters=%s old_cohort=%s new_cohort=%s current=%s/%s refused=%s undated=%s ahead=%s now=%s level_session=%s', sems, n_old, n_new, cur_level, cur_session, refused, reached_undated, reached_ahead, reached_now, ls));
END $$;

-- ── 17i. the MBBS Coordinator is held by level, by a College lecturer only (V250) ──
DO $$
DECLARE p1 uuid := gen_random_uuid(); p2 uuid := gen_random_uuid(); who uuid := gen_random_uuid(); refused_outsider boolean := false; refused_level boolean := false; lvl int; dept text;
BEGIN
    PERFORM set_config('moaum.actor_id', who::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (p1, 'MOAUM/CHK/0001', 'CHECKCOORD', 'Anatomy'), (p2, 'MOAUM/CHK/0002', 'CHECKCOORD', 'Mathematics');
    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES
        (gen_random_uuid(), p1, 'lecturer', 'department', 'ANT', 'check', who, current_date),
        (gen_random_uuid(), p2, 'lecturer', 'department', 'MTC', 'check', who, current_date);
    -- a Mathematics lecturer is refused the coordinatorship; a level outside 200 to 600 is refused
    BEGIN
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
        VALUES (gen_random_uuid(), p2, 'mbbscoordinator', 'level', '200', 'check', who, current_date);
    EXCEPTION WHEN check_violation THEN refused_outsider := true; END;
    BEGIN
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
        VALUES (gen_random_uuid(), p1, 'mbbscoordinator', 'level', '100', 'check', who, current_date);
    EXCEPTION WHEN check_violation THEN refused_level := true; END;
    -- the Anatomy lecturer holds 300 Level
    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
    VALUES (gen_random_uuid(), p1, 'mbbscoordinator', 'level', ' 300 ', 'check', who, current_date);
    lvl := iam.coordinator_level(p1);
    dept := iam.college_lecturer_dept(p1);
    DELETE FROM iam.office_assignment WHERE person_id IN (p1, p2);
    DELETE FROM iam.person WHERE id IN (p1, p2);
    PERFORM pg_temp.assert('The MBBS Coordinator is held by level, 200 to 600, by a College lecturer only: an outsider is refused, a level outside the range is refused, and the level held is read back (trimmed)',
        refused_outsider AND refused_level AND lvl = 300 AND dept = 'ANT',
        format('outsider_refused=%s level_refused=%s level=%s dept=%s', refused_outsider, refused_level, lvl, dept));
END $$;

-- ── 17j. an ICT support ticket: a number of the right shape, the lifecycle held, the resolution required, the history written once (V251) ──
DO $$
DECLARE who uuid := gen_random_uuid(); agent uuid := gen_random_uuid(); st uuid := gen_random_uuid(); t uuid; num text;
        refused_resolve boolean := false; refused_skip boolean := false; refused_edit boolean := false; refused_reopen boolean := false;
        st_after text; n_events int; closed_reason text;
BEGIN
    PERFORM set_config('moaum.actor_id', who::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (agent, 'MOAUM/CHK/0003', 'CHECKAGENT', 'Support');
    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
    VALUES (gen_random_uuid(), agent, 'ictagent', 'platform', NULL, 'check', who, current_date);
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, 'MOAUM/ADM/99/990990', 'MOAUM/MTC/20/9990', 'CHECKTICKET', 'Student', (SELECT code FROM ref.programme ORDER BY code LIMIT 1), 'UTME', '2020/2021', 100, 300, 'ACTIVE', now());

    -- submitted with the category's required fields: a number of the right shape, the priority the category suggests
    t := helpdesk.submit('STUDENT', st, 'CHECKTICKET, Student', 'MOAUM/MTC/20/9990', 'check@example.edu', '08012345678', NULL, NULL,
                         'PAYMENT', 'A payment that did not register', 'I paid on Monday and the portal still says unpaid.',
                         '{"payment_reference":"RRR-1","payment_date":"2026-09-01","payment_type":"School fees","amount":"45000"}'::jsonb);
    SELECT number INTO num FROM helpdesk.ticket WHERE id = t;

    -- an agent cannot resolve what is not in progress, nor skip from opened to closed without a reason
    PERFORM helpdesk.open_ticket(t, agent);
    BEGIN
        PERFORM helpdesk.resolve(t, agent, 'Fixed', 'The payment was matched to the ledger and the receipt reissued.');
    EXCEPTION WHEN check_violation THEN refused_resolve := true; END;
    BEGIN
        PERFORM helpdesk.transition(t, 'CLOSED', 'AGENT', agent, 'CHECKAGENT, Support', NULL);
    EXCEPTION WHEN check_violation THEN refused_skip := true; END;
    PERFORM helpdesk.transition(t, 'IN_PROGRESS', 'AGENT', agent, 'CHECKAGENT, Support', NULL);
    PERFORM helpdesk.resolve(t, agent, 'Payment matched', 'The payment was matched to the ledger and the receipt reissued to the student.');
    -- the requester is not satisfied: reopened on a reason, and only on a reason
    BEGIN
        PERFORM helpdesk.transition(t, 'REOPENED', 'REQUESTER', st, 'CHECKTICKET, Student', '');
    EXCEPTION WHEN check_violation THEN refused_reopen := true; END;
    PERFORM helpdesk.transition(t, 'REOPENED', 'REQUESTER', st, 'CHECKTICKET, Student', 'The receipt still shows the old amount');
    PERFORM helpdesk.transition(t, 'IN_PROGRESS', 'AGENT', agent, 'CHECKAGENT, Support', NULL);
    PERFORM helpdesk.resolve(t, agent, 'Receipt corrected', 'The receipt was regenerated with the amount as paid, and the student told.');
    PERFORM helpdesk.transition(t, 'CLOSED', 'REQUESTER', st, 'CHECKTICKET, Student', NULL);
    SELECT status, closure_reason INTO st_after, closed_reason FROM helpdesk.ticket WHERE id = t;
    SELECT count(*) INTO n_events FROM helpdesk.ticket_event WHERE ticket_id = t;
    -- the history is written once
    BEGIN
        UPDATE helpdesk.ticket_event SET detail = 'tampered' WHERE ticket_id = t;
    EXCEPTION WHEN check_violation THEN refused_edit := true; END;

    PERFORM set_config('moaum.maintenance', 'on', true);
    DELETE FROM helpdesk.ticket_event WHERE ticket_id = t;
    DELETE FROM helpdesk.ticket_comment WHERE ticket_id = t;
    DELETE FROM helpdesk.ticket WHERE id = t;
    PERFORM set_config('moaum.maintenance', '', true);
    DELETE FROM iam.office_assignment WHERE person_id = agent;
    DELETE FROM iam.person WHERE id = agent;
    DELETE FROM people.student WHERE id = st;

    PERFORM pg_temp.assert('A ticket is numbered TICK-YYYY-NNNNN and walks submitted → opened → in progress → resolved → closed',
        num ~ '^TICK-[0-9]{4}-[0-9]{5}$' AND refused_resolve AND refused_skip AND refused_reopen AND st_after = 'CLOSED' AND closed_reason = 'The requester confirmed the resolution',
        format('number=%s refused_resolve=%s refused_skip=%s refused_reopen=%s status=%s reason=%s', num, refused_resolve, refused_skip, refused_reopen, st_after, closed_reason));
    PERFORM pg_temp.assert('The ticket history holds every act and is written once',
        n_events = 8 AND refused_edit, format('events=%s refused_edit=%s', n_events, refused_edit));
END $$;

-- ── 17k. the nominal roll of non-academic staff is placed in its units; a dry run writes nothing; no sign-in is issued (V253) ──
DO $$
DECLARE who uuid := gen_random_uuid(); dry record; wet record; placed_unit text; placed_dept text; given text; has_login boolean; n_before int; n_after int;
BEGIN
    PERFORM set_config('moaum.actor_id', who::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    SELECT count(*) INTO n_before FROM iam.person WHERE staff_number IN ('P990001','P990002','P990003');
    SELECT * INTO dry FROM iam.import_staff('[
        {"pno":"990001","full_names":"CHECK TERFA ROLLONE","sex":"M","date_first_appointment":"04/01/2001","department":"BUR-DIRECTORATE OF FAT-[CASH OFFICE]","present_rank":"ACCOUNTANT","phone":"08000000001","contiss":"12"},
        {"pno":"990002","full_names":"CHECK ADI ROLLTWO","sex":"F","date_first_appointment":"29/04/1993","department":"CHS-DEPT. OF ANATOMY","present_rank":"SECRETARY","phone":"08000000002","contiss":"CONSOLIDATED"},
        {"pno":"990003","full_names":"CHECK NOBODY ROLLTHREE","sex":"M","date_first_appointment":"","department":"UNIT THAT DOES NOT EXIST","present_rank":"CLERK","phone":"","contiss":"7"}]'::jsonb, true);
    SELECT count(*) INTO n_after FROM iam.person WHERE staff_number IN ('P990001','P990002','P990003');
    SELECT * INTO wet FROM iam.import_staff('[
        {"pno":"990001","full_names":"CHECK TERFA ROLLONE","sex":"M","date_first_appointment":"04/01/2001","department":"BUR-DIRECTORATE OF FAT-[CASH OFFICE]","present_rank":"ACCOUNTANT","phone":"08000000001","contiss":"12"},
        {"pno":"990002","full_names":"CHECK ADI ROLLTWO","sex":"F","date_first_appointment":"29/04/1993","department":"CHS-DEPT. OF ANATOMY","present_rank":"SECRETARY","phone":"08000000002","contiss":"CONSOLIDATED"},
        {"pno":"990003","full_names":"CHECK NOBODY ROLLTHREE","sex":"M","date_first_appointment":"","department":"UNIT THAT DOES NOT EXIST","present_rank":"CLERK","phone":"","contiss":"7"}]'::jsonb, false);
    SELECT sr.home_unit, sr.unit_as_given INTO placed_unit, given FROM hrm.staff_record sr JOIN iam.person p ON p.id = sr.person_id WHERE p.staff_number = 'P990001';
    SELECT sr.home_department INTO placed_dept FROM hrm.staff_record sr JOIN iam.person p ON p.id = sr.person_id WHERE p.staff_number = 'P990002';
    SELECT EXISTS (SELECT 1 FROM iam.credential c JOIN iam.person p ON p.id = c.person_id WHERE p.staff_number IN ('P990001','P990002')) INTO has_login;
    DELETE FROM hrm.staff_record WHERE person_id IN (SELECT id FROM iam.person WHERE staff_number IN ('P990001','P990002'));
    DELETE FROM iam.person WHERE staff_number IN ('P990001','P990002');
    PERFORM pg_temp.assert('The nominal roll of non-academic staff is placed in its units, a dry run writes nothing, and no sign-in is issued',
        n_before = 0 AND n_after = 0 AND dry.rows = 3 AND dry.unplaced = 1 AND dry.unplaced_units = 'UNIT THAT DOES NOT EXIST'
        AND wet.created = 2 AND wet.unplaced = 1 AND placed_unit = 'BUR_FAT_CASH_OFFICE' AND placed_dept = 'ANT' AND given = 'BUR-DIRECTORATE OF FAT-[CASH OFFICE]' AND NOT has_login,
        format('dry=%s/%s/%s wet=%s/%s unit=%s dept=%s login=%s after_dry=%s', dry.rows, dry.unplaced, dry.unplaced_units, wet.created, wet.unplaced, placed_unit, placed_dept, has_login, n_after));
END $$;

-- ── 17l. an external examiner's assessment: scored within the maxima, the total computed, submitted once, reopened on a reason, the history written once (V254) ──
DO $$
DECLARE who uuid := gen_random_uuid(); px uuid := gen_random_uuid(); ex uuid; st uuid := gen_random_uuid(); pr uuid; asg uuid; ass uuid; rub uuid; c1 uuid; c2 uuid;
        refused_over boolean := false; refused_early boolean := false; refused_edit boolean := false; refused_reopen boolean := false; t_total numeric; t_pct numeric; t_grade text; st_after text; n_events int;
BEGIN
    PERFORM set_config('moaum.actor_id', who::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    INSERT INTO iam.person (id, surname, given_names, email) VALUES (px, 'CHECKEXAMINER', 'External', 'check.examiner@example.edu');
    INSERT INTO extexam.examiner (person_id, email, institution, status, activated_at) VALUES (px, 'check.examiner@example.edu', 'Check University', 'ACTIVE', now()) RETURNING id INTO ex;
    INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
    VALUES (st, NULL, 'MOAUM/MTC/20/9991', 'CHECKPROJECT', 'Student', (SELECT code FROM ref.programme ORDER BY code LIMIT 1), 'UTME', '2020/2021', 100, 400, 'ACTIVE', now());
    INSERT INTO extexam.project (student_id, kind, session, title) VALUES (st, 'UNDERGRADUATE', '2090/2091', 'A check project') RETURNING id INTO pr;
    SELECT id INTO rub FROM extexam.rubric WHERE code = 'UG_DEFAULT';
    INSERT INTO extexam.assignment (project_id, examiner_id, rubric_id, deadline, assigned_by) VALUES (pr, ex, rub, current_date + 14, who) RETURNING id INTO asg;
    PERFORM extexam.record('PROJECT_ASSIGNED', who, 'Check', ex, pr, asg, NULL, (current_date + 14)::text, NULL);
    INSERT INTO extexam.assessment (assignment_id) VALUES (asg) RETURNING id INTO ass;
    -- a score over the maximum is refused; submission before every line is scored is refused
    SELECT id INTO c1 FROM extexam.criterion WHERE rubric_id = rub ORDER BY ordinal LIMIT 1;
    BEGIN PERFORM extexam.score(ass, c1, 999, NULL); EXCEPTION WHEN check_violation THEN refused_over := true; END;
    BEGIN PERFORM extexam.submit(ass, px, 'CHECKEXAMINER, External'); EXCEPTION WHEN check_violation THEN refused_early := true; END;
    -- every line scored at its maximum: the total is the form's total, 100 per cent, the top grade in force
    FOR c2 IN SELECT id FROM extexam.criterion WHERE rubric_id = rub AND active LOOP
        PERFORM extexam.score(ass, c2, (SELECT max_score FROM extexam.criterion WHERE id = c2), 'fine');
    END LOOP;
    UPDATE extexam.assessment SET general_comments = 'A thorough, well-argued and well-built piece of work.', final_recommendation = 'PASS' WHERE id = ass;
    PERFORM extexam.submit(ass, px, 'CHECKEXAMINER, External');
    SELECT total, percentage, grade INTO t_total, t_pct, t_grade FROM extexam.assessment WHERE id = ass;
    -- submitted means read-only; reopening needs a reason; reopened means scorable again
    BEGIN PERFORM extexam.score(ass, c1, 1, NULL); EXCEPTION WHEN check_violation THEN refused_edit := true; END;
    BEGIN PERFORM extexam.reopen(ass, who, 'Check', ''); EXCEPTION WHEN check_violation THEN refused_reopen := true; END;
    PERFORM extexam.reopen(ass, who, 'Check', 'The defence marks want a second look');
    SELECT status INTO st_after FROM extexam.assignment WHERE id = asg;
    SELECT count(*) INTO n_events FROM extexam.event WHERE assignment_id = asg;

    PERFORM set_config('moaum.maintenance', 'on', true);
    DELETE FROM extexam.event WHERE assignment_id = asg OR examiner_id = ex OR project_id = pr;
    PERFORM set_config('moaum.maintenance', '', true);
    DELETE FROM extexam.assessment_score WHERE assessment_id = ass;
    DELETE FROM extexam.assessment WHERE id = ass;
    DELETE FROM extexam.assignment WHERE id = asg;
    DELETE FROM extexam.project WHERE id = pr;
    DELETE FROM extexam.examiner WHERE id = ex;
    DELETE FROM people.student WHERE id = st;
    DELETE FROM iam.person WHERE id = px;

    PERFORM pg_temp.assert('An external assessment is scored within its maxima, totalled by the form, submitted once and reopened only on a reason',
        refused_over AND refused_early AND t_total = (SELECT sum(max_score) FROM extexam.criterion WHERE rubric_id = rub AND active) AND t_pct = 100 AND t_grade = 'A'
        AND refused_edit AND refused_reopen AND st_after = 'REOPENED' AND n_events = 3,
        format('over=%s early=%s total=%s pct=%s grade=%s edit=%s reopen=%s status=%s events=%s', refused_over, refused_early, t_total, t_pct, t_grade, refused_edit, refused_reopen, st_after, n_events));
END $$;

-- ── V292. the clean slate reaches every table that hangs on what it clears ──
-- Computed from the catalogue, not from data: a table added later that refers to
-- anything platform.reset_operational_data deletes, without ON DELETE CASCADE or
-- SET NULL, and that the reset does not clear itself, would make the go-live
-- reset fail with a foreign-key violation. It fails here the day it is added.
DO $$
DECLARE n int; lst text;
BEGIN
    WITH RECURSIVE cleared AS (
        SELECT DISTINCT m[1]::regclass AS t
          FROM pg_proc p, regexp_matches(p.prosrc, 'DELETE FROM ([a-z_]+\.[a-z_]+)', 'g') AS m
         WHERE p.oid = 'platform.reset_operational_data(text, text)'::regprocedure),
    blocking AS (
        SELECT c.conrelid::regclass AS t, c.confrelid::regclass AS parent
          FROM pg_constraint c
         WHERE c.contype = 'f' AND c.confdeltype IN ('a', 'r') AND c.conrelid <> c.confrelid
           AND c.confrelid IN (SELECT t FROM cleared) AND c.conrelid NOT IN (SELECT t FROM cleared)
        UNION
        SELECT c.conrelid::regclass, c.confrelid::regclass
          FROM pg_constraint c JOIN blocking b ON c.confrelid = b.t
         WHERE c.contype = 'f' AND c.confdeltype IN ('a', 'r') AND c.conrelid <> c.confrelid AND c.conrelid NOT IN (SELECT t FROM cleared))
    SELECT count(DISTINCT t), string_agg(DISTINCT t::text || ' → ' || parent::text, ', ') INTO n, lst FROM blocking;
    PERFORM pg_temp.assert('The data reset clears every table that hangs on what it clears, so it cannot fail on a foreign key',
                           n = 0, coalesce(lst, 'none left behind'));
END $$;

-- ── V294. the biodata upload: one sealed hash an upload, and the same rows again write nothing ──
-- A migrated student's sign-in is opened sealed: a cost-12 hash of a random secret nobody holds (the
-- first sign-in is the student's own number while must_change holds). Made once a row, that hash was
-- nine tenths of the upload's time; it is made once an upload. A re-upload of unchanged rows writes
-- nothing, so it adds nothing to the audit chain. The block undoes its own writes.
DO $$
DECLARE v_rows jsonb; c1 int; c2 int; a int; h int; ok12 boolean; t0 timestamptz; w int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        SELECT jsonb_agg(jsonb_build_object('matric', 'MOAUM/CSC/19/' || lpad((9900 + i)::text, 4, '0'),
                   'surname', 'Sealcheck', 'otherNames', 'Row ' || i, 'level', '300',
                   'programme', (SELECT code FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1),
                   'phone', '0803000' || lpad(i::text, 4, '0'), 'nationality', 'Nigeria', 'lga', 'Makurdi'))
          INTO v_rows FROM generate_series(1, 5) i;
        SELECT created INTO c1 FROM people.import_biography(v_rows);
        SELECT count(*), count(DISTINCT x.password_hash), bool_and(x.password_hash LIKE '$2%$12$%' AND x.must_change)
          INTO a, h, ok12
          FROM iam.student_account x JOIN people.student s ON s.id = x.student_id
         WHERE s.matric_no LIKE 'MOAUM/CSC/19/99%';
        t0 := clock_timestamp();
        SELECT created INTO c2 FROM people.import_biography(v_rows);
        SELECT count(*) INTO w FROM audit.entries
         WHERE occurred_at >= t0
           AND subject_type IN ('people.student', 'people.student_contact', 'people.biodata', 'clearance.item');
        RAISE EXCEPTION 'the V294 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The biodata upload seals its sign-ins with one cost-12 hash; unchanged rows again write nothing',
        coalesce(c1 = 5 AND c2 = 0 AND a = 5 AND h = 1 AND ok12 AND w = 0, false),
        format('created=%s again=%s accounts=%s hashes=%s cost12=%s written-again=%s', c1, c2, a, h, ok12, w));
END $$;

-- ── V295. admission status checking follows the application, the window and the fee — never the decision ──
-- Every applicant with a valid Post-UTME application (fee confirmed, submitted) may pay the admission checking fee and check
-- their status while the Director of ICT has checking open — not yet decided, not admitted or admitted alike; nobody else may,
-- and nobody while it is closed (it is closed until first opened). The fee is paid once; the status comes from the decision.
-- Nothing about an offer can be learned or acted on before it is checked: the acceptance fee, the undertaking and the decline
-- give one answer whatever the decision; an admission already read continues after checking closes.
DO $$
DECLARE pend uuid; notad uuid; incomp uuid; offer uuid; ref1 text; ref2 text; ref3 text;
        r_closed text := 'ok'; r_incomp text := 'ok'; r_unpaid text := 'ok'; r_again text := 'ok'; r_accept text := 'ok';
        r_und text := 'ok'; r_dec text := 'ok'; r_acc_unread text := 'ok'; und text; st_after text; acc_after text;
        st_closed text; st_open text; st_pend text; st_notad text; st_offer text; st_later text; tr_hidden text; n_refs bigint; n_checks bigint;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state) VALUES (gen_random_uuid(), '9984/9985', date '9984-09-01', date '9985-08-31', 'DRAFT') ON CONFLICT DO NOTHING;
        CREATE TEMP TABLE v295_apps (tag text, app uuid) ON COMMIT DROP;
        DECLARE t record; cand uuid; acct uuid; app uuid; n int := 0;
        BEGIN
            FOR t IN SELECT * FROM (VALUES ('pending', true, NULL::text, false), ('notadmitted', true, 'NOT_OFFERED', true),
                                           ('incomplete', false, NULL, false), ('offered', true, 'OFFERED', true)) v(tag, submitted, decision, released) LOOP
                n := n + 1; cand := gen_random_uuid(); acct := gen_random_uuid(); app := gen_random_uuid();
                INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
                VALUES (cand, '9984/9985', '99840000000' || n || 'CK', 'V295-' || t.tag, 'Check', (SELECT name FROM ref.programme WHERE NOT archived ORDER BY code LIMIT 1), 'UTME', 100, 'PROPOSED');
                INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
                VALUES (acct, '9984/9985', cand, '99840000000' || n || 'CK', 'v295.' || t.tag || '@example.com', '08030000000', crypt('x', gen_salt('bf', 12)));
                INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, decision, decided_at, decision_released_at)
                VALUES (app, acct, cand, '9984/9985', 'APP/84/99990' || n, now(), CASE WHEN t.submitted THEN now() END, t.decision, CASE WHEN t.decision IS NOT NULL THEN now() END, CASE WHEN t.released THEN now() END);
                INSERT INTO v295_apps VALUES (t.tag, app);
            END LOOP;
        END;
        SELECT app INTO pend FROM v295_apps WHERE tag = 'pending';
        SELECT app INTO notad FROM v295_apps WHERE tag = 'notadmitted';
        SELECT app INTO incomp FROM v295_apps WHERE tag = 'incomplete';
        SELECT app INTO offer FROM v295_apps WHERE tag = 'offered';
        -- closed until the Director opens it
        SELECT status INTO st_closed FROM admissions.admission_status(notad);
        BEGIN PERFORM admissions.new_fee_reference(pend, 'CHECKING'); EXCEPTION WHEN check_violation THEN r_closed := split_part(SQLERRM, ':', 1); END;
        PERFORM set_config('moaum.actor_office', 'ict', true);
        PERFORM policy.window_act('ADMISSION_STATUS_CHECKING', '9984/9985', NULL, 'OPEN', NULL, NULL, NULL, false, 'check', gen_random_uuid(), 'ict');
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        SELECT status INTO st_open FROM admissions.admission_status(notad);
        SELECT string_agg(x->>'state', ',') INTO tr_hidden FROM jsonb_array_elements(admissions.admission_tracker(notad)) x WHERE x->>'key' = 'ADMISSION';
        BEGIN PERFORM admissions.new_fee_reference(incomp, 'CHECKING'); EXCEPTION WHEN check_violation THEN r_incomp := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.admission_status_checked(pend); EXCEPTION WHEN check_violation THEN r_unpaid := split_part(SQLERRM, ':', 1); END;
        -- an offer not yet read: accepting, declining or paying for it answers as for any applicant, and opens nothing
        BEGIN PERFORM admissions.sign_undertaking(offer); EXCEPTION WHEN check_violation THEN r_und := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.decline_offer(offer); EXCEPTION WHEN check_violation THEN r_dec := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.new_fee_reference(offer, 'ACCEPTANCE'); EXCEPTION WHEN check_violation THEN r_acc_unread := split_part(SQLERRM, ':', 1); END;
        -- open: the undecided, the not admitted and the admitted pay, once; a reference still open is the one returned
        ref1 := admissions.new_fee_reference(pend, 'CHECKING');
        ref2 := admissions.new_fee_reference(notad, 'CHECKING');
        ref3 := admissions.new_fee_reference(offer, 'CHECKING');
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        PERFORM admissions.confirm_fee(ref1, 'Card', 'check');
        PERFORM admissions.confirm_fee(ref2, 'Card', 'check');
        PERFORM admissions.confirm_fee(ref3, 'Card', 'check');
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        PERFORM admissions.admission_status_checked(pend);
        PERFORM admissions.admission_status_checked(notad);
        PERFORM admissions.admission_status_checked(offer);
        SELECT status INTO st_pend FROM admissions.admission_status(pend);
        SELECT status INTO st_notad FROM admissions.admission_status(notad);
        SELECT status INTO st_offer FROM admissions.admission_status(offer);
        BEGIN PERFORM admissions.new_fee_reference(pend, 'CHECKING'); EXCEPTION WHEN check_violation THEN r_again := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.new_fee_reference(notad, 'ACCEPTANCE'); EXCEPTION WHEN check_violation THEN r_accept := split_part(SQLERRM, ':', 1); END;
        -- the offer read: the undertaking follows; checking closes and the admission under way continues
        und := admissions.sign_undertaking(offer);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        PERFORM policy.window_act('ADMISSION_STATUS_CHECKING', '9984/9985', NULL, 'CLOSE', NULL, NULL, NULL, false, 'check closed', gen_random_uuid(), 'ict');
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        SELECT status INTO st_after FROM admissions.admission_status(offer);
        acc_after := left(admissions.new_fee_reference(offer, 'ACCEPTANCE'), 10);
        -- pending today, admitted later: checked again when checking reopens, without paying again
        PERFORM set_config('moaum.actor_office', 'ict', true);
        PERFORM policy.window_act('ADMISSION_STATUS_CHECKING', '9984/9985', NULL, 'REOPEN', NULL, NULL, NULL, false, 'check reopened', gen_random_uuid(), 'ict');
        PERFORM set_config('moaum.actor_office', 'academic', true);
        UPDATE admissions.application SET decision = 'OFFERED', decided_at = now(), decision_released_at = now() WHERE id = pend;
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        PERFORM admissions.admission_status_checked(pend);
        SELECT status INTO st_later FROM admissions.admission_status(pend);
        SELECT count(*) INTO n_refs FROM admissions.fee_reference WHERE application_id = pend AND kind = 'CHECKING';
        SELECT count(*) INTO n_checks FROM admissions.status_check WHERE application_id = pend;
        RAISE EXCEPTION 'the V295 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('Admission status checking follows the application, the window and the fee, never the decision',
        coalesce(st_closed = 'CHECKING_CLOSED' AND r_closed = 'ADMISSION_CHECKING_CLOSED' AND st_open = 'CHECKING_FEE_PENDING' AND tr_hidden = 'now'
                 AND r_incomp = 'ADMISSION_CHECKING_NOT_ELIGIBLE' AND r_unpaid = 'ADMISSION_CHECKING_FEE_UNPAID' AND ref1 <> ref2
                 AND r_und = 'ADMISSION_STATUS_NOT_CHECKED' AND r_dec = 'ADMISSION_STATUS_NOT_CHECKED' AND r_acc_unread = 'ADMISSION_STATUS_NOT_CHECKED'
                 AND st_pend = 'PENDING' AND st_notad = 'NOT_ADMITTED' AND st_offer = 'ADMITTED' AND r_again = 'ADMISSION_CHECKING_PAID'
                 AND r_accept = 'ADMISSION_STATUS_NOT_CHECKED' AND und = 'undertaking signed' AND st_after = 'ACCEPTANCE_PENDING' AND acc_after = 'MOAUM-ACC-'
                 AND st_later = 'ADMITTED' AND n_refs = 1 AND n_checks = 2, false),
        format('closed=%s/%s open=%s tracker=%s incomplete=%s unpaid=%s unread=%s/%s/%s pending=%s notadmitted=%s offered=%s again=%s acceptance=%s undertaking=%s after-close=%s/%s later=%s refs=%s checks=%s',
               st_closed, r_closed, st_open, tr_hidden, r_incomp, r_unpaid, r_und, r_dec, r_acc_unread, st_pend, st_notad, st_offer, r_again, r_accept,
               und, st_after, acc_after, st_later, n_refs, n_checks));
END $$;

-- ── V296. the old-portal applicants come with their email and phone ──
-- A contact cell is read as people write it; a new applicant is imported with the file's email and phone, an applicant already
-- migrated takes them (the office's contacts replace the placeholders and what an earlier file gave), an account the applicant
-- opened keeps theirs, an email already on another account is not taken, and every row says what happened and why.
DO $$
DECLARE r1 record; r2 record; r3 record; r4 record; r5 record; r6 record; r7 record; r8 record; w1 text; w2 text; n_ev bigint; lst record;
        reads boolean;
BEGIN
    reads := admissions.first_email('Ada Obi <Ada.Obi@Gmail.com>, other@x.com') = 'ada.obi@gmail.com'
         AND admissions.first_email('x@migrate.moau.local') IS NULL AND admissions.first_email('not an email') IS NULL
         AND admissions.first_mobile('+234 803 123 4567') = '08031234567' AND admissions.first_mobile('8031234567') = '08031234567'
         AND admissions.first_mobile('08031234567 / 07061234567') = '08031234567' AND admissions.first_mobile('01234567890') IS NULL
         AND admissions.first_mobile('00000000000') IS NULL;
    BEGIN
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        DECLARE b uuid := gen_random_uuid(); i int;
        BEGIN
            INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at)
            VALUES (b, '9982/9983', 'CAPS_DOWNLOAD', 'check.xlsx', decode(md5(b::text), 'hex'), 4, 'UTME', current_date, gen_random_uuid(), 'academic', now());
            FOR i IN 1..4 LOOP
                INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
                VALUES (gen_random_uuid(), b, '9982/9983', '998200000' || i || 'CK', '{}'::jsonb, 'V296-' || i, 'Check', 'C00023', 220, 'UTME', 'F', 'Benue', 'Makurdi');
            END LOOP;
        END;
        SELECT * INTO r1 FROM admissions.import_applicant_row('9982/9983', '9982000001CK', 'One.V296@Mail.com', '+234 803 123 4567');   -- new, with contacts
        SELECT * INTO r2 FROM admissions.import_applicant_row('9982/9983', '9982000002ck', 'not-an-email', '');                        -- new, on placeholders, told why
        SELECT * INTO r3 FROM admissions.import_applicant_row('9982/9983', '9982000003CK', 'one.v296@mail.com', '0706 555 1234');      -- the email is another's
        SELECT * INTO r4 FROM admissions.import_applicant_row('9982/9983', '9982000002CK', 'two.v296@mail.com', '8061112222');         -- already migrated: filled
        SELECT * INTO r5 FROM admissions.import_applicant_row('9982/9983', '9982000001CK', 'one.new.v296@mail.com', '');               -- the office's newer email
        SELECT * INTO r6 FROM admissions.import_applicant_row('9982/9983', '9982000001CK', 'ONE.NEW.V296@mail.com', '08031234567');    -- nothing to change
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        PERFORM admissions.register_applicant('9982/9983', '9982000004CK', 'own.v296@choice.com', '08099998888', crypt('x', gen_salt('bf', 12)));
        PERFORM set_config('moaum.actor_office', 'academic', true);
        SELECT * INTO r7 FROM admissions.import_applicant_row('9982/9983', '9982000004CK', 'office.v296@file.com', '08011112222');     -- the applicant's own are kept
        SELECT * INTO r8 FROM admissions.import_applicant_row('9982/9983', '9982000099CK', 'x.v296@y.com', '08031234567');             -- not on CAPS
        w1 := admissions.import_applicant('9982/9983', '9982000003CK', 'three.v296@mail.com', '');                                      -- the text answer of old
        w2 := admissions.import_applicant('9982/9983', 'NOT A NUMBER', '', '');
        SELECT count(*) INTO n_ev FROM admissions.applicant_event WHERE identifier LIKE '998200000%' AND outcome LIKE 'CONTACTS_UPDATED%';
        SELECT count(*) AS migrated, count(*) FILTER (WHERE has_email) AS e, count(*) FILTER (WHERE has_phone) AS p INTO lst FROM admissions.migrated_contacts('9982/9983');
        RAISE EXCEPTION 'the V296 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The old-portal applicants come with their email and phone, and those already migrated take them',
        coalesce(reads
            AND r1.o_outcome = 'IMPORTED' AND r1.o_email = 'one.v296@mail.com' AND r1.o_phone = '08031234567' AND r1.o_email_note IS NULL AND r1.o_phone_note IS NULL
            AND r2.o_outcome = 'IMPORTED' AND r2.o_email = '9982000002ck@migrate.moau.local' AND r2.o_phone = '00000000000'
            AND r2.o_email_note LIKE 'not a usable email address%' AND r2.o_phone_note = 'no phone number in the file'
            AND r3.o_outcome = 'IMPORTED' AND r3.o_email LIKE '%@migrate.moau.local' AND r3.o_email_note LIKE 'already on another applicant%' AND r3.o_phone = '07065551234'
            AND r4.o_outcome = 'UPDATED' AND r4.o_email = 'two.v296@mail.com' AND r4.o_phone = '08061112222' AND r4.o_detail = 'email and phone updated'
            AND r5.o_outcome = 'UPDATED' AND r5.o_email = 'one.new.v296@mail.com' AND r5.o_phone = '08031234567' AND r5.o_phone_note IS NULL
            AND r6.o_outcome = 'EXISTS' AND r6.o_email_note IS NULL AND r6.o_phone_note IS NULL
            AND r7.o_outcome = 'EXISTS' AND r7.o_email = 'own.v296@choice.com' AND r7.o_email_note LIKE 'kept the email the applicant chose%' AND r7.o_phone_note LIKE 'kept the phone%'
            AND r8.o_outcome = 'SKIPPED' AND r8.o_detail = 'not on the JAMB CAPS list'
            AND w1 = 'exists' AND w2 = 'skip: bad JAMB number' AND n_ev = 3
            AND lst.migrated = 3 AND lst.e = 3 AND lst.p = 3, false),
        format('reads=%s r1=%s/%s/%s r2=%s/%s/%s r3=%s/%s r4=%s/%s r5=%s/%s r6=%s r7=%s/%s r8=%s/%s wrapper=%s/%s events=%s listed=%s/%s/%s',
               reads, r1.o_outcome, r1.o_email, r1.o_phone, r2.o_outcome, r2.o_email_note, r2.o_phone_note, r3.o_outcome, r3.o_email_note,
               r4.o_outcome, r4.o_detail, r5.o_outcome, r5.o_email, r6.o_outcome, r7.o_outcome, r7.o_email_note, r8.o_outcome, r8.o_detail,
               w1, w2, n_ev, lst.migrated, lst.e, lst.p));
END $$;

-- ── V297. an admission found in error is corrected after the decision, even after school fees, and every change is listed ──
-- The ordinary change is shut once the decision is released; a correction takes over up to matriculation (after it, a transfer).
-- It is recommended with the error described, decided by the Registrar's office and not by its recommender, keeps the fees paid
-- against the new programme (the position before and after on the record), returns the courses registered on the old one and
-- reissues the letter; the register lists the applicant with the programme applied for and the programme held now. The fee
-- schedule read for a programme named agrees with the fee schedule read for the programme held.
DO $$
DECLARE academic uuid := gen_random_uuid(); registrar uuid := gen_random_uuid();
        cand uuid := gen_random_uuid(); acct uuid := gen_random_uuid(); app uuid := gen_random_uuid(); st uuid; reg uuid;
        e_cand uuid := gen_random_uuid(); e_acct uuid := gen_random_uuid(); e_app uuid := gen_random_uuid();
        m_cand uuid := gen_random_uuid(); m_acct uuid := gen_random_uuid(); m_app uuid := gen_random_uuid(); m_st uuid;
        r_ordinary text := 'ok'; r_note text := 'ok'; r_elig text := 'ok'; r_approver text := 'ok'; r_same text := 'ok'; r_early text := 'ok'; r_mat text := 'ok';
        req uuid; pv jsonb; rt record; decided text; q record; reg_row record; st_row record; pos record; reg_line record; charges_same boolean;
        e_route text; m_route text; n_letters bigint; stage_after text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', academic::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state) VALUES (gen_random_uuid(), '9986/9987', date '9986-09-01', date '9987-08-31', 'DRAFT') ON CONFLICT DO NOTHING;
        INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, ord)
        VALUES ('9986/9987', 'Tuition (V297 check)', 150000, 100, 'C00023', 1), ('9986/9987', 'Tuition (V297 check)', 120000, 100, 'C00019', 1);
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state)
        VALUES (cand, '9986/9987', '9986000001CK', 'V297-Corrected', 'Check', (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, 'PROPOSED'),
               (e_cand, '9986/9987', '9986000002CK', 'V297-Undecided', 'Check', (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, 'PROPOSED'),
               (m_cand, '9986/9987', '9986000003CK', 'V297-Matriculated', 'Check', (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, 'PROPOSED');
        DECLARE b uuid := gen_random_uuid();
        BEGIN
            INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at)
            VALUES (b, '9986/9987', 'CAPS_DOWNLOAD', 'v297.xlsx', decode(md5(b::text), 'hex'), 2, 'UTME', current_date, academic, 'academic', now());
            INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
            VALUES (gen_random_uuid(), b, '9986/9987', '9986000001CK', '{}'::jsonb, 'V297-Corrected', 'Check', 'C00023', 220, 'UTME', 'F', 'Benue', 'Makurdi'),
                   (gen_random_uuid(), b, '9986/9987', '9986000003CK', '{}'::jsonb, 'V297-Matriculated', 'Check', 'C00023', 220, 'UTME', 'M', 'Benue', 'Gboko');
            UPDATE admissions.candidate c SET offer_state = 'ADMITTED', admitted_from = r.id FROM admissions.caps_row r
             WHERE r.batch_id = b AND r.jamb_reg_no = c.jamb_reg_no AND c.id IN (cand, m_cand);
        END;
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
        VALUES (acct, '9986/9987', cand, '9986000001CK', 'v297.one@example.com', '08030000000', crypt('x', gen_salt('bf', 12))),
               (e_acct, '9986/9987', e_cand, '9986000002CK', 'v297.two@example.com', '08030000000', crypt('x', gen_salt('bf', 12))),
               (m_acct, '9986/9987', m_cand, '9986000003CK', 'v297.three@example.com', '08030000000', crypt('x', gen_salt('bf', 12)));
        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, decision, decided_at, decision_released_at, accepted_at)
        VALUES (app, acct, cand, '9986/9987', 'APP/86/000001', now(), now(), 'OFFERED', now(), now(), now()),
               (e_app, e_acct, e_cand, '9986/9987', 'APP/86/000002', now(), now(), NULL, NULL, NULL, NULL),
               (m_app, m_acct, m_cand, '9986/9987', 'APP/86/000003', now(), now(), 'OFFERED', now(), now(), now());
        -- offered, accepted, on the register, school fees paid (150,000 on Computer Science), courses registered and approved, the letter issued
        st := people.intake_one(cand);
        m_st := people.intake_one(m_cand);
        UPDATE people.student SET matric_no = 'MOAUM/MTC/86/9701', matriculated_at = now() WHERE id = m_st;
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
        VALUES (st, '9986/9987', 'MOAUM-FEE-V297-0001', 'School fees 9986/9987', 150000, now() + interval '1 day', now(), academic, 'Card', 'RCPT-V297-0001');
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), st, '9986/9987', 1, 100, 'APPROVED', now()) RETURNING id INTO reg;
        PERFORM admissions.issue_admission_letter(app);
        SELECT * INTO rt FROM admissions.programme_change_route(app);
        SELECT route INTO e_route FROM admissions.programme_change_route(e_app);
        SELECT route INTO m_route FROM admissions.programme_change_route(m_app);
        charges_same := (SELECT coalesce(sum(amount), 0) FROM finance.charges(st, '9986/9987')) = 150000
                    AND finance.due_as(st, '9986/9987', NULL) = 150000 AND finance.due_as(st, '9986/9987', 'C00019') = 120000;
        pv := admissions.correction_preview(app, 'C00019');
        BEGIN PERFORM admissions.recommend_programme_change(app, 'C00019', 'ADMISSION_POLICY', NULL, academic, 'academic', false, NULL); EXCEPTION WHEN check_violation THEN r_ordinary := left(SQLERRM, 26); END;
        BEGIN PERFORM admissions.recommend_admission_correction(app, 'C00019', 'ADMISSION_ERROR', '  ', academic, 'academic', false, NULL); EXCEPTION WHEN check_violation THEN r_note := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.recommend_admission_correction(app, 'C00019', 'ADMISSION_ERROR', 'Admitted to Computer Science on a mis-keyed UTME score', academic, 'academic', false, NULL); EXCEPTION WHEN check_violation THEN r_elig := left(SQLERRM, 29); END;
        BEGIN PERFORM admissions.recommend_admission_correction(e_app, 'C00019', 'ADMISSION_ERROR', 'x', academic, 'academic', true, 'x'); EXCEPTION WHEN check_violation THEN r_early := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.recommend_admission_correction(m_app, 'C00019', 'ADMISSION_ERROR', 'x', academic, 'academic', true, 'x'); EXCEPTION WHEN check_violation THEN r_mat := split_part(SQLERRM, ':', 1); END;
        req := admissions.recommend_admission_correction(app, 'C00019', 'ADMISSION_ERROR', 'Admitted to Computer Science on a mis-keyed UTME score', academic, 'academic', true, 'Registrar''s directive on the audit of the list');
        BEGIN PERFORM admissions.decide_programme_change(req, 'APPROVE', NULL, academic); EXCEPTION WHEN check_violation THEN r_approver := split_part(SQLERRM, ':', 1); END;
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        BEGIN PERFORM admissions.decide_programme_change(req, 'APPROVE', NULL, academic); EXCEPTION WHEN check_violation THEN r_same := split_part(SQLERRM, ':', 1); END;
        PERFORM set_config('moaum.actor_id', registrar::text, true);
        decided := admissions.decide_programme_change(req, 'APPROVE', 'Corrected on the audit of the admission list', registrar);
        SELECT * INTO q FROM admissions.programme_change_request WHERE id = req;
        SELECT * INTO reg_row FROM registration.course_registration WHERE id = reg;
        SELECT s.programme_code, c.programme INTO st_row FROM people.student s JOIN admissions.candidate c ON c.id = s.candidate_id WHERE s.id = st;
        SELECT * INTO pos FROM finance.position(st, '9986/9987');
        SELECT * INTO reg_line FROM admissions.programme_change_register('9986/9987') x WHERE x.application_id = app;
        SELECT count(*) INTO n_letters FROM credentials.issued WHERE application_id = app AND kind = 'ADMISSION_LETTER';
        stage_after := admissions.admission_stage(app);
        RAISE EXCEPTION 'the V297 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('An admission found in error is corrected after school fees, by the Registrar, and listed',
        coalesce(rt.route = 'CORRECTION' AND rt.stage = 'COURSES_REGISTERED' AND e_route = 'CHANGE' AND m_route = 'TRANSFER' AND charges_same
                 AND (pv #>> '{fees,dueAfter}')::numeric = 120000 AND (pv #>> '{fees,excessAfter}')::numeric = 30000 AND pv #>> '{target,result}' = 'UNVERIFIED'
                 AND r_ordinary = 'the Board''s decision on th' AND r_note = 'CORRECTION_NOTE_REQUIRED' AND r_elig = 'the candidate is not eligible'
                 AND r_early = 'CORRECTION_NOT_NEEDED' AND r_mat = 'CORRECTION_TRANSFER' AND r_approver = 'CORRECTION_APPROVER' AND r_same = 'CORRECTION_SAME_OFFICER'
                 AND decided = 'APPROVED' AND q.kind = 'CORRECTION' AND q.admission_stage = 'COURSES_REGISTERED' AND q.decided_office = 'registrar'
                 AND q.fees_paid = 150000 AND q.fees_due_before = 150000 AND q.fees_due_after = 120000 AND q.registrations_returned = 1 AND q.letter_reissued
                 AND reg_row.status = 'RETURNED' AND reg_row.approved_at IS NULL AND reg_row.returned_comment LIKE 'Your admission was corrected from%'
                 AND st_row.programme_code = 'C00019' AND st_row.programme = (SELECT name FROM ref.programme WHERE code = 'C00019')
                 AND pos.due = 120000 AND pos.paid = 150000 AND pos.balance = 0 AND n_letters = 2 AND stage_after = 'SCHOOL_FEES_PAID'
                 AND reg_line.applied_code = 'C00023' AND reg_line.current_code = 'C00019' AND reg_line.moved AND reg_line.stage = 'CORRECTION'
                 AND reg_line.reason = 'Error discovered in the admission' AND reg_line.fees_due_after = 120000 AND reg_line.history LIKE '%"kind": "CORRECTION"%', false),
        format('route=%s/%s early=%s matriculated=%s charges=%s preview=%s/%s/%s refusals=%s|%s|%s|%s|%s|%s|%s decided=%s request=%s/%s/%s fees=%s/%s/%s regs=%s letter=%s registration=%s/%s student=%s position=%s/%s/%s letters=%s stage=%s register=%s→%s %s %s',
               rt.route, rt.stage, e_route, m_route, charges_same, pv #>> '{fees,dueAfter}', pv #>> '{fees,excessAfter}', pv #>> '{target,result}',
               r_ordinary, r_note, r_elig, r_early, r_mat, r_approver, r_same, decided, q.kind, q.admission_stage, q.decided_office,
               q.fees_paid, q.fees_due_before, q.fees_due_after, q.registrations_returned, q.letter_reissued, reg_row.status, left(reg_row.returned_comment, 30),
               st_row.programme_code, pos.due, pos.paid, pos.balance, n_letters, stage_after, reg_line.applied_code, reg_line.current_code, reg_line.stage, reg_line.reason));
END $$;

-- ── V298 / V315. an O'Level upload is checked for duplicates ──
-- The same result again (the exam number written another way, or no number and the same grades) is not recorded again; the same
-- exam number with other grades is held, not recorded, until the Office keeps the one on record or uses the uploaded one in its
-- place; another exam number of the same body — the same year and series or not — is a sitting of its own (V315: results are
-- combined across sittings); the same exam number on another applicant's record is recorded and flagged until verified. Every
-- finding is kept, and the Office's word always says how it was verified.
DO $$
DECLARE officer uuid := gen_random_uuid(); k1 text := '9980000001OL'; k2 text := '9980000002OL';
        a1 uuid := gen_random_uuid(); a2 uuid := gen_random_uuid(); a3 uuid := gen_random_uuid(); a4 uuid := gen_random_uuid(); a5 uuid := gen_random_uuid(); a6 uuid := gen_random_uuid();
        n1 int; n2 int; n3 int; n4 int; n5 int; n6 int; s1 int; s1_after int; s2 int; held uuid; flagged uuid; st_use text; st_ver text;
        r_note text := 'ok'; r_again text := 'ok'; r_office text := 'ok'; numbers text; kinds text; listed bigint; helpers boolean; flag_other text; known_again boolean; known_new boolean;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', officer::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        helpers := admissions.olevel_series_class('GCE', NULL) = 'EXTERNAL' AND admissions.olevel_series_class('WASSCE', 'MAY/JUNE') = 'INTERNAL'
               AND admissions.olevel_series_class('WAEC', 'Nov/Dec') = 'EXTERNAL' AND admissions.olevel_series_class('SSCE', NULL) = 'INTERNAL'
               AND admissions.olevel_exam_key(' 4250-101/001 ') = '4250101001' AND admissions.olevel_exam_key('  ') IS NULL
               AND admissions.olevel_year('MAY/JUNE 2023') = '2023' AND admissions.olevel_year('n/a') IS NULL;
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload) VALUES (a1, '9980/9981', 'OLEVEL', 'v298-1', k1, 'COLUMN',
          '{"sittings":[{"type":"WASSCE","series":"MAY/JUNE","year":"2023","examNumber":"4250101001","subjects":[{"subject":"English Language","grade":"C6"},{"subject":"Mathematics","grade":"B3"},{"subject":"Physics","grade":"C5"}]},
                        {"type":"NECO","year":"2023","examNumber":"1234567890","subjects":[{"subject":"English Language","grade":"B3"},{"subject":"Chemistry","grade":"C4"}]}]}'::jsonb);
        n1 := admissions.olevel_from_attachment(a1);
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload) VALUES (a2, '9980/9981', 'OLEVEL', 'v298-2', k1, 'COLUMN',
          '{"sittings":[{"type":"WAEC","year":"2023","examNumber":"4250101 001","subjects":[{"subject":"English Language","grade":"C6"},{"subject":"Mathematics","grade":"B3"},{"subject":"Physics","grade":"C5"}]}]}'::jsonb);
        n2 := admissions.olevel_from_attachment(a2);
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload) VALUES (a3, '9980/9981', 'OLEVEL', 'v298-3', k1, 'COLUMN',
          '{"sittings":[{"type":"WASSCE","series":"MAY/JUNE","year":"2023","examNumber":"4250101002","subjects":[{"subject":"English Language","grade":"B2"},{"subject":"Mathematics","grade":"A1"},{"subject":"Physics","grade":"B3"}]},
                        {"type":"WAEC GCE","series":"NOV/DEC","year":"2023","examNumber":"4250999001","subjects":[{"subject":"Biology","grade":"C4"}]}]}'::jsonb);
        n3 := admissions.olevel_from_attachment(a3);
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload) VALUES (a4, '9980/9981', 'OLEVEL', 'v298-4', k2, 'COLUMN',
          '{"sittings":[{"type":"WAEC","year":"2022","examNumber":"4250-101-001","subjects":[{"subject":"English Language","grade":"A1"}]}]}'::jsonb);
        n4 := admissions.olevel_from_attachment(a4);
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload) VALUES (a5, '9980/9981', 'OLEVEL', 'v298-5', k1, 'COLUMN',
          '{"sittings":[{"type":"WAEC","year":"May/June 2023","subjects":[{"subject":"Physics","grade":"C5"},{"subject":"English Language","grade":"C6"},{"subject":"Mathematics","grade":"B3"}]}]}'::jsonb);
        n5 := admissions.olevel_from_attachment(a5);
        -- V315: the same exam number again with other grades is the one thing held
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload) VALUES (a6, '9980/9981', 'OLEVEL', 'v315-6', k1, 'COLUMN',
          '{"sittings":[{"type":"WASSCE","series":"MAY/JUNE","year":"2023","examNumber":"4250101001","subjects":[{"subject":"English Language","grade":"B2"},{"subject":"Mathematics","grade":"A1"},{"subject":"Physics","grade":"B3"}]}]}'::jsonb);
        n6 := admissions.olevel_from_attachment(a6);
        s1 := admissions.olevel_sittings('9980/9981', k1);
        s2 := admissions.olevel_sittings('9980/9981', k2);
        -- a file sent again brings nothing new when every sitting is the same result on record; one with a second result does
        known_again := admissions.olevel_payload_known('9980/9981', k1, '{"sittings":[{"type":"WAEC","series":"May/June","year":"2023","examNumber":"4250 101 001","subjects":[{"subject":"English Language","grade":"C6"},{"subject":"Mathematics","grade":"B3"},{"subject":"Physics","grade":"C5"}]},{"type":"NECO","year":"2023","examNumber":"1234567890","subjects":[{"subject":"English Language","grade":"B3"},{"subject":"Chemistry","grade":"C4"}]}]}'::jsonb);
        known_new := admissions.olevel_payload_known('9980/9981', k1, '{"sittings":[{"type":"NECO","year":"2024","examNumber":"1234567891","subjects":[{"subject":"Chemistry","grade":"B3"}]}]}'::jsonb);
        SELECT string_agg(kind || ':' || state, ',' ORDER BY attachment_id = a2 DESC, attachment_id = a4 DESC, attachment_id = a5 DESC, attachment_id = a6 DESC) INTO kinds FROM admissions.olevel_duplicate WHERE session = '9980/9981';
        SELECT id INTO held FROM admissions.olevel_duplicate WHERE attachment_id = a6 AND kind = 'SAME_SITTING';
        SELECT id, other_jamb_key INTO flagged, flag_other FROM admissions.olevel_duplicate WHERE attachment_id = a4 AND kind = 'NUMBER_ELSEWHERE';
        BEGIN PERFORM admissions.olevel_duplicate_decide(held, 'USE', ' ', officer, 'academic'); EXCEPTION WHEN check_violation THEN r_note := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM admissions.olevel_duplicate_decide(held, 'USE', 'x', officer, 'bursar'); EXCEPTION WHEN check_violation THEN r_office := split_part(SQLERRM, ':', 1); END;
        st_use := admissions.olevel_duplicate_decide(held, 'USE', 'Verified on the WAEC result checker: 4250101002 is the candidate''s', officer, 'academic');
        BEGIN PERFORM admissions.olevel_duplicate_decide(held, 'KEEP', 'x', officer, 'academic'); EXCEPTION WHEN check_violation THEN r_again := split_part(SQLERRM, ':', 1); END;
        st_ver := admissions.olevel_duplicate_decide(flagged, 'VERIFIED', 'WAEC confirms 4250101001 is the first candidate''s', officer, 'academic');
        s1_after := admissions.olevel_sittings('9980/9981', k1);
        SELECT string_agg(exam_number, ',' ORDER BY exam_number) INTO numbers FROM admissions.olevel_sitting WHERE session = '9980/9981' AND jamb_key = k1;
        SELECT count(*) INTO listed FROM admissions.olevel_duplicates('9980/9981');
        RAISE EXCEPTION 'the V298 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('An O''Level upload is checked for duplicates: the same result skipped, the same exam number with other grades held, another number recorded, a shared number flagged',
        coalesce(helpers AND n1 = 2 AND n2 = 0 AND n3 = 2 AND n4 = 1 AND n5 = 0 AND n6 = 0 AND s1 = 4 AND s2 = 1
                 AND kinds = 'SAME_RESULT:SKIPPED,NUMBER_ELSEWHERE:OPEN,SAME_RESULT:SKIPPED,SAME_SITTING:HELD' AND flag_other = k1
                 AND r_note = 'OLEVEL_DUPLICATE_NOTE' AND r_office = 'OLEVEL_DUPLICATE_OFFICE' AND r_again = 'OLEVEL_DUPLICATE_DECIDED'
                 AND st_use = 'USED' AND st_ver = 'VERIFIED' AND s1_after = 4 AND numbers = '1234567890,4250101001,4250101002,4250999001' AND listed = 4
                 AND known_again AND NOT known_new, false),
        format('helpers=%s recorded=%s/%s/%s/%s/%s/%s sittings=%s/%s findings=%s flagged-with=%s refusals=%s/%s/%s decided=%s/%s after=%s numbers=%s listed=%s known=%s/%s',
               helpers, n1, n2, n3, n4, n5, n6, s1, s2, kinds, flag_other, r_note, r_office, r_again, st_use, st_ver, s1_after, numbers, listed, known_again, known_new));
END $$;

-- ── V299. Pay on Quickteller: the portal's own reference in cid, the amount if wanted, the biller of the payer's College ──
-- Off until the Bursary switches a biller on; a link can only be an Interswitch page. A College of Health
-- Sciences payer goes to the College's biller while it is in use, else to the University's. Quickteller's
-- question about a reference is answered from the reference itself; the collections import leaves a short
-- payment open. The block undoes its own writes.
DO $$
DECLARE s_main uuid := gen_random_uuid(); s_chs uuid := gen_random_uuid(); r_main text; r_chs text;
        off_link int; off_any boolean; r_link text; r_needs text; stored text; l_main text; l_chs_off int; l_chs text; l_chs_main text;
        cu record; cu_unknown record; cu_paid record; imp record; chs_open boolean; main_paid boolean; logged boolean;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
            (s_main, 'MOAUM/ADM/99/990299', 'MOAUM/CHK/99/0299', 'CHECKQT', 'Main', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now()),
            (s_chs,  'MOAUM/ADM/99/990300', 'MOAUM/CHK/99/0300', 'CHECKQT', 'Health', 'C00061', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
        r_main := finance.new_reference(s_main, '9999/0000', 51000, NULL);
        r_chs := finance.new_reference(s_chs, '9999/0000', 48000.50, NULL);

        -- off until switched on
        SELECT count(*) INTO off_link FROM finance.quickteller_link(r_main);
        off_any := finance.quickteller_redirect_on();
        -- a link to any other site is refused, and so is a redirect with nowhere to go
        BEGIN PERFORM finance.set_paydirect_biller('MAIN', '04255101', 'Benue State University, Makurdi', 'https://quickteller.example.com/bsum', true, true, true);
        EXCEPTION WHEN check_violation THEN r_link := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM finance.set_paydirect_biller('MAIN', '04255101', 'Benue State University, Makurdi', NULL, true, true, true);
        EXCEPTION WHEN check_violation THEN r_needs := split_part(SQLERRM, ':', 1); END;
        -- switched on: the host is read without regard to case, a trailing slash dropped
        SELECT pay_link INTO stored FROM finance.set_paydirect_biller('MAIN', '04255101', 'Benue State University, Makurdi', 'HTTPS://Quickteller.com/bsum/', true, true, true);
        SELECT url INTO l_main FROM finance.quickteller_link(r_main);
        -- the College's biller is in use but not switched on: its payer is not sent to the University's instead
        SELECT count(*) INTO l_chs_off FROM finance.quickteller_link(r_chs);
        PERFORM finance.set_paydirect_biller('CHS', '04263001', 'College of Health Sciences, Benue', 'https://quickteller.com/chsbsu', true, true, false);
        SELECT url INTO l_chs FROM finance.quickteller_link(r_chs);
        -- the College's biller out of use: its payers pay the University's
        PERFORM finance.set_paydirect_biller('CHS', '04263001', 'College of Health Sciences, Benue', 'https://quickteller.com/chsbsu', false, false, true);
        SELECT url INTO l_chs_main FROM finance.quickteller_link(r_chs);

        -- what Quickteller is told about a reference
        SELECT * INTO cu FROM finance.paydirect_customer(lower(r_main));
        SELECT * INTO cu_unknown FROM finance.paydirect_customer('MOAUM-FEE-NOSUCH-0000');
        -- the collections report: short of the amount stays open; the whole amount confirms
        SELECT * INTO imp FROM finance.import_paydirect(jsonb_build_array(
            jsonb_build_object('prn', r_chs, 'amount', '1000', 'rrn', 'RRNQT299A'),
            jsonb_build_object('prn', r_main, 'amount', '51000', 'rrn', 'RRNQT299B')));
        chs_open := (SELECT confirmed_at IS NULL FROM finance.payment_reference WHERE reference = r_chs);
        main_paid := (SELECT confirmed_at IS NOT NULL FROM finance.payment_reference WHERE reference = r_main);
        SELECT * INTO cu_paid FROM finance.paydirect_customer(r_main);
        -- the log keeps a reference check and a reversal as what they are
        PERFORM finance.log_gateway_event('paydirect', 'VALIDATE', 'validate', r_main, NULL, 51000, '0', true, 'VALID', NULL);
        PERFORM finance.log_gateway_event('paydirect', 'WEBHOOK', 'notification', r_main, 'PLOG299', -51000, 'reversal', true, 'REVERSED', NULL);
        logged := true;
        RAISE EXCEPTION 'the V299 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('Pay on Quickteller carries the portal''s own reference and the amount to the biller of the payer''s College, only once switched on and only to Interswitch',
        coalesce(off_link = 0 AND NOT off_any AND r_link = 'QUICKTELLER_LINK' AND r_needs = 'QUICKTELLER_REDIRECT_NEEDS_LINK'
                 AND stored = 'https://quickteller.com/bsum'
                 AND l_main = 'https://quickteller.com/bsum?cid=' || r_main || '&amount=51000'
                 AND l_chs_off = 0 AND l_chs = 'https://quickteller.com/chsbsu?cid=' || r_chs
                 AND l_chs_main = 'https://quickteller.com/bsum?cid=' || r_chs || '&amount=48000.50'
                 AND cu.valid AND cu.reference = r_main AND cu.surname = 'CHECKQT' AND cu.amount = 51000 AND cu.number = 'MOAUM/CHK/99/0299'
                 AND NOT cu_unknown.valid AND imp.matched = 1 AND imp.short_paid = 1 AND chs_open AND main_paid
                 AND NOT cu_paid.valid AND cu_paid.why = 'Already paid' AND logged, false),
        format('off=%s/%s refusals=%s/%s stored=%s main=%s chs_off=%s chs=%s chs_main=%s customer=%s/%s/%s unknown=%s import=%s/%s open=%s paid=%s after=%s/%s',
               off_link, off_any, r_link, r_needs, stored, l_main, l_chs_off, l_chs, l_chs_main, cu.valid, cu.surname, cu.amount,
               cu_unknown.valid, imp.matched, imp.short_paid, chs_open, main_paid, cu_paid.valid, cu_paid.why));
END $$;

-- ── V312: the application windows — open until the Director acts, the applicant's own writes refused while closed ──
DO $$
DECLARE st_default text; st_closed text; r_applicant text; r_office text; st_sched text; st_reopen text; msg text; pub record; n_ev int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state) VALUES (gen_random_uuid(), '9983/9984', date '9983-09-01', date '9984-08-31', 'DRAFT') ON CONFLICT DO NOTHING;
        SELECT state INTO st_default FROM policy.window_state('POST_UTME_REGISTRATION', '9983/9984', NULL);
        PERFORM policy.window_act('POST_UTME_REGISTRATION', '9983/9984', NULL, 'CLOSE', NULL, NULL, NULL, false, 'check closed', gen_random_uuid(), 'ict');
        SELECT state INTO st_closed FROM policy.window_state('POST_UTME_REGISTRATION', '9983/9984', NULL);
        -- the applicant registering themselves is held at the door, before any constraint is reached
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        BEGIN
            INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
            VALUES (gen_random_uuid(), '9983/9984', gen_random_uuid(), '998300000001CK', 'v312@example.com', '08030000000', 'x');
            r_applicant := 'ALLOWED';
        EXCEPTION WHEN check_violation THEN r_applicant := split_part(SQLERRM, ':', 1); END;
        -- an office's write is not an applicant registering: it goes past the window to the constraints
        PERFORM set_config('moaum.actor_office', 'academic', true);
        BEGIN
            INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
            VALUES (gen_random_uuid(), '9983/9984', gen_random_uuid(), '998300000002CK', 'v312b@example.com', '08030000000', 'x');
            r_office := 'ALLOWED';
        EXCEPTION WHEN OTHERS THEN r_office := split_part(SQLERRM, ':', 1); END;
        -- scheduled for later is not open; reopened is
        PERFORM set_config('moaum.actor_office', 'ict', true);
        PERFORM policy.window_act('POST_UTME_REGISTRATION', '9983/9984', NULL, 'SCHEDULE', now() + interval '1 day', now() + interval '30 days', NULL, false, NULL, gen_random_uuid(), 'ict');
        SELECT state INTO st_sched FROM policy.window_state('POST_UTME_REGISTRATION', '9983/9984', NULL);
        PERFORM policy.window_act('POST_UTME_REGISTRATION', '9983/9984', NULL, 'REOPEN', NULL, NULL, NULL, false, 'check reopened', gen_random_uuid(), 'ict');
        SELECT state INTO st_reopen FROM policy.window_state('POST_UTME_REGISTRATION', '9983/9984', NULL);
        -- the closure message is the Director's plain text, and the public reads it
        PERFORM policy.window_message_set('POSTGRADUATE_APPLICATION', E'<b>Closed</b> until <i>March</i>.\r\n\r\nWatch the website.', gen_random_uuid(), 'ict');
        SELECT message INTO msg FROM policy.portal_window_message WHERE window_type = 'POSTGRADUATE_APPLICATION';
        SELECT * INTO pub FROM policy.application_windows_public() WHERE window_type = 'POSTGRADUATE_APPLICATION';
        SELECT count(*) INTO n_ev FROM policy.portal_window_event WHERE window_type = 'POST_UTME_REGISTRATION' AND session = '9983/9984';
        RAISE EXCEPTION 'the V312 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('Application windows are open until the Director of ICT acts, hold the applicant''s own registration at the door while closed or scheduled, and carry the Director''s plain-text message to the public',
        coalesce(st_default = 'OPEN' AND st_closed = 'CLOSED' AND r_applicant = 'APPLICATION_CLOSED' AND r_office <> 'APPLICATION_CLOSED'
                 AND st_sched = 'SCHEDULED' AND st_reopen = 'OPEN'
                 AND msg = E'Closed until March.\n\nWatch the website.' AND pub.message = msg AND pub.state IN ('OPEN', 'CLOSED', 'SCHEDULED', 'EXPIRED')
                 AND n_ev = 3, false),
        format('default=%s closed=%s applicant=%s office=%s scheduled=%s reopened=%s msg=%s pub=%s/%s events=%s',
               st_default, st_closed, r_applicant, r_office, st_sched, st_reopen, msg, pub.state, pub.message, n_ev));
END $$;

-- ── V314: GST & EPS — the fee the Bursar states holds GST and EPS courses until the one confirmed payment lifts it ──
DO $$
DECLARE st uuid := gen_random_uuid(); dept text; o_gst uuid := gen_random_uuid(); o_ent uuid := gen_random_uuid(); reg uuid; e record;
        split_gst text; split_ent text; r_unstated text; r_unpaid text; r_ent text; r_other text; r_choose text; r_paid text; ref text;
        n_notice int; n_pop int; n_ent int; n_entries int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        SELECT dept_code INTO dept FROM ref.programme WHERE code = 'C00061';
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (st, 'MOAUM/ADM/99/990314', 'MOAUM/CHK/99/0314', 'CHECKGST', 'Invented', 'C00061', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
            ('GST 991', 'Check General Studies', 2, 1, 100, dept, 'GST', 'LIVE'),
            ('ENT 991', 'Check Venture Creation', 2, 1, 100, dept, 'GST', 'LIVE');
        INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('GST 991', 'C00061', 100, 'GST'), ('ENT 991', 'C00061', 100, 'GST');
        INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (o_gst, 'GST 991', '9999/0000', 1), (o_ent, 'ENT 991', '9999/0000', 1);
        SELECT general_office INTO split_gst FROM catalogue.course WHERE code = 'GST 991';
        SELECT general_office INTO split_ent FROM catalogue.course WHERE code = 'ENT 991';
        PERFORM set_config('moaum.actor_office', 'student', true);
        INSERT INTO people.student_contact (student_id, email, phone) VALUES (st, 'check.gst@example.com', '08030000314');
        -- no fee stated: nothing to pay, and no gate
        r_unstated := coalesce(registration.gst_gate(st, '9999/0000', 'GST 991'), 'OPEN');
        -- the Bursar states the fee: the GST course and the EPS course are held, another course is not
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        PERFORM finance.state_gst_fee('9999/0000', 10000, NULL, NULL, NULL, NULL, NULL, 'check', gen_random_uuid(), 'bursar');
        r_unpaid := split_part(coalesce(registration.gst_gate(st, '9999/0000', 'GST 991'), 'OPEN'), ':', 1);
        r_ent := split_part(coalesce(registration.gst_gate(st, '9999/0000', 'ENT 991'), 'OPEN'), ':', 1);
        r_other := coalesce(registration.gst_gate(st, '9999/0000', 'CHK 101'), 'OPEN');
        -- the registration itself refuses the GST course to the unpaid student
        PERFORM set_config('moaum.actor_office', 'student', true);
        reg := registration.student_draft(st, '9999/0000', 1);
        BEGIN
            PERFORM registration.student_choose(reg, ARRAY[o_gst]);
            r_choose := 'ALLOWED';
        EXCEPTION WHEN check_violation THEN r_choose := split_part(SQLERRM, ':', 1); END;
        -- the one payment, confirmed on the ledger: entitled, the gate lifts for GST and EPS alike, the student is told
        ref := finance.new_gst_reference(st, '9999/0000');
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        PERFORM finance.confirm_payment(ref, 'Bank transfer', 'check');
        SELECT * INTO e FROM finance.gst_entitlement(st, '9999/0000');
        r_paid := coalesce(registration.gst_gate(st, '9999/0000', 'GST 991'), 'OPEN');
        PERFORM set_config('moaum.actor_office', 'student', true);
        PERFORM registration.student_choose(reg, ARRAY[o_gst, o_ent]);
        SELECT count(*) INTO n_entries FROM registration.entry WHERE registration_id = reg AND entry_type = 'GST';
        SELECT count(*) INTO n_notice FROM platform.notice WHERE about_kind = 'student' AND about_id = st AND subject ILIKE 'GST fee%';
        SELECT count(*), count(*) FILTER (WHERE entitled AND gst_registered AND eps_registered AND pay_state = 'PAID')
          INTO n_pop, n_ent FROM finance.gst_population('9999/0000', NULL) WHERE student_id = st;
        RAISE EXCEPTION 'the V314 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('GST & EPS: the fee the Bursar states holds GST and EPS courses alone until the one confirmed payment lifts it, and the student is told',
        coalesce(split_gst = 'GST' AND split_ent = 'EPS' AND r_unstated = 'OPEN' AND r_unpaid = 'GST_PAYMENT_REQUIRED' AND r_ent = 'GST_PAYMENT_REQUIRED' AND r_other = 'OPEN'
                 AND r_choose = 'GST_PAYMENT_REQUIRED' AND e.entitled AND e.state = 'PAID' AND e.paid = 10000 AND r_paid = 'OPEN' AND n_entries = 2
                 AND n_notice >= 1 AND n_pop = 1 AND n_ent = 1, false),
        format('split=%s/%s unstated=%s unpaid=%s ent=%s other=%s choose=%s entitled=%s state=%s paid=%s after=%s entries=%s notices=%s population=%s/%s',
               split_gst, split_ent, r_unstated, r_unpaid, r_ent, r_other, r_choose, e.entitled, e.state, e.paid, r_paid, n_entries, n_notice, n_pop, n_ent));
END $$;

-- ── V316: a bounded office grant carries the register's code — a name resolves to it, an unknown name is refused ──
DO $$
DECLARE who uuid := gen_random_uuid(); g1 uuid := gen_random_uuid(); g2 uuid := gen_random_uuid(); g3 uuid := gen_random_uuid();
        s_dept text; s_prog text; s_fac text; r_unknown text := 'ALLOWED'; v_prog_name text; v_fac_name text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        INSERT INTO iam.person (id, surname, given_names, staff_number) VALUES (who, 'CHECKSCOPE', 'Invented', 'P-V316');
        SELECT name INTO v_prog_name FROM ref.programme WHERE code = 'C00023';
        SELECT name INTO v_fac_name FROM ref.faculty WHERE code = 'SC';
        -- typed as names: the Head of Department over the department's name, the Examinations Officer over the programme's name, the Dean over the faculty's name
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
        VALUES (g1, who, 'hod', 'department', 'mathematics and computer science', 'check', who, current_date),
               (g2, who, 'exams', 'programme', v_prog_name, 'check', who, current_date),
               (g3, who, 'dean', 'faculty', lower(v_fac_name), 'check', who, current_date);
        SELECT scope_id INTO s_dept FROM iam.office_assignment WHERE id = g1;
        SELECT scope_id INTO s_prog FROM iam.office_assignment WHERE id = g2;
        SELECT scope_id INTO s_fac FROM iam.office_assignment WHERE id = g3;
        -- a name the register does not know is refused
        BEGIN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), who, 'hod', 'department', 'Department of Nowhere', 'check', who, current_date);
        EXCEPTION WHEN check_violation THEN r_unknown := split_part(SQLERRM, ':', 1); END;
        RAISE EXCEPTION 'the V316 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A bounded office grant carries the register''s code: a department, programme or faculty typed by name is stored as its code, and an unknown name is refused',
        coalesce(s_dept = 'MTC' AND s_prog = 'C00023' AND s_fac = 'SC' AND r_unknown = 'OFFICE_SCOPE_UNKNOWN', false),
        format('department=%s programme=%s faculty=%s unknown=%s', s_dept, s_prog, s_fac, r_unknown));
END $$;

-- ── 161-162. V318: coverage is counted from the roll; an upload on behalf names its uploader and says why ──
DO $$
DECLARE sh uuid; o uuid; o2 uuid := gen_random_uuid(); sh2 uuid := gen_random_uuid(); s1 uuid; up uuid;
        lect uuid := gen_random_uuid(); officer uuid := gen_random_uuid();
        v_exp bigint; v_rec bigint; v_mis bigint; v_gra bigint;
        r_noreason text; r_teach text; r_blank text; v_by uuid; v_office text; v_owner uuid; e_by uuid; e_office text; e_behalf boolean;
BEGIN
    -- the sheet block 74 took through the chain: two on the roll, one graded and one absent — nothing missing
    SELECT s.id, oo.id INTO sh, o FROM assessment.score_sheet s JOIN catalogue.offering oo ON oo.id = s.offering_id WHERE oo.course_code = 'ZZC 101';
    SELECT id INTO s1 FROM people.student WHERE admission_no = 'MOAUM/ADM/99/000001';
    SELECT expected, received, missing, graded INTO v_exp, v_rec, v_mis, v_gra FROM assessment.sheet_coverage(sh);
    PERFORM pg_temp.assert('Coverage is counted from the roll: two candidates expected, two with a mark or an outcome, none missing, one graded',
        v_exp = 2 AND v_rec = 2 AND v_mis = 0 AND v_gra = 1, format('expected=%s received=%s missing=%s graded=%s', v_exp, v_rec, v_mis, v_gra));

    BEGIN
        PERFORM set_config('moaum.actor_id', officer::text, true);
        PERFORM set_config('moaum.actor_office', 'exams', true);
        INSERT INTO iam.person (id, surname, given_names, staff_number) VALUES (lect, 'CHECKLECT', 'Invented', 'P-V318-L'), (officer, 'CHECKEXAMS', 'Invented', 'P-V318-E');
        -- a second sitting of the course with its lecturer, and a sheet at entry
        INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id) VALUES (o2, 'ZZC 101', '9999/0000', 2, lect);
        INSERT INTO assessment.score_sheet (id, offering_id) VALUES (sh2, o2);
        -- an upload on behalf without a reason is refused
        BEGIN
            PERFORM assessment.record_upload_on_behalf(sh2, NULL, 1);
        EXCEPTION WHEN check_violation THEN r_noreason := split_part(SQLERRM, ':', 1); END;
        -- the lecturer's own entry is not on anyone's behalf
        PERFORM set_config('moaum.actor_id', lect::text, true);
        PERFORM set_config('moaum.actor_office', 'lecturer', true);
        BEGIN
            PERFORM assessment.record_upload_on_behalf(sh2, 'lecturer away', 1);
        EXCEPTION WHEN check_violation THEN r_teach := split_part(SQLERRM, ':', 1); END;
        -- the officer, with the reason: the record names the uploader, their office and the lecturer of record
        PERFORM set_config('moaum.actor_id', officer::text, true);
        PERFORM set_config('moaum.actor_office', 'exams', true);
        up := assessment.record_upload_on_behalf(sh2, 'Lecturer on medical leave', 1);
        SELECT uploaded_by, uploader_office, owner_id INTO v_by, v_office, v_owner FROM assessment.sheet_upload WHERE id = up;
        -- a mark on behalf without its reason is refused by the table itself
        BEGIN
            INSERT INTO assessment.score (sheet_id, student_id, ca, exam, on_behalf) VALUES (sh2, s1, 30, 45, true);
        EXCEPTION WHEN check_violation THEN r_blank := 'refused'; END;
        INSERT INTO assessment.score (sheet_id, student_id, ca, exam, on_behalf, on_behalf_reason) VALUES (sh2, s1, 30, 45, true, 'Lecturer on medical leave');
        SELECT entered_by, entered_office, on_behalf INTO e_by, e_office, e_behalf FROM assessment.score WHERE sheet_id = sh2 AND student_id = s1;
        RAISE EXCEPTION 'the V318 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('An upload on behalf says why and names its uploader: refused without a reason, refused from the lecturer, recorded with the officer, their office and the lecturer of record; the mark itself refuses on-behalf without a reason and carries who wrote it',
        coalesce(r_noreason = 'RES_UPLOAD_ON_BEHALF_SAYS_WHY' AND r_teach = 'RES_NOT_ON_BEHALF' AND v_by = officer AND v_office = 'exams' AND v_owner = lect
                 AND r_blank = 'refused' AND e_by = officer AND e_office = 'exams' AND e_behalf, false),
        format('no reason=%s lecturer=%s by=%s office=%s owner=%s blank=%s entered_by=%s', r_noreason, r_teach, v_by = officer, v_office, v_owner = lect, r_blank, e_by = officer));
END $$;

-- ── 163. V319: a grant is amended with its reason, its scope normalised, and an ended grant is left as it was ──
DO $$
DECLARE who uuid := gen_random_uuid(); g1 uuid := gen_random_uuid(); g2 uuid := gen_random_uuid();
        r_noreason text; r_ended text; o_after text; s_after text; v_prog_name text; v_reason text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        INSERT INTO iam.person (id, surname, given_names, staff_number) VALUES (who, 'CHECKAMEND', 'Invented', 'P-V319');
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from, valid_to)
        VALUES (g1, who, 'hod', 'department', 'MTC', 'check', who, current_date, NULL),
               (g2, who, 'exams', 'programme', 'C00023', 'check', who, current_date - 30, current_date - 1);
        -- without a reason, refused
        BEGIN
            PERFORM iam.amend_grant(g1, 'exams', 'programme', 'C00023', 'check', NULL, NULL, NULL);
        EXCEPTION WHEN check_violation THEN r_noreason := split_part(SQLERRM, ':', 1); END;
        -- the office and the scope change in place, the scope typed as a name and stored as the register's code
        SELECT name INTO v_prog_name FROM ref.programme WHERE code = 'C00023';
        PERFORM iam.amend_grant(g1, 'exams', 'programme', v_prog_name, 'Registrar memo REG/2026/400', NULL, NULL,
                                'granted as Head of Department in error; the letter appoints an Examinations Officer');
        SELECT office_code, scope_id INTO o_after, s_after FROM iam.office_assignment WHERE id = g1;
        v_reason := current_setting('moaum.reason', true);
        -- an ended grant stays as it was
        BEGIN
            PERFORM iam.amend_grant(g2, 'exams', 'programme', 'C00023', 'check', NULL, NULL, 'too late');
        EXCEPTION WHEN check_violation THEN r_ended := split_part(SQLERRM, ':', 1); END;
        RAISE EXCEPTION 'the V319 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A grant is amended with its reason: refused without one, the office and the scope changed in place with the scope as the register''s code, the reason on the audit context, and an ended grant left as it was',
        coalesce(r_noreason = 'IAM_AMEND_SAYS_WHY' AND o_after = 'exams' AND s_after = 'C00023' AND v_reason LIKE 'grant amended:%' AND r_ended = 'IAM_GRANT_ENDED', false),
        format('no reason=%s office=%s scope=%s reason=%s ended=%s', r_noreason, o_after, s_after, left(v_reason, 30), r_ended));
END $$;

-- ── 164-165. V320: one institution profile every document reads, changed with its rules and audited; an issued document on the record ──
DO $$
DECLARE n int; v_name text; r_blank text; r_mail text; v_motto text; audited int; who uuid := gen_random_uuid(); iss uuid; v_actor uuid; v_kind text;
BEGIN
    SELECT count(*), max(name) INTO n, v_name FROM platform.institution_profile;
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        BEGIN
            PERFORM platform.set_institution_profile(' ', 'X', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, true, true, 'LONG');
        EXCEPTION WHEN check_violation THEN r_blank := split_part(SQLERRM, ':', 1); END;
        BEGIN
            PERFORM platform.set_institution_profile('A University', 'AU', NULL, NULL, NULL, NULL, NULL, NULL, 'not-an-address', NULL, NULL, true, true, 'LONG');
        EXCEPTION WHEN check_violation THEN r_mail := split_part(SQLERRM, ':', 1); END;
        v_motto := platform.set_institution_profile('A University', 'AU', ' Knowledge and Service ', NULL, 'Makurdi', NULL, NULL, NULL, 'info@example.edu.ng', 'www.example.edu.ng', NULL, true, true, 'SHORT') ->> 'motto';
        SELECT count(*) INTO audited FROM audit.entries WHERE subject_type = 'platform.institution_profile' AND action = 'UPDATE' AND actor_id = who;
        iss := platform.record_document_issue('receipt_downloaded', 'RCT/2026/000001', 'payment', 'RCT/2026/000001', '{"format":"pdf"}'::jsonb);
        SELECT actor_id, kind INTO v_actor, v_kind FROM platform.document_issue WHERE id = iss;
        RAISE EXCEPTION 'the V320 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('One institution profile heads every document: seeded with a name, a blank name and a malformed e-mail refused, a change trimmed and audited in the actor''s name',
        coalesce(n = 1 AND v_name <> '' AND r_blank = 'INSTITUTION_NAME_REQUIRED' AND r_mail = 'INSTITUTION_EMAIL_INVALID' AND v_motto = 'Knowledge and Service' AND audited >= 1, false),
        format('rows=%s blank=%s mail=%s motto=%s audited=%s', n, r_blank, r_mail, v_motto, audited));
    PERFORM pg_temp.assert('A document the portal issues is on the record in the actor''s name, its kind in capitals',
        coalesce(v_actor = who AND v_kind = 'RECEIPT_DOWNLOADED', false), format('actor=%s kind=%s', v_actor = who, v_kind));
END $$;

-- ── 166. V321: a bulk allocation import is recorded under a reference numbered in the session, and the same key never records twice ──
DO $$
DECLARE who uuid := gen_random_uuid(); k uuid := gen_random_uuid(); r1 catalogue.allocation_import; r2 catalogue.allocation_import; r3 catalogue.allocation_import;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'hod', true);
        r1 := catalogue.record_allocation_import(k, 'allocations.xlsx', '9999/0000', 1, 'MTC', 10, 8, 7, 1, 3, 2, 1, 'COMPLETED_WITH_ERRORS', '{"allowOverload":false}'::jsonb, '[]'::jsonb);
        r2 := catalogue.record_allocation_import(k, 'allocations.xlsx', '9999/0000', 1, 'MTC', 10, 8, 7, 1, 3, 2, 1, 'COMPLETED_WITH_ERRORS', '{}'::jsonb, '[]'::jsonb);
        r3 := catalogue.record_allocation_import(gen_random_uuid(), 'more.xlsx', '9999/0000', 2, 'MTC', 1, 1, 1, 0, 0, 0, 0, 'COMPLETED', '{}'::jsonb, '[]'::jsonb);
        RAISE EXCEPTION 'the V321 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A bulk allocation import is recorded under a reference numbered in the session, in the uploader''s name; the same key answers with the record already made, and the next import takes the next number',
        coalesce(r1.reference ~ '^ALLOC/9999-0000/\d{5}$' AND r1.uploaded_by = who AND r1.uploader_office = 'hod' AND r2.id = r1.id AND r2.reference = r1.reference
                 AND r3.id <> r1.id AND r3.reference > r1.reference, false),
        format('first=%s again=%s next=%s', r1.reference, r2.reference, r3.reference));
END $$;

-- ── 167-168. V322: a CBT attempt is the server's — eligibility judged at the start, the second sign-in by policy, the paper drawn by a seed,
--                   the score in one transaction and never twice, the violation policy applied, the result a version with its reason ──
DO $$
DECLARE who uuid := gen_random_uuid(); st uuid := gen_random_uuid(); off uuid := gen_random_uuid(); ex assessment.cbt_exam; a assessment.cbt_attempt; a2 assessment.cbt_attempt; r assessment.cbt_result;
        q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid(); reg uuid; ref text;
        r_unpublished text; r_unregistered text; r_unpaid text; r_paid text; r_limit text; r_old_token text; r_publish_empty text;
        tok1 uuid; tok2 uuid; ev jsonb; v_status text; v_score numeric; v_pct numeric; v_grade text; v_passed boolean; v_events int; v_again numeric; v_versions int; v_sweep int; v_sweep_status text;
        v_live text; v_results text; v_student_sees numeric; v_student_hidden numeric; v_key_leak int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'gst', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '9995/9996', date '9995-10-01', date '9996-08-31') ON CONFLICT (name) DO NOTHING;
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
        SELECT 'GST 995', 'Check General Studies', 2, 1, 100, p.dept_code, 'GST', 'LIVE' FROM ref.programme p WHERE p.code = 'C00023';
        INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('GST 995', 'C00023', 100, 'GST');
        INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (off, 'GST 995', '9995/9996', 1);
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (st, 'MOAUM/ADM/95/000995', 'MOAUM/CHK/95/995', 'ZZCHECKCBT', 'Invented', 'C00023', 'UTME', '9995/9996', 100, 100, 'ACTIVE', now());
        INSERT INTO assessment.question (id, course_code, stem, options, answer, kind, marks) VALUES (q1, 'GST 995', 'one of four', '["a","b","c","d"]', 2, 'MCQ', 1), (q2, 'GST 995', 'true or false', '["True","False"]', 0, 'TRUE_FALSE', 1);
        INSERT INTO assessment.question (id, course_code, stem, options, answer, answers, kind, marks) VALUES (q3, 'GST 995', 'several', '["a","b","c","d"]', 0, ARRAY[3, 1], 'MULTI', 2);
        -- the key is kept as a sorted array whatever the kind, and never appears in what a paper carries (the question ids only)
        SELECT count(*) INTO v_key_leak FROM assessment.question WHERE id IN (q1, q2, q3) AND NOT (answers = ARRAY[answer] OR (kind = 'MULTI' AND answers = ARRAY[1, 3]));
        ex := assessment.cbt_new_exam('GST', off, 'Check CBT', NULL, 30, 0, 'FIXED', false, false, 50, 1, 'STANDARD', 'REMOTE', 1, 'TERMINATE', 'CONTINUE', now() - interval '1 minute', now() + interval '2 hours');
        r_unpublished := split_part(assessment.cbt_eligibility(ex.id, st), ':', 1);
        BEGIN
            PERFORM assessment.cbt_exam_action(ex.id, 'publish', NULL);
        EXCEPTION WHEN check_violation THEN r_publish_empty := split_part(SQLERRM, ':', 1); END;
        INSERT INTO assessment.cbt_exam_question (exam_id, question_id, ordinal) VALUES (ex.id, q1, 1), (ex.id, q2, 2), (ex.id, q3, 3);
        PERFORM assessment.cbt_exam_action(ex.id, 'publish', NULL);
        SELECT assessment.cbt_live_state(e) INTO v_live FROM assessment.cbt_exam e WHERE e.id = ex.id;
        r_unregistered := split_part(assessment.cbt_eligibility(ex.id, st), ':', 1);
        reg := registration.student_draft(st, '9995/9996', 1);
        PERFORM registration.student_choose(reg, ARRAY[off]);
        UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE id = reg;
        PERFORM finance.state_gst_fee('9995/9996', 5000, NULL, NULL, NULL, NULL, current_date, NULL, who, 'bursar');
        r_unpaid := split_part(assessment.cbt_eligibility(ex.id, st), ':', 1);
        ref := finance.new_gst_reference(st, '9995/9996');
        PERFORM finance.confirm_payment(ref, 'CARD', 'check');
        r_paid := coalesce(assessment.cbt_eligibility(ex.id, st), 'ELIGIBLE');
        -- the attempt: started, opened again (the token rotates, the second sign-in is on the record), the old screen refused
        PERFORM set_config('moaum.actor_id', st::text, true);
        PERFORM set_config('moaum.actor_office', 'student', true);
        a := assessment.cbt_start(ex.id, st, '10.0.0.1', 'check');
        tok1 := a.token;
        a2 := assessment.cbt_start(ex.id, st, '10.0.0.2', 'check');
        tok2 := a2.token;
        BEGIN
            PERFORM assessment.cbt_touch(a.id, tok1);
        EXCEPTION WHEN check_violation THEN r_old_token := split_part(SQLERRM, ':', 1); END;
        -- answers: two right, one wrong; one violation over the limit of one (the second sign-in counted) terminates and scores at once
        PERFORM assessment.cbt_save_answers(a.id, tok2, jsonb_build_array(jsonb_build_object('q', q1, 'a', jsonb_build_array(2)), jsonb_build_object('q', q2, 'a', jsonb_build_array(0)), jsonb_build_object('q', q3, 'a', jsonb_build_array(1))));
        ev := assessment.cbt_record_events(a.id, tok2, '[{"kind":"TAB_SWITCH"}]'::jsonb, '10.0.0.2');
        SELECT status, score, percentage, grade, passed INTO v_status, v_score, v_pct, v_grade, v_passed FROM assessment.cbt_attempt WHERE id = a.id;
        SELECT count(*) INTO v_events FROM assessment.cbt_event WHERE attempt_id = a.id AND kind IN ('STARTED', 'MULTIPLE_LOGIN', 'SESSION_REPLACED', 'TAB_SWITCH', 'TERMINATED');
        -- finalised once: a second finalisation changes nothing
        PERFORM assessment.cbt_finalize(a.id, 'SUBMITTED', 'again');
        SELECT score INTO v_again FROM assessment.cbt_attempt WHERE id = a.id;
        SELECT count(*) INTO v_versions FROM assessment.cbt_result WHERE attempt_id = a.id;
        r_limit := split_part(coalesce(assessment.cbt_eligibility(ex.id, st), 'ELIGIBLE'), ':', 1);
        -- the office: results hidden from the student until published; an amendment is a version with its reason
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'gst', true);
        SELECT x.percentage INTO v_student_hidden FROM assessment.cbt_student_exams(st, '9995/9996') x WHERE x.exam_id = ex.id;
        PERFORM assessment.cbt_exam_action(ex.id, 'close', NULL);
        PERFORM assessment.cbt_exam_action(ex.id, 'complete', NULL);
        PERFORM assessment.cbt_results_action(ex.id, 'review');
        r := assessment.cbt_amend_result(a.id, 2, 'SCORED', 'check: a key corrected');
        PERFORM assessment.cbt_results_action(ex.id, 'approve');
        PERFORM assessment.cbt_results_action(ex.id, 'publish');
        SELECT x.results_state INTO v_results FROM assessment.cbt_exam x WHERE x.id = ex.id;
        SELECT x.percentage INTO v_student_sees FROM assessment.cbt_student_exams(st, '9995/9996') x WHERE x.exam_id = ex.id;
        -- the clock: an attempt left past its end is finalised by the sweep
        UPDATE assessment.cbt_exam SET state = 'PUBLISHED', ends_at = now() + interval '1 hour', attempt_limit = 2 WHERE id = ex.id;
        PERFORM set_config('moaum.actor_id', st::text, true);
        PERFORM set_config('moaum.actor_office', 'student', true);
        a2 := assessment.cbt_start(ex.id, st, '10.0.0.1', 'check');
        UPDATE assessment.cbt_attempt SET ends_at = now() - interval '1 minute' WHERE id = a2.id;
        v_sweep := assessment.cbt_sweep();
        SELECT status INTO v_sweep_status FROM assessment.cbt_attempt WHERE id = a2.id;
        RAISE EXCEPTION 'the V322 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A CBT attempt is the server''s: not eligible unpublished, the paper refused empty, refused unregistered, held on the GST fee and freed by the confirmed payment; a second sign-in rotates the token and the old screen is refused; the attempt limit holds',
        coalesce(v_key_leak = 0 AND r_unpublished = 'CBT_EXAM_NOT_OPEN' AND r_publish_empty = 'CBT_PAPER_EMPTY' AND v_live = 'OPEN' AND r_unregistered = 'CBT_COURSE_NOT_REGISTERED'
                 AND r_unpaid = 'GST_PAYMENT_REQUIRED' AND r_paid = 'ELIGIBLE' AND tok1 <> tok2 AND r_old_token = 'CBT_SESSION_REPLACED' AND r_limit = 'CBT_ATTEMPT_LIMIT', false),
        format('leak=%s unpublished=%s empty=%s live=%s unreg=%s unpaid=%s paid=%s rotated=%s old=%s limit=%s', v_key_leak, r_unpublished, r_publish_empty, v_live, r_unregistered, r_unpaid, r_paid, tok1 <> tok2, r_old_token, r_limit));
    PERFORM pg_temp.assert('The score is one transaction and never twice: the violation policy terminates over the limit and scores at once (2 of 4, 50%, C, passed at the pass mark), the events are on the record, a second finalisation changes nothing; the result is hidden from the student until published, an amendment is version 2 with its reason, and the sweep finalises an attempt past its end',
        coalesce(v_status = 'TERMINATED' AND v_score = 2 AND v_pct = 50 AND v_grade = 'C' AND v_passed AND v_events = 5 AND v_again = 2 AND v_versions = 1 AND r.version = 2 AND r.score = 2
                 AND v_student_hidden IS NULL AND v_results = 'PUBLISHED' AND v_student_sees = 50 AND v_sweep >= 1 AND v_sweep_status = 'TIME_EXPIRED', false),
        format('status=%s score=%s pct=%s grade=%s passed=%s events=%s again=%s versions=%s amended=%s hidden=%s results=%s sees=%s sweep=%s/%s', v_status, v_score, v_pct, v_grade, v_passed, v_events, v_again, v_versions, r.version, v_student_hidden, v_results, v_student_sees, v_sweep, v_sweep_status));
END $$;

-- ── 169-170. V323: an old-portal GST payment is staged once, matched by strong identifiers only, judged against THAT session's fee and the ledger,
--                   written to the one ledger on apply with its old reference and date, never twice; the student then reads PAID from the old portal ──
DO $$
DECLARE who uuid := gen_random_uuid(); sa uuid := gen_random_uuid(); sb uuid := gen_random_uuid(); sc uuid := gen_random_uuid(); imp uuid; r record; st record;
        v_matched int; v_validated int; v_tx1 text; v_tx2 text; v_tx3 text; v_tx4 text; v_tx5 text; v_tx6 text; v_dup_in_file int; v_before text; v_after text; v_source text; v_legacy_ref text;
        v_paid_at date; v_gate text; v_again int; v_ledger int; v_prev text; v_written_once text; v_steal text; v_sum record; v_relabel text; v_purpose text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '9993/9994', date '9993-10-01', date '9994-08-31') ON CONFLICT (name) DO NOTHING;
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '9992/9993', date '9992-10-01', date '9993-08-31') ON CONFLICT (name) DO NOTHING;
        PERFORM finance.state_gst_fee('9992/9993', 15000, NULL, NULL, NULL, NULL, current_date, NULL, who, 'bursar');
        PERFORM finance.state_gst_fee('9993/9994', 20000, NULL, NULL, NULL, NULL, current_date, NULL, who, 'bursar');
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
        SELECT 'GST 993', 'Check Legacy GST', 2, 1, 100, p.dept_code, 'GST', 'LIVE' FROM ref.programme p WHERE p.code = 'C00023';
        INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('GST 993', 'C00023', 100, 'GST');
        INSERT INTO people.student (id, admission_no, matric_no, jamb_reg_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
            (sa, 'MOAUM/ADM/93/000001', 'MOAUM/CHK/93/0001', '93000001ZA', 'ZZCHKLEGA', 'Invented', 'C00023', 'UTME', '9993/9994', 100, 100, 'ACTIVE', now()),
            (sb, 'MOAUM/ADM/93/000002', 'MOAUM/CHK/93/0002', NULL, 'ZZCHKLEGB', 'Invented', 'C00023', 'UTME', '9993/9994', 100, 100, 'ACTIVE', now()),
            (sc, 'MOAUM/ADM/93/000003', 'MOAUM/CHK/93/0003', NULL, 'ZZCHKLEGC', 'Invented', 'C00023', 'UTME', '9993/9994', 100, 100, 'ACTIVE', now());
        -- C's money already on the ledger as school fees from the Old Fees History import
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (sc, '9993/9994', 'MOAUM-LEG-CHK930003-9993-9994', 'School fees (legacy)', 20000, '9993-09-16', '9993-09-16', who, 'Legacy', 'LEG-MOAUM-LEG-CHK930003-9993-9994', 'Imported from the old portal');
        SELECT state INTO v_before FROM finance.gst_entitlement(sa, '9993/9994');
        imp := (finance.legacy_gst_new_import('old.xlsx', '9993/9994', 'check')).id;
        SELECT already_staged INTO v_dup_in_file FROM finance.legacy_gst_stage(imp, jsonb_build_array(
            jsonb_build_object('transactionId', 'CHK-TX1', 'reference', 'CHK-OLD-1', 'matric', 'MOAUM/CHK/93/0001', 'jamb', '93000001ZA', 'paymentType', 'GST PAYMENT', 'amount', '20,000.00', 'paidAt', '15/09/9993', 'session', '9993/9994', 'status', 'SUCCESS'),
            jsonb_build_object('transactionId', 'CHK-TX2', 'reference', 'CHK-OLD-2', 'matric', 'MOAUM/CHK/93/0002', 'paymentType', 'GST', 'amount', '20000', 'paidAt', '9993-09-16', 'session', '9993/9994', 'status', 'FAILED'),
            jsonb_build_object('transactionId', 'CHK-TX3', 'reference', 'CHK-OLD-3', 'matric', 'MOAUM/CHK/93/0002', 'paymentType', 'GST', 'amount', '20000', 'paidAt', '9993-09-16', 'session', '9993/9994', 'status', 'REFUNDED'),
            jsonb_build_object('transactionId', 'CHK-TX4', 'reference', 'CHK-OLD-4', 'matric', 'MOAUM/CHK/93/0001', 'paymentType', 'GST', 'amount', '15000', 'paidAt', '9992-10-02', 'session', '9992/9993', 'status', 'PAID'),
            jsonb_build_object('transactionId', 'CHK-TX5', 'reference', 'CHK-OLD-5', 'matric', 'MOAUM/CHK/93/0003', 'paymentType', 'General Studies', 'amount', '20000', 'paidAt', '9993-09-16', 'session', '9993/9994', 'status', 'SUCCESS'),
            jsonb_build_object('transactionId', 'CHK-TX6', 'reference', 'CHK-OLD-6', 'matric', 'MOAUM/CHK/93/0099', 'name', 'ZZCHKLEGB Invented', 'paymentType', 'GST', 'amount', '20000', 'session', '9993/9994', 'status', 'SUCCESS'),
            jsonb_build_object('transactionId', 'CHK-TX1', 'reference', 'CHK-OLD-1', 'matric', 'MOAUM/CHK/93/0001', 'paymentType', 'GST', 'amount', '20000', 'session', '9993/9994', 'status', 'SUCCESS')));
        v_matched := finance.legacy_gst_match(imp);
        v_validated := finance.legacy_gst_validate(imp);
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') || '/' || coalesce(rc.match_method, '-') || '/' || coalesce(rc.fee_amount::text, '-') INTO v_tx1 FROM finance.legacy_gst_payment p JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = p.id WHERE p.source_transaction_id = 'CHK-TX1';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') INTO v_tx2 FROM finance.legacy_gst_payment p JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = p.id WHERE p.source_transaction_id = 'CHK-TX2';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') INTO v_tx3 FROM finance.legacy_gst_payment p JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = p.id WHERE p.source_transaction_id = 'CHK-TX3';
        SELECT rc.status || '/' || coalesce(rc.fee_amount::text, '-') INTO v_tx4 FROM finance.legacy_gst_payment p JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = p.id WHERE p.source_transaction_id = 'CHK-TX4';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') INTO v_tx5 FROM finance.legacy_gst_payment p JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = p.id WHERE p.source_transaction_id = 'CHK-TX5';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') || '/' || jsonb_array_length(coalesce(rc.candidates, '[]')) INTO v_tx6 FROM finance.legacy_gst_payment p JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = p.id WHERE p.source_transaction_id = 'CHK-TX6';
        BEGIN
            UPDATE finance.legacy_gst_payment SET amount = 1 WHERE source_transaction_id = 'CHK-TX1';
            v_written_once := 'allowed';
        EXCEPTION WHEN check_violation THEN v_written_once := split_part(SQLERRM, ':', 1); END;
        -- applied: A reads PAID from the old portal, with the old reference and the old date; the gate opens; last session's payment stands for last session; twice changes nothing
        SELECT reconciled INTO v_again FROM finance.legacy_gst_apply(imp);
        SELECT state, source, legacy_reference, paid_at::date INTO v_after, v_source, v_legacy_ref, v_paid_at FROM finance.gst_entitlement(sa, '9993/9994');
        SELECT state INTO v_prev FROM finance.gst_entitlement(sa, '9992/9993');
        v_gate := registration.gst_gate(sa, '9993/9994', 'GST 993');
        SELECT reconciled INTO v_ledger FROM finance.legacy_gst_apply(imp);
        SELECT count(*) INTO v_ledger FROM finance.payment_reference WHERE student_id = sa AND purpose LIKE 'GST fee %' AND confirmed_at IS NOT NULL;
        -- the officer: a row whose number names A cannot be moved onto B; C's row is relabelled from the school-fees row, one ledger row not two
        BEGIN
            PERFORM finance.legacy_gst_resolve((SELECT id FROM finance.legacy_gst_payment WHERE source_transaction_id = 'CHK-TX2'), 'MATCH', sa, 'guessing');
            v_steal := 'allowed';
        EXCEPTION WHEN check_violation THEN v_steal := split_part(SQLERRM, ':', 1); END;
        SELECT status INTO v_relabel FROM finance.legacy_gst_resolve((SELECT id FROM finance.legacy_gst_payment WHERE source_transaction_id = 'CHK-TX5'), 'RELABEL', NULL, 'the narration says GST');
        SELECT purpose INTO v_purpose FROM finance.payment_reference WHERE reference = 'MOAUM-LEG-CHK930003-9993-9994';
        SELECT * INTO v_sum FROM finance.legacy_gst_summary(imp, NULL);
        RAISE EXCEPTION 'the V323 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('An old-portal GST payment is staged once (the file''s repeat is counted, not staged), matched by the matriculation number at high confidence, judged against THAT session''s fee (15,000 last session, 20,000 this one), the failed and the refunded rejected, the same money as school fees held for review, a row nobody''s number carries left unmatched with name suggestions only, and the raw row written once',
        coalesce(v_dup_in_file = 1 AND v_matched = 6 AND v_tx1 = 'MATCHED/-/MATRIC_NO/20000.00' AND v_tx2 = 'REJECTED/PAYMENT_FAILED' AND v_tx3 = 'REJECTED/PAYMENT_REFUNDED'
                 AND v_tx4 = 'MATCHED/15000.00' AND v_tx5 = 'REQUIRES_REVIEW/POSSIBLE_RELABEL' AND v_tx6 = 'UNMATCHED/STUDENT_NOT_FOUND/1' AND v_written_once = 'LEGACY_PAYMENT_WRITTEN_ONCE', false),
        format('dup=%s matched=%s tx1=%s tx2=%s tx3=%s tx4=%s tx5=%s tx6=%s once=%s', v_dup_in_file, v_matched, v_tx1, v_tx2, v_tx3, v_tx4, v_tx5, v_tx6, v_written_once));
    PERFORM pg_temp.assert('Applied, the student reads PAID from the old portal with the old reference and the old date, the registration gate opens, last session''s payment stands for last session, a second apply writes nothing, a payment is never moved onto a student its number does not name, and the school-fees row is relabelled rather than doubled',
        coalesce(v_before = 'NOT_PAID' AND v_again = 2 AND v_after = 'PAID' AND v_source = 'LEGACY_PORTAL' AND v_legacy_ref = 'CHK-OLD-1' AND v_paid_at = date '9993-09-15' AND v_gate IS NULL AND v_prev = 'PAID'
                 AND v_ledger = 2 AND v_steal = 'LEGACY_IDENTIFIER_CONFLICT' AND v_relabel = 'RECONCILED' AND v_purpose = 'GST fee 9993/9994' AND v_sum.reconciled = 3 AND v_sum.rejected = 2 AND v_sum.unmatched = 1, false),
        format('before=%s applied=%s after=%s source=%s ref=%s paid=%s gate=%s prev=%s ledger=%s steal=%s relabel=%s purpose=%s sum=%s/%s/%s', v_before, v_again, v_after, v_source, v_legacy_ref, v_paid_at, v_gate, v_prev, v_ledger, v_steal, v_relabel, v_purpose, v_sum.reconciled, v_sum.rejected, v_sum.unmatched));
END $$;

-- ── 171. V324: a multiple-select question is marked by the examination's rule — all or nothing, or partial credit that never goes below zero ──
DO $$
DECLARE k int[] := ARRAY[1, 3];
BEGIN
    PERFORM pg_temp.assert('A multiple-select question earns its marks for exactly the key; with partial credit each right option earns a share and each wrong one costs a share, never below zero, and select-everything earns nothing; a single-answer question is never partial',
        assessment.cbt_marks_for('MULTI', k, ARRAY[1, 3], 2, false) = 2 AND assessment.cbt_marks_for('MULTI', k, ARRAY[1], 2, false) = 0
        AND assessment.cbt_marks_for('MULTI', k, ARRAY[1], 2, true) = 1 AND assessment.cbt_marks_for('MULTI', k, ARRAY[1, 2], 2, true) = 0
        AND assessment.cbt_marks_for('MULTI', k, ARRAY[0, 1, 2, 3], 2, true) = 0 AND assessment.cbt_marks_for('MULTI', ARRAY[0, 1, 2], ARRAY[0, 1], 3, true) = 2
        AND assessment.cbt_marks_for('MCQ', ARRAY[2], ARRAY[1], 1, true) = 0 AND assessment.cbt_marks_for('MCQ', ARRAY[2], ARRAY[2], 1, true) = 1
        AND assessment.cbt_marks_for('MULTI', k, NULL, 2, true) = 0,
        format('exact=%s off=%s half=%s mixed=%s all=%s two-of-three=%s mcq=%s/%s blank=%s',
               assessment.cbt_marks_for('MULTI', k, ARRAY[1, 3], 2, false), assessment.cbt_marks_for('MULTI', k, ARRAY[1], 2, false), assessment.cbt_marks_for('MULTI', k, ARRAY[1], 2, true),
               assessment.cbt_marks_for('MULTI', k, ARRAY[1, 2], 2, true), assessment.cbt_marks_for('MULTI', k, ARRAY[0, 1, 2, 3], 2, true), assessment.cbt_marks_for('MULTI', ARRAY[0, 1, 2], ARRAY[0, 1], 3, true),
               assessment.cbt_marks_for('MCQ', ARRAY[2], ARRAY[1], 1, true), assessment.cbt_marks_for('MCQ', ARRAY[2], ARRAY[2], 1, true), assessment.cbt_marks_for('MULTI', k, NULL, 2, true)));
END $$;

-- ── 172. V325: a bounded office is granted with its bound, and a desk explains the scope it reads ──
DO $$
DECLARE who uuid := gen_random_uuid(); r_kind text; r_blank text; s0 record; s1 record; s2 record; s3 record; v_live text := 'unset';
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        INSERT INTO iam.person (id, surname, given_names, staff_number) VALUES (who, 'CHECKBOUND', 'Invented', 'P-V325');
        -- a Head of Department over the University, and one over a department with none chosen: refused, the remedy in the hint
        BEGIN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), who, 'hod', 'institution', NULL, 'check', who, current_date);
        EXCEPTION WHEN check_violation THEN r_kind := split_part(SQLERRM, ':', 1); END;
        BEGIN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), who, 'hod', 'department', '  ', 'check', who, current_date);
        EXCEPTION WHEN check_violation THEN r_blank := split_part(SQLERRM, ':', 1); END;
        -- no live grant: the state says so
        SELECT * INTO s0 FROM iam.office_scope_state(who, 'hod');
        -- granted over a department by its name: the code is stored and the desk reads it through the grant
        INSERT INTO ref.department (code, name, faculty_code) VALUES ('ZZV325', 'CHECK DEPARTMENT V325', 'SC');
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
        VALUES (gen_random_uuid(), who, 'hod', 'department', 'check department v325', 'check', who, current_date);
        SELECT * INTO s1 FROM iam.office_scope_state(who, 'hod');
        -- the department ends: the grant no longer answers, and the state says why
        UPDATE ref.department SET ended_on = current_date - 1 WHERE code = 'ZZV325';
        SELECT * INTO s2 FROM iam.office_scope_state(who, 'hod');
        -- a lecturer grant over MTC: the desk reads MTC through it, and still says what is wrong with the office's own grant
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
        VALUES (gen_random_uuid(), who, 'lecturer', 'department', 'MTC', 'check', who, current_date);
        SELECT * INTO s3 FROM iam.office_scope_state(who, 'hod');
        v_live := iam.live_scope_code('department', 'ZZV325');
        RAISE EXCEPTION 'the V325 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A bounded office is granted with its bound, chosen from the register, and a desk explains the scope it reads: no grant, the grant, the grant''s department ended, the lecturer grant answering instead',
        r_kind = 'OFFICE_SCOPE_REQUIRED' AND r_blank = 'OFFICE_SCOPE_REQUIRED'
        AND s0.bound_kind = 'department' AND s0.reason = 'NO_LIVE_GRANT' AND s0.resolved_code IS NULL
        AND s1.reason IS NULL AND s1.scope_id = 'ZZV325' AND s1.resolved_code = 'ZZV325' AND s1.source = 'OFFICE_GRANT'
        AND s2.reason = 'SCOPE_ENDED' AND s2.resolved_code IS NULL
        AND s3.reason = 'SCOPE_ENDED' AND s3.resolved_code = 'MTC' AND s3.source = 'LECTURER_GRANT'
        AND v_live IS NULL AND iam.acting_department(who, 'hod') IS NULL,
        format('refused=%s/%s none=%s/%s grant=%s/%s/%s/%s ended=%s/%s lecturer=%s/%s/%s live=%s',
               r_kind, r_blank, s0.reason, s0.resolved_code, s1.reason, s1.scope_id, s1.resolved_code, s1.source,
               s2.reason, s2.resolved_code, s3.reason, s3.resolved_code, s3.source, v_live));
END $$;

-- ── 173. V326: the Old Fees History import reads the old portal's payment item — a GST payment is the GST fee, a semester reads as First/Second, a row filed as school fees before is corrected, not doubled ──
DO $$
DECLARE who uuid := gen_random_uuid(); sd uuid := gen_random_uuid(); res record; again record;
        v_state text; v_source text; v_gst_ref text; v_gst_purpose text; v_school int; v_sems text; v_base_left int; v_other text; v_sem_words text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '9995/9996', date '9995-10-01', date '9996-08-31') ON CONFLICT (name) DO NOTHING;
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (sd, 'MOAUM/ADM/95/000001', 'MOAUM/CHK/95/0001', 'ZZCHKLEGD', 'Invented', 'C00023', 'UTME', '9995/9996', 100, 100, 'ACTIVE', now());
        -- what an earlier upload of the same export left: the GST money as whole-session school fees, because the screen could not read the item
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (sd, '9995/9996', 'MOAUM-LEG-MOAUMCHK950001-9995-9996', 'School fees (legacy)', 4000, '9996-02-01', '9996-02-01', who, 'Legacy', 'LEG-MOAUM-LEG-MOAUMCHK950001-9995-9996', 'Imported from the old portal');
        -- the export, read with its item column
        SELECT * INTO res FROM finance.import_legacy_payments(jsonb_build_array(
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'First',   'amount', '4000',  'purpose', 'GST FEES',           'paidOn', '9996-02-01', 'receiptNo', '2019470000000001', 'channel', 'Interswitch'),
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'First',   'amount', '24510', 'purpose', 'SCHOOL FEES',        'paidOn', '9995-11-10', 'receiptNo', '2019470000000002', 'channel', 'Old Record'),
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'Second',  'amount', '24510', 'purpose', 'SCHOOL FEES',        'paidOn', '9996-03-02', 'receiptNo', '2019470000000003', 'channel', 'Old Record'),
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'Session', 'amount', '2000',  'purpose', 'ADMISSION CHECKING', 'paidOn', '9995-10-03', 'receiptNo', '2019470000000004', 'channel', 'Interswitch'),
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'First',   'amount', '4000',  'purpose', 'GST FEES',           'paidOn', '9996-02-01', 'receiptNo', '2019470000000001', 'channel', 'Interswitch')));   -- the same transaction listed twice
        SELECT state, source INTO v_state, v_source FROM finance.gst_entitlement(sd, '9995/9996');
        SELECT reference, purpose INTO v_gst_ref, v_gst_purpose FROM finance.payment_reference WHERE student_id = sd AND purpose LIKE 'GST fee %' ORDER BY reference LIMIT 1;
        SELECT count(*), string_agg(right(reference, 2), ',' ORDER BY reference) INTO v_school, v_sems FROM finance.payment_reference WHERE student_id = sd AND purpose LIKE 'School fees (legacy)%';
        SELECT count(*) INTO v_base_left FROM finance.payment_reference WHERE reference = 'MOAUM-LEG-MOAUMCHK950001-9995-9996';
        SELECT purpose INTO v_other FROM finance.payment_reference WHERE student_id = sd AND reference LIKE '%-ADMISSIONCHECKING';
        -- the same export again: nothing doubles, nothing is lost
        SELECT * INTO again FROM finance.import_legacy_payments(jsonb_build_array(
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'First',  'amount', '4000',  'purpose', 'GST FEES',    'paidOn', '9996-02-01'),
            jsonb_build_object('matric', 'MOAUM/CHK/95/0001', 'session', '9995/9996', 'semester', 'Second', 'amount', '24510', 'purpose', 'SCHOOL FEES', 'paidOn', '9996-03-02')));
        v_sem_words := finance.legacy_semester('First') || '/' || finance.legacy_semester('2nd') || '/' || finance.legacy_semester('Semester 1') || '/' || coalesce(finance.legacy_semester('Session')::text, 'whole') || '/' || coalesce(finance.legacy_semester('')::text, 'whole');
        RAISE EXCEPTION 'the V326 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The Old Fees History import reads the payment item: a GST FEES row is the GST fee the gate counts (the row filed as school fees before is relabelled, not doubled), First/Second semesters each keep their school fees, another item is its own purpose, and the export loaded twice changes nothing',
        v_state = 'PAID' AND v_source = 'LEGACY_PORTAL'
        AND v_gst_ref = 'MOAUM-LEG-MOAUMCHK950001-9995-9996-S1-GST' AND v_gst_purpose = 'GST fee 9995/9996'
        AND v_school = 2 AND v_sems = 'S1,S2' AND v_base_left = 0
        AND v_other = 'ADMISSION CHECKING (legacy)'
        AND res.rows = 5 AND res.cleared = 3 AND res.corrected = 1 AND res.duplicates = 1
        AND again.cleared = 0 AND again.corrected = 0 AND again.duplicates = 2
        AND v_sem_words = '1/2/1/whole/whole',
        format('state=%s/%s gst=%s/%s school=%s/%s base_left=%s other=%s first=%s/%s/%s/%s again=%s/%s/%s sems=%s',
               v_state, v_source, v_gst_ref, v_gst_purpose, v_school, v_sems, v_base_left, v_other,
               res.cleared, res.corrected, res.duplicates, res.rows, again.cleared, again.corrected, again.duplicates, v_sem_words));
END $$;

-- ── 174. V327: the wallet keeps every naira to its source — a top-up only for the shortfall, the charge settled source by source, a refund only of the Fund's money that arrived after the fees were paid, never a grant ──
DO $$
DECLARE s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); s3 uuid := gen_random_uuid(); who uuid := gen_random_uuid(); two uuid := gen_random_uuid(); three uuid := gen_random_uuid();
        e1 record; e2 record; e3 record; r_above text; r_none text; r_src text; r_nosrc text; r_over text; ref1 text; ref2 text; v_exp1 boolean; v_apply text; pos record;
        v_nel_applied numeric; v_self_applied numeric; v_avail numeric; w record; wd finance.wallet_withdrawal; v_nel_after numeric; v_grant numeric; v_bal numeric; v_refunded numeric; v_note text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
            (s1, 'MOAUM/ADM/99/990174', 'MOAUM/CHK/99/0174', 'CHECKSOURCE', 'Invented One', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now()),
            (s2, 'MOAUM/ADM/99/990175', 'MOAUM/CHK/99/0175', 'CHECKSOURCE', 'Invented Two', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now()),
            (s3, 'MOAUM/ADM/99/990176', 'MOAUM/CHK/99/0176', 'CHECKSOURCE', 'Invented Three', 'C00023', 'UTME', '9999/0000', 100, 100, 'ACTIVE', now());
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        -- a hand credit of no source is refused
        BEGIN PERFORM finance.credit_wallet(s3, '9999/0000', 10000, 'a credit from nowhere'); EXCEPTION WHEN check_violation THEN r_nosrc := split_part(SQLERRM, ':', 1); END;
        -- s1: the Fund remits 60,000 against a charge of 100,000 — the shortfall is 40,000, and a top-up is for exactly that
        PERFORM finance.credit_wallet(s1, '9999/0000', 60000, 'NELFUND remittance NLF/9999/174', 'NELFUND');
        SELECT * INTO e1 FROM finance.topup_eligibility(s1, '9999/0000');
        PERFORM set_config('moaum.actor_office', 'student', true);
        BEGIN ref1 := finance.wallet_topup_reference(s1, '9999/0000', 50000); EXCEPTION WHEN check_violation THEN r_above := split_part(SQLERRM, ':', 1); END;
        ref1 := finance.wallet_topup_reference(s1, '9999/0000', NULL);
        ref2 := finance.wallet_topup_reference(s1, '9999/0000', 40000);   -- a second request retires the first
        SELECT expires_at <= now() INTO v_exp1 FROM finance.payment_reference WHERE reference = ref1;
        SELECT note INTO v_note FROM finance.payment_reference WHERE reference = ref2;
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        PERFORM finance.confirm_payment(ref2, 'WebPAY', 'check: the top-up paid');
        SELECT * INTO e2 FROM finance.topup_eligibility(s1, '9999/0000');
        PERFORM set_config('moaum.actor_office', 'student', true);
        BEGIN PERFORM finance.wallet_topup_reference(s1, '9999/0000', 1000); EXCEPTION WHEN check_violation THEN r_none := split_part(SQLERRM, ':', 1); END;
        -- applied: the loan first, then the student's own money; each source's share on its own entry
        v_apply := finance.apply_wallet(s1, '9999/0000', NULL);
        SELECT * INTO pos FROM finance.position(s1, '9999/0000');
        SELECT coalesce(sum(amount) FILTER (WHERE source_code = 'NELFUND'), 0), coalesce(sum(amount) FILTER (WHERE source_code = 'SELF'), 0)
          INTO v_nel_applied, v_self_applied FROM finance.wallet_entry WHERE student_id = s1 AND kind = 'APPLIED' AND reference = v_apply;
        SELECT coalesce(sum(available), 0) INTO v_avail FROM finance.wallet_balances(s1);
        SELECT * INTO e3 FROM finance.topup_eligibility(s1, '9998/9999');
        -- s2 pays the whole charge personally; then the Fund's 100,000 lands, and a 20,000 scholarship with it
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        PERFORM finance.confirm_payment(finance.new_reference(s2, '9999/0000', 100000, NULL), 'WebPAY', 'check: paid personally');
        PERFORM finance.credit_wallet(s2, '9999/0000', 100000, 'NELFUND remittance NLF/9999/175', 'NELFUND');
        PERFORM finance.credit_wallet(s2, '9999/0000', 20000, 'State scholarship', 'SCHOLARSHIP');
        SELECT * INTO w FROM finance.withdrawal_eligibility(s2, '9999/0000');
        PERFORM set_config('moaum.actor_office', 'student', true);
        BEGIN PERFORM finance.request_withdrawal(s2, '9999/0000', 150000, 'Check Bank', '0123456789', 'CHECKSOURCE INVENTED TWO', 'NELFUND'); EXCEPTION WHEN check_violation THEN r_over := split_part(SQLERRM, ':', 1); END;
        BEGIN PERFORM finance.request_withdrawal(s2, '9999/0000', 20000, 'Check Bank', '0123456789', 'CHECKSOURCE INVENTED TWO', 'SCHOLARSHIP'); EXCEPTION WHEN check_violation THEN r_src := split_part(SQLERRM, ':', 1); END;
        wd := finance.request_withdrawal(s2, '9999/0000', NULL, 'Check Bank', '0123456789', 'CHECKSOURCE INVENTED TWO', NULL);
        PERFORM set_config('moaum.actor_id', two::text, true);
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        wd := finance.approve_withdrawal(wd.id);
        PERFORM set_config('moaum.actor_id', three::text, true);
        wd := finance.pay_withdrawal(wd.id, 'TRF-CHECK-174');
        SELECT coalesce(sum(available) FILTER (WHERE source_code = 'NELFUND'), 0), coalesce(sum(refunded) FILTER (WHERE source_code = 'NELFUND'), 0), coalesce(sum(available) FILTER (WHERE source_code = 'SCHOLARSHIP'), 0)
          INTO v_nel_after, v_refunded, v_grant FROM finance.wallet_balances(s2);
        v_bal := finance.wallet_balance(s2);
        RAISE EXCEPTION 'the V327 wallet check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The wallet keeps every naira to its source: a top-up is refused above the shortfall and when nothing is short, an earlier top-up reference is retired, the charge settles loan first then own money on separate entries, a credit of no source is refused, and a refund is of the Fund''s money that arrived after the fees were paid — never the scholarship',
        r_nosrc = 'WALLET_SOURCE_REQUIRED'
        AND e1.allowed AND e1.reason = 'ALLOWED' AND e1.due = 100000 AND e1.outstanding = 100000 AND e1.wallet_available = 60000 AND e1.nelfund_available = 60000 AND e1.shortfall = 40000 AND e1.max_topup = 40000
        AND r_above = 'WALLET_TOPUP_ABOVE_SHORTFALL' AND ref1 LIKE 'MOAUM-FEE-%' AND v_exp1 AND v_note LIKE 'Shortfall top-up: fees 100000%'
        AND NOT e2.allowed AND e2.reason = 'NO_SHORTFALL' AND e2.wallet_available = 100000 AND r_none = 'WALLET_TOPUP_NOT_REQUIRED'
        AND pos.paid = 100000 AND pos.paid_in_full AND v_nel_applied = 60000 AND v_self_applied = 40000 AND v_avail = 0
        AND NOT e3.allowed AND e3.reason = 'NO_CHARGE_STATED'
        AND w.eligible AND w.nelfund_refundable = 100000 AND w.self_refundable = 0 AND w.grant_held = 20000 AND w.nelfund_after_settlement
        AND r_over = 'WALLET_REFUND_ABOVE_REFUNDABLE' AND r_src = 'WALLET_REFUND_SOURCE'
        AND wd.state = 'PAID' AND wd.source_code = 'NELFUND' AND wd.amount = 100000
        AND v_nel_after = 0 AND v_refunded = 100000 AND v_grant = 20000 AND v_bal = 20000,
        format('nosrc=%s e1=%s/%s/%s/%s/%s above=%s exp1=%s note=%s e2=%s/%s none=%s pos=%s/%s applied=%s/%s avail=%s e3=%s w=%s/%s/%s/%s/%s over=%s src=%s wd=%s/%s/%s after=%s/%s/%s bal=%s',
               r_nosrc, e1.reason, e1.due, e1.wallet_available, e1.shortfall, e1.max_topup, r_above, v_exp1, left(v_note, 40), e2.reason, e2.wallet_available, r_none, pos.paid, pos.paid_in_full,
               v_nel_applied, v_self_applied, v_avail, e3.reason, w.eligible, w.nelfund_refundable, w.self_refundable, w.grant_held, w.nelfund_after_settlement, r_over, r_src,
               wd.state, wd.source_code, wd.amount, v_nel_after, v_refunded, v_grant, v_bal));
END $$;

-- ── 175. V327: the old portal's NELFUND payments are staged once, matched by identifiers never by name, posted to the wallet once for the session they name, and what cannot be reconciled waits for an officer ──
DO $$
DECLARE s5 uuid := gen_random_uuid(); s6 uuid := gen_random_uuid(); s7 uuid := gen_random_uuid(); who uuid := gen_random_uuid(); imp uuid; imp2 uuid; st record; st2 record; ap record; ap2 record;
        r1 text; r2 text; r3 text; r4 text; r5 text; v_cands int; v_credited numeric; v_session text; v_origin text; v_legacy_ref text; r_conflict text; rc4 finance.legacy_nelfund_reconciliation; ap3 record; v_s6 numeric; v_summary record;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '9997/9998', date '9997-10-01', date '9998-08-31') ON CONFLICT (name) DO NOTHING;
        INSERT INTO people.student (id, admission_no, matric_no, jamb_reg_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
            (s5, 'MOAUM/ADM/97/000005', 'MOAUM/CHK/97/0005', '97000005ZB', 'ZZCHKNELA', 'Invented', 'C00023', 'UTME', '9997/9998', 100, 100, 'ACTIVE', now()),
            (s6, 'MOAUM/ADM/97/000006', 'MOAUM/CHK/97/0006', '97000006ZB', 'ZZCHKNELB', 'Invented', 'C00023', 'UTME', '9997/9998', 100, 100, 'ACTIVE', now()),
            (s7, 'MOAUM/ADM/97/000007', 'MOAUM/CHK/97/0007', '97000007ZB', 'ZZCHKNELC', 'Invented', 'C00023', 'UTME', '9997/9998', 100, 100, 'ACTIVE', now());
        imp := (finance.legacy_nelfund_new_import('nelfund-old.xlsx', '9997/9998', 'check')).id;
        SELECT * INTO st FROM finance.legacy_nelfund_stage(imp, jsonb_build_array(
            jsonb_build_object('reference', 'NEL-1', 'matric', 'MOAUM/CHK/97/0005', 'amount', '150,000.00', 'paidAt', '20/11/9997', 'session', '9997/9998', 'status', 'SUCCESS'),
            jsonb_build_object('reference', 'NEL-2', 'matric', 'MOAUM/CHK/97/0005', 'amount', '50000', 'paidAt', '9997-12-01', 'session', '9997/9998', 'status', 'FAILED'),
            jsonb_build_object('reference', 'NEL-3', 'matric', 'MOAUM/CHK/97/0006', 'jamb', '97000007ZB', 'amount', '80000', 'paidAt', '9997-12-02', 'session', '9997/9998', 'status', 'PAID'),
            jsonb_build_object('reference', 'NEL-4', 'name', 'ZZCHKNELB Invented', 'amount', '90000', 'paidAt', '9997-12-03', 'session', '9997/9998', 'status', 'SUCCESS'),
            jsonb_build_object('reference', 'NEL-5', 'matric', 'MOAUM/CHK/97/0005', 'amount', '70000', 'paidAt', '9998-03-01', 'status', 'SUCCESS'),
            jsonb_build_object('reference', 'NEL-1', 'matric', 'MOAUM/CHK/97/0005', 'amount', '150000', 'session', '9997/9998', 'status', 'SUCCESS')));
        PERFORM finance.legacy_nelfund_match(imp);
        PERFORM finance.legacy_nelfund_validate(imp);
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') || '/' || coalesce(rc.match_method, '-') INTO r1 FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-1';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') INTO r2 FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-2';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') INTO r3 FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-3';
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-'), jsonb_array_length(coalesce(rc.candidates, '[]')) INTO r4, v_cands FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-4';
        SELECT rc.status || '/' || coalesce(p.session, '-') INTO r5 FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-5';
        SELECT * INTO ap FROM finance.legacy_nelfund_apply(imp);
        SELECT * INTO ap2 FROM finance.legacy_nelfund_apply(imp);   -- twice changes nothing
        SELECT rc.status || '/' || coalesce(rc.reason_code, '-') || '/' || coalesce(rc.match_method, '-') INTO r1 FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-1';
        SELECT rc.status || '/' || coalesce(p.session, '-') INTO r5 FROM finance.legacy_nelfund_payment p JOIN finance.legacy_nelfund_reconciliation rc ON rc.payment_id = p.id WHERE p.source_reference = 'NEL-5';
        SELECT coalesce(sum(credited), 0) INTO v_credited FROM finance.wallet_balances_session(s5, '9997/9998') WHERE source_code = 'NELFUND';
        SELECT e.session, e.origin, e.legacy_reference INTO v_session, v_origin, v_legacy_ref FROM finance.wallet_statement(s5) e WHERE e.legacy_reference = 'NEL-1';
        -- the same file again: nothing is staged twice
        imp2 := (finance.legacy_nelfund_new_import('nelfund-old.xlsx', '9997/9998', 'check again')).id;
        SELECT * INTO st2 FROM finance.legacy_nelfund_stage(imp2, jsonb_build_array(
            jsonb_build_object('reference', 'NEL-1', 'matric', 'MOAUM/CHK/97/0005', 'amount', '150000', 'session', '9997/9998', 'status', 'SUCCESS'),
            jsonb_build_object('reference', 'NEL-5', 'matric', 'MOAUM/CHK/97/0005', 'amount', '70000', 'session', '9997/9998', 'status', 'SUCCESS')));
        -- the officer: the ambiguous row cannot be moved past its identifiers; the name-only row is matched on evidence and then posted
        BEGIN PERFORM finance.legacy_nelfund_resolve((SELECT id FROM finance.legacy_nelfund_payment WHERE source_reference = 'NEL-3'), 'MATCH', s6, 'guessing'); EXCEPTION WHEN check_violation THEN r_conflict := split_part(SQLERRM, ':', 1); END;
        rc4 := finance.legacy_nelfund_resolve((SELECT id FROM finance.legacy_nelfund_payment WHERE source_reference = 'NEL-4'), 'MATCH', s6, 'identity confirmed with the old portal''s receipt in hand');
        SELECT * INTO ap3 FROM finance.legacy_nelfund_apply(imp);
        SELECT coalesce(sum(credited), 0) INTO v_s6 FROM finance.wallet_balances_session(s6, '9997/9998') WHERE source_code = 'NELFUND';
        SELECT * INTO v_summary FROM finance.legacy_nelfund_summary(imp, NULL);
        RAISE EXCEPTION 'the V327 legacy check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('Old-portal NELFUND payments are staged once (the file''s repeat and a second upload stage nothing), matched by identifiers only (a name is a suggestion, two students a review), a failed payment is never credited, a session is read from the row or its date and kept on the credit, posting is once, and an officer resolves on evidence but never past the identifiers',
        st.total_rows = 6 AND st.staged = 5 AND st.already_staged = 1
        AND r1 = 'POSTED/-/MATRIC_NO' AND r2 = 'REJECTED/PAYMENT_FAILED' AND r3 = 'REQUIRES_REVIEW/AMBIGUOUS_STUDENT' AND r4 = 'UNMATCHED/STUDENT_NOT_FOUND' AND v_cands = 1 AND r5 = 'POSTED/9997/9998'
        AND ap.posted = 2 AND ap.amount = 220000 AND ap2.posted = 0 AND v_credited = 220000 AND v_session = '9997/9998' AND v_origin = 'OLD_PORTAL' AND v_legacy_ref = 'NEL-1'
        AND st2.staged = 0 AND st2.already_staged = 2
        AND r_conflict = 'LEGACY_IDENTIFIER_CONFLICT' AND rc4.status = 'MATCHED' AND rc4.match_method = 'MANUAL' AND ap3.posted = 1 AND v_s6 = 90000
        AND v_summary.posted = 3 AND v_summary.rejected = 1 AND v_summary.requires_review = 1 AND v_summary.amount_posted = 310000,
        format('stage=%s/%s/%s r1=%s r2=%s r3=%s r4=%s/%s r5=%s apply=%s/%s again=%s credited=%s session=%s origin=%s ref=%s stage2=%s/%s conflict=%s rc4=%s/%s ap3=%s s6=%s summary=%s/%s/%s/%s',
               st.total_rows, st.staged, st.already_staged, r1, r2, r3, r4, v_cands, r5, ap.posted, ap.amount, ap2.posted, v_credited, v_session, v_origin, v_legacy_ref, st2.staged, st2.already_staged,
               r_conflict, rc4.status, rc4.match_method, ap3.posted, v_s6, v_summary.posted, v_summary.rejected, v_summary.requires_review, v_summary.amount_posted));
END $$;

-- ── result ────────────────────────────────────────────────────────────────
-- A check that ERRORS never reaches its assert, so counting only failures
-- reports green over an aborted block. The count of checks that actually ran
-- is therefore part of the result.
SELECT CASE
    WHEN (SELECT count(*) FROM ran) <> :EXPECTED
        THEN E'\n=== ' || (SELECT count(*) FROM ran) || ' of ' || :EXPECTED ||
             ' checks RAN — ' || (:EXPECTED - (SELECT count(*) FROM ran)) ||
             ' errored before asserting anything ==='
    WHEN (SELECT count(*) FROM failures) = 0
        THEN E'\n=== FOUNDATION GREEN — ' || :EXPECTED || ' properties, all holding ==='
    ELSE E'\n=== ' || (SELECT count(*) FROM failures) || ' FAILED: ' ||
         (SELECT string_agg(name, '; ') FROM failures) || ' ==='
END;
