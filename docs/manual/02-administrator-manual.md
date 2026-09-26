# 02 — Administrator Manual

**MOAUM Unified University Portal** — Rev. Fr. Moses Orshio Adasu University, Makurdi
Directorate of ICT · Documentation package, volume 02 · Repository state: commit `8c2b6fa`, migrations V001–V263

**Audience.** Super Administrator (`super`), System Administrator (`admin`), Director of ICT (`ict`) and ICT Support Agents (`ictagent`), Registrar (`registrar`) and Deputy Registrar (Academic Affairs) (`dregistrar`), Academic Officer (`academic`), Exams and Records (`records`), Bursar (`bursar`) and the Finance Controller of the College of Health Sciences (`financecontroller`), Director of Internal Audit (`audit`) and Deputy Director of Audit (`deputyaudit`), Director of Human Resource Management (`hrm`), Dean (`pgschool`) and Secretary (`pgsecretary`) of the School of Postgraduate Studies, Provost (`provost`), College Secretary (`collegesecretary`) and MBBS Coordinator (`mbbscoordinator`), Deputy Registrar (Housing, Welfare, Passages) (`housing`), Vice-Chancellor (`vc`) and Deputy Vice-Chancellor (Academic) (`dvc`), and the documents office (the Registry and Exams and Records officers who work `/credentials/documents`).

**How to read this volume.** Every screen is named by its menu label and page title, with its URL in backticks. Every procedure is numbered. Every feature carries a status where it matters — **IMPLEMENTED**, **PARTIALLY IMPLEMENTED**, **CONFIGURED BUT UNUSED**, **PLACEHOLDER** or **NOT IMPLEMENTED** — and nothing unfinished is presented as finished. Where a screenshot belongs, a marker `> **Screenshot Required:**` names the page, the URL and what the picture must show. The complete office × module matrix is in *04 Role and Permission Matrix*; the screen-by-screen map is in *05 Module Navigation Guide*; end-to-end workflows are in *06 Workflows*; the technical background (environment variables, deployment, jobs) is in *03 Technical Documentation*.

**Demo accounts.** `docs/demo-accounts.md` in the repository lists a demonstration sign-in for every office (`demo.<office>`) and demonstration students and an applicant, created by `bash db/demo.sh`. The password is printed in that file, not here. A live system removes them with "Remove demo data only" on the platform dashboard (§3.11.6).

---

## Table of contents

