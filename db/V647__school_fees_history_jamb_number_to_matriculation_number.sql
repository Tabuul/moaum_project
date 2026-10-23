-- V647: school-fees history, JAMB number to matriculation number — the University's master prompt of 23 October 2026 ("SCHOOL FEES
-- HISTORY — JAMB NUMBER TO MATRICULATION NUMBER RECONCILIATION": a historical school-fees payment whose "matriculation number" is the
-- student's JAMB registration number, paid before matriculation, is the student's — never rejected, never paid twice).
--   The old portal named a payer by whatever number they had: a JAMB registration number before matriculation. The old-fees import
--   (finance.import_legacy_payments, V498) found the student by the matriculation or admission number alone and dropped every other
--   row as "no student": on the Bursary's export of 14 October, 922 school-fees rows named by a JAMB-shaped number (46 of them a
--   student on the live-shaped copy), with GST, hostel and deferment payments beside them.
--   · people.student_identifier: every number a student is known by, read where each is kept (matriculation number, an old one,
--     admission, JAMB on the record and the candidate, application) — the crosswalk, never a copy.
--   · people.resolve_student: the student a number names, in the order the brief sets — the record's id, the matriculation number,
--     an old one, the admission number, the JAMB registration number, the application number; a JAMB or application number naming
--     several students resolves none (AMBIGUOUS); a name never matches.
--   · finance.import_legacy_payments restated exactly as it stands but for the lookup: a row is the student's by that resolution
--     (an applicant's payment — Post-UTME, application, admission checking, screening, acceptance — is not resolved by JAMB: it is
--     the admissions'); paid under another number, the number is kept beside the payment on finance.payment_identity (the type, the
--     student, the matriculation number then, the match, the source, the batch); the payment is the same payment, its reference,
--     amount, date and channel as the file gives them, counted once by its old payment number as before.
--   · finance.legacy_payment_held: a row the records give no student (or several) is held, keyed by its old payment number, not
--     dropped; the rows of the uploads the Bursar approved (V607) that were dropped so are held now.
--   · finance.fee_history_recon_batch (PAY-RECON/YYYY/NNNNNN): finance.fee_history_scan reads every held payment's number again
--     (MATCHED, AMBIGUOUS, NO_MATCH, ALREADY_RECONCILED, DUPLICATE, INVALID); the Students Account Officer or a Bursary officer
--     initiates a batch of the matched (fee_history_initiate), a Bursar officer who did not initiate it approves — each payment
--     recorded once by the import, its number kept — or rejects it with a reason (fee_history_decide); the initiator withdraws.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V647: school-fees history, JAMB number to matriculation number (the University, 23 October 2026)', true);

-- ── every number a student is known by, read from where each is kept: the crosswalk ──
CREATE OR REPLACE VIEW people.student_identifier AS
    SELECT s.id AS student_id, 'MATRIC_NUMBER'::text AS identifier_type, upper(s.matric_no) AS identifier_value, 'people.student'::text AS source, true AS is_primary
      FROM people.student s WHERE s.matric_no IS NOT NULL AND s.duplicate_of IS NULL
    UNION ALL
    SELECT a.student_id, 'MATRIC_NUMBER', upper(a.old_no), 'people.matric_alias', false
      FROM people.matric_alias a JOIN people.student s ON s.id = a.student_id AND s.duplicate_of IS NULL
    UNION ALL
    SELECT s.id, 'ADMISSION_NUMBER', upper(s.admission_no), 'people.student', s.matric_no IS NULL
      FROM people.student s WHERE s.admission_no IS NOT NULL AND s.duplicate_of IS NULL
    UNION ALL
    SELECT s.id, 'JAMB_NUMBER', upper(s.jamb_reg_no), 'people.student', false
      FROM people.student s WHERE s.jamb_reg_no IS NOT NULL AND s.duplicate_of IS NULL
    UNION ALL
    SELECT s.id, 'JAMB_NUMBER', upper(c.jamb_reg_no), 'admissions.candidate', false
      FROM people.student s JOIN admissions.candidate c ON c.id = s.candidate_id
     WHERE c.jamb_reg_no IS NOT NULL AND s.duplicate_of IS NULL AND upper(c.jamb_reg_no) IS DISTINCT FROM upper(s.jamb_reg_no)
    UNION ALL
    SELECT s.id, 'APPLICATION_NUMBER', upper(ap.application_no), 'admissions.application', false
      FROM people.student s JOIN admissions.application ap ON ap.candidate_id = s.candidate_id
     WHERE ap.application_no IS NOT NULL AND s.duplicate_of IS NULL;
COMMENT ON VIEW people.student_identifier IS
  'V645: every number a student is known by — the matriculation number (primary), an old one a correction replaced, the admission number, the JAMB registration number (on the record and on the candidate), the application number — read from the tables that keep each; never a second copy. Searching any of them finds the same student.';

