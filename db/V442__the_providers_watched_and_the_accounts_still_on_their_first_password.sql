-- ═══════════════════════════════════════
-- V442 — the providers watched, and the accounts still on their first password
--
-- 1 · The reminders, campaigns and window messages all depend on the mail and SMS providers, and nothing noticed when one
--     stopped accepting: an eBulkSMS account out of credit, or a mail password changed, turned every message into a quiet
--     failure. The dispatcher now counts every attempt by channel, provider and hour (platform.dispatch_tally), and a watch
--     (platform.watch_providers, every ten minutes) reads each channel's state from those counts and the outbox:
--       OFF          queue processing paused or the channel's delivery switched off (V436) — not a fault;
--       FAILING      in the last two clock hours at least failing_min messages were tried and failing_share per cent failed;
--       STUCK        a message has waited stuck_minutes with nothing tried on its channel (no provider wired, or the
--                    dispatcher not running);
--       LOW_BALANCE  the SMS account's balance, read from eBulkSMS, is below sms_low_balance (0 switches the warning off);
--       OK / IDLE    messages are going, or nothing is asked of the channel.
--     The Directorate of ICT is told once per episode, through PROVIDER_PROBLEM, on the channels that still work (an e-mail
--     problem is told by SMS and on the portal, an SMS problem by e-mail and on the portal); a recovery ends the episode.
--
-- 2 · With the first sign-in on the person's own number restored (13 Oct 2026, at the user's word), any account nobody has
--     claimed opens to whoever knows the number. The accounts still on their first password — as the doors judge it: a
--     student account to be changed with no temporary password standing, a staff credential to be changed, an applicant
--     account on its first-login sentinel — are counted and listed on Biodata compliance (a Dean or Head within their own
--     faculty or department), and a campaign may be written to exactly them (filter first_password, template
--     FIRST_PASSWORD_REMINDER).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V442: the providers watched, and the accounts still on their first password', true);

-- ── 1 · the providers watched ────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE platform.notice_setting
    ADD COLUMN provider_watch  boolean NOT NULL DEFAULT true,
    ADD COLUMN failing_share   int NOT NULL DEFAULT 50 CHECK (failing_share BETWEEN 5 AND 100),
    ADD COLUMN failing_min     int NOT NULL DEFAULT 10 CHECK (failing_min BETWEEN 1 AND 10000),
    ADD COLUMN stuck_minutes   int NOT NULL DEFAULT 30 CHECK (stuck_minutes BETWEEN 5 AND 1440),
    ADD COLUMN sms_low_balance numeric NOT NULL DEFAULT 500 CHECK (sms_low_balance >= 0);
COMMENT ON COLUMN platform.notice_setting.provider_watch IS 'V442: whether the Directorate of ICT is told when a provider fails, the queue is stuck or the SMS balance runs low';
COMMENT ON COLUMN platform.notice_setting.sms_low_balance IS 'V442: the SMS balance (eBulkSMS units) below which ICT is warned; 0 switches the warning off';

CREATE TABLE platform.dispatch_tally (
    channel       text NOT NULL CHECK (channel IN ('EMAIL', 'SMS')),
    provider      text NOT NULL,
    hour          timestamptz NOT NULL,
    tried         int NOT NULL DEFAULT 0,
    failed        int NOT NULL DEFAULT 0,
    last_error    text NULL,
    last_error_at timestamptz NULL,
    last_ok_at    timestamptz NULL,
    PRIMARY KEY (channel, provider, hour)
);
COMMENT ON TABLE platform.dispatch_tally IS 'V442: every attempt the dispatcher made, counted by channel, provider and hour, with the last error — what the provider watch reads';
SELECT audit.exempt('platform.dispatch_tally', 'counts of the dispatcher''s attempts by channel, provider and hour, written on every send; the messages themselves are audited on platform.notice');

