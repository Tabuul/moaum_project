-- ═══════════════════════════════════════
-- V435 — a deferment letter is verified by the check code its QR carries (portal gap audit, QR verification)
--
--   The public page /verify/deferment/{reference} answered by the reference alone. The references run in sequence
--   (DEF-2026-00001, DEF-2026-00002, …), so anyone could step through them and read each student's name, number, programme,
--   faculty and deferment — the same hole V359 closed for hostel letters. Each deferment now carries a random check code, the
--   letter's QR carries it, and the page answers only with it; without the code, or with another, it says nothing about the
--   reference, not even whether it exists. A letter printed before this is printed again from the portal (the student's or the
--   desk's copy), with the code.
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V435: deferment letters verified by a check code', true);

-- a volatile default is drawn per row, so every deferment already on the register takes a code of its own
ALTER TABLE people.deferment ADD COLUMN verify_code text NOT NULL DEFAULT encode(gen_random_bytes(9), 'hex');
ALTER TABLE people.deferment ADD CONSTRAINT ck_deferment_verify_code CHECK (verify_code ~ '^[0-9a-f]{18}$');
COMMENT ON COLUMN people.deferment.verify_code IS
  'V435: the random check code the approval letter''s QR carries; the public verification page shows the deferment only when it matches (the references run in sequence).';

COMMIT;
