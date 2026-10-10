# CCE — the Centre for Continuing Education

CCE is a **regular, part-time, six-year undergraduate route** inside the University Portal. A CCE student is an ordinary
`people.student` — same programme catalogue, same finance, registration, results, documents and sign-in — distinguished by
three facts on the record and one rule of the calendar:

```
CCE = admission route CCE (entry_mode) + study mode PART_TIME + the Centre for Continuing Education (unit CCE)
      + the CCE session, one session behind the undergraduate session by default (configurable)
```

It is not JUPEB, not postgraduate, not a short course, and it has no portal of its own.

---

## A. Architecture assessment — what the portal already has, and what CCE does with it

| # | Area | What exists | What CCE does |
|---|------|-------------|---------------|
| 1 | **Admission** | `admissions.candidate` → `applicant_account` → `application` (APP/yy/nnnnnn) → fee references → submission → decision (`OFFERED / WAITING / NOT_OFFERED`) released → status checking → undertaking + acceptance fee → online screening → `people.intake_one` puts the candidate on the register (admission number). The decision path is built around Post-UTME screening (score released before a decision; a checking window and fee before the status is read). | **Reused end to end.** A CCE candidate is an `admissions.candidate` with `entry_mode = 'CCE'`, linked to the CCE list row it came from. The Post-UTME-only steps (screening score, checking fee/window) do not apply to a CCE application; in their place the Centre's own review (below) produces the same `decision` and the same release. |
| 2 | **JAMB import** | `caps_batch` / `caps_row` (the CAPS list): Academic Office loads JAMB's list; a candidate registers only if their number is on it (`applicant_lookup`, `register_applicant`). Reconciliation blocks ghost admissions. | The CCE list follows the same principle (only a listed number may apply) but carries different columns (date of birth, phone, email, programme, O'Level notes) and needs NEW / EXISTING / UPDATED / DUPLICATE / REQUIRES REVIEW / INVALID reconciliation, so it gets its own staging tables (`admissions.cce_batch`, `cce_batch_row`) and pool (`admissions.cce_candidate`). The UTME CAPS reconciliation is left untouched. |
| 3 | **Applicant** | Sign-in by application number, email or JAMB number (session-independent), JWT office `applicant`; the applicant portal (`/applicant/*`); O'Level rows per application (`screening_olevel`: WAEC/NECO/NABTEB/OTHER), documents with review (`application_document`: PENDING/ACCEPTED/REJECTED), passport and date of birth as attachments. | Reused: a CCE applicant signs in like any applicant; the shell shows a CCE menu (no Post-UTME items). The application form uses the same O'Level rows (with a sitting number, one or two sittings) and the same documents. |
| 4 | **Programme** | `ref.programme` (code `C#####`, `UNDER GRADUATE` / `POST GRADUATE`, `duration_years`, `final_level`). | **No duplicate programmes.** A CCE offering of a programme is a row in `ref.programme_route` (programme × route): duration (6 years by default, from the route), final level, active. |
| 5 | **Study mode** | None. `people.enrolment.mode` exists but is unused for this; `SANDWICH` is an entry mode. | New `people.student.study_mode` (`FULL_TIME` default, `PART_TIME`); a CCE student is always `PART_TIME`. |
| 6 | **Admission route** | `people.student.entry_mode` (UTME, DIRECT_ENTRY, TRANSFER, POSTGRADUATE, JUPEB, SANDWICH); fee lines match on it. | `CCE` added as an entry mode. Changing a student's route or study mode is refused except to the Academic Office / Registry with a reason. |
| 7 | **Academic session** | `policy.academic_session` (one CURRENT); `policy.university_current_session()`, `intake_session()`, `application_session(type)` (V378); PG has its own current session, JUPEB its own (V351); `people.academic_context(student)` gives the session a student stands in. Session arithmetic by name (`session_after`, `sessions_elapsed`), skipping cancelled sessions. | **No second session system.** A route row (`policy.study_route`, `CCE`) carries the offset (−1) and an optional override set by the Academic Office. `policy.route_session('CCE')` = the override, else the undergraduate session shifted by the offset — so when undergraduate moves to 2027/2028, CCE moves to 2026/2027 by itself. `policy.resolve_session(route, study_mode, programme)` is the one resolver; `people.academic_context` uses it for CCE students. Nothing is moved between sessions. |
| 8 | **Course registration** | `registration.student_menu(student, session, semester)` over `catalogue.course_offer` (programme × level) and `catalogue.offering` (course × session × semester, unique). The session is chosen by the caller. | **Phase 2.** CCE studies in a session undergraduates have already finished, so CCE must have its own offerings (a stream on `catalogue.offering`), or CCE scores would land on undergraduate score sheets already approved for that session. Until phase 2, course registration refuses a CCE student with that reason. |
| 9 | **Finance** | `finance.fee_schedule` lines by session, level, entry mode, faculty, programme, fee group, semester, indigene; applicant fees per session (`admissions.applicant_fee`); one payment gateway and reference model. | Applicant fees for CCE stated separately (`admissions.route_fee`: application, portal charge, acceptance), used by the existing fee references. School fees (phase 2): lines with entry mode `CCE`; generic lines stop applying to CCE students so full-time fees never reach them. |
| 10 | **Student activation** | `people.intake_one(candidate)` — admission number, programme, entry session; screening answers become biodata. | Reused; it now keeps `entry_mode = 'CCE'`, sets `PART_TIME`, and the entry session is the CCE session the candidate was admitted for. |
| 11 | **Attendance** | Two: `registration.attendance` (per offering, present/absent) for courses; `attendance.register/mark` (PRESENT/ABSENT/LATE/EXCUSED, slots, locking) for JUPEB only. | Phase 2: the register/mark model opened to course offerings, used by CCE evening classes. |
| 12 | **Results** | Score sheets per offering and exam sitting, the approval chain, publication, amendments, carryovers. | Phase 2: CCE offerings give CCE sheets of their own in the CCE session; nothing else changes. |
| 13 | **Matriculation** | Formats (`people.matric_format`), series (`people.matric_series`, transaction-safe numbering), batches. | Phase 3: a CCE series/format configured, never hard-coded. |
| 14 | **RBAC** | Offices (`ref.office`, authority `OFFICE_<code>`), scope by office (`OfficeScope`), every rule enforced in the database function or the controller. | New office **`cce` — Centre for Continuing Education** (scope: CCE records only). The prompt's permissions map onto offices: see C. |
| 15 | **Documents** | `credentials.issued` (signed, versioned letters), `lib/document` (PDF in the browser, branded). | The admission letter carries the route, study mode and the Centre. |
| 16 | **Academic Office dashboard** | Menu `academic` with Admissions, Students, Reports groups. | A **CCE Management** group added. |
| 17 | **Timetable** | `catalogue.class_slot` (weekday, start, end, venue, kind) per offering; no fixed periods. | Phase 2: evening slots on CCE offerings; the times are whatever the Centre enters. |
| 18 | **Reporting** | Admission pipeline counts, registers, cohort positions (`people.academic_position`, V331). | CCE counts on the CCE desk now; cohort positions use the route's duration and session in phase 2. |

