-- ═══════════════════════════════════════
-- V604 — the registration draft refused to a graduated record only
--
--   V602 made registration.student_draft refuse every status outside study (ADMITTED, ACTIVE, PROBATION). The graduated record was
--   the point; the wider refusal broke a door that was never the student's: the deferment engine's academic effect makes the
--   deferred student's draft for the semester the deferment covers (DefermentIT, on CI for 9aa30489). The guard now refuses a
--   GRADUATED record alone; a deferred, suspended or dormant student is judged where they always were — the student's own doors in
--   the API (REG_STUDENT_NOT_ELIGIBLE at add, choose and submit) and the engines that act on their behalf.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V604: the registration draft refused to a graduated record only', true);

CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v uuid; s people.student; m record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    -- V602/V604: a graduated record is closed to course registration (and so to carry-overs) on every path; every other status is
    -- judged where it always was — the student's own doors in the API, the deferment and support engines in theirs
    IF s.status = 'GRADUATED' THEN
        RAISE EXCEPTION 'REG_STUDENT_NOT_ELIGIBLE: Course registration is unavailable because this academic record has been graduated.'
            USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF v IS NOT NULL THEN RETURN v; END IF;
    v := gen_random_uuid();
    INSERT INTO registration.course_registration (id, student_id, session, semester, level)
    VALUES (v, p_student, p_session, p_semester, s.current_level);
    FOR m IN SELECT * FROM registration.student_menu(p_student, p_session, p_semester) WHERE carryover LOOP
        -- V512: a GST/EPS carry-over waits for the GST fee: being a carry-over does not pass it
        IF registration.gst_course_hold(p_student, p_session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(v, m.offering_id); END IF;
    END LOOP;
    RETURN v;
END $function$;

COMMIT;
