# GST & EPS Legacy Payment Reconciliation (V323)

A verified GST payment made on the old portal is a real historical payment. This note records why the new
portal did not see it, where the old records are, how they are reconciled into the existing entitlement, what
was built, and what the reconciliation totals say.

## A. Root cause

1. **The entitlement reads one thing.** `finance.gst_entitlement(student, session)` (V314) answers PAID only
   from confirmed rows of `finance.payment_reference` whose purpose is `GST fee <session>` for that student and
   that session, net of approved or paid refunds. The registration gate (`registration.gst_gate`), the CBT
   eligibility (`assessment.cbt_eligibility`), the GST and EPS dashboards (`finance.gst_population`) and the
   student's screen all read the same answer. Nothing is cached: every read is live.
2. **The only door old-portal money had was the Old Fees History import** (`finance.import_legacy_payments`,
   V087/V304, Finance → Old Fees History). It records a row as **school fees** unless its Note or Purpose column
   names GST, and it matches a student by matriculation or admission number only. It knows nothing of
   transaction ids, gateway references, JAMB numbers, payment status or the GST fee of a session.
3. **The file the Bursary loaded carried school fees only.** On Railway (the reference data), the legacy
   import holds 67,490 rows for 16,406 students across 2023/2024, 2024/2025 and 2025/2026, all imported on
   15 September 2026; every one is "School fees (legacy) · semester 1/2"; no row names GST. No old-portal GST
   payment exists on the ledger at all, so no student can be entitled through one.
4. **The GST fee of the current session is not stated on Railway**, so there the 43,288 students required to
   take GST read "no fee stated" rather than NOT PAID; wherever the fee is stated (the AWS instance, or Railway
   once the Bursar states it), every one of them reads NOT PAID and is asked to pay again.

So: not a filter bug, not a session mix-up, not a cache. The old-portal GST payments were never brought into the
ledger, and the import that exists could not have brought them in correctly.

## B. Legacy payment source

| | |
|---|---|
| Source system | the old portal's payment export (Excel/CSV); its database is not reachable from the new portal |
| Payment identifier | the old portal's transaction id and/or its payment reference (RRR, order id, receipt) — a row needs one of them |
| Student identifier | matriculation number, JAMB number, application/admission number, the old portal's own student id, the name as typed |
| Payment reference | preserved as `source_reference`; gateway and gateway reference preserved too |
| Amount, currency | as exported (NGN) |
| Payment type | as exported (GST, GNS, General Studies, EPS, Entrepreneurship … mapped by `finance.legacy_payment_type_map`) |
| Session / semester | as exported, read as YYYY/YYYY (`finance.legacy_session_of`); never derived from the student's current level |
| Payment date | as exported, read day-first (`finance.legacy_date`); kept as the ledger row's `confirmed_at` |
| Status | as exported, read into SUCCESS / FAILED / REVERSED / REFUNDED / PENDING / UNKNOWN (`finance.legacy_status_of`) |

The whole exported row is kept as `raw` on the staged record.

## C. Design — what is reused, what is added

Reused, unchanged in meaning: the ledger `finance.payment_reference` (one row per payment, `channel` as the
payment source, `confirmed_at` as the payment date), the GST fee per session `finance.gst_fee` with its
level/entry-mode/faculty/programme scopes (the historical fee structure), `finance.gst_entitlement`, the gate,
the CBT eligibility, the dashboards, the refund table, the audit spine, `platform.next_number`, the branded
exports, the office RBAC. No second ledger, no flag on the student, no new payment attempt, no EPS payment.

Added (`db/V323__legacy_gst_payment_reconciliation.sql`), all keys UUIDs:

