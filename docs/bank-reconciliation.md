# The bank reconciliation statement (V557, V562)

Reconcile (`/finance/reconcile`) → **Bank reconciliation**. For 1010 Bank — Fees collection or 1020 Bank — Disbursements, a
month's reconciliation sets the ledger's balance at the month's last day beside the balance on the bank's statement. It lists the
items between them and what is left unexplained:

| | Amount |
|---|---|
| Balance on the bank's statement at the month's last day | typed by the Bursary from the statement |
| each kind of item, with its effect on the bank's balance | + the ledger holds more, − the bank holds more |
| Adjusted balance of the bank | the statement's balance with the items |
| Balance on the ledger at the month's last day | every posting to the account up to that day |
| Difference left unexplained | the ledger less the adjusted bank |

## The items

They are found from what the statements matched: the collections statement on Reconcile (V552) and the disbursement statement on
Refunds & Credits (V545). The function is `finance.bank_reconciliation_items`.

| Kind | Account | Meaning | Effect |
|---|---|---|---|
| Receipts on the ledger, not yet in the bank | 1010 | A payment confirmed and posted, through the bank, that no line of a statement up to the month's end shows, no gateway day settled and no one reconciled by hand (V068) | + |
| Receipts through a channel that never passes the bank | 1010 | The same, confirmed through the old portal, a migration and the like: on the ledger's bank account, never in the bank | + |
| Money into the bank, not on the ledger | both | A credit the portal never confirmed, a payment received twice, a credit no one found, a transfer into the disbursement account | − |
| Money out of the bank, not on the ledger | both | The bank's charges, a debit no one found, a payout the ledger has not posted by the month's end | + |
| Payments on the ledger, not yet out of the bank | 1020 | A refund, a wallet withdrawal or a voucher paid on the ledger that no line shows | − |
| Amounts that differ | both | A line matched at another amount than the ledger's | the difference |
| NELFUND remittances not yet credited to students | 1010 | The part of a remittance the wallet has not credited to students by the month's end | − |
| Gateway charges not yet on the ledger | 1010 | A gateway's one credit for a day, short of the day's payments | + |
| Other money in or out on the ledger, not in the bank | both | Any other journal moving the account (a transfer between the accounts, an adjustment) | ± |

A paid voucher is found by its reference written in a debit of its amount. A journal that corrects the position brought forward is
no item: an opening balance, or the wallet's opening balance reclassified (V552). A reversed journal whose reversal falls in the
same span is no item either.

The items run from the start of the account's first reconciliation to the month's end. What came before is the opening position.
What is still outstanding from an earlier month is carried into the next.

## Booked in one press, or tied to a journal

A line the ledger does not hold is booked on its item (V562, `finance.book_statement_line_to`). The Bursary names the account
and says what the booking records, and **Book** posts the journal, dated the line's day, and ties the line to it.

