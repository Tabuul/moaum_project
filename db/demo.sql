-- ═══════════════════════════════════════════════════════════════════════════
-- demo.sql — invented accounts to walk the portal with
--
--   Every person here is invented. The surname is DEMO, the staff numbers
--   are MOAUM/DEMO/nnn, the matriculation numbers sit at the top of their
--   year (9901–9906) so a real matriculation run never meets them, and the
--   courses carry the DMO prefix. Nothing here is a real student, a real
--   member of staff, or a real JAMB candidate.
--
--   It is NOT a migration. migrate.sh does not run it; CI runs it twice to
--   prove it is idempotent, and an operator runs `bash db/demo.sh` against a
--   database they mean to demonstrate on. Running it on the University's
--   live database would put invented people on the register, so the runner
--   says so before it starts.
--
--   Every write is attributed, as every write must be (V002): the actor is
--   the fixed demo actor below, acting at the door the Directorate of ICT
--   operates, and the functions that read the acting office are called
--   under the office that would call them.
--
--   The password for every account is: Demo password 2026
-- ═══════════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-00000000de30', true);
SELECT set_config('moaum.actor_office', 'ict', true);

DO $$
DECLARE
    v_actor     uuid := '00000000-0000-0000-0000-00000000de30';
    v_pw        text := 'Demo password 2026';
    v_session   text;
    v_yy        text;
    v_person    uuid;
    v_lecturer  uuid;
    v_exams     uuid;
    v_hod       uuid;
    v_student   uuid;
    v_reg       uuid;
    v_exam      uuid;
    v_batch     uuid;
    v_made      int;
    v_none      int;
    v_app       uuid;
    v_att       uuid;
    v_ref       text;
    v_elig      uuid;
    o           record;
    s           record;
    c           record;
    elig        record;
