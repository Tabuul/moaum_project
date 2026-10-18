# Overpaid old-portal fees: possible bank double charges and payments never received (V561)

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
  * the record is kept on `finance.old_payment_withdrawn` (kind `NOT_RECEIVED`, with the record that stands), then removed;
  * its payment number is kept on `finance.legacy_payref_withdrawn`, so loading the same export again never records it
    again (counted as a duplicate);
  * the student is told by e-mail, text and the portal (template `PAYMENT_NOT_RECEIVED_REMOVED`) and their fees page shows
    what is now owed.
* **Refused:** a portal payment (settled with the gateway); a record holding several payments; one that a deferment fee, a
  refund, the GST desk, a gateway test or a payment swap points at; and one whose session's overpayment was already carried or
  refunded.

The checks and the withdrawals are the Bursary's office (`bursar`). Every other finance reader sees them. The database enforces
the office and the two people, not only the screen.

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

On the Railway copy (17 Oct 2026) no student has such a pair, so the list is empty there; the AWS case comes from uploads made
on AWS. The list reads a session in about 0.5 s on that copy, and every session in 1.4 s.
