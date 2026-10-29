-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V701 — Preliminary Technology & Industrial Studies, and the Adikpo Campus proficiency certificate courses, on the preliminary
--        stack of V446
--
--   The University's master prompt of 29 October 2026 ("PRELIMINARY TECHNOLOGY & INDUSTRIAL STUDIES + ADIKPO PROFICIENCY
--   CERTIFICATE PROGRAMMES"): two more offerings, neither an undergraduate degree, both on the portal's one application, fee,
--   O'Level, document, notification, window and audit stack. V446 built that stack for Preliminary Science as routes; nothing here
--   is a second application, payment, eligibility or student system. Added:
--
--     two routes       PRELIMINARY_TECHNOLOGY (Preliminary Technology & Industrial Studies, programme type PRELIMINARY, entry
--                      mode PRELIMINARY like Preliminary Science) and PROFICIENCY_CERTIFICATE (the Adikpo Campus proficiency
--                      certificate courses, programme type PROFICIENCY_CERTIFICATE, entry mode PROFICIENCY so that its payments
--                      and records are never read as preliminary or undergraduate), each with its own window, office, fee, rule,
--                      documents and notices, all data in admissions.prelim_programme
--     the office       prelimtech — the Preliminary Vocational & Technical Education Office (the HR unit of V253): it reviews and
--                      recommends both; the Academic Office approves and publishes, never the recommender (as V446)
--     the campus       ref.campus (none existed): the main campus and Adikpo Campus; a programme names its campus
--     the rule         per route: an O'Level rule (credits, sittings, a credit grade, subjects that must be credited, a list some
--                      of which must be credited — per target where the target says so — and the completion rule, over every
--                      credit or the relevant ones), or the rule that a secondary school certificate was attempted; the
--                      qualifications a route accepts (admissions.qualification_type)
--     the targets      a target is a programme on the register (Preliminary Technology's three areas: B.Sc. (Ed) Home Economics,
--                      B.Sc. (Ed) Business Education, B.Sc. (Ed) Technology) or a certificate course (Adikpo's 30, in three
--                      categories), with its own subject list where the area has one; the options within a target programme
--                      (admissions.prelim_specialisation — catalogue.programme_specialisation is the postgraduate programmes')
--     the review       the target chosen by id, and the specialisation (prelim_review.target_id, specialisation_id)
--
--   Not done, for want of the University's word (docs/preliminary-technology-and-proficiency.md): the proficiency application fee
--   (FEE NOT CONFIGURED), any acceptance or school fee, the duration of Preliminary Technology, the windows' dates (closed until the
--   Director of ICT opens them), the identity number and the move onto the student register, courses, attendance, results and
--   certificates (none issued until completion is configured).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V701: Preliminary Technology & Industrial Studies and the Adikpo Campus proficiency certificate courses', true);

-- ── 1 · the office, the campus, the programme type ─────────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('prelimtech', 'Preliminary Vocational and Technical Education Office', 'institution')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE ref.campus (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,19}$'),
    name        text NOT NULL CHECK (btrim(name) <> ''),
    town        text NULL,
    main        boolean NOT NULL DEFAULT false,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_campus_main ON ref.campus (main) WHERE main;
SELECT audit.attach('ref.campus');
COMMENT ON TABLE ref.campus IS
  'V701: the University''s campuses — the main campus at Makurdi and Adikpo Campus. A programme run at a campus names it (admissions.prelim_programme.campus_code); none existed before.';
INSERT INTO ref.campus (code, name, town, main) VALUES ('MAKURDI', 'Main Campus, Makurdi', 'Makurdi', true), ('ADIKPO', 'Adikpo Campus', 'Adikpo', false)
ON CONFLICT (code) DO NOTHING;

-- the proficiency certificate courses are a programme type of their own: never preliminary, never a degree (V409's types)
INSERT INTO finance.programme_type (code, label, ord, entry_modes, programme_categories, study_mode, description, offices)
VALUES ('PROFICIENCY_CERTIFICATE', 'Proficiency certificate', 65, ARRAY['PROFICIENCY'], '{}', 'FULL_TIME',
        'The proficiency certificate courses of Adikpo Campus (V701): skill certificates of nine months, not degree programmes', ARRAY['prelimtech'])
ON CONFLICT (code) DO NOTHING;
INSERT INTO finance.payment_classification (purpose, programme_type, source_module, responsible_office, note)
SELECT NULL, 'PROFICIENCY_CERTIFICATE', 'PROFICIENCY_CERTIFICATE', 'prelimtech', 'The Adikpo Campus proficiency certificate courses'' applications and fees (V701)'
 WHERE NOT EXISTS (SELECT 1 FROM finance.payment_classification WHERE purpose IS NULL AND programme_type = 'PROFICIENCY_CERTIFICATE');
UPDATE finance.programme_type SET description = 'The Preliminary Science Programme (V446), Preliminary Technology & Industrial Studies (V701) and any other preliminary programme run as an admission route',
       offices = (SELECT array_agg(DISTINCT o) FROM unnest(offices || ARRAY['prelim', 'prelimtech']) o)
 WHERE code = 'PRELIMINARY';
UPDATE finance.payment_classification SET note = 'The preliminary programmes'' applications and fees — Preliminary Science (V446) and Preliminary Technology & Industrial Studies (V701)'
 WHERE purpose IS NULL AND programme_type = 'PRELIMINARY';

-- a route's code names it (PRELIMINARY_TECHNOLOGY, PROFICIENCY_CERTIFICATE): up to thirty letters, from V379's twenty
ALTER TABLE policy.study_route DROP CONSTRAINT study_route_code_check;
ALTER TABLE policy.study_route ADD CONSTRAINT study_route_code_check CHECK (code ~ '^[A-Z][A-Z_]{1,29}$');

-- ── 2 · the applicant of a proficiency course: no JAMB record, entry level 0, admitted off the Office's review ──────────
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_jamb_number;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_jamb_number CHECK (jamb_reg_no IS NOT NULL OR entry_mode IN ('PRELIMINARY', 'PROFICIENCY'));
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_level;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_level CHECK (
    (entry_mode = 'UTME' AND entry_level = 100) OR (entry_mode IN ('DIRECT_ENTRY', 'TRANSFER') AND entry_level IN (200, 300))
    OR (entry_mode = 'CCE' AND entry_level IN (100, 200, 300)) OR (entry_mode IN ('PRELIMINARY', 'PROFICIENCY') AND entry_level = 0));
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_needs_caps;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_needs_caps CHECK (
    offer_state = 'PROPOSED' OR admitted_from IS NOT NULL OR cce_candidate_id IS NOT NULL OR entry_mode IN ('PRELIMINARY', 'PROFICIENCY'));
CREATE OR REPLACE FUNCTION admissions.applicant_account_key_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.jamb_key IS NULL AND NOT EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.id = NEW.candidate_id AND c.entry_mode IN ('PRELIMINARY', 'PROFICIENCY')) THEN
        RAISE EXCEPTION 'APPLICANT_JAMB_KEY: an applicant account carries the JAMB number, except on a route JAMB does not list' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;

-- a third passport photograph, where a route asks for three (Preliminary Technology's procedure)
ALTER TABLE admissions.application_document DROP CONSTRAINT ck_doc_kind;
ALTER TABLE admissions.application_document ADD CONSTRAINT ck_doc_kind CHECK (kind IN (
    'OLEVEL_STATEMENT', 'OLEVEL_STATEMENT_2', 'BIRTH_CERT', 'LGA_ID', 'JAMB_SLIP', 'PASSPORT', 'JAMB_ADMISSION_LETTER', 'STATE_OF_ORIGIN',
    'MARRIAGE_CERT', 'CHANGE_OF_NAME', 'PREVIOUS_QUALIFICATION', 'OTHER', 'PASSPORT_2', 'PASSPORT_3'));
ALTER TABLE admissions.prelim_document DROP CONSTRAINT ck_prelim_document_kind;
ALTER TABLE admissions.prelim_document ADD CONSTRAINT ck_prelim_document_kind CHECK (kind IN ('OLEVEL_STATEMENT', 'OLEVEL_STATEMENT_2', 'BIRTH_CERT', 'LGA_ID',
    'PASSPORT', 'PASSPORT_2', 'PASSPORT_3', 'STATE_OF_ORIGIN', 'CHANGE_OF_NAME', 'MARRIAGE_CERT', 'PREVIOUS_QUALIFICATION', 'OTHER'));

-- ── 3 · the qualifications a sitting is: the school certificate and its equivalents, a route accepting some of them ────
CREATE TABLE admissions.qualification_type (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,19}$'),
    label       text NOT NULL CHECK (btrim(label) <> ''),
    ord         integer NOT NULL DEFAULT 100,
    active      boolean NOT NULL DEFAULT true
);
SELECT audit.attach('admissions.qualification_type');
COMMENT ON TABLE admissions.qualification_type IS
  'V701: the examinations an O''Level sitting may be — the school certificate (May/June), the GCE and the technical and craft equivalents the University accepts for its preliminary and proficiency programmes. A route lists those it accepts (admissions.prelim_programme.qualification_types).';
INSERT INTO admissions.qualification_type (code, label, ord) VALUES
    ('SSCE', 'Senior School Certificate (May/June)', 10),
    ('GCE', 'General Certificate of Education (Nov/Dec)', 20),
    ('NTC', 'National Technical Certificate (NTC)', 30),
    ('NBC', 'National Business Certificate (NBC)', 40),
    ('CG_I', 'City & Guilds Part I', 50),
    ('CG_II', 'City & Guilds Part II', 60),
    ('FCTC', 'Federal Craft Training Certificate', 70),
    ('TC_II', 'Technical Certificate (TC II)', 80),
    ('OTHER', 'Another equivalent the University approves', 900)
ON CONFLICT (code) DO NOTHING;
ALTER TABLE admissions.screening_olevel DROP CONSTRAINT screening_olevel_exam_type_check;
ALTER TABLE admissions.screening_olevel ADD CONSTRAINT fk_screening_olevel_exam_type FOREIGN KEY (exam_type) REFERENCES admissions.qualification_type (code);
COMMENT ON COLUMN admissions.screening_olevel.exam_type IS 'V446/V701: the examination of the sitting — a qualification type (SSCE, GCE, NTC, NBC, City & Guilds, …).';

-- ── 4 · the programme: its window, office, campus, duration, and its rule as data ──────────────────────────────────
ALTER TABLE admissions.prelim_programme
    ADD COLUMN window_type        text NULL,
    ADD COLUMN office_code        text NULL REFERENCES ref.office (code),
    ADD COLUMN campus_code        text NULL REFERENCES ref.campus (code),
    ADD COLUMN duration_months    integer NULL CHECK (duration_months IS NULL OR duration_months BETWEEN 1 AND 120),
    ADD COLUMN certificate_type   text NULL,
    ADD COLUMN entry_requirement  text NULL,
    ADD COLUMN rule_kind          text NOT NULL DEFAULT 'OLEVEL_CREDITS' CHECK (rule_kind IN ('OLEVEL_CREDITS', 'ATTEMPTED_CERTIFICATE')),
    ADD COLUMN required_subjects  text[] NOT NULL DEFAULT '{}' CHECK (cardinality(required_subjects) <= 9),
    ADD COLUMN core_by_target     boolean NOT NULL DEFAULT false,
    ADD COLUMN completion_scope   text NOT NULL DEFAULT 'ANY' CHECK (completion_scope IN ('ANY', 'RELEVANT')),
    ADD COLUMN qualification_types text[] NOT NULL DEFAULT ARRAY['SSCE', 'GCE', 'OTHER'],
    ADD COLUMN target_word        text NOT NULL DEFAULT 'target programme' CHECK (btrim(target_word) <> ''),
    ADD COLUMN group_word         text NOT NULL DEFAULT 'group' CHECK (btrim(group_word) <> ''),
    ADD COLUMN target_note        text NULL;
ALTER TABLE admissions.prelim_programme DROP CONSTRAINT prelim_programme_core_subjects_check;
ALTER TABLE admissions.prelim_programme ADD CONSTRAINT prelim_programme_core_subjects_check CHECK (cardinality(core_subjects) <= 30);
ALTER TABLE admissions.prelim_programme DROP CONSTRAINT ck_prelim_core_within;
ALTER TABLE admissions.prelim_programme ADD CONSTRAINT ck_prelim_core_within CHECK (
    rule_kind = 'ATTEMPTED_CERTIFICATE' OR core_by_target
    OR (cardinality(core_subjects) >= 1 AND min_core_credits <= cardinality(core_subjects) AND min_core_credits <= min_credits));
COMMENT ON COLUMN admissions.prelim_programme.rule_kind IS
  'V701: OLEVEL_CREDITS — the credit rule (min_credits, required_subjects, core_subjects or the target''s, completion); ATTEMPTED_CERTIFICATE — a secondary school certificate attempted, its results given (the proficiency courses).';
COMMENT ON COLUMN admissions.prelim_programme.core_by_target IS 'V701: the subjects some of which must be credited are each target''s own (Preliminary Technology''s areas), not the programme''s.';
COMMENT ON COLUMN admissions.prelim_programme.completion_scope IS 'V701: the completion rule counts every credit (ANY, Preliminary Science) or only the relevant ones — the required subjects and the target''s list (RELEVANT, Preliminary Technology).';
UPDATE admissions.prelim_programme SET window_type = 'PRELIMINARY_SCIENCE_APPLICATION', office_code = 'prelim', campus_code = 'MAKURDI',
       target_note = 'Selection of a target programme under Preliminary Science does not constitute admission into the undergraduate programme. Subsequent admission remains subject to University requirements and applicable admission processes.'
 WHERE route = 'PRELIMINARY_SCIENCE';
ALTER TABLE admissions.prelim_programme ALTER COLUMN window_type SET NOT NULL;
ALTER TABLE admissions.prelim_programme ALTER COLUMN office_code SET NOT NULL;
CREATE UNIQUE INDEX ux_prelim_programme_window ON admissions.prelim_programme (window_type);

-- ── 5 · the targets: a programme on the register, or a certificate course; an area's own subjects; the options ─────
ALTER TABLE admissions.prelim_target
    ADD COLUMN kind              text NOT NULL DEFAULT 'PROGRAMME' CHECK (kind IN ('PROGRAMME', 'COURSE')),
    ADD COLUMN core_subjects     text[] NULL CHECK (core_subjects IS NULL OR cardinality(core_subjects) BETWEEN 1 AND 30),
    ADD COLUMN min_core_credits  integer NULL CHECK (min_core_credits IS NULL OR min_core_credits >= 0),
    ADD COLUMN description       text NULL,
    ADD COLUMN duration_months   integer NULL CHECK (duration_months IS NULL OR duration_months BETWEEN 1 AND 120);
ALTER TABLE admissions.prelim_target DROP CONSTRAINT ck_prelim_target_mapped;
ALTER TABLE admissions.prelim_target ADD CONSTRAINT ck_prelim_target_mapped CHECK (
    (kind = 'PROGRAMME' AND (state = 'MISSING') = (programme_code IS NULL))
    OR (kind = 'COURSE' AND programme_code IS NULL AND state IN ('MAPPED', 'WITHDRAWN')));
ALTER TABLE admissions.prelim_target ADD CONSTRAINT ck_prelim_target_core CHECK (core_subjects IS NULL OR min_core_credits IS NULL OR min_core_credits <= cardinality(core_subjects));
CREATE UNIQUE INDEX ux_prelim_target_course ON admissions.prelim_target (route, lower(btrim(requested_name))) WHERE kind = 'COURSE';
COMMENT ON COLUMN admissions.prelim_target.kind IS 'V701: PROGRAMME — an undergraduate programme of the register (the intended progression); COURSE — a certificate course of the programme itself (the proficiency courses), never a degree programme.';
COMMENT ON COLUMN admissions.prelim_target.core_subjects IS 'V701: the subjects some of which must be credited for this target (an area of Preliminary Technology); none — the programme''s own.';

CREATE TABLE admissions.prelim_specialisation (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id   uuid NOT NULL REFERENCES admissions.prelim_target (id),
    code        text NOT NULL CHECK (code ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),
    name        text NOT NULL CHECK (btrim(name) <> ''),
    ord         integer NOT NULL DEFAULT 100,
    active      boolean NOT NULL DEFAULT true,
    added_by    uuid NULL,
    added_office text NULL,
    added_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (target_id, code)
);
CREATE UNIQUE INDEX ux_prelim_specialisation_name ON admissions.prelim_specialisation (target_id, lower(btrim(name)));
SELECT audit.attach('admissions.prelim_specialisation');
COMMENT ON TABLE admissions.prelim_specialisation IS
  'V701: the options of a preliminary target programme (B.Sc. (Ed) Business Education: Accounting Education, …) the applicant chooses with it — an intended option, never a registration in it. catalogue.programme_specialisation is the postgraduate programmes'' structure and is not used for undergraduate targets.';

ALTER TABLE admissions.prelim_review
    ADD COLUMN target_id          uuid NULL REFERENCES admissions.prelim_target (id),
    ADD COLUMN specialisation_id  uuid NULL REFERENCES admissions.prelim_specialisation (id);
CREATE INDEX ix_prelim_review_target_id ON admissions.prelim_review (target_id);
UPDATE admissions.prelim_review r SET target_id = t.id
  FROM admissions.prelim_target t
 WHERE t.route = r.route AND t.programme_code = r.target_programme AND r.target_id IS NULL;
COMMENT ON COLUMN admissions.prelim_review.target_id IS 'V701: the target chosen (a programme or a certificate course); target_programme keeps the programme''s code where it is one.';

-- ── 6 · the windows: one a route ───────────────────────────────────────────────────────────────────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check CHECK ((window_type = ANY (ARRAY['SCHOOL_FEES_PAYMENT'::text, 'COURSE_REGISTRATION'::text, 'ADMISSION_STATUS_CHECKING'::text, 'POST_UTME_REGISTRATION'::text, 'POSTGRADUATE_APPLICATION'::text, 'POSTGRADUATE_ADMISSION_STATUS_CHECKING'::text, 'JUPEB_APPLICATION'::text, 'JUPEB_ADMISSION_STATUS_CHECKING'::text, 'CCE_APPLICATION'::text, 'CCE_SCHOOL_FEES_PAYMENT'::text, 'CCE_COURSE_REGISTRATION'::text, 'POST_UTME_CBT'::text, 'POST_UTME_RESULT_CHECKING'::text, 'PG_SCHOOL_FEES_PAYMENT'::text, 'PG_COURSE_REGISTRATION'::text, 'PRELIMINARY_SCIENCE_APPLICATION'::text, 'PRELIMINARY_TECHNOLOGY_APPLICATION'::text, 'PROFICIENCY_CERTIFICATE_APPLICATION'::text])));

ALTER TABLE policy.portal_window DROP CONSTRAINT ck_window_application_session;
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_application_session CHECK (((window_type <> ALL (ARRAY['POST_UTME_REGISTRATION'::text, 'POSTGRADUATE_APPLICATION'::text, 'JUPEB_APPLICATION'::text, 'CCE_APPLICATION'::text, 'POST_UTME_CBT'::text, 'POST_UTME_RESULT_CHECKING'::text, 'PRELIMINARY_SCIENCE_APPLICATION'::text, 'PRELIMINARY_TECHNOLOGY_APPLICATION'::text, 'PROFICIENCY_CERTIFICATE_APPLICATION'::text])) OR ((semester IS NULL) AND (late_until IS NULL) AND (NOT late_fee_enabled))));

ALTER TABLE policy.portal_window_message DROP CONSTRAINT portal_window_message_window_type_check;
ALTER TABLE policy.portal_window_message ADD CONSTRAINT portal_window_message_window_type_check CHECK ((window_type = ANY (ARRAY['POST_UTME_REGISTRATION'::text, 'POSTGRADUATE_APPLICATION'::text, 'JUPEB_APPLICATION'::text, 'CCE_APPLICATION'::text, 'POST_UTME_CBT'::text, 'POST_UTME_RESULT_CHECKING'::text, 'PRELIMINARY_SCIENCE_APPLICATION'::text, 'PRELIMINARY_TECHNOLOGY_APPLICATION'::text, 'PROFICIENCY_CERTIFICATE_APPLICATION'::text, 'SCHOOL_FEES_PAYMENT'::text])));

