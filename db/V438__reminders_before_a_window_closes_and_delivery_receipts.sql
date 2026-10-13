-- ═══════════════════════════════════════
-- V438 — reminders before a window closes, and delivery receipts from the providers
--
-- 1 · Three days and one day before a school fees payment or course registration window closes (the University's, the
--     Centre's and the School's), the students of the session who have not yet done what the window is for are reminded,
--     through the engine: a WINDOW job with the action CLOSING, queued once per window, deadline and day by a daily pass
--     (platform.queue_closing_reminders, 08:00 Lagos), drained by the job runner like the open/close messages (V425), the
--     WINDOW_CLOSING template with a variant per window type. Who has done it is read from the record (policy.window_done):
--     fees paid in full for the session (a student whose fees are not stated has nothing to pay and is left alone), a
--     registration submitted for the semester. The deadline is the window's close, or the end of its late period once
--     the close has passed. Nobody is reminded twice for the same deadline and day (the event key).
--
-- 2 · A message is SENT when the provider accepts it (V025). The providers can say more later — delivered, bounced,
--     undelivered — and that word now lands on the message: platform.notice.delivery_state, delivered_at, delivery_detail,
--     never touching the state itself (a late report never turns a cancelled or failed message into a sent one). The
--     dispatcher keeps the provider's own id of each message (provider_id: Resend's id; for eBulkSMS the message id the
--     portal sends is the notice's own), and the receipt door (POST /api/v1/notices/receipts/{provider}, behind a token
--     the Directorate of ICT generates) matches the report to it. Every report is kept on platform.notice_receipt as it
--     came, matched or not, so what a provider actually sends is seen before it is trusted.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V438: reminders before a window closes, and delivery receipts', true);

-- ── 1 · reminders before a window closes ─────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE platform.notice_setting ADD COLUMN closing_reminders boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN platform.notice_setting.closing_reminders IS 'V438: whether the students not yet done are reminded three days and one day before a fees or registration window closes';

