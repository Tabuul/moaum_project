-- ═══════════════════════════════════════════════════════════════════════════
-- V254 — external examiners of final-year projects
--
--   The University appoints an examiner from outside — a scholar of another
--   institution — for a session, a faculty, a department and a programme, and
--   sends them a project to assess independently: the student's final-year
--   project (undergraduate), or a postgraduate's project report, dissertation
--   or thesis already on the School's research record (V209). The examiner is
--   invited by email, activates an account through a link that works once and
--   expires, signs in at the one door as everyone does, and sees a workspace of
--   their own: the projects assigned to them, the documents released for
--   external examination, and an assessment form the University configures —
--   criteria with maximum marks, in sections (the written work, the defence).
--   The total is computed, never typed; the grade is the University's own
--   grading scheme in force (policy.grade_of). A draft is saved and continued;
--   a submission locks the assessment; only the desk reopens it, on a reason.
--   Nothing here touches an official result: the assessment is a record the
--   department reads at moderation, under the existing results workflow.
--
--   The office extexaminer is held by the examiner's own person row (no staff
--   number). Every table is on the audit spine; the module keeps its own
--   history besides, written once. Reference data — student, programme,
--   department, faculty, session, the PG research record, the roster of PG
--   examiners (V213) — is referenced, never copied.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'external examiners (V254)', true);

INSERT INTO ref.office (code, label, scope_kind) VALUES ('extexaminer', 'External Examiner', 'institution')
ON CONFLICT (code) DO NOTHING;

CREATE SCHEMA IF NOT EXISTS extexam;
COMMENT ON SCHEMA extexam IS 'External examiners of final-year projects (V254): who they are, their appointments, the projects sent to them, the documents released, and their assessments.';

