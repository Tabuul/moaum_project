-- ═══════════════════════════════════════════════════════════════════════════
-- V245 — the College of Health Sciences' tables, from §7 of the prospectus extraction
--
--   The CHS Prospectus 2023–2025 extraction of 24 September 2026 (v2) proposes
--   in its §7 the model the College's academic machinery needs: the programme's
--   rule, the levels and their phases, the semesters of 17, 17 and 20 weeks, the
--   Blocks and their Postings with the courses each carries, rotation groups and
--   a student's allocation, the timetable, the logbooks (procedures, cases,
--   mandatory events), attendance rules and records, the Professional
--   examinations with their subjects, CA items and scores, the Community
--   Medicine project, the result by attempt and the progression decision.
--   This migration is that model as tables in a `college` schema, every one on
--   the audit spine, seeded with what the document gives — the blocks, the
--   postings, the Psychiatry week, the examinations and their rules, the
--   Paediatrics procedures, the attendance thresholds — and left empty where
--   the document is silent (dates, the CA split within the 30, the registration
--   mode). Course codes are kept as text: the College's courses are not all in
--   the catalogue yet, and the document's codes must not be lost waiting.
--
--   What is NOT here, on purpose: registration. The document says the mode is
--   unconfirmed (per semester or session; whether posting codes are registered;
--   what a repeat year does), so the College's registration stays the portal's
--   registration until the College answers.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'The College of Health Sciences tables and their seed from the prospectus (V245)', true);

CREATE SCHEMA IF NOT EXISTS college;
COMMENT ON SCHEMA college IS 'The College of Health Sciences'' academic machinery: phases, blocks, postings, logbooks, attendance, the Professional examinations and progression (V245, from the CHS Prospectus 2023–2025 extraction §7).';

-- ── 1 · the programme's rule ────────────────────────────────────────────────
CREATE TABLE college.programme_rule (
    programme_code       text PRIMARY KEY REFERENCES ref.programme(code),
    degree               text NOT NULL,
    min_years_utme       int  NOT NULL,
    min_years_de         int  NOT NULL,
    min_total_cu         int  NOT NULL,
    regs_effective_from  date NOT NULL,
    classified           boolean NOT NULL DEFAULT false,
    distinction_mark     int  NOT NULL DEFAULT 70,
    resit_window_months  int  NOT NULL DEFAULT 3,
    carry_over_note      text NULL,
    honours_rule         text NULL
);
SELECT audit.attach('college.programme_rule');
INSERT INTO college.programme_rule (programme_code, degree, min_years_utme, min_years_de, min_total_cu, regs_effective_from, carry_over_note, honours_rule)
VALUES ('C00061', 'MB.BS', 6, 5, 160, date '2021-09-29',
        'No carry-over except GST and EPS courses; both must be passed before graduation.',
        'MBBS Honours for at least one distinction (70% or more) in each of the four Professional examinations; the degree itself is unclassified.');

-- ── 2 · levels and their phase ──────────────────────────────────────────────
CREATE TABLE college.level (
    level         int  PRIMARY KEY,
    phase         text NOT NULL,
    clinical_year int  NULL,
    enrolment     text NOT NULL,
    CONSTRAINT ck_college_level       CHECK (level IN (100,200,300,400,500,600)),
    CONSTRAINT ck_college_level_phase CHECK (phase IN ('PREMEDICAL','PRECLINICAL','CLINICAL'))
);
SELECT audit.attach('college.level');
INSERT INTO college.level (level, phase, clinical_year, enrolment) VALUES
    (100, 'PREMEDICAL',  NULL, 'Semester, credit-unit registration under the Faculty of Science; courses tagged C or E; CA 30, examination 70'),
    (200, 'PRECLINICAL', NULL, 'Fixed programme, two semesters of 17 weeks; assessed by subject in the Comprehensive Promotional Examination'),
    (300, 'PRECLINICAL', NULL, 'Fixed programme, the 20-week Third Semester; assessed by subject in the 1st Professional'),
    (400, 'CLINICAL',    1,    'Block and posting enrolment; the 2nd Professional at the end'),
    (500, 'CLINICAL',    2,    'Block and posting enrolment; the 3rd Professional at the end'),
    (600, 'CLINICAL',    3,    'Block and posting enrolment; the 4th (Final) Professional at the end');

-- ── 3 · semesters: the template the prospectus gives, and the session's own once the College dates it ──
CREATE TABLE college.semester_template (
    level        int  NOT NULL REFERENCES college.level(level),
    ordinal      int  NOT NULL,
    name         text NOT NULL,
    length_weeks int  NOT NULL,
    subjects     text NULL,
    PRIMARY KEY (level, ordinal)
);
SELECT audit.attach('college.semester_template');
INSERT INTO college.semester_template (level, ordinal, name, length_weeks, subjects) VALUES
    (200, 1, '200 Level, semester 1',           17, 'ANA 201/203/205, BCM 201/203/205, PHS 201/203/205/207'),
    (200, 2, '200 Level, semester 2',           17, 'ANA 202/204/206/208, BCM 202/204/206, PHS 202/204/206/208'),
    (300, 1, '300 Level, the Third Semester',   20, 'ANA 301/303/305, BCM 301/303/305, PHS 301/303/305/307');

