-- ═══════════════════════════════════════════════════════════════════════════
-- V355 — The JUPEB examination year: registering the candidates with the Board, the syllabus covered in the lectures,
--         continuous assessment, the calendar's reminders, the examination timetable and admit cards, and practice by topic
--         with a mock examination
--
--   · Registering with the Board (13 November 2026 – 29 January 2027 on the Board's calendar): each student's record ready to
--     send — subjects registered with the option chosen, a passport photograph, the facts the Board asks for — exported with
--     the photographs, then followed through the Board's stages (sent, confirmed, correction needed, corrected, withdrawn). What
--     was sent is kept; a record changed since is flagged with what changed, before the data-alignment deadline (12 February;
--     ₦50,000 a record after it). The Board's own portal format is not invented: the export carries every fact it asks for.
--   · The syllabus covered: when a lecture's attendance is taken, the topics it covered are ticked; a course's coverage is the
--     topics covered in its lectures of the session — for the office before the Board's monitoring of lectures (8 March – 16
--     April 2027), and for the lecturer.
--   · Continuous assessment: the JUPEB Office sets the session's components (each with its maximum — never assumed); the
--     lecturers of a subject enter their students' scores, the office reviews and locks a subject, and exports it for the
--     Board (scores due 25 June 2027). Unlocking takes a reason; a score is never deleted.
--   · The calendar's reminders, once each: the students of an event they see, 7 and 1 days before; the JUPEB Office's staff of a
--     deadline 14, 7 and 1 days before, with what stands (records not yet sent, changed since; subjects whose assessment is
--     incomplete); the lecturers of a subject whose assessment is incomplete, before it is due.
--   · The examination timetable (the Board releases it on 3 May 2027): its papers by subject, published by the office; each
--     student's own (the option they sit); and an admit card, a verifiable paper issued only to a student cleared to sit.
--   · Practice by topic: a question names its course and syllabus topic; a student sees their weakest topics, a lecturer the
--     class's. A mock examination: a practice test of kind MOCK — one attempt, within its window, its results shown only once
--     the office releases them. (The University's CBT engine serves registered University students only; the JUPEB practice
--     engine carries the mock.)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V355: the JUPEB examination year — Board registration, coverage, continuous assessment, reminders, examinations, practice by topic', true);

-- ── 0 · three more of the Board's dates the portal works from ─────────────────────────────────────────────────
ALTER TABLE jupeb.calendar_event DROP CONSTRAINT calendar_event_marker_check;
ALTER TABLE jupeb.calendar_event ADD CONSTRAINT calendar_event_marker_check CHECK (marker IN ('TEACHING_STARTS', 'SEMESTER_2_STARTS', 'BOARD_REGISTRATION',
    'BOARD_DATA_ALIGNMENT', 'BOARD_PENALTY_ALIGNMENT', 'LECTURE_MONITORING', 'CA_SUBMISSION', 'EXAM_TIMETABLE', 'CBT_MOCK', 'EXAMINATIONS', 'RESULTS'));
UPDATE jupeb.calendar_event e SET marker = v.marker
  FROM (VALUES (8, 'BOARD_DATA_ALIGNMENT'), (9, 'BOARD_PENALTY_ALIGNMENT'), (14, 'EXAM_TIMETABLE')) v(ord, marker)
 WHERE e.session = '2026/2027' AND e.source = 'BOARD' AND e.ord = v.ord AND e.marker IS NULL AND e.removed_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM jupeb.calendar_event x WHERE x.session = e.session AND x.marker = v.marker AND x.removed_at IS NULL);

-- ── 1 · registering the candidates with the Board ─────────────────────────────────────────────────────────────
/* what the Board is sent of a student: who they are, how to reach them, their combination and the Board's subjects (the option
   of an either/or subject as chosen) — the fingerprint of these tells a record changed since it was sent */
CREATE OR REPLACE FUNCTION jupeb.board_facts(p_app uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'surname', upper(btrim(a.surname)), 'firstName', btrim(a.first_name), 'middleName', nullif(btrim(coalesce(a.middle_name, '')), ''),
        'sex', a.sex, 'dateOfBirth', a.date_of_birth::text, 'nin', a.nin, 'phone', a.phone, 'email', lower(a.email),
        'stateOfOrigin', a.state_of_origin, 'lga', a.lga, 'combination', (SELECT c.code FROM jupeb.combination c WHERE c.id = a.combination_id),
        'subjects', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', coalesce(b.code, s.code), 'prefix', coalesce(b.prefix, s.code), 'title', coalesce(b.title, s.title))
                                               ORDER BY coalesce(b.code, s.code)), '[]'::jsonb)
                       FROM jupeb.subject_registration r JOIN jupeb.subject s ON s.id = r.subject_id
                       LEFT JOIN jupeb.board_subject b ON b.id = coalesce(r.board_subject_id,
                            (SELECT min(x.id::text)::uuid FROM jupeb.board_subject x WHERE x.subject_id = r.subject_id HAVING count(*) = 1))
                      WHERE r.application_id = a.id))
      FROM jupeb.application a WHERE a.id = p_app
$$;

CREATE TABLE jupeb.board_registration (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    session        text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    stage          text NOT NULL CHECK (stage IN ('SENT', 'CONFIRMED', 'CORRECTION_NEEDED', 'CORRECTED', 'WITHDRAWN')),
    board_ref      text NULL CHECK (board_ref IS NULL OR length(btrim(board_ref)) BETWEEN 1 AND 60),
    snapshot       jsonb NOT NULL,
    fingerprint    text NOT NULL,
    note           text NULL CHECK (note IS NULL OR length(note) <= 500),
    sent_at        timestamptz NOT NULL DEFAULT now(),
    sent_by        uuid NULL,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    updated_by     uuid NULL,
    CONSTRAINT uq_jupeb_board_registration UNIQUE (application_id, session)
);
SELECT audit.attach('jupeb.board_registration');
COMMENT ON TABLE jupeb.board_registration IS 'V355: a student''s registration with the JUPEB Board for the session''s examination — what was sent (snapshot) and the stage the Board''s portal is at; a record changed since it was sent is flagged by its fingerprint.';

CREATE TABLE jupeb.board_registration_event (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registration_id uuid NOT NULL REFERENCES jupeb.board_registration(id),
    stage           text NOT NULL,
    note            text NULL,
    at              timestamptz NOT NULL DEFAULT now(),
    actor           uuid NULL,
    office          text NULL
);
SELECT audit.attach('jupeb.board_registration_event');

/* a student's record ready to send to the Board — what is missing, said plainly (none: ready) */
CREATE OR REPLACE FUNCTION jupeb.board_problems(p_app uuid)
RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT array_remove(ARRAY[
        CASE WHEN a.state <> 'STUDENT' THEN 'Not an active student' END,
        CASE WHEN a.subjects_registered_at IS NULL THEN 'Subjects not registered' END,
        (SELECT 'Say which is taken: ' || string_agg(s.title, ', ') FROM jupeb.subject_registration r JOIN jupeb.subject s ON s.id = r.subject_id
          WHERE r.application_id = a.id AND r.board_subject_id IS NULL AND (SELECT count(*) FROM jupeb.board_subject b WHERE b.subject_id = r.subject_id) > 1),
        CASE WHEN NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED'))
             THEN 'No passport photograph' END,
        CASE WHEN a.sex IS NULL THEN 'Sex not recorded' END,
        CASE WHEN a.date_of_birth IS NULL THEN 'Date of birth not recorded' END,
        CASE WHEN a.nin IS NULL THEN 'NIN not recorded' END,
        CASE WHEN a.phone IS NULL THEN 'Phone not recorded' END,
        CASE WHEN a.state_of_origin IS NULL OR a.lga IS NULL THEN 'State of origin or LGA not recorded' END
    ], NULL)
      FROM jupeb.application a WHERE a.id = p_app
$$;

/* the session's students and where each stands with the Board: not sent (ready or what is missing), or the stage, and whether
   the record has changed since it was sent — with the facts that changed */
