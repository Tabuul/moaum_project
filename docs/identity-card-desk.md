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

## 9. The cards redrawn to the University's new design (12 November 2026)

The University sent the design of both cards, front and back, to be followed exactly: the student card in navy, the staff card
in green, with gold and red swooshes across the header and the foot.

**One drawing, two ends.** The design is drawn once (`lib/idcard-design.ts`) on a drawing surface (`lib/card-surface.ts`) that
writes either the PDF the desk prints (`PdfSurface`, through `lib/idcard-pdf.ts`) or the SVG the desk shows on screen
(`SvgSurface`). The desk's **VIEW ID CARD** is therefore the print itself, not a sketch of it: the same shapes, colours,
sizes and wrapping. The units are tenths of a millimetre of an ID-1 card (856 × 540 landscape, 540 × 856 portrait).

**The student card (landscape)**
- Header: the crest on a white disc, the University's name in condensed serif capitals over MAKURDI between gold rules, and a
  navy tab on the right with a gold cap, **STUDENT / IDENTITY CARD**; gold and red swooshes under the header.
- Body: the photograph in a navy rounded frame; the name in navy capitals; the matriculation number on a red pill; the
  particulars in two columns with icons — Faculty, Programme, Admitted on the left, Level, Blood group, Graduates on the right.
