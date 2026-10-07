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
\set EXPECTED 200

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
                           n = 39, n || ' offices (37 staff offices incl. the SIWES Coordinator V156, the School of Postgraduate Studies'' Dean and Secretary V201, the College Finance Controller V227, the MBBS Coordinator V250, the ICT Support Agent V251, the External Examiner V254, the Dean of Student Affairs V290, the GST and EPS offices V314, the Head of ICT Support Desk V328 and the JUPEB Office V339; the applicant V021 and the student V026)');
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

-- ── 176. V328: the support desk across the University — a ticket routed to its queue and to the posted agent who covers it, scope enforced, a transfer that never duplicates, an escalation only to the queue's office, a wait ended by the requester's reply, and no ticket left with an agent who is gone ──
DO $$
DECLARE who uuid := gen_random_uuid(); head uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); bur uuid := gen_random_uuid();
        s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); t1 uuid; t2 uuid; t3 uuid; prog text; msg text;
        q1 text; a1 uuid; q2 text; a2 uuid; q3 text; a3 uuid; v_scope text; r_noreason text; q1b text; a1b uuid; n_tickets int; r_office text; st3 text; o3 text;
        r_notoffice text; st3b text; o3b uuid; n_internal int; st2 text; w2 boolean; st2b text; w2b boolean; n_swept int; st2c text; a2c uuid; n_off int; n_c int;
        v_hours numeric; ev text; n_queues int; n_rules int; n_offices int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        SELECT code INTO prog FROM ref.programme ORDER BY code LIMIT 1;
        INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (head, 'MOAUM/CHK/0176', 'CHECKHEAD', 'Desk'), (a, 'MOAUM/CHK/0177', 'CHECKAGENT', 'Faculty'),
               (b, 'MOAUM/CHK/0178', 'CHECKAGENT', 'Global'), (c, 'MOAUM/CHK/0179', 'CHECKAGENT', 'Bursary'), (bur, 'MOAUM/CHK/0180', 'CHECKBURSAR', 'Office');
        INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from) VALUES
            (gen_random_uuid(), head, 'helpdeskhead', 'platform', NULL, 'check', who, current_date),
            (gen_random_uuid(), a, 'ictagent', 'platform', NULL, 'check', who, current_date),
            (gen_random_uuid(), b, 'ictagent', 'platform', NULL, 'check', who, current_date),
            (gen_random_uuid(), c, 'ictagent', 'platform', NULL, 'check', who, current_date),
            (gen_random_uuid(), bur, 'bursar', 'platform', NULL, 'check', who, current_date);
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, assigned_by, reason) VALUES
            (a, 'ICT_SUPPORT', 'FACULTY', 'AC', head, 'check'), (b, 'ICT_SUPPORT', 'GLOBAL', NULL, head, 'check'), (c, 'BURSARY_SUPPORT', 'GLOBAL', NULL, head, 'check');
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (s1, 'MOAUM/ADM/97/970176', 'MOAUM/CHK/20/0176', 'CHECKDESK', 'One', prog, 'UTME', '2020/2021', 100, 300, 'ACTIVE', now()),
               (s2, 'MOAUM/ADM/97/970177', 'MOAUM/CHK/20/0177', 'CHECKDESK', 'Two', prog, 'UTME', '2020/2021', 100, 300, 'ACTIVE', now());
        SELECT count(*) INTO n_queues FROM helpdesk.queue WHERE active;
        SELECT count(*) INTO n_rules FROM helpdesk.routing_rule WHERE active;
        SELECT count(*) INTO n_offices FROM ref.office WHERE code = 'helpdeskhead';

        -- a login problem from the Faculty of Agriculture goes to the ICT Support queue and to the agent posted to that faculty, before the University-wide one
        t1 := helpdesk.submit('STUDENT', s1, 'CHECKDESK, One', 'MOAUM/CHK/20/0176', 'd1@example.edu', '08011111111', 'CSC', 'AC', 'LOGIN', 'Cannot log in', 'The portal says my password is wrong though I reset it.',
                              '{"account_type":"Student","username":"MOAUM/CHK/20/0176","error":"Password refused"}'::jsonb);
        q1 := helpdesk.route(t1);
        SELECT assigned_to INTO a1 FROM helpdesk.ticket WHERE id = t1;
        -- the same problem from another faculty goes to the University-wide agent
        t2 := helpdesk.submit('STUDENT', s2, 'CHECKDESK, Two', 'MOAUM/CHK/20/0177', 'd2@example.edu', '08022222222', 'ENG', 'ES', 'LOGIN', 'Cannot log in either', 'Same problem, another faculty.',
                              '{"account_type":"Student","username":"MOAUM/CHK/20/0177","error":"Password refused"}'::jsonb);
        q2 := helpdesk.route(t2);
        SELECT assigned_to INTO a2 FROM helpdesk.ticket WHERE id = t2;
        -- a payment problem goes to the Bursary's queue
        t3 := helpdesk.submit('STUDENT', s1, 'CHECKDESK, One', 'MOAUM/CHK/20/0176', 'd1@example.edu', '08011111111', 'CSC', 'AC', 'PAYMENT', 'Payment not reflecting', 'I paid on Monday and the portal still says unpaid.',
                              '{"payment_reference":"MOAUM-X","payment_date":"2020-01-01","payment_type":"School fees","amount":"50000"}'::jsonb);
        q3 := helpdesk.route(t3);
        SELECT assigned_to INTO a3 FROM helpdesk.ticket WHERE id = t3;
        -- scope: the faculty agent sees their faculty's ticket, not the other faculty's nor the Bursary's; the Bursary agent the converse; the Head everything
        v_scope := format('%s%s%s%s%s%s', helpdesk.can_view(a, t1), helpdesk.can_view(a, t2), helpdesk.can_view(a, t3), helpdesk.can_view(c, t3), helpdesk.can_view(c, t1),
                          helpdesk.can_view(head, t1) AND helpdesk.can_view(head, t2) AND helpdesk.can_view(head, t3));
        -- a transfer says why, moves the same ticket, and routes it to an agent of the new queue
        BEGIN PERFORM helpdesk.transfer(t1, 'BURSARY_SUPPORT', head, ''); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_noreason := split_part(msg, ':', 1); END;
        PERFORM helpdesk.transfer(t1, 'BURSARY_SUPPORT', head, 'It is a payment problem after all');
        SELECT queue_code, assigned_to INTO q1b, a1b FROM helpdesk.ticket WHERE id = t1;
        SELECT count(*) INTO n_tickets FROM helpdesk.ticket WHERE requester_id = s1 AND category_id = (SELECT id FROM helpdesk.category WHERE code = 'LOGIN');
        -- an escalation goes only to the queue's office or the Director of ICT; the office answers, and only the office
        BEGIN PERFORM helpdesk.escalate_to_office(t3, 'academic', c, 'Please decide'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_office := split_part(msg, ':', 1); END;
        PERFORM helpdesk.escalate_to_office(t3, 'bursar', c, 'The payment is on the bank statement but not the ledger; the Bursary decides');
        SELECT status, escalated_office INTO st3, o3 FROM helpdesk.ticket WHERE id = t3;
        BEGIN PERFORM helpdesk.office_answer(t3, a, 'I am not the Bursar', true); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_notoffice := split_part(msg, ':', 1); END;
        PERFORM helpdesk.office_answer(t3, bur, 'Matched to the ledger by the Bursary; tell the student the receipt is reissued.', true);
        SELECT status, assigned_to INTO st3b, o3b FROM helpdesk.ticket WHERE id = t3;
        SELECT count(*) INTO n_internal FROM helpdesk.ticket_comment WHERE ticket_id = t3 AND internal AND author_name LIKE '%(Bursar)';
        -- waiting on the requester ends with their reply
        PERFORM helpdesk.transition(t2, 'OPENED', 'AGENT', b, 'CHECKAGENT, Global', NULL);
        PERFORM helpdesk.transition(t2, 'IN_PROGRESS', 'AGENT', b, 'CHECKAGENT, Global', NULL);
        PERFORM helpdesk.transition(t2, 'WAITING_FOR_STUDENT', 'AGENT', b, 'CHECKAGENT, Global', 'Send a screenshot of the error');
        SELECT status, waiting_since IS NOT NULL INTO st2, w2 FROM helpdesk.ticket WHERE id = t2;
        PERFORM helpdesk.comment(t2, 'REQUESTER', s2, 'CHECKDESK, Two', false, 'Here is the screenshot, attached.');
        SELECT status, waiting_since IS NULL INTO st2b, w2b FROM helpdesk.ticket WHERE id = t2;
        -- an agent on leave holds nothing: the sweep returns their open ticket to the queue
        UPDATE helpdesk.agent_assignment SET availability = 'ON_LEAVE' WHERE person_id = b;
        SELECT count(*) INTO n_swept FROM helpdesk.sweep_inactive_agents();
        SELECT status, assigned_to INTO st2c, a2c FROM helpdesk.ticket WHERE id = t2;
        -- the Head takes an agent off the desk: every open ticket with them returns
        n_off := helpdesk.deactivate_agent(c, head, 'Transferred out of the ICT unit');
        SELECT count(*) INTO n_c FROM helpdesk.agent_assignment WHERE person_id = c AND active;
        -- a critical ticket is due within its own SLA
        PERFORM helpdesk.set_priority(t1, 'CRITICAL', head);
        v_hours := round(EXTRACT(EPOCH FROM (helpdesk.due_at(now(), 'CRITICAL') - now())) / 3600);
        SELECT string_agg(action, ',' ORDER BY at) INTO ev FROM helpdesk.ticket_event WHERE ticket_id = t1;
        RAISE EXCEPTION 'the V328 support desk check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The support desk across the University: the Head of ICT Support Desk is an office, the queues and the routing rules are seeded, a ticket is routed to its queue and to the agent posted to its faculty before the University-wide one, a payment problem goes to the Bursary''s queue, an agent sees only what their postings cover and the Head everything, a transfer says why and moves the one ticket to an agent of the new queue, an escalation goes only to the queue''s office or the Director of ICT and only that office answers (internally, back to the agent), a wait on the requester ends with their reply, an agent on leave or taken off the desk holds nothing, and a critical ticket is due within its own hours',
        n_offices = 1 AND n_queues >= 11 AND n_rules >= 17
        AND q1 = 'ICT_SUPPORT' AND a1 = a AND q2 = 'ICT_SUPPORT' AND a2 = b AND q3 = 'BURSARY_SUPPORT' AND a3 = c
        AND v_scope = 'tfftft'
        AND r_noreason = 'HELPDESK_REASON_REQUIRED' AND q1b = 'BURSARY_SUPPORT' AND a1b = c AND n_tickets = 1
        AND r_office = 'HELPDESK_ESCALATION_OFFICE' AND st3 = 'WAITING_FOR_OFFICE' AND o3 = 'bursar' AND r_notoffice = 'HELPDESK_NOT_THE_OFFICE' AND st3b = 'IN_PROGRESS' AND o3b = c AND n_internal = 1
        AND st2 = 'WAITING_FOR_STUDENT' AND w2 AND st2b = 'IN_PROGRESS' AND w2b
        AND n_swept = 1 AND st2c = 'OPENED' AND a2c IS NULL
        AND n_off = 2 AND n_c = 0 AND v_hours = 4
        AND ev = 'SUBMITTED,ROUTED,ASSIGNED,TRANSFERRED,ASSIGNED,RETURNED,PRIORITY_CHANGED',
        format('offices=%s queues=%s rules=%s t1=%s/%s t2=%s/%s t3=%s/%s scope=%s noreason=%s transfer=%s/%s tickets=%s office=%s st3=%s/%s notoffice=%s after=%s/%s internal=%s wait=%s/%s reply=%s/%s swept=%s t2=%s/%s off=%s/%s hours=%s events=%s',
               n_offices, n_queues, n_rules, q1, a1 = a, q2, a2 = b, q3, a3 = c, v_scope, r_noreason, q1b, a1b = c, n_tickets, r_office, st3, o3, r_notoffice, st3b, o3b = c, n_internal,
               st2, w2, st2b, w2b, n_swept, st2c, a2c IS NULL, n_off, n_c, v_hours, ev));
END $$;

-- ── 177. V329: a course nothing carries is removed outright, with its offers and empty offerings; one a record carries is refused and ended instead ──
DO $$
DECLARE who uuid := gen_random_uuid(); v_dept text; v_prog text; v_sess text; v_off uuid; msg text;
        gone1 boolean; r_fk text; r_legacy text; kept2 boolean; o record; out2 text; out4 text; st2 text; gone4 boolean; n_offers int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        SELECT d.code, p.code INTO v_dept, v_prog FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code ORDER BY d.code, p.code LIMIT 1;
        SELECT name INTO v_sess FROM policy.academic_session ORDER BY starts_on DESC LIMIT 1;
        -- a bare course: removed outright, its programme offer with it
        PERFORM catalogue.create_course('ZZQ 901', 'Check removal one', 3, 1, 100, v_dept, 'Core');
        INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES ('ZZQ 901', v_prog, 100, 'Core');
        PERFORM catalogue.remove_course('ZZQ 901');
        gone1 := NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = 'ZZQ 901');
        SELECT count(*) INTO n_offers FROM catalogue.course_offer WHERE course_code = 'ZZQ 901';
        -- a course with a timetabled offering: refused by the key that carries it
        PERFORM catalogue.create_course('ZZQ 902', 'Check removal two', 3, 1, 100, v_dept, 'Core');
        v_off := gen_random_uuid();
        INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (v_off, 'ZZQ 902', v_sess, 1);
        INSERT INTO assessment.exam_timetable (offering_id, held_on, starts_at, ends_at, venue) VALUES (v_off, current_date + 30, '09:00', '11:00', 'Check Hall');
        BEGIN PERFORM catalogue.remove_course('ZZQ 902'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_fk := msg; END;
        kept2 := EXISTS (SELECT 1 FROM catalogue.course WHERE code = 'ZZQ 902' AND state <> 'ENDED') AND EXISTS (SELECT 1 FROM catalogue.offering WHERE id = v_off);
        -- a course an old-portal result names by code: refused too
        PERFORM catalogue.create_course('ZZQ 903', 'Check removal three', 3, 1, 100, v_dept, 'Core');
        INSERT INTO assessment.legacy_result_holding (session, semester, matric, course_code, raw) VALUES (v_sess, 1, 'MOAUM/CHK/00/0177', 'ZZQ 903', '{}'::jsonb);
        BEGIN PERFORM catalogue.remove_course('ZZQ 903'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_legacy := msg; END;
        -- the list: the carried one is ended, the bare one removed, each reported
        PERFORM catalogue.create_course('ZZQ 904', 'Check removal four', 3, 1, 100, v_dept, 'Core');
        FOR o IN SELECT * FROM catalogue.remove_or_end(ARRAY['ZZQ 902', 'ZZQ 904']) LOOP
            IF o.code = 'ZZQ 902' THEN out2 := o.outcome; ELSIF o.code = 'ZZQ 904' THEN out4 := o.outcome; END IF;
        END LOOP;
        SELECT state INTO st2 FROM catalogue.course WHERE code = 'ZZQ 902';
        gone4 := NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = 'ZZQ 904');
        RAISE EXCEPTION 'the V329 removal check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A course nothing carries is removed outright with its programme offer; one with a timetabled offering or an old-portal result is refused (COURSE_CARRIED) and kept whole; the list removes the bare and ends the carried, reporting each',
        gone1 AND n_offers = 0
        AND r_fk LIKE 'COURSE_CARRIED: ZZQ 902 is carried by the examination timetable%' AND kept2
        AND r_legacy LIKE 'COURSE_CARRIED: ZZQ 903 is named on 1 old-portal result%'
        AND out2 = 'ENDED' AND st2 = 'ENDED' AND out4 = 'REMOVED' AND gone4,
        format('gone1=%s offers=%s fk=%s kept2=%s legacy=%s out2=%s st2=%s out4=%s gone4=%s', gone1, n_offers, r_fk, kept2, r_legacy, out2, st2, out4, gone4));
END $$;

-- ── 178. V330: the level a student was at in a session is the registration's, else the enrolment's, else carried forward from entry — never today's level on a past record ──
DO $$
DECLARE who uuid := gen_random_uuid(); st uuid := gen_random_uuid(); prog text; s1 text; s2 text; s3 text; v_reg int; v_reg2 int; v_enrol int; v_carry int; v_now int; v_future int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        SELECT code INTO prog FROM ref.programme ORDER BY code LIMIT 1;
        -- three consecutive sessions on the calendar, the earliest the entry session
        s1 := '2170/2171'; s2 := '2171/2172'; s3 := '2172/2173';
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on)
        VALUES (gen_random_uuid(), s1, '2170-10-01', '2171-09-30'), (gen_random_uuid(), s2, '2171-10-01', '2172-09-30'), (gen_random_uuid(), s3, '2172-10-01', '2173-09-30');
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (st, 'MOAUM/ADM/96/960178', 'MOAUM/CHK/20/0178', 'CHECKLEVEL', 'Student', prog, 'UTME', s1, 100, 300, 'ACTIVE', now());
        -- the register's own word: an approved registration at 100 level in the entry session; 200 in the next
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by) VALUES (gen_random_uuid(), st, s1, 2, 100, 'APPROVED', now(), now(), who);
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by) VALUES (gen_random_uuid(), st, s2, 1, 200, 'APPROVED', now(), now(), who);
        v_reg := people.level_in(st, s1, 2);
        v_reg2 := people.level_in(st, s2, 2);          -- the session's other semester reads the session's registration
        -- the third session has no registration: the enrolment answers
        INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), st, s3, 300);
        v_enrol := people.level_in(st, s3, 1);
        -- a session with neither: the entry level carried forward from the entry session
        DELETE FROM people.enrolment WHERE student_id = st;
        v_carry := people.level_in(st, s3, 1);
        -- the current level is the last resort only: a session before entry, with no record, falls to it
        v_now := (SELECT current_level FROM people.student WHERE id = st);
        RAISE EXCEPTION 'the V330 level check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The level a student was at in a session is the registration''s (100 in the entry session, 200 the next, the session''s other semester reading the same), else the enrolment''s (300), else the entry level carried forward a session at a time (300), and never today''s level on a past record',
        v_reg = 100 AND v_reg2 = 200 AND v_enrol = 300 AND v_carry = 300 AND v_now = 300,
        format('reg=%s reg2=%s enrol=%s carry=%s now=%s', v_reg, v_reg2, v_enrol, v_carry, v_now));
END $$;