-- ── the examiner ─────────────────────────────────────────────────────────────
CREATE TABLE extexam.examiner (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id        uuid NOT NULL UNIQUE REFERENCES iam.person(id),
    pg_examiner_id   uuid NULL REFERENCES admissions.pg_examiner(id),
    title            text NULL,
    email            text NOT NULL UNIQUE,
    phone            text NULL,
    institution      text NOT NULL,
    department       text NULL,
    rank             text NULL,
    specialization   text NULL,
    qualification    text NULL,
    professional     text NULL,
    experience_years int NULL,
    country          text NULL,
    region           text NULL,
    orcid            text NULL,
    status           text NOT NULL DEFAULT 'INVITED',
    notes            text NULL,
    created_by       uuid NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    activated_at     timestamptz NULL,
    CONSTRAINT ck_ee_email CHECK (email = lower(btrim(email)) AND email ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$'),
    CONSTRAINT ck_ee_status CHECK (status IN ('INVITED','PENDING_ACTIVATION','ACTIVE','SUSPENDED','INACTIVE')),
    CONSTRAINT ck_ee_experience CHECK (experience_years IS NULL OR experience_years BETWEEN 0 AND 70),
    CONSTRAINT ck_ee_institution CHECK (btrim(institution) <> '')
);
SELECT audit.attach('extexam.examiner');
COMMENT ON TABLE extexam.examiner IS 'An external examiner: their person row carries the name and the login; this row carries what the appointment letter needs. Deactivated, never deleted.';

-- the examiner's CV or academic profile, kept apart from its record
CREATE TABLE extexam.examiner_file (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    examiner_id  uuid NOT NULL REFERENCES extexam.examiner(id),
    kind         text NOT NULL,
    filename     text NOT NULL,
    content_type text NOT NULL,
    bytes        bigint NOT NULL,
    uploaded_by  uuid NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ee_file_kind CHECK (kind IN ('CV','PHOTO')),
    CONSTRAINT ck_ee_file_type CHECK (content_type IN ('application/pdf','image/jpeg','image/png')),
    CONSTRAINT ck_ee_file_size CHECK (bytes BETWEEN 1 AND 5242880)
);
SELECT audit.attach('extexam.examiner_file');
CREATE TABLE extexam.examiner_file_blob (file_id uuid PRIMARY KEY REFERENCES extexam.examiner_file(id), content bytea NOT NULL);
SELECT audit.exempt('extexam.examiner_file_blob', 'The bytes of an examiner''s CV or photo; the file row on the spine records who put it there.');

-- ── the invitation: a token kept only as a hash, good for a fortnight, spent once ──
CREATE TABLE extexam.invitation (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    examiner_id  uuid NOT NULL REFERENCES extexam.examiner(id),
    token_hash   text NOT NULL,
    sent_by      uuid NULL,
    sent_at      timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    used_at      timestamptz NULL
);
CREATE INDEX ix_ee_invitation_token ON extexam.invitation (token_hash);
CREATE INDEX ix_ee_invitation_examiner ON extexam.invitation (examiner_id, sent_at DESC);
SELECT audit.exempt('extexam.invitation', 'Holds an activation token hash and nothing that changes the record; the activation it authorises is on the spine (the examiner row and iam.credential_event).');

-- ── the appointment: a session, a unit, a period ─────────────────────────────
CREATE TABLE extexam.appointment (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    examiner_id    uuid NOT NULL REFERENCES extexam.examiner(id),
    session        text NOT NULL,
    semester       int NULL,
    faculty_code   text NOT NULL REFERENCES ref.faculty(code),
    dept_code      text NOT NULL REFERENCES ref.department(code),
    programme_code text NULL REFERENCES ref.programme(code),
    period         text NULL,
    starts_on      date NOT NULL,
    ends_on        date NOT NULL,
    status         text NOT NULL DEFAULT 'ACTIVE',
    instrument     text NULL,
    appointed_by   uuid NULL,
    appointed_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ee_appt_dates CHECK (ends_on >= starts_on),
    CONSTRAINT ck_ee_appt_semester CHECK (semester IS NULL OR semester IN (1,2,3)),
    CONSTRAINT ck_ee_appt_status CHECK (status IN ('ACTIVE','ENDED','SUSPENDED'))
);
CREATE INDEX ix_ee_appt_examiner ON extexam.appointment (examiner_id, session);
CREATE INDEX ix_ee_appt_unit ON extexam.appointment (session, dept_code);
SELECT audit.attach('extexam.appointment');

-- ── the project sent for external examination ────────────────────────────────
CREATE TABLE extexam.project (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid NOT NULL REFERENCES people.student(id),
    kind            text NOT NULL,
    pg_research_id  uuid NULL REFERENCES admissions.pg_research(id),
    course_code     text NULL REFERENCES catalogue.course(code),
    session         text NOT NULL,
    title           text NOT NULL,
    abstract        text NULL,
    keywords        text NULL,
    project_type    text NULL,
    submitted_on    date NULL,
    supervisor_id   uuid NULL REFERENCES iam.person(id),
    supervisor_name text NULL,
    co_supervisor   text NULL,
    created_by      uuid NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ee_project_kind CHECK (kind IN ('UNDERGRADUATE','POSTGRADUATE')),
    CONSTRAINT ck_ee_project_title CHECK (btrim(title) <> ''),
    CONSTRAINT uq_ee_project UNIQUE (student_id, session)
);
CREATE INDEX ix_ee_project_student ON extexam.project (student_id);
SELECT audit.attach('extexam.project');
COMMENT ON TABLE extexam.project IS 'One final-year project per student per session: the undergraduate project as the department registers it here, or the postgraduate research record (V209) referenced. What the examiner reads about the work.';

-- the documents released for external examination — and only those
CREATE TABLE extexam.project_document (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   uuid NOT NULL REFERENCES extexam.project(id),
    kind         text NOT NULL,
    filename     text NOT NULL,
    content_type text NOT NULL,
    bytes        bigint NOT NULL,
    released     boolean NOT NULL DEFAULT true,
    uploaded_by  uuid NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ee_doc_kind CHECK (kind IN ('PROPOSAL','REPORT','SOURCE','PRESENTATION','SUPPORTING')),
    CONSTRAINT ck_ee_doc_type CHECK (content_type IN ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                                      'application/vnd.openxmlformats-officedocument.presentationml.presentation','application/zip')),
    CONSTRAINT ck_ee_doc_size CHECK (bytes BETWEEN 1 AND 26214400),
    CONSTRAINT ck_ee_doc_name CHECK (btrim(filename) <> '' AND length(filename) <= 200)
);
CREATE INDEX ix_ee_doc_project ON extexam.project_document (project_id, kind);
SELECT audit.attach('extexam.project_document');
CREATE TABLE extexam.project_document_blob (document_id uuid PRIMARY KEY REFERENCES extexam.project_document(id), content bytea NOT NULL);
SELECT audit.exempt('extexam.project_document_blob', 'The bytes of a project document; the document row on the spine records who released it and when.');

