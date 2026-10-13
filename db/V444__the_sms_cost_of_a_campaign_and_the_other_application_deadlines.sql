-- ═══════════════════════════════════════
-- V444 — the SMS cost of a campaign set against the balance, and the JUPEB, postgraduate and CCE application deadlines
--
-- 1 · A campaign to fifty thousand students by SMS can use more credit than the account holds and stop halfway. An SMS is
--     charged by the page: 160 characters of the GSM alphabet make one, 153 a page once a message runs longer; a message
--     with any character outside it (an accented letter the alphabet lacks, a curly quote, an emoji) is sent as Unicode,
--     70 characters one, 67 a page (platform.sms_units). The campaign's own SMS is rendered for its first recipient and
--     allowed fifteen characters more for longer names; its pages times the recipients with a usable phone is what the
--     campaign needs (platform.campaign_sms_cost), set against the balance the provider watch last read (V442). The preview
--     shows it; the send is refused while the balance is known and does not cover it (CAMPAIGN_SMS_CREDIT), unless the office
--     accepts the shortfall in so many words.
--
-- 2 · V440 reminded the Post-UTME applicants before their windows close. The other application routes keep their applicants
--     in their own modules: JUPEB (jupeb.application: a draft, or one returned for correction, is not yet done), the
--     School of Postgraduate Studies (admissions.pg_application: a draft is not yet done) and the Centre for Continuing
--     Education (admissions.application of a CCE candidate: not yet submitted). The same daily pass now queues their
--     windows; each applicant is reminded through WINDOW_CLOSING's variant for the route, on the address their own module
--     holds, once per deadline and day. The Post-UTME windows no longer reach a CCE candidate.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V444: the SMS cost of a campaign, and the other application deadlines', true);

-- ── 1 · the SMS cost of a campaign ───────────────────────────────────────────────────────────────────────────────────────────
-- the pages an SMS takes: GSM-7 (an extension character counts twice) or Unicode
CREATE FUNCTION platform.sms_units(p_text text)
RETURNS int LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    gsm text := '@£$¥èéùìòÇ' || chr(10) || 'Øø' || chr(13) || 'ÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&''()*+,-./0123456789:;<=>?¡'
                || 'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
    ext text := '^{}\[~]|€' || chr(12);
    t text := coalesce(p_text, '');
    n int;
BEGIN
    IF t = '' THEN RETURN 0; END IF;
    IF translate(t, gsm || ext, '') = '' THEN
        n := char_length(t) + (char_length(t) - char_length(translate(t, ext, '')));
        RETURN CASE WHEN n <= 160 THEN 1 ELSE ceil(n / 153.0)::int END;
    END IF;
    n := char_length(t);
    RETURN CASE WHEN n <= 70 THEN 1 ELSE ceil(n / 67.0)::int END;
END $$;
COMMENT ON FUNCTION platform.sms_units(text) IS 'V444: the pages an SMS is charged as — GSM-7 (160 one, 153 a page; an extension character counts twice) or Unicode (70 one, 67 a page)';

