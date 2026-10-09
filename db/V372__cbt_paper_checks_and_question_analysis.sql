-- V372: a CBT paper checked before it is published, and each question analysed once the examination has ended.
--
-- 1  Paper checks. The bank already refuses a key outside the options, a true/false question without two options and a
--    multiple-select question without a key. What it cannot refuse is a paper a candidate finds unfair or confusing:
--    assessment.cbt_paper_checks names, question by question, the same question twice (stem and options), two options that
--    read the same (HIGH when only one of them is the key), a blank option, an option such as "all of the above" when the
--    options are shuffled for each candidate, a multiple-select question with one correct option, and — when the options are
--    not shuffled — half or more of the single-answer keys on one letter. They are warnings for the office: nothing is refused.
-- 2  Question analysis. assessment.cbt_item_analysis reads the scored attempts of an examination and, for each question as it
--    was drawn (its frozen version and key), counts who saw it, answered it and got it right (the facility), compares the top
--    and bottom 27% of candidates by score (the discrimination: their difference in the share who got it right), and counts
--    every option chosen, overall and by the top group. It flags a question where more of the top group chose one wrong option
--    than the marked answer (a possible wrong key), a negative or weak discrimination, and a very hard or very easy question —
--    the classical test-theory guides (facility 0.20 to 0.90, discrimination 0.20 or more), shown to the office as guides. With
--    fewer than ten scored candidates there are no groups and no discrimination. Nothing is re-marked here.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V372: CBT paper checks and question analysis', true);

-- ── 1 · the paper checked before it is published ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_paper_checks(p_exam uuid)
RETURNS TABLE (n int, question_id uuid, severity text, code text, detail text)
LANGUAGE sql STABLE AS $$
WITH e AS (
    SELECT * FROM assessment.cbt_exam WHERE id = p_exam
), p AS (
    SELECT (row_number() OVER (ORDER BY pl.ordinal, q.authored_at, q.id))::int AS n, q.id,
           coalesce(qv.kind, q.kind, 'MCQ') AS kind, coalesce(qv.stem, q.stem) AS stem, coalesce(qv.options, q.options) AS options,
           coalesce(qv.answers, q.answers, ARRAY[q.answer]) AS answers
      FROM assessment.cbt_pool(p_exam) pl
      JOIN assessment.question q ON q.id = pl.question_id
      LEFT JOIN assessment.question_version qv ON qv.question_id = q.id AND qv.version = q.version
), o AS (
    SELECT p.n, p.id, p.answers, (x.i - 1)::int AS i, x.t, lower(regexp_replace(btrim(x.t), '\s+', ' ', 'g')) AS nt
      FROM p CROSS JOIN LATERAL jsonb_array_elements_text(p.options) WITH ORDINALITY x(t, i)
), sig AS (
    -- a question's wording and its options, as a reader sees them
    SELECT p.n, p.id, lower(regexp_replace(btrim(p.stem), '\s+', ' ', 'g')) || ' | ' || coalesce((SELECT string_agg(o.nt, ' | ' ORDER BY o.nt) FROM o WHERE o.id = p.id), '') AS s
      FROM p
), keys AS (
    SELECT p.answers[1] AS k, count(*)::int AS c, sum(count(*)) OVER ()::int AS total
      FROM p WHERE p.kind = 'MCQ' GROUP BY p.answers[1]
)
SELECT * FROM (
    SELECT a.n, a.id, 'MEDIUM'::text, 'DUPLICATE_QUESTION'::text, 'The same question, with the same options, as question ' || min(b.n) || '.'
      FROM sig a JOIN sig b ON b.s = a.s AND b.n < a.n GROUP BY a.n, a.id
    UNION ALL
    SELECT x.n, x.id, CASE WHEN (x.i = ANY (x.answers)) <> (y.i = ANY (x.answers)) THEN 'HIGH' ELSE 'MEDIUM' END, 'REPEATED_OPTION',
           'Options ' || chr(65 + y.i) || ' and ' || chr(65 + x.i) || ' read the same'
           || CASE WHEN (x.i = ANY (x.answers)) <> (y.i = ANY (x.answers)) THEN ', and only one of them is marked correct.' ELSE '.' END
      FROM o x JOIN o y ON y.id = x.id AND y.i < x.i AND y.nt = x.nt AND x.nt <> ''
    UNION ALL
    SELECT x.n, x.id, 'HIGH', 'BLANK_OPTION', 'Option ' || chr(65 + x.i) || ' has no text.' FROM o x WHERE x.nt = ''
    UNION ALL
    SELECT x.n, x.id, 'HIGH', 'POSITIONAL_OPTION',
           'Option ' || chr(65 + x.i) || ' ("' || left(btrim(x.t), 60) || '") points at the other options by their place, but the options are shuffled for each candidate.'
      FROM o x, e
     WHERE e.randomize_options
       AND (x.nt ~ '(all|none|both|neither|either) of the (above|below|preceding|options|foregoing)'
            OR x.nt ~ '^(options? )?[a-e] (and|or|&) [a-e]\.?$' OR x.nt ~ '^(only )?[a-e] and [a-e] (only|are correct)')
    UNION ALL
    SELECT p.n, p.id, 'LOW', 'MULTI_ONE_KEY',
           'A select-every-correct-option question with only one correct option: candidates may look for more. A single-answer question may suit it better.'
      FROM p WHERE p.kind = 'MULTI' AND cardinality(p.answers) = 1
    UNION ALL
    SELECT NULL::int, NULL::uuid, 'LOW', 'KEYS_BUNCHED',
           round(100.0 * keys.c / keys.total) || '% of the single-answer questions (' || keys.c || ' of ' || keys.total || ') have option '
           || chr(65 + keys.k) || ' as their answer, and the options are not shuffled for each candidate: candidates may notice the pattern.'
      FROM keys, e WHERE NOT e.randomize_options AND keys.total >= 10 AND keys.c * 2 >= keys.total
) c(n, question_id, severity, code, detail)
ORDER BY CASE c.severity WHEN 'HIGH' THEN 0 WHEN 'MEDIUM' THEN 1 ELSE 2 END, c.n NULLS FIRST, c.code
$$;
COMMENT ON FUNCTION assessment.cbt_paper_checks(uuid) IS
  'V372: what to look at on a paper before publishing it — duplicate questions, options that read the same (HIGH where only one is the key), blank options, positional options under shuffling, multiple-select with one key, keys bunched on one letter. Warnings only.';