-- ── the assessment form the University configures ────────────────────────────
CREATE TABLE extexam.rubric (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE,
    name        text NOT NULL,
    kind        text NOT NULL,
    active      boolean NOT NULL DEFAULT true,
    has_defence boolean NOT NULL DEFAULT true,
    note        text NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ee_rubric_kind CHECK (kind IN ('UNDERGRADUATE','POSTGRADUATE'))
);
SELECT audit.attach('extexam.rubric');

CREATE TABLE extexam.criterion (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rubric_id uuid NOT NULL REFERENCES extexam.rubric(id),
    section   text NOT NULL,
    name      text NOT NULL,
    guidance  text NULL,
    max_score numeric(5,1) NOT NULL,
    ordinal   int NOT NULL,
    active    boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_ee_criterion_section CHECK (section IN ('WRITTEN','DEFENCE')),
    CONSTRAINT ck_ee_criterion_max CHECK (max_score > 0 AND max_score <= 100),
    CONSTRAINT ck_ee_criterion_name CHECK (btrim(name) <> '')
);
CREATE INDEX ix_ee_criterion_rubric ON extexam.criterion (rubric_id, ordinal);
SELECT audit.attach('extexam.criterion');
COMMENT ON TABLE extexam.criterion IS 'A line of the assessment form: its section, its maximum. A criterion is deactivated rather than deleted, so an assessment scored on it still reads.';

-- ── the assignment: a project to an examiner, under an appointment, by a deadline ──
CREATE TABLE extexam.assignment (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      uuid NOT NULL REFERENCES extexam.project(id),
    examiner_id     uuid NOT NULL REFERENCES extexam.examiner(id),
    appointment_id  uuid NULL REFERENCES extexam.appointment(id),
    rubric_id       uuid NOT NULL REFERENCES extexam.rubric(id),
    deadline        date NOT NULL,
    exam_date       date NULL,
    status          text NOT NULL DEFAULT 'ASSIGNED',
    assigned_by     uuid NULL,
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    first_viewed_at timestamptz NULL,
    ended_at        timestamptz NULL,
    ended_reason    text NULL,
    replaced_by     uuid NULL REFERENCES extexam.assignment(id),
    reminded_at     timestamptz NULL,
    overdue_told_at timestamptz NULL,
    CONSTRAINT ck_ee_asg_status CHECK (status IN ('ASSIGNED','IN_REVIEW','SUBMITTED','LOCKED','REOPENED','REASSIGNED','WITHDRAWN')),
    CONSTRAINT ck_ee_asg_ended CHECK ((status IN ('REASSIGNED','WITHDRAWN')) = (ended_at IS NOT NULL))
);
CREATE UNIQUE INDEX uq_ee_asg_live ON extexam.assignment (project_id, examiner_id) WHERE ended_at IS NULL;
CREATE INDEX ix_ee_asg_examiner ON extexam.assignment (examiner_id, status);
CREATE INDEX ix_ee_asg_project ON extexam.assignment (project_id);
SELECT audit.attach('extexam.assignment');
COMMENT ON TABLE extexam.assignment IS 'A project may go to more than one examiner; each assignment, and its assessment, stands on its own. A reassignment ends this row and names the one that replaced it.';

-- ── the assessment: one per assignment, drafted, submitted, locked, reopened ──
CREATE TABLE extexam.assessment (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id        uuid NOT NULL UNIQUE REFERENCES extexam.assignment(id),
    state                text NOT NULL DEFAULT 'DRAFT',
    total                numeric(6,1) NULL,
    max_total            numeric(6,1) NULL,
    percentage           numeric(5,1) NULL,
    grade                text NULL,
    general_comments     text NULL,
    strengths            text NULL,
    weaknesses           text NULL,
    recommendations      text NULL,
    corrections          text NULL,
    final_recommendation text NULL,
    version              int NOT NULL DEFAULT 1,
    started_at           timestamptz NOT NULL DEFAULT now(),
    saved_at             timestamptz NOT NULL DEFAULT now(),
    submitted_at         timestamptz NULL,
    locked_at            timestamptz NULL,
    locked_by            uuid NULL,
    reopened_at          timestamptz NULL,
    reopened_by          uuid NULL,
    reopen_reason        text NULL,
    CONSTRAINT ck_ee_ass_state CHECK (state IN ('DRAFT','SUBMITTED','LOCKED','REOPENED')),
    CONSTRAINT ck_ee_ass_recommendation CHECK (final_recommendation IS NULL OR final_recommendation IN ('PASS','PASS_WITH_CORRECTIONS','REASSESSMENT','FAIL')),
    CONSTRAINT ck_ee_ass_submitted CHECK (state NOT IN ('SUBMITTED','LOCKED') OR (submitted_at IS NOT NULL AND total IS NOT NULL AND final_recommendation IS NOT NULL))
);
SELECT audit.attach('extexam.assessment');

