-- V625: legacy financial reconciliation — the Students Account Officer's desk for the old portal's outstanding fees and e-wallet
-- top-ups, with the Bursar's approval before any wallet credit (the University's brief of 21 October 2026).
--
-- What the portal already held, and what this migration adds to it:
--   · The old portal's e-wallet (V583): finance.legacy_wallet, one row a student — top-ups less the fees paid from the old wallet,
--     verified by the Students Account Officer, posted to the wallet by a different Bursar officer, one LEGACY_WALLET credit a
--     student. V625 adds the Bursar's RETURN for correction (status RETURNED; the officer corrects and verifies again), and the
--     notices between the desks: the Bursar told of balances verified and waiting, the verifier told of the Bursar's decision, the
--     student told of a rejection.
--   · The old portal's outstanding fees: the old-fees import (V498) and the reconciliation by session (finance.old_fees_reconciliation)
--     already classify each student of a session — UNDER (the student owes the University), OVER (the student paid more than the
--     fees stated: a credit the University holds), OVER_SETTLED (carried into the next session or refunded, V506), NO_FEE_STATED.
--     An outstanding fee is a liability of the student and is never wallet money. The one thing missing was the controlled road from
--     a verified overpayment to the student's wallet: finance.legacy_credit_request (LOR/YYYY/NNNNNN) — the officer confirms the
--     amount (never above the excess; a different amount names its reason and is marked adjusted), the evidence and the reason; a
--     Bursar officer other than the one who initiated approves, rejects or returns it; on approval the wallet that exists is credited
--     once (funding source OVERPAID, the student's own money), the overpayment is decided WALLET so it can never also be carried or
--     refunded (V506), the student and the officer are told. Nothing is credited at the officer's stage; nothing is credited twice.
--   · Dashboards and the report read finance.legacy_reconciliation_figures, finance.legacy_outstanding_rows and
--     finance.legacy_credit_rows; the student's full record reads finance.legacy_credit_of.
-- Nothing registered, paid, posted or issued is deleted or rewritten; the original old-portal records stay as imported (V498, V609).

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V625: legacy financial reconciliation (the University, 21 October 2026)', true);

-- ── the funding source: a verified overpayment credited to the wallet ──
INSERT INTO finance.funding_source (code, name, nature, sponsor, account, active, note, sort)
VALUES ('OVERPAID', 'Overpaid school fees credited to the wallet', 'SELF', NULL, NULL, true,
        'School fees the student paid above the fees stated for a session, verified by the Students Account Officer and credited to the wallet by the Bursar (V625). The student''s own money: applied to fees after a loan or a grant, refundable as own money. On the ledger it moves from the session''s fee income to the wallet; no new cash.', 85)
ON CONFLICT (code) DO NOTHING;

-- the ledger: an OVERPAID credit is drawn from the school-fees income of the overpaid session (the entry''s session) into 2100
CREATE OR REPLACE FUNCTION finance.gl_wallet_credit_account(p_source text, p_legacy boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN p_legacy OR p_source = 'LEGACY_WALLET' THEN '3900'
                WHEN p_source = 'OVERPAID' THEN finance.gl_income_account('School fees')
                WHEN (SELECT fs.nature FROM finance.funding_source fs WHERE fs.code = p_source) = 'GRANT' THEN '5240'
                ELSE '1010' END
$function$;
COMMENT ON FUNCTION finance.gl_wallet_credit_account(text, boolean) IS 'V545, V583, V625: the account a wallet credit is drawn from — cash for a loan or the student''s own top-up, the scholarship expense for a grant, suspense for an old-portal credit (NELFUND or e-wallet), the session''s school-fees income for an overpayment credited to the wallet (no new cash).';

-- ── the old portal's e-wallet: returned for correction, and the desks told ──
ALTER TABLE finance.legacy_wallet DROP CONSTRAINT legacy_wallet_status_check;
ALTER TABLE finance.legacy_wallet ADD CONSTRAINT legacy_wallet_status_check
    CHECK (status IN ('COMPUTED', 'VERIFIED', 'POSTED', 'NO_BALANCE', 'REQUIRES_REVIEW', 'REJECTED', 'FROZEN', 'RETURNED'));

-- the Bursar's office holders, today
CREATE OR REPLACE FUNCTION finance.bursar_holders()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
AS $function$
    SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
     WHERE oa.office_code = 'bursar'
       AND oa.valid_from <= (now() AT TIME ZONE 'Africa/Lagos')::date AND (oa.valid_to IS NULL OR oa.valid_to >= (now() AT TIME ZONE 'Africa/Lagos')::date)
$function$;
COMMENT ON FUNCTION finance.bursar_holders() IS 'V625: the persons holding the Bursar office today — told of what waits on the Bursar.';

CREATE OR REPLACE FUNCTION finance.legacy_wallet_verify(p_ids uuid[], p_note text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); n int; v_sum numeric; p uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_WALLET_ACTOR: a balance is verified by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_verifies(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_WALLET_OFFICE: a balance is verified by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    -- V625: a balance the Bursar returned for correction is verified again once the officer has corrected it
    WITH done AS (
        UPDATE finance.legacy_wallet w
           SET status = 'VERIFIED', verified_by = who, verified_office = office, verified_at = now(), verify_note = nullif(btrim(coalesce(p_note, '')), '')
         WHERE w.id = ANY (p_ids) AND w.status IN ('COMPUTED', 'RETURNED') AND w.available > 0
         RETURNING w.available)
    SELECT count(*), coalesce(sum(available), 0) INTO n, v_sum FROM done;
    -- V625: the Bursar told that verified balances wait for a posting (once a minute at most for each holder)
    IF n > 0 THEN
        FOR p IN SELECT * FROM finance.bursar_holders() LOOP
            BEGIN
                PERFORM platform.tell_person(p, 'LEGACY_WALLET_WAITING', NULL,
                    jsonb_build_object('STUDENTS', n, 'AMOUNT', 'NGN ' || to_char(v_sum, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                    'legacy-wallet:waiting:' || p::text || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'legacy wallet: the Bursar could not be told (%)', SQLERRM;
            END;
        END LOOP;
    END IF;
    RETURN n;
END $function$;
COMMENT ON FUNCTION finance.legacy_wallet_verify(uuid[], text) IS 'V583, V625: the Students Account Officer or the Bursar verifies computed balances (and balances the Bursar returned for correction); the Bursar''s office holders are told what waits.';

CREATE OR REPLACE FUNCTION finance.legacy_wallet_decide(p_id uuid, p_action text, p_reason text)
 RETURNS finance.legacy_wallet
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        w finance.legacy_wallet; v_verifier uuid; v_name text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_WALLET_ACTOR: a wallet is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_wallet_office_posts(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_WALLET_OFFICE: a wallet is rejected, frozen, returned or reopened by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_action IS NULL OR p_action NOT IN ('REJECT', 'FREEZE', 'REOPEN', 'RETURN') THEN
        RAISE EXCEPTION 'LEGACY_WALLET_ACTION: reject, freeze, return for correction or reopen' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_WALLET_REASON: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO w FROM finance.legacy_wallet WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_WALLET_NOT_FOUND: no such wallet' USING ERRCODE = 'P0002'; END IF;
    IF w.status = 'POSTED' THEN RAISE EXCEPTION 'LEGACY_WALLET_POSTED: this balance is on the wallet; it is not decided here' USING ERRCODE = '23514'; END IF;
    v_verifier := w.verified_by;
    SELECT s.surname || ', ' || s.other_names INTO v_name FROM people.student s WHERE s.id = w.student_id;
    IF p_action = 'REOPEN' THEN
        IF w.status NOT IN ('REJECTED', 'FROZEN') THEN RAISE EXCEPTION 'LEGACY_WALLET_STATE: only a rejected or frozen wallet is reopened' USING ERRCODE = '23514'; END IF;
        UPDATE finance.legacy_wallet SET status = 'COMPUTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason),
               verified_by = NULL, verified_office = NULL, verified_at = NULL WHERE id = p_id RETURNING * INTO w;
        PERFORM finance.legacy_wallet_compute(w.student_id);
        SELECT * INTO w FROM finance.legacy_wallet WHERE id = p_id;
        RETURN w;
    END IF;
    -- V625: returned for correction — only a verified balance waiting for a posting; the verifier corrects it and verifies again
    IF p_action = 'RETURN' THEN
        IF w.status <> 'VERIFIED' THEN RAISE EXCEPTION 'LEGACY_WALLET_STATE: only a verified balance waiting for a posting is returned for correction' USING ERRCODE = '23514'; END IF;
        IF w.verified_by = who THEN RAISE EXCEPTION 'LEGACY_WALLET_SAME_OFFICER: you verified this balance; another Bursar officer returns or posts it' USING ERRCODE = '23514'; END IF;
        UPDATE finance.legacy_wallet SET status = 'RETURNED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason),
               verified_by = NULL, verified_office = NULL, verified_at = NULL
         WHERE id = p_id RETURNING * INTO w;
    ELSE
        UPDATE finance.legacy_wallet SET status = CASE p_action WHEN 'REJECT' THEN 'REJECTED' ELSE 'FROZEN' END, decided_by = who, decided_office = office, decided_at = now(),
               decision_note = btrim(p_reason), verified_by = NULL, verified_office = NULL, verified_at = NULL
         WHERE id = p_id RETURNING * INTO w;
    END IF;
    -- V625: the verifier told of the decision; the student told of a rejection (the reason stays on the desk)
    BEGIN
        IF v_verifier IS NOT NULL AND v_verifier <> who THEN
            PERFORM platform.tell_person(v_verifier, 'LEGACY_WALLET_DECIDED', NULL,
                jsonb_build_object('STUDENT', coalesce(v_name, 'the student'), 'ACTION', CASE p_action WHEN 'REJECT' THEN 'rejected' WHEN 'FREEZE' THEN 'frozen' ELSE 'returned for correction' END,
                                   'AMOUNT', 'NGN ' || to_char(w.available, 'FM999,999,999,990.00'), 'REASON', btrim(p_reason), 'BURSAR', coalesce(helpdesk.person_name(who), 'the Bursar')),
                'legacy-wallet:decided:' || w.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        END IF;
        IF p_action = 'REJECT' THEN
            PERFORM platform.tell_student(w.student_id, 'LEGACY_WALLET_REJECTED', NULL, jsonb_build_object('AMOUNT', 'NGN ' || to_char(w.available, 'FM999,999,999,990.00')),
                'legacy-wallet:rejected:' || w.id::text || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'legacy wallet %: the decision could not be told (%)', w.id, SQLERRM;
    END;
    RETURN w;
END $function$;
COMMENT ON FUNCTION finance.legacy_wallet_decide(uuid, text, text) IS 'V583, V625: the Bursar rejects, freezes, returns for correction (a verified balance, by an officer other than the verifier) or reopens a balance, with a reason; the verifier is told, the student told of a rejection.';

-- ── the overpayment decided WALLET: a third way, taken only through the request below ──
ALTER TABLE finance.overpayment_decision DROP CONSTRAINT overpayment_decision_decision_check;
ALTER TABLE finance.overpayment_decision ADD CONSTRAINT overpayment_decision_decision_check CHECK (decision IN ('CARRY', 'REFUND', 'WALLET'));
COMMENT ON COLUMN finance.overpayment_decision.decision IS 'CARRY into the next session or REFUND (V506); WALLET — credited to the student''s wallet on a legacy credit request the Bursar approved (V625). One decision stands a student and session: the others are refused while it does.';

-- ── the legacy credit request: a verified overpayment on its way to the wallet ──
CREATE SEQUENCE IF NOT EXISTS finance.legacy_credit_request_seq;
CREATE TABLE finance.legacy_credit_request (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref                text NOT NULL UNIQUE CHECK (ref ~ '^LOR/[0-9]{4}/[0-9]{6}$'),
    student_id         uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    session            text NOT NULL,
    kind               text NOT NULL DEFAULT 'OVERPAID' CHECK (kind IN ('OVERPAID')),
    due                numeric(14,2) NOT NULL,
    paid               numeric(14,2) NOT NULL,
    legacy_amount      numeric(14,2) NOT NULL CHECK (legacy_amount >= 1),
    confirmed_amount   numeric(14,2) NOT NULL CHECK (confirmed_amount >= 1),
    adjusted           boolean GENERATED ALWAYS AS (confirmed_amount <> legacy_amount) STORED,
    adjustment_reason  text,
    reason             text NOT NULL CHECK (length(btrim(reason)) >= 10),
    evidence           text NOT NULL CHECK (length(btrim(evidence)) >= 3),
    status             text NOT NULL DEFAULT 'PENDING_BURSAR_APPROVAL'
                       CHECK (status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'CREDITED', 'REJECTED', 'WITHDRAWN')),
    initiated_by       uuid NOT NULL,
    initiated_office   text NOT NULL,
    initiated_at       timestamptz NOT NULL DEFAULT now(),
    resubmitted_at     timestamptz,
    resubmissions      integer NOT NULL DEFAULT 0,
    decided_by         uuid,
    decided_office     text,
    decided_at         timestamptz,
    decision_note      text,
    withdrawn_by       uuid,
    withdrawn_at       timestamptz,
    withdraw_reason    text,
    wallet_entry_id    uuid UNIQUE REFERENCES finance.wallet_entry (id) ON DELETE CASCADE,
    decision_id        uuid REFERENCES finance.overpayment_decision (id) ON DELETE CASCADE,
    CONSTRAINT ck_lcr_amount CHECK (confirmed_amount <= legacy_amount),
    CONSTRAINT ck_lcr_adjusted CHECK (confirmed_amount = legacy_amount OR length(btrim(coalesce(adjustment_reason, ''))) >= 10),
    CONSTRAINT ck_lcr_two_officers CHECK (decided_by IS NULL OR decided_by <> initiated_by),
    CONSTRAINT ck_lcr_credited CHECK (status <> 'CREDITED' OR (wallet_entry_id IS NOT NULL AND decision_id IS NOT NULL AND decided_by IS NOT NULL)),
    CONSTRAINT ck_lcr_withdrawn CHECK (status <> 'WITHDRAWN' OR withdrawn_by IS NOT NULL)
);
CREATE UNIQUE INDEX ux_lcr_open ON finance.legacy_credit_request (student_id, session) WHERE status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION');
CREATE INDEX ix_lcr_status ON finance.legacy_credit_request (status);
CREATE INDEX ix_lcr_student ON finance.legacy_credit_request (student_id);
COMMENT ON TABLE finance.legacy_credit_request IS 'V625: a verified overpayment of school fees on its way to the student''s wallet (LOR/YYYY/NNNNNN) — initiated by the Students Account Officer or the Bursar with the amount confirmed (never above the excess; a different amount names its reason and is marked adjusted), the evidence and the reason; approved, rejected or returned for correction by a Bursar officer other than the initiator; approval credits the wallet once (OVERPAID) and decides the overpayment WALLET. The original old-portal records and the payments stay as they are.';
SELECT audit.attach('finance.legacy_credit_request');

CREATE OR REPLACE FUNCTION finance.legacy_credit_office_initiates(p_office text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_office IN ('studentaccounts', 'bursar', 'super') $$;
CREATE OR REPLACE FUNCTION finance.legacy_credit_office_decides(p_office text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_office IN ('bursar', 'super') $$;

-- the overpayment of one student on one session as the reconciliation reads it today: NULL when none
CREATE OR REPLACE FUNCTION finance.legacy_credit_excess(p_student uuid, p_session text)
 RETURNS TABLE(due numeric, paid numeric, excess numeric, decision text, decision_reference text, held boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT x.due, x.paid, x.excess, x.decision, x.reference,
           EXISTS (SELECT 1 FROM finance.possible_double_charges(p_session) d
                    WHERE d.student_id = p_student AND d.purpose LIKE 'School fees%' AND (d.verdict IS NULL OR d.open_requests > 0))
      FROM finance.overpaid(p_session) x WHERE x.student_id = p_student
$function$;
COMMENT ON FUNCTION finance.legacy_credit_excess(uuid, text) IS 'V625: what a student paid above the fees stated for a session, as finance.overpaid reads it, with any decision standing and whether the Bursary''s bank check (V561) still holds it.';

CREATE OR REPLACE FUNCTION finance.legacy_credit_initiate(p_student uuid, p_session text, p_amount numeric, p_reason text, p_evidence text, p_adjust_reason text)
 RETURNS finance.legacy_credit_request
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; x record; r finance.legacy_credit_request; v_amount numeric; v_ref text; p uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is made by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_initiates(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is initiated by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_CREDIT_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    IF s.duplicate_of IS NOT NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_STUDENT: this record is a duplicate merged into another; the credit is requested on the record kept' USING ERRCODE = '23514'; END IF;
    IF s.status = 'DECEASED' THEN RAISE EXCEPTION 'LEGACY_CREDIT_STUDENT: the student is recorded as deceased; the estate is paid by refund, not by wallet credit' USING ERRCODE = '23514'; END IF;
    IF p_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_SESSION: name the session the fees were overpaid on' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_CREDIT_REASON: say why the credit is due, in ten characters or more' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_evidence, ''))) < 3 THEN RAISE EXCEPTION 'LEGACY_CREDIT_EVIDENCE: name the legacy record or evidence the amount was checked against (the old portal''s statement, the receipt, the export row)' USING ERRCODE = '23514'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('overpay:' || p_student::text || ':' || p_session));
    IF EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.student_id = p_student AND q.session = p_session AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OPEN: a credit request already stands for this student on %; decide or withdraw it first', p_session USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM finance.legacy_credit_excess(p_student, p_session);
    IF x.excess IS NULL OR x.excess < 1 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_NOT_OVERPAID: the student has not paid above the fees stated for %; an outstanding fee is what the student owes the University, never money for the wallet', p_session USING ERRCODE = '23514',
            HINT = 'A credit is requested only on a session the reconciliation shows as overpaid.';
    END IF;
    IF x.decision IS NOT NULL THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_SETTLED: the overpayment on % is already decided (%, %)', p_session, lower(x.decision), x.decision_reference USING ERRCODE = '23514';
    END IF;
    IF x.held THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: the Bursary is checking with the bank whether the student''s school fees were charged twice (V561); the credit waits for the verdict' USING ERRCODE = '23514';
    END IF;
    v_amount := coalesce(p_amount, x.excess);
    IF v_amount < 1 OR v_amount > x.excess THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_AMOUNT: the amount to credit is between NGN 1 and the excess paid, NGN %', to_char(x.excess, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    IF v_amount <> x.excess AND length(btrim(coalesce(p_adjust_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_ADJUSTMENT_REASON: the amount differs from the excess the records show (NGN %); say why, in ten characters or more', to_char(x.excess, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    v_ref := 'LOR/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.legacy_credit_request_seq')::text, 6, '0');
    INSERT INTO finance.legacy_credit_request (ref, student_id, session, due, paid, legacy_amount, confirmed_amount, adjustment_reason, reason, evidence, initiated_by, initiated_office)
    VALUES (v_ref, p_student, p_session, x.due, x.paid, x.excess, v_amount, CASE WHEN v_amount <> x.excess THEN btrim(p_adjust_reason) END, btrim(p_reason), btrim(p_evidence), who, office)
    RETURNING * INTO r;
    -- the Bursar told a request waits
    FOR p IN SELECT * FROM finance.bursar_holders() LOOP
        BEGIN
            PERFORM platform.tell_person(p, 'LEGACY_CREDIT_WAITING', NULL,
                jsonb_build_object('REF', r.ref, 'STUDENT', s.surname || ', ' || s.other_names, 'NUMBER', coalesce(s.matric_no, s.admission_no), 'SESSION', p_session,
                                   'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                'legacy-credit:' || r.ref || ':waiting:' || p::text);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'legacy credit %: the Bursar could not be told (%)', r.ref, SQLERRM;
        END;
    END LOOP;
    RETURN r;
END $function$;
COMMENT ON FUNCTION finance.legacy_credit_initiate(uuid, text, numeric, text, text, text) IS 'V625: the Students Account Officer (or the Bursar) confirms a student''s overpayment on a session and initiates the wallet credit — the amount never above the excess the records show (a different amount names its reason and is marked adjusted), the evidence and the reason named; refused where the student owes or is settled, where the overpayment is already decided, where the bank check holds the student, or where a request already stands. Nothing is credited here; the Bursar is told.';

CREATE OR REPLACE FUNCTION finance.legacy_credit_resubmit(p_id uuid, p_amount numeric, p_reason text, p_evidence text, p_adjust_reason text)
 RETURNS finance.legacy_credit_request
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.legacy_credit_request; x record; v_amount numeric; s people.student; p uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is resubmitted by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_initiates(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is corrected by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO r FROM finance.legacy_credit_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_CREDIT_NOT_FOUND: no such request' USING ERRCODE = 'P0002'; END IF;
    IF r.status <> 'RETURNED_FOR_CORRECTION' THEN RAISE EXCEPTION 'LEGACY_CREDIT_STATE: request % is %; only one returned for correction is resubmitted', r.ref, lower(replace(r.status, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_CREDIT_REASON: say why the credit is due, in ten characters or more' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_evidence, ''))) < 3 THEN RAISE EXCEPTION 'LEGACY_CREDIT_EVIDENCE: name the legacy record or evidence the amount was checked against' USING ERRCODE = '23514'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('overpay:' || r.student_id::text || ':' || r.session));
    SELECT * INTO x FROM finance.legacy_credit_excess(r.student_id, r.session);
    IF x.excess IS NULL OR x.excess < 1 THEN RAISE EXCEPTION 'LEGACY_CREDIT_NOT_OVERPAID: the records no longer show an overpayment on %; withdraw the request', r.session USING ERRCODE = '23514'; END IF;
    IF x.decision IS NOT NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_SETTLED: the overpayment on % is already decided (%, %)', r.session, lower(x.decision), x.decision_reference USING ERRCODE = '23514'; END IF;
    v_amount := coalesce(p_amount, x.excess);
    IF v_amount < 1 OR v_amount > x.excess THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_AMOUNT: the amount to credit is between NGN 1 and the excess paid, NGN %', to_char(x.excess, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    IF v_amount <> x.excess AND length(btrim(coalesce(p_adjust_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_ADJUSTMENT_REASON: the amount differs from the excess the records show (NGN %); say why, in ten characters or more', to_char(x.excess, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    UPDATE finance.legacy_credit_request
       SET due = x.due, paid = x.paid, legacy_amount = x.excess, confirmed_amount = v_amount, adjustment_reason = CASE WHEN v_amount <> x.excess THEN btrim(p_adjust_reason) END,
           reason = btrim(p_reason), evidence = btrim(p_evidence), status = 'PENDING_BURSAR_APPROVAL', resubmitted_at = now(), resubmissions = resubmissions + 1,
           decided_by = NULL, decided_office = NULL, decided_at = NULL
     WHERE id = p_id RETURNING * INTO r;
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    FOR p IN SELECT * FROM finance.bursar_holders() LOOP
        BEGIN
            PERFORM platform.tell_person(p, 'LEGACY_CREDIT_WAITING', NULL,
                jsonb_build_object('REF', r.ref, 'STUDENT', s.surname || ', ' || s.other_names, 'NUMBER', coalesce(s.matric_no, s.admission_no), 'SESSION', r.session,
                                   'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                'legacy-credit:' || r.ref || ':waiting:' || r.resubmissions || ':' || p::text);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'legacy credit %: the Bursar could not be told (%)', r.ref, SQLERRM;
        END;
    END LOOP;
    RETURN r;
END $function$;
COMMENT ON FUNCTION finance.legacy_credit_resubmit(uuid, numeric, text, text, text) IS 'V625: a request the Bursar returned for correction, corrected and sent again — the excess read afresh, the same rules as the first submission; the decision note stays on the record.';

CREATE OR REPLACE FUNCTION finance.legacy_credit_withdraw(p_id uuid, p_reason text)
 RETURNS finance.legacy_credit_request
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); r finance.legacy_credit_request;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_initiates(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is withdrawn by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_CREDIT_REASON: say why it is withdrawn, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.legacy_credit_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_CREDIT_NOT_FOUND: no such request' USING ERRCODE = 'P0002'; END IF;
    IF r.status NOT IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION') THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_STATE: request % is %; only one waiting or returned is withdrawn', r.ref, lower(replace(r.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    UPDATE finance.legacy_credit_request SET status = 'WITHDRAWN', withdrawn_by = who, withdrawn_at = now(), withdraw_reason = btrim(p_reason) WHERE id = p_id RETURNING * INTO r;
    RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION finance.legacy_credit_decide(p_id uuid, p_action text, p_note text)
 RETURNS finance.legacy_credit_request
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.legacy_credit_request; s people.student; x record; v_entry uuid; v_decision uuid; v_balance numeric; v_action text := upper(btrim(coalesce(p_action, '')));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_decides(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is approved, rejected or returned by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('APPROVE', 'REJECT', 'RETURN') THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTION: approve, reject or return for correction' USING ERRCODE = '23514'; END IF;
    IF v_action <> 'APPROVE' AND length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_NOTE: say why it is % , in ten characters or more', CASE v_action WHEN 'REJECT' THEN 'rejected' ELSE 'returned' END USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM finance.legacy_credit_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_CREDIT_NOT_FOUND: no such request' USING ERRCODE = 'P0002'; END IF;
    IF r.status <> 'PENDING_BURSAR_APPROVAL' THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_STATE: request % is %; only one waiting for the Bursar is decided', r.ref, lower(replace(r.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF r.initiated_by = who THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_SAME_OFFICER: you initiated request %; another Bursar officer decides it', r.ref USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    IF v_action = 'APPROVE' THEN
        -- all or nothing: the overpayment locked, read afresh, the wallet credited once, the overpayment decided, the request closed
        PERFORM pg_advisory_xact_lock(hashtext('overpay:' || r.student_id::text || ':' || r.session));
        PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
        IF EXISTS (SELECT 1 FROM finance.overpayment_settled(r.student_id, r.session)) THEN
            RAISE EXCEPTION 'LEGACY_CREDIT_SETTLED: the overpayment on % is already decided; nothing is credited twice', r.session USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.student_id = r.student_id AND q.session = r.session AND q.status = 'CREDITED') THEN
            RAISE EXCEPTION 'LEGACY_CREDIT_ALREADY_CREDITED: this legacy record has already been credited to the wallet' USING ERRCODE = '23514';
        END IF;
        SELECT * INTO x FROM finance.legacy_credit_excess(r.student_id, r.session);
        IF x.excess IS NULL OR x.excess < r.confirmed_amount THEN
            RAISE EXCEPTION 'LEGACY_CREDIT_EXCESS_CHANGED: the records now show an excess of NGN % on %, below the NGN % confirmed; return the request for correction', coalesce(to_char(x.excess, 'FM999,999,999,990.00'), '0.00'), r.session, to_char(r.confirmed_amount, 'FM999,999,999,990.00') USING ERRCODE = '23514';
        END IF;
        IF x.held THEN
            RAISE EXCEPTION 'LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: the Bursary is checking with the bank whether the student''s school fees were charged twice (V561); the credit waits for the verdict' USING ERRCODE = '23514';
        END IF;
        IF s.duplicate_of IS NOT NULL OR s.status = 'DECEASED' THEN
            RAISE EXCEPTION 'LEGACY_CREDIT_STUDENT: the student record is merged or recorded as deceased; the credit is not posted' USING ERRCODE = '23514';
        END IF;
        INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code, at)
        VALUES (r.student_id, r.session, 'CREDIT', r.confirmed_amount, r.ref,
                'School fees overpaid on ' || r.session || ' (paid NGN ' || to_char(r.paid, 'FM999,999,999,990.00') || ', due NGN ' || to_char(r.due, 'FM999,999,999,990.00')
                || ') credited to the wallet on request ' || r.ref || ', confirmed by ' || coalesce(helpdesk.person_name(r.initiated_by), 'the Students Account Officer')
                || ' (' || r.evidence || ') and approved by the Bursar' || CASE WHEN r.adjusted THEN ' — amount adjusted from NGN ' || to_char(r.legacy_amount, 'FM999,999,999,990.00') || ': ' || r.adjustment_reason ELSE '' END,
                'OVERPAID', now())
        RETURNING id INTO v_entry;
        INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, reference, decided_by, reason)
        VALUES (r.student_id, r.session, r.due, r.paid, r.confirmed_amount, 'WALLET', r.ref, who, 'Credited to the wallet on request ' || r.ref || ': ' || r.reason)
        RETURNING id INTO v_decision;
        UPDATE finance.legacy_credit_request
           SET status = 'CREDITED', decided_by = who, decided_office = office, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''),
               wallet_entry_id = v_entry, decision_id = v_decision
         WHERE id = p_id RETURNING * INTO r;
        v_balance := finance.wallet_balance(r.student_id);
        BEGIN
            PERFORM platform.tell_student(r.student_id, 'LEGACY_CREDIT_POSTED', NULL,
                jsonb_build_object('AMOUNT', 'NGN ' || to_char(r.confirmed_amount, 'FM999,999,999,990.00'), 'SESSION', r.session, 'REFERENCE', r.ref,
                                   'BALANCE', 'NGN ' || to_char(coalesce(v_balance, 0), 'FM999,999,999,990.00')),
                'legacy-credit:' || r.ref || ':posted');
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'legacy credit %: the student could not be told (%)', r.ref, SQLERRM;
        END;
    ELSE
        UPDATE finance.legacy_credit_request
           SET status = CASE v_action WHEN 'REJECT' THEN 'REJECTED' ELSE 'RETURNED_FOR_CORRECTION' END,
               decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_note)
         WHERE id = p_id RETURNING * INTO r;
        IF v_action = 'REJECT' THEN
            BEGIN
                PERFORM platform.tell_student(r.student_id, 'LEGACY_CREDIT_REJECTED', NULL,
                    jsonb_build_object('AMOUNT', 'NGN ' || to_char(r.confirmed_amount, 'FM999,999,999,990.00'), 'SESSION', r.session, 'REFERENCE', r.ref),
                    'legacy-credit:' || r.ref || ':rejected');
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'legacy credit %: the student could not be told (%)', r.ref, SQLERRM;
            END;
        END IF;
    END IF;
    -- the officer who initiated told of the decision
    BEGIN
        PERFORM platform.tell_person(r.initiated_by, 'LEGACY_CREDIT_DECIDED', NULL,
            jsonb_build_object('REF', r.ref, 'STUDENT', s.surname || ', ' || s.other_names, 'NUMBER', coalesce(s.matric_no, s.admission_no), 'SESSION', r.session,
                               'AMOUNT', 'NGN ' || to_char(r.confirmed_amount, 'FM999,999,999,990.00'),
                               'ACTION', CASE v_action WHEN 'APPROVE' THEN 'approved and credited to the wallet' WHEN 'REJECT' THEN 'rejected' ELSE 'returned for correction' END,
                               'NOTE', coalesce(nullif(btrim(coalesce(p_note, '')), ''), '—'), 'BURSAR', coalesce(helpdesk.person_name(who), 'the Bursar')),
            'legacy-credit:' || r.ref || ':decided:' || to_char(now(), 'YYYYMMDDHH24MISS'));
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'legacy credit %: the officer could not be told (%)', r.ref, SQLERRM;
    END;
    RETURN r;
END $function$;
COMMENT ON FUNCTION finance.legacy_credit_decide(uuid, text, text) IS 'V625: a Bursar officer other than the initiator approves (the overpayment locked and read afresh, one OVERPAID credit on the wallet, the overpayment decided WALLET, the student told the amount and the balance), rejects or returns a request for correction, with a note; the initiator is told. All or nothing: a refusal leaves no partial credit.';

-- ── what the desks read ──
CREATE OR REPLACE FUNCTION finance.legacy_credit_rows(p_status text, p_session text, p_q text, p_fac text, p_dept text, p_limit integer DEFAULT 500)
 RETURNS TABLE(id uuid, ref text, student_id uuid, student text, matric_no text, jamb_reg_no text, admission_no text, programme_code text, programme text, dept_code text, department text,
               faculty_code text, faculty text, session text, kind text, due numeric, paid numeric, legacy_amount numeric, confirmed_amount numeric, adjusted boolean, adjustment_reason text,
               reason text, evidence text, status text, initiated_by text, initiated_office text, initiated_at timestamptz, resubmitted_at timestamptz, resubmissions integer,
               decided_by text, decided_office text, decided_at timestamptz, decision_note text, withdrawn_by text, withdrawn_at timestamptz, withdraw_reason text,
               wallet_reference text, credited_at timestamptz, balance_after numeric)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT q.id, q.ref, q.student_id, s.surname || ', ' || s.other_names, s.matric_no, s.jamb_reg_no, s.admission_no, s.programme_code, p.name, p.dept_code, d.name, p.faculty_code, f.name,
           q.session, q.kind, q.due, q.paid, q.legacy_amount, q.confirmed_amount, q.adjusted, q.adjustment_reason, q.reason, q.evidence, q.status,
           helpdesk.person_name(q.initiated_by), q.initiated_office, q.initiated_at, q.resubmitted_at, q.resubmissions,
           helpdesk.person_name(q.decided_by), q.decided_office, q.decided_at, q.decision_note, helpdesk.person_name(q.withdrawn_by), q.withdrawn_at, q.withdraw_reason,
           e.reference, e.at,
           CASE WHEN e.id IS NULL THEN NULL ELSE (SELECT coalesce(sum(CASE WHEN w.kind IN ('CREDIT', 'TOPUP') THEN w.amount ELSE -w.amount END), 0)
                                                      FROM finance.wallet_entry w WHERE w.student_id = q.student_id AND (w.at, w.id) <= (e.at, e.id)) END
      FROM finance.legacy_credit_request q
      JOIN people.student s ON s.id = q.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN finance.wallet_entry e ON e.id = q.wallet_entry_id
     WHERE (p_status IS NULL OR q.status = p_status)
       AND (p_session IS NULL OR q.session = p_session)
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept)
       AND (p_q IS NULL OR s.matric_no ILIKE '%' || p_q || '%' OR s.jamb_reg_no ILIKE '%' || p_q || '%' OR s.admission_no ILIKE '%' || p_q || '%'
            OR (s.surname || ' ' || s.other_names) ILIKE '%' || p_q || '%' OR q.ref ILIKE '%' || p_q || '%')
     ORDER BY CASE q.status WHEN 'PENDING_BURSAR_APPROVAL' THEN 0 WHEN 'RETURNED_FOR_CORRECTION' THEN 1 WHEN 'CREDITED' THEN 2 ELSE 3 END, q.initiated_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 500), 5000))
$function$;

CREATE OR REPLACE FUNCTION finance.legacy_credit_of(p_student uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'ref', q.ref, 'session', q.session, 'kind', q.kind, 'due', q.due, 'paid', q.paid, 'legacyAmount', q.legacy_amount, 'confirmedAmount', q.confirmed_amount,
               'adjusted', q.adjusted, 'status', q.status, 'initiatedAt', q.initiated_at, 'initiatedBy', helpdesk.person_name(q.initiated_by),
               'decidedAt', q.decided_at, 'decidedBy', helpdesk.person_name(q.decided_by), 'walletReference', e.reference, 'creditedAt', e.at) ORDER BY q.initiated_at DESC), '[]'::jsonb)
      FROM finance.legacy_credit_request q LEFT JOIN finance.wallet_entry e ON e.id = q.wallet_entry_id
     WHERE q.student_id = p_student
$function$;
COMMENT ON FUNCTION finance.legacy_credit_of(uuid) IS 'V625: a student''s legacy credit requests for the full record — the reference, the session, the amounts, the status, who initiated and decided, the wallet credit; never the desk''s notes.';

-- the old portal's outstanding fees of a session, student by student, as the reconciliation classifies them
CREATE OR REPLACE FUNCTION finance.legacy_outstanding_rows(p_session text, p_state text, p_q text, p_fac text, p_dept text, p_limit integer DEFAULT 500, p_legacy_only boolean DEFAULT true)
 RETURNS TABLE(student_id uuid, number text, name text, matric_no text, jamb_reg_no text, admission_no text, programme_code text, programme text, dept_code text, department text,
               faculty_code text, faculty text, level integer, session text, due numeric, paid numeric, paid_old_s1 numeric, paid_old_s2 numeric, paid_old_session numeric,
               paid_payment_history numeric, paid_portal numeric, old_payments integer, owed numeric, excess numeric, state text, decision text, carried_in numeric, settled numeric,
               doubles integer, request_ref text, request_status text, request_amount numeric, last_reference text, last_paid_at timestamptz)
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS MATERIALIZED (SELECT * FROM finance.old_fees_reconciliation(p_session)),
    dbl AS MATERIALIZED (SELECT d.student_id, count(*)::int AS n FROM finance.old_payment_doubles() d WHERE d.session = p_session GROUP BY d.student_id),
    lastp AS MATERIALIZED (SELECT sp.student_id, sp.last_reference, sp.last_paid_at FROM finance.session_payments(p_session) sp)
    SELECT r.student_id, r.number, r.name, s.matric_no, s.jamb_reg_no, s.admission_no, r.programme_code, p.name, p.dept_code, d.name, r.faculty_code, f.name, r.level, p_session,
           r.due, r.paid, r.paid_old_s1, r.paid_old_s2, r.paid_old_session, r.paid_payment_history, r.paid_portal, r.old_payments,
           greatest(r.due - r.paid, 0), greatest(r.paid - r.due, 0),
           CASE r.state WHEN 'UNDER' THEN 'OWES' WHEN 'OVER' THEN 'CREDIT' WHEN 'OVER_SETTLED' THEN 'CREDIT_DECIDED' WHEN 'NO_FEE_STATED' THEN 'NO_FEE_STATED' ELSE 'SETTLED' END,
           r.decision, r.carried_in, r.settled, coalesce(dbl.n, 0), q.ref, q.status, q.confirmed_amount, lastp.last_reference, lastp.last_paid_at
      FROM r
      JOIN people.student s ON s.id = r.student_id
      LEFT JOIN ref.programme p ON p.code = r.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN dbl ON dbl.student_id = r.student_id
      LEFT JOIN lastp ON lastp.student_id = r.student_id
      LEFT JOIN LATERAL (SELECT x.ref, x.status, x.confirmed_amount FROM finance.legacy_credit_request x
                          WHERE x.student_id = r.student_id AND x.session = p_session
                          ORDER BY (x.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')) DESC, (x.status = 'CREDITED') DESC, x.initiated_at DESC LIMIT 1) q ON true
     WHERE (NOT p_legacy_only OR r.old_payments > 0)
       AND (p_state IS NULL OR p_state = CASE r.state WHEN 'UNDER' THEN 'OWES' WHEN 'OVER' THEN 'CREDIT' WHEN 'OVER_SETTLED' THEN 'CREDIT_DECIDED' WHEN 'NO_FEE_STATED' THEN 'NO_FEE_STATED' ELSE 'SETTLED' END)
       AND (p_fac IS NULL OR r.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept)
       AND (p_q IS NULL OR s.matric_no ILIKE '%' || p_q || '%' OR s.jamb_reg_no ILIKE '%' || p_q || '%' OR s.admission_no ILIKE '%' || p_q || '%'
            OR r.name ILIKE '%' || p_q || '%' OR q.ref ILIKE '%' || p_q || '%' OR lastp.last_reference ILIKE '%' || p_q || '%')
     ORDER BY CASE r.state WHEN 'OVER' THEN 0 WHEN 'UNDER' THEN 1 WHEN 'OVER_SETTLED' THEN 2 WHEN 'NO_FEE_STATED' THEN 3 ELSE 4 END, greatest(r.paid - r.due, r.due - r.paid) DESC, r.name
     LIMIT greatest(1, least(coalesce(p_limit, 500), 5000))
$function$;
COMMENT ON FUNCTION finance.legacy_outstanding_rows(text, text, text, text, text, integer, boolean) IS 'V625: the old portal''s outstanding fees of a session as the reconciliation (V498, V506) classifies each student — OWES (a liability of the student, never wallet money), CREDIT (paid above the fees stated: eligible for a legacy credit request), CREDIT_DECIDED (carried, refunded or credited), SETTLED, NO_FEE_STATED — with the doubles found, the request standing and the last payment.';

CREATE OR REPLACE FUNCTION finance.legacy_reconciliation_figures(p_session text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS MATERIALIZED (SELECT * FROM finance.old_fees_reconciliation(p_session) x WHERE x.old_payments > 0),
    q AS (SELECT * FROM finance.legacy_credit_request),
    w AS (SELECT * FROM finance.legacy_wallet)
    SELECT jsonb_build_object(
        'session', p_session,
        'outstanding', jsonb_build_object(
            'students', (SELECT count(*) FROM r),
            'owes', (SELECT count(*) FROM r WHERE r.state = 'UNDER'), 'owesAmount', (SELECT coalesce(sum(r.due - r.paid), 0) FROM r WHERE r.state = 'UNDER'),
            'credit', (SELECT count(*) FROM r WHERE r.state = 'OVER'), 'creditAmount', (SELECT coalesce(sum(r.paid - r.due), 0) FROM r WHERE r.state = 'OVER'),
            'decided', (SELECT count(*) FROM r WHERE r.state = 'OVER_SETTLED'), 'decidedAmount', (SELECT coalesce(sum(r.settled), 0) FROM r WHERE r.state = 'OVER_SETTLED'),
            'carried', (SELECT count(*) FROM r WHERE r.decision = 'CARRY'), 'refunded', (SELECT count(*) FROM r WHERE r.decision = 'REFUND'), 'toWallet', (SELECT count(*) FROM r WHERE r.decision = 'WALLET'),
            'settled', (SELECT count(*) FROM r WHERE r.state NOT IN ('UNDER', 'OVER', 'OVER_SETTLED', 'NO_FEE_STATED')),
            'noFee', (SELECT count(*) FROM r WHERE r.state = 'NO_FEE_STATED')),
        'requests', jsonb_build_object(
            'pending', (SELECT count(*) FROM q WHERE q.status = 'PENDING_BURSAR_APPROVAL'), 'pendingAmount', (SELECT coalesce(sum(q.confirmed_amount), 0) FROM q WHERE q.status = 'PENDING_BURSAR_APPROVAL'),
            'returned', (SELECT count(*) FROM q WHERE q.status = 'RETURNED_FOR_CORRECTION'), 'returnedAmount', (SELECT coalesce(sum(q.confirmed_amount), 0) FROM q WHERE q.status = 'RETURNED_FOR_CORRECTION'),
            'credited', (SELECT count(*) FROM q WHERE q.status = 'CREDITED'), 'creditedAmount', (SELECT coalesce(sum(q.confirmed_amount), 0) FROM q WHERE q.status = 'CREDITED'),
            'rejected', (SELECT count(*) FROM q WHERE q.status = 'REJECTED'), 'rejectedAmount', (SELECT coalesce(sum(q.confirmed_amount), 0) FROM q WHERE q.status = 'REJECTED'),
            'withdrawn', (SELECT count(*) FROM q WHERE q.status = 'WITHDRAWN'),
            'adjusted', (SELECT count(*) FROM q WHERE q.adjusted AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')),
            'pendingSession', (SELECT count(*) FROM q WHERE q.status = 'PENDING_BURSAR_APPROVAL' AND q.session = p_session)),
        'wallet', jsonb_build_object(
            'students', (SELECT count(*) FROM w),
            'computed', (SELECT count(*) FROM w WHERE w.status = 'COMPUTED'), 'computedAmount', (SELECT coalesce(sum(w.available), 0) FROM w WHERE w.status = 'COMPUTED'),
            'verified', (SELECT count(*) FROM w WHERE w.status = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(w.available), 0) FROM w WHERE w.status = 'VERIFIED'),
            'returned', (SELECT count(*) FROM w WHERE w.status = 'RETURNED'), 'returnedAmount', (SELECT coalesce(sum(w.available), 0) FROM w WHERE w.status = 'RETURNED'),
            'posted', (SELECT count(*) FROM w WHERE w.status = 'POSTED'),
            'postedAmount', (SELECT coalesce(sum(e.amount), 0) FROM finance.wallet_entry e WHERE e.kind = 'CREDIT' AND e.source_code = 'LEGACY_WALLET'),
            'review', (SELECT count(*) FROM w WHERE w.status = 'REQUIRES_REVIEW'), 'rejected', (SELECT count(*) FROM w WHERE w.status = 'REJECTED'),
            'frozen', (SELECT count(*) FROM w WHERE w.status = 'FROZEN'), 'noBalance', (SELECT count(*) FROM w WHERE w.status = 'NO_BALANCE'),
            'applied', (SELECT coalesce(sum(e.amount), 0) FROM finance.wallet_entry e WHERE e.kind = 'APPLIED' AND e.source_code = 'LEGACY_WALLET')),
        'overpaidCredited', jsonb_build_object(
            'amount', (SELECT coalesce(sum(e.amount), 0) FROM finance.wallet_entry e WHERE e.kind = 'CREDIT' AND e.source_code = 'OVERPAID'),
            'applied', (SELECT coalesce(sum(e.amount), 0) FROM finance.wallet_entry e WHERE e.kind = 'APPLIED' AND e.source_code = 'OVERPAID')))
$function$;
COMMENT ON FUNCTION finance.legacy_reconciliation_figures(text) IS 'V625: the desk''s figures — the session''s old-portal outstanding fees (what students owe and what the University holds, kept apart), the legacy credit requests by state, the old e-wallet balances by state, and what the wallet was credited and has applied.';

-- the e-wallet desk's figures say how many balances are returned for correction
CREATE OR REPLACE FUNCTION finance.legacy_wallet_figures()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (SELECT * FROM finance.legacy_wallet),
    applied AS (SELECT coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refunded,
                       coalesce(sum(e.amount) FILTER (WHERE e.kind = 'CREDIT'), 0) AS credited
                  FROM finance.wallet_entry e WHERE e.source_code = 'LEGACY_WALLET'),
    orphan AS (   -- paid from the old wallet with no top-up on file
        SELECT count(DISTINCT pr.student_id) AS students, coalesce(sum(pr.amount), 0) AS amount
          FROM finance.payment_reference pr
         WHERE pr.channel = 'Legacy' AND pr.confirmed_at IS NOT NULL AND finance.legacy_wallet_method(pr.note) = 'E-Wallet' AND NOT finance.legacy_wallet_is_topup(pr.purpose)
           AND NOT EXISTS (SELECT 1 FROM finance.legacy_wallet lw WHERE lw.student_id = pr.student_id AND lw.topup_count > 0))
    SELECT jsonb_build_object(
        'students', (SELECT count(*) FROM w),
        'topups', (SELECT coalesce(sum(topups), 0) FROM w), 'topupCount', (SELECT coalesce(sum(topup_count), 0) FROM w),
        'used', (SELECT coalesce(sum(used), 0) FROM w),
        'computed', (SELECT count(*) FROM w WHERE status = 'COMPUTED'), 'computedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'COMPUTED'),
        'verified', (SELECT count(*) FROM w WHERE status = 'VERIFIED'), 'verifiedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'VERIFIED'),
        'returned', (SELECT count(*) FROM w WHERE status = 'RETURNED'), 'returnedAmount', (SELECT coalesce(sum(available), 0) FROM w WHERE status = 'RETURNED'),
        'posted', (SELECT count(*) FROM w WHERE status = 'POSTED'), 'postedAmount', (SELECT credited FROM applied),
        'applied', (SELECT applied FROM applied), 'refunded', (SELECT refunded FROM applied),
        'remaining', (SELECT credited - applied - refunded FROM applied),
        'review', (SELECT count(*) FROM w WHERE status = 'REQUIRES_REVIEW'), 'reviewUsed', (SELECT coalesce(sum(used - topups), 0) FROM w WHERE status = 'REQUIRES_REVIEW'),
        'noBalance', (SELECT count(*) FROM w WHERE status = 'NO_BALANCE'),
        'rejected', (SELECT count(*) FROM w WHERE status = 'REJECTED'), 'frozen', (SELECT count(*) FROM w WHERE status = 'FROZEN'),
        'stated', (SELECT count(*) FROM w WHERE stated_balance IS NOT NULL), 'differs', (SELECT count(*) FROM w WHERE reason_code = 'STATEMENT_DIFFERS'),
        'changed', (SELECT count(*) FROM w WHERE reason_code IN ('CHANGED_AFTER_POSTING', 'CHANGED_AFTER_VERIFICATION')),
        'orphanStudents', (SELECT students FROM orphan), 'orphanAmount', (SELECT amount FROM orphan),
        'lastComputed', (SELECT max(computed_at) FROM w),
        'batches', (SELECT coalesce(json_agg(b ORDER BY b.posted_at DESC), '[]'::json)::jsonb FROM (
                        SELECT b.ref, b.posted_at, b.students, b.amount, b.skipped, helpdesk.person_name(b.posted_by) AS posted_by, b.office FROM finance.legacy_wallet_batch b ORDER BY b.posted_at DESC LIMIT 50) b))
$function$;

-- ── the notices between the desks and to the student ──
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('LEGACY_WALLET_WAITING', 'Old e-wallet balances verified and waiting',
 'To the Bursar''s office holders when the Students Account Officer has verified old-portal e-wallet balances that wait for a posting',
 '[STUDENTS] old e-wallet balance(s) verified, waiting for your posting',
 E'[OFFICER] has verified [STUDENTS] old-portal e-wallet balance(s) of [AMOUNT] in all. They wait for a Bursar officer other than the verifier to post them to the students'' wallets, or to return them for correction, on Old E-Wallet Balances.',
 '[UNIVERSITY_SHORT]: [STUDENTS] old e-wallet balance(s) ([AMOUNT]) verified by [OFFICER] wait for your posting.',
 'Old e-wallet balances wait for your posting',
 '[OFFICER] verified [STUDENTS] balance(s) of [AMOUNT]. Post them to the wallets, or return them for correction, on Old E-Wallet Balances.',
 ARRAY['STUDENTS','AMOUNT','OFFICER','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_WALLET_DECIDED', 'Old e-wallet balance decided by the Bursar',
 'To the officer who verified an old-portal e-wallet balance when the Bursar rejects, freezes or returns it for correction',
 'Old e-wallet balance of [STUDENT] [ACTION]',
 E'The old-portal e-wallet balance of [AMOUNT] you verified for [STUDENT] was [ACTION] by [BURSAR].\n\nReason: [REASON]\n\nA balance returned for correction is corrected on Old E-Wallet Balances (the old portal''s statement entered, or the figures read again) and verified afresh.',
 '[UNIVERSITY_SHORT]: the old e-wallet balance of [STUDENT] ([AMOUNT]) was [ACTION] by the Bursar: [REASON]',
 'Old e-wallet balance [ACTION]',
 'The balance of [AMOUNT] you verified for [STUDENT] was [ACTION] by [BURSAR]: [REASON]',
 ARRAY['STUDENT','AMOUNT','ACTION','REASON','BURSAR','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_WALLET_REJECTED', 'Old e-wallet balance not credited',
 'To a student whose old-portal e-wallet balance the Bursar has rejected after review',
 'Your old e-wallet balance was not credited',
 E'Dear [FIRST_NAME],\n\nAfter review, the Bursary could not credit the [AMOUNT] the old portal''s records suggested for your e-wallet. If you hold the old portal''s statement or a receipt that shows the balance, bring it to the Bursary (Students Account) so the record can be reviewed again.',
 '[UNIVERSITY_SHORT]: your old e-wallet balance of [AMOUNT] was not credited after review. Bring the old portal''s statement to the Bursary to have it reviewed again.',
 'Your old e-wallet balance was not credited',
 'After review the Bursary could not credit the [AMOUNT] the old portal''s records suggested. Bring the old portal''s statement or a receipt to the Bursary to have it reviewed again.',
 ARRAY['FIRST_NAME','AMOUNT','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_CREDIT_WAITING', 'Legacy credit request waiting for the Bursar',
 'To the Bursar''s office holders when the Students Account Officer initiates or resubmits a legacy credit request (overpaid school fees to the wallet)',
 'Legacy credit request [REF] waits for your approval',
 E'[OFFICER] has confirmed that [STUDENT] ([NUMBER]) paid [AMOUNT] above the school fees stated for [SESSION] and requests that it be credited to the student''s wallet (request [REF]).\n\nReview it on Legacy Financial Reconciliation: approve and credit the wallet, reject, or return it for correction. Nothing is credited until you approve.',
 '[UNIVERSITY_SHORT]: legacy credit request [REF] ([STUDENT], [AMOUNT], [SESSION]) by [OFFICER] waits for your approval.',
 'Legacy credit request [REF] waits for your approval',
 '[OFFICER] confirmed [AMOUNT] overpaid by [STUDENT] ([NUMBER]) on [SESSION]. Approve and credit the wallet, reject, or return it for correction.',
 ARRAY['REF','STUDENT','NUMBER','SESSION','AMOUNT','OFFICER','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_CREDIT_DECIDED', 'Legacy credit request decided',
 'To the officer who initiated a legacy credit request when the Bursar approves, rejects or returns it',
 'Legacy credit request [REF] [ACTION]',
 E'Your legacy credit request [REF] — [AMOUNT] for [STUDENT] ([NUMBER]), [SESSION] — was [ACTION] by [BURSAR].\n\nNote: [NOTE]\n\nA request returned for correction is corrected and resubmitted on Legacy Financial Reconciliation.',
 '[UNIVERSITY_SHORT]: legacy credit request [REF] ([STUDENT], [AMOUNT]) was [ACTION] by the Bursar. [NOTE]',
 'Legacy credit request [REF] [ACTION]',
 'Request [REF] ([AMOUNT] for [STUDENT], [SESSION]) was [ACTION] by [BURSAR]. Note: [NOTE]',
 ARRAY['REF','STUDENT','NUMBER','SESSION','AMOUNT','ACTION','NOTE','BURSAR','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_CREDIT_POSTED', 'Overpaid school fees credited to the wallet',
 'To a student whose overpaid school fees on an earlier session the Bursar has approved and credited to their wallet',
 'Your overpaid school fees of [AMOUNT] are on your wallet',
 E'Dear [FIRST_NAME],\n\nThe [AMOUNT] you paid above the school fees stated for [SESSION] has been approved by the Bursar and credited to your wallet (reference [REFERENCE]). Your wallet balance is now [BALANCE].\n\nYou can apply it to your school fees from the wallet page on the portal, and pay any shortfall through the gateway as usual.',
 '[UNIVERSITY_SHORT]: your overpaid school fees of [AMOUNT] ([SESSION]) are on your wallet, ref [REFERENCE]. Balance [BALANCE]. Apply it to your fees on the portal.',
 'Your overpaid school fees are on your wallet',
 'The [AMOUNT] you paid above the fees stated for [SESSION] is on your wallet (ref [REFERENCE]); your balance is [BALANCE]. Apply it to your school fees from the wallet page.',
 ARRAY['FIRST_NAME','AMOUNT','SESSION','REFERENCE','BALANCE','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('LEGACY_CREDIT_REJECTED', 'Legacy credit not approved',
 'To a student whose legacy credit request (overpaid school fees to the wallet) the Bursar has rejected',
 'Your legacy credit request was not approved',
 E'Dear [FIRST_NAME],\n\nAfter review, the Bursar did not approve the credit of [AMOUNT] from your school fees paid on [SESSION] (request [REFERENCE]). Your fee position for that session stands as the portal shows it. If you hold a receipt or the old portal''s statement that shows the overpayment, bring it to the Bursary (Students Account) so the record can be reviewed again.',
 '[UNIVERSITY_SHORT]: your legacy credit request [REFERENCE] ([AMOUNT], [SESSION]) was not approved. Bring your receipts to the Bursary to have it reviewed again.',
 'Your legacy credit request was not approved',
 'The Bursar did not approve the credit of [AMOUNT] from your school fees paid on [SESSION] (request [REFERENCE]). Bring your receipts to the Bursary to have it reviewed again.',
 ARRAY['FIRST_NAME','AMOUNT','SESSION','REFERENCE','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

GRANT SELECT ON finance.legacy_credit_request TO app_auditor, app_reporting;

COMMIT;
