-- V376: diagrams in CBT questions (formulas are written in the text between dollar signs and drawn by the screens); the time an outage
--       took given back to everyone writing, in one step; a candidate never seated in two sittings at the same time.
--
-- 1  Images. A question may carry a diagram, and each option one of its own (assessment.question_image: a PNG or JPEG of at most
--    1 MB, in the object store or, without one, in assessment.question_image_blob; an image is never changed — a new one is added).
--    assessment.question.image_id and option_images (one entry an option, NULL for none) are part of the question's content: a
--    change is a new version, kept whole in assessment.question_version, and waits for moderation again. A candidate's paper carries
--    the image of each question and option at the version drawn (assessment.cbt_candidate_paper), and the candidate sees an image
--    only inside their own running attempt; the office's preview carries them too. Formulas need no change of record: the text
--    between dollar signs ($x^2$, $\frac{1}{2}mv^2$, $H_2O$) is drawn by the screens, as JUPEB practice already does.
-- 2  Time back. An incident in a sitting (a power cut, a network failure, anything for the hall or for one candidate) is given its
--    time back by the office: the minutes it chooses go, as extra time, to every candidate of the sitting (or the one candidate)
--    whose attempt was running when it happened and still runs, each with the incident named in the reason; once only, and on
--    the incident's record (how many minutes, to how many, when, by whom). A candidate who has finished is not reopened.
-- 3  Clashes. A candidate is not seated in a sitting that overlaps one they are seated in for another examination
--    (assessment.cbt_seat_clash): moving one is refused (CBT_SEAT_CLASH), seating everyone passes over a sitting that clashes and
--    says how many could not be seated for a clash; assessment.cbt_seat_clashes lists every clash an examination's seats have (a
--    sitting moved after seating may make one).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V376: CBT question images, time back after an incident, seating clashes', true);

-- ── 1 · images ─────────────────────────────────────────────────────────────────────────────────────────────────

CREATE TABLE assessment.question_image (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    filename     text NOT NULL CHECK (btrim(filename) <> '' AND length(filename) <= 200),
    content_type text NOT NULL CHECK (content_type IN ('image/png', 'image/jpeg')),
    size_bytes   int NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 1048576),
    object_id    uuid NULL REFERENCES platform.file_object(id),
    uploaded_by  uuid NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE assessment.question_image IS
  'V376: a diagram of a CBT question or of one of its options — PNG or JPEG, at most 1 MB, in the object store (object_id) or in question_image_blob. Never changed: a new image is added and the question versioned.';
SELECT audit.attach('assessment.question_image');
CREATE TABLE assessment.question_image_blob (
    image_id uuid PRIMARY KEY REFERENCES assessment.question_image(id) ON DELETE CASCADE,
    bytes    bytea NOT NULL
);
SELECT audit.exempt('assessment.question_image_blob', 'The bytes of a CBT question''s image kept in the database when no object store is configured; the image row on the spine records who uploaded it.');
GRANT SELECT ON assessment.question_image TO app_auditor;

ALTER TABLE assessment.question
    ADD COLUMN image_id      uuid NULL REFERENCES assessment.question_image(id),
    ADD COLUMN option_images uuid[] NULL,
    ADD CONSTRAINT ck_question_option_images CHECK (option_images IS NULL OR cardinality(option_images) = jsonb_array_length(options));
COMMENT ON COLUMN assessment.question.image_id IS 'V376: the question''s diagram, part of its content: a change is a new version and waits for moderation again.';
COMMENT ON COLUMN assessment.question.option_images IS 'V376: an image for each option, in the options'' written order (NULL for an option without one); NULL when no option has one.';
ALTER TABLE assessment.question_version
    ADD COLUMN image_id      uuid NULL REFERENCES assessment.question_image(id),
    ADD COLUMN option_images uuid[] NULL;

