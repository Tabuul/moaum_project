-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V574 — Duplicate programmes merged into one, with their students
--
--   The postgraduate register upload (V203, V463) creates a programme for every old-portal code it does not know, named from the
--   award and the department alone ("MSC GEOGRAPHY"). The old portal kept one code per option, so one programme arrived under up
--   to eleven codes (175 such codes under 60 names on the live-shaped copy), almost every postgraduate student sits on one of them,
--   and new applicants are admitted to the School's own catalogue (M.Sc. Geography …) — two catalogues side by side, and a few
--   twins inside the catalogue itself (LL.M and Master of Laws, MBA twice …).
--
--   ref.merge_programmes merges a programme into another, pair by pair, by the Registry or the School of Postgraduate Studies with
--   a reason:
--     · every record naming the old code moves to the kept one, as ref.programme_reference classes each column: MOVE (students,
--       applications, transfers asked for, examiners, a course's owner…), MOVE_UNLESS_HELD (a programme's own settings — a course
--       offered to it, its rule, route, specialisations — moved unless the kept programme already holds the same, which stays on
--       the old code with the archived programme), FEES (a session's fee lines moved where the kept programme has none for that
--       session, else ended), KEEP (history: amendments, record moves, old transfers, imports — what was, kept as it was), DERIVED
--       (the academic position, refreshed from the student);
--     · each student moved is recorded in people.record_move (V548) at their own level, and every moved row in
--       ref.programme_merge_row, so a merge is undone from its record (ref.undo_programme_merge);
--     · the old code is kept as an alias of the kept programme (ref.programme_alias) and archived, never deleted: a student, an
--       application, a fee line or a course offer written later with the old code lands on the kept programme
--       (ref.programme_alias_apply), so a later upload from the old portal does not bring the duplicate back.
--   ref.programme_merge_effect shows what a set of merges would do, done and undone; ref.programme_merge_suggestions proposes
--   them: codes of one name and department into the one most students sit on; an older code into the School's catalogue
--   programme of its degree and department where one plainly answers to it; catalogue twins into the one in use.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V574: duplicate programmes merged into one, with their students', true);

