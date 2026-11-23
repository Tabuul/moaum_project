# Overpaid school fees reconciled from the Bursar's dashboard (V781)

*22 November 2026.* **Bursary → Finance → Overpaid School Fees** (`/finance/overpaid`; the Students Account Officer has it under
Payment Management, and the Bursar's dashboard carries its panel). The University's word of 15 November 2026: students paid school
fees twice, so what a session charges and what was paid no longer agree, and the Bursar wants every such student on the dashboard
"so I can reconcile this transactions either move the money to student wallet to use it next semester or do a refund to the
student".

The case behind it, as two screens of a student's Fees tab showed it:

| | Amount |
|---|---|
| Charged for 2025/2026 (₦66,745 first semester + ₦28,605 second) | ₦95,350 |
| Paid (₦66,745, and ₦28,605 twice on two portal references) | ₦123,955 |
| Paid above the charge | ₦28,605 |

The tab read **Paid ₦123,955 "in full"** and **Balance ₦0 "settled"**: nothing on any screen said that ₦28,605 was the student's
money.

The University's decisions of 15–16 November 2026, and what this build does with each:

1. **Everyone paid above their charge is listed, sorted by cause.** "Credit all" and "Refund all" act only on a repeated payment;
   an excess the fee line decides is shown apart and decided one student at a time, after the fee setup is checked. *Built.*
2. **A wallet credit is the work of two officers, in bulk.** The Students Account Officer or a Bursary officer requests; a
   different Bursary officer approves. Refunds keep their own two-person rule. *Built.*
3. **The wallet's overpaid money is used automatically** on the student's next school fees. *Not in this build* (§19): the student
   applies it on the Wallet page, or asks there for a refund.
4. **A second payment of school fees already paid is stopped** where the portal can stop it. *Not in this build* (§19). Money a bank
   has already taken is always recorded.

## 1. Nothing rebuilt

| The request asked for | Where it already was | Since |
|---|---|---|
| Who is overpaid in a session, old portal or new | `finance.overpaid(session)`: charged from the fee lines (`finance.session_charges`), paid from every confirmed, not archived `School fees%` payment of the session (`finance.session_payments`), listed from ₦1 | V506, V519, V670 |
| A refund to the student | `finance.decide_overpayments(…, 'REFUND', …)` raises `RF-YYYY-NNNN` on Refunds & Credits: approved by another officer, paid with the transfer reference and the date | V506, V528, V533, V534 |
| The excess moved to the student's wallet | the credit request `finance.legacy_credit_request` (`LOR/YYYY/NNNNNN`): one CREDIT of source **OVERPAID**, one decision **WALLET**, the student told | V625 |
| The wallet, its statement, its refund | `finance.wallet_entry`, `apply_wallet`, `wallet_withdrawal` | V033, V327, V714 |
| The ledger | `finance.gl_sync`: an OVERPAID credit is drawn from the overpaid session's school-fees income into 2100; a wallet payment is Dr 2100 / Cr fee income | V545, V625 |
| Possible bank double charges held for the bank's word | `finance.possible_double_charges`, `double_charge_check`, the bank's list | V561, V684 |

What was missing: the wallet request reached only students with an old-portal record, one at a time, re-reading the whole session
for each (2.7 s a student); nothing sorted a repeated payment from a fee-line difference; one decision a student and session stood
in the way of a student who was decided and then paid again; no screen showed the excess before a decision; a refund from the wallet
looked for the money under the wrong source; and a wallet credit was worded as a refund. V781 adds those and nothing else: no
second overpayment rule, no second wallet, no second refund.

## 2. Who is listed, and the five causes

A student is listed for a session when the session charges them something and what they paid is ₦1 or more above it
(`finance.overpaid`, unchanged in its rule). Every listed student carries **one cause**, the first that applies
(`finance.overpaid_read`). The payments compared are the session's counted school-fees payments: those of the **portal**
(`MOAUM-…` references: the gateways, PayDirect, bank transfer, the wallet's own payment, the historical door), those of the **old
portal** (`MOAUM-LEG-…` and the old portal's own numbers), and CARRIED records, which are never compared. Amounts are compared to
the naira.

| Cause | The test | In bulk? |
|---|---|---|
| **Paid twice on the portal** (`PORTAL_TWICE`) | two or more portal payments of one amount, and the excess is that amount once or more (never more times than there are repeats). The case above: ₦66,745 + ₦28,605 + ₦28,605 against ₦95,350 leaves ₦28,605 = 1 × ₦28,605 | yes, when exact (§3) |
| **Paid on the old portal and the new** (`OLD_AND_PORTAL`) | an old-portal and a portal payment of one amount, and the excess is that amount once or more | yes, when exact |
| **Paid twice on the old portal** (`OLD_TWICE`) | two or more old-portal payments under the old portal's own label (the same item and semester) at one amount, and the excess is no more than the repeated money. V561's possible bank double charges are such pairs | yes, when exact |
| **Several payments above the charge** (`PART_PAYMENTS`) | a repeat that does not explain the excess by those tests, or three or more payments | never |
| **Paid above the fee line** (`ABOVE_FEE_LINE`) | at most two payments, none repeated: what was paid differs from the fee setup | never |

"Paid twice" is strict on purpose. Two equal semester payments above the line (the old portal billed ₦55,000 + ₦55,000 where the
line says ₦100,000) are **not** paid twice: no payment was repeated, the fee line is in question. The error this accepts is a true
double shown as "several payments" and decided one at a time. The error it refuses is fee-line money returned in bulk.
`finance.payment_term` is not used: it counts cumulatively, so a repeated second-semester payment reads as another semester.

**The fee-line group is the Bursary's ruling, not the portal's.** On the live-shaped copy of 22 October 2026, 1,018 of the 1,136
students listed for 2025/2026 are above the fee line (₦16.7m of ₦22.4m), most of them College of Health Sciences students whose
copy holds an older set of fee lines than the old portal billed. V781 changes no fee line. The panel and the desk show that group
apart, labelled **Check the fee setup first**, and no "all" button touches it.

## 3. What "Credit all" and "Refund all" take: an exact repeat the bank reported

A row is **ready** (`bulk`) only when all of these hold:

- its cause is one of the three paid-twice causes;
- **the repeat makes up the excess exactly**, to within ₦1. The other payments then equal the charge, so the fee line does not set
  the amount. Of the copy's 81 students paid twice on the old portal, 34 are exact (₦2,500,220) and 47 are not (₦1,846,345): for
  those the amount to give back is "the repeat less what the fee line still asks", and a person confirms the fee line;
- **every portal payment of the repeated amount carries the bank's or the gateway's own report**: a gateway settlement event, a
  PayDirect notification, a matched line of the collections report, or the wallet's own payment. Two references confirmed by hand
  against one bank transfer share no gateway reference, so nothing else would tell them from two payments;
- **the level on record is the level by entry year**. The charge is read at the level on record (as the fees page and every gate
  read it); where the two differ (90 of the 1,136 on the copy, ₦2,851,119) both are shown and the row is decided by a person;
- no wallet credit of an adjusted amount already stands for the student and session (V625 lets a request confirm less than the
  excess with a reason; what it left is looked at by a person).

**Every other row is decided one student a call, with the officer's confirmation that the fee setup and the payments were
checked.** The confirmation is a parameter of the SQL functions, refused when missing, and kept on the request and on the decision
(`fee_setup_checked`). It binds every route: the Overpaid desk, the old Overpaid panel's Carry and Refund
(`finance.decide_overpayments`), and the request on Legacy Financial Reconciliation (`finance.legacy_credit_initiate`,
`OVERPAID_FEE_SETUP_CHECK`). The kept list is never asked: the row is read live.

## 4. Holds

A held row is listed with every reason that applies, and **no decision is made on it: not a wallet credit, not a refund, not a
carry**. The words are the database's (`finance.overpaid_hold_word`) and the screen shows the same sentences
(`lib/overpaid.ts`).

| Hold | When | Shown as | Cleared by |
|---|---|---|---|
| `PAST_SESSION` | the session began before the student's current session | Not this student's current session — its charge is read as the student stands today | not here: Historical Fees assesses a past session (§8) |
| `CLOSED_FOR_FEES` | graduated or award approved, and the session is after the graduation session: nothing is charged, so the whole payment is the excess, not the figure listed | Graduated: nothing is charged for this session — refund the payment on Refunds & Credits | a refund raised there against the payment (it then counts as decided) |
| `BANK_CHECK` | a possible bank double charge of the session's school fees is unchecked or has a withdrawal open (V561, V684), or a "never received" withdrawal is proposed on a school-fees record of the session | Waiting for the bank check | the Bursary's verdict |
| `SAME_PAYMENT` | two of the student's records of one amount share a gateway reference, a transaction reference or an old-portal number (V670's authoritative signals): one payment recorded twice, not two payments | One payment recorded twice — archive the duplicate | the archive desk (allowed while the decided money stays covered, §7) |
| `REVERSAL` | a PayDirect reversal names one of the payments | A PayDirect reversal is on record | the reversed record archived |
| `UNDER_REVIEW` | a school-fees payment of the student and session is archived and not settled (V670) | A payment is archived for review | the archive settled |
| `OPEN_CORRECTION` | a swap of a school-fees payment of the session is pending with the student on either side (V527), or a reallocation from or into the session is pending or returned (V649) | A payment correction is open | the correction decided |
| `SEMESTER_NOT_CHARGED` | the student's fee lines include a semester after the highest one open | A semester of this session is not yet charged | the semester opened |
| `SEMESTER_NOT_STATED` | a semester of the session that is not closed has no fee line for the student (`finance.fee_semesters_unstated`) | A semester's fees are not yet stated | the line stated, or the semester closed |
| `SPILLOVER_SEMESTER` | a spillover student with no course registered (and none paid for, V697) in a semester that has a spillover line and is not closed | Spillover: a semester still to be registered | registration, or the semester closed |
| `LATE_FEE_POSSIBLE` | the student's fee lines carry a late registration fee, a registration window of the student's own kind has its late fee on for a semester not closed, and the student has not submitted that semester | A late registration fee may still fall | the registration submitted, or the semester closed |
| `LATE_FEE_LAPSED` | the student's fee lines carry a late payment fee, the student's own school-fees window had its late fee on and has closed, and what was confirmed by its closing date is below the fee | A late payment fee was due — it is not an overpayment | not here: if the Bursary waives the fee, the refund is raised on Refunds & Credits against the payment |
| `EXCESS_UNCERTAIN` | a ready row whose own fee account (`finance.position`) reads an excess ₦1 or more different from the list | The student's own fee account reads a different excess | a person looks; one student a call says which figure differs |
| `MERGED_RECORD` | the record is a duplicate merged into another | A duplicate record — decide on the record kept | the record kept |

The four holds on the charge (`SEMESTER_NOT_CHARGED`, `SEMESTER_NOT_STATED`, `SPILLOVER_SEMESTER`, `LATE_FEE_POSSIBLE`) are the
ones that matter most to a student who paid a semester twice early in a session: the second payment already pays the next
semester of the **same** session (every school-fees payment of a session is pooled), so until the session's charge is final the
"excess" may be that session's own money.

A level by entry year that differs from the level on record is **not** a hold: in the student's current session the record is the
authority for every charge. The difference is shown and keeps the row out of the ready group (§3).

## 5. Who is refunded, never credited

The wallet is **refused** (`OVERPAID_WALLET_REFUSED`) for a student who is graduated, withdrawn (or withdrew voluntarily),
expelled, transferred out or deceased, and for a record whose award the Senate has approved: there is no next school fees for the
money to pay. Their excess is refunded (a deceased student's to the estate). **A carry into the next session is refused for them
too**: the next session charges them nothing, and carried money would never be listed again. A final-level student still in
study is not refused: they may spill over, and money on a wallet stays refundable.

## 6. The two routes

### 6.1 Wallet credit, by two officers

1. **Request** (Students Account Officer, Bursar; `finance.overpaid_credits_request`). The officer selects students on the desk,
   or with a paid-twice cause as the filter, and no other filter (state, held, repeated payment, faculty, department or search),
   presses **Credit all ready** (the cause as a whole: every ready student of it in every faculty and department, whatever page
   is shown), gives the reason (ten characters or more) and ticks "I
   have looked at the payments behind these students' excess". For one student who is not ready, the second tick: "The fee setup
   for this student's programme and level, and the payments, were checked". Each student gets one request (`LOR/YYYY/NNNNNN`)
   for **the whole undecided excess**, with the evidence written by the portal from the payments (amount, channel and day of each;
   no reference), under one batch number `OCR/YYYY/NNNNNN` for the act. **Nothing is credited.** The Bursar's office holders are
   told once (`OVERPAID_CREDITS_WAITING`). A student left out is named with the reason:

   | Left out as | Why |
   |---|---|
   | `DECIDED` | nothing is left to decide |
   | `HELD` | a hold of §4, in its words |
   | `REFUND_ONLY` | the student is refunded, not credited (§5) |
   | `ONE_AT_A_TIME` | not an exact repeat: decided one student at a time, with the fee setup checked |
   | `FEE_SETUP_UNCHECKED` | the one student named needs the fee-setup confirmation |
   | `REQUEST_OPEN` | a credit request is already open for the student |
   | `EXCESS_UNCERTAIN` | the student's own fee account reads another excess |
   | `NOT_OVERPAID` | not paid above the session's school fees |

2. **Approve** (a Bursar officer other than the requester; `finance.overpaid_credits_decide`), for a whole batch or for ticked
   requests, from the dashboard panel or the desk's **Approvals** tab. For each request the session is read afresh, the student's
   own fee account is read under the student's lock, and only then: one `CREDIT` on `finance.wallet_entry` (source OVERPAID, the
   request's reference, the plain note "Overpaid school fees of {session} credited to your wallet ({reference})"), one
   `overpayment_decision` **WALLET**, the request CREDITED under an approval batch `OCA/YYYY/NNNNNN`, and the student told
   (`LEGACY_CREDIT_POSTED`). **The approval pays no fees**: the credit stays on the wallet until the student applies it on the
   Wallet page (the Apply button, `finance.apply_wallet`) when they owe school fees and payment is open, or asks there for it as a
   refund (§6.3).

   A request that cannot be credited is **left with its reason and not tried again in that pass**: the requester's own
   (`LEGACY_CREDIT_SAME_OFFICER`: never credited by the person who asked), one that is held now (`OVERPAID_HELD`,
   `LEGACY_CREDIT_DOUBLE_CHARGE_CHECK`), one whose excess changed since (`LEGACY_CREDIT_EXCESS_CHANGED`,
   `OVERPAID_EXCESS_UNCERTAIN`), a student now refund-only (`OVERPAID_WALLET_REFUSED`), a merged record
   (`LEGACY_CREDIT_STUDENT`). The reason shows beside the request, and a new pass tries it again. The requester is told what was
   decided of theirs (`OVERPAID_CREDITS_DECIDED`).
3. **Return or reject** (the same officer, a note of ten characters or more), for a batch or ticked requests. A rejection on this
   desk tells no student: the student never knew a request existed.
4. **Withdraw** (`finance.overpaid_credits_withdraw`): the requester withdraws their own open or returned requests in one act,
   with a reason; a Bursary officer may withdraw anyone's. A returned request is not resubmitted here: it is withdrawn, what the
   Bursar's note names is put right, and the student is requested again (a request made on this desk is always for the whole
   undecided excess, so there is nothing in it to correct).

Requests made on this desk are decided on this desk. The Legacy Financial Reconciliation desk keeps the single requests made
there (`docs/legacy-financial-reconciliation.md`), and each desk's queue and figures show its own.

### 6.2 Refund

**Refund** on the desk (Bursar only) raises a refund for each selected student, or for every ready row of a paid-twice cause
(`finance.decide_overpayments(…, 'REFUND', …)`, the same function the old Overpaid panel calls). It is raised against the latest
school-fees payment of the session that covers the amount (`RF-YYYY-NNNN`), another officer approves it, and it is paid with the
transfer reference and the date. The student gives the account on their fees page (V528, V533). The same holds, the same
one-at-a-time rule and the same fee-setup confirmation apply. The desk never refunds "everyone": students or a paid-twice cause
must be named (`OVERPAID_BULK_WHO`).

**Carry** into the next session (V506) stays where it was, on the old Overpaid panel under Refunds & Credits and Old Fees History.
It is not offered on the new desk. It follows the same rules since V781: every hold stops it, "Carry all" takes the ready rows
only, and a refund-only student is not carried.

### 6.3 After the credit: the student's wallet

The credit is the student's own money on the wallet, under the source **Overpaid school fees** (`OVERPAID`), on the session it was
overpaid in. The student:

- **applies it** on the Wallet page when they owe school fees and payment is open (the Apply button, which spends the wallet's
  sources in the Bursar's order); the fees page says "₦X of overpaid school fees is on your wallet" beside the fees it may pay; or
- **asks for it as a refund** on the Wallet page once the current session's fees are paid in full and no arrears stand.

Two faults of the wallet's refund were put right for this money (found while reading `request_withdrawal` and
`withdrawal_eligibility`): an "own money" refund was recorded under source `SELF` and then looked for there, where an OVERPAID
credit never was; and the refund read one session's entries, while the credit sits on the session it was overpaid in, so once the
next session was current the page saw nothing to refund. Now `finance.withdrawal_sources(student, session)` says what each source
may be refunded now (the Fund's money; the student's own top-up; overpaid school fees over every session), the Wallet page offers
one choice a source ("₦X of Overpaid school fees"), caps the amount at the chosen source's figure, and sends the `source`; a
request larger than any one source holds is refused with what each may give (`WALLET_REFUND_ONE_SOURCE`). The refund is paid
as before (`pay_withdrawal`, unchanged) and debits the source it was asked of.

## 7. Never twice, never more than the excess

- **A further decision is arithmetic.** What is left to decide is `paid − charged − decided`, where **decided** is the standing
  decisions (carried, refunded, credited) **plus the refunds raised by hand** on Refunds & Credits against the session's
  school-fees payments (`finance.overpayment_decided`). A student decided once who pays again is listed again for the new amount
  and decided again; the unique index that allowed one live decision a student and session is gone. A trigger on
  `finance.overpayment_decision` refuses any decision that would take the decided money above the excess its own row records
  (`OVERPAY_ABOVE_EXCESS`).
- **Two witnesses for every amount.** The session's reader finds the student and the holds; the student's own fee account
  (`finance.position`), read under the student's lock, gives the amount, at the request, the refund, the carry and the approval.
  If they differ by ₦1 or more nothing is decided (`EXCESS_UNCERTAIN`).
- **A hand refund counts, and is itself guarded.** A refund raised on Refunds & Credits against a school-fees payment is refused
  while a wallet credit request is open for that student and session (`REFUND_CREDIT_REQUEST_OPEN`), and refused beyond what is
  paid less what is already decided (`REFUND_ALREADY_DECIDED`). Once raised it shows on the desk (**Refunded on Refunds &
  Credits**), lowers what is left, and a credit approved after it is refused as changed.
- **A hand wallet credit of source OVERPAID is refused** (`WALLET_OVERPAID_ROUTE`): overpaid school fees reach a wallet only
  through a request a second Bursary officer approved. A constraint checked at commit holds the same for anything that writes the
  wallet.
- **A wallet reset is refused while a credit of overpaid fees is on the wallet** (`WALLET_RESET_OVERPAID_CREDIT`): the reset
  would leave the overpayment decided with no money behind it.
- **Carry and Refund pass over a student with a credit request open**, and say how many.
- **A correction of a payment is refused only when it would uncover decided money.** The archive, the school-fees payment swap,
  the reallocation and the "never received" withdrawal used to refuse any school-fees payment of a decided student
  (`PAR_OVERPAYMENT_DECISION`, `SWAP_OVERPAYMENT_DECISION`, `REALLOC_OVERPAYMENT_DECISION`, `PAY_NOT_RECEIVED_DECIDED`). They now
  refuse only when, without that payment, less would remain above the charge than is decided or requested
  (`finance.overpayment_decisions_covered`). So a decided student's later duplicate can be archived, withdrawn as never received
  or swapped to its owner; the payments a decision rests on still cannot leave. Money arriving on a decided student (the target of
  a swap, the destination of a reallocation) is no longer refused: it is "a decided student pays again". Where the decided money
  has already left (a carry, a refund, a credit spent), the payment it rests on is kept.
- **Old-fees maintenance keeps the records a decision rests on.** The old fees reset, an upload that would take a record over
  and the put-right of mislabelled items leave a school-fees record of a student and session with a standing decision or an open
  request (`finance.overpayment_holds_record`). An upload that would relabel a record carrying no payment number (the same money,
  put under another item or another reference) counts the row as already recorded instead when a decision stands on the record or
  a credit request is open for it and the relabel would take it out of the school fees, or when something points at the record by
  its reference (a refund raised against it is read through that reference); a record nothing rests on is relabelled as before.

## 8. A session that is not the student's current one

Every reader of a charge reads the student as they are **today**: their level, their programme, their spillover year. For the
student's current session that is right. For an earlier one it is not (V654's own finding), and two witnesses would agree on a
wrong charge. So a session before the student's current one is **listed and never decided here** (`PAST_SESSION`).

What the Bursary must know: **overpayments are reconciled while the session is the students' current one.** After the calendar
moves on, what was not decided is shown held. The reader of a past session is the historical account (Historical Fees &
Clearance, `docs/historical-school-fees.md`); reading a past session's excess from it for this desk is a follow-up, not part of
V781. On the copy no listed student of 2025/2026 has another current session.

## 9. Decided above the excess

If the charge of a student's current session rises after a decision (a level corrected, a fee line restated, a late fee), the
decided money is still read as paid and the fees page reads no balance. The desk lists such a row **Decided above the excess**
with the amount to recover (`OVER_DECIDED`: "₦X to recover"), the dashboard counts them, and a decided student who is no longer
overpaid at all stays on the list.

In this build nothing puts that amount back on the session: the desk shows it and the wallet **keeps it back from refunds**. The
rule (`finance.overpaid_refundable`, `finance.overpaid_kept_back`): of the OVERPAID money a wallet holds, what the current
session's decisions are above the excess is not refundable. The Wallet page offers only the rest, says "₦X of it is kept for your
{session} school fees, which rose after it was credited; that part is not refunded", and a refund already requested before the
rise is refused when it comes to be approved (`WALLET_REFUND_KEPT_BACK`); the charge put back, it is refundable again. What this
does not cover: a carry or a refund decided above the excess, or wallet money already spent, has nothing on the wallet to keep
back; those rows stay listed for the Bursary to correct by hand. No "reversal" instrument was added.

## 10. What staff and students see

- **The Bursar's dashboard**: the panel **Overpaid school fees** for the dashboard's session (any session with fee lines can be
  chosen): *Paid twice — ready*, *Check the fee setup first*, *Held for a check*, *Waiting for your approval* (with **Approve**
  for each batch another officer requested), *Credited to wallets* (how much is already used on fees, how much is still in
  wallets), *Refunds* (raised, approved, paid), and a table by cause. The Students Account Officer's dashboard carries the same
  panel with *Waiting for the Bursar* and *Returned to you*.
- **The desk** (`/finance/overpaid`): the five causes as filters; the students with what was charged and paid, the excess, what
  is decided, the cause, the payments behind it (amount, channel, day), why a row is held, and its state; **Credit to wallet**,
  **Refund**, **Excel**; the tabs **Students**, **Approvals** and **Returned**. A row that is not ready can only be selected alone.
  Refunds & Credits points to it above the old Overpaid panel.
- **The staff record's Fees tab**: **Credit ₦28,605 — paid above the charge** in place of "Balance ₦0 settled", with one line
  saying what happens to it; "excess decided" once it is.
- **The student's fees page**: "Paid above the charge" in place of "Outstanding ₦0 — Cleared", with a note that depends on the
  case: paid twice ("The Bursary will credit ₦X to your wallet for your next school fees, or refund it. There is nothing for you
  to do until you are told."), a credit requested, a charge not yet final ("₦X paid ahead… counts towards the rest of this
  session's fees"), a late fee, or a fee-line question ("The Bursary is checking it against your fees"). A wallet credit reads
  "₦X credited to your wallet" (it read as a refund before V781); once credited, the page says the credit is on the wallet and
  where to apply it.
- **The student's wallet page**: the plain statement line, a note that the overpaid school fees are on the wallet and may be
  applied or refunded, and the refund form by source (§6.3).
- **The notices**: `LEGACY_CREDIT_POSTED` (reworded for the wallet; now mandatory), and to the offices
  `OVERPAID_CREDITS_WAITING` and `OVERPAID_CREDITS_DECIDED`.

## 11. The kept list

The session's read costs seconds (§16), so the dashboard and the desk read a **kept list** in the database
(`finance.overpaid_snapshot`, one row a student and session; `finance.overpaid_snapshot_run` says when it was worked out). It is
a list worked out from the fee lines and the payments, with nothing in it decided by a person, so it is audit-exempt, as
`finance.historical_summary` is (V654). It lives in the database, not in the API, because the API runs on more than one instance.

- **What is kept** is what is dear and slow to change: charged, paid, the excess, the cause, the payments (amount, channel, day
  and kind; never a reference or a receipt), the holds.
- **The state is never kept**: decisions, credit requests and refunds are read live at each read, so an officer's act shows at
  once on every screen with no refresh.
- **Money never reads the kept list**: every request, approval, refund and carry reads the session live.
- **Refreshed** by a job every ten minutes for the University's current session, when a school-fees payment of the session was
  confirmed, uploaded or archived since, or after an hour (`finance.overpaid_refresh_due`); every session once worked out, once a
  night; and by **Refresh** on the desk (Bursar, Students Account Officer). A session never worked out says so
  ("Not yet worked out for {session}") until one of those two offices opens it. Fee-line, level, registration and bank-check
  changes are caught by the hour, by Refresh, and — for money — by the live read of every decision.

## 12. The ledger

Nothing new is posted by V781's own code; `finance.gl_sync` is not restated.

| Event | Journal |
|---|---|
| A wallet credit approved | Dr 4010 School fees [the overpaid session, fund OVERPAID] / Cr 2100 Student deposits & wallet. The cash was booked when the payment was received: no new cash, and the overpaid income becomes a liability to the student |
| The student applies the wallet to school fees (Apply) | Dr 2100 / Cr 4010 School fees [the session paid], as every wallet payment |
| A refund from the wallet paid | Dr 2100 / Cr 1020 Bank — Disbursements, on the day paid |
| A refund of an overpayment paid (Refunds & Credits) | Dr 4990 Refunds of fees / Cr 1020, as before |
| A carry (V506) | Dr 4010 [the overpaid session] / Cr 4010 [the next], as before |

The wallet payment's line on 2100 carries the session paid and no fund, as every wallet payment's has since V545: account 2100
clears in total, not by session or fund, when a credit of one session is used on another.

## 13. Who may

| Office | May |
|---|---|
| Bursar (`bursar`), super | read; refresh; request, withdraw (anyone's); approve, return, reject (never their own request); refund |
| Students Account Officer (`studentaccounts`) | read; refresh; request; withdraw their own |
| Registry, Academic Office, Audit, Deputy Audit, ICT, admin, VC, DVC | read |

The API names the offices (`OverpaidController`: READERS, REQUESTERS, DECIDERS) and the database holds every rule
(`LEGACY_CREDIT_OFFICE`, the two-officer check `ck_lcr_two_officers`, one open request a student and session, one wallet entry a
request, the trigger on the decided amount, the advisory locks).

## 14. The API

`/api/v1/finance/overpaid` (`session` is `YYYY/YYYY`, the University's current session by default):

| Method, path | Office | Does |
|---|---|---|
| `GET /figures?session=` | readers | the panel's figures from the kept list and the live state: `students`, `excess`, `causes[5]`, `paidTwice`, `apart`, `held` (with `reasons`), `overDecided`, `requests` (with `batches[]`), `credited`, `refunds`, `carried`, `sessions[]`, `computed`, `refreshedAt`. Never a refresh |
| `GET /rows?session=&cause=&state=&held=&bulk=&faculty=&department=&q=&page=&size=` | readers | the desk's rows (`size` 1–500; the Excel list with `export=true`), with the faculties and departments to filter by |
| `POST /refresh` `{session}` | Bursar, Students Account Officer | works the session out again; `OVERPAID_SESSION` for a session not on the calendar |
| `POST /credits/request` `{session, students?, cause?, reason, confirmed, feeSetupChecked?, limit?, batch?}` | Bursar, Students Account Officer | → `{batch, requested, amount, skipped, skippedWhy[], remaining}`; called again with the answer's `batch` while `remaining > 0` |
| `GET /credits?session=&status=&batch=&page=&size=` | readers | the requests made on this desk |
| `POST /credits/decide` `{batch?, ids?, action: APPROVE\|REJECT\|RETURN, note?, limit?, since?}` | Bursar | → `{batch, since, credited, amount, rejected, returned, skipped, skippedWhy[], remaining}`; called again with the answer's `since` while `remaining > 0` |
| `POST /credits/withdraw` `{batch?, ids?, reason}` | Bursar, Students Account Officer | → `{withdrawn}` |
| `POST /refund` `{session, students?, cause?, reason, confirmed, feeSetupChecked?, limit?}` | Bursar | → `{refunds, held, apart, requested, uncertain, unchecked, remaining}` |

Refused by the API before the database: `OVERPAID_CONFIRM` (the confirmation not ticked), `OVERPAID_TOO_MANY` (more than 2,000
students or requests named), `OVERPAID_SESSION` (a session not written as 2025/2026, or none current to default to), on `/refund`
`OVERPAID_BULK_WHO`, on `/rows` and `/credits` `OVERPAID_FILTER` (a cause, a state or a status the desk does not list), and on
`/credits/decide` `OVERPAID_SINCE` (a `since` that is not the timestamp an earlier call of the pass answered). Every other refusal
is the database's, with its code and its remedy (422; an office the database refuses, 403).

Elsewhere:

- `GET /api/v1/me` and `/me/fees`: `excess`, `excessDecided`, `excessRemaining`, `excessRequested`, `excessCause`,
  `excessHolds[]` and `walletOverpaid`, each only when it applies (`/me?view=core` is unchanged).
- `GET /api/v1/me/wallet`: `overpaid`, `overpaidKeptBack` (only when ₦1 or more), and `eligibility.sources[{code, name, nature,
  refundable}]`; the refund request names its `source` (`WALLET_REFUND_ONE_SOURCE` when the amount is more than any one source
  holds, `WALLET_REFUND_KEPT_BACK` when the money is kept back, §9). `/nelfund/credit` and `/nelfund/reset` refuse a hand credit of
  source OVERPAID (`WALLET_OVERPAID_ROUTE`) and a reset over one (`WALLET_RESET_OVERPAID_CREDIT`).
- `GET /api/v1/finance/legacy-fees/overpaid` and `POST …/overpaid/decide` (the old panel): rows carry `remaining`,
  `decision_count`, `refunded_by_hand`; the decision takes `feeSetupChecked` and answers `apart`, `requested`, `uncertain`,
  `refundOnly`, `unchecked` beside `carried`, `refunds`, `held`, `remaining`.
- `/api/v1/finance/legacy-reconciliation`: the request and the resubmission take `feeSetupChecked`; a student's sessions carry
  `remaining`, `cause`, `bulk`, `holds[]`, `refund_only`; the queue shows that desk's own requests; `figures.requests.onOverpaidDesk`.

## 15. The words a screen uses

`lib/overpaid.ts` carries the labels (the five causes, the ten states, the fourteen holds and what clears each, the refund-only
reasons, the suggestions, the skip codes), what may be ticked (`selectable`: a row that is not an exact repeat is the only one
ticked), why a row cannot be acted on (`whyNot`), the totals of one act over its calls (`addUp`), and the Excel list (22 columns).
`lib/overpayment.ts` carries the student's words for a wallet credit and for an excess not yet decided (`excessWords`). Every
figure is the server's; nothing in the frontend works out an excess.

The ten states: *Decided above the excess*, *Not decided*, *Credit requested*, *Credit returned for correction*, *Credited to the
wallet*, *Refund raised*, *Refund approved*, *Refund paid*, *Refunded on Refunds & Credits*, *Carried into the next session*.

## 16. Measured

On `lv643pre`, the live-shaped copy of 22 October 2026 (PostgreSQL 18, read only; session 2025/2026; counts and naira only), before
the build:

| Read | Result |
|---|---|
| `finance.overpaid`: 1,136 students, ₦22,446,080 | 1.8 s on an idle server; 3.5–11.9 s with other work on the same server |
| the causes on top of it | about 0.4 s more |
| the whole live read: overpaid, payments, causes, holds | 6.2 s under load |
| one student's `finance.position` | 3.1 ms warm; 25 ms on a connection's second call; 308 ms its very first |

| Cause | Students | Paid above the charge |
|---|---|---|
| Paid above the fee line | 1,018 | ₦16,680,552 |
| Paid twice on the old portal | 81 (34 exact, ₦2,500,220) | ₦4,346,565 |
| Several payments above the charge | 34 | ₦1,299,072 |
| Paid on the old portal and the new | 3 | ₦119,891 |
| Paid twice on the portal | 0 | — |

Held: 79, all waiting for the bank check; no other hold applies on the copy. The copy was taken before the payments of 27–28
October, so it holds no student paid twice on the portal: that group is sized on live. So the live read cannot sit on the
dashboard or behind each page of the desk, which is why the kept list exists.

The targets the build is held to: the figures and a filtered page of the desk under 50 ms; "is a refresh due" under 5 ms; the
migration's two triggers, its last statements, to their commit under one second. The build's own timings are recorded in
`docs/performance-audit.md` as the verification on a scratch copy produces them.

## 17. The migration

`db/V781__overpaid_school_fees_reconciled_from_the_bursars_dashboard.sql`, one transaction under a five-second `lock_timeout`: a
migration that cannot have a lock fails and is run again. It does not work the kept list out (the job does, within ten minutes, and
the screens say "not yet worked out" until then). Its two triggers (the decided amount of a decision; the commit-time check that an
OVERPAID credit has its approved request) are its last statements before the commit: the second takes a share lock on the wallet's
entries, so wallet writes wait from there to the commit. Its data steps: the notes of overpaid credits already on wallets are made
plain (the evidence stays on the request), and refunds waiting under the wrong source are re-sourced where exactly one source
holds the money, the rest counted for the Bursary. Nobody is told by the migration.

New: `finance.overpaid_snapshot`, `overpaid_snapshot_run` (audit-exempt); columns on `finance.overpayment_decision`
(`fee_setup_checked`) and `finance.legacy_credit_request` (`cause`, `bulk`, `request_batch`, `credit_batch`, `fee_setup_checked`,
`last_skip_at`, `last_skip_code`, `last_skip_why`); the batch sequences. Locks, always in this order: `overpay:<student>:<session>`,
then `wallet:<student>`; loops take students in one order. The refresh job (`OverpaidWatch`) runs under a `JobLock` and is switched
by `moaum.overpaid.enabled` (`MOAUM_OVERPAID_ENABLED`, on by default; off in the integration tests).

## 18. Tests

- `db/check.sql` V781, on made-up students in made-up sessions: one student of each cause with the case above; an exact repeat
  against one short of the excess, two records confirmed by hand, two levels, an adjusted credit; each of the fourteen holds
  tried through request, refund and carry; the "all" acts leaving the fee-line student apart; two officers; the single credit and
  its journal; the approval pass that ends; never twice; the further decision and the corrections by arithmetic; the hand refund;
  refund-only students; return, reject and withdraw; decided above the excess and what the wallet keeps back from a refund;
  old-fees maintenance (and an upload that would relabel such a record); a student's row of the list the same whoever else is asked
  for; the desk's decided and requested read for the whole session in one pass; the kept list against the live list and the
  figures' identities; the wallet refund by source; the requests read by id, student and batch.
- `OverpaidReconciliationIT`: the figures and rows by office, the request, the approval by another officer, the wallet, the
  student's own Apply into the next session, the refund route, the further decision, the hand refund, return and withdraw, a
  wallet refund of source OVERPAID requested, approved by another and paid, the refund kept back.
- `lib/overpaid.test.ts`, `lib/overpayment.test.ts`, `lib/old-fees.test.ts`.

## 19. What needs the Bursary's hand

- **The fee lines first.** The "Check the fee setup first" group is a fee-setup question before it is anyone's money. Where the
  old portal billed another amount than the lines state, restate the lines on Fee Setup and refresh: students who paid the right
  amount leave the list, and none of it is credited or refunded.
- **The bank check** for the possible double charges of the old portal (Old Fees History, `docs/old-fees-double-charges.md`)
  before those students can be decided.
- **A second Bursary officer.** A request is never approved by the officer who made it.
- **Before the calendar moves on**, decide the session's overpayments (§8).

**Not in this build**, and not promised by any screen, notice or note of it:

- the wallet's overpaid money **used automatically** on the student's next school fees (the student applies it, or asks for a
  refund); a decision above the excess is therefore shown and kept back from refunds, not paid back into the session;
- the stopping of a **second payment** of school fees already paid: one open reference, "payment started", the bank's check and the
  checkout refusing a reference whose fees are paid, and the closing of sibling references on a confirmation. A repeated payment can
  still be made and is still recorded; this desk is where it is reconciled;
- a past session's excess read from the historical account; a two-officer reversal of a wallet credit; arrears as a test before a
  refund of an overpayment (the wallet's own refund keeps its arrears rule).
