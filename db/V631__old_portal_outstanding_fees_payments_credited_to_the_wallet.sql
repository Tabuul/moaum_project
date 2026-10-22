-- V631: the old portal's OUTSTANDING FEES payments kept apart, verified by the Students Account Officer and credited to the
-- student's wallet by the Bursar (the University's word of 22 October 2026: "put the outstanding the dashboard let the bursar
-- decides to credit it to their wallet for them to use it, so separate all the outstanding fee so we can verify and credit to
-- their wallet").
--
-- The old portal took payments it filed as OUTSTANDING FEES — a student paying what the old portal said was still owed on a
-- session. The old-fees import (V498) brought each one in as "OUTSTANDING FEES (legacy) · semester N" (its own reference ending
-- -OUTSTANDINGFEES, the old payment number kept). The school-fees test reads purposes that begin "School fees", so none of them
-- counts towards a session's school fees: MOAU/AD/BUS/25/12847 paid ₦6,709 as OUTSTANDING FEES on 2025/2026 semester 2 and the
-- portal still shows ₦6,708.42 owed. On the live-shaped copy: 1,193 such payments by 807 students, ₦59.8m, from 2012/2013 to
-- 2026/2027, all confirmed, all on the Legacy channel.
--
-- They are not relabelled as school fees. They stay as imported, listed apart on the Legacy Financial Reconciliation desk, and go
-- to the student's wallet only through two officers, as the old e-wallet balances do (V583, V625):
--   · finance.legacy_outstanding_payment_rows — every such payment with the student, the session and semester, the old payment
--     number, the method the old portal recorded, the student's school-fee position on that session (due, paid, owed), and where
--     it stands: WAITING (nothing done yet), VERIFIED, RETURNED (to the officer), CREDITED, REJECTED.
--   · finance.legacy_outstanding_payment_verify — the Students Account Officer (or the Bursar) verifies payments against the
--     records; the Bursar's office holders are told what waits.
--   · finance.legacy_outstanding_payment_credit — a Bursar officer OTHER than the one who verified credits them: one CREDIT on
--     the wallet a payment, source LEGACY_OUTSTANDING (the student's own money: applied to fees after a loan or a grant,
--     refundable as own money), the payment's own amount, under a batch LEGACY-OUTSTANDING/YYYY/NNNNNN; once only (the row and a
--     unique key on the credit). The student is told and applies it to the session's fees on the wallet page, as any credit.
--     On the general ledger the credit is drawn from Opening balance / suspense (3900) into Student deposits & wallet (2100), as
--     every old-portal credit is (V545, V583).
--   · finance.legacy_outstanding_payment_decide — the Bursar rejects (with a reason; the student is told), returns a verified
--     payment to the officer (another officer than the verifier), or reopens a rejected one.
--   · finance.legacy_outstanding_payment_figures — the desk's figures.
-- A payment credited to a wallet is never deleted: the old-fees reset (V499, V527) keeps it, and anything else that would delete
-- it is refused. Nothing imported is rewritten; nothing is credited at the officer's stage; nothing is credited twice.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V631: the old portal''s OUTSTANDING FEES payments verified and credited to the wallet (the University, 22 October 2026)', true);

-- ── 1 · the source and the ledger ──
INSERT INTO finance.funding_source (code, name, nature, sponsor, account, active, note, sort)
VALUES ('LEGACY_OUTSTANDING', 'Old-portal outstanding fees payment', 'SELF', NULL, NULL, true,
        'A payment the old portal filed as OUTSTANDING FEES, kept apart from school fees, verified by the Students Account Officer and credited to the wallet by a different Bursar officer (V631). The student''s own money: applied to fees after a loan or a grant, refundable as own money. On the ledger drawn from Opening balance / suspense (3900), as every old-portal credit is.', 82)
ON CONFLICT (code) DO NOTHING;

