-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V607 — Old Fees History uploads by the Students Account Officer held for the Bursar's approval
--
--   V591 gave the Students Account Officer the Old Fees History desk's import: the officer's file went straight onto the
--   records (payments, the ledger, the item codes). On the University's word the officer keeps the desk and the upload, but
--   nothing the officer uploads is written to the records until the Bursar approves it.
--
--   · finance.legacy_fee_upload holds the officer's upload — the file's name, the old portal's item codes read from it, the
--     rows in parts of up to 2,000 (finance.legacy_fee_upload_part) and what they add up to (rows, students, sessions, the
--     amount stated) — DRAFT while the parts arrive, PENDING once sent to the Bursar; a part cannot be changed or removed once
--     the upload is sent, so what the Bursar approves is what the officer sent.
--   · The Bursar reads the upload (its summary and rows), checks what approving would do (finance.legacy_upload_check: the
--     import run on the parts and undone — recorded, already on record, no student, no fee due), then approves it — the item
--     codes set and the parts loaded a few at a time with finance.import_legacy_payments, exactly as the Bursar's own upload is
--     (APPROVING until the last part is in, then APPROVED, the totals kept) — or rejects it with the reason. The officer may
--     withdraw an upload not yet decided. The Bursar's decision is the Bursar's office's alone, never on the Bursar's own
--     upload; the Bursar's own file still loads directly.
--   · The Bursar is told when an upload waits (OLD_FEES_UPLOAD_WAITING), and the officer when it is approved or rejected
--     (OLD_FEES_UPLOAD_DECIDED).
--   The API keeps the direct import, the item codes and what is loaded to the Bursary; the officer's other acts on the desk are
--   unchanged.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V607: Old Fees History uploads by the Students Account Officer held for the Bursar''s approval', true);

-- ── the upload and its parts ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE finance.legacy_fee_upload_no;

CREATE TABLE finance.legacy_fee_upload (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref             text NOT NULL UNIQUE,
    state           text NOT NULL DEFAULT 'DRAFT',
    file_name       text NULL,
    note            text NULL,
    item_codes      jsonb NULL,
    parts           integer NOT NULL DEFAULT 0,
    row_count       integer NOT NULL DEFAULT 0,
    students        integer NULL,
    sessions        text NULL,
    amount          numeric(16,2) NULL,
    uploaded_by     uuid NOT NULL,
    uploaded_office text NOT NULL,
    uploaded_at     timestamptz NOT NULL DEFAULT now(),
    submitted_at    timestamptz NULL,
    decided_by      uuid NULL,
    decided_office  text NULL,
    decided_at      timestamptz NULL,
    decision_note   text NULL,
    applied_parts   integer NOT NULL DEFAULT 0,
    result          jsonb NULL,
    completed_at    timestamptz NULL,
    CONSTRAINT ck_legacy_upload_state CHECK (state IN ('DRAFT', 'PENDING', 'APPROVING', 'APPROVED', 'REJECTED', 'WITHDRAWN')),
    CONSTRAINT ck_legacy_upload_codes CHECK (item_codes IS NULL OR jsonb_typeof(item_codes) = 'array'),
    CONSTRAINT ck_legacy_upload_applied CHECK (applied_parts BETWEEN 0 AND parts)
);
COMMENT ON TABLE finance.legacy_fee_upload IS
  'V607: an Old Fees History upload by the Students Account Officer, held for the Bursar''s approval — DRAFT while its parts arrive, PENDING once sent, APPROVING while the Bursar''s approval loads it, then APPROVED; or REJECTED (with the reason) or WITHDRAWN. Nothing of it is on the records before the approval';
CREATE INDEX ix_legacy_upload_state ON finance.legacy_fee_upload (state, submitted_at DESC);

CREATE TABLE finance.legacy_fee_upload_part (
    upload_id  uuid NOT NULL REFERENCES finance.legacy_fee_upload(id) ON DELETE CASCADE,
    seq        integer NOT NULL,
    rows       jsonb NOT NULL,
    row_count  integer NOT NULL,
    PRIMARY KEY (upload_id, seq),
    CONSTRAINT ck_legacy_upload_part_rows CHECK (jsonb_typeof(rows) = 'array' AND row_count = jsonb_array_length(rows) AND row_count BETWEEN 1 AND 2000)
);
COMMENT ON TABLE finance.legacy_fee_upload_part IS
  'V607: the rows of an Old Fees History upload held for approval, in the order sent (up to 2,000 a part); fixed once the upload is sent to the Bursar';

