# The Security Unit's student identity card desk (V605)

This is the implementation report for the brief *Security Unit — student ID card management, eligibility, printing, issuance
& reprint* (21 October 2026). The portal already had the card; V605 gives the Security Unit the desk the brief describes and
makes the one rule explicit: **a student ID card is not student clearance.**

## 1. What was there, and what was reused

| Need | Existing piece, kept |
|---|---|
| The card register | `credentials.identity_card` (V027): one number `MOAUM/ID/YY/NNNNN` from `platform.next_number`, keyed on the matriculation number, one live card a student, ended with a reason, never deleted; on the audit spine |
| Who prints and issues | the Security Unit alone (GAP-005, 16 Oct 2026); the Library, Registry, Academic Office, Records and ICT read |
| The printable card | the PDF engine's card (`lib/idcard-pdf`, `/credentials/idcards/student/pdf?id=`) with the University's design and crest, the photograph, and a QR carrying the signed check address (`/verify/idcard`, V360/V435) |
| The photograph | `people.student_photo`, else the admission's passport document, else the attachment store — the order the portal serves it in (`StudentPortalService.passportImage`) |
| The matriculation number | `people.student.matric_no`, issued by matriculation and never touched here |
| The school fees | finance's own word: `finance.fee_stated`, `finance.position` and `finance.clears(student, session, 'ID_CARD')` — the scheme the Bursary puts in force (`policy.clearance_scheme` / `policy.clearance_rule`, the instalment the card is released at) |
| Verification | `/verify/idcard?no=&c=` answers with the University's record for a signed code |
| The student's own page | Identity card: status, never the card itself |
| Audit | the audit spine on the register; `credentials.event` for the acts |
| Export | `brandedXlsx` / `brandedPrint`, S/N first, the University heading |
| RBAC | office authorities on every endpoint (`OFFICE_security`, `OFFICE_super` act; the readers read) |

The card was never gated by the office-by-office clearance workflow (`clearance.*`, V013/V415): the gate was the Bursary's fee
scheme, which is finance's. But the refusal said "the Bursary has not cleared this student", nothing said why a student was not
eligible, nothing separated printed from handed over, a replacement carried no reason code and no link to the card it replaced,
and the desk had no search, no eligibility reading and no report.

## 2. Eligibility — `credentials.id_card_eligibility(student)`

One reading, every failing check a reason in words:

| Check | Source | Reason when it fails |
|---|---|---|
| in study on the register | `people.student.status` ADMITTED, ACTIVE, PROBATION or DORMANT | "The record has graduated: no new card is issued; the cards held stay on the record" / "Not in study on the register (…)" |
| matriculation number | `people.student.matric_no` | "Matriculation number not yet issued" |
| official photograph | `credentials.has_photo` — the three places the portal keeps one | "Student photograph is missing" |
| school fees, the latest session the record shows the student in (an enrolment or a submitted registration) | `finance.fee_stated` and `finance.clears(…, 'ID_CARD')` — released by the scheme in force | "Required school-fee condition not satisfied: the school fees for … are not yet stated / are not paid as the scheme in force requires for the card" (or: the record shows no session in study) |
| school fees, from the first session | every earlier session on the record with stated fees, `finance.position` paid in full (the fee engine states a past session by the student's current level, as it does everywhere) | "Required school-fee condition not satisfied: school fees outstanding for … — the card is issued to a student who has paid from the first session" |

Clearance is not read and is never a reason: a student with clearance incomplete, or never started, is eligible when the five
checks hold (tested). The Security Unit changes nothing in finance: it reads the eligibility result, nothing more; no manual
"paid" flag exists.

## 3. The lifecycle

| State | Meaning |
|---|---|
| (none) | not printed |
| `PRINTED` | made and printed — a number drawn, `printed_at` / `printed_by`, `print_count`; awaiting collection |
| `ISSUED` | handed to the student — `collected_at` / `collected_by`; in force |
| `LOST`, `DAMAGED`, `REPLACED`, `RETURNED`, `REVOKED`, `CANCELLED` | ended with `ended_at` and a reason; the record stays |

- `credentials.print_identity_card(student, replace_reason, note)` — the student's row locked (two clicks make one card; a
  partial unique index allows one live card a student), eligibility read again, then: the live card printed again and counted;
  or, on a reason from the list (lost, damaged, name correction, programme change, matriculation correction, photograph update,
  security replacement, expired, other — "other" with a note), the live card ended and a new number drawn, `version` +1,
  `previous_card_id` and `replacement_reason` kept.
