-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V477 — Pay on Quickteller payments unreported after a day: the Bursary told once a day
--
--   · A payment opened on Pay on Quickteller (PayDirect) reaches the portal only when Interswitch reports it; the portal cannot
--     ask (the sweep leaves it alone, WebPAY's requery does not know it). One the payer paid and Interswitch did not report sat
--     on the hanging list until somebody looked.
--   · finance.paydirect_unreported(at, hours, days): the references opened on Pay on Quickteller more than a day before and in
--     the last fortnight, with nothing confirmed — the payer, the number, the amount, when it was opened.
--   · finance.watch_paydirect_unreported(at): once a day, from 08:00 Lagos time, each Bursary office holder is told by e-mail
--     and on the portal (template PAYDIRECT_UNREPORTED; no text message): how many, how much, the oldest, the first ten, and
--     what brings them in — the collections report import, or Interswitch re-sending the notification. The notification
--     engine's event key (one per day) keeps it to once a day; the PAYDirect watch's own switch (finance.paydirect_setting.
--     watch_enabled) turns it off with the door watch. PayDirectWatch runs it with the door watch, every quarter of an hour.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V477: Pay on Quickteller payments unreported after a day', true);

CREATE OR REPLACE FUNCTION finance.paydirect_unreported(p_at timestamptz DEFAULT now(), p_hours int DEFAULT 24, p_days int DEFAULT 14)
RETURNS TABLE(reference text, payer text, number text, amount numeric, opened_at timestamptz, hours int)
LANGUAGE sql STABLE AS $fn$
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
     ORDER BY a.opened_at
$fn$;
COMMENT ON FUNCTION finance.paydirect_unreported(timestamptz, int, int) IS
  'V477: the references opened on Pay on Quickteller (PayDirect) more than a day before and in the last fortnight with nothing confirmed — Interswitch has not reported them.';

CREATE OR REPLACE FUNCTION finance.watch_paydirect_unreported(p_at timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE n int; v_total numeric; v_oldest timestamptz; v_list text; vars jsonb; r record; told int := 0;
BEGIN
    IF NOT coalesce((SELECT s.watch_enabled FROM finance.paydirect_setting s LIMIT 1), true) THEN RETURN 0; END IF;
    IF extract(hour FROM p_at AT TIME ZONE 'Africa/Lagos') < 8 THEN RETURN 0; END IF;   -- told in the working day, not overnight
    SELECT count(*), coalesce(sum(u.amount), 0), min(u.opened_at) INTO n, v_total, v_oldest FROM finance.paydirect_unreported(p_at) u;
    IF n = 0 THEN RETURN 0; END IF;
    SELECT string_agg(format('%s — %s%s — ₦%s — opened %s', u.reference, coalesce(u.payer, 'payer unknown'), coalesce(' (' || u.number || ')', ''),
                             to_char(coalesce(u.amount, 0), 'FM999,999,999,990.00'), to_char(u.opened_at AT TIME ZONE 'Africa/Lagos', 'DD Mon, HH24:MI')),
                      E'\n' ORDER BY u.opened_at)
      INTO v_list FROM (SELECT * FROM finance.paydirect_unreported(p_at) LIMIT 10) u;
    vars := jsonb_build_object(
        'COUNT', n,
        'TOTAL', '₦' || to_char(v_total, 'FM999,999,999,990.00'),
        'OLDEST', to_char(v_oldest AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'),
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
  'V477: once a day from 08:00 Lagos time, each Bursary office holder told of the Pay on Quickteller payments Interswitch has not reported after a day (e-mail and portal; the event key keeps it to one a day).';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYDIRECT_UNREPORTED', 'Quickteller payments not reported',
 'To the Bursary once a day when payments opened on Pay on Quickteller (PayDirect) have not been reported by Interswitch after a day — the portal cannot ask about them',
 'Pay on Quickteller: [COUNT] payment(s) not reported after a day',
 E'Dear [FIRST_NAME],\n\n[COUNT] payment(s) opened on Pay on Quickteller ([TOTAL] in all, the oldest on [OLDEST]) have not been reported by Interswitch a day later:\n\n[LIST]\n\nThe portal cannot ask Interswitch about these: a Pay on Quickteller payment counts only when Interswitch reports it. If the payers paid, import Interswitch''s collections report on the Payment gateways screen (each reference is matched and confirmed), or ask Interswitch to re-send the payment notification for its Payment Log Id. A reference that is not in the report was not paid.\n\nThe list: [SCREEN]\n\nMOAUM Portal',
 NULL,
 'Quickteller payments not reported',
 '[COUNT] payment(s) opened on Pay on Quickteller ([TOTAL]) have not been reported by Interswitch after a day. Import the collections report on the Payment gateways screen, or ask Interswitch to re-send the notifications.',
 ARRAY['FIRST_NAME','COUNT','TOTAL','OLDEST','LIST','SCREEN','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

COMMIT;
