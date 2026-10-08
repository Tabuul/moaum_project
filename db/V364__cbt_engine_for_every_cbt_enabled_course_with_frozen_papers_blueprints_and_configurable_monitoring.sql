-- V364: the University's one CBT engine, opened from GST and EPS to every course the University allows to be examined by
-- computer, with each candidate's paper frozen as it was sat, an optional blueprint for the draw, and the monitoring the
-- examination's own settings say.
--
-- What changes, and why:
--
--   1. A course is examined by CBT only when the catalogue says so (catalogue.course.cbt_enabled, set by the Academic
--      Office, the Registry or Examinations and Records). GST courses and any course already examined by CBT start
--      enabled; no other course is assumed. An examination is created, published and sat only on an enabled course.
--
--   2. Besides the GST and EPS offices, the University's examinations office ('EXAMS') runs CBT examinations of other
--      courses — a department's Examinations Officer for the department's courses, a Faculty Examinations Officer for
--      the faculty's, Examinations and Records for any (the API holds each to its scope). The eligibility of such a
--      candidate is the University's own: registered on the course and the session's fees cleared for examinations
--      (finance.clears, V362). GST and EPS keep their own fee gate (V314).
--
--   3. Each attempt's paper is frozen: the version of every question (assessment.question_version, kept by trigger as
--      a question changes) and the marks it carries are stored on the attempt at the start, and the paper, the
--      scoring and every later reading use that snapshot. Before V364 the paper and the scoring read the bank live:
--      a question retired mid-examination fell out of the candidates' scores while their maximum stood, and a sat
--      question's key, wording or marks could still change what an attempt was worth.
--
--   4. A random paper may follow a blueprint — so many questions of each difficulty, or of each topic — and is refused
--      (on setting and on publication) when the pool cannot satisfy it, with exactly what is short.
--
--   5. The examination's settings: the kind of examination; negative marking (marks deducted for a wrong answer, the
--      total never below nought); back navigation and marking for review; fullscreen; which browser signals are
--      watched and which of them count as violations; the warning, final-warning and action thresholds; how long a
--      candidate may be out of contact before the attempt is submitted with what was saved; a second sign-in that is
--      merely watched; camera proctoring by consent; whether the candidate sees the score on submission (never, by
--      default — the result is published through the office); and whether the result goes onto the score sheet as the
--      examination, as continuous assessment, or not at all.
--
--   6. Answers carry the screen's own sequence number, so a save retried over a poor connection never overwrites a
--      newer answer; a cleared answer is kept as cleared rather than deleted; a question may be marked for review.
--
--   7. The record of an attempt names more of what the screen saw (focus regained, fullscreen re-entered, copy, cut
--      and paste apart, the page left, the device clock moved, proctoring signals) with a severity, the question it
--      happened on and how long it lasted. An event is evidence for the office, never a verdict.
--
--   8. A completed or cancelled examination is archived, never deleted.
--
-- Nothing in the attempts, answers, events, results or score sheets already recorded is changed, except that each
-- existing attempt is given the snapshot of the paper it was drawn (the questions' first versions and their marks as
-- they stood), so the attempts sat before V364 read and score exactly as they did.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V364: the CBT engine opened to every CBT-enabled course, with frozen papers, blueprints and configurable monitoring', true);

-- ── 1 · a course examined by CBT only when the catalogue says so ─────────────────────────────────────────────────

ALTER TABLE catalogue.course ADD COLUMN cbt_enabled boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN catalogue.course.cbt_enabled IS
    'V364: the course may be examined by the University CBT engine. Set by the Academic Office, the Registry or Examinations and Records (the GST and EPS offices for their own courses); GST courses and courses already examined by CBT started enabled. No course is assumed to be a CBT course.';

UPDATE catalogue.course c SET cbt_enabled = true
 WHERE c.kind = 'GST' OR EXISTS (SELECT 1 FROM assessment.cbt_exam e WHERE e.course_code = c.code);

CREATE FUNCTION catalogue.set_cbt_enabled(p_code text, p_on boolean)
RETURNS catalogue.course
LANGUAGE plpgsql AS $$
DECLARE c catalogue.course;
BEGIN
    SELECT * INTO c FROM catalogue.course WHERE upper(code) = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_COURSE_NOT_FOUND: no course %', p_code USING ERRCODE = '23503'; END IF;
    IF p_on AND c.state = 'ENDED' THEN
        RAISE EXCEPTION 'CBT_COURSE_ENDED: % has ended and is not examined', c.code USING ERRCODE = '23514';
    END IF;
    IF NOT p_on AND EXISTS (SELECT 1 FROM assessment.cbt_exam e WHERE e.course_code = c.code AND e.state IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'CLOSED')) THEN
        RAISE EXCEPTION 'CBT_COURSE_IN_USE: % has a CBT examination not yet completed or cancelled', c.code USING ERRCODE = '23514',
            HINT = 'Complete or cancel it first. Examinations already sat keep their record either way.';
    END IF;
    UPDATE catalogue.course SET cbt_enabled = p_on WHERE id = c.id RETURNING * INTO c;
    RETURN c;
END $$;
COMMENT ON FUNCTION catalogue.set_cbt_enabled(text, boolean) IS 'V364: allow or withdraw CBT for a course; withdrawn only when no CBT examination of it is still to be completed.';

-- a General Studies course is the GST (or EPS) office's, and that office examines by CBT (V322): it starts enabled, and may be withdrawn
CREATE FUNCTION catalogue.course_cbt_default()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.kind = 'GST' THEN NEW.cbt_enabled := true; END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_cbt_default BEFORE INSERT ON catalogue.course FOR EACH ROW EXECUTE FUNCTION catalogue.course_cbt_default();

-- ── 2 · the examination's settings ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.cbt_exam DROP CONSTRAINT cbt_exam_office_check;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT cbt_exam_office_check CHECK (office IN ('GST', 'EPS', 'EXAMS'));
ALTER TABLE assessment.cbt_exam DROP CONSTRAINT cbt_exam_second_session_check;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT cbt_exam_second_session_check CHECK (second_session IN ('CONTINUE', 'DENY', 'MONITOR'));

ALTER TABLE assessment.cbt_exam
    ADD COLUMN exam_type           text NOT NULL DEFAULT 'EXAMINATION',
    ADD COLUMN negative_marks      numeric(6,2) NOT NULL DEFAULT 0,
    ADD COLUMN allow_back          boolean NOT NULL DEFAULT true,
    ADD COLUMN allow_review        boolean NOT NULL DEFAULT true,
    ADD COLUMN fullscreen_required boolean NOT NULL DEFAULT true,
    ADD COLUMN detectors           text[] NOT NULL DEFAULT ARRAY['TAB', 'BLUR', 'FULLSCREEN', 'COPY', 'PASTE', 'RIGHT_CLICK', 'NETWORK'],
    ADD COLUMN counted_events      text[] NOT NULL DEFAULT ARRAY['TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT'],
    ADD COLUMN warn_at             int NULL,
    ADD COLUMN final_warn_at       int NULL,
    ADD COLUMN disconnect_minutes  int NULL,
    ADD COLUMN proctoring          text NOT NULL DEFAULT 'NONE',
    ADD COLUMN score_on_submit     boolean NOT NULL DEFAULT false,
    ADD COLUMN sheet_component     text NOT NULL DEFAULT 'EXAM',
    ADD COLUMN blueprint           text NULL,
    ADD COLUMN archived_at         timestamptz NULL;

ALTER TABLE assessment.cbt_exam
    ADD CONSTRAINT ck_cbt_exam_type CHECK (exam_type IN ('EXAMINATION', 'TEST', 'QUIZ', 'MOCK', 'RESIT')),
    ADD CONSTRAINT ck_cbt_exam_negative CHECK (negative_marks >= 0 AND negative_marks <= 100),
    ADD CONSTRAINT ck_cbt_exam_detectors CHECK (detectors <@ ARRAY['TAB', 'BLUR', 'FULLSCREEN', 'COPY', 'PASTE', 'RIGHT_CLICK', 'NETWORK']),
    ADD CONSTRAINT ck_cbt_exam_counted CHECK (counted_events <@ ARRAY['TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT',
                                                                    'RIGHT_CLICK', 'NETWORK_DISCONNECT', 'EXAM_PAGE_EXIT', 'UNUSUAL_NAVIGATION', 'TIME_MANIPULATION_ATTEMPT',
                                                                    'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME', 'PROLONGED_LOOK_AWAY', 'CAMERA_STOPPED']),
    ADD CONSTRAINT ck_cbt_exam_warn_at CHECK (warn_at IS NULL OR (warn_at BETWEEN 1 AND 20 AND warn_at <= coalesce(final_warn_at, violation_limit))),
    ADD CONSTRAINT ck_cbt_exam_final_warn_at CHECK (final_warn_at IS NULL OR (final_warn_at BETWEEN 1 AND 20 AND final_warn_at <= violation_limit)),
    ADD CONSTRAINT ck_cbt_exam_disconnect CHECK (disconnect_minutes IS NULL OR disconnect_minutes BETWEEN 2 AND 120),
    ADD CONSTRAINT ck_cbt_exam_proctoring CHECK (proctoring IN ('NONE', 'CAMERA')),
    ADD CONSTRAINT ck_cbt_exam_sheet_component CHECK (sheet_component IN ('EXAM', 'CA', 'NONE')),
    ADD CONSTRAINT ck_cbt_exam_blueprint CHECK (blueprint IS NULL OR (blueprint IN ('DIFFICULTY', 'TOPIC') AND selection = 'RANDOM')),
    ADD CONSTRAINT ck_cbt_exam_archived CHECK (archived_at IS NULL OR state IN ('COMPLETED', 'CANCELLED'));

