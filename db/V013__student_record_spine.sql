-- ═══════════════════════════════════════════════════════════════════════════
-- V013 — the student record, and everything the Academic Office's screens
--        stand on
--
-- The Academic Office's menu has eighteen screens the portal did not yet
-- serve, and between them they read one relationship chain:
--
--   FACULTY → DEPARTMENT → PROGRAMME → STUDENT
--           → SESSION ENROLMENT → COURSE REGISTRATION → OFFERING → COURSE
--           → SCORE SHEET → DECISION → SENATE
--           → CLEARANCE → TRANSCRIPT · CERTIFICATE · GRADUATION
--
-- This migration lays that chain down once, in the schemas V001 reserved for
-- it: people (the student), catalogue and registration (courses and who is
-- registered for them), assessment (score sheets and the chain they pass),
-- clearance and credentials (what is released, and what holds it), records
-- (graduation). Nothing here invents a student, a course or a mark: the
-- registers are empty until the Academic Office brings the admitted
-- candidates onto them and the departments create their courses. What is
-- seeded is structure — the departments the programme table already names,
-- the clearance units, the classification bands — and settings the Office
-- amends on its own screen.
--
-- Three rules run through every table, and they are the same three as V006:
--   · nothing is deleted — a record is ENDED or SUPERSEDED with a date
--   · every write is attributed — every table is on the audit spine
--   · a number issued is never reused — matriculation, admission, transcript
--     and certificate numbers come from one series each, inside the
--     transaction that issues them (BR-007)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'V013: the student record spine, ICT/MOAUMPP/2026/01', true);
END $seed$;

-- ══ 1 · the structure: departments, and the College tier ══════════════════

CREATE TABLE ref.department (
    code         text PRIMARY KEY,
    name         text NOT NULL,
    faculty_code text NOT NULL REFERENCES ref.faculty(code),
    ended_on     date NULL
);

COMMENT ON TABLE ref.department IS
  'The departments the programme table already names by code. Named here '
  'from the programmes under each; the register (ICT/MOAUMPP/2026/01, '
  'Appendix A) is the authority when it disagrees. A code, once issued, is '
  'never reused — a department is ended, not deleted.';

INSERT INTO ref.department (code, name, faculty_code) VALUES
    ('ACC',  'Accounting',                                   'MS'),
    ('ADV',  'Advertising',                                  'CM'),
    ('ANT',  'Human Anatomy',                                'BAMS'),
    ('ARC',  'Architecture',                                 'AC'),
    ('ASS',  'Arts and Social Sciences Education',           'ED'),
    ('ATC',  'Home Economics',                               'TI'),
    ('BCH',  'Biochemistry',                                 'BAMS'),
    ('BIO',  'Biological Sciences',                          'SC'),
    ('BRC',  'Broadcasting',                                 'CM'),
    ('BSM',  'Business Management',                          'MS'),
    ('BTE',  'Business Education',                           'TI'),
    ('CHM',  'Chemistry',                                    'SC'),
    ('DCM',  'Development Communication Studies',            'CM'),
    ('ECO',  'Economics',                                    'SS'),
    ('EDF',  'Educational Foundations',                      'ED'),
    ('ENG',  'English',                                      'AR'),
    ('GEO',  'Geography',                                    'ES'),
    ('HKH',  'Human Kinetics and Health Education',          'ED'),
    ('HST',  'History',                                      'AR'),
    ('IND',  'Industrial and Technology Education',          'TI'),
    ('JMS',  'Journalism and Media Studies',                 'CM'),
    ('LAN',  'Languages and Linguistics',                    'AR'),
    ('LAW',  'Law',                                          'LW'),
    ('LIS',  'Library and Information Science',              'SS'),
    ('MCM',  'Mass Communication',                           'CM'),
    ('MED',  'Medicine and Surgery',                         'BAMS'),
    ('MLS',  'Medical Laboratory Science',                   'BAMS'),
    ('MTC',  'Mathematics and Computer Science',             'SC'),
    ('NUR',  'Nursing Sciences',                             'BAMS'),
    ('PGY',  'Human Physiology',                             'BAMS'),
    ('PHL',  'Philosophy',                                   'AR'),
    ('PHM',  'Pharmaceutical Sciences',                      'PS'),
    ('PHY',  'Physics',                                      'SC'),
    ('POL',  'Political Science',                            'SS'),
    ('PSY',  'Psychology',                                   'SS'),
    ('PUB',  'Public Administration',                        'MS'),
    ('PUR',  'Public Relations',                             'CM'),
    ('RAC',  'Religious Studies',                            'AR'),
    ('RAD',  'Radiography and Radiation Science',            'BAMS'),
    ('RAP',  'Religion and Philosophy',                      'AR'),
    ('SCM',  'Strategic Communications',                     'CM'),
    ('SME',  'Science and Mathematics Education',            'ED'),
    ('SOC',  'Sociology',                                    'SS'),
    ('THE',  'Theatre Arts',                                 'AR'),
    ('URP',  'Urban and Regional Planning',                  'ES');

-- every programme's department is now a department on the register
ALTER TABLE ref.programme
    ADD CONSTRAINT fk_programme_department FOREIGN KEY (dept_code) REFERENCES ref.department(code);

-- The College of Health Sciences sits above its faculties with officers of
-- its own (REC-MOAUMPP-001 P4), and runs a separate academic system by
-- decision of 6 September 2026 (CHS-MOAUMPP-001). What the portal needs is
-- the fact of the tier, not the College's academic model.
CREATE TABLE ref.college (
    code   text PRIMARY KEY,
    name   text NOT NULL,
    system text NULL,            -- the College's own system, where it has one
    url    text NULL
);
INSERT INTO ref.college (code, name, system, url) VALUES
    ('CHS', 'College of Health Sciences', 'CHS-AMS', NULL);

ALTER TABLE ref.faculty ADD COLUMN college_code text NULL REFERENCES ref.college(code);
UPDATE ref.faculty SET college_code = 'CHS' WHERE code = 'BAMS';

-- ══ 2 · the calendar: sessions with a state, semesters, unit limits ═══════

-- Exactly one session is current at a time, and no two overlap. Both are
-- constraints in the database, not checks on a form.
ALTER TABLE policy.academic_session
    ADD COLUMN state         text NOT NULL DEFAULT 'PLANNED',
    ADD COLUMN senate_minute text NULL,
    ADD COLUMN semesters     int  NOT NULL DEFAULT 2,
    ADD CONSTRAINT ck_session_state CHECK (state IN ('PLANNED','CURRENT','CLOSED')),
    ADD CONSTRAINT ck_session_semesters CHECK (semesters BETWEEN 1 AND 3),
    ADD CONSTRAINT ck_session_current_has_minute
        CHECK (state <> 'CURRENT' OR (senate_minute IS NOT NULL AND btrim(senate_minute) <> '')),
    ADD CONSTRAINT ex_session_no_overlap
        EXCLUDE USING gist (daterange(starts_on, ends_on, '[]') WITH &&);

CREATE UNIQUE INDEX uq_session_one_current ON policy.academic_session ((true)) WHERE state = 'CURRENT';

COMMENT ON COLUMN policy.academic_session.senate_minute IS
  'A session stays PLANNED until its Senate minute is recorded against it. '
  'Opening one early would let students register into a session the '
  'University has not resolved to run.';

-- the last session is over; this one waits on its minute, which the Academic
-- Office records on the Session and semester screen
UPDATE policy.academic_session SET state = 'CLOSED' WHERE name = '2025/2026';

