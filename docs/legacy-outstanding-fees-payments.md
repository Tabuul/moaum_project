# The old portal's OUTSTANDING FEES payments credited to the wallet (V631, 22 October 2026)

**Where:** Bursary → Legacy Financial Reconciliation (`/finance/legacy-reconciliation`), tab **Outstanding fees payments**; tiles on its
overview, on the Bursar's dashboard and on the Students Account Officer's dashboard.

## Why

The old portal took payments it filed as **OUTSTANDING FEES**: a student paying what the old portal said was still owed on a session.
The old-fees import brought each one in as `OUTSTANDING FEES (legacy) · semester N`, with its own reference ending `-OUTSTANDINGFEES`
and the old payment number kept. The portal counts as school fees only payments whose purpose begins "School fees", so these never
count towards a session's fees. MOAU/AD/BUS/25/12847, for one, paid ₦6,709 as OUTSTANDING FEES on 2025/2026 semester 2 and the portal
still showed ₦6,708.42 owed. On the live-shaped copy there are 1,193 such payments by 807 students, ₦59.8m, from 2012/2013 to 2026/2027.

The University asked for them to be listed apart, verified, and credited by the Bursar to the students' wallets for the students to use.
They are **not** turned into school fees: each payment stays as it was imported.

## The road to the wallet

1. **Listed.** Every such payment is one row. Each row shows:
   - the student and the session and semester;
   - the old payment number and the method the old portal recorded (Interswitch, E-Wallet and so on);
   - the student's school-fee position on that session today: due, paid as school fees, owed;
   - where the payment stands: **To verify**, **Returned to the officer**, **Verified · waiting for the Bursar**, **Credited to the wallet** or **Rejected**.
2. **Verified.** The Students Account Officer (or the Bursar) ticks payments, checks them against the records and verifies them. A window shows the payments, asks for remarks and needs the explicit confirmation. Nothing is credited at this stage. The Bursar's office holders are told what waits (`LEGACY_OUTSTANDING_WAITING`).
3. **Credited.** A Bursar officer **other than the one who verified** ticks the verified payments and credits them:
   - Each payment becomes one `CREDIT` on the student's wallet, for the payment's own amount.
   - The credit has source **LEGACY_OUTSTANDING**, the student's own money. It is applied to fees after a loan or a grant, and refunded as own money.
   - The credits go under a batch `LEGACY-OUTSTANDING/YYYY/NNNNNN`. A call that credits nothing uses no batch number.
   - The student is told the amount and the new balance (`LEGACY_OUTSTANDING_CREDITED`).
   - A payment is skipped, with the reason given, when it is:
     - not verified, or verified by the person crediting it;
     - changed since it was verified (amount, student or purpose);
     - on a merged or deceased student's record;
     - already credited.
4. **Used.** The student applies the credit to the session's fees from the wallet page, as any wallet credit. On the example, ₦6,708.42 is applied and the 2025/2026 school fees read fully paid, with ₦0.58 left on the wallet.

The Bursar can also act on a single payment, always giving a reason of ten characters or more:
- **reject** a payment not yet credited (the student is told, `LEGACY_OUTSTANDING_REJECTED`);
- **return** a verified payment to the officer (by an officer other than the verifier);
- **reopen** a rejected payment so the officer can verify it again.

The officer is told of a rejection or return (`LEGACY_OUTSTANDING_DECIDED`).

**On the ledger:** the credit is drawn from Opening balance / suspense (3900) into Student deposits & wallet (2100), as every old-portal credit is (V545, V583).

**Once only:**
- A payment carries at most one credit (`finance.legacy_outstanding_payment.wallet_entry_id` is unique).
- A credited payment is never decided again.
- A credited payment cannot be deleted: the old-fees reset keeps it, and any other delete is refused with `LEGACY_OUTSTANDING_CREDITED`.

## API

Readers: Bursar, Students Account Officer, Audit, Registrar, ICT and super. Verify: Bursar, Students Account Officer and super. Credit and decide: Bursar and super.

- `GET /api/v1/finance/legacy-reconciliation/outstanding-payments?status&session&q&fac&dept&student&limit`
  - Lists the payments. `status` takes `WAITING`, `RETURNED`, `VERIFIED`, `CREDITED`, `REJECTED`, or `TO_VERIFY` (waiting or returned).
- `POST …/outstanding-payments/verify` with `{ids, note, confirmed}`
  - `confirmed` must be true (`LEGACY_OUTSTANDING_CONFIRM`).
  - Returns `{verified, asked}`.
- `POST …/outstanding-payments/credit` with `{ids, note}`
  - Returns `{batch_ref, credited, amount, skipped, skipped_why}`.
- `POST …/outstanding-payments/{paymentId}/decide` with `{action: REJECT|RETURN|REOPEN, reason}`
- `GET …/figures` gains `outstandingPayments`, with these figures:
  - payments, students and amount;
  - waiting, returned, verified, credited and rejected;
  - the amount applied to fees and refunded;
  - totals by session, and the credit batches.

Database: `finance.legacy_outstanding_payment` (one row per payment acted on) and these functions: `finance.legacy_outstanding_payment_rows`, `_verify`, `_credit`, `_decide` and `_figures`.

## Tests

- **check.sql V631**, on a made-up student:
  - The OUTSTANDING FEES payments are listed and the school-fees one is not.
  - The Registrar is refused, and the officer verifies once.
  - The verifier cannot credit; another Bursar officer credits once, through 3900.
  - The credited payment can be neither deleted nor rejected.
  - The old-fees reset keeps the credited payment and removes the others.
- **`LegacyReconciliationIT.anOldPortalOutstandingFeesPaymentReachesTheWalletByTheOfficersVerificationAndAnotherBursarsCredit`**, through the API:
  - The payment is listed, and a student is refused.
  - The confirmation is required, and the Bursar is told.
  - The officer cannot credit, even as Bursar. A return needs a reason, and the officer is told and verifies again.
  - Another Bursar officer credits once, and the student is told. A second credit and a rejection are refused.
  - The student applies the credit and the session reads paid in full.
