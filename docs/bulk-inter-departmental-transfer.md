# Bulk inter-departmental transfer

*Oct 2026 (V587).* Academic Office → **Bulk Inter-Departmental Transfer** (`/transfers/bulk`) records many students who moved
from one department to another, from a spreadsheet. Such moves were approved by the Senate and recorded on paper or in the old
portal.

There is no second system. Each row becomes a **programme swap** (V578, kind `ACADEMIC_TRANSFER`), so a move from a file is
checked, made, kept in the programme history and told to the student exactly as a single swap is — and, since V633, made at
once by the officer who uploads the file, with no second level of approval. The student's own application, with its committee,
Senate and fee (V070, `/transfers`), stays as it is.

## The steps

1. **Template.** Choose a faculty, department, programme or level, and download the template
   (`people.transfer_template`). It lists the department's students with their current faculty, department, programme and
   level in the *Old* columns. The *New* columns are left for the office to fill, and the rows of students who are not
   transferring are deleted. The columns are:
   - S/N, Student Matriculation Number, JAMB Number, Student Name;
   - Old Faculty Code, Old Department Code, Old Programme Code, Old Level;
   - New Faculty Code, New Department Code, New Programme Code, New Level;
   - Effective Session, Effective Semester, Transfer Type, Reason, Approval Reference, Remarks.
2. **Upload.** Upload the filled file (Excel or CSV). Every row is checked (`people.transfer_upload_check`) and previewed:
   - the counts: total, valid, valid with points to look at, invalid, and the invalid rows that are on a duplicated student;
   - the table, which puts the current department on the record beside the old department the file states.

   **Download error report** gives every row with its status and the reason. Correct the file and upload it again: nothing is
   corrected silently.
3. **Transfer.** Give the reason (the Senate's approval) and the approval reference. The rows are checked again, and a batch is
   made (`IDT/YYYY/NNNNNN`, `people.transfer_batch`) with a programme swap for each valid row — each made at once by the officer
   who uploads the file (V633): the student is on the new programme when the call returns, and the batch reads `COMPLETED`, or
   `COMPLETED_WITH_EXCEPTIONS` where rows were left out. While any row is invalid, the batch is refused unless the officer ticks
   *Transfer the valid rows alone*. The invalid rows are then kept with their reasons.
4. **A batch left pending from before V633** is decided on the batch (**Batches → Open**) by any officer who may make a swap, the
   one who uploaded it included. The swaps are decided one by one: one that its record refuses (because the record changed
   since) leaves the others decided.

## What a row must be

| Code | When the row is refused |
|---|---|
| `STUDENT_NOT_FOUND` | no student holds the matriculation number, a former number kept by a correction (V579), or the JAMB number. The name is never used to find a student, only compared with the record (`NAME_DIFFERS` is a point to look at) |
| `SOURCE_PROGRAMME_MISMATCH` | the old faculty, department or programme the row states is not the student's current one |
| `SOURCE_LEVEL_MISMATCH` | the old level is not the student's current level |
| `TARGET_MISSING`, `TARGET_UNKNOWN` | no new programme is given, or the code is not on the register (an upload never creates a programme) |
| `TARGET_DEPARTMENT`, `TARGET_FACULTY` | the new programme is not in the new department, or the department is not in the new faculty |
| `TARGET_LEVEL` | no new level is given |
| `LEVEL_REDUCED` | the level goes down and the row gives no reason. With a reason it is a point to look at |
| `DUPLICATE_ROW` | the student is on more than one row. Every one of those rows is refused, and the office says which is meant |
| `PSW_*` | the programme swap's own refusals: the record is not live, the programme is archived or of another category, the level is not one of the programme's, a transfer or swap is already under way, a change was requested at admission, or the placement would not change |

The swap's review points come with each row: a change of faculty, a level below one already registered, the cohort engine's
level, the CCE route, and the registered courses the new programme does not offer.

## What changes, and what does not

A swap sets the student's programme and level and nothing else:

- the department and faculty follow the programme;
- the matriculation number, the account, the registrations, the results, the payments and receipts, and the documents all stay
  as they are;
- the old placement is kept in the programme history, which the full record shows;
- the student is told (`PROGRAMME_SWAP_COMPLETED`);
- course registration, the class lists, the statistics, the fee lines and the query engine read the new placement, because
  they read the record.

A matriculation number that must follow the move is corrected separately, under Matriculation Correction (V579).

## Who

| | Reads | Transfers | Decides a batch left pending from before V633 |
|---|---|---|---|
| Academic Office, Registrar, Deputy Registrar, Super Administrator | yes | yes | yes |
| Director of ICT | yes | yes | yes |
| Records | yes | no | no |

## API

`/api/v1/transfers/bulk` (`TransferBatchController`):

| Call | Purpose |
|---|---|
| `GET /template?faculty=&department=&programme=&level=` | the template's rows |
| `POST /validate {rows, session}` | check the rows |
| `POST {rows, session, reason, approvalRef, filename, validRowsOnly}` | make the batch: the students move at once |
| `GET` and `GET /{id}` | the batches, and one with every row and its swap |

The decision is the swap's own: `POST /api/v1/programme-swaps/batches/{id}/decide {approve, note}`. A file takes up to 1,000
rows.