-- ── what each programme column does in a merge ──────────────────────────────────────────────────────────────────────────
CREATE TABLE ref.programme_reference (
    tab     text NOT NULL,
    col     text NOT NULL,
    policy  text NOT NULL CHECK (policy IN ('MOVE', 'MOVE_UNLESS_HELD', 'FEES', 'KEEP', 'DERIVED')),
    note    text NULL,
    PRIMARY KEY (tab, col)
);
SELECT audit.attach('ref.programme_reference');
COMMENT ON TABLE ref.programme_reference IS
  'V574: every column that names a programme by its code, and what a merge does with it — MOVE, MOVE_UNLESS_HELD (unless the kept programme holds the same), FEES, KEEP (history), DERIVED (recomputed).';
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('people.student', 'programme_code', 'MOVE', 'the students; each move recorded in people.record_move'),
    ('admissions.pg_application', 'programme_code', 'MOVE', 'postgraduate applications'),
    ('admissions.cce_candidate', 'programme_code', 'MOVE', 'CCE candidates'),
    ('jupeb.application', 'programme_code', 'MOVE', 'the programme a JUPEB applicant aims for'),
    ('people.transfer_application', 'to_programme_code', 'MOVE', 'a transfer asked for into it'),
    ('admissions.programme_change_request', 'to_programme_code', 'MOVE', 'a change of programme asked for into it'),
    ('admissions.prelim_review', 'target_programme', 'MOVE', 'a Preliminary Science student''s target'),
    ('catalogue.course', 'owner_programme', 'MOVE', 'the programme that owns a course'),
    ('extexam.appointment', 'programme_code', 'MOVE', 'an external examiner''s appointment'),
    ('finance.fee_schedule', 'programme_code', 'FEES', 'a session''s fee lines: moved where the kept programme has none for it, else ended'),
    ('catalogue.course_offer', 'programme_code', 'MOVE_UNLESS_HELD', 'a course offered to the programme'),
    ('catalogue.course_offer_specialisation', 'programme_code', 'MOVE_UNLESS_HELD', 'a course offered to a specialisation'),
    ('catalogue.offer_proposal', 'programme_code', 'MOVE_UNLESS_HELD', 'a proposed offer'),
    ('catalogue.offering_teacher', 'programme_code', 'MOVE_UNLESS_HELD', 'who teaches the programme''s class'),
    ('catalogue.programme_specialisation', 'programme_code', 'MOVE_UNLESS_HELD', 'a specialisation; one the kept programme also has takes its students'),
    ('admissions.pg_course', 'programme_code', 'MOVE_UNLESS_HELD', 'a postgraduate course of the programme'),
    ('admissions.programme_rule', 'programme_code', 'MOVE_UNLESS_HELD', 'an admission rule'),
    ('admissions.programme_closed', 'programme_code', 'MOVE_UNLESS_HELD', 'closed for admission'),
    ('admissions.screening_exam_programme', 'programme_code', 'MOVE_UNLESS_HELD', 'screened by an examination'),
    ('admissions.prelim_target', 'programme_code', 'MOVE_UNLESS_HELD', 'a Preliminary Science target'),
    ('admissions.programme_olevel_allowance', 'programme_code', 'MOVE_UNLESS_HELD', 'an O''Level allowance'),
    ('admissions.rule_subject_group', 'programme_code', 'MOVE_UNLESS_HELD', 'a subject group of a rule'),
    ('college.programme_rule', 'programme_code', 'MOVE_UNLESS_HELD', 'a College rule'),
    ('finance.gst_fee', 'programme_code', 'MOVE_UNLESS_HELD', 'a GST fee'),
    ('jupeb.combination_relevance', 'programme_code', 'MOVE_UNLESS_HELD', 'a JUPEB combination''s relevance'),
    ('ref.programme_route', 'programme_code', 'MOVE_UNLESS_HELD', 'a route of study'),
    ('people.academic_position', 'programme_code', 'DERIVED', 'refreshed from the student'),
    ('assessment.amendment', 'programme_code', 'KEEP', 'history'),
    ('catalogue.course_offer_history', 'programme_code', 'KEEP', 'history'),
    ('catalogue.course_owner_history', 'from_programme', 'KEEP', 'history'),
    ('catalogue.course_owner_history', 'to_programme', 'KEEP', 'history'),
    ('catalogue.course_reset_item', 'programme_code', 'KEEP', 'history'),
    ('people.record_move', 'from_programme', 'KEEP', 'history'),
    ('people.record_move', 'to_programme', 'KEEP', 'history'),
    ('people.transfer_application', 'from_programme_code', 'KEEP', 'history: where the student came from'),
    ('admissions.programme_change_request', 'from_programme_code', 'KEEP', 'history'),
    ('people.matric_batch_row', 'programme_code', 'KEEP', 'history: an import'),
    ('admissions.cce_batch_row', 'programme_code', 'KEEP', 'history: an import'),
    ('admissions.eligibility_event', 'programme_code', 'KEEP', 'history'),
    ('admissions.eligibility_result', 'programme_code', 'KEEP', 'history'),
    ('admissions.eligibility_run', 'applied_programme_code', 'KEEP', 'history');

-- ── the merges, the rows each moved, the old codes kept as aliases ──────────────────────────────────────────────────────
CREATE TABLE ref.programme_merge (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    from_code        text NOT NULL REFERENCES ref.programme(code),
    to_code          text NOT NULL REFERENCES ref.programme(code),
    from_name        text NOT NULL,
    to_name          text NOT NULL,
    reason           text NOT NULL CHECK (length(btrim(reason)) >= 10),
    students         int NOT NULL DEFAULT 0,
    moved            jsonb NOT NULL DEFAULT '{}',
    kept             jsonb NOT NULL DEFAULT '{}',
    was_archived     boolean NOT NULL DEFAULT false,
    merged_by        uuid NOT NULL,
    merged_office    text NULL,
    merged_at        timestamptz NOT NULL DEFAULT now(),
    undone_at        timestamptz NULL,
    undone_by        uuid NULL,
    undone_office    text NULL,
    undo_reason      text NULL,
    CHECK (from_code <> to_code)
);
CREATE INDEX ix_programme_merge_from ON ref.programme_merge (from_code);
CREATE INDEX ix_programme_merge_to ON ref.programme_merge (to_code);
SELECT audit.attach('ref.programme_merge');
COMMENT ON TABLE ref.programme_merge IS
  'V574: a programme merged into another — who, why, the students moved, the rows moved and kept by table, and its undoing.';

CREATE TABLE ref.programme_merge_row (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    merge_id  uuid NOT NULL REFERENCES ref.programme_merge(id) ON DELETE CASCADE,
    tab       text NOT NULL,
    col       text NOT NULL,
    pk        jsonb NOT NULL
);
CREATE INDEX ix_programme_merge_row ON ref.programme_merge_row (merge_id, tab, col);
SELECT audit.attach('ref.programme_merge_row');
COMMENT ON TABLE ref.programme_merge_row IS
  'V574: each row a merge moved (or, for a fee line, ended — col ended_at), by its primary key, so the merge is undone exactly.';

