-- ═══════════════════════════════════════════════════════════════════════════
-- V252 — the helpdesk after review
--
--   The ticket number is drawn again on a collision: two submissions in the
--   same instant could both pass new_number()'s check and one would fail on
--   the UNIQUE index; the insert now retries in its own block. The year in the
--   number is Lagos's, not the server's. Reopening a ticket sets its resolution
--   aside (the RESOLUTION event keeps it) so a reopened ticket no longer reads
--   as resolved; reopening records a reason whoever asks. A desk name falls
--   back to 'The ICT desk' for an administrator with no person row. Each side
--   has its own ten attachments. The quiet-spell closer skips a ticket somebody
--   else holds and carries on past one that refuses. The application role may
--   no longer UPDATE the history or the file bytes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'helpdesk after review (V252)', true);

-- ── the year as Lagos counts it ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.new_number()
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text; i int := 0;
BEGIN
    LOOP
        v := 'TICK-' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '-' || (10000 + floor(random() * 90000))::int;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM helpdesk.ticket t WHERE t.number = v);
        i := i + 1;
        IF i > 50 THEN RAISE EXCEPTION 'no free ticket number found after 50 draws' USING ERRCODE = '23514'; END IF;
    END LOOP;
    RETURN v;
END $$;

-- ── a name for everyone who acts, even an administrator with no person row ──
CREATE OR REPLACE FUNCTION helpdesk.person_name(p_person uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = p_person),
                    CASE WHEN p_person IS NULL THEN NULL ELSE 'The ICT desk' END)
$$;

