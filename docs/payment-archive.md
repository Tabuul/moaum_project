# Payments archived for review (V670)

A payment that appears twice, stands on a student who did not make it, or has not been verified is **archived, never deleted**. It
is kept exactly as it was received, it counts nowhere until the Bursary settles it, and it is then restored, reallocated to its true
owner, or excluded for good. This answers the University's master prompt of 27 October 2026, "Payment archive, duplicate payment
detection & payment ownership reconciliation".

> **Archived payments are not income until verified and correctly reconciled.** Archiving does not delete a payment: it removes it
> from active financial recognition while preserving the complete audit history. A payment becomes active again only through the
> controlled verification and reconciliation below.

## Nothing rebuilt

A student payment is still the one row of `finance.payment_reference`; every balance, clearance, entitlement, report and the ledger
still read it live. V670 adds one mark and one record:

- `finance.payment_reference.archived_at` — set while the payment is archived (and for good once it is confirmed a duplicate or
  never received). Every reader of confirmed payments now reads **confirmed and not archived** (71 functions restated with that
  rule and nothing else, and `reporting.payments`).
- `finance.payment_archive` — the archive record, `PAR/<year>/<number>`, separate from the payment's own reference; both are
  searchable.

The payment lifecycle reads: gateway received → payment recorded → verified (confirmed) → ownership and allocation → active. A
suspicious payment goes gateway received → payment recorded → **archived** → not active revenue, until it is settled.

## What an archived payment no longer counts towards

Enforced in the database, not the screens: the student's school-fees position, balance and arrears (`finance.position`,
`semester_position`, `semester_cleared`, `payment_position`, the spillover panel), the registration and results gates, GST/EPS
entitlement and the CBT candidate lists, late-payment and session charges, overpayment and refund sources, the graduates' historical
fees and the final clearance, postgraduate fee review, deferment financials, the old portal's reconciliation, wallet and
outstanding-fees desks, revenue (`reporting.payments`, the payments query and breakdown, collections by faculty, the day book, the
Bursar's dashboard, the revenue report, the CCE, HOD and record readers, the hostel and transcript collections, the master report)
and the ledger sync. A check in `db/check.sql` reads the catalogue and fails the day any function or view counts a confirmed payment
without leaving the archived ones out.

An archived payment also cannot be swapped, corrected (V649), refunded, credited to the wallet, decided on the GST review, withdrawn
by the old-portal tools or have its entitlement refreshed: each refuses with its own code (`SWAP_ARCHIVED`, `REALLOC_ARCHIVED`,
`REFUND_ARCHIVED`, `PAY_ARCHIVED`, …). A trigger refuses any change to its reference, amount, student, purpose, session, channel,
receipt or dates, and refuses a delete, outside the archive's own settling. An unspent deferment fee the payment was is set aside
while it is archived and given back if it is restored.

What the payment had already paid for — a hostel bed, a transcript — stands as it was: the archive shows it, and the office
concerned decides.

## The workflow

| Step | Who | What |
|---|---|---|
| Archive | Students Account Officer, Bursar | reason from `finance.payment_archive_reason`, the payment it repeats where the reason asks, a note (20+), the confirmation |
| Investigate | Students Account Officer, Bursar | notes, evidence items (strong or supporting), files |
| Propose | Students Account Officer, Bursar | restore · reallocate to the true owner · duplicate · never received |
| Decide | a Bursar officer other than the proposer | approve (executed at once), return for correction, reject |

States: `ARCHIVED` → `UNDER_REVIEW` → `PENDING_BURSAR_APPROVAL` → `RECONCILED` (restored or reallocated) · `DUPLICATE_CONFIRMED` ·
`NOT_RECEIVED`; `RETURNED` goes back to the officer. The verification status shown is NOT YET VERIFIED, VERIFIED — READY FOR
RECONCILIATION, or RECONCILED.

**Evidence.** Strong: the gateway's payer details or reference, payment metadata, the invoice or payment intent (the reference the
student generated), the student record, JAMB, matriculation or application number, the old-portal crosswalk, a bank reference or
statement. Supporting: name, phone, e-mail, date, amount. A payment is moved to another student only on strong evidence — never on a
name alone.

**Duplicates.** `finance.payment_duplicate_signals` compares two records: the authoritative identifiers (the same gateway reference,
transaction reference or old-portal payment number) are proof; the same student, amount, purpose, session or day are supporting
signals and never proof. A duplicate is confirmed only on an authoritative identifier or strong evidence. **Possible duplicates**
(`finance.payment_duplicate_suspects`) lists both kinds, the second marked "supporting only".

**Reallocation to the true owner** reuses the school-fees payment swap (V527): the proposal opens a swap request, the Bursar's
approval of the archive executes it (the swap desk refuses to decide it on its own: `SWAP_ARCHIVE_LINKED`), and the swap reconciles
the move and tells both students without naming the other. The original payment — reference, amount, date, gateway record, receipt —
is unchanged; no new payment and no new receipt is made. The swap moves the whole payment (the existing policy: no partial move).
The swap covers school fees and the old portal's outstanding fees; a payment of another purpose on the wrong student can be restored,
confirmed a duplicate or never received, but is not moved here. A purpose, session or semester that is wrong is corrected through
the payment reallocation desk (V649) once the payment is restored.

