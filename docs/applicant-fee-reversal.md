# An applicant fee confirmed in error (V420)

A bank payment confirmed against the wrong applicant's reference is reversed by the **Bursary** on **Payment Investigation**
(`/finance/exceptions`): look the reference up, read what it is and whether it may be reversed, give the reason, reverse.
It applies to every applicant fee — application, admission checking and acceptance — of Post-UTME, Direct Entry, transfer
and CCE applicants (`admissions.fee_reference`). Postgraduate and JUPEB fees have references of their own and are not
covered here.

**What may be reversed.** Only a confirmation made by hand. A payment the gateway settled (a `finance.gateway_event` with
outcome SETTLED or ALREADY_SETTLED for the reference) is money that reached the University on that reference: it is
refunded on *Refunds & Credits*, never reversed (`FEE_REVERSAL_GATEWAY`). And only while nothing has been done on it: an
application fee once the application was submitted, a checking fee once the admission status was read, an acceptance fee
once the offer was accepted, cannot be reversed (`FEE_REVERSAL_IN_USE`). The Bursar (or super) reverses, with a reason of
ten characters at least (`FEE_REVERSAL_OFFICE`, `FEE_REVERSAL_REASON`); an unknown reference is `FEE_REVERSAL_UNKNOWN`.

**What a reversal does** (`admissions.reverse_fee_confirmation`, in one transaction):

- keeps the reversal in `admissions.fee_reversal` — the reference, the kind and amount, who confirmed it and when, the channel
  and the receipt number, who reversed it, when and why, and the general-ledger reversal;
- takes the confirmation and the receipt number off the reference and stops it being paid (the applicant generates a new
  reference; a receipt already sent no longer verifies);
- clears the application's mark for that fee, unless another reference of the same kind stands confirmed — so a CCE
  applicant's form closes again until the fee is paid (V404);
- reverses the payment's general-ledger journal where the ledger sync had posted it (`finance.gl_reverse`);
- tells the applicant by email and SMS that the payment was recorded in error and the fee is still owed.

**API.** `GET /api/v1/admissions/fee-references/{reference}` (what it is, `reversible`, `why_not`, earlier reversals),
`POST /api/v1/admissions/fee-references/{reference}/reverse` `{reason}`, `GET /api/v1/admissions/fee-references/reversals`
(the latest hundred) — the Bursar and super only.

**Tests.** check.sql — the V420 property; `CceIT` (a CCE application fee reversed through the API, the form shut again,
paid again).