-- ── 2 · each question analysed once the examination has ended ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assessment.cbt_item_analysis(p_exam uuid)
RETURNS TABLE (question_id uuid, n int, stem text, kind text, options jsonb, key int[], seen int, answered int, correct int,
               facility numeric, discrimination numeric, upper_n int, lower_n int, choices jsonb, upper_choices jsonb, flags text[])
LANGUAGE sql STABLE AS $$
WITH att AS (
    SELECT a.id, a.score, a.question_ids, a.question_versions, row_number() OVER (ORDER BY a.score DESC, a.id) AS r, count(*) OVER () AS total
      FROM assessment.cbt_attempt a
     WHERE a.exam_id = p_exam AND a.status IN ('SUBMITTED', 'TIME_EXPIRED', 'TERMINATED') AND a.outcome = 'SCORED' AND a.score IS NOT NULL
), g AS (
    -- the top and bottom 27% by score, when there are ten scored candidates or more
    SELECT att.*, greatest(1, round(att.total * 0.27))::int AS k FROM att
), items AS (
    SELECT g.id AS attempt_id,
           CASE WHEN g.total >= 10 AND g.r <= g.k THEN 'U' WHEN g.total >= 10 AND g.r > g.total - g.k THEN 'L' END AS band,
           u.qid, u.v, u.pos::int AS pos
      FROM g CROSS JOIN LATERAL unnest(g.question_ids, g.question_versions) WITH ORDINALITY u(qid, v, pos)
), resp AS (
    SELECT i.*, qv.answers AS qkey, coalesce(an.chosen, ARRAY[]::int[]) AS chosen
      FROM items i
      JOIN assessment.question_version qv ON qv.question_id = i.qid AND qv.version = i.v
      LEFT JOIN assessment.cbt_answer an ON an.attempt_id = i.attempt_id AND an.question_id = i.qid
), per AS (
    SELECT r.qid,
           count(*)::int AS seen,
           count(*) FILTER (WHERE cardinality(r.chosen) > 0)::int AS answered,
           count(*) FILTER (WHERE r.chosen = r.qkey)::int AS correct,
           count(*) FILTER (WHERE r.band = 'U')::int AS upper_n,
           count(*) FILTER (WHERE r.band = 'L')::int AS lower_n,
           count(*) FILTER (WHERE r.band = 'U' AND r.chosen = r.qkey)::int AS upper_correct,
           count(*) FILTER (WHERE r.band = 'L' AND r.chosen = r.qkey)::int AS lower_correct,
           mode() WITHIN GROUP (ORDER BY r.v) AS v,
           min(r.pos) AS pos
      FROM resp r GROUP BY r.qid
), ch AS (
    SELECT r.qid, c.opt, count(*)::int AS cnt, count(*) FILTER (WHERE r.band = 'U')::int AS ucnt
      FROM resp r CROSS JOIN LATERAL unnest(r.chosen) AS c(opt) GROUP BY r.qid, c.opt
), out AS (
    SELECT per.*, qv.stem, qv.kind, qv.options AS raw_options, qv.answers AS qkey,
           round(per.correct::numeric / nullif(per.seen, 0), 2) AS facility,
           CASE WHEN per.upper_n >= 3 AND per.lower_n >= 3
                THEN round(per.upper_correct::numeric / per.upper_n - per.lower_correct::numeric / per.lower_n, 2) END AS discrimination,
           (SELECT max(ch.ucnt) FROM ch WHERE ch.qid = per.qid AND NOT (ch.opt = ANY (qv.answers))) AS top_wrong_upper,
           coalesce((SELECT eq.ordinal FROM assessment.cbt_exam_question eq WHERE eq.exam_id = p_exam AND eq.question_id = per.qid), 100000 + per.pos) AS ord
      FROM per JOIN assessment.question_version qv ON qv.question_id = per.qid AND qv.version = per.v
)
SELECT o.qid, (row_number() OVER (ORDER BY o.ord, o.qid))::int, o.stem, o.kind,
       (SELECT coalesce(jsonb_agg(jsonb_build_object('i', x.i - 1, 'text', x.t) ORDER BY x.i), '[]'::jsonb)
          FROM jsonb_array_elements_text(o.raw_options) WITH ORDINALITY x(t, i)),
       o.qkey, o.seen, o.answered, o.correct, o.facility, o.discrimination, o.upper_n, o.lower_n,
       (SELECT coalesce(jsonb_object_agg(ch.opt::text, ch.cnt), '{}'::jsonb) FROM ch WHERE ch.qid = o.qid),
       (SELECT coalesce(jsonb_object_agg(ch.opt::text, ch.ucnt), '{}'::jsonb) FROM ch WHERE ch.qid = o.qid AND ch.ucnt > 0),
       array_remove(ARRAY[
           CASE WHEN o.kind <> 'MULTI' AND o.upper_n >= 5 AND coalesce(o.top_wrong_upper, 0) > o.upper_correct THEN 'POSSIBLE_WRONG_KEY' END,
           CASE WHEN o.discrimination < 0 THEN 'NEGATIVE_DISCRIMINATION' WHEN o.discrimination < 0.20 THEN 'WEAK_DISCRIMINATION' END,
           CASE WHEN o.seen >= 10 AND o.facility < 0.20 THEN 'VERY_HARD' WHEN o.seen >= 10 AND o.facility > 0.90 THEN 'VERY_EASY' END,
           CASE WHEN o.seen >= 10 AND o.answered = 0 THEN 'NOBODY_ANSWERED' END
       ], NULL)
  FROM out o
 ORDER BY 2
$$;
COMMENT ON FUNCTION assessment.cbt_item_analysis(uuid) IS
  'V372: each question of an ended examination as its scored candidates met it — facility, discrimination (top and bottom 27%), every option chosen, and flags for a possible wrong key, a negative or weak discrimination, a very hard or very easy question. Read by the office that manages the examination; nothing is re-marked.';

COMMIT;
