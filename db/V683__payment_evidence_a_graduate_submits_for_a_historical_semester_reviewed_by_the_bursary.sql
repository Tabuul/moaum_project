-- ═══════════════════════════════════════
-- V683 — Payment evidence a graduate submits for a historical semester, reviewed by the Bursary; each period's payments under review
--
-- The University's master prompt of 28 October 2026 ("HISTORICAL SCHOOL FEES HISTORY, MISSING PAYMENT RECONCILIATION, OUTSTANDING
-- BALANCE & GRADUATING STUDENT CLEARANCE"): "no receipt evidence must not automatically mean the student did not pay"; "SUBMIT PAYMENT
-- EVIDENCE … the student may upload a receipt, payment evidence, bank evidence, an old portal receipt, a transaction reference …
-- PAYMENT_EVIDENCE_SUBMITTED … Bursary reviews it: VERIFIED, REJECTED, REQUIRES_MORE_INFORMATION … do NOT automatically mark paid
-- because a student uploaded a document"; "when Bursary verifies a historical payment, do not create a second payment: link the evidence
-- to the existing payment … correct ownership if required … allocate to the correct session … preserve the original reference, date
-- and amount"; "if the system cannot determine whether a historical fee was paid, show PAYMENT VERIFICATION REQUIRED rather than
-- automatically UNPAID". Asked who uploads the evidence, the University chose: the student submits it, the Bursary reviews it.
--
-- What stood (V654, V665, V668, V670): the historical account by session and semester at the fees of the period, assessments made by
-- the Students Account Officer and approved by the Bursar, waivers, cohort assessment, the graduate paying a historical balance online,
-- the FINAL clearance's Bursary stage reading the account, the payment archive (an archived payment counts for nothing until settled),
-- reallocation (V649) and the swap (V527) to put a payment right. But a graduate who had paid and kept the receipt had no way to say
-- so on the portal, and the account read a period with an archived school-fee payment, or a payment under another purpose, as plainly
-- OUTSTANDING.
--
-- Now:
--   1. finance.historical_payment_evidence (HPE/YYYY/NNNNNN): what the graduate says they paid for a session's semester — the amount,
--      the day, how (bank, old portal, online, other), the receipt, teller or transaction number, a note and files (PDF, JPEG, PNG, up
--      to 5 MB). One open at a time for a period; only a period of the student's own historical account that is not settled.
--   2. The student submits it (finance.historical_evidence_submit), adds what the Bursary asks for and sends it again
--      (historical_evidence_resubmit), or withdraws it (historical_evidence_withdraw).
--   3. The Students Account Officer or the Bursar (REVIEW_PAYMENT_EVIDENCE) decides it (historical_evidence_decide): VERIFIED, linked
--      to the payment on record it shows — never a payment made up, one payment backing one verified evidence; MORE_INFORMATION_REQUIRED
--      or REJECTED, with the reason. The evidence never counts by itself: only the payment does, as every reader counts it. Where the
--      payment linked is archived, another student's, or under another purpose or session, historical_evidence_payment_state says so
--      and the Payment Archive, the swap or the reallocation puts it right — each with its own approval.
--   4. historical_evidence_candidates: the payments on record the evidence may be — its number as a reference or receipt number, the
--      student's own payments of the session, and their archived payments.
--   5. finance.historical_review(students): each period not settled, with its open evidence, the session's archived school-fee payments
--      not yet settled, and the session's payments under another purpose (V665) — PAYMENT_UNDER_REVIEW where any stands.
--   6. finance.historical_quality restated with PAYMENT_EVIDENCE_SUBMITTED and ARCHIVED_SCHOOL_FEES.
--   7. Notices to the student: evidence received, verified, more information required, rejected.
-- Nothing here changes a payment, an assessment, the account's amounts or a clearance.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V683: payment evidence for a historical semester, reviewed by the Bursary (the University, 28 October 2026)', true);

