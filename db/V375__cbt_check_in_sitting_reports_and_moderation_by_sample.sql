-- V375: candidates checked in at the door; a report for every sitting, with its incidents; moderation that tells the setter, a
--       moderator's queue, and approval by sample.
--
-- 1  Check-in. A candidate's CBT slip carries a QR signed by the API (the examination and the candidate, under the check-code key).
--    An invigilator scans it — with the phone's own camera, which opens the portal's check-in page, or from the board — sees the
--    candidate's photograph, name, number and seat, and checks them in (assessment.cbt_attendance PRESENT, with when, by whom and how:
--    SCAN or MANUAL). An admission late counts as a check-in (ADMITTED). A candidate marked absent is not checked in until the mark is
--    undone. The office may require check-in for an examination's sittings (assessment.cbt_exam.require_check_in): a candidate in a
--    sitting then starts only once checked in or admitted (CBT_NOT_CHECKED_IN). The board shows who is checked in.
-- 2  The sitting report. assessment.cbt_sitting_incident keeps what happened in a sitting — power or network lost (with the minutes),
--    equipment, suspected malpractice, illness, a disturbance, a question of identity, anything else — with the candidate and their
--    attempt where there is one; an invigilator records them as they happen. assessment.cbt_sitting_report is filed once the sitting's
--    candidates have all finished or its time is over: when it actually began and ended, the invigilators present, the remarks, and the
--    counts as they stood (seated, checked in, started, absent, admitted late, finished, incidents). A filed report is not changed; the
--    office adds an addendum, and an incident recorded after filing is marked so.
-- 3  Moderation. Each setter is told — by email, else a text — of the decisions on their questions, gathered per bank, a few minutes
--    after they are made (assessment.notify_moderation, run by the API's clock): how many approved, how many returned. The notice
--    carries no question and no note; those are read in the bank. A moderator approves by sample: a random sample of the questions
--    waiting in a bank that they did not set (assessment.question_moderation_sample); once every question in the sample is approved,
--    the rest approve together, each with the sample named in its decision; one returned, and the rest wait to be moderated one by one.
--    A question changed or decided since the sample was drawn is left as it is.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V375: CBT check-in, sitting reports, moderation notices and sampling', true);

-- ── 1 · check-in ───────────────────────────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.cbt_attendance DROP CONSTRAINT cbt_attendance_status_check;
ALTER TABLE assessment.cbt_attendance ADD CONSTRAINT cbt_attendance_status_check CHECK (status IN ('ABSENT', 'LATE', 'PRESENT'));
ALTER TABLE assessment.cbt_attendance
    ADD COLUMN checked_in_at timestamptz NULL,
    ADD COLUMN checked_in_by uuid NULL,
    ADD COLUMN check_method  text NULL CONSTRAINT ck_cbt_attendance_method CHECK (check_method IN ('SCAN', 'MANUAL', 'ADMITTED')),
    ADD CONSTRAINT ck_cbt_attendance_checked CHECK ((checked_in_at IS NULL) = (check_method IS NULL) AND (status <> 'PRESENT' OR checked_in_at IS NOT NULL)
                                                   AND (status <> 'ABSENT' OR checked_in_at IS NULL));
COMMENT ON COLUMN assessment.cbt_attendance.checked_in_at IS
  'V375: when the candidate was checked in at the door — by scanning their slip (SCAN), by the invigilator finding them on the board (MANUAL), or by being admitted late (ADMITTED).';

ALTER TABLE assessment.cbt_exam ADD COLUMN require_check_in boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN assessment.cbt_exam.require_check_in IS
  'V375: true = a candidate in a sitting starts only once an invigilator has checked them in or admitted them late. Set by the office; off unless it says so.';

/* a seated candidate checked in at the door — once; a candidate marked absent is not, until the mark is undone */
CREATE OR REPLACE FUNCTION assessment.cbt_check_in(p_sitting uuid, p_candidate uuid, p_method text)
RETURNS assessment.cbt_attendance LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; m assessment.cbt_attendance; v_method text := upper(btrim(coalesce(p_method, '')));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'attendance is marked by a person' USING ERRCODE = '23514'; END IF;
    IF v_method NOT IN ('SCAN', 'MANUAL') THEN RAISE EXCEPTION 'CBT_CHECK_IN_METHOD: a candidate is checked in by scanning their slip or by hand' USING ERRCODE = '23514'; END IF;
    s := assessment.cbt_seated_sitting(p_sitting, p_candidate);
    PERFORM pg_advisory_xact_lock(hashtext(s.exam_id::text || ':' || p_candidate::text));
    IF now() >= s.ends_at THEN RAISE EXCEPTION 'CBT_SITTING_OVER: % has ended', s.label USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM assessment.cbt_attendance WHERE sitting_id = s.id AND candidate_id = p_candidate FOR UPDATE;
    IF m.status = 'ABSENT' THEN
        RAISE EXCEPTION 'CBT_CHECK_IN_ABSENT: the candidate is marked absent from %', s.label USING ERRCODE = '23514',
            HINT = 'Undo the mark if it was wrong, or admit them late.';
    END IF;
    IF m.checked_in_at IS NOT NULL THEN RETURN m; END IF;
    IF m.status = 'LATE' THEN
        UPDATE assessment.cbt_attendance SET checked_in_at = now(), checked_in_by = who, check_method = v_method
         WHERE sitting_id = s.id AND candidate_id = p_candidate RETURNING * INTO m;
        RETURN m;
    END IF;
    INSERT INTO assessment.cbt_attendance (sitting_id, candidate_id, exam_id, status, marked_by, marked_office, checked_in_at, checked_in_by, check_method)
    VALUES (s.id, p_candidate, s.exam_id, 'PRESENT', who, actor, now(), who, v_method)
    RETURNING * INTO m;
    RETURN m;
END $$;

/* the office's word on whether its sittings need a check-in */
CREATE OR REPLACE FUNCTION assessment.cbt_set_check_in_required(p_exam uuid, p_required boolean)
RETURNS assessment.cbt_exam LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.cbt_exam;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'check-in is set by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.cbt_exam WHERE id = p_exam FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_EXAM_NOT_FOUND: no such examination' USING ERRCODE = '23503'; END IF;
    IF e.state IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'CBT_STATE: the check-in of a % examination is not changed', lower(e.state) USING ERRCODE = '23514'; END IF;
    UPDATE assessment.cbt_exam SET require_check_in = coalesce(p_required, false) WHERE id = e.id RETURNING * INTO e;
    RETURN e;
END $$;

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
    -- V375: an admission is a check-in, unless the candidate was checked in at the door already
    INSERT INTO assessment.cbt_attendance (sitting_id, candidate_id, exam_id, status, minutes_late, minutes_given, note, marked_by, marked_office,
                                           checked_in_at, checked_in_by, check_method)
    VALUES (s.id, p_candidate, s.exam_id, 'LATE', v_late, p_minutes, nullif(btrim(coalesce(p_note, '')), ''), who, actor, now(), who, 'ADMITTED')
    ON CONFLICT (sitting_id, candidate_id) DO UPDATE SET status = 'LATE', minutes_late = EXCLUDED.minutes_late, minutes_given = EXCLUDED.minutes_given,
        note = EXCLUDED.note, marked_by = EXCLUDED.marked_by, marked_office = EXCLUDED.marked_office, marked_at = now(),
        checked_in_at = coalesce(cbt_attendance.checked_in_at, EXCLUDED.checked_in_at),
        checked_in_by = CASE WHEN cbt_attendance.checked_in_at IS NULL THEN EXCLUDED.checked_in_by ELSE cbt_attendance.checked_in_by END,
        check_method = coalesce(cbt_attendance.check_method, EXCLUDED.check_method)
    RETURNING * INTO m;
    RETURN m;
END $$;

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
        marked_by = EXCLUDED.marked_by, marked_office = EXCLUDED.marked_office, marked_at = now(),
        checked_in_at = NULL, checked_in_by = NULL, check_method = NULL   -- V375: absent is not checked in
    RETURNING * INTO m;
    RETURN m;
END $$;

-- the board: who is checked in, and when
DROP FUNCTION assessment.cbt_sitting_board(uuid);
CREATE OR REPLACE FUNCTION assessment.cbt_sitting_board(p_sitting uuid)
RETURNS TABLE (seat_no int, candidate_id uuid, number text, surname text, other_names text, level int, programme text, state text,
               attempt_id uuid, started_at timestamptz, ends_at timestamptz, submitted_at timestamptz, last_activity_at timestamptz,
               answered int, questions int, violations int, extra_minutes int, mark text, minutes_late int, minutes_given int,
               mark_note text, marked_at timestamptz, marked_by text, checked_in_at timestamptz, check_method text)
LANGUAGE sql STABLE AS $$
    SELECT x.seat_no, x.candidate_id,
           coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no),
           coalesce(st.surname, upper(ja.surname)),
           coalesce(st.other_names, ja.first_name || coalesce(' ' || ja.middle_name, '')),
           st.current_level,
           coalesce(p.name, cb.name),
           CASE WHEN a.id IS NULL THEN CASE m.status WHEN 'ABSENT' THEN 'ABSENT' WHEN 'LATE' THEN 'ADMITTED' WHEN 'PRESENT' THEN 'CHECKED_IN' ELSE 'NOT_COME' END
                WHEN a.status = 'IN_PROGRESS' AND a.ends_at <= now() THEN 'TIME_UP'
                WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED'
                WHEN a.status = 'IN_PROGRESS' THEN 'WRITING'
                ELSE a.status END,
           a.id, a.started_at, a.ends_at, a.submitted_at, a.last_activity_at, a.answered, cardinality(a.question_ids), a.violations,
           xt.minutes, m.status, m.minutes_late, m.minutes_given, m.note, m.marked_at,
           CASE WHEN pm.id IS NULL THEN NULL ELSE pm.surname || ', ' || pm.given_names END,
           m.checked_in_at, m.check_method
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

