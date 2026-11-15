# Identity cards: staff cards in bulk (V698), the student card on the matriculation number (V699)

The University's word of 29 October 2026:

> add staff id card printing to chief security officer dashboard, let them be able to print all the staff id cards too

> they shouldnt be restriction for student id card, so far as the student has matriculation number, id card should be issued to the
> student, except is for replacement, they have to pay a fee for replacement

## Staff identity cards (V698)

**Who is in service.** A card is issued on the staff number to a member of staff in the University's service. That means one of:
* an office on the portal today;
* a place on the **HR staff register** (`hrm.staff_record`), which holds the non-teaching staff from the nominal roll. Most of them
  hold no portal office.

Before V698 only the first counted. On the copy of 21 October 2026, 870 of the 1,541 staff in service were on the register with no
office, and none of them could be issued a card. A staff number is still needed and someone who has left gets no card
(STAFF_CARD_NO_NUMBER, STAFF_CARD_ENDED), and since V765 nor does someone out of service in HR — every employment ended
(STAFF_CARD_LEFT). Someone neither in office nor on the register is refused (STAFF_CARD_NO_OFFICE). Since V765 a staff card has no end
date: it is valid while its holder is in service.

**The desk.** The Chief Security Officer's menu has **Staff ID Cards** under Services (`/credentials/idcards/staff`, `t/staffidcards`).
* **The list.** Every member of staff in service, with the rank, category, department or unit, faculty, whether a photograph is on
  file and the card in force (`credentials.staff_card_roster`).
* **Narrowing.** By faculty, department or unit, a search and with or without a card. It is done on the server and kept in the
  address.
* **Issue cards to all without one.** One act gives a card to everyone the narrowing holds who has none (`credentials.issue_staff_cards`):
  * someone with a card is passed over;
  * a refusal is counted by its reason;
  * each card is numbered as one issued alone.
* **Print all cards in force (PDF).** One PDF, a card (front and back) to a page, names A–Z, for the narrowing chosen
  (`/credentials/idcards/staff/pdf`). The crest and the signature are written into the file once and the pages are compressed: about
  9 KB a card, so every staff card in one file is about 15 MB.
* **One at a time.** Issue or Print on each row, as before.

HR and the other card-desk readers read the list. The Security Unit (and super) issue and print (GAP-005).

**The dashboard.** The Chief Security Officer's home has an **Identity cards** panel:
* the staff in service, the cards in force, those without a card and those without a photograph;
* **Staff ID cards**, **Print all staff ID cards**, **Issue the N missing** and **Student ID cards**.

**What the card prints.** A non-teaching member of staff's card prints the rank, "Non-teaching" and the unit the HR register gives.
On the copy, only 3 staff photographs are on file: a card without one prints with a blank frame until HR adds it.

## The student card (V699)

**The first card on the matriculation number.** The matriculation number alone decides a student's first card.
* **No longer conditions:** the official photograph, being in study and the school fees (the scheme in force, earlier sessions paid
  in full).
* **Shown as warnings** under the desk's eligibility instead, never held against the card. A card without a photograph prints with a
  blank frame.
* **A student who has left** (graduated, withdrawn) is shown as such, but the card is not refused.

**A replacement on its fee.** Any card after the first is a replacement and is printed once the student has paid the replacement fee:
* a replacement of the card in force (lost, damaged, a name or programme change…);
* a new card after one was ended.

How it works:
* **Setting the fee.** The Bursary sets it on Fee Setup (**Student identity card · replacement fee**, `finance.fee_setting.id_card_replacement_fee`).
  There is no default: until it is set, no replacement is printed.
* **Paying.** The student pays it on their portal (**Identity Card → Replacement card → Pay replacement fee**). The reference is
  labelled "Identity card replacement fee" and classed with the identity card fee (ID_CARD).
* **One payment, one card.** The desk prints the replacement on the paid fee, and the payment is linked to the card
  (`credentials.identity_card.replacement_payment_id`). Another replacement waits on another payment.
* **Refused** (ID_CARD_REPLACEMENT_FEE) when no fee is paid, saying the amount.
* **Free:** printing the card in force again (a printer jam).

The desk's eligibility says whether a new card is a replacement and whether its fee is paid. The student's page says what the
replacement costs, or that it is paid and the card is to be collected.

## Tests

* `db/check.sql`: V698 and V699, with the V605 block restated for V699.
* `StaffIdCardsIT`.
* `IdentityCardDeskIT` (restated for V699).
* `lib/staff-cards.test.ts`, `lib/idcard-desk.test.ts`, `lib/pdf-write.test.ts`.