- Foot: a navy band under a gold swoosh carrying **SESSION**, **VALID UNTIL** and **ID NO.** (the card's number), each with
  its icon.
- Back: the navy strip **PROPERTY OF THE UNIVERSITY - NOT TRANSFERABLE**; the barcode in a white panel with the matriculation
  number under it; **CONDITIONS** on a navy pill and the three conditions with check marks; the verification QR with the
  card's number and the emergency contact; the Chief Security Officer's signature, name and title; the gold, red and navy foot.

**The staff card (portrait)** has the same parts in green: the header with **STAFF IDENTITY CARD** on a red pill, the
photograph centred, the name and the staff number on a red pill between rules, Rank, Unit (or Department), Appointed and
Office on the left and Category, Faculty and Blood group on the right, and **VALID UNTIL** and **ID NO.** on the foot. Its back
carries the gold-lettered strip, the barcode with the staff number, the conditions with shield marks, the QR in a green frame,
the card's number, **Km 1 Gboko Road, Makurdi** with a pin, and the signature.

**What changed besides the look**
- The barcode carries the number exactly as printed under it (`MOAU/SS/LIS/25/83810`, slashes and all); it used to carry the
  number with its punctuation removed. Nothing in the portal reads the barcode; the QR remains the card's verification.
- The conditions are three lines, as the design sets them ("Loss must be reported…" apart from "Any alteration…").
- The staff card's back says where a found card goes with the pin and the address, without the words "If found, return to the
  Security post".
- A long name takes two lines (the staff card's photograph gives way a little to it) and every word of it is printed, measured
  as it is drawn; only a name too long for two lines even at half the size ends in a visible "…". A long programme, faculty or
  unit steps down in size and wraps before anything is cut; every word stays inside the card (`lib/idcard-design.test.ts`).
- A name with accents keeps its letters without the marks (Ọlábísí → OLABISI) and a typographic apostrophe prints as one; the
  print used to blank such letters out.
- The desk's preview of a student without a matriculation number says NUMBER NOT YET ISSUED on the pill and prints no barcode.
- The staff card's QR keeps four modules of white inside its green frame, as the QR standard asks.
- The University's place under its name is the profile's city (MAKURDI), fitted between its gold rules.

**What could not be copied exactly.** The PDF engine sets text in the PDF's standard faces: the University's name in Times
Bold at 93 % of its width (the design's serif, measured), the rest in Helvetica (the design uses a rounder sans-serif). The crest is the University's own (its ribbon reads *Scientia Liberatio Populorum*), not the drawing in the design.
The card keeps the ID-1 proportion (85.6 × 54 mm), a little taller than the design's picture.

**PDF writer.** `Page` gains `gs` (graphics states, for the faint watermark and shadows) and `shadings` (the gradients, painted
with `sh` inside a clip). `pdf()` writes each distinct shading once as an object that every page painting it refers to, and the
graphics states into the page's resources; the QR's modules and the barcode's bars are written as rectangles (`re`). The print
of every staff card stays about 9 KB a card before photographs, as before the redesign. The card's scale is written at full
precision, so a card laid out W points wide prints W points wide.

**Tests:** `lib/idcard-design.test.ts` (every word inside the card for ordinary and very long particulars, the two-line staff
name clear of the photograph and the number, the barcode, the PDF's gradients and balanced states, the SVG escaped with ids of
its own); `lib/staff-cards.test.ts`; `lib/pdf-write.test.ts`.

## 10. A staff number is one person whatever its case (V744, 12 November 2026)

The University's word: "fix the duplicate staff number issue". Issuing a staff card to **P2016** failed with a server error: the
portal held two people under that number — `p2016`, the account the portal was opened with (its offices and sign-in), and `P2016`,
the same officer made a second time when the HR register of non-teaching staff was uploaded. Every desk looks a staff number up
without regard to case and expects one person; the database's own rule held the number unique only as typed, and the two staff
uploads (`iam.import_staff`, `iam.import_lecturers`) looked the number up as typed, so the register's `P2016` never found `p2016`.

**What V744 does**
- `iam.merge_staff_number_duplicates()` makes one person of the people whose staff numbers differ only by case or spaces. The person
  kept is the one who signs in (else the one holding offices, else the one on the HR register). Every row that points at the other
  person moves across; where the kept person already has the one row a person may have (a sign-in, a photograph…), theirs stands;
  the HR record is merged (the other's particulars fill what the kept one lacks). The number is written in capitals, as every other
  staff number is. The other person is deleted, or — if something that could not move still points at them — closed (ended, with
  the reason) and their number cleared. Each merge is recorded in `iam.person_merge`.
- Run on deploy. On the copy of the live database of late October one number is shared, **P2016** (Okpali): his HR register record
  moves to his account, which keeps his offices and sign-in and now reads P2016; the duplicate is deleted.
- A unique index on `upper(staff_number)` and a rule that a number has no spaces around it and is not blank: the same number typed
  in another case is refused (409 ALREADY_EXISTS on Users & roles) rather than becoming a second person, and every lookup by staff
  number — the card desk, the University's sign-on, the library, attendance, appraisal, movement — finds one person.
- Both staff uploads find an existing person by the number whatever its case.

**Tests:** check.sql's two V744 properties (the merge, with a third record whose own sign-in cannot move; the refusal and both
uploads); `StaffIdCardsIT.aStaffNumberIsOnePersonWhateverItsCase` (a card issued by the number in another case; the second person
refused by Users & roles and by the database).

## 11. The cards' new layouts: fields removed, DEPARTMENT on the staff card (V748, 12 November 2026)

The University's brief "Update student and staff identity card layouts" changes only what the cards print. The level, the session, the faculty, the office, the unit and the validity all stay on record for the rest of the portal.

**The student card** no longer prints LEVEL, SESSION or GRADUATES. It prints:

- Faculty and Programme in the wider left column;
- Blood group and Admitted on the right (Admitted kept: the brief changes only the fields it names);
- Valid until and the card number in the foot.

**The staff card** prints:

- DEPARTMENT in place of UNIT;
- no FACULTY, OFFICE or VALID UNTIL;
- Rank, Category, Department, Appointed and Blood group, with the card number alone in the foot, centred;
- Category as **Teaching** or **Non-teaching**, where it used to read "Academic" or "Non-teaching" (the University's decision of 12 November 2026).

**Where the department comes from.** `credentials.staff_card_department(person)` reads the HR staff record, which is the authoritative organisational assignment:

1. its academic department, when it names one (never replaced by the unit, the faculty or the office);
2. else the unit's card name;
3. else the unit as the nominal roll spelled it;
4. else (V751, V753) the office the person holds on the portal, read by its scope: a department-scoped grant its department (a programme- or course-scoped one, the programme's or the course's department), a unit-scoped one the unit's card name (the unit as Users & roles typed it, resolved as the nominal roll resolves it), a faculty-scoped one the faculty, a college-scoped one the college, and an office the University holds centrally the unit it belongs to (`ref.office.unit_code`: the Registrar's and the Deputy Registrar's offices the Registry, the Bursar's and the Students Account Officer's the Bursary, the Director of ICT's ICT, the Chief Security Officer's the Security Unit, the Librarian's the Library);
5. else a dash. An office's title ("Head of Department", "Registrar") is never printed under DEPARTMENT.

A posting recorded in `hrm.movement` does not change the record, so the record is what every reader uses.

**The units' card names.** The unit register names units formally ("Office of the Registrar", "Directorate of ICT"). A unit now has a card name (`ref.unit.card_name`), the short name a staff card prints, following the University's decision of 12 November 2026.

- **Seeded from the brief:** Registry (Office of the Registrar), Bursary (Bursary Department), Information and Communication Technology (Directorate of ICT) and Stores (the three stores units).
- **A unit without a card name** prints its nearest parent's (Payroll (FAT) prints Bursary), else its formal name (`ref.unit_card_name`).
- **Setting a card name:** ICT sets one, or clears it, with a reason on the staff page's unit register (*The Unit Register* tab, *Staff card prints* column; `PUT /api/v1/iam/units/{code}/card-name`, ICT or super).

**What reads it.** The same faces serve every print:

- `lib/staff-card-face` for the staff card's single print, the print of them all and a reprint;
- the card desk's preview and `credentials/idcards/student/pdf` for the student card.

The design (`lib/idcard-design`) now sets both columns of particulars at one size and spacing. With fewer fields, the particulars grow (up to six-fifths) and spread down the card, so no room is left where a field was.

**Tests.**

- `lib/idcard-design.test.ts`: no removed label is printed on either card; the staff card's number is centred on the foot; the particulars fill the room.
- `lib/staff-cards.test.ts`: the staff face's fields and the Teaching category.
- `StaffIdCardsIT`: the face's department is the unit's card-name reading; ICT's card name printed; HR refused; a reason required.
- check.sql's V748 block: the seeds, the inheritance, the department's order and the office check.

## 12. The review of the new layouts (V748, V751)

The review (three readers, each finding put to a refuter) confirmed five points on the cards.

- **Fixed in V748, before it was pushed:**
  - a long department could be cut short as the particulars grew;
  - the staff card's number sat 1.7 mm right of centre;
  - an appointment date in a long month broke over two lines;
  - rows went out of level beside a wrapped value.
- **Fixed in V751:** a member of staff the HR record places nowhere printed their office's title as the department. The card now reads the office's scope or the unit a central office belongs to, else a dash.
- **Left as they were (refuted as older than the change):**
  - the verification page reads only the academic department;
  - the desk's lists show a unit's formal name;
  - an ended department or unit still prints.

**The review of V751 (V753).** Two more scopes are read for someone the HR record places nowhere:

- a programme- or course-scoped office (an Examinations Officer, a lecturer given one course) prints the programme's or the course's department;
- a unit typed by name in Users & roles ("Medical Library") is resolved as the nominal roll resolves it, so it no longer falls back to the main Library or a dash.
