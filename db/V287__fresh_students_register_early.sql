-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V287 — a planned semester opens early to the session's fresh students
--
--   A semester on the calendar is NOT_YET_OPEN, OPEN or CLOSED; returning students register in
--   an open one. Fresh students of a session — those whose entry session it is — may be let in
--   before the semester opens for everyone: the Academic Office dates
--   policy.semester.fresh_registration_from, and from that day the session's entrants register
--   their courses while the semester is still planned. registration.registration_gate says, for
--   one student and one semester, whether the door is open and if not why; the portal refuses on
--   it. A semester with no calendar row keeps the old behaviour (open), so nothing already running
--   changes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V287: a planned semester opens early to fresh students', true);

ALTER TABLE policy.semester ADD COLUMN IF NOT EXISTS fresh_registration_from date;
COMMENT ON COLUMN policy.semester.fresh_registration_from IS 'From this day the session''s fresh students (entry session = the session) register their courses although the semester is not yet open to everyone (V287). NULL: no early window.';

CREATE OR REPLACE FUNCTION registration.registration_gate(p_student uuid, p_session text, p_semester integer)
RETURNS text LANGUAGE sql STABLE AS $fn$
    WITH sm AS (SELECT * FROM policy.semester WHERE session = p_session AND number = p_semester),
         st AS (SELECT * FROM people.student WHERE id = p_student),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
             WHEN NOT EXISTS (SELECT 1 FROM sm) THEN NULL
             WHEN sm.state = 'OPEN' THEN NULL
             WHEN sm.state = 'CLOSED' THEN 'The ' || w.ord || ' semester of ' || p_session || ' is closed for registration.'
             WHEN sm.fresh_registration_from IS NOT NULL AND sm.fresh_registration_from <= current_date AND st.entry_session = p_session THEN NULL
             WHEN sm.fresh_registration_from IS NOT NULL AND st.entry_session = p_session
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' opens to fresh students on ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             WHEN sm.fresh_registration_from IS NOT NULL
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open; only the session''s fresh students register from ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             ELSE 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open for registration.'
           END
      FROM w LEFT JOIN sm ON true LEFT JOIN st ON true
$fn$;
COMMENT ON FUNCTION registration.registration_gate(uuid, text, integer) IS 'NULL when the student may register the semester now; otherwise why not: closed, not yet open, or open only to the session''s fresh students from a date (V287).';

COMMIT;
