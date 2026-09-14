-- ═══════════════════════════════════════════════════════════════════════════
-- V127 — open course registration for a session (create the offerings)
--
--   registration.student_menu lists a course only when a catalogue.offering (the
--   session instance of the course) exists for that session and semester. Until
--   now offerings were created only by the legacy results import and the demo
--   seed — so a live session had none of the uploaded courses, and a student saw
--   nothing (or leftover demo offerings). This opens registration for a session:
--   it creates an offering for every course the catalogue offers that semester
--   (from catalogue.course_offer), so the real programme/level courses appear.
--
--   Offerings are derived here from the approved structure in one deliberate
--   office action, so the audit trigger is disabled around the bulk insert (the
--   same way the migration backfills are). Idempotent — a course already offered
--   this session is skipped. SECURITY DEFINER so it runs as the owner (to insert
--   and to toggle the trigger); the session must already exist on the calendar.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION registration.open_course_registration(p_session text, p_semester int)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, catalogue, registration, ref, policy
AS $$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'course registration is opened by a person' USING ERRCODE = '23514';
    END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'no academic session % on the calendar — open the session first', p_session USING ERRCODE = '23503';
    END IF;

    ALTER TABLE catalogue.offering DISABLE TRIGGER trg_audit_catalogue_offering;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), c.code, p_session, p_semester
      FROM catalogue.course c
     WHERE c.semester = p_semester
       AND c.state <> 'ENDED'
       AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                        WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ALTER TABLE catalogue.offering ENABLE TRIGGER trg_audit_catalogue_offering;

    RETURN v_count;
END $$;

COMMENT ON FUNCTION registration.open_course_registration(text, int) IS
  'Open course registration for a session: create a catalogue.offering for every '
  'offered course of that semester, so student_menu shows the real programme/level '
  'courses. Idempotent; audit-light bulk; the session must exist on the calendar.';

COMMIT;