BEGIN
    -- ── the session everything hangs in: the current one, else 2026/2027 ──
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT';
    IF v_session IS NULL THEN
        v_session := '2026/2027';
    END IF;
    v_yy := substr(v_session, 3, 2);

    -- ── the staff: one person per office, signing in as demo.<office> ──
    FOR o IN
        SELECT * FROM (VALUES
            ('lecturer',         '001', 'Lecturer',                 'department',  'MTC'),
            ('hod',              '002', 'Head Of Department',       'department',  'MTC'),
            ('exams',            '003', 'Examinations Officer',     'department',  'MTC'),
            ('facultyexams',     '004', 'Faculty Examinations',     'faculty',     'SC'),
            ('facultyofficer',   '005', 'Faculty Officer',          'faculty',     'SC'),
            ('dean',             '006', 'Dean',                     'faculty',     'SC'),
            ('records',          '007', 'Exams And Records',        'institution', NULL),
            ('academic',         '008', 'Academic Office',          'institution', NULL),
            ('dregistrar',       '009', 'Deputy Registrar',         'institution', NULL),
            ('registrar',        '010', 'Registrar',                'institution', NULL),
            ('dvc',              '011', 'Deputy Vice Chancellor',   'institution', NULL),
            ('vc',               '012', 'Vice Chancellor',          'institution', NULL),
            ('bursar',           '013', 'Bursar',                   'institution', NULL),
            ('audit',            '014', 'Internal Audit',           'institution', NULL),
            ('deputyaudit',      '015', 'Deputy Audit',             'institution', NULL),
            ('hrm',              '016', 'Human Resources',          'institution', NULL),
            ('housing',          '017', 'Housing',                  'institution', NULL),
            ('provost',          '018', 'Provost',                  'college',     'CHS'),
            ('collegesecretary', '019', 'College Secretary',        'college',     'CHS'),
            ('library',          '020', 'Librarian',                'institution', NULL),
            ('security',         '021', 'Security',                 'institution', NULL),
            ('services',         '022', 'Student Services',         'institution', NULL),
            ('ict',              '023', 'ICT Directorate',          'platform',    NULL),
            ('admin',            '024', 'University Administrator', 'platform',    NULL),
            ('super',            '025', 'Super Administrator',      'platform',    NULL),
            ('pgschool',         '026', 'PG School Dean',           'institution', NULL),
            ('pgsecretary',      '027', 'PG School Secretary',      'institution', NULL),
            ('financecontroller','028', 'Finance Controller',       'college',     'CHS')
        ) AS t(office, n, given, scope_kind, scope_id)
    LOOP
        SELECT id INTO v_person FROM iam.person WHERE staff_number = 'MOAUM/DEMO/' || o.n;
        IF v_person IS NULL THEN
            v_person := gen_random_uuid();
            INSERT INTO iam.person (id, staff_number, surname, given_names)
            VALUES (v_person, 'MOAUM/DEMO/' || o.n, 'DEMO', o.given);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a
                        WHERE a.person_id = v_person AND a.office_code = o.office
                          AND (a.valid_to IS NULL OR a.valid_to >= current_date)) THEN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), v_person, o.office, o.scope_kind, o.scope_id,
                    'Demo account (db/demo.sql) — invented person, no instrument exists', v_actor, current_date);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM iam.credential WHERE person_id = v_person) THEN
            INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
            VALUES (v_person, 'demo.' || o.office, crypt(v_pw, gen_salt('bf', 12)), false, v_actor);
            INSERT INTO iam.credential_event (id, person_id, kind, by_person, note)
            VALUES (gen_random_uuid(), v_person, 'SET', v_actor, 'demo account (db/demo.sql)');
        END IF;
        IF o.office = 'lecturer' THEN v_lecturer := v_person; END IF;
        IF o.office = 'exams'    THEN v_exams    := v_person; END IF;
        IF o.office = 'hod'      THEN v_hod      := v_person; END IF;
    END LOOP;

    -- ── a College lecturer (Human Anatomy, under the College of Health Sciences) who also coordinates 200 Level:
    --    two offices on one person, signing in as demo.mbbscoordinator (V250) ──
    DECLARE v_coord uuid;
    BEGIN
        SELECT id INTO v_coord FROM iam.person WHERE staff_number = 'MOAUM/DEMO/029';
        IF v_coord IS NULL THEN
            v_coord := gen_random_uuid();
            INSERT INTO iam.person (id, staff_number, surname, given_names) VALUES (v_coord, 'MOAUM/DEMO/029', 'DEMO', 'MBBS Coordinator');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = v_coord AND a.office_code = 'lecturer' AND (a.valid_to IS NULL OR a.valid_to >= current_date)) THEN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), v_coord, 'lecturer', 'department', 'ANT', 'Demo account (db/demo.sql) — invented person, no instrument exists', v_actor, current_date);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = v_coord AND a.office_code = 'mbbscoordinator' AND (a.valid_to IS NULL OR a.valid_to >= current_date)) THEN
            INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
            VALUES (gen_random_uuid(), v_coord, 'mbbscoordinator', 'level', '200', 'Demo account (db/demo.sql) — invented person, no instrument exists', v_actor, current_date);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM iam.credential WHERE person_id = v_coord) THEN
            INSERT INTO iam.credential (person_id, username, password_hash, must_change, set_by)
            VALUES (v_coord, 'demo.mbbscoordinator', crypt(v_pw, gen_salt('bf', 12)), false, v_actor);
            INSERT INTO iam.credential_event (id, person_id, kind, by_person, note)
            VALUES (gen_random_uuid(), v_coord, 'SET', v_actor, 'demo account (db/demo.sql)');
        END IF;
    END;

    -- ── the students: one at every level, ACTIVE, enrolled in the session ──
    FOR s IN
        SELECT * FROM (VALUES
            (100, 'MTC', 'C00023', 'Ayima',   '9901', '08030009901', 0),
            (200, 'ACC', 'C00019', 'Terhide', '9902', '08030009902', 1),
            (300, 'MTC', 'C00023', 'Mwuese',  '9903', '08030009903', 2),
            (400, 'ECO', 'C00024', 'Sesugh',  '9904', '08030009904', 3),
            (500, 'LAW', 'C00033', 'Doosuur', '9905', '08030009905', 4),
            (600, 'MED', 'C00061', 'Aondona', '9906', '08030009906', 5),
            -- a College of Health Sciences student (MBBS, faculty BAMS · college CHS) at 200 level,
            -- so the College student login gate can be demonstrated
            (200, 'MED', 'C00061', 'Terkimbi','9907', '08030009907', 1),
            -- a second College student at 200 level, entering this session: the later cohort, so two
            -- College years can stand at one level side by side (V249)
            (200, 'MED', 'C00061', 'Sewuese', '9908', '08030009908', 0)
        ) AS t(level, dept, programme, given, n, phone, years_in)
    LOOP
        DECLARE v_entry_year int := (substr(v_session, 1, 4))::int - s.years_in;
                v_matric text := 'MOAUM/' || s.dept || '/' || substr(v_entry_year::text, 3, 2) || '/' || s.n;
        BEGIN
            SELECT id INTO v_student FROM people.student WHERE matric_no = v_matric;
            IF v_student IS NULL THEN
                v_student := gen_random_uuid();
                INSERT INTO people.student (id, admission_no, matric_no, surname, other_names, programme_code, entry_mode,
                                            entry_session, entry_level, current_level, status, matriculated_at)
                VALUES (v_student, 'MOAUM/ADM/' || substr(v_entry_year::text, 3, 2) || '/99' || s.n, v_matric,
                        'DEMO', s.given || ' (' || s.level || ' Level)', s.programme, 'UTME',
                        v_entry_year || '/' || (v_entry_year + 1), 100, s.level, 'ACTIVE', now());
            END IF;
            IF NOT EXISTS (SELECT 1 FROM people.enrolment WHERE student_id = v_student AND session = v_session) THEN
                INSERT INTO people.enrolment (id, student_id, session, level) VALUES (gen_random_uuid(), v_student, v_session, s.level);
            END IF;
            IF NOT EXISTS (SELECT 1 FROM people.student_contact WHERE student_id = v_student) THEN
                INSERT INTO people.student_contact (student_id, email, phone)
                VALUES (v_student, 'demo.student' || s.level || '@example.com', s.phone);
            END IF;
            IF NOT EXISTS (SELECT 1 FROM iam.student_account WHERE student_id = v_student) THEN
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
                VALUES (gen_random_uuid(), v_student, crypt(v_pw, gen_salt('bf', 12)), false);
            END IF;
        END;
    END LOOP;

    -- ── the lecturer's results path: five demo courses at 300 level, offered
    --    this session, the 300-level student registered and approved, and
    --    the examination session opened so the score sheets exist ──
    FOR c IN
        SELECT * FROM (VALUES
            ('DMO 311', 'Algorithms and Complexity (demo)', 3),
            ('DMO 321', 'Database Systems (demo)',          3),
            ('DMO 331', 'Operating Systems (demo)',         3),
            ('DMO 341', 'Software Engineering (demo)',      3),
            ('DMO 351', 'Computer Networks (demo)',         3)
        ) AS t(code, title, units)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = c.code) THEN
            INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
            VALUES (c.code, c.title, c.units, 1, 300, 'MTC', 'Core', 'LIVE');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM catalogue.course_offer WHERE course_code = c.code AND programme_code = 'C00023' AND level = 300) THEN
            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis) VALUES (c.code, 'C00023', 300, 'Core');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM catalogue.offering WHERE course_code = c.code AND session = v_session AND semester = 1) THEN
            INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id, second_examiner_id, allocated_on)
            VALUES (gen_random_uuid(), c.code, v_session, 1, v_lecturer, v_exams, current_date);
        END IF;
    END LOOP;

    SELECT id INTO v_student FROM people.student WHERE matric_no LIKE 'MOAUM/MTC/%/9903';
    SELECT id INTO v_reg FROM registration.course_registration WHERE student_id = v_student AND session = v_session AND semester = 1;
    IF v_reg IS NULL THEN
        v_reg := gen_random_uuid();
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by)
        VALUES (v_reg, v_student, v_session, 1, 300, 'APPROVED', now(), now(), v_hod);
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
        SELECT v_reg, o2.id, c2.units, 'CURRENT', 'APPROVED'
          FROM catalogue.offering o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
         WHERE o2.session = v_session AND o2.semester = 1 AND o2.course_code LIKE 'DMO %';
    END IF;

    PERFORM set_config('moaum.actor_office', 'academic', true);
    SELECT id INTO v_exam FROM assessment.exam_session WHERE session = v_session AND semester = 1 AND kind = 'MAIN';
    IF v_exam IS NULL THEN
        v_exam := gen_random_uuid();
        INSERT INTO assessment.exam_session (id, session, semester, kind, exams_from, exams_to, sheets_due)
        VALUES (v_exam, v_session, 1, 'MAIN', current_date, current_date + 14, current_date + 42);
    END IF;
    IF (SELECT state FROM assessment.exam_session WHERE id = v_exam) = 'DRAFT' THEN
        SELECT * INTO v_made, v_none FROM assessment.open_exam_session(v_exam);
    END IF;
    -- an offering allocated after the session opened gets its sheet here, the way the Registry would
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), o2.id, v_exam, (SELECT sheets_due FROM assessment.exam_session WHERE id = v_exam)
      FROM catalogue.offering o2
     WHERE o2.session = v_session AND o2.semester = 1 AND o2.course_code LIKE 'DMO %'
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = o2.id);

    -- ── the Bursary: a schedule for the session, and a clearance scheme in force ──
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    IF NOT EXISTS (SELECT 1 FROM finance.fee_schedule WHERE session = v_session AND ended_at IS NULL) THEN
        INSERT INTO finance.fee_schedule (session, item, amount, ord) VALUES
            (v_session, 'School fees (demo schedule)', 100000, 1),
            (v_session, 'Portal and ICT charge (demo schedule)', 10000, 2);
    END IF;
    IF policy.in_force('clearance', 'UNIVERSITY', current_date) IS NULL THEN
        PERFORM finance.put_scheme_in_force('DEMO — BUR/DEMO/1, the recommended scheme, for demonstration', current_date);
    END IF;

    -- ── one demo student paid in full and carded, so fees, clearance and the
    --    identity card are all demonstrable end to end (best-effort; skipped if a
    --    precondition is not met, never breaking the rest of the demo) ──
    SELECT id INTO v_student FROM people.student WHERE matric_no LIKE 'MOAUM/MTC/%/9903';
    IF v_student IS NOT NULL AND NOT EXISTS (SELECT 1 FROM credentials.identity_card WHERE student_id = v_student AND state = 'ISSUED') THEN
        DECLARE v_due numeric; v_ref text;
        BEGIN
            SELECT due INTO v_due FROM finance.position(v_student, v_session);
            IF coalesce(v_due, 0) > 0 AND NOT finance.clears(v_student, v_session, 'ID_CARD') THEN
                v_ref := finance.new_reference(v_student, v_session, v_due, 'School fees ' || v_session || ' (demo)');
                PERFORM finance.confirm_payment(v_ref, 'Demo — bank transfer', 'Seeded so fees, clearance and the identity card are demonstrable');
            END IF;
            IF finance.clears(v_student, v_session, 'ID_CARD') THEN
                PERFORM set_config('moaum.actor_office', 'library', true);
                PERFORM credentials.issue_identity_card(v_student, 'Demo — first card');
                PERFORM set_config('moaum.actor_office', 'bursar', true);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'demo: could not clear and card the 300-level student (%): %', v_student, SQLERRM;
        END;
    END IF;

    -- ── some biodata for the 300-level demo student, so the biodata wizard shows real
    --    values (open-tier fields only; idempotent, never overwriting a later student edit) ──
    PERFORM set_config('moaum.actor_office', 'academic', true);
    SELECT id INTO v_student FROM people.student WHERE matric_no LIKE 'MOAUM/MTC/%/9903';
    IF v_student IS NOT NULL THEN
        INSERT INTO people.biodata (student_id, field, value) VALUES
            (v_student, 'preferred_name', 'Mwuese'),
            (v_student, 'marital_status', 'Single'),
            (v_student, 'religion', 'Christianity'),
            (v_student, 'place_of_birth', 'Makurdi, Benue State'),
            (v_student, 'mobile', '0803 000 9903'),
            (v_student, 'personal_email', 'demo.student300@example.com'),
            (v_student, 'term_address', 'Room B14, Akpehe Hall, MOAUM campus'),
            (v_student, 'home_address', '12 Ikpayongo Street, Wurukum, Makurdi, Benue State'),
            (v_student, 'city', 'Makurdi'),
            (v_student, 'state_of_residence', 'Benue'),
            (v_student, 'town', 'Naka'),
            (v_student, 'ethnic_group', 'Tiv'),
            (v_student, 'sponsorship', 'Parent or guardian'),
            (v_student, 'father_name', 'DEMO, Terhemba John'),
            (v_student, 'father_mobile', '0806 000 0001'),
            (v_student, 'mother_name', 'DEMO, Rebecca'),
            (v_student, 'kin_name', 'DEMO, Terhemba John'),
            (v_student, 'kin_relationship', 'Father'),
            (v_student, 'kin_mobile', '0806 000 0001'),
            (v_student, 'blood_group', 'O+'),
            (v_student, 'genotype', 'AA'),
            (v_student, 'bank_name', 'Demo Bank'),
            (v_student, 'bank_account_type', 'Savings')
        ON CONFLICT (student_id, field) DO NOTHING;
    END IF;

    -- ── the applicant: a demo row on a demo CAPS list, registered under the number ──
    PERFORM set_config('moaum.actor_office', 'academic', true);
    IF NOT EXISTS (SELECT 1 FROM admissions.applicant_fee WHERE session = v_session) THEN
        INSERT INTO admissions.applicant_fee (session, application_fee, portal_charge, acceptance_fee)
        VALUES (v_session, 2000, 300, 30000);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.caps_row WHERE session = v_session AND jamb_reg_no = '20269999DM') THEN
        v_batch := gen_random_uuid();
        INSERT INTO admissions.caps_batch (id, session, source, filename, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
        VALUES (v_batch, v_session, 'CAPS_DOWNLOAD', 'demo — not a CAPS file', 'UTME', digest('demo.sql ' || v_session, 'sha256'), 1,
                current_date, v_actor, 'academic');
        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
        VALUES (gen_random_uuid(), v_batch, v_session, '20269999DM', '{"demo": true}'::jsonb, 'DEMO', 'Applicant (invented)', 'C00023', 250, 'UTME', 'F', 'Benue', 'Makurdi');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.applicant_account a
                    WHERE a.candidate_id IN (SELECT id FROM admissions.candidate WHERE session = v_session AND jamb_reg_no = '20269999DM')) THEN
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        PERFORM admissions.register_applicant(v_session, '20269999DM', 'demo.applicant@example.com', '08030009910', crypt(v_pw, gen_salt('bf', 12)));
    END IF;

    -- ── ten fully-eligible applicants across four programmes ──────────────
    -- On the CAPS list with a UTME aggregate above any cut-off, registered and
    -- submitted, five O'Level credits (English and Mathematics among them), and
    -- a released screening score — so the merit engine proposes them and the
    -- Board can Record offers, decide and release. Every person is invented.
    IF NOT EXISTS (SELECT 1 FROM admissions.caps_row WHERE session = v_session AND jamb_reg_no = '20269901DA') THEN
        PERFORM set_config('moaum.actor_office', 'academic', true);
        v_elig := gen_random_uuid();
        INSERT INTO admissions.caps_batch (id, session, source, filename, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
        VALUES (v_elig, v_session, 'CAPS_DOWNLOAD', 'demo — eligible cohort (invented)', 'UTME',
                digest('demo.sql eligible ' || v_session, 'sha256'), 10, current_date, v_actor, 'academic');

        FOR elig IN SELECT * FROM (VALUES
                ('20269901DA', 'Ada Merit (invented)',     'C00023', 290, 'F', 'Benue',    'Makurdi',   78.0),
                ('20269902DA', 'Bem Merit (invented)',     'C00023', 276, 'M', 'Benue',    'Gboko',     71.0),
                ('20269903DA', 'Chidi Merit (invented)',   'C00023', 268, 'M', 'Enugu',    'Nsukka',    69.0),
                ('20269904DA', 'Doofan Merit (invented)',  'C00033', 285, 'F', 'Benue',    'Konshisha', 80.0),
                ('20269905DA', 'Emeka Merit (invented)',   'C00033', 272, 'M', 'Anambra',  'Awka',      74.0),
                ('20269906DA', 'Fatima Merit (invented)',  'C00033', 261, 'F', 'Benue',    'Otukpo',    66.0),
                ('20269907DA', 'Grace Merit (invented)',   'C00019', 279, 'F', 'Benue',    'Gwer West', 76.0),
                ('20269908DA', 'Hassan Merit (invented)',  'C00019', 254, 'M', 'Nasarawa', 'Lafia',     63.0),
                ('20269909DA', 'Iveren Merit (invented)',  'C64548', 283, 'F', 'Benue',    'Vandeikya', 77.0),
                ('20269910DA', 'John Merit (invented)',    'C64548', 259, 'M', 'Kogi',     'Lokoja',    64.0)
            ) AS t(jamb, names, prog, agg, sex, st, lga, putme)
        LOOP
            INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
            VALUES (gen_random_uuid(), v_elig, v_session, elig.jamb, '{"demo": true}'::jsonb, 'DEMO', elig.names, elig.prog, elig.agg, 'UTME', elig.sex, elig.st, elig.lga);

            PERFORM set_config('moaum.actor_office', 'applicant', true);
            PERFORM admissions.register_applicant(v_session, elig.jamb, 'demo.' || lower(elig.jamb) || '@example.com', '08030000000', crypt(v_pw, gen_salt('bf', 12)));

            PERFORM set_config('moaum.actor_office', 'academic', true);
            SELECT ap.id INTO v_app FROM admissions.application ap
              JOIN admissions.candidate cc ON cc.id = ap.candidate_id
             WHERE cc.session = v_session AND cc.jamb_key = elig.jamb;
            UPDATE admissions.application SET next_of_kin = 'DEMO Next of Kin · 0803 000 0000', submitted_at = now() WHERE id = v_app;

            v_att := gen_random_uuid();
            INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload)
            VALUES (v_att, v_session, 'OLEVEL', 'demo-eligible-' || elig.jamb, elig.jamb, 'COLUMN',
                ('{"sittings":[{"type":"WAEC","year":"2025","examNumber":"4100000","subjects":[' ||
                '{"subject":"English Language","grade":"B2"},{"subject":"Mathematics","grade":"B3"},' ||
                '{"subject":"Physics","grade":"C4"},{"subject":"Chemistry","grade":"C5"},' ||
                '{"subject":"Biology","grade":"B2"}]}]}')::jsonb);
            PERFORM admissions.olevel_from_attachment(v_att);

            UPDATE admissions.application SET screening_score = elig.putme, score_entered_at = now() WHERE id = v_app;
        END LOOP;

        -- release every entered score for the session, so the pool is eligible
        PERFORM set_config('moaum.actor_office', 'academic', true);
        PERFORM admissions.release_scores(v_session);

        -- take the first candidate all the way to ACCEPTED, so the admission
        -- letter is printable end to end; the rest wait for the Board to Record
        -- offers, decide and release in the portal.
        SELECT ap.id INTO v_app FROM admissions.application ap
          JOIN admissions.candidate cc ON cc.id = ap.candidate_id
         WHERE cc.session = v_session AND cc.jamb_key = '20269901DA';
        PERFORM admissions.decide_application(v_app, 'OFFERED', 'Demo merit offer (invented)');
        PERFORM admissions.release_decisions(v_session);
        PERFORM set_config('moaum.actor_office', 'applicant', true);
        PERFORM admissions.sign_undertaking(v_app);
        v_ref := admissions.new_fee_reference(v_app, 'ACCEPTANCE');
        PERFORM set_config('moaum.actor_office', 'bursar', true);
        PERFORM admissions.confirm_fee(v_ref, 'Card', 'Demo acceptance (invented)');
    END IF;

    -- ── polish: the eligible cohort reads the true stage on its own screen ──
    -- application_stage is a strict sequence — fee confirmed, submitted, seated
    -- for screening, scored, decided, accepted — so an applicant with a released
    -- score but no confirmed application fee or screening seat still shows "pay
    -- the application fee". Confirm the fee and seat them in a screening batch.
    -- This runs OUTSIDE the seed guard so it also repairs a cohort already
    -- seeded, and every step is idempotent.
    PERFORM set_config('moaum.actor_office', 'academic', true);
    UPDATE admissions.application a SET fee_confirmed_at = now()
      FROM admissions.candidate cc
     WHERE a.candidate_id = cc.id AND a.session = v_session
       AND cc.jamb_reg_no LIKE '202699%DA' AND a.fee_confirmed_at IS NULL;
    IF EXISTS (SELECT 1 FROM admissions.application a JOIN admissions.candidate cc ON cc.id = a.candidate_id
                WHERE a.session = v_session AND cc.jamb_reg_no LIKE '202699%DA'
                  AND a.submitted_at IS NOT NULL AND a.screening_batch_id IS NULL) THEN
        IF NOT EXISTS (SELECT 1 FROM admissions.screening_batch WHERE session = v_session AND label = 'DEMO') THEN
            INSERT INTO admissions.screening_batch (id, session, label, held_on, starts_at, ends_at, venue, capacity)
            VALUES (gen_random_uuid(), v_session, 'DEMO', current_date, '09:00', '12:00', 'Demo CBT Hall (invented)', 200);
        END IF;
        PERFORM admissions.assign_screening((SELECT id FROM admissions.screening_batch WHERE session = v_session AND label = 'DEMO'));
    END IF;

    RAISE NOTICE 'demo accounts ready for session % — password for every one: %', v_session, v_pw;
