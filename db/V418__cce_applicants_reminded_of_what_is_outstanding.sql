-- ═══════════════════════════════════════
-- V418 — CCE applicants reminded of what they still have to do
--
--   V414's admissions.cce_outstanding is what a CCE applicant still has to do: the application fee, the form, what the Centre
--   asked for, the CCE admission checking fee once the outcome is published, the acceptance fee once the offer is read. An
--   applicant who stops there is now reminded, by email and (where the rule says) SMS, as JUPEB's candidates are (V343):
--
--     admissions.cce_reminder_rule   one row per step: on or off, the first reminder so many days after the step began, then
--                                    every so many days, at most so many times, SMS or email only. The Centre (or the
--                                    Academic Office) sets them; seeded at 2/3/3 for the fees, 3/4/3 for the form and what
--                                    the Centre asked.
--     admissions.cce_reminder_log    every reminder sent: the application, the step, when, by SMS too, by the schedule or by
--                                    an officer's "send now".
--     admissions.cce_due_reminders   who is due one now, and of what — at most one step per applicant (the earliest), at most
--                                    one reminder a day, and only for a step that can be done: the application fee and the
--                                    form only while the CCE application window is open, a fee only once the Bursary has
--                                    stated it.
--     admissions.cce_send_reminders  sends them (each morning by the API's schedule, or now by the Centre), logs each one.
--
--   The step began: the application fee when the account was opened; the form when the fee was settled; what the Centre asked
--   when it asked; the checking fee when the outcome was published; the acceptance fee when the offer was read.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V418: CCE applicants reminded of what is outstanding', true);

CREATE TABLE admissions.cce_reminder_rule (
    item             text PRIMARY KEY CHECK (item IN ('APPLICATION_FEE', 'FORM', 'CENTRE_ASKED', 'CHECKING_FEE', 'ACCEPTANCE_FEE')),
    enabled          boolean NOT NULL DEFAULT true,
    first_after_days int NOT NULL CHECK (first_after_days BETWEEN 0 AND 60),
    every_days       int NOT NULL CHECK (every_days BETWEEN 1 AND 60),
    max_count        int NOT NULL CHECK (max_count BETWEEN 1 AND 10),
    sms              boolean NOT NULL DEFAULT true,
    ord              int NOT NULL,
    updated_by       uuid NULL,
    updated_office   text NULL REFERENCES ref.office(code),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('admissions.cce_reminder_rule');
COMMENT ON TABLE admissions.cce_reminder_rule IS
  'V418: when a CCE applicant is reminded of each step still outstanding (admissions.cce_outstanding) — days after the step began, every how many days, at most how many times, and whether by SMS too; the Centre''s (or the Academic Office''s) to set.';
INSERT INTO admissions.cce_reminder_rule (item, first_after_days, every_days, max_count, ord) VALUES
    ('APPLICATION_FEE', 2, 3, 3, 1), ('FORM', 3, 4, 3, 2), ('CENTRE_ASKED', 3, 4, 3, 3), ('CHECKING_FEE', 2, 3, 3, 4), ('ACCEPTANCE_FEE', 2, 3, 3, 5);

CREATE TABLE admissions.cce_reminder_log (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- cleared with its application by the go-live data reset (platform.reset_operational_data), which this table does not restate
    application_id uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    item           text NOT NULL REFERENCES admissions.cce_reminder_rule(item),
    sent_at        timestamptz NOT NULL DEFAULT now(),
    by_sms         boolean NOT NULL DEFAULT false,
    trigger        text NOT NULL DEFAULT 'SCHEDULE' CHECK (trigger IN ('SCHEDULE', 'OFFICE')),
    sent_by        uuid NULL
);
CREATE INDEX ix_cce_reminder_log ON admissions.cce_reminder_log (application_id, item, sent_at DESC);
SELECT audit.attach('admissions.cce_reminder_log');
COMMENT ON TABLE admissions.cce_reminder_log IS 'V418: every reminder sent to a CCE applicant — the step, when, by SMS too, by the schedule or by an officer.';

-- ── the Centre sets a rule ──
CREATE FUNCTION admissions.cce_set_reminder_rule(p_item text, p_enabled boolean, p_first int, p_every int, p_max int, p_sms boolean)
RETURNS admissions.cce_reminder_rule LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_reminder_rule;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'setting the CCE reminders');
    UPDATE admissions.cce_reminder_rule
       SET enabled = coalesce(p_enabled, enabled), first_after_days = coalesce(p_first, first_after_days), every_days = coalesce(p_every, every_days),
           max_count = coalesce(p_max, max_count), sms = coalesce(p_sms, sms),
           updated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, updated_office = nullif(current_setting('moaum.actor_office', true), ''), updated_at = now()
     WHERE item = upper(btrim(p_item)) RETURNING * INTO r;
    IF NOT FOUND THEN RAISE EXCEPTION 'CCE_REMINDER_ITEM: % is not a step CCE applicants are reminded of', p_item USING ERRCODE = '23514'; END IF;
    RETURN r;
END $fn$;

-- ── who is due a reminder now, and of what ──
CREATE FUNCTION admissions.cce_due_reminders(p_now timestamptz)
RETURNS TABLE(application_id uuid, application_no text, name text, item text, label text, detail text, amount numeric, href text, sent_before int, last_sent timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH apps AS (
        SELECT a.id, a.application_no, a.created_at, a.fee_confirmed_at, a.decision_released_at, a.status_checked_at, r.requested_at,
               l.surname || ', ' || l.first_name AS name,
               (SELECT w.state FROM policy.window_state('CCE_APPLICATION', a.session, NULL) w LIMIT 1) AS window_state
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode = 'CCE'
          JOIN admissions.cce_review r ON r.application_id = a.id
          JOIN admissions.cce_candidate l ON l.id = c.cce_candidate_id
         WHERE r.state NOT IN ('REJECTED', 'NOT_ADMITTED') AND l.standing = 'LISTED'
    ), o AS (
        SELECT apps.id, apps.application_no, apps.name, x.item, x.label, x.detail, x.amount, x.href, rr.ord, rr.first_after_days, rr.every_days, rr.max_count,
               CASE x.item WHEN 'APPLICATION_FEE' THEN apps.created_at WHEN 'FORM' THEN coalesce(apps.fee_confirmed_at, apps.created_at)
                           WHEN 'CENTRE_ASKED' THEN apps.requested_at WHEN 'CHECKING_FEE' THEN apps.decision_released_at
                           ELSE apps.status_checked_at END AS anchor
          FROM apps
          CROSS JOIN LATERAL admissions.cce_outstanding(apps.id) x
          JOIN admissions.cce_reminder_rule rr ON rr.item = x.item AND rr.enabled
         -- only a step that can be done: the fee and the form while applications are open, a fee once the Bursary stated it
         WHERE (x.item NOT IN ('APPLICATION_FEE', 'FORM') OR apps.window_state = 'OPEN')
           AND (x.item NOT IN ('APPLICATION_FEE', 'CHECKING_FEE', 'ACCEPTANCE_FEE') OR x.amount IS NOT NULL)
    ), s AS (
        SELECT o.*,
               (SELECT count(*) FROM admissions.cce_reminder_log g WHERE g.application_id = o.id AND g.item = o.item)::int AS sent_before,
               (SELECT max(g.sent_at) FROM admissions.cce_reminder_log g WHERE g.application_id = o.id AND g.item = o.item) AS last_sent,
               (SELECT max(g.sent_at) FROM admissions.cce_reminder_log g WHERE g.application_id = o.id) AS last_any
          FROM o
    ), due AS (
        SELECT s.*, row_number() OVER (PARTITION BY s.id ORDER BY s.ord) AS rn
          FROM s
         WHERE s.anchor IS NOT NULL AND p_now >= s.anchor + make_interval(days => s.first_after_days)
           AND s.sent_before < s.max_count
           AND (s.last_sent IS NULL OR p_now >= s.last_sent + make_interval(days => s.every_days))
           -- at most one reminder a day to anyone
           AND (s.last_any IS NULL OR (s.last_any AT TIME ZONE 'Africa/Lagos')::date < (p_now AT TIME ZONE 'Africa/Lagos')::date)
    )
    SELECT due.id, due.application_no, due.name, due.item, due.label, due.detail, due.amount, due.href, due.sent_before, due.last_sent
      FROM due WHERE due.rn = 1 ORDER BY due.application_no;
$fn$;
COMMENT ON FUNCTION admissions.cce_due_reminders(timestamptz) IS
  'V418: the CCE applicants due a reminder now — the earliest outstanding step, once its rule''s days have passed, not more often or more times than the rule allows, at most once a day, and only a step that can be done.';

-- ── the words ──
CREATE FUNCTION admissions.cce_reminder_words(p_item text, p_label text, p_detail text, p_amount numeric, p_href text, p_application_no text, p_portal text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT ARRAY[
        'Your CCE application: ' || lower(left(p_label, 1)) || substr(p_label, 2),
        'Your application to the Centre for Continuing Education (' || p_application_no || ') is waiting on you.' || chr(10) || chr(10)
            || p_label || coalesce(' — NGN ' || to_char(p_amount, 'FM999,999,990.00'), '') || '.' || chr(10)
            || coalesce(p_detail || '.' || chr(10), '') || chr(10)
            || 'Sign in at ' || coalesce(nullif(p_portal, '') || coalesce(p_href, ''), 'the University portal') || CASE p_href WHEN '/applicant/admission' THEN ' (Admission Status)' WHEN '/applicant/accept' THEN ' (Accept your offer)' ELSE ' (your CCE application)' END || '.' || chr(10) || chr(10)
            || 'If you have done this already, you can ignore this reminder.',
        'MOAUM CCE ' || p_application_no || ': ' || p_label || coalesce(' (NGN ' || to_char(p_amount, 'FM999,999,990') || ')', '')
            || '. Sign in at ' || coalesce(nullif(p_portal, '') || coalesce(p_href, ''), 'the portal') || '.'];
$fn$;

-- ── send them ──
CREATE FUNCTION admissions.cce_send_reminders(p_now timestamptz, p_portal text, p_limit int, p_trigger text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE d record; w text[]; r admissions.cce_reminder_rule; acct record; n int := 0; v_by jsonb := '{}'::jsonb;
        v_trigger text := coalesce(nullif(upper(btrim(p_trigger)), ''), 'SCHEDULE'); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_trigger = 'OFFICE' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'sending the CCE reminders now');
    END IF;
    FOR d IN SELECT * FROM admissions.cce_due_reminders(p_now) LIMIT greatest(coalesce(p_limit, 500), 0) LOOP
        SELECT * INTO r FROM admissions.cce_reminder_rule WHERE item = d.item;
        SELECT x.email, x.phone INTO acct FROM admissions.applicant_account x JOIN admissions.application a ON a.account_id = x.id WHERE a.id = d.application_id;
        w := admissions.cce_reminder_words(d.item, d.label, d.detail, d.amount, d.href, d.application_no, p_portal);
        IF acct.email IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', acct.email, w[1], w[2], 'application', d.application_id);
        END IF;
        IF r.sms AND acct.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', acct.phone, w[1], w[3], 'application', d.application_id);
        END IF;
        INSERT INTO admissions.cce_reminder_log (application_id, item, sent_at, by_sms, trigger, sent_by)
        VALUES (d.application_id, d.item, p_now, r.sms AND acct.phone IS NOT NULL, v_trigger, CASE WHEN v_trigger = 'OFFICE' THEN v_actor END);
        n := n + 1;
        v_by := jsonb_set(v_by, ARRAY[d.item], to_jsonb(coalesce((v_by->>d.item)::int, 0) + 1));
    END LOOP;
    RETURN jsonb_build_object('sent', n, 'byItem', v_by);
END $fn$;
COMMENT ON FUNCTION admissions.cce_send_reminders(timestamptz, text, int, text) IS
  'V418: sends the CCE reminders due now (admissions.cce_due_reminders) by email, and SMS where the rule says, and logs each; OFFICE (the Centre''s "send now") needs the Centre, the Academic Office or super.';

COMMIT;