-- ── submission: the insert retried on a number collision ───────────────────
CREATE OR REPLACE FUNCTION helpdesk.submit(p_kind text, p_requester uuid, p_name text, p_number text, p_email text, p_phone text,
                                           p_dept text, p_faculty text, p_category text, p_subject text, p_description text, p_details jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE c helpdesk.category; f jsonb; v uuid := gen_random_uuid(); v_number text; n_open int; tries int := 0;
BEGIN
    SELECT * INTO c FROM helpdesk.category WHERE code = upper(btrim(p_category));
    IF NOT FOUND OR NOT c.active THEN
        RAISE EXCEPTION 'that category is not open for new tickets' USING ERRCODE = '23514', HINT = 'Choose one of the categories offered.';
    END IF;
    IF p_subject IS NULL OR btrim(p_subject) = '' THEN RAISE EXCEPTION 'a ticket has a subject' USING ERRCODE = '23514', HINT = 'Say what the problem is, in one line.'; END IF;
    IF p_description IS NULL OR btrim(p_description) = '' THEN RAISE EXCEPTION 'a ticket describes the problem' USING ERRCODE = '23514', HINT = 'Describe what happened and what you expected.'; END IF;
    IF p_email IS NULL OR btrim(p_email) = '' THEN RAISE EXCEPTION 'a ticket carries an email address the desk can reach' USING ERRCODE = '23514', HINT = 'Give an email address; the ticket''s updates and the public tracking page use it.'; END IF;
    FOR f IN SELECT * FROM jsonb_array_elements(c.fields) LOOP
        IF coalesce((f->>'required')::boolean, false) AND coalesce(f->>'type', 'text') <> 'file'
           AND btrim(coalesce(p_details->>(f->>'key'), '')) = '' THEN
            RAISE EXCEPTION '% is required for a % ticket', f->>'label', c.name USING ERRCODE = '23514', HINT = 'Fill it in and submit again.';
        END IF;
    END LOOP;
    SELECT count(*) INTO n_open FROM helpdesk.ticket WHERE requester_kind = p_kind AND requester_id = p_requester AND status <> 'CLOSED';
    IF n_open >= 10 THEN
        RAISE EXCEPTION 'ten tickets are open already' USING ERRCODE = '23514', HINT = 'Wait for an answer on one of them, or close one you no longer need, before raising another.';
    END IF;
    LOOP
        v_number := helpdesk.new_number();
        BEGIN
            INSERT INTO helpdesk.ticket (id, number, category_id, subject, description, priority, requester_kind, requester_id, requester_name, requester_number,
                                         requester_email, requester_phone, department_code, faculty_code, details)
            VALUES (v, v_number, c.id, btrim(p_subject), btrim(p_description), c.suggested_priority, p_kind, p_requester, p_name, nullif(btrim(coalesce(p_number, '')), ''),
                    lower(btrim(p_email)), nullif(btrim(coalesce(p_phone, '')), ''), p_dept, p_faculty, coalesce(p_details, '{}'::jsonb));
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            tries := tries + 1;
            IF tries >= 10 THEN RAISE; END IF;
        END;
    END LOOP;
    PERFORM helpdesk.record(v, 'REQUESTER', p_requester, p_name, 'SUBMITTED', NULL, 'SUBMITTED', c.name || ' · ' || btrim(p_subject));
    RETURN v;
END $$;

-- ── the transitions: a reason to reopen, whoever asks; the resolution set aside on reopening ──
CREATE OR REPLACE FUNCTION helpdesk.transition(p_ticket uuid, p_to text, p_actor_kind text, p_actor uuid, p_actor_name text, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; v_from text; ok boolean := false; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    v_from := t.status;
    IF p_to = v_from THEN RAISE EXCEPTION 'the ticket is already %', lower(replace(p_to, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF p_actor_kind = 'AGENT' THEN
        ok := (v_from, p_to) IN (('SUBMITTED','OPENED'), ('OPENED','IN_PROGRESS'), ('REOPENED','IN_PROGRESS'), ('RESOLVED','CLOSED'))
              OR (p_to = 'REOPENED' AND v_from IN ('RESOLVED','CLOSED'))
              OR (p_to = 'CLOSED' AND v_from <> 'CLOSED');
        IF p_to = 'CLOSED' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'a closure by the desk records its reason' USING ERRCODE = '23514', HINT = 'Say why the ticket is closed.';
        END IF;
    ELSIF p_actor_kind = 'REQUESTER' THEN
        ok := (v_from = 'RESOLVED' AND p_to IN ('CLOSED','REOPENED'))
              OR (p_to = 'CLOSED' AND v_from IN ('SUBMITTED','OPENED','IN_PROGRESS','REOPENED'));
    ELSIF p_actor_kind = 'SYSTEM' THEN
        ok := (v_from = 'RESOLVED' AND p_to = 'CLOSED');
    END IF;
    IF p_to = 'REOPENED' AND v_reason IS NULL THEN
        RAISE EXCEPTION 'reopening a ticket says what is still wrong' USING ERRCODE = '23514', HINT = 'Say why the ticket is reopened, in a line.';
    END IF;
    IF NOT ok THEN
        RAISE EXCEPTION 'a ticket does not go from % to % this way', lower(replace(v_from, '_', ' ')), lower(replace(p_to, '_', ' '))
            USING ERRCODE = '23514', HINT = 'The ticket moves submitted → opened → in progress → resolved → closed; a resolved or closed ticket is reopened on a reason.';
    END IF;
    UPDATE helpdesk.ticket SET
        status = p_to,
        opened_at = CASE WHEN p_to IN ('OPENED','REOPENED') AND opened_at IS NULL THEN now() ELSE opened_at END,
        opened_by = CASE WHEN p_to IN ('OPENED','REOPENED') AND opened_by IS NULL THEN p_actor ELSE opened_by END,
        in_progress_at = CASE WHEN p_to = 'IN_PROGRESS' THEN now() ELSE in_progress_at END,
        first_response_at = CASE WHEN p_to = 'IN_PROGRESS' AND first_response_at IS NULL AND p_actor_kind = 'AGENT' THEN now() ELSE first_response_at END,
        resolved_at = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolved_at END,
        resolved_by = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolved_by END,
        resolution_summary = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolution_summary END,
        resolution_details = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolution_details END,
        closed_at = CASE WHEN p_to = 'CLOSED' THEN now() ELSE NULL END,
        closed_by = CASE WHEN p_to = 'CLOSED' THEN p_actor ELSE NULL END,
        closed_by_kind = CASE WHEN p_to = 'CLOSED' THEN p_actor_kind ELSE NULL END,
        closure_reason = CASE WHEN p_to = 'CLOSED' THEN coalesce(v_reason, CASE WHEN p_actor_kind = 'REQUESTER' AND v_from = 'RESOLVED' THEN 'The requester confirmed the resolution' WHEN p_actor_kind = 'REQUESTER' THEN 'Withdrawn by the requester' ELSE NULL END) ELSE NULL END,
        reopen_count = CASE WHEN p_to = 'REOPENED' THEN reopen_count + 1 ELSE reopen_count END
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, p_actor_kind, p_actor, p_actor_name,
        CASE WHEN p_to = 'OPENED' THEN 'OPENED' WHEN p_to = 'REOPENED' THEN 'REOPENED' WHEN p_to = 'CLOSED' THEN 'CLOSED' ELSE 'STATUS_CHANGED' END,
        v_from, p_to,
        coalesce(v_reason, CASE WHEN p_to = 'CLOSED' AND p_actor_kind = 'REQUESTER' AND v_from = 'RESOLVED' THEN 'The requester confirmed the resolution'
                                WHEN p_to = 'CLOSED' AND p_actor_kind = 'REQUESTER' THEN 'Withdrawn by the requester' END));
END $$;

-- ── each side has its own ten files ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.attach(p_ticket uuid, p_comment uuid, p_kind text, p_by uuid, p_by_name text,
                                           p_filename text, p_type text, p_bytes bigint, p_content bytea, p_internal boolean)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; v uuid := gen_random_uuid(); n int;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF p_kind = 'REQUESTER' AND t.status = 'CLOSED' THEN
        RAISE EXCEPTION 'a closed ticket takes no more attachments' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO n FROM helpdesk.ticket_attachment WHERE ticket_id = p_ticket AND uploaded_kind = p_kind;
    IF n >= 10 THEN RAISE EXCEPTION 'ten attachments are on the ticket already' USING ERRCODE = '23514', HINT = 'Put further evidence in an update, or combine the files.'; END IF;
    INSERT INTO helpdesk.ticket_attachment (id, ticket_id, comment_id, uploaded_kind, uploaded_by, uploader_name, filename, content_type, bytes, internal)
    VALUES (v, p_ticket, p_comment, p_kind, p_by, p_by_name, btrim(p_filename), p_type, p_bytes, coalesce(p_internal, false) AND p_kind = 'AGENT');
    INSERT INTO helpdesk.ticket_attachment_blob (attachment_id, content) VALUES (v, p_content);
    PERFORM helpdesk.record(p_ticket, p_kind, p_by, p_by_name, 'ATTACHMENT', NULL, NULL, btrim(p_filename), coalesce(p_internal, false) AND p_kind = 'AGENT');
    RETURN v;
END $$;

-- ── the quiet spell: skip what somebody holds, carry on past a refusal ───────
CREATE OR REPLACE FUNCTION helpdesk.auto_close()
RETURNS SETOF uuid
LANGUAGE plpgsql AS $$
DECLARE d int; t record;
BEGIN
    SELECT auto_close_days INTO d FROM helpdesk.setting WHERE row_no;
    IF d IS NULL THEN RETURN; END IF;
    FOR t IN SELECT id FROM helpdesk.ticket WHERE status = 'RESOLVED' AND resolved_at < now() - make_interval(days => d)
              ORDER BY resolved_at LIMIT 200 FOR UPDATE SKIP LOCKED LOOP
        BEGIN
            PERFORM helpdesk.transition(t.id, 'CLOSED', 'SYSTEM', NULL, 'The portal',
                'Closed automatically: ' || d || ' day' || CASE WHEN d = 1 THEN '' ELSE 's' END || ' passed after the resolution with no reply from the requester');
            RETURN NEXT t.id;
        EXCEPTION WHEN check_violation THEN
            NULL;
        END;
    END LOOP;
    RETURN;
END $$;

-- ── the history and the bytes are written once by the application too ──────
REVOKE UPDATE ON helpdesk.ticket_event, helpdesk.ticket_attachment_blob FROM app_platform;

COMMIT;
