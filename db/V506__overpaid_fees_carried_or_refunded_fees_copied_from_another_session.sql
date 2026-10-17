-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V506 — Overpaid old-portal fees carried into the next session or refunded, and a session's fees copied from another
--
--   1 · Overpaid. The reconciliation of old-portal payments against the fee setup (V498) finds students who paid more than
--       the setup says was due (183 in 2025/2026 on the 13 Oct copy of the live data). The Bursary decides, a student at a time
--       or all at once, with a reason kept on each:
--       · CARRY — the excess counts towards the next session's school fees: a confirmed record in that session, "School fees
--         <next> (carried from <session>)", channel CARRIED, which every reading of what is paid counts (the fee gate, the
--         positions, the reconciliation). It is no new money: its ledger journal, written with it, moves the school-fees income
--         from the overpaid session to the next (debit and credit 4010, each line naming its session), so the sync never posts
--         it as cash;
--       · REFUND — a refund raised on the Refunds & Credits desk (finance.propose_refund, maker–checker as every refund), against
--         the payment that covers the excess when one does.
--       Each decision is kept on finance.overpayment_decision, once a student and session (a refund rejected leaves it to be
--       decided again). finance.overpaid(session) lists the overpaid with their decision; the reconciliation counts a decided
--       excess as settled (state OVER_SETTLED) and shows what was carried in.
--   2 · A session without fee lines (2024/2025: every student "no fee stated") is filled from another session:
--       finance.copy_session_fees(from, to, apply) — a preview first (apply false), then the copy — takes every live line of the
--       source session (every kind, level, entry mode, faculty, programme, fee group, semester, indigene, spillover) that the
--       target has no live line for in the same scope; a line the target already states is kept, never overwritten. The
--       Bursary then adjusts the amounts on Fee Setup as for any line.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V506: overpaid fees carried or refunded; a session''s fees copied from another', true);

-- ── 1 · overpaid ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.overpayment_decision (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,   -- a decision goes with its student (the go-live reset)
    session       text NOT NULL,
    due           numeric(14,2) NOT NULL,
    paid          numeric(14,2) NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount >= 1),
    decision      text NOT NULL CHECK (decision IN ('CARRY', 'REFUND')),
    to_session    text NULL,
    reference     text NOT NULL,
    journal       uuid NULL,
    decided_by    uuid NOT NULL,
    decided_at    timestamptz NOT NULL DEFAULT now(),
    reason        text NOT NULL,
    superseded_at timestamptz NULL,
    CONSTRAINT ck_od_carry CHECK (decision <> 'CARRY' OR to_session IS NOT NULL)
);
COMMENT ON TABLE finance.overpayment_decision IS
  'V506: what the Bursary decided for a student''s overpaid school fees of a session — CARRY (the excess a confirmed CARRIED record in the next session, its journal moving the income across) or REFUND (a refund raised on the Refunds & Credits desk) — the excess, the reference made, who, when, why; once a student and session (superseded only when a refund was rejected).';
CREATE UNIQUE INDEX uq_overpayment_decision_live ON finance.overpayment_decision (student_id, session) WHERE superseded_at IS NULL;
SELECT audit.attach('finance.overpayment_decision');

/* the session after a session, by the day it starts */
CREATE FUNCTION finance.next_session(p_session text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT n.name FROM policy.academic_session n
     WHERE n.starts_on > (SELECT a.starts_on FROM policy.academic_session a WHERE a.name = p_session)
     ORDER BY n.starts_on, n.name LIMIT 1
$fn$;
COMMENT ON FUNCTION finance.next_session(text) IS 'V506: the session that starts next after the one named (NULL when none is on the calendar).';

/* a decision that stands: not superseded, and not a refund the desk rejected */
CREATE FUNCTION finance.overpayment_settled(p_student uuid, p_session text)
RETURNS TABLE (decision text, amount numeric, reference text, to_session text, decided_at timestamptz, refund_state text)
LANGUAGE sql STABLE AS $fn$
    SELECT d.decision, d.amount, d.reference, d.to_session, d.decided_at, rf.state
      FROM finance.overpayment_decision d
      LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
     WHERE d.student_id = p_student AND d.session = p_session AND d.superseded_at IS NULL
       AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
$fn$;

-- the reconciliation (V498), restated: what was carried in, what of an excess is settled, and OVER_SETTLED
DROP FUNCTION finance.old_fees_reconciliation(text);
CREATE FUNCTION finance.old_fees_reconciliation(p_session text)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, faculty_code text, level int, due numeric, paid numeric,
               paid_old_s1 numeric, paid_old_s2 numeric, paid_old_session numeric, paid_payment_history numeric, paid_portal numeric,
               old_payments int, difference numeric, state text, carried_in numeric, settled numeric, decision text)
