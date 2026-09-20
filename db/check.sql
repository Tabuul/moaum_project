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
\set EXPECTED 135

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
                           n = 28, n || ' offices (26 staff offices incl. the SIWES Coordinator V156, the applicant V021 and the student V026)');
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
            (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from)
        VALUES (gen_random_uuid(), v_p, 'hod', 'department', '   ',
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
           (gen_random_uuid(), v_p, 'hod', 'department', 'MCS',
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
    VALUES (gen_random_uuid(), '9999/0000', date '9999-01-01', date '9999-12-31');

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
        m2 IS NULL AND m1 = 'MOAUM/MTC/99/0001', coalesce(m1, '—') || ' issued; the queried one waits for the next run');

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
    INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, instrument, granted_by, valid_from, valid_to)
    VALUES (v_g, v_p, 'dean', 'faculty', 'check', gen_random_uuid(), current_date - 30, current_date - 1),
           (gen_random_uuid(), v_p, 'hod', 'department', 'check', gen_random_uuid(), current_date, NULL);
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
    PERFORM set_config('moaum.actor_office', 'applicant', true);
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
        ('CHK 101', 'Check Course One', 12, 1, 100, dept, 'Compulsory', 'LIVE'),
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
        ('CHK 201', 'Check Result One',   3, 1, 100, dept, 'Compulsory', 'LIVE'),
        ('CHK 202', 'Check Result Two',   3, 1, 100, dept, 'Elective',   'LIVE'),
        ('CHK 203', 'Check Result Three', 3, 1, 200, dept, 'Compulsory', 'LIVE');

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
        n >= 1 AND v_status = 'GRADUATED' AND v_notices = 2 AND g.senate_state = 'APPROVED' AND g.senate_minute = 'CHECK SEN/9999/7'
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
    INSERT INTO hostel.session_setting (session, fee, hold_hours) VALUES ('9999/0000', 40000, 72);
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
    -- a scholarship (a grant) of 150,000 credited by the Bursary, tagged with its source
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    v_entry := finance.credit_wallet(s3, '9999/0000', 150000, 'CHECK scholarship', 'SCHOLARSHIP');
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
        AND (SELECT source_code FROM finance.wallet_entry WHERE id = v_entry) = 'SCHOLARSHIP'
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
    PERFORM pg_temp.assert('The legacy migration creates the student, an approved registration, and a PUBLISHED result the transcript and GPA read',
        r.created = 1 AND stu IS NOT NULL
        AND g.results = 1 AND g.no_student = 1 AND g.registrations = 1
        AND (SELECT total FROM assessment.student_results(stu) WHERE course_code = 'ARC 999') = 75
        AND (SELECT published FROM assessment.student_results(stu) WHERE course_code = 'ARC 999')
        AND (SELECT gpa FROM assessment.student_gpa(stu) WHERE session = '9994/9995' AND semester = 1) IS NOT NULL,
        format('created=%s results=%s no_student=%s regs=%s', r.created, g.results, g.no_student, g.registrations));
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
