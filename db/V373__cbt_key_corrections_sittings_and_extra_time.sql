-- V373: a wrong key corrected and the examination re-marked, with a record; an examination sat in sittings, each candidate seated;
--       extra time for a named candidate.
--
-- 1  Key corrections. The question analysis (V372) names a key the strongest candidates answered against; nothing could correct
--    it. catalogue of corrections: assessment.cbt_key_correction keeps, for an examination's question at the version its
--    candidates sat, the key before and after, the reason, who and when. Every reading of an attempt's key (assessment.cbt_key,
--    read by cbt_attempt_questions and so by the scoring and the analysis) takes the latest correction; the question's frozen
--    version is never rewritten. assessment.cbt_key_correction_preview shows what the correction would do to every candidate's
--    score; assessment.cbt_correct_key applies it — each changed score a new result version naming the correction (the score
--    moves by the difference the key makes, so an amendment made by hand stays), and, if the office asks and the bank still holds
--    that version and no running examination draws it, the bank's question corrected too (a new version). A key is corrected once
--    the examination has ended; once its results are published, only by the Registrar or the Super Administrator.
-- 2  Sittings. assessment.cbt_sitting is one sitting of an examination (label, venue, start, end, seats); assessment.cbt_seat seats
--    a candidate in one sitting with a seat number. The office seats every candidate at once (by programme, name or number) or
--    moves one; when an examination has sittings, cbt_start opens it to a candidate only in their own sitting, and their attempt
--    ends with the sitting at the latest.
-- 3  Extra time. assessment.cbt_extra_time gives a named candidate minutes beyond the paper's time, with the reason, on the record;
--    applied when they start, and to an attempt already running (its clock follows within the half-minute heartbeat). Granting 0
--    withdraws it.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V373: CBT key corrections, sittings and extra time', true);

-- ── 1 · the tables ─────────────────────────────────────────────────────────────────────────────────────────────

CREATE TABLE assessment.cbt_key_correction (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id          uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    question_id      uuid NOT NULL REFERENCES assessment.question(id) ON DELETE CASCADE,
    version          int  NOT NULL CHECK (version >= 1),
    old_key          int[] NOT NULL,
    new_key          int[] NOT NULL CHECK (cardinality(new_key) >= 1),
    reason           text NOT NULL CHECK (btrim(reason) <> ''),
    corrected_by     uuid NOT NULL,
    corrected_office text NULL,
    corrected_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    attempts_seen    int NOT NULL DEFAULT 0,
    scores_changed   int NOT NULL DEFAULT 0,
    bank_fixed       boolean NOT NULL DEFAULT false
);
COMMENT ON TABLE assessment.cbt_key_correction IS
  'V373: a key corrected for an examination''s question at the version its candidates sat — before and after, the reason, who and when, how many attempts it touched and how many scores it changed. The latest correction is the key every reading of the attempts takes.';
CREATE INDEX ix_cbt_key_correction ON assessment.cbt_key_correction (exam_id, question_id, version, corrected_at DESC);
SELECT audit.attach('assessment.cbt_key_correction');

CREATE TABLE assessment.cbt_sitting (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id    uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    label      text NOT NULL CHECK (btrim(label) <> ''),
    venue      text NOT NULL CHECK (btrim(venue) <> ''),
    starts_at  timestamptz NOT NULL,
    ends_at    timestamptz NOT NULL,
    capacity   int NOT NULL CHECK (capacity BETWEEN 1 AND 5000),
    created_by uuid NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_cbt_sitting_time CHECK (ends_at > starts_at),
    CONSTRAINT uq_cbt_sitting_label UNIQUE (exam_id, label)
);
COMMENT ON TABLE assessment.cbt_sitting IS 'V373: one sitting of a CBT examination — its label, venue, time and seats. With sittings, a candidate starts only in their own.';
CREATE INDEX ix_cbt_sitting_exam ON assessment.cbt_sitting (exam_id, starts_at);
SELECT audit.attach('assessment.cbt_sitting');

CREATE TABLE assessment.cbt_seat (
    exam_id      uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    sitting_id   uuid NOT NULL REFERENCES assessment.cbt_sitting(id) ON DELETE CASCADE,
    candidate_id uuid NOT NULL,
    seat_no      int NOT NULL CHECK (seat_no >= 1),
    assigned_by  uuid NULL,
    assigned_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (exam_id, candidate_id),
    CONSTRAINT uq_cbt_seat_number UNIQUE (sitting_id, seat_no)
);
COMMENT ON TABLE assessment.cbt_seat IS 'V373: a candidate seated in one sitting of an examination, with a seat number — the candidate a student (people.student) or a JUPEB application.';
CREATE INDEX ix_cbt_seat_sitting ON assessment.cbt_seat (sitting_id, seat_no);
SELECT audit.attach('assessment.cbt_seat');

