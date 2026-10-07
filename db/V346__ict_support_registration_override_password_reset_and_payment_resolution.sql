-- ═══════════════════════════════════════════════════════════════════════════
-- V346 — ICT Support: course registration corrections with a recorded override, the secure password reset, and the
--        resolution of portal payment problems — on the desk V328 built and the student support V334 gave it
--
--   Nothing here is a second registration engine, a second password system or a second payment engine:
--     · a course is added, dropped, restored or a registration submitted from the support desk by the engine's own
--       functions (student_draft, student_choose, student_add, student_drop, student_submit), after every rule the
--       engine applies is checked and named (registration.support_add_checks / support_drop_checks). Where the only
--       rules in the way are the registration window or the engine's menu — a portal fault, a course mapped wrongly,
--       a registration interrupted — an agent whose posting carries OVERRIDE_REGISTRATION may set those two aside,
--       on the student's ticket, with a reason and a description; the rule that blocked it and why it was set aside
--       are written on the support ledger and the ticket. Fees, the GST gate, the unit ceiling, a locked
--       registration, a recorded mark, a carry-over and a closed semester are never set aside here. A dropped course
--       is marked DROPPED, never deleted; earlier sessions, results and transcripts are not reachable at all;
--     · the password is reset through the portal's own reset (iam.password_reset, the one-hour link to the address on
--       the record), or — at the desk, on a ticket — a temporary password the student's account holds as a hash,
--       random, valid for 24 hours, good for one sign-in and changed at it. The matriculation-number first password
--       is never offered while a temporary one stands. No password is recorded anywhere (the ledger refuses one);
--     · a payment is verified by the existing gateway verification (the API's PaymentsService.verify — the same
--       requery the reconciler sweeps with), and an entitlement refreshed by re-applying, idempotently, the effects the
--       confirmation itself applies (hostel, library, transcript) and recomputing the academic position. Nothing is
--       marked paid: finance.refresh_entitlement refuses a reference that is not confirmed, and creates no payment;
--     · every act is on helpdesk.support_action, which now carries the summary, the outcome, the override's normal
--       rule and description, the state before and after, the method, the authentication event and the source IP;
--       and on the ticket's timeline — which, until now, refused the SUPPORT_ events V334 wrote (fixed here);
--     · a posting's capabilities are now read for a student only from the postings whose scope covers that student.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V346: ICT support resolution', true);

-- ── 1 · the ticket's timeline takes the support acts filed on it ─────────────────────────────────────────────────
-- V334 filed SUPPORT_<act> events on the ticket a support act was done for, but the timeline's check did not know them:
-- every act done from a ticket was refused. The timeline now takes them.
ALTER TABLE helpdesk.ticket_event DROP CONSTRAINT IF EXISTS ck_hd_event_action;
ALTER TABLE helpdesk.ticket_event ADD CONSTRAINT ck_hd_event_action CHECK (
    action = ANY (ARRAY['SUBMITTED', 'OPENED', 'STATUS_CHANGED', 'ASSIGNED', 'REASSIGNED', 'ESCALATED', 'PRIORITY_CHANGED', 'INTERNAL_NOTE',
                        'UPDATE', 'RESOLUTION', 'REOPENED', 'CLOSED', 'ATTACHMENT', 'ROUTED', 'QUEUED', 'TRANSFERRED', 'WAITING',
                        'ESCALATED_TO_OFFICE', 'OFFICE_ANSWERED', 'RETURNED'])
    OR action ~ '^SUPPORT_[A-Z_]{3,40}$');

-- ── 2 · the capabilities a posting may carry ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT']
$$;
COMMENT ON FUNCTION helpdesk.support_capabilities() IS 'V334, extended by V346: what a support posting may carry. V346 adds the support override of the registration window and menu (never fees, units, GST, a mark or a locked registration), the password reset, the payment investigation, the gateway verification, the entitlement refresh, the receipt, raising a ticket for a student, and reading the desk''s own audit. Results, grades, refunds, fees, amounts, matriculation and admission decisions are never among them.';
ALTER TABLE helpdesk.agent_assignment DROP CONSTRAINT IF EXISTS ck_hd_aa_capabilities;
ALTER TABLE helpdesk.agent_assignment ADD CONSTRAINT ck_hd_aa_capabilities CHECK (capabilities <@ helpdesk.support_capabilities());

-- ── 3 · a capability reaches a student only through a posting whose scope covers them ────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.agent_capabilities_for(p_person uuid, p_student uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT array_agg(DISTINCT c ORDER BY c)
                       FROM people.student s
                       JOIN ref.programme p ON p.code = s.programme_code
                       JOIN helpdesk.agent_assignment a ON a.person_id = p_person AND a.active AND a.scope_kind <> 'OFFICE'
                              AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                              AND helpdesk.scope_covers(a.scope_kind, a.scope_ref, p.faculty_code, p.dept_code)
                       CROSS JOIN LATERAL unnest(a.capabilities) AS c
                      WHERE s.id = p_student), '{}'::text[])
$$;
COMMENT ON FUNCTION helpdesk.agent_capabilities_for(uuid, uuid) IS 'V346: what an agent may do on one student — the union of the capabilities of the live postings whose scope covers that student, so a capability granted on a faculty posting never reaches beyond the faculty through another posting''s wider scope.';