LANGUAGE sql STABLE AS $$
    WITH pay AS MATERIALIZED (
        SELECT r.student_id,
               sum(r.amount) AS paid,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 1'), 0) AS s1,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 2'), 0) AS s2,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose NOT LIKE '% semester _'), 0) AS whole,
               coalesce(sum(r.amount) FILTER (WHERE r.reference NOT LIKE 'MOAUM-%'), 0) AS hist,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-%' AND r.reference NOT LIKE 'MOAUM-LEG-%' AND r.channel IS DISTINCT FROM 'CARRIED'), 0) AS portal,
               coalesce(sum(r.amount) FILTER (WHERE r.channel = 'CARRIED'), 0) AS carried,
               count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%')::int AS old_n
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id
        HAVING count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%') > 0),
    ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c),
    dec AS MATERIALIZED (
        SELECT d.student_id, sum(d.amount) AS settled, string_agg(d.decision, ', ' ORDER BY d.decision) AS decision
          FROM finance.overpayment_decision d
          LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
         WHERE d.session = p_session AND d.superseded_at IS NULL AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
         GROUP BY d.student_id)
    SELECT p.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session),
           coalesce(ch.total, 0), p.paid, p.s1, p.s2, p.whole, p.hist, p.portal, p.old_n, p.paid - coalesce(ch.total, 0),
           CASE WHEN coalesce(ch.total, 0) <= 0 THEN 'NO_FEE_STATED'
                WHEN finance.fee_short(ch.total, p.paid) THEN 'UNDER'
                WHEN p.paid - ch.total >= 1 AND p.paid - ch.total - coalesce(dec.settled, 0) < 1 THEN 'OVER_SETTLED'
                WHEN p.paid - ch.total >= 1 THEN 'OVER'
                ELSE 'MATCHED' END,
           p.carried, coalesce(dec.settled, 0), dec.decision
      FROM pay p
      JOIN people.student s ON s.id = p.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ch ON ch.student_id = p.student_id
      LEFT JOIN dec ON dec.student_id = p.student_id
$$;
COMMENT ON FUNCTION finance.old_fees_reconciliation(text) IS
  'V498, V506: every student with an old-portal school-fees payment in the session — due by the fee setup (finance.session_charges), paid (old portal by semester and whole session, the retired Payment History Upload, the portal), the difference and the state: UNDER, OVER, OVER_SETTLED (the excess carried into the next session or refunded, V506), MATCHED, or NO_FEE_STATED when the setup charges the student nothing; with what was carried in from the session before and what of an excess is settled, and how.';

/* the overpaid of a session (the reconciliation's OVER and OVER_SETTLED), with the excess and the decision that stands */
CREATE FUNCTION finance.overpaid(p_session text)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, faculty_code text, level int, due numeric, paid numeric,
               excess numeric, decision text, decided numeric, reference text, to_session text, decided_at timestamptz, refund_state text)
LANGUAGE sql STABLE AS $fn$
    SELECT x.student_id, x.number, x.name, x.programme_code, x.faculty_code, x.level, x.due, x.paid, x.paid - x.due,
           d.decision, d.amount, d.reference, d.to_session, d.decided_at, d.refund_state
      FROM finance.old_fees_reconciliation(p_session) x
      LEFT JOIN LATERAL finance.overpayment_settled(x.student_id, p_session) d ON true
     WHERE x.state IN ('OVER', 'OVER_SETTLED')
$fn$;
COMMENT ON FUNCTION finance.overpaid(text) IS
  'V506: the students the reconciliation finds overpaid in the session — due, paid, the excess — with the decision that stands (CARRY or REFUND, the reference made, the next session, the refund''s state), or none.';