-- restated from V625 with LEGACY_OUTSTANDING beside LEGACY_WALLET
CREATE OR REPLACE FUNCTION finance.gl_wallet_credit_account(p_source text, p_legacy boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN p_legacy OR p_source IN ('LEGACY_WALLET', 'LEGACY_OUTSTANDING') THEN '3900'
                WHEN p_source = 'OVERPAID' THEN finance.gl_income_account('School fees')
                WHEN (SELECT fs.nature FROM finance.funding_source fs WHERE fs.code = p_source) = 'GRANT' THEN '5240'
                ELSE '1010' END
$function$;
COMMENT ON FUNCTION finance.gl_wallet_credit_account(text, boolean) IS 'V545, V583, V625, V631: the account a wallet credit is drawn from — cash for a loan or the student''s own top-up, the scholarship expense for a grant, suspense for an old-portal credit (NELFUND, the e-wallet balance, an OUTSTANDING FEES payment), the session''s school-fees income for an overpayment credited to the wallet (no new cash).';

-- ── 2 · which payments: the old portal's OUTSTANDING FEES, as the import files them ──
-- every reader below names the same predicate (channel Legacy, purpose beginning OUTSTANDING), which this index serves
CREATE INDEX IF NOT EXISTS ix_pref_legacy_outstanding ON finance.payment_reference (student_id, session) WHERE channel = 'Legacy' AND purpose ~* '^outstanding';

-- ── 3 · what was done with each ──
CREATE SEQUENCE IF NOT EXISTS finance.legacy_outstanding_batch_seq;
CREATE TABLE finance.legacy_outstanding_payment (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id       uuid NOT NULL UNIQUE REFERENCES finance.payment_reference (id) ON DELETE CASCADE,
    reference        text NOT NULL,
    student_id       uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session          text NOT NULL,
    amount           numeric(12,2) NOT NULL CHECK (amount > 0),
    status           text NOT NULL CHECK (status IN ('VERIFIED', 'RETURNED', 'CREDITED', 'REJECTED')),
    verified_by      uuid,
    verified_office  text,
    verified_at      timestamptz,
    verify_note      text,
    decided_by       uuid,
    decided_office   text,
    decided_at       timestamptz,
    decision_note    text,
    batch_ref        text CHECK (batch_ref IS NULL OR batch_ref ~ '^LEGACY-OUTSTANDING/[0-9]{4}/[0-9]{6}$'),
    wallet_entry_id  uuid UNIQUE REFERENCES finance.wallet_entry (id) ON DELETE CASCADE,
    CONSTRAINT ck_lop_verified CHECK (status <> 'VERIFIED' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)),
    CONSTRAINT ck_lop_credited CHECK (status <> 'CREDITED' OR (wallet_entry_id IS NOT NULL AND batch_ref IS NOT NULL AND decided_by IS NOT NULL
                                                               AND verified_by IS NOT NULL AND decided_by <> verified_by)),
    CONSTRAINT ck_lop_reason CHECK (status NOT IN ('RETURNED', 'REJECTED') OR (decided_by IS NOT NULL AND length(btrim(coalesce(decision_note, ''))) >= 10))
);
CREATE INDEX ix_lop_status ON finance.legacy_outstanding_payment (status);
CREATE INDEX ix_lop_student ON finance.legacy_outstanding_payment (student_id);
CREATE INDEX ix_lop_batch ON finance.legacy_outstanding_payment (batch_ref) WHERE batch_ref IS NOT NULL;
COMMENT ON TABLE finance.legacy_outstanding_payment IS 'V631: what was done with an old-portal OUTSTANDING FEES payment (no row: waiting to be verified) — VERIFIED by the Students Account Officer or the Bursar; CREDITED to the student''s wallet by a Bursar officer other than the verifier (one LEGACY_OUTSTANDING credit a payment, under a LEGACY-OUTSTANDING/YYYY/NNNNNN batch); RETURNED to the officer or REJECTED by the Bursar with a reason. The payment itself stays as imported.';
SELECT audit.attach('finance.legacy_outstanding_payment');
GRANT SELECT ON finance.legacy_outstanding_payment TO app_auditor, app_reporting;

-- a payment credited to a wallet stays: deleting it would leave the credit with nothing behind it (the go-live reset, under
-- maintenance, clears the wallet first and is not held)
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_kept()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_batch text;
BEGIN
    IF OLD.purpose ~* '^outstanding' AND coalesce(current_setting('moaum.maintenance', true), '') <> 'on' THEN
        SELECT c.batch_ref INTO v_batch FROM finance.legacy_outstanding_payment c WHERE c.payment_id = OLD.id AND c.status = 'CREDITED';
        IF FOUND THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_CREDITED: payment % was credited to the student''s wallet (%); it is not removed', OLD.reference, v_batch
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN OLD;
END $function$;
CREATE TRIGGER trg_pref_legacy_outstanding_kept BEFORE DELETE ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.channel = 'Legacy') EXECUTE FUNCTION finance.legacy_outstanding_payment_kept();

