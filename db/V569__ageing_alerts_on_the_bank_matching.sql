-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V569 — Ageing alerts on the bank matching: what the statements show and no one has acted on, told to the office whose act it is
--
--   The bank statements are matched (V545, V552) and each month reconciled and signed (V557, V562), but nothing said when they were
--   not. Every morning finance.watch_bank_matching tells, by e-mail and on the portal:
--     · the Bursar — an account (1010 or 1020) whose month has no signed reconciliation by the set day of the next month
--       (finance.months_unreconciled; recon_day, the 10th by default): once for each account and month, naming how many months
--       are behind;
--     · the Bursar and the Students Account Officer — a credit on the collections statement for a reference the portal issued and
--       never confirmed, not sent to the bank credits a day after the statement came (finance.credits_waiting; credit_hours, 24):
--       a student who paid and may still be blocked; each line once;
--     · Internal Audit — a payment confirmed on the portal, through the bank, that the collections statements do not show
--       missing_days (3) or more after it, nor a gateway's day settled, nor a reconciliation by hand
--       (finance.payments_missing_from_bank): each payment once, by channel and day.
--   An account is watched once its first statement is loaded or its first reconciliation prepared. The Bursary sets the days
--   (finance.matching_watch) and can switch the watch off.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V569: ageing alerts on the bank matching', true);

CREATE TABLE finance.matching_watch (
    id            boolean PRIMARY KEY DEFAULT true CHECK (id),
    enabled       boolean NOT NULL DEFAULT true,
    recon_day     int NOT NULL DEFAULT 10 CHECK (recon_day BETWEEN 1 AND 28),
    credit_hours  int NOT NULL DEFAULT 24 CHECK (credit_hours BETWEEN 1 AND 336),
    missing_days  int NOT NULL DEFAULT 3 CHECK (missing_days BETWEEN 1 AND 60),
    set_at        timestamptz NULL,
    set_by        uuid NULL,
    set_office    text NULL
);
INSERT INTO finance.matching_watch DEFAULT VALUES;
SELECT audit.attach('finance.matching_watch');
COMMENT ON TABLE finance.matching_watch IS
  'V569: the bank matching''s alerts — a month reconciled by recon_day of the next, a credit for an unconfirmed reference sent to the bank credits within credit_hours, a payment confirmed on the portal seen in the bank within missing_days — and whether they run.';

/* what each alert has told, so nothing is told twice: CREDIT (a statement line), MISSING (a payment's reference) */
CREATE TABLE finance.matching_told (
    kind     text NOT NULL CHECK (kind IN ('CREDIT', 'MISSING')),
    key      text NOT NULL,
    told_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (kind, key)
);
SELECT audit.attach('finance.matching_told');
COMMENT ON TABLE finance.matching_told IS 'V569: the statement lines (CREDIT) and payments (MISSING) the bank matching''s alerts have told of, each once.';

/* the Bursary sets the days */
CREATE FUNCTION finance.set_matching_watch(p_enabled boolean, p_recon_day int, p_credit_hours int, p_missing_days int)
RETURNS finance.matching_watch LANGUAGE plpgsql AS $fn$
DECLARE w finance.matching_watch; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'the bank matching''s alerts are set by a person' USING ERRCODE = '23514'; END IF;
    IF p_recon_day IS NULL OR p_recon_day NOT BETWEEN 1 AND 28 THEN
        RAISE EXCEPTION 'MATCHING_WATCH_DAY: a month is reconciled by a day of the next from the 1st to the 28th' USING ERRCODE = '23514';
    END IF;
    IF p_credit_hours IS NULL OR p_credit_hours NOT BETWEEN 1 AND 336 THEN
        RAISE EXCEPTION 'MATCHING_WATCH_HOURS: a credit waits 1 to 336 hours before it is told' USING ERRCODE = '23514';
    END IF;
    IF p_missing_days IS NULL OR p_missing_days NOT BETWEEN 1 AND 60 THEN
        RAISE EXCEPTION 'MATCHING_WATCH_DAYS: a payment is missing from the bank after 1 to 60 days' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.matching_watch SET enabled = coalesce(p_enabled, true), recon_day = p_recon_day, credit_hours = p_credit_hours, missing_days = p_missing_days,
           set_at = now(), set_by = v_actor, set_office = nullif(current_setting('moaum.actor_office', true), '')
     WHERE id RETURNING * INTO w;
    RETURN w;
