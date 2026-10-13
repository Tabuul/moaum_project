-- ═══════════════════════════════════════
-- V430 — staff reach, and the contact prompt at sign-in
--
--   The campaigns and reminders of V425/V426 reach a person only where the record holds an address. On the live register
--   13,882 students have no e-mail and 30,886 no phone; of the staff who came over, 627 have never signed in and one has an
--   e-mail on record. Two things close that gap without a hand on any list:
--
--   1. Staff reach — the same reading for the staff as the students have: for every active person with an office, whether
--      the e-mail and the phone are present and usable (iam.staff_reach_summary / staff_reach_list); a weekly reminder
--      (iam.remind_staff_contact) through the STAFF_CONTACT_REMINDER template to those whose contact is incomplete, by the
--      channel they do have, once in seven days, on ICT's switch; and a weekly digest to the HR office naming how many staff
--      cannot be reached at all.
--   2. The contact prompt — a student or staff member who signs in without a usable e-mail or phone is asked, once, on the
--      first screen: "how do we reach you". They may put it off for seven days at a time (platform.contact_prompt); nobody
--      is locked out. The answer is the contact they already keep (the student's contact, the person's record).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V430: staff reach and the contact prompt at sign-in', true);

-- ── 1 · staff reach ──────────────────────────────────────────────────────────────────────────────────────────────────
-- an active person with an office of any kind other than a student's or an applicant's
CREATE OR REPLACE FUNCTION iam.is_staff(p_person uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.office_assignment oa
                    WHERE oa.person_id = p_person AND oa.office_code NOT IN ('student', 'applicant')
                      AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date))
$$;

CREATE OR REPLACE FUNCTION iam.reach_status(p_email text, p_phone text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN platform.email_valid(p_email) AND platform.phone_valid(p_phone) THEN 'REACHABLE'
                WHEN platform.phone_valid(p_phone) THEN 'PHONE_ONLY'
                WHEN platform.email_valid(p_email) THEN 'EMAIL_ONLY'
                ELSE 'UNREACHABLE' END
$$;

CREATE TABLE iam.staff_contact_reminder (
    person_id    uuid PRIMARY KEY REFERENCES iam.person(id) ON DELETE CASCADE,
    last_sent_at timestamptz NOT NULL,
    sent         int NOT NULL DEFAULT 1,
    queued       int NOT NULL DEFAULT 0
);
SELECT audit.exempt('iam.staff_contact_reminder', 'when a staff member was last reminded to complete their contact; written by the weekly job, read to keep from reminding twice in a week');

CREATE OR REPLACE FUNCTION iam.staff_reach_summary(p_office text DEFAULT NULL)
RETURNS TABLE(total int, reachable int, phone_only int, email_only int, unreachable int,
              no_email int, bad_email int, no_phone int, bad_phone int, never_signed_in int, reminded_week int)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT p.id, p.email, p.phone, iam.reach_status(p.email, p.phone) AS st
          FROM iam.person p
         WHERE p.ended_on IS NULL AND iam.is_staff(p.id)
           AND (p_office IS NULL OR platform.office_active(p.id, p_office)))
    SELECT count(*)::int,
           count(*) FILTER (WHERE st = 'REACHABLE')::int,
           count(*) FILTER (WHERE st = 'PHONE_ONLY')::int,
           count(*) FILTER (WHERE st = 'EMAIL_ONLY')::int,
           count(*) FILTER (WHERE st = 'UNREACHABLE')::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(email, '')), '') IS NULL)::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(email, '')), '') IS NOT NULL AND NOT platform.email_valid(email))::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(phone, '')), '') IS NULL)::int,
           count(*) FILTER (WHERE nullif(btrim(coalesce(phone, '')), '') IS NOT NULL AND NOT platform.phone_valid(phone))::int,
           count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM iam.credential c WHERE c.person_id = base.id AND c.last_sign_in_at IS NOT NULL))::int,
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM iam.staff_contact_reminder r WHERE r.person_id = base.id AND r.last_sent_at > now() - interval '7 days'))::int
      FROM base
$$;

