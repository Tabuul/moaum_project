# Dossier F — Finance, Payments, Wallet, Expenditure, Human Resources and Staff

Read-only audit of the MOAUM portal as of commit 8c2b6fa. Sources: `api/src/main/java/ng/edu/moaum/portal/{finance,payments,wallet,expenditure,hrm,staff}`, migrations `db/V026…V256`, `frontend/src/app/{finance,payroll,hr,staff,vouchers,stores,student/fees,student/receipt,student/wallet,audit}` (sections 1–6 summarise each screen from routes.md, page.tsx gating and the API each screen calls; the verbatim label-level audit of every TSX — titles, tiles, fields, buttons, X-Reason/toast texts, empty states, exports and the unfinished items — is in Annex A (finance/wallet/expenditure pages) and Annex B (student money, payroll/HR/staff, self-service, vouchers/stores, and the `t/hrm`/`r/bursar` route ids) at the end of this file). Local DB queried read-only for seeds and counts.

Note on the inventory: `api.md` omits two endpoints declared with fully-qualified `@org.springframework.web.bind.annotation.PutMapping`: `PUT /api/v1/payments/gateways/{gateway}/key` (ict, admin, super) and `PUT /api/v1/payments/paydirect/billers/{scope}` (bursar, ict, admin, super) — `payments/PaymentsController.java:152,186`.

---

# 1. Finance — fees, charges, references, confirmation, Bursary desk, refunds, reconciliation, general ledger
(API module: `finance` — FinanceController, RefundsController, AccountingController; schema: `finance`; pages: `finance/fees`, `finance/payments`, `finance/payments-history`, `finance/legacy-fees`, `finance/exceptions`, `finance/refunds`, `finance/reconcile`, `finance/ledger`, `finance/accounting`, `finance/held-scripts`, `college/payments`, `audit/revenue`, `student/fees`, `student/receipt/[reference]`, `verify/receipt/[reference]`)

## 1.1 Purpose
The finance module states what each student owes for a session (the fee schedule), computes each student's charge from it, mints payment references, confirms payments (by gateway, by the Bursary against a bank record, or by import), issues receipt numbers, and answers the position — due, paid, balance, instalments, arrears — that every gate in the portal (registration, examination, results, transcript, hostel, ID card) reads. Around that core sit the Bursary's desks: bank credits without a reference (maker–checker), refunds (maker–checker), reconciliation against the bank, a day book and payments query with Excel/PDF, legacy imports from the old portal, and a cash-basis double-entry general ledger with trial balance, income & expenditure and balance sheet.

