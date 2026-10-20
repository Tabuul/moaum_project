-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V587 — Bulk inter-departmental transfer, on the programme swap
--
--   Students who moved from one department to another — approved by the Senate, recorded on paper or in the old portal — are
--   recorded on the portal many at a time, from a spreadsheet, without a second system: each row becomes a programme swap (V578,
--   kind ACADEMIC_TRANSFER), so the move is checked, prepared by one officer, decided by another, kept in the programme history
--   and told to the student exactly as a single swap is.
--     · people.transfer_template(faculty, department, programme, level): the department's students as they stand — the
--       template is filled in, never typed from nothing;
--     · people.transfer_upload_check(rows, session): each row matched to its student by the matriculation number (a former
--       number kept by a correction too, V579) or the JAMB number — never by the name, which is only compared — and checked:
--       the OLD faculty, department, programme and level it states against the student's CURRENT record (SOURCE PROGRAMME
--       MISMATCH otherwise, never silently put right), the NEW programme in the NEW department in the NEW faculty, the new level
--       among the programme's own, a lower level only with the row's reason, the same student twice in the file, and every
--       check of the programme swap (people.programme_swap_check: a record not live, a transfer or swap under way, a change
--       requested at admission, the same placement, a category crossed); the swap's review points come with it;
--     · people.prepare_transfer_batch: the rows checked again, a batch IDT/YYYY/NNNNNN (people.transfer_batch, every row kept
--       with its result in people.transfer_batch_row), and a swap prepared for each valid row under the batch — refused while
--       any row is invalid unless the officer asks, in so many words, for the valid rows alone; nothing on any student changes
--       until another officer decides the batch (the swap screens' batch decision);
--     · people.transfer_batches and people.transfer_batch_rows: the batches and each row with its swap as it stands.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V587: bulk inter-departmental transfer, on the programme swap', true);

-- ── 1 · the batch and its rows ──────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.transfer_batch (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref              text NOT NULL UNIQUE CHECK (ref ~ '^IDT/[0-9]{4}/[0-9]{6}$'),
    effective_session text NOT NULL,
    filename         text NULL,
    reason           text NOT NULL CHECK (length(btrim(reason)) >= 10),
    approval_ref     text NULL,
    partial          boolean NOT NULL DEFAULT false,
    total            int NOT NULL DEFAULT 0,
    prepared         int NOT NULL DEFAULT 0,
    skipped          int NOT NULL DEFAULT 0,
    prepared_by      uuid NOT NULL,
    prepared_office  text NOT NULL,
    prepared_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_transfer_batch_at ON people.transfer_batch (prepared_at DESC);
SELECT audit.attach('people.transfer_batch');
COMMENT ON TABLE people.transfer_batch IS
  'V587: a bulk inter-departmental transfer (IDT/YYYY/NNNNNN) — the file, the session, the reason, how many rows, prepared as programme swaps and skipped; the swaps carry its id as their batch and are decided as one by another officer.';

CREATE TABLE people.transfer_batch_row (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id      uuid NOT NULL REFERENCES people.transfer_batch (id) ON DELETE CASCADE,
    row_no        int NOT NULL,
    student_id    uuid NULL REFERENCES people.student (id) ON DELETE CASCADE,
    uploaded      jsonb NOT NULL,
    status        text NOT NULL CHECK (status IN ('PREPARED', 'SKIPPED', 'INVALID')),
    messages      jsonb NOT NULL DEFAULT '[]',
    swap_id       uuid NULL REFERENCES people.programme_swap (id) ON DELETE SET NULL,
    UNIQUE (batch_id, row_no)
);
CREATE INDEX ix_transfer_batch_row_batch ON people.transfer_batch_row (batch_id, row_no);
CREATE INDEX ix_transfer_batch_row_student ON people.transfer_batch_row (student_id) WHERE student_id IS NOT NULL;
SELECT audit.attach('people.transfer_batch_row');
COMMENT ON TABLE people.transfer_batch_row IS
  'V587: each row of a bulk transfer as uploaded, the student it named, and what became of it — PREPARED (its programme swap), SKIPPED (valid when checked, refused when prepared, with why) or INVALID (left out, with why).';

-- ── 2 · the template: a department's students as they stand ─────────────────────────────────────────────────────────────
CREATE FUNCTION people.transfer_template(p_faculty text, p_dept text, p_programme text, p_level int)
RETURNS TABLE (matric_no text, jamb_reg_no text, student text, faculty_code text, dept_code text, programme_code text, programme text, current_level int, status text)
LANGUAGE sql STABLE AS $fn$
    SELECT s.matric_no, s.jamb_reg_no, s.surname || ', ' || s.other_names, p.faculty_code, p.dept_code, p.code, p.name, s.current_level, s.status
      FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
     WHERE s.duplicate_of IS NULL AND s.status IN ('ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT', 'ADMITTED')
       AND (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_dept IS NULL OR p.dept_code = p_dept)
       AND (p_programme IS NULL OR p.code = p_programme) AND (p_level IS NULL OR s.current_level = p_level)
       AND (p_faculty IS NOT NULL OR p_dept IS NOT NULL OR p_programme IS NOT NULL)
     ORDER BY p.name, s.current_level, s.surname, s.other_names
     LIMIT 5000
$fn$;

-- ── 3 · the rows checked ────────────────────────────────────────────────────────────────────────────────────────────────
/* a cell of a row by any of the names a template column may carry */
CREATE FUNCTION people.transfer_cell(r jsonb, VARIADIC keys text[])
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT nullif(btrim(r ->> k), '') FROM unnest(keys) WITH ORDINALITY u(k, o) WHERE nullif(btrim(r ->> k), '') IS NOT NULL ORDER BY o LIMIT 1
$fn$;

CREATE FUNCTION people.transfer_upload_check(p_rows jsonb, p_session text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE r record; v_out jsonb := '[]'; v_msgs jsonb; v_warn jsonb; v_no text; v_jamb text; s record; v_matched text; v_new_prog text; v_new_dept text;
        v_new_fac text; v_new_level int; v_old_level int; v_reason text; t record; chk jsonb; v_status text; v_name text;
        v_session text;
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RETURN '[]'; END IF;
    -- the same student twice in one file: every row of theirs is refused
    FOR r IN SELECT x.value AS row, x.ordinality::int AS n FROM jsonb_array_elements(p_rows) WITH ORDINALITY x LOOP
        v_msgs := '[]'; v_warn := '[]'; v_matched := NULL;
        v_no := upper(regexp_replace(coalesce(people.transfer_cell(r.row, 'matric_no', 'matricNo', 'Student Matriculation Number', 'Matriculation Number', 'Matric No'), ''), '\s+', '', 'g'));
        v_jamb := upper(btrim(coalesce(people.transfer_cell(r.row, 'jamb_reg_no', 'jambRegNo', 'JAMB Number', 'JAMB'), '')));
        v_name := people.transfer_cell(r.row, 'student', 'Student Name', 'Name');
        v_session := coalesce(people.transfer_cell(r.row, 'effective_session', 'Effective Session'), p_session);
        -- the student: the matriculation number, a former one kept by a correction, the JAMB number — never the name
        SELECT x.id, x.surname, x.other_names, x.matric_no, x.current_level, x.programme_code, p.dept_code, p.faculty_code INTO s
          FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
         WHERE x.duplicate_of IS NULL AND v_no <> '' AND upper(x.matric_no) = v_no;
        IF s.id IS NOT NULL THEN v_matched := 'MATRIC'; END IF;
        IF s.id IS NULL AND v_no <> '' THEN
            SELECT x.id, x.surname, x.other_names, x.matric_no, x.current_level, x.programme_code, p.dept_code, p.faculty_code INTO s
              FROM people.matric_alias a JOIN people.student x ON x.id = a.student_id LEFT JOIN ref.programme p ON p.code = x.programme_code
             WHERE upper(a.old_no) = v_no AND a.ended_at IS NULL;
            IF s.id IS NOT NULL THEN
                v_matched := 'FORMER_MATRIC';
                v_warn := v_warn || jsonb_build_object('code', 'FORMER_MATRIC', 'text', v_no || ' was corrected to ' || s.matric_no || '; the row is read as that student');
            END IF;
        END IF;
        IF s.id IS NULL AND v_jamb <> '' THEN
            SELECT x.id, x.surname, x.other_names, x.matric_no, x.current_level, x.programme_code, p.dept_code, p.faculty_code INTO s
              FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
             WHERE x.duplicate_of IS NULL AND upper(x.jamb_reg_no) = v_jamb LIMIT 1;
            IF s.id IS NOT NULL THEN v_matched := 'JAMB'; END IF;
        END IF;
        IF s.id IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'STUDENT_NOT_FOUND', 'text', 'No student holds the matriculation or JAMB number given');
        ELSE
            IF v_name IS NOT NULL AND position(upper(btrim(s.surname)) IN upper(v_name)) = 0 THEN
                v_warn := v_warn || jsonb_build_object('code', 'NAME_DIFFERS', 'text', 'The name given (' || v_name || ') does not carry the surname on the record (' || s.surname || ')');
            END IF;
            -- the OLD placement stated against the CURRENT record: never silently put right
            IF upper(coalesce(people.transfer_cell(r.row, 'old_programme', 'Old Programme Code', 'Old Programme'), '')) IS DISTINCT FROM upper(coalesce(s.programme_code, ''))
               OR upper(coalesce(people.transfer_cell(r.row, 'old_dept', 'Old Department Code', 'Old Department'), '')) IS DISTINCT FROM upper(coalesce(s.dept_code, ''))
               OR upper(coalesce(people.transfer_cell(r.row, 'old_faculty', 'Old Faculty Code', 'Old Faculty'), '')) IS DISTINCT FROM upper(coalesce(s.faculty_code, '')) THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'SOURCE_PROGRAMME_MISMATCH', 'text',
                    'SOURCE PROGRAMME MISMATCH: the file says ' || coalesce(people.transfer_cell(r.row, 'old_faculty', 'Old Faculty Code', 'Old Faculty'), '—') || ' / '
                    || coalesce(people.transfer_cell(r.row, 'old_dept', 'Old Department Code', 'Old Department'), '—') || ' / '
                    || coalesce(people.transfer_cell(r.row, 'old_programme', 'Old Programme Code', 'Old Programme'), '—')
                    || '; the record says ' || coalesce(s.faculty_code, '—') || ' / ' || coalesce(s.dept_code, '—') || ' / ' || coalesce(s.programme_code, '—'));
            END IF;
            BEGIN
                v_old_level := nullif(regexp_replace(coalesce(people.transfer_cell(r.row, 'old_level', 'Old Level'), ''), '[^0-9]', '', 'g'), '')::int;
            EXCEPTION WHEN OTHERS THEN v_old_level := NULL; END;
            IF v_old_level IS DISTINCT FROM s.current_level THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'SOURCE_LEVEL_MISMATCH', 'text',
                    'The file says ' || coalesce(v_old_level::text, 'no level') || ' Level; the record says ' || coalesce(s.current_level::text, 'none'));
            END IF;
        END IF;
        -- the NEW placement: the programme in the department in the faculty, a level of its own
        v_new_prog := upper(coalesce(people.transfer_cell(r.row, 'new_programme', 'New Programme Code', 'New Programme'), ''));
        v_new_dept := upper(coalesce(people.transfer_cell(r.row, 'new_dept', 'New Department Code', 'New Department'), ''));
        v_new_fac := upper(coalesce(people.transfer_cell(r.row, 'new_faculty', 'New Faculty Code', 'New Faculty'), ''));
        BEGIN
            v_new_level := nullif(regexp_replace(coalesce(people.transfer_cell(r.row, 'new_level', 'New Level'), ''), '[^0-9]', '', 'g'), '')::int;
        EXCEPTION WHEN OTHERS THEN v_new_level := NULL; END;
        SELECT p.code, p.name, p.dept_code, p.faculty_code, d.faculty_code AS dept_faculty INTO t
          FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = v_new_prog;
        IF v_new_prog = '' THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_MISSING', 'text', 'Give the new programme code');
        ELSIF t.code IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_UNKNOWN', 'text', v_new_prog || ' is not a programme on the register (no programme is created by an upload)');
        ELSE
            IF v_new_dept IS DISTINCT FROM upper(coalesce(t.dept_code, '')) THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_DEPARTMENT', 'text', t.name || ' belongs to department ' || coalesce(t.dept_code, '—') || ', not ' || coalesce(nullif(v_new_dept, ''), '—'));
            END IF;
            IF v_new_fac IS DISTINCT FROM upper(coalesce(t.faculty_code, '')) OR upper(coalesce(t.dept_faculty, t.faculty_code, '')) IS DISTINCT FROM upper(coalesce(t.faculty_code, '')) THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_FACULTY', 'text', 'Department ' || coalesce(t.dept_code, '—') || ' belongs to faculty ' || coalesce(t.faculty_code, '—') || ', not ' || coalesce(nullif(v_new_fac, ''), '—'));
            END IF;
        END IF;
        IF v_new_level IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_LEVEL', 'text', 'Give the new level');
        END IF;
        v_reason := people.transfer_cell(r.row, 'reason', 'Reason');
        IF s.id IS NOT NULL AND v_new_level IS NOT NULL AND s.current_level IS NOT NULL AND v_new_level < s.current_level THEN
            IF v_reason IS NULL OR length(v_reason) < 10 THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'LEVEL_REDUCED', 'text', 'The level goes down from ' || s.current_level || ' to ' || v_new_level || '; the row gives the reason (ten characters or more)');
            ELSE
                v_warn := v_warn || jsonb_build_object('code', 'LEVEL_REDUCED', 'text', 'The level goes down from ' || s.current_level || ' to ' || v_new_level || ': ' || v_reason);
            END IF;
        END IF;
        -- every check of the programme swap, and its review points
        IF s.id IS NOT NULL AND t.code IS NOT NULL AND v_new_level IS NOT NULL THEN
            chk := people.programme_swap_check(s.id, t.code, v_new_level, v_session, NULL);
            SELECT v_msgs || coalesce(jsonb_agg(jsonb_build_object('code', split_part(x, ':', 1), 'text', btrim(substr(x, position(':' IN x) + 1)))), '[]')
              INTO v_msgs FROM jsonb_array_elements_text(chk->'refusals') x;
            v_warn := v_warn || coalesce(chk->'warnings', '[]');
        END IF;
        v_status := CASE WHEN jsonb_array_length(v_msgs) > 0 THEN 'INVALID' WHEN jsonb_array_length(v_warn) > 0 THEN 'WARNING' ELSE 'VALID' END;
        v_out := v_out || jsonb_build_array(jsonb_build_object(
            'row', r.n, 'status', v_status, 'studentId', s.id, 'matchedBy', v_matched,
            'student', CASE WHEN s.id IS NOT NULL THEN s.surname || ', ' || s.other_names END, 'matricNo', s.matric_no,
            'current', CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('faculty', s.faculty_code, 'dept', s.dept_code, 'programme', s.programme_code, 'level', s.current_level) END,
            'uploadedOld', jsonb_build_object('faculty', people.transfer_cell(r.row, 'old_faculty', 'Old Faculty Code', 'Old Faculty'),
                                              'dept', people.transfer_cell(r.row, 'old_dept', 'Old Department Code', 'Old Department'),
                                              'programme', people.transfer_cell(r.row, 'old_programme', 'Old Programme Code', 'Old Programme'), 'level', v_old_level),
            'new', jsonb_build_object('faculty', nullif(v_new_fac, ''), 'dept', nullif(v_new_dept, ''), 'programme', nullif(v_new_prog, ''), 'programmeName', t.name, 'level', v_new_level),
            'transferType', CASE WHEN t.code IS NULL OR s.id IS NULL THEN NULL WHEN t.faculty_code IS DISTINCT FROM s.faculty_code THEN 'INTER_FACULTY_TRANSFER' ELSE 'INTER_DEPARTMENTAL_TRANSFER' END,
            'session', v_session, 'reason', v_reason, 'problems', v_msgs, 'warnings', v_warn));
    END LOOP;
    -- the same student on two rows or more: every row of theirs refused, the rows named (which one is meant is the officer's to say)
    SELECT coalesce(jsonb_agg(CASE WHEN d.n > 1
                    THEN o.value || jsonb_build_object('status', 'INVALID', 'problems', (o.value->'problems') || jsonb_build_array(jsonb_build_object(
                         'code', 'DUPLICATE_ROW', 'text', 'The student is on rows ' || d.rows || ' of the file; keep one row')))
                    ELSE o.value END ORDER BY (o.value->>'row')::int), '[]')
      INTO v_out
      FROM jsonb_array_elements(v_out) o
      LEFT JOIN (SELECT x->>'studentId' AS sid, count(*) AS n, string_agg(x->>'row', ', ' ORDER BY (x->>'row')::int) AS rows
                   FROM jsonb_array_elements(v_out) x WHERE x->>'studentId' IS NOT NULL GROUP BY 1) d ON d.sid = o.value->>'studentId';
    RETURN v_out;
END $fn$;
COMMENT ON FUNCTION people.transfer_upload_check(jsonb, text) IS
  'V587: each row of a bulk transfer checked — its student by the matriculation number (a former one too) or the JAMB number, the old placement it states against the current record (SOURCE PROGRAMME MISMATCH), the new programme in its department and faculty, the new level, a lower level''s reason, the student twice in the file, and every check of the programme swap; VALID, WARNING (review points) or INVALID (problems).';

-- ── 4 · the batch prepared ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.prepare_transfer_batch(p_rows jsonb, p_session text, p_reason text, p_approval_ref text, p_filename text, p_partial boolean)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_checked jsonb; v_bad int; v_id uuid := gen_random_uuid(); v_ref text; x jsonb; v_swap uuid; v_prepared int := 0; v_skipped int := 0; v_msg text;
        v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'); v_rows jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'TRANSFER_BATCH_ACTOR: a bulk transfer is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_OFFICE: a bulk transfer is prepared by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_REASON: say why these students are transferred (the Senate''s approval, the memo), ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_EMPTY: the file has no rows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 1000 THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_TOO_MANY: up to 1,000 rows at a time (% given); split the file', jsonb_array_length(p_rows) USING ERRCODE = '23514';
    END IF;
    -- checked again now, the final word before anything is written
    v_checked := people.transfer_upload_check(p_rows, p_session);
    v_bad := (SELECT count(*) FROM jsonb_array_elements(v_checked) c WHERE c->>'status' = 'INVALID');
    IF v_bad > 0 AND NOT coalesce(p_partial, false) THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_INVALID: % of the % rows are invalid; correct them and upload the file again, or prepare the valid rows alone', v_bad, jsonb_array_length(p_rows)
            USING ERRCODE = '23514';
    END IF;
    IF v_bad = jsonb_array_length(p_rows) THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_NONE_VALID: none of the % rows is valid', v_bad USING ERRCODE = '23514';
    END IF;
    v_ref := 'IDT/' || v_year || '/' || lpad(platform.next_number('INTER_DEPARTMENTAL_TRANSFER', 'UNIVERSITY', v_year)::text, 6, '0');
    INSERT INTO people.transfer_batch (id, ref, effective_session, filename, reason, approval_ref, partial, total, prepared_by, prepared_office)
    VALUES (v_id, v_ref, coalesce(nullif(btrim(p_session), ''), policy.university_current_session()), nullif(btrim(coalesce(p_filename, '')), ''), btrim(p_reason),
            nullif(btrim(coalesce(p_approval_ref, '')), ''), v_bad > 0, jsonb_array_length(p_rows), who, office);
    v_rows := p_rows;
    FOR x IN SELECT c.value FROM jsonb_array_elements(v_checked) c ORDER BY (c.value->>'row')::int LOOP
        IF x->>'status' = 'INVALID' THEN
            INSERT INTO people.transfer_batch_row (batch_id, row_no, student_id, uploaded, status, messages)
            VALUES (v_id, (x->>'row')::int, (x->>'studentId')::uuid, v_rows -> ((x->>'row')::int - 1), 'INVALID', x->'problems');
            CONTINUE;
        END IF;
        BEGIN
            v_swap := people.prepare_programme_swap((x->>'studentId')::uuid, x->'new'->>'programme', (x->'new'->>'level')::int, x->>'session', 'ACADEMIC_TRANSFER',
                btrim(p_reason) || ' (' || v_ref || CASE WHEN x->>'reason' IS NOT NULL THEN ': ' || (x->>'reason') ELSE '' END || ')', v_id);
            INSERT INTO people.transfer_batch_row (batch_id, row_no, student_id, uploaded, status, messages, swap_id)
            VALUES (v_id, (x->>'row')::int, (x->>'studentId')::uuid, v_rows -> ((x->>'row')::int - 1), 'PREPARED', x->'warnings', v_swap);
            v_prepared := v_prepared + 1;
        EXCEPTION WHEN check_violation OR insufficient_privilege OR unique_violation THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            INSERT INTO people.transfer_batch_row (batch_id, row_no, student_id, uploaded, status, messages)
            VALUES (v_id, (x->>'row')::int, (x->>'studentId')::uuid, v_rows -> ((x->>'row')::int - 1), 'SKIPPED',
                    jsonb_build_array(jsonb_build_object('code', split_part(v_msg, ':', 1), 'text', btrim(substr(v_msg, position(':' IN v_msg) + 1)))));
            v_skipped := v_skipped + 1;
        END;
    END LOOP;
    UPDATE people.transfer_batch SET prepared = v_prepared, skipped = v_skipped + v_bad WHERE id = v_id;
    RETURN jsonb_build_object('id', v_id, 'ref', v_ref, 'total', jsonb_array_length(p_rows), 'prepared', v_prepared, 'skipped', v_skipped, 'invalid', v_bad);
END $fn$;
COMMENT ON FUNCTION people.prepare_transfer_batch(jsonb, text, text, text, text, boolean) IS
  'V587: a bulk inter-departmental transfer prepared (IDT/YYYY/NNNNNN) — the rows checked again, a programme swap (ACADEMIC_TRANSFER) prepared under the batch for each valid row, every row kept with its result; refused while a row is invalid unless the valid rows alone are asked for; nothing on a student changes until another officer decides the batch.';

-- ── 5 · reading: the batches, a batch's rows with their swaps ───────────────────────────────────────────────────────────
CREATE FUNCTION people.transfer_batches(p_limit int DEFAULT 200)
RETURNS TABLE (id uuid, ref text, effective_session text, filename text, reason text, approval_ref text, partial boolean, total int, prepared int, skipped int,
               pending bigint, completed bigint, rejected bigint, failed bigint, prepared_by uuid, prepared_by_name text, prepared_office text, prepared_at timestamptz, status text)
LANGUAGE sql STABLE AS $fn$
    SELECT b.id, b.ref, b.effective_session, b.filename, b.reason, b.approval_ref, b.partial, b.total, b.prepared, b.skipped,
           count(*) FILTER (WHERE w.status = 'PENDING_APPROVAL'), count(*) FILTER (WHERE w.status = 'COMPLETED'),
           count(*) FILTER (WHERE w.status = 'REJECTED'), count(*) FILTER (WHERE w.status IN ('FAILED', 'CANCELLED')),
           b.prepared_by, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.prepared_by), b.prepared_office, b.prepared_at,
           CASE WHEN count(w.id) = 0 THEN 'NOTHING_PREPARED'
                WHEN count(*) FILTER (WHERE w.status = 'PENDING_APPROVAL') = count(w.id) THEN 'PENDING_APPROVAL'
                WHEN count(*) FILTER (WHERE w.status = 'PENDING_APPROVAL') > 0 THEN 'PARTLY_DECIDED'
                WHEN count(*) FILTER (WHERE w.status = 'COMPLETED') = count(w.id) AND b.skipped = 0 THEN 'COMPLETED'
                WHEN count(*) FILTER (WHERE w.status = 'COMPLETED') > 0 THEN 'COMPLETED_WITH_EXCEPTIONS'
                WHEN count(*) FILTER (WHERE w.status = 'REJECTED') = count(w.id) THEN 'REJECTED'
                ELSE 'FAILED' END
      FROM people.transfer_batch b LEFT JOIN people.programme_swap w ON w.batch_id = b.id
     GROUP BY b.id
     ORDER BY b.prepared_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 200), 2000))
$fn$;

CREATE FUNCTION people.transfer_batch_rows(p_batch uuid)
RETURNS TABLE (row_no int, status text, messages jsonb, uploaded jsonb, student_id uuid, student text, matric_no text, swap_id uuid, swap_ref text, swap_status text,
               from_programme text, from_level int, to_programme text, to_level int, decided_at timestamptz, failure text)
LANGUAGE sql STABLE AS $fn$
    SELECT r.row_no, r.status, r.messages, r.uploaded, r.student_id, s.surname || ', ' || s.other_names, s.matric_no, r.swap_id, w.swap_ref, w.status,
           w.from_programme, w.from_level, w.to_programme, w.to_level, w.decided_at, w.failure
      FROM people.transfer_batch_row r LEFT JOIN people.student s ON s.id = r.student_id LEFT JOIN people.programme_swap w ON w.id = r.swap_id
     WHERE r.batch_id = p_batch
     ORDER BY r.row_no
$fn$;

GRANT SELECT ON people.transfer_batch, people.transfer_batch_row TO app_auditor, app_reporting;

COMMIT;
