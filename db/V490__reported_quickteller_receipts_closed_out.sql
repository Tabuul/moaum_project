-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V490 — Reported Pay on Quickteller receipts closed out, and the ICT Support Desk takes them
--
--   V480 let a payer report the receipt of a Pay on Quickteller payment Interswitch has not reported. Until now such a receipt
--   only waited. Now:
--   · Where the receipt's Payment Log Id has been seen. Interswitch's notifications carry it (finance.gateway_event.gateway_ref)
--     and its collections report carries it (finance.paydirect_collection.rrn). A receipt is CONFIRMED when its reference
--     stands confirmed; SEEN when Interswitch reported that Payment Log Id for this reference without settling it (short of
--     the amount, say); ELSEWHERE when Interswitch reported it against another reference (a payer who typed another number
--     on Quickteller) — the Bursary's to settle, not Interswitch's to re-send; WAITING otherwise.
--   · The Bursary marks a receipt NOT_FOUND with a note when Interswitch has no such payment; the payer is told and reads the
--     note on their pay screen. A corrected receipt from the payer (or the desk) reopens it; the Bursary may reopen it too.
--   · The list Interswitch is sent (finance.paydirect_ask_list) holds only what Interswitch can answer: the WAITING receipts
--     and the unreported references with no receipt the Bursary has already settled one way or another.
--   · The Bursary's daily e-mail (V477) counts the receipts that wait on it beside the unreported payments.
--   · The ICT Support Desk records a caller's receipt on their reference (PAYMENT_RECEIPT_REPORTED on the support ledger).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V490: reported Quickteller receipts closed out', true);

-- ── the Bursary's word on a receipt ──
ALTER TABLE finance.paydirect_claim
    ADD COLUMN not_found_at     timestamptz NULL,
    ADD COLUMN not_found_by     uuid NULL,
    ADD COLUMN not_found_office text NULL,
    ADD COLUMN not_found_note   text NULL,
    ADD CONSTRAINT ck_pdc_not_found CHECK ((not_found_at IS NULL) = (not_found_note IS NULL)),
    ADD CONSTRAINT ck_pdc_not_found_note CHECK (not_found_note IS NULL OR length(btrim(not_found_note)) BETWEEN 10 AND 500);
COMMENT ON COLUMN finance.paydirect_claim.not_found_note IS
  'V490: the Bursary''s note when Interswitch has no payment for the receipt''s Payment Log Id; the payer reads it. Cleared when the receipt is corrected or reopened';

