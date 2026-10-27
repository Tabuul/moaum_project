-- ═══════════════════════════════════════════════════════════════════════════
-- V668 — a transcript asked for without a portal account, and issued on the University's own template
--
--   The University's word of 27 October 2026: a graduate may no longer have the portal, and an institution never had it, yet both
--   ask the Registry for transcripts. Until now a request was the signed-in student's alone (credentials.request_document, V262).
--   This opens the same request at a public door, and changes nothing behind it — the fee, the payment reference, clearance, the
--   desk's processing, the quality check, the Registrar's release, the delivery by an expiring link or by courier are V262's:
--
--     · A GRADUATE proves who they are by the matriculation number and the date of birth on the record, then by a six-digit code
--       sent to the e-mail and phone the University reaches them at (people.student_reach). The code is good for fifteen minutes and
--       five tries; the pass it gives is good for an hour. Nothing says whether a number exists until the date of birth matches.
--     · A graduate who no longer has that e-mail or phone gives a new one and a photograph of an identity document: the request is
--       taken, the invoice raised, and nothing is produced until the desk has looked at the document (credentials.review_identity).
--     · An INSTITUTION names the graduate by matriculation number and surname. The graduate is asked, at the contact on record, to
--       consent by a private link good for fourteen days; nothing is produced without that consent, and a refusal cancels the request.
--     · Every public request is followed by its own private link (its SHA-256 kept, never the link): the stage in plain words, the
--       fee, the payment reference — renewed there once expired (finance.renew_reference, V635) — and the trail.
--     · A graduate who asked publicly is sent the secure download link at release, since they cannot open the portal to fetch it.
--
--   And the transcript itself follows the University's template ("ACADEMIC TRANSCRIPT (For External Use only)", Office of the
--   Registrar): a second TRANSCRIPT template version signed by the Dean and the Academic Secretary, the statement carrying the date of
--   birth, the sex and the session the holder left (credentials.build_statement, restated from V488 with those three keys and nothing
--   else changed); and the cover letter the Transcript Desk sends with each copy to a recipient ("ACADEMIC TRANSCRIPT IN RESPECT OF
--   …", Desk Officer Transcript, For: Academic Officer), its wording kept in credentials.cover_letter.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V668: transcripts asked for without a portal account, on the University''s template', true);

-- ── 1 · the code that proves a graduate, and the pass it gives ───────────

CREATE TABLE credentials.access_code (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    code_hash       bytea NOT NULL,
    sent_email      text NULL,                       -- masked, as the person was shown it
    sent_phone      text NULL,
    expires_at      timestamptz NOT NULL,
    attempts        int NOT NULL DEFAULT 0,
    verified_at     timestamptz NULL,
    pass_hash       bytea NULL UNIQUE,
    pass_expires_at timestamptz NULL,
    source          text NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ac_attempts CHECK (attempts BETWEEN 0 AND 10),
    CONSTRAINT ck_ac_pass CHECK ((pass_hash IS NULL) = (pass_expires_at IS NULL))
);
CREATE INDEX ix_ac_student ON credentials.access_code (student_id, created_at DESC);
SELECT audit.exempt('credentials.access_code',
  'V668: one-time codes (hashes) sent to a graduate asking for a transcript at the public door; like the password resets, no actor and nothing a person edits');

CREATE OR REPLACE FUNCTION credentials.secret_hash(p_secret text)
RETURNS bytea LANGUAGE sql IMMUTABLE AS $$
    SELECT digest(coalesce(p_secret, ''), 'sha256')
$$;

/* the graduate behind a matriculation number and a date of birth, or NULL — the same answer whichever of the two is wrong */
CREATE OR REPLACE FUNCTION credentials.public_student(p_matric text, p_dob date)
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT s.id FROM people.student s
     WHERE upper(s.matric_no) = upper(regexp_replace(btrim(coalesce(p_matric, '')), '\s+', '', 'g'))
       AND s.date_of_birth = p_dob AND s.duplicate_of IS NULL
     LIMIT 1
$$;

/* a code sent to the contact on record: returns the masked e-mail and phone it went to */
CREATE OR REPLACE FUNCTION credentials.public_code_send(p_matric text, p_dob date, p_source text)
RETURNS TABLE (challenge uuid, email text, phone text)
LANGUAGE plpgsql AS $$
DECLARE v_student uuid; reach record; v_code text; v_id uuid := gen_random_uuid(); v_name text;
BEGIN
    v_student := credentials.public_student(p_matric, p_dob);
    IF v_student IS NULL THEN
        RAISE EXCEPTION 'TRN_NOT_MATCHED: the matriculation number and date of birth do not match a record together' USING ERRCODE = '23514',
            HINT = 'Type them as on your admission letter; if they still do not match, the Registry corrects the record.';
    END IF;
    SELECT * INTO reach FROM people.student_reach(v_student);
    IF reach.email IS NULL AND reach.phone IS NULL THEN
        RAISE EXCEPTION 'TRN_NO_CONTACT: the record holds no e-mail or phone to send a code to' USING ERRCODE = '23514',
            HINT = 'Choose "I no longer have that e-mail or phone" and attach an identity document.';
    END IF;
    IF (SELECT count(*) FROM credentials.access_code c WHERE c.student_id = v_student AND c.created_at > now() - interval '1 hour') >= 5 THEN
        RAISE EXCEPTION 'TRN_CODE_LIMIT: five codes have been sent for this record in the last hour' USING ERRCODE = '23514',
            HINT = 'Use the latest code sent, or try again in an hour.';
    END IF;
    v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
    INSERT INTO credentials.access_code (id, student_id, code_hash, sent_email, sent_phone, expires_at, source)
    VALUES (v_id, v_student, credentials.secret_hash(v_id::text || ':' || v_code), people.mask_email(reach.email), people.mask_phone(reach.phone),
            now() + interval '15 minutes', left(p_source, 64));
    SELECT initcap(lower(split_part(btrim(s.other_names), ' ', 1))) INTO v_name FROM people.student s WHERE s.id = v_student;
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your transcript request code: ' || v_code,
        'Dear ' || coalesce(v_name, 'graduate') || E',\n\nYour code for a transcript request at Rev. Fr. Moses Orshio Adasu University, Makurdi is ' || v_code
        || E'. It is good for 15 minutes.\n\nIf you did not ask for it, ignore this message: nothing is requested without the code.', 'student', v_student);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Transcript request code',
        'MOAUM: your transcript request code is ' || v_code || '. Valid 15 minutes. Ignore if you did not ask.', 'student', v_student);
    RETURN QUERY SELECT v_id, people.mask_email(reach.email), people.mask_phone(reach.phone);
END $$;

/* the code checked: five tries, fifteen minutes; a match keeps the pass (its hash) for an hour */
CREATE OR REPLACE FUNCTION credentials.public_code_check(p_challenge uuid, p_code text, p_pass text)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE c credentials.access_code;
BEGIN
    SELECT * INTO c FROM credentials.access_code WHERE id = p_challenge FOR UPDATE;
    IF c.id IS NULL OR c.verified_at IS NOT NULL OR c.expires_at < now() OR c.attempts >= 5 THEN
        RAISE EXCEPTION 'TRN_CODE_SPENT: that code has expired or been used' USING ERRCODE = '23514', HINT = 'Ask for a new code.';
    END IF;
    IF p_pass IS NULL OR length(p_pass) < 32 THEN RAISE EXCEPTION 'TRN_PASS: a pass is a long random secret' USING ERRCODE = '23514'; END IF;
    IF c.code_hash <> credentials.secret_hash(c.id::text || ':' || regexp_replace(coalesce(p_code, ''), '\D', '', 'g')) THEN
        UPDATE credentials.access_code SET attempts = attempts + 1 WHERE id = c.id;
        RETURN false;
    END IF;
    UPDATE credentials.access_code SET verified_at = now(), attempts = attempts + 1, pass_hash = credentials.secret_hash(p_pass), pass_expires_at = now() + interval '1 hour'
     WHERE id = c.id;
    RETURN true;