-- the students a capability reaches, as a list's filter: everything, or these faculties and departments
CREATE OR REPLACE FUNCTION helpdesk.agent_scope_for(p_person uuid, p_capability text)
RETURNS TABLE (global boolean, faculties text[], departments text[], words text)
LANGUAGE sql STABLE AS $$
    WITH live AS (
        SELECT a.scope_kind, upper(a.scope_ref) AS ref
          FROM helpdesk.agent_assignment a
         WHERE a.person_id = p_person AND a.active AND a.scope_kind <> 'OFFICE' AND p_capability = ANY (a.capabilities)
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
COMMENT ON FUNCTION helpdesk.agent_scope_for(uuid, text) IS 'V346: the scope of the postings that carry one capability — the filter a list applies (the student search reads it for VIEW_STUDENT, the payment search for INVESTIGATE_PAYMENT).';

-- ── 4 · the support ledger: what was done, what blocked it, before and after, how ───────────────────────────────
ALTER TABLE helpdesk.support_action
    ADD COLUMN summary           text    NULL,
    ADD COLUMN outcome           text    NOT NULL DEFAULT 'COMPLETED',
    ADD COLUMN override          boolean NOT NULL DEFAULT false,
    ADD COLUMN normal_rule       text    NULL,
    ADD COLUMN description       text    NULL,
    ADD COLUMN before_state      jsonb   NULL,
    ADD COLUMN after_state       jsonb   NULL,
    ADD COLUMN method            text    NULL,
    ADD COLUMN auth_event_id     uuid    NULL,
    ADD COLUMN payment_reference text    NULL,
    ADD COLUMN source_ip         inet    NULL;
ALTER TABLE helpdesk.support_action DROP CONSTRAINT IF EXISTS ck_hd_sa_action;
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_action CHECK (action IN (
    'CONTACT_EDITED', 'PERSONAL_EDITED', 'FAMILY_EDITED', 'PHOTO_REPLACED', 'CHANGE_REQUESTED',
    'REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED', 'RECORD_EXPORTED',
    'PASSWORD_RESET', 'PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED', 'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED',
    'ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED'));
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_outcome CHECK (outcome IN ('COMPLETED', 'NO_CHANGE', 'ESCALATED', 'RESOLVED'));
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_override CHECK (
    NOT override OR (action IN ('COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED')
                     AND nullif(btrim(normal_rule), '') IS NOT NULL AND nullif(btrim(description), '') IS NOT NULL));
-- a password is never on the ledger: a reset records how, never what
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_no_password CHECK (
    action <> 'PASSWORD_RESET' OR (old_value IS NULL AND new_value IS NULL AND method IN ('RESET_LINK', 'TEMPORARY_PASSWORD')));
CREATE INDEX IF NOT EXISTS ix_hd_sa_at ON helpdesk.support_action (at DESC);
CREATE INDEX IF NOT EXISTS ix_hd_sa_payment ON helpdesk.support_action (payment_reference) WHERE payment_reference IS NOT NULL;
COMMENT ON COLUMN helpdesk.support_action.override IS 'V346: the act set aside the registration window or the engine''s menu; normal_rule says what blocked it, reason why it was approved, description the problem found';
COMMENT ON COLUMN helpdesk.support_action.method IS 'V346: how — RESET_LINK or TEMPORARY_PASSWORD for a password (never the password), GATEWAY_VERIFY, ENTITLEMENT_REFRESH, RECEIPT for a payment';

-- the module an act belongs to, for the Support Action History
CREATE OR REPLACE FUNCTION helpdesk.support_module(p_action text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_action IN ('REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED') THEN 'COURSE_REGISTRATION'
                WHEN p_action = 'PASSWORD_RESET' THEN 'AUTHENTICATION'
                WHEN p_action IN ('PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED', 'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED') THEN 'PAYMENT'
                WHEN p_action IN ('ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED') THEN 'TICKET'
                WHEN p_action = 'RECORD_EXPORTED' THEN 'REPORTS'
                ELSE 'STUDENT_RECORD' END
$$;

DROP FUNCTION IF EXISTS helpdesk.record_support_action(uuid, uuid, text, text, text, text, text, text, int);
CREATE FUNCTION helpdesk.record_support_action(p_student uuid, p_ticket uuid, p_action text, p_field text, p_old text, p_new text, p_reason text,
                                               p_session text DEFAULT NULL, p_semester int DEFAULT NULL, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        d jsonb := coalesce(p_detail, '{}'::jsonb); v uuid; v_over boolean; v_summary text; v_rule text; v_words text; v_ip inet;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a support act is made by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'SUPPORT_REASON: a support act on a student''s record says why' USING ERRCODE = '23514',
            HINT = 'Name the ticket, or what the student reported.';
    END IF;
    IF p_ticket IS NOT NULL AND NOT EXISTS (SELECT 1 FROM helpdesk.ticket WHERE id = p_ticket) THEN
        RAISE EXCEPTION 'no ticket is identified %', p_ticket USING ERRCODE = '23503';
    END IF;
    v_over := coalesce((d->>'override')::boolean, false);
    v_summary := nullif(btrim(d->>'summary'), '');
    v_rule := nullif(btrim(d->>'normalRule'), '');
    IF v_over AND p_ticket IS NULL THEN
        RAISE EXCEPTION 'SUPPORT_OVERRIDE_TICKET: a support override is made on the student''s own ticket' USING ERRCODE = '23514',
            HINT = 'Open the student from their ticket, or raise one for them first.';
    END IF;
    BEGIN
        v_ip := nullif(current_setting('moaum.source_ip', true), '')::inet;
    EXCEPTION WHEN others THEN v_ip := NULL;
    END;
    INSERT INTO helpdesk.support_action (student_id, agent_id, agent_office, ticket_id, action, field, old_value, new_value, reason, session, semester,
                                         summary, outcome, override, normal_rule, description, before_state, after_state, method, auth_event_id,
                                         payment_reference, source_ip)
    VALUES (p_student, who, coalesce(office, 'ictagent'), p_ticket, p_action, p_field, p_old, p_new, btrim(p_reason), p_session, p_semester,
            v_summary, coalesce(d->>'outcome', 'COMPLETED'), v_over, v_rule, nullif(btrim(d->>'description'), ''), d->'before', d->'after',
            d->>'method', nullif(d->>'authEventId', '')::uuid, nullif(d->>'paymentReference', ''), v_ip)
    RETURNING id INTO v;
    IF p_ticket IS NOT NULL THEN
        v_words := CASE WHEN v_over
                        THEN 'NORMAL RULE: Registration blocked because ' || v_rule || E'\nSUPPORT ACTION: Override approved because ' || btrim(p_reason)
                             || coalesce(E'\nAction taken: ' || v_summary, '')
                        ELSE coalesce('Action taken: ' || v_summary || E'\n', '') || 'Reason: ' || btrim(p_reason) END;
        INSERT INTO helpdesk.ticket_event (ticket_id, actor_kind, actor_id, actor_name, action, from_value, to_value, detail)
        VALUES (p_ticket, 'AGENT', who, helpdesk.person_name(who), 'SUPPORT_' || p_action, left(p_old, 200), left(p_new, 200), left(v_words, 2000));
        UPDATE helpdesk.ticket SET updated_at = now() WHERE id = p_ticket;
    END IF;
    RETURN v;
END $$;
COMMENT ON FUNCTION helpdesk.record_support_action(uuid, uuid, text, text, text, text, text, text, int, jsonb) IS 'V334, extended by V346: write a support act to the ledger with its reason and, in p_detail, its summary, outcome, override (with the normal rule and the description, on a ticket), the state before and after, the method, the authentication event and the payment reference; filed on the ticket''s timeline as "Action taken" — for an override as NORMAL RULE / SUPPORT ACTION. Refused without a reason.';

-- ── 5 · the registration engine, from the support desk ───────────────────────────────────────────────────────────
-- a course put on a registration by a support override says so on the entry, so the student's own form keeps it
ALTER TABLE registration.entry
    ADD COLUMN support_override_at     timestamptz NULL,
    ADD COLUMN support_override_by     uuid        NULL,
    ADD COLUMN support_override_reason text        NULL;
ALTER TABLE registration.entry ADD CONSTRAINT ck_entry_support_override CHECK (
    (support_override_at IS NULL) = (support_override_by IS NULL)
    AND (support_override_at IS NULL OR nullif(btrim(support_override_reason), '') IS NOT NULL));
COMMENT ON COLUMN registration.entry.support_override_at IS 'V346: the course was put on the registration by an ICT Support override of the window or the menu (the ledger, helpdesk.support_action, says what blocked it and why it was approved); the student''s own form keeps it';

-- V314's student_choose, unchanged but for one thing: an entry a support override placed is kept when the student saves the form
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type NOT IN ('CARRYOVER','DEFERRED') AND support_override_at IS NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
    END LOOP;
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        -- V314: a GST or EPS course is registered only by a student whose GST fee is paid
        v_gate := registration.gst_gate(r.student_id, r.session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR m.kind = 'Elective' THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $$;

-- every rule the engine applies to adding a course, named and judged: what passes, what blocks, and whether a support
-- override may set it aside (only the registration window and the engine's menu)
CREATE OR REPLACE FUNCTION registration.support_add_checks(p_student uuid, p_session text, p_semester int, p_offering uuid)
RETURNS TABLE (ord int, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; o catalogue.offering; c catalogue.course; r registration.course_registration; sm policy.semester; m record;
        lim policy.level_limit; v_status text; v_units int; v_add int; v_gate text; v_pre text; w text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF o.id IS NOT NULL THEN SELECT * INTO c FROM catalogue.course WHERE code = o.course_code; END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    SELECT * INTO sm FROM policy.semester WHERE session = p_session AND number = p_semester;
    v_status := coalesce(r.status, 'NONE');
    w := CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END;
    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) x WHERE x.offering_id = p_offering LIMIT 1;

    ord := 1; rule := 'STUDENT_ACTIVE'; label := 'Student is active'; overridable := false; advisory := false;
    passed := coalesce(s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'), false);
    message := CASE WHEN s.id IS NULL THEN 'No such student.' WHEN passed THEN 'The student is ' || lower(s.status) || '.'
                    ELSE 'A student who is ' || lower(s.status) || ' does not register.' END;
    RETURN NEXT;

    ord := 2; rule := 'SESSION'; label := 'Correct academic session';
    passed := EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session);
    message := CASE WHEN passed THEN p_session || '.' ELSE 'No academic session ' || coalesce(p_session, '') || ' is on the calendar.' END;
    RETURN NEXT;

    ord := 3; rule := 'SEMESTER_RECORDS'; label := 'Semester not closed';
    passed := sm.id IS NULL OR sm.state NOT IN ('CLOSED', 'ARCHIVED');
    message := CASE WHEN passed THEN 'The ' || w || ' semester is ' || lower(replace(coalesce(sm.state, 'not on the calendar'), '_', ' ')) || '.'
                    ELSE 'The ' || w || ' semester of ' || p_session || ' is ' || lower(sm.state) || '; its registrations are history and are not changed.' END;
    RETURN NEXT;

    ord := 4; rule := 'COURSE_EXISTS'; label := 'Course exists';
    passed := o.id IS NOT NULL AND c.code IS NOT NULL;
    message := CASE WHEN passed THEN c.code || ' ' || c.title || ' (' || coalesce(o.units, c.units) || ' units).' ELSE 'No such course offering.' END;
    RETURN NEXT;

    ord := 5; rule := 'OFFERING_PERIOD'; label := 'Offered this session and semester';
    passed := o.id IS NOT NULL AND o.session = p_session AND o.semester = p_semester;
    message := CASE WHEN o.id IS NULL THEN 'No such course offering.'
                    WHEN passed THEN 'Offered in ' || o.session || ', ' || w || ' semester.'
                    ELSE c.code || ' is offered in ' || o.session || ', ' || CASE o.semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END
                         || ' semester — not in this registration''s session and semester.' END;
    RETURN NEXT;

    ord := 6; rule := 'COURSE_ACTIVE'; label := 'Course offering is active';
    passed := c.code IS NOT NULL AND c.state <> 'ENDED';
    message := CASE WHEN c.code IS NULL THEN 'No such course.' WHEN passed THEN 'The course is ' || lower(c.state) || '.' ELSE c.code || ' has ended (' || c.ended_on || ').' END;
    RETURN NEXT;

    ord := 7; rule := 'REGISTRATION_STATE'; label := 'Registration not locked';
    passed := v_status <> 'LOCKED';
    message := CASE WHEN v_status = 'NONE' THEN 'No registration yet; the engine drafts one.' WHEN passed THEN 'The registration is ' || lower(v_status) || '.'
                    ELSE 'This registration is locked and cannot be changed.' END;
    RETURN NEXT;

    ord := 8; rule := 'NOT_REGISTERED'; label := 'Not already on the registration';
    passed := NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering AND e.status <> 'DROPPED');
    message := CASE WHEN passed THEN CASE WHEN EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering)
                                          THEN 'Dropped earlier; adding it restores it.' ELSE 'Not on the registration.' END
                    ELSE coalesce(c.code, 'The course') || ' is already on the registration.' END;
    RETURN NEXT;

    ord := 9; rule := 'PROGRAMME_LEVEL'; label := 'Offered to the student''s programme and level'; overridable := true;
    passed := m.offering_id IS NOT NULL AND (NOT m.carryover OR v_status IN ('NONE', 'DRAFT', 'RETURNED'));
    message := CASE WHEN passed THEN coalesce(m.basis, c.kind, '') || ' for ' || s.programme_code || ' at ' || s.current_level || ' level.'
                    WHEN m.offering_id IS NOT NULL THEN 'A carry-over is placed by the engine when the registration is drafted; this registration is ' || lower(v_status) || '.'
                    WHEN c.code IS NULL THEN 'No such course.'
                    ELSE c.code || ' is not on the engine''s menu for ' || s.programme_code || ' at ' || s.current_level || ' level (a ' || c.level || ' level '
                         || lower(c.kind) || ' course of ' || c.dept_code || ').' END;
    RETURN NEXT;
    overridable := false;

    ord := 10; rule := 'UNITS'; label := 'Maximum credit load';
    SELECT * INTO lim FROM policy.level_limit WHERE level = coalesce(r.level, s.current_level);
    v_units := CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) END;
    v_add := coalesce(m.units, o.units, c.units, 0);
    passed := lim.level IS NULL OR v_units + v_add <= lim.max_units;
    message := CASE WHEN lim.level IS NULL THEN 'No unit limit is set for the level.'
                    WHEN passed THEN v_units || ' + ' || v_add || ' units, within the maximum of ' || lim.max_units || '.'
                    ELSE 'Adding it puts the registration at ' || (v_units + v_add) || ' units, over the maximum of ' || lim.max_units || ' at ' || lim.level
                         || ' level; drop a course first, or the Head of Department approves an overload.' END;
    RETURN NEXT;

    ord := 11; rule := 'REGISTRATION_WINDOW'; label := 'Registration window and late registration'; overridable := true;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    passed := v_gate IS NULL;
    message := coalesce(v_gate, 'Open.');
    RETURN NEXT;

    ord := 12; rule := 'ADD_DROP_PERIOD'; label := 'Add and drop period';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        passed := registration.add_drop_open(p_session, p_semester);
        message := CASE WHEN passed THEN 'Open.' ELSE 'Add and drop is not open for ' || p_session || ' semester ' || p_semester
                                                       || '; it runs while the semester is open, up to the late-registration deadline.' END;
    ELSE
        passed := true; message := 'Not needed: the registration is not yet submitted.';
    END IF;
    RETURN NEXT;
    overridable := false;

    ord := 13; rule := 'FEES'; label := 'Payment requirement';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        BEGIN
            passed := coalesce(finance.clears(p_student, p_session, 'REGISTRATION'), false);
            message := CASE WHEN passed THEN 'The Bursary clears the student for registration.' ELSE 'The Bursary has not cleared the student for registration in ' || p_session
                                                                                                   || '; refresh the payment entitlement if a payment is confirmed, else escalate to the Bursary.' END;
        EXCEPTION WHEN check_violation THEN
            passed := false; message := SQLERRM;
        END;
    ELSE
        advisory := true; passed := true;
        message := CASE WHEN finance.semester_cleared(p_student, p_session, p_semester) THEN 'The semester''s fees are cleared.'
                        ELSE 'The ' || w || ' semester''s fees are not cleared: the course goes on the draft, but the engine refuses the submission until they are.' END;
    END IF;
    RETURN NEXT;
    advisory := false;

    ord := 14; rule := 'GST'; label := 'GST/EPS requirement';
    v_gate := CASE WHEN c.code IS NULL THEN NULL ELSE registration.gst_gate(p_student, p_session, c.code) END;
    passed := v_gate IS NULL;
    message := coalesce(v_gate, CASE WHEN c.kind = 'GST' OR c.general_office IS NOT NULL THEN 'The GST fee is paid.' ELSE 'Not a GST/EPS course.' END);
    RETURN NEXT;

    ord := 15; rule := 'PREREQUISITES'; label := 'Prerequisites'; advisory := true; passed := true;
    SELECT string_agg(p.requires_code, ', ' ORDER BY p.requires_code) INTO v_pre FROM catalogue.course_prerequisite p WHERE p.course_code = c.code;
    message := CASE WHEN v_pre IS NULL THEN 'None recorded.' ELSE 'Recorded: ' || v_pre || '. The engine shows them; it does not refuse on them.' END;
    RETURN NEXT;

    ord := 16; rule := 'CORE_ELECTIVE'; label := 'Core or elective';
    message := CASE WHEN c.code IS NULL THEN '—' ELSE coalesce(m.basis, c.kind) || CASE WHEN c.kind = 'Elective' THEN ' — counts within the elective allowance.' ELSE '.' END END;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION registration.support_add_checks(uuid, text, int, uuid) IS 'V346: the rules the engine applies to adding a course, each judged by the engine''s own functions (registration_gate, add_drop_open, finance.clears, gst_gate, student_menu, units_of, level_limit). overridable marks the two a support override may set aside — the window and the menu; advisory rows inform and never block.';

-- add (or restore) a course through the engine; with an override, only the window and the menu set aside
CREATE OR REPLACE FUNCTION registration.support_add(p_student uuid, p_session text, p_semester int, p_offering uuid, p_override boolean, p_by uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE k record; v_rules jsonb := '[]'::jsonb; v_hard text; v_soft text[] := '{}'; r registration.course_registration; v_reg uuid; v_restored boolean;
        m record; o catalogue.offering; c catalogue.course; s people.student; v_type text; v_units int; v_status text; v_choice uuid[];
BEGIN
    FOR k IN SELECT * FROM registration.support_add_checks(p_student, p_session, p_semester, p_offering) LOOP
        v_rules := v_rules || jsonb_build_array(jsonb_build_object('ord', k.ord, 'rule', k.rule, 'label', k.label, 'passed', k.passed,
                                                                   'overridable', k.overridable, 'advisory', k.advisory, 'message', k.message));
        IF NOT k.passed AND NOT k.overridable AND v_hard IS NULL THEN v_hard := k.message; END IF;
        IF NOT k.passed AND k.overridable THEN v_soft := v_soft || k.message; END IF;
    END LOOP;
    IF v_hard IS NOT NULL THEN
        RAISE EXCEPTION 'REG_RULE: %', v_hard USING ERRCODE = '23514',
            HINT = 'The registration engine''s rule stands; a support override does not set it aside. Document it on the ticket and escalate it to the office that owns it.';
    END IF;
    IF cardinality(v_soft) > 0 AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', array_to_string(v_soft, ' ') USING ERRCODE = '23514',
            HINT = 'If this is a genuine portal problem, an agent whose posting carries the support override may set it aside, on the student''s ticket, with the reason.';
    END IF;
    IF cardinality(v_soft) > 0 AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    v_restored := r.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.offering_id = p_offering AND e.status = 'DROPPED');
    IF cardinality(v_soft) = 0 THEN
        -- nothing in the way: exactly what the student's own form or add/drop does
        IF r.id IS NULL OR r.status IN ('DRAFT', 'RETURNED') THEN
            v_reg := registration.student_draft(p_student, p_session, p_semester);
            v_choice := ARRAY(SELECT e.offering_id FROM registration.entry e
                               WHERE e.registration_id = v_reg AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED') AND e.status <> 'DROPPED' AND e.support_override_at IS NULL);
            PERFORM registration.student_choose(v_reg, v_choice || p_offering);
            IF NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = v_reg AND e.offering_id = p_offering AND e.status <> 'DROPPED') THEN
                RAISE EXCEPTION 'REG_RULE: the engine did not place the course on the draft' USING ERRCODE = '23514';
            END IF;
        ELSE
            PERFORM registration.student_add(p_student, p_session, p_semester, p_offering);
            v_reg := r.id;
        END IF;
    ELSE
        -- the window or the menu set aside, on the record: the engine's draft, the engine's entry, the override named on it
        v_reg := registration.student_draft(p_student, p_session, p_semester);
        SELECT * INTO r FROM registration.course_registration WHERE id = v_reg;
        SELECT * INTO s FROM people.student WHERE id = p_student;
        SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
        SELECT * INTO c FROM catalogue.course WHERE code = o.course_code;
        SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) x WHERE x.offering_id = p_offering LIMIT 1;
        v_units := coalesce(m.units, o.units, c.units);
        v_type := CASE WHEN m.offering_id IS NOT NULL AND m.carryover THEN CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END
                       WHEN c.kind = 'GST' OR m.basis = 'GST' THEN 'GST'
                       WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                       WHEN c.kind = 'Elective' OR m.basis = 'Elective' THEN 'ELECTIVE'
                       WHEN m.offering_id IS NULL AND c.dept_code IS DISTINCT FROM (SELECT p.dept_code FROM ref.programme p WHERE p.code = s.programme_code) THEN 'BORROWED'
                       ELSE 'CURRENT' END;
        v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, support_override_at, support_override_by, support_override_reason)
        VALUES (v_reg, p_offering, v_units, v_type, v_status, now(), p_by, btrim(p_reason))
        ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = EXCLUDED.status, units = EXCLUDED.units, entry_type = EXCLUDED.entry_type,
            support_override_at = EXCLUDED.support_override_at, support_override_by = EXCLUDED.support_override_by,
            support_override_reason = EXCLUDED.support_override_reason;
    END IF;
    RETURN jsonb_build_object('registrationId', v_reg, 'status', (SELECT x.status FROM registration.course_registration x WHERE x.id = v_reg),
                              'units', registration.units_of(v_reg), 'overridden', cardinality(v_soft) > 0, 'restored', v_restored,
                              'normalRule', nullif(array_to_string(v_soft, ' '), ''), 'rules', v_rules);
