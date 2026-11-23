-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V781 · Overpaid school fees reconciled from the Bursar's dashboard (stage 1: the list by cause with its holds, the kept list, the
--         desk, the wallet credit in bulk by two officers, the refund route, the further decision, the guards)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's brief of 15 and 16 November 2026: most students paid school fees twice, so what was paid is over what was charged.
--  The Bursar sees every such student of a session on one list, sorted by cause, and either credits the money to the student's wallet
--  (a Bursary officer requests, another approves, many at once) or refunds it. Nothing is paid back by this migration and nothing
--  is applied to a student's fees by it: the credit stays on the wallet until the student applies it (finance.apply_wallet, the
--  Wallet page) or asks for it as a refund.
--
--    · The list. finance.overpaid_read works the session out in one read (of the students asked for only, when some are named: a student
--      costs one student, not the session): the five causes (PORTAL_TWICE, OLD_AND_PORTAL, OLD_TWICE,
--      PART_PAYMENTS, ABOVE_FEE_LINE), whether the row is "bulk" (a repeated payment that makes up the excess exactly, on records the bank
--      reported, at the level by entry year: the only rows decided many at a time), and the fourteen holds that stop every decision
--      (a past session, a record closed for fees, a bank check, one payment recorded twice, a reversal, a payment archived, a correction
--      open, a semester not charged or not stated, a spillover semester to register, a late fee that may still fall or lapsed, an excess
--      the student's own fee account reads differently, a merged record). finance.overpaid_refresh keeps it in finance.overpaid_snapshot
--      (a cache; the API's job refreshes it); the state of each row — decided, requested, refunded — is read live at every read
--      (finance.overpaid_desk, finance.overpaid_figures) and money never reads the kept list.
--    · The further decision. One live decision a student and session no longer stands: remaining = paid - due - decided, where decided
--      is the standing decisions plus the refunds raised by hand against the session's payments (finance.overpayment_decided). A
--      trigger refuses a decision that would pass the excess its own row records, a decision's reference is unique among live rows, and
--      the archive, the swap, the reallocation and the "never received" withdrawal refuse a payment only when taking it away would
--      leave less paid above the charge than is decided (finance.overpayment_decisions_covered).
--    · Two witnesses for every amount: the list finds the student, the student's own finance.position (read under the student's lock)
--      gives the amount; a difference of NGN 1 or more skips the student (EXCESS_UNCERTAIN). Every row that is not "bulk" is decided
--      one student a call, with the officer's confirmation that the fee setup and the payments were checked (kept on the request and on
--      the decision, fee_setup_checked). The same rules bind finance.decide_overpayments, legacy_credit_initiate and _resubmit.
--    · The wallet route. finance.overpaid_credits_request (one Bursary officer or the Students Account Officer), _decide (another
--      Bursar officer: APPROVE, REJECT, RETURN; a pass ends: a request it cannot credit is marked and not tried again in the pass) and
--      _withdraw; finance.overpaid_credit_post is the one place a credit is posted (the single approval on Legacy Financial
--      Reconciliation uses it too). An OVERPAID credit exists only with its approved request: a hand credit of that source and a wallet
--      reset over such a credit are refused, and a deferred trigger refuses an OVERPAID credit with no request behind it at commit.
--    · The wallet refund by source. A wallet refund draws on the source that holds the money (finance.withdrawal_sources), and overpaid
--      money is refundable from whichever session's page the student is on. What a decision above the excess owes back to the session's
--      fees is not refunded from the wallet (finance.overpaid_refundable, finance.overpaid_kept_back).
--    · A refund raised against a school-fees payment never gives back money an overpayment decision already gave, nor crosses an open
--      credit request (finance.propose_refund). Old-fees maintenance (the reset, an upload that takes a record over or relabels one, the
--      put-right) leaves a school-fees record a decision or an open request rests on.
--
--  The migration works nothing out (the kept list is empty until the API's job, or the desk's Refresh, runs finance.overpaid_refresh),
--  holds no table lock for long (lock_timeout 5 s; the two triggers on finance.overpayment_decision and finance.wallet_entry are its last
--  statements), and writes no student's name, number or reference. Every function restated here is restated from its latest text on a
--  database at V780 (V777's text for the four payment functions both restate, which is why this file follows V777), each anchor of one
--  patched by anchor asserted to occur exactly once.
--
--  The wallet's own use of that money without being asked, and the stopping of a second payment of school fees already paid, are
--  separate pieces of the same work and are not in this migration.
--  Every catching block of this file re-raises a deadlock, a serialization failure and a lock not had in time (V762's rule), so the
--  API runs the door again.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SET LOCAL lock_timeout = '5s';
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V781: overpaid school fees reconciled from the Bursar''s dashboard (the University, 15 November 2026)', true);

-- an anchor must be there exactly once before it is replaced (copied from V762's v762_once)
CREATE FUNCTION pg_temp.v781_once(p_def text, p_anchor text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_anchor IS NULL OR length(p_anchor) = 0 OR (length(p_def) - length(replace(p_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
        RAISE EXCEPTION 'V781: % is not as it was left (an anchor is not there exactly once)', p_what;
    END IF;
END $$;

-- ── 0 · what the unique index on a decision's reference needs ──
DO $v781$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM (SELECT d.reference FROM finance.overpayment_decision d WHERE d.superseded_at IS NULL GROUP BY d.reference HAVING count(*) > 1) x;
    IF n > 0 THEN
        RAISE EXCEPTION 'V781: % overpayment decision reference(s) are shared by two decisions that stand; they are looked at before one decision an instrument is made a rule', n;
    END IF;
END $v781$;

-- ── 1 · the kept list, and the sequences of the requests' batches ──
CREATE TABLE finance.overpaid_snapshot (
    session text NOT NULL, student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    number text, name text, programme_code text, dept_code text, faculty_code text, level int, cohort_level int, status text,
    due numeric(14,2) NOT NULL, paid numeric(14,2) NOT NULL, excess numeric(14,2) NOT NULL,
    cause text NULL, bulk boolean NOT NULL, repeat_amount numeric(14,2) NULL, n_payments int NOT NULL,
    payments jsonb NOT NULL DEFAULT '[]', holds text[] NOT NULL DEFAULT '{}', refund_only text NULL, suggested text NOT NULL,
    PRIMARY KEY (session, student_id));
CREATE INDEX ix_overpaid_snapshot_cause ON finance.overpaid_snapshot (session, cause);
CREATE TABLE finance.overpaid_snapshot_run (
    session text PRIMARY KEY, refreshed_at timestamptz NOT NULL, took_ms int NOT NULL, students int NOT NULL, excess numeric(16,2) NOT NULL);
COMMENT ON TABLE finance.overpaid_snapshot IS 'V781: the Overpaid school fees list of a session, worked out by finance.overpaid_read and kept (a cache refreshed by finance.overpaid_refresh): the student, what was charged and paid, the cause, whether the row is decided in bulk, the payments behind it (amount, channel, day and kind only), the holds and what the Bursary is advised. The state of a row — decided, requested, refunded — is never kept: finance.overpaid_desk reads it live. Money never reads this table.';
COMMENT ON COLUMN finance.overpaid_snapshot.level IS 'V781: the level the charge is read at (people.student.current_level).';
COMMENT ON COLUMN finance.overpaid_snapshot.cohort_level IS 'V781: the level by entry year (finance.overpaid''s own column); a row where the two differ is never decided in bulk.';
COMMENT ON TABLE finance.overpaid_snapshot_run IS 'V781: when the kept list of a session was last worked out, how long it took and what it held.';
SELECT audit.exempt('finance.overpaid_snapshot', 'V781: a list worked out from the fee lines and the confirmed payments; nothing in it is decided by a person');
SELECT audit.exempt('finance.overpaid_snapshot_run', 'V781: when that list was last worked out');
GRANT SELECT ON finance.overpaid_snapshot, finance.overpaid_snapshot_run TO app_auditor, app_reporting;
CREATE SEQUENCE finance.overpaid_request_batch_seq;
CREATE SEQUENCE finance.overpaid_credit_batch_seq;

-- ── 2 · a further decision allowed; the confirmation that the fee setup was checked ──
ALTER TABLE finance.overpayment_decision ADD COLUMN fee_setup_checked boolean NOT NULL DEFAULT false;
DROP INDEX finance.uq_overpayment_decision_live;
CREATE INDEX ix_overpayment_decision_live ON finance.overpayment_decision (student_id, session) WHERE superseded_at IS NULL;
CREATE INDEX ix_overpayment_decision_session ON finance.overpayment_decision (session) WHERE superseded_at IS NULL;
CREATE UNIQUE INDEX uq_overpayment_decision_reference ON finance.overpayment_decision (reference) WHERE superseded_at IS NULL;
COMMENT ON TABLE finance.overpayment_decision IS 'V506, V781: what the Bursary decided about money a student paid above the school fees of a session — carried into the next session, refunded, or credited to the wallet. Several decisions may stand for a student and session (a further decision for the amount above what is already decided, when the student paid again): the invariant is that the decided money never passes the excess the row records (trigger trg_overpayment_decision_within_excess), counted with the refunds raised by hand against the session''s payments (finance.overpayment_decided). A decision''s reference is unique among those that stand.';
COMMENT ON COLUMN finance.overpayment_decision.decision IS 'CARRY into the next session or REFUND (V506); WALLET — credited to the student''s wallet on a credit request a second Bursary officer approved (V625). Several may stand for a student and session, together never above the excess (V781).';
COMMENT ON COLUMN finance.overpayment_decision.fee_setup_checked IS 'V781: the officer confirmed that the fee setup and the payments were checked — required for a row that is not a repeated payment making up the excess exactly (the two fee-line causes and a repeat that falls short of the excess).';

-- ── 3 · the credit request in bulk ──
ALTER TABLE finance.legacy_credit_request
    ADD COLUMN cause text NULL CHECK (cause IN ('PORTAL_TWICE', 'OLD_AND_PORTAL', 'OLD_TWICE', 'PART_PAYMENTS', 'ABOVE_FEE_LINE')),
    ADD COLUMN bulk boolean NOT NULL DEFAULT false,
    ADD COLUMN request_batch text NULL CHECK (request_batch ~ '^OCR/[0-9]{4}/[0-9]{6}$'),
    ADD COLUMN credit_batch  text NULL CHECK (credit_batch  ~ '^OCA/[0-9]{4}/[0-9]{6}$'),
    ADD COLUMN fee_setup_checked boolean NOT NULL DEFAULT false,
    ADD COLUMN last_skip_at timestamptz NULL, ADD COLUMN last_skip_code text NULL, ADD COLUMN last_skip_why text NULL,
    ADD CONSTRAINT ck_lcr_bulk_batch CHECK (bulk = (request_batch IS NOT NULL));
CREATE INDEX ix_lcr_request_batch ON finance.legacy_credit_request (request_batch) WHERE request_batch IS NOT NULL;
CREATE INDEX ix_lcr_session_status ON finance.legacy_credit_request (session, status);
COMMENT ON COLUMN finance.legacy_credit_request.cause IS 'V781: the cause the student''s excess was listed under when the request was made.';
COMMENT ON COLUMN finance.legacy_credit_request.bulk IS 'V781: requested on the Overpaid school fees desk (one student or many, always with a request batch); a request made on Legacy Financial Reconciliation is false and has no batch. The desk of each decides its own.';
COMMENT ON COLUMN finance.legacy_credit_request.request_batch IS 'V781: OCR/<year>/<number>: the act of requesting many together (one number for the calls of one act).';
COMMENT ON COLUMN finance.legacy_credit_request.credit_batch IS 'V781: OCA/<year>/<number>: the approval pass that credited the request.';
COMMENT ON COLUMN finance.legacy_credit_request.fee_setup_checked IS 'V781: the officer confirmed that the fee setup and the payments were checked (a row that is not a repeated payment making up the excess exactly).';
COMMENT ON COLUMN finance.legacy_credit_request.last_skip_at IS 'V781: the last time an approval pass tried the request and left it, with its code and words: a request left is not tried again in that pass; cleared when the request is credited, returned, rejected, withdrawn or resubmitted.';

-- ── 4 · what the new reads and the job's candidates are served by ──
CREATE INDEX ix_we_overpaid ON finance.wallet_entry (student_id) INCLUDE (kind, amount) WHERE source_code = 'OVERPAID';
-- the PayDirect collections report names the reference it matched: the list's evidence that the bank reported a payment
CREATE INDEX IF NOT EXISTS ix_pdc_reference ON finance.paydirect_collection (reference);

-- ── 5 · words, and the small readers the rest stand on ──
CREATE FUNCTION finance.overpaid_hold_word(p_code text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_code
        WHEN 'PAST_SESSION' THEN 'Not this student''s current session — its charge is read as the student stands today'
        WHEN 'CLOSED_FOR_FEES' THEN 'Graduated: nothing is charged for this session — refund the payment on Refunds & Credits'
        WHEN 'BANK_CHECK' THEN 'Waiting for the bank check'
        WHEN 'SAME_PAYMENT' THEN 'One payment recorded twice — archive the duplicate'
        WHEN 'REVERSAL' THEN 'A PayDirect reversal is on record'
        WHEN 'UNDER_REVIEW' THEN 'A payment is archived for review'
        WHEN 'OPEN_CORRECTION' THEN 'A payment correction is open'
        WHEN 'SEMESTER_NOT_CHARGED' THEN 'A semester of this session is not yet charged'
        WHEN 'SEMESTER_NOT_STATED' THEN 'A semester''s fees are not yet stated'
        WHEN 'SPILLOVER_SEMESTER' THEN 'Spillover: a semester still to be registered'
        WHEN 'LATE_FEE_POSSIBLE' THEN 'A late registration fee may still fall'
        WHEN 'LATE_FEE_LAPSED' THEN 'A late payment fee was due — it is not an overpayment'
        WHEN 'EXCESS_UNCERTAIN' THEN 'The student''s own fee account reads a different excess'
        WHEN 'MERGED_RECORD' THEN 'A duplicate record — decide on the record kept'
        ELSE p_code END
$fn$;
COMMENT ON FUNCTION finance.overpaid_hold_word(text) IS 'V781: the words of one hold on an overpaid row (the desk, the refusals and lib/overpaid.ts carry the same sentences).';
CREATE FUNCTION finance.overpaid_hold_words(p_holds text[]) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT coalesce(string_agg(finance.overpaid_hold_word(h.code), '; ' ORDER BY h.ord), '') FROM unnest(coalesce(p_holds, '{}'::text[])) WITH ORDINALITY h(code, ord)
$fn$;
COMMENT ON FUNCTION finance.overpaid_hold_words(text[]) IS 'V781: the words of each hold, joined by "; ".';
CREATE FUNCTION finance.overpaid_cause_word(p_cause text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_cause
        WHEN 'PORTAL_TWICE' THEN 'Paid twice on the portal'
        WHEN 'OLD_AND_PORTAL' THEN 'Paid on the old portal and the new'
        WHEN 'OLD_TWICE' THEN 'Paid twice on the old portal'
        WHEN 'PART_PAYMENTS' THEN 'Several payments above the charge'
        WHEN 'ABOVE_FEE_LINE' THEN 'Paid above the fee line'
        ELSE p_cause END
$fn$;
COMMENT ON FUNCTION finance.overpaid_cause_word(text) IS 'V781: the words of a cause of an overpayment.';
CREATE FUNCTION finance.overpaid_refund_only_word(p_code text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_code
        WHEN 'DECEASED' THEN 'deceased (the estate is refunded)'
        WHEN 'GRADUATED' THEN 'graduated'
        WHEN 'WITHDRAWN' THEN 'withdrawn'
        WHEN 'LEFT' THEN 'no longer a student of the University'
        WHEN 'AWARD_APPROVED' THEN 'cleared for an award'
        ELSE p_code END
$fn$;
COMMENT ON FUNCTION finance.overpaid_refund_only_word(text) IS 'V781: why a student''s excess is refunded and never credited to a wallet or carried.';

-- a graduated, withdrawn, expelled, transferred or deceased student, or one whose award is approved: the next session charges them
-- nothing, so what they overpaid is refunded; a final-level student still in study may spill over and is not one of them
CREATE FUNCTION finance.overpaid_refund_only(p_student uuid) RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN s.status = 'DECEASED' THEN 'DECEASED'
                WHEN s.status = 'GRADUATED' THEN 'GRADUATED'
                WHEN s.status IN ('WITHDRAWN', 'VOLUNTARY_WITHDRAWAL') THEN 'WITHDRAWN'
                WHEN s.status IN ('EXPELLED', 'TRANSFERRED_OUT') THEN 'LEFT'
                WHEN EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED') THEN 'AWARD_APPROVED' END
      FROM people.student s WHERE s.id = p_student
$fn$;
COMMENT ON FUNCTION finance.overpaid_refund_only(uuid) IS 'V781: DECEASED, GRADUATED, WITHDRAWN (withdrawn or voluntarily withdrawn), LEFT (expelled or transferred out) or AWARD_APPROVED when a student''s excess is refunded and never credited to a wallet or carried; NULL otherwise.';

-- the semesters of a session a student's fees are not yet stated for: V616's fee_unstated_semesters word for word except the last branch,
-- which reads every semester not closed (not only the open ones): a first-semester double payer before the second semester's line is stated
CREATE FUNCTION finance.fee_semesters_unstated(p_student uuid, p_session text) RETURNS integer[] LANGUAGE sql STABLE AS $fn$
    WITH me AS (SELECT s.entry_mode, p.category FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student),
    lines AS (SELECT f.semester FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], NULL, true) c JOIN finance.fee_schedule f ON f.id = c.id)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM me) THEN '{}'::int[]
        WHEN (SELECT me.entry_mode IS NOT DISTINCT FROM 'CCE' OR people.is_postgraduate(me.entry_mode, me.category) FROM me) THEN '{}'::int[]
        WHEN p_session < coalesce(finance.schedule_from(), p_session) THEN '{}'::int[]
        WHEN NOT EXISTS (SELECT 1 FROM lines) THEN '{}'::int[]
        WHEN EXISTS (SELECT 1 FROM lines l WHERE l.semester IS NULL) THEN '{}'::int[]
        ELSE coalesce((SELECT array_agg(n.number ORDER BY n.number)
                         FROM generate_series(1, coalesce((SELECT a.semesters FROM policy.academic_session a WHERE a.name = p_session), 2)) n(number)
                        WHERE NOT EXISTS (SELECT 1 FROM policy.semester sm WHERE sm.session = p_session AND sm.number = n.number AND sm.state = 'CLOSED')
                          AND NOT EXISTS (SELECT 1 FROM lines l WHERE l.semester = n.number)), '{}'::int[]) END
$fn$;
COMMENT ON FUNCTION finance.fee_semesters_unstated(uuid, text) IS 'V781: the semesters of a session — every one not closed, from 1 to the session''s number of semesters — with no fee line for the student. A whole-session line reads as stating every semester. finance.fee_unstated_semesters (the fee watch) reads the open semesters only and is not changed.';

-- decided = the decisions that stand + the refunds raised by hand against the session's school-fees payments (a refund reduces no
-- "paid", so it is counted here or the same money could go out twice)
CREATE FUNCTION finance.overpayment_decided(p_student uuid, p_session text, p_except_refund text DEFAULT NULL) RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT sum(d.amount) FROM finance.overpayment_decision d
                      LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
                     WHERE d.student_id = p_student AND d.session = p_session AND d.superseded_at IS NULL
                       AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')), 0)
         + coalesce((SELECT sum(rf.amount) FROM finance.refund rf JOIN finance.payment_reference r ON r.reference = rf.source_reference
                      WHERE rf.state <> 'REJECTED' AND r.student_id = p_student AND r.session = p_session
                        AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
                        AND (p_except_refund IS NULL OR rf.reference <> p_except_refund)
                        AND NOT EXISTS (SELECT 1 FROM finance.overpayment_decision d2
                                         WHERE d2.reference = rf.reference AND d2.decision = 'REFUND' AND d2.superseded_at IS NULL)), 0)
$fn$;
COMMENT ON FUNCTION finance.overpayment_decided(uuid, text, text) IS 'V781: the money of a student''s excess on a session already decided: the decisions that stand (a refund the desk rejected does not stand) plus the refunds raised by hand against the session''s counted school-fees payments (not the refund of a decision that stands). p_except_refund leaves one refund reference out (the trigger of a decision passes the reference of the row it is writing).';

-- what a decision that ends above the excess owes back: only for the student's current session, with a charge stated; hand refunds are not in it
CREATE FUNCTION finance.overpayment_shortfall(p_student uuid, p_session text) RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_session IS NULL OR p_session IS DISTINCT FROM people.student_current_session(p_student) THEN 0::numeric
                ELSE coalesce((SELECT greatest(dz.decisions - greatest(p.paid - p.due, 0), 0)
                                 FROM finance.position(p_student, p_session) p
                                 CROSS JOIN LATERAL (SELECT coalesce(sum(d.amount), 0) AS decisions
                                                       FROM finance.overpayment_decision d
                                                       LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
                                                      WHERE d.student_id = p_student AND d.session = p_session AND d.superseded_at IS NULL
                                                        AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')) dz
                                WHERE p.due > 0 AND finance.fee_stated(p_student, p_session)), 0::numeric) END
$fn$;
COMMENT ON FUNCTION finance.overpayment_shortfall(uuid, text) IS 'V781: the hidden amount of a student whose session''s charge rose after a decision: what the standing decisions pass of what is now paid above the charge. 0 for a session that is not the student''s current one, when no charge is stated, and when nothing is over-decided. The student''s own position reads the decided money as paid, so the balance reads nothing; this is the money the session is short of.';

-- the wallet's own money from an overpayment: OVERPAID credited - applied - reversed - refunded, less a refund of it pending, and never
-- more than the wallet holds in all less every pending refund (a wallet owing gives 0). NELFUND, grants, top-ups and old-portal credits
-- are other sources: never read.
CREATE FUNCTION finance.overpaid_wallet_money(p_student uuid) RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT greatest(least(
        coalesce((SELECT b.available - b.held FROM finance.wallet_balances(p_student) b WHERE b.source_code = 'OVERPAID'), 0),
        finance.wallet_balance(p_student)
          - coalesce((SELECT sum(w.amount) FROM finance.wallet_withdrawal w WHERE w.student_id = p_student AND w.state IN ('REQUESTED', 'APPROVED')), 0)), 0)
$fn$;
COMMENT ON FUNCTION finance.overpaid_wallet_money(uuid) IS 'V781: the wallet''s own money from an overpayment: OVERPAID credited less applied, reversed and refunded, less a refund of it pending, and never more than the wallet holds in all less every pending refund. Other sources are never read.';

-- the part of the wallet's overpaid money a refund may take: what a decision above the excess owes back to the session's fees is kept back
CREATE FUNCTION finance.overpaid_refundable(p_student uuid, p_counting_back numeric DEFAULT 0) RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT greatest(b.available - b.held + coalesce(p_counting_back, 0)
                                     - CASE WHEN b.available > 0 THEN finance.overpayment_shortfall(p_student, people.student_current_session(p_student)) ELSE 0 END, 0)
                       FROM finance.wallet_balances(p_student) b WHERE b.source_code = 'OVERPAID'), 0)
$fn$;
COMMENT ON FUNCTION finance.overpaid_refundable(uuid, numeric) IS 'V781: what the wallet''s overpaid money may give back as a refund: available less held (p_counting_back adds back the hold of a refund being approved) less what a decision above the excess owes the session''s fees. The session the wallet pays first; read only for a wallet that holds overpaid money.';
CREATE FUNCTION finance.overpaid_kept_back(p_student uuid) RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT greatest(greatest(b.available - b.held, 0) - finance.overpaid_refundable(p_student), 0)
                       FROM finance.wallet_balances(p_student) b WHERE b.source_code = 'OVERPAID'), 0)
$fn$;
COMMENT ON FUNCTION finance.overpaid_kept_back(uuid) IS 'V781: the part of the wallet''s overpaid money that is not refunded because a decision above the excess owes it back to the session''s fees.';

-- the arithmetic that replaces "a decision stands": taking a payment away is refused only when it would leave less paid above the charge
-- than is decided, or requested and not yet decided
CREATE FUNCTION finance.overpayment_decisions_covered(p_student uuid, p_session text, p_leaving numeric) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN d.decided <= 0 AND q.amount IS NULL THEN true
                ELSE coalesce((SELECT p.paid - p.due - coalesce(p_leaving, 0) >= d.decided + coalesce(q.amount, 0) - 0.005
                                 FROM finance.position(p_student, p_session) p), true) END
      FROM (SELECT finance.overpayment_decided(p_student, p_session) AS decided) d,
           (SELECT sum(x.confirmed_amount) AS amount FROM finance.legacy_credit_request x
             WHERE x.student_id = p_student AND x.session = p_session AND x.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')) q
$fn$;
COMMENT ON FUNCTION finance.overpayment_decisions_covered(uuid, text, numeric) IS 'V781: true when nothing is decided and no credit request is open for the student and session; else whether what is paid above the charge, less the p_leaving a correction would take away, still covers the decided money (refunds raised by hand included) and the open request''s amount. The archive, the swap, the reallocation and the "never received" withdrawal refuse a school-fees payment on this, not on the mere presence of a decision.';

-- a school-fees record of a student and session with a decision that stands or a request open: the old fees reset, an upload that would
-- take it over and the put-right leave it (a single expression, so it is read in the middle of a set of records)
CREATE FUNCTION finance.overpayment_holds_record(p_student uuid, p_session text, p_purpose text) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT p_purpose LIKE 'School fees%'
       AND (EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = p_student AND d.session = p_session AND d.superseded_at IS NULL)
            OR EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.student_id = p_student AND q.session = p_session
                          AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')))
$fn$;
COMMENT ON FUNCTION finance.overpayment_holds_record(uuid, text, text) IS 'V781: true for a school-fees record of a student and session on which an overpayment decision stands or a credit request is open: money decided or requested rests on the counted payments, so old-fees maintenance leaves them.';

-- ── 5a · the session's reads taking the students asked for: each is its own text with its rows cut to them ──
-- The Overpaid school fees list is worked out for a session, and every part of it — a student's charge (fee_profiles, fee_sums,
-- session_charges), what was paid, the payments the bank may have charged twice — reads the whole session (54,575 students on the live-shaped
-- copy) even when one student is asked for. Each of the five below is the text of the function as it stands on the database, restated by
-- anchor (each asserted to occur exactly once), with one more parameter: the students whose rows it works out (NULL: every student, exactly
-- the function it is cut from). Every row of a student is worked out from that student's own records and the session's fee lines alone, so a
-- row never depends on who else is asked for; db/check.sql holds that for the Overpaid school fees list (the read of every student at once
-- equals the read of each student alone). Each is a PL/pgSQL function planned for the students it is given on every call (a SQL function is
-- planned once without them, and a plan kept for "every student" would read the session's payments, registrations and profiles for one).
CREATE FUNCTION pg_temp.v781_plpgsql(p_def text, p_what text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_head text := E' LANGUAGE sql\n STABLE\nAS $function$\n'; v_tail text := '$function$'; v_text text := rtrim(p_def, E'\n');
BEGIN
    PERFORM pg_temp.v781_once(p_def, v_head, p_what || ' (its language)');
    IF right(v_text, length(v_tail)) <> v_tail THEN RAISE EXCEPTION 'V781: % is not as it was left (its body does not end the text)', p_what; END IF;
    RETURN replace(left(v_text, length(v_text) - length(v_tail)), v_head,
                   E' LANGUAGE plpgsql\n STABLE\n SET plan_cache_mode TO \'force_custom_plan\'\nAS $function$\n#variable_conflict use_column\nBEGIN\nRETURN QUERY\n')
           || E'\n;\nEND\n$function$\n';
END $$;
DO $v781$
DECLARE d text;
BEGIN
    -- the charge profiles
    d := pg_get_functiondef('finance.fee_profiles(text)'::regprocedure);
    PERFORM pg_temp.v781_once(d, $a$CREATE OR REPLACE FUNCTION finance.fee_profiles(p_session text)$a$, 'finance.fee_profiles (its head)');
    PERFORM pg_temp.v781_once(d, $a$FROM ref.programme pr),$a$, 'finance.fee_profiles (the final levels)');
    PERFORM pg_temp.v781_once(d, $a$WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e$a$, 'finance.fee_profiles (the registrations)');
    PERFORM pg_temp.v781_once(d, $a$AND finance.purpose_semester(r.purpose) IS NOT NULL) x$a$, 'finance.fee_profiles (the semesters paid for)');
    PERFORM pg_temp.v781_once(d, $a$admissions.pg_fee_stages_of(p_session, NULL)$a$, 'finance.fee_profiles (the postgraduate stages)');
    PERFORM pg_temp.v781_once(d, $a$LEFT JOIN pgs ON pgs.student_id = s.id$a$, 'finance.fee_profiles (its last join)');
    d := replace(d, $a$CREATE OR REPLACE FUNCTION finance.fee_profiles(p_session text)$a$, $a$CREATE OR REPLACE FUNCTION finance.fee_profiles_of(p_session text, p_students uuid[])$a$);
    -- the final level of a programme is read for the programmes of the students asked for (one read of a programme is dear)
    d := replace(d, $a$FROM ref.programme pr),$a$,
                    $a$FROM ref.programme pr WHERE p_students IS NULL OR pr.code IN (SELECT st.programme_code FROM people.student st WHERE st.id = ANY (p_students))),$a$);
    d := replace(d, $a$WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e$a$,
                    $a$WHERE (p_students IS NULL OR cr.student_id = ANY (p_students)) AND cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e$a$);
    d := replace(d, $a$AND finance.purpose_semester(r.purpose) IS NOT NULL) x$a$,
                    $a$AND finance.purpose_semester(r.purpose) IS NOT NULL AND (p_students IS NULL OR r.student_id = ANY (p_students))) x$a$);
    -- the stages are read for the postgraduate students asked for, exactly the set admissions.pg_stages_of reads when none is named
    d := replace(d, $a$admissions.pg_fee_stages_of(p_session, NULL)$a$,
                    $a$admissions.pg_fee_stages_of(p_session, CASE WHEN p_students IS NULL THEN NULL
                         ELSE coalesce((SELECT array_agg(st.id) FROM people.student st JOIN ref.programme pp ON pp.code = st.programme_code
                                         WHERE st.id = ANY (p_students) AND people.is_postgraduate(st.entry_mode, pp.category)), '{}'::uuid[]) END)$a$);
    d := replace(d, $a$LEFT JOIN pgs ON pgs.student_id = s.id$a$, E'LEFT JOIN pgs ON pgs.student_id = s.id\n     WHERE p_students IS NULL OR s.id = ANY (p_students)');
    EXECUTE pg_temp.v781_plpgsql(d, 'the restricted read');

    -- what each charge profile costs
    d := pg_get_functiondef('finance.fee_sums(text,integer)'::regprocedure);
    PERFORM pg_temp.v781_once(d, $a$CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)$a$, 'finance.fee_sums (its head)');
    PERFORM pg_temp.v781_once(d, $a$FROM finance.fee_profiles(p_session) pr) x$a$, 'finance.fee_sums (the profiles)');
    d := replace(d, $a$CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)$a$,
                    $a$CREATE OR REPLACE FUNCTION finance.fee_sums_of(p_session text, p_semester integer, p_students uuid[])$a$);
    d := replace(d, $a$FROM finance.fee_profiles(p_session) pr) x$a$, $a$FROM finance.fee_profiles_of(p_session, p_students) pr) x$a$);
    EXECUTE pg_temp.v781_plpgsql(d, 'the restricted read');

    -- what each student of the session is charged
    d := pg_get_functiondef('finance.session_charges(text)'::regprocedure);
    PERFORM pg_temp.v781_once(d, $a$CREATE OR REPLACE FUNCTION finance.session_charges(p_session text)$a$, 'finance.session_charges (its head)');
    PERFORM pg_temp.v781_once(d, $a$AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)$a$, 'finance.session_charges (the payments in time)');
    PERFORM pg_temp.v781_once(d, $a$FROM finance.fee_profiles(p_session) fp)$a$, 'finance.session_charges (the profiles)');
    PERFORM pg_temp.v781_once(d, $a$FROM finance.fee_sums(p_session, NULL) x)$a$, 'finance.session_charges (the sums)');
    d := replace(d, $a$CREATE OR REPLACE FUNCTION finance.session_charges(p_session text)$a$,
                    $a$CREATE OR REPLACE FUNCTION finance.session_charges_of(p_session text, p_students uuid[])$a$);
    d := replace(d, $a$AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)$a$,
                    $a$AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at) AND (p_students IS NULL OR r.student_id = ANY (p_students))$a$);
    d := replace(d, $a$FROM finance.fee_profiles(p_session) fp)$a$, $a$FROM finance.fee_profiles_of(p_session, p_students) fp)$a$);
    d := replace(d, $a$FROM finance.fee_sums(p_session, NULL) x)$a$, $a$FROM finance.fee_sums_of(p_session, NULL, p_students) x)$a$);
    EXECUTE pg_temp.v781_plpgsql(d, 'the restricted read');

    -- what each student of the session paid
    d := pg_get_functiondef('finance.session_payments(text)'::regprocedure);
    PERFORM pg_temp.v781_once(d, $a$CREATE OR REPLACE FUNCTION finance.session_payments(p_session text)$a$, 'finance.session_payments (its head)');
    PERFORM pg_temp.v781_once(d, $a$r.purpose LIKE 'School fees%'),$a$, 'finance.session_payments (the payments)');
    d := replace(d, $a$CREATE OR REPLACE FUNCTION finance.session_payments(p_session text)$a$,
                    $a$CREATE OR REPLACE FUNCTION finance.session_payments_of(p_session text, p_students uuid[])$a$);
    d := replace(d, $a$r.purpose LIKE 'School fees%'),$a$, $a$r.purpose LIKE 'School fees%' AND (p_students IS NULL OR r.student_id = ANY (p_students))),$a$);
    EXECUTE pg_temp.v781_plpgsql(d, 'the restricted read');

    -- the payments the bank may have charged twice
    d := pg_get_functiondef('finance.possible_double_charges(text)'::regprocedure);
    PERFORM pg_temp.v781_once(d, $a$CREATE OR REPLACE FUNCTION finance.possible_double_charges(p_session text)$a$, 'finance.possible_double_charges (its head)');
    PERFORM pg_temp.v781_once(d, $a$AND (p_session IS NULL OR r.session = p_session)$a$, 'finance.possible_double_charges (the payments)');
    d := replace(d, $a$CREATE OR REPLACE FUNCTION finance.possible_double_charges(p_session text)$a$,
                    $a$CREATE OR REPLACE FUNCTION finance.possible_double_charges_of(p_session text, p_students uuid[])$a$);
    d := replace(d, $a$AND (p_session IS NULL OR r.session = p_session)$a$, $a$AND (p_session IS NULL OR r.session = p_session) AND (p_students IS NULL OR r.student_id = ANY (p_students))$a$);
    EXECUTE pg_temp.v781_plpgsql(d, 'the restricted read');
