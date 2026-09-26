# Dossier E — Results, examinations, assessment policy, course allocation and the College of Health Sciences

Read-only audit of the repository at `C:\Users\ajene\Documents\moaumpp` (HEAD 8c2b6fa) and the local Postgres (all migrations to V263). Paths below are relative to the repo root; `api/…` means `api/src/main/java/ng/edu/moaum/portal/…` and `fe/…` means `frontend/src/…`. SQL function bodies were read from the live database (`pg_get_functiondef`); the migration that last defines each function is named beside it.

Modules covered, in order:

- A. Course allocation (`allocation`)
- B. Examination sessions, score sheets and the approval chain (`results`)
- C. Held scripts (`results`)
- D. Result queries and the examination slot (`results`, `studentportal`)
- E. Grading policy, GPA/CGPA, class of degree, probation and withdrawal (`policy`, `assessment` functions)
- F. Broadsheet, Senate schedule and publication (`results`)
- G. The student's results, statement of results, broadsheet, docket and public verification (`studentportal`, `verify`)
- H. CBT question bank (`cbt`)
- I. College of Health Sciences / MB;BS (`college`, `provost`)

---

# A. Course allocation  (API module: allocation; schema: catalogue.offering / catalogue.offering_teacher, assessment.score_sheet; page: fe/app/allocate)

## 1 Purpose
The Head of Department (or a wider office) names, for each course offering of a session and semester, the lead lecturer who owns the score sheet, an optional second examiner who verifies it, and any co-lecturers who may enter marks on the same sheet. Allocation is the act that makes a sheet exist: assigning a lead lecturer while the examination session is OPEN creates the score sheet at once, and opening an examination session only generates sheets for offerings that already have a lecturer. A load ceiling of 12 units per lecturer per semester is enforced unless the allocation is expressly saved as an overload.

## 2 Users and roles
- Allocate: `ALLOCATORS = hod, dean, academic, dregistrar, registrar, admin, super` (`api/allocation/AllocationController.java:31`).
- Read the history: `HISTORY_READERS` adds `lecturer, exams, facultyexams, facultyofficer, records` (`:44-45`).
- `/allocation/departments` is `isAuthenticated()` (`:105`): an HOD sees only their own department (`scope.actingHod()` / `scope.scopedDept`, `:108-111`).
- Scope: an HOD's offerings and lecturer lists are limited to the HOD's department (`scope.scopedDept(dept)`, `:122`, `:170`); `assertHodOwnsOffering` refuses an offering of another department with `ALLOC_DEPT` "A Head of Department allocates only courses that belong to their own department." (`:200-211`).

## 3 Navigation
- HOD: Department → Teaching Allocation `r/allocate` → `/allocate` (menus.md:42).
- Dean: Teaching Allocation `r/allocate` (menus.md:92). System Administrator: `r/allocate` (menus.md:615).
- Lecturer: Course History `t/coursehistory` → `/me/courses` (menus.md:30), My Courses & Timetable `t/teaching` → `/me/teaching` (menus.md:19) — both read `/api/v1/allocation/history?scope=me`.

## 4 Screens
**Teaching allocation** — `/allocate` (`fe/app/allocate/page.tsx`, `Allocate.tsx`). Opened by admin, dean, hod (menus); the API decides who may act.
- Scope bar: Department (SearchSelect when more than one department is offered, else a fixed label), Session, Semester (First/Second), Level (All levels, 100–600) (`Allocate.tsx:162-185`).
- Tiles: "Courses", "Unassigned" (No lead lecturer yet / All have a lead), "No second examiner" ("Blocks verification"), "Lecturers" ("In this department") (`:195-200`).
- Table "Teaching allocation": Course, Level, Units, Registered, Lecturers (lead in bold, co-lecturers as pills), Second examiner (pill "Not set" when a lead exists), Action (**Assign** in urgent style when unassigned, else **Manage**) (`:202-223`). Empty state: "No course is offered for {dept} in {session}, … A course appears here once it is offered to the programme for the session and its registration is opened." (`:222`).
- Note "Assigning the lead lecturer does four things at once" (`:225-227`).
- Modal "Assign/Manage teaching for {code}": Lead lecturer list with radio "Choose/Lead", a search box ("Search a lecturer by name or staff number…"), a checkbox "Lecturers from other departments" that fetches `/allocation/lecturers?…&all=true` (`:51-59`), columns Current load / After this (red when > 12); Field "Second examiner" ("Verifies the marks. Cannot be the lead. Set now so verification is not blocked later.") via SearchSelect; "Co-lecturers" section with chips and Remove, "Add a co-lecturer" SearchSelect + **Add co-lecturer**; footer button **Save the lead & second examiner** or, when the load would exceed 12, **Save as an overload (N units)** (`:229-296`).
- Calls: `POST /api/v1/allocation/{offering}` body `{lecturer, secondExaminer|null, overload}`; `POST /{offering}/teachers {lecturer}`; `DELETE /{offering}/teachers/{lecturer}`. A 30-second client abort shows "The portal did not answer within 30 seconds" (`:88-103`). Success note: "{code} assigned to {name}…" with the explanation "The score sheet opens in the lead lecturer's name once the examination session is open…" (`:192`).

**Course History** — `/me/courses` (lecturer) and the My Teaching screen read the history; they are documented in the staff/self dossier; the data is `AllocationController.history` (`:54-101`): every offering the person carried as lecturer or co-lecturer, with role ("Lecturer", "Co-lecturer", "Second examiner"), class size and the sheet's stage.

## 5 Workflow and statuses
There is no status column on an allocation; `catalogue.offering.lecturer_id`, `second_examiner_id`, `allocated_on` are set, and co-lecturers are rows in `catalogue.offering_teacher`. Side effect: `catalogue.allocate_offering` inserts an `assessment.score_sheet` for the offering when an exam session for that session/semester is `OPEN` and no sheet exists yet (function body, last lines).

## 6 Business rules and validations
- `catalogue.allocate_offering(p_offering, p_lecturer, p_second, p_overload_ok)` (db): "a teaching allocation is made by a person"; "an allocation names the lecturer who teaches it"; "the second examiner cannot be the lecturer" (HINT "The person who enters the marks may not be the person who verifies them."); "this assignment puts the lecturer at N units, over the approved maximum of 12" unless overload (HINT "Assign it as an overload if the department intends it; the overload is on the record and reported to the Dean."). All 23514 → HTTP 422.
- Controller: `ALLOC_ENDED` "This course has ended, so it cannot be allocated to a lecturer." (`:214-221`); `ALLOC_BUSY` on an 8 s lock timeout: "The offerings are held by another act at the moment…" (`:232-247`).
- Offerings listed only for courses of the department whose `c.semester` matches and `c.state <> 'ENDED'` (`:139-142`).
- Co-lecturer insert is skipped when the person is already the lead (`:262-269`).
- "Reported to the Dean" for overloads is a HINT only; no notice or report is generated (no `queue_notice` in this module).

## 7 Notifications
None.

## 8 Reports, exports and documents
None on this screen. (Course History has its own table; see the staff dossier.)

## 9 Configuration
The 12-unit ceiling is a constant in `catalogue.allocate_offering` and `MAX_UNITS = 12` in `Allocate.tsx:27`; not configurable.

## 10 Data
`catalogue.offering(id, course_code, session, semester, lecturer_id, second_examiner_id, allocated_on)`; `catalogue.offering_teacher(offering_id, lecturer_id, added_by)`. Both audited (catalogue tables carry `audit.record` triggers; see the catalogue dossier).

## 11 Scheduled jobs and integrations
None.

## 12 Security notes
Cross-department assignment is allowed on purpose (`all=true`). The HOD bound is enforced in code, not in the token. The overload flag is a client checkbox-free decision: the button changes label; there is no separate approval.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Assign lead + second examiner, overload guard | IMPLEMENTED | `AllocationController.java:224-250`; `catalogue.allocate_offering` | |
| Co-lecturers | IMPLEMENTED | `:256-282`; `Allocate.tsx:275-291` | |
| Cross-department lecturer pool | IMPLEMENTED | `:164-197`; `Allocate.tsx:51-59` | |
| Sheet created on allocation when session open | IMPLEMENTED | `allocate_offering` last INSERT | |
| Overload "reported to the Dean" | NOT IMPLEMENTED | only a HINT string | no report/notice exists |
| Allocation history (me / department) | IMPLEMENTED | `:54-101` | UI at `/me/courses` |

## 14 Common problems
- "over the approved maximum of 12": press **Save as an overload** or choose another lecturer.
- "A Head of Department allocates only courses that belong to their own department": the offering is another department's; that department allocates.
- Sheet does not appear for a lecturer after allocation: no examination session is OPEN for that session/semester; the Academic Office/Records must open one (see B).
- "No lecturer is on record for this department": the Registry has not granted a `lecturer` office scoped to the department; tick "Lecturers from other departments".

## 15 Glossary
Lead lecturer (owns and submits the sheet); Second examiner (verifier, cannot be the lead); Co-lecturer (`offering_teacher`, enters marks on the shared sheet); Overload (allocation past 12 units, saved deliberately).

---

# B. Examination sessions, score sheets and the approval chain  (API: results; schema: assessment; pages: fe/app/examinations/sessions, results/sheets, results/sheets/[id], results/sheets/history, results/desk, results/approvals, results/chain, results/pipeline)

## 1 Purpose
An examination session (MAIN, RESIT or SPECIAL) for a session/semester fixes the dates and the score-sheets-due date; opening it generates one score sheet per allocated offering. The lecturer enters CA and examination marks (or an outcome) for every candidate on the approved register, or uploads the same template, then submits and attests. The sheet then passes eight desks — verification (exams), departmental board (hod), faculty scrutiny (facultyexams), faculty compilation (facultyofficer), faculty board (dean), Exams & Records (records), Senate (registrar/dregistrar) — and is PUBLISHED only on a cited Senate minute. Total, grade and points are never typed; the register computes them from the grading scheme in force, with a one-mark grace at the pass boundary. Marks are versioned, never overwritten.

## 2 Users and roles
Guard constants in `api/results/ResultsController.java`:
- `READERS` (`:27-30`): academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, lecturer, ict, admin, super — list/read sheets, rolls, exam sessions, monitor, mine, broadsheet, senate.
- `DESKS` (`:31-33`): lecturer, exams, hod, facultyexams, facultyofficer, dean, records, registrar, dregistrar, academic — advance, return, remind.
- `ENTRY` (`:34`): lecturer, exams, academic — write scores.
- `EXAMS` (`:35`): records, academic, registrar, dregistrar — create/edit/open exam sessions.
- Minute: registrar, dregistrar only (`:256`).
- Which office may advance which stage is `Sheets.DESK` (`api/results/Sheets.java:17-26`): ENTRY→lecturer, VERIFICATION→exams, DEPT_BOARD→hod, FACULTY_SCRUTINY→facultyexams, FACULTY_COMPILATION→facultyofficer, FACULTY_BOARD→dean, RECORDS→records, SENATE→registrar/dregistrar. **This map only drives `mayAct` on the UI** (`ResultsService.listed`, `:296`); the database `assessment.advance` does not check the office — any `DESKS` office can advance any stage through the API (see 12).
- Scope: `own(id)` refuses a sheet to a lecturer who is not lead, second examiner or co-lecturer: "{course} is not allocated to you in {session}; a lecturer reaches only the score sheets of their own courses." (`ResultsService.java:278-288`, `ResultsRepository.teaches` `:285-292`). Listing is bound by `OfficeScope.bound` (department offices to their department, faculty offices to their faculty, `api/shared/OfficeScope.java:147-172`); an HOD's list is forced to their department (`ResultsService.java:322-326`); acting as lecturer the list is only their own sheets (`:320`).