-- ── 2 · the sitting report and its incidents ───────────────────────────────────────────────────────────────────

CREATE TABLE assessment.cbt_sitting_incident (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sitting_id      uuid NOT NULL REFERENCES assessment.cbt_sitting(id) ON DELETE CASCADE,
    exam_id         uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    candidate_id    uuid NULL,
    attempt_id      uuid NULL REFERENCES assessment.cbt_attempt(id) ON DELETE SET NULL,
    kind            text NOT NULL CHECK (kind IN ('POWER', 'NETWORK', 'EQUIPMENT', 'MALPRACTICE', 'ILLNESS', 'DISTURBANCE', 'IDENTITY', 'OTHER')),
    occurred_at     timestamptz NOT NULL,
    minutes_lost    int NULL CHECK (minutes_lost BETWEEN 0 AND 600),
    detail          text NOT NULL CHECK (btrim(detail) <> ''),
    after_filing    boolean NOT NULL DEFAULT false,
    recorded_by     uuid NOT NULL,
    recorded_office text NULL,
    recorded_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE assessment.cbt_sitting_incident IS
  'V375: what happened in a sitting — power or network lost (with the minutes), equipment, suspected malpractice, illness, a disturbance, a question of identity, anything else — with the candidate and their attempt where there is one. Recorded by an invigilator or the office; one recorded after the report was filed is marked so.';
CREATE INDEX ix_cbt_sitting_incident ON assessment.cbt_sitting_incident (sitting_id, occurred_at);
CREATE INDEX ix_cbt_sitting_incident_candidate ON assessment.cbt_sitting_incident (exam_id, candidate_id) WHERE candidate_id IS NOT NULL;
SELECT audit.attach('assessment.cbt_sitting_incident');

CREATE TABLE assessment.cbt_sitting_report (
    sitting_id      uuid PRIMARY KEY REFERENCES assessment.cbt_sitting(id) ON DELETE CASCADE,
    exam_id         uuid NOT NULL REFERENCES assessment.cbt_exam(id) ON DELETE CASCADE,
    began_at        timestamptz NOT NULL,
    ended_at        timestamptz NOT NULL,
    invigilators    uuid[] NOT NULL,
    remarks         text NULL,
    counts          jsonb NOT NULL,
    filed_by        uuid NOT NULL,
    filed_office    text NULL,
    filed_at        timestamptz NOT NULL DEFAULT now(),
    addendum        text NULL,
    addendum_at     timestamptz NULL,
    CONSTRAINT ck_cbt_sitting_report_time CHECK (ended_at >= began_at)
);
COMMENT ON TABLE assessment.cbt_sitting_report IS
  'V375: the report of a sitting, filed once its candidates have finished or its time is over — when it actually began and ended, the invigilators present, the remarks and the counts as they stood. Not changed after filing; the office adds an addendum.';
SELECT audit.attach('assessment.cbt_sitting_report');

GRANT SELECT ON assessment.cbt_sitting_incident, assessment.cbt_sitting_report TO app_auditor;

/* an incident recorded in a sitting: the candidate (seated in it) and their attempt where there is one */
CREATE OR REPLACE FUNCTION assessment.cbt_record_incident(p_sitting uuid, p_candidate uuid, p_kind text, p_detail text, p_minutes_lost int, p_occurred_at timestamptz)
RETURNS assessment.cbt_sitting_incident LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; x assessment.cbt_sitting_incident; v_kind text := upper(btrim(coalesce(p_kind, ''))); v_at timestamptz := coalesce(p_occurred_at, now());
        v_attempt uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an incident is recorded by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    IF v_kind NOT IN ('POWER', 'NETWORK', 'EQUIPMENT', 'MALPRACTICE', 'ILLNESS', 'DISTURBANCE', 'IDENTITY', 'OTHER') THEN
        RAISE EXCEPTION 'CBT_INCIDENT_KIND: an incident is power, network, equipment, malpractice, illness, a disturbance, identity or other' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_detail, '')) = '' THEN RAISE EXCEPTION 'CBT_INCIDENT_DETAIL: an incident says what happened' USING ERRCODE = '23514'; END IF;
    IF v_at > now() + interval '1 minute' THEN RAISE EXCEPTION 'CBT_INCIDENT_TIME: an incident is recorded once it has happened' USING ERRCODE = '23514'; END IF;
    IF v_at < s.starts_at - interval '1 day' OR v_at > s.ends_at + interval '1 day' THEN
        RAISE EXCEPTION 'CBT_INCIDENT_TIME: an incident of % happened on the day of the sitting', s.label USING ERRCODE = '23514';
    END IF;
    IF p_candidate IS NOT NULL THEN
        PERFORM assessment.cbt_seated_sitting(s.id, p_candidate);
        SELECT a.id INTO v_attempt FROM assessment.cbt_attempt a WHERE a.exam_id = s.exam_id AND a.candidate_id = p_candidate ORDER BY a.number DESC LIMIT 1;
    END IF;
    INSERT INTO assessment.cbt_sitting_incident (sitting_id, exam_id, candidate_id, attempt_id, kind, occurred_at, minutes_lost, detail, after_filing, recorded_by, recorded_office)
    VALUES (s.id, s.exam_id, p_candidate, v_attempt, v_kind, v_at, p_minutes_lost, btrim(p_detail),
            EXISTS (SELECT 1 FROM assessment.cbt_sitting_report r WHERE r.sitting_id = s.id), who, actor)
    RETURNING * INTO x;
    RETURN x;
