# Dossier D — Student records, academic structure, registration and the student portal

Audit date 2026-09-26, repository `C:\Users\ajene\Documents\moaumpp` at HEAD `8c2b6fa` (read-only). Evidence paths are relative to the repository root unless stated. SQL function bodies were read from the local migrated database (`pg_get_functiondef`), so they are cited by function name; the migrations that created them are named where known (V013, V026/V027, V064, V070, V139, V149, V155/V156, V185/V186/V193, V233, V246/V247, V259, V263).

Conventions shared by every module below: every client screen calls the API through `/api/bff/api/v1/...` with an `X-Reason` header (`frontend/src/app/student/common.tsx` `useAct`); a refusal arrives as an RFC-7807 problem (`title`, `detail`, `remedy.message`, `remedy.who`) and is shown by `ProblemNotice` and a red toast; SQLSTATE 23514 raised in SQL becomes HTTP 422 with the message text as written in the function; a `DomainRuleViolation` thrown in Java carries a code (e.g. `REG_UNITS_OUT_OF_RANGE`) plus the remedy. All state tables named in section 10 of each module are attached to the audit spine (`audit.record()` trigger present on every one listed — `inv/triggers.psv`), so a write with no acting person is refused by the database.

---

# 1 Student record and register  (API module: `student`, `studentportal/StudentAuthController`; schemas: `people` (student, biodata, biodata_change, status_change, enrolment, document, student_contact, search_log); pages: `students/**`, `records/**`, `api/auth/student`)

## 1 Purpose
The register is the list of every student the University has admitted, with one row per person in `people.student`: names, numbers (admission, matriculation, JAMB), programme, entry mode/session/level, current level, curriculum track and status. Offices read a record "assembled live" from the modules that own each part (biodata, documents, status history, enrolments, registrations, clearance positions, pending and decided biodata changes). The Academic Office and the Registry make the few writes the register allows: bring a session's admitted candidates onto it (intake), change a status on a cited instrument, correct a level, write biodata, decide a biodata change, close voluntary withdrawals, clear migrated students, and open a student's portal account. A "Records & queries" workbench gives every office one scoped view over students, registration, results, examinations, allocation and clearance.

## 2 Users and roles
- Readers (`StudentController.READERS`): academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, ict, admin, super, bursar, library, security, housing, hrm, audit, lecturer. Every reader may open `/api/v1/student/students`, `/students/{id}`, `/students/{id}/portal`, `/students/{id}/passport`, `/biodata-changes`, `/search`, `/records/{view}`, `/students/migrated`.
- Writers (`StudentController.WRITERS`): academic, registrar, dregistrar — biodata writes, status change, level correction, biodata-change decisions, intake.
- Migrated clearance and voluntary withdrawals: academic, registrar, dregistrar, ict, super.
- Portal account open/reset (`StudentAuthController.open`): registrar, dregistrar, academic, records, ict, super.
- Scope: the register list is bound by `OfficeScope.bound(fac, dept, prog)` "whatever the parameters say" (`StudentController.register`), so a HOD sees their department and a Dean their faculty. `records/{view}` takes the scope from the request as given (no `OfficeScope` call) — see §12.

