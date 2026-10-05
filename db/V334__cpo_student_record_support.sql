-- V334 · Student record support from the ICT Support Desk
--
-- A Computer Programme Officer (an ICT Support Agent) resolves a student's problem by looking at the record and, where the
-- Head of the Support Desk has let them, correcting what is theirs to correct: a phone number, an address, a guardian, the
-- photograph, a course registration — through the same services the student and the offices use, never around them.
-- Nothing here is a second register, a second registration engine, a second RBAC or a second audit:
--
--     · the posting on a queue (V328) carries the capabilities the Head grants with it; a person's capabilities are the
--       union of their live postings'; the Head of the Support Desk and the Director hold them all;
--     · a student is within an agent's reach when a live posting's scope (the University, a faculty, a college, a
--       department) covers the student's faculty and department — the same scope rule the tickets use; an office-scoped
--       posting reaches no student;
--     · every support act on a student is written to helpdesk.support_action — the student, the agent, the ticket it was
--       done for, what changed from what to what, the reason — beside the audit spine's own record of the write, and
--       filed on the ticket's timeline when a ticket is named;
--     · a replacement photograph is kept in people.student_photo and read first by the one resolver every screen uses;
--     · the sensitive fields (nationality, state of origin, LGA) go to the Registry as a change request, as the student's
--       own would; the JAMB-read fields are refused; status, programme, matriculation, results and money are not touched
--       here at all.

-- ── 1 · the capabilities a posting carries ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS']
$$;
COMMENT ON FUNCTION helpdesk.support_capabilities() IS 'V334: what a support posting may carry — reading a student within scope; editing the open contact, personal and family fields; replacing the photograph; raising a Registry change; reading payments and documents; managing a registration through the engine; exporting lists. Status, programme, matriculation, results and money are never among them.';

ALTER TABLE helpdesk.agent_assignment ADD COLUMN IF NOT EXISTS capabilities text[] NOT NULL DEFAULT '{}';
ALTER TABLE helpdesk.agent_assignment DROP CONSTRAINT IF EXISTS ck_hd_aa_capabilities;
ALTER TABLE helpdesk.agent_assignment ADD CONSTRAINT ck_hd_aa_capabilities CHECK (capabilities <@ helpdesk.support_capabilities());
COMMENT ON COLUMN helpdesk.agent_assignment.capabilities IS 'V334: the student-record capabilities the Head granted with this posting; empty by default — a posting reads and works tickets, nothing more, until the Head says otherwise.';

-- a person's capabilities: the union of their live postings'
CREATE OR REPLACE FUNCTION helpdesk.agent_capabilities(p_person uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT array_agg(DISTINCT c ORDER BY c)
                       FROM helpdesk.agent_assignment a, unnest(a.capabilities) AS c
                      WHERE a.person_id = p_person AND a.active
                        AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)), '{}'::text[])
$$;

-- ── 2 · the students a person reaches ───────────────────────────────────────────────────────────────────────────
-- a live posting's scope covers the student's faculty and department (the University, a faculty, a college, a department);
-- an office-scoped posting reaches no student
CREATE OR REPLACE FUNCTION helpdesk.agent_may_see_student(p_person uuid, p_student uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN helpdesk.agent_assignment a ON a.person_id = p_person AND a.active
                 AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
         WHERE s.id = p_student
           AND a.scope_kind <> 'OFFICE'
           AND helpdesk.scope_covers(a.scope_kind, a.scope_ref, p.faculty_code, p.dept_code))
$$;
COMMENT ON FUNCTION helpdesk.agent_may_see_student(uuid, uuid) IS 'V334: whether a support agent reaches a student — a live posting whose scope covers the student''s faculty and department. The server asks this before every read and every write on a student from the support desk.';

-- the scope as a filter a list applies: everything, or these faculties and departments
CREATE OR REPLACE FUNCTION helpdesk.agent_student_scope(p_person uuid)
RETURNS TABLE (global boolean, faculties text[], departments text[], words text)
LANGUAGE sql STABLE AS $$
    WITH live AS (
        SELECT a.scope_kind, upper(a.scope_ref) AS ref
          FROM helpdesk.agent_assignment a
         WHERE a.person_id = p_person AND a.active AND a.scope_kind <> 'OFFICE'
           AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)),
    fac AS (
        SELECT ref AS code FROM live WHERE scope_kind = 'FACULTY'
        UNION
        SELECT f.code FROM live l JOIN ref.faculty f ON l.scope_kind = 'COLLEGE' AND upper(coalesce(f.college_code, '')) = l.ref),
    dep AS (SELECT ref AS code FROM live WHERE scope_kind = 'DEPARTMENT')
    SELECT EXISTS (SELECT 1 FROM live WHERE scope_kind = 'GLOBAL'),
           coalesce((SELECT array_agg(code ORDER BY code) FROM fac), '{}'::text[]),
           coalesce((SELECT array_agg(code ORDER BY code) FROM dep), '{}'::text[]),
           CASE WHEN EXISTS (SELECT 1 FROM live WHERE scope_kind = 'GLOBAL') THEN 'The University'
                ELSE nullif(concat_ws('; ',
                        (SELECT string_agg(f.name, ', ' ORDER BY f.name) FROM fac JOIN ref.faculty f ON f.code = fac.code),
                        (SELECT string_agg(d.name, ', ' ORDER BY d.name) FROM dep JOIN ref.department d ON d.code = dep.code)), '') END
