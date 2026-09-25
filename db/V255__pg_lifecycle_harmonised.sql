-- ═══════════════════════════════════════════════════════════════════════════
-- V255 · The postgraduate lifecycle, one connected record
--
--   The School's modules already run an applicant from the apply form to an
--   award (V201–V228, V254). What they lacked was the thread between them:
--
--   1. a history of the application itself — every state it passed, every fee
--      confirmed, every reference received — with the actor on each line, and
--      the applicant told at each turn from the same outbox as everything else;
--   2. an admitted applicant becoming a student without a second account: the
--      password chosen as an applicant opens the student portal on the
--      admission number, and the applicant's email and phone become the
--      student's reach;
--   3. a research record that keeps every document the candidate submits, by
--      kind and version, and tells the candidate when its stage moves;
--   4. an award that ends on the register: the Senate's award recorded on the
--      research desk writes the graduand, changes the student's status to
--      GRADUATED and tells them — so the graduation list, alumni and the
--      certificate see a postgraduate as they see everyone else;
--   5. a postgraduate never charged as a spillover student: the fee engine's
--      final level for a postgraduate programme is its own highest level.
--
--   Nothing here rewrites the application, research or coursework tables; it
--   adds the trail, the documents and the two functions the thread was missing.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V255: the postgraduate lifecycle harmonised', true);

-- ── 1 · the application's own history ─────────────────────────────────────

CREATE TABLE admissions.pg_application_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.pg_application(id) ON DELETE CASCADE,
    kind           text NOT NULL,
    note           text NULL,
    actor_id       uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pg_application_event ON admissions.pg_application_event (application_id, at);
SELECT audit.attach('admissions.pg_application_event');
COMMENT ON TABLE admissions.pg_application_event IS
  'Every turn a postgraduate application takes — created, submitted, each fee confirmed, each desk''s decision, '
  'each reference received, accepted, admitted — written by trigger from the application itself, with the actor.';

CREATE OR REPLACE FUNCTION admissions.pg_app_event(p_app uuid, p_kind text, p_note text)
RETURNS void
LANGUAGE sql AS $$
    INSERT INTO admissions.pg_application_event (application_id, kind, note, actor_id, actor_office)
    VALUES (p_app, p_kind, p_note,
            nullif(current_setting('moaum.actor_id', true), '')::uuid,
            nullif(current_setting('moaum.actor_office', true), ''));
$$;