-- a part is fixed once the upload has been sent: what the Bursar approves is what the officer sent
CREATE FUNCTION finance.legacy_upload_part_fixed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    SELECT state INTO v_state FROM finance.legacy_fee_upload WHERE id = coalesce(NEW.upload_id, OLD.upload_id);
    IF TG_OP = 'UPDATE' OR coalesce(v_state, 'DRAFT') <> 'DRAFT' THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_FIXED: the rows of an upload sent to the Bursar are not changed' USING ERRCODE = '23514';
    END IF;
    RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER trg_legacy_upload_part_fixed BEFORE INSERT OR UPDATE OR DELETE ON finance.legacy_fee_upload_part
    FOR EACH ROW EXECUTE FUNCTION finance.legacy_upload_part_fixed();

SELECT audit.attach('finance.legacy_fee_upload');
SELECT audit.attach('finance.legacy_fee_upload_part');

GRANT SELECT ON finance.legacy_fee_upload TO app_auditor, app_reporting;

-- ── who acts ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_upload_actor(p_offices text[]) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_PERSON: an old fees upload is made and decided by a person' USING ERRCODE = '42501'; END IF;
    IF NOT (coalesce(office, '') = ANY (p_offices)) THEN
        RAISE EXCEPTION '%', CASE WHEN p_offices = ARRAY['bursar']
            THEN 'LEGACY_UPLOAD_OFFICE: an old fees upload held for approval is approved or rejected by the Bursar'
            ELSE 'LEGACY_UPLOAD_OFFICE: an upload held for the Bursar''s approval is the Students Account Officer''s; the Bursary loads its own file directly' END
            USING ERRCODE = '42501';
    END IF;
    RETURN who;
END $$;

-- ── the officer: open, send the parts, send to the Bursar, withdraw ─────────────────────────────────────────────────────────
CREATE FUNCTION finance.legacy_upload_open(p_file text, p_note text, p_item_codes jsonb)
RETURNS TABLE (id uuid, ref text) LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['studentaccounts']); v_id uuid := gen_random_uuid(); v_ref text;
BEGIN
    IF p_item_codes IS NOT NULL AND jsonb_typeof(p_item_codes) <> 'array' THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_CODES: the item codes are rows (code, description)' USING ERRCODE = '23514';
    END IF;
    v_ref := 'OFU-' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '-' || lpad(nextval('finance.legacy_fee_upload_no')::text, 5, '0');
    INSERT INTO finance.legacy_fee_upload (id, ref, file_name, note, item_codes, uploaded_by, uploaded_office)
    VALUES (v_id, v_ref, left(nullif(btrim(coalesce(p_file, '')), ''), 200), left(nullif(btrim(coalesce(p_note, '')), ''), 500),
            CASE WHEN jsonb_array_length(coalesce(p_item_codes, '[]')) > 0 THEN p_item_codes END, who, 'studentaccounts');
    RETURN QUERY SELECT v_id, v_ref;
END $$;

CREATE FUNCTION finance.legacy_upload_add(p_upload uuid, p_rows jsonb) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['studentaccounts']); u finance.legacy_fee_upload; n int;
BEGIN
    SELECT * INTO u FROM finance.legacy_fee_upload WHERE id = p_upload FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_UPLOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
    IF u.uploaded_by <> who THEN RAISE EXCEPTION 'LEGACY_UPLOAD_OWN: rows are added to an upload by the person who opened it' USING ERRCODE = '42501'; END IF;
    IF u.state <> 'DRAFT' THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; rows are added only before it is sent', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 2000 THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_ROWS: send the rows in parts of 1 to 2,000' USING ERRCODE = '23514';
    END IF;
    n := jsonb_array_length(p_rows);
    INSERT INTO finance.legacy_fee_upload_part (upload_id, seq, rows, row_count) VALUES (u.id, u.parts + 1, p_rows, n);
    UPDATE finance.legacy_fee_upload SET parts = parts + 1, row_count = row_count + n WHERE id = u.id;
    RETURN u.row_count + n;
END $$;

