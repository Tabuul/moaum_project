-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V528 — The student's bank account for a refund of overpaid fees, and the Head of ICT Support's oversight of password resets
--
--   1 · A refund raised from the Overpaid list (V506, V519) carried no bank details: the refunds desk had to find the student's
--       account before it could pay. The student now gives it on the fees page — bank, account name, the ten-digit account
--       number (finance.give_refund_account) — kept beside the refund on finance.refund_account; the refund takes its usual
--       snapshot (bank, account name, the last four digits). The account may be given or changed while the refund awaits
--       approval, or given once after approval when none was; never changed once approved with one, nor after it is paid or
--       rejected — money an officer approved is not redirected. The refunds desk sees the account to pay into; the notice that
--       a refund is raised asks the student for it.
--   2 · V526 lifted the hourly limit on ICT Support's resets to the default student credential. The Head of the ICT Support Desk
--       now sees each agent's resets today and this week (helpdesk.reset_counts) and may set a daily figure at which the Head is
--       told (helpdesk.setting.student_reset_alert_daily; empty, the default, tells no one): the notice SUPPORT_RESET_ALERT, once
--       an agent a day, when the agent's resets that day reach it (or pass it, when the figure is lowered during the day).
--       Nothing is refused.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V528: the refund''s bank account from the student; the oversight of password resets', true);

-- ── 1 · the student's account for a refund ───────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.refund_account (
    refund_id      uuid PRIMARY KEY REFERENCES finance.refund(id) ON DELETE CASCADE,
    bank_name      text NOT NULL CHECK (btrim(bank_name) <> ''),
    account_name   text NOT NULL CHECK (btrim(account_name) <> ''),
    account_number text NOT NULL CHECK (account_number ~ '^[0-9]{10}$'),
    given_at       timestamptz NOT NULL DEFAULT now(),
    given_by       uuid NULL
);
COMMENT ON TABLE finance.refund_account IS
  'V528: the bank account a student gave for a refund raised to them (a refund of overpaid fees): the bank, the account name and the ten-digit account number the refunds desk pays into; the refund keeps its own snapshot (bank, name, last four digits).';
SELECT audit.attach('finance.refund_account');

