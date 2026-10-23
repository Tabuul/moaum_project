# Payment reallocation and correction (V649)

A verified payment that was applied to the wrong purpose, session or semester is moved to the obligation it was meant for. It is a
controlled, audited correction. It is not a refund, not a new payment and not a gateway reversal, and it is never a way to type in
a balance.

The University's example: a student meant to pay school fees and paid under Inter-Departmental Transfer. The payment is verified.
The Bursary moves it to the student's school fees, and if it is less than the fee, the student pays only what is left.

## How the finance engine reads a payment

The portal keeps no stored invoice. Each obligation is read live, and each counts the confirmed payments of its purpose and session:

| Obligation | Fee | What counts towards it |
|---|---|---|
| School fees | the fee lines for the student's level and programme in the session (`finance.position`, `finance.charges`) | confirmed payments `School fees…` of the session |
| GST fee | the Bursar's statement (`finance.gst_entitlement`) | confirmed payments `GST fee …` of the session |
| Deferment application fee | `people.deferment_setting.fee` | a confirmed `people.deferment_fee` linked to the payment |

So a payment counts towards an obligation by its purpose and its session. A correction changes those two on the payment, and
nothing else, and only inside an approved correction that keeps the payment as it stood.

## What changes and what does not

Never changed: the payment reference, the amount, the student, the channel and gateway record (`finance.paydirect_inbox`, gateway
logs), the dates it was generated and confirmed, the receipt number. No payment is deleted, none is created, nothing is refunded and
no balance is typed in.

Changed, inside the correction only: `finance.payment_reference.purpose` and `.session` — what the payment counts towards. The label
is the one every reader of the destination counts: `School fees 2026/2027 · first semester`, `GST fee 2026/2027`, `Deferment
application fee`.

The ledger keeps its original journal. Where the payment is posted, a reclassification journal (`source_type` `REALLOCATION`,
`source_ref` the correction's reference) debits the income account it was booked to and credits the one it belongs to, each line
with its session. It has no bank line, so the bank and the University's money received are the same before and after: the
correction is never counted as new revenue. A payment not yet on the ledger is posted later by the sync under its corrected purpose.

## Destinations

`finance.reallocation_destinations()` lists the University's payment purposes (`finance.payment_purpose`, V409), each with whether a
payment may be moved onto it:

- **School fees** — any amount. The balance after is the fee less everything paid, this payment included; it is paid through the
  student's normal payment page. A surplus is not absorbed.
- **GST fee** — paid in one. The payment must cover what is left of the fee, the fee must be stated, and the GST fee must be owed
  by the student or shown to them (V643). The GST engine entitles on any GST payment, so a partial move is refused rather than
  granting the entitlement early.
- **Deferment application fee** — paid in one. The payment must cover the fee, the student must be eligible to defer, and they must
  not hold a paid, unused deferment fee already. The deferment door then opens as it does after a normal payment.
- Every other purpose (hostel, transcript, transfer and the rest) is paid through its own request and is not a destination.

The level is the student's own level in the destination session (`people.level_in`). It is shown, never chosen from a list: a
level that is wrong in the session is put right on the level desk. The faculty, department and programme are the student's own.

## Eligibility (`finance.payment_reallocation_check`)

Refusals, each with its code:

- not on record (`REALLOC_NOT_FOUND`); not confirmed — pending, failed or expired (`REALLOC_NOT_VERIFIED`)
- a refund stands against it (`REALLOC_REFUNDED`); Interswitch reported it reversed (`REALLOC_REVERSED`)
- from or into a wallet (`REALLOC_WALLET`); a gateway test (`REALLOC_NOT_A_FEE`)
- tied to something that stands (`REALLOC_LINKED`): an old-portal GST reconciliation, a GST payment the Bursary decided, an
  old-portal outstanding payment credited to the wallet, the fee of a deferment request already made, the fee of an
  inter-departmental transfer application that stands (withdrawn or declined, it may be moved), a hostel bed or transcript paid
  on the new portal
- an open swap or correction of it (`REALLOC_OPEN`); already corrected (`REALLOC_ALREADY` — a further correction is a reversal)
- the student's record merged (`REALLOC_STUDENT_MERGED`)
- the destination: an unknown or unsupported purpose (`REALLOC_PURPOSE_UNKNOWN`, `REALLOC_PURPOSE_UNSUPPORTED`), a session not on
  the calendar or a semester it does not have (`REALLOC_SESSION_UNKNOWN`, `REALLOC_SEMESTER_UNKNOWN`), the same as now
  (`REALLOC_SAME`), no school fees stated (`REALLOC_FEES_NOT_STATED`), the GST and deferment rules above (`REALLOC_GST_…`,
  `REALLOC_DEFERMENT_…`), an overpayment decision standing on either session's school fees (`REALLOC_OVERPAYMENT_DECISION`)

A payment credited to the wrong student goes through the payment swap (V527), not here.

## The workflow

1. **Initiate** (`finance.initiate_payment_reallocation`) — the Students Account Officer or the Bursar: the payment, the
   destination, what was wrong (wrong purpose, session, semester or level, an old-portal migration, a reconciliation, other), a
   reason of twenty characters or more, the evidence and the confirmation. It waits as `PENDING_APPROVAL`, the destination's fee,
   what was paid towards it, the balance and any surplus recorded.
2. **Decide** (`finance.decide_payment_reallocation`) — a Bursar officer other than the initiator:
   - **Return** for correction (with a note): `RETURNED`; the initiator or the Bursar changes and sends it again
     (`finance.resubmit_payment_reallocation`), or cancels it.
   - **Reject** (with a reason): `REJECTED`; nothing changes.
   - **Approve** (with the confirmation): executed in the same transaction. The correction and the payment are locked and every
     check is made again; the payment's purpose and session change; a deferment fee is given or set aside; the ledger is
     reclassified; both obligations and the student's money received are read before and after and reconciled (received
     unchanged, the source down and the destination up by exactly the amount) — or `REALLOC_RECONCILIATION` rolls everything back.
     A check that no longer holds marks it `FAILED` and changes nothing.
