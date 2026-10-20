-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V582 — Password resets from support tickets
--
--   Most of the desk's tickets are students who cannot sign in. The single reset works one ticket at a time (V485), and the bulk
--   reset (V559, V563) works on students the agent searches for — any student within the posting's scope. This is the other
--   way: the TICKET is the reason and the only door. The agent filters the desk's queue to login and password tickets, ticks
--   them, and the students who raised them are reset to the default student credential (the matriculation number, changed at
--   the next sign-in) by the same reset service and worker:
--     · helpdesk.category.password_reset_eligible says which categories are login and password issues (Login Issues on; the
--       Director of ICT switches others on — an account-locked category, say — without a change of code);
--     · capability BULK_RESET_FROM_TICKETS, granted on a posting with its scope and outside the baseline (the Head of the
--       Support Desk, the Director of ICT and the administrators hold it for the University); the student bulk reset's
--       BULK_RESET_PASSWORD is not needed for it, and does not give it;
--     · helpdesk.ticket_reset_check(agent, head, tickets): for each ticket asked — never a student — whether it may be reset
--       and why not: a ticket the agent cannot see (said as not found), not a login or password category, not a student's,
--       resolved or closed, already in an operation, its reset already done, the student outside the capability's scope,
--       and every check of the student's own (V559: not found, no matriculation number, a status not reset, merged, the
--       reset switched off);
--     · helpdesk.start_ticket_reset: the eligible tickets, checked again under lock, grouped by student — one reset for each
--       student however many tickets they raised — as a bulk reset of source TICKETS (PWR-TKT/YYYY/NNNNNN; start_bulk_reset
--       restated with the source), each ticket held in helpdesk.bulk_reset_ticket; a ticket is in one waiting operation at
--       most, so two agents ticking it at once reset it once;
--     · the worker resets each student once and resolves every ticket of theirs; a student not reset leaves their tickets
--       unresolved with the reason (helpdesk.bulk_reset_ticket FAILED), for the desk to take up;
--     · helpdesk.ticket_password_resets(ticket): the ticket's reset history (bulk and single), never a password.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V582: password resets from support tickets', true);

-- ── 1 · which categories are login and password issues; the capability ──────────────────────────────────────────────────
ALTER TABLE helpdesk.category ADD COLUMN password_reset_eligible boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN helpdesk.category.password_reset_eligible IS
  'V582: a login or password category — its students'' open tickets may be reset from the desk''s queue (Reset selected passwords).';
UPDATE helpdesk.category SET password_reset_eligible = true WHERE code = 'LOGIN';

CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY',
                 'VIEW_STUDENT_PORTAL',
                 -- V559: many students reset to the default credential in one operation, within the posting's scope
                 'BULK_RESET_PASSWORD',
                 -- V582: the students of the login and password tickets the agent ticks, reset from the desk's queue
                 'BULK_RESET_FROM_TICKETS']
$function$;

-- ── 2 · an operation's source, and its tickets ──────────────────────────────────────────────────────────────────────────
ALTER TABLE helpdesk.bulk_reset ADD COLUMN source text NOT NULL DEFAULT 'STUDENTS' CHECK (source IN ('STUDENTS', 'TICKETS'));
COMMENT ON COLUMN helpdesk.bulk_reset.source IS
  'V582: STUDENTS — the agent chose the students (V559); TICKETS — the students of the login and password tickets ticked on the queue (PWR-TKT/…)';

CREATE TABLE helpdesk.bulk_reset_ticket (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bulk_id      uuid NOT NULL REFERENCES helpdesk.bulk_reset (id) ON DELETE CASCADE,
    item_id      uuid NOT NULL REFERENCES helpdesk.bulk_reset_item (id) ON DELETE CASCADE,
    ticket_id    uuid NOT NULL REFERENCES helpdesk.ticket (id) ON DELETE CASCADE,
    status       text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'RESOLVED', 'UNRESOLVED', 'FAILED')),
    note         text NULL,
    resolved_at  timestamptz NULL,
    UNIQUE (bulk_id, ticket_id)
);
-- a ticket in one waiting operation at most: two agents ticking it at once reset its student once
CREATE UNIQUE INDEX ux_bulk_reset_ticket_pending ON helpdesk.bulk_reset_ticket (ticket_id) WHERE status = 'PENDING';
CREATE INDEX ix_bulk_reset_ticket_item ON helpdesk.bulk_reset_ticket (item_id);
CREATE INDEX ix_bulk_reset_ticket_ticket ON helpdesk.bulk_reset_ticket (ticket_id);
SELECT audit.attach('helpdesk.bulk_reset_ticket');
COMMENT ON TABLE helpdesk.bulk_reset_ticket IS
  'V582: each ticket of a reset from tickets — its student''s item, and what became of the ticket: RESOLVED with the reset, UNRESOLVED (the student was reset; the ticket was settled elsewhere first), FAILED (the student was not reset, with why; the ticket stays open)';