---

## B. The design, decided

1. **One student record.** No CCE tables duplicate `people.student`, finance, results or attendance. The CCE tables are the
   list (what JAMB sent), the review of each application, the route and its session mapping, and the programme × route terms.
2. **The session is resolved, never assumed.** `policy.route_session(route)`; `policy.resolve_session(route, study_mode,
   programme)`; a CCE candidate is filed under the CCE session chosen at import (default: the current CCE session); the
   student's entry session is that session and stays so.
3. **The list decides who may apply.** A number not on the committed CCE list cannot open a CCE application; the candidate
   proves who they are with the JAMB number and the date of birth on the list (so a number read off a notice board is not
   enough), and only while the Academic Office has the CCE application window open.
4. **Separation of duties.** The Centre reviews, asks for documents or verification, and recommends; an application is
   approved by someone other than the officer who recommended it (the Director of the Centre or the Academic Office); the
   Academic Office publishes the admission list. Every step is a database function under the signed-in officer, written to
   the review's own history and the audit spine.
5. **Six years is configuration.** `policy.study_route.default_duration_years = 6`; a programme may differ in
   `ref.programme_route.duration_years`. Expected completion = the CCE entry session + duration − 1 (+ deferments), never the
   undergraduate session; six years elapsing graduates nobody.

