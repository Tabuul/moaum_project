# Students Account Officer (V520)

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
| Hanging payments | The desk, the claims, the Ask Interswitch list, the payment events | Recheck at the gateway (`/payments/verify`, `/payments/sweep`), resolve an event, mark a reported receipt not found or reopen it (`PaymentsController.HANGING_DESK`) |

**Never held by the officer:** confirming a payment by hand, refunds, bank credits, payment reversal, ledger and accounting,
gateway keys and settings, the PAYDirect collections import, test payments, the clearance scheme, old fees and old GST uploads,
applicant, postgraduate, deferment, transfer and GST fees, payroll and budget, users and roles, results, courses, admission and
matriculation. `StudentsAccountOfficerIT` checks the refusals (403) with request bodies that pass validation, so each refusal
comes from the office check and not from the form.

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
| Hanging Payments | The hanging payments desk |

## 4. Changes made

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
the office, the time and the reason, as every other change is. Student searches are audited as before. Reading a report and
exporting it are not recorded: the audit trail records changes, not reads.

## 6. Limitations

- **Office hierarchy:** the portal has no office-hierarchy table, so "Bursary" shows as the office's unit.
- **Permissions are per office:** one office cannot be split into separate permissions for different people.
- **Fee changes need no approval:** the portal had no fee approval step, so the officer's fee changes take effect as the
  Bursar's do. The history keeps every earlier amount.
- **Hanging-payment alerts:** the daily PAYDirect "unreported payments" e-mail still goes to the Bursar's office holders only.
- **Remittance matching:** NELFUND remittance matching stays with the offices that hold it today.
