-- V374: questions moderated before a paper uses them; an invigilator's screen for each sitting — attendance marked, a late candidate
--       admitted with the time they lost given back — and a limit on late entry the office may set.
--
-- 1  Moderation. A question written or changed waits for moderation (assessment.question.moderation PENDING) until someone other than
--    the person who set that version approves it, or returns it with a note saying what to change. Every decision is kept in
--    assessment.question_moderation (the version, the decision, the note, who and when). Only approved questions go on a paper: a
--    paper holding one that is not approved is neither published nor opened to candidates (cbt_paper_ready, CBT_NOT_MODERATED), the
--    paper checks name it, and a paper drawn from the whole bank draws approved questions only. A change of wording, options, key,
--    kind, marks or explanation (a new version) sends the question back to moderation, and the version now records who made it
--    (updated_by). The questions already in the banks are taken as approved — moderated_by is empty for them, "in the bank before
--    moderation began" — so no examination already set stops.
-- 2  Invigilators. assessment.cbt_invigilator names the staff who invigilate a sitting, one of them the chief if the office says so;
--    each is told by email (or a text when the record holds no email) and finds the sitting under Invigilation. Nobody invigilates
--    two sittings that overlap.
-- 3  Attendance. assessment.cbt_attendance records a seated candidate as ABSENT (once the sitting has begun, and never after they have
--    started) or LATE (admitted late: how late, and the minutes given back — at most the minutes lost, on top of any extra time the
--    office gave). A candidate marked absent does not start; the invigilator undoes the mark if they were wrong. A sitting with marks
--    in it is kept. assessment.cbt_sitting_board is the invigilator's screen: seat by seat, who has not come, who is writing and when
--    they were last heard from, who has submitted — read from the seats, never from the whole candidate list.
-- 4  Late entry. assessment.cbt_exam.late_entry_minutes, when the office sets it, is how long after a sitting begins a candidate may
--    still start on their own; later, the invigilator admits them. It applies to sittings; not set, there is no limit — none is
--    assumed.
-- 5  Found by the load test of a full hall: every answer saved and every heartbeat wrote the whole attempt to the audit trail, before
--    and after. An update of an attempt that moves only its heartbeat (last_activity_at, answered, updated_at) is no longer audited;
--    every other change is, as before, and the answers are kept as they always were.
-- 6  Also found there: the office's live monitor judged every candidate's eligibility again on each two-second read. The two-second
--    read (cbt_monitor_live_counts) leaves it out; the screen reads it on opening and once a minute.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V374: CBT question moderation, invigilators, attendance and late entry', true);

-- ── 1 · moderation ─────────────────────────────────────────────────────────────────────────────────────────────

-- the questions already in the banks are taken as approved (the default as the column is added); every question after is not
ALTER TABLE assessment.question
    ADD COLUMN moderation        text NOT NULL DEFAULT 'APPROVED',
    ADD COLUMN moderated_version int NULL,
    ADD COLUMN moderated_by      uuid NULL,
    ADD COLUMN moderated_at      timestamptz NULL,
    ADD COLUMN moderation_note   text NULL;
ALTER TABLE assessment.question ALTER COLUMN moderation SET DEFAULT 'PENDING';
ALTER TABLE assessment.question ADD CONSTRAINT ck_question_moderation CHECK (moderation IN ('PENDING', 'APPROVED', 'RETURNED'));
ALTER TABLE assessment.question ADD CONSTRAINT ck_question_returned_note CHECK (moderation <> 'RETURNED' OR btrim(coalesce(moderation_note, '')) <> '');
COMMENT ON COLUMN assessment.question.moderation IS
  'V374: PENDING until someone other than the person who set the version approves it (APPROVED) or returns it with a note (RETURNED); a new version is PENDING again. Only APPROVED questions go on a paper. Questions in the bank before V374 are APPROVED with moderated_by empty.';
CREATE INDEX ix_question_awaiting ON assessment.question (course_code, jupeb_subject_id) WHERE moderation <> 'APPROVED';

CREATE TABLE assessment.question_moderation (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id    uuid NOT NULL REFERENCES assessment.question(id) ON DELETE CASCADE,
    version        int  NOT NULL CHECK (version >= 1),
    decision       text NOT NULL CHECK (decision IN ('APPROVED', 'RETURNED')),
    note           text NULL,
    decided_by     uuid NOT NULL,
    decided_office text NULL,
    decided_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_question_moderation_note CHECK (decision = 'APPROVED' OR btrim(coalesce(note, '')) <> '')
);
COMMENT ON TABLE assessment.question_moderation IS 'V374: every moderation decision on a question — the version decided on, approved or returned, the note, who and when.';
CREATE INDEX ix_question_moderation ON assessment.question_moderation (question_id, decided_at DESC);
SELECT audit.attach('assessment.question_moderation');

/* who set a version of a question: the person who made that version, else the question's last editor or author */
CREATE OR REPLACE FUNCTION assessment.question_setter(p_question uuid, p_version int)
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT coalesce(v.created_by, q.updated_by, q.authored_by)
      FROM assessment.question q LEFT JOIN assessment.question_version v ON v.question_id = q.id AND v.version = p_version
     WHERE q.id = p_question
$$;

/* a question written now waits for moderation, whatever the writer says */
CREATE OR REPLACE FUNCTION assessment.question_awaits_moderation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.moderation := 'PENDING';
    NEW.moderated_version := NULL; NEW.moderated_by := NULL; NEW.moderated_at := NULL; NEW.moderation_note := NULL;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_question_awaits_moderation BEFORE INSERT ON assessment.question FOR EACH ROW EXECUTE FUNCTION assessment.question_awaits_moderation();

