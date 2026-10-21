-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V615 — A student in spillover is not held to the minimum credit load
--
--   V597 waived the minimum (the curriculum's CCMAS 15 or BMAS 18, or the level's) for a registration of carry-overs alone or of
--   GST/EPS courses alone; it still bound any registration carrying a current course of the programme. A student past the
--   programme's length — SP1, SP2 or beyond the spillover limit, as the cohort engine reads it (people.academic_position) — still
--   owes some of the final level's courses, and those read as current courses of the programme: a 400 Level SP1 student
--   registering the one 1-unit course still owed was refused REG_UNITS_BELOW_MINIMUM and the screen held SUBMIT back ("Minimum not
--   met"). On the University's word a spillover student registers what they still owe, whatever its units.
--
--   registration.load_kind reads SPILLOVER for the registration of a student in spillover, before anything else; the minimum binds a
--   NORMAL registration only (registration.submit_checks, unchanged), so it does not bind them, and the Academic Office's list of
--   registrations below the minimum (registration.below_minimum, unchanged) leaves them out. The maximum, the probation ceiling,
--   the SIWES semester, the fees stated and cleared and the GST fee gate bind as before. Nothing is stored: the kind is read from
--   the cohort engine's position at every submission. A student within the programme's length is held to the minimum as before.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V615: a student in spillover is not held to the minimum credit load', true);

CREATE OR REPLACE FUNCTION registration.load_kind(p_registration uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM registration.course_registration g
                               JOIN people.academic_position ap ON ap.student_id = g.student_id
                              WHERE g.id = p_registration AND ap.spillover_state LIKE 'SPILLOVER%') THEN 'SPILLOVER'
                WHEN bool_or(x.cat = 'NORMAL') THEN 'NORMAL'
                WHEN bool_or(x.cat = 'GST') THEN 'GST_EPS'
                WHEN count(*) > 0 THEN 'CARRY_OVER'
                ELSE 'NORMAL' END
      FROM (SELECT CASE WHEN e.entry_type IN ('CARRYOVER', 'DEFERRED', 'REPEAT') THEN 'CARRY_OVER'
                        WHEN e.entry_type = 'GST' OR c.kind = 'GST' THEN 'GST'
                        ELSE 'NORMAL' END AS cat
              FROM registration.entry e
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN catalogue.course c ON c.code = o.course_code
             WHERE e.registration_id = p_registration AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) x
$fn$;
COMMENT ON FUNCTION registration.load_kind(uuid) IS
    'V597, V615: SPILLOVER for the registration of a student the cohort engine reads in spillover (SP1, SP2, beyond the limit); else '
    'NORMAL where a live entry is a current course of the programme, GST_EPS where one is a current GST/EPS course, CARRY_OVER for '
    'carry-overs and deferred courses alone; the minimum credit load binds a NORMAL registration only';

COMMIT;
