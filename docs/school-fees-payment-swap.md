# School fees payment swap (V527)

A verified school-fees payment credited to the wrong student (for example MOAU/AD/BUS/25/12939) is moved to the student it belongs to (for example MOAU/SC/MCB/24/75807) as a controlled, audited correction. A swap is not a refund, not a new payment and not a gateway reversal. Nothing is sent to Interswitch or any other gateway.

## What moves and what does not

The swap changes one thing: `finance.payment_reference.student_id`, the student the payment counts for. It changes it only inside an approved swap record, and it keeps the full trail.

These are never changed:

- the payment reference
- the amount
- the purpose and session
- the channel and gateway record (`finance.paydirect_inbox`, gateway logs)
- the date the payment was generated and confirmed (`confirmed_at`, `confirmed_by`)
- the receipt number
- the ledger (`finance.gl_journal` / `gl_posting`)

The ledger holds the University's money by account, purpose and session, not by student, so the University's books are the same before and after a swap.

These are never done:

- no payment is deleted
- no second payment is created
- nothing is refunded
- no balance is typed in
- no student is marked paid by hand

Balances, clearances, the registration fee gate, the examination card and every other entitlement read the payments as they stand (`finance.position`, `finance.clears`), so they follow the swap with no second ledger. Course registrations, results and academic records are never touched.

## Records

| Table | What it holds |
|---|---|
| `finance.payment_swap` | The swap, `SWAP/<year>/<number>`, with a UUID key. It keeps the payment as it stood (reference, amount, session, purpose, channel, receipt, when it was confirmed, and whether it came from the old portal), the student it was credited to (`from_student`), the student it belongs to (`to_student`), the reason (20 characters or more), the evidence text, and `status` (`PENDING_APPROVAL`, `COMPLETED`, `REJECTED`, `CANCELLED`, `FAILED`, `REVERSED`). It also records who initiated it and when (with their office), who decided it and when (with the note), the execution time, both accounts before and after (`before_state`, `after_state`), `flags` and `failure`. It is on the audit spine. |
| `finance.payment_swap_evidence` | Files supporting the swap: PDF, JPEG or PNG, up to 5 MB. Each file goes to the object store when one is configured, otherwise into `content`. Files are never stored on the payment itself. |
| `finance.payment_swap_event` | The timeline, written once: `PAYMENT_SWAP_INITIATED`, `…_EVIDENCE_ADDED`, `…_APPROVED`, `…_EXECUTION_STARTED`, `PAYMENT_ALLOCATION_REMOVED`, `PAYMENT_ALLOCATION_CREATED`, `…_COMPLETED`, or `…_REJECTED`, `…_CANCELLED`, `…_FAILED`, `…_REVERSED`. Each event records the actor, office, source IP and `clock_timestamp()`. |

Two partial unique indexes protect each payment:

- only one open swap at a time
- only one completed swap standing (a reversal frees it)

## Who does what

| Office | May |
|---|---|
| Students Account Officer (`studentaccounts`) | Search payments and students, check a swap, initiate one, attach evidence, cancel their own |
| Bursar (`bursar`) | All of the above. Approve or reject a swap they did not initiate. Reverse a completed swap (another Bursar officer decides the reversal). |
| Internal Audit (`audit`, `deputyaudit`), super | Read the swaps, their timelines and evidence, and export the report |
| Registry, ICT, admin | See a student's reallocations on the student record |

The Finance Controller office (`financecontroller`, V227) belongs to the College of Health Sciences and reads only its college. It is not given University-wide swaps. If the University later has its own Finance Controller office, it can be added in the three database functions and `PaymentSwapController`.

Separation of duties is enforced in the database:

- the officer who initiated a swap never decides it (`SWAP_SAME_OFFICER`), whatever office they act in
- the Students Account Officer never decides (`SWAP_OFFICE`)

The API checks offices with `@PreAuthorize` before the database is reached. The screens only follow what the server allows.