END $$;

/* the graduate a pass stands for, while it stands */
CREATE OR REPLACE FUNCTION credentials.public_pass_student(p_pass text)
RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE v uuid;
BEGIN
    SELECT c.student_id INTO v FROM credentials.access_code c WHERE c.pass_hash = credentials.secret_hash(p_pass) AND c.pass_expires_at > now();
    IF v IS NULL THEN
        RAISE EXCEPTION 'TRN_PASS_EXPIRED: the confirmation has expired' USING ERRCODE = '23514', HINT = 'Start again: a new code is sent to you.';
    END IF;
    RETURN v;
END $$;

-- ── 2 · the request's public side ────────────────────────────────────────

CREATE TABLE credentials.public_request (
    request_id         uuid PRIMARY KEY REFERENCES credentials.transcript_request(id) ON DELETE CASCADE,
    requested_by       text NOT NULL,
    requester_name     text NOT NULL,
    organisation       text NULL,
    email              text NOT NULL,
    phone              text NULL,
    status_hash        bytea NOT NULL UNIQUE,
    identity_state     text NOT NULL,
    id_filename        text NULL,
    id_content_type    text NULL,
    id_content         bytea NULL,
    id_object          uuid NULL REFERENCES platform.file_object(id),
    id_sha256          bytea NULL,
    reviewed_by        uuid NULL,
    reviewed_at        timestamptz NULL,
    review_note        text NULL,
    consent_state      text NOT NULL,
    consent_hash       bytea NULL UNIQUE,
    consent_expires_at timestamptz NULL,
    consent_at         timestamptz NULL,
    consent_note       text NULL,
    source             text NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pr_by CHECK (requested_by IN ('GRADUATE','INSTITUTION')),
    CONSTRAINT ck_pr_identity CHECK (identity_state IN ('CONFIRMED','AWAITING_REVIEW','ACCEPTED','REFUSED','NOT_REQUIRED')),
    CONSTRAINT ck_pr_consent CHECK (consent_state IN ('NOT_REQUIRED','AWAITING','GIVEN','REFUSED','EXPIRED')),
    CONSTRAINT ck_pr_email CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT ck_pr_name CHECK (btrim(requester_name) <> '' AND length(requester_name) <= 200),
    -- a graduate is proved by the code or by a document the desk looks at; an institution by the graduate's consent
    CONSTRAINT ck_pr_shape CHECK (
        (requested_by = 'GRADUATE' AND consent_state = 'NOT_REQUIRED' AND identity_state IN ('CONFIRMED','AWAITING_REVIEW','ACCEPTED','REFUSED'))
     OR (requested_by = 'INSTITUTION' AND identity_state = 'NOT_REQUIRED' AND consent_state <> 'NOT_REQUIRED' AND consent_hash IS NOT NULL AND organisation IS NOT NULL)),
    CONSTRAINT ck_pr_document CHECK (identity_state NOT IN ('AWAITING_REVIEW','ACCEPTED','REFUSED') OR (id_filename IS NOT NULL AND id_sha256 IS NOT NULL AND (id_content IS NOT NULL OR id_object IS NOT NULL))),
    CONSTRAINT ck_pr_reviewed CHECK (identity_state NOT IN ('ACCEPTED','REFUSED') OR (reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL))
);
CREATE INDEX ix_pr_review ON credentials.public_request (created_at) WHERE identity_state = 'AWAITING_REVIEW';
SELECT audit.attach('credentials.public_request');

/* what the public may be shown of a stage */
CREATE OR REPLACE FUNCTION credentials.public_stage_words(p_stage text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_stage
        WHEN 'AWAITING_PAYMENT' THEN 'Awaiting payment'
        WHEN 'HELD_AT_CLEARANCE' THEN 'Paid — held until clearance is complete'
        WHEN 'READY' THEN 'Paid — with the Transcript Desk'
        WHEN 'PROCESSING' THEN 'Being prepared'
        WHEN 'GENERATED' THEN 'Being checked'
        WHEN 'CORRECTION' THEN 'Being corrected'
        WHEN 'VERIFIED' THEN 'Awaiting signature'
        WHEN 'RELEASED' THEN 'Issued — being delivered'
        WHEN 'DELIVERED' THEN 'Delivered'
        WHEN 'COMPLETED' THEN 'Completed'
        WHEN 'REJECTED' THEN 'Not issued'
        WHEN 'CANCELLED' THEN 'Cancelled'
        ELSE initcap(lower(replace(coalesce(p_stage, ''), '_', ' '))) END
$$;

/* the requester's acknowledgement, with the private link to follow it */
CREATE OR REPLACE FUNCTION credentials.public_acknowledge(p_request uuid, p_status_url text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request; pr credentials.public_request; v_holder text;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request;
    SELECT * INTO pr FROM credentials.public_request WHERE request_id = p_request;
    SELECT s.surname || ', ' || s.other_names INTO v_holder FROM people.student s WHERE s.id = t.student_id;
    PERFORM platform.queue_notice('EMAIL', pr.email, 'Transcript request ' || t.ref || ' received',
        'Dear ' || pr.requester_name || E',\n\nThe Registry has received request ' || t.ref || ' for an academic transcript in respect of ' || v_holder || '. '
        || CASE WHEN coalesce(t.fee, 0) > 0 THEN 'The fee is NGN ' || to_char(t.fee, 'FM999,999,990.00') || ', payable with reference ' || coalesce(t.reference, '(shown on the request page)') || '. ' ELSE '' END
        || CASE pr.consent_state WHEN 'AWAITING' THEN 'The graduate has been asked to consent; nothing is issued without it. ' ELSE '' END
        || CASE pr.identity_state WHEN 'AWAITING_REVIEW' THEN 'The identity document you attached is checked by the Transcript Desk before anything is issued. ' ELSE '' END
        || E'\n\nFollow the request, pay and renew the payment reference at your private link (keep it to yourself):\n' || coalesce(p_status_url, '')
        || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'transcript_request', t.id);
END $$;

/* the request made through credentials.request_document as the student it is for, with its public side; the fee and payment as V262's */
CREATE OR REPLACE FUNCTION credentials.public_request_make(
    p_student uuid, p_by text, p_status_token text, p_name text, p_org text, p_email text, p_phone text,
    p_kind text, p_destination text, p_destination_name text, p_department text, p_recipient text, p_recipient_email text, p_address text,
    p_recipient_ref text, p_purpose text, p_delivery text, p_express boolean, p_international boolean, p_copies int,
    p_identity text, p_consent_token text, p_source text,
    p_id_filename text DEFAULT NULL, p_id_content_type text DEFAULT NULL, p_id_content bytea DEFAULT NULL, p_id_object uuid DEFAULT NULL, p_id_sha256 bytea DEFAULT NULL)
RETURNS TABLE (id uuid, ref text, fee numeric, reference text, stage text)
LANGUAGE plpgsql AS $$
DECLARE r record; v_email text := lower(btrim(coalesce(p_email, '')));
BEGIN
    IF p_status_token IS NULL OR length(p_status_token) < 32 THEN RAISE EXCEPTION 'TRN_TOKEN: a request is followed by its private link' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_name, '')), '') IS NULL THEN RAISE EXCEPTION 'TRN_NAME: give your name' USING ERRCODE = '23514'; END IF;
    IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'TRN_EMAIL: give an e-mail address the Registry can write to' USING ERRCODE = '23514'; END IF;
    IF coalesce(p_kind, 'TRANSCRIPT') NOT IN ('TRANSCRIPT','SESSIONAL_TRANSCRIPT') THEN
        RAISE EXCEPTION 'TRN_KIND: a full or a sessional transcript is asked for here' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM credentials.request_document(p_student, coalesce(p_kind, 'TRANSCRIPT'), NULL, NULL, coalesce(p_destination, 'SELF'), p_destination_name, p_department,
                                                     p_recipient, p_recipient_email, p_address, p_recipient_ref, p_purpose, p_delivery, p_express, p_international, p_copies);
    INSERT INTO credentials.public_request (request_id, requested_by, requester_name, organisation, email, phone, status_hash, identity_state, consent_state,
                                            consent_hash, consent_expires_at, source, id_filename, id_content_type, id_content, id_object, id_sha256)
    VALUES (r.id, p_by, btrim(p_name), nullif(btrim(coalesce(p_org, '')), ''), v_email, nullif(btrim(coalesce(p_phone, '')), ''), credentials.secret_hash(p_status_token),
            CASE WHEN p_by = 'INSTITUTION' THEN 'NOT_REQUIRED' ELSE p_identity END,
            CASE WHEN p_by = 'INSTITUTION' THEN 'AWAITING' ELSE 'NOT_REQUIRED' END,
            CASE WHEN p_by = 'INSTITUTION' THEN credentials.secret_hash(p_consent_token) END,
            CASE WHEN p_by = 'INSTITUTION' THEN now() + interval '14 days' END, left(p_source, 64),
            left(p_id_filename, 200), p_id_content_type, p_id_content, p_id_object, p_id_sha256);
    PERFORM credentials.log(r.id, NULL, p_student, 'PUBLIC_REQUEST', NULL, r.stage,
        CASE p_by WHEN 'INSTITUTION' THEN 'Asked by ' || btrim(p_org) || ' (' || btrim(p_name) || ') without a portal account; the graduate''s consent sought'
                  ELSE 'Asked by the graduate without a portal account; identity ' || CASE p_identity WHEN 'CONFIRMED' THEN 'confirmed by a code to the contact on record' ELSE 'to be checked from a document' END END);
    RETURN QUERY SELECT r.id, r.ref, r.fee, r.reference, r.stage;
