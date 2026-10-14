-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V456 — Every ICT support agent opens the JUPEB record in support mode and its payments
--
--   · A ticket raised by a JUPEB candidate shows two buttons: Open the JUPEB Record in Support Mode and Payments. Since V347 an
--     agent reached JUPEB records only through a posting on the JUPEB Support queue, a University-wide posting or one scoped to
--     the JUPEB office, and did only what that posting carried — every other agent found the record "not found". V453 gave
--     every ICT support agent in service the support baseline on students; this gives the same on JUPEB records, as the user
--     asked of the student buttons ("active and available for all ICT support agents").
--   · helpdesk.agent_reaches_jupeb: a posting that reaches JUPEB records, or an ICT support agent in service
--     (helpdesk.agent_in_service, V453: the ictagent office today, and never posted or a live posting).
--   · helpdesk.agent_jupeb_capabilities: the capabilities of the postings that reach JUPEB records, and helpdesk.agent_baseline()
--     for an agent in service — open the record, its payments (investigate, verify with the gateway, refresh the entitlement,
--     regenerate the receipt). Editing the contact, resetting the password, raising tickets and the support audit stay the
--     posting's to give. Nothing is taken away.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V456: every ICT support agent opens the JUPEB record and its payments', true);

CREATE OR REPLACE FUNCTION helpdesk.agent_reaches_jupeb(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM helpdesk.agent_assignment a
                    WHERE a.person_id = p_person AND a.active
                      AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                      AND (a.queue_code = 'JUPEB_SUPPORT' OR a.scope_kind = 'GLOBAL' OR (a.scope_kind = 'OFFICE' AND lower(a.scope_ref) = 'jupeb')))
        OR helpdesk.agent_in_service(p_person)
$fn$;
COMMENT ON FUNCTION helpdesk.agent_reaches_jupeb(uuid) IS
  'V347, V456: an agent reaches JUPEB records through a posting on the JUPEB Support queue, a University-wide posting or one scoped to the JUPEB office — or as an ICT support agent in service.';

CREATE OR REPLACE FUNCTION helpdesk.agent_jupeb_capabilities(p_person uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT array_agg(DISTINCT c ORDER BY c)
                       FROM (SELECT unnest(a.capabilities) AS c
                               FROM helpdesk.agent_assignment a
                              WHERE a.person_id = p_person AND a.active
                                AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                                AND (a.queue_code = 'JUPEB_SUPPORT' OR a.scope_kind = 'GLOBAL' OR (a.scope_kind = 'OFFICE' AND lower(a.scope_ref) = 'jupeb'))
                             UNION
                             SELECT unnest(helpdesk.agent_baseline()) WHERE helpdesk.agent_in_service(p_person)) x), '{}'::text[])
$fn$;
COMMENT ON FUNCTION helpdesk.agent_jupeb_capabilities(uuid) IS
  'V347, V456: what an agent may do on JUPEB records — the capabilities of the live postings that reach them, and the support baseline (V453) for an ICT support agent in service.';

COMMIT;
