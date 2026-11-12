# Inter-departmental transfers begun on the old portal, and the transfer fee read against every verified payment (V727)

The University's master prompt of 11 November 2026 ("Legacy inter-departmental transfer payment reconciliation and outstanding
balance recovery"). Students who began an inter-departmental transfer (IDT) on the old portal continue it here without paying
twice. The fee is the one the Bursary states (₦20,000 today, on Finance → Fees); what a student owes is that fee less every
verified payment — the old portal's and this portal's. A student who paid ₦10,000 on the old portal owes ₦10,000; one who paid
₦20,000 owes nothing; one who paid nothing owes the whole fee. No figure is written into the code.

The University's decisions of 12 November 2026:

- **Scope.** The old portal's transfer payments made **from 1 September 2025** belong to the current exercise (a stated setting,
  changed on the Old-portal transfers page with a reason; nothing else in the code knows the date).
- **Items.** INTER DEPARTMENTAL TRANFER FORM, INTER DEPT. TRANSFER PROVISIONAL LETTER and INTER DEPT. TRANSFER count toward the
  one fee. CHANGE OF COURSE does not: it is listed for the Bursary to decide. The inter-university items are another process.
- **Applications.** The old portal's applications come in by an upload of its export; old-portal payments also count toward an
  application made here.
- **Desks.** Any verified payment lets the current HOD, the new HOD and the Registry act; only the Academic Office's final
  approval waits for the whole fee, with nothing awaiting the bank.
- Also: no Dean stage (the chain is unchanged); the balance is read against the fee as stated now (an effected transfer against
  the fee it was completed against); imported old-portal payments count as verified as imported; a student who paid more than
  the fee is shown OVERPAID for the Bursary (no automatic refund); nothing is owed until an application exists; a transfer the
  old portal finished is restored (V669/V686), never billed again, and the money that paid for it is no credit for another.

## What stood before

- One `fee_reference` per application, returned unchanged forever (V193) and reopened at its old amount (V690). "Paid" meant that
  one reference confirmed, whatever its amount: an application paid ₦10,000 here read as paid.
- The old portal's 336 transfer payments (₦5.19m from 312 students, imported as confirmed payments on the students' records,
  channel `Legacy`) were never read against an application. The old portal's applications were never brought in.
- The Academic Office's final approval checked only that the one reference was confirmed (V186); `effect_transfer` (V070) alike.
- The transfer fee had no history and could be set to ₦0; the transfer letter printed ₦10,000.

## The database (V727)

- **`finance.transfer_fee_revision`** — every statement of the transfer fee (the figure, the one before, who, which office, why),
  written by a trigger on `finance.fee_setting`, never changed or removed.
