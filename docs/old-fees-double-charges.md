# Overpaid old-portal fees: possible bank double charges and payments never received (V561, V684)

## The case

Seen on AWS on 18 October 2026: a 200 Level student on the Overpaid list, ₦48,738.20 "paid more than due". Their first
semester of 2025/2026 held two old-portal school-fees records of ₦85,294, both dated 23 March 2026, under two of the old
portal's payment numbers (`…-S1` and `…-S1-PR20260323062528751`).

| | Amount |
|---|---|
| Due for 2025/2026 (₦85,294 first semester + ₦36,555.80 second) | ₦121,849.80 |
| Paid (two × ₦85,294) | ₦170,588.00 |
| Overpaid | ₦48,738.20 |

Old Fees History rightly records a payment number it has not seen as a payment of its own (V498). So the excess is real if
both payments reached the University's account. It is nothing if the bank charged the student twice and sent one charge
back. Before V561 nothing asked which before the Bursary carried or refunded the excess, and a numbered record the bank never
received could not be withdrawn. Registration was never in the way: the second semester counts the session's payments
together, so the second payment already covers it.

## What V561 adds

### Possible bank double charges

Finance → Old Fees History → **Possible bank double charges** lists old-portal records of one student, session, item, day
and amount (to the naira) under two or more payment numbers (`finance.possible_double_charges(session)`). A record that holds
several payments is not compared. A record with no number beside a numbered one is a double on the record, and V498's
"payments on record twice" tool handles it.

A Bursary officer checks each group against the bank statement (or the gateway's collections report) for that day and records
the result with the evidence:

* **Every payment received.** The excess is real; carry or refund it on the Overpaid list as before.
* **Not all received.** Tick the records the bank never received; at least one did arrive. Each record ticked is raised for
  withdrawal on the same evidence.

**Until a group is checked, the student is held on the Overpaid list.** `finance.decide_overpayments` leaves them out of every
carry or refund decision and returns how many it held. The list marks them "Check with the bank".

### Payments the bank never received

Finance → Old Fees History → **Payments the bank never received** lists the withdrawals (`PNR/YYYY/NNNNNN`). A withdrawal is
raised from a bank check, or for any old-portal reference on its own ("Raise for a payment reference…"), on evidence and a
reason.

* **Raised by one Bursary officer, decided by another.** The officer who raised it cannot approve it
  (`PAY_NOT_RECEIVED_SAME_OFFICER`). Another officer approves it, or rejects it with a note. Only the officer who raised it
  can cancel it.
* **Approved:**
  * the record is withdrawn as V498 withdraws a double: its ledger posting reversed and freed;
  * the record is kept on `finance.old_payment_withdrawn` (kind `NOT_RECEIVED`, with the record that stands) and, since V670,
    archived for good (counted nowhere, never deleted);
  * its payment number is kept on `finance.legacy_payref_withdrawn`, so loading the same export again never records it
    again (counted as a duplicate);
  * the student is told by e-mail, text and the portal (template `PAYMENT_NOT_RECEIVED_REMOVED`) and their fees page shows
    what is now owed.
* **Refused:** a portal payment (settled with the gateway); a record holding several payments; one that a deferment fee, a
  refund, the GST desk, a gateway test or a payment swap points at; and one that a carry, a refund or a wallet credit of the
  session's overpayment rests on (V781: a decided student's later duplicate is not refused, see the last section).

The checks and the withdrawals are the Bursary's office (`bursar`). Every other finance reader sees them. The database enforces
the office and the two people, not only the screen.

### Checking against the bank's list (V684)

Finance → Old Fees History → **Check against the bank's list** checks many groups at once. A Bursary officer uploads the bank's
or the gateway's list of payments received (Excel or CSV) and says which days of payments it covers:

* **The file.** A column naming the payment number (Payment Reference, Transaction Ref, Customer Reference, Ref, Receipt No …)
  is read with the amount and date columns where the list has them. A bank statement with no such column is searched cell by
  cell for numbers, and its amounts are not compared. Numbers are read in upper case without spaces, as the old portal keeps
  them.
* **The days.** Only groups paid within the days stated are judged. A payment made late on the last day may reach the bank the
  next day, so end the days a little before the list does.
* **Preview first** (`finance.bank_list_preview`, nothing written). Each unchecked group of those days is:
  * **every payment on the list**: checked "every payment received";
  * **not all on the list** (at least one on it): checked "not all", and each record not on the list is raised for withdrawal
    beside the one that is;
  * **none on the list**, **less on the list** than the record holds, or **a record with no payment number**: left for a check by
    hand.
* **Record** (`finance.bank_list_apply`, `BLC/YYYY/NNNNNN`). The checks and withdrawals are V561's own, each marked with the
  list. A group whose withdrawal V561 refuses (several payments in one record, linked, swapped, the excess decided) is left
  unchecked and named. Every group judged is kept on `finance.bank_list_group`, written once. A list that settles nothing is
  refused (`BANK_LIST_NOTHING_TO_RECORD`).