CREATE OR REPLACE FUNCTION jupeb.board_status(p_session text)
RETURNS TABLE (application_id uuid, application_no text, name text, class_name text, combination_code text, exam_no text, stage text, board_ref text,
               sent_at timestamptz, updated_at timestamptz, note text, problems text[], ready boolean, changed boolean, changed_facts text[])
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, upper(a.surname) || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), k.name, c.code, a.exam_no,
           coalesce(g.stage, 'NOT_SENT'), g.board_ref, g.sent_at, g.updated_at, g.note, p.problems, cardinality(p.problems) = 0,
           g.id IS NOT NULL AND g.stage <> 'WITHDRAWN' AND g.fingerprint <> md5(f.facts::text),
           CASE WHEN g.id IS NOT NULL AND g.fingerprint <> md5(f.facts::text)
                THEN ARRAY(SELECT x.key FROM jsonb_each(f.facts) x WHERE x.value IS DISTINCT FROM g.snapshot -> x.key ORDER BY x.key) END
      FROM jupeb.application a
      LEFT JOIN jupeb.board_registration g ON g.application_id = a.id AND g.session = p_session
      LEFT JOIN jupeb.class k ON k.id = a.class_id LEFT JOIN jupeb.combination c ON c.id = a.combination_id
      CROSS JOIN LATERAL (SELECT jupeb.board_facts(a.id) AS facts) f
      CROSS JOIN LATERAL (SELECT jupeb.board_problems(a.id) AS problems) p
     WHERE a.session = p_session AND (a.state = 'STUDENT' OR g.id IS NOT NULL)
     ORDER BY a.surname, a.first_name
$$;

/* the Board's stage of each student given: SENT and CORRECTED take what is sent now (the record must be ready); CONFIRMED,
   CORRECTION_NEEDED and WITHDRAWN only for a record already sent. Returns how many changed. */