## Eligibility (`finance.payment_swap_check`)

A payment may be swapped only when all of these hold. Each refusal has its own code:

- it is on record (`SWAP_NOT_FOUND`)
- it is school fees (`SWAP_NOT_SCHOOL_FEES`)
- it is confirmed; pending, failed and expired payments are refused (`SWAP_NOT_VERIFIED`)
- no refund stands against it (`SWAP_REFUNDED`)
- Interswitch has not reported it reversed (`SWAP_REVERSED`)
- it was not paid from a NELFUND wallet (`SWAP_WALLET`)
- it has not been swapped already (`SWAP_ALREADY_SWAPPED`, "This payment has already been reallocated"); a correction is a reversal
- no other swap of it is open (`SWAP_OPEN`)
- no overpayment decision stands on either student's fees for the session (`SWAP_OVERPAYMENT_DECISION`)
- the target is a real student (`SWAP_TARGET_UNKNOWN`)
- the target is a different student (`SWAP_SAME_STUDENT`, "Original and target student cannot be the same.")
- the target is not a merged record (`SWAP_TARGET_MERGED`)
- the target has school fees stated for the session (`SWAP_TARGET_FEES_NOT_STATED`)

The whole payment is swapped. A payment is never split.

## The workflow

1. **Initiate** (`finance.initiate_payment_swap`). The officer chooses the payment and the target student from search results. A typed-in student ID is never trusted. The server loads the amount, the session and both students itself. The officer gives a reason of 20 characters or more (not "wrong", "fix", "swap" and the like), the evidence, and the confirmation "I have verified that this payment belongs to the target student". The payment is locked and checked, and the swap waits as `PENDING_APPROVAL`.
2. **Decide** (`finance.decide_payment_swap`). A Bursar officer other than the initiator either rejects the swap (with a reason of 10 characters or more) or approves it with the ownership confirmation. An approval runs in the same database transaction:
   - the swap and the payment are locked (`FOR UPDATE`) and everything is checked again
   - if the payment changed, moved or became ineligible, the swap is marked `FAILED` with the reason and nothing else changes
   - otherwise both accounts and the session's school-fees total are read, the payment's student is changed, and everything is read again
   - the change is reconciled: the total must be unchanged, the credited student's paid must go down by exactly the amount, and the owner's must go up by exactly the amount; if not, `SWAP_RECONCILIATION` is raised and the transaction rolls back
   - the swap is marked `COMPLETED` with the before and after states
   - both students are told
3. **Cancel** (`finance.cancel_payment_swap`). The initiator or the Bursar may cancel a swap that is still waiting.
4. **Reverse**. A completed swap is never edited. The Bursar initiates a reversal: a swap of kind `REVERSAL` that takes the payment back to the student it was first credited to. It goes through the same check, approval by another Bursar officer, execution and reconciliation. When it completes, the original is marked `REVERSED`.

Idempotency:

- the swap row is locked during a decision
- a decided swap refuses a second decision (`SWAP_DECIDED`)
- the partial unique indexes stop a payment from being swapped twice, even if two requests race
- the screen's buttons hold while a request is in flight

## Follow-up flags

A course registration is never changed by a swap. If the credited student has a submitted or approved registration this session that their fees no longer clear, the swap is flagged `FROM_REGISTRATION_UNCLEARED` for the Bursary to follow up.

If the swap leaves the owner paid beyond the session's fees, it is flagged `TO_OVERPAID`. The New payment swap screen warns before submission and gives the excess. The swap is still the whole payment. The excess is handled on the Bursary's own overpayment and refund screens (Refunds & Credits), never by changing the swap.

On the live-shaped copy, the prompt's own example produced this case. Moving MOAU/AD/BUS/25/12939's ₦124,806 to MOAU/SC/MCB/24/75807, who had already paid ₦85,294 of ₦121,849.80, leaves the owner ₦88,250.20 overpaid.