-- ── 179. V331: a student's standing is computed from the register, never from the matriculation year — a cancelled session merged carries its entrants, the Senate's award graduates, the programme's end with the record incomplete is spillover within the limit and review beyond it, and history is untouched ──
DO $$
DECLARE who uuid := gen_random_uuid(); prog text; a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); d uuid := gen_random_uuid(); e uuid := gen_random_uuid();
        r record; msg text; v uuid; k int; n_dec int;
        v_eff text; v_after text; v_elapsed int; r_cur text; r_merge text;
        pa record; pb record; pc record; pd record; pe record; dry record; wet record; c_status text; r_grad text; pe2 record; v_max int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        UPDATE policy.academic_session SET state = 'CLOSED', completed_at = now() WHERE state = 'CURRENT';
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on, state) VALUES
          (gen_random_uuid(), '2169/2170', '2169-10-01', '2170-09-30', 'CLOSED'), (gen_random_uuid(), '2170/2171', '2170-10-01', '2171-09-30', 'CLOSED'),
          (gen_random_uuid(), '2171/2172', '2171-10-01', '2172-09-30', 'CLOSED'), (gen_random_uuid(), '2172/2173', '2172-10-01', '2173-09-30', 'CLOSED'),
          (gen_random_uuid(), '2173/2174', '2173-10-01', '2174-09-30', 'CLOSED'), (gen_random_uuid(), '2174/2175', '2174-10-01', '2175-09-30', 'CLOSED'),
          (gen_random_uuid(), '2175/2176', '2175-10-01', '2176-09-30', 'PLANNED'), (gen_random_uuid(), '2176/2177', '2176-10-01', '2177-09-30', 'PLANNED');
        UPDATE policy.academic_session SET state = 'CURRENT', made_current_at = now(), senate_minute = 'SEN/2175/01' WHERE name = '2175/2176';
        PERFORM policy.merge_session('2171/2172', '2172/2173', 'Session cancelled by Senate; cohort merged', 'SEN/2172/04');
        v_eff := policy.effective_session('2171/2172'); v_after := policy.session_after('2172/2173', 3); v_elapsed := policy.sessions_elapsed('2172/2173', '2175/2176');
        BEGIN UPDATE policy.academic_session SET state = 'CURRENT' WHERE name = '2171/2172'; EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_cur := split_part(msg, ':', 1); END;
        BEGIN PERFORM policy.merge_session('2175/2176', '2176/2177', 'x', NULL); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_merge := split_part(msg, ':', 1); END;
        SELECT code INTO prog FROM ref.programme WHERE final_level = 400 ORDER BY code LIMIT 1;
        -- A: entered in the cancelled session, matric /71/, four years, registered every session, 400 level and registered now
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (a, 'MOAUM/ADM/71/710179', 'MOAUM/CHK/71/000179', 'CHECKCOHORTA', 'Student', prog, 'UTME', '2171/2172', 100, 400, 'ACTIVE', now());
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by) VALUES
          (gen_random_uuid(), a, '2172/2173', 1, 100, 'APPROVED', now(), now(), who), (gen_random_uuid(), a, '2175/2176', 1, 400, 'APPROVED', now(), now(), who);
        -- B: entered 2172/2173, matric /72/, enrolled now
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (b, 'MOAUM/ADM/72/720179', 'MOAUM/CHK/72/000179', 'CHECKCOHORTB', 'Student', prog, 'UTME', '2172/2173', 100, 400, 'ACTIVE', now());
        INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), b, '2175/2176', 400);
        -- C: entered 2170/2171, award approved by Senate, still ACTIVE on the record
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (c, 'MOAUM/ADM/70/700179', 'MOAUM/CHK/70/000179', 'CHECKCOHORTC', 'Student', prog, 'UTME', '2170/2171', 100, 400, 'ACTIVE', now());
        INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet, senate_state, senate_minute) VALUES (gen_random_uuid(), c, '2174/2175', 3.8, 'B.Sc.', NULL, 'APPROVED', 'SEN/2175/09');
        -- D: entered 2170/2171, no award, registered now: spillover year 1
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (d, 'MOAUM/ADM/70/700180', 'MOAUM/CHK/70/000180', 'CHECKCOHORTD', 'Student', prog, 'UTME', '2170/2171', 100, 400, 'ACTIVE', now());
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by) VALUES (gen_random_uuid(), d, '2175/2176', 1, 400, 'APPROVED', now(), now(), who);
        -- E: entered 2169/2170, nothing since 2170/2171: beyond the limit once the limit is one
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (e, 'MOAUM/ADM/69/690179', 'MOAUM/CHK/69/000179', 'CHECKCOHORTE', 'Student', prog, 'UTME', '2169/2170', 100, 400, 'ACTIVE', now());
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by) VALUES (gen_random_uuid(), e, '2170/2171', 1, 200, 'APPROVED', now(), now(), who);
        SELECT * INTO pa FROM people.academic_position WHERE student_id = a;
        SELECT * INTO pb FROM people.academic_position WHERE student_id = b;
        SELECT * INTO pc FROM people.academic_position WHERE student_id = c;
        SELECT * INTO pd FROM people.academic_position WHERE student_id = d;
        SELECT * INTO pe FROM people.academic_position WHERE student_id = e;
        -- the Senate's awards reconciled in bulk: counted first, then C graduated, nobody else moved
        SELECT * INTO dry FROM people.apply_cohort_rule('R1', NULL, 'CHK-179', true);
        SELECT * INTO wet FROM people.apply_cohort_rule('R1', NULL, 'CHK-179', false);
        SELECT status INTO c_status FROM people.student WHERE id = c;
        -- nobody is graduated by hand; a decision on evidence is recorded; a cohort corrected on evidence moves the expected completion
        BEGIN PERFORM people.decide_cohort(d, 'GRADUATED', 'He must have finished'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_grad := split_part(msg, ':', 1); END;
        v := people.decide_cohort(d, 'ACTIVE', 'Spillover confirmed: two courses outstanding, registered this session', 'CHK-179');
        SELECT count(*) INTO n_dec FROM people.cohort_decision WHERE student_id = d AND batch_ref = 'CHK-179';
        PERFORM policy.set_max_spillover(1);
        SELECT * INTO pe2 FROM people.academic_position WHERE student_id = e;
        PERFORM people.set_cohort_override(e, '2173/2174', 'Re-admitted into 200 level in 2173/2174 on the Senate list');
        SELECT max_spillover_years INTO v_max FROM policy.progression_setting;
        SELECT count(*) INTO k FROM people.student WHERE surname LIKE 'CHECKCOHORT%' AND matric_no LIKE 'MOAUM/CHK/%' AND entry_session IN ('2169/2170','2170/2171','2171/2172','2172/2173');
        SELECT effective_cohort, cohort_source, expected_completion, spillover_years INTO r FROM people.academic_position WHERE student_id = e;
        RAISE EXCEPTION 'the V331 cohort check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A student''s standing is computed from the register, never from the matriculation year: a cancelled session merged carries its entrants (A is ACTIVE at 400 in the merged cohort, expected to complete now, like B who entered the merged-into session), the Senate''s approved award graduates C in one counted act, D beyond the programme''s length with the record incomplete is a validated spillover student, E beyond the limit is for review, nobody is graduated by hand, a decision and a cohort correction are recorded, and every matriculation number and entry session stays',
        v_eff = '2172/2173' AND v_after = '2175/2176' AND v_elapsed = 3 AND r_cur = 'SESSION_CANCELLED' AND r_merge = 'SESSION_MERGE_CURRENT'
        AND pa.effective_cohort = '2172/2173' AND pa.cohort_source = 'MERGED' AND pa.jamb_year = 2171 AND pa.matric_year = 2071 AND pa.expected_completion = '2175/2176' AND pa.spillover_years = 0 AND pa.classification = 'ACTIVE' AND pa.rule = 'R3' AND pa.confidence = 'VALIDATED' AND pa.computed_level = 400
        AND pb.effective_cohort = '2172/2173' AND pb.cohort_source = 'ENTRY' AND pb.classification = 'ACTIVE' AND pb.expected_completion = '2175/2176'
        AND pc.classification = 'GRADUATED' AND pc.rule = 'R1' AND pc.confidence = 'VALIDATED' AND pc.proposed_status = 'GRADUATED' AND 'APPROVED_NOT_GRADUATED' = ANY(pc.issues)
        AND pd.classification = 'SPILLOVER' AND pd.spillover_years = 1 AND pd.spillover_state = 'SPILLOVER_YEAR_1' AND pd.confidence = 'VALIDATED' AND pd.proposed_status = 'ACTIVE'
        AND pe.classification = 'SPILLOVER' AND pe.spillover_years = 2 AND pe.confidence = 'LIKELY'
        AND dry.considered = 1 AND dry.applied = 0 AND wet.applied = 1 AND c_status = 'GRADUATED'
        AND r_grad = 'COHORT_GRADUATION_SENATE' AND n_dec = 1
        AND pe2.classification = 'SPILLOVER_LIMIT_REACHED' AND pe2.confidence = 'REVIEW' AND v_max = 1
        AND r.effective_cohort = '2173/2174' AND r.cohort_source = 'OVERRIDE' AND r.spillover_years = 0 AND r.expected_completion = '2176/2177'
        AND k = 5,
        format('eff=%s after=%s elapsed=%s cur=%s merge=%s | A=%s/%s/%s/%s/%s/%s/%s/%s | B=%s/%s/%s | C=%s/%s/%s/%s | D=%s/%s/%s/%s | E=%s/%s/%s | dry=%s/%s wet=%s c=%s grad=%s dec=%s | E2=%s/%s max=%s | over=%s/%s/%s/%s | kept=%s',
               v_eff, v_after, v_elapsed, r_cur, r_merge, pa.effective_cohort, pa.cohort_source, pa.jamb_year, pa.matric_year, pa.expected_completion, pa.spillover_years, pa.classification, pa.confidence,
               pb.effective_cohort, pb.classification, pb.expected_completion, pc.classification, pc.rule, pc.confidence, pc.proposed_status, pd.classification, pd.spillover_years, pd.spillover_state, pd.confidence,
               pe.classification, pe.spillover_years, pe.confidence, dry.considered, dry.applied, wet.applied, c_status, r_grad, n_dec, pe2.classification, pe2.confidence, v_max,
               r.effective_cohort, r.cohort_source, r.spillover_years, r.expected_completion, k));
END $$;

-- ── 180. V332: one course is offered to many programmes across departments without a second record — the owner's programme bound at once, another department's by its approval, the code renamed and the title edited with the identity and every binding kept, a binding ended kept on the record, and a structure upload binding another department's course without rewriting it ──
DO $$
DECLARE who uuid := gen_random_uuid(); d_a text; d_b text; p_a text; p_b text; v_id uuid; v_id2 uuid; v_id3 uuid; pr uuid; msg text;
        r_dup text; r_exists text; r_ended text; n_off int; n_off2 int; n_hist int; v_src text; v_out text; v_state text; n_prop int;
        v_title text; v_units int; v_basis text; imp record; v_new text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        -- two live departments in different faculties, each with an active programme
        SELECT d.code, p.code INTO d_a, p_a FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code AND NOT coalesce(p.archived, false)
         WHERE d.ended_on IS NULL ORDER BY d.code, p.code LIMIT 1;
        SELECT d.code, p.code INTO d_b, p_b FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code AND NOT coalesce(p.archived, false)
         WHERE d.ended_on IS NULL AND d.faculty_code <> (SELECT faculty_code FROM ref.department WHERE code = d_a) ORDER BY d.code, p.code LIMIT 1;
        PERFORM catalogue.create_course('ZZQ 332', 'Data Structures', 3, 1, 200, d_a, 'Core');
        SELECT id INTO v_id FROM catalogue.course WHERE code = 'ZZQ 332';
        PERFORM catalogue.bind_offer('ZZQ 332', p_a, 200, 'Core', NULL, 'COURSE');
        pr := catalogue.propose_offer('ZZQ 332', p_b, 200, 'Borrowed', NULL, 'Taken by the other programme', d_a);
        BEGIN PERFORM catalogue.propose_offer('ZZQ 332', p_b, 200, 'Borrowed', NULL, NULL, d_a); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_dup := split_part(msg, ':', 1); END;
        v_out := catalogue.decide_offer_proposal(pr, true, 'Approved at the board');
        SELECT count(*) INTO n_off FROM catalogue.course_offer WHERE course_code = 'ZZQ 332';
        SELECT source INTO v_src FROM catalogue.course_offer WHERE course_code = 'ZZQ 332' AND programme_code = p_b;
        BEGIN PERFORM catalogue.propose_offer('ZZQ 332', p_b, 200, 'Borrowed', NULL, NULL, d_a); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_exists := split_part(msg, ':', 1); END;
        -- the course edited and renamed is the same course; its bindings and its proposal follow
        PERFORM catalogue.update_course('ZZQ 332', 'Data Structures and Algorithms', 4, 1, 200, 'Core');
        v_new := catalogue.rename_course('ZZQ 332', 'zzq333');
        SELECT id, title, units INTO v_id2, v_title, v_units FROM catalogue.course WHERE code = v_new;
        SELECT count(*) INTO n_off2 FROM catalogue.course_offer WHERE course_code = v_new;
        SELECT count(*) INTO n_prop FROM catalogue.offer_proposal WHERE course_code = v_new AND state = 'APPROVED';
        -- a binding ended is kept on the record; an ended course is not offered
        v_state := catalogue.unbind_offer(v_new, p_b, 200, 'Dropped from the structure');
        SELECT count(*) INTO n_hist FROM catalogue.course_offer_history WHERE course_code = v_new AND programme_code = p_b;
        PERFORM catalogue.end_course(v_new);
        BEGIN PERFORM catalogue.bind_offer(v_new, p_b, 200, 'Borrowed', NULL, 'COURSE'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_ended := split_part(msg, ':', 1); END;
        -- a structure upload that names another department's course binds it, and leaves its title and units to its owner
        PERFORM catalogue.create_course('ZZQ 334', 'Owned Elsewhere', 2, 2, 300, d_a, 'Core');
        SELECT * INTO imp FROM catalogue.import_courses(p_b, jsonb_build_array(jsonb_build_object('code', 'ZZQ 334', 'title', 'Rewritten Title', 'units', '9', 'level', '300', 'semester', '2', 'status', 'C')), NULL);
        SELECT title, units INTO v_title, v_units FROM catalogue.course WHERE code = 'ZZQ 334';
        SELECT basis INTO v_basis FROM catalogue.course_offer WHERE course_code = 'ZZQ 334' AND programme_code = p_b;
        SELECT id INTO v_id3 FROM catalogue.course WHERE code = 'ZZQ 334';
        RAISE EXCEPTION 'the V332 offering check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('One course is offered to many programmes across departments without a second record: the owner''s programme bound at once, another department''s by its approval (a repeat proposal and a proposal of what is offered refused), the code renamed and the title edited with the identity and both bindings kept, a binding ended kept on the record, an ended course refused, and a structure upload binding another department''s course as Borrowed without rewriting it',
        d_a IS NOT NULL AND d_b IS NOT NULL AND d_a <> d_b
        AND r_dup = 'CAT_PROPOSAL_PENDING' AND v_out = 'APPROVED' AND n_off = 2 AND v_src = 'PROPOSAL' AND r_exists = 'CAT_OFFER_EXISTS'
        AND v_new = 'ZZQ 333' AND v_id2 = v_id AND n_off2 = 2 AND n_prop = 1
        AND v_state = 'REMOVED' AND n_hist = 1 AND r_ended = 'CAT_ENDED'
        AND imp.existing = 1 AND imp.courses = 0 AND imp.offers = 1 AND v_title = 'Owned Elsewhere' AND v_units = 2 AND v_basis = 'Borrowed' AND v_id3 IS NOT NULL,
        format('depts=%s/%s dup=%s decided=%s offers=%s src=%s exists=%s | renamed=%s same_id=%s offers2=%s prop=%s | unbind=%s hist=%s ended=%s | import existing=%s courses=%s offers=%s title=%s units=%s basis=%s',
               d_a, d_b, r_dup, v_out, n_off, v_src, r_exists, v_new, (v_id2 = v_id), n_off2, n_prop, v_state, n_hist, r_ended, imp.existing, imp.courses, imp.offers, v_title, v_units, v_basis));
END $$;

-- ── 181. V333: a course code written without its hyphen is corrected in place — proposed from the known prefixes, renamed where the corrected code is free with the identity and every binding kept, left where the corrected code is another course already, and a code of neither form refused ──
DO $$
DECLARE who uuid := gen_random_uuid(); d_a text; p_a text; msg text; v_id uuid; v_id2 uuid; n_fix int; v_prop text; v_twin boolean; r_bad text; r_taken text;
        n_renamed int; n_twin int; n_off int; v_norm1 text; v_norm2 text; v_norm3 text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        SELECT d.code, p.code INTO d_a, p_a FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code AND NOT coalesce(p.archived, false)
         WHERE d.ended_on IS NULL ORDER BY d.code, p.code LIMIT 1;
        -- uploaded as the old portal wrote them: the hyphen dropped
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state) VALUES
          ('MOAUCHM 181', 'Physical Chemistry I', 3, 1, 100, d_a, 'Core', 'LIVE'),
          ('BSUGEO 181', 'Map Reading', 2, 2, 100, d_a, 'Core', 'LIVE'),
          ('BSU-GEO 181', 'Map Reading', 2, 2, 100, d_a, 'Core', 'LIVE');
        PERFORM catalogue.bind_offer('MOAUCHM 181', p_a, 100, 'Core', NULL, 'IMPORT');
        SELECT id INTO v_id FROM catalogue.course WHERE code = 'MOAUCHM 181';
        SELECT count(*) INTO n_fix FROM catalogue.code_fixes(d_a) WHERE code IN ('MOAUCHM 181', 'BSUGEO 181');
        SELECT proposed INTO v_prop FROM catalogue.code_fixes(d_a) WHERE code = 'MOAUCHM 181';
        SELECT twin_exists INTO v_twin FROM catalogue.code_fixes(d_a) WHERE code = 'BSUGEO 181';
        SELECT count(*) FILTER (WHERE outcome = 'RENAMED'), count(*) FILTER (WHERE outcome = 'TWIN_EXISTS') INTO n_renamed, n_twin
          FROM catalogue.apply_code_fixes(d_a) WHERE code IN ('MOAUCHM 181', 'BSUGEO 181');
        SELECT id INTO v_id2 FROM catalogue.course WHERE code = 'MOAU-CHM 181';
        SELECT count(*) INTO n_off FROM catalogue.course_offer WHERE course_code = 'MOAU-CHM 181';
        BEGIN PERFORM catalogue.rename_course('BSUGEO 181', 'bad code!'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_bad := split_part(msg, ':', 1); END;
        BEGIN PERFORM catalogue.rename_course('BSUGEO 181', 'BSU-GEO 181'); EXCEPTION WHEN unique_violation THEN r_taken := 'TAKEN'; END;
        v_norm1 := catalogue.normal_code('moau - chm  101'); v_norm2 := catalogue.normal_code('csc311'); v_norm3 := catalogue.normal_code('CSC 309/CMP 441');
        RAISE EXCEPTION 'the V333 code-fix check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A course code written without its hyphen is corrected in place: proposed from the known prefixes, renamed where the corrected code is free with the identity and the binding kept, left as a twin where the corrected code is another course already, a code of neither form refused, and every accepted form normalised',
        n_fix = 2 AND v_prop = 'MOAU-CHM 181' AND v_twin = true AND n_renamed = 1 AND n_twin = 1 AND v_id2 = v_id AND n_off = 1
        AND r_bad = 'CAT_CODE' AND r_taken = 'TAKEN' AND v_norm1 = 'MOAU-CHM 101' AND v_norm2 = 'CSC 311' AND v_norm3 = 'CSC 309/CMP 441',
        format('fixes=%s proposed=%s twin=%s renamed=%s twins=%s same_id=%s offers=%s bad=%s taken=%s norm=%s/%s/%s',
               n_fix, v_prop, v_twin, n_renamed, n_twin, (v_id2 = v_id), n_off, r_bad, r_taken, v_norm1, v_norm2, v_norm3));
END $$;

-- ── 182. V334: a support agent reaches the students their postings' scopes cover and does only what the Head granted — a posting carries only known capabilities, a person's are the union of their live postings', an office-scoped posting reaches no student, and every support act is written with its reason and filed on the ticket named ──
DO $$
DECLARE who uuid := gen_random_uuid(); agent uuid; d_a text; p_a text; f_a text; d_b text; p_b text; st_a uuid := gen_random_uuid(); st_b uuid := gen_random_uuid();
        q text; msg text; r_caps text; sees_a boolean; sees_b boolean; sees_none boolean; caps text[]; words text; r_reason text; v_act uuid; n_ev int; n_act int; v_ins boolean;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'helpdeskhead', true);
        SELECT d.code, p.code, d.faculty_code INTO d_a, p_a, f_a FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code AND NOT coalesce(p.archived, false) WHERE d.ended_on IS NULL ORDER BY d.code, p.code LIMIT 1;
        SELECT d.code, p.code INTO d_b, p_b FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code AND NOT coalesce(p.archived, false)
         WHERE d.ended_on IS NULL AND d.faculty_code <> f_a ORDER BY d.code, p.code LIMIT 1;
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at) VALUES
          (st_a, 'MOAUM/ADM/82/820182', 'MOAUM/CHK/82/000182', 'CHECKSUPPORTA', 'Student', p_a, 'UTME', '2082/2083', 100, 100, 'ACTIVE', now()),
          (st_b, 'MOAUM/ADM/82/820183', 'MOAUM/CHK/82/000183', 'CHECKSUPPORTB', 'Student', p_b, 'UTME', '2082/2083', 100, 100, 'ACTIVE', now());
        INSERT INTO iam.person (id, surname, given_names) VALUES (gen_random_uuid(), 'CHECKAGENT', 'Support') RETURNING id INTO agent;
        SELECT code INTO q FROM helpdesk.queue WHERE active ORDER BY ordinal LIMIT 1;
        -- a posting carries only known capabilities
        BEGIN
            INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, q, 'FACULTY', f_a, ARRAY['VIEW_STUDENT', 'DELETE_EVERYTHING']);
        EXCEPTION WHEN check_violation THEN r_caps := 'REFUSED';
        END;
        -- an office-scoped posting reaches no student; a faculty posting reaches its own students
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, q, 'OFFICE', 'bursar', ARRAY['VIEW_STUDENT']);
        sees_none := helpdesk.agent_may_see_student(agent, st_a);
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, q, 'FACULTY', f_a, ARRAY['VIEW_STUDENT', 'EDIT_CONTACT']);
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities, effective_from, effective_to) VALUES (agent, q, 'DEPARTMENT', d_b, ARRAY['MANAGE_REGISTRATION'], current_date - 10, current_date - 1);
        sees_a := helpdesk.agent_may_see_student(agent, st_a);
        sees_b := helpdesk.agent_may_see_student(agent, st_b);
        caps := helpdesk.agent_capabilities(agent);
        SELECT s.words INTO words FROM helpdesk.agent_student_scope(agent) s;
        -- a support act says why, and is filed on the ticket named
        PERFORM set_config('moaum.actor_id', agent::text, true);
        PERFORM set_config('moaum.actor_office', 'ictagent', true);
        BEGIN PERFORM helpdesk.record_support_action(st_a, NULL, 'CONTACT_EDITED', 'mobile', '08011111111', '08022222222', '  '); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_reason := split_part(msg, ':', 1); END;
        v_act := helpdesk.record_support_action(st_a, NULL, 'CONTACT_EDITED', 'mobile', '08011111111', '08022222222', 'The student reported a wrong number');
        SELECT count(*) INTO n_act FROM helpdesk.support_action WHERE student_id = st_a AND agent_id = agent AND action = 'CONTACT_EDITED';
        v_ins := EXISTS (SELECT 1 FROM people.student_photo WHERE student_id = st_a);
        INSERT INTO people.student_photo (student_id, content, content_type, bytes, replaced_by, reason) VALUES (st_a, '\x00'::bytea, 'image/jpeg', 1, agent, 'replaced');
        SELECT count(*) INTO n_ev FROM people.student_photo WHERE student_id = st_a;
        RAISE EXCEPTION 'the V334 support check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A support agent reaches the students their postings'' scopes cover and does only what the Head granted: a posting with an unknown capability is refused, an office-scoped posting reaches no student, a faculty posting reaches its own student and not another faculty''s, a person''s capabilities are the union of their live postings'' (an ended posting counts for nothing), the scope reads in words, a support act without a reason is refused and one with it is on the ledger, and a replacement photograph is kept',
        r_caps = 'REFUSED' AND sees_none = false AND sees_a = true AND sees_b = false AND caps = ARRAY['EDIT_CONTACT', 'VIEW_STUDENT'] AND words IS NOT NULL
        AND r_reason = 'SUPPORT_REASON' AND v_act IS NOT NULL AND n_act = 1 AND v_ins = false AND n_ev = 1,
        format('caps_refused=%s none=%s a=%s b=%s caps=%s words=%s reason=%s act=%s n=%s photo=%s/%s', r_caps, sees_none, sees_a, sees_b, caps, words, r_reason, v_act IS NOT NULL, n_act, v_ins, n_ev));
END $$;

