-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V568 — The payers on the hanging desk told in one press; checkouts nobody paid counted apart from what hangs
--
--   1 · The hanging desk lists who paid, with the contact on record (dd5f62a0), but the desk could not reach them from there.
--       finance.tell_payers tells each payer on the desk what their case asks of them, through the notification engine (e-mail,
--       SMS and the portal; a postgraduate or JUPEB applicant by their own module's message), once per case and reference
--       (finance.payer_told):
--         · SHORT_PAID — Interswitch or a gateway reported less than the reference asks: the reference stays open, the payment
--           is with the Bursary; do not pay it again;
--         · REVERSED   — Interswitch reported a reversal: check whether the money came back, and see the Bursary before paying
--           again;
--         · HANGING    — a checkout on Pay on Quickteller hanging over a day (finance.hanging_setting.tell_after_hours): if you
--           paid, enter the receipt's Payment Log Id where you pay; if not, the reference is still yours to pay.
--       finance.payers_to_tell lists who would be told now; the desk says how many before it presses.
--   2 · Most of "Hanging now" were checkouts nobody went on to pay. finance.abandoned_checkouts counts a checkout of the last
--       fortnight, unconfirmed, older than finance.hanging_setting.abandon_hours (24 by default), with no receipt reported and
--       nothing from Interswitch about it, as abandoned when:
--         · NEVER_ASKED    — opened on Pay on Quickteller and Quickteller never asked after the reference since (a payer who goes on
--           to pay, on the page or at a bank, makes Quickteller ask first);
--         · NOT_PAID       — a card checkout whose gateway's last answer was that it was not paid;
--         · TOLD_NO_ANSWER — its payer was told (HANGING) that long ago, and since then neither reported a receipt nor went to
--           Quickteller with it.
--       Whatever happens next to it (Quickteller asks, a receipt, a payment) brings it back: nothing is stored, nothing cancelled.
--       The desk's "Hanging now" leaves them out; the Bursar's daily list of Pay on Quickteller payments Interswitch has not
--       reported, and the Ask Interswitch list, leave them out too (finance.paydirect_unreported restated).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V568: payers on the hanging desk told; abandoned checkouts counted apart', true);

-- ── the desk's settings ──────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.hanging_setting (
    id                boolean PRIMARY KEY DEFAULT true CHECK (id),
    abandon_hours     int NOT NULL DEFAULT 24 CHECK (abandon_hours BETWEEN 2 AND 336),
    tell_after_hours  int NOT NULL DEFAULT 24 CHECK (tell_after_hours BETWEEN 1 AND 72),
    set_at            timestamptz NULL,
    set_by            uuid NULL,
    set_office        text NULL
);
INSERT INTO finance.hanging_setting DEFAULT VALUES;
SELECT audit.attach('finance.hanging_setting');
COMMENT ON TABLE finance.hanging_setting IS
  'V568: the hanging desk''s two clocks — a checkout nobody went on to pay is abandoned after abandon_hours; a Pay on Quickteller checkout hanging tell_after_hours may be told to its payer.';

/* the Bursary sets the clocks */
CREATE FUNCTION finance.set_hanging_setting(p_abandon_hours int, p_tell_after_hours int)
RETURNS finance.hanging_setting LANGUAGE plpgsql AS $fn$
DECLARE s finance.hanging_setting; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'the hanging desk''s settings are set by a person' USING ERRCODE = '23514'; END IF;
    IF p_abandon_hours IS NULL OR p_abandon_hours NOT BETWEEN 2 AND 336 THEN
        RAISE EXCEPTION 'HANGING_ABANDON_HOURS: a checkout is abandoned after 2 to 336 hours (a fortnight)' USING ERRCODE = '23514';
    END IF;
    IF p_tell_after_hours IS NULL OR p_tell_after_hours NOT BETWEEN 1 AND 72 THEN
        RAISE EXCEPTION 'HANGING_TELL_HOURS: a hanging payer is told after 1 to 72 hours' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.hanging_setting SET abandon_hours = p_abandon_hours, tell_after_hours = p_tell_after_hours,
           set_at = now(), set_by = v_actor, set_office = nullif(current_setting('moaum.actor_office', true), '')
     WHERE id RETURNING * INTO s;
    RETURN s;