COMMENT ON COLUMN assessment.cbt_exam.office IS 'GST, EPS (V322) or, from V364, EXAMS: the University''s examinations office for any other CBT-enabled course (a department''s or faculty''s Examinations Officer, or Examinations and Records, each within their scope).';
COMMENT ON COLUMN assessment.cbt_exam.negative_marks IS 'V364: marks deducted for each question answered wrongly (an answer given that earns nothing); 0 = no negative marking. The total never falls below nought.';
COMMENT ON COLUMN assessment.cbt_exam.allow_back IS 'V364: false = the paper moves forward only; the server refuses changing an answer once a later question has been answered.';
COMMENT ON COLUMN assessment.cbt_exam.allow_review IS 'V364: the candidate may mark questions for review; the final screen lists them.';
COMMENT ON COLUMN assessment.cbt_exam.detectors IS 'V364: the browser signals the examination screen watches: TAB (the tab hidden), BLUR (the window loses focus), FULLSCREEN, COPY, PASTE, RIGHT_CLICK, NETWORK.';
COMMENT ON COLUMN assessment.cbt_exam.counted_events IS 'V364: the recorded events that count towards the violation thresholds. Others are recorded as evidence only.';
COMMENT ON COLUMN assessment.cbt_exam.warn_at IS 'V364: the violation count at which the candidate is first warned (default 1). Below it the record is kept without a warning.';
COMMENT ON COLUMN assessment.cbt_exam.final_warn_at IS 'V364: the violation count at which the candidate is given the final warning (default: the allowed number, violation_limit). One more is acted on by violation_action.';
COMMENT ON COLUMN assessment.cbt_exam.disconnect_minutes IS 'V364: minutes without contact after which the attempt is submitted with the answers saved (DISCONNECT_TIMEOUT); NULL = the attempt waits for the candidate until its time ends.';
COMMENT ON COLUMN assessment.cbt_exam.proctoring IS 'V364: CAMERA = the candidate consents to the camera before writing, and the screen reports face and head signals as proctoring events (evidence, counted only if the office counts them). No video is stored; no microphone, no identity matching.';
COMMENT ON COLUMN assessment.cbt_exam.score_on_submit IS 'V364: the candidate sees the score on submission. Default false: the result is seen only once the office publishes it.';
COMMENT ON COLUMN assessment.cbt_exam.sheet_component IS 'V364: where the result goes on the course''s score sheet — EXAM (the examination component, V322), CA (the continuous assessment), or NONE (a quiz or mock that does not count).';
COMMENT ON COLUMN assessment.cbt_exam.blueprint IS 'V364: a random paper drawn by DIFFICULTY or by TOPIC in the proportions of assessment.cbt_blueprint; NULL = drawn from the whole pool.';

CREATE INDEX ix_cbt_exam_course ON assessment.cbt_exam (course_code, session);

-- ── 3 · the blueprint ──────────────────────────────────────────────────────────────────────────────────────────

CREATE TABLE assessment.cbt_blueprint (
    exam_id   uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    dimension text NOT NULL CHECK (dimension IN ('DIFFICULTY', 'TOPIC')),
    value     text NOT NULL CHECK (btrim(value) <> '' AND length(value) <= 200),
    questions int NOT NULL CHECK (questions BETWEEN 1 AND 1000),
    PRIMARY KEY (exam_id, dimension, value)
);
COMMENT ON TABLE assessment.cbt_blueprint IS 'V364: how many questions of each difficulty (EASY, MEDIUM, HARD) or each topic a random paper draws; the rows of the examination''s own dimension sum to the paper''s size.';
SELECT audit.attach('assessment.cbt_blueprint');

-- ── 4 · every version of a question kept ────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.question ADD COLUMN version int NOT NULL DEFAULT 1, ADD COLUMN archived_at timestamptz NULL;
ALTER TABLE assessment.question ADD CONSTRAINT ck_question_archived CHECK (archived_at IS NULL OR NOT active);
COMMENT ON COLUMN assessment.question.version IS 'V364: raised whenever the wording, options, key, kind, marks or explanation change; each version is kept in assessment.question_version, and an attempt reads the version it was drawn.';
COMMENT ON COLUMN assessment.question.archived_at IS 'V364: archived — retired and out of the bank''s lists; never deleted, and every attempt that drew it keeps it.';

CREATE TABLE assessment.question_version (
    question_id uuid NOT NULL REFERENCES assessment.question(id) ON DELETE CASCADE,
    version     int NOT NULL CHECK (version >= 1),
    kind        text NOT NULL,
    stem        text NOT NULL,
    options     jsonb NOT NULL,
    answers     int[] NOT NULL,
    explanation text NULL,
    marks       int NOT NULL,
    topic       text NULL,
    difficulty  text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  uuid NULL,
    PRIMARY KEY (question_id, version)
);
COMMENT ON TABLE assessment.question_version IS 'V364: each version of a question as it stood — the wording, options, key and marks a candidate was examined on — written once by trigger as the question changes, never edited.';
SELECT audit.exempt('assessment.question_version', 'the frozen wording, options and key of each version of a question (V364), written once by trigger as the question changes and never edited; the change itself is on the audited question');

INSERT INTO assessment.question_version (question_id, version, kind, stem, options, answers, explanation, marks, topic, difficulty, created_at, created_by)
SELECT q.id, 1, q.kind, q.stem, q.options, coalesce(q.answers, ARRAY[q.answer]), q.explanation, q.marks, q.topic, q.difficulty,
       coalesce(q.updated_at, q.authored_at, now()), coalesce(q.updated_by, q.authored_by)
  FROM assessment.question q;

CREATE FUNCTION assessment.question_versioned()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.stem, NEW.options, NEW.answers, NEW.kind, NEW.marks, NEW.explanation) IS DISTINCT FROM (OLD.stem, OLD.options, OLD.answers, OLD.kind, OLD.marks, OLD.explanation) THEN
        NEW.version := OLD.version + 1;
    ELSE
        NEW.version := OLD.version;
    END IF;
    RETURN NEW;
END $$;
-- after trg_question_key (the key normalised first), before the row is written
CREATE TRIGGER trg_question_versioned BEFORE UPDATE ON assessment.question FOR EACH ROW EXECUTE FUNCTION assessment.question_versioned();

CREATE FUNCTION assessment.question_version_kept()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO assessment.question_version (question_id, version, kind, stem, options, answers, explanation, marks, topic, difficulty, created_by)
    VALUES (NEW.id, NEW.version, NEW.kind, NEW.stem, NEW.options, coalesce(NEW.answers, ARRAY[NEW.answer]), NEW.explanation, NEW.marks, NEW.topic, NEW.difficulty,
            coalesce(NEW.updated_by, NEW.authored_by, nullif(current_setting('moaum.actor_id', true), '')::uuid))
    ON CONFLICT (question_id, version) DO NOTHING;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_question_version_kept AFTER INSERT OR UPDATE ON assessment.question FOR EACH ROW EXECUTE FUNCTION assessment.question_version_kept();

CREATE INDEX ix_question_course_active ON assessment.question (course_code, active);

/** the examination of a question that is open to candidates now, if any: a question is not changed under a running examination */
CREATE FUNCTION assessment.question_in_live_exam(p_question uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT e.reference FROM assessment.cbt_exam e JOIN assessment.question q ON q.id = p_question AND q.course_code = e.course_code
     WHERE e.state = 'PUBLISHED' AND e.ends_at > now()
       AND (EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id AND eq.question_id = p_question)
            OR (e.selection = 'RANDOM' AND NOT EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id)))
     LIMIT 1
$$;

-- ── 5 · the attempt's own paper, answers that know their order, the camera's consent ─────────────────────────────

ALTER TABLE assessment.cbt_attempt
    ADD COLUMN question_versions  int[] NULL,
    ADD COLUMN question_marks     int[] NULL,
    ADD COLUMN camera_consent_at  timestamptz NULL,
    ADD COLUMN camera_declined_at timestamptz NULL;
COMMENT ON COLUMN assessment.cbt_attempt.question_versions IS 'V364: the version of each question of the paper as drawn (parallel to question_ids); the paper and the scoring read these versions, so a later edit of the bank changes no attempt.';
COMMENT ON COLUMN assessment.cbt_attempt.question_marks IS 'V364: the marks each question carried on this paper when it was drawn (parallel to question_ids).';

UPDATE assessment.cbt_attempt a SET question_versions = x.v, question_marks = x.m
  FROM (SELECT a2.id,
               array_agg(1 ORDER BY u.n) AS v,
               array_agg(coalesce(eq.marks, q.marks, 1) ORDER BY u.n) AS m
          FROM assessment.cbt_attempt a2
          CROSS JOIN LATERAL unnest(a2.question_ids) WITH ORDINALITY u(qid, n)
          LEFT JOIN assessment.question q ON q.id = u.qid
          LEFT JOIN assessment.cbt_exam_question eq ON eq.exam_id = a2.exam_id AND eq.question_id = u.qid
         GROUP BY a2.id) x
 WHERE x.id = a.id;
UPDATE assessment.cbt_attempt SET question_versions = '{}', question_marks = '{}' WHERE question_versions IS NULL;
ALTER TABLE assessment.cbt_attempt ADD CONSTRAINT ck_cbt_attempt_snapshot
    CHECK (question_versions IS NOT NULL AND question_marks IS NOT NULL
           AND cardinality(question_versions) = cardinality(question_ids) AND cardinality(question_marks) = cardinality(question_ids));

CREATE INDEX ix_cbt_attempt_silent ON assessment.cbt_attempt (last_activity_at) WHERE status = 'IN_PROGRESS';

ALTER TABLE assessment.cbt_answer ADD COLUMN seq bigint NULL, ADD COLUMN flagged boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN assessment.cbt_answer.seq IS 'V364: the examination screen''s own count of its saves of this question; a save that arrives with a lower count than the one kept (a retry over a poor connection) is ignored.';
COMMENT ON COLUMN assessment.cbt_answer.flagged IS 'V364: the candidate marked the question for review.';
COMMENT ON COLUMN assessment.cbt_answer.chosen IS 'The options chosen, by original position; from V364 an answer cleared is kept as an empty set (with its sequence) rather than deleted.';

