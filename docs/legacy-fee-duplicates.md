# Legacy school-fee duplicates deleted on deployment (V726)

The University's brief of 11 November 2026, "Automatic legacy school fees payment duplicate detection and permanent deletion on
deployment". A legacy school-fee payment record that repeats another on all six fields is deleted for good when the portal is
deployed with V726; one record of each group is kept; the run is recorded with actual counts and read on Old Fees History.

## The six fields

| Brief | What the portal holds |
|---|---|
| Payment reference number | The old portal's payment number (payref): in `finance.legacy_payref` (its key, so one record at most holds it there) and at the end of each record's note (`… · old ref <number>`), where a second record of the same payment carries it. Compared upper-cased and trimmed, as the importer stores it. The portal's own `reference` and `receipt_no` are unique and never repeat. |
| Payment date | The Lagos day of `confirmed_at` (the day the old portal's file gives). |
| Matriculation number | The student the record belongs to (`student_id` → `people.student.matric_no`), never the number written inside the reference. Two student records sharing a number are not taken as one. |
| Academic level | `people.receipt_level(student, session)`. No legacy payment stores a level, so it is the student's level in that session; it follows from the student and the session and never splits a group. |
| Semester | From the purpose (`School fees (legacy) · semester n`); a whole-session record matches only another whole-session record. |
| Academic session | `payment_reference.session`. |

## Scope

Legacy-imported school-fee records alone: `channel = 'Legacy'`, a `MOAUM-LEG-…` reference that is not `MOAUM-LEG-GST-…`, confirmed,
and the purpose `School fees (legacy)` or `School fees (legacy) · semester 1–3` (`finance.legacy_fee_in_scope`). Never a portal or
gateway payment, an acceptance, application, GST/EPS, outstanding-fees, hostel or other item. Undergraduate and postgraduate records
are treated alike.

## Which record is kept

Of each group, deterministically: the record with VERIFIED payment evidence (V683); else the record the number is linked to in
`finance.legacy_payref`; else the record posted to the ledger; else the record with an identity (V647); else the earliest imported
(`generated_at`), then the lowest reference, then the lowest id.

## Groups left whole

A group is never guessed at. It is left whole, every record kept, and listed with the reason on Old Fees History when:

- its amounts differ (`AMOUNTS_DIFFER`);
- a record is archived or under review (V670) (`ARCHIVED_OR_UNDER_REVIEW`);
- VERIFIED evidence names two of its records, or any evidence names a record that would go (`EVIDENCE_ON_TWO_RECORDS`, `EVIDENCE_ON_A_DUPLICATE`);
- a record to be deleted carries another payment number, or belongs to another group (`ANOTHER_PAYMENT_NUMBER`);
- a record is tied to a deferment fee, the GST reconciliation, a refund, a swap, a reallocation, an outstanding-fees credit or an
  archived payment (`LINKED_RECORD`);
- the student and session have an overpayment decision, a credit request, a double-charge check or a bank-list outcome (`MONEY_DECISION`);
- a record to be deleted was paid from the old e-wallet whose balance is verified, posted, frozen or rejected (`OLD_WALLET_SETTLED`).

## What happens to each deleted record

1. Its ledger journal moves to the kept record when the kept record has none (the same amount, the same day); when both were posted,
   the deleted record's journal is reversed and let go (`finance.gl_free_payment`, source type `PAYMENT_DUPLICATE_DELETED`).
2. The group's payment number is sealed on the kept record in `finance.legacy_payref`, so a re-upload of it is "already on record".
3. Its identity (V647) and any held row (V647) move to the kept record.
4. It is deleted from `finance.payment_reference`: no archive table, no soft delete, no filter. Its legacy_payref links cascade with it.
5. The students' historical-fees summaries are marked stale (`finance.historical_mark`) and an old e-wallet touched is worked out again
   (`finance.legacy_wallet_compute`).

A deleted record's printed receipt (`LEG-<reference>`) no longer opens; the kept record's does.

## Checks and failure

After the work, inside the same transaction: every planned record deleted and only those; each group down to its kept record; no group
left that could be deleted; every number sealed on its kept record; no ledger journal left naming a deleted record; no identity left on
one (integrity); each student's paid school fees for the session lower by exactly the deleted records' amounts, and every kept record
still confirmed at its amount (reconciliation). If any check fails, or anything goes wrong, all of the cleanup's work is undone, nothing
is deleted, and the run is recorded `FAILED` with the reason. The deployment then goes on with the data as it was; the run says so on
Old Fees History and in the migration's output.

## The run record

`finance.legacy_fee_duplicate_run`: the run reference, what ran it, the database, the start and finish, the status (`DELETED`,
`NOTHING_TO_DELETE`, `FAILED`), the records inspected, the groups found, cleaned and left whole (by reason), the records kept, deleted
and skipped, the amount the deleted records counted twice, the students, the numbers sealed, the ledger journals moved and reversed,
each check and any error. Counts only: no copy of a deleted payment.

The audit trail (`audit.entries`) records each delete as it records every change to a payment (V002: nothing is deleted from the
record of who changed what). It is the University's evidence trail, not an archive of payments: the records are gone from every
payment table, statement, report and figure.

## Deployment

V726 is applied once by `db/migrate.sh` on each database (Railway's pre-deploy command; the AWS pipeline's migrate step), after every
earlier migration, in one transaction. The cleanup takes an advisory lock so two runs never overlap, holds the group members it works
on, and reads and deletes set-wise; it locks no table. A later deployment does not run it again (the migration ledger), and would find
nothing to delete if it did. The function stays for a later migration to run again.

Before deploying: take a Railway snapshot of the database (Railway › Database › Backups) and confirm AWS RDS's automated backups (point
in time, 14 days) are on — a migration cannot see either. Rehearse on a live-shaped copy as below.