END $fn$;

-- ── 2 · checkouts nobody went on to pay ──────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.payer_told (
    reference    text NOT NULL,
    case_code    text NOT NULL CHECK (case_code IN ('SHORT_PAID', 'REVERSED', 'HANGING')),
    payer_kind   text NOT NULL CHECK (payer_kind IN ('STUDENT', 'APPLICANT', 'PG_APPLICANT', 'JUPEB')),
    reached      int NOT NULL,
    told_at      timestamptz NOT NULL DEFAULT now(),
    told_by      uuid NOT NULL,
    told_office  text NULL,
    PRIMARY KEY (reference, case_code)
);
SELECT audit.attach('finance.payer_told');
COMMENT ON TABLE finance.payer_told IS
  'V568: each payer the hanging desk told, once per case and reference — SHORT_PAID, REVERSED, HANGING — with how many messages reached them.';

/* the checkouts of the last p_days nobody went on to pay: the latest checkout of each reference, unconfirmed, older than the desk's
   abandon_hours, no receipt reported and nothing from Interswitch about it, and Quickteller never asked after it (Pay on Quickteller),
   the gateway's last answer that it was not paid (a card), or its payer told that long ago with no answer since */
CREATE FUNCTION finance.abandoned_checkouts(p_at timestamptz DEFAULT now(), p_days int DEFAULT 14)
RETURNS TABLE (reference text, gateway text, opened_at timestamptz, rule text, why text)
LANGUAGE sql STABLE AS $fn$
WITH s AS (SELECT coalesce((SELECT h.abandon_hours FROM finance.hanging_setting h WHERE h.id), 24) AS hours),
a AS MATERIALIZED (
    SELECT DISTINCT ON (x.reference) x.reference, x.gateway, x.opened_at
      FROM finance.gateway_attempt x
     WHERE x.opened_at > p_at - make_interval(days => p_days) AND x.opened_at <= p_at
     ORDER BY x.reference, x.opened_at DESC),
c AS MATERIALIZED (
    SELECT a.* FROM a CROSS JOIN s
     WHERE a.opened_at <= p_at - make_interval(hours => s.hours)
       AND (SELECT st.confirmed_at FROM finance.reference_state(a.reference) st LIMIT 1) IS NULL
       -- a receipt the payer reported, or anything Interswitch sent about it, and it is not abandoned
       AND NOT EXISTS (SELECT 1 FROM finance.paydirect_claim k WHERE k.reference = a.reference)
       AND NOT EXISTS (SELECT 1 FROM finance.paydirect_inbox i WHERE i.reference = a.reference)
       AND NOT EXISTS (SELECT 1 FROM finance.gateway_event e WHERE e.reference = a.reference AND e.source = 'WEBHOOK'))
