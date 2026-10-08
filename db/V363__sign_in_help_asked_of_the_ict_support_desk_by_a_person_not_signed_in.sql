-- V363: a person who cannot sign in asks the ICT Support Desk for help from the sign-in page.
--
-- Until now a ticket could only be raised from inside the portal, so the person who most needed the desk — the one the
-- reset link never reaches, whose account is locked, whose number the portal does not recognise — had no way to ask.
-- The sign-in page now takes a request: who they say they are, the account and number they tried, what the portal
-- said, an email to track it with and a phone the desk can call. It becomes a Login Issues ticket on the desk.
--
-- Nothing in it is proven. The request names no account: its requester is the request itself (requester_kind
-- 'PUBLIC', requester_id = the ticket's own id), no department or faculty is taken from what was typed, and nothing is
-- matched to a record by the number or the name given. The desk confirms who the person is before it acts on any
-- account, through the tools it already has. What the person types is held to plain text (a name in letters, a phone
-- in digits), and an email address keeps at most three such requests open, so the form cannot be used to send the
-- University's mail to someone else's inbox again and again. The portal limits each connection as well (Throttle).

BEGIN;

ALTER TABLE helpdesk.ticket DROP CONSTRAINT ck_hd_ticket_requester;
ALTER TABLE helpdesk.ticket ADD CONSTRAINT ck_hd_ticket_requester CHECK (requester_kind IN ('STUDENT', 'STAFF', 'JUPEB', 'PUBLIC'));
ALTER TABLE helpdesk.ticket ADD CONSTRAINT ck_hd_ticket_public
    CHECK (requester_kind <> 'PUBLIC' OR (requester_id = id AND department_code IS NULL AND faculty_code IS NULL AND requester_email IS NOT NULL));
COMMENT ON COLUMN helpdesk.ticket.requester_kind IS
    'STUDENT (people.student), STAFF (iam.person), JUPEB (jupeb.application, V339) or, from V363, PUBLIC: asked from the sign-in page by a person not signed in — no account is linked, requester_id is the ticket''s own id, and nothing in it is proven until the desk confirms who the person is.';

CREATE OR REPLACE FUNCTION helpdesk.submit_public(p_name text, p_email text, p_phone text, p_details jsonb, p_description text)
RETURNS uuid
LANGUAGE plpgsql AS $$
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
    IF p_description IS NULL OR btrim(p_description) = '' OR length(p_description) > 4000 THEN
        RAISE EXCEPTION 'a request says what happened' USING ERRCODE = '23514', HINT = 'Say what you tried and what the portal did, in a few lines.';
    END IF;
    IF jsonb_typeof(v_details) <> 'object' THEN
        RAISE EXCEPTION 'the request''s details are a set of answers' USING ERRCODE = '23514';
    END IF;
    FOR f IN SELECT * FROM jsonb_array_elements(c.fields) LOOP
        v_value := btrim(coalesce(v_details->>(f->>'key'), ''));
        IF coalesce((f->>'required')::boolean, false) AND coalesce(f->>'type', 'text') <> 'file' AND v_value = '' THEN
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
            VALUES (v, v_number, c.id, 'Cannot sign in — ' || coalesce(nullif(btrim(v_details->>'account_type'), ''), 'the portal'), btrim(p_description), c.suggested_priority,
                    'PUBLIC', v, v_name, nullif(left(btrim(coalesce(v_details->>'username', '')), 60), ''), v_email, v_phone, NULL, NULL, v_details);
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            tries := tries + 1;
            IF tries >= 10 THEN RAISE; END IF;
        END;
    END LOOP;
    PERFORM helpdesk.record(v, 'REQUESTER', v, v_name, 'SUBMITTED', NULL, 'SUBMITTED', c.name || ' · asked from the sign-in page, not signed in');
    RETURN v;
END $$;
COMMENT ON FUNCTION helpdesk.submit_public(text, text, text, jsonb, text) IS
    'V363: a Login Issues ticket asked from the sign-in page by a person not signed in. No account is linked or matched; the name is letters only, the phone digits; at most three open per email address. The API limits each connection.';

COMMIT;