CREATE TABLE assessment.cbt_extra_time (
    exam_id        uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    candidate_id   uuid NOT NULL,
    minutes        int NOT NULL CHECK (minutes BETWEEN 1 AND 600),
    reason         text NOT NULL CHECK (btrim(reason) <> ''),
    granted_by     uuid NOT NULL,
    granted_office text NULL,
    granted_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (exam_id, candidate_id)
);
COMMENT ON TABLE assessment.cbt_extra_time IS 'V373: minutes a named candidate has beyond the paper''s time, with the reason — a disability, a sitting delayed by power; every change on the audit record.';
SELECT audit.attach('assessment.cbt_extra_time');

GRANT SELECT ON assessment.cbt_key_correction, assessment.cbt_sitting, assessment.cbt_seat, assessment.cbt_extra_time TO app_auditor;

ALTER TABLE assessment.cbt_event DROP CONSTRAINT cbt_event_kind_check;
ALTER TABLE assessment.cbt_event ADD CONSTRAINT cbt_event_kind_check CHECK (kind IN (
    'STARTED', 'RESUMED', 'TAB_SWITCH', 'WINDOW_BLUR', 'FULLSCREEN_EXIT', 'NETWORK_DISCONNECT', 'RECONNECTED', 'MULTIPLE_LOGIN', 'SESSION_REPLACED',
    'COPY_PASTE', 'CONTEXT_MENU', 'WARNING', 'FINAL_WARNING', 'AUTO_SUBMITTED', 'TERMINATED', 'SUBMITTED', 'TIME_EXPIRED', 'AMENDED',
    'WINDOW_FOCUS', 'FULLSCREEN_ENTER', 'COPY_ATTEMPT', 'PASTE_ATTEMPT', 'CUT_ATTEMPT', 'RIGHT_CLICK', 'UNUSUAL_NAVIGATION', 'TIME_MANIPULATION_ATTEMPT',
    'EXAM_PAGE_EXIT', 'DISCONNECT_TIMEOUT', 'CAMERA_CONSENTED', 'CAMERA_DECLINED', 'CAMERA_STOPPED', 'FACE_NOT_DETECTED', 'MULTIPLE_FACES', 'FACE_OUT_OF_FRAME',
    'HEAD_POSE_LEFT', 'HEAD_POSE_RIGHT', 'HEAD_POSE_UP', 'HEAD_POSE_DOWN', 'PROLONGED_LOOK_AWAY',
    -- V373
    'EXTRA_TIME'));

-- ── 2 · the key every reading takes, and the scoring with a key in question ─────────────────────────────────────

/* the key of an examination's question at a version: the latest correction for that examination, else the version's own */
CREATE OR REPLACE FUNCTION assessment.cbt_key(p_exam uuid, p_question uuid, p_version int)
RETURNS int[] LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT kc.new_key FROM assessment.cbt_key_correction kc
          WHERE kc.exam_id = p_exam AND kc.question_id = p_question AND kc.version = p_version ORDER BY kc.corrected_at DESC LIMIT 1),
        (SELECT qv.answers FROM assessment.question_version qv WHERE qv.question_id = p_question AND qv.version = p_version))
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_attempt_questions(p_attempt uuid)
RETURNS TABLE (n int, question_id uuid, version int, marks int, kind text, stem text, options jsonb, answers int[])
LANGUAGE sql STABLE AS $$
    SELECT u.n::int, u.qid, u.v, u.m, qv.kind, qv.stem, qv.options, assessment.cbt_key(a.exam_id, u.qid, u.v)
      FROM assessment.cbt_attempt a
      CROSS JOIN LATERAL unnest(a.question_ids, a.question_versions, a.question_marks) WITH ORDINALITY u(qid, v, m, n)
      JOIN assessment.question_version qv ON qv.question_id = u.qid AND qv.version = u.v
     WHERE a.id = p_attempt
$$;
COMMENT ON FUNCTION assessment.cbt_attempt_questions(uuid) IS 'V364/V373: an attempt''s questions at the versions and marks it drew, each with its key as corrected for the examination (engine only — never sent to a candidate).';

CREATE OR REPLACE FUNCTION assessment.cbt_item_analysis(p_exam uuid)
RETURNS TABLE (question_id uuid, n int, stem text, kind text, options jsonb, key int[], seen int, answered int, correct int,
               facility numeric, discrimination numeric, upper_n int, lower_n int, choices jsonb, upper_choices jsonb, flags text[])
