# Dossier C — Postgraduate School and External Examiners

Read-only audit of the repository at `C:\Users\ajene\Documents\moaumpp` (migrations V202–V228, V254, V255 and the code that uses them) and of the local database on port 5433. Three modules are covered, each with the brief's template:

1. **Postgraduate admissions and the applicant portal** (API `pgadmissions`: `PgApplyController`, `PgRefereeController`, `PgPortalController`, `PgAdmissionsController`, `PgCalendarController`; pages `pg/**`, `admissions/postgraduate`, `admissions/postgraduate/calendar`; tables `admissions.pg_applicant`, `pg_application`, `pg_application_event`, `pg_referee`, `pg_document`, `pg_prior_degree`, `pg_fee`, `pg_fee_reference`, `pg_academic_session`, `pg_semester`).
2. **Postgraduate coursework, research and awards** (API `PgCourseworkController`, `PgResearchController`, `PgSecretaryController`, the students/examiners parts of `PgAdmissionsController`; pages `admissions/postgraduate/{courses,results,students,research,board,clearance,registration,examinations,senate,examiners}`, `student/{pg-courses,pg-progress,research}`; tables `pg_course`, `pg_registration`, `pg_registration_entry`, `pg_score`, `pg_research`, `pg_research_supervisor`, `pg_research_panel`, `pg_research_event`, `pg_research_document(+_blob)`, `pg_examiner`, `pg_legacy_holding`).
3. **External examiners** (API `examiners`: `ExaminersController`, `ExaminerNotifier`, `ExaminerReminders`; pages `examiners/**`, `examiner/**`, `login/activate`; schema `extexam`).

Two pages assigned to this group turned out not to be postgraduate at all and are noted at the end: `research/projects` (research **grants**, expenditure module) and `ethics` (a static framework page).

---

# Module 1 — Postgraduate admissions and the applicant portal
(API module: `pgadmissions` — `PgApplyController`, `PgRefereeController`, `PgPortalController`, `PgAdmissionsController`, `PgCalendarController`; schema: `admissions.pg_*`; pages: `/pg/apply`, `/pg/portal`, `/pg/referee/[token]`, `/pg/summary/pdf`, `/pg/offer/pdf`, `/admissions/postgraduate`, `/admissions/postgraduate/calendar`, `/login/*`)

## 1 Purpose
A postgraduate applicant applies directly to the School of Postgraduate Studies (SPGS) with no JAMB number: they pick a programme, create an account and receive an application number `PG/YY/NNNNNN` and an application-fee reference in one call (`admissions.pg_apply`, db/V205, V210, V217, V224, V225). After the fee is confirmed they complete the record in their portal — first degree, other qualifications, referees (each emailed a private reference link), documents and passport. The department (HOD), then the faculty (Dean), then the School decide; the applicant pays a checking fee to read the decision, and an acceptance fee accepts an offer; the School admits, which writes a `people.student` row with `entry_mode = 'POSTGRADUATE'` and reuses the applicant's password as the student account (V255 `pg_admit`). Every turn is written to `admissions.pg_application_event` by trigger and the applicant is emailed at each turn. The School also keeps its own calendar of sessions and semesters (V224) that every PG desk defaults to.

## 2 Users and roles
- **Public (no token)** — `/api/v1/pg/programmes`, `/apply`, `/status`, `/sign-in`, `/referee/**` are whitelisted in `api/.../platform/SecurityConfig.java:54-55`; the Next proxy opens `/pg/apply`, `/pg/referee/` and the matching BFF paths (`frontend/src/proxy.ts:17-30`).
- **Applicant** — signs in on email or `PG/..` number (`PgPortalController.signIn`, line 117); the token carries the single office `applicant` (line 164) so every portal endpoint is `@PreAuthorize("hasAuthority('OFFICE_applicant')")`. Every read is scoped to `applicant_id = :me`. The frontend paints the shell as office `pgapplicant` (`PgPortal.tsx:178`) — a UI label only; there is no `OFFICE_pgapplicant` authority in this module (the helpdesk module does accept `pgapplicant`).
- **Readers of the desks** — `READERS = pgschool, pgsecretary, academic, registrar, dregistrar, dean, hod, dvc, vc, super` (`PgAdmissionsController.java:55-56`).
- **Department decision** `DEPT = hod, academic, super` (line 58); **faculty decision** `FACULTY = dean, academic, super` (line 60); **School decision / accept / appoint PG examiner / student status** `SPGS = pgschool, pgsecretary, super` (line 62); **admit** `ADMIT = pgschool, pgsecretary, registrar, super` (line 64); **confirm a fee** `CONFIRMERS = pgsecretary, bursar, super` (line 65); **state fees** `FEES = bursar, pgsecretary, pgschool, super` (line 81).
- **Scope** — `boundDept()`/`boundFaculty()` (lines 468-474) use `OfficeScope.actingHod()` and `actingFacultyOffice()` (dean, facultyofficer): a HOD sees and decides only applications for their department's programmes, a Dean only their faculty's; `inBound()` (line 476) refuses the record itself with `AccessDeniedException("This application is for another department's programme; …")`. The School decision (`spgsDecision`) does not call `inBound`.
- **Calendar** — read by `READERS + bursar` (`PgCalendarController.java:569-570`), written by `pgschool, pgsecretary, super` (line 572).

## 3 Navigation
| Office | Group → item | URL |
|---|---|---|
| pgapplicant | My application → Dashboard / Apply Form / Application Summary | `/pg/portal`, `/pg/apply`, `/pg/summary/pdf` (a PDF route handler, "NO PAGE" in menus.md) |
| pgschool, pgsecretary | Admissions → Admissions | `/admissions/postgraduate` |
| pgschool, pgsecretary | Academic → Calendar | `/admissions/postgraduate/calendar` |
| hod, dean | Admissions → PG Admissions | `/admissions/postgraduate` |
| academic | Admissions → Postgraduate Admissions | `/admissions/postgraduate` |
| pgschool, pgsecretary | Overview → Dashboard `r/pgschool` | `/` (home page renders `PgSchoolDashboard` / `PgSecretaryDashboard`, `frontend/src/app/page.tsx:99-150`) |
| bursar, pgsecretary, financecontroller, admin | Finance → Fees | `/finance/fees` (the PG fee card on that page calls `/api/v1/pg/sessions/{s}/{y}/fees`) |
The `pgapplicant` home is `pg/home`, which has no entry in `Shell.tsx` ROUTES (`menus.ts:1462`); the portal page itself is `pg/portal`.

## 4 Screens

### 4.1 Apply — `/pg/apply` (`pg/apply/PgApply.tsx`)
Public, branded login-style frame ("School of Postgraduate Studies · Apply for a postgraduate programme"). A three-step wizard: **1. Programme** (searchable combobox `ProgrammePicker`, grouped by faculty, from `/api/v1/pg/programmes`; hint "· research degree (you can add a proposal in the last step)" when `pg_research`), **2. Your details** (Surname*, Other names*, Sex, Date of birth, State of origin → Local government (dependent selects from `lib/nigeria`), Email*, Phone placeholder `08030000000`), **3. Account** (Password* "At least six characters", Confirm password*, and for a research programme an optional "Proposed topic" and "Summary of the proposed research"). Client checks: "Choose a programme to continue.", "Your surname and other names are required.", "Your email is required — you sign in with it to pay.", "Choose a password of at least six characters.", "The two passwords do not match." Button **Create account & continue** → `POST /api/v1/pg/apply`. On success a green note "Account created — PG/26/000123" with the payment reference and amount, a button **Sign in to pay and continue application** (`/login?next=/pg/portal`), and the **Check your application** card. Server validation (`PgApplyController.ApplyIn`, lines 70-78): surname ≤80, email valid ≤160, password 6–100, ≤5 referees. A second application on the same email is refused with `PG_APP_EXISTS` "An application already exists for this email." (line 125-131).

**Check your application** card (also at the foot of the form): Application number + Email → `GET /api/v1/pg/status`; shows a note titled with the state label (e.g. "Decision ready — pay the checking fee to see it") and a sign-in button whose wording depends on the state; otherwise "No application matches that number and email."

