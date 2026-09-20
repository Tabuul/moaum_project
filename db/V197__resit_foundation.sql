-- ═══════════════════════════════════════════════════════════════════════════
-- V197 — resit / special sittings, phase 1: foundation (dormant)
--
--   A score sheet was unique per offering, so one offering could carry exactly
--   one sheet ever. This lets an offering carry one sheet per sitting instead —
--   the Main, and later a Re-sit or Special — by keying uniqueness on
--   (offering_id, exam_session_id), which score_sheet already carries.
--
--   With that, open_exam_session generates the right sheets for a sitting, and
--   the roster a sheet is judged against becomes sitting-aware:
--     • MAIN     — every approved candidate registered for the offering (as before)
--     • RESIT    — those who FAILED or were ABSENT in the published Main sitting
--     • SPECIAL  — those who were ABSENT in the published Main sitting
--
--   Nothing here changes behaviour while only Main sittings exist (the create
--   form still offers Main only), so it is safe to carry into go-live. Later
--   phases add the cross-sitting result resolution (a passed re-sit caps at the
--   pass mark and replaces the Main grade; a Special is uncapped), the broadsheet
--   and graduation, and the desk UI. This phase is the foundation they build on.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V197: resit foundation', true);
END $seed$;

-- ── 1 · a sheet is unique per (offering, sitting), not per offering ──
DO $c$
DECLARE v_con text;
BEGIN
    SELECT conname INTO v_con FROM pg_constraint
     WHERE conrelid = 'assessment.score_sheet'::regclass AND contype = 'u'
       AND pg_get_constraintdef(oid) = 'UNIQUE (offering_id)';
    IF v_con IS NOT NULL THEN
        EXECUTE format('ALTER TABLE assessment.score_sheet DROP CONSTRAINT %I', v_con);
    END IF;
END $c$;

ALTER TABLE assessment.score_sheet
    DROP CONSTRAINT IF EXISTS uq_score_sheet_offering_sitting,
    ADD CONSTRAINT uq_score_sheet_offering_sitting UNIQUE (offering_id, exam_session_id);

-- ── 2 · the roster a sheet is judged against, by sitting ──
CREATE OR REPLACE FUNCTION assessment.sheet_candidates(p_sheet uuid)
RETURNS TABLE (student_id uuid)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_off uuid; v_kind text;
BEGIN
    SELECT sh.offering_id, coalesce(es.kind, 'MAIN')
      INTO v_off, v_kind
      FROM assessment.score_sheet sh
      LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
     WHERE sh.id = p_sheet;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF v_kind = 'MAIN' THEN
        -- every candidate on an approved/locked registration for the offering (as the sheet was always judged)
        RETURN QUERY
            SELECT r.student_id
              FROM registration.entry e
              JOIN registration.course_registration r ON r.id = e.registration_id
             WHERE e.offering_id = v_off AND e.status = 'APPROVED' AND r.status IN ('APPROVED','LOCKED');
    ELSE
        -- a re-sit/special is judged only against those who need it: from the published Main sitting,
        -- the failed-or-absent (re-sit) or the absent (special) candidates of the same offering
        RETURN QUERY
            SELECT ls.student_id
              FROM assessment.score_sheet ms
              JOIN assessment.exam_session mes ON mes.id = ms.exam_session_id AND mes.kind = 'MAIN'
              CROSS JOIN LATERAL assessment.latest_scores(ms.id) ls
             WHERE ms.offering_id = v_off AND ms.stage = 'PUBLISHED'
               AND ((v_kind = 'SPECIAL' AND ls.outcome = 'ABSENT')
                    OR (v_kind = 'RESIT'  AND (ls.outcome = 'ABSENT'
                                              OR (ls.outcome = 'GRADED' AND coalesce(ls.points, 0) = 0))));
    END IF;
END $$;

COMMENT ON FUNCTION assessment.sheet_candidates(uuid) IS
  'The candidates a score sheet is judged against, by its sitting: MAIN = every approved registration for the '
  'offering; RESIT = those who failed or were absent in the published Main; SPECIAL = those absent in the Main.';

-- ── 3 · the completeness gate reads that roster, so a re-sit sheet is judged against its own candidates ──
CREATE OR REPLACE FUNCTION assessment.advance(p_sheet uuid, p_comment text, p_minute text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_stage text; v_next text; v_actor uuid; v_office text; v_last uuid; v_missing int;
BEGIN
    v_actor  := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    SELECT stage INTO v_stage FROM assessment.score_sheet WHERE id = p_sheet FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found';
    END IF;
    v_next := assessment.stage_after(v_stage);
    IF v_next IS NULL THEN
        RAISE EXCEPTION 'this sheet is published; there is no stage after publication'
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_stage = 'ENTRY' THEN
        -- a sheet leaves the lecturer only when every candidate on its roster has an outcome (I-RES-4)
        SELECT count(*) INTO v_missing
          FROM assessment.sheet_candidates(p_sheet) c
         WHERE NOT EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = p_sheet AND sc.student_id = c.student_id);
        IF v_missing > 0 THEN
            RAISE EXCEPTION '% registered candidate(s) on this sheet have no mark and no outcome', v_missing
                USING ERRCODE = 'check_violation',
                      HINT = 'Every candidate on the register is graded, absent, withheld, incomplete, malpractice or exempted. A blank is not an outcome.';
        END IF;
    END IF;
    SELECT d.actor_id INTO v_last FROM assessment.decision d
     WHERE d.sheet_id = p_sheet AND d.kind IN ('SUBMIT','ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you approved the previous stage of this sheet; another desk must approve this one'
            USING ERRCODE = 'check_violation',
                  HINT = 'BR-006. The system refuses two consecutive stages by one person even where one person holds both offices.';
    END IF;
    IF v_next = 'PUBLISHED' AND (p_minute IS NULL OR btrim(p_minute) = '') THEN
        RAISE EXCEPTION 'a result reaches a student on the Senate minute that approved it, and none was cited'
            USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO assessment.decision (id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (gen_random_uuid(), p_sheet, v_stage, v_next,
            CASE WHEN v_stage = 'ENTRY' THEN 'SUBMIT' ELSE 'ADVANCE' END, v_actor, v_office, p_comment);
    UPDATE assessment.score_sheet
       SET stage = v_next,
           submitted_at = CASE WHEN v_stage = 'ENTRY' THEN now() ELSE submitted_at END,
           senate_minute = CASE WHEN v_next = 'PUBLISHED' THEN p_minute ELSE senate_minute END,
           published_at  = CASE WHEN v_next = 'PUBLISHED' THEN now() ELSE published_at END,
           engine_version = CASE WHEN v_next = 'PUBLISHED' THEN 'GpaCalculator 2.1' ELSE engine_version END
     WHERE id = p_sheet;
    RETURN v_next;
END;
$$;

-- ── 4 · opening a sitting generates its sheets: Main over every offering, a re-sit/special over
--        every offering whose Main is published (its roster is derived; an empty one advances trivially) ──
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
    UPDATE assessment.exam_session SET state = 'OPEN', opened_at = now() WHERE id = p_id;
    RETURN QUERY SELECT v_made, v_none;
END;
$$;

COMMIT;
