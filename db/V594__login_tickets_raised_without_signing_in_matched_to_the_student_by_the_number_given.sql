-- V594: login tickets raised from the sign-in page matched to the student by the number given, so the desk resets them with the
-- rest — the Head of the ICT Support Desk's decision of 20 October 2026.
--
-- A person who cannot sign in asks from the sign-in page (V363): the request names no account (requester_kind PUBLIC), and V582's
-- reset from tickets refused every such ticket as "not a student's" — 611 open Login Issues tickets on the live desk that day, nearly
-- all of them asked from the sign-in page. Since 18 October the sign-in help form refuses a student-portal request whose number no
-- student holds (a132ddca), so the number on such a request is a number on the register.
--
--   * helpdesk.ticket_student: the student a ticket is for — the requester's own record for a student's ticket; for a request from
--     the sign-in page about the student portal, the one student whose matriculation number, admission number or former
--     matriculation number (V579) is the number given, read as the sign-in help reads it (upper case, no spaces); none when no
--     student or more than one holds it.
--   * helpdesk.ticket_reset_check (restated from V582's text) reads it: such a ticket is eligible as a student's own is, under the
--     same checks (the category, open, not in another operation, the student within the agent's scope, the student's own checks);
--     one whose number no student holds is TICKET_NO_STUDENT. The student is reset to the matriculation number, changed at the next
--     sign-in, as from any ticket. What the person typed is not proven: the Head of the ICT Support Desk chose to reset them all the
--     same, knowing that a person who typed another student's number could sign in as that student before the student does. Each
--     reset stays on the ticket it was made from, which keeps the name, number, e-mail and phone given.
--   * helpdesk.login_ticket_summary (restated from V582's text) counts the open tickets a student is found for, the requests from
--     the sign-in page and those whose number no student holds.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V594: login tickets raised without signing in matched to the student by the number given', true);

CREATE FUNCTION helpdesk.ticket_student(p_kind text, p_requester uuid, p_number text, p_details jsonb)
RETURNS uuid LANGUAGE sql STABLE AS $fn$
    WITH k AS (SELECT upper(regexp_replace(coalesce(p_number, ''), '\s+', '', 'g')) AS n),
    found AS (
        SELECT s.id FROM people.student s, k WHERE k.n <> '' AND upper(s.matric_no) = k.n AND s.duplicate_of IS NULL
        UNION
        SELECT s.id FROM people.student s, k WHERE k.n <> '' AND upper(s.admission_no) = k.n AND s.duplicate_of IS NULL
        UNION
        SELECT a.student_id FROM people.matric_alias a, k WHERE k.n <> '' AND upper(a.old_no) = k.n AND a.ended_at IS NULL
    )
    SELECT CASE
        WHEN p_kind = 'STUDENT' THEN p_requester
        -- a request from the sign-in page about the student portal (the sign-in help form's own test: the account type names it)
        WHEN p_kind = 'PUBLIC' AND lower(coalesce(p_details->>'account_type', '')) LIKE '%student%'
             THEN (SELECT CASE WHEN count(*) = 1 THEN (array_agg(f.id))[1] END FROM found f)
    END
$fn$;
COMMENT ON FUNCTION helpdesk.ticket_student(text, uuid, text, jsonb) IS
  'V594: the student a ticket is for — the requester''s own record, or for a student-portal request from the sign-in page the one student holding the number given (matriculation, admission or former matriculation number)';

-- ── the reset from tickets reads it (restated from V582's text) ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.ticket_reset_check(p_agent uuid, p_head boolean, p_tickets uuid[], p_bulk uuid DEFAULT NULL::uuid)
 RETURNS TABLE(ticket_id uuid, number text, category_code text, category text, ticket_status text, subject text, created_at timestamp with time zone, student_id uuid, full_name text, matric_no text, faculty text, department text, programme text, current_level integer, eligible boolean, code text, student_status text)
 LANGUAGE sql
 STABLE
AS $function$
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
          -- V594: the student the ticket is for — the requester's own record, or the one whose number a request from the sign-in page gave
          LEFT JOIN people.student s ON s.id = helpdesk.ticket_student(tk.requester_kind, tk.requester_id, tk.requester_number, tk.details)
          LEFT JOIN ref.programme p ON p.code = s.programme_code),
    -- the student's own checks (V559), the capability's scope read here instead of BULK_RESET_PASSWORD's
    stu AS MATERIALIZED (SELECT * FROM helpdesk.bulk_reset_check(p_agent, true, ARRAY(SELECT DISTINCT t.sid FROM t WHERE t.sid IS NOT NULL AND t.sees))),
    j AS (
        SELECT t.*, stu.full_name, stu.matric_no, stu.faculty AS sfaculty, stu.department AS sdepartment, stu.programme AS sprogramme,
               stu.current_level, stu.status AS sstatus, stu.code AS scode,
               (p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR t.faculty_code = ANY (sc.faculties) OR t.dept_code = ANY (sc.departments))) AS reach,
               CASE WHEN NOT t.sees THEN 'TICKET_NOT_FOUND'
                    WHEN NOT t.cat_ok THEN 'TICKET_NOT_LOGIN'
                    WHEN t.requester_kind = 'PUBLIC' AND t.sid IS NULL THEN 'TICKET_NO_STUDENT'
                    WHEN t.requester_kind NOT IN ('STUDENT', 'PUBLIC') OR t.sid IS NULL THEN 'TICKET_NOT_STUDENT'
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
$function$;

-- ── the desk's login figures read it (restated from V582's text) ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.login_ticket_summary(p_agent uuid, p_head boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH t AS MATERIALIZED (
        SELECT tk.id, tk.status, tk.assigned_to, tk.requester_kind, tk.created_at, tk.priority, tk.resolved_at,
               helpdesk.ticket_student(tk.requester_kind, tk.requester_id, tk.requester_number, tk.details) AS student_id
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
        -- V594: the open tickets a student is found for (their own, or by the number a request from the sign-in page gave), and
        -- the requests from the sign-in page whose number no student holds
        'students', (SELECT count(*) FROM o WHERE o.student_id IS NOT NULL),
        'unmatched', (SELECT count(*) FROM o WHERE o.requester_kind = 'PUBLIC' AND o.student_id IS NULL),
        'public', (SELECT count(*) FROM o WHERE o.requester_kind = 'PUBLIC'),
        'inOperation', (SELECT count(*) FROM last_op WHERE last_op.status = 'PENDING'),
        'failed', (SELECT count(*) FROM last_op WHERE last_op.status = 'FAILED'),
        'overdue', (SELECT count(*) FROM o WHERE helpdesk.due_at(o.created_at, o.priority) < now()),
        'resetToday', (SELECT count(*) FROM helpdesk.bulk_reset_ticket x JOIN t ON t.id = x.ticket_id
                        WHERE x.status = 'RESOLVED' AND x.resolved_at >= date_trunc('day', now() AT TIME ZONE 'Africa/Lagos') AT TIME ZONE 'Africa/Lagos'))
$function$;

COMMIT;
