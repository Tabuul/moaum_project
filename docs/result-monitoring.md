# Result monitoring for the Director of ICT (V700)

The University's master prompt of 29 October 2026: one place where the Director of ICT sees every uploaded and processed result by
faculty, department, programme, level, session and semester; opens the result records and the broadsheet; finds what is wrong; and has
it corrected through the University's own correction workflow — never a second result system.

## What was already there, and is reused

- **Score sheets and their chain.** One sheet per class and sitting (ENTRY → VERIFICATION → Departmental Board → Faculty scrutiny →
  Faculty compilation → Faculty Board → Exams & Records → Senate → PUBLISHED). Every mark is kept as a version (`assessment.score`).
- **A course's result.** `assessment.course_final(student, offering)` reads it: a published special or re-sit stands over the Main.
- **The broadsheet.** Built from the approved registrations and `course_final` (`ResultsRepository.broadsheet`), on the shared scope
  bar. The Director of ICT already reads it (`ResultsController.READERS`).
- **Amendments (V358).** A published mark is corrected by an amendment that the course's desk of entry raises (the lecturer, the
  Programme Examinations Officer, the GST or EPS office). It is approved desk by desk and applied on the Senate minute as a new
  version of the mark; the original is kept.
- **The exports.** `brandedXlsx` and `brandedPrint` put the University's logo, name, title, filters, date and serial on the page. S/N
  comes first, numbered across pages and restarting with each filter; Matric and JAMB numbers stay text. Every export is written to
  `platform.export_log`.

## What V700 adds

Every read below goes over the same tables. No result is copied anywhere.

| Function | What it gives |
|---|---|
| `assessment.result_records(session, semester, faculty, department, programme, level, course)` | every course on an approved registration in scope — the rows the broadsheet is made of — with the main sitting's sheet, its stage (`NO_SHEET` when there is none) and whether the student has a mark on it |
| `assessment.result_state(stage, has_score)` | AWAITING (no sheet, or no mark while at entry — **no result, never a fail**), MISSING (a sheet past entry without the student's mark), ENTRY, VERIFICATION, APPROVAL (Departmental Board to Senate), PUBLISHED |
| `assessment.result_monitor_groups(session, semester, faculty, department)` | the records counted by faculty, by department of a faculty, or by programme and level of a department |
| `assessment.result_exceptions(session, semester, faculty, department, programme, level)` | what needs a look (below), each with the record it is about |
| `assessment.result_uploads(session, semester)` | the uploads of marks: each score sheet's (`assessment.sheet_upload`) and each load of the old portal's past results |

**Exceptions.**

| Kind | What it is |
|---|---|
| RESULT_WITHOUT_REGISTRATION | a mark for a course the student has no approved registration of |
| DUPLICATE_RESULT | marks for one course on two classes (its BSU-/MOAU- twin, or a second course under the code) |
| MISSING_SCORE | a registered student with no mark on a sheet already past entry |
| INVALID_SCORE | a mark entered on the portal above the course's CA, or its examination, maximum (the course's split changed after) |
| COURSE_ABOVE_LEVEL | a course of a higher level than the registration, with a mark |
| COURSE_OTHER_SEMESTER | a course taught in the other semester, with a mark in this one |
| COURSE_OUTSIDE_PROGRAMME | a course with a mark that the programme neither registered under its structure nor binds, not general, and not taken off its broadsheet (V624) |
| PASSED_STILL_CARRIED | a carry-over registered for a course already passed on a published result |
| RESULT_HELD_NO_STUDENT | an uploaded result held for a number no student holds (University-wide only) |

