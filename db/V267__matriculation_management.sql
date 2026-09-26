-- ═══════════════════════════════════════════════════════════════════════════
-- V267 — Matriculation Management: faculty by faculty, prepared before issued
--
--   V263 issues a number the moment the run or the single act asks for one.
--   The Registry's exercise is in two halves and this migration keeps them
--   apart: GENERATING a number is preparation, ISSUING it is the official act.
--     · a BATCH is opened per faculty and session (its reference from the same
--       MAT/YYYY/NNN series as a run, so a batch that issues IS the run);
--     · generation proposes a number per eligible student from the configured
--       rule (V263) and RESERVES the sequence in the series — the series row is
--       locked, so two officers cannot propose the same number, and the old
--       run and single act (next_matric) now pass a reserved number over;
--     · every row is validated, over and over, and a batch with a conflict is
--       not issued; an authorised correction of a proposed number is validated
--       the same way, needs a reason and keeps the previous value;
--     · issuing is one transaction over the READY batch: the number, the
--       history, the series, the status ADMITTED → ACTIVE, the student's
--       sign-in identity (the number in place of the admission number, with
--       the old one on its own history) and the notice — every student or none;
--     · a reserved number a cancelled batch never issued is released; a number
--       once issued is never reused (V263's trigger stands).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V267: matriculation management', true);

-- ── 1 · the batch, its rows, the reservations, the histories ─────────────

CREATE TABLE people.matric_batch (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref             text NOT NULL UNIQUE,
    session         text NOT NULL REFERENCES policy.academic_session(name),
    faculty_code    text NOT NULL REFERENCES ref.faculty(code),
    state           text NOT NULL DEFAULT 'DRAFT',
    prepared_by     uuid NULL,
    prepared_office text NULL,
    prepared_at     timestamptz NOT NULL DEFAULT now(),
    generated_at    timestamptz NULL,
    reviewed_by     uuid NULL,
    reviewed_office text NULL,
    reviewed_at     timestamptz NULL,
    issued_by       uuid NULL,
    issued_office   text NULL,
    issued_at       timestamptz NULL,
    cancelled_by    uuid NULL,
    cancelled_at    timestamptz NULL,
    cancel_reason   text NULL,
    note            text NULL,
    students        int NOT NULL DEFAULT 0,
    valid           int NOT NULL DEFAULT 0,
    conflicts       int NOT NULL DEFAULT 0,
    issued          int NOT NULL DEFAULT 0,
    run_id          uuid NULL REFERENCES people.matriculation_run(id),
    CONSTRAINT ck_mb_state CHECK (state IN ('DRAFT', 'GENERATED', 'READY_FOR_ISSUANCE', 'ISSUED', 'CANCELLED')),
    CONSTRAINT ck_mb_cancel CHECK (state <> 'CANCELLED' OR nullif(btrim(coalesce(cancel_reason, '')), '') IS NOT NULL)
);
CREATE UNIQUE INDEX uq_matric_batch_open ON people.matric_batch (session, faculty_code) WHERE state NOT IN ('ISSUED', 'CANCELLED');
CREATE INDEX ix_matric_batch_session ON people.matric_batch (session, faculty_code);
SELECT audit.attach('people.matric_batch');
COMMENT ON TABLE people.matric_batch IS
    'One matriculation exercise for one faculty and session (V267): DRAFT → GENERATED → READY_FOR_ISSUANCE → ISSUED, or CANCELLED. '
    'Its reference comes from the run series (MAT/YYYY/NNN); a batch that issues is recorded as the run of that reference.';

CREATE TABLE people.matric_batch_row (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id      uuid NOT NULL REFERENCES people.matric_batch(id),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    programme_code text NULL,
    dept_code     text NULL,
    series_code   text NULL REFERENCES people.matric_series(code),
    sequence      bigint NULL,
    proposed_no   text NULL,
    generated_no  text NULL,            -- what the engine proposed, kept when an officer edits
    components    jsonb NULL,
    edited        boolean NOT NULL DEFAULT false,
    previous_no   text NULL,
    edit_reason   text NULL,
    edited_by     uuid NULL,
    edited_at     timestamptz NULL,
    problems      text[] NOT NULL DEFAULT '{}',
    state         text NOT NULL DEFAULT 'PROPOSED',
    drop_reason   text NULL,
    issued_no     text NULL,
    issued_at     timestamptz NULL,
    CONSTRAINT ck_mbr_state CHECK (state IN ('PROPOSED', 'ISSUED', 'DROPPED')),
    UNIQUE (batch_id, student_id)
);
CREATE INDEX ix_mbr_student ON people.matric_batch_row (student_id);
SELECT audit.attach('people.matric_batch_row');

