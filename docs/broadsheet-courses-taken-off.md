# A course taken off a programme's broadsheet (V624, 21 October 2026)

**Where:** Results → Broadsheet (`/results/broadsheet`), for a programme, level, session and semester.

## Why

A broadsheet has a column for every course any student of the class has on an approved registration. On Environmental Management
and Toxicology's 100 Level sheet (Chemistry) that brought in a Linguistics and Religion load (LIN 101/103/105, BSU-LIN 107–113,
REL 105, BSU-REL 103) and a Political Science load (POL 201/203/205, BSU-POL 207/209/211, ENT 211) the department does not offer —
a few students' registrations: a registration made in error, or a student placed in the wrong programme. The University asked for
those courses to come off the broadsheet.

No rule can take such a course off by itself: on the live data many classes have courses outside their programme's structure that
a few of the class rightly take — an Education student's teaching subject (14 of 61 Human Kinetics (Ed) 100 Level students take
CHM 101), a borrowed elective. So the department decides, course by course.

## On the screen

- **Courses outside the programme** are flagged under the summary: a course no student registered under the programme's basis
  (V620's `registration.entry.basis`), not bound to the programme at any level (its BSU-/MOAU- twin counts) and not a general
  course (GST, EPS). Each has **Take off this broadsheet**; any other column can be taken off from **Take another course off this
  broadsheet**. A reason is asked for.
- **A course taken off** leaves the sheet before anything is counted — its column, the semester figures (CUR, CUE, WGP, GPA), the
  remark (CO:, NR:), the coverage — and is listed under the summary with the students who carry it, the reason, who took it off
  and when, and **Put back**. A student whose only courses were taken off is no longer on the sheet; they are named in that list.
- The students' registrations and results are **not** changed: their result page, transcript and CGPA (the sheet's cumulative
  columns) still count the course. The record is put right elsewhere — a student in the wrong programme under **Programme Swap**,
  a course registered in error dropped from the registration.

Who: the Head of Department, the Examinations Officers (programme and faculty), the Academic Office, the Registrar, the Deputy
Registrar and super — each within the programmes of their own scope.

## API

- `GET /api/v1/results/broadsheet` gains `outside` (the courses taken off, with `students`, `reason`, `omittedBy`, `omittedAt`) and
  each course's `inProgramme`.
- `POST /api/v1/results/broadsheet/omissions` `{prog, level, session, sem, stream, course, reason}` — refused without a reason
  (`BROADSHEET_OMIT_REASON`) or for a course not on the sheet (`BROADSHEET_COURSE_NOT_ON_SHEET`).
- `POST /api/v1/results/broadsheet/omissions/restore` `{prog, level, session, sem, stream, course}` — `BROADSHEET_COURSE_NOT_OMITTED`
  when it was not off.
- Stored in `assessment.broadsheet_omission` (one row per sheet and course, a reason of three letters or more, on the audit spine).

## Tests

check.sql V624 (the table's rules and its audit trigger); `ResultPipelineIT` (refused without a reason, for a course off the sheet
and for a lecturer; taken off — no column, listed with both students and the reason; put back; nothing to put back).
