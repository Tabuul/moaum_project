-- ═══════════════════════════════════════
-- V521 — ICT Support opens the student's portal, as the student, read-only
--
--   To see what a student sees — the course registration screen, the fees, the examination card, a message the portal shows them —
--   an ICT support agent asked for the student's password or a screenshot. Now every agent in service opens the student's portal
--   from the support record, without the student's password, for a short while, and can change nothing from it:
--     · VIEW_STUDENT_PORTAL joins helpdesk.support_capabilities and the agent baseline (V453/V500): every agent in service, on every
--       student they reach; the Head of the Support Desk, the Director of ICT, admin and super as before;
--     · helpdesk.open_portal_view — a session of the portal's own (platform.session, the student's, office student) that ends after
--       its minutes (30), named in a support view (helpdesk.portal_view: the agent, the office, the reason, the ticket where one is
--       named), on the support ledger (STUDENT_PORTAL_VIEWED) and on the ticket's timeline; a merged record is not opened;
--     · the token the API issues for it names the agent (claim support_view): the API refuses every change made with it
--       (SUPPORT_VIEW_READ_ONLY) and runs its reads in read-only transactions, so nothing a student could do is done by the agent;
--     · helpdesk.end_portal_view — the agent leaves (or the session lapses): the portal session ends with it.
--   The student's password is never read, shown or changed; the student's own sessions are untouched.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V521: ICT Support opens the student''s portal, as the student, read-only', true);

-- ── the capability, and every agent in service holds it ──
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY',
                 'VIEW_STUDENT_PORTAL']
$$;
COMMENT ON FUNCTION helpdesk.support_capabilities() IS
  'V334, V346, V408, V471, V500, V521: what a support posting may carry. V521 adds opening the student''s portal as the student, read-only. Results, refunds, fees, amounts, matriculation and admission decisions are never among them.';

CREATE OR REPLACE FUNCTION helpdesk.agent_baseline()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT ARRAY['ALLOCATE_COURSES', 'CORRECT_LEVEL', 'INVESTIGATE_PAYMENT', 'MANAGE_REGISTRATION', 'PROGRESS_LEVEL', 'REGENERATE_RECEIPT',
                 'REMOVE_ALLOCATIONS', 'RESET_PASSWORD', 'SYNC_ENTITLEMENT', 'VERIFY_PAYMENT', 'VIEW_ALLOCATIONS', 'VIEW_LEVEL_HISTORY',
                 'VIEW_PAYMENTS', 'VIEW_PROGRAMME_STRUCTURE', 'VIEW_RESET_HISTORY', 'VIEW_STUDENT', 'VIEW_STUDENT_PORTAL']::text[]
$fn$;
COMMENT ON FUNCTION helpdesk.agent_baseline() IS
  'V453, V471, V500, V521: what every ICT support agent in service may do across the University — open a student in support mode, manage course registration, payment support (V453); view the programme structure and allocate courses (V471); reset a student''s password to the default credential, progress or correct a student''s academic level, and read the level-change and password-reset histories (V500); open the student''s portal as the student, read-only (V521). The bulk allocation import, editing the structure, the registration override, record edits, exports and the whole support audit are granted with a posting.';