END $$;

-- ── the payroll (V069): put the demo staff on the establishment and run a month ──
DO $payroll$
DECLARE
    v_actor    uuid := '00000000-0000-0000-0000-00000000de30';
    v_builder  uuid; v_approver uuid; v_run uuid; v_prev date; v_cur date;
    emp record; v_grade text; v_cat text;
BEGIN
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'demo: payroll establishment and runs', true);

    FOR emp IN
        SELECT p.id AS pid, p.staff_number, min(a.office_code) AS office_code
          FROM iam.person p
          JOIN iam.office_assignment a ON a.person_id = p.id
         WHERE p.staff_number LIKE 'MOAUM/DEMO/%' AND p.ended_on IS NULL
         GROUP BY p.id, p.staff_number
    LOOP
        IF NOT EXISTS (SELECT 1 FROM hrm.employment WHERE person_id = emp.pid) THEN
            v_grade := CASE emp.office_code
                WHEN 'lecturer' THEN 'CONUASS 3'
                WHEN 'exams' THEN 'CONUASS 3'
                WHEN 'facultyexams' THEN 'CONUASS 3'
                WHEN 'hod' THEN 'CONUASS 5'
                WHEN 'dean' THEN 'CONUASS 7'
                WHEN 'provost' THEN 'CONUASS 7'
                WHEN 'financecontroller' THEN 'CONTISS 15'
                WHEN 'bursar' THEN 'CONTISS 15'
                WHEN 'registrar' THEN 'CONTISS 15'
                WHEN 'audit' THEN 'CONTISS 15'
                WHEN 'hrm' THEN 'CONTISS 15'
                WHEN 'library' THEN 'CONTISS 13'
                ELSE 'CONTISS 13' END;
            v_cat := CASE WHEN v_grade LIKE 'CONUASS%' THEN 'ACADEMIC' ELSE 'NON_ACADEMIC' END;
            INSERT INTO hrm.employment (person_id, staff_no, grade, step, category, appointment_date, status,
                                        bank_name, account_name, account_last4, pension_pin)
            VALUES (emp.pid, 'MOAUM/STAFF/' || right(emp.staff_number, 3), v_grade, 1, v_cat, date '2021-01-04', 'ACTIVE',
                    'Demo Bank (invented)', 'DEMO account', right(emp.staff_number, 4), 'PEN' || right(emp.staff_number, 6));
        END IF;
    END LOOP;

    SELECT a.person_id INTO v_builder FROM iam.office_assignment a WHERE a.office_code = 'hrm' LIMIT 1;
    SELECT a.person_id INTO v_approver FROM iam.office_assignment a WHERE a.office_code = 'super' LIMIT 1;
    v_prev := date_trunc('month', current_date - interval '1 month')::date;
    v_cur  := date_trunc('month', current_date)::date;

    -- last month: built, approved by a second officer, and paid
    IF v_builder IS NOT NULL AND v_approver IS NOT NULL AND v_builder <> v_approver
       AND NOT EXISTS (SELECT 1 FROM hrm.pay_run WHERE period = v_prev) THEN
        PERFORM set_config('moaum.actor_id', v_builder::text, true);
        PERFORM set_config('moaum.actor_office', 'hrm', true);
        PERFORM hrm.build_pay_run(v_prev, 'Regular monthly salary');
        SELECT id INTO v_run FROM hrm.pay_run WHERE period = v_prev;
        PERFORM set_config('moaum.actor_id', v_approver::text, true);
        PERFORM set_config('moaum.actor_office', 'super', true);
        PERFORM hrm.approve_pay_run(v_run);
        PERFORM hrm.pay_pay_run(v_run);
    END IF;

    -- this month: built, awaiting a second officer's approval
    IF v_builder IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hrm.pay_run WHERE period = v_cur) THEN
        PERFORM set_config('moaum.actor_id', v_builder::text, true);
        PERFORM set_config('moaum.actor_office', 'hrm', true);
        PERFORM hrm.build_pay_run(v_cur, 'Regular monthly salary');
    END IF;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo payroll ready: establishment seeded, % run(s)', (SELECT count(*) FROM hrm.pay_run);
END $payroll$;

-- ── inter-departmental transfer (V070): a case awaiting the committee, and one recommended, awaiting Senate ──
DO $xfer$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_academic uuid; s1 uuid; s2 uuid; p1 text; p2 text; v_app uuid;
BEGIN
    SELECT a.person_id INTO v_academic FROM iam.office_assignment a WHERE a.office_code = 'academic' LIMIT 1;
    SELECT id, programme_code INTO s1, p1 FROM people.student WHERE surname = 'DEMO' AND matric_no LIKE 'MOAUM/MTC/%' AND status = 'ACTIVE' ORDER BY matric_no LIMIT 1;
    SELECT id, programme_code INTO s2, p2 FROM people.student WHERE surname = 'DEMO' AND matric_no LIKE 'MOAUM/ACC/%' AND status = 'ACTIVE' ORDER BY matric_no LIMIT 1;

    IF s1 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.transfer_application WHERE student_id = s1 AND state IN ('APPLIED','RECOMMENDED','APPROVED')) THEN
        PERFORM set_config('moaum.actor_id', s1::text, true);
        PERFORM set_config('moaum.actor_office', 'student', true);
        v_app := people.apply_transfer(s1, (SELECT code FROM ref.programme WHERE NOT archived AND code <> p1 ORDER BY code LIMIT 1), 'I have a stronger passion for the course applied for.', 215);
        PERFORM set_config('moaum.actor_id', coalesce(v_academic, v_actor)::text, true);
        PERFORM set_config('moaum.actor_office', 'academic', true);
        PERFORM people.review_transfer(v_app, true, 200, 'Good academic standing; space available.');
    END IF;

    IF s2 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.transfer_application WHERE student_id = s2 AND state IN ('APPLIED','RECOMMENDED','APPROVED')) THEN
        PERFORM set_config('moaum.actor_id', s2::text, true);
        PERFORM set_config('moaum.actor_office', 'student', true);
        PERFORM people.apply_transfer(s2, (SELECT code FROM ref.programme WHERE NOT archived AND code <> p2 ORDER BY code LIMIT 1), 'Inability to cope in the current department.', 208);
    END IF;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo transfers ready: % application(s)', (SELECT count(*) FROM people.transfer_application);