CREATE TABLE extexam.assessment_score (
    assessment_id uuid NOT NULL REFERENCES extexam.assessment(id),
    criterion_id  uuid NOT NULL REFERENCES extexam.criterion(id),
    score         numeric(5,1) NULL,
    comment       text NULL,
    PRIMARY KEY (assessment_id, criterion_id),
    CONSTRAINT ck_ee_score_range CHECK (score IS NULL OR score >= 0)
);
SELECT audit.attach('extexam.assessment_score');

-- ── the module's own history, written once ───────────────────────────────────
CREATE TABLE extexam.event (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at            timestamptz NOT NULL DEFAULT now(),
    actor_id      uuid NULL,
    actor_office  text NULL,
    actor_name    text NOT NULL,
    action        text NOT NULL,
    examiner_id   uuid NULL REFERENCES extexam.examiner(id),
    project_id    uuid NULL REFERENCES extexam.project(id),
    assignment_id uuid NULL REFERENCES extexam.assignment(id),
    from_value    text NULL,
    to_value      text NULL,
    reason        text NULL,
    CONSTRAINT ck_ee_event_action CHECK (action IN ('EXAMINER_CREATED','EXAMINER_EDITED','EXAMINER_INVITED','INVITATION_RESENT','ACCOUNT_ACTIVATED','EXAMINER_STATUS',
        'APPOINTED','APPOINTMENT_ENDED','PROJECT_CREATED','PROJECT_EDITED','DOCUMENT_RELEASED','DOCUMENT_WITHDRAWN','PROJECT_ASSIGNED','PROJECT_REASSIGNED','ASSIGNMENT_WITHDRAWN',
        'DEADLINE_CHANGED','PROJECT_VIEWED','ASSESSMENT_STARTED','ASSESSMENT_SAVED','ASSESSMENT_SUBMITTED','ASSESSMENT_LOCKED','ASSESSMENT_REOPENED','ASSESSMENT_RESUBMITTED'))
);
CREATE INDEX ix_ee_event_assignment ON extexam.event (assignment_id, at);
CREATE INDEX ix_ee_event_examiner ON extexam.event (examiner_id, at);
CREATE INDEX ix_ee_event_project ON extexam.event (project_id, at);
SELECT audit.attach('extexam.event');

CREATE OR REPLACE FUNCTION extexam.history_is_written_once()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'the examiners'' history is written once; nothing on it is changed or removed' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_ee_event_written_once BEFORE UPDATE OR DELETE ON extexam.event
    FOR EACH ROW EXECUTE FUNCTION extexam.history_is_written_once();

