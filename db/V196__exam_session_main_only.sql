-- ═══════════════════════════════════════════════════════════════════════════
-- V196 — opening a re-sit / special sitting fails clearly instead of silently
--
--   assessment.score_sheet.offering_id is globally UNIQUE, so one offering can
--   carry exactly one score sheet ever. open_exam_session therefore skips any
--   offering that already has a sheet. For a second sitting (RESIT or SPECIAL)
--   over the same session/semester, every offering already has its MAIN sheet,
--   so it made zero sheets and reported "0 score sheets generated" — a silent
--   dead end the Examinations Office could not diagnose.
--
--   A true second sitting needs a sheet per (offering, sitting) and every
--   score-sheet-by-offering join disambiguated — a larger change. Until then,
--   opening a RESIT/SPECIAL session is refused with a clear message rather than
--   quietly producing nothing. Only the MAIN behaviour is unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION assessment.open_exam_session(p_id uuid)
RETURNS TABLE (sheets_made int, offerings_without_lecturer int)
LANGUAGE plpgsql
AS $$
DECLARE e assessment.exam_session; v_made int; v_none int;
BEGIN
    SELECT * INTO e FROM assessment.exam_session WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no examination session %', p_id USING ERRCODE = 'no_data_found';
    END IF;
    IF e.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'the examination session is already %', lower(e.state) USING ERRCODE = 'check_violation';
    END IF;
    IF e.kind <> 'MAIN' THEN
        RAISE EXCEPTION 'a % sitting cannot be opened yet', lower(e.kind)
            USING ERRCODE = 'check_violation',
                  HINT = 'The portal records one score sheet per offering, so a second sitting over the same '
                         'courses is not yet supported. Open the Main sitting for this session and semester.';
    END IF;
    INSERT INTO assessment.score_sheet (id, offering_id, exam_session_id, due_on)
    SELECT gen_random_uuid(), o.id, p_id, e.sheets_due
      FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet s WHERE s.offering_id = o.id);
    GET DIAGNOSTICS v_made = ROW_COUNT;
    SELECT count(*) INTO v_none FROM catalogue.offering o
     WHERE o.session = e.session AND o.semester = e.semester AND o.lecturer_id IS NULL;
    UPDATE assessment.exam_session SET state = 'OPEN', opened_at = now() WHERE id = p_id;
    RETURN QUERY SELECT v_made, v_none;
END;
$$;

COMMIT;