END $$;
COMMENT ON FUNCTION registration.support_add(uuid, text, int, uuid, boolean, uuid, text) IS 'V346: a course added (or a dropped one restored) from the support desk — by student_choose on a draft or student_add on a submitted registration when no rule blocks it; where only the window or the menu blocks it, with p_override, the engine''s draft and entry are written with the override named on the entry. Every other rule (student status, session, closed semester, offering period, ended course, lock, already registered, units, fees, GST) refuses with REG_RULE.';

-- every rule the engine applies to dropping a course
CREATE OR REPLACE FUNCTION registration.support_drop_checks(p_student uuid, p_session text, p_semester int, p_offering uuid)
RETURNS TABLE (ord int, rule text, label text, passed boolean, overridable boolean, advisory boolean, message text)
LANGUAGE plpgsql STABLE AS $$
DECLARE r registration.course_registration; e registration.entry; sm policy.semester; v_status text; v_gate text; lim policy.level_limit; v_units int; v_code text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    SELECT * INTO sm FROM policy.semester WHERE session = p_session AND number = p_semester;
    IF r.id IS NOT NULL THEN SELECT * INTO e FROM registration.entry x WHERE x.registration_id = r.id AND x.offering_id = p_offering; END IF;
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    v_status := coalesce(r.status, 'NONE');
    overridable := false; advisory := false;

    ord := 1; rule := 'REGISTRATION_EXISTS'; label := 'A registration to change';
    passed := r.id IS NOT NULL; message := CASE WHEN passed THEN 'The registration is ' || lower(v_status) || '.' ELSE 'No registration to change.' END;
    RETURN NEXT;
    ord := 2; rule := 'REGISTRATION_STATE'; label := 'Registration not locked';
    passed := v_status <> 'LOCKED'; message := CASE WHEN passed THEN 'Not locked.' ELSE 'This registration is locked and cannot be changed.' END;
    RETURN NEXT;
    ord := 3; rule := 'SEMESTER_RECORDS'; label := 'Semester not closed';
    passed := sm.id IS NULL OR sm.state NOT IN ('CLOSED', 'ARCHIVED');
    message := CASE WHEN passed THEN 'Not closed.' ELSE 'The semester is ' || lower(sm.state) || '; its registrations are history and are not changed.' END;
    RETURN NEXT;
    ord := 4; rule := 'ON_REGISTRATION'; label := 'On the current registration';
    passed := e.offering_id IS NOT NULL AND e.status <> 'DROPPED';
    message := CASE WHEN passed THEN coalesce(v_code, 'The course') || ' is ' || lower(e.status) || ' (' || e.units || ' units).'
                    ELSE coalesce(v_code, 'That course') || ' is not on the registration.' END;
    RETURN NEXT;
    ord := 5; rule := 'NOT_CARRYOVER'; label := 'Not a carry-over or deferred course';
    passed := e.offering_id IS NULL OR e.entry_type NOT IN ('CARRYOVER', 'DEFERRED');
    message := CASE WHEN passed THEN 'A ' || lower(coalesce(e.entry_type, 'current')) || ' course.'
                    WHEN e.entry_type = 'CARRYOVER' THEN 'A carry-over cannot be dropped; it must be repeated.'
                    ELSE 'A deferred course cannot be dropped; it is taken in the semester it is due.' END;
    RETURN NEXT;
    ord := 6; rule := 'NO_MARK'; label := 'No mark recorded';
    passed := NOT EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sc.student_id = p_student AND sh.offering_id = p_offering);
    message := CASE WHEN passed THEN 'No mark is recorded.' ELSE 'A mark is already recorded in this course; it is examination history and is not dropped.' END;
    RETURN NEXT;
    ord := 7; rule := 'REGISTRATION_WINDOW'; label := 'Registration window and late registration'; overridable := true;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    passed := v_gate IS NULL; message := coalesce(v_gate, 'Open.');
    RETURN NEXT;
    ord := 8; rule := 'ADD_DROP_PERIOD'; label := 'Add and drop period';
    IF v_status IN ('SUBMITTED', 'APPROVED') THEN
        passed := registration.add_drop_open(p_session, p_semester);
        message := CASE WHEN passed THEN 'Open.' ELSE 'Add and drop is not open for ' || p_session || ' semester ' || p_semester || '.' END;
    ELSE
        passed := true; message := 'Not needed: the registration is not yet submitted.';
    END IF;
    RETURN NEXT;
    overridable := false;
    ord := 9; rule := 'UNITS'; label := 'Minimum credit load'; advisory := true; passed := true;
    SELECT * INTO lim FROM policy.level_limit WHERE level = r.level;
    v_units := CASE WHEN r.id IS NULL THEN 0 ELSE registration.units_of(r.id) - CASE WHEN e.status IS NOT NULL AND e.status <> 'DROPPED' THEN e.units ELSE 0 END END;
    message := CASE WHEN lim.level IS NULL THEN 'No unit limit is set for the level.'
                    WHEN v_units >= lim.min_units THEN v_units || ' units after the drop, within the minimum of ' || lim.min_units || '.'
                    ELSE v_units || ' units after the drop, under the minimum of ' || lim.min_units || '; a draft so short is refused at submission.' END;
    RETURN NEXT;
