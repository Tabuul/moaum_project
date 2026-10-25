# Course registration report and examination attendance (V652)

The University's master prompt of 25 October 2026, "Central course registration, GST, EPS & examination attendance reporting engine".
The portal already had most of what it asks for:

- the statistics and payment-against-registration figures: the Master University Report (V650);
- the paid and registered students for the examination: Examination Readiness (V640);
- the examination card (V567) and the GST & EPS permit (V589).

This round adds the four pieces it did not have:

1. the course registration report (one row a student and course);
2. the examination attendance sheet, with its manual / late registration rows and its versions;
3. the attendance recorded after the paper, with handwritten rows held for verification;
4. the reconciliation.

Nothing here creates a student, changes a registration or touches a result.

## 1. The course registration report

`reporting.course_registration_rows(session, semester, filters)` gives one row a student and course on a registration of the session.

**What a row carries:**
- the student and where they sit;
- the registration and its status;
- the course by its own key, with the code shown (`catalogue.shown_code`, V646), its units and its type;
- the category:
  - GST and EPS, by the course's `general_office`;
  - DEPARTMENTAL: the student's own department;
  - FACULTY: another department of the student's faculty;
  - OTHER: a department of another faculty;
- the curriculum (BMAS or CCMAS) and carry-over;
- whether the student holds what the paper asks: the GST & EPS permit for a GST or EPS course, the examination card for any other.

Dropped and withdrawn courses are left out unless asked for.