END $$;

/* a graduate proved by the code */
CREATE OR REPLACE FUNCTION credentials.public_request_graduate(
    p_pass text, p_status_token text, p_name text, p_email text, p_phone text,
    p_kind text, p_destination text, p_destination_name text, p_department text, p_recipient text, p_recipient_email text, p_address text,
    p_recipient_ref text, p_purpose text, p_delivery text, p_express boolean, p_international boolean, p_copies int, p_source text, p_status_url text)
RETURNS TABLE (id uuid, ref text, fee numeric, reference text, stage text)
LANGUAGE plpgsql AS $$
DECLARE v_student uuid := credentials.public_pass_student(p_pass); reach record; r record;
BEGIN
    SELECT * INTO reach FROM people.student_reach(v_student);
    SELECT * INTO r FROM credentials.public_request_make(v_student, 'GRADUATE', p_status_token,
        coalesce(nullif(btrim(coalesce(p_name, '')), ''), (SELECT s.other_names || ' ' || s.surname FROM people.student s WHERE s.id = v_student)),
        NULL, coalesce(nullif(btrim(coalesce(p_email, '')), ''), reach.email), coalesce(nullif(btrim(coalesce(p_phone, '')), ''), reach.phone),
        p_kind, p_destination, p_destination_name, p_department, p_recipient, p_recipient_email, p_address, p_recipient_ref, p_purpose, p_delivery, p_express,
        p_international, p_copies, 'CONFIRMED', NULL, p_source);
    PERFORM credentials.public_acknowledge(r.id, p_status_url);
    RETURN QUERY SELECT r.id, r.ref, r.fee, r.reference, r.stage;
END $$;

/* a graduate who no longer has the contact on record: a new one and an identity document the desk will look at */
CREATE OR REPLACE FUNCTION credentials.public_request_with_document(
    p_matric text, p_dob date, p_status_token text, p_name text, p_email text, p_phone text,
    p_id_filename text, p_id_content_type text, p_id_content bytea, p_id_object uuid, p_id_sha256 bytea,
    p_kind text, p_destination text, p_destination_name text, p_department text, p_recipient text, p_recipient_email text, p_address text,
    p_recipient_ref text, p_purpose text, p_delivery text, p_express boolean, p_international boolean, p_copies int, p_source text, p_status_url text)
RETURNS TABLE (id uuid, ref text, fee numeric, reference text, stage text)
LANGUAGE plpgsql AS $$
DECLARE v_student uuid := credentials.public_student(p_matric, p_dob); r record;
BEGIN
    IF v_student IS NULL THEN
        RAISE EXCEPTION 'TRN_NOT_MATCHED: the matriculation number and date of birth do not match a record together' USING ERRCODE = '23514',
            HINT = 'Type them as on your admission letter; if they still do not match, the Registry corrects the record.';
    END IF;
    IF p_id_filename IS NULL OR p_id_sha256 IS NULL OR (p_id_content IS NULL AND p_id_object IS NULL) THEN
        RAISE EXCEPTION 'TRN_ID_DOCUMENT: attach a photograph or scan of an identity document' USING ERRCODE = '23514';
    END IF;
    IF (SELECT count(*) FROM credentials.public_request q JOIN credentials.transcript_request t ON t.id = q.request_id
         WHERE t.student_id = v_student AND q.identity_state = 'AWAITING_REVIEW') >= 3 THEN
        RAISE EXCEPTION 'TRN_REVIEW_LIMIT: three requests for this record are already waiting for the desk to check an identity document' USING ERRCODE = '23514',
            HINT = 'Follow them by their links; the desk answers each.';
    END IF;
    SELECT * INTO r FROM credentials.public_request_make(v_student, 'GRADUATE', p_status_token, p_name, NULL, p_email, p_phone,
        p_kind, p_destination, p_destination_name, p_department, p_recipient, p_recipient_email, p_address, p_recipient_ref, p_purpose, p_delivery, p_express,
        p_international, p_copies, 'AWAITING_REVIEW', NULL, p_source, p_id_filename, p_id_content_type, p_id_content, p_id_object, p_id_sha256);
    PERFORM credentials.tell_desk('An identity document to check', 'Transcript request ' || r.ref || ' was made without access to the contact on record; check the identity document before it is processed.');
    PERFORM credentials.public_acknowledge(r.id, p_status_url);
    RETURN QUERY SELECT r.id, r.ref, r.fee, r.reference, r.stage;
END $$;

/* an institution, for a graduate it names by matriculation number and surname; the graduate is asked to consent */
CREATE OR REPLACE FUNCTION credentials.public_request_institution(
    p_matric text, p_surname text, p_status_token text, p_consent_token text, p_org text, p_name text, p_email text, p_phone text,
    p_destination text, p_department text, p_recipient text, p_recipient_email text, p_address text, p_recipient_ref text, p_purpose text,
    p_delivery text, p_express boolean, p_international boolean, p_copies int, p_source text, p_status_url text, p_consent_url text)