/* a student not reset leaves their tickets unresolved, with the reason the operation gives */
CREATE FUNCTION helpdesk.bulk_reset_ticket_failed() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.status = 'FAILED' AND OLD.status IS DISTINCT FROM 'FAILED' THEN
        UPDATE helpdesk.bulk_reset_ticket SET status = 'FAILED', note = coalesce(NEW.failure_words, NEW.failure_code)
         WHERE item_id = NEW.id AND status = 'PENDING';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_bulk_reset_item_tickets AFTER UPDATE OF status ON helpdesk.bulk_reset_item
    FOR EACH ROW EXECUTE FUNCTION helpdesk.bulk_reset_ticket_failed();

-- ── 3 · whether each ticket may be reset ────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION helpdesk.ticket_reset_check(p_agent uuid, p_head boolean, p_tickets uuid[], p_bulk uuid DEFAULT NULL)
RETURNS TABLE (ticket_id uuid, number text, category_code text, category text, ticket_status text, subject text, created_at timestamptz,
               student_id uuid, full_name text, matric_no text, faculty text, department text, programme text, current_level int,
               eligible boolean, code text, student_status text)
LANGUAGE sql STABLE AS $fn$
    WITH them AS (SELECT DISTINCT x AS id FROM unnest(p_tickets) x WHERE x IS NOT NULL),
    sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(p_agent, 'BULK_RESET_FROM_TICKETS')),
    t AS MATERIALIZED (
        SELECT th.id AS asked, tk.id, tk.number, tk.status, tk.subject, tk.created_at, tk.requester_kind, tk.requester_id, c.code AS ccode, c.name AS cname,
               coalesce(c.password_reset_eligible, false) AS cat_ok,
               tk.id IS NOT NULL AND (p_head OR helpdesk.can_view(p_agent, tk.id)) AS sees,
               p.faculty_code, p.dept_code, s.id AS sid
          FROM them th
          LEFT JOIN helpdesk.ticket tk ON tk.id = th.id
          LEFT JOIN helpdesk.category c ON c.id = tk.category_id
          LEFT JOIN people.student s ON tk.requester_kind = 'STUDENT' AND s.id = tk.requester_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code),
    -- the student's own checks (V559), the capability's scope read here instead of BULK_RESET_PASSWORD's
    stu AS MATERIALIZED (SELECT * FROM helpdesk.bulk_reset_check(p_agent, true, ARRAY(SELECT DISTINCT t.sid FROM t WHERE t.sid IS NOT NULL AND t.sees))),
    j AS (
        SELECT t.*, stu.full_name, stu.matric_no, stu.faculty AS sfaculty, stu.department AS sdepartment, stu.programme AS sprogramme,
               stu.current_level, stu.status AS sstatus, stu.code AS scode,
               (p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR t.faculty_code = ANY (sc.faculties) OR t.dept_code = ANY (sc.departments))) AS reach,
               CASE WHEN NOT t.sees THEN 'TICKET_NOT_FOUND'
                    WHEN NOT t.cat_ok THEN 'TICKET_NOT_LOGIN'
                    WHEN t.requester_kind <> 'STUDENT' OR t.sid IS NULL THEN 'TICKET_NOT_STUDENT'
                    WHEN t.status IN ('RESOLVED', 'CLOSED') THEN 'TICKET_SETTLED'
                    WHEN EXISTS (SELECT 1 FROM helpdesk.bulk_reset_ticket x WHERE x.ticket_id = t.id AND x.status = 'PENDING' AND x.bulk_id IS DISTINCT FROM p_bulk) THEN 'TICKET_IN_OPERATION'
                    WHEN t.status <> 'REOPENED'
                         AND (EXISTS (SELECT 1 FROM helpdesk.bulk_reset_ticket x WHERE x.ticket_id = t.id AND x.status IN ('RESOLVED', 'UNRESOLVED'))
                              OR EXISTS (SELECT 1 FROM helpdesk.support_action a WHERE a.ticket_id = t.id AND a.action = 'PASSWORD_RESET' AND a.method = 'DEFAULT_CREDENTIAL'))
                         THEN 'TICKET_RESET_DONE'
                    WHEN NOT (p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR t.faculty_code = ANY (sc.faculties) OR t.dept_code = ANY (sc.departments))) THEN 'OUT_OF_SCOPE'
                    WHEN stu.code IS DISTINCT FROM 'ELIGIBLE' THEN coalesce(stu.code, 'NOT_FOUND')
                    ELSE 'ELIGIBLE' END AS code
          FROM t LEFT JOIN stu ON stu.student_id = t.sid)
    -- a ticket the agent cannot see, or a student beyond the scope, is never described
    SELECT j.asked, CASE WHEN j.sees THEN j.number END, CASE WHEN j.sees THEN j.ccode END, CASE WHEN j.sees THEN j.cname END,
           CASE WHEN j.sees THEN j.status END, CASE WHEN j.sees THEN j.subject END, CASE WHEN j.sees THEN j.created_at END,
           CASE WHEN j.sees AND j.reach THEN j.sid END, CASE WHEN j.sees AND j.reach THEN j.full_name END, CASE WHEN j.sees AND j.reach THEN j.matric_no END,
           CASE WHEN j.sees AND j.reach THEN j.sfaculty END, CASE WHEN j.sees AND j.reach THEN j.sdepartment END,
           CASE WHEN j.sees AND j.reach THEN j.sprogramme END, CASE WHEN j.sees AND j.reach THEN j.current_level END,
           j.code = 'ELIGIBLE', j.code, CASE WHEN j.sees AND j.reach THEN j.sstatus END
      FROM j