END $v781$;
COMMENT ON FUNCTION finance.fee_profiles_of(text, uuid[]) IS 'V781: finance.fee_profiles for the students named only (NULL: every student, exactly finance.fee_profiles): its text with the registrations, the semesters paid for, the postgraduate stages and the students cut to them.';
COMMENT ON FUNCTION finance.fee_sums_of(text, integer, uuid[]) IS 'V781: finance.fee_sums for the charge profiles of the students named only (NULL: every profile, exactly finance.fee_sums).';
COMMENT ON FUNCTION finance.session_charges_of(text, uuid[]) IS 'V781: finance.session_charges for the students named only (NULL: every student, exactly finance.session_charges).';
COMMENT ON FUNCTION finance.session_payments_of(text, uuid[]) IS 'V781: finance.session_payments for the students named only (NULL: every student, exactly finance.session_payments).';
COMMENT ON FUNCTION finance.possible_double_charges_of(text, uuid[]) IS 'V781: finance.possible_double_charges for the students named only (NULL: every student, exactly finance.possible_double_charges).';

-- ── 6 · finance.overpaid restated: a student with two decisions is listed once, and "undecided" is "remaining >= 1" ──
-- Its join to finance.overpayment_settled returned one row a decision; with several standing the student would be listed twice. Its text
-- is V725's with the level expression as V741 left it; that expression is asserted below to be what the function reads today. It is
-- finance.overpaid_of(session, students) — the students named only, NULL for every student — and finance.overpaid(session) reads it for all.
DO $v781$
DECLARE d text := pg_get_functiondef('finance.overpaid(text)'::regprocedure);
BEGIN
    PERFORM pg_temp.v781_once(d, $a$reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN ('CCE', 'POSTGRADUATE') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, left(s.entry_session, 4))], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)$a$, 'finance.overpaid (its level expression)');
    PERFORM pg_temp.v781_once(d, $a$      CROSS JOIN policy.cancelled_years() cy(years, into_years)$a$, 'finance.overpaid (cancelled years)');
    PERFORM pg_temp.v781_once(d, $a$      CROSS JOIN policy.cohort_starts() cs(admissions, firsts)   -- V738$a$, 'finance.overpaid (cohort starts)');
END $v781$;

DROP FUNCTION finance.overpaid(text);
CREATE FUNCTION finance.overpaid_of(p_session text, p_students uuid[])
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, faculty_code text, level integer, due numeric, paid numeric,
               excess numeric, decision text, decided numeric, reference text, to_session text, decided_at timestamptz, refund_state text,
               old_portal boolean, remaining numeric, decision_count integer, refunded_by_hand numeric)
 LANGUAGE plpgsql STABLE SET plan_cache_mode TO 'force_custom_plan' AS $function$
#variable_conflict use_column
BEGIN
RETURN QUERY
    WITH ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges_of(p_session, p_students) c WHERE c.total > 0),
    pay AS MATERIALIZED (SELECT p.student_id, p.total FROM finance.session_payments_of(p_session, p_students) p),
    old AS MATERIALIZED (
        SELECT DISTINCT r.student_id FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND (r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%') AND (p_students IS NULL OR r.student_id = ANY (p_students))),
    -- V781: every decision that stands, summed; the latest one named
    dec AS MATERIALIZED (
        SELECT d.student_id, sum(d.amount) AS decided, count(*)::int AS n,
               (array_agg(d.decision   ORDER BY d.decided_at DESC, d.id DESC))[1] AS decision,
               (array_agg(d.reference  ORDER BY d.decided_at DESC, d.id DESC))[1] AS reference,
               (array_agg(d.to_session ORDER BY d.decided_at DESC, d.id DESC))[1] AS to_session,
               max(d.decided_at) AS decided_at,
               (array_agg(rf.state     ORDER BY d.decided_at DESC, d.id DESC))[1] AS refund_state
          FROM finance.overpayment_decision d
          LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
         WHERE d.session = p_session AND d.superseded_at IS NULL AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
           AND (p_students IS NULL OR d.student_id = ANY (p_students))
         GROUP BY d.student_id),
    -- V781: refunds raised by hand against the session's school-fees payments (not the refund of a decision that stands)
    hr AS MATERIALIZED (
        SELECT r.student_id, sum(rf.amount) AS refunded
          FROM finance.refund rf JOIN finance.payment_reference r ON r.reference = rf.source_reference
         WHERE rf.state <> 'REJECTED' AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND (p_students IS NULL OR r.student_id = ANY (p_students))
           AND NOT EXISTS (SELECT 1 FROM finance.overpayment_decision d2
                            WHERE d2.reference = rf.reference AND d2.decision = 'REFUND' AND d2.superseded_at IS NULL)
         GROUP BY r.student_id)
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN ('CCE', 'POSTGRADUATE') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, left(s.entry_session, 4))], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years),   -- V725
           ch.total, pay.total, pay.total - ch.total,
           d.decision, nullif(coalesce(d.decided, 0) + coalesce(hr.refunded, 0), 0), d.reference, d.to_session, d.decided_at, d.refund_state, old.student_id IS NOT NULL,
           greatest(pay.total - ch.total - coalesce(d.decided, 0) - coalesce(hr.refunded, 0), 0), coalesce(d.n, 0), coalesce(hr.refunded, 0)
      FROM ch
      JOIN pay ON pay.student_id = ch.student_id AND pay.total - ch.total >= 1
      JOIN people.student s ON s.id = ch.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN old ON old.student_id = ch.student_id
      LEFT JOIN dec d ON d.student_id = ch.student_id
      LEFT JOIN hr ON hr.student_id = ch.student_id
      CROSS JOIN policy.cancelled_years() cy(years, into_years)
      CROSS JOIN policy.cohort_starts() cs(admissions, firsts);   -- V738
END $function$;
COMMENT ON FUNCTION finance.overpaid_of(text, uuid[]) IS 'V506, V781: the students of a session (the students named only; NULL: every student) who paid at least NGN 1 above what they were charged, with the decision that stands (the latest) and what is decided in all — the decisions that stand plus the refunds raised by hand against the session''s payments — and what remains undecided (remaining; undecided is remaining >= 1). Several decisions may stand for a student; the student is listed once. A student''s row is the same whoever else is named.';
CREATE FUNCTION finance.overpaid(p_session text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, faculty_code text, level integer, due numeric, paid numeric,
               excess numeric, decision text, decided numeric, reference text, to_session text, decided_at timestamptz, refund_state text,
               old_portal boolean, remaining numeric, decision_count integer, refunded_by_hand numeric)
 LANGUAGE sql STABLE AS $function$
    SELECT x.* FROM finance.overpaid_of(p_session, NULL) x
$function$;
COMMENT ON FUNCTION finance.overpaid(text) IS 'V506, V781: the students of a session who paid at least NGN 1 above what they were charged, with the decision that stands (the latest) and what is decided in all — the decisions that stand plus the refunds raised by hand against the session''s payments — and what remains undecided (remaining; undecided is remaining >= 1). Several decisions may stand for a student; the student is listed once. It is finance.overpaid_of for every student.';


-- ── 7 · the list: every student of a session paid above the charge, with the cause, whether the row is decided in bulk, and the holds ──
-- One read of the session for the students asked for (p_students; NULL: every student). Every part of it is cut to those students — the
-- charge, the payments, the bank check, the charge profiles — so one student costs one student, and a student's row is the same whoever else
-- is asked for (db/check.sql holds that). A decided student no longer overpaid is kept in sight (cause NULL, suggested RECOVER) so a charge
-- that rose after a decision is seen.
-- A plpgsql function so that it is never inlined into the query that calls it (a filter or an order on its rows made the planner repeat the
-- per-student holds for every row: quadratic); the two CTEs that are dear for each student are computed once, and the payments of one amount,
-- the amounts that make up an excess and the repeats are each found in one pass, never by a student's rows against every other student's.
-- The reads that take the students (section 5a and finance.overpaid_of) are each planned for the students they are given; this function is
-- not, so that the per-student functions it calls for each row keep their plans (planned afresh for every row, they cost twice as much).
CREATE FUNCTION finance.overpaid_read(p_session text, p_students uuid[] DEFAULT NULL)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, dept_code text, faculty_code text, level integer, cohort_level integer,
               status text, due numeric, paid numeric, excess numeric, decided numeric, remaining numeric, cause text, bulk boolean,
               repeat_amount numeric, n_payments integer, payments jsonb, holds text[], refund_only text, suggested text)
 LANGUAGE plpgsql STABLE AS $fn$