/* the sequences a batch holds while it is prepared: the guard against two batches proposing one number */
CREATE TABLE people.matric_reservation (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    series_code    text NOT NULL REFERENCES people.matric_series(code),
    sequence       bigint NOT NULL,
    matric_no      text NOT NULL,
    batch_id       uuid NOT NULL REFERENCES people.matric_batch(id),
    row_id         uuid NOT NULL REFERENCES people.matric_batch_row(id),
    edited         boolean NOT NULL DEFAULT false,
    reserved_at    timestamptz NOT NULL DEFAULT now(),
    released_at    timestamptz NULL,               -- nothing deletes: a reservation is released, and the row says why
    release_reason text NULL
);
CREATE UNIQUE INDEX uq_mres_sequence ON people.matric_reservation (series_code, sequence) WHERE released_at IS NULL;
CREATE UNIQUE INDEX uq_mres_number ON people.matric_reservation (matric_no) WHERE released_at IS NULL;
CREATE INDEX ix_mres_batch ON people.matric_reservation (batch_id);
SELECT audit.exempt('people.matric_reservation',
    'A working set: the sequence a batch row holds while the batch is prepared. The act is on the batch row, which is attached; the reservation is released when the batch issues or is cancelled.');

/* every correction of a proposed number, written once */
CREATE TABLE people.matric_batch_edit (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id    uuid NOT NULL REFERENCES people.matric_batch(id),
    row_id      uuid NOT NULL REFERENCES people.matric_batch_row(id),
    student_id  uuid NOT NULL REFERENCES people.student(id),
    previous_no text NULL,
    new_no      text NOT NULL,
    reason      text NOT NULL,
    edited_by   uuid NULL,
    office      text NULL,
    edited_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_mbe_reason CHECK (btrim(reason) <> '')
);
SELECT audit.attach('people.matric_batch_edit');

/* the student's sign-in identity, each time it changes: the admission number before, the matriculation number after */
CREATE TABLE people.student_username_change (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id        uuid NOT NULL REFERENCES people.student(id),
    previous_username text NULL,
    new_username      text NOT NULL,
    reason            text NOT NULL,
    changed_by        uuid NULL,
    office            text NULL,
    batch_id          uuid NULL REFERENCES people.matric_batch(id),
    changed_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_suc_student ON people.student_username_change (student_id);
SELECT audit.attach('people.student_username_change');

CREATE OR REPLACE FUNCTION people.matric_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'this matriculation history is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_mbe_once BEFORE UPDATE OR DELETE ON people.matric_batch_edit FOR EACH ROW EXECUTE FUNCTION people.matric_written_once();
CREATE TRIGGER trg_suc_once BEFORE UPDATE OR DELETE ON people.student_username_change FOR EACH ROW EXECUTE FUNCTION people.matric_written_once();

/* the one policy switch: whether the officer who prepared a batch may also issue it */
ALTER TABLE people.matric_format ADD COLUMN IF NOT EXISTS separate_duties boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN people.matric_format.separate_duties IS 'When true, the officer who generated or marked a batch ready may not be the one who issues it (V267).';

-- ── 2 · who is eligible, and why not ─────────────────────────────────────

/* every student of the faculty the exercise concerns: the admitted without a number (eligible or pending, with the reason),
   and those already matriculated for the session; with the open batch's proposal where one stands */
CREATE OR REPLACE FUNCTION people.matric_candidates(p_session text, p_faculty text)
RETURNS TABLE (student_id uuid, admission_no text, surname text, other_names text, programme_code text, programme text, dept_code text, department text,
               faculty_code text, faculty text, entry_session text, status text, matric_no text, matriculated_at timestamptz,
               registered boolean, paid boolean, query_reason text, config_problem text, eligible boolean, reason text,
               batch_id uuid, batch_ref text, batch_state text, row_id uuid, proposed_no text, row_state text, problems text[], edited boolean, series_code text, sequence bigint)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.id, s.admission_no, s.surname, s.other_names, p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department,
               f.code AS faculty_code, f.name AS faculty, s.entry_session, s.status, s.matric_no, s.matriculated_at,
               EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = p_session AND r.status IN ('APPROVED', 'LOCKED')) AS registered,
               coalesce((SELECT fp.paid_in_full FROM finance.position(s.id, p_session) fp), false) AS paid,
               (SELECT q.reason FROM people.faculty_list l JOIN people.faculty_list_query q ON q.list_id = l.id AND q.student_id = s.id AND q.withdrawn_at IS NULL
                 WHERE l.session = p_session AND l.faculty_code = f.code LIMIT 1) AS query_reason,
               (SELECT c.problem FROM people.matric_components(s.id) c) AS config_problem
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
         WHERE f.code = p_faculty
           AND ((s.status = 'ADMITTED' AND s.matric_no IS NULL
                 AND (s.entry_session = p_session OR EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = p_session)))
                OR (s.matric_no IS NOT NULL AND (s.entry_session = p_session
                     OR EXISTS (SELECT 1 FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id WHERE br.student_id = s.id AND b.session = p_session AND br.state = 'ISSUED'))))
    ), judged AS (
        SELECT b.*,
               CASE WHEN b.matric_no IS NOT NULL THEN 'Already matriculated as ' || b.matric_no
                    WHEN b.status <> 'ADMITTED' THEN 'The student is ' || lower(b.status)
                    WHEN b.query_reason IS NOT NULL THEN 'Under query on the faculty list: ' || b.query_reason
                    WHEN NOT b.registered THEN 'No approved course registration for ' || p_session
                    WHEN NOT b.paid THEN 'School fees for ' || p_session || ' not settled'
                    WHEN b.config_problem IS NOT NULL THEN b.config_problem
                    END AS reason
          FROM base b
    )
    SELECT j.id, j.admission_no, j.surname, j.other_names, j.programme_code, j.programme, j.dept_code, j.department, j.faculty_code, j.faculty, j.entry_session,
           j.status, j.matric_no, j.matriculated_at, j.registered, j.paid, j.query_reason, j.config_problem, j.reason IS NULL, j.reason,
           mb.id, mb.ref, mb.state, br.id, br.proposed_no, br.state, br.problems, br.edited, br.series_code, br.sequence
      FROM judged j
      LEFT JOIN people.matric_batch mb ON mb.session = p_session AND mb.faculty_code = j.faculty_code AND mb.state NOT IN ('ISSUED', 'CANCELLED')
      LEFT JOIN people.matric_batch_row br ON br.batch_id = mb.id AND br.student_id = j.id AND br.state <> 'DROPPED'
     ORDER BY j.surname, j.other_names;