-- ── the support ledger: the portal opened (the list restated from V500's) ──
ALTER TABLE helpdesk.support_action DROP CONSTRAINT ck_hd_sa_action;
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_action CHECK (action IN (
    'CONTACT_EDITED', 'PERSONAL_EDITED', 'FAMILY_EDITED', 'PHOTO_REPLACED', 'CHANGE_REQUESTED', 'REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED',
    'COURSE_RESTORED', 'REGISTRATION_SUBMITTED', 'RECORD_EXPORTED', 'PASSWORD_RESET', 'ACCOUNT_UNLOCKED', 'PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED',
    'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'PAYMENT_RECEIPT_REPORTED', 'ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED',
    'LEVEL_PROGRESSED', 'LEVEL_CORRECTED', 'STUDENT_PORTAL_VIEWED'));
CREATE OR REPLACE FUNCTION helpdesk.support_module(p_action text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_action IN ('REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED') THEN 'COURSE_REGISTRATION'
                WHEN p_action IN ('PASSWORD_RESET', 'ACCOUNT_UNLOCKED', 'STUDENT_PORTAL_VIEWED') THEN 'AUTHENTICATION'
                WHEN p_action IN ('PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED', 'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'PAYMENT_RECEIPT_REPORTED') THEN 'PAYMENT'
                WHEN p_action IN ('ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED') THEN 'TICKET'
                WHEN p_action IN ('LEVEL_PROGRESSED', 'LEVEL_CORRECTED') THEN 'ACADEMIC_LEVEL'
                WHEN p_action = 'RECORD_EXPORTED' THEN 'REPORTS'
                ELSE 'STUDENT_RECORD' END
$$;

-- ── the support view of a student's portal ──
CREATE TABLE helpdesk.portal_view (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id   bytea NOT NULL UNIQUE REFERENCES platform.session (id) ON DELETE CASCADE,
    student_id   uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    agent_id     uuid NOT NULL,
    agent_office text NOT NULL,
    ticket_id    uuid NULL REFERENCES helpdesk.ticket (id) ON DELETE SET NULL,
    reason       text NOT NULL CHECK (length(btrim(reason)) >= 10),
    opened_at    timestamptz NOT NULL DEFAULT now(),
    ends_at      timestamptz NOT NULL,
    ended_at     timestamptz NULL,
    ended_reason text NULL,
    CONSTRAINT ck_portal_view_ended CHECK ((ended_at IS NULL) = (ended_reason IS NULL))
);
CREATE INDEX ix_portal_view_student ON helpdesk.portal_view (student_id, opened_at DESC);
CREATE INDEX ix_portal_view_agent ON helpdesk.portal_view (agent_id, opened_at DESC);
COMMENT ON TABLE helpdesk.portal_view IS
  'V521: each time an ICT support agent opened a student''s portal as the student, read-only — the portal session it ran on, the agent and office, the reason and ticket, when it opened, was to end and ended';
SELECT audit.attach('helpdesk.portal_view');

-- the agent opens the student's portal: a session of the portal's own for the student, ending after its minutes, and why
CREATE FUNCTION helpdesk.open_portal_view(p_student uuid, p_ticket uuid, p_reason text, p_session bytea, p_minutes integer)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; v_end timestamptz; v uuid;
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'SUPPORT_VIEW_OFFICE: the student''s portal is opened by ICT Support' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUPPORT_VIEW_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    IF s.duplicate_of IS NOT NULL THEN
        RAISE EXCEPTION 'SUPPORT_VIEW_MERGED: this record was merged into another; open the student''s current record' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUPPORT_VIEW_REASON: say why the student''s portal is opened, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    v_end := now() + make_interval(mins => greatest(5, least(coalesce(p_minutes, 30), 60)));
    INSERT INTO platform.session (id, person_id, active_office, absolute_end) VALUES (p_session, p_student, 'student', v_end);
    INSERT INTO helpdesk.portal_view (session_id, student_id, agent_id, agent_office, ticket_id, reason, ends_at)
    VALUES (p_session, p_student, who, office, p_ticket, btrim(p_reason), v_end)
    RETURNING id INTO v;
    PERFORM helpdesk.record_support_action(p_student, p_ticket, 'STUDENT_PORTAL_VIEWED', NULL, NULL, NULL, btrim(p_reason), NULL, NULL,
        jsonb_build_object('summary', 'Opened the student''s portal as the student, read-only, until ' || to_char(v_end AT TIME ZONE 'Africa/Lagos', 'HH24:MI'),
                           'method', 'SUPPORT_VIEW'));
    RETURN jsonb_build_object('viewId', v, 'endsAt', v_end, 'matricNo', s.matric_no, 'name', s.surname || ', ' || s.other_names);
END $$;
COMMENT ON FUNCTION helpdesk.open_portal_view(uuid, uuid, text, bytea, integer) IS
  'V521: an ICT support agent opens a student''s portal as the student: a portal session of the student''s (office student) ending after its minutes (5 to 60, 30 by default), the support view with the reason and ticket, and the act on the support ledger (STUDENT_PORTAL_VIEWED); the API makes the session read-only. Never a merged record; the student''s password is never read';

-- the agent leaves the student's portal: the portal session ends with the view
CREATE FUNCTION helpdesk.end_portal_view(p_view uuid, p_reason text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v helpdesk.portal_view;
BEGIN
    SELECT * INTO v FROM helpdesk.portal_view WHERE id = p_view FOR UPDATE;
    IF NOT FOUND THEN RETURN false; END IF;
    IF v.agent_id IS DISTINCT FROM who AND coalesce(office, '') NOT IN ('helpdeskhead', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'SUPPORT_VIEW_NOT_YOURS: another agent''s view of a student''s portal is ended by that agent or the Head of the Support Desk' USING ERRCODE = '42501';
    END IF;
    IF v.ended_at IS NOT NULL THEN RETURN false; END IF;
    UPDATE platform.session SET ended_at = now(), ended_reason = 'support view ended' WHERE id = v.session_id AND ended_at IS NULL;
    UPDATE helpdesk.portal_view SET ended_at = now(), ended_reason = coalesce(nullif(btrim(p_reason), ''), 'left by the agent') WHERE id = v.id;
    RETURN true;
END $$;
COMMENT ON FUNCTION helpdesk.end_portal_view(uuid, text) IS
  'V521: a support view of a student''s portal ended — by the agent who opened it, or the Head of the Support Desk — and its portal session with it';

COMMIT;
