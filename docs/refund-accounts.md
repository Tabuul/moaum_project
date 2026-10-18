# Refund accounts (V528, V533, V534, V540)

A refund is paid only into a full account on record — the bank, the name on the account and the ten-digit account number
(NUBAN) — kept in `finance.refund_account`. The refund itself keeps a snapshot: the bank, the account name and the last four
digits. The database refuses to mark a refund paid without an account (`REFUND_NO_ACCOUNT`).

## Where the account comes from

| Source | Who | When |
|---|---|---|
| `STUDENT` | the student, on their fees page, for a refund of overpaid school fees (V528) | while the refund awaits approval (and may change it then), or once after approval when none was given |
| `DESK` | the Bursary, on Refunds & Credits — when raising a refund, or with **Record the account** / **Change the account** | while it awaits approval; on an approved refund the account goes back for approval unless it only completes the account the approver saw (the same bank and last four digits) |
| `JUPEB` | a withdrawn JUPEB candidate, on the JUPEB portal, for their refund claim | taken over when the Bursary raises the refund on the claim |

An account the desk recorded is approved by another officer than the one who recorded it (`REFUND_ACCOUNT_SAME_OFFICER`), as a
refund is approved by another officer than the one who raised it. No account changes once a refund is paid or rejected
(`REFUND_ACCOUNT_CLOSED`).

## The number checked against the bank

`finance.bank` lists the banks, with the code the Central Bank gave each. For a bank whose numbers are checked, the tenth digit
of the account number must be the NUBAN check digit of the bank's three-digit code and the first nine digits (weights 3, 7, 3
repeated; ten less the last digit of the sum, 0 for 10). The CBN's own example: bank 011, serial 000001457 → 0000014579. A
number one digit off, or given with the wrong bank, is refused (`REFUND_ACCOUNT_CHECK_DIGIT`) — on the screen as it is typed and
by the database when it is sent.

- Checked from the start: the established commercial banks (Access, Citibank, Ecobank, Fidelity, First Bank, FCMB, GTBank,
  Keystone, Polaris, Stanbic IBTC, Standard Chartered, Sterling, Union, UBA, Unity, Wema, Zenith; Access (Diamond)).
- Listed, not checked: newer commercial and non-interest banks (their codes not yet confirmed), microfinance banks, and payment
  service banks such as OPay and PalmPay, whose account numbers are often the phone number. Ten digits is all that is asked.
- A bank not on the list may be typed by name; its number is checked for ten digits only.

The Bursary keeps the list on Refunds & Credits → **Banks refunds are paid into**: switch the check on or off for a commercial,
non-interest or merchant bank with a three-digit code (never a microfinance or payment service bank), set a bank aside, rename
one, or add one with its other names.

## Marking a refund paid (V534)

**Mark paid** asks for the bank transfer reference (4 to 60 letters and digits, as on the bank's confirmation) and the date the
money left — not after today, not before the refund was approved (`finance.pay_refund(id, reference, paid on)`). The database
refuses PAID without them (`REFUND_PAID_EVIDENCE`). The student (a refund of overpaid fees) and the JUPEB candidate are told the
reference and the date, and see them on the fees page or the JUPEB portal. The refunds desk shows them on each paid refund and
says when the same reference was recorded on other refunds, so Internal Audit can match every refund to the bank statement.

## Other accounts money is paid out to (V534)

A withdrawn JUPEB candidate's refund claim and a student's NELFUND wallet withdrawal take the same bank list and the same check
when the account is given (a trigger on `jupeb.refund_claim` and on `finance.wallet_withdrawal`, through
`finance.checked_account`): ten digits, the check digit at a checked bank, the bank written as it is listed. Accounts given
before V534 are left as they are.

## Wallet withdrawals paid with evidence (V540)

A NELFUND wallet withdrawal is paid, like a refund, with the bank transfer reference and the date the money left — not after
today, not before it was approved (`finance.pay_withdrawal(id, reference, paid on)`; `WALLET_PAID_EVIDENCE` without them). The
student is told both; the NELFUND desk's withdrawals and the student's wallet show them.

## The ledger date (V540)

The general ledger posts a paid refund on the day the money left (`paid_on`), the day it was recorded where that is not known.
Journals posted before V540 are not moved. Wallet withdrawals are not on the general ledger.

## Paid out (V540)

Refunds & Credits → **Paid out**: every refund and wallet withdrawal paid in a period of up to a year, by the day the money left
(`finance.paid_out(from, to)`, `GET /api/v1/finance/refunds/paid-out`) — the payee, the account it went to, the amount, the bank
transfer reference, who approved and who paid it — with **Also on N other** where the same reference was recorded on other
payments. Excel and PDF go through the export engine, on the export log. The Bursary, Internal Audit and admin read it.

## The name on the account

When the name on the account shares no word of three letters or more with the student's (or the JUPEB candidate's, or the
payer's) name, the student's form and the refunds desk say so (**Name differs**). It is a warning, never a refusal.