CREATE TABLE policy.semester (
    id                      uuid PRIMARY KEY,
    session                 text NOT NULL REFERENCES policy.academic_session(name),
    number                  int  NOT NULL,
    lectures_from           date NULL,
    lectures_to             date NULL,
    registration_opens      date NULL,
    registration_closes     date NULL,
    late_registration_closes date NULL,
    exams_from              date NULL,
    exams_to                date NULL,
    results_due             date NULL,
    query_window            text NULL,
    state                   text NOT NULL DEFAULT 'NOT_YET_OPEN',
    UNIQUE (session, number),
    CONSTRAINT ck_semester_number CHECK (number BETWEEN 1 AND 3),
    CONSTRAINT ck_semester_state  CHECK (state IN ('NOT_YET_OPEN','OPEN','CLOSED')),
    CONSTRAINT ck_semester_lectures CHECK (lectures_to IS NULL OR lectures_from IS NULL OR lectures_to >= lectures_from),
    CONSTRAINT ck_semester_exams    CHECK (exams_to IS NULL OR exams_from IS NULL OR exams_to >= exams_from),
    CONSTRAINT ck_semester_reg      CHECK (registration_closes IS NULL OR registration_opens IS NULL
                                           OR registration_closes >= registration_opens)
);

COMMENT ON TABLE policy.semester IS
  'Every date here changes what a student can do today. Moving a closing '
  'date backwards after it has passed does not un-register anybody: '
  'registrations are records, and records are not deleted.';

-- Per level: the minimum and maximum units a semester registration may carry.
-- The figures are the prototype''s working defaults and are amended on the
-- Session and semester screen; the Senate minute that fixes them is recorded
-- there.
CREATE TABLE policy.level_limit (
    level           int  PRIMARY KEY,
    applies_to      text NOT NULL,
    min_units       int  NOT NULL,
    max_units       int  NOT NULL,
    carryover_counts boolean NOT NULL DEFAULT true,
    instrument      text NULL,
    CONSTRAINT ck_level_limit_range CHECK (min_units >= 0 AND max_units >= min_units),
    CONSTRAINT ck_level_limit_level CHECK (level IN (100,200,300,400,500,600))
);
INSERT INTO policy.level_limit (level, applies_to, min_units, max_units) VALUES
    (100, 'All programmes', 15, 27),
    (200, 'All programmes', 15, 27),
    (300, 'All programmes', 15, 27),
    (400, 'All programmes', 15, 24),
    (500, 'MBBS, LL.B and other five-year programmes', 15, 24),
    (600, 'MBBS', 15, 24);

-- the classification table, versioned like the grading scheme it sits beside
CREATE TABLE policy.classification_band (
    version_id uuid NOT NULL REFERENCES policy.version(id) ON DELETE RESTRICT,
    class      text NOT NULL,
    low        numeric(3,2) NOT NULL,
    high       numeric(3,2) NOT NULL,
    ord        int  NOT NULL,
    PRIMARY KEY (version_id, class),
    CONSTRAINT ck_class_range CHECK (high >= low AND low >= 0 AND high <= 5),
    CONSTRAINT ex_class_no_overlap
        EXCLUDE USING gist (version_id WITH =, numrange(low, high, '[]') WITH &&)
);
DO $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    INSERT INTO policy.version (id, kind, scope, validity, instrument, decided_by)
    VALUES (v, 'classification', 'UNIVERSITY', daterange(date '2015-10-01', NULL), 'SEN/2015/44', 'registrar');
    INSERT INTO policy.classification_band (version_id, class, low, high, ord) VALUES
        (v, 'First Class Honours',           4.50, 5.00, 1),
        (v, 'Second Class Honours (Upper)',  3.50, 4.49, 2),
        (v, 'Second Class Honours (Lower)',  2.40, 3.49, 3),
        (v, 'Third Class Honours',           1.50, 2.39, 4),
        (v, 'Pass',                          1.00, 1.49, 5);
END $$;

CREATE OR REPLACE FUNCTION policy.class_of(p_cgpa numeric, p_at date DEFAULT current_date)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT b.class
      FROM policy.classification_band b
     WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', p_at)
       AND p_cgpa BETWEEN b.low AND b.high
     LIMIT 1
$$;

-- ══ 3 · the numbers the University issues ═════════════════════════════════