### 4.2 Applicant portal — `/pg/portal` (`pg/portal/PgPortal.tsx`)
Signed-in applicant. Loads `GET /api/v1/pg/me`, then prepares the fee reference for the current step with `POST /api/v1/pg/fee-reference?kind=APPLICATION|CHECKING|ACCEPTANCE`. On return from the gateway (`?paid=<ref>`) it polls `POST /api/v1/payments/verify` + `/pg/me` up to 8 times, 4 s apart ("Confirming your payment…").
- Header note "{name} · {applicationNo} — Your postgraduate application is **{state label}**".
- Tiles: Programme, Application fee (Paid / ₦amount), Documents `n/7`, Stage.
- Decision gate panels: "Your admission decision is ready" (checking fee, `PayByCard`, **I've paid — show my status**); "Congratulations — you have been offered a place" (acceptance fee); "Offer of admission" with **Download / print offer of admission (PDF)** (`/pg/offer/pdf`) once `acceptanceConfirmedAt`; "Admission decision — Not offered a place" for `NOT_OFFERED`.
- "Application fee" panel before payment: `PayByCard`, **I've paid — check now**, "Reference: … · Acceptance later: ₦… + checking ₦…". If no reference could be minted: "The application fee could not be prepared".
- "Application" and "Bio-data" key-value grids; "Progress" list of seven steps (Application submitted, Application fee paid, Department decision, Faculty decision, School decision, Offer accepted, Admitted to the register).
- **Complete your application** — a four-step stepper unlocked after payment: *Academic record* (First degree: Institution, Degree / award, Field of study, Class of degree select, CGPA, Year awarded → `POST /pg/first-degree`; Other qualifications rows: Qualification kind (MASTERS/PGD/HND/ND/NCE/PHD/OTHER), Institution, Award / title, Field, Class / result, CGPA, Year → `POST /pg/qualifications`), *Referees* (rows of name, Email, Phone number, Institution, Position; **Save referees & send requests** → `POST /pg/referees`; referees who already answered are shown "Reference received from …" and cannot be edited), *Documents* (one PDF per kind: Higher degree certificate (multiple), Undergraduate certificate, O'Level result, Birth certificate / declaration of age, NYSC certificate, LGA / indigene certificate, Change of name / marriage certificate (optional); client limits "Each document is a single PDF file.", 8 MB; `POST /pg/documents`, `DELETE /pg/documents/{id}`), *Passport* (JPEG/PNG ≤4 MB → `POST /pg/passport`). Before payment each step shows "Pay the application fee first".
- "Application summary": **Download / print summary (PDF)** (`/pg/summary/pdf`) and **Email me the summary** (`POST /pg/email-summary`).
- "A note from the School" (spgsNote, only once the checking fee is confirmed), "You are now a student of the University" with the admission number and **Go to the Student Sign-in**, and "History of this application" (the V255 trail; decision notes are `null` until the checking fee: "What each desk decided is shown once the checking fee is confirmed.").
- Not signed in: "Sign in to see your application".

### 4.3 Referee form — `/pg/referee/[token]` (`RefereeForm.tsx`)
Public. `GET /api/v1/pg/referee/{token}` shows "Reference for {applicant}" naming the programme, award and session. Fields: Relationship to the applicant*, How long have you known the applicant?*, Academic attestation* (textarea), Recommendation (any further remarks), Your recommendation* (select: "I recommend this applicant" / "I recommend with reservation" / "I do not recommend this applicant"). **Submit reference** → `POST /api/v1/pg/referee/{token}` ("Once submitted, a reference cannot be changed."). Done or already-submitted: "Thank you — your reference has been received". Invalid token: 404 problem "This reference link is not valid." Second submission: `PG_REF_DONE` "This reference has already been submitted."

### 4.4 Sign-in and password reset
The single `/login` door routes a `PG/YY/NNNNNN` identifier, or an email that fails the staff and undergraduate doors, to `POST /api/v1/pg/sign-in` (`frontend/src/app/api/auth/sign-in/route.ts:21-92`). Five wrong passwords lock the account for fifteen minutes (`LOCK_AFTER`, `LOCK_FOR`, `PgPortalController.java:56-57`), twenty failures from one connection in fifteen minutes throttle the source (`SOURCE_FAILURES`, line 60), the session lasts twelve hours (line 55). Forgotten passwords use the shared reset with subject kind `PGAPPLICANT` (`PasswordResetService.java:95-103,168`; db/V220).

### 4.5 PG admissions desk — `/admissions/postgraduate` (`PgAdmissions.tsx`)
Who: READERS (menu for pgschool, pgsecretary, hod, dean, academic); `RoleLine allowed=[pgschool, pgsecretary, hod, dean, academic, registrar]`. Layout: info note; "Session" select (PG calendar sessions, defaulting to the School's CURRENT, `page.tsx:11-19`); six tiles (Applications, Submitted "Awaiting the department", Dept recommended "Awaiting the faculty", Faculty recommended "Awaiting the School", Offered, Admitted); table "Postgraduate applications" (S/N, Applicant + number, Programme, Level, First degree, Stage pill, **Details**) with **Download Excel** (`brandedXlsx`, serial `PGAPP`, `PgAdmissions.tsx:75-83`); empty: "No postgraduate application has been submitted for {session} yet."
`DetailPanel` (`GET /pg/applications/{id}`): passport photo or "No passport uploaded", Bio-data, Institutions attended, Research proposal (research programmes), Referees with the attestation once received ("Reference not yet submitted — a request was emailed"), Documents with **View all as one PDF** / **Download** (`/pg/applications/{id}/documents.pdf`) and per-document **View PDF** in a modal `iframe`, notes from each desk, a "A note for the decision (optional)" textarea and the action buttons shown by office and state: **Department: recommend / Decline** (hod/academic/super at SUBMITTED → `dept-decision`), **Faculty: recommend / Decline** (dean/academic/super at DEPT_RECOMMENDED → `faculty-decision`), **Offer a place / Refuse** (SPGS at FAC_RECOMMENDED → `spgs-decision`), **Record acceptance** (SPGS at OFFERED → `accept`), **Admit onto the register** (pgschool/pgsecretary/registrar/super at ACCEPTED → `admit`), and the History list with actor and office. Toasts carry the `X-Reason` text (e.g. "Offered {name} a place on {programme}").

### 4.6 School / Secretary home dashboards — `/` (`dashboards/PgSchool.tsx`)
`PgSchoolDashboard` (`GET /pg/dashboard`): a lead note ("{n} applications recommended by a faculty, awaiting the School" → **Decide them**, or "{n} applicants have accepted an offer, ready to admit" → **Admit them**), the StatsPanel, tiles (Applications, Awaiting the School, Offered, To admit, PG students) and the register pipeline tiles (Active students, On research, Awaiting defence, Finishing, Graduation eligible, Graduated), "Latest applications" (last 50 across sessions) and "By programme". `PgSecretaryDashboard` (`GET /pg/secretary/dashboard`): "{n} items wait on the Secretary", tiles (To register, Fees to confirm, Exams pending, Clearances), and three lists — registrations to endorse, live fee references with a **ConfirmFee** button (`POST /pg/applications/{id}/confirm-fee` with `channel: "bank"`, `dashboards/ConfirmFee.tsx:18-20`), theses awaiting clearance.

### 4.7 Postgraduate calendar — `/admissions/postgraduate/calendar` (`PgCalendar.tsx`)
pgschool, pgsecretary. Tiles (Current session, Current semester, Sessions on record); "Sessions" table (Session, Opens, Closes, Semesters, State) with **Edit**, **Make current** (`POST /pg/calendar/sessions/{s}/{y}/make-current`) and **Setup new session** (modal: Session `2026/2027` regex-checked client-side with `alert("The session name reads like 2026/2027.")`, Semesters 2 or 3 (Summer), Opens, Closes, State PLANNED/CURRENT/CLOSED, Note → `PUT /pg/calendar/sessions/{s}/{y}`); "Semesters — {session}" rows with **Set windows / Edit windows** (modal: Registration opens/closes, Lectures from/to, Exams from/to, Results due, State NOT_YET_OPEN/OPEN/CLOSED → `PUT …/semesters/{n}`). Empty: "No sessions yet. Set one up to start the PG calendar."

### 4.8 PDFs — `/pg/summary/pdf`, `/pg/offer/pdf`
See §8.

## 5 Workflow and statuses
`admissions.pg_application.state` CHECK (`ck_pg_app_state`, V226): `DRAFT, SUBMITTED, DEPT_RECOMMENDED, DEPT_DECLINED, FAC_RECOMMENDED, FAC_DECLINED, OFFERED, NOT_OFFERED, ACCEPTED, ADMITTED`. The public apply inserts straight at `SUBMITTED` (V205 onward); `DRAFT` and `pg_submit` (V202) survive only for records created by the older `pg_register`.

| From | Act | By | To | Data / notice |
|---|---|---|---|---|
| — | `pg_apply` | public | SUBMITTED | applicant row, application, referees, prior degrees, APPLICATION fee reference (24 h); trail `CREATED`, `SUBMITTED`; email "Your MOAUM postgraduate application has been received" |
| any | `pg_confirm_fee(APPLICATION)` | Bursar/Secretary desk, or `PaymentsService` gateway callback (`PaymentsService.java:568`) | same, `fee_confirmed_at` set | trail `APPLICATION_FEE_CONFIRMED`; email "Your application fee is confirmed"; unlocks the portal steps |
| SUBMITTED | `pg_dept_decide` | hod / academic / super, in bound | DEPT_RECOMMENDED / DEPT_DECLINED | `dept_decided_*`, `dept_note`; trail row |
| DEPT_RECOMMENDED | `pg_faculty_decide` | dean / academic / super, in bound | FAC_RECOMMENDED / FAC_DECLINED | `fac_*`; trail |
| FAC_RECOMMENDED | `pg_spgs_decide` | pgschool / pgsecretary / super | OFFERED / NOT_OFFERED | `spgs_*`; trail; controller emails "A decision on your MOAUM postgraduate application" telling the applicant to pay the checking fee (`PgAdmissionsController.java:614-630`) |
| decided | `pg_confirm_fee(CHECKING)` | as above | `checking_confirmed_at` | trail `CHECKING_FEE_CONFIRMED`; email "Your admission decision is ready to view"; the decision and notes become readable (`DECISION_LOCKED` mask lifts) |
| OFFERED | `pg_confirm_fee(ACCEPTANCE)` or `pg_accept` (desk) | applicant by paying; SPGS desk | ACCEPTED | `acceptance_confirmed_at`, `accepted_at`; trail `ACCEPTANCE_FEE_CONFIRMED`, `ACCEPTED`; email "Your offer of admission is accepted"; offer letter PDF unlocks (needs `acceptanceConfirmedAt`, not merely ACCEPTED) |
| ACCEPTED | `pg_admit` | pgschool / pgsecretary / registrar / super | ADMITTED | `people.student` (admission no `MOAUM/ADM/YY/NNNNNN`, entry_mode POSTGRADUATE, level from award, school `S002`, status ADMITTED), `people.student_contact`, `iam.student_account` with the applicant's hash; idempotent; email "You are admitted — your student record is open" naming the admission number |
Declines (`*_DECLINED`, `NOT_OFFERED`) are terminal — no reopen or appeal endpoint exists; a declined applicant cannot apply again on the same email (`PG_APP_EXISTS`).

Fee references: `pg_fee_reference.kind` ∈ `APPLICATION, CHECKING, ACCEPTANCE`; reference format `MOAUM-PGAPP-|PGCHK-|PGACC-NNNNNN` from series `PG_FEEREF` (V223); 24-hour expiry; a live unpaid one is reused (`feeReference`, line 223). `PaymentsRepository.java:65-78` maps them to kinds `PG_APPLICATION/PG_CHECKING/PG_ACCEPTANCE` for the gateway and returns the payer to `/pg/portal`.

Calendar: `pg_academic_session.state` ∈ `PLANNED, CURRENT, CLOSED` (one CURRENT enforced by `uq_pg_session_one_current`); `pg_semester.state` ∈ `NOT_YET_OPEN, OPEN, CLOSED`. `admissions.pg_current_session()` = the School's CURRENT, else the University's, else `'2025/2026'` (V224 §3). Local DB: `2025/2026 CLOSED`, `2026/2027 PLANNED` — **no session is CURRENT**, so `pg_current_session()` falls back to the University's.

## 6 Business rules and validations
- Programme must exist and be `category = 'POST GRADUATE'`: "that programme is not one the University runs" (23503) / "that programme is not a postgraduate programme" (23514) (V225 `pg_apply`). Entry level from `pg_award_level`: PGD→700, PHD/MPHIL→900, else 800.
- `pg_applicant`: email regex, phone `^0[0-9]{10}$`, bcrypt cost-12 hash (`ck_pgapplicant_pw`), unique lower(email); a race on the same email is caught as `DuplicateKeyException` → `PG_APP_EXISTS`.
- Fee gates in the controller: `PG_FEE_NOT_YET` "The checking fee is paid once the School has decided on the application." / "The acceptance fee is paid once a place is offered and the decision has been read."; `PG_FEE_PAID` "That fee is already confirmed for this application."; `PG_FEE_UNPAID` "Pay the application fee before uploading your documents." guards first-degree, qualifications, referees, documents, passport.
- Documents: kinds in `APPLICANT_DOC_KINDS` else `PG_DOC_KIND`; PDF only (`PG_DOC_TYPE` "Each document is a single PDF file."); 1 byte–8 MB (`PG_DOC_SIZE`); a new upload replaces the earlier of the same kind except `HIGHER_DEGREE`; passport JPEG/PNG ≤4 MB (`PG_PASSPORT_TYPE/SIZE`). Table CHECK `ck_pg_doc_kind` lists 14 kinds (V222).
- Referees: saving deletes unsent referees and re-inserts; a referee whose reference is in is kept and not duplicated by email; a token (`encode(gen_random_bytes(18),'hex')`, unique) is generated per row (V225) and emailed as `{portalUrl}/pg/referee/{token}`. Verdict CHECK `RECOMMEND, RECOMMEND_WITH_RESERVATION, DO_NOT_RECOMMEND`; `RefIn` requires relationship ≤200, knownDuration ≤120, attestation ≤4000.
- Decisions must follow the order — SQL messages: "the department decides a submitted application, not one at %", "the faculty decides after the department recommends, not on an application at %", "the School decides after the faculty, not on an application at %", "only an offer can be accepted (state is %)", "only an accepted offer is admitted (state is %)" (V202/V226; raised without an ERRCODE, so they surface as 500-class errors rather than 422).
- Confirm-fee: the reference must belong to the application (`PG_FEE_REF_MISMATCH`); an unknown or already-confirmed reference is silently a no-op in `pg_confirm_fee`.
- Status mask: `state` is reported as `DECISION_LOCKED` while `spgs_decided_at` is set and `checking_confirmed_at` is null, on both the public status check and `/pg/me`; dept/fac notes are null until the checking fee (`view()`, lines 287-313, 337-343).
- HOD/Dean bound (§2). Session default for the desk: the PG calendar's CURRENT, else `intakeSession()`.
- Calendar: session name `^[0-9]{4}/[0-9]{4}$`, semesters 1–3, `PG_CAL_SEMESTER` "A session has at most three semesters."; saving a session as CURRENT closes the previous CURRENT.

## 7 Notifications (all EMAIL via `platform.queue_notice`; no SMS is sent by this module)
| Event | Trigger | Recipient | Subject |
|---|---|---|---|
| Application created (SUBMITTED on insert) | `pg_application_trail` (V255) | applicant | "Your MOAUM postgraduate application has been received" |
| DRAFT→SUBMITTED | same | applicant | "Your MOAUM postgraduate application has been submitted" |
| Application fee confirmed | same | applicant | "Your application fee is confirmed" |
| School decided | `PgAdmissionsController.spgsDecision` | applicant | "A decision on your MOAUM postgraduate application" |
| Checking fee confirmed | trail | applicant | "Your admission decision is ready to view" |
| ACCEPTED | trail | applicant | "Your offer of admission is accepted" |
| ADMITTED | trail | applicant | "You are admitted — your student record is open" |
| Referee named (with email) | `PgPortalController.referees` | referee | "Reference request — {applicant} (MOAUM Postgraduate)" |
| Reference received | `pg_referee_trail` | applicant | "A reference has been received" |
| Summary requested | `emailSummary` | applicant | "Your MOAUM postgraduate application summary" |
Every applicant mail is signed "School of Postgraduate Studies, Rev. Fr. Moses Orshio Adasu University, Makurdi" and carries the application number (`pg_tell_applicant`). Nothing notifies the HOD, Dean or School when an application arrives or advances.

## 8 Reports, exports and documents
- **Applications Excel** — `brandedXlsx("Postgraduate applications", …)` with S/N, Application number, Applicant, Programme, Award, Department, Faculty, Level, Session, Application fee, Application status, Submitted; serial `PGAPP`, sheet "Applications" (`PgAdmissions.tsx:74-83`).
- **Merged documents PDF** — `GET /pg/applications/{id}/documents.pdf` concatenates every uploaded PDF with PDFBox and adds the passport as an A4 image page (`PgAdmissionsController.java:517-568`); unreadable files are skipped; `PG_DOC_MERGE` if nothing merges.
- **Application summary PDF** — `/pg/summary/pdf/route.ts`: crest, "APPLICATION SUMMARY", sections APPLICATION (with the passport re-encoded to JPEG via `/pg/passport/image?format=jpeg`), APPLICANT, QUALIFICATIONS, RESEARCH PROPOSAL, REFEREES, "Documents on file: …", footer "Generated {date} · {name} · {no}". No verification code.
- **Confirmation of offer of admission PDF** — `/pg/offer/pdf/route.ts`: refused with 409 "Offer letter not available yet" until `acceptanceConfirmedAt`; headed "(Office of the Registrar)", DATE, APPLICANT'S NAME, APPLICATION NUMBER, "CONFIRMATION OF OFFER OF ADMISSION: {session} ACADEMIC SESSION", COURSE/PROGRAMME/FACULTY/LEVEL/DURATION (700→3 SEMESTERS, 800→4, 900→6), six numbered notes, signed "Ajuma Isaac Ugbabe, Secretary, Postgraduate School" (hard-coded), and a QR encoding the text `MOAUM PG {applicationNo}`. **There is no `/verify` endpoint for that QR** (the verify module covers exam cards, hostel, PUTME, receipts, reports, registration and results only) — the QR is decorative.
- The postgraduate return `GET /api/v1/reports/postgraduate` (reports module, `ReportsController.java:301-359`) counts applications → offered → accepted → admitted per programme, plus register, sex, mode, researching and awarded; read on `/reports` and `/reports/postgraduate/view`.

## 9 Configuration
- **Fees** — `admissions.pg_fee(session, application_fee, acceptance_fee, checking_fee)`; `pg_fee_rule(session)` returns the stated row else defaults **₦20,000 / ₦50,000 / ₦3,000** (V208). Set on `/finance/fees` (PG card → `GET/PUT /api/v1/pg/sessions/{s}/{y}/fees`, `FeeSchedule.tsx:254-262`; the PUT is missing from api.md). Local DB: no row stated — defaults apply.
- **Calendar** — `pg_academic_session`, `pg_semester` on `/admissions/postgraduate/calendar` (seeded from the University calendar by V224; on the audit spine since V228).
- **Programmes** — `ref.programme` with `category = 'POST GRADUATE'`, `pg_award`, `pg_research` (catalogue module; 189 active PG programmes locally, 176 research). Awards seen: LLM, MA, MBA, MED, MHM, MLIS, MPA, MPH, MRH, MSC, MURP, PGD, PHD.
- `moaum.portal-url` (default `https://moaum-portal-production.up.railway.app`) builds referee and portal links.
- Number series `PG_APPLICATION`, `PG_FEEREF`, `ADMISSION` in `platform.next_number`.

## 10 Data
| Table | Purpose / notes | Audit |
|---|---|---|
| `admissions.pg_applicant` | account + biodata, `password_hash`, `failed_attempts`, `locked_until`, `last_signed_in_at` | exempt (holds a hash) |
| `pg_application` | one per applicant (`uq_pg_application_per_applicant`), state machine, first-degree columns, proposal, every decision's timestamp/actor/note, `student_id` | attached + `trg_pg_application_trail` |
| `pg_application_event` | write-once trail (kind, note, actor_id, actor_office, at); back-filled by V255 | attached (no written-once trigger) |
| `pg_referee` | name, email, phone, institution, position, `token`, relationship, known_duration, attestation, recommendation, verdict, submitted_at | attached + `trg_pg_referee_trail` |
| `pg_prior_degree` | kind (NCE, ND, HND, FIRST, PGD, MASTERS, PHD, OTHER), institution, award, field, class, cgpa, year | attached |
| `pg_document` | kind, filename, content_type, bytes (bytea) | exempt |
| `pg_fee`, `pg_fee_reference` | fees per session; references with kind, amount, expires_at, confirmed_at, channel | attached |
| `pg_academic_session`, `pg_semester` | the School's calendar | attached (V228) |

## 11 Scheduled jobs and integrations
None in this module. Payment confirmation arrives through the payments module's gateway verify/callback (`PaymentsService.confirmPg`) or a desk confirmation; emails through `NoticeDispatcher`.

## 12 Security notes
- Public endpoints: programmes, apply, status, sign-in, referee GET/POST, plus the frontend `/pg/apply` and `/pg/referee/`. `/pg/portal` requires the session cookie.
- Public `status` returns the applicant's name for a (number, email) pair — both are needed.
- Applicant writes are attributed to `NOBODY` under office `applicant` for apply and the referee submission; the signed-in applicant's own id afterwards.
- Documents served with `Content-Security-Policy: sandbox` and `nosniff` to the applicant; the desk stream does not set CSP (`document()`, line 509).
- HOD/Dean scope is enforced on the record (`inBound`), not only on the list.
- The offer-letter QR cannot be verified (no endpoint). Password minimum is six characters for applicants (the examiner door requires ten).

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Public apply wizard + account | IMPLEMENTED | `PgApply.tsx`, `PgApplyController.java:82`, V225 `pg_apply` | |
| Public status check with decision mask | IMPLEMENTED | `PgApplyController.java:137-151` | |
| Applicant sign-in, lockout, reset | IMPLEMENTED | `PgPortalController.java:117-166`, `PasswordResetService.java:95` | |
| Fee references (3 kinds) + gateway confirm + desk confirm | IMPLEMENTED | `feeReference` line 193; `PaymentsService.java:568`; `confirmFee` line 658 | |
| Academic record, qualifications, referees, documents, passport | IMPLEMENTED | `PgPortalController.java:396-682` | |
| Referee email link and attestation | IMPLEMENTED | `PgRefereeController.java`, V225 | |
| Department → Faculty → School decisions with HOD/Dean bound | IMPLEMENTED | `PgAdmissionsController.java:574-632` | |
| Acceptance by fee / by desk; admit → student + account | IMPLEMENTED | V223 `pg_confirm_fee`, V255 `pg_admit` | |
| Application trail + applicant notices | IMPLEMENTED | V255 `pg_application_trail` | |
| Application summary PDF, offer letter PDF | IMPLEMENTED | `pg/summary/pdf/route.ts`, `pg/offer/pdf/route.ts` | offer QR has no verifier → verification PARTIALLY IMPLEMENTED |
| Merged documents PDF for the desk | IMPLEMENTED | `mergedDocuments` line 517 | |
| Applications Excel | IMPLEMENTED | `PgAdmissions.tsx:75` | |
| PG calendar | IMPLEMENTED | `PgCalendarController.java`, `PgCalendar.tsx` | windows are informational; nothing enforces `registration_opens/closes` for PG registration (no reference in `PgCourseworkController` or SQL) |
| PG fee setup | IMPLEMENTED | `setFees` line 102; `FeeSchedule.tsx:254` | |
| Applicant home route `pg/home` | PLACEHOLDER | `menus.ts:1462`, no ROUTES entry | portal opens at `/pg/portal` |
| Reopening a declined application / appeal | NOT IMPLEMENTED | no endpoint | |
| Notice to HOD/Dean/School of new or advancing applications | NOT IMPLEMENTED | only applicant mails exist | |

## 14 Common problems and troubleshooting
- "An application already exists for this email." — one application per email; sign in with it (or reset the password).
- "Pay the application fee before uploading your documents." — `fee_confirmed_at` is null; pay, then **I've paid — check now** (which calls `payments/verify`), or have the Secretary/Bursar confirm the reference on the Secretary's home.
- "That reference does not belong to this application." — the desk typed a reference minted for another application.
- "The checking fee is paid once the School has decided…" — the portal only prepares the CHECKING reference after `spgs_decided_at`.
- Offer letter returns 409 "Offer letter not available yet" — the acceptance fee is unconfirmed even if the desk recorded acceptance with **Record acceptance**; only a confirmed ACCEPTANCE reference sets `acceptance_confirmed_at`.
- "This application is for another department's programme…" (403) — a HOD/Dean opened an application outside their scope (`iam.office_assignment` scope).
- Decision buttons missing — the state does not match the office's step (e.g. a Dean sees no buttons at SUBMITTED); the desk defaults to the School's CURRENT session and the local DB has none marked CURRENT, so choose the session explicitly.
- Referee never received a mail — the referee row has no email, or the applicant re-saved referees (unsent rows are deleted and re-created with new tokens; old links 404).

## 15 Glossary
**Checking fee** — the fee (default ₦3,000) that releases the School's decision to the applicant. **Acceptance fee** — the fee whose confirmation accepts an offer. **DECISION_LOCKED** — the masked state shown between the School's decision and the checking fee. **SPGS** — School of Postgraduate Studies. **PG calendar** — the School's own sessions/semesters (`admissions.pg_academic_session`). **Trail** — `pg_application_event`.

---

# Module 2 — Postgraduate coursework, research and awards
(API: `PgCourseworkController`, `PgResearchController`, `PgSecretaryController`, `PgAdmissionsController.students/setStatus/examiners`; schema: `admissions.pg_course`, `pg_registration(_entry)`, `pg_score`, `pg_research*`, `pg_examiner`, `pg_legacy_holding`; pages: `/admissions/postgraduate/{courses,results,students,research,board,clearance,registration,examinations,senate,examiners}`, `/student/pg-courses`, `/student/pg-progress`, `/student/research`)

## 1 Purpose
Once admitted, a postgraduate registers the courses of their programme per session and semester on the School's own catalogue (V211), the HOD/School endorses the registration, the desk records CA and examination marks and the grade is computed on the postgraduate scale (A 70+, B 60–69, C 50–59, F <50; 5/4/3/0 points; deficiency courses earn no credit). In parallel a research record (V209) runs the candidate from supervision through proposal, seminar, title registration with a plagiarism figure, panel, draft, viva, corrections, final submission, the Secretary's clearance, the School Board's recommendation and Senate's award; every document the candidate submits is kept by kind and version (V255), and `pg_award` writes the graduand row and sets the student `GRADUATED`. The Secretary's four read-only desks (registration, examinations, clearance, Senate) summarise those registers; the School keeps a roster of appointed external examiners (V213) separate from the extexam workspace.

## 2 Users and roles
- Student (`OFFICE_student`, must have `entry_mode = 'POSTGRADUATE'`): own coursework, summary, registration, research record and documents.
- Coursework desk `DESK = hod, academic, pgschool, pgsecretary, super` (`PgCourseworkController.java:42`): catalogue, import, registrations, endorse, score. No department scope is applied here — a HOD can read and score any programme's registrations (contrast with the admissions desk).
- Research desk `SCHOOL = pgschool, pgsecretary, super` (`PgResearchController.java:49`): pipeline, supervisors, panel, actions, document review.
- Secretary desks `READERS = pgsecretary, pgschool, academic, registrar, dregistrar, super` (`PgSecretaryController.java:438-439`).
- Register `/pg/students`: admissions READERS; status change: SPGS. PG examiner roster: read by READERS, add by SPGS.
- UI editors: courses and results pages `EDITORS = hod, academic, pgschool, pgsecretary, super`; board, examiners, students `pgschool, pgsecretary, super`; clearance `CLEARERS = pgsecretary, pgschool, super` (each `page.tsx:7`).

## 3 Navigation
| Office | Group → item | URL |
|---|---|---|
| pgschool, pgsecretary | Academic → Courses | `/admissions/postgraduate/courses` |
| pgschool, pgsecretary | Academic → Course Results | `/admissions/postgraduate/results` |
| pgschool | Academic → School Board | `/admissions/postgraduate/board` |
| pgschool, pgsecretary | Academic → External Examiners | `/admissions/postgraduate/examiners` |
| pgschool, pgsecretary | Academic → Examination Panels / Panels & Viva | `/admissions/postgraduate/research?stage=DRAFT_SUBMITTED` |
| pgschool | Academic → Research Desk | `/admissions/postgraduate/research` |
| pgsecretary | Academic → Research Seminars | `/admissions/postgraduate/research?stage=PROPOSAL_APPROVED` |
| pgschool, pgsecretary | Academic → Thesis Clearance | `/admissions/postgraduate/clearance` |
| pgsecretary | Academic → Registration / Course Examinations / Results to Senate | `/admissions/postgraduate/registration`, `/examinations`, `/senate` |
| pgschool, pgsecretary | Students → PG Students | `/admissions/postgraduate/students` |
| pgstudent | Academic → Course Registration & Results / Academic Progress; Research → Research & Thesis | `/student/pg-courses`, `/student/pg-progress`, `/student/research` |
Routes `t/pgsupervision`, `t/pgproposals`, `t/pgtheses` exist in `Shell.tsx:68-72` but no menu lists them. Neither HOD nor academic has a menu entry to the courses/results desks although the API admits them.

## 4 Screens

### 4.1 Courses — `/admissions/postgraduate/courses` (`CoursesDesk.tsx`)
Programme select (grouped by faculty, from `/pg/programmes`). Editors see **Upload the course catalogue** — **Download template** (`PG courses template.xlsx`: Programme, Course Code, Title, Units, Kind, Semester) and **Upload courses (.xlsx / .csv)** parsed client-side with flexible header matching → `POST /pg/coursework/courses/import`; result note "{n} courses added, {m} updated · {k} rows had a programme that did not match one on record · {s} skipped." Errors: "The file needs Programme, Course Code and Title columns.", "No course rows to read.", "That file could not be read as a spreadsheet." With no programme chosen: "All postgraduate courses" table (`/courses/all`); with one: "Courses" (Code, Title, Units, Type pill, Semester, Status) and **Add a course** (Course code (upper-cased, e.g. `ACC 801`), Title, Units, Type Core/Elective/Research/Deficiency, Semester First/Second → `POST /pg/coursework/courses`, upsert on (programme, code)). Note "Course units (Policy 11)…".

### 4.2 Course results — `/admissions/postgraduate/results` (`ResultsDesk.tsx`)
Session text box, Semester (First/Second), Programme filter → `GET /pg/coursework/registrations`. Table: Student, Programme, Mode, Courses, GPA, Status pill, **Open**. Detail: mode, state, **Endorse registration** (editors, if not ENDORSED → `POST …/registrations/{id}/endorse`), and a per-course row with CA and Exam inputs and **Save** (`POST /pg/coursework/score`), Total and Grade computed. Note "Grading (Policy 16)". Empty: "No registration for this session and semester."

### 4.3 PG Students register — `/admissions/postgraduate/students` (`StudentsRegister.tsx`)
`GET /pg/students`. Clickable tiles (PG students, PGD, Master's, Doctoral, On probation) that filter; selects Programme, Level, Gender, Entry session, Standing. Table: Student, Programme, Level, Sex, Status (+ FT/PT), CGPA, Standing pill (Good ≥2.50 / Probation / New), Research stage; editors get an **Action…** select (Defer, Withdraw, Reinstate (active), Readmit (continue)) which `window.prompt`s for the instrument and posts `POST /pg/students/{id}/status` with `to ∈ DEFERRED|WITHDRAWN|ACTIVE` (READMIT maps to ACTIVE with reason "Readmitted to continue"; the readmission fee is charged by the finance engine per the code comment, not verified here). Note "Academic standing (Policy 15.5 / 20)".

### 4.4 Research desk — `/admissions/postgraduate/research[?stage=]` (`PgResearch.tsx`)
`GET /pg/research?stage=` with counts tiles (In the pipeline, Supervision, Proposal, Seminar & title, Examination, Awarded); "Research pipeline" table (Candidate, Programme, Kind, Stage pill, Supervisors, Updated) and a stage select (16 options from "All stages" to "Withdrawn"). Clicking a candidate opens the detail panel: milestone key-values; **Supervisors** with an inline add (name, role First/Second/Co, external checkbox → `POST /pg/research/{id}/supervisor`); **Panel of examiners** with inline add (name, role Chair / HOD, External examiner, Supervisor, Co-supervisor, Internal examiner, PGSR, PG Coordinator → `/panel-member`; empty text "Not constituted yet — six for a Master's, seven for a PhD (Policy 24.3)"); **Advance** buttons per stage (`NEXT` map, lines 97-110): Record proposal submitted, Approve proposal, Record seminar (+PGSR), Register title (+Originality %), Constitute panel, Record draft submission, Record viva (+Score %, outcome select), Corrections required (+due date) / Record final submission, Clear for binding, Recommend to Senate, Record Senate award; **Withdraw candidate** after `window.confirm`; **Documents submitted by the candidate** table with **Accept** / **Return** (prompt "What must the candidate correct?") → `/documents/{docId}/review`; **Milestones** log. Note: the Advance section offers `AWARD` without a Senate-minute input, so from this desk it always fails with `PG_AWARD_MINUTE` — the award is recorded on the Board page.

### 4.5 School Board — `/admissions/postgraduate/board` (`Board.tsx`)
`GET /pg/research` (all rows) split into Cleared → **Recommend** (`RECOMMEND`), Recommended → **Record Award** enabled only after a "Senate minute" is typed (e.g. `SEN/2026/07/12`; `AWARD` with `senateMinute`), and "Awarded this session" (every AWARDED row, not filtered by session despite the heading). Tiles Awaiting the Board / With Senate / Awarded.

### 4.6 Thesis clearance — `/admissions/postgraduate/clearance` (`Clearance.tsx`)
`GET /pg/secretary/clearance`: "Awaiting clearance" (Candidate, Programme, Work + topic, Final submitted, Plagiarism pill (≤20 % green else amber), Viva pill, **Clear for binding** → `CLEAR` with note "Cleared by the Secretary before binding") and "Cleared for binding" (last 50).

### 4.7 Registration & matriculation — `/admissions/postgraduate/registration` (`Registration.tsx`)
`GET /pg/secretary/registration?session=`: tiles To register / Registered / Part-time / Lapsed; "Fresh postgraduate students" (Mode, Acceptance fee Paid/Owing, Registered, Matriculation → **Matriculate** link to `/matriculation`); "Semester renewal" (Renewed / Submitted / Not renewed). Read-only.

### 4.8 Course examinations — `/admissions/postgraduate/examinations` (`Examinations.tsx`)
`GET /pg/secretary/examinations?session=&semester=` (First/Second/Summer): tiles Courses sat, Results recorded, Results awaited, Candidates; per-course Recorded / Partly recorded / Awaited. Read-only; links to the Results desk.

### 4.9 Results to Senate — `/admissions/postgraduate/senate` (`Senate.tsx`)
`GET /pg/secretary/senate?session=`: tiles To Senate, Awarded, Coursework results, Pending computation; "Computed results to Senate" (Coursework CGPA, Viva, Outcome, "With Senate") and "Awarded this session" (awards dated within the two calendar years of the session). Read-only; links to the Board.

### 4.10 External examiners (School roster) — `/admissions/postgraduate/examiners` (`Examiners.tsx`)
`GET /pg/examiners` table (Name, Institution, Field, Tenure, Active/Ended) and, for SPGS, **Appoint an examiner** (Name*, Institution*, Field / specialization, Tenure from, Tenure to → `POST /pg/examiners`). There is no edit, end or deactivate action; `active` can never be changed from the UI or API.

### 4.11 Student: Course Registration & Results — `/student/pg-courses` (`Coursework.tsx`)
Session text box and Semester (First/Second) → `GET /pg/coursework/me`. "Results" table once scored (GPA/CGPA, Units passed, Standing Good standing/Probation). "Course registration": checkboxes per programme course (locked once scored), Mode Full-time/Part-time, **Register these courses / Update registration** → `POST /pg/coursework/register`; endorsed registration shows "Your registration is endorsed… Write to the department to change it." Empty catalogue: "No courses listed for this semester yet".

### 4.12 Student: Academic Progress — `/student/pg-progress` (`Progress.tsx`)
Reads `/pg/coursework/summary`. Tiles Units earned, Courses passed, CGPA, Graduation; a meter; "Graduation eligibility" checklist computed client-side (`pg-common.ts eligibility()`): Coursework completed, Minimum CGPA of 2.50, Research completed and cleared, Oral examination passed, School fees settled, plus each convocation clearance unit — each MET / PENDING / NOT_MET with a link. Programme and Research panels; award note when a graduand row exists.

### 4.13 Student: Research & Thesis — `/student/research` (`Research.tsx`)
`GET /pg/research/me` (creates the record on first read via `pg_research_ensure`). Progress steps (Supervisor assigned … Award), Supervision, Panel of examiners (when constituted), Viva note, "Topic & proposal" (Research topic input, **Save topic** while editable, **Submit proposal** → `/me/proposal`; hint "A Master's proposal is due within 6 months, a PhD within 12 months…"), "Documents" (kind select defaulting to what the stage calls for — Proposal, Seminar paper, Plagiarism report, Draft for examination, Corrected copy, Final copy, Other; PDF/.docx ≤25 MB; Note; **Submit Document** → `/me/documents`), Milestones.

## 5 Workflow and statuses
**Registration** `pg_registration.state` ∈ `DRAFT, SUBMITTED, ENDORSED`; `mode` ∈ `FULL_TIME, PART_TIME`; `semester` ∈ 1,2,3 (V224). `pg_register` upserts at SUBMITTED, replaces unscored entries, keeps scored ones, admits only active courses of the student's programme; the deferment gate `trg_deferment_gate_pg_registration` (V259) refuses "REGISTRATION UNAVAILABLE: your deferment for % is approved; you cannot register for the deferred period". `endorse` sets ENDORSED with no state precondition. Scores: `pg_record_score` rounds CA+exam, grades via `pg_grade`; upsert per entry; `ck_pg_score_total` 0–100 (CA 60 + exam 60 is refused by the CHECK); no check that the registration is endorsed or that CA ≤40/exam ≤70.

**Research** `pg_research.stage` ∈ `REGISTERED, SUPERVISED, PROPOSAL_SUBMITTED, PROPOSAL_APPROVED, SEMINAR_HELD, TITLE_REGISTERED, PANEL_CONSTITUTED, DRAFT_SUBMITTED, VIVA_HELD, CORRECTIONS, FINAL_SUBMITTED, CLEARED, AWARD_RECOMMENDED, AWARDED, WITHDRAWN`; `degree_kind` PROJECT / DISSERTATION / THESIS derived from level and `pg_research`; `viva_outcome` ∈ `PASS_CLEAN, PASS_MINOR, PASS_MAJOR, SECOND_ORAL, FAIL`; `viva_grade` A/B/C/F from the score (70/60/50).

| Action (`/action`) | Allowed from (`FROM`, `PgResearchController.java:208-220`) | To | Notes |
|---|---|---|---|
| first `/supervisor` | REGISTERED | SUPERVISED | any later stage keeps its stage |
| student `/me/proposal` | any (topic required) | PROPOSAL_SUBMITTED | |
| SUBMIT_PROPOSAL | REGISTERED, SUPERVISED | PROPOSAL_SUBMITTED | desk |
| APPROVE_PROPOSAL | PROPOSAL_SUBMITTED | PROPOSAL_APPROVED | topic locked for the student from here (`PG_TOPIC_LOCKED`) |
| SEMINAR (+pgsr) | PROPOSAL_APPROVED | SEMINAR_HELD | |
| REGISTER_TITLE (+plagiarismPct, required) | SEMINAR_HELD | TITLE_REGISTERED | `PG_PLAGIARISM` "Record the plagiarism-check originality before registering the title." (75–85 % is advisory only) |
| PANEL | TITLE_REGISTERED | PANEL_CONSTITUTED | `/panel-member` rows can be added at any stage |
| DRAFT, or student DRAFT document | TITLE_REGISTERED, PANEL_CONSTITUTED | DRAFT_SUBMITTED | |
| VIVA (+score, outcome) | DRAFT_SUBMITTED, CORRECTIONS | VIVA_HELD | a second oral re-enters from CORRECTIONS |
| CORRECTIONS (+due) | VIVA_HELD | CORRECTIONS | student then submits CORRECTED copies |
| FINAL, or student FINAL document | VIVA_HELD, CORRECTIONS | FINAL_SUBMITTED | |
| CLEAR | FINAL_SUBMITTED | CLEARED | Secretary's clearance page |
| RECOMMEND | CLEARED | AWARD_RECOMMENDED | Board |
| AWARD (+senateMinute, session) | AWARD_RECOMMENDED | AWARDED | `pg_award` (V255): graduand `records.graduand` APPROVED on the minute, `people.change_status(GRADUATED)`, event "Award of {award} approved by Senate under minute …" |
| WITHDRAW | any | WITHDRAWN | terminal; no reinstatement action |
Out-of-order: `PG_STAGE_ORDER` "This record is at 'x'; y follows 'z'." After AWARDED: `PG_AWARDED`. Every stage change fires `trg_pg_research_trail` (email to the student, §7) and the controller writes `pg_research_event`.

**Documents** `pg_research_document.status` ∈ `SUBMITTED, ACCEPTED, RETURNED`; kind ∈ `PROPOSAL, SEMINAR_PAPER, PLAGIARISM_REPORT, DRAFT, CORRECTED, FINAL, OTHER`; version = `pg_research_next_version`; a new version never replaces an old one; the desk review keeps the version and logs "{kind} version n accepted/returned".

**Student status** (`setStatus`): `DEFERRED`, `WITHDRAWN`, `ACTIVE` only (`PG_STATUS`), through `people.change_status` with an instrument.

## 6 Business rules and validations
- `pg_register` / `pg_research_ensure`: "not a postgraduate student %" (23514). Coursework endpoints for a non-PG student: `PG_NOT_STUDENT` "Postgraduate coursework is for postgraduate students."
- Catalogue: `units` 0–12, kind ∈ CORE/ELECTIVE/DEFICIENCY/RESEARCH, semester 1–2 (`ck_pg_course_*`); a programme must be `POST GRADUATE` (404 otherwise). Import resolves programme by code or name, defaults units 3, kind CORE, semester from "2"/"s…"; counts created/updated/no_programme/skipped and reports `first_error`.
- GPA/CGPA (`pg_gpa`, `pg_cgpa`) weight points by units, excluding DEFICIENCY; standing PROBATION below 2.50 once any score exists, NEW before.
- Research documents: kinds checked (`PG_DOC_KIND`), closed record (`PG_DOC_CLOSED`), stage gates `PG_DRAFT_EARLY` "The draft is submitted for examination once your title is registered.", `PG_FINAL_EARLY` "The final copy is submitted after the oral examination.", `PG_CORRECTED_EARLY`; type sniffed (`%PDF-` or `PK`) and ≤25 MB (`PG_DOC_TYPE`, `PG_DOC_SIZE`); CHECK `ck_pg_rdoc_type` allows PDF and .docx only.
- Supervisor role ∈ FIRST/SECOND/CO (`PG_SUP_ROLE`); panel role list (`PG_PANEL_ROLE`); viva outcome list (`PG_VIVA_OUTCOME`); `PG_VIVA` "Record the viva score and outcome."
- `pg_award`: minute required ("an award is recorded on a Senate minute, and none was cited"), stage must be AWARD_RECOMMENDED/AWARDED, the student must have a matric number ("an award is recorded for a matriculated student; % has no matriculation number"), award name from `ref.programme.pg_award`, CGPA capped at 5, graduation session resolved from `policy.academic_session`.
- `finance.final_level` returns 900 for a PG programme so a postgraduate is never charged as a spillover (V255 §5).

## 7 Notifications
| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Any research stage change (SUPERVISED … WITHDRAWN) | `admissions.pg_research_trail` (V255) | student via `people.student_reach` (student_contact email, set at admission) | EMAIL | "Your research: {stage words}" with a stage-specific sentence, e.g. "A supervisor has been assigned to you…", "Senate has approved your award. Congratulations…" |
No notice is sent on registration endorsement, on a score recorded, on a document accepted/returned, or to supervisors/panel members. Coursework and research desks generate no desk-side mails.

## 8 Reports, exports and documents
- Course template download (`buildXlsx`, `CoursesDesk.tsx:174-185`) — the only file the coursework desks produce; there is no Excel export of registrations, results, the register, the pipeline or the Senate list (contrast the admissions desk).
- Student-facing academic documents (transcripts, statements) for postgraduates come from the credentials module (V262 reads `pg_registration/pg_score/pg_research`), not from here.
- The postgraduate return (`/api/v1/reports/postgraduate`) counts researching and awarded candidates.

## 9 Configuration
- Course catalogue (`pg_course`) per programme — the courses desk / upload.
- Grade bands are fixed in `admissions.pg_grade` (no table).
- Probation threshold 2.50 is hard-coded in `PgAdmissionsController.students` and `PgCourseworkController.summary`.
- PG examiner roster `admissions.pg_examiner` (2 rows locally, from demo data).
- Legacy imports: `POST /api/v1/results/legacy/pg-students|pg-registration|pg-results|pg-research|reconcile-pg-results` (results module, V214/V215) load old-portal postgraduates, coursework and research; `pg_legacy_holding` parks results for students not yet on the register.

## 10 Data
| Table | Purpose | Audit |
|---|---|---|
| `pg_course` | catalogue: programme_code, code, title, units, kind, semester, active; `uq_pg_course(programme_code, code)` | attached |
| `pg_registration`, `pg_registration_entry` | one per student/session/semester (`uq_pg_reg`), mode, state, endorsed_by/at; entries unique per course | attached; deferment gate trigger |
| `pg_score` | one per entry: ca, exam, total, grade, points, recorded_by | attached |
| `pg_research` | one per student (`student_id UNIQUE`), degree_kind, stage, topic, every milestone timestamp, pgsr, plagiarism_pct, viva_*, corrections_due | attached + `trg_pg_research_trail` |
| `pg_research_supervisor` | person_id (optional), name, role, is_external, assigned_at, ended_at (never set by any endpoint) | attached |
| `pg_research_panel` | name, role, is_external | attached |
| `pg_research_event` | stage, note, by_person (never populated by the controller), at | attached |
| `pg_research_document` / `_blob` | versioned files with status and reviewer note | attached / exempt |
| `pg_examiner` | roster: name, institution, field, tenure_from/to, active | attached |
| `pg_legacy_holding` | migration scratch | exempt |
Relationships: `pg_research.student_id → people.student`; `extexam.project.pg_research_id → pg_research` (module 3); `records.graduand` written by `pg_award`.

## 11 Scheduled jobs and integrations
None. Graduation list, alumni and certificates read the graduand row and student status that `pg_award` writes.

## 12 Security notes
- Coursework `DESK` has no HOD department scope (`PgCourseworkController` never uses `OfficeScope`); a HOD may endorse and score any PG registration.
- `endorse`/`score` derive `by` from the token subject; `pg_research_event.by_person` is left null so the milestone log does not record who acted (the audit spine does).
- Student research documents served with `sandbox` CSP; the desk's `deskDocument` scopes by research id only (SCHOOL sees all).
- `/student/pg-progress` eligibility is computed in the browser from the summary — advisory, not an authorisation.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| PG course catalogue + spreadsheet import | IMPLEMENTED | `PgCourseworkController.java:203-322`, `CoursesDesk.tsx` | |
| Student registration, mode, deferment gate | IMPLEMENTED | `register` line 187; V211 `pg_register`; V259 trigger | registration windows of the PG calendar are not enforced |
| Endorsement | IMPLEMENTED | line 379 | no precondition, no notice |
| Score entry, grade, GPA/CGPA | IMPLEMENTED | line 398; V211 functions | CA/exam weighting (30–40/60–70) is text only |
| Research lifecycle actions | IMPLEMENTED | `PgResearchController.java:232-312` | |
| Supervisors / panel | PARTIALLY IMPLEMENTED | `addSupervisor` line 158, `addPanelMember` line 185 | add only; no end/replace supervisor (Policy 14.6 `ended_at` unused), no remove panel member; supervisor picker `/examiners/supervisors` exists in module 3 but the PG desk takes a free-text name and never sets `person_id` |
| Versioned research documents + review | IMPLEMENTED | lines 351-441 | |
| Senate award → graduand, GRADUATED | IMPLEMENTED | V255 `pg_award`; `Board.tsx` | Research desk's own **Record Senate award** button sends no minute → always `PG_AWARD_MINUTE` |
| Thesis clearance, registration, examinations, Senate desks | IMPLEMENTED (read-only views) | `PgSecretaryController.java` | |
| PG students register + defer/withdraw/reinstate | IMPLEMENTED | `students` line 306, `setStatus` line 389 | |
| PG examiner roster (V213) | PARTIALLY IMPLEMENTED | `examiners`/`addExaminer` lines 353-383 | list + add only; `active`, tenure never editable; not linked to panels (`pg_research_panel` stores a free name) |
| Student research notices | IMPLEMENTED | V255 `pg_research_trail` | |
| Exports from coursework/research desks | NOT IMPLEMENTED | none | |
| Menu access for HOD/academic to courses/results desks | NOT IMPLEMENTED | menus.md | API admits them |
| Unlisted routes `t/pgsupervision`, `t/pgproposals`, `t/pgtheses` | CONFIGURED BUT UNUSED | `Shell.tsx:68-72` | |
| Legacy PG imports | IMPLEMENTED | V214, V215, `ResultsController` | belongs to the results/migration group |

## 14 Common problems and troubleshooting
- "This record is at 'x'; y follows 'z'." — the action was taken out of order; record the earlier step (the Advance list only offers valid next steps, the Board and Clearance pages act blindly on stage lists).
- "An award is recorded on a Senate minute." — type the minute on the Board page; the Research desk's award button cannot supply one.
- "an award is recorded for a matriculated student; X has no matriculation number" — matriculate the student (fees + registration on `/matriculation`) first.
- "The topic can no longer be changed here once the proposal is approved." — Policy 21.6; the desk has no topic-change action either (only the student before approval).
- "The draft is submitted for examination once your title is registered." — the student picked DRAFT too early; the default kind follows the stage.
- Score refused with a 23514 on `ck_pg_score_total` — CA + exam exceeds 100.
- "REGISTRATION UNAVAILABLE: your deferment for … is approved" — an approved deferment covers that session/semester.
- Student sees "No courses listed for this semester yet" — the catalogue has no active course for that programme and semester; note the student screen offers semesters 1–2 only while the calendar may define a Summer semester 3.
- Register shows CGPA "—" and standing "New" for a migrated student — their legacy results were held (`pg_legacy_holding`); run `reconcile-pg-results`.

## 15 Glossary
**Deficiency course** — earns no credit and is excluded from GPA. **PGSR** — Postgraduate School Representative at the seminar/viva. **Panel** — the per-candidate examiners (`pg_research_panel`), distinct from the School's **roster** (`pg_examiner`) and from the **extexam** workspace. **Standing** — NEW / GOOD / PROBATION (<2.50). **Degree kind** — PROJECT (PGD, taught Master's), DISSERTATION (research Master's), THESIS (900 level).

---

# Module 3 — External examiners
(API module: `examiners` — `ExaminersController` under `/api/v1/examiners`, `ExaminerNotifier`, `ExaminerReminders`; schema: `extexam`; pages: `/examiners`, `/examiners/[id]`, `/examiners/appointments`, `/examiners/projects`, `/examiners/projects/[id]`, `/examiners/assignments`, `/examiners/assignments/[id]`, `/examiners/reports`, `/examiners/rubrics`, `/examiner`, `/examiner/projects`, `/examiner/projects/[id]`, `/examiner/profile`, `/login/activate`)

## 1 Purpose
The University records a scholar from another institution as an external examiner, invites them by an emailed link that works once and expires in fourteen days, and they choose a password to activate an account (an `iam.person` without a staff number, office `extexaminer`). The desk records appointments (session, faculty, department, programme, period), registers a final-year project — an undergraduate's, or a postgraduate's research record — releases documents for external examination, and assigns the project to one or more active examiners by a deadline on a configurable assessment form (rubric with criteria in WRITTEN and DEFENCE sections). The examiner sees only their own assignments and released documents, scores each line, writes comments and a recommendation, saves drafts and submits once; the desk reads, locks, or reopens on a reason, extends deadlines, reassigns or withdraws. A morning job reminds and flags overdue reviews. Every act is in `extexam.event` (written once) and on the audit spine; the assessment feeds moderation and never writes an official result (db/V254 header).

## 2 Users and roles
- `DESK = academic, dregistrar, registrar, exams, hod, dean, pgschool, pgsecretary, admin, super` (`ExaminersController.java:63`).
- `FORM = academic, dregistrar, pgschool, admin, super` — rubric and criterion writes (line 64).
- `EXAMINER = extexaminer` — `/me/**` (line 65); `examinerOf()` also requires `extexam.examiner.status = 'ACTIVE'` else `EXAMINER_NOT_ACTIVE` "Your examiner appointment is not active."
- Public: `GET /invitation/{token}`, `POST /activate` (SecurityConfig line 57).
- **Reach** (`reach()`, lines 104-115): a department office (hod, exams, siwes, lecturer per `OfficeScope.DEPARTMENT_OFFICES`) sees projects, assignments, appointments and reports of its department; a faculty office (dean, facultyofficer) its faculty; everyone else the University. `requireProject` returns 404 "project" outside reach; `appoint` refuses another department with `EXAMINER_REACH`. The examiner register (`/list`, `/{id}`) is not reach-filtered.

## 3 Navigation
Group **Academic** in the menus of hod, dean, exams, academic, dregistrar, super, registrar, admin, pgschool and pgsecretary: External Examiners `/examiners`, Examiner Appointments `/examiners/appointments`, Project Assignments `/examiners/projects`, Assessments `/examiners/assignments`, Examiner Reports `/examiners/reports`. `/examiners/rubrics` ("Assessment Criteria") is reached only from buttons on the projects page. External examiner menu (`extexaminer`, home `x/dashboard`): Dashboard `/examiner`, My Projects `/examiner/projects`, Pending Reviews `?filter=pending`, Submitted Reviews `?filter=submitted`, My Profile `/examiner/profile`.

## 4 Screens

### 4.1 External Examiners (register) — `/examiners` (`ExaminersDesk.tsx`)
Loads `/examiners/dashboard`, `/examiners/list`, `/ref/structure`. PageHead actions **New Examiner**, **Project Assignments**, **Reports**; Session select; tiles Examiners ("{n} active · {m} awaiting activation"), Assigned projects, Pending reviews, Submitted ("{locked} locked · {avg} days on average"); "Overdue reviews" panel when any; "The register" with search and status filter (Invited, Pending activation, Active, Suspended, Inactive) and columns Examiner/email, Institution, Specialisation, Status (+ "link to {date}" while pending), Projects ("{pending} pending · {submitted} in"), Overdue, Sign-in, **Open**; "Projects by examiner", "Reviews by department" (meter), "Recent assignments". **New External Examiner** modal: Title, First name*, Middle name, Last name*, Email* ("Becomes the username"), Phone, Institution*, Department, Position or rank, Area of specialisation, Highest qualification, Professional qualifications, Years of academic experience (0–70), Country (default Nigeria), State or region, ORCID, Notes for the desk ("Never shown to the examiner"), checkbox "Send the invitation email now; the link works once and for fourteen days" → `POST /examiners` (then navigates to the record). Empty register: "No external examiner is on the register yet. Record one and send the invitation."

### 4.2 Examiner record — `/examiners/[id]` (`ExaminerDetail.tsx`)
"Act on the record": **Send Invitation / Resend Invitation** (`POST /{id}/invite`; hidden for SUSPENDED/INACTIVE), **Suspend or Deactivate / Set Active** (modal Standing + Reason ≥5 chars → `POST /{id}/status`), **Edit Record** (modal, all fields → `PUT /{id}`), **Record an Appointment** (modal: Academic session*, Semester (Whole session/First/Second), Examination period, Faculty*, Department*, Programme (or "Every programme of the department"), Appointment starts*/ends*, Letter or minute → `POST /{id}/appointments`), **Assign a Project** (link to `/examiners/projects?assign={id}`, disabled unless ACTIVE). Profile grid (with "On the PG roster" pill when `pg_examiner_id`), "CV and photo" with **Keep File** (PDF→CV, image→PHOTO, ≤5 MB → `POST /{id}/files`), tabs Projects / Appointments (with **End** via `window.prompt` → `POST /appointments/{id}/end`) / History.

### 4.3 Examiner Appointments — `/examiners/appointments` (server page)
Session chips (from `/ref/sessions`), table Examiner (+status pill), Session, Unit, Programme, From, To, Projects, Status, **Open**. Read-only list.

### 4.4 Project Assignments — `/examiners/projects` (`Projects.tsx`)
Actions **Register a Project**, **Every Assignment**, **Assessment Criteria**; Session select and Search. Table: Candidate (number · level), Project (kind, type, submitted), Programme, Supervisor, Session, Documents (red when 0), Examiners ("Not assigned" pill / names with status / "{n} submitted"), **Assign**, **Open**. **Register a Project** modal: Candidate* (type-ahead `GET /examiners/students?q=` — finalists at or above `finance.final_level` and postgraduates, ACTIVE/PROBATION, within reach; picking a PG candidate pre-fills the title with their research topic), Academic session*, Project type, Submission date, Project title* (≤400), Abstract (≤8000), Keywords, Project course code ("links moderation to the score sheet"), Co-supervisor, Supervisor (type-ahead `GET /examiners/supervisors?q=` over lecturers, or a typed name) → `POST /examiners/projects`. **Assign** modal: External examiner* (active only, "{pending} pending"), Assessment form (default for the kind), Review deadline*, Examination date → `POST /examiners/assignments`; warns "No document released yet" when the project has none.

### 4.5 Project — `/examiners/projects/[id]` (`ProjectDetail.tsx`)
Project grid (with "On the postgraduate research record" pill), "Documents for external examination" with per-file **Release/Withhold** toggle (`PUT /projects/{id}/documents/{doc}`) and an upload row (Kind: Project proposal, Final project report, Source code, Presentation, Supporting document; File PDF/Word/PowerPoint/ZIP ≤25 MB → `POST /projects/{id}/documents`; "Only what is released here reaches an examiner"), "Examiners" table (assigned by, deadline, status, assessment total/grade/recommendation, **Open**), History, and an **Assign an Examiner** modal excluding examiners already live on the project.

### 4.6 Assessments — `/examiners/assignments` (`Assignments.tsx`)
Tiles (Assignments shown, Pending, Overdue, Submitted "{n} locked"); filter bar Search, Session, Status (Pending, Submitted or locked, Not started, In review, Submitted, Locked, Reopened), Examiner, "Overdue only", **Search**/**Clear** → `GET /examiners/assignments?…`. Rows with **Extend** (modal New deadline*, Reason → `POST /assignments/{id}/deadline`), **Reassign** (modal New examiner* (active, not the current), Deadline for the new examiner, Reason* ≥5 → `/reassign`; link "Withdraw the assignment instead"), **Withdraw** (Reason* → `/withdraw`), **Open / View Assessment**. LOCKED rows hide Extend/Reassign.

### 4.7 Assessment — `/examiners/assignments/[id]` (`AssignmentDetail.tsx`)
State note: SUBMITTED → **Approve and Lock** (`window.confirm`, `POST /assessments/{id}/lock`) and **Reopen**; LOCKED → **Reopen**; REOPENED shows the reason; otherwise "The examiner has not started" / "In review" with first-opened time and draft-saved time. Panels: The assignment, Documents the examiner was given, The assessment (per-section tables with the examiner's score and comment, subtotals; General comments, Strengths, Weaknesses, Recommendations, Required corrections, Final recommendation), History. **Reopen** modal requires a reason ≥5 → `POST /assessments/{id}/reopen`. "The desk never types a score."

### 4.8 Examiner Reports — `/examiners/reports` (`Reports.tsx`)
Eight report kinds as buttons (External Examiner, Project Assessment, Examiner Workload, Department Assessment, Programme Assessment, Pending Review, Overdue Review, Submitted Assessment) with filters Session, Faculty, Department, Programme, Examiner, Status, Assigned from/to → `GET /examiners/reports?kind=…`; **Download** produces a **CSV** via `csv/download` from `lib/results` (not the branded Excel). Empty: "Nothing in this scope yet."

### 4.9 Assessment Criteria — `/examiners/rubrics` (`Rubrics.tsx`)
One panel per rubric (kind pill, Active/Inactive, "{used} assignments · total {n}", **Set Inactive/Active** for FORM offices), section tables (criterion, guidance, maximum, order, state, **Edit**), **Add a Line** per section (modal Criterion*, Guidance, Maximum mark*, Section, Order, Active → `POST /rubrics/{id}/criteria` / `PUT /criteria/{id}`; "Changing a maximum affects assessments in draft; a submitted assessment keeps the marks it was given."), **New Form** (Name*, For UG/PG, Has a defence section, Note → `POST /rubrics`). Non-FORM offices see "Read-only".

### 4.10 Examiner Workspace — `/examiner` (server page)
`GET /examiners/me`: PageHead "Welcome, {name}" with institution and appointments; tiles Assigned projects, Pending reviews ("{n} not started · {m} in review"), Submitted, Overdue; a red note when overdue; "Upcoming deadlines", "Recent assignments", "Recently submitted", "Your appointment". Row buttons **Start Review / Continue / View**.

### 4.11 My Projects — `/examiner/projects[?filter=pending|submitted]`
Table Candidate, Project title ("{n} documents" or "No documents released yet"), Programme, Supervisor, Session, Submitted, Deadline (+ days words), Status (+ recommendation), **Start Review / Continue Review / View Assessment**.

### 4.12 Review — `/examiner/projects/[id]` (`Review.tsx`)
`GET /examiners/me/projects/{id}` (records `first_viewed_at` and `PROJECT_VIEWED` once). State note (deadline; "Reopened by the University on … {reason}"; read-only after submission). Panels The candidate, The project (abstract), Documents (released only, `/me/projects/{id}/documents/{doc}/content`), "Assessment · {rubric}" — per section a table with Maximum, Score input (red "Over {max}" when exceeded) and Comment; subtotals; Total "Computed from the scores; it is not typed." — "Comments and recommendation" (General comments* "At least a sentence or two", Strengths, Weaknesses, Recommendations, Required corrections, Final recommendation* Pass / Pass subject to corrections / Reassessment required / Fail). **Save Draft** (`PUT …/assessment`), **Submit Assessment / Resubmit Assessment** enabled only when every line is scored, none over maximum, a recommendation chosen and general comments ≥20 characters; a confirmation modal "Submit this assessment?" then `PUT` + `POST …/assessment/submit`. History panel.

### 4.13 My Profile — `/examiner/profile` (`Profile.tsx`)
"On the University's record" (read-only: Name, Email (your username), Institution, Status, Projects assigned, Submitted) and "Keep current" (Phone, Department, Position or rank, Area of specialisation, Highest qualification, Professional qualifications, Years of academic experience, Country, State or region, ORCID → `PUT /examiners/me/profile`).

### 4.14 Activation — `/login/activate?token=` (`Activate.tsx`)
`GET /examiners/invitation/{token}` → "Dear {name} ({institution}), the University invites you to serve as an External Examiner for {appointment}… Your username will be {email}." Password* ("At least ten characters, not containing your email address"), Password again* → `POST /examiners/activate`; success "Your examiner account is active" → **Sign In**. Bad link: "This invitation link has expired or was already used."

## 5 Workflow and statuses
**Examiner** `extexam.examiner.status` ∈ `INVITED, PENDING_ACTIVATION, ACTIVE, SUSPENDED, INACTIVE`. Create → INVITED (or PENDING_ACTIVATION when invited at once); `invite` spends any live invitation, mints a 32-byte hex token stored as SHA-256, 14 days, sets PENDING_ACTIVATION unless already ACTIVE, emails the link `{portalUrl}/login/activate?token=`; `activate` checks the hash, unused, unexpired, not SUSPENDED/INACTIVE, password ≥10 and not containing the email, username not taken (`EXAMINER_USERNAME_TAKEN`), writes/updates `iam.credential` (username = email), `iam.credential_event`, grants `iam.office_assignment` office `extexaminer` scope institution (`grantOffice`), sets ACTIVE and `activated_at`, marks the invitation used, records `ACCOUNT_ACTIVATED`, and emails the desk. `status` to SUSPENDED/INACTIVE requires a reason and ends the office grant via `iam.end_grant`; to ACTIVE requires a prior activation (`EXAMINER_NOT_ACTIVATED`) and re-grants the office.

**Appointment** `status` ∈ `ACTIVE, ENDED, SUSPENDED`; `ends_on ≥ starts_on`; `end` sets ENDED and clips `ends_on` to today. SUSPENDED is never set by any endpoint.

**Assignment** `status` ∈ `ASSIGNED, IN_REVIEW, SUBMITTED, LOCKED, REOPENED, REASSIGNED, WITHDRAWN`; `ck_ee_asg_ended` ties REASSIGNED/WITHDRAWN to `ended_at`; `uq_ee_asg_live` one live assignment per (project, examiner).
| From | Act | By | To |
|---|---|---|---|
| — | `assign` (examiner ACTIVE, deadline ≥ today, rubric active for the kind, appointment auto-matched by session+dept) | DESK | ASSIGNED; email "New Project Assigned for Review" |
| ASSIGNED | first save/start by examiner (`ensureAssessment`) | examiner | IN_REVIEW (assessment DRAFT) |
| DRAFT/REOPENED | `extexam.submit` | examiner | SUBMITTED; assessment SUBMITTED; desk emailed "Assessment Submitted/Resubmitted", examiner "Assessment Received" |
| SUBMITTED | `extexam.lock` | DESK | LOCKED; email "Assessment Approved and Locked" |
| SUBMITTED/LOCKED | `extexam.reopen` (reason) | DESK | REOPENED; version+1, submitted/locked cleared; email "Assessment Reopened for Revision" |
| not LOCKED, live | `reassign` (new ACTIVE examiner, reason) | DESK | old REASSIGNED with `replaced_by`; new ASSIGNED; two emails |
| not LOCKED, live | `withdraw` (reason) | DESK | WITHDRAWN; email |
| live | `deadline` | DESK | same; clears `reminded_at` if later, `overdue_told_at` if ≥ today; email "Review Deadline Changed" |

**Assessment** `state` ∈ `DRAFT, SUBMITTED, LOCKED, REOPENED`; `final_recommendation` ∈ `PASS, PASS_WITH_CORRECTIONS, REASSESSMENT, FAIL`; `ck_ee_ass_submitted` demands submitted_at, total and a recommendation when SUBMITTED/LOCKED. `extexam.compute` sums scores over active criteria, sets `max_total`, `percentage`, and `grade` from **`policy.grade_of`** — the University's undergraduate scheme — for both UG and PG rubrics; total/percentage/grade are null while any active line is unscored.

**Event** actions (CHECK on `extexam.event.action`): EXAMINER_CREATED, EXAMINER_EDITED, EXAMINER_INVITED, INVITATION_RESENT, ACCOUNT_ACTIVATED, EXAMINER_STATUS, APPOINTED, APPOINTMENT_ENDED, PROJECT_CREATED, PROJECT_EDITED, DOCUMENT_RELEASED, DOCUMENT_WITHDRAWN, PROJECT_ASSIGNED, PROJECT_REASSIGNED, ASSIGNMENT_WITHDRAWN, DEADLINE_CHANGED, PROJECT_VIEWED, ASSESSMENT_STARTED, ASSESSMENT_SAVED, ASSESSMENT_SUBMITTED, ASSESSMENT_LOCKED, ASSESSMENT_REOPENED, ASSESSMENT_RESUBMITTED. `trg_ee_event_written_once` refuses UPDATE/DELETE unless `moaum.maintenance = on`.

## 6 Business rules and validations (messages as written)
- Create: `EXAMINER_EXISTS` "An examiner with that email is on the register already."; email lower-cased and regex-checked (`ck_ee_email`); institution non-blank; experience 0–70.
- Invite: `EXAMINER_NOT_INVITABLE` "A suspended or inactive examiner is not invited."; activation `EXAMINER_INVITE_TOKEN` "This invitation link has expired or was already used." / `AUTH_WEAK_PASSWORD`.
- Status: `EXAMINER_STATUS`, `EXAMINER_NOT_ACTIVATED`, `EXAMINER_STATUS_REASON` "Suspending or deactivating an examiner records the reason."
- Files: CV/PHOTO only (`EXAMINER_FILE_KIND`), PDF/JPEG/PNG ≤5 MB, bytes sniffed (`EXAMINER_FILE_TYPE` "The file is not of a kind accepted here, or its contents are not what its name says."); project documents PDF/DOCX/PPTX/ZIP ≤25 MB, filename ≤200 (`PROJECT_DOC_KIND` for kinds).
- Project: one per (student, session) (`uq_ee_project`); kind POSTGRADUATE when the student is PG, with `pg_research_id` linked if a research record exists; title non-blank.
- Assign: `EXAMINER_NOT_ACTIVE` "A project is assigned to an examiner whose account is active.", `ASSIGNMENT_DEADLINE` "The review deadline is today or later.", `ASSIGNMENT_APPOINTMENT` "The appointment named is not this examiner's live appointment.", `ASSIGNMENT_RUBRIC` "No active assessment form exists for this kind of project.", `ASSIGNMENT_EXISTS` "This project is with that examiner already."
- Reassign/withdraw: `ASSIGNMENT_ENDED`, `ASSIGNMENT_LOCKED` "A locked assessment is not reassigned." / "…not withdrawn.", `ASSIGNMENT_REASON`.
- Scoring (`extexam.score`): "a submitted assessment is read-only" (hint "Ask the department to reopen it…"), "% is marked out of %"; save: `ASSESSMENT_READ_ONLY`, `ASSESSMENT_RECOMMENDATION`.
- Submit (`extexam.submit`): "the assessment is submitted already", "this assignment has ended", "every criterion is scored before submission; still unscored: …", "a final recommendation is given before submission", "the general comments say something about the work" (<20 chars).
- Lock/reopen: "only a submitted assessment is locked; this one is …", "only a submitted or locked assessment is reopened", "reopening an assessment records the reason".
- Reports: `REPORT_KIND` lists the eight kinds. Rubric: `ck_ee_criterion_max` 0<max≤100, section WRITTEN/DEFENCE; a criterion is deactivated, never deleted; new rubric code derived from the name.

## 7 Notifications (`ExaminerNotifier`, EMAIL via `NoticeRepository.queueEmail`, signed "Academic Office / Rev. Fr. Moses Orshio Adasu University, Makurdi")
| Event | Trigger | Recipient | Subject |
|---|---|---|---|
| Invitation / resend | `invite` | examiner | "External Examiner Appointment — {University}" (link, expiry) |
| Account activated | `activate` | whoever sent the invitation + every current `academic` office holder | "External examiner account activated — {name}" |
| Appointment recorded | `appoint` | examiner | "External Examiner Appointment — …" (unit, dates) |
| Project assigned / reassigned to | `assign`, `reassign` | new examiner | "New Project Assigned for Review — …" |
| Reassigned away | `reassign` | old examiner | "Project Assignment Withdrawn — …" (reason) |
| Withdrawn | `withdraw` | examiner | "Project Assignment Withdrawn — …" |
| Deadline changed | `deadline` | examiner | "Review Deadline Changed — …" |
| Reminder (≤3 days) | `ExaminerReminders` | examiner | "Reminder: Project Review Deadline — …" |
| Overdue | `ExaminerReminders` | examiner and desk (assigner + academic) | "Project Review Overdue — …" / "External examiner review overdue — {number}" |
| Submitted / resubmitted | `submit` | desk (assigner + academic) and examiner | "External Examiner Assessment Submitted — {number}" / "Assessment Received — …" |
| Reopened | `reopen` | examiner | "Assessment Reopened for Revision — …" |
| Locked | `lock` | examiner | "Assessment Approved and Locked — …" |
No SMS. The "desk" is the person who assigned plus current `academic` office holders — never the HOD or the PG School unless they assigned.

## 8 Reports, exports and documents
- Reports endpoint kinds: examiners (assigned, submitted, pending, overdue, avg days, avg %), workload, department, programme (with PASS / corrections / reassess / fail counts), assessments, pending, overdue, submitted (rows capped at 2000). Download is CSV with a three-line header (Report, Session, Rows).
- `GET /examiners/moderation?session=&dept=` returns per project the submitted/locked external assessments (JSON), their average percentage, and the internal course total from `assessment.score` when `course_code` matches — **no screen calls it** (grep of `frontend/src` finds no use).
- No PDF is generated by this module (no appointment letter, no assessment report PDF).

## 9 Configuration
- Rubrics seeded by V254: `UG_DEFAULT` "Undergraduate Final-Year Project" (written 80 + defence 20 across 13 criteria) and `PG_DEFAULT` "Postgraduate Project, Dissertation or Thesis" (written 70 + defence 30 across 9 criteria); edited on `/examiners/rubrics` by FORM offices.
- `moaum.portal-url` for links; reminder cron `0 15 7 * * *` Africa/Lagos (`ExaminerReminders.java:212`).
- Office `extexaminer` (label "External Examiner", scope institution) inserted by V254; grants written per activation.
- Demo: `demo.extexaminer@example.edu` (University of Jos) seeded ACTIVE by `db/demo.sql:151-155`.

## 10 Data
| Table | Purpose | Audit |
|---|---|---|
| `extexam.examiner` | person_id (unique), optional `pg_examiner_id` → `admissions.pg_examiner`, title, email (unique), institution, department, rank, specialization, qualification, professional, experience_years, country, region, orcid, status, notes, activated_at | attached |
| `examiner_file` / `_blob` | CV or PHOTO | attached / exempt |
| `invitation` | token_hash, sent_by, expires_at, used_at | exempt |
| `appointment` | session, semester, faculty/dept/programme, period, starts_on, ends_on, status, instrument, appointed_by | attached |
| `project` | student_id, kind, pg_research_id, course_code, session, title, abstract, keywords, project_type, submitted_on, supervisor_id/name, co_supervisor; unique (student, session) | attached |
| `project_document` / `_blob` | kind, filename, content_type, bytes, released | attached / exempt |
| `rubric`, `criterion` | forms and lines (section, max_score, ordinal, active) | attached |
| `assignment` | project, examiner, appointment, rubric, deadline, exam_date, status, assigned_by, first_viewed_at, ended_at/reason, replaced_by, reminded_at, overdue_told_at | attached |
| `assessment` | one per assignment: state, total, max_total, percentage, grade, comments, final_recommendation, version, timestamps, reopen_reason | attached |
| `assessment_score` | (assessment, criterion) score, comment | attached |
| `event` | write-once history with actor name/office | attached + written-once trigger |
Grants: `app_results`, `app_admissions` SELECT/INSERT/UPDATE (no DELETE; no UPDATE on event or blobs).

## 11 Scheduled jobs and integrations
`ExaminerReminders.run()` daily 07:15 Lagos: reminds once per live assignment (ASSIGNED/IN_REVIEW/REOPENED, examiner ACTIVE) whose deadline is within 3 days (`reminded_at`), and tells examiner + desk once when the deadline has passed (`overdue_told_at`); 200 rows per pass with `FOR UPDATE SKIP LOCKED`; runs under actor NOBODY, office `academic`; a failure is logged as a warning only. Sign-in for examiners uses the ordinary staff door (`iam.credential`, username = email).

## 12 Security notes
- Public activation is token-hash based, single-use, 14 days; the token is never stored in clear; a taken username is refused.
- The examiner reaches only live assignments of their own (`myAssignment`), only released documents (`document(…, releasedOnly=true)`), and never `notes`; the desk's `notes` field is stripped from `/me`.
- Suspension ends the office grant immediately, so the token's `OFFICE_extexaminer` authority disappears at the next token issue and `examinerOf()` refuses in the meantime.
- Reach filters are applied on the server for projects, assignments, appointments, dashboard and reports; the examiner register itself is University-wide for every DESK office.
- Grade from `policy.grade_of` (UG scheme) on PG assessments is a modelling choice worth documenting.
- Files are sniffed by magic number; served with `Content-Security-Policy: sandbox` and `nosniff`.

## 13 Implementation status
| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Examiner register, create/edit, files | IMPLEMENTED | `ExaminersController.java:204-382` | |
| Invitation link, activation, office grant | IMPLEMENTED | lines 287-312, 1064-1116; `Activate.tsx` | |
| Status active/suspended/inactive with grant follow | IMPLEMENTED | lines 325-355 | appointment SUSPENDED status unused |
| Appointments (record, list, end) | IMPLEMENTED | lines 386-434 | end via `window.prompt` |
| Project register, documents release/withhold | IMPLEMENTED | lines 451-581 | |
| Assign / reassign / deadline / withdraw | IMPLEMENTED | lines 665-806 | |
| Examiner workspace, draft, submit, resubmit | IMPLEMENTED | lines 900-1060; `Review.tsx` | |
| Lock / reopen | IMPLEMENTED | lines 810-830 | |
| Rubrics and criteria | IMPLEMENTED | lines 585-643; `Rubrics.tsx` | |
| Reports (8 kinds) + CSV | IMPLEMENTED | lines 834-878; `Reports.tsx` | CSV, not branded Excel |
| Moderation feed | PARTIALLY IMPLEMENTED | line 881; no frontend caller | backend without UI |
| Reminder / overdue job | IMPLEMENTED | `ExaminerReminders.java` | |
| Link to PG roster (`pg_examiner_id`) | PARTIALLY IMPLEMENTED | create/edit accept `pgExaminerId`; `ExaminerDetail.tsx:247` pill | no picker in the UI sets it |
| PG research ↔ extexam project | PARTIALLY IMPLEMENTED | `newProject` line 499 links `pg_research_id`; `/students` returns `pg_topic` | the PG research desk never shows the external assessment, and the extexam result never feeds `pg_research.viva_*` |
| Appointment letter / assessment PDF | NOT IMPLEMENTED | none | |
| End-to-end test | IMPLEMENTED | `api/src/test/java/ng/edu/moaum/portal/ExaminersIT.java` (`theWholeJourneyAndItsWalls`) | needs DATABASE_URL |

## 14 Common problems and troubleshooting
- "Your examiner appointment is not active." — the examiner's status is not ACTIVE (never activated, suspended, or inactive); the desk sends/resends the invitation or sets Active (only after a first activation).
- "This invitation link has expired or was already used." — fourteen days passed, a newer invitation superseded it, or it was spent; resend from the record.
- "A project is assigned to an examiner whose account is active." — wait for activation; the Assign picker lists active examiners only.
- "every criterion is scored before submission; still unscored: …" — score every active line; the Submit button is disabled client-side until then, so this appears only when a criterion was added to the form after the draft.
- "This project is with that examiner already." — reassign or extend instead; a second examiner must be a different person.
- Examiner sees "No documents released yet" — release the report on the project page (withheld files never reach them).
- No reminder arrived — reminders go once per deadline (`reminded_at`); moving the deadline later resets it; the job only runs at 07:15 Lagos and needs the mail dispatcher configured.
- A HOD cannot find a project — it is outside their department (reach → 404 "project"); an Examinations Officer likewise.

## 15 Glossary
**Rubric / assessment form** — `extexam.rubric` with **criteria** (lines) in the **WRITTEN** and **DEFENCE** sections. **Assignment** — one examiner on one project by a deadline. **Assessment** — the examiner's scored form, one per assignment, versioned on reopen. **Released document** — a project document with `released = true`, the only kind an examiner can read. **Reach** — the unit (department/faculty) a desk office is limited to. **Locked** — approved by the desk; read-only to everyone.

---

# Appendix — pages in this group that are not postgraduate

- `/research/projects` (`research/projects/Projects.tsx`, route `t/projects` in the lecturer, dean and vc menus, titled "My Projects" / "Research in the Faculty" / "Research") is the **research grants** register of the expenditure module (`/api/v1/research/grants`, table `expenditure.research_grant`, states PROPOSED/ACTIVE/COMPLETED/CLOSED/SUSPENDED; writes allowed to bursar, dvc, super). It has nothing to do with postgraduate research and belongs to the finance/expenditure dossier.
- `/ethics` (`ethics/page.tsx`, route `t/ethics`, listed in no menu) renders two static panels ("Research ethics review", "Open-access repository") and states that "A live application queue and a populated repository arrive with the research-administration module" — **PLACEHOLDER**, no API call beyond `/iam/me`.

# Verification notes
- Local DB counts at audit time: 9 PG applications, 5 research records, 4 PG courses, 2 roster examiners, 5 extexam examiners, 1 extexam project; `admissions.pg_fee` empty (defaults in force); PG calendar has no CURRENT session.
- `api.md` lists `PgCalendarController` paths as `/` and `/sessions/...`; the real paths are `/api/v1/pg/calendar` and `/api/v1/pg/calendar/sessions/{session}/{year}[/make-current|/close|/semesters/{n}]`. `PUT /api/v1/pg/sessions/{session}/{year}/fees` (set fees) is absent from api.md but present at `PgAdmissionsController.java:102`.
- End-to-end tests: `PgLifecycleIT.fromApplicationToAward` and `ExaminersIT.theWholeJourneyAndItsWalls` cover the journeys described above.