CREATE OR REPLACE FUNCTION jupeb.board_mark(p_apps uuid[], p_session text, p_stage text, p_note text, p_ref text, p_actor uuid, p_office text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE a uuid; g jupeb.board_registration; f jsonb; k int := 0; v_problems text[];
BEGIN
    IF p_stage NOT IN ('SENT', 'CONFIRMED', 'CORRECTION_NEEDED', 'CORRECTED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'JUPEB_BOARD_STAGE: no such stage' USING ERRCODE = '23514';
    END IF;
    IF p_stage IN ('CORRECTION_NEEDED', 'WITHDRAWN') AND length(btrim(coalesce(p_note, ''))) < 3 THEN
        RAISE EXCEPTION 'JUPEB_BOARD_NOTE: say what the Board asks, or why the candidate is withdrawn' USING ERRCODE = '23514';
    END IF;
    FOREACH a IN ARRAY coalesce(p_apps, '{}') LOOP
        SELECT * INTO g FROM jupeb.board_registration WHERE application_id = a AND session = p_session FOR UPDATE;
        IF p_stage IN ('SENT', 'CORRECTED') THEN
            IF NOT EXISTS (SELECT 1 FROM jupeb.application x WHERE x.id = a AND x.session = p_session) THEN
                RAISE EXCEPTION 'JUPEB_BOARD_SESSION: a student of another session' USING ERRCODE = '23514';
            END IF;
            v_problems := jupeb.board_problems(a);
            IF cardinality(v_problems) > 0 THEN
                RAISE EXCEPTION 'JUPEB_BOARD_NOT_READY: % — %', (SELECT application_no FROM jupeb.application WHERE id = a), array_to_string(v_problems, '; ') USING ERRCODE = '23514';
            END IF;
            f := jupeb.board_facts(a);
            IF g.id IS NULL THEN
                INSERT INTO jupeb.board_registration (application_id, session, stage, board_ref, snapshot, fingerprint, note, sent_by, updated_by)
                VALUES (a, p_session, p_stage, nullif(btrim(coalesce(p_ref, '')), ''), f, md5(f::text), nullif(btrim(coalesce(p_note, '')), ''), p_actor, p_actor)
                RETURNING * INTO g;
            ELSE
                UPDATE jupeb.board_registration SET stage = p_stage, snapshot = f, fingerprint = md5(f::text), board_ref = coalesce(nullif(btrim(coalesce(p_ref, '')), ''), board_ref),
                       note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now(), updated_by = p_actor
                 WHERE id = g.id RETURNING * INTO g;
            END IF;
        ELSE
            IF g.id IS NULL THEN
                RAISE EXCEPTION 'JUPEB_BOARD_NOT_SENT: % has not been sent to the Board', (SELECT application_no FROM jupeb.application WHERE id = a) USING ERRCODE = '23514';
            END IF;
            UPDATE jupeb.board_registration SET stage = p_stage, board_ref = coalesce(nullif(btrim(coalesce(p_ref, '')), ''), board_ref),
                   note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now(), updated_by = p_actor
             WHERE id = g.id RETURNING * INTO g;
        END IF;
        INSERT INTO jupeb.board_registration_event (registration_id, stage, note, actor, office) VALUES (g.id, p_stage, nullif(btrim(coalesce(p_note, '')), ''), p_actor, p_office);
        PERFORM jupeb.app_event(a, 'BOARD_' || p_stage, CASE p_stage WHEN 'SENT' THEN 'Sent to the JUPEB Board for registration' WHEN 'CONFIRMED' THEN 'Registration confirmed by the Board'
            WHEN 'CORRECTION_NEEDED' THEN 'The Board asks for a correction' WHEN 'CORRECTED' THEN 'The corrected record sent to the Board' ELSE 'Withdrawn from the Board''s registration' END
            || coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
        k := k + 1;
    END LOOP;
    RETURN k;
END $$;

-- ── 2 · the syllabus covered in the lectures ─────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.lecture_topic (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    register_id uuid NOT NULL REFERENCES attendance.register(id),
    topic_id    uuid NOT NULL REFERENCES jupeb.unit_topic(id),
    marked_by   uuid NULL,
    marked_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_lecture_topic UNIQUE (register_id, topic_id)
);
CREATE INDEX ix_jupeb_lecture_topic_topic ON jupeb.lecture_topic (topic_id);
SELECT audit.attach('jupeb.lecture_topic');
COMMENT ON TABLE jupeb.lecture_topic IS 'V355: a syllabus topic a lecture covered, ticked when its attendance is taken.';

/* the topics a register may tick: of a timetabled lecture, its course's; of a register opened by hand, every course of the subject
   in that semester — with whether this lecture covered each, and when one of the session's lectures first did */
CREATE OR REPLACE FUNCTION jupeb.register_topics(p_register uuid)
RETURNS TABLE (topic_id uuid, unit_id uuid, unit_code text, unit_title text, ord int, sn text, topic text, sub_topic text, here boolean, first_covered date)
LANGUAGE sql STABLE AS $$
    WITH r AS (SELECT g.*, (SELECT t.unit_id FROM jupeb.timetable_slot t WHERE t.id = g.slot_ref) AS unit FROM attendance.register g WHERE g.id = p_register AND g.context = 'JUPEB')
    SELECT x.id, u.id, u.code, u.title, x.ord, x.sn, x.topic, x.sub_topic,
           EXISTS (SELECT 1 FROM jupeb.lecture_topic l WHERE l.register_id = r.id AND l.topic_id = x.id),
           (SELECT min(g2.held_on) FROM jupeb.lecture_topic l JOIN attendance.register g2 ON g2.id = l.register_id WHERE l.topic_id = x.id AND g2.session = r.session)
      FROM r JOIN jupeb.subject_unit u ON (r.unit IS NOT NULL AND u.id = r.unit) OR (r.unit IS NULL AND u.subject_id = r.subject_ref AND u.semester = r.semester)
      JOIN jupeb.unit_topic x ON x.unit_id = u.id
     ORDER BY u.ord, u.code, x.ord
$$;

/* the topics a lecture covered, as ticked: only topics the register may tick */
CREATE OR REPLACE FUNCTION jupeb.set_register_topics(p_register uuid, p_topics uuid[], p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE bad int;
BEGIN
    SELECT count(*) INTO bad FROM unnest(coalesce(p_topics, '{}')) t(id) WHERE t.id NOT IN (SELECT x.topic_id FROM jupeb.register_topics(p_register) x);
    IF bad > 0 THEN RAISE EXCEPTION 'JUPEB_COVERAGE_TOPIC: % of the topics are not of this lecture''s course', bad USING ERRCODE = '23514'; END IF;
    DELETE FROM jupeb.lecture_topic WHERE register_id = p_register AND NOT (topic_id = ANY (coalesce(p_topics, '{}')));
    INSERT INTO jupeb.lecture_topic (register_id, topic_id, marked_by) SELECT p_register, t, p_actor FROM unnest(coalesce(p_topics, '{}')) t
    ON CONFLICT (register_id, topic_id) DO NOTHING;
    RETURN (SELECT count(*) FROM jupeb.lecture_topic WHERE register_id = p_register);
END $$;

/* each course of a session's semester: its topics, those covered in the session's lectures, the last time, the lectures recorded */
CREATE OR REPLACE FUNCTION jupeb.coverage(p_session text, p_semester int)
RETURNS TABLE (unit_id uuid, subject_id uuid, subject_code text, subject_title text, code text, title text, semester int, topics int, covered int,
               last_covered date, lectures int, instructors text)
LANGUAGE sql STABLE AS $$
    SELECT u.id, s.id, s.code, s.title, u.code, u.title, u.semester,
           (SELECT count(*)::int FROM jupeb.unit_topic x WHERE x.unit_id = u.id),
           (SELECT count(DISTINCT l.topic_id)::int FROM jupeb.lecture_topic l JOIN jupeb.unit_topic x ON x.id = l.topic_id JOIN attendance.register g ON g.id = l.register_id
             WHERE x.unit_id = u.id AND g.session = p_session),
           (SELECT max(g.held_on) FROM jupeb.lecture_topic l JOIN jupeb.unit_topic x ON x.id = l.topic_id JOIN attendance.register g ON g.id = l.register_id
             WHERE x.unit_id = u.id AND g.session = p_session),
           (SELECT count(*)::int FROM attendance.register g JOIN jupeb.timetable_slot t ON t.id = g.slot_ref WHERE t.unit_id = u.id AND g.session = p_session AND g.saved_at IS NOT NULL),
           (SELECT string_agg(DISTINCT p.surname || ', ' || p.given_names, '; ') FROM attendance.instructor i JOIN iam.person p ON p.id = i.person_id
             WHERE i.context = 'JUPEB' AND i.session = p_session AND i.subject_ref = s.id AND i.ended_at IS NULL)
      FROM jupeb.subject_unit u JOIN jupeb.subject s ON s.id = u.subject_id
     WHERE u.semester = p_semester AND s.active AND EXISTS (SELECT 1 FROM jupeb.unit_topic x WHERE x.unit_id = u.id)
     ORDER BY s.title, u.ord, u.code
$$;
COMMENT ON FUNCTION jupeb.coverage(text, int) IS 'V355: each course of a semester — its syllabus topics, those its lectures of the session covered, the last time one did, its lectures recorded.';

-- ── 3 · continuous assessment ────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.ca_component (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session    text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    code       text NOT NULL CHECK (code ~ '^[A-Z0-9_]{1,20}$'),
    title      text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 80),
    max_score  numeric(6,2) NOT NULL CHECK (max_score > 0 AND max_score <= 1000),
    ord        int NOT NULL DEFAULT 1,
    active     boolean NOT NULL DEFAULT true,
    created_by uuid NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_ca_component UNIQUE (session, code)
);
SELECT audit.attach('jupeb.ca_component');
COMMENT ON TABLE jupeb.ca_component IS 'V355: a part of the session''s continuous assessment (a test, an assignment …) and its maximum, as the JUPEB Office sets it — never assumed.';

CREATE TABLE jupeb.ca_score (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    subject_id     uuid NOT NULL REFERENCES jupeb.subject(id),
    component_id   uuid NOT NULL REFERENCES jupeb.ca_component(id),
    score          numeric(6,2) NULL CHECK (score IS NULL OR score >= 0),
    entered_by     uuid NULL,
    entered_office text NULL,
    entered_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_ca_score UNIQUE (application_id, subject_id, component_id)
);
SELECT audit.attach('jupeb.ca_score');
COMMENT ON TABLE jupeb.ca_score IS 'V355: a student''s score in a part of a subject''s continuous assessment; cleared, it is kept empty — never deleted; every change on the audit trail.';

CREATE TABLE jupeb.ca_lock (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session       text NOT NULL,
    subject_id    uuid NOT NULL REFERENCES jupeb.subject(id),
    locked_at     timestamptz NOT NULL DEFAULT now(),
    locked_by     uuid NULL,
    unlocked_at   timestamptz NULL,
    unlocked_by   uuid NULL,
    unlock_reason text NULL,
    CONSTRAINT ck_jupeb_ca_unlock CHECK ((unlocked_at IS NULL) = (unlock_reason IS NULL))
);
CREATE UNIQUE INDEX ux_jupeb_ca_lock ON jupeb.ca_lock (session, subject_id) WHERE unlocked_at IS NULL;
SELECT audit.attach('jupeb.ca_lock');
COMMENT ON TABLE jupeb.ca_lock IS 'V355: a subject''s continuous assessment of a session locked by the JUPEB Office — its scores final for the Board; unlocked only with a reason.';

/* a score entered: of a student registered for the subject, in a component of their session, within its maximum, while the subject
   is not locked; an empty score clears it (the row is kept) */
CREATE OR REPLACE FUNCTION jupeb.ca_save(p_app uuid, p_subject uuid, p_component uuid, p_score numeric, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.ca_component;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    SELECT * INTO c FROM jupeb.ca_component WHERE id = p_component;
    IF a.id IS NULL OR NOT EXISTS (SELECT 1 FROM jupeb.subject_registration r WHERE r.application_id = p_app AND r.subject_id = p_subject) THEN
        RAISE EXCEPTION 'JUPEB_CA_STUDENT: the student is not registered for that subject' USING ERRCODE = '23514';
    END IF;
    IF c.id IS NULL OR c.session <> a.session OR NOT c.active THEN RAISE EXCEPTION 'JUPEB_CA_COMPONENT: no such part of the % assessment', a.session USING ERRCODE = '23514'; END IF;
    IF p_score IS NOT NULL AND (p_score < 0 OR p_score > c.max_score) THEN
        RAISE EXCEPTION 'JUPEB_CA_RANGE: % is scored out of %', c.title, trim(to_char(c.max_score, 'FM9990.##')) USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM jupeb.ca_lock l WHERE l.session = a.session AND l.subject_id = p_subject AND l.unlocked_at IS NULL) THEN
        RAISE EXCEPTION 'JUPEB_CA_LOCKED: the subject''s assessment is locked; the JUPEB Office unlocks it, with a reason' USING ERRCODE = '23514';
    END IF;
    INSERT INTO jupeb.ca_score (application_id, subject_id, component_id, score, entered_by, entered_office) VALUES (p_app, p_subject, p_component, p_score, p_actor, p_office)
    ON CONFLICT (application_id, subject_id, component_id) DO UPDATE SET score = EXCLUDED.score, entered_by = EXCLUDED.entered_by, entered_office = EXCLUDED.entered_office, updated_at = now()
    WHERE jupeb.ca_score.score IS DISTINCT FROM EXCLUDED.score;
END $$;

/* a subject's assessment sheet for a session (one class, or all): each student, their score in each part, the total out of the
   parts' maxima, and whether every part is entered */
CREATE OR REPLACE FUNCTION jupeb.ca_sheet(p_session text, p_subject uuid, p_class uuid)
RETURNS TABLE (application_id uuid, application_no text, name text, class_name text, exam_no text, scores jsonb, total numeric, out_of numeric, complete boolean)
LANGUAGE sql STABLE AS $$
    WITH comp AS (SELECT * FROM jupeb.ca_component WHERE session = p_session AND active)
    SELECT a.id, a.application_no, upper(a.surname) || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), k.name, a.exam_no,
           (SELECT coalesce(jsonb_object_agg(cp.id::text, sc.score), '{}'::jsonb) FROM comp cp
              LEFT JOIN jupeb.ca_score sc ON sc.component_id = cp.id AND sc.application_id = a.id AND sc.subject_id = p_subject),
           (SELECT sum(sc.score) FROM jupeb.ca_score sc JOIN comp cp ON cp.id = sc.component_id WHERE sc.application_id = a.id AND sc.subject_id = p_subject),
           (SELECT sum(max_score) FROM comp),
           EXISTS (SELECT 1 FROM comp) AND NOT EXISTS (SELECT 1 FROM comp cp WHERE NOT EXISTS (
               SELECT 1 FROM jupeb.ca_score sc WHERE sc.component_id = cp.id AND sc.application_id = a.id AND sc.subject_id = p_subject AND sc.score IS NOT NULL))
      FROM jupeb.subject_registration r JOIN jupeb.application a ON a.id = r.application_id LEFT JOIN jupeb.class k ON k.id = a.class_id
     WHERE r.subject_id = p_subject AND a.session = p_session AND a.state IN ('STUDENT', 'COMPLETED') AND (p_class IS NULL OR a.class_id = p_class)
     ORDER BY a.surname, a.first_name
$$;

/* each subject's assessment of a session: students, those complete, and whether it is locked */
CREATE OR REPLACE FUNCTION jupeb.ca_progress(p_session text)
RETURNS TABLE (subject_id uuid, code text, title text, students int, complete int, locked_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.code, s.title, count(sh.application_id)::int, count(sh.application_id) FILTER (WHERE sh.complete)::int,
           (SELECT l.locked_at FROM jupeb.ca_lock l WHERE l.session = p_session AND l.subject_id = s.id AND l.unlocked_at IS NULL)
      FROM jupeb.subject s CROSS JOIN LATERAL jupeb.ca_sheet(p_session, s.id, NULL) sh
     GROUP BY s.id, s.code, s.title
     ORDER BY s.title
$$;

-- ── 4 · the examination timetable and admit cards ────────────────────────────────────────────────────────────
CREATE TABLE jupeb.exam_paper (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session          text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    subject_id       uuid NOT NULL REFERENCES jupeb.subject(id),
    board_subject_id uuid NULL REFERENCES jupeb.board_subject(id),
    title            text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 160),
    kind             text NOT NULL DEFAULT 'PAPER' CHECK (kind IN ('CBT', 'PAPER', 'PRACTICAL', 'ORAL')),
    sits_on          date NOT NULL,
    starts_at        time NOT NULL,
    ends_at          time NOT NULL,
    centre           text NULL CHECK (centre IS NULL OR length(centre) <= 160),
    note             text NULL CHECK (note IS NULL OR length(note) <= 300),
    active           boolean NOT NULL DEFAULT true,
    created_by       uuid NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_exam_paper_time CHECK (ends_at > starts_at)
);
CREATE INDEX ix_jupeb_exam_paper ON jupeb.exam_paper (session, sits_on, starts_at) WHERE active;
SELECT audit.attach('jupeb.exam_paper');
COMMENT ON TABLE jupeb.exam_paper IS 'V355: a paper of the Board''s examination timetable — a subject''s (or, of an either/or subject, one option''s), its day, hours and centre; removed, never deleted.';

CREATE OR REPLACE FUNCTION jupeb.exam_paper_subject()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.board_subject_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jupeb.board_subject b WHERE b.id = NEW.board_subject_id AND b.subject_id = NEW.subject_id) THEN
        RAISE EXCEPTION 'JUPEB_EXAM_SUBJECT: that option is not of the subject' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_exam_paper BEFORE INSERT OR UPDATE ON jupeb.exam_paper FOR EACH ROW EXECUTE FUNCTION jupeb.exam_paper_subject();

CREATE TABLE jupeb.exam_timetable (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session      text NOT NULL UNIQUE CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    published_at timestamptz NULL,
    published_by uuid NULL,
    updated_at   timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.exam_timetable');
COMMENT ON TABLE jupeb.exam_timetable IS 'V355: whether the session''s examination timetable is published to the students — their schedules and admit cards wait for it.';

/* a subject on an upload row: the portal's code (ECO), the Board's code (J133) or course prefix (ECN, CRS for an option), or its title */
CREATE OR REPLACE FUNCTION jupeb.subject_named(p text)
RETURNS TABLE (subject_id uuid, board_subject_id uuid)
LANGUAGE sql STABLE AS $$
    SELECT b.subject_id, CASE WHEN (SELECT count(*) FROM jupeb.board_subject y WHERE y.subject_id = b.subject_id) > 1 THEN b.id END
      FROM jupeb.board_subject b WHERE upper(b.code) = upper(btrim(p)) OR upper(b.prefix) = upper(btrim(p)) OR lower(b.title) = lower(btrim(p))
    UNION
    SELECT s.id, NULL FROM jupeb.subject s WHERE upper(s.code) = upper(btrim(p)) OR lower(s.title) = lower(btrim(p))
    LIMIT 1
$$;

/* a time from a sheet: 09:00, 9:00 AM, or a spreadsheet's fraction of a day (0.375) */
CREATE OR REPLACE FUNCTION jupeb.sheet_time(p text)
RETURNS time LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN btrim(coalesce(p, '')) ~ '^0?\.[0-9]+$' THEN (TIME '00:00' + make_interval(secs => round(btrim(p)::numeric * 86400)))
                WHEN btrim(coalesce(p, '')) ~ '^[0-9]{1,2}(:[0-9]{2}){1,2}( ?[AaPp][Mm])?$' THEN btrim(p)::time END
$$;

/* a date from a sheet: 2027-07-26, 26/07/2027, or a spreadsheet's day number (46594) */
CREATE OR REPLACE FUNCTION jupeb.sheet_date(p text)
RETURNS date LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN btrim(coalesce(p, '')) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN left(btrim(p), 10)::date
                WHEN btrim(coalesce(p, '')) ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN to_date(btrim(p), 'DD/MM/YYYY')
                WHEN btrim(coalesce(p, '')) ~ '^[0-9]{5}(\.[0-9]+)?$' THEN DATE '1899-12-30' + floor(btrim(p)::numeric)::int END
$$;

/* the Board's timetable uploaded: one row a paper (subject, paper, kind, date, start, end, centre, note); a row that cannot be
   read is named and left; replacing removes the session's papers first */
CREATE OR REPLACE FUNCTION jupeb.exam_paper_upload(p_session text, p_rows jsonb, p_replace boolean, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_row int; sub record; v_day date; v_start time; v_end time; v_kind text; n_ok int := 0; bad jsonb := '[]'::jsonb;
BEGIN
    IF p_replace THEN UPDATE jupeb.exam_paper SET active = false WHERE session = p_session AND active; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_row := nullif(r->>'row', '')::int;
        SELECT * INTO sub FROM jupeb.subject_named(r->>'subject');
        IF sub.subject_id IS NULL THEN bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'No JUPEB subject is called "' || coalesce(r->>'subject', '') || '".')); CONTINUE; END IF;
        BEGIN
            v_day := jupeb.sheet_date(r->>'date');
            v_start := jupeb.sheet_time(r->>'start');
            v_end := jupeb.sheet_time(r->>'end');
        EXCEPTION WHEN OTHERS THEN v_day := NULL;
        END;
        IF v_day IS NULL OR v_start IS NULL OR v_end IS NULL OR v_end <= v_start THEN
            bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'A paper needs its date (YYYY-MM-DD, DD/MM/YYYY or a date cell) and its start and end times.')); CONTINUE;
        END IF;
        v_kind := upper(btrim(coalesce(nullif(r->>'kind', ''), 'PAPER')));
        IF v_kind NOT IN ('CBT', 'PAPER', 'PRACTICAL', 'ORAL') THEN v_kind := 'PAPER'; END IF;
        IF length(btrim(coalesce(r->>'paper', ''))) < 2 THEN bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'Name the paper.')); CONTINUE; END IF;
        INSERT INTO jupeb.exam_paper (session, subject_id, board_subject_id, title, kind, sits_on, starts_at, ends_at, centre, note, created_by)
        VALUES (p_session, sub.subject_id, sub.board_subject_id, left(btrim(r->>'paper'), 160), v_kind, v_day, v_start, v_end,
                nullif(btrim(coalesce(r->>'centre', '')), ''), nullif(btrim(coalesce(r->>'note', '')), ''), p_actor);
        n_ok := n_ok + 1;
    END LOOP;
    RETURN jsonb_build_object('added', n_ok, 'refused', bad, 'papers', (SELECT count(*) FROM jupeb.exam_paper WHERE session = p_session AND active));
