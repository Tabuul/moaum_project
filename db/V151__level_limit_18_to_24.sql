-- ═══════════════════════════════════════════════════════════════════════════
-- V151 — the per-semester credit-unit range is 18 to 24 at every level
--
--   V013 seeded 15–27 (and 15–24 for the long programmes). The University's rule
--   is 18 minimum, 24 maximum per semester at every level. Set it. The Registry
--   can still adjust a level on the calendar screen; this is the standing rule.
--
--   policy.level_limit is on the audit spine, and a migration has no acting
--   person to attribute the write to (a fresh database has no people yet), so
--   the audit trigger is lifted for this one standing correction.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE policy.level_limit DISABLE TRIGGER USER;

INSERT INTO policy.level_limit (level, applies_to, min_units, max_units) VALUES
    (100, 'All programmes', 18, 24),
    (200, 'All programmes', 18, 24),
    (300, 'All programmes', 18, 24),
    (400, 'All programmes', 18, 24),
    (500, 'All programmes', 18, 24),
    (600, 'All programmes', 18, 24)
ON CONFLICT (level) DO UPDATE SET min_units = 18, max_units = 24;

ALTER TABLE policy.level_limit ENABLE TRIGGER USER;

COMMIT;