/* the Bursary's decision for the overpaid of a session — all not yet decided, or the students named — in batches */
CREATE FUNCTION finance.decide_overpayments(p_session text, p_decision text, p_students uuid[], p_reason text, p_limit int DEFAULT 2000)
RETURNS TABLE (carried int, refunds int, remaining int)
LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, '')); v_decision text := upper(btrim(coalesce(p_decision, '')));
        v_next text; o record; v_ref text; v_src text; v_journal uuid; v_rf text; nc int := 0; nr int := 0; v_left int;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'OVERPAY_ACTOR: an overpayment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF v_decision NOT IN ('CARRY', 'REFUND') THEN
        RAISE EXCEPTION 'OVERPAY_DECISION: an overpayment is carried into the next session (CARRY) or refunded (REFUND)' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'OVERPAY_REASON: say why (at least ten characters); it is kept with each decision' USING ERRCODE = '23514';
    END IF;
    IF v_decision = 'CARRY' THEN
        v_next := finance.next_session(p_session);
        IF v_next IS NULL THEN
            RAISE EXCEPTION 'OVERPAY_NO_NEXT_SESSION: no session follows % on the calendar to carry the excess into', p_session USING ERRCODE = '23514',
                HINT = 'Add the next session on the academic calendar, or refund the excess instead.';
        END IF;
    END IF;
    FOR o IN SELECT * FROM finance.overpaid(p_session) x
              WHERE x.decision IS NULL AND x.excess >= 1 AND (p_students IS NULL OR x.student_id = ANY (p_students))
              ORDER BY x.number LIMIT greatest(1, coalesce(p_limit, 2000)) LOOP
        PERFORM pg_advisory_xact_lock(hashtext('overpay:' || o.student_id::text || ':' || p_session));
        IF EXISTS (SELECT 1 FROM finance.overpayment_settled(o.student_id, p_session)) THEN CONTINUE; END IF;
        -- a refund the desk rejected leaves the excess to be decided again
        UPDATE finance.overpayment_decision SET superseded_at = now()
         WHERE student_id = o.student_id AND session = p_session AND superseded_at IS NULL;
        IF v_decision = 'CARRY' THEN
            v_ref := 'MOAUM-CF-' || regexp_replace(upper(o.number), '[^0-9A-Z]', '', 'g') || '-' || replace(p_session, '/', '-');
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref OR receipt_no = 'RCT-' || v_ref) THEN
                v_ref := v_ref || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
            END IF;
            INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by,
                                                   channel, note, receipt_no)
            VALUES (o.student_id, v_next, v_ref, 'School fees ' || v_next || ' (carried from ' || p_session || ')', o.excess, now(), now(), now(), v_actor,
                    'CARRIED', 'Overpaid on ' || p_session || ' (paid ' || to_char(o.paid, 'FM999,999,999,990.00') || ', due ' || to_char(o.due, 'FM999,999,999,990.00')
                               || '), carried into ' || v_next || ': ' || v_reason, 'RCT-' || v_ref);
            -- no new money: the school-fees income moves from the overpaid session to the next
            v_journal := finance.gl_post(current_date, 'School fees overpaid on ' || p_session || ' carried into ' || v_next || ' — ' || v_ref,
                                         'AUTO', 'PAYMENT', v_ref,
                jsonb_build_array(
                    jsonb_build_object('account', finance.gl_income_account('School fees'), 'debit', o.excess,
                                       'narration', 'Overpaid on ' || p_session || ', carried into ' || v_next, 'session', p_session),
                    jsonb_build_object('account', finance.gl_income_account('School fees'), 'credit', o.excess,
                                       'narration', 'Carried from ' || p_session, 'session', v_next)));
            INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, to_session, reference, journal, decided_by, reason)
            VALUES (o.student_id, p_session, o.due, o.paid, o.excess, 'CARRY', v_next, v_ref, v_journal, v_actor, v_reason);
            nc := nc + 1;
        ELSE
            -- against the latest school-fees payment of the session that covers the excess, when one does
            v_src := (SELECT r.reference FROM finance.payment_reference r
                       WHERE r.student_id = o.student_id AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
                         AND r.amount - coalesce((SELECT sum(f.amount) FROM finance.refund f WHERE f.source_reference = r.reference AND f.state <> 'REJECTED'), 0) >= o.excess
                       ORDER BY r.confirmed_at DESC, r.reference LIMIT 1);
            v_rf := finance.propose_refund(o.student_id, o.name,
                        'School fees overpaid on ' || p_session || ' (paid ' || to_char(o.paid, 'FM999,999,999,990.00') || ', due '
                        || to_char(o.due, 'FM999,999,999,990.00') || '): ' || v_reason, o.excess, NULL, NULL, NULL, v_src);
            INSERT INTO finance.overpayment_decision (student_id, session, due, paid, amount, decision, reference, decided_by, reason)
            VALUES (o.student_id, p_session, o.due, o.paid, o.excess, 'REFUND', v_rf, v_actor, v_reason);
            nr := nr + 1;
        END IF;
    END LOOP;
    SELECT count(*) INTO v_left FROM finance.overpaid(p_session) x
     WHERE x.decision IS NULL AND x.excess >= 1 AND (p_students IS NULL OR x.student_id = ANY (p_students));
    RETURN QUERY SELECT nc, nr, v_left;
