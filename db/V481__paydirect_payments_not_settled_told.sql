-- ═══════════════════════════════════════
-- V481 — A Pay on Quickteller payment recorded and not settled is told to the Bursary and the Directorate of ICT
--
-- V474 records each payment Interswitch reports before it is settled, answers Interswitch at once, and retries every minute
-- a payment whose settling did not finish. The Gateways screen counted what was left; nobody was told. Now:
--
--   · finance.paydirect_unsettled lists the recorded payments still RECEIVED or FAILED a while after Interswitch last reported
--     them (ten minutes by default: ten retries of the sweeper), with the error the last attempt met;
--   · finance.watch_paydirect_inbox tells each holder of the Bursary's office and of the Directorate of ICT's — by e-mail, on the
--     portal, and by text message — how many, how much, the oldest, the first ten and the last error; while any remain,
--     at most once an hour (the event key), day or night: a payment the portal was told of and has not credited is the
--     payer's money waiting.
--
-- No payment or record is changed by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V481: Pay on Quickteller payments not settled told', true);

CREATE FUNCTION finance.paydirect_unsettled(p_at timestamptz DEFAULT now(), p_minutes int DEFAULT 10)
RETURNS TABLE (id uuid, payment_log_id text, reference text, amount numeric, state text, attempts int, received_at timestamptz, last_error text)
LANGUAGE sql STABLE AS $fn$
    SELECT i.id, i.payment_log_id, i.reference, i.amount, i.state, i.attempts, i.received_at, i.last_error
      FROM finance.paydirect_inbox i
     WHERE i.state <> 'SETTLED' AND i.last_received_at < p_at - make_interval(mins => greatest(coalesce(p_minutes, 10), 1))
     ORDER BY i.received_at
$fn$;
COMMENT ON FUNCTION finance.paydirect_unsettled(timestamptz, int) IS
  'V481: the Pay on Quickteller payments Interswitch reported that are still not settled some minutes after it last reported them (V474 records each before settling it).';

CREATE FUNCTION finance.watch_paydirect_inbox(p_at timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int; v_total numeric; v_oldest timestamptz; v_list text; v_error text; vars jsonb; r record; told int := 0;
BEGIN
    SELECT count(*), coalesce(sum(u.amount), 0), min(u.received_at) INTO n, v_total, v_oldest FROM finance.paydirect_unsettled(p_at) u;
    IF n = 0 THEN RETURN 0; END IF;
    SELECT string_agg(format('%s — %s — ₦%s — reported %s — %s after %s attempt(s)', coalesce(u.reference, 'no reference'), coalesce(u.payment_log_id, 'no log id'),
                             to_char(coalesce(u.amount, 0), 'FM999,999,999,990.00'), to_char(u.received_at AT TIME ZONE 'Africa/Lagos', 'DD Mon, HH24:MI'),
                             CASE WHEN u.state = 'FAILED' THEN 'failed' ELSE 'not yet settled' END, u.attempts),
                      E'\n' ORDER BY u.received_at)
      INTO v_list FROM (SELECT * FROM finance.paydirect_unsettled(p_at) LIMIT 10) u;
    SELECT u.last_error INTO v_error FROM finance.paydirect_unsettled(p_at) u WHERE u.last_error IS NOT NULL ORDER BY u.received_at DESC LIMIT 1;
    vars := jsonb_build_object(
        'COUNT', n,
        'TOTAL', '₦' || to_char(v_total, 'FM999,999,999,990.00'),
        'OLDEST', to_char(v_oldest AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY, HH24:MI'),
        'LIST', v_list || CASE WHEN n > 10 THEN format(E'\n… and %s more', n - 10) ELSE '' END,
        'ERROR', coalesce(v_error, 'none recorded: the portal has not finished settling them'),
        'SCREEN', coalesce(platform.portal_url(), '') || '/finance/gateways');
    FOR r IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
              WHERE a.office_code IN ('bursar', 'ict') AND p.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        told := told + platform.tell_person(r.person_id, 'PAYDIRECT_UNSETTLED', NULL, vars,
                                            'paydirect-unsettled:' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'YYYYMMDDHH24'));
    END LOOP;
    RETURN told;
END $fn$;
COMMENT ON FUNCTION finance.watch_paydirect_inbox(timestamptz) IS
  'V481: while Pay on Quickteller payments Interswitch reported stay unsettled past ten minutes, each Bursary and Directorate of ICT office holder told — e-mail, portal and text — at most once an hour (the event key).';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYDIRECT_UNSETTLED', 'Quickteller payments not settled',
 'To the Bursary and the Directorate of ICT, at most once an hour, while payments Interswitch reported on Pay on Quickteller stay recorded and not settled',
 'Pay on Quickteller: [COUNT] reported payment(s) not settled',
 E'Dear [FIRST_NAME],\n\nInterswitch reported [COUNT] payment(s) on Pay on Quickteller ([TOTAL] in all, the oldest at [OLDEST]) that the portal has recorded but not yet settled:\n\n[LIST]\n\nThe last error: [ERROR]\n\nThe portal retries each one every minute. A payment that stays here means the payer has paid and is not yet credited: the Directorate of ICT looks at the error (the database busy, a reference the portal cannot settle); the Bursary can confirm a payment by hand on its desk once the cause is known.\n\nThe Payment gateways screen: [SCREEN]\n\nMOAUM Portal',
 'MOAUM Portal: [COUNT] Quickteller payment(s) reported by Interswitch not yet settled ([TOTAL]). See Payment gateways.',
 'Quickteller payments not settled',
 '[COUNT] payment(s) Interswitch reported on Pay on Quickteller ([TOTAL]) are recorded and not yet settled; the portal retries each every minute. Last error: [ERROR].',
 ARRAY['FIRST_NAME','COUNT','TOTAL','OLDEST','LIST','ERROR','SCREEN','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH');

COMMIT;