LANGUAGE sql STABLE AS $$
WITH att AS (
    SELECT a.id, a.score, a.question_ids, a.question_versions, row_number() OVER (ORDER BY a.score DESC, a.id) AS r, count(*) OVER () AS total
      FROM assessment.cbt_attempt a
     WHERE a.exam_id = p_exam AND a.status IN ('SUBMITTED', 'TIME_EXPIRED', 'TERMINATED') AND a.outcome = 'SCORED' AND a.score IS NOT NULL
), g AS (
    -- the top and bottom 27% by score, when there are ten scored candidates or more
    SELECT att.*, greatest(1, round(att.total * 0.27))::int AS k FROM att
), items AS (
    SELECT g.id AS attempt_id,
           CASE WHEN g.total >= 10 AND g.r <= g.k THEN 'U' WHEN g.total >= 10 AND g.r > g.total - g.k THEN 'L' END AS band,
           u.qid, u.v, u.pos::int AS pos
      FROM g CROSS JOIN LATERAL unnest(g.question_ids, g.question_versions) WITH ORDINALITY u(qid, v, pos)
), resp AS (
    SELECT i.*, assessment.cbt_key(p_exam, i.qid, i.v) AS qkey, coalesce(an.chosen, ARRAY[]::int[]) AS chosen
      FROM items i
      JOIN assessment.question_version qv ON qv.question_id = i.qid AND qv.version = i.v
      LEFT JOIN assessment.cbt_answer an ON an.attempt_id = i.attempt_id AND an.question_id = i.qid
), per AS (
    SELECT r.qid,
           count(*)::int AS seen,
           count(*) FILTER (WHERE cardinality(r.chosen) > 0)::int AS answered,
           count(*) FILTER (WHERE r.chosen = r.qkey)::int AS correct,
           count(*) FILTER (WHERE r.band = 'U')::int AS upper_n,
           count(*) FILTER (WHERE r.band = 'L')::int AS lower_n,
           count(*) FILTER (WHERE r.band = 'U' AND r.chosen = r.qkey)::int AS upper_correct,
           count(*) FILTER (WHERE r.band = 'L' AND r.chosen = r.qkey)::int AS lower_correct,
           mode() WITHIN GROUP (ORDER BY r.v) AS v,
           min(r.pos) AS pos
      FROM resp r GROUP BY r.qid
), ch AS (
    SELECT r.qid, c.opt, count(*)::int AS cnt, count(*) FILTER (WHERE r.band = 'U')::int AS ucnt
      FROM resp r CROSS JOIN LATERAL unnest(r.chosen) AS c(opt) GROUP BY r.qid, c.opt
), out AS (
    SELECT per.*, qv.stem, qv.kind, qv.options AS raw_options, assessment.cbt_key(p_exam, per.qid, per.v) AS qkey,
           round(per.correct::numeric / nullif(per.seen, 0), 2) AS facility,
           CASE WHEN per.upper_n >= 3 AND per.lower_n >= 3
                THEN round(per.upper_correct::numeric / per.upper_n - per.lower_correct::numeric / per.lower_n, 2) END AS discrimination,
           (SELECT max(ch.ucnt) FROM ch WHERE ch.qid = per.qid AND NOT (ch.opt = ANY (assessment.cbt_key(p_exam, per.qid, per.v)))) AS top_wrong_upper,
           coalesce((SELECT eq.ordinal FROM assessment.cbt_exam_question eq WHERE eq.exam_id = p_exam AND eq.question_id = per.qid), 100000 + per.pos) AS ord
      FROM per JOIN assessment.question_version qv ON qv.question_id = per.qid AND qv.version = per.v
)
SELECT o.qid, (row_number() OVER (ORDER BY o.ord, o.qid))::int, o.stem, o.kind,
       (SELECT coalesce(jsonb_agg(jsonb_build_object('i', x.i - 1, 'text', x.t) ORDER BY x.i), '[]'::jsonb)
          FROM jsonb_array_elements_text(o.raw_options) WITH ORDINALITY x(t, i)),
       o.qkey, o.seen, o.answered, o.correct, o.facility, o.discrimination, o.upper_n, o.lower_n,
       (SELECT coalesce(jsonb_object_agg(ch.opt::text, ch.cnt), '{}'::jsonb) FROM ch WHERE ch.qid = o.qid),
       (SELECT coalesce(jsonb_object_agg(ch.opt::text, ch.ucnt), '{}'::jsonb) FROM ch WHERE ch.qid = o.qid AND ch.ucnt > 0),
       array_remove(ARRAY[
           CASE WHEN o.kind <> 'MULTI' AND o.upper_n >= 5 AND coalesce(o.top_wrong_upper, 0) > o.upper_correct THEN 'POSSIBLE_WRONG_KEY' END,
           CASE WHEN o.discrimination < 0 THEN 'NEGATIVE_DISCRIMINATION' WHEN o.discrimination < 0.20 THEN 'WEAK_DISCRIMINATION' END,
           CASE WHEN o.seen >= 10 AND o.facility < 0.20 THEN 'VERY_HARD' WHEN o.seen >= 10 AND o.facility > 0.90 THEN 'VERY_EASY' END,
           CASE WHEN o.seen >= 10 AND o.answered = 0 THEN 'NOBODY_ANSWERED' END
       ], NULL)
  FROM out o
 ORDER BY 2