-- ── 1 · who reviews ──────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.historical_grant DROP CONSTRAINT historical_grant_permission_check;
ALTER TABLE finance.historical_grant ADD CONSTRAINT historical_grant_permission_check CHECK (permission IN (
    'VIEW_HISTORICAL_FEE_ASSESSMENT', 'CREATE_HISTORICAL_FEE_ASSESSMENT', 'EDIT_HISTORICAL_FEE_ASSESSMENT', 'SUBMIT_HISTORICAL_FEE_ASSESSMENT',
    'REVIEW_HISTORICAL_FEE_ASSESSMENT', 'APPROVE_HISTORICAL_FEE_ASSESSMENT', 'REJECT_HISTORICAL_FEE_ASSESSMENT', 'RETURN_HISTORICAL_FEE_ASSESSMENT',
    'VIEW_FINANCIAL_CLEARANCE', 'PROCESS_FINANCIAL_CLEARANCE', 'APPROVE_FINANCIAL_CLEARANCE', 'VIEW_HISTORICAL_PAYMENT',
    'VIEW_HISTORICAL_FEE_REPORT', 'EXPORT_HISTORICAL_FEE_REPORT', 'CORRECT_HISTORICAL_ASSESSMENT', 'VIEW_ASSESSMENT_HISTORY',
    'SET_HISTORICAL_FEE_START', 'REVIEW_PAYMENT_EVIDENCE'));
INSERT INTO finance.historical_grant (office_code, permission)
SELECT o, 'REVIEW_PAYMENT_EVIDENCE' FROM unnest(ARRAY['bursar', 'super', 'studentaccounts']) o
ON CONFLICT DO NOTHING;

-- ── 2 · the evidence, its files and its timeline ─────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.historical_payment_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE CHECK (reference ~ '^HPE/[0-9]{4}/[0-9]{6}$'),
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session text NOT NULL REFERENCES policy.academic_session (name),
    semester integer NOT NULL CHECK (semester BETWEEN 1 AND 3),
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    paid_on date,
    channel text NOT NULL CHECK (channel IN ('BANK', 'OLD_PORTAL', 'ONLINE', 'OTHER')),
    payment_reference text NOT NULL CHECK (length(btrim(payment_reference)) BETWEEN 4 AND 80),
    note text CHECK (note IS NULL OR length(note) <= 1000),
    state text NOT NULL DEFAULT 'SUBMITTED' CHECK (state IN ('SUBMITTED', 'MORE_INFORMATION_REQUIRED', 'VERIFIED', 'REJECTED', 'WITHDRAWN')),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    decision_note text,
    payment_id uuid REFERENCES finance.payment_reference (id) ON DELETE CASCADE,
    CONSTRAINT ck_hpe_verified CHECK ((state = 'VERIFIED') = (payment_id IS NOT NULL))
);
-- one open evidence a period; one verified evidence a payment
CREATE UNIQUE INDEX ux_hpe_open ON finance.historical_payment_evidence (student_id, session, semester) WHERE state IN ('SUBMITTED', 'MORE_INFORMATION_REQUIRED');
CREATE UNIQUE INDEX ux_hpe_payment ON finance.historical_payment_evidence (payment_id) WHERE state = 'VERIFIED';
CREATE INDEX ix_hpe_state ON finance.historical_payment_evidence (state, submitted_at);
CREATE INDEX ix_hpe_student ON finance.historical_payment_evidence (student_id, session, semester);
SELECT audit.attach('finance.historical_payment_evidence');
COMMENT ON TABLE finance.historical_payment_evidence IS
  'V683: what a graduate says they paid for a past session''s semester, with the receipt, teller or transaction number and files — reviewed by the Students Account Officer or the Bursar: VERIFIED against a payment on record (never a payment made up), MORE_INFORMATION_REQUIRED or REJECTED. The evidence never counts as paid: only the payment linked does, once it is the student''s confirmed school fees of the session.';

