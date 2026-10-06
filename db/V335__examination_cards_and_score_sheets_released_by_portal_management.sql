-- ═══════════════════════════════════════
-- V335 — examination cards and score sheets are released by Portal Management, each by its own act
--
--   Opening an examination session did two things at once: it made every lecturer's score sheet, and from that moment
--   every student saw their papers and could download the examination card. The University wants each released when it
--   decides, from Portal Management, and not as a side effect of opening the session:
--
--     · opening the session sets it up (the Examinations Office timetables its papers); it releases nothing;
--     · "Release examination cards" shows students their papers and lets a student cleared by the Bursary download the
--       card; it can be withdrawn, and released again;
--     · "Release score sheets" makes the lecturers' sheets (the same rule as before: every offering with a lecturer; a
--       resit only where the main sheet is published) and from then on a lecturer allocated in the session gets a sheet
--       at once; it is not withdrawn, since marks may be on the sheets.
--
--   Sessions opened before this migration released both when they opened; they are recorded as released then.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V335: examination cards and score sheets released by Portal Management, each by its own act', true);

ALTER TABLE assessment.exam_session
    ADD COLUMN IF NOT EXISTS cards_released_at  timestamptz NULL,
    ADD COLUMN IF NOT EXISTS cards_released_by  uuid NULL,
    ADD COLUMN IF NOT EXISTS sheets_released_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS sheets_released_by uuid NULL;
COMMENT ON COLUMN assessment.exam_session.cards_released_at IS 'V335: when Portal Management released the examination cards; students see their papers and cards only from then. Cleared on a withdrawal.';
COMMENT ON COLUMN assessment.exam_session.sheets_released_at IS 'V335: when Portal Management released the score sheets to lecturers; the sheets were made then, and a lecturer allocated afterwards gets one at once.';

-- the sessions opened before: both were released when they opened
UPDATE assessment.exam_session
   SET cards_released_at = coalesce(opened_at, now()), sheets_released_at = coalesce(opened_at, now())
 WHERE state IN ('OPEN', 'CLOSED') AND cards_released_at IS NULL AND sheets_released_at IS NULL;

-- ── opening sets the session up and releases nothing ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.open_exam_session(p_id uuid)
RETURNS TABLE (sheets_made int, offerings_without_lecturer int)
LANGUAGE plpgsql
AS $$
DECLARE e assessment.exam_session; v_none int;
BEGIN
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found';
    END IF;
    IF e.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'the examination session is already %', lower(e.state) USING ERRCODE = 'check_violation';
    END IF;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL;
    UPDATE assessment.exam_session SET state = 'OPEN', opened_at = now() WHERE id = p_id;
    RETURN QUERY SELECT 0, v_none;
END;
$$;
COMMENT ON FUNCTION assessment.open_exam_session(uuid) IS 'V197/V335: open an examination session — set up for timetabling; the examination cards and the score sheets are released by their own acts.';

-- ── the score sheets, released to the lecturers ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.release_exam_sheets(p_id uuid)
RETURNS TABLE (sheets_made int, offerings_without_lecturer int)
LANGUAGE plpgsql
AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.exam_session; v_made int; v_none int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'score sheets are released by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found'; END IF;
    IF e.state <> 'OPEN' THEN
        RAISE EXCEPTION 'EXAM_NOT_OPEN: the examination session is %; its score sheets are released once it is open', lower(e.state) USING ERRCODE = '23514';
    END IF;
    IF e.sheets_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'EXAM_SHEETS_RELEASED: the score sheets of this session were released on %', to_char(e.sheets_released_at, 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), o.id, p_id, e.sheets_due
      FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id AND s.exam_session_id = p_id)
       AND (e.kind = 'MAIN'
            OR EXISTS (SELECT 1 FROM assessment.score_sheet ms
                         JOIN assessment.exam_session mes ON mes.id = ms.exam_session_id AND mes.kind = 'MAIN'
                        WHERE ms.offering_id = o.id AND ms.stage = 'PUBLISHED'));
    GET DIAGNOSTICS v_made = ROW_COUNT;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL;
    UPDATE assessment.exam_session SET sheets_released_at = now(), sheets_released_by = who WHERE id = p_id;
    RETURN QUERY SELECT v_made, v_none;
END;
$$;
COMMENT ON FUNCTION assessment.release_exam_sheets(uuid) IS 'V335: release an open examination session''s score sheets to the lecturers — the sheets made for every offering with a lecturer (a resit only where the main sheet is published); once only.';

-- ── the examination cards, released to the students (and withdrawn, if released in error) ──────────────────────
CREATE OR REPLACE FUNCTION assessment.release_exam_cards(p_id uuid, p_release boolean)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e assessment.exam_session;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'examination cards are released by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found'; END IF;
    IF p_release AND e.state <> 'OPEN' THEN
        RAISE EXCEPTION 'EXAM_NOT_OPEN: the examination session is %; its cards are released once it is open', lower(e.state) USING ERRCODE = '23514';
    END IF;
    UPDATE assessment.exam_session
       SET cards_released_at = CASE WHEN p_release THEN coalesce(cards_released_at, now()) END,
           cards_released_by = CASE WHEN p_release THEN coalesce(cards_released_by, who) END
     WHERE id = p_id;
    RETURN (SELECT cards_released_at FROM assessment.exam_session WHERE id = p_id);
END;
$$;
COMMENT ON FUNCTION assessment.release_exam_cards(uuid, boolean) IS 'V335: release (true) or withdraw (false) an examination session''s cards; students see their papers and a cleared student downloads the card only while released.';

-- ── a lecturer allocated in a session whose sheets are released gets the sheet at once; before, the release makes it ──
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

    -- assigning the lecturer opens the score sheet, if the examination session is open, its sheets released, and none exists yet
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), p_offering, es.id, es.sheets_due
      FROM assessment.exam_session es
     WHERE es.session = o.session AND es.semester = o.semester AND es.state = 'OPEN' AND es.sheets_released_at IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = p_offering);
END $$;

COMMIT;
