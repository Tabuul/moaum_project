# The old portal's e-wallet reconciled (V583)

*20 Oct 2026.* **Bursary → Finance → Old E-Wallet Balances** (`/finance/legacy-wallet`; the Students Account Officer has it too,
Audit reads it). This is the final report the brief *Legacy financial migration, payment reallocation/swap & e-wallet
reconciliation* asked for. It is written against what the portal already had, which it reuses: nothing here is a second wallet,
a second ledger, a second payment system or a second swap.

## 1. What existed, and what the brief maps onto

| The brief asked for | Where it already is | Since |
|---|---|---|
| Legacy payment import, matching by strong identifiers, verification, reconciliation, duplicates, outstanding records, reset | the old-fees desk (**Old Fees History**): `finance.import_legacy_payments`, `finance.legacy_payref`, reconciliation, doubles, mislabelled items, payments never received, bank double charges | V498–V502, V561 |
| Misallocated payment → payment swap/reallocation: two officers, reason, evidence, timeline, reversal, both students told, report, old-portal payments included, no revenue change, the student record | **School Fees Payment Swaps** (`finance.payment_swap`, `SWAP/<year>/<n>`), `docs/school-fees-payment-swap.md` | V527 |
| A wallet ledger with sources, balances derived from entries, apply to fees (whole or part), top-up, refund, statement, the student's wallet page, posting on the general ledger | `finance.wallet_entry` (CREDIT, TOPUP, APPLIED, REVERSED, REFUND; by `funding_source`), `finance.apply_wallet`, `finance.wallet_statement`, `/student/wallet`, `docs/nelfund-wallet.md` | V033, V079, V327, V545 |
| Old-portal wallet funding imported once, matched, validated, queued for review | the old portal's NELFUND payments (`finance.legacy_nelfund_*`) | V327 |
| Student 360° finance: payments, swaps, wallet, refunds, receipts | the full record's Fees and payments tab | V578 |

What was missing, and what the live-shaped copy showed: the old-fees export had brought the old e-wallet in as plain payments —
2,992 **top-ups** (`E-WALLET TOP-UP (legacy)`, ₦73.8M, 2,885 students) and 8,667 **fees paid from the wallet** (method
`E-Wallet` on the note, ₦533M) — but nothing credited the wallet the portal keeps, so a student whose old wallet still held money
could not use it, and the top-ups were read as other income.

## 2. What V583 adds

**One row a student** (`finance.legacy_wallet`): the top-ups and what was paid from the old wallet, as the imported payments show
them; the old portal's own statement for the student where the Bursary holds one (it governs); the balance; the class; who
verified and who posted; the credit it became.

```
top-ups (purpose E-WALLET TOP-UP)  −  fees paid from the wallet (method E-Wallet)  =  balance
```

| Class | Meaning |
|---|---|
| COMPUTED | used ≤ top-ups and something left — for an officer to verify |
| VERIFIED | checked by the Students Account Officer or the Bursar — for another Bursar officer to post |
| POSTED | one `LEGACY_WALLET` credit stands on the wallet |
| NO_BALANCE | nothing left |
| REQUIRES_REVIEW | more was paid from the old wallet than the top-ups on file: the old wallet held money the export does not show (an earlier balance, a NELFUND credit); nothing is posted until the old portal's statement for the student is entered |
| REJECTED / FROZEN | the Bursar's decision, with a reason; reopened with one |

On the copy: 2,885 students; 1,811 with a balance (₦36.6M); 925 under review; the rest with nothing left. 6,041 other students
paid from the old wallet with no top-up on file — counted on the desk, never credited.

**The steps**
1. **Run the reconciliation** (`finance.legacy_wallet_compute`): set-based over the imported payments (0.4 s on the copy); run
   again at any time. A posted, rejected or frozen row keeps its state; a verified row whose figures changed goes back to
   COMPUTED and says so.
2. **Enter the old portal's statement** for a student where it differs (top-ups, used, refunds, reversals, balance, where it was
   read from): the balance then rests on it and the row is verified afresh (`finance.legacy_wallet_state`).
3. **Verify** (`finance.legacy_wallet_verify`): Students Account Officer or Bursar.
4. **Post** (`finance.legacy_wallet_post`): a Bursar officer other than the one who verified (the verifier is skipped and said).
   One CREDIT on the wallet, source `LEGACY_WALLET` (a funding source of the student's own nature), dated the last top-up,
   carrying the figures and the old reference, under a batch `LEGACY-WALLET/YYYY/NNNNNN`. Once only: the row, and a unique
   index on the credit. The student is told (`LEGACY_WALLET_POSTED`).
5. The student **applies it to the session's fees** on the wallet page, wholly or in part, exactly as any wallet money: one
   school-fees reference confirmed from the wallet (channel `NELFUND wallet`), the shortfall paid through the gateway. The fee
   position, the clearances and the examination card read it as paid.

**Reports.** Excel and PDF with S/N first (the brief's §54 columns); the figures; the batches. The full record's Fees and payments
tab shows the old wallet: topped up, paid from it, balance, posted, applied, left.

## 3. The ledger

A legacy-wallet credit is drawn from **3900 Opening balance / suspense** into **2100 Student deposits & wallet**, as V545 draws
every old-portal credit (`finance.gl_wallet_credit_account` now says so for the source as well). The top-ups' cash was booked
when the old payments were imported, so the Bursary settles 3900 from **Accounting → Wallet opening** (V552). Applying the credit
to fees posts Dr 2100 / Cr fee income — no new cash, as for every wallet application. The top-up purpose is now classed
`WALLET_TOP_UP` (a wallet deposit, as a gateway top-up is), so the payments reports no longer read it as other income.

## 4. Who may

| Office | May |
|---|---|
| Students Account Officer, Bursar | run the reconciliation, enter a statement, verify |
| Bursar | post (never what they verified themselves), reject, freeze, reopen |
| Audit, Registry, ICT, admin, super | read (V603: no longer the College's Finance Controller, whose office is held to the College) |

Every student named is held to the office's bound; the database holds every rule (`LEGACY_WALLET_OFFICE`, the two-officer check
constraint, the unique credit).

## 5. Tests

`LegacyWalletIT`; `lib/legacy-wallet.test.ts`; check.sql V583.