$$;

/* an attempt's score by the scoring's own rule (cbt_finalize), with one question's key put in question (p_key) when asked */
CREATE OR REPLACE FUNCTION assessment.cbt_computed_score(p_attempt uuid, p_question uuid DEFAULT NULL, p_key int[] DEFAULT NULL)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT greatest(0, coalesce(sum(m.got), 0)
                       - count(*) FILTER (WHERE m.got = 0 AND cardinality(coalesce(an.chosen, ARRAY[]::int[])) > 0) * max(e.negative_marks))
      FROM assessment.cbt_attempt a
      JOIN assessment.cbt_exam e ON e.id = a.exam_id
      CROSS JOIN LATERAL assessment.cbt_attempt_questions(a.id) x
      LEFT JOIN assessment.cbt_answer an ON an.attempt_id = a.id AND an.question_id = x.question_id
      CROSS JOIN LATERAL (SELECT assessment.cbt_marks_for(x.kind, CASE WHEN x.question_id = p_question THEN p_key ELSE x.answers END,
                                                          an.chosen, x.marks, e.partial_credit) AS got) m
     WHERE a.id = p_attempt
$$;

-- ── 3 · a key corrected: what it would do, then done ──────────────────────────────────────────────────────────────

/* the version of a question an examination's candidates sat — refused when none sat it, or they sat more than one */
CREATE OR REPLACE FUNCTION assessment.cbt_sat_version(p_exam uuid, p_question uuid)
RETURNS int LANGUAGE plpgsql STABLE AS $$
DECLARE v_n int; v_version int;
BEGIN
    SELECT count(DISTINCT u.v), min(u.v) INTO v_n, v_version
      FROM assessment.cbt_attempt a CROSS JOIN LATERAL unnest(a.question_ids, a.question_versions) u(qid, v)
     WHERE a.exam_id = p_exam AND u.qid = p_question;
    IF coalesce(v_n, 0) = 0 THEN RAISE EXCEPTION 'CBT_KEY_NOT_ON_PAPER: no candidate sat this question in this examination' USING ERRCODE = '23514'; END IF;
    IF v_n > 1 THEN
        RAISE EXCEPTION 'CBT_KEY_VERSIONS: candidates sat more than one version of this question; amend the affected results one by one' USING ERRCODE = '23514';
    END IF;
    RETURN v_version;
END $$;

/* a proposed key made whole and checked against the question as sat: in range; one option for a single-answer question */
CREATE OR REPLACE FUNCTION assessment.cbt_checked_key(p_exam uuid, p_question uuid, p_key int[])
RETURNS int[] LANGUAGE plpgsql STABLE AS $$
DECLARE v_version int := assessment.cbt_sat_version(p_exam, p_question); v_kind text; v_opts int; v_key int[];
BEGIN
    SELECT qv.kind, jsonb_array_length(qv.options) INTO v_kind, v_opts FROM assessment.question_version qv WHERE qv.question_id = p_question AND qv.version = v_version;
    SELECT array_agg(DISTINCT k ORDER BY k) INTO v_key FROM unnest(p_key) k WHERE k IS NOT NULL;
    IF v_key IS NULL OR EXISTS (SELECT 1 FROM unnest(v_key) k WHERE k < 0 OR k >= v_opts) THEN
        RAISE EXCEPTION 'CBT_KEY_RANGE: the correct option must be one of the question''s % options', v_opts USING ERRCODE = '23514';
    END IF;
    IF v_kind <> 'MULTI' AND cardinality(v_key) <> 1 THEN
        RAISE EXCEPTION 'CBT_KEY_ONE: a single-answer question has exactly one correct option' USING ERRCODE = '23514';
    END IF;
    RETURN v_key;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_key_correction_preview(p_exam uuid, p_question uuid, p_key int[])