CREATE TABLE college.semester (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session      text NOT NULL REFERENCES policy.academic_session(name),
    level        int  NOT NULL REFERENCES college.level(level),
    ordinal      int  NOT NULL,
    length_weeks int  NOT NULL,
    starts_on    date NULL,
    ends_on      date NULL,
    UNIQUE (session, level, ordinal),
    CONSTRAINT ck_college_semester_dates CHECK (starts_on IS NULL OR ends_on IS NULL OR ends_on > starts_on)
);
SELECT audit.attach('college.semester');
COMMENT ON TABLE college.semester IS 'A session''s dated semester at a level — the prospectus gives lengths, never dates; the College enters them.';

-- ── 4 · departments' units, blocks, postings ────────────────────────────────
CREATE TABLE college.department_unit (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dept_code       text NOT NULL REFERENCES ref.department(code),
    name            text NOT NULL,
    head_person_id  uuid NULL REFERENCES iam.person(id),
    UNIQUE (dept_code, name)
);
SELECT audit.attach('college.department_unit');
COMMENT ON TABLE college.department_unit IS 'A unit under a department, each headed by a consultant — Bacteriology, Virology, Parasitology, Immunology, Mycology under Medical Microbiology.';

CREATE TABLE college.block (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code         text NOT NULL UNIQUE,
    name         text NOT NULL,
    dept_code    text NULL REFERENCES ref.department(code),
    total_weeks  int  NULL,
    weeks_note   text NULL,
    ordinal      int  NOT NULL,
    note         text NULL
);
SELECT audit.attach('college.block');
INSERT INTO college.block (code, name, dept_code, total_weeks, weeks_note, ordinal, note) VALUES
    ('MED', 'Internal Medicine',            'MED', 34,   NULL, 1, 'Formal lectures (about five per body system), tutorials, seminars and independent class projects.'),
    ('SUG', 'Surgery',                      'MED', 30,   'Stated as 30 weeks; the phases add to 26, or 34 with the SUG 606 revision block — to resolve with the College', 2, NULL),
    ('PAE', 'Paediatrics',                  NULL,  16,   NULL, 3, 'Within the posting, 7–14 days in the Newborn Unit. Results released within one week of the examination.'),
    ('OBG', 'Obstetrics & Gynaecology',     NULL,  16,   NULL, 4, NULL),
    ('PHT', 'Pharmacology & Therapeutics',  NULL,  24,   'Three 8-week postings; the 2nd Professional in Pharmacology falls 42–44 weeks after the clinical programme begins', 5, 'Eighteen laboratory practicals of three hours each.'),
    ('PTH', 'Pathology disciplines',        NULL,  24,   'Three 8-week postings in each of four disciplines; 24 weeks a discipline', 6, 'Chemical Pathology, Haematology, Medical Microbiology, Anatomical Pathology.'),
    ('FAM', 'Family Medicine',              NULL,  3,    NULL, 7, 'Groups A and B rotate through the General Outpatient and the special clinics (NHIS, Well Adult, Pain & Palliative, HAART).'),
    ('COM', 'Community Medicine',           NULL,  NULL, '200–600 Level; the project is a prerequisite for the final', 8, 'COM 510 Field Activities; COM 602 Community Diagnosis.');

CREATE TABLE college.posting (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    block_id       uuid NOT NULL REFERENCES college.block(id),
    code           text NOT NULL,
    name           text NOT NULL,
    tier           text NOT NULL,
    level          int  NULL REFERENCES college.level(level),
    level_note     text NULL,
    duration_weeks numeric(4,1) NULL,
    ordinal        int  NOT NULL,
    min_cases      int  NULL,
    note           text NULL,
    UNIQUE (block_id, code),
    CONSTRAINT ck_college_posting_tier CHECK (tier IN ('INTRO','JUNIOR','INTERMEDIATE','SENIOR','REVISION','LECTURES'))
);
SELECT audit.attach('college.posting');
COMMENT ON COLUMN college.posting.min_cases IS 'Cases the student must clerk on the posting — Paediatrics asks for six.';

CREATE TABLE college.posting_course (
    posting_id  uuid NOT NULL REFERENCES college.posting(id),
    course_code text NOT NULL,
    title       text NULL,
    credit_units int NULL,
    contact_hours int NULL,
    PRIMARY KEY (posting_id, course_code)
);
SELECT audit.attach('college.posting_course');
COMMENT ON TABLE college.posting_course IS 'The courses a posting carries, by the prospectus'' code; the catalogue is the owner of the course once it is loaded there.';

CREATE FUNCTION pg_temp.college_post(p_block text, p_code text, p_name text, p_tier text, p_level int, p_level_note text, p_weeks numeric, p_ord int, p_min_cases int, p_courses text[])
RETURNS void
LANGUAGE plpgsql AS $p$
DECLARE v_block uuid; v_post uuid; c text;
BEGIN
    SELECT id INTO v_block FROM college.block WHERE code = p_block;
    INSERT INTO college.posting (block_id, code, name, tier, level, level_note, duration_weeks, ordinal, min_cases)
    VALUES (v_block, p_code, p_name, p_tier, p_level, p_level_note, p_weeks, p_ord, p_min_cases) RETURNING id INTO v_post;
    FOREACH c IN ARRAY p_courses LOOP
        INSERT INTO college.posting_course (posting_id, course_code, title)
        VALUES (v_post, split_part(c, '|', 1), nullif(split_part(c, '|', 2), ''));
    END LOOP;
END $p$;

