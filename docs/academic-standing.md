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

**The Senate broadsheet.** A registered course with no mark and no outcome is **NR**, no result. It is never ABS, never F,
never counted in the GPA and never owed. On a set past the Faculty Board, the student is not on the approved sheet:

- the remark names the course (*NR: …*);
- the row's standing reads *Incomplete*, never *Pass*;
- nothing is pronounced on that semester, so no *TO GO ON PROBATION* or *ADVISED TO WITHDRAW*;
- the reporting sheet counts *Candidates with a Result Not Available*, and the key explains NR.

A set still in the chain, or a course with no sheet yet, shows NR greyed as a mark not yet entered. A candidate the lecturer
**recorded** absent stays ABS, graded F, and owes the course. Before this, the broadsheet showed every blank as
ABS/F0, so the same student read 0.00 there and "result not available" on their own dashboard.

**Results not yet in** (`/results/pipeline`) lists every course with a registered candidate who has no mark or outcome,
wherever the set stands:

| Why | Meaning | Where to act |
|---|---|---|
| No mark entered yet / partly entered | the sheet is at entry | the sheet |
| Joined the roll after submission | in the chain | the chain (return it to the lecturer) |
| Not on the published sheet | published through the chain | the chain: a late result (V422) |
| Not in the old portal's results | the published set came from the old portal's upload | *Upload results* → Migrate from the old portal (Exams and Records, ICT) |
| No sheet / no lecturer | nothing to enter on yet | Sessions / Allocate |

*Download students* (`GET /api/v1/results/pipeline/missing-students`) gives the same list student by student: matriculation
number, name, programme, level, course, where the set is and why. It keeps the monitor's bounds: a lecturer sees only their own
courses, a HOD their department, the GST/EPS office its own courses, any other office its scope. A published set with
candidates missing is flagged *Results missing on the published set*.

**Every outcome, read alike (V422).** The University's rule, the same on the student's record, the broadsheet, carryovers
and the GST/EPS fee:

| Outcome | GPA | Owed (carryover) | Semester | Broadsheet |
|---|---|---|---|---|
| Graded | counted | an F is owed (never an elective) | complete | the mark and grade |
| Absent | an F, counted | **owed**, and a GST/EPS course is owed again | complete | ABS F0, *CO:* |
| Withheld, incomplete, malpractice | not counted | not owed | **held**: no standing until the Senate decides | WIT / INC / MAL, *HELD:* |
| Exempted | not counted | not owed | complete | EXE |
| No result | not counted | not owed | incomplete | NR, *NR:* |

A held result is never an F before the Senate decides. The decision comes as an amendment of the mark. The student reads
*Result held for the Senate*: "Your result for the … is published with 1 course held for the Senate's decision." Before
V422, a recorded absence was owed on the broadsheet but not carried over on the student's record, and withheld, incomplete,
malpractice and exempted counted as F0 on the broadsheet only.

**Late results (V422).** A candidate on a published sheet's roll with no mark on it has no result. This can be a
registration added after publication, or one migrated without its result. The course's lecturer, or the Programme
Examinations Officer on the lecturer's behalf, raises a **late result** from the sheet's chain, under *Amendments of the
published result → Raise an amendment or a late result*. The roll's candidates with no mark are listed there. It goes
through the same chain as an amendment, a different person at each desk, and the Registrar applies it on the Senate minute
as the candidate's first mark. The student is told "Your result in … is published", with no mark in the message. A student
who is not on the sheet's roll is refused (`RES_AMEND_NO_MARK`). On the pipeline, *Results not yet in* offers **Late
result** to the desk of entry for a candidate not on a published sheet.

**Held results and who the absent rule touches (V424).** Two read-only lists on the Result pipeline, for the Registry and
the result desks (never a lecturer), within the office's scope:

- **Held for the Senate**: every withheld, incomplete or malpractice result on a published sheet, in every session. It shows
  the student, the course, how many days it has waited, and the amendment carrying the decision when one is open.
  Each morning the Registrar, the Deputy Registrar and Exams and Records are emailed about any held longer than the
  University's days, at most once a week. The days are 30 until the Academic Office or the Registry changes them on
  *Cohorts → Settings → Academic standing*: 7 to 365, or 0 for no reminder. `assessment.held_reminder_log` keeps what was
  sent.
- **Owed after a recorded absence**: the students still on the register who owe a course only because of an absence, so it
  now comes back at registration. A course also owed for a graded F was owed before and is not listed.

The Bursary's GST fee panel (*Fees → GST fee*) has **Owed again after a recorded absence**. It lists the students who owe a
GST/EPS course again in the session because they were absent from it, and whether it is owed this session. Nothing is
charged or registered by any of these lists.

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
the API, plus the broadsheet's NR, the pipeline's missing list and its student list within a lecturer's bound. It can be
rerun on one database.
