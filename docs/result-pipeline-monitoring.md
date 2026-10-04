# Result Pipeline Monitoring, Live Broadsheets and Upload on Behalf (V318)

The nine-stage result chain the portal has carried since V013 — ENTRY → VERIFICATION → DEPT_BOARD →
FACULTY_SCRUTINY → FACULTY_COMPILATION → FACULTY_BOARD → RECORDS → SENATE → PUBLISHED — is unchanged.
V318 adds what it lacked: a monitor that reads every stage's real count from the record, coverage counted
from the rolls, a broadsheet that fills as the course sheets are entered, and a Programme Examinations
Officer's upload on the lecturer's behalf that is recorded as exactly that.

## A. What existed, and what was missing (the gap analysis)

| Need | Before V318 | Gap |
|---|---|---|
| The nine stages | `assessment.score_sheet.stage`, `assessment.advance` / `return_sheet`, `assessment.decision`, BR-006 (no two consecutive stages by one person) | None — kept as it is |
| Stage counts | `/results/pipeline` counted the listing on the screen; the HOD dashboard had four buckets | Counts were not drillable and said nothing about candidates; no stage had a "since when" |
| Coverage | The listing carried `candidates`; the lecturer's own list carried `entered` | Nothing in scope said expected / received / missing per course, per candidate, per programme and level |
| Missing results | The monitor of an examination session listed sheets still at entry | A sheet partly entered, an offering with nobody allocated (so no sheet at all), a candidate who joined the roll after submission: none was named |
| Exceptions | `failRate > 50` on the desk, `daysLate` on the listing | Returns, held scripts, sets stalled on a desk, uploads on behalf: not surfaced together |
| Needs attention | The desk screen (`t/resultdesk`) showed what sits at the office's stage | No single read of "what waits on me" with coverage beside it |
| Timeline | The chain of one sheet (`t/chain`) | No timeline across a scope |
| Broadsheet | Computed from the sheets; a score still in the chain shown grey | No coverage: how many cells are in, which courses and which candidates are still out |
| Upload on behalf | The Examinations Officer already held the ENTRY authority and could type marks on any sheet in the University | No reason, no record of who actually uploaded versus the lecturer of record, no scope |
| Scope | Listing bound by `OfficeScope.bound` (HOD → department, Dean/Faculty Officer → faculty); `ResultsService.own` bound only the lecturer | A sheet reached by its id was open to any desk office; the Programme Examinations Officer was bound to a department, not a programme; the Faculty Examinations Officer was unbound |
| HOD monitoring | `/api/v1/hod/dashboard` counted ENTRY / workflow / SENATE / PUBLISHED | Not drillable, no coverage, no programme-and-level view |

## B. What V318 adds

### Database (`db/V318__result_pipeline_monitoring_and_upload_on_behalf.sql`)

- `assessment.sheet_coverage(sheet)` — `expected` (the roll, `sheet_candidates`), `received` (candidates with a
  mark or an outcome on the latest version), `missing`, `graded`. Counted, never typed.
