-- ═══════════════════════════════════════════════════════════
-- V747 — the record of merged staff numbers on the audit spine
--
--   V744 made one person of the people who shared a staff number up to case, and wrote each merge to iam.person_merge. Every state
--   table is attached to the audit spine (audit.unattached() lists those that are not); iam.person_merge was not, and the property
--   suite's "Every state table is attached to the spine" failed on it (CI of 48b5a5e7). Attached here, in a migration of its own,
--   so V744 stays as the deployments that already ran it read it.
--   With it, the two staff uploads' descriptions, which V744's restatement replaced: what each upload makes is said again, with
--   V744's lookup added (the review of V744).
-- ═══════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V747: the record of merged staff numbers on the audit spine', true);

SELECT audit.attach('iam.person_merge');

COMMENT ON FUNCTION iam.import_staff(jsonb, boolean) IS
  'Loads non-academic staff from the nominal roll: person and establishment record, placed in a unit, department or faculty; no sign-in, no office. Per-row savepoints; idempotent; a dry run writes nothing. V744: an existing person is found by the staff number whatever its case, never made twice.';
COMMENT ON FUNCTION iam.import_lecturers(jsonb) IS
  'Bulk-onboard teaching staff from the List of teaching staff sheet: person + sign-in (the username the staff number; V428: a random first password nobody knows — the first sign-in is the reset link, or a password the Registry gives) + lecturer office scoped to the home department + hrm.staff_record (sex, first appointment, rank, CONUASS). Cross-department teaching is by course allocation, not a second home. Resilient and idempotent; reports departments not on the register. V744: an existing person is found by the staff number whatever its case, never made twice.';

COMMIT;