CREATE OR REPLACE FUNCTION assessment.question_versioned()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    -- V376: the question's diagram and its options' images are content too
    IF (NEW.stem, NEW.options, NEW.answers, NEW.kind, NEW.marks, NEW.explanation, NEW.image_id, NEW.option_images)
       IS DISTINCT FROM (OLD.stem, OLD.options, OLD.answers, OLD.kind, OLD.marks, OLD.explanation, OLD.image_id, OLD.option_images) THEN
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

CREATE OR REPLACE FUNCTION assessment.question_version_kept()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO assessment.question_version (question_id, version, kind, stem, options, answers, explanation, marks, topic, difficulty, created_by, image_id, option_images)
    VALUES (NEW.id, NEW.version, NEW.kind, NEW.stem, NEW.options, coalesce(NEW.answers, ARRAY[NEW.answer]), NEW.explanation, NEW.marks, NEW.topic, NEW.difficulty,
            coalesce(NEW.updated_by, NEW.authored_by, nullif(current_setting('moaum.actor_id', true), '')::uuid), NEW.image_id, NEW.option_images)
    ON CONFLICT (question_id, version) DO NOTHING;
    RETURN NULL;
END $$;

/* whether an image is on the paper a candidate's attempt drew (the question's, or an option's, at the version drawn) */
CREATE OR REPLACE FUNCTION assessment.cbt_attempt_shows_image(p_attempt uuid, p_image uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM assessment.cbt_attempt a
                     CROSS JOIN LATERAL unnest(a.question_ids, a.question_versions) u(qid, v)
                     JOIN assessment.question_version qv ON qv.question_id = u.qid AND qv.version = u.v
                    WHERE a.id = p_attempt AND (qv.image_id = p_image OR p_image = ANY (coalesce(qv.option_images, '{}'))))
$$;

/* a question an image belongs to (its current content or any version of it) — for the office reading it through the question's bank */
CREATE OR REPLACE FUNCTION assessment.question_of_image(p_image uuid)
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT q.id FROM assessment.question q WHERE q.image_id = p_image OR p_image = ANY (coalesce(q.option_images, '{}')) LIMIT 1),
        (SELECT v.question_id FROM assessment.question_version v WHERE v.image_id = p_image OR p_image = ANY (coalesce(v.option_images, '{}')) LIMIT 1))
$$;

-- the candidate's paper and the office's preview carry the images
DROP FUNCTION assessment.cbt_candidate_paper(uuid);
CREATE FUNCTION assessment.cbt_candidate_paper(p_attempt uuid)
RETURNS TABLE (n int, id uuid, kind text, stem text, marks int, options jsonb, image uuid)
LANGUAGE sql STABLE AS $$
    SELECT x.n, x.question_id, x.kind, x.stem, x.marks,
           (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('i', o.i - 1, 'text', o.t, 'image', qv.option_images[o.i]))
                             ORDER BY CASE WHEN e.randomize_options THEN md5(a.seed::text || x.question_id::text || o.i::text) ELSE lpad(o.i::text, 4, '0') END)
              FROM jsonb_array_elements_text(x.options) WITH ORDINALITY o(t, i)),
           qv.image_id
      FROM assessment.cbt_attempt a JOIN assessment.cbt_exam e ON e.id = a.exam_id
      CROSS JOIN LATERAL assessment.cbt_attempt_questions(a.id) x
      JOIN assessment.question_version qv ON qv.question_id = x.question_id AND qv.version = x.version
     WHERE a.id = p_attempt
     ORDER BY x.n
$$;