-- what the rows add up to: rows, students (by the number given), sessions, the amount stated (a blank amount is "cleared in full")
CREATE FUNCTION finance.legacy_upload_tally(p_upload uuid)
RETURNS TABLE (row_count integer, students integer, sessions text, amount numeric) LANGUAGE sql STABLE AS $$
    WITH r AS (
        SELECT upper(btrim(coalesce(e->>'matric', e->>'matric_no', e->>'matno', ''))) AS num, btrim(coalesce(e->>'session', '')) AS ses,
               regexp_replace(coalesce(e->>'amount', e->>'paid', ''), '[^0-9.]', '', 'g') AS amt
          FROM finance.legacy_fee_upload_part p, jsonb_array_elements(p.rows) e
         WHERE p.upload_id = p_upload)
    SELECT count(*)::int, count(DISTINCT nullif(num, ''))::int,
           (SELECT string_agg(s, ', ' ORDER BY s) FROM (SELECT DISTINCT ses AS s FROM r WHERE ses <> '') x),
           coalesce(sum(CASE WHEN amt ~ '^[0-9]+(\.[0-9]+)?$' THEN amt::numeric END), 0)
      FROM r
$$;

CREATE FUNCTION finance.legacy_upload_submit(p_upload uuid) RETURNS finance.legacy_fee_upload LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['studentaccounts']); u finance.legacy_fee_upload; t record; p record;
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT * INTO u FROM finance.legacy_fee_upload WHERE id = p_upload FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_UPLOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
    IF u.uploaded_by <> who THEN RAISE EXCEPTION 'LEGACY_UPLOAD_OWN: an upload is sent by the person who made it' USING ERRCODE = '42501'; END IF;
    IF u.state <> 'DRAFT' THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is already %', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    IF u.parts = 0 THEN RAISE EXCEPTION 'LEGACY_UPLOAD_EMPTY: upload % has no rows to send', u.ref USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM finance.legacy_upload_tally(u.id);
    UPDATE finance.legacy_fee_upload SET state = 'PENDING', submitted_at = now(), students = t.students, sessions = t.sessions, amount = t.amount
     WHERE id = u.id RETURNING * INTO u;
    -- the Bursar is told an upload waits
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code = 'bursar' AND oa.valid_from <= v_today AND (oa.valid_to IS NULL OR oa.valid_to >= v_today) LOOP
        PERFORM platform.tell_person(p.person_id, 'OLD_FEES_UPLOAD_WAITING', NULL,
                    jsonb_build_object('REF', u.ref, 'ROWS', u.row_count, 'STUDENTS', coalesce(u.students, 0), 'SESSIONS', coalesce(u.sessions, '—'),
                                       'FILE', coalesce(u.file_name, 'the file')),
                    'old-fees-upload:' || u.ref || ':waiting:' || p.person_id);
    END LOOP;
    RETURN u;
END $$;

CREATE FUNCTION finance.legacy_upload_withdraw(p_upload uuid, p_reason text) RETURNS finance.legacy_fee_upload LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['studentaccounts']); u finance.legacy_fee_upload;
BEGIN
    SELECT * INTO u FROM finance.legacy_fee_upload WHERE id = p_upload FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_UPLOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
    IF u.uploaded_by <> who THEN RAISE EXCEPTION 'LEGACY_UPLOAD_OWN: an upload is withdrawn by the person who made it' USING ERRCODE = '42501'; END IF;
    IF u.state NOT IN ('DRAFT', 'PENDING') THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; only one not yet decided is withdrawn', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    UPDATE finance.legacy_fee_upload SET state = 'WITHDRAWN', decision_note = left(nullif(btrim(coalesce(p_reason, '')), ''), 500), decided_at = now()
     WHERE id = u.id RETURNING * INTO u;
    RETURN u;
END $$;

