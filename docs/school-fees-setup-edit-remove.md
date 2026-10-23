# School fees setup: edit and remove incorrect lines (V648)

The University's master prompt of 23 October 2026 asked that a fee line added by mistake (Industrial Chemistry 600 Level) can be
corrected or removed, without touching a payment, an invoice, a receipt or the ledger.

## How the fee setup works

The setup is `finance.fee_schedule`: one line per item, amount and scope (session, level, entry mode, faculty, programme, fee group,
semester, indigeneship, spillover year). A student's charge is computed from the lines in force (`ended_at IS NULL`) each time it is
read. A payment reference (the invoice) keeps the amount it was generated with. Nothing references a line by key, so ending or
editing a line never changes a reference, a payment, a receipt or a ledger entry. It changes what is owed from then on.

## Used or not: the database decides

`finance.fee_line_usage(lines)` answers for each line. The screen never decides.

| Use | Meaning | Remove |
|---|---|---|
| Never used | No student is charged by it; no invoice, payment or ledger entry was made under it | Removed permanently |
| Charged to students | Part of what students owe now; nothing generated under it | Archived |
| Used by invoices | School-fees references generated, while it stood, by students within its scope | Archived |
| Used by payments | Some of those references paid | Archived |
| Used by the ledger | Those payments posted to the general ledger | Archived |

"Within its scope" is read generously: the line's programme, faculty (or the faculty charged as), entry mode, fee group and level,
at any level the session knows the student at (the record, the session's enrolment, its course registration). "While it stood"
means generated after the line was stated (its first audit entry) and before it was ended. Old-portal payments of the session count.

## Remove, deactivate (archive)

`finance.remove_fee_lines(lines, mode, reason code, reason, apply)`:

- **REMOVE**: a line never used is deleted; a used one is answered `CANNOT_REMOVE` and left as it is.
- **DEACTIVATE**: the line is archived: ended, kept on record, no longer charged.
- **AUTO** (Remove selected): each line removed or archived, as its use decides.

Without `apply` it is the preview: the same answer, nothing changed. A reason is required: added in error, wrong level, duplicate fee
structure, wrong programme, wrong faculty, wrong session, wrong semester, replaced by corrected structure, or other (described in ten
characters at least). Every removal and archive is kept in `finance.fee_line_change` with the line as it was, its use, the reason,
who and when. The audit trail carries the reason too.

## Edit

`finance.edit_fee_line(line, values, reason)`:

- A line no invoice or payment was made under is corrected in place (**EDITED**).
- A line that was is **VERSIONED**: it is ended and kept, and the corrected line is stated beside it. `finance.fee_line_change` names
  both. Every invoice keeps its amount; new invoices take the corrected line.

The edit is refused when another line in force states the same scope (`FEE_LINE_DUPLICATE`), or when it moves the line to a level
outside the programme structure (`FEE_LEVEL_NOT_IN_STRUCTURE`).

## Levels from the programme structure

`finance.fee_levels_of(programme)` reads the programme structure (`people.programme_levels`, as the programme swap reads it, up to the
charge engine's final level). `finance.fee_line_level_problem(level, programme, faculty, spillover)` says why a level is outside it:

- a programme line at a level the programme does not run;
- a faculty or University line at a level no programme of it runs;
- a spillover line not at a programme's final level.

A new line, or a line moved to another level or scope, is refused at such a level. A line already there is flagged on the schedule
("Not in the structure"). Nothing is removed until the Bursary confirms.

On the live-shaped copy (2025/2026, 840 lines): 72 lines are flagged, the 500 Level faculty-wide lines of Arts, Communication and
Media Studies, Education, Administration and Management, Social Sciences, and Technology and Industrial Studies, where no programme
runs to 500 Level. All 72 were never used, so each would be removed permanently. Of the 840 lines, 368 were never used, 12 are
charged to students only, 224 are used by payments and 236 by the ledger.

## Who may

`finance.fee_setup_grant`, checked by the API and by the functions:

| Permission | Bursar, platform | Students Account Officer | Registry, Academic Office, Audit, ICT, VC, DVC |
|---|---|---|---|
| VIEW_FEE_SETUP | ✓ | ✓ | ✓ |
| CREATE_FEE_STRUCTURE | ✓ | ✓ | |
| EDIT_FEE_STRUCTURE | ✓ | ✓ | |
| REMOVE_FEE_STRUCTURE | ✓ | | |
| DEACTIVATE_FEE_STRUCTURE | ✓ | ✓ | |
| VIEW_FEE_STRUCTURE_HISTORY | ✓ | ✓ | ✓ |
| EXPORT_FEE_STRUCTURE | ✓ | ✓ | ✓ |

The Students Account Officer kept what V520 gave (state, edit, end) and was not given REMOVE.

## The screen

**Finance → Fee Setup and Schedule**, "The charges for <session>": S/N, Item, Faculty, Department, Programme, Level, Semester, Amount,
Status, and the actions View, Edit, Remove (or Deactivate for a line with financial dependencies, and for the Students Account
Officer) and History. Filters: faculty, programme, level (with "Outside the programme structure"), status (active, archived, removed,
all), use, semester, spillover, students. Tick lines and choose **Remove selected** for a bulk removal with its preview. The Excel and
PDF reports carry the status when they list more than the lines in force.

## API

| Method | Path | |
|---|---|---|
| GET | `/api/v1/finance/fee-setup/permissions` | The acting office's grants |
| GET | `/api/v1/finance/sessions/{s}/{y}/schedule?status=ACTIVE\|ARCHIVED\|ALL` | The lines, with status, department and level problem |
| GET | `…/schedule/usage?ids=…&status=…` | Each line's use |
| POST | `…/schedule/remove/preview` | `{ids, mode}`: what removing would do |
| POST | `…/schedule/remove` | `{ids, mode, reasonCode, reason}` |
| PUT | `…/schedule/{id}` | Edit: `{…, reason}`; the answer's `edit` says EDITED, VERSIONED or UNCHANGED |
| POST | `…/schedule/{id}/end` | Deactivate one line (optional `{reasonCode, reason}`) |
| GET | `…/schedule/{id}/history` | Every version of the line |
| GET | `…/schedule/removed` | The lines removed permanently |

Tests: `db/check.sql` (V648, two properties), `FeeSetupIT`, `frontend/src/lib/fee-setup.test.ts`.
