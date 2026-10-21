-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V609 — Old Fees History: the history of the uploads, every one logged and queried on the page
--
--   The Bursary's own file loads straight onto the records in parts of 500 rows (POST /finance/legacy-fees, V498) and nothing
--   kept the upload: who loaded which file, when, how many rows it had, what each part recorded and skipped. V607 keeps the
--   Students Account Officer's uploads held for approval; the Bursary's own and the go-live resets ("Start over", V499) had no
--   history but the payments themselves.
--
--   · finance.legacy_fee_load — one row an upload of the Bursary's (LOAD) or a start over (RESET): the file's name and what the
--     file states (rows, students, sessions, the amount — read in the browser and given when the upload opens), then what the
--     parts did, added up (rows read, recorded, already on record, no such student, nothing to settle, beside another, taken
--     over, corrected, no usable date, the amount recorded, the students and sessions recorded); RESET: the payments deleted,
--     their amount, students and sessions, and the reason.
--   · finance.legacy_fee_load_part — each part as it was loaded (the rows it covered, what it did, the moments it ran: the
--     payments a part recorded carry that moment as generated_at, so the payments of an upload are read back exactly). A part
--     sent again after a lost answer is the same part (the import is idempotent): what it newly recorded is added, the rest kept.
--   · finance.legacy_load_open / finance.legacy_load_part — the Bursary's load: open with the file, then each part; the old door
--     (no upload opened) still logs, its parts gathered into one upload while they keep coming (two minutes apart at most).
--   · A start over is logged as it deletes (a trigger on finance.legacy_payment_reset): one RESET a person's run of batches.
--   · Before V609: the uploads are rebuilt from the payments on record (by the person who recorded them and the moment of each
--     part; parts two minutes apart or less are one upload — the file's name and what was skipped were not kept then), leaving out
--     what a V607 approval loaded; the resets are rebuilt from what they kept. An upload whose payments a reset deleted before V609
--     shows as that reset only.
--   · finance.legacy_upload_history — every upload in one list: the Bursary's loads, the officer's uploads for approval (V607,
--     once sent) and the start overs, with the state of each.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V609: Old Fees History upload history — every upload logged and queried', true);

-- ── the log ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE finance.legacy_fee_load_no;

CREATE TABLE finance.legacy_fee_load (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref            text NOT NULL UNIQUE,
    kind           text NOT NULL,
    rebuilt        boolean NOT NULL DEFAULT false,
    file_name      text NULL,
    by_person      uuid NULL,
    office         text NULL,
    started_at     timestamptz NOT NULL DEFAULT now(),
    last_at        timestamptz NOT NULL DEFAULT now(),
    -- what the file states, read in the browser and given when the upload opens
    file_rows      integer NULL,
    file_students  integer NULL,
    file_sessions  text NULL,
    file_amount    numeric(16,2) NULL,
    -- what the parts did, added up (NULL where a rebuilt upload cannot say)
    parts          integer NOT NULL DEFAULT 0,
    rows_read      integer NULL,
    recorded       integer NOT NULL DEFAULT 0,
    duplicates     integer NULL,
    matched        integer NULL,
    no_student     integer NULL,
    no_due         integer NULL,
    separate       integer NULL,
    taken_over     integer NULL,
    corrected      integer NULL,
    undated        integer NULL,
    deleted        integer NOT NULL DEFAULT 0,
    amount         numeric(16,2) NOT NULL DEFAULT 0,
    students       integer NOT NULL DEFAULT 0,
    sessions       text[] NOT NULL DEFAULT '{}',
    note           text NULL,
    CONSTRAINT ck_legacy_load_kind CHECK (kind IN ('LOAD', 'RESET')),
    CONSTRAINT ck_legacy_load_counts CHECK (parts >= 0 AND recorded >= 0 AND deleted >= 0 AND (rows_read IS NULL OR rows_read >= 0))
);
COMMENT ON TABLE finance.legacy_fee_load IS
  'V609: an Old Fees History upload of the Bursary''s own file (LOAD: the file, what it states, what its parts did) or a start over (RESET: the old-portal payments deleted) — rebuilt from the records for those before V609; with V607''s uploads for approval, the upload history';
CREATE INDEX ix_legacy_load_person ON finance.legacy_fee_load (by_person, kind, last_at DESC);
CREATE INDEX ix_legacy_load_started ON finance.legacy_fee_load (started_at DESC);

CREATE TABLE finance.legacy_fee_load_part (
    load_id          uuid NOT NULL REFERENCES finance.legacy_fee_load(id),
    seq              integer NOT NULL,
    from_row         integer NULL,
    at               timestamptz NOT NULL DEFAULT now(),
    moments          timestamptz[] NOT NULL DEFAULT ARRAY[now()],
    rows_read        integer NULL,
    recorded         integer NOT NULL DEFAULT 0,
    duplicates       integer NULL,
    matched          integer NULL,
    no_student       integer NULL,
    no_due           integer NULL,
    separate         integer NULL,
    taken_over       integer NULL,
    corrected        integer NULL,
    undated          integer NULL,
    deleted          integer NOT NULL DEFAULT 0,
    amount           numeric(16,2) NOT NULL DEFAULT 0,
    resent           integer NOT NULL DEFAULT 0,
    duplicate_sample text NULL,
    PRIMARY KEY (load_id, seq)
);
COMMENT ON TABLE finance.legacy_fee_load_part IS
  'V609: a part of an Old Fees History upload as it was loaded (or a batch of a start over): the rows it covered, what it did, and the moments it ran — the payments it recorded (or deleted) carry them';
CREATE UNIQUE INDEX ux_legacy_load_part_from ON finance.legacy_fee_load_part (load_id, from_row) WHERE from_row IS NOT NULL;

-- the students an upload recorded (or a start over deleted): derived from the payments, which are audited themselves
CREATE TABLE finance.legacy_fee_load_student (
    load_id    uuid NOT NULL REFERENCES finance.legacy_fee_load(id),
    student_id uuid NOT NULL,
    PRIMARY KEY (load_id, student_id)
);
COMMENT ON TABLE finance.legacy_fee_load_student IS 'V609: the students an Old Fees History upload recorded or a start over deleted — counted once an upload';

-- the history is kept: an upload or a part is never removed
CREATE FUNCTION finance.legacy_load_kept() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'LEGACY_LOAD_KEPT: the history of the old fees uploads is kept' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_legacy_load_kept BEFORE DELETE ON finance.legacy_fee_load FOR EACH ROW EXECUTE FUNCTION finance.legacy_load_kept();
CREATE TRIGGER trg_legacy_load_part_kept BEFORE DELETE ON finance.legacy_fee_load_part FOR EACH ROW EXECUTE FUNCTION finance.legacy_load_kept();

SELECT audit.attach('finance.legacy_fee_load');
SELECT audit.attach('finance.legacy_fee_load_part');
SELECT audit.exempt('finance.legacy_fee_load_student', 'V609: derived — the students an old fees upload recorded, read from the payments, which are audited');

GRANT SELECT ON finance.legacy_fee_load, finance.legacy_fee_load_part, finance.legacy_fee_load_student TO app_auditor, app_reporting;

-- the payments a part recorded carry the part's moment (generated_at): read back by it
CREATE INDEX IF NOT EXISTS ix_pref_legacy_generated ON finance.payment_reference (generated_at, confirmed_by) WHERE channel = 'Legacy';
CREATE INDEX IF NOT EXISTS ix_legacy_payment_reset_at ON finance.legacy_payment_reset (reset_at, reset_by);

CREATE FUNCTION finance.legacy_load_ref(p_at timestamptz) RETURNS text LANGUAGE sql AS $$
    SELECT 'OFL-' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'YYYY') || '-' || lpad(nextval('finance.legacy_fee_load_no')::text, 5, '0')