$$;

-- ── 3 · the shape and the prefix a number must carry ─────────────────────

CREATE OR REPLACE FUNCTION people.matric_shape_ok(p_no text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_no ~ '^[A-Z]{2,6}[/-][A-Z0-9]{2,6}([/-][A-Z0-9]{2,6})?[/-][0-9]{2}[/-][0-9]{1,8}$';
$$;

/* the student's configured segments without the sequence: what every number of theirs begins with */
CREATE OR REPLACE FUNCTION people.matric_prefix(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, c.yy, NULL) || mf.separator
      FROM people.matric_components(p_student) c CROSS JOIN people.matric_format mf WHERE mf.id = 'UNIVERSITY';
$$;

/* is the number free: not on the register, not in the history, not held by another batch's row */
CREATE OR REPLACE FUNCTION people.matric_number_taken(p_no text, p_series text, p_seq bigint, p_row uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT 'Number already issued to ' || s.surname || ', ' || s.other_names FROM people.student s WHERE s.matric_no = p_no LIMIT 1),
        (SELECT 'Number was issued before (history of ' || h.issued_at::date || ')' FROM people.matric_history h WHERE h.matric_no = p_no OR (h.series_code = p_series AND h.sequence = p_seq) LIMIT 1),
        (SELECT 'Number is reserved by batch ' || b.ref FROM people.matric_reservation r JOIN people.matric_batch b ON b.id = r.batch_id
          WHERE r.released_at IS NULL AND (r.matric_no = p_no OR (r.series_code = p_series AND r.sequence = p_seq)) AND r.row_id IS DISTINCT FROM p_row LIMIT 1));
$$;

-- ── 4 · generation: propose and reserve, the series locked ───────────────