#variable_conflict use_column
BEGIN
RETURN QUERY
WITH ov AS MATERIALIZED (SELECT x.* FROM finance.overpaid_of(p_session, p_students) x),
gone AS MATERIALIZED (   -- decided, no longer overpaid: kept in sight (few: their figures are each student's own position)
    SELECT d.student_id, sum(d.amount) AS decisions
      FROM finance.overpayment_decision d LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
     WHERE d.session = p_session AND d.superseded_at IS NULL AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
       AND d.student_id NOT IN (SELECT ov.student_id FROM ov) AND (p_students IS NULL OR d.student_id = ANY (p_students))
     GROUP BY d.student_id),
o AS MATERIALIZED (
    SELECT x.student_id, x.number, x.name, x.programme_code, x.faculty_code, x.level AS cohort_level, x.due, x.paid, x.excess,
           coalesce(x.decided, 0) AS decided, coalesce(x.decided, 0) - x.refunded_by_hand AS decisions, x.remaining, true AS listed
      FROM ov x WHERE p_students IS NULL OR x.student_id = ANY (p_students)
    UNION ALL
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code, NULL::int,
           p.due, p.paid, p.paid - p.due, finance.overpayment_decided(s.id, p_session), g.decisions, 0::numeric, false
      FROM gone g JOIN people.student s ON s.id = g.student_id LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      CROSS JOIN LATERAL finance.position(s.id, p_session) p),
who AS MATERIALIZED (   -- each listed student's own session and window types (CCE, PG and MBBS stand apart: V380, V389, V733)
    SELECT o.student_id, people.student_current_session(o.student_id) AS cur_session,
           policy.window_type_for(o.student_id, 'SCHOOL_FEES_PAYMENT') AS pay_type, policy.window_type_for(o.student_id, 'COURSE_REGISTRATION') AS reg_type
      FROM o WHERE o.listed),
ids AS MATERIALIZED (SELECT coalesce(array_agg(o.student_id), '{}'::uuid[]) AS a FROM o WHERE o.listed),   -- the students the holds are read for
pay AS MATERIALIZED (
    SELECT r.student_id, r.id, r.reference, r.amount, round(r.amount) AS amt, r.purpose, r.channel, r.confirmed_at, k.kind,
           -- the bank's or the gateway's own report of the payment (never a hand confirmation alone)
           (k.kind = 'PORTAL' AND (r.channel = 'NELFUND wallet'
              OR EXISTS (SELECT 1 FROM finance.gateway_event e WHERE e.reference = r.reference AND e.source <> 'VALIDATE' AND nullif(btrim(e.gateway_ref), '') IS NOT NULL)
              OR EXISTS (SELECT 1 FROM finance.paydirect_inbox i WHERE i.reference = r.reference AND NOT i.is_reversal)
              OR EXISTS (SELECT 1 FROM finance.paydirect_collection c WHERE c.reference = r.reference AND c.state = 'MATCHED'))) AS evidenced
      FROM finance.payment_reference r
      CROSS JOIN LATERAL (SELECT CASE WHEN r.channel = 'CARRIED' THEN 'CARRIED'
                                      WHEN r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%' THEN 'OLD' ELSE 'PORTAL' END AS kind) k
     WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
       AND r.student_id IN (SELECT o.student_id FROM o)),
byamt AS MATERIALIZED (   -- how many portal and old-portal records carry each amount
    SELECT p.student_id, p.amt, (count(*) FILTER (WHERE p.kind = 'PORTAL'))::int AS np, (count(*) FILTER (WHERE p.kind = 'OLD'))::int AS no,
           (count(*) FILTER (WHERE p.kind = 'PORTAL' AND p.evidenced))::int AS npe
      FROM pay p WHERE p.kind <> 'CARRIED' GROUP BY p.student_id, p.amt),
grp AS MATERIALIZED (     -- the old portal's own label twice at one amount
    SELECT p.student_id, p.purpose, p.amt, count(*)::int AS n FROM pay p WHERE p.kind = 'OLD' GROUP BY 1, 2, 3 HAVING count(*) >= 2),
oldg AS MATERIALIZED (SELECT g.student_id, sum((g.n - 1) * g.amt) AS r_old, max(g.amt) AS amt FROM grp g GROUP BY g.student_id),
npay AS MATERIALIZED (
    SELECT p.student_id, (count(*) FILTER (WHERE p.kind <> 'CARRIED'))::int AS n_pay,
           jsonb_agg(jsonb_build_object('amount', p.amount, 'channel', p.channel, 'on', (p.confirmed_at AT TIME ZONE 'Africa/Lagos')::date, 'kind', p.kind)
                     ORDER BY p.confirmed_at, p.reference) AS payments
      FROM pay p GROUP BY p.student_id),
rep AS MATERIALIZED (SELECT DISTINCT b.student_id FROM byamt b WHERE b.np >= 2 OR (b.np >= 1 AND b.no >= 1)),   -- a portal record repeated, or one on both portals
pt AS MATERIALIZED (      -- the amount (the largest) repeated on the portal that makes up the excess, k times
    SELECT DISTINCT ON (o.student_id) o.student_id, b.amt, b.npe = b.np AS ok
      FROM o JOIN byamt b ON b.student_id = o.student_id
     WHERE b.np >= 2 AND EXISTS (SELECT 1 FROM generate_series(1, b.np - 1) k WHERE abs(o.excess - k * b.amt) < 1)
     ORDER BY o.student_id, b.amt DESC),
op AS MATERIALIZED (      -- the amount (the largest) on the old portal and the new that makes up the excess, k times
    SELECT DISTINCT ON (o.student_id) o.student_id, b.amt, b.npe = b.np AS ok
      FROM o JOIN byamt b ON b.student_id = o.student_id
     WHERE b.np >= 1 AND b.no >= 1 AND EXISTS (SELECT 1 FROM generate_series(1, b.np + b.no - 1) k WHERE abs(o.excess - k * b.amt) < 1)
     ORDER BY o.student_id, b.amt DESC),
sig AS MATERIALIZED (
    SELECT o.student_id, pt.amt AS pt_amt, pt.ok AS pt_ok, op.amt AS op_amt, op.ok AS op_ok, coalesce(g.r_old, 0) AS r_old, g.amt AS old_amt,
           coalesce(n.n_pay, 0) AS n_pay, coalesce(n.payments, '[]'::jsonb) AS payments,
           rp.student_id IS NOT NULL AS other_repeat,
           -- the old-portal repeat makes up the excess exactly: one group k times, or every repeat whole
           (g.r_old IS NOT NULL AND (abs(o.excess - g.r_old) < 1
              OR EXISTS (SELECT 1 FROM grp x WHERE x.student_id = o.student_id
                            AND EXISTS (SELECT 1 FROM generate_series(1, x.n - 1) k WHERE abs(o.excess - k * x.amt) < 1)))) AS old_exact
      FROM o LEFT JOIN npay n ON n.student_id = o.student_id
      LEFT JOIN oldg g ON g.student_id = o.student_id
      LEFT JOIN rep rp ON rp.student_id = o.student_id
      LEFT JOIN pt ON pt.student_id = o.student_id
      LEFT JOIN op ON op.student_id = o.student_id),
adj AS MATERIALIZED (     -- a credit of an adjusted amount already stands: what is left is looked at by a person
    SELECT DISTINCT q.student_id FROM finance.legacy_credit_request q WHERE q.session = p_session AND q.status = 'CREDITED' AND q.adjusted),
-- the holds, each a set of students
bank AS MATERIALIZED (
    SELECT DISTINCT d.student_id FROM finance.possible_double_charges_of(p_session, (SELECT i.a FROM ids i)) d
     WHERE d.purpose LIKE 'School fees%' AND (d.verdict IS NULL OR d.open_requests > 0)
    UNION SELECT w.student_id FROM finance.payment_not_received w
     WHERE w.session = p_session AND w.purpose LIKE 'School fees%' AND w.state = 'PROPOSED'),
same AS MATERIALIZED (   -- one payment recorded twice: only records of the same amount are compared (V670's signals), each pair once
    SELECT DISTINCT g.student_id FROM (SELECT p.student_id, array_agg(p.id ORDER BY p.id) AS ids FROM pay p GROUP BY p.student_id, p.amt HAVING count(*) >= 2) g
      CROSS JOIN LATERAL unnest(g.ids) WITH ORDINALITY a(id, i)
      JOIN LATERAL unnest(g.ids) WITH ORDINALITY b(id, j) ON b.j > a.i
     WHERE jsonb_array_length(finance.payment_duplicate_signals(a.id, b.id) -> 'authoritative') > 0),
rev AS MATERIALIZED (SELECT DISTINCT p.student_id FROM pay p JOIN finance.paydirect_inbox i ON i.reference = p.reference AND i.is_reversal),
review AS MATERIALIZED (
    SELECT DISTINCT a.student_id FROM finance.payment_archive a
     WHERE a.session = p_session AND a.purpose LIKE 'School fees%' AND a.state IN ('ARCHIVED', 'UNDER_REVIEW', 'PENDING_BURSAR_APPROVAL', 'RETURNED')),
corr AS MATERIALIZED (
    SELECT w.from_student AS student_id FROM finance.payment_swap w WHERE w.status = 'PENDING_APPROVAL' AND w.session = p_session AND w.purpose LIKE 'School fees%'
    UNION SELECT w.to_student FROM finance.payment_swap w WHERE w.status = 'PENDING_APPROVAL' AND w.session = p_session AND w.purpose LIKE 'School fees%'
    UNION SELECT q.student_id FROM finance.payment_reallocation q WHERE q.status IN ('PENDING_APPROVAL', 'RETURNED') AND (q.from_session = p_session OR q.to_session = p_session)),
prof AS MATERIALIZED (SELECT fp.student_id, fp.profile_key, fp.is_spill, fp.reg_sems FROM finance.fee_profiles_of(p_session, (SELECT i.a FROM ids i)) fp),
sums AS MATERIALIZED (SELECT x.profile_key, x.fee, x.late_payment, x.late_registration, x.due_upto - x.fee - x.late_payment - x.late_registration AS later FROM finance.fee_sums_of(p_session, NULL, (SELECT i.a FROM ids i)) x),
spill_sems AS MATERIALIZED (   -- the semesters a spillover line is stated for and a course may still be registered in
    SELECT coalesce(array_agg(DISTINCT f.semester), '{}'::int[]) AS sems
      FROM finance.fee_schedule f JOIN policy.semester sm ON sm.session = f.session AND sm.number = f.semester
     WHERE f.session = p_session AND f.ended_at IS NULL AND f.spillover AND f.kind = 'FEE' AND f.semester IS NOT NULL AND sm.state <> 'CLOSED'),
payw AS MATERIALIZED (         -- the three school-fees windows of the session, each read once
    SELECT t.type, w.* FROM unnest(ARRAY['SCHOOL_FEES_PAYMENT', 'CCE_SCHOOL_FEES_PAYMENT', 'PG_SCHOOL_FEES_PAYMENT']) t(type)
     CROSS JOIN LATERAL policy.window_state(t.type, p_session, NULL) w),
regw AS MATERIALIZED (         -- a registration window with a late fee, of a semester not yet closed
    SELECT t.type, sem FROM unnest(ARRAY['COURSE_REGISTRATION', 'CCE_COURSE_REGISTRATION', 'PG_COURSE_REGISTRATION']) t(type)
     CROSS JOIN generate_series(1, 3) sem CROSS JOIN LATERAL policy.window_state(t.type, p_session, sem) rw
     WHERE rw.configured AND rw.late_fee_enabled
       AND NOT EXISTS (SELECT 1 FROM policy.semester ps WHERE ps.session = p_session AND ps.number = sem AND ps.state = 'CLOSED')),
hold AS MATERIALIZED (
    SELECT o.student_id, array_remove(ARRAY[
             CASE WHEN wh.cur_session IS DISTINCT FROM p_session AND EXISTS (
                      SELECT 1 FROM policy.academic_session a JOIN policy.academic_session c ON c.name = wh.cur_session
                       WHERE a.name = p_session AND a.starts_on < c.starts_on) THEN 'PAST_SESSION' END,
             CASE WHEN finance.closed_for_fees(o.student_id, p_session) THEN 'CLOSED_FOR_FEES' END,
             CASE WHEN o.student_id IN (SELECT b.student_id FROM bank b) THEN 'BANK_CHECK' END,
             CASE WHEN o.student_id IN (SELECT x.student_id FROM same x) THEN 'SAME_PAYMENT' END,
             CASE WHEN o.student_id IN (SELECT x.student_id FROM rev x) THEN 'REVERSAL' END,
             CASE WHEN o.student_id IN (SELECT x.student_id FROM review x) THEN 'UNDER_REVIEW' END,
             CASE WHEN o.student_id IN (SELECT x.student_id FROM corr x) THEN 'OPEN_CORRECTION' END,
             CASE WHEN coalesce(sm.later, 0) >= 1 THEN 'SEMESTER_NOT_CHARGED' END,
             CASE WHEN cardinality(finance.fee_semesters_unstated(o.student_id, p_session)) > 0 THEN 'SEMESTER_NOT_STATED' END,
             CASE WHEN pf.is_spill AND NOT (coalesce(pf.reg_sems, '{}'::int[]) @> (SELECT s.sems FROM spill_sems s)) THEN 'SPILLOVER_SEMESTER' END,
             CASE WHEN coalesce(sm.late_registration, 0) > 0 AND EXISTS (
                      SELECT 1 FROM regw rw WHERE rw.type = wh.reg_type
                         AND NOT EXISTS (SELECT 1 FROM registration.course_registration cr
                                          WHERE cr.student_id = o.student_id AND cr.session = p_session AND cr.semester = rw.sem AND cr.submitted_at IS NOT NULL))
                  THEN 'LATE_FEE_POSSIBLE' END,
             CASE WHEN coalesce(sm.late_payment, 0) > 0 AND pw.configured AND pw.late_fee_enabled AND pw.closes_at IS NOT NULL AND now() > pw.closes_at
                       AND pw.phase IS DISTINCT FROM 'LATE'
                       AND coalesce((SELECT sum(p.amount) FROM pay p WHERE p.student_id = o.student_id AND p.confirmed_at <= pw.closes_at), 0) < coalesce(sm.fee, 0)
                  THEN 'LATE_FEE_LAPSED' END,
             CASE WHEN st.duplicate_of IS NOT NULL THEN 'MERGED_RECORD' END], NULL) AS holds
      FROM o JOIN people.student st ON st.id = o.student_id JOIN who wh ON wh.student_id = o.student_id
      LEFT JOIN payw pw ON pw.type = wh.pay_type
      LEFT JOIN prof pf ON pf.student_id = o.student_id LEFT JOIN sums sm ON sm.profile_key = pf.profile_key
     WHERE o.listed)
SELECT o.student_id, o.number, o.name, o.programme_code, pr.dept_code, o.faculty_code, st.current_level, o.cohort_level, st.status,
       o.due, o.paid, o.excess, o.decided, o.remaining,
       c.cause, b.bulk,
       CASE c.cause WHEN 'PORTAL_TWICE' THEN s.pt_amt WHEN 'OLD_AND_PORTAL' THEN s.op_amt WHEN 'OLD_TWICE' THEN s.old_amt END,
       coalesce(s.n_pay, 0), coalesce(s.payments, '[]'::jsonb), hh.holds, ro.why,
       CASE WHEN NOT o.listed OR o.decisions - greatest(o.excess, 0) >= 1 THEN 'RECOVER'   -- the standing decisions pass what is paid above the charge
            WHEN cardinality(hh.holds) > 0 THEN 'WAIT'
            WHEN c.cause = 'ABOVE_FEE_LINE' THEN 'CHECK_FEE_SETUP'
            WHEN NOT b.bulk THEN 'REVIEW_PAYMENTS'
            WHEN ro.why IS NOT NULL THEN 'REFUND' ELSE 'WALLET' END
  FROM o LEFT JOIN sig s ON s.student_id = o.student_id LEFT JOIN hold h ON h.student_id = o.student_id
  JOIN people.student st ON st.id = o.student_id LEFT JOIN ref.programme pr ON pr.code = o.programme_code
  CROSS JOIN LATERAL (SELECT CASE
        WHEN NOT o.listed THEN NULL
        WHEN s.pt_amt IS NOT NULL THEN 'PORTAL_TWICE'
        WHEN s.op_amt IS NOT NULL THEN 'OLD_AND_PORTAL'
        WHEN s.r_old > 0 AND o.excess <= s.r_old + 1 THEN 'OLD_TWICE'
        WHEN s.r_old > 0 OR s.other_repeat OR s.n_pay >= 3 THEN 'PART_PAYMENTS'
        ELSE 'ABOVE_FEE_LINE' END AS cause) c
  CROSS JOIN LATERAL (SELECT o.listed AND st.current_level IS NOT DISTINCT FROM o.cohort_level
                             AND o.student_id NOT IN (SELECT a.student_id FROM adj a)
                             AND coalesce(CASE c.cause WHEN 'PORTAL_TWICE' THEN s.pt_ok WHEN 'OLD_AND_PORTAL' THEN s.op_ok WHEN 'OLD_TWICE' THEN s.old_exact END, false) AS bulk) b
  CROSS JOIN LATERAL (SELECT finance.overpaid_refund_only(o.student_id) AS why) ro
  -- the second witness, tried here on the rows a bulk act would take, so an uncertain row shows held and never "ready"
  CROSS JOIN LATERAL (SELECT coalesce(h.holds, '{}'::text[]) || CASE
        WHEN b.bulk AND o.remaining >= 1 AND cardinality(coalesce(h.holds, '{}'::text[])) = 0
             AND abs((SELECT p.paid - p.due FROM finance.position(o.student_id, p_session) p) - o.excess) >= 1
        THEN ARRAY['EXCESS_UNCERTAIN'] ELSE '{}'::text[] END AS holds) hh;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_read(text, uuid[]) IS 'V781: the Overpaid school fees list of a session worked out live — every student paid above the charge with the cause (PORTAL_TWICE, OLD_AND_PORTAL, OLD_TWICE, PART_PAYMENTS, ABOVE_FEE_LINE), whether the row is decided in bulk (a repeated payment that makes up the excess exactly, on records the bank reported, at the level by entry year, no adjusted credit standing), the holds that stop every decision, and what the Bursary is advised (RECOVER, WAIT, CHECK_FEE_SETUP, REVIEW_PAYMENTS, REFUND, WALLET). A student decided and no longer overpaid is kept in sight with no cause. Every part of it is cut to the students asked for (p_students; NULL: every student), so one student costs one student and a student''s row is the same whoever else is asked for.';




-- ── 8 · the kept list, the desk's rows and the figures ──
-- Worked out by the API's job (every ten minutes when something changed, nightly for every session kept) and by the desk's Refresh; the
-- migration works nothing out. Needs no actor: both tables are audit-exempt.
CREATE FUNCTION finance.overpaid_refresh(p_session text) RETURNS TABLE(students integer, took_ms integer, refreshed boolean) LANGUAGE plpgsql AS $fn$
DECLARE t0 timestamptz; n int; x numeric; ms int; run finance.overpaid_snapshot_run;
BEGIN
    IF p_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RAISE EXCEPTION 'OVERPAID_SESSION: % is not a session on the academic calendar', coalesce(p_session, '(none)') USING ERRCODE = '23514',
            HINT = 'Choose a session of the academic calendar.';
    END IF;
    -- another refresh of the session is running: its answer stands
    IF NOT pg_try_advisory_xact_lock(hashtext('overpaid-snapshot:' || p_session)) THEN
        SELECT * INTO run FROM finance.overpaid_snapshot_run r WHERE r.session = p_session;
        RETURN QUERY SELECT coalesce(run.students, 0), coalesce(run.took_ms, 0), false;
        RETURN;
    END IF;
    t0 := clock_timestamp();
    DELETE FROM finance.overpaid_snapshot WHERE session = p_session;
    INSERT INTO finance.overpaid_snapshot (session, student_id, number, name, programme_code, dept_code, faculty_code, level, cohort_level, status,
                                           due, paid, excess, cause, bulk, repeat_amount, n_payments, payments, holds, refund_only, suggested)
    SELECT p_session, r.student_id, r.number, r.name, r.programme_code, r.dept_code, r.faculty_code, r.level, r.cohort_level, r.status,
           r.due, r.paid, r.excess, r.cause, r.bulk, r.repeat_amount, r.n_payments, r.payments, r.holds, r.refund_only, r.suggested
      FROM finance.overpaid_read(p_session) r;
    SELECT count(*) FILTER (WHERE s.excess >= 1), coalesce(sum(s.excess) FILTER (WHERE s.excess >= 1), 0) INTO n, x
      FROM finance.overpaid_snapshot s WHERE s.session = p_session;
    ms := greatest(round(extract(epoch FROM clock_timestamp() - t0) * 1000)::int, 0);
    INSERT INTO finance.overpaid_snapshot_run (session, refreshed_at, took_ms, students, excess) VALUES (p_session, now(), ms, n, x)
    ON CONFLICT (session) DO UPDATE SET refreshed_at = EXCLUDED.refreshed_at, took_ms = EXCLUDED.took_ms, students = EXCLUDED.students, excess = EXCLUDED.excess;
    RETURN QUERY SELECT n, ms, true;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_refresh(text) IS 'V781: works the session''s Overpaid school fees list out (finance.overpaid_read) and keeps it, with when and how long. Refused for a name that is not on the academic calendar (OVERPAID_SESSION); when another refresh of the session is running its answer stands (refreshed false).';

-- true when the kept list of a session was never worked out, is over an hour old, or a school-fees payment of the session was confirmed,
-- recorded by an old-fees upload or archived since: three index probes (fee-line, level, registration and bank-check changes are caught
-- by the hour, the desk's Refresh button, and for money by the live read of every decision)
-- The cut-off is read first and handed to the probes as a value, planned for that value on every call (EXECUTE ... USING): written as one
-- SQL statement over the run row's column, the planner cannot use the indexes and reads the whole payment table three times (120-240 ms on
-- the live-shaped copy's 264,000 payments; about 1 ms as written here).
CREATE FUNCTION finance.overpaid_refresh_due(p_session text) RETURNS boolean LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_at timestamptz; v_due boolean;
BEGIN
    SELECT run.refreshed_at INTO v_at FROM finance.overpaid_snapshot_run run WHERE run.session = p_session;
    IF v_at IS NULL OR v_at < now() - interval '60 minutes' THEN RETURN true; END IF;
    EXECUTE $q$SELECT EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.confirmed_at > $1 AND r.session = $2 AND r.purpose LIKE 'School fees%')
                   OR EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.channel = 'Legacy' AND r.generated_at > $1 AND r.session = $2 AND r.purpose LIKE 'School fees%')
                   OR EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.archived_at > $1 AND r.session = $2 AND r.purpose LIKE 'School fees%')$q$
       INTO v_due USING v_at, p_session;
    RETURN v_due;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_refresh_due(text) IS 'V781: whether the session''s kept list is to be worked out again: never worked out, over an hour old, or a school-fees payment of the session confirmed, recorded by an old-fees upload or archived since.';

-- the kept rows of a session with the state read live: what is decided (decisions, hand refunds), the request open, the refund's state
CREATE FUNCTION finance.overpaid_desk(p_session text, p_me uuid)
 RETURNS TABLE(session text, student_id uuid, number text, name text, programme_code text, dept_code text, faculty_code text, level integer,
               cohort_level integer, status text, due numeric, paid numeric, excess numeric, cause text, bulk boolean, repeat_amount numeric,
               n_payments integer, payments jsonb, holds text[], refund_only text, suggested text,
               decided numeric, refunded_by_hand numeric, remaining numeric, over_decided numeric, state text, decisions jsonb,
               request_id uuid, request_ref text, request_amount numeric, request_status text, request_batch text, request_by text,
               request_at timestamptz, request_mine boolean, request_skip text)
 LANGUAGE sql STABLE AS $fn$
    -- what is decided and requested is read for the whole session in one pass each (never student by student): the decisions that stand, the
    -- refunds raised by hand against the session's school-fees payments (finance.overpayment_decided's two parts), and the open requests
    WITH dz AS MATERIALIZED (
        SELECT d.student_id, sum(d.amount) AS decisions,
               jsonb_agg(jsonb_build_object('decision', d.decision, 'amount', d.amount, 'reference', d.reference, 'refund_state', rf.state,
                                            'to_session', d.to_session, 'decided_at', d.decided_at) ORDER BY d.decided_at DESC, d.id DESC) AS list,
               (array_agg(d.decision ORDER BY d.decided_at DESC, d.id DESC))[1] AS last_decision,
               (array_agg(rf.state ORDER BY d.decided_at DESC, d.id DESC))[1] AS last_refund
          FROM finance.overpayment_decision d LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
         WHERE d.session = p_session AND d.superseded_at IS NULL AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
         GROUP BY d.student_id),
    hr AS MATERIALIZED (
        SELECT r.student_id, sum(rf.amount) AS refunded
          FROM finance.refund rf JOIN finance.payment_reference r ON r.reference = rf.source_reference
         WHERE rf.state <> 'REJECTED' AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND NOT EXISTS (SELECT 1 FROM finance.overpayment_decision d2
                            WHERE d2.reference = rf.reference AND d2.decision = 'REFUND' AND d2.superseded_at IS NULL)
         GROUP BY r.student_id),
    rq AS MATERIALIZED (   -- at most one request is open for a student and session (the unique index ux_lcr_open)
        SELECT x.* FROM finance.legacy_credit_request x WHERE x.session = p_session AND x.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')),
    kept AS (
        SELECT n.*, coalesce(z.decisions, 0) AS decisions_sum, z.list, z.last_decision, z.last_refund,
               coalesce(z.decisions, 0) + coalesce(h.refunded, 0) AS decided_all, coalesce(h.refunded, 0) AS by_hand
          FROM finance.overpaid_snapshot n
          LEFT JOIN dz z ON z.student_id = n.student_id
          LEFT JOIN hr h ON h.student_id = n.student_id
         WHERE n.session = p_session)
    SELECT n.session, n.student_id, n.number, n.name, n.programme_code, n.dept_code, n.faculty_code, n.level, n.cohort_level, n.status,
           n.due, n.paid, n.excess, n.cause, n.bulk, n.repeat_amount, n.n_payments, n.payments, n.holds, n.refund_only, n.suggested,
           n.decided_all, n.by_hand, greatest(n.excess - n.decided_all, 0), od.over_decided,
           CASE WHEN od.over_decided >= 1 THEN 'OVER_DECIDED'
                WHEN q.status = 'PENDING_BURSAR_APPROVAL' THEN 'CREDIT_REQUESTED'
                WHEN q.id IS NOT NULL THEN 'CREDIT_RETURNED'
                WHEN n.excess - n.decided_all >= 1 THEN 'UNDECIDED'
                WHEN n.last_decision = 'WALLET' THEN 'CREDITED'
                WHEN n.last_decision = 'CARRY' THEN 'CARRIED'
                WHEN n.last_decision = 'REFUND' THEN CASE n.last_refund WHEN 'PAID' THEN 'REFUND_PAID' WHEN 'APPROVED' THEN 'REFUND_APPROVED' ELSE 'REFUND_RAISED' END
                ELSE 'REFUND_BY_HAND' END,
           n.list,
           q.id, q.ref, q.confirmed_amount, q.status, q.request_batch, helpdesk.person_name(q.initiated_by), q.initiated_at, q.initiated_by = p_me, q.last_skip_why
      FROM kept n
      CROSS JOIN LATERAL (SELECT CASE WHEN 'PAST_SESSION' = ANY (n.holds) OR n.decisions_sum - greatest(n.excess, 0) < 1 THEN 0::numeric
                                      ELSE n.decisions_sum - greatest(n.excess, 0) END AS over_decided) od
      LEFT JOIN rq q ON q.student_id = n.student_id
$fn$;
COMMENT ON FUNCTION finance.overpaid_desk(text, uuid) IS 'V781: the Overpaid school fees desk''s rows — the kept list of the session with the state read live at every read (never kept): OVER_DECIDED, CREDIT_REQUESTED, CREDIT_RETURNED, UNDECIDED (remaining NGN 1 or more), CREDITED, CARRIED, REFUND_RAISED, REFUND_APPROVED, REFUND_PAID, REFUND_BY_HAND. decided counts the decisions that stand and the refunds raised by hand; over_decided is what the standing decisions pass of what is now paid above the charge (never for a past session).';

-- the dashboard's and the desk's figures in one pass; every amount of an UNDECIDED row is its remaining
CREATE FUNCTION finance.overpaid_figures(p_session text, p_me uuid) RETURNS jsonb LANGUAGE sql STABLE AS $fn$
WITH d AS MATERIALIZED (SELECT x.* FROM finance.overpaid_desk(p_session, p_me) x),
run AS (SELECT r.* FROM finance.overpaid_snapshot_run r WHERE r.session = p_session),
rowsx AS MATERIALIZED (   -- one pass, the flags each figure reads
    SELECT d.student_id, d.cause, d.excess, d.remaining, d.over_decided, d.holds, d.bulk, d.refund_only, d.state,
           d.state = 'UNDECIDED' AS un, cardinality(d.holds) > 0 AS held
      FROM d),
causes AS (
    SELECT c.cause, c.ord,
           count(*) FILTER (WHERE r.cause = c.cause AND r.excess >= 1) AS students, coalesce(sum(r.excess) FILTER (WHERE r.cause = c.cause AND r.excess >= 1), 0) AS excess,
           count(*) FILTER (WHERE r.cause = c.cause AND r.un) AS undecided, coalesce(sum(r.remaining) FILTER (WHERE r.cause = c.cause AND r.un), 0) AS undecided_amount,
           count(*) FILTER (WHERE r.cause = c.cause AND r.un AND r.held) AS held, coalesce(sum(r.remaining) FILTER (WHERE r.cause = c.cause AND r.un AND r.held), 0) AS held_amount,
           count(*) FILTER (WHERE r.cause = c.cause AND r.un AND NOT r.held AND r.bulk) AS ready,
           coalesce(sum(r.remaining) FILTER (WHERE r.cause = c.cause AND r.un AND NOT r.held AND r.bulk), 0) AS ready_amount
      FROM (VALUES ('PORTAL_TWICE', 1), ('OLD_AND_PORTAL', 2), ('OLD_TWICE', 3), ('PART_PAYMENTS', 4), ('ABOVE_FEE_LINE', 5)) c(cause, ord)
      LEFT JOIN rowsx r ON true
     GROUP BY c.cause, c.ord),
pt AS (
    SELECT count(*) FILTER (WHERE r.un AND r.cause IN ('PORTAL_TWICE', 'OLD_AND_PORTAL', 'OLD_TWICE')) AS students,
           coalesce(sum(r.remaining) FILTER (WHERE r.un AND r.cause IN ('PORTAL_TWICE', 'OLD_AND_PORTAL', 'OLD_TWICE')), 0) AS amount,
           count(*) FILTER (WHERE r.un AND NOT r.held AND r.bulk) AS ready, coalesce(sum(r.remaining) FILTER (WHERE r.un AND NOT r.held AND r.bulk), 0) AS ready_amount,
           count(*) FILTER (WHERE r.un AND NOT r.held AND r.bulk AND r.refund_only IS NULL) AS wallet_ready,
           coalesce(sum(r.remaining) FILTER (WHERE r.un AND NOT r.held AND r.bulk AND r.refund_only IS NULL), 0) AS wallet_ready_amount,
           count(*) FILTER (WHERE r.un AND NOT r.held AND r.bulk AND r.refund_only IS NOT NULL) AS refund_only,
           coalesce(sum(r.remaining) FILTER (WHERE r.un AND NOT r.held AND r.bulk AND r.refund_only IS NOT NULL), 0) AS refund_only_amount
      FROM rowsx r),
ap AS (SELECT count(*) AS students, coalesce(sum(r.remaining), 0) AS amount FROM rowsx r WHERE r.un AND NOT r.held AND NOT r.bulk),
hd AS (SELECT count(*) AS students, coalesce(sum(r.remaining), 0) AS amount FROM rowsx r WHERE r.un AND r.held),
hr AS (SELECT coalesce(jsonb_object_agg(x.code, x.n), '{}'::jsonb) AS reasons
         FROM (SELECT h.code, count(*) AS n FROM rowsx r CROSS JOIN LATERAL unnest(r.holds) h(code) WHERE r.un GROUP BY h.code) x),
od AS (SELECT count(*) AS students, coalesce(sum(r.over_decided), 0) AS amount FROM rowsx r WHERE r.state = 'OVER_DECIDED'),
q AS MATERIALIZED (SELECT x.* FROM finance.legacy_credit_request x WHERE x.session = p_session AND x.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')),
rq AS (
    SELECT count(*) FILTER (WHERE x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL') AS pending,
           coalesce(sum(x.confirmed_amount) FILTER (WHERE x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL'), 0) AS pending_amount,
           count(*) FILTER (WHERE x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL' AND x.initiated_by IS DISTINCT FROM p_me) AS for_you,
           coalesce(sum(x.confirmed_amount) FILTER (WHERE x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL' AND x.initiated_by IS DISTINCT FROM p_me), 0) AS for_you_amount,
           count(*) FILTER (WHERE x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL' AND x.initiated_by = p_me) AS mine,
           coalesce(sum(x.confirmed_amount) FILTER (WHERE x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL' AND x.initiated_by = p_me), 0) AS mine_amount,
           count(*) FILTER (WHERE x.bulk AND x.status = 'RETURNED_FOR_CORRECTION') AS returned,
           count(*) FILTER (WHERE x.bulk AND x.status = 'RETURNED_FOR_CORRECTION' AND x.initiated_by = p_me) AS returned_mine,
           count(*) FILTER (WHERE NOT x.bulk AND x.status = 'PENDING_BURSAR_APPROVAL') AS single
      FROM q x),
bt AS (
    SELECT jsonb_agg(jsonb_build_object('batch', b.request_batch, 'cause', b.cause, 'requestedBy', b.who, 'requestedAt', b.req_at, 'count', b.n, 'amount', b.amount,
                                        'pending', b.pending, 'returned', b.returned, 'skipped', b.skipped, 'mine', b.mine) ORDER BY b.req_at DESC, b.request_batch DESC) AS batches
      FROM (SELECT * FROM (
              SELECT x.request_batch, CASE WHEN count(DISTINCT x.cause) = 1 THEN min(x.cause) ELSE 'MIXED' END AS cause,
                     helpdesk.person_name((array_agg(x.initiated_by ORDER BY x.initiated_at))[1]) AS who, min(x.initiated_at) AS req_at, count(*) AS n, sum(x.confirmed_amount) AS amount,
                     count(*) FILTER (WHERE x.status = 'PENDING_BURSAR_APPROVAL') AS pending, count(*) FILTER (WHERE x.status = 'RETURNED_FOR_CORRECTION') AS returned,
                     count(*) FILTER (WHERE x.status = 'PENDING_BURSAR_APPROVAL' AND x.last_skip_at IS NOT NULL) AS skipped,
                     bool_or(x.initiated_by = p_me) AS mine
                FROM q x WHERE x.bulk GROUP BY x.request_batch) y
             ORDER BY y.req_at DESC, y.request_batch DESC LIMIT 50) b),
wl AS MATERIALIZED (   -- the standing WALLET decisions of the session, and what their students' wallets hold of overpaid money
    SELECT x.student_id, sum(x.amount) AS amount FROM finance.overpayment_decision x
     WHERE x.session = p_session AND x.superseded_at IS NULL AND x.decision = 'WALLET' GROUP BY x.student_id),
wm AS (
    SELECT coalesce(sum(s.applied), 0) AS applied, coalesce(sum(greatest(s.credit - s.applied - s.refund - s.reversed, 0)), 0) AS in_wallets
      FROM (SELECT w.student_id,
                   coalesce(sum(e.amount) FILTER (WHERE e.kind IN ('CREDIT', 'TOPUP')), 0) AS credit, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'APPLIED'), 0) AS applied,
                   coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REFUND'), 0) AS refund, coalesce(sum(e.amount) FILTER (WHERE e.kind = 'REVERSED'), 0) AS reversed
              FROM wl w JOIN finance.wallet_entry e ON e.student_id = w.student_id AND e.source_code = 'OVERPAID'
             GROUP BY w.student_id) s),
rf AS (
    SELECT count(*) FILTER (WHERE r.state = 'PROPOSED') AS raised, coalesce(sum(r.amount) FILTER (WHERE r.state = 'PROPOSED'), 0) AS raised_amount,
           count(*) FILTER (WHERE r.state = 'APPROVED') AS approved, coalesce(sum(r.amount) FILTER (WHERE r.state = 'APPROVED'), 0) AS approved_amount,
           count(*) FILTER (WHERE r.state = 'PAID') AS paid, coalesce(sum(r.amount) FILTER (WHERE r.state = 'PAID'), 0) AS paid_amount
      FROM finance.overpayment_decision x JOIN finance.refund r ON r.reference = x.reference
     WHERE x.session = p_session AND x.superseded_at IS NULL AND x.decision = 'REFUND' AND r.state <> 'REJECTED'),
hh AS (
    SELECT count(*) AS n, coalesce(sum(r.amount), 0) AS amount
      FROM finance.refund r JOIN finance.payment_reference p ON p.reference = r.source_reference
     WHERE r.state <> 'REJECTED' AND p.session = p_session AND p.confirmed_at IS NOT NULL AND p.archived_at IS NULL AND p.purpose LIKE 'School fees%'
       AND NOT EXISTS (SELECT 1 FROM finance.overpayment_decision x WHERE x.reference = r.reference AND x.decision = 'REFUND' AND x.superseded_at IS NULL)),
cy AS (SELECT count(DISTINCT x.student_id) AS students, coalesce(sum(x.amount), 0) AS amount FROM finance.overpayment_decision x
        WHERE x.session = p_session AND x.superseded_at IS NULL AND x.decision = 'CARRY')
SELECT jsonb_build_object(
    'session', p_session,
    'sessions', coalesce((SELECT jsonb_agg(s.session ORDER BY s.session DESC) FROM (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.ended_at IS NULL) s), '[]'::jsonb),
    'nextSession', finance.next_session(p_session),
    'computed', EXISTS (SELECT 1 FROM run), 'refreshedAt', (SELECT r.refreshed_at FROM run r), 'tookMs', (SELECT r.took_ms FROM run r),
    'students', (SELECT count(*) FROM rowsx r WHERE r.excess >= 1), 'excess', (SELECT coalesce(sum(r.excess), 0) FROM rowsx r WHERE r.excess >= 1),
    'causes', (SELECT jsonb_agg(jsonb_build_object('cause', c.cause, 'students', c.students, 'excess', c.excess, 'undecided', c.undecided, 'undecidedAmount', c.undecided_amount,
                                                   'held', c.held, 'heldAmount', c.held_amount, 'ready', c.ready, 'readyAmount', c.ready_amount) ORDER BY c.ord) FROM causes c),
    'paidTwice', (SELECT jsonb_build_object('students', p.students, 'amount', p.amount, 'ready', p.ready, 'readyAmount', p.ready_amount,
                                            'walletReady', p.wallet_ready, 'walletReadyAmount', p.wallet_ready_amount, 'refundOnly', p.refund_only, 'refundOnlyAmount', p.refund_only_amount) FROM pt p),
    'apart', (SELECT jsonb_build_object('students', a.students, 'amount', a.amount) FROM ap a),
    'held', (SELECT jsonb_build_object('students', h.students, 'amount', h.amount, 'reasons', (SELECT hr.reasons FROM hr)) FROM hd h),
    'overDecided', (SELECT jsonb_build_object('students', o.students, 'amount', o.amount) FROM od o),
    'requests', (SELECT jsonb_build_object('pending', r.pending, 'pendingAmount', r.pending_amount, 'forYou', r.for_you, 'forYouAmount', r.for_you_amount,
                                           'mine', r.mine, 'mineAmount', r.mine_amount, 'returned', r.returned, 'returnedMine', r.returned_mine, 'single', r.single,
                                           'batches', coalesce((SELECT b.batches FROM bt b), '[]'::jsonb)) FROM rq r),
    'credited', jsonb_build_object('students', (SELECT count(*) FROM wl), 'amount', (SELECT coalesce(sum(w.amount), 0) FROM wl w),
                                   'applied', (SELECT m.applied FROM wm m), 'inWallets', (SELECT m.in_wallets FROM wm m)),
    'refunds', (SELECT jsonb_build_object('raised', r.raised, 'raisedAmount', r.raised_amount, 'approved', r.approved, 'approvedAmount', r.approved_amount,
                                          'paid', r.paid, 'paidAmount', r.paid_amount, 'byHand', (SELECT h.n FROM hh h), 'byHandAmount', (SELECT h.amount FROM hh h)) FROM rf r),
    'carried', (SELECT jsonb_build_object('students', c.students, 'amount', c.amount) FROM cy c))
$fn$;
COMMENT ON FUNCTION finance.overpaid_figures(text, uuid) IS 'V781: the dashboard panel''s and the desk''s figures for a session in one pass over finance.overpaid_desk, plus the session''s requests, credits, refunds and carries: by cause, paid twice (ready, wallet-ready, refund-only), apart, held (with the reasons), decided above the excess, the requests (waiting for the caller, the caller''s own, returned, single, by batch), credited (applied, still in wallets), refunds, carried.';

-- ── 9 · the trigger functions (the triggers themselves are created last) ──
-- a decision never takes the decided money above the excess its own row records
CREATE FUNCTION finance.overpayment_decision_within_excess() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_decided numeric;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('overpay:' || NEW.student_id::text || ':' || NEW.session));
    -- the refund this row names is not counted twice (it is already a refund raised against the payment)
    v_decided := finance.overpayment_decided(NEW.student_id, NEW.session, NEW.reference);
    IF v_decided + NEW.amount > NEW.paid - NEW.due + 0.005 THEN
        RAISE EXCEPTION 'OVERPAY_ABOVE_EXCESS: NGN % is already decided of the NGN % paid above the fees of %; NGN % more would pass it',
            to_char(v_decided, 'FM999,999,999,990.00'), to_char(NEW.paid - NEW.due, 'FM999,999,999,990.00'), NEW.session, to_char(NEW.amount, 'FM999,999,999,990.00')
            USING ERRCODE = '23514', HINT = 'An overpayment is settled once: decide only the amount above what is already decided.';
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION finance.overpayment_decision_within_excess() IS 'V781: refuses a decision that would take the decided money (the decisions that stand and the refunds raised by hand) above the amount paid above the charge that its own row records, under the student''s lock.';

-- an OVERPAID credit exists only with its approved request, whatever wrote it (checked at commit)
CREATE FUNCTION finance.overpaid_credit_by_request() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.wallet_entry_id = NEW.id AND q.status = 'CREDITED') THEN
        RAISE EXCEPTION 'WALLET_OVERPAID_ROUTE: overpaid school fees reach a wallet only through a credit request approved by a second Bursary officer' USING ERRCODE = '23514',
            HINT = 'Request the credit on the Overpaid school fees desk; a hand credit is for money that arrived from a source.';
    END IF;
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_credit_by_request() IS 'V781: at commit, a credit of source OVERPAID on a wallet has the credit request that was approved for it.';

-- ── 10 · finance.decide_overpayments restated: carry or refund the exact paid-twice rows, one student a call for the rest ──
-- V670's body with one read and one loop: every hold stops every decision, a row that is not "bulk" is decided one student at a time with
-- the officer's confirmation that the fee setup was checked, both witnesses agree on the amount, and a student with a further payment is
-- decided again for the amount above what is decided.
DROP FUNCTION finance.decide_overpayments(text, text, uuid[], text, integer);
CREATE FUNCTION finance.decide_overpayments(p_session text, p_decision text, p_students uuid[], p_reason text, p_limit integer DEFAULT 2000,
                                            p_cause text DEFAULT NULL, p_fee_setup_checked boolean DEFAULT false)
 RETURNS TABLE(carried integer, refunds integer, held integer, remaining integer, apart integer, requested integer, uncertain integer,
               refund_only integer, unchecked integer)
 LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, '')); v_decision text := upper(btrim(coalesce(p_decision, '')));
        v_next text; o record; pos record; v_ref text; v_src text; v_journal uuid; v_rf text; v_id uuid; v_amount numeric; v_one boolean; v_students uuid[];
        nc int := 0; nr int := 0; nh int := 0; v_left int := 0; na int := 0; nq int := 0; nu int := 0; nro int := 0; nfs int := 0;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'OVERPAY_ACTOR: an overpayment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF v_decision NOT IN ('CARRY', 'REFUND') THEN
        RAISE EXCEPTION 'OVERPAY_DECISION: an overpayment is carried into the next session (CARRY) or refunded (REFUND)' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'OVERPAY_REASON: say why (at least ten characters); it is kept with each decision' USING ERRCODE = '23514';
    END IF;
    IF p_cause IS NOT NULL AND p_cause NOT IN ('PORTAL_TWICE', 'OLD_AND_PORTAL', 'OLD_TWICE', 'PART_PAYMENTS', 'ABOVE_FEE_LINE') THEN
        RAISE EXCEPTION 'OVERPAY_CAUSE: % is not a cause of an overpayment', p_cause USING ERRCODE = '23514';
    END IF;
    IF v_decision = 'CARRY' THEN
        v_next := finance.next_session(p_session);
        IF v_next IS NULL THEN
            RAISE EXCEPTION 'OVERPAY_NO_NEXT_SESSION: no session follows % on the calendar to carry the excess into', p_session USING ERRCODE = '23514',
                HINT = 'Add the next session on the academic calendar, or refund the excess instead.';
        END IF;
    END IF;
    v_students := CASE WHEN coalesce(array_length(p_students, 1), 0) = 0 THEN NULL ELSE p_students END;   -- no one named is every student
    v_one := coalesce(array_length(v_students, 1), 0) = 1;
    FOR o IN SELECT x.* FROM finance.overpaid_read(p_session, v_students) x
              WHERE x.remaining >= 1 AND x.cause IS NOT NULL AND (p_cause IS NULL OR x.cause = p_cause) ORDER BY x.student_id LOOP
        IF cardinality(o.holds) > 0 THEN nh := nh + 1; CONTINUE; END IF;                                  -- every hold, not only the bank check
        IF v_decision = 'CARRY' AND o.refund_only IS NOT NULL THEN nro := nro + 1; CONTINUE; END IF;    -- nothing is charged to carry into
        IF NOT o.bulk THEN
            IF NOT v_one THEN na := na + 1; CONTINUE; END IF;                                              -- never in bulk unless bulk
            IF NOT coalesce(p_fee_setup_checked, false) THEN nfs := nfs + 1; CONTINUE; END IF;            -- deliberately, one student a call
        END IF;
        IF nc + nr >= greatest(1, coalesce(p_limit, 2000)) THEN v_left := v_left + 1; CONTINUE; END IF;   -- before any lock is taken
        PERFORM pg_advisory_xact_lock(hashtext('overpay:' || o.student_id::text || ':' || p_session));
        IF EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.student_id = o.student_id AND q.session = p_session
                      AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')) THEN nq := nq + 1; CONTINUE; END IF;
        -- a refund the desk rejected leaves its amount to be decided again: only that row is superseded
        UPDATE finance.overpayment_decision d SET superseded_at = now()
         WHERE d.student_id = o.student_id AND d.session = p_session AND d.superseded_at IS NULL AND d.decision = 'REFUND'
           AND EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = d.reference AND rf.state = 'REJECTED');
        -- the second witness, under the lock: the student's own fee account
        SELECT * INTO pos FROM finance.position(o.student_id, p_session);
        v_amount := pos.paid - pos.due - finance.overpayment_decided(o.student_id, p_session);
        IF pos.due <= 0 OR abs((pos.paid - pos.due) - o.excess) >= 1 OR v_amount < 1 THEN nu := nu + 1; CONTINUE; END IF;
        IF v_decision = 'CARRY' THEN
            v_ref := 'MOAUM-CF-' || regexp_replace(upper(o.number), '[^0-9A-Z]', '', 'g') || '-' || replace(p_session, '/', '-');
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref OR receipt_no = 'RCT-' || v_ref) THEN
                v_ref := v_ref || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
            END IF;
            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                   channel, note, receipt_no)
            VALUES (o.student_id, v_next, v_ref, 'School fees ' || v_next || ' (carried from ' || p_session || ')', v_amount, now(), now(), now(), v_actor,
                    'CARRIED', 'Overpaid on ' || p_session || ' (paid ' || to_char(pos.paid, 'FM999,999,999,990.00') || ', due ' || to_char(pos.due, 'FM999,999,999,990.00')
                               || '), carried into ' || v_next || ': ' || v_reason, 'RCT-' || v_ref);
            -- no new money: the school-fees income moves from the overpaid session to the next
            v_journal := finance.gl_post(current_date, 'School fees overpaid on ' || p_session || ' carried into ' || v_next || ' — ' || v_ref,
                                         'AUTO', 'PAYMENT', v_ref,
                jsonb_build_array(
                    jsonb_build_object('account', finance.gl_income_account('School fees'), 'debit', v_amount,
                                       'narration', 'Overpaid on ' || p_session || ', carried into ' || v_next, 'session', p_session),
                    jsonb_build_object('account', finance.gl_income_account('School fees'), 'credit', v_amount,
                                       'narration', 'Carried from ' || p_session, 'session', v_next)));
            INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, to_session, reference, journal, decided_by, reason, fee_setup_checked)
            VALUES (o.student_id, p_session, pos.due, pos.paid, v_amount, 'CARRY', v_next, v_ref, v_journal, v_actor, v_reason, NOT o.bulk)
            RETURNING id INTO v_id;
            -- V519: the student told
            PERFORM platform.tell_student(o.student_id, 'OVERPAYMENT_CARRIED', NULL,
                jsonb_build_object('SESSION_FROM', p_session, 'SESSION_TO', v_next, 'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,990.00'), 'REFERENCE', v_ref),
                'overpayment-carried:' || v_id);
            nc := nc + 1;
        ELSE
            -- against the latest school-fees payment of the session that covers the amount, when one does
            v_src := (SELECT r.reference FROM finance.payment_reference r
                       WHERE r.student_id = o.student_id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
                         AND r.amount - coalesce((SELECT sum(f.amount) FROM finance.refund f WHERE f.source_reference = r.reference AND f.state <> 'REJECTED'), 0) >= v_amount
                       ORDER BY r.confirmed_at DESC, r.reference LIMIT 1);
            v_rf := finance.propose_refund(o.student_id, o.name,
                        'School fees overpaid on ' || p_session || ' (paid ' || to_char(pos.paid, 'FM999,999,999,990.00') || ', due '
                        || to_char(pos.due, 'FM999,999,999,990.00') || '): ' || v_reason, v_amount, NULL, NULL, NULL, v_src);
            INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, reference, decided_by, reason, fee_setup_checked)
            VALUES (o.student_id, p_session, pos.due, pos.paid, v_amount, 'REFUND', v_rf, v_actor, v_reason, NOT o.bulk);
            -- V519: the student told
            PERFORM platform.tell_student(o.student_id, 'OVERPAYMENT_REFUND_RAISED', NULL,
                jsonb_build_object('SESSION_FROM', p_session, 'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,990.00'), 'REFUND', v_rf),
                'overpayment-refund:' || v_rf);
            nr := nr + 1;
        END IF;
    END LOOP;
    RETURN QUERY SELECT nc, nr, nh, v_left, na, nq, nu, nro, nfs;