CREATE FUNCTION platform.record_attempt(p_channel text, p_provider text, p_ok boolean, p_error text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO platform.dispatch_tally AS t (channel, provider, hour, tried, failed, last_error, last_error_at, last_ok_at)
    VALUES (p_channel, coalesce(nullif(btrim(coalesce(p_provider, '')), ''), 'unknown'), date_trunc('hour', now()), 1,
            CASE WHEN p_ok THEN 0 ELSE 1 END, CASE WHEN p_ok THEN NULL ELSE left(coalesce(p_error, ''), 300) END,
            CASE WHEN p_ok THEN NULL ELSE now() END, CASE WHEN p_ok THEN now() END)
    ON CONFLICT (channel, provider, hour) DO UPDATE
       SET tried = t.tried + 1,
           failed = t.failed + CASE WHEN p_ok THEN 0 ELSE 1 END,
           last_error = CASE WHEN p_ok THEN t.last_error ELSE left(coalesce(p_error, ''), 300) END,
           last_error_at = CASE WHEN p_ok THEN t.last_error_at ELSE now() END,
           last_ok_at = CASE WHEN p_ok THEN now() ELSE t.last_ok_at END
$$;

CREATE TABLE platform.provider_health (
    channel       text PRIMARY KEY CHECK (channel IN ('EMAIL', 'SMS')),
    state         text NOT NULL DEFAULT 'IDLE',
    since         timestamptz NOT NULL DEFAULT now(),
    alerted_state text NULL,
    alerted_at    timestamptz NULL,
    balance       numeric NULL,
    balance_raw   text NULL,
    balance_at    timestamptz NULL,
    checked_at    timestamptz NULL
);
COMMENT ON TABLE platform.provider_health IS 'V442: each channel''s state as the watch last read it, since when, the problem last told to ICT (one message per episode), and the SMS balance';
SELECT audit.exempt('platform.provider_health', 'the provider watch''s own reading, rewritten every ten minutes; what it told ICT is on platform.notice');
INSERT INTO platform.provider_health (channel) VALUES ('EMAIL'), ('SMS');

-- the SMS balance as eBulkSMS answered it: the number when it is one, the answer as it came either way
CREATE FUNCTION platform.record_sms_balance(p_raw text, p_value numeric)
RETURNS void LANGUAGE sql AS $$
    UPDATE platform.provider_health SET balance = p_value, balance_raw = left(coalesce(p_raw, ''), 120), balance_at = now() WHERE channel = 'SMS'
$$;

-- each channel's state now, from the last two clock hours of attempts, the outbox and the switches
CREATE FUNCTION platform.provider_status()
RETURNS TABLE (channel text, state text, since timestamptz, delivery_on boolean, tried bigint, failed bigint, last_error text, last_error_at timestamptz,
               last_ok_at timestamptz, providers text, waiting bigint, oldest_waiting timestamptz, balance numeric, balance_raw text, balance_at timestamptz,
               alerted_state text, alerted_at timestamptz, checked_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM platform.notice_setting WHERE id),
         t AS (SELECT x.channel, sum(x.tried) AS tried, sum(x.failed) AS failed, max(x.last_ok_at) AS last_ok_at, max(x.last_error_at) AS last_error_at,
                      (array_agg(x.last_error ORDER BY x.last_error_at DESC NULLS LAST))[1] AS last_error, string_agg(DISTINCT x.provider, ', ') AS providers
                 FROM platform.dispatch_tally x WHERE x.hour >= date_trunc('hour', now()) - interval '1 hour' GROUP BY x.channel),
         q AS (SELECT n.channel, count(*) AS waiting, min(n.created_at) AS oldest FROM platform.notice n
                WHERE n.state = 'QUEUED' AND n.channel IN ('EMAIL', 'SMS') GROUP BY n.channel)
    SELECT h.channel,
           CASE WHEN NOT s.dispatch_enabled OR NOT CASE h.channel WHEN 'EMAIL' THEN s.email_delivery ELSE s.sms_delivery END THEN 'OFF'
                WHEN coalesce(t.tried, 0) >= s.failing_min AND coalesce(t.failed, 0) * 100 >= s.failing_share * t.tried THEN 'FAILING'
                WHEN q.oldest IS NOT NULL AND q.oldest < now() - make_interval(mins => s.stuck_minutes) AND coalesce(t.tried, 0) = 0 THEN 'STUCK'
                WHEN h.channel = 'SMS' AND h.balance IS NOT NULL AND s.sms_low_balance > 0 AND h.balance < s.sms_low_balance THEN 'LOW_BALANCE'
                WHEN coalesce(t.tried, 0) > 0 THEN 'OK'
                ELSE 'IDLE' END,
           h.since,
           s.dispatch_enabled AND CASE h.channel WHEN 'EMAIL' THEN s.email_delivery ELSE s.sms_delivery END,
           coalesce(t.tried, 0), coalesce(t.failed, 0), t.last_error, t.last_error_at, t.last_ok_at, t.providers,
           coalesce(q.waiting, 0), q.oldest, h.balance, h.balance_raw, h.balance_at, h.alerted_state, h.alerted_at, h.checked_at
      FROM platform.provider_health h CROSS JOIN s
      LEFT JOIN t ON t.channel = h.channel
      LEFT JOIN q ON q.channel = h.channel
     ORDER BY h.channel
$$;

-- the watch: each channel's state kept with when it began; a problem told to ICT once per episode, on the channels that still work
CREATE FUNCTION platform.watch_providers()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE s platform.notice_setting; r record; h platform.provider_health; p record; told int := 0; v_since timestamptz; v_vars jsonb; v_channels text[];
BEGIN
    SELECT * INTO s FROM platform.notice_setting WHERE id;
    DELETE FROM platform.dispatch_tally WHERE hour < now() - interval '30 days';
    FOR r IN SELECT * FROM platform.provider_status() LOOP
        SELECT * INTO h FROM platform.provider_health x WHERE x.channel = r.channel FOR UPDATE;
        IF h.state IS DISTINCT FROM r.state THEN
            v_since := clock_timestamp();   -- the episode's own start, distinct even within one transaction
            -- a channel that is well again (or switched off) ends the episode: the next problem is told afresh
            UPDATE platform.provider_health
               SET state = r.state, since = v_since, checked_at = now(),
                   alerted_state = CASE WHEN r.state IN ('FAILING', 'STUCK', 'LOW_BALANCE') THEN alerted_state END
             WHERE channel = r.channel;
            IF r.state NOT IN ('FAILING', 'STUCK', 'LOW_BALANCE') THEN h.alerted_state := NULL; END IF;
        ELSE
            v_since := h.since;
            UPDATE platform.provider_health SET checked_at = now() WHERE channel = r.channel;
        END IF;
        IF s.provider_watch AND r.state IN ('FAILING', 'STUCK', 'LOW_BALANCE') AND h.alerted_state IS DISTINCT FROM r.state THEN
            v_channels := CASE r.channel WHEN 'EMAIL' THEN ARRAY['SMS', 'PORTAL'] ELSE ARRAY['EMAIL', 'PORTAL'] END;
            v_vars := jsonb_build_object(
                'CHANNEL_WORD', CASE r.channel WHEN 'EMAIL' THEN 'e-mail' ELSE 'SMS' END,
                'TRIED', r.tried, 'FAILED', r.failed,
                'LAST_ERROR', coalesce(nullif(r.last_error, ''), 'none recorded'),
                'WAITING', r.waiting,
                'OLDEST', coalesce(to_char(r.oldest_waiting AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI'), ''),
                'BALANCE', coalesce(trim_scale(r.balance)::text, nullif(r.balance_raw, ''), 'unknown'),
                'THRESHOLD', trim_scale(s.sms_low_balance)::text);
            FOR p IN SELECT DISTINCT a.person_id
                       FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
                      WHERE a.office_code = 'ict' AND pe.ended_on IS NULL
                        AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
                told := told + platform.tell_person(p.person_id, 'PROVIDER_PROBLEM', r.state, v_vars,
                                                    'provider:' || r.channel || ':' || r.state || ':' || to_char(v_since AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS'),
                                                    v_channels);
            END LOOP;
            UPDATE platform.provider_health SET alerted_state = r.state, alerted_at = now() WHERE channel = r.channel;
        END IF;
    END LOOP;
    RETURN told;
END $$;
COMMENT ON FUNCTION platform.watch_providers() IS
  'V442: each channel''s state read and kept with when it began; FAILING, STUCK or LOW_BALANCE told to every ICT office holder once per episode, through PROVIDER_PROBLEM, on the channels that still work. Returns the messages queued.';

CREATE FUNCTION platform.set_provider_watch(p_watch boolean, p_low_balance numeric, p_actor uuid, p_office text)
RETURNS void LANGUAGE sql AS $$
    UPDATE platform.notice_setting
       SET provider_watch = coalesce(p_watch, provider_watch),
           sms_low_balance = coalesce(p_low_balance, sms_low_balance),
           updated_by = p_actor, updated_office = p_office, updated_at = now()
     WHERE id
$$;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PROVIDER_PROBLEM', 'Message provider problem',
 'To the Directorate of ICT when a message provider fails, the queue is stuck or the SMS balance runs low; once per episode, on the channels that still work',
 'The portal''s [CHANNEL_WORD] is not going out',
 E'Dear [FIRST_NAME],\n\nThe portal''s [CHANNEL_WORD] messages are not going out as they should. In the last two hours [TRIED] were tried and [FAILED] failed; [WAITING] are waiting. The last error: [LAST_ERROR].\n\nCheck the provider''s account and settings on the portal: [PORTAL_URL]\n\nMOAUM Portal',
 '[UNIVERSITY_SHORT] portal: [CHANNEL_WORD] messages are not going out ([FAILED] of [TRIED] failed in two hours). Check the provider on the Notifications screen.',
 '[CHANNEL_WORD] messages are not going out',
 '[TRIED] tried and [FAILED] failed in the last two hours; [WAITING] waiting. Last error: [LAST_ERROR].',
 ARRAY['FIRST_NAME','CHANNEL_WORD','TRIED','FAILED','WAITING','LAST_ERROR','OLDEST','BALANCE','THRESHOLD','PORTAL_URL','UNIVERSITY_SHORT'], true, 'CRITICAL'),
('PROVIDER_PROBLEM:FAILING', 'Message provider failing',
 'The provider refuses or fails most of what the portal sends it: told to ICT once per episode, on the channels that still work',
 'The portal''s [CHANNEL_WORD] provider is failing',
 E'Dear [FIRST_NAME],\n\nThe portal''s [CHANNEL_WORD] provider is failing: in the last two hours [TRIED] messages were tried and [FAILED] failed. The last error was:\n\n[LAST_ERROR]\n\n[WAITING] messages are waiting and are tried again as they fall due. Check the provider''s account (credit, password, API key) and the settings on the portal''s Notifications and gateway screens: [PORTAL_URL]\n\nMOAUM Portal',
 '[UNIVERSITY_SHORT] portal: the [CHANNEL_WORD] provider is failing ([FAILED] of [TRIED] in two hours). Last error: [LAST_ERROR]',
 '[CHANNEL_WORD] provider failing',
 '[FAILED] of [TRIED] [CHANNEL_WORD] messages failed in the last two hours; [WAITING] waiting. Last error: [LAST_ERROR].',
 ARRAY['FIRST_NAME','CHANNEL_WORD','TRIED','FAILED','WAITING','LAST_ERROR','PORTAL_URL','UNIVERSITY_SHORT'], true, 'CRITICAL'),
('PROVIDER_PROBLEM:STUCK', 'Message queue stuck',
 'Messages wait on a channel and nothing is tried: no provider wired, or the dispatcher not running',
 'The portal''s [CHANNEL_WORD] messages are waiting and none is sent',
 E'Dear [FIRST_NAME],\n\n[WAITING] [CHANNEL_WORD] messages are waiting on the portal, the oldest since [OLDEST], and none has been tried in the last two hours. Either no [CHANNEL_WORD] provider is wired (the Mail server or SMS gateway screen), or the dispatcher is not running.\n\nIf the messages are not wanted while the portal is tested, switch [CHANNEL_WORD] delivery off on the Notifications screen, or clear the queue there: [PORTAL_URL]\n\nMOAUM Portal',
 '[UNIVERSITY_SHORT] portal: [WAITING] [CHANNEL_WORD] messages waiting since [OLDEST], none sent. Check the provider on the Notifications screen.',
 '[CHANNEL_WORD] queue stuck',
 '[WAITING] [CHANNEL_WORD] messages waiting since [OLDEST]; none tried in two hours. Wire the provider, or switch the channel''s delivery off.',
 ARRAY['FIRST_NAME','CHANNEL_WORD','WAITING','OLDEST','PORTAL_URL','UNIVERSITY_SHORT'], true, 'CRITICAL'),
('PROVIDER_PROBLEM:LOW_BALANCE', 'SMS balance low',
 'The SMS account''s balance, read from eBulkSMS, is below the level set on the Notifications screen',
 'The portal''s SMS balance is low: [BALANCE]',
 E'Dear [FIRST_NAME],\n\nThe SMS account the portal sends through has [BALANCE] units left, below the [THRESHOLD] set on the Notifications screen. When it runs out, every SMS the portal sends fails.\n\nTop the account up with eBulkSMS: [PORTAL_URL]\n\nMOAUM Portal',
 NULL,
 'SMS balance low: [BALANCE]',
 'The SMS account has [BALANCE] units left, below [THRESHOLD]. Top it up before it runs out.',
 ARRAY['FIRST_NAME','BALANCE','THRESHOLD','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH');

-- ── 2 · the accounts still on their first password ───────────────────────────────────────────────────────────────────────────
-- as the doors judge it (StudentAuthService.onFirstPassword, AuthService, ApplicantService's sentinel)
CREATE FUNCTION iam.first_password_summary(p_faculty text, p_department text)
RETURNS TABLE (student_accounts bigint, students_first bigint, students_first_never bigint, students_signed_in_first bigint)
LANGUAGE sql STABLE AS $$
    SELECT count(*),
           count(*) FILTER (WHERE a.must_change AND a.temp_expires_at IS NULL),
           count(*) FILTER (WHERE a.must_change AND a.temp_expires_at IS NULL AND a.last_signed_in_at IS NULL),
           count(*) FILTER (WHERE a.must_change AND a.temp_expires_at IS NULL AND a.last_signed_in_at IS NOT NULL)
      FROM iam.student_account a
      JOIN people.student s ON s.id = a.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
     WHERE people.biodata_applicable(s.status)
       AND (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
$$;

-- the staff and the applicants: the University's, never bound to a faculty
CREATE FUNCTION iam.first_password_others()
RETURNS TABLE (staff_accounts bigint, staff_first bigint, staff_first_never bigint, applicants_first bigint)
LANGUAGE sql STABLE AS $$
    SELECT (SELECT count(*) FROM iam.credential c JOIN iam.person pe ON pe.id = c.person_id WHERE pe.ended_on IS NULL AND iam.is_staff(pe.id)),
           (SELECT count(*) FROM iam.credential c JOIN iam.person pe ON pe.id = c.person_id WHERE pe.ended_on IS NULL AND iam.is_staff(pe.id) AND c.must_change),
           (SELECT count(*) FROM iam.credential c JOIN iam.person pe ON pe.id = c.person_id WHERE pe.ended_on IS NULL AND iam.is_staff(pe.id) AND c.must_change AND c.last_sign_in_at IS NULL),
           (SELECT count(*) FROM admissions.applicant_account acc WHERE acc.password_hash = 'SET_ON_FIRST_LOGIN')
$$;

-- by faculty, or by department within a faculty, or by programme within a department
CREATE FUNCTION iam.first_password_units(p_faculty text, p_department text)
RETURNS TABLE (code text, name text, accounts bigint, first bigint, first_never bigint)
LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT CASE WHEN p_department IS NOT NULL THEN p.code WHEN p_faculty IS NOT NULL THEN p.dept_code ELSE p.faculty_code END AS unit,
               (a.must_change AND a.temp_expires_at IS NULL) AS first,
               (a.last_signed_in_at IS NULL) AS never
          FROM iam.student_account a
          JOIN people.student s ON s.id = a.student_id
          JOIN ref.programme p ON p.code = s.programme_code
         WHERE people.biodata_applicable(s.status)
           AND (p_faculty IS NULL OR p.faculty_code = p_faculty)
           AND (p_department IS NULL OR p.dept_code = p_department))
    SELECT x.unit,
           CASE WHEN p_department IS NOT NULL THEN (SELECT g.name FROM ref.programme g WHERE g.code = x.unit)
                WHEN p_faculty IS NOT NULL THEN (SELECT d.name FROM ref.department d WHERE d.code = x.unit)
                ELSE (SELECT f.name FROM ref.faculty f WHERE f.code = x.unit) END,
           count(*), count(*) FILTER (WHERE x.first), count(*) FILTER (WHERE x.first AND x.never)
      FROM x
     GROUP BY x.unit
     ORDER BY 4 DESC, 2
$$;

CREATE FUNCTION iam.first_password_students(p_faculty text, p_department text, p_programme text, p_level int, p_never boolean, p_q text, p_limit int, p_offset int)
RETURNS TABLE (student_id uuid, number text, name text, programme text, department text, faculty text, level int, status text,
               account_created timestamptz, last_signed_in_at timestamptz, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.name, p.dept_code, p.faculty_code, s.current_level, s.status,
           a.created_at, a.last_signed_in_at, count(*) OVER ()
      FROM iam.student_account a
      JOIN people.student s ON s.id = a.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
     WHERE a.must_change AND a.temp_expires_at IS NULL
       AND people.biodata_applicable(s.status)
       AND (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
       AND (p_programme IS NULL OR s.programme_code = p_programme)
       AND (p_level IS NULL OR s.current_level = p_level)
       AND (NOT coalesce(p_never, false) OR a.last_signed_in_at IS NULL)
       AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL
            OR s.surname ILIKE '%' || btrim(p_q) || '%' OR s.other_names ILIKE '%' || btrim(p_q) || '%'
            OR s.matric_no ILIKE '%' || btrim(p_q) || '%' OR s.admission_no ILIKE '%' || btrim(p_q) || '%')
     ORDER BY p.faculty_code NULLS LAST, p.dept_code NULLS LAST, s.surname, s.other_names
     LIMIT greatest(1, coalesce(p_limit, 100)) OFFSET greatest(0, coalesce(p_offset, 0))
$$;

CREATE FUNCTION iam.first_password_staff(p_office text, p_never boolean, p_q text, p_limit int, p_offset int)
RETURNS TABLE (person_id uuid, staff_number text, username text, name text, offices text, set_at timestamptz, last_sign_in_at timestamptz,
               email text, phone text, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT pe.id, pe.staff_number, c.username, pe.surname || ', ' || pe.given_names,
           (SELECT string_agg(DISTINCT o.label, ', ') FROM iam.office_assignment oa JOIN ref.office o ON o.code = oa.office_code
             WHERE oa.person_id = pe.id AND oa.office_code NOT IN ('student', 'applicant')
               AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)),
           c.set_at, c.last_sign_in_at, pe.email, pe.phone, count(*) OVER ()
      FROM iam.credential c
      JOIN iam.person pe ON pe.id = c.person_id
     WHERE c.must_change AND pe.ended_on IS NULL AND iam.is_staff(pe.id)
       AND (p_office IS NULL OR platform.office_active(pe.id, p_office))
       AND (NOT coalesce(p_never, false) OR c.last_sign_in_at IS NULL)
       AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL
            OR pe.surname ILIKE '%' || btrim(p_q) || '%' OR pe.given_names ILIKE '%' || btrim(p_q) || '%'
            OR pe.staff_number ILIKE '%' || btrim(p_q) || '%' OR c.username ILIKE '%' || btrim(p_q) || '%')
     ORDER BY pe.surname, pe.given_names
     LIMIT greatest(1, coalesce(p_limit, 100)) OFFSET greatest(0, coalesce(p_offset, 0))
$$;

-- campaign_recipients (V426) restated: the filter first_password reaches exactly the accounts still on their first password
CREATE OR REPLACE FUNCTION platform.campaign_recipients(p_campaign uuid, p_kind text, p_after uuid, p_limit int)
RETURNS TABLE(id uuid, email text, phone text) LANGUAGE plpgsql STABLE AS $$
DECLARE c platform.notice_campaign; f jsonb; v_students boolean; v_staff boolean; v_lecturers boolean; v_applicants boolean;
        v_migrated boolean; v_never boolean; v_first boolean; v_session text;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign;
    IF c.id IS NULL THEN RETURN; END IF;
    f := coalesce(c.audience -> 'filters', '{}'::jsonb);
    v_students := coalesce((c.audience ->> 'students')::boolean, false);
    v_staff := coalesce((c.audience ->> 'staff')::boolean, false);
    v_lecturers := coalesce((c.audience ->> 'lecturers')::boolean, false);
    v_applicants := coalesce((c.audience ->> 'applicants')::boolean, false);
    v_migrated := coalesce((f ->> 'migrated')::boolean, false);
    v_never := coalesce((f ->> 'never_signed_in')::boolean, false);
    v_first := coalesce((f ->> 'first_password')::boolean, false);
    v_session := nullif(btrim(coalesce(f ->> 'session', '')), '');
    IF p_kind = 'student' AND v_students THEN
        RETURN QUERY
        SELECT s.id, r.email, r.phone
          FROM people.student s
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN LATERAL people.student_reach(s.id) r
         WHERE CASE WHEN f ->> 'status' IS NOT NULL THEN s.status = f ->> 'status' ELSE people.biodata_applicable(s.status) END
           AND (v_session IS NULL OR s.entry_session = v_session
                OR EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = v_session)
                OR EXISTS (SELECT 1 FROM finance.payment_reference pr WHERE pr.student_id = s.id AND pr.session = v_session))
           AND (f ->> 'faculty' IS NULL OR p.faculty_code = f ->> 'faculty')
           AND (f ->> 'department' IS NULL OR p.dept_code = f ->> 'department')
           AND (f ->> 'programme' IS NULL OR s.programme_code = f ->> 'programme')
           AND (f ->> 'level' IS NULL OR s.current_level = (f ->> 'level')::int)
           AND (f ->> 'entry_mode' IS NULL OR s.entry_mode = f ->> 'entry_mode')
           AND (f ->> 'sex' IS NULL OR s.sex = f ->> 'sex')
           AND (NOT v_migrated OR (s.matric_no IS NOT NULL AND s.matriculation_run IS NULL))
           AND (NOT v_never OR NOT EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id AND a.last_signed_in_at IS NOT NULL))
           AND (NOT v_first OR EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id AND a.must_change AND a.temp_expires_at IS NULL))
           AND (p_after IS NULL OR s.id > p_after)
         ORDER BY s.id LIMIT greatest(1, p_limit);
    ELSIF p_kind = 'person' AND (v_staff OR v_lecturers) THEN
        RETURN QUERY
        SELECT p.id, p.email, p.phone
          FROM iam.person p
         WHERE p.ended_on IS NULL
           AND ((v_lecturers AND platform.office_active(p.id, 'lecturer'))
                OR (v_staff AND EXISTS (SELECT 1 FROM iam.office_assignment oa WHERE oa.person_id = p.id
                                          AND oa.office_code NOT IN ('lecturer', 'student', 'applicant', 'extexaminer')
                                          AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date))))
           AND (f ->> 'office' IS NULL OR platform.office_active(p.id, f ->> 'office'))
           AND (f ->> 'faculty' IS NULL OR EXISTS (SELECT 1 FROM iam.office_assignment oa WHERE oa.person_id = p.id AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)
                                                      AND ((oa.scope_kind = 'faculty' AND oa.scope_id = f ->> 'faculty')
                                                           OR (oa.scope_kind = 'department' AND oa.scope_id IN (SELECT d.code FROM ref.department d WHERE d.faculty_code = f ->> 'faculty')))))
           AND (f ->> 'department' IS NULL OR EXISTS (SELECT 1 FROM iam.office_assignment oa WHERE oa.person_id = p.id AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)
                                                         AND oa.scope_kind = 'department' AND oa.scope_id = f ->> 'department'))
           AND (NOT v_never OR NOT EXISTS (SELECT 1 FROM iam.credential cr WHERE cr.person_id = p.id AND cr.last_sign_in_at IS NOT NULL))
           AND (NOT v_first OR EXISTS (SELECT 1 FROM iam.credential cr WHERE cr.person_id = p.id AND cr.must_change))
           AND (p_after IS NULL OR p.id > p_after)
         ORDER BY p.id LIMIT greatest(1, p_limit);
    ELSIF p_kind = 'application' AND v_applicants THEN
        RETURN QUERY
        SELECT a.id, acc.email, acc.phone
          FROM admissions.application a JOIN admissions.applicant_account acc ON acc.id = a.account_id
         WHERE a.session = coalesce(v_session, policy.intake_session())
           AND (NOT v_never OR acc.last_signed_in_at IS NULL)
           AND (NOT v_first OR acc.password_hash = 'SET_ON_FIRST_LOGIN')
           AND (p_after IS NULL OR a.id > p_after)
         ORDER BY a.id LIMIT greatest(1, p_limit);
    END IF;
