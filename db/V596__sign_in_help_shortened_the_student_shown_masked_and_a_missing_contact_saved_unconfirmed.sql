-- V596: the sign-in help form asks less, shows the student the number names, and fills a missing e-mail or phone on the record.
--
--   * Shorter. The request from the sign-in page (V363) no longer asks what the portal says, when the problem started or what
--     happened; helpdesk.submit_public (restated from V363's text) requires only the account type and the number of the Login
--     Issues fields, and a request without a description says what it is about ("Cannot sign in to the student portal with …").
--     The in-portal ticket form keeps the category's fields as they are.
--   * The student shown. As a student-portal number is typed, helpdesk.sign_in_help_student says whose it is: the name in full
--     and the e-mail and phone on the record masked (people.mask_email, people.mask_phone: a•••••e@gmail.com, 0803•••4567), so
--     the student recognises their own and a person stepping through numbers collects no one's contacts — the Head of the ICT
--     Support Desk's choice of 20 October 2026. The number is read as the sign-in help reads it (upper case, no spaces): a
--     matriculation number, an admission number or a former matriculation number (V579), one student only.
--   * A missing contact saved. When the student's record holds no e-mail, or no phone, the one given on the request is saved to it
--     (people.contact_from_sign_in) — held unconfirmed as an uploaded contact is (V575): notices reach it, but a password-reset
--     link goes to it only after the student confirms it with a code at sign-in, or the desk confirms it with them. A contact the
--     record holds is never replaced.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V596: sign-in help shortened, the student shown masked, a missing contact saved unconfirmed', true);

-- ── masks ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.mask_email(p_email text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN nullif(btrim(coalesce(p_email, '')), '') IS NULL THEN NULL
                WHEN position('@' IN btrim(p_email)) <= 3 THEN '•••••' || substr(btrim(p_email), position('@' IN btrim(p_email)))
                ELSE left(btrim(p_email), 1) || '•••••' || substr(btrim(p_email), position('@' IN btrim(p_email)) - 1) END
$fn$;
CREATE FUNCTION people.mask_phone(p_phone text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '') IS NULL THEN NULL
                WHEN length(regexp_replace(p_phone, '[^0-9]', '', 'g')) <= 8 THEN '•••' || right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 2)
                ELSE left(regexp_replace(p_phone, '[^0-9]', '', 'g'), 4) || '•••' || right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 4) END
$fn$;

-- ── the student a number on the sign-in page names ─────────────────────────────────────────────────────────────────────────
CREATE FUNCTION helpdesk.sign_in_help_student(p_number text)
RETURNS TABLE (student_id uuid, corrected boolean, name text, email text, phone text, has_email boolean, has_phone boolean)
LANGUAGE sql STABLE AS $fn$
    WITH k AS (SELECT upper(regexp_replace(coalesce(p_number, ''), '\s+', '', 'g')) AS n),
    found AS (
        SELECT s.id, false AS corrected FROM people.student s, k WHERE k.n <> '' AND upper(s.matric_no) = k.n AND s.duplicate_of IS NULL
        UNION
        SELECT s.id, false FROM people.student s, k WHERE k.n <> '' AND upper(s.admission_no) = k.n AND s.duplicate_of IS NULL
        UNION
        SELECT a.student_id, true FROM people.matric_alias a, k WHERE k.n <> '' AND upper(a.old_no) = k.n AND a.ended_at IS NULL
    ),
    one AS (SELECT (array_agg(f.id))[1] AS id, bool_or(f.corrected) AS corrected FROM found f HAVING count(DISTINCT f.id) = 1)
    SELECT s.id, one.corrected,
           upper(btrim(s.surname)) || coalesce(' ' || nullif(btrim(s.other_names), ''), ''),
           people.mask_email(c.email), people.mask_phone(c.phone),
           nullif(btrim(coalesce(c.email, '')), '') IS NOT NULL, nullif(btrim(coalesce(c.phone, '')), '') IS NOT NULL
      FROM one JOIN people.student s ON s.id = one.id
      LEFT JOIN people.student_contact c ON c.student_id = s.id