-- ── 183. V337: the postgraduate lifecycle completed — the department decides a paid application, returns it for correction and decides again only when the School returns it; the School's word is final on a "not recommended"; a valid applicant checks once paid, the status the School's; screening holds an accepted applicant off the register until cleared, and clearance admits them; an endorsed postgraduate registration counts for matriculation ──
DO $$
DECLARE who uuid := gen_random_uuid(); prog text; fac text; appl uuid := gen_random_uuid(); app uuid := gen_random_uuid(); v_student uuid;
        msg text; r_unpaid text; r_note text; r_twice text; r_admit text; r_reason text; st_returned text; st_resub text; st_back text; st_final text;
        dept_cleared boolean; c record; c2 record; scr_open text; st_cleared text; ok_student boolean; registered boolean; kinds text[];
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'pgschool', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKPGDESK', 'Officer');
        SELECT p.code, p.faculty_code INTO prog, fac FROM ref.programme p WHERE p.category = 'POST GRADUATE' AND NOT coalesce(p.archived, false) AND p.dept_code IS NOT NULL ORDER BY p.code LIMIT 1;
        INSERT INTO admissions.pg_applicant (id, session, surname, other_names, email, password_hash, contact_address)
        VALUES (appl, '2083/2084', 'CHECKPGLIFE', 'Applicant', 'check.pglife@example.com', '$2a$12$checkcheckcheckcheckcheckcheckcheckcheckcheckcheckche', 'No. 1 Check Road');
        INSERT INTO admissions.pg_application (id, applicant_id, session, application_no, programme_code, entry_level, state, submitted_at)
        VALUES (app, appl, '2083/2084', 'PG/83/999183', prog, 800, 'SUBMITTED', now());

        -- the department decides a paid application only
        BEGIN PERFORM admissions.pg_dept_decide(app, true, NULL, who); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_unpaid := split_part(msg, ':', 1); END;
        UPDATE admissions.pg_application SET fee_confirmed_at = now() WHERE id = app;
        -- a return says what to correct; the applicant resubmits
        BEGIN PERFORM admissions.pg_dept_return(app, '  ', who); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_note := split_part(msg, ':', 1); END;
        PERFORM admissions.pg_dept_return(app, 'Upload the NYSC certificate', who);
        SELECT state INTO st_returned FROM admissions.pg_application WHERE id = app;
        PERFORM admissions.pg_resubmit(app);
        SELECT state INTO st_resub FROM admissions.pg_application WHERE id = app;
        -- not recommended: decided once; the School returns it, the department decides again, the School's word is final
        PERFORM admissions.pg_dept_decide(app, false, 'Weak', who);
        BEGIN PERFORM admissions.pg_dept_decide(app, true, NULL, who); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_twice := split_part(msg, ':', 1); END;
        PERFORM admissions.pg_school_return(app, 'Reconsider the HND', who);
        SELECT state, dept_decided_at IS NULL AND dept_note IS NULL INTO st_back, dept_cleared FROM admissions.pg_application WHERE id = app;
        PERFORM admissions.pg_dept_decide(app, false, NULL, who);
        -- before the School decides, a valid applicant may pay to check, and reads PENDING once paid
        SELECT * INTO c FROM admissions.pg_status_checking(app);
        PERFORM admissions.pg_spgs_decide(app, true, 'Offered on the School''s judgement', who);
        SELECT state INTO st_final FROM admissions.pg_application WHERE id = app;
        UPDATE admissions.pg_application SET checking_confirmed_at = now() WHERE id = app;
        SELECT * INTO c2 FROM admissions.pg_status_checking(app);

        -- the session screens: acceptance opens the screening; the register waits for clearance, which admits
        INSERT INTO admissions.pg_screening_policy (session, required, enabled_from, venue) VALUES ('2083/2084', true, now() - interval '1 minute', 'Check Hall');
        UPDATE admissions.pg_application SET acceptance_confirmed_at = now() WHERE id = app;
        UPDATE admissions.pg_application SET state = 'ACCEPTED', accepted_at = now() WHERE id = app;
        SELECT state INTO scr_open FROM admissions.pg_screening WHERE application_id = app;
        BEGIN PERFORM admissions.pg_admit(app); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_admit := split_part(msg, ':', 1); END;
        BEGIN PERFORM admissions.pg_screening_decide(app, 'NOT_CLEARED', NULL, NULL, NULL, NULL, ' ', who, 'pgsecretary'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_reason := split_part(msg, ':', 1); END;
        PERFORM admissions.pg_screening_decide(app, 'CLEARED', ARRAY['First degree certificate'], NULL, NULL, 'Originals seen', NULL, who, 'pgsecretary');
        SELECT a.state, a.student_id INTO st_cleared, v_student FROM admissions.pg_application a WHERE a.id = app;
        ok_student := admissions.screening_ok_student(v_student);
        -- an endorsed postgraduate registration of the session is registration for matriculation
        INSERT INTO admissions.pg_registration (student_id, session, semester, mode, state, endorsed_at) VALUES (v_student, '2083/2084', 1, 'FULL_TIME', 'ENDORSED', now());
        SELECT m.registered INTO registered FROM people.matric_candidates('2083/2084', fac) m WHERE m.student_id = v_student;
        SELECT array_agg(kind ORDER BY at, kind) INTO kinds FROM admissions.pg_application_event WHERE application_id = app;
        RAISE EXCEPTION 'the V337 postgraduate lifecycle check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The postgraduate lifecycle completed: the department decides only a paid application, returns one for correction with a note and the applicant resubmits it, decides once until the School returns it to them, and the School''s decision on a "not recommended" is final; a valid applicant may pay to check before any decision and reads the School''s status once paid; an accepted applicant of a screening session is screened, held off the register until cleared (a refusal needs its reason), and clearance admits them; an endorsed postgraduate registration counts for matriculation',
        r_unpaid = 'PG_FEE_UNCONFIRMED' AND r_note = 'PG_RETURN_NOTE_REQUIRED' AND st_returned = 'RETURNED' AND st_resub = 'SUBMITTED'
        AND r_twice = 'PG_NOT_WITH_DEPARTMENT' AND st_back = 'SUBMITTED' AND dept_cleared AND st_final = 'OFFERED'
        AND c.valid AND c.may_pay AND NOT c.may_check AND c.status = 'PENDING' AND c2.may_check AND c2.status = 'ADMITTED'
        AND scr_open = 'PENDING' AND r_admit = 'PG_SCREENING_NOT_CLEARED' AND r_reason = 'PG_SCREENING_REASON' AND st_cleared = 'ADMITTED'
        AND v_student IS NOT NULL AND ok_student AND registered
        AND kinds @> ARRAY['RETURNED', 'RESUBMITTED', 'RETURNED_TO_DEPARTMENT', 'SCREENING_PENDING', 'SCREENING_CLEARED', 'ADMITTED'],
        format('unpaid=%s note=%s returned=%s resub=%s twice=%s back=%s/%s final=%s check=%s/%s/%s/%s paid=%s/%s screening=%s admit=%s reason=%s cleared=%s student=%s ok=%s registered=%s kinds=%s',
               r_unpaid, r_note, st_returned, st_resub, r_twice, st_back, dept_cleared, st_final, c.valid, c.may_pay, c.may_check, c.status, c2.may_check, c2.status,
               scr_open, r_admit, r_reason, st_cleared, v_student IS NOT NULL, ok_student, registered, kinds));
END $$;

-- ── 184. V338 (the reset withdrawn by V340): the course catalogue — an upload makes ONE course per code with an offering per programme (CORE or ELECTIVE for each) and writes nothing while a row is invalid; a registered offering keeps its title; a re-upload updates the same course; an owner change is kept; no reset function remains ──
DO $$
DECLARE who uuid := gen_random_uuid(); st uuid := gen_random_uuid(); reg uuid := gen_random_uuid(); off uuid := gen_random_uuid();
        v_id uuid; v_id2 uuid; msg text; r_invalid text; r_owner text; n_courses int; n_offers int; basis_e text; r_res jsonb;
        n_entry int; title_off text; title_res text; st_back text; title_back text; n_owner int; owner_src text; no_reset boolean;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKCATALOGUE', 'Officer');
        INSERT INTO ref.department (code, name, faculty_code) VALUES ('ZZC338', 'CHECK CATALOGUE ONE', 'SC'), ('ZZD338', 'CHECK CATALOGUE TWO', 'SC');
        INSERT INTO ref.programme (code, name, dept_code, faculty_code, min_score, category) VALUES
          ('C93381', 'CHECK PROGRAMME ONE', 'ZZC338', 'SC', 180, 'UNDER GRADUATE'),
          ('C93382', 'CHECK PROGRAMME TWO', 'ZZC338', 'SC', 180, 'UNDER GRADUATE'),
          ('C93383', 'CHECK PROGRAMME THREE', 'ZZD338', 'SC', 180, 'UNDER GRADUATE');
        -- an invalid row: nothing is written
        BEGIN
            PERFORM catalogue.import_catalogue(jsonb_build_array(
                jsonb_build_object('code', 'ZZX 338', 'title', 'Check Course', 'units', '3', 'level', '100', 'semester', '1', 'ownerDepartment', 'ZZC338', 'offeringProgramme', 'C93381', 'offeringType', 'CORE'),
                jsonb_build_object('code', 'ZZX 338', 'title', 'Check Course', 'units', '3', 'level', '100', 'semester', '1', 'ownerDepartment', 'ZZC338', 'offeringProgramme', 'C93382', 'offeringType', 'MAYBE')), true, 'check');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_invalid := split_part(msg, ':', 1);
        END;
        -- a valid file: one course, three offerings, an unused second course
        r_res := catalogue.import_catalogue(jsonb_build_array(
            jsonb_build_object('code', 'ZZX 338', 'title', 'Check Course', 'units', '3', 'level', '100', 'semester', '1', 'ownerDepartment', 'ZZC338', 'ownerProgramme', 'C93381', 'offeringProgramme', 'C93381', 'offeringType', 'CORE'),
            jsonb_build_object('code', 'ZZX 338', 'title', 'Check Course', 'units', '3', 'level', '100', 'semester', '1', 'ownerDepartment', 'ZZC338', 'ownerProgramme', 'C93381', 'offeringProgramme', 'C93382', 'offeringType', 'ELECTIVE'),
            jsonb_build_object('code', 'ZZX 338', 'title', 'Check Course', 'units', '3', 'level', '100', 'semester', '1', 'ownerDepartment', 'ZZC338', 'ownerProgramme', 'C93381', 'offeringProgramme', 'C93383', 'offeringType', 'CORE'),
            jsonb_build_object('code', 'ZZY 338', 'title', 'Check Unused', 'units', '2', 'level', '200', 'semester', '2', 'ownerDepartment', 'ZZC338', 'offeringProgramme', 'C93381', 'offeringType', 'CORE', 'prerequisite', 'ZZX 338')), true, 'check');
        SELECT count(*) INTO n_courses FROM catalogue.course WHERE code = 'ZZX 338';
        SELECT count(*) INTO n_offers FROM catalogue.course_offer WHERE course_code = 'ZZX 338';
        SELECT basis INTO basis_e FROM catalogue.course_offer WHERE course_code = 'ZZX 338' AND programme_code = 'C93382';
        SELECT id INTO v_id FROM catalogue.course WHERE code = 'ZZX 338';
        -- history on ZZX 338: a student registered on a session offering
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), '2083/2084', '2083-10-01', '2084-08-31') ON CONFLICT (name) DO NOTHING;
        INSERT INTO people.student (id, admission_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status)
        VALUES (st, 'MOAUM/ADM/83/833380', 'CHECKCATALOGUE', 'Student', 'C93381', 'UTME', '2083/2084', 100, 100, 'ADMITTED');
        INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (off, 'ZZX 338', '2083/2084', 1);
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES (reg, st, '2083/2084', 1, 100, 'APPROVED', now(), now());
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status) VALUES (reg, off, 3, 'CURRENT', 'APPROVED');
        -- a corrected title reaches the course; the registered offering keeps its own
        UPDATE catalogue.course SET title = 'Check Course Corrected' WHERE code = 'ZZX 338';
        SELECT title INTO title_off FROM catalogue.offering WHERE id = off;
        SELECT title INTO title_res FROM assessment.student_results(st) WHERE course_code = 'ZZX 338';
        -- the reset is withdrawn (V340): none of its functions remains
        no_reset := to_regprocedure('catalogue.course_reset(text,text,text,text)') IS NULL AND to_regprocedure('catalogue.course_reset_preview(text,text)') IS NULL
                    AND to_regprocedure('catalogue.reset_courses(text[],text[],text)') IS NULL AND to_regprocedure('catalogue.reset_scope(text,text)') IS NULL;
        -- a re-upload updates the same course; the registration on its offering is whole
        PERFORM catalogue.import_catalogue(jsonb_build_array(
            jsonb_build_object('code', 'ZZX 338', 'title', 'Check Course Again', 'units', '3', 'level', '100', 'semester', '1', 'ownerDepartment', 'ZZC338', 'offeringProgramme', 'C93381', 'offeringType', 'CORE')), true, 'check again');
        SELECT id, state, title INTO v_id2, st_back, title_back FROM catalogue.course WHERE code = 'ZZX 338';
        SELECT count(*) INTO n_entry FROM registration.entry WHERE offering_id = off;
        -- the owner moves, kept with its reason; an owner programme of another department is refused
        BEGIN PERFORM catalogue.change_owner('ZZX 338', 'ZZD338', 'C93381', 'wrong'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_owner := split_part(msg, ':', 1); END;
        PERFORM catalogue.change_owner('ZZX 338', 'ZZD338', 'C93383', 'Taught by the second department');
        SELECT count(*), max(source) INTO n_owner, owner_src FROM catalogue.course_owner_history WHERE course_id = v_id AND to_dept = 'ZZD338';
        RAISE EXCEPTION 'the V338 catalogue check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('The course catalogue: an invalid upload writes nothing; a valid one makes one course per code with an offering per programme, Core or Elective for each; a registered offering keeps its title through a correction; a re-upload updates the same course, its registration whole; an owner change needs a programme of the new department and is kept; the withdrawn reset has no function left',
        r_invalid = 'CAT_IMPORT_INVALID' AND n_courses = 1 AND n_offers = 3 AND basis_e = 'Elective'
        AND title_off = 'Check Course' AND title_res = 'Check Course'
        AND no_reset AND n_entry = 1 AND v_id2 = v_id AND st_back = 'LIVE' AND title_back = 'Check Course Again'
        AND r_owner = 'CAT_OWNER_PROGRAMME' AND n_owner = 1 AND owner_src = 'DESK',
        format('invalid=%s courses=%s offers=%s elective=%s title=%s/%s noreset=%s entry=%s same=%s back=%s/%s owner=%s/%s/%s',
               r_invalid, n_courses, n_offers, basis_e, title_off, title_res, no_reset, n_entry, v_id2 = v_id, st_back, title_back, r_owner, n_owner, owner_src));
END $$;

-- ── 185. V339: JUPEB — the application window is closed until opened; the Bursary's defaults stand (₦15,000; ₦180,000 / ₦195,000 / ₦200,000 / ₦215,000; 70%); an O'Level needs five credits with English and Mathematics; the school fee follows Science-or-other and indigene status, is charged 70% then 30% in order and frozen once charged; the first instalment activates the student, who registers the combination's three subjects; an examination number is unique, a surname mismatch is held for review and a correction needs its reason ──
DO $$
DECLARE who uuid := gen_random_uuid(); acc1 uuid; acc2 uuid; app1 uuid; app2 uuid; s1 uuid; s2 uuid; s3 uuid; comb uuid; prog text; fac text; msg text;
        win text; d_app numeric; d_fees numeric[]; ok4 boolean; ok5 boolean; noeng boolean; sf record; r_order text; ref1 text; amt1 numeric; st_after text;
        n_reg int; r_taken text; r_reason text; imp jsonb; held text; frozen numeric; ses text := '2093/2094';
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        win := (SELECT w.state FROM policy.window_state('JUPEB_APPLICATION', ses, NULL) w);
        d_app := (jupeb.fee_setting_of(ses)).application_fee;
        d_fees := ARRAY[jupeb.school_fee_amount(ses, 'OTHER', true), jupeb.school_fee_amount(ses, 'SCIENCE', true),
                        jupeb.school_fee_amount(ses, 'OTHER', false), jupeb.school_fee_amount(ses, 'SCIENCE', false), (jupeb.fee_setting_of(ses)).first_percent];
        SELECT code, faculty_code INTO prog, fac FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT archived ORDER BY code LIMIT 1;
        INSERT INTO jupeb.fee_category (faculty_code, category) VALUES (fac, 'SCIENCE') ON CONFLICT (faculty_code) DO UPDATE SET category = 'SCIENCE';
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZCHK1', 'Check One') RETURNING id INTO s1;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZCHK2', 'Check Two') RETURNING id INTO s2;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZCHK3', 'Check Three') RETURNING id INTO s3;
        INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3) VALUES ('ZZCHK', 'Check combination', s1, s2, s3) RETURNING id INTO comb;
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check1@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc1;
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check2@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc2;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, programme_code, combination_id, state_of_origin, state)
        VALUES (acc1, ses, 'JUPEB/APP/2093/900001', 'CHECKONE', 'Candidate', 'zz.check1@example.com', prog, comb, 'Benue', 'ADMITTED') RETURNING id INTO app1;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, programme_code, combination_id, state_of_origin, state, subjects_registered_at, exam_no)
        VALUES (acc2, ses, 'JUPEB/APP/2093/900002', 'CHECKTWO', 'Candidate', 'zz.check2@example.com', prog, comb, 'Lagos', 'STUDENT', now(), 'ZZCHK-0002') RETURNING id INTO app2;
        INSERT INTO jupeb.olevel (application_id, sitting, exam_type, exam_number, exam_year, subject, grade) VALUES
            (app1, 1, 'WAEC', '4250001001', 2091, 'English Language', 'C6'), (app1, 1, 'WAEC', '4250001001', 2091, 'Mathematics', 'C5'),
            (app1, 1, 'WAEC', '4250001001', 2091, 'Physics', 'B3'), (app1, 1, 'WAEC', '4250001001', 2091, 'Chemistry', 'C4');
        ok4 := (SELECT k.ok FROM jupeb.olevel_check(app1) k);
        INSERT INTO jupeb.olevel (application_id, sitting, exam_type, exam_number, exam_year, subject, grade) VALUES (app1, 2, 'NECO', '1010002002', 2092, 'Biology', 'A1');
        ok5 := (SELECT k.ok FROM jupeb.olevel_check(app1) k);
        UPDATE jupeb.olevel SET grade = 'D7' WHERE application_id = app1 AND subject = 'English Language';
        noeng := (SELECT NOT k.ok AND NOT k.english FROM jupeb.olevel_check(app1) k);
        SELECT * INTO sf FROM jupeb.school_fees(app1);
        /* V342: an admitted candidate's school fees follow the confirmed acceptance fee */
        INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, expires_at, confirmed_at, channel)
        VALUES (app1, 'ACCEPTANCE', 'ZZCHK-ACC-0001', 15000, ses, now() + interval '1 day', now(), 'check');
        BEGIN PERFORM jupeb.new_fee_reference(app1, 'SCHOOL_SECOND'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_order := split_part(msg, ':', 1); END;
        ref1 := jupeb.new_fee_reference(app1, 'SCHOOL_FIRST');
        amt1 := (SELECT amount FROM jupeb.fee_reference WHERE reference = ref1);
        UPDATE jupeb.school_fee SET amount = 999999 WHERE session = '*' AND category = 'SCIENCE' AND indigene;
        PERFORM jupeb.confirm_fee(ref1, 'check');
        st_after := (SELECT state FROM jupeb.application WHERE id = app1);
        frozen := (SELECT f.total FROM jupeb.school_fees(app1) f);
        n_reg := jupeb.register_subjects(app1, who);
        BEGIN PERFORM jupeb.set_exam_no(app1, 'ZZCHK-0002', NULL, 'DESK', NULL); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_taken := split_part(msg, ':', 1); END;
        imp := jupeb.import_exam_numbers(jsonb_build_array(jsonb_build_object('row', 2, 'applicationNo', 'JUPEB/APP/2093/900001', 'examNo', 'ZZCHK-0001', 'surname', 'SOMEBODY')), true, 'check', who);
        held := (SELECT exam_no FROM jupeb.application WHERE id = app1);
        PERFORM jupeb.set_exam_no(app1, 'ZZCHK-0001', NULL, 'DESK', NULL);
        BEGIN PERFORM jupeb.set_exam_no(app1, 'ZZCHK-0003', NULL, 'DESK', NULL); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_reason := split_part(msg, ':', 1); END;
        RAISE EXCEPTION 'the V339 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB: the window is closed until opened; the Bursary''s defaults stand; five credits with English and Mathematics; Science/indigene ₦195,000 charged 70% then 30%, frozen once charged; the first instalment activates; three subjects registered; an examination number unique, a surname mismatch held for review, a correction needing its reason',
        win = 'CLOSED' AND d_app = 15000 AND d_fees = ARRAY[180000, 195000, 200000, 215000, 70]::numeric[]
        AND ok4 = false AND ok5 AND noeng
        AND sf.category = 'SCIENCE' AND sf.indigene AND sf.total = 195000 AND sf.first_amount = 136500 AND sf.second_amount = 58500
        AND r_order = 'JUPEB_FEE_ORDER' AND amt1 = 136500 AND st_after = 'STUDENT' AND frozen = 195000 AND n_reg = 3
        AND r_taken = 'JUPEB_EXAM_NO_TAKEN' AND (imp->>'review')::int = 1 AND held IS NULL AND r_reason = 'JUPEB_EXAM_NO_REASON',
        format('window=%s app=%s fees=%s ok4=%s ok5=%s noeng=%s fee=%s/%s/%s/%s/%s order=%s first=%s state=%s frozen=%s reg=%s taken=%s review=%s held=%s reason=%s',
               win, d_app, d_fees, ok4, ok5, noeng, sf.category, sf.indigene, sf.total, sf.first_amount, sf.second_amount, r_order, amt1, st_after, frozen, n_reg,
               r_taken, imp->>'review', held, r_reason));
END $$;

