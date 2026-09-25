-- ═══════════════════════════════════════════════════════════════════════════
-- V251 — ICT support tickets: the helpdesk
--
--   A student or a member of staff reports a problem to the Directorate of
--   ICT — a payment that did not register, a login that fails, a course that
--   will not register, a result, the portal, email, an account, the network —
--   and receives a tracking number at once. The ticket carries what the
--   category asks for (a payment reference, a course code, an error), the
--   requester's contact as the account knows it, and its evidence. It moves
--   SUBMITTED → OPENED (the first agent to read it) → IN_PROGRESS → RESOLVED
--   (with a resolution on the record) → CLOSED (the requester confirms, an
--   agent closes on a reason, or the portal closes it after the configured
--   quiet spell); a requester who is not satisfied reopens it on a reason.
--   Agents keep internal notes the requester never sees, alongside the
--   updates the requester does. Every act is on the ticket's own history,
--   written once, and on the audit spine besides. The Director of ICT sees
--   everything, appoints agents, keeps the categories and the SLAs.
--
--   Help & requests (V036) stays as it is: a student's one-line ask to any
--   of eight offices. This is the ICT desk's own system, with agents,
--   assignment, escalation and a tracking number the public page can look up.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'ICT support tickets (V251)', true);

-- ── the office: an ICT Support Agent, appointed by the Director of ICT ──────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('ictagent', 'ICT Support Agent', 'platform')
ON CONFLICT (code) DO NOTHING;

CREATE SCHEMA IF NOT EXISTS helpdesk;
COMMENT ON SCHEMA helpdesk IS 'ICT support tickets (V251): what students and staff report to the Directorate of ICT, and what the desk did about it.';

-- ── the categories, each with the fields it asks for ─────────────────────────
CREATE TABLE helpdesk.category (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code               text NOT NULL UNIQUE,
    name               text NOT NULL,
    description        text NULL,
    active             boolean NOT NULL DEFAULT true,
    ordinal            int NOT NULL DEFAULT 100,
    suggested_priority text NOT NULL DEFAULT 'NORMAL',
    fields             jsonb NOT NULL DEFAULT '[]'::jsonb,
    attachment_hint    text NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_category_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,30}$'),
    CONSTRAINT ck_hd_category_name CHECK (btrim(name) <> ''),
    CONSTRAINT ck_hd_category_priority CHECK (suggested_priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT ck_hd_category_fields CHECK (jsonb_typeof(fields) = 'array')
);
SELECT audit.attach('helpdesk.category');
COMMENT ON COLUMN helpdesk.category.fields IS
  'What the category asks beyond subject and description: [{key, label, type (text|date|number|select|session|semester|level), required, options, hint}]. A category is deactivated, never deleted, so its tickets keep their category.';

-- ── the SLA by priority, and the desk''s settings ─────────────────────────────
CREATE TABLE helpdesk.sla (
    priority             text PRIMARY KEY,
    first_response_hours int NOT NULL,
    resolution_hours     int NOT NULL,
    CONSTRAINT ck_hd_sla_priority CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT ck_hd_sla_hours CHECK (first_response_hours > 0 AND resolution_hours >= first_response_hours)
);
SELECT audit.attach('helpdesk.sla');
INSERT INTO helpdesk.sla (priority, first_response_hours, resolution_hours) VALUES
    ('LOW', 72, 240), ('NORMAL', 24, 120), ('HIGH', 8, 48), ('URGENT', 2, 24);

CREATE TABLE helpdesk.setting (
    row_no               boolean PRIMARY KEY DEFAULT true,
    auto_close_days      int NULL,
    notify_agents_on_new boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_hd_setting_one CHECK (row_no),
    CONSTRAINT ck_hd_setting_days CHECK (auto_close_days IS NULL OR auto_close_days BETWEEN 1 AND 90)
);
SELECT audit.attach('helpdesk.setting');
INSERT INTO helpdesk.setting (row_no, auto_close_days, notify_agents_on_new) VALUES (true, NULL, true);
COMMENT ON COLUMN helpdesk.setting.auto_close_days IS 'A resolved ticket the requester has not answered closes itself after this many days; NULL, the default, means it never does.';