-- what the campaign's SMS will cost: its own text rendered for its first recipient, allowed fifteen characters for longer names
CREATE FUNCTION platform.campaign_sms_cost(p_campaign uuid, p_recipients int)
RETURNS TABLE (sms_on boolean, sample text, chars int, units_each int, recipients int, units_total int, balance numeric, balance_at timestamptz, covers boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE c platform.notice_campaign; t platform.notice_template; v_vars jsonb; v_id uuid; v_text text; v_units int; h platform.provider_health;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign;
    IF c.id IS NULL THEN RETURN; END IF;
    t := platform.template_for(c.template_key, NULL);
    SELECT * INTO h FROM platform.provider_health x WHERE x.channel = 'SMS';
    IF t.key IS NULL OR t.sms_body IS NULL OR NOT ('SMS' = ANY (c.channels)) THEN
        RETURN QUERY SELECT false, NULL::text, 0, 0, 0, 0, h.balance, h.balance_at, true;
        RETURN;
    END IF;
    v_vars := coalesce(c.vars, '{}'::jsonb);
    SELECT r.id INTO v_id FROM platform.campaign_recipients(p_campaign, 'student', NULL, 1) r;
    IF v_id IS NOT NULL THEN
        v_vars := platform.student_vars(v_id) || v_vars;
    ELSE
        SELECT r.id INTO v_id FROM platform.campaign_recipients(p_campaign, 'person', NULL, 1) r;
        IF v_id IS NOT NULL THEN
            v_vars := platform.person_vars(v_id) || v_vars;
        ELSE
            SELECT r.id INTO v_id FROM platform.campaign_recipients(p_campaign, 'application', NULL, 1) r;
            IF v_id IS NOT NULL THEN v_vars := platform.applicant_vars(v_id) || v_vars; END IF;
        END IF;
    END IF;
    v_text := (SELECT r.body FROM platform.render(c.template_key, NULL, 'SMS', v_vars) r);
    v_units := platform.sms_units(coalesce(v_text, '') || repeat(' ', 15));
    RETURN QUERY SELECT true, v_text, char_length(coalesce(v_text, '')), v_units, greatest(0, coalesce(p_recipients, 0)),
                        v_units * greatest(0, coalesce(p_recipients, 0)), h.balance, h.balance_at,
                        CASE WHEN h.balance IS NULL THEN NULL ELSE v_units * greatest(0, coalesce(p_recipients, 0)) <= h.balance END;
END $$;
COMMENT ON FUNCTION platform.campaign_sms_cost(uuid, int) IS
  'V444: the pages each SMS of a campaign takes (rendered for its first recipient, fifteen characters allowed for longer names), times the recipients with a usable phone, against the SMS balance last read; covers is NULL while no balance has been read.';

-- campaign_send (V426) restated: refused on a known shortfall of SMS credit, unless the office accepts it
DROP FUNCTION platform.campaign_send(uuid, uuid, text);
CREATE FUNCTION platform.campaign_send(p_campaign uuid, p_actor uuid, p_office text, p_accept_shortfall boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c platform.notice_campaign; v_total int; v_phones int; v_job uuid; k record;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'CAMPAIGN_NONE: no such campaign' USING ERRCODE = '23514'; END IF;
    IF c.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'CAMPAIGN_NOT_DRAFT: this campaign is already %', lower(c.state) USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(sum(total), 0), coalesce(sum(phone_ok), 0) INTO v_total, v_phones FROM platform.campaign_preview(p_campaign);
    IF v_total = 0 THEN
        RAISE EXCEPTION 'CAMPAIGN_EMPTY: nobody matches the audience; widen the filters' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO k FROM platform.campaign_sms_cost(p_campaign, v_phones);
    IF k.sms_on AND k.covers IS FALSE AND NOT coalesce(p_accept_shortfall, false) THEN
        RAISE EXCEPTION 'CAMPAIGN_SMS_CREDIT: the SMS of this campaign needs about % units (% messages of % page%) and the account held % when last read; top it up, or send accepting that the SMS stop when the credit runs out',
              k.units_total, k.recipients, k.units_each, CASE WHEN k.units_each = 1 THEN '' ELSE 's' END, trim_scale(k.balance) USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.notice_job (kind, payload, created_by, created_office)
    VALUES ('CAMPAIGN', jsonb_build_object('campaign_id', p_campaign, 'cursor_kind', 'student'), p_actor, p_office)
    RETURNING id INTO v_job;
    UPDATE platform.notice_campaign
       SET state = 'SENDING', sent_by = p_actor, sent_office = p_office, sent_at = now(), job_id = v_job, recipients = v_total, updated_at = now()
     WHERE id = p_campaign;
    RETURN v_job;
END $$;

-- ── 2 · the JUPEB, postgraduate and CCE application deadlines ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION platform.applicant_window_type(p_type text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT',
                      'JUPEB_APPLICATION', 'POSTGRADUATE_APPLICATION', 'CCE_APPLICATION')
$$;

-- the applicants a window's reminder is for, in id order from a cursor: each route's own applications of the session
CREATE OR REPLACE FUNCTION platform.applicant_window_audience(p_type text, p_session text, p_after uuid, p_limit int)
RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
    SELECT x.id FROM (
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type IN ('POST_UTME_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_CBT')
           AND a.session = p_session AND coalesce(c.entry_mode, '') <> 'CCE'
        UNION ALL
        SELECT a.id
          FROM admissions.application a
          JOIN admissions.applicant_account acc ON acc.id = a.account_id
          JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE p_type = 'CCE_APPLICATION' AND a.session = p_session AND c.entry_mode = 'CCE'
        UNION ALL
        SELECT j.id FROM jupeb.application j
         WHERE p_type = 'JUPEB_APPLICATION' AND j.session = p_session AND j.withdrawn_at IS NULL
        UNION ALL
        SELECT g.id FROM admissions.pg_application g
         WHERE p_type = 'POSTGRADUATE_APPLICATION' AND g.session = p_session) x
     WHERE p_after IS NULL OR x.id > p_after
     ORDER BY x.id
     LIMIT greatest(1, p_limit)
$$;

CREATE OR REPLACE FUNCTION policy.applicant_window_done(p_type text, p_session text, p_application uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_type IN ('POST_UTME_REGISTRATION', 'CCE_APPLICATION') THEN
            coalesce((SELECT a.submitted_at IS NOT NULL FROM admissions.application a WHERE a.id = p_application), true)
        WHEN p_type = 'ADMISSION_STATUS_CHECKING' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM admissions.status_check c WHERE c.application_id = p_application)
        WHEN p_type = 'POST_UTME_CBT' THEN
            coalesce((SELECT a.submitted_at IS NULL FROM admissions.application a WHERE a.id = p_application), true)
            OR EXISTS (SELECT 1 FROM assessment.cbt_attempt t WHERE t.application_id = p_application)
        WHEN p_type = 'JUPEB_APPLICATION' THEN
            coalesce((SELECT j.state NOT IN ('DRAFT', 'RETURNED') OR j.withdrawn_at IS NOT NULL FROM jupeb.application j WHERE j.id = p_application), true)
        WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN
            coalesce((SELECT g.state <> 'DRAFT' FROM admissions.pg_application g WHERE g.id = p_application), true)
        ELSE true END
$$;

-- one applicant of any route told, on the address their own module holds
CREATE FUNCTION platform.tell_route_applicant(p_type text, p_id uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    IF p_type = 'JUPEB_APPLICATION' THEN
        SELECT j.first_name, j.surname, j.middle_name, j.application_no, j.session, j.email, j.phone INTO r FROM jupeb.application j WHERE j.id = p_id;
        IF NOT FOUND THEN RETURN 0; END IF;
        RETURN platform.notify(p_key, p_variant,
            jsonb_strip_nulls(jsonb_build_object('FIRST_NAME', r.first_name, 'LAST_NAME', r.surname,
                'FULL_NAME', r.surname || ', ' || r.first_name || coalesce(' ' || r.middle_name, ''),
                'APPLICATION_NUMBER', r.application_no, 'SESSION', r.session)) || coalesce(p_vars, '{}'::jsonb),
            'jupeb_application', p_id, r.email, r.phone, p_event_key);
    ELSIF p_type = 'POSTGRADUATE_APPLICATION' THEN
        SELECT pa.surname, pa.other_names, pa.email, pa.phone, g.application_no, g.session INTO r
          FROM admissions.pg_application g JOIN admissions.pg_applicant pa ON pa.id = g.applicant_id WHERE g.id = p_id;
        IF NOT FOUND THEN RETURN 0; END IF;
        RETURN platform.notify(p_key, p_variant,
            jsonb_strip_nulls(jsonb_build_object('FIRST_NAME', coalesce(nullif(split_part(r.other_names, ' ', 1), ''), r.surname), 'LAST_NAME', r.surname,
                'FULL_NAME', r.surname || ', ' || r.other_names, 'APPLICATION_NUMBER', r.application_no, 'SESSION', r.session)) || coalesce(p_vars, '{}'::jsonb),
            'pg_application', p_id, r.email, r.phone, p_event_key);
    END IF;
    RETURN platform.tell_applicant(p_id, p_key, p_variant, p_vars, p_event_key);
END $$;

-- the job runner (V440) restated: an applicant window's CLOSING job tells each route's applicant through tell_route_applicant
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
                        v_queued := v_queued + platform.tell_route_applicant(v_type, s, v_key, v_type, v_vars, v_event);
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
  'V444 (V440 restated): drains the oldest open notification job by one batch — a window''s students, or for an applicant window''s CLOSING job the applicants of its route not yet done, told on the address their own module holds; or a campaign''s students, staff and applicants in turn.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('WINDOW_CLOSING:JUPEB_APPLICATION', 'JUPEB application closing',
 'The reminder before the JUPEB application window closes, to the applicants of the session whose application is a draft or was returned for correction',
 'JUPEB applications for [SESSION] close [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows your application ([APPLICATION_NUMBER]) has not been submitted, or was returned to you for correction. [LATE_NOTE]\n\nComplete and submit it on the JUPEB portal before then: [PORTAL_URL]\n\nJUPEB Office, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: JUPEB applications for [SESSION] close [DAYS_WORD] ([DEADLINE]) and yours is not yet submitted. Submit it before then.',
 'JUPEB application closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; your application has not been submitted. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSING:POSTGRADUATE_APPLICATION', 'Postgraduate application closing',
 'The reminder before the postgraduate application window closes, to the applicants of the session whose application is still a draft',
 'Postgraduate applications for [SESSION] close [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows your application ([APPLICATION_NUMBER]) is still a draft. [LATE_NOTE]\n\nComplete and submit it on the portal before then: [PORTAL_URL]\n\nSchool of Postgraduate Studies, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: postgraduate applications for [SESSION] close [DAYS_WORD] ([DEADLINE]) and yours is still a draft. Submit it before then.',
 'Postgraduate application closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; your application is still a draft. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH'),
('WINDOW_CLOSING:CCE_APPLICATION', 'CCE application closing',
 'The reminder before the CCE application window closes, to the applicants of the session who have not submitted their application',
 'CCE applications for [SESSION] close [DAYS_WORD]',
 E'Dear [FIRST_NAME],\n\n[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]. Our record shows your application ([APPLICATION_NUMBER]) has not been submitted. [LATE_NOTE]\n\nComplete and submit it on the portal before then: [PORTAL_URL]\n\nCentre for Continuing Education, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: CCE applications for [SESSION] close [DAYS_WORD] ([DEADLINE]) and yours is not yet submitted. Submit it before then.',
 'CCE application closes [DAYS_WORD]',
 '[WINDOW] for [SESSION] closes [DAYS_WORD], on [DEADLINE]; your application has not been submitted. [LATE_NOTE]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','JAMB_NUMBER','WINDOW','SESSION','DAYS_WORD','DEADLINE','LATE_NOTE','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'HIGH');

COMMIT;