END $fn$;

/* the months of each watched account with no signed reconciliation covering every day, past the set day of the next month */
CREATE FUNCTION finance.months_unreconciled(p_at timestamptz DEFAULT now())
RETURNS TABLE (account text, month date, due_on date, days_late int)
LANGUAGE sql STABLE AS $fn$
WITH w AS (SELECT coalesce((SELECT x.recon_day FROM finance.matching_watch x WHERE x.id), 10) AS recon_day),
today AS (SELECT (p_at AT TIME ZONE 'Africa/Lagos')::date AS d),
acc AS (
    SELECT a.account,
           least((SELECT min(r.period_from) FROM finance.bank_reconciliation r WHERE r.account = a.account),
                 (SELECT min(s.period_from) FROM finance.bank_statement s WHERE s.account_kind = a.kind)) AS since
      FROM (VALUES ('1010', 'COLLECTIONS'), ('1020', 'DISBURSEMENT')) a(account, kind)),
m AS (
    SELECT acc.account, gs::date AS month_start, (gs + interval '1 month' - interval '1 day')::date AS month_end
      FROM acc CROSS JOIN today
     -- stepped in local dates (a time zone's old offsets would drift the months)
     CROSS JOIN LATERAL generate_series(date_trunc('month', acc.since::timestamp), date_trunc('month', today.d::timestamp) - interval '1 month', interval '1 month') gs
     WHERE acc.since IS NOT NULL)
SELECT m.account, m.month_start, m.month_end + w.recon_day, today.d - (m.month_end + w.recon_day)
  FROM m CROSS JOIN w CROSS JOIN today
 WHERE today.d >= m.month_end + w.recon_day
   AND EXISTS (SELECT 1 FROM generate_series(m.month_start, m.month_end, interval '1 day') g
                WHERE NOT EXISTS (SELECT 1 FROM finance.bank_reconciliation r
                                   WHERE r.account = m.account AND r.state = 'SIGNED' AND g::date BETWEEN r.period_from AND r.period_to))
 ORDER BY 1, 2
$fn$;
COMMENT ON FUNCTION finance.months_unreconciled(timestamptz) IS
  'V569: for 1010 and 1020, once watched (a statement loaded or a reconciliation prepared), each month not covered day by day by signed reconciliations by finance.matching_watch.recon_day of the next month.';

/* the credits on a collections statement for a reference the portal issued and never confirmed, not sent to the bank credits
   credit_hours after the statement came */
CREATE FUNCTION finance.credits_waiting(p_at timestamptz DEFAULT now())
RETURNS TABLE (line_id uuid, statement text, line_no int, value_date date, reference text, amount numeric, payer text, number text, hours int)
LANGUAGE sql STABLE AS $fn$
WITH w AS (SELECT coalesce((SELECT x.credit_hours FROM finance.matching_watch x WHERE x.id), 24) AS hours)
SELECT l.id, s.label, l.line_no, l.value_date, l.matched_reference, l.credit,
       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.other_names, ''), ', '), ''), p.number,
       (extract(epoch FROM p_at - s.uploaded_at) / 3600)::int
  FROM finance.bank_statement_line l
  JOIN finance.bank_statement s ON s.id = l.statement_id
  CROSS JOIN w
  LEFT JOIN LATERAL (SELECT y.surname, y.other_names, y.number FROM reporting.payments y WHERE y.reference = l.matched_reference LIMIT 1) p ON true
 WHERE s.account_kind = 'COLLECTIONS' AND l.status = 'RECEIVED_NOT_CONFIRMED' AND l.bank_credit_id IS NULL
   AND s.uploaded_at <= p_at - make_interval(hours => w.hours)
   AND (SELECT st.confirmed_at FROM finance.reference_state(l.matched_reference) st LIMIT 1) IS NULL
 ORDER BY l.value_date NULLS LAST, s.label, l.line_no
