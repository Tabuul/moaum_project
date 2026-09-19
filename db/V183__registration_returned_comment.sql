-- ═══════════════════════════════════════════════════════════════════════════
-- V183 — keep the reason a Head of Department returns a registration with
--
--   Returning a registration requires a reason (the office types "what the
--   student must change"), but the reason was only validated and then discarded
--   — the course_registration had nowhere to hold it, so the student saw only
--   "Returned to you. Change it and submit again." with no why. Add a column to
--   store it, so the student is told exactly what to change.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE registration.course_registration ADD COLUMN IF NOT EXISTS returned_comment text NULL;

COMMIT;