On the live-shaped copy of 28 October 2026 (rolled back), 2024/2025 first semester (the old portal's loads) shows:

- MISSING_SCORE 49,841: courses registered on published sheets the old portal gave no mark for;
- DUPLICATE_RESULT 2,172: marks under both a BSU- code and the plain code (BSU-CMS 101 and CMS 101);
- COURSE_OUTSIDE_PROGRAMME 353;
- COURSE_OTHER_SEMESTER 170.

2025/2026 first semester shows MISSING_SCORE 192 and COURSE_OUTSIDE_PROGRAMME 4. University-wide, the heaviest semester takes about
3 s; one programme and level well under a second.

**Correction requests** (`assessment.correction_request`). The Director of ICT (or super) asks the course's desk of entry to correct one
student's result on a sheet (`assessment.request_correction`). The request carries:

- the result as it stood (version, CA, examination, total, grade, outcome, stage);
- the reason: Lecturer upload error, Data entry error, Incorrect score, Missing score, Wrong student, Wrong course, Wrong session,
  Wrong semester, Wrong programme, Approved academic correction, Migration correction, or Other;
- a note of ten characters or more;
- the marks proposed. An incorrect or missing score must name them; a wrong student, course, session, semester or programme is put
  right by the desk removing or moving the result.

Refusals:

- CRQ_OFFICE — any other office;
- CRQ_NOTE — a note under ten characters;
- CRQ_KIND — not one of the reasons;
- CRQ_NOT_ON_SHEET — the student has neither a mark nor a registration on the sheet;
- CRQ_MARKS — marks missing or out of range;
- CRQ_SAME — the marks on record;
- CRQ_OPEN — one at a time per result.

The request then follows the desks' own workflow:

| What happens | The request |
|---|---|
| a new version of the mark is written (on the sheet at entry, or an amendment applied) | RESOLVED, with the version |
| the desk raises an amendment for the result | IN_AMENDMENT, following it |
| the amendment is refused | DECLINED, with the refusal |
| the amendment is withdrawn | OPEN again |
| the desk of entry declines it (`assessment.decline_correction_request`, a reason) | DECLINED |
| the Director of ICT withdraws it while open (`assessment.withdraw_correction_request`) | WITHDRAWN |

Nothing in V700 writes a mark: separation of duties is kept, and every version stays.

## API (`ResultMonitorController`)

Readers (MONITORS): the Director of ICT, super, the Academic Office, the Registrar, the Deputy Registrar, Exams & Records — each
held to its own scope (`OfficeScope.bound`).

| Endpoint | |
|---|---|
| GET `/api/v1/results/monitor/overview?session&sem&fac&dept` | the counts by faculty, department, or programme and level; totals, exceptions, corrections, broadsheets with published results |
| GET `/api/v1/results/monitor/records?session&sem&fac&dept&prog&level&course&state&q&page&size` | the summary (students counted once, apart from course results) and a page of records, each with `course_final`'s CA, exam, total, grade, grade point, quality point, the stage, the lecturer, the first and last entry, versions, and any open request or amendment |
| GET `/api/v1/results/monitor/records/{offering}/{student}` | one result: the student, the course, the registration, the result, each sitting, every version (who, office, when, why), the chain, the amendments, the requests |
| GET `/api/v1/results/monitor/exceptions?…&kind&q&page&size` | the counts by kind and a page of exceptions |
| GET `/api/v1/results/monitor/uploads?session&sem&kind&page&size` | the upload history |
| GET `/api/v1/results/monitor/corrections?session&sem&fac&dept&state=OPEN\|CLOSED\|ALL` | the requests and the amendments |
| POST `/api/v1/results/monitor/corrections`, POST `…/corrections/{id}/withdraw` | the Director of ICT and super (REQUESTERS) |
| GET `/api/v1/results/sheets/{id}/correction-requests` | a sheet's requests, for every office that reads the sheet |
| POST `/api/v1/results/correction-requests/{id}/decline` | the sheet's desk of entry, within its reach |

Runs of the viewer and the exceptions (page 1), and each result opened, are written to `reporting.query_log` (RESULT_VIEWER,
RESULT_EXCEPTIONS, RESULT_DETAIL). Exports log themselves.

## Screens

- **Director of ICT → Results Monitoring.** Result Viewer (`/results/monitor`), Result Broadsheet (the existing broadsheet), Result
  Corrections, Result Upload History, Result Exceptions, Result Pipeline. Super's Academic group carries the same.
- **Result Viewer.**
  - Without a programme, an overview: by faculty, then department, then programme and level. Each row opens the next; View results
    lists the scope's records anyway.
  - With one, summary cards, the state filters, a search (name, matric, JAMB, course, lecturer), the records (Name A–Z), Excel and PDF
    of every record in the filter, and View, which opens the result.
  - The result shows the student, the course, the result, the workflow, the history of the mark, the amendments and the requests;
    Request a correction shows the result as it stands beside the one proposed.
- **The desk of entry.** The sheet (`/results/sheets/{id}`) and its chain show the open requests. On a published sheet, Raise the
  amendment fills the amendment's form from the request; on either, Decline asks for the reason.
- **The Director of ICT's dashboard.** Result monitoring for the current semester: results uploaded, pending verification, pending
  approval, published, missing, with exceptions, corrections pending and completed, not available yet, and the results by faculty.
  Each figure opens its list.

## The follow-ups (29 October 2026, V702)

The University's word: "d 1-7", on the follow-ups V700 left.

### Duplicate results, resolved by the Registry's side

A student with marks for one course on two classes in a semester: its BSU-/MOAU- twin, or a second course under the code. On the
copy of 28 October 2026 there were 2,172 in 2024/2025's first semester, such as BSU-CMS 101 beside CMS 101.

- **Who decides** (the University's choice): Exams & Records, the Registrar, the Deputy Registrar, the Academic Office, the Director
  of ICT, the Database Operators, and super (DUP_OFFICE otherwise).
- **What a decision does** (`assessment.resolve_duplicate(student, keep, drop, reason)`):
  - the class kept stands;
  - the other is withdrawn from the student's registration (entry WITHDRAWN), so the transcript, the CGPA and the broadsheet count
    the course once;
  - its mark stays on its sheet, as history;
  - the decision is written down (`assessment.duplicate_resolution`, audited) with the reason (ten characters or more).
- **Refusals:** DUP_NOT_SAME (not one course in one semester), DUP_NOT_DUPLICATE (no mark on both), DUP_RESOLVED (a class already
  withdrawn for the student).
- **A course on three classes** takes a decision for each class withdrawn.
- **Putting it back** (`assessment.undo_duplicate_resolution`) restores the withdrawn class's registration as it stood. The decision
  is kept, with who put it back and why.
- **The list and the exceptions.** `assessment.result_duplicates` lists each class with its result, the registration and the
  decision. The exceptions no longer count a resolved pair, nor the withdrawn class's mark as a result without a registration.

### Correction requests told

The course's lecturer is told of a request by email, SMS and the portal (template CORRECTION_REQUESTED: the student, the course,
the reason, the result as it stands and the one asked for). The Director of ICT who asked is told when it is corrected or declined
(CORRECTION_CLOSED). The rest of the desk of entry sees the request on the sheet, and on its own list: Corrections asked of your
sheets, on the score sheets page and the results desk (GET `/api/v1/results/correction-requests/mine`).

### Missing scores, by department, and late results by upload

- The exceptions, and a result's details, are read by the Heads of Department, the Deans, the Departmental, Faculty and Programme
  Examinations Officers, and the Faculty Officers, each within its own scope. Result Exceptions is in their menus. Missing score,
  narrowed to a department, exports to Excel or PDF for the department to chase.
- A published sheet's candidates with no mark get their late results from one upload (POST
  `/api/v1/results/sheets/{id}/late-results`, `assessment.raise_late_results`). The desk of entry downloads the template listing
  them, fills in the CA and exam (or an outcome), and uploads it with the reason.