CREATE OR REPLACE FUNCTION iam.staff_reach_list(p_status text, p_office text, p_q text, p_limit int, p_offset int)
RETURNS TABLE(person_id uuid, staff_number text, surname text, given_names text, email text, phone text, status text, offices text,
              signed_in boolean, last_reminded_at timestamptz, total bigint)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT p.id, p.staff_number, p.surname, p.given_names, p.email, p.phone, iam.reach_status(p.email, p.phone) AS st,
               (SELECT string_agg(DISTINCT oa.office_code, ', ' ORDER BY oa.office_code) FROM iam.office_assignment oa
                 WHERE oa.person_id = p.id AND oa.office_code NOT IN ('student', 'applicant')
                   AND oa.valid_from <= current_date AND (oa.valid_to IS NULL OR oa.valid_to >= current_date)) AS offices,
               EXISTS (SELECT 1 FROM iam.credential c WHERE c.person_id = p.id AND c.last_sign_in_at IS NOT NULL) AS signed_in,
               (SELECT r.last_sent_at FROM iam.staff_contact_reminder r WHERE r.person_id = p.id) AS last_reminded_at
          FROM iam.person p
         WHERE p.ended_on IS NULL AND iam.is_staff(p.id)
           AND (p_office IS NULL OR platform.office_active(p.id, p_office))
           AND (p_q IS NULL OR btrim(p_q) = '' OR p.surname ILIKE '%' || btrim(p_q) || '%' OR p.given_names ILIKE '%' || btrim(p_q) || '%'
                OR coalesce(p.staff_number, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(p.email, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(p.phone, '') ILIKE '%' || btrim(p_q) || '%'))
    SELECT id, staff_number, surname, given_names, email, phone, st, offices, signed_in, last_reminded_at, count(*) OVER ()
      FROM base
     WHERE (p_status IS NULL OR st = p_status)
     ORDER BY surname, given_names
     LIMIT greatest(1, p_limit) OFFSET greatest(0, p_offset)
$$;

ALTER TABLE platform.notice_setting ADD COLUMN staff_contact_remind boolean NOT NULL DEFAULT false,
                                    ADD COLUMN staff_digest_week text NULL;
COMMENT ON COLUMN platform.notice_setting.staff_contact_remind IS 'V430: whether the weekly reminder to staff whose contact is incomplete runs (ICT''s switch; off by default).';
COMMENT ON COLUMN platform.notice_setting.staff_digest_week IS 'V430: the ISO week the HR office was last told how many staff cannot be reached; one digest a week however often the reminder runs.';

-- the weekly reminder: a staff member whose contact is incomplete is told by the channel they do have (and on the portal),
-- once in seven days; the HR office is told how many cannot be reached at all
CREATE OR REPLACE FUNCTION iam.remind_staff_contact(p_limit int DEFAULT 2000)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0; v_q int; v_unreachable int; v_week text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'IYYY-"W"IW');
BEGIN
    IF NOT coalesce((SELECT staff_contact_remind FROM platform.notice_setting WHERE id), false) THEN
        RETURN 0;
    END IF;
    FOR r IN
        SELECT p.id, p.email, p.phone, iam.reach_status(p.email, p.phone) AS st
          FROM iam.person p
          LEFT JOIN iam.staff_contact_reminder m ON m.person_id = p.id
         WHERE p.ended_on IS NULL AND iam.is_staff(p.id)
           AND iam.reach_status(p.email, p.phone) <> 'REACHABLE'
           AND (m.last_sent_at IS NULL OR m.last_sent_at <= now() - interval '7 days')
         ORDER BY m.last_sent_at NULLS FIRST, p.surname
         LIMIT greatest(1, p_limit)
    LOOP
        v_q := platform.tell_person(r.id, 'STAFF_CONTACT_REMINDER', NULL, jsonb_build_object(
                   'MISSING', CASE r.st WHEN 'PHONE_ONLY' THEN 'your e-mail address' WHEN 'EMAIL_ONLY' THEN 'your phone number' ELSE 'your e-mail address and phone number' END),
                   'staff-contact:' || v_week || ':' || r.id);
        INSERT INTO iam.staff_contact_reminder (person_id, last_sent_at, sent, queued) VALUES (r.id, now(), 1, v_q)
        ON CONFLICT (person_id) DO UPDATE SET last_sent_at = now(), sent = iam.staff_contact_reminder.sent + 1, queued = EXCLUDED.queued;
        n := n + 1;
    END LOOP;
    SELECT unreachable INTO v_unreachable FROM iam.staff_reach_summary(NULL);
    IF v_unreachable > 0 AND coalesce((SELECT staff_digest_week FROM platform.notice_setting WHERE id), '') <> v_week THEN
        UPDATE platform.notice_setting SET staff_digest_week = v_week WHERE id;
        PERFORM admissions.tell_office('hrm',
            v_unreachable || ' staff member' || CASE WHEN v_unreachable = 1 THEN ' cannot' ELSE 's cannot' END || ' be reached',
            'The portal holds neither a usable e-mail address nor a phone number for ' || v_unreachable || ' active staff member' || CASE WHEN v_unreachable = 1 THEN '' ELSE 's' END
            || '. They receive no notice, no password reset and no announcement until one is on record. Biodata compliance lists them under Staff reach.', NULL);
    END IF;
    RETURN n;