END $$;

/* the counts of a sitting as they stand */
CREATE OR REPLACE FUNCTION assessment.cbt_sitting_counts(p_sitting uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'seated', count(*),
        'checked_in', count(*) FILTER (WHERE b.checked_in_at IS NOT NULL),
        'started', count(*) FILTER (WHERE b.attempt_id IS NOT NULL),
        'not_come', count(*) FILTER (WHERE b.state = 'NOT_COME'),
        'not_started', count(*) FILTER (WHERE b.state IN ('CHECKED_IN', 'ADMITTED')),
        'absent', count(*) FILTER (WHERE b.mark = 'ABSENT'),
        'late', count(*) FILTER (WHERE b.mark = 'LATE'),
        'writing', count(*) FILTER (WHERE b.state IN ('WRITING', 'DISCONNECTED', 'TIME_UP')),
        'submitted', count(*) FILTER (WHERE b.state = 'SUBMITTED'),
        'time_expired', count(*) FILTER (WHERE b.state = 'TIME_EXPIRED'),
        'terminated', count(*) FILTER (WHERE b.state = 'TERMINATED'),
        'incidents', (SELECT count(*) FROM assessment.cbt_sitting_incident i WHERE i.sitting_id = p_sitting),
        'minutes_lost', (SELECT coalesce(sum(i.minutes_lost), 0) FROM assessment.cbt_sitting_incident i WHERE i.sitting_id = p_sitting AND i.candidate_id IS NULL))
      FROM assessment.cbt_sitting_board(p_sitting) b