-- ── 186. V341 (V342): JUPEB — Science or Non-Science (V341's Arts): the applicant's stream decides the school fee (Non-Science pays the other fee); a draft without a stream is incomplete; a student registers a combination of their own stream ──
DO $$
DECLARE who uuid := gen_random_uuid(); acc uuid; app uuid; s1 uuid; s2 uuid; s3 uuid; s4 uuid; c_sci uuid; c_art uuid; msg text;
        cat text; total numeric; miss boolean; r_choose text; r_stream text; n_reg int; held uuid; ses text := '2092/2093';
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZS1', 'Check S One') RETURNING id INTO s1;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZS2', 'Check S Two') RETURNING id INTO s2;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZS3', 'Check S Three') RETURNING id INTO s3;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZS4', 'Check S Four') RETURNING id INTO s4;
        INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3, area) VALUES ('ZZSCI', 'Check science', s1, s2, s3, 'Science') RETURNING id INTO c_sci;
        INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3, area) VALUES ('ZZART', 'Check arts', s2, s3, s4, 'Arts') RETURNING id INTO c_art;
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check.stream@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, state_of_origin, state)
        VALUES (acc, ses, 'JUPEB/APP/2092/900001', 'CHECKSTREAM', 'Candidate', 'zz.check.stream@example.com', 'Benue', 'DRAFT') RETURNING id INTO app;
        miss := 'Choose Science or Non-Science' = ANY(jupeb.missing(app));
        UPDATE jupeb.application SET stream = 'NON_SCIENCE', state = 'STUDENT' WHERE id = app;
        SELECT f.category, f.total INTO cat, total FROM jupeb.school_fees(app) f;
        BEGIN PERFORM jupeb.register_subjects(app, who); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_choose := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.register_subjects(app, who, c_sci); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_stream := split_part(msg, ':', 1); END;
        n_reg := jupeb.register_subjects(app, who, c_art);
        held := (SELECT combination_id FROM jupeb.application WHERE id = app);
        RAISE EXCEPTION 'the V341 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB Science or Non-Science: a draft without a stream is incomplete; Non-Science with Benue pays the indigene other fee (NGN 180,000); a student must choose a combination of their own stream to register its three subjects',
        miss AND cat = 'OTHER' AND total = 180000 AND r_choose = 'JUPEB_COMBINATION_CHOOSE' AND r_stream = 'JUPEB_COMBINATION_STREAM' AND n_reg = 3 AND held = c_art,
        format('missing=%s fee=%s/%s choose=%s stream=%s reg=%s held=%s', miss, cat, total, r_choose, r_stream, n_reg, held = c_art));
END $$;

-- ── 187. V342: JUPEB — admission status checking is closed until opened and paid once (₦1,000) before any decision shows; the acceptance fee (₦15,000) follows an ADMITTED status and precedes school fees; an accepted admission cannot be withdrawn; two declared sittings need two O'Level documents; the grade point is out of 16 with a point for passing all three (X counts nothing); the Board's 46 combinations are seeded; a subject or combination not offered cannot be chosen and its holder is told; attendance corrections need a reason and a locked register is closed; no minimum, no verdict ──
DO $$
DECLARE who uuid := gen_random_uuid(); acc uuid; app uuid; s1 uuid; s2 uuid; s3 uuid; comb uuid; ses text := jupeb.current_session(); msg text;
        win text; d_chk numeric; d_acc numeric; masked boolean; r_closed text; ref_chk text; amt_chk numeric; r_once text; seen text; r_acc_early text; r_school text;
        ref_acc text; amt_acc numeric; accepted boolean; r_withdraw text; docs_short boolean; docs_full boolean; gp1 record; gp2 record;
        n_seed int; n_sci int; r_choose_off text; told int; prog_msg text; reg uuid; r_reason text; r_locked text; n_changes int; verdict text; rate numeric;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'ict', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'ZZCHECK', 'Attendance');
        win := (SELECT w.state FROM policy.window_state('JUPEB_ADMISSION_STATUS_CHECKING', ses, NULL) w);
        d_chk := (jupeb.fee_setting_of(ses)).checking_fee;
        d_acc := (jupeb.fee_setting_of(ses)).acceptance_fee;
        n_seed := (SELECT count(*) FROM jupeb.combination WHERE code ~ '^SC-0[0-4][0-9]$' AND jupeb.combination_offered(id));
        n_sci := (SELECT count(*) FROM jupeb.combination WHERE code ~ '^SC-' AND jupeb.combination_suits(area, 'SCIENCE'));
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZV1', 'Check V One') RETURNING id INTO s1;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZV2', 'Check V Two') RETURNING id INTO s2;
        INSERT INTO jupeb.subject (code, title) VALUES ('ZZV3', 'Check V Three') RETURNING id INTO s3;
        INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3, area) VALUES ('ZZVCOMB', 'Check V', s1, s2, s3, 'Science') RETURNING id INTO comb;
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check.v342@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, sex, date_of_birth, nin, phone, state_of_origin, lga, contact_address,
                                       next_of_kin_name, next_of_kin_phone, olevel_sittings, state)
        VALUES (acc, ses, 'JUPEB/APP/2091/900001', 'CHECKV', 'Candidate', 'zz.check.v342@example.com', 'F', '2007-01-01', '12345678901', '08012345678', 'Benue', 'Makurdi', '1 Road',
                'Kin', '08011111111', 2, 'DRAFT') RETURNING id INTO app;
        PERFORM jupeb.choose(app, 'SCIENCE', 'ZZVCOMB');
        -- the office stops offering a subject of the chosen combination: the candidate is told, and the programme step asks again
        told := (SELECT o.told FROM jupeb.set_offered('SUBJECT', ARRAY['zzv2'], false, who) o);
        BEGIN PERFORM jupeb.choose(app, 'SCIENCE', 'ZZVCOMB'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_choose_off := split_part(msg, ':', 1); END;
        prog_msg := (SELECT p->>'message' FROM jsonb_array_elements(jupeb.step_status(app)->'steps') st, jsonb_array_elements(st->'problems') p WHERE st->>'step' = 'PROGRAMME' LIMIT 1);
        PERFORM jupeb.set_offered('SUBJECT', ARRAY['ZZV2'], true, who);
        -- two sittings: both results, each its own document
        INSERT INTO jupeb.olevel (application_id, sitting, exam_type, exam_number, exam_year, subject, grade) VALUES
            (app, 1, 'WAEC', '4250009001', 2090, 'English Language', 'C5'), (app, 1, 'WAEC', '4250009001', 2090, 'Mathematics', 'B3'),
            (app, 1, 'WAEC', '4250009001', 2090, 'Physics', 'C6'), (app, 1, 'WAEC', '4250009001', 2090, 'Chemistry', 'C4'),
            (app, 2, 'NECO', '1010009002', 2090, 'Biology', 'B2');
        INSERT INTO jupeb.document (application_id, kind, sitting, filename, content_type, size_bytes) VALUES (app, 'OLEVEL_RESULT', 1, 'waec.pdf', 'application/pdf', 10);
        INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes)
        SELECT app, k.code, k.code || '.pdf', 'application/pdf', 10 FROM jupeb.document_kind k WHERE k.required AND k.active AND k.code <> 'OLEVEL_RESULT';
        docs_short := (SELECT NOT (st->>'ok')::boolean FROM jsonb_array_elements(jupeb.step_status(app)->'steps') st WHERE st->>'step' = 'DOCUMENTS');
        INSERT INTO jupeb.document (application_id, kind, sitting, filename, content_type, size_bytes) VALUES (app, 'OLEVEL_RESULT', 2, 'neco.pdf', 'application/pdf', 10);
        docs_full := (SELECT (st->>'ok')::boolean FROM jsonb_array_elements(jupeb.step_status(app)->'steps') st WHERE st->>'step' = 'DOCUMENTS');
        UPDATE jupeb.application SET fee_confirmed_at = now() WHERE id = app;
        PERFORM jupeb.submit(app);
        PERFORM jupeb.decide_eligibility(app, true, NULL, NULL);
        PERFORM jupeb.decide_admission(app, 'ADMITTED', 'Welcome', NULL);
        -- the decision is not readable, and checking not payable, until the Director of ICT opens checking
        masked := (SELECT NOT c.may_check AND NOT c.may_pay FROM jupeb.status_checking(app) c);
        BEGIN PERFORM jupeb.new_fee_reference(app, 'STATUS_CHECKING'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_closed := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.new_fee_reference(app, 'ACCEPTANCE'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_acc_early := split_part(msg, ':', 1); END;
        PERFORM policy.window_act('JUPEB_ADMISSION_STATUS_CHECKING', ses, NULL, 'OPEN', NULL, NULL, NULL, false, 'check', who, 'ict');
        ref_chk := jupeb.new_fee_reference(app, 'STATUS_CHECKING');
        amt_chk := (SELECT amount FROM jupeb.fee_reference WHERE reference = ref_chk);
        PERFORM jupeb.confirm_fee(ref_chk, 'check');
        BEGIN PERFORM jupeb.new_fee_reference(app, 'STATUS_CHECKING'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_once := split_part(msg, ':', 1); END;
        seen := (SELECT c.status FROM jupeb.status_checking(app) c WHERE c.may_check);
        BEGIN PERFORM jupeb.new_fee_reference(app, 'SCHOOL_FIRST'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_school := split_part(msg, ':', 1); END;
        ref_acc := jupeb.new_fee_reference(app, 'ACCEPTANCE');
        amt_acc := (SELECT amount FROM jupeb.fee_reference WHERE reference = ref_acc);
        PERFORM jupeb.confirm_fee(ref_acc, 'check');
        accepted := (SELECT c.accepted FROM jupeb.status_checking(app) c);
        BEGIN PERFORM jupeb.decide_admission(app, 'NOT_ADMITTED', 'withdrawn', NULL); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_withdraw := split_part(msg, ':', 1); END;
        -- results: A, B, C is 12 + 1 of 16; an absence (X) earns nothing and no point is added
        UPDATE jupeb.application SET state = 'STUDENT' WHERE id = app;
        PERFORM jupeb.register_subjects(app, who);
        INSERT INTO jupeb.result (application_id, subject_id, grade, points) VALUES (app, s1, 'A', 5), (app, s2, 'B', 4), (app, s3, 'C', 3);
        SELECT * INTO gp1 FROM jupeb.grade_point(app);
        UPDATE jupeb.result SET grade = 'X', points = 0 WHERE application_id = app AND subject_id = s3;
        SELECT * INTO gp2 FROM jupeb.grade_point(app);
        -- attendance: a correction needs its reason; a locked register is closed to the instructor; no minimum, no verdict
        INSERT INTO attendance.instructor (context, session, subject_ref, person_id) VALUES ('JUPEB', ses, s1, who);
        reg := attendance.open_register('JUPEB', ses, 1, s1, NULL, current_date, 'Check', who);
        PERFORM attendance.save_marks(reg, jsonb_build_array(jsonb_build_object('member', app, 'status', 'PRESENT')), NULL, who, false);
        BEGIN PERFORM attendance.save_marks(reg, jsonb_build_array(jsonb_build_object('member', app, 'status', 'LATE')), NULL, who, false);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_reason := split_part(msg, ':', 1); END;
        PERFORM attendance.save_marks(reg, jsonb_build_array(jsonb_build_object('member', app, 'status', 'LATE')), 'arrived late, recorded wrongly', who, false);
        n_changes := (SELECT count(*) FROM attendance.mark_change WHERE register_id = reg AND reason IS NOT NULL);
        PERFORM attendance.lock_register(reg, who, true, NULL);
        BEGIN PERFORM attendance.save_marks(reg, jsonb_build_array(jsonb_build_object('member', app, 'status', 'ABSENT')), 'again', who, false);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_locked := split_part(msg, ':', 1); END;
        SELECT m.verdict, m.rate INTO verdict, rate FROM attendance.member_summary('JUPEB', app, ses) m LIMIT 1;
        RAISE EXCEPTION 'the V342 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V342: status checking closed until opened, ₦1,000 once, before any decision shows; acceptance ₦15,000 after ADMITTED and before school fees; accepted admission kept; two sittings two documents; grade point 13/16, X nothing; 46 combinations seeded; a disabled subject withdraws its combinations and tells the holder; attendance corrections need a reason, a locked register is closed, no minimum no verdict',
        win = 'CLOSED' AND d_chk = 1000 AND d_acc = 15000 AND masked AND r_closed = 'JUPEB_CHECKING_CLOSED' AND r_acc_early = 'JUPEB_ACCEPTANCE_NOT_YET'
        AND amt_chk = 1000 AND ref_chk LIKE 'MOAUM-JUPEBCHK-' || substr(ses, 1, 4) || '-%' AND r_once = 'JUPEB_FEE_PAID' AND seen = 'ADMITTED' AND r_school = 'JUPEB_ACCEPTANCE_FIRST' AND amt_acc = 15000 AND accepted
        AND r_withdraw = 'JUPEB_ADMISSION_PAID' AND docs_short AND docs_full
        AND gp1.total = 13 AND gp1.out_of = 16 AND gp1.bonus = 1 AND gp2.total = 9 AND gp2.bonus = 0
        AND n_seed = 46 AND n_sci = 14 AND told = 1 AND r_choose_off = 'JUPEB_COMBINATION' AND prog_msg LIKE 'ZZVCOMB is no longer offered%'
        AND r_reason = 'ATT_REASON' AND n_changes = 1 AND r_locked = 'ATT_LOCKED' AND verdict IS NULL AND rate = 100,
        format('win=%s fees=%s/%s masked=%s closed=%s acc_early=%s chk=%s once=%s seen=%s school=%s acc=%s accepted=%s withdraw=%s docs=%s/%s gp=%s/%s+%s,%s+%s seed=%s sci=%s told=%s choose=%s prog=%s reason=%s changes=%s locked=%s verdict=%s rate=%s',
               win, d_chk, d_acc, masked, r_closed, r_acc_early, amt_chk, r_once, seen, r_school, amt_acc, accepted, r_withdraw, docs_short, docs_full,
               gp1.total, gp1.out_of, gp1.bonus, gp2.total, gp2.bonus, n_seed, n_sci, told, r_choose_off, prog_msg, r_reason, n_changes, r_locked, verdict, rate));
END $$;

-- ── 188. V343: JUPEB — a paper's code is issued only for what the record supports, kept while the record is unchanged, shows superseded after a change and not genuine once revoked; a change request needs its reason, is one at a time, is declined only with a note, defers only an accepted admission, and a combination change re-registers the subjects; reminders come when due, once a day, spaced and capped by the office's rule, and not at all when switched off ──
DO $$
DECLARE who uuid := gen_random_uuid(); acc uuid; acc2 uuid; app uuid; app2 uuid; ses text := jupeb.current_session(); msg text;
        c31 uuid; c33 uuid; r_noissue text; ack text; ack_again text; v_ok jsonb; v_after jsonb; v_rev jsonb; r_reason text; r_pending text; r_note text;
        r_defer text; rq uuid; rq2 uuid; subj_after text; due1 text; due_same int; due_later text; due_off int; sent jsonb; code_ok boolean;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        c31 := (SELECT id FROM jupeb.combination WHERE code = 'SC-031');
        c33 := (SELECT id FROM jupeb.combination WHERE code = 'SC-033');
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check.v343@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, state, submitted_at, fee_confirmed_at)
        VALUES (acc, ses, 'JUPEB/APP/2090/900001', 'CHECKP', 'Candidate', 'zz.check.v343@example.com', 'SCIENCE', c31, 'DRAFT', NULL, now()) RETURNING id INTO app;
        BEGIN PERFORM jupeb.issue_paper(app, 'ACKNOWLEDGEMENT', NULL, false, NULL, 'applicant'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_noissue := split_part(msg, ':', 1); END;
        UPDATE jupeb.application SET state = 'SUBMITTED', submitted_at = now() WHERE id = app;
        ack := jupeb.issue_paper(app, 'ACKNOWLEDGEMENT', NULL, false, NULL, 'applicant');
        ack_again := jupeb.issue_paper(app, 'ACKNOWLEDGEMENT', NULL, false, NULL, 'applicant');
        code_ok := ack ~ '^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$';
        v_ok := jupeb.verify_paper(lower(replace(ack, '-', '')));
        -- the change requests
        BEGIN PERFORM jupeb.request_change(app, 'CHANGE_COMBINATION', NULL, 'SC-033', NULL, 'short', who, 'applicant'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_reason := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.request_change(app, 'DEFER', NULL, NULL, NULL, 'Medical treatment this session', who, 'applicant'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_defer := split_part(msg, ':', 1); END;
        rq := jupeb.request_change(app, 'CHANGE_COMBINATION', NULL, 'SC-033', NULL, 'Mathematics in place of Physics', who, 'applicant');
        BEGIN PERFORM jupeb.request_change(app, 'WITHDRAW', NULL, NULL, NULL, 'A second request at once', who, 'applicant'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_pending := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.decide_change(rq, false, ' ', who, 'jupeb'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_note := split_part(msg, ':', 1); END;
        /* a student with subjects registered and no examination number: the change re-registers the new combination's three */
        UPDATE jupeb.application SET state = 'STUDENT' WHERE id = app;
        INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
        SELECT app, s, ses, who FROM jupeb.combination c, unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s WHERE c.id = c31;
        UPDATE jupeb.application SET subjects_registered_at = now() WHERE id = app;
        PERFORM jupeb.decide_change(rq, true, NULL, who, 'jupeb');
        subj_after := (SELECT string_agg(s.code, ',' ORDER BY s.code) FROM jupeb.subject_registration r JOIN jupeb.subject s ON s.id = r.subject_id WHERE r.application_id = app);
        v_after := jupeb.verify_paper(ack);
        PERFORM jupeb.revoke_paper(ack, 'Issued in error at the desk', who);
        v_rev := jupeb.verify_paper(ack);
        -- the reminders: a draft three days old, unpaid, while the window is open
        PERFORM policy.window_act('JUPEB_APPLICATION', ses, NULL, 'OPEN', NULL, NULL, NULL, false, 'check', who, 'ict');
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check.v343b@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc2;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, state, created_at)
        VALUES (acc2, ses, 'JUPEB/APP/2090/900002', 'CHECKR', 'Candidate', 'zz.check.v343b@example.com', 'DRAFT', now() - interval '3 days') RETURNING id INTO app2;
        due1 := (SELECT d.kind FROM jupeb.due_reminders(now()) d WHERE d.application_id = app2);
        sent := jupeb.send_reminders(now(), 'https://portal.example', 1000, 'OFFICE');
        due_same := (SELECT count(*) FROM jupeb.due_reminders(now() + interval '2 hours') d WHERE d.application_id = app2);
        due_later := (SELECT d.kind FROM jupeb.due_reminders(now() + interval '3 days 1 hour') d WHERE d.application_id = app2);
        UPDATE jupeb.reminder_rule SET enabled = false;
        due_off := (SELECT count(*) FROM jupeb.due_reminders(now() + interval '10 days'));
        RAISE EXCEPTION 'the V343 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V343: paper codes issued for the record as it is, kept, superseded after a change, void once revoked; change requests with a reason, one at a time, declined with a note, deferment only of an accepted admission, a combination change re-registering the subjects; reminders when due, once a day, spaced, off when switched off',
        r_noissue = 'JUPEB_PAPER_NOT_ISSUABLE' AND code_ok AND ack = ack_again AND (v_ok->>'genuine')::boolean AND (v_ok->>'current')::boolean
        AND r_reason = 'JUPEB_CHANGE_REASON' AND r_defer = 'JUPEB_DEFER_STATE' AND r_pending = 'JUPEB_CHANGE_PENDING' AND r_note = 'JUPEB_CHANGE_NOTE'
        AND subj_after = 'BIO,CHM,MTH' AND (v_after->>'genuine')::boolean AND NOT (v_after->>'current')::boolean
        AND NOT (v_rev->>'genuine')::boolean AND (v_rev->>'revoked')::boolean
        AND due1 = 'FEE_UNPAID' AND (sent->'byKind'->>'FEE_UNPAID')::int >= 1 AND due_same = 0 AND due_later IS NOT NULL AND due_off = 0,
        format('noissue=%s code=%s same=%s ok=%s reason=%s defer=%s pending=%s note=%s subjects=%s after=%s/%s revoked=%s due=%s sent=%s same_day=%s later=%s off=%s',
               r_noissue, code_ok, ack = ack_again, v_ok->>'current', r_reason, r_defer, r_pending, r_note, subj_after, v_after->>'genuine', v_after->>'current',
               v_rev->>'revoked', due1, sent, due_same, due_later, due_off));
END $$;

-- ── 189. V344: JUPEB attendance minimum — with no minimum nobody is below it or warned; with one, a subject under it is below (warned once enough classes are counted), one above it within the band is at risk; the warning names the subject and its rate, and the office's warning reaches it even when another reminder comes first ──
DO $$
DECLARE who uuid := gen_random_uuid(); acc uuid; app uuid; ses text := jupeb.current_session(); comb uuid; bio uuid; chm uuid; rg uuid; k int;
        none_flag int; none_due int; bio_v text; bio_w boolean; chm_r boolean; chm_v text; words text; warned jsonb; few boolean;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'ZZCHECK', 'Attendance');
        comb := (SELECT id FROM jupeb.combination WHERE code = 'SC-031');
        bio := (SELECT id FROM jupeb.subject WHERE code = 'BIO');
        chm := (SELECT id FROM jupeb.subject WHERE code = 'CHM');
        DELETE FROM attendance.policy WHERE context = 'JUPEB';
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check.v344@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, state, activated_at, subjects_registered_at)
        VALUES (acc, ses, 'JUPEB/APP/2089/900001', 'CHECKATT', 'Candidate', 'zz.check.v344@example.com', 'SCIENCE', comb, 'STUDENT', now() - interval '30 days', now())
        RETURNING id INTO app;
        INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
        SELECT app, x, ses, who FROM unnest(ARRAY[bio, chm, (SELECT id FROM jupeb.subject WHERE code = 'PHY')]) x;
        FOR k IN 1..4 LOOP   -- Biology: 2 of 4 (50%)
            rg := attendance.open_register('JUPEB', ses, 1, bio, NULL, current_date - k, NULL, who);
            PERFORM attendance.save_marks(rg, jsonb_build_array(jsonb_build_object('member', app, 'status', CASE WHEN k <= 2 THEN 'ABSENT' ELSE 'PRESENT' END)), NULL, who, true);
        END LOOP;
        FOR k IN 1..5 LOOP   -- Chemistry: 4 of 5 (80%)
            rg := attendance.open_register('JUPEB', ses, 1, chm, NULL, current_date - k, NULL, who);
            PERFORM attendance.save_marks(rg, jsonb_build_array(jsonb_build_object('member', app, 'status', CASE WHEN k = 1 THEN 'ABSENT' ELSE 'PRESENT' END)), NULL, who, true);
        END LOOP;
        none_flag := (SELECT count(*) FROM attendance.jupeb_standing(ses) st WHERE st.member_ref = app AND (st.verdict IS NOT NULL OR st.at_risk OR st.warnable));
        none_due := (SELECT count(*) FROM jupeb.due_reminders(now(), 'ATTENDANCE_LOW') d WHERE d.application_id = app);
        INSERT INTO attendance.policy (context, session, min_percent, warn_band, min_classes) VALUES ('JUPEB', ses, 75, 10, 3);
        SELECT st.verdict, st.warnable INTO bio_v, bio_w FROM attendance.jupeb_standing(ses) st WHERE st.member_ref = app AND st.code = 'BIO';
        SELECT st.verdict, st.at_risk INTO chm_v, chm_r FROM attendance.jupeb_standing(ses) st WHERE st.member_ref = app AND st.code = 'CHM';
        words := (jupeb.reminder_words(app, 'ATTENDANCE_LOW', '{}', 'https://portal.example'))[2];
        warned := jupeb.send_reminders(now(), 'https://portal.example', 1000, 'OFFICE', 'ATTENDANCE_LOW');
        UPDATE attendance.policy SET min_classes = 6 WHERE context = 'JUPEB' AND session = ses;
        few := (SELECT st.warnable FROM attendance.jupeb_standing(ses) st WHERE st.member_ref = app AND st.code = 'BIO');
        RAISE EXCEPTION 'the V344 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V344: no minimum, nobody below or warned; under the minimum is below (warned after enough classes), within the band above it is at risk; the warning names the subject; the office warning reaches it',
        none_flag = 0 AND none_due = 0 AND bio_v = 'NOT_ELIGIBLE' AND bio_w AND chm_v = 'ELIGIBLE' AND chm_r
        AND words LIKE '%minimum of 75% in: Biology 50%' || '%' AND (warned->'byKind'->>'ATTENDANCE_LOW')::int = 1 AND NOT few,
        format('none=%s/%s bio=%s/%s chm=%s/%s words=%s warned=%s few=%s', none_flag, none_due, bio_v, bio_w, chm_v, chm_r, left(words, 60), warned, few));
END $$;

-- ── 190. V345: JUPEB students from the old portal — a preview writes nothing; a row without a valid email is refused and listed, an unreadable phone or NIN is left out and said; the upload makes STUDENT records on the old App No with a temporary password to change, announces nothing, and the same file again adds nothing; no fee reminder reaches them; their registration sets the programme from the combination ──
DO $$
DECLARE who uuid := gen_random_uuid(); ses text := jupeb.current_session(); rows jsonb; prev jsonb; done jsonb; again jsonb; app uuid;
        n_prev int; st_bad text; st_review text; phone text; dob text; v_state text; v_must boolean; v_told int; v_fee int; v_stream text; n_reg int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        rows := jsonb_build_array(
            jsonb_build_object('row', 2, 'appNo', 'S0CHECK190001', 'firstName', 'IWANGER', 'surname', 'UVA', 'sex', 'Female', 'phone', '7052428202', 'dob', '9/1/2004',
                               'nin', '13181803004', 'email', 'zz.check190.a@gmail.'),
            jsonb_build_object('row', 3, 'appNo', 's0check190002', 'firstName', 'Paul', 'middleName', 'Shater', 'surname', 'Kegh', 'sex', 'Male', 'phone', '8089894004',
                               'dob', '21/10/2006', 'nin', '1171459604', 'email', 'zz.check190.b@example.com',
                               'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345'));
        prev := jupeb.import_old_portal_students(rows, ses, true, false, 'check.xlsx', who);
        n_prev := (SELECT count(*) FROM jupeb.application WHERE upper(application_no) LIKE 'S0CHECK190%');
        st_bad := prev->'rows'->0->>'status';
        st_review := prev->'rows'->1->>'status';
        phone := prev->'rows'->1->>'phone';
        dob := prev->'rows'->1->>'dob';
        done := jupeb.import_old_portal_students(rows, ses, true, true, 'check.xlsx', who);
        app := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK190002');
        SELECT a.state, acc.must_change_password INTO v_state, v_must FROM jupeb.application a JOIN jupeb.account acc ON acc.id = a.account_id WHERE a.id = app;
        v_told := (SELECT count(*) FROM platform.notice WHERE about_id = app);
        again := jupeb.import_old_portal_students(rows, ses, true, true, 'check.xlsx', who);
        v_fee := (SELECT count(*) FROM jupeb.due_reminders(now() + interval '60 days') d WHERE d.application_id = app AND d.kind = 'SCHOOL_FEE_UNPAID');
        n_reg := jupeb.register_subjects(app, who, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        v_stream := (SELECT stream FROM jupeb.application WHERE id = app);
        RAISE EXCEPTION 'the V345 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V345: the old portal''s students — a preview writes nothing; a bad email refused, an unreadable NIN left out and said; STUDENT records on the old App No with a temporary password to change, announced to nobody, not twice, spared fee reminders; registration sets the programme',
        n_prev = 0 AND st_bad = 'INVALID' AND st_review = 'REVIEW' AND phone = '08089894004' AND dob = '2006-10-21'
        AND (done->>'applied')::int = 1 AND v_state = 'STUDENT' AND v_must AND v_told = 0
        AND (again->>'applied')::int = 0 AND (again->>'exists')::int = 1 AND v_fee = 0 AND n_reg = 3 AND v_stream = 'NON_SCIENCE',
        format('prev=%s bad=%s review=%s phone=%s dob=%s applied=%s state=%s must=%s told=%s again=%s/%s fee=%s reg=%s stream=%s',
               n_prev, st_bad, st_review, phone, dob, done->>'applied', v_state, v_must, v_told, again->>'applied', again->>'exists', v_fee, n_reg, v_stream));
END $$;

-- ── 191. V346: ICT Support resolves a student's problem through the engines, never around them — a support act filed on the ticket reaches its timeline; a capability reaches a student only through a posting that covers them; the registration window and the engine's menu are set aside only by an override written with the rule it set aside, never fees, units or a closed semester; a dropped course is kept as DROPPED; an entitlement is refreshed only for a confirmed payment and makes none; no password reaches the ledger and a temporary one always forces a change ──
DO $$
DECLARE who uuid := gen_random_uuid(); agent uuid; f_a text; d_a text; p_a text; f_b text; d_b text; st uuid := gen_random_uuid(); ses text := '2071/2072';
        o_a uuid := gen_random_uuid(); o_b uuid := gen_random_uuid(); o_c uuid := gen_random_uuid(); o_d uuid := gen_random_uuid(); o_e uuid := gen_random_uuid();
        reg1 uuid := gen_random_uuid(); reg2 uuid := gen_random_uuid(); tkt uuid; msg text; q text;
        r_blocked text; r_period text; r_fees text; r_units text; r_closed text; r_noticket text; r_unconfirmed text; r_pw text; r_temp text; r_caps text;
        added jsonb; dropped jsonb; refreshed jsonb; n_checks int; v_marked boolean; v_rule text; n_ev int; v_ev_detail text; n_kept int; v_drop_status text;
        caps_for text[]; n_refs_before int; n_refs_after int; v_ref text; v_ok_cap boolean := false;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'helpdeskhead', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKSUPPORTHEAD', 'Support');
        SELECT d.faculty_code, d.code, p.code INTO f_a, d_a, p_a FROM ref.department d JOIN ref.programme p ON p.dept_code = d.code AND NOT coalesce(p.archived, false)
         WHERE d.ended_on IS NULL ORDER BY d.code, p.code LIMIT 1;
        SELECT d.faculty_code, d.code INTO f_b, d_b FROM ref.department d WHERE d.ended_on IS NULL AND d.faculty_code <> f_a ORDER BY d.code LIMIT 1;
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), ses, make_date(2071, 10, 1), make_date(2072, 8, 31)) ON CONFLICT (name) DO NOTHING;
        -- the first semester is not yet open (the window is shut); the second is closed (its registrations are history)
        INSERT INTO policy.semester (id, session, number, state) VALUES (gen_random_uuid(), ses, 1, 'NOT_YET_OPEN'), (gen_random_uuid(), ses, 2, 'CLOSED');
        -- the student owes nothing from any other session, so the Bursary's clearance reads this session alone
        UPDATE finance.fee_schedule SET ended_at = now() WHERE ended_at IS NULL AND session < ses;
        INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode, entry_session, entry_level, current_level, status, matriculated_at)
        VALUES (st, 'MOAUM/ADM/71/710191', 'MOAUM/CHK/71/000191', 'CHECKSUPPORTREG', 'Student', p_a, 'UTME', ses, 100, 100, 'ACTIVE', now());
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES
            ('CHK 191A', 'On the menu', 3, 1, 100, d_a, 'LIVE'), ('CHK 191B', 'Mapped to no programme', 3, 1, 300, d_b, 'LIVE'),
            ('CHK 191C', 'A second-semester course', 3, 2, 100, d_a, 'LIVE'), ('CHK 191D', 'Already registered', 3, 1, 100, d_a, 'LIVE'),
            ('CHK 191E', 'Another on the menu', 3, 1, 100, d_a, 'LIVE');
        INSERT INTO catalogue.course_offer (course_code, programme_code, level) VALUES ('CHK 191A', p_a, 100), ('CHK 191D', p_a, 100), ('CHK 191E', p_a, 100), ('CHK 191C', p_a, 100);
        INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (o_a, 'CHK 191A', ses, 1), (o_b, 'CHK 191B', ses, 1), (o_c, 'CHK 191C', ses, 2),
                                                                               (o_d, 'CHK 191D', ses, 1), (o_e, 'CHK 191E', ses, 1);
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at) VALUES
            (reg1, st, ses, 1, 100, 'APPROVED', now(), now()), (reg2, st, ses, 2, 100, 'APPROVED', now(), now());
        INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (reg1, o_d, 3, 'APPROVED'), (reg2, o_c, 3, 'APPROVED');

        -- the window shut: refused without an override, and the rule named
        BEGIN PERFORM registration.support_add(st, ses, 1, o_a, false, who, 'asked'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_blocked := split_part(msg, ':', 1); END;
        -- a course of another semester is never placed, override or not
        BEGIN PERFORM registration.support_add(st, ses, 1, o_c, true, who, 'asked'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_period := split_part(msg, ':', 1); END;
        n_checks := (SELECT count(*) FROM registration.support_add_checks(st, ses, 1, o_b));
        -- a course mapped to no programme, the window shut: the override places it, the override named on the entry
        added := registration.support_add(st, ses, 1, o_b, true, who, 'Portal fault: the course is missing from the student''s list');
        v_marked := EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = reg1 AND offering_id = o_b AND status = 'APPROVED' AND support_override_at IS NOT NULL);
        v_rule := added->>'normalRule';
        -- the override goes on the ledger only on a ticket, and the ticket's timeline takes it
        PERFORM set_config('moaum.actor_office', 'ictagent', true);
        BEGIN
            PERFORM helpdesk.record_support_action(st, NULL, 'COURSE_ADDED', 'CHK 191B', 'Not registered', 'Registered', 'Portal fault', ses, 1,
                    jsonb_build_object('override', true, 'normalRule', v_rule, 'description', 'Missing from the list'));
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_noticket := split_part(msg, ':', 1);
        END;
        tkt := helpdesk.submit('STUDENT', st, 'CHECKSUPPORTREG, Student', 'MOAUM/CHK/71/000191', 'check.support191@example.com', NULL, d_a, f_a, 'REGISTRATION', 'CHK 191B is missing', 'It is not on my list',
                               jsonb_build_object('session', ses, 'semester', '1', 'level', '100'));
        PERFORM helpdesk.record_support_action(st, tkt, 'COURSE_ADDED', 'CHK 191B', 'Not registered', 'Registered', 'Portal fault', ses, 1,
                jsonb_build_object('override', true, 'normalRule', v_rule, 'description', 'Missing from the list', 'summary', 'CHK 191B added to the first semester registration'));
        SELECT count(*), max(detail) INTO n_ev, v_ev_detail FROM helpdesk.ticket_event WHERE ticket_id = tkt AND action = 'SUPPORT_COURSE_ADDED';
        -- a drop is refused while the window is shut, and with the override the course is marked DROPPED, never deleted
        dropped := registration.support_drop(st, ses, 1, o_d, true, who, 'Registered in error by a portal fault');
        SELECT count(*), max(status) INTO n_kept, v_drop_status FROM registration.entry WHERE registration_id = reg1 AND offering_id = o_d;
        -- a closed semester's registration is history: not changed, override or not
        BEGIN PERFORM registration.support_drop(st, ses, 2, o_c, true, who, 'asked'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_closed := split_part(msg, ':', 1); END;
        -- the fees are never set aside: a schedule for the session, unpaid, refuses the override
        INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (ses, 'School fees', 50000, 100, p_a);
        BEGIN PERFORM registration.support_add(st, ses, 1, o_a, true, who, 'asked'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_fees := split_part(msg, ':', 1); END;
        -- an entitlement follows only a confirmed payment, and the refresh makes no payment
        v_ref := finance.new_purpose_reference(st, ses, 50000, 'School fees ' || ses);
        BEGIN PERFORM finance.refresh_entitlement(v_ref); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_unconfirmed := split_part(msg, ':', 1); END;
        PERFORM finance.confirm_payment(v_ref, 'BANK_BRANCH', 'teller for the check');
        n_refs_before := (SELECT count(*) FROM finance.payment_reference WHERE student_id = st);
        refreshed := finance.refresh_entitlement(v_ref);
        n_refs_after := (SELECT count(*) FROM finance.payment_reference WHERE student_id = st);
        -- the unit ceiling is never set aside either
        UPDATE policy.level_limit SET max_units = 4, min_units = 0 WHERE level = 100;
        BEGIN PERFORM registration.support_add(st, ses, 1, o_e, true, who, 'asked'); EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_units := split_part(msg, ':', 1); END;
        -- no password on the ledger; a temporary password always forces the change
        BEGIN
            PERFORM helpdesk.record_support_action(st, NULL, 'PASSWORD_RESET', NULL, NULL, 'Secret123', 'Locked out', NULL, NULL, jsonb_build_object('method', 'TEMPORARY_PASSWORD'));
        EXCEPTION WHEN check_violation THEN r_pw := 'REFUSED';
        END;
        BEGIN
            INSERT INTO iam.student_account (id, student_id, password_hash, must_change, temp_expires_at, temp_issued_by)
            VALUES (gen_random_uuid(), st, '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345', false, now() + interval '1 day', who);
        EXCEPTION WHEN check_violation THEN r_temp := 'REFUSED';
        END;
        -- a capability reaches a student only through a posting that covers them; a result-changing capability is not one
        PERFORM set_config('moaum.actor_office', 'helpdeskhead', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (gen_random_uuid(), 'CHECKSUPPORTCPO', 'Agent') RETURNING id INTO agent;
        SELECT code INTO q FROM helpdesk.queue WHERE active ORDER BY ordinal LIMIT 1;
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, q, 'GLOBAL', NULL, ARRAY['VIEW_STUDENT']);
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, q, 'FACULTY', f_b, ARRAY['OVERRIDE_REGISTRATION', 'RESET_PASSWORD']);
        v_ok_cap := true;
        caps_for := helpdesk.agent_capabilities_for(agent, st);
        BEGIN
            INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, q, 'GLOBAL', NULL, ARRAY['EDIT_RESULTS']);
        EXCEPTION WHEN check_violation THEN r_caps := 'REFUSED';
        END;
        RAISE EXCEPTION 'the V346 support check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('ICT Support resolves through the engines, never around them: the window and the menu set aside only by an override named with the rule it set aside and filed on the ticket''s timeline; a course of another semester, unpaid fees, the unit ceiling and a closed semester never set aside; a drop marks DROPPED and keeps the entry; an entitlement refreshed only for a confirmed payment, making none; no password on the ledger; a temporary password forces a change; a capability reaches only the students its posting covers, and no result-changing one exists',
        r_blocked = 'REG_BLOCKED' AND r_period = 'REG_RULE' AND n_checks = 16 AND (added->>'overridden')::boolean AND v_marked AND v_rule LIKE '%not on the engine%'
        AND r_noticket = 'SUPPORT_OVERRIDE_TICKET' AND n_ev = 1 AND v_ev_detail LIKE 'NORMAL RULE: Registration blocked because %SUPPORT ACTION: Override approved because Portal fault%'
        AND (dropped->>'overridden')::boolean AND n_kept = 1 AND v_drop_status = 'DROPPED' AND r_closed = 'REG_RULE'
        AND r_fees = 'REG_RULE' AND r_unconfirmed = 'PAY_NOT_CONFIRMED' AND (refreshed->'after'->>'paidInFull')::boolean AND n_refs_before = n_refs_after
        AND r_units = 'REG_RULE' AND r_pw = 'REFUSED' AND r_temp = 'REFUSED'
        AND v_ok_cap AND caps_for = ARRAY['VIEW_STUDENT'] AND r_caps = 'REFUSED',
        format('blocked=%s period=%s checks=%s added=%s marked=%s rule=%s noticket=%s ev=%s/%s dropped=%s kept=%s/%s closed=%s fees=%s unconfirmed=%s refreshed=%s refs=%s/%s units=%s pw=%s temp=%s caps_for=%s caps=%s',
               r_blocked, r_period, n_checks, added->>'overridden', v_marked, v_rule, r_noticket, n_ev, left(v_ev_detail, 60), dropped->>'overridden', n_kept, v_drop_status, r_closed,
               r_fees, r_unconfirmed, refreshed->'after'->>'paidInFull', n_refs_before, n_refs_after, r_units, r_pw, r_temp, caps_for, r_caps));