/** the attempt's paper as drawn — with the keys: the engine's own reading, never the candidate's */
CREATE FUNCTION assessment.cbt_attempt_questions(p_attempt uuid)
RETURNS TABLE (n int, question_id uuid, version int, marks int, kind text, stem text, options jsonb, answers int[])
LANGUAGE sql STABLE AS $$
    SELECT u.n::int, u.qid, u.v, u.m, qv.kind, qv.stem, qv.options, qv.answers
      FROM assessment.cbt_attempt a
      CROSS JOIN LATERAL unnest(a.question_ids, a.question_versions, a.question_marks) WITH ORDINALITY u(qid, v, m, n)
      JOIN assessment.question_version qv ON qv.question_id = u.qid AND qv.version = u.v
     WHERE a.id = p_attempt
$$;

/** the paper as the candidate sees it: the questions in the attempt's order, the options in its order — never a key, never an explanation */
CREATE FUNCTION assessment.cbt_candidate_paper(p_attempt uuid)
RETURNS TABLE (n int, id uuid, kind text, stem text, marks int, options jsonb)
LANGUAGE sql STABLE AS $$
    SELECT x.n, x.question_id, x.kind, x.stem, x.marks,
           (SELECT jsonb_agg(jsonb_build_object('i', o.i - 1, 'text', o.t)
                             ORDER BY CASE WHEN e.randomize_options THEN md5(a.seed::text || x.question_id::text || o.i::text) ELSE lpad(o.i::text, 4, '0') END)
              FROM jsonb_array_elements_text(x.options) WITH ORDINALITY o(t, i))
      FROM assessment.cbt_attempt a JOIN assessment.cbt_exam e ON e.id = a.exam_id
      CROSS JOIN LATERAL assessment.cbt_attempt_questions(a.id) x
     WHERE a.id = p_attempt
     ORDER BY x.n
$$;
COMMENT ON FUNCTION assessment.cbt_candidate_paper(uuid) IS 'V364: the frozen paper as the candidate sees it; selects neither the key nor the explanation.';

-- ── 6 · the record of an attempt ────────────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.cbt_event DROP CONSTRAINT cbt_event_kind_check;
ALTER TABLE assessment.cbt_event ADD CONSTRAINT cbt_event_kind_check CHECK (kind IN (
    'STARTED', 'RESUMED', 'TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'NETWORK_DISCONNECT', 'RECONNECTED', 'MULTIPLE_LOGIN', 'SESSION_REPLACED',
    'COPY_PASTE', 'CONTEXT_MENU', 'WARNING', 'FINAL_WARNING', 'AUTO_SUBMITTED', 'TERMINATED', 'SUBMITTED', 'TIME_EXPIRED', 'AMENDED',
    -- V364
    'WINDOW_FOCUS', 'FULLSCREEN_ENTER', 'COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT', 'RIGHT_CLICK', 'UNUSUAL_NAVIGATION', 'TIME_MANIPULATION_ATTEMPT',
    'EXAM_PAGE_EXIT', 'DISCONNECT_TIMEOUT', 'CAMERA_CONSENTED', 'CAMERA_DECLINED', 'CAMERA_STOPPED', 'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME',
    'HEAD_POSE_LEFT', 'HEAD_POSE_RIGHT', 'HEAD_POSE_UP', 'HEAD_POSE_DOWN', 'PROLONGED_LOOK_AWAY'));
ALTER TABLE assessment.cbt_event
    ADD COLUMN severity    text NULL CHECK (severity IS NULL OR severity IN ('INFO', 'LOW', 'MEDIUM', 'HIGH')),
    ADD COLUMN question_no int NULL CHECK (question_no IS NULL OR question_no BETWEEN 1 AND 1000),
    ADD COLUMN duration_ms int NULL CHECK (duration_ms IS NULL OR duration_ms >= 0);
COMMENT ON COLUMN assessment.cbt_event.severity IS 'V364: how much weight a reviewer might give the event — a reading aid for the office, never a verdict (assessment.cbt_event_severity).';
CREATE INDEX ix_cbt_event_exam_kind ON assessment.cbt_event (exam_id, kind);