-- One series per kind, scope and session, moved inside the transaction that
-- issues the number. Gaps are acceptable; duplicates never (DSN §9).
CREATE OR REPLACE FUNCTION platform.next_number(p_kind text, p_scope text, p_session text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE v bigint;
BEGIN
    INSERT INTO platform.number_series (kind, scope, session, next_value)
    VALUES (p_kind, p_scope, p_session, 2)
    ON CONFLICT (kind, scope, session) DO UPDATE SET next_value = platform.number_series.next_value + 1
    RETURNING next_value - 1 INTO v;
    RETURN v;
END;
$$;

-- ══ 4 · the student ═══════════════════════════════════════════════════════

-- A student exists on this register from the moment an admitted candidate is
-- brought onto it with an ADMISSION NUMBER. The matriculation number comes
-- later, in one run over the confirmed faculty lists, and once issued it is
-- immutable (BR-007, I-STU-1). The admission number is retired, not deleted:
-- a receipt issued under it must still resolve years later.
CREATE TABLE people.student (
    id                 uuid PRIMARY KEY,
    person_id          uuid NULL REFERENCES iam.person(id),
    candidate_id       uuid NULL REFERENCES admissions.candidate(id),
    admission_no       text NULL UNIQUE,
    matric_no          text NULL UNIQUE,
    jamb_reg_no        text NULL,
    surname            text NOT NULL,
    other_names        text NOT NULL,
    sex                text NULL,
    date_of_birth      date NULL,
    programme_code     text NOT NULL REFERENCES ref.programme(code),
    entry_mode         text NOT NULL,
    entry_session      text NOT NULL,
    entry_level        int  NOT NULL,
    current_level      int  NOT NULL,
    curriculum_version text NULL,
    status             text NOT NULL DEFAULT 'ADMITTED',
    matriculated_at    timestamptz NULL,
    matriculation_run  uuid NULL,
    CONSTRAINT ck_student_status CHECK (status IN
        ('ADMITTED','ACTIVE','PROBATION','DEFERRED','SUSPENDED','RUSTICATED','WITHDRAWN',
         'EXPELLED','TRANSFERRED_OUT','GRADUATED','DECEASED','DORMANT')),
    CONSTRAINT ck_student_entry CHECK (entry_mode IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH')),
    CONSTRAINT ck_student_sex   CHECK (sex IS NULL OR sex IN ('F','M')),
    CONSTRAINT ck_student_level CHECK (current_level IN (100,200,300,400,500,600) AND entry_level IN (100,200,300,400,500,600)),
    CONSTRAINT ck_student_matric_shape CHECK (matric_no IS NULL OR matric_no ~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$'),
    CONSTRAINT ck_student_admission_shape CHECK (admission_no IS NULL OR admission_no ~ '^MOAUM/ADM/[0-9]{2}/[0-9]{6}$'),
    CONSTRAINT ck_student_matriculated CHECK ((matric_no IS NULL) = (matriculated_at IS NULL)),
    CONSTRAINT ck_student_active_has_matric CHECK (status = 'ADMITTED' OR matric_no IS NOT NULL)
);

CREATE INDEX ix_student_programme ON people.student (programme_code);
CREATE INDEX ix_student_name ON people.student (upper(surname), upper(other_names));

-- a matriculation number is never changed once issued
CREATE OR REPLACE FUNCTION people.matric_is_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.matric_no IS NOT NULL AND NEW.matric_no IS DISTINCT FROM OLD.matric_no THEN
        RAISE EXCEPTION 'the matriculation number % is permanent and is not changed', OLD.matric_no
            USING ERRCODE = 'check_violation',
                  HINT = 'BR-007. A wrong number is a records question for the Registrar, not an edit.';
    END IF;
    IF OLD.admission_no IS NOT NULL AND NEW.admission_no IS DISTINCT FROM OLD.admission_no THEN
        RAISE EXCEPTION 'the admission number % is retired, not changed', OLD.admission_no
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_student_matric_immutable
    BEFORE UPDATE ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.matric_is_immutable();

-- every status change carries its instrument (I-STU-3, FR-SIM-006/012)
CREATE TABLE people.status_change (
    id           uuid PRIMARY KEY,
    student_id   uuid NOT NULL REFERENCES people.student(id),
    from_status  text NOT NULL,
    to_status    text NOT NULL,
    instrument   text NOT NULL,
    effective_on date NOT NULL,
    expires_on   date NULL,
    reason       text NULL,
    CONSTRAINT ck_status_change_instrument CHECK (length(btrim(instrument)) > 0)
);

CREATE OR REPLACE FUNCTION people.change_status(p_student uuid, p_to text, p_instrument text,
                                                p_effective date, p_reason text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_from text;
BEGIN
    SELECT status INTO v_from FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found';
    END IF;
    IF p_instrument IS NULL OR btrim(p_instrument) = '' THEN
        RAISE EXCEPTION 'a change of status is made on an instrument — the Senate minute, the letter, the '
                        'Registrar''s decision — and none was cited'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
    VALUES (gen_random_uuid(), p_student, v_from, p_to, p_instrument, p_effective, p_reason);
    UPDATE people.student SET status = p_to WHERE id = p_student;
END;
$$;

-- one enrolment per session (I-STU-6)
CREATE TABLE people.enrolment (
    id           uuid PRIMARY KEY,
    student_id   uuid NOT NULL REFERENCES people.student(id),
    session      text NOT NULL REFERENCES policy.academic_session(name),
    level        int  NOT NULL,
    mode         text NOT NULL DEFAULT 'FULL_TIME',
    fee_category text NULL,
    enrolled_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, session),
    CONSTRAINT ck_enrolment_level CHECK (level IN (100,200,300,400,500,600))
);

-- ── biodata: three kinds of field, and the difference matters ─────────────
-- Most of the record is the student's own and changes freely; a few fields
-- are read from JAMB and corrected with JAMB; a few more change only on
-- evidence the Registry has seen. The field list is data, so a section can
-- be added without a migration of the record.
CREATE TABLE ref.biodata_field (
    field    text PRIMARY KEY,
    section  text NOT NULL,
    label    text NOT NULL,
    tier     text NOT NULL,
    hint     text NULL,
    wide     boolean NOT NULL DEFAULT false,
    ord      int  NOT NULL,
    CONSTRAINT ck_biodata_tier CHECK (tier IN ('open','locked','approval')),
    CONSTRAINT ck_biodata_section CHECK (section IN
        ('personal','contact','origin','family','kin','health','bank'))
);
INSERT INTO ref.biodata_field (field, section, label, tier, hint, wide, ord) VALUES
    ('preferred_name',   'personal', 'Preferred name',            'open',     'Used in the portal and in correspondence; not on credentials', false, 10),
    ('marital_status',   'personal', 'Marital status',            'open',     NULL, false, 11),
    ('religion',         'personal', 'Religion',                  'open',     'Optional. Used only for chaplaincy and dietary arrangements', false, 12),
    ('nationality',      'personal', 'Nationality',               'approval', 'A change of nationality affects fee status', false, 13),
    ('place_of_birth',   'personal', 'Place of birth',            'open',     NULL, false, 14),
    ('height',           'personal', 'Height',                    'open',     'Recorded for academic dress and sport', false, 15),
    ('disability',       'personal', 'Disability or access need', 'open',     'Declaring one obtains support; it is never a bar to admission or examination', true, 16),
    ('languages',        'personal', 'Languages spoken',          'open',     NULL, true, 17),
    ('mobile',           'contact',  'Mobile number',             'open',     'Nigerian number. SMS notices go here', false, 20),
    ('alt_mobile',       'contact',  'Alternative number',        'open',     'A number that reaches somebody if yours fails', false, 21),
    ('personal_email',   'contact',  'Personal email',            'open',     'Use one you will still have after you graduate', false, 22),
    ('university_email', 'contact',  'University email',          'locked',   'Issued to you; used for official correspondence', false, 23),
    ('whatsapp',         'contact',  'WhatsApp number',           'open',     'Optional', false, 24),
    ('term_address',     'contact',  'Term-time address',         'open',     NULL, true, 25),
    ('home_address',     'contact',  'Permanent home address',    'open',     NULL, true, 26),
    ('city',             'contact',  'City or town',              'open',     NULL, false, 27),
    ('state_of_residence','contact', 'State of residence',        'open',     NULL, false, 28),
    ('country_of_origin','origin',   'Country of origin',         'approval', NULL, false, 30),
    ('state_of_origin',  'origin',   'State of origin',           'approval', 'Evidence: local government identification', false, 31),
    ('lga',              'origin',   'Local government area',     'approval', 'Evidence: local government identification', false, 32),
    ('town',             'origin',   'Town or village',           'open',     NULL, false, 33),
    ('senatorial_district','origin', 'Senatorial district',       'locked',   'Derived from the local government area', false, 34),
    ('ethnic_group',     'origin',   'Ethnic group',              'open',     'Optional', false, 35),
    ('sponsorship',      'origin',   'Sponsorship',               'open',     'Self · parent or guardian · scholarship · employer', false, 36),
    ('scholarship',      'origin',   'Scholarship or bursary',    'open',     'Name the board or fund if you hold one', false, 37),
    ('scholarship_ref',  'origin',   'Scholarship reference',     'open',     NULL, false, 38),
    ('employer',         'origin',   'Employer, if sponsored',    'open',     NULL, false, 39),
    ('father_name',      'family',   'Father — name',             'open',     NULL, false, 40),
    ('father_status',    'family',   'Father — status',           'open',     'Living · deceased', false, 41),
    ('father_occupation','family',   'Father — occupation',       'open',     NULL, false, 42),
    ('father_mobile',    'family',   'Father — mobile number',    'open',     NULL, false, 43),
    ('father_email',     'family',   'Father — email',            'open',     NULL, false, 44),
    ('father_address',   'family',   'Father — address',          'open',     NULL, true, 45),
    ('mother_name',      'family',   'Mother — name',             'open',     NULL, false, 46),
    ('mother_status',    'family',   'Mother — status',           'open',     NULL, false, 47),
    ('mother_occupation','family',   'Mother — occupation',       'open',     NULL, false, 48),
    ('mother_mobile',    'family',   'Mother — mobile number',    'open',     NULL, false, 49),
    ('mother_email',     'family',   'Mother — email',            'open',     NULL, false, 50),
    ('mother_address',   'family',   'Mother — address',          'open',     NULL, true, 51),
    ('guardian_name',    'family',   'Guardian — name',           'open',     NULL, false, 52),
    ('guardian_relationship','family','Guardian — relationship',  'open',     NULL, false, 53),
    ('guardian_mobile',  'family',   'Guardian — mobile number',  'open',     NULL, false, 54),
    ('guardian_address', 'family',   'Guardian — address',        'open',     NULL, true, 55),
    ('kin_name',         'kin',      'Next of kin — name',        'open',     NULL, false, 60),
    ('kin_relationship', 'kin',      'Next of kin — relationship','open',     NULL, false, 61),
    ('kin_mobile',       'kin',      'Next of kin — mobile number','open',    'Verified by SMS when you save it', false, 62),
    ('kin_alt_mobile',   'kin',      'Next of kin — alternative number','open', NULL, false, 63),
    ('kin_email',        'kin',      'Next of kin — email',       'open',     NULL, false, 64),
    ('kin_address',      'kin',      'Next of kin — address',     'open',     NULL, true, 65),
    ('guarantor_name',   'kin',      'Guarantor — name',          'open',     NULL, false, 66),
    ('guarantor_relationship','kin', 'Guarantor — relationship',  'open',     NULL, false, 67),
    ('guarantor_occupation','kin',   'Guarantor — occupation',    'open',     NULL, false, 68),
    ('guarantor_employer','kin',     'Guarantor — employer',      'open',     NULL, false, 69),
    ('guarantor_mobile', 'kin',      'Guarantor — mobile number', 'open',     NULL, false, 70),
    ('guarantor_address','kin',      'Guarantor — address',       'open',     NULL, true, 71),
    ('blood_group',      'health',   'Blood group',               'open',     NULL, false, 80),
    ('genotype',         'health',   'Genotype',                  'open',     'Recorded for emergency transfusion and for the sickle cell support programme', false, 81),
    ('allergies',        'health',   'Known allergies',           'open',     NULL, true, 82),
    ('chronic',          'health',   'Chronic conditions',        'open',     'Asthma, sickle cell disease, epilepsy, diabetes and others', true, 83),
    ('medication',       'health',   'Regular medication',        'open',     NULL, true, 84),
    ('insurance',        'health',   'Health insurance',          'open',     NULL, false, 85),
    ('insurance_no',     'health',   'Insurance number',          'open',     NULL, false, 86),
    ('bank_account_name','bank',     'Account name',              'approval', 'Must match your name on the register; a mismatch is why refunds fail', false, 90),
    ('bank_name',        'bank',     'Bank',                      'open',     NULL, false, 91),
    ('bank_account_no',  'bank',     'Account number',            'approval', 'Shown in part. Changing it requires the Bursary to verify the name', false, 92),
    ('bank_account_type','bank',     'Account type',              'open',     NULL, false, 93);

CREATE TABLE people.biodata (
    student_id uuid NOT NULL REFERENCES people.student(id),
    field      text NOT NULL REFERENCES ref.biodata_field(field),
    value      text NOT NULL,
    PRIMARY KEY (student_id, field)
);

-- A field that changes only on evidence is not changed by the person it
-- describes: the request waits on the document, and the Registry decides.
-- A refusal is as much a decision as an approval, and is recorded with its
-- reason.
CREATE TABLE people.biodata_change (
    id            uuid PRIMARY KEY,
    student_id    uuid NOT NULL REFERENCES people.student(id),
    field         text NOT NULL,
    from_value    text NULL,
    to_value      text NOT NULL,
    evidence      text NULL,              -- what was attached, in words
    evidence_ref  uuid NULL,              -- the attachment, when there is one
    requested_at  timestamptz NOT NULL DEFAULT now(),
    state         text NOT NULL DEFAULT 'PENDING',
    decided_at    timestamptz NULL,
    decided_by    uuid NULL,
    decision      text NULL,
    CONSTRAINT ck_bio_change_state CHECK (state IN ('PENDING','EVIDENCE_ASKED','APPROVED','REFUSED')),
    CONSTRAINT ck_bio_change_decided CHECK (state IN ('PENDING','EVIDENCE_ASKED')
        OR (decided_at IS NOT NULL AND decided_by IS NOT NULL AND decision IS NOT NULL AND btrim(decision) <> ''))
);
CREATE INDEX ix_bio_change_open ON people.biodata_change (requested_at) WHERE state IN ('PENDING','EVIDENCE_ASKED');

-- the documents the Registry holds for a student
CREATE TABLE people.document (
    id          uuid PRIMARY KEY,
    student_id  uuid NOT NULL REFERENCES people.student(id),
    kind        text NOT NULL,
    detail      text NULL,
    source      text NOT NULL,
    received_on date NULL,
    status      text NOT NULL DEFAULT 'NOT_SUPPLIED',
    attachment  uuid NULL,
    CONSTRAINT ck_document_status CHECK (status IN ('NOT_SUPPLIED','RECEIVED','ACCEPTED','VERIFIED','REFUSED','EXPIRED'))
);

-- Looking somebody up is processing their personal data whether or not
-- anything changes, so every search for a person is written down, and the
-- Registrar reviews the log quarterly.
CREATE TABLE people.search_log (
    id          uuid PRIMARY KEY,
    searched_at timestamptz NOT NULL DEFAULT now(),
    term        text NOT NULL,
    kind        text NOT NULL,
    hits        int  NOT NULL
);

-- ══ 5 · the catalogue, and who is registered for what ═════════════════════

-- A course belongs to exactly one department. A new course is a curriculum
-- change — the Faculty Board sees it and Senate approves it — and a course no
-- longer taught is ENDED with a date and stays on every transcript that
-- carries it.
CREATE TABLE catalogue.course (
    code       text PRIMARY KEY,
    title      text NOT NULL,
    units      int  NOT NULL,
    semester   int  NOT NULL,
    level      int  NOT NULL,
    dept_code  text NOT NULL REFERENCES ref.department(code),
    kind       text NOT NULL DEFAULT 'Compulsory',
    state      text NOT NULL DEFAULT 'BOARD',
    ended_on   date NULL,
    CONSTRAINT ck_course_code  CHECK (code ~ '^[A-Z]{3} [0-9]{3}$'),
    CONSTRAINT ck_course_units CHECK (units BETWEEN 0 AND 12),
    CONSTRAINT ck_course_sem   CHECK (semester IN (1,2,3)),
    CONSTRAINT ck_course_level CHECK (level IN (100,200,300,400,500,600)),
    CONSTRAINT ck_course_kind  CHECK (kind IN ('Compulsory','Required','Elective','GST')),
    CONSTRAINT ck_course_state CHECK (state IN ('BOARD','SENATE','LIVE','ENDED')),
    CONSTRAINT ck_course_ended CHECK ((state = 'ENDED') = (ended_on IS NOT NULL))
);

-- which programme-and-level pairs a course was made available to at creation
CREATE TABLE catalogue.course_offer (
    course_code    text NOT NULL REFERENCES catalogue.course(code),
    programme_code text NOT NULL REFERENCES ref.programme(code),
    level          int  NOT NULL,
    basis          text NOT NULL DEFAULT 'Core',
    PRIMARY KEY (course_code, programme_code, level),
    CONSTRAINT ck_offer_basis CHECK (basis IN ('Core','Elective','Borrowed','GST'))
);

-- a course, in a session and semester, in the name of the lecturer the
-- department allocated. Assigning the lecturer is what opens the score sheet.
CREATE TABLE catalogue.offering (
    id                 uuid PRIMARY KEY,
    course_code        text NOT NULL REFERENCES catalogue.course(code),
    session            text NOT NULL REFERENCES policy.academic_session(name),
    semester           int  NOT NULL,
    lecturer_id        uuid NULL REFERENCES iam.person(id),
    second_examiner_id uuid NULL REFERENCES iam.person(id),
    allocated_on       date NULL,
    UNIQUE (course_code, session, semester),
    CONSTRAINT ck_offering_examiners CHECK (second_examiner_id IS NULL OR second_examiner_id <> lecturer_id)
);

-- one registration per student per semester; the class list, the attendance
-- register, the examination roll and the broadsheet are all drawn from its
-- APPROVED entries and nothing else.
CREATE TABLE registration.course_registration (
    id           uuid PRIMARY KEY,
    student_id   uuid NOT NULL REFERENCES people.student(id),
    session      text NOT NULL REFERENCES policy.academic_session(name),
    semester     int  NOT NULL,
    level        int  NOT NULL,
    status       text NOT NULL DEFAULT 'DRAFT',
    submitted_at timestamptz NULL,
    approved_at  timestamptz NULL,
    approved_by  uuid NULL,
    UNIQUE (student_id, session, semester),
    CONSTRAINT ck_reg_status CHECK (status IN ('DRAFT','SUBMITTED','RETURNED','APPROVED','LOCKED')),
    CONSTRAINT ck_reg_approved CHECK (status NOT IN ('APPROVED','LOCKED') OR approved_at IS NOT NULL)
);

CREATE TABLE registration.entry (
    registration_id uuid NOT NULL REFERENCES registration.course_registration(id),
    offering_id     uuid NOT NULL REFERENCES catalogue.offering(id),
    units           int  NOT NULL,
    entry_type      text NOT NULL DEFAULT 'CURRENT',
    status          text NOT NULL DEFAULT 'REGISTERED',
    PRIMARY KEY (registration_id, offering_id),
    CONSTRAINT ck_entry_type   CHECK (entry_type IN ('CURRENT','CARRYOVER','REPEAT','ELECTIVE','GST','BORROWED')),
    CONSTRAINT ck_entry_status CHECK (status IN ('REGISTERED','DROPPED','APPROVED','WITHDRAWN'))
);

-- the units a registration carries, computed, never typed
CREATE OR REPLACE FUNCTION registration.units_of(p_registration uuid)
RETURNS int
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(sum(units), 0)::int FROM registration.entry
     WHERE registration_id = p_registration AND status <> 'DROPPED' AND status <> 'WITHDRAWN'
$$;

-- ══ 6 · score sheets, and the chain they pass ═════════════════════════════

-- An examination session is the container everything else hangs in. Opening
-- it generates every score sheet at once: one per offering with a lecturer,
-- over the approved register at that moment. An offering with no lecturer
-- generates no sheet, and is listed as such.
CREATE TABLE assessment.exam_session (
    id          uuid PRIMARY KEY,
    session     text NOT NULL REFERENCES policy.academic_session(name),
    semester    int  NOT NULL,
    kind        text NOT NULL DEFAULT 'MAIN',
    exams_from  date NOT NULL,
    exams_to    date NOT NULL,
    sheets_due  date NOT NULL,
    state       text NOT NULL DEFAULT 'DRAFT',
    opened_at   timestamptz NULL,
    UNIQUE (session, semester, kind),
    CONSTRAINT ck_exam_kind  CHECK (kind IN ('MAIN','RESIT','SPECIAL')),
    CONSTRAINT ck_exam_state CHECK (state IN ('DRAFT','OPEN','CLOSED')),
    CONSTRAINT ck_exam_dates CHECK (exams_to >= exams_from AND sheets_due >= exams_to)
);

-- The desks a sheet passes, finer than the spine a student sees (part28):
--   ENTRY → VERIFICATION → DEPT_BOARD → FACULTY_SCRUTINY → FACULTY_COMPILATION
--   → FACULTY_BOARD → RECORDS → SENATE → PUBLISHED
CREATE TABLE assessment.score_sheet (
    id              uuid PRIMARY KEY,
    offering_id     uuid NOT NULL UNIQUE REFERENCES catalogue.offering(id),
    exam_session_id uuid NULL REFERENCES assessment.exam_session(id),
    stage           text NOT NULL DEFAULT 'ENTRY',
    due_on          date NULL,
    submitted_at    timestamptz NULL,
    returned_times  int  NOT NULL DEFAULT 0,
    senate_minute   text NULL,
    published_at    timestamptz NULL,
    engine_version  text NULL,
    CONSTRAINT ck_sheet_stage CHECK (stage IN
        ('ENTRY','VERIFICATION','DEPT_BOARD','FACULTY_SCRUTINY','FACULTY_COMPILATION',
         'FACULTY_BOARD','RECORDS','SENATE','PUBLISHED')),
    CONSTRAINT ck_sheet_published CHECK (stage <> 'PUBLISHED' OR (published_at IS NOT NULL AND senate_minute IS NOT NULL))
);

-- A mark is never overwritten: an amendment writes a new version and keeps
-- the old one, with the reason and the author (I-RES-5).
CREATE TABLE assessment.score (
    sheet_id   uuid NOT NULL REFERENCES assessment.score_sheet(id),
    student_id uuid NOT NULL REFERENCES people.student(id),
    version    int  NOT NULL DEFAULT 1,
    ca         int  NULL,
    exam       int  NULL,
    outcome    text NOT NULL DEFAULT 'GRADED',
    reason     text NULL,
    entered_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (sheet_id, student_id, version),
    CONSTRAINT ck_score_outcome CHECK (outcome IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED')),
    CONSTRAINT ck_score_range   CHECK ((ca IS NULL OR ca BETWEEN 0 AND 40) AND (exam IS NULL OR exam BETWEEN 0 AND 60)),
    CONSTRAINT ck_score_graded  CHECK (outcome <> 'GRADED' OR (ca IS NOT NULL AND exam IS NOT NULL)),
    CONSTRAINT ck_score_amended CHECK (version = 1 OR (reason IS NOT NULL AND btrim(reason) <> ''))
);

-- every decision on a sheet: who, at which desk, which way, and why
CREATE TABLE assessment.decision (
    id          uuid PRIMARY KEY,
    sheet_id    uuid NOT NULL REFERENCES assessment.score_sheet(id),
    from_stage  text NOT NULL,
    to_stage    text NOT NULL,
    kind        text NOT NULL,
    actor_id    uuid NOT NULL,
    actor_office text NOT NULL,
    comment     text NULL,
    decided_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_decision_kind CHECK (kind IN ('SUBMIT','ADVANCE','RETURN')),
    CONSTRAINT ck_decision_return_says_why CHECK (kind <> 'RETURN' OR (comment IS NOT NULL AND btrim(comment) <> ''))
);
CREATE INDEX ix_decision_sheet ON assessment.decision (sheet_id, decided_at);

CREATE OR REPLACE FUNCTION assessment.stage_after(p_stage text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_stage
        WHEN 'ENTRY' THEN 'VERIFICATION'
        WHEN 'VERIFICATION' THEN 'DEPT_BOARD'
        WHEN 'DEPT_BOARD' THEN 'FACULTY_SCRUTINY'
        WHEN 'FACULTY_SCRUTINY' THEN 'FACULTY_COMPILATION'
        WHEN 'FACULTY_COMPILATION' THEN 'FACULTY_BOARD'
        WHEN 'FACULTY_BOARD' THEN 'RECORDS'
        WHEN 'RECORDS' THEN 'SENATE'
        WHEN 'SENATE' THEN 'PUBLISHED'
    END
$$;

-- Four approvals, four desks; none skipped, none reordered, and no two
-- consecutive stages by one person even where one person holds both offices
-- (BR-006, I-RES-6, I-RES-7). Senate's approval carries the minute.
CREATE OR REPLACE FUNCTION assessment.advance(p_sheet uuid, p_comment text, p_minute text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_stage text; v_next text; v_actor uuid; v_office text; v_last uuid; v_missing int;
BEGIN
    v_actor  := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = p_sheet FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    v_next := assessment.stage_after(v_stage);
    IF v_next IS NULL THEN
        RAISE EXCEPTION 'this sheet is published; there is no stage after publication'
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_stage = 'ENTRY' THEN
        -- a sheet leaves the lecturer only when every registered candidate has an outcome (I-RES-4)
        SELECT count(*) INTO v_missing
          FROM registration.entry e
          JOIN registration.course_registration r ON r.id = e.registration_id
          JOIN assessment.score_sheet s ON s.offering_id = e.offering_id
         WHERE s.id = p_sheet AND r.status IN ('APPROVED','LOCKED') AND e.status = 'APPROVED'
           AND NOT EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = p_sheet AND sc.student_id = r.student_id);
        IF v_missing > 0 THEN
            RAISE EXCEPTION '% registered candidate(s) on this sheet have no mark and no outcome', v_missing
                USING ERRCODE = 'check_violation',
                      HINT = 'Every candidate on the register is graded, absent, withheld, incomplete, malpractice or exempted. A blank is not an outcome.';
        END IF;
    END IF;
    SELECT d.actor_id INTO v_last FROM assessment.decision d
     WHERE d.sheet_id = p_sheet AND d.kind IN ('SUBMIT','ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you approved the previous stage of this sheet; another desk must approve this one'
            USING ERRCODE = 'check_violation',
                  HINT = 'BR-006. The system refuses two consecutive stages by one person even where one person holds both offices.';
    END IF;
    IF v_next = 'PUBLISHED' AND (p_minute IS NULL OR btrim(p_minute) = '') THEN
        RAISE EXCEPTION 'a result reaches a student on the Senate minute that approved it, and none was cited'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.decision (id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (gen_random_uuid(), p_sheet, v_stage, v_next,
            CASE WHEN v_stage = 'ENTRY' THEN 'SUBMIT' ELSE 'ADVANCE' END, v_actor, v_office, p_comment);
    UPDATE assessment.score_sheet
       SET stage = v_next,
           submitted_at = CASE WHEN v_stage = 'ENTRY' THEN now() ELSE submitted_at END,
           senate_minute = CASE WHEN v_next = 'PUBLISHED' THEN p_minute ELSE senate_minute END,
           published_at  = CASE WHEN v_next = 'PUBLISHED' THEN now() ELSE published_at END,
           engine_version = CASE WHEN v_next = 'PUBLISHED' THEN 'GpaCalculator 2.1' ELSE engine_version END
     WHERE id = p_sheet;
    RETURN v_next;
END;
$$;

-- a return goes back to the lecturer with the reason on the record, and the
-- sheet re-enters the chain at verification, not at the stage it left
CREATE OR REPLACE FUNCTION assessment.return_sheet(p_sheet uuid, p_comment text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_stage text;
BEGIN
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = p_sheet FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    IF v_stage IN ('ENTRY','PUBLISHED') THEN
        RAISE EXCEPTION 'a sheet at % is not returned', lower(v_stage) USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.decision (id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (gen_random_uuid(), p_sheet, v_stage, 'ENTRY', 'RETURN',
            nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''), p_comment);
    UPDATE assessment.score_sheet SET stage = 'ENTRY', returned_times = returned_times + 1 WHERE id = p_sheet;
END;
$$;

-- Opening a session generates every sheet at once and says which offerings
-- generated none.
CREATE OR REPLACE FUNCTION assessment.open_exam_session(p_id uuid)
RETURNS TABLE (sheets_made int, offerings_without_lecturer int)
LANGUAGE plpgsql
AS $$
DECLARE e assessment.exam_session; v_made int; v_none int;
BEGIN
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found';
    END IF;
    IF e.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'the examination session is already %', lower(e.state) USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), o.id, p_id, e.sheets_due
      FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id);
    GET DIAGNOSTICS v_made = ROW_COUNT;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL;
    UPDATE assessment.exam_session SET state = 'OPEN', opened_at = now() WHERE id = p_id;
    RETURN QUERY SELECT v_made, v_none;
END;
$$;

-- the total, the grade and the point are computed from the two marks, as the
-- engine computes them; they are not written into a table
CREATE OR REPLACE FUNCTION assessment.latest_scores(p_sheet uuid)
RETURNS TABLE (student_id uuid, ca int, exam int, total int, grade text, points numeric,
               outcome text, version int, amended boolean)
LANGUAGE sql
STABLE
AS $$
    SELECT s.student_id, s.ca, s.exam,
           CASE WHEN s.outcome = 'GRADED' THEN s.ca + s.exam END,
           g.grade, g.points, s.outcome, s.version, s.version > 1
      FROM (SELECT DISTINCT ON (student_id) * FROM assessment.score
             WHERE sheet_id = p_sheet ORDER BY student_id, version DESC) s
      LEFT JOIN LATERAL policy.grade_of(CASE WHEN s.outcome = 'GRADED' THEN s.ca + s.exam END) g ON true
$$;

-- ══ 7 · clearance: independent sign-offs, not a form that travels ═════════

CREATE TABLE clearance.unit (
    code           text PRIMARY KEY,
    label          text NOT NULL,
    clears_against text NOT NULL,
    holds_for      text NOT NULL,
    typical_reason text NOT NULL,
    office_code    text NULL REFERENCES ref.office(code),
    ord            int  NOT NULL
);
INSERT INTO clearance.unit (code, label, clears_against, holds_for, typical_reason, office_code, ord) VALUES
    ('BURSARY',    'Bursary',                 'Financial clearance',  'Outstanding charges on any invoice',          'Unpaid balance or an unmatched payment', 'bursar',   1),
    ('DEPARTMENT', 'Department',              'Academic clearance',   'Project, laboratory items, carryovers',       'Bound project not deposited',            'hod',      2),
    ('FACULTY',    'Faculty',                 'Faculty clearance',    'Faculty dues and equipment',                  'Laboratory coat or equipment',           'dean',     3),
    ('LIBRARY',    'Library',                 'Books and fines',      'Items on loan, unpaid fines',                 'A book never returned in 300 level',     'library',  4),
    ('HEALTH',     'Health',                  'Clinic',               'Outstanding clinic charges',                  'Unpaid treatment',                       'services', 5),
    ('HOSTEL',     'Hostel',                  'Accommodation',        'Room condition, keys, damage',                'Keys not returned',                      'services', 6),
    ('WORKS',      'Works and Maintenance',   'University property',  'Damage attributed to the candidate',          'Rare',                                   'services', 7),
    ('ALUMNI',     'Alumni and Convocation',  'Dues and gown',        'Alumni registration, gown hire',              'Gown not yet collected',                 'registrar', 8);

-- A hold names the unit, the officer, the date and the specific item
-- outstanding; a clearance names who signed. A hold with no item against it
-- is visible as such to the Registrar, which is what stops clearance being
-- used as leverage.
CREATE TABLE clearance.item (
    id          uuid PRIMARY KEY,
    student_id  uuid NOT NULL REFERENCES people.student(id),
    purpose     text NOT NULL REFERENCES ref.clearance_purpose(code),
    unit        text NOT NULL REFERENCES clearance.unit(code),
    state       text NOT NULL,
    item        text NULL,                 -- what is outstanding, for a hold
    officer_id  uuid NULL,
    decided_at  timestamptz NOT NULL DEFAULT now(),
    note        text NULL,
    superseded_by uuid NULL REFERENCES clearance.item(id),
    CONSTRAINT ck_clr_state CHECK (state IN ('HELD','CLEARED')),
    CONSTRAINT ck_clr_hold_names_item CHECK (state = 'CLEARED' OR (item IS NOT NULL AND btrim(item) <> ''))
);
CREATE INDEX ix_clr_student ON clearance.item (student_id, purpose) WHERE superseded_by IS NULL;

-- the position of one candidate, unit by unit: the latest word of each unit
CREATE OR REPLACE FUNCTION clearance.position(p_student uuid, p_purpose text)
RETURNS TABLE (unit text, label text, state text, item text, officer_id uuid, decided_at timestamptz, ord int)
LANGUAGE sql
STABLE
AS $$
    SELECT u.code, u.label, coalesce(i.state, 'HELD'), i.item, i.officer_id, i.decided_at, u.ord
      FROM clearance.unit u
      LEFT JOIN LATERAL (SELECT * FROM clearance.item c
                          WHERE c.student_id = p_student AND c.purpose = p_purpose AND c.unit = u.code
                            AND c.superseded_by IS NULL
                          ORDER BY c.decided_at DESC LIMIT 1) i ON true
     ORDER BY u.ord
$$;

CREATE OR REPLACE FUNCTION clearance.is_clear(p_student uuid, p_purpose text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT NOT EXISTS (SELECT 1 FROM clearance.position(p_student, p_purpose) WHERE state <> 'CLEARED')
$$;

-- ══ 8 · matriculation: one run, one sequence, one transaction ═════════════

-- The faculty list is GENERATED from approved registrations, never typed; a
-- Faculty Officer confirms it, and names under query keep their registration
-- and wait for the next run.
CREATE TABLE people.faculty_list (
    id            uuid PRIMARY KEY,
    session       text NOT NULL REFERENCES policy.academic_session(name),
    faculty_code  text NOT NULL REFERENCES ref.faculty(code),
    state         text NOT NULL DEFAULT 'DRAFT',
    confirmed_at  timestamptz NULL,
    confirmed_by  uuid NULL,
    UNIQUE (session, faculty_code),
    CONSTRAINT ck_flist_state CHECK (state IN ('DRAFT','CONFIRMED')),
    CONSTRAINT ck_flist_confirmed CHECK (state = 'DRAFT' OR (confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL))
);

CREATE TABLE people.faculty_list_query (
    list_id    uuid NOT NULL REFERENCES people.faculty_list(id),
    student_id uuid NOT NULL REFERENCES people.student(id),
    reason     text NOT NULL,
    office     text NOT NULL,             -- who the student goes to
    PRIMARY KEY (list_id, student_id),
    CONSTRAINT ck_query_reason CHECK (length(btrim(reason)) > 0)
);

CREATE TABLE people.matriculation_run (
    id       uuid PRIMARY KEY,
    ref      text NOT NULL UNIQUE,
    session  text NOT NULL REFERENCES policy.academic_session(name),
    run_at   timestamptz NOT NULL DEFAULT now(),
    issued   int  NOT NULL
);

ALTER TABLE people.student
    ADD CONSTRAINT fk_student_run FOREIGN KEY (matriculation_run) REFERENCES people.matriculation_run(id);

-- who is on a faculty's list for a session: every ADMITTED student of the
-- faculty with an approved registration in it
CREATE OR REPLACE FUNCTION people.faculty_list_rows(p_session text, p_faculty text)
RETURNS TABLE (student_id uuid, admission_no text, surname text, other_names text, dept_code text,
               dept_name text, units int, registration_status text, query_reason text, query_office text)
LANGUAGE sql
STABLE
AS $$
    SELECT s.id, s.admission_no, s.surname, s.other_names, p.dept_code, d.name,
           registration.units_of(r.id), r.status, q.reason, q.office
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.department d ON d.code = p.dept_code
      JOIN registration.course_registration r ON r.student_id = s.id AND r.session = p_session
      LEFT JOIN people.faculty_list l ON l.session = p_session AND l.faculty_code = p.faculty_code
      LEFT JOIN people.faculty_list_query q ON q.list_id = l.id AND q.student_id = s.id
     WHERE p.faculty_code = p_faculty AND s.status = 'ADMITTED' AND r.status IN ('APPROVED','LOCKED')
     ORDER BY d.name, s.surname, s.other_names
$$;

-- The run. It refuses while any faculty with registered students has not
-- confirmed, and then allocates every number or none: one sequence per
-- department and session, contiguous, never reused.
CREATE OR REPLACE FUNCTION people.matriculate(p_session text)
RETURNS TABLE (run_ref text, issued int)
LANGUAGE plpgsql
AS $$
DECLARE v_missing text; v_run uuid := gen_random_uuid(); v_ref text; v_n int := 0; r record; v_serial bigint; v_yy text;
BEGIN
    SELECT string_agg(f.name, ', ' ORDER BY f.name) INTO v_missing
      FROM ref.faculty f
     WHERE EXISTS (SELECT 1 FROM people.faculty_list_rows(p_session, f.code))
       AND NOT EXISTS (SELECT 1 FROM people.faculty_list l
                        WHERE l.session = p_session AND l.faculty_code = f.code AND l.state = 'CONFIRMED');
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'the run cannot start: % has not confirmed its list', v_missing
            USING ERRCODE = 'check_violation',
                  HINT = 'A run with a faculty outstanding would leave its students unmatriculated after their classmates, or force a second run whose numbers sit at the end of the sequence. Confirm every list first.';
    END IF;
    v_yy := substr(p_session, 3, 2);
    v_ref := 'MAT/' || substr(p_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', p_session)::text, 3, '0');
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (v_run, v_ref, p_session, 0);
    FOR r IN
        SELECT x.student_id, x.dept_code
          FROM ref.faculty f
          CROSS JOIN LATERAL people.faculty_list_rows(p_session, f.code) x
         WHERE x.query_reason IS NULL
         ORDER BY x.dept_code, x.surname, x.other_names
    LOOP
        v_serial := platform.next_number('MATRIC', r.dept_code, p_session);
        UPDATE people.student
           SET matric_no = 'MOAUM/' || r.dept_code || '/' || v_yy || '/' || lpad(v_serial::text, 4, '0'),
               matriculated_at = now(), matriculation_run = v_run, status = 'ACTIVE'
         WHERE id = r.student_id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), r.student_id, 'ADMITTED', 'ACTIVE', v_ref, current_date, 'Matriculated');
        v_n := v_n + 1;
    END LOOP;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'nobody is on a confirmed list for %; there is nothing to matriculate', p_session
            USING ERRCODE = 'no_data_found';
    END IF;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = v_run;
    RETURN QUERY SELECT v_ref, v_n;
END;
$$;

-- bringing the admitted candidates of a session onto the register, each with
-- an admission number; done once per candidate, never twice
CREATE OR REPLACE FUNCTION people.intake(p_session text)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE c record; v_n int := 0; v_yy text := substr(p_session, 3, 2);
BEGIN
    FOR c IN
        SELECT * FROM admissions.candidate a
         WHERE a.session = p_session AND a.offer_state IN ('ADMITTED','ACCEPTED')
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id)
         ORDER BY a.surname, a.other_names
    LOOP
        INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                    programme_code, entry_mode, entry_session, entry_level, current_level)
        VALUES (gen_random_uuid(), c.id,
                'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', p_session)::text, 6, '0'),
                c.jamb_reg_no, c.surname, c.other_names, c.programme,
                CASE WHEN c.entry_mode IN ('UTME','DIRECT_ENTRY') THEN c.entry_mode ELSE 'UTME' END,
                p_session, c.entry_level, c.entry_level);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END;
$$;

-- ══ 9 · credentials: transcripts, certificates, and the stock they use ═════

CREATE TABLE credentials.transcript_request (
    id               uuid PRIMARY KEY,
    ref              text NOT NULL UNIQUE,
    student_id       uuid NOT NULL REFERENCES people.student(id),
    destination      text NOT NULL,
    destination_name text NULL,
    mode             text NOT NULL DEFAULT 'DIGITAL',
    express          boolean NOT NULL DEFAULT false,
    copies           int  NOT NULL DEFAULT 1,
    requested_at     timestamptz NOT NULL DEFAULT now(),
    paid_at          timestamptz NULL,
    stage            text NOT NULL DEFAULT 'AWAITING_PAYMENT',
    produced_at      timestamptz NULL,
    produced_by      uuid NULL,
    released_at      timestamptz NULL,
    released_by      uuid NULL,
    issued_id        uuid NULL REFERENCES credentials.issued(id),
    CONSTRAINT ck_tr_dest  CHECK (destination IN ('SELF','INSTITUTION','EMPLOYER','EMBASSY')),
    CONSTRAINT ck_tr_mode  CHECK (mode IN ('DIGITAL','SEALED')),
    CONSTRAINT ck_tr_copies CHECK (copies BETWEEN 1 AND 10),
    CONSTRAINT ck_tr_stage CHECK (stage IN ('AWAITING_PAYMENT','HELD_AT_CLEARANCE','READY','VERIFIED','RELEASED')),
    CONSTRAINT ck_tr_ref   CHECK (ref ~ '^TRN-[0-9]{4}-[0-9]{5}$')
);

-- Production is never manual re-typing: the transcript is generated from the
-- approved record, Exams & Records verifies it, the Registrar signs it. A
-- request held at clearance does not move until the last unit signs.
CREATE OR REPLACE FUNCTION credentials.produce_transcript(p_request uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE t credentials.transcript_request;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no transcript request %', p_request USING ERRCODE = 'no_data_found'; END IF;
    IF t.paid_at IS NULL THEN
        RAISE EXCEPTION 'request % is not payable yet: the SLA clock runs from payment, and production does', t.ref
            USING ERRCODE = 'check_violation';
    END IF;
    IF NOT clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN
        RAISE EXCEPTION 'request % is held at clearance', t.ref
            USING ERRCODE = 'check_violation',
                  HINT = 'A unit holds the candidate. The transcript is blocked while any unit does; the student sees which.';
    END IF;
    IF t.stage NOT IN ('READY','HELD_AT_CLEARANCE') THEN
        RAISE EXCEPTION 'request % is %', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = 'check_violation';
    END IF;
    UPDATE credentials.transcript_request
       SET stage = 'VERIFIED', produced_at = now(),
           produced_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
     WHERE id = p_request;
END;
$$;

CREATE OR REPLACE FUNCTION credentials.release_transcript(p_request uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE t credentials.transcript_request; v_actor uuid;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no transcript request %', p_request USING ERRCODE = 'no_data_found'; END IF;
    IF t.stage <> 'VERIFIED' THEN
        RAISE EXCEPTION 'request % has not been produced and verified', t.ref USING ERRCODE = 'check_violation';
    END IF;
    IF t.produced_by = v_actor THEN
        RAISE EXCEPTION 'the officer who produced a transcript does not sign it'
            USING ERRCODE = 'check_violation', HINT = 'BR-006. The Registrar signs what Exams & Records verified.';
    END IF;
    UPDATE credentials.transcript_request
       SET stage = 'RELEASED', released_at = now(), released_by = v_actor
     WHERE id = p_request;
END;
$$;

CREATE TABLE credentials.stationery_batch (
    id          uuid PRIMARY KEY,
    batch       text NOT NULL UNIQUE,
    serial_from int  NOT NULL,
    serial_to   int  NOT NULL,
    received_on date NOT NULL,
    spoiled     int  NOT NULL DEFAULT 0,
    returned    int  NOT NULL DEFAULT 0,
    CONSTRAINT ck_batch_range CHECK (serial_to >= serial_from),
    CONSTRAINT ck_batch_counts CHECK (spoiled >= 0 AND returned >= 0)
);

-- A certificate cannot be printed before Senate approves the award, and the
-- stationery serial is tracked from issue to collection, so a spoiled
-- certificate is accounted for. Certificates awarded before 30 December 2024
-- were issued as Benue State University, Makurdi, and carry that name.
CREATE TABLE credentials.certificate (
    id              uuid PRIMARY KEY,
    number          text NOT NULL UNIQUE,
    student_id      uuid NOT NULL REFERENCES people.student(id),
    award           text NOT NULL,
    class_of_degree text NOT NULL,
    convocation     text NOT NULL,
    serial          int  NULL,
    batch_id        uuid NULL REFERENCES credentials.stationery_batch(id),
    status          text NOT NULL DEFAULT 'PRINTED',
    printed_on      date NOT NULL DEFAULT current_date,
    collected_on    date NULL,
    collected_note  text NULL,
    held_reason     text NULL,
    issuing_name    text NOT NULL DEFAULT 'Rev. Fr. Moses Orshio Adasu University, Makurdi',
    duplicate_of    uuid NULL REFERENCES credentials.certificate(id),
    issued_id       uuid NULL REFERENCES credentials.issued(id),
    CONSTRAINT ck_cert_status CHECK (status IN ('PRINTED','COLLECTED','HELD','REISSUED','REVOKED')),
    CONSTRAINT ck_cert_number CHECK (number ~ '^MOAUM/C/[0-9]{2}/[0-9]{5}$'),
    CONSTRAINT ck_cert_held CHECK (status <> 'HELD' OR held_reason IS NOT NULL),
    CONSTRAINT ck_cert_collected CHECK (status <> 'COLLECTED' OR collected_on IS NOT NULL)
);

-- ══ 10 · graduation: the audit, computed, and the Senate list ═════════════

CREATE TABLE records.graduand (
    id            uuid PRIMARY KEY,
    student_id    uuid NOT NULL REFERENCES people.student(id),
    session       text NOT NULL REFERENCES policy.academic_session(name),
    cgpa          numeric(3,2) NULL,
    award         text NOT NULL,
    unmet         text NULL,               -- the requirement the audit found unmet
    senate_state  text NOT NULL DEFAULT 'AWAITING',
    senate_minute text NULL,
    UNIQUE (student_id, session),
    CONSTRAINT ck_grad_state CHECK (senate_state IN ('AWAITING','APPROVED','REFERRED')),
    CONSTRAINT ck_grad_cgpa  CHECK (cgpa IS NULL OR cgpa BETWEEN 0 AND 5),
    CONSTRAINT ck_grad_approved CHECK (senate_state <> 'APPROVED' OR (senate_minute IS NOT NULL AND unmet IS NULL AND cgpa IS NOT NULL))
);

-- ══ 11 · every table on the spine ═════════════════════════════════════════

SELECT audit.attach('ref.department');
SELECT audit.attach('ref.college');
SELECT audit.attach('policy.semester');
SELECT audit.attach('policy.level_limit');
SELECT audit.attach('policy.classification_band');
SELECT audit.exempt('ref.biodata_field',
    'The list of fields a biodata record has. Structure, not state: it changes by migration.');
SELECT audit.attach('people.student');
SELECT audit.attach('people.status_change');
SELECT audit.attach('people.enrolment');
SELECT audit.attach('people.biodata');
SELECT audit.attach('people.biodata_change');
SELECT audit.attach('people.document');
SELECT audit.attach('people.search_log');
SELECT audit.attach('people.faculty_list');
SELECT audit.attach('people.faculty_list_query');
SELECT audit.attach('people.matriculation_run');
SELECT audit.attach('catalogue.course');
SELECT audit.attach('catalogue.course_offer');
SELECT audit.attach('catalogue.offering');
SELECT audit.attach('registration.course_registration');
SELECT audit.attach('registration.entry');
SELECT audit.attach('assessment.exam_session');
SELECT audit.attach('assessment.score_sheet');
SELECT audit.attach('assessment.score');
SELECT audit.attach('assessment.decision');
SELECT audit.attach('clearance.unit');
SELECT audit.attach('clearance.item');
SELECT audit.attach('credentials.transcript_request');
SELECT audit.attach('credentials.stationery_batch');
SELECT audit.attach('credentials.certificate');
SELECT audit.attach('records.graduand');

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA people TO app_student;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA catalogue, registration TO app_registration;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA assessment TO app_results;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA records TO app_acrecords;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA credentials, clearance TO app_credentials;
GRANT SELECT ON ALL TABLES IN SCHEMA people, catalogue, registration, assessment, records, credentials, clearance TO app_auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA ref, policy TO
    app_iam, app_student, app_admissions, app_registration, app_results,
    app_acrecords, app_credentials, app_finance, app_payments, app_expenditure,
    app_notification, app_governance, app_reporting, app_apimgmt, app_platform;

COMMIT;