END $$;

/* a student's papers: those of their registered subjects (of an either/or subject, the option they sit — both until they choose),
   once the timetable is published (or always, for the office) */
CREATE OR REPLACE FUNCTION jupeb.exam_schedule(p_app uuid, p_office boolean)
RETURNS TABLE (paper_id uuid, subject_code text, subject_title text, option_title text, title text, kind text, sits_on date, starts_at text, ends_at text, centre text, note text)
LANGUAGE sql STABLE AS $$
    SELECT p.id, s.code, s.title, b.title, p.title, p.kind, p.sits_on, to_char(p.starts_at, 'HH24:MI'), to_char(p.ends_at, 'HH24:MI'), p.centre, p.note
      FROM jupeb.application a JOIN jupeb.subject_registration r ON r.application_id = a.id
      JOIN jupeb.exam_paper p ON p.session = a.session AND p.subject_id = r.subject_id AND p.active
       AND (p.board_subject_id IS NULL OR r.board_subject_id IS NULL OR p.board_subject_id = r.board_subject_id)
      JOIN jupeb.subject s ON s.id = r.subject_id LEFT JOIN jupeb.board_subject b ON b.id = p.board_subject_id
     WHERE a.id = p_app AND (p_office OR EXISTS (SELECT 1 FROM jupeb.exam_timetable t WHERE t.session = a.session AND t.published_at IS NOT NULL))
     ORDER BY p.sits_on, p.starts_at, s.title
$$;

-- ── 5 · the calendar's reminders ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.calendar_reminder (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    uuid NOT NULL REFERENCES jupeb.calendar_event(id),
    audience    text NOT NULL CHECK (audience IN ('STUDENTS', 'OFFICE', 'LECTURERS')),
    days_before int NOT NULL,
    sent        int NOT NULL DEFAULT 0,
    sent_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jupeb_calendar_reminder UNIQUE (event_id, audience, days_before)
);
SELECT audit.exempt('jupeb.calendar_reminder', 'V355: the log of reminders the daily job sent — each one once; no person''s record');
COMMENT ON TABLE jupeb.calendar_reminder IS 'V355: a reminder of a calendar event sent, once: to the students 7 and 1 days before, to the JUPEB Office 14, 7 and 1 days before a deadline, to the lecturers before the assessment is due.';