/* the applicant told from the outbox: one place that knows their email and application number */
CREATE OR REPLACE FUNCTION admissions.pg_tell_applicant(p_app uuid, p_subject text, p_body text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_email text; v_no text;
BEGIN
    SELECT p.email, a.application_no INTO v_email, v_no
      FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id
     WHERE a.id = p_app;
    IF v_email IS NULL THEN RETURN; END IF;
    PERFORM platform.queue_notice('EMAIL', v_email, p_subject,
        'Dear applicant,' || E'\n\n' || p_body || E'\n\n' || 'Application number: ' || coalesce(v_no, '') || E'\n' ||
        'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi',
        'pg_application', p_app);
END $$;

CREATE OR REPLACE FUNCTION admissions.pg_application_trail()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_fee numeric;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM admissions.pg_app_event(NEW.id, 'CREATED', 'Application opened for ' || NEW.programme_code || ' · ' || NEW.session);
        IF NEW.state = 'SUBMITTED' THEN
            PERFORM admissions.pg_app_event(NEW.id, 'SUBMITTED', 'Application submitted');
            SELECT application_fee INTO v_fee FROM admissions.pg_fee_rule(NEW.session);
            PERFORM admissions.pg_tell_applicant(NEW.id, 'Your MOAUM postgraduate application has been received',
                'Your application for ' || NEW.programme_code || ' in the ' || NEW.session || ' session has been received and numbered. '
                || 'Pay the application fee of ₦' || coalesce(v_fee::text, '') || ' on the applicant portal; once it is confirmed you complete your academic record, '
                || 'name your referees and upload your documents there. You can track the application on the portal at any time.');
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.state IS DISTINCT FROM OLD.state THEN
        PERFORM admissions.pg_app_event(NEW.id, NEW.state,
            CASE NEW.state
                WHEN 'SUBMITTED'        THEN 'Application submitted'
                WHEN 'DEPT_RECOMMENDED' THEN 'Recommended by the department' || coalesce(' — ' || NEW.dept_note, '')
                WHEN 'DEPT_DECLINED'    THEN 'Not recommended by the department' || coalesce(' — ' || NEW.dept_note, '')
                WHEN 'FAC_RECOMMENDED'  THEN 'Recommended by the faculty' || coalesce(' — ' || NEW.fac_note, '')
                WHEN 'FAC_DECLINED'     THEN 'Not recommended by the faculty' || coalesce(' — ' || NEW.fac_note, '')
                WHEN 'OFFERED'          THEN 'Admission offered by the School' || coalesce(' — ' || NEW.spgs_note, '')
                WHEN 'NOT_OFFERED'      THEN 'Admission not offered by the School' || coalesce(' — ' || NEW.spgs_note, '')
                WHEN 'ACCEPTED'         THEN 'Offer accepted'
                WHEN 'ADMITTED'         THEN 'Admitted to the register'
                ELSE NEW.state
            END);
        IF NEW.state = 'SUBMITTED' AND OLD.state = 'DRAFT' THEN
            PERFORM admissions.pg_tell_applicant(NEW.id, 'Your MOAUM postgraduate application has been submitted',
                'Your application has been submitted to the department. You can track it on the applicant portal.');
        ELSIF NEW.state = 'ACCEPTED' THEN
            PERFORM admissions.pg_tell_applicant(NEW.id, 'Your offer of admission is accepted',
                'Your acceptance is recorded. Download your offer of admission from the applicant portal; the School now admits you to the register '
                || 'and you will be told your admission number and how to sign in as a student.');
        ELSIF NEW.state = 'ADMITTED' THEN
            PERFORM admissions.pg_tell_applicant(NEW.id, 'You are admitted — your student record is open',
                'Your student record is on the University register. Your admission number is '
                || coalesce((SELECT admission_no FROM people.student WHERE id = NEW.student_id), '(issued shortly)')
                || '. Sign in to the student portal with that number and the password you chose as an applicant, pay your school fees and register your courses. '
                || 'Your matriculation number is issued after registration.');
        END IF;
    END IF;
    IF NEW.fee_confirmed_at IS NOT NULL AND OLD.fee_confirmed_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.id, 'APPLICATION_FEE_CONFIRMED', 'Application fee confirmed');
        PERFORM admissions.pg_tell_applicant(NEW.id, 'Your application fee is confirmed',
            'Your application fee is confirmed. Complete your academic record, name your referees and upload your documents on the applicant portal; '
            || 'the department considers the application once these are in.');
    END IF;
    IF NEW.checking_confirmed_at IS NOT NULL AND OLD.checking_confirmed_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.id, 'CHECKING_FEE_CONFIRMED', 'Checking fee confirmed; the decision is open to the applicant');
        PERFORM admissions.pg_tell_applicant(NEW.id, 'Your admission decision is ready to view',
            'Your checking fee is confirmed. Sign in to the applicant portal to read the School''s decision on your application.');
    END IF;
    IF NEW.acceptance_confirmed_at IS NOT NULL AND OLD.acceptance_confirmed_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.id, 'ACCEPTANCE_FEE_CONFIRMED', 'Acceptance fee confirmed');
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pg_application_trail
AFTER INSERT OR UPDATE ON admissions.pg_application
FOR EACH ROW EXECUTE FUNCTION admissions.pg_application_trail();

/* a reference coming in is a turn on the application too */
CREATE OR REPLACE FUNCTION admissions.pg_referee_trail()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.submitted_at IS NOT NULL AND OLD.submitted_at IS NULL THEN
        PERFORM admissions.pg_app_event(NEW.application_id, 'REFERENCE_RECEIVED', 'Reference received from ' || NEW.name);
        PERFORM admissions.pg_tell_applicant(NEW.application_id, 'A reference has been received',
            'Your referee ' || NEW.name || ' has submitted a reference for your application.');
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pg_referee_trail
AFTER UPDATE ON admissions.pg_referee
FOR EACH ROW EXECUTE FUNCTION admissions.pg_referee_trail();

/* the applications already on the register get their history from the timestamps they carry, so the trail
   does not begin empty for anyone */