---

## C. Offices and permissions

| Permission (as asked) | Who |
|---|---|
| VIEW_CCE_CANDIDATES, VIEW_CCE_APPLICATIONS, VIEW_CCE_ADMISSION_LIST, VIEW_CCE_STUDENTS, VIEW_CCE_REPORTS, VIEW_CCE_IMPORT_HISTORY, VIEW_CCE_AUDIT | `cce`, `academic`, `registrar`, `super` |
| UPLOAD_CCE_CANDIDATE_LIST, IMPORT_CCE_CANDIDATES | `academic`, `super` |
| MANAGE_CCE_SESSION, programme × route terms, the application window | `academic`, `super` |
| REVIEW_CCE_APPLICATIONS, VERIFY_CCE_DOCUMENTS, RECOMMEND_CCE_ADMISSION | `cce`, `super` |
| APPROVE_CCE_ADMISSION | `cce` or `academic` — never the officer who recommended it |
| PUBLISH_CCE_ADMISSION | `academic`, `super` |
| EXPORT_CCE_REPORTS | the viewers above |

A `cce` officer sees CCE candidates, applications and students only — not the University's other students.

---

## D. Phases

**Phase 1 — V379 (this change): the route, the session, the list and admission.**
Office `cce`; `study_mode` and route `CCE` on the student and the candidate; `policy.study_route` with the session offset
and override; `ref.programme_route`; `policy.session_before`, `route_session`, `resolve_session`; the CCE list (template,
upload, column reading, validation, preview, commit, history, error report, withdrawal of a listed candidate); the CCE
application window; CCE applicant registration (JAMB number + date of birth); the application (biodata, contact, O'Level in
one or two sittings, documents, passport, programme confirmation, review and submission, acknowledgement); the Centre's
review (UNDER_REVIEW, DOCUMENTS_PENDING, VERIFICATION_REQUIRED, RECOMMENDED, APPROVED, NOT_ADMITTED, REJECTED) and the
Academic Office's publication (ADMITTED); CCE applicant fees; acceptance; the admission letter; intake onto the register as
a CCE, part-time student in the CCE session; the student's dashboard session; the Academic Office's CCE Management menu and
the Centre's desk; counts by status.

**Phase 2a — V380 (built): the CCE session in operation.** A stream on course offerings (the Centre's classes in the CCE
session), course registration through the engine on the CCE calendar and windows, the CCE course load, the evening timetable,
attendance on the register/mark model, CCE school-fee lines in use. See F.

**Phase 2b — still to build.** Examinations and CBT eligibility in the CCE session (an examination session of the CCE
stream), score sheets and the result chain on CCE classes, cohort positions and expected graduation from the route, deferment
on the CCE calendar.

**Phase 3 — the rest of the life cycle.** CCE matriculation series, transcript lines (study mode, route), graduation and
spillover reports, full CCE reporting with the mapped undergraduate session, old-portal CCE students imported.

---

## E. Phase 1 as built (V379)

**Screens.** Academic Office → *CCE Management* (`/cce`, `/cce/upload`, `/cce/imports`, `/cce/candidates`, `/cce/applications`,
`/cce/processing`, `/cce/admission-list`, `/cce/students`, `/cce/programmes`, `/cce/session`, `/cce/reports`, `/cce/history`);
the Centre for Continuing Education's own menu over the same screens (office `cce`, demo account `demo.cce`); the Bursar's
*CCE Applicant Fees* (`/cce/fees`); the public `/cce/apply`; the CCE applicant's `/applicant/cce` (menu `cceapplicant`, no
Post-UTME items), with the ordinary *Admission Status*, *Accept Your Offer* and letter; the CCE window on the Director of ICT's
*Application Windows*; the student dashboard's CCE line (part-time, the Centre, the CCE session beside undergraduate's, the
expected completion).

