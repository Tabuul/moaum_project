-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V322 — the CBT examination engine: GST first, EPS on the same engine
--
--   V314 gave General Studies and Entrepreneurship Studies their offices, the GST fee the Bursar states, the
--   entitlement a confirmed payment grants (one payment covers both), the gate on registration and the two
--   dashboards. V077 gave every course a question bank. What was missing is the examination itself. This
--   migration adds it, on what is already there:
--
--     1  the question bank learns three kinds — one correct option (MCQ), true/false, several correct options
--        (MULTI) — with the key kept as an array, an explanation, and who last changed a question. The kind is
--        the architecture's door to other kinds later; nothing a student receives ever carries the key.
--     2  an examination (assessment.cbt_exam): an office's paper over one offering of one GST or EPS course in
--        one session and semester, with its window, duration, size, selection (a fixed paper or N drawn at
--        random from a pool), randomisation, pass mark, attempt limit, security mode (standard browser or a
--        secure/kiosk environment), venue (remote or the CBT laboratory), the violation policy, and its state
--        (DRAFT → SCHEDULED → PUBLISHED → CLOSED → COMPLETED, or CANCELLED). The clock says whether a published
--        examination is upcoming, open or ended; the office closes and completes it.
--     3  the paper (cbt_exam_question): the fixed questions in order, or the pool a random paper is drawn from.
--     4  the attempt (cbt_attempt): one controlled attempt per student at a time, with its own token (the URL
--        is never the authorisation), the server's end time (start + duration, capped by the window), the paper
--        drawn for it, its answers (cbt_answer, saved as the student goes), its events (cbt_event: tab switches,
--        focus losses, fullscreen exits, disconnections, a second sign-in, warnings, termination), and — the
--        moment it is finalised, by the student, by the clock or by policy — its score, percentage, grade (the
--        University's grading in force) and pass/fail, in one transaction, with the result as a version
--        (cbt_result) that an amendment only ever adds to, with its reason.
--     5  eligibility (cbt_eligibility): an active student, registered on the offering, whose GST fee is paid
--        where the Bursar's rule requires it (registration.gst_gate — the same gate as registration, so the
--        entitlement is the ledger's and nobody else's), while the examination is open, within the attempt
--        limit. Enforced by cbt_start itself, so no path round the API starts an examination.
--     6  what the office reads, set-based: the candidates with their standing and attempt (cbt_candidates),
--        the live counters (cbt_monitor_counts), the figures of a sitting (cbt_exam_stats), the office's
--        summary (cbt_office_summary); and what the student reads (cbt_student_exams).
--     7  the result workflow: AUTO_SCORED when the examination completes → UNDER_REVIEW → APPROVED → PUBLISHED.
--        A student sees a result only once it is published; the office sees every score the moment it exists.
--        The scores go onto the course's score sheet, as the examination component, through cbt_to_sheet —
--        the result pipeline is not duplicated.
--
--   A browser can report what happens inside the page — visibility, focus, fullscreen, the network — and the
--   portal records it and warns, holds or submits by the office's policy. A browser cannot stop a student from
--   switching to another application or device: that is the secure/kiosk mode's job, and the examination says
--   which it needs. Nothing here claims otherwise.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V322: the CBT examination engine — GST first, EPS on the same engine', true);

-- ── 1 · the question bank: kinds, the key as an array, an explanation, who changed it ─────────
ALTER TABLE assessment.question
    ADD COLUMN IF NOT EXISTS kind        text NOT NULL DEFAULT 'MCQ',
    ADD COLUMN IF NOT EXISTS answers     int[] NULL,
    ADD COLUMN IF NOT EXISTS explanation text NULL,
    ADD COLUMN IF NOT EXISTS updated_at  timestamptz NULL,
    ADD COLUMN IF NOT EXISTS updated_by  uuid NULL;
ALTER TABLE assessment.question DROP CONSTRAINT IF EXISTS ck_q_kind;
ALTER TABLE assessment.question ADD CONSTRAINT ck_q_kind CHECK (kind IN ('MCQ', 'TRUE_FALSE', 'MULTI'));
COMMENT ON COLUMN assessment.question.kind IS 'MCQ (one correct option), TRUE_FALSE (two options, one correct) or MULTI (several correct options, all of them for the marks) — V322. Other kinds are added here, never improvised.';
COMMENT ON COLUMN assessment.question.answers IS 'The key: the positions of the correct options, sorted (V322). For MCQ and TRUE_FALSE it is ARRAY[answer]; the trigger keeps the two in step. Never sent to a candidate.';

/* the key and the kind kept consistent: MULTI carries a sorted set of positions and answer = its first; the
   others carry one position and answers = ARRAY[answer]; TRUE_FALSE has exactly two options */
CREATE OR REPLACE FUNCTION assessment.question_key_check()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n int := jsonb_array_length(NEW.options); a int;
BEGIN
    NEW.kind := upper(coalesce(NEW.kind, 'MCQ'));
    IF NEW.kind = 'TRUE_FALSE' AND n <> 2 THEN
        RAISE EXCEPTION 'CBT_TRUE_FALSE_OPTIONS: a true/false question has exactly two options' USING ERRCODE = '23514';
    END IF;
    IF NEW.kind = 'MULTI' THEN
        IF NEW.answers IS NULL OR cardinality(NEW.answers) = 0 THEN
            RAISE EXCEPTION 'CBT_KEY_REQUIRED: a multiple-select question names at least one correct option' USING ERRCODE = '23514';
        END IF;
        SELECT array_agg(DISTINCT x ORDER BY x) INTO NEW.answers FROM unnest(NEW.answers) x;
        FOREACH a IN ARRAY NEW.answers LOOP
            IF a < 0 OR a >= n THEN RAISE EXCEPTION 'CBT_KEY_RANGE: the correct-option position % is outside the options', a USING ERRCODE = '23514'; END IF;
        END LOOP;
        NEW.answer := NEW.answers[1];
    ELSE
        IF NEW.answer IS NULL OR NEW.answer < 0 OR NEW.answer >= n THEN
            RAISE EXCEPTION 'CBT_KEY_RANGE: the correct-option position is outside the options' USING ERRCODE = '23514';
        END IF;
        NEW.answers := ARRAY[NEW.answer];
    END IF;
    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at := now();
        NEW.updated_by := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_question_key ON assessment.question;
CREATE TRIGGER trg_question_key BEFORE INSERT OR UPDATE ON assessment.question
    FOR EACH ROW EXECUTE FUNCTION assessment.question_key_check();
UPDATE assessment.question SET answers = ARRAY[answer] WHERE answers IS NULL;