END $$;

-- ── 192. V347: JUPEB — the old portal's payments posted once as confirmed fees (matched by App No, never a failed or repeated one) and the student then reached by fee reminders; a correction of identity details applied only on the office's approval; a practice test scored by the server with the answer key hidden until submission; a class never double-booked; ICT Support reaches JUPEB records only through a posting that does, its acts on the same ledger and only on the candidate's own ticket; the report reads the session ──
DO $$
DECLARE who uuid := gen_random_uuid(); ses text := jupeb.current_session(); app uuid; prev jsonb; done jsonb; again jsonb; v_kinds text[]; v_fee_status text;
        v_exempt_before boolean; v_exempt_after boolean; req uuid; v_surname_pending text; v_surname_after text; v_dob_after date; r_same text; msg text;
        t uuid; att uuid; q1 uuid; paper_before jsonb; paper_after jsonb; v_score int; r_clash text; s1 uuid; k uuid; agent uuid; tkt uuid; r_ticket text;
        caps_none text[]; caps_jupeb text[]; n_led int; rep jsonb; r_temp text;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKJUPEB347', 'Officer');
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        done := jupeb.import_old_portal_students(jsonb_build_array(jsonb_build_object('row', 2, 'appNo', 'S0CHECK192001', 'firstName', 'Ada', 'surname', 'Check',
                     'sex', 'Female', 'phone', '08011112222', 'dob', '1/2/2005', 'email', 'zz.check192@example.com',
                     'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345')), ses, true, true, 'check.xlsx', who);
        PERFORM set_config('moaum.jupeb_quiet', 'off', true);
        app := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK192001');
        PERFORM jupeb.register_subjects(app, who, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        v_exempt_before := jupeb.reminder_exempt(app, 'SCHOOL_FEE_UNPAID');
        -- the old portal's payments: a preview writes nothing; a failed one, an unknown App No and a repeat are listed, not posted
        prev := jupeb.import_old_portal_payments(jsonb_build_array(
                    jsonb_build_object('row', 2, 'appNo', 's0check192001', 'reference', 'OLD-192-A', 'purpose', 'School Fees (First Instalment)', 'amount', '80,000', 'date', '15/11/2024', 'status', 'Successful'),
                    jsonb_build_object('row', 3, 'appNo', 'S0CHECK192001', 'reference', 'OLD-192-B', 'purpose', 'School Fees (Second Instalment)', 'amount', '40000', 'date', '15/01/2025', 'status', 'Failed'),
                    jsonb_build_object('row', 4, 'appNo', 'S0NOSUCH192', 'reference', 'OLD-192-C', 'purpose', 'Acceptance Fee', 'amount', '10000', 'date', '01/10/2024', 'status', 'Paid'),
                    jsonb_build_object('row', 5, 'appNo', 'S0CHECK192001', 'reference', 'OLD-192-A', 'purpose', 'School Fees (First Instalment)', 'amount', '80000', 'date', '15/11/2024', 'status', 'Paid')),
                true, false, 'pay.xlsx', who);
        done := jupeb.import_old_portal_payments(jsonb_build_array(
                    jsonb_build_object('row', 2, 'appNo', 's0check192001', 'reference', 'OLD-192-A', 'purpose', 'School Fees (First Instalment)', 'amount', '80,000', 'date', '15/11/2024', 'status', 'Successful')),
                true, true, 'pay.xlsx', who);
        again := jupeb.import_old_portal_payments(jsonb_build_array(
                    jsonb_build_object('row', 2, 'appNo', 'S0CHECK192001', 'reference', 'old-192-a', 'purpose', 'School Fees (First Instalment)', 'amount', '80000', 'date', '15/11/2024', 'status', 'Successful')),
                true, true, 'pay.xlsx', who);
        v_kinds := ARRAY(SELECT kind || ':' || channel FROM jupeb.fee_reference WHERE application_id = app AND confirmed_at IS NOT NULL ORDER BY kind);
        v_fee_status := (SELECT paid::text FROM jupeb.school_fees(app));
        v_exempt_after := jupeb.reminder_exempt(app, 'SCHOOL_FEE_UNPAID');
        -- a correction of identity details: pending, then applied on approval
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        req := jupeb.request_correction(app, jsonb_build_object('surname', 'Checkmore', 'date_of_birth', '2005-02-01'), 'My surname is misspelt on the old portal record', app, 'applicant');
        v_surname_pending := (SELECT surname FROM jupeb.application WHERE id = app);
        BEGIN PERFORM jupeb.request_correction(app, jsonb_build_object('surname', 'X'), 'Another request while one is pending', app, 'applicant');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_same := split_part(msg, ':', 1); END;
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM jupeb.decide_change(req, true, 'Birth certificate sighted', who, 'jupeb');
        SELECT surname, date_of_birth INTO v_surname_after, v_dob_after FROM jupeb.application WHERE id = app;
        -- a practice test: the answer key hidden until submission, then the score
        t := (SELECT id FROM jupeb.subject s WHERE s.id IN (SELECT subject_id FROM jupeb.subject_registration WHERE application_id = app) ORDER BY s.code LIMIT 1);
        INSERT INTO jupeb.practice_test (subject_id, title, questions_per_attempt, attempts_allowed, open) VALUES (t, 'Check practice', 2, 1, true) RETURNING id INTO t;
        PERFORM jupeb.practice_upload(t, jsonb_build_array(jsonb_build_object('row', 2, 'question', 'Two and two?', 'a', '3', 'b', '4', 'answer', 'B', 'explanation', 'Count them'),
                                                          jsonb_build_object('row', 3, 'question', 'Three and one?', 'a', '4', 'b', '5', 'answer', 'A'),
                                                          jsonb_build_object('row', 4, 'question', 'Bad row', 'a', '1', 'b', '2', 'answer', 'D')), false);
        att := jupeb.practice_start(app, t);
        paper_before := jupeb.practice_paper(app, att);
        q1 := (SELECT id FROM jupeb.practice_question WHERE test_id = t AND stem = 'Two and two?');
        PERFORM jupeb.practice_answer_set(app, att, q1, 'b');
        PERFORM jupeb.practice_submit(app, att);
        paper_after := jupeb.practice_paper(app, att);
        v_score := (SELECT score FROM jupeb.practice_attempt WHERE id = att);
        -- a room is never booked twice in the same hour (V351: parallel lectures in other rooms are the rule)
        s1 := (SELECT subject_id FROM jupeb.subject_registration WHERE application_id = app ORDER BY subject_id LIMIT 1);
        INSERT INTO jupeb.room (code) VALUES ('LT1') ON CONFLICT (code) DO NOTHING;  -- V354: a room is one of the list
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES (ses, 1, s1, 2, '08:00', '10:00', 'LT 1');
        BEGIN
            INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES (ses, 1, s1, 2, '09:00', '11:00', 'LT 1');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_clash := split_part(msg, ':', 1);
        END;
        -- ICT Support: no reach without a posting that reaches JUPEB; the JUPEB queue's posting does; the act on the ledger, only on the candidate's ticket
        PERFORM set_config('moaum.actor_office', 'helpdeskhead', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (gen_random_uuid(), 'CHECKJUPEBAGENT', 'Agent') RETURNING id INTO agent;
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, 'ICT_SUPPORT', 'FACULTY', 'SC', ARRAY['RESET_PASSWORD']);
        caps_none := helpdesk.agent_jupeb_capabilities(agent);
        INSERT INTO helpdesk.agent_assignment (person_id, queue_code, scope_kind, scope_ref, capabilities) VALUES (agent, 'JUPEB_SUPPORT', 'GLOBAL', NULL, ARRAY['VIEW_STUDENT', 'EDIT_CONTACT']);
        caps_jupeb := helpdesk.agent_jupeb_capabilities(agent);
        PERFORM set_config('moaum.actor_id', agent::text, true);
        PERFORM set_config('moaum.actor_office', 'ictagent', true);
        tkt := helpdesk.submit('JUPEB', gen_random_uuid(), 'Someone else', NULL, 'someone@example.com', NULL, NULL, NULL, 'JUPEB', 'Not theirs', 'Another candidate''s ticket', jsonb_build_object('jupeb_issue', 'Other'));
        BEGIN PERFORM helpdesk.record_jupeb_support_action(app, tkt, 'CONTACT_EDITED', 'phone', '08011112222', '08033334444', 'Wrong ticket');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_ticket := split_part(msg, ':', 1); END;
        PERFORM helpdesk.record_jupeb_support_action(app, NULL, 'CONTACT_EDITED', 'phone', '08011112222', '08033334444', 'The student reported a new number at the desk');
        n_led := (SELECT count(*) FROM helpdesk.support_action WHERE jupeb_application_id = app AND student_id IS NULL);
        BEGIN
            UPDATE jupeb.account SET temp_expires_at = now() + interval '1 day', temp_issued_by = agent, must_change_password = false
             WHERE id = (SELECT account_id FROM jupeb.application WHERE id = app);
        EXCEPTION WHEN check_violation THEN r_temp := 'REFUSED';
        END;
        rep := jupeb.report(ses);
        RAISE EXCEPTION 'the V347 JUPEB check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V347: old-portal payments posted once as confirmed fees and the student then reminded; a correction applied only on approval; a practice test scored by the server, its key hidden until submission; no double-booked class; ICT Support reaches JUPEB only through a posting that does, on the same ledger and the candidate''s own ticket; the report reads the session',
        (prev->>'valid')::int = 1 AND (prev->>'invalid')::int = 2 AND (prev->>'exists')::int = 1 AND (done->>'applied')::int = 1 AND (again->>'applied')::int = 0
        AND v_kinds = ARRAY['SCHOOL_FIRST:Old portal'] AND v_fee_status::numeric = 80000 AND v_exempt_before AND NOT v_exempt_after
        AND v_surname_pending = 'CHECK' AND r_same = 'JUPEB_CHANGE_PENDING' AND v_surname_after = 'CHECKMORE' AND v_dob_after = '2005-02-01'
        AND NOT (paper_before->'questions'->0 ? 'answer') AND (paper_after->'questions'->0 ? 'answer') AND v_score = 1 AND jsonb_array_length(paper_before->'questions') = 2
        AND r_clash = 'JUPEB_SLOT_CLASH' AND caps_none = '{}'::text[] AND caps_jupeb = ARRAY['EDIT_CONTACT', 'VIEW_STUDENT'] AND r_ticket = 'SUPPORT_TICKET' AND n_led = 1
        AND r_temp = 'REFUSED' AND (rep->'enrolment'->'totals'->>'fromOldPortal')::int >= 1 AND jsonb_typeof(rep->'results') = 'array',
        format('prev=%s/%s/%s applied=%s again=%s kinds=%s fees=%s exempt=%s/%s pending=%s same=%s after=%s/%s key=%s/%s score=%s clash=%s caps=%s/%s ticket=%s ledger=%s temp=%s old=%s',
               prev->>'valid', prev->>'invalid', prev->>'exists', done->>'applied', again->>'applied', v_kinds, v_fee_status, v_exempt_before, v_exempt_after,
               v_surname_pending, r_same, v_surname_after, v_dob_after, paper_before->'questions'->0 ? 'answer', paper_after->'questions'->0 ? 'answer', v_score,
               r_clash, caps_none, caps_jupeb, r_ticket, n_led, r_temp, rep->'enrolment'->'totals'->>'fromOldPortal'));