RETURNS TABLE (id uuid, ref text, fee numeric, reference text, stage text)
LANGUAGE plpgsql AS $$
DECLARE v_student uuid; reach record; r record; v_first text; v_dest text := coalesce(nullif(upper(btrim(coalesce(p_destination, ''))), ''), 'INSTITUTION');
BEGIN
    SELECT s.id, initcap(lower(split_part(btrim(s.other_names), ' ', 1))) INTO v_student, v_first FROM people.student s
     WHERE upper(s.matric_no) = upper(regexp_replace(btrim(coalesce(p_matric, '')), '\s+', '', 'g'))
       AND upper(btrim(s.surname)) = upper(btrim(coalesce(p_surname, ''))) AND s.duplicate_of IS NULL
     LIMIT 1;
    IF v_student IS NULL THEN
        RAISE EXCEPTION 'TRN_NOT_MATCHED: the matriculation number and surname do not match a record together' USING ERRCODE = '23514',
            HINT = 'Copy both from the graduate''s certificate or statement of result.';
    END IF;
    IF nullif(btrim(coalesce(p_org, '')), '') IS NULL THEN RAISE EXCEPTION 'TRN_ORG: name the institution or organisation' USING ERRCODE = '23514'; END IF;
    IF v_dest NOT IN ('INSTITUTION','EMPLOYER','EMBASSY','PROFESSIONAL_BODY','OTHER') THEN RAISE EXCEPTION 'TRN_DESTINATION: an institution asks for a copy sent to itself' USING ERRCODE = '23514'; END IF;
    IF p_consent_token IS NULL OR length(p_consent_token) < 32 THEN RAISE EXCEPTION 'TRN_TOKEN: consent is given at a private link' USING ERRCODE = '23514'; END IF;
    SELECT * INTO reach FROM people.student_reach(v_student);
    IF reach.email IS NULL AND reach.phone IS NULL THEN
        RAISE EXCEPTION 'TRN_NO_CONTACT: the graduate cannot be reached on the record to consent' USING ERRCODE = '23514',
            HINT = 'Ask the graduate to request the transcript, naming you as the recipient.';
    END IF;
    SELECT * INTO r FROM credentials.public_request_make(v_student, 'INSTITUTION', p_status_token, p_name, p_org, p_email, p_phone,
        'TRANSCRIPT', v_dest, btrim(p_org), p_department, coalesce(nullif(btrim(coalesce(p_recipient, '')), ''), btrim(p_name)),
        coalesce(nullif(btrim(coalesce(p_recipient_email, '')), ''), lower(btrim(p_email))), p_address, p_recipient_ref, p_purpose, p_delivery, p_express,
        p_international, p_copies, 'NOT_REQUIRED', p_consent_token, p_source);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your consent: ' || btrim(p_org) || ' asks for your transcript',
        'Dear ' || coalesce(v_first, 'graduate') || E',\n\n' || btrim(p_org) || ' has asked the Registry for your academic transcript'
        || coalesce(' (' || nullif(btrim(coalesce(p_purpose, '')), '') || ')', '') || ', request ' || r.ref || '. Nothing is issued without your consent.'
        || E'\n\nGive or refuse it within 14 days at:\n' || coalesce(p_consent_url, '')
        || E'\n\nIf you do not know this organisation, refuse.\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'transcript_request', r.id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Transcript consent',
        'MOAUM: ' || left(btrim(p_org), 60) || ' asks for your transcript (' || r.ref || '). Consent or refuse: ' || coalesce(p_consent_url, ''), 'transcript_request', r.id);
    PERFORM credentials.public_acknowledge(r.id, p_status_url);
    RETURN QUERY SELECT r.id, r.ref, r.fee, r.reference, r.stage;
END $$;

-- ── 2b · two recipients on one day are two requests ─────────────────────

/* the student asks for a document; a free self-service kind is issued at once, the rest wait for payment then the desk
   (restated from V262: V668 reads "the same request" as the same recipient, nothing else changed) */
CREATE OR REPLACE FUNCTION credentials.request_document(
    p_student uuid, p_kind text, p_session text, p_semester int, p_destination text, p_destination_name text, p_department text, p_recipient text,
    p_email text, p_address text, p_recipient_ref text, p_purpose text, p_delivery text, p_express boolean, p_international boolean, p_copies int)
RETURNS TABLE (id uuid, ref text, fee numeric, reference text, stage text)
LANGUAGE plpgsql AS $$
DECLARE pol credentials.document_policy; st people.student; v_id uuid := gen_random_uuid(); v_ref text; v_fee numeric; v_pay text; v_stage text; v_session text; v_yyyy text;
        v_delivery text := coalesce(upper(p_delivery), 'DIGITAL'); v_issued uuid;