END $fn$;
COMMENT ON FUNCTION finance.decide_overpayments(text, text, uuid[], text, int) IS
  'V506: the Bursary''s decision for up to p_limit overpaid students of a session not yet decided (all, or those named): CARRY — a confirmed CARRIED school-fees record of the excess in the next session, its journal moving the income across (no cash) — or REFUND — a refund raised on the Refunds & Credits desk against the payment that covers the excess; each kept on finance.overpayment_decision with the reason. Returns what was carried, refunded, and what remains undecided.';

-- ── 2 · a session's fees copied from another ─────────────────────────────────────────────────────────────────────────────────
/* two fee lines charge the same students: the same item (case and spaces aside), kind, level, entry mode, faculty, programme, fee
   group, semester, indigeneship and spillover */
CREATE FUNCTION finance.fee_line_same_scope(x finance.fee_schedule, s finance.fee_schedule)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind
       AND x.level IS NOT DISTINCT FROM s.level AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode
       AND x.faculty_code IS NOT DISTINCT FROM s.faculty_code AND x.programme_code IS NOT DISTINCT FROM s.programme_code
       AND x.fee_group IS NOT DISTINCT FROM s.fee_group AND x.semester IS NOT DISTINCT FROM s.semester
       AND x.indigene IS NOT DISTINCT FROM s.indigene AND x.spillover = s.spillover
$fn$;

CREATE FUNCTION finance.copy_session_fees(p_from text, p_to text, p_apply boolean)
RETURNS TABLE (item text, kind text, amount numeric, level int, entry_mode text, faculty_code text, programme_code text, fee_group text,
               semester int, indigene text, spillover boolean, ord int, target_amount numeric, action text)
LANGUAGE plpgsql AS $fn$
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one session into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_from AND f.ended_at IS NULL) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no fee line to copy', p_from USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    -- what each line of the source is to the target (read before anything is copied, so the answer says what the copy did);
    -- a preview writes nothing, and reads in a read-only transaction
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.fee_group, s.semester, s.indigene, s.spillover, s.ord,
           t.amount, CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.fee_schedule s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s) LIMIT 1) t ON true
     WHERE s.session = p_from AND s.ended_at IS NULL
     ORDER BY s.kind, s.ord, s.item, s.faculty_code NULLS FIRST, s.programme_code NULLS FIRST, s.level NULLS FIRST, s.semester NULLS FIRST;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, kind)
        SELECT p_to, s.item, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.ord, s.fee_group, s.semester, s.indigene, s.spillover, s.kind
          FROM finance.fee_schedule s
         WHERE s.session = p_from AND s.ended_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s));
    END IF;
END $fn$;
COMMENT ON FUNCTION finance.copy_session_fees(text, text, boolean) IS
  'V506: every live fee line of p_from, and what copying it into p_to does — COPY (the target states no live line of the same item, kind, level, entry mode, faculty, programme, fee group, semester, indigene and spillover) or KEPT (it does: never overwritten, its amount shown). p_apply false is the preview; true copies the COPY lines (a person, on the Bursary''s desk).';

COMMIT;
