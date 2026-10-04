-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V323 — old-portal GST payments reconciled into the GST/EPS entitlement
--
--   Why students who paid GST on the old portal read NOT PAID on this one: the entitlement (V314,
--   finance.gst_entitlement) reads confirmed references of purpose 'GST fee <session>' on finance.payment_reference
--   — the one ledger — and nothing else. The only door old-portal money has into that ledger is the Old Fees History
--   import (V087/V304), which records a row as SCHOOL FEES unless its Note names GST, and matches a student by
--   matriculation or admission number alone. The file the Bursary loaded on 15 September 2026 carried school fees
--   only: every one of its 67,490 rows is "School fees (legacy)". No old-portal GST payment exists on the ledger, so
--   wherever a GST fee is stated the student is asked to pay again.
--
--   The fix is not to flip a flag. A verified old-portal payment is a real historical payment: it is staged as the
--   old portal recorded it (immutable, with its own reference, date, status and amount), matched to the current
--   student by strong identifiers only, validated against the fee the Bursar stated FOR THAT SESSION, checked for
--   duplicates against the ledger and the staging, and — only then, on the Bursary's word — written to the SAME
--   ledger as a confirmed reference of purpose 'GST fee <session>', channel 'Legacy', dated when the student paid,
--   carrying the old reference. From there every reader is unchanged: the entitlement, the registration gate, the
--   CBT eligibility, the dashboards, the student's screen. Nothing is duplicated: no second ledger, no flag, no new
--   payment attempt; what cannot be reconciled waits in an exception queue for a Finance officer, with the reason.
--
--     1  finance.legacy_gst_import — one run: its reference GST-MIGRATION-<session>-<n>, the file, who, the counts.
--     2  finance.legacy_gst_payment — the staged row as the old portal had it; written once; unique on the source
--        transaction id and on the source reference, so the same old payment can never be staged twice.
--     3  finance.legacy_gst_reconciliation — what the portal made of it: the match (student, method, confidence,
--        candidates), the validation (status, reason), the link to the ledger row it became, who reconciled or
--        resolved it and why. Audited.
--     4  finance.legacy_student_crosswalk — an old-portal student id to a current student, for the old portal's
--        own ids; set by the Bursary, audited, never by name.
--     5  finance.legacy_payment_type_map — which old-portal payment types are the GST fee (GST, GNS, General
--        Studies; EPS and Entrepreneurship too, because one GST payment covers both — V314's rule).
--     6  the functions: stage, match, validate, apply, resolve, summary; and the entitlement and the population
--        now say where a payment came from (CURRENT_PORTAL or LEGACY_PORTAL) and when it was made.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V323: old-portal GST payments reconciled into the entitlement', true);

-- ── 1 · the run ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.legacy_gst_import (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference        text NOT NULL UNIQUE,
    source_system    text NOT NULL DEFAULT 'LEGACY_PORTAL',
    file_name        text NULL,
    session          text NULL,
    uploaded_by      uuid NULL,
    uploader_office  text NULL,
    uploaded_at      timestamptz NOT NULL DEFAULT now(),
    total_rows       int NOT NULL DEFAULT 0,
    staged           int NOT NULL DEFAULT 0,
    already_staged   int NOT NULL DEFAULT 0,
    skipped          int NOT NULL DEFAULT 0,
    status           text NOT NULL DEFAULT 'STAGED' CHECK (status IN ('STAGED', 'APPLIED')),
    applied_at       timestamptz NULL,
    applied_by       uuid NULL,
    note             text NULL
);
COMMENT ON TABLE finance.legacy_gst_import IS 'One upload of old-portal GST payments (V323): its reference, file, uploader, counts, and whether its reconciled rows have been applied to the ledger.';
SELECT audit.attach('finance.legacy_gst_import');

-- ── 2 · the staged payment, as the old portal had it ─────────────────────────────────────────
CREATE TABLE finance.legacy_gst_payment (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    import_id             uuid NOT NULL REFERENCES finance.legacy_gst_import(id),
    row_no                int NOT NULL,
    source_system         text NOT NULL DEFAULT 'LEGACY_PORTAL',
    source_transaction_id text NULL,
    source_reference      text NULL,
    gateway               text NULL,
    gateway_reference     text NULL,
    source_student_id     text NULL,
    matric_no             text NULL,
    jamb_no               text NULL,
    application_no        text NULL,
    student_name          text NULL,
    payment_type          text NULL,
    amount                numeric(12,2) NULL,
    currency              text NOT NULL DEFAULT 'NGN',
    paid_at               timestamptz NULL,
    paid_at_text          text NULL,
    session               text NULL,
    semester              int NULL,
    legacy_status         text NULL,
    normalized_status     text NOT NULL DEFAULT 'UNKNOWN' CHECK (normalized_status IN ('SUCCESS', 'FAILED', 'REVERSED', 'REFUNDED', 'PENDING', 'UNKNOWN')),
    raw                   jsonb NOT NULL,
    imported_at           timestamptz NOT NULL DEFAULT now(),
    imported_by           uuid NULL
);
COMMENT ON TABLE finance.legacy_gst_payment IS 'An old-portal GST payment as the old portal recorded it (V323): reference, date, amount, status, the identifiers it carried, and the whole row. Written once; never corrected in place — the reconciliation says what the portal made of it.';
CREATE UNIQUE INDEX ux_legacy_gst_source_tx ON finance.legacy_gst_payment (source_system, upper(source_transaction_id)) WHERE source_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX ux_legacy_gst_source_ref ON finance.legacy_gst_payment (source_system, upper(source_reference)) WHERE source_reference IS NOT NULL;
CREATE INDEX ix_legacy_gst_import ON finance.legacy_gst_payment (import_id, row_no);
CREATE INDEX ix_legacy_gst_matric ON finance.legacy_gst_payment (upper(matric_no)) WHERE matric_no IS NOT NULL;
CREATE INDEX ix_legacy_gst_jamb ON finance.legacy_gst_payment (upper(jamb_no)) WHERE jamb_no IS NOT NULL;
CREATE INDEX ix_legacy_gst_session ON finance.legacy_gst_payment (session, normalized_status);
SELECT audit.attach('finance.legacy_gst_payment');

CREATE OR REPLACE FUNCTION finance.legacy_gst_payment_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'LEGACY_PAYMENT_WRITTEN_ONCE: an old-portal payment is staged once and never corrected in place; the reconciliation record carries what the portal made of it' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_legacy_gst_payment_written_once BEFORE UPDATE OR DELETE ON finance.legacy_gst_payment
    FOR EACH ROW EXECUTE FUNCTION finance.legacy_gst_payment_written_once();

-- ── 3 · what the portal made of it ───────────────────────────────────────────────────────────
CREATE TABLE finance.legacy_gst_reconciliation (
    payment_id           uuid PRIMARY KEY REFERENCES finance.legacy_gst_payment(id),
    import_id            uuid NOT NULL REFERENCES finance.legacy_gst_import(id),
    status               text NOT NULL DEFAULT 'UNPROCESSED' CHECK (status IN ('UNPROCESSED', 'MATCHED', 'RECONCILED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE', 'UNMATCHED')),
    reason_code          text NULL,
    reason               text NULL,
    student_id           uuid NULL REFERENCES people.student(id),
    match_method         text NULL CHECK (match_method IS NULL OR match_method IN ('STUDENT_ID', 'MATRIC_NO', 'JAMB_NO', 'APPLICATION_NO', 'LEGACY_ID_CROSSWALK', 'MANUAL')),
    match_confidence     text NULL CHECK (match_confidence IS NULL OR match_confidence IN ('HIGH', 'REVIEW', 'MANUAL')),
    candidates           jsonb NULL,
    fee_amount           numeric(12,2) NULL,
    payment_reference_id uuid NULL UNIQUE REFERENCES finance.payment_reference(id),
    reconciled_at        timestamptz NULL,
    reconciled_by        uuid NULL,
    reconciled_office    text NULL,
    resolved_at          timestamptz NULL,
    resolved_by          uuid NULL,
    resolved_office      text NULL,
    override_reason      text NULL,
    updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.legacy_gst_reconciliation IS 'The portal''s judgement on a staged old-portal GST payment (V323): the student it was matched to and by what, its validation and the reason, the ledger row it became, and who reconciled or resolved it. The answer to "which old-portal transaction gave this student their entitlement".';
CREATE INDEX ix_legacy_gst_rec_import ON finance.legacy_gst_reconciliation (import_id, status);
CREATE INDEX ix_legacy_gst_rec_status ON finance.legacy_gst_reconciliation (status);
CREATE INDEX ix_legacy_gst_rec_student ON finance.legacy_gst_reconciliation (student_id) WHERE student_id IS NOT NULL;
SELECT audit.attach('finance.legacy_gst_reconciliation');

CREATE OR REPLACE FUNCTION finance.legacy_gst_rec_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_legacy_gst_rec_touch BEFORE UPDATE ON finance.legacy_gst_reconciliation FOR EACH ROW EXECUTE FUNCTION finance.legacy_gst_rec_touch();

-- ── 4 · the old portal's own student ids, mapped by the Bursary ──────────────────────────────
CREATE TABLE finance.legacy_student_crosswalk (
    legacy_student_id text PRIMARY KEY,
    student_id        uuid NOT NULL REFERENCES people.student(id),
    source_system     text NOT NULL DEFAULT 'LEGACY_PORTAL',
    note              text NULL,
    set_by            uuid NULL,
    set_at            timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.legacy_student_crosswalk IS 'An old-portal student id to the current student (V323), set by the Bursary on the record; a payment carrying only the old id matches through it, never through a name.';
CREATE INDEX ix_legacy_crosswalk_student ON finance.legacy_student_crosswalk (student_id);
SELECT audit.attach('finance.legacy_student_crosswalk');

-- ── 5 · which old-portal payment types are the GST fee ───────────────────────────────────────
CREATE TABLE finance.legacy_payment_type_map (
    pattern  text PRIMARY KEY,
    maps_to  text NOT NULL CHECK (maps_to IN ('GST')),
    label    text NOT NULL,
    active   boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE finance.legacy_payment_type_map IS 'Old-portal payment types read as the GST fee (V323): matched case-insensitively against the type the old portal recorded. EPS types map to the same fee because one GST payment covers GST and EPS (finance.gst_setting.covers_eps).';
INSERT INTO finance.legacy_payment_type_map (pattern, maps_to, label) VALUES
    ('(^|[^a-z])gst([^a-z]|$)',            'GST', 'GST payment'),
    ('(^|[^a-z])gns([^a-z]|$)',            'GST', 'GNS payment'),
    ('general\s*stud',                     'GST', 'General Studies fee'),
    ('(^|[^a-z])eps([^a-z]|$)',            'GST', 'EPS payment (covered by the GST fee)'),
    ('entrepreneur',                       'GST', 'Entrepreneurship Studies fee (covered by the GST fee)');
SELECT audit.attach('finance.legacy_payment_type_map');

CREATE OR REPLACE FUNCTION finance.legacy_gst_type_of(p_type text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT m.maps_to FROM finance.legacy_payment_type_map m WHERE m.active AND coalesce(p_type, '') ~* m.pattern ORDER BY length(m.pattern) DESC LIMIT 1
$$;

/* the old portal's status words, read into the ledger's own: only SUCCESS establishes anything */
CREATE OR REPLACE FUNCTION finance.legacy_status_of(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN t ~ '(refund)' THEN 'REFUNDED'
        WHEN t ~ '(revers|chargeback|charge back)' THEN 'REVERSED'
        WHEN t ~ '(fail|declin|cancel|abandon|expir|error|unsuccess|not paid|unpaid|invalid)' THEN 'FAILED'
        WHEN t ~ '(pending|processing|initiat|await|incomplete|partial)' THEN 'PENDING'
        WHEN t ~ '(success|paid|complete|verified|settled|approved|confirmed|ok|^1$|^true$|^yes$)' THEN 'SUCCESS'
        WHEN t = '' THEN 'UNKNOWN'
        ELSE 'UNKNOWN' END
      FROM (SELECT lower(btrim(coalesce(p, ''))) AS t) x
$$;

/* a session as the old portal wrote it — 2025/2026, 2025-2026, 2025 / 26, 2025 — read as YYYY/YYYY */
CREATE OR REPLACE FUNCTION finance.legacy_session_of(p text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text := btrim(coalesce(p, '')); y int; y2 text;
BEGIN
    IF t ~ '^[0-9]{4}\s*[/_-]\s*[0-9]{4}$' THEN
        RETURN substring(t from '^[0-9]{4}') || '/' || substring(t from '[0-9]{4}$');
    ELSIF t ~ '^[0-9]{4}\s*[/_-]\s*[0-9]{2}$' THEN
        y := substring(t from '^[0-9]{4}')::int; y2 := substring(t from '[0-9]{2}$');
        RETURN y::text || '/' || left(y::text, 2) || y2;
    ELSIF t ~ '^[0-9]{4}$' THEN
        y := t::int; RETURN y::text || '/' || (y + 1)::text;
    END IF;
    RETURN NULL;
END $$;

-- ── 6 · the run's reference ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.legacy_gst_new_import(p_file text, p_session text, p_note text)
RETURNS finance.legacy_gst_import LANGUAGE plpgsql AS $$
DECLARE i finance.legacy_gst_import; v_scope text := coalesce(replace(p_session, '/', '-'), 'ALL');
BEGIN
    INSERT INTO finance.legacy_gst_import (reference, file_name, session, uploaded_by, uploader_office, note)
    VALUES ('GST-MIGRATION-' || v_scope || '-' || lpad(platform.next_number('legacy_gst_import', 'UNIVERSITY', coalesce(p_session, 'ALL'))::text, 5, '0'),
            nullif(btrim(coalesce(p_file, '')), ''), p_session, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''),
            nullif(btrim(coalesce(p_note, '')), ''))
    RETURNING * INTO i;
    RETURN i;
END $$;

-- ── 7 · staging: the rows as the file gives them; a source id or reference already staged is never staged twice ──
CREATE OR REPLACE FUNCTION finance.legacy_gst_stage(p_import uuid, p_rows jsonb)
RETURNS TABLE (total_rows int, staged int, already_staged int, skipped int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; n int := 0; ns int := 0; na int := 0; nk int := 0; v_id uuid; v_tx text; v_ref text; v_cnt int;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: old-portal payments are staged by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RAISE EXCEPTION 'LEGACY_ROWS_REQUIRED: the payments are rows' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        n := n + 1;
        v_tx := nullif(btrim(coalesce(r ->> 'transactionId', '')), '');
        v_ref := nullif(btrim(coalesce(r ->> 'reference', '')), '');
        IF v_tx IS NULL AND v_ref IS NULL THEN nk := nk + 1; CONTINUE; END IF;   -- a row with no identity of its own cannot be reconciled
        -- the same old payment staged before (this file or an earlier one)
        IF EXISTS (SELECT 1 FROM finance.legacy_gst_payment p
                    WHERE (v_tx IS NOT NULL AND upper(p.source_transaction_id) = upper(v_tx)) OR (v_ref IS NOT NULL AND upper(p.source_reference) = upper(v_ref))) THEN
            na := na + 1; CONTINUE;
        END IF;
        INSERT INTO finance.legacy_gst_payment (import_id, row_no, source_transaction_id, source_reference, gateway, gateway_reference, source_student_id, matric_no, jamb_no,
                                                application_no, student_name, payment_type, amount, paid_at, paid_at_text, session, semester, legacy_status, normalized_status, raw, imported_by)
        VALUES (p_import, coalesce((r ->> 'row')::int, n), v_tx, v_ref, nullif(btrim(coalesce(r ->> 'gateway', '')), ''), nullif(btrim(coalesce(r ->> 'gatewayReference', '')), ''),
                nullif(btrim(coalesce(r ->> 'legacyStudentId', '')), ''), nullif(upper(btrim(coalesce(r ->> 'matric', ''))), ''), nullif(upper(btrim(coalesce(r ->> 'jamb', ''))), ''),
                nullif(upper(btrim(coalesce(r ->> 'applicationNo', ''))), ''), nullif(btrim(coalesce(r ->> 'name', '')), ''), nullif(btrim(coalesce(r ->> 'paymentType', '')), ''),
                nullif(regexp_replace(coalesce(r ->> 'amount', ''), '[^0-9.]', '', 'g'), '')::numeric,
                finance.legacy_date(r ->> 'paidAt'), nullif(btrim(coalesce(r ->> 'paidAt', '')), ''),
                finance.legacy_session_of(r ->> 'session'),
                CASE WHEN nullif(regexp_replace(coalesce(r ->> 'semester', ''), '[^0-9]', '', 'g'), '')::int IN (1, 2, 3) THEN nullif(regexp_replace(coalesce(r ->> 'semester', ''), '[^0-9]', '', 'g'), '')::int END,
                nullif(btrim(coalesce(r ->> 'status', '')), ''), finance.legacy_status_of(r ->> 'status'), r, v_actor)
        RETURNING id INTO v_id;
        INSERT INTO finance.legacy_gst_reconciliation (payment_id, import_id) VALUES (v_id, p_import);
        ns := ns + 1;
    END LOOP;
    UPDATE finance.legacy_gst_import i SET total_rows = i.total_rows + n, staged = i.staged + ns, already_staged = i.already_staged + na, skipped = i.skipped + nk WHERE i.id = p_import;
    GET DIAGNOSTICS v_cnt = ROW_COUNT;
    RETURN QUERY SELECT n, ns, na, nk;
END $$;

-- ── 8 · matching: strong identifiers only, in order; one student or nothing ──────────────────
CREATE OR REPLACE FUNCTION finance.legacy_gst_match(p_import uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    WITH p AS (
        SELECT lp.* FROM finance.legacy_gst_payment lp JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = lp.id
         WHERE lp.import_id = p_import AND rc.status = 'UNPROCESSED'),
    hits AS (
        SELECT p.id, s.id AS student_id, 'STUDENT_ID'::text AS method, 1 AS rank FROM p JOIN people.student s ON p.source_student_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' AND s.id = p.source_student_id::uuid
        UNION ALL
        SELECT p.id, s.id, 'MATRIC_NO', 2 FROM p JOIN people.student s ON p.matric_no IS NOT NULL AND upper(s.matric_no) = p.matric_no
        UNION ALL
        SELECT p.id, s.id, 'JAMB_NO', 3 FROM p JOIN people.student s ON p.jamb_no IS NOT NULL AND upper(s.jamb_reg_no) = p.jamb_no
        UNION ALL
        SELECT p.id, s.id, 'APPLICATION_NO', 4 FROM p JOIN people.student s ON p.application_no IS NOT NULL AND (upper(s.admission_no) = p.application_no OR upper(s.matric_no) = p.application_no)
        UNION ALL
        SELECT p.id, x.student_id, 'LEGACY_ID_CROSSWALK', 5 FROM p JOIN finance.legacy_student_crosswalk x ON p.source_student_id IS NOT NULL AND x.legacy_student_id = upper(p.source_student_id)),
    agg AS (
        SELECT h.id, count(DISTINCT h.student_id) AS students, (array_agg(h.student_id ORDER BY h.rank))[1] AS student_id, (array_agg(h.method ORDER BY h.rank))[1] AS method,
               jsonb_agg(DISTINCT jsonb_build_object('student_id', h.student_id, 'method', h.method)) AS cands
          FROM hits h GROUP BY h.id),
    judged AS (
        SELECT p.id,
               CASE WHEN a.students = 1 THEN 'MATCHED' WHEN a.students > 1 THEN 'REQUIRES_REVIEW' ELSE 'UNMATCHED' END AS status,
               CASE WHEN a.students = 1 THEN NULL WHEN a.students > 1 THEN 'AMBIGUOUS_STUDENT' ELSE 'STUDENT_NOT_FOUND' END AS code,
               CASE WHEN a.students = 1 THEN NULL WHEN a.students > 1 THEN 'the identifiers on the row point to ' || a.students || ' different students' ELSE 'no student carries the matriculation, JAMB or application number on the row, and the old id is not on the crosswalk' END AS reason,
               CASE WHEN a.students = 1 THEN a.student_id END AS student_id,
               CASE WHEN a.students = 1 THEN a.method END AS method,
               CASE WHEN a.students = 1 THEN 'HIGH' END AS confidence,
               CASE WHEN a.students > 1 THEN (SELECT jsonb_agg(jsonb_build_object('student_id', s.id, 'number', coalesce(s.matric_no, s.admission_no), 'name', s.surname || ', ' || s.other_names, 'programme', s.programme_code, 'method', c ->> 'method'))
                                               FROM jsonb_array_elements(a.cands) c JOIN people.student s ON s.id = (c ->> 'student_id')::uuid)
                    WHEN a.students IS NULL AND p.student_name IS NOT NULL THEN
                         -- suggestions only, by the whole name, never a match: an officer decides
                         (SELECT jsonb_agg(jsonb_build_object('student_id', s.id, 'number', coalesce(s.matric_no, s.admission_no), 'name', s.surname || ', ' || s.other_names, 'programme', s.programme_code, 'method', 'NAME_SUGGESTION'))
                            FROM (SELECT s.* FROM people.student s
                                   WHERE lower(regexp_replace(s.surname || ' ' || s.other_names, '[^a-z0-9 ]', '', 'gi')) = lower(regexp_replace(p.student_name, '[^a-z0-9 ]', '', 'gi'))
                                      OR lower(regexp_replace(s.other_names || ' ' || s.surname, '[^a-z0-9 ]', '', 'gi')) = lower(regexp_replace(p.student_name, '[^a-z0-9 ]', '', 'gi'))
                                   LIMIT 5) s)
                    END AS cands
          FROM p LEFT JOIN agg a ON a.id = p.id)
    UPDATE finance.legacy_gst_reconciliation rc
       SET status = j.status, reason_code = j.code, reason = j.reason, student_id = j.student_id, match_method = j.method, match_confidence = j.confidence, candidates = j.cands
      FROM judged j WHERE rc.payment_id = j.id;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION finance.legacy_gst_match(uuid) IS
  'Matches every unprocessed row of a run to a current student by strong identifiers only (V323): the current student id, the matriculation number, the JAMB number, the admission/application number, the Bursary''s crosswalk — in that order. One student: MATCHED. Several: REQUIRES_REVIEW with the candidates. None: UNMATCHED, with name suggestions an officer may act on. A name alone never matches.';

-- ── 9 · validation: status, type, session, amount against THAT session''s fee, duplicates ───
CREATE OR REPLACE FUNCTION finance.legacy_gst_validate_one(p_payment uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; f record; v_dup uuid; v_other uuid; v_code text; v_reason text; v_status text; v_fee numeric := NULL;
BEGIN
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    IF rc.student_id IS NULL OR rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE') THEN RETURN; END IF;
    IF rc.status = 'RECONCILED' THEN RETURN; END IF;
    v_status := 'MATCHED'; v_code := NULL; v_reason := NULL;
    IF p.normalized_status <> 'SUCCESS' THEN
        v_status := 'REJECTED';
        v_code := CASE p.normalized_status WHEN 'REFUNDED' THEN 'PAYMENT_REFUNDED' WHEN 'REVERSED' THEN 'PAYMENT_REVERSED' WHEN 'PENDING' THEN 'PAYMENT_PENDING' WHEN 'FAILED' THEN 'PAYMENT_FAILED' ELSE 'PAYMENT_STATUS_UNKNOWN' END;
        v_reason := 'the old portal recorded the payment as "' || coalesce(p.legacy_status, '—') || '"; only a successful payment establishes anything';
    ELSIF finance.legacy_gst_type_of(p.payment_type) IS NULL THEN
        v_status := 'REJECTED'; v_code := 'UNKNOWN_PAYMENT_TYPE';
        v_reason := 'the payment type "' || coalesce(p.payment_type, '—') || '" is not one the Bursary reads as the GST fee';
    ELSIF p.session IS NULL THEN
        v_status := 'REJECTED'; v_code := 'MISSING_SESSION'; v_reason := 'the row names no session the payment belongs to';
    ELSIF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p.session) THEN
        v_status := 'REJECTED'; v_code := 'INVALID_SESSION'; v_reason := 'the session ' || p.session || ' is not on the calendar';
    ELSIF p.amount IS NULL OR p.amount <= 0 THEN
        v_status := 'REJECTED'; v_code := 'MISSING_AMOUNT'; v_reason := 'the row carries no amount';
    ELSE
        -- an entitlement already on the ledger for this student and session: the new portal''s, or an earlier reconciliation''s
        SELECT r.id INTO v_dup FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
         ORDER BY r.confirmed_at LIMIT 1;
        IF v_dup IS NOT NULL THEN
            v_status := 'DUPLICATE'; v_code := 'EXISTING_ENTITLEMENT';
            v_reason := 'the student already holds a confirmed GST payment for ' || p.session || ' on the ledger (' || (SELECT reference || ' · ' || coalesce(channel, '') FROM finance.payment_reference WHERE id = v_dup) || '); one entitlement stands, both histories are kept';
        ELSE
            SELECT * INTO f FROM finance.gst_fee_for(rc.student_id, p.session);
            IF f.stated THEN v_fee := f.amount; END IF;
            IF NOT f.stated THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'NO_FEE_FOR_SESSION';
                v_reason := 'no GST fee is stated for ' || p.session || ' for this student, so the amount cannot be judged; the Bursar states the fee of that session first';
            ELSIF p.amount < f.amount THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'PARTIAL_PAYMENT';
                v_reason := 'the old portal shows NGN ' || to_char(p.amount, 'FM999,999,990.00') || ' against a fee of NGN ' || to_char(f.amount, 'FM999,999,990.00') || ' for ' || p.session;
            ELSIF p.amount > f.amount THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'AMOUNT_ABOVE_FEE';
                v_reason := 'the old portal shows NGN ' || to_char(p.amount, 'FM999,999,990.00') || ' against a fee of NGN ' || to_char(f.amount, 'FM999,999,990.00') || ' for ' || p.session;
            END IF;
            -- the same money may already sit on the ledger as school fees from the Old Fees History import: an officer decides
            IF v_status = 'MATCHED' THEN
                SELECT r.id INTO v_other FROM finance.payment_reference r
                 WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%'
                   AND r.amount = p.amount AND (p.paid_at IS NULL OR r.confirmed_at::date = p.paid_at::date)
                 LIMIT 1;
                IF v_other IS NOT NULL THEN
                    v_status := 'REQUIRES_REVIEW'; v_code := 'POSSIBLE_RELABEL';
                    v_reason := 'the same amount on the same day already sits on the ledger as school fees imported from the old portal (' || (SELECT reference FROM finance.payment_reference WHERE id = v_other) || '); relabel it as the GST fee, or record this payment separately';
                END IF;
            END IF;
        END IF;
    END IF;
    UPDATE finance.legacy_gst_reconciliation
       SET status = v_status, reason_code = v_code, reason = v_reason, fee_amount = coalesce(v_fee, fee_amount)
     WHERE payment_id = p_payment;
END $$;

CREATE OR REPLACE FUNCTION finance.legacy_gst_validate(p_import uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT payment_id FROM finance.legacy_gst_reconciliation WHERE import_id = p_import AND status = 'MATCHED' AND student_id IS NOT NULL LOOP
        PERFORM finance.legacy_gst_validate_one(r.payment_id);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- ── 10 · applying: the entitlement on the one ledger, with the old reference and the old date ──
CREATE OR REPLACE FUNCTION finance.legacy_gst_ledger_reference(p finance.legacy_gst_payment)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT 'MOAUM-LEG-GST-' || left(regexp_replace(upper(coalesce(p.source_transaction_id, p.source_reference)), '[^0-9A-Z]', '', 'g'), 40)
$$;

CREATE OR REPLACE FUNCTION finance.legacy_gst_apply(p_import uuid)
RETURNS TABLE (reconciled int, duplicates int, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        i finance.legacy_gst_import; n int; nd int; v_amount numeric;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is applied by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO i FROM finance.legacy_gst_import WHERE id = p_import FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_IMPORT_NOT_FOUND: no such run' USING ERRCODE = '23503'; END IF;
    -- judged again at the moment of writing: the ledger may have moved since the preview
    PERFORM finance.legacy_gst_validate(p_import);
    -- the ledger row: the same row the gateway would have written, carrying the old reference and the old date
    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
    SELECT rc.student_id, p.session, finance.legacy_gst_ledger_reference(p), 'GST fee ' || p.session, p.amount,
           coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), v_actor, 'Legacy', 'LEG-' || finance.legacy_gst_ledger_reference(p),
           'Old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || coalesce(' (' || p.payment_type || ')', '')
           || CASE WHEN p.paid_at IS NULL THEN ', undated' ELSE ' of ' || to_char(p.paid_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') END
           || ', reconciled under ' || i.reference
      FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment p ON p.id = rc.payment_id
     WHERE rc.import_id = p_import AND rc.status = 'MATCHED' AND rc.student_id IS NOT NULL
    ON CONFLICT (reference) DO NOTHING;
    -- linked by the reference the old payment maps to, for the same student as the GST fee of that session
    UPDATE finance.legacy_gst_reconciliation rc
       SET status = 'RECONCILED', reason_code = NULL, reason = NULL, payment_reference_id = r.id, reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office
      FROM finance.legacy_gst_payment p, finance.payment_reference r
     WHERE rc.payment_id = p.id AND rc.import_id = p_import AND rc.status = 'MATCHED' AND rc.student_id IS NOT NULL
       AND r.reference = finance.legacy_gst_ledger_reference(p) AND r.student_id = rc.student_id AND r.purpose = 'GST fee ' || p.session AND r.channel = 'Legacy'
       AND NOT EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation o WHERE o.payment_reference_id = r.id AND o.payment_id <> rc.payment_id);
    GET DIAGNOSTICS n = ROW_COUNT;
    -- a reference already on the ledger in another name or for another purpose: a duplicate, never a second payment
    UPDATE finance.legacy_gst_reconciliation rc
       SET status = 'DUPLICATE', reason_code = 'REFERENCE_ON_LEDGER', reason = 'a ledger row already carries this old-portal reference for another student or purpose'
     WHERE rc.import_id = p_import AND rc.status = 'MATCHED' AND rc.student_id IS NOT NULL;
    GET DIAGNOSTICS nd = ROW_COUNT;
    SELECT coalesce(sum(r.amount), 0) INTO v_amount FROM finance.legacy_gst_reconciliation rc JOIN finance.payment_reference r ON r.id = rc.payment_reference_id
     WHERE rc.import_id = p_import AND rc.status = 'RECONCILED';
    UPDATE finance.legacy_gst_import SET status = 'APPLIED', applied_at = now(), applied_by = v_actor WHERE id = p_import;
    RETURN QUERY SELECT n, nd, v_amount;
END $$;
COMMENT ON FUNCTION finance.legacy_gst_apply(uuid) IS
  'Writes every validated row of a run to the ledger (V323): a confirmed finance.payment_reference of purpose ''GST fee <session>'', channel Legacy, dated when the student paid, carrying the old-portal reference — the same row the gateway would have written — and links it. Validated again first; idempotent; a reference already on the ledger is a duplicate, never a second payment.';

-- ── 11 · the officer's hand: match, reconcile (with an override reason), relabel, reject ─────
CREATE OR REPLACE FUNCTION finance.legacy_gst_resolve(p_payment uuid, p_action text, p_student uuid, p_reason text)
RETURNS finance.legacy_gst_reconciliation LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; i finance.legacy_gst_import; v_act text := upper(btrim(coalesce(p_action, ''))); v_other uuid; v_id uuid; v_ref text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is resolved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_PAYMENT_NOT_FOUND: no such old-portal payment' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment FOR UPDATE;
    SELECT * INTO i FROM finance.legacy_gst_import WHERE id = rc.import_id;
    IF rc.status = 'RECONCILED' THEN RAISE EXCEPTION 'LEGACY_ALREADY_RECONCILED: this payment is already on the ledger as %', (SELECT reference FROM finance.payment_reference WHERE id = rc.payment_reference_id) USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'LEGACY_REASON_REQUIRED: resolving a payment names its reason' USING ERRCODE = '23514'; END IF;

    IF v_act = 'MATCH' THEN
        IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: name the current student' USING ERRCODE = '23514'; END IF;
        -- the identifiers on the row must not point at somebody else: ownership is never moved by guesswork
        IF (p.matric_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = p.matric_no AND s.id <> p_student))
           OR (p.jamb_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.jamb_reg_no) = p.jamb_no AND s.id <> p_student)) THEN
            RAISE EXCEPTION 'LEGACY_IDENTIFIER_CONFLICT: the matriculation or JAMB number on the row belongs to another student; a payment is not moved to a student its identifiers do not name' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'MATCHED', reason_code = NULL, reason = NULL, student_id = p_student, match_method = 'MANUAL', match_confidence = 'MANUAL',
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
        PERFORM finance.legacy_gst_validate_one(p_payment);
        -- the old id, once resolved by hand, is on the crosswalk for the next file
        IF p.source_student_id IS NOT NULL AND p.source_student_id !~ '^[0-9a-f]{8}-' THEN
            INSERT INTO finance.legacy_student_crosswalk (legacy_student_id, student_id, note, set_by)
            VALUES (upper(p.source_student_id), p_student, 'set when ' || coalesce(p.source_reference, p.source_transaction_id) || ' was resolved: ' || btrim(p_reason), v_actor)
            ON CONFLICT (legacy_student_id) DO NOTHING;
        END IF;
    ELSIF v_act = 'RECONCILE' THEN
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        IF rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW') THEN RAISE EXCEPTION 'LEGACY_STATE: a % payment is not reconciled by hand', lower(replace(rc.status, '_', ' ')) USING ERRCODE = '23514'; END IF;
        IF p.normalized_status <> 'SUCCESS' THEN RAISE EXCEPTION 'LEGACY_NOT_SUCCESSFUL: the old portal did not record this payment as successful; it cannot establish an entitlement' USING ERRCODE = '23514'; END IF;
        IF p.session IS NULL OR p.amount IS NULL OR p.amount <= 0 THEN RAISE EXCEPTION 'LEGACY_INCOMPLETE: the row needs a session and an amount' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))) THEN
            RAISE EXCEPTION 'LEGACY_DUPLICATE: the student already holds a confirmed GST payment for %', p.session USING ERRCODE = '23514';
        END IF;
        v_ref := finance.legacy_gst_ledger_reference(p);
        IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN RAISE EXCEPTION 'LEGACY_DUPLICATE: a ledger row already carries the old-portal reference %', v_ref USING ERRCODE = '23514'; END IF;
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (rc.student_id, p.session, v_ref, 'GST fee ' || p.session, p.amount, coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), v_actor, 'Legacy', 'LEG-' || v_ref,
                'Old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', reconciled by hand under ' || i.reference || ': ' || btrim(p_reason))
        RETURNING id INTO v_id;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = NULL, reason = NULL, payment_reference_id = v_id, reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office,
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'RELABEL' THEN
        -- the money is already on the ledger as school fees from the old portal: it was for the GST fee
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        SELECT r.id INTO v_other FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%' AND r.amount = p.amount
         ORDER BY abs(extract(epoch FROM (r.confirmed_at - coalesce(p.paid_at, r.confirmed_at)))) LIMIT 1;
        IF v_other IS NULL THEN RAISE EXCEPTION 'LEGACY_NOTHING_TO_RELABEL: no old-portal school-fees row of that amount is on the ledger for the student and session' USING ERRCODE = '23514'; END IF;
        UPDATE finance.payment_reference
           SET purpose = 'GST fee ' || p.session,
               note = coalesce(note || ' · ', '') || 'relabelled from school fees: old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', under ' || i.reference || ': ' || btrim(p_reason)
         WHERE id = v_other;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = 'RELABELLED', reason = 'the old-portal school-fees row was relabelled as the GST fee', payment_reference_id = v_other,
               reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office, resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'REJECT' THEN
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'REJECTED', reason_code = 'REJECTED_BY_OFFICER', reason = btrim(p_reason), resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSE
        RAISE EXCEPTION 'LEGACY_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    RETURN rc;
END $$;

-- ── 12 · the figures: by run or by session, with the totals that must reconcile ──────────────
CREATE OR REPLACE FUNCTION finance.legacy_gst_summary(p_import uuid, p_session text)
RETURNS TABLE (legacy_rows bigint, successful bigint, failed bigint, gst_rows bigint, unprocessed bigint, matched bigint, reconciled bigint, requires_review bigint, duplicates bigint, rejected bigint, unmatched bigint,
               legacy_amount numeric, legacy_successful_amount numeric, reconciled_amount numeric, variance numeric, legacy_students bigint, reconciled_students bigint, entitled_students bigint)
LANGUAGE sql STABLE AS $$
    WITH p AS (SELECT lp.*, rc.status, rc.student_id AS matched_student, rc.payment_reference_id
                 FROM finance.legacy_gst_payment lp JOIN finance.legacy_gst_reconciliation rc ON rc.payment_id = lp.id
                WHERE (p_import IS NULL OR lp.import_id = p_import) AND (p_session IS NULL OR lp.session = p_session)),
    gst AS (SELECT * FROM p WHERE finance.legacy_gst_type_of(payment_type) IS NOT NULL),
    led AS (SELECT coalesce(sum(r.amount), 0) AS amt, count(DISTINCT r.student_id) AS students FROM p JOIN finance.payment_reference r ON r.id = p.payment_reference_id WHERE p.status = 'RECONCILED')
    SELECT count(*), count(*) FILTER (WHERE normalized_status = 'SUCCESS'), count(*) FILTER (WHERE normalized_status <> 'SUCCESS'), (SELECT count(*) FROM gst),
           count(*) FILTER (WHERE status = 'UNPROCESSED'), count(*) FILTER (WHERE status = 'MATCHED'), count(*) FILTER (WHERE status = 'RECONCILED'), count(*) FILTER (WHERE status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE status = 'DUPLICATE'), count(*) FILTER (WHERE status = 'REJECTED'), count(*) FILTER (WHERE status = 'UNMATCHED'),
           coalesce(sum(amount), 0), coalesce(sum(amount) FILTER (WHERE normalized_status = 'SUCCESS' AND finance.legacy_gst_type_of(payment_type) IS NOT NULL), 0),
           led.amt, coalesce(sum(amount) FILTER (WHERE normalized_status = 'SUCCESS' AND finance.legacy_gst_type_of(payment_type) IS NOT NULL), 0) - led.amt,
           count(DISTINCT coalesce(matric_no, jamb_no, application_no, source_student_id)) FILTER (WHERE normalized_status = 'SUCCESS'),
           led.students,
           (SELECT count(DISTINCT r.student_id) FROM finance.payment_reference r WHERE r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND (p_session IS NULL OR r.session = p_session))
      FROM p CROSS JOIN led GROUP BY led.amt, led.students
    UNION ALL
    SELECT 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
           (SELECT count(DISTINCT r.student_id) FROM finance.payment_reference r WHERE r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND (p_session IS NULL OR r.session = p_session))
     WHERE NOT EXISTS (SELECT 1 FROM p)
$$;

-- ── 13 · where a payment came from, for the student and the office ───────────────────────────
DROP FUNCTION IF EXISTS finance.gst_entitlement(uuid, text);
CREATE FUNCTION finance.gst_entitlement(p_student uuid, p_session text)
RETURNS TABLE (required boolean, stated boolean, fee numeric, covers_eps boolean, paid numeric, entitled boolean, state text,
               reference text, receipt_no text, paid_at timestamptz, open_reference text, open_amount numeric, open_expires_at timestamptz,
               source text, channel text, legacy_reference text)
LANGUAGE sql STABLE AS $$
    WITH f AS (SELECT * FROM finance.gst_fee_for(p_student, p_session)),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    pays AS (SELECT r.id, r.reference, r.receipt_no, r.amount, r.confirmed_at, r.channel
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))),
    agg AS (SELECT coalesce(sum(amount), 0) AS paid, max(confirmed_at) AS paid_at, count(*) AS n FROM pays),
    last AS (SELECT p.id, p.reference, p.receipt_no, p.channel FROM pays p ORDER BY p.confirmed_at DESC LIMIT 1),
    open AS (SELECT r.reference, r.amount, r.expires_at
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()
              ORDER BY r.generated_at DESC LIMIT 1),
    req AS (SELECT finance.gst_required(p_student, p_session) AS required)
    SELECT req.required, f.stated, f.amount, cfg.covers_eps, agg.paid,
           (agg.n > 0 OR (f.stated AND f.amount = 0)) AS entitled,
           CASE WHEN agg.n > 0 OR (f.stated AND f.amount = 0) THEN 'PAID'
                WHEN NOT req.required THEN 'NOT_REQUIRED'
                WHEN NOT f.stated THEN 'NOT_STATED'
                WHEN open.reference IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           last.reference, last.receipt_no, agg.paid_at, open.reference, open.amount, open.expires_at,
           CASE WHEN last.id IS NULL THEN NULL WHEN last.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           last.channel,
           (SELECT coalesce(lp.source_reference, lp.source_transaction_id) FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment lp ON lp.id = rc.payment_id WHERE rc.payment_reference_id = last.id)
      FROM f CROSS JOIN cfg CROSS JOIN agg CROSS JOIN req LEFT JOIN last ON true LEFT JOIN open ON true
$$;
COMMENT ON FUNCTION finance.gst_entitlement(uuid, text) IS
  'The authoritative answer (V314, source added by V323): entitled when a CONFIRMED reference of purpose ''GST fee <session>'' stands on finance.payment_reference for the student, net of approved or paid refunds — whether the gateway, the bank, the Bursary desk or a reconciled old-portal payment wrote it. Says where the payment came from and the old-portal reference when it was reconciled.';

DROP FUNCTION IF EXISTS finance.gst_population(text, int);
CREATE FUNCTION finance.gst_population(p_session text, p_semester int)
RETURNS TABLE (student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
               programme_code text, programme text, level int, status text, entry_mode text,
               required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamptz,
               gst_registered boolean, eps_registered boolean, gst_courses int, eps_courses int, registered_at timestamptz, pay_source text)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex,
               p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.programme_code, p.name AS programme,
               s.current_level AS level, s.status, s.entry_mode
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = d.faculty_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    req AS (SELECT DISTINCT co.programme_code, co.level
              FROM catalogue.course_offer co JOIN catalogue.course c ON c.code = co.course_code AND c.kind = 'GST' AND c.state <> 'ENDED'),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM finance.gst_fee f WHERE f.session = p_session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    pays AS (SELECT r.student_id, sum(r.amount) AS paid, max(r.confirmed_at) AS paid_at, count(*) AS n,
                    (array_agg(r.reference ORDER BY r.confirmed_at DESC))[1] AS reference,
                    (array_agg(r.channel ORDER BY r.confirmed_at DESC))[1] AS channel
               FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
              GROUP BY r.student_id),
    pend AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()),
    regs AS (SELECT cr.student_id,
                    count(*) FILTER (WHERE c.general_office = 'GST') AS gst_courses,
                    count(*) FILTER (WHERE c.general_office = 'EPS') AS eps_courses,
                    min(cr.submitted_at) AS registered_at
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
               JOIN catalogue.offering o ON o.id = e.offering_id
               JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
              WHERE cr.session = p_session AND (p_semester IS NULL OR cr.semester = p_semester)
              GROUP BY cr.student_id)
    SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme,
           b.level, b.status, b.entry_mode,
           (rq.programme_code IS NOT NULL),
           coalesce(fr.amount, 0), (fr.id IS NOT NULL),
           coalesce(py.paid, 0),
           (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0)),
           CASE WHEN coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0) THEN 'PAID'
                WHEN rq.programme_code IS NULL THEN 'NOT_REQUIRED'
                WHEN fr.id IS NULL THEN 'NOT_STATED'
                WHEN pd.student_id IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           py.reference, py.paid_at,
           coalesce(rg.gst_courses, 0) > 0, coalesce(rg.eps_courses, 0) > 0, coalesce(rg.gst_courses, 0)::int, coalesce(rg.eps_courses, 0)::int, rg.registered_at,
           CASE WHEN py.n IS NULL THEN NULL WHEN py.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END
      FROM base b
      LEFT JOIN req rq ON rq.programme_code = b.programme_code AND rq.level = b.level
      LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                          WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                            AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                          ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                          LIMIT 1) fr ON true
      LEFT JOIN pays py ON py.student_id = b.id
      LEFT JOIN pend pd ON pd.student_id = b.id
      LEFT JOIN regs rg ON rg.student_id = b.id