SELECT c.reference, c.gateway, c.opened_at, r.rule,
       CASE r.rule WHEN 'NEVER_ASKED' THEN 'Opened on Pay on Quickteller; Quickteller never asked after the reference since'
                   WHEN 'NOT_PAID' THEN 'The gateway''s last answer: not paid'
                   ELSE 'The payer was told ' || to_char(t.told_at AT TIME ZONE 'Africa/Lagos', 'DD Mon') || '; no receipt, and not taken to Quickteller since' END
  FROM c CROSS JOIN s
  LEFT JOIN finance.payer_told t ON t.reference = c.reference AND t.case_code = 'HANGING'
  CROSS JOIN LATERAL (
      SELECT CASE
               WHEN c.gateway = 'paydirect' AND NOT EXISTS (
                        SELECT 1 FROM finance.gateway_event v
                         WHERE v.reference = c.reference AND v.gateway = 'paydirect' AND v.source = 'VALIDATE' AND v.outcome = 'VALID'
                           AND coalesce(v.last_at, v.received_at) >= c.opened_at - interval '10 minutes') THEN 'NEVER_ASKED'
               WHEN c.gateway <> 'paydirect' AND (
                        SELECT v.outcome FROM finance.gateway_event v
                         WHERE v.reference = c.reference AND v.source IN ('SWEEP', 'VERIFY')
                           AND coalesce(v.last_at, v.received_at) >= c.opened_at
                         ORDER BY coalesce(v.last_at, v.received_at) DESC LIMIT 1) = 'NOT_SUCCESSFUL' THEN 'NOT_PAID'
               WHEN t.told_at <= p_at - make_interval(hours => s.hours) AND NOT EXISTS (
                        SELECT 1 FROM finance.gateway_event v
                         WHERE v.reference = c.reference AND v.source = 'VALIDATE' AND v.outcome = 'VALID'
                           AND coalesce(v.last_at, v.received_at) > t.told_at) THEN 'TOLD_NO_ANSWER'
             END AS rule) r
 WHERE r.rule IS NOT NULL
$fn$;
COMMENT ON FUNCTION finance.abandoned_checkouts(timestamptz, int) IS
  'V568: the checkouts of the last p_days nobody went on to pay — unconfirmed, older than finance.hanging_setting.abandon_hours, no receipt and nothing from Interswitch, and NEVER_ASKED (Quickteller never asked after the reference since it was opened), NOT_PAID (a card gateway''s last answer) or TOLD_NO_ANSWER (its payer told that long ago, no answer since). Computed, never stored: whatever happens next brings it back.';

/* V477's Pay on Quickteller payments Interswitch has not reported, without the checkouts nobody went on to pay: the Bursar's daily
   e-mail and the Ask Interswitch list read it */
CREATE OR REPLACE FUNCTION finance.paydirect_unreported(p_at timestamptz DEFAULT now(), p_hours int DEFAULT 24, p_days int DEFAULT 14)
RETURNS TABLE(reference text, payer text, number text, amount numeric, opened_at timestamptz, hours int)
LANGUAGE sql STABLE AS $fn$
    WITH ab AS MATERIALIZED (SELECT b.reference FROM finance.abandoned_checkouts(p_at, p_days) b)
    SELECT a.reference,
           coalesce(s.surname || ', ' || s.other_names, c.surname || ', ' || c.other_names),
           coalesce(s.matric_no, s.admission_no, ap.application_no),
           st.amount, a.opened_at, (extract(epoch FROM p_at - a.opened_at) / 3600)::int
      FROM finance.gateway_attempt a
      LEFT JOIN LATERAL finance.reference_state(a.reference) st ON true
      LEFT JOIN finance.payment_reference pr ON pr.reference = a.reference
      LEFT JOIN people.student s ON s.id = pr.student_id
      LEFT JOIN admissions.fee_reference fr ON fr.reference = a.reference
      LEFT JOIN admissions.application ap ON ap.id = fr.application_id
      LEFT JOIN admissions.candidate c ON c.id = ap.candidate_id
     WHERE a.gateway = 'paydirect'
       AND a.opened_at <= p_at - make_interval(hours => p_hours) AND a.opened_at > p_at - make_interval(days => p_days)
       AND st.confirmed_at IS NULL
       AND a.id = (SELECT x.id FROM finance.gateway_attempt x WHERE x.reference = a.reference ORDER BY x.opened_at DESC LIMIT 1)
       AND NOT EXISTS (SELECT 1 FROM ab WHERE ab.reference = a.reference)
     ORDER BY a.opened_at
$fn$;
COMMENT ON FUNCTION finance.paydirect_unreported(timestamptz, int, int) IS
  'V477, V568: the references opened on Pay on Quickteller (PayDirect) more than p_hours before and in the last p_days with nothing confirmed — Interswitch has not reported them — leaving out the checkouts nobody went on to pay (finance.abandoned_checkouts).';