RETURNS TABLE (attempt_id uuid, candidate_id uuid, number text, name text, outcome text, max_marks int, old_score numeric, new_score numeric,
               old_percentage numeric, new_percentage numeric, old_grade text, new_grade text, old_passed boolean, new_passed boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_key int[];
BEGIN
    -- the key and the scores are shown only once nobody is still writing, as the question analysis is
    IF (SELECT assessment.cbt_live_state(x) FROM assessment.cbt_exam x WHERE x.id = p_exam) NOT IN ('ENDED', 'CLOSED', 'COMPLETED', 'CANCELLED') THEN
        RAISE EXCEPTION 'CBT_KEY_LIVE: a key is corrected once the examination has ended' USING ERRCODE = '23514';
    END IF;
    v_key := assessment.cbt_checked_key(p_exam, p_question, p_key);
    RETURN QUERY
    WITH e AS (SELECT * FROM assessment.cbt_exam WHERE id = p_exam),
    k AS (SELECT a.id, a.candidate_id, a.outcome, a.max_marks, a.score, a.percentage, a.grade, a.passed,
                 assessment.cbt_computed_score(a.id) AS c_old, assessment.cbt_computed_score(a.id, p_question, v_key) AS c_new
            FROM assessment.cbt_attempt a
           WHERE a.exam_id = p_exam AND a.status <> 'IN_PROGRESS' AND p_question = ANY (a.question_ids)),
    s AS (SELECT k.*, CASE WHEN k.outcome = 'SCORED' THEN least(k.max_marks, greatest(0, k.score + k.c_new - k.c_old)) ELSE k.score END AS ns FROM k),
    p AS (SELECT s.*, round(s.ns * 100.0 / greatest(s.max_marks, 1), 2) AS npct FROM s)
    SELECT p.id, p.candidate_id, coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no),
           coalesce(upper(st.surname) || ', ' || st.other_names, upper(ja.surname) || ', ' || ja.first_name),
           p.outcome, p.max_marks, p.score, p.ns, p.percentage, p.npct, p.grade,
           (SELECT g.grade FROM policy.grade_of(least(100, greatest(0, round(p.npct)))::int) g LIMIT 1),
           p.passed, (p.outcome = 'SCORED' AND p.npct >= e.pass_mark)
      FROM p CROSS JOIN e
      LEFT JOIN people.student st ON st.id = p.candidate_id
      LEFT JOIN jupeb.application ja ON ja.id = p.candidate_id
     ORDER BY (p.ns IS DISTINCT FROM p.score) DESC, 4;
END $$;
COMMENT ON FUNCTION assessment.cbt_key_correction_preview(uuid, uuid, int[]) IS
  'V373: every finished attempt that sat the question — its score now and with the proposed key (the difference the key makes added to the score as it stands). Nothing is written.';

CREATE OR REPLACE FUNCTION assessment.cbt_correct_key(p_exam uuid, p_question uuid, p_key int[], p_reason text, p_fix_bank boolean)
RETURNS assessment.cbt_key_correction
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := lower(coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''));
        e assessment.cbt_exam; v_version int; v_key int[]; v_old int[]; kc assessment.cbt_key_correction; r record;
        v_new numeric; v_pct numeric; v_grade text; v_seen int := 0; v_changed int := 0; v_fixed boolean := false; v_why text := btrim(coalesce(p_reason, ''));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a key is corrected by a person' USING ERRCODE = '23514'; END IF;
    IF v_why = '' THEN RAISE EXCEPTION 'CBT_REASON_REQUIRED: a key correction names its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF assessment.cbt_live_state(e) NOT IN ('ENDED', 'CLOSED', 'COMPLETED', 'CANCELLED') THEN
        RAISE EXCEPTION 'CBT_KEY_LIVE: a key is corrected once the examination has ended' USING ERRCODE = '23514';
    END IF;
    IF e.results_state = 'PUBLISHED' AND actor NOT IN ('registrar', 'super') THEN
        RAISE EXCEPTION 'CBT_KEY_PUBLISHED: the results are published; the Registrar or the Super Administrator corrects a key now' USING ERRCODE = '23514';
    END IF;
    v_version := assessment.cbt_sat_version(p_exam, p_question);
    v_key := assessment.cbt_checked_key(p_exam, p_question, p_key);
    v_old := assessment.cbt_key(p_exam, p_question, v_version);
    IF v_old = v_key THEN RAISE EXCEPTION 'CBT_KEY_SAME: that is already the key' USING ERRCODE = '23514'; END IF;
    INSERT INTO assessment.cbt_key_correction (exam_id, question_id, version, old_key, new_key, reason, corrected_by, corrected_office)
    VALUES (p_exam, p_question, v_version, v_old, v_key, v_why, who, actor)
    RETURNING * INTO kc;
    -- every finished attempt that sat it: the difference the key makes, added to the score as it stands, as a new result version
    FOR r IN SELECT a.* FROM assessment.cbt_attempt a
              WHERE a.exam_id = p_exam AND a.status <> 'IN_PROGRESS' AND p_question = ANY (a.question_ids)
              ORDER BY a.id FOR UPDATE LOOP
        v_seen := v_seen + 1;
        CONTINUE WHEN r.outcome <> 'SCORED' OR r.score IS NULL;
        v_new := least(r.max_marks, greatest(0, r.score + assessment.cbt_computed_score(r.id, p_question, v_key) - assessment.cbt_computed_score(r.id, p_question, v_old)));
        CONTINUE WHEN v_new = r.score;
        v_pct := round(v_new * 100.0 / greatest(r.max_marks, 1), 2);
        SELECT g.grade INTO v_grade FROM policy.grade_of(least(100, greatest(0, round(v_pct)))::int) g LIMIT 1;
        INSERT INTO assessment.cbt_result (attempt_id, version, score, max_marks, percentage, grade, passed, outcome, reason, changed_by, changed_office)
        VALUES (r.id, (SELECT coalesce(max(x.version), 0) + 1 FROM assessment.cbt_result x WHERE x.attempt_id = r.id), v_new, r.max_marks, v_pct, v_grade,
                v_pct >= e.pass_mark, 'SCORED', 'Key corrected: ' || v_why, who, actor);
        UPDATE assessment.cbt_attempt SET score = v_new, percentage = v_pct, grade = v_grade, passed = (v_pct >= e.pass_mark) WHERE id = r.id;
        PERFORM assessment.cbt_log(r.id, 'AMENDED', false, format('key corrected: %s → %s marks — %s', r.score, v_new, v_why), NULL);
        v_changed := v_changed + 1;
    END LOOP;
    -- the bank's question too, when asked, when it still stands at the version sat, and when no running examination draws it
    IF coalesce(p_fix_bank, false) AND (SELECT q.version FROM assessment.question q WHERE q.id = p_question) = v_version
       AND assessment.question_in_live_exam(p_question) IS NULL THEN
        UPDATE assessment.question SET answer = v_key[1], answers = v_key WHERE id = p_question;
        v_fixed := true;
    END IF;
    UPDATE assessment.cbt_key_correction SET attempts_seen = v_seen, scores_changed = v_changed, bank_fixed = v_fixed WHERE id = kc.id RETURNING * INTO kc;
    RETURN kc;
