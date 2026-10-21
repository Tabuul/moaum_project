# Students Account Officer (V520, V591)

A controlled sub-office of the Bursary for students' money: payment reports, school fees setup and binding, NELFUND reports,
students' accounts and hanging payments. It reuses the portal's finance, payment, NELFUND, student, reporting, audit and export
engines. No second finance, NELFUND or student system was built.

## 1. Office and role

| | |
|---|---|
| Office code | `studentaccounts` (in `ref.office`, migration V520) |
| Display name | Students Account Officer (unit shown as *Bursary · students' accounts*) |
| Parent | Bursary. The portal has no office-hierarchy table, so the parent appears as the office's unit, as for the College Finance Controller. |
| Scope | institution (University-wide) |
| Who holds it | A person is given the office on **Users & roles**, like any other office (`iam.office_assignment`). No staff record is duplicated. |

`db/verify.sql` and the office property in `db/check.sql` now count **45** offices. The Railway deploy runs `verify.sql`, so
both counts were raised in the same commit.

## 2. Permissions

The portal's permissions are the API's: each endpoint names the offices it admits, and the database enforces the rest. A token
carries only the offices the person holds today. The officer's powers are therefore exactly the endpoints that name
`OFFICE_studentaccounts`.

| Duty | Reads | Acts |
|---|---|---|
| Payment reports | Financial Analytics summary and transactions (University-wide, amounts and transactions: `AnalyticsScope.MONEY`), Payments Query, the Bursary's view | — |
| School fees | Fee schedule, gaps, fee sources, structure, copy preview, **fee history** | Add, edit or end a fee line; the gap sheet; copy a session's fees; upload the approved structure; fee sources (`FinanceController.FEE_SETTERS`) |
| NELFUND | Figures, students, statements, session funding report, old NELFUND rows and summary | — (credits, reversals, status, reset, batches, remittance matching and withdrawals stay the Bursar's) |
| Students | Student Query, the student's record with its school fees and payment history, unpaid registrations, examination cards withheld | — |
| Hanging payments | The desk, the claims, the Ask Interswitch list, the payment events | Recheck any payer's reference at the gateway (`/payments/verify`, `/payments/sweep`), resolve an event, mark a reported receipt not found or reopen it (`PaymentsController.HANGING_DESK`; V522 batch: `/payments/verify` and `/payments/state` treat the officer as an office, not as the payer) |
| Student levels (V591) | Student Level Management and Level Change History, every student (`SupportAccess.LEVEL_DESK`: the officer reaches the University there with the level capabilities only — `VIEW_STUDENT`, `PROGRESS_LEVEL`, `CORRECT_LEVEL`, `VIEW_LEVEL_HISTORY`); the student finder the desk needs | Progress a student to the next level or correct the level, with a reason (`people.support_set_level`, V500's rules unchanged; recorded on the cohort decision history and the support ledger under the office). No other door of the ICT Support Desk: the support record, tickets, password resets, the student's portal and support overrides stay `AGENTS` |
| Old fees history (V591, V607) | The Old Fees History desk: the reconciliation, doubles, mislabelled records, overpaid, double charges, payments never received, what is loaded, the officer's uploads and what became of them | Send the old portal's fees export, with its item codes, **for the Bursar's approval** (V607: nothing is written to the records until the Bursar approves; `LegacyFeeUploadController`), withdraw an upload not yet decided, put mislabelled records right, withdraw doubles (`FinanceController.OLD_FEES_DESK`). What needs the bank's word or moves money — a double charge checked, a payment never received raised or decided (`finance.bursary_actor`), an excess carried or refunded — the ledger posted and the go-live reset stay the Bursar's; the screen offers them to the Bursary only |
| Old GST payments (V591) | The Old GST Payments desk: the figures, the runs, the staged rows, the exception queue, the report | Stage the old portal's GST export (and its dry run), apply a run to the ledger, match, reconcile, relabel or reject a row, find a student (`LegacyGstController.BURSARY`, as the Bursar and the finance controller) |
| Legacy financial reconciliation (V625) | The desk: the session's outstanding fees classified (what the student owes, what the University holds), the e-wallet figures, the wallet credit requests and the history, the reports; one student's legacy picture | Confirm an overpayment against the records and initiate the wallet credit request (the amount never above the excess; a different amount with its reason; the explicit confirmation), resubmit a returned request, withdraw one. Never approve: a Bursar officer other than the initiator approves, and the wallet is credited only then |

**Never held by the officer:** confirming a payment by hand, refunds, bank credits, payment reversal, ledger and accounting,
gateway keys and settings, the PAYDirect collections import, test payments, the clearance scheme, the old fees go-live reset,
applicant, postgraduate, deferment, transfer and GST fees, payroll and budget, users and roles, results, courses, admission and
matriculation. `StudentsAccountOfficerIT` checks the refusals (403) with request bodies that pass validation, so each
refusal comes from the office check and not from the form.

## 3. Screens (menu: Students Account Officer)

| Menu | Screen (existing unless noted) |
|---|---|
| Dashboard | **New:** today, this week, this month and this year (amount, transactions and paying students kept apart); the session's paid and outstanding; NELFUND; hanging payments; successful, pending, failed and refunded; school fees by faculty with a link into the reports; quick actions |
| Payment Reports & Statistics | Financial Analytics: day, week, month, quarter or year (presets today, this week, this month, this year); faculty, department, programme, level, session, semester, gender, entry mode, channel, purpose and programme type filters; charts; the transactions and a student's payment history. Excel and PDF through the standard export engine. |
| Payments Query | The payments list |
| Fee Setup and Binding | The fee schedule. The officer may state school-fee lines; every other panel on the page stays the Bursar's. **New:** fee history from the audit trail, exportable to Excel. |
| NELFUND Reports & Wallets, NELFUND Students, Old NELFUND Payments | The NELFUND desk, read only |
| Student Accounts | Student Query, which opens the student's record (fees, payment history) |
| Unpaid Registrations, Examination Cards Withheld | As for the Bursary |
| Hanging Payments | The hanging payments desk: Ask the gateway, Resolve, Not found and Reopen are the officer's; importing Interswitch's collections report stays on the Bursary's gateways screen, so the screen does not offer it |
| Student Level Management, Level Change History (V591) | ICT Support's level desk (`/helpdesk/levels`, `/helpdesk/levels/history`) under the officer's own eyebrow: the support record and the Support Desk links are not offered, a student in the history opens on the level desk |
| Old Fees History (V591, V607) | The Bursary's Old Fees History desk (`/finance/legacy-fees`): the file is sent to the Bursar for approval ("Send N rows to the Bursar for approval"), and **Uploads for the Bursar's approval** lists each upload with its state; the tabs; the Bursary-only acts (double charges, payments never received, overpaid decisions, the ledger, the reset) are shown without their buttons |
| Old GST Payments (V591) | The Bursary's Old GST Payments desk (`/finance/legacy-gst`), every act |
| Legacy Financial Reconciliation (V625) | `/finance/legacy-reconciliation`: outstanding fees, e-wallet top-ups, wallet credit requests, history; the dashboard's legacy tiles |

## 4. Changes made

### V607: the officer's old fees uploads wait for the Bursar's approval

V591 let the officer load the old portal's fees export straight onto the records. Since V607 the officer keeps the desk and the
upload, but nothing the officer uploads is written to the records until the Bursar approves it.

- **The officer** chooses the file as before and presses **Send N rows to the Bursar for approval**. The upload (reference
  `OFU-YYYY-NNNNN`) is opened with the file's payment-item codes, its rows are sent in parts and it is sent to the Bursar, who is
  told (`OLD_FEES_UPLOAD_WAITING`). Once sent, its rows cannot be changed or removed, so what the Bursar approves is what the
  officer sent. The officer may withdraw an upload not yet decided and is told when it is approved or rejected
  (`OLD_FEES_UPLOAD_DECIDED`).
- **The Bursar** opens it under **Uploads for the Bursar's approval**: the summary (rows, students, sessions, the amount stated),
  the rows (and all of them as Excel), and **Check what approving would do** — the import run on the rows and undone, so nothing
  is written (each part is checked on its own). **Approve and load** sets the item codes, then loads the rows a few parts at a time
  exactly as the Bursar's own upload is, and keeps the totals. **Reject** needs a reason of ten characters or more. The person who
  uploaded never approves the upload, even when they also hold the Bursar's office.
- The Bursary's own file still loads directly. Loading a file directly and setting item codes directly are now the Bursary's
  only (`POST /finance/legacy-fees`, `POST /finance/legacy-fees/item-codes`). The officer's other acts on the desk (records put
  right, doubles withdrawn) are unchanged.
- **Database (V607):** `finance.legacy_fee_upload` and `finance.legacy_fee_upload_part`, with `finance.legacy_upload_open`, `_add`,
  `_submit`, `_withdraw` (the officer) and `_check`, `_approve`, `_reject` (the Bursar). The functions check the offices and states
  themselves.
- **API:** `GET/POST /finance/legacy-fees/uploads`, `GET /{id}`, `GET /{id}/rows`, `POST /{id}/rows`, `/submit`, `/withdraw`,
  `/check`, `/approve`, `/reject`.
- **Tests:** check.sql's V607 block; `OldFeesUploadIT`; `StudentsAccountOfficerIT` (the direct load refused).

### V520

- **Database (V520):** the office row. Nothing else is written.
- **Fee setup:** a fee line added or edited by hand is refused (`FEE_LINE_DUPLICATE`) while an active line already states the
  same item for the same session, level, entry mode, faculty, programme, group and semester. The bulk uploads keep their own
  rules: the structure upload replaces the session's structure, and the gap sheet and the copy skip lines already held. The live
  copy's 591 active lines hold no such duplicate. Fee history (`GET /finance/sessions/{s}/{y}/schedule/history`) reads every
  change to the session's lines from the audit trail (`audit.entries`): who, when, why, and the amount before and after.
- **API:** the office was added to the reader lists named in section 2, plus the new `FEE_SETTERS` and `HANGING_DESK`
  permissions.
- **Frontend:** the office label and unit, the menu, the dashboard, the fee page's permissions and the fee history panel.

## 5. Audit

Every change the officer makes (fee lines, hanging payment events and claims) is written to the audit trail with the person,
the office, the time and the reason, as every other change is. Student searches are audited as before. Since V523 every report
exported through the portal's export engine (Excel, or print / PDF) is on the export log with the person, office, report, rows,
filters and the serial printed on the document; Internal Audit reads it on **Export Log**. Reading a screen is not recorded.

## 6. Limitations

- **Office hierarchy:** the portal has no office-hierarchy table, so "Bursary" shows as the office's unit.
- **Permissions are per office:** one office cannot be split into separate permissions for different people.
- **Fee changes need no approval:** the portal had no fee approval step, so the officer's fee changes take effect as the
  Bursar's do. The history keeps every earlier amount.
- **Alerts:** since V522 the daily "Quickteller payments not reported" e-mail and the "students with no fee stated" alert reach
  the officer as well as the Bursar. The gateway alerts (the Quickteller door gone quiet, notifications not settled) stay with
  the Bursary and ICT.
- **Remittance matching:** NELFUND remittance matching stays with the offices that hold it today.
