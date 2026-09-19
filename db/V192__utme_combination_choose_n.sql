-- ═══════════════════════════════════════════════════════════════════════════
-- V192 — UTME subject requirement supports "any N of a set"
--
--   Real CAPS requirements often read "Biology and two (2) other subjects from
--   Chemistry, Mathematics and Physics" or "Any three (3) of CRS, Economics,
--   Geography/Physics, Government, History". These are "choose N distinct from a
--   set", which V191 (AND of one-of slots) could not express.
--
--   Grammar (one field, comma-separated items, ALL items required = AND):
--     • plain          "Biology"                      → must offer Biology
--     • any-one-of      "Government/History"          → offer either (slot count 1)
--     • any-N-of        "2 of Chemistry/Physics/Maths"→ offer at least 2 distinct
--                       "any three of CRS/Economics/…" (word or digit; "of" marks it)
--   Every item is uniformly "offer at least K distinct members of a slash-set",
--   where a plain/one-of item is simply K = 1. Members are slash-separated (or the
--   word "or"). English in any member is always satisfied (compulsory in UTME).
--   Mathematics ≠ Further Mathematics. Reads the real CAPS keys (Subject1..4).
--
--   Lenient by design (a policy filter should not wrongly reject): if no rule is
--   configured, or the candidate has no CAPS subject data, the check passes. In an
--   any-N set a member written as "Geography/Physics" is flattened, so a candidate
--   offering both counts as two toward N — acceptable over-count, never a reject.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.utme_meets_combination(p_session text, p_jamb_key text, p_programme text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    WITH raw AS (
        SELECT lower(btrim(rs.subject)) AS slot
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id
         WHERE g.policy_id = (admissions.policy_in_force(p_session)).id
           AND g.programme_code = p_programme AND g.scope = 'UTME'),
    norm AS (
        -- turn number words into digits and drop the noise word "any"
        SELECT slot,
               regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                 slot, '\many\M', ' ', 'g'),
                       '\mone\M',  '1', 'g'),
                       '\mtwo\M',  '2', 'g'),
                       '\mthree\M','3', 'g'),
                       '\mfour\M', '4', 'g'),
                       '\mfive\M', '5', 'g') AS s
          FROM raw),
    parsed AS (
        SELECT slot,
               CASE WHEN s ~ '\m\d+\s*of\M'
                    THEN ((regexp_match(s, '(\d+)\s*of\M'))[1])::int
                    ELSE 1 END AS need,
               CASE WHEN s ~ '\m\d+\s*of\M'
                    THEN btrim(regexp_replace(s, '^.*?\d+\s*of\M[:\s]*', ''))
                    ELSE s END AS setstr
          FROM norm),
    cand AS (
        SELECT lower(btrim(e.value)) AS subj
          FROM admissions.caps_row_live x
          CROSS JOIN LATERAL jsonb_each_text(x.raw) AS e(key, value)
         WHERE x.session = p_session AND x.jamb_key = upper(btrim(p_jamb_key))
           AND regexp_replace(lower(btrim(e.key)), '[^a-z0-9]', '', 'g')
               IN ('subject1', 'subject2', 'subject3', 'subject4', 'subj1', 'subj2', 'subj3', 'subj4')
           AND nullif(btrim(e.value), '') IS NOT NULL),
    eval AS (
        SELECT p.slot, p.need,
               COUNT(DISTINCT btrim(o.opt)) FILTER (WHERE
                   btrim(o.opt) LIKE 'english%'                   -- English always offered in UTME
                   OR EXISTS (
                       SELECT 1 FROM cand c
                        WHERE c.subj = btrim(o.opt)
                           OR (btrim(o.opt) LIKE 'math%' AND btrim(o.opt) NOT LIKE 'further%'
                               AND c.subj LIKE 'math%' AND c.subj NOT LIKE 'further%'))
               ) AS have
          FROM parsed p
          CROSS JOIN LATERAL regexp_split_to_table(p.setstr, '\s*/\s*|\s+or\s+') AS o(opt)
         GROUP BY p.slot, p.need)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM raw)  THEN true   -- opt-in: no requirement configured → pass
        WHEN NOT EXISTS (SELECT 1 FROM cand) THEN true   -- no subject data to check → do not reject on this ground
        ELSE NOT EXISTS (SELECT 1 FROM eval WHERE have < need)  -- any item short of its count → violated
    END
$$;

COMMENT ON FUNCTION admissions.utme_meets_combination(text, text, text) IS
  'True when the candidate offers the programme''s required UTME subjects. Comma-separated items are all '
  'required (AND). Each item is "at least K distinct of a slash-separated set": a plain or "X/Y" item is K=1, '
  'and "N of A/B/C" (word or digit) is K=N. English is always met; Mathematics <> Further Mathematics.';

COMMIT;