**Filters:**
- faculty, department, programme and level;
- course (by its key or the code shown) and class (`offering`);
- category, including CARRY_OVER and OTHER_COURSES (every course that is not GST or EPS, as the prompt's "other course registration report" asks);
- the GST or EPS office's own courses, and curriculum;
- sex (M, F, or U for not stated) and registration status;
- card or permit held;
- the registration dates and a search.

**Counts:**
- `reporting.course_registration_summary` counts the rows once, with GROUPING SETS, into the whole, category, faculty, department, programme, level, sex and course. A faculty is therefore the sum of its departments by construction.
- `reporting.course_registration_courses` gives each course its registered students, sex, carry-overs, card or permit, its latest attendance sheet, and the present, absent, manual present and pending figures.

**The API: `CourseRegistrationReportController`, at `/api/v1/reports/course-registrations`.**
- `GET`: a page of rows, each with whether the school fees are paid by the examination card's own rule.
- `/summary` and `/courses`.
- `/export`: every row, up to 50,000, under a DBO/REG reference on the official report register (`reporting.issue_report('REG', …)`).

**Who reads it, held by `OfficeScope`:**
- a Head of Department or a department Examinations Officer: their department;
- a programme Examinations Officer: their programme;
- the Faculty Examinations Officer, a Dean or a Faculty Officer: their faculty;
- the GST and EPS offices: their own courses only (the API sets the filter);
- Exams and Records, the Academic Office, the Registry, the VC, the DVC, ICT and the Database Operator: the University.

A filter narrows the scope and never widens it.

**The screen: Course Registration Report (`/reports/course-registrations`).**

It has the scope bar, the filters and the tiles, then three views:
- **Course by course:** tick courses to generate attendance sheets;
- **Students and courses:** a page at a time, with Excel and PDF under the reference;
- **Summary:** by faculty, department, programme, level, sex and category.

It is on the menus of every reading office, next to Examination Readiness. The GST and EPS offices find it next to Examination Permits.

## 2. The attendance sheet

`assessment.issue_attendance_sheet(class, manual lines, reason, faculty, department, programme)` issues the sheet of a course's class within a scope.

**What a sheet lists and keeps:**
- every student with the course on a submitted, approved or locked registration (`assessment.attendance_list`), with the card or permit marked;
- the examination date, time and venue from `assessment.exam_timetable`, where the timetable states them;
- the manual lines asked for, 0 to 60. The screen offers 5, 10, 15, 20, 25 or a custom number.

The list is kept as it was printed (`assessment.exam_attendance_sheet.list`).

**The reference:** `ATT/<code>/<year>/<nnnnn>/V<k>`.

**Versions:** a sheet issued again for the same course and scope is the next version, V2, V3. It needs a reason (`ATTENDANCE_REISSUE_REASON`). The earlier versions are kept exactly as printed, and an earlier version's PDF prints SUPERSEDED with the latest named.

**The API: `ExamAttendanceController`, at `/api/v1/exams/attendance`.**

`POST /sheets` issues one sheet a course, or one a faculty, department or programme of each course (`split`). The scope is held to the office's bound and made whole, so a programme names its department and faculty. A request is refused before anything is written when a sheet already stands and no reason is given.

**The PDF (`/exams/attendance/sheets/pdf?ref=…`, `lib/exam-attendance-pdf`).** It is A4 landscape, with:
- the University's letterhead;
- ATTENDANCE SHEET REFERENCE in a band at the top of every page;
- the facts: faculty, department, programme, course code, title and unit, level, session, semester, examination date, time and venue, a line for the examiner or invigilator, the students listed;
- the list: S/N, matriculation number, name, programme, level (C/O for a carry-over), card or permit (NO CARD or NO PERMIT in red), a large signature column, attendance status and invigilator remarks;
- the table header repeated on every page;
- the MANUAL / LATE REGISTRATION ATTENDANCE section with the University's wording and blank rows tall enough for handwriting: S/N, name written by student, matric / JAMB number, programme, level, signature, reason / remark, verified;
- the totals and the INVIGILATOR SIGNATURE, DATE, EXAM OFFICER and SIGNATURE lines.

"Page X of Y" counts each sheet's own pages. Several sheets print as one document.

## 3. Attendance after the paper

`assessment.exam_attendance` holds one record a student and course. The status is PRESENT, ABSENT, LATE, MANUAL_PRESENT, EXCUSED or INVALID_ATTENDANCE, and the source is the list or a handwritten row. Each record keeps the sheet, the invigilator, who recorded it and who verified it.

**Marking the list:** `assessment.record_attendance` takes students registered for the class or printed on one of its sheets. Anyone else is refused (`ATTENDANCE_NOT_ON_LIST`) and is entered as a handwritten row instead.

**Handwritten rows:** `assessment.manual_attendance` finds the student by the number written, through `people.resolve_student` (V647: matriculation, admission, JAMB or application number).
- **Found:** the attendance is MANUAL_PRESENT. A student already marked present on the list stays so.
- **Not found, or the number names several students:** the row is held in `assessment.exam_attendance_pending`, pending verification.

**Pending rows:** `assessment.decide_manual_attendance` matches a pending row to its student (the attendance is then verified) or finds it invalid. An invalid row needs a note, and a row is decided once.

**Who keeps attendance:** the Examinations Officers, the Faculty Examinations Officer, Exams and Records, the Head of Department, the GST and EPS offices (their own courses), the Academic Office and the Registry. The database checks this too (`assessment.attendance_office_check`). The API holds each office to its scope: a student of another department is refused (`SCOPE_STUDENT`), whether by the list or by a handwritten number.

## 4. The reconciliation

`assessment.attendance_reconciliation(class, scope)` reads every student who is registered, printed on the latest sheet of the scope, or recorded. It writes nothing. Each gets a finding:

| Finding | Meaning |
|---|---|
| OK | registered, listed and marked |
| NOT_MARKED | on the list, no attendance recorded |
| REGISTERED_NOT_ON_LIST | registered after the sheet; a new version lists them |
| ON_LIST_NOT_REGISTERED | the course dropped, or the registration withdrawn, since |
| PRESENT_NOT_REGISTERED | marked present, no registration now and not on the latest sheet |
| PRESENT_NOT_ELIGIBLE | sat without the card, or without the permit for a general course |
| MANUAL_NOT_REGISTERED | wrote their name on the sheet, with no registration for the course |

**The screen: Examination Attendance (`/exams/attendance`).** It shows the courses of the scope first, then a class with:
- the totals the prompt asks for: registered, eligible, on the sheet, present, absent, manual, pending verification;
- Mark the list (with Unmarked as absent);
- Handwritten rows;
- Pending verification (Match by matriculation number, or Invalid with a note);
- Reconciliation, filtered by finding, with Excel;
- Sheets, every version, with a new version issued with its reason.

## Checks

- **check.sql V652:** four made-up students of two made-up programmes in a session of the check's own. It covers:
  - the report's dimensions and filters;
  - the sheet and its card marks, the refused re-issue and V2 with V1 kept;
  - the list marked, the GST office refused a departmental course;
  - handwritten rows matched and pending, an invalid note required, a row decided once;
  - the reconciliation before and after a course is dropped;
  - the GST office's sheet by faculty, and an office that keeps no attendance refused.
- **ExamAttendanceIT:** the same through the API, with each office's scope.
- **`lib/course-registration-report.test.ts` and `lib/exam-attendance.test.ts`:** the filters, the marks sent, and the PDF (landscape, the reference on every page, the header repeated, S/N running on, the manual rows blank, the signatures, superseded, each sheet's own page numbers).