$fn$;
COMMENT ON FUNCTION helpdesk.ticket_reset_check(uuid, boolean, uuid[], uuid) IS
  'V582: for each ticket asked, whether its student may be reset from it and why not — the ticket (seen by the agent, a login or password category, a student''s, open, not in an operation, its reset not done), the student within BULK_RESET_FROM_TICKETS''s scope, and the student''s own checks (V559). p_bulk: the operation asking again, its own tickets not counted as in an operation.';

-- ── 4 · the operation: start_bulk_reset with its source; the tickets grouped by student ─────────────────────────────────
DROP FUNCTION helpdesk.start_bulk_reset(uuid, text, boolean, uuid[], jsonb, text, boolean, text, boolean, text, uuid);
CREATE FUNCTION helpdesk.start_bulk_reset(p_agent uuid, p_office text, p_head boolean, p_students uuid[], p_tickets jsonb, p_reason text, p_unlock boolean, p_key text, p_resolve boolean DEFAULT false, p_resolution text DEFAULT NULL::text, p_retry_of uuid DEFAULT NULL::uuid, p_source text DEFAULT 'STUDENTS')
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_first uuid; v_ids uuid[]; v_n int; v_parts int; v_part int; v_ref text; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
        v_over int; v_wait boolean; c_part constant int := 1000; v_source text := coalesce(p_source, 'STUDENTS');
