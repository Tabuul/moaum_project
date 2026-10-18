# The bank reconciliation statement (V557)

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

## Accounted for with a journal

When the Bursary has booked a journal for a line, the line is tied to it on the item (journal number and what it records;
`finance.book_statement_line`), and neither is an item any more. Examples: the bank's charges, a transfer between the two
accounts, a difference put right.

- The journal must be posted and must move the statement's account.
- A line matched to the portal, or one the portal is still to confirm, is not tied to a journal: it is confirmed through the bank
  credits.
- **Take back** undoes the tie.
- Nothing in a signed month changes.

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

| | Bursary | Internal Audit, Deputy | Administrator |
|---|---|---|---|
| Read | yes | yes | yes |
| Prepare, sign (not one's own), tie a line to a journal | yes | — | — |

## Tests

- `db/check.sql` (V557) runs on last month (always ended). It covers:
  - each item kind on both accounts with its effect;
  - the charges line tied to its journal, and the refusals to tie;
  - preparing with a difference: refused to its preparer and while unexplained, signed with a note, then kept;
  - a line in a signed month, an overlapping month and the running month refused;
  - the disbursement account signed with nothing left.
- `BankReconciliationIT` checks the same through the API, on a March of the last century of its own, with each office's rights.
