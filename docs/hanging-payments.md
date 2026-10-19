# Hanging payments (V037, V480, V490, V568)

Finance → **Hanging payments** (`/finance/hanging`) is where the Bursary and the Students Account Officer see payments the gateways
have not settled. Each figure opens the transactions behind it, with who paid: name, number, programme, department, level and the
phone and e-mail on record. The list downloads as Excel.

| Figure | What it counts |
|---|---|
| Hanging now | A checkout opened in the last three days with nothing confirmed, leaving out the checkouts nobody went on to pay |
| Resolved without a person | Settled in the last three days by Interswitch's notification, the sweep or a request to the gateway |
| Needs a person | Money against no reference or short, a reversal, a gateway silent, a notification not settled, a payer's receipt to settle |
| Abandoned (V568) | Checkouts of the last fortnight nobody went on to pay |

## Abandoned checkouts (V568)

A checkout is abandoned when it is the latest checkout of its reference and all of these hold:

- it is unconfirmed and older than the desk's abandon clock (24 hours by default);
- no receipt was reported for it, and nothing came from Interswitch about it;
- one of the following is true:

| Rule | Meaning |
|---|---|
| Never taken to Quickteller | Opened on Pay on Quickteller, and Quickteller never asked after the reference since. A payer who goes on to pay, on the page or at a bank, makes Quickteller ask first. |
| The gateway said not paid | A card checkout whose gateway's last answer was that it was not paid |
| Told, no answer | Its payer was told (below) that long ago, and has neither reported a receipt nor gone to Quickteller with it since |

Nothing is stored or cancelled. Anything that happens next brings the checkout back: Quickteller asking, a receipt, a payment. The
Bursar's daily e-mail of Pay on Quickteller payments Interswitch has not reported, and the Ask Interswitch list, leave abandoned
checkouts out too (`finance.paydirect_unreported`). The function is `finance.abandoned_checkouts`.

## Telling the payers (V568)

"Tell N payers" on the Needs a person and Hanging now lists tells each payer what their case asks of them. Messages go by e-mail, SMS
and on the portal through the notification engine. A postgraduate or JUPEB applicant is told by their own portal's message. Each
payer is told once per case and reference (`finance.payer_told`).

| Case | Who | What they are told |
|---|---|---|
| Short paid | Less than the reference asks was reported, not resolved | The reference stays open and the payment is with the Bursary. Do not pay it again; contact the Bursary with the receipt. |
| Reversed | Interswitch reported a reversal, not resolved | Check whether the money came back, and contact the Bursary before paying again |
| Payment not reported | A Pay on Quickteller checkout of the last three days, hanging past the tell clock (24 hours), not abandoned, no receipt reported | If you paid, enter the receipt's Payment Log Id where you pay; if not, pay when ready |

A payer with no e-mail or phone on record is counted as unreached and is told once an address is on record. Each row of a list
shows when its payer was told, and of what. The functions are `finance.payers_to_tell` and `finance.tell_payers`; the templates are
`PAYER_SHORT_PAID`, `PAYER_REVERSED` and `PAYER_CHECKOUT_HANGING`.

## Who may

| Act | Bursar | Students Account Officer | ICT, admin | Internal Audit, Registry, VC/DVC |
|---|---|---|---|---|
| Read the desk and its lists | yes | yes | yes | yes |
| Ask a gateway, resolve an event, mark a receipt not found | yes | yes | yes | — |
| Tell the payers | yes | yes | — | — |
| Set the clocks (abandoned after 2–336 hours, told after 1–72) | yes | yes | — | — |

## Tests

- `db/check.sql` (V568) covers the following. The block undoes its writes.
  - A checkout never asked after is abandoned and off the unreported list; a card checkout the gateway said was not paid is
    abandoned.
  - A checkout with a receipt reported is not abandoned and stays on the unreported list.
  - Short payments, reversals and hanging payers are told once; a second press tells no one.
  - A payer told with no answer for a day is abandoned, and Quickteller asking again brings the checkout back.
  - With the clock at 48 hours, a 30-hour checkout is not yet abandoned.
- V477's, V480's, V490's and V522's Pay on Quickteller payments now have Quickteller's check of their reference, as a payment does.
- `PaymentsIT` checks the same through the API, with each office's rights.