DROP FUNCTION assessment.cbt_preview_paper(uuid);
CREATE FUNCTION assessment.cbt_preview_paper(p_exam uuid)
RETURNS TABLE (n int, id uuid, kind text, stem text, marks int, options jsonb, image uuid)
LANGUAGE sql STABLE AS $$
    SELECT (row_number() OVER (ORDER BY p.ordinal, q.authored_at, q.id))::int,
           q.id, coalesce(qv.kind, q.kind, 'MCQ'), coalesce(qv.stem, q.stem), p.marks,
           (SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('i', o.i - 1, 'text', o.t, 'image', (coalesce(qv.option_images, q.option_images))[o.i])) ORDER BY o.i), '[]'::jsonb)
              FROM jsonb_array_elements_text(coalesce(qv.options, q.options)) WITH ORDINALITY o(t, i)),
           coalesce(qv.image_id, q.image_id)
      FROM assessment.cbt_pool(p_exam) p
      JOIN assessment.question q ON q.id = p.question_id
      LEFT JOIN assessment.question_version qv ON qv.question_id = q.id AND qv.version = q.version
     ORDER BY 1
$$;

-- ── 2 · time back after an incident ────────────────────────────────────────────────────────────────────────────

ALTER TABLE assessment.cbt_sitting_incident
    ADD COLUMN time_given_minutes int NULL CHECK (time_given_minutes BETWEEN 1 AND 600),
    ADD COLUMN time_given_to      int NULL,
    ADD COLUMN time_given_at      timestamptz NULL,
    ADD COLUMN time_given_by      uuid NULL,
    ADD CONSTRAINT ck_cbt_incident_time_given CHECK ((time_given_at IS NULL) = (time_given_minutes IS NULL));
COMMENT ON COLUMN assessment.cbt_sitting_incident.time_given_minutes IS
  'V376: the minutes the office gave back for the incident, as extra time, to every candidate whose attempt was running when it happened and still ran (time_given_to of them).';

/* who an incident's time would go to: the candidates of the sitting (or the incident's own candidate) whose attempt was running
   when it happened — still writing, or finished since */
CREATE OR REPLACE FUNCTION assessment.cbt_time_back_candidates(p_incident uuid)
RETURNS TABLE (candidate_id uuid, attempt_id uuid, seat_no int, number text, surname text, other_names text, still_writing boolean,
               attempt_status text, extra_minutes int)
LANGUAGE sql STABLE AS $$
    SELECT x.candidate_id, a.id, x.seat_no,
           coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no), coalesce(st.surname, upper(ja.surname)),
           coalesce(st.other_names, ja.first_name || coalesce(' ' || ja.middle_name, '')),
           a.status = 'IN_PROGRESS' AND a.ends_at > now(), a.status, xt.minutes
      FROM assessment.cbt_sitting_incident i
      JOIN assessment.cbt_seat x ON x.sitting_id = i.sitting_id AND (i.candidate_id IS NULL OR x.candidate_id = i.candidate_id)
      JOIN LATERAL (SELECT t.* FROM assessment.cbt_attempt t
                     WHERE t.exam_id = x.exam_id AND t.candidate_id = x.candidate_id AND t.started_at <= i.occurred_at
                       AND (t.submitted_at IS NULL OR t.submitted_at > i.occurred_at)
                     ORDER BY t.number DESC LIMIT 1) a ON true
      LEFT JOIN people.student st ON st.id = x.candidate_id
      LEFT JOIN jupeb.application ja ON st.id IS NULL AND ja.id = x.candidate_id
      LEFT JOIN assessment.cbt_extra_time xt ON xt.exam_id = x.exam_id AND xt.candidate_id = x.candidate_id
     WHERE i.id = p_incident
     ORDER BY x.seat_no
$$;