-- ── the Bursar: check, approve (a few parts at a time), reject ──────────────────────────────────────────────────────────────
-- the totals of finance.import_legacy_payments added up across parts (the duplicate sample kept to fifty)
CREATE FUNCTION finance.legacy_upload_add_totals(p_total jsonb, p_part jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce((SELECT jsonb_object_agg(k, coalesce((p_total->>k)::numeric, 0) + coalesce((p_part->>k)::numeric, 0))
                       FROM unnest(ARRAY['rows', 'cleared', 'no_student', 'no_due', 'duplicates', 'corrected', 'undated', 'matched', 'separate', 'taken_over']) k), '{}'::jsonb)
           || jsonb_build_object('duplicate_sample', (
                SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM (
                    SELECT x FROM (SELECT jsonb_array_elements_text(coalesce(p_total->'duplicate_sample', '[]'::jsonb)) AS x
                                   UNION ALL
                                   SELECT unnest(string_to_array(nullif(p_part->>'duplicate_sample', ''), ', '))) s
                     LIMIT 50) y))
$$;

CREATE FUNCTION finance.legacy_upload_check(p_upload uuid, p_from_part integer, p_parts integer)
RETURNS TABLE (checked_parts integer, totals jsonb) LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['bursar']); u finance.legacy_fee_upload; part record; v_totals jsonb := '{}'; v_n int := 0;
BEGIN
    SELECT * INTO u FROM finance.legacy_fee_upload WHERE id = p_upload;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_UPLOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
    IF u.state <> 'PENDING' THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; it is checked while it waits for approval', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    -- the import run on the parts and undone: what approving would do, nothing written
    BEGIN
        PERFORM set_config('moaum.reason', 'Old fees upload ' || u.ref || ' checked before approval (undone)', true);
        IF u.item_codes IS NOT NULL THEN PERFORM finance.legacy_item_codes_set(u.item_codes); END IF;
        FOR part IN SELECT p.seq, p.rows FROM finance.legacy_fee_upload_part p
                     WHERE p.upload_id = u.id AND p.seq >= greatest(1, coalesce(p_from_part, 1))
                     ORDER BY p.seq LIMIT greatest(1, least(coalesce(p_parts, 2), 10)) LOOP
            v_totals := finance.legacy_upload_add_totals(v_totals, (SELECT to_jsonb(r) FROM finance.import_legacy_payments(part.rows) r));
            v_n := v_n + 1;
        END LOOP;
        RAISE EXCEPTION 'LEGACY_UPLOAD_CHECK_UNDONE' USING ERRCODE = 'P0098';
    EXCEPTION WHEN SQLSTATE 'P0098' THEN
        NULL;
    END;
    RETURN QUERY SELECT v_n, v_totals;
END $$;

CREATE FUNCTION finance.legacy_upload_approve(p_upload uuid, p_note text, p_parts integer)
RETURNS TABLE (state text, parts integer, applied_parts integer, remaining integer, result jsonb) LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['bursar']); u finance.legacy_fee_upload; part record; v_totals jsonb;
BEGIN
    SELECT * INTO u FROM finance.legacy_fee_upload WHERE id = p_upload FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_UPLOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
    IF u.uploaded_by = who THEN RAISE EXCEPTION 'LEGACY_UPLOAD_OWN_DECISION: an upload is approved by someone other than the person who made it' USING ERRCODE = '42501'; END IF;
    IF u.state NOT IN ('PENDING', 'APPROVING') THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; only one waiting for approval is approved', u.ref, lower(u.state) USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', left('Old fees upload ' || u.ref || ' approved by the Bursar' || coalesce(': ' || nullif(btrim(coalesce(p_note, '')), ''), ''), 500), true);
    IF u.state = 'PENDING' THEN
        -- the decision: the item codes first, as the Bursar's own upload sets them before the rows
        IF u.item_codes IS NOT NULL THEN PERFORM finance.legacy_item_codes_set(u.item_codes); END IF;
        UPDATE finance.legacy_fee_upload f SET state = 'APPROVING', decided_by = who, decided_office = 'bursar', decided_at = now(),
               decision_note = left(nullif(btrim(coalesce(p_note, '')), ''), 500), result = '{}'::jsonb
         WHERE f.id = u.id RETURNING * INTO u;
    END IF;
    v_totals := coalesce(u.result, '{}'::jsonb);
    FOR part IN SELECT p.seq, p.rows FROM finance.legacy_fee_upload_part p
                 WHERE p.upload_id = u.id AND p.seq > u.applied_parts
                 ORDER BY p.seq LIMIT greatest(1, least(coalesce(p_parts, 2), 10)) LOOP
        v_totals := finance.legacy_upload_add_totals(v_totals, (SELECT to_jsonb(r) FROM finance.import_legacy_payments(part.rows) r));
        u.applied_parts := part.seq;
    END LOOP;
    UPDATE finance.legacy_fee_upload f SET applied_parts = u.applied_parts, result = v_totals,
           state = CASE WHEN u.applied_parts >= f.parts THEN 'APPROVED' ELSE 'APPROVING' END,
           completed_at = CASE WHEN u.applied_parts >= f.parts THEN now() END
     WHERE f.id = u.id RETURNING * INTO u;
    IF u.state = 'APPROVED' THEN
        PERFORM platform.tell_person(u.uploaded_by, 'OLD_FEES_UPLOAD_DECIDED', NULL,
                    jsonb_build_object('REF', u.ref, 'DECISION', 'approved and loaded', 'ROWS', u.row_count,
                                       'NOTE', coalesce(u.decision_note, '—')),
                    'old-fees-upload:' || u.ref || ':decided');
    END IF;
    RETURN QUERY SELECT u.state, u.parts, u.applied_parts, u.parts - u.applied_parts, u.result;