-- Internal Medicine, 34 weeks
SELECT pg_temp.college_post('MED', 'M0', 'Introduction to Clinical Medicine', 'INTRO',        400, NULL, 2, 1, NULL, ARRAY['MED 401','MED 402']);
SELECT pg_temp.college_post('MED', 'M1', 'Junior Clerkship',                  'JUNIOR',       400, NULL, 8, 2, NULL, ARRAY['MED 403|Cardiology I','MED 404|Respiratory I','MED 405|Gastroenterology I','MED 406|Clinical Haematology','MED 407|Metabolic & Endocrine','MED 408|Neurology I','MED 409|Nephrology I']);
SELECT pg_temp.college_post('MED', 'M2', 'Intermediate Clerkship',            'INTERMEDIATE', 500, NULL, 8, 3, NULL, ARRAY['MED 501|Cardiology II','MED 502|Respiratory','MED 503|Gastroenterology II','MED 504|Nephrology II','MED 505|Rheumatology','MED 506|Clinical Immunology','MED 507|Tropical Medicine & Infections','MED 508|Endocrine lectures']);
SELECT pg_temp.college_post('MED', 'M3', 'Senior Clerkship',                  'SENIOR',       600, NULL, 8, 4, NULL, ARRAY['MED 601|Special Topics & Neurology II','MED 602|Dermatovenereology','MED 603|Medical Ethics & Jurisprudence','MED 604|Traditional Medicine']);
SELECT pg_temp.college_post('MED', 'PSY', 'Psychiatry',                       'SENIOR',       600, NULL, 8, 5, NULL, ARRAY['MED 605|Psychiatry']);
-- Surgery
SELECT pg_temp.college_post('SUG', 'S0', 'Introductory Clerkship',            'INTRO',        400, NULL, 2, 1, NULL, ARRAY['SUG 401|Introduction to Clinical Surgery']);
SELECT pg_temp.college_post('SUG', 'S1', 'Junior Surgery Posting',            'JUNIOR',       400, NULL, 8, 2, NULL, ARRAY['SUG 402|Principles of Surgery','SUG 403|General Surgery']);
SELECT pg_temp.college_post('SUG', 'S2', 'Intermediate — major sub-specialties', 'INTERMEDIATE', 500, NULL, 8, 3, NULL, ARRAY['SUG 501|Urology','SUG 502|Burns & Plastics','SUG 503|Orthopaedics','SUG 504|Cardiothoracic','SUG 505|Paediatric Surgery','SUG 506|Neurosurgery','SUG 507|Maxillofacial']);
SELECT pg_temp.college_post('SUG', 'S3', 'Senior — minor sub-specialties',    'SENIOR',       600, 'SUG 603/604 not seen in the prospectus, possibly Radiology', 8, 4, NULL, ARRAY['SUG 601|ENT','SUG 602|Ophthalmology','SUG 605|Anaesthesia']);
SELECT pg_temp.college_post('SUG', 'SUG 606', 'Surgery Three revision',       'REVISION',     600, NULL, 8, 5, NULL, ARRAY['SUG 606|Surgery Three (S3) Revision']);
-- Paediatrics, 16 weeks at 500
SELECT pg_temp.college_post('PAE', 'P1', 'Junior Posting',                    'JUNIOR',       500, NULL, 8, 1, NULL, ARRAY['PAE 501|Introduction','PAE 502|Nutrition & Growth','PAE 503|Child Health & PHC','PAE 504|CVS/Respiratory','PAE 505|GU/GIT','PAE 506|Endocrine/Metabolic','PAE 507|CNS/Muscles/Bones','PAE 508|Blood','PAE 509|Infections & Genetics','PAE 510|Oncology','PAE 511|Neonatology']);
SELECT pg_temp.college_post('PAE', 'P2', 'Senior Posting — clinical clerkship', 'SENIOR',     500, NULL, 8, 2, 6,    ARRAY[]::text[]);
-- Obstetrics & Gynaecology, 16 weeks at 500
SELECT pg_temp.college_post('OBG', 'OBG I',  'Junior posting',                'JUNIOR',       500, NULL, 8, 1, NULL, ARRAY['OBG 501|Introductory Gynaecology','OBG 502|Reproductive Physiology & Disorders of Pregnancy','OBG 503|Labour, Puerperium & the Neonate','OBG 504|Gynaecology Clinics']);
SELECT pg_temp.college_post('OBG', 'OBG II', 'Senior posting',                'SENIOR',       500, NULL, 8, 2, NULL, ARRAY['OBG 505|Obstetrics Clinics','OBG 506|Special Topics & Clinics']);
-- Pharmacology & Therapeutics
SELECT pg_temp.college_post('PHT', 'PHT I',   'First posting',                'JUNIOR',       300, '300 Level, second semester', 8, 1, NULL, ARRAY['PHT 301|General Pharmacology & Pharmacokinetics','PHT 302|ANS Pharmacology with practical']);
SELECT pg_temp.college_post('PHT', 'PHT II',  'Second posting',               'INTERMEDIATE', 400, NULL, 8, 2, NULL, ARRAY['PHT 401|CVS Pharmacology','PHT 402|Systemic Pharmacology','PHT 403|Hormones & Endocrine']);
SELECT pg_temp.college_post('PHT', 'PHT III', 'Senior posting',               'SENIOR',       NULL, '400 or 500 Level — not stated', 8, 3, NULL, ARRAY['PHT 404|Chemotherapy','PHT 405|CNS Pharmacology','PHT 406|Drug Misuse & Toxicology']);
-- Pathology disciplines
SELECT pg_temp.college_post('PTH', 'CPY', 'Chemical Pathology I–III',         'LECTURES',     NULL, '300–400 Level; the description says 400/500 — to resolve', 24, 1, NULL, ARRAY['CPY 302','CPY 304','CPY 306','CPY 401','CPY 402','CPY 403','CPY 404']);
SELECT pg_temp.college_post('PTH', 'HAE', 'Haematology I–III',                'LECTURES',     NULL, '300–400 Level, during the first and second clinical years', 24, 2, NULL, ARRAY['HAE 302','HAE 401','HAE 402','HAE 403','HAE 404']);
SELECT pg_temp.college_post('PTH', 'MMP', 'Medical Microbiology I–III',       'LECTURES',     NULL, '300–400 Level: introductory concepts; systemic and pathogenesis; diagnosis, management and control', 24, 3, NULL, ARRAY[]::text[]);
SELECT pg_temp.college_post('PTH', 'PAT', 'Anatomical Pathology I–III',       'LECTURES',     NULL, '300–400 Level', 24, 4, NULL, ARRAY['PAT 302','PAT 304','PAT 401','PAT 403','PAT 402','PAT 404|Forensic']);
-- Family Medicine
SELECT pg_temp.college_post('FAM', 'FAM I',  'Posting I',                     'JUNIOR',       500, NULL, 2, 1, NULL, ARRAY[]::text[]);
SELECT pg_temp.college_post('FAM', 'FAM II', 'Posting II',                    'SENIOR',       600, NULL, 1, 2, NULL, ARRAY[]::text[]);
-- Community Medicine
SELECT pg_temp.college_post('COM', 'COM', 'Community Medicine 200–600',       'LECTURES',     NULL, '200–600 Level', NULL, 1, NULL,
              ARRAY['COM 201','COM 202','COM 203','COM 204','COM 301','COM 302','COM 303','COM 304','COM 401','COM 402','COM 403','COM 404','COM 405','COM 406','COM 407','COM 501','COM 502','COM 503','COM 504','COM 505','COM 506','COM 507','COM 508','COM 509','COM 510|Field Activities','COM 601','COM 602|Community Diagnosis']);

