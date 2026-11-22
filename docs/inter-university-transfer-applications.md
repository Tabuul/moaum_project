# Inter-university transfer applications online

*Nov 2026 (V766).* The University's request: "a link that students from other universities open to apply themselves". Its
decisions of 15 November 2026:

1. An application fee per session, stated and published by the Bursar, possibly nothing, paid online before submitting.
2. The applicant uploads the transcript, a letter of release or good standing, the JAMB admission letter and the like. This is an
   exception to the rule that applicants never upload.
3. The Head of Department of the programme applied for recommends (accept with a level, or decline with a reason); the Academic
   Office or the Registry then approves into the V588/V763 incoming transfer, which another officer decides on the existing
   Inter-University Transfer page.
4. The Academic Office opens a transfer window each session and lists the programmes and levels taking transfers; the public form
   offers only those.

Until the University says otherwise: no letter of admission is printed for an admitted transfer student (a follow-up), and the
application fee is not refunded when an application is declined or withdrawn; only a second payment is given back.

## 1. What it is

A public page where a student of another university applies, on their own, to transfer into this University: they register,
pay the fee, upload their documents and submit, then follow the application on their own portal until they are admitted (or not).
It is for undergraduates coming **in** only. Students leaving for another university, and transfers the Senate has already
approved, are still recorded on [Inter-University Transfer](inter-university-transfer.md) and its form.

## 2. The link

- **The address:** `https://<portal>/transfer/apply`. It is open to anyone; nothing else under `/transfer` is (the applicant's own
  pages under `/transfer/portal` and the desks under `/transfers` stay signed in).
- **The sign-in page** carries one line under the collaboration line, only while the window is open: "A student of another
  university? Apply for an inter-university transfer".
- **The University's website** reads `interUniversityTransfer` on `GET /api/v1/public/application-windows` (the same shape as the
  other doors; see [application-windows.md](application-windows.md)) and may list the open programmes from:

```
GET https://<portal-api>/api/v1/public/inter-university-transfer
```

```json
{ "session": "2026/2027",
  "window": { "status": "OPEN", "opensOn": "2026-11-20", "closesOn": "2027-01-15", "message": null, "open": true,
              "type": "INTER_UNIVERSITY_TRANSFER_APPLICATION", "label": "Inter-university transfer application",
              "applicationPath": "/transfer/apply", "applicationUrl": "https://<portal>/transfer/apply" },
  "fee": { "amount": 5000.00, "published": true },
  "programmes": [ { "code": "C00023", "name": "B.Sc. Biochemistry", "dept": "BCH", "deptName": "Biochemistry", "faculty": "SC",
                    "facultyName": "Science", "levels": [200, 300] } ],
  "universities": [ { "code": "UNIJOS", "name": "University of Jos", "country": "Nigeria" } ],
  "documents": [ { "code": "TRANSCRIPT", "label": "Academic transcript or statement of results from your present university",
                   "hint": "Every semester you have completed, with your CGPA", "required": true, "imagesAllowed": true } ],
  "maxDocumentBytes": 5242880 }
```

No sign-in, any origin, nothing personal. The programmes are listed only while the window is open, and never with their places.
While it is not open, `message` is the Academic Office's closed message.

## 3. The Academic Office

Academic Office (and Registrar, Deputy Registrar, Super Administrator) → **Transfer Applications** (`/transfers/inter-university/applications`),
tab **Window and programmes**:

- **The window**, one per session (a session PLANNED or CURRENT): *Draft*, *Open* (with an opening and a closing date, read in
  Lagos) or *Closed*. Its status today is Open, Closed, *Scheduled* (before the opening date) or *Expired* (after the closing date).
  It opens only when at least one programme below accepts **and** the Bursar has published the session's fee (a fee of nothing
  counts), so nothing is charged at a guess and no applicant is left registered with no way to pay. It goes back to Draft only
  while no application exists for the session.
