# Academic standing: a missing result is not a zero (V421)

**The rule.** No result is not a zero, not a failure, not an outstanding course and not probation. CGPA and standing come
only from authoritative results: published, under a Senate minute, with an outcome recorded for the student.

## What was wrong

A student whose results were never uploaded read *"You are on probation — your CGPA stood at 0.00 after the 2024/2025 second
semester at 100 level"*. V243 had made the student's record read **no score on a published sheet** as an absence (ABS, F,
0 points, its units counted), so that the student's record would agree with the Senate broadsheet. A sheet cannot leave the
lecturer with a blank (I-RES-4: every candidate on the roster is graded, absent, withheld, incomplete, malpractice or
exempted), so a published sheet with no outcome for a student means the student was **never on that sheet**. That happens
most often with a registration migrated from the old portal whose results were not migrated, on a sheet the legacy upload
published for the students it had rows for. It also happens with a registration added after the sheet was published. Every
such course counted as an F, the CGPA fell to 0.00, and `assessment.student_standing` pronounced probation.

## What V421 does

| Piece | Before | Now |
|---|---|---|
| `assessment.student_results` | no outcome on a published sheet = ABSENT, F, 0 points, published | **NO_RESULT**: not published for the student, no grade, no points; a **recorded** absence stays ABSENT/F |
| GPA / CGPA (`student_gpa`, `student_cumulative`) | counted the F | leave it out: no result means no CGPA (`NULL`, shown "—"), never 0.00 |
| Carryovers (`registration.carryovers`) | only a published F (unchanged) | unchanged: a missing result never becomes an outstanding course |
| `assessment.student_standing` | latest semester with any published result | the latest semester whose results are **complete** (every registered course published), with a CGPA; before any such semester **NOT_AVAILABLE** (was GOOD) |
| Threshold | 1.0 written into `assessment.standing_of` | `policy.standing_setting.probation_below_cgpa` (1.00 until the Academic Office or the Registry changes it on *Cohorts → Settings → Academic standing*) |
| Result status | none | `assessment.student_result_periods` / `student_result_status`: PUBLISHED, INCOMPLETE, PROCESSING, UNDER_VERIFICATION, NOT_AVAILABLE per registered semester |
| Offices | probation from the register status only | `assessment.result_status_counts` → `GET /api/v1/results/student-status`: students in scope by result status, with probation counted only from complete published results |

**The standing's states.**

- `NOT_AVAILABLE`: no complete published semester yet.
- `GOOD`: the latest complete semester meets the threshold.
- `PROBATION` or `ADVISED_TO_WITHDRAW`: Senate's rule (V244, V246) on the latest complete semester, against the threshold.

A semester that is partly published, under verification, in the approval chain or not uploaded pronounces nothing. A
standing pronounced on an earlier complete semester stands until the next complete one, and the message names the semester
it was pronounced on.

**What the student reads** (`/api/v1/me` → `probation`; the dashboard):

- **Result not available.** *"Your result for the 2024/2025 second semester has not yet been uploaded or published."*
  This and the next four messages carry a *View results* button.
- **Result pending (under verification).** *"… is under verification."*
- **Result pending (processing).** *"… is being processed and has not yet been published."*
- **Result incomplete.** *"3 of your 8 courses for the … are published; the rest are still being processed. Your standing is
  read when the semester's results are complete."*
- **On probation.** Only on complete published results: *"Your CGPA stood at 0.85 after the 2024/2025 second semester at
  100 level, below the University's minimum requirement of 1.00."* The values come from the record and the setting.

The semester the student is told about is the latest one that has ended on the calendar. A semester still running is not
reported as missing. On the Results page, a course with no result reads *"No result recorded — not on the published sheet;
your department records it"*, and the CGPA reads "—" until something is published.

**The offices.** The Result Pipeline monitor (`/results/pipeline`) carries *Students by result status* for the scope
(programme, department, faculty or the University; by default the latest semester the calendar has closed):

- result not uploaded
- under verification
- processing
- incomplete
- published
- on probation
- advised to withdraw

It is loaded after the page so a large scope does not hold the monitor up. A department of about a hundred students
counts in about a third of a second.

**Migrated students.** A student whose record and registrations came over but whose results did not reads *result not
available*, never 0.00. When the old portal's results are uploaded (`assessment.import_legacy_semester`), they become
published results like any other and the standing is read from them.

**Security.** A student reads only their own standing and results (`/api/v1/me`, `/api/v1/me/results`: the token's
subject); the counts are bound to the office's scope (`OfficeScope.bound`).

**Tests.** check.sql has the V421 property, eight invented students:

- no result
- published below the threshold, which is probation with its real F a carryover
- published above it
- partial
- under verification
- at Senate
- an older session only
- a recorded absence

It also covers the threshold changed and refused to a lecturer, and the counts. `AcademicStandingIT` covers the same through
the API, rerunnable on one database.