END $$;

-- ── 193. V348: a stored file is held by every table that points at it — each column keeping an object id references platform.file_object, so the store's orphan sweep (which asks the catalogue, not a list) can never remove an object a row still shows; the JUPEB documents lost before are recorded and asked for again ──
DO $$
DECLARE unheld text; who uuid := gen_random_uuid(); app uuid; obj uuid; r_forget text := 'REMOVED'; n_lost_table int;
BEGIN
    unheld := (SELECT string_agg(c.table_schema || '.' || c.table_name, ', ' ORDER BY 1)
                 FROM information_schema.columns c JOIN information_schema.tables t
                   ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
                WHERE c.column_name = 'object_id' AND c.data_type = 'uuid' AND c.table_schema NOT IN ('pg_catalog', 'information_schema')
                  AND NOT (c.table_schema = 'platform' AND c.table_name = 'file_object')
                  AND NOT EXISTS (SELECT 1 FROM pg_constraint k
                                   WHERE k.contype = 'f' AND k.conrelid = (quote_ident(c.table_schema) || '.' || quote_ident(c.table_name))::regclass
                                     AND k.confrelid = 'platform.file_object'::regclass
                                     AND k.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attname = 'object_id')]));
    n_lost_table := (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'jupeb' AND table_name = 'document_lost');
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKFILES348', 'Officer');
        PERFORM jupeb.import_old_portal_students(jsonb_build_array(jsonb_build_object('row', 2, 'appNo', 'S0CHECK193001', 'firstName', 'Ada', 'surname', 'Check',
                     'sex', 'Female', 'phone', '08011112222', 'dob', '1/2/2005', 'email', 'zz.check193@example.com',
                     'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345')), jupeb.current_session(), true, true, 'check.xlsx', who);
        app := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK193001');
        INSERT INTO platform.file_object (id, object_key, content_type, size_bytes, sha256, owner_table, owner_id)
        VALUES (gen_random_uuid(), 'jupeb/document/check193/x.pdf', 'application/pdf', 5, '\x00'::bytea, 'jupeb.document', app::text) RETURNING id INTO obj;
        INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes, object_id) VALUES (app, 'NIN', 'nin.pdf', 'application/pdf', 5, obj);
        -- what FileObjects.forget does: the record first — refused while a document still points at it
        BEGIN
            DELETE FROM platform.file_object WHERE id = obj;
        EXCEPTION WHEN foreign_key_violation THEN r_forget := 'REFUSED';
        END;
        RAISE EXCEPTION 'the V348 files check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('A stored file is held by every table that points at it: each object id column references platform.file_object, so an object a JUPEB document (or any row) still shows is never removed',
        unheld IS NULL AND r_forget = 'REFUSED' AND n_lost_table = 1,
        format('unheld=%s forget=%s lost_table=%s', coalesce(unheld, 'none'), r_forget, n_lost_table));
END $$;

-- ── 194. V349: JUPEB — a notice reaches exactly its audience (the session, the stage, one class, combination or programme; never a withdrawn application) and is emailed only to those it reaches; a practice question answered once is never rewritten — an edit makes a new version that takes the image along, and a student sees an image only inside an attempt that drew it; the identity card is issued for an active student with a passport photograph, states no NIN, birth date or contact, and a replaced card stops verifying ──
DO $$
DECLARE who uuid := gen_random_uuid(); ses text := jupeb.current_session(); app uuid; other uuid; k uuid; n_all int; n_class int; n_mine int; n_other int; n_notified int;
        ann uuid; t uuid; q1 uuid; q2 uuid; att uuid; v_old_stem text; v_img_new boolean; v_visible boolean; v_hidden boolean; r_card text := 'ISSUED'; code1 text; code2 text;
        facts jsonb; v1 jsonb; v2 jsonb;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKJUPEB349', 'Officer');
        PERFORM jupeb.import_old_portal_students(jsonb_build_array(
                    jsonb_build_object('row', 2, 'appNo', 'S0CHECK194001', 'firstName', 'Ada', 'surname', 'Check', 'sex', 'Female', 'phone', '08011112222', 'dob', '1/2/2005',
                                       'email', 'zz.check194a@example.com', 'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345'),
                    jsonb_build_object('row', 3, 'appNo', 'S0CHECK194002', 'firstName', 'Ben', 'surname', 'Check', 'sex', 'Male', 'phone', '08011113333', 'dob', '1/3/2005',
                                       'email', 'zz.check194b@example.com', 'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345')), ses, true, true, 'check.xlsx', who);
        PERFORM set_config('moaum.jupeb_quiet', 'off', true);
        app := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK194001');
        other := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK194002');
        PERFORM jupeb.register_subjects(app, who, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        INSERT INTO jupeb.class (session, name) VALUES (ses, 'CHECK 194 CLASS') RETURNING id INTO k;
        UPDATE jupeb.application SET class_id = k WHERE id = app;
        -- whom a notice reaches
        n_all := jupeb.announcement_reach(ses, 'STUDENTS', NULL);
        n_class := jupeb.announcement_reach(ses, 'CLASS', k::text);
        INSERT INTO jupeb.announcement (session, audience, audience_ref, title, body, send_email, created_by) VALUES (ses, 'CLASS', k::text, 'Class notice', 'For the class only.', true, who)
        RETURNING id INTO ann;
        n_notified := jupeb.announcement_notify(ann);
        n_mine := (SELECT count(*) FROM jupeb.application a WHERE a.id = app AND jupeb.audience_reaches(ses, 'CLASS', k::text, a));
        n_other := (SELECT count(*) FROM jupeb.application a WHERE a.id = other AND jupeb.audience_reaches(ses, 'CLASS', k::text, a));
        -- a question answered is versioned, its image along; the image only inside an attempt that drew it
        t := (SELECT subject_id FROM jupeb.subject_registration WHERE application_id = app ORDER BY subject_id LIMIT 1);
        INSERT INTO jupeb.practice_test (subject_id, title, questions_per_attempt, attempts_allowed, open) VALUES (t, 'Check 194', 1, 1, true) RETURNING id INTO t;
        q1 := jupeb.practice_add(t, jsonb_build_object('question', 'Energy is $\frac{1}{2}mv^2$?', 'a', 'Yes', 'b', 'No', 'answer', 'A'));
        INSERT INTO jupeb.practice_image (question_id, filename, content_type, size_bytes) VALUES (q1, 'd.png', 'image/png', 4);
        INSERT INTO jupeb.practice_image_blob (question_id, bytes) VALUES (q1, '\x89504e47'::bytea);
        att := jupeb.practice_start(app, t);
        v_visible := jupeb.practice_image_visible(app, att, q1);
        v_hidden := jupeb.practice_image_visible(other, att, q1);
        PERFORM jupeb.practice_answer_set(app, att, q1, 'A');
        PERFORM jupeb.practice_submit(app, att);
        q2 := jupeb.practice_edit(t, q1, jsonb_build_object('question', 'Kinetic energy is $\frac{1}{2}mv^2$?', 'a', 'Yes', 'b', 'No', 'answer', 'A'));
        v_img_new := EXISTS (SELECT 1 FROM jupeb.practice_image_blob WHERE question_id = q2);
        v_old_stem := (SELECT stem FROM jupeb.practice_question WHERE id = q1);
        -- the identity card
        BEGIN PERFORM jupeb.issue_paper(app, 'ID_CARD', NULL, true, who, 'jupeb');
        EXCEPTION WHEN check_violation THEN r_card := 'REFUSED';
        END;
        INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes) VALUES (app, 'PASSPORT', 'p.png', 'image/png', 4);
        code1 := jupeb.issue_paper(app, 'ID_CARD', NULL, true, who, 'jupeb');
        facts := (SELECT p.facts FROM jupeb.paper p WHERE p.code = code1);
        PERFORM jupeb.revoke_paper(code1, 'Card replaced: lost', who);
        code2 := jupeb.issue_paper(app, 'ID_CARD', NULL, true, who, 'jupeb');
        v1 := jupeb.verify_paper(code1);
        v2 := jupeb.verify_paper(code2);
        RAISE EXCEPTION 'the V349 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V349: a notice reaches exactly its audience and is emailed to them alone; an answered question is versioned with its image; the image is seen only in an attempt that drew it; the identity card needs a photograph, states no NIN, birth date or contact, and a replaced card stops verifying',
        n_all >= 1 AND n_class = 1 AND n_notified = 1 AND n_mine = 1 AND n_other = 0
        AND v_visible AND NOT v_hidden AND q2 <> q1 AND v_img_new AND v_old_stem = 'Energy is $\frac{1}{2}mv^2$?'
        AND r_card = 'REFUSED' AND facts->>'validFor' = ses AND NOT (facts ?| ARRAY['nin', 'dateOfBirth', 'email', 'phone'])
        AND code2 <> code1 AND (v1->>'revoked')::boolean AND (v2->>'genuine')::boolean,
        format('all=%s class=%s notified=%s mine=%s other=%s visible=%s/%s versioned=%s image=%s old=%s card=%s valid=%s codes=%s/%s revoked=%s genuine=%s',
               n_all, n_class, n_notified, n_mine, n_other, v_visible, v_hidden, q2 <> q1, v_img_new, v_old_stem, r_card, facts->>'validFor', code1, code2,
               v1->>'revoked', v2->>'genuine'));
END $$;

-- ── 195. V350: a JUPEB withdrawal opens a refund claim with the fees paid on the portal (none when nothing was paid); the Bursary raises a refund only once the candidate gave the account, through finance.refund, never beyond what was paid on the payment in all, maker and checker different; a claim with a refund raised is not declined; the paid refund is on the record; the day book names every JUPEB fee; practice results weakest first; a notice to one student reaches no other ──
DO $$
DECLARE maker uuid := gen_random_uuid(); checker uuid := gen_random_uuid(); ses text := jupeb.current_session(); app uuid; other uuid; claim uuid; ref text;
        n_claim_other int; r_details text; r_over text; r_same text; r_decline text; rf uuid; v_status text; v_paid numeric; n_ev int; v_label text; msg text;
        t uuid; att uuid; v_first uuid; n_reach int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', maker::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (maker, 'CHECKREFUND350', 'Maker'), (checker, 'CHECKREFUND350', 'Checker');
        PERFORM jupeb.import_old_portal_students(jsonb_build_array(
                    jsonb_build_object('row', 2, 'appNo', 'S0CHECK195001', 'firstName', 'Ada', 'surname', 'Check', 'sex', 'Female', 'phone', '08011112222', 'dob', '1/2/2005',
                                       'email', 'zz.check195a@example.com', 'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345'),
                    jsonb_build_object('row', 3, 'appNo', 'S0CHECK195002', 'firstName', 'Ben', 'surname', 'Check', 'sex', 'Male', 'phone', '08011113333', 'dob', '1/3/2005',
                                       'email', 'zz.check195b@example.com', 'passwordHash', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345')), ses, true, true, 'check.xlsx', maker);
        app := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK195001');
        other := (SELECT id FROM jupeb.application WHERE application_no = 'S0CHECK195002');
        INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, expires_at, confirmed_at, channel)
        VALUES (app, 'ACCEPTANCE', 'CHECK195-ACC', 75000, ses, now(), now(), 'Bank') RETURNING reference INTO ref;
        -- the withdrawal opens the claim; one with nothing paid opens none
        UPDATE jupeb.application SET state = 'WITHDRAWN', withdrawn_at = now() WHERE id IN (app, other);
        claim := (SELECT id FROM jupeb.refund_claim WHERE application_id = app);
        n_claim_other := (SELECT count(*) FROM jupeb.refund_claim WHERE application_id = other);
        BEGIN PERFORM jupeb.propose_claim_refund(claim, ref, 50000, 'Withdrawal');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_details := split_part(msg, ':', 1); END;
        UPDATE jupeb.refund_claim SET bank_name = 'First Bank', account_name = 'Ada Check', account_number = '3012345678', details_at = now() WHERE id = claim;
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        rf := jupeb.propose_claim_refund(claim, ref, 50000, 'Withdrawal before lectures');
        BEGIN PERFORM jupeb.propose_claim_refund(claim, ref, 30000, 'The rest');
        EXCEPTION WHEN check_violation THEN r_over := 'REFUSED'; END;
        BEGIN PERFORM jupeb.decline_refund_claim(claim, 'Not refundable', maker);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_decline := split_part(msg, ':', 1); END;
        BEGIN PERFORM finance.approve_refund(rf);
        EXCEPTION WHEN check_violation THEN r_same := 'REFUSED'; END;
        PERFORM set_config('moaum.actor_id', checker::text, true);
        PERFORM finance.approve_refund(rf);
        PERFORM finance.pay_refund(rf);
        v_status := jupeb.refund_claim_state(claim)->>'status';
        v_paid := (jupeb.refund_claim_state(claim)->>'paid')::numeric;
        n_ev := (SELECT count(*) FROM jupeb.application_event WHERE application_id = app AND kind IN ('REFUND_CLAIM_OPENED', 'REFUND_PROPOSED', 'REFUND_PAID'));
        v_label := (SELECT purpose FROM finance.day_book(current_date, current_date) WHERE reference = 'CHECK195-ACC');
        -- practice results, and a notice to one student
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        UPDATE jupeb.application SET state = 'STUDENT', withdrawn_at = NULL WHERE id = other;
        PERFORM jupeb.register_subjects(other, maker, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        t := (SELECT subject_id FROM jupeb.subject_registration WHERE application_id = other ORDER BY subject_id LIMIT 1);
        INSERT INTO jupeb.practice_test (subject_id, title, questions_per_attempt, attempts_allowed, open) VALUES (t, 'Check 195', 1, 1, true) RETURNING id INTO t;
        PERFORM jupeb.practice_upload(t, jsonb_build_array(jsonb_build_object('row', 2, 'question', 'Q?', 'a', '1', 'b', '2', 'answer', 'B')), false);
        att := jupeb.practice_start(other, t);
        PERFORM jupeb.practice_answer_set(other, att, (SELECT id FROM jupeb.practice_question WHERE test_id = t), 'A');
        PERFORM jupeb.practice_submit(other, att);
        v_first := (SELECT application_id FROM jupeb.practice_results(ses) ORDER BY average, name LIMIT 1);
        n_reach := jupeb.announcement_reach(ses, 'STUDENT', other::text);
        RAISE EXCEPTION 'the V350 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V350: a withdrawal opens a refund claim (none when nothing was paid); the Bursary refunds through finance.refund only to the account given, never beyond what was paid, maker and checker apart, a raised claim not declined; the day book names the fee; practice results weakest first; a notice to one student reaches one',
        claim IS NOT NULL AND n_claim_other = 0 AND r_details = 'JUPEB_REFUND_DETAILS' AND r_over = 'REFUSED' AND r_decline = 'JUPEB_REFUND_RAISED' AND r_same = 'REFUSED'
        AND v_status = 'REFUND_PAID' AND v_paid = 50000 AND n_ev = 3 AND v_label = 'JUPEB acceptance fee' AND v_first = other AND n_reach = 1,
        format('claim=%s other=%s details=%s over=%s decline=%s same=%s status=%s paid=%s events=%s label=%s first=%s reach=%s',
               claim IS NOT NULL, n_claim_other, r_details, r_over, r_decline, r_same, v_status, v_paid, n_ev, v_label, v_first = other, n_reach));
END $$;

-- ── 196. V351: the JUPEB programme names its own current session — the JUPEB windows follow it, the University's stays as it is, and cleared the University's applies again; the 2026/2027 first-semester timetable is on the record, every course at least three hours a week and every practical at least two, each lecture with its course code; a room or a class is never booked twice in the same hour while lectures in other rooms run side by side; a course code is kept as the Board prints it ──
DO $$
DECLARE who uuid := gen_random_uuid(); named text; uni text; v_cur text; v_app text; v_uni text; v_back text; r_bad text;
        n_seed int; n_short int; n_prac int; n_short_prac int; n_nocode int; n_noroom int;
        s1 uuid; s2 uuid; k uuid; v_code text; r_room text; r_class text; r_code text; n_side int; msg text;
BEGIN
    named := (SELECT current_session FROM jupeb.setting WHERE session = '*');
    -- the timetable as the JUPEB Office gave it
    n_seed := (SELECT count(*) FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active);
    n_short := (SELECT count(*) FROM (SELECT course_code FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active AND NOT practical
                                       GROUP BY course_code HAVING sum(ends_at - starts_at) < interval '3 hours') x);
    n_prac := (SELECT count(DISTINCT subject_id) FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active AND practical);
    n_short_prac := (SELECT count(*) FROM (SELECT subject_id FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active AND practical
                                            GROUP BY subject_id HAVING sum(ends_at - starts_at) < interval '2 hours') x);
    n_nocode := (SELECT count(*) FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active AND NOT practical AND course_code IS NULL);
    n_noroom := (SELECT count(*) FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active AND venue IS NULL);
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        uni := policy.application_session('POST_UTME_REGISTRATION');
        UPDATE jupeb.setting SET current_session = '2031/2032' WHERE session = '*';
        v_cur := jupeb.current_session();
        v_app := policy.application_session('JUPEB_APPLICATION');
        v_uni := policy.application_session('POST_UTME_REGISTRATION');
        UPDATE jupeb.setting SET current_session = NULL WHERE session = '*';
        v_back := jupeb.current_session();
        BEGIN UPDATE jupeb.setting SET current_session = '2031-2032' WHERE session = '*';
        EXCEPTION WHEN check_violation THEN r_bad := 'REFUSED'; END;
        -- a room or a class never twice in the same hour; other rooms side by side
        s1 := (SELECT id FROM jupeb.subject WHERE code = 'GEO');
        s2 := (SELECT id FROM jupeb.subject ORDER BY code OFFSET 1 LIMIT 1);
        INSERT INTO jupeb.class (session, name) VALUES ('2031/2032', 'CHECK196 A') RETURNING id INTO k;
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, class_id, weekday, starts_at, ends_at, venue, course_code)
        VALUES ('2031/2032', 1, s1, k, 1, '08:00', '10:00', 'LR8', 'gry001') RETURNING course_code INTO v_code;
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, s2, 1, '09:00', '10:00', 'lr 8');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_room := split_part(msg, ':', 1); END;
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, class_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, s2, k, 1, '09:00', '11:00', 'LR9');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_class := split_part(msg, ':', 1); END;
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, s2, 1, '08:00', '10:00', 'LR9');
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, s2, 1, '10:00', '11:00', 'LR8');
        n_side := (SELECT count(*) FROM jupeb.timetable_slot WHERE session = '2031/2032' AND active);
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue, course_code) VALUES ('2031/2032', 2, s1, 1, '08:00', '09:00', 'LR8', 'GEOGRAPHY 1');
        EXCEPTION WHEN check_violation THEN r_code := 'REFUSED'; END;
        RAISE EXCEPTION 'the V351 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V351: the JUPEB Office names the programme''s current session (2026/2027) and the JUPEB windows follow it, the University''s untouched, cleared the University''s again; the 2026/2027 first-semester timetable has every course three hours and every practical two, each lecture coded; a room or a class never twice in an hour, other rooms side by side; a course code as the Board prints it',
        named = '2026/2027' AND v_cur = '2031/2032' AND v_app = '2031/2032' AND v_uni = uni AND v_back = uni AND r_bad = 'REFUSED'
        AND n_seed = 56 AND n_short = 0 AND n_prac = 3 AND n_short_prac = 0 AND n_nocode = 0 AND n_noroom = 1
        AND v_code = 'GRY 001' AND r_room = 'JUPEB_SLOT_CLASH' AND r_class = 'JUPEB_SLOT_CLASH' AND n_side = 3 AND r_code = 'REFUSED',
        format('named=%s current=%s app=%s uni=%s/%s back=%s bad=%s seed=%s short=%s prac=%s short_prac=%s nocode=%s noroom=%s code=%s room=%s class=%s side=%s badcode=%s',
               named, v_cur, v_app, v_uni, uni, v_back, r_bad, n_seed, n_short, n_prac, n_short_prac, n_nocode, n_noroom, v_code, r_room, r_class, n_side, r_code));
