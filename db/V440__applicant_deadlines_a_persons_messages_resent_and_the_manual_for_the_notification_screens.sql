-- ═══════════════════════════════════════
-- V440 — applicant deadlines, a person's messages resent, and the manual for the notification screens
--
-- 1 · Applicant deadlines. V438 reminds students before fees and registration close. Applicants have deadlines too: the
--     Post-UTME registration window (an application started and not submitted), admission status checking (a submitted
--     application whose status was never checked) and the Post-UTME CBT (a submitted application with no attempt). The same
--     daily pass queues them; the job runner reminds the applicants of the session who have not yet done what the window is
--     for, through WINDOW_CLOSING's applicant variants, once per deadline and day.
--
-- 2 · A person's messages. What the portal sent a student or a staff member — e-mail, SMS, portal — with the provider's word
--     where there is one, read on Student 360 and the HR record (platform.messages_for); a message that failed, was cancelled,
--     bounced or went undelivered is sent again to the address the record holds now (platform.resend_notice), the new message
--     remembering the one it repeats (platform.notice.resent_from).
--
-- 3 · The Quick Operational Manual gains the procedures of the screens built since its second edition: notification templates
--     and settings, campaigns, the delivery switches and the queue cleared, the receipt door, biodata compliance and staff
--     reach, the Quickteller door, and a student's messages. Seeded as the first edition was (published at birth; an existing
--     key is left alone), bound to the offices whose menus carry the screens; the edition takes a minor step.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V440: applicant deadlines, a person''s messages resent, the manual for the notification screens', true);

-- ── 1 · applicant deadlines ──────────────────────────────────────────────────────────────────────────────────────────────────
-- whether an applicant has done what a window is for; an application never submitted has nothing to check or sit
CREATE FUNCTION policy.applicant_window_done(p_type text, p_session text, p_application uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_type = 'POST_UTME_REGISTRATION' THEN
            coalesce((SELECT a.submitted_at IS NOT NULL FROM admissions.application a WHERE a.id = p_application), true)
        WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM admissions.status_check c WHERE c.application_id = p_application)
        WHEN p_type = 'POST_UTME_CBT' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.application_id = p_application)
        ELSE true END
$$;

-- the applicants a window's reminder is for: the applications of the session with an account, in id order from a cursor
CREATE FUNCTION platform.applicant_window_audience(p_type text, p_session text, p_after uuid, p_limit int)
RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
    SELECT a.id
      FROM admissions.application a JOIN admissions.applicant_account acc ON acc.id = a.account_id
     WHERE a.session = p_session
       AND (p_after IS NULL OR a.id > p_after)
     ORDER BY a.id
     LIMIT greatest(1, p_limit)
$$;