* **Decide together** (`finance.decide_bank_list`). Another Bursary officer approves or rejects (with a note) every withdrawal
  the list raised that still waits; the officer who recorded the list may cancel them instead. Each one goes through
  `finance.decide_not_received`, so an approved record is archived, never deleted, its number is remembered and the student is
  told. A withdrawal that can no longer be made stays waiting and is named.

A check made again by hand on Possible bank double charges replaces the list's.

On the copy of 21 October 2026, a list of March 2026's payment numbers with one number of every other pair taken out judged
86 groups in under a second: 43 every payment received and 43 not all, with 43 withdrawals (₦2.69m) raised. Recording took
3 s and approving all 43 took 1 s (rolled back).

## For the case above

1. On Possible bank double charges, open 2025/2026 and find the student.
2. Look up both payment numbers on the University's statement for 23 March 2026.
3. **Both credits arrived:** record "every payment received" with the statement line. Then on Overpaid, carry the
   ₦48,738.20 into 2026/2027 (a continuing student) or refund it.
4. **One credit arrived:** record "not all of them" and tick the record that did not. Another Bursary officer approves the
   withdrawal under Payments the bank never received. The student then shows ₦36,555.80 owed for the second semester.

## Database objects

`finance.double_charge_check`, `finance.payment_not_received`, `finance.legacy_payref_withdrawn` (audited), and the functions
`finance.possible_double_charges`, `finance.check_double_charge`, `finance.propose_not_received`,
`finance.decide_not_received` and `finance.cancel_not_received`. V561 also restates two functions:

* `finance.import_legacy_payments`, from its V502 definition: a withdrawn payment number counts as seen;
* `finance.decide_overpayments`, from V519: it holds students waiting for a bank check and returns `held`.

The API is `/api/v1/finance/legacy-fees/double-charges` (list, `/check`) and `/api/v1/finance/payments-not-received`
(list, raise, `/{year}/{seq}/decide`, `/{year}/{seq}/cancel`).

V684 adds `finance.bank_list_check` and `finance.bank_list_group` (audited, kept), `double_charge_check.bank_list_id`, the
functions `finance.bank_list_numbers`, `finance.bank_list_match`, `finance.bank_list_validate`, `finance.bank_list_preview`,
`finance.bank_list_apply` and `finance.decide_bank_list`, and restates `finance.check_double_charge` (a check made again by
hand clears the list's mark). The API: `POST /api/v1/finance/legacy-fees/double-charges/bank-list/preview` and
`…/bank-list` (Bursary), `GET /api/v1/finance/legacy-fees/bank-lists` and `…/bank-lists/{year}/{seq}` (finance readers),
`POST …/bank-lists/{year}/{seq}/decide` with `APPROVE`, `REJECT` or `CANCEL` (Bursary).

On the Railway copy (17 Oct 2026) no student has such a pair, so the list is empty there; the AWS case comes from uploads made
on AWS. The list reads a session in about 0.5 s on that copy, and every session in 1.4 s.

## Overpaid school fees: this check is one hold of fourteen (V781)

The Overpaid school fees desk (`/finance/overpaid`; `docs/overpaid-school-fees.md`) lists every student paid above their charge, by
cause, and holds a student back for any of fourteen reasons. An unchecked possible bank double charge, or a withdrawal still open,
is one of them: `BANK_CHECK`, "Waiting for the bank check". What changes on this page's side:

* **The hold stops every decision**, not only a refund or a carry: a wallet credit too, on the new desk and on Legacy Financial
  Reconciliation. A "never received" withdrawal proposed on a school-fees record of the session holds the student the same way.
  The Bursary's verdict clears it. On the copy of 22 October 2026, 79 students were held for this alone.
* **"All" decides the exact repeats only.** Carry all and Refund all on the old Overpaid panel, and Credit all ready and Refund
  all ready on the new desk, take a student only when the repeat makes up the excess exactly and the bank or the gateway reported
  it. Of the copy's 81 students paid twice on the old portal, 34 are exact (₦2,500,220); for the other 47 (₦1,846,345) the fee
  line decides the amount, so each is decided one student at a time, with the officer's confirmation that the fee setup and the
  payments were checked.
* **A decided student's later duplicate can be withdrawn.** A withdrawal is refused (`PAY_NOT_RECEIVED_DECIDED`) only when, without
  that payment, less would remain above the charge than is decided or requested (`finance.overpayment_decisions_covered`). It used
  to be refused for any school-fees record of a student whose overpayment was decided.
* **The old list names a wallet credit.** A student credited to the wallet reads "Credited to the wallet" on the Overpaid panel, and a
  student decided who paid again is "not yet decided" for what is left.
