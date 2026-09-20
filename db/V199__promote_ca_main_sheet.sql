-- ═══════════════════════════════════════════════════════════════════════════
-- V199 — resit / special sittings, phase 3: the course-space CA promotion pins
--        to the Main sheet
--
--   lms.promote_ca lifts a course space's continuous-assessment total into the
--   score sheet's CA column. It found "the" sheet for an offering with
--   SELECT ... INTO ... WHERE offering_id = p_offering, which was one row while a
--   sheet was unique per offering. With a sheet per sitting (V197) that could
--   match two; the continuous assessment belongs to the Main sitting, so it now
--   selects the Main sheet explicitly. Nothing else in the function changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION lms.promote_ca(p_offering uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE sh assessment.score_sheet; g record; l record; n int := 0; v_ca int;
BEGIN
    SELECT s.* INTO sh
      FROM assessment.score_sheet s
      LEFT JOIN assessment.exam_session es ON es.id = s.exam_session_id
     WHERE s.offering_id = p_offering AND coalesce(es.kind, 'MAIN') = 'MAIN'
     LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no score sheet exists for this offering yet' USING ERRCODE = '23514',
            HINT = 'The sheet is generated when the examination session is opened; promote the gradebook after that.';
    END IF;
    IF sh.stage <> 'ENTRY' THEN
        RAISE EXCEPTION 'the score sheet has left the lecturer; the gradebook is not promoted into it' USING ERRCODE = '23514',
            HINT = 'A change to a mark now is a return with the reason, or a result query.';
    END IF;
    FOR g IN SELECT * FROM lms.gradebook(p_offering) LOOP
        v_ca := least(40, round(g.total))::int;
        SELECT * INTO l FROM assessment.latest_scores(sh.id) x WHERE x.student_id = g.student_id;
        IF FOUND AND l.ca IS NOT DISTINCT FROM v_ca THEN CONTINUE; END IF;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (sh.id, g.student_id, coalesce(l.version, 0) + 1, v_ca, CASE WHEN FOUND THEN l.exam END,
                CASE WHEN FOUND AND l.exam IS NOT NULL THEN 'GRADED' WHEN FOUND THEN l.outcome ELSE 'INCOMPLETE' END,
                CASE WHEN FOUND THEN 'Promoted from the course space gradebook (' || g.total || ' over ' || g.weight_marked || '% marked)' END);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

COMMIT;