END $$;

CREATE OR REPLACE FUNCTION registration.support_drop(p_student uuid, p_session text, p_semester int, p_offering uuid, p_override boolean, p_by uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE k record; v_rules jsonb := '[]'::jsonb; v_hard text; v_soft text[] := '{}'; r registration.course_registration;
BEGIN
    FOR k IN SELECT * FROM registration.support_drop_checks(p_student, p_session, p_semester, p_offering) LOOP
        v_rules := v_rules || jsonb_build_array(jsonb_build_object('ord', k.ord, 'rule', k.rule, 'label', k.label, 'passed', k.passed,
                                                                   'overridable', k.overridable, 'advisory', k.advisory, 'message', k.message));
        IF NOT k.passed AND NOT k.overridable AND v_hard IS NULL THEN v_hard := k.message; END IF;
        IF NOT k.passed AND k.overridable THEN v_soft := v_soft || k.message; END IF;
    END LOOP;
    IF v_hard IS NOT NULL THEN
        RAISE EXCEPTION 'REG_RULE: %', v_hard USING ERRCODE = '23514',
            HINT = 'The registration engine''s rule stands; a support override does not set it aside.';
    END IF;
    IF cardinality(v_soft) > 0 AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', array_to_string(v_soft, ' ') USING ERRCODE = '23514',
            HINT = 'If this is a genuine portal problem, an agent whose posting carries the support override may set it aside, on the student''s ticket, with the reason.';
    END IF;
    IF cardinality(v_soft) > 0 AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF cardinality(v_soft) = 0 AND r.status IN ('SUBMITTED', 'APPROVED') THEN
        PERFORM registration.student_drop(p_student, p_session, p_semester, p_offering);
    ELSE
        -- a draft's course, or the add/drop gate set aside on the record: marked DROPPED, as the engine's drop marks it — never deleted
        UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = r.id AND offering_id = p_offering;
    END IF;
    UPDATE registration.entry SET support_override_at = NULL, support_override_by = NULL, support_override_reason = NULL
     WHERE registration_id = r.id AND offering_id = p_offering AND status = 'DROPPED' AND support_override_at IS NOT NULL;
    RETURN jsonb_build_object('registrationId', r.id, 'status', r.status, 'units', registration.units_of(r.id), 'overridden', cardinality(v_soft) > 0,
                              'normalRule', nullif(array_to_string(v_soft, ' '), ''), 'rules', v_rules);
END $$;
COMMENT ON FUNCTION registration.support_drop(uuid, text, int, uuid, boolean, uuid, text) IS 'V346: a course dropped from the current registration from the support desk — by student_drop on a submitted registration, else marked DROPPED as the engine marks it; never deleted. A lock, a closed semester, a carry-over, a deferred course or a recorded mark refuse it (REG_RULE); only the window and the add/drop period may be set aside, with p_override.';

-- a registration submitted from the support desk: the window may be set aside; the engine's own submission checks the rest
CREATE OR REPLACE FUNCTION registration.support_submit(p_student uuid, p_session text, p_semester int, p_override boolean, p_by uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; sm policy.semester; s people.student; v_gate text; v_out text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT coalesce(s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION'), false) THEN
        RAISE EXCEPTION 'REG_RULE: a student who is % does not register', lower(coalesce(s.status, 'unknown')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'REG_RULE: no registration for % semester % to submit', p_session, p_semester USING ERRCODE = '23514'; END IF;
    SELECT * INTO sm FROM policy.semester WHERE session = p_session AND number = p_semester;
    IF sm.id IS NOT NULL AND sm.state IN ('CLOSED', 'ARCHIVED') THEN
        RAISE EXCEPTION 'REG_RULE: the semester is %; its registrations are history and are not changed', lower(sm.state) USING ERRCODE = '23514';
    END IF;
    v_gate := registration.registration_gate(p_student, p_session, p_semester);
    IF v_gate IS NOT NULL AND NOT coalesce(p_override, false) THEN
        RAISE EXCEPTION 'REG_BLOCKED: %', v_gate USING ERRCODE = '23514',
            HINT = 'If the registration was interrupted by a portal fault, an agent whose posting carries the support override may set the window aside, on the student''s ticket.';
    END IF;
    IF v_gate IS NOT NULL AND (p_by IS NULL OR nullif(btrim(coalesce(p_reason, '')), '') IS NULL) THEN
        RAISE EXCEPTION 'REG_OVERRIDE: an override names who approves it and why' USING ERRCODE = '23514';
    END IF;
    v_out := registration.student_submit(r.id);   -- the fees, the GST gate, the unit range and the probation ceiling: the engine's
    RETURN jsonb_build_object('registrationId', r.id, 'status', (SELECT x.status FROM registration.course_registration x WHERE x.id = r.id), 'result', v_out,
                              'units', registration.units_of(r.id), 'overridden', v_gate IS NOT NULL, 'normalRule', v_gate);
END $$;

-- ── 6 · the temporary password: random, time-limited, one sign-in, changed at it ─────────────────────────────────
ALTER TABLE iam.student_account
    ADD COLUMN temp_expires_at timestamptz NULL,
    ADD COLUMN temp_issued_by  uuid        NULL,
    ADD COLUMN temp_used_at    timestamptz NULL;
ALTER TABLE iam.student_account ADD CONSTRAINT ck_student_temp CHECK (
    (temp_expires_at IS NULL) = (temp_issued_by IS NULL)
    AND (temp_expires_at IS NULL OR must_change)
    AND (temp_used_at IS NULL OR temp_expires_at IS NOT NULL));
COMMENT ON COLUMN iam.student_account.temp_expires_at IS 'V346: the password hash is a temporary one ICT Support issued at the desk: random, good until this time and for one sign-in (temp_used_at), changed at it; while it stands the matriculation-number first password opens nothing';

-- ── 7 · the payment support: found fast, refreshed without a new payment ─────────────────────────────────────────
CREATE INDEX IF NOT EXISTS ix_ge_gateway_ref ON finance.gateway_event (gateway_ref) WHERE gateway_ref IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_we_reference ON finance.wallet_entry (reference) WHERE reference IS NOT NULL;

-- the Bursary's clearance, or nothing where no clearance scheme is in force (policy.clears refuses then, rather than assume)
CREATE OR REPLACE FUNCTION finance.clears_or_null(p_student uuid, p_session text, p_purpose text)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN finance.clears(p_student, p_session, p_purpose);
EXCEPTION WHEN check_violation THEN
    RETURN NULL;
END $$;

-- what a student's confirmed payments entitle them to in a session, as the engine reads it
CREATE OR REPLACE FUNCTION finance.entitlement_state(p_student uuid, p_session text)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'session', p_session, 'due', pos.due, 'paid', pos.paid, 'balance', pos.balance, 'paidInFull', pos.paid_in_full, 'hasArrears', pos.has_arrears,
        'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'),
        'semester1Cleared', finance.semester_cleared(p_student, p_session, 1),
        'semester2Cleared', finance.semester_cleared(p_student, p_session, 2),
        'gstEntitled', (SELECT g.entitled FROM finance.gst_entitlement(p_student, p_session) g),
        'gstState', (SELECT g.state FROM finance.gst_entitlement(p_student, p_session) g),
        'positionComputedAt', (SELECT ap.computed_at FROM people.academic_position ap WHERE ap.student_id = p_student))
      FROM finance.position(p_student, p_session) pos
$$;
COMMENT ON FUNCTION finance.entitlement_state(uuid, text) IS 'V346: the student''s entitlement in a session as the engine reads it from confirmed payments — the position, registration clearance, each semester, the GST entitlement — for the support desk''s diagnosis.';

-- re-apply, idempotently, what a confirmed payment entitles: never a payment, never a credit
CREATE OR REPLACE FUNCTION finance.refresh_entitlement(p_reference text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE r finance.payment_reference; v_applied text[] := '{}'; v_problems text[] := '{}'; v_trn text; v_n int; v_before jsonb;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PAY_REFERENCE: no student payment reference % was generated by this portal', p_reference USING ERRCODE = '23514';
    END IF;
    IF r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'PAY_NOT_CONFIRMED: reference % is not confirmed; an entitlement follows only a confirmed payment', r.reference USING ERRCODE = '23514',
            HINT = 'Verify it with the gateway first. If the gateway does not confirm it, escalate the ticket to the Bursary with the evidence; nothing is marked paid from the support desk.';
    END IF;
    v_before := finance.entitlement_state(r.student_id, r.session);
    IF r.purpose LIKE 'Transcript TRN-%' THEN
        v_trn := substr(r.purpose, 12, 14);
        UPDATE credentials.transcript_request t SET paid_at = now(),
               stage = CASE WHEN clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN 'READY' ELSE 'HELD_AT_CLEARANCE' END
         WHERE t.ref = v_trn AND t.paid_at IS NULL;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_applied := v_applied || CASE WHEN v_n > 0 THEN 'The transcript request is marked paid.' ELSE 'The transcript request already stood paid.' END;
    ELSIF r.purpose LIKE 'Hostel accommodation%' THEN
        BEGIN
            PERFORM hostel.confirm_by_reference(r.reference);
            v_applied := v_applied || 'The hostel booking stands confirmed against the payment.'::text;
        EXCEPTION WHEN check_violation THEN
            v_problems := v_problems || ('Hostel: ' || SQLERRM || ' — escalate to the Bursary and the Dean of Student Affairs.');
        END;
    ELSIF r.purpose LIKE 'Library fine%' THEN
        PERFORM library.settle_by_reference(r.reference);
        v_applied := v_applied || 'The library fine stands settled.'::text;
    ELSIF r.purpose LIKE 'Wallet top-up%' AND NOT EXISTS (SELECT 1 FROM finance.wallet_entry w WHERE w.reference = r.reference) THEN
        v_problems := v_problems || 'Wallet: the top-up is confirmed but no wallet credit stands against it; a credit is the Bursary''s to write — escalate the ticket to the Bursary.'::text;
    END IF;
    PERFORM people.refresh_academic_position(r.student_id);
    v_applied := v_applied || 'The academic position was recomputed from the record.'::text;
    RETURN jsonb_build_object('reference', r.reference, 'session', r.session, 'purpose', r.purpose, 'applied', to_jsonb(v_applied), 'problems', to_jsonb(v_problems),
                              'before', v_before, 'after', finance.entitlement_state(r.student_id, r.session));
END $$;
COMMENT ON FUNCTION finance.refresh_entitlement(text) IS 'V346: for a CONFIRMED student payment reference only — re-applies, idempotently, what its confirmation applies (the hostel booking, the library fine, the transcript request) and recomputes the academic position; registration, fees and GST clearance are read live from the confirmed reference. Never creates a payment, never credits a wallet, never confirms a reference: an unconfirmed one is refused (PAY_NOT_CONFIRMED).';

GRANT SELECT ON helpdesk.support_action TO app_auditor;

COMMIT;