CREATE OR REPLACE FUNCTION jupeb.event_dates(e jupeb.calendar_event)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT to_char(e.starts_on, 'FMDD Mon YYYY') || CASE WHEN e.ends_on IS NOT NULL AND e.ends_on <> e.starts_on THEN ' – ' || to_char(e.ends_on, 'FMDD Mon YYYY') ELSE '' END
$$;

/* what stands before a deadline, in a line or two, for the JUPEB Office */
CREATE OR REPLACE FUNCTION jupeb.deadline_standing(p_session text, p_marker text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_marker IN ('BOARD_REGISTRATION', 'BOARD_DATA_ALIGNMENT', 'BOARD_PENALTY_ALIGNMENT') THEN
            (SELECT format('Registration with the Board: %s not yet sent (%s of them ready), %s changed since they were sent, %s asked to be corrected.',
                           count(*) FILTER (WHERE stage = 'NOT_SENT'), count(*) FILTER (WHERE stage = 'NOT_SENT' AND ready),
                           count(*) FILTER (WHERE changed), count(*) FILTER (WHERE stage = 'CORRECTION_NEEDED')) FROM jupeb.board_status(p_session))
        WHEN p_marker = 'CA_SUBMISSION' THEN
            (SELECT format('Continuous assessment: %s subject(s) not yet locked; %s student-subject record(s) incomplete.',
                           count(*) FILTER (WHERE locked_at IS NULL AND students > 0), coalesce(sum(students - complete), 0)) FROM jupeb.ca_progress(p_session))
        WHEN p_marker = 'EXAMINATIONS' THEN
            (SELECT format('Clearance: %s of %s active students not yet cleared to sit.', count(*) FILTER (WHERE NOT cleared), count(*)) FROM jupeb.exam_clearance(p_session))
        WHEN p_marker = 'EXAM_TIMETABLE' THEN
            CASE WHEN EXISTS (SELECT 1 FROM jupeb.exam_timetable t WHERE t.session = p_session AND t.published_at IS NOT NULL)
                 THEN 'The examination timetable is published.' ELSE 'The examination timetable is not yet on the portal.' END
    END
$$;

/* the day's reminders, each once: the students of an event they see, 7 and 1 days before; the JUPEB Office's staff of a deadline
   (or a marked event) 14, 7 and 1 days before, with what stands; the lecturers whose subjects' assessment is incomplete, 14, 7 and
   2 days before it is due. Nothing for a planned event, nothing in a quiet run (the tests') but the log. */
CREATE OR REPLACE FUNCTION jupeb.send_calendar_reminders(p_now timestamptz, p_portal text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE today date := (p_now AT TIME ZONE 'Africa/Lagos')::date; ses text := jupeb.current_session(); e jupeb.calendar_event; d int; n int; ann uuid;
        k_students int := 0; k_office int := 0; k_lecturers int := 0; v_due date; v_body text; p record; quiet boolean := coalesce(current_setting('moaum.jupeb_quiet', true), '') = 'on';
        v_link text := coalesce(nullif(btrim(coalesce(p_portal, '')), ''), '');
BEGIN
    FOR e IN SELECT * FROM jupeb.calendar_event WHERE session = ses AND removed_at IS NULL AND NOT planned AND for_students AND starts_on - today IN (7, 1) ORDER BY starts_on, ord LOOP
        d := e.starts_on - today;
        CONTINUE WHEN EXISTS (SELECT 1 FROM jupeb.calendar_reminder r WHERE r.event_id = e.id AND r.audience = 'STUDENTS' AND r.days_before = d);
        INSERT INTO jupeb.announcement (session, audience, title, body, send_email, expires_on, created_office)
        VALUES (ses, 'STUDENTS', left(CASE d WHEN 1 THEN 'Tomorrow: ' ELSE 'In a week: ' END || e.title, 160), e.title || ' — ' || jupeb.event_dates(e) || '.', true,
                coalesce(e.ends_on, e.starts_on), 'jupeb')
        RETURNING id INTO ann;
        n := jupeb.announcement_notify(ann);
        INSERT INTO jupeb.calendar_reminder (event_id, audience, days_before, sent) VALUES (e.id, 'STUDENTS', d, coalesce(n, 0));
        k_students := k_students + 1;
    END LOOP;
    FOR e IN SELECT * FROM jupeb.calendar_event WHERE session = ses AND removed_at IS NULL AND NOT planned AND (deadline_on IS NOT NULL OR marker IS NOT NULL) ORDER BY starts_on, ord LOOP
        v_due := coalesce(e.deadline_on, e.starts_on);
        d := v_due - today;
        CONTINUE WHEN d NOT IN (14, 7, 1) OR EXISTS (SELECT 1 FROM jupeb.calendar_reminder r WHERE r.event_id = e.id AND r.audience = 'OFFICE' AND r.days_before = d);
        v_body := e.title || ' — ' || CASE WHEN e.deadline_on IS NOT NULL THEN 'deadline ' || to_char(e.deadline_on, 'FMDD Mon YYYY') ELSE jupeb.event_dates(e) END
                  || CASE d WHEN 1 THEN ' (tomorrow).' ELSE ' (in ' || d || ' days).' END
                  || coalesce(E'\n' || e.deadline_note, '') || coalesce(E'\n\n' || jupeb.deadline_standing(ses, e.marker), '')
                  || CASE WHEN v_link <> '' THEN E'\n\n' || v_link || '/jupeb/calendar' ELSE '' END;
        n := 0;
        FOR p IN SELECT DISTINCT pe.id, pe.email FROM iam.office_assignment o JOIN iam.person pe ON pe.id = o.person_id
                  WHERE o.office_code = 'jupeb' AND o.valid_from <= today AND (o.valid_to IS NULL OR o.valid_to >= today) AND pe.email IS NOT NULL LOOP
            IF NOT quiet THEN PERFORM platform.queue_notice('EMAIL', p.email, left('JUPEB: ' || e.title, 200), v_body, 'person', p.id); END IF;
            n := n + 1;
        END LOOP;
        INSERT INTO jupeb.calendar_reminder (event_id, audience, days_before, sent) VALUES (e.id, 'OFFICE', d, n);
        k_office := k_office + 1;
    END LOOP;
    /* the lecturers, before the assessment is due: each with the subjects (in their classes) whose scores are not all in */
    FOR e IN SELECT * FROM jupeb.calendar_event WHERE session = ses AND removed_at IS NULL AND NOT planned AND marker = 'CA_SUBMISSION' LOOP
        v_due := coalesce(e.deadline_on, e.starts_on);
        d := v_due - today;
        CONTINUE WHEN d NOT IN (14, 7, 2) OR EXISTS (SELECT 1 FROM jupeb.calendar_reminder r WHERE r.event_id = e.id AND r.audience = 'LECTURERS' AND r.days_before = d);
        n := 0;
        FOR p IN SELECT pe.id, pe.email, string_agg(DISTINCT s.title || ' (' || x.missing || ' to enter)', ', ') AS subjects
                   FROM attendance.instructor i JOIN iam.person pe ON pe.id = i.person_id JOIN jupeb.subject s ON s.id = i.subject_ref
                   CROSS JOIN LATERAL (SELECT count(*) FILTER (WHERE NOT sh.complete) AS missing FROM jupeb.ca_sheet(ses, i.subject_ref, i.class_ref) sh) x
                  WHERE i.context = 'JUPEB' AND i.session = ses AND i.ended_at IS NULL AND x.missing > 0
                    AND NOT EXISTS (SELECT 1 FROM jupeb.ca_lock l WHERE l.session = ses AND l.subject_id = i.subject_ref AND l.unlocked_at IS NULL)
                  GROUP BY pe.id, pe.email LOOP
            IF NOT quiet AND p.email IS NOT NULL THEN
                PERFORM platform.queue_notice('EMAIL', p.email, 'JUPEB continuous assessment due ' || to_char(v_due, 'FMDD Mon YYYY'),
                    'The JUPEB continuous assessment scores are due to the Board on ' || to_char(v_due, 'FMDD Mon YYYY') || '. Still to enter: ' || p.subjects || '.'
                    || CASE WHEN v_link <> '' THEN E'\n\n' || v_link || '/jupeb/teaching' ELSE '' END, 'person', p.id);
            END IF;
            n := n + 1;
        END LOOP;
        INSERT INTO jupeb.calendar_reminder (event_id, audience, days_before, sent) VALUES (e.id, 'LECTURERS', d, n);
        k_lecturers := k_lecturers + 1;
    END LOOP;
    RETURN jsonb_build_object('students', k_students, 'office', k_office, 'lecturers', k_lecturers);
END $$;

ALTER TABLE jupeb.paper DROP CONSTRAINT ck_jupeb_paper_kind;
ALTER TABLE jupeb.paper ADD CONSTRAINT ck_jupeb_paper_kind
    CHECK (kind IN ('RESULT', 'ADMISSION_LETTER', 'ACCEPTANCE_LETTER', 'STATUS_SLIP', 'REGISTRATION_SLIP', 'ACKNOWLEDGEMENT', 'RECEIPT', 'ID_CARD', 'ADMIT_CARD'));

/* V349's facts of each paper, and the admit card's: of a student cleared to sit, once the timetable is published — who they are,
   the examination number, the Board's subjects they sit and the examination's dates (not the papers' hours, so a moved paper
   does not void the card) */
CREATE OR REPLACE FUNCTION jupeb.paper_facts(p_app uuid, p_kind text, p_ref text, p_office boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE a jupeb.application; v_comb text; ck record; base jsonb; gp record; v_acc timestamptz; fr jupeb.fee_reference;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN NULL; END IF;
    v_comb := (SELECT c.code FROM jupeb.combination c WHERE c.id = a.combination_id);
    SELECT * INTO ck FROM jupeb.status_checking(p_app);
    v_acc := jupeb.paid_at(p_app, 'ACCEPTANCE');
    base := jsonb_build_object('name', upper(a.surname) || ' ' || a.first_name || coalesce(' ' || a.middle_name, ''), 'applicationNo', a.application_no,
        'session', a.session, 'programme', CASE a.stream WHEN 'SCIENCE' THEN 'Science' WHEN 'NON_SCIENCE' THEN 'Non-Science' END, 'combination', v_comb);
    IF p_kind = 'ACKNOWLEDGEMENT' THEN
        IF a.submitted_at IS NULL OR a.state IN ('DRAFT', 'WITHDRAWN') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('submittedOn', (a.submitted_at AT TIME ZONE 'Africa/Lagos')::date);
    ELSIF p_kind = 'STATUS_SLIP' THEN
        IF NOT (p_office OR ck.may_check) OR ck.status IS NULL OR a.state = 'WITHDRAWN' THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('admissionStatus', ck.status, 'admissionRef', a.admission_ref);
    ELSIF p_kind = 'ADMISSION_LETTER' THEN
        IF NOT (p_office OR ck.may_check) OR a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('admissionRef', a.admission_ref, 'admittedOn', (a.admission_decided_at AT TIME ZONE 'Africa/Lagos')::date);
    ELSIF p_kind = 'ACCEPTANCE_LETTER' THEN
        IF v_acc IS NULL OR a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('admissionRef', a.admission_ref, 'acceptedOn', (v_acc AT TIME ZONE 'Africa/Lagos')::date);
    ELSIF p_kind = 'REGISTRATION_SLIP' THEN
        IF a.subjects_registered_at IS NULL OR a.state = 'WITHDRAWN' THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('examNo', a.exam_no, 'registeredOn', (a.subjects_registered_at AT TIME ZONE 'Africa/Lagos')::date,
            'subjects', (SELECT coalesce(jsonb_agg(s.title ORDER BY s.title), '[]') FROM jupeb.subject_registration r JOIN jupeb.subject s ON s.id = r.subject_id WHERE r.application_id = p_app));
    ELSIF p_kind = 'RESULT' THEN
        IF NOT jupeb.results_published(a.session) OR NOT EXISTS (SELECT 1 FROM jupeb.result r WHERE r.application_id = p_app) OR a.state = 'WITHDRAWN' THEN RETURN NULL; END IF;
        SELECT * INTO gp FROM jupeb.grade_point(p_app);
        RETURN base || jsonb_build_object('examNo', a.exam_no, 'examination', (jupeb.setting_of(a.session)).exam_month,
            'grades', (SELECT coalesce(jsonb_agg(jsonb_build_object('subject', s.title, 'grade', r.grade) ORDER BY s.title), '[]')
                         FROM jupeb.result r JOIN jupeb.subject s ON s.id = r.subject_id WHERE r.application_id = p_app),
            'gradePoint', trim(to_char(gp.total, 'FM990.##')) || '/' || gp.out_of);
    ELSIF p_kind = 'ID_CARD' THEN
        IF a.state NOT IN ('STUDENT', 'COMPLETED')
           OR NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = p_app AND d.kind = 'PASSPORT') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('validFor', a.session);
    ELSIF p_kind = 'ADMIT_CARD' THEN
        IF a.state <> 'STUDENT' OR a.exam_no IS NULL
           OR NOT EXISTS (SELECT 1 FROM jupeb.exam_timetable t WHERE t.session = a.session AND t.published_at IS NOT NULL)
           OR NOT coalesce((SELECT c.cleared FROM jupeb.exam_clearance(a.session) c WHERE c.application_id = p_app), false) THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('examNo', a.exam_no,
            'subjects', (SELECT coalesce(jsonb_agg(coalesce(b.title, s.title) ORDER BY coalesce(b.title, s.title)), '[]') FROM jupeb.subject_registration r
                          JOIN jupeb.subject s ON s.id = r.subject_id LEFT JOIN jupeb.board_subject b ON b.id = r.board_subject_id WHERE r.application_id = p_app),
            'examinations', (SELECT jupeb.event_dates(e) FROM jupeb.calendar_event e WHERE e.session = a.session AND e.marker = 'EXAMINATIONS' AND e.removed_at IS NULL));
    ELSIF p_kind = 'RECEIPT' THEN
        SELECT * INTO fr FROM jupeb.fee_reference x WHERE x.application_id = p_app AND upper(x.reference) = upper(btrim(coalesce(p_ref, ''))) AND x.confirmed_at IS NOT NULL;
        IF fr.id IS NULL THEN RETURN NULL; END IF;
        RETURN jsonb_build_object('name', base->'name', 'applicationNo', a.application_no, 'session', fr.session, 'reference', fr.reference, 'fee', fr.kind,
            'amount', fr.amount, 'paidOn', (fr.confirmed_at AT TIME ZONE 'Africa/Lagos')::date);
    END IF;
    RETURN NULL;
END $$;

-- ── 6 · practice by topic, and the mock examination ──────────────────────────────────────────────────────────
ALTER TABLE jupeb.practice_question ADD COLUMN unit_id uuid NULL REFERENCES jupeb.subject_unit(id);
ALTER TABLE jupeb.practice_question ADD COLUMN topic_id uuid NULL REFERENCES jupeb.unit_topic(id);
COMMENT ON COLUMN jupeb.practice_question.topic_id IS 'V355: the syllabus topic (of the course, unit_id) the question tests — so a student''s and a class''s weakest topics are seen.';
ALTER TABLE jupeb.practice_test ADD COLUMN kind text NOT NULL DEFAULT 'PRACTICE' CHECK (kind IN ('PRACTICE', 'MOCK'));
ALTER TABLE jupeb.practice_test ADD COLUMN opens_at timestamptz NULL;
ALTER TABLE jupeb.practice_test ADD COLUMN closes_at timestamptz NULL;
ALTER TABLE jupeb.practice_test ADD COLUMN results_released_at timestamptz NULL;
ALTER TABLE jupeb.practice_test ADD CONSTRAINT ck_jupeb_mock
    CHECK (kind <> 'MOCK' OR (attempts_allowed = 1 AND opens_at IS NOT NULL AND closes_at IS NOT NULL AND closes_at > opens_at));
COMMENT ON COLUMN jupeb.practice_test.kind IS 'V355: PRACTICE, or MOCK — one attempt, sat within its window, its results shown only once the JUPEB Office releases them.';

/* a question's course and topic from its row: "course" a course of the test's subject (GRY 001), "topic" the S/N of one of its
   syllabus topics; either blank leaves it untagged */
CREATE OR REPLACE FUNCTION jupeb.practice_tag(p_test uuid, p_row jsonb)
RETURNS TABLE (unit_id uuid, topic_id uuid, problem text)
LANGUAGE plpgsql STABLE AS $$
DECLARE t jupeb.practice_test; u jupeb.subject_unit; v_course text := upper(regexp_replace(btrim(coalesce(p_row->>'course', '')), '^([A-Za-z/]+) ?([0-9]{3}[A-Za-z]?)$', '\1 \2'));
        v_sn text := nullif(rtrim(btrim(coalesce(p_row->>'topic', '')), '.'), ''); v_topic uuid;
BEGIN
    SELECT * INTO t FROM jupeb.practice_test WHERE id = p_test;
    IF v_course = '' THEN RETURN QUERY SELECT NULL::uuid, NULL::uuid, NULL::text; RETURN; END IF;
    SELECT * INTO u FROM jupeb.subject_unit x WHERE x.subject_id = t.subject_id AND x.code = v_course;
    IF u.id IS NULL THEN RETURN QUERY SELECT NULL::uuid, NULL::uuid, (v_course || ' is not a course of the test''s subject.')::text; RETURN; END IF;
    IF v_sn IS NULL THEN RETURN QUERY SELECT u.id, NULL::uuid, NULL::text; RETURN; END IF;
    SELECT x.id INTO v_topic FROM jupeb.unit_topic x WHERE x.unit_id = u.id AND x.sn = v_sn ORDER BY x.ord LIMIT 1;
    IF v_topic IS NULL THEN RETURN QUERY SELECT NULL::uuid, NULL::uuid, (u.code || ' has no topic ' || v_sn || ' in the syllabus.')::text; RETURN; END IF;
    RETURN QUERY SELECT u.id, v_topic, NULL::text;
END $$;

-- one question added (V349), now with its course and topic
CREATE OR REPLACE FUNCTION jupeb.practice_add(p_test uuid, p_row jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_problem text := jupeb.practice_row_problem(p_row); v_id uuid; v_ord int; tg record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_test WHERE id = p_test) THEN RAISE EXCEPTION 'JUPEB_PRACTICE_TEST: no such test' USING ERRCODE = '23514'; END IF;
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: %', v_problem USING ERRCODE = '23514'; END IF;
    SELECT * INTO tg FROM jupeb.practice_tag(p_test, p_row);
    IF tg.problem IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_TOPIC: %', tg.problem USING ERRCODE = '23514'; END IF;
    SELECT coalesce(max(ordinal), 0) + 1 INTO v_ord FROM jupeb.practice_question WHERE test_id = p_test;
    INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, option_c, option_d, option_e, answer, explanation, unit_id, topic_id)
    VALUES (p_test, v_ord, btrim(p_row->>'question'), btrim(p_row->>'a'), btrim(p_row->>'b'), nullif(btrim(coalesce(p_row->>'c', '')), ''),
            nullif(btrim(coalesce(p_row->>'d', '')), ''), nullif(btrim(coalesce(p_row->>'e', '')), ''), upper(left(btrim(p_row->>'answer'), 1)),
            nullif(btrim(coalesce(p_row->>'explanation', '')), ''), tg.unit_id, tg.topic_id)
    RETURNING id INTO v_id;
    UPDATE jupeb.practice_test SET updated_at = now() WHERE id = p_test;
    RETURN v_id;
END $$;

-- a question edited (V349: in place until answered, else a new version), now with its course and topic
CREATE OR REPLACE FUNCTION jupeb.practice_edit(p_test uuid, p_question uuid, p_row jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE q jupeb.practice_question; v_problem text := jupeb.practice_row_problem(p_row); v_id uuid; tg record;
BEGIN
    SELECT * INTO q FROM jupeb.practice_question WHERE id = p_question AND test_id = p_test AND active FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: no such question in this test' USING ERRCODE = '23514'; END IF;
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: %', v_problem USING ERRCODE = '23514'; END IF;
    SELECT * INTO tg FROM jupeb.practice_tag(p_test, p_row);
    IF tg.problem IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_TOPIC: %', tg.problem USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_answer x WHERE x.question_id = q.id)
       AND NOT EXISTS (SELECT 1 FROM jupeb.practice_attempt t WHERE q.id = ANY (t.question_ids)) THEN
        UPDATE jupeb.practice_question SET stem = btrim(p_row->>'question'), option_a = btrim(p_row->>'a'), option_b = btrim(p_row->>'b'),
               option_c = nullif(btrim(coalesce(p_row->>'c', '')), ''), option_d = nullif(btrim(coalesce(p_row->>'d', '')), ''),
               option_e = nullif(btrim(coalesce(p_row->>'e', '')), ''), answer = upper(left(btrim(p_row->>'answer'), 1)),
               explanation = nullif(btrim(coalesce(p_row->>'explanation', '')), ''), unit_id = tg.unit_id, topic_id = tg.topic_id
         WHERE id = q.id;
        v_id := q.id;
    ELSE
        UPDATE jupeb.practice_question SET active = false WHERE id = q.id;
        INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, option_c, option_d, option_e, answer, explanation, unit_id, topic_id)
        VALUES (p_test, q.ordinal, btrim(p_row->>'question'), btrim(p_row->>'a'), btrim(p_row->>'b'), nullif(btrim(coalesce(p_row->>'c', '')), ''),
                nullif(btrim(coalesce(p_row->>'d', '')), ''), nullif(btrim(coalesce(p_row->>'e', '')), ''), upper(left(btrim(p_row->>'answer'), 1)),
                nullif(btrim(coalesce(p_row->>'explanation', '')), ''), tg.unit_id, tg.topic_id)
        RETURNING id INTO v_id;
        INSERT INTO jupeb.practice_image (question_id, filename, content_type, size_bytes, object_id, uploaded_by, uploaded_at)
        SELECT v_id, i.filename, i.content_type, i.size_bytes, i.object_id, i.uploaded_by, i.uploaded_at FROM jupeb.practice_image i WHERE i.question_id = q.id;
        INSERT INTO jupeb.practice_image_blob (question_id, bytes) SELECT v_id, b.bytes FROM jupeb.practice_image_blob b WHERE b.question_id = q.id;
    END IF;
    UPDATE jupeb.practice_test SET updated_at = now() WHERE id = p_test;
    RETURN v_id;
END $$;

-- a bank uploaded (V347), each row now with its course and topic when given; a row naming a course or topic the syllabus lacks is refused
CREATE OR REPLACE FUNCTION jupeb.practice_upload(p_test uuid, p_rows jsonb, p_replace boolean)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_row int; n_ok int := 0; bad jsonb := '[]'::jsonb; v_ans text; v_stem text; v_ord int; tg record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_test WHERE id = p_test) THEN RAISE EXCEPTION 'JUPEB_PRACTICE_TEST: no such test' USING ERRCODE = '23514'; END IF;
    IF p_replace THEN UPDATE jupeb.practice_question SET active = false WHERE test_id = p_test AND active; END IF;
    SELECT coalesce(max(ordinal), 0) INTO v_ord FROM jupeb.practice_question WHERE test_id = p_test;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_row := nullif(r->>'row', '')::int;
        v_stem := nullif(btrim(coalesce(r->>'question', '')), '');
        v_ans := upper(left(btrim(coalesce(r->>'answer', '')), 1));
        IF v_stem IS NULL OR nullif(btrim(coalesce(r->>'a', '')), '') IS NULL OR nullif(btrim(coalesce(r->>'b', '')), '') IS NULL THEN
            bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'A question needs its text and at least options A and B.'));
            CONTINUE;
        END IF;
        IF v_ans NOT IN ('A', 'B', 'C', 'D', 'E') OR nullif(btrim(coalesce(r->>lower(v_ans), '')), '') IS NULL THEN
            bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'The answer must be the letter of one of the options given.'));
            CONTINUE;
        END IF;
        SELECT * INTO tg FROM jupeb.practice_tag(p_test, r);
        IF tg.problem IS NOT NULL THEN
            bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', tg.problem));
            CONTINUE;
        END IF;
        v_ord := v_ord + 1;
        INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, option_c, option_d, option_e, answer, explanation, unit_id, topic_id)
        VALUES (p_test, v_ord, v_stem, btrim(r->>'a'), btrim(r->>'b'), nullif(btrim(coalesce(r->>'c', '')), ''), nullif(btrim(coalesce(r->>'d', '')), ''),
                nullif(btrim(coalesce(r->>'e', '')), ''), v_ans, nullif(btrim(coalesce(r->>'explanation', '')), ''), tg.unit_id, tg.topic_id);
        n_ok := n_ok + 1;
    END LOOP;
    UPDATE jupeb.practice_test SET updated_at = now() WHERE id = p_test;
    RETURN jsonb_build_object('added', n_ok, 'refused', bad, 'active', (SELECT count(*) FROM jupeb.practice_question WHERE test_id = p_test AND active));