CREATE TABLE finance.historical_payment_evidence_file (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    evidence_id uuid NOT NULL REFERENCES finance.historical_payment_evidence (id) ON DELETE CASCADE,
    filename text NOT NULL,
    content_type text NOT NULL CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png')),
    size_bytes bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content bytea NULL,
    object_id uuid NULL REFERENCES platform.file_object (id),
    added_by uuid,
    added_office text,
    added_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hpe_file_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_hpe_file ON finance.historical_payment_evidence_file (evidence_id);
SELECT audit.exempt('finance.historical_payment_evidence_file', 'V683: file bytes; who added which file and when is the row itself, and the evidence it supports is on the audit spine');
COMMENT ON TABLE finance.historical_payment_evidence_file IS 'V683: a file of a graduate''s payment evidence (a receipt, a teller, an old-portal receipt) — in the file store where there is one, else here';

CREATE TABLE finance.historical_payment_evidence_event (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    evidence_id uuid NOT NULL REFERENCES finance.historical_payment_evidence (id) ON DELETE CASCADE,
    action text NOT NULL CHECK (action IN ('SUBMITTED', 'FILE_ADDED', 'RESUBMITTED', 'WITHDRAWN', 'MORE_INFORMATION_REQUIRED', 'VERIFIED', 'REJECTED')),
    actor uuid,
    office text,
    note text,
    at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_hpe_event ON finance.historical_payment_evidence_event (evidence_id, at);
SELECT audit.attach('finance.historical_payment_evidence_event');
COMMENT ON TABLE finance.historical_payment_evidence_event IS 'V683: the timeline of a graduate''s payment evidence, written once per act';

CREATE FUNCTION finance.historical_evidence_event(p_evidence uuid, p_action text, p_note text)
RETURNS void
LANGUAGE sql AS $fn$
    INSERT INTO finance.historical_payment_evidence_event (evidence_id, action, actor, office, note)
    VALUES (p_evidence, p_action, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), p_note)
$fn$;

-- ── 3 · the student's acts ───────────────────────────────────────────────────────────────────────────────────────────────
-- what the student says about the payment, checked the same way on submission and when sent again
CREATE FUNCTION finance.historical_evidence_check(p_amount numeric, p_paid_on date, p_channel text, p_reference text, p_note text)
RETURNS void
LANGUAGE plpgsql STABLE AS $fn$
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000000 THEN
        RAISE EXCEPTION 'HPE_AMOUNT: say the amount you paid, in naira' USING ERRCODE = '23514';
    END IF;
    IF p_paid_on IS NOT NULL AND (p_paid_on > (now() AT TIME ZONE 'Africa/Lagos')::date OR p_paid_on < DATE '1990-01-01') THEN
        RAISE EXCEPTION 'HPE_DATE: the day you paid cannot be in the future' USING ERRCODE = '23514';
    END IF;
    IF coalesce(upper(btrim(p_channel)), '') NOT IN ('BANK', 'OLD_PORTAL', 'ONLINE', 'OTHER') THEN
        RAISE EXCEPTION 'HPE_CHANNEL: say how you paid — at a bank, on the old portal, online or otherwise' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reference, ''))) NOT BETWEEN 4 AND 80 THEN
        RAISE EXCEPTION 'HPE_REFERENCE: give the receipt, teller or transaction number on your evidence (4 to 80 characters)' USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(p_note, '')) > 1000 THEN
        RAISE EXCEPTION 'HPE_NOTE_LONG: the note is up to 1,000 characters' USING ERRCODE = '23514';
    END IF;
END $fn$;

CREATE FUNCTION finance.historical_evidence_submit(p_student uuid, p_session text, p_semester integer, p_amount numeric, p_paid_on date,
                                                    p_channel text, p_reference text, p_note text)
RETURNS TABLE(id uuid, reference text, state text)
LANGUAGE plpgsql AS $fn$
DECLARE per record; v_id uuid; v_ref text; v_open text; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
BEGIN
    PERFORM finance.historical_evidence_check(p_amount, p_paid_on, p_channel, p_reference, p_note);
    SELECT x.status, x.outstanding INTO per FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.semester = p_semester;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'HPE_PERIOD: % % is not a semester of your school fees history', p_session, lower(finance.semester_words(p_semester))
            USING ERRCODE = '23514', HINT = 'Payment evidence is given for a semester your school fees history lists.';
    END IF;
    IF per.status IN ('CLEARED', 'CREDIT') THEN
        RAISE EXCEPTION 'HPE_SETTLED: % % is settled; nothing is owed for it', p_session, lower(finance.semester_words(p_semester)) USING ERRCODE = '23514';
    END IF;
    SELECT e.reference INTO v_open FROM finance.historical_payment_evidence e
     WHERE e.student_id = p_student AND e.session = p_session AND e.semester = p_semester AND e.state IN ('SUBMITTED', 'MORE_INFORMATION_REQUIRED');
    IF v_open IS NOT NULL THEN
        RAISE EXCEPTION 'HPE_OPEN: your evidence % for % % is already with the Bursary', v_open, p_session, lower(finance.semester_words(p_semester))
            USING ERRCODE = '23514', HINT = 'Add to it when the Bursary asks for more, or withdraw it first.';
    END IF;
    v_ref := 'HPE/' || v_year || '/' || lpad(platform.next_number('HISTORICAL_PAYMENT_EVIDENCE', 'finance', v_year)::text, 6, '0');
    INSERT INTO finance.historical_payment_evidence (reference, student_id, session, semester, amount, paid_on, channel, payment_reference, note)
    VALUES (v_ref, p_student, p_session, p_semester, round(p_amount, 2), p_paid_on, upper(btrim(p_channel)), btrim(p_reference), nullif(btrim(p_note), ''))
    RETURNING finance.historical_payment_evidence.id INTO v_id;
    PERFORM finance.historical_evidence_event(v_id, 'SUBMITTED', NULL);
    PERFORM platform.tell_student(p_student, 'HISTORICAL_EVIDENCE_RECEIVED', NULL,
        jsonb_build_object('SESSION', p_session, 'SEMESTER', finance.semester_words(p_semester), 'REFERENCE', v_ref,
                           'AMOUNT', 'NGN ' || to_char(p_amount, 'FM999,999,999,990.00'), 'NOTE', ''),
        'HISTORICAL_EVIDENCE_RECEIVED:' || v_id);
    RETURN QUERY SELECT v_id, v_ref, 'SUBMITTED'::text;