-- ── 1 · the payers told ──────────────────────────────────────────────────────────────────────────────────────────────────
/* who the desk would tell now, by case: a short payment or a reversal not yet resolved, a Pay on Quickteller checkout hanging over
   tell_after_hours in the desk's three days (not abandoned, no receipt reported) — each reference not yet told of its case */
CREATE FUNCTION finance.payers_to_tell(p_at timestamptz DEFAULT now())
RETURNS TABLE (reference text, case_code text, paid numeric, due numeric, at timestamptz, gateway text)
LANGUAGE sql STABLE AS $fn$
WITH s AS (SELECT coalesce((SELECT h.tell_after_hours FROM finance.hanging_setting h WHERE h.id), 24) AS hours),
ab AS MATERIALIZED (SELECT b.reference FROM finance.abandoned_checkouts(p_at, 14) b),
ev AS (
    SELECT DISTINCT ON (upper(e.reference), e.outcome) upper(e.reference) AS reference, e.outcome AS case_code, e.amount AS paid,
           coalesce(e.last_at, e.received_at) AS at, e.gateway
      FROM finance.gateway_event e
     WHERE e.outcome IN ('SHORT_PAID', 'REVERSED') AND e.resolved_at IS NULL AND e.reference IS NOT NULL
     ORDER BY upper(e.reference), e.outcome, coalesce(e.last_at, e.received_at) DESC),
hang AS (
    SELECT a.reference, 'HANGING'::text AS case_code, NULL::numeric AS paid, a.opened_at AS at, a.gateway
      FROM finance.gateway_attempt a CROSS JOIN s
     WHERE a.gateway = 'paydirect' AND a.opened_at > p_at - interval '3 days' AND a.opened_at <= p_at - make_interval(hours => s.hours)
       AND a.id = (SELECT x.id FROM finance.gateway_attempt x WHERE x.reference = a.reference ORDER BY x.opened_at DESC LIMIT 1)
       AND NOT EXISTS (SELECT 1 FROM finance.paydirect_claim k WHERE k.reference = a.reference)
       AND NOT EXISTS (SELECT 1 FROM ab WHERE ab.reference = a.reference)),
every AS (SELECT * FROM ev UNION ALL SELECT * FROM hang)
SELECT w.reference, w.case_code, w.paid, st.amount, w.at, w.gateway
  FROM every w
  CROSS JOIN LATERAL (SELECT r.amount, r.confirmed_at FROM finance.reference_state(w.reference) r LIMIT 1) st
 WHERE NOT EXISTS (SELECT 1 FROM finance.payer_told t WHERE t.reference = w.reference AND t.case_code = w.case_code)
   -- a short payment or a hanging checkout is told only while the reference is unconfirmed; a reversal whatever it reversed
   AND (w.case_code = 'REVERSED' OR st.confirmed_at IS NULL)
$fn$;
COMMENT ON FUNCTION finance.payers_to_tell(timestamptz) IS
  'V568: the payers the hanging desk would tell now — SHORT_PAID and REVERSED events not resolved, Pay on Quickteller checkouts hanging over finance.hanging_setting.tell_after_hours in the last three days (not abandoned, no receipt reported) — each reference once per case.';

/* the payers told, each by the address the portal reaches them at and once per case: returns how many were told, by case, and
   how many could not be reached (left to be told when they can) */