END $$;

-- ── 197. V353: the JUPEB syllabus 2027–2031 — nineteen of the Board's subjects under the portal's, 77 course units with their semesters, credit units and topics (BIO 002 Botany in the first semester, as the Biology section has it); a combination's courses: MAT 004A for a Science combination, 004B for a Management Sciences one, and both options of an either/or subject until the student chooses, then that one only; the option is one of the subject's own, chosen by the student only until the examination number and changed by the office only with a reason; a timetable course is one of the subject's units, taught in that semester; the live timetable says ECN and GRY, each lecture linked to its unit ──
DO $$
DECLARE who uuid := gen_random_uuid(); ses text := jupeb.current_session(); acc uuid; app uuid; sub uuid; crs uuid; iss uuid; yor uuid; bio uuid; msg text;
        n_board int; n_units int; n_topics int; v_bio text; v_bio_sem int; v_mat_sci text; v_mat_mgt text; n_sc001 int; n_mine int; v_mine text;
        r_wrong text; r_locked text; r_reason text; v_final text; n_events int; r_course text; r_sem text; n_old int; n_unlinked int;
BEGIN
    n_board := (SELECT count(*) FROM jupeb.board_subject b JOIN jupeb.syllabus y ON y.id = b.syllabus_id WHERE y.code = '2027-2031');
    n_units := (SELECT count(*) FROM jupeb.subject_unit WHERE board_subject_id IS NOT NULL AND semester IS NOT NULL AND credit_units = 3);
    n_topics := (SELECT count(*) FROM jupeb.unit_topic);
    SELECT title, semester INTO v_bio, v_bio_sem FROM jupeb.subject_unit WHERE code = 'BIO 002';
    v_mat_sci := (SELECT string_agg(u.code, ',') FROM jupeb.units_for((SELECT id FROM jupeb.combination WHERE code = 'SC-038'), NULL) u WHERE u.code LIKE 'MAT 004%');
    v_mat_mgt := (SELECT string_agg(u.code, ',') FROM jupeb.units_for((SELECT id FROM jupeb.combination WHERE code = 'SC-024'), NULL) u WHERE u.code LIKE 'MAT 004%');
    n_sc001 := (SELECT count(*) FROM jupeb.units_for((SELECT id FROM jupeb.combination WHERE code = 'SC-001'), NULL));
    n_old := (SELECT count(*) FROM jupeb.timetable_slot WHERE session = '2026/2027' AND course_code ~ '^(ECO|GEO) ');
    n_unlinked := (SELECT count(*) FROM jupeb.timetable_slot WHERE session = '2026/2027' AND course_code IS NOT NULL AND unit_id IS NULL);
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKSYLLABUS353', 'Officer');
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check197@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acc;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, state)
        VALUES (acc, ses, 'CHECK197/0001', 'CHECK', 'Option', 'zz.check197@example.com', 'NON_SCIENCE', (SELECT id FROM jupeb.combination WHERE code = 'SC-001'), 'STUDENT')
        RETURNING id INTO app;
        PERFORM jupeb.register_subjects(app, who, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        sub := (SELECT id FROM jupeb.subject WHERE code = 'CRS/ISS');
        crs := (SELECT id FROM jupeb.board_subject WHERE prefix = 'CRS');
        iss := (SELECT id FROM jupeb.board_subject WHERE prefix = 'ISS');
        yor := (SELECT id FROM jupeb.board_subject WHERE prefix = 'YOR');
        BEGIN PERFORM jupeb.choose_option(app, sub, yor, false, NULL);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_wrong := split_part(msg, ':', 1); END;
        PERFORM jupeb.choose_option(app, sub, iss, false, NULL);
        n_mine := (SELECT count(*) FROM jupeb.units_for(NULL, app));
        v_mine := (SELECT string_agg(DISTINCT u.prefix, ',') FROM jupeb.units_for(NULL, app) u WHERE u.subject_code = 'CRS/ISS');
        UPDATE jupeb.application SET exam_no = 'CHK197000001' WHERE id = app;
        BEGIN PERFORM jupeb.choose_option(app, sub, crs, false, NULL);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_locked := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.choose_option(app, sub, crs, true, NULL);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_reason := split_part(msg, ':', 1); END;
        PERFORM jupeb.choose_option(app, sub, crs, true, 'The candidate sits Christian Religious Studies');
        v_final := (SELECT b.prefix FROM jupeb.subject_registration r JOIN jupeb.board_subject b ON b.id = r.board_subject_id WHERE r.application_id = app AND r.subject_id = sub);
        n_events := (SELECT count(*) FROM jupeb.application_event WHERE application_id = app AND kind = 'SUBJECT_OPTION');
        -- the timetable: a course of the subject, in its semester
        bio := (SELECT id FROM jupeb.subject WHERE code = 'BIO');
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue, course_code) VALUES ('2031/2032', 1, bio, 6, '08:00', '09:00', 'LR8', 'BIO 009');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_course := split_part(msg, ':', 1); END;
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue, course_code) VALUES ('2031/2032', 1, bio, 6, '08:00', '09:00', 'LR8', 'bio003');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_sem := split_part(msg, ':', 1); END;
        RAISE EXCEPTION 'the V353 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V353: the syllabus 2027–2031 — 19 Board subjects, 77 units with semesters and topics, BIO 002 Botany in the first semester; MAT 004A for Science, 004B for Management Sciences; both options until chosen, then that one; an option among the subject''s own, by the student until the examination number, by the office with a reason; a timetable course is a unit of the subject in its semester; ECN and GRY on the live timetable, each lecture linked',
        n_board = 19 AND n_units = 77 AND n_topics = 946 AND v_bio = 'Botany' AND v_bio_sem = 1 AND v_mat_sci = 'MAT 004A' AND v_mat_mgt = 'MAT 004B' AND n_sc001 = 16
        AND r_wrong = 'JUPEB_OPTION' AND n_mine = 12 AND v_mine = 'ISS' AND r_locked = 'JUPEB_OPTION_LOCKED' AND r_reason = 'JUPEB_OPTION_REASON' AND v_final = 'CRS' AND n_events = 2
        AND r_course = 'JUPEB_SLOT_COURSE' AND r_sem = 'JUPEB_SLOT_SEMESTER' AND n_old = 0 AND n_unlinked = 0,
        format('board=%s units=%s topics=%s bio002=%s/%s mat=%s|%s sc001=%s wrong=%s mine=%s/%s locked=%s reason=%s final=%s events=%s course=%s sem=%s old=%s unlinked=%s',
               n_board, n_units, n_topics, v_bio, v_bio_sem, v_mat_sci, v_mat_mgt, n_sc001, r_wrong, n_mine, v_mine, r_locked, r_reason, v_final, n_events, r_course, r_sem, n_old, n_unlinked));
END $$;

-- ── 198. V354: the Board's 2026/2027 calendar is on the record and copied forward a year as a plan (titles' years too); the semester is the second only from the day the calendar says; a venue is one of the list of rooms, a closed room takes no new lecture, a renamed room renames its lectures; a semester's timetable copies into the next with each course moved to its place (MAT 002 → MAT 004A, 004B noted), never into one with lectures; a lecture's register opens from its slot on its weekday only, once, apart from another lecture of the subject that day; a lecture not held is not opened, and one with marks is not called not held; the lectures due say which is which; a notice to a subject reaches its students only; the clearance says what is outstanding ──
DO $$
DECLARE who uuid := gen_random_uuid(); ses text := jupeb.current_session(); today date := (now() AT TIME ZONE 'Africa/Lagos')::date; wd int := extract(isodow FROM (now() AT TIME ZONE 'Africa/Lagos')::date)::int;
        n_cal int; v_teach date; v_reg date; v_exams date; v_sem_now int; v_sem_before int; v_sem_after int; n_copy int; v_exam28 date; v_title28 text; v_planned boolean; r_cal text;
        geo uuid; acc uuid; lr8 uuid; r_room text; r_closed text; v_renamed text; n_tt int; v_gry text; v_mat text; v_mat_note text; r_tt text;
        sa uuid; sb uuid; ra uuid; ra2 uuid; rb uuid; r_day text; v_state_a text; v_state_b text; r_notheld text; r_marked text;
        acct uuid; app uuid; v_reach_mine boolean; v_reach_other boolean; v_clear boolean; v_out text[]; msg text;
BEGIN
    n_cal := (SELECT count(*) FROM jupeb.calendar_event WHERE session = '2026/2027' AND source = 'BOARD' AND removed_at IS NULL);
    v_teach := jupeb.calendar_date('2026/2027', 'TEACHING_STARTS');
    v_reg := jupeb.calendar_date('2026/2027', 'BOARD_REGISTRATION');
    v_exams := jupeb.calendar_date('2026/2027', 'EXAMINATIONS');
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKCALENDAR354', 'Officer');
        -- the semester by the calendar, the calendar copied forward
        v_sem_now := jupeb.current_semester('2026/2027', DATE '2026-10-07');
        INSERT INTO jupeb.calendar_event (session, starts_on, title, marker) VALUES ('2026/2027', '2027-02-15', 'Second semester lectures begin', 'SEMESTER_2_STARTS');
        v_sem_before := jupeb.current_semester('2026/2027', DATE '2027-02-14');
        v_sem_after := jupeb.current_semester('2026/2027', DATE '2027-03-01');
        n_copy := jupeb.copy_calendar('2026/2027', '2027/2028', who);
        SELECT starts_on, title, planned INTO v_exam28, v_title28, v_planned FROM jupeb.calendar_event WHERE session = '2027/2028' AND marker = 'EXAMINATIONS';
        BEGIN PERFORM jupeb.copy_calendar('2026/2027', '2027/2028', who);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_cal := split_part(msg, ':', 1); END;
        -- the rooms
        geo := (SELECT id FROM jupeb.subject WHERE code = 'GEO');
        acc := (SELECT id FROM jupeb.subject WHERE code = 'ACC');
        lr8 := (SELECT id FROM jupeb.room WHERE code = 'LR8');
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, geo, 7, '08:00', '09:00', 'Hall Z 99');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_room := split_part(msg, ':', 1); END;
        INSERT INTO jupeb.room (code, kind, active) VALUES ('CHK198', 'HALL', false);
        BEGIN INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, geo, 7, '08:00', '09:00', 'chk 198');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_closed := split_part(msg, ':', 1); END;
        UPDATE jupeb.room SET active = true WHERE code = 'CHK198';
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, venue) VALUES ('2031/2032', 1, geo, 7, '08:00', '09:00', 'chk 198');
        UPDATE jupeb.room SET code = 'chk 199' WHERE code = 'CHK198';
        v_renamed := (SELECT venue FROM jupeb.timetable_slot WHERE session = '2031/2032' AND weekday = 7 AND starts_at = '08:00');
        -- the first semester copied into the second
        n_tt := jupeb.copy_timetable('2026/2027', 1, '2026/2027', 2, who);
        v_gry := (SELECT string_agg(DISTINCT course_code, ',') FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 2 AND course_code LIKE 'GRY%');
        SELECT course_code, note INTO v_mat, v_mat_note FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 2 AND course_code LIKE 'MAT 004%' LIMIT 1;
        BEGIN PERFORM jupeb.copy_timetable('2026/2027', 1, '2026/2027', 2, who);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_tt := split_part(msg, ':', 1); END;
        -- two lectures of a subject today: a register each, from the slot, on its weekday only
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, room_id) VALUES ('2031/2032', 1, acc, wd, '10:00', '11:00', lr8) RETURNING id INTO sa;
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, room_id) VALUES ('2031/2032', 1, acc, wd, '14:00', '15:00', lr8) RETURNING id INTO sb;
        ra := jupeb.open_lecture_register(sa, today, who);
        ra2 := jupeb.open_lecture_register(sa, today, who);
        BEGIN PERFORM jupeb.open_lecture_register(sa, today - 1, who);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_day := split_part(msg, ':', 1); END;
        PERFORM jupeb.record_not_held(sb, today, 'Public holiday declared', who, 'jupeb');
        BEGIN rb := jupeb.open_lecture_register(sb, today, who);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_notheld := split_part(msg, ':', 1); END;
        v_state_a := (SELECT state FROM jupeb.lectures_due('2031/2032', today, today) WHERE slot_id = sa);
        v_state_b := (SELECT state FROM jupeb.lectures_due('2031/2032', today, today) WHERE slot_id = sb);
        INSERT INTO attendance.mark (register_id, member_ref, status, marked_by) VALUES (ra, gen_random_uuid(), 'PRESENT', who);
        BEGIN PERFORM jupeb.record_not_held(sa, today, 'It was not held after all', who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_marked := split_part(msg, ':', 1); END;
        -- a notice to a subject's students; the clearance of a student with much outstanding
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check198@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acct;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, state)
        VALUES (acct, ses, 'CHECK198/0001', 'CHECK', 'Clearance', 'zz.check198@example.com', 'NON_SCIENCE', (SELECT id FROM jupeb.combination WHERE code = 'SC-001'), 'STUDENT')
        RETURNING id INTO app;
        PERFORM jupeb.register_subjects(app, who, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        v_reach_mine := jupeb.audience_reaches(ses, 'SUBJECT', (SELECT id::text FROM jupeb.subject WHERE code = 'GOV'), (SELECT a FROM jupeb.application a WHERE a.id = app));
        v_reach_other := jupeb.audience_reaches(ses, 'SUBJECT', acc::text, (SELECT a FROM jupeb.application a WHERE a.id = app));
        SELECT cleared, outstanding INTO v_clear, v_out FROM jupeb.exam_clearance(ses) WHERE application_id = app;
        RAISE EXCEPTION 'the V354 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V354: the Board''s 2026/2027 calendar, copied forward a year as a plan; the second semester only from its day; rooms from the list, a closed one refused, a rename followed; the first semester copied into the second (MAT 004A, 004B noted), never into one with lectures; a register per lecture from its slot on its weekday; not held, not opened; marked, not called not held; the lectures due say which; a subject''s notice reaches its students; the clearance says what is outstanding',
        n_cal = 36 AND v_teach = DATE '2026-09-28' AND v_reg = DATE '2026-11-13' AND v_exams = DATE '2027-07-26'
        AND v_sem_now = 1 AND v_sem_before = 1 AND v_sem_after = 2 AND n_copy = 37 AND v_exam28 = DATE '2028-07-26' AND v_title28 = '2028 examinations in all universities' AND v_planned
        AND r_cal = 'JUPEB_CALENDAR_EXISTS' AND r_room = 'JUPEB_ROOM_UNKNOWN' AND r_closed = 'JUPEB_ROOM_CLOSED' AND v_renamed = 'CHK199'
        AND n_tt = 56 AND v_gry = 'GRY 003,GRY 004' AND v_mat = 'MAT 004A' AND v_mat_note LIKE '%MAT 004B%' AND r_tt = 'JUPEB_TIMETABLE_NOT_EMPTY'
        AND ra = ra2 AND r_day = 'ATT_SLOT_DAY' AND r_notheld = 'JUPEB_LECTURE_NOT_HELD' AND v_state_a = 'OPEN' AND v_state_b = 'NOT_HELD' AND r_marked = 'JUPEB_LECTURE_RECORDED'
        AND v_reach_mine AND NOT v_reach_other AND NOT v_clear
        AND 'Say which is taken: Christian / Islamic Religious Studies' = ANY (v_out) AND 'No examination number from the Board yet' = ANY (v_out)
        AND NOT ('No minimum attendance is set' = ANY (v_out)),
        format('cal=%s teach=%s reg=%s exams=%s sem=%s/%s/%s copy=%s exam28=%s title28=%s planned=%s again=%s room=%s closed=%s renamed=%s tt=%s gry=%s mat=%s/%s ttagain=%s same=%s day=%s notheld=%s states=%s/%s marked=%s reach=%s/%s cleared=%s out=%s',
               n_cal, v_teach, v_reg, v_exams, v_sem_now, v_sem_before, v_sem_after, n_copy, v_exam28, v_title28, v_planned, r_cal, r_room, r_closed, v_renamed, n_tt, v_gry,
               v_mat, v_mat_note, r_tt, ra = ra2, r_day, r_notheld, v_state_a, v_state_b, r_marked, v_reach_mine, v_reach_other, v_clear, v_out));
END $$;

