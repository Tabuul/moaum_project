# An expired payment reference regenerated (V635, 22 October 2026)

The University asked that a student whose payment reference has expired can regenerate it and pay. This covers school fees, the GST
fee and every other payment the student started.

## Why

Every reference a student pays against (`finance.payment_reference`) is payable for 24 hours. The gateways refuse an expired one:
the card checkout answers `PAY_REFERENCE_EXPIRED`, and PAYDirect answers status 1.

School fees and the GST fee could be generated again once the last reference expired. Every other payment kept its first reference
for good, so the student was stuck:
- the deferment application fee (`people.deferment_fee_start` returns the pending fee, with its expired reference);
- a transcript or document request (`credentials.transcript_request.reference`; the Transcripts list also offered no pay button
  once the reference expired);
- the inter-departmental transfer fee (`people.transfer_application.fee_reference`);
- the hostel bed, a hostel damage charge, a hostel fine, a library fine and a wallet top-up.

Several of these are matched by the reference itself when the payment is confirmed: the hostel allocation, the damage charge, the
library fine and the deferment fee. A second reference for the same item would never reach it.

## The rule: `finance.renew_reference(student, reference)`

- **The same reference is reopened** for another 24 hours, once what it pays for is still owed:
  - the transcript request is unpaid and open;
  - the bed is still held for the student, and the reference never outlasts the hold;
  - the damage charge, the hostel fine or the library fine is unsettled and not waived;
  - the deferment fee is pending;
  - the transfer is still under way;
  - the wallet top-up is still allowed for that amount;
  - for school fees, the fees are still owed and the payment window is open, as for any new school-fees reference;
  - for the GST fee, the fee is still owed.

  Whatever finds the payment by its reference still finds it. A card payment begun before the reference expired and settled late is
  never a second payment.
- **A new reference** is made for school fees or the GST fee when what is owed now is less than the old reference, because part was
  paid since. It is made by the usual functions (`finance.new_reference`, `finance.new_gst_reference`).
- **An open reference** for the same thing is returned instead of making a second one.
- **Refused, with the reason:**
  - a paid reference (`REFERENCE_PAID`);
  - another student's reference (`REFERENCE_NOT_FOUND`);
  - an item that is closed: the request cancelled, the fine waived, and so on (`REFERENCE_ITEM_CLOSED`);
  - a bed whose hold has ended (`REFERENCE_HOSTEL_HOLD_ENDED`);
  - nothing owed (`REFERENCE_NOTHING_OWED`);
  - a payment an office raised, such as the Bursary's gateway test (`REFERENCE_NOT_RENEWABLE`).

The audit trail records each reopening as a change to the reference's expiry, in the student's name.

## On the screens

- **Every pay block** (`PayByCard`) handles expiry the same way. It is used on Fees, GST & EPS, Documents and Transcripts, Deferment,
  Transfer and Wallet.
  - On an expired reference it shows **"Reference … has expired"** with **Regenerate**.
  - Once regenerated, the same reference can be paid at once, or the new reference is shown with its own pay button.
- **Fees → Payment History** lists every reference the student has.
  - An expired, unpaid row has **Regenerate**.
  - An open row has **Pay**, which opens the pay block for that reference: school fees, GST, a transcript, a hostel bed or a fine.
  - A paid row keeps its **Receipt**.
- **GST & EPS → GST payment history**: an expired row has **Regenerate** while the fee is still owed.
- **Deferment**: an expired fee shows the pay block, which offers Regenerate. Starting a second fee no longer leads back to the
  expired one.

## API

- `POST /api/v1/me/fees/references/{reference}/renew` returns `{reference, amount, expiresAt, purpose, outcome}`.
  - `outcome` is `REOPENED`, `NEW` or `OPEN`.
- `GET /api/v1/payments/state` gains `expired`, `expiresAt` and `renewable`.
  - `renewable` is true for a student's own reference.

## Tests

- **check.sql V635**, on a made-up student:
  - an expired deferment-fee reference with the fee pending is reopened as the same reference for a day;
  - asked again, it is answered as open;
  - another student, a paid reference, a closed request and an office's payment are each refused.
- **`PaymentReferenceRenewIT`**, through the API:
  - an expired school-fees reference shows as expired and renewable, and another student is refused;
  - it is reopened as the same reference, and asked again it is answered as open;
  - after part payment it is replaced by a new reference for the ₦60,000 still owed;
  - a paid reference is refused.