END $xfer$;

-- ── staff leave (V071): one request awaiting a decision, one already approved ──
DO $leave$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; s1 uuid; s2 uuid; v_hr uuid; v_req uuid;
BEGIN
    SELECT em.person_id INTO s1 FROM hrm.employment em JOIN iam.person p ON p.id = em.person_id
      WHERE em.status = 'ACTIVE' AND p.staff_number LIKE 'MOAUM/DEMO/%' ORDER BY em.staff_no LIMIT 1;
    SELECT em.person_id INTO s2 FROM hrm.employment em JOIN iam.person p ON p.id = em.person_id
      WHERE em.status = 'ACTIVE' AND p.staff_number LIKE 'MOAUM/DEMO/%' AND em.person_id <> coalesce(s1, gen_random_uuid()) ORDER BY em.staff_no LIMIT 1;
    SELECT a.person_id INTO v_hr FROM iam.office_assignment a WHERE a.office_code = 'hrm' LIMIT 1;

    IF s1 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hrm.leave_request WHERE person_id = s1) THEN
        PERFORM set_config('moaum.actor_id', s1::text, true);
        PERFORM set_config('moaum.actor_office', 'lecturer', true);
        PERFORM hrm.request_leave(s1, 'ANNUAL', current_date + 14, current_date + 23, 'A departmental colleague', 'Annual rest');
    END IF;
    IF s2 IS NOT NULL AND v_hr IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hrm.leave_request WHERE person_id = s2) THEN
        PERFORM set_config('moaum.actor_id', s2::text, true);
        PERFORM set_config('moaum.actor_office', 'lecturer', true);
        v_req := hrm.request_leave(s2, 'CASUAL', current_date + 3, current_date + 4, NULL, 'Personal');
        PERFORM set_config('moaum.actor_id', v_hr::text, true);
        PERFORM set_config('moaum.actor_office', 'hrm', true);
        PERFORM hrm.decide_leave(v_req, true, NULL);
    END IF;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo leave ready: % request(s)', (SELECT count(*) FROM hrm.leave_request);
END $leave$;

-- ── staff movements (V072): a promotion approved but awaiting its instrument ──
DO $movement$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_hr uuid; v_reg uuid; s1 uuid; v_cur text; v_target text; v_mv uuid;
BEGIN
    SELECT a.person_id INTO v_hr FROM iam.office_assignment a WHERE a.office_code = 'hrm' LIMIT 1;
    SELECT a.person_id INTO v_reg FROM iam.office_assignment a WHERE a.office_code = 'registrar' LIMIT 1;
    SELECT em.person_id, em.grade INTO s1, v_cur FROM hrm.employment em JOIN iam.person p ON p.id = em.person_id
      WHERE em.status = 'ACTIVE' AND p.staff_number LIKE 'MOAUM/DEMO/%' AND em.category = 'NON_ACADEMIC' ORDER BY em.staff_no LIMIT 1;
    SELECT grade INTO v_target FROM hrm.grade WHERE category = 'NON_ACADEMIC' AND grade <> v_cur ORDER BY basic DESC LIMIT 1;

    IF s1 IS NOT NULL AND v_hr IS NOT NULL AND v_reg IS NOT NULL AND v_hr <> v_reg AND v_target IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM hrm.movement WHERE person_id = s1) THEN
        PERFORM set_config('moaum.actor_id', v_hr::text, true);
        PERFORM set_config('moaum.actor_office', 'hrm', true);
        v_mv := hrm.raise_movement(s1, 'PROMOTION', current_date, NULL, 'Due for promotion on merit', v_target, 1);
        PERFORM set_config('moaum.actor_id', v_reg::text, true);
        PERFORM set_config('moaum.actor_office', 'registrar', true);
        PERFORM hrm.approve_movement(v_mv);   -- left APPROVED: awaiting the instrument, so nothing has changed yet
    END IF;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo movements ready: % movement(s)', (SELECT count(*) FROM hrm.movement);
END $movement$;

-- ── recruitment (V073): an open vacancy with a scored shortlist ──
DO $recruit$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_hr uuid; v_vac uuid;
BEGIN
    SELECT a.person_id INTO v_hr FROM iam.office_assignment a WHERE a.office_code = 'hrm' LIMIT 1;
    PERFORM set_config('moaum.actor_id', coalesce(v_hr, v_actor)::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    IF NOT EXISTS (SELECT 1 FROM hrm.vacancy WHERE title = 'Lecturer II — Computer Science (demo)') THEN
        INSERT INTO hrm.vacancy (title, department, requirements, grade, category, closes_on, state)
        VALUES ('Lecturer II — Computer Science (demo)', 'Computer Science', 'Ph.D in Computer Science required; publications in accredited outlets.', 'CONUASS 3', 'ACADEMIC', current_date + 21, 'SHORTLISTING')
        RETURNING id INTO v_vac;
        INSERT INTO hrm.applicant (vacancy_id, name, email, qualification, publications, teaching_years, score, recommendation, state) VALUES
         (v_vac, 'DEMO Candidate One (invented)', 'demo.cand1@example.com', 'Ph.D Computer Science, 2023', 11, 4, 86, 'Invite', 'SHORTLISTED'),
         (v_vac, 'DEMO Candidate Two (invented)', 'demo.cand2@example.com', 'Ph.D Software Engineering, 2022', 8, 3, 81, 'Invite', 'SHORTLISTED'),
         (v_vac, 'DEMO Candidate Three (invented)', 'demo.cand3@example.com', 'M.Sc Computer Science, 2019', 2, 5, 52, 'Below the Ph.D requirement', 'REJECTED');
    END IF;
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo recruitment ready: % vacancy(ies)', (SELECT count(*) FROM hrm.vacancy);
END $recruit$;

-- ── appraisal (V074): one APER recorded for the current cycle ──
DO $appraisal$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_hr uuid; em record; v_session text;
BEGIN
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT';
    v_session := coalesce(v_session, '2026/2027');
    SELECT a.person_id INTO v_hr FROM iam.office_assignment a WHERE a.office_code = 'hrm' LIMIT 1;
    PERFORM set_config('moaum.actor_id', coalesce(v_hr, v_actor)::text, true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    SELECT em2.id, em2.person_id INTO em FROM hrm.employment em2 JOIN iam.person p ON p.id = em2.person_id
      WHERE em2.status = 'ACTIVE' AND em2.category = 'ACADEMIC' AND p.staff_number LIKE 'MOAUM/DEMO/%' ORDER BY em2.staff_no LIMIT 1;
    IF em.id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM hrm.appraisal WHERE person_id = em.person_id AND cycle = v_session) THEN
        INSERT INTO hrm.appraisal (employment_id, person_id, cycle, self_score, supervisor_score, aper_grade, publications, note, state)
        VALUES (em.id, em.person_id, v_session, 88, 84, 'A', 12, 'Strong teaching and research output', 'MODERATED');
    END IF;
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo appraisal ready: % record(s)', (SELECT count(*) FROM hrm.appraisal);
END $appraisal$;

-- ── data governance (V075): a demo data-subject request and DR drills ──
DO $gov$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_reg uuid;
BEGIN
    SELECT a.person_id INTO v_reg FROM iam.office_assignment a WHERE a.office_code = 'registrar' LIMIT 1;
    PERFORM set_config('moaum.actor_id', coalesce(v_reg, v_actor)::text, true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    IF NOT EXISTS (SELECT 1 FROM governance.dsr WHERE reference = 'DSR-DEMO-0001') THEN
        INSERT INTO governance.dsr (reference, kind, requester, received_on, due_on, state, note) VALUES
         ('DSR-DEMO-0001', 'ACCESS', 'DEMO alumnus (invented)', current_date - 4, current_date + 26, 'IN_PROGRESS', 'Demo request'),
         ('DSR-DEMO-0002', 'RECTIFICATION', 'DEMO student — name spelling (invented)', current_date - 12, current_date + 18, 'COMPLETED', 'Demo request');
    END IF;
    PERFORM set_config('moaum.actor_office', 'ict', true);
    IF NOT EXISTS (SELECT 1 FROM governance.dr_drill WHERE note = 'Demo drill') THEN
        INSERT INTO governance.dr_drill (kind, ran_on, rpo_minutes, rto_minutes, outcome, note) VALUES
         ('RESTORE_VERIFY', current_date, 4, NULL, 'PASSED', 'Demo drill'),
         ('FULL_DR', current_date - 30, 5, 31, 'PASSED', 'Demo drill');
    END IF;
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo governance ready: % DSR, % drill(s)', (SELECT count(*) FROM governance.dsr), (SELECT count(*) FROM governance.dr_drill);
END $gov$;

-- ── procurement, stores, assets and grants (V076) ──
DO $ops$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_bursar uuid;
BEGIN
    SELECT a.person_id INTO v_bursar FROM iam.office_assignment a WHERE a.office_code = 'bursar' LIMIT 1;
    PERFORM set_config('moaum.actor_id', coalesce(v_bursar, v_actor)::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);

    IF NOT EXISTS (SELECT 1 FROM expenditure.requisition WHERE reference LIKE 'RQ-DEMO%') THEN
        INSERT INTO expenditure.requisition (reference, item, description, cost_centre, value, state) VALUES
         ('RQ-DEMO-0001', '40 desktop computers', 'CBT Hall B refresh', 'ICT Directorate', 34000000, 'RAISED'),
         ('RQ-DEMO-0002', 'Laboratory reagents', 'Semester consumables', 'Health Sciences', 8400000, 'APPROVED'),
         ('RQ-DEMO-0003', 'Library book acquisition', '220 CCMAS-aligned titles', 'Library', 12100000, 'PO_RAISED');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expenditure.store_item WHERE code LIKE 'DEMO%') THEN
        INSERT INTO expenditure.store_item (code, name, unit, quantity, reorder_level, location) VALUES
         ('DEMO-A4', 'A4 paper', 'ream', 120, 40, 'Central Stores'),
         ('DEMO-TONER', 'Printer toner (black)', 'cartridge', 8, 12, 'Central Stores');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expenditure.asset WHERE tag LIKE 'DEMO%') THEN
        INSERT INTO expenditure.asset (tag, name, category, location, acquired_on, cost, condition, last_verified_on) VALUES
         ('DEMO/GEN/001', '100 KVA generator', 'Plant', 'Works yard', current_date - 800, 18500000, 'GOOD', current_date - 40),
         ('DEMO/VEH/002', 'University bus', 'Vehicle', 'Transport pool', current_date - 1200, 22000000, 'FAIR', current_date - 400);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expenditure.research_grant WHERE reference LIKE 'GR-DEMO%') THEN
        INSERT INTO expenditure.research_grant (reference, title, principal_investigator, sponsor, amount, currency, starts_on, ends_on, state) VALUES
         ('GR-DEMO-0001', 'Machine learning for crop yield prediction', 'Dr. T. Iorpuu (invented)', 'TETFund', 15000000, 'NGN', current_date - 90, current_date + 640, 'ACTIVE');
    END IF;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo expenditure ops ready: % requisition(s), % asset(s)', (SELECT count(*) FROM expenditure.requisition), (SELECT count(*) FROM expenditure.asset);
