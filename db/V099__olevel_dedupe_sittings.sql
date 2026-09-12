-- ═══════════════════════════════════════════════════════════════════════════
-- V099 — an O'Level result uploaded more than once counts once
--
--   O'Level sittings are derived from admissions.attachment: a candidate can
--   have several OLEVEL attachments (the result re-sent by JAMB, or uploaded a
--   second time), and admissions.olevel_score aggregates the sittings across
--   all of them for a (session, jamb_key). Re-deriving one attachment is already
--   idempotent, but two attachments carrying the SAME result produced two
--   sitting rows — and the score counted them as two sittings.
--
--   The points were never inflated (the score takes the best grade per subject
--   across sittings, so a duplicate adds nothing), but the SITTING COUNT was,
--   and the count drives the bonus: one genuine sitting uploaded twice looked
--   like two sittings and drew the smaller two-sitting bonus instead of the
--   one-sitting bonus — a real loss to the candidate.
--
--   The fix gives each sitting an identity — JAMB's exam number where there is
--   one, else the examining body, year and the grades themselves — and counts
--   DISTINCT identities. The same result uploaded any number of times is one
--   sitting. Nothing is deleted; the uploaded files stay exactly as they
--   arrived, and the duplicate simply stops being double-counted.
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
    -- a sitting's identity, so the same result uploaded more than once counts once:
    -- JAMB's exam number where there is one, else the body, year and the grades themselves
    sigs AS (
        SELECT st.id AS sitting_id,
               coalesce(nullif(upper(btrim(st.exam_number)), ''),
                        st.exam_body || '|' || coalesce(st.exam_year, '') || '|' ||
                        coalesce((SELECT string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade)
                                    FROM admissions.olevel_grade g WHERE g.sitting_id = st.id), '')) AS sig
          FROM admissions.olevel_sitting st
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
    n AS (SELECT count(DISTINCT sig)::int AS sittings FROM sigs)
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

COMMENT ON FUNCTION admissions.olevel_score(text, text, text) IS
  'The O''Level component of the screening score, computed under the session''s '
  'grading and the programme''s relevant subjects. Sittings are counted by their '
  'identity, so the same result uploaded more than once counts once. Never '
  'stored; the Academic Office''s to see, and not the applicant''s.';

COMMIT;