BEGIN
    IF p_key IS NOT NULL THEN
        SELECT b.id INTO v_id FROM helpdesk.bulk_reset b WHERE b.initiated_by = p_agent AND b.idempotency_key = p_key;
        IF FOUND THEN RETURN v_id; END IF;
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUPPORT_REASON_SHORT: say why the passwords are reset, in 10 characters or more' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_resolve, false) AND length(btrim(coalesce(p_resolution, ''))) < 20 THEN
        RAISE EXCEPTION 'BULK_RESOLUTION_SHORT: say what the students read on their resolved tickets, in 20 characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_retry_of IS NOT NULL AND NOT EXISTS (SELECT 1 FROM helpdesk.bulk_reset b WHERE b.id = p_retry_of AND (p_head OR b.initiated_by = p_agent)) THEN
        RAISE EXCEPTION 'BULK_RETRY_NOT_YOURS: only the one who made a bulk reset, the Head of the Support Desk or the Director of ICT tries its students again'
            USING ERRCODE = '23514';
    END IF;
    -- each student once, at the place first chosen
    v_ids := ARRAY(SELECT s.x FROM unnest(p_students) WITH ORDINALITY s(x, o) WHERE s.x IS NOT NULL GROUP BY s.x ORDER BY min(s.o));
    v_n := coalesce(cardinality(v_ids), 0);
    IF v_n = 0 THEN
        RAISE EXCEPTION 'BULK_RESET_EMPTY: choose the students to reset' USING ERRCODE = '23514';
    END IF;
    IF v_n > 10 * c_part THEN
        RAISE EXCEPTION 'BULK_RESET_TOO_MANY: at most 10,000 students in one request (% chosen); reset them in two', v_n USING ERRCODE = '23514';
    END IF;
    -- the figure for approval is read against every student chosen: a request in parts waits, and is decided, as a whole
    SELECT g.bulk_reset_approval_over INTO v_over FROM helpdesk.setting g WHERE g.row_no;
    v_wait := v_over IS NOT NULL AND v_n > v_over;
    v_parts := (v_n + c_part - 1) / c_part;
    FOR v_part IN 1 .. v_parts LOOP
        -- V582: an operation from tickets carries its own series of references
        v_ref := CASE WHEN v_source = 'TICKETS'
                      THEN 'PWR-TKT/' || v_year || '/' || lpad(platform.next_number('TICKET_PASSWORD_RESET', 'ICT_SUPPORT', v_year)::text, 6, '0')
                      ELSE 'BPR/' || v_year || '/' || lpad(platform.next_number('BULK_PASSWORD_RESET', 'ICT_SUPPORT', v_year)::text, 6, '0') END;
        v_id := gen_random_uuid();
        INSERT INTO helpdesk.bulk_reset (id, reference, initiated_by, office, head, reason, unlock, idempotency_key, total, status,
                                         resolve_tickets, resolution, retry_of, approval_over, series_id, part, parts, source)
        VALUES (v_id, v_ref, p_agent, p_office, p_head, btrim(p_reason), coalesce(p_unlock, true),
                CASE WHEN p_key IS NULL THEN NULL WHEN v_part = 1 THEN p_key ELSE p_key || ':' || v_part END, least(c_part, v_n - (v_part - 1) * c_part),
                CASE WHEN v_wait THEN 'AWAITING_APPROVAL' ELSE 'PENDING' END,
                coalesce(p_resolve, false), CASE WHEN coalesce(p_resolve, false) THEN btrim(p_resolution) END, p_retry_of,
                CASE WHEN v_wait THEN v_over END,
                CASE WHEN v_parts > 1 THEN coalesce(v_first, v_id) END, CASE WHEN v_parts > 1 THEN v_part END, CASE WHEN v_parts > 1 THEN v_parts END,
                v_source);
        v_first := coalesce(v_first, v_id);
        -- one item a student of this part, in the order chosen, with the login ticket named for it; an id that names no student is
        -- counted as failed by the tally (the total is of every id chosen), never skipped in silence
        INSERT INTO helpdesk.bulk_reset_item (bulk_id, student_id, ticket_id, ord)
        SELECT v_id, b.x, t.id, row_number() OVER (ORDER BY b.o)
          FROM unnest(v_ids[(v_part - 1) * c_part + 1 : v_part * c_part]) WITH ORDINALITY b(x, o)
          LEFT JOIN helpdesk.ticket t ON t.id = CASE WHEN (p_tickets ->> b.x::text) ~ '^[0-9a-fA-F-]{36}$' THEN (p_tickets ->> b.x::text)::uuid END
         WHERE EXISTS (SELECT 1 FROM people.student st WHERE st.id = b.x);
    END LOOP;
    IF v_wait THEN
        PERFORM helpdesk.tell_bulk_approvers(v_first);
    END IF;
    RETURN v_first;
END $function$;

COMMENT ON FUNCTION helpdesk.start_bulk_reset(uuid, text, boolean, uuid[], jsonb, text, boolean, text, boolean, text, uuid, text) IS
  'V559, V563, V565: a bulk password reset opened — each student once, in parts of 1,000, waiting for a Head''s approval above the setting; V582: its source (STUDENTS, BPR/…; TICKETS, PWR-TKT/…).';

/* the tickets ticked, checked again under lock, grouped by student: one reset for each student, every eligible ticket of theirs
   held by the operation and resolved with it; the tickets that may not be reset are left out and said */
