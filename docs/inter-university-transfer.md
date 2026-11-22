# Inter-university transfer

*Oct 2026 (V588).* Academic Office → **Inter-University Transfer** (`/transfers/inter-university`) records students who come to
the University from another university (**incoming**) and students who leave for one (**outgoing**), many at a time from a
spreadsheet. Such transfers are approved by the Senate under the University's transfer policy.

*Nov 2026 (V763).* One student at a time is registered on **Inter-University Transfer Form**
(`/transfers/inter-university/form`), under the same rules and the same decision by another officer; see
[The form](#the-form).

*Nov 2026 (V766).* A student of another university also **applies online**, on their own, at `/transfer/apply`. The Registry checks
the documents, the Head of Department recommends, and the Registry approves the application into a transfer of one (batch source
`APPLICATION`), which comes here for another officer's decision like any other. See
[Inter-university transfer applications online](inter-university-transfer-applications.md).

The student is always looked for first, so no one is placed twice. An incoming student who is already on the register is that
record; an applicant under the JAMB number is linked to the new record; only otherwise is a record made. An outgoing student
keeps the record and every row of its history; only the status changes.

## The list of universities

The other university is named by its code (**Universities** tab, `ref.university`), never in free text. The Academic Office and
the Registry add a university or put its name, country or standing right (`ref.save_university`). A code is never renamed; one no
longer used is marked *not in use* and refused on new rows. The list starts with thirteen Nigerian universities. Benue State
University is not on it: it is this University's own former name.

## The steps

1. **Templates.** One file may hold both directions.
   - *Outgoing*: choose a faculty, department, programme or level. The template lists the students as the record holds them
     (`people.transfer_template`, as in V587). Keep the rows of the students who leave, and give the destination's code.
   - *Incoming*: a blank template. One row a student, with the JAMB number.

   The columns are Transfer Direction, Student Matriculation Number, JAMB Number, Student Name, Sex, Date of Birth, Email, Phone,
   Faculty Code, Department Code, Programme Code, Level, University Code, Other University Programme, Other University Level,
   Other University Matriculation Number, Other University Entry Session, Other University CGPA, CGPA Scale, Documents Seen,
   Effective Session, Reason, Approval Reference and Remarks. For an outgoing row, the faculty, department, programme and level
   are the student's own; for an incoming one, they are where the student comes in. The columns V763 added are optional on a
   file (see [The form's particulars](#the-forms-particulars)).
2. **Upload.** Upload the filled file (Excel or CSV). Every row is checked (`people.university_transfer_check`) and previewed:
   - the counts: total (incoming and outgoing), valid, valid with points to look at, invalid, and the new records the decision
     would make;
   - each row with what the decision would do: transfer out, record on the existing record, make a record with the applicant
     linked, or make a record.

   **Download error report** gives every row with its status and the reason. Correct the file and upload it again: nothing is
   corrected silently.
3. **Prepare.** Give the reason (the Senate's approval) and the approval reference. The rows are checked again and a batch is
   made (`IUT/YYYY/NNNNNN`, `people.university_transfer_batch`), with a transfer awaiting a decision for each valid row
   (`people.university_transfer`). While any row is invalid, the batch is refused unless the officer ticks *Prepare the valid rows
   alone*. The invalid rows are then kept with their reasons (`people.university_transfer_left_out`).
4. **Decide.** Another officer of the Academic Office or the Registry approves or rejects (**Batches → Open**): the whole batch,
   or one transfer at a time. A batch says where it came from: a file, the form, or (V766) an online application, whose
   transfer links the application. A rejection needs a note. Each transfer is checked again on the records as they stand. One that is
   refused now (because a record changed since) is said with the reason and left waiting; the others are decided. **Nothing on
   any record changes before this.**

## The form

Academic Office → **Inter-University Transfer Form** (also **Register one student on the form** on the Inter-University
Transfer page). The Academic Office, the Registrar, the Deputy Registrar and the Super Administrator register; Records does not.

1. **The transfer.** *Coming in from another university* or *Going out to another university*.
2. **The student.** Give the number and press **Find** (`people.university_transfer_lookup`, told the direction). The form is
   checked only once the number as it stands has been looked up. A transfer of the student already waiting is named.
   - *Coming in* (the JAMB number alone, as the check reads an incoming form; directly or through the applicant): a student
     already on the register is that record. Their placement is shown and fixed, and the transfer is recorded on the record. An
     applicant under the number is linked to the new record; the name and sex the application holds fill the form where it had
     none. Otherwise the surname, other names, sex and date of birth are given (the e-mail and phone are optional).
   - *Going out* (the matriculation number, a former one, or the JAMB number): the student must be found and live. The faculty,
     department, programme and level are read from the record, never typed. An applicant is not looked for.

   Another number undoes what the last Find filled in, wherever the officer left it as it was.
   An answer to an earlier Find is dropped.
3. **The other university.** The university, from the list. **Not on the list? Add it** adds one there and then: the code,
   the name and the country. It is chosen, and the form keeps what is filled in. Then the programme
   there. For a student coming in, also the level reached there and the matriculation number there; the session entered there
   and the CGPA with its scale (5-point or 4-point) are optional. For a student going out, the level and matriculation number
   there are optional.
4. **Where the student comes in.** The faculty, the department, an undergraduate programme and one of its own levels, each
   chosen once the one before it is. A postgraduate programme is not offered; the School of Postgraduate Studies admits those
   students. For a student going out, and for a student coming in whom the register holds, this is the record's placement,
   shown.
5. **Documents seen.** Coming in: the transcript, the letter of release, the JAMB admission letter, the O'Level result. Going out:
   the student's written application, the receiving university's letter of acceptance.
6. **The approval.** The effective session (blank: the current one), the reason (ten characters or more), the approval reference,
   and remarks.

**Check the form** (`people.university_transfer_form_check`) shows whom it is about, the status, what the decision would do,
the problems to put right and the points for the officer who decides it. A name that does not carry the surname of the record
the number finds is a point to look at (`NAME_DIFFERS`), on a form (its surname and other names) as on a file. **Register the transfer** is open only once the form as it stands has been
checked with no problem. The form is checked again as it is registered (`people.register_university_transfer`): a batch of one,
`IUT/YYYY/NNNNNN` with source FORM, awaiting another officer's decision. **Open the transfer** opens it on the Inter-University
Transfer page (`?batch=`). There it is decided like any other; nothing on a record changes before then.

### The form's particulars

Besides a row's rules (below), the form must give:

| Code | When the form is refused |
|---|---|
| `OTHER_MATRIC_MISSING`, `OTHER_PROGRAMME_MISSING`, `OTHER_LEVEL_MISSING` | coming in: the matriculation number, programme or level at the previous university is not given |
| `SEX_MISSING`, `DATE_OF_BIRTH_MISSING` | coming in, a new record: the sex or the date of birth is not given |
| `OTHER_PROGRAMME_MISSING` | going out: the programme at the receiving university is not given |

The particulars are checked on a form and on a file's row alike, whenever they are given:

| Code | When the row is refused |
|---|---|
| `OTHER_MATRIC` | the matriculation number there is not letters, digits and `/ . - _`, up to 40 |
| `ENTRY_SESSION` | the session entered there is not written 2022/2023, or is after the transfer's session |
| `CGPA`, `CGPA_SCALE` | the CGPA is not a number with up to two decimals, or is above its scale; the scale is not 4 or 5; a scale with no CGPA |
| `OUTGOING_PARTICULARS` | a student going out is given a session entered or a CGPA (they are a student coming in's) |
| `DOCUMENTS` | a document is not on the form's list, or is the other direction's |

Points to look at: `CGPA_SCALE_ASSUMED` (a file's CGPA with no scale, read on the 5-point scale), and, when the documents seen
are stated, `TRANSCRIPT_NOT_SEEN` and `RELEASE_LETTER_NOT_SEEN` (coming in) or `ACCEPTANCE_LETTER_NOT_SEEN` (going out). On a
file, Documents Seen lists the codes (TRANSCRIPT, RELEASE_LETTER, JAMB_ADMISSION_LETTER, OLEVEL_RESULT, STUDENT_APPLICATION,
ACCEPTANCE_LETTER) separated by commas.

The transfer keeps the particulars (`other_matric_no`, `other_entry_session`, `other_cgpa` with `other_cgpa_scale`, `documents`,
`remarks`). The remarks of the transfers prepared before V763, kept with the row as uploaded, were carried into `remarks`. The batches say whether a file or the form made them (`people.university_transfer_batch.source`). The transfers are
found by the matriculation number at the other university too, and the report carries it with the CGPA and the source.

## What a row must be

| Code | When the row is refused |
|---|---|
| `DIRECTION` | the direction is not INCOMING or OUTGOING (IN and OUT are read as those) |
| `UNIVERSITY_MISSING`, `UNIVERSITY_UNKNOWN` | no university code is given, or the code is not on the list (or not in use) |
| `SESSION` | the effective session is not one of the University's |
| `TRANSFER_PENDING` | an inter-university transfer of the student, or of the JAMB number, already awaits a decision |
| `DUPLICATE_ROW` | the student (or JAMB number) is on more than one row. Every one of those rows is refused |
| **Outgoing** | |
| `STUDENT_NOT_FOUND` | no student holds the matriculation number, a former number kept by a correction (V579), or the JAMB number. The name is never used to find a student, only compared (`NAME_DIFFERS` is a point to look at) |
| `STUDENT_STATE` | the record is not live (graduated, withdrawn, transferred out already) |
| `SOURCE_PROGRAMME_MISMATCH`, `SOURCE_LEVEL_MISMATCH` | the faculty, department, programme or level the row states is not the student's current one |
| `CHANGE_UNDER_WAY` | an inter-departmental transfer or a programme swap of the student is under way |
| **Incoming** | |
| `JAMB_MISSING` | no JAMB number: it is how the student is matched |
| `TARGET_*` | the programme is not on the register, is archived or not undergraduate, is not in the department or faculty named, or does not have the level |
| `STUDENT_EXISTS` | the student is on the register already on another programme or level. No second record is made; a change of placement is a programme swap (V578). On the same placement the transfer is recorded on that record (a point to look at) |
| `STUDENT_EXISTS_CLOSED` | the student is on the register already with a closed record. The Registry takes it up again |
| `NAME`, `SEX`, `DATE_OF_BIRTH`, `EMAIL`, `PHONE` | a new record's name is not SURNAME, Other names; sex is not M or F; the date is not YYYY-MM-DD; the e-mail or the Nigerian phone number is not one |

Points to look at: `APPLICANT_LINKED` (an applicant under the JAMB number becomes the new record's applicant), `FORMER_MATRIC`,
`NAME_DIFFERS`, and `SUSPENDED` (a suspended student transferring out).

## What the decision does

- **Outgoing.** The status becomes TRANSFERRED_OUT through `people.change_status`. The batch reference and the approval
  reference are the instrument, the destination is the reason, and the student is told. The matriculation number,
  registrations, results, payments and documents stay; the destination university, programme and level stay on the transfer.
- **Incoming, a new record.** The record is made as an admitted student's is: an admission number from the University's series
  (drawn until free), status ADMITTED, entry mode TRANSFER, entry and current level as stated, in the effective session. The
  applicant is linked where there is one, and the contact the row gives is kept. The previous university, programme and level
  stay on the transfer. The matriculation number follows under Matriculation Management, as for any admitted student.
- **Incoming, an existing record.** Nothing on the record changes; the transfer is recorded on it.

## Who

| | Reads | Prepares | Decides | Keeps the list of universities |
|---|---|---|---|---|
| Academic Office, Registrar, Deputy Registrar, Super Administrator | yes | yes | yes, but not a transfer they prepared themselves | yes |
| Records | yes | no | no | no |

## API

`/api/v1/transfers/inter-university` (`UniversityTransferController`):

| Call | Purpose |
|---|---|
| `GET /universities`, `POST /universities {code, name, country, active}` | the list of universities |
| `GET /template?faculty=&department=&programme=&level=` | an outgoing template's rows |
| `POST /validate {rows, session}` | check the rows |
| `POST {rows, session, reason, approvalRef, filename, validRowsOnly}` | prepare the batch |
| `GET` and `GET /{id}` | the batches, and one with its transfers and the rows left out; V766: each transfer approved from an online application carries `application {id, applicationNo}` |
| `POST /{id}/decide {approve, note}` | decide every waiting transfer of a batch |
| `POST /transfers/{id}/decide {approve, note}` | decide one transfer |
| `GET /transfers?q=&direction=&student=` | the transfers by search, direction or student (the report) |
| `GET /lookup?number=&direction=` | V763: who a number finds for the direction — the student (coming in: by the JAMB number alone), the applicant under a JAMB number (coming in), a transfer already waiting |
| `POST /form/check {form, session}` | V763: the form checked |
| `POST /form {form, session, reason, approvalRef}` | V763: the form registered as a batch of one |

The form's fields: `direction`, `matricNo`, `jambRegNo`, `surname`, `otherNames`, `sex`, `dateOfBirth`, `email`, `phone`,
`faculty`, `dept`, `programme`, `level`, `universityCode`, `otherProgramme`, `otherLevel`, `otherMatricNo`, `otherEntrySession`,
`otherCgpa`, `otherCgpaScale`, `documents`, `remarks`. The lookup, the check and the registration are the Academic Office's and the
Registry's (not Records').

A file takes up to 1,000 rows. `people.university_transfer.programme_code` is classed KEEP for the V574 programme merge.

`people.university_transfer_batch.source` is `FILE` (a spreadsheet), `FORM` (V763, one student on the form) or `APPLICATION`
(V766, an online application the Registry approved: `admissions.iut_application.transfer_id`). When the deciding officer rejects
such a transfer, the application goes back to the Registry's desk (recommended again) and the applicant is not told; the
Registry approves it again, as a new batch of one, or rejects it with words the applicant reads.
