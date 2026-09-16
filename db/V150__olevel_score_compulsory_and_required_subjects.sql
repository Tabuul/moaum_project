-- ═══════════════════════════════════════════════════════════════════════════
-- V150 — the O'Level score counts the right subjects, not merely the best grades
--
--   olevel_score took the top N subjects by grade. That let a high grade in a
--   subject the programme does not ask for (Food & Nutrition, Data Processing)
--   displace English, Mathematics or a required science. The Office's rule:
--
--     1. English and Mathematics are compulsory — always counted.
--     2. then the subjects the programme's O'Level requirement names (the
--        rule_subject groups, scope OLEVEL).
--     3. then any other subject, only to fill the remaining slots.
--
--   Within each of those bands the better grade still wins, and the sitting
--   count, bonus and total are unchanged. Where a programme names no O'Level
--   subjects, English and Maths still lead and the rest fill by grade as before.
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
    -- rank each subject: compulsory (English, Mathematics) = 0, the programme's
    -- named O'Level subjects = 1, anything else = 2; the top N are taken in that
    -- order, by grade within a band
    ranked AS (
        SELECT b.subject, b.grade, b.pts,
               CASE WHEN b.subject ILIKE 'english%'
                      OR (b.subject ILIKE 'math%' AND b.subject NOT ILIKE 'further%') THEN 0
                    WHEN b.subject IN (SELECT subject FROM relevant) THEN 1
                    ELSE 2 END AS pri
          FROM best b
    ),
    top AS (
        SELECT r.subject, r.grade, r.pts, r.pri
          FROM ranked r
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