-- the Pharmacology courses carry the only credit units the clinical phase states
UPDATE college.posting_course SET credit_units = 2, contact_hours = 20 WHERE course_code = 'PHT 301';
UPDATE college.posting_course SET credit_units = 3, contact_hours = 30 WHERE course_code IN ('PHT 302','PHT 401','PHT 402','PHT 403');
UPDATE college.posting_course SET credit_units = 3 WHERE course_code IN ('PHT 404','PHT 405','PHT 406');

-- ── 5 · rotation groups and a student's allocation ──────────────────────────
CREATE TABLE college.rotation_group (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    posting_id uuid NOT NULL REFERENCES college.posting(id),
    label      text NOT NULL,
    UNIQUE (posting_id, label)
);
SELECT audit.attach('college.rotation_group');
INSERT INTO college.rotation_group (posting_id, label)
SELECT p.id, g FROM college.posting p JOIN college.block b ON b.id = p.block_id, unnest(ARRAY['A','B']) g WHERE b.code = 'FAM';

CREATE TABLE college.posting_allocation (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    posting_id    uuid NOT NULL REFERENCES college.posting(id),
    session       text NOT NULL REFERENCES policy.academic_session(name),
    group_id      uuid NULL REFERENCES college.rotation_group(id),
    supervisor_id uuid NULL REFERENCES iam.person(id),
    starts_on     date NULL,
    ends_on       date NULL,
    state         text NOT NULL DEFAULT 'ALLOCATED',
    allocated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (student_id, posting_id, session),
    CONSTRAINT ck_college_alloc_state CHECK (state IN ('ALLOCATED','IN_PROGRESS','COMPLETED','INCOMPLETE'))
);
SELECT audit.attach('college.posting_allocation');

-- ── 6 · the timetable: Psychiatry's eight weeks are the only full data ──────
CREATE TABLE college.timetable_slot (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    posting_id uuid NOT NULL REFERENCES college.posting(id),
    week_no    int  NOT NULL,
    weekday    int  NOT NULL,
    starts_at  time NOT NULL,
    ends_at    time NOT NULL,
    slot_type  text NOT NULL,
    topic      text NULL,
    UNIQUE (posting_id, week_no, weekday, starts_at),
    CONSTRAINT ck_college_slot_day  CHECK (weekday BETWEEN 1 AND 7),
    CONSTRAINT ck_college_slot_type CHECK (slot_type IN ('LECTURE','WARD_ROUND','CLINIC','BEDSIDE','SEMINAR','DEPT_SEMINAR','CALL_DUTY','EXAM')),
    CONSTRAINT ck_college_slot_span CHECK (ends_at > starts_at)
);
SELECT audit.attach('college.timetable_slot');
INSERT INTO college.timetable_slot (posting_id, week_no, weekday, starts_at, ends_at, slot_type, topic)
SELECT p.id, w.n, d.n, s.starts_at, s.ends_at,
       CASE WHEN w.n = 8 AND d.n = 5 AND s.starts_at = time '15:00' THEN 'EXAM' ELSE s.slot_type END,
       CASE WHEN w.n = 8 AND d.n = 5 AND s.starts_at = time '15:00' THEN 'End-of-posting clinical examination — counts as CA'
            WHEN s.slot_type = 'LECTURE' THEN t.theme ELSE NULL END
  FROM college.posting p
  JOIN college.block b ON b.id = p.block_id AND b.code = 'MED'
  CROSS JOIN generate_series(1, 8) w(n)
  CROSS JOIN generate_series(1, 5) d(n)
  CROSS JOIN (VALUES (time '08:00', time '09:00', 'LECTURE'), (time '10:00', time '12:00', 'WARD_ROUND'), (time '14:00', time '15:00', 'LECTURE'),
                     (time '15:00', time '16:00', 'SEMINAR'), (time '17:00', time '20:00', 'CALL_DUTY')) s(starts_at, ends_at, slot_type)
  JOIN (VALUES (1, 'Introduction; history taking; aetiology and classification of mental disorders; psychopathology I–II'),
               (2, 'Psychopharmacology I–II; schizophrenia I–II'),
               (3, 'Alcohol and other substance disorders; organic mental disorders; delirium; Alzheimer''s; somatoform'),
               (4, 'Mood, depressive and bipolar disorders; sleep disorders'),
               (5, 'Emergency psychiatry; anxiety; molecular biology; personality disorders'),
               (6, 'Transcultural and forensic psychiatry; childhood autism; mental retardation; sex and gender identity; HIV neuropsychiatry'),
               (7, 'Suicide; old-age psychiatry; mental health & PHC; PTSD; psychological therapy I–II'),
               (8, 'Uncommon disorders; postpartum disorders; revision')) t(week, theme) ON t.week = w.n
 WHERE p.code = 'PSY';