INSERT INTO admissions.pg_application_event (application_id, kind, note, actor_id, actor_office, at)
SELECT a.id, e.kind, e.note, e.actor, NULL, e.at
  FROM admissions.pg_application a
  CROSS JOIN LATERAL (VALUES
      ('CREATED',                    'Application opened for ' || a.programme_code || ' · ' || a.session, NULL::uuid, a.created_at),
      ('SUBMITTED',                  'Application submitted',                       NULL::uuid, a.submitted_at),
      ('APPLICATION_FEE_CONFIRMED',  'Application fee confirmed',                   NULL::uuid, a.fee_confirmed_at),
      (CASE WHEN a.dept_decided_at IS NULL THEN NULL WHEN a.state IN ('DEPT_DECLINED') THEN 'DEPT_DECLINED' ELSE 'DEPT_RECOMMENDED' END,
                                     'Department decision' || coalesce(' — ' || a.dept_note, ''), a.dept_decided_by, a.dept_decided_at),
      (CASE WHEN a.fac_decided_at IS NULL THEN NULL WHEN a.state IN ('FAC_DECLINED') THEN 'FAC_DECLINED' ELSE 'FAC_RECOMMENDED' END,
                                     'Faculty decision' || coalesce(' — ' || a.fac_note, ''), a.fac_decided_by, a.fac_decided_at),
      (CASE WHEN a.spgs_decided_at IS NULL THEN NULL WHEN a.state = 'NOT_OFFERED' THEN 'NOT_OFFERED' ELSE 'OFFERED' END,
                                     'School decision' || coalesce(' — ' || a.spgs_note, ''), a.spgs_decided_by, a.spgs_decided_at),
      ('CHECKING_FEE_CONFIRMED',     'Checking fee confirmed',                      NULL::uuid, a.checking_confirmed_at),
      ('ACCEPTANCE_FEE_CONFIRMED',   'Acceptance fee confirmed',                    NULL::uuid, a.acceptance_confirmed_at),
      ('ACCEPTED',                   'Offer accepted',                              NULL::uuid, a.accepted_at),
      ('ADMITTED',                   'Admitted to the register',                    NULL::uuid, a.admitted_at)
  ) AS e(kind, note, actor, at)
 WHERE e.kind IS NOT NULL AND e.at IS NOT NULL;

-- ── 2 · the applicant becomes the student: one person, one password ───────