**Reconciled once.** One archive stands on a payment at a time (`ux_payment_archive_standing`); a decision locks the archive and
the payment and refuses a second decision (`PAR_DECIDED`); a reference is unique; the swap refuses a payment already swapped. The
settlement reconciles or changes nothing: restored, the student's verified payments rise by exactly the amount; reallocated, the
owner's do; excluded, nothing changes.

## The ledger

- Archived while posted: Dr the income account of its purpose, Cr **2400 Payments under review** (source `PAYMENT_ARCHIVE`). The
  bank line stays — the money was received.
- Archived while unposted: the sync leaves it unposted.
- Restored or reallocated: Dr 2400, Cr income (source ref `PAR/…#SETTLED`); an unposted one is posted by the sync as usual.
- Duplicate or never received: the payment's own posting and the reclassification are both reversed; the record stays archived.

## Reports

`finance.payment_archive_figures(session)` gives verified active revenue, the archived amount and the student payments recorded,
and the archive by state and reason: open, duplicates, wrong student, ownership pending, awaiting the Bursar, reconciled,
reallocated, never received, unresolved — each with its value. The desk shows these as tiles (each a door to its payments), the
Bursar's dashboard as **Archived / under review**. `reporting.payments` leaves archived payments out, so revenue charts, the
payments query, the financial analytics and the master report count verified active payments only. Exports (Excel and PDF, S/N
first, newest first) list the archived payments apart with their archive state, verification status and outcome.

## The student and the record

The student's fees page shows "₦X payment is currently under verification and is not included in your verified payment balance"
with each archived payment and its state; the payment history marks it **Under review** and withholds its receipt
(`PAYMENT_UNDER_REVIEW`). The receipt verification page says a payment is under review, or a duplicate record, or never received.
The full record's finance tab lists verified payments and, apart, **Archived / under review payments** (`finance.payment_archives_of`),
with the archived amount never in what is paid. ICT Support's payment search marks it **Archived for review** and its diagnosis
sends it to the Bursary.

Notices: the student when a payment on their account is archived, restored, confirmed a duplicate or never received (a reallocation
is told by the swap); the Bursar's office when a payment is archived and when a settlement waits; the proposer when it is decided.

## The old portal's withdrawals

Old Fees History's withdrawal of records twice (V448, V498, V502) and the withdrawal of a payment the bank never received (V561) now
archive the record for good — `DUPLICATE_CONFIRMED` or `NOT_RECEIVED`, source `DUPLICATE_WITHDRAWAL` / `NOT_RECEIVED_WITHDRAWAL` —
instead of deleting it. Their withdrawn registers stay as they were. Loading the export again recognises an archived record as on
record and never records it again; a payment of another amount under the same key is recorded beside it. The reset of the imported
history (V499) still removes the import's own records for reloading, but never one the archive holds.

## Permissions

The portal grants by office (there is no permission table): view archived payments, view ownership and history, export — Bursar,
Students Account Officer, Internal Audit, Deputy Audit, the platform; archive, verify ownership, initiate the reconciliation or
reallocation — Bursar, Students Account Officer; review, approve, execute — Bursar, never the officer who proposed it. Every
refusal is the database's (`PAR_OFFICE`, `PAR_SAME_OFFICER`) whatever the screen shows.

## Audit

The archive and the payment are on the audit spine; the archive's timeline (`finance.payment_archive_event`, written once) records
every action with the actor, office, time and source address; the files are kept with it. The archive keeps the payment as it stood
when it was archived and is never deleted.

## Not in this build

- Applicant, JUPEB and postgraduate application fees (`admissions.fee_reference`, `jupeb.fee_reference`) are not archived here; the
  archive covers student payments.
- Moving a payment of a purpose other than school fees (or the old portal's outstanding fees) to another student.
- Partial reallocation of an archived payment.

## Tests

- `db/check.sql` V670: archive, exclusion everywhere it is read, the guards, reallocation through the swap on strong evidence only,
  restore after a return, duplicate on a gateway reference (refused on supporting signals alone), never received, the ledger, the
  figures; and the catalogue check that every reader leaves archived payments out. V449, V498 and V561 restated: a withdrawn record
  is kept archived and counted nowhere.
- `PaymentArchiveIT`: the desk at the API — archive, the student's fees and receipt, the full record, the list and figures, the
  investigation, the owner search, the proposal, the separation of duties, the approval through the swap; `DoubleChargeIT` and
  `OldFeesIT` restated.
- `lib/payment-archive.test.ts`.

## A decided student's later duplicate (V781)

`PAR_OVERPAYMENT_DECISION` used to refuse the archive of any school-fees payment of a student whose overpayment had a decision
standing. A decided student who pays again could therefore never have the second payment archived. The archive is now refused only
when taking the payment away would leave less paid above the charge than is decided or requested
(`finance.overpayment_decisions_covered`, in `finance.payment_archive_refusals`); the payments a decision rests on still cannot
leave. On the Overpaid school fees desk (`docs/overpaid-school-fees.md`) a payment recorded twice (`SAME_PAYMENT`) and a payment under
review (`UNDER_REVIEW`) hold the student's excess until the archive settles it.