-- ── 7 · logbooks: procedures, cases, mandatory events ───────────────────────
CREATE TABLE college.procedure_requirement (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    posting_id uuid NOT NULL REFERENCES college.posting(id),
    name       text NOT NULL,
    min_count  int  NOT NULL DEFAULT 1,
    mode       text NOT NULL DEFAULT 'EITHER',
    UNIQUE (posting_id, name),
    CONSTRAINT ck_college_proc_mode CHECK (mode IN ('OBSERVE','PERFORM','EITHER'))
);
SELECT audit.attach('college.procedure_requirement');
INSERT INTO college.procedure_requirement (posting_id, name, min_count, mode)
SELECT p.id, n, 5, CASE WHEN n LIKE 'Exchange blood transfusion%' THEN 'OBSERVE' ELSE 'EITHER' END
  FROM college.posting p JOIN college.block b ON b.id = p.block_id AND b.code = 'PAE',
       unnest(ARRAY['Lumbar puncture','Scalp or peripheral IV infusion','Venepuncture','Exchange blood transfusion (watch and assist)','Nasogastric tube insertion','PCV/haematocrit check','Urinalysis','Malaria RDT','Random blood sugar']) n
 WHERE p.code = 'P2';

CREATE TABLE college.procedure_log (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     uuid NOT NULL REFERENCES people.student(id),
    requirement_id uuid NOT NULL REFERENCES college.procedure_requirement(id),
    done_on        date NOT NULL,
    patient_ref    text NULL,
    mode           text NOT NULL,
    verified_by    uuid NULL REFERENCES iam.person(id),
    verified_at    timestamptz NULL,
    CONSTRAINT ck_college_proclog_mode CHECK (mode IN ('OBSERVE','PERFORM'))
);
SELECT audit.attach('college.procedure_log');

CREATE TABLE college.case_clerking (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    posting_id  uuid NOT NULL REFERENCES college.posting(id),
    done_on     date NOT NULL,
    patient_ref text NULL,
    presented   boolean NOT NULL DEFAULT false,
    verified_by uuid NULL REFERENCES iam.person(id)
);
SELECT audit.attach('college.case_clerking');

CREATE TABLE college.mandatory_event (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    block_id  uuid NULL REFERENCES college.block(id),
    name      text NOT NULL,
    weekday   int  NULL,
    UNIQUE (block_id, name),
    CONSTRAINT ck_college_event_day CHECK (weekday IS NULL OR weekday BETWEEN 1 AND 7)
);
SELECT audit.attach('college.mandatory_event');
INSERT INTO college.mandatory_event (block_id, name, weekday)
SELECT b.id, e.name, e.weekday FROM college.block b, (VALUES ('Grand Round', 3), ('Case Management Conference', NULL)) e(name, weekday) WHERE b.code = 'PAE';

CREATE TABLE college.event_attendance (
    event_id   uuid NOT NULL REFERENCES college.mandatory_event(id),
    student_id uuid NOT NULL REFERENCES people.student(id),
    held_on    date NOT NULL,
    present    boolean NOT NULL,
    PRIMARY KEY (event_id, student_id, held_on)
);
SELECT audit.attach('college.event_attendance');

-- ── 8 · attendance: the rule, and the record it is judged on ────────────────
CREATE TABLE college.attendance_rule (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope      text NOT NULL,
    phase      text NULL,
    block_id   uuid NULL REFERENCES college.block(id),
    min_pct    int  NOT NULL,
    applies_to text NOT NULL DEFAULT 'OVERALL',
    note       text NULL,
    CONSTRAINT ck_college_att_scope CHECK (scope IN ('PHASE','BLOCK')),
    CONSTRAINT ck_college_att_phase CHECK (phase IS NULL OR phase IN ('PREMEDICAL','PRECLINICAL','CLINICAL')),
    CONSTRAINT ck_college_att_pct   CHECK (min_pct BETWEEN 0 AND 100),
    CONSTRAINT ck_college_att_target CHECK ((scope = 'PHASE' AND phase IS NOT NULL) OR (scope = 'BLOCK' AND block_id IS NOT NULL))
);
SELECT audit.attach('college.attendance_rule');
INSERT INTO college.attendance_rule (scope, phase, block_id, min_pct, applies_to, note) VALUES
    ('PHASE', 'PRECLINICAL', NULL, 75, 'EACH_ACTIVITY_AND_OVERALL', 'For the Comprehensive Promotional and the 1st Professional'),
    ('PHASE', 'CLINICAL',    NULL, 70, 'OVERALL', 'For the 2nd and 3rd Professionals; the regulations do not state it for the Final');
