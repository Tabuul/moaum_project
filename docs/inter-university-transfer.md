# Inter-university transfer

*Oct 2026 (V588).* Academic Office → **Inter-University Transfer** (`/transfers/inter-university`) records students who come to
the University from another university (**incoming**) and students who leave for one (**outgoing**), many at a time from a
spreadsheet. Such transfers are approved by the Senate under the University's transfer policy.

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
   Effective Session, Reason, Approval Reference and Remarks. For an outgoing row, the faculty, department, programme and level
   are the student's own; for an incoming one, they are where the student comes in.
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
   or one transfer at a time. A rejection needs a note. Each transfer is checked again on the records as they stand. One that is
   refused now (because a record changed since) is said with the reason and left waiting; the others are decided. **Nothing on
   any record changes before this.**

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
| `GET` and `GET /{id}` | the batches, and one with its transfers and the rows left out |
| `POST /{id}/decide {approve, note}` | decide every waiting transfer of a batch |
| `POST /transfers/{id}/decide {approve, note}` | decide one transfer |
| `GET /transfers?q=&direction=&student=` | the transfers by search, direction or student (the report) |

A file takes up to 1,000 rows. `people.university_transfer.programme_code` is classed KEEP for the V574 programme merge.