- `credentials.collect_identity_card` — the printed card handed over. `credentials.end_identity_card` — lost, damaged, returned,
  revoked or cancelled, on a reason.
- The old doors keep their names: `credentials.issue_identity_card` prints and hands over in one act (the student's own page and the
  older desk call it); `credentials.report_card_lost` ends the live card as LOST.
- Every act is an event on `credentials.event` (`ID_CARD_PRINTED`, `ID_CARD_ISSUED`, `ID_CARD_REPLACED`, `ID_CARD_LOST`,
  `ID_CARD_DAMAGED`, `ID_CARD_RETURNED`, `ID_CARD_REVOKED`, `ID_CARD_CANCELLED`) with the actor, the office, the states and the
  note; the register's rows are on the audit spine. No secret is ever written.
- Card numbers are never reused: `platform.next_number` only counts up, and `card_no` is unique.
- A graduated or withdrawn record is issued no new card; its cards stay traceable to it. A programme change keeps the old card
  and the desk replaces it on the "programme change" reason.

## 4. The API (`/api/v1/credentials/identity-cards`)

| Method | Path | Who | Does |
|---|---|---|---|
| GET | `/students/search?q=&page=&size=` | readers | matriculation, JAMB or admission number, name, phone or e-mail; a page at a time (at most 50) with the live card and the eligibility reading |
| GET | `/students/{id}` | readers | the particulars, whether a photograph is held, the eligibility, the live card with its signed check address, every card and every act |
| GET | `/students/{id}/eligibility`, `/students/{id}/history` | readers | the reading; the cards and the acts |
| GET | `/students/{id}/card`, `/students/{id}/photo` | issuers; readers | the printable card (PRINTED or ISSUED); the photograph of a matriculated student |
| POST | `/students/{id}/print` `{replaceReason?, note?}` | Security Unit, super | printed, printed again, or replaced on a reason |
| POST | `/students/{id}/collect` `{note?}` | Security Unit, super | handed over |
| POST | `/cards/{cardId}/end` `{state, reason}` | Security Unit, super | ended |
| GET | `/report?session&fac&dept&prog&level&status&cardState&printedFrom&printedTo&issuedFrom&issuedTo&printedBy&page&size&export` | readers | the report |
| POST | `/students/{id}/issue`, `/students/{id}/lost` | Security Unit, super | the old doors, kept |

Every refusal carries its code (`ID_CARD_NOT_ELIGIBLE` with the reasons, `ID_CARD_REASON`, `ID_CARD_ALREADY_ISSUED`,
`ID_CARD_NOT_PRINTED`, `ID_CARD_ENDED`). The Library and the other readers get 403 on every act.

## 5. The screens