END $ops$;

-- ── CBT question bank (V077): a few questions for a demo course ──
DO $cbt$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30'; v_lect uuid; v_course text;
BEGIN
    SELECT a.person_id INTO v_lect FROM iam.office_assignment a WHERE a.office_code = 'lecturer' LIMIT 1;
    SELECT code INTO v_course FROM catalogue.course ORDER BY code LIMIT 1;
    PERFORM set_config('moaum.actor_id', coalesce(v_lect, v_actor)::text, true);
    PERFORM set_config('moaum.actor_office', 'lecturer', true);
    IF v_course IS NOT NULL AND NOT EXISTS (SELECT 1 FROM assessment.question WHERE course_code = v_course) THEN
        INSERT INTO assessment.question (course_code, topic, stem, options, answer, difficulty, marks) VALUES
         (v_course, 'Fundamentals', 'Which data structure works on a Last-In-First-Out basis?', '["Queue","Stack","Tree","Graph"]'::jsonb, 1, 'EASY', 1),
         (v_course, 'Fundamentals', 'What is the time complexity of binary search on a sorted array?', '["O(n)","O(n log n)","O(log n)","O(1)"]'::jsonb, 2, 'MEDIUM', 1),
         (v_course, 'Algorithms', 'Which algorithm is NOT a comparison sort?', '["Merge sort","Quick sort","Radix sort","Heap sort"]'::jsonb, 2, 'HARD', 2);
    END IF;
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo question bank ready: % question(s)', (SELECT count(*) FROM assessment.question);
END $cbt$;

-- ── sources of funding (V079): a NELFUND remittance, scholarships, an applied wallet and a paid withdrawal ──
DO $fund$
DECLARE v_actor uuid := '00000000-0000-0000-0000-00000000de30';
        v_session text; v_rows jsonb; v_appr uuid; v_payer uuid; s_paid uuid; s_apply uuid; w record;
BEGIN
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT';
    IF v_session IS NULL THEN v_session := '2026/2027'; END IF;
    -- once only (CI runs demo.sql twice)
    IF EXISTS (SELECT 1 FROM finance.nelfund_batch WHERE ref = 'NLF/DEMO/0001') THEN RETURN; END IF;

    -- two demo staff stand behind money leaving the wallet (the approver is not the payer)
    SELECT id INTO v_appr FROM iam.person WHERE staff_number LIKE 'MOAUM/DEMO/%' ORDER BY staff_number LIMIT 1;
    SELECT id INTO v_payer FROM iam.person WHERE staff_number LIKE 'MOAUM/DEMO/%' AND id <> v_appr ORDER BY staff_number LIMIT 1;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'bursar', true);

    -- a NELFUND remittance for the Accounting demo students, matched against the register (credits their wallets)
    SELECT jsonb_agg(jsonb_build_object('matricNo', matric_no, 'name', surname || ' ' || other_names, 'amount', '45000'))
      INTO v_rows FROM people.student WHERE surname = 'DEMO' AND matric_no LIKE 'MOAUM/ACC/%' AND status = 'ACTIVE';
    IF v_rows IS NOT NULL THEN
        PERFORM finance.load_nelfund_batch('NLF/DEMO/0001', v_session, current_date, 'Demo NELFUND remittance', v_rows);
    END IF;

    -- scholarships (grants): to the paid-in-full student, and to an Economics student so a balance is held
    SELECT id INTO s_paid FROM people.student WHERE matric_no LIKE 'MOAUM/MTC/%/9903' LIMIT 1;
    IF s_paid IS NOT NULL THEN
        PERFORM finance.credit_wallet(s_paid, v_session, 50000, 'TETFund merit scholarship 2026/2027 (demo)', 'SCHOLARSHIP');
    END IF;
    SELECT id INTO s_apply FROM people.student WHERE surname = 'DEMO' AND matric_no LIKE 'MOAUM/ECO/%' AND status = 'ACTIVE' LIMIT 1;
    IF s_apply IS NOT NULL THEN
        PERFORM finance.credit_wallet(s_apply, v_session, 60000, 'State bursary award 2026/2027 (demo)', 'SCHOLARSHIP');
    END IF;

    -- one Accounting student applies their NELFUND credit to the session charge (shows applied + reconciliation)
    BEGIN
        SELECT id INTO s_apply FROM people.student WHERE surname = 'DEMO' AND matric_no LIKE 'MOAUM/ACC/%' AND status = 'ACTIVE' ORDER BY matric_no LIMIT 1;
        IF s_apply IS NOT NULL THEN
            PERFORM set_config('moaum.actor_id', s_apply::text, true);
            PERFORM finance.apply_wallet(s_apply, v_session, NULL);
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;   -- best effort: needs an outstanding charge
    END;

    -- the paid-in-full student withdraws the scholarship excess: requested, approved, and paid by a second officer
    BEGIN
        IF s_paid IS NOT NULL AND v_appr IS NOT NULL AND v_payer IS NOT NULL THEN
            PERFORM set_config('moaum.actor_id', s_paid::text, true);
            SELECT * INTO w FROM finance.request_withdrawal(s_paid, v_session, 50000, 'Zenith Bank', '1234567890', 'DEMO Student');
            PERFORM set_config('moaum.actor_id', v_appr::text, true);
            PERFORM finance.approve_withdrawal(w.id);
            PERFORM set_config('moaum.actor_id', v_payer::text, true);
            PERFORM finance.pay_withdrawal(w.id, 'TRX/DEMO/0001');
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;   -- best effort: needs the fees cleared
    END;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo funding ready: % source(s), % wallet entr(ies)', (SELECT count(*) FROM finance.funding_source), (SELECT count(*) FROM finance.wallet_entry);
END $fund$;

-- ════════════════════════════════════════════════════════════════════════
--  A cohort at volume, to exercise the results module end to end:
--  two departments (Mathematics & Computer Science C00023, Accounting
--  C00019), a hundred students each, a prior 200-level semester published
--  (so a CGPA accumulates and the quarter who failed a course carry it
--  over) and the current 300-level semester published. Half pay their fees
--  in full, so their results clear while the other half are gated. All of
--  it computes into the senate broadsheet. Idempotent, invented (surname
--  DEMO), never for live data.
-- ════════════════════════════════════════════════════════════════════════
DO $bulk$
DECLARE
    v_session text; v_prev text; v_yy text; v_pw text := 'Demo password 2026';
    v_actor uuid := '00000000-0000-0000-0000-000000000000';
    v_lecturer uuid; v_exams uuid; d record; v_rows jsonb; v_due numeric; v_ref text; st record;
