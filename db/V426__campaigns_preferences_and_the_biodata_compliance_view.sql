-- ═══════════════════════════════════════
-- V426 — campaigns, notification preferences, and the biodata compliance view
--
--   Phase 2 of the central notification engine (V425):
--
--   1. platform.notice_preference — a student's or staff member's own switch for e-mail and SMS on OPTIONAL messages
--      (an announcement); a mandatory template (a window, a payment, a result, the biodata reminder) is never switched off.
--      platform.notify reads it, and now takes the channels a sender restricts a message to.
--   2. platform.notice_campaign — a message to many, decided by an office: the NEW PORTAL MIGRATION welcome to everyone
--      brought over, an announcement to a faculty, a department, a level, a session, the staff or the applicants. The
--      recipients are never typed: they are read from the register (people.student), the staff record (iam.person with
--      an office) and the applications (admissions.application) by the filters the office sets. A preview counts them
--      (valid, bad and missing addresses, already reached); a test goes to one address; the send is a notification job the
--      scheduler drains in batches (V425), once per person and channel (the campaign is the event key); a report counts
--      what went by channel. ICT, the administrators, the Registry, Student Affairs and the Academic Office address anyone;
--      a Dean or Head addresses their own faculty's or department's students only.
--   3. people.biodata_compliance_summary / biodata_status_list / contact_quality / duplicate_contacts — the offices' view
--      of where every student's biodata stands (on V425's status): counts, the students behind each count, filtered and
--      searched, and the data-quality picture (missing, invalid and shared addresses).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V426: campaigns, notification preferences, the biodata compliance view', true);

-- ── 1 · preferences ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.notice_preference (
    about_kind text NOT NULL CHECK (about_kind IN ('student', 'person')),
    about_id   uuid NOT NULL,
    channel    text NOT NULL CHECK (channel IN ('EMAIL', 'SMS')),
    enabled    boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (about_kind, about_id, channel)
);
SELECT audit.attach('platform.notice_preference');
COMMENT ON TABLE platform.notice_preference IS
  'V426: a person''s own switch for e-mail and SMS on optional messages; a mandatory template is sent regardless. Absent row = on.';

CREATE OR REPLACE FUNCTION platform.channel_allowed(p_kind text, p_id uuid, p_channel text, p_mandatory boolean)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce(p_mandatory, true) OR p_id IS NULL
        OR NOT EXISTS (SELECT 1 FROM platform.notice_preference x WHERE x.about_kind = p_kind AND x.about_id = p_id AND x.channel = p_channel AND NOT x.enabled)
$$;