-- a Payment Log Id as typed and as Interswitch writes it compare alike: letters and digits only, upper case
CREATE OR REPLACE FUNCTION finance.log_id_key(p text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $fn$
    SELECT nullif(upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')), '')
$fn$;
CREATE INDEX ix_ge_paydirect_log_id ON finance.gateway_event (finance.log_id_key(gateway_ref))
    WHERE gateway = 'paydirect' AND gateway_ref IS NOT NULL;
CREATE INDEX ix_pdc_log_id ON finance.paydirect_collection (finance.log_id_key(rrn)) WHERE rrn IS NOT NULL;

/* the latest sighting of a Payment Log Id: in Interswitch's notifications, or in its collections report */
CREATE OR REPLACE FUNCTION finance.paydirect_log_sighting(p_log_id text)
RETURNS TABLE(reference text, seen_in text, outcome text, seen_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    SELECT s.reference, s.seen_in, s.outcome, s.seen_at FROM (
        SELECT upper(btrim(e.reference)) AS reference, 'NOTIFICATION' AS seen_in, e.outcome, e.received_at AS seen_at
          FROM finance.gateway_event e
         WHERE e.gateway = 'paydirect' AND e.gateway_ref IS NOT NULL AND e.source = 'WEBHOOK'
           AND finance.log_id_key(e.gateway_ref) = finance.log_id_key(p_log_id) AND e.reference IS NOT NULL
        UNION ALL
        SELECT upper(btrim(c.prn)), 'COLLECTIONS', c.state, c.imported_at
          FROM finance.paydirect_collection c
         WHERE c.rrn IS NOT NULL AND finance.log_id_key(c.rrn) = finance.log_id_key(p_log_id)) s
     ORDER BY s.seen_at DESC
     LIMIT 1
$fn$;
COMMENT ON FUNCTION finance.paydirect_log_sighting(text) IS
  'V490: where Interswitch last reported a Payment Log Id — a payment notification or the collections report — and against which reference';

/* the payer's report (V480), a corrected one reopening a receipt the Bursary marked not found */
CREATE OR REPLACE FUNCTION finance.paydirect_claim_set(p_reference text, p_account uuid, p_log_id text, p_paid_on date, p_amount numeric,
                                                      p_channel text, p_note text)
RETURNS finance.paydirect_claim LANGUAGE plpgsql AS $fn$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); st record; c finance.paydirect_claim;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO st FROM finance.reference_state(v_ref);
    IF st.confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'PAY_CLAIM_CONFIRMED: % is already confirmed; its receipt is on the payment', v_ref USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_log_id, ''))) < 3 THEN
        RAISE EXCEPTION 'PAY_CLAIM_LOG_ID: the receipt''s Payment Log Id is what finds the payment' USING ERRCODE = '23514';
    END IF;
    -- the day paid as the receipt prints it: a Lagos calendar day, whatever the database's own time zone
    IF p_paid_on IS NULL OR p_paid_on > (now() AT TIME ZONE 'Africa/Lagos')::date OR p_paid_on < (now() AT TIME ZONE 'Africa/Lagos')::date - 120 THEN
        RAISE EXCEPTION 'PAY_CLAIM_DATE: the day paid is today or in the last four months, as the receipt shows' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.paydirect_claim (reference, account_id, payment_log_id, paid_on, amount, channel, note, claimed_by, claimed_office)
    VALUES (v_ref, p_account, btrim(p_log_id), p_paid_on, p_amount, nullif(upper(btrim(coalesce(p_channel, ''))), ''),
            nullif(btrim(coalesce(p_note, '')), ''), v_actor, v_office)
    ON CONFLICT (reference) DO UPDATE SET account_id = EXCLUDED.account_id, payment_log_id = EXCLUDED.payment_log_id, paid_on = EXCLUDED.paid_on,
           amount = EXCLUDED.amount, channel = EXCLUDED.channel, note = EXCLUDED.note, claimed_at = now(),
           claimed_by = EXCLUDED.claimed_by, claimed_office = EXCLUDED.claimed_office,
           not_found_at = NULL, not_found_by = NULL, not_found_office = NULL, not_found_note = NULL
    RETURNING * INTO c;
    RETURN c;
END $fn$;

/* the receipts in the period (or the one for a reference, whatever its age), each with where its Payment Log Id was seen
   and its state: CONFIRMED, NOT_FOUND, ELSEWHERE, SEEN, WAITING */
DROP FUNCTION finance.paydirect_claims(int);
CREATE FUNCTION finance.paydirect_claims(p_days int DEFAULT 30, p_reference text DEFAULT NULL)
RETURNS TABLE(reference text, payer text, number text, due numeric, payment_log_id text, paid_on date, amount numeric, channel text, note text,
              claimed_at timestamptz, claimed_office text, confirmed_at timestamptz, state text, seen_reference text, seen_in text,
              seen_outcome text, seen_at timestamptz, not_found_at timestamptz, not_found_note text, not_found_office text)