3. **Cancel** (`finance.cancel_payment_reallocation`) — the initiator or the Bursar, while it is open.
4. **Reverse** — a completed correction is never edited. The Bursar initiates a reversal (kind `REVERSAL`) that puts the payment
   back on the purpose and session it carried; another Bursar officer decides it; the original is then `REVERSED`.

Idempotency: the correction row is locked while it is decided, a decided one refuses a second decision (`REALLOC_DECIDED`), and two
partial unique indexes allow one open correction and one completed correction per payment, even when two requests race.

Separation of duties is enforced in the database: the initiator never decides (`REALLOC_SAME_OFFICER`), and the Students Account
Officer never decides (`REALLOC_OFFICE`).

## Permissions

The portal has no permission table; each endpoint names its offices and the database checks again.

| The brief's permission | Who |
|---|---|
| VIEW_PAYMENT_REALLOCATION, VIEW_PAYMENT_REALLOCATION_HISTORY | Bursar, Students Account Officer, Internal Audit, Deputy Audit, super |
| INITIATE, EDIT (a returned one), CANCEL, EXPORT | Bursar, Students Account Officer |
| REVIEW, APPROVE, EXECUTE (one act), RETURN, REJECT, REVERSE | Bursar — another officer than the initiator |

## Follow-ups (flags)

- `BALANCE_TO_PAY` — a balance is left; the student pays it on the normal payment page.
- `DESTINATION_OVERPAID` — a surplus; carried forward or refunded on the Bursary's own overpayment and refund screens (Refunds &
  Credits).
- `SOURCE_REGISTRATION_UNCLEARED` — the session the payment left has a course registration its school fees no longer clear.
- `SOURCE_GST_UNPAID` — the session the payment left owes the GST fee and no longer has it paid.

## Records

| Table | What it holds |
|---|---|
| `finance.payment_reallocation` | `REA/<year>/<number>`, UUID key: the payment as it stood, the student and where they sit, the original and the destination (purpose, code, session, semester, level), the destination's fee, paid before, balance after, surplus, what was wrong and why, the evidence, who initiated, returned and decided it and when, the accounts before and after, the ledger journal, the flags, the failure. On the audit spine. |
| `finance.payment_reallocation_evidence` | Supporting files (PDF, JPEG, PNG, 5 MB), in the file store where there is one. |
| `finance.payment_reallocation_event` | The timeline, written once: initiated, resubmitted, returned, evidence added, approved, rejected, cancelled, execution started, allocation removed, allocation created, ledger reclassified, completed, failed, reversed — each with the actor, office and source IP. |

