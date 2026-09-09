-- ═══════════════════════════════════════════════════════════════════════════
-- V051 — biodata is express: a student's own record changes without approval
--
--   The record carried three tiers: open (written straight away), approval
--   (a request the Registry decided before it was written) and locked (read
--   from JAMB, corrected only with JAMB). The University's decision is that
--   nothing a student or applicant enters about themselves waits on a desk:
--   what they enter is their record, at once. So the approval tier is retired
--   — every field that was 'approval' becomes 'open' — while 'locked' stays,
--   because a JAMB field is not the student's to enter in the first place.
--
--   Every write is still on the attributed audit spine (people.student_biodata),
--   so the trail still says who changed what and when; only the wait is gone.
--   ref.biodata_field is audit-exempt, so this reclassification needs no actor.
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE ref.biodata_field SET tier = 'open' WHERE tier = 'approval';
