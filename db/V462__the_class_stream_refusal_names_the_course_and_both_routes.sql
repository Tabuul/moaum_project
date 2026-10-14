-- ═══════════════════════════════════════
-- V462 — The class-stream refusal names the course and both routes
--
-- V380 refused a registration line whose class is not of the student's own stream (registration.entry_stream_guard), and
-- V389 added the School of Postgraduate Studies' stream (PG) to people.student_stream. The refusal still knew only two:
-- anything that was not a CCE student was told "a full-time student does not register on a class of the Centre for
-- Continuing Education" — so a postgraduate student put on a full-time class (by the old-portal results import, or a desk)
-- was refused with words about the CCE, and the office went looking for a CCE problem. The refusal (same code,
-- REGISTRATION_STREAM) now names the course, what kind of class it is, and which classes the student's own route registers
-- on. The rule itself is unchanged.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V462: the class-stream refusal names the course and both routes', true);

CREATE OR REPLACE FUNCTION registration.entry_stream_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_class text; v_student text; v_code text;
BEGIN
    SELECT o.stream, o.course_code INTO v_class, v_code FROM catalogue.offering o WHERE o.id = NEW.offering_id;
    SELECT people.student_stream(r.student_id) INTO v_student FROM registration.course_registration r WHERE r.id = NEW.registration_id;
    IF v_class IS DISTINCT FROM v_student THEN
        RAISE EXCEPTION 'REGISTRATION_STREAM: % is %, and % registers only on %',
            coalesce(v_code, 'this class'),
            CASE v_class WHEN 'CCE' THEN 'a class of the Centre for Continuing Education'
                         WHEN 'PG' THEN 'a class of the School of Postgraduate Studies'
                         ELSE 'a full-time undergraduate class' END,
            CASE v_student WHEN 'CCE' THEN 'a student of the Centre for Continuing Education'
                           WHEN 'PG' THEN 'a postgraduate student'
                           ELSE 'a full-time undergraduate' END,
            CASE v_student WHEN 'CCE' THEN 'the Centre''s classes, in the CCE session'
                           WHEN 'PG' THEN 'the School''s postgraduate classes'
                           ELSE 'full-time undergraduate classes' END
            USING ERRCODE = '23514',
                  HINT = 'Register the student on the course''s class for their own route (the department, the Centre or the School opens it), or check the student''s entry mode.';
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION registration.entry_stream_guard() IS
  'V380, V462: a registration line only on a class of the student''s own stream (people.student_stream: REGULAR, CCE or PG); '
  'the refusal names the course, the class''s stream and the classes the student''s route registers on.';

COMMIT;