INSERT INTO college.attendance_rule (scope, block_id, min_pct, applies_to, note)
SELECT 'BLOCK', b.id, 80, 'OVERALL', 'Surgery requires 80% attendance and participation to sit its final — against the 70% general rule, to resolve' FROM college.block b WHERE b.code = 'SUG';

CREATE TABLE college.attendance_record (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    activity_type text NOT NULL,
    posting_id    uuid NULL REFERENCES college.posting(id),
    slot_id       uuid NULL REFERENCES college.timetable_slot(id),
    held_on       date NOT NULL,
    present       boolean NOT NULL,
    recorded_by   uuid NULL REFERENCES iam.person(id),
    CONSTRAINT ck_college_attrec_type CHECK (activity_type IN ('LECTURE','PRACTICAL','CLINICAL','TUTORIAL','TEST','OTHER'))
);
SELECT audit.attach('college.attendance_record');

-- ── 9 · the Professional examinations, their subjects, CA items and scores ──
CREATE TABLE college.professional_exam (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code                 text NOT NULL UNIQUE,
    name                 text NOT NULL,
    level                int  NOT NULL REFERENCES college.level(level),
    papers               text[] NOT NULL,
    external_examiners   boolean NOT NULL DEFAULT false,
    resit_allowed        boolean NOT NULL,
    resit_window_months  int  NOT NULL DEFAULT 3,
    no_resit_if_all_failed boolean NOT NULL DEFAULT false,
    appeal_to_senate     boolean NOT NULL DEFAULT false,
    min_attendance_pct   int  NULL,
    on_failure           text NOT NULL,
    ordinal              int  NOT NULL,
    CONSTRAINT ck_college_exam_code CHECK (code IN ('CPE','PE1','PE2','PE3','PE4'))
);
SELECT audit.attach('college.professional_exam');
INSERT INTO college.professional_exam (code, name, level, papers, external_examiners, resit_allowed, no_resit_if_all_failed, appeal_to_senate, min_attendance_pct, on_failure, ordinal) VALUES
    ('CPE', 'Comprehensive Promotional Examination', 200, ARRAY['ESSAY','MCQ','PRACTICAL','ORAL_OPTIONAL'], false, false, false, false, 75,
     'Failing any subject: repeat 200 Level with fresh CA, a second and final attempt; failing again, advice to withdraw. A failed EPS course is carried over.', 1),
    ('PE1', '1st Professional MBBS', 300, ARRAY['ESSAY','MCQ','PRACTICAL','ORAL'], true, true, true, false, 75,
     'Fail all three subjects: repeat 300 Level, no resit. Fail one or two: resit within three months with fresh CA; fail the resit: repeat 300 Level; fail after repeating: advised to withdraw.', 2),
    ('PE2', '2nd Professional MBBS', 400, ARRAY['ESSAY','MCQ','PRACTICAL','ORAL'], false, true, false, false, 70,
     'Fail the resit: repeat the class with fresh 400 Level CA; fail after repeating: must withdraw.', 3),
    ('PE3', '3rd Professional MBBS', 500, ARRAY['ESSAY','MCQ','CLINICAL'], false, true, false, false, 70,
     'Fail the resit: repeat with fresh 500 Level CA; fail after repeating: must withdraw.', 4),
    ('PE4', '4th Professional (Final) MBBS', 600, ARRAY['ESSAY','MCQ','CLINICAL'], false, true, false, true, NULL,
     'Fail the resit: repeat 600 Level; fail after repeating: advised to withdraw, with an appeal to Senate for a fourth and final attempt.', 5);