## 1.2 Users and roles
- `FinanceController.READERS` (`finance/FinanceController.java:35`): bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc — read schedule, references, day book, payments query, reconciliation list, bank credits, bursary tiles.
- `BURSARY` (`:36`): bursar, super — write schedule, confirm references, clearance scheme, bank credits (record/propose/approve/reject), legacy fees import, transfer fee.
- `RECONCILERS` (`:38`): bursar, audit, deputyaudit, super — `POST /finance/reconciliation/{reference}/check`.
- `MIGRATORS` (`:39`): bursar, super, ict, admin — `POST /finance/payments/import`.
- Refunds: readers bursar, super, audit, admin; writers bursar, super (`RefundsController.java:31-32`). Maker–checker enforced in SQL by person, not office.
- Accounting: readers as finance READERS plus deputyaudit; posting (sync, journal, reverse) bursar, super (`AccountingController.java:165-166`).
- Students read their own position through `studentportal` (`GET /api/v1/me/fees`, `POST /api/v1/me/fees/references`, `GET /api/v1/me/fees/receipts/{reference}`; `studentportal/MeController.java:59-71`).
- Scope: none of these endpoints is department-scoped; the Finance Controller (CHS) reaches the fee screen and the College payment report through the menu but the finance API guards do not include `financecontroller` (see 1.13 — the fee-setup page is listed in the financecontroller menu but `finance/*` READERS excludes that office; the page's read calls would return 403 unless the person also holds another office).

## 1.3 Navigation (menus.md)
Bursar → Finance: Held Scripts `/finance/held-scripts`; College Payment Report `/college/payments`; Fee Setup and Schedule `/finance/fees`; Old Fees History `/finance/legacy-fees`; Payment Investigation `/finance/exceptions`; Payments Query `/finance/payments`; Payment History Upload `/finance/payments-history`; Refunds & Credits `/finance/refunds`; Cash Office & Assets `/finance/exceptions`; Accounting & Books `/finance/accounting`; Transactions & Accounts `/finance/ledger`; Reconciliation `/finance/reconcile`. Bursar → Overview: Dashboard `r/bursar` (route id maps to "—" in menus.md, i.e. no Next.js URL; see 1.13).
Admin → Finance: Fee Schedule `/finance/fees` (t/feesched), Payment Investigation `/finance/exceptions`, Ledger, Reconciliation, Accounting & Books. Audit → Finance: Ledger `/finance/ledger`, Reconciliation `/finance/reconcile`, Revenue & Student Income `/audit/revenue`. financecontroller/pgsecretary → Fee Setup and Schedule `/finance/fees` (t/feesetup). Student → Start here: School Fees — Pay First `/student/fees`.

## 1.4 Screens
- **Fee Setup and Schedule** `/finance/fees` (`finance/fees/page.tsx` + `FeeSchedule.tsx`, 587 lines; modals, tabs, filters, role line, toasts). Calls: `GET /finance/sessions/{s}/{y}/schedule`, `POST …/schedule` (add line), `PUT …/schedule/{id}` (edit), `POST …/schedule/{id}/end`, `POST …/schedule/clear`, `GET/POST …/fee-structure` (bulk approved-fees upload), `GET /finance/fee-groups`, `GET /finance/fee-items`, `GET /finance/programmes`, `GET /finance/references?session=`, `GET/PUT /finance/transfer-fee`, `POST /finance/clearance-scheme`, `GET /ref/sessions`, `GET /ref/structure`, plus applicant fees (`/admissions/sessions/{s}/applicant-fees`) and PG fees (`/pg/sessions/{s}/fees`) from other modules. A fee line's fields (server record `Item`, `FinanceController.java:41`): item (required, ≤120), amount (required, ≥0), level (100–900 or blank), entryMode (≤20), facultyCode, programmeCode, feeGroup (≤12 each), semester (1–3 or blank), ord. Server errors: "A level is 100 to 900 (700–900 are postgraduate)." / "A semester is 1 or 2." / "That fee line is not on the current schedule." (`:173,176,230`). Bulk upload errors: "The structure has no rows to read." (`:86`).
- **Payments Query** `/finance/payments` (`Payments.tsx`; Excel export, print/PDF export, table, form). `GET /finance/payments?session&faculty&dept&programme&level&category&channel&from&to&limit` returns rows (confirmed student payments newest first), `count`, `total`, `byCategory`, `byFaculty`, and option lists (sessions with confirmed payments, faculties, departments, programmes, categories from `finance.payment_category`, channels) (`FinanceController.java:348-399`).
- **Payment History Upload** `/finance/payments-history` (`PaymentsHistory.tsx`; role line). `POST /finance/payments/import` with `{rows:[…]}`; the importer accepts matric/admission/JAMB numbers, session, amount, purpose, date, channel, reference, receipt; returns rows/imported/duplicate/no_student/bad_amount/skipped/first_error (`db/V136:33-121`). Error when empty: "The file has no rows to read." (`FinanceController.java:72`).
- **Old Fees History** `/finance/legacy-fees` (`LegacyFees.tsx`). `POST /finance/legacy-fees` `{rows}`; each row matric + session (`YYYY/YYYY`) + optional semester + amount (blank = settle in full against the schedule) (`db/V087:23-98`). Returns rows/cleared/no_student/no_due.
- **Payment Investigation / Cash Office & Assets** `/finance/exceptions` (`Exceptions.tsx`; table, form, toasts). Calls `GET /finance/bank-credits?state=open|posted|all`, `POST /finance/bank-credits` (Credit: receivedOn, bank ≤80 req, instrument ≤80 req, amount ≥0.01 req, payer ≤200, note ≤400), `POST …/{id}/propose` (reference req ≤60, why req ≤600), `POST …/{id}/approve`, `POST …/{id}/reject` (why req ≤400), and `GET /payments/bursary` for gateway exceptions (`FinanceController.java:300-476`).
- **Refunds & Credits** `/finance/refunds` (`Refunds.tsx`; modals). `GET /finance/refunds?state`, `GET /finance/refunds/transaction?reference=` (payer, number, amount, purpose of a confirmed transaction), `POST /finance/refunds` (Propose: student uuid opt, payer req ≤200, reason req ≤400, amount ≥0.01, bank ≤120, accountName ≤200, accountLast4 ≤8, source ≤60), `…/{id}/approve`, `…/{id}/reject` (why ≤2000), `…/{id}/pay` (`RefundsController.java:40-126`).
- **Reconciliation** `/finance/reconcile` (`page.tsx` + `ReconcileLedger.tsx`). `GET /finance/reconciliation?from&to` (default last 30 days), `POST /finance/reconciliation/{reference}/check` (result MATCHED|DISCREPANCY ≤20, bankReference ≤120, note ≤400), `GET /finance/bank-credits?state=open`, `GET /payments/bursary`.
- **Transactions & Accounts / Ledger** `/finance/ledger` (`Ledger.tsx`; filters). `GET /finance/ledger?from&to` → `finance.day_book` rows (reference, confirmed_at, payer, number, purpose, amount, channel, receipt_no, note, session), student and applicant fees together (`db/V037:119-131`).
- **Accounting & Books** `/finance/accounting` (`Accounting.tsx`, 300 lines; tabs, modals). Reads overview (cash on 1010/1020/1050, income/expenditure YTD, unposted counts), chart, trial balance (`asOf`), ledger per account (`account`, `from`, `to`; error "No such account."), income-expenditure, balance sheet, journals (nested lines). Writes: `POST /finance/accounting/sync`; `POST /finance/accounting/journals` (JournalIn: date req, memo req ≤300, lines ≥2 each account ≤20 + debit or credit + narration ≤300 + session ≤12; errors "A journal needs at least two lines.", "Each line is a debit or a credit, and positive.", "The journal does not balance: debits X ≠ credits Y.", "A line names an account that is not on the chart."); `POST …/journals/{id}/reverse` (reason req ≤300) (`AccountingController.java:293-353`).
- **Held Scripts** `/finance/held-scripts` (`HeldOwing.tsx`) reads `GET /results/held/owing` (results module) — the students whose scripts are held for fees; read-only table.
- **College Payment Report** `/college/payments` ("Student Payment Report"; Excel, print, search, filters) reads `GET /college/payments` built on `finance.payment_position` (`db/V256`), statuses FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE; offices bursar, collegesecretary, financecontroller, provost (+ readers). Tested by `CollegePaymentsIT.theReportReadsThePositionBySessionAndBySemester`.
- **Revenue & Student Income** `/audit/revenue` (audit) reads `GET /finance/bursary?session=` and `GET /reports/revenue?session=`.
- **Student — School Fees — Pay First** `/student/fees` (`student/fees/page.tsx`, `GET /me/fees?session=`). Payload (`studentportal/StudentPortalService.java:149-179`): `charges` (item, amount from `finance.charges`), `due`, `paid`, `balance`, `instalmentsPaid`, `paidInFull`, `hasArrears`, `firstSemesterOutstanding`, `secondSemesterOutstanding`, `clearsRegistration` (this semester's fees fully paid), `schemeProblem` ("No clearance scheme is in force, so the examination, results and transcript are not yet released against a payment; the Bursar states the scheme. Course registration opens on this semester's school fees, paid in full."), `references` (the student's own), `sessions` (sessions with charges). Pay: `POST /me/fees/references` `{session, amount}` (amount blank = whole balance) mints `MOAUM-FEE-…`; then `POST /payments/checkout` `{reference, gateway}` → `{url}` (Paystack/Flutterwave/Quickteller) or a PayDirect instruction `{prn, billerCode, billerName, payLink, ussd:"*723*<biller>*<amount>#"}`; `POST /payments/verify` `{reference}` = "check again". Routes `s/pay` and `s/receipt` both resolve to `/student/fees`.
- **Receipt** `/student/receipt/[reference]` + `pdf/route.ts` reads `GET /me/fees/receipts/{reference}` (reference, receipt_no, amount, purpose, session, channel, confirmed_at, name "SURNAME, Other", matricNo, programme, level at the time of the session). Public check `/verify/receipt/[reference]` → `GET /api/v1/verify/receipt/{reference}?c=<token>`; the token is the first 12 hex of SHA-256(`reference|receiptNo`) upper-cased; without a matching token the answer is `{genuine:false}`; with it: name, matricNo, programme, level, amount, purpose, session, term (`finance.payment_term`: "First Semester" / "Second Semester" / "Third Semester" / "Full session"), channel, confirmedOn, receiptNo, passport data-URL (`verify/VerifyController.java:36-104`).

## 1.5 Workflow and statuses
**Fee line**: live while `ended_at IS NULL`; "end" or "clear" or a bulk upload sets `ended_at = now()` (soft end; charges ignore ended lines immediately) (`FinanceController.java:193,204`; `db/V216:29`).
**Payment reference** (`finance.payment_reference`): no status column. States are derived: OPEN = `confirmed_at IS NULL AND expires_at > now()` (24 h validity, `db/V131:44`); EXPIRED = unconfirmed past `expires_at`; CONFIRMED = `confirmed_at IS NOT NULL` (CHECK `ck_pref_confirmed` requires confirmed_by, channel and receipt_no). Reference shape `MOAUM-FEE-<last 7 alphanumerics of matric/admission no>-<4 random digits>`, retried up to 20 times on collision (`db/V131`). Other-purpose references (transcript, hostel, library fine, wallet top-up, gateway test) come from `finance.new_purpose_reference` with the same shape (`db/V027:342`). Receipt number `RCT-<first 4 of session>-<5-digit series RECEIPT per session>` (`db/V033:216`). Channels written: gateway "Card · Paystack|Flutterwave|Quickteller", "Quickteller PayDirect", "Bank branch" (approved bank credit), "NELFUND wallet", "Legacy", "MIGRATION" or the uploaded channel, the Bursary's typed channel on manual confirm.
**Bank credit** (`ck_bc_state`): UNMATCHED → PROPOSED (one officer names a reference + why) → POSTED (a *different* officer approves; runs `finance.confirm_payment` or `admissions.confirm_fee` with channel "Bank branch") ; reject returns PROPOSED → UNMATCHED with `rejected_why`; REVERSED exists in the CHECK but no function sets it (`db/V037:62-84,162-215`).
**Refund** (`ck_rf_state`): PROPOSED → APPROVED (second person) → PAID; PROPOSED → REJECTED (why required). Reference `RF-YYYY-NNNN` (`db/V043`, `V067`).
**Reconciliation**: append-only rows per confirmed reference, result MATCHED | DISCREPANCY (note mandatory for a discrepancy) (`db/V068`).
**GL journal**: POSTED → REVERSED (by posting a reversal journal that `reverses` it); a source transaction is posted at most once (`uq_gl_journal_source`).
**Clearance scheme**: `finance.put_scheme_in_force(instrument, from)` creates a `policy.version(kind='clearance')` with the recommended rules REGISTRATION/ID_CARD/LIBRARY → INSTALMENT_1, HOSTEL → NEVER_GATED, EXAMINATION/RESULTS/TRANSCRIPT/CONVOCATION → PAID_IN_FULL; two schemes may not overlap (`db/V026:226-256`). Seeded in the local DB: "DEMO — BUR/DEMO/1" from 2026-09-25.

## 1.6 Business rules and validations
- **Charge computation** `finance.charges(student, session)` (`db/V161:12-51`): a schedule line applies when every filter it carries is blank or matches — `level = current_level` (ignored for a spillover student), `entry_mode`, `faculty_code` (of the programme), `programme_code`, `fee_group` (via `ref.fee_group.applies_category` vs the programme category), `indigene` (student's state of origin vs `finance.fee_setting.home_state`, default 'Benue'), `spillover = is_spill` (student past `finance.final_level` — 900 for postgraduate programmes, 600 for C00061 Medicine, 500 for LL.B/Pharmacy, else 400 — and not GRADUATED, `db/V255:359`), and `semester IS NULL OR semester <= max OPEN semester` of the session (defaults to 3 when none is open) — so charges accumulate as semesters open (V144). Item labels "(semester 1)" are rendered "(First Semester)" etc.
- **Position** `finance.position` (`db/V027:322-339`): due = Σ charges; paid = Σ confirmed references of the session whose purpose LIKE 'School fees%'; balance = max(due − paid, 0); `instalments_paid` = 2 if due = 0 or paid ≥ due, 1 if paid×2 ≥ due, else 0; `paid_in_full` = due = 0 or paid ≥ due; `has_arrears` = any earlier session with a live schedule where that session's charges exceed its confirmed school-fee payments.
- **Per-semester gate** `finance.due_for_semester` / `finance.semester_cleared` (`db/V149`): registration for semester n needs confirmed school-fee payments ≥ the charge up to and including semester n; error "the first/second semester school fees for 2026/2027 are not fully paid" with hint "Course registration for a semester opens when that semester's school fees are cleared in full; the position updates the moment a payment is confirmed."
- **Clearance for other purposes** `finance.clears(student, session, purpose)` → `policy.clears` on instalments/paid_in_full/arrears; FAILS CLOSED with "no clearance scheme in force for UNIVERSITY on <date> — D-Q4 is unanswered" when no scheme exists (`db/V004:145-175`).
- **Minting** `finance.new_reference` (`db/V131`): refuses "no charge is stated for <session> yet" (hint: the Bursar states the schedule first), "a payment is for an amount", "the amount X is more than the balance of Y" (hint: "Pay the balance, or part of it; nothing is taken beyond what is owed.").
- **Confirmation** `finance.confirm_payment(reference, channel, note)` (`db/V033:207-250`): unknown reference → 23503 "no reference X was generated by this portal" (hint: money sent elsewhere did not reach the University); already confirmed → returns 'already confirmed' (idempotent); requires an actor ("a payment is confirmed by a person"); issues the receipt number; side effects by purpose: `Transcript TRN-…` marks the transcript request paid and READY or HELD_AT_CLEARANCE, `Hostel accommodation%` → `hostel.confirm_by_reference`, `Library fine%` → `library.settle_by_reference`, `Wallet top-up%` → TOPUP wallet entry; then queues the email and SMS (1.7).
- **Bank credit**: proposal requires a reason, a portal-generated reference, not already confirmed ("Money against a settled reference is a duplicate: raise a credit for the student, not a second posting."), credit ≥ reference amount ("A part payment is applied against a reference for the part; generate one for the amount received."); approval by the proposer refused: "the officer who proposed a posting does not approve it" (`db/V037:162-200`); unique (bank, instrument) among non-reversed credits.
- **Refund**: amount > 0, payer and reason required; with a source reference it must be portal-issued and confirmed and the refund ≤ what was paid ("a refund of NGN X exceeds the NGN Y paid on Z"); approver ≠ proposer ("the officer who raised a refund does not approve it"); pay only when APPROVED (`db/V043`, `V067`).
- **Legacy/history imports**: rows without a matching student are counted (`no_student`), never created; legacy rows are idempotent on the derived reference `MOAUM-LEG-<matric>-<YYYY-YYYY[-Sn]>` (upsert), history rows on their given/derived reference (`MIGR-…`, `ON CONFLICT DO NOTHING`); a real `YYYY/YYYY` session on a history row is created via `assessment.ensure_session` (`db/V136`).
- **Fee structure upload** replaces the session's structure (ends all live lines first); faculty matched by code, exact name, then name LIKE; unknown levels/modes/semesters are blanked (applies to every); indigene parsed from 'IND…'/'NON…'/'NN…' (`db/V216`).
- **GL**: every journal must balance (deferred constraint trigger `gl_balance`, "Journal … is out of balance"); a line is a debit or a credit, never both (`ck_gl_post_amt`); `gl_sync` maps payment categories to income accounts 4010–4090 and voucher kinds to expense accounts 5100/5210/5220/5230/5240/5300/5900 by keyword (`db/V145:157-186`).
- **Transfer fee**: `finance.fee_setting.transfer_fee` is NULL until the Bursar sets it (no default); `people.transfer_fee()` reads it (`FinanceController.java:238-256`).

## 1.7 Notifications
| Event | Trigger | Recipient | Channel | Subject / body |
|---|---|---|---|---|
| Payment confirmed (any path: gateway, bank branch, import, wallet apply, PayDirect) | `finance.confirm_payment` (`db/V033:237-247`) | student (via `people.student_reach`) | EMAIL | "Your payment is confirmed" — "Your payment of NGN <amt> against reference <ref> is confirmed. Receipt <no>. " + purpose-specific sentence (transcript with the Registry / bed space confirmed / Library fine settled / wallet credited / "Your charges for <session> are settled in full." / "NGN <balance> remains for <session>.") + " Sign in to download the receipt." |
| same | same | student | SMS | "MOAUM: payment <ref> confirmed, receipt <no>." |
No notifications are queued for bank credits, refunds, reconciliation, GL or fee-schedule changes.

## 1.8 Reports, exports and documents
- Payments Query: Excel and print/PDF exports of the filtered confirmed payments with totals and breakdowns (front-end `brandedXlsx`/`brandedPrint`).
- College Student Payment Report (`/college/payments`): Excel and PDF; per student payable/paid/outstanding/status/last payment; by session or by semester.
- Receipt PDF (`student/receipt/[reference]/pdf/route.ts`): the student's receipt with a QR to `/verify/receipt/<reference>?c=<12-hex token>`; public verification returns the Bursary record (with the semester term and passport) only when the token matches.
- Day book / ledger, reconciliation list, bank credits list (tables on screen).
- Accounting: trial balance, ledger per account with running balance, income & expenditure (sections INCOME/EXPENSE/INCOME_TOTAL/EXPENSE_TOTAL/SURPLUS), balance sheet (ASSET/LIABILITY/EQUITY/ASSET_TOTAL/FUNDS_TOTAL), journal book — read from `finance.gl_*` (`db/V145:244-340`). `GET /reports/income-expenditure?year` and `/reports/expenditure?year` (reports module) render the same for the Reports & Returns desk.
- Bursary dashboard tiles (`GET /finance/bursary`): fees_collected (session, purpose 'School fees%'), today, today_count, references_open, credits_open(+amount), gateway_exceptions, hanging, scheme_in_force, schedule_items; `byFaculty` (`finance.collection_by_faculty`: students, paid_students, collected, due); `recent` (last 7 days of the day book) (`FinanceController.java:310-333`).

## 1.9 Configuration
- `finance.fee_schedule` per session (the Bursar's lines; 6 live lines over 3 sessions in the local DB).
- `ref.fee_group` (seeded UG Undergraduate/UNDER GRADUATE, PG Postgraduate/POST GRADUATE, GST, EPS) and `ref.fee_item` (SCHOOL_FEES, ACCEPTANCE, REGISTRATION, DEVELOPMENT, LIBRARY, ICT, MEDICAL, SPORTS, EXAMINATION, LABORATORY, HOSTEL, GST, EPS, POST_UTME, ID_CARD, CONVOCATION, READMISSION).
- `finance.fee_setting` singleton: `home_state='Benue'`, `transfer_fee=NULL`.
- Clearance scheme: `policy.version`/`clearance_rule` via `POST /finance/clearance-scheme` `{instrument, from}`.
- Chart of accounts `finance.gl_account`: 33 seeded accounts (1000 ASSETS … 5900 Other overheads; see `db/V145` seed) — no screen edits the chart.
- Number series used: RECEIPT (per session), REFUND (per year); VOUCHER/TENDER/REQUISITION/GRANT/MOVEMENT are minted by `platform.next_number` on first use.

## 1.10 Data
All finance state tables are audit-attached except `finance.gateway_credential` (explicitly exempt, `db/V039:33`). Key tables: `fee_schedule` (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, indigene, spillover, ord, ended_at); `payment_reference` (student_id → people.student, session, reference UNIQUE, purpose, amount>0, generated_at, expires_at, confirmed_at/by, channel, note, receipt_no UNIQUE; 126 rows/122 confirmed locally); `bank_credit`; `refund` (source_reference added V067); `payment_reconciliation` (append-only); `fee_setting`; `gl_account`, `gl_journal` (journal_no sequence, source MANUAL|AUTO, source_type, source_ref, status POSTED|REVERSED, reverses), `gl_posting` (line, account, debit, credit, narration, session, fund). Write-once by design: `payment_reconciliation`, `gl_posting` (never edited, only reversed), `gateway_credential_event`.

## 1.11 Scheduled jobs and integrations
None in this module itself; GL sync is manual (`POST /finance/accounting/sync`) — no scheduler calls `finance.gl_sync` (grep of `@Scheduled` finds only payments sweep, deferments, examiners, helpdesk, hostel, notices). Integrations are in the payments module (§2).

## 1.12 Security notes
- Public: `GET /api/v1/verify/receipt/{reference}` (token-gated; enumerating references without the QR token yields only `genuine:false`).
- Maker–checker on bank credits and refunds is enforced by CHECK constraints (`ck_bc_two_people`, `ck_rf_two_people`) and function checks on `moaum.actor_id`, so a single person holding several offices still cannot approve their own act.
- Confirmations by the Bursary (`POST /finance/references/{reference}/confirm`) take any free-text channel; the amount confirmed is always the reference amount — a manual confirm cannot short-pay.
- The `finance/*` READERS list omits `financecontroller`, `pgsecretary`, `deputyaudit` although menus route those offices to `/finance/fees` (see 1.13).

## 1.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Fee schedule lines (add/edit/end/clear) + charges engine | IMPLEMENTED | `FinanceController.java:116-234`; `db/V161` | filters: level, entry mode, faculty, programme, fee group, semester, indigene, spillover |
| Approved-fees bulk structure upload | IMPLEMENTED | `db/V216`; `FinanceController.java:81-98` | replaces the session's lines |
| Student position / instalments / arrears / per-semester gate | IMPLEMENTED | `db/V027:322`, `db/V149` | instalment = half/whole of session charge |
| Clearance scheme in force | IMPLEMENTED (demo scheme seeded) | `db/V026:226`; local DB | fails closed when absent |
| Reference minting and 24 h expiry | IMPLEMENTED | `db/V131` | |
| Manual confirmation by Bursary | IMPLEMENTED | `FinanceController.java:285-292` | |
| Bank credits (maker–checker) | IMPLEMENTED | `db/V037:150-215` | state REVERSED defined but never set |
| Refunds (maker–checker, against a transaction) | IMPLEMENTED | `db/V043`, `V067` | payout itself is recorded, not executed |
| Reconciliation attestation | IMPLEMENTED | `db/V068` | |
| Day book / ledger, payments query, breakdowns, exports | IMPLEMENTED | `db/V037:119`, `V112`, `V115` | |
| Legacy fees import / payment history import | IMPLEMENTED | `db/V087`, `V136` | |
| General ledger (chart, journals, sync, statements) | IMPLEMENTED, unused so far | `db/V145`; local `gl_journal` = 0 rows | manual sync only; accrual accounts exist but unused |
| Receipt PDF + public verification | IMPLEMENTED | `verify/VerifyController.java:49-96`; `student/receipt/[reference]/pdf/route.ts` | |
| Transfer fee setting | IMPLEMENTED | `FinanceController.java:238-256` | NULL until set |
| Bursar Dashboard (`r/bursar`, the office home at `/`) | IMPLEMENTED (live data) | `frontend/src/app/page.tsx:123`, `app/dashboards/Bursar.tsx`; `GET /finance/bursary`, `GET /payments/bursary` | menus.md shows "—" only because the home id resolves to `/` (`Shell.tsx:404`); NELFUND and Held scripts status pills hard-coded "Open" (`Bursar.tsx:54-55`) |
| Fee-setup access for financecontroller / pgsecretary | PARTIALLY IMPLEMENTED | menus.md t/feesetup vs `FinanceController.java:35` | menu present, API guards exclude these offices |
| Bank-credit state REVERSED | NOT IMPLEMENTED | `db/V037:80` | no function |

## 1.14 Common problems
- "no charge is stated for 2026/2027 yet" when a student tries to pay → the Bursar has not put lines for that session/level/faculty on the schedule (or all were ended); add lines or upload the structure.
- Student sees `due = 0` although the schedule exists → the student's level/entry mode/faculty/programme/indigene/spillover does not match any line, or no semester is OPEN and the lines are semester-tagged (charges only include semesters ≤ the max OPEN one; with no OPEN semester everything up to 3 applies).
- "no clearance scheme in force … D-Q4 is unanswered" from exams/results/transcript gates → the Bursar posts `POST /finance/clearance-scheme` with an instrument; overlapping schemes are refused.
- "the officer who proposed a posting does not approve it" / "…raised a refund does not approve it" → a second person must approve.
- "reference X is already confirmed" (409) when proposing a bank credit → raise a wallet credit/refund instead.
- Legacy import returns `no_due` → amount blank and no schedule for that session/level; state an amount or a schedule.
- Journal refused "does not balance" or "A line names an account that is not on the chart." → use postable codes from `GET /finance/accounting/chart`.

## 1.15 Glossary
Fee line/schedule; charge (computed, never typed); position; instalment (½ of session due); arrears; spillover student; indigene fee; clearance scheme / instrument; reference (MOAUM-FEE-…); receipt number (RCT-YYYY-NNNNN); bank credit; maker–checker; reconciliation; day book; journal / posting; cash basis.

---

# 2. Payments — gateways, checkout, webhooks, verification, sweep, PayDirect
(API module: `payments`; tables in schema `finance`: gateway_event, gateway_attempt, gateway_credential, gateway_credential_event, paydirect_biller, paydirect_collection; pages: `finance/gateways`, `finance/hanging`, `finance/exceptions` (events), student/applicant checkout flows)

## 2.1 Purpose
Opens hosted checkouts for a reference on Paystack, Flutterwave or Quickteller (Interswitch), or issues a PayDirect PRN instruction; receives the gateways' webhooks; treats every callback as a hint and settles only on a verified amount; keeps every gateway event on the record; re-checks hanging attempts every ten minutes; lets ICT set gateway keys encrypted at rest; and imports the PayDirect collections report.

## 2.2 Users and roles
- Checkout: applicant, student (`PaymentsController.java:48`). Verify: any authenticated user for their own reference; bursar/ict/admin/super/audit for any (`:112`).
- `BURSARY` (`:96`): bursar, ict, admin, super — test checkout, sweep, resolve event, PayDirect import, set biller. `READERS` (`:97`): bursar, audit, deputyaudit, ict, admin, super, registrar, vc, dvc — desk, gateway config, PayDirect desk.
- Keys: `PUT /payments/gateways/{gateway}/key` and `POST …/clear-key` — ict, admin, super only.
- Webhooks and `GET /payments/quickteller/start` are public.

## 2.3 Navigation
Bursar → Finance: Payment Gateways `/finance/gateways` (also admin, ict), Hanging Payments `/finance/hanging`, Payment Investigation `/finance/exceptions`. Student: pay from `/student/fees`; applicant from `/applicant` and `/applicant/fee`; PG applicant from `/pg/portal`.

## 2.4 Screens
- **Payment Gateways** `/finance/gateways` (`Gateways.tsx`, 230 lines; table, form, toasts). Reads `GET /payments/bursary` (gateways on/off + mode TEST/LIVE/OFF + webhook path + channels text, tiles, events, hanging, portalUrl), `GET /payments/gateway-config` (configured, has_hash, mode, last4, set_at, set_by_name — never the key), `GET /payments/paydirect` (billers, last 200 collections). Writes `PUT /payments/gateways/{gateway}/key` `{secret, hash}` — Quickteller's "secret" is a JSON document `{clientId, clientSecret, merchantCode, payItemId, sandbox}` the screen builds; `POST …/clear-key`; `POST /payments/test-checkout` `{number, amount (default 100), gateway}`; `POST /payments/sweep`; `POST /payments/paydirect/import` `{rows}`; `PUT /payments/paydirect/billers/{MAIN|CHS}` `{code, name, link, active}`. Server messages: "The gateway is Paystack, Flutterwave or Quickteller." / "The portal has no passphrase to encrypt a gateway key with." (remedy: set MOAUM_CONFIG_KEY or MOAUM_AUTH_HMAC_SECRET) / "The secret key is blank." / "The Quickteller configuration needs clientId, clientSecret, merchantCode and payItemId." / "That gateway is not wired." / "No student carries the number X." (`PaymentsService.java:784-858`).
- **Hanging Payments** `/finance/hanging` (`Hanging.tsx`): `GET /payments/bursary` → `hanging` (attempts opened in the last 3 days with no confirmation: reference, gateway, kind, opened_at, checked_at, checks, amount, expires_at, minutes, payer, number); actions `POST /payments/verify` (ask the gateway now) and `POST /payments/events/{id}/resolve` `{resolution}` for exceptions.
- Event outcome vocabulary (`frontend/src/lib/bursary.ts:26` OUTCOME map; DB `ck_ge_outcome`): SETTLED, ALREADY_SETTLED, UNKNOWN_REFERENCE, SHORT_PAID, NOT_SUCCESSFUL, IGNORED, BAD_SIGNATURE, GATEWAY_ERROR; sources WEBHOOK, VERIFY, SWEEP, TEST.
- **Quickteller start page** (server-rendered HTML, `PaymentsService.java:391-426`): "Opening the secure Quickteller payment page for <ref>…", button "Pay with Quickteller", notices "This payment could not be started" / "Already paid".

## 2.5 Workflow
1. Checkout (`PaymentsService.checkout`, `:227-274`): resolves the reference among applicant `admissions.fee_reference`, student `finance.payment_reference`, PG `admissions.pg_fee_reference`; must belong to the caller (else 404); refuses PAY_ALREADY_CONFIRMED "This reference is already confirmed as paid.", PAY_REFERENCE_EXPIRED "This reference has expired." (remedy "Generate a new one; it is free of charge."), PAY_NO_EMAIL for card gateways when no email is on record, PAY_GATEWAY_NOT_WIRED "Card and USSD payment arrive when a payment gateway is wired to the portal." Default gateway order: paystack → flutterwave → quickteller. Records a `gateway_attempt` under actor = the payer, office 'bursar'. Return URLs: `/student/fees?paid=REF`, `/applicant/accept`, `/pg/portal`, `/applicant/fee`.
2. Webhooks: Paystack — HMAC-SHA512 of the raw body with the secret must equal `x-paystack-signature`, else 401 and a BAD_SIGNATURE event; only `charge.success` is read (amount in kobo). Flutterwave — `verif-hash` must equal the dashboard hash, else 401. Quickteller — the notification is never trusted; the reference in it is re-queried (`quicktellerNotified`, `:452-475`).
3. `settle` (`:545-576`): unknown reference → UNKNOWN_REFERENCE; status not success → NOT_SUCCESSFUL; paid < owed → SHORT_PAID (nothing confirmed); else confirm through `finance.confirm_payment` / `admissions.confirm_fee` / `admissions.pg_confirm_fee` with channel "Card · <Gateway>" or "Quickteller PayDirect" and note "<gateway> <providerRef> · <amount>", actor NOBODY (00000000-…) office 'bursar'; SETTLED or ALREADY_SETTLED. Every outcome is logged (`finance.log_gateway_event`).
4. `verify` (`:628-726`): asks Paystack `transaction/verify/{ref}`, Flutterwave `verify_by_reference`, Quickteller requery (Hash = SHA-512(clientId+reference+clientSecret)), PayDirect transaction query (biller routed by College) — each wired gateway in turn — and settles on the first success; increments `gateway_attempt.checks`.
5. Sweep (`@Scheduled fixedDelay moaum.payments.sweep-every-ms=600000`, initial 120 s, `:746-763`): for each hanging attempt older than 5 minutes with < 12 checks, `verify(reference, "SWEEP")`.
6. PayDirect: `checkout` with gateway=paydirect returns the PRN instruction (`:304-321`); the Bursary later imports the collections report — each PRN matching a portal reference is confirmed with channel "Quickteller PayDirect", duplicates by (biller, RRN) skipped, unknown PRNs stored UNMATCHED with why "No reference matching this PRN was generated by the portal" (`db/V080:101-150`).

## 2.6 Business rules
Signature before parsing; amount ≥ owed; idempotent confirmation; a reference is confirmed once whatever path reaches it; nothing credited on the notification's word alone; the dashboard key (encrypted with pgcrypto `pgp_sym_encrypt` under the server passphrase) wins over the service variable (`moaum.payments.paystack-secret`, `flutterwave-secret`, `flutterwave-hash`, `quickteller-config`) (`PaymentsService.java:82-139`; `db/V039`). Biller routing: a programme whose faculty's `college_code = 'CHS'` pays biller CHS 04263001, everyone else MAIN 04255101 (`db/V080:64-77`).

## 2.7 Notifications
None of its own; a settled payment triggers §1.7 through `finance.confirm_payment`.

## 2.8 Reports/exports
Gateway events (last 200), event tiles (today, settled, exceptions, bad_signatures, settled_today), hanging list, PayDirect collections — on screen only.

## 2.9 Configuration
`finance.gateway_credential` (paystack, flutterwave, quickteller, paydirect; local DB: none set), `finance.paydirect_biller` (seeded MAIN 04255101 "Benue State University, Makurdi" quickteller.com/bsum; CHS 04263001 "College of Health Sciences, Benue" quickteller.com/chsbsu, both active), environment `moaum.portal-url` (default `https://moaum-portal-production.up.railway.app`), `moaum.api-url`, `moaum.config.key`.

## 2.10 Data
`gateway_event` (audit-attached, append-only with resolve), `gateway_attempt`, `gateway_credential` (audit-exempt), `gateway_credential_event` (SET/ROTATED/CLEARED), `paydirect_biller`, `paydirect_collection` (MATCHED/UNMATCHED/DUPLICATE).

## 2.11 Scheduled jobs and integrations
Sweep every 10 minutes (§2.5). External: api.paystack.co, api.flutterwave.com/v3, Interswitch webpay/collections (`newwebpay[.qa].interswitchng.com/collections/w/pay`, `…/collections/api/v1/gettransaction.json`), PayDirect `…/paydirect/api/v1/gettransaction.json` (code comments say the exact hash inputs/hosts must be confirmed on merchant onboarding, `:210,669-670,700-701`).

## 2.12 Security notes
Public endpoints: the three webhooks and `/payments/quickteller/start` (reveals reference, amount and payer email/number in hidden form fields to whoever holds the reference). No rate limit on webhooks; bad signatures are logged (payload kept when < 20 000 chars). Keys are never returned. The PayDirect biller PUT is open to the Bursar (routing money) — an audited act.

## 2.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Paystack checkout + signed webhook + verify | IMPLEMENTED (tested) | `PaymentsIT.aSignedWebhookConfirmsTheFeeOnceAndAnUnsignedOneIsRefused` | |
| Flutterwave checkout + hash webhook + verify | IMPLEMENTED (tested for hash/unknown ref) | same | |
| Quickteller Business hosted page + requery | IMPLEMENTED, UNVERIFIED AGAINST LIVE | `PaymentsService.java:346-426,666-692` | hash inputs "confirm on onboarding" |
| PayDirect PRN instruction, collections import, query API | IMPLEMENTED (import) / PARTIALLY (query API endpoint unconfirmed) | `db/V080`; `PaymentsService.java:693-723` | |
| Encrypted gateway keys from the screen | IMPLEMENTED | `db/V039/V052/V080` | needs MOAUM_CONFIG_KEY |
| Hanging-payment sweep | IMPLEMENTED | `PaymentsService.java:746` | |
| Test checkout | IMPLEMENTED | `:784-798` | Paystack/Flutterwave only |

## 2.14 Common problems
"Card and USSD payment arrive when a payment gateway is wired to the portal." → no secret set; "A card checkout needs an email address on your record" → student adds email under Contact or pays by Quickteller/bank; webhook 401 → wrong secret/hash on the gateway dashboard vs the portal; SHORT_PAID event → the payer paid less than the reference; ALREADY_SETTLED → duplicate callback, harmless; "The payment gateway could not be reached" → outbound network; Quickteller verify "not found at the gateway" → reference never paid.

## 2.15 Glossary
Attempt, hanging payment, gateway event, outcome, sweep, PRN (= the portal reference), biller, RRN, requery, mode TEST/LIVE.

---

# 3. Wallet, funding sources and NELFUND
(API module: `wallet`; tables `finance.wallet_entry`, `wallet_withdrawal`, `funding_source`, `nelfund_batch`, `nelfund_row`, `nelfund_status`; pages: `student/wallet`, `finance/nelfund` (tabs `?tab=match`, `?tab=status`), `finance/sources`)

## 3.1 Purpose
A student wallet is an append-only ledger fed by NELFUND loan remittances, scholarships/grants, Bursary credits and the student's own top-ups; the student applies it to the session's school-fee balance (which settles a reference through the normal confirmation with channel "NELFUND wallet") and may withdraw a surplus to a bank account once fees are cleared. The Bursary loads the Fund's remittance files, matches rows to students, reverses money to the Fund, loads the Fund's approval list, keeps the sources of funding as a setting, and reads the funding report.

## 3.2 Users and roles
Student endpoints `hasAuthority('OFFICE_student')` (`WalletController.java:76-97`). `BURSARY` = bursar, admin, super (load batch, credit, reset, reverse, status, sources, withdrawals). Match a row: bursar, registrar, dregistrar, academic, super (`:124`). `READERS` (desk, statement lookup, report, sources): bursar, registrar, dregistrar, academic, audit, deputyaudit, admin, super, ict, vc, dvc.

## 3.3 Navigation
Bursar → Finance: Funding Sources `/finance/sources`; Sources & Wallets `/finance/nelfund`; NELFUND Applicants `/finance/nelfund?tab=status`; Match a Remittance `/finance/nelfund?tab=match`. Student/pgstudent → Services: Wallet & Funding `/student/wallet`.

## 3.4 Screens
- **Wallet & Funding** `/student/wallet` (`Wallet.tsx`, 148 lines; table, form). `GET /me/wallet?session=` → session, balance, statement (kind, amount, reference, note, source_code/name, nature, running balance), position, status (latest `nelfund_status` row: state APPROVED/NOT_APPROVED/PENDING, reason, correctable), eligibility (`finance.withdrawal_eligibility`: eligible, balance, cleared, arrears, pending, reason text), withdrawal (latest). Actions: `POST /me/wallet/apply` `{session, amount}` (blank = min(balance, fees balance)); `POST /me/wallet/topup-reference` `{session, amount}` (then checkout as any reference; error "A top-up is for an amount."); `POST /me/wallet/withdrawal` `{session, amount, bank, accountNo, accountName}` (error "A withdrawal names the bank, the account number and the account name.").
- **Sources & Wallets / NELFUND** `/finance/nelfund` (`Nelfund.tsx`, 381 lines; tabs, filters, forms). `GET /nelfund/sessions/{s}/{y}` → tiles (received, batches, allocated, unallocated, unmatched_rows, reversed, students), batches (matched/unmatched/reversed counts), unmatched rows (matric on remit, name, amount, why, owner Registry|Bursary, batch), status tiles (applied/approved/not_approved/pending/correctable), refusal reasons, sources, withdrawals queue. `GET /funding/sessions/{s}/{y}/report` → bySource (`finance.funding_summary`), cashflow (credited, topped_up, applied, reversed, withdrawn, held, loans_in, grants_in, self_in, settled_to_fees, applied_matches). `GET /nelfund/student/statement?number=` → any student's ledger. Writes: `POST /nelfund/batches` `{ref (req ≤60), session, receivedOn, note, rows:[{matricNo,name,amount}]}` ("A remittance is rows: matriculation number, name, amount."); `POST /nelfund/rows/{id}/match` `{number, note}`; `POST /nelfund/rows/{id}/reverse` `{why}`; `POST /nelfund/credit` `{number, session, amount, reason, source}`; `POST /nelfund/status` `{session, rows:[{number,name,state,reason}]}`; `POST /nelfund/reset` `{number, reason}`; withdrawals `POST /funding/withdrawals/{id}/approve|reject{why}|pay{ref}`. `frontend/src/lib/wallet.ts` exports `parseRows(text, headers)` (pasted CSV → rows) and `COVERS` (what the Fund covers).
- **Funding Sources** `/finance/sources` (`Sources.tsx`; role line). `GET/POST /funding/sources` (SourceIn: code req ≤40 upper-cased, name req ≤120, nature LOAN|GRANT|SELF, sponsor, account, active, note, sort).

## 3.5 Workflow and statuses
- Wallet entry kinds (`ck_we_kind`): CREDIT, TOPUP (add) / APPLIED, REVERSED, REFUND (subtract); balance = Σ signed amounts (`finance.wallet_balance`). Source tagged by trigger `wallet_entry_source` (TOPUP → SELF, note 'NELFUND%' → NELFUND).
- NELFUND row (`ck_nr_state`): MATCHED (student found and studying → CREDIT posted), UNMATCHED (no such matric → owner Registry; withdrawn/expelled/transferred/deceased/graduated → owner Bursary "reverse to the Fund"; bad amount → Bursary), REVERSED (by the Bursary with a reason; a matched row is reversed only if the wallet still holds the amount: "the wallet has been applied; NGN X cannot be reversed from it").
- Fund status (`ck_ns_state`): APPROVED / NOT_APPROVED / PENDING, `correctable` when the reason mentions BVN, institution code or name mismatch (`db/V033:252-280`).
- Withdrawal (`ck_ww_state`): REQUESTED → APPROVED (Bursary) → PAID (a *different* officer: "the officer who approved a withdrawal does not also pay it"; posts a REFUND entry "Withdrawn to <bank> <account>"); REQUESTED/APPROVED → REJECTED (why required, student sees it) (`db/V079:186-275`).
- Apply: `finance.apply_wallet` mints a school-fee reference for min(asked, balance, fees balance) and confirms it at once ("nothing to apply: the wallet holds NGN X and the balance for S is NGN Y").

## 3.6 Business rules
Eligibility to withdraw = session paid in full AND no arrears AND balance > 0 AND no pending withdrawal (reason strings: "A withdrawal is already awaiting the Bursary." / "The <session> fees are not yet cleared in full." / "There are fees owed from a previous session." / "The wallet has no balance to withdraw."). A hand match needs evidence ("a match made by hand says on what evidence"). A Bursary credit needs a reason and, if given, a known source code ("no funding source is coded X"). Reset deletes every entry and withdrawal for one student (audited deletes) — destructive, reason required ("A wallet reset names its reason.").

## 3.7 Notifications
None queued by the wallet functions themselves; applying the wallet confirms a payment and so sends the §1.7 "Your payment is confirmed" email/SMS ("Your wallet is credited." sentence is used for a confirmed top-up).

## 3.8 Reports
Funding report by source (students, credited) and cashflow reconciliation (`applied_matches` = APPLIED total equals payments confirmed on channel 'NELFUND wallet'); student statement lookup; desk tiles. No Excel/PDF export detected for this module (routes.md lists none).

## 3.9 Configuration
`finance.funding_source` seeded NELFUND (LOAN, sponsor Nigerian Education Loan Fund, account "NELFUND collection account"), SCHOLARSHIP (GRANT), SELF (SELF).

## 3.10 Data
`wallet_entry` (student_id, session, kind, amount>0, reference, note, source_code → funding_source), `wallet_withdrawal`, `nelfund_batch` (ref UNIQUE), `nelfund_row`, `nelfund_status` (UNIQUE session+number). All audit-attached; ledger is append-only except the reset.

## 3.11–3.12 Jobs / security
No jobs. Students never see another wallet; the Bursary lookup takes the number as a query parameter because matric numbers contain '/'. The "Students do not apply for NELFUND here" rule holds — the portal only records the Fund's decisions.

## 3.13 Implementation status
| Feature | Status | Evidence |
|---|---|---|
| Student wallet: statement, apply, top-up, withdrawal request | IMPLEMENTED | `WalletController.java:75-98`; `db/V033`, `V079` |
| NELFUND batch load, match, reverse, status list | IMPLEMENTED | `db/V033` |
| Funding sources setting, source-tagged credits, report | IMPLEMENTED | `db/V079` |
| Withdrawal approve/pay (two officers) | IMPLEMENTED | `db/V079:212-275` |
| Bursary credit / reset | IMPLEMENTED | `db/V066`, `V085` |
| Payout of a withdrawal | RECORD ONLY | `db/V079:250` comment "the portal records the payout, it does not move the money itself" |

## 3.14 Common problems
"No student carries the number X." → number as the register holds it; unmatched rows owned by Registry need the identity confirmed then matched with a note; "row … is not in suspense" → already matched/reversed; a withdrawal blocked by arrears requires legacy fees import for old sessions.

## 3.15 Glossary
Wallet, remittance batch, suspense/unmatched row, owner (Registry/Bursary), correctable refusal, source nature LOAN/GRANT/SELF, apply, top-up, withdrawal.

---

# 4. Expenditure — vouchers, budget, tenders, requisitions, stores and assets, research grants
(API module: `expenditure`; schema `expenditure`; pages: `vouchers`, `finance/budget`, `finance/tenders`, `finance/requisitions`, `stores`, `audit/assets`; grants have no page)

## 4.1 Purpose
Every University payment passes Internal Audit before money moves: the Bursary raises a payment voucher, it passes the Director of Internal Audit, the Deputy Director and an auditor, and only a cleared voucher is paid. Around it: budgets per cost centre with commitment accounting, tenders scored on a technical threshold before price, procurement requisitions whose method follows the value, a consumables store and a fixed-asset register the audit directorate verifies, and research grants administered for sponsors.

## 4.2 Users and roles
Vouchers (`VouchersController.java:31-34`): READERS bursar, audit, deputyaudit, super, admin, vc; raise/pay bursar, super; advance/query/reject audit, deputyaudit, super; answer a query bursar, audit, deputyaudit, super. In SQL the desk is also checked by acting office: WITH_DIRECTOR needs 'audit', WITH_DEPUTY 'deputyaudit', WITH_AUDITOR 'audit' or 'deputyaudit' (super bypasses) (`db/V044:107-110`). Budget: readers + set by bursar/super. Tenders: readers bursar, audit, deputyaudit, super, admin, vc; all writes bursar, super. Requisitions: raise bursar, ict, registrar, hrm, dean, super; approve/po/close/reject bursar, super; readers include dvc, registrar, ict. Stores: readers add ict; writes bursar, super; asset verify bursar, audit, deputyaudit, super. Grants: write bursar, dvc, super.

## 4.3 Navigation
Audit → Overview: Payment Vouchers `/vouchers` (home, t/prepayment); Finance: A Voucher in Full `/vouchers`, Assets Register `/audit/assets`. Bursar → Finance: Payment Vouchers `/vouchers`, Budget `/finance/budget`, Tenders `/finance/tenders`. dean/vc: Budget. dean/hod/services: Requisitions `/finance/requisitions`. services/library: Stores `/stores`. Note the menu/guard mismatch: hod and services are routed to Requisitions but neither is in RAISERS or READERS; library and services are routed to Stores but neither is in the stores READERS (`RequisitionsController.java:179-180`, `StoresController.java:426-427`) — those offices get 403 on the page's data calls unless they hold another office.

## 4.4 Screens
- **Payment Vouchers** `/vouchers` (`Vouchers.tsx`, 116 lines; modals). `GET /expenditure/vouchers?stage` (rows with raised_by_name, raised_by_me, query_open, open query id/finding/to, i_acted), `GET …/{id}` (acts trail + queries). Raise (Bursary): title req ≤200, kind req ≤40, source req ≤40, costCentre ≤120, payee req ≤200, amount ≥0.01. Advance (note ≤2000), Query (finding req ≤2000, sentTo req ≤120), Answer (answer req ≤2000), Pay, Reject (why req ≤2000).
- **Budget** `/finance/budget` (`Budget.tsx`; modals). `GET /expenditure/budget?year` → rows cost_centre, budget, committed (CLEARED vouchers), spent (PAID), available; `POST /expenditure/budget` `{costCentre req ≤120, year req, amount ≥0}`; also reads `/reports/income-expenditure?year`.
- **Tenders** `/finance/tenders` (`Tenders.tsx`; modals, filters). `GET /expenditure/tenders?stage`, `GET …/{id}` (bids ranked among responsive), `POST /expenditure/tenders` (subject req ≤200, costCentre, estimate ≥0.01, threshold default 70), `POST …/{id}/bids` (bidder req, price ≥0.01), `POST …/bids/{bid}/score` (technical, responsive, reason ≤400), `POST …/{id}/award` (bid req, why ≤2000), `POST …/{id}/cancel` (why).
- **Requisitions** `/finance/requisitions` (`Requisitions.tsx`). `GET /expenditure/requisitions?state` (method computed: QUOTATION < ₦2.5m, RESTRICTED_TENDER ≤ ₦25m, else OPEN_BIDDING), `POST` (item req ≤200, description ≤600, costCentre req ≤120, value ≥1), `…/approve`, `…/po`, `…/close`, `…/reject{why}`. Error: "This requisition cannot be approved by you." (remedy "A requisition is approved by a second officer, and only while it is raised.").
- **Stores** `/stores` (`Stores.tsx`; tabs items/assets). `GET /stores/items` (low flag when quantity ≤ reorder_level), `POST /stores/items` (code req ≤40, name req ≤200, unit default 'each', quantity, reorderLevel, location), `POST …/{id}/adjust` `{delta req, note}`; `GET /stores/assets`, `POST /stores/assets` (tag req, name req, category, location, acquiredOn, cost), `POST …/{id}/verify` (stamps today), `POST …/{id}/condition` (GOOD|FAIR|POOR|DISPOSED).
- **Assets Register (audit)** `/audit/assets` (`AuditAssets.tsx`) reads `GET /stores/assets` — a read-only register with last_verified_on; the verify action endpoint exists for audit but the page is detected as table-only (routes.md).
- Research grants: `GET/POST /research/grants`, `POST …/{id}/state` — no frontend page references them (NOT surfaced).

## 4.5 Workflow and statuses
- Voucher `stage` (`ck_pv_stage`): WITH_DIRECTOR → WITH_DEPUTY → WITH_AUDITOR → CLEARED → PAID; any non-final stage → REJECTED (why). Reference `PV/YYYY/NNNN`. Each advance writes a `voucher_act` row; an open `voucher_query` blocks advance and pay ("a query stands against PV/… and it cannot move until answered").
- Requisition (`ck_rq_state`): RAISED → APPROVED (a different person; CHECK `ck_rq_two_people`) → PO_RAISED → CLOSED; RAISED → REJECTED. Reference `RQ-YYYY-NNNN`.
- Tender (`ck_tender_stage`): ADVERTISED → EVALUATED (first bid scored) → AWARDED; ADVERTISED/EVALUATED → CANCELLED. Method by estimate: QUOTATION (< 2.5m), RESTRICTED (≤ 25m), OPEN. Reference `TN/YYYY/NNNN`.
- Asset condition GOOD/FAIR/POOR/DISPOSED; grant state PROPOSED/ACTIVE/COMPLETED/CLOSED/SUSPENDED (free update, no transitions enforced).

## 4.6 Business rules (SQL, `db/V044-V046, V076`)
BR-006: "no person acts twice on a voucher (BR-006)" — the raiser and anyone already in `voucher_act` cannot advance; wrong desk: "this desk is signed by audit , not by <office>"; pay only when CLEARED and by bursar/super ("a voucher is paid by the Bursary"); reject impossible from PAID/REJECTED. Budget available = budget − committed − spent; consumed at clearance, not payment. Bid responsive = technical ≥ threshold unless overridden with a reason ("a bid found not responsive carries the reason it failed"); award only to a responsive bid; a lower responsive bid requires the Board's reason ("a lower responsive bid exists; the award records why it is not taken"). Store quantity ≥ 0 (CHECK) — an adjust below zero fails with 23514.

## 4.7 Notifications
None (no `queue_notice` in V044–V076 or the controllers).

## 4.8 Reports
Budget performance table; `/reports/expenditure?year` (reports module) renders it; voucher trail per voucher. No Excel/PDF detected on these pages.

## 4.9 Configuration
None beyond budgets per (cost_centre, financial_year). Cost centres are free text.

## 4.10 Data
`voucher`, `voucher_act` (append-only), `voucher_query`, `budget` (PK cost_centre+year), `tender`, `bid`, `requisition`, `store_item` (code UNIQUE), `asset` (tag UNIQUE), `research_grant` (reference UNIQUE) — all audit-attached. Local DB: 0 vouchers, 0 budgets, 2 demo items, 2 demo assets.

## 4.12 Security notes
Stores adjust and asset condition/verify have no reason field beyond the audit spine's `X-Reason`; requisition approve enforces second-person in SQL (`raised_by <> actor`) but po/close do not record who acted beyond the audit row.

## 4.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Voucher chain with queries and BR-006 | IMPLEMENTED | `db/V044`; `Vouchers.tsx` | |
| Budget & commitment | IMPLEMENTED | `db/V045`; `Budget.tsx` | |
| Tenders | IMPLEMENTED | `db/V046`; `Tenders.tsx` | |
| Requisitions | IMPLEMENTED (backend) / PARTIALLY (menu offices hod, services lack API access) | `RequisitionsController.java:179-181`; menus.md | no PO document is produced |
| Stores & assets | IMPLEMENTED (backend) / PARTIALLY (library, services lack API access) | `StoresController.java:426-427` | |
| Audit asset verification screen | PARTIALLY IMPLEMENTED | routes.md `t/auditassets` features "data table" only | endpoint exists |
| Research grants | PARTIALLY IMPLEMENTED (backend without UI) | `ProjectsController.java`; no page calls `/research/grants` | |

## 4.14 Common problems
"no person acts twice on a voucher" → route to another auditor; "this desk is signed by deputyaudit" → the deputy must act at WITH_DEPUTY; voucher stuck → answer the open query first; 403 on Requisitions/Stores for HOD/services/library → office not in the guard.

## 4.15 Glossary
Voucher, desk/stage, query, BR-006, commitment, responsive bid, technical threshold, procurement method, PO, reorder level, verification date.

---

# 5. Human Resources — establishment, payroll, leave, movements, recruitment, appraisal, staff record
(API module: `hrm`; schema `hrm`; pages: `payroll`, `payroll/variance`, `hr/leave`, `hr/movements`, `hr/recruitment`, `hr/appraisal`, `staff` (Establishment), `audit/staff`, `me` (Leave & Payslip), `people/staff` (Non-Academic Staff upload, iam module))

## 5.1 Purpose
Holds the establishment (one live employment per person on a grade/step of a seeded salary structure), builds monthly pay runs whose payslips snapshot components and statutory deductions (8% pension, PAYE bands) under maker–checker, manages leave requests against typed entitlements, the seventeen staff movements (promotion, retirement, suspension…) that only change the record when an instrument is issued, recruitment vacancies and scored applicants, APER appraisal per cycle with computed promotion eligibility, and a whole-person staff record read by the offices that read the register.

## 5.2 Users and roles
Payroll (`PayrollController.java:31-32`): READERS hrm, bursar, audit, deputyaudit, admin, super, vc, dvc; build/approve/pay/cancel hrm, super; `GET /me/payslips` any authenticated (own only). Leave: `/me/leave*` any authenticated; approvers hrm, hod, dean, dregistrar, registrar, audit, admin, super — a HOD sees/decides only staff whose `hrm.staff_record.home_department` is theirs (`OfficeScope.actingHodDept`, `LeaveController.java:298-324`). Movements: readers hrm, registrar, dregistrar, dvc, vc, audit, deputyaudit, admin, super; raise/issue hrm, registrar, super; approve/decline hrm, registrar, dregistrar, vc, dvc, super. Recruitment: officers hrm, registrar, super. Appraisal: record hrm, registrar, dean, hod, super (HOD scoped); readers add dregistrar, dvc, vc, audit, admin. HR dashboard: hrm, super. Staff record `GET /hr/staff/{id}`: 18 offices (`StaffRecordController.java:760-763`); `/hr/staff/me` and `/me/photo` any authenticated.

## 5.3 Navigation
hrm: Overview → Movements `t/hrm` (home; URL "—" in menus.md, no Next page — backend `GET /hr/dashboard` exists); Finance → Payroll `/payroll`; Staff → Open a Movement `/hr/movements`, Staff Records `/staff`, Recruitment `/hr/recruitment`, Leave Requests `/hr/leave`, Appraisal `/hr/appraisal`, Upload Non-Academic Staff `/people/staff`; Me → Leave & Payslip `/me`. bursar: Payroll `/payroll`. audit: Payroll Variance `/payroll/variance`, Staff Movements `/audit/staff`. hod: Leave `/hr/leave`, Appraisal `/hr/appraisal`, Department staff `/hod/staff`. registrar: Recruitment, Staff Records. housing: Staff Records. Every staff office: Leave & Payslip `/me`.

## 5.4 Screens
- **Payroll** `/payroll` (`Payroll.tsx`, 142 lines; role line, toasts). `GET /payroll/runs` (period, state, staff_count, gross_total, deduction_total, net_total, built_by_name, approved_by_name, built_by_me), `GET /payroll/runs/{id}` (run + payslips: staff_no, name, grade, step, category, basic, allowances, gross, pension, paye, other_deductions, net, bank_name, account_last4), `GET /payroll/variance?period=`. Actions: `POST /payroll/runs` `{period 'YYYY-MM' (regex), note ≤400}`; `…/{id}/approve`; `…/{id}/pay`; `…/{id}/cancel {why}`. Also `GET /payroll/grades` and `GET /payroll/staff`.
- **Payroll Variance** `/payroll/variance` (`Variance.tsx`; filters) — rows kind JOINED/LEFT/CHANGED/SAME with this_net, prev_net, delta (`db/V069:230-247`).
- **Staff Records / Establishment** `/staff` (`Establishment.tsx`) reads `GET /payroll/staff` (staff_no, grade, step, category, status, appointment_date, name, bank, gross). **Staff Movements (audit)** `/audit/staff` reads `/payroll/staff` and `/payroll/runs`.
- **Leave Requests** `/hr/leave` (`LeaveDesk.tsx`; tabs). `GET /hr/leave?state`, `POST /hr/leave/{id}/decide` `{approve, note}`.
- **Open a Movement** `/hr/movements` (`Movements.tsx`; tabs). `GET /hr/movements?state` (+ grades list), `POST /hr/movements` `{number (staff no), kind, effectiveDate, whatChanges ≤300, reason ≤600, newGrade, newStep}`, `…/approve`, `…/decline {why}`, `…/issue`.
- **Recruitment** `/hr/recruitment` (`Recruitment.tsx`). `GET /hr/vacancies?state`, `POST /hr/vacancies` (title, department, requirements req; grade, category ACADEMIC|NON_ACADEMIC, closesOn), `POST …/{id}/state {state}`, `GET …/{id}/applicants`, `POST …/{id}/applicants` (name req; email, phone, qualification, publications, teachingYears), `POST /hr/applicants/{id}/assess {score 0–100, recommendation, state}`.
- **Appraisal** `/hr/appraisal` (`Appraisal.tsx`). `GET /hr/appraisal?cycle` → `hrm.promotion_view` (years_on_grade from last implemented promotion or appointment, eligible_years ≥ 3 years, aper_grade, publications, scores, appraisal_state); `POST /hr/appraisal` `{number, cycle, selfScore, supervisorScore, aperGrade A–E, publications, note, state SELF|SUPERVISOR|MODERATED}` (upsert per person+cycle).
- **Leave & Payslip** `/me` (`Self.tsx` + `LeaveSelf.tsx`): `GET /me/leave` → requests, types (ANNUAL first), balance (annual days left), isStaff; `POST /me/leave {type, from, to, cover ≤200, note ≤600}`; `POST /me/leave/{id}/cancel`; `GET /me/payslips` (only APPROVED/PAID runs); `GET /staff/me` (person + offices held). The staff `package-info.java` states the screen "says so rather than inventing" what the Staff module does not hold.
- **Staff record pop-up** `GET /hr/staff/{id}` → person (staff_number, names, contact, pno, sex, rank, conuass_step, first appointment, department/faculty, employment grade/step/category/status, has_photo, has_account), offices (with live flag and scope name), profile (CV), teaching (offerings with student counts), leave (last 20); `GET /hr/staff/{id}/photo` (JPEG/PNG, 10-min private cache).

## 5.5 Workflow and statuses
- Pay run (`ck_run_state`): DRAFT → APPROVED (a different person: "the officer who built a pay run does not approve it") → PAID; DRAFT/APPROVED → CANCELLED (why). One non-cancelled run per month ("a pay run for September 2026 already exists", 23505). Period must be the 1st of a month.
- Employment (`ck_emp_status`): ACTIVE / SUSPENDED / ENDED (ended_on required); one live employment per person (`uq_emp_person_live`).
- Leave (`ck_lr_state`): REQUESTED → APPROVED | DECLINED (note required); REQUESTED/APPROVED → CANCELLED by the requester only. One pending request per person (23505 "a leave request is already awaiting a decision"). Days inclusive; must not exceed the type's max ("ANNUAL allows at most 30 day(s); this request is N day(s)"); annual approval checks the balance ("the annual-leave balance does not cover N days").
- Movement (`ck_mv_state`): REQUESTED → APPROVED (second person) → IMPLEMENTED on issue (instrument `MOAUM/R/ACA/YYYY/NNNN`; PROMOTION/UPGRADING/CONVERSION change grade/step; RETIREMENT/RESIGNATION/DISENGAGEMENT/DISMISSAL end the employment; SUSPENSION suspends; REINSTATEMENT reactivates); REQUESTED → DECLINED. RETURNED is in the CHECK but nothing sets it. Kinds: 17 (APPOINTMENT … DISMISSAL). Raising requires an existing employment ("no employment on record for this person") — so an APPOINTMENT movement cannot create a new employee.
- Vacancy: OPEN/SHORTLISTING/INTERVIEW/OFFER/CLOSED/CANCELLED (free update); applicant: APPLIED/SHORTLISTED/RESERVE/REJECTED/INVITED/OFFERED/DECLINED/APPOINTED (free update via assess); no transition rules and no link from APPOINTED to an employment.
- Appraisal: SELF/SUPERVISOR/MODERATED (free update).

## 5.6 Business rules
Payslip: gross = basic+housing+transport+other; pension = 8% of (basic+housing+transport); PAYE monthly from annual gross less pension less CRA (max(200 000, 1%) + 20%) through bands 7/11/15/19/21% then 24% (`db/V069:120-148`); net = gross − pension − PAYE; other_deductions always 0 (no loans/union dues). Only ACTIVE employments are paid. Leave entitlement is derived, never stored (`hrm.leave_balance`). Promotion eligibility = ≥ 3 years on grade.

## 5.7 Notifications
None — no `queue_notice` in V069–V074 or the HR controllers (no email on leave decision, payslip, or movement).

## 5.8 Reports and documents
Payroll variance; establishment list; `/reports/staff` "Staff register" and `/reports/staff-ratio` (reports module). Staff ID card PDF `staff/idcard/pdf/route.ts` (built from `/hr/staff/me` and the photo). No payslip PDF route was found (`GET /me/payslips` renders on screen only). No appointment/promotion letter document is generated — the instrument is a reference string only.

## 5.9 Configuration
`hrm.grade` seeded: CONTISS 6/7/9/13/15 and CONUASS 1/3/5/7, steps 1–2 each (18 rows; e.g. CONUASS 7 step 1 basic 480 000, housing 130 000, transport 55 000, other 50 000) — no screen edits grades. `hrm.leave_type` seeded: ANNUAL 30 (annual), CASUAL 7, SICK 14, MATERNITY 112, PATERNITY 14, COMPASSIONATE 7, EXAMINATION 14, STUDY_PAID 1095, LEAVE_ABSENCE 365 (unpaid).

## 5.10 Data
`employment` (person_id → iam.person, staff_no UNIQUE, grade/step → grade, category, appointment_date, status, bank, account_last4, pension_pin, ended_on/reason); `pay_run`; `payslip` (snapshot; UNIQUE run+employment); `leave_type`, `leave_request`; `movement`; `vacancy`, `applicant`; `appraisal` (UNIQUE person+cycle); `staff_record` (pno, sex, first appointment, present_rank, conuass_step/contiss_step, category, salary_scale CONUASS|CONTISS|CONUNASS|CONMESS|CONHESS|CONSOLIDATED, home_department/home_unit/home_faculty, unit_as_given) written by `iam.import_lecturers` (V137) and `iam.import_staff` (V253); `staff_profile`, `staff_photo` (blob, audit-exempt). **Nothing in the API or migrations inserts `hrm.employment`** — only `db/demo.sql:472` (demo seed) and `check.sql`; the 31 local employments are demo rows. Local: 2 pay runs, 62 payslips, 0 `staff_record` rows.

## 5.12 Security notes
HOD scoping for leave and appraisal depends on `staff_record.home_department`, which is empty until the teaching-staff sheet is imported; with no record a HOD's list is empty and decisions 404. `POST /hr/vacancies/{id}/state` and applicant assess accept any string that satisfies the CHECK — invalid values surface as 422 from the constraint.

## 5.13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Pay run build/approve/pay/cancel, payslips, variance | IMPLEMENTED (engine) but PARTIALLY IMPLEMENTED as payroll | `db/V069`; no `INSERT INTO hrm.employment` outside `demo.sql` | no way to add staff to the establishment, set bank details or grades from the portal; no other deductions; no payslip PDF |
| Establishment list | IMPLEMENTED (read) | `PayrollController.java:52` | demo data only |
| Leave (self-service + office decision, HOD scope) | IMPLEMENTED | `db/V071`; `LeaveController.java` | needs an ACTIVE employment |
| Movements (raise/approve/decline/issue) | IMPLEMENTED | `db/V072` | APPOINTMENT cannot create an employee; RETURNED unused; no letter |
| Recruitment | PARTIALLY IMPLEMENTED | `RecruitmentController.java` | states free-form; no link to employment |
| Appraisal & promotion view | IMPLEMENTED | `db/V074` | |
| HR dashboard (`t/hrm`, the office home at `/`) | IMPLEMENTED (live data) | `HrController.java:694`; `frontend/src/app/page.tsx:133`, `app/dashboards/Hr.tsx` | title from `titles.ts:360` reads "Staff movements" although the page is the dashboard; "Staff records" tile links to `/people/lecturers` not `/staff` (`Hr.tsx:79`) |
| `/me` tiles Appraisal / Appointment / Next increment | PLACEHOLDER | `me/Self.tsx:37,73,87-89` | always "—", caption "Staff module, not yet on the portal"; "Leave taken" assumes a hard-coded 30-day entitlement |
| Staff record pop-up and photo | IMPLEMENTED | `StaffRecordController.java` | |
| Non-academic staff upload | IMPLEMENTED (iam module) | `db/V253` | creates person + staff_record, not employment |

## 5.14 Common problems
"only a serving member of staff may request leave" → the person has no ACTIVE `hrm.employment` (real staff are not on the establishment unless seeded); "the officer who built a pay run does not approve it" → second HRM officer; "a pay run for <Month> already exists" → cancel it first; movement "no such grade/step" → only seeded grade/step pairs; HOD sees no leave → `staff_record.home_department` missing.

## 5.15 Glossary
Establishment, employment, grade/step, pay run, payslip snapshot, CRA, PAYE bands, movement, instrument, APER grade, cycle, promotion view.

---

# 6. Staff module — self record, profile (CV), photograph, College tier
(API module: `staff`; tables `hrm.staff_profile`, `hrm.staff_photo`, reads `iam.person`, `iam.office_assignment`, `ref.college`; pages: `me`, `me/profile`, `staff/idcard/pdf`, `college/dashboard` partly)

## 6.1 Purpose
Answers "who am I on this portal and under what instrument" (`GET /api/v1/staff/me`), lets a member of staff keep their own academic profile and photograph, and describes the College of Health Sciences tier (`GET /api/v1/staff/college/{code}`: faculties with student counts, students, by level).

## 6.2 Users and roles
Every endpoint `isAuthenticated()`; the actor is always the token subject — never a parameter (`StaffController.java:88-106`).

## 6.3 Navigation
Me → Leave & Payslip `/me`; profile at `/me/profile` (linked from `/me`; not a menu item); staff ID card PDF at `/staff/idcard/pdf`.

## 6.4 Screens
- `/me/profile` (`Profile.tsx`, 265 lines): `GET/PUT /staff/profile` — scalars email (regex-checked in DB), phone, department, faculty, responsibility, scholarUrl, orcid, researchInterests, mastersGraduated, phdGraduated (≥0) and nine lists (publications, grants, collaborations, conferences, assignments, innovations, patents, achievements, contributions — must be JSON arrays: "publications must be a list"); `GET/PUT /staff/profile/photo` `{contentType image/jpeg|image/png, dataBase64}` ≤ 2 MB. Errors: "A photograph is a JPEG or PNG image. Save the picture as JPEG or PNG and upload it again." / "The picture could not be read. Choose the picture again and upload it." / "A photograph is between 1 byte and 2 MB." (`StaffController.java:66-78`).
- `/me` shows the person and offices (`GET /staff/me`) alongside leave and payslips (§5).

## 6.5–6.7 Workflow / rules / notifications
No states. The profile is upserted whole (a missing scalar becomes NULL, a missing list empty). No notifications.

## 6.8 Documents
Staff identity card PDF (`frontend/src/app/staff/idcard/pdf/route.ts`, 93 lines) from `/hr/staff/me` + `/hr/staff/me/photo`.

## 6.10 Data
`staff_profile` (audit-attached, one row per person), `staff_photo` (audit-exempt blob). Tested by `StaffProfileIT.aMemberOfStaffKeepsTheirOwnProfileAndPhotograph`.

## 6.13 Implementation status
| Feature | Status | Evidence |
|---|---|---|
| Own record and offices | IMPLEMENTED | `StaffController.java:37` |
| Profile (CV) and photo | IMPLEMENTED (tested) | `db/V107`; `StaffProfileIT` |
| College tier read | IMPLEMENTED | `StaffService.java:203` |
| Staff ID card PDF | IMPLEMENTED (route exists; content not audited line-by-line here) | `staff/idcard/pdf/route.ts` |

## 6.15 Glossary
Profile, responsibility, instrument (of an office assignment), College tier.


---

# Annex A — Screen-level audit of the finance, wallet and expenditure pages (labels, fields, buttons, toasts, empty states, verbatim from the TSX)

Produced by the delegated read of `frontend/src/app/finance/**`, `lib/bursary.ts`, `lib/wallet.ts`. Supersedes the summary in sections 1.4, 2.4, 3.4 and 4.4 where they differ.

# Finance screens: user-manual audit (read-only)

This covers 17 finance pages plus `lib/bursary.ts` and `lib/wallet.ts`. All paths are under `C:\Users\ajene\Documents\moaumpp\frontend\src\`.

## Conventions that apply to every page

**Page heading.** No `page.tsx` renders its own heading. `Shell` (`components/proto/Shell.tsx:366`) takes the title and subtitle from `TITLES[route]` in `lib/titles.ts`. The title and subtitle quoted for each page below come from there.

**Access.** None of the `page.tsx` files redirect or return 403. `Shell` has no route gating. Every page renders for anyone signed in. Rights are enforced in two places only:
- the client component hides or disables controls based on `me.activeOffice` (the "acting office"), and
- the server refuses requests.

**`RoleLine`** (`components/proto/ui.tsx:217`) shows: "**{action}** is worked by the Bursar." with a pill. The pill reads "You may act — {office}" or "Signed in as {office} · view only".

**`Tiles`.** Each tile is `[label, value, colour, hint]`. Below, each tile is written as **Label**: value — hint.

**Success toast.** Every `send()` or `call()` helper runs `notify(reason)`. So the success toast text is the same as the X-Reason text. `reasonHeader()` (`lib/reason.ts`) converts the reason to ISO-8859-1: "—" becomes " - " and "₦" becomes "NGN ".

**Error handling.** The standard path is `setProblem(json ?? {status, title: statusText})` plus `notifyProblem(...)`. That gives a `ProblemNotice` banner on the page and an error toast. The error text itself comes from the server's problem JSON.

**Search boxes.** `DTable` with `texts=[...]` gives the table a client-side search box. Those texts are the searchable strings.

---

## 1. Fee Setup and Schedule — `/finance/fees`
Files: `app/finance/fees/page.tsx`, `FeeSchedule.tsx` (587 lines).

**Title.** "Fee Setup and Schedule" / "Set the approved fees, and see the versioned schedule" (route `t/feesetup`).

**`page.tsx`**
- Session comes from `?session=`, which must match `/^\d{4}\/\d{4}$/`. Otherwise it uses the session whose state is `CURRENT` from `GET /api/v1/ref/sessions`. If there is no current session it falls back to a **hard-coded `"2026/2027"`** (`page.tsx:18`).
- Server data loads:
  - `GET /api/v1/iam/me`
  - `/api/v1/finance/sessions/{session}/schedule`
  - `/api/v1/finance/references?session=…&state=open`
  - `/api/v1/ref/structure`
  - `/api/v1/finance/fee-groups`
  - `/api/v1/finance/programmes`
  - `/api/v1/admissions/sessions/{session}/applicant-fees`
  - `/api/v1/finance/fee-items`
- If the schedule call fails, only a `ProblemNotice` shows.
- `actingOffice = me.activeOffice`. There is no redirect.

**Gating.** `may = actingOffice === "bursar" || "super"` (`:156`).
- `RoleLine allowed=["bursar"] action="Stating fees and the clearance scheme"`.
- The upload panel is hidden unless `may`. Every other action button is disabled unless `may`.

**No tabs.** This file has no tab control. It is a stack of panels and modals, described in order below.

### Tiles (`:342`)
- **Items stated**: count of items — "{session} · every item applies where its filters match"
- **Charge to everybody**: ₦ sum of items with no level, entry mode, faculty or programme — "Items with no filter"
- **Confirmed this session**: ₦ confirmed — "{n} student(s) paying" (green)
- **References waiting**: count of open references — "Against the bank's record" (red when above 0)

### Clearance-scheme note
- **When a scheme is in force** (ok note): title "Clearance scheme in force under {instrument}". Body: "From {from}[ to {until}]. Registration releases at {rules.REGISTRATION}, the examination at {rules.EXAMINATION}, results at {rules.RESULTS}; arrears block everything." `rules` is JSON-parsed from `scheme.rules`.
- **When no scheme is in force** (bad note): title "No clearance scheme is in force, so no payment releases anything". Button **"Put the recommended scheme in force"** (urgent, disabled unless `may`). Body: "The portal refuses rather than assumes what a payment releases. The recommended scheme: the first instalment, half the charge, opens registration, the identity card and the library; payment in full opens the examination, results, the transcript and convocation; arrears block everything. It is put in force under a minute, from a date."

### Panel "The charges for {session}"
**Header controls**
- **Session** select. Changing it navigates to `/finance/fees?session=…`.
- **"Add an item"** (primary, disabled unless `may`). Opens the item modal.

**Filters**
- **Faculty**: "Every faculty" / "No faculty (all students)" / each faculty.
- **Semester**: "Whole session" / "First semester" / "Second semester" / "Third semester".
- **Spillover**: "All students" / "Exclude spillover" / "Spillover only".
- **Per page**: 10, 25, 50, 100 or All. Default 25.
- Count line: "{filtered} of {total} line(s)[ (filtered)]."

**Export buttons**
- **"Download Excel"**: `buildXlsx` (not branded).
  - Columns: Item, Applies to, Level, Semester, Faculty, Entry mode, Spillover, Amount.
  - Sheet and file name: "Fee schedule {session with / replaced by -}.xlsx".
- **"Download PDF"**: a hand-built print window (not `brandedPrint`).
  - Heading "Rev. Fr. Moses Orshio Adasu University, Makurdi".
  - Subtitle "Fee schedule — {session} · {faculty label}[ · Semester n][ · Spillover only | · Excluding spillover] · {n} lines".
  - Columns: Item, Applies to, Amount.
  - If pop-ups are blocked: "Allow pop-ups to print" / "Your browser blocked the print window. Allow pop-ups for this site, or use Download Excel."

**Table.** Columns: Item, Applies to, Amount, (actions).
- Item shows a "Spillover" pill where it applies.
- "Applies to" joins: fee-group name, "Spillover" or "{level} Level", entry mode, faculty, programme, semester text. If all are empty it shows "Every student".
- Row actions:
  - Edit icon ("Edit {item}"). Opens the item modal pre-filled.
  - **"End"** (shows "Ending…" while running). `POST /api/v1/finance/sessions/{session}/schedule/{id}/end` with body `{}`. X-Reason "Fee item ended: {item}". **There is no confirmation prompt.**

**Empty states**
- "No charge is stated for {session}. Until one is, no student owes anything, no reference can be generated, and registration waits."
- "No fee line matches the filters."

**Pager.** "Previous" / "Page x of y" / "Next".

### Panel "Upload the approved fees structure" (only when `may`)
Header-right text: "Council's approved table, in one upload".

Helper copy, quoted in full:

> Upload the approved fees spreadsheet — a block per faculty, with 1st and 2nd Semester rows and a column for each level, split Indigene / Non-indigene. Each cell becomes a fee line above: a student is charged the cell for their faculty, level, semester and state of origin (an indigene is of the University's State). A student can pay the semester due or the full session at once. **Uploading replaces the whole structure for {session}.** Accepts a real Excel workbook (.xlsx) or the same sheet saved as CSV (.csv) — if a file will not read, in Excel choose *Save As → Excel Workbook* or *CSV (Comma delimited)*. Two shapes work: this faculty×level cross-tab, or a plain **one-row-per-fee** table with columns *Faculty, Level, Entry mode, Semester, Indigene, Amount* (the clearer format — one line, charged once).

**File button "Upload approved fees (.xlsx / .csv)"** (shows "Uploading…"; accepts `.xlsx,.csv`)
- Parsing is done in the browser:
  - A flat table is detected by a Faculty column plus an Amount/Fee column (`parseFeeFlat`, `:103`).
  - Otherwise it is read as a cross-tab (`parseFeeMatrix`, `:43`).
  - A band like "100/200DE" means 100 Level plus 200 Level Direct Entry. A "spill" column gives spillover lines.
  - Entry modes are normalised to DIRECT_ENTRY, TRANSFER, UTME, JUPEB, SANDWICH or POSTGRADUATE.
- Request: `POST /api/v1/finance/sessions/{session}/fee-structure` with body `{rows}`. X-Reason "Approved fees structure uploaded for {session}".
- On success, an ok note titled "Approved fees loaded": "{lines} fee lines loaded across {faculties} faculties[ · {no_faculty} rows had a faculty name that did not match one on the register]. It replaced the previous structure for {session}." **There is no toast on this path.**
- Errors:
  - "That file could not be read." / "{err}. Save it from Excel as "Excel Workbook (.xlsx)" or as "CSV (Comma delimited) (.csv)" and upload that — an old .xls or a renamed file will not read."
  - "No fee rows could be read from that file." / "One-row-per-fee: give it Faculty, Level, Entry mode, Semester, Indigene and Amount columns. Cross-tab: a FACULTY/SEMESTER header with level columns, then a block per faculty with 1st and 2nd Semester rows."
  - "That file could not be read as a spreadsheet." / "Upload the approved-fees .xlsx."

**"Clear the {session} schedule"** (ghost; disabled while busy or when there are no items). Opens a modal:
- Title "Clear the {session} schedule". Subtitle "{n} line(s) will be removed".
- Bad note "Every fee line for {session} will be ended": "No student on {session} will owe anything until a new structure is stated. Receipts and payments already made are untouched. Upload the approved fees for the right session afterwards."
- **"Clear the schedule"** (urgent; shows "Clearing…"). `POST /api/v1/finance/sessions/{session}/schedule/clear` with body `{}`. X-Reason "Fee schedule cleared for {session}".

Note under the buttons: "An upload already replaces this session's schedule. Use **Clear** only to empty a session whose fees were stated by mistake (for example the wrong session) — then switch to the right session above and upload."

### Panel "References waiting on the bank's record" (header-right shows the count)
- Columns: Reference, Student, Amount, Generated, (action).
- Student cell: "{surname}, {other_names}" over "{matric or admission no} · {programme} · {level} Level".
- **"Confirm"** (disabled unless `may`). Opens the confirm modal.
- Empty: "Nothing waits. A reference a student generates appears here until the bank's record is matched to it, by the Bursary or by a gateway's webhook."

### Modal: add or edit an item (`:441-514`)
- Title "An item of the charge", or "Edit the charge item" when editing.
- Subtitle "{session} · applies where every filter it carries matches, or is blank".

| Field | Type | Options / hint / placeholder |
|---|---|---|
| **Payment item** | select | "— choose an item —", each fee item from the API, "Other (type a name)…". Hint "A payment category; choose Other to name a one-off". |
| **Amount** | text, numeric | Hint "In naira". No format check. |
| **Item name** | text | Only shown when Other is chosen. Hint "The name this charge appears under". Placeholder "e.g. Faculty dues". |
| **Session** | select | Hint "Which session this charge is for". |
| **Semester** | select | "Whole session" / "First semester" / "Second semester" (**no third semester here, although the filter offers one**). Hint "Blank for the whole session". |
| **Programme group** | select | "Every group" plus fee groups. Hint "Undergraduate, Postgraduate, GST, EPS — blank for every group". |
| **Level** | select | "Every level", 100–600, "700 · PGD", "800 · Master's", "900 · Doctoral". Hint "Blank for every level; 700–900 are postgraduate". |
| **Entry mode** | select | "Every mode" / UTME / DIRECT_ENTRY / TRANSFER / POSTGRADUATE. Hint "Blank for every mode". |
| **Faculty** | select | "Every faculty" plus faculties. Hint "Choose a faculty to list its programmes". Changing it resets programmes. |
| **Programmes** | checkbox list | Only when a faculty is chosen. Buttons "Select all" and "Clear (all in faculty)". Counter "{n} selected" or "All programmes in {faculty}". Empty list: "No programme in this faculty." Without a faculty: "Applies to every programme. Choose a faculty above to target one, two or more." |

- Required: the submit button is disabled until there is an item name and an amount.
- **Submit button** is labelled "State the item", or "Save changes" when editing. It shows "Stating…" or "Saving…" while running.
  - **Editing**: `PUT /api/v1/finance/sessions/{addSession}/schedule/{id}`. X-Reason "Fee item edited for {s}: {item}". Only the **first** ticked programme is saved (`selectedProgs[0]`, `:456`).
  - **New, with programmes ticked**: one `POST …/schedule` per programme. X-Reason "Fee item stated for {s}: {item} · {code}".
  - **New, no programmes**: one `POST …/schedule` with `programmeCode: null`. X-Reason "Fee item stated for {s}: {item}".
  - Body keys: `item, amount, level, entryMode, feeGroup, semester, ord, facultyCode, programmeCode`.
  - `ord` is read from `val("ord")`, but **no field sets it**, so it is always 0.
  - If the session was changed in the modal, the page navigates to that session after saving.

### Modal: "Confirm {reference}"
- Subtitle "{surname}, {other_names} · ₦amount".
- **Channel** (required): select "Choose…" / Bank transfer / Bank branch / USSD / Card.
- **Note** (optional): hint "Teller number, transaction reference".
- Info note "Confirmed against the bank's record, not by this page": "The receipt is issued the moment you confirm, and the student is told by email and SMS."
- **"Confirm the payment"** (shows "Confirming…"). `POST /api/v1/finance/references/{reference}/confirm` with body `{channel, note}`. X-Reason "Payment {ref} confirmed against the bank's record".

### Modal: "Put the recommended clearance scheme in force"
- Subtitle "Under a minute, from a date".
- **Instrument** (required): placeholder "BUR/2026/04". Hint "The Council or Bursary minute that approved it".
- **From**: date. Hint "Blank for today".
- Copy: "Registration, identity card and library release at the first instalment; the examination, results, transcript and convocation at payment in full; hostel is not gated; arrears block everything. Two schemes cannot overlap in time."
- **"Put in force"** (shows "Putting in force…"). `POST /api/v1/finance/clearance-scheme` with body `{instrument, from}`. X-Reason "Clearance scheme put in force under {instrument}".

### Panel "Applicant · Post-UTME fees"
Header-right: "Stated for {session}" or "Default (not yet stated for {session})".

Copy: "The charges an applicant pays before they are a student — the Post-UTME screening fee (with the portal and payment charge) and the acceptance fee an offer carries. They are a payment item of their own, under **Applicant**, kept apart from the student charges above because an applicant is not yet on the register."

Four numeric fields. Anything other than digits and "." is stripped. All are disabled unless `may`.
- **Post-UTME screening fee**: placeholder 2000. Hint "What the applicant pays to apply and be screened".
- **Portal and payment charge**: placeholder 300. Hint "Added to the screening fee at checkout".
- **Acceptance fee**: placeholder 30000. Hint "Paid on an offer; credited to first-session charges".
- **Admission checking fee**: placeholder 0. Hint "Paid at acceptance, alongside the acceptance fee".

**"State the applicant fees"** (shows "Saving…"; requires the screening fee):
- `PUT /api/v1/admissions/sessions/{session}/applicant-fees` with body `{applicationFee, portalCharge, acceptanceFee, checkingFee}`.
- X-Reason "Applicant / Post-UTME fees stated for {session}".
- **There is no success toast**; the page only refreshes.
- Live total: "Applying costs the screening fee plus the portal charge — ₦x. Accepting an offer costs the acceptance fee plus the checking fee — ₦y."

### Panel "Postgraduate · application & acceptance fees"
Header-right: "Stated for {session}" or "Default (not yet stated…)".

Copy: "The fees a postgraduate applicant pays — the application fee to apply through the School of Postgraduate Studies, and the acceptance fee an offer carries. Read by the postgraduate apply page (**/pg/apply**). Until stated, a sensible default applies."

- Loads client-side with `GET /api/bff/api/v1/pg/sessions/{session}/fees`.
- Fields:
  - **PG application fee**: placeholder 20000. Hint "What a postgraduate applicant pays to apply".
  - **PG acceptance fee**: placeholder 50000. Hint "Paid on an offer".
  - **PG checking fee**: placeholder 3000. Hint "Paid on acceptance, with the acceptance fee".
- **"State the postgraduate fees"**: `PUT /api/bff/api/v1/pg/sessions/{session}/fees` with body `{applicationFee, acceptanceFee, checkingFee}`. X-Reason "Postgraduate fees stated for {session}". **No success toast and no page refresh.**
- Live text: "A postgraduate applicant pays ₦x to apply; accepting an offer costs ₦y (acceptance ₦a + checking ₦c)."

### Panel "Inter-departmental transfer · processing fee"
Header-right: "Set by the Bursary" or "Not set yet — required before any transfer".

Copy: "The non-refundable fee a student pays to process an inter-departmental transfer. It is set here by the Bursary and read by the transfer desk and the student's page. There is no default: until you set it, a student can apply but cannot pay, so no transfer can proceed."

- Loads with `GET /api/bff/api/v1/finance/transfer-fee`.
- **Transfer processing fee**: placeholder 10000.
- **"Set the transfer fee"**: `PUT /api/v1/finance/transfer-fee` with body `{amount}`. X-Reason "Inter-departmental transfer fee set to {tf}".
- Live text: "A student who transfers will pay ₦x."

Footer pill: "Every act here is the Bursar's, on the record".

### Unfinished or inconsistent
- Hard-coded session fallback "2026/2027".
- A code comment at `:234` says the transfer fee "defaults to ₦10,000 when unset". The on-screen copy says "There is no default".
- `ord` is never editable.
- Editing a line keeps only one programme.
- The item modal has no third-semester option.
- No success toast for the applicant and PG fee saves.

---

## 2. Payments query — `/finance/payments`
Files: `page.tsx`, `Payments.tsx`.

**Title.** "Payments query" / "Confirmed payments, sliced by faculty, programme, level, category and session".

**`page.tsx`.** Reads the query parameters `session, faculty, dept, programme, level, category, channel, from, to` and calls `GET /api/v1/finance/payments?…` on the server. **There is no office gating and no RoleLine.** The screen is read-only.

**Intro note** "Payments, queried from the record": "Confirmed student payments, newest first. Choose any combination of session, faculty, department, programme, level, payment category and channel; the count and the total below are the whole matching set. Payments are charged per session, so there is no semester to choose. Applicant application and acceptance fees are on the day-book ledger."

**Panel "Query"**
- **"Clear filters"** appears when any filter is set. It goes to `/finance/payments`.
- Searchable selects (`SearchSelect`):

| Label | "All" option | Placeholder |
|---|---|---|
| Session | "All sessions" | "Search a session…" |
| Faculty | "All faculties" | "Search a faculty…" |
| Department | "All departments" | "Search a department…" (narrowed by faculty) |
| Programme | "All programmes" | "Search a programme…" (narrowed by faculty and department) |
| Level | "All levels" | "Level…" (**hard-coded 100–600**) |
| Payment category | "All categories" | "Category…" |
| Channel | "All channels" | "Channel…" |

- **From** and **To** date inputs.
- Changing any filter pushes the URL straight away. Changing the faculty clears department and programme. Changing the department clears programme.

**Tiles**
- **Payments matched**: count — "for the filters above" or "all confirmed payments"
- **Total collected**: ₦ — "sum of the matching payments"
- **Showing**: "{n}[ of {count}]" — "newest first — narrow the filters to see the rest" or "newest first"
- **Scope**: "Filtered" or "Everything" — the scope string, cut to 40 characters

**Panels "By payment category" and "By faculty"** (header-right "the whole matching set")
- Columns: Category (or Faculty), Payments, Total.
- Empty: "Nothing to summarise for this query."

**Panel "Payments"**
- Table columns: When, Payer (payer over "{number} · {faculty}"), Programme, Level, Category, Channel, Amount, Receipt (receipt number, or the reference if none).
- Empty: "No confirmed payment matches this query. Widen the filters, or clear them to see every payment."

**Exports** (both disabled when there are no rows)
- **"Export Excel"**: `brandedXlsx("Payments query", …)` with sheet "Payments", serial `docSerial("PAY")` (MOAUM/PAY/YYYYMMDD/HHMMSS-RR), and the scope as subtitle. File `payments-{serial}.xlsx`.
- **"Export PDF"**: `brandedPrint("Payments query", scope, …)`.
- Columns in both: When, Payer, Number, Faculty, Programme, Level, Category, Channel, Amount, Receipt, Reference, Session.
- Both export only the rows loaded on the page. When the count is larger than the rows shown, the rest are not exported.

---

## 3. Payment history upload — `/finance/payments-history`
Files: `page.tsx`, `PaymentsHistory.tsx`.

**Title.** "Payment history" / "Load past students' payment history from the old portal".

**Gating.** `MAY = ["bursar","super","ict","admin"]`. `RoleLine allowed=["bursar"] action="Loading past payment history"`.
- The RoleLine names only the Bursar, but ICT, admin and super can also act.
- When the office is not allowed, a bad note shows: "This desk is for the Bursary and the Directorate of ICT" / "Your office may not load payment history."

**Info note** "Load past students' payment history": "This carries confirmed school-fees payments over from the old portal, exactly as they were — the original reference, receipt, amount, date and channel are kept. It is **not** for new payments (those are confirmed on the reconciliation desk). A payment already on record is left alone, so a file may be uploaded again safely, and no student is notified. Each payment is matched to a student by matriculation, admission or JAMB number."

**Panel "The payment-history file"** (header-right "School fees")
- **"Download template"**: `buildXlsx` producing "Payment history template.xlsx".
  - Columns: Matriculation Number, Session, Amount, Purpose, Payment Date, Channel, Reference, Receipt No.
  - Two **sample rows**: MOAUM/CSC/19/1234 for 2019/2020 and 2020/2021.
- **File button "Choose the payment-history file (.xlsx)"** (`.xlsx` only; disabled unless `may`). While loading it shows the progress text.
  - Columns are found by keyword: matric/reg, session, amount, purpose/category/fee type/description/type, date/paid on, channel/method, reference/rrr/transaction, receipt.
  - Error if matric or amount is missing: "That file needs at least Matriculation Number and Amount columns." / "Download the template for the full set of columns."
  - Error if there are no rows: "No payment rows were found in the file."
  - Upload runs in chunks of 400: `POST /api/v1/finance/payments/import` with body `{rows:[{matric,session,amount,purpose,date,channel,reference,receipt}]}`. X-Reason "Past students' payment history loaded".
  - Progress text: "Reading the spreadsheet…", then "Loading {x} of {n} payments…".
  - If a batch fails: the problem detail gets "{imported} payments were loaded before this batch was refused. The import is idempotent — fix and upload again." **No toast on this path.**
  - Success, ok note "Payment history loaded": "{n} payments loaded[ · {d} already on record (skipped)][ · {n} matched no student][ · {n} had no valid amount][ · {n} skipped by an error (first: …)]."
  - Read failure: "That file could not be read as a spreadsheet."
- Helper copy: "**Amount** may carry a currency sign or commas — only the number is read. **Session** is like 2019/2020; a blank session is filed under **LEGACY**. **Payment Date** like 2019-11-05; a blank date defaults to today. A row with no **Reference** is given a stable one derived from the row, so re-uploading the same file never duplicates. Large files are loaded in batches of 400."
- There is no success toast; `notify` is not imported.

---

## 4. Old fees history — `/finance/legacy-fees`
Files: `page.tsx`, `LegacyFees.tsx`.

**Title.** "Old fees history" / "Clear returning students' past school-fees history from the old portal".

**Gating.** `MAY = ["bursar","super","admin"]`. There is no RoleLine. When not allowed, a bad note shows: "This desk is for the Bursary" / "Your office may not import fees history."

**Info note** "Clear old students' school-fees history from the old portal": "A returning student brought over from the old portal owes every past session the University has a fee schedule for, because the new portal knows only its own confirmed payments. Upload what each student already paid, by session and (optionally) semester. Give the **amount paid**, or leave it blank to mean **cleared in full** — the past session then settles and the arrears clear. Re-uploading the same file updates rather than duplicates, and every record is on the audit spine in your name."

**Panel "Old-portal fees export"** (header-right "Matriculation number · session · amount (or blank for cleared)")
- **"Download template"**: "Old fees history template.xlsx".
  - Columns: Matriculation Number, Session, Semester, Amount Paid, Paid On, Receipt No, Note.
  - Two sample rows for MOAUM/CSC/22/0001.
- **"Choose the fees file (.xlsx)"** (shows "Reading…"). Parses the file in the browser and shows a preview.
  - Rows are kept only when there is a matric number and the session matches `/^[0-9]{4}\/[0-9]{4}$/`.
  - Error: "That file has no matriculation-number and session columns." / "Download the template, or upload the old-portal export with those columns."
  - Error: "No fee rows were found in that file." / "Each row needs a matriculation number and a session (YYYY/YYYY)."
  - Error: "That file could not be read as a spreadsheet." / "Use the downloaded template (.xlsx)."
- Helper copy: "Columns read: Matriculation Number, Session (YYYY/YYYY), Semester (1/2, optional), Amount Paid (blank = cleared in full), Paid On and Receipt No (optional). Columns are matched by name, so an old-portal export with those columns can be uploaded as-is."

**Preview panel "Read from the file — check, then load"** (header-right "{n} rows")
- Columns: Matric, Session, Sem, Amount (shows "cleared in full" when blank), Paid on. Only the first 200 rows are shown.
- **"Load {n} rows"**: chunks of 500, `POST /api/v1/finance/legacy-fees` with body `{rows:[{matric,session,semester,amount,paidOn,receiptNo,note}]}`.
  - X-Reason "Old students' school-fees history imported: rows {a}–{b}".
  - Progress: "Loading x of n rows…".
- **"Cancel"** closes the preview.
- If a batch fails, the detail gets "{cleared} payments were settled before this batch was refused. The import is idempotent — fix and upload again." No toast.

**Result**
- Tiles:
  - **Rows read** — "In the file"
  - **Settled** — "Payments recorded"
  - **No such student** — "Import the students first"
  - **Nothing to settle** — "No amount and no fee schedule"
- Ok note "Fees history imported": "{n} past-session payment(s) recorded. The students' positions and arrears update at once.[ Rows with an unknown number are counted above — migrate those students first, then re-upload.]"
- No success toast.

---

## 5. Payment gateways — `/finance/gateways`
Files: `page.tsx`, `Gateways.tsx`.

**Title.** "Payment gateways" / "Providers, keys, routing and webhooks". The menu badge "!" is static (`menus.ts:543`).

**`page.tsx`.** Loads `GET /api/v1/payments/bursary` (PaymentsDesk), `/api/v1/payments/gateway-config` and `/api/v1/payments/paydirect`. Reads `?paid=`.

**Gating** (`:20-21`)
- `may` = bursar, ict, admin or super. This controls monitoring, testing and verifying.
- `mayConfigure` = ict, admin or super. This controls setting keys.

**Info note** "A secret key is written once and never read back": "Set a key below on this screen, or as a service variable (MOAUM_PAYSTACK_SECRET, MOAUM_FLUTTERWAVE_SECRET, MOAUM_FLUTTERWAVE_HASH). A key set here is encrypted at rest and used in preference to the variable; either way, no screen and no member of staff can display it again. This panel says only whether a key is set and whether it is test or live."

**When `?paid=REF` is present**
- Ok note "Back from the gateway with {ref}": "The webhook confirms it on its own; the log below shows the event when it lands. Or ask the gateway directly."
- Button **"Ask the gateway now"**: `POST /api/v1/payments/verify` with body `{reference}`. X-Reason "Verified {ref} with the gateway". Result: "The gateway says: {outcome}".

**Feedback.** Result messages show as an ok note titled with the message, body "On the record."

**Tiles**
- **Gateways live**: count — "{gateway} · {mode}" list, or "Set a secret to wire one"
- **Events today** — "₦x settled today"
- **Settled, all time** — "Posted from a gateway's word, verified"
- **Exceptions open** — "{n} bad signature(s) discarded"

**Panel "Configured gateways"** (header-right "Test or live is read from the key's own prefix")
- Columns: Gateway, Mode, Channels, Webhook address, Status.
- Mode pill: Live, Test or Off.
- Webhook address = `portalUrl` with "moaum-portal" replaced by "moaum-api", plus the webhook path.
- Status pill: "Wired", "Not wired", or "Secret set, hash missing — webhooks refused" (Flutterwave with no hash).
- Key/value help:
  - **Paystack**: "Settings → API Keys & Webhooks: set the webhook URL above; the secret key signs every event (x-paystack-signature). Test keys start sk_test_."
  - **Flutterwave**: "Settings → Webhooks: set the URL above and a secret hash; put the same hash in MOAUM_FLUTTERWAVE_HASH. Test keys start FLWSECK_TEST."
  - **Return address**: "{portalUrl}/student/fees?paid=… — the student's browser comes back here; the money is confirmed by the webhook or by verification, never by the browser."
  - **The reconciler**: "Every ten minutes the portal asks the gateway about every checkout opened in the last three days with nothing confirmed behind it, and posts what the gateway answers."

**Panel "Configure the keys"** (only when `mayConfigure`; header-right "Directorate of ICT and Super Administrator only")

Info note "A key set here is encrypted at rest and read back never": "…encrypted with the portal's own passphrase, decrypted only inside the API to call the gateway, and no screen ever shows it again — the same rule as a password. A service variable still works and is used when no key is set here. Setting a key is recorded against your name."

Each gateway gets a card:
- Pill: "Live key set", "Test key set" or "No dashboard key".
- "ends {last4}".
- "Set {when} by {name}[ · hash set | · no hash yet]".

**Quickteller card**
- Copy: "Quickteller Business (Interswitch): the four things from your merchant profile at business.quickteller.com. They are stored together, encrypted, and shown never."
- **Client ID**: placeholder "IKIA…". Hint "From your Interswitch/Quickteller developer profile."
- **Client secret**: password field. Hint "Pasted once; it is never displayed after this."
- **Merchant code**: placeholder "MX…".
- **Pay item ID**: placeholder "Default_Payable_MX…". Hint "The payable/pay-item configured on the merchant profile."
- Checkbox "Sandbox (test) — uncheck for the live Interswitch endpoints" (on by default).
- **"Set the configuration"** or **"Replace the configuration"** (all four fields required): `PUT /api/v1/payments/gateways/quickteller/key` with body `{secret: JSON{clientId,clientSecret,merchantCode,payItemId,sandbox}, hash:null}`. X-Reason "Quickteller configuration set from the dashboard". Message: "Quickteller configured — {mode} · merchant ending {last4}".
- **"Clear"**: confirm "Clear the Quickteller configuration? The gateway turns off unless a service variable is set." Then `POST …/quickteller/clear-key`. X-Reason "Quickteller configuration cleared".

**PayDirect card**
- Copy: "Quickteller PayDirect query API (optional): the client id and secret Interswitch issues for the Transaction Query API. The collections import needs none of this — set it only to poll payments automatically."
- **Client ID**, **Client secret** (password), and "Sandbox (test)" checkbox.
- **"Set the credentials"** or **"Replace the credentials"**: `PUT …/gateways/paydirect/key`. X-Reason "PayDirect query credentials set from the dashboard". Message: "PayDirect query API configured — {mode}".
- **"Clear"**: confirm "Clear the PayDirect query credentials? The report import still works." X-Reason "PayDirect query credentials cleared".

**Paystack and Flutterwave cards**
- **Secret key**: password. Placeholder "sk_test_… or sk_live_…" (Paystack) or "FLWSECK_TEST-… or FLWSECK-…" (Flutterwave).
- **Webhook secret hash** (Flutterwave only): hint "The same value you set on the Flutterwave webhook page."
- **"Set the key"** or **"Replace the key"**: `PUT /api/v1/payments/gateways/{gw}/key` with body `{secret, hash}`. X-Reason "{gw} key set from the dashboard". Message: "{gw} key set — {mode} key ending {last4}".
- **"Clear"**: confirm "Clear the {gw} key? The gateway turns off unless a service variable is set." Then `POST …/{gw}/clear-key`. X-Reason "{gw} key cleared".

**Panel "Quickteller PayDirect"** (when `may` and the PayDirect data loaded; header-right "Billers routed by College, and the collections report")
- Info note "A student pays a PRN; the payment comes back by import or by query": "Each College pays its own biller — Health Sciences the CHS biller, every other department the main one — and the student cannot choose. The student's reference is the PRN they enter on Quickteller, an ATM, USSD or at a bank. Import the day's collections report here to confirm those payments; when the query credentials above are set, the ten-minute sweep also polls Interswitch."
- Billers table columns: College ("Health Sciences" or "All departments"), Biller, Code, Pay link, Active ("Active" or "Off").
- Editable row per biller: inputs "Biller code", "Name", "Pay link".
  - **"Save"** (code and name required): `PUT /api/v1/payments/paydirect/billers/{scope}` with body `{code,name,link,active:true}`. X-Reason "PayDirect biller {scope} updated". Message "{scope} biller saved".
- **Import the collections report** (textarea). Hint "Paste rows: PRN, amount, settlement reference (RRN) — with or without a header. One payment per line."
  - **"Import and match"**: `parseRows` with the headers prn, amount, rrn, paidat, channel, payer. Then `POST /api/v1/payments/paydirect/import` with body `{rows:[{prn,amount,rrn,paidAt,channel,payer}]}`. X-Reason "PayDirect collections report imported".
  - Message: "Imported {n}: {m} matched, {u} unmatched, {d} already seen".
- Collections table (first 50 rows): Imported, PRN (RRN underneath), Amount, Channel, State, Note.
  - State pill shows the state in lower case: MATCHED = ok, DUPLICATE = grey, anything else = bad.
  - Note: "Confirmed {reference}" or the reason text.

**Panel "Test the gateway"** (when `may`; header-right "A small reference for a demo student, opened on the gateway")
- **Student**: default **hard-coded "MOAUM/MTC/24/9903"**. Hint "A demo student's matriculation number."
- **Amount**: default "100". Hint "₦100 is enough."
- **Gateway**: select. Unwired gateways are disabled and marked "— not wired".
- **"Open a test checkout"** (needs a live gateway and a number): `POST /api/v1/payments/test-checkout` with body `{number, amount, gateway}`. X-Reason "Gateway test checkout for {number}". Redirects to `j.url`.
  - Copy: "Pay with the gateway's test card; the webhook lands in the log below, and the reference shows as settled. The purpose is "Gateway test", which counts for nothing against the student's fees."
- **Ask about a reference**: placeholder "MOAUM-FEE-…". Hint "Any reference this portal generated."
  - **"Verify with the gateway"**: `POST /payments/verify` with body `{reference}`. Message "{ref}: {outcome}[ ({said})]".
  - **"Run the sweep now"**: `POST /api/v1/payments/sweep`. X-Reason "Reconciliation sweep run by hand". Message "The sweep ran; hanging payments were asked about".

**Panel "Webhook and verification log"** (header-right "Every event the portal received, signature good or bad")
- Columns: When, Gateway (source underneath), Event (· status), Reference (gateway reference underneath), Amount, Signature ("Valid" or "Invalid"), Result (OUTCOME pill).
- Resolved events show "Resolved: {resolution} · {name}".
- For unresolved UNKNOWN_REFERENCE, SHORT_PAID, BAD_SIGNATURE or GATEWAY_ERROR, and only when `may`: **"Resolve"**.
  - Prompt: "How was it resolved? It goes on the record."
  - `POST /api/v1/payments/events/{id}/resolve` with body `{resolution}`. X-Reason "Gateway event resolved: {why}".
- Empty: "No event has reached the portal yet. Open a test checkout above and pay with the gateway's test card."

**Footer note** "A callback is a hint, not an instruction": "The portal never credits a student because a gateway said so without keeping what it said. A forged callback is discarded at the signature and logged; a short payment is logged and left open; and on the student's "check again" the portal asks the gateway itself what the reference settled for."

---

## 6. Hanging payments — `/finance/hanging`
Files: `page.tsx`, `Hanging.tsx`.

**Title.** "Hanging payments" / "Successful at the gateway, pending here". The **menu badge "7" is hard-coded** (`menus.ts:544`).

**Gating.** `may` = bursar, ict, admin or super. Loads `GET /api/v1/payments/bursary`.

**Info note** "A payment that succeeded at the gateway has succeeded": "The portal's record is a copy; the gateway's is the fact. When the two disagree the portal is wrong, and the student is not the party who should have to prove it. **There is no upload-your-evidence form on this page, and that is the design.** The portal asks the gateway."

**Feedback note:** title is the result message, body "On the record; the student is told when a settlement posts."

**Tiles**
- **Hanging now** — "Checkout opened, nothing confirmed, last three days"
- **Resolved without a person** — "{x} by the sweep, {y} on request" (counts SWEEP or VERIFY events with outcome SETTLED)
- **Needs a person** — "Unknown reference, short paid, or the gateway silent"
- **The sweep**: **static "Every 10 min"** — "Runs whether or not this page is open"

**Panel "Hanging at a gateway"** (header-right "Oldest first · the sweep asks about each after five minutes, up to twelve times")
- Columns: Opened ("{when}" over "{n} min ago"), Payer (payer over number or kind), Reference, Gateway, Amount, Asked ("{n}× · last {when}" or "not yet"), action.
- **"Ask the gateway"** (shows "Asking…"): `POST /api/bff/api/v1/payments/verify` with body `{reference}`. X-Reason "Hanging payment {ref} verified with the gateway". Toast "{ref}: {outcome}".
- Empty: "Nothing is hanging: every checkout opened in the last three days is confirmed, or was never paid."

**Panel "Needs a person"** (header-right "What the sweep could not resolve on its own")
- Covers unresolved UNKNOWN_REFERENCE, SHORT_PAID and GATEWAY_ERROR events.
- Columns: When, Gateway, Reference, Amount, "Why it hung", action.
- "Why it hung" = OUTCOME pill plus explanation:
  - UNKNOWN_REFERENCE: "Generated and abandoned, paid against another institution's code, or forged — the desk officer chooses; the portal does not guess."
  - SHORT_PAID: "Less than the reference asks; applied as nothing, left open. A part payment needs a reference for the part."
  - Otherwise: "The gateway did not answer for this reference."
- **"Resolve"**: prompt "How was it resolved? It goes on the record." Then `POST …/payments/events/{id}/resolve` with body `{resolution}`. X-Reason "Gateway event resolved: {why}". Toast "Gateway event resolved".
  - **When this call fails, nothing is shown** (`:74`).
- Empty: "Nothing waits on a person."

**Footer note** "The student is told, not left to notice": "Every settlement — by webhook, by the sweep, or on request — sends the receipt by email and SMS on the spot, and the student's fees page shows it."

---

## 7. Payment investigation (exceptions / cash desk) — `/finance/exceptions`
Files: `page.tsx`, `Exceptions.tsx`.

**Title.** Route `t/exception`: "Payment investigation" / **"Unmatched settlement · teller slip BR/44821"**. The subtitle is static prototype text from `titles.ts:531`.
- The menu entry `t/cashdesk` ("Cash Office & Assets") also points to this URL. Its own title ("Cash office and final account" / "Revenue received, and the assets extracted from it") is never shown, because the page always uses the `t/exception` route.

**`page.tsx`**
- `?state=` can be `open`, `posted` or `all`; default `open`.
- Loads `GET /api/v1/finance/bank-credits?state=…` and `/api/v1/payments/bursary`. The count of unresolved gateway exceptions is passed to the client.

**Gating.** `may` = bursar or super.

**Top note**
- **When credits are open** (bad): title "₦{open amount} is sitting in the University's account and belongs to somebody". Body: "A payment the University cannot attribute is worse than a payment it never received: a student has paid, believes they have paid, and may be blocked from registering. The clock on this exception is the registration deadline, not the accounting period."
- **When nothing is open** (ok): title "No bank credit waits to be attributed". Body: "Money that arrives at a bank counter with no reference quoted is recorded here as it came, and posted only when two officers have agreed where it belongs."
- Added when there are gateway exceptions: "{n} gateway event(s) also need(s) a person — see hanging payments" (links to `/finance/hanging`).

**Feedback note** body: "On the record, in your name."

**Tiles**
- **Open**: count — ₦ amount
- **Proposed, awaiting a second officer** — "The proposer cannot approve"
- **Posted** — "Shown under Posted" (in the open view) or "In this view"
- **Cash ceiling**: **hard-coded ₦1,000** — "Cash below it at the counter; a draft above it"

**State filter buttons:** Open, Posted, All. Each links to `?state=…`.

**Panel "Bank credits"** (header-right "Recorded as they came; the bank record is never altered")
- Columns: Received, Instrument ("{bank} · {instrument}" over "{note} · recorded by {name}"), Payer named ("Not named" if empty), Amount, State, Resolution.
- State pills:
  - POSTED: "Posted to {ref}", with "Proposed by X, approved by Y · date".
  - PROPOSED: "Proposed", with "{ref} (₦ref amount) — {why} · {proposer}".
  - REVERSED: "Reversed".
  - Otherwise: "Unmatched".
  - When a proposal was rejected: "Last proposal rejected: {why}".
- **Unmatched rows, when `may`**
  - Inputs "Reference to post to" and "On what evidence". Both required.
  - **"Propose"**: `POST /api/v1/finance/bank-credits/{id}/propose` with body `{reference, why}`. X-Reason "Bank credit {instrument} proposed against {ref}". Message "Proposed — a second officer approves".
- **Proposed rows, when `may`**
  - If you made the proposal: pill "Your proposal — another officer approves".
  - Otherwise, **"Approve and post"**: `POST …/{id}/approve`. X-Reason "Bank credit {instrument} approved and posted to {ref}". Message "Posted: {outcome}".
  - Otherwise, **"Reject"**: prompt "Why is the proposal rejected?" Then `POST …/{id}/reject` with body `{why}`. X-Reason "Bank credit proposal rejected: {why}". Message "Rejected; the credit is open again".
- Empty: "No bank credit in this view."

**Panel "Record a bank credit"** (when `may`; header-right "The cash office: a draft or a counter credit, as the bank shows it")
- **Received on**: date, optional.
- **Bank** (required): placeholder "Zenith Bank, Makurdi".
- **Teller slip or draft number** (required): placeholder "BR/44821".
- **Amount** (required, above 0): digits and "." only.
- **Payer named on the slip**: optional.
- **Note**: optional.
- **"Record the credit"**: `POST /api/v1/finance/bank-credits` with body `{receivedOn, bank, instrument, amount, payer, note}`. X-Reason "Bank credit {instrument} recorded". Message "Recorded, unmatched".

**Panel "Why it is a posting, never an edit"** — four static gates, all shown as done:
1. "The bank record is never altered" / "It is evidence. The posting is a new entry that references it."
2. "Two people, recorded separately" / "Proposer and approver, and never the same person — the database refuses the second click."
3. "The reason is stored with the entry" / "On the credit, permanently, with the proposer's name."
4. "The student is told what changed" / "The posting is the same confirmation every payment passes, and it sends the receipt."

---

## 8. Refunds & credits — `/finance/refunds`
Files: `page.tsx`, `Refunds.tsx`.

**Title.** "Refunds & credits" / "Maker–checker controlled".

**`page.tsx`.** Loads `GET /api/v1/finance/refunds`. When `?refund={reference}` is present (from the Ledger's Refund button) and the office may act, the "Raise a refund" modal opens pre-filled.

**Gating.** `may` = bursar or super. For other offices the panel header-right reads "You are reading this queue".

**Status vocabulary** (`STATE`, `:25`)

| Code | Pill |
|---|---|
| PROPOSED | warn "Awaiting approval" |
| APPROVED | info "Approved, to pay" |
| PAID | ok "Paid" |
| REJECTED | grey "Rejected" |

**Info note** "Maker and checker are always different people": "The officer who raises a refund cannot approve it. The system refuses the second click rather than relying on anyone to remember the rule. A refund is paid only after a second officer has approved it, into the account snapshotted when it was raised."

**Feedback note** body: "It waits for a second officer to approve it before any money leaves the University."

**Tiles**
- **Awaiting approval** — "A second officer must agree"
- **Approved, to pay** — "Ready to disburse"
- **Paid** — "On the record"
- **All** — "Newest 300" (static hint)

**Panel "Refund requests"**
- Columns: Reference ("against {source_reference}" underneath), Payer (payer over number), Reason, Amount, Stage (pill, "Raised by you" or "Raised by {name}", and the rejection reason), Action.
- Actions:
  - **"Approve"** (PROPOSED, not your own): `POST /api/v1/finance/refunds/{id}/approve`. X-Reason "Approve refund {ref}". Message "{ref} approved".
  - Your own PROPOSED refund: disabled **"Awaiting another approver"**.
  - **"Reject"** (PROPOSED): prompt "Why is this refund rejected? The reason is recorded." Then `POST …/{id}/reject` with body `{why}`. X-Reason "Reject refund {ref}".
  - **"Mark paid"** (APPROVED): confirm "Mark {ref} paid? Record this once the money has left, into {account_name ?? "the account on file"}." Then `POST …/{id}/pay`. X-Reason "Refund {ref} paid". Message "{ref} recorded paid".
  - Otherwise the text reads "Disbursed" or "Approved by {name}".
- Empty: "No refund has been raised. A refund appears here when an overpayment, a duplicate payment or a withdrawal is owed back."

**Button "+ Raise a refund"** (when `may`).

**Modal "Raise a refund"** (subtitle "It goes to a second officer to approve")
- **From a payment reference**: optional. Placeholder "e.g. a receipt or reference". Hint "Optional — name the transaction being refunded and the payer and amount are filled in and checked against it."
  - **"Fetch"** (or Enter): `GET /api/bff/api/v1/finance/refunds/transaction?reference=…`.
  - This fills in the payer and amount, and a reason of "Refund against {REF}[ — {purpose}]".
  - Result note: "Confirmed payment of ₦x" (ok) or "Not a confirmed payment" (bad). Body: "{payer ?? "Payer not on record"}[ · number][ · purpose][ · receipt …]. A refund cannot exceed what was paid on this transaction."
- **Paid to** (required): hint "The student or sponsor the money is owed to".
- **Reason** (required): placeholder "Duplicate payment — timeout retry".
- **Amount (₦)** (required, above 0).
- **Bank**: hint "Optional".
- **Account name**: hint "Must match the payer".
- **Account (last 4)**: no length or format check.
- **"Raise it"**: `POST /api/v1/finance/refunds` with body `{student, payer, reason, amount, bank, accountName, accountLast4, source}`. X-Reason "Raise refund for {payer}". Message "Refund {reference} raised for {payer}".

---

## 9. Funding sources — `/finance/sources`
Files: `page.tsx`, `Sources.tsx`.

**Title.** "Funding sources" / "The sources of income a wallet is funded from — add as many as you need".

**`page.tsx`.** Loads `GET /api/v1/funding/sources`.

**Gating.** `canEdit` = bursar, admin or super. `RoleLine allowed=["bursar"] action="Adding and editing funding sources"`.

**Nature vocabulary** (`NAT`): LOAN = "Loan" (info), GRANT = "Grant" (ok), SELF = "Own money" (grey).

**Info note** "The sources of income, kept in the database": "Every source here is a row the University keeps and can add to at any time. A source is a **loan** the student repays the Fund (NELFUND), a **grant** that is never repaid (a scholarship or bursary), or the student's **own money** (a top-up). Every wallet credit names one of these, and a student's wallet shows one card per source with the balance as their total."

**Panel "Funding sources"** (header-right "{n} on the list · {m} active")
- Columns: Code, Name (note underneath), Nature, Sponsor ("—"), Holding account ("Main school account" when blank), Active ("Active" or "Off"), actions.
- Actions:
  - Edit icon. Scrolls to the form.
  - **"Turn off"** or **"Turn on"**: `POST /api/v1/funding/sources` with the full row and `active` flipped. X-Reason "Funding source {code} turned off|on". Message "{name} turned off|on".
- Empty: "No source on the list yet."

**Form panel.** Title "Add a source of income", or "Edit {code}" when editing. Header-right "A new scholarship, sponsor, fund or loan" or "Saving the same code edits it".
- **Code** (required): upper-cased and stripped to `[A-Z0-9]`. Disabled when editing. Hint "Short, e.g. TETFUND".
- **Name** (required): placeholder "TETFund scholarship".
- **Nature**: "Loan — repaid" / "Grant — never repaid" / "Own money". Default GRANT.
- **Sponsor**: hint "Optional".
- **Holding account**: hint "Blank = main school account".
- **Sort order**: digits only. Default 50. Sent as `Number || 100`.
- **Note**: hint "Shown under the name on the list".
- **"Add the source"** or **"Save the source"**: `POST /api/v1/funding/sources` with body `{code,name,nature,sponsor,account,active:true,note,sort}`. X-Reason "Funding source {code} added|edited".
- **"Cancel"** appears when editing.
- **"Funding report"** links to `/finance/nelfund?tab=report`.
- Copy: "NELFUND, Scholarship and Self top-up are seeded; add TETFund, a state scholarship, a sponsor or a bursary here. Add as many as you need."
- For other offices: note "Read-only" / "Only the Bursary, admin or super administrator can add or change a source of income."

---

## 10. Sources of funding / NELFUND — `/finance/nelfund`
Files: `page.tsx`, `Nelfund.tsx` (381 lines).

**Tab from the URL.** `?tab=` can be match, status, withdrawals, sources or report; anything else means `batches`.

**Title depends on the tab**
- `match` uses route `t/nelmatch`: "Unmatched remittances" / "Money received that is not yet on a wallet".
- `status` uses route `t/nelstatus`: "NELFUND applicants" / "Approved, not approved, and still with the Fund".
- Every other tab uses route `t/nelfund`: "Sources of funding" / "Loans, scholarships, wallets, withdrawals and the report".

**Session.** Taken from `loadScope(params)`, i.e. `?session=` or the remembered scope cookie.

**Data.** `GET /api/v1/nelfund/sessions/{session}` (desk) and `GET /api/v1/funding/sessions/{session}/report`.

**Gating**
- `bursary` = bursar, admin or super.
- `registry` = registrar, dregistrar, academic, super or bursar. Registry offices can match rows on the Suspense tab.

**Vocabularies**
- `LKIND` (wallet ledger): CREDIT "Credit" ok, TOPUP "Top-up" ok, APPLIED "Applied to fees" info, REVERSED "Reversed to source" bad, REFUND "Withdrawn to bank" grey.
- `NAT`: the same as the Sources page.

**Header card**
- **Session** select.
- Tabs:
  - "NELFUND remittances"
  - "Suspense[ ({unmatched_rows})]"
  - "The Fund's decisions"
  - "Withdrawals[ ({requested})]"
  - "Sources"
  - "Report"
- Navigation goes to `/finance/nelfund?tab=…&session=…`.

**Feedback note** body: "On the record, in your name."

### Tab "NELFUND remittances" (`batches`, the default)
**Tiles**
- **Received this session**: ₦ — "{n} batch(es), {students} students"
- **Allocated to students** — "Credited to a named wallet"
- **Unallocated** (red when above 0) — "{n} row(s) not yet matched"
- **Reversed to the Fund** — "Withdrawn, or not on the register"

**Suspense note**
- When there are unmatched rows (bad): title "{n} row(s) are money the University is holding that a student cannot see". Button **"Match the {n} outstanding"** goes to the Suspense tab. Body: "A remittance is received in bulk and must be split across named students. Until it is, a student whose loan was approved and paid still shows as owing. Every naira either sits on a student's wallet or sits here, and this figure is the queue."
- Otherwise (ok): "Every naira received is on a named wallet" / "There is nothing in suspense."

**Panel "Remittance batches"** (header-right "From the Fund, newest first")
- Columns: Reference, Received, Amount, Rows, Matched, Unmatched (red), Reversed.
- Empty: "No remittance loaded for {session}."

**Panel "Load a remittance"** (bursary only; header-right "Matched on matriculation number against the register, the same register the class list is drawn from")
- **The Fund's reference** (required): placeholder "NLF/2026/0918".
- **Received on**: date.
- **Note**.
- **"Download template"**: "NELFUND remittance template.xlsx" with columns Matriculation Number, Name, Amount, and a sample row "Ada Example (delete this row)".
- **"Upload filled file"** (`.xlsx`): fills the textarea. Message "{n} row(s) read from the file — review below, then Load and match."
  - Errors: "The file had no rows to read." / "Fill the template's Matriculation Number, Name and Amount columns, then upload it."; "That file could not be read as a spreadsheet." / "Use the downloaded template (.xlsx)."
- Helper: "Download the .xlsx, fill it, and upload it — or paste the rows below."
- **The rows** (textarea, required): hint "Matriculation number, name, amount — one student per line, comma- or tab-separated, with or without a header. The uploaded file fills this in for you."
- **"Load and match"**: `POST /api/bff/api/v1/nelfund/batches` with body `{ref, session, receivedOn, note, rows:[{matricNo,name,amount}]}`. X-Reason "NELFUND remittance {ref} loaded". Message "{ref}: {matched} matched, {unmatched} in suspense, ₦amount".

**Panel "Credit a student's wallet"** (bursary only; header-right "A scholarship, a sponsor's payment off the gateway, a correction")
- **Matriculation or admission number** (required): placeholder "MOAUM/CSC/26/0001".
- **Source of the funding**: "Choose a source…" plus active sources shown as "{name} · loan|grant|own money". Hint "The source says whether it is repayable — set the list on the Sources tab." Optional; sent as null when empty.
- **Amount** (required): placeholder 50000.
- **Reason** (required): placeholder "TETFund scholarship 2026/2027". Hint "The student sees this on their wallet statement."
- **"Credit the wallet"**: `POST /api/bff/api/v1/nelfund/credit` with body `{number, session, amount, reason, source}`. X-Reason "Wallet credited: {number}". Message "₦x credited to {number} — wallet balance ₦y".
- Copy: "This is an attributed credit against the named student's wallet. It counts toward what the wallet can apply to their charges, and the source and reason travel on the statement."

**Panel "Look up a student's wallet"** (all offices; header-right "The whole transaction history — credits, top-ups, what was applied, reversals and refunds")
- **Matriculation or admission number**: placeholder "MOAUM/CSC/26/0001".
- **"Show the history"** (or Enter): `GET /api/bff/api/v1/nelfund/student/statement?number=…&session=…`.
- **"Clear"**.
- The header shows the name, number, status pill, "Wallet balance ₦x" and "Outstanding for {session} ₦y".
- **"Reset wallet to zero"** (bursary only):
  - Confirm: "Wipe {name}'s wallet to zero?\n\nEvery credit, top-up, applied entry and withdrawal is deleted and the balance starts afresh. This cannot be undone."
  - Then prompt: "Why is the wallet being reset? It goes on the record."
  - `POST /api/bff/api/v1/nelfund/reset` with body `{number, reason}`. X-Reason "Wallet reset to zero: {number}".
  - Message: "{name}'s wallet wiped — {n} entr(y|ies) and {w} withdrawal(s) removed. Balance ₦0."
- Statement columns: Date, Entry (LKIND pill over note), Reference, In, Out, Balance.
- Empty: "No movement on this student's wallet yet."

**Footer note** "The reconciliation runs against the register, not against a spreadsheet": "A number that is not on the register is refused rather than created — which is why an unmatched row is the Registry's to answer, not this office's to force."

### Tab "Suspense" (`?tab=match`)
**Top note**
- When rows are held (bad): title "{n} remittance(s) are held in suspense". Body: "Each row is money the Fund has paid and the University is holding. None of it may be credited on a guess: a wallet credited to the wrong student is money the Fund will later reclaim from someone who never received it. {x} are the Registry's to resolve, {y} this office's."
- Otherwise (ok): "Suspense is empty" / "Every row of every remittance for {session} is on a named wallet or reversed to the Fund."

**Panel "Unmatched remittances"** (header-right "Suspense is owned, not parked")
- Columns: Matriculation number, Name on the remittance (batch reference underneath), Amount, Why it failed ("{student_name} · {status}" underneath), Owner (pill), What resolves it.
- **Registry offices**: inputs "Number on the register" and "Evidence, one line", both required.
  - **"Credit"**: `POST /api/bff/api/v1/nelfund/rows/{id}/match` with body `{number, note}`. X-Reason "Remittance row {matric} matched by hand". Message "Matched and credited".
- **Bursary offices**: **"Reverse"**. Prompt "Why is it reversed to the Fund? It goes on the record." Then `POST …/rows/{id}/reverse` with body `{why}`. X-Reason "Remittance row {matric} reversed to the Fund". Message "Reversed to the Fund".
- When there are no rows the panel body is empty; the note above carries the empty message.

**Footer note** "Suspense is owned, not parked": "Every row carries an office. A suspense account nobody owns is how money sits for a session and a student carries a debt they were never told about."

### Tab "The Fund's decisions" (`?tab=status`)
**Info note** "The Fund decides, the University records, and the student must be able to see which": "Nothing on this screen is the University's decision. What is the University's responsibility is that a student knows where they stand **before** registration rather than at it — and that the ones refused for a reason they can fix are told which field to fix, by name."

**Tiles**
- **Applied** — "{session} session"
- **Approved** — "₦{received} received"
- **Not approved** — "Each told, by name"
- **Still with the Fund** — "No decision yet — and told that too"

**Correctable note** (bad, when some refusals are correctable): title "{c} of the {n} refusals can be fixed by the student". Body: "A refusal for a wrong institution code or a name that does not match a BVN is a typing error, and the Fund reissues on correction. Each student concerned sees the field to fix on their wallet screen."

**Panel "Why the {n} were refused"** (header-right "And which of them is the University's to help with")
- Columns: Reason, Students, Correctable ("Yes" ok or "No" info).
- Empty: "No refusal on the Fund's list for {session}."

**Panel "Load the Fund's list"** (bursary only; header-right "All applicants, with the decision and the reason")
- **The rows** (textarea): hint "Paste: number (matriculation or JAMB), name, decision (approved / not approved / pending), reason — one per line, with or without a header."
- **"Load the list"**: `parseRows` with number, name, state, reason. Then `POST /api/bff/api/v1/nelfund/status` with body `{session, rows}`. X-Reason "NELFUND decision list loaded for {session}". Message "{loaded} loaded: {a} approved, {n} not approved, {p} pending".
- Link **"Remittances"** goes to `/finance/nelfund?tab=batches`.

### Tab "Withdrawals"
**Info note** "Money leaving the wallet to a student's bank account": "A student may withdraw a wallet balance only once the session's fees are cleared and nothing is owed — a student who paid ahead before their loan landed has genuinely paid twice. It is requested by the student, approved here, and **paid by a second officer**; the portal records the payout, it does not move the money itself."

**Panel "Withdrawal requests"** (header-right "{n} awaiting a decision")
- Columns: Student (name over matric), Bank account (bank over "{account_no} · {account_name}"), Amount, State, Requested, actions.
- State pill shows the state in lower case: PAID ok, REJECTED bad, APPROVED info, anything else grey.
- **REQUESTED rows, bursary**
  - **"Approve"**: `POST /api/bff/api/v1/funding/withdrawals/{id}/approve`. X-Reason "Withdrawal for {name} approved". Message "Approved — a second officer records the payout".
  - **"Decline"**: prompt "Why is it declined? The student sees it." Then `POST …/reject` with body `{why}`. X-Reason "Withdrawal for {name} declined".
- **APPROVED rows, bursary**
  - Input "Bank transfer ref" (optional).
  - **"Mark paid"**: `POST …/pay` with body `{ref}`. X-Reason "Withdrawal for {name} paid". Message "Paid — the wallet is debited". **There is no confirmation prompt.**
- PAID rows show the paid reference (or "paid"). REJECTED rows show the reason.
- Empty: "No withdrawal request for {session}."

**Footer note** "The officer who approves is not the one who pays": "The database refuses a payout recorded by the same person who approved it — two people stand behind money leaving the University."

### Tab "Sources"
**Info note** "The sources funding is credited from": "Each source is a **loan** the student repays (NELFUND), a **grant** that is never repaid (a scholarship or bursary), or the student's own money (a top-up). Every wallet credit names its source, so the ledger and the report can say what is repayable and what is not."

**Panel "Funding sources"** (header-right "{n} on the list")
- Columns: Code, Name, Nature, Sponsor, Holding account, Active. There are no row actions here.

**Panel "Add or edit a source"** (bursary only; header-right "A new scholarship, sponsor or fund — same code edits")
- Fields: Code (upper-cased only; **not** stripped of other characters, unlike `/finance/sources`), Name, Nature, Sponsor, Holding account, Sort order.
- There is **no Note field**, although `src.note` is sent in the body.
- **"Save the source"**: `POST /api/bff/api/v1/funding/sources`. X-Reason "Funding source {code} stated". Message "Source {code} saved".
- Copy: "NELFUND, Scholarship and Self top-up are seeded; add TETFund, a state scholarship, a sponsor or a bursary here."
- This tab duplicates `/finance/sources`.

### Tab "Report" (read-only)
**Tiles**
- **Funded this session**: credited + topped up — "Credits and top-ups, all sources"
- **Applied to school fees** — "Reconciles with Bursary receipts", or in red "Does not match receipts"
- **Withdrawn to bank** — "Paid out to students"
- **Held in wallets** — "Not yet applied or withdrawn"

**Panels**
- **"By source"** (header-right "Where the money came from"). Columns: Source ("{code} · {sponsor}" underneath), Nature, Students, Credited.
- **"By nature"** (header-right "Repayable or not"). Rows: "Loans (repayable)", "Grants (never repaid)", "Own money (top-ups)". Columns: Nature, In. Copy: "A loan is a liability the student repays the Fund; a grant is not repaid; own money is the student's."
- **"Cash-flow reconciliation"** (header-right "The wallet against the Bursary and school payments"). Columns: Movement, Amount, Note.

| Movement | Note |
|---|---|
| Credited (loans + grants) | "Into wallets, from all sources" |
| Topped up by students | "Own money paid in" |
| Applied to school fees | "Moved to the main account against invoices" |
| Confirmed as wallet payments | "Matches the applied total" or "Does NOT match — investigate" |
| Reversed to source | "Returned to the Fund" |
| Withdrawn to bank | "Paid out to students" |
| Held in wallets | "The balance the University still holds" |

**Closing note:** "The wallet reconciles with school payments" (ok) or "The wallet does not reconcile — investigate" (bad). Body: "Every naira a wallet applied to fees is a confirmed payment on the main account with the wallet as its channel. ₦{applied} applied against ₦{settled} confirmed."

**When there is no report:** "No report yet" / "Nothing has moved through the wallet for {session}."

There are no Excel or PDF exports on any NELFUND tab.

---

## 11. Settlement reconciliation — `/finance/reconcile`
Files: `page.tsx` (server-rendered tables), `ReconcileLedger.tsx` (client).

**Title.** "Settlement reconciliation" / "Gateway settlements against the ledger". The **menu badge "12" is hard-coded** (`menus.ts:560`).

**`page.tsx`**
- Loads `GET /api/v1/payments/bursary` and `/api/v1/finance/bank-credits?state=open`. If the gateway desk fails, only the `ProblemNotice` shows.
- `canCheck` = bursar, audit, deputyaudit or super.
- Server tiles:
  - **Gateway settled**: ₦ — "{n} event(s) posted, last 200"
  - **Matched**: % — "Events the portal could post or safely ignore"
  - **Exceptions**: count — "₦x at the gateways · {n} bank credit(s)"
  - **Hanging** — "Checkouts with nothing confirmed"

**`ReconcileLedger` (client component)**
- Dates default to the last 30 days up to today. Loads `GET /api/bff/api/v1/finance/reconciliation?from=…&to=…`.
- Tiles:
  - **Confirmed in the window**: ₦ — "{n} transaction(s)"
  - **Matched to the bank** — "Validated against the statement"
  - **Discrepancies** — "Do not agree with the bank"
  - **Not yet checked** — "Awaiting reconciliation"
- Panel "Confirmed payments to reconcile". Header-right "Check each against the bank statement" (when `canCheck`) or "You are reading this reconciliation".
- **From** and **To** date filters. Changing either reloads straight away.
- Loading text: "Reading the ledger…".
- Columns: Reference (purpose underneath), When, Payer, Amount, Bank / status, and Action when `canCheck`.
- Bank / status cell:
  - Pill "Matched", "Discrepancy" or "Not checked".
  - "Bank {ref}", the note, and "Reconciled by X" or "Flagged by X".
- **"Matched"** (shows "Re-confirm" when already matched):
  - Prompt: "Bank reference for {ref}? (optional — the credit or narration on the statement)".
  - `POST /api/bff/api/v1/finance/reconciliation/{ref}/check` with body `{result:"MATCHED", bankReference, note:null}`. X-Reason "Reconcile {ref}: matched".
- **"Flag"**:
  - Prompt: "What does not agree for {ref}? The note is recorded." (required).
  - Then: "Bank reference, if any (optional)".
  - Body `{result:"DISCREPANCY", bankReference, note}`. X-Reason "Reconcile {ref}: discrepancy".
- Messages: note "{ref} recorded as matched to the bank|a discrepancy"; toast "{ref} recorded as matched|a discrepancy".
- Empty: "No confirmed payment between {from} and {to}."
- Note "Reconciliation validates the ledger against the bank; it does not move money": "A transaction the portal marks confirmed was confirmed by a gateway callback or by the Bursary against a bank record. This step is the independent check that the money actually landed in the University's account. A discrepancy - a settled callback with no matching credit, or an amount that differs - is flagged with a note for the Bursary to resolve. Both the audit directorate and the Bursary may reconcile."
- **Bug at `:45`:** `else setProblem(...); notifyProblem(...)` has no braces. `notifyProblem` therefore runs on **every** load, including successful ones, and fires an error toast with the success payload.

**Server panel "Exceptions requiring action"** (header-right "Every exception is cleared before the period closes")
- Columns: Reference, Amount, Payer, Exception, Resolution.
- Gateway rows: OUTCOME label plus explanation:
  - UNKNOWN_REFERENCE: "Bank branch or another institution's code — or generated and abandoned"
  - SHORT_PAID: "Amount differs from the reference — a part payment needs a reference for the part"
  - BAD_SIGNATURE: "Discarded at the signature; nothing read from it"
  - Otherwise: "The gateway did not answer for the reference"
  - Button **"Investigate"** goes to `/finance/hanging`.
- Bank-credit rows: "Bank branch payment, no reference quoted", with "Proposed against {ref}; awaiting a second officer" or "Recorded as it came; awaiting a proposal". Button **"Approve"** or **"Investigate"** goes to `/finance/exceptions`.
- Empty: "Nothing to reconcile: every gateway event posted or was resolved, and no bank credit waits."

**Server panel "The other exception types, and how each resolves"** — a static table. Columns: Exception, What it means, Resolution, Approvals.
1. "Settled at the gateway, not posted internally" (The common one) / "The callback never arrived" / "The sweep asks the gateway every ten minutes and posts what it answers" / "None — automatic"
2. "Duplicate event" (The gateway sent it twice) / "Two callbacks for one reference" / "The second finds the reference confirmed and does nothing" / "None"
3. "Amount differs from the reference" (Short paid) / "Less than the reference asks" / "Logged and left open; a reference for the amount received is generated and the gateway asked again" / "None"
4. "No reference quoted" (Bank counter) / "Teller slip only" / "Recorded, proposed and approved on the exceptions desk" / "Two"
5. "Forged callback" (Bad signature) / "Not from the gateway" / "Discarded at the signature and logged; resolved on the record" / "One, to close it"

**Footer note** "A payment is confirmed by the gateway or the bank, never by the browser": "The candidate's browser may never return from the payment page. Two independent paths therefore converge on one idempotent settlement: the gateway's signed callback, and the sweep that asks the gateway about every open checkout. Whichever arrives first settles the payment; the second finds it already settled and does nothing." When any ALREADY_SETTLED event exists, a pill "Seen happening in this log" is added.

---

## 12. Transactions & accounts (day book) — `/finance/ledger`
Files: `page.tsx`, `Ledger.tsx`.

**Title.** "Transactions & accounts" / "Payment history and the ledger".

**`page.tsx`.** `?from=` and `?to=` are passed to `GET /api/v1/finance/ledger`. The server returns the from/to it actually used.

**Gating.** None for viewing. `mayRefund` = bursar or super, which adds an Action column.

**Tiles**
- **Collected** — "{n} confirmation(s), {from} to {to}"
- **By card**: sum where the channel starts with "Card" — "Paystack and Flutterwave"
- **By bank**: channel starts with "Bank" — "Transfers and branch credits confirmed by hand"
- **From the wallet**: channel contains "wallet" — "NELFUND"

**Panel "Filter"**
- **From** and **To** dates.
- **"Apply"** goes to `/finance/ledger?from=…&to=…`.
- **"Export the journal"** (disabled when there are no rows): `download("ledger-{from}-{to}.csv", csv(...))`. Despite the `.csv` name, `download()` (`lib/results.ts:174`) writes a **branded .xlsx** named `ledger-{from}-{to}.xlsx` with the crest.
  - Columns: Reference, Confirmed, Payer, Number, Purpose, Session, Amount, Channel, Receipt, Note.

**Panel "Transactions"** (header-right "{n} · newest first")
- Columns: Reference, When, Payer, Purpose (session underneath), Channel, Amount, Receipt, and Action when `mayRefund`.
- Channel pill: ok for Card, info for wallet, grey otherwise. The note shows underneath.
- **"Refund"** links to `/finance/refunds?refund={reference}`.
- Empty: "Nothing confirmed between {from} and {to}."

---

## 13. Accounting & books — `/finance/accounting`
Files: `page.tsx`, `Accounting.tsx` (300 lines).

**Title.** "Accounting & books" / "The general ledger: chart of accounts, trial balance, income & expenditure, balance sheet".

**`page.tsx`.** Loads `/api/v1/finance/accounting/` `overview`, `chart`, `trial-balance`, `income-expenditure`, `balance-sheet` and `journals`. If any one fails, the first failure's `ProblemNotice` is shown instead of the screen.

**Gating.** `may` = bursar or super. `RoleLine allowed=["bursar"] action="Keeping the books — posting, journals and reversals"`.

**Money format.** ₦ with two decimals. Null shows "—".

**Tiles**
- **Cash & bank on the books** — "Collections + disbursements + cash"
- **Income this year** — "Since {yearStart}"
- **Expenditure this year** — "Since {yearStart}"
- **Surplus / (deficit)** (red when negative) — "{n} journal(s) posted"

**Sync note**
- When transactions are unposted (info): title "{n} transaction(s) not yet on the books". Button **"Post them now"** (shows "Posting…"): `POST /api/v1/finance/accounting/sync`. X-Reason "Ledger sync: posted confirmed payments, paid refunds and paid vouchers". Body: "{p} payment(s), {r} refund(s) and {v} voucher(s) are confirmed or paid but not yet posted. Posting is safe to run any time — each transaction posts once."
- Otherwise (ok): "The books are up to date" / "Every confirmed payment, paid refund and paid voucher is on the ledger. Run Sync again whenever new ones are confirmed."

**Tab bar** (aria label "The books"): Overview, Trial balance, Income & expenditure, Balance sheet, Journal book, Account ledger. The tab is held in client state only, not in the URL.

**Right of the tab bar** (when `may`)
- **"New journal"** (go). Opens the journal modal.
- **"Sync"** (shows "Syncing…"): the same endpoint as above. X-Reason "Ledger sync from the accounting screen".

**Overview tab**
- Panel "The books at a glance". Copy: "The accounting module keeps a proper set of double-entry books over the money the finance desk records. Money enters the ledger automatically when a payment is confirmed, a refund is paid, or a voucher is paid; the Bursar posts opening balances and adjustments by hand. Use the tabs above for the trial balance and the financial statements. Everything is cash-basis: income is recognised when received, expenditure when paid."
- Chart-of-accounts table. Columns: Account, Type, and an unlabelled third column showing "Debit" or "Credit" (the normal side). Non-postable (parent) accounts are bold; child accounts are indented.

**Trial balance tab**
- Panel "Trial balance — as at {asOf}". Pill "In balance" or "Out of balance".
- Columns: Account, Debit, Credit, with a Total row.
- Empty: "No postings yet. Run Sync to bring the cash records onto the books."

**Income & expenditure tab**
- Panel "Income & expenditure — {from} to {to}". Columns: blank, Amount.
- Section order: Income, then the INCOME_TOTAL row, Expenditure, EXPENSE_TOTAL, SURPLUS.
- Section labels map: ASSET "Assets", LIABILITY "Liabilities", EQUITY "Fund", INCOME "Income", EXPENSE "Expenditure".
- There is no empty-state text.

**Balance sheet tab**
- Panel "Balance sheet — as at {asOf}".
- Order: Assets, ASSET_TOTAL, Liabilities, Fund (EQUITY), FUNDS_TOTAL.

**Journal book tab**
- Panel "Journal book" (header-right "{n} shown").
- Columns: No. (#n), Date, Narrative (memo plus a pill "Auto" or "Manual", and "Reversed" when reversed), Amount.
- Row buttons:
  - **"Lines"** / **"Hide"** expands the row: "Journal #{n} — {memo}", with columns Account, Debit, Credit and narration inline.
  - **"Reverse"**: only for POSTED journals and when `may`.
- Empty: "No journals in this period." There is no period filter on this tab.

**Account ledger tab**
- **Account**: "Choose an account…" plus postable accounts "{code} — {name}".
- **From** and **To** dates.
- **"Show"** (shows "Loading…"): `GET /api/bff/api/v1/finance/accounting/ledger?account=…&from=…&to=…`.
- Columns: Date, No., Narrative, Debit, Credit, Balance.
- Empty: "No movement on {account name} in this period."
- Error: "Could not load the ledger."

**Modal "Post a journal"** (subtitle "A balanced entry — opening balances, an adjustment, a correction")
- **Date** (default today).
- **Narrative** (required): placeholder "e.g. Opening balances 2025/2026".
- Line rows:
  - **Account** select ("Choose…").
  - **Debit** and **Credit**. Typing in one clears the other.
  - "✕" removes a line, but is disabled while there are only two lines.
  - **"Add a line"** adds one.
  - `DraftLine.narration` exists in the code, but **there is no input for it**.
- Live footer "Dr ₦x · Cr ₦y", green when balanced and red otherwise.
- Validation text: "Debits must equal credits before you can post."
- Balanced means debits above 0 and |Dr−Cr| < 0.005.
- **"Post the journal"** (shows "Posting…"): `POST /api/v1/finance/accounting/journals` with body `{date, memo, lines:[{account,debit,credit,narration}]}`. Empty lines are dropped. X-Reason "Manual journal posted: {memo}".

**Modal "Reverse journal #{n}"** (subtitle is the memo)
- Bad note "A reversal, not a delete": "A mirror journal is posted that cancels this one; both stay on the record. The original is marked reversed."
- **Reason** (required): hint "Why this entry is being reversed".
- **"Post the reversal"** (shows "Reversing…"): `POST …/journals/{id}/reverse` with body `{reason}`. X-Reason "Journal #{n} reversed".

**Errors on this page**
- Refused request: "The request was refused."
- Network failure: "The network dropped the request."

There are no exports.

---

## 14. Budget — `/finance/budget`
Files: `page.tsx`, `Budget.tsx`.

**Title.** "Budget" / **"Financial year 2026"**. The subtitle is static (`titles.ts:627`) and does not follow the year selected.

**`page.tsx`**
- `?year=` is passed to `GET /api/v1/expenditure/budget`.
- It then loads `GET /api/v1/reports/income-expenditure?year={view.year}`. If that fails, the income and expenditure panel is simply not shown.

**Gating.** `may` = bursar or super.

**Info note** "Commitment accounting — budget is consumed at approval, not at payment": "An approved voucher reduces the available balance immediately, before the money leaves. That is what stops a cost centre committing money it has already promised elsewhere. Available is the budget less what is committed and what is spent."

**Controls**
- **Financial year** select. Options are year+1, year, year−1 and year−2. Changing it pushes `?year=` and refreshes.
- **"+ Set a cost centre's budget"** (when `may`).

**Tiles**
- **Budget** — "{n} cost centre(s)"
- **Committed** — "Approved, not yet paid"
- **Spent** — "Paid out"
- **Over budget** — "Further requisitions refused" or "All within budget"

**Panel "Budget performance by cost centre"** (header-right "Financial year {year}")
- Columns: Cost centre, Budget, Committed, Spent, Available (red when negative), Utilisation.
- Utilisation shows a bar and %. The bar is red at 100% or more, amber at 85% or more, green otherwise.
- Empty: "No budget is set for {year}, and no voucher has been raised against a cost centre. Set a cost centre's budget to begin."

**Panel "Income and expenditure"** (header-right "Financial year {year} · against budget")
- Columns: blank, Budget, Actual, Variance.
- Rows: income lines, "Total income", expense lines, "Total expenditure" (budget / actual / variance, variance red when negative), then "Surplus for the year" or "Deficit for the year".
- Copy: "Income and expenditure are read off the general ledger's income and expense accounts for the year. The budget is the cost-centre budget the Bursary set; the variance is what remains of it against actual expenditure. Income is not budgeted in the portal, so its budget column is blank."
- Empty: "No income or expense has been posted to the ledger for {year} yet."

**Modal "Set a cost centre's budget"** (subtitle "Financial year {year}")
- **Cost centre** (required): hint "The name vouchers use, e.g. Faculty of Science, ICT Directorate".
- **Budget (₦)**: must be 0 or more. An empty field counts as 0, so it passes.
- **"Set the budget"**: `POST /api/bff/api/v1/expenditure/budget` with body `{costCentre, year, amount}`. X-Reason "Budget for {cc}". Toast and ok note "Budget set for {cc}".

There are no exports.

---

## 15. Tenders — `/finance/tenders`
Files: `page.tsx`, `Tenders.tsx`.

**Title.** "Tenders" / "Evaluation and award".

**`page.tsx`.** Loads `GET /api/v1/expenditure/tenders`. When `?t={id}` is present it also loads the bids from `GET /api/v1/expenditure/tenders/{id}`.

**Gating.** `may` = bursar or super.

**Stage vocabulary** (`STAGE`)

| Code | Pill |
|---|---|
| ADVERTISED | info "Advertised — taking bids" |
| EVALUATED | warn "Evaluated — to award" |
| AWARDED | ok "Awarded" |
| CANCELLED | grey "Cancelled" |

**Method vocabulary** (`METHOD`): QUOTATION "Quotation", RESTRICTED "Restricted tender", OPEN "Open competitive bidding".

**Info note** "A procurement's method is set by its value, and the lowest bid is not automatically the winner": "Under ₦2.5m goes to quotation, ₦2.5m to ₦25m to a restricted tender, above ₦25m to open competitive bidding. Bids are scored on a technical threshold before price is looked at; a bid below the threshold or with an invalid clearance is not responsive, and the reason is recorded. Award goes to the lowest responsive bid unless the Board records why it does not."

**Tiles**
- **Open tenders** — "Taking or evaluating bids"
- **Awarded** — "On the record"
- **All** — "Newest 300"
- A fourth **placeholder tile** with an empty label, and value "Read only" when the office cannot act (`:69`).

**Button "+ Open a tender"** (when `may`).

**Panel "Tenders"** (header-right "Method by value · technical threshold before price")
- Columns: Reference, Subject (cost centre underneath), Estimate, Method, Bids ("{n}[ · {r} ok]"), Stage ("{awarded_to} · ₦price" underneath).
- Row button **"Evaluate"** (shows "Open" when selected) goes to `?t={id}`.
- Empty: "No tender has been opened. Open one for a procurement above the quotation threshold."

**Selected-tender panel "{ref} — {subject}"** (header-right "{method} · estimate ₦x · threshold {n}%")
- **"+ Record a bid"**: ADVERTISED tenders only, when `may`.
- Bids table columns: Bidder, Technical, Bid price, Responsive ("Yes" / "No — {reason}" / "Not scored"), Rank, Action.
- **"Score"** (ADVERTISED or EVALUATED, when `may`):
  - Prompt: "Technical score out of 100 (blank = not evaluated):".
  - The bid is responsive when the score is at or above the tender's threshold.
  - If it is not responsive, a second prompt: "Why is it not responsive? (e.g. below threshold, tax clearance expired)". This is required.
  - `POST /api/bff/api/v1/expenditure/tenders/bids/{bid}/score` with body `{technical, responsive, reason}`. X-Reason "Score bid on {ref}". Message "Bid scored".
- **"Award"** (EVALUATED tenders, responsive bids):
  - If a cheaper responsive bid exists, prompt "A lower responsive bid exists. Why is this one awarded?" (required).
  - Then confirm "Award {ref} to {bidder} at ₦x?".
  - `POST …/tenders/{id}/award` with body `{bid, why}`. X-Reason "Award {ref}". Message "{ref} awarded to {bidder}".
- Empty: "No bid recorded yet."
- When an award reason exists: note "Why this award, and not the lowest bid" with the reason.
- **"Cancel the tender"** (not awarded or cancelled): prompt "Cancel this tender. The reason is recorded." Then `POST …/{id}/cancel` with body `{why}`. X-Reason "Cancel {ref}".

**Modal "Open a tender"** (subtitle "Its method is set from the estimate")
- **What is being procured** (required): placeholder "40 desktop computers".
- **Estimate (₦)** (required, above 0).
- **Cost centre**: hint "Optional".
- **Technical threshold (%)**: default 70. No range check.
- Live text "Method: Quotation|Restricted tender|Open competitive bidding" (under 2,500,000; up to and including 25,000,000; above that).
- **"Open it"**: `POST /api/bff/api/v1/expenditure/tenders` with body `{subject, costCentre, estimate, threshold}`. X-Reason "Open tender: {subject}". Message "Tender {reference} opened".

**Modal "Record a bid on {ref}"** (subtitle "Sealed until opening; recorded here after")
- **Bidder** and **Bid price (₦)**, both required, price above 0.
- **"Record it"**: `POST …/{id}/bids` with body `{bidder, price}`. X-Reason "Bid on {ref}". Message "Bid recorded".

**Inconsistency.** Tender method codes (RESTRICTED, OPEN) differ from requisition method codes (RESTRICTED_TENDER, OPEN_BIDDING).

---

## 16. Requisitions — `/finance/requisitions`
Files: `page.tsx`, `Requisitions.tsx`.

**Title.** "Requisitions" / "Procurement pipeline".

**`page.tsx`.** Loads `GET /api/v1/expenditure/requisitions` (`{rows}`).

**Gating**
- `mayRaise` = bursar, ict, registrar, hrm, dean or super.
- `mayApprove` = bursar or super.
- There is no RoleLine.

**Vocabularies**
- `METHOD`: QUOTATION "Quotation", RESTRICTED_TENDER "Restricted tender", OPEN_BIDDING "Open bidding".
- `STATE`:

| Code | Pill |
|---|---|
| RAISED | warn "Awaiting approval" |
| APPROVED | info "Approved" |
| PO_RAISED | info "PO raised" |
| CLOSED | ok "Closed" |
| REJECTED | grey "Rejected" |

**Info note** "The procurement method is set by value, and cannot be overridden": "Under ₦2,500,000 goes to quotation, ₦2,500,000–₦25,000,000 to restricted tender, above ₦25,000,000 to open competitive bidding. A requisition is approved by a second officer, never the one who raised it."

**Feedback note** body: "On the record, in your name."

**Tiles**
- **Awaiting approval** — "A second officer must agree"
- **Approved / PO** — "In procurement"
- **Value awaiting** — "Raised, not yet approved"
- **Requisitions** — "All"

**Panel "Requisitions"**
- Columns: Reference, Item (description underneath), Cost centre, Value, Method (pill), Stage (pill, "by you" or "by {name}", and the note), Action.
- Actions (all `POST /api/bff/api/v1/expenditure/requisitions/{id}/…`):
  - **"Approve"** (RAISED, not your own): `/approve`. X-Reason "Approve {ref}". Message "{ref} approved".
  - Your own RAISED requisition: disabled **"Awaiting another approver"**.
  - **"Reject"**: prompt "Why is it rejected?" Then `/reject` with body `{why}`. X-Reason "Reject {ref}".
  - **"Raise PO"** (APPROVED): `/po`. X-Reason "PO for {ref}".
  - **"Close"** (PO_RAISED): `/close`. X-Reason "Close {ref}".
  - None of these ask for confirmation.
- Empty: "No requisition raised."

**Panel "Raise a requisition"** (when `mayRaise`; header-right "The method is shown as you type the value")
- **Item** (required).
- **Cost centre** (required): placeholder "ICT Directorate".
- **Description**: hint "Optional".
- **Value (₦)** (required, above 0; digits and "." only). Hint "Determines the procurement method", which changes to "Method: {…}" once a value is typed.
- **"Raise it"**: `POST /api/bff/api/v1/expenditure/requisitions` with body `{item, description, costCentre, value}`. X-Reason "Raise requisition for {item}". Message "Requisition {reference} raised".

---

## 17. Held scripts — `/finance/held-scripts`
Files: `page.tsx`, `HeldOwing.tsx`. This is a server component with no client state.

**Title.** "Held scripts" / "Students who sat a paper unregistered — the mark waits on their fees".

**`page.tsx`.** Loads `GET /api/v1/results/held/owing`. There is no office gating and the page has **no actions**.

**Tiles**
- **Students** (red when above 0) — "A script held, waiting on registration"
- **Scripts held** — "Marks not yet on any sheet"
- **Still owing**: ₦ — "{n} student(s) with a balance"
- **Closing within 14 days** — "Late registration closes; the script lapses"

**Info note** "What this list is": "Each of these students sat a paper they had not registered for, usually because fees were owing at registration. The lecturer held the script. The mark is released into the score sheet the moment the student pays, registers the course and the Head of Department approves the registration — nothing else is needed. After the semester's late-registration date the held script lapses and the result is lost. This is the most persuasive fees reminder the University can send."

**Panel "Students a held script is waiting on"** (header-right "{n} student(s)")
- Columns: Matriculation number, Name ("{level} level" underneath), Programme, Session, Courses held (pill "{n} script(s)" over the course codes), Closes, Due, Paid, Balance.
- Closes shows "no date set" when empty, and turns red and bold within 14 days.
- Balance is red and bold when above 0, green otherwise.
- Empty: "No script is held anywhere. When a lecturer holds one, the student appears here with what they owe." followed by a link "Fee setup" to `/finance/fees`.

There are no exports.

---

## 18. `lib/bursary.ts` and `lib/wallet.ts`

### `lib/bursary.ts` (34 lines)
**Exports**
- Types: `GatewayConfig`, `GatewayRow`, `GatewayEvent`, `Hanging`, `PaymentsDesk`, `PaydirectBiller`, `PaydirectCollection`, `PaydirectDesk`, `DayBookRow`, `BursaryView`, `BankCredit`.
- **`OUTCOME`** — gateway-event label and pill map:

| Code | Label | Pill |
|---|---|---|
| SETTLED | "Settled" | ok |
| ALREADY_SETTLED | "Already settled — no-op" | ok |
| UNKNOWN_REFERENCE | "Unknown reference" | bad |
| SHORT_PAID | "Short paid" | bad |
| NOT_SUCCESSFUL | "Not successful" | grey |
| IGNORED | "Ignored" | grey |
| BAD_SIGNATURE | "Bad signature — discarded" | bad |
| GATEWAY_ERROR | "Gateway did not answer" | bad |

- **`when(iso)`** — formats as "5 Mar, 14:02" (en-GB), or "—" when empty.

**Who imports it**
- Gateways: `page.tsx` and `Gateways.tsx` (`OUTCOME`, `when`, types).
- Hanging: `page.tsx` and `Hanging.tsx` (`OUTCOME`, `when`).
- Exceptions: `page.tsx` and `Exceptions.tsx` (types).
- Reconcile: `page.tsx` (`OUTCOME`, `when`, types) and `ReconcileLedger.tsx` (`when`).
- Ledger: `page.tsx` and `Ledger.tsx` (`when`, `DayBookRow`).
- `Payments.tsx` (`when`).
- `app/dashboards/Bursar.tsx` (`BursaryView`, `PaymentsDesk`, `when`). This is the only user of `BursaryView`.

### `lib/wallet.ts` (59 lines)
**Exports**
- Types: `WalletEntry`, `FundStatus`, `Eligibility`, `Withdrawal`, `StudentWallet`, `FundingSource`, `QueueWithdrawal`, `Batch`, `UnmatchedRow`, `NelfundDesk`, `FundingReport`.
- **`COVERS`** — a static list of what the wallet may pay (Tuition ✔, Approved user charges ✔, Accommodation ✘, Transcripts ✘, Late registration penalty ✘, Card replacement ✘). **It is not imported anywhere**, so it is dead code.
- **`parseRows(text, headers)`** — splits pasted CSV or tab-separated text into rows. It detects a header row by keyword match and otherwise maps columns by position.

**Who imports it**
- `parseRows`: `Nelfund.tsx` (remittance rows `["matric","name","amount"]`; decision list `["number","name","state","reason"]`) and `Gateways.tsx` (PayDirect `["prn","amount","rrn","paidat","channel","payer"]`).
- `FundingSource`: `sources/page.tsx`, `Sources.tsx`.
- `NelfundDesk` and `FundingReport`: `nelfund/page.tsx`, `Nelfund.tsx`.
- `FundingReport`: `app/reports/funding/view/page.tsx`.
- `StudentWallet`: `app/student/wallet/page.tsx` and `Wallet.tsx`.

---

## 19. Unfinished, hard-coded or inconsistent items

**Hard-coded values**
- Fee setup: session fallback `"2026/2027"` (`fees/page.tsx:18`).
- Gateways: the demo student `MOAUM/MTC/24/9903` is prefilled in the test form (`Gateways.tsx:25`).
- Exceptions: the "Cash ceiling" tile is fixed at ₦1,000 (`Exceptions.tsx:54`).
- Payments query: levels are fixed at 100–600 (`Payments.tsx:32`).

**Static text that does not come from the API**
- Menu badges in `menus.ts`: "7" on Hanging (`:544`), "12" on Reconciliation (`:560`, `:1218`), and "!" on Gateways and Payment Investigation.
- Page subtitles in `titles.ts`: "Unmatched settlement · teller slip BR/44821" on exceptions, and "Financial year 2026" on budget.

**Leftover placeholder**
- Tenders has an empty-label fourth tile (`Tenders.tsx:69`).

**Bugs**
- `ReconcileLedger.tsx:45`: the error toast fires on every successful load.
- `Hanging.tsx:74`: when "Resolve" fails, nothing is shown to the user.

**Fields in the code with no input on screen**
- Fee item `ord`.
- Accounting journal line `narration`.
- NELFUND Sources tab `note`.

**Contradictions**
- Transfer fee: a code comment says it defaults to ₦10,000; the on-screen copy says there is no default.
- Fee setup: editing a line keeps only the first ticked programme.
- Fee setup: the item modal offers two semesters, but the filter offers three.

**Missing success toasts**
- Applicant fee save and PG fee save (fee setup). The PG save also does not refresh the page.
- Payment history upload.
- Old fees history load.
- Fee-structure upload (it shows a note instead of a toast).

**Actions with no confirmation**
- "End" a fee line.
- Requisition Approve, Raise PO and Close.
- Withdrawal "Mark paid".
- Refund "Approve".

**Inconsistent role display**
- `RoleLine` shows only "Bursar" on pages where super, ict or admin can also act: payment history and funding sources. On fee setup and accounting it is Bursar or super.

**Duplicates and vocabulary mismatches**
- The Sources tab inside NELFUND duplicates `/finance/sources`, and its Code field is validated differently.
- Tender and requisition method codes do not match.

**Exports**
- Only the payments query uses `brandedXlsx` / `brandedPrint`.
- Fee setup uses plain `buildXlsx` and a hand-built print window.
- The ledger export is named `.csv` in code but downloads as a branded `.xlsx`.
- Templates: payment history, old fees and NELFUND remittance.
- No other page exports anything.


---

# Annex B — Screen-level audit of the student money, payroll/HR/staff, self-service and expenditure pages, and the `t/hrm` / `r/bursar` route ids

# Screen audit for the user manual: student money, HR/payroll, self-service, expenditure, and the `t/hrm` and `r/bursar` route ids

This is a read-only audit. I read every file listed, plus the components they import. Paths below are relative to `C:\Users\ajene\Documents\moaumpp\frontend\src\`. Line numbers are cited as `file:line`.

**How every screen gets its title.** Each page renders inside `components/proto/Shell.tsx`. The screen heading (`<h1>`) and subtitle come from `TITLES[route]`: first the `OVERRIDES` in `Shell.tsx:255-308`, otherwise `lib/titles.ts`. The breadcrumb comes from the acting office's menu group in `lib/menus.ts`.

**Shared behaviour on staff screens:**
- **Error toast:** `notifyProblem(problem)` plus an inline `<ProblemNotice>`.
- **Success toast:** in most HR/Finance screens it is the X-Reason text itself (`notify(reason)`).
- **Student screens:** they use `useAct()` from `app/student/common.tsx:11-42`.
  - Default success toast is **"Saved"**.
  - Error toast is `p.detail || p.title || "That did not go through"`.
  - It POSTs or PUTs to `/api/bff/api/v1{path}` with the header `X-Reason: reasonHeader(reason)`.
- **`reasonHeader`** (`lib/reason.ts`) makes the reason header-safe: "—" becomes " - " and "₦" becomes "NGN ".
- **Every data table is a `DTable`** (`components/proto/DTable.tsx`). The manual can say this once for all tables:
  - Above 8 rows it shows a search box, placeholder "Search these N rows…". With no match: "Nothing matches **q** in these N rows. Clear".
  - It pages in tens. Above 10 rows there is a "Rows" selector with 10/25/50/100/All.
  - The footer reads "Showing a–b of N" or "N rows".
  - A footer **"Print"** button prints the table in an iframe. The print is headed with the panel title and "Rev. Fr. Moses Orshio Adasu University, Makurdi · printed {date}" (`DTable.tsx:20-57, 224-229`).
  - No screen in this audit calls `brandedXlsx` or `brandedPrint`. The only Excel exports are the Staff register and the Non-Academic Staff template, noted below.
- **`RoleLine`** (`ui.tsx:217-240`) renders "**{action}** is/are worked by the {office names}." with a pill: "You may act — {office}" or "Signed in as {office} · view only".
- **No `page.tsx` below redirects or blocks by office.** Gating is done in the client (a `may` flag hides forms and buttons) and by the API: an error answer renders `ProblemNotice`.

---

## A. Student money screens

### A1. Fees & payments — `/student/fees` (route `s/fees`)

**Files:**
- `app/student/fees/page.tsx` (server).
- `FeesScreen` in `app/student/Screens2.tsx:19-119`.
- `PayByCard` in `app/student/common.tsx:77-162`.

**Title:** "Fees & payments". The subtitle is hard-coded **"2026/2027 session"** (`lib/titles.ts:106-109`).

**Server logic (`page.tsx`):**
- `loadStudent()` runs first. A non-student sees `ProblemNotice`.
- `?session=` is accepted only if it matches `/^\d{4}\/\d{4}$/`; otherwise the student's current session is used (`page.tsx:15`).
- When returning from a gateway with `?paid=<reference>`, the server first calls `POST /api/v1/payments/verify {reference}` with reason `Verify payment {ref}` (`page.tsx:17-19`). Then it fetches `GET /api/v1/me/fees?session=…`.

**Layout, top to bottom:**

1. **"Confirming your payment" card.** Shown only when `?paid=` names a reference that is still unconfirmed.
   - Text: "The gateway tells the University directly when the money lands, and this page updates itself. Reference {ref}."
   - Button **"Check again"** reloads the page (`Screens2.tsx:28-34`).
2. **Three tiles** (`Screens2.tsx:35-39`):
   - **Session charge.** Shows "—" when there is no charge. Caption: "{session} · {level} Level".
   - **Paid** (green). Caption is "Settled in full", "Instalment 1 of 2" or "Nothing yet". The "of 2" is fixed in code.
   - **Outstanding.** Red when above 0, otherwise green. Caption is "No charge stated yet", "Due this session" or "Cleared".
3. **Status note.** Exactly one of these (`Screens2.tsx:40-48`):
   - No charge: "No charge is stated for {session} yet" — "The Bursar states the session's fee schedule; your charge is computed from it the moment it is stated. Nothing is paid against a charge that does not exist."
   - Scheme problem: "What a payment releases is not yet stated", followed by the API text.
   - Clears registration: "Payment confirmed" — "Proceed and register your semester courses." When not paid in full it adds "{₦balance} of the session's charge still remains."
   - Otherwise (bad): "Course registration waits on this semester's school fees".
     - With arrears: "Arrears from an earlier session stand against you, and block everything while they do."
     - Without arrears: "Course registration for a semester opens once that semester's school fees are paid in full; the examination waits on the session paid in full."
4. **Panel "The charge"** (right side: the session). Table columns **Item | Amount**, with a final **Total** row.
5. **Panel "Pay"** (right side: "Against a reference this portal generates"). Shown only when a charge exists and the balance is above 0.
   - **If an unexpired, unconfirmed reference exists for this session:**
     - The eyebrow "Reference" and the reference in large type.
     - The line "{₦amount} · expires {date-time}. Quote this reference and nothing else: at a bank branch, by transfer, or by card below. The Bursary confirms it against the bank's record; a gateway confirms it the moment the money lands."
     - Then the `PayByCard` block.
   - **Otherwise, the instalment chooser** (`Screens2.tsx:66-98`):
     - If both semesters are outstanding: toggle buttons **"First semester · ₦x"** and **"Full session · both semesters · ₦balance"**.
     - If only the first semester is outstanding: **"First semester · ₦balance"**.
     - Otherwise: **"Second semester · ₦balance"**.
     - Helper text: "Pay this semester, or the whole session at once. Pick one, then generate the reference." When there is a single option: "Pay the outstanding school fees. Generate the reference, then pay against it."
     - Button **"Generate a reference for ₦{amount}"** (shows "Generating…" while busy). It calls `POST /me/fees/references {session, amount}` with X-Reason `Fee reference generated by the student for {session}`. The toast is "Saved".
6. **Panel "Payment History"** (right side: the count, or "none yet"). Columns: **Reference | Purpose | Amount | Status | (blank)**.
   - Purpose sub-line: "Confirmed {when} · {channel}" or "Generated {when}".
   - Status pills: **Paid** (ok), **Awaiting confirmation** (info, not yet expired), **Expired** (grey).
   - The last column has a **"Receipt"** link to `/student/receipt/{ref}` when a `receipt_no` exists.
   - Empty text: "Every payment against a reference this portal generated appears here, with its receipt. Nothing is released against a payment the bank has not confirmed."
7. **Session links.** Shown when there is more than one session: "Sessions with a charge: {links to ?session=…}".

**`PayByCard` (the gateway choice).** It is shared by Fees, Wallet top-up, Documents, Transcript and Transfer.
- **Initial button:** **"Pay ₦{amount} by card or USSD"** (shows "Opening the checkout…" while busy).
- **Gateway list:** `GET /api/bff/api/v1/payments/gateways` returns a `{gateway: bool}` map.
  - If more than one gateway is on, a row appears: "Pay ₦x with" plus one button per gateway and **"Cancel"**.
  - Gateway labels: `paystack`→"Paystack", `flutterwave`→"Flutterwave", `quickteller`→"Quickteller", `paydirect`→"Quickteller PayDirect" (`common.tsx:59`).
- **Checkout:** `POST /api/bff/api/v1/payments/checkout {reference, gateway?}` with X-Reason `Checkout opened for {reference}`.
  - On success the browser is sent to the returned `url`.
  - On error the title is "The checkout could not be opened ({error})" or "…(HTTP n)", with detail "Try again in a moment, or pay by transfer or at a branch against the reference." (`common.tsx:63-72`).
- **PayDirect response:** an info box titled "**Pay ₦x to {billerName} on Quickteller.**"
  - "Your Payment Reference Number (PRN) is **{prn}**…"
  - A list: Online (the pay link, or "Quickteller, biller code X"), USSD (the code), and "Any bank branch or ATM: quote biller code X and the PRN above."
  - Buttons **"I've paid — check now"** (`POST /payments/verify {reference: prn}`, X-Reason `Checked {prn}`) and **"Choose another way to pay"**.
  - If the payment is not yet confirmed: "Not confirmed yet. If you have just paid, it can take a few minutes to reach the University — wait a moment and check again." An outcome of `confirmed` or `already confirmed` reloads the page.

**Payments shown on the student dashboard** (`Screens1.tsx:149-192`, summary only):
- The note "What a payment releases is not yet stated for this session".
- "Action required", with buttons **"Pay now"** and **"See breakdown"**, both linking to `/student/fees`.
- A quick tile "Fees & payments": "₦x outstanding", "Fully paid" or "No charge stated yet".
- The dashboard has no inline checkout. `PayByCard` is also embedded in Documents (`student/documents/Documents.tsx:165,175`), Transcript (`Screens5.tsx:297`) and Transfer (`student/transfer/Transfer.tsx:95`).

### A2. Payment receipt — `/student/receipt/[reference]` (route `s/receipt`)

**Files:** `app/student/receipt/[reference]/page.tsx` and `ReceiptScreen` at `Screens2.tsx:121-176`.

**Title:** "Payment receipt" (no subtitle).

**Server logic:**
- Calls `GET /api/v1/me/fees/receipts/{ref}`.
- If the receipt is confirmed, it builds `verifyUrl = origin + /verify/receipt/{ref}?c={token}` and a QR PNG of that URL (`page.tsx:19-27`).
  - `token = SHA-256("{reference}|{receiptNo}")`, first 12 hex characters, upper-cased (`lib/qr.ts:13-20`).
- The passport photo comes from `/api/bff/api/v1/me/passport`.

**Screen:**
- **Unconfirmed:** the note "This payment is not confirmed yet" — "A receipt is issued the moment the Bursary or the gateway confirms it. Reference {ref}."
- **Confirmed:**
  - The note "Payment confirmed on {date}".
  - A document with the crest, "REV. FR. MOSES ORSHIO ADASU / UNIVERSITY, MAKURDI" and "Official Payment Receipt".
  - Key–value fields: **Receipt number**, **Date**, passport photo, **Received from**, **Matriculation number**, **Programme** ("{prog} · {level} Level"), **Session**, and **Semester** when present.
  - A table **Being payment for | Amount**. The purpose has any trailing "semester N" removed (`receiptPurpose`, `lib/student-portal.ts:110`), with the sub-line "Against reference {ref}". Then a **TOTAL RECEIVED** row.
  - **Channel** and **Gateway or teller reference**.
  - A **Verification** block: the receipt number and "Scan the QR code to verify this payment, or use the check code to confirm the authenticity of this receipt against the Bursary's ledger. Check code {token}.", followed by the verify URL as a link and a 108px QR captioned "SCAN TO VERIFY".
  - Buttons **"Download PDF"** (opens `/student/receipt/{ref}/pdf` in a new tab) and **"Back to payments"**.

### A3. Receipt PDF — `/student/receipt/[reference]/pdf` (`route.ts`)

- An unconfirmed receipt returns 409: "Not confirmed" — "A receipt is issued when the payment is confirmed." (`route.ts:28`).
- It is one A4 page. The header is the crest plus "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", with the subtitle **"Official Payment Receipt · Bursary Department"** (`route.ts:44`, `lib/pdf-crest.ts:24-36`).
- The passport JPEG sits top-right. If there is no photo, a box labelled "PHOTO" is drawn.
- Fields, in this order:
  1. RECEIPT NUMBER, DATE.
  2. RECEIVED FROM, MATRICULATION NUMBER, PROGRAMME ("{prog} · {level} Level"), SESSION, and SEMESTER when present.
  3. A dark band "BEING PAYMENT FOR / AMOUNT", then the purpose and "Against reference {ref}", with the amount as "NGN x.xx".
  4. TOTAL RECEIVED.
  5. CHANNEL and GATEWAY OR TELLER REFERENCE.
- **Verification:** a "SCAN TO VERIFY" block (`route.ts:84-106`).
  - The QR is drawn as squares and encodes the full `/verify/receipt/{ref}?c={token}` URL.
  - Text beside it: "Scan the QR code to verify this payment, or use the check code to confirm the authenticity of this receipt against the Bursary's ledger."
  - Then "Verify at {host}" and "Check code  {token}".
- **Anti-copy microtext band**, printed twice: " REV. FR. MOSES ORSHIO ADASU UNIVERSITY · OFFICIAL RECEIPT {no} · VERIFY ONLINE ·" repeated (`route.ts:109-111`).
- **Footer:** "Issued by the portal on {date} · {receipt no}".
- **Filename:** `receipt-{no with / replaced by -}.pdf`, served inline.

### A4. Public receipt verification — `/verify/receipt/[reference]?c=CODE`

**File:** `app/verify/receipt/[reference]/page.tsx`. Public, with no Shell.

- **API:** `GET /api/v1/verify/receipt/{ref}?c={code}`. Any error is treated as not genuine.
- **Card header:** the crest, "Rev. Fr. Moses Orshio Adasu University, Makurdi" and "**Receipt verification**".
- **Genuine:** "Genuine — this receipt is on the Bursary's ledger" — "Check that the payer, amount and date below match the receipt in hand."
  - The passport photo, if any, then a table: Received from, Matriculation number, Programme, Level (when present), Being payment for, Session, Semester (when present), Amount (bold, "NGN x.xx"), Channel, Confirmed on, Receipt number.
- **Not genuine:** "Not verified" — "No confirmed receipt matches this code. A receipt is real only if it appears here — check the reference, or treat it as not genuine."
- **Footer:** "This page reads the University's payment ledger directly; it is the record, and the printed receipt is only a view of it. Verified {today}."
- **Related public entry page `/verify`** (`app/verify/page.tsx`): "Verify a payment".
  - Fields: **Reference or receipt number** (placeholder "e.g. MOAUM-FEE-370000-6912 or RCT-2025-00001"; the button stays disabled while it is empty) and **Check code** (placeholder "e.g. 185A1F24C8C3").
  - Button **"Verify payment"**, plus a camera QR `Scanner`.

### A5. Wallet & funding — `/student/wallet` (route `s/wallet`)

**Files:** `page.tsx` and `Wallet.tsx`.

**Title:** "Wallet & funding" / "Loans, scholarships and other funding paid on your behalf". **API:** `GET /api/v1/me/wallet`.

**Layout:**
- **Tiles** (`Wallet.tsx:54-59`):
  - **Wallet balance.** Caption "Held by the University on your behalf" or "Fully applied".
  - **Funded.** Caption "Every source, added together".
  - **Applied to your invoices.** Caption "The session charge is settled" or "N instalment(s) counted".
  - **Outstanding on your account.** Red when above 0. Caption "For {session}" or "Nothing owing".
- **Funding by source.**
  - Eyebrow: "Funding by source — the wallet balance above is all of them together".
  - One tile per source: name, amount received, and "{Loan|Grant|Own money} · {CODE}". Sorted loans first (NELFUND first among them), then grants, then own money.
  - Empty: "No funding on your wallet yet" — "NELFUND, a scholarship or your own top-up will each show as its own card here, and the wallet balance is their total."
- **NELFUND status note** (`Wallet.tsx:75-79`):
  - APPROVED: "The Fund approved your NELFUND loan".
  - NOT_APPROVED: "The Fund did not approve your NELFUND loan", plus the reason and "This is a correction, not a judgement: fix the field named and the Fund reissues."
  - PENDING: "Your NELFUND application is still with the Fund" — "No decision yet — and that is a real answer, shown as one…"
- **Position note** (`Wallet.tsx:80-90`):
  - Wallet covers the debt: "Your wallet covers what you owe", with button **"Apply ₦{min(bal,owed)} to {session}"**.
    - Calls `POST /me/wallet/apply {session}`, X-Reason `Wallet applied to the session charge`.
    - Afterwards the note reads "₦x applied against {reference}" / "On the record; the receipt is on your Fees page."
  - Wallet does not cover it: "Your wallet does not cover the balance".
  - Wallet empty: "Nothing in the wallet yet".
  - Nothing owed: "Nothing outstanding".
- **Panel "Wallet statement"** ("Every movement, oldest first"). Columns: **Date | Entry | Source | Reference | In | Out | Balance**. Empty: "No movement on the wallet yet."
- **Panel "Top up the wallet"** ("When funding does not cover the whole fee"):
  - **Amount** field: digits and "." only. Hint: "A payment reference like any other; confirmed, it credits the wallet."
  - Button **"Generate the reference"** (disabled unless the amount is non-zero). Calls `POST /me/wallet/topup-reference {session, amount}`, X-Reason `Wallet top-up reference`.
    - The note then reads "Reference X generated — pay it by card below, or on the Fees page." The panel shows "Reference X for ₦y. Pay it by card or USSD; the moment the gateway confirms, your wallet is credited." followed by `PayByCard`.
  - Link button **"Fees & payments"**.
- **Panel "Withdraw to your bank account"** ("Once your fees are cleared"):
  - Existing-request note: REQUESTED "A withdrawal is with the Bursary"; APPROVED "Approved — awaiting payout"; PAID "Paid to your account"; REJECTED "The Bursary declined the withdrawal".
  - When eligible: "Your {session} fees are cleared and ₦x is left in the wallet. Enter **your own** bank account to withdraw it."
  - Fields:
    - **Amount**: digits/"." only; hint "Up to ₦x"; placeholder is the full balance. A blank amount means the full balance. There is no client-side check that the amount is at most the balance.
    - **Bank**: free text.
    - **Account number**: digits only.
    - **Account name**: free text.
  - Button **"Request the withdrawal"** (disabled until bank, account number and account name are filled). Calls `POST /me/wallet/withdrawal {session, amount, bank, accountNo, accountName}`, X-Reason `Withdrawal of {amt} requested`.
    - Confirmation note: "Withdrawal of ₦x requested — the Bursary will review it."
  - Not eligible: "Not available yet", followed by the API's reason.
- **Closing note** "What is a loan, and what is a gift": "A wallet credit is only repayable if its **source is a loan**…"

**Status vocabularies:**
- `KIND` (`Wallet.tsx:13`): CREDIT→"Credit", TOPUP→"Top-up", APPLIED→"Applied to fees", REVERSED→"Reversed to source", REFUND→"Withdrawn to bank".
- `NATURE` (`Wallet.tsx:14`): LOAN→"Loan", GRANT→"Grant", SELF→"Own money".

### A6. Identity card — `/student/idcard` (route `s/idcard`)

**Files:** `page.tsx` and `IdCard` at `Screens5.tsx:194-261`.

**Title:** "Identity card" / "Your student identity card". **API:** `GET /api/v1/me/id-card`.

- **Status note** (`Screens5.tsx:219-227`):
  - Live card: "Card {no} · issued {d} · valid to {d}" — "Collected at the Library…"
  - No matric number: "A card is made after matriculation".
  - Not cleared: "Your card waits on the Bursary's clearance" — "Under the scheme in force, the identity card is released at the first instalment.", with button **"Fees & payments"**.
  - Otherwise: "Your card has not been issued yet" — "…bring your fee receipt to the Library… The printable copy opens once the card is issued."
- **Panel "Your identity card"** (right side: "This is a picture of the card, not the card" or "Preview — not yet issued"). Shows the card front and back.
  - Helper text: "The barcode on the back is your borrower number… A field shown as "—" is one the University has not recorded against you."
- **Identity block:** passport photo, name, number/programme/level, and **Card number**, **Valid to**, **Faculty**, **Department**.
- **Actions, only when a card is live:**
  - **"Open the printable copy"**, which opens `/student/idcard/pdf`.
  - **"Report it lost"**: a `window.prompt` asks "What happened to the card? This goes on the record; the Library issues a replacement." It then calls `POST /me/id-card/lost {reason}`, X-Reason `Identity card reported lost: {reason}`.
  - **"Request a replacement"**, a link to `/student/support`.
- **Panel "Cards"** ("Every card ever issued to you"). Columns: **Card | Issued | Valid to | State**. State is "Live" for ISSUED, otherwise the capitalised state plus " · {ended_reason}". Empty: "None yet."

**Student ID card PDF** (`app/student/idcard/pdf/route.ts`):
- With no ISSUED card it returns 409: "No identity card issued" — "The Library prints your card after matriculation and clearance; there is nothing to print yet."
- The A4 page is headed "Rev. Fr. Moses Orshio Adasu University - Student Identity Card" and "A printed copy of your card. The card itself is issued by the Library."
- **FRONT** (landscape):
  - Header "REV. FR. MOSES ORSHIO ADASU UNIVERSITY" / "MAKURDI · BENUE STATE · NIGERIA".
  - The red "STUDENT" tag under the photo, the name in capitals and the matric number in red.
  - Fields: Faculty, Level, Programme, Blood group, Admitted (first 4 characters of the entry session), Graduates.
  - Foot: "Session {s} · valid to {d}", with the serial = card_no.
- **BACK** (`lib/idcard-pdf.ts:274-326`):
  - Strip "PROPERTY OF THE UNIVERSITY · NOT TRANSFERABLE".
  - Code-128 barcode of the matric number (alphanumerics only).
  - "CONDITIONS":
    - "This ID card must always be in the owner's possession for identification at the gates, examination or wherever identification is necessary."
    - "Any alteration or erasure renders this card invalid. Loss must be reported immediately to the Chief Security Officer of the University."
  - A QR encoding the plain text **`MOAUM ID {serial}`**. This is not a URL, and there is no ID-card verification page.
  - "In an emergency" followed by the student's `contact.reach_phone`, and a "Registrar" signature line.
- Footer: "{name} · {matric} · generated {date}". Filename: `identity-card-{matric}.pdf`.

---

## B. Payroll, HR and staff

### B1. Payroll — `/payroll` (route `t/payroll`)

**Files:** `page.tsx` and `Payroll.tsx`.

**Title:** "Payroll" / "Prepared, checked, then paid".

**Page:** reads `GET /api/v1/payroll/runs`, plus `GET /api/v1/payroll/runs/{id}` when `?run=` is given. It passes `actingOffice`.

**Gating:** `may = ["hrm","super"]` (`Payroll.tsx:40`). The RoleLine reads "**Building and approving payroll** is worked by the Director of Human Resource Management."

**Intro note** "A payroll is built by one officer and approved by another": "…the employee's 8% pension and PAYE after the consolidated relief. The officer who builds a run cannot approve it, and only an approved run is marked paid."

**Tiles:**
- **Runs** ("All months").
- **Awaiting approval** ("A second officer must agree").
- **Approved, to pay** ("Ready to disburse").
- **Last net paid** (the month, or "None yet").

**Panel "Build a run"** ("Over everyone active on the establishment"). Shown only if `may`.
- Fields: **Month** (`type=month`, required through the disabled button) and **Note** (hint "Optional", placeholder "Regular monthly salary").
- Button **"Build the run"**: `POST /payroll/runs {period, note}`, X-Reason `Build payroll for {period}`.
  - Confirmation note: "{n} payslips built — gross ₦x, net ₦y".
- Helper text: "A month is run once. If the establishment changes after a run is built, cancel it and build again."

**Panel "Pay runs"** (non-`may` users see "You are reading these runs").
- Columns: **Month | Staff | Gross | Deductions | Net | Stage | Action**. The Stage cell adds "Built by you|{name}" and any cancellation reason.
- Actions:
  - An eye icon views the run (`?run=`).
  - **Approve** (a DRAFT not built by me): `POST /runs/{id}/approve`, X-Reason `Approve payroll {Month YYYY}`. The note reads "{Month} approved".
  - A disabled **"Awaiting another approver"** on a DRAFT I built.
  - **Mark paid** (APPROVED): confirm "Mark {Month} paid? Record this once the salaries have been disbursed.", then `POST /runs/{id}/pay`, X-Reason `Payroll {Month} paid`.
  - **Cancel** (DRAFT or APPROVED): prompt "Why is this run cancelled? The reason is recorded.", then `POST /runs/{id}/cancel {why}`, X-Reason `Cancel payroll {Month}`.
- Empty: "No pay run yet. Build the first month above."

**Run detail panel "Payslips · {Month}"** (with a back button **"← All runs"**):
- Tiles: Staff (with the stage), Gross ("Basic and allowances"), Deductions ("Pension and PAYE"), Net ("To disburse").
- Table: **Staff | Grade | Basic | Allowances | Gross | Pension | PAYE | Net**. The grade cell shows "{grade} · {step}" and Academic/Non-academic.
- Empty: "This run has no payslips — no staff were active on the establishment when it was built."

**Status map `STATE`:** DRAFT→"Draft — awaiting approval", APPROVED→"Approved, to pay", PAID→"Paid", CANCELLED→"Cancelled".

**Exports:** only the DTable Print button. There is no payslip PDF and no bank schedule export.

### B2. Payroll variance — `/payroll/variance` (route `t/auditpayroll`)

**Files:** `page.tsx` and `Variance.tsx`.

**Title:** "Payroll variance" / "This run against the last, explained by staff movements".

**Page:** reads the runs and drops CANCELLED ones. `?period=YYYY-MM` defaults to the newest run. Then it calls `GET /api/v1/payroll/variance?period=`. There is no office gating (read-only).

**Layout:**
- **Note** "Every move in the total is explained by a move in the establishment": "…A change in the payroll total that no row here explains is the thing to ask about."
- **Filter:** **Month** select, one option per run (or "No runs yet"). Changing it navigates to `?period=`.
- **Tiles:** Joined ("New on the establishment"), Left ("Off the establishment"), Changed ("Net differs from last month"), Net change ("vs the month before {Month}").
- **Panel "What moved"** (right side: the month). Columns: **Staff | Grade | Movement | Last month | This month | Change**. SAME rows are hidden.
- **Empty:** "Nothing moved: the establishment is unchanged from the previous run, or there is no previous run to compare." With no month selected: "Select a month."

**Status map `KIND`:** JOINED→"Joined", LEFT→"Left", CHANGED→"Changed", SAME→"Unchanged".

### B3. Leave desk — `/hr/leave` (route `t/leave`)

**Files:** `page.tsx` and `LeaveDesk.tsx`.

**Title:** "Leave" / "Requests and balances". **API:** `GET /api/v1/hr/leave`.

**Gating:** `may = hrm, hod, dean, dregistrar, registrar, super` (`LeaveDesk.tsx:27`). Others see "You are reading this queue".

**Layout:**
- **Tiles:** Awaiting decision ("Requests to consider"), On leave today ("Approved and current"), Approved ("All time"), Requests ("All").
- **Segmented tabs, with counts:** Awaiting (REQUESTED, the default), Approved, Declined, All.
- **Panel "Leave requests":**
  - Columns: **Staff | Type | Period | Days | Cover | Stage | Action**. The type cell shows the staff member's note; the stage cell shows the decision note.
  - **Approve**: no confirmation. Calls `POST /hr/leave/{id}/decide {approve:true, note:null}`, X-Reason `Approve leave for {name}`. Toast and note: "{name}'s leave approved".
  - **Decline**: prompt "Why is it declined? The reason is recorded.", then the same endpoint with `{approve:false, note}`, X-Reason `Decline leave for {name}`.
  - Empty: "No request in this stage."
- **Footer note** "Annual leave draws down a yearly entitlement": "The balance is derived from what has been approved, never stored, so it cannot drift. Approving annual leave that would exceed the balance is refused by the database…"

**Status map:** REQUESTED→"Awaiting decision", APPROVED→"Approved", DECLINED→"Declined", CANCELLED→"Cancelled".

### B4. Appraisal & promotion — `/hr/appraisal` (route `t/appraisal`)

**Files:** `page.tsx` and `Appraisal.tsx`.

**Title:** "Appraisal & promotion". The subtitle is hard-coded "**2026 exercise**" (`titles.ts:641-644`). **API:** `GET /api/v1/hr/appraisal` returns `{cycle, rows}`.

**Gating:** `may = hrm, registrar, dean, hod, super`.

**Layout:**
- **Note** "Promotion eligibility is computed, not argued": "…the minimum three years on grade is checked from the record."
- **Tiles:** On the establishment ("Cycle {cycle}"), Meet the years rule ("≥ 3 years on grade"), Appraised this cycle ("{n} outstanding"), Academic ("Teaching staff").
- **Panel "Promotion candidates"** ("APER cycle {cycle}"):
  - Columns: **Staff | Grade | Years on grade | APER | Pubs | Eligibility**.
  - The APER pill is ok for A/B, info otherwise.
  - Eligibility shows "Meets the years rule" or "Short {x} yrs".
  - Empty: "No active staff on the establishment."
- **Panel "Record an appraisal"** ("APER grade, publications and the two scores"). Shown only if `may`.
  - Fields:
    - **Staff number**: placeholder "MOAUM/STAFF/001"; required through the disabled button.
    - **APER grade**: select with —/A/B/C/D/E.
    - **Publications**: hint "Accredited outlets"; digits only.
    - **Self score**: hint "0–100"; digits only, with no max enforced.
    - **Supervisor score**: hint "0–100"; digits only.
    - **Note**: optional.
  - Button **"Record the appraisal"**: `POST /hr/appraisal {number, cycle, aperGrade, publications, selfScore, supervisorScore, note, state:"MODERATED"}`, X-Reason `Record appraisal for {number}`. Toast: "Appraisal recorded for {number}".

### B5. Staff movements — `/hr/movements` (route `t/movement`)

**Files:** `page.tsx` and `Movements.tsx`.

**Title:** "Movement" / "Approved is not implemented until the letter exists". **API:** `GET /api/v1/hr/movements` returns `{rows, grades}`.

**Gating:**
- `mayOfficer = hrm, registrar, super`: can open movements and issue instruments.
- `mayApprove = hrm, registrar, dregistrar, vc, dvc, super`.

**Layout:**
- **Note** "Approved is not implemented until the instrument exists": "…Issuing the instrument is the act that changes the record from the effective date, and the portal refuses to write an office that cites no instrument."
- **Tiles:** Awaiting approval, Approved no letter ("Not yet real"), Implemented ("Instrument issued"), Movements.
- **Tabs:** Awaiting, To issue (APPROVED), Implemented, All.
- **Panel "Staff movements"** ("{n} shown"):
  - Columns: **Staff | Movement | What changes | Effective | Stage | Action**. The "What changes" cell adds the reason, "Instrument {no}" and the decision note.
  - **Approve**: `POST /hr/movements/{id}/approve`, X-Reason `Approve movement for {name}`. Note: "{name}'s movement approved — issue the instrument to make it real".
  - **Decline**: prompt "Why is it declined? The reason is recorded.", then `POST /{id}/decline {why}`.
  - **Issue instrument**: confirm "Issue the instrument for {name}? This changes the record from {date}.", then `POST /{id}/issue`. Note: "Instrument {instrument} issued — the record is changed".
  - Empty: "No movement in this stage."
- **Panel "Open a movement"** ("It goes to a second officer to approve"):
  - **Staff number**: placeholder "MOAUM/STAFF/016".
  - **Movement type**: select of 17 types — Appointment, Confirmation of appointment, Promotion, Upgrading, Conversion, Transfer, Secondment, Acting appointment, Redesignation, Leave of absence, Sabbatical, Suspension, Reinstatement, Retirement, Resignation, Disengagement, Dismissal. Default: Promotion.
  - **Effective from**: date.
  - For Promotion, Upgrading and Conversion: **New grade and step**, a select of "{grade} · step {n} (Academic|Non-academic)".
  - For other types: **What it changes**, placeholder "e.g. Confirmed to permanent appointment".
  - **Reason / minute**: optional.
  - Button **"Open the movement"**: disabled unless the staff number, date, and grade or what-changes are filled. Calls `POST /hr/movements {number, kind, effectiveDate, whatChanges, reason, newGrade, newStep}`, X-Reason `Open {Kind name} for {number}`. Note: "Movement opened — it goes to a second officer".

**Status map:** REQUESTED→"Requested", APPROVED→"Approved — instrument not issued", IMPLEMENTED→"Implemented", DECLINED→"Declined", RETURNED→"Returned".

### B6. Recruitment — `/hr/recruitment` (route `t/recruit`)

**Files:** `page.tsx` and `Recruitment.tsx`.

**Title:** "Recruitment". The subtitle is hard-coded "**2026 cycle**".

**APIs:** `GET /api/v1/hr/vacancies`, plus `GET /hr/vacancies/{id}/applicants` when `?vacancy=` is given.

**Gating:** `may = hrm, registrar, super`.

**List view:**
- **Tiles:** Open vacancies ("Advertised and live"), Applications ("Across all posts"), Shortlisted ("Meeting the criteria"), Posts.
- **Panel "Vacancies":**
  - Columns: **Post | Department | Applications | State | Action**.
    - Post sub-line: grade · Academic/Non-academic.
    - Applications: "n · m shortlisted".
    - State: shows "closes {date}".
  - **Open** goes to `?vacancy=`.
  - **State**: a free-text prompt "Set state: OPEN, SHORTLISTING, INTERVIEW, OFFER, CLOSED, CANCELLED", then `POST /hr/vacancies/{id}/state {state}`, X-Reason `Set {title} to {state}`.
  - Empty: "No vacancy advertised."
- **Panel "Advertise a vacancy"** ("The criteria here are what applications are scored against"):
  - **Post**: placeholder "Lecturer II — Computer Science".
  - **Department**.
  - **Advertised criteria**: textarea, placeholder "Ph.D required · CONUASS 03 · publications in accredited outlets".
  - **Grade**: optional, placeholder "CONUASS 3".
  - **Category**: —/Academic/Non-academic.
  - **Closes on**: optional date.
  - Button **"Advertise the post"**: requires title, department and criteria. Calls `POST /hr/vacancies`. Note: "Vacancy advertised".

**Vacancy view:**
- Button **"← All vacancies"**, then a panel titled with the post (right side: "{dept} · {grade}") showing "**Advertised criteria:** …".
- Candidates table: **Candidate | Qualification | Pubs | Teaching | Score | Stage | Action**.
  - **Score**: prompts "Score (0–100)" and "Recommendation (e.g. Invite, Reserve)", then `POST /hr/applicants/{id}/assess {score, recommendation}`.
  - **Shortlist**: `POST /hr/applicants/{id}/assess {state:"SHORTLISTED"}`.
  - Empty: "No application recorded for this post yet."
- **Panel "Record an application"** ("As received on paper or by e-mail"):
  - Fields: **Candidate name** (required); **Qualification** (placeholder "Ph.D Computer Science, 2023"); **E-mail**, **Phone**, **Publications** (digits only) and **Teaching years** (digits and "."), all optional.
  - Button **"Record the application"**: `POST /hr/vacancies/{id}/applicants`. Note: "Application recorded".

**Status maps:**
- Vacancy `VSTATE`: OPEN "Open", SHORTLISTING "Shortlisting", INTERVIEW "Interview", OFFER "Offer", CLOSED "Closed", CANCELLED "Cancelled".
- Applicant `ASTATE`: APPLIED "Applied", SHORTLISTED "Shortlisted", RESERVE "Reserve", REJECTED "Rejected", INVITED "Invited", OFFERED "Offered", DECLINED "Declined", APPOINTED "Appointed".

**Gaps:** the screen has no buttons for Invite, Offer, Reject or Appoint. Vacancy state changes are free-text prompts.

### B7. Staff records (establishment) — `/staff` (route `t/staff`)

**Files:** `page.tsx` and `Establishment.tsx`. Read-only for everyone.

**Title:** "Staff records" / "Establishment and appointments". **API:** `GET /api/v1/payroll/staff`.

**Layout:**
- **Tiles:** On the roll ("{n} active"), Academic ("Teaching staff"), Non-academic ("Administrative and technical"), Monthly gross ("Active establishment, before deductions").
- **Panel "Establishment"** ("{n} on the roll"). Columns: **Staff | Grade | Category | Monthly gross | Bank | Status**.
  - The name opens the staff modal (`StaffOpen`).
  - Bank shows "{bank} ····{last4}".
  - Empty: "No staff on the establishment yet."
- **Note** "The payroll is built over this roll": "…Appointments, promotions and endings are the Human Resource office's to record; the payroll reads what they set."

**Status map:** ACTIVE "Active", SUSPENDED "Suspended", ENDED "Ended".

### B8. Staff ID card PDF — `/staff/idcard/pdf[?id=]`

**File:** `app/staff/idcard/pdf/route.ts`.

- **Whose card:** without `?id` it is the signed-in person's own card (`/api/v1/hr/staff/me`). With `?id` it is that staff member's (`/hr/staff/{id}`), with an `X-Active-Office` cookie header for the photo.
- **No staff number:** returns 409 "No staff number" — "A staff identity card carries the staff number the Registry issued; this person has none on record yet."
- **Page heading:** "Rev. Fr. Moses Orshio Adasu University - Staff Identity Card". The sub-line is "A printed copy of your card. The card itself is issued by the Registry." for your own card, or "Printed for {name} by the office signed in." for someone else's.
- **FRONT** (portrait):
  - Header in two lines, "REV. FR. MOSES ORSHIO ADASU / UNIVERSITY", and the red "STAFF" tag.
  - Name "SURNAME, Given names", with the staff number in red.
  - Fields:
    - **Rank:** the rank in title case, or the office.
    - **Category:** "Academic", "Non-teaching" or "Staff".
    - **Department** (or **Unit** when there is no faculty).
    - **Faculty**.
    - **Appointed:** the first appointment date.
    - **Office:** the first live non-lecturer office.
  - Foot: "Valid to {31 December of current year + 3}". This date is computed, not stored.
  - Serial: `STF-{last 8 alphanumerics of staff no}-{current year}`. Also computed (`route.ts:57-59`).
- **BACK:** the same design as the student card. The barcode is the staff number, the QR text is `MOAUM ID {serial}`, and the aside reads "If found, return to the Security post / Km 1 Gboko Road, Makurdi".
- **Photo:** embedded only if JPEG. A PNG leaves the frame blank (comment at `route.ts:46`).
- **Filename:** `staff-id-{no}.pdf`. It is linked from `/me` as "My ID card (PDF)".

### B9. Audit — staff and payroll — `/audit/staff` (route `t/auditstaff`)

**Files:** `page.tsx` and `AuditStaff.tsx`. Read-only.

**Title:** from `titles.ts:429-432`, **"Staff movements" / "Seventeen HR processes, and what each does to the payroll"**. This does not match the content: the screen shows the roll and the pay runs, not movements.

**APIs:** `/payroll/staff` and `/payroll/runs`.

**Layout:**
- **Note** "The roll and the payroll, read together": "…a run whose total moves without a matching change on the roll is the thing to ask about."
- **Tiles:** On the establishment ("{n} on the roll"), Academic ("{n} non-academic"), Monthly gross, Last payroll paid ("{Month} · net").
- **Panel "Pay runs"** ("Each built by one officer, approved by another"). Columns: **Month | Staff | Gross | Deductions | Net | Stage | Approved by** (shows "Awaiting" on a DRAFT). Empty: "No pay run has been built yet."
- **Panel "Establishment"** ("{n} active"). Columns: **Staff | Grade | Category | Monthly gross | Status**. Empty: "No staff are on the establishment yet."

**Status map `RUNSTATE`:** DRAFT "Draft", APPROVED "Approved", PAID "Paid", CANCELLED "Cancelled".

### B10. Audit — assets register — `/audit/assets` (route `t/auditassets`)

**Files:** `page.tsx` and `AuditAssets.tsx`. Read-only.

**Title:** "Assets register" / "With the date each was last physically verified". **API:** `/api/v1/stores/assets`.

**Layout:**
- **Headline note:**
  - Bad: "{n} asset(s) not verified within the last year".
  - Ok: "Every live asset has been verified within the year".
  - Body: "The register is the Bursary's; audit reads it. What audit checks is not the value but the **verification date**…"
- **Tiles:** Assets on the register ("{n} disposed"), Book value ("Live assets with a recorded cost"), Never verified ("No physical check on record"), Overdue verification ("Last seen over a year ago").
- **Panel "Fixed-asset register".** Columns: **Tag | Asset | Location | Cost | Condition | Last verified**. "Never", or an overdue date, is shown in red.
  - Empty: "No asset is on the register yet. Assets appear here once the Bursary records them in Stores & assets."

**Status map `COND`:** GOOD "Good", FAIR "Fair", POOR "Poor", DISPOSED "Disposed".

### B11. Non-Academic Staff upload — `/people/staff` (route `t/staffupload`), brief

**File:** `NonAcademic.tsx`. **Title:** "Non-Academic Staff" / "The nominal roll loaded into the unit register; no sign-ins issued".

- **Gating:** `MAY = registrar, dregistrar, hrm, ict, admin, super`. The RoleLine names Registrar, Deputy Registrar, DHRM and Director of ICT. Other offices see "This desk is for the Registry, Human Resources and the Directorate of ICT" — "Your office may not load staff."
- **"Download Template"** creates `Non-academic staff template.xlsx` with columns PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONTISS, and two sample rows.
- **"Check a File (.xlsx)"** does a dry run. The file needs PNO, Full Names and Department columns; otherwise the error is "That file needs PNO, Full Names and Department columns."
- **Load:** "Load All N Rows" or "Load the N Placed Rows".
  - Both steps call `POST /iam/staff/import {rows, dryRun}` in chunks of 100.
  - X-Reason `{n} non-academic staff rows checked|uploaded`.
  - Toast: "{created} staff added · {existing} already on record".
- **Result tiles and note:** rows read/loaded, would be added/added, already on record, not placed, plus the spellings that could not be placed.
- **Panel "On record":**
  - Tab "Non-Academic Staff" has a search box ("Search name, staff id, unit or rank") and columns Staff id | Name | Placed in | As the roll spelt it | Rank | Scale | First appointed. It shows at most 500 rows.
  - Tab "The Unit Register" has columns Unit | Kind | Under | Campus | Staff | Spellings known.

### B12. Staff register — `/reports/staff` (route `t/regstaff`), brief

**Files:** `reports/staff/page.tsx` and `reports/RegisterDesk.tsx`.

- **Title:** "Staff register", or "Staff register · {scope}". Subtitle: "Every member of staff — filter by faculty, department, rank, category and status; search by name or number".
- **API:** `GET /api/v1/reports/registers/staff?…&page&size=100`.
- **Filters** (each defaults to "All"): Faculty, Department, Rank, Category, Status, Office held, and Search (placeholder "Name, staff number or email").
  - Buttons **Search** and **Clear filters**.
- **Exports:**
  - **"Download Excel (N rows)"**: every matched row, fetched 500 at a time. It is branded "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", titled "{title} — {filters} (N rows)", and named `staff-register-YYYY-MM-DD.xlsx`.
    - 16 columns: Staff no., Surname, Given names, Sex, Rank, CONUASS/CONTISS step, Category, Faculty, Department, Grade, Step, First appointment, Status, Offices held, Email, Phone.
  - **"Print / Save as PDF"** opens `/reports/staff/view?…`.
- **Tiles:** Matched, Academic ("n non-teaching"), Active ("in service"), Female / Male.
- **Table:** Staff no. | Name | Rank | Faculty / department | Category | Status | Offices held | Contact.
- **Empty:** "No member of staff on the register matches these filters. Clear one and search again."

---

## C. Self-service

### C1. Leave & Payslip — `/me` (route `r/self`)

**Files:** `me/page.tsx`, `Self.tsx` (a server component) and `LeaveSelf.tsx`.

**Title:** "Leave & payslip" / "You as an employee of the University".

**APIs:** `/iam/me`, `/staff/me`, `/me/payslips`, `/me/leave`.

**Tiles** (`Self.tsx:68-75`):
- **Leave taken.** Computed as `30 − balance`, a hard-coded 30-day entitlement. Caption "Annual, this year".
- **Leave remaining.** Caption "Annual entitlement".
- **Last payslip.** The net, with caption "{Month} · net", or "No payslip yet".
- **Appraisal.** Always "—", with the caption **"Staff module, not yet on the portal"**. This is static placeholder content.

**Panel "My record":**
- Buttons **"My ID card (PDF)"** (opens `/staff/idcard/pdf`) and **"Edit my profile"** (goes to `/me/profile`).
- Fields: **Staff number**, **Office**, **Unit**, **Appointment** (always "—"), **Grade** (from the latest payslip), **Next increment** (always "—").
- With no person record: "You are signed in, but the Registry has no record of you yet" — "…the name, the staff number and the offices below are empty rather than assumed."

**Panel "Payslips"** ("{n} months" or "None yet"):
- Columns: **Month | Gross | Pension | PAYE | Net | Stage**. Stage is "Paid" or "Approved".
- Empty: "No payslip yet" — "A payslip appears here once the Human Resource office has built and approved the month's payroll and you were on the establishment for it. A draft run is not shown — only an approved or paid one."
- There is no payslip PDF or download. Only the DTable Print button.

**Panel "Offices held"** ("Each under the instrument that granted it"):
- Columns: **Office | Scope | Instrument | From | Until**.
- Empty: "No office assignment is recorded against you" — "An office is held under a letter or a minute…"

**Leave panel (`LeaveSelf`):**
- **Not staff:** "Leave is for serving staff" — "Your record does not carry an active employment, so there is no leave to request…"
- **Otherwise, panel "Leave"** (right side: "Annual balance: {n} days"):
  - **Type**: select of "{name} (max {n}d[, unpaid])". Default ANNUAL.
  - **From** and **To**: dates, required through the disabled button. There is no client-side check that To is on or after From.
  - **Cover**: hint "Who takes your duties, if required".
  - **Note**: optional.
  - Button **"Request leave"**: `POST /me/leave {type, from, to, cover, note}`, X-Reason and toast `Request leave`. Note: "Your leave request is with your office." / "It waits for your office to decide."
  - History columns: **Type | Period | Days | Stage | Action**.
    - **Cancel** appears for REQUESTED or APPROVED requests: confirm "Cancel this leave request?", then `POST /me/leave/{id}/cancel`, X-Reason `Cancel my leave request`.
  - Empty: "You have made no leave request."
  - Status map: REQUESTED "Awaiting decision", APPROVED "Approved", DECLINED "Declined", CANCELLED "Cancelled".

**Footer note** "Leave that overlaps a teaching commitment needs a named replacement": "Name who will take your duties in the Cover field…"

**Stale comment:** the header comment in `Self.tsx:1-7` still says everything except the offices "belongs to a Staff module that is not on the portal yet". Payslips and leave are in fact live.

### C2. My Profile — `/me/profile` (route `t/myprofile`)

**Files:** `page.tsx` and `Profile.tsx`.

**Title:** "My Profile" / "Your record as the University holds it — and what you may change". **API:** `GET /api/v1/staff/profile`.

**Layout:**
- **Intro note** "This is your profile — yours to keep current": "…the publications, grants and postgraduates you record here are what the Faculty and the NUC see against your name."
- **Panel "Photograph"** ("A recent picture · JPEG or PNG, up to 2 MB"):
  - The button reads "Upload photograph", "Replace photograph" or "Uploading…".
  - Validation messages: "A photograph is a JPEG or PNG image." and "A photograph is up to 2 MB."
  - Upload: `PUT /staff/profile/photo {contentType, dataBase64}`, X-Reason `Staff photograph updated by the holder`.
  - Messages: "Photograph updated." on success, "The picture could not be read." on failure.
  - Default helper: "A head-and-shoulders photograph on a plain background."
  - The existing photo loads from `GET /staff/profile/photo`.
- **Panel "Who you are"** (right side: the staff number or "Signed in"). All free text:
  - **Email** ("The address the University writes to").
  - **Phone contact** ("How you are reached").
  - **Department**, **Faculty**.
  - **Current responsibility in the department**.
  - **ORCID** ("Your ORCID identifier, if you have one").
- **Panel "Research":**
  - **Google Scholar profile**: placeholder "https://scholar.google.com/citations?user=…".
  - **Areas of research interest**: textarea.
  - **Master's candidates graduated** and **PhD candidates graduated**: digits only; hint "How many you have supervised to completion".
- **Panel "Research output"**, one entry per line:
  - Publications ("One publication per line — a full citation on each").
  - Grants obtained ("One per line — the award, the funder and the year").
  - Patents ("…the title and the patent number").
  - Innovations.
- **Panel "Engagement and recognition":**
  - Research collaborations ("Local and international — one per line").
  - Conferences attended ("…the conference, the place and the year").
  - National and international assignments.
  - Achievements.
  - Contributions to society.
- **Save:**
  - Button **"Save profile"** ("Saving…" while busy): `PUT /staff/profile` with every field, the list fields sent as arrays. X-Reason `Staff profile updated by the holder`. Toast: "Profile updated".
  - Helper: "Every field is optional. What you leave blank is saved as empty, not guessed."
  - Saved note: "Your profile is saved" — "The record is updated against your account. You can come back and edit it any time."
- **Validation:** none beyond the photo checks. The email, ORCID and URL formats are not checked.

---

## D. Expenditure

### D1. Payment vouchers — `/vouchers` (route `t/pv` for the Bursar, `t/prepayment` for everyone else)

**Files:** `page.tsx` (route choice at line 12) and `Vouchers.tsx`.

**Title:**
- `t/pv`: "Payment voucher" / "Expenditure and Control".
- `t/prepayment`: "Payment vouchers" / "Pre-payment audit · Bursary raises, Audit clears, Bursary pays".

**API:** `GET /api/v1/expenditure/vouchers`.

**Gating:**
- `isBursar = bursar, super`.
- `isAudit = audit, deputyaudit, super`.

**Layout:**
- **Headline note:**
  - With open queries (bad): "{n} voucher(s) cannot move while a query stands".
  - Otherwise: "Every University payment passes Internal Audit before money moves".
  - Body: "A voucher advances one desk at a time: the Bursary raises it, the Director signs, the Deputy signs, an auditor attests, and it returns to the Bursary to pay… No person may act twice in its chain, however many offices they hold."
- **Tiles:** On the audit desk ("Awaiting a signature"), Queries open ("Payment blocked" or "Nothing outstanding"), Cleared to pay ("Back with the Bursary"), All ("Newest 300").
- **Button "+ Raise a voucher"** (Bursar only) opens the **modal "Raise a voucher"** (sub-line "It goes to Internal Audit before it can be paid"):
  - **What it is for**: placeholder "TetFund laboratory block — first certificate"; required.
  - **Payee**: required.
  - **Amount (₦)**: `inputMode=decimal`, not filtered; must be greater than 0.
  - **Kind**: Salary/Contract/Overhead/Claim/Grant. Default Contract.
  - **Source**: IGR/SUBVENTION/TETFUND/GRANT/OTHER. Default IGR.
  - **Cost centre**: optional.
  - Footer: **Cancel** and **"Raise it"**. The latter calls `POST /expenditure/vouchers {title, kind, source, costCentre, payee, amount}`, X-Reason `Raise voucher for {payee}`. Note: "Voucher {ref} raised — with the Director of Audit".
- **Panel "Payment vouchers"** ("Bursary raises → Director → Deputy → auditor → back to the Bursary"):
  - Columns: **Voucher | What it is | Amount | Stage | Action**. "What it is" shows "{Kind} · {source} · {payee}". Stage shows the rejection reason, or "{finding} → {office}".
  - Actions:
    - **Answer query** (any user, when a query is open): prompt "Answer the query. It is recorded and lets the voucher move again.", then `POST /vouchers/queries/{qid}/answer {answer}`.
    - **Sign & advance** (audit, audit stage, no open query, not already acted, not raised by me): prompt "A note on this signature (optional). Leave blank to just sign.", then `POST /{id}/advance {note}`, X-Reason `Advance {ref}`.
    - **Query** (audit): prompts "The finding (what is wrong or missing):" and "Sent to which office? e.g. Bursary, Works", then `POST /{id}/query {finding, sentTo}`.
    - **Reject** (audit): prompt "Reject this voucher. The reason is recorded.", then `POST /{id}/reject {why}`.
    - **Mark paid** (Bursar, CLEARED): confirm "Pay {ref} (₦x to {payee})? Record this once the money has left.", then `POST /{id}/pay`.
    - The text "You have acted on this one" appears when the user has already signed.
  - Empty: "No voucher has been raised. The Bursary raises one for a payment, and it passes Internal Audit before any money moves."

**Status map `STAGE`:** WITH_DIRECTOR "With the Director of Audit", WITH_DEPUTY "With the Deputy Director", WITH_AUDITOR "With the auditor", CLEARED "Cleared — to pay", PAID "Paid", REJECTED "Rejected". Any open query overrides the stage with **"Query open"**.

**Exports:** none beyond Print. There is no voucher PDF.

### D2. Stores & assets — `/stores` (route `t/stores`)

**Files:** `page.tsx` and `Stores.tsx`.

**Title:** "Stores & assets" / "Inventory and fixed assets". **APIs:** `/stores/items` and `/stores/assets`.

**Gating:** `may = bursar, super`. The **Verify** button is also available to audit and deputyaudit.

**Layout:**
- **Tiles:** Inventory items ("In stores"), Below reorder ("Need restocking"), Fixed assets ("On the register"), Not verified in a year ("Due a physical check").
- **Tabs:** "Inventory" and "Fixed assets", each with a count.
- **Inventory tab:**
  - **Panel "Inventory".** Columns: **Code | Item | Quantity | Reorder | Location | Action**. A "low" pill appears when an item is below its reorder level.
    - **Adjust**: prompt "Adjust {name} quantity by (e.g. 20 in, -5 out):", then `POST /stores/items/{id}/adjust {delta, note:null}`, X-Reason `Adjust {code}`. Note: "Stock adjusted". The input is not validated, so text becomes `NaN`.
    - Empty: "No inventory item recorded."
  - **Panel "Add an inventory item":**
    - Fields: **Code** (required), **Item** (required), **Unit** (hint "e.g. box, each"), **Opening quantity**, **Reorder level** (optional), **Location** (optional). Numeric fields accept digits and "." only.
    - Button **"Add the item"**: `POST /stores/items {code, name, unit, quantity, reorderLevel, location}`. Note: "Item added".
- **Fixed assets tab:**
  - **Panel "Fixed-asset register"** ("Each carries the date it was last verified"). Columns: **Tag | Asset | Location | Cost | Condition | Last verified | Action**.
    - **Verify**: `POST /stores/assets/{id}/verify`, X-Reason `Verify {tag}`. Note: "{tag} verified today".
    - **Condition**: free-text prompt "Condition: GOOD, FAIR, POOR, DISPOSED", then `POST /stores/assets/{id}/condition {condition}`.
    - Empty: "No asset on the register."
  - **Panel "Add a fixed asset":**
    - Fields: **Asset tag** (required), **Asset** (required), **Category**, **Location**, **Acquired on** (date), **Cost (₦)** (digits and "."). All but the first two are optional.
    - Button **"Add the asset"**: `POST /stores/assets`. Note: "Asset added".

**Status map `COND`:** GOOD "Good", FAIR "Fair", POOR "Poor", DISPOSED "Disposed".

---

## E. The route ids `t/hrm` and `r/bursar`

**What they are.** Both ids are the office's **home** item. They are not prototype screens.

- In `lib/menus.ts`:
  - `hrm` has `"home": "t/hrm"` (`menus.ts:251`), with the menu item `{ "id": "t/hrm", "icon": "user", "label": "Movements", "badge": "8" }` (`menus.ts:256`).
  - `bursar` has `"home": "r/bursar"` (`menus.ts:519`), with the item `{ "id": "r/bursar", "icon": "home", "label": "Dashboard" }` (`menus.ts:524`).
- Neither id is in `ROUTES` (`Shell.tsx:21-252`). That is why a URL table built from `ROUTES` would show "—" for them. `menus.md` is not in the repo, so I could not check how it was generated.
- The Shell resolves every menu item with `const href = (id: string) => (id === menu.home ? "/" : ROUTES[id]);` (`Shell.tsx:404`). The home id therefore links to **`/`**.
- `app/page.tsx` renders `<Shell route="r/academic" …>` and, by office:
  - `office === "bursar"` → `<BursarDashboard session={session} />` (`page.tsx:123-124`).
  - `office === "hrm"` → `<HrDashboard me={…} home={hr…} />` (`page.tsx:133-134`), fed by `GET /api/v1/hr/dashboard` (`page.tsx:87`).
- In the Shell, `route === "r/academic"` becomes the menu's home (`Shell.tsx:365`). So the heading comes from `titles.ts`:
  - `t/hrm` → **"Staff movements" / "Seventeen processes, one workflow — and the instrument every office cites"** (`titles.ts:360-363`). The menu label "Movements" and this title describe a movements screen, but the page actually shows the HR dashboard.
  - `r/bursar` → **"Bursary" / "Collection, payroll and the returns"** (`titles.ts:493-496`).
- A menu item with no route becomes a button. Clicking it shows the notice "{label} is still the prototype's screen" — "The portal is built screen by screen against the API and the database. Until this one arrives, it is the prototype's, exactly as designed." (`Shell.tsx:481, 540-555`). This does **not** apply to `t/hrm` or `r/bursar`, because they resolve to "/".

**HR dashboard** (`app/dashboards/Hr.tsx`). The data is live, not static.
- If the API fails: "The HR figures could not be read" — "The directorate's dashboard reads the HR module; it did not answer…"
- **Headline note:**
  - Pending leave: "{n} leave request(s) awaiting a decision", with button **"Open leave"**.
  - Otherwise, approved movements: "{n} movement(s) are approved, awaiting an instrument", with button **"Issue instruments"**.
  - Otherwise: "Nothing is waiting on the directorate", with button **"Movements"**.
- **Tiles, each a link:**
  - Staff on the establishment → `/reports/staff`.
  - Leave to decide → `/hr/leave`.
  - Instruments to issue → `/hr/movements`.
  - Open vacancies ("{n} shortlisted") → `/hr/recruitment`.
- **Panels:**
  - "Leave to decide": Staff | Type | Days | From. Empty: "No leave request is waiting. Staff apply from their own page; the request appears here to decide."
  - "Movements awaiting an instrument": Staff | Change | Effective.
  - "HR desks" ("Appraisal cycle {c} · {n} recorded"): links to Leave, Movements & instruments, Appraisal & promotion, Recruitment, "Payroll (n draft)" and **"Staff records" → `/people/lecturers`**. That last link goes to the lecturers page, not `/staff` (`Hr.tsx:79`).
  - Footer: "Latest pay run {period} — {state}, {n} staff, ₦x net." or "No pay run recorded yet."

**Bursar dashboard** (`app/dashboards/Bursar.tsx`). The data is live.
- **APIs:** `/finance/bursary?session=` and `/payments/bursary`.
- **Headline note:**
  - Exceptions open: "{n} settlement exception(s) are open", with buttons "Open the investigation" and "Reconciliation".
  - No scheme: "No clearance scheme is in force", with button "State the scheme".
  - Otherwise: "No settlement exception is open".
- `<StatsPanel>`.
- **Tiles:**
  - Collected this session.
  - Collected today ("{n} confirmation(s)").
  - Exceptions open ("{n} hanging at a gateway").
  - Gateways live (the list of "{gateway} ({mode})", or "None wired yet").
- **Panels:**
  - "Collection by faculty": Faculty | Collected | Students paid | Rate, with a bar.
  - "The desk": Item | Detail | Status. Rows: Fee schedule and scheme, References awaiting confirmation, Hanging at a gateway, Bank credits, NELFUND, Held scripts.
    - The **NELFUND** and **Held scripts** status pills are hard-coded as **"Open"**, not computed (`Bursar.tsx:54-55`).
  - The note "No academic transaction completes while money is owed".
  - "Recent confirmations": When | Payer | Purpose | Channel | Amount | Receipt, with button "Query all payments". Empty: "Nothing confirmed in the last seven days. The full ledger."

**Static menu badges.** `menus.ts` hard-codes badges, for example `"badge": "8"` on `t/hrm`, `"2"` on Leave Requests, and on the Bursar menu `"!"` (Payment Gateways, Payment Investigation), `"7"` (Hanging), `"1"` (Vouchers), `"3"` (Payroll), `"12"` (Reconciliation). **The Shell never renders `it.badge`.** It shows only `me.waiting[it.id]` from the API (`Shell.tsx:337, 471`), so these fixtures stay invisible.

---

## Unfinished, hard-coded or inconsistent items (for the manual's caveats)

1. **`/me`:**
   - The "Appraisal" tile is always "—" with "Staff module, not yet on the portal" (`Self.tsx:37,73`).
   - "Appointment" and "Next increment" are always "—" (`Self.tsx:87-89`).
   - "Leave taken" assumes a 30-day entitlement (`Self.tsx:62`).
   - The file's header comment is stale.
2. **Subtitles hard-coded in `titles.ts`:**
   - `s/fees` "2026/2027 session".
   - `t/recruit` "2026 cycle".
   - `t/appraisal` "2026 exercise".
   - `s/pay` "Instalment 2 · school fees". `s/pay` is routed but unused.
3. **Wrong titles:** `t/auditstaff` is titled "Staff movements", but the screen shows the roll and pay runs. `t/hrm` (the HR home) is also titled "Staff movements".
4. **Fees:** the Paid tile caption "Instalment 1 of 2" assumes exactly two instalments (`Screens2.tsx:37`).
5. **Student ID card:**
   - On screen and in the PDF, "Blood group" and "Graduates" are always "—". The screen also always shows "—" for the kin phone (`Screens5.tsx:210-213`, `idcard/pdf/route.ts:38-39`).
   - The on-screen QR is a fixed decorative mark (`components/proto/idcard.tsx:81-89`).
   - The PDF QR encodes only the text "MOAUM ID {serial}". There is no ID-card verification page.
6. **Staff ID card:**
   - The expiry (31 Dec of current year + 3) and the serial (`STF-…-{year}`) are computed at print time and are not stored.
   - A PNG photo prints blank.
7. **Prompt-based actions with free-text input:**
   - Recruitment: vacancy state and score. Only "Shortlist" exists as a button; there is no Invite, Offer or Appoint.
   - Stores: Adjust and Condition.
   - Vouchers: Query, Reject and Answer.
8. **Missing client-side validation:**
   - Wallet withdrawal: the amount is not checked against the balance.
   - Leave: To is not checked against From.
   - Appraisal: scores are not capped at 100.
   - Voucher amount: not filtered.
9. **No payslip PDF, voucher PDF or payroll export.** Only the generic DTable "Print".
10. **Dashboards:** the Bursar dashboard's NELFUND and Held-scripts pills are always "Open". The HR dashboard's "Staff records" goes to `/people/lecturers`.
11. **Static menu badges** in `menus.ts` are dead fixtures; they are never rendered.
