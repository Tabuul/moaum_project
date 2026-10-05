-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V328 — the ICT Support Desk across the University: queues, posted agents, routing, transfer, office escalation
--
--   The helpdesk of V251/V252 had one pool of ICT Support Agents, every one of whom saw every ticket, and the Director
--   of ICT over them. The University's support is in fact distributed: Computer Programme Officers posted to faculties
--   and offices answer the portal's problems where the students are, the Bursary's own staff answer payment problems,
--   the examinations unit answers result problems — and a Head of ICT Support Desk coordinates the whole. On the SAME
--   ticket system, tables and history:
--     · a Head of ICT Support Desk office (helpdeskhead): sees every ticket, assigns, transfers, escalates, keeps the
--       queues, the routing and the agents; support authority only, never financial or academic;
--     · support QUEUES (helpdesk.queue): ICT, Bursary, Academic Office, Course Registration, Exams/Results, Library,
--       GST, Student Biodata, Student Affairs, Accommodation, Security/ID Card — each with the University office that
--       decides what support cannot (its escalation office), configurable, extensible;
--     · an AGENT ASSIGNMENT (helpdesk.agent_assignment): a person who holds the ICT Support Agent office, placed on a
--       queue within a scope — the whole University, a faculty, a college, a department — available or on leave, with
--       dates and the officer who placed them; the Registry's person and office records are reused, never duplicated;
--     · ROUTING RULES (helpdesk.routing_rule): a category (optionally in a faculty or department) to a queue, with a
--       strategy — faculty agent first, least loaded, round robin, manual; a ticket is routed on submission and
--       assigned to an eligible, available agent, or left queued and the Head told;
--     · scope enforced in the database: helpdesk.can_view(person, ticket) — a head or the Director sees all; an agent
--       sees the tickets of their queues within their scope, and those assigned or escalated to them;
--     · a TRANSFER moves a ticket to another queue on a reason, the same ticket, the chain of custody on its history;
--     · an ESCALATION TO AN OFFICE (the queue's office, or the Director of ICT for a technical fault) puts the ticket in
--       WAITING_FOR_OFFICE; the office answers with its instruction and the ticket returns to the agent; a wait on the
--       requester (WAITING_FOR_STUDENT) ends by itself when they reply;
--     · an agent who leaves, loses the office or goes on leave holds nothing: their open tickets return to the queue
--       and the Head is told; no ticket is ever lost;
--     · a CRITICAL priority with its own SLA, for a portal-wide fault the Director must see.
--   Support access is never administrative authority: nothing here changes a fee, a result, a registration or a
--   refund; the agent inspects, guides, resets through the existing secure door, and escalates to the office that may.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V328: the ICT Support Desk across the University — queues, posted agents, routing, transfer, office escalation', true);

-- ── 1 · the Head of ICT Support Desk, an office of support authority ──────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('helpdeskhead', 'Head of ICT Support Desk', 'platform')
ON CONFLICT (code) DO NOTHING;

-- ── 2 · a CRITICAL priority, and the two waiting statuses ─────────────────────────────────────────────────────
ALTER TABLE helpdesk.sla DROP CONSTRAINT ck_hd_sla_priority;
ALTER TABLE helpdesk.sla ADD CONSTRAINT ck_hd_sla_priority CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT','CRITICAL'));
INSERT INTO helpdesk.sla (priority, first_response_hours, resolution_hours) VALUES ('CRITICAL', 1, 4) ON CONFLICT (priority) DO NOTHING;
ALTER TABLE helpdesk.category DROP CONSTRAINT ck_hd_category_priority;
ALTER TABLE helpdesk.category ADD CONSTRAINT ck_hd_category_priority CHECK (suggested_priority IN ('LOW','NORMAL','HIGH','URGENT','CRITICAL'));
ALTER TABLE helpdesk.ticket DROP CONSTRAINT ck_hd_ticket_priority;
ALTER TABLE helpdesk.ticket ADD CONSTRAINT ck_hd_ticket_priority CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT','CRITICAL'));
ALTER TABLE helpdesk.ticket DROP CONSTRAINT ck_hd_ticket_status;
ALTER TABLE helpdesk.ticket ADD CONSTRAINT ck_hd_ticket_status CHECK (status IN ('SUBMITTED','OPENED','IN_PROGRESS','WAITING_FOR_STUDENT','WAITING_FOR_OFFICE','RESOLVED','CLOSED','REOPENED'));
ALTER TABLE helpdesk.ticket_event DROP CONSTRAINT ck_hd_event_action;
ALTER TABLE helpdesk.ticket_event ADD CONSTRAINT ck_hd_event_action CHECK (action IN ('SUBMITTED','OPENED','STATUS_CHANGED','ASSIGNED','REASSIGNED','ESCALATED','PRIORITY_CHANGED',
                                                                                   'INTERNAL_NOTE','UPDATE','RESOLUTION','REOPENED','CLOSED','ATTACHMENT',
                                                                                   'ROUTED','QUEUED','TRANSFERRED','WAITING','ESCALATED_TO_OFFICE','OFFICE_ANSWERED','RETURNED'));

-- ── 3 · the queues ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE helpdesk.queue (
    code         text PRIMARY KEY,
    name         text NOT NULL,
    description  text NULL,
    office_code  text NULL REFERENCES ref.office(code),
    active       boolean NOT NULL DEFAULT true,
    ordinal      int NOT NULL DEFAULT 100,
    supervisor   uuid NULL REFERENCES iam.person(id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_queue_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    CONSTRAINT ck_hd_queue_name CHECK (btrim(name) <> '')
);
COMMENT ON TABLE helpdesk.queue IS 'A support queue (V328): where a kind of problem is worked, and the University office that decides what support cannot — its escalation office. Configurable; a queue is deactivated, never deleted.';
SELECT audit.attach('helpdesk.queue');

INSERT INTO helpdesk.queue (code, name, description, office_code, ordinal) VALUES
    ('ICT_SUPPORT',                 'ICT Support',                  'The portal, accounts, passwords, email, the network.',               'ict',       10),
    ('BURSARY_SUPPORT',             'Bursary Support',              'Payments, hanging payments, receipts, refunds, NELFUND funding.',    'bursar',    20),
    ('ACADEMIC_OFFICE_SUPPORT',     'Academic Office Support',      'Admission, acceptance, matriculation, academic records.',            'academic',  30),
    ('COURSE_REGISTRATION_SUPPORT', 'Course Registration Support',  'Courses that will not register, levels, semesters, windows.',        'academic',  40),
    ('EXAMS_RESULTS_SUPPORT',       'Exams and Results Support',    'Dockets, timetables, missing or wrong results, transcripts.',        'records',   50),
    ('LIBRARY_SUPPORT',             'Library Support',              'The library portal, loans, fines.',                                  'library',   60),
    ('GST_SUPPORT',                 'GST Support',                  'GST and EPS payment, registration and examinations.',                'gst',       70),
    ('STUDENT_BIODATA_SUPPORT',     'Student Biodata Support',      'Biodata corrections and the portal photograph.',                     'registrar', 80),
    ('STUDENT_AFFAIRS_SUPPORT',     'Student Affairs Support',      'Welfare and student affairs matters.',                               'dsa',       90),
    ('ACCOMMODATION_SUPPORT',       'Accommodation Support',        'Hostel application, reservation and allocation.',                    'housing',  100),
    ('SECURITY_ID_CARD_SUPPORT',    'Security and ID Card Support', 'Identity cards and security matters.',                               'security', 110)
ON CONFLICT (code) DO NOTHING;

-- ── 4 · the agents: a person on a queue within a scope ────────────────────────────────────────────────────────
CREATE TABLE helpdesk.agent_assignment (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id      uuid NOT NULL REFERENCES iam.person(id),
    queue_code     text NOT NULL REFERENCES helpdesk.queue(code),
    scope_kind     text NOT NULL DEFAULT 'GLOBAL',
    scope_ref      text NULL,
    is_primary     boolean NOT NULL DEFAULT false,
    active         boolean NOT NULL DEFAULT true,
    availability   text NOT NULL DEFAULT 'AVAILABLE',
    effective_from date NOT NULL DEFAULT current_date,
    effective_to   date NULL,
    assigned_by    uuid NULL,
    reason         text NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_aa_scope CHECK (scope_kind IN ('GLOBAL','FACULTY','COLLEGE','DEPARTMENT','OFFICE')),
    CONSTRAINT ck_hd_aa_scope_ref CHECK ((scope_kind = 'GLOBAL') = (scope_ref IS NULL)),
    CONSTRAINT ck_hd_aa_availability CHECK (availability IN ('AVAILABLE','BUSY','AWAY','OFFLINE','ON_LEAVE')),
    CONSTRAINT ck_hd_aa_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);
CREATE INDEX ix_hd_aa_person ON helpdesk.agent_assignment (person_id, active);
CREATE INDEX ix_hd_aa_queue ON helpdesk.agent_assignment (queue_code, active);
CREATE UNIQUE INDEX ux_hd_aa_live ON helpdesk.agent_assignment (person_id, queue_code, scope_kind, coalesce(scope_ref, '')) WHERE active;
COMMENT ON TABLE helpdesk.agent_assignment IS 'A support agent on a queue within a scope (V328): the person (who holds the ICT Support Agent office), the queue, the scope (the University, a faculty, a college, a department, an office), their availability, the dates, who placed them and why. The person and their offices are the Registry''s; this adds only the posting.';
SELECT audit.attach('helpdesk.agent_assignment');
CREATE OR REPLACE FUNCTION helpdesk.aa_touch() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_hd_aa_touch BEFORE UPDATE ON helpdesk.agent_assignment FOR EACH ROW EXECUTE FUNCTION helpdesk.aa_touch();

-- ── 5 · routing: a category (optionally in a faculty or department) to a queue, with a strategy ───────────────
CREATE TABLE helpdesk.routing_rule (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_code   text NOT NULL REFERENCES helpdesk.category(code),
    faculty_code    text NULL,
    department_code text NULL,
    queue_code      text NOT NULL REFERENCES helpdesk.queue(code),
    strategy        text NOT NULL DEFAULT 'FACULTY_AGENT_FIRST',
    priority_floor  text NULL,
    active          boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_rr_strategy CHECK (strategy IN ('ROUND_ROBIN','LEAST_LOADED','MANUAL','QUEUE_ONLY','FACULTY_AGENT_FIRST','OFFICE_AGENT_FIRST')),
    CONSTRAINT ck_hd_rr_floor CHECK (priority_floor IS NULL OR priority_floor IN ('LOW','NORMAL','HIGH','URGENT','CRITICAL'))
);
CREATE INDEX ix_hd_rr_category ON helpdesk.routing_rule (category_code, active);
COMMENT ON TABLE helpdesk.routing_rule IS 'Where a category goes (V328): the most specific active rule wins — department, then faculty, then the University — and its strategy picks the agent: faculty agent first (a posted agent before a global one), least loaded, round robin, office agent first, manual (queued for the Head), queue only.';
SELECT audit.attach('helpdesk.routing_rule');

-- the categories the University's support answers for, beyond the ICT desk's own
INSERT INTO helpdesk.category (code, name, description, ordinal, suggested_priority, attachment_hint, fields) VALUES
('GST', 'GST and EPS', 'GST or EPS payment, registration, course or examination.', 55, 'NORMAL', 'The receipt or a screenshot', '[
  {"key":"session","label":"Academic session","type":"session","required":true},
  {"key":"gst_issue","label":"What is wrong","type":"select","required":true,"options":["GST fee paid but not recognised","Cannot register a GST course","CBT examination problem","Result problem","Other"]},
  {"key":"payment_reference","label":"Payment reference, if a payment","type":"text","required":false}
]'),
('LIBRARY', 'Library', 'The library portal, a loan, a fine, library clearance.', 65, 'NORMAL', 'A screenshot or the receipt', '[
  {"key":"library_issue","label":"What is wrong","type":"select","required":true,"options":["Cannot access the library portal","A loan is wrong","A fine is wrong","Clearance","Other"]}
]'),
('HOSTEL', 'Hostel and Accommodation', 'Hostel application, reservation, payment or allocation.', 75, 'NORMAL', 'The receipt or a screenshot', '[
  {"key":"session","label":"Academic session","type":"session","required":true},
  {"key":"hostel_issue","label":"What is wrong","type":"select","required":true,"options":["Application","Reservation","Payment not reflecting","Allocation","Other"]},
  {"key":"payment_reference","label":"Payment reference, if a payment","type":"text","required":false}
]'),
('IDCARD', 'Identity Card', 'An identity card not issued, lost, wrong or not working.', 85, 'NORMAL', 'A photograph of the card, if you have it', '[
  {"key":"card_issue","label":"What is wrong","type":"select","required":true,"options":["Not yet issued","Lost or stolen","Details wrong","Card not working","Other"]}
]'),
('BIODATA', 'Biodata and Photograph', 'A wrong name, date of birth, state, programme or photograph on the portal.', 86, 'NORMAL', 'The document that shows the correct detail', '[
  {"key":"field","label":"What is wrong","type":"select","required":true,"options":["Name","Date of birth","State or LGA","Programme or level","Photograph","Other"]},
  {"key":"correct_value","label":"What it should read","type":"text","required":false}
]'),
('NELFUND', 'NELFUND and Funding', 'NELFUND funding, the wallet, a scholarship, a refund.', 15, 'NORMAL', 'The receipt or the Fund''s message', '[
  {"key":"session","label":"Academic session","type":"session","required":true},
  {"key":"funding_issue","label":"What is wrong","type":"select","required":true,"options":["NELFUND not credited","Cannot apply the wallet","Top-up problem","Refund problem","Scholarship not credited","Other"]}
]')
ON CONFLICT (code) DO NOTHING;

INSERT INTO helpdesk.routing_rule (category_code, queue_code, strategy)
SELECT v.category, v.queue, v.strategy FROM (VALUES
    ('PAYMENT',      'BURSARY_SUPPORT',             'LEAST_LOADED'),
    ('NELFUND',      'BURSARY_SUPPORT',             'LEAST_LOADED'),
    ('LOGIN',        'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('ACCOUNT',      'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('EMAIL',        'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('PORTAL',       'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('NETWORK',      'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('GENERAL',      'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('OTHER',        'ICT_SUPPORT',                 'FACULTY_AGENT_FIRST'),
    ('REGISTRATION', 'COURSE_REGISTRATION_SUPPORT', 'FACULTY_AGENT_FIRST'),
    ('RESULTS',      'EXAMS_RESULTS_SUPPORT',       'LEAST_LOADED'),
    ('EXAMINATIONS', 'EXAMS_RESULTS_SUPPORT',       'LEAST_LOADED'),
    ('GST',          'GST_SUPPORT',                 'LEAST_LOADED'),
    ('LIBRARY',      'LIBRARY_SUPPORT',             'LEAST_LOADED'),
    ('HOSTEL',       'ACCOMMODATION_SUPPORT',       'LEAST_LOADED'),
    ('IDCARD',       'SECURITY_ID_CARD_SUPPORT',    'LEAST_LOADED'),
    ('BIODATA',      'STUDENT_BIODATA_SUPPORT',     'LEAST_LOADED')
) AS v(category, queue, strategy)
WHERE EXISTS (SELECT 1 FROM helpdesk.category c WHERE c.code = v.category)
  AND NOT EXISTS (SELECT 1 FROM helpdesk.routing_rule r WHERE r.category_code = v.category AND r.faculty_code IS NULL AND r.department_code IS NULL);

-- ── 6 · the ticket knows its queue and the office it waits on ──────────────────────────────────────────────────
ALTER TABLE helpdesk.ticket ADD COLUMN IF NOT EXISTS queue_code text NULL REFERENCES helpdesk.queue(code);
ALTER TABLE helpdesk.ticket ADD COLUMN IF NOT EXISTS escalated_office text NULL REFERENCES ref.office(code);
ALTER TABLE helpdesk.ticket ADD COLUMN IF NOT EXISTS waiting_since timestamptz NULL;
CREATE INDEX IF NOT EXISTS ix_hd_ticket_queue ON helpdesk.ticket (queue_code, status);
CREATE INDEX IF NOT EXISTS ix_hd_ticket_office ON helpdesk.ticket (escalated_office) WHERE escalated_office IS NOT NULL;
COMMENT ON COLUMN helpdesk.ticket.queue_code IS 'V328: the support queue the ticket is worked in, from the routing rule on submission, or a transfer.';
COMMENT ON COLUMN helpdesk.ticket.escalated_office IS 'V328: the University office the ticket waits on — the queue''s office, or the Director of ICT — until it answers.';

-- ── 7 · who may act, and who may see ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.is_agent(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.office_assignment a
                    WHERE a.person_id = p_person AND a.office_code IN ('ictagent','helpdeskhead','ict','admin','super')
                      AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
$$;

-- the Head of ICT Support Desk, the Director of ICT and the administrators: every ticket, every act of coordination
CREATE OR REPLACE FUNCTION helpdesk.is_head(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.office_assignment a
                    WHERE a.person_id = p_person AND a.office_code IN ('helpdeskhead','ict','admin','super')
                      AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
$$;

-- an assignment covers a ticket when its scope does
CREATE OR REPLACE FUNCTION helpdesk.scope_covers(p_kind text, p_ref text, p_faculty text, p_department text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT CASE p_kind
             WHEN 'GLOBAL' THEN true
             WHEN 'FACULTY' THEN p_faculty IS NOT NULL AND upper(p_ref) = upper(p_faculty)
             WHEN 'DEPARTMENT' THEN p_department IS NOT NULL AND upper(p_ref) = upper(p_department)
             WHEN 'COLLEGE' THEN p_faculty IS NOT NULL AND EXISTS (SELECT 1 FROM ref.faculty f WHERE f.code = p_faculty AND upper(coalesce(f.college_code, '')) = upper(p_ref))
             WHEN 'OFFICE' THEN true
             ELSE false END
$$;

-- what an agent may see: a head sees all; an agent the tickets of their queues within their scope, and those with them;
-- an agent the Head has never posted anywhere works the whole desk as before V328, until a posting bounds them
CREATE OR REPLACE FUNCTION helpdesk.can_view(p_person uuid, p_ticket uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT helpdesk.is_head(p_person)
        OR EXISTS (SELECT 1 FROM helpdesk.ticket t WHERE t.id = p_ticket AND (t.assigned_to = p_person OR t.escalated_to = p_person))
        OR (helpdesk.is_agent(p_person)
            AND NOT EXISTS (SELECT 1 FROM helpdesk.agent_assignment a WHERE a.person_id = p_person)
            AND EXISTS (SELECT 1 FROM helpdesk.ticket t WHERE t.id = p_ticket))
        OR EXISTS (SELECT 1 FROM helpdesk.ticket t JOIN helpdesk.agent_assignment a ON a.queue_code = t.queue_code
                    WHERE t.id = p_ticket AND a.person_id = p_person AND a.active
                      AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                      AND helpdesk.scope_covers(a.scope_kind, a.scope_ref, t.faculty_code, t.department_code))
$$;
COMMENT ON FUNCTION helpdesk.can_view(uuid, uuid) IS 'Scope, enforced where it counts (V328): the Head, the Director and the administrators see every ticket; an agent sees the tickets of the queues they are posted on within their scope, and any ticket assigned or escalated to them; an agent never posted anywhere works the whole desk as before V328; an agent whose every posting has ended sees only what is with them.';

-- ── 8 · the eligible agents for a ticket, and the one the strategy picks ──────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.eligible_agents(p_ticket uuid)
RETURNS TABLE (person_id uuid, name text, scope_kind text, scope_ref text, availability text, open_tickets bigint, last_assigned_at timestamptz, posted boolean)
LANGUAGE sql STABLE AS $$
    SELECT a.person_id, helpdesk.person_name(a.person_id), a.scope_kind, a.scope_ref, a.availability,
           (SELECT count(*) FROM helpdesk.ticket x WHERE x.assigned_to = a.person_id AND x.status NOT IN ('RESOLVED','CLOSED')),
           (SELECT max(x.assigned_at) FROM helpdesk.ticket x WHERE x.assigned_to = a.person_id),
           a.scope_kind IN ('FACULTY','COLLEGE','DEPARTMENT')
      FROM helpdesk.ticket t
      JOIN helpdesk.agent_assignment a ON a.queue_code = t.queue_code
      JOIN iam.person p ON p.id = a.person_id AND p.ended_on IS NULL
     WHERE t.id = p_ticket AND a.active AND a.availability IN ('AVAILABLE','BUSY')
       AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
       AND helpdesk.scope_covers(a.scope_kind, a.scope_ref, t.faculty_code, t.department_code)
       AND helpdesk.is_agent(a.person_id)
     ORDER BY a.scope_kind IN ('FACULTY','COLLEGE','DEPARTMENT') DESC, 6, 7 NULLS FIRST, 2
$$;

CREATE OR REPLACE FUNCTION helpdesk.pick_agent(p_ticket uuid, p_strategy text)
RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT e.person_id FROM helpdesk.eligible_agents(p_ticket) e
     ORDER BY CASE p_strategy WHEN 'FACULTY_AGENT_FIRST' THEN (NOT e.posted)::int WHEN 'OFFICE_AGENT_FIRST' THEN (e.scope_kind <> 'OFFICE')::int ELSE 0 END,
              CASE p_strategy WHEN 'ROUND_ROBIN' THEN 0 ELSE e.open_tickets END,
              CASE p_strategy WHEN 'ROUND_ROBIN' THEN coalesce(extract(epoch from e.last_assigned_at), 0) ELSE 0 END,
              e.open_tickets, e.name
     LIMIT 1
$$;

-- ── 9 · routing on submission: the queue from the most specific rule, then the agent from its strategy ────────
CREATE OR REPLACE FUNCTION helpdesk.route(p_ticket uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; c helpdesk.category; r helpdesk.routing_rule; v_agent uuid; q helpdesk.queue;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status = 'CLOSED' THEN RETURN t.queue_code; END IF;
    SELECT * INTO c FROM helpdesk.category WHERE id = t.category_id;
    SELECT rr.* INTO r FROM helpdesk.routing_rule rr JOIN helpdesk.queue qq ON qq.code = rr.queue_code AND qq.active
     WHERE rr.active AND rr.category_code = c.code
       AND (rr.department_code IS NULL OR rr.department_code = t.department_code)
       AND (rr.faculty_code IS NULL OR rr.faculty_code = t.faculty_code)
     ORDER BY (rr.department_code IS NOT NULL) DESC, (rr.faculty_code IS NOT NULL) DESC, rr.created_at
     LIMIT 1;
    IF NOT FOUND THEN
        SELECT * INTO q FROM helpdesk.queue WHERE code = 'ICT_SUPPORT';
        r.queue_code := 'ICT_SUPPORT'; r.strategy := 'FACULTY_AGENT_FIRST'; r.priority_floor := NULL;
    END IF;
    UPDATE helpdesk.ticket SET queue_code = r.queue_code,
           priority = CASE WHEN r.priority_floor IS NOT NULL
                            AND array_position(ARRAY['LOW','NORMAL','HIGH','URGENT','CRITICAL'], r.priority_floor) > array_position(ARRAY['LOW','NORMAL','HIGH','URGENT','CRITICAL'], priority)
                           THEN r.priority_floor ELSE priority END
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'ROUTED', t.queue_code, r.queue_code,
        (SELECT qq.name FROM helpdesk.queue qq WHERE qq.code = r.queue_code) || ' by the ' || c.name || ' rule');
    IF r.strategy IN ('MANUAL', 'QUEUE_ONLY') THEN
        PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'QUEUED', NULL, r.queue_code, 'Waits for the Head of ICT Support Desk to assign it');
        RETURN r.queue_code;
    END IF;
    v_agent := helpdesk.pick_agent(p_ticket, r.strategy);
    IF v_agent IS NULL THEN
        PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'QUEUED', NULL, r.queue_code, 'No available agent on the queue covers this ticket; the Head of ICT Support Desk is told');
        RETURN r.queue_code;
    END IF;
    UPDATE helpdesk.ticket SET assigned_to = v_agent, assigned_by = NULL, assigned_at = now() WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'ASSIGNED', NULL, helpdesk.person_name(v_agent),
        'Assigned by the ' || lower(replace(r.strategy, '_', ' ')) || ' rule of the ' || (SELECT qq.name FROM helpdesk.queue qq WHERE qq.code = r.queue_code) || ' queue');
    RETURN r.queue_code;
END $$;
COMMENT ON FUNCTION helpdesk.route(uuid) IS 'A ticket routed (V328): the queue from the most specific active rule for its category (department, faculty, the University; ICT Support when none), the agent from the rule''s strategy among the eligible, available agents whose scope covers it — or queued, on the record, for the Head.';

-- ── 10 · assignment: to any agent of the desk; eligibility is advice the screen shows, authority is the Head's ──
-- (helpdesk.assign of V251 stands; it now admits the Head of ICT Support Desk through helpdesk.is_agent)

-- ── 11 · transfer: the same ticket, another queue, on a reason; routed again to an agent there ────────────────
CREATE OR REPLACE FUNCTION helpdesk.transfer(p_ticket uuid, p_queue text, p_by uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; q helpdesk.queue; v_agent uuid; v_from text;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status IN ('CLOSED', 'RESOLVED') THEN RAISE EXCEPTION 'HELPDESK_TRANSFER_SETTLED: a resolved or closed ticket is not transferred' USING ERRCODE = '23514', HINT = 'Reopen it first.'; END IF;
    SELECT * INTO q FROM helpdesk.queue WHERE code = upper(btrim(coalesce(p_queue, ''))) AND active;
    IF NOT FOUND THEN RAISE EXCEPTION 'HELPDESK_QUEUE_UNKNOWN: no active support queue is called %', p_queue USING ERRCODE = '23514'; END IF;
    IF q.code = t.queue_code THEN RAISE EXCEPTION 'HELPDESK_TRANSFER_SAME: the ticket is on the % queue already', q.name USING ERRCODE = '23514'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'HELPDESK_REASON_REQUIRED: a transfer says why' USING ERRCODE = '23514', HINT = 'Give the reason in a line.'; END IF;
    v_from := t.queue_code;
    UPDATE helpdesk.ticket SET queue_code = q.code, assigned_to = NULL, assigned_by = NULL, assigned_at = NULL,
           escalated_office = NULL, status = CASE WHEN status IN ('WAITING_FOR_OFFICE','WAITING_FOR_STUDENT','IN_PROGRESS') THEN 'OPENED' ELSE status END, waiting_since = NULL
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_by, helpdesk.person_name(p_by), 'TRANSFERRED',
        coalesce((SELECT name FROM helpdesk.queue WHERE code = v_from), 'no queue') || CASE WHEN t.assigned_to IS NOT NULL THEN ' · ' || helpdesk.person_name(t.assigned_to) ELSE '' END,
        q.name, btrim(p_reason));
    v_agent := helpdesk.pick_agent(p_ticket, coalesce((SELECT r.strategy FROM helpdesk.routing_rule r JOIN helpdesk.category c ON c.code = r.category_code
                                                          WHERE c.id = t.category_id AND r.queue_code = q.code AND r.active ORDER BY r.created_at LIMIT 1), 'LEAST_LOADED'));
    IF v_agent IS NOT NULL THEN
        UPDATE helpdesk.ticket SET assigned_to = v_agent, assigned_by = NULL, assigned_at = now() WHERE id = p_ticket;
        PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'ASSIGNED', NULL, helpdesk.person_name(v_agent), 'Assigned on transfer to the ' || q.name || ' queue');
    ELSE
        PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'QUEUED', NULL, q.code, 'No available agent on the ' || q.name || ' queue covers this ticket; the Head of ICT Support Desk is told');
    END IF;
END $$;

-- ── 12 · escalation to an office: the queue's own, or the Director of ICT for a technical fault ───────────────
CREATE OR REPLACE FUNCTION helpdesk.escalate_to_office(p_ticket uuid, p_office text, p_by uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; q helpdesk.queue; v_office text := lower(btrim(coalesce(p_office, ''))); v_label text; v_from text;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.status IN ('CLOSED', 'RESOLVED') THEN RAISE EXCEPTION 'HELPDESK_ESCALATE_SETTLED: a resolved or closed ticket is not escalated' USING ERRCODE = '23514', HINT = 'Reopen it first.'; END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'HELPDESK_REASON_REQUIRED: an escalation says why' USING ERRCODE = '23514', HINT = 'Give the reason in a line.'; END IF;
    SELECT * INTO q FROM helpdesk.queue WHERE code = t.queue_code;
    IF v_office <> 'ict' AND (q.office_code IS NULL OR v_office <> q.office_code) THEN
        RAISE EXCEPTION 'HELPDESK_ESCALATION_OFFICE: a % ticket is escalated to % or to the Director of ICT, not to %', coalesce(q.name, 'support'),
            coalesce((SELECT label FROM ref.office WHERE code = q.office_code), 'no office'), v_office USING ERRCODE = '23514',
            HINT = 'A policy or administrative decision goes to the office responsible for the queue; a technical fault to the Director of ICT.';
    END IF;
    SELECT label INTO v_label FROM ref.office WHERE code = v_office;
    IF v_label IS NULL THEN RAISE EXCEPTION 'HELPDESK_ESCALATION_OFFICE: no office is coded %', v_office USING ERRCODE = '23514'; END IF;
    v_from := t.status;
    UPDATE helpdesk.ticket SET escalated_office = v_office, escalated_by = p_by, escalated_at = now(), escalation_reason = btrim(p_reason), escalated_to = NULL,
           status = CASE WHEN status IN ('SUBMITTED','OPENED','IN_PROGRESS','REOPENED','WAITING_FOR_STUDENT') THEN 'WAITING_FOR_OFFICE' ELSE status END,
           waiting_since = now(),
           opened_at = coalesce(opened_at, now()), opened_by = coalesce(opened_by, p_by)
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_by, helpdesk.person_name(p_by), 'ESCALATED_TO_OFFICE', v_from, v_label, btrim(p_reason));
END $$;
COMMENT ON FUNCTION helpdesk.escalate_to_office(uuid, text, uuid, text) IS 'An escalation to an office (V328): the queue''s responsible office for a policy or administrative decision, or the Director of ICT for a technical fault; the ticket waits for the office, which answers through helpdesk.office_answer. Support authority never becomes the office''s.';

-- the office answers: an instruction to the agent (internal by default), the ticket back with the agent
CREATE OR REPLACE FUNCTION helpdesk.office_answer(p_ticket uuid, p_by uuid, p_body text, p_internal boolean)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket; v_label text; v uuid; v_name text;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no ticket %', p_ticket USING ERRCODE = 'no_data_found'; END IF;
    IF t.escalated_office IS NULL THEN RAISE EXCEPTION 'HELPDESK_NOT_WITH_OFFICE: the ticket is not with an office' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_by AND a.office_code = t.escalated_office
                      AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
       AND NOT helpdesk.is_head(p_by) THEN
        RAISE EXCEPTION 'HELPDESK_NOT_THE_OFFICE: the ticket waits on %, which you do not hold', (SELECT label FROM ref.office WHERE code = t.escalated_office) USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_body, ''))) < 5 THEN RAISE EXCEPTION 'HELPDESK_ANSWER_REQUIRED: the office''s answer says what is decided' USING ERRCODE = '23514'; END IF;
    SELECT label INTO v_label FROM ref.office WHERE code = t.escalated_office;
    v_name := helpdesk.person_name(p_by) || ' (' || v_label || ')';
    INSERT INTO helpdesk.ticket_comment (id, ticket_id, author_kind, author_id, author_name, internal, body)
    VALUES (gen_random_uuid(), p_ticket, 'AGENT', p_by, v_name, coalesce(p_internal, true), btrim(p_body)) RETURNING id INTO v;
    UPDATE helpdesk.ticket SET escalated_office = NULL, waiting_since = NULL,
           status = CASE WHEN status = 'WAITING_FOR_OFFICE' THEN CASE WHEN assigned_to IS NULL THEN 'OPENED' ELSE 'IN_PROGRESS' END ELSE status END,
           first_response_at = CASE WHEN NOT coalesce(p_internal, true) THEN coalesce(first_response_at, now()) ELSE first_response_at END
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'AGENT', p_by, v_name, 'OFFICE_ANSWERED', v_label, coalesce(helpdesk.person_name(t.assigned_to), 'the queue'), left(btrim(p_body), 200), coalesce(p_internal, true));
    RETURN v;