-- ── 2 · the examination ──────────────────────────────────────────────────────────────────────
CREATE TABLE assessment.cbt_exam (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference            text NOT NULL UNIQUE,
    office               text NOT NULL CHECK (office IN ('GST', 'EPS')),
    course_code          text NOT NULL REFERENCES catalogue.course(code),
    offering_id          uuid NOT NULL REFERENCES catalogue.offering(id),
    session              text NOT NULL REFERENCES policy.academic_session(name),
    semester             int  NOT NULL CHECK (semester BETWEEN 1 AND 3),
    title                text NOT NULL CHECK (btrim(title) <> ''),
    instructions         text NULL,
    state                text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'CLOSED', 'COMPLETED', 'CANCELLED')),
    starts_at            timestamptz NULL,
    ends_at              timestamptz NULL,
    duration_minutes     int  NOT NULL DEFAULT 60 CHECK (duration_minutes BETWEEN 5 AND 600),
    total_questions      int  NOT NULL DEFAULT 0 CHECK (total_questions >= 0),
    selection            text NOT NULL DEFAULT 'FIXED' CHECK (selection IN ('FIXED', 'RANDOM')),
    randomize_questions  boolean NOT NULL DEFAULT true,
    randomize_options    boolean NOT NULL DEFAULT false,
    pass_mark            numeric(5,2) NOT NULL DEFAULT 40 CHECK (pass_mark BETWEEN 0 AND 100),
    attempt_limit        int  NOT NULL DEFAULT 1 CHECK (attempt_limit BETWEEN 1 AND 5),
    security_mode        text NOT NULL DEFAULT 'STANDARD' CHECK (security_mode IN ('STANDARD', 'SECURE')),
    venue                text NOT NULL DEFAULT 'REMOTE' CHECK (venue IN ('REMOTE', 'LAB')),
    violation_limit      int  NOT NULL DEFAULT 2 CHECK (violation_limit BETWEEN 0 AND 20),
    violation_action     text NOT NULL DEFAULT 'WARN' CHECK (violation_action IN ('WARN', 'SUBMIT', 'TERMINATE')),
    second_session       text NOT NULL DEFAULT 'CONTINUE' CHECK (second_session IN ('CONTINUE', 'DENY')),
    results_state        text NOT NULL DEFAULT 'PENDING' CHECK (results_state IN ('PENDING', 'AUTO_SCORED', 'UNDER_REVIEW', 'APPROVED', 'PUBLISHED')),
    results_approved_at  timestamptz NULL,
    results_approved_by  uuid NULL,
    results_published_at timestamptz NULL,
    created_by           uuid NULL,
    created_office       text NULL,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    published_at         timestamptz NULL,
    closed_at            timestamptz NULL,
    completed_at         timestamptz NULL,
    cancelled_at         timestamptz NULL,
    cancel_reason        text NULL,
    CONSTRAINT ck_cbt_exam_window CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at),
    UNIQUE (offering_id, title)
);
COMMENT ON TABLE assessment.cbt_exam IS
  'A CBT examination (V322): an office''s paper over one offering, with its window, duration, size, selection, randomisation, pass mark, attempt limit, security mode, venue, violation policy, lifecycle state and result state. GST first; EPS on the same engine.';
CREATE INDEX ix_cbt_exam_office ON assessment.cbt_exam (office, session, semester, state);
CREATE INDEX ix_cbt_exam_offering ON assessment.cbt_exam (offering_id);
SELECT audit.attach('assessment.cbt_exam');

CREATE OR REPLACE FUNCTION assessment.cbt_exam_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_cbt_exam_touch BEFORE UPDATE ON assessment.cbt_exam FOR EACH ROW EXECUTE FUNCTION assessment.cbt_exam_touch();

/* the paper: the fixed questions in order, or the pool a random paper is drawn from; marks may be overridden per paper */
CREATE TABLE assessment.cbt_exam_question (
    exam_id     uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    question_id uuid NOT NULL REFERENCES assessment.question(id),
    ordinal     int  NOT NULL DEFAULT 0,
    marks       int  NULL CHECK (marks IS NULL OR marks > 0),
    PRIMARY KEY (exam_id, question_id)
);
CREATE INDEX ix_cbt_exam_question_order ON assessment.cbt_exam_question (exam_id, ordinal);
SELECT audit.attach('assessment.cbt_exam_question');

-- ── 3 · the attempt, its answers, its events, its result ─────────────────────────────────────
CREATE TABLE assessment.cbt_attempt (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id           uuid NOT NULL REFERENCES assessment.cbt_exam(id),
    student_id        uuid NOT NULL REFERENCES people.student(id),
    number            int  NOT NULL DEFAULT 1,
    token             uuid NOT NULL DEFAULT gen_random_uuid(),
    started_at        timestamptz NOT NULL DEFAULT now(),
    ends_at           timestamptz NOT NULL,
    submitted_at      timestamptz NULL,
    status            text NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS', 'SUBMITTED', 'TIME_EXPIRED', 'TERMINATED')),
    question_ids      uuid[] NOT NULL,
    seed              int  NOT NULL,
    max_marks         int  NOT NULL CHECK (max_marks > 0),
    answered          int  NOT NULL DEFAULT 0,
    score             numeric(8,2) NULL,
    percentage        numeric(5,2) NULL,
    grade             text NULL,
    passed            boolean NULL,
    outcome           text NOT NULL DEFAULT 'SCORED' CHECK (outcome IN ('SCORED', 'VOID')),
    violations        int  NOT NULL DEFAULT 0,
    last_activity_at  timestamptz NOT NULL DEFAULT now(),
    ip                text NULL,
    user_agent        text NULL,
    finished_reason   text NULL,
    finished_by       uuid NULL,
    finished_office   text NULL,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (exam_id, student_id, number)
);
COMMENT ON TABLE assessment.cbt_attempt IS
  'One student''s attempt at a CBT examination (V322): its own token, the server''s end time, the paper drawn for it, the answers saved as it goes, and the score the moment it is finalised. One attempt in progress per student per examination.';
CREATE UNIQUE INDEX ux_cbt_attempt_active ON assessment.cbt_attempt (exam_id, student_id) WHERE status = 'IN_PROGRESS';
CREATE INDEX ix_cbt_attempt_exam_status ON assessment.cbt_attempt (exam_id, status);
CREATE INDEX ix_cbt_attempt_exam_updated ON assessment.cbt_attempt (exam_id, updated_at);
CREATE INDEX ix_cbt_attempt_student ON assessment.cbt_attempt (student_id, exam_id);
CREATE INDEX ix_cbt_attempt_expiring ON assessment.cbt_attempt (ends_at) WHERE status = 'IN_PROGRESS';
SELECT audit.attach('assessment.cbt_attempt');

CREATE OR REPLACE FUNCTION assessment.cbt_attempt_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_cbt_attempt_touch BEFORE UPDATE ON assessment.cbt_attempt FOR EACH ROW EXECUTE FUNCTION assessment.cbt_attempt_touch();

CREATE TABLE assessment.cbt_answer (
    attempt_id  uuid NOT NULL REFERENCES assessment.cbt_attempt(id) ON DELETE CASCADE,
    question_id uuid NOT NULL REFERENCES assessment.question(id),
    chosen      int[] NOT NULL,
    saved_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (attempt_id, question_id)
);
COMMENT ON TABLE assessment.cbt_answer IS 'The options a candidate chose on one question of one attempt (V322), by original position; replaced as the candidate changes their mind until the attempt is finalised.';
SELECT audit.exempt('assessment.cbt_answer', 'the candidate''s working answers, replaced as they change their mind until the attempt is finalised; the finalisation, the score and every amendment are on the audited attempt and result, and a row per keystroke on the chain would serialise thousands of candidates behind one lock');

