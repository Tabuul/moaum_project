# The collections statement matched (V552)

The fees collection account's bank statement is matched to what the portal received, as V545 matches the disbursement account's
to what was paid out. Reconcile (`/finance/reconcile`) → **Collections statement**: the Bursary or Internal Audit (and the Deputy)
uploads the bank's CSV or Excel file. The screen finds the header row and the date, narration, reference, debit and credit columns
(or one signed amount), as for the disbursement statement (`lib/bank-statement.ts`).

## How a credit is matched

`finance.load_collections_statement` looks for a portal reference in each credit's reference or narration, as a bank writes it:
`MOAUM-FEE-123456-1234`, `TRF/MOAUM-FEE-123456-1234/…` or without its hyphens (`MOAUMFEE1234561234`). It looks among the
references issued from 180 days before the statement's first line to two days after its last. A payment confirmed through a
channel that never passes through the bank is not looked for: the old portal's history, a migration, the wallet applied to fees,
an overpayment carried, or the demo's (`finance.receipt_through_bank`).

| Result | Meaning | What follows |
|---|---|---|
| **Matched** | A payment the portal confirmed, the same amount | Its reconciliation is recorded MATCHED (V068) |
| **Amount differs** | A payment the portal confirmed, another amount | A DISCREPANCY is recorded with both amounts |
| **Received, not confirmed** | A reference the portal issued and never confirmed: the student paid and may still be blocked | The Bursary proposes it against that reference as a bank credit; another officer approves it on the exceptions desk (V037), which confirms the payment |
| **Paid twice** | A reference already credited by an earlier line of the same statement | A credit for the student (a refund or the wallet), raised as usual |
| Matched (NELFUND) | A NELFUND remittance by its reference in the line, or by its amount within seven days of the day it was received | — |
| **Not found** | No portal reference and no remittance | If it is a gateway's one credit for a day, it is marked that day's settlement |
| Money out | A debit | — |

## A gateway's day

Interswitch and the card gateways pay the money of many payments into the account as one credit. The payments the portal
confirmed in the statement's period, through the bank, that no line found and no one reconciled are listed by channel and day
(`finance.collections_unmatched`). On a **Not found** credit the screen offers those days, the closest total first. Marking the
credit as one day's settlement (`finance.settle_collections_line`) reconciles each payment of that day against it. The difference
is shown: the gateway's charges, or more than the payments.

## Confirmed on the portal, not in the bank

What remains after the lines and the settlements is listed one by one (`finance.collections_not_received`): the payment, the
payer, the channel and the amount. The screen shows the first 500; the days above count them all. A payment reconciled by hand
before (V068) is not listed. The result downloads as Excel.

## Who may do what

| | Bursary | Internal Audit, Deputy | Administrator |
|---|---|---|---|
| Read statements | yes | yes | yes |
| Upload a statement, mark a settlement | yes | yes | — |
| Propose a credit against its reference | yes | — | — |
| Approve the proposal (bank credits, not the proposer) | yes | — | — |

Statements are kept (`finance.bank_statement` with `account_kind = 'COLLECTIONS'`, its lines in `finance.bank_statement_line`,
both audited). The disbursement statement list shows only disbursement statements.

Interswitch's own settlement report ties a day to its credit and books the charges, without choosing the channel and day by hand:
[interswitch-settlement.md](interswitch-settlement.md) (V570).

## Tests

- `db/check.sql` (V552) covers every result above: a reference without its hyphens, a NELFUND remittance, a gateway's day
  settled (NGN 50 of charges), and the not-received list without the old portal's payment or one reconciled before. The
  unconfirmed credit goes to the bank credits once, and a second officer's approval confirms it.
- `CollectionsStatementIT` checks the same through the API, with each office's rights.