- **`people.legacy_transfer_setting`** (the date old-portal payments count from) and **`people.legacy_transfer_item`** (the
  old portal's items and whether each counts). `people.set_legacy_transfer_scope` changes the date, with a reason, and rebuilds
  the list.
- **`people.transfer_payment`** — every payment counted toward an application: this portal's references (`PORTAL`) and the old
  portal's imported payments (`OLD_PORTAL`, read where they are, never re-posted). One payment serves one application. The
  references already drawn are linked by the migration.
- **`people.transfer_entitlement(app)`** — the fee as stated now, what is paid here and on the old portal (verified: confirmed,
  not archived for review, net of refunds approved or paid against it, and for an old-portal payment its reconciliation row
  LINKED), the balance, any excess, the payments, whether a reference open for the balance awaits the bank, and a band:
  `NOT_PAID`, `PENDING`, `PART_PAID`, `SETTLED_IN_PARTS`, `PAID_IN_FULL`, `OVERPAID`; `CLOSED` for a declined, not recommended or
  withdrawn application (nothing more is owed on it); `FEE_NOT_STATED` while the Bursary has stated none. An effected transfer
  is read against the fee it was completed against, kept in **`people.transfer_fee_settlement`**.
- **`people.transfer_fee_reference(app)`** draws the reference for the **balance** (the whole fee before anything is paid),
  returns the one still open for that amount rather than a second, and refuses `TRANSFER_FEE_SETTLED` once nothing is owed.
  **`finance.renew_reference`** renews an expired transfer reference to the one open for the balance, a new one for the
  balance, or the same one reopened; `REFERENCE_NOTHING_OWED` when nothing is owed.
- **A reference is never left open for an old figure.** `people.transfer_close_stale_references(app)` closes an application's
  open references that are no longer for the balance; it runs on every reconciliation, every officer's decision, a revised fee,
  and when the application leaves the desks (effected, declined, withdrawn). Checkout refuses such a reference
  (`TRANSFER_REFERENCE_STALE`), and the payment history sends the student to the transfer page instead of paying it.
- **`people.approve_transfer`** — the current HOD acts once any verified payment stands (`TRANSFER_FEE_UNPAID` before). The
  Academic Office's final approval is refused while anything is owed (`TRANSFER_FEE_OUTSTANDING: … ₦x remains`) or while the
  payment that would settle it awaits the bank (`TRANSFER_PAYMENT_PENDING`); **`people.effect_transfer`** (the V070 route)
  refuses alike. The stages, the offices and decline are unchanged.
- **`people.legacy_transfer_payment`** — the reconciliation list, one row per old-portal transfer payment:
  - `LINKED` to an application. A payment is matched on the student's own record only: the record answers to the matriculation
    number the payment's reference names, the payment carries an old-portal payment number, the record is no duplicate and is
    active, it was paid on or after the stated date, and its item counts. It counts toward the application it already counts
    toward — **a payment once counted stays with that application, whatever became of it** (effected, declined or withdrawn),
    as this portal's own fee does; an officer moves it — else the application the old portal's export names it for (even when
    paid before the stated date), else the student's live application;
  - `AWAITING_APPLICATION` — the student has no application yet; linked the moment one is made here, recorded by an office or
    loaded from the old portal (a trigger on `people.transfer_application`);
  - `USED` — it paid for a transfer the old portal approved and this portal restored (a `people.prior_transfer` approved on or
    after the payment): never a credit for another transfer;
  - `UNMATCHED` with the reason; `NOT_COUNTED` (the item, an officer's decision, or a payment whose purpose or record was since
    changed); `OUT_OF_SCOPE` (paid before the date); `REJECTED` (an officer's decision: it never counts).

  `people.legacy_transfer_reconcile(student or all)` builds and refreshes it (safe to run again; a run that changes nothing
  writes nothing; one student's payments are decided by one run at a time). `people.decide_legacy_transfer_payment` records an
  officer's decision — link to one of the student's applications, not counted, reject, or release back to the rule — with a
  reason; a decision is never rebuilt over. Archiving or correcting (V670) a payment that is linked, awaiting an application or
  used is refused until it is decided on the list.
- **The old portal's export** — `people.legacy_transfer_upload_check(rows)` reads each row without writing and says what would
  become of it (`NEW`, `ATTACH`, `EXISTS`, `ALREADY_MOVED`, `FROM_MISMATCH`, `CONFLICT`, `NOT_ELIGIBLE`, `NO_STUDENT`,
  `OUT_OF_SCOPE` (applied before the stated date), `DUPLICATE_ROW` (one reference or one student more than once among the rows
  that would load), `INVALID`, with the reason). The old portal's session labels lag its dates, so a row is continued in the
  current session whatever its label. `people.legacy_transfer_upload_commit` makes each `NEW` row an application at the stage
  the old portal reached (APPLIED, FROM_OK, TO_OK or REG_OK), with the date applied kept; an `ATTACH` row joins the student's
  application already here (one application a student, never a second) and moves it on to that stage, never back. The old
  record — its reference, date, stage, approvals, documents and payment numbers, the row as received — is kept beside the
  application in **`people.transfer_legacy`** (never changed) and shown on the desk. The upload is refused whole while any row
  cannot be loaded, unless the officer loads the others alone; every row is kept with what became of it
  (`people.legacy_transfer_load`, `_load_row`). The student is found by the matriculation number alone, never by name.
- **`people.transfer_fee_monitor(session)`** — every application with the fee, paid here / on the old portal, balance, band and
  what it awaits (`PAYMENT`, a desk, `DONE`), and every student whose old-portal payments await an application.
- **`people.legacy_transfer_report()`** — the reconciliation report, from the records as they stand.

## The API

- `GET /api/v1/me/transfer` adds `payment` (the live application's fee, paid on the old portal / here, outstanding, band,
  stage and next action: `PAY_NOW`, `PAY_BALANCE`, `COMPLETE_PAYMENT`, `AWAIT_APPROVAL`, `NONE`), `paymentsMade`, `credit` (old-portal
  payments awaiting an application) and `legacy` (the old portal's record). `POST /api/v1/me/transfer/{id}/fee` answers the
  reference for the balance and its amount, read from the reference row.
- `GET /api/v1/transfers` — the desk's rows carry the fee, paid, balance, band and the old portal's record; Approve at the
  Academic Office's desk is offered only when nothing is owed, as the database decides. The Bursary and the Students Account
  Officer may read the desk.
- `/api/v1/transfers/legacy` — the reconciliation list (`?status=&search=`), `POST /{payment}/decision`, `POST /reconcile`,
  `GET|PUT /scope`, `POST /upload/check`, `POST /upload`, `GET /loads`, `GET /report`. Read by the Academic Office, the Registry,
  the Bursary, the Students Account Officer, ICT and administrators; decided by the Academic Office, the Registry, the Bursary
  and ICT; the export loaded by the Academic Office, the Registry and ICT.
- `/api/v1/transfers/fees` — the monitor (list, `/summary`, `/options`, `/export` recorded as `TRANSFER_FEES`); an HOD sees the
  applications from or to their department, a Dean their faculty.
- `PUT /api/v1/finance/transfer-fee` refuses ₦0; `GET /api/v1/finance/transfer-fee/revisions` lists every statement.
- The gateway names a transfer reference "inter-departmental transfer fee" and returns the payer to `/student/transfer?paid=…`.

## The screens

- **Inter-departmental transfer (student).** The fee panel: total fee, paid on the old portal, paid here, outstanding, payment
  status, application status and next action. **PAY NOW** when nothing is paid, **PAY OUTSTANDING BALANCE** after a part
  payment; it pays the reference's own amount through the existing gateway. No button once paid in full or once the
  application is closed. An overpayment is shown for the Bursary, with no refund promised. Old-portal credit with no
  application says it will count when the student applies. The old portal's record (reference, date, stage, approvals,
  documents) is shown. The dashboard carries a transfer card when the student has an application or credit.
- **The transfer letter** reads the fee and what was paid from the server.
- **Inter-departmental transfer (desk).** Tiles by payment state (awaiting payment, part paid, with the desks, ready for final
  approval, completed), tabs for awaiting payment, balance owed and ready for final approval, the paid and balance columns, and
  the old portal's record under each continued application.
- **Old-portal transfers** — the reconciliation list with decisions, re-run, the scope, the export upload (check first, then
  load; the rows that can load alone), the load history and the reconciliation report.
- **Transfer fees** — the monitor, with filters and an export.
- **Fee schedule** — the transfer fee refuses ₦0 and lists its revisions.

## The live figures

The reconciliation on a copy of the University's data (payments recorded to 21 October 2026), with the University's decisions
and the fee at ₦20,000:

| | |
|---|---|
| Old-portal transfer payments read | 336 |
| Awaiting an application (in scope) | 260 payments, 239 students, ₦4,410,000 |
| Paid before 1 September 2025 (out of scope) | 75 |
| CHANGE OF COURSE (not counted, for the Bursary) | 1 |
| Unmatched | 0 |
| Students who paid the fee in full | 190 |
| Students who paid half (₦10,000) — owe ₦10,000 each when they apply | 45 (₦450,000) |
| Students who paid above the fee (₦40,000) — for the Bursary | 4 (₦80,000 above the fee) |
| The old portal's applications loaded | 0 — the export has not been supplied yet |
| Applications on this portal, live | 9: 7 with nothing paid, 1 part paid (₦10,000 of ₦20,000), 1 paid in full; ₦150,000 outstanding |

None of the old-portal payers has an application here yet, so nothing is linked until they apply or the export is loaded. The
figures on the portal (Old-portal transfers → Reconciliation report) are read from the records as they stand and change as
students apply, pay and the export is loaded.