- **Closing stops new applications only** (V312's rule). An application registered before the closing still pays, uploads,
  submits, is corrected and is decided; its programme and level can no longer be changed.
- **The closed message**: what the public reads while the window is not open (plain text; a blank line is a paragraph).
- **Programmes and levels**: one line per programme and level of an undergraduate, unarchived programme, the level one the
  programme runs. Each line may have **places** (blank: no limit), counted at the Registry's approval against the level the Head
  of Department recommended (approved and admitted applications on that line). A line can be closed to new applications
  (*Accepting* unticked) without touching those already made on it; a line in use is closed rather than removed. While the window
  is open, its last line taking applications is neither closed nor removed (`IUT_WINDOW_NO_PROGRAMMES`): close the window instead,
  so the public link, the sign-in page and the website never announce an open window that offers no programme.
- **A programme archived** (or merged away) after its line was added: the line stays, marked *Programme archived: not offered*,
  but offers the public nothing and counts for nothing — it is never the open window's "last line" (it closes or goes freely, and
  the last line offered is kept), and the window does not open on such lines alone. If the window's last programme offered is
  archived while it is open, the window reads **closed** to the public, the sign-in page and the website (the page says *Open, but
  offering nothing*): add another programme and level, or close the window.
- **A programme shortened** past a line's level (its length corrected, V598/V634: 400 Level of a programme now of three years): the
  line stays, marked *No longer a level of the programme: not offered*, and offers nothing and counts for nothing as an archived
  programme's line does. The Head of Department's levels leave it out; an application made on it before is moved by its applicant
  to a level still offered while the window is open (a draft), or recommended at another line of the programme.
- **The session the page opens on** when none is chosen: the open window's; else the latest session with applications on the desks'
  hands (submitted, returned for a correction, with the department, recommended or not, approved), so a window just closed keeps its
  checking, the department's work and the approvals in front of the desk — lines added or a fee stated for the next session do not
  take the desk off it; else the latest window set *Open* but not open today (scheduled, expired, or offering nothing — the page then
  says why); else the University's current session. Another session is chosen in the session list.
- **A programme merged** into another (Records, V574): its lines move to the kept programme, except a line the kept programme
  already has or whose level it does not run, which stays on the old code; the applications move.

Tab **Documents asked**: the short list of documents an applicant uploads, each with its label, hint, whether it is required,
whether a photograph (JPEG or PNG) is taken besides a PDF, and its order. It starts with:

| Document | Required | Counts on the transfer as |
|---|---|---|
| Academic transcript or statement of results from your present university | yes | TRANSCRIPT |
| Letter of release, or of good standing, from your present university | yes | RELEASE_LETTER |
| JAMB admission letter | yes | JAMB_ADMISSION_LETTER |
| O'Level result (WAEC, NECO or NABTEB) | yes | OLEVEL_RESULT |
| O'Level result, second sitting (if any) | no | OLEVEL_RESULT |
| Admission letter from your present university | no | — |
| Identity card of your present university | no | — |
| Any other supporting document | no | — |

