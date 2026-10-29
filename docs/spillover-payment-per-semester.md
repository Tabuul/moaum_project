# A spillover payment made for a semester pays that semester only (V697)

The University's word of 29 October 2026:

> SPILL OVER STUDENTS WHO ARE TO PAY FOR SECOND SEMESTER SPILL TWO IS SHOWING THEY ALREADY PAID FROM THE LEGACY DATA, THIS IS
> WRONG, CHECK THE SESSION THEY PAID AND THE CURRENT AND RECONCILE THIS … THIS WAS LAST SESSION SPILL ONE SECOND SEMESTER, PAYMENT
> IT SHOULD NOT BE APPLIED TO SECOND SEMESTER SPILL TWO

## What happened

* **Per-semester charging (V616).** A spillover student pays a semester's spillover fee only for a semester they register a
  course in.
* **Payments applied in order (V664).** The session's school-fee payments go to the whole-session item first, then the first
  semester, then the second.
* **The gap.** Spillover students who took and paid the first semester on the old portal have that payment on the Old Fees
  History, labelled "School fees (legacy) · semester 1". They have no registration of it on this portal, so the first semester
  was not charged. Its payment went to the second semester instead, which then read **paid** although nothing had been paid
  for it.
* **Example.** A B.A. History student in spillover year 2 paid ₦52,150 for the first semester of 2025/2026 on the old portal. That
  covered the second semester's ₦22,350. The session read overpaid by ₦29,800, and the overpaid desk listed the money to carry
  or refund.

**Payments are counted by the session they were made for.** Every reader (the registration gate, the semester status, the
position, the spillover panel) takes only the session's own payments. So last session's spill-one second-semester payment
(₦22,350 for 2024/2025) is not counted in 2025/2026. What covered the second semester of spill two was this session's
first-semester payment.

**On the copy of 21 October 2026** (before the 2025/2026 portal registrations):
* 1,046 spillover students had paid a named semester of 2025/2026 with no course of it registered on the portal.
* 741 of them read as overpaid.

## The rule

A semester the student paid school fees for in the session is **charged as one registered**. The payment names the semester:
the old portal's "· semester 1", or a spillover reference's "first semester" (`finance.purpose_semester`, V649).
* `finance.reg_semesters` and `finance.fee_profiles` read it, so every charge, position, gate, list and report follows.
* The semester's payment pays it.
* The second semester is owed until it is paid itself. Its registration is held (REG_SEMESTER_FEES_DUE) with the amount, and
  the student's spillover card says "Payment required".
* Nothing reads as overpaid that way any more.

**Unchanged:**
* A payment made for the whole session, or for both semesters, is applied in order, as before.
* A payment is counted only in the session it was made for, as before.
* A semester charged this way at its spillover line, where less was paid on the old portal than the line, owes the rest. That is
  what it would owe once registered here. On the copy, 12 students paid ₦34,900–₦55,000 for a first semester whose line is
  ₦46,770–₦79,310.
* Nothing is removed, moved or refunded.

## Where it shows

* **The panel.** `finance.spillover_panel` gives each semester a `paidFor` flag: charged because a payment was made for it.
* **The card.** The semester reads "Paid for" (not "Registered") and "A payment was made for this semester and its spillover
  fee is paid".
* **The quote.** The carry-over picker says the fee is owed already "a course of it is on your registration, or a payment was
  made for it".

## Tests

* `db/check.sql` V697.
* `lib/spillover.test.ts`.