$$;

/* the report filed: once every candidate who began has finished, or the sitting's time is over; never twice */
CREATE OR REPLACE FUNCTION assessment.cbt_file_sitting_report(p_sitting uuid, p_began timestamptz, p_ended timestamptz, p_invigilators uuid[], p_remarks text)
RETURNS assessment.cbt_sitting_report LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        s assessment.cbt_sitting; r assessment.cbt_sitting_report; v_writing int; v_unknown int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a report is filed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SITTING_NOT_FOUND: no such sitting' USING ERRCODE = '23503'; END IF;
    IF EXISTS (SELECT 1 FROM assessment.cbt_sitting_report x WHERE x.sitting_id = s.id) THEN
        RAISE EXCEPTION 'CBT_REPORT_FILED: the report of % is filed; the office adds an addendum', s.label USING ERRCODE = '23514';
    END IF;
    IF now() < s.starts_at THEN RAISE EXCEPTION 'CBT_SITTING_NOT_BEGUN: % has not begun', s.label USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_writing FROM assessment.cbt_seat x JOIN assessment.cbt_attempt a ON a.exam_id = x.exam_id AND a.candidate_id = x.candidate_id
     WHERE x.sitting_id = s.id AND a.status = 'IN_PROGRESS';
    IF v_writing > 0 AND now() < s.ends_at THEN
        RAISE EXCEPTION 'CBT_SITTING_RUNNING: % candidate% of % still writing', v_writing, CASE WHEN v_writing = 1 THEN ' is' ELSE 's are' END, s.label USING ERRCODE = '23514',
            HINT = 'File the report once they have finished, or once the sitting''s time is over.';
    END IF;
    IF p_began IS NULL OR p_ended IS NULL OR p_ended < p_began THEN
        RAISE EXCEPTION 'CBT_REPORT_TIME: the report says when the sitting began and ended' USING ERRCODE = '23514';
    END IF;
    IF p_began < s.starts_at - interval '1 day' OR p_ended > now() + interval '1 minute' THEN
        RAISE EXCEPTION 'CBT_REPORT_TIME: the sitting began and ended on its day, and has ended' USING ERRCODE = '23514';
    END IF;
    IF coalesce(cardinality(p_invigilators), 0) = 0 THEN RAISE EXCEPTION 'CBT_REPORT_INVIGILATORS: the report names the invigilators present' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_unknown FROM unnest(p_invigilators) p(id)
     WHERE NOT EXISTS (SELECT 1 FROM assessment.cbt_invigilator i WHERE i.sitting_id = s.id AND i.person_id = p.id);
    IF v_unknown > 0 THEN RAISE EXCEPTION 'CBT_REPORT_INVIGILATORS: the invigilators present are those named for %', s.label USING ERRCODE = '23514'; END IF;
    INSERT INTO assessment.cbt_sitting_report (sitting_id, exam_id, began_at, ended_at, invigilators, remarks, counts, filed_by, filed_office)
    VALUES (s.id, s.exam_id, p_began, p_ended, (SELECT array_agg(DISTINCT x) FROM unnest(p_invigilators) x), nullif(btrim(coalesce(p_remarks, '')), ''),
            assessment.cbt_sitting_counts(s.id), who, actor)
    RETURNING * INTO r;
    RETURN r;
