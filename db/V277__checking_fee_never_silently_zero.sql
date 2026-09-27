-- ═══════════════════════════════════════════════════════════════════════════
-- V277 — the admission checking fee is never silently zero
--
--   V271 added the checking fee to the applicant fees with a default of 0,
--   so a session whose fees were stated before then carries a zero nobody
--   chose — and admissions.checking_due treats zero as "no checking fee",
--   which opened the released decision without payment (found on 2026/2027).
--   The University's rule is that the checking fee is paid, on its own,
--   before the status is read. Every zero is restored to the built-in
--   ₦3,000; the Bursary may still state another figure on Fee Setup.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V277: the admission checking fee restored where it was silently zero', true);

UPDATE admissions.applicant_fee SET checking_fee = 3000, stated_at = now() WHERE coalesce(checking_fee, 0) <= 0;
ALTER TABLE admissions.applicant_fee ALTER COLUMN checking_fee SET DEFAULT 3000;

COMMIT;