$$;

-- ── 3 · the ledger of support acts ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE helpdesk.support_action (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    agent_id      uuid NOT NULL REFERENCES iam.person(id),
    agent_office  text NOT NULL,
    ticket_id     uuid NULL REFERENCES helpdesk.ticket(id) ON DELETE SET NULL,
    action        text NOT NULL,
    field         text NULL,
    old_value     text NULL,
    new_value     text NULL,
    reason        text NOT NULL,
    session       text NULL,
    semester      int NULL,
    at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_hd_sa_action CHECK (action IN ('CONTACT_EDITED', 'PERSONAL_EDITED', 'FAMILY_EDITED', 'PHOTO_REPLACED', 'CHANGE_REQUESTED',
                                                 'REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'REGISTRATION_SUBMITTED', 'RECORD_EXPORTED')),
    CONSTRAINT ck_hd_sa_reason CHECK (btrim(reason) <> '')
);
CREATE INDEX ix_hd_sa_student ON helpdesk.support_action (student_id, at DESC);
CREATE INDEX ix_hd_sa_agent ON helpdesk.support_action (agent_id, at DESC);
CREATE INDEX ix_hd_sa_ticket ON helpdesk.support_action (ticket_id) WHERE ticket_id IS NOT NULL;
COMMENT ON TABLE helpdesk.support_action IS 'V334: every act a support agent did on a student''s record — who, for which ticket, what changed from what to what, why, when, in which session. The audit spine records the write itself; this is the desk''s own account of it, read on the student''s profile and the ticket''s timeline.';
SELECT audit.attach('helpdesk.support_action');

CREATE OR REPLACE FUNCTION helpdesk.record_support_action(p_student uuid, p_ticket uuid, p_action text, p_field text, p_old text, p_new text, p_reason text,
                                                          p_session text DEFAULT NULL, p_semester int DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); v uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a support act is made by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'SUPPORT_REASON: a support act on a student''s record says why' USING ERRCODE = '23514',
            HINT = 'Name the ticket, or what the student reported.';
    END IF;
    IF p_ticket IS NOT NULL AND NOT EXISTS (SELECT 1 FROM helpdesk.ticket WHERE id = p_ticket) THEN
        RAISE EXCEPTION 'no ticket is identified %', p_ticket USING ERRCODE = '23503';
    END IF;
    INSERT INTO helpdesk.support_action (student_id, agent_id, agent_office, ticket_id, action, field, old_value, new_value, reason, session, semester)
    VALUES (p_student, who, coalesce(office, 'ictagent'), p_ticket, p_action, p_field, p_old, p_new, btrim(p_reason), p_session, p_semester)
    RETURNING id INTO v;
    IF p_ticket IS NOT NULL THEN
        INSERT INTO helpdesk.ticket_event (ticket_id, actor_kind, actor_id, actor_name, action, from_value, to_value, detail)
        VALUES (p_ticket, 'AGENT', who, helpdesk.person_name(who), 'SUPPORT_' || p_action, left(p_old, 200), left(p_new, 200),
                left(coalesce(p_field || ' — ', '') || btrim(p_reason), 500));
        UPDATE helpdesk.ticket SET updated_at = now() WHERE id = p_ticket;
    END IF;
    RETURN v;
END $$;
COMMENT ON FUNCTION helpdesk.record_support_action(uuid, uuid, text, text, text, text, text, text, int) IS 'V334: write a support act to the ledger, with its reason, and on the ticket''s timeline when one is named; refused without a reason.';

-- ── 4 · a replacement photograph, read first ─────────────────────────────────────────────────────────────────────
CREATE TABLE people.student_photo (
    student_id    uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    content       bytea NULL,
    object_id     uuid NULL,
    content_type  text NOT NULL DEFAULT 'image/jpeg',
    bytes         int NOT NULL,
    replaced_by   uuid NULL,
    replaced_at   timestamptz NOT NULL DEFAULT now(),
    reason        text NULL,
    CONSTRAINT ck_student_photo_store CHECK ((content IS NULL) <> (object_id IS NULL)),
    CONSTRAINT ck_student_photo_type CHECK (content_type IN ('image/jpeg', 'image/png'))
);
COMMENT ON TABLE people.student_photo IS 'V334: the student''s passport photograph where it was replaced on the portal — in the object store where one is on, else in the row — read before the admission''s photograph by the one resolver every screen uses.';
SELECT audit.attach('people.student_photo');

-- ── 5 · the search the desk makes ────────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS ix_student_support_surname ON people.student (upper(surname), upper(other_names));
CREATE INDEX IF NOT EXISTS ix_student_support_jamb ON people.student (upper(jamb_reg_no)) WHERE jamb_reg_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_student_support_admission ON people.student (upper(admission_no)) WHERE admission_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_student_contact_phone ON people.student_contact (phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_student_contact_email ON people.student_contact (lower(email)) WHERE email IS NOT NULL;

-- the module roles read the new tables as they read the desk
GRANT SELECT ON helpdesk.support_action, people.student_photo TO app_auditor;