-- ── 199. V355: a record goes to the Board only when ready, and one changed since it was sent is flagged with what changed until the correction is sent; a correction asked is said; the topics a lecture covered are its course's and count to the course's coverage; an assessment score is within its part's maximum, the total out of the parts', and a locked subject takes none; a calendar reminder is sent once; the examination timetable is read from an upload, its papers shown to a student once published (the option they sit), and an admit card only for one cleared; a practice question names a course and topic of the syllabus; a mock is sat once, in its window, its results held until released ──
DO $$
DECLARE who uuid := gen_random_uuid(); ses text := jupeb.current_session(); today date := (now() AT TIME ZONE 'Africa/Lagos')::date; wd int := extract(isodow FROM (now() AT TIME ZONE 'Africa/Lagos')::date)::int;
        acct uuid; app uuid; sub uuid; iss uuid; gov uuid; msg text;
        v_problems text[]; r_notready text; v_ready boolean; v_changed boolean; v_facts text[]; v_after boolean; r_note text; v_stage text;
        slot uuid; reg uuid; n_topics int; t1 uuid; t2 uuid; other_topic uuid; r_topic text; v_covered int;
        c1 uuid; c2 uuid; r_range text; v_total numeric; v_out numeric; v_complete boolean; r_locked text;
        ev uuid; v_rem1 jsonb; v_rem2 jsonb; n_rem int;
        v_upload jsonb; n_before int; n_after int; v_iss_papers int; v_admit jsonb;
        tst uuid; q1 uuid; r_tag text; v_tagged boolean; mock uuid; r_mock_ck text; r_window text; att uuid; v_paper jsonb; n_topics_before int; n_topics_after int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKEXAMYEAR355', 'Officer');
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check199@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acct;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, state)
        VALUES (acct, ses, 'CHECK199/0001', 'CHECK', 'Board', 'zz.check199@example.com', 'NON_SCIENCE', (SELECT id FROM jupeb.combination WHERE code = 'SC-001'), 'STUDENT')
        RETURNING id INTO app;
        PERFORM jupeb.register_subjects(app, who, (SELECT id FROM jupeb.combination WHERE code = 'SC-001'));
        sub := (SELECT id FROM jupeb.subject WHERE code = 'CRS/ISS');
        gov := (SELECT id FROM jupeb.subject WHERE code = 'GOV');
        iss := (SELECT id FROM jupeb.board_subject WHERE prefix = 'ISS');
        -- the Board: not ready, then ready and sent; a change flagged; a correction asked and sent
        v_problems := jupeb.board_problems(app);
        BEGIN PERFORM jupeb.board_mark(ARRAY[app], ses, 'SENT', NULL, NULL, who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_notready := split_part(msg, ':', 1); END;
        UPDATE jupeb.application SET sex = 'F', date_of_birth = '2007-01-02', nin = '12345678901', phone = '08012340199', state_of_origin = 'Benue', lga = 'Makurdi' WHERE id = app;
        PERFORM jupeb.choose_option(app, sub, iss, false, NULL);
        INSERT INTO jupeb.document (application_id, kind, filename, content_type, size_bytes) VALUES (app, 'PASSPORT', 'p.jpg', 'image/jpeg', 10);
        v_ready := (SELECT ready FROM jupeb.board_status(ses) WHERE application_id = app);
        PERFORM jupeb.board_mark(ARRAY[app], ses, 'SENT', NULL, NULL, who, 'jupeb');
        UPDATE jupeb.application SET phone = '08012340299' WHERE id = app;
        SELECT changed, changed_facts INTO v_changed, v_facts FROM jupeb.board_status(ses) WHERE application_id = app;
        BEGIN PERFORM jupeb.board_mark(ARRAY[app], ses, 'CORRECTION_NEEDED', '', NULL, who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_note := split_part(msg, ':', 1); END;
        PERFORM jupeb.board_mark(ARRAY[app], ses, 'CORRECTED', 'Phone corrected', NULL, who, 'jupeb');
        SELECT changed, stage INTO v_after, v_stage FROM jupeb.board_status(ses) WHERE application_id = app;
        -- the syllabus covered: a lecture's topics are its course's
        INSERT INTO jupeb.timetable_slot (session, semester, subject_id, weekday, starts_at, ends_at, room_id, course_code)
        VALUES ('2031/2032', 1, gov, wd, '07:00', '08:00', (SELECT id FROM jupeb.room WHERE code = 'LR8'), 'GOV 001') RETURNING id INTO slot;
        reg := jupeb.open_lecture_register(slot, today, who);
        n_topics := (SELECT count(*) FROM jupeb.register_topics(reg));
        SELECT topic_id INTO t1 FROM jupeb.register_topics(reg) ORDER BY ord LIMIT 1;
        SELECT topic_id INTO t2 FROM jupeb.register_topics(reg) ORDER BY ord OFFSET 1 LIMIT 1;
        other_topic := (SELECT x.id FROM jupeb.unit_topic x JOIN jupeb.subject_unit u ON u.id = x.unit_id WHERE u.code = 'GOV 002' LIMIT 1);
        BEGIN PERFORM jupeb.set_register_topics(reg, ARRAY[t1, other_topic], who);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_topic := split_part(msg, ':', 1); END;
        PERFORM jupeb.set_register_topics(reg, ARRAY[t1, t2], who);
        v_covered := (SELECT covered FROM jupeb.coverage('2031/2032', 1) WHERE code = 'GOV 001');
        -- continuous assessment
        INSERT INTO jupeb.ca_component (session, code, title, max_score, ord) VALUES (ses, 'CHK199A', 'Test one', 10, 1) RETURNING id INTO c1;
        INSERT INTO jupeb.ca_component (session, code, title, max_score, ord) VALUES (ses, 'CHK199B', 'Assignment', 20, 2) RETURNING id INTO c2;
        BEGIN PERFORM jupeb.ca_save(app, gov, c1, 12, who, 'lecturer');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_range := split_part(msg, ':', 1); END;
        PERFORM jupeb.ca_save(app, gov, c1, 8, who, 'lecturer');
        PERFORM jupeb.ca_save(app, gov, c2, 15, who, 'lecturer');
        SELECT total, out_of, complete INTO v_total, v_out, v_complete FROM jupeb.ca_sheet(ses, gov, NULL) WHERE application_id = app;
        INSERT INTO jupeb.ca_lock (session, subject_id, locked_by) VALUES (ses, gov, who);
        BEGIN PERFORM jupeb.ca_save(app, gov, c1, 9, who, 'lecturer');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_locked := split_part(msg, ':', 1); END;
        -- a reminder, once
        INSERT INTO jupeb.calendar_event (session, starts_on, title, for_students) VALUES (ses, today + 7, 'Check 199 lecture-free day', true) RETURNING id INTO ev;
        v_rem1 := jupeb.send_calendar_reminders(now(), '');
        v_rem2 := jupeb.send_calendar_reminders(now(), '');
        n_rem := (SELECT count(*) FROM jupeb.calendar_reminder WHERE event_id = ev AND audience = 'STUDENTS');
        -- the examination timetable: uploaded, held until published; the option the student sits; no admit card uncleared
        n_before := (SELECT count(*) FROM jupeb.exam_schedule(app, false));
        v_upload := jupeb.exam_paper_upload(ses, jsonb_build_array(
            jsonb_build_object('row', 2, 'subject', 'GOV', 'paper', 'Government Paper I', 'kind', 'CBT', 'date', '2027-07-26', 'start', '09:00', 'end', '11:00'),
            jsonb_build_object('row', 3, 'subject', 'ISS', 'paper', 'Islamic Studies Paper I', 'kind', 'PAPER', 'date', '27/07/2027', 'start', '09:00', 'end', '11:00'),
            jsonb_build_object('row', 4, 'subject', 'CRS', 'paper', 'Christian Religious Studies Paper I', 'date', '2027-07-27', 'start', '09:00', 'end', '11:00'),
            jsonb_build_object('row', 5, 'subject', 'Astronomy', 'paper', 'Stars', 'date', '2027-07-28', 'start', '09:00', 'end', '11:00')), false, who);
        INSERT INTO jupeb.exam_timetable (session, published_at, published_by) VALUES (ses, now(), who)
        ON CONFLICT (session) DO UPDATE SET published_at = now();
        n_after := (SELECT count(*) FROM jupeb.exam_schedule(app, false) WHERE title LIKE '%Paper I');
        v_iss_papers := (SELECT count(*) FROM jupeb.exam_schedule(app, false) WHERE title LIKE 'Christian%');
        v_admit := jupeb.paper_facts(app, 'ADMIT_CARD', NULL, true);
        -- practice by topic; the mock
        INSERT INTO jupeb.practice_test (subject_id, title, questions_per_attempt, attempts_allowed, open) VALUES (gov, 'Check 199 practice', 1, 3, true) RETURNING id INTO tst;
        q1 := jupeb.practice_add(tst, jsonb_build_object('question', 'Q?', 'a', '1', 'b', '2', 'answer', 'A', 'course', 'gov001', 'topic', '1'));
        v_tagged := (SELECT unit_id IS NOT NULL AND topic_id IS NOT NULL FROM jupeb.practice_question WHERE id = q1);
        BEGIN PERFORM jupeb.practice_add(tst, jsonb_build_object('question', 'Q2?', 'a', '1', 'b', '2', 'answer', 'A', 'course', 'GOV 009'));
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_tag := split_part(msg, ':', 1); END;
        BEGIN INSERT INTO jupeb.practice_test (subject_id, title, kind, attempts_allowed, opens_at, closes_at) VALUES (gov, 'Check 199 bad mock', 'MOCK', 2, now(), now() + interval '1 hour');
        EXCEPTION WHEN check_violation THEN r_mock_ck := 'REFUSED'; END;
        INSERT INTO jupeb.practice_test (subject_id, title, kind, questions_per_attempt, attempts_allowed, open, opens_at, closes_at)
        VALUES (gov, 'Check 199 mock', 'MOCK', 1, 1, true, now() + interval '1 day', now() + interval '2 days') RETURNING id INTO mock;
        PERFORM jupeb.practice_add(mock, jsonb_build_object('question', 'M?', 'a', '1', 'b', '2', 'answer', 'A', 'course', 'GOV 001', 'topic', '1'));
        BEGIN PERFORM jupeb.practice_start(app, mock);
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_window := split_part(msg, ':', 1); END;
        UPDATE jupeb.practice_test SET opens_at = now() - interval '1 hour' WHERE id = mock;
        att := jupeb.practice_start(app, mock);
        PERFORM jupeb.practice_answer_set(app, att, (SELECT question_ids[1] FROM jupeb.practice_attempt WHERE id = att), 'A');
        PERFORM jupeb.practice_submit(app, att);
        v_paper := jupeb.practice_paper(app, att);
        n_topics_before := (SELECT count(*) FROM jupeb.practice_topics(app));
        UPDATE jupeb.practice_test SET results_released_at = now() WHERE id = mock;
        n_topics_after := (SELECT count(*) FROM jupeb.practice_topics(app));
        RAISE EXCEPTION 'the V355 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V355: to the Board only when ready, a change flagged until corrected; a lecture''s topics its course''s, counted to its coverage; an assessment within its maxima, locked against change; a reminder once; the examination timetable from an upload, published, the option sat; no admit card uncleared; practice by syllabus topic; a mock once, in its window, results held until released',
        'No passport photograph' = ANY (v_problems) AND 'Say which is taken: Christian / Islamic Religious Studies' = ANY (v_problems) AND r_notready = 'JUPEB_BOARD_NOT_READY' AND v_ready
        AND v_changed AND v_facts = ARRAY['phone'] AND r_note = 'JUPEB_BOARD_NOTE' AND NOT v_after AND v_stage = 'CORRECTED'
        AND n_topics > 1 AND r_topic = 'JUPEB_COVERAGE_TOPIC' AND v_covered = 2
        AND r_range = 'JUPEB_CA_RANGE' AND v_total = 23 AND v_out = 30 AND v_complete AND r_locked = 'JUPEB_CA_LOCKED'
        AND (v_rem1->>'students')::int >= 1 AND (v_rem2->>'students')::int = 0 AND n_rem = 1
        AND (v_upload->>'added')::int = 3 AND jsonb_array_length(v_upload->'refused') = 1 AND n_before = 0 AND n_after = 2 AND v_iss_papers = 0 AND v_admit IS NULL
        AND v_tagged AND r_tag = 'JUPEB_PRACTICE_TOPIC' AND r_mock_ck = 'REFUSED' AND r_window = 'JUPEB_MOCK_WINDOW'
        AND (v_paper->'attempt'->>'score') IS NULL AND (v_paper->'attempt'->>'resultsHeld')::boolean AND n_topics_before = 0 AND n_topics_after = 1,
        format('problems=%s notready=%s ready=%s changed=%s/%s note=%s after=%s/%s topics=%s topic=%s covered=%s range=%s total=%s/%s complete=%s locked=%s rem=%s/%s/%s upload=%s before=%s after=%s crs=%s admit=%s tagged=%s tag=%s mockck=%s window=%s paper=%s held=%s pt=%s/%s',
               v_problems, r_notready, v_ready, v_changed, v_facts, r_note, v_after, v_stage, n_topics, r_topic, v_covered, r_range, v_total, v_out, v_complete, r_locked,
               v_rem1, v_rem2, n_rem, v_upload, n_before, n_after, v_iss_papers, v_admit IS NULL, v_tagged, r_tag, r_mock_ck, r_window,
               v_paper->'attempt'->>'score', v_paper->'attempt'->>'resultsHeld', n_topics_before, n_topics_after));
END $$;

-- ── 200. V356: the next JUPEB session is set up from the last item by item, only into what it does not have of its own — the classes before the lectures and lecturers that name them (a class matched by name), a lecturer who has left not carried, the calendar a year on and planned; the fees only by the Bursary, into a session on the University's calendar; every carry on the record; a lecturer's practice by topic counts their classes only ──
DO $$
DECLARE who uuid := gen_random_uuid(); gone uuid := gen_random_uuid(); stays uuid := gen_random_uuid(); fr text := '2088/2089'; t text := '2089/2090'; msg text;
        gov uuid; ka uuid; kb uuid; ka2 uuid; v_plan_before text; r_first text; r_exists text; r_fees_office text; r_no_session text; r_later text; r_nothing text;
        v_classes jsonb; v_tt jsonb; v_lect jsonb; v_cal jsonb; v_fees jsonb; v_set jsonb; v_ca jsonb; v_pol jsonb;
        v_slot_class text; v_lect_class text; v_first_day date; v_planned boolean; v_fee numeric; v_plan_after text; n_log int;
        acct uuid; acct2 uuid; atp uuid; app1 uuid; app2 uuid; tst uuid; q uuid; att uuid; n_mine int; n_all int;
BEGIN
    BEGIN
        PERFORM set_config('moaum.actor_id', who::text, true);
        PERFORM set_config('moaum.actor_office', 'jupeb', true);
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
        INSERT INTO iam.person (id, surname, given_names) VALUES (who, 'CHECKROLL356', 'Officer');
        INSERT INTO iam.person (id, surname, given_names, ended_on, ended_reason) VALUES (gone, 'CHECKROLL356', 'Gone', current_date - 1, 'retired');
        INSERT INTO iam.person (id, surname, given_names) VALUES (stays, 'CHECKROLL356', 'Stays');
        gov := (SELECT id FROM jupeb.subject WHERE code = 'GOV');
        -- 2088/2089 as a session set up in full
        INSERT INTO jupeb.setting (session, application_prefix, screening_required, screening_venue, screening_starts_on, exam_month, updated_by)
        VALUES (fr, 'JUPEB/APP', true, 'JUPEB Hall', date '2088-11-02', 'July 2089', who);
        INSERT INTO jupeb.class (session, name, capacity, created_by) VALUES (fr, 'CHK A', 40, who) RETURNING id INTO ka;
        INSERT INTO jupeb.class (session, name, capacity, created_by) VALUES (fr, 'CHK B', 40, who) RETURNING id INTO kb;
        INSERT INTO jupeb.calendar_event (session, ord, starts_on, title, marker, for_students, created_by) VALUES (fr, 1, date '2088-09-25', 'Teaching commences 2088', 'TEACHING_STARTS', true, who);
        INSERT INTO jupeb.timetable_slot (session, semester, class_id, subject_id, weekday, starts_at, ends_at, room_id, course_code)
        VALUES (fr, 1, ka, gov, 2, '08:00', '09:00', (SELECT id FROM jupeb.room WHERE code = 'LR8'), 'GOV 001');
        INSERT INTO jupeb.ca_component (session, code, title, max_score, created_by) VALUES (fr, 'TEST1', 'First test', 15, who);
        INSERT INTO attendance.policy (context, session, min_percent, min_classes, updated_by) VALUES ('JUPEB', fr, 75, 5, who);
        INSERT INTO attendance.instructor (context, session, subject_ref, class_ref, person_id, assigned_by) VALUES ('JUPEB', fr, gov, ka, stays, who), ('JUPEB', fr, gov, NULL, gone, who);
        INSERT INTO jupeb.fee_setting (session, application_fee, checking_fee, acceptance_fee, first_percent, allow_full, activation, indigene_state, updated_by, updated_office)
        VALUES (fr, 16000, 1200, 16000, 60, true, 'FIRST_INSTALMENT', 'Benue', who, 'bursar');
        INSERT INTO jupeb.school_fee (session, category, indigene, amount, updated_by, updated_office) VALUES (fr, 'SCIENCE', false, 230000, who, 'bursar');
        v_plan_before := (SELECT string_agg(item || '=' || state, ',' ORDER BY item) FROM jupeb.rollover_plan(fr, t));
        -- the lectures and lecturers name classes the next session has not: the classes first
        BEGIN PERFORM jupeb.rollover_carry(fr, t, 'TIMETABLE', who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_first := split_part(msg, ':', 1); END;
        v_classes := jupeb.rollover_carry(fr, t, 'CLASSES', who, 'jupeb');
        BEGIN PERFORM jupeb.rollover_carry(fr, t, 'CLASSES', who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_exists := split_part(msg, ':', 1); END;
        v_tt := jupeb.rollover_carry(fr, t, 'TIMETABLE', who, 'jupeb');
        v_lect := jupeb.rollover_carry(fr, t, 'LECTURERS', who, 'jupeb');
        v_cal := jupeb.rollover_carry(fr, t, 'CALENDAR', who, 'jupeb');
        v_set := jupeb.rollover_carry(fr, t, 'SETTINGS', who, 'jupeb');
        v_ca := jupeb.rollover_carry(fr, t, 'CA_PARTS', who, 'jupeb');
        v_pol := jupeb.rollover_carry(fr, t, 'ATTENDANCE_POLICY', who, 'jupeb');
        ka2 := (SELECT id FROM jupeb.class WHERE session = t AND name = 'CHK A');
        v_slot_class := (SELECT k.name FROM jupeb.timetable_slot s JOIN jupeb.class k ON k.id = s.class_id WHERE s.session = t);
        v_lect_class := (SELECT coalesce(k.name, 'every class') FROM attendance.instructor i LEFT JOIN jupeb.class k ON k.id = i.class_ref WHERE i.session = t AND i.person_id = stays);
        SELECT starts_on, planned INTO v_first_day, v_planned FROM jupeb.calendar_event WHERE session = t;
        -- the fees: the Bursary's, into a session on the University's calendar; never the JUPEB Office's
        BEGIN PERFORM jupeb.rollover_carry(fr, t, 'FEES', who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_fees_office := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.carry_fees(fr, t, who, 'bursar');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_no_session := split_part(msg, ':', 1); END;
        INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), t, date '2089-09-01', date '2090-08-31') ON CONFLICT (name) DO NOTHING;
        v_fees := jupeb.carry_fees(fr, t, who, 'bursar');
        v_fee := jupeb.school_fee_amount(t, 'SCIENCE', false);
        BEGIN PERFORM jupeb.rollover_carry(t, fr, 'CLASSES', who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_later := split_part(msg, ':', 1); END;
        BEGIN PERFORM jupeb.rollover_carry('2090/2091', '2091/2092', 'CA_PARTS', who, 'jupeb');
        EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT; r_nothing := split_part(msg, ':', 1); END;
        v_plan_after := (SELECT string_agg(item || '=' || state, ',' ORDER BY item) FROM jupeb.rollover_plan(fr, t));
        n_log := (SELECT count(*) FROM jupeb.session_rollover WHERE from_session = fr AND to_session = t);
        -- a lecturer's classes only: two students, one in class A, practising Government by topic
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check200@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acct;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, class_id, state)
        VALUES (acct, fr, 'CHECK200/0001', 'CHECK', 'A', 'zz.check200@example.com', 'NON_SCIENCE', (SELECT id FROM jupeb.combination WHERE code = 'SC-001'), ka, 'STUDENT') RETURNING id INTO app1;
        INSERT INTO jupeb.account (email, password_hash) VALUES ('zz.check200b@example.com', '$2a$12$abcdefghijklmnopqrstuuabcdefghijklmnopqrstuvwxyz12345') RETURNING id INTO acct2;
        INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, email, stream, combination_id, class_id, state)
        VALUES (acct2, fr, 'CHECK200/0002', 'CHECK', 'B', 'zz.check200b@example.com', 'NON_SCIENCE', (SELECT id FROM jupeb.combination WHERE code = 'SC-001'), kb, 'STUDENT') RETURNING id INTO app2;
        INSERT INTO jupeb.practice_test (subject_id, title, duration_minutes, questions_per_attempt, attempts_allowed, show_answers, open) VALUES (gov, 'CHK topics', 10, 1, 5, true, true) RETURNING id INTO tst;
        INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, answer, unit_id, topic_id)
        SELECT tst, 1, 'Government is', 'x', 'y', 'A', u.id, (SELECT x.id FROM jupeb.unit_topic x WHERE x.unit_id = u.id ORDER BY x.ord LIMIT 1)
          FROM jupeb.subject_unit u WHERE u.code = 'GOV 001' RETURNING id INTO q;
        FOR att IN SELECT unnest(ARRAY[app1, app2]) LOOP
            INSERT INTO jupeb.practice_attempt (test_id, application_id, number, question_ids, ends_at, total, submitted_at) VALUES (tst, att, 1, ARRAY[q], now() + interval '1 hour', 1, now())
            RETURNING id INTO atp;
            INSERT INTO jupeb.practice_answer (attempt_id, question_id, chosen, correct) VALUES (atp, q, 'A', true);
        END LOOP;
        n_mine := (SELECT sum(students) FROM jupeb.practice_topics_classes(fr, gov, ARRAY[ka]));
        n_all := (SELECT sum(students) FROM jupeb.practice_topics_class(fr, gov, NULL));
        RAISE EXCEPTION 'the V356 check undoes its writes';
    EXCEPTION WHEN raise_exception THEN
        NULL;
    END;
    PERFORM pg_temp.assert('JUPEB V356: the next session from the last, item by item, never over its own; the classes first, matched by name; a lecturer who left not carried; the calendar a year on, planned; the fees the Bursary''s alone, into a session on the calendar; every carry recorded; a lecturer''s classes only',
        v_plan_before = 'ATTENDANCE_POLICY=READY,CALENDAR=READY,CA_PARTS=READY,CLASSES=READY,FEES=READY,LECTURERS=READY,SETTINGS=READY,TIMETABLE=READY'
        AND r_first = 'JUPEB_ROLLOVER_CLASSES_FIRST' AND (v_classes->>'carried')::int = 2 AND r_exists = 'JUPEB_ROLLOVER_EXISTS'
        AND (v_tt->>'carried')::int = 1 AND v_slot_class = 'CHK A' AND (v_lect->>'carried')::int = 1 AND (v_lect->>'skipped')::int = 1 AND v_lect_class = 'CHK A'
        AND (v_cal->>'carried')::int = 1 AND v_first_day = date '2089-09-25' AND v_planned
        AND (v_set->>'carried')::int = 1 AND (v_ca->>'carried')::int = 1 AND (v_pol->>'carried')::int = 1
        AND r_fees_office = 'JUPEB_ROLLOVER_FEES' AND r_no_session = 'JUPEB_ROLLOVER_NO_SESSION' AND (v_fees->>'carried')::int = 2 AND v_fee = 230000
        AND r_later = 'JUPEB_ROLLOVER_LATER' AND r_nothing = 'JUPEB_ROLLOVER_NOTHING'
        AND v_plan_after = 'ATTENDANCE_POLICY=DONE,CALENDAR=DONE,CA_PARTS=DONE,CLASSES=DONE,FEES=DONE,LECTURERS=DONE,SETTINGS=DONE,TIMETABLE=DONE' AND n_log = 8
        AND n_mine = 1 AND n_all = 2,
        format('before=%s first=%s classes=%s exists=%s tt=%s/%s lect=%s/%s cal=%s/%s/%s set=%s ca=%s pol=%s feesoffice=%s nosession=%s fees=%s/%s later=%s nothing=%s after=%s log=%s mine=%s all=%s',
               v_plan_before, r_first, v_classes, r_exists, v_tt, v_slot_class, v_lect, v_lect_class, v_cal, v_first_day, v_planned, v_set, v_ca, v_pol,
               r_fees_office, r_no_session, v_fees, v_fee, r_later, r_nothing, v_plan_after, n_log, n_mine, n_all));
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