-- the old-fees reset keeps a payment credited to a wallet (restated from V527 with that one addition, in the batch and in the count)
CREATE OR REPLACE FUNCTION finance.reset_legacy_payments(p_session text, p_confirm text, p_limit integer DEFAULT 5000)
RETURNS TABLE (deleted bigint, kept_in_use bigint, ledger_reversed bigint, remaining bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, finance, people, public, pg_temp
AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := coalesce(nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), 'old-portal fees history reset to be loaded again');
        n bigint; nr bigint; v_kept bigint; v_left bigint;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'the imported payment history is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm that the imported payment history is to be deleted' USING ERRCODE = '23514';
    END IF;
    IF p_session IS NOT NULL AND p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'a session looks like 2022/2023' USING ERRCODE = '23514';
    END IF;
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 20000 THEN
        RAISE EXCEPTION 'a reset batch is from 1 to 20,000 records' USING ERRCODE = '23514';
    END IF;

    -- the batch: the import's own records nothing points at, each with the ledger journal of its reference (if any), set apart
    -- and locked; the whole batch is worked at once (a record at a time took 7 ms each on the live-shaped copy)
    IF to_regclass('pg_temp.legacy_reset_batch') IS NOT NULL THEN DROP TABLE pg_temp.legacy_reset_batch; END IF;   -- an earlier batch of this transaction
    CREATE TEMP TABLE legacy_reset_batch ON COMMIT DROP AS
        SELECT r.*, j.id AS journal_id, j.journal_no, (j.status = 'POSTED') AS posted, gen_random_uuid() AS reversal_id
          FROM (SELECT r.* FROM finance.payment_reference r
                 WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)
                   AND NOT EXISTS (SELECT 1 FROM people.deferment_fee d WHERE d.reference = r.reference)
                   AND NOT EXISTS (SELECT 1 FROM finance.refund f WHERE f.source_reference = r.reference)
                   AND NOT EXISTS (SELECT 1 FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id = r.id)
                   -- V527: a payment swapped to the student it belongs to stays: a reload of the export neither undoes nor doubles it
                   AND NOT EXISTS (SELECT 1 FROM finance.payment_swap w WHERE w.payment_id = r.id AND w.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL'))
                   -- V631: an OUTSTANDING FEES payment credited to the student's wallet stays
                   AND NOT EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment c WHERE c.payment_id = r.id AND c.status = 'CREDITED')
                 ORDER BY r.id
                 LIMIT p_limit
                 FOR UPDATE OF r) r
          LEFT JOIN finance.gl_journal j ON j.source_type = 'PAYMENT' AND j.source_ref = r.reference;

    -- the income the ledger posted for each, reversed as finance.gl_reverse reverses a journal: a journal of the same lines with
    -- debit and credit swapped, dated today, 'Reversal of #<n> — <reason>', pointing at the one it reverses, which is REVERSED
    INSERT INTO finance.gl_journal (id, entry_date, memo, source, source_type, source_ref, posted_by, reverses)
    SELECT b.reversal_id, current_date, 'Reversal of #' || b.journal_no || ' — old-portal payment ' || b.reference || ' reset: ' || v_reason,
           'MANUAL', 'REVERSAL', b.journal_id::text, v_actor, b.journal_id
      FROM legacy_reset_batch b WHERE b.posted;
    GET DIAGNOSTICS nr = ROW_COUNT;
    INSERT INTO finance.gl_posting (journal_id, line, account, debit, credit, narration, session, fund)
    SELECT b.reversal_id, p.line, p.account, p.credit, p.debit, p.narration, p.session, p.fund
      FROM legacy_reset_batch b JOIN finance.gl_posting p ON p.journal_id = b.journal_id
     WHERE b.posted;
    -- and every such journal no longer holds the reference, so the same payment loaded again is posted afresh, once
    UPDATE finance.gl_journal j
       SET status = CASE WHEN b.posted THEN 'REVERSED' ELSE j.status END,
           source_type = 'PAYMENT_RESET', source_ref = b.reference || '#' || b.id
      FROM legacy_reset_batch b
     WHERE j.id = b.journal_id;

    -- the records kept, then removed (the removal on the audit spine in the caller's name)
    INSERT INTO finance.legacy_payment_reset (id, reference, student_id, session, purpose, amount, confirmed_at, receipt_no, note,
                                             ledger_journal, reversal_journal, reset_by, reason)
    SELECT b.id, b.reference, b.student_id, b.session, b.purpose, b.amount, b.confirmed_at, b.receipt_no, b.note,
           b.journal_id, CASE WHEN b.posted THEN b.reversal_id END, v_actor, v_reason
      FROM legacy_reset_batch b
    ON CONFLICT (id) DO NOTHING;
    DELETE FROM finance.payment_reference r USING legacy_reset_batch b WHERE r.id = b.id;
    GET DIAGNOSTICS n = ROW_COUNT;
    DROP TABLE pg_temp.legacy_reset_batch;

    -- what is kept and what is left, in one pass: the few records something points at looked up by hash, not row by row (6 s
    -- over the 85,000 records of a session on the live-shaped copy as row-by-row checks)
    SELECT count(*) FILTER (WHERE linked), count(*) FILTER (WHERE NOT linked) INTO v_kept, v_left
      FROM (SELECT (r.reference IN (SELECT d.reference FROM people.deferment_fee d)
                    OR r.reference IN (SELECT f.source_reference FROM finance.refund f WHERE f.source_reference IS NOT NULL)
                    OR r.id IN (SELECT g.payment_reference_id FROM finance.legacy_gst_reconciliation g WHERE g.payment_reference_id IS NOT NULL)
                    OR r.id IN (SELECT w.payment_id FROM finance.payment_swap w WHERE w.status IN ('COMPLETED', 'REVERSED', 'PENDING_APPROVAL'))
                    OR r.id IN (SELECT c.payment_id FROM finance.legacy_outstanding_payment c WHERE c.status = 'CREDITED')) AS linked
              FROM finance.payment_reference r
             WHERE r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND (p_session IS NULL OR r.session = p_session)) s;

    RETURN QUERY SELECT n, v_kept, nr, v_left;
END $$;

-- ── 4 · the list ──
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_rows(p_status text, p_session text, p_q text, p_fac text, p_dept text,
                                                                  p_limit integer DEFAULT 500, p_student uuid DEFAULT NULL)
 RETURNS TABLE(payment_id uuid, reference text, old_reference text, student_id uuid, student text, matric_no text, jamb_reg_no text, admission_no text,
               programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, current_level integer,
               student_status text, merged boolean, session text, semester integer, purpose text, amount numeric, paid_at timestamptz, method text,
               note text, status text, due numeric, paid numeric, owed numeric, verified_by text, verified_office text, verified_at timestamptz,
               verify_note text, decided_by text, decided_office text, decided_at timestamptz, decision_note text, batch_ref text,
               wallet_reference text, credited_amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pay AS (
        SELECT r.*, coalesce(c.status, 'WAITING') AS state, c.verified_by AS v_by, c.verified_office AS v_office, c.verified_at AS v_at, c.verify_note AS v_note,
               c.decided_by AS d_by, c.decided_office AS d_office, c.decided_at AS d_at, c.decision_note AS d_note, c.batch_ref AS b_ref, c.wallet_entry_id AS w_id
          FROM finance.payment_reference r
          LEFT JOIN finance.legacy_outstanding_payment c ON c.payment_id = r.id
         WHERE r.channel = 'Legacy' AND r.purpose ~* '^outstanding' AND r.confirmed_at IS NOT NULL
           AND (p_student IS NULL OR r.student_id = p_student)
           AND (p_session IS NULL OR r.session = p_session)
           AND (p_status IS NULL OR coalesce(c.status, 'WAITING') = p_status
                OR (p_status = 'TO_VERIFY' AND coalesce(c.status, 'WAITING') IN ('WAITING', 'RETURNED')))),
    picked AS (
        SELECT pay.*, s.surname || ', ' || s.other_names AS s_name, s.matric_no AS s_matric, s.jamb_reg_no AS s_jamb, s.admission_no AS s_adm,
               s.programme_code AS s_prog, pr.name AS prog_name, pr.dept_code AS s_dept, d.name AS dept_name, pr.faculty_code AS s_fac, f.name AS fac_name,
               s.current_level AS s_level, s.status AS s_status, (s.duplicate_of IS NOT NULL) AS s_merged, lp.payref
          FROM pay
          JOIN people.student s ON s.id = pay.student_id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
          LEFT JOIN LATERAL (SELECT k.payref FROM finance.legacy_payref k WHERE k.reference = pay.reference ORDER BY k.recorded_at LIMIT 1) lp ON true
         WHERE (p_fac IS NULL OR pr.faculty_code = p_fac)
           AND (p_dept IS NULL OR pr.dept_code = p_dept)
           AND (p_q IS NULL OR btrim(p_q) = ''
                OR (s.surname || ' ' || s.other_names) ILIKE '%' || btrim(p_q) || '%'
                OR upper(coalesce(s.matric_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(s.jamb_reg_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(s.admission_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(pay.reference) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(lp.payref, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(pay.b_ref, '')) LIKE '%' || upper(btrim(p_q)) || '%')
         ORDER BY CASE pay.state WHEN 'VERIFIED' THEN 0 WHEN 'RETURNED' THEN 1 WHEN 'WAITING' THEN 2 WHEN 'REJECTED' THEN 3 ELSE 4 END,
                  pay.session DESC, s.surname, s.other_names, pay.reference
         LIMIT greatest(1, least(coalesce(p_limit, 500), 5000)))
    SELECT p.id, p.reference, p.payref, p.student_id, p.s_name, p.s_matric, p.s_jamb, p.s_adm, p.s_prog, p.prog_name, p.s_dept, p.dept_name, p.s_fac, p.fac_name,
           p.s_level, p.s_status, p.s_merged, p.session, substring(p.purpose FROM 'semester ([0-9])')::int, p.purpose, p.amount, p.confirmed_at,
           CASE WHEN p.note LIKE 'Imported from the old portal · %' THEN nullif(btrim(split_part(p.note, ' · ', 2)), '') END, p.note, p.state,
           pos.due, pos.paid, greatest(coalesce(pos.balance, 0), 0),
           helpdesk.person_name(p.v_by), p.v_office, p.v_at, p.v_note, helpdesk.person_name(p.d_by), p.d_office, p.d_at, p.d_note, p.b_ref,
           e.reference, e.amount
      FROM picked p
      LEFT JOIN LATERAL finance.position(p.student_id, p.session) pos ON true
      LEFT JOIN finance.wallet_entry e ON e.id = p.w_id
     ORDER BY CASE p.state WHEN 'VERIFIED' THEN 0 WHEN 'RETURNED' THEN 1 WHEN 'WAITING' THEN 2 WHEN 'REJECTED' THEN 3 ELSE 4 END,
              p.session DESC, p.s_name, p.reference
$function$;
COMMENT ON FUNCTION finance.legacy_outstanding_payment_rows(text, text, text, text, text, integer, uuid) IS 'V631: the old portal''s OUTSTANDING FEES payments, one row a payment — the student, the session and semester, the old payment number and method, the student''s school-fee position on that session (due, paid, owed) and where the payment stands: WAITING, VERIFIED, RETURNED, CREDITED, REJECTED (TO_VERIFY = waiting or returned); by status, session, search, faculty, department or student.';

-- ── 5 · the officer verifies ──
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_verify(p_ids uuid[], p_note text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        n int; v_sum numeric; p uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTOR: a payment is verified by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_verifies(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_OFFICE: an outstanding fees payment is verified by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    -- a payment nothing was done with, or one the Bursar returned to the officer; never one credited or rejected
    WITH cand AS (
        SELECT r.id, r.reference, r.student_id, r.session, r.amount
          FROM finance.payment_reference r
         WHERE r.id = ANY (p_ids) AND r.channel = 'Legacy' AND r.purpose ~* '^outstanding' AND r.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment c WHERE c.payment_id = r.id AND c.status <> 'RETURNED')
         FOR UPDATE OF r),
    done AS (
        INSERT INTO finance.legacy_outstanding_payment AS c (payment_id, reference, student_id, session, amount, status, verified_by, verified_office, verified_at, verify_note)
        SELECT cand.id, cand.reference, cand.student_id, cand.session, cand.amount, 'VERIFIED', who, office, now(), nullif(btrim(coalesce(p_note, '')), '')
          FROM cand
        ON CONFLICT (payment_id) DO UPDATE
           SET status = 'VERIFIED', reference = EXCLUDED.reference, student_id = EXCLUDED.student_id, session = EXCLUDED.session, amount = EXCLUDED.amount,
               verified_by = EXCLUDED.verified_by, verified_office = EXCLUDED.verified_office, verified_at = EXCLUDED.verified_at, verify_note = EXCLUDED.verify_note
         WHERE c.status = 'RETURNED'
        RETURNING c.amount)
    SELECT count(*), coalesce(sum(amount), 0) INTO n, v_sum FROM done;
    -- the Bursar told that verified payments wait to be credited (once a minute at most for each holder)
    IF n > 0 THEN
        FOR p IN SELECT * FROM finance.bursar_holders() LOOP
            BEGIN
                PERFORM platform.tell_person(p, 'LEGACY_OUTSTANDING_WAITING', NULL,
                    jsonb_build_object('PAYMENTS', n, 'AMOUNT', 'NGN ' || to_char(v_sum, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                    'legacy-outstanding:waiting:' || p::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'legacy outstanding fees: the Bursar could not be told (%)', SQLERRM;
            END;
        END LOOP;
    END IF;
    RETURN n;
END $function$;
COMMENT ON FUNCTION finance.legacy_outstanding_payment_verify(uuid[], text) IS 'V631: the Students Account Officer or the Bursar verifies old-portal OUTSTANDING FEES payments (by payment id) that nothing was done with or the Bursar returned; one already verified, credited or rejected is left as it is. The Bursar''s office holders are told what waits.';

-- ── 6 · the Bursar credits the wallet ──
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_credit(p_ids uuid[], p_note text)
 RETURNS TABLE(batch_ref text, credited integer, amount numeric, skipped integer, skipped_why jsonb)
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ref text; w record; v_entry uuid; n int := 0; v_sum numeric := 0; nk int := 0; why jsonb := '[]'::jsonb; v_reason text; v_balance numeric;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTOR: payments are credited by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_OFFICE: verified outstanding fees payments are credited to the wallet by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF coalesce(array_length(p_ids, 1), 0) = 0 THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_NONE: tick the verified payments to credit' USING ERRCODE = '23514'; END IF;
    FOR w IN
        SELECT c.*, r.id AS pay_id, r.amount AS pay_amount, r.student_id AS pay_student, r.purpose AS pay_purpose, r.channel AS pay_channel, r.confirmed_at AS pay_confirmed,
               r.reference AS pay_reference, lp.payref, s.surname, s.other_names, s.matric_no, s.admission_no, s.status AS student_status, s.duplicate_of
          FROM finance.legacy_outstanding_payment c
          JOIN finance.payment_reference r ON r.id = c.payment_id
          JOIN people.student s ON s.id = c.student_id
          LEFT JOIN LATERAL (SELECT k.payref FROM finance.legacy_payref k WHERE k.reference = r.reference ORDER BY k.recorded_at LIMIT 1) lp ON true
         WHERE c.payment_id = ANY (p_ids)
         ORDER BY s.surname, s.other_names, r.reference
         FOR UPDATE OF c, r
    LOOP
        v_reason := CASE WHEN w.status = 'CREDITED' OR w.wallet_entry_id IS NOT NULL THEN 'already credited (' || coalesce(w.batch_ref, 'on the wallet') || ')'
                         WHEN w.status <> 'VERIFIED' THEN 'not verified (' || lower(w.status) || ')'
                         WHEN w.verified_by = who THEN 'verified by you: another Bursar officer credits it'
                         WHEN w.pay_channel <> 'Legacy' OR w.pay_purpose !~* '^outstanding' OR w.pay_confirmed IS NULL THEN 'no longer an old-portal OUTSTANDING FEES payment'
                         WHEN w.pay_student <> w.student_id THEN 'the payment now stands on another student: return it to the officer'
                         WHEN w.pay_amount <> w.amount THEN 'the amount changed since it was verified: return it to the officer'
                         WHEN w.duplicate_of IS NOT NULL THEN 'a duplicate record, merged into another'
                         WHEN w.student_status = 'DECEASED' THEN 'the student is recorded as deceased'
                         END;
        IF v_reason IS NOT NULL THEN
            nk := nk + 1;
            why := why || jsonb_build_object('id', w.payment_id, 'student', w.surname || ', ' || w.other_names, 'number', coalesce(w.matric_no, w.admission_no),
                                             'reference', w.pay_reference, 'why', v_reason);
            CONTINUE;
        END IF;
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || w.student_id::text));
        -- the batch number is drawn with the first credit, so a call that credits nothing uses none
        IF v_ref IS NULL THEN
            v_ref := 'LEGACY-OUTSTANDING/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.legacy_outstanding_batch_seq')::text, 6, '0');
        END IF;
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code, at)
        VALUES (w.student_id, w.session, 'CREDIT', w.amount, v_ref,
                'Old-portal OUTSTANDING FEES payment ' || w.pay_reference || coalesce(' (old payment ' || w.payref || ')', '') || ', ' || w.session
                || coalesce(' semester ' || substring(w.pay_purpose FROM 'semester ([0-9])'), '') || ', credited to the wallet · verified by '
                || coalesce(helpdesk.person_name(w.verified_by), w.verified_office) || ' · ' || v_ref
                || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
                'LEGACY_OUTSTANDING', now())
        RETURNING id INTO v_entry;
        UPDATE finance.legacy_outstanding_payment
           SET status = 'CREDITED', decided_by = who, decided_office = office, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''),
               batch_ref = v_ref, wallet_entry_id = v_entry
         WHERE id = w.id;
        n := n + 1; v_sum := v_sum + w.amount;
        BEGIN
            v_balance := finance.wallet_balance(w.student_id);
            PERFORM platform.tell_student(w.student_id, 'LEGACY_OUTSTANDING_CREDITED', NULL,
                jsonb_build_object('AMOUNT', 'NGN ' || to_char(w.amount, 'FM999,999,999,990.00'), 'SESSION', w.session, 'REFERENCE', w.pay_reference,
                                   'BALANCE', 'NGN ' || to_char(coalesce(v_balance, 0), 'FM999,999,999,990.00')),
                'legacy-outstanding:credited:' || w.payment_id::text);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'legacy outstanding fees %: the student could not be told (%)', w.pay_reference, SQLERRM;
        END;
    END LOOP;
    -- the ids that are no payment on the list at all are said too
    SELECT nk + count(*), why || coalesce(jsonb_agg(jsonb_build_object('id', x, 'student', '', 'number', '', 'reference', '', 'why', 'not verified (waiting)')), '[]'::jsonb)
      INTO nk, why
      FROM unnest(p_ids) x
     WHERE NOT EXISTS (SELECT 1 FROM finance.legacy_outstanding_payment c WHERE c.payment_id = x);
    RETURN QUERY SELECT v_ref, n, v_sum, nk, why;
END $function$;
COMMENT ON FUNCTION finance.legacy_outstanding_payment_credit(uuid[], text) IS 'V631: verified old-portal OUTSTANDING FEES payments credited to the students'' wallets by a Bursar officer other than the one who verified them — one LEGACY_OUTSTANDING credit a payment, its own amount, under a LEGACY-OUTSTANDING/YYYY/NNNNNN batch; a payment not verified, verified by the caller, changed since (amount, student, purpose), of a merged or deceased student, or already credited is skipped and said. The student is told the amount and the balance.';

-- ── 7 · the Bursar rejects, returns or reopens ──
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_decide(p_payment uuid, p_action text, p_reason text)
 RETURNS finance.legacy_outstanding_payment
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_action text := upper(btrim(coalesce(p_action, ''))); r finance.payment_reference; c finance.legacy_outstanding_payment; v_verifier uuid; v_name text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTOR: a payment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_OFFICE: an outstanding fees payment is rejected, returned or reopened by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('REJECT', 'RETURN', 'REOPEN') THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_ACTION: reject, return to the officer or reopen' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_OUTSTANDING_REASON: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment FOR UPDATE;
    IF NOT FOUND OR r.channel <> 'Legacy' OR r.purpose !~* '^outstanding' OR r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_NOT_FOUND: no old-portal OUTSTANDING FEES payment %', p_payment USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO c FROM finance.legacy_outstanding_payment WHERE payment_id = p_payment FOR UPDATE;
    IF c.status = 'CREDITED' THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_CREDITED: payment % is on the student''s wallet (%); it is not decided again', r.reference, c.batch_ref USING ERRCODE = '23514';
    END IF;
    v_verifier := c.verified_by;
    IF v_action = 'RETURN' THEN
        IF c.status IS DISTINCT FROM 'VERIFIED' THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_STATE: only a verified payment waiting to be credited is returned to the officer' USING ERRCODE = '23514';
        END IF;
        IF c.verified_by = who THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_SAME_OFFICER: you verified payment %; another Bursar officer returns or credits it', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF v_action = 'REOPEN' THEN
        IF c.status IS DISTINCT FROM 'REJECTED' THEN
            RAISE EXCEPTION 'LEGACY_OUTSTANDING_STATE: only a rejected payment is reopened' USING ERRCODE = '23514';
        END IF;
    ELSIF c.status = 'REJECTED' THEN
        RAISE EXCEPTION 'LEGACY_OUTSTANDING_STATE: payment % is already rejected' , r.reference USING ERRCODE = '23514';
    END IF;
    -- returned and reopened both go back to the officer to verify again; rejected stays until reopened
    INSERT INTO finance.legacy_outstanding_payment AS x (payment_id, reference, student_id, session, amount, status, decided_by, decided_office, decided_at, decision_note)
    VALUES (r.id, r.reference, r.student_id, r.session, r.amount, CASE v_action WHEN 'REJECT' THEN 'REJECTED' ELSE 'RETURNED' END, who, office, now(), btrim(p_reason))
    ON CONFLICT (payment_id) DO UPDATE
       SET status = EXCLUDED.status, reference = EXCLUDED.reference, student_id = EXCLUDED.student_id, session = EXCLUDED.session, amount = EXCLUDED.amount,
           decided_by = EXCLUDED.decided_by, decided_office = EXCLUDED.decided_office, decided_at = EXCLUDED.decided_at, decision_note = EXCLUDED.decision_note,
           verified_by = NULL, verified_office = NULL, verified_at = NULL, verify_note = NULL
    RETURNING * INTO c;
    SELECT s.surname || ', ' || s.other_names INTO v_name FROM people.student s WHERE s.id = r.student_id;
    BEGIN
        IF v_verifier IS NOT NULL AND v_verifier <> who THEN
            PERFORM platform.tell_person(v_verifier, 'LEGACY_OUTSTANDING_DECIDED', NULL,
                jsonb_build_object('STUDENT', coalesce(v_name, 'the student'), 'REFERENCE', r.reference,
                                   'ACTION', CASE v_action WHEN 'REJECT' THEN 'rejected' ELSE 'returned to you' END,
                                   'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,999,990.00'), 'REASON', btrim(p_reason), 'BURSAR', coalesce(helpdesk.person_name(who), 'the Bursar')),
                'legacy-outstanding:decided:' || r.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        END IF;
        IF v_action = 'REJECT' THEN
            PERFORM platform.tell_student(r.student_id, 'LEGACY_OUTSTANDING_REJECTED', NULL,
                jsonb_build_object('AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,999,990.00'), 'SESSION', r.session, 'REFERENCE', r.reference),
                'legacy-outstanding:rejected:' || r.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'legacy outstanding fees %: the decision could not be told (%)', r.reference, SQLERRM;
    END;
    RETURN c;
END $function$;
COMMENT ON FUNCTION finance.legacy_outstanding_payment_decide(uuid, text, text) IS 'V631: the Bursar rejects an old-portal OUTSTANDING FEES payment not yet credited (the student told), returns a verified one to the officer (an officer other than the verifier) or reopens a rejected one (back to the officer to verify), always with a reason of ten characters or more; the verifier is told. A credited payment is never decided again.';

-- ── 8 · the desk's figures ──
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_payment_figures()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH p AS (
        SELECT r.id, r.student_id, r.session, r.amount, coalesce(c.status, 'WAITING') AS state, c.wallet_entry_id
          FROM finance.payment_reference r
          LEFT JOIN finance.legacy_outstanding_payment c ON c.payment_id = r.id
         WHERE r.channel = 'Legacy' AND r.purpose ~* '^outstanding' AND r.confirmed_at IS NOT NULL),
    used AS (
        SELECT coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded
          FROM finance.wallet_entry e WHERE e.source_code = 'LEGACY_OUTSTANDING' AND e.kind IN ('APPLIED', 'REFUND'))
    SELECT jsonb_build_object(
        'payments', (SELECT count(*) FROM p), 'amount', (SELECT coalesce(sum(amount), 0) FROM p), 'students', (SELECT count(DISTINCT student_id) FROM p),
        'waiting', (SELECT count(*) FROM p WHERE state = 'WAITING'), 'waitingAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'WAITING'),
        'returned', (SELECT count(*) FROM p WHERE state = 'RETURNED'), 'returnedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'RETURNED'),
        'verified', (SELECT count(*) FROM p WHERE state = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'VERIFIED'),
        'credited', (SELECT count(*) FROM p WHERE state = 'CREDITED'), 'creditedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'CREDITED'),
        'creditedStudents', (SELECT count(DISTINCT student_id) FROM p WHERE state = 'CREDITED'),
        'rejected', (SELECT count(*) FROM p WHERE state = 'REJECTED'), 'rejectedAmount', (SELECT coalesce(sum(amount), 0) FROM p WHERE state = 'REJECTED'),
        'applied', (SELECT applied FROM used), 'refunded', (SELECT refunded FROM used),
        'sessions', (SELECT coalesce(jsonb_agg(x ORDER BY x.session DESC), '[]'::jsonb) FROM (
                        SELECT p.session, count(*) AS payments, sum(p.amount) AS amount, count(*) FILTER (WHERE p.state = 'CREDITED') AS credited,
                               coalesce(sum(p.amount) FILTER (WHERE p.state = 'CREDITED'), 0) AS "creditedAmount"
                          FROM p GROUP BY p.session) x),
        'batches', (SELECT coalesce(jsonb_agg(b ORDER BY b.credited_at DESC), '[]'::jsonb) FROM (
                        SELECT c.batch_ref AS ref, max(c.decided_at) AS credited_at, count(*) AS payments, sum(c.amount) AS amount,
                               helpdesk.person_name((array_agg(c.decided_by))[1]) AS credited_by, max(c.decided_office) AS office
                          FROM finance.legacy_outstanding_payment c WHERE c.status = 'CREDITED'
                         GROUP BY c.batch_ref ORDER BY max(c.decided_at) DESC LIMIT 50) b))
$function$;
COMMENT ON FUNCTION finance.legacy_outstanding_payment_figures() IS 'V631: the old portal''s OUTSTANDING FEES payments in figures — all of them (payments, students, amount), waiting, returned, verified, credited, rejected; what the credits have paid on fees or refunded; by session; the credit batches.';

-- ── 9 · the notices ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('LEGACY_OUTSTANDING_WAITING', 'Old-portal outstanding fees payments verified and waiting',
 'To the Bursar''s office holders when the Students Account Officer has verified old-portal OUTSTANDING FEES payments that wait to be credited to the students'' wallets',
 '[PAYMENTS] old-portal outstanding fees payment(s) verified, waiting for your credit',
 E'[OFFICER] has verified [PAYMENTS] payment(s) the old portal filed as OUTSTANDING FEES, [AMOUNT] in all. They wait for a Bursar officer other than the verifier to credit them to the students'' wallets, or to return them to the officer, on Legacy Financial Reconciliation → Outstanding fees payments.',
 '[UNIVERSITY_SHORT]: [PAYMENTS] old-portal outstanding fees payment(s) ([AMOUNT]) verified by [OFFICER] wait for your credit.',
 'Outstanding fees payments wait for your credit',
 '[OFFICER] verified [PAYMENTS] old-portal OUTSTANDING FEES payment(s) of [AMOUNT]. Credit them to the wallets, or return them to the officer, on Legacy Financial Reconciliation.',
 ARRAY['PAYMENTS','AMOUNT','OFFICER','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_OUTSTANDING_DECIDED', 'Old-portal outstanding fees payment decided by the Bursar',
 'To the officer who verified an old-portal OUTSTANDING FEES payment when the Bursar rejects it or returns it for correction',
 'Outstanding fees payment of [STUDENT] [ACTION]',
 E'The old-portal OUTSTANDING FEES payment [REFERENCE] of [AMOUNT] you verified for [STUDENT] was [ACTION] by [BURSAR].\n\nReason: [REASON]\n\nA payment returned to you is checked again and verified afresh on Legacy Financial Reconciliation → Outstanding fees payments.',
 '[UNIVERSITY_SHORT]: the outstanding fees payment [REFERENCE] of [STUDENT] ([AMOUNT]) was [ACTION] by the Bursar: [REASON]',
 'Outstanding fees payment [ACTION]',
 'The payment [REFERENCE] of [AMOUNT] you verified for [STUDENT] was [ACTION] by [BURSAR]: [REASON]',
 ARRAY['STUDENT','REFERENCE','AMOUNT','ACTION','REASON','BURSAR','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_OUTSTANDING_CREDITED', 'Old-portal outstanding fees payment credited to the wallet',
 'To a student whose payment the old portal filed as OUTSTANDING FEES the Bursar has verified and credited to their wallet',
 'Your outstanding fees payment of [AMOUNT] is on your wallet',
 E'Dear [FIRST_NAME],\n\nThe [AMOUNT] you paid on the old portal as OUTSTANDING FEES for [SESSION] (reference [REFERENCE]) has been verified by the Bursary and credited to your wallet. Your wallet balance is now [BALANCE].\n\nYou can apply it to your school fees from the wallet page on the portal, and pay any shortfall through the gateway as usual.',
 '[UNIVERSITY_SHORT]: your outstanding fees payment of [AMOUNT] ([SESSION]) is on your wallet. Balance [BALANCE]. Apply it to your fees on the portal.',
 'Your outstanding fees payment is on your wallet',
 'The [AMOUNT] you paid on the old portal as OUTSTANDING FEES for [SESSION] (ref [REFERENCE]) is on your wallet; your balance is [BALANCE]. Apply it to your school fees from the wallet page.',
 ARRAY['FIRST_NAME','AMOUNT','SESSION','REFERENCE','BALANCE','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_OUTSTANDING_REJECTED', 'Old-portal outstanding fees payment not credited',
 'To a student whose old-portal OUTSTANDING FEES payment the Bursar has rejected after review',
 'Your outstanding fees payment was not credited to your wallet',
 E'Dear [FIRST_NAME],\n\nAfter review, the Bursary could not credit to your wallet the [AMOUNT] the old portal''s records show you paid as OUTSTANDING FEES for [SESSION] (reference [REFERENCE]). If you hold the receipt or the old portal''s statement for it, bring it to the Bursary (Students Account) so the record can be reviewed again.',
 '[UNIVERSITY_SHORT]: your outstanding fees payment of [AMOUNT] ([SESSION]) was not credited to your wallet after review. Bring your receipt to the Bursary to have it reviewed again.',
 'Your outstanding fees payment was not credited',
 'After review the Bursary could not credit the [AMOUNT] you paid on the old portal as OUTSTANDING FEES for [SESSION] (ref [REFERENCE]). Bring your receipt to the Bursary to have it reviewed again.',
 ARRAY['FIRST_NAME','AMOUNT','SESSION','REFERENCE','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

COMMIT;