CREATE TABLE college.exam_subject (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id                uuid NOT NULL REFERENCES college.professional_exam(id),
    name                   text NOT NULL,
    departments            text NULL,
    ca_weight              numeric(5,2) NOT NULL DEFAULT 30,
    exam_weight            numeric(5,2) NOT NULL DEFAULT 70,
    pass_mark              int  NOT NULL DEFAULT 50,
    clinical_component_min int  NULL,
    conflict_note          text NULL,
    ordinal                int  NOT NULL,
    UNIQUE (exam_id, name),
    CONSTRAINT ck_college_subject_weights CHECK (ca_weight + exam_weight = 100)
);
SELECT audit.attach('college.exam_subject');
INSERT INTO college.exam_subject (exam_id, name, departments, clinical_component_min, conflict_note, ordinal)
SELECT e.id, s.name, s.departments, s.clinical_min, s.conflict, s.ord
  FROM college.professional_exam e
  JOIN (VALUES
        ('CPE', 'Anatomy', NULL, NULL, NULL, 1), ('CPE', 'Biochemistry', NULL, NULL, NULL, 2), ('CPE', 'Physiology', NULL, NULL, NULL, 3),
        ('PE1', 'Anatomy', NULL, NULL, NULL, 1), ('PE1', 'Medical Biochemistry', NULL, NULL, NULL, 2), ('PE1', 'Physiology', NULL, NULL, NULL, 3),
        ('PE2', 'Pathology', 'Chemical Pathology & Immunology; Haematology; Microbiology & Parasitology; Morbid Anatomy & Forensic Medicine', NULL, NULL, 1),
        ('PE2', 'Pharmacology & Therapeutics', 'Pharmacology', NULL, 'The Pharmacology chapter says CA is 50% of the final mark; the regulations say 30% — to resolve', 2),
        ('PE3', 'Paediatrics', 'Paediatrics', 50, NULL, 1), ('PE3', 'Obstetrics & Gynaecology', 'Obstetrics & Gynaecology', 50, 'O&G says its examination is held with Community Health and Paediatrics; the regulations put Community Medicine in the 4th', 2),
        ('PE4', 'Medicine', 'General Medicine and its sub-specialties; Psychiatry; Family Medicine', 50, NULL, 1),
        ('PE4', 'Surgery', 'General Surgery; Anaesthesia; ENT; Orthopaedics; Ophthalmology; Neurosurgery; Radiology', 50, NULL, 2),
        ('PE4', 'Community Medicine & Epidemiology', 'Biostatistics; Epidemiology; PHC & Community Medicine', 50, 'Its chapter says Professional examinations at 300 and 600 levels; the regulations list it only in the 4th', 3)
       ) s(exam, name, departments, clinical_min, conflict, ord) ON s.exam = e.code;

CREATE TABLE college.assessment_item (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id       uuid NULL REFERENCES college.exam_subject(id),
    posting_id       uuid NULL REFERENCES college.posting(id),
    item_type        text NOT NULL,
    name             text NOT NULL,
    weight_within_ca numeric(5,2) NULL,
    max_score        numeric(6,2) NOT NULL DEFAULT 100,
    eligibility_gate boolean NOT NULL DEFAULT false,
    note             text NULL,
    CONSTRAINT ck_college_item_type CHECK (item_type IN ('COURSE_TEST','END_OF_POSTING_MCQ','END_OF_POSTING_CLINICAL','SUPERVISOR_EVAL','ORAL','PROJECT','OSCE','PERIODIC_TEST')),
    CONSTRAINT ck_college_item_owner CHECK (subject_id IS NOT NULL OR posting_id IS NOT NULL)
);
SELECT audit.attach('college.assessment_item');
COMMENT ON COLUMN college.assessment_item.weight_within_ca IS 'How the 30% CA splits across the items — the prospectus does not say; NULL until the department does.';
INSERT INTO college.assessment_item (subject_id, item_type, name, eligibility_gate, note)
SELECT s.id, i.item_type, i.name, i.gate, i.note
  FROM college.exam_subject s JOIN college.professional_exam e ON e.id = s.exam_id
  JOIN (VALUES
        ('PE2', 'Pharmacology & Therapeutics', 'COURSE_TEST', 'Course test (about 32 MCQs, two essays, an oral); at least four by the end of the course', true, 'Attendance at every test is compulsory for eligibility'),
        ('PE2', 'Pharmacology & Therapeutics', 'PERIODIC_TEST', 'End-of-semester CA test', false, NULL),
        ('PE3', 'Paediatrics', 'SUPERVISOR_EVAL', 'Continuous assessment of performance in all areas', false, NULL),
        ('PE3', 'Paediatrics', 'END_OF_POSTING_MCQ', 'Junior end-of-posting examination, end of week 8 (true/false, one in five)', false, NULL),
        ('PE3', 'Paediatrics', 'END_OF_POSTING_CLINICAL', 'Senior end-of-posting examination: long and short case, orals', false, NULL),
        ('PE3', 'Obstetrics & Gynaecology', 'OSCE', 'Electronic and non-electronic OSCE, with MCQs and essays', false, NULL),
        ('PE4', 'Medicine', 'END_OF_POSTING_CLINICAL', 'Psychiatry end-of-posting clinical examination, week 8', false, 'Counts as CA'),
        ('PE4', 'Surgery', 'COURSE_TEST', 'Test at the end of each lecture group', false, 'Forms the CA and counts toward the final'),
        ('PE4', 'Community Medicine & Epidemiology', 'PROJECT', 'Community study project — two bound copies, graded by neutral lecturers, defended at the orals', true, 'A prerequisite for the final examinations')
       ) i(exam, subject, item_type, name, gate, note) ON i.exam = e.code AND i.subject = s.name;

CREATE TABLE college.assessment_score (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    item_id     uuid NOT NULL REFERENCES college.assessment_item(id),
    attempt_no  int  NOT NULL DEFAULT 1,
    score       numeric(6,2) NOT NULL,
    assessor_id uuid NULL REFERENCES iam.person(id),
    scored_on   date NOT NULL DEFAULT current_date,
    UNIQUE (student_id, item_id, attempt_no)
);
SELECT audit.attach('college.assessment_score');

CREATE TABLE college.project (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        uuid NOT NULL REFERENCES people.student(id),
    block_id          uuid NULL REFERENCES college.block(id),
    topic             text NOT NULL,
    supervisor_id     uuid NULL REFERENCES iam.person(id),
    copies_submitted  int  NOT NULL DEFAULT 0,
    grade             numeric(6,2) NULL,
    defended          boolean NOT NULL DEFAULT false,
    exam_prerequisite boolean NOT NULL DEFAULT true
);
SELECT audit.attach('college.project');