## Prevention

Every route that writes a legacy school-fee record goes through `finance.import_legacy_payments`, which refuses a number already held in
`finance.legacy_payref`. A second record of the same payment arose where the number was held only in a note: a re-upload of a payment
whose number had been moved, an archived record whose number was carried to another, a whole-session record beside a per-semester one.
`trg_pref_legacy_fee_once` (BEFORE INSERT on `finance.payment_reference`) now refuses, quietly, a legacy school-fee record whose number,
day, student, semester and session match one on record — the importer then counts it among those already on record — and never one that
differs in level, semester or session. A unique index is not used: a group left whole for the Bursary would stop it being built, and the
deployment with it.

## Reading it

Finance › Old Fees History › "Duplicate school-fee records deleted on deployment": the latest run as the brief's table (records inspected,
groups identified, records retained, records permanently deleted, records skipped, reconciliation, integrity, status), the reasons groups
were left whole, earlier runs, and the groups left whole with their records (Excel). `GET /api/v1/finance/legacy-fees/duplicate-cleanup`
(the Bursary, Students Account Officer, Registry, Academic Office, Audit, ICT, admin, super, VC, DVC).

## Measured before deployment

On a local copy of live-shaped data (Railway's records as they stood on 21 October 2026, brought up to main and V726), applied as a
deployment applies it:

| Metric | Result |
|---|---|
| Legacy school-fee records inspected | 124,962 |
| Duplicate groups identified | 0 |
| Valid payment records retained | 0 (nothing to choose between) |
| Duplicate records permanently deleted | 0 |
| Records skipped due to inconsistencies | 0 |
| Financial reconciliation status | Passed |
| Referential integrity status | Passed |
| Cleanup execution status | Success (nothing to delete) |
| Time | about 5 seconds warm, 36 seconds cold |

Nearest to duplicates on that copy: 153 pairs with the same student, session, semester and day but two different old-portal payment
numbers (the old portal recorded them as two payments). They are not duplicates under the six-field rule and are kept.

At scale, on the same copy with 2,100 made-up second records of real payments added (2,000 alike in every field, 100 with another
amount): 2,100 groups found; 2,000 records deleted, 2,000 kept; 100 groups (200 records) left whole (amounts differ); ₦128,026,590.58
counted twice removed for 1,968 students; reconciliation and integrity passed; 38 seconds. Afterwards no made-up copy was left, no
original was missing, every student's paid total was back to what it was before the copies were added, and 500 further made-up copies
were refused by the guard.

The figures on the University's own databases (Railway and AWS) are the ones the deployment records; Old Fees History shows them.