The old-portal reset (V499, V631) keeps a payment under a correction, so reloading the export neither undoes nor doubles it.

## Notices

`FEE_PAYMENT_PURPOSE_CORRECTED`, through the notice engine (`platform.tell_student`), once the correction has completed: the
reference, the amount, where it was applied, where it now counts, the correction's number and the balance.

## API (`/api/v1/finance/payment-reallocations`, `PaymentReallocationController`)

| Method and path | Who | What |
|---|---|---|
| `GET /destinations` | readers | The purposes, each supported or not, and how it counts |
| `GET /payments?q=&session=&purpose=&status=&from=&to=&amount=` | initiators | A student's payments by reference, receipt, old-portal number, matriculation, JAMB, admission or application number, the record's id or name; thirty at most, newest first, each with whether it may be corrected |
| `GET /periods?payment=` | initiators | The calendar's sessions with the student's level in each, the semesters and whether school fees are stated |
| `GET /check?payment=&purpose=&session=&semester=` | initiators | The check, with the student, the obligation left and the one met |
| `POST /` | initiators | Initiate |
| `POST /{id}/resubmit` | initiators | Change and send again one returned |
| `POST /{id}/evidence`, `GET /{id}/evidence/{file}` | initiators, readers | Supporting files |
| `POST /{id}/decide` | Bursar | `decision` (`APPROVE`, `RETURN`, `REJECT`), `note`, `confirmed` |
| `POST /{id}/cancel` | initiators | `reason` |
| `POST /{id}/reverse` | Bursar | `reason`, `confirmed` |
| `GET /{id}` | readers | The correction, the student, both obligations now, the timeline, the evidence and the payment's history of corrections and swaps |
| `GET /` | readers | The list by status, search, session, purpose, faculty, department, programme, level and dates, newest first, with counts; `all=true` for export |

The student record (`GET /api/v1/finance/payment-swaps/of/{student}`) and the student's own corrections
(`GET /api/v1/me/payment-corrections`) list completed corrections beside swaps (direction `PURPOSE`). The receipt
(`GET /api/v1/me/fees/receipts/{reference}`) carries the correction standing on the payment.

## Screens

- **Payment Reallocation & Correction** (`/finance/payment-reallocations`, route `t/paymentrealloc`), on the Bursar's and the
  Students Account Officer's menus beside School Fees Payment Swaps, and Internal Audit's and Deputy Audit's: the figures by
  status, the filters, the list newest first, Excel and PDF (S/N first). **New correction**: find the payment; change the payment
  purpose or correct the academic period; the session with the student's level; the semester; **Calculate** (the fee, already
  paid, the amount reallocated, the balance to pay or the surplus, and the obligation the payment leaves); what was wrong, the
  reason, the evidence and files; **Preview correction** with the confirmation; **Submit for approval**. A correction opens with
  everything above and the officer's actions.
- The student's fees page and the student record say when a payment was corrected; the receipt says it was corrected and that it
  is the same payment.

## Tests

- `check.sql` V649: the balance read with what was already paid; refusals (same, pending, refunded, unsupported, unknown session,
  GST short, deferment short, a meaningless reason, no confirmation, open twice); separation of duties; return and resubmit;
  execution (the payment unchanged but for its purpose and session, the money received unchanged, the ledger reclassified with no
  bank line, the timeline); never twice; reversal; the next session; the deferment fee; the GST fee entitling only once executed;
  a rejection changing nothing.
- `PaymentReallocationIT`, at the API: the search, the sessions, the check, the refusals by office and reason, evidence, the
  initiator and the Students Account Officer refused a decision, two Bursar officers approving at once executing it once, the
  payment unchanged but for its purpose and session, the notice, the student's own fees page and receipt, the student's own
  corrections and another student's none, never twice, and the balance paid through the normal payment page.
- `lib/payment-reallocations.test.ts`.