END $fn$;
COMMENT ON FUNCTION finance.historical_evidence_submit(uuid, text, integer, numeric, date, text, text, text) IS
  'V683: a graduate''s payment evidence for a semester of their school fees history that is not settled (HPE_PERIOD, HPE_SETTLED), one open at a time (HPE_OPEN): the amount, the day, how it was paid, the receipt, teller or transaction number and a note; the student is told it is received. It counts for nothing until the Bursary verifies the payment it shows.';

CREATE FUNCTION finance.historical_evidence_mine(p_id uuid, p_student uuid)
RETURNS finance.historical_payment_evidence
LANGUAGE plpgsql AS $fn$
DECLARE e finance.historical_payment_evidence;
BEGIN
    SELECT * INTO e FROM finance.historical_payment_evidence x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND OR e.student_id IS DISTINCT FROM p_student THEN
        RAISE EXCEPTION 'HPE_NOT_FOUND: no such payment evidence of yours' USING ERRCODE = 'P0002';
    END IF;
    RETURN e;
END $fn$;

CREATE FUNCTION finance.historical_evidence_resubmit(p_id uuid, p_student uuid, p_amount numeric, p_paid_on date, p_channel text, p_reference text, p_note text)
RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE e finance.historical_payment_evidence;
BEGIN
    e := finance.historical_evidence_mine(p_id, p_student);
    IF e.state <> 'MORE_INFORMATION_REQUIRED' THEN
        RAISE EXCEPTION 'HPE_NOT_ASKED: % is %; it is sent again only when the Bursary asks for more', e.reference, lower(replace(e.state, '_', ' '))
            USING ERRCODE = '23514';
    END IF;
    PERFORM finance.historical_evidence_check(p_amount, p_paid_on, p_channel, p_reference, p_note);
    UPDATE finance.historical_payment_evidence x
       SET amount = round(p_amount, 2), paid_on = p_paid_on, channel = upper(btrim(p_channel)), payment_reference = btrim(p_reference),
           note = nullif(btrim(p_note), ''), state = 'SUBMITTED', updated_at = now()
     WHERE x.id = p_id;
    PERFORM finance.historical_evidence_event(p_id, 'RESUBMITTED', nullif(btrim(p_note), ''));
    RETURN 'SUBMITTED';
END $fn$;
COMMENT ON FUNCTION finance.historical_evidence_resubmit(uuid, uuid, numeric, date, text, text, text) IS
  'V683: the student sends their payment evidence again, with what the Bursary asked for — only when it was asked (HPE_NOT_ASKED).';