CREATE OR REPLACE FUNCTION people.matric_batch_open(p_session text, p_faculty text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_ref text;
BEGIN
    SELECT id INTO v_id FROM people.matric_batch WHERE session = p_session AND faculty_code = p_faculty AND state NOT IN ('ISSUED', 'CANCELLED') FOR UPDATE;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_faculty) THEN RAISE EXCEPTION 'no such faculty %', p_faculty USING ERRCODE = '23503'; END IF;
    v_ref := 'MAT/' || substr(p_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', p_session)::text, 3, '0');
    INSERT INTO people.matric_batch (ref, session, faculty_code, state, prepared_by, prepared_office) VALUES (v_ref, p_session, p_faculty, 'DRAFT', p_actor, p_office) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

/* propose a number for every eligible student of the faculty (or one programme) not yet on the open batch */
CREATE OR REPLACE FUNCTION people.matric_batch_generate(p_session text, p_faculty text, p_programme text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_batch uuid; cand record; c record; ms people.matric_series; v_seq bigint; v_no text; v_row uuid; v_n int := 0; v_series text;
BEGIN
    v_batch := people.matric_batch_open(p_session, p_faculty, p_actor, p_office);
    -- the series involved are locked in one order, so two officers queue rather than collide
    FOR v_series IN SELECT DISTINCT c2.series_code FROM people.matric_candidates(p_session, p_faculty) x CROSS JOIN LATERAL people.matric_components(x.student_id) c2
                     WHERE x.eligible AND x.row_id IS NULL AND (p_programme IS NULL OR x.programme_code = p_programme) ORDER BY 1 LOOP
        PERFORM 1 FROM people.matric_series WHERE code = v_series FOR UPDATE;
    END LOOP;
    FOR cand IN SELECT * FROM people.matric_candidates(p_session, p_faculty) x
                 WHERE x.eligible AND x.row_id IS NULL AND (p_programme IS NULL OR x.programme_code = p_programme)
                 ORDER BY x.dept_code, x.programme, x.surname, x.other_names LOOP
        SELECT * INTO c FROM people.matric_components(cand.student_id);
        IF c.problem IS NOT NULL THEN CONTINUE; END IF;
        SELECT * INTO ms FROM people.matric_series WHERE code = c.series_code;
        -- the first free sequence past the last issued and the last one the batches hold (edits excepted)
        SELECT greatest(ms.last_issued, coalesce((SELECT max(r.sequence) FROM people.matric_reservation r WHERE r.series_code = ms.code AND NOT r.edited AND r.released_at IS NULL), 0)) INTO v_seq;
        LOOP
            v_seq := v_seq + 1;
            v_no := people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, c.yy, v_seq);
            EXIT WHEN people.matric_number_taken(v_no, c.series_code, v_seq, NULL) IS NULL;
            IF v_seq > ms.last_issued + 1000000 THEN RAISE EXCEPTION 'no free number in series %', c.series_code USING ERRCODE = '23514'; END IF;
        END LOOP;
        INSERT INTO people.matric_batch_row (batch_id, student_id, programme_code, dept_code, series_code, sequence, proposed_no, generated_no, components)
        VALUES (v_batch, cand.student_id, cand.programme_code, cand.dept_code, c.series_code, v_seq, v_no, v_no,
                jsonb_build_object('university', c.university_code, 'faculty', c.faculty_segment, 'programme', c.programme_segment, 'usesCode', c.uses_code,
                                   'year', c.yy, 'sequence', v_seq, 'programmeCode', c.programme_code, 'facultyCode', c.faculty_code))
        ON CONFLICT (batch_id, student_id) DO UPDATE SET state = 'PROPOSED', drop_reason = NULL, series_code = EXCLUDED.series_code, sequence = EXCLUDED.sequence,
                     proposed_no = EXCLUDED.proposed_no, generated_no = EXCLUDED.generated_no, components = EXCLUDED.components, edited = false, previous_no = NULL, edit_reason = NULL
        RETURNING id INTO v_row;
        INSERT INTO people.matric_reservation (series_code, sequence, matric_no, batch_id, row_id) VALUES (c.series_code, v_seq, v_no, v_batch, v_row);
        v_n := v_n + 1;
    END LOOP;
    UPDATE people.matric_batch SET state = CASE WHEN state = 'DRAFT' AND v_n = 0 THEN 'DRAFT' ELSE 'GENERATED' END, generated_at = CASE WHEN v_n > 0 THEN now() ELSE generated_at END,
           reviewed_by = CASE WHEN v_n > 0 THEN NULL ELSE reviewed_by END, reviewed_at = CASE WHEN v_n > 0 THEN NULL ELSE reviewed_at END
     WHERE id = v_batch;
    PERFORM people.matric_batch_validate(v_batch);
    RETURN v_batch;
END $$;

-- ── 5 · validation: every row, every time ────────────────────────────────

CREATE OR REPLACE FUNCTION people.matric_batch_validate(p_batch uuid)
RETURNS TABLE (students int, valid int, conflicts int)
LANGUAGE plpgsql AS $$
DECLARE b people.matric_batch; r record; s people.student; pf text; p text[]; v_taken text; v_reason text; v_fac text;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    FOR r IN SELECT br.* FROM people.matric_batch_row br WHERE br.batch_id = p_batch AND br.state = 'PROPOSED' LOOP
        p := ARRAY[]::text[];
        SELECT * INTO s FROM people.student WHERE id = r.student_id;
        IF s.id IS NULL THEN
            p := p || 'Student no longer exists'::text;
        ELSE
            IF s.matric_no IS NOT NULL THEN p := p || ('Already matriculated as ' || s.matric_no); END IF;
            IF s.status <> 'ADMITTED' THEN p := p || ('The student is ' || lower(s.status) || ', not admitted'); END IF;
            SELECT pr.faculty_code INTO v_fac FROM ref.programme pr WHERE pr.code = s.programme_code;
            IF v_fac IS DISTINCT FROM b.faculty_code THEN p := p || 'The student is not in the batch''s faculty'::text; END IF;
            IF s.programme_code IS DISTINCT FROM r.programme_code THEN p := p || 'The student''s programme changed since the number was proposed'::text; END IF;
            SELECT x.reason INTO v_reason FROM people.matric_candidates(b.session, b.faculty_code) x WHERE x.student_id = s.id;
            IF v_reason IS NOT NULL AND s.matric_no IS NULL AND s.status = 'ADMITTED' THEN p := p || ('Not eligible: ' || v_reason); END IF;
        END IF;
        IF r.proposed_no IS NULL THEN
            p := p || 'No number proposed'::text;
        ELSE
            IF NOT people.matric_shape_ok(r.proposed_no) THEN p := p || 'Number does not match the configured shape'::text; END IF;
            pf := people.matric_prefix(r.student_id);
            IF pf IS NOT NULL AND left(r.proposed_no, length(pf)) <> pf THEN p := p || ('Number does not carry the student''s configured segments (expected ' || pf || '…)'); END IF;
            IF r.sequence IS NULL OR r.sequence <= 0 THEN p := p || 'The sequence is not valid'::text; END IF;
            v_taken := people.matric_number_taken(r.proposed_no, r.series_code, r.sequence, r.id);
            IF v_taken IS NOT NULL THEN p := p || v_taken; END IF;
            IF (SELECT count(*) FROM people.matric_batch_row o WHERE o.batch_id = p_batch AND o.state = 'PROPOSED' AND o.proposed_no = r.proposed_no) > 1 THEN p := p || 'Duplicate within this batch'::text; END IF;
            IF NOT EXISTS (SELECT 1 FROM people.matric_series ms WHERE ms.code = r.series_code AND ms.active) THEN p := p || ('Series ' || coalesce(r.series_code, '?') || ' is not active'); END IF;
        END IF;
        UPDATE people.matric_batch_row SET problems = p WHERE id = r.id;
    END LOOP;
    UPDATE people.matric_batch mb SET
        students = (SELECT count(*) FROM people.matric_batch_row x WHERE x.batch_id = p_batch AND x.state = 'PROPOSED'),
        valid = (SELECT count(*) FROM people.matric_batch_row x WHERE x.batch_id = p_batch AND x.state = 'PROPOSED' AND cardinality(x.problems) = 0),
        conflicts = (SELECT count(*) FROM people.matric_batch_row x WHERE x.batch_id = p_batch AND x.state = 'PROPOSED' AND cardinality(x.problems) > 0)
     WHERE mb.id = p_batch;
    -- a batch marked ready that now carries a conflict goes back to review
    UPDATE people.matric_batch mb2 SET state = 'GENERATED', reviewed_by = NULL, reviewed_at = NULL WHERE mb2.id = p_batch AND mb2.state = 'READY_FOR_ISSUANCE' AND mb2.conflicts > 0;
    RETURN QUERY SELECT mb.students, mb.valid, mb.conflicts FROM people.matric_batch mb WHERE mb.id = p_batch;
END $$;

-- ── 6 · an authorised correction, validated like any other number ────────

CREATE OR REPLACE FUNCTION people.matric_batch_edit_row(p_row uuid, p_new text, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r people.matric_batch_row; b people.matric_batch; v_no text := upper(btrim(coalesce(p_new, ''))); pf text; v_seq bigint; v_taken text; mf people.matric_format;
BEGIN
    SELECT * INTO r FROM people.matric_batch_row WHERE id = p_row FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM people.matric_batch WHERE id = r.batch_id FOR UPDATE;
    IF b.state NOT IN ('GENERATED', 'READY_FOR_ISSUANCE') THEN RAISE EXCEPTION 'a number is corrected on a generated batch, not one that is %', lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF r.state <> 'PROPOSED' THEN RAISE EXCEPTION 'this row is %', lower(r.state) USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a correction of a proposed number carries its reason' USING ERRCODE = '23514'; END IF;
    IF NOT people.matric_shape_ok(v_no) THEN RAISE EXCEPTION '% does not match the configured shape', v_no USING ERRCODE = '23514', HINT = 'MOAU/FACULTY[/PROGRAMME]/YY/SEQUENCE'; END IF;
    pf := people.matric_prefix(r.student_id);
    IF pf IS NULL OR left(v_no, length(pf)) <> pf THEN RAISE EXCEPTION 'the number must carry the student''s configured segments: %…', pf USING ERRCODE = '23514'; END IF;
    SELECT * INTO mf FROM people.matric_format WHERE id = 'UNIVERSITY';
    v_seq := (regexp_match(v_no, '[0-9]+$'))[1]::bigint;
    IF v_seq <= 0 THEN RAISE EXCEPTION 'the sequence must be positive' USING ERRCODE = '23514'; END IF;
    IF v_no = r.proposed_no THEN RETURN; END IF;
    PERFORM 1 FROM people.matric_series WHERE code = r.series_code FOR UPDATE;
    v_taken := people.matric_number_taken(v_no, r.series_code, v_seq, r.id);
    IF v_taken IS NOT NULL THEN RAISE EXCEPTION '%', v_taken USING ERRCODE = '23505'; END IF;
    IF EXISTS (SELECT 1 FROM people.matric_batch_row o WHERE o.batch_id = r.batch_id AND o.id <> r.id AND o.state = 'PROPOSED' AND o.proposed_no = v_no) THEN
        RAISE EXCEPTION '% is already proposed for another student in this batch', v_no USING ERRCODE = '23505';
    END IF;
    UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Corrected to ' || v_no WHERE row_id = r.id AND released_at IS NULL;
    INSERT INTO people.matric_reservation (series_code, sequence, matric_no, batch_id, row_id, edited) VALUES (r.series_code, v_seq, v_no, r.batch_id, r.id, true);
    INSERT INTO people.matric_batch_edit (batch_id, row_id, student_id, previous_no, new_no, reason, edited_by, office)
    VALUES (r.batch_id, r.id, r.student_id, r.proposed_no, v_no, btrim(p_reason), p_actor, p_office);
    UPDATE people.matric_batch_row SET previous_no = r.proposed_no, proposed_no = v_no, sequence = v_seq, edited = true, edit_reason = btrim(p_reason), edited_by = p_actor, edited_at = now(),
           components = coalesce(components, '{}'::jsonb) || jsonb_build_object('sequence', v_seq)
     WHERE id = r.id;
    PERFORM people.matric_batch_validate(r.batch_id);
END $$;

/* a student taken off the batch before issuance: the reservation released, the row kept with the reason */
CREATE OR REPLACE FUNCTION people.matric_batch_drop_row(p_row uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r people.matric_batch_row; b people.matric_batch;
BEGIN
    SELECT * INTO r FROM people.matric_batch_row WHERE id = p_row FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM people.matric_batch WHERE id = r.batch_id;
    IF b.state NOT IN ('GENERATED', 'READY_FOR_ISSUANCE') OR r.state <> 'PROPOSED' THEN RAISE EXCEPTION 'only a proposed row of a generated batch is dropped' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'dropping a student from the batch carries its reason' USING ERRCODE = '23514'; END IF;
    UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Dropped: ' || btrim(p_reason) WHERE row_id = r.id AND released_at IS NULL;
    UPDATE people.matric_batch_row SET state = 'DROPPED', drop_reason = btrim(p_reason) WHERE id = r.id;
    PERFORM people.matric_batch_validate(r.batch_id);
END $$;

-- ── 7 · ready, issue, cancel ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION people.matric_batch_ready(p_batch uuid, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v record; b people.matric_batch;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state NOT IN ('GENERATED', 'READY_FOR_ISSUANCE') THEN RAISE EXCEPTION 'a batch is marked ready once its numbers are generated; this one is %', lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    SELECT * INTO v FROM people.matric_batch_validate(p_batch);
    IF v.students = 0 THEN RAISE EXCEPTION 'the batch has no student on it' USING ERRCODE = '23514'; END IF;
    IF v.conflicts > 0 THEN RAISE EXCEPTION 'cannot mark the batch ready: % record(s) require attention', v.conflicts USING ERRCODE = '23514', HINT = 'Resolve every conflict on the review screen first.'; END IF;
    UPDATE people.matric_batch SET state = 'READY_FOR_ISSUANCE', reviewed_by = p_actor, reviewed_office = p_office, reviewed_at = now() WHERE id = p_batch;
END $$;

/* the official act: one transaction over the ready batch — every student or none */
CREATE OR REPLACE FUNCTION people.matric_batch_issue(p_batch uuid, p_actor uuid, p_office text)
RETURNS TABLE (issued int, username_updates int, run_ref text)
LANGUAGE plpgsql AS $$
DECLARE b people.matric_batch; v record; r record; s people.student; c record; v_taken text; v_n int := 0; v_prev text; mf people.matric_format;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'READY_FOR_ISSUANCE' THEN RAISE EXCEPTION 'only a batch marked READY FOR ISSUANCE is issued; this one is %', lower(replace(b.state, '_', ' ')) USING ERRCODE = '23514', HINT = 'Review the numbers and mark the batch ready first.'; END IF;
    SELECT * INTO mf FROM people.matric_format WHERE id = 'UNIVERSITY';
    IF mf.separate_duties AND p_actor IS NOT NULL AND (b.prepared_by = p_actor OR b.reviewed_by = p_actor) THEN
        RAISE EXCEPTION 'the officer who prepared or reviewed a batch does not issue it: duties are separated' USING ERRCODE = '23514', HINT = 'Another authorised officer issues the batch, or the Registry turns the separation off under Matriculation number format.';
    END IF;
    SELECT * INTO v FROM people.matric_batch_validate(p_batch);
    IF v.conflicts > 0 THEN RAISE EXCEPTION 'cannot issue matriculation numbers: % record(s) require attention', v.conflicts USING ERRCODE = '23514', HINT = 'Resolve every conflict before final issuance; nothing was issued.'; END IF;
    IF v.students = 0 THEN RAISE EXCEPTION 'the batch has no student on it' USING ERRCODE = '23514'; END IF;
    -- the run of this reference, so the register reads the batch like any run
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (b.id, b.ref, b.session, 0);
    FOR r IN SELECT br.* FROM people.matric_batch_row br WHERE br.batch_id = p_batch AND br.state = 'PROPOSED' ORDER BY br.series_code, br.sequence LOOP
        SELECT * INTO s FROM people.student WHERE id = r.student_id FOR UPDATE;
        -- verified again at the moment of issue; any failure rolls the whole batch back
        IF s.matric_no IS NOT NULL THEN RAISE EXCEPTION '% already holds %; nothing was issued', s.surname, s.matric_no USING ERRCODE = '23514'; END IF;
        IF s.status <> 'ADMITTED' THEN RAISE EXCEPTION '% is %, not admitted; nothing was issued', s.surname, lower(s.status) USING ERRCODE = '23514'; END IF;
        v_taken := people.matric_number_taken(r.proposed_no, r.series_code, r.sequence, r.id);
        IF v_taken IS NOT NULL THEN RAISE EXCEPTION '% for %; nothing was issued', v_taken, r.proposed_no USING ERRCODE = '23505'; END IF;
        PERFORM 1 FROM people.matric_series WHERE code = r.series_code FOR UPDATE;
        INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, run_id, issued_by, actor_office, reason)
        VALUES (r.student_id, r.proposed_no, r.series_code, r.sequence, coalesce(r.components, '{}'::jsonb) || jsonb_build_object('batch', b.ref, 'edited', r.edited),
                b.id, p_actor, p_office, 'Matriculation batch ' || b.ref || CASE WHEN r.edited THEN ' (number corrected: ' || coalesce(r.edit_reason, '') || ')' ELSE '' END);
        UPDATE people.matric_series SET last_issued = greatest(last_issued, r.sequence), updated_at = now() WHERE code = r.series_code;
        v_prev := coalesce(s.admission_no, s.jamb_reg_no);
        UPDATE people.student SET matric_no = r.proposed_no, matriculated_at = now(), matriculation_run = b.id, status = 'ACTIVE' WHERE id = s.id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), s.id, s.status, 'ACTIVE', b.ref, current_date, 'Matriculated (batch ' || b.ref || ')');
        INSERT INTO people.student_username_change (student_id, previous_username, new_username, reason, changed_by, office, batch_id)
        VALUES (s.id, v_prev, r.proposed_no, 'Student matriculated', p_actor, p_office, b.id);
        UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Issued' WHERE row_id = r.id AND released_at IS NULL;
        UPDATE people.matric_batch_row SET state = 'ISSUED', issued_no = r.proposed_no, issued_at = now() WHERE id = r.id;
        PERFORM people.matric_tell(s.id, r.proposed_no);
        v_n := v_n + 1;
    END LOOP;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = b.id;
    UPDATE people.matric_batch SET state = 'ISSUED', issued_by = p_actor, issued_office = p_office, issued_at = now(), issued = v_n, run_id = b.id WHERE id = p_batch;
    RETURN QUERY SELECT v_n, v_n, b.ref;
END $$;

/* what is checked after issue: the record as it must now read, row by row */
CREATE OR REPLACE FUNCTION people.matric_batch_verify(p_batch uuid)
RETURNS TABLE (checked int, with_number int, status_active int, history_rows int, username_rows int, unique_numbers int, failed int)
LANGUAGE sql STABLE AS $$
    WITH rows AS (SELECT br.student_id, br.issued_no FROM people.matric_batch_row br WHERE br.batch_id = p_batch AND br.state = 'ISSUED')
    SELECT count(*)::int,
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM people.student s WHERE s.id = r.student_id AND s.matric_no = r.issued_no))::int,
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM people.student s WHERE s.id = r.student_id AND s.status = 'ACTIVE'))::int,
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM people.matric_history h WHERE h.student_id = r.student_id AND h.matric_no = r.issued_no))::int,
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM people.student_username_change u WHERE u.student_id = r.student_id AND u.new_username = r.issued_no))::int,
           count(*) FILTER (WHERE (SELECT count(*) FROM people.student s WHERE s.matric_no = r.issued_no) = 1)::int,
           count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = r.student_id AND s.matric_no = r.issued_no AND s.status = 'ACTIVE')
                               OR NOT EXISTS (SELECT 1 FROM people.matric_history h WHERE h.student_id = r.student_id AND h.matric_no = r.issued_no)
                               OR NOT EXISTS (SELECT 1 FROM people.student_username_change u WHERE u.student_id = r.student_id AND u.new_username = r.issued_no))::int
      FROM rows r;