BEGIN
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = p_kind AND active;
    IF pol.kind IS NULL THEN RAISE EXCEPTION 'no such document kind: %', p_kind USING ERRCODE = '23514'; END IF;
    SELECT * INTO st FROM people.student WHERE people.student.id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    IF st.matric_no IS NULL THEN RAISE EXCEPTION 'a document is issued against a matriculation number; the record has none yet' USING ERRCODE = '23514', HINT = 'Matriculation comes first.'; END IF;
    IF pol.graduates_only AND st.status <> 'GRADUATED' THEN RAISE EXCEPTION '% is issued to a graduated student', pol.label USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SESSIONAL_TRANSCRIPT' AND p_session IS NULL THEN RAISE EXCEPTION 'a sessional transcript names its session' USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SESSIONAL_TRANSCRIPT' AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) r WHERE r.session = p_session AND r.published)
       AND NOT EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student AND r.session = p_session) THEN
        RAISE EXCEPTION 'no published result stands for % ', p_session USING ERRCODE = '23514';
    END IF;
    IF p_destination IN ('INSTITUTION','EMPLOYER','EMBASSY','PROFESSIONAL_BODY','OTHER') AND nullif(btrim(coalesce(p_destination_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'name the recipient' USING ERRCODE = '23514';
    END IF;
    IF v_delivery IN ('PHYSICAL','BOTH') AND nullif(btrim(coalesce(p_address, '')), '') IS NULL THEN RAISE EXCEPTION 'a physical delivery needs an address' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM credentials.transcript_request t WHERE t.student_id = p_student AND t.kind = p_kind AND t.session IS NOT DISTINCT FROM p_session AND t.semester IS NOT DISTINCT FROM p_semester
               AND t.stage IN ('AWAITING_PAYMENT','READY','HELD_AT_CLEARANCE','PROCESSING','GENERATED','CORRECTION','VERIFIED') AND t.requested_at > now() - interval '1 day'
               -- V668: the same request is to the same recipient; copies to two institutions on one day are two requests
               AND t.destination = coalesce(p_destination, 'SELF')
               AND lower(coalesce(t.destination_name, '')) = lower(btrim(coalesce(p_destination_name, '')))
               AND lower(coalesce(t.recipient_email, '')) = lower(btrim(coalesce(p_email, '')))) THEN
        RAISE EXCEPTION 'the same request was made within the day and is still in hand' USING ERRCODE = '23505';
    END IF;
    v_session := coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), p_session, '2026/2027');
    v_yyyy := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
    v_ref := 'TRN-' || v_yyyy || '-' || lpad(platform.next_number('TRANSCRIPT', 'UNIVERSITY', v_yyyy)::text, 5, '0');
    v_fee := credentials.fee_for(p_kind, v_session, v_delivery, coalesce(p_express, false), coalesce(p_international, false), p_copies);
    v_stage := CASE WHEN v_fee > 0 THEN 'AWAITING_PAYMENT' WHEN p_kind = 'TRANSCRIPT' AND NOT clearance.is_clear(p_student, 'TRANSCRIPT') THEN 'HELD_AT_CLEARANCE' ELSE 'READY' END;
    INSERT INTO credentials.transcript_request (id, ref, student_id, destination, destination_name, mode, express, copies, kind, session, semester, delivery, international,
                                                recipient_department, recipient_name, recipient_email, recipient_address, recipient_reference, purpose, fee, stage, paid_at, sla_due_on)
    VALUES (v_id, v_ref, p_student, coalesce(p_destination, 'SELF'), nullif(btrim(coalesce(p_destination_name, '')), ''), CASE WHEN v_delivery = 'DIGITAL' THEN 'DIGITAL' ELSE 'SEALED' END,
            coalesce(p_express, false), greatest(1, coalesce(p_copies, 1)), p_kind, p_session, p_semester, v_delivery, coalesce(p_international, false),
            nullif(btrim(coalesce(p_department, '')), ''), nullif(btrim(coalesce(p_recipient, '')), ''), nullif(lower(btrim(coalesce(p_email, ''))), ''), nullif(btrim(coalesce(p_address, '')), ''),
            nullif(btrim(coalesce(p_recipient_ref, '')), ''), nullif(btrim(coalesce(p_purpose, '')), ''), v_fee, v_stage, CASE WHEN v_fee = 0 THEN now() END,
            CASE WHEN v_fee = 0 THEN current_date + CASE WHEN coalesce(p_express, false) THEN pol.urgent_sla_days ELSE pol.sla_days END END);
    IF v_fee > 0 THEN
        v_pay := finance.new_purpose_reference(p_student, v_session, v_fee, 'Transcript ' || v_ref);
        UPDATE credentials.transcript_request SET reference = v_pay WHERE credentials.transcript_request.id = v_id;
    END IF;
    PERFORM credentials.log(v_id, NULL, p_student, 'REQUESTED', NULL, v_stage, pol.label || coalesce(' · ' || p_session, '') || coalesce(' · semester ' || p_semester, '') || ' · ' || v_delivery);
    PERFORM credentials.tell(p_student, 'Document request ' || v_ref || ' submitted',
        'Your request for a ' || lower(pol.label) || ' (' || v_ref || ') has been submitted. '
        || CASE WHEN v_fee > 0 THEN 'An invoice of NGN ' || v_fee::text || ' stands against payment reference ' || v_pay || '; processing begins when it is confirmed.'
                WHEN v_stage = 'HELD_AT_CLEARANCE' THEN 'It is held at clearance until every unit signs.'
                ELSE 'It is with the Exams and Records desk.' END,
        'MOAUM: document request ' || v_ref || ' submitted.' || CASE WHEN v_fee > 0 THEN ' Pay NGN ' || v_fee::text || ' ref ' || v_pay ELSE '' END);
    -- a free self-service kind is issued at once, the desk told after the fact
    IF v_fee = 0 AND pol.self_service AND v_stage = 'READY' THEN
        v_issued := credentials.produce_transcript(v_id);
        UPDATE credentials.transcript_request SET stage = 'RELEASED', released_at = now(), qc_at = now(), qc_note = 'Self-service: issued at once under the policy' WHERE credentials.transcript_request.id = v_id;
        PERFORM credentials.log(v_id, v_issued, p_student, 'RELEASED', 'GENERATED', 'RELEASED', 'Self-service under the policy');
        PERFORM credentials.open_delivery(v_id);
    ELSIF v_fee = 0 THEN
        PERFORM credentials.tell_desk('A document request awaits', 'Request ' || v_ref || ' for a ' || lower(pol.label) || ' is ready for processing.');
    END IF;
    RETURN QUERY SELECT v_id, v_ref, v_fee, v_pay, (SELECT t.stage FROM credentials.transcript_request t WHERE t.id = v_id);
END $$;

-- ── 3 · following a request, consenting, and the desk's check ────────────

/* the request behind a private link, in what the public may see */
CREATE OR REPLACE FUNCTION credentials.public_status(p_status_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE pr credentials.public_request; t credentials.transcript_request; pay record;
BEGIN
    SELECT * INTO pr FROM credentials.public_request WHERE status_hash = credentials.secret_hash(p_status_token);
    IF pr.request_id IS NULL THEN RAISE EXCEPTION 'TRN_NOT_FOUND: no request at that link' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = pr.request_id;
    SELECT p.expires_at INTO pay FROM finance.payment_reference p WHERE p.reference = t.reference;
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'ref', t.ref, 'kind', t.kind, 'kindLabel', (SELECT label FROM credentials.document_policy WHERE kind = t.kind),
        'holder', (SELECT s.surname || ', ' || s.other_names FROM people.student s WHERE s.id = t.student_id),
        'matricNo', (SELECT s.matric_no FROM people.student s WHERE s.id = t.student_id),
        'requestedBy', pr.requested_by, 'requesterName', pr.requester_name, 'organisation', pr.organisation, 'email', pr.email,
        'stage', t.stage, 'stageWords', credentials.public_stage_words(t.stage), 'closed', t.closed_at IS NOT NULL, 'closedReason', t.closed_reason,
        'delivery', t.delivery, 'copies', t.copies, 'express', t.express, 'destination', t.destination, 'destinationName', t.destination_name,
        'recipientEmail', t.recipient_email, 'recipientAddress', t.recipient_address,
        'fee', t.fee, 'reference', t.reference, 'paid', t.paid_at IS NOT NULL, 'paidAt', t.paid_at,
        'referenceExpiresAt', pay.expires_at, 'referenceExpired', t.paid_at IS NULL AND pay.expires_at IS NOT NULL AND pay.expires_at < now(),
        'identityState', pr.identity_state, 'consentState', pr.consent_state, 'consentExpiresAt', pr.consent_expires_at,
        'requestedAt', t.requested_at, 'slaDueOn', t.sla_due_on,
        'timeline', (SELECT jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action, 'stage', credentials.public_stage_words(e.to_state)) ORDER BY e.at)
                       FROM credentials.event e WHERE e.request_id = t.id AND e.action IN ('REQUESTED','PUBLIC_REQUEST','PAID','IDENTITY','CONSENT','RELEASED','DELIVERED','COMPLETED','CANCELLED'))));
END $$;

