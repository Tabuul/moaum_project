-- ═══════════════════════════════════════════════════════════════════════════
-- V100 — one source of truth for "how many sittings"
--
--   V099 taught admissions.olevel_score to count a candidate's sittings by
--   their identity, so a result uploaded twice counts once. But the JAMB
--   admission template (the list that goes back to JAMB) computed its own
--   sitting count and bonus straight from count(DISTINCT sitting_id) — the raw
--   row count. So on a candidate whose O'Level was uploaded twice, the sheet's
--   Sittings and Sitting-points columns said two sittings while the Total (which
--   comes from screening_result → olevel_score) already reflected one. The sheet
--   could not be reconciled against itself.
--
--   This puts the identity count in one function, admissions.olevel_sittings,
--   and has olevel_score use it, so every consumer — the applicant's score, the
--   screening result and the JAMB template — reads the same number.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the number of distinct sittings a candidate has, by identity: JAMB's exam
-- number where there is one, else the body, year and the grades themselves
CREATE OR REPLACE FUNCTION admissions.olevel_sittings(p_session text, p_jamb_key text)
RETURNS int
LANGUAGE sql
STABLE
AS $$
    SELECT count(DISTINCT sig)::int FROM (
        SELECT coalesce(nullif(upper(btrim(st.exam_number)), ''),
                        st.exam_body || '|' || coalesce(st.exam_year, '') || '|' ||
                        coalesce((SELECT string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade)
                                    FROM admissions.olevel_grade g WHERE g.sitting_id = st.id), '')) AS sig
          FROM admissions.olevel_sitting st
         WHERE st.session = p_session AND st.jamb_key = upper(btrim(p_jamb_key))
    ) q;
$$;

-- olevel_score now reads the count from the helper (identical result to V099,
-- but no longer a second copy of the identity rule that could drift)
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
    best AS (
        SELECT s.subject, max(s.pts) AS pts,
               (array_agg(s.grade ORDER BY s.pts DESC, s.grade))[1] AS grade
          FROM sat s
         WHERE NOT EXISTS (SELECT 1 FROM relevant) OR s.subject IN (SELECT subject FROM relevant)
         GROUP BY s.subject
    ),
    top AS (
        SELECT b.subject, b.grade, b.pts
          FROM best b, rule r
         ORDER BY b.pts DESC, b.subject
         LIMIT (SELECT r.subjects_counted FROM rule r)
    ),
    n AS (SELECT admissions.olevel_sittings(p_session, p_jamb_key) AS sittings)
    SELECT n.sittings,
           EXISTS (SELECT 1 FROM relevant) AS relevant_known,
           coalesce((SELECT jsonb_agg(jsonb_build_object('subject', t.subject, 'grade', t.grade, 'points', t.pts)
                                       ORDER BY t.pts DESC, t.subject) FROM top t), '[]'::jsonb) AS counted,
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