$$;

-- the sessions of two lists, once each, in order
CREATE FUNCTION finance.legacy_load_sessions(a text[], b text[]) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(array_agg(DISTINCT s ORDER BY s), '{}') FROM unnest(coalesce(a, '{}') || coalesce(b, '{}')) s WHERE s IS NOT NULL AND s <> ''
$$;

-- ── the Bursary's load: open, then each part ─────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_load_actor() RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_LOAD_PERSON: an old fees file is loaded by a person' USING ERRCODE = '42501'; END IF;
    IF coalesce(office, '') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'LEGACY_LOAD_OFFICE: the Bursary loads its own old fees file; the Students Account Officer''s upload waits for the Bursar''s approval'
            USING ERRCODE = '42501';
    END IF;
    RETURN who;
END $$;

CREATE FUNCTION finance.legacy_load_open(p_file text, p_rows integer, p_students integer, p_sessions text, p_amount numeric)
RETURNS TABLE (id uuid, ref text) LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_load_actor(); v_id uuid := gen_random_uuid(); v_ref text := finance.legacy_load_ref(now());
BEGIN
    IF p_rows IS NULL OR p_rows < 1 THEN
        RAISE EXCEPTION 'LEGACY_LOAD_ROWS: an upload says how many rows its file has, one or more' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.legacy_fee_load (id, ref, kind, file_name, by_person, office, file_rows, file_students, file_sessions, file_amount,
                                         rows_read, duplicates, matched, no_student, no_due, separate, taken_over, corrected, undated)
    VALUES (v_id, v_ref, 'LOAD', left(nullif(btrim(coalesce(p_file, '')), ''), 200), who, current_setting('moaum.actor_office', true),
            p_rows, p_students, left(nullif(btrim(coalesce(p_sessions, '')), ''), 500), p_amount, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    RETURN QUERY SELECT v_id, v_ref;
END $$;

-- a part: the import run on its rows (finance.import_legacy_payments, as ever), what it did kept on the part and added to the upload.
-- p_load NULL (the old door): the person's upload with no file, still coming in (a part two minutes ago at most), or a new one.
-- p_from: the part's first row in the file (0 for the first); a part sent again is the same part.
CREATE FUNCTION finance.legacy_load_part(p_load uuid, p_from integer, p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_load_actor(); l finance.legacy_fee_load; pt finance.legacy_fee_load_part; r record;
        v_amount numeric; v_sessions text[]; v_new boolean; v_before uuid[];
BEGIN
    IF p_load IS NULL THEN
        SELECT * INTO l FROM finance.legacy_fee_load f
         WHERE f.by_person = who AND f.kind = 'LOAD' AND NOT f.rebuilt AND f.file_rows IS NULL AND f.last_at >= now() - interval '2 minutes'
         ORDER BY f.last_at DESC LIMIT 1 FOR UPDATE;
        IF NOT FOUND THEN
            INSERT INTO finance.legacy_fee_load (ref, kind, by_person, office, rows_read, duplicates, matched, no_student, no_due, separate, taken_over, corrected, undated)
            VALUES (finance.legacy_load_ref(now()), 'LOAD', who, current_setting('moaum.actor_office', true), 0, 0, 0, 0, 0, 0, 0, 0, 0)
            RETURNING * INTO l;
        END IF;
    ELSE
        SELECT * INTO l FROM finance.legacy_fee_load f WHERE f.id = p_load FOR UPDATE;
        IF NOT FOUND OR l.kind <> 'LOAD' OR l.rebuilt THEN RAISE EXCEPTION 'LEGACY_LOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
        IF l.by_person IS DISTINCT FROM who THEN
            RAISE EXCEPTION 'LEGACY_LOAD_OWN: an upload is loaded by the person who opened it' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF p_from IS NOT NULL AND (p_from < 0 OR (l.file_rows IS NOT NULL AND p_from >= l.file_rows)) THEN
        RAISE EXCEPTION 'LEGACY_LOAD_PART: the part starts at row % of a file of % rows', p_from + 1, l.file_rows USING ERRCODE = '23514';
    END IF;

    -- what this part recorded: the payments it made carry this moment (the moment of the transaction: those already made in it, by
    -- an earlier part of the same transaction, are not this part's)
    SELECT coalesce(array_agg(p.id), '{}') INTO v_before FROM finance.payment_reference p
     WHERE p.channel = 'Legacy' AND p.generated_at = now() AND p.confirmed_by = who;

    SELECT * INTO r FROM finance.import_legacy_payments(p_rows);

    SELECT coalesce(sum(p.amount), 0), coalesce(array_agg(DISTINCT p.session), '{}') INTO v_amount, v_sessions
      FROM finance.payment_reference p
     WHERE p.channel = 'Legacy' AND p.generated_at = now() AND p.confirmed_by = who AND p.id <> ALL (v_before);
    INSERT INTO finance.legacy_fee_load_student (load_id, student_id)
    SELECT DISTINCT l.id, p.student_id FROM finance.payment_reference p
     WHERE p.channel = 'Legacy' AND p.generated_at = now() AND p.confirmed_by = who AND p.id <> ALL (v_before)
    ON CONFLICT DO NOTHING;

    SELECT * INTO pt FROM finance.legacy_fee_load_part x WHERE x.load_id = l.id AND x.from_row = p_from;
    v_new := NOT FOUND OR p_from IS NULL;
    IF v_new THEN
        INSERT INTO finance.legacy_fee_load_part (load_id, seq, from_row, rows_read, recorded, duplicates, matched, no_student, no_due, separate,
                                                  taken_over, corrected, undated, amount, duplicate_sample)
        VALUES (l.id, l.parts + 1, p_from, r.rows, r.cleared, r.duplicates, r.matched, r.no_student, r.no_due, r.separate,
                r.taken_over, r.corrected, r.undated, v_amount, left(nullif(r.duplicate_sample, ''), 4000));
        UPDATE finance.legacy_fee_load f
           SET parts = f.parts + 1, last_at = now(), rows_read = coalesce(f.rows_read, 0) + r.rows, recorded = f.recorded + r.cleared,
               duplicates = coalesce(f.duplicates, 0) + r.duplicates, matched = coalesce(f.matched, 0) + r.matched,
               no_student = coalesce(f.no_student, 0) + r.no_student, no_due = coalesce(f.no_due, 0) + r.no_due,
               separate = coalesce(f.separate, 0) + r.separate, taken_over = coalesce(f.taken_over, 0) + r.taken_over,
               corrected = coalesce(f.corrected, 0) + r.corrected, undated = coalesce(f.undated, 0) + r.undated,
               amount = f.amount + v_amount, sessions = finance.legacy_load_sessions(f.sessions, v_sessions),
               students = (SELECT count(*) FROM finance.legacy_fee_load_student s WHERE s.load_id = f.id)
         WHERE f.id = l.id RETURNING * INTO l;
    ELSE
        -- the same part again (its answer lost on the way): what it newly recorded is added; the part read its rows once
        UPDATE finance.legacy_fee_load_part x
           SET recorded = x.recorded + r.cleared, amount = x.amount + v_amount, resent = x.resent + 1, moments = x.moments || now()
         WHERE x.load_id = l.id AND x.seq = pt.seq;
        UPDATE finance.legacy_fee_load f
           SET last_at = now(), recorded = f.recorded + r.cleared, amount = f.amount + v_amount,
               sessions = finance.legacy_load_sessions(f.sessions, v_sessions),
               students = (SELECT count(*) FROM finance.legacy_fee_load_student s WHERE s.load_id = f.id)
         WHERE f.id = l.id RETURNING * INTO l;
    END IF;

    RETURN to_jsonb(r) || jsonb_build_object('load_id', l.id, 'load_ref', l.ref, 'parts', l.parts, 'rows_loaded', l.rows_read,
                                             'file_rows', l.file_rows, 'recorded_amount', v_amount, 'resent', NOT v_new);
END $$;

COMMENT ON FUNCTION finance.legacy_load_open(text, integer, integer, text, numeric) IS
  'V609: the Bursary opens an upload of its own old fees file — the file''s name and what it states (rows, students, sessions, amount); the parts follow';
COMMENT ON FUNCTION finance.legacy_load_part(uuid, integer, jsonb) IS
  'V609: a part of the Bursary''s old fees upload — finance.import_legacy_payments on its rows, what it did kept on the part and added to the upload (a part sent again adds only what it newly recorded); with no upload given, the person''s upload still coming in (the old door)';

-- ── a start over, logged as it deletes ─────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_reset_logged() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE g record; l finance.legacy_fee_load;
BEGIN
    FOR g IN SELECT n.reset_by, count(*)::int AS deleted, coalesce(sum(n.amount), 0) AS amount, array_agg(DISTINCT n.session) AS sessions,
                    min(n.reason) AS reason
               FROM new_rows n GROUP BY n.reset_by LOOP
        SELECT * INTO l FROM finance.legacy_fee_load f
         WHERE f.kind = 'RESET' AND NOT f.rebuilt AND f.by_person IS NOT DISTINCT FROM g.reset_by AND f.last_at >= now() - interval '10 minutes'
         ORDER BY f.last_at DESC LIMIT 1 FOR UPDATE;
        IF NOT FOUND THEN
            INSERT INTO finance.legacy_fee_load (ref, kind, by_person, office, note)
            VALUES (finance.legacy_load_ref(now()), 'RESET', g.reset_by, nullif(current_setting('moaum.actor_office', true), ''), left(g.reason, 500))
            RETURNING * INTO l;
        END IF;
        INSERT INTO finance.legacy_fee_load_student (load_id, student_id)
        SELECT DISTINCT l.id, n.student_id FROM new_rows n WHERE n.reset_by IS NOT DISTINCT FROM g.reset_by ON CONFLICT DO NOTHING;
        INSERT INTO finance.legacy_fee_load_part (load_id, seq, deleted, amount) VALUES (l.id, l.parts + 1, g.deleted, g.amount);
        UPDATE finance.legacy_fee_load f
           SET parts = f.parts + 1, last_at = now(), deleted = f.deleted + g.deleted, amount = f.amount + g.amount,
               sessions = finance.legacy_load_sessions(f.sessions, g.sessions),
               students = (SELECT count(*) FROM finance.legacy_fee_load_student s WHERE s.load_id = f.id)
         WHERE f.id = l.id;
    END LOOP;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_legacy_reset_logged AFTER INSERT ON finance.legacy_payment_reset
    REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION finance.legacy_reset_logged();

-- ── before V609: rebuilt from the records ────────────────────────────────────────────────────────────────────────────────
-- the uploads: each moment the import recorded payments is a part (the person who recorded them, that moment); parts two minutes
-- apart or less are one upload; what a V607 approval loaded is the officer's upload, not the Bursary's
CREATE TEMP TABLE v609_part ON COMMIT DROP AS
SELECT m.*, sum(m.brk) OVER (PARTITION BY m.who ORDER BY m.at) AS grp
  FROM (SELECT x.*, CASE WHEN x.at - lag(x.at) OVER (PARTITION BY x.who ORDER BY x.at) <= interval '2 minutes' THEN 0 ELSE 1 END AS brk
          FROM (SELECT p.confirmed_by AS who, p.generated_at AS at, count(*)::int AS n, sum(p.amount) AS amount, array_agg(DISTINCT p.session) AS sessions
                  FROM finance.payment_reference p
                 WHERE p.channel = 'Legacy' AND p.reference LIKE 'MOAUM-LEG-%' AND p.confirmed_by IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM finance.legacy_fee_upload u
                                    WHERE u.decided_by = p.confirmed_by AND u.decided_at IS NOT NULL
                                      AND p.generated_at BETWEEN u.decided_at AND coalesce(u.completed_at, now()))
                 GROUP BY 1, 2) x) m;

-- the start overs: each moment a reset deleted payments is a batch; a person's batches ten minutes apart or less are one start over
CREATE TEMP TABLE v609_reset ON COMMIT DROP AS
SELECT m.*, sum(m.brk) OVER (PARTITION BY m.who ORDER BY m.at) AS grp
  FROM (SELECT x.*, CASE WHEN x.at - lag(x.at) OVER (PARTITION BY x.who ORDER BY x.at) <= interval '10 minutes' THEN 0 ELSE 1 END AS brk
          FROM (SELECT r.reset_by AS who, r.reset_at AS at, count(*)::int AS n, sum(r.amount) AS amount,
                       array_agg(DISTINCT r.session) AS sessions, min(r.reason) AS reason
                  FROM finance.legacy_payment_reset r GROUP BY 1, 2) x) m;

-- one row an upload or a start over, numbered in the order they began
CREATE TEMP TABLE v609_load ON COMMIT DROP AS
SELECT gen_random_uuid() AS id, g.*
  FROM (SELECT 'LOAD'::text AS kind, who, grp, min(at) AS started_at, max(at) AS last_at, count(*)::int AS parts, sum(n)::int AS n,
               sum(amount) AS amount, NULL::text AS reason
          FROM v609_part GROUP BY who, grp
        UNION ALL
        SELECT 'RESET', who, grp, min(at), max(at), count(*)::int, sum(n)::int, sum(amount), min(reason)
          FROM v609_reset GROUP BY who, grp) g;

INSERT INTO finance.legacy_fee_load (id, ref, kind, rebuilt, by_person, started_at, last_at, parts, recorded, deleted, amount, note)
SELECT l.id, finance.legacy_load_ref(l.started_at), l.kind, true, l.who, l.started_at, l.last_at, l.parts,
       CASE l.kind WHEN 'LOAD' THEN l.n ELSE 0 END, CASE l.kind WHEN 'RESET' THEN l.n ELSE 0 END, l.amount,
       CASE l.kind WHEN 'LOAD' THEN 'Rebuilt by V609 from the payments on record: the file''s name and what was skipped were not kept then'
                   ELSE left(l.reason, 500) END
  FROM (SELECT * FROM v609_load ORDER BY started_at, kind) l;

INSERT INTO finance.legacy_fee_load_part (load_id, seq, at, moments, recorded, amount)
SELECT l.id, row_number() OVER (PARTITION BY l.id ORDER BY p.at), p.at, ARRAY[p.at], p.n, p.amount
  FROM v609_part p JOIN v609_load l ON l.kind = 'LOAD' AND l.who = p.who AND l.grp = p.grp;
INSERT INTO finance.legacy_fee_load_part (load_id, seq, at, moments, deleted, amount)
SELECT l.id, row_number() OVER (PARTITION BY l.id ORDER BY p.at), p.at, ARRAY[p.at], p.n, p.amount
  FROM v609_reset p JOIN v609_load l ON l.kind = 'RESET' AND l.who IS NOT DISTINCT FROM p.who AND l.grp = p.grp;

INSERT INTO finance.legacy_fee_load_student (load_id, student_id)
SELECT DISTINCT l.id, r.student_id
  FROM v609_part p JOIN v609_load l ON l.kind = 'LOAD' AND l.who = p.who AND l.grp = p.grp
  JOIN finance.payment_reference r ON r.channel = 'Legacy' AND r.generated_at = p.at AND r.confirmed_by = p.who;
INSERT INTO finance.legacy_fee_load_student (load_id, student_id)
SELECT DISTINCT l.id, r.student_id
  FROM v609_reset p JOIN v609_load l ON l.kind = 'RESET' AND l.who IS NOT DISTINCT FROM p.who AND l.grp = p.grp
  JOIN finance.legacy_payment_reset r ON r.reset_at = p.at AND r.reset_by IS NOT DISTINCT FROM p.who;

UPDATE finance.legacy_fee_load f
   SET students = (SELECT count(*) FROM finance.legacy_fee_load_student x WHERE x.load_id = f.id),
       sessions = (SELECT finance.legacy_load_sessions('{}', array_agg(DISTINCT u.s))
                     FROM (SELECT p.sessions FROM v609_part p WHERE l.kind = 'LOAD' AND p.who = l.who AND p.grp = l.grp
                           UNION ALL
                           SELECT p.sessions FROM v609_reset p WHERE l.kind = 'RESET' AND p.who IS NOT DISTINCT FROM l.who AND p.grp = l.grp) q,
                          unnest(q.sessions) u(s))
  FROM v609_load l
 WHERE f.id = l.id;

-- ── every upload in one list ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE VIEW finance.legacy_upload_history AS
SELECT l.id, l.ref,
       CASE l.kind WHEN 'RESET' THEN 'RESET' ELSE 'DIRECT' END AS kind,
       l.rebuilt,
       CASE WHEN l.kind = 'RESET' THEN 'DONE'
            WHEN l.rebuilt OR l.file_rows IS NULL OR coalesce(l.rows_read, 0) >= l.file_rows THEN 'LOADED'
            WHEN l.last_at >= now() - interval '15 minutes' THEN 'LOADING'
            ELSE 'STOPPED' END AS state,
       l.file_name, l.by_person, l.office, l.started_at AS at, l.last_at AS finished_at,
       l.parts, l.file_rows, l.rows_read, l.recorded,
       CASE WHEN l.duplicates IS NULL AND l.matched IS NULL THEN NULL ELSE coalesce(l.duplicates, 0) + coalesce(l.matched, 0) END AS already,
       l.no_student, l.no_due, l.separate, l.taken_over, l.corrected, l.undated, l.deleted,
       l.students, array_to_string(l.sessions, ', ') AS sessions, l.file_amount, l.amount,
       NULL::uuid AS decided_by, NULL::timestamptz AS decided_at, l.note
  FROM finance.legacy_fee_load l
UNION ALL
SELECT u.id, u.ref, 'FOR_APPROVAL', false, u.state, u.file_name, u.uploaded_by, u.uploaded_office, coalesce(u.submitted_at, u.uploaded_at),
       coalesce(u.completed_at, u.decided_at),
       u.parts, u.row_count, (u.result->>'rows')::int, coalesce((u.result->>'cleared')::int, 0),
       CASE WHEN u.result ? 'duplicates' THEN coalesce((u.result->>'duplicates')::int, 0) + coalesce((u.result->>'matched')::int, 0) END,
       (u.result->>'no_student')::int, (u.result->>'no_due')::int, (u.result->>'separate')::int, (u.result->>'taken_over')::int,
       (u.result->>'corrected')::int, (u.result->>'undated')::int, 0,
       coalesce(u.students, 0), u.sessions, u.amount, NULL::numeric,
       u.decided_by, u.decided_at, u.decision_note
  FROM finance.legacy_fee_upload u
 WHERE u.state <> 'DRAFT';
COMMENT ON VIEW finance.legacy_upload_history IS
  'V609: every Old Fees History upload — the Bursary''s own loads (DIRECT: LOADING, STOPPED or LOADED; rebuilt for those before V609), the Students Account Officer''s uploads for the Bursar''s approval (FOR_APPROVAL, V607, once sent: PENDING, APPROVING, APPROVED, REJECTED, WITHDRAWN) and the start overs (RESET: DONE)';
GRANT SELECT ON finance.legacy_upload_history TO app_auditor, app_reporting;

-- the payments an upload recorded (still on record) or a start over deleted, by the moments of its parts
CREATE FUNCTION finance.legacy_load_payments(p_load uuid)
RETURNS TABLE (part integer, at timestamptz, student_id uuid, session text, purpose text, amount numeric, paid_on timestamptz, reference text,
               receipt_no text)
LANGUAGE sql STABLE AS $$
    -- each moment of the upload once, with the first part that ran at it (parts loaded in one transaction share one), then the
    -- payments that carry it — by the index on the moment
    WITH l AS (SELECT f.id, f.kind, f.by_person FROM finance.legacy_fee_load f WHERE f.id = p_load),
         m AS (SELECT DISTINCT ON (mo) mo, pt.seq FROM finance.legacy_fee_load_part pt, unnest(pt.moments) mo
                WHERE pt.load_id = p_load ORDER BY mo, pt.seq)
    SELECT m.seq, p.generated_at, p.student_id, p.session, p.purpose, p.amount, p.confirmed_at, p.reference, p.receipt_no
      FROM l JOIN m ON l.kind = 'LOAD'
      JOIN finance.payment_reference p ON p.channel = 'Legacy' AND p.generated_at = m.mo AND p.confirmed_by = l.by_person
    UNION ALL
    SELECT m.seq, r.reset_at, r.student_id, r.session, r.purpose, r.amount, r.confirmed_at, r.reference, r.receipt_no
      FROM l JOIN m ON l.kind = 'RESET'
      JOIN finance.legacy_payment_reset r ON r.reset_at = m.mo AND r.reset_by IS NOT DISTINCT FROM l.by_person
$$;
COMMENT ON FUNCTION finance.legacy_load_payments(uuid) IS
  'V609: the payments an Old Fees History upload recorded (those still on record) or a start over deleted, part by part';

COMMIT;
