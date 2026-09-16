-- ===========================================================================
-- V154 - score from the required subjects: fill spare slots, never displace them
--
--   Two corrections to O'Level scoring:
--
--   1) The score again fills a spare slot with the best remaining grade (as V150
--      did, undoing V152's strict cut). The real fault was never the filler - it
--      was that the required set was empty, so a required subject ranked as a
--      filler and lost to a higher grade. With the requirement seeded (below) the
--      required subjects fill the slots first; a filler only takes a slot the
--      requirement leaves open ("one other subject"), so no candidate is
--      under-counted and no unrelated subject displaces a required one.
--
--   2) Seed the required subjects for every programme that names them, expanding
--      an "other Science subject(s)" phrase into the science subjects. Programmes
--      with an explicit list keep exactly that list (no category is added). This
--      is rebuilt from progrules.json; the settings screen replaces a group when
--      an office saves it. rule_subject(_group) are audit-exempt (V008).
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION admissions.olevel_score(p_session text, p_jamb_key text, p_programme text)
RETURNS TABLE (sittings int, relevant_known boolean, counted jsonb, points int, bonus int, total int)
LANGUAGE sql
STABLE
AS $FN$
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
    best AS (
        SELECT s.subject, max(s.pts) AS pts,
               (array_agg(s.grade ORDER BY s.pts DESC, s.grade))[1] AS grade
          FROM sat s
         GROUP BY s.subject
    ),
    -- band each subject: English + Mathematics compulsory = 0; the programme's named
    -- (and, where the requirement says so, the science) subjects = 1; anything else = 2.
    -- The counted set takes the bands in order, best grade within a band, so a required
    -- subject is always counted before an unrelated one; a spare slot (a requirement that
    -- allows "one other subject") is then filled by the best remaining grade. Matching is
    -- case- and space-insensitive so a spelling difference does not drop a subject.
    ranked AS (
        SELECT b.subject, b.grade, b.pts,
               CASE WHEN b.subject ILIKE 'english%'
                      OR (b.subject ILIKE 'math%' AND b.subject NOT ILIKE 'further%') THEN 0
                    WHEN lower(btrim(b.subject)) IN (SELECT lower(btrim(subject)) FROM relevant) THEN 1
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
$FN$;

-- rebuild the O'Level required-subject groups for 2025/2026 from the requirement text
DELETE FROM admissions.rule_subject rs
 USING admissions.rule_subject_group g, admissions.session_policy p
 WHERE rs.group_id = g.id AND g.scope = 'OLEVEL' AND g.policy_id = p.id AND p.session = '2025/2026';
DELETE FROM admissions.rule_subject_group g
 USING admissions.session_policy p
 WHERE g.scope = 'OLEVEL' AND g.policy_id = p.id AND p.session = '2025/2026';

WITH pol AS (SELECT id FROM admissions.session_policy WHERE session = '2025/2026'),
req(programme_code, subject) AS (VALUES
    ('C51900', 'Biology'),
    ('C51900', 'Building Construction'),
    ('C51900', 'Chemistry'),
    ('C51900', 'Economics'),
    ('C51900', 'English Language'),
    ('C51900', 'Fine Arts'),
    ('C51900', 'Geography'),
    ('C51900', 'Land Surveying'),
    ('C51900', 'Mathematics'),
    ('C51900', 'Physics'),
    ('C51900', 'Technical Drawing'),
    ('C72222', 'Biology'),
    ('C72222', 'Building Construction'),
    ('C72222', 'Chemistry'),
    ('C72222', 'Economics'),
    ('C72222', 'English Language'),
    ('C72222', 'Fine Arts'),
    ('C72222', 'Geography'),
    ('C72222', 'Land Surveying'),
    ('C72222', 'Mathematics'),
    ('C72222', 'Physics'),
    ('C72222', 'Technical Drawing'),
    ('C40831', 'Biology'),
    ('C40831', 'Building Construction'),
    ('C40831', 'Chemistry'),
    ('C40831', 'Economics'),
    ('C40831', 'English Language'),
    ('C40831', 'Fine Arts'),
    ('C40831', 'Geography'),
    ('C40831', 'Land Surveying'),
    ('C40831', 'Mathematics'),
    ('C40831', 'Physics'),
    ('C40831', 'Technical Drawing'),
    ('C00002', 'English Language'),
    ('C00002', 'Literature in English'),
    ('C00067', 'English Language'),
    ('C00067', 'History'),
    ('C00003', 'English Language'),
    ('C00005', 'English Language'),
    ('C00094', 'English Language'),
    ('C00062', 'English Language'),
    ('C00066', 'English Language'),
    ('C29132', 'Biology'),
    ('C29132', 'Chemistry'),
    ('C29132', 'English Language'),
    ('C29132', 'Mathematics'),
    ('C29132', 'Physics'),
    ('C18115', 'Biology'),
    ('C18115', 'Chemistry'),
    ('C18115', 'English Language'),
    ('C18115', 'Mathematics'),
    ('C18115', 'Physics'),
    ('C49411', 'Biology'),
    ('C49411', 'Chemistry'),
    ('C49411', 'English Language'),
    ('C49411', 'Mathematics'),
    ('C49411', 'Physics'),
    ('C00061', 'Biology'),
    ('C00061', 'Chemistry'),
    ('C00061', 'English Language'),
    ('C00061', 'Mathematics'),
    ('C00061', 'Physics'),
    ('C49412', 'Biology'),
    ('C49412', 'Chemistry'),
    ('C49412', 'English Language'),
    ('C49412', 'Mathematics'),
    ('C49412', 'Physics'),
    ('C13707', 'English Language'),
    ('C13707', 'Literature in English'),
    ('C13707', 'Mathematics'),
    ('C60514', 'English Language'),
    ('C60514', 'Literature in English'),
    ('C60514', 'Mathematics'),
    ('C62073', 'English Language'),
    ('C62073', 'Literature in English'),
    ('C62073', 'Mathematics'),
    ('C94958', 'English Language'),
    ('C94958', 'Literature in English'),
    ('C94958', 'Mathematics'),
    ('C48372', 'English Language'),
    ('C48372', 'Literature in English'),
    ('C48372', 'Mathematics'),
    ('C98602', 'English Language'),
    ('C98602', 'Literature in English'),
    ('C98602', 'Mathematics'),
    ('C00001', 'English Language'),
    ('C00001', 'Literature in English'),
    ('C34921', 'English Language'),
    ('C62664', 'English Language'),
    ('C00220', 'English Language'),
    ('C00220', 'Mathematics'),
    ('C00065', 'English Language'),
    ('C00010', 'Biology'),
    ('C00010', 'English Language'),
    ('C00012', 'Biology'),
    ('C00012', 'Chemistry'),
    ('C00012', 'English Language'),
    ('C00012', 'Mathematics'),
    ('C00014', 'Agricultural Science'),
    ('C00014', 'Biology'),
    ('C00014', 'Chemistry'),
    ('C00014', 'English Language'),
    ('C00014', 'Further Mathematics'),
    ('C00014', 'Geography'),
    ('C00014', 'Health Science'),
    ('C00014', 'Mathematics'),
    ('C00014', 'Physics'),
    ('C00014', 'Technical Drawing'),
    ('C67895', 'Agricultural Science'),
    ('C67895', 'Biology'),
    ('C67895', 'Chemistry'),
    ('C67895', 'English Language'),
    ('C67895', 'Further Mathematics'),
    ('C67895', 'Geography'),
    ('C67895', 'Health Science'),
    ('C67895', 'Mathematics'),
    ('C67895', 'Physics'),
    ('C67895', 'Technical Drawing'),
    ('C44826', 'Biology'),
    ('C44826', 'Chemistry'),
    ('C44826', 'English Language'),
    ('C44826', 'Mathematics'),
    ('C00016', 'Agricultural Science'),
    ('C00016', 'Biology'),
    ('C00016', 'Chemistry'),
    ('C00016', 'English Language'),
    ('C00016', 'Further Mathematics'),
    ('C00016', 'Geography'),
    ('C00016', 'Health Science'),
    ('C00016', 'Mathematics'),
    ('C00016', 'Physics'),
    ('C00016', 'Technical Drawing'),
    ('C00017', 'Agricultural Science'),
    ('C00017', 'Biology'),
    ('C00017', 'Chemistry'),
    ('C00017', 'English Language'),
    ('C00017', 'Further Mathematics'),
    ('C00017', 'Geography'),
    ('C00017', 'Health Science'),
    ('C00017', 'Mathematics'),
    ('C00017', 'Physics'),
    ('C00017', 'Technical Drawing'),
    ('C00025', 'English Language'),
    ('C00025', 'Geography'),
    ('C00025', 'Mathematics'),
    ('C30468', 'Biology'),
    ('C30468', 'Chemistry'),
    ('C30468', 'Economics'),
    ('C30468', 'English Language'),
    ('C30468', 'Geography'),
    ('C30468', 'Government'),
    ('C30468', 'History'),
    ('C30468', 'Mathematics'),
    ('C30468', 'Physics'),
    ('C30468', 'Social Studies'),
    ('C30468', 'Technical Drawing'),
    ('C00033', 'English Language'),
    ('C00033', 'Literature in English'),
    ('C00033', 'Mathematics'),
    ('C00019', 'Commerce'),
    ('C00019', 'Economics'),
    ('C00019', 'English Language'),
    ('C00019', 'Mathematics'),
    ('C00019', 'Office Practice'),
    ('C00019', 'Principles of Accounts'),
    ('C44827', 'Commerce'),
    ('C44827', 'Economics'),
    ('C44827', 'English Language'),
    ('C44827', 'Mathematics'),
    ('C44827', 'Office Practice'),
    ('C44827', 'Principles of Accounts'),
    ('C44829', 'Commerce'),
    ('C44829', 'Economics'),
    ('C44829', 'English Language'),
    ('C44829', 'Mathematics'),
    ('C44829', 'Office Practice'),
    ('C44829', 'Principles of Accounts'),
    ('C00021', 'Commerce'),
    ('C00021', 'Economics'),
    ('C00021', 'English Language'),
    ('C00021', 'Geography'),
    ('C00021', 'Government'),
    ('C00021', 'Mathematics'),
    ('C00021', 'Statistics'),
    ('C44828', 'English Language'),
    ('C44828', 'Mathematics'),
    ('C51691', 'Commerce'),
    ('C51691', 'Economics'),
    ('C51691', 'English Language'),
    ('C51691', 'Government'),
    ('C51691', 'Office Practice'),
    ('C51691', 'Principles of Accounts'),
    ('C73770', 'Biology'),
    ('C73770', 'Chemistry'),
    ('C73770', 'English Language'),
    ('C73770', 'Mathematics'),
    ('C73770', 'Physics'),
    ('C64548', 'Biology'),
    ('C64548', 'Chemistry'),
    ('C64548', 'English Language'),
    ('C64548', 'Mathematics'),
    ('C64548', 'Physics'),
    ('C00060', 'Agricultural Science'),
    ('C00060', 'Biology'),
    ('C00060', 'Chemistry'),
    ('C00060', 'English Language'),
    ('C00060', 'Further Mathematics'),
    ('C00060', 'Geography'),
    ('C00060', 'Health Science'),
    ('C00060', 'Mathematics'),
    ('C00060', 'Physics'),
    ('C00060', 'Technical Drawing'),
    ('C52295', 'Biology'),
    ('C52295', 'Chemistry'),
    ('C52295', 'English Language'),
    ('C52295', 'Mathematics'),
    ('C52295', 'Physics'),
    ('C82347', 'Biology'),
    ('C82347', 'Chemistry'),
    ('C82347', 'English Language'),
    ('C82347', 'Mathematics'),
    ('C82347', 'Physics'),
    ('C49638', 'Agricultural Science'),
    ('C49638', 'Biology'),
    ('C49638', 'Chemistry'),
    ('C49638', 'English Language'),
    ('C49638', 'Further Mathematics'),
    ('C49638', 'Geography'),
    ('C49638', 'Health Science'),
    ('C49638', 'Mathematics'),
    ('C49638', 'Physics'),
    ('C49638', 'Technical Drawing'),
    ('C00022', 'Biology'),
    ('C00022', 'Chemistry'),
    ('C00022', 'English Language'),
    ('C00022', 'Mathematics'),
    ('C00022', 'Physics'),
    ('C52395', 'Biology'),
    ('C52395', 'Chemistry'),
    ('C52395', 'English Language'),
    ('C52395', 'Mathematics'),
    ('C52395', 'Physics'),
    ('C22229', 'Agricultural Science'),
    ('C22229', 'Biology'),
    ('C22229', 'Chemistry'),
    ('C22229', 'English Language'),
    ('C22229', 'Further Mathematics'),
    ('C22229', 'Geography'),
    ('C22229', 'Health Science'),
    ('C22229', 'Mathematics'),
    ('C22229', 'Physics'),
    ('C22229', 'Technical Drawing'),
    ('C00023', 'Agricultural Science'),
    ('C00023', 'Biology'),
    ('C00023', 'Chemistry'),
    ('C00023', 'English Language'),
    ('C00023', 'Further Mathematics'),
    ('C00023', 'Geography'),
    ('C00023', 'Health Science'),
    ('C00023', 'Mathematics'),
    ('C00023', 'Physics'),
    ('C00023', 'Technical Drawing'),
    ('C00028', 'Chemistry'),
    ('C00028', 'English Language'),
    ('C00028', 'Mathematics'),
    ('C00028', 'Physics'),
    ('C56345', 'Chemistry'),
    ('C56345', 'Economics'),
    ('C56345', 'English Language'),
    ('C56345', 'Further Mathematics'),
    ('C56345', 'Geography'),
    ('C56345', 'Mathematics'),
    ('C56345', 'Physics'),
    ('C56345', 'Statistics'),
    ('C00029', 'Agricultural Science'),
    ('C00029', 'Biology'),
    ('C00029', 'Chemistry'),
    ('C00029', 'English Language'),
    ('C00029', 'Further Mathematics'),
    ('C00029', 'Geography'),
    ('C00029', 'Health Science'),
    ('C00029', 'Mathematics'),
    ('C00029', 'Physics'),
    ('C00029', 'Technical Drawing'),
    ('C00024', 'Economics'),
    ('C00024', 'English Language'),
    ('C00024', 'Mathematics'),
    ('C00063', 'Agricultural Science'),
    ('C00063', 'Biology'),
    ('C00063', 'Chemistry'),
    ('C00063', 'English Language'),
    ('C00063', 'Further Mathematics'),
    ('C00063', 'Geography'),
    ('C00063', 'Health Science'),
    ('C00063', 'Mathematics'),
    ('C00063', 'Physics'),
    ('C00063', 'Technical Drawing'),
    ('C00030', 'English Language'),
    ('C00030', 'Government'),
    ('C00030', 'History'),
    ('C00030', 'Mathematics'),
    ('C00031', 'Agricultural Science'),
    ('C00031', 'Animal Husbandry'),
    ('C00031', 'Biology'),
    ('C00031', 'Chemistry'),
    ('C00031', 'English Language'),
    ('C00031', 'Further Mathematics'),
    ('C00031', 'Geography'),
    ('C00031', 'Government'),
    ('C00031', 'Health Science'),
    ('C00031', 'Mathematics'),
    ('C00031', 'Physics'),
    ('C00031', 'Technical Drawing'),
    ('C00032', 'English Language'),
    ('C00032', 'Government'),
    ('C00032', 'History'),
    ('C00032', 'Mathematics'),
    ('C67773', 'Commerce'),
    ('C67773', 'Economics'),
    ('C67773', 'English Language'),
    ('C67773', 'Mathematics'),
    ('C67773', 'Office Practice'),
    ('C67773', 'Principles of Accounts'),
    ('C78876', 'Biology'),
    ('C78876', 'Chemistry'),
    ('C78876', 'Economics'),
    ('C78876', 'English Language'),
    ('C78876', 'Home Economics'),
    ('C78876', 'Mathematics'),
    ('C00096', 'Mathematics'),
    ('C00096', 'Physics')
),
progs AS (SELECT DISTINCT programme_code FROM req),
newg AS (
    INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose, min_grade)
    SELECT gen_random_uuid(), pol.id, p.programme_code, 'OLEVEL',
           LEAST((SELECT count(*) FROM req r WHERE r.programme_code = p.programme_code), 5), 'C6'
      FROM progs p
      CROSS JOIN pol
      JOIN admissions.programme_rule pr ON pr.policy_id = pol.id AND pr.programme_code = p.programme_code
    RETURNING id, programme_code
)
INSERT INTO admissions.rule_subject (group_id, subject)
SELECT newg.id, r.subject FROM newg JOIN req r ON r.programme_code = newg.programme_code;

COMMIT;