LANGUAGE sql STABLE AS $fn$
    SELECT x.* FROM (
        SELECT cl.reference,
               coalesce(s.surname || ', ' || s.other_names, c.surname || ', ' || c.other_names, ja.surname || ', ' || concat_ws(' ', ja.first_name, ja.middle_name)),
               coalesce(s.matric_no, s.admission_no, ap.application_no, ja.application_no),
               st.amount, cl.payment_log_id, cl.paid_on, cl.amount, cl.channel, cl.note, cl.claimed_at, cl.claimed_office, st.confirmed_at,
               CASE WHEN st.confirmed_at IS NOT NULL THEN 'CONFIRMED'
                    WHEN cl.not_found_at IS NOT NULL THEN 'NOT_FOUND'
                    WHEN sg.reference IS NOT NULL AND sg.reference <> cl.reference THEN 'ELSEWHERE'
                    WHEN sg.reference IS NOT NULL THEN 'SEEN'
                    ELSE 'WAITING' END AS k_state,
               sg.reference, sg.seen_in, sg.outcome, sg.seen_at, cl.not_found_at, cl.not_found_note, cl.not_found_office
          FROM finance.paydirect_claim cl
          LEFT JOIN LATERAL finance.reference_state(cl.reference) st ON true
          LEFT JOIN LATERAL finance.paydirect_log_sighting(cl.payment_log_id) sg ON true
          LEFT JOIN finance.payment_reference pr ON pr.reference = cl.reference
          LEFT JOIN people.student s ON s.id = pr.student_id
          LEFT JOIN admissions.fee_reference fr ON fr.reference = cl.reference
          LEFT JOIN admissions.application ap ON ap.id = fr.application_id
          LEFT JOIN admissions.candidate c ON c.id = ap.candidate_id
          LEFT JOIN jupeb.fee_reference jf ON upper(jf.reference) = cl.reference
          LEFT JOIN jupeb.application ja ON ja.id = jf.application_id
         WHERE CASE WHEN p_reference IS NULL THEN cl.claimed_at > now() - make_interval(days => p_days)
                    ELSE cl.reference = upper(btrim(p_reference)) END) x
     ORDER BY x.k_state = 'CONFIRMED', x.k_state = 'NOT_FOUND', x.claimed_at
$fn$;
COMMENT ON FUNCTION finance.paydirect_claims(int, text) IS
  'V480, V490: the receipts payers reported for Pay on Quickteller payments — in the period, or the one for a reference — with where the Payment Log Id was seen and the state (CONFIRMED, NOT_FOUND, ELSEWHERE, SEEN, WAITING), those needing the Bursary first.';

/* what the Bursary sends Interswitch (V480): only what Interswitch can answer — the WAITING receipts, and the unreported
   references with no receipt the Bursary has settled another way (marked not found, seen elsewhere, seen short) */
CREATE OR REPLACE FUNCTION finance.paydirect_ask_list(p_days int DEFAULT 14)
RETURNS TABLE(reference text, payer text, number text, due numeric, opened_at timestamptz, payment_log_id text, paid_on date, paid_amount numeric, channel text)
LANGUAGE sql STABLE AS $fn$
    WITH every AS (SELECT * FROM finance.paydirect_claims(p_days) x),
    u AS (SELECT * FROM finance.paydirect_unreported(now(), 1, p_days) y
           WHERE NOT EXISTS (SELECT 1 FROM every e WHERE e.reference = y.reference AND e.state <> 'WAITING')),
    cl AS (SELECT * FROM every e WHERE e.state = 'WAITING')
    SELECT coalesce(u.reference, cl.reference), coalesce(u.payer, cl.payer), coalesce(u.number, cl.number), coalesce(u.amount, cl.due),
           u.opened_at, cl.payment_log_id, cl.paid_on, cl.amount, cl.channel
      FROM u FULL JOIN cl ON cl.reference = u.reference
     ORDER BY coalesce(u.opened_at, cl.claimed_at)
$fn$;