| Object | Role |
|---|---|
| `finance.legacy_gst_import` | one run: reference `GST-MIGRATION-<session>-<n>`, file, uploader, counts, STAGED → APPLIED |
| `finance.legacy_gst_payment` | the staged row as exported; **written once** (trigger); unique on (source system, transaction id) and (source system, reference) — the same old payment is never staged twice |
| `finance.legacy_gst_reconciliation` | the portal's judgement per row: status UNPROCESSED / MATCHED / RECONCILED / REQUIRES_REVIEW / REJECTED / DUPLICATE / UNMATCHED, reason code and text, the student and the match method and confidence, candidates, the fee of that session, the ledger row it became, who reconciled or resolved it and the override reason; audited |
| `finance.legacy_student_crosswalk` | old-portal student id → current student, set by the Bursary (also filled when an officer resolves a row by hand); audited |
| `finance.legacy_payment_type_map` | which old payment types are the GST fee (EPS types too: one GST payment covers both, `finance.gst_setting.covers_eps`) |
| `finance.gst_entitlement` | now also says `source` (CURRENT_PORTAL / LEGACY_PORTAL), `channel`, `legacy_reference` |
| `finance.gst_population` | now also says `pay_source` per student, for the dashboards' split |

### Matching (`finance.legacy_gst_match`, set-based)

In order: the current student id if the row carries one · the matriculation number · the JAMB number · the
admission/application number · the crosswalk for the old portal's own id. Exactly one student → MATCHED, HIGH.
More than one distinct student → REQUIRES_REVIEW (AMBIGUOUS_STUDENT) with the candidates. None → UNMATCHED
(STUDENT_NOT_FOUND); students sharing the whole name are attached as *suggestions* for the officer — a name
never matches.

### Validation (`finance.legacy_gst_validate_one`), in this order