- Each row becomes a late result (V422) through the chain to Senate, as one raised by hand. Each row is answered:
  - RAISED, with its amendment;
  - NOT_LATE: a mark already (corrected by an amendment), or not on the roll;
  - REPEATED;
  - REFUSED, with the chain's reason.
- The whole upload is refused when the desk is not the desk of entry, the sheet is not published (LATE_NOT_PUBLISHED), or there is no
  reason (LATE_REASON). At most 2,000 rows.

### API added

| Endpoint | |
|---|---|
| GET `/api/v1/results/monitor/duplicates?session&sem&fac&dept&prog&state=OPEN\|RESOLVED\|ALL&q&page&size` | each student's course with its classes; open and resolved counted (RESOLVERS) |
| POST `/api/v1/results/monitor/duplicates/resolve`, POST `…/duplicates/{id}/undo` | RESOLVERS, within their scope |
| GET `/api/v1/results/correction-requests/mine` | the open requests on the sheets this desk of entry reaches |
| POST `/api/v1/results/sheets/{id}/late-results` | the sheet's desk of entry |
| GET `/api/v1/finance/department-change-fees?session` | the held students' fees, for the Bursary; removed with the department-change hold by V730 (see student-level-management.md) |

The exceptions and a result's details (GET `…/monitor/exceptions`, `…/monitor/records/{offering}/{student}`) are read by
EXCEPTION_READERS: the MONITORS, the Database Operators, and the department and faculty desks.