CREATE TABLE ref.programme_alias (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    alias_code      text NOT NULL REFERENCES ref.programme(code),
    programme_code  text NOT NULL REFERENCES ref.programme(code),
    merge_id        uuid NULL REFERENCES ref.programme_merge(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    ended_at        timestamptz NULL,
    CHECK (alias_code <> programme_code)
);
CREATE UNIQUE INDEX ux_programme_alias_live ON ref.programme_alias (alias_code) WHERE ended_at IS NULL;
CREATE INDEX ix_programme_alias_target ON ref.programme_alias (programme_code) WHERE ended_at IS NULL;
SELECT audit.attach('ref.programme_alias');
COMMENT ON TABLE ref.programme_alias IS
  'V574: an old code merged into a programme; a record written later with the old code lands on the programme (ref.programme_alias_apply). Ended when the merge is undone.';

/* a programme's code as it stands now: the programme an old code was merged into, else the code itself */
CREATE FUNCTION ref.programme_now(p_code text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT a.programme_code FROM ref.programme_alias a WHERE a.alias_code = p_code AND a.ended_at IS NULL), p_code)
$fn$;

/* a record written with a merged code lands on the programme it was merged into */
CREATE FUNCTION ref.programme_alias_apply() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE v_col text := TG_ARGV[0]; v_code text; v_to text;
BEGIN
    v_code := to_jsonb(NEW) ->> v_col;
    IF v_code IS NULL THEN RETURN NEW; END IF;
    SELECT a.programme_code INTO v_to FROM ref.programme_alias a WHERE a.alias_code = v_code AND a.ended_at IS NULL;
    IF v_to IS NOT NULL THEN
        NEW := jsonb_populate_record(NEW, jsonb_build_object(v_col, v_to));
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_student_programme_alias BEFORE INSERT OR UPDATE OF programme_code ON people.student
    FOR EACH ROW EXECUTE FUNCTION ref.programme_alias_apply('programme_code');
CREATE TRIGGER trg_pg_application_programme_alias BEFORE INSERT OR UPDATE OF programme_code ON admissions.pg_application
    FOR EACH ROW EXECUTE FUNCTION ref.programme_alias_apply('programme_code');
CREATE TRIGGER trg_fee_schedule_programme_alias BEFORE INSERT OR UPDATE OF programme_code ON finance.fee_schedule
    FOR EACH ROW EXECUTE FUNCTION ref.programme_alias_apply('programme_code');
CREATE TRIGGER trg_course_offer_programme_alias BEFORE INSERT ON catalogue.course_offer
    FOR EACH ROW EXECUTE FUNCTION ref.programme_alias_apply('programme_code');

/* a table's primary key as jsonb of the row, written as SQL for that table */
CREATE FUNCTION ref.pk_json_sql(p_tab text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT 'jsonb_build_object(' || string_agg(quote_literal(a.attname) || ', ' || quote_ident(a.attname), ', ' ORDER BY k.n) || ')'
      FROM pg_index i
      CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum, n)
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
     WHERE i.indrelid = p_tab::regclass AND i.indisprimary
$fn$;

/* the row of a table (by its alias) whose primary key is the jsonb given, written as SQL (each column typed as the table has it) */
CREATE FUNCTION ref.pk_match_sql(p_tab text, p_alias text, p_param text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT string_agg(format('%s.%I = (%s ->> %L)::%s', p_alias, a.attname, p_param, a.attname, format_type(a.atttypid, a.atttypmod)), ' AND ' ORDER BY k.n)
      FROM pg_index i
      CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum, n)
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
     WHERE i.indrelid = p_tab::regclass AND i.indisprimary
$fn$;