## Old-portal payments

A legacy payment (channel `Legacy`, reference `MOAUM-LEG-…`) is swapped the same way, and its old-portal payment reference is shown. A legacy reference embeds the matriculation number it was paid under (for example `MOAUM-LEG-MOAUADBUS2512939-…`). The reference is never changed, so the owner still sees that number inside the reference. `finance.reset_legacy_payments` (restated from V499) now keeps any payment with a completed, reversed or waiting swap, so reloading the export neither undoes nor duplicates a swap.

## Notifications

Notifications use the existing notification engine (`platform.tell_student`), with event keys for de-duplication:

- `FEE_PAYMENT_REALLOCATED_AWAY` tells the credited student that the payment was credited to them in error and has been reallocated
- `FEE_PAYMENT_REALLOCATED_TO` tells the owner that the payment now counts towards their fees

Each notice gives the reference, the amount, the session and the correction number. It never names the other student.

## API (`/api/v1/finance/payment-swaps`, `PaymentSwapController`)

| Method and path | Who | What |
|---|---|---|
| `GET /payments?q=` | initiators | School-fees payments by reference, receipt, old-portal number, matriculation, JAMB or admission number, or name, each with whether it is eligible |
| `GET /students?q=` | initiators | Target students by matriculation, JAMB, admission or application number, or name |
| `GET /check?payment=&to=` | initiators | The eligibility check, with both profiles and both accounts |
| `POST /` | initiators | Initiate (`payment`, `to`, `reason`, `evidence`, `confirmed`) |
| `POST /{id}/evidence` | initiators | Attach a file (`filename`, `dataUrl`) |
| `GET /{id}/evidence/{file}` | readers | The file |
| `POST /{id}/decide` | Bursar | `approve`, `note`, `confirmed` |
| `POST /{id}/cancel` | initiators | `reason` |
| `POST /{id}/reverse` | Bursar | `reason`, `confirmed` |
| `GET /{id}` | readers | The swap, both students, accounts now (and before and after), the timeline, evidence, the payment's history of swaps, and what would refuse it now |
| `GET /` | readers | The list, filtered by status, search, session, faculty, department and initiation dates, with counts by status; `all=true` returns up to 5,000 rows for export |
| `GET /of/{student}` | readers, Registry, ICT, admin | The swaps on a student's account |
| `GET /api/v1/me/payment-corrections` | the student | Their own reallocations, without the other student's number |

## Screens

- **School Fees Payment Swaps** (`/finance/payment-swaps`, route `t/paymentswaps`):
  - menus: Bursar (Finance), Students Account Officer (Payment Management), Internal Audit and Deputy Audit (Finance)
  - status figures that filter the list, filters, the list, and Excel and PDF downloads (branded, and logged with the export log)
  - **New payment swap**: find the payment, find the student it belongs to, see both accounts side by side with the expected result, then give the reason, evidence, files and confirmation
  - a swap opens with the payment, both students before, after and now, the timeline, the evidence and the officer's choices
- **The student's fees page** says when a payment on their account was corrected.
- **The student record (Student 360)** lists the reallocations with the other student's number.

## Tests

- `PaymentSwapIT`, the HTTP flow end to end:
  - the check, and the refusals for the same student, a meaningless reason, no confirmation and an open swap
  - Internal Audit refused, and the Students Account Officer and the initiator refused a decision
  - approval without confirmation refused, then approval executed: payment moved and unchanged otherwise, both accounts, ledger untouched, timeline order, both notices
  - no second swap
  - reversal by the Bursar, decided by another Bursar officer, with the original marked `REVERSED`
  - the student's own list without the other student's number
- `check.sql` block V527, in the database: eligibility, refusals, separation of duties, execution, reconciliation, no second swap, the College Finance Controller refused, and the reversal.
- `lib/payment-swaps.test.ts`: refusal wording, the reason test, filters and evidence types.
