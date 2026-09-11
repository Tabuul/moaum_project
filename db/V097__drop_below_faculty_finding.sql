-- ═══════════════════════════════════════════════════════════════════════════
-- V097 — drop the obsolete "a programme cut-off is below its faculty's" finding
--
--   Cut-offs are set per programme now, and the faculty cut-off is no longer
--   edited. Comparing a programme's cut-off to a vestigial faculty cut-off
--   flagged programmes (e.g. the Education programmes at 150 under ED at 160)
--   that nobody could clear, because there is no longer a place to change the
--   faculty cut-off. The finding is removed; the rest are unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.policy_findings(p_session text)
RETURNS TABLE (finding text, detail text, owner text)
LANGUAGE sql
STABLE
AS $$
    WITH pol AS (SELECT * FROM admissions.session_policy WHERE session = p_session)
    SELECT 'The selection criteria do not total 100%'::text,
           'National Merit, State Merit, Equality of Local Government and '
           'Locality total ' || coalesce(sum(c.percent), 0) || '%. The guidelines '
           'set 10 + 35 + 30 + 25.',
           'Central Admissions Committee'::text
      FROM pol p LEFT JOIN admissions.selection_criterion c ON c.policy_id = p.id
     GROUP BY p.id
    HAVING coalesce(sum(c.percent), 0) <> 100
  UNION ALL
    SELECT 'The programme quotas do not total the NUC approved quota'::text,
           'Distributed ' || coalesce(sum(r.quota), 0) || ' of ' || p.nuc_quota ||
           '. ' || abs(p.nuc_quota - coalesce(sum(r.quota), 0))::text ||
           CASE WHEN coalesce(sum(r.quota), 0) < p.nuc_quota
                THEN ' places are unallocated.' ELSE ' places over the capacity.' END,
           'Heads of Department'::text
      FROM pol p LEFT JOIN admissions.programme_rule r ON r.policy_id = p.id
     GROUP BY p.id, p.nuc_quota
    HAVING coalesce(sum(r.quota), 0) <> p.nuc_quota
  UNION ALL
    SELECT 'A faculty has no UTME cut-off'::text,
           string_agg(f.faculty_code, ', ' ORDER BY f.faculty_code) ||
           ' — a faculty with no cut-off admits on no rule at all.',
           'Central Admissions Committee'::text
      FROM pol p JOIN admissions.faculty_quota f ON f.policy_id = p.id
     WHERE f.cutoff IS NULL
     GROUP BY p.id
  UNION ALL
    SELECT 'Equality of Local Government exceeds its ceiling'::text,
           'ELG is set at ' || c.percent || '% but the ceiling is ' || p.elg_cap_pct ||
           '%. ELG may be any share up to the ceiling, never above it.',
           'Central Admissions Committee'::text
      FROM pol p JOIN admissions.selection_criterion c ON c.policy_id = p.id AND c.criterion = 'ELG'
     WHERE c.percent > p.elg_cap_pct
$$;

COMMIT;