/* the payment reference made payable again from the private link, as the student's own reference is (V635) */
CREATE OR REPLACE FUNCTION credentials.public_renew_reference(p_status_token text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE pr credentials.public_request; t credentials.transcript_request; v text;
BEGIN
    SELECT * INTO pr FROM credentials.public_request WHERE status_hash = credentials.secret_hash(p_status_token);
    IF pr.request_id IS NULL THEN RAISE EXCEPTION 'TRN_NOT_FOUND: no request at that link' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = pr.request_id;
    IF t.paid_at IS NOT NULL OR t.reference IS NULL OR t.closed_at IS NOT NULL THEN
        RAISE EXCEPTION 'TRN_NOTHING_TO_PAY: this request has nothing left to pay' USING ERRCODE = '23514';
    END IF;
    SELECT x.reference_out INTO v FROM finance.renew_reference(t.student_id, t.reference) x;
    IF v IS NOT NULL AND v <> t.reference THEN UPDATE credentials.transcript_request SET reference = v WHERE id = t.id; END IF;
    RETURN coalesce(v, t.reference);
END $$;

/* what the graduate is shown before consenting */
CREATE OR REPLACE FUNCTION credentials.public_consent_view(p_consent_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE pr credentials.public_request; t credentials.transcript_request;
BEGIN
    SELECT * INTO pr FROM credentials.public_request WHERE consent_hash = credentials.secret_hash(p_consent_token);
    IF pr.request_id IS NULL THEN RAISE EXCEPTION 'TRN_NOT_FOUND: no consent is asked at that link' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = pr.request_id;
    RETURN jsonb_strip_nulls(jsonb_build_object('ref', t.ref, 'organisation', pr.organisation, 'requesterName', pr.requester_name, 'email', pr.email,
        'purpose', t.purpose, 'recipientName', t.recipient_name, 'recipientEmail', t.recipient_email, 'recipientAddress', t.recipient_address, 'delivery', t.delivery,
        'holder', (SELECT s.other_names || ' ' || s.surname FROM people.student s WHERE s.id = t.student_id),
        'state', CASE WHEN pr.consent_state = 'AWAITING' AND pr.consent_expires_at < now() THEN 'EXPIRED' ELSE pr.consent_state END,
        'expiresAt', pr.consent_expires_at, 'decidedAt', pr.consent_at, 'requestClosed', t.closed_at IS NOT NULL));
END $$;

/* the graduate gives or refuses consent; a refusal cancels the request (a paid fee is the Bursary's to refund, as V262's cancellation says) */
CREATE OR REPLACE FUNCTION credentials.public_consent(p_consent_token text, p_give boolean, p_note text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE pr credentials.public_request; t credentials.transcript_request; v_to text;
BEGIN
    SELECT * INTO pr FROM credentials.public_request WHERE consent_hash = credentials.secret_hash(p_consent_token) FOR UPDATE;
    IF pr.request_id IS NULL THEN RAISE EXCEPTION 'TRN_NOT_FOUND: no consent is asked at that link' USING ERRCODE = 'P0002'; END IF;
    IF pr.consent_state <> 'AWAITING' THEN RAISE EXCEPTION 'TRN_CONSENT_DECIDED: consent was already %', lower(pr.consent_state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = pr.request_id;
    IF pr.consent_expires_at < now() THEN
        UPDATE credentials.public_request SET consent_state = 'EXPIRED' WHERE request_id = pr.request_id;
        RAISE EXCEPTION 'TRN_CONSENT_EXPIRED: the fourteen days to consent have passed' USING ERRCODE = '23514', HINT = 'The institution asks again.';
    END IF;
    IF t.closed_at IS NOT NULL THEN RAISE EXCEPTION 'TRN_CLOSED: the request is closed' USING ERRCODE = '23514'; END IF;
    v_to := CASE WHEN p_give THEN 'GIVEN' ELSE 'REFUSED' END;
    UPDATE credentials.public_request SET consent_state = v_to, consent_at = now(), consent_note = nullif(btrim(coalesce(p_note, '')), '') WHERE request_id = pr.request_id;
    PERFORM credentials.log(t.id, NULL, t.student_id, 'CONSENT', t.stage, t.stage, 'The graduate ' || CASE WHEN p_give THEN 'consented' ELSE 'refused consent' END || ' to ' || pr.organisation);
    IF NOT p_give THEN
        UPDATE credentials.transcript_request SET stage = 'CANCELLED', closed_at = now(), closed_reason = 'The graduate did not consent' WHERE id = t.id;
        PERFORM credentials.log(t.id, NULL, t.student_id, 'CANCELLED', t.stage, 'CANCELLED', 'The graduate did not consent');
    END IF;
    PERFORM platform.queue_notice('EMAIL', pr.email, 'Transcript request ' || t.ref || ': the graduate ' || CASE WHEN p_give THEN 'has consented' ELSE 'did not consent' END,
        'Dear ' || pr.requester_name || E',\n\nThe graduate ' || CASE WHEN p_give THEN 'has consented to request ' || t.ref || '. It proceeds once paid and processed.'
                                                                      ELSE 'did not consent to request ' || t.ref || ', and it is cancelled. A fee already paid is refunded through the University''s Bursary.' END
        || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'transcript_request', t.id);
    RETURN v_to;
END $$;

/* the desk looks at an identity document: accepted, the request proceeds; refused, it is rejected and the requester told why */
CREATE OR REPLACE FUNCTION credentials.review_identity(p_request uuid, p_accept boolean, p_note text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE pr credentials.public_request; t credentials.transcript_request; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO pr FROM credentials.public_request WHERE request_id = p_request FOR UPDATE;
    IF pr.request_id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF pr.identity_state <> 'AWAITING_REVIEW' THEN RAISE EXCEPTION 'TRN_NOT_FOR_REVIEW: this request has no identity document waiting' USING ERRCODE = '23514'; END IF;
    IF v_actor IS NULL OR v_actor = '00000000-0000-0000-0000-000000000000' THEN RAISE EXCEPTION 'an identity document is checked by a person' USING ERRCODE = '23514'; END IF;
    IF NOT p_accept AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'say why the document is refused' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request;
    UPDATE credentials.public_request SET identity_state = CASE WHEN p_accept THEN 'ACCEPTED' ELSE 'REFUSED' END, reviewed_by = v_actor, reviewed_at = now(),
                                          review_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE request_id = p_request;
    PERFORM credentials.log(t.id, NULL, t.student_id, 'IDENTITY', t.stage, t.stage, 'Identity document ' || CASE WHEN p_accept THEN 'accepted' ELSE 'refused' END || coalesce(': ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    IF NOT p_accept AND t.closed_at IS NULL THEN
        UPDATE credentials.transcript_request SET stage = 'REJECTED', closed_at = now(), closed_reason = 'Identity not confirmed: ' || btrim(p_note) WHERE id = t.id;
        PERFORM credentials.log(t.id, NULL, t.student_id, 'REJECTED', t.stage, 'REJECTED', 'Identity not confirmed');
    END IF;
    PERFORM platform.queue_notice('EMAIL', pr.email, 'Transcript request ' || t.ref || ': ' || CASE WHEN p_accept THEN 'identity confirmed' ELSE 'identity not confirmed' END,
        'Dear ' || pr.requester_name || E',\n\n' || CASE WHEN p_accept THEN 'The Transcript Desk has confirmed your identity, and request ' || t.ref || ' proceeds once paid.'
                                                        ELSE 'The Transcript Desk could not confirm your identity from the document attached (' || btrim(p_note) || '), and request ' || t.ref
                                                             || ' is not issued. A fee already paid is refunded through the University''s Bursary; visit the Registry with your identity document.' END
        || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'transcript_request', t.id);
    RETURN CASE WHEN p_accept THEN 'ACCEPTED' ELSE 'REFUSED' END;
END $$;

/* whether a request may be produced: always for a student's own; for a public one once the identity or the consent stands */
CREATE OR REPLACE FUNCTION credentials.public_cleared(p_request uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT pr.identity_state IN ('CONFIRMED','ACCEPTED','NOT_REQUIRED') AND pr.consent_state IN ('NOT_REQUIRED','GIVEN')
                       FROM credentials.public_request pr WHERE pr.request_id = p_request), true)
$$;

/* what the desk is shown of a request's public side (NULL for a student's own) */
CREATE OR REPLACE FUNCTION credentials.public_side(p_request uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object('requestedBy', pr.requested_by, 'requesterName', pr.requester_name, 'organisation', pr.organisation, 'email', pr.email,
               'phone', pr.phone, 'identityState', pr.identity_state, 'idFilename', pr.id_filename, 'idContentType', pr.id_content_type,
               'reviewedAt', pr.reviewed_at, 'reviewedBy', CASE WHEN pr.reviewed_by IS NOT NULL THEN helpdesk.person_name(pr.reviewed_by) END, 'reviewNote', pr.review_note,
               'consentState', CASE WHEN pr.consent_state = 'AWAITING' AND pr.consent_expires_at < now() THEN 'EXPIRED' ELSE pr.consent_state END,
               'consentExpiresAt', pr.consent_expires_at, 'consentAt', pr.consent_at, 'consentNote', pr.consent_note, 'createdAt', pr.created_at,
               'cleared', credentials.public_cleared(pr.request_id)))
      FROM credentials.public_request pr WHERE pr.request_id = p_request
$$;

-- ── 4 · nothing is produced for a public request until it is proved ──────


CREATE OR REPLACE FUNCTION credentials.public_request_gate()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pr credentials.public_request;
BEGIN
    IF NEW.stage IS DISTINCT FROM OLD.stage AND NEW.stage IN ('PROCESSING','GENERATED','VERIFIED','RELEASED') AND NOT credentials.public_cleared(NEW.id) THEN
        SELECT * INTO pr FROM credentials.public_request WHERE request_id = NEW.id;
        IF pr.identity_state NOT IN ('CONFIRMED','ACCEPTED','NOT_REQUIRED') THEN
            RAISE EXCEPTION 'TRN_IDENTITY_PENDING: request % waits for the identity document to be checked', NEW.ref USING ERRCODE = '23514',
                HINT = 'Open the request and accept or refuse the identity document first.';
        END IF;
        RAISE EXCEPTION 'TRN_CONSENT_PENDING: request % waits for the graduate''s consent', NEW.ref USING ERRCODE = '23514',
            HINT = 'Nothing is produced for an institution until the graduate consents.';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_public_request_gate BEFORE UPDATE OF stage ON credentials.transcript_request FOR EACH ROW EXECUTE FUNCTION credentials.public_request_gate();

/* a graduate who asked publicly cannot open the portal: the student's secure link is sent to them when it is made */
CREATE OR REPLACE FUNCTION credentials.public_delivery_sent()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pr credentials.public_request; t credentials.transcript_request; v_token text;
BEGIN
    IF NEW.kind <> 'DIGITAL' OR NEW.token_id IS NULL OR NEW.email IS NOT NULL THEN RETURN NEW; END IF;
    SELECT * INTO pr FROM credentials.public_request WHERE request_id = NEW.request_id AND requested_by = 'GRADUATE';
    IF pr.request_id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = NEW.request_id;
    SELECT token INTO v_token FROM credentials.download_token WHERE id = NEW.token_id;
    PERFORM platform.queue_notice('EMAIL', pr.email, 'Your transcript ' || t.ref || ' is ready',
        'Dear ' || pr.requester_name || E',\n\nYour academic transcript (request ' || t.ref || E') has been issued. Download it at the secure link below; it expires in 30 days:\n'
        || coalesce(platform.portal_url(), '') || '/documents/d/' || v_token
        || E'\n\nAny recipient can verify it by the verification code it carries.\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'document', NEW.issued_id);
    NEW.recipient := pr.requester_name;
    NEW.email := pr.email;
    NEW.state := 'SENT';
    NEW.note := 'Secure link sent by e-mail to the graduate (asked without a portal account)';
    RETURN NEW;
END $$;
CREATE TRIGGER trg_public_delivery_sent BEFORE INSERT ON credentials.delivery FOR EACH ROW EXECUTE FUNCTION credentials.public_delivery_sent();

-- ── 5 · the University's template, signed by the Dean and the Academic Secretary ──

UPDATE credentials.document_template SET active = false WHERE kind = 'TRANSCRIPT' AND active;
INSERT INTO credentials.document_template (kind, version, title, subtitle, signatory_name, signatory_title, second_name, second_title, footer, remarks, active)
SELECT 'TRANSCRIPT', coalesce(max(version), 0) + 1, 'Academic Transcript', '(For External Use only)', 'Signature of Dean', 'Stamp and Date',
       'Signature of Academic Secretary', 'Stamp and Date',
       'Not valid without the verification code. Any alteration renders this transcript invalid.', NULL, true
  FROM credentials.document_template WHERE kind = 'TRANSCRIPT';

-- ── 6 · the cover letter the Transcript Desk sends with each copy ────────

CREATE TABLE credentials.cover_letter (
    id               int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    signatory_name   text NULL,                       -- NULL: the officer who produced the transcript
    signatory_title  text NOT NULL,
    on_behalf_of     text NOT NULL,
    body             text NOT NULL,
    closing          text NOT NULL,
    updated_at       timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('credentials.cover_letter');
INSERT INTO credentials.cover_letter (signatory_name, signatory_title, on_behalf_of, body, closing)
VALUES (NULL, 'Desk Officer Transcript', 'For: Academic Officer',
        'At the request of [HOLDER] ([MATRIC]), I forward herewith his/her Academic Transcript to facilitate his/her application for [PURPOSE].',
        E'Kindly treat as confidential.\n\nThank you.');

/* the letter for one request: the recipient, the holder, the words, the officer who signs */
CREATE OR REPLACE FUNCTION credentials.cover_letter_for(p_request uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'ref', s.matric_no, 'requestRef', t.ref,
        'date', coalesce(t.released_at, t.produced_at, now())::date,
        'recipientName', t.recipient_name, 'organisation', t.destination_name, 'department', t.recipient_department, 'address', t.recipient_address,
        'recipientReference', t.recipient_reference,
        'holder', initcap(lower(btrim(s.other_names))) || ' ' || initcap(lower(btrim(s.surname))),
        'holderUpper', upper(btrim(s.other_names) || ' ' || btrim(s.surname)), 'matricNo', s.matric_no,
        'body', replace(replace(replace(l.body, '[HOLDER]', initcap(lower(btrim(s.other_names))) || ' ' || initcap(lower(btrim(s.surname)))), '[MATRIC]', s.matric_no),
                        '[PURPOSE]', coalesce(nullif(btrim(coalesce(t.purpose, '')), ''), 'admission/employment')),
        'closing', l.closing,
        'signatoryName', coalesce(l.signatory_name, CASE WHEN t.produced_by IS NOT NULL THEN helpdesk.person_name(t.produced_by) END),
        'signatoryTitle', l.signatory_title, 'onBehalfOf', l.on_behalf_of))
      FROM credentials.transcript_request t
      JOIN people.student s ON s.id = t.student_id
      CROSS JOIN credentials.cover_letter l
     WHERE t.id = p_request AND t.destination <> 'SELF'
$$;

-- ── 7 · the statement carries the date of birth, the sex and the session left (restated from V488; nothing else changed) ──

CREATE OR REPLACE FUNCTION credentials.build_statement(p_student uuid, p_kind text, p_session text, p_semester integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE st record; g record; pol credentials.document_policy; v_sessions jsonb; v_cgpa numeric; v_class text; v_scope text; v_cur text; v_cur_sem int;
        v_pg boolean; v_research jsonb; v_totals record; v_semesters jsonb;
BEGIN
    SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.entry_mode, s.entry_session, s.entry_level, s.current_level, s.status, s.programme_code, s.study_mode,
           s.date_of_birth, s.sex,
           p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, coalesce(p.pg_award, p.name) AS award_name
      INTO st FROM people.student s JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = p_kind;
    SELECT * INTO g FROM records.graduand gg WHERE gg.student_id = p_student AND gg.senate_state = 'APPROVED' ORDER BY gg.session DESC LIMIT 1;
    v_pg := st.entry_mode = 'POSTGRADUATE' OR EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student);
    v_cur := (SELECT name FROM policy.academic_session WHERE state = 'CURRENT');
    v_cur_sem := (SELECT number FROM policy.semester WHERE session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    -- V381: a CCE student's current semester is the CCE calendar's
    IF st.entry_mode = 'CCE' THEN
        v_cur := policy.route_session('CCE');
        v_cur_sem := (SELECT number FROM policy.route_semester WHERE route = 'CCE' AND session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    END IF;
    -- the scope of the document
    v_scope := CASE p_kind WHEN 'SESSIONAL_TRANSCRIPT' THEN 'SELECTED_SESSION' WHEN 'MINI_TRANSCRIPT' THEN pol.includes ELSE 'CUMULATIVE' END;
    IF NOT v_pg THEN
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', gp.units, 'gpa', gp.gpa, 'cgpa', gp.cgpa, 'tcr', gp.tcr, 'tce', gp.tce, 'twgp', gp.twgp) ORDER BY r.semester) AS semesters
                  FROM (SELECT x.session, x.semester,
                               jsonb_agg(jsonb_build_object('code', x.course_code, 'title', x.title, 'units', x.units, 'grade', x.grade, 'points', x.points, 'quality', round(coalesce(x.points, 0) * x.units, 2), 'type', x.entry_type, 'outcome', x.outcome) ORDER BY x.course_code) AS courses
                          FROM assessment.student_results(p_student) x
                         WHERE x.published
                           AND (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND x.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND x.session = p_session AND x.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND x.session = v_cur AND x.semester = coalesce(v_cur_sem, x.semester)))
                         GROUP BY x.session, x.semester) r
                  LEFT JOIN assessment.student_gpa(p_student) gp ON gp.session = r.session AND gp.semester = r.semester
                 GROUP BY r.session) q;
        SELECT coalesce(max(cgpa) FILTER (WHERE (session, semester) = (SELECT session, semester FROM assessment.student_gpa(p_student) ORDER BY session DESC, semester DESC LIMIT 1)), 0) INTO v_cgpa FROM assessment.student_gpa(p_student);
        IF g.cgpa IS NOT NULL THEN v_cgpa := g.cgpa; END IF;
        v_class := CASE WHEN g.student_id IS NOT NULL THEN coalesce(policy.class_of(g.cgpa), 'Pass') ELSE policy.class_of(v_cgpa) END;
        v_research := NULL;
    ELSE
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', r.units, 'gpa', admissions.pg_gpa(p_student, r.session, r.semester)) ORDER BY r.semester) AS semesters
                  -- V389: the old coursework's scores and the published results of the School's classes alike
                  FROM (SELECT x.session, x.semester, sum(x.units) FILTER (WHERE x.kind <> 'DEFICIENCY') AS units,
                               jsonb_agg(jsonb_build_object('code', x.code, 'title', x.title, 'units', x.units, 'grade', x.grade, 'points', x.points, 'quality', round(x.points * x.units, 2), 'type', x.kind) ORDER BY x.code) AS courses
                          FROM admissions.pg_course_results(p_student) x
                         WHERE (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND x.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND x.session = p_session AND x.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND x.session = v_cur))
                         GROUP BY x.session, x.semester) r
                 GROUP BY r.session) q;
        v_cgpa := coalesce(g.cgpa, admissions.pg_cgpa(p_student));
        v_class := CASE WHEN g.student_id IS NOT NULL THEN 'Awarded' ELSE NULL END;
        SELECT jsonb_build_object('kind', pr.degree_kind, 'topic', pr.topic, 'stage', pr.stage, 'vivaGrade', pr.viva_grade, 'awardedAt', pr.awarded_at) INTO v_research
          FROM admissions.pg_research pr WHERE pr.student_id = p_student;
    END IF;
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'holder', st.surname || ', ' || st.other_names,
        'matricNo', st.matric_no, 'admissionNo', st.admission_no,
        -- V668: the University's template names the date of birth, the sex and the session the holder left
        'dateOfBirth', st.date_of_birth, 'sex', CASE st.sex WHEN 'F' THEN 'Female' WHEN 'M' THEN 'Male' END,
        'leftSession', coalesce(g.session, CASE WHEN st.status = 'GRADUATED' THEN (SELECT max(x.session) FROM jsonb_to_recordset(coalesce(v_sessions, '[]'::jsonb)) x(session text)) END),
        'programme', st.programme, 'programmeCode', st.programme_code, 'department', st.department, 'faculty', st.faculty,
        -- V488: a postgraduate student's specialisation within the programme, where one is set
        'specialisation', (SELECT ps.name FROM people.student_specialisation ss
                             JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = st.programme_code
                            WHERE ss.student_id = p_student),
        'award', CASE WHEN g.student_id IS NOT NULL THEN coalesce(g.award, st.award_name) ELSE st.award_name END,
        'entryMode', st.entry_mode, 'entrySession', st.entry_session, 'entryLevel', st.entry_level, 'level', st.current_level, 'status', st.status,
        -- V381: the mode of study and the route, and for CCE the Centre and the programme's duration on it
        'studyMode', CASE st.study_mode WHEN 'PART_TIME' THEN 'Part-time' ELSE 'Full-time' END,
        'route', CASE WHEN st.entry_mode = 'CCE' THEN 'Centre for Continuing Education (CCE)' END,
        'centre', CASE WHEN st.entry_mode = 'CCE' THEN (SELECT u.name FROM policy.study_route r JOIN ref.unit u ON u.code = r.centre_unit WHERE r.code = 'CCE') END,
        'durationYears', CASE WHEN st.entry_mode = 'CCE' THEN (SELECT t.duration_years FROM ref.programme_route_terms(st.programme_code, 'CCE') t) END,
        'postgraduate', v_pg, 'scope', v_scope, 'session', p_session, 'semester', p_semester,
        'sessions', coalesce(v_sessions, '[]'::jsonb),
        'cgpa', v_cgpa, 'classOfDegree', v_class,
        'standing', CASE WHEN g.student_id IS NOT NULL THEN 'Graduated' WHEN st.status = 'GRADUATED' THEN 'Graduated' ELSE initcap(lower(replace(st.status, '_', ' '))) END,
        'graduationSession', g.session, 'graduationMinute', g.senate_minute,
        'graduationDate', CASE WHEN g.student_id IS NOT NULL THEN (SELECT ends_on FROM policy.academic_session WHERE name = g.session) END,
        'research', v_research,
        'gradingScale', (SELECT jsonb_agg(jsonb_build_object('grade', b.grade, 'low', b.low, 'high', b.high, 'points', b.points) ORDER BY b.points DESC)
                           FROM policy.grade_band b WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date)),
        'classificationBands', (SELECT jsonb_agg(jsonb_build_object('class', b.class, 'low', b.low, 'high', b.high) ORDER BY b.ord)
                                  FROM policy.classification_band b WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', current_date))
    ));
END $function$;

-- ── 8 · who may read and write ───────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON credentials.public_request, credentials.access_code, credentials.cover_letter TO app_credentials;
GRANT SELECT ON credentials.public_request, credentials.cover_letter TO app_auditor;

COMMIT;
