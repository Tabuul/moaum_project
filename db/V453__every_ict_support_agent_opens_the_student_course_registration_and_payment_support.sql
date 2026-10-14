-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V453 — Every ICT support agent opens the student in support mode, course registration and payment support
--
--   · A ticket raised by a student shows three buttons: Open the Student in Support Mode, Course Registration and Payment
--     Support. Since V334/V346 what an agent could do on a student came only from their postings: the capabilities a posting
--     carries, for the students its scope covers. An agent never posted, posted to a queue only (an OFFICE scope), or posted
--     without these capabilities found the student "not found" or the act refused. The user: make the three "active and
--     available for all ICT support agents".
--   · Every ICT support agent in service now holds the support baseline across the University:
--         VIEW_STUDENT                                                         Open the Student in Support Mode
--         MANAGE_REGISTRATION                                                  Course Registration (view, add, drop)
--         VIEW_PAYMENTS, INVESTIGATE_PAYMENT, VERIFY_PAYMENT, SYNC_ENTITLEMENT,  Payment Support
--         REGENERATE_RECEIPT
--     In service: holds the ICT support agent office (ictagent) today, and either has never been posted or holds a live
--     posting — so an agent the Head took off the desk (helpdesk.deactivate_agent ends every posting) holds no baseline.
--   · Postings keep adding what the Head grants beyond it, within their scope: editing the record, the support override of a
--     closed registration window, password resets, exports, the support audit, course allocation. Nothing is taken away.
--   · helpdesk.agent_capabilities, agent_capabilities_for, agent_may_see_student and agent_student_scope restated with the
--     baseline (V334/V346 otherwise unchanged); every reader — the support profile, the student and payment searches, the
--     payment case, the clearance support view, the manual — follows.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V453: every ICT support agent opens the student, course registration and payment support', true);

CREATE OR REPLACE FUNCTION helpdesk.agent_baseline()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT ARRAY['INVESTIGATE_PAYMENT', 'MANAGE_REGISTRATION', 'REGENERATE_RECEIPT', 'SYNC_ENTITLEMENT', 'VERIFY_PAYMENT', 'VIEW_PAYMENTS', 'VIEW_STUDENT']::text[]
$fn$;
COMMENT ON FUNCTION helpdesk.agent_baseline() IS
  'V453: what every ICT support agent in service may do on any student — open the record in support mode, manage course registration, and payment support (view, investigate, verify, refresh entitlement, regenerate receipt).';

CREATE OR REPLACE FUNCTION helpdesk.agent_in_service(p_person uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM iam.office_assignment o
                    WHERE o.person_id = p_person AND o.office_code = 'ictagent'
                      AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date))
       AND (NOT EXISTS (SELECT 1 FROM helpdesk.agent_assignment a WHERE a.person_id = p_person)
            OR EXISTS (SELECT 1 FROM helpdesk.agent_assignment a
                        WHERE a.person_id = p_person AND a.active
                          AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)))
$fn$;
COMMENT ON FUNCTION helpdesk.agent_in_service(uuid) IS
  'V453: an ICT support agent in service — holds the ictagent office today and has never been posted or holds a live posting (an agent taken off the desk has every posting ended).';

-- the capabilities across the desk: the live postings', and the baseline for an agent in service
CREATE OR REPLACE FUNCTION helpdesk.agent_capabilities(p_person uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT array_agg(DISTINCT c ORDER BY c)
                       FROM (SELECT unnest(a.capabilities) AS c
                               FROM helpdesk.agent_assignment a
                              WHERE a.person_id = p_person AND a.active
                                AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                             UNION
                             SELECT unnest(helpdesk.agent_baseline()) WHERE helpdesk.agent_in_service(p_person)) x), '{}'::text[])
$fn$;

-- the capabilities on one student: the postings whose scope covers the student, and the baseline for an agent in service
CREATE OR REPLACE FUNCTION helpdesk.agent_capabilities_for(p_person uuid, p_student uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT array_agg(DISTINCT c ORDER BY c)
                       FROM (SELECT c
                               FROM people.student s
                               JOIN ref.programme p ON p.code = s.programme_code
                               JOIN helpdesk.agent_assignment a ON a.person_id = p_person AND a.active AND a.scope_kind <> 'OFFICE'
                                      AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                                      AND helpdesk.scope_covers(a.scope_kind, a.scope_ref, p.faculty_code, p.dept_code)
                               CROSS JOIN LATERAL unnest(a.capabilities) AS c
                              WHERE s.id = p_student
                             UNION
                             SELECT unnest(helpdesk.agent_baseline())
                              WHERE helpdesk.agent_in_service(p_person) AND EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student)) x), '{}'::text[])
$fn$;
COMMENT ON FUNCTION helpdesk.agent_capabilities_for(uuid, uuid) IS
  'V346, V453: the capabilities an agent holds on one student — those of the live postings whose scope covers the student, and the support baseline for an ICT support agent in service.';

-- a student is within reach of a posting whose scope covers them, and of every ICT support agent in service
CREATE OR REPLACE FUNCTION helpdesk.agent_may_see_student(p_person uuid, p_student uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (
        SELECT 1
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN helpdesk.agent_assignment a ON a.person_id = p_person AND a.active
                 AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
         WHERE s.id = p_student
           AND a.scope_kind <> 'OFFICE'
           AND helpdesk.scope_covers(a.scope_kind, a.scope_ref, p.faculty_code, p.dept_code))
        OR (helpdesk.agent_in_service(p_person) AND EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student))
$fn$;

-- the student scope in words for the desk-wide lists: the University for an ICT support agent in service
CREATE OR REPLACE FUNCTION helpdesk.agent_student_scope(p_person uuid)
RETURNS TABLE (global boolean, faculties text[], departments text[], words text)
LANGUAGE sql STABLE AS $fn$
    WITH live AS (
        SELECT a.scope_kind, upper(a.scope_ref) AS ref
          FROM helpdesk.agent_assignment a
         WHERE a.person_id = p_person AND a.active AND a.scope_kind <> 'OFFICE'
           AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)),
    fac AS (
        SELECT ref AS code FROM live WHERE scope_kind = 'FACULTY'
        UNION
        SELECT f.code FROM live l JOIN ref.faculty f ON l.scope_kind = 'COLLEGE' AND upper(coalesce(f.college_code, '')) = l.ref),
    dep AS (SELECT ref AS code FROM live WHERE scope_kind = 'DEPARTMENT'),
    everyone AS (SELECT EXISTS (SELECT 1 FROM live WHERE scope_kind = 'GLOBAL') OR helpdesk.agent_in_service(p_person) AS yes)
    SELECT (SELECT yes FROM everyone),
           coalesce((SELECT array_agg(code ORDER BY code) FROM fac), '{}'::text[]),
           coalesce((SELECT array_agg(code ORDER BY code) FROM dep), '{}'::text[]),
           CASE WHEN (SELECT yes FROM everyone) THEN 'The University'
                ELSE nullif(concat_ws('; ',
                        (SELECT string_agg(f.name, ', ' ORDER BY f.name) FROM fac JOIN ref.faculty f ON f.code = fac.code),
                        (SELECT string_agg(d.name, ', ' ORDER BY d.name) FROM dep JOIN ref.department d ON d.code = dep.code)), '') END
$fn$;

COMMIT;
