-- ═══════════════════════════════════════
-- V520 — The Students Account Officer: a Bursary sub-office
--
-- A controlled office of the Bursary for students' money: the payment reports (the Financial Analytics engine: day, week, month,
-- year, faculty, department, programme, payment type and purpose, with the charts and the transactions), the school fees setup
-- and binding (the fee schedule, its lines and copies, and the fee sources), the NELFUND reports and statements, the students'
-- accounts (Student Query, the student's record with its fees and payment history, unpaid registrations, cards withheld) and the
-- hanging payments (the desk, the gateway recheck and sweep, a reported receipt marked not found, an event resolved). It reads
-- what the Bursar reads of these and acts only where named; it never confirms a payment, refunds, reverses, posts to the ledger,
-- sets a gateway, a bank account or the clearance scheme, imports a collections report or old fees, or credits a NELFUND wallet.
-- The office is held by a person on Users & roles like any other (iam.office_assignment); the portal's permissions are the API's,
-- each endpoint naming the offices it admits.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V520: the Students Account Officer, a Bursary sub-office', true);

INSERT INTO ref.office (code, label, scope_kind)
VALUES ('studentaccounts', 'Students Account Officer, Bursary', 'institution')
ON CONFLICT (code) DO NOTHING;

COMMIT;