/* who merges: the Registry, and the School of Postgraduate Studies for postgraduate programmes */
CREATE FUNCTION ref.programme_merge_office(p_category text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF coalesce(current_setting('moaum.programme_merge_preview', true), '') = 'on' THEN RETURN; END IF;
    IF v_office IN ('records', 'registrar', 'dregistrar', 'super') THEN RETURN; END IF;
    IF v_office IN ('pgschool', 'pgsecretary') AND p_category = 'POST GRADUATE' THEN RETURN; END IF;
    RAISE EXCEPTION 'PROGRAMME_MERGE_OFFICE: programmes are merged by the Registry, and postgraduate programmes by the School of Postgraduate Studies'
        USING ERRCODE = '42501';
END $fn$;

-- ── one programme merged into another ───────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION ref.merge_programme(p_from text, p_to text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        f ref.programme; t ref.programme; v_id uuid := gen_random_uuid(); x record; r record; v_n int; v_kept int; v_moved jsonb := '{}'; v_kept_j jsonb := '{}';
        v_students int := 0; v_defer boolean; v_pkj text; v_held boolean; v_sess record; v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PROGRAMME_MERGE_ACTOR: programmes are merged by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_REASON: say why the programmes are one (the School''s list, the Senate''s approval…), ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO f FROM ref.programme WHERE code = upper(btrim(coalesce(p_from, ''))) FOR UPDATE;
    SELECT * INTO t FROM ref.programme WHERE code = upper(btrim(coalesce(p_to, ''))) FOR UPDATE;
    IF f.code IS NULL OR t.code IS NULL THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_UNKNOWN: % is not a programme on the register', CASE WHEN f.code IS NULL THEN p_from ELSE p_to END USING ERRCODE = '23514';
    END IF;
    IF f.code = t.code THEN RAISE EXCEPTION 'PROGRAMME_MERGE_SAME: a programme is not merged into itself' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM ref.programme_alias a WHERE a.alias_code = f.code AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_DONE: % is already merged into %', f.code, ref.programme_now(f.code) USING ERRCODE = '23514';
    END IF;
    IF t.archived THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_ARCHIVED: % (%) is archived%; merge into a programme in use', t.code, t.name,
            coalesce(' (merged into ' || nullif(ref.programme_now(t.code), t.code) || ')', '') USING ERRCODE = '23514';
    END IF;
    IF f.category IS DISTINCT FROM t.category THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_CATEGORY: % is % and % is %; only programmes of one kind are merged', f.code, coalesce(f.category, 'of no category'),
            t.code, coalesce(t.category, 'of no category') USING ERRCODE = '23514';
    END IF;
    PERFORM ref.programme_merge_office(t.category);
    INSERT INTO ref.programme_merge (id, from_code, to_code, from_name, to_name, reason, was_archived, merged_by, merged_office, merged_at)
    VALUES (v_id, f.code, t.code, f.name, t.name, v_reason, coalesce(f.archived, false), v_actor, v_office, clock_timestamp());
    v_defer := people.defer_positions();

    -- the students: each move recorded at the student's own level, as the School's record moves are (V548)
    INSERT INTO people.record_move (student_id, from_programme, to_programme, from_level, to_level, from_entry, reason, moved_by, moved_office)
    SELECT s.id, f.code, t.code, s.current_level, s.current_level, s.entry_mode, 'Programme merge: ' || v_reason, v_actor, v_office
      FROM people.student s WHERE s.programme_code = f.code AND s.current_level IN (700, 800, 900);

    FOR x IN SELECT pr.* FROM ref.programme_reference pr
              WHERE pr.policy IN ('MOVE', 'MOVE_UNLESS_HELD', 'FEES')
                AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = to_regclass(pr.tab) AND a.attname = pr.col AND NOT a.attisdropped)
              ORDER BY CASE pr.policy WHEN 'MOVE_UNLESS_HELD' THEN 1 WHEN 'FEES' THEN 2 ELSE 3 END, pr.tab LOOP
        v_pkj := ref.pk_json_sql(x.tab);
        v_n := 0; v_kept := 0;
        IF x.policy = 'MOVE' THEN
            EXECUTE format('WITH m AS (UPDATE %s SET %I = $2 WHERE %I = $1 RETURNING %s AS pk) '
                           'INSERT INTO ref.programme_merge_row (merge_id, tab, col, pk) SELECT $3, $4, $5, m.pk FROM m', x.tab, x.col, x.col, v_pkj)
                USING f.code, t.code, v_id, x.tab, x.col;
            GET DIAGNOSTICS v_n = ROW_COUNT;
            IF x.tab = 'people.student' THEN v_students := v_n; END IF;
        ELSIF x.policy = 'FEES' THEN
            -- a session the kept programme states fees for: the old code's lines are ended; any other: moved
            FOR v_sess IN SELECT fs.session, bool_or(EXISTS (SELECT 1 FROM finance.fee_schedule k WHERE k.programme_code = t.code AND k.session = fs.session AND k.ended_at IS NULL)) AS held
                            FROM finance.fee_schedule fs WHERE fs.programme_code = f.code AND fs.ended_at IS NULL GROUP BY fs.session LOOP
                IF v_sess.held THEN
                    WITH m AS (UPDATE finance.fee_schedule fs SET ended_at = now() WHERE fs.programme_code = f.code AND fs.session = v_sess.session AND fs.ended_at IS NULL
                               RETURNING jsonb_build_object('id', fs.id) AS pk)
                    INSERT INTO ref.programme_merge_row (merge_id, tab, col, pk) SELECT v_id, 'finance.fee_schedule', 'ended_at', m.pk FROM m;
                    GET DIAGNOSTICS v_kept = ROW_COUNT;
                    v_kept_j := v_kept_j || jsonb_build_object('finance.fee_schedule ended ' || v_sess.session, v_kept);
                ELSE
                    WITH m AS (UPDATE finance.fee_schedule fs SET programme_code = t.code WHERE fs.programme_code = f.code AND fs.session = v_sess.session AND fs.ended_at IS NULL
                               RETURNING jsonb_build_object('id', fs.id) AS pk)
                    INSERT INTO ref.programme_merge_row (merge_id, tab, col, pk) SELECT v_id, 'finance.fee_schedule', 'programme_code', m.pk FROM m;
                    GET DIAGNOSTICS v_kept = ROW_COUNT;
                    v_n := v_n + v_kept;
                END IF;
            END LOOP;
            v_kept := 0;
        ELSE
            -- one by one: a setting the kept programme already holds stays on the old code, with the archived programme
            FOR r IN EXECUTE format('SELECT ctid AS c FROM %s WHERE %I = $1 FOR UPDATE', x.tab, x.col) USING f.code LOOP
                BEGIN
                    EXECUTE format('WITH m AS (UPDATE %s SET %I = $2 WHERE ctid = $1 RETURNING %s AS pk) '
                                   'INSERT INTO ref.programme_merge_row (merge_id, tab, col, pk) SELECT $3, $4, $5, m.pk FROM m', x.tab, x.col, v_pkj)
                        USING r.c, t.code, v_id, x.tab, x.col;
                    v_n := v_n + 1;
                EXCEPTION WHEN unique_violation OR foreign_key_violation THEN
                    v_kept := v_kept + 1;
                END;
            END LOOP;
        END IF;
        IF v_n > 0 THEN v_moved := v_moved || jsonb_build_object(x.tab || '.' || x.col, v_n); END IF;
        IF v_kept > 0 THEN v_kept_j := v_kept_j || jsonb_build_object(x.tab || '.' || x.col, v_kept); END IF;
    END LOOP;

    -- a specialisation the kept programme also has (by name) takes the old one's students and applications
    UPDATE people.student_specialisation ss SET specialisation_id = k.id
      FROM catalogue.programme_specialisation o JOIN catalogue.programme_specialisation k ON k.programme_code = t.code AND lower(btrim(k.name)) = lower(btrim(o.name))
     WHERE o.programme_code = f.code AND ss.specialisation_id = o.id;
    UPDATE admissions.pg_application pa SET specialisation_id = k.id
      FROM catalogue.programme_specialisation o JOIN catalogue.programme_specialisation k ON k.programme_code = t.code AND lower(btrim(k.name)) = lower(btrim(o.name))
     WHERE o.programme_code = f.code AND pa.specialisation_id = o.id;

    -- the old code an alias of the kept programme, and those merged into it before now aliases of the kept one too
    -- (recorded, so undoing this merge points them back)
    WITH m AS (UPDATE ref.programme_alias a SET programme_code = t.code WHERE a.programme_code = f.code AND a.ended_at IS NULL RETURNING jsonb_build_object('id', a.id) AS pk)
    INSERT INTO ref.programme_merge_row (merge_id, tab, col, pk) SELECT v_id, 'ref.programme_alias', 'programme_code', m.pk FROM m;
    INSERT INTO ref.programme_alias (alias_code, programme_code, merge_id) VALUES (f.code, t.code, v_id);
    UPDATE ref.programme SET archived = true WHERE code = f.code;
    IF v_defer THEN PERFORM people.refresh_deferred_positions(); END IF;

    UPDATE ref.programme_merge SET students = v_students, moved = v_moved, kept = v_kept_j WHERE id = v_id;
    RETURN jsonb_build_object('id', v_id, 'from', f.code, 'fromName', f.name, 'to', t.code, 'toName', t.name, 'students', v_students, 'moved', v_moved, 'kept', v_kept_j);
END $fn$;
COMMENT ON FUNCTION ref.merge_programme(text, text, text) IS
  'V574: a programme merged into another of its kind — every record naming the old code moved as ref.programme_reference says, each student''s move recorded, the old code an alias of the kept programme and archived; returns what moved and what was kept on the old code.';

/* merges in order, in one act: [{from, to}]; the moved students' academic positions refreshed once, together */
CREATE FUNCTION ref.merge_programmes(p_pairs jsonb, p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x jsonb; v_out jsonb := '[]'; v_defer boolean;
BEGIN
    IF p_pairs IS NULL OR jsonb_typeof(p_pairs) <> 'array' OR jsonb_array_length(p_pairs) = 0 THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_EMPTY: name the programmes to merge and the one each goes into' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_pairs) > 500 THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_TOO_MANY: up to 500 merges at a time' USING ERRCODE = '23514';
    END IF;
    v_defer := people.defer_positions();
    FOR x IN SELECT * FROM jsonb_array_elements(p_pairs) LOOP
        v_out := v_out || jsonb_build_array(ref.merge_programme(x->>'from', x->>'to', p_reason));
    END LOOP;
    IF v_defer THEN PERFORM people.refresh_deferred_positions(); END IF;
    RETURN v_out;
END $fn$;

/* what a set of merges would do, done and undone: nothing is kept; a pair that cannot be merged says why */
CREATE FUNCTION ref.programme_merge_effect(p_pairs jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x jsonb; v_out jsonb := '[]'; v_one jsonb; v_msg text; v_res jsonb;
BEGIN
    IF p_pairs IS NULL OR jsonb_typeof(p_pairs) <> 'array' THEN RETURN '[]'; END IF;
    BEGIN
        PERFORM set_config('moaum.programme_merge_preview', 'on', true);
        PERFORM people.defer_positions();   -- undone with the rest: the positions are not refreshed for a preview
        FOR x IN SELECT * FROM jsonb_array_elements(p_pairs) LOOP
            BEGIN
                v_one := ref.merge_programme(x->>'from', x->>'to', 'the effect of a merge, shown before it is made');
                v_one := v_one - 'id';
            EXCEPTION WHEN check_violation OR insufficient_privilege THEN
                GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
                v_one := jsonb_build_object('from', x->>'from', 'to', x->>'to', 'refused', v_msg);
            END;
            v_out := v_out || jsonb_build_array(v_one);
        END LOOP;
        v_res := v_out;
        RAISE EXCEPTION 'PROGRAMME_MERGE_EFFECT_UNDONE';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg <> 'PROGRAMME_MERGE_EFFECT_UNDONE' THEN RAISE; END IF;
    END;
    PERFORM set_config('moaum.programme_merge_preview', '', true);
    RETURN v_res;
END $fn$;
COMMENT ON FUNCTION ref.programme_merge_effect(jsonb) IS
  'V574: what ref.merge_programmes would do for the pairs given — each merge''s students, rows moved and kept, or why it is refused — done in order and undone.';

-- ── a merge undone from its record ──────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION ref.undo_programme_merge(p_merge uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        m ref.programme_merge; g record; v_n int; v_total int := 0; v_students int := 0; v_defer boolean; v_cat text; v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PROGRAMME_MERGE_ACTOR: a merge is undone by a person' USING ERRCODE = '23514'; END IF;
    IF length(v_reason) < 10 THEN RAISE EXCEPTION 'PROGRAMME_MERGE_REASON: say why the merge is undone, ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM ref.programme_merge WHERE id = p_merge FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'PROGRAMME_MERGE_UNKNOWN: no such merge' USING ERRCODE = '23514'; END IF;
    IF m.undone_at IS NOT NULL THEN RAISE EXCEPTION 'PROGRAMME_MERGE_UNDONE: this merge was undone on %', to_char(m.undone_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514'; END IF;
    SELECT category INTO v_cat FROM ref.programme WHERE code = m.to_code;
    PERFORM ref.programme_merge_office(v_cat);
    -- the kept programme merged into another since: that merge is undone first, or this one would find nothing to send back
    IF EXISTS (SELECT 1 FROM ref.programme_alias a WHERE a.alias_code = m.to_code AND a.ended_at IS NULL) THEN
        RAISE EXCEPTION 'PROGRAMME_MERGE_LATER: % was merged into % since; undo that merge first', m.to_code, ref.programme_now(m.to_code) USING ERRCODE = '23514';
    END IF;
    -- the alias ended first, so the rows going back are not sent forward again
    UPDATE ref.programme_alias SET ended_at = now() WHERE merge_id = m.id AND ended_at IS NULL;
    v_defer := people.defer_positions();
    INSERT INTO people.record_move (student_id, from_programme, to_programme, from_level, to_level, from_entry, reason, moved_by, moved_office)
    SELECT s.id, m.to_code, m.from_code, s.current_level, s.current_level, s.entry_mode, 'Programme merge undone: ' || v_reason, v_actor, v_office
      FROM ref.programme_merge_row r JOIN people.student s ON s.id = (r.pk->>'id')::uuid
     WHERE r.merge_id = m.id AND r.tab = 'people.student' AND s.programme_code = m.to_code AND s.current_level IN (700, 800, 900);
    UPDATE ref.programme SET archived = m.was_archived WHERE code = m.from_code;
    FOR g IN SELECT DISTINCT r.tab, r.col FROM ref.programme_merge_row r WHERE r.merge_id = m.id LOOP
        IF g.col = 'ended_at' THEN
            EXECUTE format('UPDATE %s t SET ended_at = NULL FROM ref.programme_merge_row r WHERE r.merge_id = $1 AND r.tab = $2 AND r.col = $3 AND %s',
                           g.tab, ref.pk_match_sql(g.tab, 't', 'r.pk'))
                USING m.id, g.tab, g.col;
        ELSE
            EXECUTE format('UPDATE %s t SET %I = $4 FROM ref.programme_merge_row r WHERE r.merge_id = $1 AND r.tab = $2 AND r.col = $3 AND t.%I = $5 AND %s',
                           g.tab, g.col, g.col, ref.pk_match_sql(g.tab, 't', 'r.pk'))
                USING m.id, g.tab, g.col, m.from_code, m.to_code;
        END IF;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_total := v_total + v_n;
        IF g.tab = 'people.student' THEN v_students := v_n; END IF;
    END LOOP;
    IF v_defer THEN PERFORM people.refresh_deferred_positions(); END IF;
    UPDATE ref.programme_merge SET undone_at = now(), undone_by = v_actor, undone_office = v_office, undo_reason = v_reason WHERE id = m.id;
    RETURN jsonb_build_object('id', m.id, 'from', m.from_code, 'to', m.to_code, 'students', v_students, 'rows', v_total);
END $fn$;
COMMENT ON FUNCTION ref.undo_programme_merge(uuid, text) IS
  'V574: a merge undone from its record — the alias ended, every row it moved sent back (a fee line it ended in force again), the students'' moves recorded, the old programme as it was before; refused when the kept programme was merged away since.';

-- ── the merges proposed ─────────────────────────────────────────────────────────────────────────────────────────────────
/* a programme's name as words, its degree left out: "M.Sc. Geography" and "MSC GEOGRAPHY" both "geography" */
CREATE FUNCTION ref.programme_subject(p_name text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT btrim(regexp_replace(regexp_replace(
               regexp_replace(lower(coalesce(p_name, '')) || ' ', '[^a-z]+', ' ', 'g'),
               '^ *(m sc ed|m sc|msc|m a|ma|m ed|med|ph d|phd|mba|mpa|mhm|mlis|murp|pgdm|pgd|ll m|llm|m phil|mphil|master of|masters in|master in|postgraduate diploma in|in) ', ' '),
           ' +', ' ', 'g'))
$fn$;

/* an older code's degree, as the School's catalogue writes the award */
CREATE FUNCTION ref.programme_degree(p_name text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE split_part(upper(btrim(coalesce(p_name, ''))), ' ', 1)
             WHEN 'MA' THEN 'MA' WHEN 'MSC' THEN 'MSC' WHEN 'MED' THEN 'MED' WHEN 'MBA' THEN 'MBA' WHEN 'MPA' THEN 'MPA' WHEN 'MHM' THEN 'MHM'
             WHEN 'MLIS' THEN 'MLIS' WHEN 'MURP' THEN 'MURP' WHEN 'PGD' THEN 'PGD' WHEN 'PGDM' THEN 'PGD' WHEN 'PHD' THEN 'PHD' WHEN 'LLM' THEN 'LLM' END
$fn$;

CREATE FUNCTION ref.programme_merge_suggestions(p_category text DEFAULT 'POST GRADUATE')
RETURNS TABLE (step int, kind text, from_code text, from_name text, from_students int, to_code text, to_name text, why text, choices jsonb)
LANGUAGE sql STABLE AS $fn$
WITH p AS MATERIALIZED (
    SELECT g.code, g.name, g.dept_code, g.pg_award, upper(btrim(g.name)) AS uname,
           (SELECT count(*) FROM people.student s WHERE s.programme_code = g.code)::int AS students,
           (SELECT count(*) FROM admissions.pg_application a WHERE a.programme_code = g.code)::int AS applications
      FROM ref.programme g
     WHERE g.category = p_category AND NOT coalesce(g.archived, false)
       AND NOT EXISTS (SELECT 1 FROM ref.programme_alias a WHERE a.alias_code = g.code AND a.ended_at IS NULL)),
older AS (SELECT * FROM p WHERE pg_award IS NULL),
catalogue AS (SELECT p.*, ref.programme_subject(p.name) AS subject FROM p WHERE pg_award IS NOT NULL),
-- step 1: codes of one name in one department, into the one most students sit on
same AS (
    SELECT o.*, first_value(o.code) OVER w AS keep, count(*) OVER (PARTITION BY o.uname, o.dept_code) AS n
      FROM older o WINDOW w AS (PARTITION BY o.uname, o.dept_code ORDER BY o.students DESC, o.code)),
-- step 3 first: catalogue twins (one subject, award and department; or the award alone beside its one other programme), into the one in use
twin AS (
    SELECT c.code, c.name, c.students, k.code AS keep, k.name AS keep_name
      FROM catalogue c
      JOIN LATERAL (SELECT c2.code, c2.name FROM catalogue c2
                     WHERE c2.dept_code = c.dept_code AND c2.pg_award = c.pg_award
                       AND (c2.subject = c.subject AND c2.subject <> ''
                            OR (c.subject = '' OR c2.subject = '') AND (SELECT count(*) FROM catalogue c3 WHERE c3.dept_code = c.dept_code AND c3.pg_award = c.pg_award) = 2)
                     ORDER BY c2.students + c2.applications DESC, length(c2.name) DESC, c2.code LIMIT 1) k ON k.code <> c.code),
catalogue_now AS (SELECT c.*, coalesce(tw.keep, c.code) AS now_code FROM catalogue c LEFT JOIN twin tw ON tw.code = c.code),
-- step 2: an older code (one of each name) into the catalogue programme of its degree and department that answers to it
older_one AS (SELECT s.* FROM same s WHERE s.code = s.keep),
cand AS (
    SELECT o.code AS from_code, c.now_code, c.name AS cname, c.subject, ref.programme_subject(o.name) AS osubject
      FROM older_one o JOIN catalogue_now c ON c.dept_code = o.dept_code AND c.pg_award = ref.programme_degree(o.name) AND c.code = c.now_code),
pick AS (
    SELECT o.code, o.name, o.students,
           (SELECT x.now_code FROM cand x WHERE x.from_code = o.code AND x.subject = x.osubject LIMIT 1) AS exact,
           (SELECT CASE WHEN count(*) = 1 THEN min(x.now_code) END FROM cand x WHERE x.from_code = o.code) AS only,
           (SELECT jsonb_agg(jsonb_build_object('code', x.now_code, 'name', x.cname) ORDER BY x.cname) FROM cand x WHERE x.from_code = o.code) AS choices
      FROM older_one o)
SELECT 1, 'SAME_NAME', s.code, s.name, s.students, s.keep, (SELECT k.name FROM p k WHERE k.code = s.keep),
       format('%s codes named %s in this department: into the one %s students sit on', s.n, s.name, (SELECT k.students FROM p k WHERE k.code = s.keep)), NULL::jsonb
  FROM same s WHERE s.n > 1 AND s.code <> s.keep
UNION ALL
SELECT 2, CASE WHEN k.exact IS NOT NULL THEN 'EXACT' WHEN k.only IS NOT NULL THEN 'ONLY' WHEN k.choices IS NULL THEN 'NONE' ELSE 'CHOOSE' END,
       k.code, k.name, k.students, coalesce(k.exact, k.only), (SELECT c.name FROM p c WHERE c.code = coalesce(k.exact, k.only)),
       CASE WHEN k.exact IS NOT NULL THEN 'the School''s programme of the same name, degree and department'
            WHEN k.only IS NOT NULL THEN 'the department''s only programme of this degree in the School''s catalogue'
            WHEN k.choices IS NULL THEN 'the School''s catalogue has no programme of this degree in this department: left as it is'
            ELSE 'the department has several programmes of this degree: the School chooses' END,
       k.choices
  FROM pick k
UNION ALL
SELECT 3, 'TWIN', tw.code, tw.name, tw.students, tw.keep, tw.keep_name, 'two programmes of one name in the School''s catalogue: into the one in use', NULL::jsonb
  FROM twin tw
 ORDER BY 1, 4, 3
$fn$;
COMMENT ON FUNCTION ref.programme_merge_suggestions(text) IS
  'V574: the merges proposed for a category — 1 SAME_NAME: codes of one name and department into the one most students sit on; 2: each older code into the School''s catalogue programme of its degree and department — EXACT (the same subject), ONLY (the department''s only one, its name to be checked), CHOOSE (several), NONE; 3 TWIN: catalogue twins into the one in use.';

COMMIT;