END $fn$;
COMMENT ON FUNCTION finance.decide_overpayments(text, text, uuid[], text, integer, text, boolean) IS 'V506, V670, V781: carries the excess into the next session (CARRY) or raises a refund (REFUND) for the students of a session. Only an exact repeated payment (bulk) is decided many at a time; every other row is decided one student a call with p_fee_setup_checked; every hold stops every decision; a student refused a wallet (graduated, withdrawn, deceased, award approved) is never carried; both witnesses (the list and the student''s own position, under the lock) must agree on the excess within NGN 1; the amount is what remains after what is already decided. Counts: carried, refunds, held, remaining (decidable beyond the limit), apart (not bulk, in bulk), requested (a credit request is open), uncertain, refund_only (not carried), unchecked (the confirmation missing).';


-- ── 11 · the wallet route: Legacy Financial Reconciliation's functions restated on the one list ──
-- Each of V625's functions below is restated from its text with only what the spec of this migration changes: the excess read from
-- finance.overpaid_read (the cause, the holds, what remains), "settled" is "nothing remains" (a student paid again is requested again),
-- every hold and a student refused a wallet are refused, a row that is not a repeated payment making up the excess exactly needs the
-- officer's confirmation that the fee setup was checked, and the student's own position agrees (the second witness).
DROP FUNCTION finance.legacy_credit_excess(uuid, text);
CREATE FUNCTION finance.legacy_credit_excess(p_student uuid, p_session text)
 RETURNS TABLE(due numeric, paid numeric, excess numeric, decision text, decision_reference text, held boolean, remaining numeric, decided numeric,
               holds text[], refund_only text, cause text, bulk boolean, listed boolean)
 LANGUAGE sql STABLE AS $fn$
    SELECT r.due, r.paid, r.excess, d.decision, d.reference, cardinality(r.holds) > 0, r.remaining, r.decided, r.holds, r.refund_only, r.cause, r.bulk,
           r.student_id IS NOT NULL
      FROM (SELECT 1) one
      LEFT JOIN LATERAL (SELECT x.* FROM finance.overpaid_read(p_session, ARRAY[p_student]) x WHERE x.cause IS NOT NULL) r ON true
      LEFT JOIN LATERAL (SELECT s.decision, s.reference FROM finance.overpayment_settled(p_student, p_session) s ORDER BY s.decided_at DESC LIMIT 1) d ON r.student_id IS NOT NULL
