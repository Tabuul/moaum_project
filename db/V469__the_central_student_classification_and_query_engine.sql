-- V469 — The central student classification and query engine.
--
-- Every learner the University has is classified once, from structured fields, and every
-- student list, figure and export reads that one classification:
--
--   PROGRAMME TYPE   finance.programme_type, the configurable registry V409 began for payments
--                    (UNDERGRADUATE, POSTGRADUATE, CCE, PRELIMINARY, SANDWICH, JUPEB, FOUNDATION,
--                    REMEDIAL, OTHER), now with a uuid id beside its code, the programme categories
--                    a student of the type may be on (allowed_categories), the centre its students
--                    belong to unless one is recorded (default_centre) and the offices whose student
--                    scope it is (offices). PRE_DEGREE, DIPLOMA, CERTIFICATE and PROFESSIONAL are
--                    added switched off, for the day the University runs one.
--   ADMISSION ROUTE  ref.admission_route: how the learner came in (UTME, Direct Entry, Transfer,
--                    PG application, CCE JAMB list, Sandwich, JUPEB and Preliminary applications),
--                    each read from the structured entry mode the record carries.
--   STUDY MODE       the student's own people.student.study_mode, its check widened to the modes
--                    the University may run (SANDWICH, EVENING, WEEKEND, DISTANCE_LEARNING, OTHER).
--   CENTRE           ref.centre (MAIN_CAMPUS, CCE, SANDWICH_CENTRE, ADIKPO, OTHER): the centre
--                    recorded on the student (people.student.centre_code, new, set only by the
--                    Academic Office or the Registry with a reason), else the programme type's
--                    configured centre. Never read from a department or a programme name.
--
-- A student's programme type is read first from a decision an office recorded for that student
-- (people.classification_decision), then from the entry mode, then from the programme's category —
-- the order finance.programme_type_for has used for payments since V409. It is never read from
-- a programme or department name, a matriculation or JAMB number, a username or an admission year.
-- When nothing claims the student (UNCLASSIFIED), or the type found does not admit the programme's
-- category (CONFLICTING — a POSTGRADUATE entry mode on an undergraduate programme, say), the
-- student is not counted as any type: people.student_classification says REQUIRES_CLASSIFICATION,
-- keeps what the fields propose and why, and the Academic Office or the Registry decides
-- (people.classify_student). Nothing is guessed.
--
-- people.learner is every learner in one shape, without a second student table: the register
-- (people.student, with its classification and academic position), the JUPEB learners
-- (jupeb.application from admission on) and the admitted Preliminary learners (admissions.prelim_review,
-- typed by their programme's own programme_type and shown under their target programme, never
-- as undergraduates). A learner who later joins the register keeps the earlier record: the office
-- records the progression (people.record_progression, PRELIMINARY_TO_UNDERGRADUATE or
-- JUPEB_TO_UNDERGRADUATE in people.programme_type_event) and the earlier row reads PROGRESSED.
--
-- The Sandwich Programme Office is added to the office register (44 offices): its student
-- scope is the SANDWICH type.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V469: the central student classification and query engine', true);