$fn$;
COMMENT ON FUNCTION finance.credits_waiting(timestamptz) IS
  'V569: collections credits for a reference the portal issued and never confirmed, still not sent to the bank credits finance.matching_watch.credit_hours after their statement came — a student who paid and may still be blocked.';

/* the payments confirmed on the portal through the bank that the collections statements do not show missing_days or more after them:
   each once, from the latest statement whose period runs that far past its day */
CREATE FUNCTION finance.payments_missing_from_bank(p_at timestamptz DEFAULT now())
RETURNS TABLE (reference text, channel text, day date, amount numeric, purpose text, payer text, number text, confirmed_at timestamptz)
LANGUAGE sql STABLE AS $fn$
WITH w AS (SELECT coalesce((SELECT x.missing_days FROM finance.matching_watch x WHERE x.id), 3) AS days),
n AS (
    SELECT DISTINCT ON (x.reference) x.*
      FROM finance.bank_statement s CROSS JOIN w
     CROSS JOIN LATERAL finance.collections_not_received(s.id) x
     WHERE s.account_kind = 'COLLECTIONS' AND s.period_to IS NOT NULL
       AND x.day <= s.period_to - w.days AND x.confirmed_at <= p_at - make_interval(days => w.days)
     ORDER BY x.reference, s.period_to DESC)
SELECT n.reference, n.channel, n.day, n.amount, n.purpose, n.payer, n.number, n.confirmed_at FROM n ORDER BY n.day, n.channel, n.confirmed_at
$fn$;
COMMENT ON FUNCTION finance.payments_missing_from_bank(timestamptz) IS
  'V569: payments confirmed on the portal through the bank that no collections statement shows (one by one, in a gateway''s day settled, or reconciled by hand) though a statement runs finance.matching_watch.missing_days or more past their day.';

