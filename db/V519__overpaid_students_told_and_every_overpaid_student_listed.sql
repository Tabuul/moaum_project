-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V519 — The overpaid are told, and every overpaid student is listed
--
--   V506 let the Bursary decide an overpaid student's excess — carried into the next session, or a refund raised — but:
--   1 · the student was not told. Now, through the notification engine (V425: one message an event, the student's e-mail, phone
--       and portal), at each step: OVERPAYMENT_CARRIED (the excess counts as school fees paid in the next session),
--       OVERPAYMENT_REFUND_RAISED (a refund is waiting for the Bursary's approval) and OVERPAYMENT_REFUND_PAID (the refund
--       desk paid it: a trigger on finance.refund). finance.student_overpayments(student) is what the student's fees page shows.
--   2 · the list took only the students the old-portal reconciliation reads — those with an old-portal payment in the session.
--       A student who paid twice through the portal (a gateway timeout paid again, a reference paid twice) was never listed.
--       finance.overpaid(session) now lists every student whose school-fees payments in the session exceed what the fee setup
--       charges them, by a naira or more (finance.session_charges against finance.session_payments), marked old_portal when an
--       old-portal payment is among them.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V519: the overpaid told, and every overpaid student listed', true);

-- ── 1 · the notices ──────────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('OVERPAYMENT_CARRIED', 'Overpaid school fees carried into the next session',
 'To a student whose school fees paid beyond the session''s charge the Bursary carried into the next session',
 'Your overpaid [SESSION_FROM] school fees count towards [SESSION_TO]',
 E'Dear [FIRST_NAME],\n\nYou paid [AMOUNT] more than your [SESSION_FROM] school fees. The Bursary has carried it into [SESSION_TO]: it counts there as school fees already paid (reference [REFERENCE]), and your [SESSION_TO] balance is lower by that amount.\n\nYou can see it on your fees page: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: [AMOUNT] you overpaid on [SESSION_FROM] school fees now counts as paid towards [SESSION_TO] (ref [REFERENCE]).',
 'Overpaid fees carried into [SESSION_TO]',
 'The [AMOUNT] you paid beyond your [SESSION_FROM] school fees counts as school fees paid in [SESSION_TO] (reference [REFERENCE]).',
 ARRAY['FIRST_NAME','SESSION_FROM','SESSION_TO','AMOUNT','REFERENCE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('OVERPAYMENT_REFUND_RAISED', 'Refund of overpaid school fees raised',
 'To a student whose school fees paid beyond the session''s charge the Bursary is refunding',
 'A refund of your overpaid [SESSION_FROM] school fees has been raised',
 E'Dear [FIRST_NAME],\n\nYou paid [AMOUNT] more than your [SESSION_FROM] school fees. The Bursary has raised a refund of it (refund [REFUND]). It is approved and paid by the Bursary; you will be told when it is paid. If the Bursary needs your bank details, it will ask you.\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: a refund of [AMOUNT] you overpaid on [SESSION_FROM] school fees has been raised (refund [REFUND]). You will be told when it is paid.',
 'Refund of overpaid fees raised',
 'A refund of the [AMOUNT] you paid beyond your [SESSION_FROM] school fees has been raised (refund [REFUND]). You will be told when it is paid.',
 ARRAY['FIRST_NAME','SESSION_FROM','AMOUNT','REFUND','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL'),
('OVERPAYMENT_REFUND_PAID', 'Refund of overpaid school fees paid',
 'To a student when the refund of their overpaid school fees is paid',
 'Your refund of [AMOUNT] has been paid',
 E'Dear [FIRST_NAME],\n\nThe refund of the [AMOUNT] you paid beyond your [SESSION_FROM] school fees has been paid (refund [REFUND]).\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: your refund of [AMOUNT] (overpaid [SESSION_FROM] school fees, refund [REFUND]) has been paid.',
 'Refund paid',
 'The refund of the [AMOUNT] you paid beyond your [SESSION_FROM] school fees has been paid (refund [REFUND]).',
 ARRAY['FIRST_NAME','SESSION_FROM','AMOUNT','REFUND','PORTAL_URL','UNIVERSITY_SHORT'], true, 'NORMAL');

/* what the student is told when a refund raised for their overpaid fees is paid on the refunds desk */
CREATE FUNCTION finance.trg_overpayment_refund_paid()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE d finance.overpayment_decision;
BEGIN
    SELECT * INTO d FROM finance.overpayment_decision
     WHERE decision = 'REFUND' AND reference = NEW.reference AND superseded_at IS NULL LIMIT 1;
    IF d.id IS NOT NULL THEN
        PERFORM platform.tell_student(d.student_id, 'OVERPAYMENT_REFUND_PAID', NULL,
            jsonb_build_object('SESSION_FROM', d.session, 'AMOUNT', 'NGN ' || to_char(NEW.amount, 'FM999,999,990.00'), 'REFUND', NEW.reference),
            'overpayment-refund-paid:' || NEW.reference);
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_refund_overpayment_paid AFTER UPDATE OF state ON finance.refund
    FOR EACH ROW WHEN (NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID') EXECUTE FUNCTION finance.trg_overpayment_refund_paid();

/* a student's own overpayment decisions, for the fees page: the session overpaid, the excess, what was decided, where it went */
CREATE FUNCTION finance.student_overpayments(p_student uuid)
RETURNS TABLE (session text, amount numeric, decision text, to_session text, reference text, refund_state text, decided_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    SELECT d.session, d.amount, d.decision, d.to_session, d.reference, rf.state, d.decided_at
      FROM finance.overpayment_decision d
      LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
     WHERE d.student_id = p_student AND d.superseded_at IS NULL
     ORDER BY d.decided_at DESC
$fn$;
COMMENT ON FUNCTION finance.student_overpayments(uuid) IS
  'V519: a student''s overpaid school fees and what the Bursary decided (carried into the next session, or a refund raised, with the refund''s state) — what the student''s fees page shows.';

-- ── 2 · every overpaid student ──────────────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION finance.overpaid(text);
CREATE FUNCTION finance.overpaid(p_session text)
RETURNS TABLE (student_id uuid, number text, name text, programme_code text, faculty_code text, level int, due numeric, paid numeric,
               excess numeric, decision text, decided numeric, reference text, to_session text, decided_at timestamptz, refund_state text,
               old_portal boolean)
LANGUAGE sql STABLE AS $fn$
    WITH ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c WHERE c.total > 0),
    pay AS MATERIALIZED (SELECT p.student_id, p.total FROM finance.session_payments(p_session) p),
    old AS MATERIALIZED (
        SELECT DISTINCT r.student_id FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
           AND (r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%'))
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session),
           ch.total, pay.total, pay.total - ch.total,
           d.decision, d.amount, d.reference, d.to_session, d.decided_at, d.refund_state, old.student_id IS NOT NULL
      FROM ch
      JOIN pay ON pay.student_id = ch.student_id AND pay.total - ch.total >= 1
      JOIN people.student s ON s.id = ch.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN old ON old.student_id = ch.student_id
      LEFT JOIN LATERAL finance.overpayment_settled(ch.student_id, p_session) d ON true
$fn$;
COMMENT ON FUNCTION finance.overpaid(text) IS
  'V506, V519: every student whose school-fees payments in the session exceed what the fee setup charges them by a naira or more — due, paid, the excess — with the decision that stands (CARRY or REFUND, the reference made, the next session, the refund''s state), or none; old_portal when an old-portal payment is among the payments.';

-- the decision (V506), restated: the student told
CREATE OR REPLACE FUNCTION finance.decide_overpayments(p_session text, p_decision text, p_students uuid[], p_reason text, p_limit int DEFAULT 2000)
RETURNS TABLE (carried int, refunds int, remaining int)
LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := btrim(coalesce(p_reason, '')); v_decision text := upper(btrim(coalesce(p_decision, '')));
        v_next text; o record; v_ref text; v_src text; v_journal uuid; v_rf text; v_id uuid; nc int := 0; nr int := 0; v_left int;
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
            VALUES (o.student_id, p_session, o.due, o.paid, o.excess, 'CARRY', v_next, v_ref, v_journal, v_actor, v_reason)
            RETURNING id INTO v_id;
            -- V519: the student told
            PERFORM platform.tell_student(o.student_id, 'OVERPAYMENT_CARRIED', NULL,
                jsonb_build_object('SESSION_FROM', p_session, 'SESSION_TO', v_next, 'AMOUNT', 'NGN ' || to_char(o.excess, 'FM999,999,990.00'), 'REFERENCE', v_ref),
                'overpayment-carried:' || v_id);
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
            -- V519: the student told
            PERFORM platform.tell_student(o.student_id, 'OVERPAYMENT_REFUND_RAISED', NULL,
                jsonb_build_object('SESSION_FROM', p_session, 'AMOUNT', 'NGN ' || to_char(o.excess, 'FM999,999,990.00'), 'REFUND', v_rf),
                'overpayment-refund:' || v_rf);
            nr := nr + 1;
        END IF;
    END LOOP;
    SELECT count(*) INTO v_left FROM finance.overpaid(p_session) x
     WHERE x.decision IS NULL AND x.excess >= 1 AND (p_students IS NULL OR x.student_id = ANY (p_students));
    RETURN QUERY SELECT nc, nr, v_left;
END $fn$;
COMMENT ON FUNCTION finance.decide_overpayments(text, text, uuid[], text, int) IS
  'V506, V519: the Bursary''s decision for up to p_limit overpaid students of a session not yet decided (all, or those named): CARRY — a confirmed CARRIED school-fees record of the excess in the next session, its journal moving the income across (no cash) — or REFUND — a refund raised on the Refunds & Credits desk against the payment that covers the excess; each kept on finance.overpayment_decision with the reason, the student told (V519). Returns what was carried, refunded, and what remains undecided.';

COMMIT;