END $$;

-- an attempt started (V347), and a mock only within its window
CREATE OR REPLACE FUNCTION jupeb.practice_start(p_app uuid, p_test uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t jupeb.practice_test; a jupeb.application; v_open uuid; v_used int; v_ids uuid[]; v_id uuid; v_ends timestamptz;
BEGIN
    SELECT * INTO t FROM jupeb.practice_test WHERE id = p_test;
    IF t.id IS NULL OR NOT t.open THEN RAISE EXCEPTION 'JUPEB_PRACTICE_CLOSED: the practice test is not open' USING ERRCODE = '23514'; END IF;
    IF t.kind = 'MOCK' AND (now() < t.opens_at OR now() > t.closes_at) THEN
        RAISE EXCEPTION 'JUPEB_MOCK_WINDOW: the mock examination is sat from % to %', to_char(t.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY HH24:MI'),
            to_char(t.closes_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY HH24:MI') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED') THEN
        RAISE EXCEPTION 'JUPEB_PRACTICE_STUDENTS: practice tests are for admitted JUPEB students' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_subjects(p_app) x WHERE x.subject_id = t.subject_id) THEN
        RAISE EXCEPTION 'JUPEB_PRACTICE_SUBJECT: this test is for a subject you do not take' USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v_open FROM jupeb.practice_attempt WHERE test_id = p_test AND application_id = p_app AND submitted_at IS NULL;
    IF v_open IS NOT NULL THEN RETURN v_open; END IF;
    SELECT count(*) INTO v_used FROM jupeb.practice_attempt WHERE test_id = p_test AND application_id = p_app;
    IF v_used >= t.attempts_allowed THEN
        RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPTS: you have used the % attempts this test allows', t.attempts_allowed USING ERRCODE = '23514';
    END IF;
    v_ids := ARRAY(SELECT q.id FROM jupeb.practice_question q WHERE q.test_id = p_test AND q.active ORDER BY random() LIMIT t.questions_per_attempt);
    IF cardinality(v_ids) = 0 THEN RAISE EXCEPTION 'JUPEB_PRACTICE_EMPTY: the test has no questions yet' USING ERRCODE = '23514'; END IF;
    v_ends := now() + make_interval(mins => t.duration_minutes);
    IF t.kind = 'MOCK' THEN v_ends := least(v_ends, t.closes_at); END IF;
    INSERT INTO jupeb.practice_attempt (test_id, application_id, number, question_ids, ends_at, total)
    VALUES (p_test, p_app, v_used + 1, v_ids, v_ends, cardinality(v_ids))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- an attempt's questions (V349) — of a mock not yet released, no score, no marking, no answers
CREATE OR REPLACE FUNCTION jupeb.practice_paper(p_app uuid, p_attempt uuid)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE at jupeb.practice_attempt; t jupeb.practice_test; v_over boolean; v_hidden boolean;
BEGIN
    SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt AND application_id = p_app;
    IF at.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPT: no such attempt' USING ERRCODE = '23514'; END IF;
    IF at.submitted_at IS NULL AND at.ends_at < now() THEN
        PERFORM jupeb.practice_submit(p_app, p_attempt);
        SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt;
    END IF;
    SELECT * INTO t FROM jupeb.practice_test WHERE id = at.test_id;
    v_over := at.submitted_at IS NOT NULL;
    v_hidden := t.kind = 'MOCK' AND t.results_released_at IS NULL;
    RETURN jsonb_build_object(
        'attempt', jsonb_build_object('id', at.id, 'number', at.number, 'startedAt', at.started_at, 'endsAt', at.ends_at, 'submittedAt', at.submitted_at,
                                      'score', CASE WHEN v_hidden THEN NULL ELSE at.score END, 'total', at.total,
                                      'percentage', CASE WHEN v_hidden THEN NULL ELSE at.percentage END, 'answered', at.answered, 'secondsLeft',
                                      greatest(0, floor(extract(epoch FROM at.ends_at - now())))::int, 'resultsHeld', v_over AND v_hidden),
        'test', jsonb_build_object('id', t.id, 'title', t.title, 'instructions', t.instructions, 'durationMinutes', t.duration_minutes, 'showAnswers', t.show_answers AND NOT v_hidden,
                                   'kind', t.kind),
        'questions', (SELECT coalesce(jsonb_agg(
                         jsonb_build_object('id', q.id, 'n', o.n, 'stem', q.stem,
                                            'options', jsonb_strip_nulls(jsonb_build_object('A', q.option_a, 'B', q.option_b, 'C', q.option_c, 'D', q.option_d, 'E', q.option_e)),
                                            'chosen', x.chosen,
                                            'image', EXISTS (SELECT 1 FROM jupeb.practice_image i WHERE i.question_id = q.id))
                         || CASE WHEN v_hidden THEN '{}'::jsonb
                                 WHEN v_over AND t.show_answers THEN jsonb_build_object('answer', q.answer, 'correct', coalesce(x.correct, false), 'explanation', q.explanation)
                                 WHEN v_over THEN jsonb_build_object('correct', coalesce(x.correct, false)) ELSE '{}'::jsonb END
                         ORDER BY o.n), '[]'::jsonb)
                        FROM unnest(at.question_ids) WITH ORDINALITY o(qid, n)
                        JOIN jupeb.practice_question q ON q.id = o.qid
                        LEFT JOIN jupeb.practice_answer x ON x.attempt_id = at.id AND x.question_id = q.id));
END $$;

/* the topic a question tests, named as the syllabus heads it (a sub-topic row's own topic heading above it) */
CREATE OR REPLACE FUNCTION jupeb.topic_label(p_topic uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT u.code || ' · ' || coalesce(x.sn || '. ', '') || coalesce(x.topic, (SELECT y.topic FROM jupeb.unit_topic y WHERE y.unit_id = x.unit_id AND y.ord <= x.ord AND y.topic IS NOT NULL
                                                                                ORDER BY y.ord DESC LIMIT 1), x.sub_topic, '')
      FROM jupeb.unit_topic x JOIN jupeb.subject_unit u ON u.id = x.unit_id WHERE x.id = p_topic
$$;

/* a student's practice by topic: the questions of each topic answered in their submitted attempts and the share right — a mock's
   only once its results are released — weakest first */
CREATE OR REPLACE FUNCTION jupeb.practice_topics(p_app uuid)
RETURNS TABLE (topic_id uuid, subject_code text, label text, answered int, correct int, percentage numeric)
LANGUAGE sql STABLE AS $$
    SELECT q.topic_id, s.code, jupeb.topic_label(q.topic_id), count(*)::int, count(*) FILTER (WHERE x.correct)::int, round(100.0 * count(*) FILTER (WHERE x.correct) / count(*), 1)
      FROM jupeb.practice_attempt at JOIN jupeb.practice_test t ON t.id = at.test_id JOIN jupeb.subject s ON s.id = t.subject_id
      JOIN jupeb.practice_answer x ON x.attempt_id = at.id JOIN jupeb.practice_question q ON q.id = x.question_id
     WHERE at.application_id = p_app AND at.submitted_at IS NOT NULL AND q.topic_id IS NOT NULL AND (t.kind <> 'MOCK' OR t.results_released_at IS NOT NULL)
     GROUP BY q.topic_id, s.code
     ORDER BY 6, 3
$$;

/* a subject's practice by topic across the students of a session (one class, or all) — every attempt, the mocks too */
CREATE OR REPLACE FUNCTION jupeb.practice_topics_class(p_session text, p_subject uuid, p_class uuid)
RETURNS TABLE (topic_id uuid, label text, students int, answered int, percentage numeric)
LANGUAGE sql STABLE AS $$
    SELECT q.topic_id, jupeb.topic_label(q.topic_id), count(DISTINCT at.application_id)::int, count(*)::int, round(100.0 * count(*) FILTER (WHERE x.correct) / count(*), 1)
      FROM jupeb.practice_attempt at JOIN jupeb.practice_test t ON t.id = at.test_id JOIN jupeb.application a ON a.id = at.application_id
      JOIN jupeb.practice_answer x ON x.attempt_id = at.id JOIN jupeb.practice_question q ON q.id = x.question_id
     WHERE t.subject_id = p_subject AND a.session = p_session AND at.submitted_at IS NOT NULL AND q.topic_id IS NOT NULL AND (p_class IS NULL OR a.class_id = p_class)
     GROUP BY q.topic_id
     ORDER BY 5, 2
$$;

-- ── 7 · the read-only and admissions roles reach the new tables ─────────────────────────────────────────────────
GRANT SELECT ON jupeb.board_registration, jupeb.board_registration_event, jupeb.lecture_topic, jupeb.ca_component, jupeb.ca_score, jupeb.ca_lock,
                jupeb.calendar_reminder, jupeb.exam_paper, jupeb.exam_timetable TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.board_registration, jupeb.board_registration_event, jupeb.lecture_topic, jupeb.ca_component, jupeb.ca_score, jupeb.ca_lock,
                jupeb.calendar_reminder, jupeb.exam_paper, jupeb.exam_timetable TO app_admissions;

COMMIT;