-- whether a student has done what a window is for: fees paid in full (nothing to pay counts as done), a registration submitted
CREATE FUNCTION policy.window_done(p_type text, p_session text, p_semester int, p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_type LIKE '%SCHOOL_FEES_PAYMENT' THEN
            NOT finance.fee_stated(p_student, p_session)
            OR coalesce((SELECT pos.paid_in_full FROM finance.position(p_student, p_session) pos), false)
        WHEN p_type LIKE '%COURSE_REGISTRATION' THEN
            EXISTS (SELECT 1 FROM registration.course_registration cr
                     WHERE cr.student_id = p_student AND cr.session = p_session
                       AND (p_semester IS NULL OR cr.semester = p_semester)
                       AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED'))
        ELSE true END
$$;

-- the reminder for one window queued as a WINDOW job with the action CLOSING
CREATE FUNCTION platform.queue_closing_job(p_window uuid, p_days int, p_deadline timestamptz)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_job uuid;
BEGIN
    INSERT INTO platform.notice_job (kind, payload, created_by, created_office)
    SELECT 'WINDOW',
           jsonb_strip_nulls(jsonb_build_object(
               'type', w.window_type, 'session', w.session, 'semester', w.semester, 'action', 'CLOSING', 'window_id', w.id,
               'closes_at', w.closes_at, 'late_until', w.late_until, 'phase', st.phase, 'reason', w.reason,
               'days_left', p_days, 'deadline', p_deadline, 'deadline_date', to_char(p_deadline AT TIME ZONE 'Africa/Lagos', 'YYYY-MM-DD'))),
           NULL, 'ict'
      FROM policy.portal_window w, LATERAL policy.window_state(w.window_type, w.session, w.semester) st
     WHERE w.id = p_window
    RETURNING id INTO v_job;
    RETURN v_job;
END $$;

-- the daily pass: every fees or registration window closing in three days or tomorrow (Lagos dates), queued once per deadline and day
CREATE FUNCTION platform.queue_closing_reminders(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql AS $$
DECLARE w record; n int := 0; v_deadline timestamptz; v_days int; v_today date := (p_now AT TIME ZONE 'Africa/Lagos')::date; v_date text;
BEGIN
    IF NOT coalesce((SELECT s.closing_reminders FROM platform.notice_setting s WHERE s.id), true) THEN RETURN 0; END IF;
    FOR w IN SELECT x.* FROM policy.portal_window x
              WHERE x.superseded_at IS NULL AND x.forced IS NULL
                AND (x.window_type LIKE '%SCHOOL_FEES_PAYMENT' OR x.window_type LIKE '%COURSE_REGISTRATION')
                AND (x.opens_at IS NULL OR x.opens_at <= p_now)
                AND coalesce(x.closes_at, x.late_until) IS NOT NULL
                AND coalesce(x.late_until, x.closes_at) >= p_now LOOP
        v_deadline := CASE WHEN w.closes_at IS NOT NULL AND w.closes_at >= p_now THEN w.closes_at ELSE w.late_until END;
        v_days := (v_deadline AT TIME ZONE 'Africa/Lagos')::date - v_today;
        IF v_days NOT IN (3, 1) THEN CONTINUE; END IF;
        v_date := to_char(v_deadline AT TIME ZONE 'Africa/Lagos', 'YYYY-MM-DD');
        IF EXISTS (SELECT 1 FROM platform.notice_job j
                    WHERE j.kind = 'WINDOW' AND j.payload ->> 'action' = 'CLOSING' AND j.payload ->> 'window_id' = w.id::text
                      AND j.payload ->> 'deadline_date' = v_date AND j.payload ->> 'days_left' = v_days::text) THEN
            CONTINUE;
        END IF;
        PERFORM platform.queue_closing_job(w.id, v_days, v_deadline);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION platform.queue_closing_reminders(timestamptz) IS
  'V438: the windows closing in three days or tomorrow, each queued once per deadline and day as a WINDOW job with the action CLOSING; the job runner reminds the students not yet done.';

-- the job runner (V426) restated: a CLOSING job reminds only the students not yet done, under a key per window, deadline and day
CREATE OR REPLACE FUNCTION platform.run_notice_job(p_limit int DEFAULT NULL)
RETURNS TABLE(job_id uuid, kind text, reached int, queued int, done boolean)
LANGUAGE plpgsql AS $$
DECLARE j record; c platform.notice_campaign; v_limit int := coalesce(p_limit, (SELECT job_batch FROM platform.notice_setting WHERE id), 2000);
        v_key text; v_vars jsonb; v_event text; s uuid; r record; v_reached int := 0; v_queued int := 0; v_last uuid;
        v_kind text; v_after uuid; v_done boolean; v_action text;
BEGIN
    SELECT * INTO j FROM platform.notice_job x WHERE x.state IN ('QUEUED', 'RUNNING') ORDER BY x.created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN; END IF;
    UPDATE platform.notice_job SET state = 'RUNNING', started_at = coalesce(started_at, now()), runs = runs + 1 WHERE id = j.id;
    BEGIN
        IF j.kind = 'WINDOW' THEN
            v_action := j.payload ->> 'action';
            v_key := 'WINDOW_' || CASE v_action WHEN 'OPEN' THEN 'OPENED' WHEN 'REOPEN' THEN 'REOPENED' WHEN 'EXTEND' THEN 'EXTENDED' WHEN 'CLOSING' THEN 'CLOSING' ELSE 'CLOSED' END;
            v_vars := platform.window_vars(j.payload);
            IF v_action = 'CLOSING' THEN
                v_vars := v_vars || jsonb_build_object(
                    'DAYS_WORD', CASE WHEN (j.payload ->> 'days_left')::int <= 1 THEN 'tomorrow' ELSE 'in ' || (j.payload ->> 'days_left') || ' days' END,
                    'DEADLINE', to_char((j.payload ->> 'deadline')::timestamptz AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI'));
                v_event := 'window-closing:' || (j.payload ->> 'window_id') || ':' || (j.payload ->> 'deadline_date') || ':' || (j.payload ->> 'days_left');
            ELSE
                v_event := 'window:' || coalesce(j.payload ->> 'event_id', j.id::text) || ':' || v_action;
            END IF;
            FOR s IN SELECT * FROM policy.window_audience(j.payload ->> 'type', j.payload ->> 'session', j.cursor_id, v_limit) LOOP
                IF v_action <> 'CLOSING' OR NOT policy.window_done(j.payload ->> 'type', j.payload ->> 'session', (j.payload ->> 'semester')::int, s) THEN
                    v_queued := v_queued + platform.tell_student(s, v_key, j.payload ->> 'type', v_vars, v_event);
                END IF;
                v_reached := v_reached + 1; v_last := s;
            END LOOP;
            v_done := v_reached < v_limit;
            UPDATE platform.notice_job
               SET cursor_id = coalesce(v_last, cursor_id), reached = platform.notice_job.reached + v_reached, queued = platform.notice_job.queued + v_queued,
                   state = CASE WHEN v_done THEN 'DONE' ELSE 'RUNNING' END, finished_at = CASE WHEN v_done THEN now() END
             WHERE id = j.id;
        ELSIF j.kind = 'CAMPAIGN' THEN
            SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = (j.payload ->> 'campaign_id')::uuid;
            IF c.id IS NULL OR c.state <> 'SENDING' THEN
                UPDATE platform.notice_job SET state = 'DONE', finished_at = now(), error = coalesce(error, 'the campaign is ' || coalesce(lower(c.state), 'gone')) WHERE id = j.id;
                RETURN QUERY SELECT j.id, j.kind, 0, 0, true;
                RETURN;
            END IF;
            v_event := 'campaign:' || c.id;
            v_kind := coalesce(j.payload ->> 'cursor_kind', 'student');
            v_after := j.cursor_id;
            WHILE v_kind IS NOT NULL AND v_reached < v_limit LOOP
                FOR r IN SELECT * FROM platform.campaign_recipients(c.id, v_kind, v_after, v_limit - v_reached) LOOP
                    v_queued := v_queued + CASE v_kind
                        WHEN 'student' THEN platform.tell_student(r.id, c.template_key, NULL, c.vars, v_event, c.channels)
                        WHEN 'person' THEN platform.tell_person(r.id, c.template_key, NULL, c.vars, v_event, c.channels)
                        ELSE platform.tell_applicant(r.id, c.template_key, NULL, c.vars, v_event, c.channels) END;
                    v_reached := v_reached + 1; v_last := r.id; v_after := r.id;
                END LOOP;
                IF v_reached >= v_limit THEN EXIT; END IF;
                -- this kind is exhausted: on to the next, from its beginning
                v_kind := CASE v_kind WHEN 'student' THEN 'person' WHEN 'person' THEN 'application' ELSE NULL END;
                v_after := NULL; v_last := NULL;
            END LOOP;
            v_done := v_kind IS NULL;
            UPDATE platform.notice_job
               SET cursor_id = v_last, payload = payload || jsonb_build_object('cursor_kind', coalesce(v_kind, 'done')),
                   reached = platform.notice_job.reached + v_reached, queued = platform.notice_job.queued + v_queued,
                   state = CASE WHEN v_done THEN 'DONE' ELSE 'RUNNING' END, finished_at = CASE WHEN v_done THEN now() END
             WHERE id = j.id;
            IF v_done THEN
                UPDATE platform.notice_campaign SET state = 'SENT', finished_at = now(), updated_at = now() WHERE id = c.id AND state = 'SENDING';
            END IF;
        ELSE
            RAISE EXCEPTION 'NOTICE_JOB_KIND: no runner for a % job yet', j.kind USING ERRCODE = '23514';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        UPDATE platform.notice_job SET state = 'FAILED', error = left(SQLERRM, 400), finished_at = now() WHERE id = j.id;
        RETURN QUERY SELECT j.id, j.kind, 0, 0, true;
        RETURN;
    END;
    RETURN QUERY SELECT j.id, j.kind, v_reached, v_queued, v_done;
END $$;
COMMENT ON FUNCTION platform.run_notice_job(int) IS
  'V438 (V426 restated): drains the oldest open notification job by one batch — a window''s students (a CLOSING job only those not yet done), or a campaign''s students, staff and applicants in turn, the kind and cursor kept on the job; runs until nobody is left.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('WINDOW_CLOSING', 'Portal window closing',
 'The reminder three days and one day before a window closes, to the students of the session who have not yet done what the window is for',
 '[WINDOW] for [SESSION][SEMESTER] closes [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] closes [DAYS_WORD], on [DEADLINE]. [LATE_NOTE]\n\nPlease complete it on the portal before then: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: [WINDOW] for [SESSION][SEMESTER] closes [DAYS_WORD] ([DEADLINE]). Complete it on the portal before then.',
 '[WINDOW] closes [DAYS_WORD]',
 '[WINDOW] for [SESSION][SEMESTER] closes [DAYS_WORD], on [DEADLINE]. [LATE_NOTE]',
 ARRAY['FIRST_NAME','WINDOW','SESSION','SEMESTER','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSING:SCHOOL_FEES_PAYMENT', 'School fees payment closing',
 'The reminder before the school fees payment windows close (the University''s, the Centre''s and the School''s), to the students whose fees for the session are stated and not yet paid in full',
 'School fees for [SESSION]: payment closes [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows your school fees for the session are not yet paid in full. [LATE_NOTE]\n\nGenerate your reference and pay on the portal before then: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: school fees payment for [SESSION] closes [DAYS_WORD] ([DEADLINE]) and yours is not yet paid in full. Pay on the portal before then.',
 'School fees payment closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; your school fees for the session are not yet paid in full. [LATE_NOTE]',
 ARRAY['FIRST_NAME','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSING:COURSE_REGISTRATION', 'Course registration closing',
 'The reminder before the course registration windows close, to the students who have not yet submitted a registration for the semester',
 'Course registration for [SESSION][SEMESTER] closes [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION][SEMESTER] closes [DAYS_WORD], on [DEADLINE]. Our record shows you have not yet submitted your registration. [LATE_NOTE]\n\nRegister your courses on the portal before then: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: course registration for [SESSION][SEMESTER] closes [DAYS_WORD] ([DEADLINE]) and you have not submitted yours. Register on the portal before then.',
 'Course registration closes [DAYS_WORD]',
 '[WINDOW] for [SESSION][SEMESTER] closes [DAYS_WORD], on [DEADLINE]; you have not yet submitted your registration. [LATE_NOTE]',
 ARRAY['FIRST_NAME','WINDOW','SESSION','SEMESTER','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH');

-- ── 2 · delivery receipts from the providers ─────────────────────────────────────────────────────────────────────────────────
ALTER TABLE platform.notice
    ADD COLUMN provider_id     text NULL,
    ADD COLUMN delivery_state  text NULL CHECK (delivery_state IN ('DELIVERED', 'BOUNCED', 'UNDELIVERED')),
    ADD COLUMN delivered_at    timestamptz NULL,
    ADD COLUMN delivery_detail text NULL;
COMMENT ON COLUMN platform.notice.provider_id IS 'V438: the provider''s own id of the message (Resend''s id; for eBulkSMS the notice''s own id, sent as the message id), what a delivery report names';
COMMENT ON COLUMN platform.notice.delivery_state IS 'V438: what the provider reported after accepting the message — DELIVERED, BOUNCED (the address refused it) or UNDELIVERED (expired or failed on the way); the state itself stays SENT';
CREATE INDEX ix_notice_provider_id ON platform.notice (provider_id) WHERE provider_id IS NOT NULL;

ALTER TABLE platform.notice_setting ADD COLUMN receipt_token text NULL;
COMMENT ON COLUMN platform.notice_setting.receipt_token IS 'V438: the token a provider''s delivery report must carry at the receipt door; generated by the Directorate of ICT';

ALTER TABLE platform.notice_clearance
    ADD COLUMN email_delivered int NOT NULL DEFAULT 0,
    ADD COLUMN sms_delivered   int NOT NULL DEFAULT 0;

CREATE TABLE platform.notice_receipt (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider     text NOT NULL,
    received_at  timestamptz NOT NULL DEFAULT now(),
    provider_id  text NULL,
    status_word  text NULL,
    notice_id    uuid NULL,
    outcome      text NOT NULL,
    detail       text NULL,
    payload      jsonb NULL
);
COMMENT ON TABLE platform.notice_receipt IS 'V438: every delivery report a provider sent to the receipt door, as it came, with the message it matched and what was done with it (DELIVERED, BOUNCED, UNDELIVERED, IGNORED, UNMATCHED, NOT_SENT)';
SELECT audit.exempt('platform.notice_receipt', 'the providers'' delivery reports as they came — a log written by the providers, read by the Directorate of ICT; the message it changed is audited');
CREATE INDEX ix_notice_receipt_received ON platform.notice_receipt (received_at DESC);

CREATE FUNCTION platform.new_receipt_token(p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE t text := md5(gen_random_uuid()::text || clock_timestamp()::text) || md5(gen_random_uuid()::text);
BEGIN
    UPDATE platform.notice_setting SET receipt_token = t, updated_by = p_actor, updated_office = p_office, updated_at = now() WHERE id;
    RETURN t;
END $$;

CREATE FUNCTION platform.receipt_token_ok(p_token text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT s.receipt_token IS NOT NULL AND nullif(btrim(coalesce(p_token, '')), '') = s.receipt_token FROM platform.notice_setting s WHERE s.id
$$;

-- a provider's word on a message: matched by the provider's id (or the notice's own), written on a SENT message only, always logged
CREATE FUNCTION platform.record_receipt(p_provider text, p_provider_id text, p_status text, p_detail text, p_payload jsonb)
RETURNS TABLE (outcome text, notice_id uuid) LANGUAGE plpgsql AS $$
DECLARE v_word text := regexp_replace(lower(coalesce(p_status, '')), '[^a-z]', '', 'g'); v_outcome text; v_id uuid; v_state text; v_pid text := nullif(btrim(coalesce(p_provider_id, '')), '');
BEGIN
    v_outcome := CASE
        WHEN v_word IN ('delivered', 'delivrd', 'dlvrd', 'emaildelivered', 'success', 'successful') THEN 'DELIVERED'
        WHEN v_word IN ('bounced', 'bounce', 'emailbounced', 'hardbounce', 'softbounce', 'rejected', 'rejectd', 'complained', 'emailcomplained',
                        'undeliv', 'undelivered', 'undelivrd', 'invalid', 'invalidnumber', 'dnd') THEN 'BOUNCED'
        WHEN v_word IN ('expired', 'failed', 'failure', 'error', 'unknown', 'deleted', 'notdelivered') THEN 'UNDELIVERED'
        ELSE 'IGNORED' END;
    IF v_pid IS NOT NULL THEN
        SELECT n.id, n.state INTO v_id, v_state FROM platform.notice n
         WHERE n.provider_id = v_pid OR (v_pid ~ '^[0-9a-fA-F-]{36}$' AND n.id = v_pid::uuid)
         ORDER BY n.created_at DESC LIMIT 1;
    END IF;
    IF v_id IS NULL THEN
        v_outcome := 'UNMATCHED';
    ELSIF v_state <> 'SENT' THEN
        v_outcome := 'NOT_SENT';
    ELSIF v_outcome <> 'IGNORED' THEN
        UPDATE platform.notice SET delivery_state = v_outcome, delivered_at = now(), delivery_detail = left(nullif(btrim(coalesce(p_detail, '')), ''), 400) WHERE id = v_id;
    END IF;
    INSERT INTO platform.notice_receipt (provider, provider_id, status_word, notice_id, outcome, detail, payload)
    VALUES (lower(coalesce(p_provider, 'generic')), v_pid, left(coalesce(p_status, ''), 80), v_id, v_outcome, left(coalesce(p_detail, ''), 400), p_payload);
    RETURN QUERY SELECT v_outcome, v_id;
END $$;
COMMENT ON FUNCTION platform.record_receipt(text, text, text, text, jsonb) IS
  'V438: a provider''s delivery report on a message — DELIVERED, BOUNCED or UNDELIVERED written on the SENT message it names; a report on no message, on one not sent, or with a word that says nothing is only logged.';

-- clear_notice_queue (V436) restated: the delivered history counted with the rest
CREATE OR REPLACE FUNCTION platform.clear_notice_queue(p_channels text[], p_reason text, p_actor uuid, p_office text)
RETURNS platform.notice_clearance LANGUAGE plpgsql AS $$
DECLARE c platform.notice_clearance; s platform.notice_setting; ch text[];
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); eb int; sb int; ec int; sc int;
BEGIN
    ch := ARRAY(SELECT DISTINCT upper(btrim(x)) FROM unnest(coalesce(p_channels, '{}'::text[])) x WHERE btrim(x) <> '' ORDER BY 1);
    IF coalesce(array_length(ch, 1), 0) = 0 OR EXISTS (SELECT 1 FROM unnest(ch) x WHERE x NOT IN ('EMAIL', 'SMS')) THEN
        RAISE EXCEPTION 'NOTICE_CLEAR_CHANNEL: the queue cleared is e-mail, SMS or both; a portal notice is delivered the moment it is made and is never pending' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'NOTICE_CLEAR_REASON: a reason is recorded with every clearance' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM platform.notice_setting WHERE id FOR UPDATE;
    IF s.dispatch_enabled THEN
        RAISE EXCEPTION 'NOTICE_CLEAR_DISPATCHING: pause queue processing first, so that nothing is sent while the queue is cleared' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) FILTER (WHERE n.channel = 'EMAIL'), count(*) FILTER (WHERE n.channel = 'SMS') INTO eb, sb
      FROM platform.notice n WHERE n.state = 'QUEUED';
    WITH done AS (
        UPDATE platform.notice SET state = 'CANCELLED', cancelled_at = now(), cancelled_by = p_actor, cancel_reason = v_reason
         WHERE state = 'QUEUED' AND channel = ANY (ch)
        RETURNING channel)
    SELECT count(*) FILTER (WHERE done.channel = 'EMAIL'), count(*) FILTER (WHERE done.channel = 'SMS') INTO ec, sc FROM done;
    INSERT INTO platform.notice_clearance (cleared_by, cleared_office, channels, reason, email_pending_before, sms_pending_before, email_cancelled, sms_cancelled,
                                           email_remaining, sms_remaining, email_sent, sms_sent, email_failed, sms_failed, jobs_open, campaigns_sending,
                                           email_delivered, sms_delivered)
    SELECT p_actor, p_office, ch, v_reason, eb, sb, ec, sc,
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'QUEUED' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'QUEUED' AND n.channel = 'SMS'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'SENT' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'SENT' AND n.channel = 'SMS'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'FAILED' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'FAILED' AND n.channel = 'SMS'),
           (SELECT count(*) FROM platform.notice_job j WHERE j.state IN ('QUEUED', 'RUNNING')),
           (SELECT count(*) FROM platform.notice_campaign x WHERE x.state = 'SENDING'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'SENT' AND n.delivery_state = 'DELIVERED' AND n.channel = 'EMAIL'),
           (SELECT count(*) FROM platform.notice n WHERE n.state = 'SENT' AND n.delivery_state = 'DELIVERED' AND n.channel = 'SMS')
    RETURNING * INTO c;
    RETURN c;
END $$;

COMMIT;