$fn$;
COMMENT ON FUNCTION finance.legacy_credit_excess(uuid, text) IS 'V625, V781: the overpayment of one student on one session as the Overpaid school fees list reads it — one row always: due, paid, the whole excess, the latest decision that stands, what remains undecided, what is decided, the holds, refund_only, the cause and bulk; listed is false (every other column NULL) when the list has no row with a cause for the student.';

DROP FUNCTION finance.legacy_credit_initiate(uuid, text, numeric, text, text, text);
CREATE FUNCTION finance.legacy_credit_initiate(p_student uuid, p_session text, p_amount numeric, p_reason text, p_evidence text, p_adjust_reason text,
                                               p_fee_setup_checked boolean DEFAULT false)
 RETURNS finance.legacy_credit_request
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; x record; r finance.legacy_credit_request; v_amount numeric; v_ref text; p uuid; pos record;
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
    IF NOT coalesce(x.listed, false) OR x.excess < 1 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_NOT_OVERPAID: the student has not paid above the fees stated for %; an outstanding fee is what the student owes the University, never money for the wallet', p_session USING ERRCODE = '23514',
            HINT = 'A credit is requested only on a session the reconciliation shows as overpaid.';
    END IF;
    IF x.remaining < 1 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_SETTLED: the overpayment on % is already decided (%, %)', p_session, coalesce(lower(x.decision), 'refunded by hand'), coalesce(x.decision_reference, 'see Refunds & Credits') USING ERRCODE = '23514';
    END IF;
    IF 'BANK_CHECK' = ANY (x.holds) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: the Bursary is checking with the bank whether the student''s school fees were charged twice (V561); the credit waits for the verdict' USING ERRCODE = '23514';
    END IF;
    IF cardinality(x.holds) > 0 THEN
        RAISE EXCEPTION 'OVERPAID_HELD: the excess on % cannot be decided yet (%)', p_session, finance.overpaid_hold_words(x.holds) USING ERRCODE = '23514',
            HINT = 'The Overpaid school fees desk says what each one waits for.';
    END IF;
    IF x.refund_only IS NOT NULL THEN
        RAISE EXCEPTION 'OVERPAID_WALLET_REFUSED: the student is %; the excess is refunded, not credited to a wallet', finance.overpaid_refund_only_word(x.refund_only) USING ERRCODE = '23514',
            HINT = 'Raise a refund on the Overpaid school fees desk.';
    END IF;
    IF NOT x.bulk AND NOT coalesce(p_fee_setup_checked, false) THEN
        RAISE EXCEPTION 'OVERPAID_FEE_SETUP_CHECK: this excess is not a repeated payment that makes it up exactly; confirm that the fee setup and the payments were checked before it is credited' USING ERRCODE = '23514',
            HINT = 'Open Fee Setup for the student''s programme and level, look at the payments, then tick the confirmation.';
    END IF;
    -- the second witness: the student's own fee account, under the lock
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due <= 0 OR abs((pos.paid - pos.due) - x.excess) >= 1 THEN
        RAISE EXCEPTION 'OVERPAID_EXCESS_UNCERTAIN: the student''s own fee account reads NGN % paid above the charge, not the NGN % listed',
            to_char(pos.paid - pos.due, 'FM999,999,999,990.00'), to_char(x.excess, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    v_amount := coalesce(p_amount, x.remaining);
    IF v_amount < 1 OR v_amount > x.remaining THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_AMOUNT: the amount to credit is between NGN 1 and the excess paid, NGN %', to_char(x.remaining, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    IF v_amount <> x.remaining AND length(btrim(coalesce(p_adjust_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_ADJUSTMENT_REASON: the amount differs from the excess the records show (NGN %); say why, in ten characters or more', to_char(x.remaining, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    v_ref := 'LOR/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.legacy_credit_request_seq')::text, 6, '0');
    INSERT INTO finance.legacy_credit_request (ref, student_id, session, due, paid, legacy_amount, confirmed_amount, adjustment_reason, reason, evidence, initiated_by, initiated_office,
                                               cause, fee_setup_checked)
    VALUES (v_ref, p_student, p_session, pos.due, pos.paid, x.remaining, v_amount, CASE WHEN v_amount <> x.remaining THEN btrim(p_adjust_reason) END, btrim(p_reason), btrim(p_evidence), who, office,
            x.cause, NOT x.bulk)
    RETURNING * INTO r;
    -- the Bursar told a request waits
    FOR p IN SELECT * FROM finance.bursar_holders() LOOP
        BEGIN
            PERFORM platform.tell_person(p, 'LEGACY_CREDIT_WAITING', NULL,
                jsonb_build_object('REF', r.ref, 'STUDENT', s.surname || ', ' || s.other_names, 'NUMBER', coalesce(s.matric_no, s.admission_no), 'SESSION', p_session,
                                   'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                'legacy-credit:' || r.ref || ':waiting:' || p::text);
        EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;
                  WHEN OTHERS THEN
            RAISE NOTICE 'legacy credit %: the Bursar could not be told (%)', r.ref, SQLERRM;
        END;
    END LOOP;
    RETURN r;
END $function$;
COMMENT ON FUNCTION finance.legacy_credit_initiate(uuid, text, numeric, text, text, text, boolean) IS 'V625, V781: the Students Account Officer (or the Bursar) confirms a student''s overpayment on a session and initiates the wallet credit — the amount never above what remains undecided (a different amount names its reason and is marked adjusted), the evidence and the reason named; refused where the student owes or nothing remains, where any hold stands, where the student is graduated, withdrawn or has left (the excess is refunded), where the excess is not a repeated payment that makes it up exactly and the fee setup was not confirmed checked, where the student''s own fee account reads another excess, or where a request already stands. Nothing is credited here; the Bursar is told.';

DROP FUNCTION finance.legacy_credit_resubmit(uuid, numeric, text, text, text);
CREATE FUNCTION finance.legacy_credit_resubmit(p_id uuid, p_amount numeric, p_reason text, p_evidence text, p_adjust_reason text, p_fee_setup_checked boolean DEFAULT NULL)
 RETURNS finance.legacy_credit_request
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.legacy_credit_request; x record; v_amount numeric; s people.student; p uuid; pos record;
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
    IF NOT coalesce(x.listed, false) OR x.excess < 1 THEN RAISE EXCEPTION 'LEGACY_CREDIT_NOT_OVERPAID: the records no longer show an overpayment on %; withdraw the request', r.session USING ERRCODE = '23514'; END IF;
    IF x.remaining < 1 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_SETTLED: the overpayment on % is already decided (%, %)', r.session, coalesce(lower(x.decision), 'refunded by hand'), coalesce(x.decision_reference, 'see Refunds & Credits') USING ERRCODE = '23514';
    END IF;
    IF 'BANK_CHECK' = ANY (x.holds) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: the Bursary is checking with the bank whether the student''s school fees were charged twice (V561); the credit waits for the verdict' USING ERRCODE = '23514';
    END IF;
    IF cardinality(x.holds) > 0 THEN
        RAISE EXCEPTION 'OVERPAID_HELD: the excess on % cannot be decided yet (%)', r.session, finance.overpaid_hold_words(x.holds) USING ERRCODE = '23514',
            HINT = 'The Overpaid school fees desk says what each one waits for.';
    END IF;
    IF x.refund_only IS NOT NULL THEN
        RAISE EXCEPTION 'OVERPAID_WALLET_REFUSED: the student is %; the excess is refunded, not credited to a wallet', finance.overpaid_refund_only_word(x.refund_only) USING ERRCODE = '23514',
            HINT = 'Raise a refund on the Overpaid school fees desk.';
    END IF;
    IF NOT x.bulk AND NOT coalesce(p_fee_setup_checked, r.fee_setup_checked, false) THEN
        RAISE EXCEPTION 'OVERPAID_FEE_SETUP_CHECK: this excess is not a repeated payment that makes it up exactly; confirm that the fee setup and the payments were checked before it is credited' USING ERRCODE = '23514',
            HINT = 'Open Fee Setup for the student''s programme and level, look at the payments, then tick the confirmation.';
    END IF;
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    IF pos.due <= 0 OR abs((pos.paid - pos.due) - x.excess) >= 1 THEN
        RAISE EXCEPTION 'OVERPAID_EXCESS_UNCERTAIN: the student''s own fee account reads NGN % paid above the charge, not the NGN % listed',
            to_char(pos.paid - pos.due, 'FM999,999,999,990.00'), to_char(x.excess, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    v_amount := coalesce(p_amount, x.remaining);
    IF v_amount < 1 OR v_amount > x.remaining THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_AMOUNT: the amount to credit is between NGN 1 and the excess paid, NGN %', to_char(x.remaining, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    IF v_amount <> x.remaining AND length(btrim(coalesce(p_adjust_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_ADJUSTMENT_REASON: the amount differs from the excess the records show (NGN %); say why, in ten characters or more', to_char(x.remaining, 'FM999,999,999,990.00') USING ERRCODE = '23514';
    END IF;
    UPDATE finance.legacy_credit_request
       SET due = pos.due, paid = pos.paid, legacy_amount = x.remaining, confirmed_amount = v_amount, adjustment_reason = CASE WHEN v_amount <> x.remaining THEN btrim(p_adjust_reason) END,
           reason = btrim(p_reason), evidence = btrim(p_evidence), status = 'PENDING_BURSAR_APPROVAL', resubmitted_at = now(), resubmissions = resubmissions + 1,
           decided_by = NULL, decided_office = NULL, decided_at = NULL, cause = x.cause,
           fee_setup_checked = NOT x.bulk AND coalesce(p_fee_setup_checked, r.fee_setup_checked, false),
           last_skip_at = NULL, last_skip_code = NULL, last_skip_why = NULL
     WHERE id = p_id RETURNING * INTO r;
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    FOR p IN SELECT * FROM finance.bursar_holders() LOOP
        BEGIN
            PERFORM platform.tell_person(p, 'LEGACY_CREDIT_WAITING', NULL,
                jsonb_build_object('REF', r.ref, 'STUDENT', s.surname || ', ' || s.other_names, 'NUMBER', coalesce(s.matric_no, s.admission_no), 'SESSION', r.session,
                                   'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,999,990.00'), 'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                'legacy-credit:' || r.ref || ':waiting:' || r.resubmissions || ':' || p::text);
        EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;
                  WHEN OTHERS THEN
            RAISE NOTICE 'legacy credit %: the Bursar could not be told (%)', r.ref, SQLERRM;
        END;
    END LOOP;
    RETURN r;
END $function$;
COMMENT ON FUNCTION finance.legacy_credit_resubmit(uuid, numeric, text, text, text, boolean) IS 'V625, V781: a request the Bursar returned for correction, corrected and sent again — the excess read afresh, the same rules as the first submission (holds, a student refused a wallet, the fee-setup confirmation — NULL keeps what the request holds — and the second witness); the decision note stays on the record and what an approval pass left on it is cleared.';

-- ── 12 · the requests, read by id, student or batch, page by page ──
DROP FUNCTION finance.legacy_credit_rows(text, text, text, text, text, integer);
CREATE FUNCTION finance.legacy_credit_rows(p_status text, p_session text, p_q text, p_fac text, p_dept text, p_limit integer DEFAULT 500,
                                           p_id uuid DEFAULT NULL, p_student uuid DEFAULT NULL, p_batch text DEFAULT NULL, p_bulk boolean DEFAULT NULL, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, ref text, student_id uuid, student text, matric_no text, jamb_reg_no text, admission_no text, programme_code text, programme text, dept_code text,
               department text, faculty_code text, faculty text, session text, kind text, due numeric, paid numeric, legacy_amount numeric, confirmed_amount numeric,
               adjusted boolean, adjustment_reason text, reason text, evidence text, status text, initiated_by text, initiated_office text, initiated_at timestamptz,
               resubmitted_at timestamptz, resubmissions integer, decided_by text, decided_office text, decided_at timestamptz, decision_note text, withdrawn_by text,
               withdrawn_at timestamptz, withdraw_reason text, wallet_reference text, credited_at timestamptz, balance_after numeric,
               cause text, bulk boolean, request_batch text, credit_batch text, fee_setup_checked boolean, initiated_by_id uuid, last_skip_code text, last_skip_why text)
 LANGUAGE sql STABLE
AS $function$
    SELECT q.id, q.ref, q.student_id, s.surname || ', ' || s.other_names, s.matric_no, s.jamb_reg_no, s.admission_no, s.programme_code, p.name, p.dept_code, d.name, p.faculty_code, f.name,
           q.session, q.kind, q.due, q.paid, q.legacy_amount, q.confirmed_amount, q.adjusted, q.adjustment_reason, q.reason, q.evidence, q.status,
           helpdesk.person_name(q.initiated_by), q.initiated_office, q.initiated_at, q.resubmitted_at, q.resubmissions,
           helpdesk.person_name(q.decided_by), q.decided_office, q.decided_at, q.decision_note, helpdesk.person_name(q.withdrawn_by), q.withdrawn_at, q.withdraw_reason,
           e.reference, e.at,
           CASE WHEN e.id IS NULL THEN NULL ELSE (SELECT coalesce(sum(CASE WHEN w.kind IN ('CREDIT', 'TOPUP') THEN w.amount ELSE -w.amount END), 0)
                                                      FROM finance.wallet_entry w WHERE w.student_id = q.student_id AND (w.at, w.id) <= (e.at, e.id)) END,
           q.cause, q.bulk, q.request_batch, q.credit_batch, q.fee_setup_checked, q.initiated_by, q.last_skip_code, q.last_skip_why
      FROM finance.legacy_credit_request q
      JOIN people.student s ON s.id = q.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN finance.wallet_entry e ON e.id = q.wallet_entry_id
     WHERE (p_status IS NULL OR q.status = p_status)
       AND (p_session IS NULL OR q.session = p_session)
       AND (p_id IS NULL OR q.id = p_id) AND (p_student IS NULL OR q.student_id = p_student)
       AND (p_batch IS NULL OR q.request_batch = p_batch) AND (p_bulk IS NULL OR q.bulk = p_bulk)
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept)
       AND (p_q IS NULL OR s.matric_no ILIKE '%' || p_q || '%' OR s.jamb_reg_no ILIKE '%' || p_q || '%' OR s.admission_no ILIKE '%' || p_q || '%'
            OR (s.surname || ' ' || s.other_names) ILIKE '%' || p_q || '%' OR q.ref ILIKE '%' || p_q || '%')
     ORDER BY CASE q.status WHEN 'PENDING_BURSAR_APPROVAL' THEN 0 WHEN 'RETURNED_FOR_CORRECTION' THEN 1 WHEN 'CREDITED' THEN 2 ELSE 3 END, q.initiated_at DESC, q.id
     LIMIT greatest(1, least(coalesce(p_limit, 500), 5000)) OFFSET greatest(coalesce(p_offset, 0), 0)
$function$;
COMMENT ON FUNCTION finance.legacy_credit_rows(text, text, text, text, text, integer, uuid, uuid, text, boolean, integer) IS 'V625, V781: the credit requests with the student, the officers and the wallet entry — newest waiting first, at most 5,000 — read by status, session, search, faculty and department, and by id, by student, by request batch, by where it was made (bulk: the Overpaid school fees desk or Legacy Financial Reconciliation), and page by page (p_offset). The eight columns last: the cause, bulk, the batches, the fee-setup confirmation, the initiator''s id and what an approval pass left on the request.';


-- ── 13 · the one place a credit is posted ──
-- Returns NULL when the request was credited, else 'CODE: words' for everything about the request that stops it (the caller of one request
-- raises the words, the approval pass marks the request with them and goes on); a caller that may not decide, or a request that does not
-- exist, raises. p_listed, p_excess and p_holds are the student's row in the caller's live read of the session. It does not apply the
-- money to fees: the credit stays on the wallet until the student applies it (finance.apply_wallet) or asks for it as a refund.
CREATE FUNCTION finance.overpaid_credit_post(p_id uuid, p_listed boolean, p_excess numeric, p_holds text[], p_note text, p_batch text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        r finance.legacy_credit_request; s people.student; pos record; v_decided numeric; v_entry uuid; v_decision uuid; v_balance numeric; v_rf text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_decides(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is approved, rejected or returned by the Bursar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO r FROM finance.legacy_credit_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_CREDIT_NOT_FOUND: no such request' USING ERRCODE = 'P0002'; END IF;
    IF r.status <> 'PENDING_BURSAR_APPROVAL' THEN
        RETURN 'LEGACY_CREDIT_STATE: request ' || r.ref || ' is ' || lower(replace(r.status, '_', ' ')) || '; only one waiting for the Bursar is decided';
    END IF;
    IF r.initiated_by = who THEN
        RETURN 'LEGACY_CREDIT_SAME_OFFICER: you initiated request ' || r.ref || '; another Bursar officer decides it';
    END IF;
    -- all or nothing: the overpayment locked, read afresh, the wallet credited once, the overpayment decided, the request closed
    PERFORM pg_advisory_xact_lock(hashtext('overpay:' || r.student_id::text || ':' || r.session));
    PERFORM pg_advisory_xact_lock(hashtext('wallet:' || r.student_id::text));
    SELECT * INTO s FROM people.student WHERE id = r.student_id;
    IF s.duplicate_of IS NOT NULL THEN
        RETURN 'LEGACY_CREDIT_STUDENT: the student record is merged into another; the credit is not posted';
    END IF;
    v_rf := finance.overpaid_refund_only(s.id);   -- read here, never trusted from the caller
    IF v_rf IS NOT NULL THEN
        RETURN 'OVERPAID_WALLET_REFUSED: the student is ' || finance.overpaid_refund_only_word(v_rf) || '; the excess is refunded, not credited to a wallet';
    END IF;
    IF NOT coalesce(p_listed, false) THEN
        RETURN 'LEGACY_CREDIT_EXCESS_CHANGED: the student is no longer listed as paid above the school fees of ' || r.session || '; return the request for correction';
    END IF;
    IF 'BANK_CHECK' = ANY (coalesce(p_holds, '{}'::text[])) THEN
        RETURN 'LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: the Bursary is checking with the bank whether the student''s school fees were charged twice (V561); the credit waits for the verdict';
    END IF;
    IF cardinality(coalesce(p_holds, '{}'::text[])) > 0 THEN
        RETURN 'OVERPAID_HELD: the excess on ' || r.session || ' cannot be decided yet (' || finance.overpaid_hold_words(p_holds) || ')';
    END IF;
    SELECT * INTO pos FROM finance.position(r.student_id, r.session);
    IF pos.due <= 0 OR NOT finance.fee_stated(r.student_id, r.session) THEN
        RETURN 'LEGACY_CREDIT_EXCESS_CHANGED: no school fees are stated for the student in ' || r.session || ' now; return the request for correction';
    END IF;
    IF abs((pos.paid - pos.due) - p_excess) >= 1 THEN
        RETURN 'OVERPAID_EXCESS_UNCERTAIN: the student''s own fee account reads NGN ' || to_char(pos.paid - pos.due, 'FM999,999,999,990.00')
               || ' paid above the charge, not the NGN ' || to_char(p_excess, 'FM999,999,999,990.00') || ' listed';
    END IF;
    v_decided := finance.overpayment_decided(r.student_id, r.session);
    IF (pos.paid - pos.due) - v_decided < r.confirmed_amount - 0.005 THEN
        RETURN 'LEGACY_CREDIT_EXCESS_CHANGED: the records now show NGN ' || to_char(greatest((pos.paid - pos.due) - v_decided, 0), 'FM999,999,999,990.00')
               || ' of ' || r.session || ' still undecided, below the NGN ' || to_char(r.confirmed_amount, 'FM999,999,999,990.00') || ' confirmed; return the request for correction';
    END IF;
    INSERT INTO finance.wallet_entry (student_id, session, kind, amount, reference, note, source_code, at)
    VALUES (r.student_id, r.session, 'CREDIT', r.confirmed_amount, r.ref, 'Overpaid school fees of ' || r.session || ' credited to your wallet (' || r.ref || ')', 'OVERPAID', now())
    RETURNING id INTO v_entry;
    INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, reference, decided_by, reason, fee_setup_checked)
    VALUES (r.student_id, r.session, pos.due, pos.paid, r.confirmed_amount, 'WALLET', r.ref, who, 'Credited to the wallet on request ' || r.ref || ': ' || r.reason, r.fee_setup_checked)
    RETURNING id INTO v_decision;
    UPDATE finance.legacy_credit_request
       SET status = 'CREDITED', decided_by = who, decided_office = office, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), ''),
           wallet_entry_id = v_entry, decision_id = v_decision, credit_batch = p_batch, last_skip_at = NULL, last_skip_code = NULL, last_skip_why = NULL
     WHERE id = p_id RETURNING * INTO r;
    v_balance := finance.wallet_balance(r.student_id);
    BEGIN
        PERFORM platform.tell_student(r.student_id, 'LEGACY_CREDIT_POSTED', NULL,
            jsonb_build_object('AMOUNT', 'NGN ' || to_char(r.confirmed_amount, 'FM999,999,999,990.00'), 'SESSION', r.session, 'REFERENCE', r.ref,
                               'BALANCE', 'NGN ' || to_char(coalesce(v_balance, 0), 'FM999,999,999,990.00')),
            'legacy-credit:' || r.ref || ':posted');
    EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;
              WHEN OTHERS THEN
        RAISE NOTICE 'legacy credit %: the student could not be told (%)', r.ref, SQLERRM;
    END;
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_credit_post(uuid, boolean, numeric, text[], text, text) IS 'V781: the one place an approved credit is posted — under the student''s overpay and wallet locks, the request read afresh: one wallet entry of overpaid school fees with a plain note (source OVERPAID), one WALLET decision, the request closed and the student told. Returns NULL when credited, else the CODE: words that stop the request. It does not apply the money to fees: the credit stays on the wallet until the student applies it (finance.apply_wallet) or asks for it as a refund. On the ledger finance.gl_sync moves it from the overpaid session''s school-fees income to the wallet (Dr 4010 / Cr 2100); no cash moves.';

-- the single approval on Legacy Financial Reconciliation: its APPROVE branch is the one place above (the rest of V625's text stands)
DO $v781$
DECLARE d text; a1 text; a2 text; b text; i int; j int; nl text := E'\n';
BEGIN
    d := pg_get_functiondef('finance.legacy_credit_decide(uuid,text,text)'::regprocedure);
    a1 := E'        -- all or nothing: the overpayment locked, read afresh, the wallet credited once, the overpayment decided, the request closed\n';
    a2 := E'\n    ELSE\n        UPDATE finance.legacy_credit_request\n           SET status = CASE v_action WHEN ''REJECT'' THEN ''REJECTED'' ELSE ''RETURNED_FOR_CORRECTION'' END,\n               decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_note)\n';
    PERFORM pg_temp.v781_once(d, a1, 'finance.legacy_credit_decide (the approval)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.legacy_credit_decide (the rejection)');
    PERFORM pg_temp.v781_once(d, E'        r finance.legacy_credit_request; s people.student; x record; v_entry uuid; v_decision uuid; v_balance numeric; v_action text := upper(btrim(coalesce(p_action, \'\')));', 'finance.legacy_credit_decide (declarations)');
    i := position(a1 IN d);
    j := position(a2 IN d);
    IF i = 0 OR j = 0 OR j < i THEN RAISE EXCEPTION 'V781: finance.legacy_credit_decide is not as it was left (its approval branch is not where it was)'; END IF;
    b := E'        SELECT * INTO x FROM finance.legacy_credit_excess(r.student_id, r.session);\n'
      || E'        v_why := finance.overpaid_credit_post(p_id, coalesce(x.listed, false), x.excess, coalesce(x.holds, ''{}''::text[]), p_note, NULL);\n'
      || E'        IF v_why IS NOT NULL THEN RAISE EXCEPTION ''%'', v_why USING ERRCODE = ''23514''; END IF;\n'
      || E'        SELECT * INTO r FROM finance.legacy_credit_request WHERE id = p_id;';
    d := substr(d, 1, i - 1) || E'        -- V781: the credit is posted in one place (finance.overpaid_credit_post), for this one request and for a batch\n' || b || substr(d, j);
    d := replace(d, E'        r finance.legacy_credit_request; s people.student; x record; v_entry uuid; v_decision uuid; v_balance numeric; v_action text := upper(btrim(coalesce(p_action, \'\')));',
                    E'        r finance.legacy_credit_request; s people.student; x record; v_entry uuid; v_decision uuid; v_balance numeric; v_why text; v_action text := upper(btrim(coalesce(p_action, \'\')));');
    -- a rejection or a return clears what an approval pass left on the request
    PERFORM pg_temp.v781_once(d, E'               decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_note)\n         WHERE id = p_id RETURNING * INTO r;', 'finance.legacy_credit_decide (the rejection update)');
    d := replace(d, E'               decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_note)\n         WHERE id = p_id RETURNING * INTO r;',
                    E'               decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_note),\n               last_skip_at = NULL, last_skip_code = NULL, last_skip_why = NULL\n         WHERE id = p_id RETURNING * INTO r;');
    -- the officer who initiated told of the decision: a clash passes through (V762's rule)
    PERFORM pg_temp.v781_once(d, E'    EXCEPTION WHEN OTHERS THEN\n        RAISE NOTICE ''legacy credit %: the officer could not be told (%)'', r.ref, SQLERRM;', 'finance.legacy_credit_decide (the officer told)');
    d := replace(d, E'    EXCEPTION WHEN OTHERS THEN\n        RAISE NOTICE ''legacy credit %: the officer could not be told (%)'', r.ref, SQLERRM;',
                    E'    EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;\n              WHEN OTHERS THEN\n        RAISE NOTICE ''legacy credit %: the officer could not be told (%)'', r.ref, SQLERRM;');
    PERFORM pg_temp.v781_once(d, E'            EXCEPTION WHEN OTHERS THEN\n                RAISE NOTICE ''legacy credit %: the student could not be told (%)'', r.ref, SQLERRM;', 'finance.legacy_credit_decide (the student told of a rejection)');
    d := replace(d, E'            EXCEPTION WHEN OTHERS THEN\n                RAISE NOTICE ''legacy credit %: the student could not be told (%)'', r.ref, SQLERRM;',
                    E'            EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;\n                      WHEN OTHERS THEN\n                RAISE NOTICE ''legacy credit %: the student could not be told (%)'', r.ref, SQLERRM;');
    EXECUTE d;
END $v781$;
COMMENT ON FUNCTION finance.legacy_credit_decide(uuid, text, text) IS 'V625, V781: the Bursar approves (credits the wallet once — finance.overpaid_credit_post), rejects or returns a single request made on Legacy Financial Reconciliation, by an officer other than the one who initiated it; everything that stops a credit is refused with its code (a hold, a student refused a wallet, the excess changed, the student''s own account reading another figure); the initiator is told.';

-- the Legacy desk counts the requests made on it; those made on the Overpaid school fees desk are counted by that desk
DO $v781$
DECLARE d text; a1 text; a2 text;
BEGIN
    d := pg_get_functiondef('finance.legacy_reconciliation_figures(text)'::regprocedure);
    a1 := E'    q AS (SELECT * FROM finance.legacy_credit_request),\n';
    a2 := E'            \'pendingSession\', (SELECT count(*) FROM q WHERE q.status = \'PENDING_BURSAR_APPROVAL\' AND q.session = p_session)),\n';
    PERFORM pg_temp.v781_once(d, a1, 'finance.legacy_reconciliation_figures (the requests)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.legacy_reconciliation_figures (the pending session)');
    d := replace(d, a1, E'    q AS (SELECT * FROM finance.legacy_credit_request x WHERE NOT x.bulk),   -- V781: the Overpaid school fees desk decides the ones made there\n');
    d := replace(d, a2, E'            \'pendingSession\', (SELECT count(*) FROM q WHERE q.status = \'PENDING_BURSAR_APPROVAL\' AND q.session = p_session),\n'
                        || E'            \'onOverpaidDesk\', (SELECT count(*) FROM finance.legacy_credit_request b WHERE b.bulk AND b.status = \'PENDING_BURSAR_APPROVAL\')),\n');
    EXECUTE d;
END $v781$;

-- ── 14 · the wallet credit in bulk: requested by one officer, decided by another, many at once ──
CREATE FUNCTION finance.overpaid_credits_request(p_session text, p_students uuid[], p_cause text, p_reason text, p_limit integer DEFAULT 1000,
                                                 p_batch text DEFAULT NULL, p_fee_setup_checked boolean DEFAULT false)
 RETURNS TABLE(batch_ref text, requested integer, amount numeric, skipped integer, skipped_why jsonb, remaining integer)
 LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := btrim(coalesce(p_reason, '')); v_batch text := nullif(btrim(coalesce(p_batch, '')), ''); v_drawn boolean := false;
        v_limit int := greatest(1, coalesce(p_limit, 1000)); v_one boolean; o record; pos record; v_open finance.legacy_credit_request; v_ref text; v_ev text; v_rem numeric;
        v_code text; v_why text; n_req int := 0; v_sum numeric := 0; n_skip int := 0; v_skips jsonb := '[]'::jsonb; v_left int := 0; v_seen uuid[] := '{}'::uuid[];
        v_causes text[] := '{}'::text[]; p uuid; st people.student; v_students uuid[];
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is made by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_initiates(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is initiated by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_session IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_SESSION: name the session the fees were overpaid on' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN RAISE EXCEPTION 'LEGACY_CREDIT_REASON: say why the credit is due, in ten characters or more' USING ERRCODE = '23514'; END IF;
    IF coalesce(array_length(p_students, 1), 0) = 0 AND p_cause IS NULL THEN
        RAISE EXCEPTION 'OVERPAID_BULK_WHO: name the students, or a paid-twice cause' USING ERRCODE = '23514';
    END IF;
    IF coalesce(array_length(p_students, 1), 0) = 0 AND p_cause NOT IN ('PORTAL_TWICE', 'OLD_AND_PORTAL', 'OLD_TWICE') THEN
        RAISE EXCEPTION 'OVERPAID_BULK_CAUSE: only a paid-twice cause is requested as a whole (paid twice on the portal, on the old portal and the new, or twice on the old portal); name the students of any other' USING ERRCODE = '23514';
    END IF;
    IF v_batch IS NOT NULL AND NOT EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.request_batch = v_batch AND q.session = p_session AND q.initiated_by = who) THEN
        RAISE EXCEPTION 'OVERPAID_BATCH: % is not a batch of yours for %', v_batch, p_session USING ERRCODE = '23514';
    END IF;
    v_students := CASE WHEN coalesce(array_length(p_students, 1), 0) = 0 THEN NULL ELSE p_students END;   -- no one named is a cause as a whole
    v_one := coalesce(array_length(v_students, 1), 0) = 1;
    FOR o IN SELECT x.* FROM finance.overpaid_read(p_session, v_students) x
              WHERE x.cause IS NOT NULL AND (p_cause IS NULL OR x.cause = p_cause) ORDER BY x.student_id LOOP
        v_seen := v_seen || o.student_id;
        -- an earlier call of the same act made this student's request: not a skip
        IF v_batch IS NOT NULL AND EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.student_id = o.student_id AND q.session = p_session
                                              AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION') AND q.request_batch = v_batch) THEN CONTINUE; END IF;
        v_code := NULL;
        IF o.remaining < 1 THEN v_code := 'DECIDED'; v_why := 'Nothing is left to decide: NGN ' || to_char(o.decided, 'FM999,999,999,990.00') || ' of the NGN ' || to_char(o.excess, 'FM999,999,999,990.00') || ' is already decided.';
        ELSIF cardinality(o.holds) > 0 THEN v_code := 'HELD'; v_why := 'Held: ' || finance.overpaid_hold_words(o.holds) || '.';
        ELSIF o.refund_only IS NOT NULL THEN v_code := 'REFUND_ONLY'; v_why := 'The student is ' || finance.overpaid_refund_only_word(o.refund_only) || ': the excess is refunded, not credited to a wallet.';
        ELSIF NOT o.bulk AND NOT v_one THEN v_code := 'ONE_AT_A_TIME'; v_why := 'Not a repeated payment that makes up the excess exactly: decided one student at a time, with the fee setup checked.';
        ELSIF NOT o.bulk AND NOT coalesce(p_fee_setup_checked, false) THEN v_code := 'FEE_SETUP_UNCHECKED'; v_why := 'Confirm that the fee setup and the payments were checked before this excess is credited.';
        END IF;
        IF v_code IS NULL THEN
            IF n_req >= v_limit THEN v_left := v_left + 1; CONTINUE; END IF;   -- before any lock is taken
            PERFORM pg_advisory_xact_lock(hashtext('overpay:' || o.student_id::text || ':' || p_session));
            SELECT * INTO v_open FROM finance.legacy_credit_request q WHERE q.student_id = o.student_id AND q.session = p_session
               AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION') LIMIT 1;
            IF FOUND THEN
                v_code := 'REQUEST_OPEN'; v_why := 'Credit request ' || v_open.ref || ' is already open for this student.';
            ELSE
                -- the second witness, under the lock: the student's own fee account
                SELECT * INTO pos FROM finance.position(o.student_id, p_session);
                v_rem := pos.paid - pos.due - finance.overpayment_decided(o.student_id, p_session);
                IF pos.due <= 0 OR abs((pos.paid - pos.due) - o.excess) >= 1 OR v_rem < 1 THEN
                    v_code := 'EXCESS_UNCERTAIN';
                    v_why := 'The student''s own fee account reads NGN ' || to_char(pos.paid - pos.due, 'FM999,999,999,990.00') || ' paid above the charge, not the NGN '
                             || to_char(o.excess, 'FM999,999,999,990.00') || ' listed.';
                END IF;
            END IF;
        END IF;
        IF v_code IS NOT NULL THEN
            n_skip := n_skip + 1;
            IF jsonb_array_length(v_skips) < 200 THEN
                v_skips := v_skips || jsonb_build_object('student_id', o.student_id, 'number', o.number, 'name', o.name, 'code', v_code, 'why', v_why);
            END IF;
            CONTINUE;
        END IF;
        IF v_batch IS NULL THEN
            v_batch := 'OCR/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.overpaid_request_batch_seq')::text, 6, '0');
            v_drawn := true;
        END IF;
        v_ev := finance.overpaid_cause_word(o.cause) || ': ' || o.n_payments || ' payment' || CASE WHEN o.n_payments = 1 THEN '' ELSE 's' END || ' of ' || p_session || ' — '
                || coalesce((SELECT string_agg('NGN ' || to_char((e.item ->> 'amount')::numeric, 'FM999,999,999,990.00') || ' (' || coalesce(e.item ->> 'channel', 'channel not recorded') || ', '
                                               || to_char((e.item ->> 'on')::date, 'DD Mon YYYY') || ')', '; ' ORDER BY e.ord)
                               FROM jsonb_array_elements(o.payments) WITH ORDINALITY e(item, ord)), 'none')
                || '; charged NGN ' || to_char(pos.due, 'FM999,999,999,990.00') || ', paid NGN ' || to_char(pos.paid, 'FM999,999,999,990.00');
        v_ref := 'LOR/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.legacy_credit_request_seq')::text, 6, '0');
        INSERT INTO finance.legacy_credit_request (ref, student_id, session, due, paid, legacy_amount, confirmed_amount, reason, evidence, initiated_by, initiated_office,
                                                   cause, bulk, request_batch, fee_setup_checked)
        VALUES (v_ref, o.student_id, p_session, pos.due, pos.paid, v_rem, v_rem, v_reason, v_ev, who, office, o.cause, true, v_batch, NOT o.bulk);
        n_req := n_req + 1; v_sum := v_sum + v_rem;
        IF NOT (o.cause = ANY (v_causes)) THEN v_causes := v_causes || o.cause; END IF;
    END LOOP;
    -- students named that the list has no row for
    FOR o IN SELECT u.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name
               FROM unnest(coalesce(p_students, '{}'::uuid[])) u(id) LEFT JOIN people.student s ON s.id = u.id WHERE u.id <> ALL (v_seen) LOOP
        n_skip := n_skip + 1;
        IF jsonb_array_length(v_skips) < 200 THEN
            v_skips := v_skips || jsonb_build_object('student_id', o.id, 'number', o.number, 'name', o.name, 'code', 'NOT_OVERPAID',
                                                     'why', 'Not paid above the school fees of ' || p_session || CASE WHEN p_cause IS NULL THEN '.' ELSE ' for the cause chosen.' END);
        END IF;
    END LOOP;
    -- the Bursar's office holders told, once, by the call that drew the batch number
    IF v_drawn AND n_req > 0 THEN
        FOR p IN SELECT * FROM finance.bursar_holders() LOOP
            BEGIN
                PERFORM platform.tell_person(p, 'OVERPAID_CREDITS_WAITING', NULL,
                    jsonb_build_object('BATCH', v_batch, 'COUNT', n_req, 'AMOUNT', 'NGN ' || to_char(v_sum, 'FM999,999,999,990.00'), 'SESSION', p_session,
                                       'CAUSE', CASE WHEN cardinality(v_causes) = 1 THEN finance.overpaid_cause_word(v_causes[1]) ELSE 'several causes' END,
                                       'OFFICER', coalesce(helpdesk.person_name(who), 'an officer')),
                    'overpaid-credits:' || v_batch || ':waiting:' || p::text);
            EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;
                      WHEN OTHERS THEN
                RAISE NOTICE 'overpaid credits %: the Bursar could not be told (%)', v_batch, SQLERRM;
            END;
        END LOOP;
    END IF;
    RETURN QUERY SELECT v_batch, n_req, v_sum, n_skip, v_skips, v_left;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_credits_request(text, uuid[], text, text, integer, text, boolean) IS 'V781: a Bursary officer or the Students Account Officer requests the wallet credit of many students at once (named, or every row of a paid-twice cause), one request each (LOR/...) under one batch number (OCR/...) drawn with the first request; p_batch continues the act in a further call. Each student is read live and skipped with its code and words when nothing is left to decide, a hold stands, the student is refused a wallet, the row is not a repeated payment that makes up the excess exactly (decided one student at a time, with p_fee_setup_checked), a request is open, or the student''s own fee account reads another figure. The amount is always the whole undecided excess. Nothing is credited here: another Bursary officer approves.';

