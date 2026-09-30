-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V298 — an O'Level upload is checked for duplicates
--
--   The O'Level results the University uploads for its applicants (Candidate Data → O'Level,
--   JAMB's file, one row per subject) were deduplicated only on their identity as V147 read it:
--   the exam number exactly as written, else the body, year and grades. So the same result
--   written "4250101001" and "4250101 001" was two sittings; a second WAEC result for the same
--   May/June examination of the same year, under another exam number, was simply added — the
--   candidate then had two WAEC sittings of one examination, the sitting count and bonus went
--   wrong and the eligibility engine could read three sittings where two are allowed; the same
--   exam number under two applicants passed unnoticed; and a candidate's result re-sent under
--   the same first row was skipped in silence, even when it had changed.
--
--   Now every sitting an upload carries is checked before it is recorded:
--     · SAME_RESULT — the same examining body and exam number (compared without spaces, dashes
--       or slashes), or the same body, year and series with the same grades, is already on the
--       candidate's record: not recorded again;
--     · SAME_SITTING — the same examining body, year and series (the school's May/June, or the
--       private November/December, GCE) is on record with other grades or another number: one
--       cannot sit the same examination twice, so it is HELD, not recorded, for the Office to
--       keep the result on record or use the uploaded one in its place, with the verification;
--     · NUMBER_ELSEWHERE — the same body and exam number is on another applicant's record in the
--       session: recorded (it is what JAMB sent for this candidate) and flagged OPEN until the
--       Office records its verification.
--   Every finding is kept in admissions.olevel_duplicate with what the upload carried and what it
--   met; the upload's answer counts them. The file's series (ExamSeries) is now kept on the sitting.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V298: O''Level uploads checked for duplicates', true);

-- ── 1 · a sitting's series, and its exam number as it is compared ────────────────────────────
ALTER TABLE admissions.olevel_sitting ADD COLUMN IF NOT EXISTS exam_series text;
ALTER TABLE admissions.olevel_sitting ADD COLUMN IF NOT EXISTS exam_key text
    GENERATED ALWAYS AS (nullif(upper(regexp_replace(coalesce(exam_number, ''), '[^A-Za-z0-9]', '', 'g')), '')) STORED;
CREATE INDEX IF NOT EXISTS ix_ols_exam_key ON admissions.olevel_sitting (session, exam_body, exam_key) WHERE exam_key IS NOT NULL;
COMMENT ON COLUMN admissions.olevel_sitting.exam_key IS 'V298: the exam number as compared — upper case, without spaces, dashes, slashes or dots.';
COMMENT ON COLUMN admissions.olevel_sitting.exam_series IS 'V298: the series as the file gave it (ExamSeries: MAY/JUNE, NOV/DEC …).';