-- ── 1. Centres ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE ref.centre (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$'),
    name        text NOT NULL CHECK (btrim(name) <> ''),
    description text NULL,
    unit_code   text NULL REFERENCES ref.unit (code),
    ord         integer NOT NULL DEFAULT 100,
    active      boolean NOT NULL DEFAULT true,
    updated_by  uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.centre IS
  'V469: the centres a learner studies at — an explicit classification, recorded on the student or configured on the programme type, never inferred from a department';
SELECT audit.attach('ref.centre');

INSERT INTO ref.centre (code, name, description, unit_code, ord) VALUES
    ('MAIN_CAMPUS',     'Main Campus',                      'The University''s main campus', NULL, 10),
    ('CCE',             'Centre for Continuing Education',  'The Centre for Continuing Education''s part-time programmes', 'CCE', 20),
    ('SANDWICH_CENTRE', 'Sandwich Centre',                  'The Sandwich programme''s centre', 'SANDWICH_OFFICE', 30),
    ('ADIKPO',          'Adikpo',                           'The Adikpo centre', NULL, 40),
    ('OTHER',           'Other',                            'A centre not listed here', NULL, 999);

-- ── 2. Admission routes ────────────────────────────────────────────────────────────────────
CREATE TABLE ref.admission_route (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    name        text NOT NULL CHECK (btrim(name) <> ''),
    entry_mode  text NULL UNIQUE CHECK (entry_mode IS NULL OR entry_mode ~ '^[A-Z][A-Z_]{1,30}$'),
    description text NULL,
    ord         integer NOT NULL DEFAULT 100,
    active      boolean NOT NULL DEFAULT true,
    updated_by  uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.admission_route IS
  'V469: how a learner came in — read from the structured entry mode the record carries (people.student.entry_mode, or JUPEB and PRELIMINARY for the learners kept in their own applications); a route with no entry mode is set only by an office''s classification decision';
SELECT audit.attach('ref.admission_route');

INSERT INTO ref.admission_route (code, name, entry_mode, description, ord) VALUES
    ('UTME',                        'UTME',                         'UTME',         'Admitted through the Unified Tertiary Matriculation Examination', 10),
    ('DIRECT_ENTRY',                'Direct Entry',                 'DIRECT_ENTRY', 'Admitted by Direct Entry', 20),
    ('TRANSFER',                    'Transfer',                     'TRANSFER',     'Admitted by transfer from another institution', 30),
    ('INTER_DEPARTMENTAL_TRANSFER', 'Inter-departmental transfer',  NULL,           'Recorded by a classification decision; the register keeps no entry mode for it', 40),
    ('PG_APPLICATION',              'Postgraduate application',     'POSTGRADUATE', 'Admitted through the School of Postgraduate Studies'' application', 50),
    ('CCE_JAMB',                    'CCE (JAMB list)',              'CCE',          'Admitted from the JAMB CCE list to the Centre for Continuing Education', 60),
    ('SANDWICH_APPLICATION',        'Sandwich application',         'SANDWICH',     'Admitted to the Sandwich programme', 70),
    ('JUPEB_APPLICATION',           'JUPEB application',            'JUPEB',        'Admitted through the JUPEB application', 80),
    ('PRELIMINARY_APPLICATION',     'Preliminary application',      'PRELIMINARY',  'Admitted through a Preliminary programme''s application', 90);

-- ── 3. Programme types: the registry V409 began ────────────────────────────────────────────
ALTER TABLE finance.programme_type
    ADD COLUMN id                 uuid NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN allowed_categories text[] NULL,
    ADD COLUMN default_centre     text NULL REFERENCES ref.centre (code),
    ADD COLUMN offices            text[] NOT NULL DEFAULT '{}';
ALTER TABLE finance.programme_type ADD CONSTRAINT uq_programme_type_id UNIQUE (id);
COMMENT ON COLUMN finance.programme_type.id IS 'V469: the type''s identifier (the code stays the key other tables refer to)';
COMMENT ON COLUMN finance.programme_type.label IS 'the type''s name';
COMMENT ON COLUMN finance.programme_type.ord IS 'the display order';
COMMENT ON COLUMN finance.programme_type.allowed_categories IS
  'V469: the programme categories (ref.programme.category) a student of this type may be on; a register student whose programme is outside them is CONFLICTING. NULL: not checked; empty: no programme on the register (a learner kept in their own application)';
COMMENT ON COLUMN finance.programme_type.default_centre IS 'V469: the centre this type''s learners belong to unless a centre is recorded on the student';
COMMENT ON COLUMN finance.programme_type.offices IS 'V469: the offices whose student scope is this type — they see its learners only';

CREATE FUNCTION finance.programme_type_offices_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(o, ', ') INTO v_missing FROM unnest(NEW.offices) o WHERE NOT EXISTS (SELECT 1 FROM ref.office WHERE code = o);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'PROGRAMME_TYPE_OFFICE: % is not an office in the register', v_missing USING ERRCODE = '23503';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_programme_type_offices BEFORE INSERT OR UPDATE OF offices ON finance.programme_type
    FOR EACH ROW EXECUTE FUNCTION finance.programme_type_offices_guard();

INSERT INTO ref.office (code, label, scope_kind) VALUES ('sandwich', 'Sandwich Programme Office', 'unit') ON CONFLICT (code) DO NOTHING;

UPDATE finance.programme_type SET allowed_categories = ARRAY['UNDER GRADUATE'], default_centre = 'MAIN_CAMPUS' WHERE code = 'UNDERGRADUATE';
UPDATE finance.programme_type SET allowed_categories = ARRAY['POST GRADUATE'], default_centre = 'MAIN_CAMPUS', offices = ARRAY['pgschool', 'pgsecretary'] WHERE code = 'POSTGRADUATE';
UPDATE finance.programme_type SET allowed_categories = ARRAY['UNDER GRADUATE'], default_centre = 'CCE', offices = ARRAY['cce'] WHERE code = 'CCE';
UPDATE finance.programme_type SET allowed_categories = ARRAY['UNDER GRADUATE', 'POST GRADUATE'], default_centre = 'SANDWICH_CENTRE', offices = ARRAY['sandwich'] WHERE code = 'SANDWICH';
UPDATE finance.programme_type SET allowed_categories = '{}', default_centre = 'MAIN_CAMPUS', offices = ARRAY['jupeb'] WHERE code = 'JUPEB';
UPDATE finance.programme_type SET allowed_categories = '{}', default_centre = 'MAIN_CAMPUS', offices = ARRAY['prelim'] WHERE code = 'PRELIMINARY';

INSERT INTO finance.programme_type (code, label, ord, active, description) VALUES
    ('PRE_DEGREE',   'Pre-degree',   82, false, 'A pre-degree programme — switched on and mapped when the University runs one'),
    ('DIPLOMA',      'Diploma',      84, false, 'A diploma programme — switched on and mapped when the University runs one'),
    ('CERTIFICATE',  'Certificate',  86, false, 'A certificate programme — switched on and mapped when the University runs one'),
    ('PROFESSIONAL', 'Professional', 88, false, 'A professional programme — switched on and mapped when the University runs one')
ON CONFLICT (code) DO NOTHING;

-- the maps the classification reads, in the order finance.programme_type_for reads them
CREATE VIEW people.programme_type_by_entry_mode AS
SELECT DISTINCT ON (m) m AS entry_mode, t.code
  FROM finance.programme_type t CROSS JOIN LATERAL unnest(t.entry_modes) m
 WHERE t.active
 ORDER BY m, t.ord, t.code;
CREATE VIEW people.programme_type_by_category AS
SELECT DISTINCT ON (c) c AS category, t.code
  FROM finance.programme_type t CROSS JOIN LATERAL unnest(t.programme_categories) c
 WHERE t.active
 ORDER BY c, t.ord, t.code;

-- ── 4. The student's centre and study mode ─────────────────────────────────────────────────
ALTER TABLE people.student ADD COLUMN centre_code text NULL REFERENCES ref.centre (code);
COMMENT ON COLUMN people.student.centre_code IS
  'V469: the centre recorded for this student; when NULL the programme type''s configured centre applies. Set only by the Academic Office or the Registry with a reason';

ALTER TABLE people.student DROP CONSTRAINT ck_student_study_mode;
ALTER TABLE people.student ADD CONSTRAINT ck_student_study_mode
    CHECK (study_mode IN ('FULL_TIME', 'PART_TIME', 'SANDWICH', 'EVENING', 'WEEKEND', 'DISTANCE_LEARNING', 'OTHER'));

CREATE FUNCTION people.student_centre_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') <> 'on'
       AND coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'STUDENT_CENTRE_LOCKED: a student''s centre is recorded only by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), '') IS NULL THEN
        RAISE EXCEPTION 'STUDENT_CENTRE_REASON: a student''s centre is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_student_centre_guard BEFORE UPDATE OF centre_code ON people.student
    FOR EACH ROW WHEN (NEW.centre_code IS DISTINCT FROM OLD.centre_code) EXECUTE FUNCTION people.student_centre_guard();

-- ── 5. Decisions and history ───────────────────────────────────────────────────────────────
CREATE TABLE people.classification_decision (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    programme_type  text NOT NULL REFERENCES finance.programme_type (code),
    admission_route text NULL REFERENCES ref.admission_route (code),
    reason          text NOT NULL CHECK (btrim(reason) <> ''),
    decided_by      uuid NULL,
    decided_office  text NULL REFERENCES ref.office (code),
    decided_at      timestamptz NOT NULL DEFAULT now(),
    superseded_at   timestamptz NULL
);
CREATE UNIQUE INDEX ux_classification_decision_current ON people.classification_decision (student_id) WHERE superseded_at IS NULL;
COMMENT ON TABLE people.classification_decision IS
  'V469: an office''s decision of a student''s programme type (and admission route), which the classification reads before any field; a later decision supersedes it and both are kept';
SELECT audit.attach('people.classification_decision');

CREATE TABLE people.programme_type_event (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id           uuid NULL REFERENCES people.student (id) ON DELETE CASCADE,
    jupeb_application_id uuid NULL REFERENCES jupeb.application (id) ON DELETE CASCADE,
    application_id       uuid NULL REFERENCES admissions.application (id) ON DELETE CASCADE,
    event                text NOT NULL CHECK (event IN ('CORRECTION', 'PROGRESSION')),
    kind                 text NOT NULL CHECK (kind ~ '^[A-Z_]{3,80}$'),
    from_type            text NULL REFERENCES finance.programme_type (code),
    to_type              text NOT NULL REFERENCES finance.programme_type (code),
    reason               text NOT NULL CHECK (btrim(reason) <> ''),
    at                   timestamptz NOT NULL DEFAULT now(),
    by_person            uuid NULL,
    by_office            text NULL REFERENCES ref.office (code),
    CONSTRAINT ck_programme_type_event_subject CHECK (num_nonnulls(student_id, jupeb_application_id, application_id) >= 1),
    CONSTRAINT ck_programme_type_event_progression CHECK (event <> 'PROGRESSION' OR (student_id IS NOT NULL AND num_nonnulls(jupeb_application_id, application_id) = 1))
);
CREATE INDEX ix_programme_type_event_student ON people.programme_type_event (student_id) WHERE student_id IS NOT NULL;
CREATE UNIQUE INDEX ux_programme_type_event_jupeb ON people.programme_type_event (jupeb_application_id) WHERE event = 'PROGRESSION';
CREATE UNIQUE INDEX ux_programme_type_event_application ON people.programme_type_event (application_id) WHERE event = 'PROGRESSION';
COMMENT ON TABLE people.programme_type_event IS
  'V469: a learner''s programme-type history — each correction, and each progression from an earlier record (PRELIMINARY_TO_UNDERGRADUATE, JUPEB_TO_UNDERGRADUATE), which leaves the earlier record in place';
SELECT audit.attach('people.programme_type_event');

-- ── 6. The classification of every student on the register ─────────────────────────────────
CREATE VIEW people.student_classification AS
SELECT s.id AS student_id,
       CASE WHEN k.issue IS NULL THEN k.type END AS programme_type,
       k.type AS proposed_type,
       k.source AS type_source,
       CASE WHEN k.issue IS NULL THEN 'CLASSIFIED' ELSE 'REQUIRES_CLASSIFICATION' END AS classification_status,
       k.issue AS classification_issue,
       CASE k.issue
           WHEN 'UNCLASSIFIED' THEN format('No programme type claims entry mode %s or the programme category %s', s.entry_mode, coalesce(p.category, 'not stated'))
           WHEN 'CONFLICTING' THEN format('Entry mode %s reads as %s, but %s (%s) is %s', s.entry_mode, t.label, p.name, p.code, coalesce(p.category, 'a programme without a category'))
       END AS classification_note,
       coalesce(d.admission_route, r.code) AS admission_route,
       s.study_mode,
       coalesce(s.centre_code, t.default_centre) AS centre_code,
       CASE WHEN s.centre_code IS NOT NULL THEN 'RECORDED' WHEN t.default_centre IS NOT NULL THEN 'PROGRAMME_TYPE' END AS centre_source,
       coalesce(t.study_mode IS NOT NULL AND s.study_mode <> t.study_mode, false) AS study_mode_differs,
       d.id AS decision_id
  FROM people.student s
  JOIN ref.programme p ON p.code = s.programme_code
  LEFT JOIN people.classification_decision d ON d.student_id = s.id AND d.superseded_at IS NULL
  LEFT JOIN people.programme_type_by_entry_mode be ON be.entry_mode = upper(s.entry_mode)
  LEFT JOIN people.programme_type_by_category bc ON bc.category = upper(p.category)
  LEFT JOIN finance.programme_type t ON t.code = coalesce(d.programme_type, be.code, bc.code)
  LEFT JOIN ref.admission_route r ON r.entry_mode = upper(s.entry_mode) AND r.active
  CROSS JOIN LATERAL (
      SELECT coalesce(d.programme_type, be.code, bc.code) AS type,
             CASE WHEN d.id IS NOT NULL THEN 'DECISION' WHEN be.code IS NOT NULL THEN 'ENTRY_MODE' WHEN bc.code IS NOT NULL THEN 'PROGRAMME_CATEGORY' END AS source,
             CASE WHEN d.id IS NOT NULL THEN NULL
                  WHEN coalesce(be.code, bc.code) IS NULL THEN 'UNCLASSIFIED'
                  WHEN t.allowed_categories IS NOT NULL AND NOT (upper(coalesce(p.category, '')) = ANY (t.allowed_categories)) THEN 'CONFLICTING'
             END AS issue
  ) k;
COMMENT ON VIEW people.student_classification IS
  'V469: each register student''s programme type, admission route, study mode and centre, read from an office''s decision, the entry mode and the programme category — never from a name or a number; a student nothing claims, or whose type does not admit the programme''s category, REQUIRES_CLASSIFICATION and is counted as no type';

-- ── 7. Every learner in one shape ──────────────────────────────────────────────────────────
CREATE VIEW people.learner AS
SELECT 'REGISTER'::text AS source, s.id AS learner_id, s.id AS student_id,
       s.surname, s.other_names, s.sex,
       s.matric_no, s.jamb_reg_no AS jamb_no, s.admission_no, coalesce(a.application_no, pa.application_no) AS application_no,
       c.programme_type, c.proposed_type, c.type_source, c.classification_status, c.classification_issue, c.classification_note,
       c.admission_route, c.study_mode, c.centre_code, c.study_mode_differs,
       f.code AS faculty_code, f.name AS faculty, f.college_code, d.code AS dept_code, d.name AS department,
       p.code AS programme_code, p.name AS programme, p.category AS programme_category, nullif(btrim(p.pg_award), '') AS pg_award,
       false AS programme_is_target,
       s.current_level AS level, s.entry_session AS admission_session, coalesce(ap.current_session, cur.name) AS current_session,
       s.status, s.matriculated_at,
       CASE WHEN s.entry_session ~ '^[0-9]{4}/[0-9]{4}$' THEN left(s.entry_session, 4)::int END AS entry_year,
       ap.matric_year, ap.jamb_year,
       ap.spillover_state, coalesce(ap.final_level IS NOT NULL AND s.current_level >= ap.final_level, false) AS final_year,
       ap.graduation_state,
       NULL::text AS application_status, NULL::text AS admission_status,
       NULL::uuid AS jupeb_combination_id, NULL::text AS jupeb_combination, NULL::uuid[] AS jupeb_subjects, NULL::boolean AS jupeb_registered,
       NULL::text AS prelim_route, NULL::text AS prelim_name
  FROM people.student s
  JOIN people.student_classification c ON c.student_id = s.id
  JOIN ref.programme p ON p.code = s.programme_code
  JOIN ref.department d ON d.code = p.dept_code
  JOIN ref.faculty f ON f.code = p.faculty_code
  LEFT JOIN people.academic_position ap ON ap.student_id = s.id
  CROSS JOIN (SELECT policy.university_current_session() AS name) cur
  LEFT JOIN admissions.application a ON a.candidate_id = s.candidate_id
  LEFT JOIN (SELECT DISTINCT ON (x.student_id) x.student_id, x.application_no
               FROM admissions.pg_application x WHERE x.student_id IS NOT NULL
              ORDER BY x.student_id, x.created_at DESC) pa ON pa.student_id = s.id
 WHERE s.duplicate_of IS NULL
UNION ALL
SELECT 'JUPEB', j.id, NULL::uuid,
       j.surname, concat_ws(' ', j.first_name, nullif(btrim(j.middle_name), '')), j.sex,
       NULL::text, NULL::text, j.admission_ref, j.application_no,
       be.code, be.code, CASE WHEN be.code IS NOT NULL THEN 'ENTRY_MODE' END,
       CASE WHEN be.code IS NULL THEN 'REQUIRES_CLASSIFICATION' ELSE 'CLASSIFIED' END,
       CASE WHEN be.code IS NULL THEN 'UNCLASSIFIED' END,
       CASE WHEN be.code IS NULL THEN 'No programme type claims the JUPEB entry mode' END,
       r.code, t.study_mode, t.default_centre, false,
       NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
       NULL::text, NULL::text, NULL::text, NULL::text,
       false,
       NULL::int, j.session, j.session,
       CASE WHEN pe.id IS NOT NULL THEN 'PROGRESSED'
            ELSE CASE j.state WHEN 'STUDENT' THEN 'ACTIVE' ELSE j.state END END,
       NULL::timestamptz,
       left(j.session, 4)::int, NULL::int, NULL::int,
       NULL::text, false, NULL::text,
       j.state, 'ADMITTED',
       j.combination_id, cb.code || ' — ' || cb.name, CASE WHEN cb.id IS NOT NULL THEN ARRAY[cb.subject1, cb.subject2, cb.subject3] END,
       (j.subjects_registered_at IS NOT NULL),
       NULL::text, NULL::text
  FROM jupeb.application j
  LEFT JOIN jupeb.combination cb ON cb.id = j.combination_id
  LEFT JOIN people.programme_type_by_entry_mode be ON be.entry_mode = 'JUPEB'
  LEFT JOIN finance.programme_type t ON t.code = be.code
  LEFT JOIN ref.admission_route r ON r.entry_mode = 'JUPEB' AND r.active
  LEFT JOIN people.programme_type_event pe ON pe.jupeb_application_id = j.id AND pe.event = 'PROGRESSION'
 WHERE j.state IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED') OR (j.state = 'WITHDRAWN' AND j.activated_at IS NOT NULL)
UNION ALL
SELECT 'PRELIMINARY', a.id, NULL::uuid,
       cd.surname, cd.other_names, cd.sex,
       NULL::text, cd.jamb_reg_no, cd.admission_no, a.application_no,
       t.code, t.code, 'PRELIMINARY_PROGRAMME', 'CLASSIFIED', NULL::text, NULL::text,
       r.code, sr.study_mode, coalesce(ce.code, t.default_centre), false,
       f.code, f.name, f.college_code, d.code, d.name,
       p.code, p.name, p.category, NULL::text,
       true,
       NULL::int, a.session, a.session,
       CASE WHEN pe.id IS NOT NULL THEN 'PROGRESSED' ELSE 'ADMITTED' END,
       NULL::timestamptz,
       CASE WHEN a.session ~ '^[0-9]{4}/[0-9]{4}$' THEN left(a.session, 4)::int END, NULL::int, NULL::int,
       NULL::text, false, NULL::text,
       pr.state, cd.offer_state,
       NULL::uuid, NULL::text, NULL::uuid[], NULL::boolean,
       pr.route, pp.name
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
  LEFT JOIN ref.admission_route r ON r.entry_mode = 'PRELIMINARY' AND r.active
  LEFT JOIN people.programme_type_event pe ON pe.application_id = a.id AND pe.event = 'PROGRESSION'
 WHERE pr.state = 'ADMITTED';
COMMENT ON VIEW people.learner IS
  'V469: every learner in one shape — the register with its classification and academic position, the JUPEB learners from admission on, and the admitted Preliminary learners under their target programme (typed PRELIMINARY by their programme, never undergraduate); merged duplicates left out; the one source of every student query, figure and export';

-- ── 8. An office's decision, and a progression recorded ────────────────────────────────────
CREATE FUNCTION people.require_classifier(p_doing text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF coalesce(v_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'CLASSIFICATION_OFFICE: % is for the Academic Office or the Registry', p_doing USING ERRCODE = '42501';
    END IF;
    RETURN v_office;
END $$;

CREATE FUNCTION people.classify_student(p_student uuid, p_type text, p_route text, p_centre text, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_office text := people.require_classifier('deciding a student''s programme type');
    v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
    v_before record;
    v_id     uuid;
BEGIN
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'CLASSIFICATION_REASON: a classification decision is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    SELECT c.programme_type, c.proposed_type, s.centre_code INTO v_before
      FROM people.student s JOIN people.student_classification c ON c.student_id = s.id WHERE s.id = p_student;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CLASSIFICATION_STUDENT: no such student' USING ERRCODE = 'P0002';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.programme_type WHERE code = p_type AND active) THEN
        RAISE EXCEPTION 'CLASSIFICATION_TYPE: % is not a programme type in use', coalesce(p_type, 'nothing') USING ERRCODE = '23514';
    END IF;
    IF p_type IN (SELECT code FROM finance.programme_type WHERE allowed_categories = '{}') THEN
        RAISE EXCEPTION 'CLASSIFICATION_TYPE: a % learner is kept in their own application, not on the register — record the progression instead', p_type USING ERRCODE = '23514';
    END IF;
    IF p_route IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ref.admission_route WHERE code = p_route AND active) THEN
        RAISE EXCEPTION 'CLASSIFICATION_ROUTE: % is not an admission route in use', p_route USING ERRCODE = '23514';
    END IF;
    IF p_centre IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ref.centre WHERE code = p_centre AND active) THEN
        RAISE EXCEPTION 'CLASSIFICATION_CENTRE: % is not a centre in use', p_centre USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('moaum.reason', v_reason, true);
    UPDATE people.classification_decision SET superseded_at = now() WHERE student_id = p_student AND superseded_at IS NULL;
    INSERT INTO people.classification_decision (student_id, programme_type, admission_route, reason, decided_by, decided_office)
    VALUES (p_student, p_type, p_route, v_reason, v_actor, v_office)
    RETURNING id INTO v_id;
    IF p_centre IS NOT NULL AND p_centre IS DISTINCT FROM v_before.centre_code THEN
        UPDATE people.student SET centre_code = p_centre WHERE id = p_student;
    END IF;
    INSERT INTO people.programme_type_event (student_id, event, kind, from_type, to_type, reason, by_person, by_office)
    VALUES (p_student, 'CORRECTION', 'CORRECTION', coalesce(v_before.programme_type, v_before.proposed_type), p_type, v_reason, v_actor, v_office);
    RETURN v_id;
END $$;
COMMENT ON FUNCTION people.classify_student(uuid, text, text, text, text) IS
  'V469: the Academic Office or the Registry decides a register student''s programme type (with the admission route and centre where known), with a reason; the decision supersedes any earlier one, which is kept, and the change is on the student''s programme-type history';

CREATE FUNCTION people.record_progression(p_student uuid, p_source text, p_application_no text, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_office  text := people.require_classifier('recording a learner''s progression');
    v_actor   uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_reason  text := nullif(btrim(coalesce(p_reason, '')), '');
    v_student record;
    v_from    text;
    v_surname text;
    v_jupeb   uuid;
    v_app     uuid;
    v_id      uuid;
BEGIN
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'PROGRESSION_REASON: a progression is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    SELECT s.surname, c.programme_type INTO v_student
      FROM people.student s JOIN people.student_classification c ON c.student_id = s.id WHERE s.id = p_student;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PROGRESSION_STUDENT: no such student' USING ERRCODE = 'P0002';
    END IF;
    IF v_student.programme_type IS NULL THEN
        RAISE EXCEPTION 'PROGRESSION_UNCLASSIFIED: the student''s own programme type is decided first' USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_source, '')) = 'JUPEB' THEN
        SELECT j.id, j.surname, be.code INTO v_jupeb, v_surname, v_from
          FROM jupeb.application j LEFT JOIN people.programme_type_by_entry_mode be ON be.entry_mode = 'JUPEB'
         WHERE upper(j.application_no) = upper(btrim(p_application_no)) AND j.state IN ('ADMITTED', 'STUDENT', 'COMPLETED');
        IF v_jupeb IS NULL THEN
            RAISE EXCEPTION 'PROGRESSION_SOURCE: no admitted JUPEB learner has application number %', p_application_no USING ERRCODE = 'P0002';
        END IF;
    ELSIF upper(coalesce(p_source, '')) = 'PRELIMINARY' THEN
        SELECT a.id, cd.surname, pp.programme_type INTO v_app, v_surname, v_from
          FROM admissions.application a
          JOIN admissions.prelim_review pr ON pr.application_id = a.id AND pr.state = 'ADMITTED'
          JOIN admissions.prelim_programme pp ON pp.route = pr.route
          JOIN admissions.candidate cd ON cd.id = a.candidate_id
         WHERE upper(a.application_no) = upper(btrim(p_application_no));
        IF v_app IS NULL THEN
            RAISE EXCEPTION 'PROGRESSION_SOURCE: no admitted Preliminary learner has application number %', p_application_no USING ERRCODE = 'P0002';
        END IF;
    ELSE
        RAISE EXCEPTION 'PROGRESSION_SOURCE: a progression is from a JUPEB or a Preliminary record' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(v_surname)) <> upper(btrim(v_student.surname)) THEN
        RAISE EXCEPTION 'PROGRESSION_NAME: the earlier record is in another surname (%), not this student''s (%)', v_surname, v_student.surname USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM people.programme_type_event WHERE event = 'PROGRESSION' AND (jupeb_application_id = v_jupeb OR application_id = v_app)) THEN
        RAISE EXCEPTION 'PROGRESSION_RECORDED: that earlier record''s progression is already recorded' USING ERRCODE = '23505';
    END IF;
    INSERT INTO people.programme_type_event (student_id, jupeb_application_id, application_id, event, kind, from_type, to_type, reason, by_person, by_office)
    VALUES (p_student, v_jupeb, v_app, 'PROGRESSION', coalesce(v_from, 'OTHER') || '_TO_' || v_student.programme_type,
            v_from, v_student.programme_type, v_reason, v_actor, v_office)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION people.record_progression(uuid, text, text, text) IS
  'V469: a JUPEB or Preliminary learner who joined the register: the earlier record stays (it reads PROGRESSED) and the progression is on the programme-type history, from the earlier type to the student''s own';

COMMIT;
