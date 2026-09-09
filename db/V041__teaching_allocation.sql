-- ═══════════════════════════════════════════════════════════════════════════
-- V041 — teaching allocation (the Head of Department's act)
--
--   Assigning a lecturer to an offering is the hinge of the results path: it
--   names who teaches the course and, at the same moment, who will verify the
--   marks — because the person who enters the marks may not be the person who
--   verifies them, so the second examiner has to exist before the marks do.
--   Assigning the lecturer also opens the score sheet, when the examination
--   session for that session and semester is already open.
--
--   The approved teaching maximum is 12 units. An assignment beyond it is
--   allowed but only deliberately, as an overload, which is recorded as such.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION catalogue.allocate_offering(p_offering uuid, p_lecturer uuid, p_second uuid, p_overload_ok boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    o        catalogue.offering;
    who      uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_units  int;
    v_load   int;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a teaching allocation is made by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such offering' USING ERRCODE = '23503';
    END IF;
    IF p_lecturer IS NULL THEN
        RAISE EXCEPTION 'an allocation names the lecturer who teaches it' USING ERRCODE = '23514';
    END IF;
    IF p_second IS NOT NULL AND p_second = p_lecturer THEN
        RAISE EXCEPTION 'the second examiner cannot be the lecturer' USING ERRCODE = '23514',
            HINT = 'The person who enters the marks may not be the person who verifies them.';
    END IF;

    SELECT c.units INTO v_units FROM catalogue.course c WHERE c.code = o.course_code;
    SELECT coalesce(sum(c2.units), 0) INTO v_load
      FROM catalogue.offering o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
     WHERE o2.lecturer_id = p_lecturer AND o2.session = o.session AND o2.semester = o.semester AND o2.id <> p_offering;
    IF v_load + coalesce(v_units, 0) > 12 AND NOT p_overload_ok THEN
        RAISE EXCEPTION 'this assignment puts the lecturer at % units, over the approved maximum of 12', v_load + coalesce(v_units, 0)
            USING ERRCODE = '23514', HINT = 'Assign it as an overload if the department intends it; the overload is on the record and reported to the Dean.';
    END IF;

    UPDATE catalogue.offering
       SET lecturer_id = p_lecturer, second_examiner_id = p_second, allocated_on = current_date
     WHERE id = p_offering;

    -- assigning the lecturer opens the score sheet, if the examination session is open and none exists yet
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), p_offering, es.id, es.sheets_due
      FROM assessment.exam_session es
     WHERE es.session = o.session AND es.semester = o.semester AND es.state = 'OPEN'
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = p_offering);
END $$;
