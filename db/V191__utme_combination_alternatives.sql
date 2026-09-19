-- ═══════════════════════════════════════════════════════════════════════════
-- V191 — UTME subject requirement supports "any one of" alternatives
--
--   A requirement is often "X and (Y or Z)", e.g. Government requires
--   "Government or History". The list is comma-separated (each item is required —
--   AND), and within one item a slash or the word "or" gives alternatives (any
--   one satisfies it — OR). So "Mathematics, Government/History" means the
--   candidate must offer Mathematics AND (Government OR History). English in any
--   slot is always satisfied (it is compulsory in UTME). Reads the real CAPS
--   subject keys (Subject1..4), as V190.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.utme_meets_combination(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    WITH req AS (
        SELECT lower(btrim(rs.subject)) AS slot
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
            -- a slot is violated when none of its alternatives is satisfied
            SELECT 1 FROM req r
             WHERE NOT EXISTS (
                SELECT 1 FROM regexp_split_to_table(r.slot, '\s*/\s*|\s+or\s+') AS o(opt)
                 WHERE btrim(o.opt) LIKE 'english%'          -- English always offered in UTME
                    OR EXISTS (
                        SELECT 1 FROM cand c
                         WHERE c.subj = btrim(o.opt)
                            OR (btrim(o.opt) LIKE 'math%' AND btrim(o.opt) NOT LIKE 'further%'
                                AND c.subj LIKE 'math%' AND c.subj NOT LIKE 'further%'))))
    END
$$;

COMMENT ON FUNCTION admissions.utme_meets_combination(text, text, text) IS
  'True when the candidate offers the programme''s required UTME subjects. Comma-separated items are all '
  'required (AND); within an item, "/" or "or" gives alternatives (any one satisfies). English is always met.';

COMMIT;