| Finding | Status |
|---|---|
| status not SUCCESS (failed, reversed, refunded, pending, unknown) | REJECTED |
| payment type not mapped to the GST fee | REJECTED (UNKNOWN_PAYMENT_TYPE) |
| no session / session not on the calendar | REJECTED |
| no amount | REJECTED |
| a confirmed GST reference for the student and session already on the ledger (this portal's, or an earlier reconciliation) | DUPLICATE (EXISTING_ENTITLEMENT) — one entitlement stands, both histories kept |
| no GST fee stated for that session for that student | REQUIRES_REVIEW (NO_FEE_FOR_SESSION) |
| amount below / above the fee of **that** session (`finance.gst_fee_for(student, session)`) | REQUIRES_REVIEW (PARTIAL_PAYMENT / AMOUNT_ABOVE_FEE) |
| the same amount on the same day already on the ledger as old-portal school fees | REQUIRES_REVIEW (POSSIBLE_RELABEL) |

### Apply (`finance.legacy_gst_apply`)

Validated again at the moment of writing; then one set-based insert of confirmed `finance.payment_reference`
rows — purpose `GST fee <session>`, channel `Legacy`, reference `MOAUM-LEG-GST-<old id>`, receipt
`LEG-…`, `confirmed_at` = the old payment date, note naming the old reference, type, date and the run — linked
back by reference; a reference already on the ledger for another student or purpose becomes DUPLICATE
(REFERENCE_ON_LEDGER). Idempotent: a second apply writes nothing.

### The officer's hand (`finance.legacy_gst_resolve`)

MATCH to a verified student (refused when the row's own matriculation or JAMB number names somebody else —
ownership is never moved by guesswork; the old id goes on the crosswalk); RECONCILE (a review finding needs
the override reason, on the record); RELABEL (the old-portal school-fees row of the same amount becomes the
GST fee — one ledger row, not two); REJECT. Every action needs a reason and is audited in the officer's name.

### Dry run

`POST …/imports` with `dryRun: true` stages, matches and validates inside a transaction marked rollback-only:
the counts and the judged rows come back, nothing is kept.

## D. API (`/api/v1/finance/legacy-gst`)

| Method and path | Who | What |
|---|---|---|
| `GET /summary?session=` | viewers (Bursary, finance controller, audit, Registry, ICT, admin, super) | the figures, exceptions by category, by session, the fees stated, the runs |
| `POST /imports` `{rows, fileName, session, dryRun, note}` | Bursary / finance controller / super | stage + match + validate (or dry run) |
| `GET /imports`, `GET /imports/{id}?status=&q=&page=` | viewers | the runs; one run with its rows |
| `POST /imports/{id}/apply` | Bursary | onto the ledger |
| `GET /rows?importId=&status=&code=&session=&q=&page=` | viewers | search: legacy/transaction/gateway reference, matric, JAMB, application number, name, ledger reference, amount; status OPEN = review + unmatched |
| `GET /rows/{id}` | viewers | one payment, its raw row, the student's current standing, the ledger rows of that session |
| `POST /rows/{id}/{match\|reconcile\|relabel\|reject}` `{studentId, reason}` | Bursary | the officer's hand |
| `GET /students?q=` | Bursary | a student for a manual match |
| `GET /report?importId=&status=&session=` | viewers | the rows for the reconciliation and exception reports (exported branded, S/N first, names A–Z) |

Coded refusals: `LEGACY_REASON_REQUIRED`, `LEGACY_IDENTIFIER_CONFLICT`, `LEGACY_DUPLICATE`,
`LEGACY_NOT_SUCCESSFUL`, `LEGACY_ALREADY_RECONCILED`, `LEGACY_NOTHING_TO_RELABEL`, `LEGACY_STATE`.

## E. Screens

- Finance → **Old GST Payments** (`/finance/legacy-gst`): Overview (KPIs, the RECONCILIATION REQUIRED note
  while the variance stands, exceptions by category, counts that must agree, by session, the fees stated,
  the reports), Upload & apply (file → columns mapped by name → dry run or stage → counts and rows → apply),
  Exception queue and Search (filters, the row opened: raw row, candidates, student search, match / reconcile
  / relabel / reject with a reason), Imports.
- GST and EPS dashboards: paid in this portal vs the old portal, reconciled, not paid, requires review,
  unmatched, duplicates, variance, with a link to the desk.
- The student's GST & EPS: PAID with "Paid on the old portal", the old reference, the original payment date,
  the source, the session, GST and EPS registration available; no PAY GST FEE button.

## F. Security and audit

Only the Bursary (and the finance controller and the Super Administrator) stage, apply and resolve; viewers
are the finance, audit and registry offices; students never see the staged data. Every table is on the audit
spine; the staged row is immutable by trigger; every resolution carries the officer, the office, the time and
the reason; the ledger row names the run and the old reference, and the reconciliation row names the ledger
row — the question "which old-portal transaction entitled this student" has one answer.

## G. Tests

- `LegacyGstIT`: the brief's cases — the paid legacy student (NOT PAID before, PAID from the old portal after,
  with the old reference and date, not asked to pay again, the gate opens, EPS covered), failed and refunded
  rejected, the current-plus-legacy duplicate, the historical fee of last session validated against last
  session's fee, the partial payment reviewed then reconciled with an override, the ambiguous name left as
  suggestions, the unmatched row matched by hand after verification, the identifier guard, the wrong session
  rejected, the unknown type rejected, the same old payment twice in the file staged once, the dry run keeping
  nothing, apply idempotent, the CBT eligibility reading the reconciled payment, the dashboards' split, the
  relabel of the school-fees row (one ledger row, not two), the offices refused.
- `db/check.sql` 169–170: the same flow in SQL, rolled back.
- Frontend: the column-mapping library's node tests; type-check and lint.

## H. Reconciliation on the reference data — what can and cannot be claimed

The old portal's GST payment export has not yet been given to the portal. On Railway there are **0** staged
old-portal GST payments, **0** reconciled, and the GST fee of 2025/2026 is not stated. Until the Bursary (1)
states the GST fee of every session the old portal charged, (2) obtains the old portal's GST payment export
with transaction ids, references, identifiers, amounts, dates, sessions and statuses, (3) runs the dry run,
(4) stages, works the queue and applies, no student has been moved from NOT PAID to PAID, and this note does
not claim otherwise. The desk reports the counts, the amounts and the variance for that run the moment it
is made; the migration is complete only when the variance is explained row by row.
