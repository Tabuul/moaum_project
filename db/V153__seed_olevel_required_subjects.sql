-- ===========================================================================
-- V153 - seed the O'Level required subjects, so the score counts them
--
--   V009 seeded each programme's O'Level requirement only as prose (olevel_text);
--   the structured subject list the score reads (rule_subject_group scope OLEVEL,
--   read by admissions.olevel_score's "relevant" set) was left empty. With it
--   empty the score always fell back to the best grades, so a subject the
--   programme never named (Food & Nutrition, Data Processing) still counted.
--
--   Parse progrules.json (the Academic Office's 2025/2026 subject combinations)
--   and record the named subjects for each programme that ENUMERATES them - the
--   science and vocational programmes whose requirement lists specific subjects.
--   Programmes whose requirement is a category ("any Arts or Social Science
--   subject") name too few to enumerate; they are left as they are and keep the
--   best-grade fallback, so no arts candidate is under-counted.
--
--   Only programmes with a rule and NO O'Level group yet are seeded, so an
--   office-entered requirement is never overwritten. rule_subject_group and
--   rule_subject are audit-exempt (V008), so a migration writes them directly.
--
--   Also: match the "relevant" subjects case- and space-insensitively, so a
--   difference in how a grade subject is spelled does not drop it.
-- ===========================================================================

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
                    WHEN lower(btrim(b.subject)) IN (SELECT lower(btrim(subject)) FROM relevant) THEN 1
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

-- the named subjects per enumerating programme, for the 2025/2026 policy
WITH pol AS (SELECT id FROM admissions.session_policy WHERE session = '2025/2026'),
req(programme_code, subject) AS (VALUES
    ('C51900', 'English Language'),
    ('C51900', 'Mathematics'),
    ('C51900', 'Physics'),
    ('C51900', 'Chemistry'),
    ('C51900', 'Biology'),
    ('C51900', 'Economics'),
    ('C51900', 'Geography'),
    ('C51900', 'Technical Drawing'),
    ('C51900', 'Fine Arts'),
    ('C51900', 'Building Construction'),
    ('C51900', 'Land Surveying'),
    ('C72222', 'English Language'),
    ('C72222', 'Mathematics'),
    ('C72222', 'Physics'),
    ('C72222', 'Chemistry'),
    ('C72222', 'Biology'),
    ('C72222', 'Economics'),
    ('C72222', 'Geography'),
    ('C72222', 'Technical Drawing'),
    ('C72222', 'Fine Arts'),
    ('C72222', 'Building Construction'),
    ('C72222', 'Land Surveying'),
    ('C40831', 'English Language'),
    ('C40831', 'Mathematics'),
    ('C40831', 'Physics'),
    ('C40831', 'Chemistry'),
    ('C40831', 'Biology'),
    ('C40831', 'Economics'),
    ('C40831', 'Geography'),
    ('C40831', 'Technical Drawing'),
    ('C40831', 'Fine Arts'),
    ('C40831', 'Building Construction'),
    ('C40831', 'Land Surveying'),
    ('C29132', 'English Language'),
    ('C29132', 'Mathematics'),
    ('C29132', 'Physics'),
    ('C29132', 'Chemistry'),
    ('C29132', 'Biology'),
    ('C18115', 'English Language'),
    ('C18115', 'Mathematics'),
    ('C18115', 'Physics'),
    ('C18115', 'Chemistry'),
    ('C18115', 'Biology'),
    ('C49411', 'English Language'),
    ('C49411', 'Mathematics'),
    ('C49411', 'Physics'),
    ('C49411', 'Chemistry'),
    ('C49411', 'Biology'),
    ('C00061', 'English Language'),
    ('C00061', 'Mathematics'),
    ('C00061', 'Physics'),
    ('C00061', 'Chemistry'),
    ('C00061', 'Biology'),
    ('C49412', 'English Language'),
    ('C49412', 'Mathematics'),
    ('C49412', 'Physics'),
    ('C49412', 'Chemistry'),
    ('C49412', 'Biology'),
    ('C00014', 'English Language'),
    ('C00014', 'Mathematics'),
    ('C00014', 'Physics'),
    ('C00014', 'Chemistry'),
    ('C00014', 'Biology'),
    ('C00014', 'Agricultural Science'),
    ('C30468', 'English Language'),
    ('C30468', 'Mathematics'),
    ('C30468', 'Physics'),
    ('C30468', 'Chemistry'),
    ('C30468', 'Biology'),
    ('C30468', 'Economics'),
    ('C30468', 'Geography'),
    ('C30468', 'Government'),
    ('C30468', 'History'),
    ('C30468', 'Technical Drawing'),
    ('C30468', 'Social Studies'),
    ('C00019', 'English Language'),
    ('C00019', 'Mathematics'),
    ('C00019', 'Economics'),
    ('C00019', 'Commerce'),
    ('C00019', 'Principles of Accounts'),
    ('C00019', 'Office Practice'),
    ('C44827', 'English Language'),
    ('C44827', 'Mathematics'),
    ('C44827', 'Economics'),
    ('C44827', 'Commerce'),
    ('C44827', 'Principles of Accounts'),
    ('C44827', 'Office Practice'),
    ('C44829', 'English Language'),
    ('C44829', 'Mathematics'),
    ('C44829', 'Economics'),
    ('C44829', 'Commerce'),
    ('C44829', 'Principles of Accounts'),
    ('C44829', 'Office Practice'),
    ('C00021', 'English Language'),
    ('C00021', 'Mathematics'),
    ('C00021', 'Economics'),
    ('C00021', 'Geography'),
    ('C00021', 'Commerce'),
    ('C00021', 'Government'),
    ('C00021', 'Statistics'),
    ('C51691', 'English Language'),
    ('C51691', 'Economics'),
    ('C51691', 'Commerce'),
    ('C51691', 'Government'),
    ('C51691', 'Principles of Accounts'),
    ('C51691', 'Office Practice'),
    ('C73770', 'English Language'),
    ('C73770', 'Mathematics'),
    ('C73770', 'Physics'),
    ('C73770', 'Chemistry'),
    ('C73770', 'Biology'),
    ('C64548', 'English Language'),
    ('C64548', 'Mathematics'),
    ('C64548', 'Physics'),
    ('C64548', 'Chemistry'),
    ('C64548', 'Biology'),
    ('C52295', 'English Language'),
    ('C52295', 'Mathematics'),
    ('C52295', 'Physics'),
    ('C52295', 'Chemistry'),
    ('C52295', 'Biology'),
    ('C82347', 'English Language'),
    ('C82347', 'Mathematics'),
    ('C82347', 'Physics'),
    ('C82347', 'Chemistry'),
    ('C82347', 'Biology'),
    ('C00022', 'English Language'),
    ('C00022', 'Mathematics'),
    ('C00022', 'Physics'),
    ('C00022', 'Chemistry'),
    ('C00022', 'Biology'),
    ('C52395', 'English Language'),
    ('C52395', 'Mathematics'),
    ('C52395', 'Physics'),
    ('C52395', 'Chemistry'),
    ('C52395', 'Biology'),
    ('C22229', 'English Language'),
    ('C22229', 'Mathematics'),
    ('C22229', 'Physics'),
    ('C22229', 'Chemistry'),
    ('C22229', 'Biology'),
    ('C22229', 'Agricultural Science'),
    ('C56345', 'English Language'),
    ('C56345', 'Further Mathematics'),
    ('C56345', 'Mathematics'),
    ('C56345', 'Physics'),
    ('C56345', 'Chemistry'),
    ('C56345', 'Economics'),
    ('C56345', 'Geography'),
    ('C56345', 'Statistics'),
    ('C00029', 'English Language'),
    ('C00029', 'Further Mathematics'),
    ('C00029', 'Mathematics'),
    ('C00029', 'Physics'),
    ('C00029', 'Chemistry'),
    ('C00029', 'Biology'),
    ('C00029', 'Agricultural Science'),
    ('C00031', 'English Language'),
    ('C00031', 'Mathematics'),
    ('C00031', 'Biology'),
    ('C00031', 'Government'),
    ('C00031', 'Health Science'),
    ('C00031', 'Animal Husbandry'),
    ('C67773', 'English Language'),
    ('C67773', 'Mathematics'),
    ('C67773', 'Economics'),
    ('C67773', 'Commerce'),
    ('C67773', 'Principles of Accounts'),
    ('C67773', 'Office Practice'),
    ('C78876', 'English Language'),
    ('C78876', 'Mathematics'),
    ('C78876', 'Chemistry'),
    ('C78876', 'Biology'),
    ('C78876', 'Economics'),
    ('C78876', 'Home Economics')
),
progs AS (SELECT DISTINCT programme_code FROM req),
newg AS (
    INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose, min_grade)
    SELECT gen_random_uuid(), pol.id, p.programme_code, 'OLEVEL',
           LEAST((SELECT count(*) FROM req r WHERE r.programme_code = p.programme_code), 5), 'C6'
      FROM progs p
      CROSS JOIN pol
      JOIN admissions.programme_rule pr ON pr.policy_id = pol.id AND pr.programme_code = p.programme_code
     WHERE NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group g
                        WHERE g.policy_id = pol.id AND g.programme_code = p.programme_code AND g.scope = 'OLEVEL')
    RETURNING id, programme_code
)
INSERT INTO admissions.rule_subject (group_id, subject)
SELECT newg.id, r.subject FROM newg JOIN req r ON r.programme_code = newg.programme_code;

COMMIT;