END $$;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('FIRST_PASSWORD_REMINDER', 'Choose your own password',
 'Sent by a campaign to the people whose portal account still opens with their own number as the password',
 'Choose your own password on the [UNIVERSITY_SHORT] portal',
 E'Dear [FIRST_NAME],\n\nYour account on the University''s portal still opens with your own number as the password, so anyone who knows the number could open it. Please sign in at [PORTAL_URL] with your number as the password and choose one of your own; the portal asks you to at once, and it takes a minute.\n\nIf you cannot sign in, choose "Forgot password?" on the sign-in page, or ask ICT Support.\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: your portal account still opens with your own number. Sign in at [PORTAL_URL] and choose your own password.',
 'Choose your own password',
 'Your account still opens with your own number as the password. Choose one of your own under My account.',
 ARRAY['FIRST_NAME','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL');

-- ── 3 · the manual ───────────────────────────────────────────────────────────────────────────────────────────────────────────
SELECT manual.seed('notify-provider-health', 'Know when a message provider stops sending', 'SETTINGS', ARRAY['ict', 'admin']::text[], 't/notify', NULL,
    'The portal watches its mail and SMS providers: when most of what it sends fails, when messages wait and none is tried, or when the SMS balance runs low, the Directorate of ICT is told once, on the channel that still works.',
    ARRAY['Open {menu:t/notify} and find Provider health.',
          'Read each channel''s state: OK, Idle, Off (delivery switched off), Failing, Stuck or Low balance, with what was tried and failed in the last two hours, what waits, and the last error.',
          'For the SMS account, read the balance eBulkSMS reported and when.',
          'Click `Check now` to read the balance and the state at once.',
          'Set `Warn below` (SMS units; 0 switches the warning off) and tick or untick `Watch the providers`, then click `Save`.',
          'On a problem, check the provider''s account (credit, password, API key) on the Mail server or SMS gateway screen; the episode ends by itself when messages go out again.'],
    'Each channel shows its state, and a problem has been told to the Directorate of ICT once.', '{}', 130);

SELECT manual.seed('first-passwords-read', 'See which accounts still open with the person''s own number', 'STUDENTS', ARRAY['ict', 'admin', 'super', 'registrar', 'academic', 'dean', 'hod']::text[], 't/compliance', NULL,
    'An account nobody has claimed opens with the person''s own number as the password, to whoever knows it. The count and the list show where the exposure lies and shrink as people choose their own.',
    ARRAY['Open {menu:t/compliance} and find First passwords.',
          'Read the counts: student accounts still on their first password, of those never signed in, and (for the University''s offices) staff and migrated applicants.',
          'Read the faculties, or the departments within a faculty, with the most accounts still open; click one to narrow the list.',
          'Filter the list by programme, level or never signed in, or search by name or number; export it for the department.',
          'To remind them, write a campaign on Campaigns & announcements with the template Choose your own password and the filter Still on their first password.'],
    'The counts and the list show the accounts still on their first password, within the office''s own scope.', '{}', 140);

SELECT manual.bump_edition('00000000-0000-0000-0000-000000000000', 'ict', 'V442: provider health and the accounts still on their first password', false);

COMMIT;