CREATE OR REPLACE FUNCTION admissions.olevel_exam_key(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif(upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')), '');
$$;

CREATE OR REPLACE FUNCTION admissions.olevel_year(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT substring(coalesce(p, '') from '(?:19|20)[0-9]{2}');
$$;

/* the series as a class: EXTERNAL for the private November/December examinations (GCE, "private", "external"), INTERNAL for the
   school's (May/June; NECO's June/July) — from the series when the file gave one, else from the examination's name */
CREATE OR REPLACE FUNCTION admissions.olevel_series_class(p_type text, p_series text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN upper(coalesce(p_series, '')) ~ '(NOV|DEC|PRIVATE|EXTERNAL|GCE)' THEN 'EXTERNAL'
             WHEN btrim(coalesce(p_series, '')) <> '' THEN 'INTERNAL'
             WHEN upper(coalesce(p_type, '')) ~ '(GCE|PRIVATE|EXTERNAL|NOV|DEC)' THEN 'EXTERNAL'
             ELSE 'INTERNAL'
           END;
$$;

/* a recorded sitting's grades as one comparable text: subject=grade, in order */
CREATE OR REPLACE FUNCTION admissions.olevel_grades_sig(p_sitting uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade), '') FROM admissions.olevel_grade g WHERE g.sitting_id = p_sitting;
$$;

/* the same for a sitting as an upload carries it */
CREATE OR REPLACE FUNCTION admissions.olevel_payload_sig(p_sitting jsonb)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(string_agg(x.sg, ',' ORDER BY x.sg), '')
      FROM (SELECT DISTINCT btrim(s ->> 'subject') || '=' || upper(btrim(coalesce(s ->> 'grade', ''))) AS sg
              FROM jsonb_array_elements(coalesce(p_sitting -> 'subjects', '[]'::jsonb)) s
             WHERE nullif(btrim(s ->> 'subject'), '') IS NOT NULL) x;
$$;

-- ── 2 · the findings ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admissions.olevel_duplicate (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session          text NOT NULL,
    jamb_key         text NOT NULL,
    attachment_id    uuid NOT NULL REFERENCES admissions.attachment(id) ON DELETE CASCADE,
    sitting_no       integer NOT NULL,
    kind             text NOT NULL,
    state            text NOT NULL,
    exam_body        text NOT NULL,
    exam_type_raw    text NULL,
    exam_year        text NULL,
    exam_series      text NULL,
    exam_number      text NULL,
    subjects         jsonb NOT NULL DEFAULT '[]'::jsonb,
    other_sitting_id uuid NULL REFERENCES admissions.olevel_sitting(id) ON DELETE SET NULL,
    other_jamb_key   text NULL,
    other_exam_year  text NULL,
    other_exam_number text NULL,
    other_subjects   text NULL,
    detected_at      timestamptz NOT NULL DEFAULT now(),
    decided_at       timestamptz NULL,
    decided_by       uuid NULL,
    decided_office   text NULL,
    note             text NULL,
    used_sitting_id  uuid NULL,
    CONSTRAINT uq_old_finding UNIQUE (attachment_id, sitting_no, kind),
    CONSTRAINT ck_old_kind CHECK (kind IN ('SAME_RESULT', 'SAME_SITTING', 'NUMBER_ELSEWHERE')),
    CONSTRAINT ck_old_state CHECK (state IN ('SKIPPED', 'HELD', 'KEPT', 'USED', 'OPEN', 'VERIFIED')),
    CONSTRAINT ck_old_state_kind CHECK ((kind = 'SAME_RESULT' AND state = 'SKIPPED')
                                     OR (kind = 'SAME_SITTING' AND state IN ('HELD', 'KEPT', 'USED'))
                                     OR (kind = 'NUMBER_ELSEWHERE' AND state IN ('OPEN', 'VERIFIED'))),
    CONSTRAINT ck_old_decided CHECK (state IN ('SKIPPED', 'HELD', 'OPEN') OR (decided_at IS NOT NULL AND nullif(btrim(coalesce(note, '')), '') IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_old_session ON admissions.olevel_duplicate (session, state);
CREATE INDEX IF NOT EXISTS ix_old_candidate ON admissions.olevel_duplicate (session, jamb_key);
CREATE INDEX IF NOT EXISTS ix_old_other ON admissions.olevel_duplicate (session, other_jamb_key) WHERE other_jamb_key IS NOT NULL;
COMMENT ON TABLE admissions.olevel_duplicate IS
  'V298: what an O''Level upload carried that was already on record (SAME_RESULT, not recorded again), a second result for the same examination (SAME_SITTING, held for the Office), or an exam number on another applicant''s record (NUMBER_ELSEWHERE, flagged until verified).';
SELECT audit.attach('admissions.olevel_duplicate');
GRANT SELECT, INSERT, UPDATE ON admissions.olevel_duplicate TO app_admissions;
GRANT SELECT ON admissions.olevel_duplicate TO app_auditor;

CREATE OR REPLACE FUNCTION admissions.olevel_duplicate_note(a admissions.attachment, p_no integer, p_kind text, s jsonb, hit admissions.olevel_sitting)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO admissions.olevel_duplicate (session, jamb_key, attachment_id, sitting_no, kind, state, exam_body, exam_type_raw, exam_year, exam_series, exam_number, subjects,
                                             other_sitting_id, other_jamb_key, other_exam_year, other_exam_number, other_subjects)
    VALUES (a.session, a.jamb_key, a.id, p_no, p_kind,
            CASE p_kind WHEN 'SAME_RESULT' THEN 'SKIPPED' WHEN 'SAME_SITTING' THEN 'HELD' ELSE 'OPEN' END,
            admissions.exam_body(s ->> 'type'), nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''), nullif(btrim(s ->> 'series'), ''),
            nullif(btrim(s ->> 'examNumber'), ''), coalesce(s -> 'subjects', '[]'::jsonb),
            hit.id, hit.jamb_key, hit.exam_year, hit.exam_number, CASE WHEN hit.id IS NULL THEN NULL ELSE admissions.olevel_grades_sig(hit.id) END)
    ON CONFLICT (attachment_id, sitting_no, kind) DO UPDATE
        SET detected_at = now(), other_sitting_id = EXCLUDED.other_sitting_id, other_jamb_key = EXCLUDED.other_jamb_key,
            other_exam_year = EXCLUDED.other_exam_year, other_exam_number = EXCLUDED.other_exam_number, other_subjects = EXCLUDED.other_subjects;
$$;

-- ── 3 · the sittings an upload carries, each checked before it is recorded ──────────────────
/* what a sitting as an upload carries it meets on the candidate's record: SAME_RESULT — the same body and exam number (however written),
   the same examination (body, year, series) with the same grades, or, without a number, the same body, year and grades (V147);
   SAME_SITTING — the same examination with other grades or another number; nothing — a sitting of its own */
CREATE OR REPLACE FUNCTION admissions.olevel_match(p_session text, p_jamb_key text, s jsonb)
RETURNS TABLE (kind text, sitting_id uuid)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_body text := admissions.exam_body(s ->> 'type'); v_year text := admissions.olevel_year(s ->> 'year');
        v_class text := admissions.olevel_series_class(s ->> 'type', s ->> 'series'); v_key text := admissions.olevel_exam_key(s ->> 'examNumber');
        v_grades text := admissions.olevel_payload_sig(s); hit uuid;
BEGIN
    IF v_key IS NOT NULL THEN
        SELECT st.id INTO hit FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = p_jamb_key AND st.exam_body = v_body AND st.exam_key = v_key
         ORDER BY st.ord LIMIT 1;
        IF hit IS NOT NULL THEN RETURN QUERY SELECT 'SAME_RESULT'::text, hit; RETURN; END IF;
    END IF;
    IF v_year IS NOT NULL AND v_body <> 'OTHER' THEN
        SELECT st.id INTO hit FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = p_jamb_key AND st.exam_body = v_body
           AND admissions.olevel_year(st.exam_year) = v_year
           AND admissions.olevel_series_class(st.exam_type_raw, st.exam_series) = v_class
         ORDER BY st.ord LIMIT 1;
        IF hit IS NOT NULL THEN
            RETURN QUERY SELECT CASE WHEN admissions.olevel_grades_sig(hit) = v_grades THEN 'SAME_RESULT' ELSE 'SAME_SITTING' END::text, hit;
            RETURN;
        END IF;
    END IF;
    IF v_key IS NULL THEN
        SELECT st.id INTO hit FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = p_jamb_key AND st.exam_key IS NULL AND st.exam_body = v_body
           AND coalesce(st.exam_year, '') = coalesce(nullif(btrim(s ->> 'year'), ''), '')
           AND admissions.olevel_grades_sig(st.id) = v_grades
         ORDER BY st.ord LIMIT 1;
        IF hit IS NOT NULL THEN RETURN QUERY SELECT 'SAME_RESULT'::text, hit; RETURN; END IF;
    END IF;
    RETURN;
END $$;

/* an upload that brings nothing new: every sitting it carries is already on the candidate's record as the same result */
CREATE OR REPLACE FUNCTION admissions.olevel_payload_known(p_session text, p_jamb_key text, p_payload jsonb)
RETURNS boolean LANGUAGE sql STABLE AS $$
    WITH ss AS (
        SELECT x FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_payload -> 'sittings') = 'array' THEN p_payload -> 'sittings' ELSE jsonb_build_array(p_payload) END) x
    )
    SELECT nullif(btrim(coalesce(p_jamb_key, '')), '') IS NOT NULL
       AND EXISTS (SELECT 1 FROM ss)
       AND NOT EXISTS (SELECT 1 FROM ss
                        WHERE coalesce((SELECT m.kind FROM admissions.olevel_match(p_session, upper(btrim(p_jamb_key)), ss.x) m), '') <> 'SAME_RESULT');
$$;

CREATE OR REPLACE FUNCTION admissions.olevel_from_attachment(p_attachment uuid)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    a admissions.attachment;
    sittings jsonb;
    s jsonb;
    sub jsonb;
    hit admissions.olevel_sitting;
    v_sitting uuid;
    v_ord int := 0;
    v_no int := 0;
    v_body text; v_key text; v_kind text; v_hit uuid;
BEGIN
    SELECT * INTO a FROM admissions.attachment WHERE id = p_attachment;
    IF NOT FOUND OR a.kind <> 'OLEVEL' OR a.jamb_key IS NULL THEN
        RETURN 0;
    END IF;
    -- read again from the file as it arrived: this attachment's own sittings go first
    DELETE FROM admissions.olevel_grade g USING admissions.olevel_sitting st
     WHERE g.sitting_id = st.id AND st.attachment_id = p_attachment;
    DELETE FROM admissions.olevel_sitting WHERE attachment_id = p_attachment;

    IF jsonb_typeof(a.payload -> 'sittings') = 'array' THEN
        sittings := a.payload -> 'sittings';
    ELSE
        sittings := jsonb_build_array(a.payload);
    END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(sittings) LOOP
        v_no := v_no + 1;
        v_body := admissions.exam_body(s ->> 'type');
        v_key := admissions.olevel_exam_key(s ->> 'examNumber');
        -- 1–3 · the same result already on record (not recorded again), or a second result for the same examination (held)
        v_kind := NULL; v_hit := NULL;
        SELECT m.kind, m.sitting_id INTO v_kind, v_hit FROM admissions.olevel_match(a.session, a.jamb_key, s) m;
        IF v_kind IS NOT NULL THEN
            SELECT st.* INTO hit FROM admissions.olevel_sitting st WHERE st.id = v_hit;
            PERFORM admissions.olevel_duplicate_note(a, v_no, v_kind, s, hit);
            CONTINUE;
        END IF;

        v_ord := v_ord + 1;
        v_sitting := gen_random_uuid();
        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_type_raw, exam_year, exam_number, ord, exam_series)
        VALUES (v_sitting, a.id, a.session, a.jamb_key, v_body,
                nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''), nullif(btrim(s ->> 'examNumber'), ''), v_ord, nullif(btrim(s ->> 'series'), ''));
        FOR sub IN SELECT * FROM jsonb_array_elements(coalesce(s -> 'subjects', '[]'::jsonb)) LOOP
            IF nullif(btrim(sub ->> 'subject'), '') IS NOT NULL THEN
                INSERT INTO admissions.olevel_grade AS og (sitting_id, subject, grade, raw_subject)
                VALUES (v_sitting, btrim(sub ->> 'subject'), upper(btrim(coalesce(sub ->> 'grade', ''))), sub ->> 'raw')
                ON CONFLICT (sitting_id, subject) DO UPDATE
                    SET grade = CASE WHEN admissions.olevel_points(a.session, EXCLUDED.grade)
                                          > admissions.olevel_points(a.session, og.grade)
                                     THEN EXCLUDED.grade ELSE og.grade END;
            END IF;
        END LOOP;
        -- 4 · the same exam number on another applicant's record in the session: recorded, and flagged for verification
        IF v_key IS NOT NULL THEN
            hit := NULL;
            SELECT st.* INTO hit FROM admissions.olevel_sitting st
             WHERE st.session = a.session AND st.exam_body = v_body AND st.exam_key = v_key AND st.jamb_key <> a.jamb_key
             ORDER BY st.jamb_key, st.ord LIMIT 1;
            IF hit.id IS NOT NULL THEN
                PERFORM admissions.olevel_duplicate_note(a, v_no, 'NUMBER_ELSEWHERE', s, hit);
            END IF;
        END IF;
    END LOOP;
    RETURN v_ord;
END $$;
COMMENT ON FUNCTION admissions.olevel_from_attachment(uuid) IS
  'The sittings an O''Level upload carries (V020), each checked before it is recorded (V298): the same result is not recorded again, a second result for one examination is held, an exam number on another applicant''s record is recorded and flagged — every finding in admissions.olevel_duplicate.';

-- ── 4 · the Office's word on a finding ───────────────────────────────────────────────────────
/* KEEP — the result on record stands, the uploaded one is set aside; USE — the uploaded result takes the recorded one's place;
   VERIFIED — an exam number on two applicants' records has been verified with the examining body. The word is noted, always. */
CREATE OR REPLACE FUNCTION admissions.olevel_duplicate_decide(p_id uuid, p_action text, p_note text, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE d admissions.olevel_duplicate; sub jsonb; v_sitting uuid; v_ord int; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_state text;
BEGIN
    SELECT * INTO d FROM admissions.olevel_duplicate WHERE id = p_id FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such finding' USING ERRCODE = '23503'; END IF;
    IF coalesce(p_office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'OLEVEL_DUPLICATE_OFFICE: a duplicate O''Level upload is settled by the Academic Office or the Registrar''s office' USING ERRCODE = '23514';
    END IF;
    IF v_note IS NULL THEN
        RAISE EXCEPTION 'OLEVEL_DUPLICATE_NOTE: say how it was verified — with the examining body, the candidate''s certificate or the result checker' USING ERRCODE = '23514';
    END IF;
    IF upper(coalesce(p_action, '')) IN ('KEEP', 'USE') THEN
        IF d.kind <> 'SAME_SITTING' OR d.state <> 'HELD' THEN
            RAISE EXCEPTION 'OLEVEL_DUPLICATE_DECIDED: this finding is % and is not decided again', lower(d.state) USING ERRCODE = '23514';
        END IF;
        IF upper(p_action) = 'USE' THEN
            -- the result on record goes; the uploaded one is recorded in its place, under the upload it came in
            IF d.other_sitting_id IS NOT NULL THEN
                DELETE FROM admissions.olevel_grade WHERE sitting_id = d.other_sitting_id;
                DELETE FROM admissions.olevel_sitting WHERE id = d.other_sitting_id;
            END IF;
            SELECT coalesce(max(st.ord), 0) + 1 INTO v_ord FROM admissions.olevel_sitting st WHERE st.attachment_id = d.attachment_id;
            v_sitting := gen_random_uuid();
            INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_type_raw, exam_year, exam_number, ord, exam_series)
            VALUES (v_sitting, d.attachment_id, d.session, d.jamb_key, d.exam_body, d.exam_type_raw, d.exam_year, d.exam_number, v_ord, d.exam_series);
            FOR sub IN SELECT * FROM jsonb_array_elements(d.subjects) LOOP
                IF nullif(btrim(sub ->> 'subject'), '') IS NOT NULL THEN
                    INSERT INTO admissions.olevel_grade AS og (sitting_id, subject, grade, raw_subject)
                    VALUES (v_sitting, btrim(sub ->> 'subject'), upper(btrim(coalesce(sub ->> 'grade', ''))), sub ->> 'raw')
                    ON CONFLICT (sitting_id, subject) DO UPDATE
                        SET grade = CASE WHEN admissions.olevel_points(d.session, EXCLUDED.grade) > admissions.olevel_points(d.session, og.grade) THEN EXCLUDED.grade ELSE og.grade END;
                END IF;
            END LOOP;
            v_state := 'USED';
        ELSE
            v_state := 'KEPT';
        END IF;
    ELSIF upper(coalesce(p_action, '')) = 'VERIFIED' THEN
        IF d.kind <> 'NUMBER_ELSEWHERE' OR d.state <> 'OPEN' THEN
            RAISE EXCEPTION 'OLEVEL_DUPLICATE_DECIDED: this finding is % and is not decided again', lower(d.state) USING ERRCODE = '23514';
        END IF;
        v_state := 'VERIFIED';
    ELSE
        RAISE EXCEPTION 'OLEVEL_DUPLICATE_ACTION: keep the result on record, use the uploaded one, or record the verification' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.olevel_duplicate
       SET state = v_state, decided_at = now(), decided_by = p_actor, decided_office = p_office, note = v_note, used_sitting_id = v_sitting
     WHERE id = d.id;
    RETURN v_state;
END $$;

-- ── 5 · the register of findings ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.olevel_duplicates(p_session text)
RETURNS TABLE (id uuid, kind text, state text, jamb_key text, candidate text, programme text, source_name text, sitting_no integer,
               exam_body text, exam_type_raw text, exam_year text, exam_series text, exam_number text, subjects text,
               other_jamb_key text, other_candidate text, other_exam_year text, other_exam_number text, other_subjects text, other_on_record boolean,
               detected_at timestamptz, decided_at timestamptz, decided_office text, decided_by text, note text)
LANGUAGE sql STABLE AS $$
    SELECT d.id, d.kind, d.state, d.jamb_key,
           (SELECT c.surname || ', ' || c.other_names FROM admissions.candidate c WHERE c.session = d.session AND c.jamb_key = d.jamb_key LIMIT 1),
           (SELECT c.programme FROM admissions.candidate c WHERE c.session = d.session AND c.jamb_key = d.jamb_key LIMIT 1),
           at.source_name, d.sitting_no, d.exam_body, d.exam_type_raw, d.exam_year, d.exam_series, d.exam_number,
           (SELECT string_agg(btrim(x ->> 'subject') || ' ' || upper(btrim(coalesce(x ->> 'grade', ''))), ', ' ORDER BY btrim(x ->> 'subject'))
              FROM jsonb_array_elements(d.subjects) x WHERE nullif(btrim(x ->> 'subject'), '') IS NOT NULL),
           d.other_jamb_key,
           (SELECT c.surname || ', ' || c.other_names FROM admissions.candidate c WHERE c.session = d.session AND c.jamb_key = d.other_jamb_key LIMIT 1),
           d.other_exam_year, d.other_exam_number, replace(replace(d.other_subjects, '=', ' '), ',', ', '), d.other_sitting_id IS NOT NULL,
           d.detected_at, d.decided_at, d.decided_office,
           (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = d.decided_by), d.note
      FROM admissions.olevel_duplicate d
      JOIN admissions.attachment at ON at.id = d.attachment_id
     WHERE d.session = p_session
     ORDER BY (d.state IN ('HELD', 'OPEN')) DESC, d.detected_at DESC, d.jamb_key, d.sitting_no;
$$;
COMMENT ON FUNCTION admissions.olevel_duplicates(text) IS
  'V298: the O''Level upload findings of a session — held and open first — with the candidate, what the upload carried and what it met on record.';

COMMIT;