CREATE OR REPLACE FUNCTION admissions.pg_admit(p_application uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE a admissions.pg_application; p admissions.pg_applicant; v_student uuid; v_yy text;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_application;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF a.state <> 'ACCEPTED' THEN RAISE EXCEPTION 'only an accepted offer is admitted (state is %)', a.state; END IF;
    IF a.student_id IS NOT NULL THEN RETURN a.student_id; END IF;   -- idempotent
    SELECT * INTO p FROM admissions.pg_applicant WHERE id = a.applicant_id;
    v_yy := substr(a.session, 3, 2);

    INSERT INTO people.student (id, candidate_id, admission_no, surname, other_names, sex, date_of_birth,
                               programme_code, entry_mode, entry_session, entry_level, current_level, status, school_id)
    VALUES (gen_random_uuid(), NULL,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', a.session)::text, 6, '0'),
            p.surname, p.other_names, p.sex, p.date_of_birth,
            a.programme_code, 'POSTGRADUATE', a.session, a.entry_level, a.entry_level, 'ADMITTED', 'S002')
    RETURNING id INTO v_student;

    -- the applicant's reach becomes the student's, so every notice from here finds them
    INSERT INTO people.student_contact (student_id, phone, email, updated_at)
    VALUES (v_student, p.phone, lower(p.email), now())
    ON CONFLICT (student_id) DO NOTHING;

    -- the same password opens the student portal on the admission number: no second account to create
    INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
    VALUES (gen_random_uuid(), v_student, p.password_hash, false)
    ON CONFLICT (student_id) DO NOTHING;

    UPDATE admissions.pg_application
       SET state = 'ADMITTED', admitted_at = now(), student_id = v_student
     WHERE id = p_application;
    RETURN v_student;
END;
$$;

COMMENT ON FUNCTION admissions.pg_admit(uuid) IS
  'Admits an accepted applicant: the student row, the applicant''s contact as the student''s, the applicant''s '
  'password as the student portal account (sign-in on the admission number), and the application marked ADMITTED.';

-- ── 3 · the research record keeps every document, by kind and version ─────

CREATE TABLE admissions.pg_research_document (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    research_id  uuid NOT NULL REFERENCES admissions.pg_research(id) ON DELETE CASCADE,
    kind         text NOT NULL,
    version      int  NOT NULL,
    filename     text NOT NULL,
    content_type text NOT NULL,
    size_bytes   int  NOT NULL,
    note         text NULL,
    status       text NOT NULL DEFAULT 'SUBMITTED',
    reviewer_note text NULL,
    reviewed_by  uuid NULL,
    reviewed_at  timestamptz NULL,
    by_candidate boolean NOT NULL DEFAULT true,
    uploaded_by  uuid NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (research_id, kind, version),
    CONSTRAINT ck_pg_rdoc_kind   CHECK (kind IN ('PROPOSAL','SEMINAR_PAPER','PLAGIARISM_REPORT','DRAFT','CORRECTED','FINAL','OTHER')),
    CONSTRAINT ck_pg_rdoc_status CHECK (status IN ('SUBMITTED','ACCEPTED','RETURNED')),
    CONSTRAINT ck_pg_rdoc_type   CHECK (content_type IN ('application/pdf',
                                        'application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
    CONSTRAINT ck_pg_rdoc_size   CHECK (size_bytes BETWEEN 1 AND 26214400),
    CONSTRAINT ck_pg_rdoc_version CHECK (version >= 1)
);
CREATE INDEX ix_pg_research_document ON admissions.pg_research_document (research_id, kind, version DESC);
SELECT audit.attach('admissions.pg_research_document');
COMMENT ON TABLE admissions.pg_research_document IS
  'Every document a candidate submits on their research — proposal, seminar paper, plagiarism report, draft, '
  'corrected draft, final copy — numbered by version within its kind. A new version never replaces an old one.';

CREATE TABLE admissions.pg_research_document_blob (
    document_id uuid PRIMARY KEY REFERENCES admissions.pg_research_document(id) ON DELETE CASCADE,
    bytes       bytea NOT NULL
);
SELECT audit.exempt('admissions.pg_research_document_blob', 'The bytes of a research document; the document row on the spine records who submitted it and when.');

CREATE OR REPLACE FUNCTION admissions.pg_research_next_version(p_research uuid, p_kind text)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT coalesce(max(version), 0) + 1 FROM admissions.pg_research_document WHERE research_id = p_research AND kind = p_kind;
$$;

/* the candidate told when the stage of their research moves, from the same outbox as everything else */
CREATE OR REPLACE FUNCTION admissions.pg_research_trail()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE reach record; v_words text; v_what text;
BEGIN
    IF NEW.stage IS NOT DISTINCT FROM OLD.stage THEN RETURN NEW; END IF;
    SELECT * INTO reach FROM people.student_reach(NEW.student_id);
    IF reach.email IS NULL THEN RETURN NEW; END IF;
    v_what := CASE NEW.degree_kind WHEN 'THESIS' THEN 'thesis' WHEN 'DISSERTATION' THEN 'dissertation' ELSE 'project' END;
    v_words := CASE NEW.stage
        WHEN 'SUPERVISED'        THEN 'A supervisor has been assigned to you. Their name is on your research desk; submit your proposal there when it is ready.'
        WHEN 'PROPOSAL_SUBMITTED' THEN 'Your research proposal has been submitted and is with the department.'
        WHEN 'PROPOSAL_APPROVED' THEN 'Your research proposal is approved. The department will schedule your research seminar.'
        WHEN 'SEMINAR_HELD'      THEN 'Your research seminar has been held and reported. Register your title with the School, with the plagiarism report.'
        WHEN 'TITLE_REGISTERED'  THEN 'Your research title is registered. Write the ' || v_what || ' and submit the draft when your supervisor is satisfied.'
        WHEN 'PANEL_CONSTITUTED' THEN 'A panel of examiners has been constituted for your ' || v_what || '. Submit your draft for examination on your research desk.'
        WHEN 'DRAFT_SUBMITTED'   THEN 'Your draft is with the examiners. The oral examination is scheduled once they have reported.'
        WHEN 'VIVA_HELD'         THEN 'Your oral examination has been held. The panel''s decision is on your research desk.'
        WHEN 'CORRECTIONS'       THEN 'The panel requires corrections to your ' || v_what || coalesce(', due by ' || to_char(NEW.corrections_due, 'DD Month YYYY'), '') || '. Submit the corrected copy on your research desk.'
        WHEN 'FINAL_SUBMITTED'   THEN 'Your final ' || v_what || ' has been received and is with the School for clearance.'
        WHEN 'CLEARED'           THEN 'Your final ' || v_what || ' is cleared for binding. The School Board recommends the award to Senate.'
        WHEN 'AWARD_RECOMMENDED' THEN 'The School Board has recommended your award to Senate.'
        WHEN 'AWARDED'           THEN 'Senate has approved your award. Congratulations. See the Graduation screen on the portal for clearance and your certificate.'
        WHEN 'WITHDRAWN'         THEN 'Your research record has been marked withdrawn. Contact the School of Postgraduate Studies if this is not expected.'
        ELSE NULL END;
    IF v_words IS NULL THEN RETURN NEW; END IF;
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your research: ' || lower(replace(NEW.stage, '_', ' ')),
        v_words || E'\n\n' || coalesce('Topic: ' || NEW.topic || E'\n', '') || 'School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi',
        'student', NEW.student_id);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pg_research_trail
AFTER UPDATE OF stage ON admissions.pg_research
FOR EACH ROW EXECUTE FUNCTION admissions.pg_research_trail();

-- ── 4 · the award ends on the register ────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.pg_award(p_research uuid, p_minute text, p_session text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE r admissions.pg_research; s people.student; v_award text; v_cgpa numeric; v_session text; v_g uuid;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'an award is recorded on a Senate minute, and none was cited'
        USING ERRCODE = '23514', HINT = 'Cite the minute of the Senate that approved the award.';
    END IF;
    SELECT * INTO r FROM admissions.pg_research WHERE id = p_research;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such research record' USING ERRCODE = '23503'; END IF;
    IF r.stage NOT IN ('AWARD_RECOMMENDED', 'AWARDED') THEN
        RAISE EXCEPTION 'the award follows the School Board''s recommendation; this record is at %', lower(replace(r.stage, '_', ' '))
        USING ERRCODE = '23514', HINT = 'Record the Board''s recommendation first.';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    IF s.matric_no IS NULL THEN
        RAISE EXCEPTION 'an award is recorded for a matriculated student; % has no matriculation number', s.surname
        USING ERRCODE = '23514', HINT = 'Matriculate the student (fees and registration) before the award is recorded.';
    END IF;
    SELECT coalesce(nullif(btrim(g.pg_award), ''), g.name) INTO v_award FROM ref.programme g WHERE g.code = s.programme_code;
    v_cgpa := coalesce(admissions.pg_cgpa(s.id), 0);
    -- the graduation session must be one the register knows; the PG School's calendar name is used when it is
    v_session := coalesce(
        (SELECT name FROM policy.academic_session WHERE name = nullif(btrim(p_session), '')),
        (SELECT name FROM policy.academic_session WHERE name = admissions.pg_current_session()),
        (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'),
        (SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1));

    UPDATE admissions.pg_research SET stage = 'AWARDED', awarded_at = coalesce(awarded_at, now()), updated_at = now() WHERE id = r.id;
    INSERT INTO admissions.pg_research_event (research_id, stage, note)
    VALUES (r.id, 'AWARDED', 'Award of ' || v_award || ' approved by Senate under minute ' || btrim(p_minute));

    INSERT INTO records.graduand (id, student_id, session, cgpa, award, unmet, senate_state, senate_minute)
    VALUES (gen_random_uuid(), s.id, v_session, least(v_cgpa, 5), v_award, NULL, 'APPROVED', btrim(p_minute))
    ON CONFLICT (student_id, session) DO UPDATE
       SET cgpa = EXCLUDED.cgpa, award = EXCLUDED.award, unmet = NULL, senate_state = 'APPROVED', senate_minute = EXCLUDED.senate_minute
    RETURNING id INTO v_g;

    IF s.status <> 'GRADUATED' THEN
        PERFORM people.change_status(s.id, 'GRADUATED', btrim(p_minute), current_date, 'Postgraduate award approved by Senate');
    END IF;
    RETURN v_g;
END $$;

COMMENT ON FUNCTION admissions.pg_award(uuid, text, text) IS
  'Senate''s award of a postgraduate degree, recorded once on the research desk: the stage AWARDED, the graduand '
  'row approved on the minute, the student GRADUATED. The graduation list, alumni and the certificate follow.';

-- ── 5 · a postgraduate is never a spillover student ───────────────────────

CREATE OR REPLACE FUNCTION finance.final_level(p_programme text) RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p.category = 'POST GRADUATE' THEN 900
                WHEN p.code = 'C00061' THEN 600
                WHEN upper(p.name) LIKE 'LL.B%' OR upper(p.name) LIKE '%PHARMACY%' THEN 500
                ELSE 400 END
      FROM ref.programme p WHERE p.code = p_programme;
$$;

COMMENT ON FUNCTION finance.final_level(text) IS
  'The last level of a programme, for the spillover test: a postgraduate programme''s is 900, so a postgraduate '
  'at 700–900 matches the fee rows of their own level and never those of a spillover student.';

-- ── grants: the API role reads and writes what it did before ──────────────
GRANT SELECT, INSERT ON admissions.pg_application_event TO app_admissions, app_results;
GRANT SELECT ON admissions.pg_application_event TO app_iam, app_auditor;
GRANT SELECT, INSERT, UPDATE ON admissions.pg_research_document TO app_admissions, app_results;
GRANT SELECT ON admissions.pg_research_document TO app_iam, app_auditor;
GRANT SELECT, INSERT ON admissions.pg_research_document_blob TO app_admissions, app_results;

COMMIT;