CREATE OR REPLACE FUNCTION assessment.question_versioned()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF (NEW.stem, NEW.options, NEW.answers, NEW.kind, NEW.marks, NEW.explanation) IS DISTINCT FROM (OLD.stem, OLD.options, OLD.answers, OLD.kind, OLD.marks, OLD.explanation) THEN
        NEW.version := OLD.version + 1;
        -- V374: the new version is the changer's, and waits for moderation again
        NEW.updated_by := coalesce(who, NEW.updated_by);
        NEW.updated_at := now();
        NEW.moderation := 'PENDING';
        NEW.moderated_version := NULL; NEW.moderated_by := NULL; NEW.moderated_at := NULL; NEW.moderation_note := NULL;
    ELSE
        NEW.version := OLD.version;
        -- V374: a version is approved by someone other than the person who set it
        IF NEW.moderation = 'APPROVED' AND OLD.moderation IS DISTINCT FROM 'APPROVED'
           AND (NEW.moderated_by IS NULL OR NEW.moderated_by IS NOT DISTINCT FROM assessment.question_setter(NEW.id, NEW.version)) THEN
            RAISE EXCEPTION 'CBT_MODERATE_OWN: a question is approved by someone other than the person who set it' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;

/* why a decision on a question cannot be made now, or NULL */
CREATE OR REPLACE FUNCTION assessment.question_moderation_problem(p_question uuid, p_decision text, p_note text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; q assessment.question; v_live text;
        v_decision text := upper(btrim(coalesce(p_decision, '')));
BEGIN
    IF who IS NULL THEN RETURN 'CBT_MODERATOR_REQUIRED: a question is moderated by a person'; END IF;
    IF v_decision NOT IN ('APPROVE', 'RETURN') THEN RETURN 'CBT_MODERATION_DECISION: a question is approved or returned'; END IF;
    SELECT * INTO q FROM assessment.question WHERE id = p_question;
    IF NOT FOUND THEN RETURN 'CBT_QUESTION_NOT_FOUND: no such question'; END IF;
    IF q.archived_at IS NOT NULL THEN RETURN 'CBT_QUESTION_ARCHIVED: an archived question is kept as it was'; END IF;
    IF v_decision = 'RETURN' AND btrim(coalesce(p_note, '')) = '' THEN
        RETURN 'CBT_REASON_REQUIRED: a question is returned with a note saying what to change';
    END IF;
    IF who IS NOT DISTINCT FROM assessment.question_setter(q.id, q.version) THEN
        RETURN 'CBT_MODERATE_OWN: a question is moderated by someone other than the person who set it';
    END IF;
    IF v_decision = 'RETURN' THEN
        v_live := assessment.question_in_live_exam(q.id);
        IF v_live IS NOT NULL THEN
            RETURN format('CBT_QUESTION_IN_LIVE_EXAM: the question is on the paper of %s, which is published to candidates; it is returned once that closes', v_live);
        END IF;
    END IF;
    RETURN NULL;
END $$;

/* a question approved, or returned with a note, by someone other than its setter; the decision kept */
CREATE OR REPLACE FUNCTION assessment.question_moderate(p_question uuid, p_decision text, p_note text)
RETURNS assessment.question LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        q assessment.question; v_problem text; v_state text;
BEGIN
    PERFORM 1 FROM assessment.question WHERE id = p_question FOR UPDATE;
    v_problem := assessment.question_moderation_problem(p_question, p_decision, p_note);
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION '%', v_problem USING ERRCODE = '23514'; END IF;
    v_state := CASE upper(btrim(p_decision)) WHEN 'APPROVE' THEN 'APPROVED' ELSE 'RETURNED' END;
    UPDATE assessment.question
       SET moderation = v_state, moderated_version = version, moderated_by = who, moderated_at = now(), moderation_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_question RETURNING * INTO q;
    INSERT INTO assessment.question_moderation (question_id, version, decision, note, decided_by, decided_office)
    VALUES (q.id, q.version, v_state, q.moderation_note, who, actor);
    RETURN q;
END $$;

-- a paper draws approved questions only; one holding a question not approved is not ready
CREATE OR REPLACE FUNCTION assessment.cbt_pool(p_exam uuid)
RETURNS TABLE(question_id uuid, ordinal integer, marks integer)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
         own AS (SELECT eq.question_id, eq.ordinal, coalesce(eq.marks, q.marks) AS marks
                   FROM assessment.cbt_exam_question eq JOIN assessment.question q ON q.id = eq.question_id AND q.active
                  WHERE eq.exam_id = p_exam)
    SELECT * FROM own
    UNION ALL
    SELECT q.id, 0, q.marks FROM e JOIN assessment.question q ON (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id) AND q.active
                                                              AND q.moderation = 'APPROVED'
     WHERE e.selection = 'RANDOM' AND NOT EXISTS (SELECT 1 FROM own)
$$;

CREATE OR REPLACE FUNCTION assessment.question_in_live_exam(p_question uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT e.reference FROM assessment.cbt_exam e
      JOIN assessment.question q ON q.id = p_question AND (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id)
     WHERE e.state = 'PUBLISHED' AND e.ends_at > now()
       AND (EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id AND eq.question_id = p_question)
            OR (e.selection = 'RANDOM' AND q.moderation = 'APPROVED' AND NOT EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id)))
     LIMIT 1
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_paper_ready(p_exam uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e assessment.cbt_exam; n int; v_waiting int;
BEGIN
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    SELECT count(*) INTO n FROM assessment.cbt_pool(p_exam);
    -- V374: every question on the paper approved by a moderator
    SELECT count(*) INTO v_waiting FROM assessment.cbt_exam_question eq JOIN assessment.question q ON q.id = eq.question_id AND q.active
     WHERE eq.exam_id = p_exam AND q.moderation <> 'APPROVED';
    IF v_waiting > 0 THEN
        RETURN format('CBT_NOT_MODERATED: %s question%s on the paper %s not been approved by a moderator', v_waiting,
                      CASE WHEN v_waiting = 1 THEN '' ELSE 's' END, CASE WHEN v_waiting = 1 THEN 'has' ELSE 'have' END);
    END IF;
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

CREATE OR REPLACE FUNCTION assessment.cbt_paper_checks(p_exam uuid)
RETURNS TABLE (n int, question_id uuid, severity text, code text, detail text)
LANGUAGE sql STABLE AS $$
WITH e AS (
    SELECT * FROM assessment.cbt_exam WHERE id = p_exam
), p AS (
    SELECT (row_number() OVER (ORDER BY pl.ordinal, q.authored_at, q.id))::int AS n, q.id,
           coalesce(qv.kind, q.kind, 'MCQ') AS kind, coalesce(qv.stem, q.stem) AS stem, coalesce(qv.options, q.options) AS options,
           coalesce(qv.answers, q.answers, ARRAY[q.answer]) AS answers, q.moderation, q.moderation_note
      FROM assessment.cbt_pool(p_exam) pl
      JOIN assessment.question q ON q.id = pl.question_id
      LEFT JOIN assessment.question_version qv ON qv.question_id = q.id AND qv.version = q.version
), o AS (
    SELECT p.n, p.id, p.answers, (x.i - 1)::int AS i, x.t, lower(regexp_replace(btrim(x.t), '\s+', ' ', 'g')) AS nt
      FROM p CROSS JOIN LATERAL jsonb_array_elements_text(p.options) WITH ORDINALITY x(t, i)
), sig AS (
    -- a question's wording and its options, as a reader sees them
    SELECT p.n, p.id, lower(regexp_replace(btrim(p.stem), '\s+', ' ', 'g')) || ' | ' || coalesce((SELECT string_agg(o.nt, ' | ' ORDER BY o.nt) FROM o WHERE o.id = p.id), '') AS s
      FROM p
), keys AS (
    SELECT p.answers[1] AS k, count(*)::int AS c, sum(count(*)) OVER ()::int AS total
      FROM p WHERE p.kind = 'MCQ' GROUP BY p.answers[1]
)
SELECT * FROM (
    SELECT a.n, a.id, 'MEDIUM'::text, 'DUPLICATE_QUESTION'::text, 'The same question, with the same options, as question ' || min(b.n) || '.'
      FROM sig a JOIN sig b ON b.s = a.s AND b.n < a.n GROUP BY a.n, a.id
    UNION ALL
    SELECT x.n, x.id, CASE WHEN (x.i = ANY (x.answers)) <> (y.i = ANY (x.answers)) THEN 'HIGH' ELSE 'MEDIUM' END, 'REPEATED_OPTION',
           'Options ' || chr(65 + y.i) || ' and ' || chr(65 + x.i) || ' read the same'
           || CASE WHEN (x.i = ANY (x.answers)) <> (y.i = ANY (x.answers)) THEN ', and only one of them is marked correct.' ELSE '.' END
      FROM o x JOIN o y ON y.id = x.id AND y.i < x.i AND y.nt = x.nt AND x.nt <> ''
    UNION ALL
    SELECT x.n, x.id, 'HIGH', 'BLANK_OPTION', 'Option ' || chr(65 + x.i) || ' has no text.' FROM o x WHERE x.nt = ''
    UNION ALL
    SELECT x.n, x.id, 'HIGH', 'POSITIONAL_OPTION',
           'Option ' || chr(65 + x.i) || ' ("' || left(btrim(x.t), 60) || '") points at the other options by their place, but the options are shuffled for each candidate.'
      FROM o x, e
     WHERE e.randomize_options
       AND (x.nt ~ '(all|none|both|neither|either) of the (above|below|preceding|options|foregoing)'
            OR x.nt ~ '^(options? )?[a-e] (and|or|&) [a-e]\.?$' OR x.nt ~ '^(only )?[a-e] and [a-e] (only|are correct)')
    UNION ALL
    SELECT p.n, p.id, 'LOW', 'MULTI_ONE_KEY',
           'A select-every-correct-option question with only one correct option: candidates may look for more. A single-answer question may suit it better.'
      FROM p WHERE p.kind = 'MULTI' AND cardinality(p.answers) = 1
    UNION ALL
    SELECT p.n, p.id, 'HIGH', 'NOT_MODERATED',
           CASE WHEN p.moderation = 'RETURNED' THEN 'Returned by the moderator: ' || coalesce(p.moderation_note, 'see the bank') || '. Correct it in the bank, or take it off the paper.'
                ELSE 'Not yet approved by a moderator: a question goes on a paper once someone other than the person who set it approves it.' END
      FROM p WHERE p.moderation <> 'APPROVED'
    UNION ALL
    SELECT NULL::int, NULL::uuid, 'LOW', 'BANK_AWAITING',
           w.c || ' question' || CASE WHEN w.c = 1 THEN '' ELSE 's' END || ' in the bank await' || CASE WHEN w.c = 1 THEN 's' ELSE '' END
           || ' moderation and ' || CASE WHEN w.c = 1 THEN 'is' ELSE 'are' END || ' not drawn until approved.'
      FROM e CROSS JOIN LATERAL (SELECT count(*)::int AS c FROM assessment.question q
                                  WHERE (q.course_code = e.course_code OR q.jupeb_subject_id = e.jupeb_subject_id) AND q.active AND q.moderation <> 'APPROVED') w
     WHERE e.selection = 'RANDOM' AND w.c > 0 AND NOT EXISTS (SELECT 1 FROM assessment.cbt_exam_question eq WHERE eq.exam_id = e.id)
    UNION ALL
    SELECT NULL::int, NULL::uuid, 'LOW', 'KEYS_BUNCHED',
           round(100.0 * keys.c / keys.total) || '% of the single-answer questions (' || keys.c || ' of ' || keys.total || ') have option '
           || chr(65 + keys.k) || ' as their answer, and the options are not shuffled for each candidate: candidates may notice the pattern.'
      FROM keys, e WHERE NOT e.randomize_options AND keys.total >= 10 AND keys.c * 2 >= keys.total
) c(n, question_id, severity, code, detail)
ORDER BY CASE c.severity WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 ELSE 2 END, c.n NULLS FIRST, c.code
$$;

-- ── 2 · invigilators ───────────────────────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.cbt_exam ADD COLUMN late_entry_minutes int NULL CONSTRAINT ck_cbt_exam_late_entry CHECK (late_entry_minutes BETWEEN 0 AND 600);
COMMENT ON COLUMN assessment.cbt_exam.late_entry_minutes IS
  'V374: how many minutes after their sitting begins a candidate may still start on their own; later, the invigilator admits them (assessment.cbt_attendance LATE). NULL = no limit; none is assumed.';

CREATE TABLE assessment.cbt_invigilator (
    sitting_id      uuid NOT NULL REFERENCES assessment.cbt_sitting(id) ON DELETE CASCADE,
    person_id       uuid NOT NULL REFERENCES iam.person(id),
    chief           boolean NOT NULL DEFAULT false,
    assigned_by     uuid NOT NULL,
    assigned_office text NULL,
    assigned_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (sitting_id, person_id)
);
COMMENT ON TABLE assessment.cbt_invigilator IS 'V374: the staff who invigilate a sitting of a CBT examination, one of them the chief if the office says so. They see the sitting''s seats and mark its attendance.';
CREATE UNIQUE INDEX ux_cbt_invigilator_chief ON assessment.cbt_invigilator (sitting_id) WHERE chief;
CREATE INDEX ix_cbt_invigilator_person ON assessment.cbt_invigilator (person_id);
SELECT audit.attach('assessment.cbt_invigilator');

CREATE TABLE assessment.cbt_attendance (
    sitting_id    uuid NOT NULL REFERENCES assessment.cbt_sitting(id) ON DELETE CASCADE,
    candidate_id  uuid NOT NULL,
    exam_id       uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    status        text NOT NULL CHECK (status IN ('ABSENT', 'LATE')),
    minutes_late  int NULL CHECK (minutes_late >= 0),
    minutes_given int NOT NULL DEFAULT 0 CHECK (minutes_given BETWEEN 0 AND 600),
    note          text NULL,
    marked_by     uuid NOT NULL,
    marked_office text NULL,
    marked_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (sitting_id, candidate_id),
    CONSTRAINT ck_cbt_attendance_late CHECK (status = 'LATE' OR (minutes_late IS NULL AND minutes_given = 0)),
    CONSTRAINT ck_cbt_attendance_given CHECK (status <> 'LATE' OR (minutes_late IS NOT NULL AND minutes_given <= minutes_late))
);
COMMENT ON TABLE assessment.cbt_attendance IS
  'V374: an invigilator''s mark on a seated candidate — ABSENT (does not start), or LATE (admitted late: how late, and the minutes given back, at most the minutes lost). A candidate with no mark and no attempt has simply not come.';
CREATE INDEX ix_cbt_attendance_exam ON assessment.cbt_attendance (exam_id, candidate_id);
SELECT audit.attach('assessment.cbt_attendance');

GRANT SELECT ON assessment.question_moderation, assessment.cbt_invigilator, assessment.cbt_attendance TO app_auditor;

/* what a CBT examination is called in a notice: its course, or its JUPEB subject */
CREATE OR REPLACE FUNCTION assessment.cbt_exam_name(e assessment.cbt_exam)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(e.course_code, (SELECT 'JUPEB ' || s.code FROM jupeb.subject s WHERE s.id = e.jupeb_subject_id), 'CBT')
$$;

/* a member of staff named to invigilate a sitting — never two overlapping sittings — and told so */
CREATE OR REPLACE FUNCTION assessment.cbt_assign_invigilator(p_sitting uuid, p_person uuid, p_chief boolean)
RETURNS assessment.cbt_invigilator LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; e assessment.cbt_exam; p iam.person; v_busy record; x assessment.cbt_invigilator; v_new boolean; v_subject text; v_body text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an invigilator is named by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = s.exam_id;
    IF e.state IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: the invigilators of a % examination are not changed', lower(e.state) USING ERRCODE = '23514'; END IF;
    IF s.ends_at <= now() THEN RAISE EXCEPTION 'CBT_SITTING_OVER: % has ended; its invigilators are kept as they were', s.label USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM iam.person WHERE id = p_person;
    IF NOT FOUND OR p.ended_on IS NOT NULL
       OR NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_person AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)) THEN
        RAISE EXCEPTION 'CBT_INVIGILATOR_NOT_STAFF: an invigilator is a member of staff holding an office today' USING ERRCODE = '23514';
    END IF;
    SELECT o.label, o.venue, o.starts_at, o.ends_at, assessment.cbt_exam_name(oe) AS what INTO v_busy
      FROM assessment.cbt_invigilator i JOIN assessment.cbt_sitting o ON o.id = i.sitting_id JOIN assessment.cbt_exam oe ON oe.id = o.exam_id
     WHERE i.person_id = p_person AND o.id <> s.id AND oe.state <> 'CANCELLED' AND o.starts_at < s.ends_at AND o.ends_at > s.starts_at
     ORDER BY o.starts_at LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'CBT_INVIGILATOR_BUSY: % % already invigilates % (%, %) at the same time, % to %', p.given_names, p.surname, v_busy.what, v_busy.label, v_busy.venue,
            to_char(v_busy.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon HH24:MI'), to_char(v_busy.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI') USING ERRCODE = '23514';
    END IF;
    v_new := NOT EXISTS (SELECT 1 FROM assessment.cbt_invigilator i WHERE i.sitting_id = s.id AND i.person_id = p_person);
    IF coalesce(p_chief, false) THEN
        UPDATE assessment.cbt_invigilator SET chief = false WHERE sitting_id = s.id AND person_id <> p_person AND chief;
    END IF;
    INSERT INTO assessment.cbt_invigilator (sitting_id, person_id, chief, assigned_by, assigned_office)
    VALUES (s.id, p_person, coalesce(p_chief, false), who, actor)
    ON CONFLICT (sitting_id, person_id) DO UPDATE SET chief = EXCLUDED.chief
    RETURNING * INTO x;
    IF v_new THEN
        v_subject := 'Invigilation: ' || assessment.cbt_exam_name(e) || ' CBT, ' || s.label;
        v_body := 'You are named ' || CASE WHEN x.chief THEN 'the chief invigilator' ELSE 'an invigilator' END || ' for the ' || assessment.cbt_exam_name(e)
               || ' computer-based examination "' || e.title || '", ' || s.label || ' at ' || s.venue || ', '
               || to_char(s.starts_at AT TIME ZONE 'Africa/Lagos', 'Dy DD Mon YYYY HH24:MI') || ' to ' || to_char(s.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI')
               || '. Sign in to the portal and open Invigilation to see the sitting''s seats as candidates arrive, start and submit.';
        IF nullif(btrim(coalesce(p.email, '')), '') IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', btrim(p.email), v_subject, v_body, 'person', p.id);
        ELSIF nullif(btrim(coalesce(p.phone, '')), '') IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', btrim(p.phone), v_subject,
                'MOAUM: you are to invigilate ' || assessment.cbt_exam_name(e) || ' CBT, ' || s.label || ', ' || s.venue || ', '
                || to_char(s.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon HH24:MI') || '. See Invigilation on the portal.', 'person', p.id);
        END IF;
    END IF;
    RETURN x;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_unassign_invigilator(p_sitting uuid, p_person uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s assessment.cbt_sitting; n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an invigilator is named by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    IF s.ends_at <= now() THEN RAISE EXCEPTION 'CBT_SITTING_OVER: % has ended; its invigilators are kept as they were', s.label USING ERRCODE = '23514'; END IF;
    DELETE FROM assessment.cbt_invigilator WHERE sitting_id = s.id AND person_id = p_person;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- ── 3 · attendance ─────────────────────────────────────────────────────────────────────────────────────────────

/* the sitting, checked to seat the candidate */
CREATE OR REPLACE FUNCTION assessment.cbt_seated_sitting(p_sitting uuid, p_candidate uuid)
RETURNS assessment.cbt_sitting LANGUAGE plpgsql STABLE AS $$
DECLARE s assessment.cbt_sitting;
BEGIN
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.cbt_seat x WHERE x.sitting_id = s.id AND x.candidate_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_NOT_IN_SITTING: the candidate is not seated in %', s.label USING ERRCODE = '23514';
    END IF;
    RETURN s;
END $$;

/* a seated candidate marked absent, once the sitting has begun and while they have not started */
CREATE OR REPLACE FUNCTION assessment.cbt_mark_absent(p_sitting uuid, p_candidate uuid, p_note text)
RETURNS assessment.cbt_attendance LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; m assessment.cbt_attendance;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is marked by a person' USING ERRCODE = '23514'; END IF;
    s := assessment.cbt_seated_sitting(p_sitting, p_candidate);
    PERFORM pg_advisory_xact_lock(hashtext(s.exam_id::text || ':' || p_candidate::text));
    IF now() < s.starts_at THEN RAISE EXCEPTION 'CBT_ABSENT_EARLY: a candidate is marked absent once % has begun', s.label USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = s.exam_id AND a.candidate_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_ABSENT_BEGUN: the candidate has started the examination; they are not absent' USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.cbt_attendance (sitting_id, candidate_id, exam_id, status, note, marked_by, marked_office)
    VALUES (s.id, p_candidate, s.exam_id, 'ABSENT', nullif(btrim(coalesce(p_note, '')), ''), who, actor)
    ON CONFLICT (sitting_id, candidate_id) DO UPDATE SET status = 'ABSENT', minutes_late = NULL, minutes_given = 0, note = EXCLUDED.note,
        marked_by = EXCLUDED.marked_by, marked_office = EXCLUDED.marked_office, marked_at = now()
    RETURNING * INTO m;
    RETURN m;
END $$;

/* a candidate who came late admitted while the sitting runs, with up to the minutes they lost given back on top of any extra time */
CREATE OR REPLACE FUNCTION assessment.cbt_admit_late(p_sitting uuid, p_candidate uuid, p_minutes int, p_note text)
RETURNS assessment.cbt_attendance LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; m assessment.cbt_attendance; v_late int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is marked by a person' USING ERRCODE = '23514'; END IF;
    s := assessment.cbt_seated_sitting(p_sitting, p_candidate);
    PERFORM pg_advisory_xact_lock(hashtext(s.exam_id::text || ':' || p_candidate::text));
    IF now() < s.starts_at THEN RAISE EXCEPTION 'CBT_NOT_LATE: % has not begun; the candidate is not late', s.label USING ERRCODE = '23514'; END IF;
    IF now() >= s.ends_at THEN RAISE EXCEPTION 'CBT_SITTING_OVER: % has ended', s.label USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = s.exam_id AND a.candidate_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_ALREADY_BEGUN: the candidate has already started the examination' USING ERRCODE = '23514';
    END IF;
    v_late := ceil(extract(epoch FROM now() - s.starts_at) / 60)::int;
    IF p_minutes IS NULL OR p_minutes < 0 OR p_minutes > v_late THEN
        RAISE EXCEPTION 'CBT_LATE_MINUTES: a late candidate is given back 0 to % minutes, the time they lost', v_late USING ERRCODE = '23514',
            HINT = 'More time than that is extra time, given by the examination office with its reason.';
    END IF;
    INSERT INTO assessment.cbt_attendance (sitting_id, candidate_id, exam_id, status, minutes_late, minutes_given, note, marked_by, marked_office)
    VALUES (s.id, p_candidate, s.exam_id, 'LATE', v_late, p_minutes, nullif(btrim(coalesce(p_note, '')), ''), who, actor)
    ON CONFLICT (sitting_id, candidate_id) DO UPDATE SET status = 'LATE', minutes_late = EXCLUDED.minutes_late, minutes_given = EXCLUDED.minutes_given,
        note = EXCLUDED.note, marked_by = EXCLUDED.marked_by, marked_office = EXCLUDED.marked_office, marked_at = now()
    RETURNING * INTO m;
    RETURN m;
END $$;

/* a mark taken back — never an admission the candidate started on */
CREATE OR REPLACE FUNCTION assessment.cbt_clear_mark(p_sitting uuid, p_candidate uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s assessment.cbt_sitting; n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is marked by a person' USING ERRCODE = '23514'; END IF;
    s := assessment.cbt_seated_sitting(p_sitting, p_candidate);
    PERFORM pg_advisory_xact_lock(hashtext(s.exam_id::text || ':' || p_candidate::text));
    IF EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = s.exam_id AND a.candidate_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_MARK_KEPT: the candidate started on this admission; it stays on the record' USING ERRCODE = '23514';
    END IF;
    DELETE FROM assessment.cbt_attendance WHERE sitting_id = s.id AND candidate_id = p_candidate;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

/* every seated candidate of a begun sitting who has not come and has no mark, marked absent */
CREATE OR REPLACE FUNCTION assessment.cbt_mark_rest_absent(p_sitting uuid, p_note text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is marked by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    IF now() < s.starts_at THEN RAISE EXCEPTION 'CBT_ABSENT_EARLY: a candidate is marked absent once % has begun', s.label USING ERRCODE = '23514'; END IF;
    INSERT INTO assessment.cbt_attendance (sitting_id, candidate_id, exam_id, status, note, marked_by, marked_office)
    SELECT s.id, x.candidate_id, s.exam_id, 'ABSENT', nullif(btrim(coalesce(p_note, '')), ''), who, actor
      FROM assessment.cbt_seat x
     WHERE x.sitting_id = s.id
       AND NOT EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = s.exam_id AND a.candidate_id = x.candidate_id)
       AND NOT EXISTS (SELECT 1 FROM assessment.cbt_attendance m WHERE m.sitting_id = s.id AND m.candidate_id = x.candidate_id);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

/* the invigilator's screen: seat by seat, the candidate, where they are (not come, absent, admitted, writing, disconnected, time up,
   submitted, time expired, terminated), how far through, and the marks — read from the sitting's seats alone */
CREATE OR REPLACE FUNCTION assessment.cbt_sitting_board(p_sitting uuid)
RETURNS TABLE (seat_no int, candidate_id uuid, number text, surname text, other_names text, level int, programme text, state text,
               attempt_id uuid, started_at timestamptz, ends_at timestamptz, submitted_at timestamptz, last_activity_at timestamptz,
               answered int, questions int, violations int, extra_minutes int, mark text, minutes_late int, minutes_given int,
               mark_note text, marked_at timestamptz, marked_by text)
LANGUAGE sql STABLE AS $$
    SELECT x.seat_no, x.candidate_id,
           coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no),
           coalesce(st.surname, upper(ja.surname)),
           coalesce(st.other_names, ja.first_name || coalesce(' ' || ja.middle_name, '')),
           st.current_level,
           coalesce(p.name, cb.name),
           CASE WHEN a.id IS NULL THEN CASE m.status WHEN 'ABSENT' THEN 'ABSENT' WHEN 'LATE' THEN 'ADMITTED' ELSE 'NOT_COME' END
                WHEN a.status = 'IN_PROGRESS' AND a.ends_at <= now() THEN 'TIME_UP'
                WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED'
                WHEN a.status = 'IN_PROGRESS' THEN 'WRITING'
                ELSE a.status END,
           a.id, a.started_at, a.ends_at, a.submitted_at, a.last_activity_at, a.answered, cardinality(a.question_ids), a.violations,
           xt.minutes, m.status, m.minutes_late, m.minutes_given, m.note, m.marked_at,
           CASE WHEN pm.id IS NULL THEN NULL ELSE pm.surname || ', ' || pm.given_names END
      FROM assessment.cbt_seat x
      LEFT JOIN people.student st ON st.id = x.candidate_id
      LEFT JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN jupeb.application ja ON st.id IS NULL AND ja.id = x.candidate_id
      LEFT JOIN jupeb.combination cb ON cb.id = ja.combination_id
      LEFT JOIN LATERAL (SELECT t.* FROM assessment.cbt_attempt t WHERE t.exam_id = x.exam_id AND t.candidate_id = x.candidate_id ORDER BY t.number DESC LIMIT 1) a ON true
      LEFT JOIN assessment.cbt_extra_time xt ON xt.exam_id = x.exam_id AND xt.candidate_id = x.candidate_id
      LEFT JOIN assessment.cbt_attendance m ON m.sitting_id = x.sitting_id AND m.candidate_id = x.candidate_id
      LEFT JOIN iam.person pm ON pm.id = m.marked_by
     WHERE x.sitting_id = p_sitting
     ORDER BY x.seat_no
$$;

/* the office's late-entry limit for an examination's sittings: NULL for none */
CREATE OR REPLACE FUNCTION assessment.cbt_set_late_entry(p_exam uuid, p_minutes int)
RETURNS assessment.cbt_exam LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.cbt_exam;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'late entry is set by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.state IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: the late entry of a % examination is not changed', lower(e.state) USING ERRCODE = '23514'; END IF;
    IF p_minutes IS NOT NULL AND (p_minutes < 0 OR p_minutes > 600) THEN
        RAISE EXCEPTION 'CBT_LATE_ENTRY_RANGE: late entry is 0 to 600 minutes after a sitting begins, or no limit' USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.cbt_exam SET late_entry_minutes = p_minutes WHERE id = e.id RETURNING * INTO e;
    RETURN e;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_remove_sitting(p_sitting uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s assessment.cbt_sitting; v_seated int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a sitting is set by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    IF EXISTS (SELECT 1 FROM assessment.cbt_seat x JOIN assessment.cbt_attempt a ON a.exam_id = x.exam_id AND a.candidate_id = x.candidate_id WHERE x.sitting_id = s.id) THEN
        RAISE EXCEPTION 'CBT_SITTING_SAT: a candidate of this sitting has begun the examination; the sitting is kept' USING ERRCODE = '23514';
    END IF;
    -- V374: the invigilator's marks are a record
    IF EXISTS (SELECT 1 FROM assessment.cbt_attendance m WHERE m.sitting_id = s.id) THEN
        RAISE EXCEPTION 'CBT_SITTING_MARKED: the invigilator has marked attendance in this sitting; the sitting is kept' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_seated FROM assessment.cbt_seat WHERE sitting_id = s.id;
    DELETE FROM assessment.cbt_sitting WHERE id = s.id;
    RETURN v_seated;
END $$;

-- ── 4 · the start: a candidate marked absent does not start; one past the late-entry limit starts once admitted ──

CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; a assessment.cbt_attempt; v_why text; v_seed int; v_paper uuid[]; v_versions int[]; v_marks int[]; v_n int; v_jupeb boolean;
        v_sit assessment.cbt_sitting; v_extra int; v_mark assessment.cbt_attendance;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(p_exam::text || ':' || p_student::text));
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam;
    v_jupeb := e.office = 'JUPEB';
    SELECT * INTO a FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student AND status = 'IN_PROGRESS';
    IF FOUND THEN
        IF a.ends_at <= now() THEN
            a := assessment.cbt_finalize(a.id, 'TIME_EXPIRED', 'time expired before the candidate returned');
        ELSE
            IF e.second_session = 'DENY' THEN
                PERFORM assessment.cbt_log(a.id, 'MULTIPLE_LOGIN', true, 'a second sign-in was refused', p_ip);
                UPDATE assessment.cbt_attempt SET violations = violations + 1, last_activity_at = now() WHERE id = a.id;
                RAISE EXCEPTION 'CBT_SECOND_SESSION_DENIED: your examination is already open on another browser or device' USING ERRCODE = '23514',
                    HINT = 'Return to the screen where you started it. The attempt is recorded.';
            END IF;
            IF e.second_session = 'MONITOR' THEN
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
    -- V373: an examination sat in sittings opens to a candidate only in their own sitting
    IF EXISTS (SELECT 1 FROM assessment.cbt_sitting s WHERE s.exam_id = p_exam) THEN
        SELECT s.* INTO v_sit FROM assessment.cbt_seat x JOIN assessment.cbt_sitting s ON s.id = x.sitting_id WHERE x.exam_id = p_exam AND x.candidate_id = p_student;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'CBT_NO_SITTING: you have no seat in this examination''s sittings' USING ERRCODE = '23514',
                HINT = 'The examination office seats every candidate; ask it for your sitting.';
        END IF;
        IF now() < v_sit.starts_at OR now() >= v_sit.ends_at THEN
            RAISE EXCEPTION 'CBT_NOT_YOUR_SITTING: your sitting is % at %, % to %', v_sit.label, v_sit.venue,
                to_char(v_sit.starts_at AT TIME ZONE 'Africa/Lagos', 'Dy DD Mon YYYY HH24:MI'), to_char(v_sit.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI') USING ERRCODE = '23514';
        END IF;
    END IF;
    -- V374: in a sitting, a candidate the invigilator marked absent does not start; past the office's late-entry limit, one starts once admitted
    IF v_sit.id IS NOT NULL THEN
        SELECT m.* INTO v_mark FROM assessment.cbt_attendance m WHERE m.sitting_id = v_sit.id AND m.candidate_id = p_student;
        IF v_mark.status = 'ABSENT' THEN
            RAISE EXCEPTION 'CBT_MARKED_ABSENT: the invigilator has marked you absent from %', v_sit.label USING ERRCODE = '23514',
                HINT = 'If you are in the examination hall, ask the invigilator to admit you.';
        END IF;
        IF e.late_entry_minutes IS NOT NULL AND v_mark.status IS DISTINCT FROM 'LATE'
           AND now() > v_sit.starts_at + make_interval(mins => e.late_entry_minutes)
           AND NOT EXISTS (SELECT 1 FROM assessment.cbt_attempt x WHERE x.exam_id = p_exam AND x.candidate_id = p_student) THEN
            RAISE EXCEPTION 'CBT_LATE_ENTRY: entry to % closed % minutes after it began, at %', v_sit.label, e.late_entry_minutes,
                to_char((v_sit.starts_at + make_interval(mins => e.late_entry_minutes)) AT TIME ZONE 'Africa/Lagos', 'HH24:MI') USING ERRCODE = '23514',
                HINT = 'Ask the invigilator to admit you.';
        END IF;
    END IF;
    -- V373: extra time the office granted the candidate, on top of the time every candidate has
    SELECT x.minutes INTO v_extra FROM assessment.cbt_extra_time x WHERE x.exam_id = p_exam AND x.candidate_id = p_student;
    v_extra := coalesce(v_extra, 0);
    -- V374: and the minutes the invigilator gave back to a candidate admitted late
    IF v_mark.status = 'LATE' THEN v_extra := v_extra + v_mark.minutes_given; END IF;
    v_seed := (('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 7))::bit(28))::int;
    v_paper := assessment.cbt_paper(p_exam, v_seed);
    IF coalesce(cardinality(v_paper), 0) = 0 THEN RAISE EXCEPTION 'CBT_PAPER_EMPTY: the paper has no questions' USING ERRCODE = '23514'; END IF;
    SELECT array_agg(q.version ORDER BY u.n), array_agg(p.marks ORDER BY u.n) INTO v_versions, v_marks
      FROM unnest(v_paper) WITH ORDINALITY u(qid, n)
      JOIN assessment.question q ON q.id = u.qid
      JOIN assessment.cbt_pool(p_exam) p ON p.question_id = u.qid;
    IF coalesce(cardinality(v_versions), 0) <> cardinality(v_paper) THEN
        RAISE EXCEPTION 'CBT_PAPER_CHANGED: the paper changed as the attempt began; start again' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_n FROM assessment.cbt_attempt WHERE exam_id = p_exam AND candidate_id = p_student;
    INSERT INTO assessment.cbt_attempt (exam_id, student_id, jupeb_application_id, number, ends_at, question_ids, question_versions, question_marks, seed, max_marks, ip, user_agent)
    VALUES (p_exam, CASE WHEN v_jupeb THEN NULL ELSE p_student END, CASE WHEN v_jupeb THEN p_student END, v_n + 1,
            least(now() + make_interval(mins => e.duration_minutes), e.ends_at, coalesce(v_sit.ends_at, 'infinity'::timestamptz)) + make_interval(mins => v_extra),
            v_paper, v_versions, v_marks, v_seed,
            greatest((SELECT sum(m) FROM unnest(v_marks) m), 1), p_ip, p_agent)
    RETURNING * INTO a;
    PERFORM assessment.cbt_log(a.id, 'STARTED', false, format('%s questions, %s marks, ends %s%s%s', cardinality(v_paper), a.max_marks, to_char(a.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI:SS'),
                               CASE WHEN v_sit.id IS NULL THEN '' ELSE format(' · %s, %s', v_sit.label, v_sit.venue) END,
                               CASE WHEN v_extra > 0 THEN format(' · %s minutes extra time', v_extra) ELSE '' END
                               || CASE WHEN v_mark.status = 'LATE' THEN format(' · admitted %s minutes late', v_mark.minutes_late) ELSE '' END), p_ip);
    RETURN a;
END $$;

-- ── 5 · the attempt's heartbeat kept off the audit trail ──────────────────────────────────────────────────────────
-- Every answer saved and every half-minute heartbeat moves an attempt's last_activity_at, answered and updated_at, and the audit trigger
-- wrote the whole attempt — its paper's question lists included — before and after, for each one: in the load test of a 500-candidate
-- hall, about a hundred audit entries a second, gigabytes over a day of sittings, all saying only when a screen was last heard from.
-- The answers themselves are kept with their sequence (assessment.cbt_answer) and the room's events in assessment.cbt_event, as
-- before. Every other change of an attempt — its start, its end, its score, its clock, its token, its violations, a void — is
-- audited exactly as before; an update that moves nothing but those three columns is not.
DROP TRIGGER trg_audit_assessment_cbt_attempt ON assessment.cbt_attempt;
CREATE TRIGGER trg_audit_assessment_cbt_attempt AFTER INSERT OR DELETE ON assessment.cbt_attempt FOR EACH ROW EXECUTE FUNCTION audit.record();
CREATE TRIGGER trg_audit_assessment_cbt_attempt_change AFTER UPDATE ON assessment.cbt_attempt FOR EACH ROW
    WHEN ((to_jsonb(OLD) - ARRAY['last_activity_at', 'answered', 'updated_at']) IS DISTINCT FROM (to_jsonb(NEW) - ARRAY['last_activity_at', 'answered', 'updated_at']))
    EXECUTE FUNCTION audit.record();
COMMENT ON TRIGGER trg_audit_assessment_cbt_attempt_change ON assessment.cbt_attempt IS
  'V374: every change of an attempt is audited except one that moves only last_activity_at, answered and updated_at — the heartbeat of a screen, written by every save and ping; the answers are kept in assessment.cbt_answer.';

-- ── 6 · the live monitor's counters, lighter ───────────────────────────────────────────────────────────────────────
-- The office's live monitor reads its counters every two seconds; each read judged every candidate's eligibility again (their fees,
-- their registration) and read every attempt whole. The counters now read only the attempt columns they count, and
-- cbt_monitor_live_counts — the two-second read — leaves eligibility out (NULL); the screen reads it on opening and once a minute.
CREATE OR REPLACE FUNCTION assessment.cbt_monitor_counts(p_exam uuid)
RETURNS TABLE(candidates bigint, eligible bigint, not_started bigint, in_progress bigint, submitted bigint, time_expired bigint, terminated bigint, disconnected bigint,
              warned bigint, critical bigint, scored bigint, live_state text, now timestamp with time zone)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    reg AS (SELECT (SELECT count(DISTINCT cr.student_id) FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                     WHERE e.office <> 'JUPEB' AND en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
                 + (SELECT count(DISTINCT r.application_id) FROM e, jupeb.subject_registration r WHERE e.office = 'JUPEB' AND r.subject_id = e.jupeb_subject_id AND r.session = e.session) AS n),
    el AS (SELECT count(*) FILTER (WHERE c.eligible) AS n FROM assessment.cbt_candidates(p_exam) c),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.status, a.last_activity_at, a.violations, a.score
              FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
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

CREATE OR REPLACE FUNCTION assessment.cbt_monitor_live_counts(p_exam uuid)
RETURNS TABLE(candidates bigint, eligible bigint, not_started bigint, in_progress bigint, submitted bigint, time_expired bigint, terminated bigint, disconnected bigint,
              warned bigint, critical bigint, scored bigint, live_state text, now timestamp with time zone)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    reg AS (SELECT (SELECT count(DISTINCT cr.student_id) FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
                     WHERE e.office <> 'JUPEB' AND en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
                 + (SELECT count(DISTINCT r.application_id) FROM e, jupeb.subject_registration r WHERE e.office = 'JUPEB' AND r.subject_id = e.jupeb_subject_id AND r.session = e.session) AS n),
    el AS (SELECT NULL::bigint AS n),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.status, a.last_activity_at, a.violations, a.score
              FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
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

COMMIT;