CREATE FUNCTION platform.applicant_window_type(p_type text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT')
$$;

-- the daily pass (V438) restated: the applicant windows join the fees and registration windows
CREATE OR REPLACE FUNCTION platform.queue_closing_reminders(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql AS $$
DECLARE w record; n int := 0; v_deadline timestamptz; v_days int; v_today date := (p_now AT TIME ZONE 'Africa/Lagos')::date; v_date text;
BEGIN
    IF NOT coalesce((SELECT s.closing_reminders FROM platform.notice_setting s WHERE s.id), true) THEN RETURN 0; END IF;
    FOR w IN SELECT x.* FROM policy.portal_window x
              WHERE x.superseded_at IS NULL AND x.forced IS NULL
                AND (x.window_type LIKE '%SCHOOL_FEES_PAYMENT' OR x.window_type LIKE '%COURSE_REGISTRATION' OR platform.applicant_window_type(x.window_type))
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

-- the job runner (V438) restated: a CLOSING job for an applicant window reminds the applicants not yet done
CREATE OR REPLACE FUNCTION platform.run_notice_job(p_limit int DEFAULT NULL)
RETURNS TABLE(job_id uuid, kind text, reached int, queued int, done boolean)
LANGUAGE plpgsql AS $$
DECLARE j record; c platform.notice_campaign; v_limit int := coalesce(p_limit, (SELECT job_batch FROM platform.notice_setting WHERE id), 2000);
        v_key text; v_vars jsonb; v_event text; s uuid; r record; v_reached int := 0; v_queued int := 0; v_last uuid;
        v_kind text; v_after uuid; v_done boolean; v_action text; v_type text;
BEGIN
    SELECT * INTO j FROM platform.notice_job x WHERE x.state IN ('QUEUED', 'RUNNING') ORDER BY x.created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN; END IF;
    UPDATE platform.notice_job SET state = 'RUNNING', started_at = coalesce(started_at, now()), runs = runs + 1 WHERE id = j.id;
    BEGIN
        IF j.kind = 'WINDOW' THEN
            v_action := j.payload ->> 'action';
            v_type := j.payload ->> 'type';
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
            IF v_action = 'CLOSING' AND platform.applicant_window_type(v_type) THEN
                FOR s IN SELECT * FROM platform.applicant_window_audience(v_type, j.payload ->> 'session', j.cursor_id, v_limit) LOOP
                    IF NOT policy.applicant_window_done(v_type, j.payload ->> 'session', s) THEN
                        v_queued := v_queued + platform.tell_applicant(s, v_key, v_type, v_vars, v_event);
                    END IF;
                    v_reached := v_reached + 1; v_last := s;
                END LOOP;
            ELSE
                FOR s IN SELECT * FROM policy.window_audience(v_type, j.payload ->> 'session', j.cursor_id, v_limit) LOOP
                    IF v_action <> 'CLOSING' OR NOT policy.window_done(v_type, j.payload ->> 'session', (j.payload ->> 'semester')::int, s) THEN
                        v_queued := v_queued + platform.tell_student(s, v_key, v_type, v_vars, v_event);
                    END IF;
                    v_reached := v_reached + 1; v_last := s;
                END LOOP;
            END IF;
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
  'V440 (V438 restated): drains the oldest open notification job by one batch — a window''s students, or for an applicant window''s CLOSING job the applicants not yet done, or a campaign''s students, staff and applicants in turn; the kind and cursor kept on the job.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('WINDOW_CLOSING:POST_UTME_REGISTRATION', 'Post-UTME registration closing',
 'The reminder before Post-UTME registration closes, to the applicants of the session who started an application and have not submitted it',
 'Post-UTME registration for [SESSION] closes [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows your application ([APPLICATION_NUMBER]) has not been submitted. [LATE_NOTE]\n\nComplete and submit it on the portal before then: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: Post-UTME registration for [SESSION] closes [DAYS_WORD] ([DEADLINE]) and your application is not yet submitted. Submit it on the portal before then.',
 'Post-UTME registration closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; your application has not been submitted. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','JAMB_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSING:ADMISSION_STATUS_CHECKING', 'Admission status checking closing',
 'The reminder before admission status checking closes, to the applicants of the session who submitted an application and have not checked their status',
 'Admission status checking for [SESSION] closes [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows you have not yet checked your admission status. [LATE_NOTE]\n\nCheck it on the portal before then: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: admission status checking for [SESSION] closes [DAYS_WORD] ([DEADLINE]) and you have not checked yours. Check it on the portal before then.',
 'Admission status checking closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; you have not yet checked your admission status. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','JAMB_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSING:POST_UTME_CBT', 'Post-UTME CBT closing',
 'The reminder before the Post-UTME CBT window closes, to the applicants of the session who submitted an application and have not sat the examination',
 'The Post-UTME CBT for [SESSION] closes [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows you have not yet sat the examination. [LATE_NOTE]\n\nSit it before then; your sitting and the way in are on the portal: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: the Post-UTME CBT for [SESSION] closes [DAYS_WORD] ([DEADLINE]) and you have not sat it. See your sitting on the portal.',
 'Post-UTME CBT closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; you have not yet sat the examination. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','JAMB_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH');

-- ── 2 · a person's messages, and one sent again ──────────────────────────────────────────────────────────────────────────────
ALTER TABLE platform.notice ADD COLUMN resent_from uuid NULL REFERENCES platform.notice (id);
COMMENT ON COLUMN platform.notice.resent_from IS 'V440: the message this one repeats, sent again by an office to the address the record holds now';
CREATE INDEX ix_notice_resent_from ON platform.notice (resent_from) WHERE resent_from IS NOT NULL;

CREATE FUNCTION platform.messages_for(p_kind text, p_id uuid, p_limit int DEFAULT 100)
RETURNS TABLE (id uuid, channel text, recipient text, subject text, template_key text, created_at timestamptz, state text, sent_at timestamptz,
               attempts int, last_error text, cancel_reason text, delivery_state text, delivered_at timestamptz, delivery_detail text,
               resent_from uuid, resent boolean)
LANGUAGE sql STABLE AS $$
    SELECT n.id, n.channel, n.recipient, n.subject, n.template_key, n.created_at, n.state, n.sent_at, n.attempts, n.last_error, n.cancel_reason,
           n.delivery_state, n.delivered_at, n.delivery_detail, n.resent_from,
           EXISTS (SELECT 1 FROM platform.notice r WHERE r.resent_from = n.id)
      FROM platform.notice n
     WHERE n.about_kind = p_kind AND n.about_id = p_id
     ORDER BY n.created_at DESC
     LIMIT greatest(1, coalesce(p_limit, 100))
$$;

-- a message that failed, was cancelled, bounced or went undelivered, sent again to the address the record holds now
CREATE FUNCTION platform.resend_notice(p_notice uuid, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE n platform.notice; v_to text; v_id uuid;
BEGIN
    SELECT * INTO n FROM platform.notice x WHERE x.id = p_notice;
    IF n.id IS NULL THEN RAISE EXCEPTION 'NOTICE_NONE: no such message' USING ERRCODE = '23514'; END IF;
    IF n.channel NOT IN ('EMAIL', 'SMS') THEN
        RAISE EXCEPTION 'NOTICE_RESEND_CHANNEL: a portal notice is on the dashboard already; only an e-mail or an SMS is sent again' USING ERRCODE = '23514';
    END IF;
    IF NOT (n.state IN ('FAILED', 'CANCELLED') OR (n.state = 'SENT' AND n.delivery_state IN ('BOUNCED', 'UNDELIVERED'))) THEN
        RAISE EXCEPTION 'NOTICE_RESEND_STATE: a message is sent again only when it failed, was cancelled, bounced or went undelivered; this one is %', lower(n.state) USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM platform.notice r WHERE r.resent_from = n.id AND r.state IN ('QUEUED', 'SENT')) THEN
        RAISE EXCEPTION 'NOTICE_RESEND_DONE: this message was already sent again' USING ERRCODE = '23514';
    END IF;
    -- the address the record holds now; the one on the message when the record holds none
    v_to := CASE n.about_kind
                WHEN 'student' THEN (SELECT CASE n.channel WHEN 'EMAIL' THEN r.email ELSE r.phone END FROM people.student_reach(n.about_id) r)
                WHEN 'person' THEN (SELECT CASE n.channel WHEN 'EMAIL' THEN p.email ELSE p.phone END FROM iam.person p WHERE p.id = n.about_id)
                WHEN 'application' THEN (SELECT CASE n.channel WHEN 'EMAIL' THEN acc.email ELSE acc.phone END
                                           FROM admissions.application a JOIN admissions.applicant_account acc ON acc.id = a.account_id WHERE a.id = n.about_id)
                ELSE NULL END;
    v_to := coalesce(nullif(btrim(coalesce(v_to, '')), ''), n.recipient);
    v_id := platform.queue_notice(n.channel, v_to, n.subject, n.body, n.about_kind, n.about_id, NULL, n.template_key, n.priority);
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'NOTICE_RESEND_ADDRESS: the record holds no address to send this to' USING ERRCODE = '23514';
    END IF;
    UPDATE platform.notice SET resent_from = n.id WHERE id = v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION platform.resend_notice(uuid, uuid, text) IS
  'V440: a failed, cancelled, bounced or undelivered e-mail or SMS queued again, to the address the record holds now, once; the new message remembers the one it repeats.';

-- ── 3 · the manual: the notification screens ─────────────────────────────────────────────────────────────────────────────────
SELECT manual.seed('notify-templates-words', 'Change the words of a message the portal sends', 'SETTINGS', ARRAY['ict', 'admin', 'super']::text[], 't/templates', NULL,
    'Every message the portal sends — a window opening, a fee paid, a reminder — comes from a template keyed by its event. The words are changed here, never in a module.',
    ARRAY['Open {menu:t/templates}.',
          'Find the template by its key or label (a key with a suffix, such as WINDOW_CLOSED:SCHOOL_FEES_PAYMENT, overrides the base key for that window) and click it.',
          'Edit the `E-mail subject`, `E-mail body`, `SMS body`, `Portal title` and `Portal body`; keep the [TOKENS] the template lists, in square brackets.',
          'Click `Preview` to read the three texts on sample values.',
          'Click `Save`. The next message of that event uses the new words; messages already queued keep theirs.'],
    'The template shows its new words and the preview reads them on sample values.', '{}', 10);

SELECT manual.seed('notify-templates-test', 'Send a test of a template to one address', 'SETTINGS', ARRAY['ict', 'admin', 'super']::text[], 't/templates', NULL,
    'A real message from a template to one e-mail address or phone, about nobody, so the words are seen as they arrive.',
    ARRAY['Open {menu:t/templates} and click the template.',
          'Enter an `E-mail` address or a `Phone` number under Test.',
          'Click `Send a test`.',
          'Read the message where it arrives; it is in the outbox on the Notifications screen (Directorate of ICT) like any other, about nobody.'],
    'The test message is queued and arrives at the address given.', '{}', 20);

SELECT manual.seed('notify-settings-reminders', 'Switch the weekly and closing reminders on or off', 'SETTINGS', ARRAY['ict', 'admin', 'super']::text[], 't/templates', NULL,
    'The biodata reminder (Monday), the staff contact reminder (Tuesday) and the reminders three days and one day before a fees or registration window closes run on switches here.',
    ARRAY['Open {menu:t/templates} and scroll to Settings.',
          'Tick or untick `Weekly biodata reminder`, `Weekly staff contact reminder` and `Reminders before a window closes`; set `People a job reaches per run` if a session is unusually large.',
          'Click `Save settings`.',
          'To run one at once, click `Run the biodata reminder now`, `Run the staff contact reminder now` or `Run the closing reminders now`.'],
    'The settings show the switches as set; a run reports how many were reminded or how many window jobs were queued.', '{}', 30);

SELECT manual.seed('notify-campaign-send', 'Send an announcement to many', 'SETTINGS', ARRAY['ict', 'admin', 'super', 'registrar', 'academic']::text[], 't/campaigns', NULL,
    'A message to the students, staff, lecturers or applicants the filters name, read from the record when it is sent: nobody is typed in, each person is reached once per channel.',
    ARRAY['Open {menu:t/campaigns} and click `New campaign`.',
          'Give it a `Name`, choose the `Template` (an announcement takes your own `Title`, `Message`, `SMS message` and `Signature`), tick who it is for and set the filters (session, faculty, department, programme, level, entry mode).',
          'Tick the `Channels` and click `Save`.',
          'Click `Preview`: it counts who would be reached and whose e-mail or phone is missing or not one.',
          'Enter an address under Test and click `Send a test` to read the words as they arrive.',
          'Click `Send` and confirm. The first batch goes at once; the rest follow every half-minute. If a delivery switch is off on the Notifications screen (Directorate of ICT), the screen says the messages will wait.',
          'Read the report on the campaign: queued, sent, failed and bad addresses by channel. `Cancel` stops a campaign still sending.'],
    'The campaign is SENT with its report by channel; each person has the message on the channels they have.', '{}', 40);

SELECT manual.seed('notify-delivery-switches', 'Hold e-mail and SMS while the portal is tested', 'SETTINGS', ARRAY['ict', 'admin']::text[], 't/notify', NULL,
    'While the portal is tested, the modules go on generating their messages and the outbox holds them unsent: delivery is switched, generation never is.',
    ARRAY['Open {menu:t/notify} and find Delivery.',
          'Untick `E-mail delivery` and `SMS delivery` to hold them; untick `Queue processing` to hold every channel; untick `Portal notices` to keep them from being made.',
          'Test templates and campaigns as usual: their messages wait in the outbox and are read there.',
          'Tick the switches again when real delivery should start; what waited goes out, unless the queue was cleared first.'],
    'The Delivery panel shows each switch as set and the outbox holds what is not sent.', '{}', 50);

SELECT manual.seed('notify-queue-clear', 'Cancel the pending e-mail and SMS queue', 'SETTINGS', ARRAY['ict']::text[], 't/notify', NULL,
    'Messages generated during testing that must not go out are cancelled, never deleted: they stay in the history marked cancelled with your reason; sent, delivered and failed messages are untouched.',
    ARRAY['Open {menu:t/notify} and find Queue management; read how many e-mails and SMS wait.',
          'Tick `E-mail`, `SMS` or both, and write the `Reason`.',
          'Click `Clear pending queue…` and read the confirmation: the counts, and that sent and failed messages stay.',
          'Click `Cancel … unsent messages`. Queue processing is paused first and the clearance runs under the dispatcher''s own lock, so nothing is sent meanwhile.',
          'Read the clearance report: pending before, cancelled, remaining (0), sent and failed untouched.',
          'End any job still writing to the queue under Jobs still writing to the queue, if its messages are not wanted.',
          'Click `Resume queue processing` once the counts are verified.'],
    'The report shows remaining pending 0, the history keeps every message, and queue processing is running again.', '{}', 60);

SELECT manual.seed('notify-receipts-door', 'Let a provider report delivery', 'SETTINGS', ARRAY['ict', 'admin']::text[], 't/notify', NULL,
    'A message is sent when the provider accepts it; a provider that reports further — delivered, bounced, undelivered — posts to the receipt door, and the word lands on the message.',
    ARRAY['Open {menu:t/notify} and find Delivery receipts.',
          'Click `Generate the token`; click `Show the token` to copy it.',
          'Give the provider the door address with the token: Resend''s webhooks to /api/v1/notices/receipts/resend, eBulkSMS''s delivery reports to /api/v1/notices/receipts/ebulksms, anything else to /api/v1/notices/receipts/generic, the token as ?token= or the header X-Receipt-Token.',
          'Watch the reports arrive in the list below the token: each is kept as it came, matched or not, so what the provider actually sends is seen.',
          'A message whose report says delivered or bounced shows it on {menu:t/notify} and on the person''s record.'],
    'Reports from the provider appear in the list with their outcome, and delivered or bounced messages show it.', '{}', 70);

SELECT manual.seed('biodata-compliance-read', 'Read the biodata compliance picture', 'STUDENTS', ARRAY['ict', 'admin', 'super', 'registrar', 'academic', 'dean', 'hod']::text[], 't/compliance', NULL,
    'How many students are up to date, incomplete, to review or outdated, who came over from the old portal, who has no e-mail or phone, and the students behind each count — a Dean or Head reads their own faculty or department.',
    ARRAY['Open {menu:t/compliance}.',
          'Read the tiles; the reading is taken every quarter of an hour, and its time is shown.',
          'Click a tile, or set the `Status`, `Faculty`, `Department`, `Programme`, `Level`, `Entry session`, `Entry mode` and `Came over` filters, to list the students behind it; search by name, number, e-mail or phone.',
          'Click `Print` or `Export` for the list as filtered.',
          'Read Data quality for addresses missing, not addresses, or shared by several students.'],
    'The counts and the list match the filters, and the export carries the same rows.', '{}', 80);

SELECT manual.seed('biodata-staff-reach', 'See which staff the portal cannot reach', 'STUDENTS', ARRAY['ict', 'admin', 'super', 'registrar']::text[], 't/compliance', NULL,
    'For every active person with an office: whether the e-mail and the phone are present and usable, who never signed in, and who was reminded this week.',
    ARRAY['Open {menu:t/compliance} and click `Staff reach`.',
          'Read the summary: reachable, phone only, e-mail only, unreachable, never signed in.',
          'Filter by `Status` and `Office`, or search by name or number, to list the people behind a count.',
          'The weekly reminder to them runs on `Weekly staff contact reminder` under Notification templates (Directorate of ICT); a person with no usable address is also asked for one when they sign in.'],
    'The list shows each person with the state of their e-mail and phone.', '{}', 90);

SELECT manual.seed('quickteller-door-watch', 'Know when the Quickteller door goes quiet', 'PAYMENTS', ARRAY['ict', 'admin', 'bursar']::text[], 't/gateways', NULL,
    'Interswitch validates references and reports payments at the PAYDirect door. When the door has been quiet for longer than its own rhythm allows, the Directorate of ICT and the Bursary are told once per silence.',
    ARRAY['Open {menu:t/gateways} and find The Quickteller door.',
          'Read the last validation, the last notification, how long the door has been quiet and the threshold it is judged by.',
          'Click `Check now` to run the watch at once.',
          'On a silence, check with Interswitch that their messages reach the door address, and the firewall in front of the portal; payments already made come in with the collections import once the door is open again.',
          'Set `Least silence reported, hours` and `Watch the door` under the tiles (Directorate of ICT).'],
    'The door shows its state against its rhythm, and a silence has been reported once.', '{}', 100);

SELECT manual.seed('quickteller-door-list', 'Keep the Quickteller door to Interswitch''s addresses', 'PAYMENTS', ARRAY['ict', 'admin']::text[], 't/gateways', NULL,
    'The validation door needs no credential, so it may be kept to Interswitch''s live addresses. It is never switched on blind: the addresses seen at the door are compared with the list first.',
    ARRAY['Open {menu:t/gateways} and find Kept to these addresses under The Quickteller door.',
          'Enter each of Interswitch''s live addresses (or a range such as 41.223.145.0/24) with a `Label` and click `Add`.',
          'Read Who called in the last seven days: at least one listed address must have called, or the switch is refused.',
          'Tick `Answer only the listed addresses`.',
          'If payments stop, read the refused count beside the addresses seen and untick the switch while the list is corrected.'],
    'The door answers the listed addresses only; a stranger is refused and counted.', '{}', 110);

SELECT manual.seed('student-messages-resend', 'See what the portal sent a student, and send one again', 'STUDENTS', ARRAY['ict', 'admin', 'registrar', 'dregistrar', 'academic']::text[], 't/students', NULL,
    'Every e-mail, SMS and portal notice the portal sent a student, with the provider''s word where there is one; a message that failed, was cancelled, bounced or went undelivered is sent again to the address the record holds now.',
    ARRAY['Open {menu:t/students}, find the student and open the record.',
          'Scroll to Messages: each message with its channel, when it was queued, its state and what the provider reported.',
          'If the address on the record is wrong, correct it first on the record.',
          'Click `Send again` on the message; it is queued to the current address, and the list shows the new message beside the old.'],
    'The message appears again as queued, and goes out with the next batch.', '{}', 120);

SELECT manual.bump_edition('00000000-0000-0000-0000-000000000000', 'ict', 'V440: the notification screens, biodata compliance, the Quickteller door and a student''s messages', false);

COMMIT;
