-- ═══════════════════════════════════════════════════════════════════════════
-- V190 — the UTME-subject gate reads the real CAPS subject keys
--
--   V189 read the candidate's UTME subjects from raw->>'s1'/'s2'/'s3', but the
--   CAPS row's raw jsonb is keyed by the original CAPS headers (Subject1..Subject4,
--   in whatever case/spacing JAMB sent), not the short names. So the gate found no
--   subjects, hit the "no data → pass" fallback, and admitted everyone. This reads
--   the subject columns case- and space-insensitively (regexp_replace to drop
--   non-alphanumerics), matching the Java utmeSubjects() reader. merit_list calls
--   this helper by name, so redefining it is enough — the engine is unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.utme_meets_combination(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    WITH req AS (
        SELECT lower(btrim(rs.subject)) AS subj
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id
         WHERE g.policy_id = (admissions.policy_in_force(p_session)).id
           AND g.programme_code = p_programme AND g.scope = 'UTME'),
    cand AS (
        SELECT lower(btrim(e.value)) AS subj
          FROM admissions.caps_row_live x
          CROSS JOIN LATERAL jsonb_each_text(x.raw) AS e(key, value)
         WHERE x.session = p_session AND x.jamb_key = upper(btrim(p_jamb_key))
           AND regexp_replace(lower(btrim(e.key)), '[^a-z0-9]', '', 'g')
               IN ('subject1', 'subject2', 'subject3', 'subject4', 'subj1', 'subj2', 'subj3', 'subj4')
           AND nullif(btrim(e.value), '') IS NOT NULL)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM req)  THEN true   -- opt-in: no requirement configured → pass
        WHEN NOT EXISTS (SELECT 1 FROM cand) THEN true   -- no subject data to check → do not reject on this ground
        ELSE NOT EXISTS (
            SELECT 1 FROM req r
             WHERE r.subj NOT LIKE 'english%'            -- English is always offered in UTME
               AND NOT EXISTS (
                    SELECT 1 FROM cand c
                     WHERE c.subj = r.subj
                        OR (r.subj LIKE 'math%' AND r.subj NOT LIKE 'further%' AND c.subj LIKE 'math%' AND c.subj NOT LIKE 'further%')))
    END
$$;

COMMIT;