/* the Bursary's word: NOT_FOUND with a note (the payer told), or reopened */
CREATE OR REPLACE FUNCTION finance.paydirect_claim_mark(p_reference text, p_not_found boolean, p_note text)
RETURNS finance.paydirect_claim LANGUAGE plpgsql AS $fn$
DECLARE v_ref text := upper(btrim(coalesce(p_reference, ''))); c finance.paydirect_claim; st record; vars jsonb; v_student uuid; v_app uuid; v_jupeb uuid;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_event text;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'PAY_CLAIM_ACTOR: a receipt is marked by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM finance.paydirect_claim WHERE reference = v_ref FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAY_CLAIM_NONE: no receipt is reported for %', v_ref USING ERRCODE = '23514';
    END IF;
    SELECT * INTO st FROM finance.reference_state(v_ref);
    IF st.confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'PAY_CLAIM_CONFIRMED: % is already confirmed; its receipt is on the payment', v_ref USING ERRCODE = '23514';
    END IF;
    IF NOT p_not_found THEN
        UPDATE finance.paydirect_claim SET not_found_at = NULL, not_found_by = NULL, not_found_office = NULL, not_found_note = NULL
         WHERE id = c.id RETURNING * INTO c;
        RETURN c;
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'PAY_CLAIM_NOTE: say what Interswitch answered, so the payer knows what to check (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.paydirect_claim SET not_found_at = now(), not_found_by = v_actor, not_found_office = v_office, not_found_note = left(btrim(p_note), 500)
     WHERE id = c.id RETURNING * INTO c;

    -- the payer is told, on the address the portal reaches them at
    vars := jsonb_build_object('REFERENCE', c.reference, 'LOG_ID', c.payment_log_id,
                               'PAID_ON', to_char(c.paid_on, 'FMDD Mon YYYY'), 'NOTE', c.not_found_note);
    v_event := 'paydirect-receipt-not-found:' || c.reference || ':' || to_char(c.not_found_at, 'YYYYMMDDHH24MISS');
    SELECT student_id INTO v_student FROM finance.payment_reference WHERE reference = c.reference;
    SELECT application_id INTO v_app FROM admissions.fee_reference WHERE reference = c.reference;
    SELECT application_id INTO v_jupeb FROM jupeb.fee_reference WHERE upper(reference) = c.reference;
    IF v_student IS NOT NULL THEN
        PERFORM platform.tell_student(v_student, 'PAYDIRECT_RECEIPT_NOT_FOUND', NULL, vars, v_event);
    ELSIF v_app IS NOT NULL THEN
        PERFORM platform.tell_applicant(v_app, 'PAYDIRECT_RECEIPT_NOT_FOUND', NULL, vars, v_event);
    ELSIF v_jupeb IS NOT NULL THEN
        PERFORM jupeb.tell(v_jupeb, 'Your Quickteller receipt was not found',
            format(E'The Bursary asked Interswitch about the receipt you reported for %s (Payment Log Id %s, paid %s) and could not find the payment:\n\n%s\n\nCheck the Payment Log Id on your receipt. If it was mistyped, correct it on your JUPEB portal; otherwise contact the Bursary with the receipt and your bank''s debit details. Do not pay the same reference twice.',
                   c.reference, c.payment_log_id, to_char(c.paid_on, 'FMDD Mon YYYY'), c.not_found_note));
    END IF;
    RETURN c;