END $$;
COMMENT ON FUNCTION assessment.cbt_correct_key(uuid, uuid, int[], text, boolean) IS
  'V373: a key corrected for an ended examination — recorded, every changed score a new result version naming the correction, the bank''s question corrected too when asked and when safe. Published results: the Registrar or the Super Administrator.';

-- ── 4 · sittings and seats ─────────────────────────────────────────────────────────────────────────────────────

/* a sitting as given, checked: a label and a venue, inside the examination's window, at least the paper's length */
CREATE OR REPLACE FUNCTION assessment.cbt_sitting_checked(e assessment.cbt_exam, p_label text, p_venue text, p_starts timestamptz, p_ends timestamptz, p_capacity int)
RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF e.state IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: the sittings of a % examination are not changed', lower(e.state) USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_label, '')), '') IS NULL OR nullif(btrim(coalesce(p_venue, '')), '') IS NULL THEN
        RAISE EXCEPTION 'CBT_SITTING_NAMED: a sitting has a name and a venue' USING ERRCODE = '23514';
    END IF;
    IF p_starts IS NULL OR p_ends IS NULL OR p_ends <= p_starts THEN RAISE EXCEPTION 'CBT_SITTING_TIME: a sitting ends after it starts' USING ERRCODE = '23514'; END IF;
    IF p_capacity IS NULL OR p_capacity < 1 OR p_capacity > 5000 THEN RAISE EXCEPTION 'CBT_SITTING_SEATS: a sitting has 1 to 5000 seats' USING ERRCODE = '23514'; END IF;
    IF p_ends - p_starts < make_interval(mins => e.duration_minutes) THEN
        RAISE EXCEPTION 'CBT_SITTING_SHORT: a sitting is at least the paper''s % minutes long', e.duration_minutes USING ERRCODE = '23514';
    END IF;
    IF (e.starts_at IS NOT NULL AND p_starts < e.starts_at) OR (e.ends_at IS NOT NULL AND p_ends > e.ends_at) THEN
        RAISE EXCEPTION 'CBT_SITTING_WINDOW: a sitting falls inside the examination''s window (% to %)',
            to_char(e.starts_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI'), to_char(e.ends_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI') USING ERRCODE = '23514';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_add_sitting(p_exam uuid, p_label text, p_venue text, p_starts timestamptz, p_ends timestamptz, p_capacity int)