- `assessment.sheet_stage_since(sheet)` — when the sheet reached its present stage (the last decision into it,
  or the examination session's opening for a sheet still at entry).
- `assessment.score.entered_by`, `entered_office` — the actual writer of each version, filled by trigger
  `assessment.score_writer` from the attributed transaction; `on_behalf`, `on_behalf_reason` with
  `ck_score_on_behalf_says_why`.
- `assessment.sheet_upload` — one row per upload on behalf: `uploaded_by`, `uploader_office`, `owner_id`
  (the lecturer of record at the time), `reason` (required), `rows_written`, `uploaded_at`. Audited.
- `assessment.record_upload_on_behalf(sheet, reason, rows)` — refused without a reason
  (`RES_UPLOAD_ON_BEHALF_SAYS_WHY`), refused when the actor teaches the course (`RES_NOT_ON_BEHALF`),
  refused off entry.
- `assessment.teaches(sheet, person)` — lecturer, second examiner or co-lecturer of the offering.
- `catalogue.offering_serves(offering, programme)` — the offering is the programme's business: its course is
  offered to the programme on the structure, or a student of the programme holds an approved registration
  on it (a borrowed course). This is the Programme Examinations Officer's scope and the programme filter of
  every result desk, so a course the programme's students take from another department is not lost.

### API

- `GET /api/v1/results/pipeline?fac&dept&prog&session&sem` → `Sheets.PipelineView`: `stages` (nine, each
  with sheets and candidates), `coverage` (offerings with/without a lecturer, sheets, expected, received,
  missing, percent, published), `sheets` (every set with received/missing, days at stage, flags), `missing`
  (sheets short of marks and offerings with no sheet: NOT_STARTED / PARTIAL / NO_LECTURER / NO_SHEET),
  `alerts` (OVERDUE, COMPLETE_NOT_SUBMITTED, RETURNED, HIGH_FAIL, HELD_SCRIPTS, ROLL_GREW, STALLED,
  ON_BEHALF, NO_LECTURER), `attention` (what the acting desk may act on), `timeline` (decisions and uploads
  on behalf, newest first), `programmes` (every programme and level: students, cells, received, missing,
  published sets, percent). The office's bound applies whatever the parameters say.
- `PUT /api/v1/results/sheets/{id}/scores` takes `onBehalfReason`. When the writer is the Programme
  Examinations Officer or the Academic Office and does not teach the course, the reason is mandatory; the
  marks are written `on_behalf` with it, an `assessment.sheet_upload` row records the uploader and the
  owner, and the response says `onBehalf: true` with the `upload` id and the `owner`. The lecturer of record is
  told by an e-mail notice through `platform.queue_notice` when they have an address (who entered how many
  marks, in which office, and why).
- `POST /api/v1/results/sheets/{id}/advance` from ENTRY by such a writer requires `comment`; the SUBMIT
  decision is recorded as "Submitted on behalf of <lecturer>: <reason>". BR-006 then stops the same person
  verifying it. Nothing bypasses a stage.
- `GET /api/v1/results/sheets/{id}` carries `uploads`, `youTeach`, and each mark's `enteredBy`,
  `enteredOffice`, `onBehalf`.
- `GET /api/v1/results/broadsheet` carries `coverage` (cells, received, missing, percent, courses complete,
  candidates complete, sets published, per-course coverage with the sheet id, candidates still missing a
  result) and each row's `received` / `missing`.
- Scope enforcement (`OfficeScope`, `ResultsService.own`): the Programme Examinations Officer is bound to the
  programme their grant names (`actingProgramme`, the structure ladder pruned to it); the Head of Department
  to their department; the Dean, the Faculty Officer and now the Faculty Examinations Officer to their
  faculty; Exams & Records to the University. A sheet reached by its id outside the bound is refused (403),
  not only hidden from the listing. `Sheets.DESK` lets the Programme Examinations Officer act at ENTRY.

### Frontend

- `/results/pipeline` (menu "Result Pipeline" / "Result Monitoring") — the monitor: tiles, the nine stages
  as buttons with their counts (press one to list what sits there), every set with flags, results not yet
  in (with "Enter on behalf" for the Programme Examinations Officer, "Allocate" where no lecturer), the
  timeline, needs-attention and exceptions, live broadsheets by programme and level, Excel exports through
  `brandedXlsx`, and the stage guide on request.
- `/results/broadsheet` — "Live coverage" panel: results in, courses complete, candidates complete, sets
  published, per-course coverage with a link to the sheet, candidates still missing a result.
- Score entry (`/results/sheets/[id]`) — on-behalf mode for an officer who does not teach the course: the
  banner names the lecturer as owner, the reason is required before Save and Submit, the uploads on behalf
  are listed; the approval chain (`/results/chain`) shows uploads in the ladder, who entered each mark, and
  a "Submit on their behalf" act that asks for the reason.
- Dashboards — the Head of Department's and the examinations officers' homes carry `PipelinePanel`: the
  nine counts as links into the monitor, coverage, what needs the desk, exceptions, and the live
  broadsheets of every programme and level in scope. The Programme Examinations Officer's menu gains Result
  Monitoring and Broadsheet.

### Tests

- `ResultPipelineIT` — an officer of another programme is refused; the programme's officer is refused
  without a reason and nothing is written; with a reason the mark carries the officer as writer and the
  upload names the lecturer as owner; the sheet reports `youTeach` and `uploads`; the HOD's monitor counts
  the sheet at ENTRY with 1 of 2 received, lists the course as PARTIAL and the upload on the timeline; the
  other programme's monitor omits it; the HOD is refused another department; submission on behalf is
  refused without a reason, recorded with one, and the officer cannot verify; the broadsheet's coverage
  reads the column as complete.
- `ResultsIT` — every desk now acts from within a granted scope; a HOD of another department, an
  Examinations Officer of another programme and an officer with no scope are refused the sheet.
- `db/check.sql` 161–162 — coverage counted from the roll; an upload on behalf says why and names its
  uploader, at the function and at the table.

## C. Unchanged on purpose

The chain, its functions and BR-006; the lecturer's own entry (no reason asked of a teacher of the course);
the GST and EPS offices' entry of their own courses (V314), which is the office's own and not on anyone's
behalf; publication on the Senate minute alone.