CREATE FUNCTION finance.tell_payers(p_case text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE w record; v_student uuid; v_app uuid; v_pg uuid; v_jupeb uuid; v_kind text; v_key text; n int; vars jsonb; m record; v_body text;
        v_told int := 0; v_unreached int := 0; v_by jsonb := '{}'::jsonb;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'TELL_PAYERS_ACTOR: payers are told by a person on the desk' USING ERRCODE = '23514'; END IF;
    IF p_case IS NOT NULL AND p_case NOT IN ('SHORT_PAID', 'REVERSED', 'HANGING') THEN
        RAISE EXCEPTION 'TELL_PAYERS_CASE: the cases told are SHORT_PAID, REVERSED and HANGING' USING ERRCODE = '23514';
    END IF;
    FOR w IN SELECT * FROM finance.payers_to_tell() x WHERE p_case IS NULL OR x.case_code = p_case ORDER BY x.at LOOP
        v_student := NULL; v_app := NULL; v_pg := NULL; v_jupeb := NULL; n := 0;
        SELECT student_id INTO v_student FROM finance.payment_reference WHERE reference = w.reference;
        IF v_student IS NULL THEN SELECT application_id INTO v_app FROM admissions.fee_reference WHERE reference = w.reference; END IF;
        IF v_student IS NULL AND v_app IS NULL THEN SELECT application_id INTO v_pg FROM admissions.pg_fee_reference WHERE upper(reference) = w.reference; END IF;
        IF v_student IS NULL AND v_app IS NULL AND v_pg IS NULL THEN SELECT application_id INTO v_jupeb FROM jupeb.fee_reference WHERE upper(reference) = w.reference; END IF;
        v_kind := CASE WHEN v_student IS NOT NULL THEN 'STUDENT' WHEN v_app IS NOT NULL THEN 'APPLICANT' WHEN v_pg IS NOT NULL THEN 'PG_APPLICANT'
                       WHEN v_jupeb IS NOT NULL THEN 'JUPEB' END;
        CONTINUE WHEN v_kind IS NULL;
        v_key := CASE w.case_code WHEN 'SHORT_PAID' THEN 'PAYER_SHORT_PAID' WHEN 'REVERSED' THEN 'PAYER_REVERSED' ELSE 'PAYER_CHECKOUT_HANGING' END;
        vars := jsonb_build_object(
            'REFERENCE', w.reference,
            'PAID', CASE WHEN w.paid IS NULL THEN 'the amount' ELSE '₦' || to_char(w.paid, 'FM999,999,999,990.00') END,
            'DUE', CASE WHEN w.due IS NULL THEN 'its amount' ELSE '₦' || to_char(w.due, 'FM999,999,999,990.00') END,
            'ON', to_char(w.at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY'));
        IF v_student IS NOT NULL THEN
            n := platform.tell_student(v_student, v_key, NULL, vars, 'payer-told:' || w.case_code || ':' || w.reference);
        ELSIF v_app IS NOT NULL THEN
            n := platform.tell_applicant(v_app, v_key, NULL, vars, 'payer-told:' || w.case_code || ':' || w.reference);
        ELSE
            -- a postgraduate or JUPEB applicant is told by their own module's message (it greets and signs), in the template's
            -- e-mail words
            SELECT * INTO m FROM platform.render(v_key, NULL, 'EMAIL', vars || jsonb_build_object('FIRST_NAME', 'applicant'));
            v_body := regexp_replace(regexp_replace(m.body, E'^Dear [^\\n]*\\n\\n', ''), E'\\n\\nMOAUM Portal\\s*$', '');
            IF v_pg IS NOT NULL THEN PERFORM admissions.pg_tell_applicant(v_pg, m.subject, v_body);
            ELSE PERFORM jupeb.tell(v_jupeb, m.subject, v_body); END IF;
            n := 1;
        END IF;
        IF coalesce(n, 0) = 0 THEN
            v_unreached := v_unreached + 1;   -- no address on record: told when one is
            CONTINUE;
        END IF;
        INSERT INTO finance.payer_told (reference, case_code, payer_kind, reached, told_by, told_office)
        VALUES (w.reference, w.case_code, v_kind, n, v_actor, v_office) ON CONFLICT DO NOTHING;
        v_told := v_told + 1;
        v_by := jsonb_set(v_by, ARRAY[w.case_code], to_jsonb(coalesce((v_by->>w.case_code)::int, 0) + 1));
    END LOOP;
    RETURN jsonb_build_object('told', v_told, 'unreached', v_unreached, 'byCase', v_by);
END $fn$;
COMMENT ON FUNCTION finance.tell_payers(text) IS
  'V568: each payer finance.payers_to_tell lists (of one case, or every case) told by the notification engine — e-mail, SMS and the portal — or a postgraduate or JUPEB applicant by their module''s message; recorded once per case and reference in finance.payer_told; a payer with no address on record is counted unreached and left to be told.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYER_SHORT_PAID', 'Payment less than the reference asks',
 'To a payer when Interswitch or a gateway reported less than the reference asks: the reference stays open and the payment is with the Bursary',
 'Your payment for [REFERENCE] was less than it asks',
 E'Dear [FIRST_NAME],\n\nA payment of [PAID] was reported against your reference [REFERENCE], which asks [DUE]. The portal confirms a reference only when its whole amount arrives, so [REFERENCE] is still open, and the [PAID] you paid is with the Bursary.\n\nDo not pay [REFERENCE] again. Contact the Bursary with your payment receipt, so it settles the payment with you.\n\nMOAUM Portal',
 'MOAUM: [PAID] was reported against [REFERENCE], which asks [DUE]. It is not confirmed. Do not pay it again; contact the Bursary with your receipt.',
 'Payment less than the reference asks',
 'A payment of [PAID] was reported against [REFERENCE], which asks [DUE]. The reference stays open and your payment is with the Bursary. Do not pay it again; contact the Bursary with your receipt.',
 ARRAY['FIRST_NAME','REFERENCE','PAID','DUE','ON','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL'),
('PAYER_REVERSED', 'Payment reversed by Interswitch',
 'To a payer when Interswitch reported a reversal of a payment made against their reference',
 'Interswitch reported a reversal on [REFERENCE]',
 E'Dear [FIRST_NAME],\n\nInterswitch reported a reversal of [PAID] paid against your reference [REFERENCE] on [ON]. A reversal usually means the money was returned to the account it came from.\n\nCheck your bank account. If the money came back, the payment did not go through: contact the Bursary before you pay again. If it did not come back, contact the Bursary with your payment receipt and your bank''s debit details, so the payment is settled.\n\nMOAUM Portal',
 'MOAUM: Interswitch reported a reversal of [PAID] on [REFERENCE]. Check your bank account, then contact the Bursary before paying again.',
 'Payment reversed by Interswitch',
 'Interswitch reported a reversal of [PAID] paid against [REFERENCE]. Check whether the money came back to your account, and contact the Bursary before you pay again.',
 ARRAY['FIRST_NAME','REFERENCE','PAID','DUE','ON','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL'),
('PAYER_CHECKOUT_HANGING', 'Pay on Quickteller payment not reported',
 'To a payer whose Pay on Quickteller checkout has hung over a day: if they paid, the receipt''s Payment Log Id; if not, the reference is still theirs to pay',
 'Your Pay on Quickteller payment for [REFERENCE] has not been reported',
 E'Dear [FIRST_NAME],\n\nYou started paying [DUE] for [REFERENCE] on Pay on Quickteller on [ON], and Interswitch has not reported a payment to the portal.\n\nIf you paid, enter the Payment Log Id from your Quickteller or bank receipt where you pay on the portal ([PORTAL_URL]); the Bursary then asks Interswitch for it. If you did not pay, nothing is needed: pay when you are ready.\n\nDo not pay the same reference twice.\n\nMOAUM Portal',
 'MOAUM: Your Pay on Quickteller payment for [REFERENCE] was not reported. If you paid, enter the receipt''s Payment Log Id on the portal. If not, pay when ready.',
 'Pay on Quickteller payment not reported',
 'Interswitch has not reported a payment for [REFERENCE], started on [ON]. If you paid, enter the Payment Log Id from your receipt where you pay. If you did not, pay when you are ready.',
 ARRAY['FIRST_NAME','REFERENCE','PAID','DUE','ON','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

COMMIT;