## 3 Navigation
- Students `t/students` → `/students`: menus of academic ("Student Records"), admin, dean, dregistrar ("Student Records"), facultyofficer, hod, ict, registrar (`inv/routes.md`).
- Biodata Changes `t/biochange` → `/students/biodata-changes`: academic (badge), registrar.
- Records & Queries `t/records` → `/records`: academic, admin, audit, bursar, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, housing, hrm, library, records, registrar, security, super.
- Migrate from Old Portal `t/legacy` → `/records/migration`: ict, records (the upload endpoints belong to the results/legacy group; only the "cleared on arrival" panel is this module's).
- Student 360 `/students/{id}` is reached from any list ("Details"/"Open"), not from a menu (route id `t/student`).

## 4 Screens
**Students — `/students`** (`frontend/src/app/students/page.tsx`, `Students.tsx`). Scope bar (faculty, department, programme, level, session; `loadScope` pins the office's own faculty/department), a "Find a student" box (placeholder "Matriculation number, admission number or name"; searches `matric_no`, `admission_no`, surname, other names, LIMIT 2000 — `StudentRepository.register`), and a table "Matriculation no. | Name | Programme | Level | Status | Details" opening the student modal. Empty state: "Nobody is on the register in this scope" / "Nothing on the register matches “q”". For academic/registrar/dregistrar/ict/super two panels sit above: *Migrated from the old portal* (tiles On the register / Cleared everywhere / Not yet cleared; button "Clear the N not yet cleared" → `POST /student/students/migrated/clear?from=100&to=400`, confirm dialog) and *Voluntary withdrawals* (tiles Due now / Closed so far; "Close all N due", per-row "Close" → `POST /student/students/voluntary-withdrawals/close` with `{studentIds, instrument}`; instrument text "University regulation: four consecutive semesters without course registration").

**Student 360 — `/students/{id}`** (`students/[id]/Student360.tsx`, `Biodata.tsx`). Header with passport (`/student/students/{id}/passport`), name, number, programme, level, entry; status pill; buttons **Change status** (modal: To [select of ACTIVE…VOLUNTARY_WITHDRAWAL], Instrument (required), Reason; warns "A student becomes ACTIVE at matriculation… the database will refuse"), **Correct level** (modal: level 100–600 select, Reason required; `PUT /student/students/{id}/level`), **Portal account** (prompt for an eight-character first password; `PUT /student-auth/accounts/{id}`; enabled only when a matric number exists). Three cards: *Finance* — hard-coded "NOT YET SERVED" placeholder (§13); *Academic standing* — CGPA shown as "—" with "NO RESULT PUBLISHED" and "Units registered" = `approvedUnits`; *Clearances* — the eight convocation units ✓/✗. *Registration* panel for the scope session; *Record history* (status changes with instrument; decided biodata changes). Below it the **Biodata** component: sections Identity (read-only), Personal, Contact, Origin & sponsorship, Parents or guardian, Next of kin & guarantor, Health, Bank account, Documents, Change history; each field badged "From JAMB" (locked) or "Needs approval" (approval tier); selects for nationality, state, LGA, marital status, parent status; "Save" / "Save and continue →" write each changed field with `PUT …/biodata/{field}`.

**Biodata changes — `/students/biodata-changes`** (`students/biodata-changes/BiodataChanges.tsx`). Tiles Awaiting evidence (oldest days) / Approved / Refused / Self-service changes; table Student | Field | From | To | Evidence | Action with "Approve with evidence", "Refuse" (modal requiring "The decision, in words"), "Ask for evidence"; state filter via `?state=`. Only academic/registrar/dregistrar may act ("You are reading this queue, not deciding on it").

**Records & queries — `/records?view=`** (`records/Records.tsx`, `RecordViews.tsx`). Tabs students | registration | fees | results | exams | allocation | clearance | attendance over one scope bar (with course and semester). Fees and attendance return no rows with the sentence `RecordsService.FEES_NOT_SERVED` / `ATTENDANCE_NOT_SERVED` ("School fees are the Bursary's ledger, and the Bursary is not on the portal yet…", "Attendance is taken in the lecture theatre and is not yet recorded in the portal…") — both stale statements, see §13. The allocation view's Assign/Reassign button is disabled with title "Course assignment is not on the portal yet".

**Student sign-in** — `frontend/src/app/api/auth/student/sign-in/route.ts` proxies `POST /api/v1/student-auth/sign-in` and sets the session cookie and the office cookie `student`.

## 5 Workflow and statuses
- `people.student.status` CHECK: ADMITTED, ACTIVE, PROBATION, DEFERRED, SUSPENDED, RUSTICATED, WITHDRAWN, EXPELLED, TRANSFERRED_OUT, GRADUATED, DECEASED, DORMANT, VOLUNTARY_WITHDRAWAL (`ck_student_status`). Default ADMITTED. `ck_student_active_has_matric`: any status other than ADMITTED requires a matric number. `ck_student_matriculated`: matric_no and matriculated_at are set together.
- Intake: `people.intake(session)` inserts a student for every `admissions.candidate` in the session with offer_state ADMITTED/ACCEPTED not yet on the register, admission number `MOAUM/ADM/{YY}/{NNNNNN}` from `platform.next_number('ADMISSION',…)`, programme resolved by name or code (error "the programme "%" for candidate % is not one the University runs…").
- Status changes go through `people.change_status(student, to, instrument, effective, reason)` which writes `people.status_change` and refuses a blank instrument ("a change of status is made on an instrument — the Senate minute, the letter, the Registrar's decision — and none was cited"). Transitions made by the system: ADMITTED→ACTIVE by matriculation (instrument = run ref), →DEFERRED/back by the deferment clock, →GRADUATED by Senate approval of awards, →VOLUNTARY_WITHDRAWAL by the Registry's close, →TRANSFERRED_OUT is available only manually.
- Biodata change: `people.biodata_change.state` PENDING → EVIDENCE_ASKED → APPROVED | REFUSED (`ck_bio_change_state`; a decided row must carry decision text, decided_by, decided_at). Approval writes the value onto `people.biodata` (`ChangeService.approve`). **No producer exists**: `ref.biodata_field` holds only `open` and `locked` tiers (72 rows, none `approval`), `StudentService.writeBiodata` writes open fields at once and refuses locked ones (`STU_FIELD_LOCKED`), and `StudentRepository.askForChange` is never called — the queue can only ever be empty (0 rows in the local database).
- Voluntary withdrawal: `registration.voluntary_withdrawals_due()` names students in ADMITTED/ACTIVE/PROBATION/DORMANT with ≥4 consecutive closed semesters (per `registration.closed_semesters()`) without an APPROVED/LOCKED registration since entry or the last approved one, skipping semesters covered by an approved deferment; `registration.effect_voluntary_withdrawals(instrument, student|NULL)` calls `change_status` for each. The portal refuses such a student at `/api/v1/me` with `STUDENT_RECORD_CLOSED`.
- Migrated clearance: `clearance.clear_migrated(100,400)` inserts CLEARED items for every purpose and unit for students with a matric number but no matriculation run (audit trigger disabled for the bulk insert; note text "Cleared on migration from the old portal…").

## 6 Business rules and validations
- `people.matric_is_immutable` trigger: "the matriculation number % is permanent and is not changed" (HINT "BR-007…") and "the admission number % is retired, not changed".
- `people.fill_curriculum` trigger sets `curriculum_track` (`people.track_for`: school S002 → BMAS; session < 2023/2024 → BMAS; MOAU… → CCMAS_MOAU; BSU… → CCMAS_BSU unless entry ≥ 2024/2025; 2023/2024 → CCMAS_BSU) and `curriculum_version` (framework of the track, else `people.curriculum_for`).
- Level correction (`StudentService.correctLevel`): "A level is 100, 200, 300 … in hundreds, up to the programme's final year." (STU_LEVEL), reason required (STU_LEVEL_REASON); the SQL is a plain UPDATE — no status_change row is written, only the audit spine.
- Biodata decisions: blank decision refused (STU_DECISION_REQUIRED); deciding twice refused (STU_CHANGE_DECIDED).
- Contact constraints: phone `^0[0-9]{10}$`, e-mail regex (`ck_contact_phone`, `ck_contact_email`).
- Search (`SearchService.find`) escapes LIKE wildcards, searches students (matric/admission/names/JAMB), staff, courses, credentials, and writes every search to `people.search_log` (kind, hits) — "the Registrar reviews the log quarterly" (comment; no review screen exists).
- Sign-in (`StudentAuthService`): matric or admission number (or JAMB number — `StudentPortalRepository.byMatric`), bcrypt; first sign-in carries the applicant's password over (`CARRIED_OVER`); a migrated student with `must_change` may sign in with their own number as password; 5 failures lock 15 minutes (`AUTH_LOCKED`); session 12 hours; new password ≥ 8 characters (`APP_PASSWORD_SHORT`); Registry-opened account forces a change (`mustChange`).

## 7 Notifications
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| None from this module directly | — | — | — | — |
Status changes, biodata decisions, level corrections and voluntary withdrawals send nothing (no `queue_notice` call in `StudentService`, `ChangeService`, `change_status` or `effect_voluntary_withdrawals`). The BiodataChanges screen text "the student is notified" is not implemented.

## 8 Reports, exports and documents
- Records views: `DTable` copy/filter only; no branded export on `/records` or `/students`.
- Passport image endpoint (JPEG, re-encoded from PNG by `StudentPortalService.toJpeg`).

## 9 Configuration
- `ref.biodata_field` (field, section, label, tier, hint, wide, ord) — 72 seeded fields in sections personal, contact, origin, family, kin, health, bank; tiers `open` except `university_email` and `senatorial_district` (`locked`). No screen edits it.
- Statuses and levels are CHECK constraints, not tables.

## 10 Data
`people.student` (PK id; FKs admissions.candidate, iam.person, people.matriculation_run, policy.curriculum_track, ref.programme; UNIQUE admission_no, matric_no; 22 columns), `people.student_contact`, `people.biodata` (student_id, field → ref.biodata_field), `people.biodata_change`, `people.status_change` (append-only by convention; instrument non-blank), `people.enrolment` (UNIQUE student, session), `people.document` (status NOT_SUPPLIED/RECEIVED/ACCEPTED/VERIFIED/REFUSED/EXPIRED), `people.search_log`. All audit-attached. Portal account tables `iam.student_account`, `iam.student_event`, `platform.session` are written by `StudentPortalRepository`.

## 11 Scheduled jobs and integrations — None in this module.

## 12 Security notes
- `GET /student/records/{view}` builds its scope from request parameters only (`StudentController.records` → `Scope.of(fac, dept, …)`), unlike `/students` which forces `OfficeScope.bound`. A HOD can therefore read another department's registration/results/clearance rows by editing the URL. `/students/{id}` and `/students/{id}/portal` are readable by every READER office for any student id (no scope check).
- `/student/search` is available to every reader office including lecturer, security, hrm.
- Sign-in events (`iam.student_event`) record UNKNOWN/NO_ACCOUNT/BAD_PASSWORD/LOCKED/CARRIED_OVER/SIGNED_IN/PASSWORD_CHANGED/OPENED_BY_REGISTRY with IP.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Register list with scope and search | IMPLEMENTED | `StudentController.register`, `students/Students.tsx` | LIMIT 2000 |
| Student 360 record | IMPLEMENTED | `StudentService.record` | Finance card is a hard-coded placeholder ("NOT YET SERVED") although `/students/{id}/portal` already returns fees; CGPA card shows "—" although `student_gpa` exists |
| Change status on instrument | IMPLEMENTED | `people.change_status` | |
| Correct level | IMPLEMENTED | `StudentService.correctLevel` | No status_change row |
| Biodata self-service and Registry write | IMPLEMENTED | `StudentService.writeBiodata`, `Biodata.tsx` | |
| Biodata change queue (approve/refuse/ask evidence) | CONFIGURED BUT UNUSED | `ChangeService`, `StudentRepository.askForChange` (never called), `ref.biodata_field` has no `approval` tier | Screen and endpoints work but nothing can create a request |
| Intake run | PARTIALLY IMPLEMENTED | `POST /student/intake/{s}/{y}` | Backend only; no screen calls it (grep of `frontend/src` finds no `/student/intake`) |
| Voluntary withdrawals | IMPLEMENTED | V247 functions, `VoluntaryPanel.tsx` | |
| Migrated clearance on demand | IMPLEMENTED | `clearance.clear_migrated`, `MigratedPanel.tsx` | |
| Records & queries: students/registration/results/exams/allocation/clearance | IMPLEMENTED | `RecordsRepository` | CGPA column always "—" |
| Records & queries: fees, attendance | PLACEHOLDER | `RecordsService.FEES_NOT_SERVED`, `ATTENDANCE_NOT_SERVED` | Text is stale: finance and attendance both exist elsewhere |
| Search log review | NOT IMPLEMENTED | `people.search_log` has no reader | |
| Portal account open/reset | IMPLEMENTED | `StudentAuthController.open`, Student360 "Portal account" | |
| Student sign-in / lockout / password change | IMPLEMENTED | `StudentAuthService` | |

## 14 Common problems
- "the matriculation number … is permanent and is not changed" — an attempt to edit matric_no or admission_no; the Registrar's records question, not an edit.
- "a change of status is made on an instrument … and none was cited" — the Instrument box was blank.
- Changing ADMITTED→ACTIVE manually fails `ck_student_active_has_matric` (a matric number is required); matriculate instead.
- "That number and password do not match a student account." — wrong number/password, or the student has no admission/matric number yet; after five failures "This account is locked after repeated failures; try again after HH:MM".
- "No portal account has been opened for this number yet." — a student with no applicant account (migrated); the Registry opens it from Student 360 → Portal account (needs a matric number).
- "Your record was closed as a voluntary withdrawal…" — status VOLUNTARY_WITHDRAWAL; only the Registry can change status on an instrument.
- HOD dashboard/staff list says "Your Head-of-Department office is not tied to a department yet" — the `hod` office assignment has no department scope and neither the lecturer grant nor the staff record has a home department (`OfficeScope.actingDept`).

## 15 Glossary
Register (people.student); admission number (MOAUM/ADM/YY/NNNNNN, retired at matriculation, never deleted); instrument (the minute/letter a status change cites); tier (open / locked / approval field classes); voluntary withdrawal (four consecutive closed semesters unregistered); migrated student (matric number, no matriculation run); curriculum track (BMAS, CCMAS_BSU, CCMAS_MOAU) and version (BMAS/CCMAS).

---

# 2 Student portal  (API module: `studentportal`; schemas: people, registration, finance/assessment reads; pages: `student/**`)

## 1 Purpose
The signed-in student's own desk under `/api/v1/me` (`MeController`, `@PreAuthorize("hasAuthority('OFFICE_student')")` at class level). It shows the record as the register holds it (dashboard, profile, biodata), the fees the schedule computes and the references the student generates, course registration against the eligible set with the Bursary's per-semester gate, results and GPA (server-side redacted when fees are unpaid), the examination docket, the class timetable and attendance, the identity card, the course spaces (LMS), the library position, deferment, transfer, graduation and every notice sent. Five PDFs are drawn server-side by Next route handlers: course form, examination card, identity card, payment receipt and result broadsheet. Nothing is typed by the student except contact details, the choice of courses, queries, requests and uploads.

## 2 Users and roles
Only `OFFICE_student` (token issued by `StudentAuthService.signIn` with office `student`). `loadStudent()` (`student/load.ts`) redirects any other active office to `/` and a 401 to `/login`; a postgraduate (`entryMode = POSTGRADUATE`) gets the `pgstudent` menu and `PgDashboard`. Offices read the same view for a record through `GET /student/students/{id}/portal`.

## 3 Navigation (`inv/menus.md` §student)
Start here: Dashboard `/student`, School Fees — Pay First `/student/fees`. Academic: Deferment, Course Registration `/student/register`, Registration History, Results, Result Broadsheet, Result Query, Carryover, Inter-Departmental Transfer, My Documents. Learning: My Courses `/student/courses`, Timetable, Attendance, Examinations `/student/exams`. Services: Wallet & Funding, Hostel, Library `/student/library`, Identity Card `/student/idcard`, Health, Help & Requests, ICT Support Tickets. Account: Profile, Biodata, Notifications. Unlisted but linked: `/student/form` (course form), `/student/receipt/{reference}`, `/student/results/{session}/{semester}` (slip), `/student/courses/{offering}`, `/student/transfer/letter/{id}`, `/student/transcript` (redirects to `/student/documents?new=TRANSCRIPT`). Wallet, hostel, health, support, documents, PG screens and results content belong to other groups; their links are noted here only.

## 4 Screens
**Dashboard `/student`** (`Screens1.tsx` `Dashboard`): banners for ADVISED_TO_WITHDRAW / PROBATION standing (from `assessment.student_standing`), the fee gate ("You are cleared to register" / "Action required" with "Pay now" / "What a payment releases is not yet stated for this session" when no clearance scheme is in force), identity card with passport, "This session" steps (On the register → Course registration → Examination docket), a read-only *Student details* card (reads `/me/biodata`), quick tiles (My results, Fees & payments, Graduation or My documents, Deferment, Hostel, Course form — enabled only when the registration is APPROVED/LOCKED), the carryover warning, and *Notices sent to you* (`platform.notice` rows about the student, states Sent / Not delivered / Waiting to be sent).

**Profile `/student/profile`** (`Profile`): editable Phone, Personal email, Contact address → `PUT /me/contact` (server normalises +234/10-digit forms; STU_PHONE "A Nigerian mobile number is eleven digits beginning with a zero.", STU_EMAIL); Current/New password with show/hide → `POST /student-auth/change-password` (button disabled until new ≥ 8 chars); `?change=1` shows "Choose your own password before you go on". Read-only Registry fields. Note: "On the register since" renders `onDay(undefined)` → always "—".

**Biodata `/student/biodata`**: the shared `Biodata` component with `may` and base `/api/bff/api/v1/me` (writes `PUT /me/biodata/{field}`).

**Fees `/student/fees`** (`Screens2.tsx` `FeesScreen`): tiles Session charge / Paid / Outstanding; instalment buttons "First semester · ₦x", "Full session · both semesters", or "Second semester"; "Generate a reference for ₦x" → `POST /me/fees/references` `{session, amount}`; open reference block with `PayByCard` (gateways via `/payments/gateways`, `/payments/checkout`, PayDirect PRN flow and "I've paid — check now" → `/payments/verify`); Payment History table (Paid / Awaiting confirmation / Expired; "Receipt" link when `receipt_no`); other sessions with a charge. `?paid=ref` triggers a server-side verify on load.

**Receipt `/student/receipt/{reference}`** (`ReceiptScreen`): the receipt document (receipt number, date, received from, matric, programme·level, session, semester, purpose, amount, channel, gateway/teller reference), QR + check code to `/verify/receipt/{ref}?c=`; "Download PDF" → `/student/receipt/{ref}/pdf`. Unconfirmed: "This payment is not confirmed yet".

**Course registration `/student/register?session&semester`** (`Screens3.tsx` `Register`): semester switcher up to the open semester with ✓ for registered ones and the warning "You have not registered First semester yet — register it first…"; when not cleared and not locked: "You cannot register yet" gate card (Student status, On the register, Financial clearance with the charge/paid/outstanding rows and "Pay ₦x", Registration window); SIWES notice; locked/returned notices ("Submitted on … — with your Head of Department", "Approved on …" with "Course form" button, "Returned to you" with the HOD's reason); *Add or drop courses* panel when the add/drop window is open (Drop / Add rows → `POST /me/registration/drop|add`); units meter "N of min–max credit units" with Below minimum / Over limit / Valid; *Outstanding carryovers* (fixed, red); *{level} Level Core Courses* (Core+GST bases) and *Electives* pick lists; "Save the draft" (`PUT /me/registration`) and "Submit for approval" (save then `POST /me/registration/submit`; disabled unless within range).

**Course form `/student/form`** (`Form`): "The course form is issued when your registration is approved" until APPROVED/LOCKED; then a document with passport, name, matric, level, session, semester, table Course code | Course title | Lecturer | Unit | Type (carryover first, "· C/O"), TOTAL CREDIT UNITS, Verification = first 8 chars of the registration id; "Download PDF" and "Print" (hidden-iframe print of the PDF).

**Registration history `/student/registration-history`** and the lower half of `/student/courses`: tiles Registrations / Courses registered / Carryovers / Identifier; current session panels with Course code | Course title | Lecturer | Unit | Type | Status, "History — N earlier registrations" toggle. (Text says "the Faculty Officer approved" — approval is the HOD's.)

**Results `/student/results`, slip `/student/results/{s}/{n}`, broadsheet `/student/broadsheet`, query `/student/query`, carryover `/student/carryover`** (`Screens4.tsx`, `Screens5.tsx`): read `GET /me/results` (redacted per session when `finance.clears(..,'RESULTS')` is false — `withheld: true`, GPA nulled) and `/me/queries`. Result content rules belong to the results group; this module's parts: the "Official transcript" button is disabled ("Arrives with the credentials module") even though `/student/documents` exists; slip "Download result slip" → `/student/results/{s}/{n}/pdf`; broadsheet "Print broadsheet" → `/student/broadsheet/pdf`.

**Examinations `/student/exams`** (`Exams`): scheme notice, "Bring your identity card", per exam session a table Course | Date & time | Venue | Status (Withheld / Docket ready / Awaiting slot); "Download exam card" → `/student/exams/card/pdf?session&semester`; "Print the docket".

**Timetable `/student/timetable`**, **Attendance `/student/attendance`**: `GET /me/timetable?semester` (`registration.student_timetable`, `registration.attendance_rate`); attendance flags below 75% "At risk".

**Identity card `/student/idcard`** (`IdCard`): notices (card issued / "A card is made after matriculation" / "Your card waits on the Bursary's clearance" / "Your card has not been issued yet"); card preview (`IdCardPair`; blood group, graduates, kin phone shown as "—"); "Open the printable copy" → `/student/idcard/pdf` (only when a card is ISSUED); "Report it lost" (prompt for reason → `POST /me/id-card/lost`); Cards table.

**My courses `/student/courses`** and **space `/student/courses/{offering}`** (`Courses.tsx`, `SpaceScreen.tsx`): one card per approved course space (materials read %, assignments due); space: tiles, Materials table (Open counts a read: `GET /me/courses/materials/{id}/content` or `POST …/read` for links), Assignments table with Submit/Replace modal (text and/or file ≤ 5 MB → `POST /me/courses/assignments/{id}/submit`).

**Library `/student/library`** (`Library.tsx`): On loan (Renew when not overdue and renewals < max), Fines ("Generate the reference" → `POST /me/library/loans/{id}/fine-reference`, then "Pay {ref}" on Fees), Reservations, catalogue search `?q=` with "Join the waiting list" (`POST /me/library/reservations`).

**Graduation `/student/graduation`** (`Screens6.tsx`): computed from `records.student_graduation`: steps (audit → Senate → cleared by every unit → certificate printed → collected), tiles, award panel, *Clearance for convocation* table (eight units), certificate panel.

**Notifications `/student/notifications`**: list of notices and "How we reach you" (channels always on).

**Deferment `/student/deferment`**, **Transfer `/student/transfer`** — described in modules 5 and 6.

## 5 Workflow and statuses
Registration lifecycle is module 4's; here the student-side calls: `choose` → `registration.student_draft` + `student_choose` (refused unless status ADMITTED/ACTIVE/PROBATION: REG_STUDENT_NOT_ELIGIBLE "A student who is … does not register."), `submit` → `registration.student_submit`, add/drop → `student_add`/`student_drop`. The current session is `policy.academic_session` CURRENT, else the latest session with a fee schedule, else "2026/2027" (`StudentPortalService.session`).

## 6 Business rules and validations
- Registration view limit: SIWES semester → exactly the SIWES units; on PROBATION with a `probation_max_units` ceiling the max (and min) are capped (`registrationView`).
- Fee gate per semester: `clears = finance.semester_cleared(student, session, semester)`; `openSemester` = highest OPEN semester (default 1); earlier unregistered semesters are offered.
- Results redaction happens server-side (`StudentPortalService.results`) only when a clearance scheme is in force (`policy.in_force('clearance','UNIVERSITY',…)`).
- Docket/ID card clearance: `finance.clears(student, session, 'EXAMINATION'|'ID_CARD')`; null (no scheme) shows the scheme notice.
- Result query: part EXAM/CA/ABSENT (RES_QUERY_PART), text required (RES_QUERY_SAID).
- Transcript request through `/me/transcripts` (legacy V027 path): destination SELF/INSTITUTION/EMPLOYER/EMBASSY (CTP_DESTINATION), copies 1–10, fee reference "Transcript {ref}" — the screen for it (`Screens5.Transcript`) is no longer routed (`/student/transcript` redirects to documents).

## 7 Notifications
None sent by this module; it displays `platform.notice` rows (`about_kind='student'`, last 30).

## 8 Reports, exports and documents
| Document | Route | Content | Verification |
|---|---|---|---|
| Course registration form | `student/form/pdf/route.ts` | Brand header, passport (JPEG), name/matric/programme/level/session/semester/date of registration, CODE·COURSE TITLE·UNIT·TYPE (carryovers red, first), total units, signature lines "Head of Department / Level Coordinator", "Dean of Faculty", footer with registration id prefix | QR to `/verify/registration?m&s&sem&c` + "Check code" (sha256 token; `VerifyController.registration` returns the record only when APPROVED/LOCKED and the token matches) |
| Examination card | `student/exams/card/pdf/route.ts` | Crest watermark, matric watermarks, header "EXAMINATION CARD", photo with name and "Original", candidate block, COURSE CODE·TITLE·UNIT·SIGN/INVIGILATOR lines, 8 instructions and 14 regulations, footer | QR to `/verify/exam?m&s&sem&c` + check code; refused (409) without an approved registration or when not cleared for examinations |
| Identity card (printable copy) | `student/idcard/pdf/route.ts` | Front (name, number, faculty, level, programme, blood group "—", admitted year, graduates "—", session, valid to, serial) and back (barcode = matric without punctuation, emergency phone from reach_phone) | None; 409 "No identity card issued" until a card is ISSUED |
| Payment receipt | `student/receipt/[reference]/pdf/route.ts` | Header "Official Payment Receipt · Bursary Department", passport, receipt no, date, payer block, BEING PAYMENT FOR/AMOUNT, TOTAL RECEIVED, channel, teller ref, microtext band | QR to `/verify/receipt/{ref}?c=` + check code; 409 "Not confirmed" |
| Result broadsheet | `student/broadsheet/pdf/route.ts` | Every published semester: COURSE·TITLE·UNIT·CA·EXAM·TOTAL·GRADE·PT and CUR/CUE/WGP/GPA/TCR/TCE/TWGP/LCGPA/CGPA line | None; 409 "Withheld" when results are withheld |
| Result slip | `student/results/[session]/[semester]/pdf/route.ts` | (results group) | QR to `/verify/results` |
All PDFs use `lib/pdf-write.ts`; the passport is fetched from `/api/v1/me/passport` with the session token and embedded only as JPEG.

## 9 Configuration
Reads `policy.level_limit` (100–600: 18–24 units, 700: 9–48, 800: 6–48, 900: 0–48; `probation_max_units` unset for all), `policy.semester` (state, `registration_closes`, `late_registration_closes`), the clearance scheme and fee schedule (finance group).

## 10 Data
No table of its own; reads/writes `people.student_contact`, `registration.*`, `finance.payment_reference`, `credentials.identity_card` (`report_card_lost`), `credentials.transcript_request`, `assessment.result_query`, `platform.notice`, `iam.student_account`, `iam.student_event`, `platform.session`.

## 11 Scheduled jobs and integrations
Payment gateways through the payments module (`PayByCard`). No job.

## 12 Security notes
- Every `/me/*` handler keys on `auth.getName()` (student id) — no cross-student access. Passport response is `no-store` because the URL is the same for every student.
- The PDF routes run in Next with the student's session token (`sessionToken()`); the QR check codes are stateless sha256 tokens, so the public verify pages cannot be enumerated without the code.
- The legacy `/me/transcripts` endpoints remain callable although no screen uses them.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Dashboard, profile, contact, password | IMPLEMENTED | `Screens1.tsx`, `MeController` | "On the register since" always "—" |
| Fees view, reference, receipt, gateway checkout | IMPLEMENTED | `Screens2.tsx` | Finance rules in the finance dossier |
| Course registration (draft/submit/add/drop, gates, meter) | IMPLEMENTED | `Screens3.tsx`, `StudentPortalService` | |
| Course form (screen + PDF + QR verify) | IMPLEMENTED | `form/pdf/route.ts`, `VerifyController.registration` | |
| Exam card PDF | IMPLEMENTED | `exams/card/pdf/route.ts` | |
| Identity card preview/PDF, report lost | IMPLEMENTED | `Screens5.IdCard`, `idcard/pdf/route.ts` | Blood group / kin phone / graduates hard-coded "—" |
| Registration history | IMPLEMENTED | `RegistrationHistory.tsx` | Copy says "Faculty Officer approved" |
| Results/slip/broadsheet/query/carryover screens | IMPLEMENTED | `Screens4/5.tsx` | "Official transcript" button disabled with stale text |
| Timetable, attendance | IMPLEMENTED | `Screens5.tsx` | |
| Course spaces (student side) | IMPLEMENTED | `SpaceScreen.tsx` | |
| Library (student side) | IMPLEMENTED | `Library.tsx` | |
| Graduation view | IMPLEMENTED | `Screens6.tsx` | |
| Notifications | IMPLEMENTED (read-only) | `notifications/page.tsx` | Channel preferences are display only |
| Legacy transcript request (V027) | CONFIGURED BUT UNUSED | `MeController.transcripts/requestTranscript`, `Screens5.Transcript` unrouted | Superseded by documents (V262) |
| PG dashboard, wallet, hostel, health, support, documents, research | other groups | | |

## 14 Common problems
- "the first semester school fees for 2026/2027 are not fully paid" (HINT "Course registration for a semester opens when that semester's school fees are cleared in full…") on Submit.
- "the registration carries N units; at 100 level the range is 18 to 24" — add/drop courses or obtain an HOD overload (no overload mechanism exists; see module 4).
- "add and drop is not open for 2026/2027 semester 1" — the semester is not OPEN or the late-registration deadline has passed.
- "that course is not offered to your programme at your level this semester" — the course is not bound in the programme structure or has no offering for the session.
- Exam card 409 "Not cleared for examinations"; ID card 409 "No identity card issued"; receipt 409 "Not confirmed".
- "No core course is offered to your programme this semester yet" — registration not opened for the session (module 7 "Open course registration").

## 15 Glossary
Course form (the approved registration as a document); docket/examination card; add/drop window (semester OPEN and today ≤ late_registration_closes/registration_closes); check code (sha256 token printed beside the QR); scheme (the clearance scheme stating what a payment releases).

---

# 3 Matriculation and the matriculation number format  (API: `matriculation` — `MatriculationController`, `MatricFormatController`; schema: people (faculty_list, faculty_list_query, matriculation_run, matric_format, matric_series, matric_history); pages: `matriculation/**`)

## 1 Purpose
Matriculation turns an ADMITTED student into an ACTIVE one by issuing the permanent matriculation number. A faculty list is generated (never typed) from approved course registrations of ADMITTED students; the Faculty Officer queries names or confirms the list; the Academic Office/Registry runs matriculation for a session in one transaction over every confirmed list, or issues one number to a straggler who has since paid and registered. Since V263 the number is built from a configured rule — `MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}` — with named series whose counters only move forward, and every issue is written once to a history.

## 2 Users and roles
- Readers (`MatriculationController.READERS`, `MatricFormatController.READERS`): academic, registrar, dregistrar, dvc, vc, records, dean, hod (run screens only), facultyofficer, ict, admin, super.
- Faculty list officers (`OFFICERS`): academic, registrar, dregistrar, facultyofficer — query, withdraw query, confirm.
- Runners (`RUNNERS`): academic, registrar, dregistrar — run, single matriculate.
- Format configuration (`MatricFormatController.CONFIG`): academic, registrar, dregistrar, super.
- Scope: none in code — a Faculty Officer can open and confirm any faculty's list by URL (the screen lists all faculties; the DB records `confirmed_by`).

## 3 Navigation
Matriculation `t/matriculation` → `/matriculation` (academic with badge, dregistrar, registrar); Registered Students `t/matlist` → `/matriculation` (facultyofficer); Matriculation Number Format `t/matriculation-config` → `/matriculation/config` (academic, dregistrar, registrar). Faculty list `/matriculation/faculty/{code}?session=` from "Open".

## 4 Screens
**Matriculation `/matriculation?session=`** (`MatriculationScreen.tsx`; session defaults to "2026/2027" when absent): RoleLine; headline note (run done / "N faculty lists are not confirmed, so the run cannot start" / "Every faculty list is confirmed — the run may start" / "Nobody is on a faculty list for … yet"); a note "The number follows the configured rule" with a link to the format screen; tiles Registered students / Confirmed by Faculty Officers / Faculties outstanding / Numbers issued; *Faculty lists* table Faculty | Faculty Officer | Registered | Confirmed | State (Confirmed / N under query / Not returned / Nobody registered) | Open; *What the run does* steps (text still describes "MOAUM/MTC/26/1874 … one sequence per department" — pre-V263 wording); *Held back from this run* (queried students without a number); button "Run matriculation for N students" (`POST /matriculation/sessions/{s}/{y}/run`, disabled while a faculty is outstanding or nobody is confirmed); after a run, a sample of five allocations.

**Faculty list `/matriculation/faculty/{code}`** (`FacultyListScreen.tsx`): tiles Registered in the faculty / Under query / To be confirmed / State; table Admission number | Name | Department | Units (red below `policy.level_limit(100).min_units`) | Fees ("—", not computed) | State (Query / For matriculation) | actions: "Issue number" (runners; `POST …/students/{id}/matriculate`), "Query" (modal Reason + "Who clears it" select Faculty Officer/Bursary/Head of Department/Academic Office → `PUT …/queries/{studentId}`), "Withdraw query"; "Confirm N students to the Academic Office" (`POST …/confirm`, disabled once confirmed); "Export the list" (CSV via `csv()`/`download()` — not the branded export).

**Matriculation number format `/matriculation/config`** (`MatricConfig.tsx`): PageHead with the live pattern and Excel/PDF buttons (`brandedXlsx`/`brandedPrint`, serial `MAT`, S/N first); warning "N programme(s) are set to carry a code and have none"; tiles Series / Programmes with a code / Carrying none / Numbers issued on record; *The format rule* (University code, Separator "/" or "-", Sequence padding 0–8, checkboxes Faculty code / Programme code / Year of entry / Sequence (fixed on), Note, "Save the rule" → `PUT /matriculation/config/format`; live samples); *Series* table with Edit/"Add a series" modal (Code, Name, Last number issued "Moves forward only", Note, Active → `PUT …/series/{code}`); *Faculties* table (Segment, Series; Edit modal → `PUT …/faculties/{code}`); *Programmes* table with faculty filter and search (Faculty segment, Programme code, Carries code, Series, Next number or problem pill; Edit modal: "This programme carries a programme code in the number", Programme code, Own faculty segment, Series; `PUT …/programmes/{code}`); *Numbers issued most recently* (last 25 history rows). Read-only for non-CONFIG offices.

## 5 Workflow and statuses
- `people.faculty_list.state` DRAFT → CONFIRMED (`ck_flist_state`; CONFIRMED requires confirmed_at and confirmed_by). The list rows are computed each time by `people.faculty_list_rows(session, faculty)`: ADMITTED students of the faculty with a registration in the session in APPROVED/LOCKED, joined to an un-withdrawn query. A query is upserted in `people.faculty_list_query` (reason non-blank, office) and withdrawn by setting `withdrawn_at`.
- Run (`people.matriculate(session)`): refuses if any faculty with rows lacks a CONFIRMED list ("the run cannot start: % has not confirmed its list"); creates `people.matriculation_run` with ref `MAT/{YYYY}/{NNN}` (`platform.next_number('MATRIC_RUN', …)`); for every un-queried row whose `finance.position(student, session).paid_in_full` is true, ordered by department, surname: `people.next_matric(student, run, 'Matriculation run …')`, then `UPDATE people.student SET matric_no, matriculated_at=now(), matriculation_run, status='ACTIVE'`, a `status_change` ADMITTED→ACTIVE with the run ref as instrument and reason "Matriculated", and `people.matric_tell`. If nobody qualifies: "nobody on a confirmed list has both paid the fees and registered for %; there is nothing to matriculate". One transaction — every number or none.
- Single issue (`people.matriculate_student`): returns the existing number if any; refuses unless status ADMITTED ("only an admitted student is matriculated; this one is %"), an APPROVED/LOCKED registration exists for the entry session ("the student has not registered courses for %"), and `finance.position(entry_session).paid_in_full` ("the school fees for % are not settled"); creates a one-student run and proceeds as above with reason "Matriculated on fees and registration".
- Confirm twice: `MAT_ALREADY_CONFIRMED` ("The X list for S is already confirmed.").

## 6 Business rules — the exact algorithm (V263)
`people.matric_components(student)` reads the single format row `people.matric_format WHERE id='UNIVERSITY'` and the student's programme/faculty:
- `university_code` (default MOAU, `^[A-Z]{2,6}$`);
- `faculty_segment` = when `format.faculty_code`: `coalesce(programme.matric_faculty_code, faculty.matric_code, faculty.code)`;
- `programme_segment` = when `format.programme_code AND programme.matric_uses_code`: `programme.matric_code`;
- `yy` = when `format.year`: `substr(student.entry_session, 3, 2)` (falls back to the current year when entry_session is null);
- `series_code` = `coalesce(programme.matric_series, faculty.matric_series, 'GENERAL')`;
- `problem` when: no programme; programme configured to carry a code but `matric_code` is null ("Programme % is configured to carry a code but has none; give it one or set it to carry none"); faculty segment null; series inactive.
`people.next_matric(student, run, reason)`: raises "the matriculation number cannot be built: {problem}" (HINT "The Registry configures the faculty, the programme and the series under Matriculation number format."); locks the series row `FOR UPDATE`; loops `v_seq = last_issued + try`, formats with `people.format_matric` (segments joined by the separator with empty segments removed — no empty separator; sequence left-padded to `sequence_digits` when > 0), and passes over any number already on `people.student.matric_no` or in `people.matric_history` (by number or by series+sequence) — "the sequence is spent, never reused"; after 1000 tries "no free number in series %"; then `UPDATE matric_series SET last_issued = v_seq` and `INSERT matric_history (student, number, series, sequence, components jsonb {university, faculty, programme, usesCode, year, sequence, programmeCode, facultyCode}, run_id, issued_by, actor_office, reason)`.
Configuration guards (`MatricFormatController`): university code letters only (MATRIC_UNIVERSITY); a faculty/programme code `[A-Z0-9]{2,6}` (MATRIC_CODE); series code `[A-Z][A-Z0-9_]{1,20}` (MATRIC_SERIES); a series' `last_issued` cannot go back ("Series % has issued up to %; it does not go back." MATRIC_SERIES_BACK); "carries a code" with no code refused ("The programme is set to carry a code but none is given." MATRIC_NO_CODE); DB CHECKs `ck_mf_one` (single row), `ck_mf_sep` ("/" or "-"), `ck_mf_digits` 0–8, `ck_mf_seq` (sequence always true), `ck_ms_last ≥ 0`. `people.matric_history_is_written_once` refuses any UPDATE ("the matriculation history is written once; a number issued is never edited or reused") unless `moaum.maintenance = on`. `people.student.ck_student_matric_shape` accepts both the old `MOAUM/DEPT/YY/NNNN` shape and the new `PREFIX(/SEG){1,4}/NNN…` shape.
Preview: `people.matric_preview(student)` / `GET /matriculation/config/preview/{studentId}` gives the number the student would receive next (not wired to a screen). `people.matric_config_rows()` gives every programme's next sample and problem.

## 7 Notifications
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Number issued (run or single) | `people.matric_tell` from `matriculate` / `matriculate_student` | student (`people.student_reach`: contact e-mail/phone, else applicant account) | EMAIL + SMS | "Your matriculation number" — "Your matriculation number is X. It is permanent, it opens the portal in place of your admission number…" |
No notice on query, confirm or configuration change.

## 8 Reports, exports and documents
- Faculty list CSV ("Export the list": Admission number, Name, Department, Units, State).
- Matriculation Number Configuration — branded Excel and PDF (columns S/N, Faculty, Programme, Programme Ref, Faculty Segment, Programme Code, Carries Code, Series, Next Number, Problem).
- `GET /matriculation/config/history?q=` (last 500 issues with components and run ref) — no screen consumes it.

## 9 Configuration (seeded, local DB)
- `people.matric_format`: MOAU, faculty_code on, programme_code on, year on, sequence on, digits 0, separator "/", note "MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}; the programme segment where the programme is configured to carry one".
- `people.matric_series`: ADMIN "Administration and Management series" 13567; ARCHITECTURE 76; COLLEGE "Basic and Applied Medical Sciences, and Medicine and Surgery" 6095; GENERAL "Every other faculty" 85632; PHARMACY 199 (the V263 seed values 13556/76/6093/85631/198 have advanced by the demo issues).
- `ref.faculty` segments/series: AC→AC/ARCHITECTURE; AR→AR/GENERAL; BAMS→BM/COLLEGE; CM→CS/GENERAL; ED, ES, SC, SS→GENERAL; LW→LAW/GENERAL; MS→AD/ADMIN; PS→PHRM/PHARMACY; TI→TS/GENERAL.
- `ref.programme`: 62 undergraduate programmes carry a code (e.g. ACC, CMP, MTH, MBBS none); MBBS (C00061) carries no code but its own faculty segment "MBBS"; Biochemistry (C64548) has own segment SC and series GENERAL; Doctor of Pharmacy, LL.B and every postgraduate programme carry no code; 21 undergraduate programmes (e.g. B.A. English Studies, B.Ed History, B.Sc. Zoology, B.Sc. Mass Communication) carry none "until the Registry gives it one". Sample numbers on record: `MOAU/MBBS/20/6095`, `MOAU/AD/ACC/99/13567`, `MOAU/PHRM/99/199`, `MOAU/LAW/99/85632`.
- `policy.level_limit(100).min_units` = 18 drives the red units flag on the faculty list.

## 10 Data
`people.faculty_list` (UNIQUE session+faculty), `people.faculty_list_query` (PK list+student), `people.matriculation_run` (UNIQUE ref), `people.matric_format` (single row), `people.matric_series`, `people.matric_history` (write-once; UNIQUE matric_no; UNIQUE series+sequence; FK run, student, series). `people.student.matriculation_run` links the student to the run; `matriculated_at` set with the number.

## 11 Scheduled jobs — None.

## 12 Security notes
Faculty-list actions carry no faculty scope in code; the run and single issue are limited to three offices; the history is immutable by trigger. The screen's default session "2026/2027" is hard-coded in `matriculation/page.tsx` and the faculty page.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Faculty list generation, query, withdraw, confirm | IMPLEMENTED | `MatriculationController`, `people.faculty_list_rows` | No faculty scope enforcement |
| Batch run, one transaction | IMPLEMENTED | `people.matriculate` | |
| Single straggler issue | IMPLEMENTED | `people.matriculate_student` | |
| V263 format rule, series, faculty/programme segments, history | IMPLEMENTED | `people.next_matric`, `MatricFormatController`, `MatricConfig.tsx` | |
| Preview endpoint | PARTIALLY IMPLEMENTED | `GET /matriculation/config/preview/{id}` | No UI |
| History search endpoint | PARTIALLY IMPLEMENTED | `GET /matriculation/config/history` | No UI beyond "recent 25" |
| "Fees" column on the faculty list | PLACEHOLDER | `FacultyListScreen.tsx` renders "—" | The run itself checks `finance.position` |
| Run-screen explanatory text | stale | `MatriculationScreen.tsx` "What the run does" | Describes per-department sequences (pre-V263) |

## 14 Common problems
- "the run cannot start: Faculty of X has not confirmed its list" — confirm every faculty list with registered students first.
- "the matriculation number cannot be built: Programme … is configured to carry a code but has none" — fix on the format screen (the whole run rolls back).
- "the student has not registered courses for 2025/2026" / "the school fees for … are not settled" on Issue number.
- A student on the list has no number after the run: they were under query, or `paid_in_full` was false (the list's Fees column does not show this).
- "Series X has issued up to N; it does not go back." when lowering a counter.

## 15 Glossary
Faculty list (generated roll of ADMITTED students with approved registration); query (a name held back with a reason and the office that clears it); run (`MAT/YYYY/NNN`); series (a named counter, e.g. ADMIN, COLLEGE); segment (a part of the number); straggler (single issue after the run).

---

# 4 Course registration, approvals, class lists and the offering desk  (API: `registration` — `RegistrationController`, `DeskController`; schema: registration, catalogue (offering, class_slot); pages: `registration/class-list`, `registration/RegistrationApprovals.tsx` (mounted on `/results/approvals`), the student's `/student/register`)

## 1 Purpose
A course registration is one row per student, session and semester carrying the courses (entries) the student chose from the menu the programme structure and the session's offerings produce, plus the carryovers the published results impose. The student drafts and submits it; the Head of Department approves or returns it; approval puts the student on every class list, course space and score sheet the entries carry. The module also serves the class list (roll) of an offering, the lecturer's attendance register and the department's timetable slots, and lets the Registry/HOD upsert courses, offers and offerings directly.

## 2 Users and roles
- Readers of the class list (`RegistrationController.READERS`): academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, lecturer, ict, admin, super. A department office is held to its own courses (`scope.assertCourseInScope`), a lecturer to offerings they carry (`RegistrationRepository.teaches`: lecturer, second examiner or co-lecturer) — "X is not allocated to you in S; a lecturer reads the class list of their own courses only."
- Registration desk list (`DeskController.DEPARTMENT`): hod, lecturer, dean, facultyofficer, academic, registrar, dregistrar, super; HOD/lecturer confined server-side by `scope.deptWithin`.
- Approve / return: hod, super only (`HOD_APPROVES`); a resolved HOD only for their own department (`REG_OTHER_DEPT`).
- Create/submit a registration for a student (`APPROVERS`): academic, dregistrar, hod, lecturer, registrar, super (backend only).
- Course/offer/offering upserts (`CATALOGUE`): hod, academic, registrar, dregistrar, super; making a course LIVE through this path only academic/registrar/dregistrar/super (`REG_COURSE_NOT_LIVE_BY_DEPARTMENT`).
- Attendance and slots: lecturer, hod, dean, super; the examination slot form on the same screen is for exams/facultyexams/records/academic/registrar/super (results group endpoint `PUT /results/offerings/{id}/exam-slot`).

## 3 Navigation
Registered Students `r/classlist` → `/registration/class-list` (academic, dean, exams as "Examination Roll", hod, lecturer). Departmental Approvals `t/approvals` → `/results/approvals` (hod menu; the registration desk panel appears there for hod, lecturer, dean, facultyofficer, academic, registrar, dregistrar, super — `results/approvals/page.tsx`). The HOD dashboard tile "Registrations to approve" links to `/results/approvals`.

## 4 Screens
**Registration approvals** (`RegistrationApprovals.tsx` on `/results/approvals`): panel "Course registrations submitted by students" (`GET /registration/course-registrations?session&semester=0&dept&status=SUBMITTED`), table Student (click opens a modal with Code | Course title | Units | Kind | Basis and totals) | Programme | Level | Semester | Courses | Units "of range" | Submitted | Approve / Return (prompt "What must the student change? They read this."). Only hod/super may press; others see the queue.

**Registered students `/registration/class-list`** (`ClassListScreen.tsx`, `OfferingDesk.tsx`): scope bar with course; tiles Registered / owning department / Other programmes / Cleared to sit; buttons "Download class list", "Attendance register", "Examination roll" (CSV); table Matriculation number | Name | Programme | Level | Basis | Attendance ("—") | Clearance (Cleared / Blocked — fees, from `clearance.is_clear(student,'EXAMINATION')`); warning listing students not cleared. Below: *Attendance* (date, All present/None, per-student checkboxes, "Record N of M present" → `POST /registration/offerings/{id}/attendance`; "Rate so far" from the recorded days); *Timetable slots* (Day, Kind Lecture/Practical/Tutorial, From, To, Venue → `POST …/slots`; "End" → `POST …/slots/{slot}/end`); *Examination slot* (results group).

## 5 Workflow and statuses
`registration.course_registration.status`: DRAFT → SUBMITTED → APPROVED (or RETURNED → resubmitted) → LOCKED (`ck_reg_status`; APPROVED/LOCKED require approved_at). Entries `registration.entry.status`: REGISTERED → APPROVED (set for all REGISTERED entries when the registration is approved — `RegistrationRepository.setStatus`), DROPPED, WITHDRAWN; `entry_type`: CURRENT, CARRYOVER, REPEAT, ELECTIVE, GST, BORROWED. Nothing anywhere sets LOCKED or WITHDRAWN: a grep of `api/` and `db/` finds `status = 'LOCKED'` only in refusal checks (V139, V195), never in an UPDATE of `registration.course_registration`.
- Draft: `registration.student_draft` creates the row at the student's current level and inserts every carryover from `registration.student_menu` as CARRYOVER entries.
- Choose: `registration.student_choose` deletes non-carryover entries and inserts the chosen offerings from the menu with type GST/BORROWED/ELECTIVE/CURRENT by basis/kind; refused unless DRAFT or RETURNED ("this registration is %; it is not edited", HINT "A submitted registration is changed by the level adviser returning it.").
- Submit: `registration.student_submit` — `finance.semester_cleared` gate; units within `policy.level_limit` (min/max) else "the registration carries % units; at % level the range is % to %" (HINT "…or obtain an overload approval from the Head of Department"); on PROBATION/ADVISED_TO_WITHDRAW with a `probation_max_units` ceiling: "you are on probation (CGPA % after …); the registration carries % units and the limit on probation at % level is %"; sets SUBMITTED, submitted_at. The trigger `people.deferment_gate_course_registration` refuses INSERT or a change to SUBMITTED when an approved/active deferment covers the period ("REGISTRATION UNAVAILABLE: your deferment for % is approved; you cannot register for the deferred period").
- Approve (`RegistrationService.approve`): student status must be ADMITTED/ACTIVE/PROBATION (REG_STUDENT_NOT_ELIGIBLE "(I-STU-2)"); SIWES semester must carry exactly the SIWES units, else the level range (REG_UNITS_OUT_OF_RANGE); sets APPROVED, approved_at, approved_by; entries → APPROVED. Retried up to 4 times on deadlock (`withDeadlockRetry`).
- Return: comment required (REG_RETURN_SAYS_WHY "A registration is returned with the reason on the record."); status RETURNED with `returned_comment` (the student sees it and edits again).
- Add/drop after submission (V139): `registration.student_add` (registration exists, not LOCKED, `registration.add_drop_open`, `finance.clears(...,'REGISTRATION')`, course on the menu and not a carryover, level max not exceeded — "adding this course puts you at % units, over the maximum of % at % level"; on an APPROVED registration the entry is APPROVED at once, on SUBMITTED it stays REGISTERED); `registration.student_drop` (not LOCKED, window open, entry present, not a CARRYOVER — "a carryover cannot be dropped; it must be repeated", no mark recorded — "a mark is already recorded in this course; it cannot be dropped"; entry → DROPPED).
- Side effects: `assessment.trg_registration_releases_held` / `trg_entry_releases_held` (results group) fire on status changes.

## 6 Business rules and validations
- The menu (`registration.student_menu`): courses bound to the student's programme at the student's current level (`catalogue.course_offer`, track null or equal to the student's track), course not ENDED and not a demo `DMO %`, with an offering for the session and semester, and `course.curriculum` null or equal to the student's `curriculum_version`; plus carryovers (`registration.carryovers`: published GRADED results with 0 points on non-elective courses not since passed) that have an offering this semester — suppressed entirely in a SIWES semester.
- `registration.units_of` sums entries that are not DROPPED/WITHDRAWN.
- `registration.is_elective_for`: elective by the programme's offer basis, else by the course kind — a failed elective is never a carryover.
- `registration.siwes_units(programme, level, semester)`: max units of an `industrial_training` course offered at that level/semester.
- Attendance (`registration.mark_attendance`): actor required; marks every student on the approved roll present/absent for the day; re-marking the same day replaces (UNIQUE offering, held_on, student).
- Class slots: weekday 1–7, ends > starts, kind LECTURE/PRACTICAL/TUTORIAL (CHECKs).
- Offering upsert (`RegistrationRepository.upsertOffering`): UNIQUE (course, session, semester); second examiner ≠ lecturer (`ck_offering_examiners`).
- Overload: mentioned in three hints but no endpoint, flag or table implements an HOD overload — a registration above `max_units` can neither be submitted nor approved.

## 7 Notifications
None. Neither submit, approve nor return queues a notice (no `queue_notice` in the registration schema or `RegistrationService`). The student learns of a return on the registration screen.

## 8 Reports and exports
- Class list, attendance register and examination roll as plain CSV (`lib/results.ts` `csv`/`download`) — not the branded `brandedXlsx`.
- `GET /registration/class-list` JSON; `registration.registration_cause(session, semester)` (V143) feeds `/reports/registration/view` (reports group).
- Public verification of a course form: `GET /api/v1/verify/registration` (verify group) — see module 2 §8.

## 9 Configuration
`policy.level_limit` (min_units, max_units, probation_max_units — the last is null for every level in the local DB, so the probation ceiling is inert); `policy.semester.state` OPEN and `registration_closes`/`late_registration_closes` (add/drop window); `catalogue.course.industrial_training` (SIWES semester).

## 10 Data
`registration.course_registration` (UNIQUE student+session+semester; approved_by; returned_comment), `registration.entry` (PK registration+offering; units; entry_type; status), `registration.attendance` (UNIQUE offering+held_on+student; recorded_by), `catalogue.offering` (course, session, semester, lecturer_id, second_examiner_id, allocated_on), `catalogue.offering_teacher` (co-lecturers), `catalogue.class_slot` (ended_at soft end). All audit-attached; `course_registration` also carries the deferment gate and the two "releases held" triggers.

## 11 Scheduled jobs — None.

## 12 Security notes
- Approval is a single HOD step; a lecturer/academic can `create`/`submit` a registration for any student via the API (`APPROVERS`) with no UI — the entries are inserted as given without menu validation (`RegistrationRepository.createRegistration`).
- `DeskController.registrations` confines HOD/lecturer by department server-side; the class list confines department offices by course ownership and lecturers by allocation.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Student draft/choose/submit, carryovers, unit range, fee and deferment gates | IMPLEMENTED | `registration.student_*`, triggers | |
| HOD approve / return with reason | IMPLEMENTED | `RegistrationService`, `RegistrationApprovals.tsx` | Mounted on `/results/approvals` |
| Add/drop window | IMPLEMENTED | `student_add`, `student_drop`, `Screens3.tsx` | |
| Class list with clearance flag, CSV exports | IMPLEMENTED | `ClassListScreen.tsx` | Attendance column on the roll is "—" |
| Attendance register | IMPLEMENTED | `mark_attendance`, `OfferingDesk.tsx` | |
| Timetable slots | IMPLEMENTED | `DeskController` | |
| HOD overload approval | NOT IMPLEMENTED | only hint text | |
| Probation unit ceiling | CONFIGURED BUT UNUSED | `policy.level_limit.probation_max_units` all null | Logic exists in `student_submit` |
| Office-created registration (`POST /registration/course-registrations`) | PARTIALLY IMPLEMENTED | backend only | No UI |
| LOCKED registration status | CONFIGURED BUT UNUSED | grep of `api/` and `db/` finds only checks (`V139`, `V195`), no writer sets `course_registration.status = 'LOCKED'` | Every "APPROVED/LOCKED" test is effectively APPROVED |
| Notifications on approve/return | NOT IMPLEMENTED | | |

## 14 Common problems
- HOD sees "This registration is in another department." — the registration's programme is outside the HOD's resolved department.
- "The industrial-training semester carries exactly N units; this registration carries M." — SIWES semester approval.
- "A student who is deferred does not register (I-STU-2)." — approve refused on status.
- "REGISTRATION UNAVAILABLE: your deferment for … is approved" — cancel the deferment or wait for the return session (the Registry may set `moaum.deferment_override` only at SQL level).
- Student sees no courses: registration not opened for the session/semester (module 7), programme structure empty, or curriculum tag mismatch (`course.curriculum` vs student `curriculum_version`).

## 15 Glossary
Offering (a course in a session and semester); entry (one course on a registration); carryover (failed core course auto-added); basis (Core/Elective/Borrowed/GST per programme); roll/class list (approved registrations of an offering); add/drop window.

---

# 5 Deferments  (API: `deferments` — `DefermentsController`, `DefermentClock`; schema: people (deferment, deferment_document(_blob), deferment_event, deferment_reason, deferment_setting); pages: `student/deferment`, `deferments/**`)

## 1 Purpose
A matriculated student asks to defer one semester or a whole session. The request passes the department (recommend), the faculty (recommend) and the Registry (approve), or is returned for correction, rejected or cancelled at any of those desks. Once approved, a daily clock brings the period into force on its start date: the student's status becomes DEFERRED, course registration for the period is refused by trigger, a reminder goes out before the return date, and the department/faculty/Registry confirms the return, restoring the prior status. Every act is on a write-once trail and each turn tells the student by e-mail and SMS; an approval letter PDF is issued.

## 2 Users and roles
- Student (`STUDENT`): own requests only (`owned()` check → 403 "That deferment request is not yours.").
- Desks (`DESK`): hod, dean, facultyofficer, academic, registrar, dregistrar, records, pgschool, pgsecretary, provost, collegesecretary, super, admin. Bound (`bound()`): academic/registrar/dregistrar/records/super/admin see all; pgschool/pgsecretary only postgraduate students; provost/collegesecretary only faculties with `college_code = 'CHS'`; a faculty office its faculty; a department office its department; anything else nothing (`__none__`).
- Stage (`may()`): hod recommends at SUBMITTED; dean/facultyofficer recommend at DEPT_RECOMMENDED; REGISTRY (academic, registrar, dregistrar, super) approve at DEPT_ or FAC_RECOMMENDED and may act at any stage; reject/correction only at the desk's own stage; cancel Registry only; confirm return hod/dean/facultyofficer/Registry on ACTIVE or APPROVED. records/admin read only (`DefermentsController.java:399-415`).
- Tick: registrar, dregistrar, academic, ict, super (`POST /deferments/tick`).

## 3 Navigation
Deferment `s/deferment` → `/student/deferment` (student, pgstudent). Deferments `t/deferments` → `/deferments` (academic, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super); `/deferments/returns` and `/deferments/{id}` from the desk.

## 4 Screens
**Student `/student/deferment`** (`Deferment.tsx`): PageHead "Deferment"; state banner — "DEFERMENT ACTIVE/APPROVED · period" with "Approval Letter", "Your deferment request requires correction" / "You have a draft deferment request" with "Continue the Request", "DEFERMENT REQUEST UNDER REVIEW" with "Withdraw Request" (prompt "Why do you withdraw this request?" → `POST /me/deferments/{id}/cancel`), "DEFERMENT REQUEST NOT AVAILABLE" with the eligibility reason, or "No active deferment … You have used X of the Y session(s)". Three-step wizard: (1) Student information grid; Deferment type (A semester / The whole academic session), Academic session (CURRENT/PLANNED sessions), Semester, Reason (from `deferment_reason`), Explanation (required when the reason `needs_words` or is OTHER) → "Save and Continue" (`POST /me/deferments` or `PUT /me/deferments/{id}`); (2) Supporting documents — kind select (Medical, Financial, Official letter, Employer letter, Other), file (PDF/JPEG/PNG ≤ 5 MB, at most six) → "Upload" (`POST …/documents` with base64); (3) Review — summary grid, the declaration checkbox "I confirm that the information provided in this deferment request is accurate…", "Submit Deferment Request" (PUT then `POST …/submit`; toast "Deferment request DEF-… submitted successfully"). *Deferment history* table (Reference, Type, Session, Semester, Reason, Status, Requested, Decided, Return, Letter/History) and a per-request history panel.

**Desk `/deferments`** (`Desk.tsx`): PageHead with "Students Due to Return", "Download Excel", "Download PDF" (branded, serial `DEF`, columns S/N, Deferment Number, Student ID, Student Name, Faculty, Department, Programme, Type, Session, Semester, Status, Request Date, Approval Date, Expected Return); tiles Total / Pending / Under review / Approved / Rejected / Active deferments / Returning / Overdue returns; "Waiting at this desk" (rows at the desk's stage) or "Nothing waits at this desk"; filters Session, Semester, Type, Status (incl. "In review" = PENDING pseudo-state), Faculty/Department/Programme (shown per bound), Search; the full list; By programme / By reason / By faculty breakdowns.

**Review `/deferments/{id}`** (`Review.tsx`): breadcrumb, PageHead with StatePil/ReturnPil, "Approval Letter" (APPROVED/ACTIVE/COMPLETED), "Student Record"; *This desk's act* (Comment; buttons per `may`: "Recommend to the Faculty", "Recommend to the Registry", "Approve Deferment", "Request Correction", "Reject", "Cancel Request", "Confirm Return"; approve/reject/return open a confirm modal); *The request*, *Supporting documents*, *The student's record* (status, standing, fees this session from `finance.payment_position`, recent registrations, previous deferments), *The desks*, *History*.

**Returns `/deferments/returns?status=`** (`returns/page.tsx`): filter All/Due/Overdue/Upcoming; table with "Confirm Return" link to the review.

## 5 Workflow and statuses
`people.deferment.state` (`ck_def_state`): DRAFT → SUBMITTED → DEPT_RECOMMENDED → FAC_RECOMMENDED → APPROVED → ACTIVE → COMPLETED; side exits CORRECTION_REQUIRED (back to the student, resubmits), REJECTED, CANCELLED. Return status (`people.deferment_return_status`): UPCOMING / DUE (within `reminder_days` before `return_on`) / OVERDUE (past `return_on + overdue_after_days`) / RETURNED.
- Open/edit `people.deferment_save`: kind SEMESTER/SESSION; session must exist and not be before the CURRENT one ("a session that has passed is not deferred"); semester ≤ the session's semesters; active reason; eligibility on a new request (`people.deferment_eligibility`); extension only when `allow_extension` and of a deferment in force; the sum of used + 1 (session) or 0.5 (semester) must not exceed `max_sessions`; reference `DEF-YYYY-NNNNN` (`platform.next_number('DEFERMENT',…)`); `period_from` from `people.period_start`, return from `people.deferment_return` (next semester of the same session, or semester 1 of the next session); event CREATED/UPDATED. Editing allowed only in DRAFT/CORRECTION_REQUIRED.
- Submit `people.deferment_submit`: explanation ≥ 20 chars when required ("explain the reason in a few sentences"); a document when the reason `needs_document` ("a medical deferment is supported by a document"); declaration ("confirm the declaration before submitting"); → SUBMITTED; tells the student and the department's `hod` assignments.
- Decide `people.deferment_decide(id, action, note, actor, office)`: RECOMMEND (SUBMITTED→DEPT_RECOMMENDED, tells dean), FAC_RECOMMEND (→FAC_RECOMMENDED, tells academic), APPROVE (from either recommended state → APPROVED, tells the student, then runs `deferments_tick` at once), REJECT (in-review states, note required "a rejection carries its reason"), CORRECTION (note required "say what the student must correct"), CANCEL (DRAFT…APPROVED, note required; the student's cancel passes "Withdrawn by the student"; "a deferment in force is not cancelled; the student returns from it"). Java adds `DEF_NOT_YOUR_STAGE` before calling.
- Clock `people.deferments_tick` (daily 06:20 Africa/Lagos, `DefermentClock`, cron `moaum.deferments.cron`): APPROVED with `period_from` reached (or the session CURRENT and the semester OPEN) → ACTIVE, `prior_status` saved, `change_status(…,'DEFERRED', reference, …)` for ACTIVE/PROBATION/ADMITTED matriculated students with `expires_on = return_on` on the status_change row, event ACTIVATED, notice "Your deferment is now in force"; ACTIVE with `return_on` within `reminder_days` and no reminder yet → reminder to the student and to the department.
- Return `people.deferment_confirm_return`: on ACTIVE/APPROVED → COMPLETED, `change_status` back to `prior_status` (ACTIVE/PROBATION/ADMITTED, else ACTIVE) when the student is DEFERRED, event RETURNED, notice "Welcome back — your return from deferment is confirmed".
- Registration gates: triggers `people.deferment_gate_course_registration` (registration.course_registration), `deferment_gate_pg_registration`, `deferment_gate_college_semester/year` call `people.deferment_refuse`, which raises when `people.deferment_covers` (APPROVED or ACTIVE for that session/semester) unless `moaum.deferment_override = on`.
- Documents: PDF/JPEG/PNG only, sniffed by magic bytes (`DEF_DOC_TYPE`), ≤ 5 MB (`DEF_DOC_SIZE`), ≤ 6 (`DEF_DOC_MANY`), only while DRAFT/CORRECTION_REQUIRED/SUBMITTED (`DEF_DOC_CLOSED`); served inline with `Content-Security-Policy: sandbox`.

## 6 Business rules (eligibility, `people.deferment_eligibility`)
Refused with reason when: no record; GRADUATED ("A graduated student does not defer."); WITHDRAWN/VOLUNTARY_WITHDRAWAL/EXPELLED/TRANSFERRED_OUT/DECEASED/RUSTICATED; SUSPENDED; DEFERRED with an ACTIVE deferment and extensions off; no matric number ("Deferment is asked for once you are matriculated…"); a live request already exists ("You already have a deferment request … One request is decided before another is made."); used ≥ `max_sessions` ("You have deferred N session(s) in all; the University allows M."). `people.deferment_used` counts APPROVED/ACTIVE/COMPLETED as 1 (session) or 0.5 (semester). `people.deferment_history_is_written_once` blocks UPDATE/DELETE on `deferment_event`.

## 7 Notifications (all through `people.deferment_tell` → EMAIL + SMS to the student with "Deferment reference: …", and `people.deferment_tell_desk` → EMAIL to office assignments scoped to the student's department/faculty or unscoped)
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Submitted | `deferment_submit` | student; `hod` | EMAIL+SMS; EMAIL | "Your deferment request has been received"; "A deferment request awaits the department" |
| Department recommended | `deferment_decide RECOMMEND` | student; `dean` | | "Your deferment request is recommended by the department"; "A deferment request awaits the faculty" |
| Faculty recommended | `FAC_RECOMMEND` | student; `academic` | | "Your deferment request is recommended by the faculty"; "A deferment request awaits approval" |
| Approved | `APPROVE` | student | | "Your deferment request DEF-… has been approved" |
| Rejected | `REJECT` | student | | "Your deferment request has been rejected" (with reason) |
| Correction | `CORRECTION` | student | | "Your deferment request requires correction" |
| Cancelled | `CANCEL` (from SUBMITTED…APPROVED) | student | | "Your deferment request has been cancelled" |
| In force | `deferments_tick` | student | | "Your deferment is now in force" |
| Return approaching | `deferments_tick` | student; `hod` | | "Your deferment is ending soon"; "A student is due to return from deferment" |
| Return confirmed | `deferment_confirm_return` | student | | "Welcome back — your return from deferment is confirmed" |

## 8 Reports, exports and documents
- Desk list: branded Excel/PDF (above).
- Approval letter PDF (`lib/deferment-letter.ts`, routes `student/deferment/letter/[id]/route.ts` for the student's own, `deferments/[id]/letter/route.ts` for a desk within bound; 409 "The letter is issued once the deferment is approved." before APPROVED): crest, "P.M.B 102119, Makurdi", REF/DATE, "DEFERMENT APPROVAL LETTER", student block, period, effective from, expected return, approved on/by, remarks, four notes, "Registrar" signature line, and a QR/URL `…/verify/deferment/{reference}`. **There is no `/verify/deferment` route** (neither `VerifyController` nor `frontend/src/app/verify/deferment`), so the printed verification link is dead.

## 9 Configuration
- `people.deferment_setting` (single row): max_sessions 2, allow_extension true, reminder_days 14, overdue_after_days 30 — no screen edits it.
- `people.deferment_reason` (ord): MEDICAL (document required), FINANCIAL (words), FAMILY "Family circumstances" (words), MATERNITY "Pregnancy or childbirth" (document), EMPLOYMENT (document), RELOCATION (words), BEREAVEMENT (words), PERSONAL "Personal reasons" (words), OTHER (words) — no screen edits it.
- Cron `moaum.deferments.cron` (default `0 20 6 * * *`).

## 10 Data
`people.deferment` (35 columns: kind, session, semester, reason_code, explanation, declared, state, extension_of, period_from, return_session/semester/on, dept_/fac_/decided_/returned_ at/by/note, correction_note, cancel_note, prior_status, activated_at, reminder_sent_at; UNIQUE reference `^DEF-[0-9]{4}-[0-9]{5}$`), `people.deferment_document` + `_blob` (kind, content type, size 1–5 MB; verified_at/by columns exist but nothing sets them), `people.deferment_event` (write-once trail), `people.deferment_reason`, `people.deferment_setting`. All except the blob attached to the audit spine.

## 11 Scheduled jobs and integrations
`DefermentClock.tick()` — `@Scheduled(cron = "${moaum.deferments.cron:0 20 6 * * *}", zone = "Africa/Lagos")`, runs `people.deferments_tick()` as actor NOBODY/office registrar; failures only logged.

## 12 Security notes
Bound enforced on every desk read and act (`inBound` → 403 "This deferment is outside your office's bound…"); a desk with no resolvable department/faculty sees nothing. Student endpoints check ownership. Document uploads validated by magic bytes and served sandboxed. The letter verification URL is unverifiable (§8).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Student wizard, documents, submit, withdraw | IMPLEMENTED | `Deferment.tsx`, V259 functions | |
| Three-desk decision chain with bounds and stages | IMPLEMENTED | `DefermentsController.may/act` | |
| Clock: activation, DEFERRED status, reminders | IMPLEMENTED | `DefermentClock`, `deferments_tick` | |
| Registration gates (UG, PG, College) | IMPLEMENTED | triggers | |
| Return confirmation and status restore | IMPLEMENTED | `deferment_confirm_return` | |
| Approval letter PDF | IMPLEMENTED | `deferment-letter.ts` | QR points to a non-existent verify route |
| Public verification of a letter | NOT IMPLEMENTED | no `/verify/deferment` | |
| Document verification (verified_at/by) | CONFIGURED BUT UNUSED | columns only | |
| Settings/reasons administration screen | NOT IMPLEMENTED | tables only | |
| Desk report Excel/PDF | IMPLEMENTED | `Desk.tsx` | |

## 14 Common problems
- "Deferment is asked for once you are matriculated…" — ADMITTED student without a number.
- "You already have a deferment request … One request is decided before another is made."
- "a medical deferment is supported by a document" / "explain the reason in a few sentences" (HINT "At least twenty characters.") / "confirm the declaration before submitting".
- "This request is submitted; approve is not this desk's act at that stage." — a Dean opening a SUBMITTED request; the department must recommend first.
- "This deferment is outside your office's bound" — HOD/Dean office lacks a department/faculty scope, or the student is elsewhere.
- Status still ACTIVE after approval — the clock has not run; `period_from` is in the future, or use `POST /deferments/tick`.

## 15 Glossary
Deferment kind (SEMESTER/SESSION); reference DEF-YYYY-NNNNN; in force (ACTIVE); return status (UPCOMING/DUE/OVERDUE/RETURNED); extension; bound (the office's reach: department, faculty, PG school, college, University).

---

# 6 Inter-departmental transfer  (API: `transfers` — `TransferController`; schema: people.transfer_application; pages: `student/transfer`, `student/transfer/letter/[id]`, `transfers/**`)

## 1 Purpose
A matriculated, active student applies to move to another programme. Two decision paths coexist in the code: the current pipeline (V185/V186/V193) — apply → pay the Bursary-set non-refundable fee → current-department HOD approves → new-department HOD approves → Registrar approves → Academic Office approves, which effects the change of programme (and level) on the register — and the older committee/Senate path (review → RECOMMENDED → Senate APPROVED → effect) that the API still exposes and the memo page reports on. The matriculation number never changes.

## 2 Users and roles
- Student (`OFFICE_student`): `GET/POST /me/transfer`, `POST /me/transfer/{id}/fee`.
- Readers (`READERS`): hod, academic, registrar, dregistrar, dvc, vc, ict, admin, super.
- Approve/decline (`APPROVERS`): hod, registrar, dregistrar, academic, super — stage-checked by `mayApprove` (`TransferController.java:71-80`): APPLIED → paid AND hod of `from_dept` (or super); FROM_OK → hod of `to_dept`; TO_OK → registrar/dregistrar; REG_OK → academic. The HOD's department is `scope.actingDept()`.
- Record an application for a paper case (`OFFICERS`): academic, registrar, dregistrar, super.
- Committee review (`SAIC`): academic, registrar, dregistrar, dvc, super; Senate (`SENATE`): registrar, dregistrar, vc, dvc, super; withdraw (`OFFICERS`); effect (`EFFECT`): academic, registrar, dregistrar, ict, super — none of these four has a screen.

## 3 Navigation
Inter-Departmental Transfer `s/transfer` → `/student/transfer` (student); `t/transfers` → `/transfers` (academic, hod, registrar); `/transfers/memo?type=recommended|withdrawn` (no menu); `/student/transfer/letter/{id}` from the student's completed notice.

## 4 Screens
**Student `/student/transfer`** (`Transfer.tsx`): tiles Your department / Processing fee ("Not set yet" when the Bursary has not set `finance.fee_setting.transfer_fee`) / Applications; *Your application* with seven stages (Applied, Payment, Current department, New department, Registrar, Academic office, Completed) and either "Pay the fee online" (`POST /me/transfer/{id}/fee` → reference, then `PayByCard`) or "In progress — …"; "Your transfer is complete" with "Approval letter"; "Your transfer application was not approved" with the decline note; *Apply to transfer* (Course applied for — searchable programme list excluding the student's own, Reason, UTME score optional → `POST /me/transfer`), shown only when matriculated, ACTIVE/PROBATION, no live application and the fee is set; otherwise "Transfers are not open yet" or "You cannot apply to transfer right now".

**Office `/transfers`** (`Transfers.tsx`): RoleLine; tiles for the four desks; segmented tabs Current dept / New dept / Registrar / Academic / Completed / Declined / All; table Student | From → To | Entry · UTME · CGPA | Reason | Stage (with fee reference paid/unpaid) | Approve / Decline (shown only when `canApprove`; decline prompts for a reason); *Record an application* (Student number, Course applied for, Reason, UTME score → `POST /transfers`) for academic/registrar/dregistrar/super.

**Memo `/transfers/memo`** (`memo/page.tsx`, `ReportDoc`): "Recommended List of Inter-Departmental Transfer Candidates" (states RECOMMENDED/APPROVED/EFFECTED) or "Non-Recommended / Withdrawn…" (NOT_RECOMMENDED/WITHDRAWN), issued for "Deputy Vice-Chancellor (Academic) / Chairman, SAIC", print toolbar.

**Letter `/student/transfer/letter/{id}`** (`TransferLetter.tsx`): printable approval letter — text cites Senate/SAIC and a hard-coded fee of ₦10,000 (`naira(10000)`), signed "Deputy Registrar, Academic Office for: Registrar".

## 5 Workflow and statuses
`people.transfer_application.state` (`ck_ta_state`): APPLIED → FROM_OK → TO_OK → REG_OK → EFFECTED (pipeline via `people.approve_transfer`), plus DECLINED, WITHDRAWN, RECOMMENDED, NOT_RECOMMENDED, APPROVED (committee path).
- Apply `people.apply_transfer`: actor required; matriculated and ACTIVE/PROBATION ("only a matriculated, active student may apply to transfer"); reason non-blank; target programme exists and not archived; not the student's own; no live application (23505 "a transfer application is already in progress for this student"); session = CURRENT else entry session; CGPA copied from `assessment.student_gpa`; mode_of_entry from the record.
- Fee `people.transfer_fee_reference`: allowed in APPLIED/FROM_OK/TO_OK/REG_OK/RECOMMENDED/APPROVED; returns the existing reference; refuses when `people.transfer_fee()` is null ("the inter-departmental transfer fee has not been set by the Bursary", HINT "The Bursary sets it on Finance → Fees…"); creates a purpose reference "Inter-departmental transfer to {programme}".
- Approve `people.approve_transfer`: APPLIED needs the fee confirmed ("the non-refundable processing fee has not been paid") → FROM_OK (from_dept_at/by); FROM_OK → TO_OK; TO_OK → REG_OK; REG_OK needs the fee confirmed → updates `people.student.programme_code` and `current_level = coalesce(recommended_level, current_level)` → EFFECTED (acad_at, effected_at/by). Any other state: "application % has no approval pending at this stage (%)".
- Decline `people.decline_transfer`: reason required; from APPLIED/FROM_OK/TO_OK/REG_OK/APPROVED → DECLINED (`TR_NOT_YOUR_STAGE` in Java when not the holding desk; payment not required).
- Committee path: `review_transfer` (APPLIED → RECOMMENDED with level 100–600, or NOT_RECOMMENDED with a note), `senate_transfer` (RECOMMENDED → APPROVED/DECLINED), `withdraw_transfer` (RECOMMENDED/APPROVED → WITHDRAWN), `effect_transfer` (APPROVED with confirmed fee → EFFECTED). No screen calls these; the stage labels "Recommended"/"Not recommended" and the memo page still cater for them.
- Constraints: `ck_ta_different` (from ≠ to), `ck_ta_levels` (100–600), `ck_ta_reason` non-blank.

## 6 Business rules — see §5. Note the letter's fee text (₦10,000) is not the configured fee, and the letter claims Senate/SAIC approval which the pipeline path does not involve.

## 7 Notifications
None — no `queue_notice` anywhere in the transfer functions or controller.

## 8 Reports and documents
Memo (print), approval letter (print); no Excel export.

## 9 Configuration
`finance.fee_setting.transfer_fee` (finance group; null until set — transfers cannot be paid before).

## 10 Data
`people.transfer_application` (33 columns incl. session, from/to programme, from_level, reason, mode_of_entry, utme_score, cgpa, state, recommended_level, committee/senate/decline notes, fee_reference, per-desk at/by timestamps, withdrawn_why). Audit-attached.

## 11 Scheduled jobs — None.

## 12 Security notes
The office list `/transfers` is University-wide for every reader including HOD; only the buttons are stage-scoped (server re-checks). `stageOf` reads the fee state via `finance.reference_state`.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Student application, fee reference and payment | IMPLEMENTED | `Transfer.tsx`, `apply_transfer`, `transfer_fee_reference` | |
| Four-desk approval pipeline with department scoping | IMPLEMENTED | `approve_transfer`, `mayApprove` | |
| Decline with reason | IMPLEMENTED | | |
| Record a paper application | IMPLEMENTED | `Transfers.tsx` | |
| Committee review / Senate / withdraw / effect | PARTIALLY IMPLEMENTED | endpoints only, no UI | Memo page reports on them |
| Approval letter | PARTIALLY IMPLEMENTED | `TransferLetter.tsx` | Hard-coded ₦10,000 and Senate/SAIC wording |
| Student notifications | NOT IMPLEMENTED | | |
| TRANSFERRED_OUT status | not used by the pipeline | | Student stays ACTIVE with a new programme |

## 14 Common problems
- "Transfers are not open yet" / "the inter-departmental transfer fee has not been set by the Bursary" — set `transfer_fee` on Finance → Fees.
- "This application is not ready at your desk. Awaiting payment." — the current department cannot approve before the fee is confirmed.
- "a transfer application is already in progress for this student".
- After EFFECTED the student's menu still shows the old structure until the next session's registration opens for the new programme.

## 15 Glossary
Pipeline desks (current department, new department, Registrar, Academic office); SAIC (Special Admissions and Admission Irregularities Committee — the legacy path); processing fee.

---

# 7 Academic structure and the course catalogue  (API: `catalogue` — `CatalogueController`; schema: catalogue (course, course_offer, offering), ref (faculty, department, programme — via `ref.upsert_*`/`import_*`/`delete_*` functions); pages: `structure/faculties|departments|programmes`, `catalogue/upload`, `catalogue` (department courses), `catalogue/structure`, `eligibility`)

## 1 Purpose
Faculties, departments and programmes are the reference structure; courses belong to one department; a programme's structure (`catalogue.course_offer`) says which courses it offers at which level, on what basis (Core/Elective/Borrowed/GST) and for which curriculum track; an offering opens a course for a session and semester and is what registration reads. Since commit `8c2b6fa` only the Director of ICT creates, uploads, archives or removes faculties, departments, programmes and course structures; departments (HODs) create courses (into BOARD state), make them live, end/restore them, bind them into structures, tag curriculum and assessment split; opening registration for a session is a bulk creation of offerings.

## 2 Users and roles
- `UPLOADERS` = ict only: `POST /catalogue/faculties|departments|programmes` (+`/import`), `DELETE …/{code}`, `POST /programmes/{code}/archive`, `POST /catalogue/import` (course structure). The screens enforce `MAY = ["ict"]` and show "This desk is for the Directorate of ICT…" otherwise (the course-upload note still says "and HODs", stale).
- `OWNERS` (course/structure writes): hod, dean, academic, dregistrar, registrar, admin, super — an HOD confined to their own department (`assertHodOwns` → CAT_DEPT "A Head of Department manages the catalogue of their own department only.").
- `OPENERS` (open registration): ict, super, admin, hod, dean, academic, registrar, dregistrar.
- `READERS`: the above plus lecturer, exams, facultyexams, facultyofficer, records, dvc, vc; HOD reads only their faculty/department/programmes (`hodDept()` filters).
- Upload coverage: ict, admin, super, academic, registrar, dregistrar, dvc, vc, hod, dean.

## 3 Navigation
ict menu: Upload course structure `t/courseupload` → `/catalogue/upload`, Faculties `t/facultyupload` → `/structure/faculties`, Departments `t/departmentupload` → `/structure/departments`, Programmes `t/programmeupload` → `/structure/programmes`. hod menu: Department Courses `t/deptcourses` → `/catalogue`, Programme Structure `t/structure` → `/catalogue/structure`, Who May Register It `t/eligibility` → `/eligibility` (also dean).

## 4 Screens
**Faculties `/structure/faculties`** (`Faculties.tsx`): RoleLine; Add/Edit form (Code — cannot change when editing; Name) → `POST /catalogue/faculties` (upsert); "Download template" (Code, Name); "Upload faculties (.xlsx)" → `/faculties/import` (message "N faculties saved · M rows had no name"); table Code | Name | Departments | Programmes with edit and delete icons (delete disabled unless empty; client says "still has N programme(s)…"; server `ref.delete_faculty`); "Download Excel"/"Download PDF" (branded, serial FAC).

**Departments `/structure/departments`** (`Departments.tsx`): Code, Name, Faculty (code or name); template (Code, Name, Faculty); upload .xlsx/.csv → `/departments/import` (counts saved, bad_code, no_faculty); table with edit/delete (`ref.delete_department` — only when no programme and no course); exports serial DEP.

**Programmes `/structure/programmes`** (`Programmes.tsx`): Code `^C[0-9]{5}$`, Name, Faculty select, Department code/name (optional; "blank = the faculty"), Category UNDER GRADUATE / POST GRADUATE, Minimum score; template; upload; table Code | Programme (archived pill) | Faculty | Department | Category | Min with Edit, Archive/Restore (`/programmes/{code}/archive`), Delete (`ref.delete_programme`, "only if nothing hangs on it"); exports serial PRG.

**Upload course structure `/catalogue/upload`** (`catalogue/upload/Courses.tsx`): Programme (searchable, from `/admissions/programmes`), Curriculum select (CCMAS — MOAU cohorts / CCMAS — BSU cohort / BMAS / CCMAS any cohort); "Download template" (Course Code, Course Title, Units, Status, Level, Semester, Lecture Hours, Practical Hours); "View loaded courses" (`/catalogue/offered`); "Choose the course document (.docx or .xlsx)" — a CCMAS .docx is parsed by headings ("100 Level", "First Semester") and tables; an .xlsx by column names, optionally with `programme_code` and `course_category`/`curriculum` columns to load many programmes at once; preview panel (Courses read / Levels / With a code the rule rejects) → "Load N courses" → one `POST /catalogue/import` per programme+curriculum group; programmes not on the register are held back and listed ("Download the list"); *Open course registration for a session* (Session YYYY/YYYY, Semester → `POST /catalogue/open-registration`, message "N courses opened for …"); "All courses — Excel/PDF" from `/catalogue/catalogue-export` (serial CAT); per-programme loaded list export (serial CRS).

**Department courses `/catalogue?dept=`** (`DeptCourses.tsx`): department picker (single department shown fixed for an HOD), filters Level/Semester/Kind/Programme; "Make N Live" (`/courses/live-all?dept`), "+ New course" modal (Code "Three letters, a space, three digits — e.g. CSC 311", Units, Title, Level 100–600, Semester First/Second, Kind Core Courses/Required/Elective/GST → `POST /catalogue/courses`, message "… created — at the Faculty Board"); tiles Courses owned / Live / Awaiting approval / Live, no lecturer; *Duplicate courses* panel (groups by level, semester, normalised title and curriculum; "End N duplicate courses" → `/duplicates/end?dept`); bulk buttons "Set to CCMAS/BMAS" (`/curriculum/bulk`) and "CA 40 / Exam 60", "CA 30 / Exam 70" (`/split/bulk`); table Code | Title (binding pills linking to the structure, or red "Not bound to any programme — no student sees it at registration") | Units | Semester | Level | Kind | Curriculum select (— shared / CCMAS / BMAS → `/courses/{code}/curriculum`) | CA / Exam select (`/courses/{code}/split`) | Lecturer | State (Live / At the Faculty Board / At Senate / Ended) | Make live / End / Restore.

**Programme structure `/catalogue/structure?prog=`** (`Structure.tsx`): programme picker, Track filter; tiles Courses bound / Levels / Borrowed / Without a semester; *Bind a course into the structure* (course search across the University `/courses/search?q` ≥ 2 chars; Level; Basis Core/Elective/Borrowed/GST — defaults to Borrowed when another department owns it; Track "Every track" or a `policy.curriculum_track` → `POST /structure/bind`); per level panels with limits, per semester unit totals with "core alone exceeds the N-unit maximum" / "under the N-unit minimum" warnings; rows Code | Title | Units | Basis | Track | Owner | State | Remove (`DELETE /structure/bind?programme&course&level`).

**Who may register it `/eligibility?dept&course`** (`Eligibility.tsx`): department and course pickers; tiles Owning department / Eligible cohorts / Registered / From other departments; table Programme | Department | Faculty | Level | Basis | Registered | Relation (from `/catalogue/courses/{code}/eligibility`). Read-only.

## 5 Workflow and statuses
- `catalogue.course.state` (`ck_course_state`): BOARD → SENATE → LIVE → ENDED (→ LIVE by restore). `create_course` writes BOARD; `make_course_live` lifts BOARD/SENATE → LIVE ("course % has ended; restore it instead of making it live" / "no course % awaiting approval to make live"); `end_course` sets ENDED + `ended_on` (`ck_course_ended` couples them); `restore_course` ENDED → LIVE. Nothing writes SENATE except a direct upsert with `state` (`RegistrationController.course` with the LIVE guard). The structure import writes LIVE directly (V172).
- Making a course live or restoring it also creates the current session's offering for the course's semester if a `course_offer` exists (`ensureCurrentOffering`, `makeDeptLive`).
- Open registration `registration.open_course_registration(session, semester)`: actor required; semester 1–3; session must exist ("no academic session % on the calendar — open the session first"); inserts an offering for every non-ended course of that semester bound to some programme whose track is null or still has a student of that programme and track; audit trigger disabled for the bulk insert; idempotent.
- Programme archive keeps the code (`ref.set_programme_archived`); delete only when nothing hangs on it (`ref.delete_programme`).

## 6 Business rules and validations
- `catalogue.create_course`: code `^([A-Z]{3})\s*([0-9]{3})$` normalised to "ABC 123" ("a course code is three letters, a space and three digits, like CSC 311 — % does not fit"); units 0–12 ("a course is worth between 0 and 12 units"); unique code (23505 "a course with the code % already exists"). The table CHECK is wider (`^[A-Z][A-Z0-9 /-]{2,19}$`) so imported codes like `BSU-SOC-101` or `CSC 309/CMP 441` are allowed by the import but not by the form.
- `catalogue.import_courses_rows`: programme by code or name ("no programme is coded or named %"); department must exist; per row: code normalised, units capped at 12, level defaults 100 (only 100–600 kept), semester defaults 1, status letter C/R/E/G → kind Core/Required/Elective/GST (GST also by code prefix), basis Core/Elective/GST; upserts `course` (keeps LIVE/ENDED state, lifts BOARD/SENATE to LIVE) and `course_offer`; each row in a savepoint so one bad row is counted (`skipped`, `first_error`). `import_courses` then stamps the track on the offers (CCMAS_BSU / CCMAS_MOAU / BMAS, or null for CCMAS/any).
- Bind: basis must be one of four (CAT_BASIS); an ENDED course is refused (CAT_ENDED); track upper-cased, not validated against `policy.curriculum_track`.
- Unbind: refused while a student of that programme and level is registered on the course this session (CAT_BOUND_IN_USE "N students of P at L level are registered on C this session; the binding stays while they are.").
- Curriculum tag: CCMAS / BMAS / CCMAS_BSU / CCMAS_MOAU accepted (CAT_CURRICULUM); a track collapses to CCMAS on the course.
- Split: `ca_max` 0–100 (CAT_SPLIT; CHECK `ck_course_ca_max`); default 40.
- Duplicate detection groups live courses by level, semester, normalised title and curriculum; the keeper is the least "messy" code (no `/` or `-`), then `^[A-Z]{2,4} [0-9]{3}$`, then shortest.
- Faculty/department/programme upserts and imports live in `ref.*` functions (not read here; the counters they return are `saved`, `bad`, `bad_code`, `no_faculty`).

## 7 Notifications — None.

## 8 Reports and exports
Faculties/Departments/Programmes branded Excel+PDF (FAC/DEP/PRG); courses offered to a programme (CRS); the whole catalogue (CAT: Faculty, Programme Code, Programme, Level, Semester, Course Code, Title, Units, Kind, Basis, Curriculum); templates for each upload; `GET /catalogue/upload-coverage` (totals, by faculty, pending list) consumed by the ICT/management dashboards (other group).

## 9 Configuration
`policy.curriculum_track` (BMAS, CCMAS_BSU, CCMAS_MOAU with a framework), `policy.level_limit` (shown on the structure), `ref.programme.category` (UNDER GRADUATE / POST GRADUATE), `min_score`.

## 10 Data
`catalogue.course` (PK code; units, semester 1–3, level, dept_code, kind Core/Required/Elective/GST, state, ended_on, lecture/practical hours, curriculum CCMAS/BMAS/null, industrial_training, ca_max), `catalogue.course_offer` (PK course+programme+level; basis; track → policy.curriculum_track), `catalogue.offering`, `ref.faculty` (with `matric_code`, `matric_series`), `ref.department`, `ref.programme` (archived, category, min_score, matric_* columns). Audit-attached (catalogue.*, ref.* per triggers.psv).

## 11 Scheduled jobs — None.

## 12 Security notes
Structure uploads are ICT-only at the API; HOD confinement is enforced in every course write; `courses/search` is University-wide by design. `newDepartment` still calls `assertHodOwns` although only ICT can reach it.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Faculty/department/programme create, import, edit, archive, delete | IMPLEMENTED | `CatalogueController`, `structure/*` | ICT only |
| Course structure upload (.docx/.xlsx, multi-programme) | IMPLEMENTED | `catalogue/upload/Courses.tsx`, `import_courses` | Screen note still names HODs |
| Open course registration | IMPLEMENTED | `open_course_registration` | On the ICT upload screen; HOD/academic have the right but no button elsewhere |
| Department courses: create, live, end, restore, curriculum, split, duplicates | IMPLEMENTED | `DeptCourses.tsx` | |
| SENATE course state | CONFIGURED BUT UNUSED | no UPDATE to `state = 'SENATE'` in `db/` or `api/` (only `V172` lifts it) | Courses go BOARD → LIVE directly |
| Programme structure bind/unbind with tracks | IMPLEMENTED | `Structure.tsx` | |
| Eligibility view | IMPLEMENTED | `Eligibility.tsx` | Title in `titles.ts` is a fixed "Who may register CSC 311" |
| Upload coverage | IMPLEMENTED (API) | `uploadCoverage` | Screen in another group |
| Course/offer/offering direct upsert (`/registration/courses…`) | PARTIALLY IMPLEMENTED | `RegistrationController` | No UI; teaching allocation UI is the allocation group's |

## 14 Common problems
- "no programme is coded or named X" on upload — the programme is not on the register (upload programmes first); the screen holds such rows back.
- "the programme % has no department on the register to own its courses" — set the programme's department.
- Course shows "Not bound to any programme — no student sees it at registration" — bind it on the structure.
- "N students … are registered on … this session; the binding stays while they are." on Remove.
- Students see nothing after upload — open registration for the session/semester; a course tagged CCMAS is hidden from a BMAS student and vice versa.
- New-course form refuses codes like "BSU-SOC 101" — the form rule is stricter than the import.

## 15 Glossary
Structure (course_offer rows of a programme); basis; track; offering; BOARD/SENATE/LIVE/ENDED; CA split (`ca_max`); duplicate keeper; upload coverage.

---

# 8 Course spaces (LMS)  (API: `lms` — `LmsController`, `MeTeachingController`; schema: lms (material, material_blob, assignment, submission, submission_blob, access); pages: `lms/**`, `student/courses/**`)

## 1 Purpose
Every offering with approved registrations is a course space. The lecturer allocated to the offering publishes material (a file ≤ 5 MB or a link, optionally as a draft), sets assignments with a weight in the 40-mark continuous assessment, marks submissions, watches engagement, and promotes the weighted gradebook total into the CA column of the score sheet. Students on the roll read material (every read counted), submit once (replaceable until marked, late within the window at a penalty) and see marks and feedback.

## 2 Users and roles
- `TEACHERS`: lecturer, hod, dean, academic, super for `/api/v1/lms/**`; `requireTeaches` lets the allocated lecturer/second examiner/co-lecturer act and lets hod/dean/academic/super act on any space (LMS_NOT_YOURS otherwise).
- Student: `/api/v1/me/courses/**`, on-roll check (`lms.on_roll`: entry REGISTERED/APPROVED on an APPROVED/LOCKED registration).
- `GET /api/v1/me/teaching` is `isAuthenticated()` (any signed-in person; returns their allocations).

## 3 Navigation
Course Spaces `t/lms` → `/lms` and Upload Material `r/upload` → `/lms?tab=upload` (lecturer, hod, dean); `/lms/{offering}` from "Open the space"/"Upload material". Student: My Courses `s/courses` → `/student/courses`, `/student/courses/{offering}`.

## 4 Screens
**`/lms`** (`lms/page.tsx`): table Course | Enrolled | Materials | Assignments | "Open the space"/"Upload material" from `GET /lms/teaching?session` (scope session). Empty: "No course is allocated to you in S…".
**`/lms/{offering}`** (`CourseSpaceDesk.tsx`): header tiles Materials published / Assignments / Submissions / Never opened the space; *Upload course material* (Title, Week, Kind Notes/Slides/Reading/Video/Audio/Other, Description, file drop ("up to 5 MB here"), "Or an address", checkbox "Publish to the N registered students now; unticked, it is saved as a draft" → `POST /lms/offerings/{o}/materials`); *Published material* (Item | Week | Size | Read by | Published/Draft | Download/Open link, Publish, Withdraw → `/publish`, `/end`); *Assignments* (table + form: New assignment title, Closes (datetime), Weight % of CA, Kind Individual/Pairs/Group, Brief, Marked out of, Late window hours, Late penalty % → `POST …/assignments`; "Mark"/"Review" opens a modal listing submissions with file link, text, Mark and Feedback → `…/submissions/{s}/mark`); note "The gradebook total becomes the continuous assessment mark" with "Promote CA total to the score sheet" (enabled only when `sheet_stage = ENTRY`); *Engagement — students at risk* (Last opened, Materials %, Submissions, Attendance %, CA so far, Flag High risk / Watch / On track — computed client-side: never opened with material published, attendance < 50 %, or no submission while assignments closed → High risk; < 75 % or missing submissions → Watch). Panel header notes "Similarity check is not on the portal".
Student screens: module 2 §4.

## 5 Workflow and statuses
Material: draft (`published_at` null) → published (`published_by`) → ended (`ended_at`); students see published, unended material only. Assignment: open at `opens_at` (default now) → closes at `closes_at` → late window `late_hours` (default 48) with `late_penalty` % (default 10) → ended. Submission: one per assignment and student (UNIQUE); `lms.submit` deletes and replaces the earlier one unless marked ("this submission is marked; it is not replaced"); `late` flagged after `closes_at`; after the late window "the assignment closed on % and the late window of % hours has passed"; before opening "the assignment opens on %"; not on the roll "you are not registered and approved for this course". Reads are counted in `lms.access` (`countRead`).
Gradebook `lms.gradebook`: per student on the roll, total = Σ round(min(mark, out_of)/out_of × weight × (1 − late_penalty/100 if late)); `lms.promote_ca` writes a new `assessment.score` version with `ca = least(40, round(total))` for each student whose CA differs, only on the MAIN sheet at stage ENTRY ("no score sheet exists for this offering yet" / "the score sheet has left the lecturer; the gradebook is not promoted into it"), reason "Promoted from the course space gradebook (… over …% marked)".

## 6 Business rules and validations
File types (`LmsService.TYPES`): pdf, jpeg, png, text/plain, csv, docx, pptx, xlsx, zip, mp3, mp4 (LMS_FILE_TYPE); size 1 byte–5 MB (LMS_FILE_SIZE; DB CHECK 5 242 880); material needs a file or a link (LMS_MATERIAL_EMPTY); title non-blank; kind in the six (LMS_KIND); assignment needs title, closes, weight (LMS_ASSIGNMENT); weight 1–40, out_of 1–1000, penalty 0–100, late hours 0–720, closes > opens (CHECKs); mark ≥ 0 (LMS_MARK; not capped at out_of at write, capped in the gradebook); submission needs text or file (LMS_SUBMISSION_EMPTY). No virus scan or similarity check.

## 7 Notifications — None (no notice on publish, assignment, mark or promotion).

## 8 Reports and exports — None; the engagement panel is on-screen only (its note says it "feeds the early-warning report" — no such report was found in this group).

## 9 Configuration — None (limits are constants/CHECKs).

## 10 Data
`lms.material` (+`material_blob` bytea), `lms.assignment`, `lms.submission` (+`submission_blob`; UNIQUE assignment+student; mark/marked_at coupled by CHECK), `lms.access` (not audit-attached; the blobs are not either). Roll derived from `registration.entry`/`course_registration`.

## 11 Scheduled jobs — None.

## 12 Security notes
Files are served inline with the stored content type and a sanitised filename (no `X-Content-Type-Options`/CSP sandbox headers, unlike deferment documents). Student reads are gated by the roll; lecturer reads by allocation or office. `/me/teaching` is open to any authenticated principal (returns only that person's offerings).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Materials upload/publish/withdraw/read counting | IMPLEMENTED | `LmsService`, `CourseSpaceDesk.tsx`, `SpaceScreen.tsx` | 0 rows in local DB |
| Assignments, submissions, marking, late window | IMPLEMENTED | `lms.submit`, `LmsService.mark` | |
| Gradebook → CA promotion | IMPLEMENTED | `lms.promote_ca` | Depends on the results score sheet |
| Engagement/at-risk panel | IMPLEMENTED (screen only) | `CourseSpaceDesk.tsx` | No report or notification |
| Similarity check | NOT IMPLEMENTED | panel text | |
| Notifications to students | NOT IMPLEMENTED | | |

## 14 Common problems
- "This course space belongs to the lecturer the department allocated." — the person is not on the offering; the HOD allocates (allocation group).
- "no score sheet exists for this offering yet" when promoting — the examination session has not been opened.
- Student cannot see a space — registration not APPROVED, or nothing published.
- "A file is between 1 byte and 5 MB" — link large files by address instead.

## 15 Glossary
Course space; roll; draft material; late window; weight (% of the 40 CA marks); promotion (gradebook → score sheet CA).

---

# 9 Library  (API: `library` — `LibraryController`; schema: library (item, copy, loan, reservation, setting); pages: `library/circulation`, `student/library`)

## 1 Purpose
A small circulation system: a catalogue of items with accessioned copies, loans to a student or a member of staff under one rule (loan days, fine per day, items at once, renewals), returns that post a fine, reservations that hold the next returned copy, renewals, fine references paid through the Bursary's payment references, and the library standing that feeds the LIBRARY clearance unit.

## 2 Users and roles
`DESK` (issue, return, renew, catalogue): library, services, admin, super; waive a fine and restate the rule: library, super; `READERS` of the desk: library, services, registrar, dregistrar, academic, bursar, admin, super, ict, audit; student: own loans/reservations/fine references.

## 3 Navigation
Circulation `t/circulation` → `/library/circulation` (library, services); Library `s/library` → `/student/library`.

## 4 Screens
**Circulation** (`Circulation.tsx`): RoleLine; tiles Copies in stock / On loan / Overdue / Fines unpaid; *Issue, return, renew* (Accession number e.g. CSC/004182, Patron "Matriculation, admission or staff number"; Issue → `POST /library/loans`, Return → `POST /library/returns` ("Returned N days late — fine ₦x posted"), "Look the patron up" → `?patron=` shows standing and loans with Renew / Waive); *Circulation today*; *Overdue* (Days, Fine so far); *Fines unpaid* (reference or "No reference yet", Waive with prompt); *Catalogue* (search `?q=`; add item: Title, Author, Edition, Year, ISBN, Subject, Kind Book/Journal/Thesis/Audiovisual/Reference, Shelf, "Accession numbers of the copies" comma-separated → `PUT /library/items`); *The rule in force* (Loan days, Fine per day, Items at once, Renewals → `PUT /library/setting`, librarian only).
**Student** — module 2 §4.

## 5 Workflow and statuses
`library.copy.state`: AVAILABLE → ON_LOAN → (RESERVED when a WAITING reservation exists at return) → AVAILABLE; LOST/WITHDRAWN (`ended_on` needs `ended_reason`). `library.reservation.state`: WAITING → READY (copy held) → FULFILLED (issued to that student); CANCELLED/EXPIRED exist in the CHECK but nothing sets them. Loan: issued (`due_on = today + loan_days`) → renewed (`renewals+1`, due + loan_days) → returned (`fine = days_overdue × fine_per_day` when > 0) → fine settled (`library.settle_by_reference` — called by the payments side when the reference confirms) or waived.

## 6 Business rules and validations
`library.issue`: copy exists ("no copy % on the shelf list"); AVAILABLE or RESERVED ("copy % is on loan…"); exactly one patron; for a student: no overdue item ("the patron has % overdue item(s); nothing is issued until they are returned"), fewer than `max_loans` ("the patron already has % items on loan, the most the rule allows"), no unpaid fine ("an unpaid fine stands against the patron"); a RESERVED copy only to the READY reserver ("copy % is held for the patron who reserved it"). `library.renew`: not beyond `max_renewals`, not overdue ("an overdue item is returned, not renewed"), nobody else waiting. `library.reserve`: item exists; no AVAILABLE copy ("a copy is on the shelf; borrow it rather than reserving it"); not already on loan to the student (23505). `library.fine_reference`: only a standing fine; reuses an unexpired reference; purpose "Library fine {loan id}". `library.waive_fine`: reason required. Setting CHECK: loan_days 1–120, fine ≥ 0, max_loans 1–20, max_renewals 0–5. Accession `^[A-Z]{2,5}/[0-9]{4,8}$`. `LIB_NO_PATRON` "No student or member of staff carries the number …". `library.standing(student)` → clear when nothing on loan and no unpaid fine (used by clearance text; the LIBRARY clearance unit itself is signed manually — module 12).

## 7 Notifications — None.
## 8 Reports and exports — None (tables on screen only).
## 9 Configuration — `library.setting` single row: loan_days 14, fine_per_day 50.00, max_loans 3, max_renewals 1 (editable on the desk).
## 10 Data — `library.item`, `library.copy` (PK accession), `library.loan` (student or person), `library.reservation`, `library.setting`; all audit-attached. Local DB: 0 items, 0 loans.
## 11 Scheduled jobs — None (fines are computed on return, not nightly).
## 12 Security notes — students reach only their own loans (`loanOwner` check). Fine settlement depends on the payments module calling `settle_by_reference` (not verified here).
## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Catalogue, copies, issue, return, renew, reserve, fines, waive, rule | IMPLEMENTED | `LibraryService`, `library.*` functions, `Circulation.tsx` | Unused in the local data |
| Reservation expiry/cancel | CONFIGURED BUT UNUSED | CHECK states only | |
| Library clearance auto-sign from standing | NOT IMPLEMENTED | clearance is manual | The student screen text implies it |
## 14 Common problems — the issue refusals above; "no fine stands against this loan" when generating a reference for a settled fine.
## 15 Glossary — accession; patron; standing; READY reservation.

---

# 10 SIWES / industrial training  (API: `siwes` — `SiwesController`; schema: assessment.siwes_supervisor (results group table), catalogue.course.industrial_training; pages: `siwes`)

## 1 Purpose
A SIWES course (flagged `industrial_training`) is supervised, not taught: the HOD or SIWES Coordinator assigns a supervisor from the department's lecturers to each registered student; the supervisor records an assessment out of 40 (the CA part) and the coordinator a practical report mark out of 60 (the exam part) onto the offering's ordinary score sheet; the row is GRADED only when both parts are present. The SIWES semester also fixes the student's registration to exactly the SIWES units (module 4).

## 2 Users and roles
`ASSIGNERS`: hod, siwes, academic, registrar, dregistrar, admin, super — department offices confined by `scope.deptWithin`; supervisor endpoints (`/siwes/mine`, `PUT /siwes/mine/students/{s}/score`) `isAuthenticated()` with an ownership check (`SIWES_NOT_YOUR_STUDENT`).

## 3 Navigation
SIWES Supervision `r/siwes` → `/siwes` (hod, siwes). The supervisor's own mark entry is on the lecturer dashboard (`dashboards/Siwes.tsx`, route `r/mysiwes` — dashboards group).

## 4 Screens
`/siwes?session&sem&offering` (`Siwes.tsx`): Session, Semester (First/Second), SIWES course pickers; tiles Students / Supervisors assigned / Score sheet (Entry open / Verification / Published / "Not open") / Course; table Matric | Name | Programme | Supervisor (searchable select → `PUT …/supervisor`) | Assessment /40 | Practical /60 (input + Save → `PUT …/practical`; a change of an existing mark prompts "Why is X's practical mark changing…") | Total. Inputs disabled unless the sheet is at ENTRY.

## 5 Workflow and rules
`record()`: MAIN score sheet must exist (SIWES_NO_SHEET "The SIWES score sheet is not open yet.") and be at ENTRY (SIWES_SHEET_NOT_AT_ENTRY); the other part is carried forward; unchanged → `written:false`; a changed own part needs a reason (SIWES_AMENDMENT_SAYS_WHY); new `assessment.score` version with outcome GRADED when both parts present else INCOMPLETE. Marks 0–40 / 0–60 by bean validation. Assignment via `assessment.assign_siwes_supervisor`.

## 6–8 Notifications, exports — None.
## 9 Configuration — the course flag `catalogue.course.industrial_training`: set only by migrations V155–V157 (seed); no Java endpoint, upload column or screen writes it (grep of `api/src` and `frontend/src`), so a new SIWES course needs a migration or a direct SQL change by ICT.
## 10 Data — `assessment.siwes_supervisor` (offering, student, supervisor); scores in `assessment.score`.
## 12 Security — department scoping on offerings; a supervisor can score only assigned students; `/siwes/mine` for any authenticated principal.
## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Supervisor assignment and pool | IMPLEMENTED | `SiwesController.assign/supervisorPool` | |
| Coordinator practical mark, supervisor assessment | IMPLEMENTED | `record()` | Depends on an open exam session |
| Flagging a course as industrial training | NOT IMPLEMENTED (data only) | column set by V155–V157 seed only | No endpoint or screen writes it |
| Logbooks/placement records | NOT IMPLEMENTED | | |
## 14 Common problems — "No SIWES course this session and semester" (no `industrial_training` course offered); "The SIWES score sheet is not open yet."
## 15 Glossary — SIWES semester; supervisor part (/40); practical part (/60).

---

# 11 Graduation and alumni  (API: `graduation`, `alumni`; schema: records.graduand; pages: `graduation`, `alumni`, `student/graduation`)

## 1 Purpose
The degree audit computes, for every student enrolled in a session at the final level of their programme, the CGPA over published results and the first course not yet published, and records a graduand row with an unmet requirement when the audit fails. The Registry approves the list on a Senate minute: each passing graduand becomes GRADUATED and is told. The alumni register lists the Senate-approved graduands.

## 2 Users and roles
View (`READERS`): academic, registrar, dregistrar, dvc, vc, records, dean, hod, ict, admin, super — bound by `OfficeScope.bound`; audit (`OFFICE`): academic, registrar, dregistrar, records; approve: registrar, dregistrar, academic. Alumni readers: registrar, dregistrar, academic, records, vc, dvc, audit, deputyaudit, admin, super.

## 3 Navigation
Graduation `t/graduation` → `/graduation` (academic, dean, dvc, pgschool, pgsecretary, records "Graduation Records", vc); Alumni `t/alumni` → `/alumni` (services menu — although `services` is not in the API's reader list, so the screen would fail for that office); Graduation `s/graduation` for pgstudent menu and the UG dashboard tile.

## 4 Screens
**`/graduation`** (`Graduation.tsx`): RoleLine; scope bar (session); notes (N finalists have an unmet requirement / Every finalist audited… / No degree audit has been run); tiles Finalists / Audit passed / Outstanding requirement / Awaiting clearance; *Degree audit exceptions* (Student | Programme | Unmet requirement | CGPA | Review → `/students/{id}`); *Classification summary* (bands from `policy.classification_band` in force: Class | Students | Share | CGPA range); buttons "Run the degree audit for S" (`POST /graduation/sessions/{s}/{y}/audit`) and "Send the list to Senate" (modal Senate minute e.g. "SEN/2027/…" → `/approve`).
**`/alumni`** (`Alumni.tsx`): tiles On the register / Graduating sessions / Latest cohort / Showing; search, faculty, session filters (client-side over `/api/v1/alumni`); table Name | Matric number | Programme (award) | Faculty | Class | Session.

## 5 Workflow and statuses
`records.graduand.senate_state`: AWAITING → APPROVED (or REFERRED — nothing sets it); UNIQUE student+session; APPROVED requires a minute, no unmet and a CGPA (`ck_grad_approved`).
- Audit (`GraduationService.audit`): finalists = `people.enrolment` rows of the session at the final level (600 for C00061 MBBS, 500 for names starting "LL.B" or containing "PHARMACY", else 400 — hard-coded in `GraduationRepository.finalists` and `records.student_graduation`); standing from `assessment.course_final(...)` at PUBLISHED; unmet = "{course} not graded" | "No published result on the record" | "CGPA x — below pass threshold" (< 1.00); upsert keeps `unmet` of an already APPROVED row; award = programme name.
- Approve (`records.approve_awards`): minute required ("the graduation list is approved on a Senate minute, and none was cited"); every AWAITING row with no unmet and a CGPA → APPROVED; each student not yet GRADUATED → `change_status(GRADUATED, minute, 'Award approved by Senate')`; notices sent. Certificate printing/collection is the credentials group; `trg_graduand_flags_documents` flags issued documents on change (V262).
- The audit checks only "every registered course published" and CGPA ≥ 1.00; core-course, credit-minimum, GST and project rules named on the screen ("checks every curriculum rule — core courses, elective credit minima, GST, project…") are not implemented.

## 7 Notifications
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Award approved | `records.approve_awards` | each graduand | EMAIL + SMS | "Senate has approved your award" (award, minute, CGPA, class; "Your certificate is printed once every unit has cleared you for convocation…") |

## 8 Reports — none exported here (DTable only).
## 9 Configuration — `policy.classification_band` (versioned, results group); final levels hard-coded.
## 10 Data — `records.graduand` (cgpa 0–5, award, unmet, senate_state, senate_minute); audit-attached; 7 rows locally.
## 12 Security — scope bound on view; approval limited to three offices.
## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Degree audit (published results + CGPA ≥ 1) | PARTIALLY IMPLEMENTED | `GraduationService.audit` | Curriculum rules claimed on screen are not checked; final level hard-coded |
| Senate approval → GRADUATED + notice | IMPLEMENTED | `records.approve_awards` | |
| Classification summary | IMPLEMENTED | `bands()` | |
| REFERRED state | CONFIGURED BUT UNUSED | CHECK only | |
| Alumni register | IMPLEMENTED | `AlumniController` | `services` menu lists it but the API denies that office |
| Student graduation view | IMPLEMENTED | module 2 | |
## 14 Common problems — "No degree audit has been run for S"; "the graduation list is approved on a Senate minute, and none was cited"; a finalist missing from the audit: no `people.enrolment` row for the session at the final level (enrolment is created by roll-over/`enrol_current_session`).
## 15 Glossary — finalist; graduand; unmet requirement; Senate minute; class of degree.

---

# 12 Clearance  (API: `clearance` — `ClearanceController`; schema: clearance (unit, item), ref.clearance_purpose; pages: `clearance`)

## 1 Purpose
Clearance is a set of independent sign-offs per purpose: each of eight units records CLEARED or HELD (naming the item outstanding) against a student, in any order; the latest un-superseded item per unit is the position; a student is clear for a purpose when no unit's position is other than CLEARED. Positions gate the certificate/transcript (documents group), the examination roll flag, and are shown on the student's graduation screen and Student 360.

## 2 Users and roles
Readers: academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, bursar, library, services, ict, admin, super (scope bound on the listing). Signers (`SIGNERS`): academic, registrar, dregistrar, dean, hod, bursar, library, services, housing — `ClearanceService.unitFor`: registrar/dregistrar/academic sign any unit; otherwise only the unit whose `office_code` equals the acting office, plus housing for HOSTEL (V261) — "the X clears against its own record; Y does not sign for it".

## 3 Navigation
`t/clearance` → `/clearance`: academic, admin, bursar ("Financial Clearance"), dean ("Faculty Clearance"), dregistrar, hod ("Department Clearance"), library ("Library Clearance"), registrar, services.

## 4 Screens
`/clearance?purpose=&student=` (`ClearanceScreen.tsx`): RoleLine; scope bar; tiles Candidates for clearance / Fully cleared / Outstanding at one unit / Outstanding at two or more; *Where candidates are held* (Unit | Clears against | Holding | Typical reason | Progress); *Candidates* (checkbox, number, name, one ✓/✗ column per unit, Cleared/Held); a candidate panel (Gates per unit with officer/date/item; unit select for multi-unit offices, "Clear" → `POST /clearance/students/{id}/{unit}/clear`, "Hold" modal "What is outstanding" → `/hold`); *What clearance releases* (five gates, informational); "Clear the selected candidates" (loop), "Export the held list" (CSV), "Notify held candidates" (`POST /clearance/notify-held` → HTTP 202 "The notification module is not on the portal yet; nothing was sent." — shown as "Nothing was sent").

## 5 Workflow and rules
`clearance.item.state` HELD/CLEARED; a HELD row must name an `item` (`ck_clr_hold_names_item`; Java CLR_HOLD_NAMES_ITEM "A hold names the specific item outstanding."); rows are appended (never updated; `superseded_by` column exists but nothing sets it — `position()` takes the latest by `decided_at`). Candidates listed = students in scope enrolled in the session (or the whole scope when nobody is enrolled in that session). Purposes (`ref.clearance_purpose`): CONVOCATION, EXAMINATION, HOSTEL, ID_CARD, LIBRARY, REGISTRATION, RESULTS, TRANSCRIPT — the screen offers CONVOCATION by default and the URL parameter to change it; the API defaults purpose to CONVOCATION.

## 7 Notifications — none; "Notify held candidates" is a stub (202).
## 8 Exports — held list CSV (Matriculation number, Name, Programme, unit states).
## 9 Configuration — `clearance.unit` (ord): BURSARY (bursar), DEPARTMENT (hod), FACULTY (dean), LIBRARY (library), HEALTH (services), HOSTEL (services; housing also signs), WORKS "Works and Maintenance" (services), ALUMNI "Alumni and Convocation" (registrar). No screen edits it.
## 10 Data — `clearance.unit`, `clearance.item` (student, purpose, unit, state, item, officer_id, decided_at, note, superseded_by); audit-attached; 106 items locally (migrated clearances).
## 12 Security — signing scoped by unit/office; reading scoped by `OfficeScope.bound`; `position` of any student readable by every reader.
## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Per-unit clear/hold with item, positions, listing | IMPLEMENTED | `ClearanceService`, `clearance.position` | |
| Bulk clear selected | IMPLEMENTED (client loop) | `ClearanceScreen.tsx` | One request per student |
| Notify held candidates | PLACEHOLDER | `ClearanceController.notifyHeld` 202 | |
| Purposes other than CONVOCATION on screen | PARTIALLY IMPLEMENTED | URL param only | |
| Automatic clearance from library/bursary standing | NOT IMPLEMENTED | manual sign-off | |
## 14 Common problems — "the Library clears against its own record; hod does not sign for it"; "A hold names the specific item outstanding."; a migrated student shows CLEARED everywhere with no officer — that is the V231/V233 carry-over.
## 15 Glossary — unit; purpose; position; hold item.

---

# 13 Head of Department and Dean homes, department staff  (API: `hod`, `dean`; pages: `/` dashboards (`app/dashboards/Hod.tsx`, `Dean.tsx`), `hod/staff`)

## 1 Purpose
Read-only homes scoped to the office's own department/faculty: registrations waiting, offerings without a lecturer, SIWES students without a supervisor, sheets in progress, students/courses counts, the result pipeline, at-risk (PROBATION) students, lecturers' loads, fee clearance counts with downloadable lists, curriculum-track census; the Dean sees registration by department, the pipeline, unallocated offerings and at-risk students. The HOD also has a department staff list from HR records.

## 2 Users and roles
`/hod/dashboard`, `/hod/fees`, `/hod/staff`: hod only, department from `OfficeScope.actingDept()` (office scope → lecturer home department → staff record; `resolved:false` otherwise). `/dean/dashboard`: dean, facultyofficer, super; faculty from the dean/facultyofficer grant or the staff record's department faculty.

## 3 Navigation
Home `/` renders `HodDashboard` for hod and `DeanDashboard` for dean/facultyofficer (`app/page.tsx`); Department Staff `t/deptstaff` → `/hod/staff` (hod).

## 4 Screens
HOD home: `StatsPanel` (student statistics), alert notes with links (Open approvals → `/results/approvals`, Allocate teaching → `/allocate`, Assign supervisors → `/siwes`), tiles (Registrations to approve, Courses without a Lecturer, SIWES without a supervisor, Result sheets in progress, Students, Cleared for registration / owing with `FeeCount` downloads from `/hod/fees?which=cleared|owing`, Courses, Result queries, Student requests), courses needing a lecturer, desk links, pipeline tiles, at-risk table, lecturers table, allocation history. Dean home: notes, tiles, Registration by department, Result pipeline, At-risk students, faculty desk links. Staff list: tiles Staff on the establishment / Hold a teaching office / Professors; table Name | Rank | No. | Sex | Teaching | Status.

## 6 Rules — none written; all counts are SQL in the controllers (`HodController.dashboard` etc.).
## 8 Exports — HOD fee lists (cleared/owing) downloaded via `HodFeeDownloads.tsx` (matric, name, programme, level, charged, paid).
## 13 Implementation status
| Feature | Status | Evidence |
|---|---|---|
| HOD dashboard and fee lists | IMPLEMENTED | `HodController`, `dashboards/Hod.tsx` |
| Dean/Faculty Officer dashboard | IMPLEMENTED | `DeanController`, `dashboards/Dean.tsx` |
| Department staff list | IMPLEMENTED | `HodController.staff`, `StaffList.tsx` |
## 14 Common problems — "Your Head-of-Department office is not tied to a department yet" / "Your Dean office is not tied to a faculty yet" — set the scope on the office assignment (IAM group).

---

## Cross-cutting findings for the writers
1. Notifications in this group exist only for matriculation (number issued), deferments (every turn, plus desk e-mails) and Senate award approval; registration approval/return, transfers, biodata decisions, status changes, clearance holds and LMS events send nothing, and "Notify held candidates" is an explicit stub.
2. Dead or stale surfaces to avoid documenting as working: biodata "Needs approval" tier and the Biodata Changes queue (no producer); Records & queries "fees"/"attendance" not-served text; Student 360 Finance/CGPA placeholders; the "Official transcript" disabled button; the matriculation "What the run does" text; the transfer letter's ₦10,000 and Senate wording; the deferment letter's `/verify/deferment` QR; registration-history "Faculty Officer approved"; the course-upload note naming HODs.
3. Rights without screens: intake run, office-created registrations, course/offer/offering upserts, transfer review/senate/withdraw/effect, matriculation preview/history search, legacy transcript request.
4. Scope gaps: `/student/records/{view}`, `/students/{id}`, faculty-list confirm/query, and the University-wide transfer list are not office-bound in code.