-- ── 15 · decided by another Bursar officer: approved, returned or rejected, a pass that ends ──
CREATE FUNCTION finance.overpaid_credits_decide(p_ids uuid[], p_batch text, p_action text, p_note text, p_limit integer DEFAULT 200, p_since timestamptz DEFAULT NULL)
 RETURNS TABLE(batch_ref text, since timestamptz, credited integer, amount numeric, rejected integer, returned integer, skipped integer, skipped_why jsonb, remaining integer)
 LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_action text := upper(btrim(coalesce(p_action, ''))); v_note text := btrim(coalesce(p_note, '')); v_since timestamptz; v_cands uuid[]; v_credit_batch text;
        r record; rd record; v_map jsonb; v_session text; v_why text; v_code text; v_listed boolean; v_excess numeric; v_holds text[];
        n_cred int := 0; v_sum numeric := 0; n_rej int := 0; n_ret int := 0; n_skip int := 0; v_skips jsonb := '[]'::jsonb; v_left int; v_locked boolean;
        v_done uuid[] := '{}'::uuid[]; v_left_ids uuid[] := '{}'::uuid[]; i record; v_key text; st record;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_decides(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is approved, rejected or returned by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('APPROVE', 'REJECT', 'RETURN') THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTION: approve, reject or return for correction' USING ERRCODE = '23514'; END IF;
    IF v_action <> 'APPROVE' AND length(v_note) < 10 THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_NOTE: say why it is %, in ten characters or more', CASE v_action WHEN 'REJECT' THEN 'rejected' ELSE 'returned' END USING ERRCODE = '23514';
    END IF;
    IF coalesce(array_length(p_ids, 1), 0) = 0 AND nullif(btrim(coalesce(p_batch, '')), '') IS NULL THEN
        RAISE EXCEPTION 'OVERPAID_BULK_WHO: name the requests, or the batch they were made in' USING ERRCODE = '23514';
    END IF;
    -- the moment this pass began: a request this pass already tried and left is not tried again in it
    v_since := coalesce(p_since, clock_timestamp());
    v_cands := ARRAY(SELECT q.id FROM finance.legacy_credit_request q
                      WHERE q.status = 'PENDING_BURSAR_APPROVAL' AND q.bulk AND (q.id = ANY (coalesce(p_ids, '{}'::uuid[])) OR q.request_batch = nullif(btrim(coalesce(p_batch, '')), ''))
                        AND (q.last_skip_at IS NULL OR q.last_skip_at < v_since)
                      ORDER BY q.session, q.student_id, q.id LIMIT greatest(1, least(coalesce(p_limit, 200), 500)));
    FOR v_session IN SELECT DISTINCT q.session FROM finance.legacy_credit_request q WHERE q.id = ANY (v_cands) ORDER BY 1 LOOP
        IF v_action = 'APPROVE' THEN
            -- one read of the session gives each student's row: whether listed, the excess, the holds
            v_map := (SELECT coalesce(jsonb_object_agg(x.student_id::text, jsonb_build_object('excess', x.excess, 'holds', to_jsonb(x.holds))), '{}'::jsonb)
                        FROM finance.overpaid_read(v_session, ARRAY(SELECT q.student_id FROM finance.legacy_credit_request q WHERE q.id = ANY (v_cands) AND q.session = v_session)) x
                       WHERE x.cause IS NOT NULL);
        END IF;
        FOR r IN SELECT q.id, q.ref, q.student_id, q.initiated_by, q.confirmed_amount FROM finance.legacy_credit_request q
                  WHERE q.id = ANY (v_cands) AND q.session = v_session ORDER BY q.student_id, q.id LOOP
            -- a request another approval holds at this moment is theirs
            SELECT true INTO v_locked FROM finance.legacy_credit_request q WHERE q.id = r.id AND q.status = 'PENDING_BURSAR_APPROVAL' FOR UPDATE SKIP LOCKED;
            IF NOT coalesce(v_locked, false) THEN CONTINUE; END IF;
            v_why := NULL;
            IF r.initiated_by = who THEN
                v_why := 'LEGACY_CREDIT_SAME_OFFICER: you initiated request ' || r.ref || '; another Bursar officer decides it';
            ELSIF v_action = 'APPROVE' THEN
                v_key := r.student_id::text;
                v_listed := v_map ? v_key;
                v_excess := (v_map -> v_key ->> 'excess')::numeric;
                v_holds := coalesce(ARRAY(SELECT jsonb_array_elements_text(v_map -> v_key -> 'holds')), '{}'::text[]);
                IF v_credit_batch IS NULL THEN
                    v_credit_batch := 'OCA/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('finance.overpaid_credit_batch_seq')::text, 6, '0');
                END IF;
                v_why := finance.overpaid_credit_post(r.id, v_listed, v_excess, v_holds, nullif(v_note, ''), v_credit_batch);
                IF v_why IS NULL THEN
                    n_cred := n_cred + 1; v_sum := v_sum + r.confirmed_amount; v_done := v_done || r.id;
                    CONTINUE;
                END IF;
            ELSE
                -- rejected or returned for correction; no student is told: the student never knew the request existed
                UPDATE finance.legacy_credit_request SET status = CASE v_action WHEN 'REJECT' THEN 'REJECTED' ELSE 'RETURNED_FOR_CORRECTION' END,
                       decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
                       last_skip_at = NULL, last_skip_code = NULL, last_skip_why = NULL
                 WHERE id = r.id;
                IF v_action = 'REJECT' THEN n_rej := n_rej + 1; ELSE n_ret := n_ret + 1; END IF;
                v_done := v_done || r.id;
                CONTINUE;
            END IF;
            -- the request is left as it was, with its reason, and not tried again in this pass
            v_code := split_part(v_why, ':', 1);
            UPDATE finance.legacy_credit_request SET last_skip_at = clock_timestamp(), last_skip_code = v_code, last_skip_why = btrim(substr(v_why, length(v_code) + 2))
             WHERE id = r.id AND status = 'PENDING_BURSAR_APPROVAL';
            n_skip := n_skip + 1; v_left_ids := v_left_ids || r.id;
            IF jsonb_array_length(v_skips) < 200 THEN
                SELECT coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name INTO st FROM people.student s WHERE s.id = r.student_id;
                v_skips := v_skips || jsonb_build_object('id', r.id, 'ref', r.ref, 'student_id', r.student_id, 'number', st.number, 'name', st.name,
                                                         'code', v_code, 'why', btrim(substr(v_why, length(v_code) + 2)));
            END IF;
        END LOOP;
    END LOOP;
    -- each officer who requested what was decided told once, with that officer's own counts
    FOR i IN SELECT q.initiated_by AS person, count(*) FILTER (WHERE q.id = ANY (v_done)) AS decided, coalesce(sum(q.confirmed_amount) FILTER (WHERE q.id = ANY (v_done)), 0) AS amount,
                    count(*) FILTER (WHERE q.id = ANY (v_left_ids)) AS left_over
               FROM finance.legacy_credit_request q WHERE q.id = ANY (v_done || v_left_ids) GROUP BY q.initiated_by HAVING count(*) FILTER (WHERE q.id = ANY (v_done)) > 0 LOOP
        BEGIN
            PERFORM platform.tell_person(i.person, 'OVERPAID_CREDITS_DECIDED', NULL,
                jsonb_build_object('BATCH', coalesce(nullif(btrim(coalesce(p_batch, '')), ''), v_credit_batch, 'selected requests'), 'COUNT', i.decided, 'AMOUNT', 'NGN ' || to_char(i.amount, 'FM999,999,999,990.00'),
                                   'ACTION', CASE v_action WHEN 'APPROVE' THEN 'approved and credited' WHEN 'REJECT' THEN 'rejected' ELSE 'returned for correction' END,
                                   'SKIPPED', i.left_over, 'BURSAR', coalesce(helpdesk.person_name(who), 'a Bursar officer')),
                'overpaid-credits:' || coalesce(nullif(btrim(coalesce(p_batch, '')), ''), v_credit_batch, md5(coalesce(p_ids::text, ''))) || ':decided:' || i.person::text || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
        EXCEPTION WHEN deadlock_detected OR serialization_failure OR lock_not_available THEN RAISE;
                  WHEN OTHERS THEN
            RAISE NOTICE 'overpaid credits: the officer could not be told (%)', SQLERRM;
        END;
    END LOOP;
    -- what still waits for this pass: every request tried is decided or marked, so this falls on every call that finds one
    SELECT count(*) INTO v_left FROM finance.legacy_credit_request q
     WHERE q.status = 'PENDING_BURSAR_APPROVAL' AND q.bulk AND (q.id = ANY (coalesce(p_ids, '{}'::uuid[])) OR q.request_batch = nullif(btrim(coalesce(p_batch, '')), ''))
       AND (q.last_skip_at IS NULL OR q.last_skip_at < v_since);
    RETURN QUERY SELECT coalesce(nullif(btrim(coalesce(p_batch, '')), ''), v_credit_batch), v_since, n_cred, v_sum, n_rej, n_ret, n_skip, v_skips, v_left;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_credits_decide(uuid[], text, text, text, integer, timestamptz) IS 'V781: a Bursar officer other than the requester approves (credits each wallet through finance.overpaid_credit_post, an approval batch OCA/... drawn with the first), rejects or returns for correction the pending requests made on the Overpaid school fees desk, named or by request batch, up to p_limit a call. A request that cannot be credited is left with its code and words (last_skip_*) and not tried again in the pass (p_since: the moment the pass began, returned and passed back on each further call), so remaining falls on every call that finds one and reaches 0; the requester''s own requests are skipped LEGACY_CREDIT_SAME_OFFICER. A rejection or a return tells no student; each requester is told once with their own counts. The pass does not apply any money to fees.';

-- a mistaken request undone in one act, by whoever requested it (or any Bursary officer of the Bursar's office)
CREATE FUNCTION finance.overpaid_credits_withdraw(p_batch text, p_ids uuid[], p_reason text) RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LEGACY_CREDIT_ACTOR: a credit request is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    IF NOT finance.legacy_credit_office_initiates(coalesce(office, '')) THEN
        RAISE EXCEPTION 'LEGACY_CREDIT_OFFICE: a legacy credit is initiated by the Students Account Officer or the Bursar' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'LEGACY_CREDIT_REASON: say why the request is withdrawn, in ten characters or more' USING ERRCODE = '23514'; END IF;
    IF coalesce(array_length(p_ids, 1), 0) = 0 AND nullif(btrim(coalesce(p_batch, '')), '') IS NULL THEN
        RAISE EXCEPTION 'OVERPAID_BULK_WHO: name the requests, or the batch they were made in' USING ERRCODE = '23514';
    END IF;
    WITH mine AS (
        SELECT q.id FROM finance.legacy_credit_request q
         WHERE q.bulk AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')
           AND (q.id = ANY (coalesce(p_ids, '{}'::uuid[])) OR q.request_batch = nullif(btrim(coalesce(p_batch, '')), ''))
           AND (q.initiated_by = who OR office IN ('bursar', 'super'))
         ORDER BY q.id FOR UPDATE),
    done AS (
        UPDATE finance.legacy_credit_request q SET status = 'WITHDRAWN', withdrawn_by = who, withdrawn_at = now(), withdraw_reason = btrim(p_reason),
               last_skip_at = NULL, last_skip_code = NULL, last_skip_why = NULL
         WHERE q.id IN (SELECT m.id FROM mine m) RETURNING q.id)
    SELECT count(*) INTO n FROM done;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION finance.overpaid_credits_withdraw(text, uuid[], text) IS 'V781: withdraws the open requests (pending or returned) made on the Overpaid school fees desk, named or by request batch — the requester''s own, or any when the caller''s office is the Bursar''s or super — with a reason; returns how many. A returned request is not resubmitted on this desk: it is withdrawn and the student requested again.';


-- ── 16 · the wallet: a credit of overpaid school fees comes only from its approved request, and is never wiped; a refund names its source ──
DO $v781$
DECLARE d text; a text;
BEGIN
    -- a hand credit of that source is refused: an OVERPAID credit exists only with the request a second Bursary officer approved
    d := pg_get_functiondef('finance.credit_wallet(uuid,text,numeric,text,text)'::regprocedure);
    a := E'    IF NOT EXISTS (SELECT 1 FROM finance.funding_source WHERE code = v_src AND active) THEN';
    PERFORM pg_temp.v781_once(d, a, 'finance.credit_wallet');
    d := replace(d, a, E'    -- V781: overpaid school fees reach a wallet only through a credit request a second Bursary officer approved\n'
        || E'    IF v_src = ''OVERPAID'' THEN\n'
        || E'        RAISE EXCEPTION ''WALLET_OVERPAID_ROUTE: overpaid school fees reach a wallet only through a credit request approved by a second Bursary officer'' USING ERRCODE = ''23514'',\n'
        || E'            HINT = ''Request the credit on the Overpaid school fees desk; a hand credit is for money that arrived from a source.'';\n'
        || E'    END IF;\n' || a);
    EXECUTE d;
    -- a reset over such a credit would delete the request with it (the entry''s foreign key cascades) and leave the decision and its journal standing
    d := pg_get_functiondef('finance.reset_wallet(uuid)'::regprocedure);
    a := E'    DELETE FROM finance.wallet_withdrawal WHERE student_id = p_student;';
    PERFORM pg_temp.v781_once(d, a, 'finance.reset_wallet');
    d := replace(d, a, E'    -- V781: a wallet holding a credit of overpaid school fees is not wiped: the overpayment would stay decided with no money behind it\n'
        || E'    IF EXISTS (SELECT 1 FROM finance.wallet_entry e WHERE e.student_id = p_student AND e.kind = ''CREDIT'' AND e.source_code = ''OVERPAID'') THEN\n'
        || E'        RAISE EXCEPTION ''WALLET_RESET_OVERPAID_CREDIT: this wallet holds a credit of overpaid school fees; a reset would leave the overpayment decided with no money behind it'' USING ERRCODE = ''23514'',\n'
        || E'            HINT = ''The credit is used on the student''''s fees or refunded from the wallet; it is not wiped.'';\n'
        || E'    END IF;\n' || a);
    EXECUTE d;
END $v781$;

-- what each source may give back as a refund now: the page's and the server's one figure
CREATE FUNCTION finance.withdrawal_sources(p_student uuid, p_session text)
 RETURNS TABLE(source_code text, source_name text, nature text, refundable numeric)
 LANGUAGE sql STABLE AS $fn$
    WITH e AS (SELECT x.* FROM finance.withdrawal_eligibility(p_student, p_session) x WHERE x.cleared AND NOT x.arrears),
    sess AS (SELECT b.* FROM finance.wallet_balances_session(p_student, p_session) b),
    cand AS (
        SELECT b.source_code, b.source_name, b.nature, greatest(b.available - b.held, 0) AS fig, 1 AS ord, e.nelfund_refundable AS cap
          FROM sess b CROSS JOIN e WHERE b.nature = 'LOAN' AND 'LOAN' = ANY (e.refund_natures)
        UNION ALL   -- the student's own money: a top-up first, then the other sources of the session's view
        SELECT b.source_code, b.source_name, b.nature, greatest(b.available - b.held, 0), CASE WHEN b.source_code = 'SELF' THEN 0 ELSE 1 END, e.self_refundable
          FROM sess b CROSS JOIN e WHERE b.nature = 'SELF' AND b.source_code <> 'OVERPAID' AND 'SELF' = ANY (e.refund_natures)
        UNION ALL   -- overpaid school fees, over every session, less what a decision above the excess owes the session's fees
        SELECT b.source_code, b.source_name, b.nature, finance.overpaid_refundable(p_student), 1, e.self_refundable
          FROM finance.wallet_balances(p_student) b CROSS JOIN e WHERE b.source_code = 'OVERPAID' AND b.nature = 'SELF' AND 'SELF' = ANY (e.refund_natures)),
    capped AS (   -- each nature capped in all at what the eligibility reads
        SELECT c.*, least(c.fig, greatest(c.cap - coalesce(sum(c.fig) OVER (PARTITION BY c.nature ORDER BY c.ord, c.source_code ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0), 0)) AS shown
          FROM cand c)
    SELECT c.source_code, c.source_name, c.nature, c.shown FROM capped c WHERE c.shown > 0
     ORDER BY CASE c.nature WHEN 'LOAN' THEN 0 ELSE 1 END, c.ord, c.source_code
$fn$;
COMMENT ON FUNCTION finance.withdrawal_sources(uuid, text) IS 'V781: what each source of a wallet may give back as a refund now — empty unless the session''s fees are cleared with nothing in arrears; the loan sources of the session''s view capped in all at what the eligibility reads for them; the student''s own money (a top-up first; overpaid school fees over every session, less what a decision above the excess owes the session''s fees) capped in all at what it reads for that; only sources above zero. A refund of a source never exceeds its figure here.';

DO $v781$
DECLARE d text; a text; a2 text;
BEGIN
    -- overpaid school fees sit on the session they were overpaid in: refundable from whichever session's page the student is on
    d := pg_get_functiondef('finance.withdrawal_eligibility(uuid,text)'::regprocedure);
    a := E'    -- the Fund''s money arrived after the session''s fees were settled by other means: nothing of it was applied';
    PERFORM pg_temp.v781_once(d, a, 'finance.withdrawal_eligibility');
    d := replace(d, a, E'    -- V781: overpaid school fees sit on the session they were overpaid in; they are refundable from whichever session is asked, less what a\n'
        || E'    -- decision above the excess owes back to the session''s fees (finance.overpaid_refundable). The tests after it are unchanged and right for this\n'
        || E'    -- money: nothing is refundable until the session asked is paid in full with no arrears, the session the wallet pays first, and never more than\n'
        || E'    -- the wallet holds in all.\n'
        || E'    IF ''SELF'' = ANY (v_natures) THEN\n'
        || E'        v_self := v_self\n'
        || E'            - coalesce((SELECT greatest(b.available - b.held, 0) FROM finance.wallet_balances_session(p_student, p_session) b WHERE b.source_code = ''OVERPAID''), 0)\n'
        || E'            + finance.overpaid_refundable(p_student);\n'
        || E'    END IF;\n' || a);
    EXECUTE d;

    -- a refund of the student's own money names the source that holds it
    d := pg_get_functiondef('finance.request_withdrawal(uuid,text,numeric,text,text,text,text)'::regprocedure);
    a := E'    IF v_src IS NULL THEN v_src := CASE WHEN elig.nelfund_refundable > 0 THEN ''NELFUND'' ELSE ''SELF'' END; END IF;';
    a2 := E'    v_cap := CASE WHEN v_src = ''NELFUND'' THEN elig.nelfund_refundable WHEN v_src = ''SELF'' THEN elig.self_refundable ELSE 0 END;';
    PERFORM pg_temp.v781_once(d, a, 'finance.request_withdrawal (the source)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.request_withdrawal (the cap)');
    d := replace(d, a, E'    IF v_src IS NULL AND elig.nelfund_refundable > 0 THEN v_src := ''NELFUND''; END IF;\n'
        || E'    IF v_src IS NULL OR v_src = ''SELF'' THEN   -- V781: own money: the source of the student''s own money that covers the amount (a top-up first)\n'
        || E'        v_src := (SELECT ws.source_code FROM finance.withdrawal_sources(p_student, p_session) ws\n'
        || E'                   WHERE ws.nature = ''SELF'' AND (p_amount IS NULL OR ws.refundable >= p_amount)\n'
        || E'                   ORDER BY (ws.source_code = ''SELF'') DESC, ws.refundable DESC, ws.source_code LIMIT 1);\n'
        || E'        IF v_src IS NULL AND EXISTS (SELECT 1 FROM finance.withdrawal_sources(p_student, p_session) ws WHERE ws.nature = ''SELF'') THEN\n'
        || E'            RAISE EXCEPTION ''WALLET_REFUND_ONE_SOURCE: NGN % is more than any one source of your own money holds'', p_amount USING ERRCODE = ''23514'',\n'
        || E'                HINT = ''Ask for each part separately: '' || (SELECT string_agg(''up to NGN '' || ws.refundable::text || '' of '' || ws.source_name, ''; '' ORDER BY ws.source_code)\n'
        || E'                                                              FROM finance.withdrawal_sources(p_student, p_session) ws WHERE ws.nature = ''SELF'') || ''.'';\n'
        || E'        END IF;\n'
        || E'        v_src := coalesce(v_src, ''SELF'');\n'
        || E'    END IF;');
    d := replace(d, a2, E'    v_cap := CASE WHEN v_src = ''NELFUND'' THEN elig.nelfund_refundable\n'
        || E'                  ELSE coalesce((SELECT ws.refundable FROM finance.withdrawal_sources(p_student, p_session) ws WHERE ws.source_code = v_src AND ws.nature = ''SELF''), 0) END;');
    EXECUTE d;

    -- approved: the source's own figure (its own hold counted back), and what a decision above the excess owes back is not refunded
    d := pg_get_functiondef('finance.approve_withdrawal(uuid)'::regprocedure);
    a := E'    v_cap := CASE WHEN r.source_code = ''SELF'' THEN elig.self_refundable WHEN r.source_code IS NULL THEN finance.wallet_balance(r.student_id) ELSE elig.nelfund_refundable END + r.amount;';
    a2 := E'    IF v_cap < r.amount THEN';
    PERFORM pg_temp.v781_once(d, a, 'finance.approve_withdrawal (the cap)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.approve_withdrawal (the refusal)');
    d := replace(d, a, E'    v_cap := CASE WHEN r.source_code IS NULL THEN finance.wallet_balance(r.student_id)\n'
        || E'                  WHEN (SELECT fs.nature FROM finance.funding_source fs WHERE fs.code = r.source_code) = ''SELF''\n'
        || E'                       THEN coalesce((SELECT ws.refundable FROM finance.withdrawal_sources(r.student_id, r.session) ws WHERE ws.source_code = r.source_code), 0)   -- V781: the source''s own figure\n'
        || E'                  ELSE elig.nelfund_refundable END + r.amount;');
    d := replace(d, a2, E'    -- V781: what a decision above the excess owes back to the session''s fees is not refunded from the wallet: a request made before the charge\n'
        || E'    -- rose is caught here (its own hold is counted back before the floor)\n'
        || E'    IF r.source_code = ''OVERPAID'' AND finance.overpaid_refundable(r.student_id, r.amount) < r.amount - 0.005 THEN\n'
        || E'        RAISE EXCEPTION ''WALLET_REFUND_KEPT_BACK: NGN % of the overpaid school fees on this wallet is owed back to the student''''s school fees, which rose after it was credited; NGN % may be refunded'',\n'
        || E'            to_char(r.amount - finance.overpaid_refundable(r.student_id, r.amount), ''FM999,999,999,990.00''), to_char(finance.overpaid_refundable(r.student_id, r.amount), ''FM999,999,999,990.00'')\n'
        || E'            USING ERRCODE = ''23514'', HINT = ''Overpaid school fees lists the student as decided above the excess.'';\n'
        || E'    END IF;\n' || a2);
    EXECUTE d;
END $v781$;

-- ── 17 · a refund against a school-fees payment never gives back money a decision already gave, nor crosses an open credit request ──
DO $v781$
DECLARE d text; a text; a2 text;
BEGIN
    d := pg_get_functiondef('finance.propose_refund(uuid,text,text,numeric,text,text,text,text)'::regprocedure);
    a := E'DECLARE who uuid := nullif(current_setting(''moaum.actor_id'', true), '''')::uuid; v_ref text; v_src text; st record; v_raised numeric;';
    a2 := E'        -- V350: with the refunds already raised against it and not rejected';
    PERFORM pg_temp.v781_once(d, a, 'finance.propose_refund (declarations)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.propose_refund (the V350 line)');
    d := replace(d, a, a || E' v_stu uuid; v_ses text; v_given numeric;');
    d := replace(d, a2, E'        -- V781: a refund against a school-fees payment never gives back money an overpayment decision already gave, nor crosses an open credit\n'
        || E'        -- request (the student''s overpay lock is taken before the refund rows, the order decide_overpayments takes them in)\n'
        || E'        SELECT x.student_id, x.session INTO v_stu, v_ses FROM finance.payment_reference x\n'
        || E'         WHERE x.reference = v_src AND x.student_id IS NOT NULL AND x.purpose LIKE ''School fees%'';\n'
        || E'        IF FOUND THEN\n'
        || E'            PERFORM pg_advisory_xact_lock(hashtext(''overpay:'' || v_stu::text || '':'' || v_ses));\n'
        || E'            IF EXISTS (SELECT 1 FROM finance.legacy_credit_request q WHERE q.student_id = v_stu AND q.session = v_ses\n'
        || E'                          AND q.status IN (''PENDING_BURSAR_APPROVAL'', ''RETURNED_FOR_CORRECTION'')) THEN\n'
        || E'                RAISE EXCEPTION ''REFUND_CREDIT_REQUEST_OPEN: a wallet credit request is open for the money paid above the % school fees; it is decided or withdrawn first'', v_ses USING ERRCODE = ''23514'',\n'
        || E'                    HINT = ''Overpaid school fees lists the request.'';\n'
        || E'            END IF;\n'
        || E'            v_given := finance.overpayment_decided(v_stu, v_ses);\n'
        || E'            IF v_given > 0 AND p_amount + v_given > (SELECT p.paid FROM finance.position(v_stu, v_ses) p) + 0.005 THEN\n'
        || E'                RAISE EXCEPTION ''REFUND_ALREADY_DECIDED: NGN % of the % school fees is already credited, carried or refunded; NGN % more would pass the NGN % paid'',\n'
        || E'                    to_char(v_given, ''FM999,999,999,990.00''), v_ses, to_char(p_amount, ''FM999,999,999,990.00''),\n'
        || E'                    to_char((SELECT p.paid FROM finance.position(v_stu, v_ses) p), ''FM999,999,999,990.00'') USING ERRCODE = ''23514'';\n'
        || E'            END IF;\n'
        || E'        END IF;\n' || a2);
    EXECUTE d;
END $v781$;

-- ── 18 · a correction of a payment is refused by the arithmetic, not by the mere presence of a decision ──
-- Only when taking the payment away would leave less paid above the charge than is decided or requested. Money arriving (the target of a
-- swap, the destination of a reallocation) is never refused: it is a decided student paying again.
DO $v781$
DECLARE d text; a text; a2 text;
BEGIN
    d := pg_get_functiondef('finance.payment_archive_refusals(uuid)'::regprocedure);
    a := E'    IF r.purpose LIKE ''School fees%'' AND EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = r.student_id AND d.session = r.session AND d.superseded_at IS NULL) THEN';
    a2 := E'        refusals := refusals || ''PAR_OVERPAYMENT_DECISION: an overpayment decision stands on the student''''s school fees for the session (carried or refunded); the Bursary sets it aside first''::text;';
    PERFORM pg_temp.v781_once(d, a, 'finance.payment_archive_refusals');
    PERFORM pg_temp.v781_once(d, a2, 'finance.payment_archive_refusals (the words)');
    d := replace(d, a, E'    IF r.purpose LIKE ''School fees%'' AND NOT finance.overpayment_decisions_covered(r.student_id, r.session, r.amount) THEN');
    d := replace(d, a2, E'        refusals := refusals || ''PAR_OVERPAYMENT_DECISION: money paid above the student''''s school fees for the session is already credited, carried, refunded or requested, and without this payment less than that would remain''::text;');
    EXECUTE d;

    d := pg_get_functiondef('finance.payment_swap_check(uuid,uuid,uuid)'::regprocedure);
    a := E'    IF v_kind IS DISTINCT FROM ''OUTSTANDING_FEES'' AND EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = r.student_id AND d.session = r.session AND d.superseded_at IS NULL) THEN';
    a2 := E'        refusals := refusals || ''SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the credited student''''s fees for this session; the Bursary sets it aside first''::text;';
    PERFORM pg_temp.v781_once(d, a, 'finance.payment_swap_check (the credited student)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.payment_swap_check (the words)');
    PERFORM pg_temp.v781_once(d, E'                IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = t.id AND d.session = r.session AND d.superseded_at IS NULL) THEN\n'
        || E'                    refusals := refusals || ''SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the target student''''s fees for this session; the Bursary sets it aside first''::text;\n'
        || E'                END IF;\n', 'finance.payment_swap_check (the target student)');
    d := replace(d, a, E'    IF v_kind IS DISTINCT FROM ''OUTSTANDING_FEES'' AND NOT finance.overpayment_decisions_covered(r.student_id, r.session, r.amount) THEN');
    d := replace(d, a2, E'        refusals := refusals || ''SWAP_OVERPAYMENT_DECISION: money paid above the credited student''''s school fees for this session is already credited, carried, refunded or requested, and without this payment less than that would remain''::text;');
    d := replace(d, E'                IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = t.id AND d.session = r.session AND d.superseded_at IS NULL) THEN\n'
        || E'                    refusals := refusals || ''SWAP_OVERPAYMENT_DECISION: an overpayment decision stands on the target student''''s fees for this session; the Bursary sets it aside first''::text;\n'
        || E'                END IF;\n',
        E'                -- V781: money arriving on the target student is a decided student paying again: it is never refused for a decision\n');
    EXECUTE d;

    d := pg_get_functiondef('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)'::regprocedure);
    a := E'        -- an overpayment decision is taken on the session''s school fees as they stood: set aside before they change\n'
      || E'        IF EXISTS (SELECT 1 FROM finance.overpayment_decision d WHERE d.student_id = s.id AND d.superseded_at IS NULL\n'
      || E'                     AND ((v_from_code = ''SCHOOL_FEES'' AND d.session = r.session) OR (v_code = ''SCHOOL_FEES'' AND d.session = v_session))) THEN\n'
      || E'            refusals := refusals || ''REALLOC_OVERPAYMENT_DECISION: an overpayment decision stands on the student''''s school fees for the session; the Bursary sets it aside first''::text;\n'
      || E'        END IF;\n';
    PERFORM pg_temp.v781_once(d, a, 'finance.payment_reallocation_check');
    d := replace(d, a, E'        -- V781: an overpayment decision is taken on the session''s school fees as they stood: the payment leaves only while what is paid above the\n'
      || E'        -- charge still covers the money decided or requested; money arriving into the session''s school fees is never refused\n'
      || E'        IF v_from_code = ''SCHOOL_FEES'' AND NOT finance.overpayment_decisions_covered(s.id, r.session, r.amount) THEN\n'
      || E'            refusals := refusals || ''REALLOC_OVERPAYMENT_DECISION: money paid above the student''''s school fees for the session is already credited, carried, refunded or requested, and without this payment less than that would remain''::text;\n'
      || E'        END IF;\n');
    EXECUTE d;

    d := pg_get_functiondef('finance.not_received_refusal(uuid)'::regprocedure);
    a := E'             WHEN r.purpose LIKE ''School fees%'' AND EXISTS (SELECT 1 FROM finance.overpayment_settled(r.student_id, r.session)) THEN ''PAY_NOT_RECEIVED_DECIDED''';
    PERFORM pg_temp.v781_once(d, a, 'finance.not_received_refusal');
    d := replace(d, a, E'             WHEN r.purpose LIKE ''School fees%'' AND NOT finance.overpayment_decisions_covered(r.student_id, r.session, r.amount) THEN ''PAY_NOT_RECEIVED_DECIDED''   -- V781: by the arithmetic');
    EXECUTE d;
END $v781$;

-- ── 19 · old-fees maintenance leaves the records an overpayment decision or an open request rests on ──
DO $v781$
DECLARE d text; a text; a2 text;
BEGIN
    -- the old fees reset: such a record is kept in use (never deleted), in the batch and in the count of those kept
    d := pg_get_functiondef('finance.reset_legacy_payments(text,text,integer)'::regprocedure);
    a := E'                   AND NOT (finance.is_siwes_purpose(r.purpose) AND finance.siwes_group_kept(r.id))\n';
    a2 := E'                    OR (finance.is_siwes_purpose(r.purpose) AND finance.siwes_group_kept(r.id))) AS linked   -- V762';
    PERFORM pg_temp.v781_once(d, a, 'finance.reset_legacy_payments (the batch)');
    PERFORM pg_temp.v781_once(d, a2, 'finance.reset_legacy_payments (the count)');
    d := replace(d, a, a || E'                   -- V781: a school-fees record an overpayment decision stands on, or a credit request is open for, stays\n'
        || E'                   AND NOT finance.overpayment_holds_record(r.student_id, r.session, r.purpose)\n');
    d := replace(d, a2, E'                    OR (finance.is_siwes_purpose(r.purpose) AND finance.siwes_group_kept(r.id))   -- V762\n'
        || E'                    OR finance.overpayment_holds_record(r.student_id, r.session, r.purpose)) AS linked   -- V781');
    EXECUTE d;

    -- an upload that would take a record over (its session, amount and purpose rewritten) counts it as already recorded instead; so does one
    -- that would relabel a record carrying no payment number (the same money, put under another item or another reference) while something
    -- points at the record by its reference (a refund against it is read through it) or, taking it out of the school fees, a decision stands
    -- on it or a credit request is open for it
    d := pg_get_functiondef('finance.import_legacy_payments(jsonb)'::regprocedure);
    a := E'            IF ph.id IS NOT NULL AND ph.archived_at IS NOT NULL THEN';
    a2 := E'            IF ex.id IS NOT NULL AND ex.archived_at IS NOT NULL THEN\n                nd := nd + 1; v_dups := v_dups || v_ref;   -- V670: the same money is on record, archived for review';
    PERFORM pg_temp.v781_once(d, a, 'finance.import_legacy_payments');
    PERFORM pg_temp.v781_once(d, a2, 'finance.import_legacy_payments (the relabel)');
    d := replace(d, a, E'            IF ph.id IS NOT NULL AND (ph.archived_at IS NOT NULL OR finance.overpayment_holds_record(ph.student_id, ph.session, ph.purpose)) THEN   -- V781');
    d := replace(d, a2, E'            IF ex.id IS NOT NULL AND (ex.archived_at IS NOT NULL OR finance.payment_reference_linked(ex.reference, ex.id)\n'
        || E'                                      OR (v_tag NOT LIKE ''School fees%'' AND finance.overpayment_holds_record(ex.student_id, ex.session, ex.purpose))) THEN   -- V781\n'
        || E'                nd := nd + 1; v_dups := v_dups || v_ref;   -- V670: the same money is on record, archived for review (V781: or held)');
    EXECUTE d;

    -- the put-right
    d := pg_get_functiondef('finance.put_right_legacy_items(text,integer)'::regprocedure);
    a := E'        IF pr.id IS NULL THEN CONTINUE; END IF;';
    PERFORM pg_temp.v781_once(d, a, 'finance.put_right_legacy_items');
    d := replace(d, a, a || E'\n        -- V781: a record an overpayment decision stands on, or a credit request is open for, is left as it is\n'
        || E'        IF finance.overpayment_holds_record(pr.student_id, pr.session, pr.purpose) THEN CONTINUE; END IF;');
    EXECUTE d;
END $v781$;

-- ── 20 · what a student's own pages read ──
CREATE FUNCTION finance.student_excess(p_student uuid, p_session text)
 RETURNS TABLE(excess numeric, decided numeric, remaining numeric, requested numeric, cause text, holds text[])
 LANGUAGE sql STABLE AS $fn$
    SELECT p.paid - p.due, d.decided, greatest(p.paid - p.due - d.decided, 0),
           coalesce((SELECT sum(q.confirmed_amount) FROM finance.legacy_credit_request q
                      WHERE q.student_id = p_student AND q.session = p_session AND q.status IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')), 0),
           n.cause, n.holds
      FROM finance.position(p_student, p_session) p
      CROSS JOIN LATERAL (SELECT finance.overpayment_decided(p_student, p_session) AS decided) d
      LEFT JOIN finance.overpaid_snapshot n ON n.session = p_session AND n.student_id = p_student AND abs(n.excess - (p.paid - p.due)) < 1
     WHERE p.due > 0 AND p.paid - p.due >= 1
$fn$;
COMMENT ON FUNCTION finance.student_excess(uuid, text) IS 'V781: what the student''s own pages say of money paid above the charge: from finance.position (no row unless the charge is stated and NGN 1 or more is paid above it) — the excess, what is decided, what remains, what a credit request open asks for, and the cause and holds of the kept list''s row when its excess is within NGN 1 of the live one (else NULL: a new overpayment not yet listed).';

-- ── 21 · what the student and the officers are told ──
-- A student whose overpaid school fees the Bursar approved: the wallet credit is theirs to apply on the Wallet page or to ask back as a
-- refund; mandatory (it is money on their wallet).
UPDATE platform.notice_template SET
    purpose = 'To a student whose overpaid school fees the Bursar has approved and credited to their wallet',
    email_subject = 'Your overpaid school fees of [AMOUNT] are on your wallet',
    email_body = E'Dear [FIRST_NAME],\n\nThe [AMOUNT] you paid above the school fees stated for [SESSION] has been credited to your wallet (reference [REFERENCE]). Your wallet balance is now [BALANCE].\n\nWhen you next owe school fees and payment is open, apply it on the Wallet page and pay only the rest. You may also ask for it as a refund on the Wallet page once your current fees are paid: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
    sms_body = '[UNIVERSITY_SHORT]: [AMOUNT] you overpaid on [SESSION] school fees is on your wallet (ref [REFERENCE]), balance [BALANCE]. Apply it to your fees, or ask for a refund, on the Wallet page.',
    portal_title = 'Your overpaid school fees are on your wallet',
    portal_body = 'The [AMOUNT] you paid above the fees stated for [SESSION] is on your wallet (ref [REFERENCE]); your balance is [BALANCE]. Apply it to your school fees, or ask for it as a refund, on the Wallet page.',
    mandatory = true
 WHERE key = 'LEGACY_CREDIT_POSTED';
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('OVERPAID_CREDITS_WAITING', 'Wallet credits of overpaid school fees waiting for the Bursar',
 'To the Bursar''s office holders when wallet credits of overpaid school fees are requested on the Overpaid school fees desk',
 '[COUNT] wallet credit(s) of overpaid school fees wait for your approval ([BATCH])',
 E'[OFFICER] has requested that [AMOUNT] paid above the [SESSION] school fees by [COUNT] student(s) ([CAUSE]) be credited to their wallets (batch [BATCH]).\n\nApprove, return or reject them on Overpaid school fees: [PORTAL_URL]\n\nNothing is credited until a Bursary officer other than [OFFICER] approves.',
 '[UNIVERSITY_SHORT]: [COUNT] wallet credit(s) of overpaid school fees ([AMOUNT], [SESSION]) requested by [OFFICER] wait for your approval, batch [BATCH].',
 'Wallet credits [BATCH] wait for your approval',
 '[OFFICER] requested [COUNT] wallet credit(s) of [AMOUNT] ([CAUSE], [SESSION]). Approve, return or reject them on Overpaid school fees.',
 ARRAY['BATCH','COUNT','AMOUNT','SESSION','CAUSE','OFFICER','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL'),
('OVERPAID_CREDITS_DECIDED', 'Wallet credits of overpaid school fees decided',
 'To the officer who requested wallet credits of overpaid school fees when a Bursary officer approves, returns or rejects them',
 'Wallet credits [BATCH]: [COUNT] [ACTION]',
 E'[BURSAR] [ACTION] [COUNT] of the wallet credit(s) of overpaid school fees you requested ([AMOUNT], batch [BATCH]). [SKIPPED] of yours were left as they were; Overpaid school fees says why beside each: [PORTAL_URL]',
 '[UNIVERSITY_SHORT]: [COUNT] wallet credit(s) of batch [BATCH] [ACTION] by [BURSAR] ([AMOUNT]); [SKIPPED] left.',
 'Wallet credits [BATCH] [ACTION]',
 '[BURSAR] [ACTION] [COUNT] wallet credit(s) ([AMOUNT]); [SKIPPED] left as they were.',
 ARRAY['BATCH','COUNT','AMOUNT','ACTION','SKIPPED','BURSAR','UNIVERSITY_SHORT','PORTAL_URL'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 22 · what is on the wallets already (no student's name or number is written) ──
-- 1. the notes of the overpaid credits already on wallets are made plain (the evidence stays on the request)
DO $v781$
DECLARE n int;
BEGIN
    UPDATE finance.wallet_entry e SET note = 'Overpaid school fees of ' || e.session || ' credited to your wallet (' || e.reference || ')'
     WHERE e.kind = 'CREDIT' AND e.source_code = 'OVERPAID' AND e.note LIKE 'School fees overpaid on %';
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'V781: % credit(s) of overpaid school fees on wallets have their notes made plain', n;
END $v781$;

-- 2. refunds waiting under the wrong source: a refund of "own money" was recorded under source SELF whatever source held the money, and
-- the payment looks for it under SELF; when the SELF source does not hold the amount and exactly one other source of the student's own
-- money does, the refund is put under that source
DO $v781$
DECLARE w record; v_free numeric; v_alt text[]; v_fixed int := 0; v_left int := 0;
BEGIN
    FOR w IN SELECT x.* FROM finance.wallet_withdrawal x WHERE x.state IN ('REQUESTED', 'APPROVED') AND x.source_code = 'SELF' ORDER BY x.student_id, x.requested_at, x.id LOOP
        v_free := coalesce((SELECT b.available FROM finance.wallet_balances(w.student_id) b WHERE b.source_code = 'SELF'), 0)
                  - coalesce((SELECT sum(y.amount) FROM finance.wallet_withdrawal y
                               WHERE y.student_id = w.student_id AND y.source_code = 'SELF' AND y.state IN ('REQUESTED', 'APPROVED')
                                 AND (y.requested_at, y.id) < (w.requested_at, w.id)), 0);
        IF v_free >= w.amount - 0.005 THEN CONTINUE; END IF;
        v_alt := ARRAY(SELECT b.source_code FROM finance.wallet_balances(w.student_id) b
                        WHERE b.nature = 'SELF' AND b.source_code <> 'SELF' AND b.available - b.held >= w.amount - 0.005);
        IF cardinality(v_alt) = 1 THEN
            UPDATE finance.wallet_withdrawal SET source_code = v_alt[1] WHERE id = w.id;
            v_fixed := v_fixed + 1;
        ELSE
            v_left := v_left + 1;
        END IF;
    END LOOP;
    RAISE NOTICE 'V781: % refund(s) waiting under source SELF put under the source of the student''s own money that holds them', v_fixed;
    IF v_left > 0 THEN
        RAISE NOTICE 'V781: % refund(s) waiting under source SELF are left for the Bursary to look at: no one source of the student''s own money holds them', v_left;
    END IF;
END $v781$;

-- ── 23 · the triggers, last: each takes a lock on its table until the commit that follows ──
CREATE TRIGGER trg_overpayment_decision_within_excess BEFORE INSERT ON finance.overpayment_decision
    FOR EACH ROW WHEN (NEW.superseded_at IS NULL) EXECUTE FUNCTION finance.overpayment_decision_within_excess();
CREATE CONSTRAINT TRIGGER trg_overpaid_credit_by_request AFTER INSERT ON finance.wallet_entry
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (NEW.kind = 'CREDIT' AND NEW.source_code = 'OVERPAID')
    EXECUTE FUNCTION finance.overpaid_credit_by_request();

COMMIT;