CREATE TABLE assessment.cbt_event (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id  uuid NOT NULL REFERENCES assessment.cbt_attempt(id) ON DELETE CASCADE,
    exam_id     uuid NOT NULL REFERENCES assessment.cbt_exam(id),
    kind        text NOT NULL CHECK (kind IN ('STARTED', 'RESUMED', 'TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'NETWORK_DISCONNECT', 'RECONNECTED',
                                              'MULTIPLE_LOGIN', 'SESSION_REPLACED', 'COPY_PASTE', 'CONTEXT_MENU', 'WARNING', 'FINAL_WARNING',
                                              'AUTO_SUBMITTED', 'TERMINATED', 'SUBMITTED', 'TIME_EXPIRED', 'AMENDED')),
    violation   boolean NOT NULL DEFAULT false,
    at          timestamptz NOT NULL DEFAULT now(),
    detail      text NULL,
    ip          text NULL
);
COMMENT ON TABLE assessment.cbt_event IS 'What happened on an attempt (V322): the browser''s reports (a tab switch, a focus loss, a fullscreen exit, a disconnection), a second sign-in, the warnings given, and how the attempt ended. Evidence for an authorised officer, never a verdict by itself.';
CREATE INDEX ix_cbt_event_attempt ON assessment.cbt_event (attempt_id, at);
CREATE INDEX ix_cbt_event_exam ON assessment.cbt_event (exam_id, at);
/* the record is written once: nothing updates or deletes an event, except the maintenance reset */
CREATE OR REPLACE FUNCTION assessment.cbt_event_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'CBT_EVENT_WRITTEN_ONCE: the record of an attempt is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_cbt_event_written_once BEFORE UPDATE OR DELETE ON assessment.cbt_event
    FOR EACH ROW EXECUTE FUNCTION assessment.cbt_event_written_once();
SELECT audit.exempt('assessment.cbt_event', 'the append-only record of what happened on an attempt — the browser''s reports, the warnings, the ending — written once by trigger, read as evidence; it is itself the trail, and a copy of every row on the chain would double the writes of an examination of thousands');

CREATE TABLE assessment.cbt_result (
    attempt_id     uuid NOT NULL REFERENCES assessment.cbt_attempt(id) ON DELETE CASCADE,
    version        int  NOT NULL DEFAULT 1,
    score          numeric(8,2) NOT NULL,
    max_marks      int  NOT NULL,
    percentage     numeric(5,2) NOT NULL,
    grade          text NULL,
    passed         boolean NOT NULL,
    outcome        text NOT NULL DEFAULT 'SCORED' CHECK (outcome IN ('SCORED', 'VOID')),
    reason         text NULL,
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (attempt_id, version),
    CONSTRAINT ck_cbt_result_amended CHECK (version = 1 OR (reason IS NOT NULL AND btrim(reason) <> ''))
);
COMMENT ON TABLE assessment.cbt_result IS 'The result of an attempt as versions (V322): the first written by the scoring, every later one an amendment with its reason and author. A result is never overwritten.';
SELECT audit.attach('assessment.cbt_result');

-- ── 4 · the examination's words: its reference, its live state, whether its paper is ready ──
CREATE OR REPLACE FUNCTION assessment.cbt_new_exam(p_office text, p_offering uuid, p_title text, p_instructions text, p_duration int, p_total int,
                                                    p_selection text, p_random_q boolean, p_random_o boolean, p_pass numeric, p_attempts int,
                                                    p_security text, p_venue text, p_violation_limit int, p_violation_action text, p_second_session text,
                                                    p_starts timestamptz, p_ends timestamptz)
RETURNS assessment.cbt_exam LANGUAGE plpgsql AS $$
DECLARE o record; e assessment.cbt_exam; v_office text := upper(btrim(coalesce(p_office, '')));
BEGIN
    SELECT ofr.id, ofr.course_code, ofr.session, ofr.semester, c.kind, c.general_office, c.title AS course_title
      INTO o FROM catalogue.offering ofr JOIN catalogue.course c ON c.code = ofr.course_code WHERE ofr.id = p_offering;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_OFFERING_NOT_FOUND: no such course offering' USING ERRCODE = '23503'; END IF;
    IF o.kind <> 'GST' OR coalesce(o.general_office, 'GST') <> v_office THEN
        RAISE EXCEPTION 'CBT_NOT_OFFICE_COURSE: % is not a course of the % office', o.course_code, v_office USING ERRCODE = '23514',
            HINT = 'An office examines its own courses; the course''s office is set on the catalogue.';
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

/* what the clock says of an examination: DRAFT, SCHEDULED, UPCOMING (published, not yet open), OPEN, ENDED (window passed, not yet closed), CLOSED, COMPLETED, CANCELLED */
CREATE OR REPLACE FUNCTION assessment.cbt_live_state(e assessment.cbt_exam)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN e.state <> 'PUBLISHED' THEN e.state
                WHEN e.starts_at > now() THEN 'UPCOMING'
                WHEN e.ends_at <= now() THEN 'ENDED'
                ELSE 'OPEN' END
$$;

/* the pool a paper is drawn from: the paper's own questions, else the course's active bank */
CREATE OR REPLACE FUNCTION assessment.cbt_pool(p_exam uuid)
RETURNS TABLE (question_id uuid, ordinal int, marks int)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
         own AS (SELECT eq.question_id, eq.ordinal, coalesce(eq.marks, q.marks) AS marks
                   FROM assessment.cbt_exam_question eq JOIN assessment.question q ON q.id = eq.question_id AND q.active
                  WHERE eq.exam_id = p_exam)
    SELECT * FROM own
    UNION ALL
    SELECT q.id, 0, q.marks FROM e JOIN assessment.question q ON q.course_code = e.course_code AND q.active
     WHERE e.selection = 'RANDOM' AND NOT EXISTS (SELECT 1 FROM own)
$$;

/* NULL when the paper can be sat; otherwise why not */
CREATE OR REPLACE FUNCTION assessment.cbt_paper_ready(p_exam uuid)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; n int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    SELECT count(*) INTO n FROM assessment.cbt_pool(p_exam);
    IF e.selection = 'FIXED' THEN
        IF n = 0 THEN RETURN 'CBT_PAPER_EMPTY: the paper has no questions'; END IF;
    ELSE
        IF e.total_questions <= 0 THEN RETURN 'CBT_PAPER_SIZE: a random paper says how many questions are drawn'; END IF;
        IF n < e.total_questions THEN RETURN format('CBT_POOL_TOO_SMALL: the pool holds %s active questions; the paper draws %s', n, e.total_questions); END IF;
    END IF;
    RETURN NULL;
END $$;