## 3 Navigation (menus.md)
- Lecturer: Score Sheets `t/scores` → `/results/sheets` (13-20); Score Sheet History `t/sheethistory` → `/results/sheets/history` (29).
- HOD: Result Desk `t/resultdesk` → `/results/desk`; Departmental Approvals `t/approvals` → `/results/approvals`; Result Pipeline `t/pipeline`; Approval Chain `t/chain`; Score Sheets / Score Entry / Upload Results (bulk) all → `/results/sheets` (45-53).
- Dean: Result Desk, Faculty Board (`t/approvals`), Pipeline, Broadsheet, Chain, Score Entry, Upload Results (bulk), My Score Sheets (92-101).
- Exams Officer: CBT Sessions `t/exams` → `/examinations/sessions`; Score Sheets; Approval Chain; Verification Queue (`t/approvals`) (200-205).
- Academic Office: Examination Sessions `t/examsession` → `/examinations/sessions`; Results to Senate (`t/approvals`); Approval Chain (226-229).
- Faculty Exams Officer: Scrutiny Desk (`t/resultdesk`), Pipeline, Broadsheet, Chain, Score Sheets, Examinations `t/exams` (338-345). Faculty Officer: Result Desk, Pipeline, Broadsheet, Chain, Score Sheets (354-360).
- Exams & Records: Examination Sessions, Validation Desk (`t/resultdesk`), Pipeline, Broadsheets, Senate Schedule, Publication, Chain (379-388).
- Deputy Registrar (AA): Senate Schedule, Pipeline, Chain, Broadsheets (410-414). DVC: Pipeline, Senate Schedule, Broadsheets (445-447). Registrar and VC: Senate Business (`t/approvals`) (508, 664). Super: Pipeline (468). Admin: Approval Chain (616).

## 4 Screens
**Examination sessions** — `/examinations/sessions` (`fe/app/examinations/sessions/ExamSessions.tsx`). Opened by exams, facultyexams (`t/exams`) and academic, records (`t/examsession`); only `EXAMS` offices can create/edit/open (others get 403 toasts).
- Tiles: "Open sessions", "Courses examined", "Candidates", "Sheets due" (`:95-100`).
- Panel "Create an examination session": Academic session (select), Semester (First/Second/Third), Type (Main examination / Re-sit / Special), Examinations begin, Examinations end, Score sheets due (dates, all required before the buttons enable); buttons **Open the session** (create then open) and **Save as a draft** (`:102-120`). After opening: "N score sheets generated; M courses have no lecturer and generated none." (`:76`).
- Panel "Examination sessions": Session, Semester, Type, Examinations, Sheets due, Sheets, Outstanding, State (Open/Draft/Closed pill), actions **Edit** (not when Closed) and **Open** (Draft only) (`:122-140`).
- Modal "Edit the examination session": session/semester/type disabled once sheets exist ("Only the dates can change"), else all editable; **Save the dates** (`:142-162`).
- Panel "Submission monitor": Faculty, Sheets expected, Submitted, Verified, Past the Board, Outstanding, Progress bar (`:164-175`); Panel "The N sheets holding the Faculty of X": Course, Department, Lecturer, Candidates, Days late, Escalated to ("Head of Department" under 6 days late, else "Dean" — `ResultsService.java:472`), buttons **Remind** / escalate → `POST /sheets/{id}/remind` (`:177-190`).

**Score Sheets (list)** — `/results/sheets` (`SheetsList.tsx`). `all = office !== "lecturer"` (`page.tsx:16`): a lecturer sees their own sheets (`/results/mine`), every other office every sheet of the session (`/results/mine?all=true`). Filters Session, Semester. Table: Course, Candidates, Entered (red when short; "N scripts held"), Stage (pill from `stageOf`, "N days overdue", "Returned once/N times"), Second examiner ("Not yet set"), action button (Continue/View) (`:44-59`). Empty: "No sheet is assigned to you in this session. A sheet appears here when the department allocates you a course and the examination session is opened." Notes "This list is generated from the rolls, not typed beside them" and "A sheet that has left this desk is readable, not editable" (`:23-25, 62-64`).

**Score Sheet History** — `/results/sheets/history` (lecturer; `SheetHistory.tsx`): tiles "Sheets on record", "Published", "In approval", "Still with you"; filters Session, Semester, Standing (Not started / In progress / Submitted — in approval / Published, `fe/lib/lecturer.tsx:15-20`); table with Excel/PDF links to the marked sheet and Open/View.

**Score entry (one sheet)** — `/results/sheets/{id}` (`fe/app/results/sheets/[id]/page.tsx`, `ScoreEntry.tsx`, `HeldScripts.tsx`). Loads `/sheets/{id}`, `/sheets/{id}/roll`, `/sheets/{id}/held`. `own` = acting office lecturer/exams/academic (`page.tsx:34`).
- Header pill: "Complete — not yet submitted" / "Draft — N candidates without a mark" / "Draft — unsaved changes" / stage name (`ScoreEntry.tsx:255`).
- Buttons: **Download the template** (client-built xlsx with the roll, columns "S/N, Matriculation number, Name, Programme, Level, CA (0-{caMax}), Exam (0-{examMax}), Outcome (blank = GRADED, or ABSENT / WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED)" and data validations, `:137-151`); **Marked sheet · Excel / · PDF** once anything is entered (`/results/sheets/{id}/marked?format=`); **Upload a completed sheet** (.xlsx/.csv), **Save the draft**, **Submit and attest** (`:258-266`).
- Roll table: S/N, Matriculation number, Name, Programme, Lv, "CA — {caMax}", "Exam — {examMax}", Total (with a "+1" superscript when the grace mark applied), Grade (pill "A5"…), Points, Outcome (select Graded/Absent/Withheld/Incomplete/Malpractice/Exempted), "Reason, if amended" (input only for a row already on the record after a return) (`:309-350`). Enter/↓/↑ move down/up a column. Over-range cells turn red with "More than N".
- Validation before save (client): both CA and exam or neither; CA ≤ caMax, exam ≤ examMax; an amended row needs a reason; a saved mark is locked unless the sheet's latest decision is a RETURN (`:63-78`). Notes: "N marks are on the record and locked", "Returned to you — every mark is open for amendment", "A changed mark carries its reason", "N rows are outside the marks — nothing saves until they are within" (`:279-290`).
- Upload: header row located by a cell matching /matric/; lines refused (unknown outcome, out-of-range, locked row changed) are listed and nothing is written: "{file} was not accepted — N lines refused, nothing written" with **Download Validation Report** (CSV "Line, Refused because") (`:154-215`, `:128-135`). Candidates not on the roll are set aside and offered as held scripts: "N candidates on the upload are not on this roll" → **Hold these N scripts** (bulk hold) or **Leave them** (`:218-235`, `:271-278`).
- Tiles: Candidates, From other programmes, "CA out of", Second examiner ("Not yet set") (`:292-297`).
- Modal "Submit and attest" → **I attest these marks** → `POST /sheets/{id}/advance` (`:370-375`). Notes when not at ENTRY: "Published under Senate minute X" or "This sheet has left the lecturer: {stage}" with **Open the approval chain** (`:244-247`); when returned: "Returned to you once/N times" quoting each return's office and comment (`:248-252`).
- Panel "What happens when you attest" (steps) and the note "You type two numbers; the system does the rest" (`:356-366`).

**Result Desk** — `/results/desk` (`Desk.tsx`). For each desk office a fixed description (title, unit, "arrives from", "leaves for", "may not", five "can" bullets, `:19-29`); offices outside the chain see "This office holds no stage of the result chain". Tiles "On this desk now", "Not yet arrived", "Sent on", "Published"; panels "What this office may do", "On this desk" (Open → chain; "You took the previous stage" pill), "Not yet arrived" (Stopped at / Waiting on / days late), "Send on to {next}" with **Forward N sets to {next}** (advances each sheet where `mayAct && !blockedForYou && failRate ≤ 50`, `:50-71`) or, at SENATE, **Record the Senate minute** → `/results/senate` (`:114-125`).