$$;
COMMENT ON FUNCTION finance.gst_population(text, int) IS
  'One row per undergraduate of the register for a session (V314; the source of the payment added by V323): whether their programme requires GST/EPS courses at their level, the GST fee the Bursar stated for them, what they paid and from which portal, whether they are entitled, and their GST and EPS registrations.';

-- ── 14 · the Super Administrator's data reset clears the staged old-portal payments with the ledger and the students they hang on ──
-- Restated as V322 left it, with the four V323 tables cleared before finance.payment_reference (the staged rows are written once; the reset runs under the maintenance flag their trigger honours).
CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    -- what is about to go, for the record the caller gets back
    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    -- ── V292: everything added since V108 that hangs on what the reset clears, children first ──
    -- the write-once histories (screening, PUTME, deferment, matric, external examiners) are cleared
    -- under the maintenance flag every one of their triggers honours; it is lifted again below
    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;   -- the deferment and its fee refer to each other
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;   -- an issued document and its transcript request refer to each other (V262)
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

    -- credentials and graduation hung on students
    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;

    -- course spaces (V035) and service requests (V036)
    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    -- health records
    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES, a setting, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    -- library loans (the catalogue of items/copies is kept)
    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    -- hostel allocations (the halls and rooms are kept)
    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- the student's services, timetables, cards
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    -- the Bursary's transaction trail (gateway credentials/billers, a setting, are kept)
    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.legacy_gst_reconciliation;   -- V323: the reconciliation hangs on the ledger rows and the students
    DELETE FROM finance.legacy_gst_payment;
    DELETE FROM finance.legacy_gst_import;
    DELETE FROM finance.legacy_student_crosswalk;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    -- the student's account and identity on the portal
    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    -- staff profiles a member of staff entered about themselves (V107); the
    -- person and their offices are kept, only the CV they typed is cleared
    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    -- results, registration and the uploaded course structure
    DELETE FROM assessment.sheet_upload;   -- V318: the uploads on behalf hang on the sheets
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;         -- V322: the examinations hang on the questions, the offerings and the students
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    -- the register itself
    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    -- credentials issued (the signing key, a setting, is kept)
    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    -- the admissions intake (the admission POLICY and O'Level grading, settings, are kept)
    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;   -- V106: hangs on application, must go first
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    -- the O'Level sittings are derived from the attachments and reference them,
    -- so they (and the grades that hang on them) go before the attachments.
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $$;

COMMIT;