**API.** `/api/v1/cce/*` (module `cce`, `CceDeskController`): `overview`, `session-mapping` (GET, PUT), `programmes` (GET, PUT
`/{code}`), `batches` (GET, POST preview; `/{id}`, `/{id}/rows`, `/{id}/report.csv`, `/{id}/commit`, `/{id}/discard`),
`candidates` (+ `/{id}/standing`), `applications` (+ `/{id}`, `/{id}/documents/{doc}`, `/{id}/documents/{doc}/review`,
`/{id}/act`), `admission-list`, `publish`, `students`, `history`, `fees` (GET, PUT). The applicant's: `POST
/api/v1/applicant/cce/lookup`, `POST /api/v1/applicant/cce/register` (public, limited per connection); `GET /me/cce`, `PUT
/me/cce/biodata`, `PUT /me/cce/olevel`, `POST /me/cce/programme`; documents, fee references and submission through the ordinary
`/me/documents`, `/me/fee-references`, `/me/submit`. `GET /api/v1/public/application-windows` carries `cce`.

**Codes.** `CCE_SESSION_OFFICE`, `CCE_SESSION_REASON`, `CCE_SESSION_UNKNOWN`, `CCE_PROGRAMME_OFFICE`,
`CCE_PROGRAMME_NOT_UNDERGRADUATE`, `CCE_OFFICE`, `CCE_LIST_ALREADY_LOADED`, `CCE_LIST_NOT_PREVIEW`, `CCE_LIST_ADMITTED`,
`CCE_NOT_LISTED`, `CCE_REGISTERED`, `CCE_PROGRAMME_CLOSED`, `APPLICATION_CLOSED`, `CCE_DATE_OF_BIRTH`, `CCE_OLEVEL_*`,
`CCE_NOT_EDITABLE`, `CCE_INCOMPLETE`, `CCE_DOCUMENTS_UNVERIFIED`, `CCE_OLEVEL_CREDIT`, `CCE_APPROVE_OWN`, `CCE_PUBLISHED`,
`CCE_NO_CHECKING_FEE`, `CCE_FEE_NOT_STATED`, `STUDENT_ROUTE_LOCKED`, `STUDENT_ROUTE_REASON`.

**Fees.** A CCE student is charged only the school-fee lines the Bursary states for entry mode `CCE`: a line naming no entry
mode is the full-time students' (the undergraduate fees of the very session CCE runs in included) and never reaches a CCE
student (`finance.charges_of_as`, `session_fee_total`, `due_for_semester`, `fee_stated`, `fee_sums`); the fee-structure upload
takes `CCE` as an entry mode; and a session before the portal's fee schedule began counts as "stated" only for students billed
on the old portal, never for a CCE student. The student's fees page lists only the sessions whose lines are theirs.

**Decided by default (say if the University wants otherwise).** The applicant proves who they are with the JAMB number *and*
the date of birth on the list (a number read off a notice board is not enough); a list row without a date of birth is not
loaded. The approving officer is never the recommending officer; the Director of the Centre or the Academic Office approves;
the Academic Office publishes. A CCE applicant pays no admission checking fee and needs no checking window: the published
outcome is read at once. The Centre's review is the screening, so the online screening is not asked of a CCE applicant. The
passport is a JPEG (it goes on the CCE admission letter). Course registration refuses a CCE student until phase 2 gives CCE
its own offerings in the CCE session.

**Tests.** check.sql — the V379 property (the whole path in the database; 223 properties with V383); `CceIT` (the whole path through the API, with the office and
identity refusals); the applicant, admission, status-checking, window, student-portal, offers and calendar ITs unchanged;
`admission-letter-pdf.test.ts` (the CCE letter).

---

## F. Phase 2a as built (V380)

**The stream.** `catalogue.offering.stream` is `REGULAR` (every existing class) or `CCE`; a course has one class per session,
semester and stream (`UNIQUE (course_code, session, semester, stream)`). Every lookup of a class by course, session and
semester names its stream — the menu (`registration.student_menu` offers a CCE student only CCE classes and a full-time student
only full-time ones), the full-time openings (`open_course_registration`, the catalogue's live-course openings, the GST office's,
the allocation import, the legacy results import), the HOD's allocation desk and counts, the dean's and provost's counts, the CBT
offering list, the support desk's course search (the student's own stream) and the class list (`?stream=`, `REGULAR` unless
asked). The database refuses a registration entry whose class is not the student's stream (`REGISTRATION_STREAM`), and the
support desk's checks refuse it before that (`OFFERING_PERIOD`).

**The CCE calendar.** `policy.route_semester` (route, session, semester: state `NOT_YET_OPEN`/`OPEN`/`CLOSED`, lectures,
registration, late registration, examinations), set by the Centre or the Academic Office (`policy.set_route_semester`); opened
only in the CCE session; set for the CCE session and the one after it; a change to a semester already set says why; every change
in the route's history. The student's calendar (`registration.calendar_semester`, `open_semester`, `add_drop_open(student, …)`,
`semester_closed`) is the CCE calendar for a CCE student and the full-time calendar for every other; the missed semesters that
lead to a voluntary withdrawal are read from it. `policy.archive_session` refuses a session the CCE session still studies in.

**The windows.** `CCE_COURSE_REGISTRATION` and `CCE_SCHOOL_FEES_PAYMENT`, the Directorate of ICT's, beside the full-time
two on Portal Windows (`policy.window_type_for(student, type)`); unset, each is open and the CCE calendar decides. A CCE
student's gate (`registration.cce_gate`): the Centre's classes set up, then the CCE window if ICT set one, else the calendar.
The late registration and late payment fees read the student's own window. ICT's notices reach only the window's students.

**The course load.** `policy.route_level_limit` — the units a CCE student registers within per level, stated by the Academic
Office (`policy.set_route_level_limit`, with the instrument); none is seeded, so until one is stated the University's
`policy.level_limit` applies. Every reader of the range goes through `registration.unit_limit(student, level)`: submission,
add, the support checks, the HOD's approval and the approvals desk, the student's registration screen and probation ceiling.

**The classes.** `catalogue.cce_open_classes(session, semester)` opens a class for every course an active CCE programme offers in
that semester (for a track still carrying a CCE student, or any track) and every carry-over a CCE student owes from it;
`cce_add_class` adds one; `cce_withdraw_class` withdraws one nobody has used (no registration, sheet, register, material,
examination or record refers to it). The Centre allocates the lecturer and second examiner (any lecturer of the University) with
`catalogue.allocate_offering`, whose load and automatic score sheet now keep to the class's own stream; the HOD's allocation
desk refuses a CCE class (`ALLOC_CCE`).

**The evening timetable.** `policy.route_period` — the periods offered as quick picks (seeded with the University's four
examples, 4–6, 5–7, 6–8 and 7–9 pm, as data the Centre edits or retires); a lecture may be at any time. A CCE class's slots are
the Centre's or the Academic Office's (`CCE_SLOT_OFFICE`); no venue or lecturer is in two CCE classes at once
(`CCE_SLOT_VENUE_CLASH`, `CCE_SLOT_LECTURER_CLASH`, the check serialised per session and semester so two lectures saved at the
same moment cannot both pass); `catalogue.cce_clashes` reports what is left (a lecturer allocated after the slots, a
programme-level's two core classes at once, a venue on the full-time timetable of the undergraduate session).

**Attendance.** `attendance.register` opened to course classes (context `COURSE`, the class as the subject, a slot of the class
as the lecture): present, absent, late, excused; a saved mark corrected with its reason; locked by the lecturer; reopened by the
Centre or the Academic Office with a reason. The class list is the students registered on the class (submitted, approved or
locked). `attendance.course_summary` (a student's classes), `attendance.course_report` (by stream, session, semester, faculty,
department, programme, course and date range) and the Centre's policy (`attendance.set_cce_policy`: a minimum — none unless the
Centre sets one — a warning band, the lectures before judging, and whether students read their own attendance). The department's
attendance screen for full-time classes keeps `registration.attendance`.

**Fees.** An uploaded fee structure replaces only the lines of its own kind (`finance.import_fee_structure`): a CCE structure the
CCE lines, a full-time structure every other line; the Bursar's page states CCE lines (entry mode CCE), filters full-time and CCE
lines, uploads a cross-tab as the CCE structure, and clears one kind (`?kind=CCE|FULL_TIME`). The GST/EPS fee is the full-time
students' (`finance.gst_eps_rows`, `gst_population`, the GST runs read full-time classes only); a CCE student's GST and EPS
courses are registered without it. The student's dashboard and registration screen say when the CCE fees are not yet stated.

**Screens.** The CCE desk: `/cce/calendar` (and the course load), `/cce/classes`, `/cce/timetable`, `/cce/registrations`,
`/cce/attendance`, `/cce/school-fees` (the Bursar's too); a lecturer's `/cce/teaching` (CCE Evening Classes: the classes, the
class list, each lecture's register); the lecturer's *My Teaching* marks CCE classes; Portal Windows shows the CCE windows; the
HOD's dashboard counts the department's CCE registrations awaiting approval in the CCE session; the student's registration,
dashboard, timetable and attendance read the CCE calendar, windows and registers.

**API.** `/api/v1/cce/calendar` (GET; PUT `/{session}/{number}`), `/course-load` (GET; PUT `/{level}`), `/classes` (GET, POST;
`/open`, `/{id}/withdraw`, `/{id}/teaching`, `/{id}/slots`, `/{id}/slots/{slot}/end`), `/lecturers`, `/courses`, `/timetable`,
`/periods` (GET, PUT), `/registrations`, `/attendance` (GET; PUT `/policy`; POST `/registers/{id}/unlock`), `/school-fees`;
`/api/v1/cce/teaching` (GET; `/classes/{id}`, `/classes/{id}/registers`, `/registers/{id}`, `/registers/{id}/marks`,
`/registers/{id}/lock`). `/api/v1/finance/sessions/{s}/{y}/schedule/clear?kind=`. `/api/v1/registration/class-list?stream=`.

**Codes.** `REGISTRATION_STREAM`, `CCE_CALENDAR_SEMESTER`, `CCE_CALENDAR_STATE`, `CCE_CALENDAR_SESSION`, `CCE_CALENDAR_DATES`,
`CCE_CALENDAR_REASON`, `CCE_CLASS_SEMESTER`, `CCE_CLASS_SESSION`, `CCE_CLASS_COURSE`, `CCE_CLASS_NOT_CCE`, `CCE_CLASS_REASON`,
`CCE_CLASS_IN_USE`, `CCE_LECTURER`, `CCE_PERIOD_TIMES`, `CCE_PERIOD_LABEL`, `CCE_SLOT_OFFICE`, `CCE_SLOT_TIMES`,
`CCE_SLOT_VENUE_CLASH`, `CCE_SLOT_LECTURER_CLASH`, `CCE_LOAD_LEVEL`, `CCE_LOAD_RANGE`, `ATT_OFFERING`, `ALLOC_CCE`, and the CCE
reason of `SESSION_ARCHIVE_REFUSED`.

**Decided by default (say if the University wants otherwise).** The Head of Department of the programme approves a CCE
registration, as every other; the Centre allocates the lecturers of its classes; a CCE class's register lists the students whose
registration is submitted, approved or locked (so the first lectures are marked before approval); the CCE calendar and the
attendance policy are the Centre's or the Academic Office's, the CCE course load the Academic Office's; no minimum attendance
and no CCE course load are invented; the four evening periods are seeded as editable data; the GST/EPS fee does not reach a
CCE student (the Bursary states any such charge as a CCE line).

**Kept apart on purpose until phase 2b.** Examination sessions, the score sheets they release, CBT offerings and the
allocation's automatic sheet stay on full-time classes (`stream = 'REGULAR'`); results of CCE classes, CBT for CCE, cohort
positions on the route and deferment on the CCE calendar come with the CCE examination step.

**Tests.** check.sql — the V380 property (classes, menu and the stream guard, calendar and windows, the course load, timetable
and clashes, the register, fee structures by kind, the late fee and GST fee, examination sessions, archiving; 224 with V383);
the V379 property's registration gate now reads the Centre's classes. `CceClassesIT` (the whole of it through the API, rerunnable
on one database). Every IT that upserts a class names the new key.

## G. Phase 2b and 3 as built (V381)

**Examinations on the one chain.** `assessment.exam_session.stream` (REGULAR | CCE; the unique key is now session, semester,
kind and stream): ICT sets a CCE examination session beside the full-time one of the same session, semester and kind, on the
same Examination Sessions screen ("Students: CCE (part-time)"). Opening, releasing sheets and the allocation's automatic sheet
read the class's own stream; a trigger refuses a score sheet against the other stream's session (`EXAM_STREAM`). The sheets move
on the same desks; the broadsheet, the Senate schedule and a Senate minute read one stream at a time (`?stream=CCE`; the full-time
students' by default), and the results desk tags a CCE sheet. The student's examination card lists the papers of the student's own
stream in the CCE session; CBT lists the Centre's classes beside the full-time ones, marked.

**Attendance and the examination.** `attendance.policy.bars_exams` — off unless the Centre (or the Academic Office) turns it on,
and refused without a minimum (`CCE_ATTENDANCE_BAR`). Where it is on, `attendance.exam_bar` names a student below the minimum:
CBT refuses them at the start (`CBT_ATTENDANCE`), the card marks the paper "Barred: attendance" (on screen and on the PDF), and
an excused lecture is not counted against anyone. Nothing is invented: no minimum, no bar, by default.

**Progression.** The academic position reads a CCE student in the CCE session (`policy.route_session('CCE')`), on the programme's
CCE length and final level (`ref.programme_route_terms`), with spillover counted past it; six years passing graduates nobody.
The stored position of every CCE student is recomputed when V381 runs, and again whenever the CCE session mapping, the route's
default length or a programme's CCE terms change (`people.refresh_route_positions`).
Deferment dates come from the CCE calendar (`people.period_start`, `period_end`, `deferment_return`); the programme timeline and
the deferment tick read the CCE semesters. The Centre's desk has **Examinations** (its exam sessions and where each CCE class's
sheet stands) and **Progression** (each CCE student's entry, length, expected completion, spillover, registration now).

**Matriculation.** `policy.study_route.matric_series` and `matric_segment`, set by the Registry or the Academic Office on the
Matriculation number format screen (Study routes) with a reason kept in the route's history (`people.set_route_matric`;
`CCE_MATRIC_SERIES`, `CCE_MATRIC_SEGMENT`, `CCE_MATRIC_REASON`). A segment, when set, is printed after the University code
(MOAU/CCE/…); a series, when set, gives the CCE students their own run, drawn under the same lock as every series. Blank: the
programme's series and no segment, as for everyone. Numbers already issued never change.

**Records.** The statement and transcripts carry the study mode, the route and the CCE length (a full-time record is unchanged);
the old-portal student upload reads a route or study-mode column and brings such a student over as CCE and part-time.

**Departments reach their own classes.** The class register and timetable endpoints (`/api/v1/registration/offerings/{id}/…`)
now check the class: a lecturer reaches the classes they teach, a department or faculty office its own department's or faculty's,
the University's offices any — another department's class is refused (`SCOPE_DEPARTMENT`), a lecturer not teaching it 403. A CCE
class's attendance is taken on its register (`ATT_CCE_REGISTER`).

**API.** `/api/v1/cce/exams`, `/api/v1/cce/progression`; `/api/v1/cce/attendance/policy` takes `barsExams`;
`/api/v1/results/exam-sessions` takes `stream`; `/api/v1/results/broadsheet|senate?stream=`; `/api/v1/results/senate/minute`
takes `stream`; `/api/v1/matriculation/config` lists `routes`, PUT `/routes/{code}`.

**Tests.** check.sql — the V381 property (sheets by stream, the stream guard, the card, the bar, the position and spillover,
deferment dates, the matriculation series and segment, the statement, the import; 226). `CceExamsIT` (through the API,
rerunnable). `StudentPortalIT` now acts as the Head of the course's own department.
