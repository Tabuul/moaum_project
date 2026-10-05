# The funding wallet by source: NELFUND, conditional top-up, refunds, old-portal payments (V327)

This is the final report the enhancement brief asked for. It is written against what the portal already had, which
it reuses; nothing here is a second wallet, a second ledger, a second school-fee engine or a second refund system.

## 1. What existed

| Concern | Where | Since |
|---|---|---|
| The wallet ledger | `finance.wallet_entry` — append-only; kinds CREDIT, TOPUP, APPLIED, REVERSED, REFUND; balance derived by `finance.wallet_balance` | V033 |
| Funding sources | `finance.funding_source` (NELFUND a LOAN, SCHOLARSHIP a GRANT, SELF the student's own money); every credit carries `source_code` | V079 |
| NELFUND remittances | `finance.nelfund_batch` / `finance.nelfund_row` — split against the register by matriculation number; suspense is owned; reversal to the Fund | V033 |
| The Fund's decisions | `finance.nelfund_status` (APPROVED, NOT_APPROVED, PENDING) | V033 |
| School-fee obligation | `finance.charges(student, session)` from the fee schedule; `finance.position(student, session)` = due, paid, balance, paid in full, arrears | V026/V027 |
| Applying the wallet | `finance.apply_wallet` → one school-fees reference, confirmed through `finance.confirm_payment` (channel "NELFUND wallet") | V033 |
| Top-up | `finance.wallet_topup_reference` → a purpose reference; the gateway's confirmation credits TOPUP (SELF) | V033 |
| Refund to the student | `finance.wallet_withdrawal`: requested by the student, approved by the Bursary, paid by a second officer; a REFUND entry | V079 |
| Bursary refunds against a transaction | `finance.refund` (maker–checker), `/finance/refunds` | V043/V067 |
| Gateways and webhooks | `finance.payment_reference`, `finance.gateway_event`, `PaymentsService` (an expired or already-confirmed reference is refused) | V026/V037 |
| Notifications, audit, numbers | `platform.queue_notice`, the audit spine (`audit.attach`), `platform.next_number` | — |
| Old-portal reconciliation pattern | V323: staged once, matched by identifiers, validated, applied on the Bursary's word, exceptions queued | V323 |

What it could not do: the balance was one pool. Applying it and refunding it took no notice of the source, so a
scholarship could have left the University as a "refund", a top-up could have been counted as the Fund's money, and a
student could top the wallet up for no reason at all. There was no door for the old portal's NELFUND payments.

## 2. What changed (V327)

### Balances by source
`finance.wallet_balances(student)` and `finance.wallet_balances_session(student, session)`: per source — credited,
applied, reversed, refunded, held for a pending refund, available. A credit written without a source (before V327)
reads as UNATTRIBUTED: it may be applied to fees, last; it is never refunded. The pooled `finance.wallet_balance`
remains as the sum.

### The funding waterfall
`finance.apply_wallet` settles the charge source by source in the order the policy states — loan, grant, own money
by default — writing one APPLIED entry per source consumed with its `source_code`, one payment reference, one
confirmation; the split is on the note. Every naira that paid a fee is traceable to where it came from.

### The conditional top-up
`finance.topup_eligibility(student, session)` answers: due, paid, outstanding, wallet available (and by source), the
exact shortfall, the maximum top-up, the school-fees window, and one reason when a top-up is not allowed:

| reason | meaning |
|---|---|
| `NO_CHARGE_STATED` | no fee schedule for the session |
| `FEES_SETTLED` | nothing outstanding |
| `NO_SHORTFALL` | the wallet covers what is outstanding — apply it |
| `WINDOW_CLOSED` | school-fees payment is not open (V288 window) |
| `STUDENT_INACTIVE` | not in study |
| `ALLOWED` | a top-up for exactly the shortfall |

`finance.wallet_topup_reference` is the only door: under a per-student advisory lock it recomputes the eligibility,
refuses `WALLET_TOPUP_NOT_REQUIRED` and `WALLET_TOPUP_ABOVE_SHORTFALL` (unless the policy allows more), expires any
earlier unpaid top-up reference for the session, and writes the calculation on the reference's note ("Shortfall
top-up: fees …, paid …, NELFUND available …, other …, own …, outstanding …, shortfall …, top-up …"). The gateway's
confirmation credits the wallet as SELF, never as NELFUND. The screen hides the button; the server enforces it.

### Refunds
`finance.withdrawal_eligibility(student, session)` is session-aware and by source: NELFUND refundable (the Fund's
money of that session left after the fees are settled), own money refundable, grant held (never refundable),
`nelfund_after_settlement` (the fees were settled by other means and nothing of the Fund's money was applied).
`finance.request_withdrawal(…, source)` requests a refund of ONE source up to its refundable amount
(`WALLET_REFUND_SOURCE`, `WALLET_REFUND_ABOVE_REFUNDABLE`); the requester cannot approve; the approver cannot pay;
approval re-checks the money and the clearance; payment debits that source. Statuses stay the portal's: REQUESTED,
APPROVED, REJECTED, PAID. The student is told at each step. The Bursary's own refunds against a transaction are
unchanged.

### Hand credits
`finance.credit_wallet` requires a source (`WALLET_SOURCE_REQUIRED`). A credit of unknown source is never written.

### The old portal's NELFUND payments
`finance.legacy_nelfund_import` / `legacy_nelfund_payment` (written once; unique on the old reference and transaction
id) / `legacy_nelfund_reconciliation`. `legacy_nelfund_stage` keeps every row as the file gives it (session from the
row, else the session its date falls in; never the current session by default); `legacy_nelfund_match` by the
current student id, matriculation number, JAMB number, application number, the crosswalk — never a name (a name is a
suggestion for an officer); `legacy_nelfund_validate` rejects anything but a successful payment of an amount for a
session and marks a payment already on a wallet DUPLICATE; `legacy_nelfund_apply` posts each MATCHED row as one
NELFUND credit for its session, dated when it was paid, with the old reference on it and `legacy_payment_id` set — a
unique index makes posting idempotent; `legacy_nelfund_resolve` lets an officer match on evidence (never past the
row's identifiers: `LEGACY_IDENTIFIER_CONFLICT`) or reject. Statuses: UNPROCESSED, MATCHED, POSTED, REQUIRES_REVIEW,
UNMATCHED, DUPLICATE, REJECTED.

### The Bursary's questions
`finance.nelfund_desk_figures(session)` and `finance.nelfund_student_rows(session, q, filter)` over the funded
population: received, students funded, applied, remaining, refundable, refunds by state, old-portal money posted or
waiting, students with a shortfall and the amount, who may top up, who paid before the Fund arrived. Filters: ALL,
SHORTFALL, TOPUP, REFUNDABLE, PAID_BEFORE_FUND, REFUND_PENDING, LEGACY, OUTSTANDING.

### Policy
`finance.wallet_setting` (one row): `apply_order` (LOAN, GRANT, SELF), `topup_over_shortfall` (false),
`refund_natures` (LOAN, SELF — never GRANT). Set by the Bursar on the desk's Overview tab.

## 3. API

| Endpoint | Who | What |
|---|---|---|
| `GET /api/v1/me/wallet` | the student | balance, statement (with origin and the old reference), position, status, eligibility (by source), `balances`, `sessionBalances`, `topup` |
| `POST /api/v1/me/wallet/topup-reference` | the student | a reference for the shortfall only; 422 otherwise |
| `POST /api/v1/me/wallet/apply` | the student | the wallet applied, source by source |
| `POST /api/v1/me/wallet/withdrawal` | the student | a refund request of one source (`source`), capped |
| `GET /api/v1/nelfund/figures?session=` | readers | the figures and the policy |
| `GET /api/v1/nelfund/students?session=&filter=&q=&page=&size=` | readers | the funded population, paged |
| `GET` / `PUT /api/v1/nelfund/policy` | readers / Bursar | the policy |
| `POST /api/v1/nelfund/legacy/imports` (`dryRun`) · `GET /imports` · `GET /imports/{id}` · `POST /imports/{id}/apply` | Bursary | the old-portal run |
| `GET /api/v1/nelfund/legacy/rows` · `GET /rows/{id}` · `POST /rows/{id}/{match\|reject}` · `GET /students?q=` | Bursary (readers for GET) | the queue and the officer's hand |

Unchanged: remittance batches, suspense match/reverse, the Fund's decisions, the Bursary's hand credit (now with a
required source), the withdrawal queue (approve/reject/pay), sources, the funding report.

## 4. Screens

- **Student → Wallet & Funding**: NELFUND available / used / reserved / refundable; each grant and the student's own
  money; school fees, paid, outstanding, NELFUND shortfall; "Additional payment required" with the calculation and
  TOP UP ₦X only when allowed, otherwise the reason; "NELFUND funds received after your school fees were already
  paid" and APPLY FOR REFUND capped at the refundable amount of the chosen source; where the funding stands by
  source; the statement with the origin of each credit (the Fund's remittance, the old portal with its reference and
  date, the Bursary, the gateway); a branded printable funding statement.
- **Finance → Sources & Wallets**: new tabs Overview (figures, the questions answered, the policy), Students (the
  funded population with filters, search, paging and Excel), Old portal (upload, mapping, dry run, stage, post, the
  exception queue, search, imports). The menu entry "Old NELFUND Payments" opens the last. Withdrawals are labelled
  Refunds and show their source.

## 5. Security and audit
Students reach only `/api/v1/me/...`, which reads the token's subject; the Bursary's desk and the import are
`OFFICE_bursar` (readers for the figures). All five new tables are on the audit spine; the staged payment is written
once (`LEGACY_PAYMENT_WRITTEN_ONCE`); every refusal names its code; concurrent requests are serialised per student by
an advisory lock inside the transaction. Bank details are snapshotted on the request as before; the student sees only
their own.

## 6. Tests
- `db/check.sql` properties 174 (the wallet by source, the top-up refused above the shortfall and when nothing is
  short, the earlier reference retired, the charge settled loan-then-own on separate entries, a credit of no source
  refused, a refund of the Fund's money that arrived after the fees were paid and never of the scholarship) and 175
  (old-portal payments staged once, matched by identifiers never by name, a failed payment never credited, the session
  read from the row or its date and kept, posting once, the officer's hand bounded by the identifiers).
- `NelfundWalletIT`: the same over the API, plus a student refused a wallet credit and the desk, a dry run that
  writes nothing, and a second upload that stages nothing.

The brief's twenty cases map onto these: 1–4 and 13–14 (property 174, IT 1), 5–7 and 15–16 (property 174, IT 2),
8–12 and 19 (property 175, IT 3), 17–18 (IT 1 and 3), 20 (the gateway's own idempotency, unchanged: a reference
already confirmed is answered "already confirmed").

## 7. Assumptions the University should confirm
- The default waterfall is loan first, then grants, then the student's own money. The Bursar can reorder it.
- A top-up may not exceed the shortfall unless the Bursar switches the policy.
- A refund is of NELFUND money and the student's own leftover; a scholarship or sponsor's grant is never refunded to
  the student through the wallet.
- A payment with no session and no date that falls in a session is rejected until an officer resolves it.
- Credits written before V327 without a source remain unattributed: applied last, never refunded, until the Bursary
  re-states them (reset the wallet and credit it again with its source).
