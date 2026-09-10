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
            ('provost',          '018', 'Provost',                  'institution', NULL),
            ('collegesecretary', '019', 'College Secretary',        'institution', NULL),
            ('library',          '020', 'Librarian',                'institution', NULL),
            ('security',         '021', 'Security',                 'institution', NULL),
            ('services',         '022', 'Student Services',         'institution', NULL),
            ('ict',              '023', 'ICT Directorate',          'platform',    NULL),
            ('admin',            '024', 'University Administrator', 'platform',    NULL),
            ('super',            '025', 'Super Administrator',      'platform',    NULL)
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

    -- ── the students: one at every level, ACTIVE, enrolled in the session ──
    FOR s IN
        SELECT * FROM (VALUES
            (100, 'MTC', 'C00023', 'Ayima',   '9901', '08030009901', 0),
            (200, 'ACC', 'C00019', 'Terhide', '9902', '08030009902', 1),
            (300, 'MTC', 'C00023', 'Mwuese',  '9903', '08030009903', 2),
            (400, 'ECO', 'C00024', 'Sesugh',  '9904', '08030009904', 3),
            (500, 'LAW', 'C00033', 'Doosuur', '9905', '08030009905', 4),
            (600, 'MED', 'C00061', 'Aondona', '9906', '08030009906', 5)
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
            VALUES (c.code, c.title, c.units, 1, 300, 'MTC', 'Compulsory', 'LIVE');
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

COMMIT;