### Screens added

- **Duplicate Results** (`/results/monitor/duplicates`). In the menus of the Director of ICT, Exams & Records, the Registrar, the
  Deputy Registrar, the Academic Office, the Database Operators and super. Each student's course is listed with its classes, the
  result on each and the registration, and offers Keep this one (with the reason), Put back, View and Excel. Same course twice in
  the exceptions links here.
- **The amendments panel on a published sheet:** Upload late results.
- **The score sheets page and the results desk:** Corrections asked of your sheets.

### Also in V702

- **COS 203 unbound from B.Sc. Computer Science.** It sits beside CSC 203; both are "Discrete Structures", and the CCMAS structure
  has CSC 203.
- **Admission numbers no student already holds.** Sessions a century apart (a test's 2384/2385 and 2084/2085) each counted their own
  series under the same two digits. Both issued MOAUM/ADM/84/000001: AdmissionLifecycleIT's duplicate key in CI.
  `people.next_admission_no` passes over a number already held. Intake and the postgraduate admission use it.

## Tests

| Test | What it covers |
|---|---|
| `check.sql` V700 | made-up students: the records and their states, the counts by programme and level, every kind of exception, a held result, a sheet's upload; a correction refused to the Registry, once at a time, never the marks on record, an incorrect score with no marks refused; followed into its amendment and resolved by the new version, declined by the desk (not the Director of ICT), withdrawn once, declined with a refused amendment |
| `ResultMonitorIT` | the overview, the records filtered and searched, one result, the exceptions, who reads (Registry yes, lecturer and Bursary no), the request (Registry refused, a second refused CRQ_OPEN), the Examinations Officer seeing and declining it (the Director of ICT not), a withdrawal, the corrections list, the upload history |
| `lib/result-monitor.test.ts` | the words, the request's rules before it is sent, the query string, the export row |
| `check.sql` V702 | a duplicate resolved by Exams & Records (refused to the Bursary, without a reason, across courses, without both marks, twice): the twin withdrawn, its mark kept, the exceptions and the transcript passing over it; put back by the Registry; a correction told to the lecturer and its decline to the Director of ICT; late results uploaded — raised, a mark already, not on the roll, repeated, refused (no number, over the CA), the whole refused to the Bursary, without a reason and on a sheet at entry; an admission number held passed over; COS 203 not bound |
| `ResultMonitorIT` (V702) | the duplicates listed, resolved by Exams & Records (the Bursary refused, twice refused DUP_RESOLVED) and put back by the Registry; late results uploaded by the Examinations Officer (the Bursary refused); the Officer's open requests found, a lecturer's not; the exceptions read by the Head of Department |
| `lib/result-monitor.test.ts` (V702) | the duplicate's choice and what it withdraws, the export rows; the late results read from a file |
