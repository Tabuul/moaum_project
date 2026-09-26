# 04 — Role and Permission Matrix

**MOAUM Unified University Portal** — Rev. Fr. Moses Orshio Adasu University, Makurdi — Directorate of ICT
Documentation package, volume 4 of 9. Companion volumes: *01 User Manual*, *02 Administrator Manual*, *03 Technical Documentation*, *05 Module Navigation Guide*, *06 Workflows*, *07 API Reference*, *08 Database Reference*, *09 Feature Status Report*.

This volume describes who may do what on the portal **as the code enforces it today**. Every list of offices below was read from the `@PreAuthorize` guards of the API controllers (schema version V263), from the office register `ref.office`, from the office menus in `frontend/src/lib/menus.ts`, and from the audit dossiers prepared for this package. Where the menu and the API disagree, the API is authoritative and the disagreement is listed in §4. Where a rule is intended but not enforced, this volume says so.

> **Note:** The portal has no "roles" in the usual sense. It has **offices** — the Registrar, the Bursar, a Head of Department — and a person holds one or more of them under a letter or minute. Everything in this volume is expressed in offices.

## Table of contents

1. [How authorisation works](#1-how-authorisation-works)
   1. [Offices and scope kinds](#11-offices-and-scope-kinds)
   2. [Sign-in and the token](#12-sign-in-and-the-token)
   3. [The acting office](#13-the-acting-office)
   4. [Guards on the API](#14-guards-on-the-api)
   5. [Scope binding](#15-scope-binding)
   6. [The audit spine and the acting office](#16-the-audit-spine-and-the-acting-office)
   7. [What the frontend does and does not decide](#17-what-the-frontend-does-and-does-not-decide)
   8. [The layers at a glance](#18-the-layers-at-a-glance)
2. [Role catalogue](#2-role-catalogue)
   1. [The office register](#21-the-office-register)
   2. [Sign-in identities that are not staff offices](#22-sign-in-identities-that-are-not-staff-offices)
   3. [Authority, reports and settings by office](#23-authority-reports-and-settings-by-office)
3. [Module × office permission matrix](#3-module--office-permission-matrix)
   1. [How to read the matrix](#31-how-to-read-the-matrix)
   2. [The generated matrix](#32-the-generated-matrix)
   3. [Finer rules by module](#33-finer-rules-by-module)
4. [Known mismatches between menus and guards](#4-known-mismatches-between-menus-and-guards)
5. [User creation and role assignment](#5-user-creation-and-role-assignment)
   1. [The staff account lifecycle](#51-the-staff-account-lifecycle)
   2. [Step table: staff accounts and grants](#52-step-table-staff-accounts-and-grants)
   3. [Bulk onboarding](#53-bulk-onboarding)
   4. [Student accounts](#54-student-accounts)
   5. [Applicant and postgraduate applicant accounts](#55-applicant-and-postgraduate-applicant-accounts)
   6. [External examiner accounts](#56-external-examiner-accounts)
   7. [The first account (bootstrap)](#57-the-first-account-bootstrap)
   8. [Sessions, lockout and sign-out](#58-sessions-lockout-and-sign-out)
   9. [Demo accounts](#59-demo-accounts)
6. [Permission inheritance and precedence](#6-permission-inheritance-and-precedence)
7. [Quick reference by office group](#7-quick-reference-by-office-group)
   1. [Registry](#71-registry)
   2. [Academic Office, Exams and Records](#72-academic-office-exams-and-records)
   3. [Bursary and Audit](#73-bursary-and-audit)
   4. [ICT and platform](#74-ict-and-platform)
   5. [Faculties, departments and the College](#75-faculties-departments-and-the-college)
   6. [Postgraduate School and external examiners](#76-postgraduate-school-and-external-examiners)
   7. [Students and applicants](#77-students-and-applicants)
   8. [Services, housing, library, security, health](#78-services-housing-library-security-health)
8. [Appendix: guard constants referenced in this volume](#8-appendix-guard-constants-referenced-in-this-volume)

---

## 1 How authorisation works

### 1.1 Offices and scope kinds

The register of offices is the table `ref.office` (code, label, scope kind). It holds **34 rows**: 32 staff offices plus `student` and `applicant`. The deployment check `db/verify.sql` raises if the count is not 34. No screen edits this table; a new office arrives by migration (see *02 Administrator Manual*).

Each office carries a **scope kind**, which says what a grant of that office is bounded to:

| Scope kind | Meaning | Offices |
|---|---|---|
| `platform` | The whole service; not tied to the University's structure | `super`, `admin`, `ict`, `ictagent` |
| `institution` | The University as a whole | `vc`, `dvc`, `registrar`, `dregistrar`, `academic`, `records`, `bursar`, `audit`, `hrm`, `pgschool`, `pgsecretary`, `extexaminer`, `housing`, `student`, `applicant` |
| `college` | One college (today the College of Health Sciences) | `provost`, `collegesecretary`, `financecontroller` |
| `faculty` | One faculty | `dean`, `facultyofficer`, `facultyexams` |
| `department` | One department | `hod`, `siwes` |
| `programme` | One programme | `exams` |
| `course` | The courses the person is allocated | `lecturer` |
| `level` | One level of study (MBBS Coordinator: 200–600) | `mbbscoordinator` |
| `unit` | One administrative unit | `deputyaudit`, `services`, `security`, `library` |

The scope kind is a default the Users & Roles console presets when an office is chosen; the actual bound of a grant is the `scope_kind` and `scope_id` written on the grant row (`iam.office_assignment`). The database CHECK `ck_grant_scope` accepts the nine kinds above.

### 1.2 Sign-in and the token

There is one sign-in door (`/login`). The frontend reads the shape of the identifier and forwards it to the right API door (staff `/api/v1/auth/sign-in`, student `/api/v1/student-auth/sign-in`, applicant `/api/v1/applicant/sign-in`, postgraduate applicant `/api/v1/pg/sign-in`). On success the API issues an HS256 JWT (12 hours) bound to a server-side session row (`platform.session`). The token's `offices` claim lists the codes of the person's **live** grants at that moment (`iam.live_offices`): a grant is live while `valid_from <= today <= coalesce(valid_to, ∞)`.

Spring Security turns each code into an authority `OFFICE_<code>`; every guard in the API is written against those authorities. A student's token carries exactly `["student"]`; an applicant's and a postgraduate applicant's exactly `["applicant"]`; an external examiner's `["extexaminer"]`.

> **Note:** Grants take effect at the next sign-in. A person granted an office while signed in must sign out and in again before the token carries it; a person whose grant was ended keeps the authority until their session ends (12 hours at most, or earlier if the API restarts — see §5.8).

### 1.3 The acting office

A person may hold several offices but acts in **one at a time**. The frontend keeps the chosen office in a readable cookie `moaum_office` and sends it on every API call as the header `X-Active-Office`. The API (`AuditContextFilter`) checks the header against the token:

- header names an office the token does not carry → **403** `The office 'x' is not one this token carries: […]`;
- no header → the first office in the token is the acting office;
- no office at all → the request proceeds but may only read (any write is refused by the audit spine, §1.6).

The office switcher in the sidebar ("Signed in as") rewrites the cookie and refreshes the page; it does not call the API and does not update `platform.session.active_office`, which is set once at sign-in. Attribution is nevertheless correct because the audit spine reads the header, not the session row.

### 1.4 Guards on the API

Every controller method is annotated `@PreAuthorize(...)`. Three forms occur:

| Form | Meaning | Example |
|---|---|---|
| `hasAnyAuthority('OFFICE_a','OFFICE_b',…)` | Only the listed offices | `AccountsController.GRANTORS` = registrar, dregistrar, vc, super, ict, admin |
| `isAuthenticated()` (with or without an exclusion) | Any signed-in person | `/api/v1/calendar/**` reads, `/api/v1/ref/**`, `/api/v1/staff/**`, help-desk requester (`isAuthenticated() and !hasAnyAuthority('OFFICE_applicant','OFFICE_pgapplicant')`) |
| permit-all (listed in `SecurityConfig`) | No token | sign-in doors, `/api/v1/verify/**`, payment webhooks, `/api/v1/platform/status`, examiner invitation/activation, PG public routes |

The lists are **explicit and closed**. `super` appears where it was written and nowhere else (see §6). Most controllers name their lists as constants (`READERS`, `WRITERS`, `DESK`, `OFFICE`, `SIGNERS`, …); §8 collects the ones this volume refers to. The generated matrix in §3 was built by reading every one of these annotations (919 endpoints).

A guard decides *which office* may call an endpoint. Two further checks happen inside the service or the database for many endpoints: **scope** (§1.5) and **stage / ownership** rules (for example, a lecturer reaches only the score sheets of courses allocated to them; the officer who generated a document may not release it). Those finer rules are listed per module in §3.3.

### 1.5 Scope binding

Scope is **not in the token**. It is applied per request by `shared/OfficeScope.java`, which reads the acting office and looks up the person's grant:

| Office family | Bound to | How the bound is resolved |
|---|---|---|
| Department offices — `hod`, `exams`, `siwes`, `lecturer` | Their department | The `scope_id` of the acting grant when its kind is `department`; else the department of the person's `lecturer` grant; else `hrm.staff_record.home_department`; else the sentinel `__none__` (sees nothing) |
| Faculty offices — `dean`, `facultyofficer` | Their faculty | The `scope_id` of the grant when its kind is `faculty`; else the faculty of the staff record's department; else `__none__` |
| College offices — `provost`, `collegesecretary`, `financecontroller` | The college | The grant's college, else the staff record's faculty's college, else the sole college (Provost dashboard); deferments bind them to faculties whose `college_code = 'CHS'` |
| MBBS Coordinator | One level (200–600) | The grant's `scope_id` when `scope_kind = 'level'`; a grant without one is refused at every act (`COLLEGE_NO_LEVEL`) |
| Postgraduate School offices | Postgraduate students | Deferments and statistics bind `pgschool`/`pgsecretary` to `is_pg` rows |
| Everyone else | The University | No cut |

`OfficeScope.bound(faculty, department, programme)` refuses a parameter outside the bound with `SCOPE_DEPARTMENT` / `SCOPE_FACULTY` ("That department is not in your faculty."). `reportScope()` cuts the returns and registers to the faculty or department.

> **Warning:** Scope is enforced **only where a controller calls it**. The dossiers found several desks that do not: the matriculation faculty lists (a Faculty Officer can open and confirm any faculty's list by URL), the postgraduate coursework desk (a HOD may read and score any programme's registrations), the CBT question bank (any reader sees every course), the hostel desk (no hall-level scope), the student help-request desk (a HOD sees every request addressed to "hod"), and the held-scripts endpoints (no ownership check on hold or withdraw). These are listed against their modules in §3.3.

The structure ladder served by `/api/v1/ref/structure` is pruned to the same bounds, so the scope bars on the screens usually offer only what the office may open.

### 1.6 The audit spine and the acting office

Every state table is attached to the audit spine: an `AFTER INSERT OR UPDATE OR DELETE` trigger (`audit.record`) writes a hash-chained entry carrying the **actor** (person id), the **acting office**, the **reason** (`X-Reason` header), the correlation id and the source IP, and it **refuses the write** when no actor or office is set on the transaction. The application places those values at the start of every transaction from the request's audit context (`AttributedTransactionManager`).

Consequences for authorisation:

- A request with no acting office can read but not change anything: the database refusal surfaces as **403 `NO_ACTING_OFFICE`** — "This request names no acting office, so it may read but not change anything." Remedy: "Send X-Active-Office with one of the offices your token carries."
- The office written to the trail is the acting office of that request, so a person holding two offices is recorded in the one they chose.
- Several SQL functions check the acting office themselves in addition to the controller guard (payment-voucher desks, CAPS intake, the O'Level score), so switching office changes what the database will accept, not only what the API will.
- The grantor of an office, the officer who confirms a payment, the person who releases a document — all are taken from the audit context, never from the request body.

The audit trail (`/audit`) is readable by `ict`, `admin`, `super`, `audit`, `deputyaudit` and `vc` only (see §4 for the Registrar's menu item).

### 1.7 What the frontend does and does not decide

The frontend repeats the guard lists in three places, for convenience only:

| Mechanism | What it does | Authoritative? |
|---|---|---|
| Office menus (`lib/menus.ts`, one tree per office) | Decide which items the sidebar shows | No — a URL typed by hand opens the page; the API then allows or refuses the data calls |
| `RoleLine` component ("You may act — <office>" / "Signed in as <office> · view only") and per-screen `MAY` arrays | Grey out buttons and explain who acts on a desk | No — copied by hand from the guards; can drift (§4 lists the drift found) |
| Home routing in `app/page.tsx` | Sends an office to its dashboard | No |
| The Next.js proxy (`proxy.ts`) | Requires the session cookie for every non-public path; validates a page navigation against `/api/v1/iam/me` | Only for "signed in or not" |

The **API guards are authoritative**. When a menu item leads to a page whose data calls the API refuses, the page renders a `ProblemNotice` ("You don't have access to this screen") and a toast "You do not have access to that".

An office with no menu of its own falls back to the Shell's `FALLBACK` menu (label "Office": Records → Search, Dashboard; Me → Leave & Payslip). Today exactly one office is in this position: the **Deputy Director of Audit** (`deputyaudit`) — see §2.1. A menu item with no route renders as a button that announces "<label> is still the prototype's screen"; home items such as `t/platform`, `t/setup`, `t/mgmt`, `r/registrar` resolve to `/` and are not placeholders.

### 1.8 The layers at a glance

```text
Browser
 → /login  (identifier shape picks the door)
 → cookie moaum_session (JWT, httpOnly)  +  cookie moaum_office (acting office)
 → every call: Authorization: Bearer <JWT>, X-Active-Office, X-Reason, X-Correlation-Id
API
 → SessionGuard: session exists, not ended, not past 12 h, not older than the API start
 → AuditContextFilter: X-Active-Office ∈ token offices, else 403
 → @PreAuthorize: acting person's OFFICE_<code> authorities ∈ the endpoint's list, else 403
 → OfficeScope (where called): parameter inside the office's bound, else 403 SCOPE_*
 → service rules: stage, ownership, segregation of duty, else 422 <CODE>
Database
 → SQL functions re-check acting office / actor where the rule lives there
 → audit.record: actor + acting office present, else the write is refused (403 NO_ACTING_OFFICE)
```

---

## 2 Role catalogue

### 2.1 The office register

All 34 offices exist in `ref.office` (**IMPLEMENTED**). "Home" is where the portal lands the office after sign-in (`menus.ts` `home` and `app/page.tsx`). Menu counts are taken from the menu trees (`menus.md`), including the home item. "Status" notes the offices whose menu or dashboard is generic or missing.

| Code | Title | Scope kind | Purpose · who holds it | Home | Menu | Status |
|---|---|---|---|---|---|---|
| `super` | Super Administrator | platform | The bootstrap and break-glass office; named on 33 of 44 modules as an actor. Held by the Directorate of ICT. | `/` Platform dashboard ("Setup Console") | 7 groups · 32 items | IMPLEMENTED |
| `admin` | System Administrator | platform | Day-to-day platform administration: users, gateways, mail/SMS, help desk, reconciliation reads. Directorate of ICT. | `/admin` Administrator Dashboard | 9 groups · 40 items | IMPLEMENTED |
| `ict` | Director of ICT | platform | Structure uploads (faculties, departments, programmes, courses), platform settings, accounts, integrations, audit trail. | `/` Platform dashboard ("Platform & Integrations") | 9 groups · 33 items | IMPLEMENTED |
| `ictagent` | ICT Support Agent | platform | Works the ICT help-desk queue (V251). Support staff of the Directorate. | `/helpdesk` | 2 groups · 4 items | IMPLEMENTED; Search item refused (§4) |
| `vc` | Vice-Chancellor | institution | Institutional overview, Senate business, revocation of documents, transfers at Senate, audit trail and security posture reads. | `/overview` Institutional Overview | 6 groups · 14 items | IMPLEMENTED |
| `dvc` | Deputy Vice-Chancellor (Academic) | institution | Academic oversight: pipeline, Senate schedule, graduation, transfers committee, movements, research grants. | `/` Academic dashboard | 5 groups · 13 items | IMPLEMENTED |
| `registrar` | Registrar | institution | Head of the Registry: accounts and grants, matriculation, clearance, documents (release, revoke), Senate minute, admissions, transfers, governance, staff movements. | `/` Registrar dashboard | 8 groups · 35 items | IMPLEMENTED; two menu items refused (§4) |
| `dregistrar` | Deputy Registrar (Academic Affairs) | institution | The Registrar's academic deputy: same academic authority as the Registrar except revocation and Senate transfers; Senate minute. | `/` Academic dashboard | 6 groups · 27 items | IMPLEMENTED |
| `academic` | Academic Officer (the Academic Office) | institution | Runs admissions, intake, matriculation runs, calendar, examination sessions, results to Senate, graduation, documents, LMS oversight. The busiest office (44 items). | `/` Academic dashboard | 6 groups · 44 items | IMPLEMENTED |
| `records` | Exams and Records | institution | Examination sessions, validation desk, broadsheets, Senate schedule, publication, graduation records, documents office, legacy migration. | `/` Academic dashboard | 5 groups · 23 items | IMPLEMENTED |
| `bursar` | Bursar | institution | Fees, confirmations, gateways, refunds, reconciliation, wallet/NELFUND, vouchers, budget, tenders, stores, payroll reads, financial clearance. | `/` Bursar dashboard | 5 groups · 32 items | IMPLEMENTED |
| `financecontroller` | Finance Controller, College of Health Sciences | college | Reads the College's payment report and statistics. **Acts in nothing.** | `/college/dashboard` (renders the Payment Report) | 5 groups · 12 items | IMPLEMENTED (read-only); Fee Setup and Search items refused (§4) |
| `audit` | Director of Internal Audit | institution | Payment vouchers (director's desk), reconciliation attestation, refunds/wallet/expenditure reads, audit trail, HR reads, revenue/assets/staff sub-desks. | `/vouchers` Payment Vouchers | 6 groups · 15 items | IMPLEMENTED |
| `deputyaudit` | Deputy Director of Audit | unit | Voucher checking at the deputy's desk, reconciliation, expenditure and finance reads, audit trail. | `/` Audit dashboard | **no menu of its own → FALLBACK** (Search, Dashboard, Leave & Payslip) | PARTIALLY IMPLEMENTED — acts through the API (vouchers, reconciliation, reports) but the sidebar offers no route to those screens; the FALLBACK Search is itself refused (§4) |
| `hrm` | Director of Human Resource Management | institution | Establishment, payroll runs, leave, movements, recruitment, appraisal; creates persons and loads non-academic staff. | `/` HR dashboard ("Movements") | 6 groups · 15 items | IMPLEMENTED |
| `provost` | Provost, College of Health Sciences | college | College desk: postings, professional examination decisions and confirmation, appeals, calendar, deferments of College students. | `/college/dashboard` | 4 groups · 12 items | IMPLEMENTED; Search refused (§4) |
| `collegesecretary` | College Secretary | college | Same College desk as the Provost. | `/college/dashboard` | 4 groups · 12 items | IMPLEMENTED; Search refused (§4) |
| `mbbscoordinator` | MBBS Coordinator | level | Score sheets, results, CA and enrolment for one MBBS level; must also hold `lecturer` in a College department. | `/college/coordinator` | 4 groups · 10 items | IMPLEMENTED; Search refused (§4) |
| `dean` | Dean | faculty | Faculty Board of results, faculty clearance, allocation, deferment recommendation, catalogue of the faculty, PG faculty decision, examiners, LMS, CBT bank, appraisal and leave of faculty staff. | `/` Dean dashboard | 7 groups · 34 items | IMPLEMENTED; Budget and Research items refused (§4) |
| `facultyofficer` | Faculty Officer | faculty | Faculty compilation stage of results, matriculation faculty lists (query/confirm), deferment recommendation, registers. | `/results/desk` | 5 groups · 15 items | IMPLEMENTED |
| `facultyexams` | Faculty Examinations Officer | faculty | Faculty scrutiny stage of results, examination slots, CBT bank reads. | `/results/desk` ("Scrutiny Desk") | 4 groups · 10 items | IMPLEMENTED |
| `hod` | Head of Department | department | Departmental board of results, registration approval, allocation, department catalogue, clearance, deferments, transfers, PG department decision, SIWES, examiners, leave/appraisal of department staff. | `/` HOD dashboard | 8 groups · 41 items | IMPLEMENTED; Requisitions refused (§4) |
| `exams` | Examinations Officer | programme | Verification stage of results, score entry, held scripts, result queries, exam slots, CBT bank, examiners, College results. | `/` Exams dashboard | 4 groups · 17 items | IMPLEMENTED |
| `lecturer` | Lecturer | course | Score entry on own sheets, class lists and attendance of own courses, course spaces, held scripts, CBT questions, College logbooks. | `/` Lecturer dashboard | 5 groups · 16 items | IMPLEMENTED; "My Projects" refused (§4) |
| `siwes` | SIWES Coordinator | department | Assigns industrial-training supervisors in the department; scores own students. | `/` SIWES dashboard | 3 groups · 5 items | IMPLEMENTED; Search refused (§4) |
| `pgschool` | Dean, School of Postgraduate Studies | institution | School decisions, admission, research pipeline, PG examiners, School Board, PG calendar, coursework desk. | `/` PG School dashboard | 6 groups · 26 items | IMPLEMENTED; Broadsheet, Graduation List and Search items refused (§4) |
| `pgsecretary` | Secretary, School of Postgraduate Studies | institution | Same School authority plus fee confirmation, registration desk, thesis clearance, results to Senate. | `/` PG Secretary dashboard | 7 groups · 29 items | IMPLEMENTED; Fees, Broadsheet, Graduation List and Search items refused (§4) |
| `extexaminer` | External Examiner | institution | An appointed outsider who assesses assigned projects through their own portal; account opened by invitation. | `/examiner` | 1 group · 5 items | IMPLEMENTED |
| `housing` | Deputy Registrar (Housing, Welfare, Passages) | institution | The hostel desk end to end; signs the HOSTEL clearance unit; answers student requests addressed to housing. | `/` Housing dashboard | 5 groups · 12 items | IMPLEMENTED; Staff Records refused (§4) |
| `services` | Support Services | unit | The clinic, hostel desk, library circulation, student clearance, help requests. | `/clinic` | 5 groups · 11 items | IMPLEMENTED; Requisitions, Tenders, Stores, Alumni and Search items refused (§4) |
| `security` | Chief Security Officer | unit | Identity card collection and lost-card handling. | "Verify a Card" — **no URL** (placeholder); `/` Security dashboard | 4 groups · 7 items | PARTIALLY IMPLEMENTED — the home item is a placeholder |
| `library` | Librarian | unit | Card printing, circulation, library clearance; fines waiver. | `/credentials/idcards` | 4 groups · 8 items | IMPLEMENTED; Stores item refused (§4) |
| `student` | Student | institution | The student's own portal. An undergraduate gets the `student` menu; a postgraduate (`entry_mode = POSTGRADUATE`) the `pgstudent` menu; a College student from 200 level lands on `/college/student`. | `/student` (`/college/student` for CHS) | 5 groups · 25 items (`pgstudent`: 8 groups · 17 items) | IMPLEMENTED |
| `applicant` | Applicant | institution | An undergraduate applicant's own application. The same authority is issued to postgraduate applicants (§2.2). | `/applicant` | 3 groups · 9 items | IMPLEMENTED |

> **Screenshot Required:** Users & roles — `/people` — the "Staff accounts and the offices they hold" panel showing Office, Bounded to, Granted by, From, To and the End action.

### 2.2 Sign-in identities that are not staff offices

| Identity | How it signs in | Authority in the token | Menu | Notes |
|---|---|---|---|---|
| Undergraduate applicant | JAMB registration number or `APP/YY/NNNNNN` or the account email at `/login` | `OFFICE_applicant` | `applicant` (9 items) | Registers at `/apply` with the JAMB number; the account later becomes the student account (§5.4) |
| Postgraduate applicant | Email or `PG/YY/NNNNNN` at `/login` | `OFFICE_applicant` — **there is no `OFFICE_pgapplicant` authority issued by the PG door** | `pgapplicant` (3 items; the frontend paints the shell as `pgapplicant`) | The help-desk guard excludes `pgapplicant` as well as `applicant`, which is harmless: the door never issues it |
| Undergraduate student | Matriculation number, admission number `MOAUM/ADM/YY/NNNNNN` or the legacy `BSU/…` shape | `OFFICE_student` | `student` | Account opened by carry-over from the applicant account, by the Registry, or by migration default (§5.4) |
| Postgraduate student | Same door | `OFFICE_student` | `pgstudent` | Chosen by `entry_mode`; the portal is the same office |
| External examiner | Email and password, after activation from an invitation link | `OFFICE_extexaminer` | `extexaminer` | Must also be `ACTIVE` in `extexam.examiner` or every `/me` call answers `EXAMINER_NOT_ACTIVE` |
| Development token | `PORTAL_API_TOKEN` (non-production only) | Whatever the token says | — | Accepted without a session check; ignored in production |

### 2.3 Authority, reports and settings by office

The table states what each office **approves or decides**, which **reports** it may take, and which **settings** it may change, as the guards and SQL rules stand. "Reports" refers to the returns desk (`/reports`), the registers, student statistics (`/stats`) and module exports; "money figures" means the amount columns of student statistics, shown only to the `MONEY` offices.

| Office | Approves / decides | Reports it may take | Settings it may change |
|---|---|---|---|
| Super Administrator | Every approval the guards allow (see §6 for the ones it is *not* named on); data reset and demo removal; DR drills | All returns, registers, statistics with money figures, audit trail | Calendar, mail/SMS, gateways and keys, API consumers, policies and templates, matric format, admission fees, helpdesk categories/SLA, hostel window and rules |
| System Administrator | Grants and credentials; allocation; hostel desk acts; library desk; help-desk director acts; payment sweep/PayDirect; SIWES assignment; external-examiner desk | All returns, registers, statistics with money figures, audit trail | Mail/SMS, gateway keys, API consumers, helpdesk settings; **not** the calendar, fee schedule (read only), documents policies |
| Director of ICT | Grants and credentials; structure creation/upload/archive (the only office); data reset; helpdesk director; PUTME check-in door; transfer "effect"; deferment tick | All returns, registers, statistics (no money figures), audit trail | Calendar, mail/SMS, gateway keys, API consumers, admission fees, helpdesk settings, migrations desk |
| ICT Support Agent | Take, assign, resolve, close tickets | Help-desk queue only | None |
| Vice-Chancellor | Revoke a document; approve staff movements; grant an office; transfers at Senate; research grants read | Institutional overview, all returns, registers, statistics with money figures, audit trail, security posture | None |
| DVC (Academic) | Staff movements; transfers committee (SAIC) and Senate; research grants (add, state) | Overview, returns, registers, statistics with money figures | None |
| Registrar | Grants, credentials, staff loads; matriculation runs and single issue; faculty-list confirm; clearance of any unit; document release, reissue, certificate issue, **revoke**; Senate minute; deferment approval and cancel; transfer at TO_OK and Senate; admissions decisions, CAPS load/commit, DE awards; PG admit; hostel acts; movements raise/approve; recruitment; DPIA/DSR; exam sessions; graduation approval and Senate list; results desk at SENATE | All returns (owner of admissions, enrolment, registration), registers, statistics with money figures, readiness | Calendar, matric format and series, admission policy and fees, documents policies and templates, allocation |
| Deputy Registrar (Academic Affairs) | As the Registrar for matriculation, clearance, documents (release/reissue/issue, not revoke), Senate minute, deferments, transfers (TO_OK), admissions decisions and settings, graduation, exam sessions, movements approval, DPIA/DSR; **not** CAPS load/commit, not PG admit, not hostel acts | All returns, registers, statistics with money figures | Calendar, matric format, admission policy and fees, documents policies |
| Academic Officer | CAPS load/commit and intake; admissions decisions, screening, scores, clearance items; matriculation runs; faculty-list query/confirm; deferment approval; transfer at REG_OK and paper cases; PG department *and* faculty decisions; PG coursework scoring; results entry (any sheet) and every desk stage; exam sessions; exam slots; graduation audit and approval; documents start/generate/QC/release/issue; clearance of any unit; catalogue ownership; LMS on any space; allocation; SIWES; PUTME setup and door; held scripts; result queries | All returns (owner of none), registers, statistics (no money figures) | Calendar and level limits, matric format, admission policy, O'Level grading, applicant fees, documents policies, transfer fee (read), CBT bank read |
| Exams and Records | Exam sessions create/edit/open; results validation stage; documents start/generate/QC (not release); graduation audit; admissions clearance items; deferments (read only); legacy migration; PUTME door; exam slots | Enrolment/registration/carryover returns (owner of carryovers), registers, statistics (no money figures) | None |
| Bursar | Fee schedule and structure upload; confirm references; clearance scheme; bank credits (maker–checker); refunds; reconciliation attestation; wallet loads, credits, reversals; NELFUND matching; payment sweep, PayDirect import, biller; vouchers raise/pay; budget, tenders, requisitions approval, stores, grants; applicant and PG fee confirmation; financial clearance unit; hostel damage charge reads | Revenue, funding, expenditure, income-expenditure (owner), registers, statistics with money figures | Fee schedule, applicant/PG/transfer fees, gateway configuration (not keys), funding sources, NELFUND sources |
| Finance Controller (CHS) | Nothing | College payment report, statistics with money figures (CHS bound) | None |
| Director of Internal Audit | Voucher director's desk (advance, query, reject); reconciliation check; asset verification; leave approval; refunds and wallet reads | Revenue, expenditure, income-expenditure, registers, audit trail, revenue/assets/staff sub-desks | None |
| Deputy Director of Audit | Voucher deputy's desk; reconciliation check; asset verification | Revenue and expenditure returns, kept copies, audit trail (via API) | None |
| Director of HRM | Create persons and load non-academic staff; pay runs build/approve/pay/cancel; movements raise/issue/approve; recruitment; appraisal; leave approval; requisitions raise | Staff-ratio return (owner), staff register, kept copies | None |
| Provost / College Secretary | College postings, professional-examination decisions, confirmation under a Board minute, appeals, enrolment; deferments of College students (as desk) | Statistics with money figures (CHS bound), College payment report | College calendar |
| MBBS Coordinator | Results, CA and enrolment at their level | Coordinator summary | None |
| Dean | Faculty Board stage; faculty clearance unit; allocation in the faculty; deferment recommendation at DEPT_RECOMMENDED; PG faculty decision; catalogue writes; examiner desk; appraisal and leave of faculty staff; requisitions raise; CBT authoring; LMS on any space | Enrolment/registration/carryover returns cut to the faculty (read; cannot keep a copy), registers cut to the faculty, statistics (faculty bound, no money) | None |
| Faculty Officer | Faculty compilation stage; matriculation faculty list query and confirm; deferment recommendation | Same returns and registers as the Dean (read) | None |
| Faculty Examinations Officer | Faculty scrutiny stage; exam slots | Results screens only | None |
| Head of Department | Department board stage; registration approve/return; allocation in the department; department catalogue; department clearance unit; deferment recommendation at SUBMITTED; transfer at APPLIED (from) and FROM_OK (to); PG department decision and coursework scoring; SIWES assignment; examiner desk; appraisal and leave of department staff; CBT authoring; LMS | Enrolment/registration/carryover returns cut to the department (read), registers, statistics (department bound) | None |
| Examinations Officer | Verification stage; score entry; held scripts; result queries; exam slots; CBT authoring; College results | Results screens, statistics (programme bound) | None |
| Lecturer | Score entry on own sheets; held scripts; attendance and slots of own courses; LMS on own spaces; CBT authoring; College logbooks as supervisor; SIWES scoring of own students | Class lists and sheets of own courses | None |
| SIWES Coordinator | Assign supervisors in the department; score own students | None | None |
| Dean, SPGS / Secretary, SPGS | School decision, accept, admit, student status; research pipeline and panel; PG examiner appointment; PG calendar; coursework endorse and score; deferments of PG students (as desk); examiner desk; Secretary also confirms PG fees, clears theses and sends results to Senate | Postgraduate return (owner), registers, statistics with money figures (PG bound) | PG calendar, PG fees (Secretary, through the PG module) |
| External Examiner | Submits assessments on assigned projects | Own assignments | Own profile |
| Housing | Every hostel act (window, inventory, review, allocation, check-in, transfers, inspection, clearance); HOSTEL clearance unit; answers housing requests | None | Hostel window and rules |
| Support Services | Clinic (triage, visits, fitness); hostel acts; library circulation; own clearance unit; answers services requests | None | None |
| Chief Security Officer | Issue/replace identity cards | None | None |
| Librarian | Circulation, fines waiver, card printing, library clearance unit; answers library requests | None | Library rule (waive and restate) |
| Student | Own registration, fee references and checkout, deferment and transfer requests, document requests, hostel application, tickets, queries, biodata change requests | Own results, statement, broadsheet, receipts | Own profile and password |
| Applicant | Own application, fee, acceptance, clearance documents | Own screening slip and score | Own password |

> **Note:** "Approves" above is the guard's view. Several approvals are additionally constrained by stage, by ownership or by a two-person rule in SQL; §3.3 gives those rules module by module.

---

## 3 Module × office permission matrix

### 3.1 How to read the matrix

The matrix in §3.2 was **generated from every `@PreAuthorize` guard in the API** (919 endpoints across 44 modules) and is reproduced without alteration apart from heading levels. For each module and office:

- **Act** — the office is named on at least one POST/PUT/DELETE endpoint of the module;
- **Read** — the office is named on GET endpoints only;
- **—** — the office is not named on any endpoint of the module;
- **Open** — the number of endpoints any signed-in person may call (typically the `/me` screens);
- **Public** — the number of endpoints that need no sign-in.

Two cautions. First, "Act" means the office can call *some* writing endpoint of the module, not every one: the finer lists (which office may release a document, which may confirm a reference, which stage of a chain an office may advance) are in §3.3. Second, the columns are office **codes**; the legend that follows the matrix maps each code to its title. The per-office summaries after the legend are also generated.

Two parser artefacts are known in the generated inventory and are corrected in §3.3: the help-desk requester guard (`isAuthenticated() and !hasAnyAuthority('OFFICE_applicant','OFFICE_pgapplicant')`) was read as "applicant, pgapplicant" although it means *everyone except* applicants, and `/api/v1/me/notices` (`isAuthenticated() and !hasAuthority('OFFICE_student')`) was read as "student" although it means every signed-in person except a student.

### 3.2 The generated matrix

#### Module × office matrix (derived from every `@PreAuthorize` guard in the API)

**Act** = the office is named on at least one POST/PUT/DELETE endpoint of the module; **Read** = named on GET endpoints only; **—** = not named. "Open" counts endpoints any signed-in user may call (typically `/me` screens); "Public" counts endpoints that need no sign-in.

| Module | super | admin | ict | ictagent | vc | dvc | registrar | dregistrar | academic | records | bursar | financecontroller | audit | deputyaudit | hrm | provost | collegesecretary | mbbscoordinator | dean | facultyofficer | facultyexams | hod | exams | lecturer | siwes | pgschool | pgsecretary | extexaminer | housing | services | security | library | student | applicant | Open | Public |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| API keys (`apimgmt`) | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Academic calendar (`calendar`) | Act | — | Act | — | — | — | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Academic structure & courses (`catalogue`) | Act | Act | Act | — | Read | Read | Act | Act | Act | Read | — | — | — | — | — | — | — | — | Act | Read | Read | Act | Read | Read | — | — | — | — | — | — | — | — | — | — |  |  |
| Alumni (`alumni`) | Read | Read | — | — | Read | Read | Read | Read | Read | Read | — | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Applicant portal (`applicant`) | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act |  | 5 |
| Audit log (`auditlog`) | Read | Read | Read | — | Read | — | — | — | — | — | — | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Authentication (`auth`) | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | 4 | 8 |
| CBT question bank (`cbt`) | Act | Read | — | — | — | — | Read | — | Read | — | — | — | — | — | — | — | — | — | Act | — | Read | Act | Act | Act | — | — | — | — | — | — | — | — | — | — |  |  |
| Clearance (`clearance`) | Read | Read | Read | — | Read | Read | Act | Act | Act | Read | Act | — | — | — | — | — | — | — | Act | Read | Read | Act | Read | — | — | — | — | — | Act | Act | — | Act | — | — |  |  |
| College of Health Sciences (`college`) | Act | Act | — | — | Read | Read | Act | Act | Act | Read | Read | Read | — | — | — | Act | Act | Act | Read | — | — | Act | Act | Act | — | — | — | — | — | — | — | — | Act | — |  |  |
| Course allocation (`allocation`) | Act | Act | — | — | — | — | Act | Act | Act | Read | — | — | — | — | — | — | — | — | Act | Read | Read | Act | Read | Read | — | — | — | — | — | — | — | — | — | — | 1 |  |
| Course registration (`registration`) | Act | Read | Read | — | Read | Read | Act | Act | Act | Read | — | — | — | — | — | — | — | — | Act | Read | Read | Act | Read | Act | — | — | — | — | — | — | — | — | — | — |  |  |
| Dean's desk (`dean`) | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Deferments (`deferments`) | Act | Act | Act | — | — | — | Act | Act | Act | Act | — | — | — | — | — | Act | Act | — | Act | Act | — | Act | — | — | — | Act | Act | — | — | — | — | — | Act | — |  |  |
| Documents, certificates & ID cards (`credentials`) | Act | Read | Read | — | Act | Read | Act | Act | Act | Act | Read | — | Read | — | — | — | — | — | Read | — | — | Read | — | — | — | — | — | — | — | — | Act | Act | Act | — |  | 3 |
| Expenditure & stores (`expenditure`) | Act | Read | Act | — | Read | Act | Act | — | — | — | Act | — | Act | Act | Act | — | — | — | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| External examiners (`examiners`) | Act | Act | — | — | — | — | Act | Act | Act | — | — | — | — | — | — | — | — | — | Act | — | — | Act | Act | — | — | Act | Act | Act | — | — | — | — | — | — |  | 2 |
| Finance & fees (`finance`) | Act | Act | Act | — | Read | Read | Read | Read | Read | — | Act | — | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Governance (`governance`) | Act | Read | Act | — | Read | Read | Act | Act | — | — | — | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Read | — | — | — |  |  |
| Graduation (`graduation`) | Read | Read | Read | — | Read | Read | Act | Act | Act | Act | — | — | — | — | — | — | — | — | Read | — | — | Read | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| HOD's desk (`hod`) | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Read | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Health centre (`health`) | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | — | — | Act | — |  |  |
| Hostel (`hostel`) | Act | Act | Read | — | Read | Read | Act | Read | Read | — | Read | — | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | Act | — | — | Act | — |  |  |
| Human resources (`hrm`) | Act | Act | Read | — | Act | Act | Act | Act | Read | Read | Read | — | Act | Read | Act | — | — | — | Act | Read | — | Act | — | — | — | Read | Read | — | — | — | — | — | — | — | 6 |  |
| ICT help desk (`helpdesk`) | Act | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | 11 | 1 |
| Identity & accounts (`iam`) | Act | Act | Act | — | Act | — | Act | Act | — | — | — | — | Read | — | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | 2 |  |
| Learning materials (LMS) (`lms`) | Act | — | — | — | — | — | — | — | Act | — | — | — | — | — | — | — | — | — | Act | — | — | Act | — | Act | — | — | — | — | — | — | — | — | Act | — | 1 |  |
| Library (`library`) | Act | Act | Read | — | — | — | Read | Read | Read | — | Read | — | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | — | Act | Act | — |  |  |
| Matriculation (`matriculation`) | Act | Read | Read | — | Read | Read | Act | Act | Act | Read | — | — | — | — | — | — | — | — | Read | Act | — | Read | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Payment gateways (`payments`) | Act | Act | Act | — | Read | Read | Read | — | — | — | Act | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | Act | 2 | 4 |
| Platform, notices & mail (`platform`) | Act | Act | Act | — | — | — | Read | Read | Read | — | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | 1 | 1 |
| Postgraduate school (`pgadmissions`) | Act | — | — | — | Read | Read | Act | Read | Act | — | Act | — | — | — | — | — | — | — | Act | — | — | Act | — | — | — | Act | Act | — | — | — | — | — | Act | Act |  | 6 |
| Provost's desk (`provost`) | Read | — | — | — | — | — | — | — | — | — | — | Read | — | — | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Public verification (`verify`) | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  | 7 |
| Reference data (`ref`) | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | 3 |  |
| Reporting (`reporting`) | Read | Read | Read | — | Read | Read | Read | Read | Read | — | Read | — | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Reports (`reports`) | Act | Act | Act | — | Act | Act | Act | Act | Act | Act | Act | — | Act | Act | Act | — | — | — | Read | Read | — | Read | — | — | — | Act | Act | — | — | — | — | — | — | — |  |  |
| Results & assessment (`results`) | Act | Read | Act | — | Read | Read | Act | Act | Act | Act | Read | — | — | — | — | — | — | — | Act | Act | Act | Act | Act | Act | — | — | — | — | — | — | — | — | — | — |  |  |
| SIWES (`siwes`) | Act | Act | — | — | — | — | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | Act | — | — | Act | — | — | — | — | — | — | — | — | — | 2 |  |
| Staff (`staff`) | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | 6 |  |
| Statistics (`stats`) | Read | Read | Read | — | Read | Read | Read | Read | Read | Read | Read | Read | — | — | — | Read | Read | — | Read | Read | — | Read | Read | — | — | Read | Read | — | — | — | — | — | — | — |  |  |
| Student portal (`studentportal`) | Act | — | Act | — | — | — | Act | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | — |  | 1 |
| Student records (`student`) | Act | — | Act | — | — | — | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | — |  |  |
| Support services (`support`) | Act | Act | Act | — | — | — | Act | Act | Act | — | Act | — | — | — | — | — | — | — | — | — | — | Act | — | — | — | — | — | — | Act | Act | — | Act | Act | — |  |  |
| Transfers (`transfers`) | Act | Read | Act | — | Act | Act | Act | Act | Act | — | — | — | — | — | — | — | — | — | — | — | — | Act | — | — | — | — | — | — | — | — | — | — | Act | — |  |  |
| Undergraduate admissions (`admissions`) | Act | Act | Act | — | Read | Read | Act | Act | Act | Act | Act | — | — | — | — | — | — | — | Read | — | — | Read | — | — | — | — | — | — | — | — | — | — | — | — |  |  |
| Wallet (`wallet`) | Act | Act | Read | — | Read | Read | Act | Act | Act | — | Act | — | Read | Read | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | — | Act | — |  |  |

#### Office legend

| Code | Title | Scope kind |
|---|---|---|
| `super` | Super Administrator | platform |
| `admin` | System Administrator | platform |
| `ict` | Director of ICT | platform |
| `ictagent` | ICT Support Agent | platform |
| `vc` | Vice-Chancellor | institution |
| `dvc` | Deputy Vice-Chancellor (Academic) | institution |
| `registrar` | Registrar | institution |
| `dregistrar` | Deputy Registrar (Academic Affairs) | institution |
| `academic` | Academic Officer | institution |
| `records` | Exams and Records | institution |
| `bursar` | Bursar | institution |
| `financecontroller` | Finance Controller, College of Health Sciences | college |
| `audit` | Director of Internal Audit | institution |
| `deputyaudit` | Deputy Director of Audit | unit |
| `hrm` | Director of Human Resource Management | institution |
| `provost` | Provost, College of Health Sciences | college |
| `collegesecretary` | College Secretary | college |
| `mbbscoordinator` | MBBS Coordinator | level |
| `dean` | Dean | faculty |
| `facultyofficer` | Faculty Officer | faculty |
| `facultyexams` | Faculty Examinations Officer | faculty |
| `hod` | Head of Department | department |
| `exams` | Examinations Officer | programme |
| `lecturer` | Lecturer | course |
| `siwes` | SIWES Coordinator | department |
| `pgschool` | Dean, School of Postgraduate Studies | institution |
| `pgsecretary` | Secretary, School of Postgraduate Studies | institution |
| `extexaminer` | External Examiner | institution |
| `housing` | Deputy Registrar (Housing, Welfare, Passages) | institution |
| `services` | Support Services | unit |
| `security` | Chief Security Officer | unit |
| `library` | Librarian | unit |
| `student` | Student | institution |
| `applicant` | Applicant | institution |

#### What each office may do, module by module

##### Super Administrator (`super`)
- **Acts in:** API keys, Academic calendar, Academic structure & courses, CBT question bank, College of Health Sciences, Course allocation, Course registration, Deferments, Documents, certificates & ID cards, Expenditure & stores, External examiners, Finance & fees, Governance, Health centre, Hostel, Human resources, ICT help desk, Identity & accounts, Learning materials (LMS), Library, Matriculation, Payment gateways, Platform, notices & mail, Postgraduate school, Reports, Results & assessment, SIWES, Student portal, Student records, Support services, Transfers, Undergraduate admissions, Wallet
- **Reads only:** Alumni, Audit log, Clearance, Dean's desk, Graduation, Provost's desk, Reporting, Statistics
- **Menu items:** 30

##### System Administrator (`admin`)
- **Acts in:** API keys, Academic structure & courses, College of Health Sciences, Course allocation, Deferments, External examiners, Finance & fees, Hostel, Human resources, ICT help desk, Identity & accounts, Library, Payment gateways, Platform, notices & mail, Reports, SIWES, Support services, Undergraduate admissions, Wallet
- **Reads only:** Alumni, Audit log, CBT question bank, Clearance, Course registration, Documents, certificates & ID cards, Expenditure & stores, Governance, Graduation, Matriculation, Reporting, Results & assessment, Statistics, Transfers
- **Menu items:** 39

##### Director of ICT (`ict`)
- **Acts in:** API keys, Academic calendar, Academic structure & courses, Deferments, Expenditure & stores, Finance & fees, Governance, ICT help desk, Identity & accounts, Payment gateways, Platform, notices & mail, Reports, Results & assessment, Student portal, Student records, Support services, Transfers, Undergraduate admissions
- **Reads only:** Audit log, Clearance, Course registration, Documents, certificates & ID cards, Graduation, Hostel, Human resources, Library, Matriculation, Reporting, Statistics, Wallet
- **Menu items:** 32

##### ICT Support Agent (`ictagent`)
- **Acts in:** ICT help desk
- **Reads only:** none
- **Menu items:** 4

##### Vice-Chancellor (`vc`)
- **Acts in:** Documents, certificates & ID cards, Human resources, Identity & accounts, Reports, Transfers
- **Reads only:** Academic structure & courses, Alumni, Audit log, Clearance, College of Health Sciences, Course registration, Expenditure & stores, Finance & fees, Governance, Graduation, Hostel, Matriculation, Payment gateways, Postgraduate school, Reporting, Results & assessment, Statistics, Undergraduate admissions, Wallet
- **Menu items:** 14

##### Deputy Vice-Chancellor (Academic) (`dvc`)
- **Acts in:** Expenditure & stores, Human resources, Reports, Transfers
- **Reads only:** Academic structure & courses, Alumni, Clearance, College of Health Sciences, Course registration, Documents, certificates & ID cards, Finance & fees, Governance, Graduation, Hostel, Matriculation, Payment gateways, Postgraduate school, Reporting, Results & assessment, Statistics, Undergraduate admissions, Wallet
- **Menu items:** 12

##### Registrar (`registrar`)
- **Acts in:** Academic calendar, Academic structure & courses, Clearance, College of Health Sciences, Course allocation, Course registration, Deferments, Documents, certificates & ID cards, Expenditure & stores, External examiners, Governance, Graduation, Hostel, Human resources, Identity & accounts, Matriculation, Postgraduate school, Reports, Results & assessment, SIWES, Student portal, Student records, Support services, Transfers, Undergraduate admissions, Wallet
- **Reads only:** Alumni, CBT question bank, Finance & fees, Library, Payment gateways, Platform, notices & mail, Reporting, Statistics
- **Menu items:** 34

##### Deputy Registrar (Academic Affairs) (`dregistrar`)
- **Acts in:** Academic calendar, Academic structure & courses, Clearance, College of Health Sciences, Course allocation, Course registration, Deferments, Documents, certificates & ID cards, External examiners, Governance, Graduation, Human resources, Identity & accounts, Matriculation, Reports, Results & assessment, SIWES, Student portal, Student records, Support services, Transfers, Undergraduate admissions, Wallet
- **Reads only:** Alumni, Finance & fees, Hostel, Library, Platform, notices & mail, Postgraduate school, Reporting, Statistics
- **Menu items:** 26

##### Academic Officer (`academic`)
- **Acts in:** Academic calendar, Academic structure & courses, Clearance, College of Health Sciences, Course allocation, Course registration, Deferments, Documents, certificates & ID cards, External examiners, Graduation, Learning materials (LMS), Matriculation, Postgraduate school, Reports, Results & assessment, SIWES, Student portal, Student records, Support services, Transfers, Undergraduate admissions, Wallet
- **Reads only:** Alumni, CBT question bank, Finance & fees, Hostel, Human resources, Library, Platform, notices & mail, Reporting, Statistics
- **Menu items:** 44

##### Exams and Records (`records`)
- **Acts in:** Deferments, Documents, certificates & ID cards, Graduation, Reports, Results & assessment, Student portal, Undergraduate admissions
- **Reads only:** Academic structure & courses, Alumni, Clearance, College of Health Sciences, Course allocation, Course registration, Human resources, Matriculation, Statistics
- **Menu items:** 22

##### Bursar (`bursar`)
- **Acts in:** Clearance, Expenditure & stores, Finance & fees, Payment gateways, Postgraduate school, Reports, Support services, Undergraduate admissions, Wallet
- **Reads only:** College of Health Sciences, Documents, certificates & ID cards, Hostel, Human resources, Library, Platform, notices & mail, Reporting, Results & assessment, Statistics
- **Menu items:** 31

##### Finance Controller, College of Health Sciences (`financecontroller`)
- **Acts in:** none
- **Reads only:** College of Health Sciences, Provost's desk, Statistics
- **Menu items:** 12

##### Director of Internal Audit (`audit`)
- **Acts in:** Expenditure & stores, Finance & fees, Human resources, Reports
- **Reads only:** Alumni, Audit log, Documents, certificates & ID cards, Governance, Hostel, Identity & accounts, Library, Payment gateways, Reporting, Wallet
- **Menu items:** 15

##### Deputy Director of Audit (`deputyaudit`)
- **Acts in:** Expenditure & stores, Finance & fees, Reports
- **Reads only:** Alumni, Audit log, Governance, Human resources, Payment gateways, Wallet
- **Menu items:** 0

##### Director of Human Resource Management (`hrm`)
- **Acts in:** Expenditure & stores, Human resources, Identity & accounts, Reports
- **Reads only:** none
- **Menu items:** 14

##### Provost, College of Health Sciences (`provost`)
- **Acts in:** College of Health Sciences, Deferments
- **Reads only:** Provost's desk, Statistics
- **Menu items:** 12

##### College Secretary (`collegesecretary`)
- **Acts in:** College of Health Sciences, Deferments
- **Reads only:** Provost's desk, Statistics
- **Menu items:** 12

##### MBBS Coordinator (`mbbscoordinator`)
- **Acts in:** College of Health Sciences
- **Reads only:** none
- **Menu items:** 10

##### Dean (`dean`)
- **Acts in:** Academic structure & courses, CBT question bank, Clearance, Course allocation, Course registration, Deferments, Expenditure & stores, External examiners, Human resources, Learning materials (LMS), Postgraduate school, Results & assessment
- **Reads only:** College of Health Sciences, Dean's desk, Documents, certificates & ID cards, Graduation, Matriculation, Reports, Statistics, Undergraduate admissions
- **Menu items:** 33

##### Faculty Officer (`facultyofficer`)
- **Acts in:** Deferments, Matriculation, Results & assessment
- **Reads only:** Academic structure & courses, Clearance, Course allocation, Course registration, Dean's desk, Human resources, Reports, Statistics
- **Menu items:** 15

##### Faculty Examinations Officer (`facultyexams`)
- **Acts in:** Results & assessment
- **Reads only:** Academic structure & courses, CBT question bank, Clearance, Course allocation, Course registration
- **Menu items:** 10

##### Head of Department (`hod`)
- **Acts in:** Academic structure & courses, CBT question bank, Clearance, College of Health Sciences, Course allocation, Course registration, Deferments, External examiners, Human resources, Learning materials (LMS), Postgraduate school, Results & assessment, SIWES, Support services, Transfers
- **Reads only:** Documents, certificates & ID cards, Graduation, HOD's desk, Matriculation, Reports, Statistics, Undergraduate admissions
- **Menu items:** 40

##### Examinations Officer (`exams`)
- **Acts in:** CBT question bank, College of Health Sciences, External examiners, Results & assessment
- **Reads only:** Academic structure & courses, Clearance, Course allocation, Course registration, Statistics
- **Menu items:** 16

##### Lecturer (`lecturer`)
- **Acts in:** CBT question bank, College of Health Sciences, Course registration, Learning materials (LMS), Results & assessment
- **Reads only:** Academic structure & courses, Course allocation
- **Menu items:** 15

##### SIWES Coordinator (`siwes`)
- **Acts in:** SIWES
- **Reads only:** none
- **Menu items:** 5

##### Dean, School of Postgraduate Studies (`pgschool`)
- **Acts in:** Deferments, External examiners, Postgraduate school, Reports
- **Reads only:** Human resources, Statistics
- **Menu items:** 25

##### Secretary, School of Postgraduate Studies (`pgsecretary`)
- **Acts in:** Deferments, External examiners, Postgraduate school, Reports
- **Reads only:** Human resources, Statistics
- **Menu items:** 28

##### External Examiner (`extexaminer`)
- **Acts in:** External examiners
- **Reads only:** none
- **Menu items:** 5

##### Deputy Registrar (Housing, Welfare, Passages) (`housing`)
- **Acts in:** Clearance, Hostel, Support services
- **Reads only:** none
- **Menu items:** 11

##### Support Services (`services`)
- **Acts in:** Clearance, Health centre, Hostel, Library, Support services
- **Reads only:** none
- **Menu items:** 11

##### Chief Security Officer (`security`)
- **Acts in:** Documents, certificates & ID cards
- **Reads only:** Governance
- **Menu items:** 6

##### Librarian (`library`)
- **Acts in:** Clearance, Documents, certificates & ID cards, Library, Support services
- **Reads only:** none
- **Menu items:** 8

##### Student (`student`)
- **Acts in:** College of Health Sciences, Deferments, Documents, certificates & ID cards, Health centre, Hostel, Learning materials (LMS), Library, Payment gateways, Postgraduate school, Student portal, Student records, Support services, Transfers, Wallet
- **Reads only:** none
- **Menu items:** 25

##### Applicant (`applicant`)
- **Acts in:** Applicant portal, Payment gateways, Postgraduate school
- **Reads only:** none
- **Menu items:** 9


### 3.3 Finer rules by module

The matrix says which offices touch a module. The rules below say **which office does what inside it**, and where scope, stage, ownership or a two-person rule narrows the guard further. Office lists are the guard constants as written in the controllers (names in `CAPITALS`); module keys are those of the matrix.

#### 3.3.1 Identity & accounts (`iam`)

| Act | Offices | Rule beyond the guard |
|---|---|---|
| Read persons, grants, lecturers (`READERS`) | registrar, dregistrar, hrm, ict, admin, super, audit | Exposes username, lock state and last sign-in |
| Create person, set contact | registrar, dregistrar, hrm, ict, admin, super | Staff number UNIQUE (409 `ALREADY_EXISTS`) |
| Create or reset a credential (`CREDENTIALS`) | registrar, dregistrar, ict, admin, super | Username ≥ 3 chars, unique; first password ≥ 10; `must_change` set |
| Grant an office, end a grant (`GRANTORS`) | registrar, dregistrar, vc, super, ict, admin | Any of the six may grant **any** office, including `super`; instrument required; grantor = acting person; `mbbscoordinator` needs a level 200–600 and an existing `lecturer` grant in a College department (trigger) |
| Bulk lecturer / non-academic loads (`STAFF_LOADERS`) | registrar, dregistrar, hrm, ict, admin, super | Lecturer load issues sign-in `P<PNO>` + lecturer office; staff load issues neither |
| `/iam/me`, `/iam/offices` | any token | |

#### 3.3.2 Academic calendar (`calendar`) and reference data (`ref`)

Read: any signed-in person (students included). Write (`WRITERS`): academic, registrar, dregistrar, super, ict — sessions, semesters, level limits, make-current (needs a Senate minute), roll-over (`ROLLOVER` + reason), enrol-all. `/ref/structure` and `/ref/courses` are pruned to the acting office's bound (a department office sees its department, a lecturer only the programmes its courses are offered to).

#### 3.3.3 Academic structure & courses (`catalogue`)

| Act | Offices | Rule |
|---|---|---|
| Create, upload, archive, delete faculties, departments, programmes; course-structure import (`UPLOADERS`) | **ict only** | The screens enforce `MAY = ["ict"]`; the course-upload note still says "and HODs" (stale) |
| Course, offer and structure writes (`OWNERS`) | hod, dean, academic, dregistrar, registrar, admin, super | A HOD is confined to their own department (`CAT_DEPT`) |
| Open registration for a session (`OPENERS`) | ict, super, admin, hod, dean, academic, registrar, dregistrar | Not a structure upload, so the earlier offices were kept |
| Read (`READERS`) | the above + lecturer, exams, facultyexams, facultyofficer, records, dvc, vc | HOD reads only their faculty/department/programmes |
| Upload coverage | ict, admin, super, academic, registrar, dregistrar, dvc, vc, hod, dean | |

#### 3.3.4 Undergraduate admissions (`admissions`) and Post-UTME (`admissions.Putme*`)

| Act | Offices | Rule |
|---|---|---|
| CAPS load/append/commit/withdraw, merit record, DE awards, JAMB list, programme names (`LOADERS`) | academic, registrar | The service also requires the **acting** office to be academic or registrar (`requireUploadingOffice`, CHECK `ck_batch_office`) |
| Readers | academic, registrar, dregistrar, dvc, vc, records, ict, admin, super | |
| Decisions, releases, screening batches, scores, reconsiderations (`OFFICE`) | academic, registrar, dregistrar | |
| Confirm an applicant fee reference (`CONFIRMERS`) | academic, registrar, dregistrar, bursar | |
| Record clearance items (`REGISTRY`) | academic, registrar, dregistrar, records | |
| Old-portal import (`IMPORTERS`) | academic, registrar, dregistrar, ict, super | |
| Applicant fees (`FEESETTERS`) | academic, registrar, dregistrar, bursar, ict, admin, super | |
| Upload / zero / derive PUTME scores (`SCORE_UPLOADERS`) | academic, registrar, dregistrar, ict, admin, super | |
| Compute PUTME score (`/post-utme-computed`) | academic, super | |
| Candidate data and O'Level writers | academic, registrar, dregistrar | The O'Level **score** is returned only when the acting office is `academic` |
| Admission settings (`SECRETARIAT`) | academic, registrar, dregistrar | Readers add dean, hod, dvc, vc, records, ict, admin, super |
| Intake to the register (`POST /student/intake/{session}`) | academic, registrar, dregistrar | Called from the Admissions screen; runs on ADMITTED and ACCEPTED candidates |
| Post-UTME CBT setup, generate, publish, move, unschedule, batch state (`OFFICE`) | academic, registrar, dregistrar, super | |
| Post-UTME door: lookup, check-in, attendance (`DOOR`) | academic, registrar, dregistrar, records, ict, super | |
| Post-UTME readers | academic, registrar, dregistrar, records, bursar, ict, admin, super | |

Scope: none by faculty or department; everything is by session.

#### 3.3.5 Applicant portal (`applicant`)

`OFFICE_applicant` only; every read is the caller's own application. `lookup`, `register`, `sign-in`, `forgot`, `reset` are public.

#### 3.3.6 Postgraduate school (`pgadmissions`)

| Act | Offices | Rule |
|---|---|---|
| Read the desks (`READERS`) | pgschool, pgsecretary, academic, registrar, dregistrar, dean, hod, dvc, vc, super | HOD bound to their department's programmes, Dean to their faculty (`inBound` refuses another department's application) |
| Department decision (`DEPT`) | hod, academic, super | |
| Faculty decision (`FACULTY`) | dean, academic, super | |
| School decision, accept, PG examiner appointment, student status (`SPGS`) | pgschool, pgsecretary, super | `spgsDecision` does not call `inBound` |
| Admit → student record and account (`ADMIT`) | pgschool, pgsecretary, registrar, super | |
| Confirm a fee (`CONFIRMERS`) | pgsecretary, bursar, super | |
| State PG fees (`FEES`) | bursar, pgsecretary, pgschool, super | |
| PG calendar | read: READERS + bursar; write: pgschool, pgsecretary, super | |
| Coursework desk — catalogue, import, registrations, endorse, score (`DESK`) | hod, academic, pgschool, pgsecretary, super | **No department scope**: a HOD can read and score any programme |
| Research desk — pipeline, supervisors, panel, actions, document review (`SCHOOL`) | pgschool, pgsecretary, super | |
| Secretary desks | pgsecretary, pgschool, academic, registrar, dregistrar, super | |
| Student | `OFFICE_student` with `entry_mode = POSTGRADUATE` | |

#### 3.3.7 External examiners (`examiners`)

`DESK` = academic, dregistrar, registrar, exams, hod, dean, pgschool, pgsecretary, admin, super (projects, appointments, assignments, reports). `FORM` = academic, dregistrar, pgschool, admin, super (rubrics and criteria). `EXAMINER` = extexaminer for `/me/**`, and the examiner must be `ACTIVE`. **Reach:** a department office sees its department's projects, a faculty office its faculty's, everyone else the University; `appoint` refuses another department (`EXAMINER_REACH`). The examiner register itself is not reach-filtered. Invitation and activation are public.

#### 3.3.8 Student records (`student`) and the student portal (`studentportal`)

Readers (21 offices): academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, ict, admin, super, bursar, library, security, housing, hrm, audit, lecturer — the register, a student's record and portal view, passport, biodata changes, `/search`, `/records/{view}`. Writers: academic, registrar, dregistrar (biodata, status change, level correction, biodata-change decisions, intake). Migrated clearance and voluntary withdrawal: academic, registrar, dregistrar, ict, super. Open or reset a student's portal account: registrar, dregistrar, academic, records, ict, super. The register list is bound by `OfficeScope.bound`; `/records/{view}` takes the scope from the request as given. The portal (`/student/**`) is `OFFICE_student` only.

#### 3.3.9 Matriculation (`matriculation`)

| Tier | Offices | May |
|---|---|---|
| `READERS` | academic, registrar, dregistrar, dvc, vc, records, dean, hod (run screens only), facultyofficer, ict, admin, super | Open the desk, the runs, the history, the format screen |
| `OFFICERS` | academic, registrar, dregistrar, facultyofficer | Query a faculty list, withdraw a query, confirm the list |
| `RUNNERS` | academic, registrar, dregistrar | Run a matriculation; matriculate one student |
| `CONFIG` | academic, registrar, dregistrar, super | Edit the number format, the series, the faculty segments and programme codes (V263) |

No scope in code: a Faculty Officer can open and confirm any faculty's list by URL; the database records `confirmed_by`.

#### 3.3.10 Course registration (`registration`)

| Act | Offices | Rule |
|---|---|---|
| Class list (`READERS`) | academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, lecturer, ict, admin, super | Department offices held to their own courses; a lecturer only to offerings they carry (lead, second examiner or co-lecturer) |
| Registration desk list (`DEPARTMENT`) | hod, lecturer, dean, facultyofficer, academic, registrar, dregistrar, super | HOD and lecturer confined server-side |
| Approve / return a registration (`HOD_APPROVES`) | hod, super | Only the HOD of the student's department (`REG_OTHER_DEPT`) |
| Create/submit a registration for a student (`APPROVERS`) | academic, dregistrar, hod, lecturer, registrar, super | Backend only — no screen |
| Course / offer / offering upserts (`CATALOGUE`) | hod, academic, registrar, dregistrar, super | Making a course LIVE here: academic, registrar, dregistrar, super only |
| Attendance and class slots | lecturer, hod, dean, super | |
| Examination slot (`PUT /results/offerings/{id}/exam-slot`) | exams, facultyexams, records, academic, registrar, super | |

#### 3.3.11 Deferments (`deferments`)

`DESK` = hod, dean, facultyofficer, academic, registrar, dregistrar, records, pgschool, pgsecretary, provost, collegesecretary, super, admin. **Bound:** academic, registrar, dregistrar, records, super, admin see all; pgschool/pgsecretary postgraduate students only; provost/collegesecretary faculties of the College; a faculty office its faculty; a department office its department. **Stage:** HOD recommends at SUBMITTED; Dean or Faculty Officer at DEPT_RECOMMENDED; the Registry (academic, registrar, dregistrar, super) approves at DEPT_ or FAC_RECOMMENDED and may act at any stage; reject/correction only at the desk's own stage; cancel Registry only; confirm return HOD/Dean/Faculty Officer/Registry. `records` and `admin` read only. Tick (the clock): registrar, dregistrar, academic, ict, super. A student acts on own requests only (`owned()`).

#### 3.3.12 Transfers (`transfers`)

Readers: hod, academic, registrar, dregistrar, dvc, vc, ict, admin, super. Approve/decline (`APPROVERS` = hod, registrar, dregistrar, academic, super) is stage-checked: APPLIED → paid **and** the HOD of the *from* department (or super); FROM_OK → the HOD of the *to* department; TO_OK → registrar or dregistrar; REG_OK → academic. Paper cases (`OFFICERS`): academic, registrar, dregistrar, super. Committee review (`SAIC`: academic, registrar, dregistrar, dvc, super), Senate (registrar, dregistrar, vc, dvc, super), withdraw and effect (academic, registrar, dregistrar, ict, super) exist in the API **without a screen**.

#### 3.3.13 Learning materials (`lms`), library (`library`), SIWES (`siwes`)

- **LMS** `TEACHERS` = lecturer, hod, dean, academic, super; the allocated lecturer/second examiner/co-lecturer acts on their space, hod/dean/academic/super on any (`LMS_NOT_YOURS` otherwise). Students on the roll read `/me/courses/**`. `GET /me/teaching` is any signed-in person.
- **Library** `DESK` (issue, return, renew, catalogue) = library, services, admin, super; waive a fine and restate the rule = library, super; desk readers add registrar, dregistrar, academic, bursar, ict, audit; a student sees own loans, reservations and fine references.
- **SIWES** `ASSIGNERS` = hod, siwes, academic, registrar, dregistrar, admin, super, department offices confined by `deptWithin`; supervisor endpoints are any signed-in person with an ownership check (`SIWES_NOT_YOUR_STUDENT`).

#### 3.3.14 Graduation (`graduation`), alumni (`alumni`), clearance (`clearance`)

- **Graduation** view: academic, registrar, dregistrar, dvc, vc, records, dean, hod, ict, admin, super (bound by `OfficeScope.bound`); degree audit: academic, registrar, dregistrar, records; approve under a Senate minute: registrar, dregistrar, academic.
- **Alumni** readers: registrar, dregistrar, academic, records, vc, dvc, audit, deputyaudit, admin, super.
- **Clearance** readers: academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, bursar, library, services, ict, admin, super (listing bound by scope). `SIGNERS` = academic, registrar, dregistrar, dean, hod, bursar, library, services, housing — registrar, dregistrar and academic sign **any** unit; every other signer only the unit whose `office_code` equals the acting office, plus `housing` for the HOSTEL unit ("the X clears against its own record; Y does not sign for it").

#### 3.3.15 Course allocation (`allocation`)

`ALLOCATORS` = hod, dean, academic, dregistrar, registrar, admin, super. History readers add lecturer, exams, facultyexams, facultyofficer, records. A HOD's offerings and lecturer lists are limited to their department; an offering of another department is refused (`ALLOC_DEPT`). `/allocation/departments` is any signed-in person, pruned for a HOD.

#### 3.3.16 Results & assessment (`results`), held scripts, result queries

| Tier | Offices | May |
|---|---|---|
| `READERS` | academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, lecturer, ict, admin, super | List and read sheets, rolls, exam sessions, monitor, broadsheet, Senate schedule |
| `DESKS` | lecturer, exams, hod, facultyexams, facultyofficer, dean, records, registrar, dregistrar, academic | Advance, return, remind |
| `ENTRY` | lecturer, exams, academic | Write scores; hold / withdraw held scripts |
| `EXAMS` | records, academic, registrar, dregistrar | Create, edit, open examination sessions |
| Senate minute | registrar, dregistrar | Record the minute that publishes a schedule |
| Legacy migration (`MIGRATE`) | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `/results/legacy/*` imports and reconciliations |

**Desks by stage** (`Sheets.DESK`): ENTRY → lecturer; VERIFICATION → exams; DEPT_BOARD → hod; FACULTY_SCRUTINY → facultyexams; FACULTY_COMPILATION → facultyofficer; FACULTY_BOARD → dean; RECORDS → records; SENATE → registrar/dregistrar.

> **Warning:** The stage→office map drives only the `mayAct` flag that shows or hides the buttons. The database function `assessment.advance` enforces "not the same person twice in a row" and completeness, **not the office**: any `DESKS` office can call `/sheets/{id}/advance` at any stage through the API, and a `DESKS` office can publish a single sheet by passing a minute at SENATE. The UI hides; the API does not refuse.

Scope: listing is bound by `OfficeScope.bound` (department offices to their department, faculty offices to their faculty); a lecturer's list is only their own sheets and `own(id)` refuses any sheet they do not carry ("… a lecturer reaches only the score sheets of their own courses."). The broadsheet refuses a programme outside a department/faculty office's bound.

**Held scripts:** hold, bulk hold and withdraw = `ENTRY` (lecturer, exams, academic) **without** an ownership check — any lecturer may hold on any sheet id (dossier E, NOT IMPLEMENTED ownership); read a sheet's held scripts = readers + bursar; the owing list = bursar, academic, registrar, dregistrar, exams, hod, dean, records, vc, dvc, admin, super.

**Result queries:** read and answer (`DEPARTMENT`) = hod, lecturer, exams, dean, records, academic, registrar, super, department offices bound by `deptWithin`; a student raises a query only on a sheet carrying a score of theirs.

#### 3.3.17 CBT question bank (`cbt`)

`READERS` = lecturer, hod, exams, facultyexams, dean, academic, registrar, admin, super; `AUTHORS` (author, retire, restore) = lecturer, hod, exams, dean, super. No department or course scope. There is no CBT test delivery on the portal (NOT IMPLEMENTED); the Examinations Officer's "CBT Sessions" item opens the results examination sessions.

#### 3.3.18 College of Health Sciences (`college`, `provost`)

| Tier | Offices | May |
|---|---|---|
| `DESK` | provost, collegesecretary, academic, registrar, dregistrar, admin, super | Postings/allocations, decisions, confirmation under a Board minute, appeals, calendar, supervisors |
| `DESK_OR_COORDINATOR` | DESK + mbbscoordinator | Students list, enrol |
| `EXAMINERS` | DESK + lecturer, hod, exams, mbbscoordinator | Candidates, results (single and bulk), CA assessments, uploads, coordinator summary — a department office outside the College is refused (`COLLEGE_NOT_EXAMINER`) |
| `READERS` | DESK + financecontroller, records, dean, hod, lecturer, exams, vc, dvc, mbbscoordinator | Structure, examinations, summary, reconciliation, calendar, overview, dashboard, requirements |
| `SUPERVISORS` | lecturer, hod, exams + DESK | Logbook writes, limited to the allocation's supervisor or a desk office (`COLLEGE_NOT_SUPERVISOR`) |
| `PAYMENT_READERS` | financecontroller, provost, collegesecretary, bursar, registrar, dregistrar, academic, dvc, vc, super | The payment report |
| Provost dashboard API | provost, collegesecretary, financecontroller, super | No screen calls it (backend only) |
| Student | `OFFICE_student` | Own record, postings, logbooks, assessments, register |

The MBBS Coordinator acts only at the level of their grant (`COLLEGE_NOT_YOUR_LEVEL`).

#### 3.3.19 Finance & fees (`finance`)

| Act | Offices | Rule |
|---|---|---|
| Read schedule, references, day book, payments query, reconciliation, bank credits, Bursary tiles (`READERS`) | bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc | `financecontroller` and `pgsecretary` are **not** readers (§4) |
| Fee schedule, structure upload, confirm references, clearance scheme, bank credits, legacy import, transfer fee (`BURSARY`) | bursar, super | |
| Reconciliation check (`RECONCILERS`) | bursar, audit, deputyaudit, super | |
| Payment-history import (`MIGRATORS`) | bursar, super, ict, admin | |
| Refunds | read: bursar, super, audit, admin; write: bursar, super | **Maker–checker by person, in SQL** — the person who proposed a refund or a bank credit cannot approve it, whatever offices they hold |
| Accounting: sync, journal, reverse | bursar, super | Readers = finance readers + deputyaudit |
| Own position, references, receipts | student (`/me/fees/**`) | |

#### 3.3.20 Payment gateways (`payments`) and wallet (`wallet`)

- Checkout: applicant, student. Verify: any signed-in person for their own reference; bursar, ict, admin, super, audit for any. `BURSARY` (test checkout, sweep, resolve event, PayDirect import, biller) = bursar, ict, admin, super. Readers (desk, gateway configuration, PayDirect desk) = bursar, audit, deputyaudit, ict, admin, super, registrar, vc, dvc. **Gateway keys** (set, clear) = ict, admin, super only. Webhooks and the Quickteller start are public.
- Wallet: student endpoints `OFFICE_student`; `BURSARY` (load batch, credit, reset, reverse, status, sources, withdrawals) = bursar, admin, super; match a remittance row = bursar, registrar, dregistrar, academic, super; readers = bursar, registrar, dregistrar, academic, audit, deputyaudit, admin, super, ict, vc, dvc.

#### 3.3.21 Expenditure & stores (`expenditure`)

| Desk | Read | Act |
|---|---|---|
| Payment vouchers | bursar, audit, deputyaudit, super, admin, vc | raise/pay: bursar, super; advance/query/reject: audit, deputyaudit, super; answer a query: bursar, audit, deputyaudit, super. **SQL also checks the acting office per stage**: WITH_DIRECTOR needs `audit`, WITH_DEPUTY `deputyaudit`, WITH_AUDITOR either (super bypasses) |
| Budget | admin, audit, bursar, deputyaudit, dvc, super, vc | set: bursar, super |
| Tenders | admin, audit, bursar, deputyaudit, super, vc | all writes: bursar, super |
| Requisitions | admin, audit, bursar, deputyaudit, dvc, ict, registrar, super, vc | raise: bursar, dean, hrm, ict, registrar, super; approve/PO/close/reject: bursar, super |
| Stores and assets | admin, audit, bursar, deputyaudit, ict, super, vc | writes: bursar, super; asset verify: bursar, audit, deputyaudit, super |
| Research grants | admin, audit, bursar, deputyaudit, dvc, super, vc | add, state: bursar, dvc, super |

#### 3.3.22 Human resources (`hrm`) and staff (`staff`)

- Payroll readers: hrm, bursar, audit, deputyaudit, admin, super, vc, dvc; build/approve/pay/cancel: hrm, super; `/me/payslips` any signed-in person (own only).
- Leave: `/me/leave*` any signed-in person; approvers hrm, hod, dean, dregistrar, registrar, audit, admin, super — a HOD decides only for staff whose `home_department` is theirs.
- Movements: readers hrm, registrar, dregistrar, dvc, vc, audit, deputyaudit, admin, super; raise/issue hrm, registrar, super; approve/decline hrm, registrar, dregistrar, vc, dvc, super.
- Recruitment officers: hrm, registrar, super. Appraisal: record hrm, registrar, dean, hod, super (HOD scoped); readers add dregistrar, dvc, vc, audit, admin.
- Staff record `GET /hr/staff/{id}`: academic, admin, audit, bursar, dean, deputyaudit, dregistrar, dvc, facultyofficer, hod, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc; `/hr/staff/me` and own photo: any signed-in person.
- `staff` module (own record, profile, photo, College tier): every endpoint `isAuthenticated()`; the actor is always the token subject.

#### 3.3.23 Hostel (`hostel`)

`OFFICE` (every write) = services, housing, registrar, admin, super. `READERS` add bursar, dregistrar, academic, ict, audit, vc, dvc. Student: `/me/hostel…`. **No hall-level scope** — every officer sees every hall. Desk notices go to every current holder of `housing` or `services`. The Bursary reads (and confirms damage-charge references through the finance module) but does not act on the hostel desk.

#### 3.3.24 ICT help desk (`helpdesk`), support (`support`), health (`health`)

- **Help desk** `REQUESTER` = any signed-in person **except** applicants and postgraduate applicants (`isAuthenticated() and !hasAnyAuthority('OFFICE_applicant','OFFICE_pgapplicant')`); a staff token with no person record is refused (`HELPDESK_NOT_A_MEMBER`). `AGENTS` = ictagent, ict, admin, super (the desk). `DIRECTOR` = ict, admin, super (categories, SLA, settings). Who may be assigned or escalated to is decided in SQL (`helpdesk.is_agent`). A requester sees only their own tickets and never an internal note. `POST /helpdesk/track` is public and throttled.
- **Help & requests** (`support`) student side: `OFFICE_student`. Office desk `OFFICES` = registrar, dregistrar, bursar, ict, library, services, academic, hod, housing, admin, super — each office sees only requests addressed to its own office code; admin, super and ict see every office's. A student cannot address `dregistrar`, so that desk is always empty; a HOD sees every request addressed to "hod" (no department scope). The desk page `/support` is on no menu.
- **Health** `CLINIC` = services, super (there is no clinician office); student `/me/health…`. Every read of a record is logged and shown to the patient.

#### 3.3.25 Documents, certificates & ID cards (`credentials`)

| Tier | Offices | May |
|---|---|---|
| `READERS` | academic, registrar, dregistrar, records, dvc, vc, bursar, ict, admin, super, audit | Dashboard, requests, register, templates, verification log, office PDF |
| `OFFICE` | academic, registrar, dregistrar, records | Start, generate, QC, cancel, complete, deliveries, resend, clear a flag |
| `SIGNERS` | registrar, dregistrar, academic | Release, reissue, issue degree certificates (single and bulk) — **the officer who generated a document cannot release it** (segregation of duty in SQL) |
| `REVOKERS` | registrar, vc | Revoke, citing the instrument (guard and CHECK) |
| `CONFIG` | registrar, dregistrar, academic, super | Policies and templates |
| Legacy transcript queue | readers add dean, hod; `OFFICE` academic, registrar, dregistrar, records; `SIGNERS` registrar, dregistrar, academic | Mark paid, release, reissue |
| Identity cards | readers library, security, registrar, dregistrar, academic, records, ict, super; `ISSUERS` library, security, super | Issue, report lost |
| Student | `/me/documents…` | Requests, downloads, secure links |

Public verification (`verify`): `/api/v1/verify/**` needs no sign-in; document lookups are throttled (40 per 15 minutes per IP) and logged.

#### 3.3.26 Reports (`reports`), reporting (`reporting`), statistics (`stats`)

- Enrolment, registration-cause and carryover returns: academic, registrar, dregistrar, records, dvc, vc, ict, admin, super, dean, facultyofficer, hod (cut to faculty/department for the last three). Revenue, expenditure, income-expenditure: bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc. Postgraduate adds pgschool, pgsecretary; staff-ratio adds hrm; trends excludes dean, facultyofficer, hod.
- Due register and kept copies (`READERS`): vc, dvc, registrar, dregistrar, academic, records, bursar, audit, deputyaudit, hrm, ict, admin, super, pgschool, pgsecretary — **dean, facultyofficer and hod cannot keep a copy** (toolbar: "Your office reads this return; the office that owns it keeps and files the copy"). Registers: the same plus dean, facultyofficer, hod.
- Institutional overview (`reporting`) `MANAGEMENT` = ict, admin, super, vc, dvc, registrar, dregistrar, academic, audit, bursar.
- Student statistics readers: registrar, dregistrar, bursar, academic, records, ict, admin, super, dvc, vc, pgschool, pgsecretary, provost, collegesecretary, financecontroller, dean, facultyofficer, hod, exams. **Money figures** (`MONEY`) only for bursar, financecontroller, registrar, dregistrar, super, admin, pgschool, pgsecretary, provost, collegesecretary, dvc, vc; stripped server-side for everyone else. Bound: PG offices `is_pg`, College offices `is_chs`, faculty/department offices their unit.
- Exports from these desks put **S/N** first, generated at export time, and sort names A–Z.

#### 3.3.27 Platform (`platform`), governance, audit log, API keys

- Platform: status public; migrations ict, admin, super; readiness super, ict, admin, registrar, dregistrar, academic, bursar; data reset and demo removal super, ict (typed confirmation, no second approver); mail and SMS settings (`KEEPERS`) ict, admin, super; outbox read ict, admin, super, registrar; retry ict, admin, super; `/me/notices` any signed-in person except a student.
- Governance: readers registrar, dregistrar, ict, audit, deputyaudit, vc, dvc, admin, super; DPIA and DSR writes registrar, dregistrar, ict, super; DR drill ict, super; security posture ict, audit, deputyaudit, security, registrar, vc, dvc, admin, super.
- Audit log (`OVERSIGHT`): ict, admin, super, audit, deputyaudit, vc.
- API keys (`OPERATORS`): ict, admin, super. The register issues hashed keys, but **no request is authenticated by an API key** — scopes and quotas are stored, never enforced (NOT IMPLEMENTED).

---

## 4 Known mismatches between menus and guards

The office menus are written by hand; the guards are the law. Comparing every menu item's URL (`menus.md`, `routes.md`) with the guards of the API calls that page makes gives the list below. "Menu shows, API refuses" means the page opens but its data calls answer 403 (the page renders a `ProblemNotice`, and the toast "You do not have access to that"). "API allows, no menu" means the office may use the screen but has to type the URL. Source: the dossier that recorded the finding, or "routes vs guards" when found by this comparison and confirmed against the controller.

### 4.1 Menu item present, API refuses (403)

| Office | Menu item | URL | API guard that refuses | Effect | Status · source |
|---|---|---|---|---|---|
| Registrar | Administration → Audit Trail | `/audit` | `auditlog.OVERSIGHT` = ict, admin, super, audit, deputyaudit, vc | 403 on `/audit/entries`; "You don't have access to this screen" | NOT IMPLEMENTED (menu only) · A4 |
| Registrar | Staff → Staff Records | `/staff` | page calls `/api/v1/payroll/staff`; payroll `READERS` = hrm, bursar, audit, deputyaudit, admin, super, vc, dvc | Empty table with a 403 | Mismatch · routes vs guards |
| Housing | Staff → Staff Records | `/staff` | same | same | Mismatch · routes vs guards |
| Finance Controller (CHS) | Finance → Fee Setup and Schedule | `/finance/fees` | `finance.READERS` excludes `financecontroller` | 403 on every read of the page | PARTIALLY IMPLEMENTED · F1.13 |
| Secretary, SPGS | Finance → Fees | `/finance/fees` | same | 403 (PG fees are set on the PG module instead) | PARTIALLY IMPLEMENTED · F1.13 |
| Head of Department | Finance → Requisitions | `/finance/requisitions` | requisitions readers/raisers exclude `hod` | 403 | PARTIALLY IMPLEMENTED · F4.13 |
| Support Services | Finance → Requisitions | `/finance/requisitions` | same | 403 | PARTIALLY IMPLEMENTED · F4.13 |
| Support Services | Finance → Tenders | `/finance/tenders` | tenders readers = admin, audit, bursar, deputyaudit, super, vc | 403 | Mismatch · routes vs guards |
| Librarian | Services → Stock & Acquisitions | `/stores` | stores readers = admin, audit, bursar, deputyaudit, ict, super, vc | 403 | PARTIALLY IMPLEMENTED · F4.13 |
| Support Services | Services → Stores & Assets | `/stores` | same | 403 | PARTIALLY IMPLEMENTED · F4.13 |
| Support Services | Services → Alumni Register | `/alumni` | alumni readers = registrar, dregistrar, academic, records, vc, dvc, audit, deputyaudit, admin, super | 403 | Mismatch · D11 |
| Dean | Finance → Faculty Budget | `/finance/budget` | budget readers = admin, audit, bursar, deputyaudit, dvc, super, vc; the page also calls `/reports/income-expenditure` (revenue readers exclude dean) | 403 | Mismatch · routes vs guards |
| Dean, Lecturer | Academic → Research in the Faculty / My Projects | `/research/projects` | page calls `/api/v1/research/grants`; readers = admin, audit, bursar, deputyaudit, dvc, super, vc | 403 (the Vice-Chancellor's identical item works) | Mismatch · routes vs guards (dossier F recorded the grants page as unused; it is on three menus) |
| Dean, SPGS; Secretary, SPGS | Academic → Results Broadsheet | `/results/broadsheet` | `results.READERS` excludes pgschool, pgsecretary | 403 | Mismatch · routes vs guards |
| Dean, SPGS; Secretary, SPGS | Academic → Graduation List | `/graduation` | graduation readers exclude pgschool, pgsecretary | 403 | Mismatch · routes vs guards |
| Provost, College Secretary, Finance Controller, MBBS Coordinator, Dean SPGS, Secretary SPGS, Support Services, SIWES Coordinator, ICT Support Agent, Deputy Director of Audit (FALLBACK) | Overview → Search | `/search` | `/api/v1/student/search` uses `student.READERS` (21 offices) which excludes these ten | 403 on every search | Mismatch · routes vs guards |
| Dean, Faculty Officer, HOD | Reports → Reports & Returns (due register, kept copies, "Keep a copy") | `/reports` | snapshot/due `READERS` exclude the three | Due register and kept copies refused; the returns themselves open, cut to scope; "Keep a copy" refused with the toolbar's explanation | NOT IMPLEMENTED by design · A9 |
| Chief Security Officer | Overview → Verify a Card (home) | — (no URL) | No endpoint or page exists | Button announces "still the prototype's screen" | PLACEHOLDER · G5.13 |
| Examinations Officer | Academic → CBT Sessions | `/examinations/sessions` | Opens the results examination sessions; no CBT delivery exists | Label promises a module that is NOT IMPLEMENTED | E-H |
| Deputy Director of Audit | whole menu | — | Office has no menu; the Shell `FALLBACK` (Search, Dashboard, Leave & Payslip) is shown although the office acts in vouchers, reconciliation, expenditure reads and reports | Acts only by URL | PARTIALLY IMPLEMENTED · A10, generated summary |

### 4.2 API allows the office, no menu item shows it

| Office | Screen | URL | API guard that allows | Effect | Status · source |
|---|---|---|---|---|---|
| Registrar | Admission Settings, CAPS upload, candidate data, screening, PUTME scores, merit list, DE screening | `/admissions/settings`, `/admissions/caps`, `/admissions/candidate-data`, `/admissions/screening`, `/admissions/scores`, `/admissions/merit`, `/admissions/de-screening` | `LOADERS` (academic, registrar), `OFFICE`, `SECRETARIAT`, `SCORE_UPLOADERS` all name registrar | Reachable by URL; the Registrar's menu lists only Admissions, Admitted List and the CBT schedule | PARTIALLY IMPLEMENTED · B2 |
| Deputy Registrar, Super Administrator (acting); Records, Bursar, ICT, Admin, DVC, VC (reading) | Programme Eligibility (V266) | `/admissions/eligibility` | `AdmissionEligibilityController` READERS academic, registrar, dregistrar, records, bursar, ict, admin, super, dvc, vc; OFFICE academic, registrar, dregistrar, super | Reachable by URL; the menu lists it for academic and registrar only | IMPLEMENTED · B2 |
| Registrar, Deputy Registrar (AA), Director of ICT | Session & Semester Setup | `/calendar` | calendar `WRITERS` | Reachable by URL; menu item only for academic and super | PARTIALLY IMPLEMENTED · A7 |
| Registrar, System Administrator, Super Administrator | Hostel desk | `/hostel` and sub-screens | hostel `OFFICE` | Reachable by URL | G1.3 |
| Head of Department, Academic Officer | PG Courses, Course Results desks | `/admissions/postgraduate/courses`, `/admissions/postgraduate/results` | coursework `DESK` | No menu entry | C2 |
| Lecturer | Question Bank | `/exams/question-bank` | cbt `READERS`/`AUTHORS` | No menu entry (the lecturer's sheet list carries a question count) | E-H |
| Every support office | Help & requests desk | `/support` | support `OFFICES` | On no menu at all | G3.3 |
| Provost, College Secretary, Finance Controller | Provost dashboard read model | `GET /api/v1/provost/dashboard` | provost guard | No page calls it | Backend only · E-I |
| Academic, Registrar, Deputy Registrar, DVC, VC, ICT, super | Transfer committee, Senate, withdraw, effect | `POST /transfers/…` | `SAIC`, `SENATE`, `OFFICERS`, `EFFECT` | No screen | Backend only · D6 |
| Academic, Deputy Registrar, HOD, Lecturer, Registrar, super | Create or submit a registration for a student | `POST /registration/…` | `APPROVERS` | No screen | Backend only · D4 |
| Any signed-in person | List and end own sessions | `GET /auth/sessions`, `POST /auth/sessions/{id}/end` | authenticated | No screen | Backend only · A1 |
| Any signed-in person | Own notices | `/me/notices` | authenticated, non-student | Menu item only on the lecturer menu; other offices open `/me/notices` by URL | A2 |

### 4.3 Guard present, rule makes it inert

| Office | Where | Finding | Source |
|---|---|---|---|
| Deputy Registrar (AA) | Help & requests desk | In `support.OFFICES`, but a student cannot address a request to `dregistrar`; the desk is always empty | G3.2 |
| Any `DESKS` office | Results approval chain | The guard admits ten offices to `advance`; the stage→office map is UI-only, so the API accepts an office at a stage that is not its own | E-B §12 |
| Finance Controller | College dashboard | `/college/dashboard` renders the Payment Report for this office; the office acts in nothing | E-I |

> **Tip:** When a person reports "You don't have access" on a screen the sidebar offered them, check this table first, then the acting office in the sidebar ("Signed in as"), then whether the grant is live (§5).

---

## 5 User creation and role assignment

### 5.1 The staff account lifecycle

Three tables carry a member of staff: `iam.person` (who they are), `iam.credential` (how they sign in), `iam.office_assignment` (what they hold, under what instrument, from when to when). The Users & Roles console (`/people`) works them one person at a time; two bulk loaders exist for teaching and non-academic staff (§5.3).

```text
Users & Roles  (/people)                                     Who may
 ┌────────────────────────────────────────────────────────┐
 │ 1  + New person                                        │  registrar, dregistrar, hrm, ict, admin, super
 │      surname, given names, staff number?, email, phone │
 │            ↓                                           │
 │ 2  Grant an office                                     │  registrar, dregistrar, vc, super, ict, admin
 │      office, bounded to (scope kind + which one),      │
 │      from, to?, authority for the grant (instrument)   │
 │            ↓                                           │
 │ 3  Create account                                      │  registrar, dregistrar, ict, admin, super
 │      username (staff number or email), first password  │
 │      → must_change = true                              │
 │            ↓                                           │
 │ 4  Person signs in at /login                           │  the person
 │      → sent to /account/password: current, new ×2      │
 │      → must_change = false; event CHANGED              │
 │            ↓                                           │
 │ 5  Works in the acting office; switches office in the  │  the person
 │    sidebar when holding more than one                  │
 │            ↓                                           │
 │ 6  Reset password (Registry)  → must_change again,     │  registrar, dregistrar, ict, admin, super
 │    lock cleared                                        │
 │    Forgot password (self)     → emailed/SMS link,      │  the person (public /login/forgot)
 │    1 hour, once                                        │
 │            ↓                                           │
 │ 7  End a grant  (date, reason)  → valid_to set;        │  registrar, dregistrar, vc, super, ict, admin
 │    the office leaves the token at the next sign-in     │
 │            ↓                                           │
 │ 8  Change of office = end the old grant + grant the    │  same
 │    new one; a grant is never edited or deleted         │
 └────────────────────────────────────────────────────────┘
 Leaver: iam.person.ended_on refuses sign-in — but no screen or
 endpoint sets it today (NOT IMPLEMENTED); end every grant instead.
```

> **Screenshot Required:** Users & roles — `/people?new=grant` — the "Grant an office" modal with Office, Bounded to, Which one, From, To and "Authority for the grant".

### 5.2 Step table: staff accounts and grants

| Step | Screen / endpoint | Required fields | Validations and rules | Recorded |
|---|---|---|---|---|
| Create a person | `/people` → "+ New person" → `POST /api/v1/iam/persons` | Surname, Given names; optional Staff number (`MOAUM/STF/…`), Email ("where a password reset and notices are sent"), Phone | Staff number UNIQUE (409 `ALREADY_EXISTS`) | `iam.person` on the spine; toast "Person created" |
| Set contact | "Contact" → `PUT /iam/persons/{id}/contact` | Email, Phone | The email here is where a reset link goes | `iam.person` |
| Grant an office | "Grant an office" → `POST /iam/persons/{id}/office-assignments` | Office (from `GET /iam/offices`), Bounded to (preset from `ref.office.scope_kind`), Which one (faculty/department/programme/course code; blank for the University or the platform), From, To ("an acting grant must carry one"), Authority for the grant | `IAM_NO_SUCH_OFFICE`; `IAM_GRANT_NEEDS_INSTRUMENT` ("An office is held under a letter or minute; none was given."); scope kind ∈ nine kinds; `valid_to ≥ valid_from`; MBBS Coordinator: level 200–600 and an existing lecturer grant in a College department; grantor = acting person | `iam.office_assignment`; toast "<office> granted under <instrument>" |
| Create the sign-in | "Create account" → `PUT /iam/persons/{id}/credential` | Username (prefilled with the staff number, lower-cased; or an email), First password | Username 3–200 chars, lower-case, unique (`AUTH_USERNAME_TAKEN`); password ≥ 10 and not containing the username; bcrypt cost 12; `must_change = true`; the first password is told to the person out of band, never emailed | `iam.credential` (audit-exempt), `iam.credential_event` SET |
| First sign-in | `/login` → `/account/password` → `POST /api/auth/change-password` | Current password, New password ×2 | ≥ 10 characters, not the username; both match | `credential_event` CHANGED |
| Reset by the Registry | "Reset password" → same `PUT …/credential` | New first password | As create; clears `locked_until`; `must_change` again | `credential_event` RESET; toast "Password reset by the Registry" |
| Forgot / reset by the person | `/login/forgot` → `POST /api/v1/auth/forgot`; `/login/reset?token=` → `POST /api/v1/auth/reset` | Identifier; then new password ×2 | Always answers "If that names an account, a reset link is on its way"; token SHA-256 kept, 1 hour, single use; reset ≥ 8 characters (shorter than the Registry's 10); clears lock and `must_change` | `iam.password_reset`; notice "Reset your MOAUM password" (email and SMS) |
| End a grant | "End" → `POST /iam/persons/{id}/office-assignments/{grant}/end` | Ended with effect from (today when blank), Reason | Reason required ("an office is ended with the reason on the record"); no live grant → refused; grants are never deleted | `office_assignment.valid_to` |
| Change of role | End the old grant, grant the new | as above | The person must sign out and in for the token to change | |
| Deactivate a person | — | — | **NOT IMPLEMENTED**: `iam.person.ended_on` is read by sign-in (`AUTH_BAD_CREDENTIALS` for an ended person) but no screen or endpoint sets it; a lecturer with no teaching history can be deleted outright from `/people/lecturers` | |
| Re-activate | Grant again, reset the password | as above | | |

> **Warning:** Any of the six grantor offices may grant any office — including `super` and `ict` — to anyone, with free-text authority and no second person. Keep the grantor offices few and read the "Staff accounts and the offices they hold" panel regularly (tile "Holding two offices", "Grants expiring in 30 days").

### 5.3 Bulk onboarding

| Loader | Screen | Who | What each row becomes | Notes |
|---|---|---|---|---|
| Teaching staff | Staff → Upload Lecturers `/people/lecturers` (`POST /iam/lecturers/import`) | super, ict, admin; API also registrar, dregistrar, hrm | Person + sign-in (username and first password `P<PNO>`, `must_change`) + `lecturer` office bounded to the home department + establishment record | Needs PNO, Full Names, Department columns; chunks of 25; idempotent; a department the sheet names but the register lacks is reported ("Create these departments first"); a password already set is never reset; edit moves the office when the department changes; delete keeps a lecturer who already teaches |
| Non-academic staff | Staff → Upload Non-Academic Staff `/people/staff` (`POST /iam/staff/import`) | super, ict, admin, registrar, dregistrar, hrm | Person + establishment record placed in a unit resolved through `ref.unit_alias` | Dry run first ("Check a File"); **issues no sign-in and no office** — grant and credential follow on `/people` |

The predictable lecturer first password is a known weakness (dossier A2 §12): anyone who knows a PNO can sign in first if the lecturer has not. The lecturer must change it at first sign-in.

### 5.4 Student accounts

A student never appears on `/people`. The record (`people.student`) and the account (`iam.student_account`) are created by the admissions flow:

```text
Undergraduate
 Applicant registers at /apply with the JAMB number (public)        → admissions.applicant_account (bcrypt hash)
   ↓ fee, form, screening, decision, acceptance
 Academic Office / Registrar runs the intake from /admissions        → people.student, admission no MOAUM/ADM/YY/NNNNNN
   (POST /student/intake/{session}; academic, registrar, dregistrar)   (runs on ADMITTED and ACCEPTED candidates)
   ↓
 Student signs in at /login with the admission number                → iam.student_account created by CARRY-OVER of the
                                                                        applicant's hash (event CARRIED_OVER)
   ↓ fees, registration
 Matriculation run (academic, registrar, dregistrar)                 → matric number; "Your matriculation number" notice;
                                                                        the number opens the portal in place of the admission no

Postgraduate
 Applicant applies at /pg/apply (public)                             → PG account, PG/YY/NNNNNN
   ↓ HOD → Dean → School decisions, acceptance fee
 School admits (pg_admit: pgschool, pgsecretary, registrar, super)   → people.student (entry_mode POSTGRADUATE) +
                                                                        iam.student_account with the applicant's hash

Migrated or accountless student
 Registry opens the account from Student 360 → "Portal account"      → PUT /student-auth/accounts/{id} with an
   (registrar, dregistrar, academic, records, ict, super)               eight-character first password; must_change
 Migrated account with must_change and no hash                       → the student's own number is accepted as the
                                                                        first password (iam.set_migrated_default_passwords)
```

Rules: a student who has no applicant account behind them gets "No portal account has been opened for this number yet." until the Registry opens one (the button is enabled only once a matriculation number exists); lockout is 5 failures for 15 minutes; a student's password change is `POST /student-auth/change-password` (≥ 8); forgot/reset works on matric number, admission number or email. The token carries only `student`; a College student from 200 level is routed to `/college/student`, a postgraduate to the `pgstudent` menu. See *06 Workflows* for the admissions and matriculation flows and dossiers B, C and D for the field-level rules.

### 5.5 Applicant and postgraduate applicant accounts

| Kind | Created by | Identifier | Password rule | Becomes |
|---|---|---|---|---|
| Undergraduate applicant | Self-registration at `/apply` (public): JAMB number (must be on the committed CAPS list for the session), email, phone (11 digits from 0), password ×2 | JAMB number, `APP/YY/NNNNNN` or email | ≥ 8; bcrypt 12; lockout 5/15 min | The student account, by carry-over of the hash at first student sign-in |
| Postgraduate applicant | Self-registration at `/pg/apply` (public): programme, personal details, email, password; the application number and fee reference are issued in one call | Email or `PG/YY/NNNNNN` | As above | The student account when the School admits |

Both kinds sign in through `/login`; both receive the `applicant` authority; both have forgot/reset through the shared reset service (`subject_kind` APPLICANT / PGAPPLICANT).

### 5.6 External examiner accounts

An external examiner is **invited**, not created on `/people`: the examiner desk (academic, dregistrar, registrar, exams, hod, dean, pgschool, pgsecretary, admin, super) appoints the examiner; an invitation email carries a link to `/login/activate?token=…` (public), where the examiner sets a password (≥ 10, not containing the email) and the account becomes `ACTIVE`. The token then carries `extexaminer`; an examiner whose status is not ACTIVE is refused on every `/me` call. Reminders run daily at 07:15 (Africa/Lagos).

### 5.7 The first account (bootstrap)

On an empty register, `/login/first` ("Create the first account") posts `POST /api/v1/auth/bootstrap` with the header `X-Bootstrap-Secret`. It succeeds only when the secret equals the API's `MOAUM_AUTH_HMAC_SECRET` **and** `iam.credential` is empty (`AUTH_BOOTSTRAPPED` — "The portal already has accounts; the first one is made once."). Fields: Bootstrap secret, Surname, Given names, Staff number (optional), Username, Password (≥ 10). The person is created and granted `registrar` (institution), `academic` (institution), `ict` (platform) and `super` (platform) under the instrument "Bootstrap of the portal, Directorate of ICT", then signed in as `registrar` and taken to `/people`. Every later account is made from there. CI exercises this door on every image build.

### 5.8 Sessions, lockout and sign-out

| Rule | Value | Where |
|---|---|---|
| Session length | 12 hours absolute (`platform.session.absolute_end`) | `AuthService`, `ApplicantService` |
| Lockout | 5 failed attempts → locked 15 minutes ("This account is locked after repeated failures; try again after HH:MM") | staff, student, applicant doors |
| Deploy floor | A session issued before the API instance started is refused ("The portal was updated. Sign in again.") | `SessionGuard` |
| Ended session | "This session was ended. Sign in again." | `SessionGuard` |
| Sign-out | Nav-foot button → `POST /api/v1/auth/sign-out`; both cookies cleared | `Shell` |
| Own sessions | `GET /auth/sessions`, `POST /auth/sessions/{id}/end` — **no screen** (PARTIALLY IMPLEMENTED) | `AuthController` |
| Ending another person's session | **NOT IMPLEMENTED** (the Registrar cannot; the ADR text says otherwise) | `SessionGuard` comment |
| Rate limiting of sign-in / forgot | **NOT IMPLEMENTED** (`AUTH_THROTTLED` exists as a title only) | `ProblemHandler` |
| Single sign-on (Keycloak, MFA required by default) | IMPLEMENTED in code, **not deployed**; button hidden until `MOAUM_SSO_*` are set; matches the person by staff-number claim, else username/email | `SsoService`, `docs/keycloak.md` |

Every sign-in outcome is written (`iam.sign_in_event`, `iam.student_event`, `admissions.applicant_event`) and shows on the audit trail as `auth:<outcome>`. Sign-in, lockout and password change send no notice; only the reset request does.

### 5.9 Demo accounts

`docs/demo-accounts.md` lists a demo sign-in for every office (`demo.<office>`, for example `demo.registrar`, `demo.hod`, `demo.ictagent`), eight demo students at every level (`MOAUM/MTC/26/9901` … `MOAUM/MED/26/9908`) and one demo applicant, all created by `bash db/demo.sh` and removable with "Remove demo data only" on the platform dashboard. The password is printed in that file and is not repeated here. The demo HOD, Examinations Officer and Lecturer are scoped to Mathematics and Computer Science; the demo Dean, Faculty Officer and Faculty Examinations Officer to the Faculty of Science; the demo MBBS Coordinator holds the 200 Level. There is no demo account for `deputyaudit`'s screens beyond the office itself, and none for the external examiner (that account is made by invitation).

---

## 6 Permission inheritance and precedence

**There is no hierarchy.** An office grants exactly the endpoints on which it is named; nothing is inherited from a "higher" office, and a person holding several offices has the union of them only when acting in each in turn (one acting office per request, §1.3). The points below are the ones that surprise new administrators.

1. **`super` is named explicitly, not implied.** It appears where a controller listed it and nowhere else. Examples from the matrix where `super` is **not** an actor: the Dean's desk and the HOD's desk read models (`/hod/dashboard`, `/hod/fees`, `/hod/staff` are `hod` only; `/dean/dashboard` is dean, facultyofficer, super); Alumni (read only); Audit log (read only); Clearance (read only — `super` is not a `SIGNER`); Graduation (read only — approval is registrar, dregistrar, academic); Provost's desk (read only); results **score entry** (`ENTRY` = lecturer, exams, academic) and the Senate minute (registrar, dregistrar) — `super` can advance a sheet but cannot write marks or record the minute; the admissions CAPS load (`LOADERS` = academic, registrar); PG department and faculty decisions name `super` but the School admit and the coursework desk do too — while document **release** (`SIGNERS` = registrar, dregistrar, academic) and **revocation** (registrar, vc) exclude it; the SIWES supervisor score; the results `DESKS` list (super is not in it — it advances nothing).
2. **`admin` is not a lesser `super`.** It is a distinct list: it acts in identity, gateways, mail/SMS, the help desk, hostel, library and allocation, but only reads finance, results, documents and governance, and is absent from the calendar.
3. **`ict` is the structure office.** Creating, uploading, archiving and removing faculties, departments, programmes and course structures is `ict` alone (`UPLOADERS`); the Registrar, the Academic Office and `super` cannot.
4. **Registrar ≠ Deputy Registrar.** They differ on: CAPS load and commit (Registrar), PG admit (Registrar), hostel acts (Registrar), revocation (Registrar with the VC), transfers at Senate (Registrar with VC, DVC, super), movements raise (Registrar with HRM), recruitment (Registrar). Both record the Senate minute and both release documents.
5. **Reading is wider than acting, but not universal.** The 21-office reader list of the student module is the broadest; the results readers (15), the finance readers (10) and the audit-log readers (6) are different lists. An office that appears in one is not thereby in another — the Search mismatch in §4 is the visible symptom.
6. **Two-person rules bind the person, not the office.** Refund and bank-credit approval (SQL maker–checker), document release (the generator may not release), and the results chain ("not the same person twice in a row") are checked against the actor id. Holding two offices does not get round them.
7. **Stage rules bind the office at a moment.** Transfers, deferments and the College decisions check the office *and* the record's state; the same office is refused at another stage even though the guard admits it.
8. **Scope narrows, never widens.** A HOD who also holds `dean` sees the faculty only while acting as Dean. A grant with no scope where one is expected resolves to `__none__` and sees nothing ("Your Head-of-Department office is not tied to a department yet").
9. **Order of checks.** Session → acting office in token → guard → scope → service/stage/ownership rule → database CHECK and audit context. The first refusal wins; a 403 from the guard is reported before any 422 from a rule.
10. **Where enforcement is UI-only, treat the guard as the permission.** The results stage map (§3.3.16) and the frontend `MAY` arrays are conveniences; the API list is what a person can do with a script.

---

## 7 Quick reference by office group

Each table lists what the group **may do**, what it may **read only**, and what it **may not** do, as the guards stand. "Registry" means registrar and dregistrar; differences are noted.

### 7.1 Registry

| May do | Read only | May not |
|---|---|---|
| Create persons, grants (any office), credentials, staff loads; matriculation runs, single issue, faculty-list confirm, number format; clearance of any unit; document start/generate/QC/release/reissue/certificate issue; Senate minute; deferment approval and cancel; transfer at TO_OK; admissions decisions, settings, screening, scores, PUTME setup and door; Registrar only: CAPS load/commit, PG admit, hostel acts, revocation (with VC), transfers at Senate, movements raise, recruitment; both: movements approve, governance DPIA/DSR, exam sessions, graduation audit and approval, calendar, allocation, SIWES assignment, external-examiner desk, readiness | Finance (schedule, references, day book, payments query, reconciliation), payment gateways, wallet (Registry may match a remittance row), platform outbox, library desk, hostel (dregistrar), statistics with money figures, all returns and registers | Structure creation/upload (ict only); confirm a school-fee reference or set the fee schedule (bursar, super); write scores; read the audit trail (Registrar's menu item notwithstanding); end another person's session; set gateway keys; help-desk settings |

### 7.2 Academic Office, Exams and Records

| May do | Read only | May not |
|---|---|---|
| **Academic Office:** CAPS load/commit and intake; admissions decisions, screening, scores, clearance items, PUTME compute and door; matriculation runs and format; calendar and level limits; exam sessions; score entry on any sheet and every desk stage; exam slots; held scripts; result queries; graduation audit and approval; documents start/generate/QC/release/issue and policies; clearance of any unit; catalogue ownership and registration opening; allocation; LMS on any space; SIWES; PG department and faculty decisions, coursework; transfer at REG_OK and paper cases; deferment approval. **Records:** exam sessions; validation stage; documents start/generate/QC; graduation audit; admissions clearance items; PUTME door; exam slots; legacy migration | Academic Office: finance, gateways, hostel, HR, library, platform outbox, statistics without money figures. Records: matriculation, clearance, allocation, class lists, College, deferments, HR, statistics | Academic Office: revoke a document; record the Senate minute; set the fee schedule; upload structure; grant offices. Records: release a document; approve graduation; run matriculation; approve a deferment |

### 7.3 Bursary and Audit

| May do | Read only | May not |
|---|---|---|
| **Bursar:** fee schedule and structure; confirm references (school, applicant, PG, transfer, hostel charges); clearance scheme; bank credits and refunds (maker–checker by person); reconciliation attestation; wallet loads/credits/reversals; NELFUND; sweep, PayDirect, biller; vouchers raise/pay; budget; tenders; requisitions approval; stores; grants; financial clearance unit; legacy imports. **Finance Controller (CHS):** nothing. **Audit:** voucher director's desk; reconciliation check; asset verification; leave approval. **Deputy Audit:** voucher deputy's desk; reconciliation check; asset verification | Bursar: College, documents, hostel, HR/payroll, library, platform outbox, results and held scripts, statistics with money figures. Finance Controller: College payment report, College overview, statistics with money figures (CHS). Audit: audit trail, governance, documents, hostel, library, wallet, IAM persons, HR, revenue/assets/staff desks. Deputy Audit: audit trail, governance, HR, payments, wallet, alumni | Bursar: gateway keys (ict/admin/super); write results or documents; grant offices. Audit: raise or pay a voucher; confirm a fee; edit any record. Finance Controller: open `/finance/fees` (403); search (403) |

### 7.4 ICT and platform

| May do | Read only | May not |
|---|---|---|
| **Director of ICT:** structure create/upload/archive/remove (alone); persons, credentials, grants, staff loads; calendar; mail/SMS; gateway keys; API consumers; help-desk settings and queue; data reset and demo removal; DR drills; DPIA/DSR; deferment tick; transfer effect; PUTME scores and door; old-portal imports; student account open; migrations desk. **System Administrator:** persons, credentials, grants, staff loads; mail/SMS; gateway keys; API consumers; help-desk settings and queue; allocation; hostel acts; library desk; payment sweep/PayDirect; SIWES; deferments; external-examiner desk; wallet loads. **Super Administrator:** all of the above plus calendar, documents policies, matric format, hostel, health, LMS, and every desk where named. **ICT Support Agent:** the help-desk queue | ICT: audit trail, clearance, registration, documents, graduation, hostel, HR, library, matriculation, wallet, statistics. Admin: alumni, audit trail, CBT, clearance, registration, documents, expenditure, governance, graduation, matriculation, results, transfers, statistics with money figures. Super: alumni, audit trail, clearance, Dean's/HOD's/Provost's desks, graduation, reporting, statistics | ICT: write scores or approve results; confirm fees; release documents. Admin: calendar; fee schedule; score entry; document release; DPIA/DSR. Super: score entry; Senate minute; document release/revocation; clearance signing; graduation approval; CAPS load; results advance. ICT Support Agent: anything outside tickets (its Search item is refused) |

### 7.5 Faculties, departments and the College

| May do | Read only | May not |
|---|---|---|
| **Dean:** Faculty Board stage; faculty clearance unit; allocation; catalogue writes; deferment recommendation; PG faculty decision; examiner desk; appraisal/leave of faculty staff; requisitions raise; CBT authoring; LMS. **Faculty Officer:** compilation stage; matriculation faculty lists; deferment recommendation. **Faculty Exams Officer:** scrutiny stage; exam slots. **HOD:** department board stage; registration approve/return; allocation; department catalogue; department clearance; deferment recommendation; transfers (from/to); PG department decision and coursework scoring; SIWES; examiner desk; appraisal/leave of department staff; CBT authoring; LMS. **Exams Officer:** verification stage; score entry; held scripts; queries; exam slots; CBT authoring; College results. **Lecturer:** scores on own sheets; held scripts; attendance/slots of own courses; own course spaces; CBT questions; College logbooks as supervisor. **SIWES Coordinator:** assign supervisors; score own students. **Provost / College Secretary:** postings, decisions, confirmation, appeals, calendar, enrolment; College deferments. **MBBS Coordinator:** results, CA and enrolment at own level | Dean/Faculty Officer/HOD: returns and registers cut to scope; matriculation; graduation (dean, hod); documents (dean, hod); admissions cycle and policy (dean, hod); statistics (bound). Lecturer/Exams: class lists, allocation history, catalogue. College offices: statistics with money figures (CHS), payment report | Dean/Faculty Officer/HOD: keep a copy of a return; approve a deferment; run matriculation; open `/finance/budget`, `/research/projects`, `/finance/requisitions` (403). Lecturer: another lecturer's sheet; open `/research/projects` (403). Exams Officer: department board. College offices: search (403); anything outside the College's students |

### 7.6 Postgraduate School and external examiners

| May do | Read only | May not |
|---|---|---|
| **Dean SPGS / Secretary SPGS:** School decision, accept, admit, student status; research pipeline, panels, School Board; PG examiner appointment; PG calendar; coursework endorse and score; PG deferments; external-examiner desk. **Secretary also:** confirm PG fees; registration desk; thesis clearance; results to Senate. **External Examiner:** assessments on assigned projects; own profile | HR staff records; statistics with money figures (PG bound); postgraduate return and registers | Open `/results/broadsheet`, `/graduation`, `/finance/fees` or `/search` (403); matriculate (the Registry's run); revoke or release documents. External Examiner: anything outside `/examiner/**` |

### 7.7 Students and applicants

| May do | Read only | May not |
|---|---|---|
| **Student:** course registration (submit; changes only while DRAFT/RETURNED); fee references and checkout; deferment request; transfer request and fee; document requests and downloads; hostel application, acceptance, maintenance, checkout, transfer request; library reservations and fine references; health appointments and consent; help requests; tickets; result queries on own scores; biodata change requests; PG coursework registration and research submissions; password change. **Applicant:** application form, fee, screening slip, acceptance, clearance documents, password | Own results, statement, broadsheet, carryovers, docket, receipts, notices, ID card, College record | See another student's record; approve anything; address a request to `dregistrar` (not offered); raise a ticket as an applicant |

### 7.8 Services, housing, library, security, health

| May do | Read only | May not |
|---|---|---|
| **Housing:** every hostel act; HOSTEL clearance unit; answer housing requests. **Support Services:** clinic (arrival, triage, visits, fitness, restrict); hostel acts; library circulation; own clearance unit; answer services requests. **Librarian:** circulation, fines waiver and rule, card printing, library clearance unit; answer library requests. **Chief Security Officer:** issue and replace identity cards; read security posture | Housing, Library, Security: Records & queries (student module). Services: none | Housing: `/staff` (403). Services: `/finance/requisitions`, `/finance/tenders`, `/stores`, `/alumni`, `/search` (all 403). Librarian: `/stores` (403). Security: verify a card (no page) |

---

## 8 Appendix: guard constants referenced in this volume

| Constant (controller) | Offices |
|---|---|
| `AccountsController.READERS` | registrar, dregistrar, hrm, ict, admin, super, audit |
| `AccountsController.CREDENTIALS` | registrar, dregistrar, ict, admin, super |
| `AccountsController.GRANTORS` / `IamController` grant | registrar, dregistrar, vc, super, ict, admin |
| `AccountsController.STAFF_LOADERS` / `IamController` person | registrar, dregistrar, hrm, ict, admin, super |
| `CalendarController.WRITERS` | academic, registrar, dregistrar, super, ict |
| `CatalogueController.UPLOADERS` | ict |
| `CatalogueController.OWNERS` | hod, dean, academic, dregistrar, registrar, admin, super |
| `AdmissionsController.LOADERS` | academic, registrar |
| `ApplicantsController.OFFICE` | academic, registrar, dregistrar |
| `PutmeController.OFFICE` / `DOOR` | academic, registrar, dregistrar, super / academic, registrar, dregistrar, records, ict, super |
| `PgAdmissionsController.SPGS` / `ADMIT` | pgschool, pgsecretary, super / pgschool, pgsecretary, registrar, super |
| `ExaminersController.DESK` | academic, dregistrar, registrar, exams, hod, dean, pgschool, pgsecretary, admin, super |
| `StudentController.READERS` | academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, ict, admin, super, bursar, library, security, housing, hrm, audit, lecturer |
| `StudentController.WRITERS` | academic, registrar, dregistrar |
| `MatriculationController.RUNNERS` / `OFFICERS` / `MatricFormatController.CONFIG` | academic, registrar, dregistrar / + facultyofficer / academic, registrar, dregistrar, super |
| `RegistrationController.HOD_APPROVES` | hod, super |
| `DefermentsController.DESK` | hod, dean, facultyofficer, academic, registrar, dregistrar, records, pgschool, pgsecretary, provost, collegesecretary, super, admin |
| `TransferController.APPROVERS` | hod, registrar, dregistrar, academic, super |
| `ClearanceController.SIGNERS` | academic, registrar, dregistrar, dean, hod, bursar, library, services, housing |
| `AllocationController.ALLOCATORS` | hod, dean, academic, dregistrar, registrar, admin, super |
| `ResultsController.READERS` | academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, lecturer, ict, admin, super |
| `ResultsController.DESKS` | lecturer, exams, hod, facultyexams, facultyofficer, dean, records, registrar, dregistrar, academic |
| `ResultsController.ENTRY` / `EXAMS` / minute | lecturer, exams, academic / records, academic, registrar, dregistrar / registrar, dregistrar |
| `QuestionBankController.AUTHORS` | lecturer, hod, exams, dean, super |
| `CollegeController.DESK` | provost, collegesecretary, academic, registrar, dregistrar, admin, super |
| `FinanceController.READERS` / `BURSARY` / `RECONCILERS` | bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc / bursar, super / bursar, audit, deputyaudit, super |
| `PaymentsController.BURSARY` / keys | bursar, ict, admin, super / ict, admin, super |
| `WalletController.BURSARY` | bursar, admin, super |
| `PayrollController.READERS` | hrm, bursar, audit, deputyaudit, admin, super, vc, dvc |
| `HostelLifecycleController.OFFICE` | services, housing, registrar, admin, super |
| `HelpdeskController.AGENTS` / `DIRECTOR` | ictagent, ict, admin, super / ict, admin, super |
| `SupportController.OFFICES` | registrar, dregistrar, bursar, ict, library, services, academic, hod, housing, admin, super |
| `HealthController.CLINIC` | services, super |
| `DocumentsController.OFFICE` / `SIGNERS` / `REVOKERS` / `CONFIG` | academic, registrar, dregistrar, records / registrar, dregistrar, academic / registrar, vc / registrar, dregistrar, academic, super |
| `IdentityCardController.ISSUERS` | library, security, super |
| `SnapshotsController.READERS` (due register, kept copies) | vc, dvc, registrar, dregistrar, academic, records, bursar, audit, deputyaudit, hrm, ict, admin, super, pgschool, pgsecretary |
| `StudentStatsController.MONEY` | bursar, financecontroller, registrar, dregistrar, super, admin, pgschool, pgsecretary, provost, collegesecretary, dvc, vc |
| `ReportingController.MANAGEMENT` | ict, admin, super, vc, dvc, registrar, dregistrar, academic, audit, bursar |
| `AuditLogController.OVERSIGHT` | ict, admin, super, audit, deputyaudit, vc |
| `GovernanceController.WRITERS` / `ICT` | registrar, dregistrar, ict, super / ict, super |
| `ApiKeysController.OPERATORS` / mail & SMS `KEEPERS` | ict, admin, super |

*End of volume 04. For the complete endpoint list with each guard see 07 API Reference; for the screens each office reaches see 05 Module Navigation Guide; for the account procedures in administrator form see 02 Administrator Manual.*