CREATE OR REPLACE FUNCTION extexam.record(p_action text, p_actor uuid, p_actor_name text, p_examiner uuid, p_project uuid, p_assignment uuid,
                                          p_from text, p_to text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    INSERT INTO extexam.event (id, actor_id, actor_office, actor_name, action, examiner_id, project_id, assignment_id, from_value, to_value, reason)
    VALUES (v, p_actor, nullif(current_setting('moaum.actor_office', true), ''), coalesce(p_actor_name, 'The portal'), p_action, p_examiner, p_project, p_assignment,
            p_from, p_to, nullif(btrim(coalesce(p_reason, '')), ''));
    RETURN v;
END $$;

-- ── the examiner's name, from the person row ─────────────────────────────────
CREATE OR REPLACE FUNCTION extexam.examiner_name(p_examiner uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce(e.title || ' ', '') || p.given_names || ' ' || p.surname
      FROM extexam.examiner e JOIN iam.person p ON p.id = e.person_id WHERE e.id = p_examiner
$$;

-- ── the examiner behind a signed-in person ───────────────────────────────────
CREATE OR REPLACE FUNCTION extexam.examiner_of(p_person uuid)
RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT e.id FROM extexam.examiner e WHERE e.person_id = p_person AND e.status = 'ACTIVE'
$$;

-- ── the assessment's arithmetic: the total, the maximum, the percentage, the grade in force ──
CREATE OR REPLACE FUNCTION extexam.compute(p_assessment uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_total numeric; v_max numeric; v_pct numeric; v_grade text; v_rubric uuid; v_missing int;
BEGIN
    SELECT a2.rubric_id INTO v_rubric FROM extexam.assessment a JOIN extexam.assignment a2 ON a2.id = a.assignment_id WHERE a.id = p_assessment;
    SELECT coalesce(sum(s.score), 0), sum(c.max_score) FILTER (WHERE c.active), count(*) FILTER (WHERE c.active AND s.score IS NULL)
      INTO v_total, v_max, v_missing
      FROM extexam.criterion c LEFT JOIN extexam.assessment_score s ON s.criterion_id = c.id AND s.assessment_id = p_assessment
     WHERE c.rubric_id = v_rubric;
    v_pct := CASE WHEN coalesce(v_max, 0) > 0 THEN round(100 * v_total / v_max, 1) ELSE NULL END;
    SELECT g.grade INTO v_grade FROM policy.grade_of(CASE WHEN v_pct IS NULL THEN NULL ELSE round(v_pct)::int END) g;
    UPDATE extexam.assessment SET total = CASE WHEN v_missing = 0 THEN v_total ELSE NULL END, max_total = v_max, percentage = CASE WHEN v_missing = 0 THEN v_pct ELSE NULL END,
           grade = CASE WHEN v_missing = 0 THEN v_grade ELSE NULL END, saved_at = now()
     WHERE id = p_assessment;
END $$;

-- ── a score, checked against its criterion's maximum ─────────────────────────
CREATE OR REPLACE FUNCTION extexam.score(p_assessment uuid, p_criterion uuid, p_score numeric, p_comment text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE c extexam.criterion; a extexam.assessment;
BEGIN
    SELECT * INTO a FROM extexam.assessment WHERE id = p_assessment FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no assessment %', p_assessment USING ERRCODE = 'no_data_found'; END IF;
    IF a.state IN ('SUBMITTED','LOCKED') THEN
        RAISE EXCEPTION 'a submitted assessment is read-only' USING ERRCODE = '23514', HINT = 'Ask the department to reopen it if a correction is needed.';
    END IF;
    SELECT * INTO c FROM extexam.criterion WHERE id = p_criterion;
    IF NOT FOUND THEN RAISE EXCEPTION 'no criterion %', p_criterion USING ERRCODE = 'no_data_found'; END IF;
    IF p_score IS NOT NULL AND (p_score < 0 OR p_score > c.max_score) THEN
        RAISE EXCEPTION '% is marked out of %', c.name, c.max_score USING ERRCODE = '23514', HINT = 'Enter a score between 0 and the maximum.';
    END IF;
    INSERT INTO extexam.assessment_score (assessment_id, criterion_id, score, comment) VALUES (p_assessment, p_criterion, p_score, nullif(btrim(coalesce(p_comment, '')), ''))
    ON CONFLICT (assessment_id, criterion_id) DO UPDATE SET score = EXCLUDED.score, comment = EXCLUDED.comment;
END $$;

-- ── submission: every active criterion scored, a recommendation given; the assignment follows ──
CREATE OR REPLACE FUNCTION extexam.submit(p_assessment uuid, p_actor uuid, p_actor_name text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a extexam.assessment; g extexam.assignment; v_missing text;
BEGIN
    SELECT * INTO a FROM extexam.assessment WHERE id = p_assessment FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no assessment %', p_assessment USING ERRCODE = 'no_data_found'; END IF;
    IF a.state IN ('SUBMITTED','LOCKED') THEN RAISE EXCEPTION 'the assessment is submitted already' USING ERRCODE = '23514'; END IF;
    SELECT * INTO g FROM extexam.assignment WHERE id = a.assignment_id FOR UPDATE;
    IF g.ended_at IS NOT NULL THEN RAISE EXCEPTION 'this assignment has ended' USING ERRCODE = '23514', HINT = 'The project was reassigned or withdrawn.'; END IF;
    PERFORM extexam.compute(p_assessment);
    SELECT string_agg(c.name, ', ' ORDER BY c.ordinal) INTO v_missing
      FROM extexam.criterion c LEFT JOIN extexam.assessment_score s ON s.criterion_id = c.id AND s.assessment_id = p_assessment
     WHERE c.rubric_id = g.rubric_id AND c.active AND s.score IS NULL;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'every criterion is scored before submission; still unscored: %', v_missing USING ERRCODE = '23514', HINT = 'Score each line, then submit.';
    END IF;
    IF a.final_recommendation IS NULL THEN
        RAISE EXCEPTION 'a final recommendation is given before submission' USING ERRCODE = '23514', HINT = 'Choose pass, pass subject to corrections, reassessment required, or fail.';
    END IF;
    IF length(btrim(coalesce(a.general_comments, ''))) < 20 THEN
        RAISE EXCEPTION 'the general comments say something about the work' USING ERRCODE = '23514', HINT = 'Write at least a sentence or two of general comments.';
    END IF;
    UPDATE extexam.assessment SET state = 'SUBMITTED', submitted_at = now(), saved_at = now() WHERE id = p_assessment;
    UPDATE extexam.assignment SET status = 'SUBMITTED' WHERE id = a.assignment_id;
    PERFORM extexam.record(CASE WHEN a.state = 'REOPENED' THEN 'ASSESSMENT_RESUBMITTED' ELSE 'ASSESSMENT_SUBMITTED' END, p_actor, p_actor_name, g.examiner_id, g.project_id, g.id,
                           a.state, 'SUBMITTED', NULL);
END $$;

-- ── the desk locks a submission, or reopens it on a reason ──────────────────
CREATE OR REPLACE FUNCTION extexam.lock(p_assessment uuid, p_actor uuid, p_actor_name text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a extexam.assessment; g extexam.assignment;
BEGIN
    SELECT * INTO a FROM extexam.assessment WHERE id = p_assessment FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no assessment %', p_assessment USING ERRCODE = 'no_data_found'; END IF;
    IF a.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'only a submitted assessment is locked; this one is %', lower(a.state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO g FROM extexam.assignment WHERE id = a.assignment_id;
    UPDATE extexam.assessment SET state = 'LOCKED', locked_at = now(), locked_by = p_actor WHERE id = p_assessment;
    UPDATE extexam.assignment SET status = 'LOCKED' WHERE id = a.assignment_id;
    PERFORM extexam.record('ASSESSMENT_LOCKED', p_actor, p_actor_name, g.examiner_id, g.project_id, g.id, 'SUBMITTED', 'LOCKED', NULL);
END $$;

CREATE OR REPLACE FUNCTION extexam.reopen(p_assessment uuid, p_actor uuid, p_actor_name text, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a extexam.assessment; g extexam.assignment;
BEGIN
    SELECT * INTO a FROM extexam.assessment WHERE id = p_assessment FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no assessment %', p_assessment USING ERRCODE = 'no_data_found'; END IF;
    IF a.state NOT IN ('SUBMITTED','LOCKED') THEN RAISE EXCEPTION 'only a submitted or locked assessment is reopened' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'reopening an assessment records the reason' USING ERRCODE = '23514', HINT = 'Say why, in a line; the examiner is told.'; END IF;
    SELECT * INTO g FROM extexam.assignment WHERE id = a.assignment_id;
    UPDATE extexam.assessment SET state = 'REOPENED', reopened_at = now(), reopened_by = p_actor, reopen_reason = btrim(p_reason), version = version + 1,
           submitted_at = NULL, locked_at = NULL, locked_by = NULL WHERE id = p_assessment;
    UPDATE extexam.assignment SET status = 'REOPENED' WHERE id = a.assignment_id;
    PERFORM extexam.record('ASSESSMENT_REOPENED', p_actor, p_actor_name, g.examiner_id, g.project_id, g.id, a.state, 'REOPENED', btrim(p_reason));
END $$;

-- ── the standing of an assignment against its deadline ───────────────────────
CREATE OR REPLACE FUNCTION extexam.overdue(p_status text, p_deadline date)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_status IN ('ASSIGNED','IN_REVIEW','REOPENED') AND p_deadline < current_date
$$;

-- ── the default form: the University's criteria, in two sections ────────────
INSERT INTO extexam.rubric (code, name, kind, has_defence, note) VALUES
    ('UG_DEFAULT', 'Undergraduate Final-Year Project', 'UNDERGRADUATE', true, 'The written work out of 80 and the defence out of 20, to 100 in all.'),
    ('PG_DEFAULT', 'Postgraduate Project, Dissertation or Thesis', 'POSTGRADUATE', true, 'The written work out of 70 and the oral examination out of 30, to 100 in all.');
INSERT INTO extexam.criterion (rubric_id, section, name, guidance, max_score, ordinal)
SELECT r.id, x.section, x.name, x.guidance, x.max_score, x.ordinal FROM extexam.rubric r, (VALUES
    ('WRITTEN', 'Project title and relevance', 'Is the title apt, and the problem worth the work?', 5, 1),
    ('WRITTEN', 'Abstract', 'Does it state the problem, the method, the findings and the contribution?', 5, 2),
    ('WRITTEN', 'Introduction and problem definition', 'Background, aim, objectives, scope, significance', 8, 3),
    ('WRITTEN', 'Literature review', 'Breadth, currency, critical engagement, the gap identified', 10, 4),
    ('WRITTEN', 'Methodology', 'Fitness of the approach, rigour, ethics where relevant', 10, 5),
    ('WRITTEN', 'Implementation or technical work', 'Design, construction, testing; the system or study as built', 15, 6),
    ('WRITTEN', 'Analysis, results and discussion', 'Findings presented clearly and interpreted against the objectives', 10, 7),
    ('WRITTEN', 'Originality and practical contribution', 'What is new, and what use it is', 7, 8),
    ('WRITTEN', 'Documentation and presentation quality', 'Structure, language, figures, references in the required style', 10, 9),
    ('DEFENCE', 'Presentation and communication', 'Clarity, organisation, timing', 5, 10),
    ('DEFENCE', 'Technical knowledge and understanding of the project', 'Command of the subject and of the work done', 8, 11),
    ('DEFENCE', 'Response to questions', 'Answers direct, reasoned, honest about limits', 5, 12),
    ('DEFENCE', 'Demonstration and professionalism', 'The artefact shown to work; conduct', 2, 13)
) AS x(section, name, guidance, max_score, ordinal) WHERE r.code = 'UG_DEFAULT';
INSERT INTO extexam.criterion (rubric_id, section, name, guidance, max_score, ordinal)
SELECT r.id, x.section, x.name, x.guidance, x.max_score, x.ordinal FROM extexam.rubric r, (VALUES
    ('WRITTEN', 'Title, abstract and statement of the problem', NULL, 10, 1),
    ('WRITTEN', 'Literature review and theoretical framework', NULL, 15, 2),
    ('WRITTEN', 'Methodology', NULL, 15, 3),
    ('WRITTEN', 'Results, analysis and discussion', NULL, 15, 4),
    ('WRITTEN', 'Originality and contribution to knowledge', NULL, 10, 5),
    ('WRITTEN', 'Organisation, language and referencing', NULL, 5, 6),
    ('DEFENCE', 'Presentation and communication', NULL, 10, 7),
    ('DEFENCE', 'Knowledge of the subject and defence of the work', NULL, 15, 8),
    ('DEFENCE', 'Response to questions', NULL, 5, 9)
) AS x(section, name, guidance, max_score, ordinal) WHERE r.code = 'PG_DEFAULT';

-- ── the grants: no DELETE, ever ─────────────────────────────────────────────
GRANT USAGE ON SCHEMA extexam TO app_results, app_admissions, app_iam, app_auditor;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA extexam TO app_results, app_admissions;
GRANT SELECT ON ALL TABLES IN SCHEMA extexam TO app_iam, app_auditor;
REVOKE UPDATE ON extexam.event, extexam.project_document_blob, extexam.examiner_file_blob FROM app_results, app_admissions;
ALTER DEFAULT PRIVILEGES IN SCHEMA extexam GRANT SELECT, INSERT, UPDATE ON TABLES TO app_results, app_admissions;
ALTER DEFAULT PRIVILEGES IN SCHEMA extexam GRANT SELECT ON TABLES TO app_iam, app_auditor;

COMMIT;