CREATE FUNCTION assessment.cbt_event_severity(p_kind text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_kind IN ('MULTIPLE_LOGIN', 'MULTIPLE_FACES', 'TIME_MANIPULATION_ATTEMPT', 'CAMERA_DECLINED', 'TERMINATED', 'AUTO_SUBMITTED') THEN 'HIGH'
        WHEN p_kind IN ('TAB_SWITCH', 'FULLSCREEN_EXIT', 'PASTE_ATTEMPT', 'COPY_PASTE', 'UNUSUAL_NAVIGATION', 'EXAM_PAGE_EXIT', 'FACE_NOT_DETECTED', 'FACE_OUT_OF_FRAME',
                        'PROLONGED_LOOK_AWAY', 'CAMERA_STOPPED', 'DISCONNECT_TIMEOUT', 'FINAL_WARNING', 'SESSION_REPLACED') THEN 'MEDIUM'
        WHEN p_kind IN ('WINDOW_BLUR', 'COPY_ATTEMPT', 'CUT_ATTEMPT', 'RIGHT_CLICK', 'CONTEXT_MENU', 'NETWORK_DISCONNECT', 'HEAD_POSE_LEFT', 'HEAD_POSE_RIGHT',
                        'HEAD_POSE_UP', 'HEAD_POSE_DOWN', 'WARNING') THEN 'LOW'
        ELSE 'INFO' END
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_log(p_attempt uuid, p_kind text, p_violation boolean, p_detail text, p_ip text)
RETURNS void
LANGUAGE sql AS $$
    INSERT INTO assessment.cbt_event (attempt_id, exam_id, kind, violation, detail, ip, severity)
    SELECT a.id, a.exam_id, p_kind, p_violation, nullif(btrim(coalesce(p_detail, '')), ''), p_ip, assessment.cbt_event_severity(p_kind)
      FROM assessment.cbt_attempt a WHERE a.id = p_attempt
$$;

CREATE FUNCTION assessment.cbt_log(p_attempt uuid, p_kind text, p_violation boolean, p_detail text, p_ip text, p_question int, p_ms int)
RETURNS void
LANGUAGE sql AS $$
    INSERT INTO assessment.cbt_event (attempt_id, exam_id, kind, violation, detail, ip, severity, question_no, duration_ms)
    SELECT a.id, a.exam_id, p_kind, p_violation, nullif(btrim(coalesce(p_detail, '')), ''), p_ip, assessment.cbt_event_severity(p_kind),
           CASE WHEN p_question BETWEEN 1 AND 1000 THEN p_question END, CASE WHEN p_ms >= 0 THEN p_ms END
      FROM assessment.cbt_attempt a WHERE a.id = p_attempt
$$;

-- ── 7 · creating and configuring an examination ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_new_exam(p_office text, p_offering uuid, p_title text, p_instructions text, p_duration integer, p_total integer,
                                                   p_selection text, p_random_q boolean, p_random_o boolean, p_pass numeric, p_attempts integer, p_security text,
                                                   p_venue text, p_violation_limit integer, p_violation_action text, p_second_session text,
                                                   p_starts timestamp with time zone, p_ends timestamp with time zone)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE o record; e assessment.cbt_exam; v_office text := upper(btrim(coalesce(p_office, '')));
BEGIN
    SELECT ofr.id, ofr.course_code, ofr.session, ofr.semester, c.kind, c.general_office, c.title AS course_title, c.cbt_enabled, c.state AS course_state
      INTO o FROM catalogue.offering ofr JOIN catalogue.course c ON c.code = ofr.course_code WHERE ofr.id = p_offering;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_OFFERING_NOT_FOUND: no such course offering' USING ERRCODE = '23503'; END IF;
    -- a GST course is its office's (GST or EPS); every other course is examined by the University's examinations office
    IF (o.kind = 'GST' AND coalesce(o.general_office, 'GST') <> v_office) OR (o.kind <> 'GST' AND v_office <> 'EXAMS') THEN
        RAISE EXCEPTION 'CBT_NOT_OFFICE_COURSE: % is not a course of the % office', o.course_code, v_office USING ERRCODE = '23514',
            HINT = 'An office examines its own courses: GST and EPS their General Studies courses, the examinations office every other course.';
    END IF;
    IF NOT o.cbt_enabled THEN
        RAISE EXCEPTION 'CBT_COURSE_NOT_ENABLED: % is not a CBT course', o.course_code USING ERRCODE = '23514',
            HINT = 'The Academic Office, the Registry or Examinations and Records allows a course to be examined by CBT on the catalogue.';
    END IF;
    INSERT INTO assessment.cbt_exam (reference, office, course_code, offering_id, session, semester, title, instructions, duration_minutes, total_questions,
                                     selection, randomize_questions, randomize_options, pass_mark, attempt_limit, security_mode, venue, violation_limit,
                                     violation_action, second_session, starts_at, ends_at, created_by, created_office)
    VALUES ('CBT/' || replace(o.session, '/', '-') || '/' || lpad(platform.next_number('cbt_exam', 'UNIVERSITY', o.session)::text, 5, '0'),
            v_office, o.course_code, o.id, o.session, o.semester, btrim(p_title), nullif(btrim(coalesce(p_instructions, '')), ''),
            coalesce(p_duration, 60), coalesce(p_total, 0), coalesce(upper(p_selection), 'FIXED'), coalesce(p_random_q, true), coalesce(p_random_o, false),
            coalesce(p_pass, 40), coalesce(p_attempts, 1), coalesce(upper(p_security), 'STANDARD'), coalesce(upper(p_venue), 'REMOTE'),
            coalesce(p_violation_limit, 2), coalesce(upper(p_violation_action), 'WARN'), coalesce(upper(p_second_session), 'CONTINUE'),
            p_starts, p_ends, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING * INTO e;
    RETURN e;
END $$;

/** V364: the examination's further settings, each key applied only when present; a published examination keeps its rules */
CREATE FUNCTION assessment.cbt_configure(p_exam uuid, p jsonb)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_bad text;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RETURN e; END IF;
    IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN
        RAISE EXCEPTION 'CBT_STATE: the settings of a % examination are kept as they were published', lower(e.state) USING ERRCODE = '23514';
    END IF;
    IF p ? 'examType' AND upper(p->>'examType') NOT IN ('EXAMINATION', 'TEST', 'QUIZ', 'MOCK', 'RESIT') THEN
        RAISE EXCEPTION 'CBT_SETTING: an examination is an Examination, a Test, a Quiz, a Mock or a Resit' USING ERRCODE = '23514';
    END IF;
    IF p ? 'negativeMarks' AND ((p->>'negativeMarks')::numeric < 0 OR (p->>'negativeMarks')::numeric > 100) THEN
        RAISE EXCEPTION 'CBT_SETTING: negative marking deducts between 0 and 100 marks for a wrong answer' USING ERRCODE = '23514';
    END IF;
    IF p ? 'detectors' THEN
        SELECT string_agg(x, ', ') INTO v_bad FROM jsonb_array_elements_text(p->'detectors') x
         WHERE upper(x) NOT IN ('TAB', 'BLUR', 'FULLSCREEN', 'COPY', 'PASTE', 'RIGHT_CLICK', 'NETWORK');
        IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CBT_SETTING: % is not a signal the screen watches', v_bad USING ERRCODE = '23514'; END IF;
    END IF;
    IF p ? 'countedEvents' THEN
        SELECT string_agg(x, ', ') INTO v_bad FROM jsonb_array_elements_text(p->'countedEvents') x
         WHERE upper(x) NOT IN ('TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT', 'RIGHT_CLICK', 'NETWORK_DISCONNECT',
                                'EXAM_PAGE_EXIT', 'UNUSUAL_NAVIGATION', 'TIME_MANIPULATION_ATTEMPT', 'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME',
                                'PROLONGED_LOOK_AWAY', 'CAMERA_STOPPED');
        IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'CBT_SETTING: % is not an event that can count as a violation', v_bad USING ERRCODE = '23514'; END IF;
    END IF;
    IF p ? 'sheetComponent' AND upper(p->>'sheetComponent') NOT IN ('EXAM', 'CA', 'NONE') THEN
        RAISE EXCEPTION 'CBT_SETTING: the result goes onto the score sheet as the Examination, as continuous assessment, or not at all' USING ERRCODE = '23514';
    END IF;
    IF p ? 'proctoring' AND upper(p->>'proctoring') NOT IN ('NONE', 'CAMERA') THEN
        RAISE EXCEPTION 'CBT_SETTING: proctoring is NONE or CAMERA' USING ERRCODE = '23514';
    END IF;
    IF p ? 'disconnectMinutes' AND jsonb_typeof(p->'disconnectMinutes') = 'number' AND (p->>'disconnectMinutes')::int NOT BETWEEN 2 AND 120 THEN
        RAISE EXCEPTION 'CBT_SETTING: an attempt out of contact is submitted after between 2 and 120 minutes, or never' USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.cbt_exam SET
        exam_type = CASE WHEN p ? 'examType' THEN upper(p->>'examType') ELSE exam_type END,
        negative_marks = CASE WHEN p ? 'negativeMarks' THEN round((p->>'negativeMarks')::numeric, 2) ELSE negative_marks END,
        allow_back = CASE WHEN p ? 'allowBack' THEN (p->>'allowBack')::boolean ELSE allow_back END,
        allow_review = CASE WHEN p ? 'allowReview' THEN (p->>'allowReview')::boolean ELSE allow_review END,
        fullscreen_required = CASE WHEN p ? 'fullscreenRequired' THEN (p->>'fullscreenRequired')::boolean ELSE fullscreen_required END,
        detectors = CASE WHEN p ? 'detectors' THEN ARRAY(SELECT DISTINCT upper(x) FROM jsonb_array_elements_text(p->'detectors') x ORDER BY 1) ELSE detectors END,
        counted_events = CASE WHEN p ? 'countedEvents' THEN ARRAY(SELECT DISTINCT upper(x) FROM jsonb_array_elements_text(p->'countedEvents') x ORDER BY 1) ELSE counted_events END,
        warn_at = CASE WHEN p ? 'warnAt' THEN (p->>'warnAt')::int ELSE warn_at END,
        final_warn_at = CASE WHEN p ? 'finalWarnAt' THEN (p->>'finalWarnAt')::int ELSE final_warn_at END,
        disconnect_minutes = CASE WHEN p ? 'disconnectMinutes' THEN (p->>'disconnectMinutes')::int ELSE disconnect_minutes END,
        proctoring = CASE WHEN p ? 'proctoring' THEN upper(p->>'proctoring') ELSE proctoring END,
        score_on_submit = CASE WHEN p ? 'scoreOnSubmit' THEN (p->>'scoreOnSubmit')::boolean ELSE score_on_submit END,
        sheet_component = CASE WHEN p ? 'sheetComponent' THEN upper(p->>'sheetComponent') ELSE sheet_component END
     WHERE id = e.id RETURNING * INTO e;
    -- a forward-only paper has nothing to mark for review: it is never revisited
    IF NOT e.allow_back AND e.allow_review THEN
        UPDATE assessment.cbt_exam SET allow_review = false WHERE id = e.id RETURNING * INTO e;
    END IF;
    RETURN e;
END $$;
COMMENT ON FUNCTION assessment.cbt_configure(uuid, jsonb) IS 'V364: the further settings of a draft or scheduled examination (examType, negativeMarks, allowBack, allowReview, fullscreenRequired, detectors, countedEvents, warnAt, finalWarnAt, disconnectMinutes, proctoring, scoreOnSubmit, sheetComponent); each applied only when present.';

-- ── 8 · the blueprint: set, judged, drawn ───────────────────────────────────────────────────────────────────────

/** what stops the blueprint being satisfied, or NULL: the rows sum to the paper, and each row's part of the pool holds enough */
CREATE FUNCTION assessment.cbt_blueprint_problem(p_exam uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    b AS (SELECT bp.* FROM assessment.cbt_blueprint bp JOIN e ON bp.exam_id = e.id AND bp.dimension = e.blueprint),
    pool AS (SELECT q.difficulty, lower(btrim(coalesce(q.topic, ''))) AS topic
               FROM assessment.cbt_pool(p_exam) p JOIN assessment.question q ON q.id = p.question_id),
    have AS (SELECT b.value, b.questions,
                    (SELECT count(*) FROM pool, e WHERE CASE e.blueprint WHEN 'DIFFICULTY' THEN pool.difficulty = upper(b.value) ELSE pool.topic = lower(btrim(b.value)) END) AS n
               FROM b)
    SELECT CASE
        WHEN (SELECT blueprint FROM e) IS NULL THEN NULL
        WHEN NOT EXISTS (SELECT 1 FROM b) THEN 'CBT_BLUEPRINT_EMPTY: the blueprint names no ' || lower((SELECT blueprint FROM e)) || ' to draw from'
        WHEN (SELECT sum(questions) FROM b) <> (SELECT total_questions FROM e)
            THEN format('CBT_BLUEPRINT_TOTAL: the blueprint draws %s questions; the paper draws %s', (SELECT sum(questions) FROM b), (SELECT total_questions FROM e))
        WHEN EXISTS (SELECT 1 FROM have WHERE n < questions)
            THEN 'CBT_BLUEPRINT_SHORT: the pool cannot satisfy the blueprint — '
                 || (SELECT string_agg(format('%s needs %s, the pool holds %s', initcap(value), questions, n), '; ' ORDER BY value) FROM have WHERE n < questions)
        END
$$;

CREATE FUNCTION assessment.cbt_set_blueprint(p_exam uuid, p_dimension text, p_rows jsonb)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_dim text := nullif(upper(btrim(coalesce(p_dimension, ''))), ''); r jsonb; v_problem text;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: the blueprint of a % examination is not changed', lower(e.state) USING ERRCODE = '23514'; END IF;
    DELETE FROM assessment.cbt_blueprint WHERE exam_id = e.id;
    IF v_dim IS NULL THEN
        UPDATE assessment.cbt_exam SET blueprint = NULL WHERE id = e.id RETURNING * INTO e;
        RETURN e;
    END IF;
    IF v_dim NOT IN ('DIFFICULTY', 'TOPIC') THEN RAISE EXCEPTION 'CBT_BLUEPRINT: a blueprint is by difficulty or by topic' USING ERRCODE = '23514'; END IF;
    IF e.selection <> 'RANDOM' THEN RAISE EXCEPTION 'CBT_BLUEPRINT_FIXED: a fixed paper has no draw to plan; a blueprint is for a random paper' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        CONTINUE WHEN coalesce((r->>'questions')::int, 0) = 0;
        IF v_dim = 'DIFFICULTY' AND upper(r->>'value') NOT IN ('EASY', 'MEDIUM', 'HARD') THEN
            RAISE EXCEPTION 'CBT_BLUEPRINT: a difficulty is Easy, Medium or Hard' USING ERRCODE = '23514';
        END IF;
        INSERT INTO assessment.cbt_blueprint (exam_id, dimension, value, questions)
        VALUES (e.id, v_dim, CASE WHEN v_dim = 'DIFFICULTY' THEN upper(r->>'value') ELSE btrim(r->>'value') END, (r->>'questions')::int);
    END LOOP;
    UPDATE assessment.cbt_exam SET blueprint = v_dim WHERE id = e.id RETURNING * INTO e;
    v_problem := assessment.cbt_blueprint_problem(e.id);
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION '%', v_problem USING ERRCODE = '23514', HINT = 'Add questions to the bank, or change the blueprint.'; END IF;
    RETURN e;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_paper_ready(p_exam uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; n int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    SELECT count(*) INTO n FROM assessment.cbt_pool(p_exam);
    IF e.selection = 'FIXED' THEN
        IF n = 0 THEN RETURN 'CBT_PAPER_EMPTY: the paper has no questions'; END IF;
    ELSE
        IF e.total_questions <= 0 THEN RETURN 'CBT_PAPER_SIZE: a random paper says how many questions are drawn'; END IF;
        IF n < e.total_questions THEN
            RETURN format('CBT_POOL_TOO_SMALL: Insufficient eligible questions. This examination requires %s questions but only %s valid questions are available.', e.total_questions, n);
        END IF;
        RETURN assessment.cbt_blueprint_problem(p_exam);
    END IF;
    RETURN NULL;
END $$;

/** the questions an attempt draws: the fixed paper in order, or a random draw of the paper's size — by the blueprint when there is one — in a
 *  random order when asked; the seed is the attempt's, so the draw is the attempt's own and never changes */
CREATE OR REPLACE FUNCTION assessment.cbt_paper(p_exam uuid, p_seed integer)
RETURNS uuid[]
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    pool AS (SELECT pl.question_id, pl.ordinal, q.difficulty, lower(btrim(coalesce(q.topic, ''))) AS topic, md5(p_seed::text || pl.question_id::text) AS draw
               FROM assessment.cbt_pool(p_exam) pl JOIN assessment.question q ON q.id = pl.question_id),
    drawn AS (
        SELECT x.question_id, x.ordinal
          FROM e JOIN assessment.cbt_blueprint b ON b.exam_id = e.id AND b.dimension = e.blueprint
          CROSS JOIN LATERAL (SELECT p.question_id, p.ordinal FROM pool p
                               WHERE CASE b.dimension WHEN 'DIFFICULTY' THEN p.difficulty = upper(b.value) ELSE p.topic = lower(btrim(b.value)) END
                               ORDER BY p.draw LIMIT b.questions) x
         WHERE e.selection = 'RANDOM' AND e.blueprint IS NOT NULL
        UNION ALL
        SELECT p.question_id, p.ordinal
          FROM e CROSS JOIN LATERAL (SELECT pool.question_id, pool.ordinal FROM pool
                                      ORDER BY CASE WHEN e.selection = 'RANDOM' THEN pool.draw ELSE lpad(pool.ordinal::text, 9, '0') END
                                      LIMIT CASE WHEN e.selection = 'RANDOM' THEN e.total_questions ELSE NULL END) p
         WHERE NOT (e.selection = 'RANDOM' AND e.blueprint IS NOT NULL))
    SELECT coalesce(array_agg(d.question_id ORDER BY CASE WHEN e.selection = 'RANDOM' OR e.randomize_questions THEN md5(p_seed::text || d.question_id::text)
                                                          ELSE lpad(d.ordinal::text, 9, '0') END), ARRAY[]::uuid[])
      FROM e, drawn d
$$;

-- ── 9 · eligibility: the course, the registration, the fees ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_eligibility(p_exam uuid, p_student uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; st people.student; v_gate text; v_ready text; n int; v_enabled boolean;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT cbt_enabled INTO v_enabled FROM catalogue.course WHERE code = e.course_code;
    IF NOT coalesce(v_enabled, false) THEN RETURN format('CBT_COURSE_NOT_ENABLED: %s is not a CBT course', e.course_code); END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF NOT FOUND OR st.status NOT IN ('ACTIVE', 'ADMITTED', 'PROBATION') THEN
        RETURN 'CBT_STUDENT_INACTIVE: only an active student sits an examination';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE cr.student_id = p_student AND en.offering_id = e.offering_id
                      AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
        RETURN format('CBT_COURSE_NOT_REGISTERED: %s is not on your submitted registration for %s', e.course_code, e.session);
    END IF;
    IF e.office IN ('GST', 'EPS') THEN
        v_gate := registration.gst_gate(p_student, e.session, e.course_code);
        IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    ELSIF NOT coalesce(finance.clears(p_student, e.session, 'EXAMINATION'), false) THEN
        RETURN format('CBT_FEES_NOT_CLEARED: your %s school fees are not cleared for examinations', e.session);
    END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND student_id = p_student AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $$;

-- ── 10 · the start: one attempt, its own draw, its paper frozen ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; a assessment.cbt_attempt; v_why text; v_seed int; v_paper uuid[]; v_versions int[]; v_marks int[]; v_n int;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(p_exam::text || ':' || p_student::text));
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    SELECT * INTO a FROM assessment.cbt_attempt WHERE exam_id = p_exam AND student_id = p_student AND status = 'IN_PROGRESS';
    IF FOUND THEN
        IF a.ends_at <= now() THEN
            a := assessment.cbt_finalize(a.id, 'TIME_EXPIRED', 'time expired before the candidate returned');
            -- fall through: the window may still allow another attempt
        ELSE
            IF e.second_session = 'DENY' THEN
                PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', true, 'a second sign-in was refused', p_ip);
                UPDATE assessment.cbt_attempt SET violations = violations + 1, last_activity_at = now() WHERE id = a.id;
                RAISE EXCEPTION 'CBT_SECOND_SESSION_DENIED: your examination is already open on another browser or device' USING ERRCODE = '23514',
                    HINT = 'Return to the screen where you started it. The attempt is recorded.';
            END IF;
            IF e.second_session = 'MONITOR' THEN
                -- V364: allowed and watched — both screens hold the attempt; the office sees the second sign-in
                PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', false, 'the examination was opened again; allowed and recorded', p_ip);
                UPDATE assessment.cbt_attempt SET last_activity_at = now() WHERE id = a.id RETURNING * INTO a;
                RETURN a;
            END IF;
            PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', true, 'the examination was opened again; the earlier screen is replaced', p_ip);
            PERFORM assessment.cbt_log(a.id, 'SESSION_REPLACED', false, 'the earlier screen no longer holds the attempt', p_ip);
            UPDATE assessment.cbt_attempt SET token = gen_random_uuid(), violations = violations + 1, last_activity_at = now(), ip = coalesce(p_ip, ip), user_agent = coalesce(p_agent, user_agent)
             WHERE id = a.id RETURNING * INTO a;
            RETURN a;
        END IF;
    END IF;
    v_why := assessment.cbt_eligibility(p_exam, p_student);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514', HINT = 'Eligibility is judged on the record: the registration, the payments on the ledger, the examination window.';
    END IF;
    -- the draw's seed from the server's cryptographic source, never the browser's
    v_seed := (('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 7))::bit(28))::int;
    v_paper := assessment.cbt_paper(p_exam, v_seed);
    IF coalesce(cardinality(v_paper), 0) = 0 THEN RAISE EXCEPTION 'CBT_PAPER_EMPTY: the paper has no questions' USING ERRCODE = '23514'; END IF;
    -- the paper frozen: each question's version and its marks on this paper, as they stand now
    SELECT array_agg(q.version ORDER BY u.n), array_agg(p.marks ORDER BY u.n) INTO v_versions, v_marks
      FROM unnest(v_paper) WITH ORDINALITY u(qid, n)
      JOIN assessment.question q ON q.id = u.qid
      JOIN assessment.cbt_pool(p_exam) p ON p.question_id = u.qid;
    IF coalesce(cardinality(v_versions), 0) <> cardinality(v_paper) THEN
        RAISE EXCEPTION 'CBT_PAPER_CHANGED: the paper changed as the attempt began; start again' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND student_id = p_student;
    INSERT INTO assessment.cbt_attempt (exam_id, student_id, number, ends_at, question_ids, question_versions, question_marks, seed, max_marks, ip, user_agent)
    VALUES (p_exam, p_student, v_n + 1, least(now() + make_interval(mins => e.duration_minutes), e.ends_at), v_paper, v_versions, v_marks, v_seed,
            greatest((SELECT sum(m) FROM unnest(v_marks) m), 1), p_ip, p_agent)
    RETURNING * INTO a;
    PERFORM assessment.cbt_log(a.id, 'STARTED', false, format('%s questions, %s marks, ends %s', cardinality(v_paper), a.max_marks, to_char(a.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI:SS')), p_ip);
    RETURN a;
END $$;

-- ── 11 · the camera's consent ───────────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION assessment.cbt_camera(p_attempt uuid, p_token uuid, p_consent boolean, p_ip text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam;
BEGIN
    a := assessment.cbt_touch(p_attempt, p_token);
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    IF e.proctoring <> 'CAMERA' OR a.status <> 'IN_PROGRESS' THEN RETURN a; END IF;
    IF p_consent THEN
        IF a.camera_consent_at IS NULL THEN
            UPDATE assessment.cbt_attempt SET camera_consent_at = now() WHERE id = a.id RETURNING * INTO a;
            PERFORM assessment.cbt_log(a.id, 'CAMERA_CONSENTED', false, 'the candidate consented to the camera for this examination', p_ip);
        END IF;
    ELSE
        UPDATE assessment.cbt_attempt SET camera_declined_at = now() WHERE id = a.id RETURNING * INTO a;
        PERFORM assessment.cbt_log(a.id, 'CAMERA_DECLINED', false, 'the candidate did not consent to the camera, or the camera could not be used', p_ip);
    END IF;
    RETURN a;
END $$;
COMMENT ON FUNCTION assessment.cbt_camera(uuid, uuid, boolean, text) IS 'V364: a proctored examination''s consent (or its refusal), recorded on the attempt and its record. Without consent no answer is saved.';

-- ── 12 · answers saved in order, cleared answers kept, questions marked for review ──────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_save_answers(p_attempt uuid, p_token uuid, p_answers jsonb)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; r jsonb; q uuid; ch int[]; n int; v_pos int; v_seq bigint; v_flag boolean; v_last int;
        old_chosen int[]; old_seq bigint; old_found boolean;
BEGIN
    a := assessment.cbt_touch(p_attempt, p_token);
    IF a.status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION 'CBT_ATTEMPT_CLOSED: the attempt is %', lower(replace(a.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    IF e.proctoring = 'CAMERA' AND a.camera_consent_at IS NULL THEN
        RAISE EXCEPTION 'CBT_CONSENT_REQUIRED: this examination is sat with the camera on, by your consent' USING ERRCODE = '23514',
            HINT = 'Give your consent on the examination screen, or speak to the office about sitting it another way.';
    END IF;
    IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' THEN RETURN a; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
        q := (r ->> 'q')::uuid;
        v_pos := array_position(a.question_ids, q);
        IF v_pos IS NULL THEN
            RAISE EXCEPTION 'CBT_QUESTION_NOT_ON_PAPER: that question is not on this paper' USING ERRCODE = '23514';
        END IF;
        v_seq := CASE WHEN jsonb_typeof(r -> 'seq') = 'number' THEN (r ->> 'seq')::bigint END;
        v_flag := CASE WHEN e.allow_review AND jsonb_typeof(r -> 'flag') = 'boolean' THEN (r ->> 'flag')::boolean END;
        SELECT x.chosen, x.seq, true INTO old_chosen, old_seq, old_found FROM assessment.cbt_answer x WHERE x.attempt_id = a.id AND x.question_id = q;
        old_found := coalesce(old_found, false);
        -- a save older than the one kept (a retry arriving late) changes nothing
        CONTINUE WHEN old_found AND v_seq IS NOT NULL AND old_seq IS NOT NULL AND old_seq >= v_seq;
        IF r ? 'a' THEN
            SELECT coalesce(array_agg(DISTINCT x ORDER BY x), ARRAY[]::int[]) INTO ch
              FROM jsonb_array_elements_text(coalesce(r -> 'a', '[]'::jsonb)) t(x_text), LATERAL (SELECT x_text::int AS x) v;
        ELSE
            ch := coalesce(old_chosen, ARRAY[]::int[]);
        END IF;
        SELECT jsonb_array_length(qv.options) INTO n FROM assessment.question_version qv WHERE qv.question_id = q AND qv.version = a.question_versions[v_pos];
        IF EXISTS (SELECT 1 FROM unnest(ch) x WHERE x < 0 OR x >= n) THEN
            RAISE EXCEPTION 'CBT_OPTION_RANGE: an option outside the question' USING ERRCODE = '23514';
        END IF;
        IF NOT e.allow_back AND ch IS DISTINCT FROM coalesce(old_chosen, ARRAY[]::int[]) THEN
            SELECT max(array_position(a.question_ids, x.question_id)) INTO v_last
              FROM assessment.cbt_answer x WHERE x.attempt_id = a.id AND x.question_id <> q AND cardinality(x.chosen) > 0;
            IF v_last IS NOT NULL AND v_last > v_pos THEN
                RAISE EXCEPTION 'CBT_BACK_NOT_ALLOWED: this examination moves forward only; an answer before the last one given is not changed' USING ERRCODE = '23514';
            END IF;
        END IF;
        INSERT INTO assessment.cbt_answer AS x (attempt_id, question_id, chosen, seq, flagged) VALUES (a.id, q, ch, v_seq, coalesce(v_flag, false))
        ON CONFLICT (attempt_id, question_id) DO UPDATE
           SET chosen = EXCLUDED.chosen, seq = coalesce(EXCLUDED.seq, x.seq), flagged = coalesce(v_flag, x.flagged), saved_at = now();
    END LOOP;
    UPDATE assessment.cbt_attempt SET answered = (SELECT count(*) FROM assessment.cbt_answer WHERE attempt_id = a.id AND cardinality(chosen) > 0), last_activity_at = now()
     WHERE id = a.id RETURNING * INTO a;
    RETURN a;
END $$;

-- ── 13 · the screen's reports, judged by the examination's own thresholds ───────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_record_events(p_attempt uuid, p_token uuid, p_events jsonb, p_ip text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; r jsonb; k text; v_before int; v_level text := NULL; v_action text := NULL; v_counts boolean;
        v_warn int; v_final int;
BEGIN
    a := assessment.cbt_touch(p_attempt, p_token);
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    v_before := a.violations;
    v_warn := coalesce(e.warn_at, 1);
    v_final := coalesce(e.final_warn_at, e.violation_limit);
    IF a.status = 'IN_PROGRESS' AND p_events IS NOT NULL AND jsonb_typeof(p_events) = 'array' THEN
        FOR r IN SELECT * FROM jsonb_array_elements(p_events) LOOP
            k := upper(coalesce(r ->> 'kind', ''));
            IF k NOT IN ('TAB_SWITCH', 'WINDOW_BLUR', 'WINDOW_FOCUS', 'FULLSCREEN_EXIT', 'FULLSCREEN_ENTER', 'NETWORK_DISCONNECT', 'RECONNECTED', 'COPY_PASTE',
                         'CONTEXT_MENU', 'COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT', 'RIGHT_CLICK', 'RESUMED', 'UNUSUAL_NAVIGATION', 'TIME_MANIPULATION_ATTEMPT',
                         'EXAM_PAGE_EXIT', 'CAMERA_STOPPED', 'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME', 'HEAD_POSE_LEFT', 'HEAD_POSE_RIGHT',
                         'HEAD_POSE_UP', 'HEAD_POSE_DOWN', 'PROLONGED_LOOK_AWAY') THEN CONTINUE; END IF;
            -- proctoring signals are taken only from a proctored examination
            CONTINUE WHEN e.proctoring <> 'CAMERA' AND k IN ('CAMERA_STOPPED', 'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME', 'HEAD_POSE_LEFT',
                                                               'HEAD_POSE_RIGHT', 'HEAD_POSE_UP', 'HEAD_POSE_DOWN', 'PROLONGED_LOOK_AWAY');
            v_counts := k = ANY (e.counted_events)
                        OR (k = 'COPY_PASTE' AND (e.counted_events && ARRAY['COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT']))
                        OR (k = 'CONTEXT_MENU' AND 'RIGHT_CLICK' = ANY (e.counted_events));
            PERFORM assessment.cbt_log(a.id, k, v_counts, left(r ->> 'detail', 500), p_ip,
                                       CASE WHEN jsonb_typeof(r -> 'n') = 'number' THEN (r ->> 'n')::int END,
                                       CASE WHEN jsonb_typeof(r -> 'ms') = 'number' THEN least((r ->> 'ms')::bigint, 2147483647)::int END);
            IF v_counts THEN a.violations := a.violations + 1; END IF;
        END LOOP;
        IF a.violations <> v_before THEN
            UPDATE assessment.cbt_attempt SET violations = a.violations WHERE id = a.id;
            IF a.violations > e.violation_limit THEN
                IF e.violation_action = 'SUBMIT' THEN
                    PERFORM assessment.cbt_log(a.id, 'AUTO_SUBMITTED', false, format('%s violations, over the %s allowed', a.violations, e.violation_limit), p_ip);
                    a := assessment.cbt_finalize(a.id, 'SUBMITTED', format('submitted by policy after %s violations', a.violations));
                    v_action := 'SUBMITTED';
                ELSIF e.violation_action = 'TERMINATE' THEN
                    a := assessment.cbt_finalize(a.id, 'TERMINATED', format('terminated by policy after %s violations, over the %s allowed', a.violations, e.violation_limit));
                    v_action := 'TERMINATED';
                ELSE
                    PERFORM assessment.cbt_log(a.id, 'FINAL_WARNING', false, format('%s violations, over the %s allowed; the examination continues and the record stands', a.violations, e.violation_limit), p_ip);
                    v_level := 'FINAL_WARNING';
                END IF;
            ELSIF a.violations >= v_final THEN
                PERFORM assessment.cbt_log(a.id, 'FINAL_WARNING', false, format('%s of %s violations allowed', a.violations, e.violation_limit), p_ip);
                v_level := 'FINAL_WARNING';
            ELSIF a.violations >= v_warn THEN
                PERFORM assessment.cbt_log(a.id, 'WARNING', false, format('%s of %s violations allowed', a.violations, e.violation_limit), p_ip);
                v_level := 'WARNING';
            END IF;
        END IF;
    END IF;
    RETURN jsonb_build_object('violations', a.violations, 'limit', e.violation_limit, 'policy', e.violation_action, 'level', v_level, 'action', v_action,
                              'status', a.status, 'ends_at', a.ends_at, 'now', now());
END $$;

-- ── 14 · scoring the frozen paper, with negative marking ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_finalize(p_attempt uuid, p_status text, p_reason text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; v_score numeric := 0; v_pct numeric; v_grade text; v_wrong int := 0;
BEGIN
    SELECT * INTO a FROM assessment.cbt_attempt WHERE id = p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_ATTEMPT_NOT_FOUND: no such attempt' USING ERRCODE = '23503'; END IF;
    IF a.status <> 'IN_PROGRESS' THEN RETURN a; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    -- each question judged on the version and the marks the attempt drew; an answer given that earns nothing costs the negative marks
    SELECT coalesce(sum(m.got), 0), count(*) FILTER (WHERE m.got = 0 AND cardinality(coalesce(an.chosen, ARRAY[]::int[])) > 0)
      INTO v_score, v_wrong
      FROM assessment.cbt_attempt_questions(a.id) x
      LEFT JOIN assessment.cbt_answer an ON an.attempt_id = a.id AND an.question_id = x.question_id
      CROSS JOIN LATERAL (SELECT assessment.cbt_marks_for(x.kind, x.answers, an.chosen, x.marks, e.partial_credit) AS got) m;
    v_score := greatest(0, v_score - v_wrong * e.negative_marks);
    v_pct := round(v_score * 100.0 / greatest(a.max_marks, 1), 2);
    SELECT g.grade INTO v_grade FROM policy.grade_of(least(100, greatest(0, round(v_pct)))::int) g LIMIT 1;
    UPDATE assessment.cbt_attempt
       SET status = p_status, submitted_at = now(), score = v_score, percentage = v_pct, grade = v_grade, passed = (v_pct >= e.pass_mark),
           answered = (SELECT count(*) FROM assessment.cbt_answer WHERE attempt_id = a.id AND cardinality(chosen) > 0),
           finished_reason = nullif(btrim(coalesce(p_reason, '')), ''),
           finished_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, finished_office = nullif(current_setting('moaum.actor_office', true), ''),
           last_activity_at = now()
     WHERE id = a.id RETURNING * INTO a;
    INSERT INTO assessment.cbt_result (attempt_id, version, score, max_marks, percentage, grade, passed, changed_by, changed_office)
    VALUES (a.id, 1, v_score, a.max_marks, v_pct, v_grade, a.passed, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    PERFORM assessment.cbt_log(a.id, CASE p_status WHEN 'SUBMITTED' THEN 'SUBMITTED' WHEN 'TIME_EXPIRED' THEN 'TIME_EXPIRED' ELSE 'TERMINATED' END, false,
                               format('%s of %s marks (%s%%, %s)%s%s%s', v_score, a.max_marks, v_pct, coalesce(v_grade, '—'),
                                      CASE WHEN e.partial_credit THEN ' · partial credit on multiple-select' ELSE '' END,
                                      CASE WHEN e.negative_marks > 0 THEN format(' · %s wrong, %s deducted each', v_wrong, e.negative_marks) ELSE '' END,
                                      CASE WHEN p_reason IS NULL THEN '' ELSE ' · ' || p_reason END), NULL);
    RETURN a;
END $$;

-- ── 15 · the clock: time ended, and contact lost past the examination's limit ───────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_sweep()
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT id FROM assessment.cbt_attempt WHERE status = 'IN_PROGRESS' AND ends_at + interval '15 seconds' <= now() ORDER BY ends_at LOOP
        PERFORM assessment.cbt_finalize(r.id, 'TIME_EXPIRED', 'time expired');
        n := n + 1;
    END LOOP;
    FOR r IN SELECT a.id, e.disconnect_minutes FROM assessment.cbt_attempt a JOIN assessment.cbt_exam e ON e.id = a.exam_id
              WHERE a.status = 'IN_PROGRESS' AND e.disconnect_minutes IS NOT NULL
                AND a.last_activity_at < now() - make_interval(mins => e.disconnect_minutes) ORDER BY a.last_activity_at LOOP
        PERFORM assessment.cbt_log(r.id, 'DISCONNECT_TIMEOUT', false, format('no contact for %s minutes; submitted with the answers saved', r.disconnect_minutes), NULL);
        PERFORM assessment.cbt_finalize(r.id, 'SUBMITTED', format('no contact for %s minutes', r.disconnect_minutes));
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- ── 16 · the lifecycle: the course still a CBT course; words for every office; archived, never deleted ──────────

CREATE OR REPLACE FUNCTION assessment.cbt_exam_action(p_exam uuid, p_action text, p_reason text)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_act text := lower(btrim(coalesce(p_action, ''))); v_ready text; r record; v_fees text;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    v_fees := CASE WHEN e.office IN ('GST', 'EPS') THEN 'Your GST fee must be paid' ELSE 'Your school fees must be cleared for examinations' END;
    IF v_act = 'schedule' THEN
        IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not scheduled', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF e.starts_at IS NULL OR e.ends_at IS NULL THEN RAISE EXCEPTION 'CBT_WINDOW_REQUIRED: set the date and time the examination opens and closes first' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'SCHEDULED' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'publish' THEN
        IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not published', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF e.starts_at IS NULL OR e.ends_at IS NULL THEN RAISE EXCEPTION 'CBT_WINDOW_REQUIRED: set the date and time the examination opens and closes first' USING ERRCODE = '23514'; END IF;
        IF e.ends_at <= now() THEN RAISE EXCEPTION 'CBT_WINDOW_PAST: the examination window has already passed' USING ERRCODE = '23514'; END IF;
        IF NOT coalesce((SELECT cbt_enabled FROM catalogue.course WHERE code = e.course_code), false) THEN
            RAISE EXCEPTION 'CBT_COURSE_NOT_ENABLED: % is not a CBT course', e.course_code USING ERRCODE = '23514';
        END IF;
        v_ready := assessment.cbt_paper_ready(e.id);
        IF v_ready IS NOT NULL THEN RAISE EXCEPTION '%', v_ready USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'PUBLISHED', published_at = coalesce(published_at, now()) WHERE id = e.id RETURNING * INTO e;
        PERFORM assessment.cbt_notify_candidates(e.id, e.course_code || ' CBT examination: ' || e.title,
            'Your ' || e.course_code || ' computer-based examination, ' || e.title || ', is scheduled for ' || to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY')
            || ' from ' || to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI') || ' to ' || to_char(e.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI')
            || ' (' || e.duration_minutes || ' minutes once you start). Sign in to the portal, open CBT Examinations, read the instructions and start within the window. '
            || v_fees || ' and the course on your registration.', false);
    ELSIF v_act = 'unpublish' THEN
        IF e.state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_STATE: only a published examination is withdrawn' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM assessment.cbt_attempt WHERE exam_id = e.id) THEN RAISE EXCEPTION 'CBT_HAS_ATTEMPTS: candidates have sat this examination; close or cancel it instead' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'SCHEDULED' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'close' THEN
        IF e.state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_STATE: only a published examination is closed' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'CLOSED', closed_at = now(), ends_at = least(ends_at, now()) WHERE id = e.id RETURNING * INTO e;
        FOR r IN SELECT id FROM assessment.cbt_attempt WHERE exam_id = e.id AND status = 'IN_PROGRESS' LOOP
            PERFORM assessment.cbt_log(r.id, 'AUTO_SUBMITTED', false, 'the examination was closed by the office', NULL);
            PERFORM assessment.cbt_finalize(r.id, 'SUBMITTED', 'the examination was closed by the office');
        END LOOP;
    ELSIF v_act = 'complete' THEN
        IF NOT (e.state = 'CLOSED' OR (e.state = 'PUBLISHED' AND e.ends_at <= now())) THEN
            RAISE EXCEPTION 'CBT_STATE: an examination is completed once its window has passed or it is closed' USING ERRCODE = '23514';
        END IF;
        PERFORM assessment.cbt_finalize(id, 'TIME_EXPIRED', 'time expired') FROM assessment.cbt_attempt WHERE exam_id = e.id AND status = 'IN_PROGRESS';
        UPDATE assessment.cbt_exam SET state = 'COMPLETED', completed_at = now(), closed_at = coalesce(closed_at, now()),
               results_state = CASE WHEN results_state = 'PENDING' THEN 'AUTO_SCORED' ELSE results_state END
         WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'cancel' THEN
        IF e.state IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not cancelled', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'CBT_REASON_REQUIRED: cancelling an examination names its reason' USING ERRCODE = '23514'; END IF;
        FOR r IN SELECT id FROM assessment.cbt_attempt WHERE exam_id = e.id AND status = 'IN_PROGRESS' LOOP
            PERFORM assessment.cbt_finalize(r.id, 'TERMINATED', 'the examination was cancelled: ' || btrim(p_reason));
        END LOOP;
        UPDATE assessment.cbt_exam SET state = 'CANCELLED', cancelled_at = now(), cancel_reason = btrim(p_reason) WHERE id = e.id RETURNING * INTO e;
        IF e.published_at IS NOT NULL THEN
            PERFORM assessment.cbt_notify_candidates(e.id, e.course_code || ' CBT examination cancelled: ' || e.title,
                'The ' || e.course_code || ' computer-based examination, ' || e.title || ', is cancelled. Reason: ' || btrim(p_reason) || '. You will be told when it is rescheduled.', false);
        END IF;
    ELSIF v_act = 'archive' THEN
        -- V364: out of the working lists; the examination, its papers, answers, events and results are kept whole
        IF e.state NOT IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: an examination is archived once it is completed or cancelled' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET archived_at = coalesce(archived_at, now()) WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'unarchive' THEN
        UPDATE assessment.cbt_exam SET archived_at = NULL WHERE id = e.id RETURNING * INTO e;
    ELSE
        RAISE EXCEPTION 'CBT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN e;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_results_action(p_exam uuid, p_action text)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_act text := lower(btrim(coalesce(p_action, '')));
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF v_act = 'review' THEN
        IF e.results_state NOT IN ('PENDING', 'AUTO_SCORED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are %', lower(replace(e.results_state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'UNDER_REVIEW' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'approve' THEN
        IF e.state <> 'COMPLETED' THEN RAISE EXCEPTION 'CBT_NOT_COMPLETED: complete the examination before its results are approved' USING ERRCODE = '23514'; END IF;
        IF e.results_state NOT IN ('AUTO_SCORED', 'UNDER_REVIEW') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are %', lower(replace(e.results_state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'APPROVED', results_approved_at = now(), results_approved_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
         WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'publish' THEN
        IF e.results_state <> 'APPROVED' THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: results are published once approved' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'PUBLISHED', results_published_at = now() WHERE id = e.id RETURNING * INTO e;
        PERFORM assessment.cbt_notify_candidates(e.id, e.course_code || ' CBT result published: ' || e.title,
            'Your result for the ' || e.course_code || ' computer-based examination, ' || e.title || ', is published. Sign in to the portal and open CBT Examinations to see it.', true);
    ELSIF v_act = 'unpublish' THEN
        IF e.results_state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are not published' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'APPROVED', results_published_at = NULL WHERE id = e.id RETURNING * INTO e;
    ELSE
        RAISE EXCEPTION 'CBT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN e;
END $$;

-- ── 17 · onto the score sheet: as the examination, as continuous assessment, or not at all ─────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_to_sheet(p_exam uuid)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; sh assessment.score_sheet; v_ca_max int; r record; n int := 0; v_exam int; v_version int; v_ca int; v_old_exam int; v_new_ca int; v_new_exam int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.sheet_component = 'NONE' THEN
        RAISE EXCEPTION 'CBT_NOT_FOR_SHEET: this examination is set not to count on the score sheet' USING ERRCODE = '23514';
    END IF;
    IF e.results_state NOT IN ('APPROVED', 'PUBLISHED') THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: approve the results before they go onto the score sheet' USING ERRCODE = '23514'; END IF;
    SELECT * INTO sh FROM assessment.score_sheet WHERE offering_id = e.offering_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_NO_SHEET: the course has no score sheet yet; it opens with the examination session' USING ERRCODE = '23514'; END IF;
    IF sh.stage <> 'ENTRY' THEN RAISE EXCEPTION 'CBT_SHEET_NOT_AT_ENTRY: the score sheet is at %; scores are entered at entry', lower(replace(sh.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    SELECT ca_max INTO v_ca_max FROM catalogue.course WHERE code = e.course_code;
    FOR r IN
        SELECT DISTINCT ON (a.student_id) a.student_id, a.percentage, a.outcome
          FROM assessment.cbt_attempt a WHERE a.exam_id = e.id AND a.status <> 'IN_PROGRESS' AND a.percentage IS NOT NULL
         ORDER BY a.student_id, a.percentage DESC, a.number DESC
    LOOP
        v_version := NULL; v_ca := NULL; v_old_exam := NULL;
        SELECT l.version, l.ca, l.exam INTO v_version, v_ca, v_old_exam FROM assessment.latest_scores(sh.id) l WHERE l.student_id = r.student_id;
        IF e.sheet_component = 'CA' THEN
            v_new_ca := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * v_ca_max / 100.0)::int END;
            v_new_exam := v_old_exam;
        ELSE
            v_new_ca := v_ca;
            v_new_exam := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * (100 - v_ca_max) / 100.0)::int END;
        END IF;
        IF v_version IS NOT NULL AND EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = sh.id AND s.student_id = r.student_id AND s.version = v_version
                                               AND s.ca IS NOT DISTINCT FROM v_new_ca AND s.exam IS NOT DISTINCT FROM v_new_exam AND s.reason LIKE 'CBT ' || e.reference || '%') THEN
            CONTINUE;   -- already on the sheet from this examination
        END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (sh.id, r.student_id, coalesce(v_version, 0) + 1, v_new_ca, v_new_exam,
                CASE WHEN v_new_ca IS NULL OR v_new_exam IS NULL THEN 'INCOMPLETE' ELSE 'GRADED' END,
                'CBT ' || e.reference || ': ' || e.title || ' — ' || CASE e.sheet_component WHEN 'CA' THEN 'continuous assessment' ELSE 'examination component' END
                || ' from the computer-based test');
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- ── 18 · the candidates: the payment rule of the examination's own office ───────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
              programme_code text, programme text, level integer, student_status text, entitled boolean, eligible boolean, attempts integer, attempt_id uuid,
              attempt_status text, connection text, started_at timestamp with time zone, ends_at timestamp with time zone, submitted_at timestamp with time zone,
              time_left integer, last_activity_at timestamp with time zone, violations integer, answered integer, score numeric, max_marks integer, percentage numeric,
              grade text, passed boolean, outcome text, updated_at timestamp with time zone)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT x.*, c.general_office, c.kind FROM assessment.cbt_exam x JOIN catalogue.course c ON c.code = x.course_code WHERE x.id = p_exam),
    cfg AS (SELECT * FROM finance.gst_setting WHERE id = 1),
    reg AS (SELECT DISTINCT cr.student_id FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    base AS (SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex, s.status, s.current_level AS level, s.entry_mode,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty
               FROM reg JOIN people.student s ON s.id = reg.student_id
               JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code),
    pays AS (SELECT r.student_id, count(*) AS n FROM e, finance.payment_reference r
              WHERE e.office IN ('GST', 'EPS') AND r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.student_id IN (SELECT id FROM base)
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
              GROUP BY r.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM e, finance.gst_fee f WHERE e.office IN ('GST', 'EPS') AND f.session = e.session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    att AS (SELECT DISTINCT ON (a.student_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.student_id, a.number DESC),
    cnt AS (SELECT a.student_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam GROUP BY a.student_id),
    ent AS (SELECT b.id,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS entitled,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        -- the gate as registration.gst_gate states it, set-based: unpaid while a fee is stated and the rule holds the course
                        THEN NOT (fr.id IS NOT NULL AND fr.amount > 0 AND NOT (coalesce(py.n, 0) > 0)
                                  AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND (coalesce(e.general_office, 'GST') = 'GST' OR cfg.covers_eps))
                                       OR (cfg.required_for_all AND finance.gst_required(b.id, e.session))))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS paid_up
              FROM e CROSS JOIN cfg CROSS JOIN base b
              LEFT JOIN pays py ON py.student_id = b.id
              LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                  WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                    AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                  ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                  LIMIT 1) fr ON true)
    SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
           en.entitled,
           en.paid_up AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION'),
           coalesce(cn.attempts, 0), a.id,
           coalesce(a.status, 'NOT_STARTED'),
           CASE WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED' WHEN a.status = 'IN_PROGRESS' THEN 'ONLINE' ELSE NULL END,
           a.started_at, a.ends_at, a.submitted_at,
           CASE WHEN a.status = 'IN_PROGRESS' THEN greatest(0, extract(epoch FROM a.ends_at - now()))::int ELSE NULL END,
           a.last_activity_at, coalesce(a.violations, 0), coalesce(a.answered, 0), a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at
      FROM base b JOIN ent en ON en.id = b.id
      LEFT JOIN att a ON a.student_id = b.id
      LEFT JOIN cnt cn ON cn.student_id = b.id
$$;

-- ── 19 · the candidate's list: what is new about the examination, and a score only by the release policy ─────────

DROP FUNCTION assessment.cbt_student_exams(uuid, text);
CREATE FUNCTION assessment.cbt_student_exams(p_student uuid, p_session text)
RETURNS TABLE(exam_id uuid, reference text, office text, course_code text, course_title text, title text, session text, semester integer, instructions text,
              live_state text, starts_at timestamp with time zone, ends_at timestamp with time zone, duration_minutes integer, questions integer, security_mode text,
              venue text, attempt_limit integer, violation_limit integer, violation_action text, eligibility text, attempts integer, attempt_id uuid, attempt_status text,
              attempt_ends_at timestamp with time zone, submitted_at timestamp with time zone, result_published boolean, score numeric, max_marks integer,
              percentage numeric, grade text, passed boolean, pass_mark numeric, outcome text, partial_credit boolean,
              exam_type text, negative_marks numeric, allow_back boolean, allow_review boolean, fullscreen_required boolean, proctoring text, score_on_submit boolean)
LANGUAGE sql STABLE AS $$
    WITH mine AS (SELECT DISTINCT en.offering_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                   WHERE cr.student_id = p_student AND (p_session IS NULL OR cr.session = p_session)
                     AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    att AS (SELECT DISTINCT ON (a.exam_id) a.* FROM assessment.cbt_attempt a WHERE a.student_id = p_student ORDER BY a.exam_id, a.number DESC),
    cnt AS (SELECT a.exam_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.student_id = p_student GROUP BY a.exam_id),
    v AS (SELECT e.*, assessment.cbt_live_state(e) AS live,
                 (e.results_state = 'PUBLISHED' OR (e.score_on_submit AND a.status IS NOT NULL AND a.status <> 'IN_PROGRESS')) AS shown, a.id AS a_id, a.status AS a_status,
                 a.ends_at AS a_ends_at, a.submitted_at AS a_submitted_at, a.score AS a_score, a.max_marks AS a_max, a.percentage AS a_pct, a.grade AS a_grade,
                 a.passed AS a_passed, a.outcome AS a_outcome, cn.attempts AS a_attempts
            FROM assessment.cbt_exam e JOIN mine m ON m.offering_id = e.offering_id
            LEFT JOIN att a ON a.exam_id = e.id LEFT JOIN cnt cn ON cn.exam_id = e.id
           WHERE e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED'))
    SELECT v.id, v.reference, v.office, v.course_code, c.title, v.title, v.session, v.semester, v.instructions,
           v.live, v.starts_at, v.ends_at, v.duration_minutes,
           CASE WHEN v.selection = 'RANDOM' THEN v.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(v.id)) END,
           v.security_mode, v.venue, v.attempt_limit, v.violation_limit, v.violation_action,
           CASE WHEN v.a_status = 'IN_PROGRESS' THEN NULL ELSE assessment.cbt_eligibility(v.id, p_student) END,
           coalesce(v.a_attempts, 0), v.a_id, v.a_status, v.a_ends_at, v.a_submitted_at,
           (v.results_state = 'PUBLISHED'),
           CASE WHEN v.shown THEN v.a_score END, CASE WHEN v.shown THEN v.a_max END, CASE WHEN v.shown THEN v.a_pct END, CASE WHEN v.shown THEN v.a_grade END,
           CASE WHEN v.shown THEN v.a_passed END, v.pass_mark, CASE WHEN v.shown THEN v.a_outcome END, v.partial_credit,
           v.exam_type, v.negative_marks, v.allow_back, v.allow_review, v.fullscreen_required, v.proctoring, v.score_on_submit
      FROM v JOIN catalogue.course c ON c.code = v.course_code
     ORDER BY v.starts_at DESC NULLS LAST, v.title
$$;

-- ── 20 · the read-only roles reach the new tables ───────────────────────────────────────────────────────────────

GRANT SELECT ON assessment.cbt_blueprint, assessment.question_version TO app_auditor;

COMMIT;
