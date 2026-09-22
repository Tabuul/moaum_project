-- ═══════════════════════════════════════════════════════════════════════════
-- V227 — the College of Health Sciences' Finance Controller office
--
--   The College has three officers of its own: the Provost and the College
--   Secretary (both seeded in V001), and the Finance Controller — the Bursar
--   within the College. The first two already exist; this adds the third so the
--   College module's officers are all present. They sign in through the one
--   University login; the login gate routes a College officer to the College
--   dashboard.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'College Finance Controller office (V227)', true);

INSERT INTO ref.office (code, label, scope_kind)
VALUES ('financecontroller', 'Finance Controller, College of Health Sciences', 'college')
ON CONFLICT (code) DO NOTHING;

COMMIT;