$fn$;
COMMENT ON FUNCTION helpdesk.sign_in_help_student(text) IS
  'V596: the one student a number typed on the sign-in page names — the name in full, the e-mail and phone on the record masked, whether each is held';

-- ── a missing e-mail or phone filled from the request, unconfirmed ─────────────────────────────────────────────────────────
CREATE FUNCTION people.contact_from_sign_in(p_student uuid, p_email text, p_phone text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE c people.student_contact; v_email text := lower(btrim(coalesce(p_email, ''))); v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
        v_phone text; v_new_email text; v_new_phone text; v_saved text[] := ARRAY[]::text[];
BEGIN
    IF p_student IS NULL THEN
        RETURN '';
    END IF;
    -- the phone as the record keeps it: 0 and ten digits (+234 and 234 read as 0)
    v_phone := CASE WHEN v_digits ~ '^0[0-9]{10}$' THEN v_digits
                    WHEN v_digits ~ '^234[0-9]{10}$' THEN '0' || right(v_digits, 10)
                    WHEN v_digits ~ '^[1-9][0-9]{9}$' THEN '0' || v_digits END;
    IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := NULL; END IF;
    SELECT * INTO c FROM people.student_contact WHERE student_id = p_student FOR UPDATE;
    v_new_email := CASE WHEN v_email IS NOT NULL AND nullif(btrim(coalesce(c.email, '')), '') IS NULL THEN v_email END;
    v_new_phone := CASE WHEN v_phone IS NOT NULL AND nullif(btrim(coalesce(c.phone, '')), '') IS NULL THEN v_phone END;
    IF v_new_email IS NULL AND v_new_phone IS NULL THEN
        RETURN '';
    END IF;
    IF c.student_id IS NULL THEN
        INSERT INTO people.student_contact (student_id, email, email_pending, phone, phone_pending, updated_at)
        VALUES (p_student, v_new_email, v_new_email IS NOT NULL, v_new_phone, v_new_phone IS NOT NULL, now());
    ELSE
        UPDATE people.student_contact
           SET email = coalesce(v_new_email, email), email_pending = CASE WHEN v_new_email IS NOT NULL THEN true ELSE email_pending END,
               email_upload_id = CASE WHEN v_new_email IS NOT NULL THEN NULL ELSE email_upload_id END,
               phone = coalesce(v_new_phone, phone), phone_pending = CASE WHEN v_new_phone IS NOT NULL THEN true ELSE phone_pending END,
               phone_upload_id = CASE WHEN v_new_phone IS NOT NULL THEN NULL ELSE phone_upload_id END,
               updated_at = now()
         WHERE student_id = p_student;
    END IF;
    IF v_new_email IS NOT NULL THEN v_saved := array_append(v_saved, 'EMAIL'); END IF;
    IF v_new_phone IS NOT NULL THEN v_saved := array_append(v_saved, 'PHONE'); END IF;
    RETURN array_to_string(v_saved, ',');
END $fn$;
COMMENT ON FUNCTION people.contact_from_sign_in(uuid, text, text) IS
  'V596: the e-mail or phone a request from the sign-in page gives, saved to a student record that holds none — unconfirmed (V575) until the student or the desk confirms it; a contact held is never replaced';

-- ── the request (restated from V363's text) ────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.submit_public(p_name text, p_email text, p_phone text, p_details jsonb, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c helpdesk.category; f jsonb; v uuid := gen_random_uuid(); v_number text; n_open int; tries int := 0;
        v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
        v_email text := lower(btrim(coalesce(p_email, '')));
        v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
        v_details jsonb := coalesce(p_details, '{}'::jsonb);
        v_value text;
BEGIN
    SELECT * INTO c FROM helpdesk.category WHERE code = 'LOGIN';
    IF NOT FOUND OR NOT c.active THEN
        RAISE EXCEPTION 'sign-in help is not taking requests just now' USING ERRCODE = '23514', HINT = 'Visit the Directorate of ICT in person.';
    END IF;
    IF length(v_name) < 2 OR length(v_name) > 120 OR v_name !~ '^[[:alpha:]][[:alpha:] ''-]*$' THEN
        RAISE EXCEPTION 'a request gives the person''s name, in letters' USING ERRCODE = '23514', HINT = 'Write your name as the University has it: letters, spaces, hyphens and apostrophes only.';
    END IF;
    IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' OR length(v_email) > 200 THEN
        RAISE EXCEPTION 'a request carries an email address the desk can write to' USING ERRCODE = '23514', HINT = 'Give an email address you can read; the request is tracked with it.';
    END IF;
    IF v_phone IS NOT NULL AND v_phone !~ '^\+?[0-9][0-9 ]{6,19}$' THEN
        RAISE EXCEPTION 'a phone number is written in digits' USING ERRCODE = '23514', HINT = 'For example 08030000000 or +2348030000000.';
    END IF;
    -- V596: the form no longer asks what happened; a request without it says what it is about
    IF length(coalesce(p_description, '')) > 4000 THEN
        RAISE EXCEPTION 'a request says what happened in 4,000 characters or fewer' USING ERRCODE = '23514';
    END IF;
    IF jsonb_typeof(v_details) <> 'object' THEN
        RAISE EXCEPTION 'the request''s details are a set of answers' USING ERRCODE = '23514';
    END IF;
    FOR f IN SELECT * FROM jsonb_array_elements(c.fields) LOOP
        v_value := btrim(coalesce(v_details->>(f->>'key'), ''));
        -- V596: the sign-in page asks only the account and the number (what the portal says, and since when, are no longer asked)
        IF (f->>'key') IN ('account_type', 'username') AND coalesce((f->>'required')::boolean, false) AND coalesce(f->>'type', 'text') <> 'file' AND v_value = '' THEN
            RAISE EXCEPTION '% is required', f->>'label' USING ERRCODE = '23514', HINT = 'Fill it in and send the request again.';
        END IF;
        IF f->>'type' = 'select' AND v_value <> '' AND NOT coalesce((f->'options') ? v_value, false) THEN
            RAISE EXCEPTION '% is one of those offered', f->>'label' USING ERRCODE = '23514', HINT = 'Choose from the list.';
        END IF;
    END LOOP;
    SELECT count(*) INTO n_open FROM helpdesk.ticket WHERE requester_kind = 'PUBLIC' AND requester_email = v_email AND status <> 'CLOSED';
    IF n_open >= 3 THEN
        RAISE EXCEPTION 'three requests from this email address are open already' USING ERRCODE = '23514',
            HINT = 'Track them with their numbers; the desk answers each. Or visit the Directorate of ICT in person.';
    END IF;
    LOOP
        v_number := helpdesk.new_number();
        BEGIN
            INSERT INTO helpdesk.ticket (id, number, category_id, subject, description, priority, requester_kind, requester_id, requester_name, requester_number,
                                         requester_email, requester_phone, department_code, faculty_code, details)
            VALUES (v, v_number, c.id, 'Cannot sign in — ' || coalesce(nullif(btrim(v_details->>'account_type'), ''), 'the portal'),
                    coalesce(nullif(btrim(coalesce(p_description, '')), ''),
                             'Cannot sign in to the ' || coalesce(nullif(lower(btrim(v_details->>'account_type')), ''), 'portal')
                             || coalesce(' with ' || nullif(btrim(v_details->>'username'), ''), '') || '.'), c.suggested_priority,
                    'PUBLIC', v, v_name, nullif(left(btrim(coalesce(v_details->>'username', '')), 60), ''), v_email, v_phone, NULL, NULL, v_details);
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            tries := tries + 1;
            IF tries >= 10 THEN RAISE; END IF;
        END;
    END LOOP;
    PERFORM helpdesk.record(v, 'REQUESTER', v, v_name, 'SUBMITTED', NULL, 'SUBMITTED', c.name || ' · asked from the sign-in page, not signed in');
    RETURN v;
END $function$;

COMMIT;
