# Transcripts asked for without a portal account, on the University's template (V668, Oct 2026)

**Where:** the public form at **/transcripts/request**, the requester's page at **/transcripts/status/{token}**, the graduate's consent
page at **/transcripts/consent/{token}**, and their API doors under `/api/v1/public/transcripts` (`TranscriptPublicController`). The
Transcript Desk works these requests on the screen it already has (Documents office → Requests), which now shows who asked, the identity
document and the consent. Everything after the request (the fee, the payment reference, validation, generation, quality check, release,
delivery) is V262's pipeline, unchanged.

**Why:** graduates of earlier years have no portal account, and institutions and employers ask for transcripts on a graduate's behalf. A
signed-in student still asks from the student portal, exactly as before.

## Who can ask, and how each is proved

| Who | Proved by | Then |
|---|---|---|
| The graduate | the matriculation number and the date of birth, then a six-digit code sent to the email and phone **on the record** (`people.student_reach`) | a one-hour pass (`credentials.access_code`); the request is `CONFIRMED` |
| The graduate without that contact | the matriculation number, the date of birth and an **identity document** (PDF, JPEG or PNG, at most 5 MB, checked by its first bytes) | `AWAITING_REVIEW`: a person at the desk accepts or refuses it (`credentials.review_identity`) |
| An institution or employer | the graduate's matriculation number and surname | `AWAITING` consent: the graduate is emailed and texted a link valid 14 days; a refusal cancels the request |

A wrong matriculation number and a wrong date of birth are refused in the same words (`TRN_NOT_MATCHED`), so the form does not tell a
stranger which half was right. Five codes an hour per record (`TRN_CODE_LIMIT`), five tries per code, fifteen minutes per code. At most
three requests per graduate may wait for an identity check at once. The codes, passes and private links are kept only as SHA-256 hashes.
Each door is limited per connection (`Throttle`: `TRANSCRIPT_CODE`, `TRANSCRIPT_FORM`, `TRANSCRIPT_STATUS`), and each form has a
honeypot field (`website2`).

**Nothing is produced until the request is proved.** A trigger on `credentials.transcript_request` (`trg_public_request_gate`) refuses
the move to PROCESSING, GENERATED, VERIFIED or RELEASED while the identity is awaiting review (`TRN_IDENTITY_PENDING`) or the consent is
not given (`TRN_CONSENT_PENDING`). The identity check needs a real officer: the public door's anonymous actor cannot accept a document.

## The request, the fee and payment

The public functions call `credentials.request_document`, so the fee (`credentials.fee_for`, from the document policy the desk sets),
the payment reference (`finance.new_purpose_reference`, payable 24 hours) and the request's stages are a student's own. Payment is
confirmed by the portal's existing payment flow; this work only reads `paid_at`. The status page shows the fee, the reference and the
online payment link (`finance.quickteller_link`), and renews an expired reference (`credentials.public_renew_reference`, through
`finance.renew_reference`).

`request_document` is restated with one change: the "same request within the day" rule now also compares the destination, the
organisation and the recipient's email, so a graduate can send transcripts to two universities on the same day.

## The documents

* **The transcript** (kind TRANSCRIPT) now prints on the University's template (`TRanscript_Template.docx`): the University's name,
  "(Office of the Registrar)", "ACADEMIC TRANSCRIPT", "(For External Use only)", the crest; NAME IN FULL (Surname Last), NUMBER,
  DATE OF BIRTH, SEX, DATES IN THE UNIVERSITY (ENTER)/(LEFT), FACULTY, DEPARTMENT, COURSE/SPECIALIZATION, DEGREE … AWARDED & CLASS; one
  ruled table (COURSE CODE/NO, COURSE TITLE, CREDIT UNIT, LETTER GRADE, GRADE POINT, WEIGHTED GRADE POINT), a box per semester, every
  attempt shown; TCR, TCE, TWGP and CGPA; the grading system, degree classification and abbreviations; and the signature boxes
  "Signature of Dean / Stamp and Date" and "Signature of Academic Secretary / Stamp and Date". The verification code and QR sit under
  the boxes. `lib/document-pdf.ts` → `moaumTranscriptPdf`. Sessional and mini-transcripts and statements keep the earlier layout.
  `credentials.build_statement` (restated from V488) adds `dateOfBirth`, `sex` and `leftSession`; nothing else in it changed.
* **The template version**: V668 retires the active TRANSCRIPT template and adds a new version with the title, subtitle and the two
  signature boxes above. Documents already issued keep the version they were issued under.
* **The covering letter** (`Transcript_Letter.docx`) for a copy sent to a recipient: the matriculation number as the reference, the
  date, the recipient's address, "ACADEMIC TRANSCRIPT IN RESPECT OF …", the body, "Kindly treat as confidential", and the officer who
  produced the transcript as "Desk Officer Transcript, For: Academic Officer". Its wording is one row in `credentials.cover_letter`
  (`[HOLDER]`, `[MATRIC]`, `[PURPOSE]` are filled in); `signatory_name` NULL means the producing officer. It is the first page of the
  recipient's secure download, and the desk prints it from **Covering letter** on the request
  (`/credentials/documents/requests/{id}/letter`). There is no letter for the graduate's own copy.

## Delivery

V262's release still makes the deliveries: a 30-day secure link to the recipient's email, and a physical delivery for a posted copy. For
a graduate's own request made without an account (they cannot use the student portal's library), a trigger on `credentials.delivery`
(`trg_public_delivery_sent`) emails them their own secure link at release.

## The desk

* `GET /api/v1/documents/identity-reviews`: the identity documents waiting for a person.
* `GET /api/v1/documents/requests/{id}/identity`: the document itself (the documents office only; `Cache-Control: no-store`).
* `POST /api/v1/documents/requests/{id}/identity {accept, note}`: accept, or refuse with a reason. A refusal rejects the request; the
  requester is emailed either way.
* `GET /api/v1/documents/requests/{id}` now carries `publicSide` and `coverLetter`.
* `GET /api/v1/verify/download/{token}` now carries `letter` for a recipient's token.

## Before going live

* **Legacy alumni must be on the register.** A graduate is found in `people.student` by matriculation number and date of birth. Past
  results held for students not yet on the register post once the students are loaded (Student migration → Students, then Past results).
  A graduate with no date of birth on the record cannot use the code route until it is filled in.
* **Contacts on record.** The code route needs an email or phone in `people.student_contact`. Without one, the graduate is sent to the
  identity-document route.
* **The fee** is the TRANSCRIPT document policy's (Documents office → Settings).
* **`moaum.portal-url`** must be the portal's public address: the status and consent links in the emails are built from it.

## Tests

* `db/check.sql`: two V668 properties (the public doors, identity and consent; the statement, the letter and the delivery email).
* `TranscriptPublicIT`: the three routes through the API, the identity document refused when it is not what it says, the desk's review
  list, document, acceptance and the request's public side and letter.
