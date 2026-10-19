# Interswitch's settlement report (V570)

Reconcile (`/finance/reconcile`) → **Interswitch settlement report**. A gateway pays a day's payments into the collections account in
one credit, less its charges. The settlement report lists each payment it settled. Uploaded, it ties each day to the bank's credit
and books the charges, which the Bursary otherwise does by hand on the collections statement (V552, V562).

## Reading the report

The CSV or Excel file is read in the browser. The header row is looked for in the first 40 rows, and the columns are recognised by
the names Interswitch's reports give them:

| Field | Column names recognised (any case, spacing or punctuation) |
|---|---|
| Day settled | Settlement Date, Settle Date, Value Date … — or the day the Bursary gives when the report has none |
| Day paid | Transaction Date, Payment Date, Date |
| The portal's reference | Customer Reference, Cust Reference, CID, PRN |
| WebPAY's transaction reference | Transaction Reference, Txn Ref, Merchant Reference |
| Payment Log Id | Payment Log Id, Log Id, RRN |
| Amount | Amount, Transaction Amount, Amount Paid |
| Fee | Fee, Charge, Commission, MSC |
| Paid over | Settlement Amount, Net Amount, Amount Settled |

A missing fee is the amount less what was paid over, and a missing net the amount less the fee. A row with no amount is left out.

## Matching (`finance.load_settlement_file`)

Each row is matched to the portal:

- by the reference, written with or without its hyphens;
- otherwise by WebPAY's transaction reference;
- otherwise by the Payment Log Id that Interswitch reported, or that the collections report carried.

| Result | Meaning |
|---|---|
| Matched | A payment the portal confirmed, for its amount |
| Amount differs | Confirmed for another amount |
| Not confirmed | Interswitch settled it, but the portal never confirmed the reference: the payer paid and may still be blocked |
| Not the portal's | No reference, transaction reference or Payment Log Id the portal knows |
| Settled before | Twice in the report, or in a report uploaded before |
| Reversal | A negative row |

A report whose every row was settled before is refused (`SETTLEMENT_FILE_AGAIN`).

## Tying a day to the bank's credit

For each day, the candidates are the unmatched credits on the collections statements of exactly the day's net. The credit may be
dated from the day before to a week after (`finance.settlement_candidates`).

When a day is tied (`finance.tie_settlement_day`):

- the line becomes the day's settlement;
- the day's payments count as in the bank. They leave "confirmed, not in the bank" (`finance.collections_not_received`), the
  reconciling items (`finance.bank_reconciliation_items`) and Internal Audit's morning alert (V569);
- Interswitch's fees are booked in the same press, Dr 5250 Bank charges / Cr 1010, dated on the credit's day and tied to the line
  (V562).

Ties are made one way or the other:

- **Tie N days with one credit** (`finance.tie_settlement_days`) ties every day that has one candidate, where no other day could
  take that credit;
- otherwise the Bursary picks the credit for a day.

**Take back** (`finance.untie_settlement_day`) reverses the fees journal on its own day and makes the line an unmatched credit again.
Nothing is tied or taken back in a signed month (`RECON_SIGNED_PERIOD`).

## A row the portal never confirmed

**Propose against the reference** records it as a bank credit and proposes it against that reference
(`finance.settlement_item_to_bank_credit`). A second officer approves it on the bank credits (V037), and the payment is confirmed.

## Who may

| Act | Bursar | Internal Audit | Students Account Officer, admin |
|---|---|---|---|
| Read the reports | yes | yes | yes |
| Upload and match a report | yes | yes | — |
| Tie a day (books the fees), take one back | yes | — | — |
| Propose a row to the bank credits | yes | — | — |

## Tests

- `db/check.sql` (V570) covers the following. The block undoes its writes.
  - The six results above: matched by reference and by transaction reference, not confirmed, not the portal's, amount
    differs, settled before.
  - Each day totalled, and only the credit of exactly its net within the week offered.
  - Both days tied in one press, the fees booked to 5250 and tied to each line.
  - The paid references no longer "not received" nor reconciling items.
  - A credit of another amount refused.
  - A tie taken back, its journal reversed and its payment "not received" again.
  - The never-confirmed row proposed once, and the same report refused when uploaded again.
- `SettlementFileIT` checks the same through the API, with each office's rights.