END $$;

-- ── 13 · waiting on the requester, ended by their reply; the transitions widened ──────────────────────────────
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
        ok := (v_from, p_to) IN (('SUBMITTED','OPENED'), ('OPENED','IN_PROGRESS'), ('REOPENED','IN_PROGRESS'), ('RESOLVED','CLOSED'),
                                 ('IN_PROGRESS','WAITING_FOR_STUDENT'), ('WAITING_FOR_STUDENT','IN_PROGRESS'), ('WAITING_FOR_OFFICE','IN_PROGRESS'))
              OR (p_to = 'REOPENED' AND v_from IN ('RESOLVED','CLOSED'))
              OR (p_to = 'CLOSED' AND v_from <> 'CLOSED');
        IF p_to = 'CLOSED' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'a closure by the desk records its reason' USING ERRCODE = '23514', HINT = 'Say why the ticket is closed.';
        END IF;
        IF p_to = 'WAITING_FOR_STUDENT' AND v_reason IS NULL THEN
            RAISE EXCEPTION 'HELPDESK_REASON_REQUIRED: waiting on the requester says what is needed from them' USING ERRCODE = '23514', HINT = 'Say what the requester should send or confirm.';
        END IF;
    ELSIF p_actor_kind = 'REQUESTER' THEN
        ok := (v_from = 'RESOLVED' AND p_to IN ('CLOSED','REOPENED'))
              OR (p_to = 'CLOSED' AND v_from IN ('SUBMITTED','OPENED','IN_PROGRESS','REOPENED','WAITING_FOR_STUDENT','WAITING_FOR_OFFICE'));
    ELSIF p_actor_kind = 'SYSTEM' THEN
        ok := (v_from = 'RESOLVED' AND p_to = 'CLOSED') OR (v_from = 'WAITING_FOR_STUDENT' AND p_to = 'IN_PROGRESS');
    END IF;
    IF p_to = 'REOPENED' AND v_reason IS NULL THEN
        RAISE EXCEPTION 'reopening a ticket says what is still wrong' USING ERRCODE = '23514', HINT = 'Say why the ticket is reopened, in a line.';
    END IF;
    IF NOT ok THEN
        RAISE EXCEPTION 'a ticket does not go from % to % this way', lower(replace(v_from, '_', ' ')), lower(replace(p_to, '_', ' '))
            USING ERRCODE = '23514', HINT = 'The ticket moves submitted → opened → in progress → resolved → closed, waiting on the requester or an office in between; a resolved or closed ticket is reopened on a reason.';
    END IF;
    UPDATE helpdesk.ticket SET
        status = p_to,
        opened_at = CASE WHEN p_to IN ('OPENED','REOPENED') AND opened_at IS NULL THEN now() ELSE opened_at END,
        opened_by = CASE WHEN p_to IN ('OPENED','REOPENED') AND opened_by IS NULL THEN p_actor ELSE opened_by END,
        in_progress_at = CASE WHEN p_to = 'IN_PROGRESS' THEN now() ELSE in_progress_at END,
        first_response_at = CASE WHEN p_to IN ('IN_PROGRESS','WAITING_FOR_STUDENT') AND first_response_at IS NULL AND p_actor_kind = 'AGENT' THEN now() ELSE first_response_at END,
        waiting_since = CASE WHEN p_to IN ('WAITING_FOR_STUDENT','WAITING_FOR_OFFICE') THEN now() ELSE NULL END,
        escalated_office = CASE WHEN v_from = 'WAITING_FOR_OFFICE' THEN NULL ELSE escalated_office END,
        resolved_at = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolved_at END,
        resolved_by = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolved_by END,
        resolution_summary = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolution_summary END,
        resolution_details = CASE WHEN p_to = 'REOPENED' THEN NULL ELSE resolution_details END,
        closed_at = CASE WHEN p_to = 'CLOSED' THEN now() ELSE NULL END,
        closed_by = CASE WHEN p_to = 'CLOSED' THEN p_actor ELSE NULL END,
        closed_by_kind = CASE WHEN p_to = 'CLOSED' THEN p_actor_kind ELSE NULL END,
        closure_reason = CASE WHEN p_to = 'CLOSED' THEN coalesce(v_reason, CASE WHEN p_actor_kind = 'REQUESTER' AND v_from = 'RESOLVED' THEN 'The requester confirmed the resolution' WHEN p_actor_kind = 'REQUESTER' THEN 'Withdrawn by the requester' END) ELSE NULL END,
        reopen_count = CASE WHEN p_to = 'REOPENED' THEN reopen_count + 1 ELSE reopen_count END
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, p_actor_kind, p_actor, p_actor_name,
        CASE WHEN p_to = 'OPENED' THEN 'OPENED' WHEN p_to = 'REOPENED' THEN 'REOPENED' WHEN p_to = 'CLOSED' THEN 'CLOSED' WHEN p_to = 'WAITING_FOR_STUDENT' THEN 'WAITING' ELSE 'STATUS_CHANGED' END,
        v_from, p_to,
        coalesce(v_reason, CASE WHEN p_to = 'CLOSED' AND p_actor_kind = 'REQUESTER' AND v_from = 'RESOLVED' THEN 'The requester confirmed the resolution'
                                WHEN p_to = 'CLOSED' AND p_actor_kind = 'REQUESTER' THEN 'Withdrawn by the requester'
                                WHEN p_to = 'IN_PROGRESS' AND p_actor_kind = 'SYSTEM' THEN 'The requester replied' END));