/* the morning's alerts: each office told what is its to act on, each thing once */
CREATE FUNCTION finance.watch_bank_matching(p_at timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE w finance.matching_watch; a record; p record; v_told int := 0; v_overdue int := 0; v_credits int := 0; v_missing int := 0;
        vars jsonb; v_list text; v_total numeric; v_n int; v_day text := to_char(p_at AT TIME ZONE 'Africa/Lagos', 'YYYYMMDD');
BEGIN
    SELECT * INTO w FROM finance.matching_watch WHERE id;
    IF NOT coalesce(w.enabled, true) OR extract(hour FROM p_at AT TIME ZONE 'Africa/Lagos') < 8 THEN
        RETURN jsonb_build_object('overdue', 0, 'credits', 0, 'missing', 0, 'told', 0);
    END IF;

    -- 1 · a month not reconciled: the Bursar, once for each account and month
    FOR a IN SELECT u.account, max(u.month) AS latest, min(u.month) AS oldest, count(*) AS n
               FROM finance.months_unreconciled(p_at) u GROUP BY u.account ORDER BY u.account LOOP
        v_overdue := v_overdue + a.n::int;
        vars := jsonb_build_object(
            'ACCOUNT', CASE a.account WHEN '1010' THEN '1010 Bank — Fees collection' ELSE '1020 Bank — Disbursements' END,
            'MONTH', to_char(a.latest, 'FMMonth YYYY'),
            'DUE', to_char(a.latest + interval '1 month' + make_interval(days => w.recon_day - 1), 'FMDD FMMonth'),
            'BEHIND', CASE WHEN a.n > 1 THEN format('It is one of %s months not reconciled, the oldest %s.', a.n, to_char(a.oldest, 'FMMonth YYYY')) ELSE '' END,
            'SCREEN', coalesce(platform.portal_url(), '') || '/finance/reconcile');
        FOR p IN SELECT DISTINCT x.person_id FROM iam.office_assignment x JOIN iam.person pe ON pe.id = x.person_id
                  WHERE x.office_code = 'bursar' AND pe.ended_on IS NULL AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date) LOOP
            v_told := v_told + platform.tell_person(p.person_id, 'BANK_RECON_OVERDUE', NULL, vars,
                                                    'bank-recon-overdue:' || a.account || ':' || to_char(a.latest, 'YYYY-MM'), ARRAY['EMAIL', 'PORTAL']);
        END LOOP;
    END LOOP;

    -- 2 · credits for references never confirmed, not sent to the bank credits: the Bursar and the Students Account Officer, each line once
    CREATE TEMP TABLE IF NOT EXISTS pg_temp.watch_new (key text, line text, amount numeric) ON COMMIT DROP;
    DELETE FROM pg_temp.watch_new;
    INSERT INTO pg_temp.watch_new
    SELECT c.line_id::text, format('%s — %s%s — %s, line %s%s', c.reference, coalesce(c.payer, 'payer unknown'), coalesce(' (' || c.number || ')', ''),
                                   c.statement, c.line_no, coalesce(', ' || to_char(c.value_date, 'FMDD Mon'), '')) || ' — ₦' || to_char(c.amount, 'FM999,999,999,990.00'),
           c.amount
      FROM finance.credits_waiting(p_at) c
     WHERE NOT EXISTS (SELECT 1 FROM finance.matching_told t WHERE t.kind = 'CREDIT' AND t.key = c.line_id::text);
    SELECT count(*), coalesce(sum(x.amount), 0) INTO v_n, v_total FROM pg_temp.watch_new x;
    IF v_n > 0 THEN
        v_credits := v_n;
        SELECT string_agg(x.line, E'\n') INTO v_list FROM (SELECT y.line FROM pg_temp.watch_new y ORDER BY y.line LIMIT 15) x;
        vars := jsonb_build_object('COUNT', v_n, 'TOTAL', '₦' || to_char(v_total, 'FM999,999,999,990.00'), 'HOURS', w.credit_hours,
                                   'LIST', v_list || CASE WHEN v_n > 15 THEN format(E'\n… and %s more', v_n - 15) ELSE '' END,
                                   'SCREEN', coalesce(platform.portal_url(), '') || '/finance/reconcile');
        FOR p IN SELECT DISTINCT x.person_id FROM iam.office_assignment x JOIN iam.person pe ON pe.id = x.person_id
                  WHERE x.office_code IN ('bursar', 'studentaccounts') AND pe.ended_on IS NULL AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date) LOOP
            v_told := v_told + platform.tell_person(p.person_id, 'BANK_CREDITS_WAITING', NULL, vars, 'bank-credits-waiting:' || v_day, ARRAY['EMAIL', 'PORTAL']);
        END LOOP;
        INSERT INTO finance.matching_told (kind, key) SELECT 'CREDIT', x.key FROM pg_temp.watch_new x ON CONFLICT DO NOTHING;
    END IF;

    -- 3 · confirmed on the portal, not in the bank: Internal Audit, each payment once, by channel and day
    DELETE FROM pg_temp.watch_new;
    INSERT INTO pg_temp.watch_new
    SELECT m.reference, coalesce(m.channel, 'no channel') || '|' || m.day::text, m.amount
      FROM finance.payments_missing_from_bank(p_at) m
     WHERE NOT EXISTS (SELECT 1 FROM finance.matching_told t WHERE t.kind = 'MISSING' AND t.key = m.reference);
    SELECT count(*), coalesce(sum(x.amount), 0) INTO v_n, v_total FROM pg_temp.watch_new x;
    IF v_n > 0 THEN
        v_missing := v_n;
        SELECT string_agg(g.line, E'\n' ORDER BY g.day, g.channel) INTO v_list
          FROM (SELECT split_part(x.line, '|', 1) AS channel, split_part(x.line, '|', 2)::date AS day,
                       format('%s, %s: %s payment(s), ₦%s', split_part(x.line, '|', 1), to_char(split_part(x.line, '|', 2)::date, 'FMDD Mon YYYY'),
                              count(*), to_char(sum(x.amount), 'FM999,999,999,990.00')) AS line
                  FROM pg_temp.watch_new x GROUP BY x.line) g;
        vars := jsonb_build_object('COUNT', v_n, 'TOTAL', '₦' || to_char(v_total, 'FM999,999,999,990.00'), 'DAYS', w.missing_days, 'LIST', v_list,
                                   'SCREEN', coalesce(platform.portal_url(), '') || '/finance/reconcile');
        FOR p IN SELECT DISTINCT x.person_id FROM iam.office_assignment x JOIN iam.person pe ON pe.id = x.person_id
                  WHERE x.office_code IN ('audit', 'deputyaudit') AND pe.ended_on IS NULL AND x.valid_from <= current_date AND (x.valid_to IS NULL OR x.valid_to >= current_date) LOOP
            v_told := v_told + platform.tell_person(p.person_id, 'BANK_PAYMENTS_MISSING', NULL, vars, 'bank-payments-missing:' || v_day, ARRAY['EMAIL', 'PORTAL']);
        END LOOP;
        INSERT INTO finance.matching_told (kind, key) SELECT 'MISSING', x.key FROM pg_temp.watch_new x ON CONFLICT DO NOTHING;
    END IF;
    RETURN jsonb_build_object('overdue', v_overdue, 'credits', v_credits, 'missing', v_missing, 'told', v_told);