CREATE FUNCTION finance.historical_evidence_withdraw(p_id uuid, p_student uuid, p_reason text)
RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE e finance.historical_payment_evidence;
BEGIN
    e := finance.historical_evidence_mine(p_id, p_student);
    IF e.state NOT IN ('SUBMITTED', 'MORE_INFORMATION_REQUIRED') THEN
        RAISE EXCEPTION 'HPE_DECIDED: % is %; it is kept as it is', e.reference, lower(replace(e.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.historical_payment_evidence x SET state = 'WITHDRAWN', updated_at = now() WHERE x.id = p_id;
    PERFORM finance.historical_evidence_event(p_id, 'WITHDRAWN', nullif(btrim(p_reason), ''));
    RETURN 'WITHDRAWN';
END $fn$;

-- ── 4 · the Bursary's review ─────────────────────────────────────────────────────────────────────────────────────────────
-- where a payment stands against a student's session: what is still to be done before it counts as that session's school fees
CREATE FUNCTION finance.historical_evidence_payment_state(p_payment uuid, p_student uuid, p_session text)
RETURNS text
LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN r.id IS NULL THEN NULL
                WHEN r.confirmed_at IS NULL THEN 'NOT_CONFIRMED'
                WHEN r.archived_at IS NOT NULL THEN 'ARCHIVED'
                WHEN r.student_id IS DISTINCT FROM p_student THEN 'OTHER_STUDENT'
                WHEN r.purpose NOT LIKE 'School fees%' THEN 'NOT_SCHOOL_FEES'
                WHEN r.session IS DISTINCT FROM p_session THEN 'OTHER_SESSION'
                ELSE 'COUNTED' END
      FROM (SELECT p_payment AS id) k LEFT JOIN finance.payment_reference r ON r.id = k.id
$fn$;
COMMENT ON FUNCTION finance.historical_evidence_payment_state(uuid, uuid, text) IS
  'V683: where a payment stands against a student''s session — COUNTED (their confirmed school fees of the session), or what is still to be done before it counts: ARCHIVED (settled on the Payment Archive), OTHER_STUDENT (the swap), NOT_SCHOOL_FEES or OTHER_SESSION (a reallocation), NOT_CONFIRMED.';

-- the payments on record the evidence may be: its number as a reference or receipt number, the student's own payments of the session,
-- and the student's archived payments
CREATE FUNCTION finance.historical_evidence_candidates(p_id uuid)
RETURNS TABLE(payment_id uuid, reference text, receipt_no text, student_id uuid, matric_no text, name text, session text, purpose text, amount numeric,
              confirmed_at timestamptz, channel text, archived boolean, why text, state text, verified_for text)
LANGUAGE sql STABLE AS $fn$
    WITH e AS (SELECT * FROM finance.historical_payment_evidence x WHERE x.id = p_id),
    keys AS (SELECT DISTINCT k FROM e CROSS JOIN LATERAL unnest(ARRAY[btrim(e.payment_reference), upper(btrim(e.payment_reference)), lower(btrim(e.payment_reference))]) k),
    hit AS (
        SELECT r.id, 1 AS rank, 'NUMBER' AS why FROM finance.payment_reference r WHERE r.reference IN (SELECT k FROM keys)
        UNION ALL SELECT r.id, 1, 'NUMBER' FROM finance.payment_reference r WHERE r.receipt_no IN (SELECT k FROM keys)
        UNION ALL SELECT r.id, 2, 'SESSION' FROM finance.payment_reference r JOIN e ON r.student_id = e.student_id AND r.session = e.session
        UNION ALL SELECT r.id, 3, 'ARCHIVED' FROM finance.payment_reference r JOIN e ON r.student_id = e.student_id WHERE r.archived_at IS NOT NULL),
    best AS (SELECT DISTINCT ON (h.id) h.id, h.rank, h.why FROM hit h ORDER BY h.id, h.rank)
    SELECT r.id, r.reference, r.receipt_no, r.student_id, s.matric_no, s.surname || ', ' || s.other_names, r.session, r.purpose, r.amount, r.confirmed_at,
           r.channel, r.archived_at IS NOT NULL, b.why, finance.historical_evidence_payment_state(r.id, e.student_id, e.session),
           (SELECT v.reference FROM finance.historical_payment_evidence v WHERE v.payment_id = r.id AND v.state = 'VERIFIED' AND v.id <> e.id)
      FROM best b JOIN finance.payment_reference r ON r.id = b.id CROSS JOIN e
      LEFT JOIN people.student s ON s.id = r.student_id
     WHERE r.confirmed_at IS NOT NULL
     ORDER BY b.rank, r.confirmed_at DESC
     LIMIT 50
$fn$;
COMMENT ON FUNCTION finance.historical_evidence_candidates(uuid) IS
  'V683: the confirmed payments on record a graduate''s evidence may be — its receipt, teller or transaction number as a payment reference or receipt number (anyone''s), the student''s payments of the session (any purpose), and the student''s archived payments — each with where it stands against the session and any evidence already verified on it. Archived payments are listed on purpose: they are for review, not counted.';

CREATE FUNCTION finance.historical_evidence_decide(p_id uuid, p_decision text, p_note text, p_payment uuid)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE e finance.historical_payment_evidence; r finance.payment_reference; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_dec text := upper(btrim(coalesce(p_decision, ''))); v_state text;
        v_used text; v_key text;
BEGIN
    IF v_dec NOT IN ('VERIFY', 'MORE_INFORMATION', 'REJECT') THEN
        RAISE EXCEPTION 'HPE_DECISION: payment evidence is verified, sent back for more information, or rejected' USING ERRCODE = '23514';
    END IF;
    PERFORM finance.historical_require('REVIEW_PAYMENT_EVIDENCE');
    IF v_actor IS NULL THEN RAISE EXCEPTION 'HPE_ACTOR: payment evidence is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM finance.historical_payment_evidence x WHERE x.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'HPE_NOT_FOUND: no such payment evidence' USING ERRCODE = 'P0002'; END IF;
    IF e.state <> 'SUBMITTED' THEN
        RAISE EXCEPTION 'HPE_NOT_SUBMITTED: % is %; only evidence awaiting the Bursary is decided', e.reference, lower(replace(e.state, '_', ' '))
            USING ERRCODE = '23514';
    END IF;
    IF v_dec = 'VERIFY' THEN
        IF p_payment IS NULL THEN
            RAISE EXCEPTION 'HPE_PAYMENT_NEEDED: name the payment on record the evidence shows — a verified evidence is linked to it'
                USING ERRCODE = '23514', HINT = 'If the payment is not on the portal, record it first (Old-Portal Payments, with its approval), then verify.';
        END IF;
        SELECT * INTO r FROM finance.payment_reference x WHERE x.id = p_payment;
        IF NOT FOUND OR r.confirmed_at IS NULL THEN
            RAISE EXCEPTION 'HPE_PAYMENT: the payment named is not a confirmed payment on record' USING ERRCODE = '23514';
        END IF;
        SELECT v.reference INTO v_used FROM finance.historical_payment_evidence v WHERE v.payment_id = p_payment AND v.state = 'VERIFIED';
        IF v_used IS NOT NULL THEN
            RAISE EXCEPTION 'HPE_PAYMENT_USED: payment % already backs verified evidence %', r.reference, v_used USING ERRCODE = '23514';
        END IF;
    ELSIF length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'HPE_NOTE: say what is needed, or why, in ten characters at least' USING ERRCODE = '23514';
    END IF;
    v_state := CASE v_dec WHEN 'VERIFY' THEN 'VERIFIED' WHEN 'MORE_INFORMATION' THEN 'MORE_INFORMATION_REQUIRED' ELSE 'REJECTED' END;
    UPDATE finance.historical_payment_evidence x
       SET state = v_state, decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = nullif(btrim(p_note), ''),
           payment_id = CASE WHEN v_dec = 'VERIFY' THEN p_payment END, updated_at = now()
     WHERE x.id = p_id;
    PERFORM finance.historical_evidence_event(p_id, v_state,
        CASE WHEN v_dec = 'VERIFY' THEN concat_ws(' — ', 'Payment ' || r.reference, nullif(btrim(p_note), '')) ELSE btrim(p_note) END);
    v_key := CASE v_dec WHEN 'VERIFY' THEN 'HISTORICAL_EVIDENCE_VERIFIED' WHEN 'MORE_INFORMATION' THEN 'HISTORICAL_EVIDENCE_MORE_INFO' ELSE 'HISTORICAL_EVIDENCE_REJECTED' END;
    PERFORM platform.tell_student(e.student_id, v_key, NULL,
        jsonb_build_object('SESSION', e.session, 'SEMESTER', finance.semester_words(e.semester), 'REFERENCE', e.reference,
                           'AMOUNT', 'NGN ' || to_char(e.amount, 'FM999,999,999,990.00'), 'NOTE', coalesce(nullif(btrim(p_note), ''), '')),
        v_key || ':' || p_id || ':' || (SELECT count(*) FROM finance.historical_payment_evidence_event v WHERE v.evidence_id = p_id));
    RETURN jsonb_build_object('reference', e.reference, 'state', v_state,
                              'paymentState', CASE WHEN v_dec = 'VERIFY' THEN finance.historical_evidence_payment_state(p_payment, e.student_id, e.session) END);
END $fn$;
COMMENT ON FUNCTION finance.historical_evidence_decide(uuid, text, text, uuid) IS
  'V683: the Students Account Officer or the Bursar (REVIEW_PAYMENT_EVIDENCE) decides a graduate''s payment evidence awaiting the Bursary: VERIFY links it to the confirmed payment on record it shows (HPE_PAYMENT_NEEDED, HPE_PAYMENT, one payment backing one verified evidence: HPE_PAYMENT_USED) and answers where that payment stands (finance.historical_evidence_payment_state) — nothing is paid by the evidence itself; MORE_INFORMATION and REJECT say why (HPE_NOTE). The student is told.';

-- ── 5 · each period's payments under review ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.historical_review(p_students uuid[])
RETURNS TABLE(student_id uuid, session text, semester integer, evidence_id uuid, evidence_ref text, evidence_state text, evidence_amount numeric,
              archived_count integer, archived_amount numeric, other_count integer, other_amount numeric, review text)
LANGUAGE sql STABLE AS $fn$
    WITH per AS MATERIALIZED (SELECT x.student_id, x.session, x.semester, x.status FROM finance.historical_rows(p_students) x),
    ev AS (SELECT DISTINCT ON (e.student_id, e.session, e.semester) e.student_id, e.session, e.semester, e.id, e.reference, e.state, e.amount
             FROM finance.historical_payment_evidence e
            WHERE e.student_id = ANY (p_students) AND e.state IN ('SUBMITTED', 'MORE_INFORMATION_REQUIRED')
            ORDER BY e.student_id, e.session, e.semester, e.submitted_at DESC),
    -- the session's school-fee payments archived and not yet settled (V670): counted for nothing until they are
    ar AS (SELECT a.student_id, a.session, count(*)::int AS n, sum(a.amount) AS amount
             FROM finance.payment_archive a
            WHERE a.student_id = ANY (p_students) AND a.settled_at IS NULL AND a.purpose LIKE 'School fees%'
            GROUP BY a.student_id, a.session),
    -- the session's confirmed payments under another purpose that may be school fees (V665: outstanding fees, tuition, JAMB-named)
    ot AS (SELECT r.student_id, r.session, count(*)::int AS n, sum(r.amount) AS amount
             FROM finance.payment_reference r
            WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
              AND r.purpose NOT LIKE 'School fees%' AND r.purpose ~* '(outstanding|tuition|school|jamb|utme)'
            GROUP BY r.student_id, r.session)
    SELECT p.student_id, p.session, p.semester, ev.id, ev.reference, ev.state, ev.amount,
           coalesce(ar.n, 0), coalesce(ar.amount, 0), coalesce(ot.n, 0), coalesce(ot.amount, 0),
           CASE WHEN p.status IN ('CLEARED', 'CREDIT') THEN NULL
                WHEN ev.id IS NOT NULL OR ar.n > 0 OR ot.n > 0 THEN 'PAYMENT_UNDER_REVIEW' END
      FROM per p
      LEFT JOIN ev ON ev.student_id = p.student_id AND ev.session = p.session AND ev.semester = p.semester
      LEFT JOIN ar ON ar.student_id = p.student_id AND ar.session = p.session
      LEFT JOIN ot ON ot.student_id = p.student_id AND ot.session = p.session
$fn$;
COMMENT ON FUNCTION finance.historical_review(uuid[]) IS
  'V683: each period of the students'' historical accounts with what is under review for it — the student''s open payment evidence (the period''s), the session''s archived school-fee payments not yet settled (V670) and its payments under another purpose that may be school fees (V665): PAYMENT_UNDER_REVIEW where any stands on a period not settled. What is owed is unchanged: a payment under review counts once it is put right.';

-- ── 6 · data quality ─────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.historical_quality(p_limit integer DEFAULT 2000)
 RETURNS TABLE(issue text, student_id uuid, detail text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH grads AS (
        SELECT s.id, s.entry_session, s.programme_code, records.graduation_session(s.id) AS grad
          FROM people.student s
         WHERE s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED'))
    SELECT * FROM (
        SELECT 'NO_ENTRY_SESSION'::text, g.id, 'No admission session on the record: the historical periods cannot be read' FROM grads g WHERE g.entry_session IS NULL
        UNION ALL
        SELECT 'NO_GRADUATION_SESSION', g.id, 'No graduation session (graduand list, reconciliation, enrolment or registration)' FROM grads g WHERE g.grad IS NULL
        UNION ALL
        SELECT 'MISSING_FEE_STRUCTURE', h.student_id, h.review_periods || ' period(s) with no fee structure or approved assessment'
          FROM finance.historical_summary h JOIN grads g ON g.id = h.student_id WHERE h.review_periods > 0
        UNION ALL
        SELECT 'PENDING_APPROVAL', h.student_id, h.pending_periods || ' period(s) awaiting the Bursar''s approval'
          FROM finance.historical_summary h JOIN grads g ON g.id = h.student_id WHERE h.pending_periods > 0
        UNION ALL
        SELECT 'OVERPAYMENT', h.student_id, 'Paid NGN ' || to_char(h.credit, 'FM999,999,999,990.00') || ' beyond what is assessed: for Refunds & Credits'
          FROM finance.historical_summary h JOIN grads g ON g.id = h.student_id WHERE h.credit >= 1
        UNION ALL
        SELECT DISTINCT 'PROGRAMME_CHANGED', m.student_id, 'Moved from ' || m.from_programme || ' to ' || m.to_programme || ': earlier sessions are read on the programme now held'
          FROM people.record_move m JOIN grads g ON g.id = m.student_id WHERE m.from_programme IS DISTINCT FROM m.to_programme
        UNION ALL
        -- V683: payment evidence a graduate submitted, awaiting the Bursary
        SELECT 'PAYMENT_EVIDENCE_SUBMITTED', e.student_id,
               'Payment evidence ' || e.reference || ' for ' || e.session || ' ' || lower(finance.semester_words(e.semester)) || ': NGN '
               || to_char(e.amount, 'FM999,999,999,990.00') || ', ' || e.payment_reference || ' — awaits the Bursary'
          FROM finance.historical_payment_evidence e JOIN grads g ON g.id = e.student_id WHERE e.state = 'SUBMITTED'
        UNION ALL
        -- V683: a graduate's school-fee payment archived for review (V670), not yet settled: counted for nothing meanwhile
        SELECT 'ARCHIVED_SCHOOL_FEES', a.student_id,
               'School fees payment ' || a.reference || ' (' || coalesce(a.session, 'no session') || ', NGN ' || to_char(a.amount, 'FM999,999,999,990.00')
               || ') is archived for review as ' || a.archive_ref || ': not counted until settled'
          FROM finance.payment_archive a JOIN grads g ON g.id = a.student_id WHERE a.settled_at IS NULL AND a.purpose LIKE 'School fees%') x(issue, student_id, detail)
     LIMIT greatest(p_limit, 1)
$function$;

-- ── 7 · the notices ──────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('HISTORICAL_EVIDENCE_RECEIVED', 'Payment evidence received',
 'To a graduate once their payment evidence for a past semester is with the Bursary',
 'Your payment evidence for [SESSION] [SEMESTER] is received',
 E'Dear [FIRST_NAME],\n\nThe Bursary has your payment evidence [REFERENCE] for [SESSION], [SEMESTER] ([AMOUNT]). It is checked against the payments on record; you are told when it is verified, or if more is needed. It does not count as paid until then. Your school fees history is on your portal: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your payment evidence [REFERENCE] for [SESSION] [SEMESTER] is received and will be checked. See your portal.',
 'Payment evidence received',
 'Your payment evidence [REFERENCE] for [SESSION], [SEMESTER] ([AMOUNT]) is with the Bursary. You are told when it is verified, or if more is needed.',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','AMOUNT','REFERENCE','NOTE','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL'),
('HISTORICAL_EVIDENCE_VERIFIED', 'Payment evidence verified',
 'To a graduate once the Bursary verifies their payment evidence for a past semester against a payment on record',
 'Your payment evidence for [SESSION] [SEMESTER] is verified',
 E'Dear [FIRST_NAME],\n\nThe Bursary has verified your payment evidence [REFERENCE] for [SESSION], [SEMESTER] against the payment on record. [NOTE] Your school fees history shows what this period now stands at: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your payment evidence [REFERENCE] for [SESSION] [SEMESTER] is verified. See your portal.',
 'Payment evidence verified',
 'The Bursary has verified your payment evidence [REFERENCE] for [SESSION], [SEMESTER]. [NOTE]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','AMOUNT','REFERENCE','NOTE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('HISTORICAL_EVIDENCE_MORE_INFO', 'Payment evidence: more information needed',
 'To a graduate when the Bursary needs more to verify their payment evidence for a past semester',
 'More is needed for your payment evidence for [SESSION] [SEMESTER]',
 E'Dear [FIRST_NAME],\n\nThe Bursary needs more to verify your payment evidence [REFERENCE] for [SESSION], [SEMESTER]: [NOTE]\n\nAdd it on your portal and send the evidence again: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: more is needed for your payment evidence [REFERENCE] ([SESSION] [SEMESTER]). See your portal.',
 'More needed for your payment evidence',
 'The Bursary needs more to verify your payment evidence [REFERENCE] for [SESSION], [SEMESTER]: [NOTE]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','AMOUNT','REFERENCE','NOTE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('HISTORICAL_EVIDENCE_REJECTED', 'Payment evidence not accepted',
 'To a graduate when the Bursary does not accept their payment evidence for a past semester',
 'Your payment evidence for [SESSION] [SEMESTER] is not accepted',
 E'Dear [FIRST_NAME],\n\nThe Bursary could not accept your payment evidence [REFERENCE] for [SESSION], [SEMESTER]: [NOTE]\n\nWhat this period owes is on your portal: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your payment evidence [REFERENCE] ([SESSION] [SEMESTER]) is not accepted. See your portal.',
 'Payment evidence not accepted',
 'The Bursary could not accept your payment evidence [REFERENCE] for [SESSION], [SEMESTER]: [NOTE]',
 ARRAY['FIRST_NAME','SESSION','SEMESTER','AMOUNT','REFERENCE','NOTE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

COMMIT;