END $$;

-- a requester's reply ends the wait on them
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
    IF p_kind = 'REQUESTER' AND t.status = 'WAITING_FOR_STUDENT' THEN
        PERFORM helpdesk.transition(p_ticket, 'IN_PROGRESS', 'SYSTEM', NULL, 'The portal', NULL);
    END IF;
    RETURN v;
END $$;

-- ── 14 · nothing is lost: an agent who leaves, loses the office or is on leave holds no ticket ────────────────
CREATE OR REPLACE FUNCTION helpdesk.return_to_queue(p_ticket uuid, p_detail text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE t helpdesk.ticket;
BEGIN
    SELECT * INTO t FROM helpdesk.ticket WHERE id = p_ticket FOR UPDATE;
    IF NOT FOUND OR t.assigned_to IS NULL THEN RETURN; END IF;
    UPDATE helpdesk.ticket SET assigned_to = NULL, assigned_by = NULL, assigned_at = NULL,
           status = CASE WHEN status IN ('IN_PROGRESS','WAITING_FOR_STUDENT') THEN 'OPENED' ELSE status END, waiting_since = CASE WHEN status = 'WAITING_FOR_STUDENT' THEN NULL ELSE waiting_since END
     WHERE id = p_ticket;
    PERFORM helpdesk.record(p_ticket, 'SYSTEM', NULL, 'The portal', 'RETURNED', helpdesk.person_name(t.assigned_to), coalesce((SELECT name FROM helpdesk.queue WHERE code = t.queue_code), 'the desk'), p_detail);
END $$;

CREATE OR REPLACE FUNCTION helpdesk.sweep_inactive_agents()
RETURNS SETOF uuid
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT t.id, t.assigned_to
          FROM helpdesk.ticket t JOIN iam.person p ON p.id = t.assigned_to
         WHERE t.status NOT IN ('RESOLVED','CLOSED')
           AND (p.ended_on IS NOT NULL
                OR NOT helpdesk.is_agent(t.assigned_to)
                OR (EXISTS (SELECT 1 FROM helpdesk.agent_assignment a WHERE a.person_id = t.assigned_to)
                    AND NOT EXISTS (SELECT 1 FROM helpdesk.agent_assignment a WHERE a.person_id = t.assigned_to AND a.active
                                       AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                                       AND a.availability NOT IN ('ON_LEAVE','OFFLINE'))))
         ORDER BY t.created_at LIMIT 500 FOR UPDATE OF t SKIP LOCKED
    LOOP
        PERFORM helpdesk.return_to_queue(r.id, 'Returned to the queue: the agent is no longer available (left, lost the office, or on leave); the Head of ICT Support Desk is told');
        RETURN NEXT r.id;
    END LOOP;
    RETURN;
END $$;
COMMENT ON FUNCTION helpdesk.sweep_inactive_agents() IS 'No ticket is lost (V328): an open ticket held by a person who has left, no longer holds a support office, or whose every posting is inactive, on leave or offline is returned to its queue on the record; the Head is told.';

-- the Head takes an agent off the desk, or moves what they hold to another agent
CREATE OR REPLACE FUNCTION helpdesk.deactivate_agent(p_person uuid, p_by uuid, p_reason text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int := 0; r record;
BEGIN
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'HELPDESK_REASON_REQUIRED: taking an agent off the desk says why' USING ERRCODE = '23514'; END IF;
    UPDATE helpdesk.agent_assignment SET active = false, effective_to = least(coalesce(effective_to, current_date), current_date), reason = coalesce(reason || ' · ', '') || 'Ended: ' || btrim(p_reason)
     WHERE person_id = p_person AND active;
    FOR r IN SELECT id FROM helpdesk.ticket WHERE assigned_to = p_person AND status NOT IN ('RESOLVED','CLOSED') LOOP
        PERFORM helpdesk.return_to_queue(r.id, 'Returned to the queue by ' || helpdesk.person_name(p_by) || ': ' || btrim(p_reason));
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION helpdesk.reassign_open(p_from uuid, p_to uuid, p_by uuid, p_reason text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int := 0; r record;
BEGIN
    IF btrim(coalesce(p_reason, '')) = '' THEN RAISE EXCEPTION 'HELPDESK_REASON_REQUIRED: moving an agent''s tickets says why' USING ERRCODE = '23514'; END IF;
    IF NOT helpdesk.is_agent(p_to) THEN RAISE EXCEPTION 'only an agent of the desk takes tickets' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT id FROM helpdesk.ticket WHERE assigned_to = p_from AND status NOT IN ('RESOLVED','CLOSED') ORDER BY created_at LOOP
        PERFORM helpdesk.assign(r.id, p_to, p_by, btrim(p_reason));
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- ── 15 · the workload, by agent and by queue ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.agent_workload(p_queue text)
RETURNS TABLE (person_id uuid, name text, staff_number text, queues text, availability text, scopes text, open bigint, in_progress bigint, waiting bigint, overdue bigint, critical bigint,
               resolved_today bigint, resolved_week bigint, avg_resolution_hours numeric)
LANGUAGE sql STABLE AS $$
    WITH agents AS (
        SELECT DISTINCT a.person_id FROM helpdesk.agent_assignment a WHERE a.active AND (p_queue IS NULL OR a.queue_code = p_queue)
        UNION SELECT t.assigned_to FROM helpdesk.ticket t WHERE t.assigned_to IS NOT NULL AND t.status NOT IN ('RESOLVED','CLOSED') AND (p_queue IS NULL OR t.queue_code = p_queue))
    SELECT g.person_id, helpdesk.person_name(g.person_id), p.staff_number,
           (SELECT string_agg(DISTINCT q.name, ', ' ORDER BY q.name) FROM helpdesk.agent_assignment a JOIN helpdesk.queue q ON q.code = a.queue_code WHERE a.person_id = g.person_id AND a.active),
           coalesce((SELECT a.availability FROM helpdesk.agent_assignment a WHERE a.person_id = g.person_id AND a.active ORDER BY a.is_primary DESC, a.created_at LIMIT 1), 'AVAILABLE'),
           (SELECT string_agg(DISTINCT CASE WHEN a.scope_kind = 'GLOBAL' THEN 'The University' ELSE initcap(lower(a.scope_kind)) || ' ' || a.scope_ref END, ', ') FROM helpdesk.agent_assignment a WHERE a.person_id = g.person_id AND a.active),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')),
           count(t.id) FILTER (WHERE t.status = 'IN_PROGRESS'),
           count(t.id) FILTER (WHERE t.status IN ('WAITING_FOR_STUDENT','WAITING_FOR_OFFICE')),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND t.priority IN ('URGENT','CRITICAL')),
           count(t.id) FILTER (WHERE t.resolved_at >= date_trunc('day', now())),
           count(t.id) FILTER (WHERE t.resolved_at >= date_trunc('week', now())),
           round(avg(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 3600) FILTER (WHERE t.resolved_at IS NOT NULL)::numeric, 1)
      FROM agents g JOIN iam.person p ON p.id = g.person_id
      LEFT JOIN helpdesk.ticket t ON (t.assigned_to = g.person_id OR t.resolved_by = g.person_id) AND (p_queue IS NULL OR t.queue_code = p_queue)
     GROUP BY g.person_id, p.staff_number
     ORDER BY 7 DESC, 2
$$;

CREATE OR REPLACE FUNCTION helpdesk.queue_workload()
RETURNS TABLE (code text, name text, office_code text, office text, active boolean, agents bigint, available_agents bigint, open bigint, unassigned bigint, in_progress bigint,
               waiting_student bigint, waiting_office bigint, overdue bigint, critical bigint, resolved_week bigint)
LANGUAGE sql STABLE AS $$
    SELECT q.code, q.name, q.office_code, o.label, q.active,
           (SELECT count(DISTINCT a.person_id) FROM helpdesk.agent_assignment a WHERE a.queue_code = q.code AND a.active),
           (SELECT count(DISTINCT a.person_id) FROM helpdesk.agent_assignment a WHERE a.queue_code = q.code AND a.active AND a.availability IN ('AVAILABLE','BUSY')
              AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED')),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND t.assigned_to IS NULL),
           count(t.id) FILTER (WHERE t.status = 'IN_PROGRESS'),
           count(t.id) FILTER (WHERE t.status = 'WAITING_FOR_STUDENT'),
           count(t.id) FILTER (WHERE t.status = 'WAITING_FOR_OFFICE'),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND helpdesk.due_at(t.created_at, t.priority) < now()),
           count(t.id) FILTER (WHERE t.status NOT IN ('RESOLVED','CLOSED') AND t.priority IN ('URGENT','CRITICAL')),
           count(t.id) FILTER (WHERE t.resolved_at >= date_trunc('week', now()))
      FROM helpdesk.queue q LEFT JOIN ref.office o ON o.code = q.office_code LEFT JOIN helpdesk.ticket t ON t.queue_code = q.code
     GROUP BY q.code, q.name, q.office_code, o.label, q.active, q.ordinal
     ORDER BY q.active DESC, q.ordinal, q.name
$$;

-- ── 16 · the tickets already on the desk: given their queue by the rules, assignments left as they are ────────
UPDATE helpdesk.ticket t
   SET queue_code = coalesce((SELECT r.queue_code FROM helpdesk.routing_rule r JOIN helpdesk.category c ON c.code = r.category_code
                               WHERE c.id = t.category_id AND r.active AND r.faculty_code IS NULL AND r.department_code IS NULL ORDER BY r.created_at LIMIT 1), 'ICT_SUPPORT')
 WHERE t.queue_code IS NULL;

-- ── 17 · the grants, as the schema's default privileges give them; the queue readable to the student's side ──
GRANT SELECT ON helpdesk.queue, helpdesk.routing_rule TO app_student, app_notification;
GRANT SELECT ON helpdesk.agent_assignment TO app_notification;

COMMIT;