BEGIN
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT';
    IF v_session IS NULL THEN v_session := '2026/2027'; END IF;
    v_yy := substr(v_session, 3, 2);
    v_prev := (substr(v_session, 1, 4)::int - 1)::text || '/' || substr(v_session, 1, 4);

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM assessment.ensure_session(v_prev);   -- the prior session must exist before its offerings reference it
    SELECT person_id INTO v_lecturer FROM iam.office_assignment WHERE office_code = 'lecturer' AND valid_to IS NULL LIMIT 1;
    SELECT person_id INTO v_exams    FROM iam.office_assignment WHERE office_code = 'exams'    AND valid_to IS NULL LIMIT 1;

    -- ── the students: 100 per department, 300 level, matriculated and ACTIVE ──
    FOR d IN SELECT * FROM (VALUES
            ('MTC', 'C00023', 'DMC'),
            ('ACC', 'C00019', 'DAC')
        ) AS t(dept, prog, pfx)
    LOOP
        DECLARE v_ey int := substr(v_session, 1, 4)::int - 2; v_eyy text;
        BEGIN
            v_eyy := substr(v_ey::text, 3, 2);

            INSERT INTO people.student (id, matric_no, surname, other_names, sex, programme_code, entry_mode,
                                        entry_session, entry_level, current_level, status, matriculated_at)
            SELECT gen_random_uuid(), 'MOAUM/' || d.dept || '/' || v_eyy || '/' || lpad(i::text, 4, '0'),
                   'DEMO', d.dept || ' Student ' || i, CASE WHEN i % 2 = 0 THEN 'F' ELSE 'M' END,
                   d.prog, 'UTME', v_ey || '/' || (v_ey + 1), 100, 300, 'ACTIVE', now()
              FROM generate_series(1, 100) i
            ON CONFLICT (matric_no) DO NOTHING;

            INSERT INTO people.enrolment (id, student_id, session, level)
            SELECT gen_random_uuid(), s.id, v_session, 300
              FROM people.student s
             WHERE s.matric_no LIKE 'MOAUM/' || d.dept || '/' || v_eyy || '/%' AND s.surname = 'DEMO'
               AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = v_session);

            INSERT INTO people.student_contact (student_id, email, phone)
            SELECT s.id, lower(replace(s.matric_no, '/', '.')) || '@example.com', '080' || lpad((substring(s.matric_no from '....$'))::int::text, 8, '3')
              FROM people.student s
             WHERE s.matric_no LIKE 'MOAUM/' || d.dept || '/' || v_eyy || '/%' AND s.surname = 'DEMO'
               AND NOT EXISTS (SELECT 1 FROM people.student_contact c WHERE c.student_id = s.id);

            INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
            SELECT gen_random_uuid(), s.id, crypt(v_pw, gen_salt('bf', 12)), false
              FROM people.student s
             WHERE s.matric_no LIKE 'MOAUM/' || d.dept || '/' || v_eyy || '/%' AND s.surname = 'DEMO'
               AND NOT EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id);

            -- ── the courses and their offerings, 200-level (prior sem 2) and 300-level (current sem 1) ──
            INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
            SELECT d.pfx || ' ' || c.cnum, 'Demo ' || d.pfx || ' ' || c.cnum, 3, c.sem, c.lvl, d.dept, 'Core', 'LIVE'
              FROM (VALUES (201,200,2),(202,200,2),(203,200,2),(204,200,2),(205,200,2),
                           (301,300,1),(302,300,1),(303,300,1),(304,300,1),(305,300,1)) c(cnum, lvl, sem)
            ON CONFLICT (code) DO NOTHING;

            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis)
            SELECT d.pfx || ' ' || c.cnum, d.prog, c.lvl, 'Core'
              FROM (VALUES (201,200),(202,200),(203,200),(204,200),(205,200),
                           (301,300),(302,300),(303,300),(304,300),(305,300)) c(cnum, lvl)
            ON CONFLICT (course_code, programme_code, level) DO NOTHING;

            INSERT INTO catalogue.offering (id, course_code, session, semester, lecturer_id, second_examiner_id, allocated_on)
            SELECT gen_random_uuid(), d.pfx || ' ' || c.cnum,
                   CASE WHEN c.lvl = 200 THEN v_prev ELSE v_session END, c.sem, v_lecturer, v_exams, current_date
              FROM (VALUES (201,200,2),(202,200,2),(203,200,2),(204,200,2),(205,200,2),
                           (301,300,1),(302,300,1),(303,300,1),(304,300,1),(305,300,1)) c(cnum, lvl, sem)
             WHERE NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                WHERE o.course_code = d.pfx || ' ' || c.cnum
                                  AND o.session = CASE WHEN c.lvl = 200 THEN v_prev ELSE v_session END
                                  AND o.semester = c.sem);

            -- ── prior 200-level (semester 2): published results; a quarter fail course 203 → a carry-over ──
            SELECT jsonb_agg(jsonb_build_object('matric', m, 'course', crs, 'level', 200, 'units', 3, 'ca', ca, 'exam', ex))
              INTO v_rows
              FROM (
                SELECT 'MOAUM/' || d.dept || '/' || v_eyy || '/' || lpad(i::text, 4, '0') AS m,
                       d.pfx || ' ' || c.cnum AS crs,
                       least(40, round(t.total * 0.4))::int AS ca,
                       (t.total - least(40, round(t.total * 0.4)))::int AS ex
                  FROM generate_series(1, 100) i
                  CROSS JOIN (VALUES (201),(202),(203),(204),(205)) c(cnum)
                  CROSS JOIN LATERAL (SELECT CASE WHEN c.cnum = 203 AND i % 4 = 0 THEN 22
                                                  ELSE 40 + ((i * 7 + c.cnum) % 55) END AS total) t
              ) q;
            PERFORM assessment.import_legacy_semester(v_prev, 2, v_rows, true);

            -- ── current 300-level (semester 1): published results ──
            SELECT jsonb_agg(jsonb_build_object('matric', m, 'course', crs, 'level', 300, 'units', 3, 'ca', ca, 'exam', ex))
              INTO v_rows
              FROM (
                SELECT 'MOAUM/' || d.dept || '/' || v_eyy || '/' || lpad(i::text, 4, '0') AS m,
                       d.pfx || ' ' || c.cnum AS crs,
                       least(40, round(t.total * 0.4))::int AS ca,
                       (t.total - least(40, round(t.total * 0.4)))::int AS ex
                  FROM generate_series(1, 100) i
                  CROSS JOIN (VALUES (301),(302),(303),(304),(305)) c(cnum)
                  CROSS JOIN LATERAL (SELECT 40 + ((i * 11 + c.cnum) % 55) AS total) t
              ) q;
            PERFORM assessment.import_legacy_semester(v_session, 1, v_rows, true);
        END;
    END LOOP;

    -- ── the fees: half the cohort pays in full, so their results clear and the other half are gated ──
    PERFORM set_config('moaum.actor_office', 'bursar', true);
    FOR st IN
        SELECT s.id, s.matric_no FROM people.student s
         WHERE s.surname = 'DEMO' AND s.current_level = 300
           AND (s.matric_no LIKE 'MOAUM/MTC/%' OR s.matric_no LIKE 'MOAUM/ACC/%')
           AND (substring(s.matric_no from '....$'))::int % 2 = 0
           AND NOT finance.clears(s.id, v_session, 'RESULTS')
    LOOP
        SELECT due INTO v_due FROM finance.position(st.id, v_session);
        IF coalesce(v_due, 0) > 0 THEN
            v_ref := finance.new_reference(st.id, v_session, v_due, 'School fees ' || v_session || ' (demo cohort)');
            PERFORM finance.confirm_payment(v_ref, 'Demo — bank transfer', 'Seeded so results clear for half the cohort');
        END IF;
    END LOOP;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo cohort ready: % students, % published results',
        (SELECT count(*) FROM people.student WHERE surname = 'DEMO' AND current_level = 300),
        (SELECT count(*) FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sh.stage = 'PUBLISHED');
END $bulk$;

-- ════════════════════════════════════════════════════════════════════════
--  An admissions cohort at volume, to exercise the merit engine and the JAMB
--  template across every case. Four programmes — Law (C00033), MBBS (C00061),
--  Accounting (C00019), Economics (C00024) — under one in-force demo policy on
--  session 2098/2099, ~135 candidates each: 100 who qualify (spread across
--  National Merit, State Merit, ELG and Locality by origin and rank), and the
--  rest each a distinct violation — below the cut-off, no O'Level uploaded, or
--  O'Level without a Mathematics credit. The below-the-cut-off group hold five
--  credits, so they surface as reconsiderations with a suggested programme. The
--  merit list and the downloaded template compute all of it live. Demo only.
-- ════════════════════════════════════════════════════════════════════════
DO $adm$
DECLARE
    v_adm text := '2098/2099'; v_pol uuid; v_batch uuid; v_grp uuid; v_pw text := 'Demo password 2026';
    v_actor uuid := '00000000-0000-0000-0000-000000000000'; d record;