1. [Administration model](#1-administration-model)
   1.1 [Offices, not roles](#11-offices-not-roles) · 1.2 [Grants, scope and instruments](#12-grants-scope-and-instruments) · 1.3 [The acting office](#13-the-acting-office) · 1.4 [The audit spine and the reason header](#14-the-audit-spine-and-the-reason-header) · 1.5 [Maker–checker where it exists](#15-makerchecker-where-it-exists) · 1.6 [What the Super Administrator can and cannot do](#16-what-the-super-administrator-can-and-cannot-do) · 1.7 [Menus and guards do not always agree](#17-menus-and-guards-do-not-always-agree)
2. [Initial setup guide](#2-initial-setup-guide)
   2.1 [The order of setup](#21-the-order-of-setup) · 2.2 [Bootstrap the first account](#22-bootstrap-the-first-account) · 2.3 [People, sign-ins and offices](#23-people-sign-ins-and-offices) · 2.4 [Academic sessions, semesters, the CURRENT session and unit limits](#24-academic-sessions-semesters-the-current-session-and-unit-limits) · 2.5 [Faculties, departments and programmes](#25-faculties-departments-and-programmes) · 2.6 [Courses, course structures and opening registration](#26-courses-course-structures-and-opening-registration) · 2.7 [Grading policy](#27-grading-policy) · 2.8 [Fee schedules, instalments, clearance scheme and the other fees](#28-fee-schedules-instalments-clearance-scheme-and-the-other-fees) · 2.9 [Payment gateways](#29-payment-gateways) · 2.10 [Mail server, SMS provider and relays](#210-mail-server-sms-provider-and-relays) · 2.11 [The notice pipeline](#211-the-notice-pipeline) · 2.12 [Matriculation number format](#212-matriculation-number-format) · 2.13 [Admission settings and the Post-UTME examination](#213-admission-settings-and-the-post-utme-examination) · 2.14 [Document policies and templates](#214-document-policies-and-templates) · 2.15 [Hostel inventory, window and rules](#215-hostel-inventory-window-and-rules) · 2.16 [Help desk categories, SLA and auto-close](#216-help-desk-categories-sla-and-auto-close) · 2.17 [Clearance units and purposes](#217-clearance-units-and-purposes) · 2.18 [API keys register](#218-api-keys-register) · 2.19 [NDPA register](#219-ndpa-register) · 2.20 [Go-live readiness](#220-go-live-readiness)
3. [Daily administration by office](#3-daily-administration-by-office)
   3.1 [Registry](#31-registry-registrar-and-deputy-registrar-academic-affairs) · 3.2 [Academic Office](#32-academic-office) · 3.3 [Exams and Records](#33-exams-and-records) · 3.4 [Bursary](#34-bursary) · 3.5 [Internal Audit](#35-internal-audit) · 3.6 [Human Resource Management](#36-human-resource-management) · 3.7 [School of Postgraduate Studies](#37-school-of-postgraduate-studies) · 3.8 [College of Health Sciences](#38-college-of-health-sciences) · 3.9 [Housing](#39-housing) · 3.10 [Documents office](#310-documents-office) · 3.11 [ICT Directorate](#311-ict-directorate) · 3.12 [Super Administrator and System Administrator](#312-super-administrator-and-system-administrator) · 3.13 [Vice-Chancellor and DVC (oversight)](#313-vice-chancellor-and-deputy-vice-chancellor-oversight)
4. [Periodic administration](#4-periodic-administration)
5. [Configuration guide](#5-configuration-guide)
6. [Audit trail and compliance](#6-audit-trail-and-compliance)
7. [Reports catalogue for administrators](#7-reports-catalogue-for-administrators)
8. [Administrator troubleshooting](#8-administrator-troubleshooting)
9. [Quick start](#9-quick-start)

---

## 1. Administration model

### 1.1 Offices, not roles

The portal has no "roles" in the usual sense. A person holds **offices**. An office is a row of `ref.office` (34 rows: 32 staff offices plus `applicant` and `student`; `db/verify.sql` refuses a deployment whose register does not hold exactly 34). Each office has a code, a label and a **scope kind** that says what a grant of it is bounded to:

| Scope kind | Meaning | Offices |
|---|---|---|
| `platform` | The whole service | `super`, `admin`, `ict`, `ictagent` |
| `institution` | The whole University | `vc`, `dvc`, `registrar`, `dregistrar`, `academic`, `records`, `bursar`, `audit`, `hrm`, `pgschool`, `pgsecretary`, `extexaminer`, `housing`, `student`, `applicant` |
| `college` | One college | `provost`, `collegesecretary`, `financecontroller` |
| `faculty` | One faculty | `dean`, `facultyofficer`, `facultyexams` |
| `department` | One department | `hod`, `siwes` |
| `programme` | One programme | `exams` |
| `course` | Own courses | `lecturer` |
| `unit` | One administrative unit | `deputyaudit`, `services`, `security`, `library` |
| `level` | One level, 200–600 | `mbbscoordinator` |

Every API endpoint carries a guard that names the offices allowed to call it. The guard is the truth; the menu is a convenience. The full module × office matrix derived from every guard is in *04 Role and Permission Matrix*, and this volume cites it rather than repeating it. No screen edits `ref.office`; offices are added by migration.

### 1.2 Grants, scope and instruments

A person (`iam.person`) is created once. Each office they hold is a **grant** (`iam.office_assignment`) with a `valid_from`, an optional `valid_to`, a scope (`scope_kind` + `scope_id`) and an **instrument** — the letter or minute under which the office is held. A grant without an instrument is refused by the database ("An office is held under a letter or minute; none was given."). A grant is never deleted: it is **ended** with a date and a reason (`iam.end_grant`), and the reason goes on the record.

Scope is not in the sign-in token. It is applied per request by `shared/OfficeScope.java`: a department office (`hod`, `exams`, `siwes`, `lecturer`) is held to its department — the grant's scope, else the person's `lecturer` grant's department, else `hrm.staff_record.home_department`; a faculty office (`dean`, `facultyofficer`) to its faculty. An office that resolves to nothing is bound to the sentinel `__none__` and sees nothing, which is why a Head of Department whose grant carries no department sees "Your Head-of-Department office is not tied to a department yet".

> **Warning:** Scope is enforced only where a controller calls `OfficeScope`. Dossier findings name four surfaces that are **not** office-bound in code: `GET /student/records/{view}` (the Records & Queries tabs take the scope from the URL), `/students/{id}` (any reader office may open any student), the faculty-list query/confirm actions under Matriculation, and the University-wide transfer list at `/transfers`. Administrators should know this when granting reader offices.

### 1.3 The acting office

A person may hold several offices. At sign-in the token carries every live office as an authority; the browser keeps one **acting office** in the readable cookie `moaum_office` and sends it on every request as `X-Active-Office`. The "Signed in as" select at the top of the sidebar changes the acting office; it is a cookie change only, and the API refuses any office the token does not carry ("The office 'x' is not one this token carries").

Two consequences matter to administrators:

- A grant made today takes effect at the person's **next sign-in** (the token is minted with the offices as of sign-in).
- A request with **no** acting office may read but not write: the database refuses the write and the API answers **403 `NO_ACTING_OFFICE`** (§1.4).

The session itself lasts 12 hours (`platform.session.absolute_end`), is refused after an API restart ("The portal was updated. Sign in again." — the *session floor*), and locks after five failed passwords for fifteen minutes.

### 1.4 The audit spine and the reason header

Every state table that is not expressly exempt carries an `AFTER INSERT OR UPDATE OR DELETE` trigger, `audit.record()`, which writes a hash-chained entry naming the **actor**, the **acting office**, the **reason** and the **correlation id** — and which **refuses the write** when the transaction carries no actor and office (SQLSTATE 23514 "unattributed change to schema.table — no audit context on this transaction"). The application places those settings at the start of every transaction from the request's `AuditContext`; `ProblemHandler` turns the refusal into 403 `NO_ACTING_OFFICE` with the remedy "Send X-Active-Office with one of the offices your token carries."

Every write the screens make also sends an **`X-Reason`** header. The reason is stored on the audit entry and, on most administrative screens, is also the text of the success toast ("Fee item stated for 2026/2027: School fees"). Modals that ask "Reason, as it will read in the log" are asking for this text. Exempt tables (credentials, password hashes, gateway keys, mail/SMS secrets, session rows, blobs, the notice outbox's own log) are listed with a written reason in `audit.exemption`; the events *about* them (a key set, a password reset) are on the spine. Section 6 describes the entry, the chain and the screens that read it.

### 1.5 Maker–checker where it exists

The portal enforces four-eyes in specific places, and in two different ways. Where it is **by person** the database compares `moaum.actor_id`, so one person holding several offices still cannot approve their own act. Where it is **by office** the rule is that a different office must act, not necessarily a different person.

| Where | Rule | Enforced by | Status |
|---|---|---|---|
| Bank credits (`/finance/exceptions`) | Proposer ≠ approver | SQL by person (`ck_bc_two_people`) | IMPLEMENTED |
| Refunds (`/finance/refunds`) | Raiser ≠ approver; paid only after approval | SQL by person (`ck_rf_two_people`) | IMPLEMENTED |
| Wallet withdrawals (`/finance/nelfund?tab=withdrawals`) | Approver ≠ payer | SQL by person | IMPLEMENTED |
| Payroll runs (`/payroll`) | Builder ≠ approver | SQL by person | IMPLEMENTED (engine) — see §3.6 for the honest status of payroll |
| Requisitions (`/finance/requisitions`) | Raiser ≠ approver | SQL by person (`ck_rq_two_people`) | IMPLEMENTED |
| Payment vouchers (`/vouchers`) | No person acts twice in the chain (BR-006); each desk signed by its office | SQL by person and by acting office | IMPLEMENTED |
| Results approval chain (`/results/chain`, `/results/approvals`) | The person who took the previous stage may not take the next (BR-006); the office-per-stage map is **UI only** | SQL by person; office map in `Sheets.DESK` only | IMPLEMENTED (person) / PARTIALLY IMPLEMENTED (office) |
| Digital documents release (`/credentials/documents/requests/{id}`) | The officer who produced the document does not release it | SQL by person (V262) | IMPLEMENTED |
| Deferments (`/deferments/{id}`) | Bursary → HOD → Faculty → Academic Office (forwarding) → DVC (final approval), each at its own stage | SQL `people.deferment_office_may` + Java `may()` + bound | IMPLEMENTED (V264) |
| Office grants (`/people`) | None — any of six grantor offices may grant any office, including `super` | — | NOT IMPLEMENTED (no two-person rule) |
| Data reset / remove demo (platform dashboard) | A typed word and a reason; no second approver | SQL | IMPLEMENTED (single officer) |

### 1.6 What the Super Administrator can and cannot do

`super` is a platform office, not a master key. It is named on most guards but **omitted from several**, and where it is omitted the API refuses it regardless of menu or intent. The matrix in *04 Role and Permission Matrix* is authoritative; the list below is what an administrator most often trips over.

**Super Administrator can:** create people, credentials and grants (including granting itself any office); write the academic calendar; create, import, archive and delete structure (with `ict`); configure mail, SMS, gateways and API keys; read the audit trail and the security posture; run matriculation configuration (`MatricFormatController.CONFIG`); act on the CBT question bank; run every hostel desk; act on deferments at any stage (REGISTRY group); confirm PG fees, decide PG applications at every desk and admit; record HR movements, build and approve payroll; post journals; raise and pay vouchers and sign audit desks (`super` bypasses the desk-office check); issue library loans; act as the clinic; reset data.

**Super Administrator cannot** (the guard omits `super`):

| Act | Who may | Guard |
|---|---|---|
| Load, commit or withdraw a JAMB CAPS list | `academic`, `registrar` — and the *acting* office must be one of them | `AdmissionsController.LOADERS`, `CapsIntakeService.requireUploadingOffice` |
| Record decisions, release scores or decisions, seat legacy screening batches | `academic`, `registrar`, `dregistrar` | `ApplicantsController.OFFICE` |
| Edit admission settings | `academic`, `registrar`, `dregistrar` | `AdmissionSettingsController.SECRETARIAT` |
| Write a student's biodata, change status, correct level, run the intake | `academic`, `registrar`, `dregistrar` | `StudentController.WRITERS` |
| Run matriculation or issue a single number | `academic`, `registrar`, `dregistrar` | `MatriculationController.RUNNERS` |
| Approve or return a course registration | `hod` (and `super`) — note `super` **is** allowed here | `HOD_APPROVES` |
| Record the Senate minute that publishes results | `registrar`, `dregistrar` | `ResultsController` line 256 |
| Create or open an examination session | `records`, `academic`, `registrar`, `dregistrar` | `EXAMS` |
| Enter marks on a score sheet | `lecturer`, `exams`, `academic` | `ENTRY` |
| Sign a clearance unit | `academic`, `registrar`, `dregistrar`, `dean`, `hod`, `bursar`, `library`, `services`, `housing` | `ClearanceController.SIGNERS` |
| Run the degree audit or approve the graduation list | audit: `academic`, `registrar`, `dregistrar`, `records`; approve: `registrar`, `dregistrar`, `academic` | `GraduationController` |
| State fee lines, confirm a reference, put the clearance scheme in force | `bursar`, `super` — allowed | `FinanceController.BURSARY` |
| Release, reissue or issue a digital document | `registrar`, `dregistrar`, `academic` | `DocumentsController.SIGNERS` |
| Revoke a digital document | `registrar`, `vc` (also a CHECK constraint on the recorded office) | `REVOKERS`, `ck_revoke_office` |
| Take the College's Professional-examination results as an examiner | College desk offices and College department offices | `CollegeController.EXAMINERS` (super **is** in DESK) |
| Read an applicant's O'Level screening score | `academic` only | `OlevelController.SCORE_OFFICE` |
| Act as a document requester's Registry clearance recorder | `academic`, `registrar`, `dregistrar`, `records` | `ApplicantsController.REGISTRY` |

> **Tip:** When `super` is refused, the answer is a 403 with the office list in the problem body. The remedy is never to grant `super` more power in the database; it is to grant the person the office the act belongs to, under an instrument, from `/people`.

### 1.7 Menus and guards do not always agree

The menus (`frontend/src/lib/menus.ts`) were drawn from the prototype and are not generated from the guards. Known mismatches an administrator will meet:

| Symptom | Cause | Status |
|---|---|---|
| Registrar opens "Audit Trail" and sees a 403 notice | `/api/v1/audit/entries` admits `ict, admin, super, audit, deputyaudit, vc` only | NOT IMPLEMENTED (menu only) |
| Finance Controller (CHS) and PG Secretary open "Fee Setup and Schedule" and the reads fail | `FinanceController.READERS` excludes `financecontroller`, `pgsecretary`, `deputyaudit` | PARTIALLY IMPLEMENTED |
| HOD / Support Services open "Requisitions", Library / Support Services open "Stores", Support Services open "Alumni" and get 403 on the data | those offices are not in the module guards | PARTIALLY IMPLEMENTED |
| Registrar, Deputy Registrar and Director of ICT can write the calendar but have no "Session & Semester Setup" menu item | menu lists `academic` and `super` only; the URL `/calendar` works | PARTIALLY IMPLEMENTED |
| "Verify a Card" (Chief Security Officer's home) has no URL | route id `t/idverify` is not in `Shell.tsx` ROUTES | PLACEHOLDER |
| Menu items "Platform & Integrations", "Setup Console", "Movements" (HR home) open the office's dashboard at `/` | home ids resolve to `/`; the titles come from the prototype | IMPLEMENTED (dashboard) — titles stale |
| Numbered badges in the menu ("7", "12", "!") | fixtures in `menus.ts`; the Shell shows only live counts from `iam/me.waiting` | Not rendered |

---

## 2. Initial setup guide

This section is written in the order a new deployment needs. Every step is one that exists on the portal today. Where the University's configuration is seeded by migration and has no screen, the step says so and names the table so that ICT can change it by a new migration (never by editing an applied one — the migration runner stops the deployment when an applied file's SHA-256 changes).

### 2.1 The order of setup

| # | Step | Screen | Who (guard) | Depends on |
|---|---|---|---|---|
| 1 | Environment and secrets on the API service (`MOAUM_AUTH_HMAC_SECRET` ≥ 32 bytes, `MOAUM_CONFIG_KEY`, `MOAUM_PORTAL_URL`, database URL) | Railway service variables — see *03 Technical Documentation* | ICT | — |
| 2 | Bootstrap the first account | `/login/first` | Whoever holds the HMAC secret | 1 |
| 3 | People, sign-ins, offices | `/people`, `/people/lecturers`, `/people/staff` | Registrar, DR(AA), ICT, admin, super (readers/grantors vary) | 2 |
| 4 | Sessions, semesters, the CURRENT session, unit limits | `/calendar` | academic, registrar, dregistrar, super, ict | 3 |
| 5 | Faculties, departments, programmes | `/structure/faculties`, `/structure/departments`, `/structure/programmes` | `ict` only | 3 |
| 6 | Course structures, department courses, open registration | `/catalogue/upload`, `/catalogue`, `/catalogue/structure` | `ict` (uploads); HOD/academic/Registry (courses) | 4, 5 |
| 7 | Grading policy — seeded; confirm | (none) | ICT by migration | — |
| 8 | Fee schedule, clearance scheme, applicant/PG/transfer fees | `/finance/fees` | Bursar, super | 4, 5 |
| 9 | Payment gateways | `/finance/gateways` | keys: ict, admin, super | 1 |
| 10 | Mail server, SMS gateway | `/platform/mail`, `/platform/sms` | ict, admin, super | 1 (`MOAUM_CONFIG_KEY`) |
| 11 | Matriculation number format | `/matriculation/config` | academic, registrar, dregistrar, super | 5 |
| 12 | Admission settings, load cut-off, O'Level grading, Post-UTME examination | `/admissions/settings`, `/admissions/putme/setup` | academic, registrar, dregistrar | 4, 5, 8 |
| 13 | Document policies and templates | `/credentials/documents/settings` | registrar, dregistrar, academic, super | — |
| 14 | Hostel inventory, window and rules | `/hostel/inventory`, `/hostel/window` | housing, services, registrar, admin, super | 4, 8 |
| 15 | Help desk categories, SLA, auto-close | `/helpdesk/settings` | ict, admin, super | — |
| 16 | Clearance units — seeded; confirm | (none) | ICT by migration | — |
| 17 | API keys register (register only) | `/api-keys` | ict, admin, super | — |
| 18 | NDPA register — seeded activities; log requests | `/governance` | registrar, dregistrar, ict, super | — |
| 19 | Go-live readiness check | `/readiness` | super, ict, admin, registrar, dregistrar, academic, bursar | all |
| 20 | Remove demo data | platform dashboard `/` (ict, super) | super, ict | — |

The repository's `docs/go-live-readiness.md` orders the same work as a checklist; the live equivalent is `/readiness` (§2.20).

### 2.2 Bootstrap the first account

**Status: IMPLEMENTED.** The bootstrap runs once, while `iam.credential` is empty.

```text
/login
 → "First account"
 → Create the first account  (/login/first)
```

1. Open `/login/first`.
2. Fill **Bootstrap secret** — the value of `MOAUM_AUTH_HMAC_SECRET` on the API service ("It is checked, never stored here"). It travels as the header `X-Bootstrap-Secret`.
3. Fill **Surname**, **Given names**, **Staff number** (optional), **Username** ("The staff number or an email address"), **Password** (at least ten characters).
4. Press **Create and sign in**.

Outcome: the person is created and granted four offices under the instrument "Bootstrap of the portal, Directorate of ICT" — `registrar` (institution), `academic` (institution), `ict` (platform), `super` (platform) — the credential is set, and the browser is signed in as `registrar` and taken to `/people`. A second attempt answers `AUTH_BOOTSTRAPPED` ("The portal already has accounts; the first one is made once."); a wrong secret answers `AUTH_BOOTSTRAP_SECRET`.

> **Screenshot Required:** Create the first account — `/login/first` — the six fields and the "Create and sign in" button, with the hint under Bootstrap secret visible.

> **Note:** The bootstrap person holds `registrar` and `academic`. Real office holders should be created next (§2.3) and the bootstrap person's institutional grants ended with a reason once the Registrar and the Academic Officer are on the portal.

### 2.3 People, sign-ins and offices

**Status: IMPLEMENTED.** Screen: Users & Roles — `/people` (menu: super, ict, admin under Administration; dashboard shortcuts `/people?new=person` and `/people?new=grant` for ict, admin, super, registrar, dregistrar).

Guards: readers `registrar, dregistrar, hrm, ict, admin, super, audit`; credentials `registrar, dregistrar, ict, admin, super`; grantors `registrar, dregistrar, vc, super, ict, admin`.

> **Screenshot Required:** Users & roles — `/people` — the four tiles, the "People on the register" table with the State pills and the three action buttons, and the "Staff accounts and the offices they hold" panel.

**2.3.1 Create a person.**

1. Press **+ New person**.
2. **Surname** and **Given names** (required); **Staff number** (optional, unique — the database answers 409 `ALREADY_EXISTS` on a duplicate); **Email** ("Where a password reset and notices are sent"); **Phone** (optional, for SMS).
3. Save → toast "Person created".

**2.3.2 Give a sign-in.** In the person's row press **Create account** (or **Reset password** later).

1. **Username** — the staff number lower-cased is prefilled; an email address is also accepted; at least three characters; unique ("'x' already signs somebody else in.").
2. **First password** — at least ten characters and not containing the username.
3. Save → toast "Account created by the Registry". The credential is flagged `must_change`; at first sign-in the holder is sent to **Your password** (`/account/password`) and must choose a password of ten or more characters. The first password is told to the person out of band; the portal never writes it anywhere.

**2.3.3 Grant an office.** Press **Grant an office** on the row (or **+ Grant an office** in the lower panel).

| Field | Rule |
|---|---|
| Office | From `ref.office`; choosing one presets "Bounded to" from its scope kind |
| Which one | The faculty, department, programme or course code; a unit; a level 200–600 for the MBBS Coordinator; blank for the University or the platform |
| From / To | An acting grant must carry a To date; `valid_to ≥ valid_from` |
| Authority for the grant | Required. Free text, e.g. "Registrar, memo REG/2026/318" |

Outcome: toast "<office> granted under <instrument>"; the grant appears in "Staff accounts and the offices they hold" with Bounded to, Granted by, From and To. The grantor is always the acting person, never a typed name.

Rules the database applies: an `mbbscoordinator` grant must be `scope_kind = level` in 200–600 and the person must already hold a `lecturer` office in a College department ("Grant the lecturer's office in a College department first"); `IAM_NO_SUCH_OFFICE`, `IAM_GRANT_NEEDS_INSTRUMENT`.

**2.3.4 End a grant.** Press **End** on the grant: "Ended with effect from" (today when blank) and "Reason, as it will read in the log" (required). The grant is kept with its `valid_to`; it is never deleted.

**2.3.5 Contact details.** **Contact** on the row sets Email and Phone (`PUT /iam/persons/{id}/contact`). This is the address a password reset goes to; a staff account with no email is emailed only if its username is itself an email.

**2.3.6 Bulk onboarding of teaching staff.** Upload Lecturers — `/people/lecturers` (super, ict, admin). **Status: IMPLEMENTED.** Download the template (columns **PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONUASS**), fill it and upload the `.xlsx`. The file needs PNO, Full Names and Department columns. Each row becomes a person + a sign-in (username and first password both `P<PNO>`, `must_change`) + a `lecturer` office at the home department + an establishment record (`hrm.staff_record`). Rows are sent 25 at a time; the import is idempotent, so re-uploading fills gaps; rows whose department does not exist are reported ("Create these departments first, then re-upload"). The panel below lists teaching staff on record with **Edit** and **Delete selected** (a lecturer who already teaches an offering is kept).

> **Warning:** The lecturer import issues predictable first passwords (`P<PNO>`). Tell each lecturer to sign in and change it promptly; anyone who knows a PNO could sign in first.

**2.3.7 Bulk load of non-academic staff.** Upload Non-Academic Staff — `/people/staff` (registrar, dregistrar, hrm, ict, admin, super). **Status: IMPLEMENTED.** Template columns **PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONTISS**. **Check a File (.xlsx)** runs a dry run (rows read, would be added, already on record, "Not placed, as spelt in the sheet: …" for unit spellings the unit register does not know); then **Load All n Rows** or **Load the n Placed Rows**. No sign-in and no office are issued by this loader; it creates the person and the establishment record only. Unit spellings live in `ref.unit_alias`, added by ICT by migration.

**2.3.8 What is not on the portal.** Ending a *person* (a leaver) from the UI — **NOT IMPLEMENTED**; `iam.person.ended_on` is read by sign-in but no endpoint in the IAM module sets it. Listing or ending another person's sessions — **NOT IMPLEMENTED** (only the caller's own sessions have endpoints, and no screen calls them). Keycloak single sign-on with MFA — **IMPLEMENTED in code, NOT DEPLOYED**; it appears on the sign-in card only when `MOAUM_SSO_ISSUER`, `MOAUM_SSO_CLIENT_ID` and `MOAUM_SSO_CLIENT_SECRET` are set (`docs/keycloak.md`).

### 2.4 Academic sessions, semesters, the CURRENT session and unit limits

**Status: IMPLEMENTED.** Screen: Session & Semester Setup — `/calendar?session=YYYY/YYYY` (menu: academic, super; writers by guard also registrar, dregistrar, ict, reachable by URL). Reads are open to any signed-in person.

```text
Academic
 → Session & Semester Setup   (/calendar)
```

> **Screenshot Required:** Session & semester setup — `/calendar` — the four tiles, the "Academic sessions" table with State pills, the "Semesters of <session>" table and the "Levels and unit limits" panel.

**2.4.1 Create a session.** Press **+ New session**.

| Field | Rule |
|---|---|
| Session | `YYYY/YYYY` (client check "The session has to be named as the University names one"); locked on edit |
| Opens / Closes | `ends_on > starts_on`; no two sessions may overlap (`ex_session_no_overlap`) |
| Semesters | "2" or "3 (Summer semester)" |
| Senate minute | Required before the state may be Current |
| State | Planned / Current / Closed |

Rules: exactly one session is CURRENT (`uq_session_one_current`); CURRENT requires a non-blank Senate minute (`CAL_MINUTE_REQUIRED` — "A session stays planned until its Senate minute is recorded against it, and none was given."); saving with State = Current calls make-current and closes whatever else was current in the same transaction. "End this session" in the modal footer asks a reason and closes the session.

**2.4.2 Semester windows.** Press **+ New semester** or **Edit windows** on a semester.

| Field | What it does |
|---|---|
| Semester | First / Second / (Third) — number 1–3 |
| State | Not yet open / Open / Closed |
| Lectures from / to | Informational dates (order checked) |
| Registration opens | "Makes the course form writable for cleared students." |
| Registration closes | "Freezes the register — and the register is what every score sheet is generated over." |
| Late registration closes | The add/drop window and the date after which a held script lapses |
| Examinations from / to | "Locks the examination roll." |
| Score sheets due | "What the escalation clock counts from." |
| Result query window | Free text (the actual window is seven calendar days from publication, fixed in SQL) |

> **Note:** Setting the examination dates here does **not** open an examination session; that is done under Examination Sessions (`/examinations/sessions`, §3.3.1). The Go-Live Readiness gate "A semester is open" reads the semester State on this screen.

**2.4.3 Levels and unit limits.** Press **+ New level** or **Edit** on a level: Level (the select offers 100–600; the database also holds 700–900, editable only through an existing row's Edit), Applies to (All programmes / MBBS, LL.B and other five-year programmes / One programme), Minimum and Maximum units per semester, Maximum units on probation (blank = probation pronounced but no unit cut), Carryover counts (Yes/No), Senate minute. Seeded rows: 100–400 "All programmes" 18–24; 500 "MBBS, LL.B and other five-year programmes" 18–24; 600 "MBBS" 18–24; 700 PGD 9–48; 800 Master's 6–48; 900 MPhil/Doctoral 0–48; `probation_max_units` is NULL for every row, so the probation unit ceiling is **CONFIGURED BUT UNUSED** until a value is set.

**2.4.4 Roll-over and enrol-all.** At the top of the screen: **Roll into <session>** (confirm) runs `people.roll_over_session` — promotes continuing students one level into the new session (opened as PLANNED if new), needs the word ROLLOVER and a reason, and is idempotent; **Enrol all into <session>** backfills `people.enrolment` rows for the loaded cohort. Both are periodic acts (§4.1).

### 2.5 Faculties, departments and programmes

**Status: IMPLEMENTED — Director of ICT only.** Since commit `8c2b6fa` the API guard `UPLOADERS` names `ict` alone for creating, importing, editing, archiving and deleting faculties, departments and programmes, and the three screens act for that office only ("This desk is for the Directorate of ICT…" otherwise). Menu (ict, Academic group): Upload or Create Faculties `/structure/faculties`, Upload or Create Departments `/structure/departments`, Upload or Create Programmes `/structure/programmes`.

| Screen | Form fields | Import file (`.xlsx`; departments also `.csv`) | Delete rule | Export serial |
|---|---|---|---|---|
| Faculties | Code (fixed on edit), Name | Code, Name | Only when no department or programme hangs on it | FAC |
| Departments | Code, Name, Faculty (code or name) | Code, Name, Faculty | Only when no programme and no course | DEP |
| Programmes | Code `^C[0-9]{5}$`, Name, Faculty, Department (optional; blank = the faculty), Category UNDER GRADUATE / POST GRADUATE, Minimum score | same columns | Only if nothing hangs on it; **Archive/Restore** keeps the code | PRG |

Each screen has **Download template**, **Upload … (.xlsx)** (reporting saved / bad_code / no_faculty / rows with no name), a table with edit and delete icons, and **Download Excel** / **Download PDF** (branded, S/N first, names A–Z).

> **Screenshot Required:** Upload or Create Programmes — `/structure/programmes` — the add form, the upload button and the table with the archived pill and Archive/Restore actions.

> **Note:** The programme code is JAMB's course code (`C` + five digits). The matriculation number's faculty segment, programme code and series are configured separately on `/matriculation/config` (§2.12), and a new programme carries **no** matriculation programme code until the Registry gives it one.

### 2.6 Courses, course structures and opening registration

Three screens share this work. Only the first is ICT's.

**2.6.1 Upload course structure — `/catalogue/upload` (ict).** **Status: IMPLEMENTED.**

1. Choose the **Programme** (searchable) and the **Curriculum** (CCMAS — MOAU cohorts / CCMAS — BSU cohort / BMAS / CCMAS any cohort).
2. **Download template** — columns **Course Code, Course Title, Units, Status, Level, Semester, Lecture Hours, Practical Hours**. A workbook may also carry `programme_code` and `course_category` / `curriculum` columns to load many programmes at once. A CCMAS `.docx` is also accepted and is parsed by its headings ("100 Level", "First Semester") and tables.
3. Choose the file; the preview shows Courses read / Levels / With a code the rule rejects; programmes not on the register are held back and listed ("Download the list").
4. Press **Load N courses** — one import per programme + curriculum group.

As implemented (`catalogue.import_courses_rows`): programme resolved by code or name ("no programme is coded or named X"); the course code is normalised (the table CHECK is wider than the create form's `ABC 123` rule, so `BSU-SOC-101`-style codes import); units capped at 12; level defaults 100 (only 100–600 kept); semester defaults 1; Status letter C/R/E/G → kind Core/Required/Elective/GST; the course is upserted (an existing LIVE/ENDED state is kept; BOARD/SENATE is lifted to LIVE) together with its structure row (`catalogue.course_offer`); each row is in a savepoint so one bad row is counted, not fatal.

Also on this screen: **Open course registration for a session** (Session `YYYY/YYYY`, Semester) — creates an offering for every non-ended course of that semester bound to some programme (`registration.open_course_registration`; "no academic session % on the calendar — open the session first"; idempotent); **All courses — Excel/PDF** (serial CAT: Faculty, Programme Code, Programme, Level, Semester, Course Code, Title, Units, Kind, Basis, Curriculum); **View loaded courses**.

> **Screenshot Required:** Upload course structure — `/catalogue/upload` — programme and curriculum selects, the preview panel after a file is chosen, and the "Open course registration for a session" panel.

> **Note:** The screen's explanatory note still says "and HODs" may upload; only `ict` can. The opening of registration is also allowed to `super, admin, hod, dean, academic, registrar, dregistrar` by guard, but the only button is on this ICT screen.

**2.6.2 Department courses — `/catalogue?dept=` (HOD; also dean, academic, dregistrar, registrar, admin, super).** **Status: IMPLEMENTED.** **+ New course** (Code "Three letters, a space, three digits — e.g. CSC 311", Units 0–12, Title, Level 100–600, Semester, Kind Core Courses/Required/Elective/GST) creates a course in state **BOARD** ("… created — at the Faculty Board"); **Make live** lifts it to LIVE (only `academic, registrar, dregistrar, super` may make a course LIVE through the direct upsert path; the department's own **Make N Live** button uses `courses/live-all`); **End** / **Restore**; the **Curriculum** select per course (shared / CCMAS / BMAS) and the **CA / Exam** split (`ca_max`, default 40 — "CA 40 / Exam 60", "CA 30 / Exam 70" as bulk buttons); a **Duplicate courses** panel with **End N duplicate courses**. A course not bound to any programme shows the red pill "Not bound to any programme — no student sees it at registration". The SENATE state exists in the CHECK but nothing sets it — **CONFIGURED BUT UNUSED**.

**2.6.3 Programme structure — `/catalogue/structure?prog=`.** **Status: IMPLEMENTED.** **Bind a course into the structure**: course search (≥ 2 characters, University-wide), Level, Basis Core/Elective/Borrowed/GST (defaults to Borrowed when another department owns it), Track ("Every track" or one of `policy.curriculum_track`: BMAS, CCMAS_BSU, CCMAS_MOAU). Per level the panel shows unit totals against `policy.level_limit` with "core alone exceeds the N-unit maximum" / "under the N-unit minimum" warnings. **Remove** is refused while a student of that programme and level is registered on the course this session (`CAT_BOUND_IN_USE`).

> **Note:** The **industrial-training flag** on a course (which makes a semester a SIWES semester) is set only by migrations V155–V157; no screen or upload column writes `catalogue.course.industrial_training` — **NOT IMPLEMENTED** as an administrative act. A new SIWES course needs ICT.

### 2.7 Grading policy

**Status: IMPLEMENTED as seeded rows; there is no administrative screen.** The grading scheme, the classification bands and the effective-dated `policy.version` rows are inserted by migration and read by every result, GPA and class computation. No controller writes `policy.grade_band`, `policy.classification_band` or `policy.version`.

| Table | Seeded values |
|---|---|
| `policy.version` | grading UNIVERSITY from 2015-10-01, instrument `SEN/2015/44`; classification UNIVERSITY from 2015-10-01, `SEN/2015/44`; clearance (demo) from 2026-09-25, `BUR/DEMO/1` |
| `policy.grade_band` | A 70–100 = 5.00; B 60–69 = 4.00; C 50–59 = 3.00; D 45–49 = 2.00; E 40–44 = 1.00; F 0–39 = 0.00 |
| `policy.classification_band` | First Class Honours 4.50–5.00; Second Class (Upper) 3.50–4.49; Second Class (Lower) 2.40–3.49; Third Class 1.50–2.39; Pass 1.00–1.49 — **no band below 1.00**, so the class of standing is blank ("—") for a CGPA under 1.0 |
| Grace mark | A raw total exactly one mark below the lowest passing band (39) becomes 40 (`assessment.grace_total`) |

Two honest caveats: grades are computed under the scheme in force at `current_date`, not at the publication date (only one scheme is seeded, so the difference is moot today); and the student's Semester Results PDF prints a hard-coded grading key rather than reading the table. A change of scheme is a new migration that inserts a new `policy.version` and bands with a later validity range.

### 2.8 Fee schedules, instalments, clearance scheme and the other fees

**Status: IMPLEMENTED.** Screen: Fee Setup and Schedule — `/finance/fees?session=` (menu: bursar; also admin as "Fee Schedules", financecontroller and pgsecretary — see §1.7 for their read failure). Acting: `bursar` or `super`; every other office reads.

```text
Finance
 → Fee Setup and Schedule   (/finance/fees)
```

> **Screenshot Required:** Fee Setup and Schedule — `/finance/fees` — the four tiles, the clearance-scheme note, "The charges for <session>" table with filters, and the applicant / postgraduate / transfer fee panels lower down.

**2.8.1 How a charge is computed.** A student is never charged a typed figure. `finance.charges(student, session)` sums every live schedule line whose filters are blank or match the student: level (ignored for a spillover student), entry mode, faculty of the programme, programme, fee group (`ref.fee_group`: UG, PG, GST, EPS by programme category), indigene (state of origin against `finance.fee_setting.home_state`, default Benue), spillover (a student past the programme's final level and not GRADUATED), and semester (a line tagged semester n counts once semester n is OPEN on the calendar — charges accumulate as semesters open; with no OPEN semester everything up to semester 3 applies). The position (`finance.position`) gives due, paid (confirmed references whose purpose begins "School fees"), balance, instalments paid (2 when settled, 1 when at least half is paid), `paid_in_full` and arrears (any earlier session with a live schedule whose charges exceed its payments). Registration for a semester needs the fees up to and including that semester paid in full (`finance.semester_cleared`).

**2.8.2 State a fee line.** Press **Add an item**.

| Field | Options / rule |
|---|---|
| Payment item | One of `ref.fee_item` (SCHOOL_FEES, ACCEPTANCE, REGISTRATION, DEVELOPMENT, LIBRARY, ICT, MEDICAL, SPORTS, EXAMINATION, LABORATORY, HOSTEL, GST, EPS, POST_UTME, ID_CARD, CONVOCATION, READMISSION) or "Other (type a name)…" |
| Amount | Naira; required; ≥ 0 |
| Session | Which session the charge is for |
| Semester | Whole session / First / Second (the modal has no Third; the filter does) |
| Programme group | Every group / UG / PG / GST / EPS |
| Level | Every level / 100–600 / 700 PGD / 800 Master's / 900 Doctoral |
| Entry mode | Every mode / UTME / DIRECT_ENTRY / TRANSFER / POSTGRADUATE |
| Faculty, Programmes | Choosing a faculty lists its programmes as checkboxes; one line is stated per ticked programme |

**State the item** posts one line per ticked programme (X-Reason "Fee item stated for <session>: <item> · <code>"). **Edit** keeps only the first ticked programme. **End** soft-ends a line at once (no confirmation prompt). "Clear the <session> schedule" ends every line for the session after a typed confirmation.

**2.8.3 Upload the approved fees structure** (Bursar only). "Council's approved table, in one upload." Two shapes are read in the browser: the faculty × level cross-tab (a block per faculty with 1st and 2nd Semester rows, a column per level split Indigene / Non-indigene; a band like "100/200DE" means 100 Level plus 200 Level Direct Entry; a "spill" column gives spillover lines) or the flat table with columns **Faculty, Level, Entry mode, Semester, Indigene, Amount**. Accepts `.xlsx` or `.csv`. **Uploading replaces the whole structure for the session** (every live line is ended first). Result: "N fee lines loaded across M faculties[ · k rows had a faculty name that did not match one on the register]".

**2.8.4 Put the clearance scheme in force.** Until a scheme is in force, **no payment releases anything** and every gate that asks fails closed ("no clearance scheme in force for UNIVERSITY on <date> — D-Q4 is unanswered"). Press **Put the recommended scheme in force**: Instrument (required, e.g. `BUR/2026/04`) and From (blank = today). The recommended scheme: the first instalment (half the session charge) opens REGISTRATION, ID_CARD and LIBRARY; payment in full opens EXAMINATION, RESULTS, TRANSCRIPT and CONVOCATION; HOSTEL is never gated; arrears block everything. Two schemes may not overlap in time. Only this recommended scheme can be put in force from the screen; a different rule set would be a migration. The local audit database carries a demo scheme `BUR/DEMO/1` from 2026-09-25.

**2.8.5 Applicant · Post-UTME fees** (per session). Post-UTME screening fee, Portal and payment charge, Acceptance fee, Admission checking fee → **State the applicant fees** (`PUT /admissions/sessions/{s}/{y}/applicant-fees`; guard `academic, registrar, dregistrar, bursar, ict, admin, super`). Defaults when unstated: 2,000 / 300 / 25,000 / 0. There is no success toast; the page refreshes.

**2.8.6 Postgraduate · application & acceptance fees** (per session). PG application fee, PG acceptance fee, PG checking fee → **State the postgraduate fees** (`PUT /pg/sessions/{s}/{y}/fees`; guard `bursar, pgsecretary, pgschool, super`). Defaults: 20,000 / 50,000 / 3,000. No toast and no refresh on save.

**2.8.7 Inter-departmental transfer · processing fee.** **Set the transfer fee** (`PUT /finance/transfer-fee`). There is no default: until it is set a student can apply to transfer but cannot pay, so no transfer can proceed.

**2.8.8 Hostel fee.** The accommodation fee per session is stated on the hostel window (`/hostel/window`, §2.15), not here.

**2.8.9 What is not configurable here.** `ref.fee_group`, `ref.fee_item`, `finance.fee_setting.home_state` and the chart of accounts (`finance.gl_account`, 33 seeded accounts) have no screen.

### 2.9 Payment gateways

**Status: IMPLEMENTED** (Paystack and Flutterwave are covered by `PaymentsIT`; the Quickteller Business hosted page and requery are implemented but **unverified against a live merchant account**; the PayDirect collections import is implemented, its query API endpoint is unconfirmed). Screen: Payment Gateways — `/finance/gateways` (menu: bursar, ict, admin). Monitoring, testing and verifying: `bursar, ict, admin, super`. **Setting keys: `ict`, `admin`, `super` only.**

```text
Finance
 → Payment Gateways   (/finance/gateways)
```

> **Screenshot Required:** Payment gateways — `/finance/gateways` — the "Configured gateways" table with Mode and Status pills and the webhook addresses, and the "Configure the keys" cards showing "Live key set / Test key set / No dashboard key" pills.

**2.9.1 Set a key.** In "Configure the keys":

- **Paystack**: paste the **Secret key** (`sk_test_…` or `sk_live_…`) → **Set the key**. Mode (Test/Live) is read from the key's prefix.
- **Flutterwave**: **Secret key** (`FLWSECK_TEST-…` or `FLWSECK-…`) and **Webhook secret hash** ("The same value you set on the Flutterwave webhook page"). Without the hash the status reads "Secret set, hash missing — webhooks refused".
- **Quickteller Business (Interswitch)**: Client ID, Client secret, Merchant code, Pay item ID and the **Sandbox (test)** checkbox → **Set the configuration**. The four values are stored together as one encrypted document.
- **PayDirect query API** (optional): Client ID, Client secret, Sandbox → **Set the credentials**. Needed only for the automatic poll; the collections import works without it.

Each key is encrypted at rest with `MOAUM_CONFIG_KEY` (falling back to `MOAUM_AUTH_HMAC_SECRET`), used in preference to the service variables `MOAUM_PAYSTACK_SECRET`, `MOAUM_FLUTTERWAVE_SECRET`, `MOAUM_FLUTTERWAVE_HASH`, and **never displayed again** — the screen shows only the mode, the last four characters, when and by whom it was set. **Clear** turns the gateway off unless a service variable is set. Without a config key the save answers "The portal has no passphrase to encrypt a gateway key with."

**2.9.2 Point the gateway's webhook at the portal.** The "Configured gateways" table prints the webhook address per gateway (the portal URL with `moaum-portal` replaced by `moaum-api` plus the webhook path). Paystack: Settings → API Keys & Webhooks; every event is signed with the secret (`x-paystack-signature`, HMAC-SHA512). Flutterwave: Settings → Webhooks, with the secret hash. Quickteller's notification is never trusted; the reference is re-queried.

**2.9.3 PayDirect billers.** The "Quickteller PayDirect" panel lists the two billers, routed by College: MAIN (seeded code 04255101) for every department and CHS (seeded 04263001) for the College of Health Sciences. Edit Biller code, Name and Pay link and **Save** (`bursar, ict, admin, super`). A student who pays by PayDirect is given a PRN (the portal reference), and the Bursary later imports the day's collections report here (§3.4.6).

**2.9.4 Test the gateway.** "Open a test checkout" for a demo student (the field is prefilled with the demo number `MOAUM/MTC/24/9903`) and ₦100 on a wired gateway; the purpose "Gateway test" counts for nothing against fees. "Verify with the gateway" asks about any portal reference; "Run the sweep now" runs the reconciliation sweep by hand.

**2.9.5 How settlement works.** A callback is a hint. The portal verifies the signature, re-reads the amount, and confirms only when the paid amount is at least what the reference asks; a short payment is logged (`SHORT_PAID`) and left open; an unknown reference is logged (`UNKNOWN_REFERENCE`); a bad signature is discarded and logged. Every ten minutes (`moaum.payments.sweep-every-ms`, default 600 000) the sweep asks the gateways about every checkout opened in the last three days, older than five minutes, with fewer than twelve checks. The student's "check again" runs the same verification on demand. A settlement confirms through `finance.confirm_payment` and sends the receipt by email and SMS.

### 2.10 Mail server, SMS provider and relays

**Status: IMPLEMENTED** (delivery itself depends on what is configured). Keepers: `ict`, `admin`, `super`.

```text
Administration
 → Mail Server    (/platform/mail)
 → SMS Gateway    (/platform/sms)
```

**2.10.1 Mail Server — `/platform/mail`.** Three panels — SMTP, IMAP, POP — each with Server, Port (1–65535) and Encryption (STARTTLS / SSL / NONE; defaults `smtp.office365.com` 587 STARTTLS, `outlook.office365.com` 993 SSL, 995 SSL), and "The account": Username (the full email address), From address, Password or app password (pasted once; the pill reads "Password set" / "No password"). **Save the settings**; **Clear the password**. The password is encrypted with `MOAUM_CONFIG_KEY` (or the HMAC secret) and decrypted only inside the dispatcher; if neither key is set the screen shows the red note "No passphrase to encrypt the password with" and refuses the save (`MAIL_NO_CONFIG_KEY`). Only the SMTP part is used for sending; IMAP/POP are stored.

> **Note:** The footer of this screen still says SMTP sending "arrives with the mail transport … once the SMTP transport is enabled on the API". That text is stale: the dispatcher already sends through SMTP when the settings are complete.

> **Screenshot Required:** Mail Server — `/platform/mail` — the SMTP panel and "The account" panel with the "Password set" pill.

**2.10.2 SMS Gateway — `/platform/sms`.** Username, Sender ID (≤ 11 characters), API key (pasted once), checkbox "Send SMS notices through eBulkSMS" → **Save the settings**; **Clear the API key**. The provider is fixed (`EBULKSMS`); numbers are normalised to `234…` at send time.

**2.10.3 HTTP relays (alternative to SMTP/eBulkSMS).** If the University runs its own mail or SMS relay, set on the API service `MOAUM_NOTICES_EMAIL_URL`, `MOAUM_NOTICES_SMS_URL`, `MOAUM_NOTICES_TOKEN`, `MOAUM_NOTICES_EMAIL_FORMAT` (generic | resend), `MOAUM_NOTICES_SMS_FORMAT` (generic | termii), `MOAUM_NOTICES_EMAIL_FROM`, `MOAUM_NOTICES_SMS_FROM`. Email goes by SMTP when the Mail settings are complete, else by the email relay; SMS by eBulkSMS when enabled, else by the SMS relay.

### 2.11 The notice pipeline

**Status: IMPLEMENTED.** Every module writes what it intends to send into one transactional outbox, `platform.notice`, through `platform.queue_notice(channel, recipient, subject, body, about_kind, about_id)` inside its own transaction (a blank recipient queues nothing). The dispatcher (`NoticeDispatcher`) runs every `MOAUM_NOTICES_EVERY_MS` (default 60 000 ms, first run after 15 s), takes up to 50 QUEUED rows with fewer than five attempts, oldest first, and sends each. Success → SENT with `sent_at` and the provider reference; failure → attempts + 1 and the error; the fifth failure → FAILED. If neither SMTP nor eBulkSMS nor a relay is configured the dispatcher logs once and returns, and **notices stay QUEUED**. Attachments (kept returns) travel in `platform.notice_attachment` (≤ 15 MB).

Screen: Notifications / Notification Channels — `/notices` (read: ict, admin, super, registrar; requeue: ict, admin, super). Tiles Waiting / Sent today / Failed / Sent, all time; "Providers"; "The outbox" (When, To, Notice, Channel, Attempts, State Sent / Failed + error + **Requeue** / Queued); **Put all n failed back in the queue** (resets attempts to 0 for FAILED rows only).

> **Warning:** The "Providers" panel on `/notices` reflects only the HTTP relay variables. It can read "No provider is wired, so nothing is being sent" while SMTP or eBulkSMS delivery is in fact working — **PARTIALLY IMPLEMENTED** indicator. Judge delivery by the Sent/Failed counts and the platform dashboard's outbox panel, not by that sentence.

Recipients read the same rows: staff at My notifications (`/me/notices`), students on their Notifications page, applicants on their overview. Which events send what is catalogued per module in *05 Module Navigation Guide*; the notable **silences** are course-registration approval/return, results publication, transfers, biodata decisions, status changes, clearance holds, HR decisions, and every expenditure and GL act — none of these queue a notice.

### 2.12 Matriculation number format

**Status: IMPLEMENTED (V263).** Screen: Matriculation Number Format — `/matriculation/config` (menu: academic, dregistrar, registrar; configuration guard `academic, registrar, dregistrar, super`; readers include dvc, vc, records, dean, hod, facultyofficer, ict, admin).

```text
Students
 → Matriculation
 → Matriculation Number Format   (/matriculation/config)
```

> **Screenshot Required:** Matriculation number format — `/matriculation/config` — the PageHead with the live pattern, the warning about programmes set to carry a code with none, the four tiles, "The format rule" panel, and the Series and Programmes tables.

**2.12.1 The rule.** The number is built by `people.matric_components` from the single row `people.matric_format`:

```text
{UNIVERSITY}/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}
 MOAU      / AD      / ACC       / 26 / 13568        → MOAU/AD/ACC/26/13568
 MOAU      / MBBS    / (none)    / 26 / 6096         → MOAU/MBBS/26/6096
 MOAU      / PHRM    / (none)    / 26 / 200          → MOAU/PHRM/26/200
```

- **University code** — default `MOAU`, letters only (`^[A-Z]{2,6}$`).
- **Faculty segment** — when the rule's Faculty code box is on: the programme's own faculty segment if it has one, else the faculty's matric code, else the faculty code.
- **Programme segment** — when the rule's Programme code box is on **and** the programme is configured to carry a code: the programme's code. A programme configured to carry a code but given none is a **problem** and the run refuses.
- **Year** — the last two digits of the student's entry session.
- **Sequence** — the next number in the series the programme, else the faculty, else `GENERAL` belongs to; padded to `sequence_digits` (0–8; 0 = no padding).
- Segments are joined by the separator (`/` or `-`) and empty segments are removed — there is never an empty `//`.

"The format rule" panel: University code, Separator, Sequence padding, checkboxes Faculty code / Programme code / Year of entry / Sequence (always on), Note → **Save the rule**, with live samples.

**2.12.2 Series.** A series is a named counter. `Last number issued` only ever moves forward ("Series X has issued up to N; it does not go back." — `MATRIC_SERIES_BACK`); a series may be made inactive, and an inactive series is a problem for every programme on it. Seeded by V263 (values on the audited database have advanced by demo issues):

| Series code | Name (seed) | Last issued (seed) | Belongs to |
|---|---|---|---|
| ADMIN | Administration and Management series | 13556 | Faculty of Management Sciences (segment AD) |
| COLLEGE | College series — Basic and Applied Medical Sciences, and Medicine and Surgery | 6093 | Faculty of Basic and Applied Medical Sciences (segment BM); MBBS (own segment MBBS) |
| PHARMACY | Pharmacy series | 198 | Faculty of Pharmaceutical Sciences (segment PHRM) |
| ARCHITECTURE | Architecture series | 76 | Architecture (segment AC) |
| GENERAL | General series — every other faculty | 85631 | AR, CM (segment CS), ED, ES, LW (segment LAW), SC, SS, TI (segment TS); Biochemistry (own segment SC) |

**Add a series** / **Edit**: Code (`[A-Z][A-Z0-9_]{1,20}`), Name, Last number issued, Note, Active.

**2.12.3 Faculties.** Each faculty row: Segment (`[A-Z0-9]{2,6}`) and Series. Seeded: MS→AD/ADMIN, BAMS→BM/COLLEGE, PS→PHRM/PHARMACY, CM→CS/GENERAL, LW→LAW/GENERAL, TI→TS/GENERAL, AC→AC/ARCHITECTURE, and AR, ED, ES, SC, SS on GENERAL with their own codes.

**2.12.4 Programmes.** Filter by faculty, search; each row shows Faculty segment, Programme code, Carries code, Series, and **Next number** or a problem pill. **Edit**: "This programme carries a programme code in the number", Programme code, Own faculty segment, Series. Seeded: 62 undergraduate programmes carry a code (e.g. ACC, CMP, MTH); Medicine and Surgery (C00061) carries **no** code but its own faculty segment `MBBS`; Doctor of Pharmacy, LL.B and every postgraduate programme carry none; 21 undergraduate programmes carry none "until the Registry gives it one"; Biochemistry (C64548) has its own segment SC on GENERAL.

**2.12.5 The rules to respect.**

1. **Never invent a code.** A programme the schedule does not name carries no programme segment until the Registry configures one. The run refuses a programme set to carry a code with none ("Programme % is configured to carry a code but has none; give it one or set it to carry none") — and the whole run rolls back.
2. **A series never goes back.** A number already on the register or in the history is passed over, never reused ("the sequence is spent, never reused"); after 1,000 tries the run reports "no free number in series %".
3. **Numbers are permanent.** `people.matric_is_immutable` refuses any change to `matric_no` ("the matriculation number % is permanent and is not changed"); `people.matric_history` is written once and refuses UPDATE unless the maintenance switch is on. There is no correction screen by design.
4. The sign-in door accepts the new form beside the old (`MOAUM/DEPT/YY/NNNN`); the hint on the sign-in card that names "who the number looks like" is stale for the new form but routing is correct.

Exports: **Excel** / **PDF** of the configuration (serial MAT; S/N first; columns Faculty, Programme, Programme Ref, Faculty Segment, Programme Code, Carries Code, Series, Next Number, Problem). "Numbers issued most recently" lists the last 25 history rows; the history search endpoint (`GET /matriculation/config/history?q=`) and the per-student preview (`/preview/{studentId}`) exist but have **no screen** — PARTIALLY IMPLEMENTED.

### 2.13 Admission settings and the Post-UTME examination

**Status: IMPLEMENTED.** Screen: Admission Settings — `/admissions/settings?session=` (menu: academic, badge "!" when the next PLANNED session has no in-force policy). Writers: `academic, registrar, dregistrar`; readers add dean, hod, dvc, vc, records, ict, admin, super.

```text
Admissions
 → Admission Settings   (/admissions/settings)
```

> **Screenshot Required:** Admission settings — `/admissions/settings` — the in-force / DRAFT note, "The four selection criteria", "The ratios and the caps", the programme table, and the "Put the settings in force" panel with the Central Admissions Committee minute field.

**2.13.1 Create the session's settings.** With none: **Begin from <previous>** (copies) or type the NUC quota and **Create the <session> settings** (defaults: weighting UTME 70 / Post-UTME 30, UTME:DE 80:20, Science:Arts 60:40, ELG cap 50, department share 80, index 6/2, MPF and screening required).

**2.13.2 The panels.**

| Panel | Fields / rule |
|---|---|
| The aggregate score | UTME weight and Post-UTME weight — must total 100 (`ADM_WEIGHTS`) |
| The four selection criteria | National Merit, State Merit, Equality of LGA, Locality — percentages must total 100 (guidelines 10 / 35 / 30 / 25); `policy_findings` names "The selection criteria do not total 100%" |
| The ratios and the caps | UTME:DE, Science:Arts, ELG ceiling, department share |
| Catchment local governments | Textarea of LGAs |
| NUC approved quota | Positive integer; programme quotas should total it ("The programme quotas do not total the NUC approved quota") |
| Faculty UTME:Direct-Entry split | Per faculty; Education is 60:40, every other faculty the session's ratio (`ADM_RATIO_SUM`) |
| Every programme the University runs | Cut-off, O'Level requirement, UTME subjects, Direct Entry, Places; per-row edit, close/reopen; the rule modal takes Cut-off of its own (1–400), Programme quota, requirement texts, Relevant O'Level subjects, Required UTME subjects ("comma = all, '/' = any-one-of, 'N of A/B/C'"), Direct Entry subjects, DE passes required, Compulsory-credit exceptions |
| Findings | Everything that blocks putting the settings in force |
| Put the settings in force | **Central Admissions Committee minute** (e.g. `CAC/2026/07`), refused while any finding stands |

Once IN_FORCE the weights, ratios, criteria, cut-offs and subject rules are frozen (`ADM_SETTINGS_IN_FORCE` "The … settings are in force under … and are not edited."); quotas, catchment, relevant O'Level subjects, UTME/DE subject sets and programme closures remain editable. `SUPERSEDED` is in the CHECK but never set.

**2.13.3 General UTME cut-off for loading the JAMB lists** (`LoadCutoff.tsx`, 0–400). "No UTME list can be loaded until this is stated." Rows under it are read but not loaded (`caps_row_excluded`, BELOW_CUTOFF).

**2.13.4 O'Level grading for the screening score.** Points per grade A1–F9 (defaults A1 6 … C6 1, D7–F9 0), subjects counted (default 5), one-sitting bonus (10) and two-sitting bonus (6), and **Programmes screened by examination** (the "index" programmes whose Post-UTME score comes from the CBT/uploaded score rather than the O'Level computation) — add/remove. Compulsory credits default to English and Mathematics; a programme may waive one through an allowance.

**2.13.5 Post-UTME CBT examination — `/admissions/putme/setup`** (from Post-UTME CBT Schedule `/admissions/putme`; OFFICE `academic, registrar, dregistrar, super`). **Status: IMPLEMENTED.**

| Panel | Fields / rule |
|---|---|
| The examination | Name (required), First day, Last day, Report before (minutes, 0–240; default 30), Sitting (minutes, 10–600; default 120), Buffer between batches (default 30), Registration deadline, Batching strategy (PROGRAMME / DEPARTMENT / FACULTY / ALPHABETICAL / APPLICATION_NO / BALANCED), Keep a programme together, Enquiries contact, Examination instructions, Venue instructions |
| CBT centres and rooms | **Add a centre**: Code `^[A-Z0-9-]{2,12}$`, Name, Location, Address, Contact person, Contact phone or email, State; rooms: Code, Name, Capacity 1–2000, Workstations ≤ capacity, State (workstations "Computer 001…" are numbered on save; a toggle grid marks a workstation operational or not) |
| Centres this examination uses, Examination days, Time slots | Days: add/remove dates; Slots: Code, From, To (auto-suggested from duration + buffer; "Slot X ends before it starts." refused) |
| Places | days × slots × rooms; capacity = operational workstations else room capacity |

Places cannot be changed under a published schedule. Centres and rooms are University-wide and reused across sessions. `keep_programme`, `registration_deadline` and `kind` are saved but **not read** by generation or eligibility — CONFIGURED BUT UNUSED. Running the cycle is §3.2.2.

**2.13.6 Eligibility rules and the Programme Eligibility register (V266).** **Status: IMPLEMENTED.** The automatic admission course suggestion engine reads every submitted applicant against the settings above and nothing else — no requirement is hard-coded and no equivalence is invented.

*The rules.* The per-programme rule modal carries three more fields, editable whether the settings are DRAFT or in force: **Required O'Level subjects for eligibility (checked)** in the shared grammar (comma = all required; `A/B` = any one of; `N of A/B/C` = any N of a set), a **Minimum grade** for those subjects (default C6), and **Additional screening** (free text — an aptitude test, an interview, a medical; when stated, a candidate who meets the academic rules reads ACADEMICALLY ELIGIBLE — ADDITIONAL SCREENING REQUIRED). English and Mathematics remain the compulsory credits (§2.13.4), the credit count is the rule's `olevel_credits` (default five) and the sittings combined are its `olevel_sittings` (default two; one means the best single sitting is read). The UTME combination is the **Required UTME subjects (checked)** set; the score is read against the greatest of the programme's cut-off (or the faculty's) and the session's load cut-off; Direct Entry candidates are read against the DE subject set and the captured award. A new **Subject equivalencies** panel states, one per line, `Required subject = Accepted subject`, optionally `@OLEVEL` or `@UTME`; the engine honours these and only these. Every change to any of these tables moves the policy's **rules version**, and every evaluation records the version it was read under; the next opening of a stale reading re-evaluates it.

*The register* — **Programme Eligibility** `/admissions/eligibility?session=` (menu: academic and registrar, Admissions group; also from the Admissions page). Readers: academic, registrar, dregistrar, records, bursar, ict, admin, super, dvc, vc; acting office (recalculate, request, decide): academic, registrar, dregistrar, super. Tiles: Applicants evaluated, Eligible (with the screening-required count), Not eligible, Alternatives available, No eligible alternative, Pending verification, Change requests open, Stale evaluations. Filters and search run on the server: Eligibility (Eligible / Not eligible / Alternatives available / No alternatives / Pending verification / Change requested / Not evaluated), Faculty, Department, Programme applied, Recommended programme, Mode, and a search over name, JAMB number, application number, programme, faculty and department. The table shows Applicant, Applied programme, Eligibility, Failed requirements, Suggested programmes and any change request; **View Matching Details** opens the applicant's O'Level and UTME on record, the check-by-check table for the applied programme, the suggested programmes (eligible first, same faculty first; a checkbox shows every programme evaluated for diagnostics), each with its own table and a **Request Change** on the applicant's behalf, the change requests and the trail. **Evaluate the unevaluated** reads every submitted application that has no current evaluation (the system's reading — the applicant is told); **Recalculate all** and the per-row **Recalculate** are the officer's own act. A candidate whose applied programme is refused is told once per change of verdict, never that admission is guaranteed.

*Change of programme.* A request — the applicant's, for a programme the engine listed, or the Office's — sits on the **Programme change requests** queue as REQUESTED; **Approve** re-reads the candidate's eligibility for the programme at that moment, changes the application's programme on the record, re-evaluates under PROGRAMME_CHANGE and tells the applicant; **Reject** requires a reason and tells the applicant. One open request per application; none once the Board's decision is released. Nothing here admits anybody or moves an offer.

*Reports* (Excel and PDF, S/N first, names A–Z): the register as filtered, **Candidates not eligible for the applied programme** (Applicant, Applied Programme, Reason, Alternatives), **Alternative programme suggestions** (Applicant, Original Programme, Suggested Programme, Eligibility) and the statistics sheet.

*Trail.* `admissions.eligibility_event` (write-once): EVALUATED, RECOMMENDATION_GENERATED, RECOMMENDATION_VIEWED (each officer opening), PROGRAMME_CHANGE_REQUESTED / APPROVED / REJECTED, with the policy version and the trigger (SUBMISSION, SYSTEM, OFFICER, APPLICANT, DATA_CHANGE, POLICY_CHANGE, PROGRAMME_CHANGE).

> **Screenshot Required:** Programme Eligibility — `/admissions/eligibility` — the eight tiles, the filter bar, the register with Failed requirements and Suggested programmes, and the View Matching Details modal.

### 2.14 Document policies and templates

**Status: IMPLEMENTED (V262).** Screen: Policies & templates — `/credentials/documents/settings` (reached from Documents Office `/credentials/documents`; configuration guard `registrar, dregistrar, academic, super`; other readers see "You are reading these settings").

> **Screenshot Required:** Policies & templates — `/credentials/documents/settings` — the "Policies by document kind" table and the policy modal with the "Fields shown to a stranger on verification" checkboxes.

**2.14.1 Policies by document kind** (seeded by V262 and confirmed on the audited database):

| Kind | Label | Billable | Fee | SLA (days) | Self-service | Prefix | Graduates only | Public fields |
|---|---|---|---|---|---|---|---|---|
| DEGREE_CERTIFICATE | Degree certificate | no | 0 | 10 | no | CERT | yes | holder, programme, award, classOfDegree, faculty, department, graduationSession, graduationDate |
| TRANSCRIPT | Official full transcript | yes | blank → `finance.transcript_fee(session)` (the fee schedule) | 5 | no | TRN | no | holder, programme, faculty, department, award, classOfDegree, graduationSession |
| SESSIONAL_TRANSCRIPT | Sessional transcript | yes | 2,000 | 3 | no | STR | no | holder, programme, faculty, department, session |
| MINI_TRANSCRIPT | Mini-transcript | no | 0 | 1 | yes | MTR | no | holder, programme, faculty, department |
| ACADEMIC_STATEMENT | Statement of academic record | no | 0 | 1 | yes | ASR | no | holder, programme, faculty, department, level |

**Edit** a policy: Label, Fee (blank = fee schedule for TRANSCRIPT, zero otherwise; disabled when not billable), Urgent processing fee, Physical delivery fee, International delivery fee, Standard processing (working days), Urgent processing (days), "Mini-transcript covers" (current semester / selected semester / selected session / cumulative), Billable, Self-service, Graduates only, Active, and the checkboxes for the fields a stranger may see on verification (holder, matricNo, programme, award, classOfDegree, faculty, department, graduationSession, graduationDate, session, level, standing, cgpa — "Never shown: date of birth, address, phone, email, finances, internal identifiers. Results are never on the public page."). Number format is `PREFIX/YYYY/NNNNNN` with the prefix `^[A-Z]{2,6}$`. A free self-service kind is generated and released the moment the student requests it. A degree certificate is never requested; the Registry issues it.

**2.14.2 Templates.** One version in force per kind; **New template version**: Document, Title, Subtitle, Signatory and title, Second signatory and title, Footer, Official remarks → **Put in force**. Every document already issued stays under the version it was issued with. Seeded v1 signatories: certificate — The Registrar / The Vice-Chancellor; transcript — The Registrar; sessional, mini and statement — Deputy Registrar (Exams and Records) / Exams and Records.

> **Note:** The "signature" on an issued document is a SHA-256 content hash, not a cryptographic signature (`credentials.signing_key` holds no row). A document is tamper-evident only against the University's own store; offline verification is **NOT IMPLEMENTED**.

### 2.15 Hostel inventory, window and rules

**Status: IMPLEMENTED (V030 + V261).** Actors: `services, housing, registrar, admin, super`. Menu (housing, Accommodation group): Hostel Dashboard `/hostel`, Application Window & Rules `/hostel/window`, Hostel Inventory `/hostel/inventory`, Applications & Waitlist, Occupancy & Check-in, Checkout & Clearance. **No hall and no window is seeded**; the halls on the audited database are integration-test residue.

**2.15.1 Inventory — `/hostel/inventory`.**

| Modal | Fields / rule |
|---|---|
| A new hostel | Code (2–8 letters/digits, upper-cased, required), Type (`hostel.hall_kind`: UNDERGRADUATE, POSTGRADUATE, STAFF, INTERNATIONAL, MEDICAL, SPECIAL_NEEDS, OTHER), Name (required), Gender (Mixed/Female/Male), Campus, Location, Description |
| A block | Hostel, Block code (≤ 12, required), Name (default "Block X"), Floors 1–30 |
| A room | Hostel, Block (required; a block named here is auto-created), Floor (0 = ground), Room number (required), Capacity (beds) 1–12 (required), Room type ("From the capacity": SINGLE 1, DOUBLE 2, TRIPLE 3, QUADRUPLE 4, SIX_BED 6, EIGHT_BED 8, OTHER 12), Gender restriction ("As the hostel"), State (Available / Maintenance / Closed / Reserved), Note — saving numbers the beds "Bed 1…n"; lowering the capacity marks surplus beds OUT_OF_SERVICE |
| Generate rooms | Hostel, Block, Floor, Number prefix (e.g. "A-"), From number, To number, Beds per room, Room type — at most 500 in a run, lower to higher |
| An asset | Asset tag (required), Asset type (required), Hostel, Room, Quantity, Condition (NEW … DISPOSED), Date acquired, Value, Note |
| Facilities of a room | A quantity per facility (15 seeded codes: Bed, Mattress, Wardrobe, Reading table, Chair, Fan, Air conditioner, Bathroom, Toilet, Water supply, Power supply, Generator, Internet / Wi-Fi, Fire extinguisher, Security system); 0 removes |
| Close / Reopen | For a hall, block, room (State Maintenance / Closed / Reserved) — Reason required; afterwards a red notice lists occupants affected, each to be transferred from their allocation page |

Exports: **Excel**, **PDF** ("Hostel Inventory"), **Bed list (Excel)**. The reference lists (hall kinds, room types, facilities, the nine clearance requirements) are seeded and edited only in SQL.

> **Screenshot Required:** Hostel inventory — `/hostel/inventory` — the hostel filter, the officer buttons, the five tiles and the Rooms table with Edit / Facilities / Close actions.

**2.15.2 Application window & rules — `/hostel/window`** (one row per session, `hostel.session_setting`).

| Panel | Fields |
|---|---|
| Fee, dates and stay | Accommodation fee (₦, required — "Zero is a fee; blank is not."), Hold window (hours, 1–720; default 72 — how long a bed is held for payment), Maximum applications (blank = no limit), Applications open / close (dates), Window state (Draft — not visible / Open / Closed / Allocated), Stay from / to, Allocation method (BALLOT default, FIRST_COME, LEVEL, FACULTY, PROGRAMME, SPECIAL_NEEDS, MANUAL), "The desk reviews each application before allocation", "Keep a waiting list; a lapsed bed passes to the next name" |
| Who is eligible | Student status checkboxes (default ACTIVE, ADMITTED, PROBATION), Levels 100–900 (none = every level), Faculties (none = every faculty), Kinds of hall open this session, "Course registration for the session submitted", "No unsettled hostel damage charge or uncleared stay" |
| Hostel rules and regulations | Textarea (≤ 20,000 characters); every change makes a new **rules version** the student acknowledges again before accepting a bed |

Buttons: **Save the window / Create the window**, **Save and open applications**, **Save and close applications**. Creating or opening a window emails and texts every student in an eligible status ("Hostel applications are open") when there are at most 5,000 of them. After the draw the method and seed are on the record; dates and rules may still change.

The hold clock runs hourly at minute 5 (`moaum.hostel.cron`, default `0 5 * * * *`, Africa/Lagos) and lapses unpaid holds, passing the bed to the next name on the list. Running the session is §3.9.

### 2.16 Help desk categories, SLA and auto-close

**Status: IMPLEMENTED.** Screen: ICT Support Settings — `/helpdesk/settings` (Director: `ict, admin, super`).

**Categories.** Eleven are seeded with their fields and suggested priority: PAYMENT (HIGH; payment_reference*, payment_date*, payment_type* choice, amount*), LOGIN (HIGH; account_type*, username*, error*, started_on), REGISTRATION (NORMAL; session*, semester*, programme, level*, course_code, course_title), RESULTS (NORMAL), EXAMINATIONS (HIGH), PORTAL (NORMAL), EMAIL (NORMAL), ACCOUNT (NORMAL), NETWORK (NORMAL), GENERAL (NORMAL), OTHER (LOW). **New Category** / **Edit**: Name (≤ 120), Code (made from the name; `^[A-Z][A-Z0-9_]{1,30}$`; fixed once created), Order, Handled as (priority), Description, What to attach, "Open for new tickets", and the field list (Label, Key `^[a-z][a-z0-9_]{0,30}$`, Type Text / Date / Number / Choice / Academic session / Semester / Level, Required, Hint, Options for a Choice). A category is deactivated, never deleted.

**The SLA by priority.** First response (h, 1–720) and Resolution (h, 1–2160) per priority; seeded LOW 72/240, NORMAL 24/120, HIGH 8/48, URGENT 2/24; the resolution time is at least the first-response time.

**Closing and notice.** "Close a resolved ticket automatically after" N days (blank = Off; 1–90) and "Email every agent and the Director when a new ticket arrives" (seeded on). The auto-closer runs hourly and is inactive while the days are blank — **IMPLEMENTED, off by default**.

Agents are people who hold the `ictagent` office (or `ict`, `admin`, `super`); grant it from `/people` before assigning tickets ("only an ICT Support Agent or the Director of ICT takes a ticket").

### 2.17 Clearance units and purposes

**Status: seeded; no screen.** `clearance.unit` holds eight units in order — BURSARY (`bursar`), DEPARTMENT (`hod`), FACULTY (`dean`), LIBRARY (`library`), HEALTH (`services`), HOSTEL (`services`; `housing` also signs since V261), WORKS "Works and Maintenance" (`services`), ALUMNI "Alumni and Convocation" (`registrar`). `ref.clearance_purpose` holds CONVOCATION, EXAMINATION, HOSTEL, ID_CARD, LIBRARY, REGISTRATION, RESULTS, TRANSCRIPT. The Clearance screen (`/clearance`) offers CONVOCATION by default and takes another purpose only from the URL (`?purpose=`) — PARTIALLY IMPLEMENTED on screen. Registrar, Deputy Registrar (AA) and the Academic Officer may sign any unit; every other signer signs only the unit whose `office_code` is their acting office. Automatic clearance from the library or Bursary position is **NOT IMPLEMENTED** — every unit signs by hand; the hostel module writes a HOSTEL item on the CONVOCATION purpose when a hostel clearance completes.

### 2.18 API keys register

**Status: register IMPLEMENTED; API-key authentication, scopes and quotas NOT IMPLEMENTED.** Screen: Integrations / API Management — `/api-keys` (ict, admin, super). **+ Register a consumer** (Client name, Owner, Scopes space-separated, Daily quota); per consumer **Issue a key** (days until expiry, max 366) → the plaintext `mk_…` key is shown once and only its SHA-256 and last four characters are kept; **Revoke**; **Deprecate** (revokes every live key). "Due to rotate" means expiring within 14 days.

> **Warning:** Nothing in the API authenticates a request by API key. The security chain accepts JWTs alone; scopes and quotas are stored, never enforced; the screen's wording "rate-limited" is aspirational. Register consumers for the record, but do not hand a key to an integrator expecting it to open anything today.

### 2.19 NDPA register

**Status: IMPLEMENTED for reading the processing register, completing a DPIA, and logging/advancing data-subject requests; adding or editing a processing activity is NOT IMPLEMENTED (migration only).** Screen: Data Governance — `/governance` (writers `registrar, dregistrar, ict, super`; readers add audit, deputyaudit, vc, dvc, admin).

- **Record of processing activities** — seven seeded rows (Automated admission scoring — DPIA OUTSTANDING; Biometric identity verification at CBT — COMPLETE; CBT proctoring and session logging — OUTSTANDING; Health records — COMPLETE; Payment and financial records, Staff personnel and payroll records, Student academic records — NOT REQUIRED). **Mark done** moves OUTSTANDING → COMPLETE.
- **Data-subject rights requests** — Log a request (Type Access / Rectification / Erasure / Portability / Objection, Requester, Due — defaults to 30 days) → reference `DSR-YYYY-NNNN`; **Start** (→ IN_PROGRESS), **Complete**. REFUSED exists in the CHECK but cannot be reached from the screen. Overdue rows turn red; there is no reminder.

### 2.20 Go-live readiness

**Status: IMPLEMENTED.** Screen: Go-Live Readiness — `/readiness?session=` (menu: admin; guard `super, ict, admin, registrar, dregistrar, academic, bursar`). Session select (must be `dddd/dddd`, else the hard-coded `2026/2027`); tiles Ready / Blocking / To review / Total checks; each gate with a pill and a **Fix** link:

| Gate | Reads | Blocking when |
|---|---|---|
| Applicant fee set | `admissions.applicant_fee_rule` | unstated |
| Admission policy in force | `session_policy` | none IN_FORCE |
| Session on the calendar | `policy.academic_session` | absent (warn unless CURRENT) |
| A semester is open | `policy.semester` | none OPEN |
| School-fee schedule set | `finance.fee_schedule` | no live line |
| Clearance scheme in force | `policy.version` | none |
| Demo data removed | surname DEMO / DMO-DMC courses | present |
| Exam-screened programmes set | `screening_exam_programme` | never blocks |
| Payment gateway configured | keys | none (TEST = warn) |
| Email (SMTP) configured | `platform.mail_settings.smtp_host` | blank |
| SMS configured | `platform.sms_settings` enabled and keyed | not |

> **Screenshot Required:** Go-Live Readiness — `/readiness` — the four tiles and the list of gates with Ready / Check / Blocking pills and Fix links.

---

## 3. Daily administration by office

Each subsection opens with the office's dashboard and what its figures compute, names the queues to watch, then gives the procedures with navigation, fields, validations and outcomes. Dashboards are read models over other modules' tables; nothing is entered on them. Every office's Overview group also has **Search** (`/search`: students, staff, courses, credentials; every search for a person is written to `people.search_log`).

### 3.1 Registry (Registrar and Deputy Registrar (Academic Affairs))

**Dashboard — `/` (RegistrarDashboard; the DR(AA) sees the AcademicDashboard).** A static note "The NDPA Compliance Audit Return is due on 31 March"; the student statistics panel; tiles **Students on the register** (`/student/students` count), **Staff on the register** (`/iam/persons`, with accounts), **Senate business** (sheets in the approval chain, from `/results/sheets`), **Credentials in hand**; a "Registry business" table (admissions cycle, matriculation, convocation, and a static row for the name of the University); a "Council and Senate" table whose rows are **PLACEHOLDER** ("No sitting recorded").

> **Screenshot Required:** Registrar dashboard — `/` (acting as Registrar) — the tiles and the "Registry business" table.

**Queues to watch.** Deferments forwarded to the DVC (`/deferments`, status filter WAITING DVC ACTION; the DVC's approval is final); transfers at the Registrar desk (`/transfers` tab Registrar); documents awaiting release (`/credentials/documents` tile "Awaiting release"); results waiting at SENATE (`/results/senate` for the DR(AA); `/results/approvals` "Senate Business" for the Registrar); faculty lists not confirmed (`/matriculation`); the returns due register (`/reports`).

**3.1.1 Matriculation — run and single issue.** Status: IMPLEMENTED. Runners `academic, registrar, dregistrar`.

```text
Students
 → Matriculation                 (/matriculation?session=)
 → Open (a faculty)              (/matriculation/faculty/{code}?session=)
```

1. Open **Matriculation**. The headline note says whether the run may start: "N faculty lists are not confirmed, so the run cannot start" / "Every faculty list is confirmed — the run may start" / "Nobody is on a faculty list for … yet". Tiles: Registered students, Confirmed by Faculty Officers, Faculties outstanding, Numbers issued.
2. For each faculty press **Open**. The list is generated (never typed) from ADMITTED students with an APPROVED registration in the session. Columns Admission number, Name, Department, Units (red below the 100-level minimum of 18), Fees ("—", not computed on this screen — **PLACEHOLDER**), State.
3. **Query** a name (Reason; "Who clears it": Faculty Officer / Bursary / Head of Department / Academic Office) or **Withdraw query**. A queried student is held back from the run.
4. **Confirm N students to the Academic Office** (officers `academic, registrar, dregistrar, facultyofficer`; a second confirm answers `MAT_ALREADY_CONFIRMED`). No faculty scope is enforced in code on this screen.
5. Back on **Matriculation**, press **Run matriculation for N students**. In one transaction, for every un-queried student whose fees for the session are paid in full (`finance.position(...).paid_in_full`), ordered by department and surname: the next number is drawn from the configured series, the student becomes ACTIVE with a status change citing the run reference `MAT/YYYY/NNN` and reason "Matriculated", the issue is written once to `people.matric_history`, and the student is emailed and texted "Your matriculation number". If nobody qualifies: "nobody on a confirmed list has both paid the fees and registered for %; there is nothing to matriculate". A configuration problem (a code missing, an inactive series) rolls the whole run back.
6. **Issue number** on one row (a straggler who has since paid and registered) runs the same steps for one student: refused unless ADMITTED, registered for the entry session and paid in full.

> **Note:** The "What the run does" text on the run screen still describes per-department sequences (`MOAUM/MTC/26/1874`); the number actually follows the V263 rule (§2.12). "Export the list" on a faculty page is a plain CSV, not the branded export.

**3.1.2 The student record (Student 360) — status changes, level correction, portal account.** Status: IMPLEMENTED. Writers `academic, registrar, dregistrar`.

```text
Students
 → Student Records   (/students)
 → Details           (/students/{id})
```

- **Change status**: To (ACTIVE, PROBATION, DEFERRED, SUSPENDED, RUSTICATED, WITHDRAWN, EXPELLED, TRANSFERRED_OUT, GRADUATED, DECEASED, DORMANT, VOLUNTARY_WITHDRAWAL), **Instrument** (required — "a change of status is made on an instrument — the Senate minute, the letter, the Registrar's decision — and none was cited"), Reason. Any status other than ADMITTED requires a matriculation number (`ck_student_active_has_matric`), so ADMITTED → ACTIVE is done by matriculation, not here. The change is written to `people.status_change`. No notice is sent.
- **Correct level**: level 100–600 and a reason; a plain update, no status_change row.
- **Portal account**: prompt for an eight-character first password; opens or resets the student's sign-in (`registrar, dregistrar, academic, records, ict, super`); enabled only when a matric number exists; the student must change the password at first sign-in.
- **Biodata**: the Registry writes any open field directly; locked fields (`university_email`, `senatorial_district`) are refused.
- Two panels on `/students` for `academic, registrar, dregistrar, ict, super`: **Migrated from the old portal** — "Clear the N not yet cleared" inserts CLEARED items for every purpose and unit for students with a number but no matriculation run; **Voluntary withdrawals** — "Close all N due" / per-row "Close" applies VOLUNTARY_WITHDRAWAL to students with four consecutive closed semesters without an approved registration, under the instrument "University regulation: four consecutive semesters without course registration".

> **Warning:** The Student 360 Finance card is a hard-coded "NOT YET SERVED" and the CGPA card shows "—" although the data exists elsewhere — **PLACEHOLDER** cards. Read fees on Student Statistics or the Bursary screens and CGPA on the broadsheet.

**3.1.3 Biodata Changes queue — `/students/biodata-changes`.** Status: **CONFIGURED BUT UNUSED — unusable today.** The screen (tiles Awaiting evidence / Approved / Refused / Self-service changes; actions Approve with evidence, Refuse with "The decision, in words", Ask for evidence) and its endpoints work, but nothing can create a request: `ref.biodata_field` has no `approval` tier and the code path that would ask for a change is never called. The queue is always empty. The menu badge "4" is a fixture.

**3.1.4 Inter-departmental transfers.** Status: IMPLEMENTED (pipeline); the older committee/Senate path has endpoints but no screen. Screen: Inter-Departmental Transfer — `/transfers` (academic, hod, registrar). Stages: APPLIED (fee must be paid) → current-department HOD → new-department HOD → **Registrar/DR(AA)** → Academic Office, which effects the change of programme and level on the register. The Registrar's act is **Approve** or **Decline** (reason) on the Registrar tab; approve is refused before the fee is confirmed. **Record an application** (Student number, Course applied for, Reason, UTME score) captures a paper case (`academic, registrar, dregistrar, super`). No notice is sent at any stage. The approval letter the student prints cites a hard-coded ₦10,000 and Senate/SAIC wording — **PARTIALLY IMPLEMENTED**.

**3.1.5 Deferments.** Status: IMPLEMENTED (V259, revised by V264). Screens: Deferments — `/deferments`, review `/deferments/{id}`, Students Due to Resume `/deferments/returns`, Forwarding Batches `/deferments/batches`. The chain is Bursary → Head of Department → Faculty → Academic Office → DVC, and the DVC's approval (with a required comment) is final (V265). The Registry (`registrar`, `dregistrar`, `super`) reads the whole chain, may forward with the Academic Office, is the only desk (with the Academic Office) that may **Cancel**, and confirms returns. The Academic Office (`academic`, and the Registry) sees every stage, downloads an application only once the faculty has approved it (the API refuses earlier), and forwards the faculty-approved list to the DVC in a numbered batch (**Forward Approved Applications to DVC**). The DVC's approval applies the academic effect in the same transaction: the courses of the period are marked DEFERRED (never failed), the CGPA is untouched, the programme timeline is extended by the period deferred, the entry session and matriculation number stand; the approval letter is issued and the student told. The daily clock (06:20 Africa/Lagos) brings the period into force, sets the student DEFERRED, refuses registration by trigger for the period, reminds 14 days before the return and flags overdue returns 30 days after; on the confirmed return the deferred courses become due on the registration form. The **fee** is stated by the Bursary on Fee Setup (Deferment · application fee); the limits (`max_sessions` 2, `allow_extension`, `reminder_days` 14, `overdue_after_days` 30) are set through `PUT /api/v1/deferments/settings` (Registry) — **no screen** yet; the reason list is a table. The approval letter's QR points to `/verify/deferment`, which **does not exist** — NOT IMPLEMENTED. Desk exports: Excel/PDF (serial DEF, S/N first); the Academic Office's export contains faculty-approved applications only.

**3.1.6 Revoking a document.** Status: IMPLEMENTED. Only `registrar` or `vc`, and only citing a minute. Issued documents — `/credentials/documents/register` → **Open** the document → **Revoke**: Reason (required) and **Instrument (the minute)** (required, e.g. `SEN/2026/118`). Every secure-link token is revoked, the student is told, and the document verifies as REVOKED from then on with a diagonal watermark on any print. The Registrar (and DR(AA), Academic Officer) may also **Reissue (new version)** — the old version verifies as REPLACED — and **Authorise and release** requests (§3.10).

**3.1.7 Graduands and the Senate list.** Status: PARTIALLY IMPLEMENTED (audit) / IMPLEMENTED (approval). Screen: Graduation — `/graduation` (menu: academic, dean, dvc, records, vc, pgschool, pgsecretary; the Registrar reaches it by URL). **Run the degree audit for <session>** (`academic, registrar, dregistrar, records`) computes, for every student enrolled at the final level, the CGPA over published results and any unmet requirement — but the audit checks only "every registered course published" and CGPA ≥ 1.00; the curriculum rules the screen names (core courses, credit minima, GST, project) are **not** checked. **Send the list to Senate** (`registrar, dregistrar, academic`) takes the Senate minute and marks every passing graduand APPROVED, sets each GRADUATED with the minute as instrument, and emails and texts "Senate has approved your award". Final levels are hard-coded (600 for MBBS, 500 for LL.B and Pharmacy, 400 otherwise).

**3.1.8 Statistics and returns.** Student Statistics — `/stats` (money figures for MONEY offices including the Registrar); Reports & Returns — `/reports` where the Registrar owns admissions, enrolment and registration returns (due 31 December and 31 March/31 August) and keeps, files and emails copies (§4.8, §7).

**3.1.9 Also the Registrar's.** People console (§2.3); Data Governance (§2.19); the printed certificate register (`/credentials/certificates`, §3.10.6); Post-UTME CBT Schedule and Admissions read screens; Staff Records and Recruitment (with HRM, §3.6); Senate Business (`/results/approvals`) where the Registrar records the minute that publishes result sets (§3.3.4).

### 3.2 Academic Office

**Dashboard — `/` (AcademicDashboard, shared with the DR(AA), Exams and Records and the DVC).** A leading note on result sets and transcripts, the student statistics panel, tiles, "Committed admission list" (from the CAPS cycle), "Registration, by faculty" (the "Blocked at the Bursary" column shows "—"), and "Credentials in hand" whose "verification requests" row still says "Public verification arrives with its module" — stale text; public verification exists.

**Queues to watch.** The menu badges that are live: Matriculation "!" (current-session ADMITTED students without a number), Admission Settings "!" (no in-force policy for the next PLANNED session), Clearance, Transcripts, Certificates, Biodata Changes (always zero), Approvals. Also: "n admitted candidates are not yet on the register" on `/admissions`; sheets holding a faculty on `/examinations/sessions`.

**3.2.1 The undergraduate admissions cycle.** Status: IMPLEMENTED end to end, with the caveats named per step. Offices: settings `academic, registrar, dregistrar`; CAPS loads `academic, registrar` acting as such; decisions, releases and screening `academic, registrar, dregistrar`.

```text
Admissions
 → Admission Settings                 (/admissions/settings)
 → Upload Applicants and Candidates    (/admissions/caps)
 → Upload Passport, DOB & O'Level      (/admissions/candidate-data)
 → Post-UTME CBT Schedule              (/admissions/putme)
 → Upload PUTME Score                  (/admissions/scores)
 → Compute PUTME Score                 (/admissions/computed-screening)
 → Merit List                          (/admissions/merit)
 → Direct Entry Screening              (/admissions/de-screening)
 → Report on Admissions                (/admissions)
```

1. **Put the settings in force** and state the **General UTME cut-off** (§2.13). No UTME list loads without both.
2. **Load the CAPS list** (`/admissions/caps`). Choose the UTME (100 Level) or Direct Entry (200 Level) `.xlsx` (JAMB's raw `RG_NUM/CO_NAME…` layout or the office layout). The parsed list shows blocking findings ("n rows cannot be accepted, so none of the file is written"), JAMB course names the alias list does not carry (map them with **AliasMapper** → the programme's JAMB alias), and "Under the cut-off — read, not loaded". **Load the list** writes a *held* batch; rows are sent in chunks. **Does the list reconcile?** shows the five findings; **Commit** is refused while any finding other than "On the CAPS list, no candidate record" is non-zero ("the admission list does not reconcile: …"). **Withdraw** needs a reason and is refused once a student holds an admission number from the list. Committing re-attaches any passports, dates of birth or O'Level results already uploaded.
3. **Record the candidate data** (`/admissions/candidate-data`): passports (the JAMB number is read from the filename; images ≤ 64 KB are stored, larger ones by metadata only), the date-of-birth `.xlsx`, and the O'Level `.xlsx` (one row per subject). The O'Level screening points are computed per candidate and are shown to the Academic Office only.
4. **Screening.** For exam-screened programmes, set up and run the CBT (§3.2.2) or seat legacy batches on the desk (`/admissions` → ApplicantsDesk → **New batch** / **Seat the submitted** / **Hall list**). Scores arrive by **Upload PUTME Score** (`/admissions/scores`: CSV `key, score` with the JAMB or application number; rows out of 0–100 or already released are reported; **Score remaining as zero** for stragglers; **Clear uploaded Post-UTME scores** after typing `CLEAR SCORES`) or by entering one CBT score on the application modal. For non-index programmes and Direct Entry, **Compute PUTME Score** → **Enter O'Level as Post-UTME score**. Then **Release the scores** (stamps `score_released_at` for every seated or scored application and notifies each applicant).
5. **Merit list** (`/admissions/merit`): pick the programme; the pool, eligibility ("No Eng/Maths credit" / "Below cut-off" / "Not scored") and the proposed offers by basis NM → SM → ELG → LOCALITY up to each criterion's percentage of the programme's UTME quota are computed by `admissions.merit_list`; **Record the merit list** writes OFFERED / WAITING / NOT_OFFERED per application. **Record all programmes** on `/admissions` does the same for every programme. Direct Entry candidates are excluded from the merit list by design ("UTME only for now") and are decided one by one.
6. **Decisions** on the desk (`/admissions`, eye icon on an applicant): Decision (OFFERED / WAITING / NOT_OFFERED), Basis (NM / SM / ELG / LOCALITY / PLWD / OTHER — "an offer is made on a basis"), Note. Refused when the score is unreleased, when the decision was already released, or when a compulsory O'Level credit is missing. **Release decisions** stamps `decision_released_at`, moves PROPOSED candidates with an OFFERED decision to ADMITTED and notifies each applicant. Alternatively upload **Admission status from JAMB** (registration number, name, course, admission status): every "Accept…" row with an application is offered and released with the basis from JAMB's category — with **no applicant notice**.
7. **Bring N candidates onto the register** on `/admissions` runs the intake (`people.intake`): a `people.student` row for every ADMITTED or ACCEPTED candidate not yet on it, admission number `MOAUM/ADM/YY/NNNNNN`. It runs on ADMITTED — before acceptance — and refuses (409) a candidate whose programme name is not one the University runs.
8. **Reconsiderations** (`/admissions`): non-qualified candidates with five credits and an open programme they qualify for; **Suggest** emails "Your … admission — a suggested programme". **Programme Eligibility** (`/admissions/eligibility`, §2.13.6) is the rule-based reading of every submitted applicant against the settings, with the failed requirements, the suggested programmes and the change-of-programme queue.
9. **Reset the JAMB list for <session>** (double confirm) deletes the session's intake — candidates, applications, accounts, references, screening — and detaches students. Destructive; guarded only by the browser confirms.

What has **no screen**: the Registry's recording of an applicant's six clearance documents (`PUT …/clearance/{item}`), applicant document review, and office confirmation of an applicant's fee reference — all PARTIALLY IMPLEMENTED (endpoints only). Offer lapse and waiting-list promotion are **NOT IMPLEMENTED** (the `LAPSED` state is never set although applicant text promises it).

> **Screenshot Required:** Upload Applicants and Candidates — `/admissions/caps` — the two upload cards, a parsed list with its findings and the "Lists loaded for <session>" table with held/committed states.

**3.2.2 Post-UTME CBT scheduling and the door.** Status: IMPLEMENTED (V260). Screen: Post-UTME CBT Schedule — `/admissions/putme` (OFFICE `academic, registrar, dregistrar, super`; DOOR adds `records, ict`).

1. **Setup** (§2.13.5). Eligibility needs an exam-screened programme list; otherwise "No programme is named as screened by examination this session, so nobody is eligible".
2. **Generate Batches**: places = days × slots × rooms; candidates READY_FOR_SCHEDULING (paid, submitted, programme exam-screened) are dealt by the strategy into batches `B001…` with seats `001…`. The exam moves to SCHEDULING_IN_PROGRESS; batches are DRAFT — candidates see no slip yet.
3. Read the **Validation report** (errors CAPACITY, DUPLICATE, ROOM_CLASH, INELIGIBLE, UNPAID, UNSUBMITTED, UNPLACED_BATCH; warnings UNSCHEDULED, REVIEW, NO_WORKSTATION). Fix on **Candidates** (`/admissions/putme/candidates`: **Move n to a batch** with a reason, **Unschedule n**, **Confirm** a schedule review after a programme change, **Trail**).
4. **Publish and notify** (disabled while errors stand): every batch becomes PUBLISHED, the exam SCHEDULED, and each candidate is emailed and texted "Your Post-UTME examination schedule"; the slip with its QR appears on the applicant's Screening Slip page.
5. On the day, **Check-in Desk** (`/admissions/putme/checkin`): scan the slip's QR (or type the application or JAMB number) → **Find** → verdicts "Seated today · batch B, seat NNN" (→ **Check in**), "Not seated in any batch", "Seated on {day}, not today", "Already checked in at … A second arrival on this slip is an impersonation", "Disqualified". Then **Seated, started** / **Completed** / **Absent** / **Disqualify** (remarks required). A batch page offers **Postpone** / **Cancel batch** (reason; unseats everyone and notifies if published) and the attendance sheet (Excel/print).
6. **Mark completed** when the sitting is over (ONGOING is a state nothing sets automatically — PARTIALLY IMPLEMENTED).

Public verification of a slip is at `/verify/putme/{token}` — genuine only for a published batch.

**3.2.3 Calendar.** §2.4 — the Academic Office is the menu owner of Session & Semester Setup.

**3.2.4 Registration desk.** Status: IMPLEMENTED (approval is the HOD's). The Academic Office's "Registered Students" (`/registration/class-list`) shows the roll of an offering with its clearance flag, the attendance register and timetable slots; the registration approval queue on `/results/approvals` lists submitted registrations for every department, but **Approve / Return** are enabled for `hod` (and `super`) only — the Academic Office reads. There is **no overload mechanism**: a registration above the level maximum can neither be submitted nor approved; the hints that mention an HOD overload describe nothing that exists.

**3.2.5 Results desks and Senate.** The Academic Office creates and opens examination sessions (§3.3.1) and may enter marks (`ENTRY`), but it holds **no stage** of the approval chain in the UI map, so on `/results/approvals` ("Results to Senate") and `/results/chain` it reads. Recording the minute is the Registrar's and DR(AA)'s (§3.3.4).

**3.2.6 Clearance, documents, transcripts, certificates.** The Academic Officer signs **any** clearance unit (§2.17), works every stage of the digital-document pipeline including release (§3.10), and the legacy transcript queue.

**3.2.7 Reports.** Owner of no return itself, but a reader and runner of enrolment, registration, carryovers, admissions and revenue returns, and a keeper of copies (§7).

### 3.3 Exams and Records

**Dashboard — `/`**: the AcademicDashboard (§3.2). Menu (records): Examination Sessions (badge "!"), Post-UTME CBT Schedule, Validation Desk, Result Pipeline, College of Health Sciences, Migrate from Old Portal, Broadsheets, Senate Schedule, Publication, Approval Chain, Graduation Records, Deferments (read), Documents Office, Transcripts, Certificates, Records & Queries, Reports.

**3.3.1 Examination sessions.** Status: IMPLEMENTED (the CLOSED state is never set). Screen: Examination Sessions — `/examinations/sessions` (create/edit/open: `records, academic, registrar, dregistrar`).

1. **Create an examination session**: Academic session, Semester (First/Second/Third), Type (Main examination / Re-sit / Special), Examinations begin, Examinations end, Score sheets due. Rules: the examinations end after they begin; the sheets are due after the examinations end; one session per (academic session, semester, type).
2. **Open the session** (or **Save as a draft** then **Open**): one score sheet is generated per offering of the session and semester **that already has a lecturer**; "N score sheets generated; M courses have no lecturer and generated none." A lecturer allocated later gets a sheet at once while the session is OPEN. For RESIT/SPECIAL a sheet is made only where the MAIN sheet is PUBLISHED.
3. **Edit** — once sheets exist only the dates change.
4. The **Submission monitor** (by faculty: expected, submitted, verified, past the Board, outstanding) and "The N sheets holding the Faculty of X" (Course, Lecturer, Days late, Escalated to HOD under six days late else Dean) with **Remind**.

> **Warning:** **Remind / escalate** returns 202 "The notification module is not on the portal yet; nothing was sent." — **PLACEHOLDER**. Chase late sheets by other means.

> **Screenshot Required:** Examination sessions — `/examinations/sessions` — the create panel, the sessions table with Open/Draft pills and the Submission monitor.

**3.3.2 The Validation Desk (RECORDS stage).** Status: IMPLEMENTED. Screen: Result Desk — `/results/desk`. Exams and Records holds the RECORDS stage: sheets arriving from the Faculty Board, "Send on to Senate" with **Forward N sets to Senate** (each sheet where the desk may act, the person did not take the previous stage, and the fail rate is ≤ 50%). Individual sheets are reviewed on `/results/chain?sheet=` (**Validate** / **Return to the lecturer** with the reason). The database enforces completeness, the minute and "not the same person twice"; the office-per-stage rule is UI only (§1.5).

**3.3.3 Broadsheets.** Status: IMPLEMENTED. `/results/broadsheet` — by programme, level, session and semester: the Examination Reporting Sheet (summary of results, key, courses, Dean/HOD signature blocks), the sheet table with CUR/CUE/WGP/GPA and cumulative figures, remarks in Senate's wording (CO:, Fail:, TO GO ON PROBATION, ADVISED TO WITHDRAW, PENDING, PASS, DID NOT REGISTER FOR THIS SEMESTER), the probation and advised-to-withdraw lists from 200 level. **Download Excel** (two sheets, serial BRD) and **Download PDF** (a print window). "Withheld set shows as withheld" in the screen text is **NOT IMPLEMENTED** — there is no withheld-set concept in the data.

**3.3.4 Senate schedule and publication.** Status: IMPLEMENTED. `/results/senate` (records, dregistrar, dvc) and `/results/publish` (records): by faculty — Sets, Candidates, At Senate, Published, Outstanding, Recommendation. **Record the minute and release** / **Release to candidates on the minute** (Minute number e.g. `SEN/2026/…`, Faculty or every faculty) is enabled for **`registrar` and `dregistrar` only**; Exams and Records reads the schedule and cannot press the button. Publication advances every sheet at SENATE in scope to PUBLISHED, each in its own transaction, and lists refusals (typically BR-006: the same person validated at RECORDS). **Publication does not notify students** (NOT IMPLEMENTED); students see the result the moment it is published, subject to the results fee gate. "Print the schedule" exists in the desk text but there is **no export**.

**3.3.5 Clearance and graduation.** Exams and Records reads clearance (not a signer), runs the degree audit (§3.1.7) but does not approve the list, and reads Graduation Records.

**3.3.6 Transcripts queue (legacy) — `/credentials/transcripts`.** Status: IMPLEMENTED (kept beside the V262 pipeline). Tiles Open requests, Held at clearance, Breaching SLA (over 5 working days), Average turnaround. Per request: **Record payment** (signers), "Blocked — {unit}", **Produce & verify** (`records`, `academic`, `registrar`, `dregistrar` — generation and verification in one act), **Sign & release** (signers `registrar, dregistrar, academic` — Exams and Records cannot release). "View verification" is a button with no handler. A request can be raised on a student's behalf only through the API — no screen.

**3.3.7 Documents office.** Exams and Records works validation, generation, quality check, deliveries and completion in the V262 pipeline (§3.10) but is not a signer (no release, no certificate issue).

**3.3.8 Migrate from Old Portal — `/records/migration`** (records, ict). Legacy uploads of students, registrations, results and postgraduate records belong to the results module's `MIGRATE` guard; the "cleared on arrival" panel is the register's. Migrated sheets carry the minute "Migrated from the legacy portal". Details in *06 Workflows*.

### 3.4 Bursary

**Dashboard — `/` (BursarDashboard).** Headline note: "{n} settlement exception(s) are open" (→ Open the investigation / Reconciliation), or "No clearance scheme is in force" (→ State the scheme), or "No settlement exception is open". Student statistics panel. Tiles: **Collected this session** (confirmed school-fee references), **Collected today** ("{n} confirmation(s)"), **Exceptions open** ("{n} hanging at a gateway"), **Gateways live**. Panels "Collection by faculty" (Faculty, Collected, Students paid, Rate), "The desk" (Fee schedule and scheme, References awaiting confirmation, Hanging at a gateway, Bank credits, NELFUND, Held scripts — the NELFUND and Held scripts pills are hard-coded "Open"), "Recent confirmations" (last seven days).

> **Screenshot Required:** Bursar dashboard — `/` (acting as Bursar) — the headline note, the four tiles and "The desk" table.

**Queues to watch.** References waiting on the bank's record (`/finance/fees`); hanging payments and events that need a person (`/finance/hanging`); unmatched bank credits and proposals awaiting a second officer (`/finance/exceptions`); refunds awaiting approval (`/finance/refunds`); NELFUND suspense (`/finance/nelfund?tab=match`); withdrawals (`?tab=withdrawals`); vouchers cleared to pay (`/vouchers`); payroll runs to approve or pay (`/payroll`); students a held script waits on (`/finance/held-scripts`); returns due day 10 monthly (`/reports`).

**3.4.1 Confirm a bank-branch or transfer payment against a reference.** Status: IMPLEMENTED. `/finance/fees` → "References waiting on the bank's record" → **Confirm** → Channel (Bank transfer / Bank branch / USSD / Card; required), Note (teller number, transaction reference) → **Confirm the payment**. The receipt number `RCT-YYYY-NNNNN` is issued at once and the student is emailed and texted. A manual confirm always confirms the reference amount — it cannot short-pay. Unknown reference → 409 "no reference X was generated by this portal".

**3.4.2 Money with no reference — bank credits (maker–checker).** Status: IMPLEMENTED. Payment Investigation — `/finance/exceptions` (`bursar`, `super`).

1. **Record the credit**: Received on, Bank (required), Teller slip or draft number (required), Amount (> 0), Payer named on the slip, Note → state UNMATCHED. The bank record is never altered afterwards.
2. On an unmatched row: "Reference to post to" and "On what evidence" → **Propose**. Rules: a portal-generated reference, not already confirmed, credit ≥ reference amount ("A part payment is applied against a reference for the part").
3. A **different** officer presses **Approve and post** (the proposer sees "Your proposal — another officer approves"); the posting runs the ordinary confirmation with channel "Bank branch" and sends the receipt. **Reject** (reason) returns the credit to UNMATCHED. REVERSED is in the CHECK but no function sets it.

**3.4.3 Gateway exceptions and hanging payments.** Status: IMPLEMENTED. Hanging Payments — `/finance/hanging` (`bursar, ict, admin, super`): checkouts opened in the last three days with nothing confirmed — **Ask the gateway** now; "Needs a person" lists UNKNOWN_REFERENCE ("Generated and abandoned, paid against another institution's code, or forged — the desk officer chooses"), SHORT_PAID and GATEWAY_ERROR events with **Resolve** (a free-text resolution on the record). The webhook and verification log on `/finance/gateways` shows every event with its signature and outcome.

**3.4.4 Reconciliation against the bank statement.** Status: IMPLEMENTED. Settlement reconciliation — `/finance/reconcile` (`bursar, audit, deputyaudit, super` may check). For each confirmed payment in the window (default last 30 days): **Matched** (optional bank reference) or **Flag** (note required) → an append-only `payment_reconciliation` row. The server panel "Exceptions requiring action" links gateway events to Hanging Payments and bank credits to Payment Investigation. Known defect: on this page the error toast fires on every load, including successful ones (`ReconcileLedger.tsx:45`).

**3.4.5 Refunds (maker–checker).** Status: IMPLEMENTED (the payout is recorded, not executed). Refunds & Credits — `/finance/refunds` (`bursar`, `super`). **+ Raise a refund**: From a payment reference (optional; **Fetch** fills payer and amount and checks against the confirmed payment — a refund cannot exceed what was paid), Paid to (required), Reason (required), Amount (> 0), Bank, Account name, Account (last 4) → PROPOSED (`RF-YYYY-NNNN`). A different officer **Approve**s (or **Reject**s with a reason); then **Mark paid** once the money has left. A raiser sees "Awaiting another approver" on their own row.

**3.4.6 PayDirect collections import.** Status: IMPLEMENTED. `/finance/gateways` → "Quickteller PayDirect" → paste the day's report rows (PRN, amount, RRN — with or without a header) → **Import and match**: PRNs that match a portal reference are confirmed with channel "Quickteller PayDirect"; duplicates by (biller, RRN) are skipped; unknown PRNs are stored UNMATCHED ("No reference matching this PRN was generated by the portal"). Result: "Imported n: m matched, u unmatched, d already seen".

**3.4.7 Legacy fees and payment history imports.** Status: IMPLEMENTED. Old Fees History — `/finance/legacy-fees` (`bursar, super, admin`): template **Matriculation Number, Session, Semester, Amount Paid, Paid On, Receipt No, Note**; Amount blank = cleared in full against the schedule; preview then **Load n rows** (chunks of 500; idempotent on `MOAUM-LEG-…`); tiles Rows read / Settled / No such student / Nothing to settle. Payment History Upload — `/finance/payments-history` (`bursar, super, ict, admin`): template **Matriculation Number, Session, Amount, Purpose, Payment Date, Channel, Reference, Receipt No**; chunks of 400; a row already on record is skipped; no student is notified; a blank session files under LEGACY.

**3.4.8 NELFUND, wallets and funding sources.** Status: IMPLEMENTED. Sources & Wallets — `/finance/nelfund` (Bursary `bursar, admin, super`; Registry offices may match rows).

- **Load a remittance**: The Fund's reference (e.g. `NLF/2026/0918`), Received on, Note, and the rows (template **Matriculation Number, Name, Amount**, or pasted) → **Load and match**: each row is matched on the register; matched rows credit the student's wallet; unmatched rows go to **Suspense** owned by the Registry (no such number) or the Bursary (withdrawn/graduated/bad amount).
- **Suspense** (`?tab=match`): Registry offices **Credit** a row with "Number on the register" and one line of evidence; the Bursary **Reverse**s to the Fund with a reason.
- **The Fund's decisions** (`?tab=status`): paste number, name, decision (approved / not approved / pending), reason → **Load the list**; correctable refusals (BVN, institution code, name mismatch) are flagged so each student sees the field to fix.
- **Credit a student's wallet** (number, source, amount, reason) and **Reset wallet to zero** (confirm + reason; deletes every entry — destructive).
- **Withdrawals** (`?tab=withdrawals`): **Approve** / **Decline** (reason); a **different** officer **Mark paid** with the bank transfer reference — "the officer who approved a withdrawal does not also pay it". The portal records the payout; it does not move the money.
- **Sources** (`/finance/sources` or the tab): Code, Name, Nature (Loan — repaid / Grant — never repaid / Own money), Sponsor, Holding account, Sort order, Note; seeded NELFUND (LOAN), SCHOLARSHIP (GRANT), SELF.
- **Report** (`?tab=report`): funded, applied, withdrawn, held; by source; by nature; cash-flow reconciliation ("The wallet reconciles with school payments" or "does not reconcile — investigate"). No Excel/PDF export on any NELFUND tab.

**3.4.9 General ledger sync and books.** Status: IMPLEMENTED, unused so far (0 journals on the audited database); sync is manual. Accounting & Books — `/finance/accounting` (`bursar`, `super` post). The note "{n} transaction(s) not yet on the books" → **Post them now** (or **Sync**) posts every confirmed payment, paid refund and paid voucher once (`uq_gl_journal_source`); income categories map to accounts 4010–4090, voucher kinds to 5100–5900. Tabs: Overview (chart of 33 accounts), Trial balance (In balance / Out of balance), Income & expenditure, Balance sheet, Journal book (**Lines**, **Reverse** with a reason — a mirror journal), Account ledger. **New journal**: Date, Narrative, lines of Account + Debit or Credit (at least two; must balance; "A line names an account that is not on the chart."). Everything is cash-basis. No scheduler calls the sync.

**3.4.10 Fee setup, hostel/applicant/PG fees.** §2.8 and §2.15. The hostel fee is on the housing window; the Bursary confirms hostel references like any other, and a confirmed hostel reference confirms the bed.

**3.4.11 Reports.** Payments Query — `/finance/payments` (filters session, faculty, department, programme, level 100–600, category, channel, dates; **Export Excel** / **Export PDF**, serial PAY, S/N first — only the rows loaded on the page); Transactions & Accounts — `/finance/ledger` (day book by date range; "Export the journal" downloads a branded `.xlsx` despite the `.csv` name); College Payment Report — `/college/payments` (§3.8); Reports & Returns — revenue (day 10 monthly), funding, expenditure and income-expenditure returns; Held Scripts — `/finance/held-scripts` (read-only, no export).

**3.4.12 Also the Bursar's.** Payment vouchers (raise and pay, §3.5.2), Budget (`/finance/budget`: **Set a cost centre's budget** per financial year; commitment at voucher clearance), Tenders (`/finance/tenders`: open, record bids, score on the technical threshold, award — a lower responsive bid requires the Board's reason — cancel), Requisitions (approve, raise PO, close), Stores & assets (`/stores`), Payroll (read; build/approve is HRM's), Financial Clearance (sign the BURSARY unit at `/clearance`).

### 3.5 Internal Audit

**Dashboard — `/` (AuditDashboard for `audit` and `deputyaudit`).** The security posture (audit entries with shard count, unattached tables, failed sign-ins in 7 days, last audit entry), a 12-row recent-activity feed from the audit trail, and links. The Director's home menu item is **Payment Vouchers** (`/vouchers`).

**What Internal Audit reads.** Status: IMPLEMENTED (read-only over other modules).

| Screen | URL | What it shows |
|---|---|---|
| Audit Log | `/audit` | The audit trail (§6.2); `audit` and `deputyaudit` are in the OVERSIGHT guard |
| Revenue & Student Income | `/audit/revenue?session=` | Fees collected, confirmed today, still owed, open exceptions (from `/finance/bursary`) and revenue by category (from `/reports/revenue`); default session hard-coded `2026/2027` |
| Staff Movements | `/audit/staff` | The establishment and the pay runs (built by / approved by) — the title "Staff movements" is stale; the screen shows the roll and the runs |
| Assets Register | `/audit/assets` | `stores/assets` with "Never verified" and "Overdue verification" (> 1 year) tiles |
| Payroll Variance | `/payroll/variance?period=` | Joined / Left / Changed / Net change between consecutive runs |
| Ledger, Reconciliation | `/finance/ledger`, `/finance/reconcile` | The day book; and the reconciliation attestation, which audit may perform (`RECONCILERS`) |
| Reports & Returns, registers, statistics money figures | `/reports`, `/reports/students`, `/reports/staff` | Revenue, expenditure, income-expenditure returns; kept copies |

**3.5.1 Payment vouchers — the pre-payment audit chain.** Status: IMPLEMENTED. `/vouchers`. The Bursary raises (What it is for, Payee, Amount, Kind Salary/Contract/Overhead/Claim/Grant, Source IGR/SUBVENTION/TETFUND/GRANT/OTHER, Cost centre) → `PV/YYYY/NNNN` at WITH_DIRECTOR. The Director of Internal Audit (acting as `audit`) **Sign & advance**s → WITH_DEPUTY (acting `deputyaudit`) → WITH_AUDITOR (`audit` or `deputyaudit`) → CLEARED → the Bursary **Mark paid**. At any audit desk: **Query** (the finding and the office it is sent to — the voucher cannot move until **Answer query**), **Reject** (reason). No person acts twice in the chain (BR-006 by person); each desk is signed by its office ("this desk is signed by deputyaudit, not by audit"). Budget is consumed at clearance. There is no voucher PDF.

**3.5.2 Verifying assets.** `/stores` (Fixed assets tab) → **Verify** stamps today's date (`bursar, audit, deputyaudit, super`); the Assets Register desk itself is table-only.

### 3.6 Human Resource Management

**Dashboard — `/` (HrDashboard; title stale: "Staff movements").** Headline: "{n} leave request(s) awaiting a decision" (→ Open leave), else "{n} movement(s) are approved, awaiting an instrument" (→ Issue instruments), else "Nothing is waiting on the directorate". Tiles (links): Staff on the establishment → `/reports/staff`; Leave to decide → `/hr/leave`; Instruments to issue → `/hr/movements`; Open vacancies → `/hr/recruitment`. Panels "Leave to decide", "Movements awaiting an instrument", "HR desks" (the "Staff records" link goes to `/people/lecturers`, not `/staff`).

> **Warning — the honest status of HR and payroll.** The payroll engine (build, approve by a second officer, pay, cancel, payslip snapshots with 8% pension and PAYE bands, variance) is **IMPLEMENTED**, but **nothing in the API or the migrations inserts `hrm.employment`** — the establishment the payroll is built over is populated only by the demo seed. There is no screen to add a member of staff to the establishment, set a grade/step, bank or pension details; an APPOINTMENT movement requires an existing employment and cannot create one. Grades (`hrm.grade`: CONTISS 6/7/9/13/15 and CONUASS 1/3/5/7, steps 1–2) and leave types are seeded with no screen. Payroll is therefore **PARTIALLY IMPLEMENTED** as a University payroll, and there is no payslip PDF and no bank schedule. Leave self-service works only for a person with an ACTIVE employment.

**3.6.1 Staff records.** Staff Records — `/staff` (read-only establishment: Staff, Grade, Category, Monthly gross, Bank, Status; the name opens the whole-person staff record pop-up with offices, profile, teaching, leave); Staff register — `/reports/staff` (filters and a branded Excel of every `iam.person` with a staff number; §7); Upload Non-Academic Staff — `/people/staff` (§2.3.7); Department staff lists are the HODs'.

**3.6.2 Movements.** Status: IMPLEMENTED (RETURNED unused; no letter). Open a Movement — `/hr/movements`. **Open the movement** (`hrm, registrar, super`): Staff number, Movement type (17: Appointment, Confirmation of appointment, Promotion, Upgrading, Conversion, Transfer, Secondment, Acting appointment, Redesignation, Leave of absence, Sabbatical, Suspension, Reinstatement, Retirement, Resignation, Disengagement, Dismissal), Effective from, New grade and step (for Promotion/Upgrading/Conversion) or What it changes, Reason / minute → REQUESTED. A second officer (`hrm, registrar, dregistrar, vc, dvc, super`) **Approve**s or **Decline**s; then **Issue instrument** (`MOAUM/R/ACA/YYYY/NNNN`) makes it real from the effective date: promotions change grade/step; retirement, resignation, disengagement and dismissal end the employment; suspension suspends; reinstatement reactivates. "Approved is not implemented until the letter exists."

**3.6.3 Leave.** Leave Requests — `/hr/leave` (`hrm, hod, dean, dregistrar, registrar, super`; a HOD sees only staff whose home department is theirs). **Approve** (no confirmation) or **Decline** (reason). Balance is derived from approvals against the type's entitlement (ANNUAL 30, CASUAL 7, SICK 14, MATERNITY 112, PATERNITY 14, COMPASSIONATE 7, EXAMINATION 14, STUDY_PAID 1095, LEAVE_ABSENCE 365 unpaid); an annual approval that would exceed the balance is refused. No notice is sent on a decision.

**3.6.4 Payroll runs.** `/payroll` (`hrm`, `super`). **Build the run** (Month, Note) over everyone ACTIVE on the establishment → DRAFT ("{n} payslips built — gross ₦x, net ₦y"); a **different** HRM officer **Approve**s; **Mark paid** once salaries are disbursed; **Cancel** (reason) a DRAFT or APPROVED run. One non-cancelled run per month. Payslips (basic, allowances, gross, pension, PAYE, net) appear to staff on `/me` only when the run is APPROVED or PAID. Payroll Variance — `/payroll/variance`.

**3.6.5 Recruitment and appraisal.** Recruitment — `/hr/recruitment` (`hrm, registrar, super`): advertise a vacancy (Post, Department, Advertised criteria, Grade, Category, Closes on), record applications, **Score** and **Shortlist**; vacancy states are set by a free-text prompt and there are no Invite / Offer / Appoint buttons and no link from APPOINTED to an employment — **PARTIALLY IMPLEMENTED**. Appraisal & promotion — `/hr/appraisal` (`hrm, registrar, dean, hod, super`): the promotion view (years on grade, ≥ 3 years rule, APER, publications) and **Record the appraisal** (Staff number, APER grade A–E, Publications, Self score, Supervisor score, Note).

### 3.7 School of Postgraduate Studies

**Dashboards — `/`.** *Dean (pgschool):* a lead note ("{n} applications recommended by a faculty, awaiting the School" → Decide them; or "{n} applicants have accepted an offer, ready to admit" → Admit them), the statistics panel, tiles Applications / Awaiting the School / Offered / To admit / PG students, pipeline tiles (Active students, On research, Awaiting defence, Finishing, Graduation eligible, Graduated), "Latest applications", "By programme". *Secretary (pgsecretary):* "{n} items wait on the Secretary", tiles To register / Fees to confirm / Exams pending / Clearances, and lists of registrations to endorse, live fee references with a **Confirm fee** button (channel "bank"), and theses awaiting clearance.

> **Screenshot Required:** PG School dashboard — `/` (acting as Dean, School of Postgraduate Studies) — the lead note, the tiles and the pipeline tiles.

**3.7.1 PG calendar.** Status: IMPLEMENTED (windows are informational — nothing enforces the registration dates). Calendar — `/admissions/postgraduate/calendar` (`pgschool, pgsecretary, super`). **Setup new session** (Session `YYYY/YYYY`, Semesters 2 or 3, Opens, Closes, State PLANNED/CURRENT/CLOSED, Note); **Make current** (closes the previous CURRENT); **Set windows** per semester (Registration opens/closes, Lectures from/to, Exams from/to, Results due, State). Every PG desk defaults to the School's CURRENT session, else the University's. On the audited database no PG session is CURRENT — choose the session explicitly on each desk.

**3.7.2 Applications and decisions.** Status: IMPLEMENTED. Admissions — `/admissions/postgraduate` (readers `pgschool, pgsecretary, academic, registrar, dregistrar, dean, hod, dvc, vc, super`). Table with **Download Excel** (serial PGAPP, S/N first). **Details** opens the application: passport, bio-data, institutions, proposal, referees (with attestations once received), documents (**View all as one PDF**), notes from each desk, "A note for the decision", and the buttons by stage:

| Stage | Button | Who |
|---|---|---|
| SUBMITTED | **Department: recommend / Decline** | `hod` (own department), `academic`, `super` |
| DEPT_RECOMMENDED | **Faculty: recommend / Decline** | `dean` (own faculty), `academic`, `super` |
| FAC_RECOMMENDED | **Offer a place / Refuse** | `pgschool`, `pgsecretary`, `super` — emails "A decision on your MOAUM postgraduate application" (the applicant pays the checking fee to read it) |
| OFFERED | **Record acceptance** | SPGS (acceptance is otherwise settled by the applicant's confirmed acceptance fee) |
| ACCEPTED | **Admit onto the register** | `pgschool`, `pgsecretary`, `registrar`, `super` — writes the `people.student` row (admission number, entry mode POSTGRADUATE, level 700/800/900 by award), the contact, and the student account with the applicant's password; idempotent |

Declines are terminal; there is no reopen or appeal endpoint. Nothing notifies the HOD, Dean or School when an application arrives — check the desk. **Confirm fee** (Secretary's home, or `bursar`) confirms an application, checking or acceptance reference by hand; the gateway confirms the rest.

**3.7.3 Coursework.** Status: IMPLEMENTED. Courses — `/admissions/postgraduate/courses` (`hod, academic, pgschool, pgsecretary, super`): **Upload the course catalogue** (template `PG courses template.xlsx`: Programme, Course Code, Title, Units, Kind, Semester; units 0–12; kind Core/Elective/Research/Deficiency) or **Add a course**. Course Results — `/admissions/postgraduate/results`: per session/semester/programme, **Endorse registration**, CA and Exam per course → grade on the postgraduate scale (A 70+, B 60–69, C 50–59, F < 50; deficiency courses earn no credit; CA + exam ≤ 100 by CHECK). No department scope is applied on this desk.

**3.7.4 Research stages, panels and awards.** Status: IMPLEMENTED (supervisors/panel: add only — PARTIALLY IMPLEMENTED). Research Desk — `/admissions/postgraduate/research[?stage=]` (`pgschool, pgsecretary, super`). Per candidate: **Supervisors** (name, First/Second/Co, external), **Panel of examiners** (name, role Chair/HOD, External examiner, Supervisor, Co-supervisor, Internal examiner, PGSR, PG Coordinator), and **Advance** in order — Record proposal submitted → Approve proposal → Record seminar (+PGSR) → Register title (+Originality %, required) → Constitute panel → Record draft submission → Record viva (+Score %, outcome PASS_CLEAN / PASS_MINOR / PASS_MAJOR / SECOND_ORAL / FAIL) → Corrections required (+due) or Record final submission → Clear for binding → Recommend to Senate → Record Senate award. Out of order: "This record is at 'x'; y follows 'z'." **Withdraw candidate** is terminal. Documents submitted by the candidate are versioned; **Accept** / **Return** (what to correct). Every stage change emails the student.

Thesis Clearance — `/admissions/postgraduate/clearance` (Secretary): **Clear for binding** (plagiarism ≤ 20% shown green). School Board — `/admissions/postgraduate/board` (Dean): **Recommend**; **Record Award** enabled only after a **Senate minute** is typed — `pg_award` writes the graduand row, sets the student GRADUATED and emails "Senate has approved your award". The award button on the Research Desk sends no minute and always fails with `PG_AWARD_MINUTE`; use the Board page. An award needs a matriculated student.

**3.7.5 PG students, examiners roster, Secretary's read-only desks.** PG Students — `/admissions/postgraduate/students`: register with standing (Good ≥ 2.50 / Probation / New) and an **Action…** select (Defer, Withdraw, Reinstate, Readmit) that prompts for the instrument. External Examiners (School roster) — `/admissions/postgraduate/examiners`: list and **Appoint an examiner** (Name, Institution, Field, Tenure) — no edit, end or deactivate (PARTIALLY IMPLEMENTED); this roster is separate from the external-examiner workspace at `/examiners` (assignments, rubrics, activation) which the School also uses. Secretary: Registration (`/registration`), Course Examinations (`/examinations`), Results to Senate (`/senate`) — read-only summaries. Coursework and research desks have **no Excel/PDF exports**.

**3.7.6 PG fees.** §2.8.6 (`/finance/fees`, PG card; the Secretary's menu links there but the fee page's finance reads fail for that office — §1.7; the PG card itself calls the PG endpoint).

### 3.8 College of Health Sciences

**Dashboard — `/college/dashboard`** (Provost, College Secretary; the Finance Controller sees the Student Payment Report here). "Welcome, {name}"; the statistics panel; tiles **Students**, **Years open**, **Awaiting the Board**, **Postings this session**; "What waits on the College" (The Board, Results, Registration, Calendar, Senate, Appointment — each with **Open**); "The session by level"; "The rotation this session" (400 level up); "Fees this session" (first/second semester cleared, year registered); "Decisions confirmed most recently"; "The MBBS Coordinators" (level, holder, since; "Not appointed"); "The College's desks lately" (audit spine, 90 days). The separate `/api/v1/provost/dashboard` endpoint has **no screen** — CONFIGURED BUT UNUSED. **MBBS Coordinator dashboard — `/college/coordinator`**: the coordinator's level, cohorts, students, "What waits on you", results by subject.

> **Screenshot Required:** College dashboard — `/college/dashboard` — the tiles, "What waits on the College" and "The MBBS Coordinators" panel.

**3.8.1 College calendar.** Status: IMPLEMENTED. `/college/calendar?session=` (edit: `provost, collegesecretary, academic, registrar, dregistrar, admin, super`). Per level a table Semester / Weeks / Subjects / Starts / Ends → **Save**; **Date from the first semester** fills by the prospectus weeks; **Copy {previous}'s dates, a year on**; **Save all N**. An end before a start is refused. Results for a level open only once its last dated semester has started ("The N Level year … has not reached its final semester") — and an **undated** level is treated as reached, so date every level.

**3.8.2 Postings and logbooks.** Status: IMPLEMENTED. Postings — `/college/postings?session=&level=` (300 level up): pick a posting, tick students, Rotation group, Supervisor (College staff), Starts, Ends → **Allocate N students**; per allocation begin / complete / mark incomplete / **Withdraw** (only while ALLOCATED). Logbooks — `/college/supervision`: procedures (Observe/Perform, **Verify**), cases clerked, attendance (LECTURE/PRACTICAL/CLINICAL/TUTORIAL/TEST/OTHER), mandatory events — written by the supervisor or a desk office.

**3.8.3 Professional examinations and results.** Status: IMPLEMENTED. Professional Examinations — `/college/examinations?session=&exam=` (CPE at 200, PE1–PE4 at 300–600; subjects CA 30 / examination 70 / pass 50, clinical where set, attendance minimum 75 for CPE and PE1, 70 for PE2/PE3, none for PE4). **Open the year for a student** (matriculation number). Candidate panel: attempt (FIRST / RESIT / REPEAT / SENATE_APPEAL); per subject CA, Examination, Clinical, Attendance % → **Save the results** (barred and failed below the attendance minimum). Score Sheet — `/college/scoresheets`: **Download the score sheet** per cohort, **Upload the filled sheet** (preview with flags: not in the cohort, not fully registered, over range, attendance missing, clinical missing, barred), **Save**, **Download the marked sheet**. Examiners are the College's own departments (`COLLEGE_NOT_EXAMINER`); the MBBS Coordinator acts at their level only.

> **Warning:** The College score-sheet workbooks carry the letterhead of another university ("Moshood Abiola University of Science and Technology, Abeokuta", `ScoreSheets.tsx:18`) — a defect to be fixed before the exports are used officially.

**3.8.4 Board confirmation and appeals.** Status: IMPLEMENTED. When every subject of a candidate is resulted the rule gives a **provisional** decision (PROMOTE / GRADUATE at 600 / RESIT / REPEAT / WITHDRAW_ADVISED / WITHDRAW_REQUIRED / APPEAL at PE4). The desk may **Change the provisional decision** (only while provisional; Board minute; carry-overs GST/EPS only). On the examinations page, **Board minute** → **Confirm N decisions**: PROMOTE raises `current_level` by 100; RESIT keeps the year open as RESIT; WITHDRAW_* changes the student's status to WITHDRAWN citing the Board minute; GRADUATE sets GRADUATED, "with Honours" when every Professional carried a distinction. After a confirmed APPEAL at 600 level, **Record Senate's approval of the appeal** (Senate minute) opens the appeal attempt. The "ready for Senate" reconciliation is a read; nothing crosses to the University results chain. **No notice** reaches the student for any College decision — NOT IMPLEMENTED. The 100-level College rule (every non-GST course ≥ 50) is read-only advice; it records no withdrawal.

**3.8.5 Student Payment Report.** Status: IMPLEMENTED (V256). `/college/payments` (`financecontroller, provost, collegesecretary, bursar, registrar, dregistrar, academic, dvc, vc, super`): Academic session, Period (session or semester), Department, Programme, Level, Payment status (FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE), Search; **Excel** / **PDF** (serial CHSPAY, S/N first) for the report, the summary and by programme.

**3.8.6 Configuration the College cannot change on screen.** The examinations, subjects, assessment items, programme rule, levels, semester templates, blocks, postings, rotation groups, procedure requirements, attendance rules and mandatory events are seeded (V245/V248/V249) and read-only in the API — **NOT IMPLEMENTED** as administration; only the calendar is editable.

### 3.9 Housing

**Dashboard — `/hostel?session=`** (Accommodation desk; `housing`, `services`, `registrar`, `admin`, `super` act; bursar, dregistrar, academic, ict, audit, vc, dvc read). Window notice with state pill and, for officers, **Generate Allocation** (hidden once drawn or when MANUAL; disabled with no free bed or nobody approved) and **Lapse expired holds**; twelve tiles (Total beds, Occupied, Reserved, Available, Under maintenance, Students accommodated, Applications, Allocated, Waitlisted, Checked out, Pending clearance, Open maintenance), "Waiting at this desk" (applications to review, students to check in, transfer requests, checkout requests, clearances in progress, maintenance open), charts, and "Occupancy by hostel, in figures" with **Excel / PDF** (serial HST).

> **Screenshot Required:** Accommodation desk — `/hostel` — the window notice with Generate Allocation, the twelve tiles and "Waiting at this desk".

**The lifecycle desk, in order.** Status: IMPLEMENTED (V261; end-to-end tested).

1. **Inventory and window** (§2.15); open the window.
2. **Applications & Waitlist — `/hostel/applications`**: filters by standing, faculty, department, programme, level, search; per row **Approve**, **Reject** (reason), **Correction** (reason; the student withdraws and applies again), **Withdraw**, **History**, **Allocate** (a named free bed with a reason — "Every check the allocation run makes is made here"); bulk **Approve N / Waitlist N / Reject N**; **Download Excel / PDF** (17 columns). Review is needed only when the window says so.
3. **Generate the allocation** (dashboard): the preview says how many are eligible, seated and waitlisted; a BALLOT needs a **Published seed** of at least six characters; priority categories go first, then the method's order; a bed is picked preferring the hall, room type and block asked for; those who find no bed are UNSUCCESSFUL with a draw position. A draw runs once per session; late applicants are seated by hand.
4. **Holds**: a fee > 0 makes a HELD allocation with `held_until` = allocated + hold hours; the student generates the payment reference and pays; the Bursary or gateway confirms and the bed is CONFIRMED. The hourly clock (or **Lapse expired holds**) lapses unpaid holds and offers the bed to the next name.
5. **Occupancy & Check-in — `/hostel/occupancy`**: Beds board, Students, To check in, Checkout requested; **Excel / PDF**. Open an allocation (`/hostel/allocations/{id}`): **Check in** (Condition Good/Fair/Damaged, Remarks — refused on a hold or before the student accepts under the rules), **Transfer** (free bed, reason), **Cancel** (reason; not once checked in), **Raise a damage charge** (Asset, Damage, repair/replacement cost, Charge to the student — above zero becomes a payment reference on the student's fees page), **Checkout inspection** (condition, cleanliness, keys and access card returned, damages, remarks — opens the clearance).
6. **Checkout & Clearance — `/hostel/clearance`**: tabs Clearances, Checkout requests (**Inspect**), Transfer requests (**Decide**: bed to move to, or reason), Maintenance (**Update**: Raised/Assigned/Fixed/Closed, priority, assigned to, note). On the allocation page decide each of the nine requirements **Clear / Hold / Waive / N/A** (remarks required for Hold and Waive; settling a charge marks its item), **Complete clearance** when nothing is PENDING — CLEARED ends the stay and writes the HOSTEL unit of the convocation clearance; NOT_CLEARED writes a HELD item naming what is outstanding and may be **Reopen**ed later. **Excel / PDF** per tab.
7. **Student accommodation history — `/hostel/students/{id}`** and the write-once trail on every allocation.

Every turn emails and texts the student, and the desk (every holder of `housing` or `services`) is emailed on applications to review, fee confirmations, declines, transfer and checkout requests and maintenance.

> **Warning:** The porter's verification page `/verify/hostel/{ref}` is public, un-throttled and has no check token; the `ALC-YYYY-NNNNN` reference is sequential, so names, photographs and room numbers can be enumerated. Raise this with ICT before printing letters at scale.

### 3.10 Documents office

The V262 digital-documents system is worked by the Registry and Exams and Records officers. Guards: readers `academic, registrar, dregistrar, records, dvc, vc, bursar, ict, admin, super, audit`; OFFICE (start, generate, QC, cancel, complete, deliveries, resend, clear flag) `academic, registrar, dregistrar, records`; SIGNERS (release, reissue, issue certificates) `registrar, dregistrar, academic`; REVOKERS `registrar, vc`; CONFIG `registrar, dregistrar, academic, super`.

**Dashboard — Documents Office `/credentials/documents`.** Tiles, each a filtered link: New requests (paid, not started), Payment pending (₦ outstanding), Held at clearance, Processing, Quality check, Awaiting release, Ready for delivery, Delivered, Breaching SLA, Certificates issued (N graduates awaiting), Transcripts issued, Revoked · reissued · flagged. Charts: Requests by stage; Verification and downloads in 30 days ("suspected forgeries" = codes checked three or more times that were never issued); Revenue by document kind; Processing (average days payment → release). Panels **Graduates awaiting a digital certificate** and **Documents flagged after the record changed**.

> **Screenshot Required:** Documents office — `/credentials/documents` — the twelve tiles, the charts and the "Graduates awaiting a digital certificate" panel with Issue buttons.

**3.10.1 The request pipeline.** Status: IMPLEMENTED. Document requests — `/credentials/documents/requests` (filters Stage, Document, Payment, Delivery, Faculty, Department, Programme, Search; **Excel / PDF** "Document Requests", 16 columns) → **Process / Check / Release / Deliver / Open** → the request page `/credentials/documents/requests/{id}`:

| Stage | Act | Rule |
|---|---|---|
| AWAITING_PAYMENT | (wait) | Payment confirmation stamps the SLA due date; nothing starts before `paid_at` |
| READY / HELD_AT_CLEARANCE / CORRECTION | **Validate the record** | Findings: ERROR — no matric number, programme not on the list, EXPELLED/RUSTICATED, no published result, certificate not GRADUATED / no Senate award / convocation clearance incomplete, transcript clearance incomplete; WARNING — unpublished registered courses, not yet graduated, award not approved. Held at clearance until the unit clears the student |
| PROCESSING (validation ok) | **Generate the document** | Builds the statement from the authoritative record, numbers it `PREFIX/YYYY/NNNNNN` vN, hashes it |
| GENERATED | **Quality check** — Approve / Request correction / Reject (note) | Correction regenerates as a new version |
| VERIFIED | **Authorise and release** (signers) | **The officer who produced the document may not release it** — the button is disabled for the producer. Opens the deliveries: the student's token (50 uses, 30 days), a recipient email link (10 uses, 30 days), a courier record |
| RELEASED | **Update** a physical delivery (state, courier, tracking), **Resend link** for an email delivery | Every delivery DELIVERED (or the student's token spent) → DELIVERED |
| RELEASED / DELIVERED | **Mark completed** | |
| AWAITING_PAYMENT / READY / HELD | **Cancel** | Also the student's right |

The student is emailed and texted at each turn; the desk is emailed for a free non-self-service request and on a delivery failure. Free self-service kinds (mini-transcript, statement of record) are generated and released at once without the desk.

**3.10.2 Degree certificates — single, bulk, revoke, reissue.** Status: IMPLEMENTED. On the office dashboard, "Graduates awaiting a digital certificate" lists graduated, Senate-approved students with no active certificate; **Issue** (signers; cleared only) or tick and **Issue N certificate(s)** — the run is all-or-nothing ("One that fails the checks stops the run"). Gates: GRADUATED, Senate-approved award, convocation clearance complete; "an active degree certificate already stands; revoke or reissue it". The PDF follows the University's own certificate layout with a QR and the verification code. Revoke (Registrar/VC, minute) and Reissue (signers, reason) are on the register (§3.1.6). A published result or an award change after issue **flags** the document ("A result of the student changed after issue"); **Review** then **Clear the flag** or reissue.

**3.10.3 Register and verification log.** Issued documents — `/credentials/documents/register`: tabs **Documents** (kind, number, version, flagged pill, holder, status Valid/Revoked/Replaced, code, downloads and verifications; **PDF** per document, logged as an office download; **Excel / PDF** "Issued Documents") and **Verification log** (When, Key, Result, Document, Holder, Source IP; PDF "Document Verifications"). Public verification is at `/verify/document/{key}` (code or number; 40 lookups per 15 minutes per IP; every lookup logged; answers VALID / REVOKED / REPLACED / NOT FOUND / INVALID with the policy's public fields only).

**3.10.4 Policies and templates.** §2.14.

**3.10.5 The legacy transcript queue.** §3.3.6 — kept beside the pipeline; its produce is generation and verification in one act, so its release still follows.

**3.10.6 The printed certificate register and stationery.** Status: IMPLEMENTED. Certificates — `/credentials/certificates` (academic, records, registrar): **Print a certificate** (Graduand from the awaiting list, Stationery batch — the next unused serial is taken) → `MOAUM/C/YY/NNNNN` PRINTED; **Collected**, **Hold** (reason), **Reissue** (signers; "carries the affidavit and police report reference"); **+ New batch** (Batch, Received on, First serial, Last serial), **Spoiled one**. The stationery "return" endpoint has no button; the certificate REVOKED status is never set.

**3.10.7 Identity cards.** Status: IMPLEMENTED (issue and report lost) — `/credentials/idcards` (issuers `library`, `security`, `super`): "Waiting for a card" (matriculated students with no live card; released by the ID_CARD clearance rule — at the first instalment under the recommended scheme) → **Issue the card / Issue a replacement** (`MOAUM/ID/YY/NNNNN`, valid four years); **Report lost**. There is no printing, no collection record and **no card verification** ("Verify a Card" is a menu item without a page). The staff card PDF (`/staff/idcard/pdf`) is stateless — nothing is stored.

### 3.11 ICT Directorate

The Director of ICT (`ict`) and ICT Support Agents (`ictagent`) work two things: the help desk, and the platform itself. `ict` also holds the structure uploads (§2.5–2.6), the People console (§2.3), gateway keys (§2.9), mail and SMS (§2.10), Post-UTME check-in (DOOR) and the migration desk.

**Dashboard — `/` (PlatformDashboard for `ict` and `super`).** Student statistics; course-structure upload coverage (tiles and two panels from `/catalogue/upload-coverage`); "People and access" (people on record, with a sign-in, live grants, grants ending within 30 days; **+ New person**, **+ Grant an office**, **Open the people console**); tiles **The service** (up/down, commit), **The database** (reachable, migrations applied, latest), **2025/2026 admission settings** (a hard-coded label from the prototype health check), **Acting as**; "What is actually true" (Service, Started, Latest migration, Actor, Acting office, Offices held, `API_URL`); "The outbox" (email/SMS provider wired?, waiting / sent / failed / sent in the last day, the recent 50); "Danger zone — reset uploaded data"; a closing note "How attribution works".

> **Screenshot Required:** Platform dashboard — `/` (acting as Director of ICT) — "What is actually true", the outbox panel and the Danger zone.

**3.11.1 The help desk queue.** Status: IMPLEMENTED (V251; email only; end-to-end tested). ICT Support Desk — `/helpdesk` (agents `ictagent, ict, admin, super`).

KPI tiles: **Total tickets**; **New** (SUBMITTED); **Opened**; **In progress** (+ reopened); **Unassigned**; **High priority**; **Overdue** ("N past first response · N escalated" — against the SLA hours by priority); **Average resolution** ("First response … · N% within SLA"). "With you" (the agent's own, by due); filter bar (Search — number, subject, name, matric/staff number, email, payment reference; Status; Category; Priority; Agent; Raised from/to); the queue sorted by Updated / Raised / Priority / Status / Due / Number; **Take** (self-assign an unassigned ticket) and **Open**; "Lately on the desk"; Director-only "Agent workload" and "Tickets by category".

> **Screenshot Required:** ICT Support Desk — `/helpdesk` — the KPI tiles, the filter bar and the queue with Take / Open.

**Working a ticket — `/helpdesk/tickets/{id}`.** Opening the page **opens** a SUBMITTED ticket (OPENED; the requester is emailed).

| Act | Rule / effect |
|---|---|
| **Accept the Ticket / Take It Over**, **Assign to an Agent / Reassign** (agent, note) | Only a holder of `ictagent`/`ict`/`admin`/`super` can be assigned ("only an ICT Support Agent or the Director of ICT takes a ticket"); the agent is emailed; refused on a CLOSED ticket |
| **Start Work** | OPENED / REOPENED → IN_PROGRESS; sets the first-response time |
| **Escalate** (to another agent, director first; reason ≥ 5) | Records a person; does not change the assignment; the person is emailed |
| Priority select | Low / Normal / High / Urgent (the category's suggestion at submission) |
| **Internal Note** / **Update to the Requester** | Notes are seen by the desk only; updates are emailed to the requester and shown on their ticket; attachments may be marked internal (PDF/JPEG/PNG ≤ 5 MB, sniffed; ≤ 10 per ticket) |
| **Resolve** (summary ≥ 5, details ≥ 20) | IN_PROGRESS → RESOLVED ("a ticket is resolved from in progress" — start work first); the requester is emailed and may **Confirm Resolution** or **Reopen** |
| **Close as Resolved** | RESOLVED → CLOSED, reason "Closed by the desk after the resolution" |
| **Close on a Reason** (≥ 5) | Any non-closed status → CLOSED |
| **Reopen** (reason ≥ 5) | RESOLVED or CLOSED → REOPENED; the assigned agent (else every agent) is emailed |

The ticket history is written once. The auto-closer closes RESOLVED tickets after the configured quiet spell (off by default). A requester may hold at most ten open tickets. Satisfaction rating is **NOT IMPLEMENTED** — the requester's confirm-or-reopen is the only signal.

**Reports — `/helpdesk/reports`.** Filters (Raised from/to, Category, Priority, Agent, Faculty, Department); tiles Tickets, Overdue, Average first response, Average resolution (% within SLA); monthly volume (raised vs resolved, 12 months); breakdowns by status, category, priority, requester kind, faculty, department; "Tickets by agent"; "The SLA in force". **Download the Report** is a plain **CSV** (not the branded Excel).

**Public tracking — `/track`.** Ticket number + the email the ticket was raised with; throttled to 12 lookups per 15 minutes per IP and per email; shows standing and non-internal history, no names.

**3.11.2 Platform status, migrations, readiness.** `GET /api/v1/platform/status` (public: service, commit, started at, database reachable, migrations applied, latest migration) feeds the dashboard tiles. Data Migration — `/migrations` (guard `ict, admin, super`; menu: super): tiles Migrations applied / Latest / Running commit / Started; the ledger `public.schema_migration` (filename, applied, by, checksum). Its second note says a legacy data migration "is not shown here because none has been run" — the legacy console is **PLACEHOLDER**. Go-Live Readiness — §2.20.

**3.11.3 Sessions.** There is **no screen** to list or end sessions. The API offers a person their own sessions (`GET /api/v1/auth/sessions`, `POST …/{id}/end`) with no page — PARTIALLY IMPLEMENTED; ending another person's session is NOT IMPLEMENTED. The practical control is the **session floor**: every restart of the API refuses every earlier session ("The portal was updated. Sign in again."). Sign-in defence figures are on `/security` (§3.12.4).

**3.11.4 Mail, SMS and the outbox.** §2.10–2.11. Failed notices are requeued from `/notices`; a stuck outbox is diagnosed in §8.

**3.11.5 Structure uploads and legacy migration.** §2.5–2.6; Migrate from Old Portal — `/records/migration` (ict, records).

**3.11.6 Data reset and demo removal.** Status: IMPLEMENTED (single officer, typed word, reason). On the platform dashboard, "Danger zone — reset uploaded data" (`super`, `ict`): **Remove demo courses only…** and **Remove demo data only…** (type `REMOVE DEMO`), **Reset ALL uploaded data…** (type `RESET` and a reason). `platform.reset_operational_data` attributes every deletion to the actor; there is no second approver and no undo.

**3.11.7 Release, Disaster Recovery and Cloud pages — their true status.**

| Page | URL | Status |
|---|---|---|
| Release Pipeline | `/release` | **PLACEHOLDER** — static text; "does not surface its own live build or deploy status"; calls only `/iam/me`. CI (`.github/workflows/ci.yml`) and Railway's "Wait for CI" are the real pipeline (*03 Technical Documentation*) |
| Disaster Recovery / Backups & Recovery | `/disaster-recovery` | Drill log **IMPLEMENTED** (§6.8); the "Recovery objectives" table (RPO ≤ 15 min, RTO ≤ 4 h, nightly restore verification, daily off-site replication, two drills a year) is **typed in the page, not measured**; backup telemetry NOT IMPLEMENTED — the page says so |
| Cloud Readiness | `/cloud` | **PLACEHOLDER** — static notes, "not wired to live … telemetry" |
| `/ethics` | (no menu) | **PLACEHOLDER** — two static panels |

**3.11.8 Security Posture — `/security`** (ict, admin, super, vc; API also audit, deputyaudit, security, registrar, dregistrar, dvc). Tiles Audit entries (with shard count), Unattached tables, Failed sign-ins 7 days, Last audit entry; "Sign-in defence" (staff events only); "Accounts drawing failed attempts". The panel text "verified nightly across every shard… A nightly job recomputes the chain" is **not true** — no such job exists (§6.5).

### 3.12 Super Administrator and System Administrator

`super` shares the Platform dashboard with `ict`; `admin` has its own home, the **Administrator Dashboard** — `/admin` (the institutional read model with a Scope row — The University / each faculty — re-cutting tiles Students, Result sets past Senate, Collected this session, Fees outstanding; the "Academic pipeline" donut with links Chase the chain / To Senate / Unraised sheets; the "Money" table; "By faculty" bars), plus Go-Live Readiness and the Institutional Overview.

> **Screenshot Required:** Administrator dashboard — `/admin` — the Scope row, the tiles and the Academic pipeline donut.

**3.12.1 Accounts and offices.** Users & Roles — `/people` (§2.3). `admin` and `super` are grantors and credential setters; ICT holds the two bulk loaders. **There is no two-person rule on grants** (§1.5).

**3.12.2 Sessions and the calendar.** Session & Semester Setup — `/calendar` is on the `super` menu (§2.4). For sign-in sessions see §3.11.3.

**3.12.3 Audit trail.** Audit Log — `/audit` (§6.2). `super`, `admin`, `ict`, `vc`, `audit`, `deputyaudit` may read it; the Registrar's menu item is refused by the guard.

**3.12.4 Security page — claims that are not true.** On `/security`: the audit chain is **not** verified nightly (only `db/check.sql` calls `audit.verify_chain`); "Unattached tables > 0" on a developer database is integration-test residue in `public`, and should be 0 on production. On `/audit`: the closing note claims refused database writes are on the trail — they are not (a refused write is rolled back with its audit row; only explicit `REFUS…` actions and failed sign-ins appear). On `/api-keys`: "rate-limited" and "scoped" are stored, not enforced. On `/disaster-recovery`: the objectives are typed text.

**3.12.5 API keys.** §2.18. **3.12.6 Notification Channels.** `/notices` (§2.11). **3.12.7 Data Migration.** `/migrations` (§3.11.2). **3.12.8 Backups & Recovery.** `/disaster-recovery` (§6.8). **3.12.9 Governance.** `/governance` (§2.19). **3.12.10 Help desk.** The System Administrator is an agent and a Director for settings (§3.11.1, §2.16).

**3.12.11 Where `admin` differs from `super`.** `admin` is on more menus (39 items against 30) but on fewer guards: it reads rather than acts in course registration, matriculation, results, documents, transfers, the CBT bank and clearance, and is not a calendar writer, not a hostel actor beyond the write guard it does hold, and not in the structure `UPLOADERS`. Consult the per-office summary in *04 Role and Permission Matrix* before assuming an act is available.

### 3.13 Vice-Chancellor and Deputy Vice-Chancellor (oversight)

**Institutional Overview — `/overview?session=&sem=`** (VC home; also admin, dvc, registrar): the statistics panel; tiles Students on the register (ACTIVE), Result sets expected, Past Senate (%), Never submitted; Returns overdue / due within 30 days; donuts "Where the n result sets stand" and "Students by level"; "Results by faculty" (with the faculty furthest behind named); "The semester week by week"; "Students by faculty"; the grade spread A–F with a note when F ≥ 15%. KPI definitions: results per faculty over MAIN-kind examination sessions — expected = sheets, submitted = stage ≠ ENTRY, approved = PUBLISHED; grades = latest score per (sheet, student) on PUBLISHED sheets, banded at 70/60/50/45/40 after the grace mark.

**What the VC acts on.** Senate Business — `/results/approvals` (read; the minute is the Registrar's); Graduation (read); Audit Trail, Data Governance (read), Security Posture; Budget (read); revoking a digital document (with the Registrar); HR movement approvals (`vc`, `dvc`); transfers (`dvc` in the legacy Senate path only — no screen). The DVC additionally reads the Senate Schedule, Result Pipeline and Broadsheets, and Deferments are on the DVC's list since V264: the DVC gives the final approval of forwarded applications with a comment (`/deferments`, tiles Pending approval · Approved · Rejected · Returned · Total received). Neither office can keep or file a return except through the snapshot readers' guard, which both hold.

> **Screenshot Required:** Institutional overview — `/overview` — the tiles and the "Where the result sets stand" and "Results by faculty" panels.

---

## 4. Periodic administration

### 4.1 New session setup checklist

| # | Act | Screen | Office | Notes |
|---|---|---|---|---|
| 1 | Create the session (Opens, Closes, Semesters) as PLANNED | `/calendar` | academic / registrar / dregistrar / super / ict | No overlap with any session, including test residue |
| 2 | Record the Senate minute and make it CURRENT | `/calendar` → Edit → State Current | same | Closes the previous CURRENT in the same transaction |
| 3 | Create the semesters with windows; open the first | `/calendar` → + New semester | same | Registration opens/closes, late registration closes, examinations, sheets due |
| 4 | Roll the register into the new session | `/calendar` → Roll into <session> | same | Promotes continuing students one level; idempotent |
| 5 | Enrol all into the session | `/calendar` → Enrol all | same | Creates `people.enrolment` rows the degree audit and finalist lists depend on |
| 6 | State the fee schedule (or upload the approved structure); confirm the clearance scheme is still in force | `/finance/fees` | bursar / super | "No charge is stated" blocks every payment |
| 7 | State applicant, PG and hostel fees for the session | `/finance/fees`, `/hostel/window` | bursar; housing | Defaults apply for applicant and PG fees; the hostel window must exist |
| 8 | Open course registration for semester 1 | `/catalogue/upload` → Open course registration | ict (button); others by API | Creates the offerings students register on |
| 9 | Allocate teaching (HODs) | `/allocate` | hod / dean / academic / Registry / admin / super | Needed before an examination session generates sheets |
| 10 | Admission settings for the coming intake in force; matriculation configuration checked | `/admissions/settings`, `/matriculation/config` | academic / Registry | Badges "!" on the Academic Office menu |
| 11 | PG calendar session and semesters; make current | `/admissions/postgraduate/calendar` | pgschool / pgsecretary | Every PG desk defaults to it |
| 12 | College calendar: date every level's semesters | `/college/calendar` | College desk | An undated level lets results in at any time |
| 13 | Help desk, mail, SMS, gateways still wired | `/readiness` | admin / ict | Read the gates |

### 4.2 New semester

1. `/calendar` → **Edit windows** on the semester → State **Open**; registration opens/closes; late registration closes (this date also lapses held scripts); examinations from/to; score sheets due.
2. `/catalogue/upload` → **Open course registration for a session** for the semester.
3. When examinations approach: `/examinations/sessions` → **Create an examination session** (MAIN) and **Open the session** — after allocation, so that sheets generate.
4. At the end: set the semester State **Closed** on `/calendar`. Voluntary-withdrawal counting (`registration.closed_semesters`) reads closed semesters.

### 4.3 Admission cycle

§3.2.1 in order: settings in force (CAC minute) → load cut-off → CAPS lists loaded and committed → candidate data → screening (CBT or scores) → release scores → merit lists recorded → decisions released (or JAMB's status list) → intake to the register → acceptance and clearance (applicant side) → the new students appear on the faculty lists once they register and pay.

### 4.4 Matriculation

1. Confirm the configuration: `/matriculation/config` warns "N programme(s) are set to carry a code and have none"; every series active; the Registry has given codes to any new programme.
2. Faculty Officers confirm their lists (`/matriculation/faculty/{code}`) after queries are cleared.
3. The Academic Office or the Registry runs the session (`/matriculation` → **Run matriculation for N students**); stragglers by **Issue number** later.
4. The issued numbers are on the write-once history; the students are emailed and texted; identity cards can now be issued (`/credentials/idcards`) once the ID_CARD clearance rule is met.

### 4.5 Results processing calendar

| When | Act | Screen | Who |
|---|---|---|---|
| Before examinations | Open the MAIN examination session (dates, sheets due) | `/examinations/sessions` | records / academic / Registry |
| During marking | Lecturers enter or upload marks and **Submit and attest**; held scripts for unregistered candidates | `/results/sheets/{id}` | lecturers |
| Sheets due | Read the Submission monitor; chase late sheets by other means (Remind is a placeholder) | `/examinations/sessions` | records |
| Chain | VERIFICATION (exams) → DEPT_BOARD (hod) → FACULTY_SCRUTINY (facultyexams) → FACULTY_COMPILATION (facultyofficer) → FACULTY_BOARD (dean) → RECORDS (records) → SENATE | `/results/desk`, `/results/approvals`, `/results/chain` | each desk |
| Senate | Record the minute; sets refused for BR-006 are re-recorded by another holder of the office | `/results/senate`, `/results/publish`, `/results/approvals` | registrar / dregistrar |
| After publication | Result queries answered within the 7-day window (a CORRECTED query has no mechanical correction path — a PUBLISHED sheet cannot be returned or amended); RESIT / SPECIAL sessions for candidates who failed or were absent | `/results/queries`, `/examinations/sessions` | hod / exams; records |
| Documents | Flagged transcripts reviewed when a result changes after issue | `/credentials/documents` | documents office |

### 4.6 Graduation and certificates

1. `/calendar` — the graduating session's finalists need `people.enrolment` rows (roll-over / enrol-all).
2. `/graduation` → **Run the degree audit** → review exceptions → **Send the list to Senate** with the minute (students become GRADUATED and are told).
3. Convocation clearance: each unit clears or holds on `/clearance` (BURSARY, DEPARTMENT, FACULTY, LIBRARY, HEALTH, HOSTEL, WORKS, ALUMNI); the hostel clearance writes its own HOSTEL item.
4. `/credentials/documents` → **Issue N certificate(s)** (digital, all-or-nothing) and, for paper, `/credentials/certificates` → **Print a certificate** against a stationery batch; **Collected** on hand-over.
5. Alumni register (`/alumni`) lists the Senate-approved graduands.

### 4.7 Hostel window per session

`/hostel/window` (create with the fee, hold hours, dates, method, eligibility, rules; **Save and open applications**) → review (`/hostel/applications`) → **Generate Allocation** (seed for a ballot) → holds, payments, acceptance → check-in → at the end of the stay checkout inspections, charges, clearance → **Save and close applications** was done at the draw; the next session gets a new window. Inventory changes (closed rooms, maintenance) at any time with the affected occupants transferred.

### 4.8 Statistics and the returns due register

Reports & Returns — `/reports?session=`: the **Due register** lists every return with Owner, Frequency, Last due, Next due and State (Overdue · n days after a 14-day grace; Due; Kept · not filed; Filed; On demand). Seeded schedule (`reports.catalogue`): admissions 31 Dec (registrar), enrolment 31 Dec (registrar), registration 31 Mar and 31 Aug (registrar), carryovers 31 Oct (records), staff-ratio 31 Dec (hrm), postgraduate 30 Nov (pgschool), revenue day 10 monthly (bursar), funding 31 Dec (bursar), expenditure and income-expenditure day 10 monthly (bursar); students and staff registers on demand. For each: **Run** → the branded document → **Keep a copy** (a snapshot with a verification code checkable at `/verify/report/<code>`) → **Mark as filed** (Filed with: NUC / JAMB / Council / State treasury / Senate / Management / School Board; once only) → **Email this return** (1–20 addresses; PDF and workbook attached; needs the outbox provider). Deans, Faculty Officers and HODs run and read returns cut to their scope but cannot keep a copy. No reminder is sent for a due return — NOT IMPLEMENTED; read the register. Student Statistics (`/stats`) is live and cached 60 s per scope.

### 4.9 NDPA return

The Registrar dashboard's note that the NDPA Compliance Audit Return is due on 31 March is static text; the portal holds the material for it on `/governance` (the processing register with DPIA states and the DSR log with due dates) and on `/audit`. Complete outstanding DPIAs (**Mark done**), close data-subject requests (**Start** / **Complete**), and export nothing — the governance screen has no export beyond the table's Print button.

---

## 5. Configuration guide

Every configurable item found in the audit, in one table. "Screen" means an administrative page edits it; "migration" means only ICT can change it by a new migration file; "env" means a service variable on the API (names only). Seeded values are those of V001–V263; where the audited database differs (demo issues, test residue) the seed is given.

| Item | Where | Who | Default / seeded value | Notes |
|---|---|---|---|---|
| Offices (`ref.office`) | migration | ICT | 34 rows (32 staff + applicant + student) | `verify.sql` asserts 34 |
| Units and unit spellings (`ref.unit`, `ref.unit_alias`) | migration | ICT | seeded register | Used by the non-academic staff loader; "ended, never deleted" |
| Colleges, faculties, departments, programmes (`ref.*`) | `/structure/*` | `ict` | seeded structure (12 faculties, 1 college) | Programme code `^C[0-9]{5}$`; category UNDER/POST GRADUATE; archive keeps the code |
| JAMB course aliases (`ref.jamb_alias`) | `/admissions/caps` AliasMapper | academic, registrar | seeded names | Programme's JAMB alias |
| Academic sessions | `/calendar` | academic, registrar, dregistrar, super, ict | none CURRENT on the audited DB | One CURRENT; minute required; no overlap |
| Semesters and windows | `/calendar` | same | — | States NOT_YET_OPEN/OPEN/CLOSED; late-registration date drives add/drop and held-script lapse |
| Level unit limits (`policy.level_limit`) | `/calendar` | same | 100–400 18–24; 500/600 18–24; 700 9–48; 800 6–48; 900 0–48; probation ceiling NULL | Select offers 100–600 only |
| Curriculum tracks (`policy.curriculum_track`) | migration | ICT | BMAS, CCMAS_BSU, CCMAS_MOAU | Assigned to students by trigger (`people.track_for`) |
| Grading scheme, classification bands, policy versions | migration | ICT | SEN/2015/44 bands (§2.7) | No screen; grades computed at `current_date` |
| Clearance scheme | `/finance/fees` → Put the recommended scheme in force | bursar, super | demo `BUR/DEMO/1` from 2026-09-25 | Only the recommended rule set from the screen; no overlap |
| Fee schedule lines | `/finance/fees` | bursar, super | 6 live lines (demo) | Filters level / entry mode / faculty / programme / fee group / semester / indigene / spillover |
| Fee groups and fee items (`ref.fee_group`, `ref.fee_item`) | migration | ICT | UG, PG, GST, EPS; 17 items | — |
| Home state for indigene fees (`finance.fee_setting.home_state`) | migration | ICT | Benue | — |
| Transfer processing fee (`finance.fee_setting.transfer_fee`) | `/finance/fees` | bursar, super | NULL (no default) | Transfers cannot be paid until set |
| Applicant fees (`admissions.applicant_fee`) | `/finance/fees` | academic, registrar, dregistrar, bursar, ict, admin, super | 2,000 / 300 / 25,000 / 0 when unstated | Per session |
| PG fees (`admissions.pg_fee`) | `/finance/fees` | bursar, pgsecretary, pgschool, super | 20,000 / 50,000 / 3,000 when unstated | Per session |
| Hostel window (`hostel.session_setting`) | `/hostel/window` | housing, services, registrar, admin, super | none seeded; hold 72 h; BALLOT; review off; waitlist on; refuse debt on | Rules text versioned |
| Hostel inventory (halls, blocks, rooms, beds, assets, facilities) | `/hostel/inventory` | same | none seeded | Hall kinds, room types, facility codes, clearance requirements seeded by migration only |
| Hostel hold clock (`moaum.hostel.cron`) | env/property | ICT | `0 5 * * * *` Africa/Lagos | — |
| Payment gateway keys (`finance.gateway_credential`) | `/finance/gateways` or env `MOAUM_PAYSTACK_SECRET`, `MOAUM_FLUTTERWAVE_SECRET`, `MOAUM_FLUTTERWAVE_HASH` | ict, admin, super | none | Encrypted with `MOAUM_CONFIG_KEY`; never shown |
| PayDirect billers (`finance.paydirect_biller`) | `/finance/gateways` | bursar, ict, admin, super | MAIN 04255101; CHS 04263001 | Routed by College |
| Sweep interval (`moaum.payments.sweep-every-ms`) | property | ICT | 600,000 ms | — |
| Chart of accounts (`finance.gl_account`) | migration | ICT | 33 accounts | GL sync is manual |
| Funding sources (`finance.funding_source`) | `/finance/sources` | bursar, admin, super | NELFUND (loan), SCHOLARSHIP (grant), SELF | — |
| Budgets per cost centre | `/finance/budget` | bursar, super | none | Cost centres are free text |
| Mail server (`platform.mail_settings`) | `/platform/mail` | ict, admin, super | office365 hosts/ports; no account | Needs `MOAUM_CONFIG_KEY` |
| SMS gateway (`platform.sms_settings`) | `/platform/sms` | ict, admin, super | eBulkSMS; disabled | Sender ≤ 11 |
| Notice relays and cadence | env `MOAUM_NOTICES_*` | ICT | every 60 s, first after 15 s | — |
| Portal URL for links (`MOAUM_PORTAL_URL` / `moaum.portal-url`) | env | ICT | the Railway production URL | Reset links, referee links, tracking line |
| Auth secret, config key (`MOAUM_AUTH_HMAC_SECRET`, `MOAUM_CONFIG_KEY`) | env | ICT | — | HMAC secret ≥ 32 bytes or the API refuses to start |
| SSO (`MOAUM_SSO_*`) | env | ICT | unset — button hidden | Coded, not deployed |
| Session length, lockout, password minima | code constants | — | 12 h; 5 failures / 15 min; staff 10, student/reset 8 | Not configurable |
| Matriculation format (`people.matric_format`) | `/matriculation/config` | academic, registrar, dregistrar, super | MOAU; faculty, programme, year, sequence on; `/`; padding 0 | Single row |
| Matriculation series (`people.matric_series`) | `/matriculation/config` | same | ADMIN 13556, COLLEGE 6093, PHARMACY 198, ARCHITECTURE 76, GENERAL 85631 | Forward only |
| Faculty segments/series, programme codes (`ref.faculty.matric_*`, `ref.programme.matric_*`) | `/matriculation/config` | same | per the Registry's schedule (§2.12) | Never inferred |
| Admission settings (`admissions.session_policy` and children) | `/admissions/settings` | academic, registrar, dregistrar | 2025/2026 DRAFT seeded (quota 10198, 70/30, 80:20, 60:40, criteria 10/35/30/25) | Frozen once IN_FORCE under a CAC minute |
| Load cut-off, O'Level grading, compulsory credits, exam-screened programmes | `/admissions/settings` | same | none for real sessions — defaults apply | — |
| Post-UTME examination, centres, rooms, slots, days | `/admissions/putme/setup` | academic, registrar, dregistrar, super | test residue only | Centres reused across sessions |
| Biodata fields and tiers (`ref.biodata_field`) | migration | ICT | 72 fields; two locked | No `approval` tier exists |
| Deferment application fee (`people.deferment_setting.fee`) | Fee Setup → Deferment · application fee (`PUT /api/v1/deferments/settings`) | Bursar | ₦10,000 | Zero waives the fee |
| Deferment limits and reasons (`people.deferment_setting`, `deferment_reason`) | `PUT /api/v1/deferments/settings` (limits); migration (reasons) | Registry; ICT | max 2 sessions; extension on; remind 14 d; overdue after 30 d; 9 reasons | No screen for the limits or the reasons |
| Deferment clock (`moaum.deferments.cron`) | property | ICT | `0 20 6 * * *` Africa/Lagos | — |
| Clearance units and purposes | migration | ICT | 8 units; 8 purposes | — |
| Document policies (`credentials.document_policy`) | `/credentials/documents/settings` | registrar, dregistrar, academic, super | five kinds (§2.14) | Number prefix `^[A-Z]{2,6}$` |
| Document templates (`credentials.document_template`) | same | same | v1 per kind | Issued documents keep their version |
| Verification throttle | code | — | 40 / 15 min per IP (documents); 12 / 15 min (ticket tracking) | Receipt/exam/registration/results/report checks rely on tokens; hostel has neither |
| Stationery batches (`credentials.stationery_batch`) | `/credentials/certificates` | academic, records, registrar | none | Serial range per batch |
| Help desk categories, SLA, auto-close, notify-agents | `/helpdesk/settings` | ict, admin, super | 11 categories; LOW 72/240, NORMAL 24/120, HIGH 8/48, URGENT 2/24; auto-close off; notify on | — |
| Library rule (`library.setting`) | `/library/circulation` | library, super | 14 days; ₦50/day; 3 items; 1 renewal | — |
| PG course catalogue (`admissions.pg_course`) | `/admissions/postgraduate/courses` | hod, academic, pgschool, pgsecretary, super | 4 demo rows | — |
| PG calendar | `/admissions/postgraduate/calendar` | pgschool, pgsecretary, super | seeded from the University calendar; none CURRENT | Windows informational |
| PG examiner roster (`admissions.pg_examiner`) | `/admissions/postgraduate/examiners` | pgschool, pgsecretary, super | 2 demo rows | Add only |
| External-examiner rubrics (`extexam.rubric`, `criterion`) | `/examiners/rubrics` | academic, dregistrar, pgschool, admin, super | UG_DEFAULT (80+20, 13 criteria); PG_DEFAULT (70+30, 9) | Criteria deactivated, never deleted |
| Examiner reminder cron | code | — | 07:15 Africa/Lagos | — |
| College calendar (`college.semester`) | `/college/calendar` | College desk offices | undated | The only editable College configuration |
| College examinations, subjects, postings, rules | migration | ICT | seeded V245/V248/V249 | Read-only in the API |
| Course CA/exam split (`catalogue.course.ca_max`) | `/catalogue` | hod and owners | 40 | — |
| Industrial-training flag on a course | migration | ICT | V155–V157 seed | No screen |
| Teaching load ceiling | code | — | 12 units per semester | Overload saved deliberately |
| Result query window | code | — | 7 calendar days from publication | — |
| Reports catalogue and due dates (`reports.catalogue`) | migration | ICT | 12 returns (§4.8) | `lib/report.ts` must be kept in step by hand |
| NDPA processing activities (`governance.processing_activity`) | migration | ICT | 7 rows | DPIA state editable on screen |
| DR objectives | page text | — | RPO ≤ 15 min; RTO ≤ 4 h | Not measured |
| API consumers and keys (`apimgmt.*`) | `/api-keys` | ict, admin, super | none | Register only |
| Audit exemptions (`audit.exemption`) | migration | ICT | 50 rows with reasons | Reason > 20 characters required |

---

## 6. Audit trail and compliance

### 6.1 What `audit.record` stores

Every attached table's trigger writes one row of `audit.entries` (partitioned by month, `audit.entries_YYYYMM`; partitions are pre-created through 2028-08) with: `occurred_at`; `period` and `shard` (0–15, from `hashtext(subject)`); `seq` within the shard; `actor_id` and `actor_office` (from the transaction-local settings `moaum.actor_id`, `moaum.actor_office`); `action` — the trigger argument (a domain-prefixed name such as `admissions:commit` where a module named one) or the bare `INSERT` / `UPDATE` / `DELETE`; `subject_type` (the table) and `subject_id` (the row's uuid, else an md5-derived uuid over its primary key); `before_state` and `after_state` as full-row JSON; `reason` (the `X-Reason` header); `correlation_id` (the `X-Correlation-Id` the request carried or was given; every problem response echoes it); `source_ip`; `prev_hash` and `entry_hash`.

The application side: `AttributedTransactionManager` sets the five values at the start of every transaction that has an `AuditContext`; `CorrelationIdFilter` accepts or mints the id and puts it in the log MDC. Scheduled jobs run under a synthetic actor and the office the module names (notice dispatch and the auto-closer as `ict`, the deferment clock as `registrar`, the hostel clock as `housing`, examiner reminders as `academic`, gateway settlements as `bursar`).

### 6.2 Reading the trail — the Audit Trail screen and its guard

Audit Log / Audit Trail — `/audit?action=&office=`. Guard `OVERSIGHT`: `ict, admin, super, audit, deputyaudit, vc` (the Registrar's menu item is refused — §1.7). Tiles **Entries on the record** (audit entries + staff sign-in events + student sign-in events), **Today**, **Actors today**, **Refusals today** (entries whose action contains "REFUS" plus failed sign-ins). Filters **Domain** (the part of the action before `:`, over the last 30 days, plus `auth`) and **Acting office** (last 30 days). Table When, Actor (name or "System", office), Action (red when it matches refus / denied / blocked), Subject (type and the first 8 characters of the id), Reason; "Most recent n" (200, at most 500). `before_state` / `after_state` are stored but **not shown** on the screen; there is **no export** of the trail.

> **Screenshot Required:** Audit trail — `/audit` — the four tiles, the Domain and Acting office filters and the table with an `auth:` row and a domain-prefixed row.

### 6.3 Sign-in events

Staff sign-ins are `iam.sign_in_event` rows (outcomes written: SIGNED_IN, BAD_PASSWORD, UNKNOWN, LOCKED, SIGNED_OUT), written **before** a refusal is thrown, in their own transaction, so the lockout counter survives the rollback. Student sign-ins are `iam.student_event` (UNKNOWN, NO_ACCOUNT, BAD_PASSWORD, LOCKED, CARRIED_OVER, SIGNED_IN, PASSWORD_CHANGED, OPENED_BY_REGISTRY, with IP); applicant sign-ins `admissions.applicant_event`. On `/audit` they appear as action `auth:<outcome>` with the username or IP in the Reason column; `/security` sums the last seven days of staff events ("Sign-in defence") and names the accounts drawing failed attempts. Credential events (SET, RESET, CHANGED) are on the spine.

### 6.4 Refused writes

A write refused by the database is rolled back together with any audit row — the spine is an AFTER trigger in the same transaction. Therefore **a refused write leaves no entry**, whatever the closing note on `/audit` says. What does appear: actions a module records explicitly with a `REFUS…` name, failed sign-ins, and bad-signature gateway events (kept in `finance.gateway_event`, not the spine). The 403 `NO_ACTING_OFFICE` a caller receives is the visible trace of an unattributed write; its correlation id is in the API log.

### 6.5 The hash chain and how it is verified

`entry_hash = sha256(canonical(entry) || prev_hash)`; `audit.chain_head(period, shard)` holds the last hash and sequence and is locked `FOR UPDATE` on every write. `audit.verify_chain(period)` recomputes every shard and reports `ok`, `first_break`, `broke_at`.

**Honest status:** the chain is verified **only by `db/check.sql`**, which CI runs against a fresh database (the "FOUNDATION GREEN" gate). There is **no nightly job**, no verification on the production database and no report screen — the Security Posture's "verified nightly across every shard" is untrue. `audit.unattached()` lists tables outside `audit` and `reporting` with neither an exemption nor a trigger; `db/verify.sql` runs after every deploy and raises if any application role holds DELETE, if anything may write to `audit.*`, or if an unattributed write is not refused. A periodic production run of `SELECT * FROM audit.verify_chain(period)` by ICT is the only way to detect a break today — **NOT IMPLEMENTED** as a scheduled control.

### 6.6 Retention

No retention or purge is implemented for the audit trail, sign-in events, notices, verification logs or download logs; monthly partitions accumulate. The reset actions (§3.11.6) delete operational data and record each deletion; they do not touch `audit.entries`. Gateway payloads are kept when under 20,000 characters.

### 6.7 NDPA register and DSR log

§2.19. Writers `registrar, dregistrar, ict, super`. A DSR carries no subject id and links to no record; completing one needs no note. Processing activities change only by migration.

### 6.8 DR drill log

Disaster Recovery / Backups & Recovery — `/disaster-recovery` (record: `ict`, `super`). "Record a drill": Drill (Restore verification / Full DR drill / Failover / Backup), Run on (defaults to today), Outcome (Passed / Partial / Failed), RPO achieved, RTO achieved, Note → `governance.dr_drill` (on the spine). Tiles Last restore verification / Last full DR drill / Drills on record / Failed drills. Backup telemetry and measured RPO/RTO are **NOT IMPLEMENTED**; the objectives table is static.

### 6.9 Deployment integrity

The migration runner (`db/migrate.sh`) keeps `public.schema_migration` (filename, SHA-256, applied at, by) and **stops the deployment when an applied file has changed**; a fix is always a new V-file. `db/verify.sql` asserts the invariants above plus the office count, the programme count and the presence of the 2025/2026 admission settings. The ledger is readable on `/migrations`.

---

## 7. Reports catalogue for administrators

Branded Excel and print exports put **S/N** as the first column, generated at export time, and sort names A–Z. "Print" means the browser's print-to-PDF of a branded document or a print window; "server PDF" means a PDF built by a route. CSV-only exports are marked.

| Report | Module | Offices (run) | Filters | PDF | Excel | Data source |
|---|---|---|---|---|---|---|
| Admissions return | reports | academic, registrar, dregistrar, records, dvc, vc, ict, admin, super (+ dean/facultyofficer/hod read) | session | print | yes | `/admissions/sessions/{s}/cycle` |
| Enrolment return | reports | same | session; scope-cut for deans/HODs | print | yes | `people.student` by entry session |
| Registration (cause) return | reports | same | session, semester | print | yes | `registration.registration_cause` |
| Carryovers return | reports | same | (as at today) | print | yes | published `course_final` with 0 points |
| Staff ratio return | reports | + hrm | session | print | yes | `hrm.staff_record` × live teaching offices |
| Postgraduate return | reports | + pgschool, pgsecretary | PG session | print | yes | `admissions.pg_*` |
| Revenue return | reports | bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc | session | print | yes | confirmed references by purpose + applicant fees |
| Funding return | reports | same | session | print | yes | `/funding/sessions/{s}/report` |
| Expenditure return | reports | same | year (from the session) | print | yes | `expenditure.budget_performance` |
| Income & expenditure return | reports | same | calendar year | print | yes | `finance.income_expenditure` + budget |
| Kept copy of any return | reports | snapshot readers (vc, dvc, registrar, dregistrar, academic, records, bursar, audit, deputyaudit, hrm, ict, admin, super, pgschool, pgsecretary) | — | server PDF (emailed) + print | yes | `reports.snapshot`; verification code at `/verify/report/<code>` |
| Student register | reports | snapshot readers + dean, facultyofficer, hod | faculty, department, programme, level, sex, status, entry mode, entry session, search | print (≤ 5,000 rows, else PARTIAL) | yes (all rows, 500 at a time) | `people.student` |
| Staff register | reports | same | faculty, department, rank, category, status, office held, search | print | yes (16 columns) | `iam.person` + `hrm.*` |
| Student statistics and drill-down | stats | registrar, dregistrar, bursar, academic, records, ict, admin, super, dvc, vc, pgschool, pgsecretary, provost, collegesecretary, financecontroller, dean, facultyofficer, hod, exams (money for MONEY offices) | session, semester, faculty, department, programme, level, status, degree, figure | branded print | yes | `reporting.student_positions` |
| Payments query | finance | bursar and finance readers | session, faculty, department, programme, level, category, channel, dates | branded print | yes (loaded rows only) | confirmed `finance.payment_reference` |
| Day book / ledger | finance | finance readers | date range | — | yes (branded, despite the `.csv` name) | `finance.day_book` |
| College Student Payment Report / Summary / by Programme | college | financecontroller, provost, collegesecretary, bursar, registrar, dregistrar, academic, dvc, vc, super | session, period, department, programme, level, status, search | branded print | yes | `finance.payment_position` |
| Fee schedule | finance | bursar (readers) | faculty, semester, spillover | print window | plain xlsx | `finance.fee_schedule` |
| Hostel: Occupancy by Hall, Inventory, Bed list, Applications, Bed Board / Occupancy — Students, Clearance, Checkout requests, Transfer requests | hostel | hostel actors and readers | per screen | branded print | yes | `hostel.*` |
| Hostel allocation letter, clearance certificate | hostel | student (own) | — | server PDF with QR | — | `hostel.allocation`, `clearance` |
| Deferments desk list | deferments | desk offices (bound) | session, semester, type, status, faculty, department, programme, search | branded print | yes | `people.deferment` |
| Deferment approval letter | deferments | student; desk in bound | — | server PDF (QR points to a route that does not exist) | — | — |
| Matriculation number configuration | matriculation | readers | faculty, search | branded print | yes | `people.matric_config_rows()` |
| Faculty matriculation list | matriculation | readers | — | — | **CSV only** | `people.faculty_list_rows` |
| Class list, attendance register, examination roll | registration | readers of the roll | course, session, semester | — | **CSV only** | `registration.*` |
| Score-sheet template and marked sheet | results | sheet readers | — | server PDF (marked sheet, landscape) | yes (both) | `assessment.score` |
| Upload validation report | results | lecturer / entry offices | — | — | **CSV only** | client validation |
| Broadsheet / Examination Reporting Sheet | results | readers, programme in bound | programme, level, session, semester | print window | yes (two sheets, serial BRD) | computed |
| Semester Results statement, Result broadsheet, Exam card, Course form, Receipt, Identity card (student) | studentportal | student (own) | — | server PDF (QR where noted) | — | — |
| Faculties, Departments, Programmes | catalogue | ict (readers) | — | branded print | yes (FAC/DEP/PRG) | `ref.*` |
| Courses offered to a programme; whole catalogue | catalogue | readers | programme/curriculum | branded print | yes (CRS/CAT) | `catalogue.*` |
| Post-UTME: batches, candidates, attendance sheet per batch | admissions (putme) | readers / office | session, filters | branded print | yes (CBT) | `screening_batch`, `screening_assignment` |
| JAMB admission template | admissions | academic, registrar | programme or all | — | yes (JAMB's own layout, five sheets) | `admissions.*` |
| Computed Post-UTME; Screened summary/detail/all-O'Level | admissions | academic, super (computed); readers | programme, faculty | branded print | yes (CPU) | `non_sitter_post_utme`, screening views |
| Screening register non-index scores | admissions | readers | — | — | **CSV only** | — |
| Postgraduate applications | pgadmissions | readers | session | — | yes (PGAPP) | `pg_application` |
| Merged application documents; application summary; offer letter | pgadmissions | desk; applicant | — | server PDF | — | — |
| Examiner reports (8 kinds) | examiners | desk offices in reach | session, faculty, department, programme, examiner, status, dates | — | **CSV only** | `extexam.*` |
| ICT support report | helpdesk | ict, admin, super | dates, category, priority, agent, faculty, department | — | **CSV only** | `helpdesk.*` |
| Graduates Awaiting Certificate; Document Requests; Issued Documents; Document Verifications | credentials | documents readers | per screen | branded print | yes (DOC; verifications PDF only) | `credentials.*` |
| Degree certificate, transcripts, statement of record | credentials | student, office, recipient | — | server PDF with QR and code | — | `credentials.issued` |
| Clearance held list | clearance | readers | purpose, scope | — | **CSV only** | `clearance.item` |
| HOD fee lists (cleared / owing) | hod | hod | — | — | download | `finance.position` |
| Wallet / NELFUND report | wallet | readers | session | none | none | `finance.funding_summary` |
| Payroll, payslips, vouchers, budget, tenders, requisitions, stores, GL statements, reconciliation, bank credits, refunds, audit trail, governance | finance / expenditure / hrm / auditlog / governance | — | — | table Print only | none | — |

---

## 8. Administrator troubleshooting

Each problem: what the screen says, why, and the remedy. Problem responses are RFC 7807 bodies with `title`, `detail`, `remedy.message`, `remedy.who` and a `correlationId`; the `ProblemNotice` banner shows them and the toast repeats the title.

**403 `NO_ACTING_OFFICE` — "This request names no acting office, so it may read but not change anything."**
The write reached the database with no `moaum.actor_office`. Causes: the `moaum_office` cookie is missing or blank (choose an office in "Signed in as"); the person has no live office at all; a batch or script forgot to set a context. Remedy: pick an acting office and retry; for a person, grant the office on `/people` and have them sign out and in.

**403 "The office 'x' is not one this token carries: […]" — office not held.**
The cookie names an office the token lacks — typically a grant that ended, or a grant made after sign-in. Remedy: sign out and in (the token is minted with the offices as of sign-in). If the office should be held, check the grant's From/To on `/people`.

**403 with an office list, e.g. "You do not have access to that" on a screen the menu offered.**
The guard omits the acting office (§1.6–1.7). Remedy: act as the office the guard names, or have the Registry grant it under an instrument. Do not try to widen `super`.

**422 `DATABASE_RULE_REFUSED` with a remedy line.**
A SQL rule raised 23514; the message is the rule's own text and the HINT is the remedy — e.g. "a change of status is made on an instrument … and none was cited" (fill Instrument), "the run cannot start: Faculty of X has not confirmed its list" (confirm the list), "the first semester school fees for 2026/2027 are not fully paid" (the student pays), "no clearance scheme in force … D-Q4 is unanswered" (Bursar puts the scheme in force), "the registration carries N units; at L level the range is a to b" (adjust courses — there is no overload), "A session stays planned until its Senate minute is recorded against it" (fill the minute). Remedy: do what the HINT says; the row was not written.

**422 `VALIDATION_FAILED` with `violations[]`.** A field failed bean validation (length, range, pattern). Correct the named field.

**409 `ALREADY_EXISTS` — duplicates.** A unique key: a staff number already on `iam.person`; a username already signing somebody in; a second CURRENT session; a second application account for a JAMB number or email; "a transfer application is already in progress"; "an application for % already stands" (hostel); "a pay run for <Month> already exists"; "reference X is already confirmed" on a bank-credit proposal (raise a wallet credit or refund instead). Remedy: find and use the existing row.

**409 `REFERENCE_MISSING`.** A foreign key: "no reference X was generated by this portal" (money sent against a reference the portal never minted — it did not reach the University's record; record it as a bank credit if it is in the account); a candidate whose programme name is not on `ref.programme` during intake (create or rename the programme, then re-run); "no active consumer to issue a key to".

**"unattributed change to schema.table — no audit context on this transaction".**
Seen only in the API log or from SQL run by hand: a write without `SET LOCAL moaum.actor_id / moaum.actor_office`. Every application path sets them; a hand-run SQL fix must set them too (`SET LOCAL moaum.actor_id = '<person uuid>'; SET LOCAL moaum.actor_office = 'ict';`) or the trigger refuses.

**Notices stuck QUEUED.**
`/notices` shows Waiting rising and Sent today at zero. No provider: on the API, either Mail Server (`/platform/mail`: host, username, password, and `MOAUM_CONFIG_KEY` set), or SMS Gateway enabled with a key, or the relay URLs. The API log says "notices: no email account…". Once fixed the dispatcher drains 50 a minute. Rows FAILED with `AuthenticationFailedException` or "provider answered 4xx": wrong password or token — fix, then **Put all n failed back in the queue**. A staff reset mail never arrives: the person has no email (`/people` → Contact).

**Gateway callback not settling.**
Check `/finance/gateways` "Webhook and verification log": no event at all → the gateway dashboard's webhook URL is wrong (copy the address printed on the screen) or outbound network is blocked; `BAD_SIGNATURE` → the secret (Paystack) or hash (Flutterwave) on the gateway differs from the portal's; `SHORT_PAID` → the payer paid less than the reference asks (generate a reference for the part); `UNKNOWN_REFERENCE` → paid against another institution's code or a reference the portal never minted (resolve on the record); `GATEWAY_ERROR` → the gateway did not answer (the sweep retries every ten minutes up to twelve times; or **Ask the gateway now**). "Card and USSD payment arrive when a payment gateway is wired" on the student's side → no key set. "The portal has no passphrase to encrypt a gateway key with" → set `MOAUM_CONFIG_KEY`.

**Matriculation run refused.**
"the run cannot start: Faculty of X has not confirmed its list" → every faculty with registered students must confirm on `/matriculation/faculty/{code}`. "the matriculation number cannot be built: Programme … is configured to carry a code but has none" → on `/matriculation/config` give the programme its code or set it to carry none; the whole run rolled back, nothing was issued. Series inactive → set the series Active. "Series X has issued up to N; it does not go back." → a counter cannot be lowered; if the Registry's schedule is genuinely lower, that is a records question, not a configuration one. A student on a confirmed list got no number → under query, or fees not paid in full (the list's Fees column shows "—"; check `/stats` or the student's fees).

**Deploy blocked by an edited migration.**
`db/migrate.sh` compares each applied file's SHA-256 with `public.schema_migration` and stops the deployment when one differs ("an edited migration must be refused" is also a CI gate). Remedy: restore the applied file to its recorded content and put the change in a new `V264__…` file. Never edit an applied migration.

**Session floor after deploy — "The portal was updated. Sign in again."**
Every session issued before the API instance started is refused by design. Nothing to fix; warn users before a deploy. If the frontend's `/iam/me` check cannot reach the API at all, page navigations are let through and BFF calls fail instead — check the API's `/actuator/health`.

**"That username and password do not match an account." / "This account is locked after repeated failures; try again after HH:MM."**
Unknown username, an ended person, or a wrong password; the fifth failure locks for fifteen minutes. Remedy: `/people` → **Reset password** (sets a new first password and clears the lock). Note the lock time is in the server's time zone.

**"No portal account has been opened for this number yet."** A migrated student with no applicant account behind them: Student 360 → **Portal account** (needs a matric number).

**Readiness "Blocking".** Follow each **Fix** link; "Session on the calendar" needs a CURRENT session under a Senate minute; "A semester is open" is the semester State on `/calendar`, not the examination session.

**HOD or Dean sees "not tied to a department / faculty yet".** The grant carries no scope and the person has no lecturer grant or staff record department. `/people` → **Grant an office** with "Which one" filled (end the unscoped grant with a reason).

**A screen shows figures that are wrong by up to a minute.** Student statistics are cached 60 s per scope. Menu badges like "7" or "12" are prototype fixtures and never render; only live `waiting` counts show.

---

## 9. Quick start

### 9.1 New Administrator (Registrar, Deputy Registrar, Academic Officer, Bursar) — first 10 things

1. Sign in at `/login` with the staff number or email; change the first password at `/account/password` (ten characters or more, not your username).
2. Look at "Signed in as" — confirm the acting office; every write you make is attributed to it and carries the reason you type.
3. Open `/calendar`: is there a CURRENT session with a Senate minute and an OPEN semester? If not, nothing registers and nothing is charged.
4. Open `/finance/fees` (Bursar): is a fee schedule stated for the session and a clearance scheme in force? Without them no payment releases anything.
5. Open `/people`: confirm your own grant carries the right scope and instrument, and that the HODs and Deans you rely on have scoped grants.
6. Open `/readiness`: read the gates and fix the blocking ones with the Bursary and ICT.
7. Open `/reports`: read the Due register for the returns your office owns and their next due dates.
8. Open `/matriculation/config` (Registry / Academic Office): check every programme has the code the Registry's schedule gives it and that no series is inactive.
9. Open `/admissions/settings` (Academic Office): put the coming session's settings in force under the CAC minute before any CAPS list is loaded.
10. Read §1.6 and *04 Role and Permission Matrix* for your office before asking ICT for "more rights" — most refusals are the guard doing its job.

### 9.2 New ICT Officer — first 10 things

1. Confirm the service variables on the API: `MOAUM_AUTH_HMAC_SECRET` (≥ 32 bytes), `MOAUM_CONFIG_KEY`, `MOAUM_PORTAL_URL`, the database URL; on the frontend `PORTAL_API_URL`. Never set `PORTAL_API_TOKEN` in production.
2. Open the platform dashboard at `/` as `ict`: read "What is actually true" — service up, database reachable, latest migration.
3. Open `/migrations`: the ledger must match the repository's `db/` folder; an edited applied file stops the next deploy.
4. Open `/platform/mail` and `/platform/sms`: set the SMTP account (or the relay variables) and the eBulkSMS key; then watch `/notices` — Waiting must fall and Sent today rise.
5. Open `/finance/gateways`: set the gateway keys (never share or display them), copy the webhook addresses to the gateway dashboards, run a ₦100 test checkout and see the event land with a valid signature.
6. Open `/people`: create the office holders and grant them under instruments; use `/people/lecturers` and `/people/staff` for the bulk loads; tell lecturers to change `P<PNO>` at once.
7. Open `/structure/faculties`, `/structure/departments`, `/structure/programmes`, then `/catalogue/upload`: load the structure (only `ict` can), then open course registration for the session.
8. Open `/helpdesk/settings`: confirm categories and SLA hours, decide the auto-close days, and grant `ictagent` to the desk staff; then work `/helpdesk` daily.
9. Open `/security` and `/audit`: understand what is and is not true there (no nightly chain check; refused writes are not on the trail); run `audit.verify_chain` on production by hand on a schedule of your own.
10. Before go-live: `/readiness` all green, "Remove demo data only" on the platform dashboard, and a note to every user that a deploy signs everyone out.

---

*End of volume 02. Cross-references: 01 User Manual (students, applicants, lecturers, general staff) · 03 Technical Documentation · 04 Role and Permission Matrix · 05 Module Navigation Guide · 06 Workflows · 07 API Reference · 08 Database Reference · 09 Feature Status Report.*