CREATE FUNCTION finance.give_refund_account(p_student uuid, p_reference text, p_bank text, p_name text, p_number text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r finance.refund; v_number text := regexp_replace(coalesce(p_number, ''), '[^0-9]', '', 'g');
        v_bank text := btrim(coalesce(p_bank, '')); v_name text := btrim(coalesce(p_name, '')); v_had boolean;
BEGIN
    SELECT * INTO r FROM finance.refund WHERE reference = upper(btrim(coalesce(p_reference, ''))) AND student_id = p_student FOR UPDATE;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_NOT_YOURS: no refund % is raised to you', p_reference USING ERRCODE = '23514';
    END IF;
    IF v_bank = '' OR v_name = '' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_DETAILS: give the bank and the name on the account' USING ERRCODE = '23514';
    END IF;
    IF v_number !~ '^[0-9]{10}$' THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_NUMBER: an account number is ten digits (your NUBAN)' USING ERRCODE = '23514';
    END IF;
    v_had := EXISTS (SELECT 1 FROM finance.refund_account a WHERE a.refund_id = r.id) OR r.account_last4 IS NOT NULL;
    IF r.state IN ('PAID', 'REJECTED') OR (r.state = 'APPROVED' AND v_had) THEN
        RAISE EXCEPTION 'REFUND_ACCOUNT_CLOSED: refund % is %; the account it is paid into is no longer changed here', r.reference, lower(r.state)
            USING ERRCODE = '23514', HINT = 'Contact the Bursary.';
    END IF;
    INSERT INTO finance.refund_account (refund_id, bank_name, account_name, account_number, given_by)
    VALUES (r.id, v_bank, v_name, v_number, p_student)
    ON CONFLICT (refund_id) DO UPDATE SET bank_name = EXCLUDED.bank_name, account_name = EXCLUDED.account_name,
                                          account_number = EXCLUDED.account_number, given_at = now(), given_by = EXCLUDED.given_by;
    UPDATE finance.refund SET bank_name = v_bank, account_name = v_name, account_last4 = right(v_number, 4) WHERE id = r.id;
END $fn$;
COMMENT ON FUNCTION finance.give_refund_account(uuid, text, text, text, text) IS
  'V528: a student gives the bank account a refund raised to them is paid into — while it awaits approval (and may change it then), or once after approval when none was given; never once approved with one, paid or rejected.';

-- the student's own overpayment decisions (V519), with the account given for a refund
DROP FUNCTION finance.student_overpayments(uuid);
CREATE FUNCTION finance.student_overpayments(p_student uuid)
RETURNS TABLE (session text, amount numeric, decision text, to_session text, reference text, refund_state text, decided_at timestamptz,
               bank_name text, account_name text, account_last4 text, account_given_at timestamptz, account_open boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT d.session, d.amount, d.decision, d.to_session, d.reference, rf.state, d.decided_at,
           rf.bank_name, rf.account_name, rf.account_last4, ra.given_at,
           -- whether the student may give (or change) the account now
           d.decision = 'REFUND' AND (rf.state = 'PROPOSED' OR (rf.state = 'APPROVED' AND ra.refund_id IS NULL AND rf.account_last4 IS NULL))
      FROM finance.overpayment_decision d
      LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
      LEFT JOIN finance.refund_account ra ON ra.refund_id = rf.id
     WHERE d.student_id = p_student AND d.superseded_at IS NULL
     ORDER BY d.decided_at DESC
$fn$;
COMMENT ON FUNCTION finance.student_overpayments(uuid) IS
  'V519, V528: a student''s overpaid school fees and what the Bursary decided (carried into the next session, or a refund raised, with its state), the account given for a refund (bank, name, last four digits, when) and whether it may be given now — what the student''s fees page shows.';

-- the notice that a refund is raised asks for the account
UPDATE platform.notice_template SET
    email_body = E'Dear [FIRST_NAME],\n\nYou paid [AMOUNT] more than your [SESSION_FROM] school fees. The Bursary has raised a refund of it (refund [REFUND]). Give the bank account it should be paid into on your fees page: [PORTAL_URL]\n\nThe refund is approved and paid by the Bursary; you will be told when it is paid.\n\n[UNIVERSITY_SHORT] Bursary',
    sms_body = '[UNIVERSITY_SHORT]: a refund of [AMOUNT] you overpaid on [SESSION_FROM] school fees has been raised (refund [REFUND]). Give your bank account on your fees page on the portal.',
    portal_body = 'A refund of the [AMOUNT] you paid beyond your [SESSION_FROM] school fees has been raised (refund [REFUND]). Give the bank account it should be paid into on your fees page.'
 WHERE key = 'OVERPAYMENT_REFUND_RAISED';

-- ── 2 · the oversight of password resets ─────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE helpdesk.setting
    ADD COLUMN student_reset_alert_daily integer NULL,
    ADD CONSTRAINT ck_hd_setting_reset_alert CHECK (student_reset_alert_daily IS NULL OR student_reset_alert_daily BETWEEN 1 AND 10000);
COMMENT ON COLUMN helpdesk.setting.student_reset_alert_daily IS
  'V528: when one ICT Support agent''s student password resets in a day reach this, the Head of the ICT Support Desk is told (once an agent a day); NULL (the default) tells no one. Nothing is refused.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('SUPPORT_RESET_ALERT', 'Many student password resets by one agent',
 'To the Head of the ICT Support Desk when one agent''s student password resets in a day reach the figure in ICT Support Settings',
 '[AGENT] has reset [COUNT] student passwords today',
 E'Dear [FIRST_NAME],\n\n[AGENT] has reset [COUNT] student passwords today ([DAY]), the figure set in ICT Support Settings for this notice. Nothing has been refused.\n\nEach reset, with its reason and the student, is in Password Reset History: [PORTAL_URL]\n\nMOAUM Portal',
 NULL,
 'Many password resets by [AGENT]',
 '[AGENT] has reset [COUNT] student passwords today ([DAY]). Each one is in Password Reset History.',
 ARRAY['FIRST_NAME','AGENT','COUNT','DAY','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

/* the Head of the ICT Support Desk told when an agent's resets in the day reach the figure (the Director of ICT where no Head is
   in office); each reset is counted as it is recorded */
CREATE FUNCTION helpdesk.trg_reset_alert()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_at int; v_day date := (now() AT TIME ZONE 'Africa/Lagos')::date; n int; v_agent text; p record; v_heads int := 0; v_key text;
BEGIN
    SELECT g.student_reset_alert_daily INTO v_at FROM helpdesk.setting g WHERE g.row_no;
    IF v_at IS NULL OR NEW.agent_id IS NULL THEN RETURN NEW; END IF;
    -- the agent's resets this Lagos day, read on ix_hd_sa_agent (agent_id, at)
    SELECT count(*) INTO n FROM helpdesk.support_action a
     WHERE a.agent_id = NEW.agent_id AND a.action = 'PASSWORD_RESET'
       AND a.at >= v_day::timestamp AT TIME ZONE 'Africa/Lagos' AND a.at < (v_day + 1)::timestamp AT TIME ZONE 'Africa/Lagos';
    IF n < v_at THEN RETURN NEW; END IF;
    -- once an agent a day (reached, or passed when the figure was lowered during the day)
    v_key := 'reset-alert:' || NEW.agent_id || ':' || v_day;
    IF EXISTS (SELECT 1 FROM platform.notice x WHERE x.event_key = v_key) THEN RETURN NEW; END IF;
    SELECT coalesce(pp.surname || ', ' || pp.given_names, 'An agent') INTO v_agent FROM iam.person pp WHERE pp.id = NEW.agent_id;
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code = 'helpdeskhead' AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)
                AND oa.person_id <> NEW.agent_id LOOP
        v_heads := v_heads + platform.tell_person(p.person_id, 'SUPPORT_RESET_ALERT', NULL,
            jsonb_build_object('AGENT', coalesce(v_agent, 'An agent'), 'COUNT', n::text, 'DAY', to_char(v_day, 'FMDD FMMonth YYYY')),
            v_key);
    END LOOP;
    IF v_heads = 0 THEN
        FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
                  WHERE oa.office_code = 'ict' AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)
                    AND oa.person_id <> NEW.agent_id LOOP
            PERFORM platform.tell_person(p.person_id, 'SUPPORT_RESET_ALERT', NULL,
                jsonb_build_object('AGENT', coalesce(v_agent, 'An agent'), 'COUNT', n::text, 'DAY', to_char(v_day, 'FMDD FMMonth YYYY')),
                v_key);
        END LOOP;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_support_reset_alert AFTER INSERT ON helpdesk.support_action
    FOR EACH ROW WHEN (NEW.action = 'PASSWORD_RESET') EXECUTE FUNCTION helpdesk.trg_reset_alert();

/* each agent's student password resets today and in the last seven days (Lagos days), for the Head */
CREATE FUNCTION helpdesk.reset_counts()
RETURNS TABLE (agent_id uuid, name text, today int, week int, last_at timestamptz, alert_at int)
LANGUAGE sql STABLE AS $fn$
    WITH d AS (SELECT (now() AT TIME ZONE 'Africa/Lagos')::date AS today),
    r AS (
        SELECT a.agent_id, (a.at AT TIME ZONE 'Africa/Lagos')::date AS day, a.at
          FROM helpdesk.support_action a, d
         WHERE a.action = 'PASSWORD_RESET' AND a.agent_id IS NOT NULL AND a.at >= (d.today - 6)::timestamp AT TIME ZONE 'Africa/Lagos')
    SELECT r.agent_id, coalesce(pp.surname || ', ' || pp.given_names, r.agent_id::text),
           count(*) FILTER (WHERE r.day = d.today)::int, count(*)::int, max(r.at),
           (SELECT g.student_reset_alert_daily FROM helpdesk.setting g WHERE g.row_no)
      FROM r CROSS JOIN d
      LEFT JOIN iam.person pp ON pp.id = r.agent_id
     GROUP BY r.agent_id, pp.surname, pp.given_names
     ORDER BY 3 DESC, 4 DESC, 2
$fn$;
COMMENT ON FUNCTION helpdesk.reset_counts() IS
  'V528: each ICT Support agent''s student password resets today and in the last seven days (Lagos days), the last one, and the daily figure at which the Head is told.';

COMMIT;