BEGIN
    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'academic', true);

    -- ── the policy in force, its criteria, catchment and grading ──
    SELECT id INTO v_pol FROM admissions.session_policy WHERE session = v_adm;
    IF v_pol IS NULL THEN
        v_pol := gen_random_uuid();
        INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, instrument, in_force, state)
        VALUES (v_pol, v_adm, 600, 70, 30, 80, 20, 'DEMO CAC/2098/1 — invented, for demonstration', tstzrange(now(), NULL), 'IN_FORCE');
    END IF;
    INSERT INTO admissions.selection_criterion (policy_id, criterion, percent) VALUES
        (v_pol, 'NATIONAL_MERIT', 40), (v_pol, 'STATE_MERIT', 30), (v_pol, 'ELG', 20), (v_pol, 'LOCALITY', 10)
    ON CONFLICT (policy_id, criterion) DO NOTHING;
    INSERT INTO admissions.catchment_lga (policy_id, lga)
    SELECT v_pol, x FROM (VALUES ('Makurdi'),('Gboko'),('Otukpo'),('Gwer West'),('Vandeikya')) l(x)
    ON CONFLICT (policy_id, lga) DO NOTHING;
    IF NOT EXISTS (SELECT 1 FROM admissions.olevel_grading WHERE session = v_adm) THEN
        INSERT INTO admissions.olevel_grading (session, subjects_counted, bonus_one_sitting, bonus_two_sittings) VALUES (v_adm, 5, 10, 6);
        INSERT INTO admissions.olevel_grade_point (session, grade, points)
        SELECT v_adm, g, p FROM (VALUES ('A1',10),('B2',8),('B3',6),('C4',4),('C5',3),('C6',2),('D7',0),('E8',0),('F9',0)) v(g, p);
    END IF;

    v_batch := (SELECT id FROM admissions.caps_batch WHERE session = v_adm AND list_kind = 'UTME' LIMIT 1);
    IF v_batch IS NULL THEN
        v_batch := gen_random_uuid();
        INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
        VALUES (v_batch, v_adm, 'CAPS_DOWNLOAD', 'UTME', '\xAD'::bytea, 540, current_date, v_actor, 'academic');
    END IF;

    FOR d IN SELECT * FROM (VALUES
            (1, 'C00033', 'LL.B (LAW)',       180),
            (2, 'C00061', 'MBBS',             200),
            (3, 'C00019', 'B.Sc. ACCOUNTING', 170),
            (4, 'C00024', 'B.Sc. ECONOMICS',  160)
        ) AS t(ix, code, pname, cutoff)
    LOOP
        INSERT INTO admissions.programme_rule (policy_id, programme_code, quota, cutoff, olevel_text, utme_text, de_text)
        VALUES (v_pol, d.code, 150, d.cutoff, 'Five credits including English and Mathematics', 'UTME as JAMB sent them', 'A-Level or equivalent')
        ON CONFLICT (policy_id, programme_code) DO NOTHING;

        -- the UTME subject requirement, so the combination reads correct or incorrect
        IF NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group WHERE policy_id = v_pol AND programme_code = d.code AND scope = 'UTME') THEN
            v_grp := gen_random_uuid();
            INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose) VALUES (v_grp, v_pol, d.code, 'UTME', 2);
            INSERT INTO admissions.rule_subject (group_id, subject) VALUES (v_grp, 'Mathematics'), (v_grp, 'Economics');
        END IF;

        -- the CAPS rows: 135 candidates, each bucket a UTME aggregate, origin and O'Level shape
        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
        SELECT gen_random_uuid(), v_batch, v_adm, '2098' || lpad((d.ix * 1000 + i)::text, 7, '0'),
               CASE WHEN i BETWEEN 96 AND 100    -- a wrong UTME combination: no Mathematics, no Economics
                    THEN jsonb_build_object('Subject1', 'Use of English', 'Subject2', 'Government', 'Subject3', 'Biology', 'Subject4', 'Literature')
                    ELSE jsonb_build_object('Subject1', 'Use of English', 'Subject2', 'Mathematics', 'Subject3', 'Economics', 'Subject4', 'Government') END,
               'DEMO', d.code || ' Applicant ' || i, d.code,
               CASE WHEN i <= 100 THEN d.cutoff + 5 + (i % 85)             -- qualifies
                    WHEN i <= 115 THEN d.cutoff - 15 - (i % 10)            -- below the cut-off
                    ELSE d.cutoff + 10 END,                               -- otherwise blocked by O'Level
               'UTME', CASE WHEN i % 2 = 0 THEN 'F' ELSE 'M' END,
               CASE WHEN i % 4 = 0 THEN 'Kano' ELSE 'Benue' END,
               CASE WHEN i % 3 = 0 THEN 'Makurdi' WHEN i % 5 = 0 THEN 'Gboko' ELSE 'Ushongo' END
          FROM generate_series(1, 135) i
         WHERE NOT EXISTS (SELECT 1 FROM admissions.caps_row r WHERE r.session = v_adm AND r.jamb_reg_no = '2098' || lpad((d.ix * 1000 + i)::text, 7, '0'));

        -- correct any rows seeded before the UTME subjects took the Subject1..4 shape
        UPDATE admissions.caps_row SET raw =
               CASE WHEN (substring(jamb_reg_no from '...$'))::int BETWEEN 96 AND 100
                    THEN jsonb_build_object('Subject1', 'Use of English', 'Subject2', 'Government', 'Subject3', 'Biology', 'Subject4', 'Literature')
                    ELSE jsonb_build_object('Subject1', 'Use of English', 'Subject2', 'Mathematics', 'Subject3', 'Economics', 'Subject4', 'Government') END
         WHERE session = v_adm AND jamb_code = d.code AND raw ? 'subjects';

        -- the candidate record for each CAPS row
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
        SELECT gen_random_uuid(), v_adm, r.jamb_reg_no, r.surname, r.other_names, d.pname, 'UTME', 100, 'PROPOSED', r.id
          FROM admissions.caps_row r
         WHERE r.session = v_adm AND r.jamb_code = d.code
           AND NOT EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.session = v_adm AND c.jamb_reg_no = r.jamb_reg_no);

        -- the applicant account and the submitted, screened, released application
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
        SELECT gen_random_uuid(), v_adm, c.id, upper(c.jamb_reg_no), lower(c.jamb_reg_no) || '@example.com', '08030000000', crypt(v_pw, gen_salt('bf', 12))
          FROM admissions.candidate c
         WHERE c.session = v_adm AND c.programme = d.pname
           AND NOT EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.candidate_id = c.id);

        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, submitted_at, fee_confirmed_at, screening_score, score_entered_at, score_released_at)
        SELECT gen_random_uuid(), a.id, a.candidate_id, v_adm,
               'APP/98/' || lpad((d.ix * 1000 + row_number() OVER (ORDER BY a.jamb_key))::text, 6, '0'),
               now(), now(), 45 + ((substring(a.jamb_key from '...$'))::int % 45), now(), now()
          FROM admissions.applicant_account a
         WHERE a.session = v_adm AND a.jamb_key IN (SELECT upper(jamb_reg_no) FROM admissions.candidate WHERE session = v_adm AND programme = d.pname)
           AND NOT EXISTS (SELECT 1 FROM admissions.application ap WHERE ap.candidate_id = a.candidate_id);

        -- O'Level: uploaded for the qualifiers, the below-cut-off group and the missing-Maths group;
        -- NOT uploaded for i in 116..125; the missing-Maths group (126..135) has no Mathematics credit
        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, payload)
        SELECT gen_random_uuid(), v_adm, 'OLEVEL', 'demo-olevel-' || c.jamb_key, c.jamb_key, 'COLUMN', '{}'::jsonb
          FROM admissions.candidate c
         WHERE c.session = v_adm AND c.programme = d.pname
           AND (substring(c.jamb_key from '...$'))::int NOT BETWEEN 116 AND 125
           AND NOT EXISTS (SELECT 1 FROM admissions.attachment at WHERE at.session = v_adm AND at.kind = 'OLEVEL' AND at.jamb_key = c.jamb_key);

        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_type_raw, exam_year, exam_number, ord)
        SELECT gen_random_uuid(), at.id, v_adm, at.jamb_key, 'WAEC', 'WAEC', '2097', 'DMO' || at.jamb_key, 1
          FROM admissions.attachment at
         WHERE at.session = v_adm AND at.kind = 'OLEVEL' AND at.source_name LIKE 'demo-olevel-%'
           AND at.jamb_key IN (SELECT upper(jamb_reg_no) FROM admissions.candidate WHERE session = v_adm AND programme = d.pname)
           AND NOT EXISTS (SELECT 1 FROM admissions.olevel_sitting st WHERE st.attachment_id = at.id);

        INSERT INTO admissions.olevel_grade (sitting_id, subject, grade)
        SELECT st.id, s.subject, s.grade
          FROM admissions.olevel_sitting st
          JOIN admissions.attachment at ON at.id = st.attachment_id
          CROSS JOIN LATERAL (
              SELECT * FROM (VALUES
                  ('English Language', 'B3'), ('Mathematics', 'B3'), ('Economics', 'C4'), ('Government', 'C5'), ('Biology', 'C6')
              ) full_set(subject, grade)
              WHERE (substring(st.jamb_key from '...$'))::int NOT BETWEEN 126 AND 135   -- the full five for everyone but the missing-Maths group
              UNION ALL
              SELECT * FROM (VALUES
                  ('English Language', 'B3'), ('Economics', 'C4'), ('Government', 'C5'), ('Biology', 'C6'), ('Chemistry', 'C4')
              ) no_maths(subject, grade)
              WHERE (substring(st.jamb_key from '...$'))::int BETWEEN 126 AND 135        -- five credits, but no Mathematics
          ) s
         WHERE st.session = v_adm
           AND at.jamb_key IN (SELECT upper(jamb_reg_no) FROM admissions.candidate WHERE session = v_adm AND programme = d.pname)
           AND NOT EXISTS (SELECT 1 FROM admissions.olevel_grade g WHERE g.sitting_id = st.id AND g.subject = s.subject);
    END LOOP;

    PERFORM set_config('moaum.actor_id', v_actor::text, true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    RAISE NOTICE 'demo admissions ready on %: % candidates across % programmes',
        v_adm, (SELECT count(*) FROM admissions.candidate WHERE session = v_adm),
        (SELECT count(*) FROM admissions.programme_rule WHERE policy_id = v_pol);
END $adm$;

-- ── a worked staff profile for the demo lecturer, so /me/profile opens full ──
DO $prof$
DECLARE v_person uuid;
BEGIN
    SELECT id INTO v_person FROM iam.person WHERE staff_number = 'MOAUM/DEMO/001';
    IF v_person IS NULL THEN RETURN; END IF;

    INSERT INTO hrm.staff_profile AS sp (
        person_id, email, phone, department, faculty, responsibility, scholar_url, orcid,
        research_interests, masters_graduated, phd_graduated,
        publications, grants, collaborations, conferences, assignments, innovations,
        patents, achievements, contributions)
    VALUES (
        v_person, 'demo.lecturer@example.com', '08030000001', 'Mathematics', 'Science',
        'Examinations Officer', 'https://scholar.google.com/citations?user=DEMO', '0000-0002-1825-0097',
        'Numerical analysis, optimisation and mathematical modelling of teaching outcomes.', 6, 2,
        '["Demo A. et al. (2023). A note on iterative solvers. J. Demo Maths, 12(3), 45-58.",
          "Demo A. (2021). Modelling attendance. Proc. Demo Conf., 210-219."]'::jsonb,
        '["TETFund Institution-Based Research 2024 - NGN 5,000,000",
          "MOAUM Senate Research Grant 2022 - NGN 1,200,000"]'::jsonb,
        '["University of Ibadan, Nigeria (local)", "University of Turin, Italy (international)"]'::jsonb,
        '["ICM Satellite, Abuja, 2022", "West African Maths Colloquium, Accra, 2023"]'::jsonb,
        '["NUC accreditation panel member, 2023 (national)"]'::jsonb,
        '["A low-cost classroom response system"]'::jsonb,
        '[]'::jsonb,
        '["Best Lecturer, Faculty of Science, 2021"]'::jsonb,
        '["Free JAMB coaching for rural secondary schools, Benue"]'::jsonb)
    ON CONFLICT (person_id) DO UPDATE SET
        email = excluded.email, phone = excluded.phone, department = excluded.department,
        faculty = excluded.faculty, responsibility = excluded.responsibility,
        scholar_url = excluded.scholar_url, orcid = excluded.orcid,
        research_interests = excluded.research_interests,
        masters_graduated = excluded.masters_graduated, phd_graduated = excluded.phd_graduated,
        publications = excluded.publications, grants = excluded.grants,
        collaborations = excluded.collaborations, conferences = excluded.conferences,
        assignments = excluded.assignments, innovations = excluded.innovations,
        patents = excluded.patents, achievements = excluded.achievements,
        contributions = excluded.contributions, updated_at = now();

    INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content)
    VALUES (v_person, 'image/png', 70,
        decode('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da6360000002000001e221bc330000000049454e44ae426082', 'hex'))
    ON CONFLICT (person_id) DO NOTHING;
END $prof$;

-- ── postgraduate applications (V202), a few in different states to work the desks ──
DO $pg$
DECLARE v_app uuid; v_ref text; v_hod uuid; v_dean uuid;
        v_student uuid; v_res uuid; v_reg uuid; v_courses uuid[]; e record;
        v_pdf bytea := decode('255044462d312e34', 'hex');   -- a stub "%PDF-1.4" byte string