-- the shape a payer's number has, when the records hold no student for it
CREATE OR REPLACE FUNCTION people.identifier_type_of(p_identifier text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN 'STUDENT_ID'
        WHEN upper(btrim(coalesce(p_identifier, ''))) ~ '^[0-9]{8,14}[A-Z]{2,3}$' THEN 'JAMB_NUMBER'
        WHEN upper(btrim(coalesce(p_identifier, ''))) ~ '^MOAUM/ADM/' THEN 'ADMISSION_NUMBER'
        WHEN upper(btrim(coalesce(p_identifier, ''))) ~ '/' THEN 'MATRIC_NUMBER'
        WHEN upper(btrim(coalesce(p_identifier, ''))) ~ '^(APP|MOAUM-APP|APPL)' THEN 'APPLICATION_NUMBER'
        ELSE 'OTHER' END
$$;

-- ── the student a payer's number names: the authoritative records, in a fixed order, a JAMB number only when it names one ──
CREATE OR REPLACE FUNCTION people.resolve_student(p_identifier text, p_beyond_matric boolean DEFAULT true)
RETURNS TABLE (student_id uuid, method text, identifier_type text, status text, candidates uuid[])
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v text := upper(btrim(coalesce(p_identifier, ''))); ids uuid[];
BEGIN
    IF v = '' THEN
        RETURN QUERY SELECT NULL::uuid, NULL::text, 'OTHER'::text, 'INVALID'::text, '{}'::uuid[]; RETURN;
    END IF;
    -- 1. the record's own id
    IF v ~* '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' THEN
        SELECT array_agg(s.id) INTO ids FROM people.student s WHERE s.id = lower(v)::uuid AND s.duplicate_of IS NULL;
        IF cardinality(ids) = 1 THEN RETURN QUERY SELECT ids[1], 'MATCHED_BY_STUDENT_ID'::text, 'STUDENT_ID'::text, 'MATCHED'::text, ids; RETURN; END IF;
    END IF;
    -- 2. the matriculation number (unique), then one a correction replaced
    SELECT array_agg(s.id) INTO ids FROM people.student s WHERE upper(s.matric_no) = v AND s.duplicate_of IS NULL;
    IF cardinality(ids) = 1 THEN RETURN QUERY SELECT ids[1], 'MATCHED_BY_MATRIC'::text, 'MATRIC_NUMBER'::text, 'MATCHED'::text, ids; RETURN; END IF;
    SELECT array_agg(DISTINCT a.student_id) INTO ids FROM people.matric_alias a JOIN people.student s ON s.id = a.student_id AND s.duplicate_of IS NULL
     WHERE upper(a.old_no) = v;
    IF cardinality(ids) = 1 THEN RETURN QUERY SELECT ids[1], 'MATCHED_BY_MATRIC'::text, 'MATRIC_NUMBER'::text, 'MATCHED'::text, ids; RETURN; END IF;
    -- 3. the admission number (unique)
    SELECT array_agg(s.id) INTO ids FROM people.student s WHERE upper(s.admission_no) = v AND s.duplicate_of IS NULL;
    IF cardinality(ids) = 1 THEN RETURN QUERY SELECT ids[1], 'MATCHED_BY_ADMISSION'::text, 'ADMISSION_NUMBER'::text, 'MATCHED'::text, ids; RETURN; END IF;
    IF NOT p_beyond_matric THEN
        RETURN QUERY SELECT NULL::uuid, NULL::text, people.identifier_type_of(v), 'NO_MATCH'::text, '{}'::uuid[]; RETURN;
    END IF;
    -- 4. the JAMB registration number: on the record or on the candidate it was admitted from — one student, never several
    SELECT array_agg(DISTINCT x.id) INTO ids FROM (
        SELECT s.id FROM people.student s WHERE upper(s.jamb_reg_no) = v AND s.duplicate_of IS NULL
        UNION SELECT s.id FROM people.student s JOIN admissions.candidate c ON c.id = s.candidate_id WHERE upper(c.jamb_reg_no) = v AND s.duplicate_of IS NULL) x;
    IF cardinality(ids) = 1 THEN RETURN QUERY SELECT ids[1], 'MATCHED_BY_JAMB'::text, 'JAMB_NUMBER'::text, 'MATCHED'::text, ids; RETURN; END IF;
    IF cardinality(ids) > 1 THEN RETURN QUERY SELECT NULL::uuid, NULL::text, 'JAMB_NUMBER'::text, 'AMBIGUOUS'::text, ids; RETURN; END IF;
    -- 5. the application number
    SELECT array_agg(DISTINCT s.id) INTO ids FROM people.student s JOIN admissions.application ap ON ap.candidate_id = s.candidate_id
     WHERE ap.application_no = v AND s.duplicate_of IS NULL;
    IF cardinality(ids) = 1 THEN RETURN QUERY SELECT ids[1], 'MATCHED_BY_APPLICATION'::text, 'APPLICATION_NUMBER'::text, 'MATCHED'::text, ids; RETURN; END IF;
    IF cardinality(ids) > 1 THEN RETURN QUERY SELECT NULL::uuid, NULL::text, 'APPLICATION_NUMBER'::text, 'AMBIGUOUS'::text, ids; RETURN; END IF;
    RETURN QUERY SELECT NULL::uuid, NULL::text, people.identifier_type_of(v), 'NO_MATCH'::text, '{}'::uuid[];
END $$;
COMMENT ON FUNCTION people.resolve_student(text, boolean) IS
  'V645: the student a payer''s number names, by the authoritative records in order — the record''s id, the matriculation number, an old one a correction replaced, the admission number, then (p_beyond_matric) the JAMB registration number and the application number. A JAMB or application number that names several students is AMBIGUOUS and resolves none; a name never matches anything.';

-- ── what an old-portal row is for, read as the import reads it ──
CREATE OR REPLACE FUNCTION finance.legacy_row_purpose(r jsonb)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    WITH t AS (SELECT finance.legacy_item_of(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', '')) AS item,
                      btrim(coalesce(r->>'note', '')) AS note),
         x AS (SELECT CASE WHEN t.item <> '' THEN t.item ELSE t.note END AS text FROM t)
    SELECT CASE
        WHEN x.text ~* '(post.?utme|post.?de|application|admission check|screening|acceptance)' THEN 'APPLICANT'
        WHEN coalesce(finance.legacy_gst_type_of(x.text), '') = 'GST' THEN 'GST'
        WHEN x.text = '' OR x.text ~* '(school|tuition|semester fee|session fee)' THEN 'SCHOOL_FEES'
        ELSE 'OTHER' END
      FROM x
$$;

-- ── the payment's identity as it was paid and as it was resolved, kept beside the payment, never in its place ──
CREATE TABLE finance.payment_identity (
    payment_id uuid PRIMARY KEY REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    original_identifier text NOT NULL,
    original_identifier_type text NOT NULL CHECK (original_identifier_type IN ('MATRIC_NUMBER', 'JAMB_NUMBER', 'APPLICATION_NUMBER', 'ADMISSION_NUMBER', 'STUDENT_ID', 'LEGACY_STUDENT_ID', 'OTHER')),
    resolved_student_id uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    resolved_matric_no text,
    match_method text NOT NULL CHECK (match_method IN ('MATCHED_BY_STUDENT_ID', 'MATCHED_BY_MATRIC', 'MATCHED_BY_ADMISSION', 'MATCHED_BY_JAMB', 'MATCHED_BY_APPLICATION')),
    source text NOT NULL,
    batch_ref text,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid
);
CREATE INDEX ix_payment_identity_student ON finance.payment_identity (resolved_student_id);
CREATE INDEX ix_payment_identity_original ON finance.payment_identity (upper(original_identifier));
SELECT audit.attach('finance.payment_identity');
COMMENT ON TABLE finance.payment_identity IS
  'V645: how a payment made under another number reached its student — the number the old portal named the payer by (a JAMB registration, application or admission number, an old matriculation number), its type, the student it resolved to, their matriculation number then, the match, the source and the reconciliation batch. The payment itself is unchanged: the same reference, amount, date, channel and receipt.';

-- ── an old-portal payment the records held no student for, or several: held for the reconciliation, never dropped ──
CREATE TABLE finance.legacy_payment_held (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    row_key text NOT NULL UNIQUE,
    row_data jsonb NOT NULL,
    original_identifier text NOT NULL,
    identifier_type text NOT NULL,
    purpose text NOT NULL CHECK (purpose IN ('SCHOOL_FEES', 'GST', 'OTHER')),
    session text,
    semester integer,
    amount numeric(14, 2),
    payref text,
    status text NOT NULL CHECK (status IN ('NO_MATCH', 'AMBIGUOUS', 'INVALID', 'RECONCILED')),
    candidates uuid[] NOT NULL DEFAULT '{}',
    first_seen timestamptz NOT NULL DEFAULT now(),
    last_seen timestamptz NOT NULL DEFAULT now(),
    seen_count integer NOT NULL DEFAULT 1,
    payment_id uuid REFERENCES finance.payment_reference(id) ON DELETE SET NULL,
    batch_ref text,
    reconciled_at timestamptz
);
CREATE INDEX ix_legacy_held_status ON finance.legacy_payment_held (status, session);
CREATE INDEX ix_legacy_held_identifier ON finance.legacy_payment_held (upper(original_identifier));
SELECT audit.attach('finance.legacy_payment_held');
COMMENT ON TABLE finance.legacy_payment_held IS
  'V645: an old-portal payment row the import could not give to one student — its number names none on the portal yet (NO_MATCH), several (AMBIGUOUS), or the row is incomplete (INVALID) — kept as the file gave it, keyed by its old payment number, until a reconciliation records it (RECONCILED). Applicant payments (Post-UTME, application, admission checking, screening, acceptance) are the admissions'' and are not held.';

CREATE OR REPLACE FUNCTION finance.legacy_hold(r jsonb, p_identifier text, p_purpose text, p_type text, p_status text, p_candidates uuid[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_payref text := nullif(upper(btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', r->>'payref', ''))), '');
        v_session text := nullif(btrim(coalesce(r->>'session', '')), '');
        v_amount numeric := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;
BEGIN
    IF p_purpose = 'APPLICANT' THEN RETURN; END IF;
    INSERT INTO finance.legacy_payment_held (row_key, row_data, original_identifier, identifier_type, purpose, session, semester, amount, payref, status, candidates)
    VALUES (coalesce('PAYREF:' || v_payref, 'ROW:' || md5(r::text)), r, upper(btrim(p_identifier)), coalesce(p_type, 'OTHER'), p_purpose, v_session,
            finance.legacy_semester(coalesce(r->>'semester', r->>'sem')), v_amount, v_payref,
            CASE WHEN v_session IS NULL OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN 'INVALID' ELSE p_status END, coalesce(p_candidates, '{}'))
    ON CONFLICT (row_key) DO UPDATE SET last_seen = now(), seen_count = finance.legacy_payment_held.seen_count + 1,
        status = CASE WHEN finance.legacy_payment_held.status = 'RECONCILED' THEN 'RECONCILED' ELSE EXCLUDED.status END,
        candidates = EXCLUDED.candidates;
END $$;

-- ── the reconciliation: a batch of held payments their numbers now resolve, initiated by one officer, decided by a Bursar officer ──
CREATE TABLE finance.fee_history_recon_batch (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref text NOT NULL UNIQUE,
    state text NOT NULL CHECK (state IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'WITHDRAWN')),
    held_ids uuid[] NOT NULL,
    reason text NOT NULL,
    scanned integer NOT NULL DEFAULT 0,
    matched integer NOT NULL DEFAULT 0,
    ambiguous integer NOT NULL DEFAULT 0,
    unmatched integer NOT NULL DEFAULT 0,
    duplicate integer NOT NULL DEFAULT 0,
    amount numeric(16, 2) NOT NULL DEFAULT 0,
    initiated_by uuid NOT NULL,
    initiated_office text NOT NULL,
    initiated_at timestamptz NOT NULL DEFAULT now(),
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    decision_note text,
    reconciled integer,
    reconciled_amount numeric(16, 2),
    result jsonb,
    CONSTRAINT ck_fhr_two_officers CHECK (decided_by IS NULL OR decided_by IS DISTINCT FROM initiated_by)
);
SELECT audit.attach('finance.fee_history_recon_batch');
COMMENT ON TABLE finance.fee_history_recon_batch IS
  'V645: a school-fees history reconciliation — PAY-RECON/YYYY/NNNNNN — the held old-portal payments whose numbers now name one student, initiated by the Students Account Officer or a Bursary officer and decided by a Bursar officer who did not initiate it; on approval each is recorded once, as the import records a payment, with its original number kept.';

-- the held payments as they stand now: each one's number resolved again, and what the reconciliation would do with it
CREATE OR REPLACE FUNCTION finance.fee_history_scan(p_session text, p_category text, p_purpose text, p_q text, p_fac text, p_dept text, p_prog text)
RETURNS TABLE (id uuid, original_identifier text, identifier_type text, purpose text, session text, semester integer, amount numeric, payref text,
               held_status text, category text, student_id uuid, student_name text, matric_no text, programme text, faculty_code text, dept_code text,
               candidates integer, first_seen timestamptz, last_seen timestamptz, payment_id uuid, batch_ref text)
LANGUAGE sql
STABLE
AS $$
    WITH h AS (SELECT * FROM finance.legacy_payment_held x
                WHERE (p_session IS NULL OR x.session = p_session) AND (p_purpose IS NULL OR x.purpose = p_purpose)
                  AND (p_q IS NULL OR x.original_identifier ILIKE '%' || p_q || '%' OR x.payref ILIKE '%' || p_q || '%')),
         r AS (SELECT h.*, rs.student_id AS sid, rs.status AS rstatus, cardinality(rs.candidates) AS ncand
                 FROM h CROSS JOIN LATERAL people.resolve_student(h.original_identifier, true) rs),
         c AS (SELECT r.*,
                      CASE WHEN r.status = 'RECONCILED' THEN 'ALREADY_RECONCILED'
                           WHEN r.status = 'INVALID' OR r.amount IS NULL OR r.amount <= 0 THEN 'INVALID'
                           WHEN r.payref IS NOT NULL AND (EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = r.payref)
                                                          OR EXISTS (SELECT 1 FROM finance.legacy_payref_withdrawn w WHERE w.payref = r.payref)) THEN 'DUPLICATE'
                           WHEN r.sid IS NOT NULL THEN 'MATCHED'
                           WHEN r.rstatus = 'AMBIGUOUS' THEN 'AMBIGUOUS'
                           ELSE 'NO_MATCH' END AS cat
                 FROM r)
    SELECT c.id, c.original_identifier, c.identifier_type, c.purpose, c.session, c.semester, c.amount, c.payref, c.status, c.cat,
           c.sid, CASE WHEN s.id IS NULL THEN NULL ELSE upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') END,
           s.matric_no, p.name, coalesce(d.faculty_code, p.faculty_code), p.dept_code, c.ncand, c.first_seen, c.last_seen, c.payment_id, c.batch_ref
      FROM c
      LEFT JOIN people.student s ON s.id = c.sid
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
     WHERE (p_category IS NULL OR c.cat = p_category)
       AND (p_fac IS NULL OR coalesce(d.faculty_code, p.faculty_code) = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
$$;

CREATE OR REPLACE FUNCTION finance.fee_history_initiate(p_ids uuid[], p_reason text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_ref text; v_ok uuid[]; n_scan int; n_amb int; n_none int; n_dup int; v_amount numeric;
BEGIN
    IF coalesce(v_office, '') NOT IN ('studentaccounts', 'bursar') THEN
        RAISE EXCEPTION 'FEE_RECON_OFFICE: a reconciliation is initiated by the Students Account Officer or the Bursary' USING ERRCODE = '42501';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'FEE_RECON_REASON: say why the payments are reconciled, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
        RAISE EXCEPTION 'FEE_RECON_NONE: choose the held payments to reconcile' USING ERRCODE = '23514';
    END IF;
    SELECT count(*), count(*) FILTER (WHERE s.category = 'AMBIGUOUS'), count(*) FILTER (WHERE s.category = 'NO_MATCH'),
           count(*) FILTER (WHERE s.category = 'DUPLICATE'), array_agg(s.id) FILTER (WHERE s.category = 'MATCHED'),
           coalesce(sum(s.amount) FILTER (WHERE s.category = 'MATCHED'), 0)
      INTO n_scan, n_amb, n_none, n_dup, v_ok, v_amount
      FROM finance.fee_history_scan(NULL, NULL, NULL, NULL, NULL, NULL, NULL) s WHERE s.id = ANY (p_ids);
    IF v_ok IS NULL OR cardinality(v_ok) = 0 THEN
        RAISE EXCEPTION 'FEE_RECON_NOTHING_MATCHED: none of the chosen payments names one student now' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM finance.fee_history_recon_batch b WHERE b.state = 'PENDING_APPROVAL' AND b.held_ids && v_ok) THEN
        RAISE EXCEPTION 'FEE_RECON_PENDING: some of these payments are in a reconciliation awaiting the Bursar already' USING ERRCODE = '23514';
    END IF;
    v_ref := 'PAY-RECON/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/'
             || lpad(platform.next_number('PAY_RECON', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 6, '0');
    INSERT INTO finance.fee_history_recon_batch (ref, state, held_ids, reason, scanned, matched, ambiguous, unmatched, duplicate, amount, initiated_by, initiated_office)
    VALUES (v_ref, 'PENDING_APPROVAL', v_ok, btrim(p_reason), n_scan, cardinality(v_ok), n_amb, n_none, n_dup, v_amount, v_actor, v_office);
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION finance.fee_history_decide(p_ref text, p_approve boolean, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        b finance.fee_history_recon_batch; v_rows jsonb; res record; n_rec int := 0; v_amt numeric := 0; h record; v_pid uuid;
BEGIN
    SELECT * INTO b FROM finance.fee_history_recon_batch WHERE ref = p_ref FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'FEE_RECON_NOT_FOUND: no reconciliation %', p_ref USING ERRCODE = 'P0002'; END IF;
    IF b.state <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'FEE_RECON_DECIDED: % is % already', p_ref, lower(b.state) USING ERRCODE = '23514'; END IF;
    IF coalesce(v_office, '') <> 'bursar' THEN
        RAISE EXCEPTION 'FEE_RECON_BURSAR: a reconciliation is decided by a Bursar officer' USING ERRCODE = '42501';
    END IF;
    IF v_actor IS NOT DISTINCT FROM b.initiated_by THEN
        RAISE EXCEPTION 'FEE_RECON_SAME_OFFICER: the officer who initiated a reconciliation does not decide it' USING ERRCODE = '23514';
    END IF;
    IF NOT p_approve THEN
        IF p_note IS NULL OR length(btrim(p_note)) < 10 THEN
            RAISE EXCEPTION 'FEE_RECON_REASON: say why it is rejected, in ten characters or more' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.fee_history_recon_batch SET state = 'REJECTED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note) WHERE id = b.id;
        RETURN jsonb_build_object('ref', p_ref, 'state', 'REJECTED');
    END IF;
    -- each payment again, as it stands now: still held, still naming one student
    SELECT jsonb_agg(x.row_data ORDER BY x.first_seen) INTO v_rows
      FROM finance.legacy_payment_held x
      JOIN finance.fee_history_scan(NULL, NULL, NULL, NULL, NULL, NULL, NULL) s ON s.id = x.id AND s.category = 'MATCHED'
     WHERE x.id = ANY (b.held_ids);
    IF v_rows IS NOT NULL THEN
        PERFORM set_config('moaum.recon_batch', p_ref, true);
        SELECT * INTO res FROM finance.import_legacy_payments(v_rows);
        PERFORM set_config('moaum.recon_batch', '', true);
    END IF;
    -- what each became: its payment (found by its old payment number, or the row the import marked)
    FOR h IN SELECT * FROM finance.legacy_payment_held x WHERE x.id = ANY (b.held_ids) LOOP
        v_pid := h.payment_id;
        IF v_pid IS NULL AND h.payref IS NOT NULL THEN
            SELECT pr.id INTO v_pid FROM finance.legacy_payref k JOIN finance.payment_reference pr ON pr.reference = k.reference WHERE k.payref = h.payref;
        END IF;
        IF v_pid IS NOT NULL THEN
            n_rec := n_rec + 1; v_amt := v_amt + coalesce(h.amount, 0);
            UPDATE finance.legacy_payment_held SET status = 'RECONCILED', payment_id = v_pid, batch_ref = p_ref, reconciled_at = coalesce(reconciled_at, now()) WHERE id = h.id;
        END IF;
    END LOOP;
    UPDATE finance.fee_history_recon_batch SET state = 'APPROVED', decided_by = v_actor, decided_office = v_office, decided_at = now(),
           decision_note = nullif(btrim(coalesce(p_note, '')), ''), reconciled = n_rec, reconciled_amount = v_amt,
           result = CASE WHEN res IS NULL THEN NULL ELSE to_jsonb(res) END
     WHERE id = b.id;
    RETURN jsonb_build_object('ref', p_ref, 'state', 'APPROVED', 'reconciled', n_rec, 'amount', v_amt);
END $$;

CREATE OR REPLACE FUNCTION finance.fee_history_withdraw(p_ref text, p_reason text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; b finance.fee_history_recon_batch;
BEGIN
    SELECT * INTO b FROM finance.fee_history_recon_batch WHERE ref = p_ref FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'FEE_RECON_NOT_FOUND: no reconciliation %', p_ref USING ERRCODE = 'P0002'; END IF;
    IF b.state <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'FEE_RECON_DECIDED: % is % already', p_ref, lower(b.state) USING ERRCODE = '23514'; END IF;
    IF v_actor IS DISTINCT FROM b.initiated_by THEN RAISE EXCEPTION 'FEE_RECON_OWN: only the officer who initiated it withdraws it' USING ERRCODE = '42501'; END IF;
    UPDATE finance.fee_history_recon_batch SET state = 'WITHDRAWN', decision_note = nullif(btrim(coalesce(p_reason, '')), ''), decided_at = now() WHERE id = b.id;
END $$;

CREATE OR REPLACE FUNCTION finance.fee_history_figures()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object(
        'held', (SELECT count(*) FROM finance.legacy_payment_held WHERE status <> 'RECONCILED'),
        'heldAmount', (SELECT coalesce(sum(amount), 0) FROM finance.legacy_payment_held WHERE status <> 'RECONCILED'),
        'byCategory', (SELECT coalesce(jsonb_object_agg(cat, n), '{}') FROM (SELECT s.category AS cat, count(*) AS n FROM finance.fee_history_scan(NULL, NULL, NULL, NULL, NULL, NULL, NULL) s GROUP BY 1) x),
        'reconciled', (SELECT count(*) FROM finance.legacy_payment_held WHERE status = 'RECONCILED'),
        'resolvedByJamb', (SELECT count(*) FROM finance.payment_identity WHERE match_method = 'MATCHED_BY_JAMB'),
        'pending', (SELECT count(*) FROM finance.fee_history_recon_batch WHERE state = 'PENDING_APPROVAL'))
$$;

CREATE OR REPLACE FUNCTION finance.import_legacy_payments(p_rows jsonb)
 RETURNS TABLE(rows integer, cleared integer, no_student integer, no_due integer, duplicates integer, duplicate_sample text, corrected integer, undated integer, matched integer, separate integer, taken_over integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_payref text; v_channel text; v_separate boolean; st people.student; ex finance.payment_reference;
        ph finance.payment_reference; gf record; rs record; v_purpose text;
        v_reason text := coalesce(nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), 'the old portal''s export names this payment');
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; nm int := 0; nsep int := 0; ntk int := 0;
        v_dups text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a legacy payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the payments are rows: matriculation number, session, amount (or blank for cleared in full)' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        v_session := btrim(coalesce(r->>'session', ''));
        IF v_matric = '' OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN CONTINUE; END IF;
        IF v_matric ~* '^mat(ric|no)' THEN CONTINUE; END IF;   -- a header row
        n := n + 1;

        -- V647: the payer's number resolved by the authoritative records — the matriculation number, an old one a correction
        -- replaced, the admission number, and (not for an applicant's payment) the JAMB registration or application number naming
        -- one student; a row the records give no student, or several, is held for the reconciliation instead of dropped
        v_purpose := finance.legacy_row_purpose(r);
        SELECT * INTO rs FROM people.resolve_student(v_matric, v_purpose <> 'APPLICANT');
        IF rs.student_id IS NULL THEN
            PERFORM finance.legacy_hold(r, v_matric, v_purpose, rs.identifier_type, rs.status, rs.candidates);
            nns := nns + 1; CONTINUE;
        END IF;
        SELECT * INTO st FROM people.student WHERE id = rs.student_id;
        v_sid := st.id;

        v_sem := finance.legacy_semester(coalesce(r->>'semester', r->>'sem'));

        -- what the money was for: the old portal's payment item when the file carries one (it is what it says);
        -- else the free-text Note, which is another purpose only when it names one
        v_item := finance.legacy_item_of(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', ''));   -- V498: a code is the item it names
        v_free := btrim(coalesce(r->>'note', ''));
        v_text := CASE WHEN v_item <> '' THEN v_item ELSE v_free END;
        v_gst := coalesce(finance.legacy_gst_type_of(v_text), '') = 'GST';
        v_other := NOT v_gst AND v_text <> '' AND v_text !~* '(school|tuition|semester fee|session fee)'
                   AND (v_item <> ''
                        OR v_text ~* '(^|[^a-z])(gst|gns|general stud|hostel|accommodation|transcript|library|deferment|transfer|wallet|acceptance|application|post-?utme|screening|medical|id card|convocation|late registration|clearance|siwes|certificate|verification|result|change of|add(-| )?drop|carry-?over|exam|fine|penalty|levy|dues|insurance|sports|development|laboratory|lab|studio|field|excursion|matriculation|thesis|project|supervision|bench|departmental|faculty)');
        v_slug := CASE WHEN v_gst THEN 'GST' WHEN v_other THEN left(regexp_replace(upper(v_text), '[^0-9A-Z]', '', 'g'), 20) END;

        v_key := replace(v_session, '/', '-');
        v_base0 := 'MOAUM-LEG-' || regexp_replace(v_matric, '[^0-9A-Z]', '', 'g') || '-' || v_key;      -- the whole-session school-fees reference
        v_base := v_base0 || CASE WHEN v_sem IS NOT NULL THEN '-S' || v_sem ELSE '' END;                -- this row's school-fees reference
        v_ref := v_base || CASE WHEN v_slug IS NOT NULL THEN '-' || v_slug ELSE '' END;

        -- the date the student paid, as the file gives it
        v_given := finance.legacy_date(coalesce(r->>'paidOn', r->>'paid_on', r->>'date'));
        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;

        -- the purpose as the ledger names it: the GST fee is one per session, and is what the GST desk counts
        v_tag := CASE WHEN v_gst THEN 'GST fee ' || v_session
                      ELSE (CASE WHEN v_other THEN v_text ELSE 'School fees' END) || ' (legacy)'
                           || CASE WHEN v_sem IS NOT NULL THEN ' · semester ' || v_sem ELSE '' END END;

        v_old_ref := btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', r->>'payref', ''));
        v_payref := nullif(upper(v_old_ref), '');
        v_channel := btrim(coalesce(r->>'channel', ''));
        v_note := coalesce(nullif(v_free, ''), 'Imported from the old portal')
                  || CASE WHEN v_channel <> '' AND v_channel !~* '^(old record|legacy)$' THEN ' · ' || v_channel ELSE '' END
                  || CASE WHEN v_old_ref <> '' THEN ' · old ref ' || v_old_ref ELSE '' END;
        v_separate := false;

        IF v_payref IS NOT NULL THEN
            -- V498: the old portal's payment number decides. Seen before: that payment again, never a second one
            -- V561: and a payment withdrawn because the bank never received it stays withdrawn when the export names it again
            IF EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = v_payref)
               OR EXISTS (SELECT 1 FROM finance.legacy_payref_withdrawn w WHERE w.payref = v_payref) THEN
                nd := nd + 1; v_dups := v_dups || v_payref;
                CONTINUE;
            END IF;
            -- a record already there for this key that this payment is (part of), recorded by an upload that did not keep the
            -- number: what the record holds beyond the payments already attached to it is this payment's amount (the same day
            -- first) — or, on a record the 15 Sep 2026 migration summed from several payments, has room for it. The same amount
            -- is within a naira: that migration kept whole naira (36,556.00 for the export's 36,555.80), as finance.fee_short reads
            SELECT x.* INTO ex FROM finance.payment_reference x
              LEFT JOIN LATERAL (SELECT count(*) AS n, coalesce(sum(coalesce(k.amount, x.amount)), 0) AS held
                                   FROM finance.legacy_payref k WHERE k.reference = x.reference) c ON true
             WHERE x.student_id = v_sid AND x.channel = 'Legacy'
               AND (x.reference = v_ref
                    OR (v_sem IS NULL AND v_slug IS NULL AND x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')))
               AND CASE WHEN v_amount IS NULL THEN c.n = 0
                        WHEN x.note ~ '^[2-9][0-9]* school-fees payment\(s\), migrated' THEN x.amount - c.held - v_amount > -1
                        ELSE abs(x.amount - c.held - v_amount) < 1 END
             ORDER BY (v_given IS NOT NULL AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date) DESC,
                      abs(x.amount - c.held - coalesce(v_amount, x.amount - c.held)), (x.reference = v_ref) DESC
             LIMIT 1;
            IF ex.id IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, ex.reference, coalesce(v_amount, ex.amount));
                -- a summed record keeps its day; one payment's record takes the day the file gives
                IF v_given IS NOT NULL AND ex.note !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'
                   AND (ex.confirmed_at AT TIME ZONE 'Africa/Lagos')::date IS DISTINCT FROM (v_given AT TIME ZONE 'Africa/Lagos')::date THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given,
                           note = CASE WHEN note LIKE '%old ref %' THEN note ELSE v_note END
                     WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSIF ex.note NOT LIKE '%old ref %' THEN
                    UPDATE finance.payment_reference SET note = v_note WHERE id = ex.id;
                END IF;
                nm := nm + 1;
                CONTINUE;
            END IF;
            -- the key is held by another payment (one with its own number, or another amount): this one is its own record
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN
                v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                v_separate := true;
            END IF;
        ELSE
            -- a file without payment numbers, read as before: already on record, skip and report; the amount is never touched
            -- (a wrong date is put right)
            SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
            IF ex.id IS NOT NULL THEN
                IF ex.channel = 'Legacy' AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
                   AND (v_amount IS NULL OR v_amount = ex.amount) THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSE
                    nd := nd + 1; v_dups := v_dups || v_ref;
                END IF;
                CONTINUE;
            END IF;

            -- V449: this row names no semester and no other item, and an earlier upload already put the same money on the ledger
            -- per semester (this reference with -S1, -S2 or -S3), for the same amount and, when the file gives one, the same day
            IF v_sem IS NULL AND v_slug IS NULL AND v_amount IS NOT NULL
               AND EXISTS (SELECT 1 FROM finance.payment_reference x
                            WHERE x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')
                              AND x.channel = 'Legacy' AND x.amount = v_amount
                              AND (v_given IS NULL OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date)) THEN
                nd := nd + 1; v_dups := v_dups || v_ref;
                CONTINUE;
            END IF;
        END IF;

        -- the same money already on the ledger as school fees from an upload that could not tell more — without this row's
        -- semester, or without its item: put the semester on it, or relabel it; one row, not two (never for a payment that is
        -- its own record beside another of the same key, and never a record that already carries a payment number)
        IF NOT v_separate AND v_amount IS NOT NULL AND (v_sem IS NOT NULL OR v_slug IS NOT NULL) THEN
            SELECT * INTO ex FROM finance.payment_reference x
             WHERE x.reference IN (v_base0, v_base) AND x.reference <> v_ref AND x.channel = 'Legacy'
               AND x.purpose LIKE 'School fees%' AND abs(x.amount - v_amount) < 1
               AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = x.reference)
             ORDER BY (x.reference = v_base) DESC LIMIT 1;
            IF ex.id IS NOT NULL THEN
                v_when := coalesce(v_given, ex.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, confirmed_at = v_when, expires_at = v_when,
                       note = CASE WHEN v_free <> '' OR v_old_ref <> '' THEN v_note ELSE note END
                 WHERE id = ex.id;
                IF v_payref IS NOT NULL THEN
                    INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, ex.amount);
                END IF;
                nfix := nfix + 1;
                CONTINUE;
            END IF;
        END IF;

        -- V502: the retired Payment History Upload recorded this payment under its number (as the reference, or the receipt) and
        -- no Old Fees History record has it: that record becomes the one this row makes — the item, the semester, the day paid,
        -- the session — so the payment is on record once. That door read every row as school fees whatever it was, without a
        -- semester, and dated a row it could not read with the day of the upload. Its ledger posting is let go (reversed and
        -- freed), so the sync posts the payment again under its item; a record something points at by its reference is left.
        IF v_payref IS NOT NULL THEN
            ph := NULL;
            SELECT x.* INTO ph FROM finance.payment_reference x
             WHERE x.student_id = v_sid AND x.reference NOT LIKE 'MOAUM-%' AND x.confirmed_at IS NOT NULL
               AND (upper(btrim(x.reference)) = v_payref OR upper(btrim(x.receipt_no)) = v_payref)
               AND NOT finance.payment_reference_linked(x.reference, x.id)
             ORDER BY (upper(btrim(x.reference)) = v_payref) DESC, x.reference
             LIMIT 1;
            IF ph.id IS NOT NULL THEN
                IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE (x.reference = v_ref OR x.receipt_no = 'LEG-' || v_ref) AND x.id <> ph.id) THEN
                    v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                END IF;
                SELECT * INTO gf FROM finance.gl_free_payment(ph.reference, ph.id, 'PAYMENT_CORRECTED',
                    'the payment ' || ph.reference || ' recorded by Payment History Upload is ' || v_tag || ' (' || v_ref || '): ' || v_reason);
                v_when := coalesce(v_given, ph.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, session = v_session,
                       amount = coalesce(v_amount, amount), confirmed_at = v_when, expires_at = v_when, channel = 'Legacy',
                       note = v_note || ' · first recorded by Payment History Upload as ' || ph.reference
                 WHERE id = ph.id;
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, coalesce(v_amount, ph.amount));
                INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action,
                                                           ledger_journal, reversal_journal, corrected_by, reason)
                VALUES (ph.id, ph.reference, v_ref, ph.purpose, v_tag, 'TAKEN_OVER', gf.journal, gf.reversal, v_actor, v_reason);
                ntk := ntk + 1;
                CONTINUE;
            END IF;
        END IF;

        IF v_amount IS NULL THEN
            -- the level the student was at in THAT session, unless the file says
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NULL OR v_level NOT IN (100, 200, 300, 400, 500, 600) THEN
                v_level := reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session);
            END IF;
            SELECT coalesce(sum(f.amount), 0) INTO v_amount
              FROM finance.fee_schedule f
              JOIN ref.programme p ON p.code = st.programme_code
             WHERE f.session = v_session AND f.ended_at IS NULL
               AND (f.level IS NULL OR f.level = v_level)
               AND (f.entry_mode IS NULL OR f.entry_mode = st.entry_mode)
               AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
               AND (f.programme_code IS NULL OR f.programme_code = st.programme_code)
               AND (v_sem IS NULL OR f.semester IS NULL OR f.semester = v_sem)
               AND CASE WHEN v_gst THEN f.item ~* '(gst|gns|general stud)'
                        WHEN v_other THEN f.item ILIKE '%' || v_text || '%'
                        ELSE f.item ILIKE 'school fee%' END;
            IF v_gst AND (v_amount IS NULL OR v_amount <= 0) THEN
                SELECT g.amount INTO v_amount FROM finance.gst_fee_for(v_sid, v_session) g WHERE g.stated;
            END IF;
        END IF;
        IF v_amount IS NULL OR v_amount <= 0 THEN nnd := nnd + 1; CONTINUE; END IF;

        v_when := v_given;
        IF v_when IS NULL THEN v_when := now(); nund := nund + 1; END IF;
        v_rcpt := 'LEG-' || v_ref;

        INSERT INTO finance.payment_reference
            (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (v_sid, v_session, v_ref, v_tag, v_amount, v_when, v_when, v_actor, 'Legacy', v_rcpt, v_note)
        ON CONFLICT (reference) DO NOTHING;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        IF v_cnt > 0 THEN
            nc := nc + 1;
            IF v_separate THEN nsep := nsep + 1; END IF;
            IF v_payref IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, v_amount);
            END IF;
            -- V647: paid under another number (a JAMB registration, application or admission number, an old matriculation number):
            -- the number kept beside the payment, which is the same payment, counted once
            IF upper(coalesce(st.matric_no, '')) <> v_matric THEN
                INSERT INTO finance.payment_identity (payment_id, original_identifier, original_identifier_type, resolved_student_id, resolved_matric_no,
                                                      match_method, source, batch_ref, recorded_by)
                SELECT pr.id, v_matric, rs.identifier_type, v_sid, st.matric_no, rs.method,
                       CASE WHEN nullif(current_setting('moaum.recon_batch', true), '') IS NULL THEN 'OLD_FEES_IMPORT' ELSE 'FEE_HISTORY_RECONCILIATION' END,
                       nullif(current_setting('moaum.recon_batch', true), ''), v_actor
                  FROM finance.payment_reference pr WHERE pr.reference = v_ref
                ON CONFLICT (payment_id) DO NOTHING;
            END IF;
            -- a row held before, recorded now
            UPDATE finance.legacy_payment_held h
               SET status = 'RECONCILED', payment_id = (SELECT pr.id FROM finance.payment_reference pr WHERE pr.reference = v_ref), reconciled_at = now(),
                   batch_ref = coalesce(nullif(current_setting('moaum.recon_batch', true), ''), h.batch_ref)
             WHERE h.row_key = coalesce('PAYREF:' || v_payref, 'ROW:' || md5(r::text)) AND h.status <> 'RECONCILED';
        ELSE
            nd := nd + 1; v_dups := v_dups || coalesce(v_payref, v_ref);
        END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund, nm, nsep, ntk;
END $function$;

-- ── the rows of the uploads the Bursar approved that the import dropped because their number was not a matriculation or admission
--    number: held now, for the reconciliation (a direct load kept no rows; its file is uploaded again) ──
DO $$
DECLARE x record; v text; pur text; rs record; n int := 0;
BEGIN
    FOR x IN SELECT e.value AS r
               FROM finance.legacy_fee_upload u
               JOIN finance.legacy_fee_upload_part p ON p.upload_id = u.id
               CROSS JOIN LATERAL jsonb_array_elements(p.rows) e
              WHERE u.state = 'APPROVED' LOOP
        v := upper(btrim(coalesce(x.r->>'matric', x.r->>'matricNo', x.r->>'matric_no', x.r->>'matno', x.r->>'regNo', '')));
        CONTINUE WHEN v = '' OR v ~* '^mat(ric|no)';
        CONTINUE WHEN EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = v) OR EXISTS (SELECT 1 FROM people.student s WHERE upper(s.admission_no) = v);
        pur := finance.legacy_row_purpose(x.r);
        CONTINUE WHEN pur = 'APPLICANT';
        SELECT * INTO rs FROM people.resolve_student(v, true);
        PERFORM finance.legacy_hold(x.r, v, pur, rs.identifier_type, CASE WHEN rs.status = 'AMBIGUOUS' THEN 'AMBIGUOUS' ELSE 'NO_MATCH' END, rs.candidates);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'V647: % old-portal payment row(s) of approved uploads held for the reconciliation', n;
END $$;

COMMIT;