END $fn$;
COMMENT ON FUNCTION finance.watch_bank_matching(timestamptz) IS
  'V569: from 08:00 Lagos time, while the watch is on — the Bursar told of a month not reconciled (once per account and month), the Bursar and the Students Account Officer of collections credits for never-confirmed references not sent to the bank credits (each line once), Internal Audit of payments confirmed on the portal and not in the bank (each once, by channel and day); returns what was found new and how many messages were queued.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('BANK_RECON_OVERDUE', 'Bank reconciliation overdue',
 'To the Bursar when a bank account''s month has no signed reconciliation by the set day of the next month',
 '[ACCOUNT]: [MONTH] is not reconciled',
 E'Dear [FIRST_NAME],\n\n[ACCOUNT] has no signed bank reconciliation for [MONTH], which was due by [DUE]. [BEHIND]\n\nPrepare it on Reconcile, and another Bursary officer signs it: [SCREEN]\n\nMOAUM Portal',
 NULL,
 'Bank reconciliation overdue',
 '[ACCOUNT] has no signed reconciliation for [MONTH], due by [DUE]. [BEHIND] Prepare it on Reconcile; another Bursary officer signs it.',
 ARRAY['FIRST_NAME','ACCOUNT','MONTH','DUE','BEHIND','SCREEN','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL'),
('BANK_CREDITS_WAITING', 'Bank credits for unconfirmed references',
 'To the Bursar and the Students Account Officer when collections credits for references the portal never confirmed wait to be sent to the bank credits',
 '[COUNT] bank credit(s) for references the portal never confirmed',
 E'Dear [FIRST_NAME],\n\n[COUNT] credit(s) on the collections statement ([TOTAL] in all) are for references the portal issued and never confirmed, and were not sent to the bank credits within [HOURS] hours. Each is a payer who paid and may still be blocked:\n\n[LIST]\n\nSend each to the bank credits from the collections statement on Reconcile; a second officer approves it, and the payment is confirmed: [SCREEN]\n\nMOAUM Portal',
 NULL,
 'Bank credits waiting',
 '[COUNT] collections credit(s) ([TOTAL]) are for references never confirmed. Send each to the bank credits from the collections statement on Reconcile.',
 ARRAY['FIRST_NAME','COUNT','TOTAL','HOURS','LIST','SCREEN','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL'),
('BANK_PAYMENTS_MISSING', 'Payments not in the bank',
 'To Internal Audit when payments confirmed on the portal are not on the collections statements days after them',
 '[COUNT] payment(s) confirmed on the portal are not in the bank after [DAYS] days',
 E'Dear [FIRST_NAME],\n\n[COUNT] payment(s) ([TOTAL] in all) were confirmed on the portal and are not on the collections statements [DAYS] days or more after: not credited one by one, not in a gateway''s day the Bursary has settled, and not reconciled by hand. By channel and day:\n\n[LIST]\n\nA gateway pays a day''s payments in one credit: an unmarked settlement on the statement may explain a day. The payments are listed on Reconcile, under the collections statement: [SCREEN]\n\nMOAUM Portal',
 NULL,
 'Payments not in the bank',
 '[COUNT] payment(s) ([TOTAL]) confirmed on the portal are not on the collections statements after [DAYS] days. See Reconcile.',
 ARRAY['FIRST_NAME','COUNT','TOTAL','DAYS','LIST','SCREEN','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

COMMIT;