END $$;
COMMENT ON FUNCTION iam.remind_staff_contact(int) IS
  'V430: while ICT''s switch is on, tells each active staff member whose contact is incomplete (by the channel they have, and on the portal) through the STAFF_CONTACT_REMINDER template, once in seven days; the HR office is told once a week how many cannot be reached at all.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('STAFF_CONTACT_REMINDER', 'Staff contact incomplete', 'The weekly reminder to a staff member or lecturer whose e-mail or phone on the portal is missing or not usable; at most one a week, by the channel they have.',
 'Complete your contact details on the portal',
 E'Dear [FIRST_NAME],\n\nThe portal does not hold [MISSING] for you, so some notices cannot reach you. Please sign in and complete your contact details on My profile: [PORTAL_URL]\n\nDirectorate of ICT, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: the staff portal does not hold [MISSING] for you. Sign in and complete My profile: [PORTAL_URL]',
 'Complete your contact details', 'The portal does not hold [MISSING] for you. Complete My profile so that notices reach you.',
 ARRAY['FIRST_NAME','LAST_NAME','FULL_NAME','STAFF_NUMBER','MISSING','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL');

-- ── 2 · the contact prompt at sign-in ────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.contact_prompt (
    about_kind text NOT NULL CHECK (about_kind IN ('student', 'person')),
    about_id   uuid NOT NULL,
    skipped_at timestamptz NULL,
    skips      int NOT NULL DEFAULT 0,
    PRIMARY KEY (about_kind, about_id)
);
SELECT audit.exempt('platform.contact_prompt', 'when a person last put off the "how do we reach you" prompt; written by the person, read at sign-in');

-- ASK while the person has no usable e-mail or phone and has not put the prompt off in the last seven days; else NONE
CREATE OR REPLACE FUNCTION platform.contact_prompt_state(p_kind text, p_id uuid, p_email text, p_phone text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN platform.email_valid(p_email) AND platform.phone_valid(p_phone) THEN 'NONE'
                WHEN EXISTS (SELECT 1 FROM platform.contact_prompt x WHERE x.about_kind = p_kind AND x.about_id = p_id AND x.skipped_at > now() - interval '7 days') THEN 'NONE'
                ELSE 'ASK' END
$$;

CREATE OR REPLACE FUNCTION platform.contact_prompt_skip(p_kind text, p_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_kind NOT IN ('student', 'person') THEN
        RAISE EXCEPTION 'CONTACT_PROMPT_KIND: the prompt is a student''s or a staff member''s' USING ERRCODE = '23514';
    END IF;
    INSERT INTO platform.contact_prompt (about_kind, about_id, skipped_at, skips) VALUES (p_kind, p_id, now(), 1)
    ON CONFLICT (about_kind, about_id) DO UPDATE SET skipped_at = now(), skips = platform.contact_prompt.skips + 1;
END $$;

-- the student's prompt, from the contact the portal keeps; the staff member's from the person's record
CREATE OR REPLACE FUNCTION platform.contact_prompt_for(p_kind text, p_id uuid)
RETURNS TABLE(state text, email text, phone text, email_ok boolean, phone_ok boolean)
LANGUAGE sql STABLE AS $$
    SELECT platform.contact_prompt_state(p_kind, p_id, x.email, x.phone), x.email, x.phone, platform.email_valid(x.email), platform.phone_valid(x.phone)
      FROM (SELECT r.email, r.phone FROM people.student_reach(p_id) r WHERE p_kind = 'student'
            UNION ALL
            SELECT p.email, p.phone FROM iam.person p WHERE p_kind = 'person' AND p.id = p_id) x
$$;

COMMIT;