END $$;

CREATE FUNCTION finance.legacy_upload_reject(p_upload uuid, p_reason text) RETURNS finance.legacy_fee_upload LANGUAGE plpgsql AS $$
DECLARE who uuid := finance.legacy_upload_actor(ARRAY['bursar']); u finance.legacy_fee_upload; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    SELECT * INTO u FROM finance.legacy_fee_upload WHERE id = p_upload FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_UPLOAD_NOT_FOUND: no such upload' USING ERRCODE = 'P0002'; END IF;
    IF u.state <> 'PENDING' THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; only one waiting for approval is rejected', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_REASON: say why the upload is rejected, in ten characters or more; the officer is told' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.legacy_fee_upload SET state = 'REJECTED', decided_by = who, decided_office = 'bursar', decided_at = now(), decision_note = left(v_reason, 500)
     WHERE id = u.id RETURNING * INTO u;
    PERFORM platform.tell_person(u.uploaded_by, 'OLD_FEES_UPLOAD_DECIDED', NULL,
                jsonb_build_object('REF', u.ref, 'DECISION', 'rejected', 'ROWS', u.row_count, 'NOTE', u.decision_note),
                'old-fees-upload:' || u.ref || ':decided');
    RETURN u;
END $$;

COMMENT ON FUNCTION finance.legacy_upload_open(text, text, jsonb) IS 'V607: the Students Account Officer opens an Old Fees History upload for the Bursar''s approval (with the item codes read from the file)';
COMMENT ON FUNCTION finance.legacy_upload_add(uuid, jsonb) IS 'V607: a part of the upload''s rows (1 to 2,000), by the officer who opened it, before it is sent';
COMMENT ON FUNCTION finance.legacy_upload_submit(uuid) IS 'V607: the upload sent to the Bursar — PENDING, its rows fixed, its tally kept, the Bursar told';
COMMENT ON FUNCTION finance.legacy_upload_withdraw(uuid, text) IS 'V607: the officer withdraws an upload not yet decided';
COMMENT ON FUNCTION finance.legacy_upload_check(uuid, integer, integer) IS 'V607: what approving would do — the import run on the parts given and undone; the Bursar''s';
COMMENT ON FUNCTION finance.legacy_upload_approve(uuid, text, integer) IS 'V607: the Bursar approves an upload — the item codes set, then the parts loaded a few at a time with finance.import_legacy_payments (APPROVING until the last, then APPROVED); never the Bursar''s own upload';
COMMENT ON FUNCTION finance.legacy_upload_reject(uuid, text) IS 'V607: the Bursar rejects an upload waiting for approval, with the reason; the officer is told';

-- ── the notices ──────────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('OLD_FEES_UPLOAD_WAITING', 'Old fees upload waiting for approval',
 'To the Bursar when the Students Account Officer sends an Old Fees History upload for approval: nothing of it is on the records until approved',
 'Old fees upload [REF] waits for your approval',
 E'Dear [FIRST_NAME],\n\nThe Students Account Officer has sent an Old Fees History upload for your approval: [REF] ([FILE]), [ROWS] row(s) for [STUDENTS] student(s), sessions [SESSIONS]. Nothing of it is on the records until you approve it.\n\nOpen Old Fees History on the portal to check it, then approve or reject it.',
 NULL,
 'Old fees upload waits for approval',
 'Upload [REF]: [ROWS] row(s) for [STUDENTS] student(s), sessions [SESSIONS], waits for your approval on Old Fees History.',
 ARRAY['FIRST_NAME', 'REF', 'FILE', 'ROWS', 'STUDENTS', 'SESSIONS'], false, 'NORMAL'),
('OLD_FEES_UPLOAD_DECIDED', 'Old fees upload decided',
 'To the Students Account Officer when the Bursar approves (and loads) or rejects an Old Fees History upload the officer sent',
 'Old fees upload [REF] [DECISION]',
 E'Dear [FIRST_NAME],\n\nYour Old Fees History upload [REF] ([ROWS] row(s)) was [DECISION] by the Bursar.\n\nThe Bursar''s note: [NOTE]\n\nOpen Old Fees History on the portal for the details.',
 NULL,
 'Old fees upload [DECISION]',
 'Your upload [REF] ([ROWS] row(s)) was [DECISION] by the Bursar. Note: [NOTE]',
 ARRAY['FIRST_NAME', 'REF', 'DECISION', 'ROWS', 'NOTE'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

COMMIT;