RETURNS assessment.cbt_sitting LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.cbt_exam; s assessment.cbt_sitting;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a sitting is set by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    PERFORM assessment.cbt_sitting_checked(e, p_label, p_venue, p_starts, p_ends, p_capacity);
    IF EXISTS (SELECT 1 FROM assessment.cbt_sitting x WHERE x.exam_id = p_exam AND lower(x.label) = lower(btrim(p_label))) THEN
        RAISE EXCEPTION 'CBT_SITTING_NAME_TAKEN: the examination already has a sitting named %', btrim(p_label) USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.cbt_sitting (exam_id, label, venue, starts_at, ends_at, capacity, created_by)
    VALUES (p_exam, btrim(p_label), btrim(p_venue), p_starts, p_ends, p_capacity, who) RETURNING * INTO s;
    RETURN s;
END $$;

CREATE OR REPLACE FUNCTION assessment.cbt_update_sitting(p_sitting uuid, p_label text, p_venue text, p_starts timestamptz, p_ends timestamptz, p_capacity int)
RETURNS assessment.cbt_sitting LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.cbt_exam; s assessment.cbt_sitting; v_seated int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a sitting is set by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = s.exam_id;
    PERFORM assessment.cbt_sitting_checked(e, p_label, p_venue, p_starts, p_ends, p_capacity);
    SELECT count(*) INTO v_seated FROM assessment.cbt_seat WHERE sitting_id = s.id;
    IF p_capacity < v_seated THEN
        RAISE EXCEPTION 'CBT_SITTING_FULL: % candidates are seated in it; move some before cutting its seats to %', v_seated, p_capacity USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.cbt_sitting SET label = btrim(p_label), venue = btrim(p_venue), starts_at = p_starts, ends_at = p_ends, capacity = p_capacity
     WHERE id = s.id RETURNING * INTO s;
    RETURN s;
END $$;

/* a sitting nobody has sat in is taken away (its seats with it); one in which a candidate has begun is kept */
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
    SELECT count(*) INTO v_seated FROM assessment.cbt_seat WHERE sitting_id = s.id;
    DELETE FROM assessment.cbt_sitting WHERE id = s.id;
    RETURN v_seated;
END $$;

/* every candidate not yet seated, in the order asked (PROGRAMME, NAME or NUMBER), into the sittings by time, seat after seat */
CREATE OR REPLACE FUNCTION assessment.cbt_seat_all(p_exam uuid, p_order text)
RETURNS TABLE (seated int, unseated int) LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.cbt_exam; c record; v_sid uuid; n int := 0; v_left int := 0;
        v_order text := upper(coalesce(nullif(btrim(p_order), ''), 'PROGRAMME'));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'candidates are seated by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.cbt_sitting WHERE exam_id = p_exam) THEN
        RAISE EXCEPTION 'CBT_NO_SITTINGS: add the examination''s sittings first' USING ERRCODE = '23514';
    END IF;
    IF v_order NOT IN ('PROGRAMME', 'NAME', 'NUMBER') THEN RAISE EXCEPTION 'CBT_SEAT_ORDER: candidates are seated by programme, name or number' USING ERRCODE = '23514'; END IF;
    FOR c IN SELECT k.student_id FROM assessment.cbt_candidates(p_exam) k
              WHERE NOT EXISTS (SELECT 1 FROM assessment.cbt_seat x WHERE x.exam_id = p_exam AND x.candidate_id = k.student_id)
              ORDER BY CASE WHEN v_order = 'PROGRAMME' THEN k.programme END, CASE WHEN v_order = 'NAME' THEN k.surname END,
                       CASE WHEN v_order = 'NAME' THEN k.other_names END, k.number LOOP
        SELECT s.id INTO v_sid FROM assessment.cbt_sitting s
         WHERE s.exam_id = p_exam AND (SELECT count(*) FROM assessment.cbt_seat x WHERE x.sitting_id = s.id) < s.capacity
         ORDER BY s.starts_at, s.label LIMIT 1;
        IF v_sid IS NULL THEN v_left := v_left + 1; CONTINUE; END IF;
        INSERT INTO assessment.cbt_seat (exam_id, sitting_id, candidate_id, seat_no, assigned_by)
        VALUES (p_exam, v_sid, c.student_id, (SELECT coalesce(max(x.seat_no), 0) + 1 FROM assessment.cbt_seat x WHERE x.sitting_id = v_sid), who);
        n := n + 1;
    END LOOP;
    RETURN QUERY SELECT n, v_left;
END $$;