BEGIN
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'demo: postgraduate applications', true);
    SELECT person_id INTO v_hod  FROM iam.office_assignment WHERE office_code = 'hod'      ORDER BY valid_from LIMIT 1;
    SELECT person_id INTO v_dean FROM iam.office_assignment WHERE office_code = 'pgschool' ORDER BY valid_from LIMIT 1;

    IF NOT EXISTS (SELECT 1 FROM admissions.pg_application) THEN
        -- 1 · M.Sc. Computer Science — submitted, waiting on the department
        v_app := admissions.pg_register('2025/2026', 'Terzungwe', 'Aondofa Grace',
                    'pg.demo1@example.com', '08030000001', crypt('pg-demo', gen_salt('bf', 12)), 'C90002');
        UPDATE admissions.pg_application SET
            prior_institution = 'University of Nigeria, Nsukka', prior_award = 'B.Sc. Computer Science',
            prior_class = 'Second Class (Upper)', prior_cgpa = 3.80, prior_year = 2022,
            proposal_title = 'Federated learning for low-resource clinics',
            proposal_text  = 'A study of privacy-preserving model training across rural health facilities.'
          WHERE id = v_app;
        INSERT INTO admissions.pg_referee (application_id, name, email, institution, position)
            VALUES (v_app, 'Prof. A. B. Ode', 'abode@unn.edu.ng', 'University of Nigeria, Nsukka', 'Professor');
        INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes)
            VALUES (v_app, 'TRANSCRIPT', 'transcript.pdf', 'application/pdf', v_pdf);
        v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
        PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        PERFORM admissions.pg_submit(v_app);

        -- 2 · Ph.D. Economics — recommended by the department, waiting on the School
        v_app := admissions.pg_register('2025/2026', 'Ngukwagh', 'Mimidoo Faith',
                    'pg.demo2@example.com', '08030000002', crypt('pg-demo', gen_salt('bf', 12)), 'C90005');
        UPDATE admissions.pg_application SET
            prior_institution = 'Benue State University, Makurdi', prior_award = 'M.Sc. Economics',
            prior_class = 'Distinction', prior_cgpa = 4.20, prior_year = 2020,
            proposal_title = 'Fiscal federalism and sub-national debt in Nigeria',
            proposal_text  = 'An empirical study of state borrowing since the 1999 constitution.'
          WHERE id = v_app;
        INSERT INTO admissions.pg_referee (application_id, name, email, institution, position)
            VALUES (v_app, 'Prof. C. D. Iorpev', 'cdiorpev@bsum.edu.ng', 'Benue State University', 'Professor');
        INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes)
            VALUES (v_app, 'TRANSCRIPT', 'msc-transcript.pdf', 'application/pdf', v_pdf);
        v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
        PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        PERFORM admissions.pg_submit(v_app);
        IF v_hod IS NOT NULL THEN
            PERFORM admissions.pg_dept_decide(v_app, true, 'A strong candidate with a fundable proposal.', v_hod);
        END IF;

        -- 3 · PGD Computer Science — offered, waiting on the applicant to accept
        v_app := admissions.pg_register('2025/2026', 'Iormember', 'Doosuur Peter',
                    'pg.demo3@example.com', '08030000003', crypt('pg-demo', gen_salt('bf', 12)), 'C90001');
        UPDATE admissions.pg_application SET
            prior_institution = 'Federal Polytechnic, Nasarawa', prior_award = 'HND Computer Science',
            prior_class = 'Upper Credit', prior_cgpa = 3.40, prior_year = 2021
          WHERE id = v_app;
        INSERT INTO admissions.pg_referee (application_id, name, email, institution, position)
            VALUES (v_app, 'Engr. E. F. Terwase', 'eftwase@fpn.edu.ng', 'Federal Polytechnic, Nasarawa', 'Chief Lecturer');
        INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes)
            VALUES (v_app, 'TRANSCRIPT', 'hnd-transcript.pdf', 'application/pdf', v_pdf);
        v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
        PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        PERFORM admissions.pg_submit(v_app);
        IF v_hod IS NOT NULL THEN
            PERFORM admissions.pg_dept_decide(v_app, true, 'Suitable for the diploma.', v_hod);
        END IF;
        IF v_dean IS NOT NULL THEN
            PERFORM admissions.pg_faculty_decide(v_app, true, 'Faculty recommends.', v_dean);
            PERFORM admissions.pg_spgs_decide(v_app, true, 'Offer a place.', v_dean);
            -- the applicant paid the checking fee to see the decision; the acceptance fee is still to pay
            v_ref := admissions.pg_new_fee_reference(v_app, 'CHECKING'); PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        END IF;

        -- 4 · M.Sc. Computer Science — admitted, registered, scored, and through to a cleared thesis,
        --     so the whole postgraduate vertical (coursework, results, register, research, Board) has data
        v_app := admissions.pg_register('2025/2026', 'Ikyernum', 'Manasseh Aondongu',
                    'pg.demo4@example.com', '08030000004', crypt('pg-demo', gen_salt('bf', 12)), 'C90002');
        UPDATE admissions.pg_application SET
            prior_institution = 'Benue State University, Makurdi', prior_award = 'B.Sc. Computer Science',
            prior_class = 'Second Class (Upper)', prior_cgpa = 3.90, prior_year = 2021,
            proposal_title = 'Federated learning for financial reporting quality',
            proposal_text  = 'A privacy-preserving machine-learning study of earnings quality.'
          WHERE id = v_app;
        INSERT INTO admissions.pg_referee (application_id, name, email, institution, position)
            VALUES (v_app, 'Prof. G. T. Utor', 'gtutor@moaum.edu.ng', 'Rev. Fr. M. O. Adasu University', 'Professor');
        INSERT INTO admissions.pg_document (application_id, kind, filename, content_type, bytes)
            VALUES (v_app, 'TRANSCRIPT', 'bsc-transcript.pdf', 'application/pdf', v_pdf);
        v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
        PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        PERFORM admissions.pg_submit(v_app);
        IF v_hod  IS NOT NULL THEN PERFORM admissions.pg_dept_decide(v_app, true, 'Admit.', v_hod); END IF;
        IF v_dean IS NOT NULL THEN PERFORM admissions.pg_faculty_decide(v_app, true, 'Faculty recommends.', v_dean); PERFORM admissions.pg_spgs_decide(v_app, true, 'Offer a place.', v_dean); END IF;
        -- the applicant paid the checking fee to see the decision and the acceptance fee to accept it
        -- (confirming the acceptance fee moves the offer to ACCEPTED); then the School admits
        v_ref := admissions.pg_new_fee_reference(v_app, 'CHECKING');   PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        v_ref := admissions.pg_new_fee_reference(v_app, 'ACCEPTANCE'); PERFORM admissions.pg_confirm_fee(v_ref, 'demo');
        v_student := admissions.pg_admit(v_app);

        -- the programme's courses (Policy 11)
        INSERT INTO admissions.pg_course (programme_code, code, title, units, kind, semester) VALUES
            ('C90002', 'CSC 801', 'Advanced Algorithms & Complexity', 3, 'CORE',     1),
            ('C90002', 'CSC 803', 'Research Methodology',             3, 'CORE',     1),
            ('C90002', 'CSC 805', 'Machine Learning',                 3, 'ELECTIVE', 1),
            ('C90002', 'CSC 899', 'Dissertation',                     6, 'RESEARCH', 1)
        ON CONFLICT (programme_code, code) DO NOTHING;

        -- register the coursework, endorse it, and record externally-moderated scores
        SELECT array_agg(id) INTO v_courses FROM admissions.pg_course
         WHERE programme_code = 'C90002' AND kind <> 'RESEARCH';
        v_reg := admissions.pg_register(v_student, '2025/2026', 1, 'FULL_TIME', v_courses);
        UPDATE admissions.pg_registration SET state = 'ENDORSED', endorsed_by = v_dean, endorsed_at = now() WHERE id = v_reg;
        FOR e IN SELECT ent.id AS entry_id, c.code FROM admissions.pg_registration_entry ent
                   JOIN admissions.pg_course c ON c.id = ent.course_id WHERE ent.registration_id = v_reg LOOP
            PERFORM admissions.pg_record_score(e.entry_id,
                CASE e.code WHEN 'CSC 801' THEN 30 WHEN 'CSC 803' THEN 28 ELSE 25 END,
                CASE e.code WHEN 'CSC 801' THEN 42 WHEN 'CSC 803' THEN 37 ELSE 30 END, v_dean);
        END LOOP;

        -- the research, carried through to a cleared thesis awaiting the Board
        v_res := admissions.pg_research_ensure(v_student);
        INSERT INTO admissions.pg_research_supervisor (research_id, person_id, name, role, is_external)
            VALUES (v_res, v_dean, 'Dr. J. Aondo', 'FIRST', false);
        INSERT INTO admissions.pg_research_panel (research_id, name, role, is_external) VALUES
            (v_res, 'Prof. G. Utor', 'CHAIR', false), (v_res, 'Prof. B. Okonkwo', 'EXTERNAL', true),
            (v_res, 'Dr. J. Aondo', 'SUPERVISOR', false), (v_res, 'Dr. M. Adaikwu', 'INTERNAL', false),
            (v_res, 'Dr. S. Ige', 'PGSR', false), (v_res, 'Dr. S. Ochoga', 'COORDINATOR', false);
        UPDATE admissions.pg_research SET
            topic = 'Federated learning for financial reporting quality', stage = 'CLEARED',
            proposal_submitted_at = now() - interval '120 days', proposal_approved_at = now() - interval '110 days',
            seminar_held_at = now() - interval '70 days', pgsr = 'Dr. S. Ige',
            title_registered_at = now() - interval '60 days', plagiarism_pct = 82,
            panel_constituted_at = now() - interval '40 days', draft_submitted_at = now() - interval '35 days',
            viva_held_at = now() - interval '20 days', viva_score = 78, viva_grade = 'A', viva_outcome = 'PASS_MINOR',
            final_submitted_at = now() - interval '8 days', cleared_at = now() - interval '3 days', updated_at = now()
          WHERE id = v_res;
        INSERT INTO admissions.pg_research_event (research_id, stage, note)
            VALUES (v_res, 'CLEARED', 'Cleared by the Secretary before binding (demo)');

        -- the School's external examiners (Policy 18)
        INSERT INTO admissions.pg_examiner (name, institution, field, tenure_from, tenure_to) VALUES
            ('Prof. B. Okonkwo', 'University of Ibadan', 'Computer Science', date '2024-01-01', date '2027-01-01'),
            ('Prof. C. Danjuma', 'Ahmadu Bello University, Zaria', 'Economics', date '2025-01-01', date '2028-01-01');

        -- 5 · a postgraduate carried over from the old portal, to prove the migration desk (V214/V215):
        --     the student is loaded, then a past session's registration + results (graded on the PG scale)
        --     and a completed research record — through the same functions Records → Migration uses
        PERFORM people.import_postgraduate(jsonb_build_array(jsonb_build_object(
            'matric', 'MOAU/SC/CSC/MSC/22/0007', 'name', 'Ortserga, Sesugh David',
            'programme', 'C90002', 'level', '800', 'sex', 'M', 'dob', '1994-02-11',
            'email', 'pg.legacy1@example.com', 'phone', '08030000077', 'entrySession', '2022/2023')));
        SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = 'MOAU/SC/CSC/MSC/22/0007';
        IF v_student IS NOT NULL THEN
            PERFORM admissions.import_legacy_pg_semester('2022/2023', 1,
                jsonb_build_array(
                    jsonb_build_object('matric','MOAU/SC/CSC/MSC/22/0007','course','CSC 801','title','Advanced Algorithms & Complexity','units','3','kind','CORE','ca','30','exam','45'),
                    jsonb_build_object('matric','MOAU/SC/CSC/MSC/22/0007','course','CSC 803','title','Research Methodology','units','3','kind','CORE','ca','28','exam','40')),
                true);
            PERFORM admissions.import_legacy_pg_research(jsonb_build_array(jsonb_build_object(
                'matric','MOAU/SC/CSC/MSC/22/0007','topic','A study of scheduling heuristics for stream processing',
                'supervisor','Dr. J. Aondo','supervisor2','Dr. M. Adaikwu','stage','AWARDED',
                'proposalApproved','2022-11-01','vivaHeld','2023-10-05','awardDate','2024-01-20',
                'vivaScore','80','vivaGrade','A','vivaOutcome','PASS_CLEAN')));
        END IF;
    END IF;
END $pg$;

COMMIT;
