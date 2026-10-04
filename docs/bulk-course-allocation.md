# Bulk Course Allocation to Lecturers (V321)

A spreadsheet of staff numbers and course codes becomes teaching allocations — the same allocations the
allocation desk makes one by one, read by the lecturer's teaching page, the score sheets and the result
pipeline. The file is judged against the register row by row before anything is written, and it never
creates or changes a lecturer, a course, a department, a programme, a session or a semester.

## A. What existed (the gap analysis)

| Need | Already there | Gap |
|---|---|---|
| The allocation | `catalogue.offering.lecturer_id` (lead), `second_examiner_id`, `catalogue.offering_teacher` (co-lecturers), `catalogue.allocate_offering` with the 12-unit rule and the score sheet opened in the lead's name (V041, V158) | No way to make many at once |
| The desk | `/allocate` (Head of Department, Dean, Academic Office, Registry, Administrator): one offering at a time, lecturers from other departments on an explicit toggle, overload on an explicit press | No template, no file, no preview, no history |
| Lecturers | `iam.person.staff_number`, a live `lecturer` (or `hod`) grant over a department, `hrm.staff_record.home_department`, `ended_on` | — |
| Courses and offerings | `catalogue.course` (code, department, kind GST = service course), `catalogue.course_offer` (programme, level), `catalogue.offering` per session and semester (opened with registration or added by the Academic Office) | — |
| Sessions | `policy.academic_session` with its number of semesters | — |
| Imports elsewhere | Lecturer upload, courses upload, fee schedule: a file read in the browser, rows posted as JSON, the server validating | No import record, no idempotency, no error report |
| Scope and audit | `OfficeScope`, `audit.attach` on every table | — |

## B. What V321 adds

- **Template** (Download template on the allocation desk): the Allocations sheet with the columns Staff ID*,
  Lecturer name, Lecturer department, Course code*, Course title, Course department, Programme, Level,
  Session*, Semester*, Role, Cross-department; an Instructions sheet; and reference sheets — Lecturers
  (staff numbers), Courses, Programmes, Departments, Sessions — read from the register at download.
- **Column mapping**: headings are matched by name, not by position; the mapping is shown and can be changed
  before validation. `.xlsx` and `.csv`, up to 20 MB and 50,000 rows.
- **Validation** (`POST /api/v1/allocation/import/validate`, nothing written): the register is loaded in
  batches for everything the file names and every row is judged in memory —
  `INVALID_REQUIRED_FIELD`, `INVALID_FORMAT`, `SESSION_NOT_FOUND`, `SEMESTER_NOT_FOUND`, `STAFF_ID_NOT_FOUND`,
  `LECTURER_NOT_FOUND` (no lecturer's office), `LECTURER_INACTIVE`, `LECTURER_NAME_MISMATCH` (warning),
  `DEPARTMENT_NOT_FOUND`, `LECTURER_DEPARTMENT_MISMATCH`, `COURSE_NOT_FOUND`, `COURSE_ENDED`,
  `COURSE_TITLE_MISMATCH` (warning; the catalogue stands), `COURSE_DEPARTMENT_MISMATCH`,
  `CROSS_DEPARTMENT_NOT_ALLOWED` (a course of another department needs YES in Cross-department, as the
  desk's toggle does; GST and other service courses need none), `OUT_OF_SCOPE` (a Head of Department's own
  department, a faculty office's faculty), `PROGRAMME_NOT_FOUND`, `PROGRAMME_ARCHIVED`,
  `COURSE_NOT_OFFERED_TO_PROGRAMME`, `INVALID_LEVEL`, `COURSE_NOT_OFFERED` (no offering in that session and
  semester), `DUPLICATE_IN_FILE`, `ALLOCATION_ALREADY_EXISTS` (EXISTING, left as it is),
  `ALLOCATION_EXISTS_OTHER` (another lead on record; replaced only with the Replace option, then
  `WILL_REPLACE_LEAD`), `CO_LECTURER_IS_LEAD`, `SECOND_EXAMINER_IS_LEAD`, `LECTURER_WORKLOAD_EXCEEDED`
  (over 12 units; imported only with Allow overloads, as the desk's overload press). Each finding carries a
  message and the recommended action. A course code is matched exactly, then without spaces (the
  register's own rule, V316); a staff number exactly; a name is never used to find a lecturer.
- **Preview**: the counts (rows, will be imported, will not, already on record), the options (ticking one
  re-validates the file at once with the new value, so the counts never describe a stale option), a filter
  by status that opens on the errors when there are any, every row with its findings, and the error report.
- **Import** (`POST /api/v1/allocation/import`): the file is validated again on the server and the valid
  rows are written in one transaction — a lead through `catalogue.allocate_offering` (keeping the second
  examiner on record), a co-lecturer into `offering_teacher`, a second examiner onto the offering — so a
  database error leaves nothing half done. The import key the preview was given makes a repeated press
  answer with the record already made. Each lecturer allocated is told by e-mail through the notice queue.
- **Record and history**: `catalogue.allocation_import` (audited) with a reference numbered in the
  session (`ALLOC/2026-2027/00017`), the file, the uploader and office, the session and semester, the counts,
  the status (COMPLETED, COMPLETED_WITH_ERRORS, NOTHING_TO_IMPORT), the options and every finding;
  `GET /api/v1/allocation/imports` scoped to the office; the error report of any past import.
- **Export**: the allocation table downloads as a branded workbook with S/N through the central document
  system; the desk's print goes through it too.

## C. Integration, unchanged by design

The import writes the same offering fields the desk writes. The lecturer's teaching page, the score
sheets (`Sheets.DESK`, `assessment.teaches`), the Programme Examinations Officer's upload on behalf, the
HOD's and faculty's monitors and the nine-stage pipeline all read `catalogue.offering` and
`offering_teacher`; nothing else was added for them to read.

## D. Tests

- `AllocationImportIT` — fifteen rows exercising every category above, nothing written by validation, a
  lecturer's token refused, an import without its key refused, six rows imported and on the offerings, the
  same key answering with the record already made, EXISTING and ALLOCATION_EXISTS_OTHER on a second file,
  the overload refused then allowed, the history in the department's scope and hidden from another
  department's Head, and the lecturer's teaching page and the desk reading the same allocation.
- `db/check.sql` 166 — the import record numbered in the session, idempotent on its key.