-- ── 10 · the result by attempt, and the progression decision ────────────────
CREATE TABLE college.exam_result (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     uuid NOT NULL REFERENCES people.student(id),
    subject_id     uuid NOT NULL REFERENCES college.exam_subject(id),
    session        text NOT NULL REFERENCES policy.academic_session(name),
    attempt        text NOT NULL,
    ca_score       numeric(6,2) NULL,
    exam_score     numeric(6,2) NULL,
    clinical_score numeric(6,2) NULL,
    total          numeric(6,2) GENERATED ALWAYS AS (coalesce(ca_score, 0) + coalesce(exam_score, 0)) STORED,
    passed         boolean NULL,
    decided_on     date NULL,
    UNIQUE (student_id, subject_id, session, attempt),
    CONSTRAINT ck_college_result_attempt CHECK (attempt IN ('FIRST','RESIT','REPEAT','SENATE_APPEAL'))
);
SELECT audit.attach('college.exam_result');

CREATE TABLE college.progression_decision (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    from_level  int  NOT NULL REFERENCES college.level(level),
    session     text NOT NULL REFERENCES policy.academic_session(name),
    outcome     text NOT NULL,
    carry_overs text[] NOT NULL DEFAULT '{}',
    rule_ref    text NULL,
    minute      text NULL,
    decided_on  date NOT NULL DEFAULT current_date,
    UNIQUE (student_id, from_level, session),
    CONSTRAINT ck_college_decision CHECK (outcome IN ('PROMOTE','RESIT','REPEAT','WITHDRAW_ADVISED','WITHDRAW_REQUIRED','APPEAL'))
);
SELECT audit.attach('college.progression_decision');

-- ── 11 · the rules as functions ─────────────────────────────────────────────
-- a subject is passed at 50 or more in all; for a subject with a clinical component, 50 or more there too
CREATE OR REPLACE FUNCTION college.passes(p_subject uuid, p_ca numeric, p_exam numeric, p_clinical numeric DEFAULT NULL)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce(p_ca, 0) + coalesce(p_exam, 0) >= s.pass_mark
       AND (s.clinical_component_min IS NULL OR coalesce(p_clinical, 0) >= s.clinical_component_min)
      FROM college.exam_subject s WHERE s.id = p_subject
$$;

-- a distinction is 70 or more in the subject
CREATE OR REPLACE FUNCTION college.distinction(p_programme text, p_total numeric)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_total >= r.distinction_mark FROM college.programme_rule r WHERE r.programme_code = p_programme
$$;

-- the resit rule after a first attempt: which attempt follows, by the examination's rule
CREATE OR REPLACE FUNCTION college.next_attempt(p_exam text, p_failed int, p_of int)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_failed = 0 THEN 'PROMOTE'
                WHEN NOT e.resit_allowed THEN 'REPEAT'
                WHEN e.no_resit_if_all_failed AND p_failed >= p_of THEN 'REPEAT'
                ELSE 'RESIT' END
      FROM college.professional_exam e WHERE e.code = p_exam
$$;

-- honours: at least one distinction in each of the four Professionals
CREATE OR REPLACE FUNCTION college.honours(p_student uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT (SELECT count(DISTINCT e.code)
              FROM college.exam_result r JOIN college.exam_subject s ON s.id = r.subject_id JOIN college.professional_exam e ON e.id = s.exam_id
             WHERE r.student_id = p_student AND r.passed AND e.code IN ('PE1','PE2','PE3','PE4') AND r.total >= 70) = 4
$$;

-- what a posting asks of a student, and what is on record
CREATE OR REPLACE FUNCTION college.posting_logbook(p_student uuid, p_posting uuid)
RETURNS TABLE (requirement text, min_count int, mode text, done bigint, met boolean)
LANGUAGE sql STABLE AS $$
    SELECT pr.name, pr.min_count, pr.mode,
           (SELECT count(*) FROM college.procedure_log l WHERE l.student_id = p_student AND l.requirement_id = pr.id AND l.verified_at IS NOT NULL
               AND (pr.mode = 'EITHER' OR l.mode = pr.mode)),
           (SELECT count(*) FROM college.procedure_log l WHERE l.student_id = p_student AND l.requirement_id = pr.id AND l.verified_at IS NOT NULL
               AND (pr.mode = 'EITHER' OR l.mode = pr.mode)) >= pr.min_count
      FROM college.procedure_requirement pr WHERE pr.posting_id = p_posting
    UNION ALL
    SELECT 'Cases clerked', p.min_cases, 'EITHER',
           (SELECT count(*) FROM college.case_clerking c WHERE c.student_id = p_student AND c.posting_id = p_posting),
           (SELECT count(*) FROM college.case_clerking c WHERE c.student_id = p_student AND c.posting_id = p_posting) >= p.min_cases
      FROM college.posting p WHERE p.id = p_posting AND p.min_cases IS NOT NULL
$$;

-- ── 12 · who reads and writes ───────────────────────────────────────────────
GRANT USAGE ON SCHEMA college TO app_results, app_registration, app_student, app_auditor;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA college TO app_results, app_registration;
GRANT SELECT ON ALL TABLES IN SCHEMA college TO app_student, app_auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA college GRANT SELECT, INSERT, UPDATE ON TABLES TO app_results, app_registration;
ALTER DEFAULT PRIVILEGES IN SCHEMA college GRANT SELECT ON TABLES TO app_student, app_auditor;

COMMIT;