CREATE OR REPLACE FUNCTION platform.set_preference(p_kind text, p_id uuid, p_channel text, p_enabled boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_kind NOT IN ('student', 'person') OR p_channel NOT IN ('EMAIL', 'SMS') THEN
        RAISE EXCEPTION 'NOTICE_PREFERENCE: a preference is for e-mail or SMS, for a student or a staff member' USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.notice_preference (about_kind, about_id, channel, enabled) VALUES (p_kind, p_id, p_channel, coalesce(p_enabled, true))
    ON CONFLICT (about_kind, about_id, channel) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
END $$;

CREATE OR REPLACE FUNCTION platform.preferences(p_kind text, p_id uuid)
RETURNS TABLE(channel text, enabled boolean) LANGUAGE sql STABLE AS $$
    SELECT c, coalesce((SELECT x.enabled FROM platform.notice_preference x WHERE x.about_kind = p_kind AND x.about_id = p_id AND x.channel = c), true)
      FROM unnest(ARRAY['EMAIL', 'SMS']) AS c
$$;

-- ── 2 · notify: the channels a sender restricts to, and the person's preference on an optional message ──────────────
DROP FUNCTION platform.notify(text, text, jsonb, text, uuid, text, text, text);
CREATE FUNCTION platform.notify(p_key text, p_variant text, p_vars jsonb, p_about_kind text, p_about_id uuid,
                                p_email text, p_phone text, p_event_key text, p_channels text[] DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE t platform.notice_template; r record; v uuid; n int := 0;
BEGIN
    t := platform.template_for(p_key, p_variant);
    IF t.key IS NULL THEN RETURN 0; END IF;
    -- counted: a message queued or delivered — not one recorded FAILED for an address that is not one, nor one the event key refused
    IF t.email_body IS NOT NULL AND nullif(btrim(coalesce(p_email, '')), '') IS NOT NULL
       AND (p_channels IS NULL OR 'EMAIL' = ANY (p_channels)) AND platform.channel_allowed(p_about_kind, p_about_id, 'EMAIL', t.mandatory) THEN
        SELECT * INTO r FROM platform.render(p_key, p_variant, 'EMAIL', p_vars);
        v := platform.queue_notice('EMAIL', p_email, r.subject, r.body, p_about_kind, p_about_id, p_event_key, t.key, t.priority);
        IF v IS NOT NULL AND EXISTS (SELECT 1 FROM platform.notice x WHERE x.id = v AND x.state <> 'FAILED') THEN n := n + 1; END IF;
    END IF;
    IF t.sms_body IS NOT NULL AND nullif(btrim(coalesce(p_phone, '')), '') IS NOT NULL
       AND (p_channels IS NULL OR 'SMS' = ANY (p_channels)) AND platform.channel_allowed(p_about_kind, p_about_id, 'SMS', t.mandatory) THEN
        SELECT * INTO r FROM platform.render(p_key, p_variant, 'SMS', p_vars);
        v := platform.queue_notice('SMS', p_phone, r.subject, r.body, p_about_kind, p_about_id, p_event_key, t.key, t.priority);
        IF v IS NOT NULL AND EXISTS (SELECT 1 FROM platform.notice x WHERE x.id = v AND x.state <> 'FAILED') THEN n := n + 1; END IF;
    END IF;
    IF t.portal_body IS NOT NULL AND p_about_id IS NOT NULL AND (p_channels IS NULL OR 'PORTAL' = ANY (p_channels)) THEN
        SELECT * INTO r FROM platform.render(p_key, p_variant, 'PORTAL', p_vars);
        v := platform.queue_notice('PORTAL', NULL, r.subject, r.body, p_about_kind, p_about_id, p_event_key, t.key, t.priority);
        IF v IS NOT NULL THEN n := n + 1; END IF;
    END IF;
    RETURN n;
END $$;
COMMENT ON FUNCTION platform.notify(text, text, jsonb, text, uuid, text, text, text, text[]) IS
  'V426: a template rendered and queued for one person on the channels it has (or those given), honouring the person''s preference on an optional template; once per event key; returns how many were queued or delivered.';

DROP FUNCTION platform.tell_student(uuid, text, text, jsonb, text);
CREATE FUNCTION platform.tell_student(p_student uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text, p_channels text[] DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM people.student_reach(p_student);
    IF NOT FOUND THEN RETURN 0; END IF;
    RETURN platform.notify(p_key, p_variant, platform.student_vars(p_student) || coalesce(p_vars, '{}'::jsonb), 'student', p_student, r.email, r.phone, p_event_key, p_channels);
END $$;

DROP FUNCTION platform.tell_person(uuid, text, text, jsonb, text);
CREATE FUNCTION platform.tell_person(p_person uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text, p_channels text[] DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE p record;
BEGIN
    SELECT email, phone INTO p FROM iam.person WHERE id = p_person AND ended_on IS NULL;
    IF NOT FOUND THEN RETURN 0; END IF;
    RETURN platform.notify(p_key, p_variant, platform.person_vars(p_person) || coalesce(p_vars, '{}'::jsonb), 'person', p_person, p.email, p.phone, p_event_key, p_channels);
END $$;

-- an applicant: the candidate's names and numbers, the account's address
CREATE OR REPLACE FUNCTION platform.applicant_vars(p_application uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'FIRST_NAME', coalesce(nullif(split_part(c.other_names, ' ', 1), ''), c.surname),
        'LAST_NAME', c.surname,
        'FULL_NAME', c.surname || ', ' || c.other_names,
        'JAMB_NUMBER', c.jamb_reg_no,
        'APPLICATION_NUMBER', a.application_no,
        'LOGIN_ID', coalesce(c.jamb_reg_no, a.application_no),
        'PROGRAMME', c.programme,
        'SESSION', a.session))
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE a.id = p_application
$$;

CREATE OR REPLACE FUNCTION platform.tell_applicant(p_application uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text, p_channels text[] DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE x record;
BEGIN
    SELECT acc.email, acc.phone INTO x FROM admissions.application a JOIN admissions.applicant_account acc ON acc.id = a.account_id WHERE a.id = p_application;
    IF NOT FOUND THEN RETURN 0; END IF;
    RETURN platform.notify(p_key, p_variant, platform.applicant_vars(p_application) || coalesce(p_vars, '{}'::jsonb), 'application', p_application, x.email, x.phone, p_event_key, p_channels);
END $$;

-- ── 3 · campaigns ─────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.notice_campaign (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name           text NOT NULL,
    template_key   text NOT NULL REFERENCES platform.notice_template(key),
    audience       jsonb NOT NULL DEFAULT '{}',
    channels       text[] NOT NULL DEFAULT ARRAY['EMAIL', 'SMS', 'PORTAL'],
    vars           jsonb NOT NULL DEFAULT '{}',
    state          text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'SENDING', 'SENT', 'CANCELLED')),
    created_by     uuid NULL,
    created_office text NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    sent_by        uuid NULL,
    sent_office    text NULL,
    sent_at        timestamptz NULL,
    finished_at    timestamptz NULL,
    cancelled_at   timestamptz NULL,
    cancel_reason  text NULL,
    job_id         uuid NULL REFERENCES platform.notice_job(id),
    recipients     int NULL,
    CONSTRAINT ck_campaign_channels CHECK (cardinality(channels) > 0 AND channels <@ ARRAY['EMAIL', 'SMS', 'PORTAL'])
);
CREATE INDEX ix_campaign_created ON platform.notice_campaign (created_at DESC);
SELECT audit.attach('platform.notice_campaign');
COMMENT ON TABLE platform.notice_campaign IS
  'V426: a message to many, decided by an office: the template, who (students / staff / lecturers / applicants, filtered on the record), the channels, the office''s own words for an announcement; sent as a notification job, once per person and channel.';
COMMENT ON COLUMN platform.notice_campaign.audience IS
  'V426: {"students":bool,"staff":bool,"lecturers":bool,"applicants":bool,"filters":{"session","faculty","department","programme","level","status","entry_mode","sex","office","migrated":bool,"never_signed_in":bool}}';

CREATE OR REPLACE FUNCTION platform.office_active(p_person uuid, p_office text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.office_assignment oa
                    WHERE oa.person_id = p_person AND oa.office_code = p_office
                      AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date))
$$;

-- the recipients of one kind, after a cursor, up to a limit: read from the record by the campaign's filters, never typed
CREATE OR REPLACE FUNCTION platform.campaign_recipients(p_campaign uuid, p_kind text, p_after uuid, p_limit int)
RETURNS TABLE(id uuid, email text, phone text) LANGUAGE plpgsql STABLE AS $$
DECLARE c platform.notice_campaign; f jsonb; v_students boolean; v_staff boolean; v_lecturers boolean; v_applicants boolean;
        v_migrated boolean; v_never boolean; v_session text;
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
           AND (p_after IS NULL OR p.id > p_after)
         ORDER BY p.id LIMIT greatest(1, p_limit);
    ELSIF p_kind = 'application' AND v_applicants THEN
        RETURN QUERY
        SELECT a.id, acc.email, acc.phone
          FROM admissions.application a JOIN admissions.applicant_account acc ON acc.id = a.account_id
         WHERE a.session = coalesce(v_session, policy.intake_session())
           AND (NOT v_never OR acc.last_signed_in_at IS NULL)
           AND (p_after IS NULL OR a.id > p_after)
         ORDER BY a.id LIMIT greatest(1, p_limit);
    END IF;
END $$;

-- what a campaign would reach: by kind, the addresses that are good, bad or missing, and who was already reached
CREATE OR REPLACE FUNCTION platform.campaign_preview(p_campaign uuid)
RETURNS TABLE(kind text, total int, email_ok int, email_bad int, email_missing int, phone_ok int, phone_bad int, phone_missing int, already int)
LANGUAGE plpgsql STABLE AS $$
DECLARE k text;
BEGIN
    FOREACH k IN ARRAY ARRAY['student', 'person', 'application'] LOOP
        RETURN QUERY
        SELECT k, count(*)::int,
               count(*) FILTER (WHERE platform.email_valid(r.email))::int,
               count(*) FILTER (WHERE nullif(btrim(coalesce(r.email, '')), '') IS NOT NULL AND NOT platform.email_valid(r.email))::int,
               count(*) FILTER (WHERE nullif(btrim(coalesce(r.email, '')), '') IS NULL)::int,
               count(*) FILTER (WHERE platform.phone_valid(r.phone))::int,
               count(*) FILTER (WHERE nullif(btrim(coalesce(r.phone, '')), '') IS NOT NULL AND NOT platform.phone_valid(r.phone))::int,
               count(*) FILTER (WHERE nullif(btrim(coalesce(r.phone, '')), '') IS NULL)::int,
               (SELECT count(DISTINCT n.about_id)::int FROM platform.notice n WHERE n.event_key = 'campaign:' || p_campaign AND n.about_kind = k)
          FROM platform.campaign_recipients(p_campaign, k, NULL, 100000000) r;
    END LOOP;
END $$;

-- the offices that may write to many, and how far: a Dean or Head only their own students
CREATE OR REPLACE FUNCTION platform.campaign_save(p_id uuid, p_name text, p_template_key text, p_audience jsonb, p_channels text[], p_vars jsonb,
                                                  p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := coalesce(p_id, gen_random_uuid()); f jsonb := coalesce(p_audience -> 'filters', '{}'::jsonb); t platform.notice_template;
        v_wide boolean := p_office IN ('ict', 'admin', 'super', 'registrar', 'dregistrar', 'dsa', 'academic');
BEGIN
    IF p_office IS NULL OR (NOT v_wide AND p_office NOT IN ('dean', 'facultyofficer', 'hod')) THEN
        RAISE EXCEPTION 'CAMPAIGN_OFFICE: a message to many is sent by ICT, an administrator, the Registry, Student Affairs, the Academic Office, a Dean or a Head of Department' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'CAMPAIGN_NAME: a campaign has a name' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO t FROM platform.notice_template x WHERE x.key = p_template_key AND x.enabled;
    IF t.key IS NULL THEN
        RAISE EXCEPTION 'CAMPAIGN_TEMPLATE: no such template, or it is switched off' USING ERRCODE = '23514';
    END IF;
    IF p_channels IS NULL OR cardinality(p_channels) = 0 OR NOT (p_channels <@ ARRAY['EMAIL', 'SMS', 'PORTAL']) THEN
        RAISE EXCEPTION 'CAMPAIGN_CHANNELS: choose e-mail, SMS, the portal, or several' USING ERRCODE = '23514';
    END IF;
    IF NOT (coalesce((p_audience ->> 'students')::boolean, false) OR coalesce((p_audience ->> 'staff')::boolean, false)
            OR coalesce((p_audience ->> 'lecturers')::boolean, false) OR coalesce((p_audience ->> 'applicants')::boolean, false)) THEN
        RAISE EXCEPTION 'CAMPAIGN_AUDIENCE: choose who the message is for' USING ERRCODE = '23514';
    END IF;
    IF t.key = 'ANNOUNCEMENT' AND (nullif(btrim(coalesce(p_vars ->> 'TITLE', '')), '') IS NULL OR nullif(btrim(coalesce(p_vars ->> 'MESSAGE', '')), '') IS NULL) THEN
        RAISE EXCEPTION 'CAMPAIGN_WORDS: an announcement has a title and a message' USING ERRCODE = '23514';
    END IF;
    IF NOT v_wide THEN
        IF coalesce((p_audience ->> 'staff')::boolean, false) OR coalesce((p_audience ->> 'lecturers')::boolean, false) OR coalesce((p_audience ->> 'applicants')::boolean, false) THEN
            RAISE EXCEPTION 'CAMPAIGN_SCOPE: a Dean or Head writes to their own students; the staff and the applicants are the Registry''s' USING ERRCODE = '23514';
        END IF;
        IF p_office = 'hod' THEN
            IF f ->> 'department' IS NULL OR NOT EXISTS (SELECT 1 FROM iam.office_assignment oa WHERE oa.person_id = p_actor AND oa.office_code = 'hod' AND oa.scope_kind = 'department'
                                                            AND oa.scope_id = f ->> 'department' AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)) THEN
                RAISE EXCEPTION 'CAMPAIGN_SCOPE: a Head of Department writes to the students of their own department' USING ERRCODE = '23514';
            END IF;
        ELSE
            IF f ->> 'faculty' IS NULL OR NOT EXISTS (SELECT 1 FROM iam.office_assignment oa WHERE oa.person_id = p_actor AND oa.office_code = p_office AND oa.scope_kind = 'faculty'
                                                         AND oa.scope_id = f ->> 'faculty' AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)) THEN
                RAISE EXCEPTION 'CAMPAIGN_SCOPE: a Dean writes to the students of their own faculty' USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    IF p_id IS NOT NULL AND EXISTS (SELECT 1 FROM platform.notice_campaign x WHERE x.id = p_id AND x.state <> 'DRAFT') THEN
        RAISE EXCEPTION 'CAMPAIGN_NOT_DRAFT: a campaign already sent or cancelled is not edited; start another' USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.notice_campaign (id, name, template_key, audience, channels, vars, created_by, created_office)
    VALUES (v_id, btrim(p_name), t.key, coalesce(p_audience, '{}'::jsonb), p_channels, coalesce(p_vars, '{}'::jsonb), p_actor, p_office)
    ON CONFLICT (id) DO UPDATE
       SET name = EXCLUDED.name, template_key = EXCLUDED.template_key, audience = EXCLUDED.audience, channels = EXCLUDED.channels, vars = EXCLUDED.vars, updated_at = now();
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION platform.campaign_sample_vars()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT '{"FIRST_NAME":"Adaeze","LAST_NAME":"Okafor","FULL_NAME":"Okafor, Adaeze Chioma","MATRIC_NUMBER":"MOAUM/SC/23/1234","JAMB_NUMBER":"23456789AB","LOGIN_ID":"MOAUM/SC/23/1234","STAFF_NUMBER":"PF/1234","PROGRAMME":"B.Sc. Computer Science","DEPARTMENT":"Computer Science","FACULTY":"Science","LEVEL":"200","SESSION":"2026/2027"}'::jsonb
$$;