**Approvals queue** — `/results/approvals` (`Approvals.tsx`): scope bar with course; tiles Expected sheets / Senate approved / In workflow / Not submitted; table Course (Re-sit/Special pill), Department, Students, Fail rate (pill when > 50 %), Stage ("Not submitted" + lecturer + "N days overdue"; else stage text + "With {who}" or "You approved the previous stage — another holder of the next desk must approve this one"; "Fail rate above half the candidates — review before approving"), Action: at ENTRY **Remind**/escalate (202 → note "Nothing was sent" with the API's text, `:43-45`); PUBLISHED **Chain**; SENATE **Record Senate minute**/Review; blocked "Not available to you"; high fail rate **Return**/Review; else **Return**/**Approve** (`:74-117`). Modal "Return the sheet to the lecturer" → field "Why it is returned" → **Return it** (`:120-127`).

**Approval chain** — `/results/chain?sheet=` (`Chain.tsx`; without `sheet` the `PickSheet` list). Tiles Course / Students / Fail rate / "Stage N of 6"; notes: published ("Senate has approved this result set and it is published… Minute X") with buttons **Raise an amendment** and **View as a student** that have **no handler** (`:91`, placeholder); "This stage is yours: {act}" with **{Approve verb}** (at SENATE opens the minute modal) and **Return to the lecturer** (`:94-100`); "You performed the previous stage, so this one is not open to you" (`:101-104`); the ladder of decisions ("Scores entered", "Submitted for verification", stage names, "Returned by {office}" with comment) (`:60-66`); panel "What the rules require" (BR-004/BR-006 gates; "engine version … GpaCalculator 2.1") (`:127-138`); table "Marks on this sheet" (Student, CA, Exam, Total, Grade, Point, "Amended — version N") (`:140-154`); modal for return reason or "Senate minute" (placeholder "SEN/2026/…") → **Approve and publish** (`:162-174`).

**Result pipeline** — `/results/pipeline?at=n` (`Pipeline.tsx`): the nine stages `RP_STAGES` with "What happens here" / "What it cannot pass without" (`:12-22`), counts per stage, tiles, table "Where every set is now", and the note "A set is failing more than half its candidates" → **Open the queue** (`:86-90`).

## 5 Workflow and statuses
- `assessment.exam_session.state`: `DRAFT → OPEN` (`assessment.open_exam_session`, `V197:145`); `CLOSED` exists in the CHECK but **nothing in the code sets it** (no UPDATE to CLOSED found in api or db). `kind` MAIN/RESIT/SPECIAL; UNIQUE (session, semester, kind).
- Opening: one sheet per offering of the session/semester with a lecturer; for RESIT/SPECIAL only where the MAIN sheet of that offering is PUBLISHED; returns `(sheets_made, offerings_without_lecturer)`. "the examination session is already open/closed" if not DRAFT.
- `assessment.score_sheet.stage` (CHECK `ck_sheet_stage`): `ENTRY → VERIFICATION → DEPT_BOARD → FACULTY_SCRUTINY → FACULTY_COMPILATION → FACULTY_BOARD → RECORDS → SENATE → PUBLISHED` (`assessment.stage_after`). Each move writes an `assessment.decision` row (kind SUBMIT from ENTRY, ADVANCE otherwise, RETURN back to ENTRY; a RETURN must carry a comment, `ck_decision_return_says_why`). `returned_times` increments on each return. PUBLISHED requires `published_at` and `senate_minute` (`ck_sheet_published`); publishing sets `engine_version = 'GpaCalculator 2.1'`.
- Return: from any stage except ENTRY and PUBLISHED, back to ENTRY ("a sheet at entry/published is not returned", `assessment.return_sheet`, `V013:748`). The sheet re-enters at VERIFICATION when resubmitted (it simply advances from ENTRY again).
- Score outcomes (`ck_score_outcome`): GRADED, ABSENT, WITHHELD, INCOMPLETE, MALPRACTICE, EXEMPTED. GRADED needs ca and exam (or an imported total). Versions: `(sheet_id, student_id, version)`; version > 1 needs a reason (`ck_score_amended`).
- Student-facing spine (`Sheets.spine`): 1 ENTRY, 2 VERIFICATION, 3 DEPT_BOARD, 4 the three faculty stages, 5 RECORDS/SENATE, 6 PUBLISHED. Labels the student and desks see: `STAGE_LABEL` (`fe/lib/results.ts:128-138`), e.g. VERIFICATION = "Submitted for verification / Second examiner", SENATE = "Validated / Senate, on the Registrar's minute".
- Publication in bulk: `POST /results/senate/minute {session, sem, fac?, minute}` advances every sheet at SENATE in scope, each in its own transaction; refusals (e.g. BR-006) are returned by id with the reason (`ResultsService.recordMinute`, `:657-675`).

## 6 Business rules and validations
- `assessment.advance` (`V197:89`): a sheet leaving ENTRY must have an outcome for every candidate of `assessment.sheet_candidates` — "N registered candidate(s) on this sheet have no mark and no outcome" (HINT "…A blank is not an outcome."); BR-006 "you approved the previous stage of this sheet; another desk must approve this one" when the last SUBMIT/ADVANCE actor is the same person; "a result reaches a student on the Senate minute that approved it, and none was cited" when moving to PUBLISHED without a minute; "this sheet is published; there is no stage after publication".
- `assessment.sheet_candidates` (`V197:84`): MAIN = every APPROVED entry on an APPROVED/LOCKED registration; RESIT = candidates ABSENT or GRADED with 0 points on the published MAIN sheet; SPECIAL = ABSENT on the published MAIN.
- Scores (`ResultsService.scores`, `:355-395`): `RES_SHEET_NOT_AT_ENTRY` "The sheet is at {stage}; a mark changes by amendment with a reason, not by entry." (remedy "Return the sheet to the lecturer…"); `RES_MARK_OUTSIDE_SPLIT` "{code} assesses out of {caMax} and examines out of {examMax}; a mark outside that was entered."; `RES_MARK_ON_RECORD` "A saved mark is on the record; the lecturer does not change it on their own." unless the latest decision is a RETURN (`repo.returnedToEntry`, `:149-154`); `RES_AMENDMENT_SAYS_WHY` "An amended mark carries its reason."; unchanged rows are skipped.
- Trigger `assessment.score_within_split` (`V239:61`): "continuous assessment in {code} is out of {caMax}, not {n}" / "the examination in {code} is out of {examMax}, not {n}" with the HINT "This course assesses X and examines Y…". The split is `catalogue.course.ca_max` (default 40).
- Grace mark (`assessment.grace_total`, `V238:31`): a raw total exactly one below the lowest passing band's low (39 under the seeded scheme) becomes that low (40); applied in `latest_scores` for non-imported GRADED marks.
- Return (`giveBack`): `RES_RETURN_SAYS_WHY` "A sheet is returned with the reason on the record."
- Exam session dates: `EXAM_DATES` "The examinations end before they begin." / "The score sheets are due before the examinations end." (`:51-58`); `EXAM_CLOSED` "A closed examination session cannot be changed."; `EXAM_HAS_SHEETS` "This session already has N score sheet(s), so its academic session, semester and type are fixed — only the dates can change."; `EXAM_DUPLICATE` "An examination session already exists for that academic session, semester and type." (`:431-455`).
- Fail rate > 50 % is a UI caution only (Desk excludes such sheets from bulk forwarding; Approvals hides the Approve button behind Review); the API does not block it.

## 7 Notifications
| event | trigger | recipient | channel | subject |
|---|---|---|---|---|
| Reminder / escalation of an overdue sheet | `ResultsController.remind` `:181-188` | — | none | returns 202 `"The notification module is not on the portal yet; nothing was sent."` |
| Publication of a sheet | — | — | none | **no notice is queued on PUBLISHED** (no `queue_notice` in `results/*.java` except held scripts; none in db for score_sheet) |
| Result changed after a document was issued | trigger `trg_score_flags_documents` → `credentials.score_changed` | (documents office, via flags) | in-data flag | flags issued transcripts/statements "A result of the student changed after issue" |

## 8 Reports, exports and documents
- Score-sheet template: client-built xlsx (`ScoreEntry.tsx:137-151`) and server route `/results/sheets/{id}/template?format=xlsx|csv` (`fe/app/results/sheets/[id]/template/route.ts`): letterhead (SCHOOL), meta Department/Programme/Course/Lecturer/Session/Candidates, columns as above with CA/Exam data validation.
- Marked sheet: `/results/sheets/{id}/marked?format=xlsx|pdf` (`marked/route.ts`; `fe/lib/marked-sheet.ts`): headers "S/N, Matriculation number, Name, Programme, Level, CA, Exam, Total, Grade, Points, Outcome", then a "Performance summary" (grade counts and shares, candidates, graded, passed/failed, other outcomes, not yet entered, mean/highest/lowest). PDF is landscape A4 with crest, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", footer "Generated … from the register. … The record is the register, not this print." No QR.
- Validation report CSV of a refused upload (`ScoreEntry.tsx:128-135`).
- The Examination sessions screen has no export.

## 9 Configuration
`catalogue.course.ca_max` (default 40) sets the CA/exam split per course (catalogue dossier). Exam sessions are the only other configuration. Stage names/desks are code constants (`Sheets.DESK`, `fe/lib/results.ts`).

## 10 Data
- `assessment.exam_session(id, session, semester, kind, exams_from, exams_to, sheets_due, state, opened_at)`; CHECK `exams_to >= exams_from AND sheets_due >= exams_to`.
- `assessment.score_sheet(id, offering_id, exam_session_id, stage, due_on, submitted_at, returned_times, senate_minute, published_at, engine_version)`; UNIQUE (offering_id, exam_session_id). Legacy sheets have `exam_session_id` NULL and minute "Migrated from the legacy portal" (`assessment.import_legacy_semester`).
- `assessment.score(sheet_id, student_id, version, ca, exam, outcome, reason, entered_at, total, imported)` — append-only by convention (new version per change); `total` only for imported rows (`ck_score_total_imported`).
- `assessment.decision(id, sheet_id, from_stage, to_stage, kind, actor_id, actor_office, comment, decided_at)` — write-once trail.
- `assessment.exam_timetable(offering_id PK, held_on, starts_at, ends_at, venue)`.
- All attached to the audit spine (`trg_audit_assessment_*`).

## 11 Scheduled jobs and integrations
None for this module (see C for held-script lapsing, which is on-read).

## 12 Security notes
- The stage→office map is not enforced in SQL; `assessment.advance` only enforces "not the same person twice in a row" and completeness. Any `DESKS` office (including a lecturer on their own sheet, or the Academic Office) can call `/sheets/{id}/advance` at any stage. The UI hides the buttons (`mayAct`), the API does not refuse.
- Minute recording is limited to registrar/dregistrar in the controller (`:256`), but a `DESKS` office can also publish a single sheet by passing `minute` to `/sheets/{id}/advance` at SENATE (the Chain screen does exactly this for whoever `mayAct`).
- Lecturer sheet ownership is checked on every read/write (`own`).
- `/api/v1/results/legacy/*` (migration desk) is in this controller with the `MIGRATE` guard (`:45-47`); it is documented in the records/migration dossier.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Exam session create/edit/open, sheet generation | IMPLEMENTED | `ResultsService.java:420-462`; `open_exam_session` | CLOSED state never set |
| Submission monitor with escalation names | IMPLEMENTED (read) | `:464-476`; `ExamSessions.tsx:164-190` | |
| Remind / escalate a late lecturer | PLACEHOLDER | `ResultsController.java:181-188` | 202 "nothing was sent" |
| Score entry, versioning, lock-until-return | IMPLEMENTED | `ResultsService.java:355-395`; `ScoreEntry.tsx` | |
| Bulk upload with whole-file validation | IMPLEMENTED (client-side parse, server-side write) | `ScoreEntry.tsx:154-215` | |
| Template and marked sheet exports | IMPLEMENTED | `template/route.ts`, `marked/route.ts` | |
| Approval chain 9 stages, BR-006, minute on publish | IMPLEMENTED | `assessment.advance`; `Chain.tsx` | office-per-stage not enforced server-side |
| Bulk forward from a desk | IMPLEMENTED | `Desk.tsx:50-71` | sequential client calls |
| "Raise an amendment" / "View as a student" on a published sheet | PLACEHOLDER | `Chain.tsx:91` (buttons with no onClick) | no amendment path exists for a PUBLISHED sheet (return refuses at PUBLISHED; scores refuse when not at ENTRY) |
| Publication notifies students | NOT IMPLEMENTED | no queue_notice on publish | |
| Re-sit / special sittings | IMPLEMENTED | `sheet_candidates`, `course_final` | a passed re-sit is recorded at the pass mark (40, "E") |
| Second examiner acting at VERIFICATION | PARTIALLY IMPLEMENTED | `Sheets.DESK` maps VERIFICATION to the `exams` office; the second examiner set at allocation only gains read access (`teaches`) | UI text says "It goes to the second examiner" |

## 14 Common problems
- "N registered candidate(s) on this sheet have no mark and no outcome": every roll row needs a mark or an outcome (Absent etc.) before Submit.
- "A saved mark is on the record; the lecturer does not change it on their own": submit and ask the Examination Officer/HOD to Return with a reason; then amend with a reason per row.
- "you approved the previous stage of this sheet; another desk must approve this one": another holder of the office must act (also applies to the Registrar's minute).
- "a result reaches a student on the Senate minute that approved it, and none was cited": enter the minute in the modal / Senate screen.
- Sheet missing after opening the session: the offering had no lecturer at opening; allocate it (a sheet is then created because the session is OPEN).
- "{code} is not allocated to you in {session}": a lecturer opened another lecturer's sheet id.
- Upload "was not accepted — N lines refused": download the validation report; fix the lines; nothing was written.

## 15 Glossary
Examination session (the container: MAIN/RESIT/SPECIAL, dates, sheets due); Score sheet (one offering × one sitting); Roll (approved registrations for the offering); Attest (SUBMIT from ENTRY); Return (RETURN decision back to ENTRY with a reason); Senate minute (the citation that publishes); Engine version ("GpaCalculator 2.1", stamped on publication); Grace mark (39→40); Outcome (GRADED/ABSENT/WITHHELD/INCOMPLETE/MALPRACTICE/EXEMPTED); BR-006 (no two consecutive stages by one person).

---

# C. Held scripts  (API: results/HeldScriptsController; table assessment.held_script; UI: the held-scripts panel on the score sheet, /finance/held-scripts)

## 1 Purpose
A mark from a candidate who sat the paper without being on the roll is held against the sheet by matriculation number, not graded and not on the broadsheet. When the candidate's registration for that offering is approved, a trigger releases the held mark into the sheet as a new score version; when the semester's late-registration date passes, it lapses. The student is told by email and SMS the moment a script is held. The Bursary reads the students a held script is waiting on with what they owe.

## 2 Users and roles
- Hold/withdraw: `ENTRY = lecturer, exams, academic` (`HeldScriptsController.java:141`), within `own(id)`? — **No**: this controller does not call `own`; any lecturer can hold on any sheet id (see 12).
- Read a sheet's held scripts: `READERS` = the results readers plus bursar (`:137-140`). Owing list: bursar, academic, registrar, dregistrar, exams, hod, dean, records, vc, dvc, admin, super (`:142-144`).

## 3 Navigation
Panel "Scripts from candidates not on the roll" under every score sheet (`/results/sheets/{id}`); Bursar: Held Scripts `t/heldscripts` → `/finance/held-scripts` (menus.md:279).

## 4 Screens
- Panel (`HeldScripts.tsx`): explanatory text with the closing date ("Late registration for this semester closes on {date}; a script not released by then lapses and never grades." or "The Registry has not set a late-registration closing date for this semester on the calendar; until it does, held scripts do not lapse.", `:126`); buttons **Download the held-scripts template** (xlsx: "S/N, Matriculation number, CA (0-x), Exam (0-y), Outcome (…), Note", 30 blank lines, `:58-70`) and **Upload held scripts** (bulk, all-or-nothing, `:73-111`); form fields Matriculation number (placeholder "BSU/SC/CMP/23/70049"), Outcome, "CA — x", "Exam — y", "Note (optional)" (placeholder "e.g. script no. 47, sat in LT 2"), button **Hold the script** (`:141-157`); after closing: note "Late registration has closed for this semester" (`:139`). Table: Matriculation number, Name, Programme, CA, Exam, Outcome, Standing (pills "Held — waiting on registration", "Released into the sheet", "Lapsed — not registered in time", "Withdrawn"), Entered (by/when), **Withdraw** (confirm dialog) (`:160-171`).
- `/finance/held-scripts` (`HeldOwing.tsx`): tiles, note "What this list is", table "Students a held script is waiting on": Matriculation number, Name, Programme, Session, Courses held, Closes, Due, Paid, Balance (`:32-34`) — read from `assessment.held_scripts_owing()` joined to `finance.position`.

## 5 Workflow and statuses
`assessment.held_script.state`: `HELD → RELEASED` (trigger on `registration.entry` status APPROVED or `registration.course_registration` becoming APPROVED/LOCKED → `assessment.release_held_scripts`), `HELD → LAPSED` (`assessment.lapse_held_scripts()`, run at every read of `/held` and `/held/owing`; also inside release when the date has passed), `HELD → WITHDRAWN` (`assessment.withdraw_held_script`). Release inserts `assessment.score` version n+1 with reason "Released from a held script: the candidate sat the paper before registering, and the registration is now approved" — **even when the sheet is past ENTRY** (no stage check in `release_held_scripts`).

## 6 Business rules
`assessment.hold_script` (`V240:69`): "a script is held by a person"; "no student on the register is numbered X"; "X is on the roll of {code}; enter the mark on the sheet"; "late registration for this semester closed on {date}; a script can no longer be held for {code}" (closing = `policy.semester.late_registration_closes`); GRADED needs both marks; CA/exam split checks; "a script is already held for X on {code}" (HINT "Withdraw the held script first…"). Bulk: "the upload has no lines"; "N of M line(s) refused — nothing held" with up to 12 line problems in the HINT. Withdraw: "only a script still held is withdrawn".

## 7 Notifications
| event | trigger | recipient | channel | subject |
|---|---|---|---|---|
| Script held (single or bulk) | `HeldScriptsController.tellStudents` `:160-201` | the student (`people.student_reach`) | EMAIL and SMS (`about_kind 'held_script'`) | "Your {code} script is held until you register" |

## 8 Reports, exports
Held-scripts template (xlsx). The Bursary list has no export button in `HeldOwing.tsx` (grep shows no brandedXlsx/brandedPrint).

## 9 Configuration
`policy.semester.late_registration_closes` (Registry calendar) governs lapsing.

## 10 Data
`assessment.held_script(id, sheet_id, student_id, ca, exam, outcome, note, entered_by, entered_at, state, released_at, lapsed_at, withdrawn_at)`; UNIQUE per sheet/student (implied by the unique_violation handler). Audited.

## 11 Scheduled jobs
None; lapsing is lazy (on read).

## 12 Security notes
`hold`, `holdBulk`, `withdraw` do not check that the acting lecturer teaches the sheet (no `own`/`teaches` call in this controller). Release can add a score to a sheet already at a later stage or PUBLISHED, bypassing the approval chain for that mark.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Hold / bulk hold / withdraw / list | IMPLEMENTED | controller `:204-250` | |
| Auto-release on approval, lapse on date | IMPLEMENTED | triggers `trg_entry_releases_held`, `trg_registration_releases_held`; `lapse_held_scripts` | lazy lapsing |
| Student notice | IMPLEMENTED | `:160-201` | |
| Bursary owing list | IMPLEMENTED | `:253-259`; `HeldOwing.tsx` | no export |
| Ownership check for holding | NOT IMPLEMENTED | no `own` in controller | |

## 14 Common problems
"X is on the roll of {code}; enter the mark on the sheet" — the candidate is registered; use the roll. "late registration … closed on …" — the Registry can move the date on the calendar. A held mark that never releases: the registration was never approved before the closing date; the state is LAPSED.

## 15 Glossary
Held script; Release; Lapse; Late-registration closing date.

---

# D. Result queries and the examination slot  (API: results/QueriesController, studentportal MeController; tables assessment.result_query, assessment.exam_timetable; pages /results/queries, /student/query)

## 1 Purpose
For seven days after a sheet is published a student may query one mark in one course (the examination mark, the CA mark, or an absence recorded for a paper they sat). The query is routed to the department that owns the course and answered on the record as UPHELD, CORRECTED or CLOSED; the student is told by email and SMS and reads the answer on their screen. The same controller lets the Examinations Office set an offering's examination slot (day, time, venue), which the student's docket carries.

## 2 Users and roles
- Read/answer queries: `DEPARTMENT = hod, lecturer, exams, dean, records, academic, registrar, super` (`QueriesController.java:39`); an HOD sees their own department unless they pick one; `scope.deptWithin` binds department offices (`:62`).
- Set exam slot: `EXAMS = exams, facultyexams, records, academic, registrar, super` (`:40`).
- Raise/read own: student (`MeController` `/api/v1/me/queries`).

## 3 Navigation
HOD: Result Queries `t/queries` → `/results/queries` (menus.md:47); Exams Officer: Result Queries (205). Student: Result Query `s/query` → `/student/query` (690). The exam slot is set on the class-list desk (`/registration/class-list`, `OfferingDesk.tsx:102`, PUT `/results/offerings/{id}/exam-slot`).

## 4 Screens
- **Result queries desk** (`Queries.tsx`): tiles Open / Shown / Corrected / Upheld; filter buttons Open / Answered / All (`?state=`); note "A query is against one mark, and the answer says what was checked" (Upheld / Corrected / Closed explained); table Reference (QRY-YYYY-NNNNN), Student, Course, "Mark on the sheet" ("CA a + exam b = t (G)"), "What they said" (part: "The examination mark" / "The continuous assessment mark" / "Recorded absent, sat the paper"), State pill, **Answer** (enabled for `may` offices). Modal "Answer {ref}": Finding select (Upheld — the mark stands / Corrected — the mark is amended through the chain / Closed — not a query), Answer textarea ("What was checked and what was found. The student reads this."), note for CORRECTED "Correcting the mark is a separate act… Amend it on the sheet from the approval chain and return the set" → **Answer on the record**.
- **Student: Result Query** (`fe/app/student/Screens5.tsx:25-78`): note "The query window is open until {date}" or "The query window is not open"; tiles Window / Your queries / Answered / Marks corrected; panel "Raise a query": Course (select of queryable sheets with the mark), Which mark (EXAM / CA / ABSENT), "What you say is wrong" textarea → **Submit the query** (`POST /api/v1/me/queries {sheetId, part, said}`); panel "Your queries" (Reference, Course, What you said, Routed to, State "With the department"/Upheld/Corrected/Closed, Answer); note "A corrected mark does not quietly change your result".

## 5 Workflow and statuses
`assessment.result_query.state`: `RAISED → UPHELD | CORRECTED | CLOSED` (one answer; `ck_query_answered` requires answer, answered_at, answered_by). `ref` format `QRY-YYYY-NNNNN` from `platform.next_number('RESULT_QUERY','UNIVERSITY',year)`. `part` EXAM/CA/ABSENT. Window: `assessment.query_window_open` = PUBLISHED and `published_at + 7 days > now()`.
**CORRECTED has no mechanical effect**: nothing reopens the published sheet; `return_sheet` refuses PUBLISHED and `scores` refuses a sheet not at ENTRY. The UI text promising "the set goes back through the department, the faculty and Senate for an amendment minute" describes a path that does not exist in code (see B.13).

## 6 Business rules
`assessment.raise_query` (`V027:56`): "no mark of yours is on this sheet"; "the query window for this course is not open" (HINT says "five working days" although the window is seven calendar days); "a query on this mark is already open" (23505 → 409). Service: `RES_QUERY_PART` "A query names the mark it is about."; `RES_QUERY_SAID` "Say what you say is wrong." (`StudentPortalService.java:349-362`). `assessment.answer_query` (`V027:79`): "this query was answered on {date}"; "a query is answered in words". Controller: `RES_QUERY_STATE` "'x' is not an answer to a query." Exam slot: bean validation only (heldOn, startsAt, endsAt, venue ≤ 200), upsert on offering.

## 7 Notifications
| event | trigger | recipient | channel | subject |
|---|---|---|---|---|
| Query answered | `assessment.answer_query` | student (`people.student_reach`) | EMAIL | "Your result query {ref} is answered" (body: "the mark stands." / "the mark is being corrected through the approval chain." / "closed.") |
| Query answered | same | student | SMS | "Your result query is answered" — "MOAUM: query {ref} answered — {state}. Sign in to read it." |
| Query raised | — | — | none | the department is not notified |

## 8 Reports, exports
None.

## 9 Configuration
Window length (7 days) and numbering series are code/SQL constants.

## 10 Data
`assessment.result_query(id, ref, student_id, sheet_id, part, said, routed_dept, raised_at, state, answer, answered_at, answered_by)`; audited. `assessment.exam_timetable` (one slot per offering).

## 12 Security notes
A student can only query a sheet carrying a score of theirs. The desk's department filter is bound in code.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Raise, list, answer, notify | IMPLEMENTED | `V027`, `QueriesController.java:56-91`, `Screens5.tsx:25-78` | |
| Correction of a published mark after CORRECTED | NOT IMPLEMENTED | no reopen path; `return_sheet` refuses PUBLISHED | UI text promises it |
| Department told of a new query | NOT IMPLEMENTED | no notice on raise | dashboard count `open_queries` on `/results/mine` only |
| Exam slot per offering | IMPLEMENTED | `QueriesController.java:94-103`; `OfferingDesk.tsx:102` | |

## 14 Common problems
"the query window for this course is not open": more than 7 days since publication, or not published. "a query on this mark is already open": wait for the answer. Answer button disabled: office not in the `may` list.

## 15 Glossary
Query window (7 days from `published_at`); Part (EXAM/CA/ABSENT); Upheld/Corrected/Closed.

---

# E. Grading policy, GPA/CGPA, class of degree, probation and withdrawal  (schema: policy, assessment functions; no dedicated screen)

## 1 Purpose
The grading scheme, the classification table and the level unit limits are versioned policy rows effective by date range. Every grade, point, GPA, CGPA, class of standing and probation/withdrawal pronouncement in the portal is computed from published sheets through a small set of SQL functions; nothing is typed.

## 2 Users and roles
No screen edits these tables (no controller writes `policy.grade_band`/`classification_band`/`version`); they are seeded by migrations. Readers: every results screen and the student portal.

## 9 Configuration (seeded rows, from the database)
- `policy.version`: grading UNIVERSITY `[2015-10-01,)` instrument `SEN/2015/44` decided_by registrar; classification UNIVERSITY `[2015-10-01,)` `SEN/2015/44`; clearance (demo) `[2026-09-25,)` `BUR/DEMO/1`.
- `policy.grade_band`: A 70–100 = 5.00; B 60–69 = 4.00; C 50–59 = 3.00; D 45–49 = 2.00; E 40–44 = 1.00; F 0–39 = 0.00 (CHECKs: 0 ≤ low ≤ high ≤ 100, 0 ≤ points ≤ 5).
- `policy.classification_band`: First Class Honours 4.50–5.00; Second Class Honours (Upper) 3.50–4.49; Second Class Honours (Lower) 2.40–3.49; Third Class Honours 1.50–2.39; Pass 1.00–1.49. **No band below 1.00**, so `policy.class_of` returns NULL (shown "—") for a CGPA under 1.0.
- `policy.level_limit` (level, applies_to, min_units, max_units, carryover_counts, instrument, probation_max_units): 100–400 "All programmes" 18–24; 500 "MBBS, LL.B and other five-year programmes" 18–24; 600 "MBBS" 18–24; 700 PGD 9–48; 800 Master's 6–48; 900 MPhil/Doctoral 0–48; `probation_max_units` is NULL for every row (the probation unit ceiling is **CONFIGURED BUT UNUSED**).
- `policy.in_force(kind, scope, at)` picks the version whose validity contains the date; `policy.grade_of(mark, at)`, `policy.class_of(cgpa, at)` (`V004:230`, `V013:224`).

## 5–6 Rules (the functions)
- `assessment.latest_scores(sheet)` (`V238:34`): latest version per student; total = `grace_total(ca+exam)` for typed marks, `coalesce(ca+exam,total)` for imported; grade/points via `policy.grade_of` at `current_date` (**not** at publication date — despite the UI's "effective-dated" claim, the grade is recomputed under whichever scheme is in force today; only one scheme is seeded so this is moot for now).
- `assessment.course_final(student, offering)` (`V198:64`): picks a PUBLISHED SPECIAL over a PUBLISHED RESIT over the MAIN sheet; a passed re-sit is recorded at the pass mark (lowest passing band low = 40, grade E, 1.00 point).
- `assessment.student_results(student)` (`V243:18`): every REGISTERED/APPROVED entry on an APPROVED/LOCKED registration, with the sheet stage ("NO_SHEET" when none), `published` flag, and — on a published sheet — a missing score or ABSENT counted as grade F, 0 points, outcome ABSENT.
- `assessment.student_gpa(student)` (`V243:46`): per session/semester CUR (units of published GRADED/ABSENT rows), CUE (units with points > 0), WGP, GPA = WGP/CUR (2 dp), running TCR/TCE/TWGP, CGPA = TWGP/TCR, LCGPA = previous CGPA. Non-GRADED outcomes other than ABSENT (WITHHELD, INCOMPLETE, MALPRACTICE, EXEMPTED) do not count in units.
- `assessment.student_cumulative(student, session, sem)` — same figures up to a period (used by the broadsheet).
- `registration.carryovers_at(student, session, sem, inclusive)` — non-elective courses failed (points = 0) on a published sheet and not later passed; `registration.carryovers(student)` feeds the student's Carryover screen.
- `assessment.standing_of(level, semester, cgpa, prev_cgpa, de_at_200)` (`V246:44`): NULL when CGPA ≥ 1.0 or unknown; first semester: PROBATION from 200 level unless a Direct-Entry student's 200 level; second semester: ADVISED_TO_WITHDRAW when level ≥ 200, not DE-at-200, and the previous CGPA was also < 1.0; otherwise PROBATION (so 100 level second semester and a DE student's 200 level pronounce probation).
- `assessment.student_standing(student)` (`V246:65`): applies `standing_of` to the latest published semester → GOOD / PROBATION / ADVISED_TO_WITHDRAW with the pronounced session/semester/level. (Which screens surface it is outside this group; the broadsheet computes the same via `repo.standingOf`.)
- Class of standing shown to students and on the statement = `policy.class_of(cgpa)` (`StudentPortalRepository.classOf`, `:377-382`); it is a classification band applied to a running CGPA, not a Senate-approved class of degree.

## 10 Data
`policy.version`, `policy.grade_band`, `policy.classification_band`, `policy.level_limit`, `policy.academic_session`, `policy.semester` — all audited (`trg_audit_policy_*`).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Effective-dated grading and classification tables | IMPLEMENTED (seeded, read) | `policy.*`, `grade_of`, `class_of` | no admin screen; grades computed at `current_date` |
| GPA/CGPA engine | IMPLEMENTED | `student_gpa`, `student_cumulative` | |
| Carry-over derivation (core only) | IMPLEMENTED | `registration.carryovers_at` | electives excluded (V242) |
| Probation / advised-to-withdraw pronouncement | IMPLEMENTED | `standing_of`, `student_standing` | probation unit ceiling (`probation_max_units`) unused |
| Class of degree at graduation | see graduation dossier | `policy.class_of` used by V262 documents | not a results-module act |

## 15 Glossary
CUR/CUE/WGP/GPA, TCR/TCE/TWGP/LCGPA/CGPA (as printed on the sheets); Grace mark; Class of standing; PROBATION / ADVISED_TO_WITHDRAW.

---

# F. Broadsheet, Senate schedule and publication  (API: results; pages /results/broadsheet, /results/senate, /results/publish)

## 1 Purpose
The broadsheet lays out every candidate of one programme at one level for one semester across all courses, with the CURRENT (CUR, CUE, WGP, GPA) and CUMULATIVE (TCR, TCE, TWGP, LCGPA, CGPA) figures and a REMARKS column in Senate's wording, computed from the sheets. The Senate schedule shows, by faculty, how many sets are at Senate, published or outstanding, and lets the Registrar/Deputy Registrar record the minute that publishes every set waiting at Senate in scope.

## 2 Users and roles
Broadsheet: `READERS`, with `scope.bound(null,null,prog)` refusing a programme outside a department/faculty office's bound (`ResultsController.java:239-244`). Senate read: `READERS`; minute: registrar, dregistrar (`:252-259`). The Senate screen's `RoleLine` disables the button for others (`SenateScreen.tsx:29, 54, 136-142`).

## 3 Navigation
Broadsheet `t/broadsheet` → `/results/broadsheet`: hod, dean, facultyexams, facultyofficer, records ("Broadsheets"), dregistrar, dvc, pgschool, pgsecretary ("Results Broadsheet"). Senate Schedule `t/senate` → `/results/senate`: records, dregistrar, dvc. Publication `t/publish` → `/results/publish`: records.

## 4 Screens
**Broadsheet** (`BroadsheetScreen.tsx`): scope bar (programme, level, session, semester; Excel export hook). Notes "The broadsheet is computed, not typed" and "A broadsheet is by programme and level. A score sheet is by course." Tiles Candidates / Mean GPA / Passed every course / Carrying over (pending sets). Panel "Examination reporting sheet" (cover: Faculty, Department, Degree in view, Level, Semester, Session; "Summary of results" — Total on Roll, Registered, did not Register, at Examination, did not sit, with Pass, Deferred (always "Nil"), with Carryover/Fail, on Probation, Advised to Withdraw, Expelled ("Nil"); Key; Courses; signature blocks Dean of Faculty / Head of Department) with **Download Excel** / **Download PDF** (print window). The sheet table: S/N, MATRIC NO. (class prefix once in the heading, serial per row), NAME OF CANDIDATE, course bands (carryover courses, GST, core, electives), CURRENT (CUR, CUE, WGP, GPA), CUMULATIVE DATE (hidden at 100 level first semester), REMARKS. Lists from 200 level: the class, "DIRECT ENTRY STUDENTS", then "PROBATION LIST" (first semester) or "ADVISED TO WITHDRAW" (second). Cells "75 / A5", "ABS / F0", "(not yet counted)" for a score still in the chain. Panels "The grading scheme this sheet used" and "Classification".
- Remarks (`ResultsService.broadsheet`, `:507-638`): "CO: {core courses owed}", "Fail: {electives failed}", "TO GO ON PROBATION", "ADVISED TO WITHDRAW", "PENDING" (a set still in the chain, nothing owed), "PASS", "DID NOT REGISTER FOR THIS SEMESTER" (class member without an approved registration, `repo.unregistered`). A mark counts once its set is at RECORDS, SENATE or PUBLISHED (`COUNTED`, `:505`); a published sheet with no score or ABSENT counts as F.
**Senate schedule / Publication** (`SenateScreen.tsx`, `publish` flag): RoleLine; notes ("Senate minute X is recorded" / "Nothing is published before the minute exists"; on Publication "N sets are live to their candidates" / "Publication is held: there is no Senate minute"); tiles; panel "Senate schedule — {session} {semester} semester" by faculty (Sets, Candidates, At Senate, Published, Outstanding, Recommendation pill "Approve" / "Approve, outstanding named" / "All published" / "Nothing at Senate"); on Publication the steps "What a release does, in order"; panel "Record the resolution" / "Release control": fields "Minute number" (placeholder "SEN/2026/…"), "Faculty" (Every faculty or one) → **Record the minute and release** / **Release to candidates on the minute** (disabled when nothing is at Senate); outcome note "N sets published under {minute}, M refused" listing each refusal; panel "Minutes recorded" (Minute, Sets, Candidates, First release, Last release).

## 5–6 Workflow and rules
Publication = `assessment.advance` to PUBLISHED for each sheet at SENATE in scope (`repo.sheetsAtSenate`), each in its own transaction; BR-006 refusals reported (`recordMinute`). `RES_MINUTE_REQUIRED` "A result reaches a student on the Senate minute that approved it, and none was cited." Broadsheet figures come from `repo.broadsheet` cells, `repo.cumulative` (`assessment.student_cumulative`), `repo.carryoversAt`, `repo.standingOf`.

## 7 Notifications
None (publication does not notify; see B.7).

## 8 Reports, exports
- Broadsheet Excel: two sheets "Summary" and "Broadsheet", two-row merged heading, file name "Result {degree} {level} Level {semester} Semester {session}.xlsx", serial `docSerial("BRD")`, crest (`:141-187`).
- Broadsheet PDF: print window HTML "Examination Reporting Sheet" cover + lists, same serial (`:189-236`). No QR / no verification endpoint for the broadsheet serial.
- The Senate screens have no export ("Print the schedule" is listed in the Desk's "can" text but no button exists).

## 12 Security notes
Programme bound checked server-side. Publication by a `DESKS` office through the single-sheet advance is possible (see B.12).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Computed broadsheet with Senate lists and remarks | IMPLEMENTED | `ResultsService.java:507-638`; `BroadsheetScreen.tsx` | |
| Excel / PDF export of the reporting sheet | IMPLEMENTED | `BroadsheetScreen.tsx:141-236` | PDF is a print dialog, not a server PDF |
| Senate schedule and minute-based release | IMPLEMENTED | `recordMinute`; `SenateScreen.tsx` | |
| "Withheld set shows as withheld, with the reason the Board recorded" (screen text) | NOT IMPLEMENTED | no withheld-set concept in data | text only |
| Print the Senate schedule | NOT IMPLEMENTED | no export on `SenateScreen.tsx` | |

## 14 Common problems
"Nothing is waiting at Senate in this scope." — sets are not yet at SENATE (Records must validate). A set "refused" on the minute: the same person validated it at RECORDS; another holder of the office records the minute. Broadsheet "No approved registration at this level…": pick the right programme/level/session.

---

# G. The student's results, statement, broadsheet, docket and public verification  (API: studentportal MeController `/api/v1/me/results|queries|docket`, verify; pages /student/results, /student/results/[session]/[semester] (+pdf), /student/broadsheet (+pdf), /student/carryover, /student/exams (+card pdf), /verify/results, /verify/exam)

## 1 Purpose
The student sees only what Senate has published: per semester the courses with the desk each unpublished sheet is on, the published score/grade/points, GPA and CGPA, the class of standing, carry-overs; a per-semester Statement of Results PDF with a QR that opens the University's own record; a whole-history broadsheet PDF; the examination docket with timetabled papers and an examination card PDF. A results fee gate withholds marks server-side when the clearance scheme says so.

## 2 Users and roles
Student only (`OFFICE_student`). Verification endpoints are public (`SecurityConfig.java:56` permits `/api/v1/verify/**`).

## 3 Navigation (menus.md 688-698)
Results `s/results` → `/student/results`; Result Broadsheet `s/broadsheet`; Result Query `s/query`; Carryover `s/carryover`; Examinations `s/exams`. `/student/transcript` redirects to `/student/documents?new=TRANSCRIPT` (V262).

## 4 Screens
- **Results** (`fe/app/student/Screens4.tsx:26-96`): notes "Your results are withheld until your fees are settled" (when `clearsResults === false`), "Nothing is registered against you yet", "Your {session} {semester}-semester results are not published yet", "N of your M courses are published", "All N courses are published under minute X — Released {date}". Tiles "This semester" (GPA on units released), "Cumulative", "Standing", "Units this semester". Panel for the latest semester: Course, Units, Score, Grade, Points, "Where it is" (stage label), "Taught by"; buttons **Semester Results** and a disabled **Official transcript** ("Arrives with the credentials module" — stale: documents now live under My Documents). Panel "Academic summary" (Session · Semester, CUR, CUE, WGP, GPA, TCR, TCE, TWGP, LCGPA, CGPA, Open). Note "N carryovers … will be added to your next registration automatically."
- **Statement of results** (`Slip`, `:98-134`): GPA/CGPA banner with the class of standing, table Course/Unit/Score/Grade, totals "Units registered N · passed M", "GP x.x", carryover note, **Download result slip** → `/student/results/{session}/{semester}/pdf`, "Published {date} after Senate approval · minute X".
- **Result broadsheet** (`:138-196`): tiles Name/Level/CGPA/Standing; one panel per published semester (Course, Title, Unit, CA, Exam, Total, Grade, Point) with the CUR…CGPA line; **Print broadsheet** → `/student/broadsheet/pdf`.
- **Carryover** (`Screens5.tsx:80-110`): note "You are carrying N courses, U units" / "You are carrying nothing"; tiles; table Course, Units, Failed in, Note; panel "How a repeat is scored" (static text: pass mark 40, units counted once, registered before a new course).
- **Examinations / docket** (`Screens5.tsx:112-141`): notes for no scheme ("What a payment releases is not yet stated"), not cleared ("Your docket is withheld until your fees are settled"), or "Bring your identity card"; per open exam session a table Course, Date & time ("Not yet timetabled"), Venue, Status (Withheld / Docket ready / Awaiting slot); **Download exam card** → `/student/exams/card/pdf?session=&semester=` and **Print the docket**.
- **Public verification pages**: `/verify/results?m=&s=&sem=&c=` ("Genuine statement — this is the University's record" / "Not verified"; name, matric, programme, level, session, semester, GPA, CGPA, class of standing, "Approved by Senate on … · minute …", published grades) and `/verify/exam` (name, photo, matric, session, semester, "Cleared" Yes/No, courses).

## 5–6 Rules
- `StudentPortalService.results` (`:289-338`): rows from `assessment.student_results`, semesters from `assessment.student_gpa`; when a clearance scheme is in force and `repo.clears(student, session, 'RESULTS')` is false the row's ca/exam/total/grade/points are nulled and `withheld=true`, GPA/CGPA nulled for that session, `withheldSessions` listed; `clearsResults` for the current session; `standing = policy.class_of(cgpa)`; `carryovers = registration.carryovers(student)`.
- PDF routes refuse with 409 "Withheld — Results are withheld until the fees are settled." and "Nothing published" (`pdf/route.ts:33-35`, `broadsheet/pdf/route.ts:21`). The exam card refuses "No approved registration" and "Not cleared for examinations".
- Docket: `assessment.student_docket(student, exam_session)` — the approved registration's offerings with any timetable slot and the sheet stage; `clearsExamination = clears(…,'EXAMINATION')`.

## 7 Notifications
None from these screens.

## 8 Reports, exports and documents
- **Semester Results PDF** (`fe/app/student/results/[session]/[semester]/pdf/route.ts`): brand header "Semester Results · Exams & Records"; Name, Programme · Level, Matriculation number, Session · semester; table COURSE / UNIT / SCORE / GRADE / POINTS; totals; box Semester GPA / Cumulative GPA / Class of standing; SUMMARY line (CUR…CGPA); GRADING key hard-coded "A 70-100 (5) B 60-69 (4) C 50-59 (3) D 45-49 (2) E 40-44 (1) F 0-39 (0)" (`:122`, not read from policy); "Approved by Senate on {date} · minute X"; QR to `/verify/results?…&c=` where `c = sha256("RESULT|matric|session|semester")[0:12]` (`fe/lib/qr.ts:41-47`) and the text "Check code {c}"; footer "Issued by the portal on …".
- **Result broadsheet PDF** (`broadsheet/pdf/route.ts`): "Result Broadsheet · Exams & Records", per semester COURSE/TITLE/UNIT/CA/EXAM/TOTAL/GRADE/PT and the summary line; no QR.
- **Examination card PDF** (`exams/card/pdf/route.ts`): courses to sit, passport photo from `/api/v1/me/passport`, instructions list, QR to `/verify/exam`.
- Verification: `VerifyController.results` (`:251-300`) returns only published rows and only when the stateless token matches; `genuine:false` otherwise. **No rate limiting** exists on `/api/v1/verify/**` (no limiter found in `api/`), contrary to "rate-limited" wording elsewhere; the token stops enumeration.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Results view with stage per unpublished course, fee gate | IMPLEMENTED | `StudentPortalService.java:289-338`; `Screens4.tsx` | |
| Statement PDF with QR verification | IMPLEMENTED | pdf route; `VerifyController.java:251-300` | grading key hard-coded |
| Broadsheet PDF | IMPLEMENTED | `broadsheet/pdf/route.ts` | |
| Carryover screen | IMPLEMENTED | `Screens5.tsx:80-110` | "How a repeat is scored" is static text |
| Docket and exam card | IMPLEMENTED | `docket`, card route | |
| "Official transcript" button | PLACEHOLDER (stale) | `Screens4.tsx:70` disabled | transcripts are under My Documents (V262) |
| Verify rate limit | NOT IMPLEMENTED | no limiter in api | |

## 14 Common problems
"Your results are withheld until your fees are settled": pay under the scheme's RESULTS release rule. "Not yet timetabled": the Examinations Office has not set the slot (class-list desk). Statement 409 "Nothing published": no published sheet for that semester. QR says "Not verified": code/session/semester do not match or nothing is published.

---

# H. CBT question bank  (API: cbt/QuestionBankController; table assessment.question; page /exams/question-bank)

## 1 Purpose
A per-course bank of multiple-choice questions tagged by topic, difficulty and marks, with a "blueprint" count by topic × difficulty. Questions are retired, not deleted. **There is no CBT examination**: no test, sitting, paper assembly, candidate delivery or scoring exists anywhere in the code (grep for `/api/v1/cbt` shows only these four endpoints; the "CBT Sessions" menu item opens the results Examination sessions screen).

## 2 Users and roles
Read: `READERS = lecturer, hod, exams, facultyexams, dean, academic, registrar, admin, super` (`QuestionBankController.java:289`); author/retire: `AUTHORS = lecturer, hod, exams, dean, super` (`:290`). No department or course scope: any reader sees every course's bank.

## 3 Navigation
Exams Officer: Question Bank `t/cbtbank` → `/exams/question-bank` (menus.md:201). Lecturers have no menu item (the lecturer's `/results/mine` carries a `bankQuestions` count per sheet).

## 4 Screens
`/exams/question-bank` (`QuestionBank.tsx`): without a course, note "A paper is assembled to a blueprint, not picked by hand" and a Courses table (Code, Title, Questions, **Open**); with `?course=`: tiles Course / Active questions (N retired) / Topics / Marks available; panel "Blueprint" (Topic, Easy, Medium, Hard, Total); panel "Questions" (stem with "Answer: …", Topic, Difficulty pill, Marks, Active/Retired pill and **Retire/Restore** for authors); panel "Author a question": Question textarea, four option inputs with a radio "Correct answer", Topic (optional), Difficulty (Easy/Medium/Hard), Marks → button posts `/api/v1/cbt/questions` (`:102-121`).

## 6 Business rules
Bean: course ≤ 10, stem ≤ 2000, options ≤ 500 each, answer ≥ 0. Controller: `CBT_OPTIONS` "A question needs at least two options."; `CBT_ANSWER` "The correct-answer position is outside the options." DB CHECKs: options a JSON array ≥ 2; `0 ≤ answer < length`; difficulty EASY/MEDIUM/HARD; marks > 0; stem not blank. Defaults MEDIUM, 1 mark.

## 10 Data
`assessment.question(id, course_code→catalogue.course, topic, stem, options jsonb, answer, difficulty, marks, active, authored_at, authored_by)`; audited.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Question authoring, retire/restore, blueprint counts | IMPLEMENTED | controller `:306-365`; `QuestionBank.tsx` | |
| Editing a question's text | NOT IMPLEMENTED | no PUT | retire and re-author |
| CBT tests, paper assembly, delivery, scoring | NOT IMPLEMENTED | no code, no tables | menu "CBT Sessions" opens results exam sessions |
| Course/department scoping of the bank | NOT IMPLEMENTED | no scope call | |

## 15 Glossary
Blueprint (counts by topic × difficulty of active questions); Retired question (`active=false`).

---

# I. College of Health Sciences — MB;BS  (API: college/CollegeController, provost/ProvostController; schema college; pages /college, /college/dashboard, /college/coordinator, /college/examinations, /college/scoresheets, /college/calendar, /college/postings, /college/supervision, /college/payments, /college/student)

## 1 Purpose
From 200 Level a College student runs on the College's own years rather than the University's semester GPA: a year (enrolment) at a level, registered semester by semester on that semester's fees (V249), dated by the College calendar; from 400 Level, allocation to blocks and postings with a supervisor who keeps a logbook (procedures, cases, attendance, mandatory events); one examination per level — CPE at 200, 1st–4th Professional at 300–600 — with subjects marked CA + examination (+ clinical), the pass judged by the rule (50, attendance minimum, clinical minimum), a provisional progression decision applied automatically when every subject is resulted, confirmed by the College Academic Board on a minute, which promotes, opens a resit, closes the year for a repeat, withdraws, or graduates (with MBBS Honours for a distinction in each Professional). 100 Level stays on the University's courses, judged by the College's 100 Level rule (every non-GST course ≥ 50). The Provost, College Secretary and Finance Controller share a dashboard; the Finance Controller's home is the Student Payment Report (V256); the MBBS Coordinator is bound to one level (V250).

## 2 Users and roles (guards in `api/college/CollegeController.java`)
- `DESK` (`:17`): provost, collegesecretary, academic, registrar, dregistrar, admin, super — allocations, decisions, confirm, appeals, calendar edit, supervisors list.
- `DESK_OR_COORDINATOR` (`:23`) adds mbbscoordinator — students list, enrol.
- `EXAMINERS` (`:21`): DESK + lecturer, hod, exams, mbbscoordinator — candidates, results, bulk, CA assessments, uploads, coordinator summary. `assertCollegeExaminer` (`:49-57`) refuses a department office whose department is not the College's: `COLLEGE_NOT_EXAMINER` "The Professional examinations are examined by the College of Health Sciences' own departments."
- `READERS` (`:18-19`): DESK + financecontroller, records, dean, hod, lecturer, exams, vc, dvc, mbbscoordinator — structure, exams, summary, reconciliation, calendar, overview, dashboard, requirements, allocations of a posting.
- `SUPERVISORS` (`:287`): lecturer, hod, exams + DESK offices — logbook writes, limited by `supervised()` to the allocation's supervisor or a desk office: `COLLEGE_NOT_SUPERVISOR` "This posting is supervised by someone else; only the supervisor, or the College's desk, writes its logbook." (`:298-312`).
- `PAYMENT_READERS` (`:34-35`): financecontroller, provost, collegesecretary, bursar, registrar, dregistrar, academic, dvc, vc, super.
- `STUDENT`: my-record, my-postings, my-logbooks, my-assessments, register.
- MBBS Coordinator scope: `assertLevel` (`:38-46`) — `COLLEGE_NOT_YOUR_LEVEL` "The MBBS Coordinator acts at N Level; this is M Level." (level from the `mbbscoordinator` grant's `scope_kind='level'`); `COLLEGE_NO_LEVEL` when the grant names none.
- Provost dashboard (`api/provost/ProvostController.java:431`): provost, collegesecretary, financecontroller, super; scope = the office grant's college, else the staff record's faculty college, else the sole college.

## 3 Navigation (menus.md)
- Provost (793-806), College Secretary (811-824), Finance Controller (845-859): Dashboard `r/college` → `/college/dashboard`; Student Payment Report `t/collegepayments` → `/college/payments`; College Overview `t/college` → `/college`; Professional Examinations `t/collegeexams` → `/college/examinations`; College Calendar `t/collegecalendar`; Postings `t/postings`; Logbooks `t/supervision`.
- MBBS Coordinator (829-840): Dashboard `r/mbbscoordinator` → `/college/coordinator`; Score Sheet `t/collegesheets` → `/college/scoresheets`; Professional Examination; College Calendar; College Overview; Postings; Logbooks.
- Academic Office, Records, Registrar, Super: College of Health Sciences `t/college` → `/college` (224, 383, 507, 467). Bursar: College Payment Report (280). Lecturer: Postings I Supervise `t/supervision` (26). Student: the College dashboard at `/college/student` (no menu row in menus.md; reached from the student shell; `VIEWS` Dashboard / Fees & payments / Course registration / Postings & logbook / Results history, `student/page.tsx:42`).

## 4 Screens
**College dashboard** `/college/dashboard` (`dashboard/page.tsx`): for the Finance Controller it renders the Payment Report instead (`:24-31`). Otherwise: PageHead "Welcome, {name}" with buttons Professional Examinations / Postings / College Calendar / College Overview; a StatsPanel; tiles Students / Years open / Awaiting the Board / Postings this session; panel "What waits on the College" (kinds The Board, Results, Registration, Calendar, Senate, Appointment — each with text and **Open**; built in `CollegeController.dashboard` `:1143-1268`); "The session by level" (from `/exams/summary`: Cohort, Registered, With every result, Decisions, Year "At its end"/"Running"); "The rotation this session" (400+: on a posting, allocations, in progress, completed, incomplete, without a supervisor); "Fees this session" (First/Second semester cleared, Year registered, via `finance.semester_cleared`); "Decisions confirmed most recently"; "The MBBS Coordinators" (level, holder, since; "Not appointed"); "The College's desks lately" (audit spine, 90 days).
**Provost API** `/api/v1/provost/dashboard` (`ProvostController.java:430-510`): students, registration by department, sheet pipeline counts, offerings without a lecturer, probation and "at risk" list. **No frontend calls it** (grep `provost/dashboard` in `fe/` returns nothing) — backend without UI.
**MBBS Coordinator dashboard** `/college/coordinator` (`coordinator/page.tsx`): welcome note with the level and department; tiles Level / Cohorts running / Students at the level / Awaiting the Board; "Your doors" (Score sheet, Professional examination, Postings, College calendar, College overview); "What waits on you" (level-filtered); "Results by subject" per open cohort (Resulted, Passed, Barred, progress); "Cohorts at N Level" (Students, Registered, Year, Runs, With results, Decisions, "Waiting on" text: "N not fully registered" / "The year runs to {date}; results open at the final semester" / "N without results" / "N provisional decisions for the Board" / "N resits pending" / Closed / Decided).
**College overview** `/college` (`Overview.tsx`): tiles; "The levels" (Level, Phase, Students, Years open, Cohorts, Examination, Decisions, Calendar Dated/Undated, Open → examinations or Broadsheet at 100); "Blocks and postings"; "The programme, from the prospectus"; "Progression, as the rule applies it"; note "Still to confirm with the College".
**Professional examinations** `/college/examinations?session=&exam=` (`Examinations.tsx`): scope Session, Examination; "The examinations · {session}" summary table; a note with the exam's papers and each subject's weights ("Anatomy (CA 30, examination 70, pass 50)") and any `conflict_note` in red; note "The N Level year for the {session} cohort has not reached its final semester" when results are locked; tiles Cohort / Subject results / Decisions / "Ready for Senate"; panel "The College Academic Board confirms" with field "Board minute" and **Confirm N decisions** (browser confirm) → `POST /exams/{code}/confirm`; note "The crossing to Senate is a reconciliation, not a file drop" naming missing/undecided; "Results by subject"; "Candidates for {code} · the {session} cohort" with Show filters (Everyone / Not fully registered / No results yet / Results incomplete / Passed every subject / …), **Open the year for a student** (field "Matriculation number" → `POST /enrol`), a download of "results and decisions" CSV (`downloadSheet`, `:168-188`), the candidates table (Matriculation number, Name (UTME/Direct Entry, repeat/appeal), one column per subject with total and Pass/Fail/Barred pill, Decision pill, **Open**). Candidate panel: attempt select (FIRST/RESIT/REPEAT/SENATE_APPEAL); table Subject / CA / Examination / Clinical / Attendance % / Total / Standing (on save: Distinction / Pass / Barred / Fail) / earlier attempts; **Save the {attempt} results** (one POST per subject to `/exams/{code}/results`); "CA kept during the year" (items and scores; Item select + Score → **Record** `POST /assessments`); "Progression decision" ("The rule says …"; provisional/confirmed pill; for a confirmed APPEAL at PE4 the field "Senate minute" → **Record Senate's approval of the appeal** `POST /exams/{code}/appeals`; Decision select (Promote, Graduate, Resit, Repeat, Advised to withdraw, Required to withdraw, Appeal to Senate), "Carry-overs (GST / EPS only)", "Board minute" → **Change the provisional decision** `POST /exams/{code}/decisions`).
**Score sheet** `/college/scoresheets?session=&level=` (`ScoreSheets.tsx`): scope Cohort (session), Level (hidden for the coordinator); "Score sheets by level"; tiles Cohort / Registered / With every result / Year; buttons **Download the score sheet** (xlsx per cohort: "S/N, Matriculation number, Name, Registered, {subject} · CA (0-30), · Exam (0-70), [· Clinical (0-100)], · Attendance % (0-100)" with validations), **Upload the filled sheet** (preview with flags "not in the N Level cohort", "not fully registered", "not a number", "is over", "attendance missing", "clinical mark missing", "barred at x% attendance", "no marks on the row"; then **Save** → `POST /exams/{code}/results/bulk` — rows flagged not-in-cohort/over-range/missing/empty are left out client-side; the API refuses the rest by row), **Download the marked sheet** (Total/Remark per subject, Decision, summary). Panels "Marked sheet…", "Marks entered for this sheet" (from `/exams/{code}/uploads` — audit spine), "The cohort as it stands". **Defect**: the workbook letterhead constant is `UNI = "Moshood Abiola University of Science and Technology, Abeokuta"` (`ScoreSheets.tsx:18`) — the wrong university on both exports.
**College calendar** `/college/calendar?session=` (`Calendar.tsx`): Session; tiles Levels dated / Years open, undated / Running now / Unsaved changes; buttons **Copy {prev}'s dates, a year on**, **Save all N** (mayEdit = DESK offices, `calendar/page.tsx:22`); "The session at a glance" timeline against the University's semesters; "The year at each level"; per level a table Semester / Weeks / Subjects / Starts / Ends / Standing / **Save** (blank both dates to clear; a span differing from the prospectus's weeks shows amber, an end before start is refused) plus **Date from the first semester** (fills by prospectus weeks); "The University's semesters".
**Postings** `/college/postings?session=&level=&posting=` (`Postings.tsx`): Session, Level (≥ 300), Posting; without a posting: the postings at the level (Block, Posting, Tier, Weeks, Allocated, In progress, Completed, Supervisors, **Open/Allocate**) and "Students at N Level · where each is on the rotation" (Allocated x of y, Completed, Now on, Not yet allocated); with a posting: "Students at this level not yet on it" (search, **Tick all**, **Clear**), "Allocate the ticked students" (Rotation group, Supervisor SearchSelect "Search the College's staff…", Starts, Ends → **Allocate N students** `POST /allocations`), "On {posting} in {session}" (Group, Supervisor, Starts, Ends, Standing pill Allocated/In progress/Completed/Incomplete; row actions **Edit**, begin (→ IN_PROGRESS), complete, mark incomplete (confirm), **Withdraw** (confirm; only ALLOCATED); bulk begin/complete buttons); modal to edit one or all ("Only what is filled changes").
**Logbooks / supervision** `/college/supervision?session=&allocation=` (`Supervision.tsx`): Session, "Student on a posting"; "Supervisors this session"; "The students you supervise" (desk offices see everyone with `all=true`); "What the logbook asks, by posting", "Attendance rules", "Mandatory events" (from `/requirements`); for one allocation: "Procedures" (Procedure, Date, Mode Observe/Perform, Patient reference → record; **Verify** per unverified log), "Cases clerked" (Date, Patient reference, presented), "Attendance" (Date, Activity LECTURE/PRACTICAL/CLINICAL/TUTORIAL/TEST/OTHER, Timetable slot, Present), "Mandatory events" (Event, Date, Present).
**Student Payment Report** `/college/payments` (`PaymentReport.tsx`): PageHead "Student Payment Report"; filters Academic session, Period (hint "Payments cover the first semester before the second"), Department, Programme, Level, Payment status (FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE), Search ("Name, matriculation number or payment reference", placeholder "e.g. MOAUM/MED/24/9907 or a reference"); tiles; "By programme" with Excel/PDF; "Students" table; exports via `brandedXlsx`/`brandedPrint` titled "Student Payment Report — College of Health Sciences", "Student Payment Summary — …", "Student Payments by Programme — …", serial `docSerial("CHSPAY")`.
**College student dashboard** `/college/student?view=` (`student/page.tsx`): views Dashboard / Fees & payments / Course registration / Postings & logbook / Results history; "Your journey to the MB.BS"; "{level} Level · {session}" with the three steps (pay fees, register, the examination) and a **Pay … fees** link; **Register {semester}** / **Register N Level · session** (`RegisterButton.tsx` → `POST /college/register {session}`); "100 Level · Pre-Medical" outcome by the College's rule; latest decision note; carry-overs; "The examination ahead"; "Your postings"; "Fees by session"; "Semesters at your level"; "CA recorded so far"; results history with decisions.

## 5 Workflow and statuses
- **Enrolment (a College year)** `college.enrolment(kind REGULAR|REPEAT|APPEAL, state OPEN|RESIT|CLOSED, attempt_no, registered_at, registered_items, resit_subjects)`; `college.enrolment_semester` per prospectus template (200: two 17-week semesters; 300: one 20-week "Third Semester"; 400–600: no template = the whole year registers at once). Opened by the student's **Register** (`college.register_level`) or the desk/coordinator (`/enrol` → `college.open_enrolment`). A year closes only by the Board's confirmation (`confirm_decisions`: RESIT keeps it OPEN as `RESIT`; every other outcome → CLOSED).
- **Registration gate**: each semester registers on its own fees — `finance.semester_cleared(student, session, ordinal)` (confirmed "School fees%" references ≥ `finance.due_for_semester`); clinical years register whole on semester 1's fees; "the earlier semester is registered first". Deferment triggers `trg_deferment_gate_college_year/semester` refuse registration for a deferred student.
- **Results** `college.exam_result(attempt FIRST|RESIT|REPEAT|SENATE_APPEAL, ca_score, exam_score, clinical_score, attendance_pct, barred, passed, total)`; upsert per (student, subject, session, attempt). `college.judge` → passed = total ≥ pass_mark (50) and clinical ≥ `clinical_component_min` where set, unless attendance < `min_attendance_pct` → barred and failed.
- **Decision** `college.progression_decision(outcome PROMOTE|RESIT|REPEAT|WITHDRAW_ADVISED|WITHDRAW_REQUIRED|APPEAL|GRADUATE, state PROVISIONAL|CONFIRMED, rule_ref, minute, resit_subjects, carry_overs, honours)`: `college.apply_provisional` runs after every result save; when all subjects have a result, `college.decide` gives: no fails → PROMOTE (GRADUATE at 600); latest attempt RESIT with fails → REPEAT; SENATE_APPEAL fails → WITHDRAW_REQUIRED; REPEAT fails → APPEAL (PE4), WITHDRAW_ADVISED (CPE, PE1) or WITHDRAW_REQUIRED (PE2, PE3); FIRST fails → `next_attempt`: REPEAT when resit not allowed (CPE) or all subjects failed where `no_resit_if_all_failed` (PE1), else RESIT. The Board may override with `/decisions` (only while PROVISIONAL: `COLLEGE_CONFIRMED`; only when every subject is resulted: `COLLEGE_UNDECIDED`). A confirmed RESIT is re-opened for the Board by the resit's own results.
- **Confirmation** (`college.confirm_decisions`, minute required: "the Board confirms on a minute, and none was cited"): each PROVISIONAL decision → CONFIRMED; RESIT → enrolment RESIT with `resit_subjects`; else enrolment CLOSED; PROMOTE → `people.student.current_level += 100`; WITHDRAW_* → `people.change_status(…,'WITHDRAWN', instrument "College Academic Board minute X (exam, session)")`; GRADUATE → `change_status('GRADUATED', …)` with "with Honours (a distinction in each of the four Professional examinations)" when `college.honours` (total ≥ 70 in a passed subject of each of PE1–PE4).
- **Appeal** (`college.grant_appeal`): only when the last confirmed 600-level decision is APPEAL; opens an `APPEAL` enrolment (4th attempt) and appends "· Senate: {minute}".
- **Postings** `college.posting_allocation.state ALLOCATED → IN_PROGRESS → COMPLETED | INCOMPLETE`; withdraw only while ALLOCATED (`COLLEGE_ALLOC_STARTED`).
- **100 Level** (`college.decide_100`): INCOMPLETE while any entry-session course is unpublished; WITHDRAW_ADVISED if any non-GST course < 50; else PROMOTE; GST courses < 50 are "carried". `register_level` refuses a 200-level registration under WITHDRAW_ADVISED: "the College's 100 Level rule does not promote: {courses} below 50" (HINT "Every C-group course … passed at 50 or more, with no resit; the College advises withdrawal."). **No act records the 100 Level withdrawal** — it is read-only advice; the student's status is not changed.

## 6 Business rules and validations (messages as written)
Controller (`CollegeController.java`): `COLLEGE_DATES` "A posting ends after it starts."; `COLLEGE_GROUP` "That rotation group is not one of this posting's."; `COLLEGE_NOT_MEMBER` "N of the students are not the College's: …"; `COLLEGE_STATE` "A posting allocation is allocated, in progress, completed or incomplete."; `COLLEGE_PROC_MODE` "A procedure is observed or performed."; `COLLEGE_PROC_POSTING` "That procedure is not one this posting asks for."; `COLLEGE_ACTIVITY` "An attendance is at a lecture, a practical, a clinical session, a tutorial, a test or another activity."; `COLLEGE_EVENT` "That event is not one of this block's."; results: `COLLEGE_ATTENDANCE_RANGE` "Attendance is a percentage, 0 to 100."; `COLLEGE_ATTENDANCE` "{exam} requires attendance of N%; the candidate's attendance is entered with the marks."; `COLLEGE_ATTEMPT` "An attempt is the first, a resit, a repeat or a Senate appeal."; `COLLEGE_SUBJECT` "That subject is not one of this examination's."; `COLLEGE_CA_RANGE` "{subject}: CA is out of 30."; `COLLEGE_EXAM_RANGE` "{subject}: the examination is out of 70."; `COLLEGE_CLINICAL` "{subject} has a clinical component; its mark out of 100 is entered with the examination."; `COLLEGE_CLINICAL_RANGE`; `COLLEGE_NOT_MEMBER` "That student has no N Level year in {session}."; `COLLEGE_YEAR_NOT_ENDED` "The N Level year for {session} has not reached its final semester; the College's students sit once, at the end of the year." (`college.year_reached_final`: the last dated semester has started; **true when the level is undated**); `COLLEGE_OUTCOME`; `COLLEGE_CONFIRMED` "The Board has confirmed this candidate's decision; it is not changed here."; `COLLEGE_UNDECIDED` "The candidate has a result in x of the examination's y subjects; a decision waits on all of them."; `COLLEGE_NO_APPEAL` "{exam} carries no appeal to Senate."; `COLLEGE_CALENDAR` "A semester ends after it starts."; `COLLEGE_SHEET_REFUSED` "No row of the sheet could be saved: …"; `COLLEGE_NOT_MEMBER` (my-record) "This record is not the College of Health Sciences'."
SQL: `open_enrolment` — "not a College of Health Sciences student"; "a student who is {status} does not enrol"; "100 Level is the University's year, registered by semester on its form"; "the student is at N Level, not M"; "the student has a College year still open; it closes by the Board's decision before another opens"; "the appeal to Senate is not yet granted"; "the record at this level is closed by withdrawal". `register_level` — "100 Level registers on the University's form, by semester"; "the N Level year is still open; it closes by the Board's decision before M Level opens"; "the N Level fees for {session} are not yet cleared" (HINT "Registration opens the moment the session's first semester fees are confirmed; the second semester's are due before its results."). `register_semester` — "this College year is closed"; "the earlier semester is registered first"; "the N Level fees for {session} semester k are not yet cleared". `grant_appeal` — "no appeal stands for this student: the last confirmed decision at 600 Level is …"; "Senate's approval is recorded on its minute, and none was cited".
Seeded rule rows (`college.professional_exam`): CPE (200; papers ESSAY, MCQ, PRACTICAL, ORAL_OPTIONAL; no resit; min attendance 75); PE1 (300; external examiners; resit 3 months; no resit if all failed; 75); PE2 (400; resit; 70); PE3 (500; resit; 70); PE4 (600; resit; appeal to Senate; no attendance minimum). Subjects (all CA 30 / exam 70 / pass 50): CPE and PE1 Anatomy, (Medical) Biochemistry, Physiology; PE2 Pathology, Pharmacology & Therapeutics; PE3 Paediatrics, Obstetrics & Gynaecology; PE4 Medicine, Surgery, Community Medicine & Epidemiology. `college.programme_rule` C00061 MB.BS: 6 years UTME / 5 DE, 160 CU, unclassified, distinction 70, "No carry-over except GST and EPS courses…", Honours rule. Blocks COM, FAM, MED, OBG, PAE, PHT, PTH, SUG; 24 postings (INTRO 2, JUNIOR 6, INTERMEDIATE 3, SENIOR 7, REVISION 1, LECTURES 5); `college.level` 100 PREMEDICAL … 600 CLINICAL year 3; assessment items COURSE_TEST 2, END_OF_POSTING_MCQ 1, END_OF_POSTING_CLINICAL 2, SUPERVISOR_EVAL 1, PROJECT 1, PERIODIC_TEST 1, OSCE 1.

## 7 Notifications
None. Neither the College controller nor the `college.*` functions call `platform.queue_notice` (grep). Withdrawal/graduation go through `people.change_status`, whose own notices (if any) belong to the student-record dossier.

## 8 Reports, exports and documents
- Score sheet template and marked sheet (xlsx, `ScoreSheets.tsx`) — wrong letterhead constant (see 4).
- Results and decisions CSV from the examinations desk (`Examinations.tsx:168-188`).
- Student Payment Report / Summary / by Programme (Excel and print PDF, serial CHSPAY).
- "Marks entered for this sheet" is an audit-spine read (`/exams/{code}/uploads`), not an export.
- No College transcript, result slip or Board schedule PDF exists.

## 9 Configuration
`college.professional_exam`, `exam_subject`, `assessment_item`, `programme_rule`, `level`, `semester_template`, `block`, `posting`, `posting_course`, `rotation_group`, `procedure_requirement`, `attendance_rule`, `mandatory_event`, `timetable_slot` are seeded by V245/V248/V249; **no screen edits them** (all read-only in the API). The College calendar (`college.semester`) is the one editable configuration. The MBBS Coordinator is an `iam.office_assignment` with `scope_kind='level'` made at the People desk.

## 10 Data
Tables and purpose (all audited; `college.enrolment(_semester)` also carry the deferment gate triggers): `enrolment`, `enrolment_semester`, `semester` (dated calendar), `semester_template`, `level`, `professional_exam`, `exam_subject`, `assessment_item`, `assessment_score` (CA kept during the year; UNIQUE student/item/attempt), `exam_result`, `progression_decision`, `carry_over` (GST/EPS owed; `cleared_on`), `programme_rule`, `block`, `department_unit`, `posting`, `posting_course`, `rotation_group`, `posting_allocation`, `timetable_slot`, `procedure_requirement`, `procedure_log`, `case_clerking`, `attendance_rule`, `attendance_record`, `mandatory_event`, `event_attendance`, `project`. Nothing writes `college.project`, `college.carry_over` (the decision's `carry_overs` text[] is not copied into `carry_over`) or `college.department_unit` from the API — CONFIGURED BUT UNUSED apart from seed data. `college.timetable_slot` has 200 rows seeded; attendance may reference a slot.

## 11 Scheduled jobs and integrations
None. Fees are read from `finance.payment_reference` through `finance.semester_cleared`/`finance.payment_position`.

## 12 Security notes
- The College examiner check (`assertCollegeExaminer`) binds a department office (lecturer, HOD, exams) to a College department on candidates (`:531`), single results (`:574`), bulk (`:893`) and CA writes (`:866`); the desk offices are not so limited. The CA read `GET /assessments` (`:841`) applies only `assertLevel`, so any `EXAMINERS` office may read the CA of any College student.
- `year_reached_final` is `true` for an undated level, so results can be entered any time until the College dates the calendar (the dashboard flags "undated" for this reason).
- Bulk results run each row in a nested transaction; a partly-refused sheet still saves the good rows.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| College years, semester-by-semester fee-gated registration | IMPLEMENTED | `college.register_level/register_semester` (V249); `RegisterButton.tsx` | |
| College calendar | IMPLEMENTED | `CollegeController.java:799-839`; `Calendar.tsx` | |
| Postings allocation and states | IMPLEMENTED | `:172-256`; `Postings.tsx` | |
| Logbook (procedures, cases, attendance, events) | IMPLEMENTED | `:340-513`; `Supervision.tsx` | student reads only |
| Professional examination results, rule-judged pass, provisional decision | IMPLEMENTED | `:570-642`; `college.judge`, `apply_provisional` | |
| Bulk score sheet upload with preview | IMPLEMENTED | `:891-943`; `ScoreSheets.tsx` | letterhead names another university (`ScoreSheets.tsx:18`) |
| Board confirmation, promotion, withdrawal, graduation with Honours | IMPLEMENTED | `college.confirm_decisions` | |
| Senate appeal after the Final | IMPLEMENTED | `college.grant_appeal` | |
| Reconciliation "ready for Senate" | IMPLEMENTED (read) | `:699-754` | no act "crosses" to Senate; nothing is sent to the University results chain |
| 100 Level College rule | IMPLEMENTED (read-only advice) | `college.decide_100` | no withdrawal act |
| CA items during the year | IMPLEMENTED | `:841-889` | not combined into the subject CA automatically |
| Carry-over table (`college.carry_over`) | CONFIGURED BUT UNUSED | no writer | decisions keep `carry_overs` text only |
| Projects (`college.project`), department units | CONFIGURED BUT UNUSED | no API | |
| Student Payment Report | IMPLEMENTED | `:1003-1095`; `PaymentReport.tsx` | |
| Provost dashboard endpoint | CONFIGURED BUT UNUSED (backend without UI) | `ProvostController.java`; no frontend call | the College dashboard uses `/college/dashboard` |
| MBBS Coordinator level binding | IMPLEMENTED | `assertLevel`, `OfficeScope.actingLevel` | |
| Notifications to students (decision, resit, graduation) | NOT IMPLEMENTED | no queue_notice | |
| Editing exam/subject/posting configuration | NOT IMPLEMENTED | read-only endpoints | migrations only |

## 14 Common problems
- "The N Level year … has not reached its final semester": date the level's semesters on the College calendar; results open once the last semester has started.
- "the N Level fees for {session} semester k are not yet cleared": the student pays school fees for that semester; "the whole session paid at once clears every semester".
- "the student has a College year still open": the Board must confirm the previous year's decisions.
- "That student has no N Level year in {session}": open it with **Open the year for a student** (paper registration/transfer); the student must be at that level on the register.
- "The MBBS Coordinator acts at N Level; this is M Level": the grant is bound to a level; the College Secretary works other levels.
- Score-sheet upload "left out" rows: fix the flags (not in cohort, over range, attendance missing where the exam has a minimum, clinical missing where the subject has one).
- "no appeal stands for this student": the last confirmed 600-level decision must be APPEAL.

## 15 Glossary
Cohort (the students whose year at a level began in a session); Year / enrolment (OPEN, RESIT, CLOSED; REGULAR, REPEAT, APPEAL); CPE / PE1–PE4; Barred (attendance below the examination's minimum); Distinction (subject total ≥ 70); MBBS Honours (a distinction in each of PE1–PE4); Provisional / Confirmed decision; Reconciliation (every registered candidate resulted and decided); Posting, Block, Rotation group, Tier; Logbook requirement (procedure × minimum count, OBSERVE/PERFORM/EITHER); Mandatory event (e.g. the Wednesday Grand Round); Year reached final (the last dated semester has started).

---

## Cross-cutting findings for the manuals
1. Publication does not notify students; the only results-related notices are "Your result query {ref} is answered" and the held-script notice.
2. The reminder/escalation buttons for late score sheets return 202 "The notification module is not on the portal yet; nothing was sent."
3. A CORRECTED result query has no correction path: a PUBLISHED sheet cannot be returned or amended (`return_sheet` refuses PUBLISHED; `scores` refuses a sheet not at ENTRY); the Chain screen's "Raise an amendment" button has no handler.
4. The office-per-stage rule of the approval chain is enforced only in the UI (`Sheets.DESK` → `mayAct`); the database enforces completeness, the minute, and "not the same person twice".
5. Held scripts can be held on any sheet by any lecturer (no ownership check) and are released into a sheet at any stage.
6. Grades are computed under the scheme in force at `current_date`, not at publication; only one scheme (SEN/2015/44) is seeded. The classification table has no band under 1.00, so the class of standing is blank for a CGPA under 1.0. The statement PDF hard-codes the grading key.
7. The CBT module is a question bank only; no test exists.
8. The College's score-sheet exports carry the letterhead "Moshood Abiola University of Science and Technology, Abeokuta" (`fe/app/college/scoresheets/ScoreSheets.tsx:18`).
9. `/api/v1/provost/dashboard` has no frontend; the Provost's home is the College dashboard.
10. `/api/v1/verify/**` is public and unthrottled; the results statement is protected by the 12-hex check code only.
