# School-fees history: JAMB number to matriculation number (V647)

The University's master prompt of 23 October 2026 asked that a historical school-fees payment whose "matriculation number" is the
student's JAMB registration number be accepted as the student's. Such payments were made before matriculation. They must never be
rejected and never be counted twice.

## What was wrong

The old portal named a payer by whatever number they had at the time. Before matriculation that was the JAMB registration number.
The old-fees import (`finance.import_legacy_payments`, V498) found the student by the matriculation or admission number alone. It
counted every other row as "no student" and dropped it.

On the Bursary's export of 14 October 2026:

| Rows named by a JAMB-shaped number | Rows | Amount |
|---|---|---|
| School fees and make-ups | 922 | ₦27.7m |
| Of those, a student on the live-shaped copy | 46 | |
| Applicant payments (Post-UTME, admission checking, acceptance) | about 29,000 | |

The applicant payments are the admissions' own and stay out of the student's account.

## What V647 does

- **One crosswalk.** `people.student_identifier` lists every number a student is known by, read from where each is kept: the
  matriculation number (primary), an old one a correction replaced, the admission number, the JAMB registration number on the record
  and on the candidate, and the application number. It is a view, not a copy.
- **One resolution.** `people.resolve_student(number)` finds the student in the brief's order: the record's ID, the matriculation
  number, an old matriculation number, the admission number, the JAMB registration number, the application number. A JAMB or
  application number that names several students resolves none (AMBIGUOUS). A name never matches a payment.
- **The import uses it.** A row is the student's by that resolution. An applicant's payment (Post-UTME, application, admission
  checking, screening, acceptance) is not resolved by JAMB number. The payment is recorded as before, under the student's ID: its old
  payment number, amount, date, session and channel as the file gives them, counted once by its old payment number.
- **The number is kept.** When a payment was made under any number but the student's matriculation number, `finance.payment_identity`
  keeps the original number, its type, the student, the matriculation number at the time, the match, the source and the batch. The
  payment itself is unchanged.
- **Nothing is dropped.** A school-fees, GST or other student payment whose number names no student yet, or several, is held in
  `finance.legacy_payment_held`, keyed by its old payment number. The rows of approved uploads (V607) that were dropped this way are
  held too. A direct Bursar load kept no rows, so its file is uploaded again; rows already on record are skipped as before.

## The reconciliation

**Students Account → School Fees History Reconciliation** (and the Bursar's Finance menu) lists the held payments as their numbers
resolve now.

| Match status | Meaning |
|---|---|
| Matched | The number names one student now: ready to reconcile |
| Ambiguous | The number names several students: never chosen automatically |
| No match | No student on the register has this number yet |
| Already reconciled | Recorded under its student already |
| Duplicate | Its old payment number is on record already: not recorded twice |
| Invalid | No session or no amount on the row |

1. The Students Account Officer or a Bursary officer chooses **Match JAMB payments** (every matched payment under the filters) or
   ticks payments, gives a reason, and sends a batch, **PAY-RECON/YYYY/NNNNNN**, to the Bursar.
2. A Bursar officer who did not initiate it approves or rejects it. A rejection needs a reason.
3. On approval each payment is checked again and recorded once by the import, its original number kept and its batch named.
4. The initiator may withdraw a batch that is still waiting.

## Where it shows

- **Student full record → Finance** lists the student's payments by the student's ID. A payment made under another number reads
  "Paid as JAMB number …" under its purpose. It counts towards the fee position, the outstanding balance, registration, the GST permit,
  clearance and the reports through the existing finance functions, once.
- **Student Records** search finds a student by the JAMB registration number, and by a number a payment was made under.
- Receipts are unchanged: the payment keeps its reference and receipt number.

## API

| Method | Path | |
|---|---|---|
| GET | `/api/v1/finance/fee-history-reconciliation/figures` | Held, by match status, reconciled, resolved by JAMB, awaiting the Bursar |
| GET | `…/held?session&category&purpose&q&fac&dept&prog&page&size` | The held payments as they resolve now |
| POST | `…/batches` | `{heldIds}` or `{allMatched: true, session, purpose, q, …}` with a reason: the Students Account Officer or the Bursary |
| GET | `…/batches`, `…/batches/{year}/{seq}` | The batches, and one with its payments |
| POST | `…/batches/{year}/{seq}/decide` | `{approve, note}`: a Bursar officer other than the initiator |
| POST | `…/batches/{year}/{seq}/withdraw` | The initiator |

Tests: `db/check.sql` (V647) and `FeeHistoryReconciliationIT`.