END $fn$;
COMMENT ON FUNCTION finance.paydirect_claim_mark(text, boolean, text) IS
  'V490: the Bursary marks a reported receipt not found at Interswitch, with a note the payer is told and reads on their pay screen; or reopens it. A confirmed reference is refused';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYDIRECT_RECEIPT_NOT_FOUND', 'Quickteller receipt not found',
 'To a payer when the Bursary could not find at Interswitch the Pay on Quickteller payment whose receipt they reported',
 'Your Quickteller receipt for [REFERENCE] was not found',
 E'Dear [FIRST_NAME],\n\nThe Bursary asked Interswitch about the receipt you reported for [REFERENCE] (Payment Log Id [LOG_ID], paid [PAID_ON]) and could not find the payment:\n\n[NOTE]\n\nCheck the Payment Log Id on your receipt. If it was mistyped, correct it where you pay on the portal; otherwise contact the Bursary with the receipt and your bank''s debit details. Do not pay the same reference twice.\n\nMOAUM Portal',
 NULL,
 'Quickteller receipt not found',
 'The Bursary could not find at Interswitch the payment for receipt [LOG_ID] ([REFERENCE]): [NOTE] Check the Payment Log Id on your receipt and correct it if it was mistyped.',
 ARRAY['FIRST_NAME','REFERENCE','LOG_ID','PAID_ON','NOTE','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

-- ── the Bursary's daily e-mail (V477): the receipts that wait on it beside the unreported payments ──
/* what waits on the Bursary: unreported a day after it was opened (V477) unless its receipt is marked not found, and every
   receipt waiting for Interswitch, seen short, or seen against another reference */
CREATE OR REPLACE FUNCTION finance.paydirect_waiting(p_at timestamptz DEFAULT now())
RETURNS TABLE(reference text, payer text, number text, amount numeric, since timestamptz, log_id text, paid_on date, state text, seen_reference text)
LANGUAGE sql STABLE AS $fn$
    WITH u AS (SELECT y.reference, y.payer, y.number, y.amount, y.opened_at AS since FROM finance.paydirect_unreported(p_at) y
                WHERE NOT EXISTS (SELECT 1 FROM finance.paydirect_claim k WHERE k.reference = y.reference AND k.not_found_at IS NOT NULL)),
    c AS (SELECT x.* FROM finance.paydirect_claims(30) x WHERE x.state IN ('WAITING', 'SEEN', 'ELSEWHERE'))
    SELECT coalesce(u.reference, c.reference), coalesce(u.payer, c.payer), coalesce(u.number, c.number), coalesce(u.amount, c.due),
           least(u.since, c.claimed_at), c.payment_log_id, c.paid_on, c.state, c.seen_reference
      FROM u FULL JOIN c ON c.reference = u.reference
$fn$;
COMMENT ON FUNCTION finance.paydirect_waiting(timestamptz) IS
  'V490: the Pay on Quickteller payments that wait on the Bursary — unreported a day after they were opened, and the receipts payers reported that are not confirmed nor marked not found';

CREATE OR REPLACE FUNCTION finance.watch_paydirect_unreported(p_at timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int; v_total numeric; v_oldest timestamptz; v_list text; v_receipts text; v_with int; v_elsewhere int; vars jsonb; r record; told int := 0;
BEGIN
    IF NOT coalesce((SELECT s.watch_enabled FROM finance.paydirect_setting s LIMIT 1), true) THEN RETURN 0; END IF;
    IF extract(hour FROM p_at AT TIME ZONE 'Africa/Lagos') < 8 THEN RETURN 0; END IF;   -- told in the working day, not overnight
    SELECT count(*), coalesce(sum(w.amount), 0), min(w.since), count(w.log_id), count(*) FILTER (WHERE w.state = 'ELSEWHERE')
      INTO n, v_total, v_oldest, v_with, v_elsewhere FROM finance.paydirect_waiting(p_at) w;
    IF n = 0 THEN RETURN 0; END IF;
    SELECT string_agg(format('%s — %s%s — ₦%s — since %s%s', w.reference, coalesce(w.payer, 'payer unknown'), coalesce(' (' || w.number || ')', ''),
                             to_char(coalesce(w.amount, 0), 'FM999,999,999,990.00'), to_char(w.since AT TIME ZONE 'Africa/Lagos', 'DD Mon, HH24:MI'),
                             CASE WHEN w.log_id IS NULL THEN ''
                                  ELSE format(' — receipt %s, paid %s%s', w.log_id, to_char(w.paid_on, 'FMDD Mon'),
                                              CASE WHEN w.state = 'ELSEWHERE' THEN ', reported by Interswitch against ' || w.seen_reference
                                                   WHEN w.state = 'SEEN' THEN ', reported by Interswitch for it and not settled' ELSE '' END) END),
                      E'\n' ORDER BY w.since)
      INTO v_list FROM (SELECT * FROM finance.paydirect_waiting(p_at) z ORDER BY z.since LIMIT 10) w;
    v_receipts := CASE WHEN v_with = 0 THEN 'No payer has reported a receipt for them.'
                       ELSE format('Payers reported the receipt (its Payment Log Id) for %s of them%s.', v_with,
                                   CASE WHEN v_elsewhere > 0 THEN format('; Interswitch reported %s of those against another reference — the Bursary''s to settle, not Interswitch''s to re-send', v_elsewhere) ELSE '' END) END;
    vars := jsonb_build_object(
        'COUNT', n,
        'TOTAL', '₦' || to_char(v_total, 'FM999,999,999,990.00'),
        'OLDEST', to_char(v_oldest AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'),
        'RECEIPTS', v_receipts,
        'LIST', v_list || CASE WHEN n > 10 THEN format(E'\n… and %s more', n - 10) ELSE '' END,
        'SCREEN', coalesce(platform.portal_url(), '') || '/finance/hanging');
    FOR r IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
              WHERE a.office_code = 'bursar' AND p.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        told := told + platform.tell_person(r.person_id, 'PAYDIRECT_UNREPORTED', NULL, vars,
                                            'paydirect-unreported:' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'YYYYMMDD'));
    END LOOP;
    RETURN told;
END $fn$;
COMMENT ON FUNCTION finance.watch_paydirect_unreported(timestamptz) IS
  'V477, V490: once a day from 08:00 Lagos time, each Bursary office holder told of the Pay on Quickteller payments that wait on Interswitch — unreported a day after they were opened, and the receipts payers reported (finance.paydirect_waiting) — by e-mail and on the portal; the event key keeps it to one a day.';

UPDATE platform.notice_template SET
    email_subject = 'Pay on Quickteller: [COUNT] payment(s) not reported by Interswitch',
    email_body = E'Dear [FIRST_NAME],\n\n[COUNT] payment(s) ([TOTAL] in all, the oldest since [OLDEST]) wait on Interswitch: opened on Pay on Quickteller a day ago or more and not reported, or reported by the payer with the receipt. [RECEIPTS]\n\n[LIST]\n\nThe portal cannot ask Interswitch about these: a Pay on Quickteller payment counts only when Interswitch reports it. If the payers paid, import Interswitch''s collections report on the Payment gateways screen (each reference is matched and confirmed), or send Interswitch the Ask Interswitch list from the hanging payments screen and ask them to re-send the notifications. A reference that is not in the report was not paid; mark a receipt Interswitch cannot find as not found, with what they said, and the payer is told.\n\nThe list: [SCREEN]\n\nMOAUM Portal',
    portal_body = '[COUNT] payment(s) opened on Pay on Quickteller ([TOTAL]) wait on Interswitch. [RECEIPTS] Import the collections report, or send Interswitch the Ask Interswitch list from the hanging payments screen.',
    variables = ARRAY['FIRST_NAME','COUNT','TOTAL','OLDEST','RECEIPTS','LIST','SCREEN','PORTAL_URL','UNIVERSITY_SHORT']
 WHERE key = 'PAYDIRECT_UNREPORTED';

-- ── the ICT Support Desk records a caller's receipt: an act on the support ledger, filed under payments ──
-- (the lists carry V500's level acts too, LEVEL_PROGRESSED and LEVEL_CORRECTED in ACADEMIC_LEVEL: whichever of V490 and V500
--  runs last on a database, the support ledger takes both)
ALTER TABLE helpdesk.support_action DROP CONSTRAINT ck_hd_sa_action;
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_action CHECK (action IN (
    'CONTACT_EDITED', 'PERSONAL_EDITED', 'FAMILY_EDITED', 'PHOTO_REPLACED', 'CHANGE_REQUESTED', 'REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED',
    'COURSE_RESTORED', 'REGISTRATION_SUBMITTED', 'RECORD_EXPORTED', 'PASSWORD_RESET', 'ACCOUNT_UNLOCKED', 'PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED',
    'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'PAYMENT_RECEIPT_REPORTED', 'ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED',
    'LEVEL_PROGRESSED', 'LEVEL_CORRECTED'));

CREATE OR REPLACE FUNCTION helpdesk.support_module(p_action text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_action IN ('REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED') THEN 'COURSE_REGISTRATION'
                WHEN p_action IN ('PASSWORD_RESET', 'ACCOUNT_UNLOCKED') THEN 'AUTHENTICATION'
                WHEN p_action IN ('PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED', 'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'PAYMENT_RECEIPT_REPORTED') THEN 'PAYMENT'
                WHEN p_action IN ('ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED') THEN 'TICKET'
                WHEN p_action IN ('LEVEL_PROGRESSED', 'LEVEL_CORRECTED') THEN 'ACADEMIC_LEVEL'
                WHEN p_action = 'RECORD_EXPORTED' THEN 'REPORTS'
                ELSE 'STUDENT_RECORD' END
$$;

COMMIT;