END $$;

/* the office's addendum to a filed report: added to, never rewritten */
CREATE OR REPLACE FUNCTION assessment.cbt_sitting_report_addendum(p_sitting uuid, p_text text)
RETURNS assessment.cbt_sitting_report LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r assessment.cbt_sitting_report;
        v_name text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an addendum is written by a person' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_text, '')) = '' THEN RAISE EXCEPTION 'CBT_ADDENDUM_TEXT: an addendum says what it adds' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM assessment.cbt_sitting_report WHERE sitting_id = p_sitting FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_REPORT_NOT_FILED: the sitting''s report is not filed yet' USING ERRCODE = '23514'; END IF;
    SELECT p.surname || ', ' || p.given_names INTO v_name FROM iam.person p WHERE p.id = who;
    UPDATE assessment.cbt_sitting_report
       SET addendum = concat_ws(E'\n', addendum, to_char(now() AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI') || ' · ' || coalesce(v_name, 'the office') || ': ' || btrim(p_text)),
           addendum_at = now()
     WHERE sitting_id = p_sitting RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 3 · moderation: the setter told, the moderator's sample ────────────────────────────────────────────────────

ALTER TABLE assessment.question_moderation ADD COLUMN noticed_at timestamptz NULL;
COMMENT ON COLUMN assessment.question_moderation.noticed_at IS 'V375: when the setter was told of the decision (gathered per bank by assessment.notify_moderation); NULL until then.';
CREATE INDEX ix_question_moderation_unnoticed ON assessment.question_moderation (decided_at) WHERE noticed_at IS NULL;

/* each setter told, once a few minutes have passed, of the decisions on their questions, a notice per bank: how many approved and
   returned — never a question or a note, which are read in the bank */
CREATE OR REPLACE FUNCTION assessment.notify_moderation(p_settle interval DEFAULT interval '5 minutes')
RETURNS int LANGUAGE plpgsql AS $$
DECLARE g record; n int := 0; v_subject text; v_body text;
BEGIN
    FOR g IN
        SELECT coalesce(qv.created_by, q.updated_by, q.authored_by) AS setter, coalesce(q.course_code, 'JUPEB ' || js.code) AS bank,
               count(*) FILTER (WHERE m.decision = 'APPROVED') AS approved, count(*) FILTER (WHERE m.decision = 'RETURNED') AS returned,
               array_agg(m.id) AS ids
          FROM assessment.question_moderation m
          JOIN assessment.question q ON q.id = m.question_id
          LEFT JOIN assessment.question_version qv ON qv.question_id = m.question_id AND qv.version = m.version
          LEFT JOIN jupeb.subject js ON js.id = q.jupeb_subject_id
         WHERE m.noticed_at IS NULL AND m.decided_at <= clock_timestamp() - p_settle
         GROUP BY 1, 2
    LOOP
        UPDATE assessment.question_moderation SET noticed_at = now() WHERE id = ANY (g.ids);
        CONTINUE WHEN g.setter IS NULL;
        v_subject := 'Question moderation: ' || g.bank;
        v_body := 'Your questions in the ' || g.bank || ' question bank were moderated: '
               || concat_ws(' and ', CASE WHEN g.approved > 0 THEN g.approved || ' approved' END,
                                     CASE WHEN g.returned > 0 THEN g.returned || ' returned with a note' END) || '. '
               || CASE WHEN g.returned > 0 THEN 'Sign in to the portal and open the question bank to read the notes and correct the returned questions; a corrected question goes back for moderation.'
                       ELSE 'Approved questions may now go on a paper.' END;
        IF EXISTS (SELECT 1 FROM iam.person p WHERE p.id = g.setter AND nullif(btrim(coalesce(p.email, '')), '') IS NOT NULL) THEN
            PERFORM platform.queue_notice('EMAIL', (SELECT btrim(p.email) FROM iam.person p WHERE p.id = g.setter), v_subject, v_body, 'person', g.setter);
            n := n + 1;
        ELSIF EXISTS (SELECT 1 FROM iam.person p WHERE p.id = g.setter AND nullif(btrim(coalesce(p.phone, '')), '') IS NOT NULL) THEN
            PERFORM platform.queue_notice('SMS', (SELECT btrim(p.phone) FROM iam.person p WHERE p.id = g.setter), v_subject,
                'MOAUM: ' || concat_ws(', ', CASE WHEN g.approved > 0 THEN g.approved || ' approved' END, CASE WHEN g.returned > 0 THEN g.returned || ' returned' END)
                || ' of your ' || g.bank || ' questions. See the question bank on the portal.', 'person', g.setter);
            n := n + 1;
        END IF;
    END LOOP;
    RETURN n;
END $$;

CREATE TABLE assessment.question_moderation_sample (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code         text NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    jupeb_subject_id    uuid NULL REFERENCES jupeb.subject(id) ON DELETE CASCADE,
    drawn_by            uuid NOT NULL,
    drawn_office        text NULL,
    drawn_at            timestamptz NOT NULL DEFAULT now(),
    population          uuid[] NOT NULL,
    population_versions int[] NOT NULL,
    sample              uuid[] NOT NULL,
    state               text NOT NULL DEFAULT 'OPEN' CHECK (state IN ('OPEN', 'APPROVED', 'FAILED', 'WITHDRAWN')),
    decided_at          timestamptz NULL,
    approved            int NULL,
    left_as_they_were   int NULL,
    CONSTRAINT ck_question_sample_bank CHECK ((course_code IS NULL) <> (jupeb_subject_id IS NULL)),
    CONSTRAINT ck_question_sample_size CHECK (cardinality(sample) >= 1 AND cardinality(sample) <= cardinality(population)
                                              AND cardinality(population) = cardinality(population_versions))
);
COMMENT ON TABLE assessment.question_moderation_sample IS
  'V375: a moderator''s random sample of the questions waiting in a bank that they did not set, with the population as it stood (each question at its version). Every sampled question approved: the rest approve together; one returned: the sample fails and the rest wait.';
CREATE UNIQUE INDEX ux_question_sample_open ON assessment.question_moderation_sample (drawn_by, coalesce(course_code, jupeb_subject_id::text)) WHERE state = 'OPEN';
SELECT audit.attach('assessment.question_moderation_sample');
GRANT SELECT ON assessment.question_moderation_sample TO app_auditor;

/* a random sample of the size the moderator chooses, from the bank's questions waiting (not returned) that they did not set */
CREATE OR REPLACE FUNCTION assessment.question_sample_draw(p_course text, p_subject uuid, p_size int)
RETURNS assessment.question_moderation_sample LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := nullif(current_setting('moaum.actor_office', true), '');
        v_pop uuid[]; v_ver int[]; v_sample uuid[]; x assessment.question_moderation_sample;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'CBT_MODERATOR_REQUIRED: a sample is drawn by a person' USING ERRCODE = '23514'; END IF;
    IF (p_course IS NULL) = (p_subject IS NULL) THEN RAISE EXCEPTION 'CBT_SAMPLE_BANK: a sample is drawn from one bank' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM assessment.question_moderation_sample s WHERE s.state = 'OPEN' AND s.drawn_by = who
                  AND coalesce(s.course_code, s.jupeb_subject_id::text) = coalesce(p_course, p_subject::text)) THEN
        RAISE EXCEPTION 'CBT_SAMPLE_OPEN: you have a sample of this bank open; finish it or withdraw it first' USING ERRCODE = '23514';
    END IF;
    SELECT array_agg(q.id ORDER BY q.id), array_agg(q.version ORDER BY q.id) INTO v_pop, v_ver
      FROM assessment.question q
     WHERE CASE WHEN p_subject IS NULL THEN q.course_code = p_course ELSE q.jupeb_subject_id = p_subject END
       AND q.moderation = 'PENDING' AND q.archived_at IS NULL
       AND assessment.question_setter(q.id, q.version) IS DISTINCT FROM who;
    IF coalesce(cardinality(v_pop), 0) = 0 THEN
        RAISE EXCEPTION 'CBT_SAMPLE_NOTHING: no question in this bank waits for you to moderate' USING ERRCODE = '23514';
    END IF;
    IF p_size IS NULL OR p_size < 1 OR p_size > cardinality(v_pop) THEN
        RAISE EXCEPTION 'CBT_SAMPLE_SIZE: a sample is 1 to % questions, the number waiting', cardinality(v_pop) USING ERRCODE = '23514';
    END IF;
    SELECT array_agg(id) INTO v_sample FROM (SELECT u.id FROM unnest(v_pop) u(id) ORDER BY random() LIMIT p_size) d;
    INSERT INTO assessment.question_moderation_sample (course_code, jupeb_subject_id, drawn_by, drawn_office, population, population_versions, sample)
    VALUES (p_course, p_subject, who, actor, v_pop, v_ver, v_sample)
    RETURNING * INTO x;
    RETURN x;
END $$;

/* the sample decided: every sampled question approved at the version drawn — the rest of the population approve together, each
   naming the sample; one returned — the sample fails and the rest wait; one still undecided — refused */
CREATE OR REPLACE FUNCTION assessment.question_sample_close(p_sample uuid)
RETURNS assessment.question_moderation_sample LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; x assessment.question_moderation_sample; v_returned int; v_waiting int;
        pq record; n int := 0; v_left int := 0; v_note text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'CBT_MODERATOR_REQUIRED: a sample is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO x FROM assessment.question_moderation_sample WHERE id = p_sample FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SAMPLE_NOT_FOUND: no such sample' USING ERRCODE = '23503'; END IF;
    IF x.drawn_by IS DISTINCT FROM who THEN RAISE EXCEPTION 'CBT_SAMPLE_NOT_YOURS: a sample is decided by the moderator who drew it' USING ERRCODE = '23514'; END IF;
    IF x.state <> 'OPEN' THEN RAISE EXCEPTION 'CBT_SAMPLE_CLOSED: the sample is % already', lower(x.state) USING ERRCODE = '23514'; END IF;
    -- each sampled question as it stands, at the version drawn
    SELECT count(*) FILTER (WHERE q.moderation = 'RETURNED' AND q.version = pv.v),
           count(*) FILTER (WHERE NOT (q.moderation = 'APPROVED' AND q.moderated_version = pv.v) AND NOT (q.moderation = 'RETURNED' AND q.version = pv.v))
      INTO v_returned, v_waiting
      FROM unnest(x.sample) s(id)
      JOIN unnest(x.population, x.population_versions) pv(id, v) ON pv.id = s.id
      JOIN assessment.question q ON q.id = s.id;
    IF v_returned > 0 THEN
        UPDATE assessment.question_moderation_sample SET state = 'FAILED', decided_at = now(), approved = 0, left_as_they_were = cardinality(population) - cardinality(sample)
         WHERE id = x.id RETURNING * INTO x;
        RETURN x;
    END IF;
    IF v_waiting > 0 THEN
        RAISE EXCEPTION 'CBT_SAMPLE_UNFINISHED: % question% of the sample % not been decided at the version drawn', v_waiting, CASE WHEN v_waiting = 1 THEN '' ELSE 's' END,
            CASE WHEN v_waiting = 1 THEN 'has' ELSE 'have' END USING ERRCODE = '23514',
            HINT = 'Approve or return every question in the sample first; one changed since the draw is moderated on its own.';
    END IF;
    v_note := format('Approved by sample: %s of %s questions reviewed, all approved (sample %s)', cardinality(x.sample), cardinality(x.population), left(x.id::text, 8));
    FOR pq IN SELECT pv.id, pv.v FROM unnest(x.population, x.population_versions) pv(id, v) WHERE NOT (pv.id = ANY (x.sample)) LOOP
        IF EXISTS (SELECT 1 FROM assessment.question qq WHERE qq.id = pq.id AND qq.version = pq.v AND qq.moderation = 'PENDING' AND qq.archived_at IS NULL)
           AND assessment.question_moderation_problem(pq.id, 'APPROVE', v_note) IS NULL THEN
            PERFORM assessment.question_moderate(pq.id, 'APPROVE', v_note);
            n := n + 1;
        ELSE
            v_left := v_left + 1;
        END IF;
    END LOOP;
    UPDATE assessment.question_moderation_sample SET state = 'APPROVED', decided_at = now(), approved = n, left_as_they_were = v_left
     WHERE id = x.id RETURNING * INTO x;
    RETURN x;
END $$;

CREATE OR REPLACE FUNCTION assessment.question_sample_withdraw(p_sample uuid)
RETURNS assessment.question_moderation_sample LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; x assessment.question_moderation_sample;
BEGIN
    SELECT * INTO x FROM assessment.question_moderation_sample WHERE id = p_sample FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_SAMPLE_NOT_FOUND: no such sample' USING ERRCODE = '23503'; END IF;
    IF x.drawn_by IS DISTINCT FROM who THEN RAISE EXCEPTION 'CBT_SAMPLE_NOT_YOURS: a sample is withdrawn by the moderator who drew it' USING ERRCODE = '23514'; END IF;
    IF x.state <> 'OPEN' THEN RAISE EXCEPTION 'CBT_SAMPLE_CLOSED: the sample is % already', lower(x.state) USING ERRCODE = '23514'; END IF;
    UPDATE assessment.question_moderation_sample SET state = 'WITHDRAWN', decided_at = now() WHERE id = x.id RETURNING * INTO x;
    RETURN x;
END $$;

-- ── 4 · the start: when the office requires it, a candidate in a sitting starts once checked in ─────────────────

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
        -- V375: when the office requires it, a candidate starts once an invigilator has checked them in (or admitted them late)
        IF e.require_check_in AND coalesce(v_mark.status, '') NOT IN ('PRESENT', 'LATE') THEN
            RAISE EXCEPTION 'CBT_NOT_CHECKED_IN: the invigilator has not checked you in to %', v_sit.label USING ERRCODE = '23514',
                HINT = 'Show your CBT slip to the invigilator at the door.';
        END IF;
        IF e.late_entry_minutes IS NOT NULL AND v_mark.status IS DISTINCT FROM 'LATE'
           AND NOT coalesce(v_mark.checked_in_at <= v_sit.starts_at + make_interval(mins => e.late_entry_minutes), false)   -- V375: at the door in time
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

COMMIT;
