# The College Finance Controller's fee reports (22 October 2026)

**Who:** the Finance Controller, College of Health Sciences (office `financecontroller`), held to the College on the server
(`OfficeScope.bound`, V603). The College is the faculty Basic Medical Sciences (BAMS): 14 programmes, 7 undergraduate and 7
postgraduate.

The University asked that every College transaction reach the Finance Controller, reported by date range, department, programme and
so on, the way the Bursary reports the University's. The Controller now reads the Bursary's own reports, never copies of them:

| Screen | What it reports | Held to the College by |
|---|---|---|
| **Payments Query** (`/finance/payments`) | every confirmed student payment — newest first, the total and the breakdown of the whole matching set — by session, faculty, department, programme, level, payment category, channel and a date range; Excel and PDF | `FinanceController.payments`: `scope.bound` fills the College's faculty and refuses another faculty, department or programme (`SCOPE_COLLEGE…`); the lists offer the College's alone |
| **School Fees Report** (`/finance/fee-report`) | for a session, by department and level: who paid in full, who owes (part payments among them), what was paid and owed, with the grand total; Excel and PDF | `FeeReportController` already held its reader by `scope.bound`; the Controller was added to its readers |
| **Payment History** (`/finance/student-payment-history`) | one student's payments, biodata and course registration, by matric number | the student search and the full record were College-only for the office already (V603) |
| **Student Payment Report** (`/college/payments`) | each student's position for a session (payable, paid, outstanding) — as before | — |

**The dashboard** (`/college/dashboard`) adds **Recent payments** — the College's newest confirmed payments (`/finance/payments?limit=15`)
with *Query all payments* — and links to the Payments Query and the School Fees Report beside the Student Payment Report.

The Bursary, the Students Account Officer and the other readers see the whole University as before.

**Tests:** `CollegePaymentsIT` — the Controller's query finds the College payment and never another faculty's (the Bursar's finds both),
by programme and by date; the faculty choices are the College's; another faculty or programme is refused; the School Fees Report opens
for the Controller, held to the College. `FeeReportIT` and `FinanceControllerScopeIT` unchanged and passing.
