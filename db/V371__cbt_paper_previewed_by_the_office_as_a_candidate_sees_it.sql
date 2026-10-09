-- V371: an examination's paper previewed by its office as a candidate sees it.
--
-- The office that manages a CBT examination opens the examination room on its own paper before candidates do: the questions of
-- the examination's pool at their current version, with their marks and their options, in the room's own layout. No attempt is
-- made and nothing is saved. Like assessment.cbt_candidate_paper, the function selects neither the key nor the explanation, so
-- the preview carries no more than a candidate's screen does. Options are shown in their written order; a candidate's screen
-- shuffles them when the examination says so, and a random paper draws its questions from this pool for each candidate.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V371: a CBT paper previewed by its office as a candidate sees it', true);

CREATE OR REPLACE FUNCTION assessment.cbt_preview_paper(p_exam uuid)
RETURNS TABLE (n int, id uuid, kind text, stem text, marks int, options jsonb)
LANGUAGE sql STABLE AS $$
    SELECT (row_number() OVER (ORDER BY p.ordinal, q.authored_at, q.id))::int,
           q.id, coalesce(qv.kind, q.kind, 'MCQ'), coalesce(qv.stem, q.stem), p.marks,
           (SELECT coalesce(jsonb_agg(jsonb_build_object('i', o.i - 1, 'text', o.t) ORDER BY o.i), '[]'::jsonb)
              FROM jsonb_array_elements_text(coalesce(qv.options, q.options)) WITH ORDINALITY o(t, i))
      FROM assessment.cbt_pool(p_exam) p
      JOIN assessment.question q ON q.id = p.question_id
      LEFT JOIN assessment.question_version qv ON qv.question_id = q.id AND qv.version = q.version
     ORDER BY 1
$$;
COMMENT ON FUNCTION assessment.cbt_preview_paper(uuid) IS
  'V371: the examination''s pool as a candidate''s screen shows a question — stem, marks, options in their written order — for its office to preview; selects neither the key nor the explanation.';

COMMIT;