/* the incident's time given back, once: the minutes added to the extra time of each candidate still writing, the incident named */
CREATE OR REPLACE FUNCTION assessment.cbt_give_time_back(p_incident uuid, p_minutes int)
RETURNS assessment.cbt_sitting_incident LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; i assessment.cbt_sitting_incident; s assessment.cbt_sitting; c record;
        n int := 0; v_had int; v_why text; v_reason text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'time is given back by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO i FROM assessment.cbt_sitting_incident WHERE id = p_incident FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_INCIDENT_NOT_FOUND: no such incident' USING ERRCODE = '23503'; END IF;
    IF i.time_given_at IS NOT NULL THEN
        RAISE EXCEPTION 'CBT_TIME_GIVEN: % minutes were given back for this incident already, to % candidate%', i.time_given_minutes, i.time_given_to,
            CASE WHEN i.time_given_to = 1 THEN '' ELSE 's' END USING ERRCODE = '23514';
    END IF;
    IF p_minutes IS NULL OR p_minutes < 1 OR p_minutes > 600 THEN RAISE EXCEPTION 'CBT_EXTRA_RANGE: time given back is 1 to 600 minutes' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM assessment.cbt_sitting WHERE id = i.sitting_id;
    v_reason := format('%s minutes given back for %s at %s in %s', p_minutes,
                       CASE i.kind WHEN 'POWER' THEN 'the power cut' WHEN 'NETWORK' THEN 'the network failure' WHEN 'EQUIPMENT' THEN 'the equipment fault'
                                   WHEN 'ILLNESS' THEN 'illness' WHEN 'DISTURBANCE' THEN 'the disturbance' ELSE 'the incident' END,
                       to_char(i.occurred_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI'), s.label);
    FOR c IN SELECT * FROM assessment.cbt_time_back_candidates(i.id) b WHERE b.still_writing LOOP
        SELECT x.minutes, x.reason INTO v_had, v_why FROM assessment.cbt_extra_time x WHERE x.exam_id = i.exam_id AND x.candidate_id = c.candidate_id;
        PERFORM assessment.cbt_grant_extra_time(i.exam_id, c.candidate_id, least(600, coalesce(v_had, 0) + p_minutes), concat_ws('; ', v_why, v_reason));
        n := n + 1;
    END LOOP;
    UPDATE assessment.cbt_sitting_incident SET time_given_minutes = p_minutes, time_given_to = n, time_given_at = now(), time_given_by = who
     WHERE id = i.id RETURNING * INTO i;
    RETURN i;
END $$;

-- ── 3 · clashes ────────────────────────────────────────────────────────────────────────────────────────────────

/* the sitting of another examination the candidate is seated in at the same time as this one, described; NULL when none */
CREATE OR REPLACE FUNCTION assessment.cbt_seat_clash(p_candidate uuid, p_sitting uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT format('%s %s, %s at %s, %s to %s', coalesce(oe.course_code, js.code), oe.title, o.label, o.venue,
                  to_char(o.starts_at AT TIME ZONE 'Africa/Lagos', 'Dy DD Mon HH24:MI'), to_char(o.ends_at AT TIME ZONE 'Africa/Lagos', 'HH24:MI'))
      FROM assessment.cbt_sitting s
      JOIN assessment.cbt_seat y ON y.candidate_id = p_candidate
      JOIN assessment.cbt_sitting o ON o.id = y.sitting_id
      JOIN assessment.cbt_exam oe ON oe.id = o.exam_id
      LEFT JOIN jupeb.subject js ON js.id = oe.jupeb_subject_id
     WHERE s.id = p_sitting AND o.exam_id <> s.exam_id AND oe.state <> 'CANCELLED' AND o.starts_at < s.ends_at AND o.ends_at > s.starts_at
     ORDER BY o.starts_at LIMIT 1
$$;

/* every clash an examination's seats have: the candidate, their sitting here and the other examination's sitting at the same time */
CREATE OR REPLACE FUNCTION assessment.cbt_seat_clashes(p_exam uuid)
RETURNS TABLE (candidate_id uuid, number text, surname text, other_names text, sitting_id uuid, sitting text, seat_no int, starts_at timestamptz, ends_at timestamptz,
               other_exam_id uuid, other_reference text, other_course text, other_title text, other_sitting text, other_venue text, other_starts_at timestamptz, other_ends_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT x.candidate_id, coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no), coalesce(st.surname, upper(ja.surname)),
           coalesce(st.other_names, ja.first_name || coalesce(' ' || ja.middle_name, '')),
           s.id, s.label, x.seat_no, s.starts_at, s.ends_at,
           oe.id, oe.reference, coalesce(oe.course_code, js.code), oe.title, o.label, o.venue, o.starts_at, o.ends_at
      FROM assessment.cbt_seat x
      JOIN assessment.cbt_sitting s ON s.id = x.sitting_id
      JOIN assessment.cbt_seat y ON y.candidate_id = x.candidate_id AND y.exam_id <> x.exam_id
      JOIN assessment.cbt_sitting o ON o.id = y.sitting_id AND o.starts_at < s.ends_at AND o.ends_at > s.starts_at
      JOIN assessment.cbt_exam oe ON oe.id = o.exam_id AND oe.state <> 'CANCELLED'
      LEFT JOIN jupeb.subject js ON js.id = oe.jupeb_subject_id
      LEFT JOIN people.student st ON st.id = x.candidate_id
      LEFT JOIN jupeb.application ja ON st.id IS NULL AND ja.id = x.candidate_id
     WHERE x.exam_id = p_exam
     ORDER BY s.starts_at, x.seat_no
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_seat_candidate(p_exam uuid, p_candidate uuid, p_sitting uuid)
RETURNS assessment.cbt_seat LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s assessment.cbt_sitting; x assessment.cbt_seat; v_clash text;
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
    -- V376: never two sittings at the same time
    v_clash := assessment.cbt_seat_clash(p_candidate, s.id);
    IF v_clash IS NOT NULL THEN
        RAISE EXCEPTION 'CBT_SEAT_CLASH: the candidate is seated at the same time in %', v_clash USING ERRCODE = '23514',
            HINT = 'Choose another sitting, or move them in the other examination first.';
    END IF;
    DELETE FROM assessment.cbt_seat WHERE exam_id = p_exam AND candidate_id = p_candidate;
    INSERT INTO assessment.cbt_seat (exam_id, sitting_id, candidate_id, seat_no, assigned_by)
    VALUES (p_exam, s.id, p_candidate, (SELECT coalesce(max(y.seat_no), 0) + 1 FROM assessment.cbt_seat y WHERE y.sitting_id = s.id), who)
    RETURNING * INTO x;
    RETURN x;
END $$;

DROP FUNCTION assessment.cbt_seat_all(uuid, text);
CREATE FUNCTION assessment.cbt_seat_all(p_exam uuid, p_order text)
RETURNS TABLE (seated int, unseated int, clashed int) LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.cbt_exam; c record; v_sid uuid; n int := 0; v_left int := 0;
        v_clashed int := 0; v_room boolean;
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
        -- V376: the first sitting with a free seat that does not clash with another examination's sitting of the candidate
        SELECT s.id INTO v_sid FROM assessment.cbt_sitting s
         WHERE s.exam_id = p_exam AND (SELECT count(*) FROM assessment.cbt_seat x WHERE x.sitting_id = s.id) < s.capacity
           AND assessment.cbt_seat_clash(c.student_id, s.id) IS NULL
         ORDER BY s.starts_at, s.label LIMIT 1;
        IF v_sid IS NULL THEN
            v_room := EXISTS (SELECT 1 FROM assessment.cbt_sitting s WHERE s.exam_id = p_exam AND (SELECT count(*) FROM assessment.cbt_seat x WHERE x.sitting_id = s.id) < s.capacity);
            IF v_room THEN v_clashed := v_clashed + 1; ELSE v_left := v_left + 1; END IF;
            CONTINUE;
        END IF;
        INSERT INTO assessment.cbt_seat (exam_id, sitting_id, candidate_id, seat_no, assigned_by)
        VALUES (p_exam, v_sid, c.student_id, (SELECT coalesce(max(x.seat_no), 0) + 1 FROM assessment.cbt_seat x WHERE x.sitting_id = v_sid), who);
        n := n + 1;
    END LOOP;
    RETURN QUERY SELECT n, v_left + v_clashed, v_clashed;
END $$;

COMMIT;