- **Security Unit → Student ID Card** (`/credentials/idcards`): SEARCH STUDENT; the results (S/N, student, JAMB, faculty and
  department, programme, level, session, status, school fees satisfied or not, the card's state, VIEW); the student — the
  photograph, the particulars, the eligibility (ID CARD ELIGIBLE with the checks met, or NOT ELIGIBLE with the reasons), VIEW ID
  CARD (the front and the back on screen; the number assigned when printed), PRINT ID CARD → PREPARING ID CARD... → ID CARD
  PRINTED SUCCESSFULLY and the print opens, PRINT AGAIN, ISSUE ID CARD, REPLACE CARD… (the reason from the list and a note), END
  CARD… (lost, damaged, returned, revoked, cancelled, with a reason), the print and what a scan shows; the history — every card
  with its version, prints, printed and issued by whom and when, the reason, the card it replaced — and every act. A student named
  in the address (`?student=`) opens at once. The card register and the staff cards stay below.
- **Security Unit → ID Card Report** (`/credentials/idcards/report`): the filters the brief lists, the table, Excel and PDF.
- The student's own page says "printed — collect it from the Security Unit" for a PRINTED card and names the school-fee condition,
  not clearance; `/verify/idcard` says a PRINTED card is not yet collected.
- Student 360° → Documents lists every card with its version, printed and issued dates, state and replacement reason.

## 6. Tests

- `IdentityCardDeskIT`: eligible with no clearance started (the word never appears); the reasons for a missing photograph, a
  missing matriculation number and an earlier session unpaid; the search by matriculation number, JAMB number and name; the Library
  refused a print and an end; printing blocked with the reason; two concurrent prints make one card (print count 2); the print,
  the photograph and the desk's view; handed over once; a replacement refused without a listed reason and made on one, the old
  card ended and linked, version 2; the history; the report; the student's own view; finance moving; a graduated record keeps its
  cards and gets no new one.
- `check.sql` V605: the same in the database alone, with the one-live-card index and the old door.
- `lib/idcard-desk.test.ts`: the words, the reading never naming clearance, the actions by state.

## 7. Needing the University's configuration

- The fee scheme in force decides what "school fees paid" means for the current session (the instalment the card is released
  at); the Bursary sets it on the scheme. Nothing else needs configuring.

## 8. The printed cards redesigned, the Chief Security Officer's signature and the blood group (V622)

The University reviewed the printed cards (21 October 2026).

**The design** (`lib/idcard-pdf.ts`, both cards)
- The University's name is set larger and bolder, with the card's title under it: **STUDENT IDENTITY CARD** or **STAFF IDENTITY
  CARD**. The red tag under the photograph is gone.
- The cards are told apart by colour: the student card in the University's blue, the staff card in its green (the header, the
  back's strip and the card's faint pattern).
- Less empty space: the photograph is larger, the name, number and fields are set larger, and the fields are spread down to the
  photograph's foot (the staff card's down to its foot).
- The back's write-ups are centred: the strip, the barcode and its number, the conditions line by line, and (on the staff card)
  the QR with the serial and the address under it.
- The back is signed for the University by the **Chief Security Officer**, not the Registrar. The signature prints above the line
  with the paper's white dropped, so only the ink shows; the officer's name, when set, sits between the line and the title.

**The signature** (`credentials.card_signatory`, `CardSignatoryController`)
- Uploaded by the Directorate of ICT under **Institution Profile → Identity card signature**: the officer's name and a PNG or JPEG
  scan of the signature (at most 1 MB), replaced or removed there. The database lets only ICT (and super) set it.
- Kept as uploaded and as a JPEG on white for the PDF engine, in the file store when one is configured and in the row otherwise.
- Never public, unlike the logo: only ICT, the Security Unit and super read it. The card's print reads it with the printing
  office's sign-in; without one, the card prints the line and the title alone.

**The blood group**
- A student's is the record's own: the biodata field `blood_group`, which the biodata form already asks, or the health profile's
  where the biodata holds none.
- A member of staff's is held for the card in `credentials.staff_card_detail`.
- The card desk adds or corrects either: on the student's panel (**Add / Correct the blood group**, then **SAVE BLOOD GROUP**) and
  on the staff cards' list (**Add / Change**). It is one of A+, A-, B+, B-, AB+, AB-, O+, O-; the database reads the common
  spellings ("O positive", "o+ve", "0+") as one of these and refuses anything else (`CARD_BLOOD_GROUP`).
- Only the Security Unit (and super) set it (`credentials.set_blood_group`). Both cards print it.

**API**
- `GET/PUT /api/v1/credentials/identity-cards/signatory`; `GET /signatory/signature?format=jpeg`; `DELETE /signatory/signature`.
- `PUT /students/{id}/blood-group`, `PUT /staff/{personId}/blood-group` (`{bloodGroup}`).
- `blood_group` on the desk's student view, on both printable cards and on the staff cards' list.

**Tests:** check.sql's V622 block; `CardSignatoryIT`; `lib/idcard-desk` tests.