$$;

CREATE OR REPLACE FUNCTION people.matric_batch_cancel(p_batch uuid, p_reason text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE b people.matric_batch;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state = 'ISSUED' THEN RAISE EXCEPTION 'an issued batch is not cancelled: its numbers are permanent' USING ERRCODE = '23514', HINT = 'A correction of an issued number is a matter for the Registry''s revocation procedure, on the record.'; END IF;
    IF b.state = 'CANCELLED' THEN RETURN; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'cancelling a batch carries its reason' USING ERRCODE = '23514'; END IF;
    -- the reserved numbers were never issued: released, as the numbering policy allows; nothing issued is ever reused
    UPDATE people.matric_reservation SET released_at = now(), release_reason = 'Batch cancelled: ' || btrim(p_reason) WHERE batch_id = p_batch AND released_at IS NULL;
    UPDATE people.matric_batch_row SET state = 'DROPPED', drop_reason = coalesce(drop_reason, 'Batch cancelled: ' || btrim(p_reason)) WHERE batch_id = p_batch AND state = 'PROPOSED';
    UPDATE people.matric_batch SET state = 'CANCELLED', cancelled_by = p_actor, cancelled_at = now(), cancel_reason = btrim(p_reason), students = 0, valid = 0, conflicts = 0 WHERE id = p_batch;
END $$;

-- ── 8 · the overview across faculties, and the old paths made batch-aware ─

CREATE OR REPLACE FUNCTION people.matric_overview(p_session text)
RETURNS TABLE (faculty_code text, faculty text, eligible bigint, pending bigint, already bigint, prepared bigint, valid bigint, conflicts bigint, issued bigint, batch_id uuid, batch_ref text, batch_state text, list_state text)
LANGUAGE sql STABLE AS $$
    SELECT f.code, f.name,
           (SELECT count(*) FROM people.matric_candidates(p_session, f.code) x WHERE x.eligible),
           (SELECT count(*) FROM people.matric_candidates(p_session, f.code) x WHERE NOT x.eligible AND x.matric_no IS NULL),
           (SELECT count(*) FROM people.matric_candidates(p_session, f.code) x WHERE x.matric_no IS NOT NULL),
           coalesce(b.students, 0), coalesce(b.valid, 0), coalesce(b.conflicts, 0),
           (SELECT count(*) FROM people.matric_batch_row br JOIN people.matric_batch bb ON bb.id = br.batch_id WHERE bb.session = p_session AND bb.faculty_code = f.code AND br.state = 'ISSUED'),
           b.id, b.ref, b.state, coalesce(l.state, 'NOT_RETURNED')
      FROM ref.faculty f
      LEFT JOIN people.matric_batch b ON b.session = p_session AND b.faculty_code = f.code AND b.state NOT IN ('ISSUED', 'CANCELLED')
      LEFT JOIN people.faculty_list l ON l.session = p_session AND l.faculty_code = f.code
     ORDER BY f.name;
$$;

/* V263's next number, now passing over a sequence a batch holds */
CREATE OR REPLACE FUNCTION people.next_matric(p_student uuid, p_run uuid, p_reason text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE c record; ms people.matric_series; v_seq bigint; v_no text; v_try int := 0;
BEGIN
    SELECT * INTO c FROM people.matric_components(p_student);
    IF c.problem IS NOT NULL THEN
        RAISE EXCEPTION 'the matriculation number cannot be built: %', c.problem USING ERRCODE = '23514', HINT = 'The Registry configures the faculty, the programme and the series under Matriculation number format.';
    END IF;
    SELECT * INTO ms FROM people.matric_series WHERE code = c.series_code FOR UPDATE;
    IF ms.code IS NULL THEN RAISE EXCEPTION 'no series %', c.series_code USING ERRCODE = '23503'; END IF;
    LOOP
        v_try := v_try + 1;
        v_seq := ms.last_issued + v_try;
        v_no := people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, c.yy, v_seq);
        EXIT WHEN people.matric_number_taken(v_no, c.series_code, v_seq, NULL) IS NULL;
        IF v_try > 100000 THEN RAISE EXCEPTION 'no free number in series % after a hundred thousand tries', c.series_code USING ERRCODE = '23514'; END IF;
    END LOOP;
    UPDATE people.matric_series SET last_issued = v_seq, updated_at = now() WHERE code = ms.code;
    INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, run_id, issued_by, actor_office, reason)
    VALUES (p_student, v_no, c.series_code, v_seq,
            jsonb_build_object('university', c.university_code, 'faculty', c.faculty_segment, 'programme', c.programme_segment, 'usesCode', c.uses_code,
                               'year', c.yy, 'sequence', v_seq, 'programmeCode', c.programme_code, 'facultyCode', c.faculty_code),
            p_run, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), p_reason);
    -- the sign-in identity moves with the number on every path, not only the batch
    INSERT INTO people.student_username_change (student_id, previous_username, new_username, reason, changed_by, office)
    SELECT s.id, coalesce(s.admission_no, s.jamb_reg_no), v_no, coalesce(p_reason, 'Student matriculated'), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), '')
      FROM people.student s WHERE s.id = p_student;
    RETURN v_no;
END $$;

/* the student told: the number, and that it is now their sign-in */
CREATE OR REPLACE FUNCTION people.matric_tell(p_student uuid, p_no text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE reach record;
BEGIN
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Congratulations — you have been officially matriculated',
        'You have been officially matriculated. Your matriculation number is ' || p_no || '. It is permanent and appears on every document the University issues to you.'
        || E'\n\nYour matriculation number is now your portal sign-in username, in place of your admission number. Your password is unchanged.'
        || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', p_student);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your matriculation number', 'MOAUM: you are matriculated. Your matriculation number ' || p_no || ' is now your portal sign-in; your password is unchanged.', 'student', p_student);
END $$;

-- ── 9 · grants ────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON people.matric_batch, people.matric_batch_row, people.matric_reservation TO app_student;
GRANT SELECT, INSERT ON people.matric_batch_edit, people.student_username_change TO app_student;
GRANT SELECT ON people.matric_batch, people.matric_batch_row, people.matric_reservation, people.matric_batch_edit, people.student_username_change TO app_auditor;

COMMIT;