-- ── 6b · the proficiency applicant's admission route, and the learner register reading it ─────────────────────────────
INSERT INTO ref.admission_route (code, name, entry_mode, description, ord)
VALUES ('PROFICIENCY_APPLICATION', 'Proficiency certificate application', 'PROFICIENCY', 'Admitted through a proficiency certificate course''s application (Adikpo Campus)', 95)
ON CONFLICT DO NOTHING;
-- people.learner (V469): a preliminary or proficiency admission reads its own admission route (by the candidate's entry mode)
CREATE OR REPLACE VIEW people.learner AS
SELECT 'REGISTER'::text AS source,
    s.id AS learner_id,
    s.id AS student_id,
    s.surname,
    s.other_names,
    s.sex,
    s.matric_no,
    s.jamb_reg_no AS jamb_no,
    s.admission_no,
    COALESCE(a.application_no, pa.application_no) AS application_no,
    c.programme_type,
    c.proposed_type,
    c.type_source,
    c.classification_status,
    c.classification_issue,
    c.classification_note,
    c.admission_route,
    c.study_mode,
    c.centre_code,
    c.study_mode_differs,
    f.code AS faculty_code,
    f.name AS faculty,
    f.college_code,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    p.category AS programme_category,
    NULLIF(btrim(p.pg_award), ''::text) AS pg_award,
    false AS programme_is_target,
    s.current_level AS level,
    s.entry_session AS admission_session,
    COALESCE(ap.current_session, cur.name) AS current_session,
    s.status,
    s.matriculated_at,
        CASE
            WHEN s.entry_session ~ '^[0-9]{4}/[0-9]{4}$'::text THEN "left"(s.entry_session, 4)::integer
            ELSE NULL::integer
        END AS entry_year,
    ap.matric_year,
    ap.jamb_year,
    ap.spillover_state,
    COALESCE(ap.final_level IS NOT NULL AND s.current_level >= ap.final_level, false) AS final_year,
    ap.graduation_state,
    NULL::text AS application_status,
    NULL::text AS admission_status,
    NULL::uuid AS jupeb_combination_id,
    NULL::text AS jupeb_combination,
    NULL::uuid[] AS jupeb_subjects,
    NULL::boolean AS jupeb_registered,
    NULL::text AS prelim_route,
    NULL::text AS prelim_name
   FROM people.student s
     JOIN people.student_classification c ON c.student_id = s.id
     JOIN ref.programme p ON p.code = s.programme_code
     JOIN ref.department d ON d.code = p.dept_code
     JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN people.academic_position ap ON ap.student_id = s.id
     CROSS JOIN ( SELECT policy.university_current_session() AS name) cur
     LEFT JOIN admissions.application a ON a.candidate_id = s.candidate_id
     LEFT JOIN ( SELECT DISTINCT ON (x.student_id) x.student_id,
            x.application_no
           FROM admissions.pg_application x
          WHERE x.student_id IS NOT NULL
          ORDER BY x.student_id, x.created_at DESC) pa ON pa.student_id = s.id
  WHERE s.duplicate_of IS NULL
UNION ALL
 SELECT 'JUPEB'::text AS source,
    j.id AS learner_id,
    NULL::uuid AS student_id,
    j.surname,
    concat_ws(' '::text, j.first_name, NULLIF(btrim(j.middle_name), ''::text)) AS other_names,
    j.sex,
    NULL::text AS matric_no,
    NULL::text AS jamb_no,
    j.admission_ref AS admission_no,
    j.application_no,
    be.code AS programme_type,
    be.code AS proposed_type,
        CASE
            WHEN be.code IS NOT NULL THEN 'ENTRY_MODE'::text
            ELSE NULL::text
        END AS type_source,
        CASE
            WHEN be.code IS NULL THEN 'REQUIRES_CLASSIFICATION'::text
            ELSE 'CLASSIFIED'::text
        END AS classification_status,
        CASE
            WHEN be.code IS NULL THEN 'UNCLASSIFIED'::text
            ELSE NULL::text
        END AS classification_issue,
        CASE
            WHEN be.code IS NULL THEN 'No programme type claims the JUPEB entry mode'::text
            ELSE NULL::text
        END AS classification_note,
    r.code AS admission_route,
    t.study_mode,
    t.default_centre AS centre_code,
    false AS study_mode_differs,
    NULL::text AS faculty_code,
    NULL::text AS faculty,
    NULL::text AS college_code,
    NULL::text AS dept_code,
    NULL::text AS department,
    NULL::text AS programme_code,
    NULL::text AS programme,
    NULL::text AS programme_category,
    NULL::text AS pg_award,
    false AS programme_is_target,
    NULL::integer AS level,
    j.session AS admission_session,
    j.session AS current_session,
        CASE
            WHEN pe.id IS NOT NULL THEN 'PROGRESSED'::text
            ELSE
            CASE j.state
                WHEN 'STUDENT'::text THEN 'ACTIVE'::text
                ELSE j.state
            END
        END AS status,
    NULL::timestamp with time zone AS matriculated_at,
    "left"(j.session, 4)::integer AS entry_year,
    NULL::integer AS matric_year,
    NULL::integer AS jamb_year,
    NULL::text AS spillover_state,
    false AS final_year,
    NULL::text AS graduation_state,
    j.state AS application_status,
    'ADMITTED'::text AS admission_status,
    j.combination_id AS jupeb_combination_id,
    (cb.code || ' — '::text) || cb.name AS jupeb_combination,
        CASE
            WHEN cb.id IS NOT NULL THEN ARRAY[cb.subject1, cb.subject2, cb.subject3]
            ELSE NULL::uuid[]
        END AS jupeb_subjects,
    j.subjects_registered_at IS NOT NULL AS jupeb_registered,
    NULL::text AS prelim_route,
    NULL::text AS prelim_name
   FROM jupeb.application j
     LEFT JOIN jupeb.combination cb ON cb.id = j.combination_id
     LEFT JOIN people.programme_type_by_entry_mode be ON be.entry_mode = 'JUPEB'::text
     LEFT JOIN finance.programme_type t ON t.code = be.code
     LEFT JOIN ref.admission_route r ON r.entry_mode = 'JUPEB'::text AND r.active
     LEFT JOIN people.programme_type_event pe ON pe.jupeb_application_id = j.id AND pe.event = 'PROGRESSION'::text
  WHERE (j.state = ANY (ARRAY['ADMITTED'::text, 'STUDENT'::text, 'COMPLETED'::text, 'DEFERRED'::text])) OR j.state = 'WITHDRAWN'::text AND j.activated_at IS NOT NULL
UNION ALL
 SELECT 'PRELIMINARY'::text AS source,
    a.id AS learner_id,
    NULL::uuid AS student_id,
    cd.surname,
    cd.other_names,
    cd.sex,
    NULL::text AS matric_no,
    cd.jamb_reg_no AS jamb_no,
    cd.admission_no,
    a.application_no,
    t.code AS programme_type,
    t.code AS proposed_type,
    'PRELIMINARY_PROGRAMME'::text AS type_source,
    'CLASSIFIED'::text AS classification_status,
    NULL::text AS classification_issue,
    NULL::text AS classification_note,
    r.code AS admission_route,
    sr.study_mode,
    COALESCE(ce.code, t.default_centre) AS centre_code,
    false AS study_mode_differs,
    f.code AS faculty_code,
    f.name AS faculty,
    f.college_code,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    p.category AS programme_category,
    NULL::text AS pg_award,
    true AS programme_is_target,
    NULL::integer AS level,
    a.session AS admission_session,
    a.session AS current_session,
        CASE
            WHEN pe.id IS NOT NULL THEN 'PROGRESSED'::text
            ELSE 'ADMITTED'::text
        END AS status,
    NULL::timestamp with time zone AS matriculated_at,
        CASE
            WHEN a.session ~ '^[0-9]{4}/[0-9]{4}$'::text THEN "left"(a.session, 4)::integer
            ELSE NULL::integer
        END AS entry_year,
    NULL::integer AS matric_year,
    NULL::integer AS jamb_year,
    NULL::text AS spillover_state,
    false AS final_year,
    NULL::text AS graduation_state,
    pr.state AS application_status,
    cd.offer_state AS admission_status,
    NULL::uuid AS jupeb_combination_id,
    NULL::text AS jupeb_combination,
    NULL::uuid[] AS jupeb_subjects,
    NULL::boolean AS jupeb_registered,
    pr.route AS prelim_route,
    pp.name AS prelim_name
   FROM admissions.prelim_review pr
     JOIN admissions.application a ON a.id = pr.application_id
     JOIN admissions.candidate cd ON cd.id = a.candidate_id
     JOIN admissions.prelim_programme pp ON pp.route = pr.route
     JOIN finance.programme_type t ON t.code = pp.programme_type
     LEFT JOIN policy.study_route sr ON sr.code = pr.route
     LEFT JOIN ref.centre ce ON ce.unit_code = sr.centre_unit AND sr.centre_unit IS NOT NULL
     LEFT JOIN ref.programme p ON p.code = pr.target_programme
     LEFT JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.admission_route r ON r.entry_mode = cd.entry_mode AND r.active
     LEFT JOIN people.programme_type_event pe ON pe.application_id = a.id AND pe.event = 'PROGRESSION'::text
  WHERE pr.state = 'ADMITTED'::text;

-- ── 7 · the shared functions, restated from main with only the changes marked ──

-- policy.window_message_set: the closure message of the two new application windows
CREATE OR REPLACE FUNCTION policy.window_message_set(p_type text, p_message text, p_actor uuid, p_office text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_old text; v_new text;
BEGIN
    IF p_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION',
                      'SCHOOL_FEES_PAYMENT') THEN RAISE EXCEPTION 'no closure message for %', p_type USING ERRCODE = '23514'; END IF;
    v_new := btrim(regexp_replace(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'), '[\u0001-\u0008\u000B-\u001F\u007F]', '', 'g'));
    IF length(v_new) = 0 THEN RAISE EXCEPTION 'the closure message cannot be blank' USING ERRCODE = '23514'; END IF;
    IF length(v_new) > 2000 THEN RAISE EXCEPTION 'the closure message is at most 2000 characters' USING ERRCODE = '23514'; END IF;
    SELECT message INTO v_old FROM policy.portal_window_message WHERE window_type = p_type;
    INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office, updated_at)
    VALUES (p_type, v_new, p_actor, p_office, now())
    ON CONFLICT (window_type) DO UPDATE SET message = EXCLUDED.message, updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now();
    INSERT INTO policy.portal_window_event (window_type, session, action, previous_state, new_state, reason, actor, office)
    SELECT p_type, coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1), (SELECT max(name) FROM policy.academic_session)),
           'MESSAGE', left(v_old, 120), left(v_new, 120), 'closure message updated', p_actor, p_office
     WHERE EXISTS (SELECT 1 FROM policy.academic_session);
END $function$;

-- policy.window_state: a route's application window with no row is closed, like Preliminary Science's
CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
 RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamp with time zone, closes_at timestamp with time zone, late_until timestamp with time zone, late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING', 'PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION') THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING', 'PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION') THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$function$;

-- policy.window_word: the two new windows named
CREATE OR REPLACE FUNCTION policy.window_word(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_type
        WHEN 'SCHOOL_FEES_PAYMENT' THEN 'School fees payment'
        WHEN 'COURSE_REGISTRATION' THEN 'Course registration'
        WHEN 'ADMISSION_STATUS_CHECKING' THEN 'Admission status checking'
        WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration'
        WHEN 'POSTGRADUATE_APPLICATION' THEN 'Postgraduate application'
        WHEN 'POSTGRADUATE_ADMISSION_STATUS_CHECKING' THEN 'Postgraduate admission status checking'
        WHEN 'JUPEB_APPLICATION' THEN 'JUPEB application'
        WHEN 'JUPEB_ADMISSION_STATUS_CHECKING' THEN 'JUPEB admission status checking'
        WHEN 'CCE_APPLICATION' THEN 'CCE application'
        WHEN 'CCE_SCHOOL_FEES_PAYMENT' THEN 'CCE school fees payment'
        WHEN 'CCE_COURSE_REGISTRATION' THEN 'CCE course registration'
        WHEN 'POST_UTME_CBT' THEN 'Post-UTME CBT'
        WHEN 'POST_UTME_RESULT_CHECKING' THEN 'Post-UTME result checking'
        WHEN 'PG_SCHOOL_FEES_PAYMENT' THEN 'Postgraduate school fees payment'
        WHEN 'PG_COURSE_REGISTRATION' THEN 'Postgraduate course registration'
        WHEN 'PRELIMINARY_SCIENCE_APPLICATION' THEN 'Preliminary Science application'
        WHEN 'PRELIMINARY_TECHNOLOGY_APPLICATION' THEN 'Preliminary Technology & Industrial Studies application'
        WHEN 'PROFICIENCY_CERTIFICATE_APPLICATION' THEN 'Proficiency certificate (Adikpo Campus) application'
        ELSE initcap(replace(lower(p_type), '_', ' ')) END
$function$;

-- policy.window_act: the Director of ICT opens, closes, schedules and extends the two new windows like the others
CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamp with time zone, p_closes timestamp with time zone, p_late_until timestamp with time zone, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION',
                      'CCE_SCHOOL_FEES_PAYMENT', 'CCE_COURSE_REGISTRATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
                      'PG_SCHOOL_FEES_PAYMENT', 'PG_COURSE_REGISTRATION', 'PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING')
       AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: this window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION')
       AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $function$;

-- policy.application_session: every preliminary route's window reads its own session
CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_intake_session()
                WHEN p_type = 'CCE_APPLICATION' THEN policy.route_session('CCE')
                -- V701: a preliminary or proficiency programme's window is its route's session
                WHEN p_type IN (SELECT pp.window_type FROM admissions.prelim_programme pp)
                    THEN policy.route_session((SELECT pp.route FROM admissions.prelim_programme pp WHERE pp.window_type = p_type))
                WHEN p_type LIKE 'JUPEB%'
                    THEN coalesce((SELECT current_session FROM jupeb.setting WHERE session = '*'), policy.university_current_session())
                ELSE policy.intake_session() END
$function$;

