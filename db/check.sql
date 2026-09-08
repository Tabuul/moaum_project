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

    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

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
\set EXPECTED 63

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
    PERFORM pg_temp.assert('The office register carries all twenty-five offices',
                           n = 25, n || ' offices');
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
DECLARE c_id uuid := gen_random_uuid(); c_key text := '202699176777GF';
        v_n bigint; unread bigint; pending bigint;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- a candidate with a REAL registration number: the fixtures elsewhere
    -- use short invented ones, and the whole point here is the real shape
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
        v_n = 2, v_n || ' findings: no faculty quota distribution, and 28 of 92 '
        'programmes with no stated requirement');
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

    /* every programme the University runs has a rule */
    INSERT INTO admissions.programme_rule
        (policy_id, programme_code, cutoff, olevel_text, utme_text, de_text)
    SELECT v_id, code, NULL, 'five credits including English and Mathematics',
           'as JAMB prescribes', 'two A Level passes'
      FROM ref.programme;

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

-- ── 61. a cut-off under the faculty's is reported, not silently kept ────
DO $$
DECLARE v_id uuid; n int;
BEGIN
    PERFORM set_config('moaum.actor_id', gen_random_uuid()::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    SELECT id INTO v_id FROM admissions.session_policy WHERE session = '9999/0000';
    UPDATE admissions.programme_rule SET cutoff = 150
     WHERE policy_id = v_id AND programme_code = 'C00023';
    SELECT count(*) INTO n FROM admissions.policy_findings('9999/0000')
     WHERE finding = 'A programme cut-off is below its faculty''s';
    PERFORM pg_temp.assert('A programme cut-off below its faculty''s is a finding',
        n = 1, 'Computer Science at 150 under a Faculty of Science at 160');
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
