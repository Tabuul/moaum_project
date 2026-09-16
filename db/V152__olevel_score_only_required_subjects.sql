-- ═══════════════════════════════════════════════════════════════════════════
-- V152 — the O'Level score counts only the subjects the programme asks for
--
--   V150 put English and Mathematics first, then the programme's named O'Level
--   subjects, then filled any spare slot with the best remaining grade. That
--   last band is the problem: a high grade in a subject the programme never
--   named (Food & Nutrition, Data Processing) still entered the score.
--
--   The Office's rule is that the score is built from the requirement, not from
--   the best grades on the certificate:
--
--     1. English and Mathematics are compulsory — always counted when sat.
--     2. then the subjects the programme's O'Level requirement names.
--     3. no other subject counts. If fewer than the counted number were sat,
--        the score is the sum of those — it is not topped up with an unrelated
--        subject.
--
--   Where a programme names NO O'Level subjects at all, there is nothing to
--   prioritise, so the old behaviour stands (English and Maths, then the best
--   remaining grades) — otherwise such a programme could score nobody.
--
--   Only the choice of counted subjects changes; sittings, bonus and total are
--   as before. Read-only function, no audit write.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.olevel_score(p_session text, p_jamb_key text, p_programme text)
RETURNS TABLE (sittings int, relevant_known boolean, counted jsonb, points int, bonus int, total int)
LANGUAGE sql
STABLE
AS $$
    WITH rule AS (SELECT * FROM admissions.olevel_rule(p_session)),
    relevant AS (
        SELECT DISTINCT rs.subject
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id AND g.scope = 'OLEVEL'
          JOIN admissions.session_policy p ON p.id = g.policy_id
         WHERE p.session = p_session AND g.programme_code = p_programme
    ),
    sat AS (
        SELECT st.id AS sitting_id, gr.subject, gr.grade, admissions.olevel_points(p_session, gr.grade) AS pts
          FROM admissions.olevel_sitting st
          JOIN admissions.olevel_grade gr ON gr.sitting_id = st.id
         WHERE st.session = p_session AND st.jamb_key = upper(btrim(p_jamb_key))
    ),
    sigs AS (
        SELECT st.id AS sitting_id,
               coalesce(nullif(upper(btrim(st.exam_number)), ''),
                        st.exam_body || '|' || coalesce(st.exam_year, '') || '|' ||
                        coalesce((SELECT string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade)
                                    FROM admissions.olevel_grade g WHERE g.sitting_id = st.id), '')) AS sig
          FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = upper(btrim(p_jamb_key))
    ),
    -- best grade per subject across the sittings, over EVERY subject sat
    best AS (
        SELECT s.subject, max(s.pts) AS pts,
               (array_agg(s.grade ORDER BY s.pts DESC, s.grade))[1] AS grade
          FROM sat s
         GROUP BY s.subject
    ),
    -- band each subject: compulsory (English, Mathematics) = 0, the programme's
    -- named O'Level subjects = 1, anything else = 2
    ranked AS (
        SELECT b.subject, b.grade, b.pts,
               CASE WHEN b.subject ILIKE 'english%'
                      OR (b.subject ILIKE 'math%' AND b.subject NOT ILIKE 'further%') THEN 0
                    WHEN b.subject IN (SELECT subject FROM relevant) THEN 1
                    ELSE 2 END AS pri
          FROM best b
    ),
    -- take the counted subjects in band order, best grade within a band. Band 2
    -- (an unnamed subject) counts ONLY when the programme names no O'Level
    -- subjects at all — otherwise the score is built from the requirement alone.
    top AS (
        SELECT r.subject, r.grade, r.pts, r.pri
          FROM ranked r
         WHERE r.pri < 2 OR NOT EXISTS (SELECT 1 FROM relevant)
         ORDER BY r.pri, r.pts DESC, r.subject
         LIMIT (SELECT rr.subjects_counted FROM rule rr)
    ),
    n AS (SELECT count(DISTINCT sig)::int AS sittings FROM sigs)
    SELECT n.sittings,
           EXISTS (SELECT 1 FROM relevant) AS relevant_known,
           coalesce((SELECT jsonb_agg(jsonb_build_object('subject', t.subject, 'grade', t.grade, 'points', t.pts)
                                       ORDER BY t.pri, t.pts DESC, t.subject) FROM top t), '[]'::jsonb) AS counted,
           coalesce((SELECT sum(t.pts) FROM top t), 0)::int AS points,
           CASE WHEN n.sittings = 0 THEN 0
                WHEN n.sittings = 1 THEN r.bonus_one_sitting
                ELSE r.bonus_two_sittings END AS bonus,
           (coalesce((SELECT sum(t.pts) FROM top t), 0)
              + CASE WHEN n.sittings = 0 THEN 0
                     WHEN n.sittings = 1 THEN r.bonus_one_sitting
                     ELSE r.bonus_two_sittings END)::int AS total
      FROM n, rule r;
$$;

COMMIT;