/* the paper of one attempt: the fixed questions in their order (shuffled by the seed when asked), or N drawn by the seed from the pool */
CREATE OR REPLACE FUNCTION assessment.cbt_paper(p_exam uuid, p_seed int)
RETURNS uuid[] LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam)
    SELECT coalesce(array_agg(p.question_id ORDER BY
                CASE WHEN e.selection = 'RANDOM' OR e.randomize_questions THEN md5(p_seed::text || p.question_id::text) ELSE lpad(p.ordinal::text, 9, '0') END),
           ARRAY[]::uuid[])
      FROM e, LATERAL (SELECT * FROM assessment.cbt_pool(p_exam) pl
                        ORDER BY CASE WHEN e.selection = 'RANDOM' THEN md5(p_seed::text || pl.question_id::text) ELSE lpad(pl.ordinal::text, 9, '0') END
                        LIMIT CASE WHEN e.selection = 'RANDOM' THEN e.total_questions ELSE NULL END) p
$$;

-- ── 5 · eligibility: enforced where the attempt is made ──────────────────────────────────────
/* NULL when the student may sit this examination now; otherwise 'CODE: why not' */
CREATE OR REPLACE FUNCTION assessment.cbt_eligibility(p_exam uuid, p_student uuid)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; st people.student; v_gate text; v_ready text; n int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RETURN 'CBT_EXAM_NOT_FOUND: no such examination'; END IF;
    IF e.state = 'CANCELLED' THEN RETURN 'CBT_EXAM_CANCELLED: this examination was cancelled'; END IF;
    IF e.state <> 'PUBLISHED' THEN RETURN 'CBT_EXAM_NOT_OPEN: this examination is not open to candidates'; END IF;
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF NOT FOUND OR st.status NOT IN ('ACTIVE', 'ADMITTED', 'PROBATION') THEN
        RETURN 'CBT_STUDENT_INACTIVE: only an active student sits an examination';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                    WHERE cr.student_id = p_student AND en.offering_id = e.offering_id
                      AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) THEN
        RETURN format('CBT_COURSE_NOT_REGISTERED: %s is not on your submitted registration for %s', e.course_code, e.session);
    END IF;
    v_gate := registration.gst_gate(p_student, e.session, e.course_code);
    IF v_gate IS NOT NULL THEN RETURN v_gate; END IF;
    v_ready := assessment.cbt_paper_ready(p_exam);
    IF v_ready IS NOT NULL THEN RETURN v_ready; END IF;
    IF e.starts_at > now() THEN RETURN format('CBT_EXAM_NOT_STARTED: the examination opens at %s', to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI')); END IF;
    IF e.ends_at <= now() THEN RETURN 'CBT_EXAM_ENDED: the examination window has closed'; END IF;
    SELECT count(*) INTO n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND student_id = p_student AND status <> 'IN_PROGRESS';
    IF n >= e.attempt_limit THEN RETURN format('CBT_ATTEMPT_LIMIT: you have used the %s attempt%s this examination allows', e.attempt_limit, CASE WHEN e.attempt_limit = 1 THEN '' ELSE 's' END); END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION assessment.cbt_eligibility(uuid, uuid) IS
  'Whether a student may sit a CBT examination now (V322): published, active student, registered on the offering, the GST fee paid where the Bursar''s rule requires it (registration.gst_gate), the paper ready, the window open, attempts left. Raised by cbt_start itself.';

CREATE OR REPLACE FUNCTION assessment.cbt_log(p_attempt uuid, p_kind text, p_violation boolean, p_detail text, p_ip text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO assessment.cbt_event (attempt_id, exam_id, kind, violation, detail, ip)
    SELECT a.id, a.exam_id, p_kind, p_violation, nullif(btrim(coalesce(p_detail, '')), ''), p_ip FROM assessment.cbt_attempt a WHERE a.id = p_attempt
$$;

/* the student starts, or returns to, their attempt: eligibility judged here; a second sign-in handled by the examination's policy */
CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; a assessment.cbt_attempt; v_why text; v_seed int; v_paper uuid[]; v_max int; v_n int;
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
            PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', true, 'the examination was opened again; the earlier screen is replaced', p_ip);
            PERFORM assessment.cbt_log(a.id, 'SESSION_REPLACED', false, 'the earlier screen no longer holds the attempt', p_ip);
            UPDATE assessment.cbt_attempt SET token = gen_random_uuid(), violations = violations + 1, last_activity_at = now(), ip = coalesce(p_ip, ip), user_agent = coalesce(p_agent, user_agent)
             WHERE id = a.id RETURNING * INTO a;
            RETURN a;
        END IF;
    END IF;
    v_why := assessment.cbt_eligibility(p_exam, p_student);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514', HINT = 'Eligibility is judged on the record: the registration, the GST payment on the ledger, the examination window.';
    END IF;
    v_seed := (random() * 2147483646)::int;
    v_paper := assessment.cbt_paper(p_exam, v_seed);
    IF coalesce(cardinality(v_paper), 0) = 0 THEN RAISE EXCEPTION 'CBT_PAPER_EMPTY: the paper has no questions' USING ERRCODE = '23514'; END IF;
    SELECT coalesce(sum(p.marks), 0) INTO v_max FROM assessment.cbt_pool(p_exam) p WHERE p.question_id = ANY (v_paper);
    SELECT count(*) INTO v_n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND student_id = p_student;
    INSERT INTO assessment.cbt_attempt (exam_id, student_id, number, ends_at, question_ids, seed, max_marks, ip, user_agent)
    VALUES (p_exam, p_student, v_n + 1, least(now() + make_interval(mins => e.duration_minutes), e.ends_at), v_paper, v_seed, greatest(v_max, 1), p_ip, p_agent)
    RETURNING * INTO a;
    PERFORM assessment.cbt_log(a.id, 'STARTED', false, format('%s questions, %s marks, ends %s', cardinality(v_paper), a.max_marks, to_char(a.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI:SS')), p_ip);
    RETURN a;
END $$;
COMMENT ON FUNCTION assessment.cbt_start(uuid, uuid, text, text) IS
  'Starts a student''s attempt (V322) after judging eligibility, draws their paper by a seed, sets the server''s end time; an attempt already in progress is continued (its token rotated and the second sign-in recorded) or refused, by the examination''s policy.';

-- ── 6 · the attempt while it runs: the token checked, the clock the server's ─────────────────
/* the attempt, if this token holds it and it is still running; an attempt past its end is finalised first */
CREATE OR REPLACE FUNCTION assessment.cbt_touch(p_attempt uuid, p_token uuid)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt;
BEGIN
    SELECT * INTO a FROM assessment.cbt_attempt WHERE id = p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_ATTEMPT_NOT_FOUND: no such attempt' USING ERRCODE = '23503'; END IF;
    IF a.token <> p_token THEN
        RAISE EXCEPTION 'CBT_SESSION_REPLACED: this examination screen no longer holds the attempt' USING ERRCODE = '23514',
            HINT = 'The examination was opened on another browser or device; continue there.';
    END IF;
    IF a.status = 'IN_PROGRESS' AND a.ends_at + interval '15 seconds' <= now() THEN
        a := assessment.cbt_finalize(a.id, 'TIME_EXPIRED', 'time expired');
    ELSIF a.status = 'IN_PROGRESS' THEN
        UPDATE assessment.cbt_attempt SET last_activity_at = now() WHERE id = a.id RETURNING * INTO a;
    END IF;
    RETURN a;
END $$;

/* the answers as they are given: [{"q": "<question id>", "a": [positions]}, …]; a question not on this paper is refused */
CREATE OR REPLACE FUNCTION assessment.cbt_save_answers(p_attempt uuid, p_token uuid, p_answers jsonb)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; r jsonb; q uuid; ch int[]; n int;
BEGIN
    a := assessment.cbt_touch(p_attempt, p_token);
    IF a.status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION 'CBT_ATTEMPT_CLOSED: the attempt is %', lower(replace(a.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' THEN RETURN a; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
        q := (r ->> 'q')::uuid;
        IF NOT (q = ANY (a.question_ids)) THEN
            RAISE EXCEPTION 'CBT_QUESTION_NOT_ON_PAPER: that question is not on this paper' USING ERRCODE = '23514';
        END IF;
        SELECT coalesce(array_agg(DISTINCT x ORDER BY x), ARRAY[]::int[]) INTO ch FROM jsonb_array_elements_text(coalesce(r -> 'a', '[]'::jsonb)) t(x_text), LATERAL (SELECT x_text::int AS x) v;
        SELECT jsonb_array_length(options) INTO n FROM assessment.question WHERE id = q;
        IF EXISTS (SELECT 1 FROM unnest(ch) x WHERE x < 0 OR x >= n) THEN
            RAISE EXCEPTION 'CBT_OPTION_RANGE: an option outside the question' USING ERRCODE = '23514';
        END IF;
        IF cardinality(ch) = 0 THEN
            DELETE FROM assessment.cbt_answer WHERE attempt_id = a.id AND question_id = q;
        ELSE
            INSERT INTO assessment.cbt_answer (attempt_id, question_id, chosen) VALUES (a.id, q, ch)
            ON CONFLICT (attempt_id, question_id) DO UPDATE SET chosen = EXCLUDED.chosen, saved_at = now();
        END IF;
    END LOOP;
    UPDATE assessment.cbt_attempt SET answered = (SELECT count(*) FROM assessment.cbt_answer WHERE attempt_id = a.id), last_activity_at = now()
     WHERE id = a.id RETURNING * INTO a;
    RETURN a;
END $$;

/* the browser's reports: [{"kind": "TAB_SWITCH", "detail": "…"}, …]; the violation policy applied; what to tell the candidate returned */
CREATE OR REPLACE FUNCTION assessment.cbt_record_events(p_attempt uuid, p_token uuid, p_events jsonb, p_ip text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; r jsonb; k text; v_before int; v_level text := NULL; v_action text := NULL;
BEGIN
    a := assessment.cbt_touch(p_attempt, p_token);
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    v_before := a.violations;
    IF a.status = 'IN_PROGRESS' AND p_events IS NOT NULL AND jsonb_typeof(p_events) = 'array' THEN
        FOR r IN SELECT * FROM jsonb_array_elements(p_events) LOOP
            k := upper(coalesce(r ->> 'kind', ''));
            IF k NOT IN ('TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'NETWORK_DISCONNECT', 'RECONNECTED', 'COPY_PASTE', 'CONTEXT_MENU', 'RESUMED') THEN CONTINUE; END IF;
            PERFORM assessment.cbt_log(a.id, k, k IN ('TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT'), r ->> 'detail', p_ip);
            IF k IN ('TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT') THEN a.violations := a.violations + 1; END IF;
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
            ELSIF a.violations = e.violation_limit THEN
                PERFORM assessment.cbt_log(a.id, 'FINAL_WARNING', false, format('%s of %s violations allowed', a.violations, e.violation_limit), p_ip);
                v_level := 'FINAL_WARNING';
            ELSE
                PERFORM assessment.cbt_log(a.id, 'WARNING', false, format('%s of %s violations allowed', a.violations, e.violation_limit), p_ip);
                v_level := 'WARNING';
            END IF;
        END IF;
    END IF;
    RETURN jsonb_build_object('violations', a.violations, 'limit', e.violation_limit, 'policy', e.violation_action, 'level', v_level, 'action', v_action,
                              'status', a.status, 'ends_at', a.ends_at, 'now', now());
END $$;

-- ── 7 · finalising: one transaction from the last answer to the result ───────────────────────
CREATE OR REPLACE FUNCTION assessment.cbt_finalize(p_attempt uuid, p_status text, p_reason text)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; v_score numeric := 0; v_pct numeric; v_grade text;
BEGIN
    SELECT * INTO a FROM assessment.cbt_attempt WHERE id = p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_ATTEMPT_NOT_FOUND: no such attempt' USING ERRCODE = '23503'; END IF;
    IF a.status <> 'IN_PROGRESS' THEN RETURN a; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    -- the marks: a question earns its marks when the chosen options are exactly its key; nothing is lost for a wrong one
    SELECT coalesce(sum(CASE WHEN an.chosen = q.answers THEN p.marks ELSE 0 END), 0) INTO v_score
      FROM unnest(a.question_ids) qid
      JOIN assessment.cbt_pool(a.exam_id) p ON p.question_id = qid
      JOIN assessment.question q ON q.id = qid
      LEFT JOIN assessment.cbt_answer an ON an.attempt_id = a.id AND an.question_id = qid;
    v_pct := round(v_score * 100.0 / greatest(a.max_marks, 1), 2);
    SELECT g.grade INTO v_grade FROM policy.grade_of(least(100, greatest(0, round(v_pct)))::int) g LIMIT 1;
    UPDATE assessment.cbt_attempt
       SET status = p_status, submitted_at = now(), score = v_score, percentage = v_pct, grade = v_grade, passed = (v_pct >= e.pass_mark),
           answered = (SELECT count(*) FROM assessment.cbt_answer WHERE attempt_id = a.id),
           finished_reason = nullif(btrim(coalesce(p_reason, '')), ''),
           finished_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, finished_office = nullif(current_setting('moaum.actor_office', true), ''),
           last_activity_at = now()
     WHERE id = a.id RETURNING * INTO a;
    INSERT INTO assessment.cbt_result (attempt_id, version, score, max_marks, percentage, grade, passed, changed_by, changed_office)
    VALUES (a.id, 1, v_score, a.max_marks, v_pct, v_grade, a.passed, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    PERFORM assessment.cbt_log(a.id, CASE p_status WHEN 'SUBMITTED' THEN 'SUBMITTED' WHEN 'TIME_EXPIRED' THEN 'TIME_EXPIRED' ELSE 'TERMINATED' END, false,
                               format('%s of %s marks (%s%%, %s)%s', v_score, a.max_marks, v_pct, coalesce(v_grade, '—'), CASE WHEN p_reason IS NULL THEN '' ELSE ' · ' || p_reason END), NULL);
    RETURN a;
END $$;
COMMENT ON FUNCTION assessment.cbt_finalize(uuid, text, text) IS
  'Ends an attempt in one transaction (V322): the answers are judged against the keys, the score, percentage, grade (policy.grade_of) and pass/fail written on the attempt, the first result version recorded, the event logged. A second call changes nothing.';

/* the candidate submits */
CREATE OR REPLACE FUNCTION assessment.cbt_submit(p_attempt uuid, p_token uuid)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt;
BEGIN
    a := assessment.cbt_touch(p_attempt, p_token);
    IF a.status = 'IN_PROGRESS' THEN a := assessment.cbt_finalize(a.id, 'SUBMITTED', 'submitted by the candidate'); END IF;
    RETURN a;
END $$;

/* the clock: every attempt past its end is finalised, whether or not its browser ever came back */
CREATE OR REPLACE FUNCTION assessment.cbt_sweep()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT id FROM assessment.cbt_attempt WHERE status = 'IN_PROGRESS' AND ends_at + interval '15 seconds' <= now() ORDER BY ends_at LOOP
        PERFORM assessment.cbt_finalize(r.id, 'TIME_EXPIRED', 'time expired');
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

/* an authorised officer ends an attempt, with the reason on the record */
CREATE OR REPLACE FUNCTION assessment.cbt_terminate(p_attempt uuid, p_reason text)
RETURNS assessment.cbt_attempt LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'CBT_REASON_REQUIRED: terminating an attempt names its reason' USING ERRCODE = '23514'; END IF;
    RETURN assessment.cbt_finalize(p_attempt, 'TERMINATED', 'terminated by ' || coalesce(nullif(current_setting('moaum.actor_office', true), ''), 'the office') || ': ' || btrim(p_reason));
END $$;

/* an amendment: a new version with its reason; the attempt carries the latest */
CREATE OR REPLACE FUNCTION assessment.cbt_amend_result(p_attempt uuid, p_score numeric, p_outcome text, p_reason text)
RETURNS assessment.cbt_result LANGUAGE plpgsql AS $$
DECLARE a assessment.cbt_attempt; e assessment.cbt_exam; r assessment.cbt_result; v_pct numeric; v_grade text; v_out text := upper(coalesce(p_outcome, 'SCORED'));
BEGIN
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'CBT_REASON_REQUIRED: an amendment names its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM assessment.cbt_attempt WHERE id = p_attempt FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_ATTEMPT_NOT_FOUND: no such attempt' USING ERRCODE = '23503'; END IF;
    IF a.status = 'IN_PROGRESS' THEN RAISE EXCEPTION 'CBT_ATTEMPT_RUNNING: the attempt is still in progress' USING ERRCODE = '23514'; END IF;
    IF v_out NOT IN ('SCORED', 'VOID') THEN RAISE EXCEPTION 'CBT_OUTCOME: an outcome is SCORED or VOID' USING ERRCODE = '23514'; END IF;
    IF p_score IS NULL OR p_score < 0 OR p_score > a.max_marks THEN
        RAISE EXCEPTION 'CBT_SCORE_RANGE: a score is between 0 and the paper''s %s marks', a.max_marks USING ERRCODE = '23514';
    END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = a.exam_id;
    v_pct := round(p_score * 100.0 / greatest(a.max_marks, 1), 2);
    SELECT g.grade INTO v_grade FROM policy.grade_of(least(100, greatest(0, round(v_pct)))::int) g LIMIT 1;
    INSERT INTO assessment.cbt_result (attempt_id, version, score, max_marks, percentage, grade, passed, outcome, reason, changed_by, changed_office)
    VALUES (a.id, (SELECT coalesce(max(version), 0) + 1 FROM assessment.cbt_result WHERE attempt_id = a.id), p_score, a.max_marks, v_pct, v_grade,
            (v_out = 'SCORED' AND v_pct >= e.pass_mark), v_out, btrim(p_reason),
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING * INTO r;
    UPDATE assessment.cbt_attempt SET score = r.score, percentage = r.percentage, grade = r.grade, passed = r.passed, outcome = r.outcome WHERE id = a.id;
    PERFORM assessment.cbt_log(a.id, 'AMENDED', false, format('version %s: %s of %s (%s) — %s', r.version, r.score, r.max_marks, r.outcome, btrim(p_reason)), NULL);
    RETURN r;
END $$;

-- ── 8 · the examination's lifecycle and its results' ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.cbt_notify_candidates(p_exam uuid, p_subject text, p_body text, p_only_sat boolean)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; r record; n int := 0;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    FOR r IN
        SELECT DISTINCT cr.student_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
         WHERE en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
           AND (NOT p_only_sat OR EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam AND a.student_id = cr.student_id AND a.status <> 'IN_PROGRESS'))
    LOOP
        PERFORM platform.queue_notice('EMAIL', x.email, p_subject, p_body || E'\n\n' || e.office || ' Office, ' || (platform.institution() ->> 'name'), 'student', r.student_id)
          FROM people.student_reach(r.student_id) x WHERE x.email IS NOT NULL;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_exam_action(p_exam uuid, p_action text, p_reason text)
RETURNS assessment.cbt_exam LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; v_act text := lower(btrim(coalesce(p_action, ''))); v_ready text; r record;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF v_act = 'schedule' THEN
        IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not scheduled', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF e.starts_at IS NULL OR e.ends_at IS NULL THEN RAISE EXCEPTION 'CBT_WINDOW_REQUIRED: set the date and time the examination opens and closes first' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'SCHEDULED' WHERE id = e.id RETURNING * INTO e;
    ELSIF v_act = 'publish' THEN
        IF e.state NOT IN ('DRAFT', 'SCHEDULED') THEN RAISE EXCEPTION 'CBT_STATE: a % examination is not published', lower(e.state) USING ERRCODE = '23514'; END IF;
        IF e.starts_at IS NULL OR e.ends_at IS NULL THEN RAISE EXCEPTION 'CBT_WINDOW_REQUIRED: set the date and time the examination opens and closes first' USING ERRCODE = '23514'; END IF;
        IF e.ends_at <= now() THEN RAISE EXCEPTION 'CBT_WINDOW_PAST: the examination window has already passed' USING ERRCODE = '23514'; END IF;
        v_ready := assessment.cbt_paper_ready(e.id);
        IF v_ready IS NOT NULL THEN RAISE EXCEPTION '%', v_ready USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET state = 'PUBLISHED', published_at = coalesce(published_at, now()) WHERE id = e.id RETURNING * INTO e;
        PERFORM assessment.cbt_notify_candidates(e.id, e.course_code || ' CBT examination: ' || e.title,
            'Your ' || e.course_code || ' computer-based examination, ' || e.title || ', is scheduled for ' || to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY')
            || ' from ' || to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI') || ' to ' || to_char(e.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI')
            || ' (' || e.duration_minutes || ' minutes once you start). Sign in to the portal, open GST CBT Examinations, read the instructions and start within the window. '
            || 'Your GST fee must be paid and the course on your registration.', false);
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
    ELSE
        RAISE EXCEPTION 'CBT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN e;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_results_action(p_exam uuid, p_action text)
RETURNS assessment.cbt_exam LANGUAGE plpgsql AS $$
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
            'Your result for the ' || e.course_code || ' computer-based examination, ' || e.title || ', is published. Sign in to the portal and open GST CBT Examinations to see it.', true);
    ELSIF v_act = 'unpublish' THEN
        IF e.results_state <> 'PUBLISHED' THEN RAISE EXCEPTION 'CBT_RESULTS_STATE: the results are not published' USING ERRCODE = '23514'; END IF;
        UPDATE assessment.cbt_exam SET results_state = 'APPROVED', results_published_at = NULL WHERE id = e.id RETURNING * INTO e;
    ELSE
        RAISE EXCEPTION 'CBT_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    RETURN e;
END $$;

/* the scores onto the course's score sheet as the examination component, scaled to the course's examination maximum;
   the CA, if entered, kept; without one the mark is INCOMPLETE until the lecturer enters it. The result pipeline is not duplicated. */
CREATE OR REPLACE FUNCTION assessment.cbt_to_sheet(p_exam uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; sh assessment.score_sheet; v_ca_max int; r record; n int := 0; v_exam int; v_version int; v_ca int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
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
        v_exam := CASE WHEN r.outcome = 'VOID' THEN 0 ELSE round(r.percentage * (100 - v_ca_max) / 100.0)::int END;
        SELECT l.version, l.ca INTO v_version, v_ca FROM assessment.latest_scores(sh.id) l WHERE l.student_id = r.student_id;
        IF v_version IS NOT NULL AND EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = sh.id AND s.student_id = r.student_id AND s.version = v_version
                                               AND s.exam = v_exam AND s.reason LIKE 'CBT ' || e.reference || '%') THEN
            CONTINUE;   -- already on the sheet from this examination
        END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (sh.id, r.student_id, coalesce(v_version, 0) + 1, v_ca, v_exam, CASE WHEN v_ca IS NULL THEN 'INCOMPLETE' ELSE 'GRADED' END,
                'CBT ' || e.reference || ': ' || e.title || ' — examination component from the computer-based test');
        n := n + 1;
        v_version := NULL; v_ca := NULL;
    END LOOP;
    RETURN n;
END $$;

-- ── 9 · what the office reads, set-based ─────────────────────────────────────────────────────
/* every registered candidate of an examination with their standing and their latest attempt */
CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
RETURNS TABLE (student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
               programme_code text, programme text, level int, student_status text,
               entitled boolean, eligible boolean, attempts int, attempt_id uuid, attempt_status text, connection text,
               started_at timestamptz, ends_at timestamptz, submitted_at timestamptz, time_left int, last_activity_at timestamptz,
               violations int, answered int, score numeric, max_marks int, percentage numeric, grade text, passed boolean, outcome text, updated_at timestamptz)
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
              WHERE r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.student_id IN (SELECT id FROM base)
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
              GROUP BY r.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM e, finance.gst_fee f WHERE f.session = e.session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    att AS (SELECT DISTINCT ON (a.student_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.student_id, a.number DESC),
    cnt AS (SELECT a.student_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam GROUP BY a.student_id)
    SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
           (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0)) AS entitled,
           -- the gate as registration.gst_gate states it, set-based: unpaid while a fee is stated and the rule holds the course
           NOT (fr.id IS NOT NULL AND fr.amount > 0 AND NOT (coalesce(py.n, 0) > 0)
                AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND (coalesce(e.general_office, 'GST') = 'GST' OR cfg.covers_eps))
                     OR (cfg.required_for_all AND finance.gst_required(b.id, e.session))))
           AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION') AS eligible,
           coalesce(cn.attempts, 0), a.id,
           coalesce(a.status, 'NOT_STARTED'),
           CASE WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED' WHEN a.status = 'IN_PROGRESS' THEN 'ONLINE' ELSE NULL END,
           a.started_at, a.ends_at, a.submitted_at,
           CASE WHEN a.status = 'IN_PROGRESS' THEN greatest(0, extract(epoch FROM a.ends_at - now()))::int ELSE NULL END,
           a.last_activity_at, coalesce(a.violations, 0), coalesce(a.answered, 0), a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at
      FROM e CROSS JOIN cfg CROSS JOIN base b
      LEFT JOIN pays py ON py.student_id = b.id
      LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                          WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                            AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                          ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                          LIMIT 1) fr ON true
      LEFT JOIN att a ON a.student_id = b.id
      LEFT JOIN cnt cn ON cn.student_id = b.id
$$;
COMMENT ON FUNCTION assessment.cbt_candidates(uuid) IS
  'One row per student registered on the examination''s offering (V322): their standing on the GST fee (the gate as registration.gst_gate states it, computed set-based), eligibility, and their latest attempt with its status, connection, clock, violations and score. The source of the candidate list, the monitor and the results.';

/* the live counters of one examination, one pass over its attempts */
CREATE OR REPLACE FUNCTION assessment.cbt_monitor_counts(p_exam uuid)
RETURNS TABLE (candidates bigint, eligible bigint, not_started bigint, in_progress bigint, submitted bigint, time_expired bigint, terminated bigint,
               disconnected bigint, warned bigint, critical bigint, scored bigint, live_state text, now timestamptz)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    reg AS (SELECT count(DISTINCT cr.student_id) AS n FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    el AS (SELECT count(*) FILTER (WHERE c.eligible) AS n FROM assessment.cbt_candidates(p_exam) c),
    att AS (SELECT DISTINCT ON (a.student_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.student_id, a.number DESC),
    agg AS (SELECT count(*) AS started,
                   count(*) FILTER (WHERE status = 'IN_PROGRESS') AS in_progress,
                   count(*) FILTER (WHERE status = 'SUBMITTED') AS submitted,
                   count(*) FILTER (WHERE status = 'TIME_EXPIRED') AS time_expired,
                   count(*) FILTER (WHERE status = 'TERMINATED') AS terminated,
                   count(*) FILTER (WHERE status = 'IN_PROGRESS' AND last_activity_at < now() - interval '60 seconds') AS disconnected,
                   count(*) FILTER (WHERE violations > 0) AS warned,
                   count(*) FILTER (WHERE violations >= (SELECT violation_limit FROM e)) AS critical,
                   count(*) FILTER (WHERE score IS NOT NULL) AS scored
              FROM att)
    SELECT reg.n, el.n, reg.n - agg.started, agg.in_progress, agg.submitted, agg.time_expired, agg.terminated, agg.disconnected, agg.warned, agg.critical, agg.scored,
           assessment.cbt_live_state(e), now()
      FROM e CROSS JOIN reg CROSS JOIN el CROSS JOIN agg
$$;

/* the figures of a sitting */
CREATE OR REPLACE FUNCTION assessment.cbt_exam_stats(p_exam uuid)
RETURNS TABLE (candidates bigint, started bigint, completed bigint, submitted bigint, time_expired bigint, terminated bigint, scored bigint, not_started bigint,
               average numeric, highest numeric, lowest numeric, passed bigint, failed bigint, void bigint)
LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT * FROM assessment.cbt_candidates(p_exam))
    SELECT count(*), count(*) FILTER (WHERE attempt_id IS NOT NULL),
           count(*) FILTER (WHERE attempt_status IN ('SUBMITTED', 'TIME_EXPIRED', 'TERMINATED')),
           count(*) FILTER (WHERE attempt_status = 'SUBMITTED'), count(*) FILTER (WHERE attempt_status = 'TIME_EXPIRED'), count(*) FILTER (WHERE attempt_status = 'TERMINATED'),
           count(*) FILTER (WHERE percentage IS NOT NULL), count(*) FILTER (WHERE attempt_id IS NULL),
           round(avg(percentage) FILTER (WHERE outcome = 'SCORED'), 2), max(percentage) FILTER (WHERE outcome = 'SCORED'), min(percentage) FILTER (WHERE outcome = 'SCORED'),
           count(*) FILTER (WHERE passed), count(*) FILTER (WHERE percentage IS NOT NULL AND NOT passed AND outcome = 'SCORED'), count(*) FILTER (WHERE outcome = 'VOID')
      FROM c
$$;

/* the office's summary for its dashboard */
CREATE OR REPLACE FUNCTION assessment.cbt_office_summary(p_office text, p_session text)
RETURNS TABLE (exams bigint, upcoming bigint, open bigint, completed bigint, draft bigint, writing bigint, scores bigint, results_pending bigint, results_published bigint, candidates bigint)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT x.*, assessment.cbt_live_state(x) AS live FROM assessment.cbt_exam x WHERE x.office = upper(p_office) AND (p_session IS NULL OR x.session = p_session)),
    a AS (SELECT a.exam_id, count(*) FILTER (WHERE a.status = 'IN_PROGRESS') AS writing, count(*) FILTER (WHERE a.score IS NOT NULL) AS scored
            FROM assessment.cbt_attempt a WHERE a.exam_id IN (SELECT id FROM e) GROUP BY a.exam_id),
    reg AS (SELECT e.id, count(DISTINCT cr.student_id) AS n FROM e JOIN registration.entry en ON en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED')
              JOIN registration.course_registration cr ON cr.id = en.registration_id AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED') GROUP BY e.id)
    SELECT count(*), count(*) FILTER (WHERE live IN ('SCHEDULED', 'UPCOMING')), count(*) FILTER (WHERE live = 'OPEN'), count(*) FILTER (WHERE live = 'COMPLETED'),
           count(*) FILTER (WHERE live = 'DRAFT'),
           coalesce(sum(a.writing), 0), coalesce(sum(a.scored), 0),
           count(*) FILTER (WHERE e.state = 'COMPLETED' AND e.results_state <> 'PUBLISHED'), count(*) FILTER (WHERE e.results_state = 'PUBLISHED'),
           coalesce(sum(reg.n), 0)
      FROM e LEFT JOIN a ON a.exam_id = e.id LEFT JOIN reg ON reg.id = e.id
$$;

-- ── 10 · what the student reads ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.cbt_student_exams(p_student uuid, p_session text)
RETURNS TABLE (exam_id uuid, reference text, office text, course_code text, course_title text, title text, session text, semester int, instructions text,
               live_state text, starts_at timestamptz, ends_at timestamptz, duration_minutes int, questions int, security_mode text, venue text,
               attempt_limit int, violation_limit int, violation_action text, eligibility text, attempts int,
               attempt_id uuid, attempt_status text, attempt_ends_at timestamptz, submitted_at timestamptz,
               result_published boolean, score numeric, max_marks int, percentage numeric, grade text, passed boolean, pass_mark numeric, outcome text)
LANGUAGE sql STABLE AS $$
    WITH mine AS (SELECT DISTINCT en.offering_id FROM registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                   WHERE cr.student_id = p_student AND (p_session IS NULL OR cr.session = p_session)
                     AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    att AS (SELECT DISTINCT ON (a.exam_id) a.* FROM assessment.cbt_attempt a WHERE a.student_id = p_student ORDER BY a.exam_id, a.number DESC),
    cnt AS (SELECT a.exam_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.student_id = p_student GROUP BY a.exam_id)
    SELECT e.id, e.reference, e.office, e.course_code, c.title, e.title, e.session, e.semester, e.instructions,
           assessment.cbt_live_state(e), e.starts_at, e.ends_at, e.duration_minutes,
           CASE WHEN e.selection = 'RANDOM' THEN e.total_questions ELSE (SELECT count(*)::int FROM assessment.cbt_pool(e.id)) END,
           e.security_mode, e.venue, e.attempt_limit, e.violation_limit, e.violation_action,
           CASE WHEN a.status = 'IN_PROGRESS' THEN NULL ELSE assessment.cbt_eligibility(e.id, p_student) END,
           coalesce(cn.attempts, 0), a.id, a.status, a.ends_at, a.submitted_at,
           (e.results_state = 'PUBLISHED'),
           CASE WHEN e.results_state = 'PUBLISHED' THEN a.score END, CASE WHEN e.results_state = 'PUBLISHED' THEN a.max_marks END,
           CASE WHEN e.results_state = 'PUBLISHED' THEN a.percentage END, CASE WHEN e.results_state = 'PUBLISHED' THEN a.grade END,
           CASE WHEN e.results_state = 'PUBLISHED' THEN a.passed END, e.pass_mark, CASE WHEN e.results_state = 'PUBLISHED' THEN a.outcome END
      FROM assessment.cbt_exam e JOIN mine m ON m.offering_id = e.offering_id JOIN catalogue.course c ON c.code = e.course_code
      LEFT JOIN att a ON a.exam_id = e.id LEFT JOIN cnt cn ON cn.exam_id = e.id
     WHERE e.state IN ('PUBLISHED', 'CLOSED', 'COMPLETED')
     ORDER BY e.starts_at DESC NULLS LAST, e.title
$$;
COMMENT ON FUNCTION assessment.cbt_student_exams(uuid, text) IS
  'The CBT examinations on a student''s registered courses (V322) with the clock''s word, their eligibility, their attempt, and their result only once the office has published it.';

-- ── 11 · the Super Administrator's data reset clears the examinations with the questions and the students they hang on ──
-- The reset (V292, restated by V318) names every operational table it clears; the property suite checks that a table referencing a
-- cleared one is named. Restated here as V318 left it, with the CBT tables cleared before the questions, the offerings and the students.

CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    -- what is about to go, for the record the caller gets back
    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    -- ── V292: everything added since V108 that hangs on what the reset clears, children first ──
    -- the write-once histories (screening, PUTME, deferment, matric, external examiners) are cleared
    -- under the maintenance flag every one of their triggers honours; it is lifted again below
    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;   -- the deferment and its fee refer to each other
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;   -- an issued document and its transcript request refer to each other (V262)
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

    -- credentials and graduation hung on students
    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;

    -- course spaces (V035) and service requests (V036)
    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    -- health records
    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES, a setting, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    -- library loans (the catalogue of items/copies is kept)
    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    -- hostel allocations (the halls and rooms are kept)
    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- the student's services, timetables, cards
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    -- the Bursary's transaction trail (gateway credentials/billers, a setting, are kept)
    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    -- the student's account and identity on the portal
    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    -- staff profiles a member of staff entered about themselves (V107); the
    -- person and their offices are kept, only the CV they typed is cleared
    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    -- results, registration and the uploaded course structure
    DELETE FROM assessment.sheet_upload;   -- V318: the uploads on behalf hang on the sheets
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;         -- V322: the examinations hang on the questions, the offerings and the students
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    -- the register itself
    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    -- credentials issued (the signing key, a setting, is kept)
    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    -- the admissions intake (the admission POLICY and O'Level grading, settings, are kept)
    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;   -- V106: hangs on application, must go first
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    -- the O'Level sittings are derived from the attachments and reference them,
    -- so they (and the grades that hang on them) go before the attachments.
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $$;

COMMIT;