/* one candidate seated, or moved to another sitting, while they have not begun */
CREATE OR REPLACE FUNCTION assessment.cbt_seat_candidate(p_exam uuid, p_candidate uuid, p_sitting uuid)
RETURNS assessment.cbt_seat LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s assessment.cbt_sitting; x assessment.cbt_seat;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'candidates are seated by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting AND exam_id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting of this examination' USING ERRCODE = '23503'; END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.cbt_candidates(p_exam) k WHERE k.student_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_NOT_A_CANDIDATE: the student is not a candidate of this examination' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam AND a.candidate_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_SEAT_SAT: the candidate has begun the examination; their seat is kept' USING ERRCODE = '23514';
    END IF;
    IF (SELECT count(*) FROM assessment.cbt_seat y WHERE y.sitting_id = s.id AND y.candidate_id <> p_candidate) >= s.capacity THEN
        RAISE EXCEPTION 'CBT_SITTING_FULL: % has no free seat', s.label USING ERRCODE = '23514';
    END IF;
    DELETE FROM assessment.cbt_seat WHERE exam_id = p_exam AND candidate_id = p_candidate;
    INSERT INTO assessment.cbt_seat (exam_id, sitting_id, candidate_id, seat_no, assigned_by)
    VALUES (p_exam, s.id, p_candidate, (SELECT coalesce(max(y.seat_no), 0) + 1 FROM assessment.cbt_seat y WHERE y.sitting_id = s.id), who)
    RETURNING * INTO x;
    RETURN x;
END $$;

-- ── 5 · extra time for a named candidate ───────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_grant_extra_time(p_exam uuid, p_candidate uuid, p_minutes int, p_reason text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        v_old int; v_delta int; v_why text := btrim(coalesce(p_reason, '')); a record;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'extra time is given by a person' USING ERRCODE = '23514'; END IF;
    IF v_why = '' THEN RAISE EXCEPTION 'CBT_REASON_REQUIRED: extra time names its reason' USING ERRCODE = '23514'; END IF;
    IF p_minutes IS NULL OR p_minutes < 0 OR p_minutes > 600 THEN RAISE EXCEPTION 'CBT_EXTRA_RANGE: extra time is 0 to 600 minutes (0 withdraws it)' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM assessment.cbt_candidates(p_exam) k WHERE k.student_id = p_candidate)
       AND NOT EXISTS (SELECT 1 FROM assessment.cbt_attempt x WHERE x.exam_id = p_exam AND x.candidate_id = p_candidate) THEN
        RAISE EXCEPTION 'CBT_NOT_A_CANDIDATE: the student is not a candidate of this examination' USING ERRCODE = '23514';
    END IF;
    SELECT minutes INTO v_old FROM assessment.cbt_extra_time WHERE exam_id = p_exam AND candidate_id = p_candidate FOR UPDATE;
    v_old := coalesce(v_old, 0);
    IF p_minutes = 0 THEN
        DELETE FROM assessment.cbt_extra_time WHERE exam_id = p_exam AND candidate_id = p_candidate;
    ELSE
        INSERT INTO assessment.cbt_extra_time (exam_id, candidate_id, minutes, reason, granted_by, granted_office)
        VALUES (p_exam, p_candidate, p_minutes, v_why, who, actor)
        ON CONFLICT (exam_id, candidate_id) DO UPDATE SET minutes = EXCLUDED.minutes, reason = EXCLUDED.reason, granted_by = EXCLUDED.granted_by,
            granted_office = EXCLUDED.granted_office, granted_at = now();
    END IF;
    -- an attempt already running: its end moves by the difference, never into the past
    v_delta := p_minutes - v_old;
    FOR a IN SELECT x.id FROM assessment.cbt_attempt x WHERE x.exam_id = p_exam AND x.candidate_id = p_candidate AND x.status = 'IN_PROGRESS' FOR UPDATE LOOP
        UPDATE assessment.cbt_attempt SET ends_at = greatest(now() + interval '1 minute', ends_at + make_interval(mins => v_delta)) WHERE id = a.id;
        PERFORM assessment.cbt_log(a.id, 'EXTRA_TIME', false, format('%s minutes extra time (was %s): %s', p_minutes, v_old, v_why), NULL);
    END LOOP;
    RETURN p_minutes;
END $$;

-- ── 6 · the start, with the sitting and the extra time ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_start(p_exam uuid, p_student uuid, p_ip text, p_agent text)
RETURNS assessment.cbt_attempt
LANGUAGE plpgsql AS $$
DECLARE e assessment.cbt_exam; a assessment.cbt_attempt; v_why text; v_seed int; v_paper uuid[]; v_versions int[]; v_marks int[]; v_n int; v_jupeb boolean;
        v_sit assessment.cbt_sitting; v_extra int;
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
    -- V373: extra time the office granted the candidate, on top of the time every candidate has
    SELECT x.minutes INTO v_extra FROM assessment.cbt_extra_time x WHERE x.exam_id = p_exam AND x.candidate_id = p_student;
    v_extra := coalesce(v_extra, 0);
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
                               CASE WHEN v_extra > 0 THEN format(' · %s minutes extra time', v_extra) ELSE '' END), p_ip);
    RETURN a;
END $$;

COMMIT;
