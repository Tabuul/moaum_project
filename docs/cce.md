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

**Phase 2 — the CCE academic session in operation.** A stream on course offerings (CCE offerings in the CCE session),
course registration, evening timetable, attendance on the register/mark model, examinations and CBT eligibility, results,
CCE school-fee lines, cohort positions and expected graduation from the route.

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