A document made *required* is asked of every application not yet with the Head of Department: one already submitted is
returned to its applicant for it (the Registry's send to the department asks it). An application the department has seen is never
held back by it: the approval checks only that every current document is accepted. The last column is fixed: it is how the
documents the Registry accepted are recorded on the transfer.

## 4. The Bursary

- **The fee.** Bursary → Fee Setup → **Inter-university transfer application fee**. The Bursar, the Students Account Officer or the
  Super Administrator states a figure for the session as a draft; the Bursar (or the Super Administrator) publishes it. Nothing
  (₦0) is a fee too: published, it means no fee is charged, and the applicant's fee is settled at registration. A restatement waits
  beside the published figure until it is published; a reference already drawn keeps its amount — except when the fee is restated
  to nothing: a draft then owes nothing, so a reference drawn before is no longer taken (the card checkout and PAYDirect's validation
  refuse it) and the draft is settled without a fee when its applicant next opens the fee step. Money paid on such a reference anyway
  (at a bank, say) settles nothing: the draft is settled without a fee and the payment is **owed back**, for the refund desk.
- **The payments report.** Bursary → **Transfer Application Payments** (`/finance/transfer-application-payments`; also the auditors):
  each reference drawn, its state (paid, waiting, expired), the receipt and channel, the application and its state, what the refund
  desk gave back, with the totals over the filters (never the page alone), and a CSV export.
- **Owed back.** A payment confirmed for an application already settled (a second payment, or one made after a withdrawal or a
  decision) settles nothing: it is listed as **owed back** and paid by the existing refund desk (`finance.refund`, the payer by name,
  the reference as its source; the desk's list shows the application number under the payer, as it shows a JUPEB applicant's). Once the refund desk's refunds of it are approved (or paid) for the whole payment it reads
  **Refunded** and leaves the list owed back; a part refunded stays owed back for the rest. The tile's amount is what is still owed.
- **The application fee is not refunded** on a decline or a withdrawal: the refund desk refuses a refund of the payment that settled
  an application (`REFUND_IUT_SETTLES`), raised or approved; only a payment owed back is refunded.
- **Hand confirmation.** The Bursar confirms a reference by hand against the bank's record (*Confirm by hand*), as on the JUPEB fees
  desk; a receipt is issued and the applicant told. The note records the bank, the teller or transfer number and the date as the
  bank's record shows them. **After a hand confirmation, a bank credit on that reference is never posted by the portal**, whatever
  the note says: the approval of one proposed for it is refused (`IUT_FEE_ALREADY_PAID`, with the date of the hand confirmation, its
  receipt and the note as written). The Bursary checks the bank's record and rejects the proposal, and refunds only money received
  twice: if the record shows the credit is the payment confirmed by hand, nothing is owed back; if it shows a second payment, the
  credit is owed back to the applicant and the refund desk pays it. A note is free text, and no reading of it tells one payment from
  another (a note naming two tellers, the same number at another branch, or the reference written short would otherwise have posted
  real second payments as nothing).
- **Bank credits.** Money for a transfer applicant's reference (a teller, a line of the collections statement, a row of
  Interswitch's settlement report) is posted by the Bursary's two-person bank credit like any other reference: one officer proposes
  it, another approves, and the approval confirms the reference (channel *Bank branch*): it settles the application, or is owed back.
  When the reference was confirmed between the proposal and the approval, how it was confirmed does not say whether this credit is
  that payment — two tellers proposed against one reference, a teller and then a payment at a branch or on the web through PAYDirect,
  Interswitch's row of one payment and the import of another are all money received twice. So the approval reads the evidence:
  - **the credit is that payment** — it came from Interswitch's settlement report or the collections statement and carries one of
    the identifiers the gateway or the collections import gave the payment, as the confirmation kept them (Interswitch's Payment Log
    Id and payment reference from PAYDirect's notice, the collections import's Log Id, and for a card on WebPAY its payment
    reference, its RRN and the transaction reference the portal asked), letters and digits compared:
    - on a row of Interswitch's settlement report, its Log Id, payment reference or transaction reference equal to one of them;
    - **on a line of the collections statement, only the bank's own reference equal to one of them** — for a card on WebPAY, its
      RRN or its payment reference. The line's narration never counts: it is what the payer typed, and a payer who pays again by
      transfer may quote the first payment's receipt (its Log Id, its RRN, the card's transaction reference) in it. Nor does a bank
      reference that carries the identifier among other words (such as `PAYDIRECT/<reference>/7661104` or `FBN 7661104`), a bare
      number shorter than an RRN's twelve digits (a teller's number, which another bank may give another payment; a PAYDirect Log
      Id is one), or one that holds the portal reference (such as `<reference>-A2`, the card's transaction reference, which a payer
      may copy). Such a line is checked by the Bursary first, as below; the same PAYDirect payment is posted from Interswitch's
      settlement report instead, where the Log Id is Interswitch's own field.

    One payment seen twice by the Bursary's tools: the credit is posted as *already confirmed*, as any reference's is, and nothing
    is owed back. The portal reference is never this evidence, nor any piece of it (the reference written short, such as
    `IUTAPP-2026-000017` or `2026/000017`); and one payment is posted once: when another bank credit is already posted to the
    reference, a second is not;
  - **anything else**, however the reference was confirmed (by hand — always, see above — by PAYDirect, by another bank credit, by
    card): the approval is refused (`IUT_FEE_ALREADY_PAID`, saying how and when the reference was confirmed, its receipt, this
    credit's bank and instrument, and why) and the credit stays proposed. Check the bank's record, then reject the proposal either
    way: if the bank shows the money twice, the credit is owed back to the applicant and the refund desk pays it, naming them, without
    a transaction reference (the reference holds the payment confirmed first); if the credit is that same payment, nothing is owed back.

Payments go through the gateways every fee uses (card, USSD, Quickteller, PAYDirect). The payment kind and category are
`IUT_APPLICATION` ("Inter-university transfer application fee", purpose APPLICATION), so the general ledger, Financial Analytics,
Collections and the master report take them in.

## 5. Applying

On `/transfer/apply`, while the window is open:

- **About you:** surname, other names, sex, date of birth (14 to 70 years old), e-mail, a Nigerian phone number, and the JAMB
  registration number of the present admission (12 digits and 2 or 3 letters). One **live** application a JAMB number (any state
  but rejected or withdrawn).
- **Your present university:** from the list, or *My university is not on the list* and its name; the matriculation number there,
  the programme, the level reached, the session entered (`2023/2024`, not after this session) and the CGPA with its scale (4 or 5).
- **What you apply for:** a programme the window opens, then one of its levels. The session is the window's.
- **Your reason for transferring:** 20 to 2,000 characters.
- **Your password:** at least 8 characters; not the JAMB number.

**Register and continue** makes the account and the application (`IUT/APP/2026/000001`) and signs the applicant in at once on
their portal (**My transfer application**, `/transfer/portal`). They sign in again on the sign-in page with the e-mail or the
application number; *Forgot password* resets it by e-mail, asked with the **application number** (`IUT/APP/…`): an e-mail that is also
on a Post-UTME or postgraduate account resets that account first.

On the portal, in order:

1. **Particulars.** Changed at will while a draft (the programme and level only while the window is open); when returned for
   correction, everything but the programme and level; until a decision, the e-mail and phone (the student record, once admitted,
   takes them as they stand at the decision).
2. **The fee.** *Get a payment reference*, then pay by card or USSD (or Quickteller, or at the bank by PAYDirect). The reference is
   good for 24 hours; a new one is free. The receipt is printed with a QR to its verification page. With no fee, nothing to do.
   A draft withdrawn before its fee is paid owes nothing; a payment that arrives after is owed back. A payment owed back that the
   refund desk has given back reads *refunded to you* (or what is still owed, when part is given back).
3. **Documents**, once the fee is paid: PDF, JPEG or PNG, at most 5 MB each (some kinds PDF only), checked in the browser first and
   by their first bytes on the server. A document is replaced by uploading the same kind again (the earlier one is kept, never
   deleted); one the Registry accepted is never replaced.
4. **Submit**, under the declaration: "The particulars and documents I have given are true. I understand that a false one ends
   this application and any admission it leads to." It needs the fee and every required document, and none rejected.

From submission, **Print acknowledgement** gives a PDF with a QR that opens `/verify/transfer-application?no=IUT%2FAPP%2F…&t=…` (the
number in the query: an encoded slash in a path is refused by the API's firewall): it attests the submission only, never a state or
a decision. The applicant may **withdraw** on the portal until the Head of Department has assessed the application (a draft,
submitted, returned for correction, or with the department). After that, while it is with the Registry for a decision —
recommended, not recommended or approved alike — the portal says to write to the Registry, and the API refuses a withdrawal in the
same words in all three, so nothing tells which it is; the Registry ends it by rejecting it, with the applicant's request as its
reason (an approved one once the deciding officer has rejected the transfer). Changing the password ends every other session of
the account. When an
application is rejected or withdrawn and a later window opens, **Apply again** fills the new application from the old one.

What the applicant reads at each step:

| State | The banner | Told by e-mail and SMS |
|---|---|---|
| Draft | Not yet submitted. Next: pay the fee / upload the documents missing / submit | started; payment receipt |
| Submitted | Submitted on the date. The Registry is checking your documents | submitted |
| Returned for correction | Returned to you: the Registry's note. Replace the documents marked and submit again | correction required |
| With the department | Your documents are checked. The Head of Department of the programme is assessing your application | with the department |
| Recommended, not recommended, approved | With the Registry for a decision | nothing |
| Admitted | Admitted to the programme, at the level admitted (the department's), the session; the admission number; sign in as a student with it and this password (once signed in as a student: the student portal's own password) | admitted |
| Rejected | Not admitted. Reason: the Registry's reason | rejected |
| Withdrawn | Withdrawn on the date | withdrawn |

The department's recommendation and the Registry's approval are never shown to the applicant before another officer confirms the
transfer: the applicant's own data (`GET /me`, its list of applications and its history) gives the one state `WITH_REGISTRY` for
recommended, not recommended and approved, and the time of the last step shown to them, never of a desk's act.

## 6. The review

1. **The Registry checks the documents** (Transfer Applications → an application). While the application is *Submitted*, each
   document is **accepted**, or **rejected** with a note the applicant reads. Then:
   - **Return to the applicant** with a note: the applicant replaces the documents rejected and submits again;
   - **Send to the Head of Department**, once every document is checked and every required one accepted;
   - or **Reject** with a reason the applicant reads.

   A **draft** (not yet submitted) is the applicant's own, but it holds its JAMB number as any application in progress does: the
   number's owner is refused (`IUT_JAMB_TAKEN`, "ask the Registry") while it stands, in that session and every later one. The
   Registry finds it by the JAMB number (the search) and **rejects** it, with a reason the account that made it reads; the number is
   free at once, a reference drawn on the draft is no longer taken to a gateway, and a fee paid on it is not refunded (a payment
   that arrives after is owed back). Reject a draft only to end one made under another person's number — never because it is
   unfinished: a started application has no deadline (a draft made before the window closed still pays and submits). On a draft
   whose fee is paid, the page warns before the rejection that, ended, the fee is not refunded and the account cannot apply again in
   that window.

   The page also shows **what the transfer check says**: V763's own check of the transfer the application would register (a student
   already on the register, a transfer waiting under the number, the university not on the list, a name that differs), so these are
   seen before the department is asked.
2. **The Head of Department** (or, for a department in a College, the College Dean) is told by e-mail and finds the applicant on
   **Transfer Applicants (other universities)** (`/hod/transfer-applications`), their own department only, without the contact,
   the fee or the Registry's own words: the history lists each step, but not the payment, nor the note of a return, a rejection, a
   document rejected (the document is named, the Registry's words to the applicant are not) or the approval (those are written for
   the applicant or the record); the Registry's notes sent with the application to the department, or with it back to the
   department, are shown — to the department only, never to the applicant. They read the documents (one by one, or all as one PDF) and **recommend** at a level the window opens for the programme
   (with an optional assessment note), or **decline** with a reason.
3. **The Registry decides.** A declined application is **rejected** (with words for the applicant) or **sent back** to the department;
   it is never approved without the department's level. A recommended one is **approved**: the approval registers the incoming
   transfer of one exactly as the Inter-University Transfer Form does (`people.register_university_transfer`, batch source
   `APPLICATION`, the documents accepted recorded on it, the department's level its level), checked for places on the line, and
   refused while the university is not on the list (put it there with *Add to the list*, then *Set university*). It is refused too
   (`IUT_STUDENT_EXISTS`) when a student already on the register holds the JAMB number at that programme and level — what the
   transfer check reads as *recorded on the existing record*: an online application never admits anyone onto another student's
   record. The approving officer is the transfer's preparer. **Approve** stays closed, with the check's own words, while the transfer
   check refuses the transfer (the programme archived since, a transfer of the student already waiting, and the like): the approval
   runs the same check and would be refused (`UNIVERSITY_TRANSFER_FORM_INVALID`).
4. **Another officer** of the Academic Office or the Registry decides the transfer on **Inter-University Transfer** (the batch
   says *Applied online* and links the application). Approved, the student is admitted and the application follows (*Admitted*,
   the applicant told). Rejected, the application goes back to the Registry's desk as recommended, and the applicant is **not**
   told: the Registry approves it again or rejects it with its own words. A transfer that would be recorded on a student already on
   the register (one given the JAMB number after the approval) is not completed (`IUT_STUDENT_EXISTS`): the deciding officer
   rejects it instead.
5. **A withdrawal asked for after the approval.** The applicant can no longer withdraw on the portal and writes to the Registry. The
   approved application's page says how to honour it: ask the deciding officer to reject the transfer on Inter-University Transfer
   (the application comes back as recommended, the applicant not told), then **Reject** it with the applicant's request as the
   reason.

## 7. After the decision

- **The student record** is made as V588 makes it: an admission number from the University's series (`MOAUM/ADM/YY/NNNNNN`),
  status admitted, entry mode TRANSFER, at the level the department recommended, in the window's session.
- **Signing in as a student**: with the admission number and the application's password (carried over at the first sign-in).
  From then on the student portal keeps its own password: one changed on the transfer portal opens only the application page, and
  the portal says so (its password page and the banner). The banner's **Sign in as a student** signs the applicant out to the
  sign-in page.
- **School fees** are paid in the student portal; the acceptance-fee gate of fresh UTME and Direct Entry admits does not hold them.
- **Matriculation** follows under Matriculation Management, as for any admitted student. No letter of admission is printed yet.

## 8. Notices

E-mail and SMS, never on the portal (the status page is the portal view):

| Notice | When |
|---|---|
| `IUT_APPLICATION:CREATED` | the application is started |
| `IUT_APPLICATION:PAYMENT_RECEIVED` | the fee is paid (the receipt) |
| `IUT_APPLICATION:SUBMITTED` | submitted |
| `IUT_APPLICATION:CORRECTION_REQUIRED` | returned for correction, with the note and the documents rejected |
| `IUT_APPLICATION:WITH_HOD` | sent to the department |
| `IUT_APPLICATION:ADMITTED` | admitted, with the admission number |
| `IUT_APPLICATION:REJECTED` | rejected by the Registry, with the reason |
| `IUT_APPLICATION:WITHDRAWN` | withdrawn |
| `IUT_DESK:WITH_HOD` | to the Head of Department (or the College Dean): an applicant awaits a recommendation |

## 9. Who does what

| Act | Who | Refused in the database by |
|---|---|---|
| Apply, sign in | anyone (the door is limited per connection, with a hidden field for robots) | the window, the line, the particulars |
| Pay, upload, submit, edit, withdraw | the applicant, on their own application | `IUT_NOT_YOURS` |
| The window, programmes and levels, documents asked | Academic Office, Registrar, Deputy Registrar, Super Administrator | `IUT_OFFICE` |
| State the fee / publish it | Bursar, Students Account Officer, Super Administrator / Bursar, Super Administrator | `IUT_FEE_OFFICE` |
| Read the Registry's desk and documents | Academic Office, Registrar, Deputy Registrar, Records, Super Administrator | — |
| Review documents, return, send to the department, reject, set the university, approve | Academic Office, Registrar, Deputy Registrar, Super Administrator | `IUT_OFFICE` |
| Read the department's desk and documents | Head of Department (own department), College Dean (own faculty, in a College), Super Administrator | `iut_hod_may` |
| Recommend | Head of Department, College Dean, Super Administrator | `IUT_HOD_OFFICE`, `IUT_HOD_OTHER_DEPARTMENT` |
| Decide the transfer | the Inter-University Transfer keepers, **not the approver** | `UNIVERSITY_TRANSFER_SAME_OFFICER` |
| Payments report / hand confirmation | Bursar, Students Account Officer, Super Administrator, Internal Audit / Bursar, Super Administrator | `IUT_FEE_CONFIRM_OFFICE` |

## 10. Refusal codes

Each reaches the screen as the database says it (HTTP 422, or 403 where marked), with what to do.

| Code | When |
|---|---|
| `IUT_OFFICE` (403) | a window, line, document kind, document review, act, university or approval by an office outside those above |
| `IUT_SESSION` | the session is not planned or current |
| `IUT_WINDOW_STATE`, `IUT_WINDOW_DATES`, `IUT_WINDOW_NO_PROGRAMMES`, `IUT_WINDOW_FEE_UNPUBLISHED`, `IUT_WINDOW_IN_USE` | setting the window; `IUT_WINDOW_NO_PROGRAMMES` also closing or removing an open window's last line offered (taking applications, on a programme in use) |
| `IUT_PROGRAMME`, `IUT_LEVEL` | a line on a programme not undergraduate or archived; a level the programme does not run |
| `IUT_LINE_UNKNOWN`, `IUT_LINE_IN_USE`, `IUT_PLACES` | changing lines |
| `IUT_KIND` | a document kind's code or label |
| `IUT_FEE_OFFICE` (403), `IUT_FEE_AMOUNT`, `IUT_FEE_NOT_STATED`, `IUT_FEE_NOT_PUBLISHED` | the fee |
| `IUT_WINDOW_CLOSED` | a new application, or a programme change, while the window is not open (the closed message with it) |
| `IUT_PROGRAMME_NOT_OPEN` | a programme and level not taking transfers |
| `IUT_NAME`, `IUT_SEX`, `IUT_DATE_OF_BIRTH`, `IUT_EMAIL`, `IUT_PHONE`, `IUT_JAMB`, `IUT_UNIVERSITY`, `IUT_OTHER_MATRIC`, `IUT_OTHER_PROGRAMME`, `IUT_OTHER_LEVEL`, `IUT_ENTRY_SESSION`, `IUT_CGPA`, `IUT_REASON` | the particulars |
| `IUT_EMAIL_TAKEN`, `IUT_JAMB_TAKEN`, `IUT_ALREADY_APPLIED` | an account under the e-mail; a live application under the JAMB number (a draft too, until the Registry ends it); applying again too soon |
| `IUT_NOT_YOURS` (403) | an applicant's call on another account's application |
| `IUT_STATE`, `IUT_STATE_MOVED`, `IUT_NOT_EDITABLE`, `IUT_ACTION` | the application is not in a state for the act, or another officer moved it meanwhile |
| `IUT_FEE_SETTLED`, `IUT_FEE_UNPAID`, `IUT_REFERENCE_UNKNOWN`, `IUT_FEE_CONFIRM_ACTOR`, `IUT_FEE_CONFIRM_OFFICE` (403), `IUT_REFERENCE_STALE` | payment |
| `REFUND_IUT_SETTLES` | the refund desk, a refund of the payment that settled an application (only a payment owed back is refunded) |
| `IUT_FEE_ALREADY_PAID` | the bank credits, the approval of a credit proposed against a reference confirmed meanwhile, with nothing to show the credit is that payment (check the bank's record and reject the proposal; owed back only when the bank shows the money twice). A credit whose settlement row carries one of the identifiers the gateway or the collections import gave the payment (its Log Id, payment reference, RRN or WebPAY transaction reference), or whose collections line has the bank's own reference equal to one of them, is posted as the same money; never on a line's narration (the payer's words), never on the portal reference or a piece of it, never on a line's bank reference that carries the identifier among other words, is a bare number shorter than an RRN or holds the portal reference, never once another credit is posted to the reference, and never on a reference the Bursar confirmed by hand |
| `IUT_DOCUMENT_KIND`, `IUT_DOCUMENT_TYPE`, `IUT_DOCUMENT_SIZE`, `IUT_DOCUMENT_ACCEPTED`, `IUT_DOCUMENT_UNKNOWN`, `IUT_DOCUMENTS_MISSING`, `IUT_DOCUMENTS_REJECTED`, `IUT_DOCUMENTS_UNCHECKED` | documents |
| `IUT_REVIEW_VERDICT`, `IUT_REVIEW_NOTE`, `IUT_NOTE` | the Registry's review |
| `IUT_HOD_OFFICE` (403), `IUT_HOD_OTHER_DEPARTMENT` (403), `IUT_LEVEL_NOT_OPEN` | the department |
| `IUT_UNIVERSITY_UNKNOWN`, `IUT_UNIVERSITY_NOT_LISTED`, `IUT_PLACES_FILLED`, `IUT_STUDENT_EXISTS` | approval (and, for `IUT_STUDENT_EXISTS`, the second officer's decision): the university not on the list, the places taken, the JAMB number a student's on the register |
| `UNIVERSITY_TRANSFER_FORM_INVALID`, `UNIVERSITY_TRANSFER_SAME_OFFICER` (403) | V763 and V588, passed through unchanged |
| `IUT_DECLARATION`, `IUT_PASSWORD`, `IUT_APPLY_REFUSED` | the declaration unticked; a password under 8 characters or equal to the JAMB or application number; the hidden field filled |

## 11. API

Public (no sign-in):

| Call | Purpose |
|---|---|
| `GET /api/v1/public/inter-university-transfer?session=` | the window, the fee, the programmes and levels open, the universities, the documents asked |
| `POST /api/v1/transfer-applications/apply` | register and sign in (throttled `IUT_APPLY`) |
| `POST /api/v1/transfer-applications/sign-in {identifier, password}` | sign in on the e-mail or application number (throttled `IUT_SIGN_IN`) |
| `GET /api/v1/verify/transfer-application?no={applicationNo}&t=` | the acknowledgement's verification (the number in the query; in the path only with its slashes raw, never `%2F`) |

The applicant (`/api/v1/transfer-applications/me`): `GET` and `PUT /me`, `POST /me/applications` (apply again),
`POST /me/fee-reference`, `GET /me/receipts/{reference}`, `POST /me/documents {kind, filename, dataUrl}`,
`GET` and `DELETE /me/documents/{id}`, `POST /me/submit {declaration}`, `POST /me/withdraw {reason}`, `GET /me/acknowledgement`,
`POST /me/password {current, next}`.

The desks (`/api/v1/transfer-applications/office`): `GET` and `PUT /window` (`GET` with no session answers for
`admissions.iut_desk_session()`, the session the page opens on, §3), `POST`, `PUT` and `DELETE /lines` (`PUT /lines` sends
`places` every time: left out or null, it takes the line's limit off), `GET /programmes`,
`GET` and `PUT /document-kinds`, `GET /applications`, `GET /applications/{id}` (with `transferCheck` for the Registry),
`GET /applications/{id}/documents/{docId}`, `GET /applications/{id}/documents.pdf`, `POST /applications/{id}/documents/{docId}/review`,
`POST /applications/{id}/act {action, note, expectedState}`, `POST /applications/{id}/recommend {accept, level, note, expectedState}`,
`POST /applications/{id}/university {code}`, `POST /applications/{id}/approve {approvalRef, note, expectedState}`, `GET /summary`.

The Bursary (`/api/v1/finance/transfer-applications`): `GET` and `PUT /fee`, `POST /fee/publish`, `GET /payments`,
`POST /payments/{reference}/confirm {note}`.

## 12. Left out

- **A minimum CGPA:** no such rule exists in the portal; the Head of Department judges the CGPA.
- **A letter of admission** for the admitted transfer student: none is issued today (a follow-up, needing a template and a
  signatory); the notice and the portal carry the admission number.
- **JAMB's regularisation of the transfer on CAPS:** outside the portal, as for V588.
- **The Head of Department changing the programme:** an applicant wanting another programme is declined and applies again in a
  later window.
- **Credit transfer or course exemptions:** the assessment note may record them; the portal does not apply them.
- **Outgoing transfers online:** only students coming in apply here.
- **A captcha:** none; the door's limits per connection and a hidden field stand in.
- **ICT Support resetting a transfer applicant's password:** *Forgot password* covers it.
- **Notices on the portal** to applicants, and **telling the second officer** an approval waits (the Registry's desk shows approved
  applications, and the Inter-University Transfer page lists the batch).
- **A passport photograph:** the identity card desk takes it.
- **A refund of the application fee** on a decline or withdrawal: only a second payment is owed back.
- **Reminders before the window closes:** an application started may finish after the closing.