CREATE FUNCTION helpdesk.start_ticket_reset(p_agent uuid, p_office text, p_head boolean, p_tickets uuid[], p_reason text, p_unlock boolean,
                                            p_key text, p_resolution text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; v_students uuid[]; v_primary jsonb; v_asked int; v_n int; v_t uuid[]; v_s uuid[]; v_c timestamptz[];
BEGIN
    IF p_key IS NOT NULL THEN
        SELECT b.id INTO v_id FROM helpdesk.bulk_reset b WHERE b.initiated_by = p_agent AND b.idempotency_key = p_key;
        IF FOUND THEN
            RETURN jsonb_build_object('id', v_id, 'reference', (SELECT reference FROM helpdesk.bulk_reset WHERE id = v_id), 'repeated', true);
        END IF;
    END IF;
    v_asked := coalesce(cardinality(ARRAY(SELECT DISTINCT x FROM unnest(p_tickets) x WHERE x IS NOT NULL)), 0);
    IF v_asked = 0 THEN RAISE EXCEPTION 'TICKET_RESET_EMPTY: tick the login and password tickets to reset' USING ERRCODE = '23514'; END IF;
    IF v_asked > 10000 THEN RAISE EXCEPTION 'TICKET_RESET_TOO_MANY: at most 10,000 tickets in one request (% ticked)', v_asked USING ERRCODE = '23514'; END IF;
    -- held while they are checked and taken: an agent ticking the same ticket waits, then finds it in this operation
    PERFORM 1 FROM helpdesk.ticket t WHERE t.id = ANY (p_tickets) ORDER BY t.id FOR UPDATE;
    SELECT array_agg(c.ticket_id ORDER BY c.created_at), array_agg(c.student_id ORDER BY c.created_at), array_agg(c.created_at ORDER BY c.created_at)
      INTO v_t, v_s, v_c
      FROM helpdesk.ticket_reset_check(p_agent, p_head, p_tickets) c WHERE c.eligible;
    IF v_t IS NULL THEN
        RAISE EXCEPTION 'TICKET_RESET_NONE: none of the % ticket(s) ticked may be reset from here; see why on the check', v_asked USING ERRCODE = '23514';
    END IF;
    -- each student once, the student of the oldest ticket first; the newest of a student's tickets is the one the reset is filed on
    v_students := ARRAY(SELECT o.student_id FROM unnest(v_t, v_s, v_c) o(ticket_id, student_id, created_at) GROUP BY o.student_id ORDER BY min(o.created_at));
    v_primary := (SELECT jsonb_object_agg(x.student_id, x.ticket_id)
                    FROM (SELECT DISTINCT ON (o.student_id) o.student_id, o.ticket_id FROM unnest(v_t, v_s, v_c) o(ticket_id, student_id, created_at)
                           ORDER BY o.student_id, o.created_at DESC) x);
    v_id := helpdesk.start_bulk_reset(p_agent, p_office, p_head, v_students, v_primary, p_reason, p_unlock, p_key, true, p_resolution, NULL, 'TICKETS');
    INSERT INTO helpdesk.bulk_reset_ticket (bulk_id, item_id, ticket_id)
    SELECT i.bulk_id, i.id, o.ticket_id
      FROM unnest(v_t, v_s) o(ticket_id, student_id)
      JOIN helpdesk.bulk_reset_item i ON i.student_id = o.student_id
      JOIN helpdesk.bulk_reset b ON b.id = i.bulk_id AND (b.id = v_id OR b.series_id = v_id)
    ON CONFLICT (bulk_id, ticket_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN jsonb_build_object('id', v_id, 'reference', (SELECT reference FROM helpdesk.bulk_reset WHERE id = v_id),
                              'tickets', v_n, 'students', cardinality(v_students), 'consolidated', v_n - cardinality(v_students),
                              'leftOut', v_asked - cardinality(v_t), 'status', (SELECT status FROM helpdesk.bulk_reset WHERE id = v_id));
END $fn$;
COMMENT ON FUNCTION helpdesk.start_ticket_reset(uuid, text, boolean, uuid[], text, boolean, text, text) IS
  'V582: a reset from the tickets ticked — each checked again under lock, the eligible grouped by student into one bulk reset of source TICKETS (PWR-TKT/…), every ticket held by the operation; refused when none may be reset.';

-- ── 5 · a ticket's reset history; the desk's login figures ──────────────────────────────────────────────────────────────
CREATE FUNCTION helpdesk.ticket_password_resets(p_ticket uuid)
RETURNS TABLE (at timestamptz, kind text, reference text, by_name text, result text, words text, force_change boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(i.processed_at, b.created_at), 'FROM_TICKETS', b.reference, helpdesk.person_name(b.initiated_by),
           CASE x.status WHEN 'PENDING' THEN CASE WHEN b.status = 'AWAITING_APPROVAL' THEN 'AWAITING_APPROVAL' ELSE 'PENDING' END
                         WHEN 'FAILED' THEN 'FAILED' ELSE 'RESET' END,
           CASE x.status WHEN 'FAILED' THEN x.note WHEN 'RESOLVED' THEN 'Reset to the default credential; the ticket resolved with it'
                         WHEN 'UNRESOLVED' THEN 'Reset to the default credential; the ticket had been settled already' END,
           x.status IN ('RESOLVED', 'UNRESOLVED')
      FROM helpdesk.bulk_reset_ticket x JOIN helpdesk.bulk_reset b ON b.id = x.bulk_id JOIN helpdesk.bulk_reset_item i ON i.id = x.item_id
     WHERE x.ticket_id = p_ticket
    UNION ALL
    SELECT a.at, CASE WHEN a.bulk_id IS NULL THEN 'SINGLE' ELSE 'BULK' END, (SELECT b.reference FROM helpdesk.bulk_reset b WHERE b.id = a.bulk_id),
           helpdesk.person_name(a.agent_id), 'RESET',
           CASE a.method WHEN 'DEFAULT_CREDENTIAL' THEN 'Reset to the default credential' WHEN 'RESET_LINK' THEN 'A one-hour reset link sent'
                         WHEN 'TEMPORARY_PASSWORD' THEN 'A temporary password issued' END,
           a.method IN ('DEFAULT_CREDENTIAL', 'TEMPORARY_PASSWORD')
      FROM helpdesk.support_action a
     WHERE a.ticket_id = p_ticket AND a.action = 'PASSWORD_RESET'
       AND NOT EXISTS (SELECT 1 FROM helpdesk.bulk_reset b WHERE b.id = a.bulk_id AND b.source = 'TICKETS')
     ORDER BY 1 DESC
$fn$;

/* the login and password tickets the agent works: open, unassigned, in progress, eligible, reset, failed, overdue */
CREATE FUNCTION helpdesk.login_ticket_summary(p_agent uuid, p_head boolean)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH t AS MATERIALIZED (
        SELECT tk.id, tk.status, tk.assigned_to, tk.requester_kind, tk.created_at, tk.priority, tk.resolved_at
          FROM helpdesk.ticket tk JOIN helpdesk.category c ON c.id = tk.category_id AND c.password_reset_eligible
         WHERE p_head OR helpdesk.can_view(p_agent, tk.id)),
    o AS (SELECT * FROM t WHERE t.status NOT IN ('RESOLVED', 'CLOSED')),
    last_op AS (
        SELECT DISTINCT ON (x.ticket_id) x.ticket_id, x.status FROM helpdesk.bulk_reset_ticket x JOIN o ON o.id = x.ticket_id
         ORDER BY x.ticket_id, x.id DESC)
    SELECT jsonb_build_object(
        'open', (SELECT count(*) FROM o),
        'unassigned', (SELECT count(*) FROM o WHERE o.assigned_to IS NULL),
        'inProgress', (SELECT count(*) FROM o WHERE o.status IN ('OPENED', 'IN_PROGRESS', 'REOPENED')),
        'students', (SELECT count(*) FROM o WHERE o.requester_kind = 'STUDENT'),
        'inOperation', (SELECT count(*) FROM last_op WHERE last_op.status = 'PENDING'),
        'failed', (SELECT count(*) FROM last_op WHERE last_op.status = 'FAILED'),
        'overdue', (SELECT count(*) FROM o WHERE helpdesk.due_at(o.created_at, o.priority) < now()),
        'resetToday', (SELECT count(*) FROM helpdesk.bulk_reset_ticket x JOIN t ON t.id = x.ticket_id
                        WHERE x.status = 'RESOLVED' AND x.resolved_at >= date_trunc('day', now() AT TIME ZONE 'Africa/Lagos') AT TIME ZONE 'Africa/Lagos'))
$fn$;

GRANT SELECT ON helpdesk.bulk_reset_ticket TO app_auditor, app_reporting;

COMMIT;
