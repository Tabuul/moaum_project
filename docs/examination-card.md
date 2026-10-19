# The examination card (V501, V567)

The student prints the examination card from the portal (Examinations), with every course on the semester's registration:
departmental, GST and EPS, carry-overs and deferred courses. It carries a signed code that can be verified.

## Who gets it (V567, the University's instruction of 19 October 2026)

Once a student has made the payment and registered courses, the card is theirs. Nothing else is asked:

| Asked | How it is read |
|---|---|
| Courses registered for the semester | a course registration for the session and semester, submitted, with at least one course on it (submitted, returned, approved or locked; a draft never submitted does not count) |
| School fees paid for the session | a confirmed school-fees payment for the session, of any amount, through any channel the portal records (a card or bank gateway, Pay on Quickteller, a bank credit, the NELFUND wallet applied, the old portal's history, a migration); `registration.exam_card_paid` |

Before V567 the card also waited for these, and none of them withholds it now:
- the registration to be approved;
- the Bursary's clearance scheme: an instalment or the whole session paid, nothing owed from an earlier session, the session's fee
  lines stated;
- the cards to be released with the timetable;
- the student record to be in study.

A payment made at a bank or on Pay on Quickteller counts once Interswitch reports it to the portal. Until then it is on Hanging
payments, and the Bursary imports the collections report or asks Interswitch to re-send.

## What a student sees when it is not yet theirs

| Code | Message |
|---|---|
| `EXAM_CARD_NO_REGISTRATION` | You have not registered courses for the semester. Register your courses, and the card is yours once your school fees are paid. |
| `EXAM_CARD_NOT_SUBMITTED` | Your course registration is not yet submitted. Submit it, and the card is yours once your school fees are paid. |
| `EXAM_CARD_NO_COURSES` | Your course registration carries no course. |
| `EXAM_CARD_NOT_PAID` | Your examination card is issued once your school fees for the session are paid. A payment made at a bank or on Quickteller shows once Interswitch reports it. |

## On the screens

- Examinations (`/student/exams`): each semester's card panel shows the server's answer; the notice above says the card is issued once
  the school fees are paid only when a card's code is `EXAM_CARD_NOT_PAID`. A paper is "Card withheld" only when that semester's card
  is withheld. Nothing on the screen reads the Bursary's clearance any more.
- The dashboard step and the registration screen offer the card for a submitted registration, not only an approved one.
- Registration approval (`/registration/approval`): the old "exam card immediately after approval" switch is no longer shown, since
  it decides nothing (the field is still stored).
- At the examination hall (`/verify/exam`): a genuine card is valid while the card's rule holds. It lists the courses of any submitted
  registration, as the card does, and shows "School fees: Paid / Not paid" from `registration.exam_card_paid` (it used to show "Cleared"
  from the clearance scheme).

## Who cannot get one, and why

Registration → **Exam cards** (`/registration/exam-cards`) lists every registration whose card is withheld, with the code, counted by
reason (`registration.exam_cards_withheld`; the session's payers read in one pass). The Bursar, Records, the Registrar and Deputy, the
Academic Office, the Students Account Officer, ICT and the administrator read it. Exams & Records, the Bursary and the Registry tell
the students why, once a day at most (`EXAM_CARD_WITHHELD`).

The GST & EPS examination permit keeps its own rule (the GST fee): [gst-eps-examination-permit.md](gst-eps-examination-permit.md).

## Tests

- `db/check.sql`, V567: no clearance scheme, no fee line stated, cards on release only and none released, an earlier session unpaid.
  A suspended student with a submitted registration and school fees paid has the card, and so does one whose only payment is the
  old portal's. An unpaid registration, or one paid only the GST fee, has none (not paid), nor does a draft (not submitted). The
  withheld list agrees with each card. V501's and V505's properties read the same codes.
- `ExamCardIT`: a submitted, unapproved registration has its card as soon as it is paid, and that card verifies at the hall as valid,
  with its course and the school fees paid. `CardsAndLoadDecisionsIT`: the withheld list
  and its reminder use the new codes.