CREATE OR REPLACE FUNCTION platform.campaign_test(p_campaign uuid, p_email text, p_phone text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE c platform.notice_campaign;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign;
    IF c.id IS NULL THEN RAISE EXCEPTION 'CAMPAIGN_NONE: no such campaign' USING ERRCODE = '23514'; END IF;
    RETURN platform.notify(c.template_key, NULL, platform.campaign_sample_vars() || c.vars, 'test', NULL, p_email, p_phone, NULL, c.channels);
END $$;

CREATE OR REPLACE FUNCTION platform.campaign_send(p_campaign uuid, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c platform.notice_campaign; v_total int; v_job uuid;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'CAMPAIGN_NONE: no such campaign' USING ERRCODE = '23514'; END IF;
    IF c.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'CAMPAIGN_NOT_DRAFT: this campaign is already %', lower(c.state) USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(sum(total), 0) INTO v_total FROM platform.campaign_preview(p_campaign);
    IF v_total = 0 THEN
        RAISE EXCEPTION 'CAMPAIGN_EMPTY: nobody matches the audience; widen the filters' USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.notice_job (kind, payload, created_by, created_office)
    VALUES ('CAMPAIGN', jsonb_build_object('campaign_id', p_campaign, 'cursor_kind', 'student'), p_actor, p_office)
    RETURNING id INTO v_job;
    UPDATE platform.notice_campaign
       SET state = 'SENDING', sent_by = p_actor, sent_office = p_office, sent_at = now(), job_id = v_job, recipients = v_total, updated_at = now()
     WHERE id = p_campaign;
    RETURN v_job;
END $$;

CREATE OR REPLACE FUNCTION platform.campaign_cancel(p_campaign uuid, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE c platform.notice_campaign;
BEGIN
    SELECT * INTO c FROM platform.notice_campaign x WHERE x.id = p_campaign FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'CAMPAIGN_NONE: no such campaign' USING ERRCODE = '23514'; END IF;
    IF c.state NOT IN ('DRAFT', 'SENDING') THEN
        RAISE EXCEPTION 'CAMPAIGN_FINISHED: a campaign already % is not cancelled', lower(c.state) USING ERRCODE = '23514';
    END IF;
    UPDATE platform.notice_campaign SET state = 'CANCELLED', cancelled_at = now(), cancel_reason = nullif(btrim(coalesce(p_reason, '')), ''), updated_at = now() WHERE id = p_campaign;
    IF c.job_id IS NOT NULL THEN
        UPDATE platform.notice_job SET state = 'DONE', finished_at = coalesce(finished_at, now()), error = 'cancelled by ' || coalesce(p_office, 'an office') || CASE WHEN nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN '' ELSE ': ' || btrim(p_reason) END
         WHERE id = c.job_id AND state IN ('QUEUED', 'RUNNING');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION platform.campaign_report(p_campaign uuid)
RETURNS TABLE(channel text, total int, queued int, sent int, failed int, invalid int)
LANGUAGE sql STABLE AS $$
    SELECT n.channel, count(*)::int,
           count(*) FILTER (WHERE n.state = 'QUEUED')::int,
           count(*) FILTER (WHERE n.state = 'SENT')::int,
           count(*) FILTER (WHERE n.state = 'FAILED')::int,
           count(*) FILTER (WHERE n.state = 'FAILED' AND n.last_error IN ('INVALID_EMAIL', 'INVALID_PHONE'))::int
      FROM platform.notice n WHERE n.event_key = 'campaign:' || p_campaign
     GROUP BY n.channel ORDER BY n.channel
$$;

-- the job runner (V425) restated: a CAMPAIGN job walks the students, then the staff, then the applicants, the kind and the
-- cursor kept on the job; done when every kind is exhausted (the campaign is then SENT) or when the campaign was cancelled
CREATE OR REPLACE FUNCTION platform.run_notice_job(p_limit int DEFAULT NULL)
RETURNS TABLE(job_id uuid, kind text, reached int, queued int, done boolean)
LANGUAGE plpgsql AS $$
DECLARE j record; c platform.notice_campaign; v_limit int := coalesce(p_limit, (SELECT job_batch FROM platform.notice_setting WHERE id), 2000);
        v_key text; v_vars jsonb; v_event text; s uuid; r record; v_reached int := 0; v_queued int := 0; v_last uuid;
        v_kind text; v_after uuid; v_done boolean;
BEGIN
    SELECT * INTO j FROM platform.notice_job x WHERE x.state IN ('QUEUED', 'RUNNING') ORDER BY x.created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN; END IF;
    UPDATE platform.notice_job SET state = 'RUNNING', started_at = coalesce(started_at, now()), runs = runs + 1 WHERE id = j.id;
    BEGIN
        IF j.kind = 'WINDOW' THEN
            v_key := 'WINDOW_' || CASE j.payload ->> 'action' WHEN 'OPEN' THEN 'OPENED' WHEN 'REOPEN' THEN 'REOPENED' WHEN 'EXTEND' THEN 'EXTENDED' ELSE 'CLOSED' END;
            v_vars := platform.window_vars(j.payload);
            v_event := 'window:' || coalesce(j.payload ->> 'event_id', j.id::text) || ':' || (j.payload ->> 'action');
            FOR s IN SELECT * FROM policy.window_audience(j.payload ->> 'type', j.payload ->> 'session', j.cursor_id, v_limit) LOOP
                v_queued := v_queued + platform.tell_student(s, v_key, j.payload ->> 'type', v_vars, v_event);
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
  'V426 (V425 restated): drains the oldest open notification job by one batch — a window''s students, or a campaign''s students, staff and applicants in turn, the kind and cursor kept on the job; run by the API every half-minute; a job that raises is FAILED with the error kept.';

-- ── 4 · the compliance view ───────────────────────────────────────────────────────────────────────────────────────────
-- Every student's status, read for the offices: computing it for the whole register takes some ten seconds on live-shaped
-- data (54,000 students), so the scheduler keeps a reading (people.biodata_status_snapshot) every quarter of an hour and after
-- each reminder run, and the counts, lists and data-quality figures read that; the reading's time is shown. A student's own
-- status (people.biodata_status) is always computed live, and their confirmation refreshes their row at once.
CREATE TABLE people.biodata_status_snapshot (
    student_id       uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    status           text NOT NULL,
    required         int NOT NULL,
    completed        int NOT NULL,
    missing          text[] NOT NULL DEFAULT '{}',
    missing_labels   text[] NOT NULL DEFAULT '{}',
    last_updated     timestamptz NULL,
    confirmed_at     timestamptz NULL,
    migrated         boolean NOT NULL DEFAULT false,
    last_reminded_at timestamptz NULL,
    email            text NULL,
    phone            text NULL,
    email_ok         boolean NOT NULL DEFAULT false,
    phone_ok         boolean NOT NULL DEFAULT false,
    signed_in        boolean NOT NULL DEFAULT false,
    computed_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_bss_status ON people.biodata_status_snapshot (status);
SELECT audit.exempt('people.biodata_status_snapshot', 'a periodic reading of every student''s biodata status for the offices'' counts and lists; recomputed by the scheduler, never written by hand');
CREATE TABLE people.biodata_snapshot_run (
    id          boolean PRIMARY KEY DEFAULT true CHECK (id),
    computed_at timestamptz NULL,
    students    int NULL,
    took_ms     int NULL
);
INSERT INTO people.biodata_snapshot_run (id) VALUES (true);
SELECT audit.exempt('people.biodata_snapshot_run', 'when the biodata status reading was last taken, over how many students, and how long it took');

CREATE OR REPLACE FUNCTION people.refresh_biodata_snapshot(p_students uuid[] DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_t0 timestamptz := clock_timestamp(); n int;
BEGIN
    WITH base AS (
        SELECT s.id FROM people.student s
         WHERE people.biodata_applicable(s.status) AND (p_students IS NULL OR s.id = ANY (p_students))),
    st AS (SELECT * FROM people.biodata_statuses((SELECT coalesce(array_agg(id), '{}'::uuid[]) FROM base))),
    rows AS (
        SELECT x.student_id, x.status, x.required, x.completed, coalesce(x.missing, '{}') AS missing, coalesce(x.missing_labels, '{}') AS missing_labels,
               x.last_updated, x.confirmed_at, x.migrated, x.last_reminded_at, r.email, r.phone,
               platform.email_valid(r.email) AS email_ok, platform.phone_valid(r.phone) AS phone_ok,
               EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = x.student_id AND a.last_signed_in_at IS NOT NULL) AS signed_in
          FROM st x CROSS JOIN LATERAL people.student_reach(x.student_id) r),
    ins AS (
        INSERT INTO people.biodata_status_snapshot (student_id, status, required, completed, missing, missing_labels, last_updated, confirmed_at, migrated,
                                                    last_reminded_at, email, phone, email_ok, phone_ok, signed_in, computed_at)
        SELECT rows.student_id, rows.status, rows.required, rows.completed, rows.missing, rows.missing_labels, rows.last_updated, rows.confirmed_at, rows.migrated,
               rows.last_reminded_at, rows.email, rows.phone, rows.email_ok, rows.phone_ok, rows.signed_in, now()
          FROM rows
        ON CONFLICT (student_id) DO UPDATE
           SET status = EXCLUDED.status, required = EXCLUDED.required, completed = EXCLUDED.completed, missing = EXCLUDED.missing,
               missing_labels = EXCLUDED.missing_labels, last_updated = EXCLUDED.last_updated, confirmed_at = EXCLUDED.confirmed_at,
               migrated = EXCLUDED.migrated, last_reminded_at = EXCLUDED.last_reminded_at, email = EXCLUDED.email, phone = EXCLUDED.phone,
               email_ok = EXCLUDED.email_ok, phone_ok = EXCLUDED.phone_ok, signed_in = EXCLUDED.signed_in, computed_at = now()
        RETURNING 1)
    SELECT count(*) INTO n FROM ins;
    IF p_students IS NULL THEN
        DELETE FROM people.biodata_status_snapshot x WHERE NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = x.student_id AND people.biodata_applicable(s.status));
        UPDATE people.biodata_snapshot_run SET computed_at = now(), students = n, took_ms = (extract(epoch FROM clock_timestamp() - v_t0) * 1000)::int WHERE id;
    END IF;
    RETURN n;
END $$;
COMMENT ON FUNCTION people.refresh_biodata_snapshot(uuid[]) IS
  'V426: the reading of every applicable student''s biodata status (or of the students given) for the offices'' counts and lists; the scheduler takes it every quarter of an hour.';

-- the student's confirmation (V425) restated: their row of the reading refreshed at once
CREATE OR REPLACE FUNCTION people.confirm_biodata(p_student uuid, p_actor uuid)
RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE c record; v_at timestamptz;
BEGIN
    SELECT * INTO c FROM people.biodata_completion(ARRAY[p_student]);
    IF c.student_id IS NULL THEN
        RAISE EXCEPTION 'BIO_NO_STUDENT: no such student' USING ERRCODE = '23514';
    END IF;
    IF NOT c.complete THEN
        RAISE EXCEPTION 'BIODATA_INCOMPLETE: % required item(s) still missing: %', c.required - c.completed, array_to_string(c.missing_labels, ', ') USING ERRCODE = '23514';
    END IF;
    INSERT INTO people.biodata_review (student_id, confirmed_at, confirmed_by) VALUES (p_student, now(), p_actor)
    ON CONFLICT (student_id) DO UPDATE SET confirmed_at = now(), confirmed_by = EXCLUDED.confirmed_by
    RETURNING confirmed_at INTO v_at;
    PERFORM people.refresh_biodata_snapshot(ARRAY[p_student]);
    RETURN v_at;
END $$;

CREATE OR REPLACE FUNCTION people.biodata_compliance_summary(p_faculty text DEFAULT NULL, p_department text DEFAULT NULL)
RETURNS TABLE(total int, up_to_date int, incomplete int, review_required int, outdated int, migrated int, migrated_reviewed int,
              no_email int, no_phone int, invalid_email int, invalid_phone int, never_signed_in int, reminded_week int, computed_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT count(*)::int,
           count(*) FILTER (WHERE x.status = 'UP_TO_DATE')::int,
           count(*) FILTER (WHERE x.status = 'INCOMPLETE')::int,
           count(*) FILTER (WHERE x.status = 'REVIEW_REQUIRED')::int,
           count(*) FILTER (WHERE x.status = 'OUTDATED')::int,
           count(*) FILTER (WHERE x.migrated)::int,
           count(*) FILTER (WHERE x.migrated AND x.status = 'UP_TO_DATE')::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(x.email, '')), '') IS NULL)::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(x.phone, '')), '') IS NULL)::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(x.email, '')), '') IS NOT NULL AND NOT x.email_ok)::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(x.phone, '')), '') IS NOT NULL AND NOT x.phone_ok)::int,
           count(*) FILTER (WHERE NOT x.signed_in)::int,
           count(*) FILTER (WHERE x.last_reminded_at > now() - interval '7 days')::int,
           (SELECT r.computed_at FROM people.biodata_snapshot_run r WHERE r.id)
      FROM people.biodata_status_snapshot x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
     WHERE (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
$$;
COMMENT ON FUNCTION people.biodata_compliance_summary(text, text) IS
  'V426: how the students on the register stand (within a faculty or department when given), from the latest reading: the biodata statuses, those who came over, the addresses missing or not addresses, who never signed in, who was reminded this week.';

CREATE OR REPLACE FUNCTION people.biodata_status_list(p_status text, p_faculty text, p_department text, p_programme text, p_level int, p_session text,
                                                      p_entry_mode text, p_migrated boolean, p_q text, p_limit int, p_offset int)
RETURNS TABLE(student_id uuid, matric_no text, jamb_reg_no text, surname text, other_names text, faculty text, department text, programme text,
              level int, entry_session text, status text, email text, phone text, missing_labels text[], last_updated timestamptz,
              confirmed_at timestamptz, last_reminded_at timestamptz, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.matric_no, s.jamb_reg_no, s.surname, s.other_names, f.name, d.name, p.name, s.current_level, s.entry_session,
           x.status, x.email, x.phone, x.missing_labels, x.last_updated, x.confirmed_at, x.last_reminded_at, count(*) OVER ()
      FROM people.biodata_status_snapshot x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE (p_status IS NULL OR x.status = p_status)
       AND (p_migrated IS NULL OR x.migrated = p_migrated)
       AND (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
       AND (p_programme IS NULL OR s.programme_code = p_programme)
       AND (p_level IS NULL OR s.current_level = p_level)
       AND (p_session IS NULL OR s.entry_session = p_session)
       AND (p_entry_mode IS NULL OR s.entry_mode = p_entry_mode)
       AND (p_q IS NULL OR btrim(p_q) = '' OR s.surname ILIKE '%' || btrim(p_q) || '%' OR s.other_names ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(s.matric_no, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(s.jamb_reg_no, '') ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(x.email, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(x.phone, '') ILIKE '%' || btrim(p_q) || '%')
     ORDER BY s.surname, s.other_names
     LIMIT greatest(1, p_limit) OFFSET greatest(0, p_offset)
$$;
COMMENT ON FUNCTION people.biodata_status_list(text, text, text, text, int, text, text, boolean, text, int, int) IS
  'V426: the students behind a compliance count, from the latest reading, filtered by status, faculty, department, programme, level, entry session, entry mode, came-over, and searched by name, number, e-mail or phone; paged, with the total.';

CREATE OR REPLACE FUNCTION people.contact_quality(p_faculty text DEFAULT NULL, p_department text DEFAULT NULL)
RETURNS TABLE(shared_emails int, students_sharing_email int, shared_phones int, students_sharing_phone int,
              missing_email int, missing_phone int, invalid_email int, invalid_phone int, missing_passport int)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT x.* FROM people.biodata_status_snapshot x JOIN people.student s ON s.id = x.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
         WHERE (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_department IS NULL OR p.dept_code = p_department)),
    e AS (SELECT lower(btrim(email)) AS v, count(*) n FROM base WHERE nullif(btrim(coalesce(email, '')), '') IS NOT NULL GROUP BY 1 HAVING count(*) > 1),
    ph AS (SELECT regexp_replace(phone, '[^0-9]', '', 'g') AS v, count(*) n FROM base WHERE nullif(btrim(coalesce(phone, '')), '') IS NOT NULL GROUP BY 1 HAVING count(*) > 1)
    SELECT (SELECT count(*)::int FROM e), (SELECT coalesce(sum(n), 0)::int FROM e),
           (SELECT count(*)::int FROM ph), (SELECT coalesce(sum(n), 0)::int FROM ph),
           (SELECT count(*)::int FROM base WHERE nullif(btrim(coalesce(email, '')), '') IS NULL),
           (SELECT count(*)::int FROM base WHERE nullif(btrim(coalesce(phone, '')), '') IS NULL),
           (SELECT count(*)::int FROM base WHERE nullif(btrim(coalesce(email, '')), '') IS NOT NULL AND NOT email_ok),
           (SELECT count(*)::int FROM base WHERE nullif(btrim(coalesce(phone, '')), '') IS NOT NULL AND NOT phone_ok),
           (SELECT count(*)::int FROM base WHERE 'PASSPORT' = ANY (missing))
$$;

CREATE OR REPLACE FUNCTION people.duplicate_contacts(p_kind text, p_faculty text DEFAULT NULL, p_department text DEFAULT NULL, p_limit int DEFAULT 200)
RETURNS TABLE(value text, students int, names text)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.surname || ', ' || s.other_names || coalesce(' (' || s.matric_no || ')', '') AS who,
               CASE WHEN p_kind = 'PHONE' THEN regexp_replace(coalesce(x.phone, ''), '[^0-9]', '', 'g') ELSE lower(btrim(coalesce(x.email, ''))) END AS v
          FROM people.biodata_status_snapshot x JOIN people.student s ON s.id = x.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
         WHERE (p_faculty IS NULL OR p.faculty_code = p_faculty) AND (p_department IS NULL OR p.dept_code = p_department))
    SELECT v, count(*)::int, string_agg(who, '; ' ORDER BY who)
      FROM base WHERE v <> ''
     GROUP BY v HAVING count(*) > 1
     ORDER BY count(*) DESC, v
     LIMIT greatest(1, p_limit)
$$;

COMMIT;