| The line | Journal |
|---|---|
| Money out of the bank (the bank's charges, a debit no one found) | Dr the account named, Cr the bank account |
| Money into the bank (interest, a credit no one found, a payment received twice) | Dr the bank account, Cr the account named |
| A gateway's day settled short, or a payment at another amount | the difference, either way |

**5250 Bank charges**, added by V562, is offered first for the bank's and a gateway's charges. A bank account itself is refused:
a transfer between them is booked as a transfer.

A journal already posted (for example, a month's charges in one journal) can still be tied instead: **A journal already
posted…**, its number and what it records (`finance.book_statement_line`). The journal must be posted and must move the
statement's account.

**Transfers between the accounts.** A debit on one account's statement and a credit of the same amount on the other's within
three days, neither booked, are offered as a transfer (`finance.transfer_candidates`). **Book the transfer** posts Dr the account
it reached, Cr the one it left, and ties both lines to that one journal (`finance.book_transfer`).

Refused:
- a line matched to the portal or to a NELFUND remittance, or one the portal is still to confirm (it is confirmed through the bank
  credits);
- a line booked already.

**Take back** undoes the tie. A journal booked in one press is reversed on its own day, so the two cancel within the month, and a
transfer's other line is taken back with it. Nothing in a signed month changes.

## Prepared and signed

1. The Bursary prepares the month with the statement's closing balance and a note (`finance.prepare_bank_reconciliation`). It may
   prepare it again while it is unsigned. Periods of one account never overlap.
2. Another officer of the Bursary signs it (`finance.sign_bank_reconciliation`). Signing is refused:
   - by the officer who prepared it;
   - before the month has ended;
   - while a day of the month has no statement of the account;
   - while a transaction of the month waits to be posted on the ledger;
   - while a difference is left with no note to explain it.
3. A signed reconciliation is kept as signed, with its figures and its items. It downloads as Excel, and prints as a PDF with who
   prepared and signed it.

## The month closed on the ledger (V562)

A signed reconciliation closes its month on the ledger for its account:

- A journal posted by hand that moves the account with a date in the month is refused (`LEDGER_MONTH_CLOSED`, saying the first
  open day).
- What the ledger posts by itself for that month (a payment, a refund or a withdrawal recorded late with an earlier date) is
  posted on the first open day after it, its memo saying which day it belongs to (`finance.gl_open_date`).
- A posting to the account dated in the month, or the deletion of one, is refused whatever does it (triggers on
  `finance.gl_posting` and `finance.gl_journal`).
- Journals that move neither bank account are not affected, nor is the other bank account while its own month is open.

The check runs on every posting the ledger makes. It costs about 12 microseconds a posting to a bank account and 5 a journal,
measured.

Accounting → Overview → **Closed months** lists the signed months, the latest of each account marked.

1. One officer of the Bursary asks for the **latest** signed month of an account to be reopened, on a reason
   (`finance.request_reconciliation_reopen`; a later signed month must be reopened first).
2. Another officer reopens it, or keeps it closed on a note (`finance.decide_reconciliation_reopen`).
3. Reopened, the month is open on the ledger again, and its reconciliation goes back to prepared. The reason is added to its note,
   and the signed copy is kept with the request (`finance.bank_reconciliation_reopen`).

| | Bursary | Internal Audit, Deputy | Administrator |
|---|---|---|---|
| Read, closed months | yes | yes | yes |
| Prepare, sign (not one's own), book or tie a line, book a transfer | yes | — | — |
| Ask to reopen a month, decide (not one's own request) | yes | — | — |

## Reminders (V569)

Every morning at 08:20, while the watch is on, `finance.watch_bank_matching` tells the office whose act each thing is, by e-mail and
on the portal. Each thing is told once. **Reminders** on Reconcile shows what the alerts read now.

| Alert | To | When | Function |
|---|---|---|---|
| A month not reconciled | Bursar | An account's month has no signed reconciliation for every day by the set day of the next month (the 10th by default); told once for each account and month, naming how many months are behind | `finance.months_unreconciled` |
| A credit for a reference never confirmed | Bursar and Students Account Officer | A collections credit for a reference the portal issued and never confirmed, not sent to the bank credits a set number of hours (24) after its statement came; each line once | `finance.credits_waiting` |
| A payment not in the bank | Internal Audit | A payment confirmed on the portal through the bank that the collections statements do not show, though a statement runs a set number of days (3) past it: not one by one, not in a gateway's day settled or tied (V570), not reconciled by hand; each payment once, grouped by channel and day | `finance.payments_missing_from_bank` |

An account is watched once its first statement is loaded or its first reconciliation prepared. The Bursar sets the days, or
switches the alerts off (`finance.matching_watch`, `PUT /api/v1/finance/bank-reconciliation/watch`). What has been told is kept in
`finance.matching_told`.

## Tests

- `db/check.sql` (V557) runs on last month (always ended). It covers:
  - each item kind on both accounts with its effect;
  - the charges line tied to its journal, and the refusals to tie;
  - preparing with a difference: refused to its preparer and while unexplained, signed with a note, then kept;
  - a line in a signed month, an overlapping month and the running month refused;
  - the disbursement account signed with nothing left.
- `BankReconciliationIT` checks the same through the API, on a March of the last century of its own, with each office's rights.
- `db/check.sql` (V562) runs on last month too. It covers:
  - the transfer offered and booked from its two lines (Dr 1020, Cr 1010), its two amounts refused when they differ;
  - the charges and the interest booked in one press, and the refusals (an account that is a bank, a line booked twice, a
    line matched to the portal);
  - a booking taken back, its journal reversed, booked again;
  - the month closed once signed:
    - a journal by hand refused, one moving no bank account or only the other taken;
    - a payment recorded late posted on the first open day;
    - a posting and a deletion in the month refused, and a line in it not taken back;
  - reopening refused for an earlier month, twice, to the asker and without a note, then approved, the month open again and the
    signed copy kept.
- `BankReconciliationIT` (V562) does the same through the API on a March after every earlier run's, with each office's rights.
- `db/check.sql` (V569) reads a collections statement of this month on the 15th two months on. It covers:
  - this month signed and next month not: the Bursar told once, naming next month;
  - a never-confirmed credit not sent on: the Bursar and the Students Account Officer told;
  - a bank transfer on no line: Internal Audit told;
  - the next morning nothing told again; at 07:00 nothing run; with the day set to the 28th, nothing due.
- `BankReconciliationIT` (V569): Internal Audit reads the reminders and cannot set them; the Bursary sets them, and a day past the
  28th is refused.