-- ── the ticket ─────────────────────────────────────────────────────────────
CREATE TABLE helpdesk.ticket (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    number              text NOT NULL UNIQUE,
    category_id         uuid NOT NULL REFERENCES helpdesk.category(id),
    subject             text NOT NULL,
    description         text NOT NULL,
    priority            text NOT NULL DEFAULT 'NORMAL',
    status              text NOT NULL DEFAULT 'SUBMITTED',
    requester_kind      text NOT NULL,
    requester_id        uuid NOT NULL,
    requester_name      text NOT NULL,
    requester_number    text NULL,
    requester_email     text NULL,
    requester_phone     text NULL,
    department_code     text NULL,
    faculty_code        text NULL,
    details             jsonb NOT NULL DEFAULT '{}'::jsonb,
    assigned_to         uuid NULL REFERENCES iam.person(id),
    assigned_by         uuid NULL,
    assigned_at         timestamptz NULL,
    escalated_to        uuid NULL REFERENCES iam.person(id),
    escalated_by        uuid NULL,
    escalated_at        timestamptz NULL,
    escalation_reason   text NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    opened_at           timestamptz NULL,
    opened_by           uuid NULL,
    first_response_at   timestamptz NULL,
    in_progress_at      timestamptz NULL,
    resolved_at         timestamptz NULL,
    resolved_by         uuid NULL,
    resolution_summary  text NULL,
    resolution_details  text NULL,
    closed_at           timestamptz NULL,
    closed_by           uuid NULL,
    closed_by_kind      text NULL,
    closure_reason      text NULL,
    reopen_count        int NOT NULL DEFAULT 0,
    CONSTRAINT ck_hd_ticket_number CHECK (number ~ '^TICK-[0-9]{4}-[0-9]{5}$'),
    CONSTRAINT ck_hd_ticket_subject CHECK (btrim(subject) <> '' AND length(subject) <= 200),
    CONSTRAINT ck_hd_ticket_description CHECK (btrim(description) <> ''),
    CONSTRAINT ck_hd_ticket_priority CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    CONSTRAINT ck_hd_ticket_status CHECK (status IN ('SUBMITTED','OPENED','IN_PROGRESS','RESOLVED','CLOSED','REOPENED')),
    CONSTRAINT ck_hd_ticket_requester CHECK (requester_kind IN ('STUDENT','STAFF')),
    CONSTRAINT ck_hd_ticket_email CHECK (requester_email IS NULL OR requester_email ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$'),
    CONSTRAINT ck_hd_ticket_details CHECK (jsonb_typeof(details) = 'object'),
    CONSTRAINT ck_hd_ticket_resolved CHECK (status <> 'RESOLVED' OR (resolved_at IS NOT NULL AND btrim(coalesce(resolution_summary, '')) <> '' AND btrim(coalesce(resolution_details, '')) <> '')),
    CONSTRAINT ck_hd_ticket_closed CHECK (status <> 'CLOSED' OR (closed_at IS NOT NULL AND closed_by_kind IN ('REQUESTER','AGENT','SYSTEM'))),
    CONSTRAINT ck_hd_ticket_opened CHECK (status = 'SUBMITTED' OR opened_at IS NOT NULL OR status = 'CLOSED')
);
CREATE INDEX ix_hd_ticket_status ON helpdesk.ticket (status, created_at DESC);
CREATE INDEX ix_hd_ticket_requester ON helpdesk.ticket (requester_kind, requester_id, created_at DESC);
CREATE INDEX ix_hd_ticket_agent ON helpdesk.ticket (assigned_to, status);
CREATE INDEX ix_hd_ticket_category ON helpdesk.ticket (category_id);
CREATE INDEX ix_hd_ticket_email ON helpdesk.ticket (lower(requester_email));
SELECT audit.attach('helpdesk.ticket');
COMMENT ON TABLE helpdesk.ticket IS
  'One report to the ICT desk. The number is what the requester quotes and the public page looks up; the id is the key. The requester''s contact and unit are copied in at submission, so the ticket reads as it was raised.';

-- ── what was said: the requester''s updates, the agents'' updates and their internal notes ──
CREATE TABLE helpdesk.ticket_comment (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id   uuid NOT NULL REFERENCES helpdesk.ticket(id),
    author_kind text NOT NULL,
    author_id   uuid NULL,
    author_name text NOT NULL,
    internal    boolean NOT NULL DEFAULT false,
    body        text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_comment_kind CHECK (author_kind IN ('REQUESTER','AGENT','SYSTEM')),
    CONSTRAINT ck_hd_comment_body CHECK (btrim(body) <> '' AND length(body) <= 8000),
    CONSTRAINT ck_hd_comment_internal CHECK (NOT internal OR author_kind = 'AGENT')
);
CREATE INDEX ix_hd_comment_ticket ON helpdesk.ticket_comment (ticket_id, created_at);
SELECT audit.attach('helpdesk.ticket_comment');

-- ── the evidence: PDF, JPEG or PNG, at most 5 MB, at most ten a ticket ──────
CREATE TABLE helpdesk.ticket_attachment (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id     uuid NOT NULL REFERENCES helpdesk.ticket(id),
    comment_id    uuid NULL REFERENCES helpdesk.ticket_comment(id),
    uploaded_kind text NOT NULL,
    uploaded_by   uuid NULL,
    uploader_name text NOT NULL,
    filename      text NOT NULL,
    content_type  text NOT NULL,
    bytes         bigint NOT NULL,
    internal      boolean NOT NULL DEFAULT false,
    uploaded_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_attachment_kind CHECK (uploaded_kind IN ('REQUESTER','AGENT')),
    CONSTRAINT ck_hd_attachment_name CHECK (btrim(filename) <> '' AND length(filename) <= 200),
    CONSTRAINT ck_hd_attachment_type CHECK (content_type IN ('application/pdf','image/jpeg','image/png')),
    CONSTRAINT ck_hd_attachment_size CHECK (bytes BETWEEN 1 AND 5242880),
    CONSTRAINT ck_hd_attachment_internal CHECK (NOT internal OR uploaded_kind = 'AGENT')
);
CREATE INDEX ix_hd_attachment_ticket ON helpdesk.ticket_attachment (ticket_id, uploaded_at);
SELECT audit.attach('helpdesk.ticket_attachment');

CREATE TABLE helpdesk.ticket_attachment_blob (
    attachment_id uuid PRIMARY KEY REFERENCES helpdesk.ticket_attachment(id),
    content       bytea NOT NULL
);
SELECT audit.exempt('helpdesk.ticket_attachment_blob',
  'The bytes of a ticket attachment. The attachment row, on the spine, records who put it there and when; the bytes themselves are not a change worth chaining.');

-- ── the history: every act on the ticket, written once ──────────────────────
CREATE TABLE helpdesk.ticket_event (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id  uuid NOT NULL REFERENCES helpdesk.ticket(id),
    at         timestamptz NOT NULL DEFAULT now(),
    actor_kind text NOT NULL,
    actor_id   uuid NULL,
    actor_name text NOT NULL,
    action     text NOT NULL,
    from_value text NULL,
    to_value   text NULL,
    detail     text NULL,
    internal   boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_hd_event_kind CHECK (actor_kind IN ('REQUESTER','AGENT','SYSTEM')),
    CONSTRAINT ck_hd_event_action CHECK (action IN ('SUBMITTED','OPENED','STATUS_CHANGED','ASSIGNED','REASSIGNED','ESCALATED','PRIORITY_CHANGED',
                                                    'INTERNAL_NOTE','UPDATE','RESOLUTION','REOPENED','CLOSED','ATTACHMENT'))
);
CREATE INDEX ix_hd_event_ticket ON helpdesk.ticket_event (ticket_id, at);
SELECT audit.attach('helpdesk.ticket_event');
COMMENT ON TABLE helpdesk.ticket_event IS
  'The ticket''s timeline. Written once: an update or delete is refused unless the session is in maintenance (db/check.sql''s cleanup), which the application never sets.';

CREATE OR REPLACE FUNCTION helpdesk.history_is_written_once()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'the ticket history is written once; nothing on it is changed or removed'
        USING ERRCODE = '23514', HINT = 'Add a new note or event instead.';
END $$;
CREATE TRIGGER trg_hd_event_written_once BEFORE UPDATE OR DELETE ON helpdesk.ticket_event
    FOR EACH ROW EXECUTE FUNCTION helpdesk.history_is_written_once();

-- ── who may act for the desk ─────────────────────────────────────────────────
-- an agent is a person who holds the ICT Support Agent office or the Director's, today
CREATE OR REPLACE FUNCTION helpdesk.is_agent(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.office_assignment a
                    WHERE a.person_id = p_person AND a.office_code IN ('ictagent','ict','admin','super')
                      AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
$$;

CREATE OR REPLACE FUNCTION helpdesk.person_name(p_person uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = p_person
$$;

-- ── the number: TICK-YYYY-NNNNN, the five digits drawn at random, never reused ──
CREATE OR REPLACE FUNCTION helpdesk.new_number()
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text; i int := 0;
BEGIN
    LOOP
        v := 'TICK-' || to_char(current_date, 'YYYY') || '-' || (10000 + floor(random() * 90000))::int;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM helpdesk.ticket t WHERE t.number = v);
        i := i + 1;
        IF i > 50 THEN RAISE EXCEPTION 'no free ticket number found after 50 draws' USING ERRCODE = '23514'; END IF;
    END LOOP;
    RETURN v;
END $$;

-- ── the history, and the ticket''s updated_at, in one call ───────────────────
CREATE OR REPLACE FUNCTION helpdesk.record(p_ticket uuid, p_actor_kind text, p_actor_id uuid, p_actor_name text, p_action text,
                                           p_from text, p_to text, p_detail text, p_internal boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    INSERT INTO helpdesk.ticket_event (id, ticket_id, actor_kind, actor_id, actor_name, action, from_value, to_value, detail, internal)
    VALUES (v, p_ticket, p_actor_kind, p_actor_id, p_actor_name, p_action, p_from, p_to, nullif(btrim(coalesce(p_detail, '')), ''), coalesce(p_internal, false));
    UPDATE helpdesk.ticket SET updated_at = now() WHERE id = p_ticket;
    RETURN v;
END $$;

-- ── submission ───────────────────────────────────────────────────────────────
-- the category must be active; every field it marks required must be filled; the priority is the category's suggestion
CREATE OR REPLACE FUNCTION helpdesk.submit(p_kind text, p_requester uuid, p_name text, p_number text, p_email text, p_phone text,
                                           p_dept text, p_faculty text, p_category text, p_subject text, p_description text, p_details jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE c helpdesk.category; f jsonb; v uuid := gen_random_uuid(); v_number text; n_open int;
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
    v_number := helpdesk.new_number();
    INSERT INTO helpdesk.ticket (id, number, category_id, subject, description, priority, requester_kind, requester_id, requester_name, requester_number,
                                 requester_email, requester_phone, department_code, faculty_code, details)
    VALUES (v, v_number, c.id, btrim(p_subject), btrim(p_description), c.suggested_priority, p_kind, p_requester, p_name, nullif(btrim(coalesce(p_number, '')), ''),
            lower(btrim(p_email)), nullif(btrim(coalesce(p_phone, '')), ''), p_dept, p_faculty, coalesce(p_details, '{}'::jsonb));
    PERFORM helpdesk.record(v, 'REQUESTER', p_requester, p_name, 'SUBMITTED', NULL, 'SUBMITTED', c.name || ' · ' || btrim(p_subject));
    RETURN v;
END $$;

-- ── the first agent to read a submitted ticket opens it ─────────────────────
CREATE OR REPLACE FUNCTION helpdesk.open_ticket(p_ticket uuid, p_agent uuid)
RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status <> 'SUBMITTED' THEN RETURN false; END IF;
    UPDATE helpdesk.ticket SET status = 'OPENED', opened_at = now(), opened_by = p_agent WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_agent, helpdesk.person_name(p_agent), 'OPENED', 'SUBMITTED', 'OPENED', 'Opened by the ICT desk');
    RETURN true;
END $$;

-- ── the transitions, by who asks ─────────────────────────────────────────────
--   AGENT:     SUBMITTED→OPENED, OPENED→IN_PROGRESS, REOPENED→IN_PROGRESS, RESOLVED→CLOSED, RESOLVED→REOPENED (reason),
--              CLOSED→REOPENED (reason), any open status→CLOSED on a reason (the administrative closure)
--   REQUESTER: RESOLVED→CLOSED (confirmation), RESOLVED→REOPENED (reason), SUBMITTED/OPENED/IN_PROGRESS/REOPENED→CLOSED (withdrawn)
--   SYSTEM:    RESOLVED→CLOSED (the configured quiet spell)
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
        IF p_to IN ('REOPENED', 'CLOSED') AND v_from <> 'RESOLVED' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'a reason is recorded when a ticket is % by the desk', lower(p_to) USING ERRCODE = '23514', HINT = 'Say why, in a line.';
        END IF;
        IF p_to = 'CLOSED' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'a closure by the desk records its reason' USING ERRCODE = '23514', HINT = 'Say why the ticket is closed.';
        END IF;
    ELSIF p_actor_kind = 'REQUESTER' THEN
        ok := (v_from = 'RESOLVED' AND p_to IN ('CLOSED','REOPENED'))
              OR (p_to = 'CLOSED' AND v_from IN ('SUBMITTED','OPENED','IN_PROGRESS','REOPENED'));
        IF p_to = 'REOPENED' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'reopening a ticket says what is still wrong' USING ERRCODE = '23514', HINT = 'Tell the desk why the resolution did not settle it.';
        END IF;
    ELSIF p_actor_kind = 'SYSTEM' THEN
        ok := (v_from = 'RESOLVED' AND p_to = 'CLOSED');
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

-- ── resolution: a summary and the details, from in progress ─────────────────
CREATE OR REPLACE FUNCTION helpdesk.resolve(p_ticket uuid, p_agent uuid, p_summary text, p_details text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION 'a ticket is resolved from in progress; this one is %', lower(replace(t.status, '_', ' ')) USING ERRCODE = '23514', HINT = 'Start work on it first.';
    END IF;
    IF length(btrim(coalesce(p_summary, ''))) < 5 OR length(btrim(coalesce(p_details, ''))) < 20 THEN
        RAISE EXCEPTION 'a resolution says what was done' USING ERRCODE = '23514', HINT = 'Give a one-line summary and the details of what was found and changed.';
    END IF;
    UPDATE helpdesk.ticket SET status = 'RESOLVED', resolved_at = now(), resolved_by = p_agent,
           resolution_summary = btrim(p_summary), resolution_details = btrim(p_details),
           first_response_at = coalesce(first_response_at, now())
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_agent, helpdesk.person_name(p_agent), 'RESOLUTION', 'IN_PROGRESS', 'RESOLVED', btrim(p_summary));
END $$;

-- ── assignment: to an agent, by an agent; a reassignment says so ─────────────
CREATE OR REPLACE FUNCTION helpdesk.assign(p_ticket uuid, p_agent uuid, p_by uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status = 'CLOSED' THEN RAISE EXCEPTION 'a closed ticket is not assigned' USING ERRCODE = '23514', HINT = 'Reopen it first.'; END IF;
    IF NOT helpdesk.is_agent(p_agent) THEN
        RAISE EXCEPTION 'only an ICT Support Agent or the Director of ICT takes a ticket' USING ERRCODE = '23514', HINT = 'Appoint the person to the ICT Support Agent office first.';
    END IF;
    IF t.assigned_to = p_agent THEN RAISE EXCEPTION 'the ticket is with that agent already' USING ERRCODE = '23514'; END IF;
    UPDATE helpdesk.ticket SET assigned_to = p_agent, assigned_by = p_by, assigned_at = now() WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_by, helpdesk.person_name(p_by), CASE WHEN t.assigned_to IS NULL THEN 'ASSIGNED' ELSE 'REASSIGNED' END,
        CASE WHEN t.assigned_to IS NULL THEN NULL ELSE helpdesk.person_name(t.assigned_to) END, helpdesk.person_name(p_agent), p_reason);
END $$;

-- ── escalation: to a senior agent or the Director, on a reason ──────────────
CREATE OR REPLACE FUNCTION helpdesk.escalate(p_ticket uuid, p_to uuid, p_by uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status = 'CLOSED' THEN RAISE EXCEPTION 'a closed ticket is not escalated' USING ERRCODE = '23514', HINT = 'Reopen it first.'; END IF;
    IF NOT helpdesk.is_agent(p_to) THEN
        RAISE EXCEPTION 'a ticket is escalated to an ICT Support Agent or the Director of ICT' USING ERRCODE = '23514';
    END IF;
    IF p_to = p_by THEN RAISE EXCEPTION 'a ticket is escalated to someone else' USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'an escalation says why' USING ERRCODE = '23514', HINT = 'Give the reason in a line.'; END IF;
    UPDATE helpdesk.ticket SET escalated_to = p_to, escalated_by = p_by, escalated_at = now(), escalation_reason = btrim(p_reason) WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_by, helpdesk.person_name(p_by), 'ESCALATED', helpdesk.person_name(p_by), helpdesk.person_name(p_to), btrim(p_reason));
END $$;

-- ── priority, by the desk ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.set_priority(p_ticket uuid, p_priority text, p_by uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.priority = p_priority THEN RETURN; END IF;
    UPDATE helpdesk.ticket SET priority = p_priority WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_by, helpdesk.person_name(p_by), 'PRIORITY_CHANGED', t.priority, p_priority, NULL);
END $$;

-- ── a comment: the requester's update, the agent's update, or the agent's internal note ──
CREATE OR REPLACE FUNCTION helpdesk.comment(p_ticket uuid, p_kind text, p_author uuid, p_author_name text, p_internal boolean, p_body text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; v uuid := gen_random_uuid();
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF p_kind = 'REQUESTER' AND t.status = 'CLOSED' THEN
        RAISE EXCEPTION 'a closed ticket takes no more updates' USING ERRCODE = '23514', HINT = 'Raise a new ticket, quoting this one''s number.';
    END IF;
    IF btrim(coalesce(p_body, '')) = '' THEN RAISE EXCEPTION 'an update says something' USING ERRCODE = '23514'; END IF;
    INSERT INTO helpdesk.ticket_comment (id, ticket_id, author_kind, author_id, author_name, internal, body)
    VALUES (v, p_ticket, p_kind, p_author, p_author_name, coalesce(p_internal, false) AND p_kind = 'AGENT', btrim(p_body));
    IF p_kind = 'AGENT' AND NOT coalesce(p_internal, false) AND t.first_response_at IS NULL THEN
        UPDATE helpdesk.ticket SET first_response_at = now() WHERE id = p_ticket;
    END IF;
    PERFORM helpdesk.record(p_ticket, p_kind, p_author, p_author_name,
        CASE WHEN p_kind = 'AGENT' AND coalesce(p_internal, false) THEN 'INTERNAL_NOTE' ELSE 'UPDATE' END,
        NULL, NULL, left(btrim(p_body), 200), p_kind = 'AGENT' AND coalesce(p_internal, false));
    RETURN v;
END $$;

-- ── an attachment: the bytes kept apart from the record of them ──────────────
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
    SELECT count(*) INTO n FROM helpdesk.ticket_attachment WHERE ticket_id = p_ticket;
    IF n >= 10 THEN RAISE EXCEPTION 'ten attachments are on the ticket already' USING ERRCODE = '23514', HINT = 'Put further evidence in an update, or combine the files.'; END IF;
    INSERT INTO helpdesk.ticket_attachment (id, ticket_id, comment_id, uploaded_kind, uploaded_by, uploader_name, filename, content_type, bytes, internal)
    VALUES (v, p_ticket, p_comment, p_kind, p_by, p_by_name, btrim(p_filename), p_type, p_bytes, coalesce(p_internal, false) AND p_kind = 'AGENT');
    INSERT INTO helpdesk.ticket_attachment_blob (attachment_id, content) VALUES (v, p_content);
    PERFORM helpdesk.record(p_ticket, p_kind, p_by, p_by_name, 'ATTACHMENT', NULL, NULL, btrim(p_filename), coalesce(p_internal, false) AND p_kind = 'AGENT');
    RETURN v;
END $$;

-- ── the SLA read against a ticket ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.due_at(p_created timestamptz, p_priority text)
RETURNS timestamptz
LANGUAGE sql STABLE AS $$
    SELECT p_created + make_interval(hours => s.resolution_hours) FROM helpdesk.sla s WHERE s.priority = p_priority
$$;

CREATE OR REPLACE FUNCTION helpdesk.response_due_at(p_created timestamptz, p_priority text)
RETURNS timestamptz
LANGUAGE sql STABLE AS $$
    SELECT p_created + make_interval(hours => s.first_response_hours) FROM helpdesk.sla s WHERE s.priority = p_priority
$$;

-- ── the configured quiet spell: resolved tickets nobody answered close themselves ──
CREATE OR REPLACE FUNCTION helpdesk.auto_close()
RETURNS SETOF uuid
LANGUAGE plpgsql AS $$
DECLARE d int; t record;
BEGIN
    SELECT auto_close_days INTO d FROM helpdesk.setting WHERE row_no;
    IF d IS NULL THEN RETURN; END IF;
    FOR t IN SELECT id FROM helpdesk.ticket WHERE status = 'RESOLVED' AND resolved_at < now() - make_interval(days => d) ORDER BY resolved_at LIMIT 200 LOOP
        PERFORM helpdesk.transition(t.id, 'CLOSED', 'SYSTEM', NULL, 'The portal', 'Closed automatically: ' || d || ' day' || CASE WHEN d = 1 THEN '' ELSE 's' END || ' passed after the resolution with no reply from the requester');
        RETURN NEXT t.id;
    END LOOP;
    RETURN;
END $$;

-- ── the categories, with what each asks for ──────────────────────────────────
INSERT INTO helpdesk.category (code, name, description, ordinal, suggested_priority, attachment_hint, fields) VALUES
('PAYMENT', 'Payment Issues', 'A payment that did not register, a receipt that will not print, a wrong amount.', 10, 'HIGH', 'The receipt or other evidence of payment', '[
  {"key":"payment_reference","label":"Payment reference number","type":"text","required":true,"hint":"As printed on the receipt or the bank alert"},
  {"key":"payment_date","label":"Payment date","type":"date","required":true},
  {"key":"payment_type","label":"Payment type","type":"select","required":true,"options":["School fees","Acceptance fee","Hostel fee","Application fee","Other"]},
  {"key":"amount","label":"Amount (naira)","type":"number","required":true}
]'),
('LOGIN', 'Login Issues', 'You cannot sign in, or the portal refuses your password.', 20, 'HIGH', 'A screenshot of the error', '[
  {"key":"account_type","label":"Account type","type":"select","required":true,"options":["Student portal","Staff portal","Applicant portal","University email"]},
  {"key":"username","label":"Username, matriculation number or staff number","type":"text","required":true},
  {"key":"error","label":"What the portal says","type":"text","required":true,"hint":"The message shown, word for word"},
  {"key":"started_on","label":"When the problem started","type":"date","required":false}
]'),
('REGISTRATION', 'Course Registration', 'A course that will not register, a missing course, a wrong level or semester.', 30, 'NORMAL', 'A screenshot or other evidence', '[
  {"key":"session","label":"Academic session","type":"session","required":true},
  {"key":"semester","label":"Semester","type":"semester","required":true},
  {"key":"programme","label":"Programme","type":"text","required":false},
  {"key":"level","label":"Level","type":"level","required":true},
  {"key":"course_code","label":"Course code","type":"text","required":false,"hint":"e.g. CSC 201"},
  {"key":"course_title","label":"Course title","type":"text","required":false}
]'),
('RESULTS', 'Results', 'A result missing, a wrong grade or score, a carry-over shown wrongly.', 40, 'NORMAL', 'A supporting document', '[
  {"key":"session","label":"Academic session","type":"session","required":true},
  {"key":"semester","label":"Semester","type":"semester","required":true},
  {"key":"course_code","label":"Course code","type":"text","required":true},
  {"key":"result_type","label":"What is wrong","type":"select","required":true,"options":["Result missing","Wrong grade","Wrong score","Carry-over shown wrongly","Other"]}
]'),
('EXAMINATIONS', 'Examinations', 'A docket, a timetable clash, a computer-based test that would not run.', 50, 'HIGH', 'A screenshot or the docket', '[
  {"key":"session","label":"Academic session","type":"session","required":true},
  {"key":"semester","label":"Semester","type":"semester","required":true},
  {"key":"course_code","label":"Course code","type":"text","required":false},
  {"key":"exam_issue","label":"What went wrong","type":"select","required":true,"options":["Docket problem","Timetable clash","Not on the examination list","CBT problem","Other"]}
]'),
('PORTAL', 'Portal Issues', 'A page that fails, a button that does nothing, a figure that is wrong.', 60, 'NORMAL', 'A screenshot of the page', '[
  {"key":"portal_section","label":"Portal section","type":"select","required":true,"options":["Dashboard","Course registration","Results","Fees and payments","Hostel","Library","Profile and biodata","Staff desk","Other"]},
  {"key":"page","label":"Page or module","type":"text","required":false,"hint":"The page title or its address"},
  {"key":"error","label":"What the portal says","type":"text","required":true}
]'),
('EMAIL', 'Email Issues', 'Your university mailbox: access, password, delivery.', 70, 'NORMAL', 'A screenshot of the error', '[
  {"key":"email_address","label":"Email address","type":"text","required":true},
  {"key":"error","label":"What goes wrong","type":"text","required":true}
]'),
('ACCOUNT', 'Account Issues', 'Your account: a wrong name, a locked account, a number that is not yours.', 80, 'NORMAL', 'Evidence, where it helps', '[
  {"key":"account_type","label":"Account type","type":"select","required":true,"options":["Student portal","Staff portal","University email","Other"]},
  {"key":"identifier","label":"The number or username on the account","type":"text","required":true}
]'),
('NETWORK', 'Network and Internet', 'The campus network or Wi-Fi where you are.', 90, 'NORMAL', NULL, '[
  {"key":"location","label":"Where on campus","type":"text","required":true,"hint":"The building, the office or the hall"},
  {"key":"since","label":"Since when","type":"date","required":false}
]'),
('GENERAL', 'General ICT Issues', 'Anything else the Directorate of ICT should look at.', 100, 'NORMAL', 'Evidence, where it helps', '[]'),
('OTHER', 'Other Enquiries', 'A question rather than a problem.', 110, 'LOW', NULL, '[]');

-- ── the grants: no DELETE, ever (verify.sql §1) ─────────────────────────────
GRANT USAGE ON SCHEMA helpdesk TO app_platform, app_student, app_notification, app_auditor;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA helpdesk TO app_platform;
GRANT SELECT, INSERT ON helpdesk.ticket, helpdesk.ticket_comment, helpdesk.ticket_attachment, helpdesk.ticket_attachment_blob, helpdesk.ticket_event TO app_student;
GRANT UPDATE ON helpdesk.ticket TO app_student;
GRANT SELECT ON helpdesk.category, helpdesk.sla, helpdesk.setting TO app_student, app_notification;
GRANT SELECT ON ALL TABLES IN SCHEMA helpdesk TO app_auditor;
ALTER DEFAULT PRIVILEGES IN SCHEMA helpdesk GRANT SELECT, INSERT, UPDATE ON TABLES TO app_platform;
ALTER DEFAULT PRIVILEGES IN SCHEMA helpdesk GRANT SELECT ON TABLES TO app_auditor;

COMMIT;