-- policy.application_windows_public: the public reads the two new windows
CREATE OR REPLACE FUNCTION policy.application_windows_public()
 RETURNS TABLE(window_type text, session text, state text, opens_at timestamp with time zone, closes_at timestamp with time zone, message text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT t.window_type, s.session, w.state, w.opens_at, w.closes_at, m.message
      FROM (VALUES ('POST_UTME_REGISTRATION'), ('POSTGRADUATE_APPLICATION'), ('JUPEB_APPLICATION'), ('PRELIMINARY_SCIENCE_APPLICATION'), ('PRELIMINARY_TECHNOLOGY_APPLICATION'), ('PROFICIENCY_CERTIFICATE_APPLICATION')) t(window_type)
      CROSS JOIN LATERAL (SELECT policy.application_session(t.window_type) AS session) s
      CROSS JOIN LATERAL policy.window_state(t.window_type, s.session, NULL) w
      LEFT JOIN policy.portal_window_message m ON m.window_type = t.window_type
$function$;

-- policy.application_window_guard: a new applicant account held at its own route's window
CREATE OR REPLACE FUNCTION policy.application_window_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_type text := TG_ARGV[0]; v_state text; v_mode text;
BEGIN
    -- only the applicant registering themselves is held at the door; an office importing or correcting records is not
    IF coalesce(current_setting('moaum.actor_office', true), '') <> 'applicant' THEN RETURN NEW; END IF;
    IF TG_TABLE_SCHEMA = 'admissions' AND TG_TABLE_NAME = 'applicant_account' THEN
        SELECT c.entry_mode INTO v_mode FROM admissions.candidate c WHERE c.id = NEW.candidate_id;
        -- V701: a preliminary or proficiency applicant is held at their own route's window (prelim_register names the route)
        v_type := CASE WHEN v_mode = 'CCE' THEN 'CCE_APPLICATION'
                       WHEN v_mode IN ('PRELIMINARY', 'PROFICIENCY')
                           THEN coalesce((SELECT pp.window_type FROM admissions.prelim_programme pp WHERE pp.route = nullif(current_setting('moaum.prelim_route', true), '')),
                                         CASE v_mode WHEN 'PROFICIENCY' THEN 'PROFICIENCY_CERTIFICATE_APPLICATION' ELSE 'PRELIMINARY_SCIENCE_APPLICATION' END)
                       ELSE v_type END;
    END IF;
    SELECT state INTO v_state FROM policy.window_state(v_type, NEW.session, NULL);
    IF v_state <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: % for % is % — no new application can be started until the Director of ICT opens it',
            CASE v_type WHEN 'POST_UTME_REGISTRATION' THEN 'Post-UTME registration' WHEN 'JUPEB_APPLICATION' THEN 'JUPEB application'
                        WHEN 'CCE_APPLICATION' THEN 'CCE application' WHEN 'PRELIMINARY_SCIENCE_APPLICATION' THEN 'Preliminary Science application'
                        WHEN 'PRELIMINARY_TECHNOLOGY_APPLICATION' THEN 'Preliminary Technology & Industrial Studies application'
                        WHEN 'PROFICIENCY_CERTIFICATE_APPLICATION' THEN 'Proficiency certificate application'
                        ELSE 'postgraduate application' END,
            NEW.session, lower(v_state)
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $function$;

-- platform.applicant_window_type: the closing reminders of the two new windows
CREATE OR REPLACE FUNCTION platform.applicant_window_type(p_type text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT',
                      'JUPEB_APPLICATION', 'POSTGRADUATE_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION')
$function$;

-- platform.applicant_window_audience: each route's reminder reaches its own applicants
CREATE OR REPLACE FUNCTION platform.applicant_window_audience(p_type text, p_session text, p_after uuid, p_limit integer)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
AS $function$
    SELECT x.id FROM (
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT')
           AND a.session = p_session AND coalesce(c.entry_mode, '') NOT IN ('CCE', 'PRELIMINARY', 'PROFICIENCY')
        UNION ALL
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type = 'CCE_APPLICATION' AND a.session = p_session AND c.entry_mode = 'CCE'
        UNION ALL
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         -- V701: a preliminary or proficiency window's audience is its own route's applicants
         WHERE p_type IN (SELECT pp.window_type FROM admissions.prelim_programme pp) AND a.session = p_session
           AND EXISTS (SELECT 1 FROM admissions.prelim_review pr JOIN admissions.prelim_programme pp ON pp.route = pr.route
                        WHERE pr.application_id = a.id AND pp.window_type = p_type)
        UNION ALL
        SELECT j.id FROM jupeb.application j
         WHERE p_type = 'JUPEB_APPLICATION' AND j.session = p_session AND j.withdrawn_at IS NULL
        UNION ALL
        SELECT g.id FROM admissions.pg_application g
         WHERE p_type = 'POSTGRADUATE_APPLICATION' AND g.session = p_session) x
     WHERE p_after IS NULL OR x.id > p_after
     ORDER BY x.id
     LIMIT greatest(1, p_limit)
$function$;

-- policy.applicant_window_done: a submitted preliminary or proficiency application is reminded no more
CREATE OR REPLACE FUNCTION policy.applicant_window_done(p_type text, p_session text, p_application uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE
        WHEN p_type IN ('POST_UTME_REGISTRATION', 'CCE_APPLICATION') THEN
            coalesce((SELECT a.submitted_at IS NOT NULL FROM admissions.application a WHERE a.id = p_application), true)
        WHEN p_type IN ('PRELIMINARY_SCIENCE_APPLICATION', 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'PROFICIENCY_CERTIFICATE_APPLICATION') THEN
            coalesce((SELECT r.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') FROM admissions.prelim_review r WHERE r.application_id = p_application), true)
        WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM admissions.status_check c WHERE c.application_id = p_application)
        WHEN p_type = 'POST_UTME_CBT' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.application_id = p_application)
        WHEN p_type = 'JUPEB_APPLICATION' THEN
            coalesce((SELECT j.state NOT IN ('DRAFT', 'RETURNED') OR j.withdrawn_at IS NOT NULL FROM jupeb.application j WHERE j.id = p_application), true)
        WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN
            coalesce((SELECT g.state <> 'DRAFT' FROM admissions.pg_application g WHERE g.id = p_application), true)
        ELSE true END
$function$;

-- admissions.applicant_route: a proficiency applicant's fees are read under its route
CREATE OR REPLACE FUNCTION admissions.applicant_route(p_app uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE c.entry_mode WHEN 'CCE' THEN 'CCE'
                             WHEN 'PRELIMINARY' THEN (SELECT r.route FROM admissions.prelim_review r WHERE r.application_id = a.id)
                             WHEN 'PROFICIENCY' THEN (SELECT r.route FROM admissions.prelim_review r WHERE r.application_id = a.id)
                             END
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE a.id = p_app
$function$;

-- admissions.screening_required: a proficiency applicant is kept apart from Post-UTME like a preliminary one
CREATE OR REPLACE FUNCTION admissions.screening_required(p_app uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce((SELECT sp.enabled AND (a.accepted_at IS NULL OR a.accepted_at >= sp.enabled_from)
                       FROM admissions.application a JOIN admissions.screening_policy sp ON sp.session = a.session
                       JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode NOT IN ('CCE', 'PRELIMINARY', 'PROFICIENCY') WHERE a.id = p_app), false);
$function$;

-- admissions.post_utme_paid_applicants: a proficiency applicant is kept apart from Post-UTME like a preliminary one
CREATE OR REPLACE FUNCTION admissions.post_utme_paid_applicants(p_session text)
 RETURNS TABLE(application_id uuid, application_no text, session text, jamb_reg_no text, surname text, other_names text, full_name text, programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text, sex text, entry_mode text, utme_aggregate integer, phone text, email text, payment_status text, paid_at timestamp with time zone, payment_reference text, receipt_no text, channel text, amount numeric, verified_payments integer, missing text[])
 LANGUAGE sql
 STABLE
AS $function$
    SELECT a.id, a.application_no, a.session, nullif(btrim(c.jamb_reg_no), ''), c.surname, c.other_names,
           upper(btrim(c.surname)) || coalesce(', ' || nullif(btrim(c.other_names), ''), ''),
           c.programme, p.code, f.code, f.name, d.code, d.name,
           coalesce(c.sex, x.sex), c.entry_mode, coalesce(x.aggregate, c.utme_aggregate),
           ct.phone, ct.email,
           CASE WHEN pay.first_id IS NOT NULL THEN 'VERIFIED'
                WHEN EXISTS (SELECT 1 FROM admissions.fee_reversal v WHERE v.application_id = a.id AND v.kind = 'APPLICATION') THEN 'REVERSED'
                WHEN EXISTS (SELECT 1 FROM admissions.fee_reference r WHERE r.application_id = a.id AND r.kind = 'APPLICATION') THEN 'PENDING'
                ELSE 'NOT_STARTED' END,
           pay.paid_at, pay.reference, pay.receipt_no, pay.channel, pay.amount, coalesce(pay.n, 0),
           array_remove(ARRAY[
               CASE WHEN nullif(btrim(c.jamb_reg_no), '') IS NULL THEN 'JAMB_NUMBER' END,
               CASE WHEN p.code IS NULL THEN 'PROGRAMME_NOT_MATCHED' END,
               CASE WHEN coalesce(c.sex, x.sex) IS NULL THEN 'GENDER' END,
               CASE WHEN ct.phone IS NULL THEN 'PHONE' END,
               CASE WHEN ct.email IS NULL THEN 'EMAIL' END,
               CASE WHEN c.entry_mode = 'UTME' AND coalesce(x.aggregate, c.utme_aggregate) IS NULL THEN 'UTME_AGGREGATE' END], NULL)
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      JOIN admissions.applicant_account acc ON acc.id = a.account_id
      -- the programme the candidate applied for, matched by name as admissions.programme_code_of matches it (one map, joined once)
      LEFT JOIN (SELECT DISTINCT ON (g.name) g.name, g.code FROM ref.programme g ORDER BY g.name, g.archived, g.code) pm ON pm.name = c.programme
      LEFT JOIN ref.programme p ON p.code = pm.code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
      -- the old portal's applicants came over with placeholder contacts where it had none (V168): they are not contacts
      CROSS JOIN LATERAL (SELECT CASE WHEN btrim(coalesce(acc.phone, '')) IN ('', '00000000000') THEN NULL ELSE btrim(acc.phone) END AS phone,
                                 CASE WHEN btrim(coalesce(acc.email, '')) = '' OR acc.email ILIKE '%@migrate.moau.local' THEN NULL ELSE btrim(acc.email) END AS email) ct
      LEFT JOIN LATERAL (
          SELECT (array_agg(r.id ORDER BY r.confirmed_at, r.id))[1] AS first_id, min(r.confirmed_at) AS paid_at,
                 (array_agg(r.reference ORDER BY r.confirmed_at, r.id))[1] AS reference,
                 (array_agg(r.receipt_no ORDER BY r.confirmed_at, r.id))[1] AS receipt_no,
                 (array_agg(r.channel ORDER BY r.confirmed_at, r.id))[1] AS channel,
                 (array_agg(r.amount ORDER BY r.confirmed_at, r.id))[1] AS amount,
                 count(*)::int AS n
            FROM admissions.fee_reference r
           WHERE r.application_id = a.id AND r.kind = 'APPLICATION' AND r.confirmed_at IS NOT NULL
          HAVING count(*) > 0) pay ON true
     WHERE a.session = p_session
       AND c.entry_mode NOT IN ('CCE', 'PRELIMINARY', 'PROFICIENCY');
$function$;

-- admissions.status_checking_rows: a proficiency applicant is not on the Post-UTME status checking list
CREATE OR REPLACE FUNCTION admissions.status_checking_rows(p_session text, p_cce boolean)
 RETURNS TABLE(application_id uuid, application_no text, jamb_reg_no text, name text, sex text, programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text, valid boolean, paid boolean, paid_at timestamp with time zone, reference text, amount numeric, checked boolean, checks bigint, first_checked_at timestamp with time zone, last_checked_at timestamp with time zone, last_result text, result text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V537: each programme name's code read once (as admissions.programme_code_of reads it), not by that function for every applicant
    WITH named AS MATERIALIZED (SELECT DISTINCT ON (pp.name) pp.name, pp.code FROM ref.programme pp ORDER BY pp.name, pp.archived, pp.code)
    SELECT a.id, a.application_no, c.jamb_reg_no, c.surname || ', ' || c.other_names, r.sex, c.programme, p.code,
           p.faculty_code, fa.name, p.dept_code, d.name,
           (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL),
           (a.checking_confirmed_at IS NOT NULL OR ck.confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL),
           coalesce(a.checking_confirmed_at, ck.confirmed_at), ck.reference, ck.amount,
           (k.n > 0 OR a.status_checked_at IS NOT NULL), k.n, coalesce(k.first_at, a.status_checked_at), coalesce(k.last_at, a.status_checked_at), k.last_result,
           CASE WHEN a.decision_released_at IS NULL OR a.decision IS NULL THEN 'PENDING'
                WHEN a.decision = 'OFFERED' THEN 'ADMITTED' WHEN a.decision = 'WAITING' THEN 'WAITING_LIST' ELSE 'NOT_ADMITTED' END
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN named nm ON nm.name = c.programme
      LEFT JOIN ref.programme p ON p.code = nm.code
      LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN LATERAL (SELECT x.reference, x.amount, x.confirmed_at FROM admissions.fee_reference x
                          WHERE x.application_id = a.id AND x.kind = 'CHECKING' AND x.confirmed_at IS NOT NULL ORDER BY x.confirmed_at LIMIT 1) ck ON true
      LEFT JOIN LATERAL (SELECT count(*) AS n, min(s.checked_at) AS first_at, max(s.checked_at) AS last_at,
                                (array_agg(s.result ORDER BY s.checked_at DESC))[1] AS last_result
                           FROM admissions.status_check s WHERE s.application_id = a.id) k ON true
     WHERE a.session = p_session
       -- V412: the CCE applicants apart from the rest (their checking is not the ICT window's); V446: Preliminary Science has none
       AND (coalesce(c.entry_mode, '') = 'CCE') = coalesce(p_cce, false)
       AND coalesce(c.entry_mode, '') NOT IN ('PRELIMINARY', 'PROFICIENCY')
$function$;

-- admissions.status_checking: a proficiency applicant reads the published outcome like a preliminary one
CREATE OR REPLACE FUNCTION admissions.status_checking(p_app uuid)
 RETURNS TABLE(application_id uuid, session text, application_valid boolean, window_state text, window_open boolean, opens_at timestamp with time zone, closes_at timestamp with time zone, fee numeric, fee_required boolean, paid boolean, paid_at timestamp with time zone, paid_reference text, open_reference text, open_reference_expires timestamp with time zone, past boolean, may_pay boolean, may_check boolean, decision_visible boolean, reason text, checks bigint, last_checked_at timestamp with time zone, last_result text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (SELECT * FROM admissions.application WHERE id = p_app),
    -- V404: a CCE applicant has no checking window of the Director of ICT's: checking opens to them when the Centre's outcome of
    -- their application is published (admissions.cce_publish releases it and tells them), and costs the CCE admission checking
    -- fee the Bursary stated for the route (NULL while it is not stated: owed, and not yet payable)
    cce AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE c.entry_mode = 'CCE') AS yes),
    -- V446: a Preliminary Science applicant likewise reads the published outcome, with no window of ICT's and no fee the University has not stated
    pre AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE c.entry_mode IN ('PRELIMINARY', 'PROFICIENCY')) AS yes,
                   (SELECT r.route FROM admissions.prelim_review r WHERE r.application_id = p_app) AS route,
                   (SELECT r.submitted_at FROM admissions.prelim_review r WHERE r.application_id = p_app) AS submitted_at),
    w AS (SELECT CASE WHEN cce.yes OR pre.yes THEN CASE WHEN a.decision_released_at IS NOT NULL THEN 'OPEN' ELSE 'CLOSED' END ELSE ws.state END AS state,
                 CASE WHEN cce.yes OR pre.yes THEN NULL ELSE ws.opens_at END AS opens_at,
                 CASE WHEN cce.yes OR pre.yes THEN NULL ELSE ws.closes_at END AS closes_at
            FROM a CROSS JOIN cce CROSS JOIN pre CROSS JOIN LATERAL policy.window_state('ADMISSION_STATUS_CHECKING', a.session, NULL) ws),
    f AS (SELECT CASE WHEN (SELECT yes FROM cce) THEN (SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, 'CCE') r)
                      WHEN (SELECT yes FROM pre) THEN (SELECT r.checking_fee FROM a CROSS JOIN pre CROSS JOIN LATERAL admissions.route_fee_rule(a.session, pre.route) r)
                      ELSE coalesce((SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.applicant_fee_rule(a.session) r), 0) END::numeric AS fee),
    pay AS (SELECT min(r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING') AS ck_at,
                   (array_agg(r.reference ORDER BY r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING'))[1] AS ck_ref,
                   coalesce(bool_or(r.kind = 'ACCEPTANCE'), false) AS acc
              FROM admissions.fee_reference r WHERE r.application_id = p_app AND r.confirmed_at IS NOT NULL),
    o AS (SELECT r.reference, r.expires_at FROM admissions.fee_reference r
           WHERE r.application_id = p_app AND r.kind = 'CHECKING' AND r.confirmed_at IS NULL AND r.expires_at > now()
           ORDER BY r.generated_at DESC LIMIT 1),
    k AS (SELECT count(*) AS n, max(c.checked_at) AS last_at, (array_agg(c.result ORDER BY c.checked_at DESC))[1] AS last_result
            FROM admissions.status_check c WHERE c.application_id = p_app),
    x AS (
        SELECT a.id, a.session,
               (a.fee_confirmed_at IS NOT NULL AND coalesce(a.submitted_at, (SELECT pre.submitted_at FROM pre)) IS NOT NULL) AS valid,
               w.state AS wstate, w.state = 'OPEN' AS wopen, w.opens_at, w.closes_at,
               f.fee, coalesce(f.fee > 0, (SELECT yes FROM cce)) AS required,
               -- an acceptance confirmed under the old rule (V148) included the checking fee: it counts as paid
               (a.checking_confirmed_at IS NOT NULL OR pay.ck_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL OR pay.acc) AS paid,
               coalesce(a.checking_confirmed_at, pay.ck_at) AS paid_at, pay.ck_ref,
               -- the offer has been read and the admission is under way: the workflow continues whatever the window
               (a.decision_released_at IS NOT NULL AND a.decision = 'OFFERED'
                AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL
                     OR a.accepted_at IS NOT NULL OR a.declined_at IS NOT NULL OR pay.acc)) AS past
          FROM a, w, f, pay)
    SELECT x.id, x.session, x.valid, x.wstate, x.wopen, x.opens_at, x.closes_at, x.fee, x.required,
           x.paid, x.paid_at, x.ck_ref, (SELECT o.reference FROM o), (SELECT o.expires_at FROM o),
           x.past,
           x.valid AND x.wopen AND x.required AND NOT x.paid,
           x.valid AND x.wopen AND (x.paid OR NOT x.required),
           x.past OR (x.valid AND x.wopen AND (x.paid OR NOT x.required)),
           CASE WHEN x.past THEN NULL WHEN NOT x.valid THEN 'APPLICATION_INCOMPLETE' WHEN NOT x.wopen THEN 'CHECKING_CLOSED'
                WHEN x.required AND NOT x.paid THEN 'CHECKING_FEE_UNPAID' END,
           k.n, k.last_at, k.last_result
      FROM x, k
$function$;

-- admissions.confirm_fee: a preliminary or proficiency payment confirmed in its route's words
CREATE OR REPLACE FUNCTION admissions.confirm_fee(p_reference text, p_channel text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r admissions.fee_reference; a admissions.application; v_no text; v_purpose text; v_action text; v_sms_action text; v_prelim boolean;
BEGIN
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id;
    v_prelim := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode IN ('PRELIMINARY', 'PROFICIENCY'));

    v_no := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
    UPDATE admissions.fee_reference SET confirmed_at = now(), confirmed_by = admissions.acting_person(),
           channel = p_channel, note = p_note, receipt_no = v_no WHERE id = r.id;

    IF r.kind = 'APPLICATION' THEN
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE application'
                          WHEN v_prelim THEN coalesce((SELECT pp.name || ' application' FROM admissions.prelim_review pr JOIN admissions.prelim_programme pp ON pp.route = pr.route
                                                     WHERE pr.application_id = a.id), 'Preliminary application') ELSE 'Application & Post-UTME' END;
        v_action := 'Your application form is now open: sign in and complete it.';
        v_sms_action := 'Your application form is open.';
    ELSIF r.kind = 'CHECKING' THEN
        -- V295: the fee grants the checking service; the status is read, and recorded, when the applicant checks it
        UPDATE admissions.application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()) WHERE id = a.id;
        -- V412: a CCE applicant's checking fee is the CCE admission checking fee, paid to read the published outcome
        IF EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN
            v_purpose := 'CCE admission checking';
            v_action := 'Your CCE admission checking fee payment has been verified. Sign in and open Admission Status to read the outcome of your application.';
            v_sms_action := 'CCE admission checking fee verified. Sign in to read the outcome of your application.';
        ELSE
            v_purpose := 'Admission checking';
            v_action := 'Your Admission Checking Fee payment has been verified. You can now check your admission status: sign in and open Admission Status.';
            v_sms_action := 'Admission checking fee verified. You can now check your admission status.';
        END IF;
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE acceptance' ELSE 'Acceptance' END;
        v_action := 'Your acceptance of the offer is settled. Sign in to continue to clearance.';
        v_sms_action := 'Acceptance settled.';
        PERFORM admissions.settle_acceptance(a.id);
    END IF;

    IF v_prelim THEN
        -- V446: a preliminary payment is told through the central templates (email, SMS and the portal), with its receipt; V701: the route's own
        PERFORM platform.tell_applicant(a.id, coalesce(admissions.applicant_route(a.id), 'PRELIMINARY_SCIENCE'), 'PAYMENT_SUCCESSFUL',
            jsonb_build_object('RECEIPT_NUMBER', v_no, 'REFERENCE', r.reference, 'PURPOSE', v_purpose || ' fee',
                               'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,990.00'), 'PAID_ON', to_char(now() AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY'),
                               'CHANNEL', coalesce(p_channel, 'Bank')),
            coalesce(admissions.applicant_route(a.id), 'PRELIMINARY_SCIENCE') || '_PAYMENT_SUCCESSFUL:' || r.reference);
        RETURN 'confirmed';
    END IF;

    PERFORM admissions.notify_applicant(a.id, 'Your payment receipt · ' || v_no,
        'This is your official receipt from Rev. Fr. Moses Orshio Adasu University, Makurdi.' || chr(10) || chr(10)
        || 'Receipt no:  ' || v_no || chr(10)
        || 'Reference:   ' || r.reference || chr(10)
        || 'Purpose:     ' || v_purpose || ' fee' || chr(10)
        || 'Session:     ' || a.session || chr(10)
        || 'Amount:      NGN ' || to_char(r.amount, 'FM999,999,990.00') || chr(10)
        || 'Confirmed:   ' || to_char(now(), 'FMDD FMMonth YYYY') || chr(10)
        || 'Channel:     ' || coalesce(p_channel, 'Bank') || chr(10) || chr(10)
        || v_action || chr(10) || chr(10)
        || 'Keep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
        'MOAUM receipt ' || v_no || ': NGN ' || to_char(r.amount, 'FM999,999,990.00') || ' for ' || v_purpose || ' confirmed. ' || v_sms_action);

    RETURN 'confirmed';
END $function$;

-- admissions.new_fee_reference: a fee not stated is named with its own programme
CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean; v_try int; v_route text; v_prelim boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    v_route := admissions.applicant_route(p_app);
    v_prelim := v_route IS NOT NULL AND NOT v_cce;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    -- V446: a Preliminary Science applicant pays the application fee; the University has stated no checking or acceptance fee for it
    IF v_prelim AND p_kind <> 'APPLICATION' THEN
        SELECT r.checking_fee, r.acceptance_fee INTO fee FROM admissions.route_fee_rule(a.session, v_route) r;
        IF (p_kind = 'CHECKING' AND fee.checking_fee IS NULL) OR (p_kind = 'ACCEPTANCE' AND fee.acceptance_fee IS NULL) THEN
            RAISE EXCEPTION 'PRELIM_FEE_NOT_CONFIGURED: the University has not stated a % fee of % for %', lower(p_kind), coalesce((SELECT pp.name FROM admissions.prelim_programme pp WHERE pp.route = v_route), 'the programme'), a.session USING ERRCODE = '23514';
        END IF;
    END IF;
    IF p_kind = 'CHECKING' AND NOT v_prelim THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already paid; nothing more is owed' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking follows a CCE application paid for and submitted'
                ELSE 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' END USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            -- V404: for CCE, checking opens when the Centre publishes the outcome of the application
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_CLOSED: the Centre for Continuing Education has not yet published the outcome of your application'
                ELSE 'ADMISSION_CHECKING_CLOSED: admission status checking is closed' END USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' AND NOT v_prelim THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce OR v_prelim THEN
        -- V379: the route's fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures.
        -- V404: the CCE admission checking fee among them; V446: a preliminary programme's fees, read the same way
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, r.checking_fee INTO fee FROM admissions.route_fee_rule(a.session, v_route) r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge WHEN 'CHECKING' THEN fee.checking_fee ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN format('CCE_FEE_NOT_STATED: the Bursary has not stated the CCE %s fee for %s', lower(p_kind), a.session)
                                      ELSE format('PRELIM_FEE_NOT_CONFIGURED: the Bursary has not stated the %s fee of %s for %s', lower(p_kind), coalesce((SELECT pp.name FROM admissions.prelim_programme pp WHERE pp.route = v_route), 'the programme'), a.session) END
                USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- V401: where the Bursary refuses to carry a session's applicant fees forward, nothing is paid until they are stated
    IF NOT fee.stated AND admissions.applicant_fee_policy() = 'REFUSE' THEN
        RAISE EXCEPTION 'APPLICANT_FEE_NOT_STATED: the % fee for % is not stated yet', lower(p_kind), a.session USING ERRCODE = '23514',
            HINT = 'The Bursary states the applicant fees for the session on Fee Setup.';
    END IF;
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    -- a reference still open for the application fee is the one to pay (V446: never two at once for the same fee)
    IF v_prelim AND p_kind = 'APPLICATION' THEN
        SELECT r.reference INTO v_ref FROM admissions.fee_reference r
         WHERE r.application_id = p_app AND r.kind = 'APPLICATION' AND r.confirmed_at IS NULL AND r.expires_at > now() AND r.amount = v_amount
         ORDER BY r.generated_at DESC LIMIT 1;
        IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    END IF;
    -- V390: the four random digits may repeat a reference another application drew (the last six digits of an application
    -- number are the session's running number, shared across sessions); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
                 || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
        VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free % reference was found for % in fifty draws', lower(p_kind), a.application_no USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

-- admissions.set_route_fee: the Bursary states every preliminary route's fees
CREATE OR REPLACE FUNCTION admissions.set_route_fee(p_session text, p_route text, p_application numeric, p_portal numeric, p_acceptance numeric, p_checking numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_route text := upper(btrim(p_route)); v_prelim boolean;
BEGIN
    v_prelim := EXISTS (SELECT 1 FROM admissions.prelim_programme p WHERE p.route = v_route);
    PERFORM admissions.cce_require_office(ARRAY['bursar', 'super'], CASE WHEN v_prelim THEN 'stating a preliminary or proficiency programme''s applicant fees' ELSE 'stating the CCE applicant fees' END);
    IF v_prelim THEN
        IF p_application IS NULL OR p_application < 0 OR coalesce(p_acceptance, 0) < 0 OR coalesce(p_checking, 0) < 0 OR coalesce(p_portal, 0) < 0 THEN
            RAISE EXCEPTION 'PRELIM_FEE_AMOUNT: the application fee is stated; an acceptance or checking fee only when the University has given one, and none is negative' USING ERRCODE = '23514';
        END IF;
    ELSIF p_application IS NULL OR p_acceptance IS NULL OR p_checking IS NULL
       OR p_application < 0 OR p_acceptance < 0 OR p_checking < 0 OR coalesce(p_portal, 0) < 0 THEN
        RAISE EXCEPTION 'CCE_FEE_AMOUNT: the application, admission checking and acceptance fees are stated, and none is negative' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.route_fee (session, route, application_fee, portal_charge, acceptance_fee, checking_fee, stated_by, stated_office)
    VALUES (p_session, v_route, p_application, coalesce(p_portal, 0), p_acceptance, p_checking,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, current_setting('moaum.actor_office', true))
    ON CONFLICT (session, route) DO UPDATE SET application_fee = EXCLUDED.application_fee, portal_charge = EXCLUDED.portal_charge,
        acceptance_fee = EXCLUDED.acceptance_fee, checking_fee = EXCLUDED.checking_fee, stated_by = EXCLUDED.stated_by,
        stated_office = EXCLUDED.stated_office, stated_at = now();
END $function$;

-- admissions.issue_admission_letter: the letter of a preliminary or proficiency admission in its own programme's terms
CREATE OR REPLACE FUNCTION admissions.issue_admission_letter(p_app uuid)
 RETURNS credentials.issued
 LANGUAGE plpgsql
AS $function$
DECLARE pr admissions.prelim_review; pp admissions.prelim_programme; tg record; a admissions.application; c admissions.candidate; cur credentials.issued; v_stmt jsonb; v_hash text; v_number text; v_version int := 1; v_id uuid := gen_random_uuid();
        v_actor uuid; v_office text; ent record; v_prog record; v_changed record; v_student people.student;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN RAISE EXCEPTION 'there is no offer to issue a letter for' USING ERRCODE = '23514'; END IF;
    SELECT * INTO pr FROM admissions.prelim_review WHERE application_id = p_app;
    -- V446: a Preliminary Science offer has no acceptance fee the University has stated; its letter follows the published offer
    IF a.accepted_at IS NULL AND pr.application_id IS NULL THEN RAISE EXCEPTION 'the admission letter is issued once the offer is accepted and the acceptance fee confirmed' USING ERRCODE = '23514', HINT = 'Sign the undertaking and pay the acceptance fee, then print the letter.'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT p.code, p.name, p.category, f.name AS faculty, d.name AS department INTO v_prog
      FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = admissions.programme_code_of(c.programme);
    SELECT * INTO cur FROM credentials.issued i WHERE i.application_id = p_app AND i.kind = 'ADMISSION_LETTER' AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = i.id) ORDER BY i.version DESC LIMIT 1;
    -- the letter stands while it names the programme the admission is for
    IF cur.id IS NOT NULL AND cur.statement->>'programme' = c.programme THEN RETURN cur; END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    SELECT * INTO v_student FROM people.student WHERE candidate_id = c.id LIMIT 1;
    SELECT q.from_programme, q.to_programme, q.decided_at INTO v_changed FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1;
    v_actor := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    IF v_office IS NULL OR NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN v_office := 'registrar'; END IF;
    IF cur.id IS NOT NULL THEN v_version := cur.version + 1; v_number := cur.number; ELSE v_number := credentials.next_document_number('ADMISSION_LETTER'); END IF;
    v_stmt := jsonb_build_object(
        'kind', 'ADMISSION_LETTER', 'number', v_number, 'version', v_version,
        'holder', c.surname || ', ' || c.other_names, 'surname', c.surname, 'otherNames', c.other_names, 'jambRegNo', c.jamb_reg_no, 'applicationNo', a.application_no,
        'session', a.session, 'programme', c.programme, 'programmeCode', v_prog.code, 'degreeType', v_prog.category, 'faculty', v_prog.faculty, 'department', v_prog.department,
        'admissionType', c.entry_mode || ' · ' || c.entry_level || ' Level', 'entryMode', c.entry_mode, 'entryLevel', c.entry_level, 'basis', a.decision_basis,
        'decisionReleasedOn', a.decision_released_at::date, 'acceptedOn', a.accepted_at::date, 'acceptanceReference', ent.reference, 'acceptanceConfirmedOn', ent.confirmed_at::date,
        'admissionNo', v_student.admission_no,
        'changedFrom', v_changed.from_programme, 'changedTo', v_changed.to_programme, 'changedOn', v_changed.decided_at::date,
        'issuedOn', current_date, 'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi');
    -- V379: a CCE admission names the route, the study mode, the Centre and the programme's duration on the route
    IF c.entry_mode = 'CCE' THEN
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', 'CCE', 'studyMode', 'PART-TIME', 'centre', 'Centre for Continuing Education',
                    'admissionType', 'CCE · Part-time · ' || c.entry_level || ' Level',
                    'durationYears', (SELECT t.duration_years FROM ref.programme_route_terms(v_prog.code, 'CCE') t),
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for the Centre for Continuing Education');
    END IF;
    -- V446/V701: a preliminary or proficiency letter names the programme, its type and campus, and the target programme (an intended
    -- progression only) with the option chosen, or the certificate course
    IF pr.application_id IS NOT NULL THEN
        SELECT * INTO pp FROM admissions.prelim_programme WHERE route = pr.route;
        SELECT p.code, p.name, f.name AS faculty, d.name AS department, t.kind, t.requested_name, t.group_name, sp.name AS specialisation,
               coalesce(t.duration_months, pp.duration_months) AS months
          INTO tg
          FROM admissions.prelim_target t
          LEFT JOIN ref.programme p ON p.code = t.programme_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN admissions.prelim_specialisation sp ON sp.id = pr.specialisation_id
         WHERE t.id = pr.target_id;
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', pr.route, 'programme', pp.name, 'programmeCode', NULL,
                    'degreeType', CASE pp.programme_type WHEN 'PROFICIENCY_CERTIFICATE' THEN 'PROFICIENCY CERTIFICATE' ELSE 'PRELIMINARY / REMEDIAL' END,
                    'faculty', NULL, 'department', NULL, 'studyMode', 'FULL-TIME', 'admissionType', pp.name || ' · Full-time', 'entryLevel', NULL,
                    'campus', (SELECT cm.name FROM ref.campus cm WHERE cm.code = pp.campus_code),
                    'durationMonths', tg.months, 'area', tg.group_name,
                    'targetProgramme', CASE WHEN tg.kind = 'PROGRAMME' THEN tg.name END, 'targetProgrammeCode', CASE WHEN tg.kind = 'PROGRAMME' THEN tg.code END,
                    'targetFaculty', tg.faculty, 'targetDepartment', tg.department, 'specialisation', tg.specialisation,
                    'certificateCourse', CASE WHEN tg.kind = 'COURSE' THEN tg.requested_name END,
                    'targetNote', pp.target_note,
                    'remediationRequired', pr.remediation_status = 'REQUIRED',
                    'remediationSubjects', to_jsonb(pr.remediation_subjects), 'remediationCreditsShort', pr.remediation_credits_short,
                    'completionNote', pp.completion_note,
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for ' || pp.name);
    END IF;
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, application_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes, number, version, template_version, content_hash, note)
    VALUES (v_id, 'ADMISSION_LETTER', v_student.id, p_app, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, cur.id,
            v_number, v_version, NULL, v_hash, CASE WHEN cur.id IS NULL THEN 'Letter of provisional admission' ELSE 'Reissued: the programme changed to ' || c.programme END);
    PERFORM credentials.log(NULL, v_id, v_student.id, 'ISSUED', NULL, 'ACTIVE', 'ADMISSION_LETTER ' || v_number || ' v' || v_version || ' · ' || c.programme);
    SELECT * INTO cur FROM credentials.issued WHERE id = v_id;
    RETURN cur;
END $function$;

-- ── 8 · the preliminary functions, every route's (V446's, restated where a route differs) ───────────────────────────────
/* the office that reviews and recommends a route's applications (Preliminary Science's, or the Vocational and Technical one) */
CREATE OR REPLACE FUNCTION admissions.prelim_office(p_route text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT office_code FROM admissions.prelim_programme WHERE route = upper(btrim(p_route))
$fn$;

/* "the Preliminary Science Office", "the Preliminary Vocational and Technical Education Office" — the words a message names it by */
CREATE OR REPLACE FUNCTION admissions.prelim_office_words(p_route text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce('the ' || o.label, 'the programme''s office') FROM admissions.prelim_programme p LEFT JOIN ref.office o ON o.code = p.office_code
     WHERE p.route = upper(btrim(p_route))
$fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_application(p_app uuid)
RETURNS admissions.prelim_review LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    IF r.application_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a preliminary or proficiency programme application' USING ERRCODE = '23514'; END IF;
    RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_require_editable(p_app uuid)
RETURNS admissions.prelim_review LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN
        RAISE EXCEPTION 'PRELIM_NOT_EDITABLE: the application is % and is with %; it is changed only when the Office asks',
            lower(replace(r.state, '_', ' ')), admissions.prelim_office_words(r.route) USING ERRCODE = '23514';
    END IF;
    IF NOT admissions.prelim_fee_settled(p_app) THEN
        RAISE EXCEPTION 'PRELIM_FEE_FIRST: pay the application fee first; the application form opens once the payment is verified' USING ERRCODE = '23514';
    END IF;
    RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_event_once() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    -- the application itself removed (the go-live data reset): its history goes with it, as CCE's does
    IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM admissions.application a WHERE a.id = OLD.application_id) THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'a preliminary or proficiency application''s history is written once and never changed' USING ERRCODE = '23514';
END $fn$;

/* the eligibility, worked out on the O'Level the applicant gave, under the route's rule (V446, V701).
   OLEVEL_CREDITS: a credit is a grade no worse than the credit grade; a subject sat twice counts once, at its better grade;
   subjects are matched as the eligibility engine matches them (admissions.subject_same). The rule: the credits in all, the
   subjects that must be credited (English Language for Preliminary Technology), and some of a list (the programme's, or — where
   the programme says so — the chosen area's own: until an area is chosen the eligibility waits). An eligible candidate short of
   the completion rule (five credits with the named subjects, counted over every credit or over the relevant ones) is
   ELIGIBLE_WITH_REMEDIATION, with what is to be made up.
   ATTEMPTED_CERTIFICATE (the proficiency courses): a secondary school certificate attempted — a sitting with its results — is
   all the rule asks; no credits are counted and nothing is to be made up.
   An awaiting result is never accepted (prelim_save_olevel); an officer's finding that the result is invalid stands over all. */
CREATE OR REPLACE FUNCTION admissions.prelim_evaluate(p_app uuid)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; p admissions.prelim_programme; t admissions.prelim_target; v_policy uuid; v_credit int; v_sittings int;
        v_total int := NULL; v_core text[] := NULL; v_missing text[] := '{}'; v_short int := 0; v_status text; v_checks jsonb := '[]'::jsonb;
        v_reasons text[] := '{}'; v_rem text; v_ok_credits boolean; v_ok_sittings boolean; v_ok_core boolean; v_ok_required boolean;
        v_list text[]; v_min_core int; v_req_held text[] := '{}'; v_req_missing text[] := '{}'; v_relevant int; v_subjects int; v_list_words text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.application_id IS NULL THEN RETURN NULL; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = r.target_id;
    v_policy := admissions.prelim_policy(a.session);
    v_credit := admissions.grade_rank(p.credit_grade);
    SELECT count(DISTINCT o.sitting), count(*) INTO v_sittings, v_subjects FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active;
    IF v_sittings = 0 THEN
        v_status := 'RESULT_REQUIRED';
        v_reasons := ARRAY[CASE WHEN p.rule_kind = 'ATTEMPTED_CERTIFICATE'
                                THEN 'No secondary school certificate result has been given. Give the results of the examination you sat.'
                                ELSE 'No released O''Level result has been given. Admission is on results already released; an awaiting result is not accepted.' END];
        v_checks := jsonb_build_array(jsonb_build_object('key', 'RESULT_RELEASED', 'label',
                        CASE WHEN p.rule_kind = 'ATTEMPTED_CERTIFICATE' THEN 'Secondary school certificate attempted (its results given)' ELSE 'O''Level results released (no awaiting result)' END, 'ok', false));
    ELSIF p.rule_kind = 'ATTEMPTED_CERTIFICATE' THEN
        v_ok_sittings := v_sittings <= p.max_sittings;
        v_checks := jsonb_build_array(
            jsonb_build_object('key', 'ATTEMPTED', 'label', 'Secondary school certificate attempted (its results given)', 'required', 1, 'held', v_sittings, 'ok', true),
            jsonb_build_object('key', 'MAX_SITTINGS', 'label', 'Sittings', 'required', p.max_sittings, 'held', v_sittings, 'ok', v_ok_sittings, 'atMost', true));
        IF v_ok_sittings THEN v_status := 'ELIGIBLE';
        ELSE
            v_status := 'NOT_ELIGIBLE';
            v_reasons := ARRAY[format('%s sittings given; at most %s %s allowed.', v_sittings, p.max_sittings, CASE WHEN p.max_sittings = 1 THEN 'is' ELSE 'are' END)];
        END IF;
    ELSE
        -- the list some of which must be credited: the programme's, or the chosen area's own
        IF p.core_by_target THEN
            v_list := t.core_subjects;
            v_min_core := coalesce(t.min_core_credits, p.min_core_credits);
        ELSE
            v_list := p.core_subjects;
            v_min_core := p.min_core_credits;
        END IF;
        WITH best AS (SELECT min(btrim(o.subject)) AS subject, min(admissions.grade_rank(o.grade)) AS rank
                        FROM admissions.screening_olevel o WHERE o.application_id = p_app AND o.active
                       GROUP BY lower(btrim(o.subject)))
        SELECT count(*) FILTER (WHERE best.rank <= v_credit),
               (SELECT array_agg(cs ORDER BY ord) FROM unnest(v_list) WITH ORDINALITY u(cs, ord)
                 WHERE EXISTS (SELECT 1 FROM best b WHERE b.rank <= v_credit AND admissions.subject_same(b.subject, cs, v_policy, 'OLEVEL'))),
               (SELECT coalesce(array_agg(rs ORDER BY ord), '{}') FROM unnest(p.required_subjects) WITH ORDINALITY u(rs, ord)
                 WHERE EXISTS (SELECT 1 FROM best b WHERE b.rank <= v_credit AND admissions.subject_same(b.subject, rs, v_policy, 'OLEVEL'))),
               (SELECT coalesce(array_agg(rs ORDER BY ord), '{}') FROM unnest(p.required_subjects) WITH ORDINALITY u(rs, ord)
                 WHERE NOT EXISTS (SELECT 1 FROM best b WHERE b.rank <= v_credit AND admissions.subject_same(b.subject, rs, v_policy, 'OLEVEL'))),
               (SELECT coalesce(array_agg(cs ORDER BY ord), '{}') FROM unnest(p.completion_subjects) WITH ORDINALITY u(cs, ord)
                 WHERE NOT EXISTS (SELECT 1 FROM best b WHERE b.rank <= v_credit AND admissions.subject_same(b.subject, cs, v_policy, 'OLEVEL'))),
               -- the relevant credits: those of a required subject or of the list
               count(*) FILTER (WHERE best.rank <= v_credit
                                  AND (EXISTS (SELECT 1 FROM unnest(p.required_subjects) rs WHERE admissions.subject_same(best.subject, rs, v_policy, 'OLEVEL'))
                                       OR EXISTS (SELECT 1 FROM unnest(coalesce(v_list, '{}')) cs WHERE admissions.subject_same(best.subject, cs, v_policy, 'OLEVEL'))))
          INTO v_total, v_core, v_req_held, v_req_missing, v_missing, v_relevant
          FROM best;
        v_core := coalesce(v_core, '{}');
        v_ok_credits := v_total >= p.min_credits;
        v_ok_sittings := v_sittings <= p.max_sittings;
        v_ok_required := cardinality(v_req_missing) = 0;
        v_ok_core := v_list IS NOT NULL AND cardinality(v_core) >= v_min_core;
        v_list_words := CASE WHEN v_list IS NULL THEN 'the subjects of the ' || p.group_word || ' you choose' ELSE array_to_string(v_list, ', ') END;
        v_checks := jsonb_build_array(
            jsonb_build_object('key', 'MIN_CREDITS', 'label', 'Credit passes (' || p.credit_grade || ' or better)', 'required', p.min_credits, 'held', v_total, 'ok', v_ok_credits),
            jsonb_build_object('key', 'MAX_SITTINGS', 'label', 'Sittings', 'required', p.max_sittings, 'held', v_sittings, 'ok', v_ok_sittings, 'atMost', true))
            || CASE WHEN cardinality(p.required_subjects) > 0
                    THEN jsonb_build_array(jsonb_build_object('key', 'REQUIRED_SUBJECTS', 'label', 'Credit in ' || array_to_string(p.required_subjects, ', '),
                                                              'required', cardinality(p.required_subjects), 'held', cardinality(v_req_held), 'ok', v_ok_required,
                                                              'subjects', to_jsonb(v_req_held), 'missing', to_jsonb(v_req_missing)))
                    ELSE '[]'::jsonb END
            || jsonb_build_array(
                jsonb_build_object('key', 'MIN_CORE_CREDITS', 'label', 'Credits in ' || v_list_words, 'required', v_min_core,
                                   'held', CASE WHEN v_list IS NULL THEN NULL ELSE cardinality(v_core) END, 'ok', v_ok_core, 'subjects', to_jsonb(v_core)),
                jsonb_build_object('key', 'RESULT_RELEASED', 'label', 'O''Level results released (no awaiting result)', 'ok', true));
        IF NOT v_ok_credits THEN
            v_reasons := v_reasons || format('%s credit pass%s held; at least %s are required.', v_total, CASE WHEN v_total = 1 THEN '' ELSE 'es' END, p.min_credits);
        END IF;
        IF NOT v_ok_sittings THEN
            v_reasons := v_reasons || format('%s sittings given; at most %s %s allowed.', v_sittings, p.max_sittings, CASE WHEN p.max_sittings = 1 THEN 'is' ELSE 'are' END);
        END IF;
        IF NOT v_ok_required THEN
            v_reasons := v_reasons || format('A credit in %s is required.', array_to_string(v_req_missing, ', '));
        END IF;
        IF v_list IS NULL THEN
            v_reasons := v_reasons || format('Choose your %s: the subjects counted are the %s''s own.', p.group_word, p.group_word);
        ELSIF NOT v_ok_core THEN
            v_reasons := v_reasons || format('%s credit%s among %s; at least %s are required.', cardinality(v_core), CASE WHEN cardinality(v_core) = 1 THEN '' ELSE 's' END,
                                             v_list_words, v_min_core);
        END IF;
        IF v_list IS NULL AND v_ok_credits AND v_ok_sittings AND v_ok_required THEN
            v_status := 'PENDING_REVIEW';
            v_missing := '{}';
        ELSIF v_ok_credits AND v_ok_sittings AND v_ok_core AND v_ok_required THEN
            -- the completion rule: the named subjects credited, and the total reached — over every credit, or the relevant ones
            v_short := greatest(0, p.completion_credits - CASE WHEN p.completion_scope = 'RELEVANT' THEN v_relevant ELSE v_total END - cardinality(v_missing));
            v_status := CASE WHEN cardinality(v_missing) > 0 OR v_short > 0 THEN 'ELIGIBLE_WITH_REMEDIATION' ELSE 'ELIGIBLE' END;
        ELSE
            v_status := 'NOT_ELIGIBLE';
            v_missing := '{}';
        END IF;
    END IF;
    IF r.olevel_verification = 'INVALID' THEN
        v_status := 'INVALID_RESULT';
        v_reasons := ARRAY['The O''Level result was found invalid on verification' || coalesce(': ' || r.olevel_note, '.')] || v_reasons;
    END IF;
    -- the remediation the completion rule asks for; an officer's own setting (in progress, completed, not completed, review) stands
    v_rem := r.remediation_status;
    IF v_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION') THEN
        IF r.remediation_status IS NULL OR r.remediation_status IN ('NOT_REQUIRED', 'REQUIRED') THEN
            v_rem := CASE WHEN v_status = 'ELIGIBLE_WITH_REMEDIATION' THEN 'REQUIRED' ELSE 'NOT_REQUIRED' END;
        END IF;
    ELSIF r.remediation_status IN ('NOT_REQUIRED', 'REQUIRED') THEN
        v_rem := NULL;
    END IF;
    UPDATE admissions.prelim_review
       SET eligibility_status = v_status, total_credits = v_total, core_credits = CASE WHEN v_core IS NULL THEN NULL ELSE cardinality(v_core) END,
           sittings = v_sittings, credited_core = v_core, eligibility_checks = v_checks, eligibility_reasons = v_reasons, evaluated_at = now(),
           rules_version = p.rules_version, remediation_status = v_rem,
           remediation_subjects = CASE WHEN v_status = 'ELIGIBLE_WITH_REMEDIATION' THEN v_missing ELSE '{}' END,
           remediation_credits_short = CASE WHEN v_status = 'ELIGIBLE_WITH_REMEDIATION' THEN v_short ELSE 0 END,
           updated_at = now()
     WHERE application_id = p_app;
    RETURN v_status;
END $fn$;

/* what still stands between the applicant and submitting, step by step, in the route's own words */
CREATE OR REPLACE FUNCTION admissions.prelim_problems(p_app uuid)
RETURNS TABLE (step text, field text, message text)
LANGUAGE sql STABLE AS $fn$
    WITH a AS (SELECT ap.*, c.sex FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         r AS (SELECT x.* FROM admissions.prelim_review x WHERE x.application_id = p_app),
         p AS (SELECT pp.* FROM admissions.prelim_programme pp JOIN r ON r.route = pp.route),
         t AS (SELECT tt.* FROM admissions.prelim_target tt JOIN r ON tt.id = r.target_id),
         fee AS (SELECT f.* FROM a CROSS JOIN r CROSS JOIN LATERAL admissions.route_fee_rule(a.session, r.route) f),
         ans AS (SELECT x.field, x.value FROM admissions.screening_answer x WHERE x.application_id = p_app),
         ol AS (SELECT x.* FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         sittings AS (SELECT count(DISTINCT sitting) AS n FROM ol),
         docs AS (SELECT d.* FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL),
         req AS (SELECT d.* FROM admissions.prelim_document d JOIN r ON r.route = d.route WHERE d.required AND (NOT d.second_sitting_only OR (SELECT n FROM sittings) >= 2))
    SELECT 'PAYMENT', 'application_fee',
           CASE WHEN NOT EXISTS (SELECT 1 FROM fee) THEN 'The Bursary has not yet stated the ' || (SELECT name FROM p) || ' application fee for ' || (SELECT session FROM a) || '; the form opens once it is paid'
                ELSE 'Pay the ' || (SELECT name FROM p) || ' application fee' END
     WHERE NOT admissions.prelim_fee_settled(p_app)
    UNION ALL
    SELECT 'PERSONAL', 'sex', 'Give your sex' WHERE (SELECT sex FROM a) IS NULL
    UNION ALL
    SELECT 'PERSONAL', f.field, 'Give your ' || replace(replace(replace(f.field, 'kin_', 'next of kin''s '), '_', ' '), 'lga', 'local government area')
      FROM admissions.prelim_form_fields() f WHERE f.required AND NOT EXISTS (SELECT 1 FROM ans WHERE ans.field = f.field)
    UNION ALL
    SELECT 'OLEVEL', 'sittings',
           CASE WHEN (SELECT rule_kind FROM p) = 'ATTEMPTED_CERTIFICATE' THEN 'Give the results of the secondary school certificate examination you sat (one sitting or two).'
                ELSE 'Give your O''Level results (one sitting or two). An awaiting result is not accepted.' END
     WHERE (SELECT n FROM sittings) = 0
    UNION ALL
    SELECT 'PROGRAMME', 'target', 'Choose the ' || (SELECT target_word FROM p) WHERE (SELECT target_id FROM r) IS NULL
    UNION ALL
    SELECT 'PROGRAMME', 'target', 'The ' || (SELECT target_word FROM p) || ' you chose is no longer offered; choose another'
     WHERE (SELECT target_id FROM r) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM t WHERE t.state = 'MAPPED')
    UNION ALL
    SELECT 'PROGRAMME', 'specialisation', 'Choose your specialisation within ' || coalesce((SELECT pr.name FROM ref.programme pr JOIN t ON pr.code = t.programme_code), (SELECT requested_name FROM t))
     WHERE (SELECT specialisation_id FROM r) IS NULL
       AND EXISTS (SELECT 1 FROM admissions.prelim_specialisation s JOIN t ON s.target_id = t.id WHERE s.active)
    UNION ALL
    SELECT 'PROGRAMME', 'specialisation', 'The specialisation you chose is no longer offered; choose another'
     WHERE (SELECT specialisation_id FROM r) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM admissions.prelim_specialisation s JOIN r ON s.id = r.specialisation_id JOIN t ON s.target_id = t.id WHERE s.active)
    UNION ALL
    SELECT 'DOCUMENTS', q.kind, 'Upload your ' || lower(left(q.label, 1)) || substr(q.label, 2)
      FROM req q WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = q.kind)
    UNION ALL
    SELECT 'DOCUMENTS', d.kind, 'Replace your ' || lower(coalesce((SELECT q.label FROM admissions.prelim_document q JOIN r ON r.route = q.route WHERE q.kind = d.kind), replace(d.kind, '_', ' ')))
                                 || ', which the Office could not accept: ' || rtrim(coalesce(d.review_note, ''), '. ')
      FROM docs d WHERE d.status = 'REJECTED'
$fn$;

/* the applicant's account and application: while the route's window is open; one per address, and one per person (name and date
   of birth) in a session and route. The candidate is an ordinary admissions candidate with no JAMB number — entry mode PRELIMINARY,
   or PROFICIENCY for a proficiency certificate course (so that its payments and records are never read as preliminary). */
CREATE OR REPLACE FUNCTION admissions.prelim_register(p_route text, p_surname text, p_first text, p_middle text, p_sex text, p_dob date,
                                                      p_email text, p_phone text, p_hash text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE p admissions.prelim_programme; v_session text; v_state text; v_candidate uuid := gen_random_uuid(); v_account uuid := gen_random_uuid();
        v_app uuid := gen_random_uuid(); v_no text; fee record; v_surname text := upper(btrim(coalesce(p_surname, '')));
        v_first text := initcap(btrim(coalesce(p_first, ''))); v_middle text := nullif(initcap(btrim(coalesce(p_middle, ''))), '');
        v_phone text := admissions.cce_phone(p_phone); v_mode text;
BEGIN
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = upper(btrim(p_route));
    IF p.route IS NULL THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    v_mode := CASE p.programme_type WHEN 'PROFICIENCY_CERTIFICATE' THEN 'PROFICIENCY' ELSE 'PRELIMINARY' END;
    v_session := policy.route_session(p.route);
    SELECT w.state INTO v_state FROM policy.window_state(p.window_type, v_session, NULL) w;
    IF coalesce(v_state, 'CLOSED') <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: the % application for % is %', p.name, v_session, lower(coalesce(v_state, 'closed')) USING ERRCODE = '23514';
    END IF;
    IF v_surname = '' OR v_first = '' OR length(v_surname) > 60 OR length(v_first) > 60 OR length(coalesce(v_middle, '')) > 60 THEN
        RAISE EXCEPTION 'PRELIM_NAME: the surname and first name are given, as on your O''Level certificate' USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_sex, '')) NOT IN ('M', 'F') THEN RAISE EXCEPTION 'PRELIM_SEX: give your sex' USING ERRCODE = '23514'; END IF;
    IF p_dob IS NULL OR p_dob > current_date OR p_dob < DATE '1950-01-01' THEN
        RAISE EXCEPTION 'PRELIM_DATE_OF_BIRTH: give your date of birth' USING ERRCODE = '23514';
    END IF;
    IF v_phone IS NULL THEN RAISE EXCEPTION 'PRELIM_PHONE: give a Nigerian mobile number (eleven digits beginning with 0)' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email) USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;
    -- one application a person (name and date of birth) in a session and route; the phone number is never anyone else's application's here
    IF EXISTS (SELECT 1 FROM admissions.candidate c JOIN admissions.application ap ON ap.candidate_id = c.id
                 JOIN admissions.prelim_review pr ON pr.application_id = ap.id AND pr.route = p.route
                 JOIN admissions.screening_answer s ON s.application_id = ap.id AND s.field = 'date_of_birth'
                WHERE c.session = v_session AND upper(c.surname) = v_surname
                  AND lower(split_part(c.other_names, ' ', 1)) = lower(v_first) AND s.value = p_dob::text) THEN
        RAISE EXCEPTION 'PRELIM_DUPLICATE: an application for % % born % already exists for % (%)', v_first, v_surname, to_char(p_dob, 'DD Mon YYYY'), p.name, v_session USING ERRCODE = '23514',
            HINT = 'Sign in to the application you started; a forgotten password is reset from the sign-in page. If it is not yours, write to ' || admissions.prelim_office_words(p.route) || '.';
    END IF;
    -- the window guard on the new account reads the route (policy.application_window_guard)
    PERFORM set_config('moaum.prelim_route', p.route, true);
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, sex)
    VALUES (v_candidate, v_session, NULL, v_surname, btrim(v_first || coalesce(' ' || v_middle, '')), p.name, v_mode, 0, 'PROPOSED', upper(p_sex));
    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, v_session, v_candidate, NULL, btrim(p_email), v_phone, p_hash);
    v_no := 'APP/' || substr(v_session, 3, 2) || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (v_app, v_account, v_candidate, v_session, v_no);
    INSERT INTO admissions.prelim_review (application_id, route, state) VALUES (v_app, p.route, 'DRAFT');
    INSERT INTO admissions.screening_answer (application_id, field, value)
    VALUES (v_app, 'date_of_birth', p_dob::text), (v_app, 'mobile', v_phone), (v_app, 'personal_email', btrim(p_email));
    -- an application fee stated as nothing is nothing to pay
    SELECT * INTO fee FROM admissions.route_fee_rule(v_session, p.route);
    IF fee.stated IS NOT NULL AND coalesce(fee.application_fee, -1) + coalesce(fee.portal_charge, 0) = 0 THEN
        UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = v_app;
    END IF;
    PERFORM admissions.prelim_evaluate(v_app);
    PERFORM admissions.prelim_log(v_app, 'REGISTERED', NULL, 'DRAFT', 'The application was started online');
    PERFORM platform.tell_applicant(v_app, p.route, 'APPLICATION_CREATED', '{}'::jsonb, p.route || '_APPLICATION_CREATED:' || v_app);
    RETURN v_account;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_save_biodata(p_app uuid, p_fields jsonb, p_sex text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; k text; v text; n int := 0; d date;
BEGIN
    r := admissions.prelim_require_editable(p_app);
    IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN RAISE EXCEPTION 'the form is a set of fields' USING ERRCODE = '23514'; END IF;
    IF p_sex IS NOT NULL THEN
        IF upper(btrim(p_sex)) NOT IN ('M', 'F') THEN RAISE EXCEPTION 'PRELIM_SEX: the sex is male or female' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.candidate c SET sex = upper(btrim(p_sex)) FROM admissions.application a WHERE a.id = p_app AND c.id = a.candidate_id;
    END IF;
    FOR k IN SELECT jsonb_object_keys(p_fields) LOOP
        IF NOT EXISTS (SELECT 1 FROM admissions.prelim_form_fields() f WHERE f.field = k) THEN
            RAISE EXCEPTION 'PRELIM_FIELD: % is not a field of the application form', k USING ERRCODE = '23514';
        END IF;
        v := nullif(btrim(coalesce(p_fields->>k, '')), '');
        IF v IS NOT NULL AND length(v) > 400 THEN RAISE EXCEPTION 'PRELIM_FIELD: % is too long', k USING ERRCODE = '23514'; END IF;
        IF k = 'date_of_birth' AND v IS NOT NULL THEN
            d := admissions.cce_date(v);
            IF d IS NULL OR d > current_date OR d < DATE '1950-01-01' THEN RAISE EXCEPTION 'PRELIM_FIELD: the date of birth cannot be read' USING ERRCODE = '23514'; END IF;
            v := d::text;
        END IF;
        IF k IN ('mobile', 'alt_mobile', 'kin_mobile') AND v IS NOT NULL THEN
            IF admissions.cce_phone(v) IS NULL THEN RAISE EXCEPTION 'PRELIM_FIELD: % is not a Nigerian mobile number (eleven digits beginning with 0)', replace(k, '_', ' ') USING ERRCODE = '23514'; END IF;
            v := admissions.cce_phone(v);
        END IF;
        IF k = 'personal_email' AND v IS NOT NULL AND v !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN RAISE EXCEPTION 'PRELIM_FIELD: that is not a complete email address' USING ERRCODE = '23514'; END IF;
        IF v IS NULL THEN
            DELETE FROM admissions.screening_answer WHERE application_id = p_app AND field = k;
        ELSE
            INSERT INTO admissions.screening_answer (application_id, field, value) VALUES (p_app, k, v)
            ON CONFLICT (application_id, field) DO UPDATE SET value = EXCLUDED.value;
        END IF;
        n := n + 1;
    END LOOP;
    UPDATE admissions.application a
       SET next_of_kin = nullif(btrim(concat_ws(', ', (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_name')
                                                    || coalesce(' (' || (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_relationship') || ')', ''),
                                                (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_mobile'))), '')
     WHERE a.id = p_app;
    RETURN n;
END $fn$;

/* the O'Level or school certificate: one sitting or two (as the route allows), each complete and RELEASED — the examination body,
   the qualification (one the route accepts: the school certificate, the GCE, the NTC, the NBC, City & Guilds, …), number and year,
   and its subjects and grades. An awaiting result is refused outright. */
CREATE OR REPLACE FUNCTION admissions.prelim_save_olevel(p_app uuid, p_sittings jsonb)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; p admissions.prelim_programme; s jsonb; g jsonb; v_sit int; v_body text; v_type text; v_no text; v_year int; n int := 0; ord int := 0;
        v_subj text; v_grade text; seen text[];
BEGIN
    r := admissions.prelim_require_editable(p_app);
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    IF p_sittings IS NULL OR jsonb_typeof(p_sittings) <> 'array' OR jsonb_array_length(p_sittings) < 1 THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: give one sitting or two' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_sittings) > 2 OR jsonb_array_length(p_sittings) > p.max_sittings THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: at most % sitting% are accepted for %', p.max_sittings, CASE WHEN p.max_sittings = 1 THEN '' ELSE 's' END, p.name USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.screening_olevel SET active = false WHERE application_id = p_app AND active;
    SELECT coalesce(max(o.ord), 0) INTO ord FROM admissions.screening_olevel o WHERE o.application_id = p_app;
    FOR s IN SELECT x FROM jsonb_array_elements(p_sittings) x LOOP
        v_sit := coalesce((s->>'sitting')::int, 0);
        IF v_sit NOT IN (1, 2) THEN RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: a sitting is the first or the second' USING ERRCODE = '23514'; END IF;
        IF coalesce((s->>'awaiting')::boolean, false) THEN
            RAISE EXCEPTION 'PRELIM_AWAITING_RESULT: sitting %: an awaiting result is not accepted — % admission is on results already released', v_sit, p.name USING ERRCODE = '23514';
        END IF;
        v_body := upper(btrim(coalesce(s->>'exam_body', '')));
        IF v_body NOT IN ('WAEC', 'NECO', 'NABTEB', 'OTHER') THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_BODY: sitting %: the examination body is WAEC, NECO, NABTEB or another', v_sit USING ERRCODE = '23514';
        END IF;
        v_type := nullif(upper(btrim(coalesce(s->>'exam_type', ''))), '');
        IF v_type IS NOT NULL AND (v_type <> ALL (p.qualification_types) OR NOT EXISTS (SELECT 1 FROM admissions.qualification_type q WHERE q.code = v_type AND q.active)) THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_TYPE: sitting %: % accepts %', v_sit, p.name,
                (SELECT string_agg(q.label, ', ' ORDER BY q.ord) FROM admissions.qualification_type q WHERE q.code = ANY (p.qualification_types) AND q.active) USING ERRCODE = '23514';
        END IF;
        v_no := nullif(btrim(coalesce(s->>'exam_number', '')), '');
        IF v_no IS NULL OR length(v_no) > 30 THEN RAISE EXCEPTION 'PRELIM_OLEVEL_NUMBER: sitting %: the examination number is given', v_sit USING ERRCODE = '23514'; END IF;
        v_year := CASE WHEN coalesce(s->>'exam_year', '') ~ '^[0-9]{4}$' THEN (s->>'exam_year')::int END;
        IF v_year IS NULL OR v_year < 1970 OR v_year > extract(year FROM current_date)::int THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_YEAR: sitting %: the year of the examination is given', v_sit USING ERRCODE = '23514';
        END IF;
        -- V701: one examination sitting is one person's — it is on no other live application of the route and session
        IF EXISTS (SELECT 1 FROM admissions.screening_olevel o
                     JOIN admissions.prelim_review pr ON pr.application_id = o.application_id AND pr.route = r.route AND pr.state <> 'WITHDRAWN'
                     JOIN admissions.application ap ON ap.id = o.application_id
                    WHERE o.active AND o.application_id <> p_app AND ap.session = (SELECT x.session FROM admissions.application x WHERE x.id = p_app)
                      AND upper(o.exam_body) = v_body AND o.exam_year = v_year
                      AND upper(regexp_replace(o.exam_number, '\s', '', 'g')) = upper(regexp_replace(v_no, '\s', '', 'g'))) THEN
            RAISE EXCEPTION 'PRELIM_DUPLICATE_OLEVEL: sitting %: the % examination number % (%) is already on another % application for this session', v_sit, v_body, v_no, v_year, p.name
                USING ERRCODE = '23514', HINT = 'Sign in to the application you started. If the number is yours and the other application is not, write to the Office.';
        END IF;
        IF jsonb_typeof(s->'subjects') <> 'array' OR jsonb_array_length(s->'subjects') = 0 THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_INCOMPLETE: sitting % has no subjects; a second sitting is complete or not given', v_sit USING ERRCODE = '23514';
        END IF;
        IF jsonb_array_length(s->'subjects') > 9 THEN RAISE EXCEPTION 'PRELIM_OLEVEL_SUBJECTS: sitting %: nine subjects at most', v_sit USING ERRCODE = '23514'; END IF;
        seen := '{}';
        FOR g IN SELECT x FROM jsonb_array_elements(s->'subjects') x LOOP
            v_subj := nullif(btrim(coalesce(g->>'subject', '')), '');
            v_grade := upper(btrim(coalesce(g->>'grade', '')));
            IF v_subj IS NULL OR length(v_subj) > 60 THEN RAISE EXCEPTION 'PRELIM_OLEVEL_INCOMPLETE: sitting %: a subject is named', v_sit USING ERRCODE = '23514'; END IF;
            IF v_grade IN ('AR', 'AWAITING', 'AWAITING RESULT', 'PENDING', 'NR', '*') THEN
                RAISE EXCEPTION 'PRELIM_AWAITING_RESULT: sitting %, %: an awaiting result is not accepted — % admission is on results already released', v_sit, v_subj, p.name USING ERRCODE = '23514';
            END IF;
            IF v_grade NOT IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6', 'D7', 'E8', 'F9') THEN
                RAISE EXCEPTION 'PRELIM_OLEVEL_GRADE: sitting %, %: the grade is one of A1, B2, B3, C4, C5, C6, D7, E8, F9', v_sit, v_subj USING ERRCODE = '23514';
            END IF;
            IF upper(v_subj) = ANY (seen) THEN RAISE EXCEPTION 'PRELIM_OLEVEL_SUBJECTS: sitting %: % is given twice', v_sit, v_subj USING ERRCODE = '23514'; END IF;
            seen := array_append(seen, upper(v_subj));
            ord := ord + 1;
            INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_type, exam_number, exam_year, subject, grade, active, sitting)
            VALUES (p_app, ord, v_body, v_type, v_no, v_year, v_subj, v_grade, true, v_sit);
            n := n + 1;
        END LOOP;
    END LOOP;
    IF (SELECT count(DISTINCT sitting) FROM admissions.screening_olevel WHERE application_id = p_app AND active) <> jsonb_array_length(p_sittings) THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_SITTINGS: the same sitting is given twice' USING ERRCODE = '23514';
    END IF;
    -- a corrected result is verified afresh
    UPDATE admissions.prelim_review SET olevel_verification = 'PENDING', olevel_verified_by = NULL, olevel_verified_at = NULL, updated_at = now()
     WHERE application_id = p_app AND olevel_verification <> 'PENDING';
    PERFORM admissions.prelim_evaluate(p_app);
    RETURN n;
END $fn$;

/* the target and its option: the applicant chooses among the route's targets — a programme of the register (the intended
   progression, never an admission into the degree) or a certificate course — and, where the target has options, one of them,
   while the form is theirs; an officer changes either with a reason until the outcome is published. The eligibility is read
   again: an area's own subjects count from the moment it is chosen. */
CREATE OR REPLACE FUNCTION admissions.prelim_choose(p_app uuid, p_target uuid, p_specialisation uuid, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; t admissions.prelim_target; p admissions.prelim_programme; v_office text := coalesce(nullif(current_setting('moaum.actor_office', true), ''), '');
        v_name text; v_spec admissions.prelim_specialisation; v_has_options boolean;
BEGIN
    r := admissions.prelim_application(p_app);
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    IF v_office = 'applicant' THEN
        r := admissions.prelim_require_editable(p_app);
    ELSE
        PERFORM admissions.prelim_require_office(ARRAY[p.office_code, 'academic', 'super'], 'changing the ' || p.target_word || ' of a ' || p.name || ' application');
        SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
        IF r.published_at IS NOT NULL OR r.state IN ('WITHDRAWN', 'ADMITTED') THEN
            RAISE EXCEPTION 'PRELIM_TARGET_FIXED: the outcome is published; the % stands', p.target_word USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a change of the % is recorded with its reason', p.target_word USING ERRCODE = '23514'; END IF;
    END IF;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = p_target AND route = r.route AND state = 'MAPPED';
    IF t.id IS NULL THEN
        RAISE EXCEPTION 'PRELIM_TARGET_NOT_OFFERED: that is not a % offered under %', p.target_word, p.name USING ERRCODE = '23514';
    END IF;
    v_name := coalesce((SELECT pr.name FROM ref.programme pr WHERE pr.code = t.programme_code), t.requested_name);
    v_has_options := EXISTS (SELECT 1 FROM admissions.prelim_specialisation s WHERE s.target_id = t.id AND s.active);
    IF p_specialisation IS NOT NULL THEN
        SELECT * INTO v_spec FROM admissions.prelim_specialisation WHERE id = p_specialisation AND target_id = t.id AND active;
        IF v_spec.id IS NULL THEN
            RAISE EXCEPTION 'PRELIM_SPECIALISATION_NOT_OFFERED: that specialisation is not one of %', v_name USING ERRCODE = '23514';
        END IF;
    END IF;
    IF r.target_id IS NOT DISTINCT FROM t.id AND r.specialisation_id IS NOT DISTINCT FROM p_specialisation THEN RETURN v_name; END IF;
    UPDATE admissions.prelim_review SET target_id = t.id, target_programme = t.programme_code, specialisation_id = p_specialisation,
           target_set_at = now(), updated_at = now()
     WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, CASE WHEN r.target_id IS NULL THEN 'TARGET_SET' ELSE 'TARGET_CHANGED' END, r.state, r.state, p_note,
                                  jsonb_strip_nulls(jsonb_build_object('from', r.target_id, 'to', t.id, 'name', v_name, 'specialisation', v_spec.name,
                                                                       'fromSpecialisation', r.specialisation_id)));
    PERFORM admissions.prelim_evaluate(p_app);
    RETURN v_name || coalesce(' — ' || v_spec.name, '');
END $fn$;
COMMENT ON FUNCTION admissions.prelim_choose(uuid, uuid, uuid, text) IS
  'V701: the target (a programme or a certificate course) and its option chosen — by the applicant while the form is theirs, by the route''s office or the Academic Office with a reason until the outcome is published; the eligibility read again.';

/* V446's form of the choice, by programme code: the target that programme is, with no option */
CREATE OR REPLACE FUNCTION admissions.prelim_set_target(p_app uuid, p_programme text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_target uuid;
BEGIN
    r := admissions.prelim_application(p_app);
    SELECT t.id INTO v_target FROM admissions.prelim_target t WHERE t.route = r.route AND t.programme_code = p_programme AND t.state = 'MAPPED';
    IF v_target IS NULL THEN
        RAISE EXCEPTION 'PRELIM_TARGET_NOT_OFFERED: that programme is not a target programme of %', (SELECT name FROM admissions.prelim_programme WHERE route = r.route) USING ERRCODE = '23514';
    END IF;
    RETURN admissions.prelim_choose(p_app, v_target, CASE WHEN r.target_id = v_target THEN r.specialisation_id END, p_note);
END $fn$;

/* the applicant submits — or sends back what the Office asked for. A first submission is made while the route's window is open. */
CREATE OR REPLACE FUNCTION admissions.prelim_submit(p_app uuid, p_ip text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; p admissions.prelim_programme; v_missing text; v_state text; v_elig text;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    IF r.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN RETURN 'already submitted'; END IF;
    IF r.state = 'DRAFT' THEN
        SELECT w.state INTO v_state FROM policy.window_state(p.window_type, a.session, NULL) w;
        IF coalesce(v_state, 'CLOSED') <> 'OPEN' THEN
            RAISE EXCEPTION 'APPLICATION_CLOSED: the % application for % is %; an application is submitted while the window is open', p.name, a.session, lower(coalesce(v_state, 'closed')) USING ERRCODE = '23514';
        END IF;
    END IF;
    SELECT string_agg(x.message, '; ') INTO v_missing FROM (SELECT pb.message FROM admissions.prelim_problems(p_app) pb LIMIT 6) x;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'PRELIM_INCOMPLETE: the application is not complete: %', v_missing USING ERRCODE = '23514';
    END IF;
    v_elig := admissions.prelim_evaluate(p_app);
    IF r.state = 'DRAFT' THEN
        UPDATE admissions.prelim_review SET state = 'SUBMITTED', submitted_at = now(), declaration_ip = p_ip, updated_at = now() WHERE application_id = p_app;
        PERFORM admissions.prelim_log(p_app, 'SUBMITTED', 'DRAFT', 'SUBMITTED', NULL, jsonb_build_object('eligibility', v_elig));
        PERFORM platform.tell_applicant(p_app, r.route, 'APPLICATION_SUBMITTED', '{}'::jsonb, r.route || '_APPLICATION_SUBMITTED:' || p_app);
        RETURN 'submitted';
    END IF;
    UPDATE admissions.prelim_review SET state = 'UNDER_REVIEW', updated_at = now() WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'CORRECTED', r.state, 'UNDER_REVIEW', 'The applicant sent the application back with the correction asked for', jsonb_build_object('eligibility', v_elig));
    RETURN 'returned to the Office';
END $fn$;

-- ── 9 · the route's office reviews, the Academic Office approves and publishes ──────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_review_document(p_document uuid, p_status text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE d admissions.application_document; r admissions.prelim_review; v_label text;
BEGIN
    SELECT * INTO d FROM admissions.application_document WHERE id = p_document FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such document' USING ERRCODE = '23503'; END IF;
    r := admissions.prelim_application(d.application_id);
    PERFORM admissions.prelim_require_office(ARRAY[admissions.prelim_office(r.route), 'academic', 'super'], 'verifying a preliminary or proficiency applicant''s documents');
    IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED') THEN
        RAISE EXCEPTION 'PRELIM_REVIEW_STATE: the documents of a % application are not reviewed', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF p_status NOT IN ('ACCEPTED', 'REJECTED') THEN RAISE EXCEPTION 'a document is ACCEPTED or REJECTED' USING ERRCODE = '23514'; END IF;
    IF p_status = 'REJECTED' AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PRELIM_DOCUMENT_REASON: a document is rejected with the reason the applicant reads' USING ERRCODE = '23514';
    END IF;
    IF d.superseded_at IS NOT NULL THEN RAISE EXCEPTION 'PRELIM_DOCUMENT_REPLACED: the applicant has replaced this document' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.application_document SET status = p_status, reviewed_at = now(), reviewed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           review_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_document;
    SELECT q.label INTO v_label FROM admissions.prelim_document q WHERE q.route = r.route AND q.kind = d.kind;
    PERFORM admissions.prelim_log(d.application_id, 'DOCUMENT_' || p_status, r.state, r.state, coalesce(v_label, d.kind) || coalesce(': ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    RETURN p_status;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_verify_olevel(p_app uuid, p_outcome text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_elig text; v_to text;
BEGIN
    r := admissions.prelim_application(p_app);
    PERFORM admissions.prelim_require_office(ARRAY[admissions.prelim_office(r.route), 'academic', 'super'], 'verifying a preliminary or proficiency applicant''s O''Level');
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED') THEN
        RAISE EXCEPTION 'PRELIM_REVIEW_STATE: the O''Level of a % application is not verified', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_outcome, '')) NOT IN ('VERIFIED', 'INVALID') THEN RAISE EXCEPTION 'an O''Level is VERIFIED or INVALID' USING ERRCODE = '23514'; END IF;
    IF upper(p_outcome) = 'INVALID' AND v_note IS NULL THEN
        RAISE EXCEPTION 'PRELIM_OLEVEL_REASON: an invalid result is recorded with what was found' USING ERRCODE = '23514';
    END IF;
    v_to := CASE WHEN r.state = 'RECOMMENDED' AND upper(p_outcome) = 'INVALID' THEN 'UNDER_REVIEW' ELSE r.state END;
    UPDATE admissions.prelim_review
       SET olevel_verification = upper(p_outcome), olevel_verified_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, olevel_verified_at = now(),
           olevel_note = v_note, state = v_to,
           recommended_at = CASE WHEN v_to <> r.state THEN NULL ELSE recommended_at END,
           recommended_by = CASE WHEN v_to <> r.state THEN NULL ELSE recommended_by END,
           recommendation_note = CASE WHEN v_to <> r.state THEN NULL ELSE recommendation_note END,
           updated_at = now()
     WHERE application_id = p_app;
    v_elig := admissions.prelim_evaluate(p_app);
    PERFORM admissions.prelim_log(p_app, 'OLEVEL_' || upper(p_outcome), r.state, v_to, v_note, jsonb_build_object('eligibility', v_elig));
    RETURN v_elig;
END $fn$;

/* one step of the review (V446), the route's office in place of the Preliminary Science Office: START, REQUEST_CORRECTION, RESUME,
   RECOMMEND (documents accepted, O'Level verified, eligible, the target and any option chosen — the route's office), APPROVE (the
   Academic Office, never the officer who recommended), NOT_ADMIT and REJECT (with the reason), REOPEN */
CREATE OR REPLACE FUNCTION admissions.prelim_act(p_app uuid, p_action text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; p admissions.prelim_programme; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_to text; v_pending int; v_elig text;
BEGIN
    PERFORM admissions.prelim_application(p_app);
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a preliminary or proficiency application is reviewed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    IF r.published_at IS NOT NULL THEN
        RAISE EXCEPTION 'PRELIM_PUBLISHED: the outcome was published on % and stands', to_char(r.published_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
    CASE upper(p_action)
    WHEN 'START' THEN
        PERFORM admissions.prelim_require_office(ARRAY[p.office_code, 'academic', 'super'], 'reviewing ' || p.name || ' applications');
        IF r.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'PRELIM_REVIEW_STATE: only a submitted application is taken up; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.prelim_review SET state = v_to, review_started_at = now(), review_started_by = v_actor, updated_at = now() WHERE application_id = p_app;
    WHEN 'REQUEST_CORRECTION' THEN
        PERFORM admissions.prelim_require_office(ARRAY[p.office_code, 'academic', 'super'], 'asking a ' || p.name || ' applicant for a correction');
        IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED') THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: a % application is not sent back to the applicant', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_REQUEST_NOTE: say what the applicant is to correct or provide' USING ERRCODE = '23514'; END IF;
        v_to := 'CORRECTION_REQUIRED';
        UPDATE admissions.prelim_review SET state = v_to, request_note = v_note, requested_at = now(), requested_by = v_actor,
               recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, updated_at = now()
         WHERE application_id = p_app;
        PERFORM platform.tell_applicant(p_app, r.route, 'CORRECTION_REQUIRED', jsonb_build_object('NOTE', v_note),
                                        r.route || '_CORRECTION_REQUIRED:' || p_app || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
    WHEN 'RESUME' THEN
        PERFORM admissions.prelim_require_office(ARRAY[p.office_code, 'academic', 'super'], 'reviewing ' || p.name || ' applications');
        IF r.state <> 'CORRECTION_REQUIRED' THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: only an application waiting on the applicant is taken back; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.prelim_review SET state = v_to, updated_at = now() WHERE application_id = p_app;
    WHEN 'RECOMMEND' THEN
        PERFORM admissions.prelim_require_office(ARRAY[p.office_code, 'super'], 'recommending a ' || p.name || ' admission');
        IF r.state <> 'UNDER_REVIEW' THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: an application is recommended from review; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        SELECT count(*) INTO v_pending FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL AND d.status <> 'ACCEPTED';
        IF v_pending > 0 THEN
            RAISE EXCEPTION 'PRELIM_DOCUMENTS_UNVERIFIED: % document(s) not yet accepted; verify every document before recommending', v_pending USING ERRCODE = '23514';
        END IF;
        IF r.olevel_verification <> 'VERIFIED' THEN
            RAISE EXCEPTION 'PRELIM_OLEVEL_UNVERIFIED: verify the O''Level against the result documents before recommending' USING ERRCODE = '23514';
        END IF;
        v_elig := admissions.prelim_evaluate(p_app);
        IF v_elig NOT IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION') THEN
            RAISE EXCEPTION 'PRELIM_NOT_ELIGIBLE: the applicant does not meet the entry requirement (%); an ineligible application is not recommended', lower(replace(v_elig, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.target_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NO_TARGET: no % is chosen', p.target_word USING ERRCODE = '23514'; END IF;
        IF r.specialisation_id IS NULL AND EXISTS (SELECT 1 FROM admissions.prelim_specialisation s WHERE s.target_id = r.target_id AND s.active) THEN
            RAISE EXCEPTION 'PRELIM_NO_SPECIALISATION: no specialisation is chosen within the %', p.target_word USING ERRCODE = '23514';
        END IF;
        v_to := 'RECOMMENDED';
        UPDATE admissions.prelim_review SET state = v_to, recommended_at = now(), recommended_by = v_actor, recommendation_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'APPROVE' THEN
        PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'approving a ' || p.name || ' admission');
        IF r.state <> 'RECOMMENDED' THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: an admission is approved once recommended; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.recommended_by = v_actor THEN
            RAISE EXCEPTION 'PRELIM_APPROVE_OWN: the officer who recommended an admission does not also approve it' USING ERRCODE = '23514';
        END IF;
        v_to := 'APPROVED';
        UPDATE admissions.prelim_review SET state = v_to, decided_at = now(), decided_by = v_actor, decided_office = v_office, decision_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'NOT_ADMIT', 'REJECT' THEN
        PERFORM admissions.prelim_require_office(ARRAY[p.office_code, 'academic', 'super'], 'deciding a ' || p.name || ' application');
        IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED', 'APPROVED') THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: a % application is not decided', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_DECISION_NOTE: the reason is recorded and is what the applicant reads' USING ERRCODE = '23514'; END IF;
        v_to := CASE upper(p_action) WHEN 'NOT_ADMIT' THEN 'NOT_ADMITTED' ELSE 'REJECTED' END;
        UPDATE admissions.prelim_review SET state = v_to, decided_at = now(), decided_by = v_actor, decided_office = v_office, decision_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'REOPEN' THEN
        PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'reopening a ' || p.name || ' application');
        IF r.state NOT IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED') THEN
            RAISE EXCEPTION 'PRELIM_REVIEW_STATE: only a decided, unpublished application is reopened; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_REOPEN_NOTE: say why the decision is reopened' USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.prelim_review SET state = v_to, decided_at = NULL, decided_by = NULL, decided_office = NULL, decision_note = NULL,
               recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, updated_at = now()
         WHERE application_id = p_app;
    ELSE
        RAISE EXCEPTION 'unknown review step %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM admissions.prelim_log(p_app, upper(p_action), r.state, v_to, v_note);
    RETURN v_to;
END $fn$;

/* the Academic Office publishes a route's outcome: an approved admission becomes the ordinary offer (into the programme itself —
   never the target degree); a declined one the ordinary NOT_OFFERED with its reason; each told in the route's own notices */
CREATE OR REPLACE FUNCTION admissions.prelim_publish(p_route text, p_session text, p_apps uuid[])
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x record; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; n_adm int := 0; n_not int := 0; n_rej int := 0; v_rem text;
        v_route text := upper(btrim(p_route));
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'publishing a preliminary or proficiency admission list');
    FOR x IN SELECT r.*, a.application_no, a.candidate_id,
                    coalesce(p.name, t.requested_name) || coalesce(' (' || sp.name || ')', '') AS target_name
               FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
               LEFT JOIN admissions.prelim_target t ON t.id = r.target_id
               LEFT JOIN ref.programme p ON p.code = t.programme_code
               LEFT JOIN admissions.prelim_specialisation sp ON sp.id = r.specialisation_id
              WHERE r.route = v_route AND a.session = p_session AND r.published_at IS NULL AND r.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED')
                AND (p_apps IS NULL OR r.application_id = ANY (p_apps))
              ORDER BY a.application_no FOR UPDATE OF r LOOP
        IF x.state = 'APPROVED' THEN
            UPDATE admissions.application SET decision = 'OFFERED', decision_basis = 'OTHER', decision_note = x.decision_note, decided_at = x.decided_at,
                   decision_released_at = now() WHERE id = x.application_id;
            UPDATE admissions.candidate SET offer_state = 'ADMITTED' WHERE id = x.candidate_id AND offer_state = 'PROPOSED';
            UPDATE admissions.prelim_review SET state = 'ADMITTED', published_at = now(), published_by = v_actor, updated_at = now() WHERE application_id = x.application_id;
            PERFORM admissions.prelim_log(x.application_id, 'PUBLISHED', 'APPROVED', 'ADMITTED', NULL);
            v_rem := CASE WHEN x.remediation_status = 'REQUIRED'
                          THEN array_to_string(x.remediation_subjects
                                   || CASE WHEN x.remediation_credits_short > 0 THEN ARRAY[x.remediation_credits_short || ' more O''Level credit pass' || CASE WHEN x.remediation_credits_short = 1 THEN '' ELSE 'es' END] ELSE '{}' END, ', ') END;
            PERFORM platform.tell_applicant(x.application_id, v_route, 'ADMISSION_OFFERED',
                jsonb_strip_nulls(jsonb_build_object('TARGET_PROGRAMME', x.target_name,
                    'REMEDIATION_NOTE', CASE WHEN v_rem IS NOT NULL THEN 'Before completing the programme you are to make up: ' || v_rem || '.' ELSE '' END)),
                v_route || '_ADMISSION_OFFERED:' || x.application_id);
            IF v_rem IS NOT NULL THEN
                PERFORM platform.tell_applicant(x.application_id, v_route, 'REMEDIATION_REQUIRED', jsonb_build_object('REMEDIATION', v_rem),
                                                v_route || '_REMEDIATION_REQUIRED:' || x.application_id);
            END IF;
            n_adm := n_adm + 1;
        ELSE
            UPDATE admissions.application SET decision = 'NOT_OFFERED', decision_basis = NULL, decision_note = x.decision_note, decided_at = x.decided_at,
                   decision_released_at = now() WHERE id = x.application_id;
            UPDATE admissions.prelim_review SET published_at = now(), published_by = v_actor, updated_at = now() WHERE application_id = x.application_id;
            PERFORM admissions.prelim_log(x.application_id, 'PUBLISHED', x.state, x.state, NULL);
            PERFORM platform.tell_applicant(x.application_id, v_route, 'ADMISSION_NOT_OFFERED', jsonb_build_object('NOTE', coalesce(x.decision_note, '')),
                                            v_route || '_ADMISSION_NOT_OFFERED:' || x.application_id);
            IF x.state = 'NOT_ADMITTED' THEN n_not := n_not + 1; ELSE n_rej := n_rej + 1; END IF;
        END IF;
    END LOOP;
    RETURN jsonb_build_object('admitted', n_adm, 'not_admitted', n_not, 'rejected', n_rej);
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_set_remediation(p_app uuid, p_status text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    r := admissions.prelim_application(p_app);
    PERFORM admissions.prelim_require_office(ARRAY[admissions.prelim_office(r.route), 'academic', 'super'], 'recording a preliminary applicant''s remediation');
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF upper(coalesce(p_status, '')) NOT IN ('NOT_REQUIRED', 'REQUIRED', 'IN_PROGRESS', 'COMPLETED', 'NOT_COMPLETED', 'REQUIRES_REVIEW') THEN
        RAISE EXCEPTION 'PRELIM_REMEDIATION_STATUS: the remediation is not required, required, in progress, completed, not completed or under review' USING ERRCODE = '23514';
    END IF;
    IF v_note IS NULL THEN RAISE EXCEPTION 'PRELIM_REMEDIATION_NOTE: the remediation is recorded with its reason or evidence' USING ERRCODE = '23514'; END IF;
    IF r.eligibility_status NOT IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION') THEN
        RAISE EXCEPTION 'PRELIM_REMEDIATION_NOT_ELIGIBLE: a remediation is recorded for an eligible applicant' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.prelim_review SET remediation_status = upper(p_status), remediation_note = v_note, remediation_set_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           remediation_set_at = now(), updated_at = now()
     WHERE application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'REMEDIATION_' || upper(p_status), r.state, r.state, v_note,
                                  jsonb_build_object('from', r.remediation_status, 'to', upper(p_status), 'subjects', to_jsonb(r.remediation_subjects)));
    RETURN upper(p_status);
END $fn$;

-- ── 10 · the configuration, the Academic Office's (the fee the Bursary's) ──────────────────────────────────────────
/* the programme's description and rule, changed with a reason; every open application is read again under the new rule */
CREATE OR REPLACE FUNCTION admissions.prelim_set_rules(p_route text, p_settings jsonb, p_reason text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE p admissions.prelim_programme; k text; x record; n int := 0;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing a preliminary or proficiency programme and its requirements');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_RULES_REASON: a change to the programme is recorded with its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = upper(btrim(p_route)) FOR UPDATE;
    IF p.route IS NULL THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    IF p_settings IS NULL OR jsonb_typeof(p_settings) <> 'object' THEN RAISE EXCEPTION 'the settings are a set of fields' USING ERRCODE = '23514'; END IF;
    FOR k IN SELECT jsonb_object_keys(p_settings) LOOP
        IF k NOT IN ('name', 'description', 'completion_note', 'procedure', 'office_note', 'min_credits', 'max_sittings', 'min_core_credits', 'core_subjects',
                     'credit_grade', 'completion_credits', 'completion_subjects', 'remediation_terms',
                     'required_subjects', 'completion_scope', 'qualification_types', 'duration_months', 'certificate_type', 'entry_requirement', 'target_note') THEN
            RAISE EXCEPTION 'PRELIM_RULES_FIELD: % is not a setting of the programme', k USING ERRCODE = '23514';
        END IF;
    END LOOP;
    IF p_settings ? 'qualification_types' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(p_settings->'qualification_types') v
                                                      WHERE NOT EXISTS (SELECT 1 FROM admissions.qualification_type q WHERE q.code = upper(btrim(v)))) THEN
        RAISE EXCEPTION 'PRELIM_RULES_QUALIFICATION: a qualification type is one of %', (SELECT string_agg(code, ', ' ORDER BY ord) FROM admissions.qualification_type) USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    UPDATE admissions.prelim_programme SET
        name = coalesce(nullif(btrim(p_settings->>'name'), ''), name),
        description = coalesce(nullif(btrim(p_settings->>'description'), ''), description),
        completion_note = coalesce(p_settings->>'completion_note', completion_note),
        procedure = CASE WHEN p_settings ? 'procedure' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'procedure') v WHERE btrim(v) <> '') ELSE procedure END,
        office_note = CASE WHEN p_settings ? 'office_note' THEN nullif(btrim(p_settings->>'office_note'), '') ELSE office_note END,
        min_credits = coalesce((p_settings->>'min_credits')::int, min_credits),
        max_sittings = coalesce((p_settings->>'max_sittings')::int, max_sittings),
        min_core_credits = coalesce((p_settings->>'min_core_credits')::int, min_core_credits),
        core_subjects = CASE WHEN p_settings ? 'core_subjects' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'core_subjects') v WHERE btrim(v) <> '') ELSE core_subjects END,
        credit_grade = coalesce(upper(nullif(btrim(p_settings->>'credit_grade'), '')), credit_grade),
        completion_credits = coalesce((p_settings->>'completion_credits')::int, completion_credits),
        completion_subjects = CASE WHEN p_settings ? 'completion_subjects' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'completion_subjects') v WHERE btrim(v) <> '') ELSE completion_subjects END,
        remediation_terms = CASE WHEN p_settings ? 'remediation_terms' THEN nullif(btrim(p_settings->>'remediation_terms'), '') ELSE remediation_terms END,
        required_subjects = CASE WHEN p_settings ? 'required_subjects' THEN ARRAY(SELECT btrim(v) FROM jsonb_array_elements_text(p_settings->'required_subjects') v WHERE btrim(v) <> '') ELSE required_subjects END,
        completion_scope = coalesce(upper(nullif(btrim(p_settings->>'completion_scope'), '')), completion_scope),
        qualification_types = CASE WHEN p_settings ? 'qualification_types' THEN ARRAY(SELECT DISTINCT upper(btrim(v)) FROM jsonb_array_elements_text(p_settings->'qualification_types') v WHERE btrim(v) <> '') ELSE qualification_types END,
        duration_months = CASE WHEN p_settings ? 'duration_months' THEN nullif(p_settings->>'duration_months', '')::int ELSE duration_months END,
        certificate_type = CASE WHEN p_settings ? 'certificate_type' THEN nullif(btrim(p_settings->>'certificate_type'), '') ELSE certificate_type END,
        entry_requirement = CASE WHEN p_settings ? 'entry_requirement' THEN nullif(btrim(p_settings->>'entry_requirement'), '') ELSE entry_requirement END,
        target_note = CASE WHEN p_settings ? 'target_note' THEN nullif(btrim(p_settings->>'target_note'), '') ELSE target_note END,
        rules_version = rules_version + 1,
        updated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, updated_office = nullif(current_setting('moaum.actor_office', true), ''), updated_at = now()
     WHERE route = p.route;
    -- the applications not yet published are read again under the new rule
    FOR x IN SELECT r.application_id FROM admissions.prelim_review r WHERE r.route = p.route AND r.published_at IS NULL AND r.state <> 'WITHDRAWN' LOOP
        PERFORM admissions.prelim_evaluate(x.application_id);
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;

/* a target programme added: an existing, current undergraduate programme, once; a withdrawn one is reinstated */
CREATE OR REPLACE FUNCTION admissions.prelim_add_target(p_route text, p_programme text, p_group text, p_ord integer, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target; v_id uuid; v_name text; v_route text := upper(btrim(p_route));
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'adding a preliminary target programme');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a target programme is added with its reason' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.prelim_programme WHERE route = v_route) THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    IF policy.route_session(v_route) IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = policy.route_session(v_route)) THEN
        RAISE EXCEPTION 'PRELIM_SESSION: the programme''s session is not on the calendar' USING ERRCODE = '23514';
    END IF;
    SELECT name INTO v_name FROM ref.programme WHERE code = p_programme;
    IF v_name IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_UNKNOWN: no programme % on the register', p_programme USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    SELECT * INTO t FROM admissions.prelim_target WHERE route = v_route AND programme_code = p_programme FOR UPDATE;
    IF t.id IS NOT NULL AND t.state = 'MAPPED' THEN
        RAISE EXCEPTION 'PRELIM_TARGET_DUPLICATE: % is already a target programme', v_name USING ERRCODE = '23514';
    ELSIF t.id IS NOT NULL THEN
        UPDATE admissions.prelim_target SET state = 'MAPPED', group_name = coalesce(nullif(btrim(p_group), ''), group_name), ord = coalesce(p_ord, ord), note = p_reason
         WHERE id = t.id;
        RETURN t.id;
    END IF;
    INSERT INTO admissions.prelim_target (route, group_name, ord, requested_name, programme_code, state, note, added_by, added_office)
    VALUES (v_route, coalesce(nullif(btrim(p_group), ''), 'Other'), coalesce(p_ord, 500), v_name, p_programme, 'MAPPED', p_reason,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;

/* a certificate course added to a route (the proficiency courses): never a programme of the register, never a degree */
CREATE OR REPLACE FUNCTION admissions.prelim_add_course(p_route text, p_name text, p_group text, p_ord integer, p_description text, p_months integer, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target; v_id uuid; v_route text := upper(btrim(p_route)); v_name text := btrim(coalesce(p_name, ''));
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'adding a certificate course');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a certificate course is added with its reason' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.prelim_programme WHERE route = v_route) THEN RAISE EXCEPTION 'PRELIM_NO_PROGRAMME: no preliminary programme %', p_route USING ERRCODE = '23514'; END IF;
    IF v_name = '' OR length(v_name) > 150 THEN RAISE EXCEPTION 'PRELIM_COURSE_NAME: a certificate course has its name' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_group, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_COURSE_CATEGORY: a certificate course is in a category' USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    SELECT * INTO t FROM admissions.prelim_target WHERE route = v_route AND kind = 'COURSE' AND lower(btrim(requested_name)) = lower(v_name) FOR UPDATE;
    IF t.id IS NOT NULL AND t.state = 'MAPPED' THEN
        RAISE EXCEPTION 'PRELIM_TARGET_DUPLICATE: % is already a certificate course', v_name USING ERRCODE = '23514';
    ELSIF t.id IS NOT NULL THEN
        UPDATE admissions.prelim_target SET state = 'MAPPED', group_name = btrim(p_group), ord = coalesce(p_ord, ord), note = p_reason,
               description = coalesce(nullif(btrim(coalesce(p_description, '')), ''), description), duration_months = coalesce(p_months, duration_months)
         WHERE id = t.id;
        RETURN t.id;
    END IF;
    INSERT INTO admissions.prelim_target (route, kind, group_name, ord, requested_name, programme_code, state, note, description, duration_months, added_by, added_office)
    VALUES (v_route, 'COURSE', btrim(p_group), coalesce(p_ord, 500), v_name, NULL, 'MAPPED', p_reason, nullif(btrim(coalesce(p_description, '')), ''), p_months,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING id INTO v_id;
    RETURN v_id;
END $fn$;

/* a target withdrawn (kept, WITHDRAWN, for the applications that chose it) or reinstated, or a programme named but missing from the
   register resolved to the existing programme it is */
CREATE OR REPLACE FUNCTION admissions.prelim_change_target(p_target uuid, p_action text, p_programme text, p_reason text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing a preliminary target or certificate course');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_TARGET_REASON: a change of a target is recorded with its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = p_target FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such target' USING ERRCODE = '23503'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    CASE upper(p_action)
    WHEN 'WITHDRAW' THEN
        IF t.state <> 'MAPPED' THEN RAISE EXCEPTION 'PRELIM_TARGET_STATE: only an offered target is withdrawn' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.prelim_target SET state = 'WITHDRAWN', note = p_reason WHERE id = t.id;
        RETURN 'WITHDRAWN';
    WHEN 'REINSTATE' THEN
        IF t.state <> 'WITHDRAWN' THEN RAISE EXCEPTION 'PRELIM_TARGET_STATE: only a withdrawn target is reinstated' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.prelim_target SET state = 'MAPPED', note = p_reason WHERE id = t.id;
        RETURN 'MAPPED';
    WHEN 'RESOLVE' THEN
        IF t.kind <> 'PROGRAMME' OR t.state <> 'MISSING' THEN RAISE EXCEPTION 'PRELIM_TARGET_STATE: only a missing target programme is resolved' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM admissions.prelim_target x WHERE x.route = t.route AND x.programme_code = p_programme) THEN
            RAISE EXCEPTION 'PRELIM_TARGET_DUPLICATE: that programme is already a target programme' USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.prelim_target SET state = 'MAPPED', programme_code = p_programme, note = p_reason WHERE id = t.id;
        RETURN 'MAPPED';
    ELSE
        RAISE EXCEPTION 'unknown change %', p_action USING ERRCODE = '23514';
    END CASE;
END $fn$;

/* an area's own subjects, some of which must be credited (Preliminary Technology's areas): set, or cleared to the programme's */
CREATE OR REPLACE FUNCTION admissions.prelim_set_target_rule(p_target uuid, p_core_subjects text[], p_min_core integer, p_reason text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target; x record; n int := 0; v_list text[];
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing the subjects of a preliminary area');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_RULES_REASON: a change to the requirements is recorded with its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = p_target FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such target' USING ERRCODE = '23503'; END IF;
    v_list := (SELECT array_agg(DISTINCT btrim(s)) FROM unnest(p_core_subjects) s WHERE btrim(s) <> '');
    IF v_list IS NOT NULL AND p_min_core IS NOT NULL AND p_min_core > cardinality(v_list) THEN
        RAISE EXCEPTION 'PRELIM_RULES_CORE: % credits cannot be asked among % subjects', p_min_core, cardinality(v_list) USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    UPDATE admissions.prelim_target SET core_subjects = v_list, min_core_credits = p_min_core WHERE id = t.id;
    UPDATE admissions.prelim_programme SET rules_version = rules_version + 1, updated_at = now() WHERE route = t.route;
    FOR x IN SELECT r.application_id FROM admissions.prelim_review r WHERE r.target_id = t.id AND r.published_at IS NULL AND r.state <> 'WITHDRAWN' LOOP
        PERFORM admissions.prelim_evaluate(x.application_id);
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;

/* an option of a target programme added, renamed, or ended (kept for the applications that chose it) */
CREATE OR REPLACE FUNCTION admissions.prelim_save_specialisation(p_target uuid, p_code text, p_name text, p_ord integer, p_active boolean, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE t admissions.prelim_target; s admissions.prelim_specialisation; v_code text := upper(btrim(coalesce(p_code, ''))); v_id uuid;
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing the specialisations of a preliminary target programme');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_SPECIALISATION_REASON: a change to the specialisations is recorded with its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = p_target;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such target' USING ERRCODE = '23503'; END IF;
    IF t.kind <> 'PROGRAMME' THEN RAISE EXCEPTION 'PRELIM_SPECIALISATION_TARGET: a certificate course has no specialisations' USING ERRCODE = '23514'; END IF;
    IF v_code !~ '^[A-Z0-9][A-Z0-9-]{0,11}$' THEN RAISE EXCEPTION 'PRELIM_SPECIALISATION_CODE: a short code of letters and digits (ACC-ED)' USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    SELECT * INTO s FROM admissions.prelim_specialisation WHERE target_id = t.id AND code = v_code FOR UPDATE;
    IF s.id IS NULL THEN
        IF nullif(btrim(coalesce(p_name, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_SPECIALISATION_NAME: a specialisation has its name' USING ERRCODE = '23514'; END IF;
        INSERT INTO admissions.prelim_specialisation (target_id, code, name, ord, active, added_by, added_office)
        VALUES (t.id, v_code, btrim(p_name), coalesce(p_ord, 100), coalesce(p_active, true),
                nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
        RETURNING id INTO v_id;
        RETURN v_id;
    END IF;
    UPDATE admissions.prelim_specialisation SET name = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name), ord = coalesce(p_ord, ord), active = coalesce(p_active, active)
     WHERE id = s.id;
    RETURN s.id;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.prelim_set_document(p_route text, p_kind text, p_label text, p_hint text, p_required boolean, p_second_only boolean, p_ord integer, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM admissions.prelim_require_office(ARRAY['academic', 'super'], 'changing a preliminary or proficiency programme''s documents');
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'PRELIM_DOCUMENT_REASON: a change to the documents is recorded with its reason' USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', p_reason, true);
    INSERT INTO admissions.prelim_document (route, kind, label, hint, required, second_sitting_only, ord)
    VALUES (upper(btrim(p_route)), upper(btrim(p_kind)), btrim(p_label), nullif(btrim(coalesce(p_hint, '')), ''), coalesce(p_required, true), coalesce(p_second_only, false), coalesce(p_ord, 100))
    ON CONFLICT (route, kind) DO UPDATE SET label = EXCLUDED.label, hint = EXCLUDED.hint, required = EXCLUDED.required,
        second_sitting_only = EXCLUDED.second_sitting_only, ord = EXCLUDED.ord;
END $fn$;

-- ── 11 · what the public, the applicant and the dashboard read ──────────────────────────────────────────────────────
/* the public page of a route: the programme, its type, campus and duration, its session and window, the fee as the Bursary stated
   it (or none), the requirements, the targets — programmes with their options and an area's subjects, or certificate courses by
   category — and the documents */
CREATE OR REPLACE FUNCTION admissions.prelim_public(p_route text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH p AS (SELECT * FROM admissions.prelim_programme WHERE route = upper(btrim(p_route))),
         s AS (SELECT policy.route_session(p.route) AS session FROM p),
         w AS (SELECT ws.* FROM p CROSS JOIN s CROSS JOIN LATERAL policy.window_state(p.window_type, s.session, NULL) ws),
         f AS (SELECT rf.* FROM p CROSS JOIN s CROSS JOIN LATERAL admissions.route_fee_rule(s.session, p.route) rf)
    SELECT jsonb_build_object(
        'route', p.route, 'name', p.name, 'programmeType', pt.label, 'programmeTypeCode', p.programme_type, 'description', p.description,
        'completionNote', p.completion_note, 'procedure', to_jsonb(p.procedure), 'officeNote', p.office_note, 'session', s.session,
        'studyMode', r.study_mode, 'office', (SELECT o.label FROM ref.office o WHERE o.code = p.office_code),
        'campus', (SELECT jsonb_build_object('code', cm.code, 'name', cm.name) FROM ref.campus cm WHERE cm.code = p.campus_code),
        'durationMonths', p.duration_months, 'certificateType', p.certificate_type, 'entryRequirement', p.entry_requirement,
        'targetWord', p.target_word, 'groupWord', p.group_word, 'targetNote', p.target_note,
        'window', jsonb_build_object('type', p.window_type, 'state', w.state, 'opensAt', w.opens_at, 'closesAt', w.closes_at,
                                     'message', (SELECT m.message FROM policy.portal_window_message m WHERE m.window_type = p.window_type)),
        'fee', jsonb_build_object('stated', coalesce((SELECT f.stated FROM f), false), 'applicationFee', (SELECT f.application_fee + f.portal_charge FROM f),
                                  'session', coalesce((SELECT f.carried_from FROM f), s.session)),
        'rules', jsonb_build_object('kind', p.rule_kind, 'minCredits', p.min_credits, 'maxSittings', p.max_sittings, 'minCoreCredits', p.min_core_credits,
                                    'coreSubjects', to_jsonb(p.core_subjects), 'coreByTarget', p.core_by_target, 'requiredSubjects', to_jsonb(p.required_subjects),
                                    'creditGrade', p.credit_grade, 'completionCredits', p.completion_credits, 'completionScope', p.completion_scope,
                                    'completionSubjects', to_jsonb(p.completion_subjects), 'awaitingAccepted', false, 'remediationTerms', p.remediation_terms,
                                    'qualifications', coalesce((SELECT jsonb_agg(jsonb_build_object('code', q.code, 'label', q.label) ORDER BY q.ord)
                                                                  FROM admissions.qualification_type q WHERE q.code = ANY (p.qualification_types) AND q.active), '[]'::jsonb)),
        'targets', coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'group', t.group_name, 'name', t.requested_name,
                                                                 'programmeCode', t.programme_code, 'registerName', pr.name, 'description', t.description,
                                                                 'durationMonths', coalesce(t.duration_months, p.duration_months),
                                                                 'coreSubjects', to_jsonb(t.core_subjects), 'minCoreCredits', coalesce(t.min_core_credits, p.min_core_credits),
                                                                 'specialisations', coalesce((SELECT jsonb_agg(jsonb_build_object('id', sp.id, 'code', sp.code, 'name', sp.name) ORDER BY sp.ord, sp.name)
                                                                                                FROM admissions.prelim_specialisation sp WHERE sp.target_id = t.id AND sp.active), '[]'::jsonb))
                                       ORDER BY t.ord, t.requested_name)
                               FROM admissions.prelim_target t LEFT JOIN ref.programme pr ON pr.code = t.programme_code
                              WHERE t.route = p.route AND t.state = 'MAPPED'), '[]'::jsonb),
        'documents', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', d.kind, 'label', d.label, 'hint', d.hint, 'required', d.required,
                                                                   'secondSittingOnly', d.second_sitting_only) ORDER BY d.ord)
                                 FROM admissions.prelim_document d WHERE d.route = p.route), '[]'::jsonb))
      FROM p CROSS JOIN s CROSS JOIN w JOIN policy.study_route r ON r.code = p.route LEFT JOIN finance.programme_type pt ON pt.code = p.programme_type
$fn$;

/* the routes the public application page offers, by programme type (Preliminary / Remedial, Proficiency certificate) */
CREATE OR REPLACE FUNCTION admissions.prelim_routes_public()
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(jsonb_agg(jsonb_build_object('route', p.route, 'name', p.name, 'programmeType', p.programme_type, 'programmeTypeLabel', pt.label,
                                                 'campus', (SELECT cm.name FROM ref.campus cm WHERE cm.code = p.campus_code),
                                                 'session', policy.route_session(p.route),
                                                 'window', (SELECT ws.state FROM policy.window_state(p.window_type, policy.route_session(p.route), NULL) ws))
                              ORDER BY pt.ord, p.name), '[]'::jsonb)
      FROM admissions.prelim_programme p LEFT JOIN finance.programme_type pt ON pt.code = p.programme_type
$fn$;

/* the dashboard's figures for a session, each the filter of the list behind it; a Head of Department or a Dean reads those whose
   target programme is in their department or faculty */
CREATE OR REPLACE FUNCTION admissions.prelim_stats(p_route text, p_session text, p_dept text DEFAULT NULL, p_faculty text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH x AS (SELECT r.*, a.fee_confirmed_at FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                 LEFT JOIN ref.programme tp ON tp.code = r.target_programme
                WHERE r.route = upper(btrim(p_route)) AND a.session = p_session
                  AND (p_dept IS NULL OR tp.dept_code = p_dept) AND (p_faculty IS NULL OR tp.faculty_code = p_faculty))
    SELECT jsonb_build_object(
        'total', (SELECT count(*) FROM x),
        'paid', (SELECT count(*) FROM x WHERE fee_confirmed_at IS NOT NULL),
        'submitted', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN'),
        'incomplete', (SELECT count(*) FROM x WHERE state = 'DRAFT'),
        'pendingReview', (SELECT count(*) FROM x WHERE state = 'SUBMITTED'),
        'underReview', (SELECT count(*) FROM x WHERE state IN ('UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED', 'APPROVED')
                                              OR (state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NULL)),
        'correction', (SELECT count(*) FROM x WHERE state = 'CORRECTION_REQUIRED'),
        'eligible', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND eligibility_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION')),
        'notEligible', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND eligibility_status IN ('NOT_ELIGIBLE', 'RESULT_REQUIRED', 'INVALID_RESULT')),
        'remediationRequired', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND remediation_status IN ('REQUIRED', 'IN_PROGRESS', 'NOT_COMPLETED', 'REQUIRES_REVIEW')),
        'admitted', (SELECT count(*) FROM x WHERE state = 'ADMITTED'),
        'notAdmitted', (SELECT count(*) FROM x WHERE state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NOT NULL),
        'withdrawn', (SELECT count(*) FROM x WHERE state = 'WITHDRAWN'),
        'byTarget', coalesce((SELECT jsonb_agg(jsonb_build_object('targetId', q.id, 'programmeCode', q.code, 'name', q.name, 'group', q.group_name, 'n', q.n) ORDER BY q.n DESC, q.name)
                                FROM (SELECT t.id, t.programme_code AS code, coalesce(p.name, t.requested_name) AS name, t.group_name, count(*) AS n
                                        FROM x JOIN admissions.prelim_target t ON t.id = x.target_id LEFT JOIN ref.programme p ON p.code = t.programme_code
                                       WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY t.id, t.programme_code, p.name, t.requested_name, t.group_name) q), '[]'::jsonb),
        'byGroup', coalesce((SELECT jsonb_agg(jsonb_build_object('group', q.group_name, 'n', q.n) ORDER BY q.n DESC, q.group_name)
                               FROM (SELECT t.group_name, count(*) AS n FROM x JOIN admissions.prelim_target t ON t.id = x.target_id
                                      WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY t.group_name) q), '[]'::jsonb),
        'bySpecialisation', coalesce((SELECT jsonb_agg(jsonb_build_object('name', q.name, 'n', q.n) ORDER BY q.n DESC, q.name)
                                        FROM (SELECT sp.name, count(*) AS n FROM x JOIN admissions.prelim_specialisation sp ON sp.id = x.specialisation_id
                                               WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY sp.name) q), '[]'::jsonb),
        'bySittings', coalesce((SELECT jsonb_agg(jsonb_build_object('sittings', s.sittings, 'n', s.n) ORDER BY s.sittings)
                                  FROM (SELECT coalesce(sittings, 0) AS sittings, count(*) AS n FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' GROUP BY 1) s), '[]'::jsonb))
$fn$;

/* the applicant's status, in the route's own terms; an unpublished decision is never shown */
CREATE OR REPLACE FUNCTION admissions.prelim_status(p_app uuid)
RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; p admissions.prelim_programme; t admissions.prelim_target; v_target text; v_spec text; v_office text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = r.target_id;
    v_target := coalesce((SELECT pr.name FROM ref.programme pr WHERE pr.code = t.programme_code), t.requested_name);
    v_spec := (SELECT sp.name FROM admissions.prelim_specialisation sp WHERE sp.id = r.specialisation_id);
    v_office := admissions.prelim_office_words(r.route);
    IF r.state = 'WITHDRAWN' THEN RETURN QUERY SELECT 'WITHDRAWN', 'Application withdrawn', NULL::text, '/applicant/preliminary', 'This application was withdrawn.'; RETURN; END IF;
    IF r.state = 'DRAFT' THEN
        RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
            CASE WHEN admissions.prelim_fee_settled(p_app) THEN 'Complete and submit your application' ELSE 'Pay the application fee' END, '/applicant/preliminary',
            initcap(left(v_office, 1)) || substr(v_office, 2) || ' reviews your application once it is complete and submitted.'; RETURN;
    END IF;
    IF r.state = 'CORRECTION_REQUIRED' THEN
        RETURN QUERY SELECT 'CORRECTION_REQUIRED', 'Correction required', 'Provide what the Office asked for', '/applicant/preliminary', r.request_note; RETURN;
    END IF;
    IF r.published_at IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/preliminary',
            'Your application is with ' || v_office || '. You are told by email and SMS when the outcome is published.'; RETURN;
    END IF;
    IF r.state = 'ADMITTED' THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted into ' || p.name, 'Print your admission letter', '/applicant/preliminary',
            'You are admitted into ' || p.name || ' for ' || a.session || '.'
            || CASE WHEN t.kind = 'COURSE' THEN coalesce(' Your certificate course is ' || v_target || '.', '')
                    ELSE coalesce(' Your intended progression is ' || v_target || coalesce(' (' || v_spec || ')', '') || '; ' || coalesce(p.target_note, ''), '') END
            || CASE WHEN r.remediation_status = 'REQUIRED' THEN ' Before completing the programme you are to make up: '
                    || array_to_string(r.remediation_subjects || CASE WHEN r.remediation_credits_short > 0 THEN ARRAY[r.remediation_credits_short || ' more O''Level credit pass(es)'] ELSE '{}' END, ', ') || '.' ELSE '' END;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'NOT_ADMITTED', 'Not admitted', NULL::text, '/applicant/preliminary',
        coalesce(a.decision_note, 'Your application for ' || p.name || ' for ' || a.session || ' was not successful.');
END $fn$;

-- ── 12 · the two routes, as the University gives them ──────────────────────────────────────────────────────────────
-- the session is the one the University named for these applications (2026/2027), as Preliminary Science's; the route register's
-- duration in years is its placeholder, never printed — Preliminary Technology's duration is not given, the courses' is nine months
INSERT INTO policy.study_route (code, name, study_mode, centre_unit, entry_level, default_duration_years, session_offset, session_override, override_reason, configured_office)
SELECT x.code, x.name, 'FULL_TIME', NULL, 0, 1, 0,
       CASE WHEN EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027') THEN '2026/2027' END,
       CASE WHEN EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027') THEN 'The University named 2026/2027 for these applications (29 October 2026)' END,
       'academic'
  FROM (VALUES ('PRELIMINARY_TECHNOLOGY', 'Preliminary Technology & Industrial Studies'),
               ('PROFICIENCY_CERTIFICATE', 'Proficiency Certificate Courses (Adikpo Campus)')) x(code, name)
ON CONFLICT (code) DO NOTHING;
INSERT INTO policy.study_route_event (route, actor, office, what, after, reason)
SELECT x.code, '00000000-0000-0000-0000-000000000000', 'academic', 'CREATED',
       jsonb_build_object('study_mode', 'FULL_TIME', 'entry_level', 0, 'session', policy.route_session(x.code)),
       'V701: ' || x.name || ', as the University''s master prompt of 29 October 2026 gives it'
  FROM (VALUES ('PRELIMINARY_TECHNOLOGY', 'Preliminary Technology & Industrial Studies'),
               ('PROFICIENCY_CERTIFICATE', 'the Adikpo Campus proficiency certificate courses')) x(code, name);

INSERT INTO admissions.prelim_programme (route, name, programme_type, description, completion_note, procedure, office_note,
                                         min_credits, max_sittings, min_core_credits, core_subjects, credit_grade, completion_credits, completion_subjects,
                                         remediation_terms, window_type, office_code, campus_code, duration_months, certificate_type, entry_requirement,
                                         rule_kind, required_subjects, core_by_target, completion_scope, qualification_types, target_word, group_word, target_note)
VALUES
('PRELIMINARY_TECHNOLOGY', 'Preliminary Technology & Industrial Studies', 'PRELIMINARY',
 'Preliminary Technology & Industrial Studies is a preliminary / remedial programme of the University. It prepares candidates for the UTME and for subsequent admission into approved programmes of the Faculty of Technology and Industrial Studies: it allows them to remedy deficiencies in their SSCE / O''Level results, gives intensive coaching towards the scores the University requires, and guides them through JAMB registration and UTME preparation. The UTME is not required for admission into the programme itself. It is not an undergraduate degree programme. The portal gives guidance on JAMB registration; it does not register candidates with JAMB.',
 'Candidates with fewer than five O''Level credit passes in the relevant subjects (English Language and the subjects of their area) are to make up the deficient subjects before being placed into their desired programme.',
 ARRAY['Open the University''s application portal and choose Preliminary Technology & Industrial Studies.',
       'Start the application (pre-registration): give your name, sex, date of birth, email and phone number. Your application number is issued at once.',
       'Print the pre-registration form where required.',
       'Pay the non-refundable application fee online with the reference the portal gives you.',
       'Once the payment is verified, return to the portal and continue the application.',
       'Complete the form: your personal details, your O''Level results (one sitting or two; an awaiting result is not accepted), your area, the programme you intend to progress to and its specialisation.',
       'Upload the documents listed on this page.',
       'Submit the application.',
       'Print the completed application form.',
       'Submit the printed form and the required copies to the Coordinator where the University requires physical submission.'],
 'Applications are reviewed by the Preliminary Vocational and Technical Education Office; the admission decision is approved and published by the Academic Office.',
 4, 2, 3, '{}', 'C6', 5, ARRAY['English Language'], NULL,
 'PRELIMINARY_TECHNOLOGY_APPLICATION', 'prelimtech', NULL, NULL, NULL,
 'A minimum of four (4) credits, including English Language, in the SSCE, GCE, NABTEB, NTC, NBC, City & Guilds Part I or II, the Federal Craft Training Certificate, TC II or another equivalent qualification approved by the University.',
 'OLEVEL_CREDITS', ARRAY['English Language'], true, 'RELEVANT', ARRAY['SSCE', 'GCE', 'NTC', 'NBC', 'CG_I', 'CG_II', 'FCTC', 'TC_II', 'OTHER'],
 'target programme', 'area',
 'Selection of a target programme under Preliminary Technology & Industrial Studies does not constitute admission into the undergraduate programme. Subsequent admission remains subject to the UTME, University requirements and applicable admission processes.'),
('PROFICIENCY_CERTIFICATE', 'Proficiency Certificate Courses (Adikpo Campus)', 'PROFICIENCY_CERTIFICATE',
 'The proficiency certificate courses of Adikpo Campus are skill-based certificate programmes of nine months, in three categories: Agricultural Technology and Consumer Science; Business Technology and Entrepreneurship Education; and Industrial Technology. They are not undergraduate degree programmes.',
 'A certificate is issued on completing the course and its requirements; none is issued before.',
 ARRAY['Open the University''s application portal and choose Proficiency Certificate (Adikpo Campus).',
       'Start the application: give your name, sex, date of birth, email and phone number. Your application number is issued at once.',
       'Pay the application fee the Bursary has set, with the reference the portal gives you.',
       'Once the payment is verified, continue the application.',
       'Choose your category and certificate course, give your personal details and the results of the secondary school certificate examination you sat.',
       'Upload the documents listed on this page.',
       'Submit the application.',
       'Print the completed application form.'],
 'Applications are reviewed by the Preliminary Vocational and Technical Education Office; the admission decision is approved and published by the Academic Office.',
 1, 2, 0, '{}', 'C6', 1, '{}', NULL,
 'PROFICIENCY_CERTIFICATE_APPLICATION', 'prelimtech', 'ADIKPO', 9, 'Proficiency Certificate',
 'An attempted Secondary School Certificate (the SSCE, GCE, NABTEB, NTC, NBC or an equivalent the University accepts) — the examination sat, its results given.',
 'ATTEMPTED_CERTIFICATE', '{}', false, 'ANY', ARRAY['SSCE', 'GCE', 'NTC', 'NBC', 'CG_I', 'CG_II', 'FCTC', 'TC_II', 'OTHER'],
 'certificate course', 'category', NULL)
ON CONFLICT (route) DO NOTHING;

INSERT INTO admissions.prelim_document (route, kind, label, hint, required, second_sitting_only, ord) VALUES
    ('PRELIMINARY_TECHNOLOGY', 'PASSPORT', 'Passport photograph (1 of 3)', 'A clear, recent JPEG photograph on a plain background.', true, false, 10),
    ('PRELIMINARY_TECHNOLOGY', 'PASSPORT_2', 'Passport photograph (2 of 3)', 'The procedure asks for three recent passport photographs (JPEG).', true, false, 20),
    ('PRELIMINARY_TECHNOLOGY', 'PASSPORT_3', 'Passport photograph (3 of 3)', 'The third recent passport photograph (JPEG).', true, false, 30),
    ('PRELIMINARY_TECHNOLOGY', 'OLEVEL_STATEMENT', 'O''Level result (first sitting)', 'The SSCE, WAEC, NECO, NABTEB, GCE or equivalent result of your first sitting.', true, false, 40),
    ('PRELIMINARY_TECHNOLOGY', 'OLEVEL_STATEMENT_2', 'O''Level result (second sitting)', 'Only when you give two sittings: the result of the second, kept apart from the first.', true, true, 50),
    ('PRELIMINARY_TECHNOLOGY', 'LGA_ID', 'Local Government Certificate of Origin', 'The certificate of origin of your local government area.', true, false, 60),
    ('PRELIMINARY_TECHNOLOGY', 'BIRTH_CERT', 'Birth certificate or declaration of age', NULL, true, false, 70),
    ('PROFICIENCY_CERTIFICATE', 'PASSPORT', 'Passport photograph', 'A clear, recent JPEG photograph on a plain background.', true, false, 10),
    ('PROFICIENCY_CERTIFICATE', 'OLEVEL_STATEMENT', 'Secondary school certificate or result (attempted)', 'The certificate or statement of result of the examination you sat.', true, false, 20),
    ('PROFICIENCY_CERTIFICATE', 'OLEVEL_STATEMENT_2', 'Secondary school result (second sitting)', 'Only when you give two sittings.', true, true, 30),
    ('PROFICIENCY_CERTIFICATE', 'LGA_ID', 'Local Government Certificate of Origin', 'If you have it.', false, false, 40),
    ('PROFICIENCY_CERTIFICATE', 'BIRTH_CERT', 'Birth certificate or declaration of age', 'If you have it.', false, false, 50)
ON CONFLICT (route, kind) DO NOTHING;

-- Preliminary Technology's three areas, each the existing programme of the register the University named (by its code, checked):
-- the area's subjects, three of which must be credited beside English Language; the programmes' options
WITH want(group_name, ord, requested_name, code, core) AS (VALUES
    ('Agricultural Technology and Consumer Science', 10, 'B.Sc. Ed. Home Economics', 'C78876',
     ARRAY['Chemistry', 'Biology', 'Agricultural Science', 'Food and Nutrition', 'Clothing and Textiles', 'Textile and Clothing', 'Economics', 'Geography']),
    ('Business Technology & Entrepreneurship Education', 20, 'B.Sc. Ed. Business Education', 'C67773',
     ARRAY['Mathematics', 'Economics', 'Financial Accounting', 'Marketing', 'Commerce', 'ICT', 'Computer Studies', 'Data Processing']),
    ('Industrial Technology', 30, 'B.Tech. Ed. Industrial Technology', 'C00096',
     ARRAY['Mathematics', 'Technical Drawing', 'Physics', 'Chemistry', 'ICT', 'Computer Studies', 'Data Processing'])),
found AS (
    SELECT w.*, (SELECT p.code FROM ref.programme p WHERE p.code = w.code AND NOT p.archived AND p.category = 'UNDER GRADUATE'
                    AND EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.ended_on IS NULL)) AS ok
      FROM want w)
INSERT INTO admissions.prelim_target (route, kind, group_name, ord, requested_name, programme_code, state, note, core_subjects, min_core_credits, added_office)
SELECT 'PRELIMINARY_TECHNOLOGY', 'PROGRAMME', f.group_name, f.ord, f.requested_name, f.ok, CASE WHEN f.ok IS NOT NULL THEN 'MAPPED' ELSE 'MISSING' END,
       CASE WHEN f.ok IS NOT NULL THEN 'Named in the University''s master prompt of 29 October 2026'
            ELSE 'MISSING TARGET PROGRAMME: ' || f.code || ' is not a current undergraduate programme on the register; the Academic Office names the one it is' END,
       f.core, 3, 'academic'
  FROM found f;

WITH want(code, spec, name, ord) AS (VALUES
    ('C67773', 'ACC-ED', 'Accounting Education', 10), ('C67773', 'ENT-ED', 'Entrepreneurship Education', 20),
    ('C67773', 'MKT-ED', 'Marketing and Distribution Education', 30), ('C67773', 'OFF-MGT', 'Office Management', 40),
    ('C00096', 'AUTO', 'Automobile Technology', 10), ('C00096', 'BLD', 'Building Technology', 20), ('C00096', 'ELECT', 'Electrical/Electronic Technology', 30),
    ('C00096', 'METAL', 'Metal Work Technology', 40), ('C00096', 'WOOD', 'Wood Work Technology', 50), ('C00096', 'RAC', 'Refrigeration and Air Conditioning', 60))
INSERT INTO admissions.prelim_specialisation (target_id, code, name, ord, added_office)
SELECT t.id, w.spec, w.name, w.ord, 'academic'
  FROM want w JOIN admissions.prelim_target t ON t.route = 'PRELIMINARY_TECHNOLOGY' AND t.programme_code = w.code
ON CONFLICT DO NOTHING;

-- the Adikpo Campus certificate courses, by category, as the University names them (never programmes of the register)
WITH want(group_name, gord, ord, name) AS (VALUES
    ('Agricultural Technology and Consumer Science', 10, 1, 'Certificate Course in Salon and Beauty Therapy'),
    ('Agricultural Technology and Consumer Science', 10, 2, 'Certificate Course in Fashion Design'),
    ('Agricultural Technology and Consumer Science', 10, 3, 'Certificate Course in Baking and Confectioneries'),
    ('Business Technology and Entrepreneurship Education', 20, 1, 'Certificate Course in Word Processing'),
    ('Business Technology and Entrepreneurship Education', 20, 2, 'Certificate Course in Computer Application'),
    ('Business Technology and Entrepreneurship Education', 20, 3, 'Certificate in Information Technology'),
    ('Business Technology and Entrepreneurship Education', 20, 4, 'Certificate in Office Management'),
    ('Business Technology and Entrepreneurship Education', 20, 5, 'Certificate in Financial Accounting'),
    ('Industrial Technology', 30, 1, 'Certificate in Auto-body Repairs, Finishing, and Maintenance'),
    ('Industrial Technology', 30, 2, 'Certificate in Automobile Repair and Maintenance'),
    ('Industrial Technology', 30, 3, 'Certificate in Auto-Electrician Work Technology'),
    ('Industrial Technology', 30, 4, 'Certificate in Vulcanizing'),
    ('Industrial Technology', 30, 5, 'Certificate in Masonry and Block Laying'),
    ('Industrial Technology', 30, 6, 'Certificate in Tiling and Land Scraping'),
    ('Industrial Technology', 30, 7, 'Certificate in Paraflex and POP'),
    ('Industrial Technology', 30, 8, 'Certificate in Domestic Wiring and Installation Practice Technology'),
    ('Industrial Technology', 30, 9, 'Certificate in Piping and Plumbing'),
    ('Industrial Technology', 30, 10, 'Certificate in AC/DC Generator/Motors Repair and Maintenance'),
    ('Industrial Technology', 30, 11, 'Certificate in Radio and Television Repairs'),
    ('Industrial Technology', 30, 12, 'Certificate in Satellite Installation and Maintenance'),
    ('Industrial Technology', 30, 13, 'Certificate in CCTV Installation and Maintenance'),
    ('Industrial Technology', 30, 14, 'Certificate in Mobile Phone Repairs'),
    ('Industrial Technology', 30, 15, 'Certificate in Electrical Power Distribution and Maintenance'),
    ('Industrial Technology', 30, 16, 'Certificate in Solar System Installations and Maintenance'),
    ('Industrial Technology', 30, 17, 'Certificate in Photography'),
    ('Industrial Technology', 30, 18, 'Certificate in Welding and Fabrication'),
    ('Industrial Technology', 30, 19, 'Certificate in Machining Technology'),
    ('Industrial Technology', 30, 20, 'Certificate in Refrigeration and Air-Conditioning Technology'),
    ('Industrial Technology', 30, 21, 'Certificate in Woodwork Technology'),
    ('Industrial Technology', 30, 22, 'Certificate in Upholstery Technology'))
INSERT INTO admissions.prelim_target (route, kind, group_name, ord, requested_name, programme_code, state, note, added_office)
SELECT 'PROFICIENCY_CERTIFICATE', 'COURSE', w.group_name, w.gord * 100 + w.ord, w.name, NULL, 'MAPPED',
       'Named in the University''s master prompt of 29 October 2026 (Adikpo Campus)', 'academic'
  FROM want w
ON CONFLICT DO NOTHING;

-- the application fee of Preliminary Technology (₦5,000, non-refundable), through the Bursary's route fees; the proficiency courses'
-- fee is not given: none is stated, and the Bursary reads FEE NOT CONFIGURED until it sets one
INSERT INTO admissions.route_fee (session, route, application_fee, portal_charge, acceptance_fee, checking_fee, stated_by, stated_office)
SELECT '2026/2027', 'PRELIMINARY_TECHNOLOGY', 5000, 0, NULL, NULL, '00000000-0000-0000-0000-000000000000', 'bursar'
 WHERE EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2026/2027')
ON CONFLICT (session, route) DO NOTHING;

-- the windows: no dates are given — closed until the Director of ICT opens them; the public reads the message meanwhile
INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office) VALUES
    ('PRELIMINARY_TECHNOLOGY_APPLICATION', 'Preliminary Technology & Industrial Studies applications are not open at present. The University announces the opening on this page.',
     '00000000-0000-0000-0000-000000000000', 'ict'),
    ('PROFICIENCY_CERTIFICATE_APPLICATION', 'Applications for the Adikpo Campus proficiency certificate courses are not open at present. The University announces the opening on this page.',
     '00000000-0000-0000-0000-000000000000', 'ict')
ON CONFLICT (window_type) DO NOTHING;

-- ── 13 · the notices, in the central templates: each route's own, in its own words (from Preliminary Science's) ──────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority)
SELECT replace(t.key, 'PRELIMINARY_SCIENCE', x.route),
       replace(replace(replace(replace(t.label, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       replace(replace(replace(replace(t.purpose, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       replace(replace(replace(replace(t.email_subject, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       replace(replace(replace(replace(t.email_body, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       replace(replace(replace(replace(t.sms_body, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       replace(replace(replace(replace(t.portal_title, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       replace(replace(replace(replace(t.portal_body, 'the Preliminary Science Programme', x.name), 'Preliminary Science Programme', x.name), 'Preliminary Science Office', x.office), 'Preliminary Science', x.name),
       t.variables, t.mandatory, t.priority
  FROM platform.notice_template t
 CROSS JOIN (VALUES ('PRELIMINARY_TECHNOLOGY', 'Preliminary Technology & Industrial Studies', 'Preliminary Vocational and Technical Education Office'),
                    ('PROFICIENCY_CERTIFICATE', 'Proficiency Certificate (Adikpo Campus)', 'Preliminary Vocational and Technical Education Office')) x(route, name, office)
 WHERE (t.key = 'PRELIMINARY_SCIENCE' OR t.key LIKE 'PRELIMINARY\_SCIENCE:%' OR t.key = 'WINDOW_CLOSING:PRELIMINARY_SCIENCE_APPLICATION')
   AND NOT (x.route = 'PROFICIENCY_CERTIFICATE' AND t.key IN ('PRELIMINARY_SCIENCE:ADMISSION_OFFERED', 'PRELIMINARY_SCIENCE:REMEDIATION_REQUIRED'))
ON CONFLICT (key) DO NOTHING;
-- a proficiency admission is into a certificate course, never an intended progression
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PROFICIENCY_CERTIFICATE:ADMISSION_OFFERED', 'Proficiency certificate admission offered', 'Sent when the Academic Office publishes an admission into a proficiency certificate course of Adikpo Campus.',
 'Admission into a proficiency certificate course (Adikpo Campus)',
 E'Dear [FIRST_NAME],\n\nCongratulations: you have been offered admission into the [TARGET_PROGRAMME] of [UNIVERSITY_NAME], Adikpo Campus, for the [SESSION] session (application [APPLICATION_NUMBER]). It is a proficiency certificate course, not a degree programme.\n\nSign in to read the offer and print your admission letter: [PORTAL_URL]\n\nPreliminary Vocational and Technical Education Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: congratulations, you are offered admission into the [TARGET_PROGRAMME], Adikpo Campus ([APPLICATION_NUMBER]). Sign in for your letter.',
 'Admission offered', 'You are offered admission into the [TARGET_PROGRAMME] (Adikpo Campus) for [SESSION].',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','SESSION','TARGET_PROGRAMME','REMEDIATION_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH')
ON CONFLICT (key) DO NOTHING;

COMMIT;
