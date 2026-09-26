# MOAUM Unified University Portal — Module and Navigation Guide

**Volume 05 of the documentation package** · Rev. Fr. Moses Orshio Adasu University, Makurdi · Directorate of ICT

This volume is the map of the portal. It describes how the sidebar and the office menus work, lists every office's menu as it is actually wired, catalogues every module against one fixed template, documents every screen the portal serves, and closes with the catalogues of dashboards, reports, generated documents and notifications. Everything here was read from the code and the database as they stand at commit `8c2b6fa` (migrations V001–V263). Where a menu item, a button or a piece of on-screen text promises something the code does not do, this volume says so.

Cross-references: sign-in, day-to-day use and troubleshooting are in *01 User Manual*; setup and administration in *02 Administrator Manual*; architecture and configuration in *03 Technical Documentation*; the authority behind every screen in *04 Role and Permission Matrix*; the end-to-end business flows in *06 Workflows*; every endpoint in *07 API Reference*; every table in *08 Database Reference*; the consolidated status matrix in *09 Feature Status Report*.

## Table of contents

1. [How navigation works](#1-how-navigation-works)
   1. [The Shell](#11-the-shell)
   2. [Menu sections and their vocabulary](#12-menu-sections-and-their-vocabulary)
   3. [The home route and the office dashboards](#13-the-home-route-and-the-office-dashboards)
   4. [Titles, breadcrumbs and badges](#14-titles-breadcrumbs-and-badges)
   5. [The office switcher](#15-the-office-switcher)
   6. [The fallback menu](#16-the-fallback-menu)
   7. [Search](#17-search)
   8. [Journey menus for students and applicants](#18-journey-menus-for-students-and-applicants)
   9. [Menu items that do not work as labelled](#19-menu-items-that-do-not-work-as-labelled)
2. [Complete navigation map, office by office](#2-complete-navigation-map-office-by-office)
3. [Module catalogue](#3-module-catalogue)
4. [Screen-by-screen documentation](#4-screen-by-screen-documentation)
5. [Dashboards and KPIs](#5-dashboards-and-kpis)
6. [Reports and exports catalogue](#6-reports-and-exports-catalogue)
7. [Generated documents catalogue](#7-generated-documents-catalogue)
8. [Notifications catalogue](#8-notifications-catalogue)

---

## 1 How navigation works

### 1.1 The Shell

Every signed-in staff screen renders inside one component, the Shell (`frontend/src/components/proto/Shell.tsx`). The Shell draws three things:

- the **sidebar** on the left — the University crest, a "Signed in as" office selector, the acting office's menu folded into groups, a collapse control, and a foot with the sign-out button;
- the **top bar** — a menu button (on narrow screens), the breadcrumb, the page title and subtitle, the identity chip and the "Search records" button;
- the **content column**, where the page itself renders.

The sidebar is 244 px wide and collapses to 62 px (icons only). Below 900 px it becomes an off-canvas drawer opened by the menu button; below 760 px tiles stack two-up and tables scroll sideways. Printing hides the Shell entirely, so a printed page shows only the document.

The sidebar's content is chosen in this order (`Shell.tsx:313-320`):

1. a menu the API handed down with `/api/v1/iam/me` (used for a postgraduate student, who gets the School's menu);
2. the office menu for the acting office (`frontend/src/lib/menus.ts`, keyed by office code);
3. the **fallback** menu for an office that has no menu of its own (§1.6).

Each menu item is a *route id* such as `t/matriculation` or `s/fees`. The Shell's `ROUTES` table maps a route id to a URL. An item whose id is the menu's **home** resolves to `/`. An item whose id is in neither the home nor `ROUTES` renders as a button that shows the notice "*{label}* is still the prototype's screen"; such items are marked **(placeholder)** in §2.

> **Note:** The menus are written by hand. The API's guards are the law. A menu item can therefore open a page whose data calls the API refuses with 403; the page then shows a `ProblemNotice` and the toast "You do not have access to that". Every such item is marked **(refused by API)** in §2, and the full list with the guard that refuses it is in *04 Role and Permission Matrix*, §4.1.

### 1.2 Menu sections and their vocabulary

Staff menus use a fixed vocabulary of group names. Not every office has every group.

| Group | What it holds |
|---|---|
| **Overview** | The office's home (Dashboard, Setup Console, Platform & Integrations, Movements, Payment Vouchers, Card Printing, Verify a Card, Clinic, ICT Support Desk, Scrutiny Desk…), Student Statistics, Institutional Overview, Go-Live Readiness and Search. |
| **Academic** | Calendar and sessions, examination sessions, results desks and the approval chain, broadsheets, Senate schedule, publication, graduation, courses and structure, course spaces, teaching allocation, external examiners, College of Health Sciences, postgraduate desks. |
| **Students** | The register and Student 360, records & queries, matriculation, deferments, transfers, biodata changes, clearance, class lists, SIWES supervision, documents office, transcripts, certificates, hostel (housing), PG students. |
| **Admissions** | Admission settings, CAPS upload, candidate data, screening, Post-UTME CBT schedule and scores, merit list, Direct Entry screening, admissions report, postgraduate admissions. |
| **Finance** | Fee setup, payments, gateways, hanging payments, investigation, refunds, funding sources and NELFUND, vouchers, payroll, budget, tenders, requisitions, accounting, ledger, reconciliation, held scripts, College payment report. |
| **Staff** | Staff records, recruitment, leave, appraisal, movements, department staff, the two staff uploads. |
| **Services** | Circulation, stores, alumni, card printing/collection, hostel (support services). |
| **Accommodation** | The housing desk's six hostel screens. |
| **Reports** | Reports & Returns, Student Register, Staff Register. |
| **Administration** | Users & Roles, notification channels, data migration, platform, integrations/API keys, audit trail, security posture, backups/DR, governance, mail server, SMS gateway, release pipeline, cloud readiness, the ICT help desk screens. |
| **History** | (Lecturer only) Score Sheet History, Course History. |
| **Me** | Leave & Payslip, My Profile, ICT Support Tickets. |

Student menus use **Start here / Academic / Learning / Services / Account** (undergraduate) and **Overview / Academic / Finance / Research / Documents / Communication / Graduation / Profile** (postgraduate). The applicant menu uses **My application / Screening / Admission**; the postgraduate applicant **My application**; the external examiner **External Examiner**.

### 1.3 The home route and the office dashboards

`/` is a router (`frontend/src/app/page.tsx`). It reads `/api/v1/iam/me`, redirects single-purpose offices to their own home, and renders one of about eighteen office dashboards for the rest:

| Acting office | What `/` does |
|---|---|
| `applicant` | redirect → `/applicant` |
| `student` | redirect → `/student` (or `/college/student` for a College of Health Sciences student from 200 Level) |
| `admin` | redirect → `/admin` (Administrator Dashboard) |
| `vc` | redirect → `/overview` (Institutional Overview) |
| `library` | redirect → `/credentials/idcards` (Card Printing) |
| `provost`, `collegesecretary`, `financecontroller` | redirect → `/college/dashboard` |
| `mbbscoordinator` | redirect → `/college/coordinator` |
| `ictagent` | redirect → `/helpdesk` |
| `extexaminer` | redirect → `/examiner` |
| `ict`, `super` | Platform dashboard |
| `academic`, `dregistrar`, `records`, `dvc` | Academic dashboard |
| `registrar` | Registrar dashboard |
| `bursar` | Bursar dashboard |
| `lecturer` | Lecturer dashboard |
| `hod` | HOD dashboard |
| `dean`, `facultyofficer` | Dean dashboard |
| `exams`, `facultyexams` | Exams dashboard |
| `hrm` | HR dashboard |
| `services` | Clinic dashboard |
| `security` | Security dashboard |
| `audit`, `deputyaudit` | Audit dashboard |
| `housing` | Housing dashboard |
| `siwes` | SIWES dashboard |
| `pgschool` | PG School dashboard |
| `pgsecretary` | PG Secretary dashboard |
| any other | generic Office dashboard (placeholder, hard-coded "Session 2026/2027" tile) |

The session a dashboard uses is the CURRENT one from `/api/v1/ref/sessions`; when no session is CURRENT the literal `2026/2027` is used. §5 lists every dashboard's tiles.

### 1.4 Titles, breadcrumbs and badges

The page title and subtitle come from `frontend/src/lib/titles.ts` (the prototype's titles) overridden by the Shell's `OVERRIDES` table; a page may also pass a live title. Several subtitles are static prototype text — for example the student's Fees page says "2026/2027 session", Recruitment says "2026 cycle", Appraisal says "2026 exercise", Budget says "Financial year 2026" and Payment Investigation says "Unmatched settlement · teller slip BR/44821" — and are flagged where they occur in §4.

The breadcrumb reads *group › item* when the item label differs from the page title.

Badges on menu items are the **waiting counts** the API returns in `iam/me.waiting`: persons without a credential (`t/users`), pending biodata changes, admissions, clearance, transcripts, certificates and approvals counts, a "!" on Admission Settings when the next planned session has no policy in force, and a "!" on Matriculation when admitted students of the current session have no number. A closed group shows the sum of its items' counts. The badge fixtures written in `menus.ts` itself (for instance "7" on Hanging Payments or "12" on Reconciliation) are never rendered.

### 1.5 The office switcher

A person holding several offices chooses the acting office from the "Signed in as" select at the top of the sidebar. The choice is written to the `moaum_office` cookie and the page refreshes; every request then carries that office as `X-Active-Office`, and the API refuses an office the token does not carry. Switching office does not update `platform.session.active_office` (it is set once at sign-in); attribution on the audit spine follows the header, so it is still correct. Grants take effect at the next sign-in.

### 1.6 The fallback menu

An office the prototype drew no menu for gets the Shell's `FALLBACK` menu, labelled "Office": **Records** (Search, Dashboard) and **Me** (Leave & Payslip). At commit `8c2b6fa` exactly one office is in this position: the **Deputy Director of Audit** (`deputyaudit`). That office acts in payment vouchers, reconciliation, expenditure reads and reports, and reads the audit log, but reaches those screens only by typing the URL. Its Search item is refused by the API (§1.7).

### 1.7 Search

`/search` is on every staff menu, on the top bar as "Search records ⌘/", and on the `/` keyboard shortcut. It finds students, staff, courses and credentials by matriculation number, name, staff number, course code or verification code, writes every searched term to `people.search_log` ("Every search for a person is recorded against your account"), and opens the student or staff record. Its data call is `/api/v1/student/search`, guarded by the student module's readers. Ten offices carry the menu item but are refused: Provost, College Secretary, Finance Controller, MBBS Coordinator, Dean SPGS, Secretary SPGS, Support Services, SIWES Coordinator, ICT Support Agent and the Deputy Director of Audit (fallback). The "Open" button on a course hit and the "Verify" button on a credential hit are disabled ("The course screens are not on the portal yet" / "Verification is not on the portal yet").

### 1.8 Journey menus for students and applicants

Students and applicants do not choose an office. A student's menu is a journey: **Start here** (Dashboard, School Fees — Pay First), **Academic**, **Learning**, **Services**, **Account**. A postgraduate student receives the School's menu from the API (`me.menu`) instead. An applicant's menu follows the ten stages of the application — **My application**, **Screening**, **Admission** — and each screen tells the applicant what the next step is. A postgraduate applicant has a three-item menu whose third item, "Application Summary", is a PDF route rather than a page, and whose home id (`pg/home`) has no route — the portal opens at `/pg/portal`.

### 1.9 Menu items that do not work as labelled

Beyond the "(refused by API)" items of §2, four kinds of item mislead:

- **Placeholders** — items with no route: Platform / Platform & Integrations (`t/platform`) in the Administration group of the Super Administrator and the System Administrator (for the Director of ICT it is the home and resolves to `/`); the Chief Security Officer's "Verify a Card" (`t/idverify`) is that office's home and so resolves to `/`, but no card-verification screen exists anywhere.
- **Mislabelled** — the Examinations Officer's "CBT Sessions" opens the results module's Examination Sessions screen; there is no CBT delivery. The HRM home is titled "Staff movements" although it is the HR dashboard. "Cash Office & Assets" on the Bursar's menu opens the same Payment Investigation page as "Payment Investigation".
- **Duplicated** — Score Sheets, Score Entry and Upload Results (bulk) on the HOD and Dean menus all open `/results/sheets`; Card Collection and Lost & Replacement on the Security menu both open `/credentials/idcards`.
- **Partially refused** — Reports & Returns for a Dean, Faculty Officer or HOD opens, and the returns run cut to scope, but the due register, kept copies and "Keep a copy" are refused.

---

## 2 Complete navigation map, office by office

Each tree below is the office's menu exactly as `frontend/src/lib/menus.ts` lists it, group by group, with the URL the Shell resolves for the item. **Home** items resolve to `/` (the office dashboard of §1.3). Items are marked **(refused by API)** when the page's data calls are refused for that office (see *04 Role and Permission Matrix*, §4.1) and **(placeholder)** when no route exists. Route ids are given in the office heading only where they matter.

### 2.1 Super Administrator (`super`)

```text
Super Administrator — home: Setup Console → /
Overview
 → Setup Console → /  (home; renders the Platform dashboard)
 → Student Statistics → /stats
 → Search → /search
Academic
 → Session & Semester Setup → /calendar
 → Post-UTME CBT Schedule → /admissions/putme
 → College of Health Sciences → /college
 → Result Pipeline → /results/pipeline
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → Records & Queries → /records
Staff
 → Upload Lecturers → /people/lecturers
 → Upload Non-Academic Staff → /people/staff
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Administration
 → Users & Roles → /people
 → Notification Channels → /notices
 → Data Migration → /migrations
 → Platform → (placeholder — no route; shows "Platform is still the prototype's screen")
 → Integrations → /api-keys
 → Audit Log → /audit
 → Security → /security
 → Backups & Recovery → /disaster-recovery
 → Governance → /governance
 → ICT Support Desk → /helpdesk
 → ICT Support Reports → /helpdesk/reports
 → ICT Support Settings → /helpdesk/settings
Me
 → ICT Support Tickets → /tickets
```

### 2.2 System Administrator (`admin`)

```text
System Administrator — home: Administrator Dashboard → /admin
Overview
 → Administrator Dashboard → /admin
 → Student Statistics → /stats
 → Go-Live Readiness → /readiness
 → Institutional Overview → /overview
 → Search → /search
Academic
 → Teaching Allocation → /allocate
 → Approval Chain → /results/chain
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Records & Queries → /records
 → Clearance → /clearance
 → Student Records → /students
Admissions
 → Post-UTME CBT Schedule → /admissions/putme
 → Post-UTME Scores → /admissions/scores
 → Admissions → /admissions
Finance
 → Payment Gateways → /finance/gateways
 → Accounting & Books → /finance/accounting
 → Transactions & Accounts → /finance/ledger
 → Reconciliation → /finance/reconcile
 → Payment Investigation → /finance/exceptions
 → Fee Schedules → /finance/fees
Staff
 → Upload Lecturers → /people/lecturers
 → Upload Non-Academic Staff → /people/staff
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Administration
 → Mail Server → /platform/mail
 → SMS Gateway → /platform/sms
 → Users & Roles → /people
 → Platform & Integrations → (placeholder — no route)
 → Security Posture → /security
 → Audit Trail → /audit
 → Data Governance → /governance
 → ICT Support Desk → /helpdesk
 → ICT Support Reports → /helpdesk/reports
 → ICT Support Settings → /helpdesk/settings
Me
 → ICT Support Tickets → /tickets
```

### 2.3 Director of ICT (`ict`)

```text
Director of ICT — home: Platform & Integrations → /
Overview
 → Platform & Integrations → /  (home; Platform dashboard)
 → Student Statistics → /stats
 → Search → /search
Academic
 → Upload or Create Faculties → /structure/faculties
 → Upload or Create Programmes → /structure/programmes
 → Upload or Create Departments → /structure/departments
 → Upload or Create Courses → /catalogue/upload
 → Migrate from Old Portal → /records/migration
Students
 → Student Records → /students
Admissions
 → Post-UTME CBT Schedule → /admissions/putme
 → Post-UTME Scores → /admissions/scores
Finance
 → Payment Gateways → /finance/gateways
Staff
 → Upload Lecturers → /people/lecturers
 → Upload Non-Academic Staff → /people/staff
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Administration
 → Users & Roles → /people
 → Mail Server → /platform/mail
 → SMS Gateway → /platform/sms
 → Notifications → /notices
 → Security Posture → /security
 → API Management → /api-keys
 → Release Pipeline → /release  (static page)
 → Disaster Recovery → /disaster-recovery
 → Cloud Readiness → /cloud  (static page)
 → Audit Trail → /audit
 → Data Governance → /governance
 → ICT Support Desk → /helpdesk
 → ICT Support Reports → /helpdesk/reports
 → ICT Support Settings → /helpdesk/settings
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.4 ICT Support Agent (`ictagent`)

```text
ICT Support Agent — home: ICT Support Desk → /helpdesk
Overview
 → ICT Support Desk → /helpdesk
 → Search → /search  (refused by API)
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.5 Vice-Chancellor (`vc`)

```text
Vice-Chancellor — home: Institutional Overview → /overview
Overview
 → Institutional Overview → /overview
 → Student Statistics → /stats
 → Search → /search
Academic
 → Senate Business → /results/approvals
 → Graduation → /graduation
 → Research → /research/projects  (research grants register)
Finance
 → Budget → /finance/budget
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Administration
 → Audit Trail → /audit
 → Data Governance → /governance
 → Security Posture → /security
Me
 → ICT Support Tickets → /tickets
```

### 2.6 Deputy Vice-Chancellor (Academic) (`dvc`)

```text
DVC (Academic) — home: Dashboard → /  (Academic dashboard)
Overview
 → Dashboard → /
 → Institutional Overview → /overview
 → Search → /search
Academic
 → Result Pipeline → /results/pipeline
 → Senate Schedule → /results/senate
 → Broadsheets → /results/broadsheet
 → Graduation → /graduation
Students
 → Records & Queries → /records
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.7 Registrar (`registrar`)

```text
Registrar — home: Dashboard → /  (Registrar dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Institutional Overview → /overview
 → Search → /search
Academic
 → College of Health Sciences → /college
 → Senate Business → /results/approvals
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → Matriculation → /matriculation
 → Matriculation Management → /matriculation/manage
 → Matriculation Number Format → /matriculation/config
 → Records & Queries → /records
 → Inter-Departmental Transfer → /transfers
 → Student Records → /students
 → Biodata Changes → /students/biodata-changes
 → Certificates → /credentials/certificates
 → Clearance → /clearance
 → Documents Office → /credentials/documents
 → Transcripts → /credentials/transcripts
Admissions
 → Post-UTME CBT Schedule → /admissions/putme
 → Admissions → /admissions
 → Programme Eligibility → /admissions/eligibility
 → Admitted List → /admissions/applicants
Staff
 → Staff Records → /staff  (refused by API — payroll readers exclude registrar)
 → Recruitment → /hr/recruitment
 → Upload Non-Academic Staff → /people/staff
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Administration
 → Data Governance → /governance
 → Audit Trail → /audit  (refused by API — auditlog OVERSIGHT excludes registrar)
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

> **Note:** The Registrar may also open Admission Settings, CAPS upload, candidate data, screening, PUTME scores, the merit list, Direct Entry screening (`/admissions/…`), Session & Semester Setup (`/calendar`) and the hostel desk (`/hostel`) by URL; the API admits the office but the menu does not list them.

### 2.8 Deputy Registrar (Academic Affairs) (`dregistrar`)

```text
Deputy Registrar (Academic Affairs) — home: Dashboard → /  (Academic dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Search → /search
Academic
 → Senate Schedule → /results/senate
 → Post-UTME CBT Schedule → /admissions/putme
 → Result Pipeline → /results/pipeline
 → Approval Chain → /results/chain
 → Broadsheets → /results/broadsheet
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → Matriculation → /matriculation
 → Matriculation Management → /matriculation/manage
 → Matriculation Number Format → /matriculation/config
 → Clearance → /clearance
 → Student Records → /students
 → Records & Queries → /records
 → Documents Office → /credentials/documents
 → Transcripts → /credentials/transcripts
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Staff
 → Upload Non-Academic Staff → /people/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.9 Academic Office (`academic`)

```text
Academic Office — home: Dashboard → /  (Academic dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Search → /search
Academic
 → College of Health Sciences → /college
 → Session & Semester Setup → /calendar
 → Examination Sessions → /examinations/sessions
 → Graduation → /graduation
 → Results to Senate → /results/approvals
 → Approval Chain → /results/chain
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → Matriculation → /matriculation
 → Matriculation Management → /matriculation/manage
 → Matriculation Number Format → /matriculation/config
 → Records & Queries → /records
 → Student Records → /students
 → Biodata Changes → /students/biodata-changes
 → Registered Students → /registration/class-list
 → Inter-Departmental Transfer → /transfers
 → Clearance → /clearance
 → Documents Office → /credentials/documents
 → Transcripts → /credentials/transcripts
 → Certificates → /credentials/certificates
Admissions
 → Admission Settings → /admissions/settings
 → Programme Eligibility → /admissions/eligibility
 → Upload Applicants and Candidates → /admissions/caps
 → Upload Passport, DOB & O'Level → /admissions/candidate-data
 → Migrate Old-Portal Applicants → /admissions/migrate
 → Compute PUTME Score → /admissions/computed-screening
 → Screening Register → /admissions/screening
 → Post-UTME CBT Schedule → /admissions/putme
 → Upload PUTME Score → /admissions/scores
 → Merit List → /admissions/merit
 → Direct Entry Screening → /admissions/de-screening
 → Postgraduate Admissions → /admissions/postgraduate
 → Report on Post-UTME Registration → /admissions/applicants
 → Report on Admissions → /admissions
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.10 Exams and Records (`records`)

```text
Exams & Records — home: Dashboard → /  (Academic dashboard)
Overview
 → Dashboard → /
 → Search → /search
Academic
 → Examination Sessions → /examinations/sessions
 → Post-UTME CBT Schedule → /admissions/putme
 → Validation Desk → /results/desk
 → Result Pipeline → /results/pipeline
 → College of Health Sciences → /college
 → Migrate from Old Portal → /records/migration
 → Broadsheets → /results/broadsheet
 → Senate Schedule → /results/senate
 → Publication → /results/publish
 → Approval Chain → /results/chain
 → Graduation Records → /graduation
Students
 → Deferments → /deferments
 → Documents Office → /credentials/documents
 → Transcripts → /credentials/transcripts
 → Certificates → /credentials/certificates
 → Records & Queries → /records
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.11 Bursar (`bursar`)

```text
Bursar — home: Dashboard → /  (Bursar dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Search → /search
Students
 → Financial Clearance → /clearance
 → Records & Queries → /records
Finance
 → Held Scripts → /finance/held-scripts
 → College Payment Report → /college/payments
 → Fee Setup and Schedule → /finance/fees
 → Old Fees History → /finance/legacy-fees
 → Payment Gateways → /finance/gateways
 → Hanging Payments → /finance/hanging
 → Payment Investigation → /finance/exceptions
 → Payments Query → /finance/payments
 → Payment History Upload → /finance/payments-history
 → Refunds & Credits → /finance/refunds
 → Funding Sources → /finance/sources
 → Sources & Wallets → /finance/nelfund
 → NELFUND Applicants → /finance/nelfund?tab=status
 → Match a Remittance → /finance/nelfund?tab=match
 → Payment Vouchers → /vouchers
 → Payroll → /payroll
 → Budget → /finance/budget
 → Tenders → /finance/tenders
 → Cash Office & Assets → /finance/exceptions  (same page as Payment Investigation)
 → Accounting & Books → /finance/accounting
 → Transactions & Accounts → /finance/ledger
 → Reconciliation → /finance/reconcile
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.12 Finance Controller, College of Health Sciences (`financecontroller`)

```text
Finance Controller (CHS) — home: Dashboard → /college/dashboard  (renders the Student Payment Report)
Overview
 → Dashboard → /college/dashboard
 → Student Statistics → /stats
 → Search → /search  (refused by API)
Finance
 → Student Payment Report → /college/payments
 → Fee Setup and Schedule → /finance/fees  (refused by API — finance READERS exclude financecontroller)
Academic
 → College Overview → /college
 → Professional Examinations → /college/examinations
 → College Calendar → /college/calendar
Students
 → Postings → /college/postings
 → Logbooks → /college/supervision
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.13 Director of Internal Audit (`audit`)

```text
Director of Internal Audit — home: Payment Vouchers → /  (Audit dashboard)
Overview
 → Payment Vouchers → /
 → Search → /search
Students
 → Records & Queries → /records
Finance
 → A Voucher in Full → /vouchers
 → Revenue & Student Income → /audit/revenue
 → Ledger → /finance/ledger
 → Reconciliation → /finance/reconcile
 → Payroll Variance → /payroll/variance
 → Assets Register → /audit/assets
Staff
 → Staff Movements → /audit/staff
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.14 Deputy Director of Audit (`deputyaudit`) — fallback menu

```text
Office (fallback) — home: Dashboard → /  (Audit dashboard)
Records
 → Search → /search  (refused by API)
 → Dashboard → /
Me
 → Leave & Payslip → /me
```

> **Note:** The office has no menu of its own. It may act on `/vouchers` (WITH_DEPUTY and WITH_AUDITOR desks), `/finance/reconcile`, `/finance/ledger`, `/finance/accounting` (read), `/stores` (read), `/finance/tenders` and `/finance/budget` (read), `/reports`, `/audit` and `/governance` (read) by typing the URL. Status: PARTIALLY IMPLEMENTED (menu missing).

### 2.15 Director of Human Resource Management (`hrm`)

```text
Director of HRM — home: Movements → /  (HR dashboard; titled "Staff movements")
Overview
 → Movements → /
 → Search → /search
Students
 → Records & Queries → /records
Finance
 → Payroll → /payroll
Staff
 → Open a Movement → /hr/movements
 → Staff Records → /staff
 → Recruitment → /hr/recruitment
 → Leave Requests → /hr/leave
 → Appraisal → /hr/appraisal
 → Upload Non-Academic Staff → /people/staff
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.16 Provost, College of Health Sciences (`provost`)

```text
Provost (CHS) — home: Dashboard → /college/dashboard
Overview
 → Dashboard → /college/dashboard
 → Student Statistics → /stats
 → Search → /search  (refused by API)
Academic
 → Student Payment Report → /college/payments
 → College Overview → /college
 → Professional Examinations → /college/examinations
 → College Calendar → /college/calendar
Students
 → Deferments → /deferments
 → Postings → /college/postings
 → Logbooks → /college/supervision
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.17 College Secretary, College of Health Sciences (`collegesecretary`)

```text
College Secretary (CHS) — home: Dashboard → /college/dashboard
Overview
 → Dashboard → /college/dashboard
 → Student Statistics → /stats
 → Search → /search  (refused by API)
Academic
 → Student Payment Report → /college/payments
 → College Overview → /college
 → Professional Examinations → /college/examinations
 → College Calendar → /college/calendar
Students
 → Deferments → /deferments
 → Postings → /college/postings
 → Logbooks → /college/supervision
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.18 MBBS Coordinator, College of Health Sciences (`mbbscoordinator`)

```text
MBBS Coordinator — home: Dashboard → /college/coordinator
Overview
 → Dashboard → /college/coordinator
 → Search → /search  (refused by API)
Academic
 → Score Sheet → /college/scoresheets
 → Professional Examination → /college/examinations
 → College Calendar → /college/calendar
 → College Overview → /college
Students
 → Postings → /college/postings
 → Logbooks → /college/supervision
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.19 Dean (`dean`)

```text
Dean — home: Dashboard → /  (Dean dashboard)
Overview
 → Dashboard → /
 → Search → /search
Academic
 → Teaching Allocation → /allocate
 → Result Desk → /results/desk
 → Faculty Board → /results/approvals
 → Result Pipeline → /results/pipeline
 → Broadsheet → /results/broadsheet
 → Approval Chain → /results/chain
 → Graduation List → /graduation
 → Score Entry → /results/sheets
 → Upload Results (bulk) → /results/sheets  (same page)
 → My Score Sheets → /results/sheets  (same page)
 → Who May Register It → /eligibility
 → Course Spaces → /lms
 → Upload Material → /lms?tab=upload
 → Research in the Faculty → /research/projects  (refused by API — grants readers exclude dean)
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → Faculty Clearance → /clearance
 → Records & Queries → /records
 → Students → /students
 → Registered Students → /registration/class-list
Admissions
 → PG Admissions → /admissions/postgraduate
Finance
 → Faculty Budget → /finance/budget  (refused by API — budget readers exclude dean)
 → Requisitions → /finance/requisitions
Reports
 → Reports & Returns → /reports  (returns open cut to scope; due register and "Keep a copy" refused by API)
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.20 Faculty Officer (`facultyofficer`)

```text
Faculty Officer — home: Result Desk → /  (Dean dashboard)
Overview
 → Result Desk → /
 → Search → /search
Academic
 → Result Pipeline → /results/pipeline
 → Broadsheet → /results/broadsheet
 → Approval Chain → /results/chain
 → Score Sheets → /results/sheets
Students
 → Deferments → /deferments
 → Records & Queries → /records
 → Students → /students
 → Registered Students → /matriculation  (the faculty-list desk of matriculation)
Reports
 → Reports & Returns → /reports  (due register and "Keep a copy" refused by API)
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.21 Faculty Examinations Officer (`facultyexams`)

```text
Faculty Exams Officer — home: Scrutiny Desk → /  (Exams dashboard)
Overview
 → Scrutiny Desk → /
 → Search → /search
Academic
 → Result Pipeline → /results/pipeline
 → Broadsheet → /results/broadsheet
 → Approval Chain → /results/chain
 → Score Sheets → /results/sheets
 → Examinations → /examinations/sessions
Students
 → Records & Queries → /records
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.22 Head of Department (`hod`)

```text
Head of Department — home: Dashboard → /  (HOD dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Search → /search
Academic
 → Teaching Allocation → /allocate
 → Department Courses → /catalogue
 → Programme Structure → /catalogue/structure
 → Result Desk → /results/desk
 → Departmental Approvals → /results/approvals
 → Result Queries → /results/queries
 → Result Pipeline → /results/pipeline
 → Broadsheet → /results/broadsheet
 → Approval Chain → /results/chain
 → Score Sheets → /results/sheets
 → Score Entry → /results/sheets  (same page)
 → Upload Results (bulk) → /results/sheets  (same page)
 → Who May Register It → /eligibility
 → Course Spaces → /lms
 → Upload Material → /lms?tab=upload
 → My Teaching & Timetable → /me/teaching
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → Department Clearance → /clearance
 → Inter-Departmental Transfer → /transfers
 → Records & Queries → /records
 → SIWES Supervision → /siwes
 → Registered Students → /registration/class-list
 → Students → /students
Admissions
 → PG Admissions → /admissions/postgraduate
Finance
 → Requisitions → /finance/requisitions  (refused by API — requisition readers/raisers exclude hod)
Staff
 → Department Staff → /hod/staff
 → Leave Requests → /hr/leave
 → Appraisal → /hr/appraisal
Reports
 → Reports & Returns → /reports  (due register and "Keep a copy" refused by API)
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.23 Examinations Officer (Programme) (`exams`)

```text
Exams Officer — home: Dashboard → /  (Exams dashboard)
Overview
 → Dashboard → /
 → Search → /search
Academic
 → CBT Sessions → /examinations/sessions  (mislabelled: opens the results Examination Sessions; no CBT delivery exists)
 → Question Bank → /exams/question-bank
 → Score Sheets → /results/sheets
 → Approval Chain → /results/chain
 → Verification Queue → /results/approvals
 → Result Queries → /results/queries
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Records & Queries → /records
 → Examination Roll → /registration/class-list
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.24 Lecturer (`lecturer`)

```text
Lecturer — home: Dashboard → /  (Lecturer dashboard)
Overview
 → Dashboard → /
 → Notifications → /me/notices
 → Search → /search
Academic
 → My Courses & Timetable → /me/teaching
 → Score Sheets → /results/sheets
 → Course Spaces → /lms
 → Upload Material → /lms?tab=upload
 → My Projects → /research/projects  (refused by API — grants readers exclude lecturer)
Students
 → Registered Students → /registration/class-list
 → Postings I Supervise → /college/supervision
 → My SIWES Students → /me/siwes
History
 → Score Sheet History → /results/sheets/history
 → Course History → /me/courses
Me
 → My Profile → /me/profile
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.25 SIWES Coordinator (`siwes`)

```text
SIWES Coordinator — home: Dashboard → /  (SIWES dashboard)
Overview
 → Dashboard → /
 → Search → /search  (refused by API)
Students
 → SIWES Supervision → /siwes
 → My SIWES Students → /me/siwes
Me
 → ICT Support Tickets → /tickets
```

### 2.26 Dean, School of Postgraduate Studies (`pgschool`)

```text
Dean, Postgraduate School — home: Dashboard → /  (PG School dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Search → /search  (refused by API)
Academic
 → Courses → /admissions/postgraduate/courses
 → Calendar → /admissions/postgraduate/calendar
 → School Board → /admissions/postgraduate/board
 → Course Results → /admissions/postgraduate/results
 → External Examiners → /admissions/postgraduate/examiners  (the School's roster)
 → Examination Panels → /admissions/postgraduate/research?stage=DRAFT_SUBMITTED
 → Graduation List → /graduation  (refused by API — graduation readers exclude pgschool)
 → Results Broadsheet → /results/broadsheet  (refused by API — results READERS exclude pgschool)
 → Research Desk → /admissions/postgraduate/research
 → Thesis Clearance → /admissions/postgraduate/clearance
 → External Examiners → /examiners  (the University's external-examiner workspace)
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → PG Students → /admissions/postgraduate/students
Admissions
 → Admissions → /admissions/postgraduate
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.27 Secretary, School of Postgraduate Studies (`pgsecretary`)

```text
Secretary, Postgraduate School — home: Dashboard → /  (PG Secretary dashboard)
Overview
 → Dashboard → /
 → Student Statistics → /stats
 → Search → /search  (refused by API)
Academic
 → Courses → /admissions/postgraduate/courses
 → Calendar → /admissions/postgraduate/calendar
 → Registration → /admissions/postgraduate/registration
 → Course Examinations → /admissions/postgraduate/examinations
 → Research Seminars → /admissions/postgraduate/research?stage=PROPOSAL_APPROVED
 → Panels & Viva → /admissions/postgraduate/research?stage=DRAFT_SUBMITTED
 → External Examiners → /admissions/postgraduate/examiners
 → Thesis Clearance → /admissions/postgraduate/clearance
 → Course Results → /admissions/postgraduate/results
 → Results to Senate → /admissions/postgraduate/senate
 → Results Broadsheet → /results/broadsheet  (refused by API)
 → Graduation List → /graduation  (refused by API)
 → External Examiners → /examiners
 → Examiner Appointments → /examiners/appointments
 → Project Assignments → /examiners/projects
 → Assessments → /examiners/assignments
 → Examiner Reports → /examiners/reports
Students
 → Deferments → /deferments
 → PG Students → /admissions/postgraduate/students
Admissions
 → Admissions → /admissions/postgraduate
Finance
 → Fees → /finance/fees  (refused by API — finance READERS exclude pgsecretary; PG fees are set through the PG card on that page, which the office cannot load)
Reports
 → Reports & Returns → /reports
 → Student Register → /reports/students
 → Staff Register → /reports/staff
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.28 External Examiner (`extexaminer`)

```text
External Examiner — home: Dashboard → /examiner
External Examiner
 → Dashboard → /examiner
 → My Projects → /examiner/projects
 → Pending Reviews → /examiner/projects?filter=pending
 → Submitted Reviews → /examiner/projects?filter=submitted
 → My Profile → /examiner/profile
```

### 2.29 Deputy Registrar (Housing, Welfare and Passages) (`housing`)

```text
Housing & Welfare — home: Housing & Welfare → /  (Housing dashboard)
Overview
 → Housing & Welfare → /
 → Search → /search
Students
 → Records & Queries → /records
Staff
 → Staff Records → /staff  (refused by API — payroll readers exclude housing)
Accommodation
 → Hostel Dashboard → /hostel
 → Application Window & Rules → /hostel/window
 → Hostel Inventory → /hostel/inventory
 → Applications & Waitlist → /hostel/applications
 → Occupancy & Check-in → /hostel/occupancy
 → Checkout & Clearance → /hostel/clearance
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.30 Support Services (`services`)

```text
Support Services — home: Clinic → /clinic
Overview
 → Clinic → /clinic
 → Search → /search  (refused by API)
Students
 → Student Clearance → /clearance
 → Hostel Accommodation → /hostel
Finance
 → Requisitions → /finance/requisitions  (refused by API)
 → Tenders → /finance/tenders  (refused by API)
Services
 → Library Circulation → /library/circulation
 → Stores & Assets → /stores  (refused by API)
 → Alumni Register → /alumni  (refused by API — alumni readers exclude services)
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.31 Chief Security Officer (`security`)

```text
Chief Security Officer — home: Verify a Card → /  (Security dashboard)
Overview
 → Verify a Card → /  (placeholder label — no card-verification screen exists; the home renders the Security dashboard)
 → Search → /search
Students
 → Records & Queries → /records
Services
 → Card Collection → /credentials/idcards
 → Lost & Replacement → /credentials/idcards  (same page)
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.32 Librarian (`library`)

```text
Librarian — home: Card Printing → /credentials/idcards
Overview
 → Card Printing → /credentials/idcards
 → Search → /search
Students
 → Records & Queries → /records
 → Library Clearance → /clearance
Services
 → Circulation → /library/circulation
 → Stock & Acquisitions → /stores  (refused by API — stores readers exclude library)
Me
 → Leave & Payslip → /me
 → ICT Support Tickets → /tickets
```

### 2.33 Student — undergraduate (`student`)

```text
Student — home: Dashboard → /student
Start here
 → Dashboard → /student
 → School Fees — Pay First → /student/fees
Academic
 → Deferment → /student/deferment
 → Course Registration → /student/register
 → Registration History → /student/registration-history
 → Results → /student/results
 → Result Broadsheet → /student/broadsheet
 → Result Query → /student/query
 → Carryover → /student/carryover
 → Inter-Departmental Transfer → /student/transfer
 → My Documents → /student/documents
Learning
 → My Courses → /student/courses
 → Timetable → /student/timetable
 → Attendance → /student/attendance
 → Examinations → /student/exams
Services
 → Wallet & Funding → /student/wallet
 → Hostel → /student/hostel
 → Library → /student/library
 → Identity Card → /student/idcard
 → Health → /student/health
 → Help & Requests → /student/support
 → ICT Support Tickets → /tickets
Account
 → Profile → /student/profile
 → Biodata → /student/biodata
 → Notifications → /student/notifications
```

A College of Health Sciences student from 200 Level lands on `/college/student` (views Dashboard / Fees & payments / Course registration / Postings & logbook / Results history) and keeps the same menu.

### 2.34 Postgraduate student (`pgstudent` menu, office `student`)

```text
Postgraduate Student — home: Dashboard → /student
Overview
 → Dashboard → /student
Academic
 → Deferment → /student/deferment
 → Course Registration & Results → /student/pg-courses
 → Academic Progress → /student/pg-progress
 → My Documents → /student/documents
Finance
 → School Fees & Payments → /student/fees
 → Wallet & Funding → /student/wallet
Research
 → Research & Thesis → /student/research
Documents
 → Identity Card → /student/idcard
 → Library → /student/library
Communication
 → Notifications → /student/notifications
 → Help & Requests → /student/support
 → ICT Support Tickets → /tickets
Graduation
 → Graduation & Clearance → /student/graduation
Profile
 → My Profile → /student/profile
 → Biodata → /student/biodata
 → Health → /student/health
```

### 2.35 Applicant (`applicant`)

```text
Applicant — home: Overview → /applicant
My application
 → Overview → /applicant
 → Application Form → /applicant/apply
 → Application Fee → /applicant/fee
Screening
 → Screening Slip → /applicant/screening
 → Screening Result → /applicant/score
Admission
 → Admission Status → /applicant/status
 → Accept Your Offer → /applicant/accept
 → Document Clearance → /applicant/clearance
 → Matriculation → /applicant/matric
```

### 2.36 Postgraduate applicant (`pgapplicant` menu, office `applicant`)

```text
Postgraduate Applicant — home: pg/home (no route — placeholder; the portal opens at /pg/portal)
My application
 → Dashboard → /pg/portal
 → Apply Form → /pg/apply
 → Application Summary → /pg/summary/pdf  (a PDF route, not a page)
```

### 2.37 Screens on no menu

The following real screens are reached from buttons, links, QR codes or by URL only: `/students/{id}` (Student 360), `/deferments/{id}` and `/deferments/returns`, `/matriculation/faculty/{code}`, `/results/sheets/{id}`, `/examiners/{id}`, `/examiners/projects/{id}`, `/examiners/assignments/{id}`, `/examiners/rubrics`, `/examiner/projects/{id}`, `/lms/{offering}`, `/hostel/allocations/{id}`, `/hostel/students/{id}`, `/helpdesk/tickets/{id}`, `/tickets/new`, `/tickets/{id}`, `/support` (Help & requests desk — on no office menu at all), `/credentials/documents/requests`, `/credentials/documents/requests/{id}`, `/credentials/documents/register`, `/credentials/documents/settings`, `/admissions/putme/setup`, `/admissions/putme/candidates`, `/admissions/putme/batches/{id}`, `/admissions/putme/checkin`, `/admissions/screened`, `/admissions/screening/{batch}`, `/reports/{slug}/view`, `/reports/snapshots/{id}`, `/stats/students`, `/transfers/memo`, `/college/student`, `/student/form`, `/student/receipt/{reference}`, `/student/results/{session}/{semester}`, `/student/courses/{offering}`, `/student/transfer/letter/{id}`, `/account/password`, `/me/notices` (menu item on the lecturer menu only), `/ethics` (static), and the public pages `/login`, `/login/first`, `/login/forgot`, `/login/reset`, `/login/activate`, `/apply`, `/pg/referee/{token}`, `/track`, `/documents/d/{token}` and every `/verify/…` page.

---

## 3 Module catalogue

Every module is described against the same 22 points, as a two-column table, followed by one implementation-status line. "None" means nothing exists in the code for that point. Office codes are those of *04 Role and Permission Matrix*; guard constant names are the ones in the controllers. Every state table named is on the audit spine unless stated (see *08 Database Reference*).

### 3.1 Dashboard and home

| Point | Content |
|---|---|
| Purpose | `/` routes each office to its home and renders a read-only dashboard over the office's own modules; `/overview` and `/admin` draw the institutional read model as charts. |
| Users / roles | Every signed-in office; `/api/v1/reporting/overview` is `MANAGEMENT` (ict, admin, super, vc, dvc, registrar, dregistrar, academic, audit, bursar); HOD/Dean homes read `/hod/dashboard` (hod) and `/dean/dashboard` (dean, facultyofficer, super); the Provost dashboard endpoint has no frontend. |
| Navigation | Overview → Dashboard (every menu, various labels) → `/`; Administrator Dashboard → `/admin`; Institutional Overview → `/overview` (admin, dvc, registrar, vc). |
| Dashboard | This module *is* the dashboards; see §5 for every tile. |
| Main features | Office routing; ~18 office dashboards; StatsPanel (student statistics) embedded on Platform, Registrar, Academic, Bursar, HOD, PG and Overview; Overview charts (result sets, students by level/faculty, week-by-week, grade spread); Administrator scope re-cut by faculty. |
| Create | None. |
| View | Tiles, tables and charts; "desks" link panels. |
| Edit | None (the Platform dashboard hosts the People shortcuts and the Danger zone, which belong to §3.5 and §3.56). |
| Delete / deactivate | None. |
| Search | None (the top-bar search is §3.4). |
| Filters | Session and semester pickers on `/overview`; Scope buttons (University / faculty) on `/admin`. |
| Reports | None; tiles link to the returns and registers. |
| Export | DTable Print only; charts are inline SVG. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | None. |
| Validation rules | None. |
| Security | No scope cut on `/reporting/overview` (VC-level offices only); HOD/Dean homes resolve their unit from the grant scope, else the lecturer grant, else the staff record ("not tied to a department yet" when none). |
| Audit trail | Reads only. |
| Related modules | Every module; Statistics (§3.55); Reports (§3.54). |
| Common errors | "Your Head-of-Department office is not tied to a department yet" / "Your Dean office is not tied to a faculty yet"; an empty Overview when no session is CURRENT or no examination session is open. |
| Troubleshooting | Set the scope on the office grant (Users & Roles → Grant an office → "Which one"); make a session CURRENT on `/calendar`; open the examination session. |

**Status:** IMPLEMENTED — office routing, Overview and Administrator desks; PLACEHOLDER — the generic Office dashboard (hard-coded "Session 2026/2027"), the Registrar dashboard's "Council and Senate" sittings ("No sitting recorded") and its static NDPA-due note; PARTIALLY IMPLEMENTED — the Bursar dashboard's NELFUND and Held-scripts pills are always "Open", the HR dashboard's "Staff records" link opens `/people/lecturers`, and the Provost dashboard read model has no page.

### 3.2 Sign-in and account

| Point | Content |
|---|---|
| Purpose | One sign-in door for staff, students, applicants and postgraduate applicants; HS256 JWT bound to a server-side session; forgot/reset; forced change of a first password; Keycloak SSO with MFA (coded); bootstrap of the first account. |
| Users / roles | Public: sign-in, bootstrap, offices, forgot, reset, SSO start/callback, student/applicant/PG sign-in. Any signed-in person: sign-out, own sessions, change password. Student only: `/student-auth/sign-out`, `/student-auth/change-password`. Registry opens a student account (registrar, dregistrar, academic, records, ict, super). |
| Navigation | No menu item; `/login` and its links ("Forgot your password?", "First account", "Post UTME Registration", "Postgraduate application", "Verify a payment or receipt"); `/account/password` after a `mustChange` sign-in; sign-out in the sidebar foot. |
| Dashboard | None. |
| Main features | Identifier-shape routing to the right door; lockout (5 failures → 15 minutes); 12-hour session; deploy floor (sessions issued before the API restarted are refused); applicant password carried over to the student account; migrated students sign in with their own number as first password; reset token hashed, one hour, single use. |
| Create | Bootstrap (`/login/first`) creates the first person with registrar, academic, ict and super. |
| View | Sign-in hint names what the identifier looks like. |
| Edit | Change password (staff ≥ 10 characters, not containing the username; student ≥ 8). |
| Delete / deactivate | Sign-out ends the session; an ended person (`iam.person.ended_on`) is refused at the door. |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | None. |
| Notifications | "Reset your MOAUM password" (email + SMS) on a forgot request. Sign-in, lockout, change and bootstrap send nothing. |
| Approval workflow | None. |
| Statuses | `iam.sign_in_event.outcome`: SIGNED_IN, BAD_PASSWORD, UNKNOWN, LOCKED, SIGNED_OUT written (MUST_CHANGE, ENDED never written); credential events SET, RESET, CHANGED. |
| Validation rules | Username 3–200 lower-case, unique; bcrypt cost 12 (`$2…$12$`); `X-Active-Office` must be one of the token's offices; session id 32 bytes. |
| Security | Token in an httpOnly cookie (`moaum_session`); office in a readable cookie; CSRF disabled (stateless API); no rate limit on `/auth/forgot`, `/auth/reset` or sign-in; a Registrar cannot end another person's session; `/api/v1/platform/status` is public. |
| Audit trail | `iam.credential_event` attached; sign-in events are the log itself (exempt); failed attempts are written before the refusal so the lockout survives the rollback. |
| Related modules | Identity & accounts (§3.5); Applicant portal (§3.18); PG applicant portal (§3.19); External examiners (§3.22 — activation). |
| Common errors | "That username and password do not match an account."; "This account is locked after repeated failures; try again after HH:MM."; "No portal account has been opened for this number yet."; "The portal was updated. Sign in again."; "The office 'x' is not one this token carries"; "This reset link has expired or was already used." |
| Troubleshooting | Users & Roles → Reset password clears a lock; Student 360 → Portal account opens a student account; sign out and in after a grant changes; a reset mail needs an email on the person and a mail provider (§3.3). |

**Status:** IMPLEMENTED — password sign-in, one-door routing, student/applicant doors, forgot/reset, forced change, bootstrap, deploy floor; IMPLEMENTED (code) / NOT DEPLOYED — Keycloak SSO; PARTIALLY IMPLEMENTED — own-sessions list and end (backend only); NOT IMPLEMENTED — rate limiting, Registrar ending another's session; the sign-in card's matric-number hint regex predates the V263 number format.

### 3.3 Notices (outbox and my notifications)

| Point | Content |
|---|---|
| Purpose | The transactional outbox every module writes to (`platform.queue_notice`), the dispatcher that sends by SMTP, eBulkSMS or an HTTP relay, the office screens that show the outbox and retry failures, and the recipient's own list. |
| Users / roles | Outbox read: ict, admin, super, registrar; retry: ict, admin, super; mail/SMS settings `KEEPERS` = ict, admin, super; `/me/notices` any authenticated non-student; students read theirs on `/student/notifications` and the dashboard. |
| Navigation | Administration → Notifications (ict) / Notification Channels (super) → `/notices`; Mail Server → `/platform/mail`; SMS Gateway → `/platform/sms` (ict, admin); Overview → Notifications → `/me/notices` (lecturer only); Account → Notifications → `/student/notifications`. |
| Dashboard | Tiles Waiting / Sent today / Failed / Sent, all time; the Platform dashboard's "The outbox" panel. |
| Main features | Queue → dispatch every `MOAUM_NOTICES_EVERY_MS` (60 s) in batches of 50, up to 5 attempts; SMTP with branded HTML; eBulkSMS with 234-normalised numbers; generic/Termii/Resend relays; attachments up to 15 MB (kept returns); requeue of FAILED rows. |
| Create | Only modules create notices. |
| View | Outbox table (When, To, Notice, Channel, Attempts, State); `/me/notices` with All / This week / By email / Not delivered tiles and expandable bodies. |
| Edit | Mail and SMS settings (host, port, encryption, account, password/API key pasted once). |
| Delete / deactivate | "Clear the password" / "Clear the API key"; SMS "Send SMS notices through eBulkSMS" checkbox. |
| Search | `/me/notices` search box and Channel filter. |
| Filters | Channel (Email and SMS / Email / SMS). |
| Reports | None. |
| Export | DTable Print only. |
| Notifications | This module is the transport; it originates none. |
| Approval workflow | None. |
| Statuses | `platform.notice.state` QUEUED → SENT / FAILED (after the fifth failure); channel EMAIL / SMS. |
| Validation rules | Encryption STARTTLS/SSL/NONE; ports 1–65535; sender id ≤ 11; a blank recipient queues nothing; a password needs `MOAUM_CONFIG_KEY` (or the HMAC secret) to encrypt. |
| Security | Secrets encrypted at rest with pgcrypto; screens learn only "set"; outcome written as NOBODY/`ict` "notice dispatch". |
| Audit trail | `platform.notice`, `notice_attachment` attached; settings tables exempt, their SET/CLEARED events attached. |
| Related modules | Every module that notifies (§8); Platform (§3.56). |
| Common errors | Notices stay "Queued" (no provider); "Failed" with `provider answered 4xx` or `AuthenticationFailedException`; "No passphrase to encrypt the password with". |
| Troubleshooting | Set SMTP on Mail Server or enable eBulkSMS or set the relay URLs; fix the credential and "Put all n failed back in the queue"; set `MOAUM_CONFIG_KEY`. |

**Status:** IMPLEMENTED — outbox, dispatcher, settings screens, my notifications; PARTIALLY IMPLEMENTED — the outbox screen's "provider wired" indicator reads only the relay URLs (it can say "No provider is wired" while SMTP/eBulkSMS are delivering) and the Mail Server footer note about SMTP "not yet enabled" is stale; CONFIGURED BUT UNUSED — `platform.idempotency_key`, `platform.processed_event`.

### 3.4 Search

| Point | Content |
|---|---|
| Purpose | One box that finds a student, a member of staff, a course or a credential and opens the record. |
| Users / roles | The menu item is on every staff menu; the data call `/api/v1/student/search` is guarded by the student module's readers (academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, ict, admin, super, bursar, library, security, housing, hrm, audit, lecturer). |
| Navigation | Overview → Search → `/search`; top bar "Search records ⌘/"; the `/` key. |
| Dashboard | None; hit counts on the kind tabs. |
| Main features | Kind tabs Everything / Students / Staff / Courses / Credentials; "Exact match on {identifier}" note with Open; recent searches (localStorage); every search logged. |
| Create | None. |
| View | Per-kind panels (Identifier, Name, Detail, Status, Action); student and staff rows open modals. |
| Edit | None. |
| Delete / deactivate | None. |
| Search | The whole module. |
| Filters | `?kind=`. |
| Reports | None; `people.search_log` has no reader ("the Registrar reviews the log quarterly" is a comment, not a screen). |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | None. |
| Validation rules | LIKE wildcards escaped. |
| Security | Refused for provost, collegesecretary, financecontroller, mbbscoordinator, pgschool, pgsecretary, services, siwes, ictagent and deputyaudit although the item is on their menus; available to lecturer, security and hrm. |
| Audit trail | `people.search_log` (kind, term, hits) attached. |
| Related modules | Student records (§3.23); Staff (§3.46); Public verification (§3.53). |
| Common errors | "You do not have access to that" for the ten refused offices; course "Open" and credential "Verify" buttons disabled. |
| Troubleshooting | Search as an office in the reader list; verify a credential at `/verify/document` instead. |

**Status:** IMPLEMENTED — students and staff; PARTIALLY IMPLEMENTED — course and credential hits found but their buttons are disabled with stale text; menu/guard mismatch for ten offices.

### 3.5 Identity and accounts (Users & Roles, staff uploads)

| Point | Content |
|---|---|
| Purpose | Create a person, give them a sign-in, grant offices under an instrument with a scope, end grants, onboard teaching and non-academic staff in bulk. |
| Users / roles | `READERS` registrar, dregistrar, hrm, ict, admin, super, audit; `CREDENTIALS` registrar, dregistrar, ict, admin, super; `GRANTORS` registrar, dregistrar, vc, super, ict, admin; `STAFF_LOADERS` registrar, dregistrar, hrm, ict, admin, super; lecturer import ict, super, admin, registrar, dregistrar. |
| Navigation | Administration → Users & Roles → `/people` (super, ict, admin); Staff → Upload Lecturers → `/people/lecturers` (super, ict, admin); Staff → Upload Non-Academic Staff → `/people/staff` (super, ict, admin, registrar, dregistrar, hrm); Platform dashboard shortcuts `/people?new=person`, `/people?new=grant`. |
| Dashboard | Tiles Accounts / Staff accounts / Holding two offices / Grants expiring in 30 days; "People and access" panel on the Platform dashboard. |
| Main features | New person; Contact; Create/Reset credential (first password ≥ 10, `must_change`); Grant an office with scope kind and "Which one"; End a grant with a dated reason; lecturer import (person + sign-in `P<PNO>` + lecturer office + establishment record, chunks of 25, idempotent); non-academic dry run then load (no sign-in, no office); edit/delete lecturers; unit register. |
| Create | POST `/iam/persons`; `/iam/persons/{id}/office-assignments`; `PUT …/credential`; `/iam/lecturers/import`; `/iam/staff/import`. |
| View | "People on the register" and "Staff accounts and the offices they hold"; "Teaching staff on record" (first 500); "Non-Academic Staff" and "The Unit Register" tabs. |
| Edit | Contact; Edit lecturer (department move re-scopes the office); Reset password. |
| Delete / deactivate | End a grant (never deleted); Delete selected lecturers (kept when they already teach). Ending a person from the UI is NOT IMPLEMENTED. |
| Search | "Find a person" (name, staff number, username); lecturer search; staff search. |
| Filters | None beyond search. |
| Reports | Staff register (§3.54). |
| Export | Template workbooks "Teaching staff template.xlsx" and "Non-academic staff template.xlsx". |
| Notifications | None (the first password is told out of band). |
| Approval workflow | None — any grantor may grant any office including `super`; no two-person rule. |
| Statuses | Person: active / ended; grant: live while `valid_from ≤ today ≤ valid_to`; credential pills Active / Locked / "Password to change" / "No account". |
| Validation rules | Instrument required ("An office is held under a letter or minute; none was given."); scope kind ∈ institution, college, faculty, department, programme, course, unit, platform, level; `valid_to ≥ valid_from`; MBBS Coordinator grant must be `level` 200–600 held by a College lecturer; staff number unique (409). |
| Security | Grantor is the acting person, never the body; `GET /iam/persons` exposes username, lock state and last sign-in to seven reader offices; lecturer import issues predictable first passwords with `must_change`. |
| Audit trail | `iam.person`, `iam.office_assignment`, `iam.credential_event` attached; `iam.credential` exempt (holds the hash). |
| Related modules | Sign-in (§3.2); HRM (§3.45 — `hrm.staff_record` written by the importers); every scoped office. |
| Common errors | "'x' is not one of the offices in ref.office."; "n with no matching department"; rows "Not placed"; person cannot sign in ("No account", future `valid_from`, signed in before the grant). |
| Troubleshooting | Create the department first and re-upload; ask ICT for a unit alias; "Create account"; sign out and in. |

**Status:** IMPLEMENTED — people console, grants, credentials, both uploads, scope enforcement in code, waiting badges; NOT IMPLEMENTED — ending a person (leaver) from the UI; PLACEHOLDER — `/me` appraisal/appointment/increment tiles.

### 3.6 Audit trail and security posture

| Point | Content |
|---|---|
| Purpose | Read the hash-chained audit spine (every attached table's before/after with actor, office, reason and correlation id) together with sign-in events; read the spine's health and the sign-in defence; the Internal Audit directorate's read-only desks over finance, payroll and assets. |
| Users / roles | `OVERSIGHT` for `/audit/entries` and `/facets`: ict, admin, super, audit, deputyaudit, vc; `/governance/security`: ict, audit, deputyaudit, security, registrar, vc, dvc, admin, super; `/audit/revenue|staff|assets` read finance, payroll and stores endpoints (audit office). |
| Navigation | Administration → Audit Log / Audit Trail → `/audit` (super, ict, admin, vc; registrar — refused); Security / Security Posture → `/security` (super, ict, admin, vc); Finance → Revenue & Student Income `/audit/revenue`, Assets Register `/audit/assets`; Staff → Staff Movements `/audit/staff` (audit). |
| Dashboard | Tiles Entries on the record / Today / Actors today / Refusals today; posture tiles Audit entries / Unattached tables / Failed sign-ins 7 days / Last audit entry; the Audit and Security dashboards at `/`. |
| Main features | Facets by domain (`split_part(action, ':', 1)`) and acting office over 30 days; "Most recent n" (200, max 500); sign-in rows as `auth:<outcome>`; posture with "Sign-in defence" and "Accounts drawing failed attempts". |
| Create | None (the spine writes itself). |
| View | When, Actor (name or "System", office), Action (red pill when it matches refus/denied/blocked), Subject (type, first 8 chars of id), Reason. |
| Edit | None — "The audit trail cannot be edited through the application". |
| Delete / deactivate | None; no application role holds DELETE anywhere (`verify.sql`). |
| Search | None. |
| Filters | Domain, Acting office (query parameters). |
| Reports | None; no chain-verification report screen. |
| Export | DTable Print only. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | None. |
| Validation rules | `audit.exempt` needs a reason longer than 20 characters; office on an entry non-empty ≤ 32; shard 0–15. |
| Security | `before_state/after_state` stored but not shown; credentials, gateway keys and mail/SMS settings are exempt so secrets never enter the trail; a refused (rolled-back) write leaves **no** entry despite the screen's note. |
| Audit trail | `audit.entries` partitioned by month, 16 shards, `entry_hash = sha256(canonical ‖ prev_hash)`; `audit.verify_chain` exists but is called only by `db/check.sql`. |
| Related modules | Every module; Platform (§3.56 — `NO_ACTING_OFFICE` problem). |
| Common errors | 403 "This request names no acting office, so it may read but not change anything."; "no such office: x"; Registrar sees "You don't have access to this screen" on `/audit`. |
| Troubleshooting | Choose an office in the sidebar; developer databases show integration-test residue as "Unattached tables". |

**Status:** IMPLEMENTED — spine, trail screen, posture, audit desks; PARTIALLY IMPLEMENTED — "refusals on the trail" (only explicit REFUS actions and failed sign-ins); NOT IMPLEMENTED — nightly chain verification (claimed on the Security screen), Registrar access to `/audit` (menu only); `/audit/revenue` defaults to a hard-coded `2026/2027`.

### 3.7 API keys (Integrations / API Management)

| Point | Content |
|---|---|
| Purpose | A register of external API consumers with hashed, expiring keys shown once. |
| Users / roles | `OPERATORS` ict, admin, super. |
| Navigation | Administration → Integrations (super) / API Management (ict) → `/api-keys`. |
| Dashboard | Tiles Consumers (active/total) / Live keys / Due for rotation (within 14 days). |
| Main features | Register a consumer (name, owner, space-separated scopes, daily quota); issue a key (`mk_<48 hex>`, 1–366 days, shown once); revoke; deprecate. |
| Create | `POST /apimgmt/consumers`; `POST /consumers/{id}/keys`. |
| View | One panel per consumer; key table (`••••last4`, issued, expires, state). |
| Edit | None. |
| Delete / deactivate | Revoke a key; Deprecate a consumer (revokes its live keys). |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Consumer ACTIVE / DEPRECATED; key Live / "Due to rotate" / Expired / Revoked. |
| Validation rules | Name and owner ≤ 120, scopes ≤ 400, all required ("a consumer is named, owned and scoped"); "no active consumer to issue a key to"; "no live key to revoke". |
| Security | Keys hashed (SHA-256) at rest — but **no request path authenticates by API key**; scopes and quotas are stored, never enforced. |
| Audit trail | `apimgmt.consumer`, `apimgmt.key` attached. |
| Related modules | None. |
| Common errors | "no active consumer to issue a key to"; lost plaintext (never recoverable). |
| Troubleshooting | Revoke and issue another. |

**Status:** IMPLEMENTED — the register; NOT IMPLEMENTED — API-key authentication, scope and quota enforcement (the screen's "rate-limited" wording is aspirational).

### 3.8 Governance, NDPA and disaster recovery

| Point | Content |
|---|---|
| Purpose | The NDPA record of processing activities with DPIA state, the data-subject rights request log with statutory due dates, and the DR drill log; three explanatory framework pages. |
| Users / roles | `READERS` registrar, dregistrar, ict, audit, deputyaudit, vc, dvc, admin, super; `WRITERS` (DPIA, DSR) registrar, dregistrar, ict, super; `ICT` (record a drill) ict, super. |
| Navigation | Administration → Governance / Data Governance → `/governance` (super, ict, admin, registrar, vc); Backups & Recovery / Disaster Recovery → `/disaster-recovery` (super, ict); Cloud Readiness → `/cloud`, Release Pipeline → `/release` (ict); `/ethics` on no menu. |
| Dashboard | Tiles Processing activities / DPIAs outstanding / Open subject requests / Overdue requests; DR tiles Last restore verification / Last full DR drill / Drills on record / Failed drills. |
| Main features | Mark a DPIA done; log a DSR (`DSR-YYYY-NNNN`, due in 30 days by default); Start and Complete a DSR; record a drill with RPO/RTO achieved. |
| Create | `POST /governance/dsr`; `POST /governance/dr`. |
| View | Record of processing activities; DSR table (Reference, Type, Requester, Due, Status); drill log; static "Recovery objectives" table. |
| Edit | DPIA state OUTSTANDING → COMPLETE; DSR advance. No endpoint adds or edits a processing activity. |
| Delete / deactivate | None. |
| Search | None. |
| Filters | None. |
| Reports | None; the Registrar dashboard's "NDPA Compliance Audit Return is due on 31 March" is static text. |
| Export | DTable Print only. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | DPIA NOT_REQUIRED / OUTSTANDING / COMPLETE; DSR RECEIVED → IN_PROGRESS → COMPLETED (REFUSED allowed but unreachable from the screen); drill kind RESTORE_VERIFY / FULL_DR / FAILOVER / BACKUP, outcome PASSED / FAILED / PARTIAL. |
| Validation rules | Requester ≤ 200, note ≤ 400, state ≤ 20; reference unique. |
| Security | A DSR can be completed without a note; no link to the subject's record. |
| Audit trail | `governance.processing_activity`, `dsr`, `dr_drill` attached. |
| Related modules | Platform (§3.56). |
| Common errors | "Mark done" invisible (office not a writer); 422 `DATABASE_RULE_REFUSED` on a state outside the CHECK. |
| Troubleshooting | Act as registrar, dregistrar, ict or super. |

**Status:** IMPLEMENTED — register read, DPIA completion, DSR log, drill log; NOT IMPLEMENTED — backup telemetry and RPO/RTO measurement (objectives are typed in the TSX), adding processing activities, DSR REFUSED, reminders; PLACEHOLDER — `/cloud`, `/release`, `/ethics`.

### 3.9 Academic calendar and sessions

| Point | Content |
|---|---|
| Purpose | The session/semester calendar every module reads: the CURRENT session under a Senate minute, each semester's windows (lectures, registration, late registration, examinations, results due, query window), the unit limits per level, the yearly roll-over and the enrol-all backfill. |
| Users / roles | Read: any authenticated user; `WRITERS` academic, registrar, dregistrar, super, ict. |
| Navigation | Academic → Session & Semester Setup → `/calendar` (academic, super only; registrar, dregistrar, ict reach it by URL). |
| Dashboard | Tiles Current session / Current semester / Registration (Open/Closed) / Score sheets due. |
| Main features | New/Edit session (state Planned/Current/Closed, Senate minute); End/Reopen; semester windows; level unit limits; "Roll into {session}" (promotes continuing students; word ROLLOVER + reason); "Enrol all into {session}". |
| Create | `PUT /calendar/sessions/{s}`; `PUT …/semesters/{n}`; `PUT /calendar/levels/{level}`. |
| View | Academic sessions table (Opens, Closes, Senate minute, Students, State); Semesters of {session}; Levels and unit limits. |
| Edit | Sessions, semesters, levels; `make-current` with a minute. |
| Delete / deactivate | End this session (`/close`) with a reason; Reopen. |
| Search | None. |
| Filters | `?session=`. |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None (the Senate minute is typed). |
| Statuses | Session PLANNED / CURRENT / CLOSED (exactly one CURRENT; no overlap); semester NOT_YET_OPEN / OPEN / CLOSED. |
| Validation rules | Name `dddd/dddd`; `ends_on > starts_on`; CURRENT needs a non-blank minute ("A session stays planned until its Senate minute is recorded against it, and none was given."); semesters 1–3; date-order checks; level 100–900, `max ≥ min ≥ 0`. |
| Security | Readable by every office including students; writes by five offices. |
| Audit trail | `policy.academic_session`, `policy.semester`, `policy.level_limit` attached. |
| Related modules | Registration (§3.13 — windows and limits); Results (§3.30); Finance (§3.36 — semester-tagged charges); Deferments (§3.25); Readiness (§3.56). |
| Common errors | Overlap 422 (`ex_session_no_overlap`); second CURRENT 409; Readiness "No semester is open". |
| Troubleshooting | Fill the Senate minute; fix the dates (integration-test residue sessions can overlap); set a semester OPEN here — exam dates do not open the examination session (§3.30). |

**Status:** IMPLEMENTED; PARTIALLY IMPLEMENTED — no menu item for registrar/dregistrar/ict; the level select offers 100–600 only (700–900 rows are edited through their existing-row Edit); `probation_max_units` is NULL for every level (the probation ceiling is CONFIGURED BUT UNUSED).

### 3.10 Reference data and academic structure

| Point | Content |
|---|---|
| Purpose | Faculties, departments and programmes — the structure ladder every module reads, created, uploaded, archived or removed by the Director of ICT alone. |
| Users / roles | `UPLOADERS` = ict only (create, import, delete, archive); `READERS` every academic office; `/ref/structure`, `/ref/sessions`, `/ref/courses` any authenticated user, pruned to the caller's scope. |
| Navigation | Academic → Upload or Create Faculties `/structure/faculties`, Departments `/structure/departments`, Programmes `/structure/programmes` (ict). |
| Dashboard | Upload-coverage tiles on the Platform dashboard (`/catalogue/upload-coverage`). |
| Main features | Add/Edit form; template download; .xlsx/.csv upload (`ref.import_*`); archive/restore a programme; delete only when nothing hangs on it. |
| Create | `POST /catalogue/faculties|departments|programmes` (upsert) and `/import`. |
| View | Tables Code / Name / Departments / Programmes; Code / Programme / Faculty / Department / Category / Min. |
| Edit | Same form (code locked on edit). |
| Delete / deactivate | Delete icon (disabled while the unit has children); Archive/Restore a programme (`ref.set_programme_archived`). |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | Branded Excel and PDF (serials FAC, DEP, PRG; S/N first, names A–Z). |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Programme archived / live; category UNDER GRADUATE / POST GRADUATE. |
| Validation rules | Programme code `^C[0-9]{5}$`; department needs a faculty; "still has N programme(s)" blocks a delete. |
| Security | ICT-only at the API since commit `8c2b6fa`; the course-upload note still names HODs (stale). |
| Audit trail | `ref.faculty`, `ref.department`, `ref.programme` attached; `ref.office` migration-seeded, no screen. |
| Related modules | Courses & catalogue (§3.11); Matriculation format (§3.24 — `matric_code`, `matric_series` on faculty/programme); Admissions (§3.17 — JAMB aliases). |
| Common errors | "no programme is coded or named X"; "the programme % has no department on the register to own its courses"; import counters `bad_code`, `no_faculty`. |
| Troubleshooting | Upload faculties → departments → programmes in that order; set the programme's department. |

**Status:** IMPLEMENTED.

### 3.11 Courses and catalogue

| Point | Content |
|---|---|
| Purpose | Courses owned by a department (BOARD → LIVE → ENDED), the programme structure that binds courses to a programme at a level on a basis and for a curriculum track, the bulk course-structure upload (.docx/.xlsx), duplicate clean-up, curriculum and CA/exam split tagging, and opening course registration for a session. |
| Users / roles | Structure upload `POST /catalogue/import` ict only; `OWNERS` (course/structure writes) hod, dean, academic, dregistrar, registrar, admin, super — an HOD confined to their department; `OPENERS` (open registration) ict, super, admin, hod, dean, academic, registrar, dregistrar; `READERS` add lecturer, exams, facultyexams, facultyofficer, records, dvc, vc. |
| Navigation | Academic → Upload or Create Courses → `/catalogue/upload` (ict); Department Courses → `/catalogue` (hod); Programme Structure → `/catalogue/structure` (hod); Who May Register It → `/eligibility` (hod, dean). |
| Dashboard | Tiles Courses owned / Live / Awaiting approval / Live, no lecturer; structure tiles Courses bound / Levels / Borrowed / Without a semester. |
| Main features | New course (BOARD); Make live / End / Restore; Make N Live; Duplicate courses panel with "End N duplicate courses"; bulk "Set to CCMAS/BMAS" and "CA 40 / Exam 60" / "CA 30 / Exam 70"; per-course Curriculum and CA/Exam selects; bind/remove a course in a structure with basis Core/Elective/Borrowed/GST and track; CCMAS .docx parsed by headings; multi-programme .xlsx; "Open course registration for a session"; whole-catalogue export. |
| Create | `POST /catalogue/courses`; `POST /structure/bind`; `POST /catalogue/import`. |
| View | Department courses table (binding pills, Lecturer, State); structure per level with unit totals and min/max warnings; eligibility table (Programme, Department, Faculty, Level, Basis, Registered, Relation). |
| Edit | Curriculum tag, CA split, live/end/restore. |
| Delete / deactivate | End a course (soft, `ended_on`); Remove a binding (refused while students are registered on it this session). |
| Search | Course search across the University (≥ 2 characters) when binding. |
| Filters | Level / Semester / Kind / Programme; Track. |
| Reports | `GET /catalogue/upload-coverage` (Platform dashboard). |
| Export | Branded Excel/PDF: courses offered to a programme (CRS), the whole catalogue (CAT); templates for each upload. |
| Notifications | None. |
| Approval workflow | None in practice — courses go BOARD → LIVE directly; SENATE is never written. |
| Statuses | `catalogue.course.state` BOARD / SENATE / LIVE / ENDED; kind Core / Required / Elective / GST; curriculum CCMAS / BMAS / null; tracks BMAS, CCMAS_BSU, CCMAS_MOAU. |
| Validation rules | Form code `^[A-Z]{3}\s*[0-9]{3}$` ("a course code is three letters, a space and three digits, like CSC 311"); units 0–12; unique code; basis in four; ENDED course not bindable; `ca_max` 0–100 (default 40); import keeps LIVE/ENDED, lifts BOARD/SENATE to LIVE. |
| Security | HOD confinement (`assertHodOwns` → "A Head of Department manages the catalogue of their own department only."); structure uploads ICT-only. |
| Audit trail | `catalogue.course`, `course_offer`, `offering` attached; the bulk offering insert of open-registration runs with the audit trigger disabled. |
| Related modules | Reference data (§3.10); Registration (§3.13 — the menu); Allocation (§3.12); Results (§3.30 — `ca_max`). |
| Common errors | "Not bound to any programme — no student sees it at registration"; "N students … are registered on … this session; the binding stays while they are."; form refuses codes like `BSU-SOC 101` that the import accepts. |
| Troubleshooting | Bind the course on the structure; open registration for the session/semester; a CCMAS-tagged course is hidden from a BMAS student. |

**Status:** IMPLEMENTED; CONFIGURED BUT UNUSED — the SENATE course state; PARTIALLY IMPLEMENTED — direct course/offer/offering upserts under `/registration/…` (backend only); the course-upload note naming HODs is stale; the eligibility page title is fixed to "Who may register CSC 311".

### 3.12 Course allocation

| Point | Content |
|---|---|
| Purpose | Name the lead lecturer (who owns the score sheet), an optional second examiner (verifier) and co-lecturers for each offering of a session and semester; a 12-unit load ceiling unless saved as an overload; allocation creates the score sheet when the examination session is OPEN. |
| Users / roles | `ALLOCATORS` hod, dean, academic, dregistrar, registrar, admin, super (HOD bound to their department); `HISTORY_READERS` add lecturer, exams, facultyexams, facultyofficer, records; `/allocation/departments` any authenticated. |
| Navigation | Academic → Teaching Allocation → `/allocate` (hod, dean, admin); lecturer: History → Course History → `/me/courses`, Academic → My Courses & Timetable → `/me/teaching`. |
| Dashboard | Tiles Courses / Unassigned / No second examiner / Lecturers; HOD home tile "Courses without a Lecturer". |
| Main features | Assign/Manage modal with load "Current / After this" (red above 12), "Lecturers from other departments" checkbox, second examiner (cannot be the lead), co-lecturers; "Save as an overload (N units)". |
| Create | `POST /allocation/{offering}` `{lecturer, secondExaminer, overload}`; `POST /{offering}/teachers`. |
| View | Table Course / Level / Units / Registered / Lecturers / Second examiner; history by scope (me / department). |
| Edit | Manage the same modal. |
| Delete / deactivate | Remove a co-lecturer (`DELETE /{offering}/teachers/{lecturer}`). |
| Search | Lecturer search by name or staff number in the modal. |
| Filters | Department, Session, Semester, Level. |
| Reports | None ("reported to the Dean" for overloads is a HINT only). |
| Export | None. |
| Notifications | None. |
| Approval workflow | None; overload is a deliberate second button, not an approval. |
| Statuses | None (columns on `catalogue.offering`); a sheet appears once an exam session is OPEN. |
| Validation rules | "an allocation names the lecturer who teaches it"; "the second examiner cannot be the lecturer"; "this assignment puts the lecturer at N units, over the approved maximum of 12" unless overload; `ALLOC_ENDED`; `ALLOC_BUSY` after an 8 s lock wait; `ALLOC_DEPT` "A Head of Department allocates only courses that belong to their own department." |
| Security | Cross-department assignment allowed on purpose; HOD bound in code. |
| Audit trail | `catalogue.offering`, `offering_teacher` attached. |
| Related modules | Results (§3.30); LMS (§3.14); Courses (§3.11); Registration class list (§3.13). |
| Common errors | "over the approved maximum of 12"; sheet missing after allocation (no OPEN exam session); "No lecturer is on record for this department". |
| Troubleshooting | Save as an overload or choose another lecturer; open the examination session; grant a `lecturer` office scoped to the department or tick "Lecturers from other departments". |

**Status:** IMPLEMENTED; NOT IMPLEMENTED — overload report to the Dean.

### 3.13 Course registration, class lists, attendance and timetable

| Point | Content |
|---|---|
| Purpose | The student's course registration per session and semester from the menu the structure and offerings produce, with carryovers imposed; HOD approval or return; the class list, attendance register and timetable slots of an offering; the student's timetable and attendance rate. |
| Users / roles | Student (`OFFICE_student`) drafts, submits, adds, drops; approve/return hod, super (own department); desk list `DEPARTMENT` hod, lecturer, dean, facultyofficer, academic, registrar, dregistrar, super; class-list `READERS` (department offices held to their courses, a lecturer to their allocations); attendance and slots lecturer, hod, dean, super; `APPROVERS` may create/submit for a student (backend only). |
| Navigation | Student: Academic → Course Registration `/student/register`, Registration History, Learning → My Courses, Timetable `/student/timetable`, Attendance `/student/attendance`; staff: Students → Registered Students / Examination Roll → `/registration/class-list` (academic, dean, exams, hod, lecturer); Departmental Approvals → `/results/approvals` (hod; the registration panel appears there for the desk offices). |
| Dashboard | Class-list tiles Registered / owning department / Other programmes / Cleared to sit; HOD home "Registrations to approve"; Dean home "Registration by department". |
| Main features | Semester switcher; gate card (status, register, financial clearance, window); Core/GST and Elective pick lists; units meter against `policy.level_limit`; carryovers fixed; Save the draft / Submit for approval; Add or drop within the window; HOD Approve / Return with a reason; class list with Clearance flag; attendance (All present / None, per student, "Record N of M present"); timetable slots (Day, Kind, From, To, Venue); examination slot (results module). |
| Create | `PUT /me/registration`; `POST /me/registration/submit|add|drop`; `POST /registration/offerings/{id}/attendance|slots`. |
| View | Registration approvals table (Student, Programme, Level, Semester, Courses, Units of range, Submitted); class list (Matriculation number, Name, Programme, Level, Basis, Attendance "—", Clearance); student timetable and attendance (below 75 % "At risk"). |
| Edit | The student edits while DRAFT or RETURNED; add/drop after submission. |
| Delete / deactivate | Drop an entry (→ DROPPED); end a slot. |
| Search | None. |
| Filters | Scope bar (faculty, department, programme, course, session, semester). |
| Reports | `registration.registration_cause` feeds the Registration return (§3.54). |
| Export | Class list, attendance register and examination roll as plain CSV (not branded). |
| Notifications | None — submit, approve and return send nothing; the student reads a return on the registration screen. |
| Approval workflow | DRAFT → SUBMITTED → APPROVED (HOD) or RETURNED (with comment) → resubmitted; LOCKED exists but nothing sets it. |
| Statuses | `course_registration.status` DRAFT / SUBMITTED / APPROVED / RETURNED / LOCKED; `entry.status` REGISTERED / APPROVED / DROPPED / WITHDRAWN; `entry_type` CURRENT / CARRYOVER / REPEAT / ELECTIVE / GST / BORROWED. |
| Validation rules | Status ADMITTED/ACTIVE/PROBATION ("A student who is … does not register."); per-semester fee gate `finance.semester_cleared` ("the first semester school fees for … are not fully paid"); units within the level range ("the registration carries % units; at % level the range is % to %"); probation ceiling when set; deferment gate ("REGISTRATION UNAVAILABLE: your deferment for % is approved…"); SIWES semester carries exactly the SIWES units; add/drop window = semester OPEN and before `late_registration_closes`; a carryover cannot be dropped; a marked course cannot be dropped; return needs a comment. |
| Security | HOD approval bound to the department; a lecturer reads the class list of own courses only; `POST /registration/course-registrations` (office-created) inserts entries without menu validation. |
| Audit trail | `registration.course_registration`, `entry`, `attendance`, `catalogue.class_slot` attached; deferment gate and held-script release triggers. |
| Related modules | Courses (§3.11); Calendar (§3.9); Finance (§3.36); Deferments (§3.25); Results (§3.30 — rolls, held scripts); LMS (§3.14 — the roll). |
| Common errors | "add and drop is not open for …"; "that course is not offered to your programme at your level this semester"; "No core course is offered to your programme this semester yet"; "This registration is in another department."; "The industrial-training semester carries exactly N units". |
| Troubleshooting | Pay the semester's fees; open registration for the session (§3.11); bind the course; obtain a return from the HOD to edit a submitted form; there is no HOD overload mechanism despite the hint text. |

**Status:** IMPLEMENTED; NOT IMPLEMENTED — HOD overload approval, notifications; CONFIGURED BUT UNUSED — LOCKED status, probation unit ceiling; PARTIALLY IMPLEMENTED — office-created registration (backend only); the registration-history text "the Faculty Officer approved" is wrong (approval is the HOD's); the roll's Attendance column is always "—".

### 3.14 Course spaces (LMS)

| Point | Content |
|---|---|
| Purpose | Every offering with approved registrations is a course space: material (file ≤ 5 MB or link, draft or published), assignments with a weight in the 40-mark CA, submissions marked with feedback, engagement flags, and promotion of the gradebook total into the score sheet's CA column. |
| Users / roles | `TEACHERS` lecturer, hod, dean, academic, super (`requireTeaches`: the allocated lecturer, second examiner or co-lecturer; hod/dean/academic/super on any space); students on the roll under `/me/courses/**`. |
| Navigation | Academic → Course Spaces → `/lms`, Upload Material → `/lms?tab=upload` (lecturer, hod, dean); `/lms/{offering}`; student Learning → My Courses → `/student/courses`, `/student/courses/{offering}`. |
| Dashboard | Tiles Materials published / Assignments / Submissions / Never opened the space. |
| Main features | Upload course material (Title, Week, Kind Notes/Slides/Reading/Video/Audio/Other, Description, file or address, publish now or draft); Publish / Withdraw; assignments (title, closes, weight % of CA, kind Individual/Pairs/Group, brief, marked out of, late window hours, late penalty %); Mark/Review submissions; "Promote CA total to the score sheet" (only at ENTRY); engagement panel (High risk / Watch / On track). Student: read (every read counted), submit or replace (until marked), see marks and feedback. |
| Create | `POST /lms/offerings/{o}/materials`, `…/assignments`; student `POST /me/courses/assignments/{id}/submit`. |
| View | Published material (Item, Week, Size, Read by, state); Assignments; submissions modal; student space (materials read %, assignments due). |
| Edit | Mark and feedback; publish/withdraw. |
| Delete / deactivate | Withdraw material (`/end`). |
| Search | None. |
| Filters | Session on `/lms`. |
| Reports | None; the engagement note says it "feeds the early-warning report" — no such report exists. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Material draft → published → ended; assignment open → closed → late window → ended; submission unmarked / marked / late. |
| Validation rules | Types pdf, jpeg, png, text, csv, docx, pptx, xlsx, zip, mp3, mp4; 1 byte–5 MB; material needs a file or a link; weight 1–40; out_of 1–1000; penalty 0–100; late hours 0–720; "this submission is marked; it is not replaced"; "you are not registered and approved for this course"; promotion refused when "no score sheet exists for this offering yet" or "the score sheet has left the lecturer". |
| Security | Files served inline without `nosniff`/sandbox headers (unlike deferment documents); no virus or similarity check. |
| Audit trail | `lms.material`, `assignment`, `submission` attached; `lms.access` and the blobs are not. |
| Related modules | Allocation (§3.12); Registration (§3.13); Results (§3.30 — `lms.promote_ca` writes a score version). |
| Common errors | "This course space belongs to the lecturer the department allocated."; "A file is between 1 byte and 5 MB". |
| Troubleshooting | Ask the HOD to allocate; open the examination session before promoting; link large files by address. |

**Status:** IMPLEMENTED (0 rows in the local database); NOT IMPLEMENTED — similarity check, notifications, early-warning report.

### 3.15 Library

| Point | Content |
|---|---|
| Purpose | A small circulation system: catalogue items with accessioned copies, loans under one rule (loan days, fine per day, items at once, renewals), returns that post a fine, reservations, renewals, fine references paid through the Bursary, and the library standing read by clearance. |
| Users / roles | `DESK` library, services, admin, super; waive a fine and restate the rule: library, super; readers add registrar, dregistrar, academic, bursar, ict, audit; student: own loans, reservations and fine references. |
| Navigation | Services → Circulation → `/library/circulation` (library, services); student Services → Library → `/student/library`. |
| Dashboard | Tiles Copies in stock / On loan / Overdue / Fines unpaid. |
| Main features | Issue / Return / Renew by accession and patron number; "Look the patron up"; waive with a reason; catalogue add (Title, Author, Edition, Year, ISBN, Subject, Kind Book/Journal/Thesis/Audiovisual/Reference, Shelf, accession numbers); the rule in force; student Renew, "Generate the reference" for a fine, catalogue search and "Join the waiting list". |
| Create | `PUT /library/items`; `POST /library/loans`; `POST /me/library/reservations`. |
| View | Circulation today; Overdue; Fines unpaid; catalogue. |
| Edit | `PUT /library/setting` (librarian only). |
| Delete / deactivate | Copy LOST / WITHDRAWN (with a reason); no item delete. |
| Search | Catalogue `?q=`; patron lookup. |
| Filters | None. |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Copy AVAILABLE / ON_LOAN / RESERVED / LOST / WITHDRAWN; reservation WAITING / READY / FULFILLED (CANCELLED, EXPIRED never set); fine standing / settled / waived. |
| Validation rules | Accession `^[A-Z]{2,5}/[0-9]{4,8}$`; no overdue item, fewer than `max_loans`, no unpaid fine before an issue; a RESERVED copy only to its reserver; renew not beyond `max_renewals`, not overdue, nobody waiting; reserve only when no copy is on the shelf; rule CHECKs loan_days 1–120, max_loans 1–20, max_renewals 0–5. |
| Security | Students reach only their own loans; fine settlement depends on `finance.confirm_payment` calling `library.settle_by_reference`. |
| Audit trail | `library.item`, `copy`, `loan`, `reservation`, `setting` attached. |
| Related modules | Finance (§3.37 — fine references); Clearance (§3.28 — the LIBRARY unit is signed manually). |
| Common errors | "the patron has % overdue item(s)"; "an unpaid fine stands against the patron"; "no fine stands against this loan"; `LIB_NO_PATRON`. |
| Troubleshooting | Return the overdue item; settle or waive the fine. |

**Status:** IMPLEMENTED (unused in the local data: 0 items); CONFIGURED BUT UNUSED — reservation expiry/cancel; NOT IMPLEMENTED — automatic library clearance from standing (the student screen implies it).

### 3.16 SIWES / industrial training

| Point | Content |
|---|---|
| Purpose | A SIWES course (`industrial_training` flag) is supervised: assign a supervisor per registered student; the supervisor records an assessment out of 40 and the coordinator a practical mark out of 60 onto the offering's ordinary score sheet; GRADED only when both parts stand. |
| Users / roles | `ASSIGNERS` hod, siwes, academic, registrar, dregistrar, admin, super (department offices confined); supervisor endpoints any authenticated with ownership (`SIWES_NOT_YOUR_STUDENT`). |
| Navigation | Students → SIWES Supervision → `/siwes` (hod, siwes); My SIWES Students → `/me/siwes` (lecturer, siwes); SIWES dashboard at `/`. |
| Dashboard | Tiles Students / Supervisors assigned / Score sheet state / Course. |
| Main features | Session, Semester and SIWES course pickers; supervisor select per student; Practical /60 input with Save (a change prompts for the reason); supervisor's Assessment /40 on `/me/siwes`. |
| Create | `PUT …/supervisor`; `PUT …/practical`; `PUT /siwes/mine/students/{s}/score`. |
| View | Table Matric / Name / Programme / Supervisor / Assessment / Practical / Total. |
| Edit | A changed own part needs a reason (`SIWES_AMENDMENT_SAYS_WHY`). |
| Delete / deactivate | None. |
| Search | Searchable supervisor select. |
| Filters | Session, semester, offering. |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | Inherits the score sheet's chain (§3.30). |
| Statuses | Score outcome GRADED (both parts) / INCOMPLETE; sheet must be at ENTRY. |
| Validation rules | Marks 0–40 / 0–60; `SIWES_NO_SHEET` "The SIWES score sheet is not open yet."; `SIWES_SHEET_NOT_AT_ENTRY`. |
| Security | Department scoping; supervisors score only assigned students. |
| Audit trail | `assessment.siwes_supervisor` attached; marks in `assessment.score`. |
| Related modules | Results (§3.30); Registration (§3.13 — SIWES semester units). |
| Common errors | "No SIWES course this session and semester"; "The SIWES score sheet is not open yet." |
| Troubleshooting | Open the examination session; a new SIWES course needs the `industrial_training` flag set by migration or ICT — no screen writes it. |

**Status:** IMPLEMENTED — assignment, both marks; NOT IMPLEMENTED — flagging a course as industrial training from the portal, logbooks/placement records.

### 3.17 Undergraduate admissions

| Point | Content |
|---|---|
| Purpose | The office side of the UTME/Direct Entry cycle: admission settings put in force under a Central Admissions Committee minute; the load cut-off; CAPS lists loaded, committed or withdrawn; passports, dates of birth and O'Level recorded; screening seated and scored (legacy batches or the V260 CBT schedule with centres, rooms, slots, days, batches, publish, check-in by QR); merit lists, Board decisions and releases; the JAMB status list; intake to the register with admission numbers; Direct Entry screening; old-portal migration; reconsiderations. |
| Users / roles | `LOADERS` academic, registrar (CAPS, merit, DE awards, JAMB list, programme aliases); `READERS` academic, registrar, dregistrar, dvc, vc, records, ict, admin, super; `OFFICE` academic, registrar, dregistrar (decisions, releases, batches, scores); `CONFIRMERS` + bursar; `REGISTRY` + records (clearance recording); `IMPORTERS` + ict, super; `SCORE_UPLOADERS` academic, registrar, dregistrar, ict, admin, super; `/post-utme-computed` academic, super; settings `SECRETARIAT` academic, registrar, dregistrar (readers add dean, hod); intake `StudentController.WRITERS` academic, registrar, dregistrar; CBT `OFFICE` academic, registrar, dregistrar, super; `DOOR` academic, registrar, dregistrar, records, ict, super. |
| Navigation | Academic Office → Admissions group (fourteen items, §2.9, including Programme Eligibility `/admissions/eligibility`); Registrar → Post-UTME CBT Schedule, Admissions, Programme Eligibility, Admitted List; ict/admin → CBT Schedule, Post-UTME Scores (admin also Admissions); records, dregistrar, super → CBT Schedule; sub-pages `/admissions/putme/{setup,candidates,checkin,batches/{id}}`, `/admissions/screened`, `/admissions/screening/{batch}` from buttons. |
| Dashboard | Report on Admissions tiles Applications / Screened / Offers issued / Accepted; ApplicantsDesk tiles; CBT dashboard tiles, validation report and breakdowns; Academic dashboard "Committed admission list". |
| Main features | Settings (weights 70/30, ratios, four criteria, quotas, catchment, per-programme cut-off/quota/subject rules, O'Level grading, exam-screened programmes, "Put in force" with a CAC minute, "Begin from {previous}"); load cut-off; CAPS parse in the browser, alias mapper, load/commit/withdraw/reset; candidate data uploads; legacy screening batches and hall lists; CBT exam setup, generate, publish and notify, move, unschedule, postpone/cancel, attendance sheet, check-in desk; scores per application, bulk CSV, zero missing, from O'Level, release, clear; merit list (UTME only) and "Record all programmes"; decision modal; release decisions; JAMB status upload; "Bring N candidates onto the register" (intake); DE award capture; migrate old-portal applicants; reconsideration suggestions; **Programme Eligibility** (V266): every submitted applicant read against the settings — verdict, failed requirements, suggested programmes, server-side search and filters, View Matching Details, Recalculate / Evaluate the unevaluated, the programme-change queue (Approve revalidates and changes the programme; Reject needs a reason), three reports; the rule modal's required O'Level subjects, minimum grade and additional screening; the Subject equivalencies panel. |
| Create | Many (see §4.17–4.20); the intake `POST /api/v1/student/intake/{session}` is wired at `Admissions.tsx:49`. |
| View | Screening register, screened pool, hall list, applicants report, merit table, DE table, candidates table, batch page. |
| Edit | Settings while DRAFT (quotas, catchment, subject sets and closures remain editable in force); programme names/aliases; CBT places until publish. |
| Delete / deactivate | Withdraw a CAPS batch (reason, no student admitted from it); Reset the JAMB list (destructive, double confirm); Clear uploaded scores (type `CLEAR SCORES`); close a programme; cancel a CBT batch; reset migrated applicants. |
| Search | Programme type-aheads; applicant search (name or JAMB); candidate search on the CBT desk; check-in box (QR, application or JAMB number). |
| Filters | Faculty, Programme, Entry mode; CBT Standing, Faculty, Department, Programme, Batch, Centre. |
| Reports | Report on Admissions, Report on Post-UTME Registration, Screening Register, Screened pool, Computed Post-UTME, JAMB admission template (five-sheet workbook), admissions cycle return (§3.54). |
| Export | Branded Excel/print: Computed Post-UTME (CPU), Screened, CBT batches (CBT), candidates, attendance sheets; CSVs (non-index scores, awaiting scores); templates; JAMB template in JAMB's own layout. |
| Notifications | To the applicant only (§8): screening slip, CBT schedule published/changed/withdrawn/postponed/cancelled, scores released, decision released, reconsideration suggestion. `load_jamb_admissions` notifies nobody; no office is notified of anything. |
| Approval workflow | Settings DRAFT → IN_FORCE (minute, zero findings); CAPS held → committed / withdrawn; candidate PROPOSED → ADMITTED → ACCEPTED / DECLINED / WITHDRAWN (LAPSED never set); decision OFFERED / WAITING / NOT_OFFERED with basis NM / SM / ELG / LOCALITY / PLWD / OTHER; CBT exam DRAFT → CONFIGURING → OPEN_FOR_SCHEDULING → SCHEDULING_IN_PROGRESS → SCHEDULED → ONGOING → COMPLETED / CANCELLED; batch DRAFT → PUBLISHED → POSTPONED / CANCELLED. |
| Statuses | As above, plus attendance NOT_CHECKED_IN → CHECKED_IN → PRESENT / ABSENT / DISQUALIFIED; eligibility NOT_ELIGIBLE, PAYMENT_PENDING, DOCUMENT_PENDING, READY_FOR_SCHEDULING, SCHEDULED, RESCHEDULE_REQUIRED, EXAM_COMPLETED…; DE screening NO_RULE / UNVERIFIED / MET / SHORT. |
| Validation rules | Weights and criteria total 100; quotas total the NUC quota; UTME list needs settings in force and a load cut-off; commit refused while `reconcile` findings stand; a decision needs a released score and, for OFFERED, a basis and the compulsory credits; scores only for a seated, unreleased candidate; CBT publish needs zero validation errors; a move, unschedule, postpone or cancel carries a reason; check-in only at a published batch, once. |
| Security | O'Level score returned only to the Academic Office; CAPS load checks the acting office in code; `reset-intake` guarded only by browser confirms; `/api/v1/verify/putme/{token}` public and unthrottled. |
| Audit trail | Most `admissions.*` tables attached; `caps_row`, `olevel_*`, `rule_subject*`, `selection_criterion`, `suggestion_sent`, applicant account/event, blobs not; `putme_event` write-once. |
| Related modules | Applicant portal (§3.18); Finance (§3.36 — applicant fees); Student records (§3.23 — intake); Reports (§3.54). |
| Common errors | "No admission settings are in force"; "No general UTME cut-off is stated for loading…"; "Not a programme the University runs: C…"; "the admission list does not reconcile"; "an offer is made on a basis"; "the schedule cannot be published: …"; "already checked in at HH:MM". |
| Troubleshooting | Put settings in force; state the load cut-off; map the JAMB course name; fix the named reconcile findings; release scores before the merit list; publish the CBT batches; treat a second arrival as impersonation. |

**Status:** IMPLEMENTED — settings, CAPS, candidate data, screening (legacy and CBT), scores, merit (UTME only), decisions, JAMB list, intake, DE screening, migration, reconsideration suggest, public slip verification; PARTIALLY IMPLEMENTED — applicant document review and Registry clearance recording (endpoints without screens, so applicant stage 7 is unreachable from the UI), office fee confirmation, notify-all reconsiderations; CONFIGURED BUT UNUSED — `SUPERSEDED` settings, `LAPSED` candidates, `CAPS_API` source, CBT `keep_programme`/`registration_deadline`; NOT IMPLEMENTED — offer lapse and waiting-list promotion (UI text promises it).

### 3.18 Applicant portal (undergraduate)

| Point | Content |
|---|---|
| Purpose | A JAMB-admitted candidate registers with the JAMB number alone and is carried through ten computed stages: account → application fee → submitted form → screening slip → released score → released decision → accepted offer → cleared documents → fees paid and registered → matriculated. |
| Users / roles | Applicant only (`OFFICE_applicant`); public lookup, register, sign-in, forgot, reset. |
| Navigation | `/apply` (public), then My application → Overview `/applicant`, Application Form, Application Fee; Screening → Screening Slip, Screening Result; Admission → Admission Status, Accept Your Offer, Document Clearance, Matriculation. |
| Dashboard | Overview: passport card, tiles Application number / Programme applied for / UTME score / Stage n of 10, the ten-step rail, "Dates that matter", "Notices sent to you". |
| Main features | Lookup on every keystroke once the number is shaped; biodata read-only from CAPS; next of kin; declaration and submit; fee references (`MOAUM-APP-…`, `MOAUM-ACC-…`, 24 h) paid by card/USSD/PayDirect/bank; slip with QR once the batch is published; result with aggregate breakdown and merit position; status, undertaking, acceptance fee, decline; six-item clearance checklist (read-only); admission and matric number display; **Programme eligibility** (V266) on the Overview and Admission Status once submitted — the verdict with its reasons, View eligibility details, the programmes the applicant may be eligible for with Request Change, Recalculate. |
| Create | `POST /applicant/register`; `POST /me/fee-references`; `POST /me/submit`; `POST /me/accept`; `POST /me/decline`; `POST /me/eligibility/change` (a programme the engine listed only). |
| View | Every screen renders from one `GET /api/v1/applicant/me`. |
| Edit | Next of kin until submission; PASSPORT replaceable after submission (API only). |
| Delete / deactivate | Decline the offer (not reinstated). |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | Application form PDF, examination slip PDF (QR), admission letter PDF (after acceptance). |
| Notifications | Email + SMS at account creation, reset, fee confirmed (receipt), slip ready, CBT schedule changes, scores released, decision released, place held, clearance query, cleared; reconsideration email. Nothing on decline or submission. |
| Approval workflow | Stage 0–9 computed by `admissions.application_stage`. |
| Statuses | Candidate `offer_state` PROPOSED / ADMITTED / ACCEPTED / DECLINED / WITHDRAWN / LAPSED; clearance item NOT_PRESENTED / VERIFIED / QUERY; document PENDING / ACCEPTED / REJECTED. |
| Validation rules | JAMB number `^\d{12}[A-Z]{2,3}$`; email; phone 11 digits from 0; password ≥ 8; "the form opens when the application fee is confirmed"; "the next of kin is not given"; declaration ticked; acceptance needs both the undertaking and the fee; clearance opens after acceptance; 6/6 VERIFIED clears. |
| Security | Public endpoints without rate limit; 12-hour JWT; lockout 5/15 min; reset token hashed, one hour; documents served inline; the applicant never sees an unreleased score or decision nor the O'Level score. |
| Audit trail | `application`, `fee_reference`, `application_document`, `clearance_document` attached; `applicant_account`, `applicant_event`, `password_reset` not. |
| Related modules | Admissions (§3.17); Payments (§3.37); Sign-in (§3.2); Student records (§3.23). |
| Common errors | "Nobody can be verified yet…"; "That number is not on the list JAMB sent the University"; "An application account already exists for this number"; slip "not published yet"; letter 409 "Accept your offer first". |
| Troubleshooting | Load and commit the CAPS list; publish the CBT batches; complete the undertaking and the acceptance fee. |

**Status:** IMPLEMENTED; PARTIALLY IMPLEMENTED — document upload (API only, no control on any screen); NOT IMPLEMENTED (by design) — O'Level entry by the applicant; the Matriculation page's format text (`MOAUM/dept/YY/NNNN`) predates V263.

### 3.19 Postgraduate admissions and PG applicant portal

| Point | Content |
|---|---|
| Purpose | A postgraduate applicant applies directly (no JAMB): programme, account, `PG/YY/NNNNNN` and an application-fee reference in one call; after payment completes first degree, qualifications, referees (each emailed a private link), documents and passport; department → faculty → School decisions; checking fee releases the decision; acceptance fee accepts; admit writes the student row and account; the School's own calendar. |
| Users / roles | Public: programmes, apply, status, sign-in, referee; applicant token (`applicant`); `READERS` pgschool, pgsecretary, academic, registrar, dregistrar, dean, hod, dvc, vc, super; `DEPT` hod, academic, super; `FACULTY` dean, academic, super; `SPGS` pgschool, pgsecretary, super; `ADMIT` + registrar; `CONFIRMERS` pgsecretary, bursar, super; `FEES` bursar, pgsecretary, pgschool, super; calendar write pgschool, pgsecretary, super. HOD/Dean bound to their unit (`inBound`). |
| Navigation | `/pg/apply` (public), `/pg/portal`, `/pg/referee/{token}`; Admissions → Admissions / PG Admissions / Postgraduate Admissions → `/admissions/postgraduate` (pgschool, pgsecretary, hod, dean, academic); Academic → Calendar → `/admissions/postgraduate/calendar` (pgschool, pgsecretary); PG fees card on `/finance/fees`. |
| Dashboard | PG School home (applications, awaiting the School, offered, to admit, PG students, pipeline tiles); PG Secretary home (to register, fees to confirm, exams pending, clearances; ConfirmFee buttons); desk tiles Applications / Submitted / Dept recommended / Faculty recommended / Offered / Admitted. |
| Main features | Three-step apply wizard; status check by number + email with the decision mask; portal stepper (Academic record, Referees, Documents, Passport); PayByCard for three fee kinds; summary PDF and email; offer PDF after the acceptance fee; desk DetailPanel with per-stage buttons and merged documents PDF; calendar sessions and semester windows. |
| Create | `POST /pg/apply`; `/pg/first-degree`, `/qualifications`, `/referees`, `/documents`, `/passport`; `PUT /pg/calendar/sessions/{s}/{y}`. |
| View | Applications table with Excel; DetailPanel; History. |
| Edit | Referees re-saved (unsent rows re-created with new tokens); calendar. |
| Delete / deactivate | `DELETE /pg/documents/{id}`; declines are terminal. |
| Search | Programme combobox; status check. |
| Filters | Session. |
| Reports | Postgraduate return (§3.54). |
| Export | "Postgraduate applications" branded Excel (serial PGAPP); merged documents PDF; summary PDF; offer PDF. |
| Notifications | Email only: received, fee confirmed, School decided, decision ready, accepted, admitted, referee request, reference received, summary. Nothing to the HOD, Dean or School. |
| Approval workflow | SUBMITTED → DEPT_RECOMMENDED / DEPT_DECLINED → FAC_RECOMMENDED / FAC_DECLINED → OFFERED / NOT_OFFERED → ACCEPTED → ADMITTED. |
| Statuses | As above plus the `DECISION_LOCKED` mask; fee kinds APPLICATION / CHECKING / ACCEPTANCE; calendar PLANNED / CURRENT / CLOSED. |
| Validation rules | Programme POST GRADUATE; one application per email (`PG_APP_EXISTS`); password 6–100; fee gates (`PG_FEE_NOT_YET`, `PG_FEE_UNPAID`); documents PDF ≤ 8 MB, passport JPEG/PNG ≤ 4 MB; decision order enforced in SQL; a reference must belong to the application. |
| Security | HOD/Dean scope on the record; documents served sandboxed to the applicant; the offer-letter QR has no verifier; six-character passwords. |
| Audit trail | `pg_application` (+ trail trigger), `pg_referee`, `pg_prior_degree`, fees, calendar attached; `pg_applicant`, `pg_document` exempt. |
| Related modules | PG coursework (§3.20); Payments (§3.37); Fees (§3.36); Student records (§3.23). |
| Common errors | "An application already exists for this email."; "Pay the application fee before uploading your documents."; "Offer letter not available yet"; "This application is for another department's programme…"; decision buttons missing (wrong stage or session). |
| Troubleshooting | Sign in with the existing email; pay and "I've paid — check now"; confirm the ACCEPTANCE reference; choose the session explicitly (no PG session is CURRENT locally). |

**Status:** IMPLEMENTED; PARTIALLY IMPLEMENTED — offer-letter QR (no verify endpoint), PG calendar windows (informational; nothing enforces them); PLACEHOLDER — the `pg/home` route; NOT IMPLEMENTED — reopening a declined application, desk-side notices.

### 3.20 Postgraduate coursework

| Point | Content |
|---|---|
| Purpose | The School's own course catalogue per programme; a postgraduate registers per session and semester; HOD/School endorses; CA and examination marks graded on the PG scale (A 70+, B 60–69, C 50–59, F < 50); GPA/CGPA with deficiency courses excluded; the Secretary's read-only Registration, Examinations and Senate desks; the PG students register with status changes. |
| Users / roles | Student (POSTGRADUATE); `DESK` hod, academic, pgschool, pgsecretary, super (no department scope); Secretary desks `READERS` pgsecretary, pgschool, academic, registrar, dregistrar, super; register: admissions READERS; status change: SPGS. |
| Navigation | Academic → Courses `/admissions/postgraduate/courses`, Course Results `/results`, Registration `/registration`, Course Examinations `/examinations`, Results to Senate `/senate` (pgsecretary), Students → PG Students `/students`; pgstudent Academic → Course Registration & Results `/student/pg-courses`, Academic Progress `/student/pg-progress`. HOD and Academic Office have the API right but no menu entry. |
| Dashboard | Register tiles PG students / PGD / Master's / Doctoral / On probation; Secretary tiles. |
| Main features | Course upload template and import; Add a course; Endorse registration; per-course CA/Exam Save; student checkbox registration with mode Full-time/Part-time; progress checklist (advisory); Defer/Withdraw/Reinstate/Readmit with an instrument. |
| Create | `POST /pg/coursework/courses[/import]`; `POST /pg/coursework/register`; `POST /pg/coursework/score`; `POST /pg/students/{id}/status`. |
| View | All postgraduate courses; registrations (Student, Programme, Mode, Courses, GPA, Status); register (CGPA, Standing, Research stage). |
| Edit | Scores upsert per entry; registration replaced while unscored. |
| Delete / deactivate | None (courses have `active`; no UI toggles it). |
| Search | None. |
| Filters | Programme, Session, Semester; register Programme, Level, Gender, Entry session, Standing. |
| Reports | Postgraduate return. |
| Export | Course template only; no Excel of registrations, results, register or Senate list. |
| Notifications | None. |
| Approval workflow | Registration DRAFT / SUBMITTED / ENDORSED (endorse has no precondition). |
| Statuses | Mode FULL_TIME / PART_TIME; standing NEW / GOOD / PROBATION (< 2.50); student ACTIVE / DEFERRED / WITHDRAWN. |
| Validation rules | Units 0–12; kind CORE/ELECTIVE/DEFICIENCY/RESEARCH; semester 1–2; `ck_pg_score_total` 0–100 (CA + exam); deferment gate trigger; `PG_NOT_STUDENT`. |
| Security | A HOD may endorse and score any PG registration; `pg_research_event.by_person` left null. |
| Audit trail | `pg_course`, `pg_registration(_entry)`, `pg_score` attached. |
| Related modules | PG admissions (§3.19); PG research (§3.21); Deferments (§3.25); Documents (§3.51 — PG transcripts). |
| Common errors | "No courses listed for this semester yet"; "REGISTRATION UNAVAILABLE: your deferment…"; 23514 on `ck_pg_score_total`. |
| Troubleshooting | Upload the programme's catalogue; note the student screen offers semesters 1–2 only. |

**Status:** IMPLEMENTED; NOT IMPLEMENTED — exports, menu access for HOD/academic, PG registration-window enforcement; CA/exam weighting is text only.

### 3.21 Postgraduate research and awards

| Point | Content |
|---|---|
| Purpose | One research record per candidate through supervision, proposal, seminar, title with plagiarism figure, panel, draft, viva, corrections, final submission, the Secretary's clearance, the Board's recommendation and Senate's award (graduand row, GRADUATED); every document kept by kind and version; the School's roster of external examiners. |
| Users / roles | Student (own record, documents); `SCHOOL` pgschool, pgsecretary, super (pipeline, supervisors, panel, actions, review); roster read by admissions READERS, add by SPGS. |
| Navigation | Academic → Research Desk `/admissions/postgraduate/research` (pgschool), Research Seminars `?stage=PROPOSAL_APPROVED` (pgsecretary), Examination Panels / Panels & Viva `?stage=DRAFT_SUBMITTED`, Thesis Clearance `/clearance`, School Board `/board` (pgschool), External Examiners `/examiners`; pgstudent Research → Research & Thesis `/student/research`. |
| Dashboard | Pipeline tiles In the pipeline / Supervision / Proposal / Seminar & title / Examination / Awarded; Board tiles Awaiting the Board / With Senate / Awarded. |
| Main features | Stage select (16); detail with Supervisors (add), Panel (add), Advance buttons per stage, Withdraw candidate, document Accept/Return; Board Recommend and Record Award (Senate minute); clearance "Clear for binding"; roster "Appoint an examiner"; student Save topic / Submit proposal / Submit Document (PDF/.docx ≤ 25 MB). |
| Create | `POST /pg/research/{id}/supervisor|panel-member|action`; `/me/proposal`; `/me/documents`; `POST /pg/examiners`. |
| View | Pipeline table; milestones; documents table; roster. |
| Edit | Topic until proposal approval (`PG_TOPIC_LOCKED`). |
| Delete / deactivate | Withdraw (terminal). No supervisor end/replace, no panel member removal, no roster edit. |
| Search | None. |
| Filters | Stage. |
| Reports | Postgraduate return (researching, awarded). |
| Export | None. |
| Notifications | Email to the student on every stage change ("Your research: {stage words}"); nothing on endorsement, scores, document review, or to supervisors/panel. |
| Approval workflow | REGISTERED → SUPERVISED → PROPOSAL_SUBMITTED → PROPOSAL_APPROVED → SEMINAR_HELD → TITLE_REGISTERED → PANEL_CONSTITUTED → DRAFT_SUBMITTED → VIVA_HELD → (CORRECTIONS →) FINAL_SUBMITTED → CLEARED → AWARD_RECOMMENDED → AWARDED; WITHDRAWN. |
| Statuses | Document SUBMITTED / ACCEPTED / RETURNED; viva outcome PASS_CLEAN / PASS_MINOR / PASS_MAJOR / SECOND_ORAL / FAIL; degree kind PROJECT / DISSERTATION / THESIS. |
| Validation rules | `PG_STAGE_ORDER` "This record is at 'x'; y follows 'z'."; plagiarism figure required to register the title; viva needs score and outcome; award needs a Senate minute and a matriculated student; document stage gates (`PG_DRAFT_EARLY`, `PG_FINAL_EARLY`); PDF/.docx sniffed. |
| Security | Documents served sandboxed; SCHOOL sees all. |
| Audit trail | `pg_research` (+ trail trigger), supervisors, panel, events, documents attached; blobs exempt. |
| Related modules | Graduation (§3.29 — `records.graduand`); External examiners (§3.22 — project link); Documents (§3.51). |
| Common errors | "An award is recorded on a Senate minute." from the Research desk's own award button (it sends no minute — use the Board page); "an award is recorded for a matriculated student"; "The draft is submitted for examination once your title is registered." |
| Troubleshooting | Record the award on the School Board page; matriculate first. |

**Status:** IMPLEMENTED — lifecycle, documents, award; PARTIALLY IMPLEMENTED — supervisors/panel (add only), PG examiner roster (list and add only), extexam link; CONFIGURED BUT UNUSED — routes `t/pgsupervision`, `t/pgproposals`, `t/pgtheses`.

### 3.22 External examiners

| Point | Content |
|---|---|
| Purpose | Record an external examiner, invite by a one-use fourteen-day link, activate an account (office `extexaminer`), record appointments, register final-year projects (UG or PG), release documents, assign projects on a rubric by a deadline, receive scored assessments, lock or reopen, extend, reassign, withdraw; a morning job reminds and flags overdue reviews; eight reports. |
| Users / roles | `DESK` academic, dregistrar, registrar, exams, hod, dean, pgschool, pgsecretary, admin, super (department/faculty offices reach their own unit); `FORM` academic, dregistrar, pgschool, admin, super (rubrics); `EXAMINER` extexaminer (must be ACTIVE); public invitation/activate. |
| Navigation | Academic → External Examiners `/examiners`, Examiner Appointments `/examiners/appointments`, Project Assignments `/examiners/projects`, Assessments `/examiners/assignments`, Examiner Reports `/examiners/reports` (ten offices); `/examiners/rubrics` from buttons; examiner menu Dashboard `/examiner`, My Projects, Pending Reviews, Submitted Reviews, My Profile; `/login/activate`. |
| Dashboard | Tiles Examiners / Assigned projects / Pending reviews / Submitted; Overdue reviews panel; examiner workspace tiles Assigned / Pending / Submitted / Overdue. |
| Main features | New External Examiner (18 fields, "Send the invitation email now"); Send/Resend Invitation; Suspend/Deactivate/Set Active; Edit; Record an Appointment; Keep File (CV/photo); Register a Project (candidate type-ahead over finalists and postgraduates); documents Release/Withhold and upload; Assign (examiner, form, deadline); Extend, Reassign, Withdraw; Approve and Lock, Reopen; rubric forms and criteria; examiner Save Draft / Submit Assessment; My Profile. |
| Create | `POST /examiners`, `/{id}/appointments`, `/projects`, `/assignments`, `/rubrics`, `/rubrics/{id}/criteria`. |
| View | Register; record with tabs Projects / Appointments / History; projects; assessments; assessment detail; reports. |
| Edit | Record; profile; criteria; deadline. |
| Delete / deactivate | Status SUSPENDED / INACTIVE (ends the office grant); End an appointment; Withdraw an assignment; Set a rubric inactive; criteria deactivated, never deleted. |
| Search | Register search; projects search; assignments search; candidate and supervisor type-aheads. |
| Filters | Session; status; examiner; "Overdue only"; report filters (Session, Faculty, Department, Programme, Examiner, Status, dates). |
| Reports | Eight kinds (External Examiner, Project Assessment, Examiner Workload, Department Assessment, Programme Assessment, Pending Review, Overdue Review, Submitted Assessment). |
| Export | CSV downloads (not branded Excel); no PDF. |
| Notifications | Email: invitation, activation (to the inviter and academic), appointment, assigned/reassigned/withdrawn, deadline changed, reminder (≤ 3 days), overdue (examiner and desk), submitted/resubmitted (desk and examiner), reopened, locked. No SMS. |
| Approval workflow | Assignment ASSIGNED → IN_REVIEW → SUBMITTED → LOCKED; REOPENED (version + 1); REASSIGNED / WITHDRAWN. |
| Statuses | Examiner INVITED / PENDING_ACTIVATION / ACTIVE / SUSPENDED / INACTIVE; appointment ACTIVE / ENDED (SUSPENDED never set); assessment DRAFT / SUBMITTED / LOCKED / REOPENED; recommendation PASS / PASS_WITH_CORRECTIONS / REASSESSMENT / FAIL. |
| Validation rules | `EXAMINER_EXISTS`; invitation 14 days, one use; password ≥ 10 not containing the email; files sniffed (CV/photo ≤ 5 MB; project docs ≤ 25 MB); one project per (student, session); assign needs an ACTIVE examiner, deadline ≥ today, an active rubric; submit needs every criterion scored, none over maximum, a recommendation and general comments ≥ 20 characters; reopen and status changes need a reason ≥ 5. |
| Security | Token-hash activation; examiner reaches only own live assignments and released documents; suspension ends the grant; grade from `policy.grade_of` (the UG scheme) even on PG rubrics. |
| Audit trail | `extexam.*` attached; `extexam.event` write-once; `invitation` and blobs exempt. |
| Related modules | Sign-in (§3.2); PG research (§3.21); Results (§3.30 — moderation feed reads `assessment.score`). |
| Common errors | "Your examiner appointment is not active."; "This invitation link has expired or was already used."; "This project is with that examiner already."; examiner sees "No documents released yet". |
| Troubleshooting | Resend the invitation; release the report on the project page; reminders need the mail dispatcher. |

**Status:** IMPLEMENTED (end-to-end test `ExaminersIT`); PARTIALLY IMPLEMENTED — moderation feed (no UI), PG roster link, PG research ↔ project result flow; NOT IMPLEMENTED — appointment letter and assessment PDF.

### 3.23 Student records, Student 360 and Records & Queries

| Point | Content |
|---|---|
| Purpose | The register of every admitted student (`people.student`), assembled live into a Student 360 record; the Registry's few writes (intake, status on an instrument, level correction, biodata, portal account, voluntary withdrawals, migrated clearance); the Records & Queries workbench over students, registration, results, examinations, allocation and clearance. |
| Users / roles | `READERS` academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, ict, admin, super, bursar, library, security, housing, hrm, audit, lecturer; `WRITERS` academic, registrar, dregistrar; migrated clearance and withdrawals + ict, super; portal account registrar, dregistrar, academic, records, ict, super. |
| Navigation | Students → Students / Student Records → `/students` (academic, admin, dean, dregistrar, facultyofficer, hod, ict, registrar); Records & Queries → `/records` (eighteen offices); Student 360 `/students/{id}` from any list. |
| Dashboard | Migrated tiles On the register / Cleared everywhere / Not yet cleared; Voluntary withdrawals Due now / Closed so far. |
| Main features | Scope bar and "Find a student"; Student 360 with Change status (instrument required), Correct level, Portal account (first password), Finance card (placeholder), Academic standing, eight clearance units, Registration, Record history, Biodata sections with per-field "From JAMB"/"Needs approval" badges; "Clear the N not yet cleared"; "Close all N due" voluntary withdrawals; Records tabs students / registration / fees / results / exams / allocation / clearance / attendance. |
| Create | Intake `POST /student/intake/{s}/{y}` (button on `/admissions`). |
| View | Register table (Matriculation no., Name, Programme, Level, Status); Student 360; records views. |
| Edit | `PUT …/biodata/{field}` (open fields; locked refused); status; level. |
| Delete / deactivate | Status change to WITHDRAWN, EXPELLED, TRANSFERRED_OUT, DECEASED, VOLUNTARY_WITHDRAWAL etc. — never a delete. |
| Search | Matriculation number, admission number or name (LIMIT 2000). |
| Filters | Faculty, department, programme, level, session; records course and semester. |
| Reports | Student register (§3.54). |
| Export | None on `/students` or `/records` (DTable only). |
| Notifications | None — status changes, biodata decisions and withdrawals send nothing. |
| Approval workflow | Biodata change PENDING → EVIDENCE_ASKED → APPROVED / REFUSED (see §3.27 — no producer). |
| Statuses | ADMITTED, ACTIVE, PROBATION, DEFERRED, SUSPENDED, RUSTICATED, WITHDRAWN, EXPELLED, TRANSFERRED_OUT, GRADUATED, DECEASED, DORMANT, VOLUNTARY_WITHDRAWAL. |
| Validation rules | Any status but ADMITTED needs a matric number; matric and admission numbers immutable ("the matriculation number % is permanent and is not changed"); instrument required; level in hundreds up to the final year with a reason; phone `^0[0-9]{10}$`. |
| Security | `/student/records/{view}` builds its scope from request parameters only (a HOD can read another department's rows by editing the URL); `/students/{id}` readable by every reader for any student. |
| Audit trail | `people.student`, `student_contact`, `biodata`, `biodata_change`, `status_change`, `enrolment`, `document`, `search_log` attached. |
| Related modules | Admissions (§3.17 — intake); Matriculation (§3.24); Sign-in (§3.2); Clearance (§3.28); Finance (§3.37). |
| Common errors | "a change of status is made on an instrument … and none was cited"; ADMITTED→ACTIVE by hand fails `ck_student_active_has_matric`; "No portal account has been opened for this number yet." |
| Troubleshooting | Matriculate instead of setting ACTIVE; open the portal account from Student 360 (needs a matric number). |

**Status:** IMPLEMENTED — register, 360, status, level, biodata write, voluntary withdrawals, migrated clearance, portal account; PLACEHOLDER — the 360 Finance card ("NOT YET SERVED") and CGPA "—", the records "fees" and "attendance" tabs (stale not-served text); NOT IMPLEMENTED — a search-log reader.

### 3.24 Matriculation and the matriculation number format

| Point | Content |
|---|---|
| Purpose | Turn ADMITTED students into ACTIVE ones by issuing the permanent matriculation number: generated faculty lists confirmed by Faculty Officers, one run per session in one transaction, single issue for stragglers, and since V263 a configured rule `MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}` with named series whose counters only move forward and a write-once history. |
| Users / roles | `READERS` academic, registrar, dregistrar, dvc, vc, records, dean, hod, facultyofficer, ict, admin, super; `OFFICERS` (query, withdraw, confirm) academic, registrar, dregistrar, facultyofficer; `RUNNERS` academic, registrar, dregistrar; `CONFIG` academic, registrar, dregistrar, super. |
| Navigation | Students → Matriculation → `/matriculation` (academic, dregistrar, registrar); Registered Students → `/matriculation` (facultyofficer); Matriculation Number Format → `/matriculation/config` (academic, dregistrar, registrar); `/matriculation/faculty/{code}` from Open. |
| Dashboard | Tiles Registered students / Confirmed by Faculty Officers / Faculties outstanding / Numbers issued; config tiles Series / Programmes with a code / Carrying none / Numbers issued on record. |
| Main features | Faculty lists table with Open; Query (reason + who clears it) / Withdraw query; "Confirm N students to the Academic Office"; "Issue number" per student; "Run matriculation for N students"; format rule (University code, separator, padding, components); series with "Last number issued — moves forward only"; faculty segment and series; per-programme code, own segment, series and next number; recent issues. |
| Create | `POST /matriculation/sessions/{s}/{y}/run`; `POST …/students/{id}/matriculate`; `PUT /matriculation/config/format|series/{code}|faculties/{code}|programmes/{code}`. |
| View | Faculty list (Admission number, Name, Department, Units, Fees "—", State); numbers issued most recently (25). |
| Edit | Configuration only; a number is never edited. |
| Delete / deactivate | Series can be set inactive. |
| Search | Programme search on the config screen. |
| Filters | Faculty filter; `?session=` (defaults to a hard-coded 2026/2027). |
| Reports | Matriculation Number Configuration. |
| Export | Config branded Excel/PDF (serial MAT, S/N first); faculty list CSV (not branded). |
| Notifications | "Your matriculation number" (email + SMS) on issue; nothing on query, confirm or configuration. |
| Approval workflow | Faculty list DRAFT → CONFIRMED; the run needs every faculty with rows confirmed. |
| Statuses | List state; student ADMITTED → ACTIVE with a status_change citing the run ref `MAT/YYYY/NNN`. |
| Validation rules | Run refuses an unconfirmed faculty; a student is issued only when ADMITTED, registered (APPROVED/LOCKED for the entry session) and `finance.position.paid_in_full`; number built from the format row (empty segments removed); "the sequence is spent, never reused" — a number on the register or in the history is passed over; series `last_issued` cannot go back; a programme set to carry a code must have one; University code `^[A-Z]{2,6}$`; codes `[A-Z0-9]{2,6}`; series `[A-Z][A-Z0-9_]{1,20}`; padding 0–8; separator "/" or "-". |
| Security | No faculty scope in code (a Faculty Officer can confirm any faculty's list by URL); history immutable by trigger. |
| Audit trail | `people.faculty_list`, `faculty_list_query`, `matriculation_run`, `matric_format`, `matric_series`, `matric_history` (write-once) attached. |
| Related modules | Registration (§3.13); Finance (§3.36); Student records (§3.23); Reference data (§3.10). |
| Common errors | "the run cannot start: Faculty of X has not confirmed its list"; "the matriculation number cannot be built: Programme … is configured to carry a code but has none" (the whole run rolls back); "the school fees for … are not settled"; "Series X has issued up to N; it does not go back." |
| Troubleshooting | Confirm every list; give the programme a code or set it to carry none on the format screen; the list's Fees column does not show who is unpaid — the run checks `finance.position`. |

**Status:** IMPLEMENTED — lists, run, single issue, V263 rule, series, history (seeded series: Administration 13556, College 6093, Pharmacy 198, Architecture 76, General 85631 in `db/V263`); PARTIALLY IMPLEMENTED — preview and history-search endpoints without UI; PLACEHOLDER — the faculty list's Fees column; the run screen's "What the run does" text still describes per-department sequences.

### 3.25 Deferments

> **Revised by V264 (26 September 2026):** the application fee (₦10,000, Bursary-stated) is paid through the existing payment reference before the form opens; the chain is now **Bursary → Head of Department → Faculty → Academic Office (forwards in batches DEF-DVC-YYYY-NNNNN; downloads only faculty-approved applications) → DVC (comment required; **final approval**, V265)**; the final approval marks the period's courses DEFERRED (never failed), leaves the CGPA untouched and extends the expected completion by the period deferred; deferred courses become due on the registration form on the return; supporting documents open in a modal viewer; the desk is searched on the server; new screens `/deferments/batches` and the filtered `/deferments/returns`; the Bursar and the DVC now hold the Deferments menu item. The entry below describes the V259 baseline where it differs; see *06 Workflows* §7.1 and *09 Feature Status* §3.21 for the current rules.

| Point | Content |
|---|---|
| Purpose | A matriculated student defers a semester or a session; the request passes department, faculty and Registry, or is returned, rejected or cancelled; a daily clock brings an approved period into force (status DEFERRED, registration refused by trigger), reminds before the return and the desk confirms the return; an approval letter PDF. |
| Users / roles | Student (own); `DESK` hod, dean, facultyofficer, academic, registrar, dregistrar, records, pgschool, pgsecretary, provost, collegesecretary, super, admin, bound by unit (department, faculty, PG, College, University); stage rules (`may`): hod at SUBMITTED, dean/facultyofficer at DEPT_RECOMMENDED, Registry (academic, registrar, dregistrar, super) approve at either recommended state; cancel Registry only; tick registrar, dregistrar, academic, ict, super. |
| Navigation | Academic → Deferment → `/student/deferment` (student, pgstudent); Students → Deferments → `/deferments` (twelve offices); `/deferments/{id}`, `/deferments/returns` from the desk. |
| Dashboard | Desk tiles Total / Pending / Under review / Approved / Rejected / Active deferments / Returning / Overdue returns; "Waiting at this desk". |
| Main features | Three-step student wizard (request, documents, review with declaration), Withdraw Request; desk list with filters and breakdowns; Review with "This desk's act" buttons (Recommend to the Faculty / Recommend to the Registry / Approve Deferment / Request Correction / Reject / Cancel Request / Confirm Return); Students Due to Return; Approval Letter. |
| Create | `POST /me/deferments`, `PUT /me/deferments/{id}`, `POST …/documents`, `POST …/submit`. |
| View | Deferment history; request, documents, student's record (status, standing, fees, registrations, previous deferments), desks, history. |
| Edit | While DRAFT or CORRECTION_REQUIRED. |
| Delete / deactivate | Cancel (Registry) / Withdraw (student, from an in-review state). |
| Search | Desk search. |
| Filters | Session, Semester, Type, Status, Faculty/Department/Programme (per bound); returns All/Due/Overdue/Upcoming. |
| Reports | Desk list. |
| Export | Branded Excel/PDF (serial DEF, S/N first: Deferment Number, Student ID, Student Name, Faculty, Department, Programme, Type, Session, Semester, Status, Request Date, Approval Date, Expected Return). |
| Notifications | Email + SMS to the student at every turn and email to the department/faculty/Registry desks (§8). |
| Approval workflow | DRAFT → SUBMITTED → DEPT_RECOMMENDED → FAC_RECOMMENDED → APPROVED → ACTIVE → COMPLETED; CORRECTION_REQUIRED, REJECTED, CANCELLED. |
| Statuses | Return status UPCOMING / DUE / OVERDUE / RETURNED; reference `DEF-YYYY-NNNNN`. |
| Validation rules | Eligibility (matriculated, not graduated/withdrawn/suspended, one live request, ≤ `max_sessions` 2); explanation ≥ 20 characters when required; a document for MEDICAL/MATERNITY/EMPLOYMENT; declaration; documents PDF/JPEG/PNG ≤ 5 MB, at most six; reject and correction carry a note; a deferment in force is not cancelled. |
| Security | Bound enforced on every desk read and act; documents sniffed and served sandboxed; the letter's QR points to `/verify/deferment/{reference}`, which does not exist. |
| Audit trail | `people.deferment`, `deferment_document`, `deferment_event` (write-once), reasons, setting attached. |
| Related modules | Registration (§3.13 — gate); PG coursework (§3.20 — gate); College (§3.35 — gate); Student records (§3.23 — status). |
| Common errors | "Deferment is asked for once you are matriculated…"; "You already have a deferment request…"; "This request is submitted; approve is not this desk's act at that stage."; "This deferment is outside your office's bound". |
| Troubleshooting | The department recommends first; set the HOD/Dean grant scope; run `POST /deferments/tick` when the clock has not fired. |

**Status:** IMPLEMENTED (clock 06:20 Africa/Lagos); NOT IMPLEMENTED — public verification of the letter, settings/reasons screen; CONFIGURED BUT UNUSED — document `verified_at/by`.

### 3.26 Inter-departmental transfers

| Point | Content |
|---|---|
| Purpose | A matriculated active student applies to move to another programme; pays the Bursary-set fee; current-department HOD, new-department HOD, Registrar and Academic Office approve in turn; the change of programme is effected on the register; the matriculation number never changes. An older committee/Senate path is still exposed by the API. |
| Users / roles | Student; `READERS` hod, academic, registrar, dregistrar, dvc, vc, ict, admin, super; `APPROVERS` hod, registrar, dregistrar, academic, super stage-checked; `OFFICERS` (paper application) academic, registrar, dregistrar, super; committee/Senate/withdraw/effect endpoints have no screen. |
| Navigation | Academic → Inter-Departmental Transfer → `/student/transfer`; Students → Inter-Departmental Transfer → `/transfers` (academic, hod, registrar); `/transfers/memo?type=`, `/student/transfer/letter/{id}`. |
| Dashboard | Student tiles Your department / Processing fee / Applications; office tiles for the four desks. |
| Main features | Apply (programme, reason, UTME score); "Pay the fee online"; seven-stage tracker; office tabs Current dept / New dept / Registrar / Academic / Completed / Declined / All with Approve / Decline; Record an application; memo document; approval letter. |
| Create | `POST /me/transfer`; `POST /me/transfer/{id}/fee`; `POST /transfers`. |
| View | Table Student / From → To / Entry · UTME · CGPA / Reason / Stage. |
| Edit | None. |
| Delete / deactivate | Decline with a reason. |
| Search | Searchable programme list. |
| Filters | Stage tabs. |
| Reports | Memo (recommended / withdrawn lists) for the DVC/SAIC. |
| Export | Print only. |
| Notifications | None. |
| Approval workflow | APPLIED → FROM_OK → TO_OK → REG_OK → EFFECTED; DECLINED; committee path RECOMMENDED / NOT_RECOMMENDED / APPROVED / WITHDRAWN. |
| Statuses | As above. |
| Validation rules | Matriculated and ACTIVE/PROBATION; reason non-blank; target ≠ own, not archived; one live application; the fee must be set ("the inter-departmental transfer fee has not been set by the Bursary") and confirmed before the first approval and before effecting. |
| Security | The office list is University-wide for every reader; buttons are stage-scoped and the server re-checks. |
| Audit trail | `people.transfer_application` attached. |
| Related modules | Finance (§3.36 — `fee_setting.transfer_fee`); Student records (§3.23). |
| Common errors | "Transfers are not open yet"; "This application is not ready at your desk. Awaiting payment."; "a transfer application is already in progress for this student". |
| Troubleshooting | Set the transfer fee on Finance → Fees; the student's menu shows the old structure until the next registration opens for the new programme. |

**Status:** IMPLEMENTED — application, fee, four-desk pipeline, decline, paper application; PARTIALLY IMPLEMENTED — committee/Senate/withdraw/effect (API only), the approval letter (hard-coded ₦10,000 and Senate/SAIC wording); NOT IMPLEMENTED — notifications.

### 3.27 Biodata changes

| Point | Content |
|---|---|
| Purpose | A queue where the Registry approves, refuses or asks for evidence on a student's requested change to an approval-tier biodata field. |
| Users / roles | Readers as §3.23; deciders academic, registrar, dregistrar. |
| Navigation | Students → Biodata Changes → `/students/biodata-changes` (academic with badge, registrar). |
| Dashboard | Tiles Awaiting evidence / Approved / Refused / Self-service changes. |
| Main features | Approve with evidence; Refuse (decision text required); Ask for evidence. |
| Create | None from any screen — `ref.biodata_field` holds only `open` and `locked` tiers; `askForChange` is never called. |
| View | Table Student / Field / From / To / Evidence / Action. |
| Edit | Decide once (`STU_CHANGE_DECIDED`). |
| Delete / deactivate | None. |
| Search | None. |
| Filters | `?state=`. |
| Reports | None. |
| Export | None. |
| Notifications | None (the screen text "the student is notified" is not implemented). |
| Approval workflow | PENDING → EVIDENCE_ASKED → APPROVED / REFUSED. |
| Statuses | As above. |
| Validation rules | Blank decision refused. |
| Security | Deciders only; readers see the queue. |
| Audit trail | `people.biodata_change` attached. |
| Related modules | Student records (§3.23); Student portal biodata. |
| Common errors | An always-empty queue. |
| Troubleshooting | None possible until a field carries the `approval` tier. |

**Status:** CONFIGURED BUT UNUSED — the screen and endpoints work but nothing can create a request.

### 3.28 Clearance

| Point | Content |
|---|---|
| Purpose | Independent sign-offs per purpose by eight units (BURSARY, DEPARTMENT, FACULTY, LIBRARY, HEALTH, HOSTEL, WORKS, ALUMNI): CLEARED or HELD naming the item; the latest position per unit; a student is clear when no unit's position is other than CLEARED. |
| Users / roles | Readers academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, bursar, library, services, ict, admin, super (scope bound); `SIGNERS` academic, registrar, dregistrar (any unit), dean, hod, bursar, library, services, housing (own unit; housing also HOSTEL). |
| Navigation | Students → Clearance / Financial Clearance / Faculty Clearance / Department Clearance / Library Clearance / Student Clearance → `/clearance` (academic, admin, bursar, dean, dregistrar, hod, library, registrar, services). |
| Dashboard | Tiles Candidates for clearance / Fully cleared / Outstanding at one unit / Outstanding at two or more; "Where candidates are held". |
| Main features | Candidates table with one ✓/✗ column per unit; candidate panel with Clear / Hold ("What is outstanding"); "Clear the selected candidates"; "Export the held list"; "Notify held candidates" (stub). |
| Create | `POST /clearance/students/{id}/{unit}/clear|hold`. |
| View | Positions per purpose. |
| Edit | Rows are appended; `superseded_by` exists but nothing sets it. |
| Delete / deactivate | None. |
| Search | None. |
| Filters | Scope bar; `?purpose=` (CONVOCATION by default; EXAMINATION, HOSTEL, ID_CARD, LIBRARY, REGISTRATION, RESULTS, TRANSCRIPT by URL only). |
| Reports | None. |
| Export | Held list CSV. |
| Notifications | None — "Notify held candidates" returns 202 "The notification module is not on the portal yet; nothing was sent." |
| Approval workflow | None (independent sign-offs). |
| Statuses | Item HELD / CLEARED. |
| Validation rules | A hold names its item; "the X clears against its own record; Y does not sign for it". |
| Security | Unit/office scoping on signing; positions of any student readable by every reader. |
| Audit trail | `clearance.unit`, `clearance.item` attached; migrated clearances carry no officer. |
| Related modules | Documents (§3.51 — CONVOCATION and TRANSCRIPT gates); Hostel (§3.47 — writes the HOSTEL item); Graduation (§3.29); Registration class list (§3.13 — EXAMINATION flag). |
| Common errors | "A hold names the specific item outstanding."; migrated students show CLEARED everywhere with no officer. |
| Troubleshooting | Sign as the unit's office or as the Registry. |

**Status:** IMPLEMENTED — clear/hold/positions; PLACEHOLDER — Notify held candidates; PARTIALLY IMPLEMENTED — purposes other than CONVOCATION (URL only); NOT IMPLEMENTED — automatic clearance from library/bursary standing.

### 3.29 Graduation and alumni

| Point | Content |
|---|---|
| Purpose | The degree audit over finalists (CGPA over published results, first unpublished course), the graduand row with any unmet requirement, Senate approval on a minute (GRADUATED, notice), the classification summary and the alumni register. |
| Users / roles | View academic, registrar, dregistrar, dvc, vc, records, dean, hod, ict, admin, super (scope bound); audit academic, registrar, dregistrar, records; approve registrar, dregistrar, academic; alumni readers registrar, dregistrar, academic, records, vc, dvc, audit, deputyaudit, admin, super. |
| Navigation | Academic → Graduation / Graduation List / Graduation Records → `/graduation` (academic, dean, dvc, pgschool, pgsecretary, records, vc); Services → Alumni Register → `/alumni` (services — refused); pgstudent Graduation → `/student/graduation`; UG dashboard tile. |
| Dashboard | Tiles Finalists / Audit passed / Outstanding requirement / Awaiting clearance; alumni tiles On the register / Graduating sessions / Latest cohort / Showing. |
| Main features | "Run the degree audit for S"; exceptions table; classification summary by band; "Send the list to Senate" with a minute; alumni search and filters; student graduation steps, award panel and the eight-unit convocation clearance table. |
| Create | `POST /graduation/sessions/{s}/{y}/audit`, `/approve`. |
| View | Exceptions (Student, Programme, Unmet requirement, CGPA); alumni (Name, Matric number, Programme (award), Faculty, Class, Session). |
| Edit | None. |
| Delete / deactivate | None. |
| Search | Alumni search (client-side). |
| Filters | Session scope; alumni faculty and session. |
| Reports | None (DTable only). |
| Export | None. |
| Notifications | "Senate has approved your award" (email + SMS) to each graduand. |
| Approval workflow | `records.graduand.senate_state` AWAITING → APPROVED (REFERRED never set). |
| Statuses | As above; student → GRADUATED. |
| Validation rules | Minute required; APPROVED needs no unmet and a CGPA; final level hard-coded (600 MBBS, 500 LL.B/Pharmacy, else 400); unmet = "{course} not graded" / "No published result on the record" / "CGPA x — below pass threshold" (< 1.00). |
| Security | Scope bound on view; approval by three offices. |
| Audit trail | `records.graduand` attached; `trg_graduand_flags_documents` flags issued documents on change. |
| Related modules | Results (§3.30); Clearance (§3.28); Documents (§3.51 — certificates); PG research (§3.21 — `pg_award` writes graduands). |
| Common errors | "No degree audit has been run for S"; "the graduation list is approved on a Senate minute, and none was cited"; a finalist missing (no `people.enrolment` row at the final level). |
| Troubleshooting | Run roll-over/enrol-all on the calendar so enrolments exist. |

**Status:** PARTIALLY IMPLEMENTED — the audit checks only "every registered course published" and CGPA ≥ 1.00 (the screen claims core, credit-minimum, GST and project rules); IMPLEMENTED — Senate approval, classification, alumni register, student view; CONFIGURED BUT UNUSED — REFERRED; menu/guard mismatch for Support Services.

### 3.30 Results and score sheets

| Point | Content |
|---|---|
| Purpose | Examination sessions (MAIN, RESIT, SPECIAL) whose opening generates one score sheet per allocated offering; CA and examination marks entered or uploaded, submitted and attested; the nine-stage approval chain to PUBLISHED on a Senate minute; total, grade and points computed from the grading scheme with a one-mark grace; marks versioned; the computed broadsheet; the Senate schedule and publication. |
| Users / roles | `READERS` academic, registrar, dregistrar, dvc, vc, records, dean, hod, exams, facultyexams, facultyofficer, lecturer, ict, admin, super; `DESKS` lecturer, exams, hod, facultyexams, facultyofficer, dean, records, registrar, dregistrar, academic; `ENTRY` lecturer, exams, academic; `EXAMS` (sessions) records, academic, registrar, dregistrar; minute registrar, dregistrar. Stage→office map (`Sheets.DESK`) drives the UI only. |
| Navigation | Academic → Examination Sessions / CBT Sessions / Examinations → `/examinations/sessions`; Score Sheets / Score Entry / Upload Results (bulk) / My Score Sheets → `/results/sheets`; Score Sheet History → `/results/sheets/history`; Result Desk / Scrutiny Desk / Validation Desk → `/results/desk`; Departmental Approvals / Faculty Board / Verification Queue / Results to Senate / Senate Business → `/results/approvals`; Approval Chain → `/results/chain`; Result Pipeline → `/results/pipeline`; Broadsheet(s) → `/results/broadsheet`; Senate Schedule → `/results/senate`; Publication → `/results/publish`. |
| Dashboard | Exam-sessions tiles Open sessions / Courses examined / Candidates / Sheets due; submission monitor; desk tiles On this desk now / Not yet arrived / Sent on / Published; pipeline counts per stage; broadsheet tiles Candidates / Mean GPA / Passed every course / Carrying over. |
| Main features | Create/open/edit an examination session; sheet list with stage pills; score entry with template download, upload with whole-file validation, Save the draft, Submit and attest; held scripts panel (§3.31); Desk with "Forward N sets to {next}"; Approvals queue with Approve / Return / Remind; Chain ladder with per-stage act and the minute modal; Pipeline; Broadsheet with Senate lists and remarks; Senate schedule "Record the minute and release"; Publication "Release to candidates on the minute". |
| Create | `POST /results/exam-sessions` (+ open); `PUT /results/sheets/{id}/scores`; `POST /sheets/{id}/advance`; `POST /results/senate/minute`. |
| View | Roll table (S/N, Matriculation number, Name, Programme, Lv, CA, Exam, Total, Grade, Points, Outcome); "Marks on this sheet"; ladder of decisions. |
| Edit | A saved mark is locked until the sheet is returned; an amended row needs a reason; exam-session dates editable, keys fixed once sheets exist. |
| Delete / deactivate | None; CLOSED exam session never set. |
| Search | PickSheet list; DTable search. |
| Filters | Session, Semester, Standing (history); scope bar with course (approvals); programme/level/session/semester (broadsheet); faculty (senate). |
| Reports | Submission monitor; broadsheet ("Examination reporting sheet"); Senate schedule by faculty. |
| Export | Score-sheet template (xlsx/csv), marked sheet (xlsx/pdf, landscape, no QR), validation report CSV, broadsheet Excel (serial BRD) and print PDF. |
| Notifications | None on publication; Remind/escalate returns 202 "The notification module is not on the portal yet; nothing was sent."; `trg_score_flags_documents` flags issued documents when a score changes. |
| Approval workflow | ENTRY → VERIFICATION (exams) → DEPT_BOARD (hod) → FACULTY_SCRUTINY (facultyexams) → FACULTY_COMPILATION (facultyofficer) → FACULTY_BOARD (dean) → RECORDS (records) → SENATE (registrar/dregistrar, minute) → PUBLISHED; RETURN to ENTRY with a comment from any stage but ENTRY/PUBLISHED. |
| Statuses | Sheet stage as above; exam session DRAFT / OPEN (CLOSED unused); score outcome GRADED / ABSENT / WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED. |
| Validation rules | Every candidate needs a mark or an outcome before submit; BR-006 "you approved the previous stage of this sheet; another desk must approve this one"; a minute to publish; marks within the course split (`ca_max`, default 40); `RES_MARK_ON_RECORD`; `RES_AMENDMENT_SAYS_WHY`; exam dates in order; one session per (session, semester, kind); grace 39 → 40. |
| Security | The office-per-stage rule is not enforced in SQL (any DESKS office can advance any stage through the API); a DESKS office can publish a single sheet by passing the minute at SENATE; lecturer ownership checked on every read/write. |
| Audit trail | `assessment.exam_session`, `score_sheet`, `score` (append-only versions), `decision` (write-once), `exam_timetable` attached. |
| Related modules | Allocation (§3.12); Registration (§3.13 — rolls); Grading policy (§3.30 note); Held scripts (§3.31); Result queries (§3.32); Student results/exam cards (§3.33); Documents (§3.51). |
| Common errors | "N registered candidate(s) on this sheet have no mark and no outcome"; "A saved mark is on the record; the lecturer does not change it on their own"; "a result reaches a student on the Senate minute that approved it, and none was cited"; "{code} is not allocated to you in {session}"; upload "was not accepted — N lines refused, nothing written". |
| Troubleshooting | Give every roll row an outcome; ask for a Return to amend; another holder of the office records the minute; allocate the offering so the sheet is generated. |

Grading policy note: `policy.grade_band` A 70–100 (5), B 60–69 (4), C 50–59 (3), D 45–49 (2), E 40–44 (1), F 0–39 (0) under `SEN/2015/44`; classification First 4.50–5.00, 2:1 3.50–4.49, 2:2 2.40–3.49, Third 1.50–2.39, Pass 1.00–1.49 (no band under 1.00, so the class is "—"); GPA/CGPA by `assessment.student_gpa`; probation/advised-to-withdraw by `assessment.standing_of`. No screen edits these tables; grades are computed under the scheme in force at `current_date`.

**Status:** IMPLEMENTED — sessions, entry, upload, chain, broadsheet, Senate release, re-sits; PLACEHOLDER — Remind/escalate, the Chain screen's "Raise an amendment" and "View as a student" buttons (no handler), "withheld set" text on the Senate screen; PARTIALLY IMPLEMENTED — second examiner acting at VERIFICATION (the stage belongs to the `exams` office; the second examiner only gains read access); NOT IMPLEMENTED — publication notices, printing the Senate schedule, an amendment path for a PUBLISHED sheet.

### 3.31 Held scripts

| Point | Content |
|---|---|
| Purpose | A mark from a candidate who sat without being on the roll is held against the sheet by matriculation number; released into the sheet as a new score version when the registration is approved; lapses at the semester's late-registration date; the Bursary reads who is waiting and what they owe. |
| Users / roles | Hold/withdraw `ENTRY` lecturer, exams, academic (no ownership check); read: results readers + bursar; owing list bursar, academic, registrar, dregistrar, exams, hod, dean, records, vc, dvc, admin, super. |
| Navigation | The "Scripts from candidates not on the roll" panel on `/results/sheets/{id}`; Finance → Held Scripts → `/finance/held-scripts` (bursar). |
| Dashboard | Bursary tiles Students / Scripts held / Still owing / Closing within 14 days. |
| Main features | Hold the script (number, outcome, CA, Exam, note); template and bulk upload (all-or-nothing); Withdraw; Bursary list with Closes, Due, Paid, Balance. |
| Create | `POST /results/sheets/{id}/held`, `/held/bulk`. |
| View | Held table (Standing pills Held / Released / Lapsed / Withdrawn). |
| Edit | None. |
| Delete / deactivate | Withdraw a still-held script. |
| Search | None. |
| Filters | None. |
| Reports | The owing list. |
| Export | Held-scripts template (xlsx); the Bursary list has no export. |
| Notifications | "Your {code} script is held until you register" (email + SMS). |
| Approval workflow | None. |
| Statuses | HELD → RELEASED / LAPSED / WITHDRAWN. |
| Validation rules | "no student on the register is numbered X"; "X is on the roll of {code}; enter the mark on the sheet"; "late registration for this semester closed on {date}"; split checks; one held script per sheet and student. |
| Security | Any lecturer can hold on any sheet id; a release can add a score to a sheet already past ENTRY or PUBLISHED. |
| Audit trail | `assessment.held_script` attached. |
| Related modules | Results (§3.30); Registration (§3.13 — release triggers); Finance (§3.37 — owing). |
| Common errors | As above; a held mark that never releases is LAPSED. |
| Troubleshooting | The Registry can move `late_registration_closes` on the calendar. |

**Status:** IMPLEMENTED; NOT IMPLEMENTED — ownership check for holding, an export of the owing list.

### 3.32 Result queries

| Point | Content |
|---|---|
| Purpose | For seven days after publication a student queries one mark (EXAM, CA or an absence); the department answers UPHELD, CORRECTED or CLOSED and the student is told. |
| Users / roles | Read/answer `DEPARTMENT` hod, lecturer, exams, dean, records, academic, registrar, super (department offices bound); student raises and reads own. |
| Navigation | Academic → Result Queries → `/results/queries` (hod, exams); student Academic → Result Query → `/student/query`. |
| Dashboard | Tiles Open / Shown / Corrected / Upheld; student tiles Window / Your queries / Answered / Marks corrected. |
| Main features | Answer modal (Finding, Answer text); student Raise a query (Course, Which mark, What you say is wrong). |
| Create | `POST /me/queries`; `POST /results/queries/{id}/answer`. |
| View | Reference `QRY-YYYY-NNNNN`, Student, Course, Mark on the sheet, What they said, State. |
| Edit | None (one answer). |
| Delete / deactivate | None. |
| Search | None. |
| Filters | Open / Answered / All. |
| Reports | None. |
| Export | None. |
| Notifications | "Your result query {ref} is answered" (email) and an SMS; the department is not told of a new query. |
| Approval workflow | RAISED → UPHELD / CORRECTED / CLOSED. |
| Statuses | As above; part EXAM / CA / ABSENT. |
| Validation rules | "no mark of yours is on this sheet"; window = PUBLISHED and `published_at + 7 days`; "a query on this mark is already open"; a query names its part and says what is wrong; answered in words. |
| Security | A student can only query a sheet carrying a score of theirs. |
| Audit trail | `assessment.result_query` attached. |
| Related modules | Results (§3.30). |
| Common errors | "the query window for this course is not open" (the HINT says "five working days"; the window is seven calendar days). |
| Troubleshooting | CORRECTED has no mechanical effect — a PUBLISHED sheet cannot be returned or amended. |

**Status:** IMPLEMENTED — raise, answer, notify; NOT IMPLEMENTED — the correction path after CORRECTED (UI text promises it), a notice to the department.

### 3.33 Examination sessions, dockets and examination cards (student side)

| Point | Content |
|---|---|
| Purpose | The student sees only what Senate published: per-semester results with the desk each unpublished sheet is on, GPA/CGPA and class of standing, a Statement of Results PDF with a QR, a broadsheet PDF, carryovers, the examination docket with timetabled papers and an examination card PDF; the Examinations Office sets an offering's examination slot. |
| Users / roles | Student; exam slot `EXAMS` exams, facultyexams, records, academic, registrar, super (on the class-list desk); verification public. |
| Navigation | Academic → Results `/student/results`, Result Broadsheet `/student/broadsheet`, Carryover `/student/carryover`; Learning → Examinations `/student/exams`; slip `/student/results/{session}/{semester}`; slot on `/registration/class-list`. |
| Dashboard | Tiles This semester / Cumulative / Standing / Units this semester. |
| Main features | Results with "Where it is" stage per course; Academic summary (CUR, CUE, WGP, GPA, TCR, TCE, TWGP, LCGPA, CGPA); Download result slip; Print broadsheet; carryover list and "How a repeat is scored"; docket per open exam session (Course, Date & time, Venue, Status Withheld / Docket ready / Awaiting slot); Download exam card; Print the docket. |
| Create | `PUT /results/offerings/{id}/exam-slot`. |
| View | As above. |
| Edit | None. |
| Delete / deactivate | None. |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | Semester Results PDF (QR to `/verify/results`, check code), Result broadsheet PDF (no QR), Examination card PDF (QR to `/verify/exam`). |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Docket Withheld / Docket ready / Awaiting slot; results withheld per session when the clearance scheme says so. |
| Validation rules | Results redacted server-side when `finance.clears(…,'RESULTS')` is false under a scheme in force; PDFs refuse 409 "Withheld" / "Nothing published" / "No approved registration" / "Not cleared for examinations". |
| Security | Stateless SHA-256 check codes on the QR; `/api/v1/verify/**` unthrottled. |
| Audit trail | Reads only (`assessment.exam_timetable` attached). |
| Related modules | Results (§3.30); Finance (§3.36 — scheme); Public verification (§3.53); Documents (§3.51 — transcripts). |
| Common errors | "Your results are withheld until your fees are settled"; "Not yet timetabled"; statement 409 "Nothing published". |
| Troubleshooting | Pay under the scheme's RESULTS rule; the Examinations Office sets the slot on the class-list desk. |

**Status:** IMPLEMENTED; PLACEHOLDER — the "Official transcript" button ("Arrives with the credentials module" — transcripts are under My Documents); the statement PDF's grading key is hard-coded, not read from policy.

### 3.34 CBT question bank

| Point | Content |
|---|---|
| Purpose | A per-course bank of multiple-choice questions tagged by topic, difficulty and marks with a blueprint count. There is no CBT examination: no test, paper assembly, delivery or scoring exists. |
| Users / roles | `READERS` lecturer, hod, exams, facultyexams, dean, academic, registrar, admin, super; `AUTHORS` lecturer, hod, exams, dean, super; no course or department scope. |
| Navigation | Academic → Question Bank → `/exams/question-bank` (exams); lecturers have no menu item. |
| Dashboard | Tiles Course / Active questions / Topics / Marks available; Blueprint (Topic × Easy/Medium/Hard). |
| Main features | Author a question (stem, four options, correct answer, topic, difficulty, marks); Retire / Restore. |
| Create | `POST /cbt/questions`. |
| View | Courses table; questions list. |
| Edit | None (retire and re-author). |
| Delete / deactivate | Retire (`active=false`). |
| Search | None. |
| Filters | `?course=`. |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Active / Retired. |
| Validation rules | At least two options; answer within the options; difficulty EASY/MEDIUM/HARD; marks > 0; stem ≤ 2000. |
| Security | Any reader sees every course's bank. |
| Audit trail | `assessment.question` attached. |
| Related modules | Results (§3.30 — the lecturer's sheet list carries a question count). |
| Common errors | `CBT_OPTIONS`, `CBT_ANSWER`. |
| Troubleshooting | None. |

**Status:** IMPLEMENTED — the bank; NOT IMPLEMENTED — editing a question, CBT tests, scoping; the Examinations Officer's "CBT Sessions" menu item opens the results Examination Sessions.

### 3.35 College of Health Sciences (MB;BS)

| Point | Content |
|---|---|
| Purpose | From 200 Level a College student runs on the College's own years: semester-by-semester registration on that semester's fees, dated by the College calendar; postings with supervisors and logbooks from 400 Level; one Professional examination per level (CPE, PE1–PE4) with subjects marked CA + examination (+ clinical), pass judged by rule, provisional progression decisions confirmed by the College Academic Board on a minute (promote, resit, repeat, withdraw, graduate with Honours), Senate appeal after the Final; the 100 Level rule; the Student Payment Report. |
| Users / roles | `DESK` provost, collegesecretary, academic, registrar, dregistrar, admin, super; `DESK_OR_COORDINATOR` + mbbscoordinator; `EXAMINERS` DESK + lecturer, hod, exams, mbbscoordinator (College departments only); `READERS` + financecontroller, records, dean, hod, lecturer, exams, vc, dvc; `SUPERVISORS` lecturer, hod, exams + DESK (own posting); `PAYMENT_READERS` financecontroller, provost, collegesecretary, bursar, registrar, dregistrar, academic, dvc, vc, super; MBBS Coordinator bound to one level. |
| Navigation | College offices: Dashboard `/college/dashboard` (or `/college/coordinator`), Student Payment Report `/college/payments`, College Overview `/college`, Professional Examinations `/college/examinations`, College Calendar `/college/calendar`, Postings `/college/postings`, Logbooks `/college/supervision`, Score Sheet `/college/scoresheets` (coordinator); Academic → College of Health Sciences → `/college` (academic, records, registrar, super); Bursar → College Payment Report; lecturer → Postings I Supervise; student `/college/student`. |
| Dashboard | Tiles Students / Years open / Awaiting the Board / Postings this session; "What waits on the College"; "The session by level"; "The rotation this session"; "Fees this session"; coordinator tiles Level / Cohorts running / Students at the level / Awaiting the Board. |
| Main features | Register a year or semester (student or "Open the year for a student"); calendar dates per level with "Copy {prev}'s dates, a year on"; postings allocate/begin/complete/withdraw; logbook procedures, cases, attendance, mandatory events with Verify; results per subject and attempt; CA items; provisional decision override; "Confirm N decisions" with a Board minute; Senate appeal minute; score-sheet workbook download/upload/marked; payment report with Excel/PDF. |
| Create | `POST /college/register`, `/enrol`, `/allocations`, `/exams/{code}/results[/bulk]`, `/assessments`, `/exams/{code}/decisions|confirm|appeals`, logbook posts. |
| View | Candidates table with one column per subject and a Decision pill; overview; cohorts. |
| Edit | Decision while PROVISIONAL; allocations; calendar. |
| Delete / deactivate | Withdraw an allocation while ALLOCATED. |
| Search | Student search on postings; payment report search. |
| Filters | Session, Examination, Level, Posting, Show filters; payment report Period, Department, Programme, Level, Payment status. |
| Reports | Student Payment Report / Summary / by Programme; results and decisions CSV; reconciliation "ready for Senate" (read). |
| Export | Payment report branded Excel/print (serial CHSPAY, S/N first); score-sheet template and marked sheet (xlsx — **letterhead constant names "Moshood Abiola University of Science and Technology, Abeokuta"**); results CSV. |
| Notifications | None. |
| Approval workflow | Decision PROVISIONAL → CONFIRMED (Board minute); year OPEN → RESIT / CLOSED. |
| Statuses | Enrolment kind REGULAR / REPEAT / APPEAL, state OPEN / RESIT / CLOSED; attempt FIRST / RESIT / REPEAT / SENATE_APPEAL; outcome PROMOTE / RESIT / REPEAT / WITHDRAW_ADVISED / WITHDRAW_REQUIRED / APPEAL / GRADUATE; posting allocation ALLOCATED → IN_PROGRESS → COMPLETED / INCOMPLETE. |
| Validation rules | CA out of 30, examination out of 70, pass 50, attendance minimum (75 / 70 / none) bars; clinical component where the subject has one; results only once the year "reached final" (true when undated); a decision waits on every subject; the Board confirms on a minute; fees per semester (`finance.semester_cleared`); deferment gate; 100 Level: every non-GST course ≥ 50 else WITHDRAW_ADVISED (read-only advice). |
| Security | College examiner check binds department offices to College departments; `GET /assessments` reads any College student's CA for any EXAMINERS office; bulk results save the good rows of a partly refused sheet. |
| Audit trail | All `college.*` attached; `college.carry_over`, `college.project`, `college.department_unit` have no writer. |
| Related modules | Finance (§3.36 — semester fees); Deferments (§3.25); Student records (§3.23 — status changes); Statistics (§3.55). |
| Common errors | "The N Level year … has not reached its final semester"; "the N Level fees for {session} semester k are not yet cleared"; "the student has a College year still open"; "The MBBS Coordinator acts at N Level; this is M Level". |
| Troubleshooting | Date the level on the College calendar; pay the semester's fees; confirm the previous year's decisions. |

**Status:** IMPLEMENTED — years, calendar, postings, logbooks, examinations, decisions, Board confirmation, Honours, appeal, payment report, coordinator binding; PARTIALLY IMPLEMENTED — 100 Level rule (advice only, no withdrawal act), reconciliation to Senate (read only; nothing crosses to the University chain), CA items (not combined automatically); CONFIGURED BUT UNUSED — `carry_over`, `project`, `department_unit`, the Provost dashboard endpoint; NOT IMPLEMENTED — notifications, editing exam/subject/posting configuration; the score-sheet letterhead defect.

### 3.36 Finance: fee setup and the clearance scheme

| Point | Content |
|---|---|
| Purpose | State what each student owes for a session (fee lines with filters on level, entry mode, faculty, programme, fee group, semester, indigene and spillover), upload Council's approved structure in one go, put the clearance scheme in force, and state the applicant, postgraduate and transfer fees. |
| Users / roles | `FinanceController.READERS` bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc; `BURSARY` (write) bursar, super; applicant fees `FEESETTERS` academic, registrar, dregistrar, bursar, ict, admin, super; PG fees bursar, pgsecretary, pgschool, super. |
| Navigation | Finance → Fee Setup and Schedule → `/finance/fees` (bursar; financecontroller and pgsecretary — refused); Fee Schedules → `/finance/fees` (admin). |
| Dashboard | Tiles Items stated / Charge to everybody / Confirmed this session / References waiting. |
| Main features | Add an item modal (Payment item, Amount, Session, Semester, Programme group, Level, Entry mode, Faculty, Programmes); End a line; "Upload approved fees (.xlsx / .csv)" (cross-tab or one-row-per-fee; replaces the session's structure); "Clear the {session} schedule"; "Confirm" a waiting reference against the bank's record; "Put the recommended scheme in force" (instrument, from); Applicant · Post-UTME fees; Postgraduate fees; Inter-departmental transfer fee. |
| Create | `POST /finance/sessions/{s}/{y}/schedule`; `POST …/fee-structure`; `POST /finance/clearance-scheme`; `PUT /admissions/sessions/{s}/{y}/applicant-fees`; `PUT /pg/sessions/{s}/{y}/fees`; `PUT /finance/transfer-fee`. |
| View | The charges table (Item, Applies to, Amount); references waiting. |
| Edit | `PUT …/schedule/{id}` (keeps only the first ticked programme). |
| Delete / deactivate | End (soft, `ended_at`); Clear the schedule. |
| Search | None. |
| Filters | Faculty, Semester, Spillover, per page. |
| Reports | None. |
| Export | "Download Excel" (plain `buildXlsx`, not branded) and a hand-built print window. |
| Notifications | None from this screen (confirming a reference sends the receipt, §3.37). |
| Approval workflow | None. |
| Statuses | Fee line live / ended; scheme in force by date range. |
| Validation rules | Level 100–900; semester 1–2 in the modal (the filter offers three); amount ≥ 0; a scheme must not overlap another; the charge engine applies a line when every filter is blank or matches; charges accumulate as semesters open. |
| Security | The page's data calls are 403 for financecontroller and pgsecretary although both menus route them here. |
| Audit trail | `finance.fee_schedule`, `fee_setting`, `policy.version`/`clearance_rule` attached. |
| Related modules | Payments (§3.37); Registration (§3.13 — semester gate); Applicant portal (§3.18); PG admissions (§3.19); Transfers (§3.26); Matriculation (§3.24). |
| Common errors | "no charge is stated for 2026/2027 yet"; a student's due is 0 (no matching line or no OPEN semester); "no clearance scheme in force … D-Q4 is unanswered". |
| Troubleshooting | State lines or upload the structure; open a semester; put the scheme in force. |

**Status:** IMPLEMENTED — lines, charges engine, structure upload, scheme, references confirm, applicant/PG/transfer fees; PARTIALLY IMPLEMENTED — access for Finance Controller and Secretary SPGS (menu only); hard-coded fallback session "2026/2027"; no success toast on applicant and PG fee saves; `ord` never editable.

### 3.37 Payments, references and the Bursary desks

| Point | Content |
|---|---|
| Purpose | Mint payment references (`MOAUM-FEE-…`, 24 h), confirm them (gateway, Bursary against a bank record, import, wallet), issue receipt numbers, answer every student's position, and run the Bursary desks: payments query, day book, bank credits (maker–checker), refunds (maker–checker), reconciliation attestation, hanging payments, held scripts owing. |
| Users / roles | Student (`/me/fees…`); readers as §3.36; `BURSARY` bursar, super; `RECONCILERS` bursar, audit, deputyaudit, super; refunds readers bursar, super, audit, admin, writers bursar, super. |
| Navigation | Student Start here → School Fees — Pay First `/student/fees`, receipt `/student/receipt/{reference}`; Bursar Finance → Payments Query `/finance/payments`, Transactions & Accounts `/finance/ledger`, Payment Investigation / Cash Office & Assets `/finance/exceptions`, Refunds & Credits `/finance/refunds`, Reconciliation `/finance/reconcile`, Hanging Payments `/finance/hanging`, Held Scripts `/finance/held-scripts`; admin and audit variants (§2). |
| Dashboard | Student tiles Session charge / Paid / Outstanding; Bursar dashboard; page tiles (Payments matched, Total collected; Collected / By card / By bank / From the wallet; Open / Proposed / Posted / Cash ceiling; Awaiting approval / Approved, to pay / Paid / All; Gateway settled / Matched / Exceptions / Hanging; Hanging now / Resolved without a person / Needs a person / The sweep). |
| Main features | Instalment chooser and "Generate a reference for ₦x"; PayByCard; Payment History with Receipt; receipt document with QR; payments query with breakdowns; day book with "Export the journal"; bank credit Record → Propose → Approve and post / Reject; refund Raise → Approve → Mark paid / Reject; reconcile Matched / Flag; hanging "Ask the gateway"; event Resolve. |
| Create | `POST /me/fees/references`; `POST /finance/bank-credits`; `POST /finance/refunds`; `POST /finance/reconciliation/{ref}/check`; `POST /finance/references/{ref}/confirm`. |
| View | Payment History (Paid / Awaiting confirmation / Expired); receipt; day book; payments; credits; refunds; reconciliation ledger. |
| Edit | None (rows are appended). |
| Delete / deactivate | Reject a proposal or a refund. |
| Search | None (filters only). |
| Filters | Payments: session, faculty, department, programme, level (100–600 hard-coded), category, channel, dates; ledger and reconcile: from/to; credits: Open / Posted / All; refunds by state. |
| Reports | Payments query; day book; reconciliation; Bursary tiles (`/finance/bursary`); revenue return (§3.54). |
| Export | Payments query branded Excel/PDF (serial PAY, S/N first, rows loaded on the page only); ledger "journal" export (branded xlsx despite the `.csv` name); receipt PDF with QR and check code. |
| Notifications | "Your payment is confirmed" (email) and "MOAUM: payment {ref} confirmed, receipt {no}." (SMS) on every confirmation path; nothing for credits, refunds or reconciliation. |
| Approval workflow | Bank credit UNMATCHED → PROPOSED → POSTED (a different officer) / back to UNMATCHED; refund PROPOSED → APPROVED (different officer) → PAID / REJECTED. |
| Statuses | Reference OPEN / EXPIRED / CONFIRMED (derived); receipt `RCT-YYYY-NNNNN`; reconciliation MATCHED / DISCREPANCY; gateway event outcomes SETTLED, ALREADY_SETTLED, UNKNOWN_REFERENCE, SHORT_PAID, NOT_SUCCESSFUL, IGNORED, BAD_SIGNATURE, GATEWAY_ERROR. |
| Validation rules | "no charge is stated for … yet"; "the amount X is more than the balance of Y"; unknown reference 23503; confirmation idempotent and by a person; a proposal needs a reason, a portal reference, an amount ≥ the reference and not already confirmed; "the officer who proposed a posting does not approve it"; a refund ≤ what was paid; a discrepancy needs a note. |
| Security | Public receipt verification token-gated (first 12 hex of SHA-256(`reference|receiptNo`)); maker–checker enforced by CHECK constraints and actor checks; a manual confirm cannot short-pay. |
| Audit trail | `finance.payment_reference`, `bank_credit`, `refund`, `payment_reconciliation` (append-only) attached. |
| Related modules | Fee setup (§3.36); Gateways (§3.38); Wallet (§3.42); Hostel, Library, Documents (purpose references); Held scripts (§3.31). |
| Common errors | "reference X is already confirmed"; "Money against a settled reference is a duplicate"; the ReconcileLedger error toast that fires on every successful load (bug). |
| Troubleshooting | Raise a wallet credit or refund instead of a second posting; a part payment needs a reference for the part. |

**Status:** IMPLEMENTED; NOT IMPLEMENTED — bank-credit REVERSED state; refund payout is recorded, not executed; two client bugs (reconcile toast; Hanging "Resolve" failure shows nothing).

### 3.38 Payment gateways

| Point | Content |
|---|---|
| Purpose | Hosted checkouts on Paystack, Flutterwave and Quickteller, PayDirect PRN instructions, signed webhooks, verification, a ten-minute sweep over hanging attempts, encrypted keys, PayDirect billers and the collections import. |
| Users / roles | Checkout applicant, student; verify any authenticated for own reference, bursar/ict/admin/super/audit for any; `BURSARY` bursar, ict, admin, super (test checkout, sweep, resolve, PayDirect import, billers); `READERS` + audit, deputyaudit, registrar, vc, dvc; keys ict, admin, super; webhooks and `/payments/quickteller/start` public. |
| Navigation | Finance → Payment Gateways → `/finance/gateways` (bursar, admin, ict); Hanging Payments (§3.37). |
| Dashboard | Tiles Gateways live / Events today / Settled, all time / Exceptions open. |
| Main features | Configured gateways table (Mode Live/Test/Off, webhook address, "Wired"); key cards (Paystack, Flutterwave with hash, Quickteller four-field JSON, PayDirect query credentials); billers MAIN 04255101 and CHS 04263001; "Import and match" collections; "Open a test checkout"; "Verify with the gateway"; "Run the sweep now"; webhook and verification log with Resolve. |
| Create | `PUT /payments/gateways/{gateway}/key`; `PUT /payments/paydirect/billers/{scope}`; `POST /payments/paydirect/import`; `POST /payments/test-checkout`. |
| View | Log (When, Gateway, Event, Reference, Amount, Signature, Result). |
| Edit | Replace a key / configuration. |
| Delete / deactivate | Clear a key (the gateway turns off unless a service variable is set). |
| Search | None. |
| Filters | None. |
| Reports | Events (last 200), hanging, collections — on screen only. |
| Export | None. |
| Notifications | None of its own (a settlement triggers §3.37). |
| Approval workflow | None. |
| Statuses | Mode TEST / LIVE / OFF; collection MATCHED / UNMATCHED / DUPLICATE; outcomes as §3.37. |
| Validation rules | Signature before parsing (Paystack HMAC-SHA512, Flutterwave `verif-hash`; Quickteller re-queried); amount ≥ owed else SHORT_PAID; idempotent confirmation; `PAY_ALREADY_CONFIRMED`, `PAY_REFERENCE_EXPIRED`, `PAY_NO_EMAIL`, `PAY_GATEWAY_NOT_WIRED`; a key needs `MOAUM_CONFIG_KEY`. |
| Security | Keys encrypted with pgcrypto and never returned; webhooks unthrottled; `/payments/quickteller/start` exposes reference, amount and payer to whoever holds the reference. |
| Audit trail | `gateway_event`, `gateway_attempt`, `gateway_credential_event`, `paydirect_*` attached; `gateway_credential` exempt. |
| Related modules | Payments (§3.37); Applicant portal (§3.18); PG portal (§3.19); Wallet (§3.42). |
| Common errors | "Card and USSD payment arrive when a payment gateway is wired to the portal."; "A card checkout needs an email address on your record"; webhook 401. |
| Troubleshooting | Set a secret; add an email under Profile; match the secret/hash on the gateway dashboard. |

**Status:** IMPLEMENTED (tested) — Paystack, Flutterwave, keys, sweep, test checkout; IMPLEMENTED, UNVERIFIED AGAINST LIVE — Quickteller hosted page and requery; PARTIALLY IMPLEMENTED — PayDirect query API (endpoint unconfirmed; import works); the test form prefills demo student `MOAUM/MTC/24/9903`.

### 3.39 Receipts

| Point | Content |
|---|---|
| Purpose | The Bursary's official receipt for a confirmed payment reference, on screen and as a PDF with a QR and a check code that opens the public ledger record. |
| Users / roles | Student (own); public verification. |
| Navigation | Payment History → Receipt → `/student/receipt/{reference}`; PDF `/student/receipt/{reference}/pdf`; `/verify/receipt/{reference}?c=`; `/verify` entry page. |
| Dashboard | None. |
| Main features | Receipt number, date, passport, payer, matric, programme · level, session, semester, Being payment for, TOTAL RECEIVED, channel, gateway or teller reference, Verification block; "Download PDF". |
| Create | Issued by `finance.confirm_payment` (`RCT-<year>-NNNNN`). |
| View | As above; unconfirmed → "This payment is not confirmed yet". |
| Edit / Delete | None. |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | PDF (A4, microtext band, "Issued by the portal on …"). |
| Notifications | The confirmation email carries the receipt number. |
| Approval workflow | None. |
| Statuses | Confirmed / not confirmed. |
| Validation rules | PDF 409 "Not confirmed". |
| Security | Verification token first 12 hex of SHA-256(`reference|receiptNo`); without it `{genuine:false}`. |
| Audit trail | Reads only. |
| Related modules | Payments (§3.37); Public verification (§3.53). |
| Common errors | "Not verified — No confirmed receipt matches this code." |
| Troubleshooting | Check the reference and code; a receipt is real only if it appears on the verify page. |

**Status:** IMPLEMENTED.

### 3.40 Legacy fees and payment history

| Point | Content |
|---|---|
| Purpose | Clear returning students' past school-fees history (amount paid or "cleared in full" per session/semester) and load the old portal's confirmed payment history as it was. |
| Users / roles | Legacy fees bursar, super, admin; payment history `MIGRATORS` bursar, super, ict, admin. |
| Navigation | Finance → Old Fees History → `/finance/legacy-fees`; Payment History Upload → `/finance/payments-history` (bursar). |
| Dashboard | Result tiles Rows read / Settled / No such student / Nothing to settle. |
| Main features | Template downloads; browser parsing; preview (first 200 rows); "Load n rows" in chunks of 500 / 400; idempotent on derived references (`MOAUM-LEG-…`, `MIGR-…`). |
| Create | `POST /finance/legacy-fees {rows}`; `POST /finance/payments/import {rows}`. |
| View | Preview table. |
| Edit / Delete | None. |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | Templates "Old fees history template.xlsx", "Payment history template.xlsx". |
| Notifications | None (no student is notified of an imported payment). |
| Approval workflow | None. |
| Statuses | Counters rows / cleared / no_student / no_due; rows / imported / duplicate / no_student / bad_amount / skipped. |
| Validation rules | Session `YYYY/YYYY`; a blank amount means settle in full against the schedule; rows without a matching student are counted, never created; a blank session is filed under LEGACY. |
| Security | Every import is the officer's act on the spine. |
| Audit trail | `finance.payment_reference` rows attached. |
| Related modules | Payments (§3.37); Student records (§3.23 — migrated students). |
| Common errors | "That file needs at least Matriculation Number and Amount columns."; `no_due` (no amount and no schedule). |
| Troubleshooting | Migrate the students first; state an amount or a schedule. |

**Status:** IMPLEMENTED; no success toasts on either upload.

### 3.41 NELFUND and funding sources

| Point | Content |
|---|---|
| Purpose | Load the Fund's remittance files, match rows to students, reverse money to the Fund, load the Fund's decision list, credit a wallet from a named source, approve and pay withdrawals, keep the sources of funding, read the funding report. |
| Users / roles | `BURSARY` bursar, admin, super; match a row bursar, registrar, dregistrar, academic, super; `READERS` + audit, deputyaudit, ict, vc, dvc. |
| Navigation | Finance → Funding Sources `/finance/sources`; Sources & Wallets `/finance/nelfund`; NELFUND Applicants `?tab=status`; Match a Remittance `?tab=match` (bursar); tabs Withdrawals, Sources, Report. |
| Dashboard | Tiles Received this session / Allocated to students / Unallocated / Reversed to the Fund; status tiles Applied / Approved / Not approved / Still with the Fund; report tiles Funded / Applied to school fees / Withdrawn / Held in wallets. |
| Main features | Load a remittance (template, upload or paste); Credit a student's wallet; Look up a student's wallet with "Reset wallet to zero"; Suspense Credit (Registry) / Reverse (Bursary); Load the Fund's list; withdrawals Approve / Decline / Mark paid; sources add/edit/turn off; report by source, by nature, cash-flow reconciliation. |
| Create | `POST /nelfund/batches`, `/nelfund/credit`, `/nelfund/status`; `POST /funding/sources`. |
| View | Batches; unmatched rows with owner; refusal reasons; withdrawal requests; statement. |
| Edit | Sources (same code edits). |
| Delete / deactivate | Reverse a row; Reset a wallet (destructive, reason); turn a source off. |
| Search | Statement lookup by number. |
| Filters | Session; tabs. |
| Reports | Funding report (`/funding/sessions/{s}/report`), also on `/reports/funding/view`. |
| Export | None on any NELFUND tab; remittance template. |
| Notifications | None from these desks (a matched credit applied to fees sends the payment confirmation). |
| Approval workflow | Withdrawal REQUESTED → APPROVED (Bursary) → PAID (a different officer) / REJECTED. |
| Statuses | Row MATCHED / UNMATCHED / REVERSED; Fund status APPROVED / NOT_APPROVED / PENDING (correctable flag). |
| Validation rules | "A remittance is rows: matriculation number, name, amount."; a hand match says on what evidence; a credit needs a reason and a known source; "the wallet has been applied; NGN X cannot be reversed"; "the officer who approved a withdrawal does not also pay it". |
| Security | Numbers passed as query parameters (they contain "/"); the portal records the Fund's decisions, never makes them. |
| Audit trail | `finance.nelfund_batch`, `nelfund_row`, `nelfund_status`, `funding_source`, `wallet_withdrawal` attached. |
| Related modules | Wallet (§3.42); Payments (§3.37). |
| Common errors | "No student carries the number X."; "row … is not in suspense". |
| Troubleshooting | Unmatched rows owned by the Registry need the identity confirmed then matched with a note; arrears block a withdrawal until legacy fees are imported. |

**Status:** IMPLEMENTED; RECORD ONLY — the payout of a withdrawal; the Sources tab duplicates `/finance/sources` with different code validation and no Note field.

### 3.42 Wallet

| Point | Content |
|---|---|
| Purpose | An append-only student ledger fed by NELFUND, grants, Bursary credits and top-ups; applied to the session's school-fee balance (which confirms a reference on channel "NELFUND wallet"); a surplus withdrawn to a bank account once fees are cleared. |
| Users / roles | Student (`OFFICE_student`). |
| Navigation | Services → Wallet & Funding → `/student/wallet` (student, pgstudent). |
| Dashboard | Tiles Wallet balance / Funded / Applied to your invoices / Outstanding on your account; funding by source cards. |
| Main features | NELFUND status note (approved / not approved with the field to fix / pending); "Apply ₦x to {session}"; statement; top-up reference + PayByCard; withdrawal request (bank, account number, account name). |
| Create | `POST /me/wallet/apply`, `/topup-reference`, `/withdrawal`. |
| View | Statement (Date, Entry, Source, Reference, In, Out, Balance). |
| Edit / Delete | None. |
| Search | None. |
| Filters | `?session=`. |
| Reports | None. |
| Export | None. |
| Notifications | The payment confirmation on apply/top-up. |
| Approval workflow | Withdrawal (§3.41). |
| Statuses | Entry kinds CREDIT, TOPUP, APPLIED, REVERSED, REFUND; withdrawal REQUESTED / APPROVED / PAID / REJECTED. |
| Validation rules | Eligibility: session paid in full, no arrears, balance > 0, no pending withdrawal; "A top-up is for an amount."; "A withdrawal names the bank, the account number and the account name."; no client check that the amount ≤ balance. |
| Security | Students never see another wallet. |
| Audit trail | `finance.wallet_entry` attached (append-only except the Bursary reset). |
| Related modules | NELFUND (§3.41); Payments (§3.37). |
| Common errors | "Not available yet" with the API's reason. |
| Troubleshooting | Clear the session's fees and arrears first. |

**Status:** IMPLEMENTED.

### 3.43 General ledger (Accounting & Books)

| Point | Content |
|---|---|
| Purpose | A cash-basis double-entry set of books over the finance desk's money: chart of 33 accounts, sync of confirmed payments / paid refunds / paid vouchers, manual journals and reversals, trial balance, income & expenditure, balance sheet, account ledger. |
| Users / roles | Readers as finance READERS + deputyaudit; posting (sync, journal, reverse) bursar, super. |
| Navigation | Finance → Accounting & Books → `/finance/accounting` (bursar, admin). |
| Dashboard | Tiles Cash & bank on the books / Income this year / Expenditure this year / Surplus (deficit). |
| Main features | "Post them now" / Sync; tabs Overview, Trial balance, Income & expenditure, Balance sheet, Journal book, Account ledger; New journal (balanced lines); Reverse (mirror journal with a reason). |
| Create | `POST /finance/accounting/sync`, `/journals`, `/journals/{id}/reverse`. |
| View | Statements and the journal book. |
| Edit | None (postings are never edited). |
| Delete / deactivate | Reversal only. |
| Search | None. |
| Filters | Account, from/to on the ledger tab. |
| Reports | Trial balance; income & expenditure (also `/reports/income-expenditure/view`); balance sheet. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Journal POSTED / REVERSED; source MANUAL / AUTO. |
| Validation rules | "A journal needs at least two lines."; "Each line is a debit or a credit, and positive."; "The journal does not balance: debits X ≠ credits Y."; "A line names an account that is not on the chart."; a source transaction posts once. |
| Security | Posting by two offices. |
| Audit trail | `finance.gl_journal`, `gl_posting` (write-once) attached. |
| Related modules | Payments (§3.37); Expenditure (§3.44); Reports (§3.54). |
| Common errors | "does not balance"; "No such account." |
| Troubleshooting | Use postable codes from the chart. |

**Status:** IMPLEMENTED, unused so far (0 journals locally; sync is manual — no scheduler); the journal line `narration` has no input.

### 3.44 Expenditure: vouchers, budget, tenders, requisitions, stores and assets

| Point | Content |
|---|---|
| Purpose | Every University payment passes Internal Audit before money moves (voucher chain with queries and BR-006); budgets per cost centre with commitment accounting; tenders scored on a technical threshold before price; requisitions whose method follows the value; a consumables store and a fixed-asset register the audit directorate verifies; research grants (API only). |
| Users / roles | Vouchers: readers bursar, audit, deputyaudit, super, admin, vc; raise/pay bursar, super; advance/query/reject audit, deputyaudit, super (desk checked by acting office in SQL). Budget set bursar, super. Tenders writes bursar, super. Requisitions raise bursar, ict, registrar, hrm, dean, super; approve/po/close/reject bursar, super. Stores writes bursar, super; asset verify bursar, audit, deputyaudit, super. Grants write bursar, dvc, super. |
| Navigation | Audit Overview → Payment Vouchers `/` and Finance → A Voucher in Full `/vouchers`, Assets Register `/audit/assets`; Bursar → Payment Vouchers, Budget `/finance/budget`, Tenders `/finance/tenders`; dean/vc → Budget (dean refused); dean/hod/services → Requisitions `/finance/requisitions` (hod, services refused); library/services → Stores `/stores` (both refused); `/research/projects` (dean, lecturer refused; vc works). |
| Dashboard | Tiles On the audit desk / Queries open / Cleared to pay / All; Budget / Committed / Spent / Over budget; Open tenders / Awarded / All; Awaiting approval / Approved / Value awaiting / Requisitions; Inventory items / Below reorder / Fixed assets / Not verified in a year. |
| Main features | Raise a voucher; Sign & advance; Query; Answer query; Reject; Mark paid; Set a cost centre's budget; Open a tender, Record a bid, Score, Award, Cancel; Raise a requisition, Approve, Raise PO, Close, Reject; Add an inventory item, Adjust; Add a fixed asset, Verify, Condition. |
| Create | `POST /expenditure/vouchers|budget|tenders|requisitions`; `POST /stores/items|assets`; `POST /research/grants`. |
| View | Voucher trail; budget performance; bids ranked; requisitions; inventory and register. |
| Edit | Budget upsert; condition; adjust. |
| Delete / deactivate | Reject a voucher or requisition; cancel a tender; asset DISPOSED. |
| Search | None. |
| Filters | Voucher stage; financial year; tender/requisition state; store tabs. |
| Reports | Budget performance (`/reports/expenditure/view`); voucher trail; income & expenditure against budget. |
| Export | None on these pages (DTable Print). |
| Notifications | None. |
| Approval workflow | Voucher WITH_DIRECTOR → WITH_DEPUTY → WITH_AUDITOR → CLEARED → PAID (REJECTED from any non-final stage; an open query blocks); requisition RAISED → APPROVED (second person) → PO_RAISED → CLOSED / REJECTED; tender ADVERTISED → EVALUATED → AWARDED / CANCELLED. |
| Statuses | Method QUOTATION (< ₦2.5m) / RESTRICTED_TENDER (≤ ₦25m) / OPEN_BIDDING (tender codes RESTRICTED / OPEN differ); asset condition GOOD / FAIR / POOR / DISPOSED; grant PROPOSED / ACTIVE / COMPLETED / CLOSED / SUSPENDED. |
| Validation rules | "no person acts twice on a voucher (BR-006)"; "this desk is signed by audit, not by <office>"; pay only when CLEARED by the Bursary; budget available = budget − committed − spent; a non-responsive bid carries its reason; a lower responsive bid needs the Board's reason; store quantity ≥ 0. |
| Security | Free-text prompts for Query, Reject, Adjust, Condition; no PO or voucher document. |
| Audit trail | `expenditure.*` attached; `voucher_act` append-only. |
| Related modules | General ledger (§3.43 — paid vouchers sync); Reports (§3.54); HRM (§3.45). |
| Common errors | 403 on Requisitions/Stores for HOD, services, library; "a query stands against PV/…"; store adjust with text becomes `NaN`. |
| Troubleshooting | Route to another auditor; answer the open query; act as an office in the guard. |

**Status:** IMPLEMENTED — vouchers, budget, tenders, requisitions, stores, assets; PARTIALLY IMPLEMENTED — menu offices without API access (hod, services, library), the audit asset-verification page (read-only although the endpoint exists), research grants (backend without a working page); the Tenders page has an empty placeholder tile.

### 3.45 Human resources and payroll

| Point | Content |
|---|---|
| Purpose | The establishment (one live employment per person on a seeded grade/step), monthly pay runs with payslips (8 % pension, PAYE bands) under maker–checker, leave against typed entitlements, seventeen staff movements implemented only when an instrument is issued, recruitment vacancies and scored applicants, APER appraisal with promotion eligibility, the whole-person staff record. |
| Users / roles | Payroll readers hrm, bursar, audit, deputyaudit, admin, super, vc, dvc; build/approve/pay/cancel hrm, super; leave approvers hrm, hod (own department), dean, dregistrar, registrar, audit, admin, super; movements raise/issue hrm, registrar, super, approve hrm, registrar, dregistrar, vc, dvc, super; recruitment hrm, registrar, super; appraisal record hrm, registrar, dean, hod, super; staff record read 18 offices; `/me/leave*`, `/me/payslips` any authenticated. |
| Navigation | hrm: Overview → Movements `/`, Finance → Payroll `/payroll`, Staff → Open a Movement `/hr/movements`, Staff Records `/staff`, Recruitment `/hr/recruitment`, Leave Requests `/hr/leave`, Appraisal `/hr/appraisal`; bursar → Payroll; audit → Payroll Variance `/payroll/variance`, Staff Movements `/audit/staff`; hod → Leave, Appraisal; registrar → Recruitment, Staff Records (refused); housing → Staff Records (refused); every staff office Me → Leave & Payslip `/me`. |
| Dashboard | HR home tiles Staff on the establishment / Leave to decide / Instruments to issue / Open vacancies; payroll tiles Runs / Awaiting approval / Approved, to pay / Last net paid; leave, movement, recruitment and appraisal tiles. |
| Main features | Build the run (month), Approve, Mark paid, Cancel; payslips table; variance JOINED / LEFT / CHANGED; leave Approve / Decline; Open a movement (17 types, new grade and step), Approve, Decline, Issue instrument (`MOAUM/R/ACA/YYYY/NNNN`); Advertise a vacancy, Record an application, Score, Shortlist, State; Record an appraisal; self-service Request leave / Cancel and payslips. |
| Create | `POST /payroll/runs`; `POST /me/leave`; `POST /hr/movements`; `POST /hr/vacancies`, `…/applicants`; `POST /hr/appraisal`. |
| View | Establishment (Staff, Grade, Category, Monthly gross, Bank, Status); runs and payslips; promotion candidates; staff record pop-up with photo. |
| Edit | Appraisal upsert per person and cycle; vacancy state; applicant assess. |
| Delete / deactivate | Cancel a run; Decline; movements RETIREMENT/RESIGNATION/DISENGAGEMENT/DISMISSAL end the employment. |
| Search | None. |
| Filters | Leave tabs Awaiting / Approved / Declined / All; movement tabs; `?period=`; `?cycle=`. |
| Reports | Payroll variance; establishment; staff register and staff ratio (§3.54). |
| Export | None (DTable Print); no payslip PDF, no bank schedule. |
| Notifications | None. |
| Approval workflow | Run DRAFT → APPROVED (different person) → PAID / CANCELLED; leave REQUESTED → APPROVED / DECLINED / CANCELLED; movement REQUESTED → APPROVED → IMPLEMENTED / DECLINED (RETURNED unused). |
| Statuses | Employment ACTIVE / SUSPENDED / ENDED; vacancy OPEN / SHORTLISTING / INTERVIEW / OFFER / CLOSED / CANCELLED; applicant APPLIED / SHORTLISTED / RESERVE / REJECTED / INVITED / OFFERED / DECLINED / APPOINTED; appraisal SELF / SUPERVISOR / MODERATED. |
| Validation rules | "the officer who built a pay run does not approve it"; one run per month; only ACTIVE employments paid; one pending leave per person; days ≤ the type's max ("ANNUAL allows at most 30 day(s)"); annual balance; a movement needs an existing employment ("no employment on record for this person"); grade/step from the seeded 18 rows. |
| Security | HOD scoping depends on `staff_record.home_department`; vacancy state and assess accept any string satisfying the CHECK. |
| Audit trail | `hrm.*` attached; `staff_photo` exempt. |
| Related modules | Identity (§3.5 — importers write `staff_record`); Staff directory (§3.46); Expenditure (§3.44). |
| Common errors | "only a serving member of staff may request leave" (no ACTIVE employment); "a pay run for <Month> already exists"; HOD sees no leave (no home department). |
| Troubleshooting | Real staff are not on the establishment unless seeded — **nothing in the API or migrations inserts `hrm.employment`** except `demo.sql`. |

**Status:** IMPLEMENTED (engine) but PARTIALLY IMPLEMENTED as payroll — no way to add staff to the establishment, set bank details or grades from the portal, no other deductions, no payslip PDF; PARTIALLY IMPLEMENTED — recruitment (free-form states, no link to employment; only Shortlist is a button); PLACEHOLDER — `/me` Appraisal / Appointment / Next increment tiles; wrong titles on `/audit/staff` and the HR home ("Staff movements").

### 3.46 Staff directory, profile and staff identity cards

| Point | Content |
|---|---|
| Purpose | "Who am I on this portal and under what instrument" (`/staff/me`), the member of staff's own academic profile (CV) and photograph, the establishment list, the department staff list, the staff register and the staff identity card PDF. |
| Users / roles | `/staff/me`, `/staff/profile` any authenticated (actor = token subject); `/payroll/staff` payroll readers; `/hod/staff` hod; staff register readers (§3.54). |
| Navigation | Me → Leave & Payslip `/me` (record, offices held, "My ID card (PDF)"); My Profile `/me/profile` (lecturer menu; linked from `/me`); Staff → Staff Records `/staff`; Department Staff `/hod/staff`; Reports → Staff Register `/reports/staff`; `/staff/idcard/pdf[?id=]`. |
| Dashboard | `/me` tiles Leave taken / Leave remaining / Last payslip / Appraisal ("—"); `/staff` tiles On the roll / Academic / Non-academic / Monthly gross; department tiles Staff on the establishment / Hold a teaching office / Professors. |
| Main features | Profile panels Photograph, Who you are, Research, Research output, Engagement and recognition; "Save profile"; offices held with instrument; staff record pop-up from lists. |
| Create | None. |
| View | Establishment; department staff (Name, Rank, No., Sex, Teaching, Status). |
| Edit | `PUT /staff/profile`; `PUT /staff/profile/photo` (JPEG/PNG ≤ 2 MB). |
| Delete / deactivate | None. |
| Search | Staff register search (name, staff number or email). |
| Filters | Register: Faculty, Department, Rank, Category, Status, Office held. |
| Reports | Staff register. |
| Export | Staff register branded Excel (16 columns) and print view; staff card PDF. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Employment status; offices live flag. |
| Validation rules | Photo type and size; list fields must be JSON arrays; email regex in the DB; no format check on ORCID/URL. |
| Security | The staff card's serial `STF-…-{year}` and "Valid to" are computed at print; nothing is stored; a PNG photo prints blank. |
| Audit trail | `hrm.staff_profile` attached. |
| Related modules | HRM (§3.45); Identity (§3.5); Reports (§3.54). |
| Common errors | "You are signed in, but the Registry has no record of you yet"; 409 "No staff number" on the card. |
| Troubleshooting | The Registry creates the person with a staff number. |

**Status:** IMPLEMENTED — record, profile, photo, lists, register, card PDF (stateless); PLACEHOLDER — the `/me` Appraisal/Appointment/Next increment tiles and a stale header comment; NOT IMPLEMENTED — a staff card register.

### 3.47 Hostel accommodation

| Point | Content |
|---|---|
| Purpose | A student's whole stay on the record: inventory of halls, blocks, rooms and beds (a bed is a row); the session's window with fee, hold hours, eligibility rules and allocation method; applications with preferences and a roommate; desk review; the allocation run (seven methods, ballot from a published seed); holds that lapse and pass to the waiting list; the fee through an ordinary payment reference; acceptance under versioned rules; porter's check-in; transfers; maintenance; checkout inspection, damage charges and the hostel clearance that signs the HOSTEL unit. |
| Users / roles | `OFFICE` services, housing, registrar, admin, super; `READERS` + bursar, dregistrar, academic, ict, audit, vc, dvc; student under `/me/hostel…`; no hall-level scope. |
| Navigation | housing Accommodation → Hostel Dashboard `/hostel`, Application Window & Rules `/hostel/window`, Hostel Inventory `/hostel/inventory`, Applications & Waitlist `/hostel/applications`, Occupancy & Check-in `/hostel/occupancy`, Checkout & Clearance `/hostel/clearance`; services Students → Hostel Accommodation `/hostel`; student Services → Hostel `/student/hostel`; `/hostel/allocations/{id}`, `/hostel/students/{id}`; PDFs `/student/hostel/letter`, `/student/hostel/clearance`; `/verify/hostel/{ref}`. |
| Dashboard | Twelve tiles (Total beds, Occupied, Reserved, Available, Under maintenance, Students accommodated, Applications, Allocated, Waitlisted, Checked out, Pending clearance, Open maintenance); "Waiting at this desk"; seven charts; Housing dashboard at `/`. |
| Main features | Window (fee, hold window 1–720 h, dates, method, review required, waiting list, eligibility by status/level/faculty/hall kind, registration required, refuse hostel debt, rules text with version); inventory with Generate rooms (≤ 500) and close/reopen with affected occupants; applications review (Approve / Reject / Correction / Waitlist, bulk), Allocate into a named free bed; Generate Allocation (seed for BALLOT), Lapse expired holds; bed board and student views; allocation page Check in, Transfer, Cancel, Checkout inspection, Raise a damage charge, clearance items Clear / Hold / Waive / N/A, Complete, Reopen; transfer decisions; maintenance Update; student Apply, Pay, Accept (rules acknowledgement), Decline, Withdraw, Request transfer, Request checkout, maintenance, letters. |
| Create | `PUT /hostel/sessions/{s}/{y}/window`, `/hostel/halls-full|blocks|rooms-full|assets`, `POST /hostel/rooms/generate`; `POST …/applications/{id}/allocate|review|withdraw`, `…/draw`, `…/lapse`; `POST /hostel/allocations/{id}/checkin|transfer|inspect|charge|cancel`; student `POST /me/hostel/apply-full|fee-reference|accept|decline|transfer|checkout|maintenance-full`. |
| View | Applications table (17 columns exportable); occupancy Beds / Students / To check in / Checkout requested; clearances, checkout requests, transfer requests, maintenance tabs; history and trail. |
| Edit | Window (dates and rules after the draw); inventory; maintenance state/priority/assignee; delivery of clearance items. |
| Delete / deactivate | Close a hall/block/room/bed with a reason; Cancel an allocation; Withdraw an application; retire an asset. |
| Search | Applications and occupancy search (name, ID, application number, programme). |
| Filters | Standing, Faculty, Department, Programme, Level; Hostel, Block, Status, Gender; clearance status. |
| Reports | Occupancy by hostel in figures; bed board. |
| Export | Branded Excel/PDF (serial HST, S/N first): Hostel Occupancy by Hall, Hostel Inventory, Hostel Bed Inventory, Hostel Applications, Hostel Bed Board / Occupancy — Students, Hostel Clearance, Checkout Requests, Transfer Requests; allocation letter and clearance certificate PDFs with QR. |
| Notifications | Email + SMS to the student and email to the desk at every turn (§8 lists 24 events). |
| Approval workflow | Application APPLIED → ALLOCATED → CONFIRMED; LAPSED / UNSUCCESSFUL / WITHDRAWN / REJECTED; allocation HELD → CONFIRMED → ACCEPTED → CHECKED_IN → CHECKED_OUT; DECLINED / LAPSED / CANCELLED / TRANSFERRED; clearance PENDING → CLEARED / NOT_CLEARED. |
| Statuses | Window DRAFT / OPEN / CLOSED / ALLOCATED; transfer request SUBMITTED / UNDER_REVIEW / APPROVED / REJECTED / COMPLETED; maintenance RAISED / ASSIGNED / FIXED / CLOSED; occupancy OCCUPIED / RESERVED / MAINTENANCE / OUT_OF_SERVICE / AVAILABLE. |
| Validation rules | Eligibility messages ("A student whose status is {x} is not eligible", "Course registration for {s} has not been submitted", "An unsettled hostel damage charge of NGN {x} stands"…); one application per session; the draw runs once from a seed ≥ 6 characters; a hold expires at `allocated + hold_hours`; fee before acceptance; rules acknowledged before acceptance; check-in only on a confirmed, accepted allocation; a transfer/cancel/closure carries a reason; "% requirement(s) still pending" before completion; hall code `^[A-Z0-9]{2,8}$`; room beds 1–12. |
| Security | `/api/v1/verify/hostel/{ref}` is public with **no check token and no rate limit** over a sequential `ALC-YYYY-NNNNN` reference (names, photographs and room numbers can be enumerated). |
| Audit trail | All `hostel.*` attached; `hostel.event` write-once. |
| Related modules | Payments (§3.37 — `hostel.confirm_by_reference`); Clearance (§3.28 — HOSTEL item); Public verification (§3.53). |
| Common errors | "Accommodation for {session} is not open yet"; "Generate Allocation" disabled; "the draw for … was run on …"; "nobody checks in on a hold"; "Complete clearance" disabled. |
| Troubleshooting | Create and open the window; add rooms or approve applications; seat late applicants manually; confirm the fee; decide every item. |

**Status:** IMPLEMENTED (end-to-end test `HostelIT`; hourly hold clock); IMPLEMENTED but UNUSED BY THE UI — the V030 legacy endpoints; no menu for registrar/admin/super; category claims are not verified by the system; `CANCELLED` transfer state never set.

### 3.48 ICT help desk (tickets)

| Point | Content |
|---|---|
| Purpose | A student or member of staff raises a ticket (`TICK-YYYY-NNNNN`) with a category's own fields and up to ten attachments; the desk opens, works, resolves with a written resolution, and closes (requester confirms, desk closes on a reason, or auto-close after a quiet spell); internal notes the requester never sees; SLA hours by priority; reports; public tracking by number and email. |
| Users / roles | `REQUESTER` any signed-in non-applicant with a person record; `AGENTS` ictagent, ict, admin, super; `DIRECTOR` ict, admin, super. |
| Navigation | Administration → ICT Support Desk `/helpdesk`, ICT Support Reports `/helpdesk/reports`, ICT Support Settings `/helpdesk/settings` (ict, admin, super); ictagent Overview → ICT Support Desk; every staff office and student Me/Services → ICT Support Tickets `/tickets`; `/tickets/new`, `/tickets/{id}`, `/helpdesk/tickets/{id}`; public `/track`. |
| Dashboard | Desk KPIs Total tickets / New / Opened / In progress / Unassigned / High priority / Overdue / Average resolution; "With you"; Director's Agent workload and Tickets by category; requester tiles Open / Awaiting your confirmation / Closed / All. |
| Main features | Submit a New Ticket (category, dynamic fields, subject, description, attachments); Track a Ticket; requester Confirm Resolution / Reopen / Close This Ticket / Add an update; desk queue with server-side search, filters, sort, paging, Take; ticket Accept / Assign / Start Work / Resolve / Close as Resolved / Reopen / Escalate / priority / Close on a Reason; Internal Note vs Update to the Requester; categories editor with fields; SLA by priority; auto-close days; "Email every agent and the Director when a new ticket arrives". |
| Create | `POST /helpdesk/my/tickets` (+ attachments); `POST /helpdesk/admin/categories`. |
| View | Queue; ticket with conversation and history; reports. |
| Edit | `PUT /helpdesk/admin/categories/{id}`; `PUT /helpdesk/admin/settings`; priority. |
| Delete / deactivate | A category is deactivated, never deleted. |
| Search | Queue search (number, subject, name, matric/staff number, email, payment reference, username). |
| Filters | Status, Category, Priority, Agent, Raised from/To; report filters add Faculty, Department. |
| Reports | Tickets, Overdue, Average first response, Average resolution; monthly volume; breakdowns by status, category, priority, requester, faculty, department, agent. |
| Export | "Download the Report" CSV (not branded); no PDF, no printed ticket. |
| Notifications | Email only (§8): received, new ticket to agents, opened/status change, assigned, escalated, resolved, closed, reopened, agent update, requester update. |
| Approval workflow | SUBMITTED → OPENED → IN_PROGRESS → RESOLVED → CLOSED; REOPENED. |
| Statuses | As above; priority LOW / NORMAL / HIGH / URGENT; SLA seeded LOW 72/240 h, NORMAL 24/120, HIGH 8/48, URGENT 2/24. |
| Validation rules | Subject ≤ 200, description ≤ 8000, email reachable, required category fields, "ten tickets are open already"; resolution summary ≥ 5 and details ≥ 20; reasons ≥ 5; attachments PDF/JPEG/PNG ≤ 5 MB, sniffed, ≤ 10; tracking 12 lookups per 15 minutes per IP and email. |
| Security | Requesters never read internal notes or files; attachments served sandboxed; the public track answers with no names. |
| Audit trail | `helpdesk.*` attached; `ticket_event` write-once; blobs exempt. |
| Related modules | Notices (§3.3); Identity (§3.5 — `ictagent` office). |
| Common errors | `HELPDESK_NOT_A_MEMBER`; "a ticket is resolved from in progress"; "only an ICT Support Agent or the Director of ICT takes a ticket"; tracking "No ticket with that number was raised with that email address." |
| Troubleshooting | Create the person record; Start Work first; grant the `ictagent` office. |

**Status:** IMPLEMENTED (end-to-end test `HelpdeskIT`; auto-close off by default); NOT IMPLEMENTED — satisfaction rating.

### 3.49 Help & Requests (service requests to an office)

| Point | Content |
|---|---|
| Purpose | A student's one-line request to one of eight offices (Registry, Bursary, ICT, Library, Student Services, Academic Office, My department, Housing) with detail and up to six documents; the office answers on the record, resolving or keeping open; the student is told. |
| Users / roles | Student; `OFFICES` registrar, dregistrar, bursar, ict, library, services, academic, hod, housing, admin, super — each sees only requests addressed to its own code (admin, super, ict see all). |
| Navigation | Services → Help & Requests → `/student/support` (student, pgstudent); the office desk `/support` is on no menu. |
| Dashboard | Desk tiles Open (oldest age) / Answered still open / Resolved / All. |
| Main features | Raise a new request (office pills, subject, detail, documents); desk Answer modal with "This resolves the request." |
| Create | `POST /me/requests` (+ documents); `POST /support/requests/{id}/answer`. |
| View | Your requests; desk table. |
| Edit / Delete | None; no student reply. |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | None. |
| Notifications | "Your request {ref} is resolved" / "…has an answer" (email + SMS); none to the office. |
| Approval workflow | OPEN → RESOLVED or WITH_OFFICE (CLOSED never set). |
| Statuses | As above; reference `SR-YYYY-NNNNN`. |
| Validation rules | Office in the eight; "say what the problem is, in one line"; five open requests at most; ≤ 6 documents, PDF/JPEG/PNG ≤ 2 MB (no magic-byte sniffing). |
| Security | Ownership and office checks; `dregistrar` is in the guard but cannot be addressed (desk always empty); a HOD sees every "hod" request, not only their department's; documents served without `nosniff`/sandbox. |
| Audit trail | `platform.service_request`, `request_document` attached. |
| Related modules | ICT help desk (§3.48 — separate by design); Student portal. |
| Common errors | "five requests are open already"; an office sees nothing (requests are per office code). |
| Troubleshooting | Open `/support` directly. |

**Status:** IMPLEMENTED — raise and answer; PARTIALLY IMPLEMENTED — the office desk is on no menu; NOT IMPLEMENTED — student reply, HOD department scope, reminders; CONFIGURED BUT UNUSED — CLOSED.

### 3.50 Clinic (University Health Services)

| Point | Content |
|---|---|
| Purpose | A minimal clinic record: booking or walk-in, triaged waiting list, opening the record (logged), concluding with an outcome the student sees, a referral, a clinical note that never leaves the clinic, and a fitness status; consent to blood group, genotype and allergies. |
| Users / roles | `CLINIC` services, super; student for `/me/health…`. |
| Navigation | Overview → Clinic → `/clinic` (services, home); student Services → Health → `/student/health`. |
| Dashboard | Tiles Encounters today / Awaiting triage / Referrals this month / Fitness recorded. |
| Main features | Patient arrives (number, presenting complaint, triage); Look the patient up; Booked with Arrived; Waiting list with See now / Open; Conclude the visit (Outcome, Referred to, Fitness, Clinical note). |
| Create | `POST /health/visits`; student booking `POST /me/health/appointments`. |
| View | Waiting list, concluded today, earlier visits. |
| Edit | Consent / restrict (student). |
| Delete / deactivate | Student cancels a BOOKED appointment. |
| Search | Patient lookup. |
| Filters | None. |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Appointment BOOKED → SEEN / CANCELLED (MISSED unused); visit WAITING → IN_CONSULTATION → DONE (LEFT unused); fitness PENDING / FIT / UNFIT / FIT_WITH_CONDITIONS. |
| Validation rules | "say why you want to be seen"; "choose a time ahead"; one booked appointment; "the patient is already on the waiting list"; "a visit is concluded with its outcome"; triage URGENT / STANDARD / ROUTINE. |
| Security | Every record read is logged and shown to the patient; notes returned only to the clinician; no dedicated clinician office. |
| Audit trail | `health.profile`, `appointment`, `visit` attached; `note` and `record_access` exempt with stated reasons. |
| Related modules | Clearance (§3.28 — HEALTH unit signed by services manually). |
| Common errors | "Nobody carries the number X"; "an appointment already stands". |
| Troubleshooting | Use the matric or admission number as issued. |

**Status:** IMPLEMENTED — booking, arrival, triage, open, conclude, fitness; NOT IMPLEMENTED — pharmacy/dispensing ("Pharmacy stock is not on the portal"), prescriptions, lab, medical certificates, notifications, exports; CONFIGURED BUT UNUSED — MISSED, LEFT.

### 3.51 Documents, certificates and transcripts

| Point | Content |
|---|---|
| Purpose | Digital academic documents (V262) on the credential store: a policy per kind (degree certificate, official full transcript, sessional transcript, mini-transcript, statement of academic record); versioned templates; the statement built from the authoritative result record and kept byte for byte with a SHA-256 hash, a Crockford verification code and a number `PREFIX/YYYY/NNNNNN`; the request pipeline (invoice, validation, generation, quality check, release by a second officer, delivery by expiring tokens or courier, completion); degree certificates issued singly or in a run; revoke on a minute; reissue as a new version; flags when a result or award changes; the student's library; the legacy transcript queue and the printed certificate register. |
| Users / roles | `READERS` academic, registrar, dregistrar, records, dvc, vc, bursar, ict, admin, super, audit; `OFFICE` academic, registrar, dregistrar, records; `SIGNERS` registrar, dregistrar, academic; `REVOKERS` registrar, vc; `CONFIG` registrar, dregistrar, academic, super; student under `/me/documents…`; the producer never releases (BR-006). |
| Navigation | Students → Documents Office `/credentials/documents` (academic, records, registrar, dregistrar) with sub-pages `/requests`, `/requests/{id}`, `/register`, `/settings`; Transcripts `/credentials/transcripts`; Certificates `/credentials/certificates` (academic, records, registrar); student Academic → My Documents `/student/documents`; `/student/transcript` redirects there; public `/verify/document`, `/documents/d/{token}`. |
| Dashboard | Twelve tiles (New requests, Payment pending, Held at clearance, Processing, Quality check, Awaiting release, Ready for delivery, Delivered, Breaching SLA, Certificates issued, Transcripts issued, Revoked · reissued · flagged); charts Requests by stage, Verification and downloads (30 days), Revenue by kind, Processing time; "Graduates awaiting a digital certificate"; "Documents flagged after the record changed". |
| Main features | Request wizard (kind, delivery Digital/Physical/Both, copies 1–10, urgent, international, recipient, purpose, fee review); PayByCard; Download PDF; Secure link (7 days); Timeline with Cancel; office Validate the record / Generate the document / Quality check / Authorise and release / Mark completed / Cancel; deliveries Update, Resend link; register Reissue / Revoke (reason + minute) / Clear the flag; policies and template versions; Issue / Issue N certificate(s); legacy queue Record payment / Produce & verify / Sign & release; printed certificate register with stationery batches, Collected / Hold / Reissue / Spoiled one. |
| Create | `POST /me/documents/requests`; `POST /documents/certificates[/bulk]`; `POST /documents/templates`; `POST /credentials/certificates`; `POST /me/documents/{id}/link`. |
| View | Requests (16 columns), issued documents (14 columns), verification log, versions, trail, downloads. |
| Edit | `PUT /documents/policies/{kind}`; delivery state, courier, tracking. |
| Delete / deactivate | Cancel a request (AWAITING_PAYMENT / READY / HELD_AT_CLEARANCE); Revoke (REVOKERS); Reissue supersedes (old REPLACED). |
| Search | Requests and register search (name, ID, request, document number or code). |
| Filters | Stage, Document, Payment, Delivery, Faculty, Department, Programme; register Kind, Status, Flagged. |
| Reports | Dashboard figures; revenue by month; verification log. |
| Export | Branded Excel/PDF (serial DOC, S/N first): Graduates Awaiting Certificate, Document Requests, Issued Documents, Document Verifications (PDF); generated document PDFs (certificate after the University's own layout; transcripts and statements with QR and code; REVOKED / REPLACED watermarks). |
| Notifications | Email + SMS to the student and email to the desk (§8: submitted, processing, generated, QC, released, delivery failed/done, cancelled, certificate issued, revoked, reissued, flagged, link resent). Identity cards, the printed register and the legacy queue send none. |
| Approval workflow | AWAITING_PAYMENT / HELD_AT_CLEARANCE / READY → PROCESSING → GENERATED → VERIFIED / CORRECTION / REJECTED → RELEASED → DELIVERED → COMPLETED; CANCELLED. Free self-service kinds (mini-transcript, statement) are generated and RELEASED at once. |
| Statuses | Document ACTIVE / REVOKED / REPLACED (+ flag); delivery NOT_SENT / READY / SENT / DELIVERED / FAILED / EXPIRED / RESENT and PROCESSING / DISPATCHED / IN_TRANSIT / DELIVERED / RETURNED; printed certificate PRINTED → COLLECTED / HELD / REISSUED (REVOKED never set). |
| Validation rules | A matriculation number ("Matriculation comes first."); graduates-only kinds; a sessional transcript names its session with a published result; recipient for a third party; address for physical; one identical request per day; validation ERRORs (no matric, programme not on the list, EXPELLED/RUSTICATED, no published result, certificate: not GRADUATED / no Senate-approved award / convocation clearance incomplete, transcript: TRANSCRIPT clearance incomplete); "request % is not paid; processing begins at payment"; "the officer who produced a transcript does not sign it"; "an active degree certificate already stands"; bulk issue rolls back on the first refusal; a reissue and a revoke carry a reason (revoke also the minute). |
| Security | Public verification throttled 40 lookups / 15 minutes per IP, every lookup logged, only the policy's public fields shown, results never; secure-link tokens 24 bytes with expiry and use limits, revoked with the document; the "signature" is a hash — no cryptographic signing (`credentials.signing_key` empty). |
| Audit trail | `credentials.issued`, `revocation`, `transcript_request`, policies, templates, `event` (write-once), `delivery`, `download_token`, `certificate`, `stationery_batch` attached; `download_log`, `verification`, `lookup_miss` exempt. |
| Related modules | Results (§3.30); Graduation (§3.29); Clearance (§3.28); Payments (§3.37 — "Transcript {ref}" references); PG coursework and research (§3.20–21); Public verification (§3.53). |
| Common errors | "a document is issued against a matriculation number"; "Payment pending"; "Held at clearance"; "Generate the document" disabled (ERROR findings); "Authorise and release" disabled (you produced it); "Too many verifications from this source". |
| Troubleshooting | Matriculate; pay the reference; clear the holding unit; another signer releases; resend an expired link. |

**Status:** IMPLEMENTED (end-to-end tests `DocumentsIT`, `CredentialsIT`) — policies, templates, wizard, pipeline, deliveries, certificates, revoke/reissue, flags, verification, register, PDFs; NOT IMPLEMENTED — cryptographic signing / offline verification; IMPLEMENTED (kept) — the legacy transcript queue (its "View verification" button does nothing; no screen raises a request on a student's behalf); printed certificate `/stationery/{id}/return` has no button.

### 3.52 Identity cards (student)

| Point | Content |
|---|---|
| Purpose | Issue a student identity card keyed on the matriculation number once the Bursary's position releases ID_CARD, record loss and replacement, and give the student a printable copy. |
| Users / roles | `READERS` library, security, registrar, dregistrar, academic, records, ict, super; `ISSUERS` library, security, super; student `/me/id-card`. |
| Navigation | Overview → Card Printing → `/credentials/idcards` (library, home); Services → Card Collection / Lost & Replacement → same page (security); student Services → Identity Card `/student/idcard`; PDF `/student/idcard/pdf`. |
| Dashboard | Tiles Waiting for a card / Live cards / Lost or replaced / Issued today. |
| Main features | "Waiting for a card" (matriculated ADMITTED/ACTIVE/PROBATION/DORMANT students without a live card) with Issue the card / Issue a replacement; "Cards issued" with Report lost; student card preview, "Open the printable copy", "Report it lost", "Request a replacement" (→ Help & Requests). |
| Create | `POST /credentials/identity-cards/students/{id}/issue`. |
| View | Card number `MOAUM/ID/YY/NNNNN`, issued, valid to (four years), state. |
| Edit | None. |
| Delete / deactivate | Report lost (`…/lost`; a new card marks the old REPLACED). |
| Search | Matric or surname. |
| Filters | None. |
| Reports | None. |
| Export | Student card PDF (front/back, Code-128 barcode of the matric number, QR text `MOAUM ID {serial}` — not a URL). |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | ISSUED → LOST / REPLACED (RETURNED never set); one live card per student. |
| Validation rules | "an identity card is keyed on the matriculation number, and % has none yet"; "the Bursary has not cleared this student for the identity card in {session}" (`finance.clears(…,'ID_CARD')`, released at the first instalment under the recommended scheme). |
| Security | No card verification exists (the CSO's "Verify a Card" is a label only); no collection record. |
| Audit trail | `credentials.identity_card` attached. |
| Related modules | Finance scheme (§3.36); Matriculation (§3.24); Staff cards (§3.46). |
| Common errors | 409 "No identity card issued" on the PDF; "waits on the Bursary's clearance". |
| Troubleshooting | Pay the first instalment; matriculate. |

**Status:** IMPLEMENTED — issue, report lost, replacement, PDF; PLACEHOLDER — "Verify a Card"; Blood group, Graduates and the kin phone print as "—"; NOT IMPLEMENTED — collection recording, card verification.

### 3.53 Public verification

| Point | Content |
|---|---|
| Purpose | Every printed or downloadable artefact carries a QR or a code that opens a public page reading the University's own record. |
| Users / roles | Public (`/api/v1/verify/**`, `/api/v1/helpdesk/track` permit-all). |
| Navigation | `/verify` (payment form + camera Scanner), `/verify/receipt/{reference}?c=`, `/verify/exam`, `/verify/registration`, `/verify/results`, `/verify/report/{code}`, `/verify/putme/{token}`, `/verify/hostel/{ref}`, `/verify/document[/{key}]`, `/documents/d/{token}`, `/track`; the Documents office links "Public verification page". |
| Dashboard | None. |
| Main features | Nine checks; a shared card layout with a green "Genuine …" or red "Not verified" note and the footer "This page reads the University's register directly…". |
| Create / Edit / Delete | None. |
| View | The record's public fields (photographs as data URIs where the endpoint returns them). |
| Search | The key or code typed on `/verify` and `/verify/document`. |
| Filters | None. |
| Reports | Verification log on the documents register. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Document VALID / REVOKED / REPLACED / NOT FOUND / INVALID; others genuine / not verified. |
| Validation rules | Receipt, exam, registration and results need a SHA-256 check token; report by its code; PUTME by an opaque token; document by a 128-bit code or number; secure link by a 192-bit token with expiry and use limit; hostel by reference alone. |
| Security | Document verification throttled 40 / 15 min per IP; ticket tracking 12 / 15 min per IP and email; **no throttle** on the token-gated endpoints (the token stops enumeration) and **neither token nor throttle** on `/verify/hostel/{ref}`. |
| Audit trail | Document verifications and downloads logged (exempt tables); others unlogged. |
| Related modules | Receipts (§3.39), Results (§3.33), Registration (§3.13), Reports (§3.54), Admissions CBT (§3.17), Hostel (§3.47), Documents (§3.51), Help desk (§3.48). |
| Common errors | "Not verified" when the code or session does not match or nothing is published; "That QR is not a MOAUM verification code." |
| Troubleshooting | Type the reference and check code exactly as printed. |

**Status:** IMPLEMENTED (all nine routes); NOT IMPLEMENTED — identity-card verification, deferment-letter verification (`/verify/deferment` printed on the letter does not exist), PG offer-letter verification, rate limiting on the token-gated and hostel endpoints.

### 3.54 Reports and returns

| Point | Content |
|---|---|
| Purpose | The returns desk: twelve standard returns with a due register, each run as a branded printable document with an Excel download, a "Keep a copy" snapshot with a verification code, filing, and emailing with the PDF and workbook attached; the student and staff registers; trends. |
| Users / roles | `ENROLMENT_READERS` academic, registrar, dregistrar, records, dvc, vc, ict, admin, super, dean, facultyofficer, hod; `REVENUE_READERS` bursar, registrar, dregistrar, academic, audit, ict, admin, super, vc, dvc; `PG_READERS` + pgschool, pgsecretary; `STAFF_RATIO_READERS` + hrm; snapshots/due register `READERS` vc, dvc, registrar, dregistrar, academic, records, bursar, audit, deputyaudit, hrm, ict, admin, super, pgschool, pgsecretary (not dean, facultyofficer, hod); registers `READERS` + dean, facultyofficer, hod; returns cut to the Dean's faculty or the HOD's department. |
| Navigation | Reports → Reports & Returns `/reports`, Student Register `/reports/students`, Staff Register `/reports/staff` (seventeen offices); `/reports/{slug}/view`, `/reports/snapshots/{id}` from buttons. |
| Dashboard | Tiles Overdue / Due within 30 days / Kept copies / Filed; register tiles Matched / Active / Female–Male / Postgraduate (students) and Matched / Academic / Active / Female–Male (staff). |
| Main features | Due register (Return, Owner, Frequency, Last due, Next due, State, Run/Open); Registers; Kept copies; Standard reports; Trends; a return view with "Keep a copy", "Download Excel", "Print / Save as PDF"; kept copy with "Mark as filed" and "Email this return"; register filters, paging (100), "Download Excel (n rows)", "Print / Save as PDF" (5 000-row cap, PARTIAL beyond). |
| Create | `POST /reports/snapshots`; `…/{id}/file`; `…/{id}/email`. |
| View | Twelve returns: admissions, enrolment, registration, carryovers, staff-ratio, postgraduate, revenue, funding, expenditure, income-expenditure, students, staff. |
| Edit | None (filing once). |
| Delete / deactivate | None. |
| Search | Register search (students: name, matric, admission or JAMB number; staff: name, staff number or email). |
| Filters | Reporting session; register filters (Faculty, Department, Programme, Level, Sex, Status, Entry mode, Entry session / Faculty, Department, Rank, Category, Status, Office held). |
| Reports | This module. |
| Export | Crest-branded `.xlsx` per return (built in the browser); print-to-PDF; kept copies additionally a server-built PDF for email; `students-register-<date>.xlsx`, `staff-register-<date>.xlsx`. |
| Notifications | "<title> · <period> — Rev. Fr. Moses Orshio Adasu University" to each address typed (1–20), with attachments ≤ 15 MB. No due/overdue reminders. |
| Approval workflow | None. |
| Statuses | Due register ON_DEMAND / FILED / TAKEN / OVERDUE (14 days' grace) / DUE; snapshot filed or not. |
| Validation rules | Frequency MONTHLY (day 1–28) / PER_SEMESTER / PER_SESSION (1–3 dates) / ON_DEMAND; filing once (409 "This snapshot is already filed, or does not exist"); "Give at least one email address"; "At most twenty recipients at a time". |
| Security | Money figures stripped for non-money offices in statistics; scope cut by name matching. |
| Audit trail | `reports.snapshot` (write-once except filing), `reports.catalogue` attached. |
| Related modules | Statistics (§3.55); Public verification (§3.53 — `/verify/report/{code}`); every module the returns read. |
| Common errors | "Your office reads this return; the office that owns it keeps and files the copy."; an emailed return stays "queued" (no provider); PARTIAL on the printed register. |
| Troubleshooting | The owning office keeps the copy; configure the outbox; narrow filters or use Excel. |

**Status:** IMPLEMENTED; NOT IMPLEMENTED (by guard) — Keep a copy for dean/facultyofficer/hod; NOT IMPLEMENTED — due-return reminders; the client list of returns (`lib/report.ts`) must be kept in step with `reports.catalogue` by hand.

### 3.55 Student statistics

| Point | Content |
|---|---|
| Purpose | One engine (V257) every dashboard reads: students in study with their fee position and registration; drill-down to the rows behind any figure. |
| Users / roles | `READERS` registrar, dregistrar, bursar, academic, records, ict, admin, super, dvc, vc, pgschool, pgsecretary, provost, collegesecretary, financecontroller, dean, facultyofficer, hod, exams; amounts only for `MONEY` offices (bursar, financecontroller, registrar, dregistrar, super, admin, pgschool, pgsecretary, provost, collegesecretary, dvc, vc); PG offices see `is_pg`, CHS offices `is_chs`, faculty/department offices their unit. |
| Navigation | Overview → Student Statistics → `/stats` (fourteen offices); `/stats/students?which=` from any figure; the compact StatsPanel on dashboards. |
| Dashboard | Tiles All students / School fees paid / Course registered / Paid but not registered / Not paid / No charge stated / Not registered; donuts Payment status, Registration status; bars by faculty, department, programme, degree type. |
| Main features | Scope filter bar; actions Paid Not Registered / Not Paid / All Students; tables By faculty / department / programme / degree type with every cell a link; Quick actions; detail with server-side search and Figure select, 50 per page. |
| Create / Edit / Delete | None. |
| View | Detail row: S/N, Student + number + degree, Programme + dept + faculty, Level, Fees pill (Paid / Part payment / Not paid / No charge), [Payable, Paid, Outstanding], Last payment + reference, Registration pill, Registered date, Open → `/students/{id}`. |
| Search | Student ID, name, programme, department, faculty or payment reference. |
| Filters | session, semester, fac, dept, prog, level, status, degree. |
| Reports | The figures. |
| Export | Export Excel / Export PDF (branded, serial `MOAUM/STAT/…`, S/N first, names A–Z; every row fetched 500 at a time). |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | `pay_status` NO_CHARGE / FULLY_PAID / PART_PAYMENT / NOT_PAID; registered = SUBMITTED/APPROVED/LOCKED (UG), SUBMITTED/ENDORSED (PG) or College enrolment registered. |
| Validation rules | Population = ACTIVE, PROBATION, ADMITTED; summary cached 60 s per bound and filters. |
| Security | Amounts stripped server-side for non-money offices. |
| Audit trail | Read model (`reporting` schema, exempt). |
| Related modules | Finance (§3.36–37); Registration (§3.13); College (§3.35); Dashboards (§3.1). |
| Common errors | "No students found"; a figure stale by up to a minute. |
| Troubleshooting | Wait for the cache; check the scope bar. |

**Status:** IMPLEMENTED.

### 3.56 Platform status, readiness, migrations, release and data reset

| Point | Content |
|---|---|
| Purpose | What is actually true about the service (status, database, migration ledger), go-live gates, mail and SMS credentials (§3.3), the notice outbox (§3.3), the guarded data-reset actions, and the static framework pages. |
| Users / roles | `/platform/status` public; `/platform/migrations` ict, admin, super; `/platform/readiness` super, ict, admin, registrar, dregistrar, academic, bursar; reset/remove-demo super, ict. |
| Navigation | ict/super home → `/` (Platform dashboard); Administration → Data Migration `/migrations` (super), Release Pipeline `/release`, Cloud Readiness `/cloud`, Disaster Recovery `/disaster-recovery` (ict/super; §3.8); admin Overview → Go-Live Readiness `/readiness`; `/healthz`. |
| Dashboard | Tiles The service / The database / "2025/2026 admission settings" (hard-coded label) / Acting as; "What is actually true"; "The outbox"; course-structure coverage; "People and access"; Readiness tiles Ready / Blocking / To review / Total checks. |
| Main features | Migration ledger (Migration, Applied, By, Checksum); readiness gates (Applicant fee set, Admission policy in force, Session on the calendar, A semester is open, School-fee schedule set, Clearance scheme in force, Demo data removed, Exam-screened programmes set, Payment gateway configured, Email (SMTP) configured, SMS configured) with "Fix" links; Danger zone "Remove demo courses only…", "Remove demo data only…" (type `REMOVE DEMO`), "Reset ALL uploaded data…" (type `RESET` + reason). |
| Create / Edit | None beyond §3.3 settings. |
| Delete / deactivate | The three reset actions (recorded on the spine; no second approver). |
| View | Ledger; gates. |
| Search / Filters | Readiness `?session=` (`dddd/dddd`, defaults to 2026/2027). |
| Reports | None. |
| Export | None. |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | Gate Ready / Check / Blocking. |
| Validation rules | Reset words; a reason for a full reset; "a data reset is made by a person". |
| Security | `/platform/status` discloses commit, start time, migration count and latest filename; a typed word is the only guard on the resets. |
| Audit trail | Deletions attributed to the actor by the functions. |
| Related modules | Notices (§3.3); Governance/DR (§3.8); Calendar (§3.9); Fees (§3.36); Gateways (§3.38); Admissions (§3.17). |
| Common errors | Readiness "Blocking" rows; "type RESET to confirm clearing all uploaded data". |
| Troubleshooting | Follow each "Fix" link; "Session on the calendar" needs a CURRENT session under a minute. |

**Status:** IMPLEMENTED — status, ledger, readiness, resets; PLACEHOLDER — the legacy-migration text on `/migrations`, `/cloud`, `/release`, `/ethics`; hard-coded default session and admission-settings label.

### 3.57 Legacy data migration (records)

| Point | Content |
|---|---|
| Purpose | Bring the old portal's record over: student biography or core students, postgraduate students, course registration, past results (final under a legacy minute), PG registration/results/research, JAMB numbers, passport photos, and the migrated students' clearance. |
| Users / roles | The results controller's `MIGRATE` guard; the screen names "the ICT Directorate, the Examinations Officer, HODs and Records". |
| Navigation | Academic → Migrate from Old Portal → `/records/migration` (ict, records). |
| Dashboard | Result tiles per upload kind (created, updated, no student, skipped…). |
| Main features | Eleven segmented tabs (1 · Student biography (full), 1 · Students (core only), 1 · Postgraduate students, 2 · Course registration, 3 · Past results, PG · registration, PG · results, PG · research, 4 · JAMB numbers, 5 · Passport photos, 6 · Clearance); Download template; Session (fallback) and Semester (fallback); batch upload with progress; skipped rows download; passport upload matched by JAMB number in the filename; the migrated-clearance panel. |
| Create | `POST /api/v1/results/legacy/*`, `/student/students/migrated/clear`. |
| View | Counters and notes. |
| Edit / Delete | None; re-uploading updates rather than duplicates. |
| Search | None. |
| Filters | None. |
| Reports | None. |
| Export | Templates; "Download the skipped rows" / "Download the skipped numbers". |
| Notifications | None. |
| Approval workflow | None. |
| Statuses | None. |
| Validation rules | A matriculation number must be the University's own or a legacy old-portal number; order Students → Registration → Results; a result import creates the missing registration entry. |
| Security | Migrated students sign in with their number as both username and password and must choose a real one at first sign-in. |
| Audit trail | Every import is the officer's act; bulk clearance inserts run with the audit trigger disabled. |
| Related modules | Student records (§3.23); Results (§3.30); PG coursework/research (§3.20–21); Legacy fees (§3.40). |
| Common errors | "N rows had no valid matriculation number and were not uploaded"; "Your office may not migrate records." |
| Troubleshooting | Fix the numbers at source and re-upload (idempotent). |

**Status:** IMPLEMENTED (Migrations screen note about a legacy migration console remains a placeholder).

---

## 4 Screen-by-screen documentation

Every page in `frontend/src/app` is documented below, grouped by module. Each entry gives the page name (menu label or page title), the navigation path, the URL, the purpose, who can access it (the offices whose menus list it, and the API guard that actually decides), the layout, the fields where the page has a form, the actions with the endpoint each calls, what happens after each action, the messages the page shows, a security note and the screenshot that a later edition should carry. Conventions that apply to every page and are not repeated: every table is a `DTable` (client-side search above 8 rows, paging 10/25/50/100/All, a footer "Print" that prints the table with the University's name and the date); every write carries an `X-Reason` header whose text is also the success toast; an API refusal renders a `ProblemNotice` (title, detail, "What to do: remedy — office") and a red toast; no `page.tsx` redirects by office — rights are hidden client-side by the acting office and enforced by the API.

Route ids that are pure aliases are noted once and not repeated: `s/pay` and `s/receipt` resolve to `/student/fees`; `s/slip` resolves to `/student/results`; `t/sheet`, `t/bulk`, `t/scores` resolve to `/results/sheets`; `t/exams`/`t/examsession` to `/examinations/sessions`; `t/exception`/`t/cashdesk` to `/finance/exceptions`; `t/feesched`/`t/feesetup` to `/finance/fees`; `t/idcards`/`t/idlost` to `/credentials/idcards`; `t/pv`/`t/prepayment` to `/vouchers`; `t/matlist`/`t/matriculation` to `/matriculation`; `t/channels`/`t/notify` to `/notices`; `t/student`/`t/students` to `/students`; `t/review`/`t/chain` to `/results/chain`; `t/nelfund`/`t/nelstatus`/`t/nelmatch` to `/finance/nelfund`; `t/pgpanels`, `t/pgseminars`, `t/pgproposals`, `t/pgsupervision`, `t/pgtheses`, `t/pgresearch` to `/admissions/postgraduate/research`; `x/pending`/`x/submitted`/`x/projects` to `/examiner/projects`; `r/upload`/`t/lms` to `/lms`. `/student/transcript` is a redirect to `/student/documents?new=TRANSCRIPT`; `pg/summary` is a PDF route with no page.

### 4.1 Sign-in and account

#### 4.1.1 Sign in

```text
(public) → /login
```
**URL** `/login` · **Purpose** One door for staff, students, applicants and postgraduate applicants. · **Who** Public. · **Layout** Two columns: brand panel (crest, University name, static "12 faculties · 1 college · 1992 established") and the sign-in card.

| Field | Description | Required | Validation |
|---|---|---|---|
| Your number or email address | Staff number, matriculation/admission number, JAMB number, application number or email; a live hint names who it looks like | Yes | Shape decides the door (`api/auth/sign-in/route.ts`) |
| Password | Show/hide eye | Yes | — |

| Action | What it does | Endpoint |
|---|---|---|
| Sign in | Routes to the right door, sets `moaum_session` and `moaum_office`, goes home or to `/account/password` (`mustChange`) / `/student/profile?change=1` | `POST /api/auth/sign-in` → `/api/v1/auth/sign-in`, `/student-auth/sign-in`, `/applicant/sign-in` or `/pg/sign-in` |
| Sign in with the University's single sign-on | Only when SSO is configured | `/api/auth/sso/start` |
| Forgot your password? / First account / Post UTME Registration / Postgraduate application / Verify a payment or receipt | Links | `/login/forgot`, `/login/first`, `/apply`, `/pg/apply`, `/verify` |

**Messages** "Five failed attempts lock an account for fifteen minutes…" (footer); "That username and password do not match an account."; "This account is locked after repeated failures; try again after HH:MM."; "Single sign-on did not complete" (`?sso=`). · **Security** httpOnly session cookie; lockout 5/15 min; no rate limit; the matric-number hint regex predates V263 (a new-format number is labelled as a staff number but still routed correctly).

> **Screenshot Required:** Sign in — `/login` — the card with the identifier hint visible.

#### 4.1.2 Create the first account

```text
/login → First account → /login/first
```
**URL** `/login/first` · **Purpose** Bootstrap the first person once. · **Who** Public, guarded by the bootstrap secret. · **Layout** One form card.

| Field | Description | Required | Validation |
|---|---|---|---|
| Bootstrap secret | "The value of MOAUM_AUTH_HMAC_SECRET on the API service. It is checked, never stored here." | Yes | Must equal the secret; refused once accounts exist |
| Surname, Given names | — | Yes | — |
| Staff number | Optional | No | — |
| Username | "The staff number or an email address…" | Yes | ≥ 3 |
| Password | "At least ten characters" | Yes | ≥ 10, not the username |

| Action | What it does | Endpoint |
|---|---|---|
| Create and sign in | Creates the person with registrar, academic, ict and super; signs in as registrar; goes to `/people` | `POST /api/auth/bootstrap` (secret in `X-Bootstrap-Secret`) |

**Messages** "The bootstrap secret is not right."; "The portal already has accounts; the first one is made once." · **Security** One-time; afterwards grant offices from `/people`.

> **Screenshot Required:** Create the first account — `/login/first` — the empty form.

#### 4.1.3 Forgot password / Choose a new password

```text
/login → Forgot your password? → /login/forgot → (emailed link) → /login/reset?token=…
```
**URLs** `/login/forgot`, `/login/reset` · **Purpose** Self-service reset for staff, students, applicants and PG applicants. · **Who** Public. · **Layout** One field, one button; the reset page has two password fields.

| Field | Description | Required | Validation |
|---|---|---|---|
| Staff number, matriculation number, application number, email or JAMB number | The identifier | Yes | Resolved STAFF → STUDENT → APPLICANT → PGAPPLICANT |
| New password / Type it again | On `/login/reset` | Yes | ≥ 8; must match ("The two do not match.") |

| Action | What it does | Endpoint |
|---|---|---|
| Send the reset link | Always answers 202; queues email and SMS when an account matched | `POST /api/auth/forgot` |
| Save the new password | Consumes the token once, clears the lockout and `must_change` | `POST /api/auth/reset` |

**Messages** "If that names an account, a reset link is on its way"; "Your password has been changed"; "This link is incomplete"; "This reset link has expired or was already used." · **Security** Token hashed (SHA-256), one hour, single use; no rate limit; the reset minimum (8) is shorter than the staff policy (10).

> **Screenshot Required:** Forgot password — `/login/forgot` — the field and the green note after submission.

#### 4.1.4 Activate an examiner account

```text
(emailed invitation) → /login/activate?token=…
```
**URL** `/login/activate` · **Purpose** An invited external examiner chooses a password. · **Who** Public with a valid token. · **Layout** Invitation text ("Dear {name} ({institution}), the University invites you to serve as an External Examiner for {appointment}… Your username will be {email}.") and two password fields (≥ 10, not containing the email). · **Actions** Activate → `POST /api/v1/examiners/activate` (writes the credential, grants `extexaminer`, sets ACTIVE, emails the desk) → "Your examiner account is active" → Sign In. · **Messages** "This invitation link has expired or was already used." · **Security** 14-day, single-use token hash.

> **Screenshot Required:** Activate an examiner account — `/login/activate` — the invitation text and password fields.

#### 4.1.5 Your password

```text
(after a first sign-in with a Registry-set password) → /account/password
```
**URL** `/account/password` · **Purpose** Forced change of a first password. · **Who** Any signed-in staff person. · **Layout** Inside the Shell; a note "Choose a password of your own — The Registry set the one you signed in with, so it changes now…". · **Fields** Current password (required), New password (≥ 10, not the username), New password, again (must match). · **Actions** Change the password → `POST /api/auth/change-password` (`X-Reason: password changed by the person`) → continues to the page originally requested. · **Messages** `AUTH_PASSWORD_SHORT`, `AUTH_PASSWORD_IS_USERNAME`; current password mismatch. · **Security** Rewrites the credential with `must_change=false`.

> **Screenshot Required:** Your password — `/account/password` — the note and the three fields.

### 4.2 Home, dashboards and search

#### 4.2.1 Home (`/`)

```text
Overview → Dashboard (label varies by office) → /
```
**URL** `/` · **Purpose** Route to the office's home and render its dashboard (§1.3, §5). · **Who** Every signed-in person; each dashboard reads its own module's endpoints. · **Layout** A leading `Note` stating the one thing waiting, `Tiles`, panels with tables, a "desks" panel of links; the Platform dashboard also hosts the People shortcuts, the outbox and the Danger zone (§4.4.1). · **Actions** Links to the desks; on the Platform dashboard "+ New person", "+ Grant an office", "Open the people console", and the three reset actions (see §4.4.1). · **Messages** "Your Head-of-Department office is not tied to a department yet" / "Your Dean office is not tied to a faculty yet"; per-panel empty states. · **Security** Scope from the grant, the lecturer grant or the staff record.

> **Screenshot Required:** Home — `/` — the Registrar dashboard with the "Registry business" table.

#### 4.2.2 Administrator Dashboard

```text
Overview → Administrator Dashboard → /admin
```
**URL** `/admin` · **Purpose** The institutional read model with a scope re-cut. · **Who** admin (menu); `/reporting/overview` `MANAGEMENT`. · **Layout** Scope button row (The University / each faculty); tiles Students, Result sets past Senate, Collected this session, Fees outstanding; "Academic pipeline" donut with links "Chase the chain" / "To Senate" / "Unraised sheets"; "Money" table (Ledger / Chase / Report / Reconcile links); "By faculty" bars. · **Actions** Links only. · **Security** No scope cut on the endpoint.

> **Screenshot Required:** Administrator Dashboard — `/admin` — scope row and the Academic pipeline donut.

#### 4.2.3 Institutional Overview

```text
Overview → Institutional Overview → /overview
```
**URL** `/overview?session=&sem=` · **Purpose** Where every result set stands, students by level and faculty, the semester week by week, the grade spread. · **Who** admin, dvc, registrar, vc (menu); `MANAGEMENT`. · **Layout** PeriodPicker; StatsPanel; tiles Students on the register (→ `/reports/students`), Result sets expected, Past Senate (%), Never submitted; tiles Returns overdue / Returns due within 30 days; donuts "Where the n result sets stand", "Students by level"; stacked bars "Results by faculty" with a red note naming the faculty furthest behind; table "Results by faculty, in figures"; line chart "The semester week by week"; bars "Students by faculty"; grade spread A–F with a note when F ≥ 15 %. · **Actions** Period picker; links. · **Messages** Per panel, e.g. "No score sheet exists for … yet".

> **Screenshot Required:** Institutional Overview — `/overview` — the two donuts and the results-by-faculty bars.

#### 4.2.4 Search

```text
Overview → Search → /search   (or the top-bar "Search records ⌘/")
```
**URL** `/search?q=&kind=` · **Purpose** Find a student, staff member, course or credential. · **Who** Every staff menu; `/api/v1/student/search` refuses provost, collegesecretary, financecontroller, mbbscoordinator, pgschool, pgsecretary, services, siwes, ictagent, deputyaudit. · **Layout** Search box (placeholder "Matriculation number, name, staff number, course code or verification code"), kind tabs with counts, a no-query state with "What you can search for" and "Recent searches", a red note "Every search for a person is recorded against your account", an "Exact match on {identifier}" note with "Open {name}", one panel per kind (Identifier, Name, Detail, Status, Action). · **Actions** Search → `GET /student/search?q=`; Open (student/staff modal); course "Open" and credential "Verify" are disabled. · **Messages** Disabled titles "The course screens are not on the portal yet" / "Verification is not on the portal yet". · **Security** Each search written to `people.search_log`.

> **Screenshot Required:** Search — `/search?q=` — results with the kind tabs and an exact-match note.

### 4.3 Identity, accounts and the "Me" pages

#### 4.3.1 Users & roles

```text
Administration → Users & Roles → /people
```
**URL** `/people` (`?q=`, `?new=person|grant`) · **Purpose** People, credentials and office grants. · **Who** super, ict, admin (menu); `READERS` registrar, dregistrar, hrm, ict, admin, super, audit; writes per §3.5. · **Layout** Red note "A role is granted by the Registrar, recorded here, and reviewed"; tiles Accounts / Staff accounts / Holding two offices / Grants expiring in 30 days; panel "People on the register" with "Find a person"; panel "Staff accounts and the offices they hold".

| Field (modal) | Description | Required | Validation |
|---|---|---|---|
| New person: Surname, Given names | — | Yes | — |
| Staff number | "Optional; the number the University issued" (`MOAUM/STF/`) | No | Unique (409) |
| Email / Phone | "Where a password reset and notices are sent" / "for SMS notices" | No | — |
| Grant: Office | From `GET /iam/offices`; presets "Bounded to" | Yes | In `ref.office` |
| Which one | "The faculty, department, programme or course code; blank for the University or the platform" | Per scope kind | MBBS Coordinator must be a level 200–600 |
| From / To | "An acting grant must carry one." | From | `valid_to ≥ valid_from` |
| Authority for the grant | Placeholder "Registrar, memo REG/2026/318" | Yes | Non-blank |
| Credential: Username | "The staff number or an email address" | Yes | 3–200, unique |
| First password | — | Yes | ≥ 10 |
| End: Ended with effect from / Reason, as it will read in the log | Today when blank / required | Reason | — |

| Action | What it does | Endpoint |
|---|---|---|
| + New person | Creates the person | `POST /iam/persons` |
| Contact | Sets email/phone | `PUT /iam/persons/{id}/contact` |
| Create account / Reset password | Sets or resets the credential with `must_change` | `PUT /iam/persons/{id}/credential` |
| Grant an office / + Grant an office | Dated grant under an instrument | `POST /iam/persons/{id}/office-assignments` |
| End | Ends a grant | `POST /iam/persons/{id}/office-assignments/{grant}/end` |

**Workflow** A grant takes effect at the person's next sign-in. · **Messages** "Person created"; "<office> granted under <instrument>"; "Account created by the Registry" / "Password reset by the Registry"; "An office is held under a letter or minute; none was given."; "'x' already signs somebody else in." · **Security** Any grantor may grant any office; the first password is told out of band.

> **Screenshot Required:** Users & roles — `/people` — the two panels and the Grant an office modal.

#### 4.3.2 Upload Lecturers

```text
Staff → Upload Lecturers → /people/lecturers
```
**URL** `/people/lecturers` · **Purpose** Bulk onboarding of teaching staff (person + sign-in + lecturer office + establishment record). · **Who** super, ict, admin (menu); registrar, dregistrar also allowed. · **Layout** RoleLine "Onboarding teaching staff"; info note; "Download template" (PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONUASS); file button; progress "Onboarding n of m…"; result tiles New staff / Sign-ins issued / Department grants / Records kept; panel "Teaching staff on record" (search, checkboxes, Add staff, Delete selected (n), Edit modal: PNO locked, Department, Surname, Given names, Sex, Present rank, Phone, CONUASS, Email; pills Active / First password set / Issued / No sign-in; first 500 rows). · **Actions** Upload teaching staff (.xlsx) → chunks of 25 to `POST /iam/lecturers/import`; Add staff → same; Edit → `PUT /iam/lecturers/{id}`; Delete selected → `POST /iam/lecturers/delete`. · **Messages** "That file needs PNO, Full Names and Department columns."; "Create these departments first, then re-upload: …". · **Security** Username and first password `P<PNO>` with `must_change`.

> **Screenshot Required:** Upload Lecturers — `/people/lecturers` — result tiles after an upload.

#### 4.3.3 Non-Academic Staff

```text
Staff → Upload Non-Academic Staff → /people/staff
```
**URL** `/people/staff` · **Purpose** Load the nominal roll into the unit register; no sign-ins issued. · **Who** super, ict, admin, registrar, dregistrar, hrm. · **Layout** RoleLine; "Download Template" (PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONTISS); "Check a File (.xlsx)" (dry run); "Load All N Rows" / "Load the N Placed Rows"; result tiles; tabs "Non-Academic Staff" (Staff id, Name, Placed in, As the roll spelt it, Rank, Scale, First appointed; ≤ 500) and "The Unit Register" (Unit, Kind, Under, Campus, Staff, Spellings known). · **Actions** Check → `POST /iam/staff/import {dryRun:true}` in chunks of 100; Load → the same without dry run. · **Messages** "{created} staff added · {existing} already on record"; "Not placed, as spelt in the sheet: …"; "This desk is for the Registry, Human Resources and the Directorate of ICT". · **Security** Creates person + `hrm.staff_record`, never an employment.

> **Screenshot Required:** Non-Academic Staff — `/people/staff` — dry-run result with "Not placed" spellings.

#### 4.3.4 Leave & Payslip (`/me`)

```text
Me → Leave & Payslip → /me
```
**URL** `/me` · **Purpose** You as an employee: record, offices held, payslips, leave. · **Who** Every staff office; `/staff/me`, `/me/payslips`, `/me/leave` any authenticated. · **Layout** Tiles Leave taken (30 − balance; hard-coded 30) / Leave remaining / Last payslip / Appraisal ("—", "Staff module, not yet on the portal"); panel "My record" (Staff number, Office, Unit, Appointment "—", Grade, Next increment "—"; buttons "My ID card (PDF)", "Edit my profile"); "Payslips" (Month, Gross, Pension, PAYE, Net, Stage); "Offices held" (Office, Scope, Instrument, From, Until); "Leave" panel.

| Field | Description | Required | Validation |
|---|---|---|---|
| Type | "{name} (max {n}d[, unpaid])", default ANNUAL | Yes | Days ≤ the type's max |
| From / To | Dates | Yes | No client check that To ≥ From |
| Cover | "Who takes your duties, if required" | No | ≤ 200 |
| Note | Optional | No | ≤ 600 |

| Action | What it does | Endpoint |
|---|---|---|
| Request leave | Opens a REQUESTED request | `POST /me/leave` |
| Cancel | Cancels a REQUESTED/APPROVED request (confirm) | `POST /me/leave/{id}/cancel` |
| My ID card (PDF) | Opens the staff card | `/staff/idcard/pdf` |

**Messages** "Your leave request is with your office."; "Leave is for serving staff"; "You are signed in, but the Registry has no record of you yet"; "No payslip yet". · **Security** Only APPROVED/PAID runs show.

> **Screenshot Required:** Leave & Payslip — `/me` — tiles, My record and the Leave panel.

#### 4.3.5 My Profile

```text
Me → My Profile → /me/profile   (lecturer menu; "Edit my profile" from /me)
```
**URL** `/me/profile` · **Purpose** The staff member's own academic profile and photograph. · **Who** Any authenticated (actor = token subject). · **Layout** Panels Photograph (JPEG/PNG ≤ 2 MB), Who you are (Email, Phone contact, Department, Faculty, Current responsibility, ORCID), Research (Google Scholar profile, Areas of research interest, Master's / PhD candidates graduated), Research output (Publications, Grants obtained, Patents, Innovations — one per line), Engagement and recognition (collaborations, conferences, assignments, achievements, contributions). · **Actions** Upload/Replace photograph → `PUT /staff/profile/photo`; Save profile → `PUT /staff/profile` (whole upsert). · **Messages** "Photograph updated."; "A photograph is a JPEG or PNG image."; "Profile updated"; "Every field is optional. What you leave blank is saved as empty, not guessed." · **Security** No format check on email/ORCID/URL beyond the DB email regex.

> **Screenshot Required:** My Profile — `/me/profile` — the Photograph and Who you are panels.

#### 4.3.6 Notifications (`/me/notices`)

```text
Overview → Notifications → /me/notices   (lecturer menu; other offices by URL)
```
**URL** `/me/notices` · **Purpose** The notices sent to the signed-in person. · **Who** Any authenticated non-student. · **Layout** Tiles All / This week / By email / Not delivered; filters Search and Channel (Email and SMS / Email / SMS); expandable notices with pills Delivered / Waiting to send / Not delivered. · **Actions** Read only (`GET /me/notices?limit=200`).

> **Screenshot Required:** Notifications — `/me/notices` — the list with a notice expanded.

#### 4.3.7 Course History and My Courses & Timetable

```text
History → Course History → /me/courses ; Academic → My Courses & Timetable → /me/teaching
```
**URLs** `/me/courses`, `/me/teaching?session=` · **Purpose** Every course allocated to the person (with class size and where its results reached) and this session's teaching. · **Who** lecturer (both), hod (`/me/teaching`); `GET /allocation/history?scope=me`, `GET /me/teaching` (any authenticated). · **Layout** Course History: PageHead with actions "This Session's Timetable" and "Score Sheet History"; tiles; filters Session, Semester, Level, Role; panel "Courses" with row links "Students" (class list) and "Sheets" (score sheet history); note "A past class is read as it stood". My Teaching: Session field; tiles; panel "Your teaching this session". · **Messages** "Nothing has been allocated to you yet"; "Nothing is allocated to you for {session}".

> **Screenshot Required:** Course History — `/me/courses` — the filters and the Courses table.

#### 4.3.8 My SIWES Students

```text
Students → My SIWES Students → /me/siwes
```
**URL** `/me/siwes` · **Purpose** The supervisor's own SIWES students and their assessment out of 40. · **Who** lecturer, siwes; `GET /siwes/mine` any authenticated (ownership on write). · **Layout** Table of assigned students with an Assessment /40 input. · **Actions** Save → `PUT /siwes/mine/students/{id}/score` (a changed mark asks why). · **Messages** `SIWES_NOT_YOUR_STUDENT`; "The SIWES score sheet is not open yet."

> **Screenshot Required:** My SIWES Students — `/me/siwes` — the table with one mark entered.

#### 4.3.9 My Support Tickets, Submit a ticket, A ticket

```text
Me → ICT Support Tickets → /tickets → Submit a New Ticket → /tickets/new ; row → /tickets/{id}
```
**URLs** `/tickets`, `/tickets/new`, `/tickets/{id}` · **Purpose** The requester's tickets. · **Who** Every staff office and students (student shell for students); `REQUESTER` = any signed-in non-applicant with a person record. · **Layout** `/tickets`: tiles Open / Awaiting your confirmation / Closed / All; green notice "N ticket(s) have been marked as resolved"; table Ticket, Subject ("With {agent}"), Category, Status, Priority, Raised, Last updated; actions Submit a New Ticket, Track a Ticket. `/tickets/new`: panels "Who you are" (read-only from the account; Email required; Phone), "What it is about" (Category with "Handled as {priority}", dynamic fields), "The problem" (Subject ≤ 200, Description ≤ 8000, Attachments PDF/JPEG/PNG ≤ 5 MB, up to five). `/tickets/{id}`: header pills; state notice; panels What you reported, Your details, The conversation (textarea "Add an update for the desk", file attach), Attachments, History.

| Action | What it does | Endpoint |
|---|---|---|
| Submit the Ticket | Creates the ticket, then uploads each file | `POST /helpdesk/my/tickets`, `POST …/{id}/attachments` |
| Confirm Resolution | RESOLVED → CLOSED | `POST …/{id}/confirm` |
| Reopen Ticket | RESOLVED → REOPENED (reason ≥ 5) | `POST …/{id}/reopen` |
| Close This Ticket | Withdraws while open | `POST …/{id}/close` |
| Add an update | Comment the desk sees | `POST …/{id}/comments` |

**Messages** "Your ticket number is TICK-…"; "You have not raised a ticket yet…"; "A closed ticket takes no more updates"; "ten tickets are open already". · **Security** Internal notes and internal files never reach the requester.

> **Screenshot Required:** Submit a ticket — `/tickets/new` — a category chosen with its dynamic fields.

### 4.4 Platform and administration

#### 4.4.1 Platform dashboard (`/` for ict and super)

```text
Overview → Platform & Integrations (ict) / Setup Console (super) → /
```
**URL** `/` · **Purpose** What is actually true about the service; people shortcuts; the outbox; data reset. · **Who** ict, super. · **Layout** StatsPanel; course-structure coverage tiles and panels; "People and access" (counts, "+ New person", "+ Grant an office", "Open the people console"); tiles The service (up/down, commit), The database (reachable, migrations applied, latest), "2025/2026 admission settings" (hard-coded label), Acting as; panel "What is actually true" (Service, Started, Latest migration, Actor, Acting office, Offices held; `API_URL`); "The outbox" (providers wired?, waiting/sent/failed, recent 50); "Danger zone — reset uploaded data" (super, ict).

| Action | What it does | Endpoint |
|---|---|---|
| Remove demo courses only… (type `REMOVE DEMO`) | Deletes DMO-DMC courses | `POST /platform/remove-demo-courses` |
| Remove demo data only… (type `REMOVE DEMO`) | Deletes demo students and accounts | `POST /platform/remove-demo` |
| Reset ALL uploaded data… (type `RESET` + reason) | `platform.reset_operational_data` | `POST /platform/reset-data` |

**Messages** "type RESET to confirm clearing all uploaded data"; "a data reset is made by a person". · **Security** Typed word only; no second approver; every deletion attributed on the spine.

> **Screenshot Required:** Platform dashboard — `/` (as Director of ICT) — "What is actually true" and the outbox panel.

#### 4.4.2 Data Migration

```text
Administration → Data Migration → /migrations
```
**URL** `/migrations` · **Purpose** The migration ledger. · **Who** super (menu); ict, admin, super (guard). · **Layout** Tiles Migrations applied / Latest / Running commit / Started; table Migration, Applied, By, Checksum (first 12 hex); a note that a legacy data migration "is not shown here because none has been run" (placeholder). · **Actions** None.

> **Screenshot Required:** Data Migration — `/migrations` — tiles and the ledger table.

#### 4.4.3 Go-Live Readiness

```text
Overview → Go-Live Readiness → /readiness
```
**URL** `/readiness?session=` · **Purpose** Gates before go-live. · **Who** admin (menu); super, ict, admin, registrar, dregistrar, academic, bursar (guard). · **Layout** Session select; tiles Ready / Blocking / To review / Total checks; the gate list (Applicant fee set, Admission policy in force, Session on the calendar, A semester is open, School-fee schedule set, Clearance scheme in force, Demo data removed, Exam-screened programmes set, Payment gateway configured, Email (SMTP) configured, SMS configured) with pills Ready / Check / Blocking and a "Fix" link. · **Actions** Fix links. · **Security** Session must be `dddd/dddd` else 2026/2027.

> **Screenshot Required:** Go-Live Readiness — `/readiness` — the gate list with mixed pills.

#### 4.4.4 Mail Server

```text
Administration → Mail Server → /platform/mail
```
**URL** `/platform/mail` · **Purpose** SMTP/IMAP/POP account for outgoing notices. · **Who** ict, admin (menu); `KEEPERS` ict, admin, super.

| Field | Description | Required | Validation |
|---|---|---|---|
| SMTP / IMAP / POP Server, Port, Encryption | Defaults smtp.office365.com 587 STARTTLS, outlook.office365.com 993 SSL, 995 SSL | SMTP for sending | Port 1–65535; STARTTLS/SSL/NONE |
| Username | "The full email address" | Yes | — |
| From address | — | No | — |
| Password or app password | Pasted once | For sending | Needs `MOAUM_CONFIG_KEY` |

| Action | What it does | Endpoint |
|---|---|---|
| Save the settings | Encrypts and stores | `PUT /platform/mail` |
| Clear the password | Removes it | `POST /platform/mail/clear-password` |

**Messages** Pill "Password set" / "No password"; red "No passphrase to encrypt the password with — Set MOAUM_CONFIG_KEY…"; the footer note about SMTP "not yet enabled" is stale. · **Security** Decrypted only inside the dispatcher.

> **Screenshot Required:** Mail Server — `/platform/mail` — the three server panels and the account panel.

#### 4.4.5 SMS Gateway

```text
Administration → SMS Gateway → /platform/sms
```
**URL** `/platform/sms` · **Purpose** eBulkSMS credentials. · **Who** ict, admin (menu); `KEEPERS`. · **Fields** Username; Sender ID (≤ 11); API key (pasted once); checkbox "Send SMS notices through eBulkSMS". · **Actions** Save the settings → `PUT /platform/sms`; Clear the API key. · **Messages** `SMS_NO_CONFIG_KEY`.

> **Screenshot Required:** SMS Gateway — `/platform/sms` — the form with the enable checkbox.

#### 4.4.6 Notifications / Notification Channels (the outbox)

```text
Administration → Notifications (ict) / Notification Channels (super) → /notices
```
**URL** `/notices` · **Purpose** The outbox and its providers. · **Who** ict, super (menu); read ict, admin, super, registrar; retry ict, admin, super. · **Layout** Note "No provider is wired, so nothing is being sent" when neither relay URL is set (it ignores SMTP/eBulkSMS settings); tiles Waiting / Sent today / Failed / Sent, all time; panel "Providers"; "The outbox" (When, To, Notice, Channel, Attempts, State Sent / Failed + error + Requeue / Queued). · **Actions** Requeue; "Put all n failed back in the queue" → `POST /platform/notices/retry-failed`. · **Security** Bodies visible to four offices.

> **Screenshot Required:** Notifications — `/notices` — tiles and the outbox table.

#### 4.4.7 Integrations / API Management

```text
Administration → Integrations (super) / API Management (ict) → /api-keys
```
**URL** `/api-keys` · **Purpose** Consumer and key register. · **Who** ict, super (menu); `OPERATORS` ict, admin, super. · **Layout** Note "Every client is named, scoped and rate-limited, and no key lives longer than a year" (aspirational); tiles Consumers / Live keys / Due for rotation; one panel per consumer with a key table. · **Fields** Client name, Owner, Scopes ("Space-separated, e.g. catalogue:read verify:read"), Daily quota (optional); "Days until this key expires (max 366):" prompt (default 365). · **Actions** + Register a consumer → `POST /apimgmt/consumers`; Issue a key → `POST /consumers/{id}/keys` (modal "The key, shown once"); Revoke → `POST /keys/{id}/revoke`; Deprecate → `POST /consumers/{id}/deprecate`. · **Messages** "No consumer is registered…"; "No key issued yet."; "no active consumer to issue a key to". · **Security** Nothing authenticates by these keys.

> **Screenshot Required:** Integrations — `/api-keys` — a consumer panel with the one-time key modal.

#### 4.4.8 Audit Trail / Audit Log

```text
Administration → Audit Trail / Audit Log → /audit
```
**URL** `/audit?action=&office=` · **Purpose** Read the spine and sign-in events. · **Who** super, ict, admin, vc (work); registrar (menu, refused). · **Layout** Note "The audit trail cannot be edited through the application"; tiles Entries on the record / Today / Actors today / Refusals today; filters Domain and Acting office; table When, Actor, Action, Subject, Reason; "Most recent n". · **Actions** Filter (navigates with query parameters). · **Messages** "No entry matches this filter."; the closing note that refused writes are on the trail is not how the spine works. · **Security** Before/after state not shown.

> **Screenshot Required:** Audit Trail — `/audit` — tiles, the two filters and the entries table.

#### 4.4.9 Security / Security Posture

```text
Administration → Security / Security Posture → /security
```
**URL** `/security` · **Purpose** The spine's health and sign-in defence. · **Who** super, ict, admin, vc (menu); guard adds audit, deputyaudit, security, registrar, dvc. · **Layout** Note on unattached tables; tiles Audit entries (shard count), Unattached tables, Failed sign-ins 7 days, Last audit entry; panel "The audit spine" (its "verified nightly" text is unfounded); "Sign-in defence" (Signed in / Wrong password / Unknown username / Locked out); "Accounts drawing failed attempts". · **Actions** None.

> **Screenshot Required:** Security posture — `/security` — tiles and the sign-in defence table.

#### 4.4.10 Data Governance

```text
Administration → Governance / Data Governance → /governance
```
**URL** `/governance` · **Purpose** NDPA register, DPIAs, DSRs. · **Who** super, ict, admin, registrar, vc (menu); readers/writers per §3.8. · **Layout** RoleLine; tiles Processing activities / DPIAs outstanding / Open subject requests / Overdue requests; "Record of processing activities" (Activity, Lawful basis, Sensitive, Retention, DPIA pill, "Mark done"); "Data-subject rights requests" (Reference, Type, Requester, Due, Status, Start / Complete); "Log a data-subject request".

| Field | Description | Required | Validation |
|---|---|---|---|
| Type | Access / Rectification / Erasure / Portability / Objection | Yes | CHECK |
| Requester | — | Yes | ≤ 200 |
| Due | "Defaults to 30 days" | No | Date |

| Action | What it does | Endpoint |
|---|---|---|
| Mark done | DPIA → COMPLETE | `POST /governance/register/{id}/dpia` |
| Log the request | `DSR-YYYY-NNNN` | `POST /governance/dsr` |
| Start / Complete | RECEIVED → IN_PROGRESS → COMPLETED | `POST /governance/dsr/{id}/advance` |

**Messages** "<ref> logged"; "The register is empty."; "No data-subject request has been logged…". · **Security** REFUSED unreachable; no activity add/edit.

> **Screenshot Required:** Data Governance — `/governance` — the three panels.

#### 4.4.11 Disaster Recovery / Backups & Recovery

```text
Administration → Disaster Recovery / Backups & Recovery → /disaster-recovery
```
**URL** `/disaster-recovery` · **Purpose** The DR drill log against stated objectives. · **Who** ict, super. · **Layout** Note "A backup that has never been restored is not a backup … Continuous backup telemetry is not wired into the portal yet"; tiles Last restore verification / Last full DR drill / Drills on record / Failed drills; static "Recovery objectives" table (RPO ≤ 15 min · 5 min for results & finance; RTO ≤ 4 hours; nightly restore verification; daily off-site replication; twice-yearly full drill — typed in the TSX); "Drill log"; form "Record a drill" (Drill kind, Run on, Outcome Passed/Partial/Failed, RPO achieved, RTO achieved, Note). · **Actions** Record a drill → `POST /governance/dr`. · **Security** Objectives are not measured.

> **Screenshot Required:** Disaster recovery — `/disaster-recovery` — the objectives table and the drill form.

#### 4.4.12 Cloud Readiness, Release Pipeline, Ethics

```text
Administration → Cloud Readiness → /cloud ; Release Pipeline → /release ; (no menu) /ethics
```
**URLs** `/cloud`, `/release`, `/ethics` · **Purpose** Explanatory framework pages. · **Who** ict (menu; `/ethics` by URL); any signed-in person (they call only `/iam/me`). · **Layout** Static notes and bullet lists; each says it is "not wired to live … telemetry", "does not surface its own live build or deploy status", "describes the process rather than showing counts"; `/ethics` says "A live application queue and a populated repository arrive with the research-administration module". · **Actions** None. **Status** PLACEHOLDER.

> **Screenshot Required:** Release Pipeline — `/release` — the static page, to show it carries no live figures.

#### 4.4.13 Revenue & Student Income, Staff Movements (audit), Assets Register

```text
Finance → Revenue & Student Income → /audit/revenue ; Staff → Staff Movements → /audit/staff ; Finance → Assets Register → /audit/assets
```
**URLs** `/audit/revenue?session=`, `/audit/staff`, `/audit/assets` · **Purpose** The Internal Audit directorate's read-only desks. · **Who** audit (menu); the pages read `/finance/bursary`, `/reports/revenue`, `/payroll/staff`, `/payroll/runs`, `/stores/assets`. · **Layout** Revenue: tiles Fees collected / Confirmed today / Still owed / Open exceptions and "Revenue by category" (default session hard-coded 2026/2027). Staff: note "The roll and the payroll, read together"; tiles On the establishment / Academic / Monthly gross / Last payroll paid; panels "Pay runs" (Month, Staff, Gross, Deductions, Net, Stage, Approved by) and "Establishment" — titled "Staff movements", which does not match its content. Assets: headline note on assets not verified within a year; tiles Assets on the register / Book value / Never verified / Overdue verification; "Fixed-asset register" (Tag, Asset, Location, Cost, Condition, Last verified). · **Actions** None (the verify endpoint exists but this page has no button).

> **Screenshot Required:** Assets Register — `/audit/assets` — the register with a "Never" in red.

### 4.5 Calendar, structure, catalogue and allocation

#### 4.5.1 Session & Semester Setup

```text
Academic → Session & Semester Setup → /calendar
```
**URL** `/calendar?session=YYYY/YYYY` · **Purpose** Sessions, semester windows, level unit limits, roll-over, enrol-all. · **Who** academic, super (menu); `WRITERS` academic, registrar, dregistrar, super, ict; read any. · **Layout** Panels "Roll the register into a new session", "Match the loaded cohort to this session", info note, tiles Current session / Current semester / Registration / Score sheets due, "Academic sessions" (+ New session), "Semesters of {session}" (+ New semester), pointer "Open the examination session", "Levels and unit limits" (+ New level).

| Field (modals) | Description | Required | Validation |
|---|---|---|---|
| Session | Locked on edit; placeholder `2027/2028` | Yes | `dddd/dddd` ("The session has to be named as the University names one") |
| Opens / Closes | Dates | Yes | `ends_on > starts_on`; no overlap |
| Semesters | "2" / "3 (Summer semester)" | Yes | 1–3 |
| Senate minute | Placeholder `SEN/2027/…` | For CURRENT | Non-blank |
| State | Planned / Current / Closed | Yes | One CURRENT |
| Semester windows: Lectures from/to, Registration opens/closes, Late registration closes, Examinations from/to, Score sheets due, Result query window | Hints explain each gate | — | Date-order CHECKs |
| Level, Applies to, Minimum/Maximum units, Maximum units on probation, Carryover counts, Senate minute | Level select 100–600 | — | `max ≥ min ≥ 0` |

| Action | What it does | Endpoint |
|---|---|---|
| Roll into {session} | Promotes continuing students (word ROLLOVER + reason) | `POST /calendar/sessions/{s}/roll-over` |
| Enrol all into {session} | Backfills enrolments | `POST …/enrol-all` |
| Save the change | Upserts; State=Current also makes current | `PUT /calendar/sessions/{s}` (+ `POST …/make-current`) |
| End this session | Closes with a reason | `POST …/close` |
| Edit windows / Save | Semester upsert | `PUT …/semesters/{n}` |
| Edit level / Save | Level limit upsert | `PUT /calendar/levels/{level}` |

**Messages** "n continuing students promoted…"; "n students enrolled … · already were · eligible"; "A session stays planned until its Senate minute is recorded against it, and none was given." · **Security** Every change on the spine with the acting office.

> **Screenshot Required:** Session & semester setup — `/calendar` — the sessions table and the Edit session modal.

#### 4.5.2 Upload or Create Faculties / Departments / Programmes

```text
Academic → Upload or Create Faculties → /structure/faculties ; Departments → /structure/departments ; Programmes → /structure/programmes
```
**URLs** `/structure/faculties`, `/structure/departments`, `/structure/programmes` · **Purpose** Maintain the reference structure. · **Who** ict (menu and API). · **Layout** RoleLine; Add/Edit form; "Download template"; upload button; table with edit and delete icons; "Download Excel" / "Download PDF".

| Field | Description | Required | Validation |
|---|---|---|---|
| Code | Locked when editing | Yes | Programme `^C[0-9]{5}$` |
| Name | — | Yes | — |
| Faculty (departments, programmes) | Code or name / select | Yes | Must exist |
| Department (programmes) | "blank = the faculty" | No | — |
| Category (programmes) | UNDER GRADUATE / POST GRADUATE | Yes | — |
| Minimum score (programmes) | — | No | — |

| Action | What it does | Endpoint |
|---|---|---|
| Save | Upsert | `POST /catalogue/faculties|departments|programmes` |
| Upload (.xlsx / .csv) | Bulk import | `…/import` |
| Delete | Only when empty | `DELETE …/{code}` |
| Archive / Restore (programmes) | Keeps the code | `POST /programmes/{code}/archive` |
| Download Excel / PDF | Branded, serials FAC / DEP / PRG | — |

**Messages** "N faculties saved · M rows had no name"; "still has N programme(s)…"; "This desk is for the Directorate of ICT…". 

> **Screenshot Required:** Programmes — `/structure/programmes` — the form and the table with an archived pill.

#### 4.5.3 Upload or Create Courses (course structure upload)

```text
Academic → Upload or Create Courses → /catalogue/upload
```
**URL** `/catalogue/upload` · **Purpose** Load a programme's course structure from a CCMAS .docx or an .xlsx; open course registration; export the catalogue. · **Who** ict (menu; the note still names HODs). · **Layout** Programme (searchable), Curriculum select (CCMAS — MOAU cohorts / CCMAS — BSU cohort / BMAS / CCMAS any cohort), "Download template" (Course Code, Course Title, Units, Status, Level, Semester, Lecture Hours, Practical Hours), "View loaded courses", "Choose the course document (.docx or .xlsx)", preview (Courses read / Levels / With a code the rule rejects), "Load N courses"; panel "Open course registration for a session" (Session, Semester); "All courses — Excel/PDF". · **Actions** Load → one `POST /catalogue/import` per programme+curriculum group; Open registration → `POST /catalogue/open-registration`; exports (serials CAT, CRS). · **Messages** "N courses opened for …"; held-back programmes listed with "Download the list"; "no programme is coded or named X". · **Security** Structure upload ICT-only; open-registration bulk insert runs with the audit trigger disabled.

> **Screenshot Required:** Upload or Create Courses — `/catalogue/upload` — the preview panel after a file is chosen.

#### 4.5.4 Department Courses

```text
Academic → Department Courses → /catalogue
```
**URL** `/catalogue?dept=` · **Purpose** A department's courses: create, make live, end, restore, tag, split, duplicates. · **Who** hod (menu, own department); `OWNERS`. · **Layout** Department picker (fixed for an HOD); filters Level / Semester / Kind / Programme; "Make N Live"; "+ New course"; tiles Courses owned / Live / Awaiting approval / Live, no lecturer; "Duplicate courses" panel; bulk buttons "Set to CCMAS/BMAS", "CA 40 / Exam 60", "CA 30 / Exam 70"; table Code, Title (binding pills or red "Not bound to any programme — no student sees it at registration"), Units, Semester, Level, Kind, Curriculum select, CA / Exam select, Lecturer, State, Make live / End / Restore.

| Field (New course) | Description | Required | Validation |
|---|---|---|---|
| Code | "Three letters, a space, three digits — e.g. CSC 311" | Yes | `^[A-Z]{3}\s*[0-9]{3}$`, unique |
| Units | — | Yes | 0–12 |
| Title | — | Yes | Non-blank |
| Level, Semester, Kind | 100–600; First/Second; Core Courses / Required / Elective / GST | Yes | — |

| Action | What it does | Endpoint |
|---|---|---|
| Create | BOARD state; "… created — at the Faculty Board" | `POST /catalogue/courses` |
| Make live / End / Restore | State changes (live creates the current offering when bound) | `/courses/{code}/live`, `/end`, `/restore` |
| Make N Live | All BOARD/SENATE of the department | `/courses/live-all?dept` |
| End N duplicate courses | Keeps the least messy code | `/duplicates/end?dept` |
| Curriculum / Split (row or bulk) | Tags | `/courses/{code}/curriculum`, `/split`, `/curriculum/bulk`, `/split/bulk` |

**Messages** "a course code is three letters, a space and three digits, like CSC 311 — % does not fit"; "a course with the code % already exists". · **Security** `assertHodOwns` on every write.

> **Screenshot Required:** Department Courses — `/catalogue` — the table with binding pills and the duplicate panel.

#### 4.5.5 Programme Structure

```text
Academic → Programme Structure → /catalogue/structure
```
**URL** `/catalogue/structure?prog=` · **Purpose** Bind courses into a programme at a level on a basis and track. · **Who** hod (menu); `OWNERS`. · **Layout** Programme picker, Track filter; tiles Courses bound / Levels / Borrowed / Without a semester; "Bind a course into the structure" (course search ≥ 2 chars, Level, Basis Core/Elective/Borrowed/GST — Borrowed by default when another department owns it, Track "Every track" or a track); per-level panels with unit totals and warnings "core alone exceeds the N-unit maximum" / "under the N-unit minimum"; rows Code, Title, Units, Basis, Track, Owner, State, Remove. · **Actions** Bind → `POST /structure/bind`; Remove → `DELETE /structure/bind?programme&course&level`. · **Messages** "N students of P at L level are registered on C this session; the binding stays while they are."

> **Screenshot Required:** Programme Structure — `/catalogue/structure` — a level panel with unit totals.

#### 4.5.6 Who May Register It

```text
Academic → Who May Register It → /eligibility
```
**URL** `/eligibility?dept&course` · **Purpose** The eligible programme-and-level set of a course. · **Who** hod, dean (menu); catalogue readers. · **Layout** Department and course pickers; tiles Owning department / Eligible cohorts / Registered / From other departments; table Programme, Department, Faculty, Level, Basis, Registered, Relation (`GET /catalogue/courses/{code}/eligibility`). · **Actions** Read-only. · **Note** The page title in `titles.ts` is fixed to "Who may register CSC 311".

> **Screenshot Required:** Who May Register It — `/eligibility` — the table for one course.

#### 4.5.7 Teaching Allocation

```text
Academic → Teaching Allocation → /allocate
```
**URL** `/allocate` · **Purpose** Lead lecturer, second examiner and co-lecturers per offering. · **Who** hod, dean, admin (menu); `ALLOCATORS`. · **Layout** Scope bar (Department, Session, Semester, Level); tiles Courses / Unassigned / No second examiner / Lecturers; table Course, Level, Units, Registered, Lecturers, Second examiner, Action (Assign in urgent style, else Manage); note "Assigning the lead lecturer does four things at once".

| Field (modal) | Description | Required | Validation |
|---|---|---|---|
| Lead lecturer | Radio list with search "Search a lecturer by name or staff number…"; "Lecturers from other departments" checkbox; Current load / After this | Yes | Load ≤ 12 unless overload |
| Second examiner | "Verifies the marks. Cannot be the lead." | No | ≠ lead |
| Co-lecturers | Chips; "Add a co-lecturer" | No | Not the lead |

| Action | What it does | Endpoint |
|---|---|---|
| Save the lead & second examiner / Save as an overload (N units) | Allocates; creates the sheet when the exam session is OPEN | `POST /allocation/{offering}` |
| Add co-lecturer / Remove | Co-lecturer rows | `POST /{offering}/teachers`, `DELETE /{offering}/teachers/{lecturer}` |

**Messages** "{code} assigned to {name}…"; "No course is offered for {dept} in {session}…"; "The portal did not answer within 30 seconds"; `ALLOC_ENDED`; `ALLOC_BUSY`. · **Security** HOD bound; cross-department pool allowed.

> **Screenshot Required:** Teaching allocation — `/allocate` — the Assign modal with load figures.

### 4.6 Registration, course spaces, library and SIWES

#### 4.6.1 Registered Students / Examination Roll (class list and offering desk)

```text
Students → Registered Students / Examination Roll → /registration/class-list
```
**URL** `/registration/class-list` · **Purpose** The roll of an offering, attendance, timetable slots and the examination slot. · **Who** academic, dean, exams, hod, lecturer (menu); `READERS` with course/allocation scope. · **Layout** Scope bar with course; tiles Registered / owning department / Other programmes / Cleared to sit; buttons "Download class list", "Attendance register", "Examination roll" (CSV); table Matriculation number, Name, Programme, Level, Basis, Attendance ("—"), Clearance (Cleared / Blocked — fees); warning listing students not cleared; panels Attendance (date, All present / None, checkboxes, "Record N of M present", "Rate so far"), Timetable slots (Day, Kind Lecture/Practical/Tutorial, From, To, Venue; End), Examination slot (Date, Start, End, Venue). · **Actions** Record attendance → `POST /registration/offerings/{id}/attendance`; Add slot → `POST …/slots`; End → `POST …/slots/{slot}/end`; Set exam slot → `PUT /results/offerings/{id}/exam-slot`. · **Messages** "X is not allocated to you in S; a lecturer reads the class list of their own courses only."

> **Screenshot Required:** Registered Students — `/registration/class-list` — the roll with the Clearance column and the attendance panel.

#### 4.6.2 Course Spaces and a course space

```text
Academic → Course Spaces → /lms → Open the space → /lms/{offering}
```
**URLs** `/lms`, `/lms?tab=upload`, `/lms/{offering}` · **Purpose** Materials, assignments, marking, engagement, CA promotion. · **Who** lecturer, hod, dean (menu); `TEACHERS` with `requireTeaches`. · **Layout** `/lms`: table Course, Enrolled, Materials, Assignments, "Open the space" / "Upload material". `/lms/{offering}`: tiles Materials published / Assignments / Submissions / Never opened the space; "Upload course material"; "Published material"; "Assignments" (table + form); "Promote CA total to the score sheet"; "Engagement — students at risk"; note "Similarity check is not on the portal".

| Field | Description | Required | Validation |
|---|---|---|---|
| Title, Week, Kind, Description | Kind Notes/Slides/Reading/Video/Audio/Other | Title, Kind | — |
| File / Or an address | "up to 5 MB here" | One of the two | Types list; 1 byte–5 MB |
| Publish to the N registered students now | Unticked = draft | No | — |
| New assignment title, Closes, Weight % of CA, Kind, Brief, Marked out of, Late window hours, Late penalty % | — | Title, Closes, Weight | Weight 1–40; out_of 1–1000; hours 0–720; penalty 0–100 |
| Mark, Feedback | Per submission | Mark | ≥ 0 |

| Action | What it does | Endpoint |
|---|---|---|
| Upload | Creates material (draft or published) | `POST /lms/offerings/{o}/materials` |
| Publish / Withdraw | State change | `…/materials/{id}/publish`, `/end` |
| Create assignment | — | `POST …/assignments` |
| Mark / Review | Saves mark and feedback | `…/assignments/{a}/submissions/{s}/mark` |
| Promote CA total to the score sheet | Writes CA (≤ 40) as a new score version, MAIN sheet at ENTRY only | `POST …/promote-ca` |

**Messages** "No course is allocated to you in S…"; "no score sheet exists for this offering yet"; "the score sheet has left the lecturer; the gradebook is not promoted into it". · **Security** Files served without sandbox headers.

> **Screenshot Required:** Course space — `/lms/{offering}` — the material upload panel and the engagement panel.

#### 4.6.3 Circulation (library desk)

```text
Services → Circulation / Library Circulation → /library/circulation
```
**URL** `/library/circulation?patron=&q=` · **Purpose** Issue, return, renew, reserve, fines, catalogue, the rule. · **Who** library, services (menu); `DESK` + admin, super; readers per §3.15. · **Layout** RoleLine; tiles Copies in stock / On loan / Overdue / Fines unpaid; panel "Issue, return, renew"; "Circulation today"; "Overdue"; "Fines unpaid"; "Catalogue"; "The rule in force".

| Field | Description | Required | Validation |
|---|---|---|---|
| Accession number | e.g. CSC/004182 | Yes | `^[A-Z]{2,5}/[0-9]{4,8}$` |
| Patron | "Matriculation, admission or staff number" | Yes | Exactly one patron |
| Catalogue item: Title, Author, Edition, Year, ISBN, Subject, Kind, Shelf, Accession numbers of the copies | Kind Book/Journal/Thesis/Audiovisual/Reference | Title | — |
| Rule: Loan days, Fine per day, Items at once, Renewals | Librarian only | — | 1–120; ≥ 0; 1–20; 0–5 |

| Action | What it does | Endpoint |
|---|---|---|
| Issue / Return / Renew | Loan lifecycle | `POST /library/loans`, `/returns`, `…/renew` |
| Waive | Fine waived with a reason (prompt) | `POST /library/loans/{id}/waive` |
| Add item | Catalogue upsert with copies | `PUT /library/items` |
| Save the rule | — | `PUT /library/setting` |

**Messages** "Returned N days late — fine ₦x posted"; issue refusals of §3.15. 

> **Screenshot Required:** Circulation — `/library/circulation` — the issue/return panel and the patron standing.

#### 4.6.4 SIWES Supervision

```text
Students → SIWES Supervision → /siwes
```
**URL** `/siwes?session&sem&offering` · **Purpose** Assign supervisors and record the practical mark. · **Who** hod, siwes (menu); `ASSIGNERS`. · **Layout** Session, Semester, SIWES course pickers; tiles Students / Supervisors assigned / Score sheet / Course; table Matric, Name, Programme, Supervisor (searchable select), Assessment /40, Practical /60 (input + Save), Total; inputs disabled unless the sheet is at ENTRY. · **Actions** Assign → `PUT /siwes/offerings/{o}/students/{s}/supervisor`; Save → `PUT …/practical` (a change prompts "Why is X's practical mark changing…"). · **Messages** "No SIWES course this session and semester"; `SIWES_NO_SHEET`.

> **Screenshot Required:** SIWES Supervision — `/siwes` — the table with supervisors assigned.

### 4.7 Undergraduate admissions

#### 4.7.1 Admission settings

```text
Students → Matriculation Management → /matriculation/manage
```
**URL** `/matriculation/manage?session=&fac=&prog=&status=&q=&tab=` · **Purpose** The matriculation exercise faculty by faculty (V267): eligible students by programme, numbers proposed and reserved, reviewed, corrected with a reason, marked ready, issued on confirmation — the number becoming the sign-in username. · **Who** academic, registrar, dregistrar, facultyofficer (menu; the officer bound to their faculty); readers dvc, vc, records, dean, ict, admin, super. · **Layout** PageHead (Matriculation run, Number format, Excel / PDF); scope bar (Academic session, Faculty, Programme, Status, Search + Load Students); tabs Faculty view / All faculties / Batches / Issued / Pending / Conflicts; eight tiles; the batch panel (Generate, Validate, Mark ready, Final review & issue, Cancel, Batch record); programme groups with the student table (Edit / Fix / Drop); modals for the correction, the drop, the cancellation, the final review, the confirmation, the completion and the batch record.

```text
Admissions → Admission Settings → /admissions/settings
```
**URL** `/admissions/settings?session=` · **Purpose** The session's admission policy, the load cut-off and the O'Level grading. · **Who** academic (menu; registrar and dregistrar by URL — `SECRETARIAT`); readers add dean, hod, dvc, vc, records, ict, admin, super. · **Layout** Without settings: "No admission settings exist for {session}" with "Begin from {previous}" or a NUC quota box and "Create the {session} settings". With settings: RoleLine; note "in force" or "a DRAFT, and nothing may be admitted under them"; tiles; panels The aggregate score, The four selection criteria, The ratios and the caps, Catchment local governments, NUC approved quota, Faculty UTME:Direct-Entry split, Every programme the University runs (per-row rule modal), Findings, Questions the guidelines raise, Put the {session} settings in force; General UTME cut-off for loading the JAMB lists; O'Level grading for the screening score.

| Field | Description | Required | Validation |
|---|---|---|---|
| UTME / Post-UTME weights | Paragraph 2.6 | Yes | Total 100 (`ADM_WEIGHTS`) |
| NM / SM / ELG / LOCALITY percentages | The four criteria | Yes | Total 100 |
| UTME:DE, Science:Arts ratios; ELG cap; department share | — | Yes | Sums; `ADM_RATIO_PAIR` |
| NUC approved quota; faculty quotas | — | Yes | `nuc_quota > 0`; programme quotas total the NUC quota |
| Catchment local governments | Textarea | No | — |
| Programme rule: Cut-off of its own, Programme quota, requirement texts, Relevant O'Level subjects, Required UTME subjects, Direct Entry subjects, DE passes required, Compulsory-credit exceptions | Syntax "comma = all, '/' = any-one-of, 'N of A/B/C'" | — | Cut-offs 1–400; credits 1–9 |
| Central Admissions Committee minute | Placeholder CAC/2026/07 | To put in force | Zero findings |
| General UTME cut-off | "of 400" | Before a UTME list loads | 0–400 |
| O'Level grading: points per grade A1–F9, subjects counted, one-/two-sitting bonus, Programmes screened by examination | — | — | — |

| Action | What it does | Endpoint |
|---|---|---|
| Create / Begin from | `PUT …/policy` / `POST …/policy/start-from/{from}` | admissions |
| Save panels | Policy parts; catchment | `PUT …/policy…`, `PUT …/policy/catchment` |
| Put in force | Freezes weights, ratios, criteria, cut-offs, subject rules | `POST …/policy/in-force` |
| Save the load cut-off | — | `PUT …/load-cutoff` |
| Save O'Level grading | — | `PUT …/olevel-grading` |

**Messages** "The selection criteria do not total 100%"; "The programme quotas do not total the NUC approved quota"; "The {session} settings are in force under {minute} and are not edited."; "No UTME list can be loaded until this is stated". · **Security** Session defaults to 2026/2027.

> **Screenshot Required:** Admission settings — `/admissions/settings` — the criteria and ratios panels with the Findings panel.

#### 4.7.2 Upload Applicants and Candidates (CAPS)

```text
Admissions → Upload Applicants and Candidates → /admissions/caps
```
**URL** `/admissions/caps` · **Purpose** Load, commit and withdraw JAMB's UTME and Direct Entry lists. · **Who** academic (menu; registrar by URL — `LOADERS`). · **Layout** Two upload cards UTME (100 Level) and Direct Entry (200 Level) with "Choose the … file…" (.xlsx) and "Use the sample instead"; parsed list with tiles, blocking findings, AliasMapper ("JAMB course names the alias list does not carry"), "Under the cut-off — read, not loaded", the list table; "Load the {kind} list"; "Commit"; "Lists loaded for {session}" (Kind, File, Rows, Downloaded, Loaded, By, State held/committed/withdrawn; Commit, Withdraw); "Does the list reconcile?"; "One course code, two names" (programme edit modal); "Reset the JAMB list for {session}".

| Action | What it does | Endpoint |
|---|---|---|
| Map an alias | JAMB name → programme | `PUT /programmes/{code}/jamb-alias` |
| Load the list | Batch + rows in chunks | `POST /caps-batches`, `…/rows` |
| Commit | Refused while findings stand | `POST /caps-batches/{id}/commit` |
| Withdraw | Modal "Why the list is withdrawn" | `POST /caps-batches/{id}/withdraw` |
| Reset the JAMB list | Double confirm; destructive | `POST …/reset-intake` |

**Messages** "n rows cannot be accepted, so none of the file is written"; "Not a programme the University runs: …"; "the admission list does not reconcile: …"; "a list is withdrawn for a reason, and none was given". · **Security** UTME load disabled until settings are in force; acting office checked in code.

> **Screenshot Required:** CAPS upload — `/admissions/caps` — a parsed list with the alias mapper.

#### 4.7.3 Upload Passport, DOB & O'Level (candidate data)

```text
Admissions → Upload Passport, DOB & O'Level → /admissions/candidate-data
```
**URL** `/admissions/candidate-data` · **Purpose** Record JAMB's passports, dates of birth and O'Level downloads. · **Who** academic (menu); `WRITERS` academic, registrar, dregistrar. · **Layout** Panels for passports (multiple images named by JAMB number; ≤ 64 KB stored as data URL, larger by metadata), date-of-birth file (.xlsx), O'Level file (.xlsx, one row per subject); "As the register stands"; passport gallery with search and programme filter; "Results recorded, and the screening score they carry" with an eye → OlevelView modal (score details to the Academic Office only). · **Actions** Record → `POST …/candidate-data {kind, items}` (re-attaches to committed candidates). · **Messages** "Named, not guessed at"; ambiguous dates flagged. · **Security** O'Level score returned only when acting as `academic`.

> **Screenshot Required:** Candidate data — `/admissions/candidate-data` — the three panels and the gallery.

#### 4.7.4 Report on Admissions (the admissions desk)

```text
Admissions → Programme Eligibility → /admissions/eligibility
```
**URL** `/admissions/eligibility?session=` · **Purpose** The automatic admission course suggestion engine's register (V266): every submitted applicant against the session's admission settings — the verdict on the applied programme, the failed requirements, the suggested programmes, the programme-change queue and the reports. · **Who** academic, registrar (menu); readers dregistrar, records, bursar, ict, admin, super, dvc, vc; acting academic, registrar, dregistrar, super. · **Layout** PageHead with Admissions / Admission Settings links, Evaluate the unevaluated, Recalculate all, Excel / PDF; eight tiles; filter bar (Eligibility, Faculty, Department, Programme applied, Recommended programme, Mode, Search); "Applicant eligibility" table (S/N, Applicant, Applied programme, Eligibility, Failed requirements, Suggested programmes, Change, View Matching Details / Recalculate); "Programme change requests" (Approve / Reject / Details); "Reports" (Candidates not eligible, Alternative programme suggestions, Statistics); the details modal (O'Level and UTME on record, check tables, suggested programmes with View Eligibility Details and Request Change, change requests, trail).

```text
Admissions → Report on Admissions / Admissions → /admissions
```
**URL** `/admissions` · **Purpose** The cycle, intake to the register, merit lists, the applicants desk, decisions, the JAMB template and status upload, reconsiderations. · **Who** academic, admin, registrar (menu); readers/OFFICE per §3.17. · **Layout** Tiles Applications / Screened / Offers issued / Accepted; red note "n admitted candidates are not yet on the register" with the intake button; "Programmes — merit lists" with "Record all programmes"; "JAMB reconciliation"; ApplicantsDesk (tiles, "Screening batches" with New batch modal — Batch label, Date, Starts, Ends, Venue, Capacity —, "Seat the submitted", "Hall list", "Release scores"; "Applicants" table with "Release decisions" and an eye → application modal with "CBT score, of 100" and "The Board's decision" — Decision, Basis, Note; "The list that goes back to JAMB" → "Download for JAMB"; "Admission status from JAMB" upload); Reconsiderations (select + "Suggest").

| Action | What it does | Endpoint |
|---|---|---|
| Bring N candidates onto the register | `people.intake` — admission numbers | `POST /api/v1/student/intake/{session}` (`Admissions.tsx:49`) |
| Record all programmes | Merit for every programme | `POST /merit/record-many` |
| New batch / Seat the submitted | Legacy screening | `POST …/screening-batches`, `assign_screening` |
| Release scores / Release decisions | Stamps release, notifies | `…/screening-scores/release`, `…/decisions/release` |
| Save CBT score / Save decision | Per application | `PUT …/screening-score`, `PUT …/decision` |
| Download for JAMB | Five-sheet workbook | `GET …/jamb-template?programme=` |
| Upload JAMB status | `load_jamb_admissions` in chunks | `POST …/jamb-admissions` |
| Suggest | Reconsideration email | `POST …/reconsiderations/suggest` |

**Messages** "The acceptance fee is not set for this session"; "the decision was released on … and stands"; "a compulsory O'Level credit is missing: …". · **Security** Intake runs on ADMITTED as well as ACCEPTED candidates.

> **Screenshot Required:** Report on Admissions — `/admissions` — the cycle tiles and the intake note.

#### 4.7.5 Report on Post-UTME Registration / Admitted List

```text
Admissions → Report on Post-UTME Registration / Admitted List → /admissions/applicants
```
**URL** `/admissions/applicants` · **Purpose** Who on the committed list has registered. · **Who** academic, registrar (menu); `READERS`. · **Layout** Filters Faculty, Programme, Entry mode, "Find an applicant"; tiles On the committed list / Registered for post-UTME / Not yet registered / Showing; "Admitted by programme"; "Applicants" table (first 200). · **Actions** Read-only.

> **Screenshot Required:** Report on Post-UTME Registration — `/admissions/applicants` — tiles and the breakdown.

#### 4.7.6 Merit List

```text
Admissions → Merit List → /admissions/merit
```
**URL** `/admissions/merit` · **Purpose** Rank and record a programme's UTME merit list. · **Who** academic (menu); record academic, registrar. · **Layout** Programme type-ahead; tiles pool/eligible/proposed; table #, Candidate, JAMB, Entry, UTME, Post-UTME, Aggregate, Basis, Eligible (else "No Eng/Maths credit" / "Below cut-off" / "Not scored"), Proposed. · **Actions** Record the merit list → `POST /merit/record` (confirm). · **Security** Direct Entry excluded ("UTME only for now").

> **Screenshot Required:** Merit List — `/admissions/merit` — a ranked table with bases.

#### 4.7.7 Direct Entry Screening

```text
Admissions → Direct Entry Screening → /admissions/de-screening
```
**URL** `/admissions/de-screening` · **Purpose** Capture DE awards and judge the subject combination. · **Who** academic (menu); `LOADERS`. · **Layout** Programme type-ahead; table Candidate, JAMB, Level, Subjects, Status (NO_RULE / UNVERIFIED / MET / SHORT); inline form.

| Field | Description | Required | Validation |
|---|---|---|---|
| Qualification (basis) | A_LEVEL / IJMB / JUPEB / NCE / ND / HND | Yes | — |
| Year awarded, Awarding body / institution | — | No | — |
| Subjects offered | One per line, grade after `:` or `,` | Yes | — |

**Actions** Save/Update the record → `POST /de-awards`; Remove → `DELETE /de-awards/{id}`.

> **Screenshot Required:** Direct Entry Screening — `/admissions/de-screening` — a row with the inline form open.

#### 4.7.8 Upload PUTME Score / Post-UTME Scores

```text
Admissions → Upload PUTME Score / Post-UTME Scores → /admissions/scores
```
**URL** `/admissions/scores` · **Purpose** Bulk Post-UTME scores, zeroing, release, clearing. · **Who** academic, admin, ict (menu); `SCORE_UPLOADERS`; release `OFFICE`. · **Layout** "Programmes whose Post-UTME scores must be uploaded" (Registered/Scored/Released/Awaiting/Status; "Download all awaiting", "Score remaining as zero"); "Post-UTME scores" textarea/CSV (`key, score`; "Download template", "Load a CSV", "Upload n scores"; reconciliation table No applicant match / Score already released / Score out of 0–100); "Release the scores"; "Clear uploaded Post-UTME scores" (programme + type `CLEAR SCORES`). · **Actions** `POST …/screening-scores/upload`, `…/zero-missing`, `…/release`, `…/clear`. · **Messages** "Type CLEAR SCORES to confirm…"; `APP_SCORE_LOCKED`.

> **Screenshot Required:** Upload PUTME Score — `/admissions/scores` — the reconciliation table after an upload.

#### 4.7.9 Compute PUTME Score (computed Post-UTME)

```text
Admissions → Compute PUTME Score → /admissions/computed-screening
```
**URL** `/admissions/computed-screening` · **Purpose** Non-index programmes and Direct Entry scored from O'Level + UTME. · **Who** academic (menu); `/post-utme-computed` academic, super; from-olevel academic, super, ict, admin, registrar, dregistrar. · **Layout** Table Candidate, JAMB, Programme, Mode, O'Level, UTME, Computed, Basis; "Enter O'Level as Post-UTME score"; "Download Excel", "Print / PDF"; audit table "Why a programme appears here — or does not". · **Actions** `POST …/screening-scores/from-olevel`; exports (serial CPU, branded).

> **Screenshot Required:** Compute PUTME Score — `/admissions/computed-screening` — the computed table.

#### 4.7.10 Screening Register, Screened pool, Hall list

```text
Admissions → Screening Register → /admissions/screening ; (from /admissions) → /admissions/screened ; (from a batch) → /admissions/screening/{batch}
```
**URLs** `/admissions/screening`, `/admissions/screened`, `/admissions/screening/{batch}` · **Purpose** Every submitted candidate with UTME, O'Level /100, Post-UTME, screening score and source; the per-faculty/course screened summary with drill-down; a legacy batch's hall list with photographs. · **Who** academic (menu); `READERS`. · **Layout** Register table with a "Non-index Post-UTME scores" CSV; Screened summary (Applied, Screened, Quota, Cut-off) and detail (RegNo, Name, Sex, State, UTME, Meets cut-off, O'Level uploaded, points, Compulsory (Eng & Maths)); hall list in seat order with "Print the hall list". · **Exports** Excel/print of summary, detail and "O'Level screening — all programmes".

> **Screenshot Required:** Screened pool — `/admissions/screened` — the summary with a programme expanded.

#### 4.7.11 Migrate Old-Portal Applicants

```text
Admissions → Migrate Old-Portal Applicants → /admissions/migrate
```
**URL** `/admissions/migrate` · **Purpose** Import old-portal applicants as fee-confirmed, submitted applications. · **Who** academic (menu); `IMPORTERS`. · **Layout** Requires the applicant fee to be stated; .xlsx/.csv of JAMB no / email / phone (name order option); "Import n applicants" in parallel chunks then `link-held`; result tiles; "rows not imported" download; "Reset migrated applicants". · **Actions** `POST …/import-applicants`, `…/link-held`, `…/reset-migrated`. · **Security** Accounts are created with the `SET_ON_FIRST_LOGIN` sentinel (JAMB number as first password).

> **Screenshot Required:** Migrate Old-Portal Applicants — `/admissions/migrate` — result tiles.

#### 4.7.12 Post-UTME CBT Schedule (dashboard)

```text
Admissions/Academic → Post-UTME CBT Schedule → /admissions/putme
```
**URL** `/admissions/putme?session=` · **Purpose** The examination event: generate, validate, publish, monitor. · **Who** academic, registrar, ict, admin, records, dregistrar, super (menu); `READERS`; `OFFICE` for acts. · **Layout** Session select; buttons Setup, Candidates, Check-in Desk; exam note with state pill; tiles; Validation report; "Where the candidates stand"; by faculty / day / centre / programme; Batches table (S/N, Batch, Day, Time, Centre · room, Capacity, Assigned, Checked in, State) with Excel/print. · **Actions** Generate Batches / Generate again → `POST …/putme/generate`; Publish and notify → `…/publish`; Reopen for scheduling / Mark completed → `…/exam/state` (modal with "Note for the record"). · **Messages** "No programme is named as screened by examination this session, so nobody is eligible"; "the schedule cannot be published: {errors}"; "nothing to publish: generate the batches first".

> **Screenshot Required:** Post-UTME CBT Schedule — `/admissions/putme` — the validation report and batches table.

#### 4.7.13 Examination setup (CBT)

```text
/admissions/putme → Setup → /admissions/putme/setup
```
**URL** `/admissions/putme/setup` · **Purpose** The exam, centres, rooms, workstations, days, slots, places. · **Who** `OFFICE`.

| Field | Description | Required | Validation |
|---|---|---|---|
| Name | The examination | Yes | Unique per session |
| First day, Last day | — | Yes | `ck_pe_dates` |
| Report before (minutes), Sitting (minutes), Buffer between batches | Defaults 30 / 120 / 30 | Yes | 0–240; 10–600 |
| Registration deadline | Stored, not read | No | — |
| Batching strategy | PROGRAMME / DEPARTMENT / FACULTY / ALPHABETICAL / APPLICATION_NO / BALANCED | Yes | — |
| Keep a programme together | Stored, not read | No | — |
| Enquiries contact, Examination instructions, Venue instructions | Text | No | — |
| Centre: Code, Name, Location, Address, Contact person, Contact phone or email, State | — | Code, Name | Code `^[A-Z0-9-]{2,12}$` |
| Room: Code, Name, Capacity, Workstations, State | Workstations numbered on save | Code, Capacity | 1–2000; workstations ≤ capacity |
| Days; Slots (Code, From, To) | Auto-suggest from duration + buffer | — | "Slot X ends before it starts." |

**Actions** Create/Save the examination → `PUT …/putme/exam`; Add a centre / rooms / workstation toggles → `PUT …/workstations/{id}`; days and slots add/remove. · **Messages** "Places cannot be changed under a published schedule".

> **Screenshot Required:** Examination setup — `/admissions/putme/setup` — the examination form and the Places table.

#### 4.7.14 Candidates (CBT)

```text
/admissions/putme → Candidates → /admissions/putme/candidates
```
**URL** `/admissions/putme/candidates` · **Purpose** Every candidate's standing, moves, unscheduling, review confirmation, trail. · **Who** `READERS`; acts `OFFICE`. · **Layout** Filters Standing (Everyone / Eligible / Ready, not seated / Scheduled / each status), Faculty, Department, Programme, Batch, Centre, Search; paged table with checkboxes; Excel/PDF. · **Actions** Move n to a batch (Batch, Reason) → `POST …/putme/move`; Unschedule n (Reason) → `…/unschedule`; Confirm (schedule review) → `…/confirm-schedule`; Trail modal. · **Messages** "a move carries its reason"; "ROOM CAPACITY EXCEEDED: batch B is full (n of n)"; "the candidate is not eligible for seating: {why}".

> **Screenshot Required:** Candidates — `/admissions/putme/candidates` — the filter bar and a selection with "Move n to a batch".

#### 4.7.15 A batch (CBT)

```text
/admissions/putme → Batches → /admissions/putme/batches/{id}
```
**URL** `/admissions/putme/batches/{id}` · **Purpose** One batch's seats, attendance sheet, marking. · **Who** `READERS`; acts `OFFICE`, marking `DOOR`. · **Layout** Header with state pill; buttons Move n to another batch, Postpone, Cancel batch (Reason), Attendance sheet (Excel), Print attendance sheet, Check-in desk; seats table with photograph, attendance, examination status, signature line, Mark (Attendance, Examination, Remarks "Required for a disqualification"). · **Actions** `POST …/batches/{id}/state`; `POST …/putme/attendance`. · **Messages** "Candidates are not told and see no slip until the schedule is published"; "say why the batch is postponed".

> **Screenshot Required:** Batch — `/admissions/putme/batches/{id}` — seats with photographs.

#### 4.7.16 Check-in desk (CBT)

```text
/admissions/putme → Check-in Desk → /admissions/putme/checkin
```
**URL** `/admissions/putme/checkin` · **Purpose** Check candidates in by scanning the slip's QR. · **Who** `DOOR` academic, registrar, dregistrar, records, ict, super. · **Layout** One autofocused box "Slip QR, application number or JAMB number"; Find; record card; verdicts "Not seated in any batch", "Seated on {day}, not today", "Already checked in at … A second arrival on this slip is an impersonation", "Disqualified", or green "Seated today · batch B, seat NNN" with Check in; then Seated, started / Completed / Absent / Disqualify; "Sitting today" list. · **Actions** `GET …/putme/lookup?key=`; `POST …/putme/checkin`; `POST …/putme/attendance`. · **Messages** "batch B is draft; check-in is at a published batch".

> **Screenshot Required:** Check-in desk — `/admissions/putme/checkin` — a green "Seated today" verdict.

### 4.8 Applicant portal

#### 4.8.1 Post UTME Registration

```text
/login → Post UTME Registration → /apply
```
**URL** `/apply?session=` · **Purpose** Create the application account from the JAMB number. · **Who** Public. · **Layout** Two-column login card headed "Post UTME Registration".

| Field | Description | Required | Validation |
|---|---|---|---|
| JAMB registration number | Placeholder `202699176777GF`, max 15 | Yes | `^\d{12}[A-Z]{2,3}$`; lookup on each keystroke |
| Surname and other names / Programme you chose | Read-only from CAPS | — | — |
| Email address | "Did you mean gmail.com?" hint | Yes | Email regex |
| Phone number | 0803…, +234 803… or 803… | Yes | 11 digits from 0 |
| Choose a password / Confirm password | Show/hide | Yes | ≥ 8; match |

| Action | What it does | Endpoint |
|---|---|---|
| (typing) | Lookup states nolist / none / found / registered / closed | `POST /api/v1/applicant/lookup` |
| Continue | Creates the account and signs in | `POST /api/auth/applicant/register` |

**Messages** "Nobody can be verified yet, and so nobody is let through"; "That number is not on the list JAMB sent the University"; "The University is not admitting into {programme} this session"; "An application account already exists for this number". · **Security** Public; no rate limit.

> **Screenshot Required:** Post UTME Registration — `/apply` — the found state with the read-only name and programme.

#### 4.8.2 Overview (applicant dashboard)

```text
My application → Overview → /applicant
```
**URL** `/applicant` · **Purpose** Stage rail and everything at a glance. · **Who** applicant. · **Layout** Passport card; tiles Application number / Programme applied for / UTME score / Entry / Stage n of 10; "what next" note with a button; the ten-step "Your application" rail; "Dates that matter"; "Notices sent to you". · **Actions** Links; PayByCard when a reference is open. 

> **Screenshot Required:** Applicant Overview — `/applicant` — the stage rail.

#### 4.8.3 Application Form

```text
My application → Application Form → /applicant/apply
```
**URL** `/applicant/apply` · **Purpose** Biodata (from JAMB), next of kin, O'Level as sent, review and submit. · **Who** applicant. · **Layout** Stage < 1: "The form opens when your application fee is confirmed"; stage 1: pills 1 Biodata · 2 O'Level · 3 Review; stage ≥ 2: "Your application was submitted on …", "What you submitted", "Print / Download (PDF)".

| Field | Description | Required | Validation |
|---|---|---|---|
| Next of kin — name and phone | Saved on blur | Yes | Non-blank ("the next of kin is not given") |
| Declaration | "I declare that the particulars I have given are true…" | Yes | Ticked |

**Actions** Save and come back later; Submit application → `POST /me/submit {declaration:true}`; PDF → `/applicant/apply/pdf`. · **Security** No document upload control exists on this screen.

> **Screenshot Required:** Application Form — `/applicant/apply` — the Review and submit step.

#### 4.8.4 Application Fee

```text
My application → Application Fee → /applicant/fee
```
**URL** `/applicant/fee?paid=` · **Purpose** Generate and pay the application reference. · **Who** applicant. · **Layout** "Application and screening fee" table (Post-UTME screening fee + Portal and payment charge = Total payable); "Your payment reference" (`MOAUM-APP-…`, 24 h); "How you can pay"; after confirmation "Payment confirmed — ₦… received" and a Receipt panel. · **Actions** Generate a reference → `POST /me/fee-references {kind:"APPLICATION"}`; Pay ₦… by card or USSD (PayByCard); "I've paid — check now" → `/payments/verify`. · **Messages** "the application fee is already confirmed"; "Not confirmed yet" after PayDirect.

> **Screenshot Required:** Application Fee — `/applicant/fee` — an open reference with the pay button.

#### 4.8.5 Screening Slip

```text
Screening → Screening Slip → /applicant/screening
```
**URL** `/applicant/screening` · **Purpose** The slip once the batch is published. · **Who** applicant. · **Layout** "Your examination schedule has not been published yet" or the slip (report time = batch start − check-in minutes; attendance pill; QR to `/verify/putme/{token}`; Batch, Date, Report by, Examination time, Centre, Room, Seat, Workstation, Bring; instructions). · **Actions** Download slip (PDF) → `/applicant/screening/slip` (409 "No examination slip yet" before scheduling); See your screening result. · **Messages** "Your batch has been postponed/cancelled".

> **Screenshot Required:** Screening Slip — `/applicant/screening` — the slip with the QR.

#### 4.8.6 Screening Result

```text
Screening → Screening Result → /applicant/score
```
**URL** `/applicant/score` · **Purpose** UTME, Post-UTME and aggregate against the cut-off. · **Who** applicant. · **Layout** Before release "Scores are released when every batch has been screened"; after: tiles UTME (of 400, scaled), Post-UTME screening (source CBT / EXAM / OLEVEL / NONE), Aggregate, Departmental cut-off; "How your aggregate was calculated"; "Where you stand"; "If you think this score is wrong". · **Actions** None.

> **Screenshot Required:** Screening Result — `/applicant/score` — the four tiles and the calculation panel.

#### 4.8.7 Admission Status

```text
Admission → Admission Status → /applicant/status
```
**URL** `/applicant/status` · **Purpose** The Board's decision once released. · **Who** applicant. · **Layout** "Your application is with the Admissions Board" / "You are on the waiting list" / "You were not offered a place this session" / green "Offer of provisional admission" card with acceptance state. · **Actions** Accept your offer (→ `/applicant/accept`); Print Offer Letter → `/applicant/status/letter` (after acceptance; 409 "No offer to print" / "Accept your offer first").

> **Screenshot Required:** Admission Status — `/applicant/status` — the offer card.

#### 4.8.8 Accept Your Offer

```text
Admission → Accept Your Offer → /applicant/accept
```
**URL** `/applicant/accept?paid=` · **Purpose** Sign the undertaking and pay the acceptance fee, or decline. · **Who** applicant. · **Layout** "To accept, you must do both" table; Undertaking text with checkbox "I have read the undertaking and I accept it."; PayByCard when a reference is open; after both: "Offer accepted — ₦… received" and a Receipt ("Non-refundable: Yes"). · **Actions** Sign the undertaking → `POST /me/accept {undertaking:true}`; Generate a reference for ₦… → `POST /me/fee-references {kind:"ACCEPTANCE"}`; Decline this offer (confirm "Decline this offer? A declined offer is not reinstated.") → `POST /me/decline`. · **Messages** "there is no offer to accept"; "this offer was declined on …".

> **Screenshot Required:** Accept Your Offer — `/applicant/accept` — the undertaking and the two requirements.

#### 4.8.9 Document Clearance

```text
Admission → Document Clearance → /applicant/clearance
```
**URL** `/applicant/clearance` · **Purpose** The six originals the Registry verifies in person. · **Who** applicant (read). · **Layout** "Clearance opens when you have accepted your offer"; six-row Documents table (O'Level certificate or statement of result, Birth certificate or declaration of age, Local government identification, JAMB admission letter, Medical fitness certificate, Passport photographs (six copies)) each Not presented / Verified / Query; "n of 6 verified"; "You are cleared" with "What happens next"; "Nothing is paid at clearance, to anyone." · **Actions** None (the Registry's recording endpoint has no screen — stage 7 is unreachable from the UI).

> **Screenshot Required:** Document Clearance — `/applicant/clearance` — the six-row table.

#### 4.8.10 Matriculation (applicant)

```text
Admission → Matriculation → /applicant/matric
```
**URL** `/applicant/matric` · **Purpose** Registration-before-matriculation explained; the admission number; later the matric number. · **Who** applicant. · **Layout** "What you carry now" (admission number or "Not issued yet."); "What you will be issued" (format table — shows the pre-V263 `MOAUM / dept / YY / NNNN` description); step list; once issued "Matriculation number issued" and "Your application account is now your student account". · **Actions** None.

> **Screenshot Required:** Matriculation (applicant) — `/applicant/matric` — "What you carry now".

### 4.9 Postgraduate School

#### 4.9.1 Apply for a postgraduate programme

```text
/login → Postgraduate application → /pg/apply
```
**URL** `/pg/apply` · **Purpose** Public three-step application; status check. · **Who** Public. · **Layout** Branded login-style frame; wizard 1 Programme (searchable combobox grouped by faculty), 2 Your details, 3 Account; "Check your application" card.

| Field | Description | Required | Validation |
|---|---|---|---|
| Programme | From `/api/v1/pg/programmes`; research hint | Yes | POST GRADUATE |
| Surname, Other names, Sex, Date of birth, State of origin → Local government, Email, Phone | Phone placeholder `08030000000` | Surname, Other names, Email | Surname ≤ 80; email ≤ 160 |
| Password / Confirm password | "At least six characters" | Yes | 6–100; match |
| Proposed topic / Summary of the proposed research | Research programmes only | No | — |
| Application number + Email (status check) | — | Yes | Both needed |

| Action | What it does | Endpoint |
|---|---|---|
| Create account & continue | `PG/YY/NNNNNN` + application-fee reference; "Sign in to pay and continue application" | `POST /api/v1/pg/apply` |
| Check | State label with the decision mask | `GET /api/v1/pg/status` |

**Messages** "Choose a programme to continue."; "An application already exists for this email."; "No application matches that number and email."

> **Screenshot Required:** Apply for a postgraduate programme — `/pg/apply` — step 1 with the programme picker.

#### 4.9.2 Your postgraduate application (portal)

```text
My application → Dashboard → /pg/portal
```
**URL** `/pg/portal?paid=` · **Purpose** Pay, complete the record, read the decision, accept, download the offer. · **Who** applicant (PG). · **Layout** Header note with state; tiles Programme / Application fee / Documents n/7 / Stage; decision gate panels (checking fee, acceptance fee, offer PDF, not offered); "Application fee" with PayByCard; Application and Bio-data grids; Progress (seven steps); "Complete your application" stepper (Academic record, Referees, Documents, Passport); "Application summary"; "A note from the School"; "You are now a student of the University"; History.

| Field | Description | Required | Validation |
|---|---|---|---|
| First degree: Institution, Degree / award, Field of study, Class of degree, CGPA, Year awarded | — | — | — |
| Other qualifications rows: kind, Institution, Award, Field, Class, CGPA, Year | MASTERS/PGD/HND/ND/NCE/PHD/OTHER | — | — |
| Referees: name, Email, Phone number, Institution, Position | ≤ 5; sent a private link | Email for a request | — |
| Documents | One PDF per kind (7 kinds; Higher degree certificate multiple) | — | PDF ≤ 8 MB |
| Passport | JPEG/PNG | — | ≤ 4 MB |

| Action | What it does | Endpoint |
|---|---|---|
| Pay / I've paid — check now | Fee reference of the current step | `POST /pg/fee-reference?kind=`, `/payments/verify` |
| Save academic record / qualifications / referees / documents / passport | Stepper writes | `POST /pg/first-degree`, `/qualifications`, `/referees`, `/documents` (+ `DELETE`), `/passport` |
| Download / print summary (PDF); Email me the summary | — | `/pg/summary/pdf`; `POST /pg/email-summary` |
| Download / print offer of admission (PDF) | After the acceptance fee | `/pg/offer/pdf` |

**Messages** "Pay the application fee first"; "The application fee could not be prepared"; "Confirming your payment…"; "Offer letter not available yet". · **Security** The offer's QR encodes text only (no verifier).

> **Screenshot Required:** Your postgraduate application — `/pg/portal` — tiles and the stepper.

#### 4.9.3 Referee form

```text
(emailed link) → /pg/referee/{token}
```
**URL** `/pg/referee/{token}` · **Purpose** A referee's attestation, once. · **Who** Public with a token. · **Fields** Relationship to the applicant*, How long have you known the applicant?*, Academic attestation* (≤ 4000), Recommendation, Your recommendation* (I recommend / with reservation / do not recommend). · **Actions** Submit reference → `POST /api/v1/pg/referee/{token}`. · **Messages** "Once submitted, a reference cannot be changed."; "Thank you — your reference has been received"; "This reference link is not valid."; "This reference has already been submitted."

> **Screenshot Required:** Referee form — `/pg/referee/{token}` — the form header naming the applicant.

#### 4.9.4 PG admissions desk

```text
Admissions → Admissions / PG Admissions / Postgraduate Admissions → /admissions/postgraduate
```
**URL** `/admissions/postgraduate?session=` · **Purpose** Applications by stage; department, faculty and School decisions; acceptance; admit. · **Who** pgschool, pgsecretary, hod, dean, academic (menu); `READERS`; decision guards per §3.19; HOD/Dean bound. · **Layout** Info note; Session select; six tiles; table (S/N, Applicant + number, Programme, Level, First degree, Stage, Details) with "Download Excel"; DetailPanel (passport, Bio-data, Institutions attended, Research proposal, Referees, Documents with "View all as one PDF" / "Download" and per-document "View PDF", desk notes, "A note for the decision (optional)", action buttons, History).

| Action | What it does | Endpoint |
|---|---|---|
| Department: recommend / Decline | SUBMITTED → DEPT_RECOMMENDED / DEPT_DECLINED | `POST /pg/applications/{id}/dept-decision` |
| Faculty: recommend / Decline | → FAC_RECOMMENDED / FAC_DECLINED | `…/faculty-decision` |
| Offer a place / Refuse | → OFFERED / NOT_OFFERED (emails the applicant) | `…/spgs-decision` |
| Record acceptance | → ACCEPTED | `…/accept` |
| Admit onto the register | → ADMITTED; student row and account | `…/admit` |

**Messages** "No postgraduate application has been submitted for {session} yet."; "This application is for another department's programme; …"; toast e.g. "Offered {name} a place on {programme}". · **Export** "Postgraduate applications" (serial PGAPP, S/N first).

> **Screenshot Required:** PG admissions desk — `/admissions/postgraduate` — the tiles and a DetailPanel with decision buttons.

#### 4.9.5 Postgraduate calendar

```text
Academic → Calendar → /admissions/postgraduate/calendar
```
**URL** `/admissions/postgraduate/calendar` · **Purpose** The School's sessions and semester windows. · **Who** pgschool, pgsecretary. · **Layout** Tiles Current session / Current semester / Sessions on record; Sessions table (Edit, Make current); Setup new session modal (Session, Semesters 2 or 3, Opens, Closes, State, Note); "Semesters — {session}" with Set/Edit windows (Registration opens/closes, Lectures from/to, Exams from/to, Results due, State). · **Actions** `PUT /pg/calendar/sessions/{s}/{y}`, `POST …/make-current`, `PUT …/semesters/{n}`. · **Messages** "The session name reads like 2026/2027."; "No sessions yet. Set one up to start the PG calendar." · **Note** Windows are informational; nothing enforces them.

> **Screenshot Required:** Postgraduate calendar — `/admissions/postgraduate/calendar` — the sessions table.

#### 4.9.6 Courses (PG catalogue)

```text
Academic → Courses → /admissions/postgraduate/courses
```
**URL** `/admissions/postgraduate/courses` · **Purpose** The School's course catalogue per programme. · **Who** pgschool, pgsecretary (menu); `DESK` hod, academic, pgschool, pgsecretary, super. · **Layout** Programme select; "Upload the course catalogue" (Download template; Upload courses (.xlsx / .csv)); "All postgraduate courses" or the programme's "Courses" (Code, Title, Units, Type, Semester, Status); "Add a course" (Course code, Title, Units, Type Core/Elective/Research/Deficiency, Semester First/Second). · **Actions** `POST /pg/coursework/courses/import`; `POST /pg/coursework/courses`. · **Messages** "{n} courses added, {m} updated · {k} rows had a programme that did not match one on record · {s} skipped."; "The file needs Programme, Course Code and Title columns."

> **Screenshot Required:** Courses — `/admissions/postgraduate/courses` — a programme's course list and the add form.

#### 4.9.7 Course Results (PG)

```text
Academic → Course Results → /admissions/postgraduate/results
```
**URL** `/admissions/postgraduate/results` · **Purpose** Endorse registrations and record CA/exam marks. · **Who** pgschool, pgsecretary (menu); `DESK`. · **Layout** Session text box, Semester, Programme filter; table Student, Programme, Mode, Courses, GPA, Status, Open; detail with "Endorse registration" and per-course CA / Exam inputs with Save (Total and Grade computed). · **Actions** `POST /pg/coursework/registrations/{id}/endorse`; `POST /pg/coursework/score`. · **Messages** "No registration for this session and semester."

> **Screenshot Required:** Course Results — `/admissions/postgraduate/results` — a registration opened with marks.

#### 4.9.8 PG Students register

```text
Students → PG Students → /admissions/postgraduate/students
```
**URL** `/admissions/postgraduate/students` · **Purpose** Every postgraduate with CGPA, standing and research stage; status changes. · **Who** pgschool, pgsecretary (menu); admissions READERS; status SPGS. · **Layout** Clickable tiles PG students / PGD / Master's / Doctoral / On probation; selects Programme, Level, Gender, Entry session, Standing; table Student, Programme, Level, Sex, Status (+ FT/PT), CGPA, Standing, Research stage; editors get an "Action…" select (Defer, Withdraw, Reinstate, Readmit) prompting for the instrument. · **Actions** `POST /pg/students/{id}/status`. 

> **Screenshot Required:** PG Students — `/admissions/postgraduate/students` — tiles and the register.

#### 4.9.9 Research Desk / Research Seminars / Examination Panels

```text
Academic → Research Desk → /admissions/postgraduate/research ; Research Seminars → ?stage=PROPOSAL_APPROVED ; Examination Panels / Panels & Viva → ?stage=DRAFT_SUBMITTED
```
**URL** `/admissions/postgraduate/research?stage=` · **Purpose** The research pipeline and every act on a candidate's record. · **Who** pgschool, pgsecretary (menu); `SCHOOL`. · **Layout** Count tiles; "Research pipeline" table (Candidate, Programme, Kind, Stage, Supervisors, Updated) with a stage select; detail panel: milestone key-values; Supervisors (inline add: name, role First/Second/Co, external); Panel of examiners (inline add with roles); Advance buttons (Record proposal submitted, Approve proposal, Record seminar (+PGSR), Register title (+Originality %), Constitute panel, Record draft submission, Record viva (+Score %, outcome), Corrections required (+due date) / Record final submission, Clear for binding, Recommend to Senate, Record Senate award); Withdraw candidate; "Documents submitted by the candidate" with Accept / Return; Milestones. · **Actions** `POST /pg/research/{id}/supervisor`, `/panel-member`, `/action`, `/documents/{docId}/review`. · **Messages** "Not constituted yet — six for a Master's, seven for a PhD (Policy 24.3)"; "This record is at 'x'; y follows 'z'."; this desk's own award button always fails with `PG_AWARD_MINUTE`.

> **Screenshot Required:** Research Desk — `/admissions/postgraduate/research` — a candidate's detail with the Advance buttons.

#### 4.9.10 School Board

```text
Academic → School Board → /admissions/postgraduate/board
```
**URL** `/admissions/postgraduate/board` · **Purpose** Recommend cleared candidates and record Senate's award. · **Who** pgschool (menu); `SCHOOL`. · **Layout** Tiles Awaiting the Board / With Senate / Awarded; Cleared → Recommend; Recommended → "Senate minute" field + Record Award; "Awarded this session" (every AWARDED row). · **Actions** `POST /pg/research/{id}/action` (RECOMMEND; AWARD with `senateMinute`). · **Messages** "an award is recorded on a Senate minute, and none was cited"; "an award is recorded for a matriculated student; % has no matriculation number".

> **Screenshot Required:** School Board — `/admissions/postgraduate/board` — the Recommended list with the minute field.

#### 4.9.11 Thesis clearance, Registration & matriculation, Course examinations, Results to Senate

```text
Academic → Thesis Clearance → /admissions/postgraduate/clearance ; Registration → /registration ; Course Examinations → /examinations ; Results to Senate → /senate
```
**URLs** `/admissions/postgraduate/clearance`, `/registration`, `/examinations`, `/senate` · **Purpose** The Secretary's desks: clear a final thesis for binding; fresh students' mode, acceptance fee, registration and matriculation link; per-course results recorded / partly / awaited; computed results to Senate and awards. · **Who** pgschool, pgsecretary (clearance); pgsecretary (the other three); `READERS` pgsecretary, pgschool, academic, registrar, dregistrar, super. · **Layout** Clearance: "Awaiting clearance" (Candidate, Programme, Work + topic, Final submitted, Plagiarism pill ≤ 20 % green, Viva pill, "Clear for binding") and "Cleared for binding". Registration: tiles To register / Registered / Part-time / Lapsed; "Fresh postgraduate students" with a Matriculate link to `/matriculation`; "Semester renewal". Examinations: tiles Courses sat / Results recorded / Results awaited / Candidates; per-course states. Senate: tiles To Senate / Awarded / Coursework results / Pending computation; "Computed results to Senate"; "Awarded this session". · **Actions** Clear for binding → `POST /pg/research/{id}/action` (CLEAR); others read-only.

> **Screenshot Required:** Thesis clearance — `/admissions/postgraduate/clearance` — the awaiting list with plagiarism pills.

#### 4.9.12 External Examiners (School roster)

```text
Academic → External Examiners → /admissions/postgraduate/examiners
```
**URL** `/admissions/postgraduate/examiners` · **Purpose** The School's roster of appointed examiners. · **Who** pgschool, pgsecretary. · **Layout** Table Name, Institution, Field, Tenure, Active/Ended; "Appoint an examiner" (Name*, Institution*, Field / specialization, Tenure from, Tenure to). · **Actions** `POST /pg/examiners`. · **Note** No edit, end or deactivate action exists; not linked to panels.

> **Screenshot Required:** External Examiners (roster) — `/admissions/postgraduate/examiners` — the table and the appoint form.

### 4.10 External examiners (University workspace)

#### 4.10.1 External Examiners (register)

```text
Academic → External Examiners → /examiners
```
**URL** `/examiners` · **Purpose** The register, dashboard and creation of examiners. · **Who** academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super (menu); `DESK` (reach by unit). · **Layout** PageHead actions New Examiner, Project Assignments, Reports; Session select; tiles Examiners / Assigned projects / Pending reviews / Submitted; "Overdue reviews"; "The register" (search, status filter; Examiner/email, Institution, Specialisation, Status, Projects, Overdue, Sign-in, Open); "Projects by examiner"; "Reviews by department"; "Recent assignments".

| Field (New External Examiner) | Description | Required | Validation |
|---|---|---|---|
| Title, First name, Middle name, Last name | — | First, Last | — |
| Email | "Becomes the username" | Yes | Regex; unique (`EXAMINER_EXISTS`) |
| Phone, Institution, Department, Position or rank, Area of specialisation, Highest qualification, Professional qualifications | — | Institution | — |
| Years of academic experience | — | No | 0–70 |
| Country (default Nigeria), State or region, ORCID | — | No | — |
| Notes for the desk | "Never shown to the examiner" | No | — |
| Send the invitation email now | "the link works once and for fourteen days" | No | — |

**Actions** Create → `POST /examiners` (then the record). · **Messages** "No external examiner is on the register yet. Record one and send the invitation."

> **Screenshot Required:** External Examiners — `/examiners` — tiles and the register.

#### 4.10.2 Examiner record

```text
/examiners → Open → /examiners/{id}
```
**URL** `/examiners/{id}` · **Purpose** Act on one examiner. · **Who** `DESK`. · **Layout** "Act on the record" buttons; profile grid ("On the PG roster" pill); "CV and photo" with Keep File; tabs Projects / Appointments (End) / History.

| Action | What it does | Endpoint |
|---|---|---|
| Send Invitation / Resend Invitation | New 14-day token; email | `POST /examiners/{id}/invite` |
| Suspend or Deactivate / Set Active | Modal Standing + Reason ≥ 5; ends/re-grants the office | `POST /examiners/{id}/status` |
| Edit Record | All fields | `PUT /examiners/{id}` |
| Record an Appointment | Academic session*, Semester, Examination period, Faculty*, Department*, Programme, Appointment starts*/ends*, Letter or minute | `POST /examiners/{id}/appointments` |
| Keep File | PDF → CV, image → PHOTO, ≤ 5 MB | `POST /examiners/{id}/files` |
| End (appointment) | `window.prompt` | `POST /examiners/appointments/{id}/end` |
| Assign a Project | Link, disabled unless ACTIVE | `/examiners/projects?assign={id}` |

**Messages** "A suspended or inactive examiner is not invited."; "Suspending or deactivating an examiner records the reason."

> **Screenshot Required:** Examiner record — `/examiners/{id}` — the action bar and profile grid.

#### 4.10.3 Examiner Appointments

```text
Academic → Examiner Appointments → /examiners/appointments
```
**URL** `/examiners/appointments` · **Purpose** Appointments by session. · **Who** the ten DESK offices. · **Layout** Session chips; table Examiner (+status), Session, Unit, Programme, From, To, Projects, Status, Open. · **Actions** Read-only.

> **Screenshot Required:** Examiner Appointments — `/examiners/appointments` — the table with session chips.

#### 4.10.4 Project Assignments

```text
Academic → Project Assignments → /examiners/projects
```
**URL** `/examiners/projects?assign=` · **Purpose** Register projects and assign examiners. · **Who** `DESK`. · **Layout** Actions Register a Project, Every Assignment, Assessment Criteria; Session select and Search; table Candidate, Project, Programme, Supervisor, Session, Documents (red when 0), Examiners, Assign, Open.

| Field (Register a Project) | Description | Required | Validation |
|---|---|---|---|
| Candidate | Type-ahead over finalists and postgraduates within reach | Yes | One project per (student, session) |
| Academic session, Project type, Submission date | — | Session | — |
| Project title | Pre-filled from a PG topic | Yes | ≤ 400 |
| Abstract, Keywords, Project course code, Co-supervisor, Supervisor | Supervisor type-ahead or typed | No | Abstract ≤ 8000 |
| Assign: External examiner, Assessment form, Review deadline, Examination date | Active examiners only; default form for the kind | Examiner, Deadline | Deadline ≥ today; active rubric |

**Actions** `POST /examiners/projects`; `POST /examiners/assignments`. · **Messages** "No document released yet"; "This project is with that examiner already."

> **Screenshot Required:** Project Assignments — `/examiners/projects` — the table with an Assign modal.

#### 4.10.5 Project

```text
/examiners/projects → Open → /examiners/projects/{id}
```
**URL** `/examiners/projects/{id}` · **Purpose** Documents release and the project's examiners. · **Who** `DESK` within reach. · **Layout** Project grid; "Documents for external examination" (Release/Withhold toggle; upload row Kind Project proposal / Final project report / Source code / Presentation / Supporting document, File PDF/Word/PowerPoint/ZIP ≤ 25 MB); "Examiners" table; History; "Assign an Examiner" modal. · **Actions** `POST /projects/{id}/documents`; `PUT /projects/{id}/documents/{doc}`; `POST /examiners/assignments`. · **Messages** "Only what is released here reaches an examiner".

> **Screenshot Required:** Project — `/examiners/projects/{id}` — the documents panel with release toggles.

#### 4.10.6 Assessments and one assessment

```text
Academic → Assessments → /examiners/assignments → Open → /examiners/assignments/{id}
```
**URLs** `/examiners/assignments`, `/examiners/assignments/{id}` · **Purpose** Every assignment; extend, reassign, withdraw; read, lock or reopen an assessment. · **Who** `DESK`. · **Layout** Tiles Assignments shown / Pending / Overdue / Submitted; filter bar (Search, Session, Status, Examiner, "Overdue only"); rows with Extend / Reassign / Withdraw / Open. Detail: state note with Approve and Lock / Reopen; panels The assignment, Documents the examiner was given, The assessment (per-section tables, subtotals, comments, Final recommendation), History; "The desk never types a score."

| Action | What it does | Endpoint |
|---|---|---|
| Extend | New deadline*, Reason | `POST /assignments/{id}/deadline` |
| Reassign | New examiner*, Deadline, Reason* ≥ 5 | `POST /assignments/{id}/reassign` |
| Withdraw | Reason* | `POST /assignments/{id}/withdraw` |
| Approve and Lock | SUBMITTED → LOCKED (confirm) | `POST /assessments/{id}/lock` |
| Reopen | Reason ≥ 5; version + 1 | `POST /assessments/{id}/reopen` |

**Messages** "A locked assessment is not reassigned."; "only a submitted assessment is locked".

> **Screenshot Required:** Assessment — `/examiners/assignments/{id}` — the scored sections and the lock button.

#### 4.10.7 Examiner Reports

```text
Academic → Examiner Reports → /examiners/reports
```
**URL** `/examiners/reports?kind=` · **Purpose** Eight report kinds. · **Who** `DESK`. · **Layout** Kind buttons (External Examiner, Project Assessment, Examiner Workload, Department Assessment, Programme Assessment, Pending Review, Overdue Review, Submitted Assessment); filters Session, Faculty, Department, Programme, Examiner, Status, Assigned from/to; table; Download (CSV). · **Messages** "Nothing in this scope yet."

> **Screenshot Required:** Examiner Reports — `/examiners/reports` — the kind buttons and a table.

#### 4.10.8 Assessment Criteria (rubrics)

```text
/examiners/projects → Assessment Criteria → /examiners/rubrics
```
**URL** `/examiners/rubrics` · **Purpose** Forms and criteria (WRITTEN and DEFENCE sections). · **Who** `FORM` academic, dregistrar, pgschool, admin, super (others read-only). · **Layout** One panel per rubric (kind, Active/Inactive, usage); section tables; "Add a Line" (Criterion*, Guidance, Maximum mark*, Section, Order, Active); "New Form" (Name*, For UG/PG, Has a defence section, Note). · **Actions** `POST /rubrics`, `POST /rubrics/{id}/criteria`, `PUT /criteria/{id}`, Set Inactive/Active. · **Messages** "Changing a maximum affects assessments in draft; a submitted assessment keeps the marks it was given."

> **Screenshot Required:** Assessment Criteria — `/examiners/rubrics` — the UG default form.

#### 4.10.9 Examiner Workspace, My Projects, Review, My Profile

```text
External Examiner → Dashboard → /examiner ; My Projects → /examiner/projects ; Start Review → /examiner/projects/{id} ; My Profile → /examiner/profile
```
**URLs** `/examiner`, `/examiner/projects[?filter=pending|submitted]`, `/examiner/projects/{id}`, `/examiner/profile` · **Purpose** The examiner's own assignments, review form and profile. · **Who** extexaminer (ACTIVE). · **Layout** Workspace: "Welcome, {name}"; tiles Assigned projects / Pending reviews / Submitted / Overdue; red overdue note; Upcoming deadlines; Recent assignments; Recently submitted; Your appointment. My Projects: Candidate, Project title ("{n} documents" or "No documents released yet"), Programme, Supervisor, Session, Submitted, Deadline, Status; Start Review / Continue Review / View Assessment. Review: state note; The candidate; The project; Documents (released only); "Assessment · {rubric}" with per-line Score (red "Over {max}") and Comment; "Comments and recommendation" (General comments* ≥ 20, Strengths, Weaknesses, Recommendations, Required corrections, Final recommendation* Pass / Pass subject to corrections / Reassessment required / Fail); History. Profile: read-only record and "Keep current" fields.

| Action | What it does | Endpoint |
|---|---|---|
| Save Draft | Keeps scores and comments | `PUT /examiners/me/projects/{id}/assessment` |
| Submit Assessment / Resubmit Assessment | Enabled when complete; confirm "Submit this assessment?" | `PUT` then `POST …/assessment/submit` |
| Save profile | — | `PUT /examiners/me/profile` |

**Messages** "Total: Computed from the scores; it is not typed."; "Reopened by the University on … {reason}"; "every criterion is scored before submission; still unscored: …". · **Security** Released documents only; notes never returned.

> **Screenshot Required:** Review — `/examiner/projects/{id}` — a section table with scores and the submit button.

### 4.11 Student records, matriculation, deferments, transfers, clearance, graduation

#### 4.11.1 Students / Student Records

```text
Students → Students / Student Records → /students
```
**URL** `/students` · **Purpose** The register in scope; migrated clearance; voluntary withdrawals. · **Who** academic, admin, dean, dregistrar, facultyofficer, hod, ict, registrar (menu); `READERS` (scope bound). · **Layout** Scope bar (faculty, department, programme, level, session); "Find a student" (placeholder "Matriculation number, admission number or name"); table Matriculation no., Name, Programme, Level, Status, Details; for academic/registrar/dregistrar/ict/super: "Migrated from the old portal" (tiles; "Clear the N not yet cleared") and "Voluntary withdrawals" (tiles Due now / Closed so far; "Close all N due", per-row Close). · **Actions** `POST /student/students/migrated/clear?from=100&to=400`; `POST /student/students/voluntary-withdrawals/close {studentIds, instrument}` (instrument "University regulation: four consecutive semesters without course registration"). · **Messages** "Nobody is on the register in this scope"; "Nothing on the register matches “q”".

> **Screenshot Required:** Students — `/students` — the scope bar, the two panels and the register.

#### 4.11.2 Student 360

```text
/students → Details → /students/{id}
```
**URL** `/students/{id}` · **Purpose** One student's whole record. · **Who** `READERS` (any student id); writes academic, registrar, dregistrar; portal account registrar, dregistrar, academic, records, ict, super. · **Layout** Header (passport, name, number, programme, level, entry, status pill); buttons Change status, Correct level, Portal account; cards Finance ("NOT YET SERVED" placeholder), Academic standing (CGPA "—", Units registered), Clearances (eight units); Registration panel; Record history; Biodata sections (Identity, Personal, Contact, Origin & sponsorship, Parents or guardian, Next of kin & guarantor, Health, Bank account, Documents, Change history).

| Field | Description | Required | Validation |
|---|---|---|---|
| Change status: To, Instrument, Reason | Select of statuses; warning that ACTIVE comes from matriculation | Instrument | Non-blank; matric required beyond ADMITTED |
| Correct level: Level, Reason | 100–600 | Reason | Hundreds up to the final year |
| Portal account: first password | Prompt (eight characters) | Yes | ≥ 8; needs a matric number |
| Biodata fields | Badged "From JAMB" (locked) or "Needs approval" | — | Open fields saved; locked refused |

| Action | What it does | Endpoint |
|---|---|---|
| Change status | `people.change_status` | `POST /student/students/{id}/status` |
| Correct level | Plain update (no status_change row) | `PUT /student/students/{id}/level` |
| Portal account | Opens/resets the student account | `PUT /student-auth/accounts/{id}` |
| Save / Save and continue → | Per-field writes | `PUT …/biodata/{field}` |

**Messages** "a change of status is made on an instrument … and none was cited"; "the matriculation number % is permanent and is not changed". · **Security** Readable by every reader for any id.

> **Screenshot Required:** Student 360 — `/students/{id}` — header, the three cards and the Change status modal.

#### 4.11.3 Biodata Changes

```text
Students → Biodata Changes → /students/biodata-changes
```
**URL** `/students/biodata-changes?state=` · **Purpose** Decide requested biodata changes (a queue that stays empty — §3.27). · **Who** academic, registrar (menu); deciders academic, registrar, dregistrar. · **Layout** Tiles Awaiting evidence / Approved / Refused / Self-service changes; table Student, Field, From, To, Evidence, Action. · **Actions** Approve with evidence, Refuse (modal "The decision, in words"), Ask for evidence → `POST /student/biodata-changes/{id}/{decision}`. · **Messages** "You are reading this queue, not deciding on it".

> **Screenshot Required:** Biodata Changes — `/students/biodata-changes` — the empty queue with tiles.

#### 4.11.4 Records & Queries

```text
Students → Records & Queries → /records
```
**URL** `/records?view=` · **Purpose** One scoped workbench over students, registration, fees, results, exams, allocation, clearance, attendance. · **Who** eighteen offices (menu); `READERS`. · **Layout** Tabs students | registration | fees | results | exams | allocation | clearance | attendance over one scope bar (with course and semester). · **Actions** Read; the allocation Assign/Reassign button is disabled ("Course assignment is not on the portal yet"). · **Messages** Fees and attendance return the stale not-served sentences. · **Security** Scope from request parameters only.

> **Screenshot Required:** Records & Queries — `/records?view=registration` — the tab strip and a table.

#### 4.11.5 Migrate from Old Portal

```text
Academic → Migrate from Old Portal → /records/migration
```
**URL** `/records/migration` · **Purpose** Bring students, registration, results, PG records, JAMB numbers, passports and clearance over (§3.57). · **Who** ict, records (menu); `MIGRATE`. · **Layout** Info note "Bring the record over from the old portal"; eleven segmented tabs; per tab a panel with Session (fallback), Semester (fallback), Download template, the upload button with progress ("Reading the file", "Preparing the rows", "Importing n of m"); result tiles and "Imported" note; "N rows had no valid matriculation number and were not uploaded" with "Download the skipped rows"; passports panel "Upload passport photos"; notes "Order matters, and re-uploading is safe" and "How migrated students sign in — no password reset needed"; the clearance tab's migrated panel. · **Actions** `POST /api/v1/results/legacy/{kind}` per batch; passports → legacy passports endpoint; Clear migrated. · **Messages** "This desk is for the ICT Directorate, the Examinations Officer, HODs and Records".

> **Screenshot Required:** Migrate from Old Portal — `/records/migration` — the tab strip and a result note.

#### 4.11.6 Matriculation

```text
Students → Matriculation / Registered Students → /matriculation
```
**URL** `/matriculation?session=` · **Purpose** Faculty lists and the run. · **Who** academic, dregistrar, registrar, facultyofficer (menu); `READERS`; run `RUNNERS`. · **Layout** RoleLine; headline note; "The number follows the configured rule" note; tiles Registered students / Confirmed by Faculty Officers / Faculties outstanding / Numbers issued; "Faculty lists" (Faculty, Faculty Officer, Registered, Confirmed, State, Open); "What the run does" (stale pre-V263 text); "Held back from this run"; "Run matriculation for N students"; sample allocations after a run. · **Actions** Run → `POST /matriculation/sessions/{s}/{y}/run`. · **Messages** "N faculty lists are not confirmed, so the run cannot start"; "nobody on a confirmed list has both paid the fees and registered for %".

> **Screenshot Required:** Matriculation — `/matriculation` — tiles and the faculty lists table.

#### 4.11.7 Faculty list

```text
/matriculation → Open → /matriculation/faculty/{code}
```
**URL** `/matriculation/faculty/{code}?session=` · **Purpose** Query, confirm, issue. · **Who** `OFFICERS`; issue `RUNNERS`. · **Layout** Tiles Registered in the faculty / Under query / To be confirmed / State; table Admission number, Name, Department, Units (red below 18), Fees ("—"), State (Query / For matriculation), actions; "Confirm N students to the Academic Office"; "Export the list" (CSV).

| Field (Query modal) | Description | Required | Validation |
|---|---|---|---|
| Reason | — | Yes | Non-blank |
| Who clears it | Faculty Officer / Bursary / Head of Department / Academic Office | Yes | — |

**Actions** Query → `PUT …/queries/{studentId}`; Withdraw query; Confirm → `POST …/confirm`; Issue number → `POST …/students/{id}/matriculate`. · **Messages** "The X list for S is already confirmed."; "the student has not registered courses for %"; "the school fees for % are not settled". · **Security** No faculty scope in code.

> **Screenshot Required:** Faculty list — `/matriculation/faculty/{code}` — the list with a query pill.

#### 4.11.8 Matriculation number format

```text
Students → Matriculation Number Format → /matriculation/config
```
**URL** `/matriculation/config` · **Purpose** The V263 rule, series, faculty segments, programme codes, recent issues. · **Who** academic, dregistrar, registrar (menu); `CONFIG` + super; readers view only. · **Layout** PageHead with the live pattern and Excel/PDF; warning "N programme(s) are set to carry a code and have none"; tiles Series / Programmes with a code / Carrying none / Numbers issued on record; "The format rule"; "Series" table; "Faculties" table; "Programmes" table with faculty filter and search; "Numbers issued most recently".

| Field | Description | Required | Validation |
|---|---|---|---|
| University code | Default MOAU | Yes | `^[A-Z]{2,6}$` |
| Separator | "/" or "-" | Yes | CHECK |
| Sequence padding | 0–8 | Yes | CHECK |
| Faculty code / Programme code / Year of entry / Sequence | Component checkboxes (Sequence fixed on) | — | — |
| Series: Code, Name, Last number issued, Note, Active | "Moves forward only" | Code, Name | `[A-Z][A-Z0-9_]{1,20}`; never backwards |
| Faculty: Segment, Series | — | — | `[A-Z0-9]{2,6}` |
| Programme: carries a code, Programme code, Own faculty segment, Series | — | — | A code when set to carry one |

**Actions** Save the rule → `PUT /matriculation/config/format`; `PUT …/series/{code}`; `PUT …/faculties/{code}`; `PUT …/programmes/{code}`; exports (serial MAT, S/N first). · **Messages** "Series % has issued up to %; it does not go back."; "The programme is set to carry a code but none is given."

> **Screenshot Required:** Matriculation number format — `/matriculation/config` — the rule panel with live samples and the series table.

#### 4.11.9 Deferments desk, Review, Returns

```text
Students → Deferments → /deferments → row → /deferments/{id} ; Students Due to Return → /deferments/returns
```
**URLs** `/deferments`, `/deferments/{id}`, `/deferments/returns?status=` · **Purpose** Decide deferment requests within the office's bound; confirm returns. · **Who** twelve offices (menu); `DESK` with `may` by stage. · **Layout** Desk: PageHead with Students Due to Return, Download Excel, Download PDF; eight tiles; "Waiting at this desk"; filters Session, Semester, Type, Status, Faculty/Department/Programme, Search; full list; By programme / reason / faculty. Review: breadcrumb; PageHead with pills, Approval Letter, Student Record; "This desk's act" (Comment + buttons); The request; Supporting documents; The student's record; The desks; History. Returns: filter All/Due/Overdue/Upcoming; "Confirm Return" links.

| Action | What it does | Endpoint |
|---|---|---|
| Recommend to the Faculty / Recommend to the Registry / Approve Deferment / Request Correction / Reject / Cancel Request / Confirm Return | `people.deferment_decide` / `deferment_confirm_return` | `POST /deferments/{id}/{act}` |
| Approval Letter | PDF within bound | `/deferments/{id}/letter` |
| Download Excel / PDF | Branded desk list (serial DEF) | — |

**Messages** "Nothing waits at this desk"; "This request is submitted; approve is not this desk's act at that stage."; "This deferment is outside your office's bound…"; "The letter is issued once the deferment is approved."

> **Screenshot Required:** Deferment review — `/deferments/{id}` — "This desk's act" and the student's record panel.

#### 4.11.10 Inter-Departmental Transfer (office) and Memo

```text
Students → Inter-Departmental Transfer → /transfers ; (no menu) /transfers/memo?type=recommended|withdrawn
```
**URLs** `/transfers`, `/transfers/memo` · **Purpose** Approve or decline at each desk; record a paper application; print the SAIC memo. · **Who** academic, hod, registrar (menu); `READERS`; `APPROVERS` stage-checked; `OFFICERS` for paper applications. · **Layout** RoleLine; tiles for the four desks; tabs Current dept / New dept / Registrar / Academic / Completed / Declined / All; table Student, From → To, Entry · UTME · CGPA, Reason, Stage (fee reference paid/unpaid), Approve / Decline; "Record an application" (Student number, Course applied for, Reason, UTME score). Memo: "Recommended List of Inter-Departmental Transfer Candidates" or "Non-Recommended / Withdrawn…" for the DVC (Academic) / Chairman, SAIC, with a print toolbar. · **Actions** Approve → `POST /transfers/{id}/approve`; Decline (prompt) → `…/decline`; Record → `POST /transfers`. · **Messages** "This application is not ready at your desk. Awaiting payment."; "application % has no approval pending at this stage (%)".

> **Screenshot Required:** Inter-Departmental Transfer — `/transfers` — the tabs and a row with Approve.

#### 4.11.11 Clearance

```text
Students → Clearance (label varies) → /clearance
```
**URL** `/clearance?purpose=&student=` · **Purpose** Per-unit clear/hold. · **Who** academic, admin, bursar, dean, dregistrar, hod, library, registrar, services (menu); readers/signers per §3.28. · **Layout** RoleLine; scope bar; tiles Candidates for clearance / Fully cleared / Outstanding at one unit / Outstanding at two or more; "Where candidates are held"; "Candidates" (checkbox, number, name, one ✓/✗ per unit, Cleared/Held); candidate panel (Gates per unit; unit select for multi-unit offices; Clear; Hold modal "What is outstanding"); "What clearance releases"; "Clear the selected candidates"; "Export the held list"; "Notify held candidates". · **Actions** `POST /clearance/students/{id}/{unit}/clear|hold`; `POST /clearance/notify-held` (202, nothing sent). · **Messages** "A hold names the specific item outstanding."; "the Library clears against its own record; hod does not sign for it"; "Nothing was sent".

> **Screenshot Required:** Clearance — `/clearance` — the candidates grid with unit columns.

#### 4.11.12 Graduation

```text
Academic → Graduation / Graduation List / Graduation Records → /graduation
```
**URL** `/graduation?session=` · **Purpose** Degree audit and Senate approval. · **Who** academic, dean, dvc, records, vc (work); pgschool, pgsecretary (menu, refused). · **Layout** RoleLine; scope bar; notes; tiles Finalists / Audit passed / Outstanding requirement / Awaiting clearance; "Degree audit exceptions" (Student, Programme, Unmet requirement, CGPA, Review); "Classification summary" (Class, Students, Share, CGPA range); "Run the degree audit for S"; "Send the list to Senate" (modal Senate minute e.g. "SEN/2027/…"). · **Actions** `POST /graduation/sessions/{s}/{y}/audit`; `…/approve`. · **Messages** "No degree audit has been run for S"; "the graduation list is approved on a Senate minute, and none was cited"; the screen's "checks every curriculum rule" claim is broader than the code.

> **Screenshot Required:** Graduation — `/graduation` — the exceptions table and classification summary.

#### 4.11.13 Alumni Register

```text
Services → Alumni Register → /alumni
```
**URL** `/alumni` · **Purpose** Senate-approved graduands. · **Who** services (menu — refused); readers registrar, dregistrar, academic, records, vc, dvc, audit, deputyaudit, admin, super. · **Layout** Tiles On the register / Graduating sessions / Latest cohort / Showing; search, faculty and session filters (client-side); table Name, Matric number, Programme (award), Faculty, Class, Session. · **Actions** Read-only.

> **Screenshot Required:** Alumni Register — `/alumni` — the table with filters.

#### 4.11.14 Department Staff

```text
Staff → Department Staff → /hod/staff
```
**URL** `/hod/staff` · **Purpose** The department's staff from HR records. · **Who** hod. · **Layout** Tiles Staff on the establishment / Hold a teaching office / Professors; table Name, Rank, No., Sex, Teaching, Status. · **Messages** "Your Head-of-Department office is not tied to a department yet".

> **Screenshot Required:** Department Staff — `/hod/staff` — tiles and the table.

### 4.12 Results, examinations and the question bank

#### 4.12.1 Examination sessions

```text
Academic → Examination Sessions / CBT Sessions / Examinations → /examinations/sessions
```
**URL** `/examinations/sessions` · **Purpose** Create, open and monitor examination sessions. · **Who** academic, records, exams, facultyexams (menu); create/edit/open `EXAMS` records, academic, registrar, dregistrar. · **Layout** Tiles Open sessions / Courses examined / Candidates / Sheets due; "Create an examination session"; "Examination sessions" (Session, Semester, Type, Examinations, Sheets due, Sheets, Outstanding, State; Edit, Open); Edit modal; "Submission monitor" (Faculty, Sheets expected, Submitted, Verified, Past the Board, Outstanding, progress); "The N sheets holding the Faculty of X" with Remind.

| Field | Description | Required | Validation |
|---|---|---|---|
| Academic session, Semester (First/Second/Third), Type (Main / Re-sit / Special) | Fixed once sheets exist | Yes | Unique triple (`EXAM_DUPLICATE`) |
| Examinations begin / end, Score sheets due | Dates | Yes | "The examinations end before they begin." / "The score sheets are due before the examinations end." |

| Action | What it does | Endpoint |
|---|---|---|
| Open the session / Save as a draft | Create (+ open → sheets generated) | `POST /results/exam-sessions` (+ `…/{id}/open`) |
| Save the dates | Edit | `PUT /results/exam-sessions/{id}` |
| Remind / escalate | 202 "nothing was sent" | `POST /results/sheets/{id}/remind` |

**Messages** "N score sheets generated; M courses have no lecturer and generated none."; "Only the dates can change"; `EXAM_CLOSED`.

> **Screenshot Required:** Examination sessions — `/examinations/sessions` — the create panel and the submission monitor.

#### 4.12.2 Score Sheets (list)

```text
Academic → Score Sheets / Score Entry / Upload Results (bulk) / My Score Sheets → /results/sheets
```
**URL** `/results/sheets` · **Purpose** The sheets of the session (a lecturer's own, or every sheet for other offices). · **Who** lecturer, hod, dean, exams, facultyexams, facultyofficer (menu); `READERS`. · **Layout** Filters Session, Semester; table Course, Candidates, Entered (red when short; "N scripts held"), Stage ("N days overdue", "Returned once/N times"), Second examiner, Continue/View; notes "This list is generated from the rolls, not typed beside them" and "A sheet that has left this desk is readable, not editable". · **Messages** "No sheet is assigned to you in this session…".

> **Screenshot Required:** Score Sheets — `/results/sheets` — the list with stage pills.

#### 4.12.3 Score entry (one sheet)

```text
/results/sheets → Continue → /results/sheets/{id}
```
**URL** `/results/sheets/{id}` · **Purpose** Enter, upload, save and attest marks; hold scripts. · **Who** `READERS` (read), `ENTRY` lecturer, exams, academic (write; lecturer must teach it). · **Layout** Header pill ("Complete — not yet submitted" / "Draft — N candidates without a mark" / stage); buttons Download the template, Marked sheet · Excel / · PDF, Upload a completed sheet, Save the draft, Submit and attest; roll table; tiles Candidates / From other programmes / CA out of / Second examiner; notes; "What happens when you attest"; the held-scripts panel.

| Field | Description | Required | Validation |
|---|---|---|---|
| CA — {caMax}, Exam — {examMax} | Per row; Enter/↓/↑ navigation | Both or neither | Within the split ("More than N") |
| Outcome | Graded / Absent / Withheld / Incomplete / Malpractice / Exempted | — | GRADED needs both marks |
| Reason, if amended | Only for a row on the record after a return | For a changed mark | Non-blank |
| Held script: Matriculation number, Outcome, CA, Exam, Note | Placeholder `BSU/SC/CMP/23/70049` | Number | Not on the roll; before the late-registration close |

| Action | What it does | Endpoint |
|---|---|---|
| Save the draft | Writes new score versions; unchanged rows skipped | `PUT /results/sheets/{id}/scores` |
| Upload a completed sheet | Whole-file validation; refused lines listed with "Download Validation Report"; off-roll candidates offered as held scripts | same, plus `…/held/bulk` |
| Submit and attest → I attest these marks | ENTRY → VERIFICATION | `POST /results/sheets/{id}/advance` |
| Hold the script / Withdraw | Held script lifecycle | `POST …/held`, `…/held/{id}/withdraw` |
| Download the template / Marked sheet | xlsx/csv; xlsx/pdf | `/results/sheets/{id}/template`, `/marked?format=` |

**Messages** "N marks are on the record and locked"; "Returned to you — every mark is open for amendment"; "{file} was not accepted — N lines refused, nothing written"; "Published under Senate minute X"; "Late registration has closed for this semester".

> **Screenshot Required:** Score entry — `/results/sheets/{id}` — the roll with marks, the header pill and the attest button.

#### 4.12.4 Score Sheet History

```text
History → Score Sheet History → /results/sheets/history
```
**URL** `/results/sheets/history` · **Purpose** A lecturer's sheets on record. · **Who** lecturer. · **Layout** Tiles Sheets on record / Published / In approval / Still with you; filters Session, Semester, Standing (Not started / In progress / Submitted — in approval / Published); table with Excel/PDF links to the marked sheet and Open/View.

> **Screenshot Required:** Score Sheet History — `/results/sheets/history` — tiles and the filtered table.

#### 4.12.5 Result Desk / Scrutiny Desk / Validation Desk

```text
Academic → Result Desk (label varies) → /results/desk
```
**URL** `/results/desk` · **Purpose** One office's stage of the chain and bulk forwarding. · **Who** hod, dean, facultyexams, facultyofficer, records (menu); `DESKS`. · **Layout** Office description (title, unit, arrives from, leaves for, may not, five "can" bullets) or "This office holds no stage of the result chain"; tiles On this desk now / Not yet arrived / Sent on / Published; "What this office may do"; "On this desk" (Open → chain; "You took the previous stage"); "Not yet arrived" (Stopped at / Waiting on / days late); "Send on to {next}" with "Forward N sets to {next}" (skips blocked sheets and fail rate > 50 %), or at SENATE "Record the Senate minute". · **Actions** Sequential `POST /results/sheets/{id}/advance`.

> **Screenshot Required:** Result Desk — `/results/desk` — "On this desk" and the forward button.

#### 4.12.6 Approvals queue (Results to Senate / Departmental Approvals / Faculty Board / Verification Queue / Senate Business)

```text
Academic → (label varies) → /results/approvals
```
**URL** `/results/approvals` · **Purpose** Approve or return sheets in scope; the HOD's registration approvals (§4.6.1 companion panel). · **Who** academic, dean, exams, hod, registrar, vc (menu); `DESKS`; registration panel for hod, lecturer, dean, facultyofficer, academic, registrar, dregistrar, super. · **Layout** Scope bar with course; tiles Expected sheets / Senate approved / In workflow / Not submitted; table Course (Re-sit/Special pill), Department, Students, Fail rate, Stage ("Not submitted" + lecturer + overdue; "With {who}"; "You approved the previous stage…"; "Fail rate above half the candidates — review before approving"), Action (Remind / Chain / Record Senate minute / Return / Approve / "Not available to you"); modal "Return the sheet to the lecturer" (field "Why it is returned"); panel "Course registrations submitted by students" (Student modal with Code, Course title, Units, Kind, Basis; Programme, Level, Semester, Courses, Units of range, Submitted; Approve / Return with prompt "What must the student change? They read this."). · **Actions** `POST /results/sheets/{id}/advance` / `…/return`; `POST /registration/course-registrations/{id}/approve|return`. · **Messages** "Nothing was sent" (remind); `RES_RETURN_SAYS_WHY`; `REG_RETURN_SAYS_WHY`.

> **Screenshot Required:** Approvals — `/results/approvals` — the sheet queue and the registration panel.

#### 4.12.7 Approval chain

```text
Academic → Approval Chain → /results/chain?sheet=
```
**URL** `/results/chain?sheet=` · **Purpose** One sheet's ladder of decisions and the act at this stage. · **Who** academic, admin, dean, dregistrar, exams, facultyexams, facultyofficer, hod, records (menu); `READERS`; act `DESKS` by `mayAct`. · **Layout** PickSheet list without `?sheet`; tiles Course / Students / Fail rate / "Stage N of 6"; notes (published with "Raise an amendment" and "View as a student" — no handlers; "This stage is yours: {act}" with the approve verb and "Return to the lecturer"; "You performed the previous stage, so this one is not open to you"); the ladder; "What the rules require" (BR-004/BR-006; "engine version … GpaCalculator 2.1"); "Marks on this sheet" (Student, CA, Exam, Total, Grade, Point, "Amended — version N"); modal for the return reason or the Senate minute (placeholder "SEN/2026/…") → "Approve and publish". · **Actions** `POST /results/sheets/{id}/advance` (with `minute` at SENATE), `…/return`.

> **Screenshot Required:** Approval chain — `/results/chain?sheet=` — the ladder and the marks table.

#### 4.12.8 Result pipeline

```text
Academic → Result Pipeline → /results/pipeline
```
**URL** `/results/pipeline?at=n` · **Purpose** Where every set is, stage by stage. · **Who** dean, dregistrar, dvc, facultyexams, facultyofficer, hod, records, super (menu); `READERS`. · **Layout** Nine stages with "What happens here" / "What it cannot pass without"; counts; tiles; "Where every set is now"; note "A set is failing more than half its candidates" → "Open the queue". · **Actions** Links.

> **Screenshot Required:** Result pipeline — `/results/pipeline` — the stage strip with counts.

#### 4.12.9 Broadsheet

```text
Academic → Broadsheet / Broadsheets / Results Broadsheet → /results/broadsheet
```
**URL** `/results/broadsheet` · **Purpose** The Examination reporting sheet by programme, level, session and semester. · **Who** dean, dregistrar, dvc, facultyexams, facultyofficer, hod, records (work); pgschool, pgsecretary (menu, refused); programme bound for department/faculty offices. · **Layout** Scope bar; notes "The broadsheet is computed, not typed" and "A broadsheet is by programme and level…"; tiles Candidates / Mean GPA / Passed every course / Carrying over; "Examination reporting sheet" (cover, Summary of results, Key, Courses, signature blocks) with Download Excel / Download PDF; the sheet table (S/N, MATRIC NO., NAME OF CANDIDATE, course bands, CURRENT CUR/CUE/WGP/GPA, CUMULATIVE TCR/TCE/TWGP/LCGPA/CGPA, REMARKS); lists DIRECT ENTRY STUDENTS, PROBATION LIST / ADVISED TO WITHDRAW; "The grading scheme this sheet used"; "Classification". · **Actions** Exports (Excel two sheets, serial BRD; PDF via print window). · **Messages** Remarks "CO: …", "Fail: …", "TO GO ON PROBATION", "ADVISED TO WITHDRAW", "PENDING", "PASS", "DID NOT REGISTER FOR THIS SEMESTER"; "No approved registration at this level…".

> **Screenshot Required:** Broadsheet — `/results/broadsheet` — the reporting sheet cover and the first rows.

#### 4.12.10 Senate Schedule and Publication

```text
Academic → Senate Schedule → /results/senate ; Publication → /results/publish
```
**URLs** `/results/senate`, `/results/publish` · **Purpose** Record the Senate minute that publishes every set at SENATE in scope; release control. · **Who** records, dregistrar, dvc (senate); records (publish); minute registrar, dregistrar only. · **Layout** RoleLine; notes; tiles; "Senate schedule — {session} {semester} semester" by faculty (Sets, Candidates, At Senate, Published, Outstanding, Recommendation); on Publication the steps "What a release does, in order"; "Record the resolution" / "Release control" (Minute number placeholder "SEN/2026/…", Faculty) → "Record the minute and release" / "Release to candidates on the minute"; outcome note "N sets published under {minute}, M refused" with each refusal; "Minutes recorded". · **Actions** `POST /results/senate/minute {session, sem, fac?, minute}`. · **Messages** "Nothing is waiting at Senate in this scope."; "Nothing is published before the minute exists".

> **Screenshot Required:** Senate Schedule — `/results/senate` — the by-faculty table and the minute form.

#### 4.12.11 Result Queries

```text
Academic → Result Queries → /results/queries
```
**URL** `/results/queries?state=` · **Purpose** Answer students' queries. · **Who** hod, exams (menu); `DEPARTMENT`. · **Layout** Tiles Open / Shown / Corrected / Upheld; filter buttons Open / Answered / All; table Reference, Student, Course, Mark on the sheet, What they said, State, Answer; modal "Answer {ref}" (Finding Upheld / Corrected / Closed; Answer textarea "What was checked and what was found. The student reads this."; a CORRECTED note that correcting the mark is a separate act). · **Actions** Answer on the record → `POST /results/queries/{id}/answer`. · **Messages** "'x' is not an answer to a query."; "a query is answered in words".

> **Screenshot Required:** Result Queries — `/results/queries` — the table and the Answer modal.

#### 4.12.12 Question Bank

```text
Academic → Question Bank → /exams/question-bank
```
**URL** `/exams/question-bank?course=` · **Purpose** Author and retire multiple-choice questions. · **Who** exams (menu); readers/authors per §3.34. · **Layout** Courses table (Code, Title, Questions, Open); with a course: tiles Course / Active questions / Topics / Marks available; Blueprint; Questions (stem, "Answer: …", Topic, Difficulty, Marks, Active/Retired, Retire/Restore); "Author a question" (Question, four options with a "Correct answer" radio, Topic, Difficulty Easy/Medium/Hard, Marks). · **Actions** `POST /cbt/questions`; retire/restore. · **Messages** "A paper is assembled to a blueprint, not picked by hand"; `CBT_OPTIONS`; `CBT_ANSWER`.

> **Screenshot Required:** Question Bank — `/exams/question-bank?course=` — the blueprint and the author form.

#### 4.12.13 Held Scripts (Bursary)

```text
Finance → Held Scripts → /finance/held-scripts
```
**URL** `/finance/held-scripts` · **Purpose** Students a held script is waiting on, with what they owe. · **Who** bursar (menu); owing-list readers. · **Layout** Tiles Students / Scripts held / Still owing / Closing within 14 days; note "What this list is"; table Matriculation number, Name, Programme, Session, Courses held, Closes, Due, Paid, Balance. · **Actions** None. · **Messages** "No script is held anywhere…".

> **Screenshot Required:** Held Scripts — `/finance/held-scripts` — tiles and the table.

### 4.13 College of Health Sciences

#### 4.13.1 College dashboard and MBBS Coordinator dashboard

```text
Overview → Dashboard → /college/dashboard (Provost, College Secretary, Finance Controller) ; → /college/coordinator (MBBS Coordinator)
```
**URLs** `/college/dashboard`, `/college/coordinator` · **Purpose** The College's home; the coordinator's level. · **Who** provost, collegesecretary, financecontroller (the latter sees the Payment Report instead); mbbscoordinator. · **Layout** Dashboard: "Welcome, {name}" with buttons Professional Examinations / Postings / College Calendar / College Overview; StatsPanel; tiles Students / Years open / Awaiting the Board / Postings this session; "What waits on the College"; "The session by level"; "The rotation this session"; "Fees this session"; "Decisions confirmed most recently"; "The MBBS Coordinators"; "The College's desks lately". Coordinator: tiles Level / Cohorts running / Students at the level / Awaiting the Board; "Your doors"; "What waits on you"; "Results by subject"; "Cohorts at N Level". · **Actions** Links.

> **Screenshot Required:** College dashboard — `/college/dashboard` — "What waits on the College" and "The session by level".

#### 4.13.2 College Overview

```text
Academic → College Overview / College of Health Sciences → /college
```
**URL** `/college` · **Purpose** The levels, blocks and postings, the programme rule and progression. · **Who** academic, collegesecretary, financecontroller, mbbscoordinator, provost, records, registrar, super (menu); `READERS`. · **Layout** Tiles; "The levels" (Level, Phase, Students, Years open, Cohorts, Examination, Decisions, Calendar Dated/Undated, Open); "Blocks and postings"; "The programme, from the prospectus"; "Progression, as the rule applies it"; note "Still to confirm with the College". · **Actions** Links.

> **Screenshot Required:** College Overview — `/college` — "The levels" table.

#### 4.13.3 Professional Examinations

```text
Academic → Professional Examinations / Professional Examination → /college/examinations
```
**URL** `/college/examinations?session=&exam=` · **Purpose** Results, CA items, provisional decisions and the Board's confirmation. · **Who** College offices (menu); `EXAMINERS`, `DESK`; coordinator bound to a level. · **Layout** Scope Session, Examination; summary table; exam note (papers, subject weights, conflict notes); year-not-final note; tiles Cohort / Subject results / Decisions / Ready for Senate; "The College Academic Board confirms" (Board minute + "Confirm N decisions"); reconciliation note; "Results by subject"; "Candidates for {code}" with Show filters, "Open the year for a student" (Matriculation number), results CSV, the candidates table; candidate panel (attempt select; Subject / CA / Examination / Clinical / Attendance % / Total / Standing; "Save the {attempt} results"; "CA kept during the year" with Item + Score → Record; "Progression decision" with Decision select, Carry-overs, Board minute, "Change the provisional decision"; "Senate minute" → "Record Senate's approval of the appeal").

| Field | Description | Required | Validation |
|---|---|---|---|
| CA / Examination / Clinical / Attendance % | Per subject | CA and exam | 0–30; 0–70; 0–100 where the subject has a clinical part; 0–100 |
| Board minute | — | To confirm | "the Board confirms on a minute, and none was cited" |
| Decision, Carry-overs (GST / EPS only), Board minute | Override while PROVISIONAL | Decision | `COLLEGE_CONFIRMED`, `COLLEGE_UNDECIDED` |
| Senate minute | Appeal after PE4 | Yes | `COLLEGE_NO_APPEAL` |

**Actions** `POST /college/exams/{code}/results`, `/assessments`, `/exams/{code}/decisions`, `/confirm`, `/appeals`, `/enrol`. · **Messages** "The N Level year for the {session} cohort has not reached its final semester"; "{subject}: CA is out of 30."; "The crossing to Senate is a reconciliation, not a file drop".

> **Screenshot Required:** Professional Examinations — `/college/examinations` — the candidates table and a candidate panel.

#### 4.13.4 Score Sheet (College)

```text
Academic → Score Sheet → /college/scoresheets
```
**URL** `/college/scoresheets?session=&level=` · **Purpose** Workbook download, upload with preview, marked sheet. · **Who** mbbscoordinator (menu); `EXAMINERS`. · **Layout** Scope Cohort, Level; "Score sheets by level"; tiles; "Download the score sheet", "Upload the filled sheet" (preview flags "not in the N Level cohort", "not fully registered", "not a number", "is over", "attendance missing", "clinical mark missing", "barred at x% attendance", "no marks on the row"; Save), "Download the marked sheet"; "Marks entered for this sheet"; "The cohort as it stands". · **Actions** `POST /college/exams/{code}/results/bulk`. · **Warning** Both workbooks carry the letterhead constant "Moshood Abiola University of Science and Technology, Abeokuta" (`ScoreSheets.tsx:18`).

> **Screenshot Required:** Score Sheet — `/college/scoresheets` — the upload preview with flags.

#### 4.13.5 College Calendar

```text
Academic → College Calendar → /college/calendar
```
**URL** `/college/calendar?session=` · **Purpose** Date each level's semesters. · **Who** College offices (menu); edit `DESK`. · **Layout** Session; tiles Levels dated / Years open, undated / Running now / Unsaved changes; "Copy {prev}'s dates, a year on"; "Save all N"; "The session at a glance"; per-level tables (Semester, Weeks, Subjects, Starts, Ends, Standing, Save; "Date from the first semester"); "The University's semesters". · **Actions** `PUT /college/calendar`. · **Messages** "A semester ends after it starts."

> **Screenshot Required:** College Calendar — `/college/calendar` — a level's semester table.

#### 4.13.6 Postings

```text
Students → Postings → /college/postings
```
**URL** `/college/postings?session=&level=&posting=` · **Purpose** Allocate students to postings; run the rotation. · **Who** College offices (menu); `DESK`. · **Layout** Session, Level (≥ 300), Posting; postings table (Block, Posting, Tier, Weeks, Allocated, In progress, Completed, Supervisors, Open/Allocate); "Students at N Level · where each is on the rotation"; with a posting: "Students at this level not yet on it" (search, Tick all, Clear), "Allocate the ticked students" (Rotation group, Supervisor, Starts, Ends), "On {posting} in {session}" (Group, Supervisor, Starts, Ends, Standing; Edit, begin, complete, incomplete, Withdraw; bulk begin/complete). · **Actions** `POST /college/allocations`, `PUT /college/allocations/{id}` (state). · **Messages** "A posting ends after it starts."; "N of the students are not the College's: …".

> **Screenshot Required:** Postings — `/college/postings` — a posting opened with the allocate form.

#### 4.13.7 Logbooks / Supervision

```text
Students → Logbooks / Postings I Supervise → /college/supervision
```
**URL** `/college/supervision?session=&allocation=` · **Purpose** Procedures, cases, attendance and mandatory events per posting. · **Who** College offices, lecturer (menu); `SUPERVISORS` (own posting) or `DESK`. · **Layout** Session, "Student on a posting"; "Supervisors this session"; "The students you supervise"; requirements panels; for one allocation: Procedures (Procedure, Date, Mode Observe/Perform, Patient reference; Verify), Cases clerked, Attendance (Date, Activity, Timetable slot, Present), Mandatory events. · **Actions** `POST /college/allocations/{id}/procedures|cases|attendance|events`, verify. · **Messages** "This posting is supervised by someone else; only the supervisor, or the College's desk, writes its logbook."

> **Screenshot Required:** Logbooks — `/college/supervision` — the procedures panel for one student.

#### 4.13.8 Student Payment Report

```text
Finance/Academic → Student Payment Report / College Payment Report → /college/payments
```
**URL** `/college/payments` · **Purpose** Students' payment position by session or semester. · **Who** bursar, collegesecretary, financecontroller, provost (menu); `PAYMENT_READERS`. · **Layout** Filters Academic session, Period, Department, Programme, Level, Payment status (FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE), Search; tiles; "By programme" with Excel/PDF; "Students" table. · **Export** "Student Payment Report — College of Health Sciences", Summary and by Programme (serial CHSPAY, S/N first).

> **Screenshot Required:** Student Payment Report — `/college/payments` — filters, tiles and the by-programme panel.

#### 4.13.9 College student dashboard

```text
(a CHS student from 200 Level) / → /college/student?view=
```
**URL** `/college/student` · **Purpose** The College student's journey, registration, postings, results. · **Who** student (College). · **Layout** Views Dashboard / Fees & payments / Course registration / Postings & logbook / Results history; "Your journey to the MB.BS"; "{level} Level · {session}" steps with a "Pay … fees" link; Register {semester} / Register N Level · session; "100 Level · Pre-Medical" outcome; latest decision; carry-overs; "The examination ahead"; postings; fees by session; CA recorded; results history. · **Actions** `POST /college/register {session}`. · **Messages** "the N Level fees for {session} are not yet cleared"; "the College's 100 Level rule does not promote: {courses} below 50".

> **Screenshot Required:** College student dashboard — `/college/student` — the journey and the register button.

### 4.14 Finance, expenditure and human resources

#### 4.14.1 Fee Setup and Schedule / Fee Schedules

```text
Finance → Fee Setup and Schedule / Fee Schedules → /finance/fees
```
**URL** `/finance/fees?session=` · **Purpose** Fee lines, structure upload, scheme, reference confirmation, applicant/PG/transfer fees (§3.36). · **Who** bursar, admin (work); financecontroller, pgsecretary (menu, refused); `may` = bursar or super. · **Layout** Tiles Items stated / Charge to everybody / Confirmed this session / References waiting; clearance-scheme note; "The charges for {session}" (Session select, "Add an item", filters Faculty / Semester / Spillover / Per page, Download Excel / Download PDF, table Item / Applies to / Amount with Edit and End); "Upload the approved fees structure"; "Clear the {session} schedule"; "References waiting on the bank's record" (Confirm); "Applicant · Post-UTME fees"; "Postgraduate · application & acceptance fees"; "Inter-departmental transfer · processing fee".

| Field | Description | Required | Validation |
|---|---|---|---|
| Payment item / Item name | Fee item or "Other (type a name)…" | Yes | — |
| Amount | "In naira" | Yes | No format check |
| Session, Semester, Programme group, Level, Entry mode, Faculty, Programmes | Filters ("blank for every…") | — | Level 100–900; semester 1–2 |
| Confirm: Channel, Note | Bank transfer / Bank branch / USSD / Card | Channel | — |
| Scheme: Instrument, From | Placeholder "BUR/2026/04" | Instrument | No overlap |
| Applicant fees: Post-UTME screening fee, Portal and payment charge, Acceptance fee, Admission checking fee | Placeholders 2000 / 300 / 30000 / 0 | Screening fee | Digits |
| PG fees: application, acceptance, checking | Placeholders 20000 / 50000 / 3000 | — | — |
| Transfer processing fee | Placeholder 10000 | — | — |

| Action | What it does | Endpoint |
|---|---|---|
| State the item / Save changes | One POST per ticked programme; edit keeps the first | `POST/PUT /finance/sessions/{s}/{y}/schedule[/{id}]` |
| End | No confirmation | `POST …/schedule/{id}/end` |
| Upload approved fees (.xlsx / .csv) | Replaces the session's structure | `POST …/fee-structure` |
| Clear the schedule | Modal | `POST …/schedule/clear` |
| Confirm the payment | Receipt issued; student told | `POST /finance/references/{ref}/confirm` |
| Put in force | Recommended scheme | `POST /finance/clearance-scheme` |
| State the applicant fees / State the postgraduate fees / Set the transfer fee | — | `PUT /admissions/sessions/{s}/{y}/applicant-fees`; `PUT /pg/sessions/{s}/{y}/fees`; `PUT /finance/transfer-fee` |

**Messages** "No charge is stated for {session}. Until one is, no student owes anything, no reference can be generated, and registration waits."; "Approved fees loaded"; "No clearance scheme is in force, so no payment releases anything"; "Nothing waits. A reference a student generates appears here until the bank's record is matched to it…".

> **Screenshot Required:** Fee Setup and Schedule — `/finance/fees` — the charges table and the item modal.

#### 4.14.2 Payments Query

```text
Finance → Payments Query → /finance/payments
```
**URL** `/finance/payments?…` · **Purpose** Confirmed student payments sliced by faculty, programme, level, category, channel and session. · **Who** bursar (menu); finance READERS. · **Layout** Intro note; "Query" panel (SearchSelects Session, Faculty, Department, Programme, Level 100–600, Payment category, Channel; From, To; "Clear filters"); tiles Payments matched / Total collected / Showing / Scope; "By payment category", "By faculty"; "Payments" (When, Payer, Programme, Level, Category, Channel, Amount, Receipt). · **Actions** Export Excel / Export PDF (branded, serial PAY; rows loaded on the page only). · **Messages** "No confirmed payment matches this query…".

> **Screenshot Required:** Payments Query — `/finance/payments` — filters, tiles and the breakdowns.

#### 4.14.3 Payment History Upload and Old Fees History

```text
Finance → Payment History Upload → /finance/payments-history ; Old Fees History → /finance/legacy-fees
```
**URLs** `/finance/payments-history`, `/finance/legacy-fees` · **Purpose** Load old-portal payment history; clear returning students' past fees. · **Who** bursar (menu); bursar, super, ict, admin / bursar, super, admin. · **Layout** Info notes; "Download template"; file button; preview (legacy, first 200 rows); "Load n rows"; result tiles and an ok note. · **Actions** `POST /finance/payments/import {rows}` in chunks of 400; `POST /finance/legacy-fees {rows}` in chunks of 500. · **Messages** "That file needs at least Matriculation Number and Amount columns."; "Fees history imported"; "{imported} payments were loaded before this batch was refused. The import is idempotent — fix and upload again."

> **Screenshot Required:** Old Fees History — `/finance/legacy-fees` — the preview panel and result tiles.

#### 4.14.4 Payment Gateways

```text
Finance → Payment Gateways → /finance/gateways
```
**URL** `/finance/gateways?paid=` · **Purpose** Providers, keys, routing, webhooks, PayDirect, test. · **Who** bursar, admin, ict (menu); `may` bursar/ict/admin/super, `mayConfigure` ict/admin/super. · **Layout** Info note "A secret key is written once and never read back"; tiles Gateways live / Events today / Settled, all time / Exceptions open; "Configured gateways" (Gateway, Mode, Channels, Webhook address, Status); "Configure the keys" (cards Quickteller, PayDirect, Paystack, Flutterwave); "Quickteller PayDirect" (billers, import); "Test the gateway"; "Webhook and verification log".

| Field | Description | Required | Validation |
|---|---|---|---|
| Secret key (Paystack / Flutterwave) | `sk_test_…` / `FLWSECK_TEST-…` | Yes | Blank refused |
| Webhook secret hash (Flutterwave) | Same value as on the Flutterwave webhook page | For webhooks | — |
| Quickteller: Client ID, Client secret, Merchant code, Pay item ID, Sandbox | Stored together as JSON | All four | `The Quickteller configuration needs clientId, clientSecret, merchantCode and payItemId.` |
| PayDirect: Client ID, Client secret, Sandbox | Query API | — | — |
| Biller code, Name, Pay link (MAIN / CHS) | — | Code, Name | — |
| Collections report rows | PRN, amount, RRN (…) | — | — |
| Test: Student, Amount, Gateway | Default `MOAUM/MTC/24/9903`, 100 | Yes | Live gateway |

| Action | What it does | Endpoint |
|---|---|---|
| Set / Replace the key (configuration, credentials) | Encrypted at rest | `PUT /payments/gateways/{gateway}/key` |
| Clear | Confirm; the gateway turns off unless a service variable is set | `POST …/{gateway}/clear-key` |
| Save (biller) | — | `PUT /payments/paydirect/billers/{scope}` |
| Import and match | Collections report | `POST /payments/paydirect/import` |
| Open a test checkout | Redirects to the gateway | `POST /payments/test-checkout` |
| Verify with the gateway / Ask the gateway now | — | `POST /payments/verify` |
| Run the sweep now | — | `POST /payments/sweep` |
| Resolve (event) | Prompt "How was it resolved? It goes on the record." | `POST /payments/events/{id}/resolve` |

**Messages** "{gw} key set — {mode} key ending {last4}"; "Imported {n}: {m} matched, {u} unmatched, {d} already seen"; "No event has reached the portal yet…"; footer "A callback is a hint, not an instruction".

> **Screenshot Required:** Payment Gateways — `/finance/gateways` — the configured gateways table and a key card.

#### 4.14.5 Hanging Payments

```text
Finance → Hanging Payments → /finance/hanging
```
**URL** `/finance/hanging` · **Purpose** Checkouts with nothing confirmed; events needing a person. · **Who** bursar (menu); `may`. · **Layout** Info note "A payment that succeeded at the gateway has succeeded"; tiles Hanging now / Resolved without a person / Needs a person / The sweep ("Every 10 min", static); "Hanging at a gateway" (Opened, Payer, Reference, Gateway, Amount, Asked; "Ask the gateway"); "Needs a person" (When, Gateway, Reference, Amount, Why it hung; "Resolve"). · **Actions** `POST /payments/verify`; `POST /payments/events/{id}/resolve` (a failure shows nothing — bug). · **Messages** "Nothing is hanging…"; "Nothing waits on a person."

> **Screenshot Required:** Hanging Payments — `/finance/hanging` — the two panels.

#### 4.14.6 Payment Investigation / Cash Office & Assets

```text
Finance → Payment Investigation / Cash Office & Assets → /finance/exceptions
```
**URL** `/finance/exceptions?state=open|posted|all` · **Purpose** Bank credits without a reference: record, propose, approve, reject. · **Who** bursar, admin (menu); `may` bursar, super. · **Layout** Top note ("₦{open} is sitting in the University's account and belongs to somebody" / "No bank credit waits to be attributed"); tiles Open / Proposed, awaiting a second officer / Posted / Cash ceiling (static ₦1,000); state buttons; "Bank credits" (Received, Instrument, Payer named, Amount, State, Resolution); "Record a bank credit"; "Why it is a posting, never an edit". · **Subtitle** static "Unmatched settlement · teller slip BR/44821".

| Field | Description | Required | Validation |
|---|---|---|---|
| Received on, Bank, Teller slip or draft number, Amount, Payer named on the slip, Note | Placeholders "Zenith Bank, Makurdi", "BR/44821" | Bank, Instrument, Amount > 0 | Unique (bank, instrument) |
| Reference to post to, On what evidence | Per unmatched row | Both | Portal reference, unconfirmed, amount ≥ reference |

| Action | What it does | Endpoint |
|---|---|---|
| Record the credit | UNMATCHED | `POST /finance/bank-credits` |
| Propose | PROPOSED | `POST …/{id}/propose` |
| Approve and post | By a different officer; confirms the reference on "Bank branch" | `POST …/{id}/approve` |
| Reject | Prompt; back to UNMATCHED | `POST …/{id}/reject` |

**Messages** "Proposed — a second officer approves"; "Your proposal — another officer approves"; "the officer who proposed a posting does not approve it".

> **Screenshot Required:** Payment Investigation — `/finance/exceptions` — a proposed row and the record form.

#### 4.14.7 Refunds & Credits

```text
Finance → Refunds & Credits → /finance/refunds
```
**URL** `/finance/refunds?refund=` · **Purpose** Maker–checker refunds. · **Who** bursar (menu); `may` bursar, super. · **Layout** Info note; tiles Awaiting approval / Approved, to pay / Paid / All; "Refund requests" (Reference, Payer, Reason, Amount, Stage, Action); "+ Raise a refund".

| Field (Raise a refund) | Description | Required | Validation |
|---|---|---|---|
| From a payment reference + Fetch | Fills payer, amount, reason | No | Confirmed portal reference |
| Paid to, Reason, Amount (₦) | — | Yes | Amount > 0; ≤ paid on the source |
| Bank, Account name, Account (last 4) | Snapshotted | No | No length check |

| Action | What it does | Endpoint |
|---|---|---|
| Raise it | PROPOSED | `POST /finance/refunds` |
| Approve | Not your own | `POST …/{id}/approve` |
| Reject | Prompt | `POST …/{id}/reject` |
| Mark paid | Confirm | `POST …/{id}/pay` |

**Messages** "Awaiting another approver"; "the officer who raised a refund does not approve it"; "a refund of NGN X exceeds the NGN Y paid on Z".

> **Screenshot Required:** Refunds & Credits — `/finance/refunds` — the queue and the raise modal.

#### 4.14.8 Funding Sources

```text
Finance → Funding Sources → /finance/sources
```
**URL** `/finance/sources` · **Purpose** The sources a wallet is funded from. · **Who** bursar (menu); `canEdit` bursar, admin, super. · **Layout** RoleLine; info note; "Funding sources" (Code, Name, Nature, Sponsor, Holding account, Active; Edit; Turn off/on); form "Add a source of income" (Code, Name, Nature Loan / Grant / Own money, Sponsor, Holding account, Sort order, Note); "Funding report" link. · **Actions** `POST /funding/sources`. · **Messages** "Only the Bursary, admin or super administrator can add or change a source of income."

> **Screenshot Required:** Funding Sources — `/finance/sources` — the list and the form.

#### 4.14.9 Sources & Wallets / NELFUND Applicants / Match a Remittance

```text
Finance → Sources & Wallets → /finance/nelfund ; NELFUND Applicants → ?tab=status ; Match a Remittance → ?tab=match
```
**URL** `/finance/nelfund?tab=batches|match|status|withdrawals|sources|report&session=` · **Purpose** NELFUND remittances, suspense, the Fund's decisions, withdrawals, sources, the report. · **Who** bursar (menu); `bursary` bursar/admin/super, `registry` for matching. · **Layout** Session select and tabs; per tab as §3.41.

| Field | Description | Required | Validation |
|---|---|---|---|
| The Fund's reference, Received on, Note, The rows | Placeholder "NLF/2026/0918"; template upload or paste | Reference, rows | matric, name, amount |
| Credit: Matriculation or admission number, Source of the funding, Amount, Reason | — | Number, Amount, Reason | Known source |
| Statement lookup: number | — | — | — |
| Suspense: Number on the register, Evidence, one line | Registry | Both | — |
| Fund's list rows | number, name, decision, reason | — | — |
| Withdrawal: Bank transfer ref | On Mark paid | No | — |

| Action | What it does | Endpoint |
|---|---|---|
| Load and match | Batch | `POST /nelfund/batches` |
| Credit the wallet | Attributed credit | `POST /nelfund/credit` |
| Show the history / Reset wallet to zero | Statement; destructive reset (confirm + reason) | `GET /nelfund/student/statement?number=`; `POST /nelfund/reset` |
| Credit (suspense) / Reverse | Match by hand / reverse to the Fund | `POST /nelfund/rows/{id}/match`, `…/reverse` |
| Load the list | Fund's decisions | `POST /nelfund/status` |
| Approve / Decline / Mark paid | Withdrawals | `POST /funding/withdrawals/{id}/approve|reject|pay` |
| Save the source | Duplicates `/finance/sources` | `POST /funding/sources` |

**Messages** "{ref}: {matched} matched, {unmatched} in suspense, ₦amount"; "{n} row(s) are money the University is holding that a student cannot see"; "The wallet reconciles with school payments" / "does not reconcile — investigate".

> **Screenshot Required:** Sources & Wallets — `/finance/nelfund` — the remittances tab with the suspense note.

#### 4.14.10 Reconciliation

```text
Finance → Reconciliation → /finance/reconcile
```
**URL** `/finance/reconcile` · **Purpose** Attest confirmed payments against the bank; see exceptions. · **Who** bursar, admin, audit (menu); `canCheck` bursar, audit, deputyaudit, super. · **Layout** Server tiles Gateway settled / Matched / Exceptions / Hanging; client tiles Confirmed in the window / Matched to the bank / Discrepancies / Not yet checked; "Confirmed payments to reconcile" (From/To; Reference, When, Payer, Amount, Bank / status, Action); "Exceptions requiring action"; "The other exception types, and how each resolves". · **Actions** Matched (prompt for the bank reference) / Flag (note required) → `POST /finance/reconciliation/{ref}/check`. · **Messages** "{ref} recorded as matched to the bank|a discrepancy"; a client bug fires an error toast on every successful load.

> **Screenshot Required:** Reconciliation — `/finance/reconcile` — the ledger with pills and the exceptions panel.

#### 4.14.11 Transactions & Accounts (day book)

```text
Finance → Transactions & Accounts / Ledger → /finance/ledger
```
**URL** `/finance/ledger?from=&to=` · **Purpose** Payment history and the day book. · **Who** bursar, admin, audit (menu); finance READERS; Refund link bursar, super. · **Layout** Tiles Collected / By card / By bank / From the wallet; "Filter" (From, To, Apply, "Export the journal"); "Transactions" (Reference, When, Payer, Purpose, Channel, Amount, Receipt, Refund). · **Actions** Export (branded xlsx despite the `.csv` name); Refund → `/finance/refunds?refund=`.

> **Screenshot Required:** Transactions & Accounts — `/finance/ledger` — tiles and the transactions table.

#### 4.14.12 Accounting & Books

```text
Finance → Accounting & Books → /finance/accounting
```
**URL** `/finance/accounting` · **Purpose** The general ledger. · **Who** bursar, admin (menu); `may` bursar, super. · **Layout** RoleLine; tiles Cash & bank on the books / Income this year / Expenditure this year / Surplus (deficit); sync note; tab bar Overview / Trial balance / Income & expenditure / Balance sheet / Journal book / Account ledger; "New journal", "Sync".

| Field (Post a journal) | Description | Required | Validation |
|---|---|---|---|
| Date, Narrative | Placeholder "e.g. Opening balances 2025/2026" | Narrative | ≤ 300 |
| Lines: Account, Debit, Credit | ≥ 2 lines; typing one clears the other | Yes | Balanced (|Dr−Cr| < 0.005); postable account |
| Reverse: Reason | — | Yes | ≤ 300 |

**Actions** Post them now / Sync → `POST /finance/accounting/sync`; Post the journal → `POST …/journals`; Reverse → `POST …/journals/{id}/reverse`; Show (account ledger) → `GET …/ledger?account&from&to`. · **Messages** "Debits must equal credits before you can post."; "No postings yet. Run Sync to bring the cash records onto the books."; "A reversal, not a delete".

> **Screenshot Required:** Accounting & Books — `/finance/accounting` — the trial balance tab and the journal modal.

#### 4.14.13 Budget

```text
Finance → Budget / Faculty Budget → /finance/budget
```
**URL** `/finance/budget?year=` · **Purpose** Cost-centre budgets with commitment accounting. · **Who** bursar, vc (work); dean (menu, refused); `may` bursar, super. · **Layout** Info note; Financial year select; "+ Set a cost centre's budget"; tiles Budget / Committed / Spent / Over budget; "Budget performance by cost centre" (Cost centre, Budget, Committed, Spent, Available, Utilisation); "Income and expenditure" against budget. · **Fields** Cost centre (required), Budget (₦) ≥ 0. · **Actions** Set the budget → `POST /expenditure/budget`. · **Subtitle** static "Financial year 2026".

> **Screenshot Required:** Budget — `/finance/budget` — the performance table with utilisation bars.

#### 4.14.14 Tenders

```text
Finance → Tenders → /finance/tenders
```
**URL** `/finance/tenders?t=` · **Purpose** Tenders, bids, scoring, award. · **Who** bursar (work); services (menu, refused); `may` bursar, super. · **Layout** Info note; tiles Open tenders / Awarded / All / (empty placeholder tile); "+ Open a tender"; "Tenders" (Reference, Subject, Estimate, Method, Bids, Stage; Evaluate); selected tender panel (bids table Bidder, Technical, Bid price, Responsive, Rank, Action; "+ Record a bid"; "Cancel the tender").

| Field | Description | Required | Validation |
|---|---|---|---|
| What is being procured, Estimate (₦), Cost centre, Technical threshold (%) | Threshold default 70 | Subject, Estimate > 0 | Method from the estimate |
| Bidder, Bid price (₦) | — | Yes | Price > 0 |
| Score: technical score, reason if not responsive | Prompts | Score | Reason when below threshold |

**Actions** Open it → `POST /expenditure/tenders`; Record it → `…/{id}/bids`; Score → `…/bids/{bid}/score`; Award (prompt when a lower responsive bid exists; confirm) → `…/{id}/award`; Cancel the tender → `…/{id}/cancel`.

> **Screenshot Required:** Tenders — `/finance/tenders?t=` — a tender with its ranked bids.

#### 4.14.15 Requisitions

```text
Finance → Requisitions → /finance/requisitions
```
**URL** `/finance/requisitions` · **Purpose** Procurement requisitions by value. · **Who** dean (menu, raise); hod, services (menu, refused); `mayRaise` bursar, ict, registrar, hrm, dean, super; `mayApprove` bursar, super. · **Layout** Info note; tiles Awaiting approval / Approved / PO / Value awaiting / Requisitions; "Requisitions" (Reference, Item, Cost centre, Value, Method, Stage, Action); "Raise a requisition" (Item, Cost centre, Description, Value (₦) with the method shown live). · **Actions** Raise it → `POST /expenditure/requisitions`; Approve / Reject (prompt) / Raise PO / Close → `…/{id}/approve|reject|po|close` (no confirmations). · **Messages** "This requisition cannot be approved by you."

> **Screenshot Required:** Requisitions — `/finance/requisitions` — the table and the raise form.

#### 4.14.16 Payment Vouchers / A Voucher in Full

```text
Overview → Payment Vouchers → / (audit) ; Finance → A Voucher in Full / Payment Vouchers → /vouchers
```
**URL** `/vouchers` · **Purpose** The pre-payment audit chain. · **Who** audit, bursar (menu); readers/actors per §3.44; `isBursar` bursar, super; `isAudit` audit, deputyaudit, super. · **Layout** Headline note; tiles On the audit desk / Queries open / Cleared to pay / All; "+ Raise a voucher" (Bursar); "Payment vouchers" (Voucher, What it is, Amount, Stage, Action).

| Field (Raise a voucher) | Description | Required | Validation |
|---|---|---|---|
| What it is for, Payee | Placeholder "TetFund laboratory block — first certificate" | Yes | ≤ 200 |
| Amount (₦) | Not filtered | Yes | > 0 |
| Kind, Source, Cost centre | Salary/Contract/Overhead/Claim/Grant; IGR/SUBVENTION/TETFUND/GRANT/OTHER | Kind, Source | — |

| Action | What it does | Endpoint |
|---|---|---|
| Raise it | WITH_DIRECTOR | `POST /expenditure/vouchers` |
| Sign & advance | Next desk (prompt for a note) | `POST …/{id}/advance` |
| Query / Answer query | Blocks / unblocks | `POST …/{id}/query`; `POST /vouchers/queries/{qid}/answer` |
| Reject | Prompt | `POST …/{id}/reject` |
| Mark paid | CLEARED → PAID (confirm) | `POST …/{id}/pay` |

**Messages** "Voucher {ref} raised — with the Director of Audit"; "You have acted on this one"; "no person acts twice on a voucher (BR-006)"; "this desk is signed by audit, not by <office>".

> **Screenshot Required:** Payment Vouchers — `/vouchers` — the queue with stage pills and the raise modal.

#### 4.14.17 Stores & Assets / Stock & Acquisitions

```text
Services → Stores & Assets / Stock & Acquisitions → /stores
```
**URL** `/stores` · **Purpose** Inventory and the fixed-asset register. · **Who** library, services (menu — both refused); writes bursar, super; verify also audit, deputyaudit. · **Layout** Tiles Inventory items / Below reorder / Fixed assets / Not verified in a year; tabs Inventory (Code, Item, Quantity, Reorder, Location, Adjust; "Add an inventory item") and Fixed assets (Tag, Asset, Location, Cost, Condition, Last verified, Verify, Condition; "Add a fixed asset"). · **Fields** Item: Code*, Item*, Unit, Opening quantity, Reorder level, Location; Asset: Asset tag*, Asset*, Category, Location, Acquired on, Cost (₦). · **Actions** `POST /stores/items`, `…/{id}/adjust` (prompt; unvalidated), `POST /stores/assets`, `…/{id}/verify`, `…/{id}/condition` (prompt GOOD / FAIR / POOR / DISPOSED).

> **Screenshot Required:** Stores & Assets — `/stores` — the fixed assets tab.

#### 4.14.18 Payroll

```text
Finance → Payroll → /payroll
```
**URL** `/payroll?run=` · **Purpose** Build, approve, pay and cancel monthly runs. · **Who** bursar, hrm (menu); `may` hrm, super. · **Layout** RoleLine; intro note; tiles Runs / Awaiting approval / Approved, to pay / Last net paid; "Build a run" (Month, Note); "Pay runs" (Month, Staff, Gross, Deductions, Net, Stage, Action); run detail "Payslips · {Month}" (tiles; Staff, Grade, Basic, Allowances, Gross, Pension, PAYE, Net). · **Actions** Build the run → `POST /payroll/runs`; Approve (not your own) → `…/{id}/approve`; Mark paid (confirm) → `…/{id}/pay`; Cancel (prompt) → `…/{id}/cancel`. · **Messages** "{n} payslips built — gross ₦x, net ₦y"; "A month is run once…"; "This run has no payslips — no staff were active on the establishment when it was built."

> **Screenshot Required:** Payroll — `/payroll` — the runs table and a run's payslips.

#### 4.14.19 Payroll Variance

```text
Finance → Payroll Variance → /payroll/variance
```
**URL** `/payroll/variance?period=` · **Purpose** This run against the last, explained by movements. · **Who** audit (menu); payroll readers. · **Layout** Note; Month select; tiles Joined / Left / Changed / Net change; "What moved" (Staff, Grade, Movement, Last month, This month, Change). · **Messages** "Nothing moved…"; "Select a month."

> **Screenshot Required:** Payroll Variance — `/payroll/variance` — tiles and the table.

#### 4.14.20 Staff Records (establishment)

```text
Staff → Staff Records → /staff
```
**URL** `/staff` · **Purpose** The establishment roll. · **Who** hrm (works); registrar, housing (menu, refused); payroll readers. · **Layout** Tiles On the roll / Academic / Non-academic / Monthly gross; "Establishment" (Staff, Grade, Category, Monthly gross, Bank ····last4, Status); note "The payroll is built over this roll". · **Actions** Name opens the staff record modal.

> **Screenshot Required:** Staff Records — `/staff` — tiles and the roll.

#### 4.14.21 Leave Requests

```text
Staff → Leave Requests → /hr/leave
```
**URL** `/hr/leave` · **Purpose** Decide staff leave. · **Who** hod, hrm (menu); approvers hrm, hod, dean, dregistrar, registrar, audit, admin, super (HOD scoped by home department). · **Layout** Tiles Awaiting decision / On leave today / Approved / Requests; tabs Awaiting / Approved / Declined / All; "Leave requests" (Staff, Type, Period, Days, Cover, Stage, Action). · **Actions** Approve → `POST /hr/leave/{id}/decide {approve:true}`; Decline (prompt) → same with the note. · **Messages** "{name}'s leave approved"; "the annual-leave balance does not cover N days".

> **Screenshot Required:** Leave Requests — `/hr/leave` — the Awaiting tab.

#### 4.14.22 Open a Movement

```text
Staff → Open a Movement → /hr/movements
```
**URL** `/hr/movements` · **Purpose** Staff movements from request to instrument. · **Who** hrm (menu); `mayOfficer` hrm, registrar, super; `mayApprove` + dregistrar, vc, dvc. · **Layout** Note "Approved is not implemented until the instrument exists"; tiles Awaiting approval / Approved no letter / Implemented / Movements; tabs Awaiting / To issue / Implemented / All; "Staff movements" (Staff, Movement, What changes, Effective, Stage, Action); "Open a movement".

| Field | Description | Required | Validation |
|---|---|---|---|
| Staff number | Placeholder "MOAUM/STAFF/016" | Yes | Existing employment |
| Movement type | 17 kinds (default Promotion) | Yes | — |
| Effective from | Date | Yes | — |
| New grade and step / What it changes | Per kind | One | Seeded grade/step |
| Reason / minute | Optional | No | — |

**Actions** Open the movement → `POST /hr/movements`; Approve → `…/{id}/approve`; Decline (prompt) → `…/{id}/decline`; Issue instrument (confirm) → `…/{id}/issue` (`MOAUM/R/ACA/YYYY/NNNN`). · **Messages** "Movement opened — it goes to a second officer"; "Instrument {instrument} issued — the record is changed".

> **Screenshot Required:** Open a Movement — `/hr/movements` — the tabs and the form.

#### 4.14.23 Recruitment

```text
Staff → Recruitment → /hr/recruitment
```
**URL** `/hr/recruitment?vacancy=` · **Purpose** Vacancies and scored applicants. · **Who** hrm, registrar (menu); `may` hrm, registrar, super. · **Layout** Tiles Open vacancies / Applications / Shortlisted / Posts; "Vacancies" (Post, Department, Applications, State, Action Open / State); "Advertise a vacancy" (Post, Department, Advertised criteria, Grade, Category, Closes on); vacancy view with candidates (Candidate, Qualification, Pubs, Teaching, Score, Stage; Score, Shortlist) and "Record an application" (Candidate name*, Qualification, E-mail, Phone, Publications, Teaching years). · **Actions** `POST /hr/vacancies`, `…/{id}/state` (free-text prompt), `…/{id}/applicants`, `POST /hr/applicants/{id}/assess`. · **Note** No Invite, Offer, Reject or Appoint buttons; subtitle static "2026 cycle".

> **Screenshot Required:** Recruitment — `/hr/recruitment` — the vacancies list and the advertise form.

#### 4.14.24 Appraisal & promotion

```text
Staff → Appraisal → /hr/appraisal
```
**URL** `/hr/appraisal?cycle=` · **Purpose** APER appraisal and the promotion view. · **Who** hod, hrm (menu); `may` hrm, registrar, dean, hod, super. · **Layout** Note "Promotion eligibility is computed, not argued"; tiles On the establishment / Meet the years rule / Appraised this cycle / Academic; "Promotion candidates" (Staff, Grade, Years on grade, APER, Pubs, Eligibility); "Record an appraisal" (Staff number, APER grade A–E, Publications, Self score, Supervisor score, Note). · **Actions** Record the appraisal → `POST /hr/appraisal` (state MODERATED). · **Note** Scores not capped at 100 client-side; subtitle static "2026 exercise".

> **Screenshot Required:** Appraisal & promotion — `/hr/appraisal` — the candidates table and the form.

### 4.15 Hostel accommodation

#### 4.15.1 Accommodation desk (Hostel Dashboard)

```text
Accommodation → Hostel Dashboard → /hostel   (Support Services: Students → Hostel Accommodation)
```
**URL** `/hostel?session=` · **Purpose** The session's window, tiles, charts and the two runs. · **Who** housing, services (menu); `OFFICE` + registrar, admin, super by URL; `READERS`. · **Layout** PageHead "Accommodation" with Session select and buttons Window & Rules, Inventory, Applications, Occupancy, Checkout & Clearance; window notice with state pill; twelve tiles; "Waiting at this desk"; seven charts; "Occupancy by hostel, in figures" with Excel/PDF. · **Actions** Generate Allocation (modal with preview; Published seed ≥ 6 for BALLOT) → `POST /hostel/sessions/{s}/{y}/draw`; Lapse expired holds → `…/lapse`; "State the window" link. · **Messages** "{allocated} allocated · {unsuccessful} waitlisted · {priority} by priority"; "{n} hold(s) lapsed and passed on"; "No window is stated for {session}".

> **Screenshot Required:** Accommodation desk — `/hostel` — the window notice, tiles and "Waiting at this desk".

#### 4.15.2 Application window & rules

```text
Accommodation → Application Window & Rules → /hostel/window
```
**URL** `/hostel/window?session=` · **Purpose** Fee, dates, method, eligibility and rules. · **Who** housing (menu); `OFFICE`.

| Field | Description | Required | Validation |
|---|---|---|---|
| Accommodation fee (₦) | "Zero is a fee; blank is not." | Yes | ≥ 0 |
| Hold window (hours) | "A bed is held this long for payment" | Yes | 1–720 |
| Maximum applications, Applications open/close, Window state, Stay from/to | Draft / Open / Closed / Allocated | — | — |
| Allocation method | BALLOT, FIRST_COME, LEVEL, FACULTY, PROGRAMME, SPECIAL_NEEDS, MANUAL | Yes | "'X' is not an allocation method." |
| The desk reviews each application before allocation; Keep a waiting list | Checkboxes | — | — |
| Student status, Levels, Faculties, Kinds of hall, Course registration submitted, No unsettled hostel damage charge or uncleared stay | Eligibility | — | — |
| Hostel rules and regulations | Textarea ≤ 20000; "Version N — a change makes a new version" | — | — |

**Actions** Save the window / Create the window; Save and open applications; Save and close applications → `PUT /hostel/sessions/{s}/{y}/window`. · **Messages** "Window saved" / "Window opened|closed"; "You are reading this window"; "The allocation has been made — the method and the seed are on the record…".

> **Screenshot Required:** Application window — `/hostel/window` — the fee/dates panel and the eligibility panel.

#### 4.15.3 Hostel inventory

```text
Accommodation → Hostel Inventory → /hostel/inventory
```
**URL** `/hostel/inventory?session=` · **Purpose** Halls, blocks, rooms, beds, facilities, assets. · **Who** housing (menu); `OFFICE`. · **Layout** Hostel filter; buttons Add a hostel, Add a block, Add a room, Generate rooms, Excel, PDF, Bed list (Excel); tiles Beds / Occupied / Reserved / Available / Maintenance; tables Hostels, Blocks and floors, Rooms (S/N, hostel, block, floor, room, type, capacity, occupied, available, maintenance, state; Edit, Facilities, Close/Reopen), Assets.

| Field | Description | Required | Validation |
|---|---|---|---|
| Hostel: Code, Type, Name, Gender, Campus, Location, Description | Code upper-cased | Code, Name | `^[A-Z0-9]{2,8}$` |
| Block: Hostel, Block code, Name, Floors | — | Code | ≤ 12; floors 1–30 |
| Room: Hostel, Block, Floor, Room number, Capacity (beds), Room type, Gender restriction, State, Note | Beds numbered from the capacity | Block, Room number, Capacity | 1–12 |
| Generate rooms: Hostel, Block, Floor, Number prefix, From, To, Beds per room, Room type | ≤ 500 per run | Block | Lower to higher |
| Asset: Asset tag, Asset type, Hostel, Room, Quantity, Condition, Date acquired, Value, Note | — | Tag, Type | — |
| Close/Reopen: State (room), Reason | — | Reason when closing | — |
| Facilities: quantity per facility | 0 removes | — | — |

**Actions** `PUT /hostel/halls-full`, `/blocks`, `/rooms-full`, `/assets`; `POST /hostel/rooms/generate`; `POST /hostel/close?session=`; `PUT /hostel/rooms/{id}/facilities`. · **Messages** "Room saved; beds numbered"; "{n} occupant(s) are affected by the closure".

> **Screenshot Required:** Hostel inventory — `/hostel/inventory` — the rooms table and the room modal.

#### 4.15.4 Applications & waitlist

```text
Accommodation → Applications & Waitlist → /hostel/applications
```
**URL** `/hostel/applications?state=&…` · **Purpose** Review, seat, reject, correct, withdraw. · **Who** housing (menu); `OFFICE`. · **Layout** Filters Standing, Faculty, Department, Programme, Level, Search; "Waiting list" title with draw Position when `state=WAITLISTED`; rows (checkbox, S/N, Application/Position, Student, Programme, Preference, Eligibility, Standing, Allocation, actions); bulk Approve N / Waitlist N / Reject N; Download Excel / PDF.

| Action | What it does | Endpoint |
|---|---|---|
| Approve / Reject / Correction / Waitlist (row or bulk) | Review (reason for REJECTED/CORRECTION — "Say why.") | `POST …/applications/{id}/review`, `…/review-bulk` |
| Allocate | Free bed (by sex) + Reason | `POST …/applications/{id}/allocate` |
| Withdraw | — | `POST …/applications/{id}/withdraw` |
| History | Modal | — |

**Messages** "Allocated · {reference}"; "No application matches. Widen the filters."; "application % has not been approved at review".

> **Screenshot Required:** Applications & waitlist — `/hostel/applications` — the filter bar and rows with pills.

#### 4.15.5 Occupancy & check-in

```text
Accommodation → Occupancy & Check-in → /hostel/occupancy
```
**URL** `/hostel/occupancy?view=&…` · **Purpose** The bed board and student views. · **Who** housing (menu); `READERS`. · **Layout** Views Beds / Students / To check in / Checkout requested; filters Hostel, Block, Status, Faculty, Department, Programme, Level, Gender, Search; Excel/PDF; bed rows (room opens a room modal with facilities, assets, beds and occupants, maintenance, previous occupants); student rows with "Check in" or "Open". · **Actions** Links to the allocation page. · **Messages** "There are currently no beds matching these filters."

> **Screenshot Required:** Occupancy — `/hostel/occupancy` — the bed board with a room modal open.

#### 4.15.6 One allocation

```text
/hostel/occupancy → Open / Check in → /hostel/allocations/{id}
```
**URL** `/hostel/allocations/{id}` · **Purpose** Everything about one stay. · **Who** `OFFICE` (act), `READERS`. · **Layout** Header with state pill; action buttons; notices; panels The stay, Roommates, Inspections, Damage charges (Waive), Hostel clearance {ref} (items Clear / Hold / Waive / N/A; Complete clearance; Reopen; "Start clearance without inspection"), Transfer requests, Trail.

| Field (modals) | Description | Required | Validation |
|---|---|---|---|
| Check in: Condition, Remarks | Good/Fair/Damaged | — | Fee confirmed; rules accepted |
| Transfer: Free bed, Reason | — | Both | Same checks as seating |
| Cancel: Reason | — | Yes | Not CHECKED_IN |
| Checkout inspection: condition, cleanliness, Keys returned, Access card returned, Damages found, Remarks | — | — | CHECKED_IN |
| Damage charge: Asset, Damage, Estimated repair cost, Replacement cost, Charge to the student | "A charge above zero becomes a payment reference…" | Damage, Charge | ≥ 0 |
| Requirement: Remarks | For NOT_CLEARED / WAIVED | — | — |
| Transfer decision: Bed to move to / Reason | — | One | — |

**Actions** `POST /hostel/allocations/{id}/checkin|transfer|cancel|inspect|charge`; clearance item and completion endpoints; `POST /hostel/transfers/{id}`. · **Messages** "Inspection recorded; clearance opened"; "% requirement(s) still pending"; "a student checked in leaves through inspection and clearance".

> **Screenshot Required:** Allocation — `/hostel/allocations/{id}` — the action bar and the clearance panel.

#### 4.15.7 Checkout & clearance

```text
Accommodation → Checkout & Clearance → /hostel/clearance
```
**URL** `/hostel/clearance?session=` · **Purpose** Clearances, checkout requests, transfer requests, maintenance. · **Who** housing (menu); `OFFICE`. · **Layout** Tabs Clearances (n) / Checkout requests (n) / Transfer requests (n) / Maintenance (n); filters and search; Excel/PDF per tab; maintenance Update modal (State Raised/Assigned/Fixed/Closed, Priority, Assigned to, Note to the student). · **Actions** `POST /hostel/maintenance/{id}/update`; links to allocations. · **Messages** "No clearance record for {session}… A clearance starts at the checkout inspection."

> **Screenshot Required:** Checkout & clearance — `/hostel/clearance` — the Clearances tab.

#### 4.15.8 Student accommodation history

```text
/hostel/allocations/{id} → Accommodation history → /hostel/students/{id}
```
**URL** `/hostel/students/{id}` · **Purpose** Every session's stay, damage charges and trail for one student. · **Who** `READERS`. · **Layout** Read-only tables; link "Student record".

> **Screenshot Required:** Accommodation history — `/hostel/students/{id}` — the history table.

### 4.16 ICT help desk, Help & Requests, clinic

#### 4.16.1 ICT Support Desk (queue)

```text
Overview/Administration → ICT Support Desk → /helpdesk
```
**URL** `/helpdesk?…` · **Purpose** The agents' queue. · **Who** ictagent, ict, admin, super; `AGENTS`. · **Layout** KPI tiles Total tickets / New / Opened / In progress / Unassigned / High priority / Overdue / Average resolution; "With you"; filter bar (Search, Status, Category, Priority, Agent, Raised from / To; Search, Clear); queue with sort buttons (Updated / Raised / Priority / Status / Due / Number) and rows (Ticket, Requester, Category, Subject, Priority, Status, Agent, Due, Raised/updated, Take, Open); pager; "Lately on the desk"; Director-only "Agent workload" and "Tickets by category"; actions Reports and Analytics, Categories and SLAs, My Own Tickets. · **Actions** Take → `POST /helpdesk/tickets/{id}/assign {agentId: me}`.

> **Screenshot Required:** ICT Support Desk — `/helpdesk` — the KPI tiles and the queue.

#### 4.16.2 The desk's ticket

```text
/helpdesk → Open → /helpdesk/tickets/{id}
```
**URL** `/helpdesk/tickets/{id}` · **Purpose** Act on a ticket (opening the page opens a SUBMITTED ticket). · **Who** `AGENTS`. · **Layout** "Act on the ticket" (Accept the Ticket / Take It Over, Assign to an Agent / Reassign, Start Work, Resolve, Close as Resolved, Reopen, Escalate, priority select, Close on a Reason); due/first-response text; resolution note; Requester (with "Open the Student Record"), Issue details, Attachments (upload, "Internal (the requester does not see it)"), Conversation and history (Internal Note / Update to the Requester).

| Field | Description | Required | Validation |
|---|---|---|---|
| Assign: Agent, Note | Agents with open load | Agent | `is_agent` |
| Resolve: Resolution summary, Resolution details | — | Yes | ≥ 5 ≤ 300; ≥ 20 ≤ 8000 |
| Reopen / Close on a Reason / Escalate: Reason | — | Yes | ≥ 5 |
| Escalate to | Agents other than yourself, director first | Yes | — |
| Message | Internal Note or Update | Yes | "an update says something" |

**Actions** `GET /helpdesk/tickets/{id}` (auto-open); `POST …/assign`, `/status`, `/resolve`, `/reopen`, `/escalate`, `/priority`, `/comments`, `/attachments`. · **Messages** "a ticket is resolved from in progress; this one is …"; "a closed ticket is not assigned"; "the ticket is with that agent already".

> **Screenshot Required:** Desk ticket — `/helpdesk/tickets/{id}` — the action panel and the conversation tabs.

#### 4.16.3 ICT Support Reports and Settings

```text
Administration → ICT Support Reports → /helpdesk/reports ; ICT Support Settings → /helpdesk/settings
```
**URLs** `/helpdesk/reports`, `/helpdesk/settings` · **Purpose** Analytics; categories, SLA and auto-close. · **Who** ict, admin, super (`DIRECTOR`). · **Layout** Reports: filters Raised from/To, Category, Priority, Agent, Faculty, Department; tiles Tickets / Overdue / Average first response / Average resolution; "Monthly ticket volume"; breakdowns; "Tickets by agent"; "The SLA in force"; "Download the Report" (CSV). Settings: "Categories" table with New Category modal (Name*, Code, Order, Handled as, Description, What to attach, Open for new tickets, fields list with Label, Key, Type, Required, Hint, Options); "The SLA by priority" (First response (h), Resolution (h)); "Closing and notice" (auto-close days 1–90 or Off; notify agents on new). · **Actions** `POST|PUT /helpdesk/admin/categories[/{id}]`; `PUT /helpdesk/admin/settings`. · **Messages** "Every field needs a key and a label."; "Two fields share a key."; "A choice field lists its options."; `HELPDESK_SLA`.

> **Screenshot Required:** ICT Support Settings — `/helpdesk/settings` — the categories table and the SLA panel.

#### 4.16.4 Track an ICT Support Ticket

```text
/tickets → Track a Ticket → /track   (public)
```
**URL** `/track` · **Purpose** Public standing by number and email. · **Who** Public (throttled 12 / 15 min per IP and email). · **Fields** Ticket number, Email address. · **Actions** Track Ticket → `POST /api/v1/helpdesk/track`. · **Messages** "No ticket with that number was raised with that email address. Check both and try again."; "Too many lookups in a short time. Wait a quarter of an hour…"; "Closed without a resolution recorded".

> **Screenshot Required:** Track a ticket — `/track` — the result card.

#### 4.16.5 Help & requests (office desk)

```text
(no menu) → /support
```
**URL** `/support` · **Purpose** Answer students' requests addressed to the acting office. · **Who** `OFFICES` (each sees its own code; admin, super, ict see all). · **Layout** Tiles Open / Answered still open / Resolved / All; notice "A request that sits unanswered is the failure this queue exists to prevent"; table Reference, Student, Subject, Raised, Documents, State, Answer/Open; modal (detail, documents, "Your answer", checkbox "This resolves the request.", Answer and resolve / Answer, keep open). · **Actions** `POST /support/requests/{id}/answer {answer, resolved}`. · **Messages** "an answer says something".

> **Screenshot Required:** Help & requests desk — `/support` — the table and the answer modal.

#### 4.16.6 Clinic

```text
Overview → Clinic → /clinic
```
**URL** `/clinic?number=` · **Purpose** Arrival, triage, waiting list, consultation. · **Who** services (menu); `CLINIC` services, super. · **Layout** Notice "Clinical notes never leave this module"; tiles Encounters today / Awaiting triage / Referrals this month / Fitness recorded; "Patient arrives" (Number, Presenting complaint, Triage Urgent/Standard/Routine; "Add to the waiting list"; "Look the patient up"); "Booked" (Arrived); "Waiting list" (See now / Open); "Concluded today"; notice "Pharmacy stock is not on the portal"; consultation modal (Outcome*, Referred to, Fitness, Clinical note; Conclude the visit / Leave open). · **Actions** `POST /health/visits`; `POST /health/visits/{id}/open`; `POST /health/visits/{id}/conclude`. · **Messages** "Nobody carries the number X"; "the patient is already on the waiting list"; "a visit is concluded with its outcome".

> **Screenshot Required:** Clinic — `/clinic` — the arrival panel and the waiting list.

### 4.17 Documents, transcripts, certificates and identity cards

#### 4.17.1 Documents office

```text
Students → Documents Office → /credentials/documents
```
**URL** `/credentials/documents` · **Purpose** The office dashboard and certificate issue. · **Who** academic, dregistrar, records, registrar (menu); `READERS`; issue `SIGNERS`. · **Layout** Actions Requests, Issued documents, Policies & templates, Public verification page; twelve tiles; charts; "Graduates awaiting a digital certificate" (checkbox, student, programme, award, session, CGPA, class, Cleared/Held, Issue; "Issue N certificate(s)"; Excel/PDF); "Documents flagged after the record changed" (Review); revenue by month; link to "the earlier transcript queue". · **Actions** Issue → `POST /documents/certificates`; bulk → `POST …/certificates/bulk` ("One that fails the checks stops the run"). · **Messages** "No issued document is flagged".

> **Screenshot Required:** Documents office — `/credentials/documents` — the tiles and the graduates panel.

#### 4.17.2 Document requests

```text
/credentials/documents → Requests → /credentials/documents/requests
```
**URL** `/credentials/documents/requests?…` · **Purpose** The request queue. · **Who** `READERS`. · **Layout** Filters Stage, Document, Payment, Delivery, Faculty, Department, Programme, Search; rows (request ref + SLA pill, student, programme, document, payment, stage, delivery, requested; Process / Check / Release / Deliver / Open); Excel/PDF "Document Requests".

> **Screenshot Required:** Document requests — `/credentials/documents/requests` — the filter bar and rows.

#### 4.17.3 One request

```text
/credentials/documents/requests → Open → /credentials/documents/requests/{id}
```
**URL** `/credentials/documents/requests/{id}` · **Purpose** Work one request through its pipeline. · **Who** `OFFICE`; release `SIGNERS` (not the producer). · **Layout** Header with stage; action buttons; Steps; notices; validation findings; "The request"; "The document"; statement preview; "Deliveries" (Update, Resend link, Mark); "Timeline".

| Action | What it does | Endpoint |
|---|---|---|
| Validate the record | Findings (errors/warnings) | `POST /documents/requests/{id}/start` |
| Generate the document | New version numbered `PREFIX/YYYY/NNNNNN` | `…/generate` |
| Quality check | Approve / Request correction / Reject (+ note) | `…/qc` |
| Authorise and release | Second officer; opens deliveries | `…/release` |
| Mark completed / Cancel | — | `…/complete`, `…/cancel` |
| Update (delivery) | State, Courier, Tracking number, Note | `POST /documents/deliveries/{id}` |
| Resend link | Email deliveries only | `…/resend` |
| Document PDF | Office download (logged) | `/credentials/documents/register/{id}/pdf` |

**Messages** "The officer who produced a document does not release it"; "request % is not paid; processing begins at payment"; "request % is held at clearance"; `DOC_RESEND`.

> **Screenshot Required:** Document request — `/credentials/documents/requests/{id}` — the steps and the validation findings.

#### 4.17.4 Issued documents register

```text
/credentials/documents → Issued documents → /credentials/documents/register
```
**URL** `/credentials/documents/register` · **Purpose** Every issued document and the verification log. · **Who** `READERS`; reissue `SIGNERS`; revoke `REVOKERS`; clear flag `OFFICE`. · **Layout** Tabs Documents (n) / Verification log (n); filters Kind, Status, Flagged, Search; rows (kind, number, vN, Flagged, holder, programme/award/class, issued, status, verification code, "N dl · N ver", Open, PDF); modal with versions, trail and excerpts; Revoke modal (Reason*, Instrument (the minute)* placeholder "SEN/2026/118"); Reissue modal (Reason). · **Actions** `POST /documents/issued/{id}/revoke|reissue|clear-flag`. · **Messages** "Only the Registrar or the Vice-Chancellor revokes, and only citing a Senate or Council minute".

> **Screenshot Required:** Issued documents — `/credentials/documents/register` — the Documents tab with a revoked row.

#### 4.17.5 Document policies & templates

```text
/credentials/documents → Policies & templates → /credentials/documents/settings
```
**URL** `/credentials/documents/settings` · **Purpose** Policies per kind and template versions. · **Who** `CONFIG` registrar, dregistrar, academic, super (others read).

| Field | Description | Required | Validation |
|---|---|---|---|
| Label, Fee (₦), Urgent processing fee, Physical delivery fee, International delivery fee | Fee blank = fee schedule for TRANSCRIPT | — | Fee cleared when not billable |
| Standard processing (working days), Urgent processing (days) | — | — | — |
| Mini-transcript covers | current semester / selected semester / selected session / cumulative | — | CHECK |
| Billable, Self-service, Graduates only, Active | Checkboxes | — | — |
| Fields shown to a stranger on verification | holder, matricNo, programme, award, classOfDegree, faculty, department, graduationSession, graduationDate, session, level, standing, cgpa | — | Results never |
| Template: Document, Title, Subtitle, Signatory, Signatory's title, Second signatory, its title, Footer, Official remarks | New version deactivates the previous | Title, Signatory, title | — |

**Actions** `PUT /documents/policies/{kind}`; `POST /documents/templates` ("Put in force"). · **Messages** "You are reading these settings"; "every document already issued stays under the version it was issued with".

> **Screenshot Required:** Document policies — `/credentials/documents/settings` — the policies table and the policy modal.

#### 4.17.6 Transcripts (legacy queue)

```text
Students → Transcripts → /credentials/transcripts
```
**URL** `/credentials/transcripts` · **Purpose** The earlier transcript queue. · **Who** academic, dregistrar, records, registrar (menu); legacy `OFFICE`/`SIGNERS`. · **Layout** Tiles Open requests / Held at clearance / Breaching SLA / Average turnaround; table Request, Student, Destination, Clearance ("3 of 3"), SLA day, Stage, Action. · **Actions** Record payment → `POST …/mark-paid`; Produce & verify → `…/produce`; Sign & release → `…/release`; "View verification" (no handler). · **Messages** "No transcript request is open… the Academic Office can raise one on a student's behalf through the API."

> **Screenshot Required:** Transcripts — `/credentials/transcripts` — the queue.

#### 4.17.7 Certificates (printed register)

```text
Students → Certificates → /credentials/certificates
```
**URL** `/credentials/certificates` · **Purpose** Printed certificates and security stationery. · **Who** academic, records, registrar (menu). · **Layout** Tiles Graduands {year} / Certificates printed / Collected / Security stock left; register (Certificate no. `MOAUM/C/YY/NNNNN`, Graduand, Award, Class, Status with Collected / Hold / Reissue); "Print a certificate" modal (Graduand, Stationery batch); notice about pre-30-December-2024 certificates issued as Benue State University; "Stationery control" (batch, serial range, issued, used, spoiled, returned; "Spoiled one"); "+ New batch" (Batch, Received on, First serial, Last serial). · **Actions** `POST /credentials/certificates`; collected / hold / reissue; batches. · **Messages** `CRED_NOT_GRADUATED`; `CRED_NOT_CLEARED`; `CRED_BATCH_EXHAUSTED`; `CRED_HOLD_SAYS_WHY`; `CRED_REISSUE_SAYS_WHY`.

> **Screenshot Required:** Certificates — `/credentials/certificates` — the register and stationery control.

#### 4.17.8 Card Printing / Card Collection / Lost & Replacement

```text
Overview → Card Printing (library) ; Services → Card Collection / Lost & Replacement (security) → /credentials/idcards
```
**URL** `/credentials/idcards` · **Purpose** Issue and report student identity cards. · **Who** library, security (menu); `ISSUERS` + super. · **Layout** Tiles Waiting for a card / Live cards / Lost or replaced / Issued today; notice on keying and release; "Waiting for a card" (search; Issue the card / Issue a replacement); "Cards issued" (card no, student, issued, valid to, Live/Lost/Replaced; Report lost via prompt). · **Actions** `POST /credentials/identity-cards/students/{id}/issue`; `…/lost`. · **Messages** "the Bursary has not cleared this student for the identity card in {session}".

> **Screenshot Required:** Card Printing — `/credentials/idcards` — the waiting list and the cards table.

#### 4.17.9 Secure recipient link

```text
(emailed secure link) → /documents/d/{token} → Open the document (PDF) → /documents/d/{token}/pdf
```
**URL** `/documents/d/{token}` · **Purpose** A recipient opens the document by an expiring token. · **Who** Public with the token (each visit spends a use). · **Layout** Green "{Kind} {number} — Issued to {holder}…" with "Open the document (PDF)" and "Verify it against the record"; or red "This link has expired" / "…used the permitted number of times" / "The document is revoked|replaced" / "This link is not valid". 

> **Screenshot Required:** Secure link — `/documents/d/{token}` — the green card.

### 4.18 Student portal

#### 4.18.1 Dashboard

```text
Start here → Dashboard → /student
```
**URL** `/student` · **Purpose** Standing, fee gate, session steps, quick tiles, notices. · **Who** student (a postgraduate sees the PG dashboard). · **Layout** Banners for ADVISED_TO_WITHDRAW / PROBATION; fee gate ("You are cleared to register" / "Action required" with "Pay now" and "See breakdown" / "What a payment releases is not yet stated for this session"); identity card with passport; "This session" steps (On the register → Course registration → Examination docket); Student details; quick tiles (My results, Fees & payments, Graduation or My documents, Deferment, Hostel, Course form — enabled only when APPROVED/LOCKED); carryover warning; "Notices sent to you". PG dashboard: coursework, research and documents summaries.

> **Screenshot Required:** Student dashboard — `/student` — the fee gate and the session steps.

#### 4.18.2 Fees & payments

```text
Start here → School Fees — Pay First → /student/fees
```
**URL** `/student/fees?session=&paid=` · **Purpose** The charge, references and payment history. · **Who** student. · **Layout** "Confirming your payment" card (after `?paid=`); tiles Session charge / Paid / Outstanding; status note; "The charge" (Item, Amount, Total); "Pay" (open reference with PayByCard, or the instalment chooser "First semester · ₦x" / "Full session · both semesters" / "Second semester" and "Generate a reference for ₦{amount}"); "Payment History" (Reference, Purpose, Amount, Status Paid / Awaiting confirmation / Expired, Receipt); session links. · **Actions** Generate → `POST /me/fees/references {session, amount}`; PayByCard → `POST /payments/checkout`; "I've paid — check now" → `POST /payments/verify`; Check again (reload). · **Messages** "No charge is stated for {session} yet"; "Course registration waits on this semester's school fees"; "Arrears from an earlier session stand against you…"; "the amount X is more than the balance of Y". · **Subtitle** static "2026/2027 session".

> **Screenshot Required:** Fees & payments — `/student/fees` — tiles, the charge table and the Pay panel.

#### 4.18.3 Payment receipt

```text
Payment History → Receipt → /student/receipt/{reference}
```
**URL** `/student/receipt/{reference}` · **Purpose** The receipt with a QR and check code. · **Who** student (own). · **Layout** "Payment confirmed on {date}"; the receipt document (Receipt number, Date, passport, Received from, Matriculation number, Programme, Session, Semester; Being payment for | Amount; TOTAL RECEIVED; Channel; Gateway or teller reference; Verification block with the QR and "Check code {token}"). · **Actions** Download PDF → `/student/receipt/{reference}/pdf`; Back to payments. · **Messages** "This payment is not confirmed yet".

> **Screenshot Required:** Payment receipt — `/student/receipt/{reference}` — the receipt with the QR.

#### 4.18.4 Course Registration

```text
Academic → Course Registration → /student/register
```
**URL** `/student/register?session&semester` · **Purpose** Draft, submit, add and drop. · **Who** student. · **Layout** Semester switcher (✓ for registered; warning "You have not registered First semester yet…"); gate card "You cannot register yet" (Student status, On the register, Financial clearance with "Pay ₦x", Registration window); SIWES notice; locked/returned notices ("Submitted on … — with your Head of Department", "Approved on …" with Course form, "Returned to you" with the reason); "Add or drop courses" (Drop / Add); units meter "N of min–max credit units" (Below minimum / Over limit / Valid); "Outstanding carryovers"; "{level} Level Core Courses"; "Electives".

| Action | What it does | Endpoint |
|---|---|---|
| Save the draft | `registration.student_draft` + `student_choose` | `PUT /me/registration` |
| Submit for approval | Fee gate, unit range, deferment gate → SUBMITTED | `POST /me/registration/submit` |
| Add / Drop | Within the window | `POST /me/registration/add|drop` |

**Messages** "the first semester school fees for … are not fully paid"; "the registration carries N units; at 100 level the range is 18 to 24"; "add and drop is not open for …"; "a carryover cannot be dropped; it must be repeated".

> **Screenshot Required:** Course Registration — `/student/register` — the pick lists and the units meter.

#### 4.18.5 Course form

```text
/student/register → Course form → /student/form
```
**URL** `/student/form` · **Purpose** The approved registration as a document. · **Who** student (APPROVED/LOCKED only). · **Layout** Passport, name, matric, level, session, semester; table Course code, Course title, Lecturer, Unit, Type (carryovers first "· C/O"); TOTAL CREDIT UNITS; Verification (first 8 chars of the registration id). · **Actions** Download PDF → `/student/form/pdf`; Print. · **Messages** "The course form is issued when your registration is approved".

> **Screenshot Required:** Course form — `/student/form` — the document.

#### 4.18.6 Registration History, My Courses, a course space

```text
Academic → Registration History → /student/registration-history ; Learning → My Courses → /student/courses → /student/courses/{offering}
```
**URLs** `/student/registration-history`, `/student/courses`, `/student/courses/{offering}` · **Purpose** Registrations on record; course spaces; materials and assignments. · **Who** student (on the roll). · **Layout** History: tiles Registrations / Courses registered / Carryovers / Identifier; current session panels (Course code, Course title, Lecturer, Unit, Type, Status); "History — N earlier registrations" (text wrongly says "the Faculty Officer approved"). My Courses: one card per approved space (materials read %, assignments due) plus the history. Space: tiles; Materials (Open counts a read); Assignments with Submit/Replace modal (text and/or file ≤ 5 MB). · **Actions** `GET /me/courses/materials/{id}/content` or `POST …/read`; `POST /me/courses/assignments/{id}/submit`. · **Messages** "the assignment closed on % and the late window of % hours has passed"; "this submission is marked; it is not replaced".

> **Screenshot Required:** Course space (student) — `/student/courses/{offering}` — materials and an assignment modal.

#### 4.18.7 Timetable and Attendance

```text
Learning → Timetable → /student/timetable ; Attendance → /student/attendance
```
**URLs** `/student/timetable`, `/student/attendance` · **Purpose** Class slots and attendance rate (below 75 % "At risk"). · **Who** student. · **Layout** Read-only tables from `GET /me/timetable?semester`.

> **Screenshot Required:** Attendance — `/student/attendance` — the per-course rates.

#### 4.18.8 Results, Statement of results, Result Broadsheet, Carryover, Result Query, Examinations

```text
Academic → Results → /student/results → Semester Results → /student/results/{session}/{semester} ; Result Broadsheet → /student/broadsheet ; Carryover → /student/carryover ; Result Query → /student/query ; Learning → Examinations → /student/exams
```
**URLs** as above · **Purpose** Published results and GPA; the statement; the whole broadsheet; carryovers; a query; the docket and card. · **Who** student. · **Layout** Results: notes ("Your results are withheld until your fees are settled", "N of your M courses are published", "All N courses are published under minute X — Released {date}"); tiles This semester / Cumulative / Standing / Units this semester; latest semester panel (Course, Units, Score, Grade, Points, Where it is, Taught by; Semester Results; disabled Official transcript); "Academic summary" (CUR…CGPA). Slip: GPA/CGPA banner, table, totals, "Download result slip". Broadsheet: tiles Name/Level/CGPA/Standing; per semester Course, Title, Unit, CA, Exam, Total, Grade, Point; "Print broadsheet". Carryover: note, tiles, table Course, Units, Failed in, Note; "How a repeat is scored". Query: window note; tiles; "Raise a query" (Course, Which mark EXAM/CA/ABSENT, "What you say is wrong"); "Your queries". Exams: scheme/cleared notes; per session Course, Date & time, Venue, Status; "Download exam card"; "Print the docket". · **Actions** `POST /me/queries`; PDFs `/student/results/{s}/{n}/pdf`, `/student/broadsheet/pdf`, `/student/exams/card/pdf?session&semester`. · **Messages** "The query window is open until {date}"; "a query on this mark is already open"; 409 "Withheld", "Nothing published", "Not cleared for examinations".

> **Screenshot Required:** Results — `/student/results` — the tiles, latest semester panel and academic summary.

#### 4.18.9 Deferment (student)

```text
Academic → Deferment → /student/deferment
```
**URL** `/student/deferment` · **Purpose** Request, document, review, submit, withdraw. · **Who** student, pgstudent. · **Layout** State banner (active/approved with Approval Letter; correction/draft with Continue the Request; under review with Withdraw Request; not available with the reason; "You have used X of the Y session(s)"); three-step wizard; "Deferment history".

| Field | Description | Required | Validation |
|---|---|---|---|
| Deferment type, Academic session, Semester, Reason, Explanation | A semester / The whole academic session | Type, Session, Reason; Explanation when required | ≥ 20 characters when required |
| Supporting documents: kind, file | Medical / Financial / Official letter / Employer letter / Other | For document reasons | PDF/JPEG/PNG ≤ 5 MB, ≤ 6 |
| Declaration | "I confirm that the information provided … is accurate…" | Yes | Ticked |

**Actions** Save and Continue → `POST /me/deferments` / `PUT …/{id}`; Upload → `POST …/documents`; Submit Deferment Request → `POST …/submit`; Withdraw Request (prompt) → `POST …/cancel`; Approval Letter → `/student/deferment/letter/{id}`. · **Messages** "Deferment request DEF-… submitted successfully"; "Deferment is asked for once you are matriculated…"; "a medical deferment is supported by a document".

> **Screenshot Required:** Deferment — `/student/deferment` — the wizard's review step.

#### 4.18.10 Inter-Departmental Transfer (student) and letter

```text
Academic → Inter-Departmental Transfer → /student/transfer ; Approval letter → /student/transfer/letter/{id}
```
**URLs** `/student/transfer`, `/student/transfer/letter/{id}` · **Purpose** Apply, pay, follow the seven stages; print the letter. · **Who** student (matriculated, ACTIVE/PROBATION). · **Layout** Tiles Your department / Processing fee / Applications; "Your application" with the stages and "Pay the fee online" or "In progress — …"; "Your transfer is complete" with Approval letter; "Apply to transfer" (Course applied for, Reason, UTME score). Letter: printable approval letter (text cites Senate/SAIC and a hard-coded ₦10,000). · **Actions** `POST /me/transfer`; `POST /me/transfer/{id}/fee` then PayByCard. · **Messages** "Transfers are not open yet"; "You cannot apply to transfer right now"; "a transfer application is already in progress for this student".

> **Screenshot Required:** Inter-Departmental Transfer — `/student/transfer` — the stage tracker.

#### 4.18.11 My documents

```text
Academic → My Documents → /student/documents   (/student/transcript redirects here)
```
**URL** `/student/documents?new=` · **Purpose** Issued documents, secure links, requests and the wizard. · **Who** student, pgstudent. · **Layout** Actions Request a document, Verify a document; tiles Certificates / Transcripts & statements / Pending requests / Available downloads; "N request(s) in hand" with PayByCard; "Documents issued to you" (kind, number, issued, status, verification code, Download PDF, Secure link); "My document requests" (Timeline, Download); five-step wizard (Select document; Select delivery Digital / Physical / Both, Copies 1–10, Urgent, International; Recipient Myself / An institution / An employer / An embassy / A professional body / Another authorised recipient with Institution*, Department/unit, Recipient name, Recipient email, Their reference, Postal address*, Purpose; Review the fee; Confirm and submit). · **Actions** `POST /me/documents/requests`; `POST /me/documents/{id}/link {days:7}`; `/student/documents/{id}/pdf`; Cancel request (prompt) → `POST /me/documents/requests/{id}/cancel`. · **Messages** "Pay ₦X against reference …"; "The document was issued at once…"; "It is with Exams and Records"; "Valid for seven days; each use is logged".

> **Screenshot Required:** My documents — `/student/documents` — the issued list and the wizard's first step.

#### 4.18.12 Wallet & Funding

```text
Services → Wallet & Funding → /student/wallet
```
**URL** `/student/wallet?session=` · **Purpose** Balance, sources, apply, top up, withdraw. · **Who** student, pgstudent. · **Layout** Tiles Wallet balance / Funded / Applied to your invoices / Outstanding on your account; funding by source; NELFUND status note; position note with "Apply ₦x to {session}"; "Wallet statement"; "Top up the wallet" (Amount; "Generate the reference"; PayByCard); "Withdraw to your bank account" (Amount, Bank, Account number, Account name; "Request the withdrawal"). · **Actions** `POST /me/wallet/apply`, `/topup-reference`, `/withdrawal`. · **Messages** "Your wallet covers what you owe"; "Not available yet" + reason; "Withdrawal of ₦x requested — the Bursary will review it."

> **Screenshot Required:** Wallet & Funding — `/student/wallet` — tiles, the sources and the statement.

#### 4.18.13 Hostel (student)

```text
Services → Hostel → /student/hostel
```
**URL** `/student/hostel?session=` · **Purpose** Apply, pay, accept, check in, transfer, checkout, maintenance, letters. · **Who** student. · **Layout** Session select; one status notice by state (with the buttons that state allows); Steps Applied → Allocated → Fee paid → Accepted → Checked in → Checkout → Cleared; "Apply for accommodation" (Hall preferred, Room type preferred, Block preferred, Priority category, "What the category rests on", Special or medical accommodation need, Preferred roommate, Roommate note); "My allocation"; "Roommates"; "Maintenance and complaints" (fault kind, Urgency, What is wrong; "Send to the housing desk"); "Transfer requests"; "Hostel clearance"; "Hostel rules and regulations"; "Accommodation history"; "Trail"; modals (rules acknowledgement, decline/withdraw reason, transfer request, checkout request). · **Actions** `POST /me/hostel/apply-full`, `/fee-reference`, `/accept {rulesVersion}`, `/decline`, `/transfer`, `/checkout`, `/maintenance-full`; letters `/student/hostel/letter`, `/student/hostel/clearance`. · **Messages** "Hostel application submitted successfully."; "You are not eligible to apply this session" + reason; "A bed is held for you — N hours to pay"; "the hostel rules (version %) are acknowledged before the allocation is accepted".

> **Screenshot Required:** Hostel (student) — `/student/hostel` — the status notice, steps and application form.

#### 4.18.14 Library (student)

```text
Services → Library → /student/library
```
**URL** `/student/library?q=` · **Purpose** Loans, fines, reservations, catalogue. · **Who** student, pgstudent. · **Layout** On loan (Renew), Fines ("Generate the reference", then pay on Fees), Reservations, catalogue search with "Join the waiting list". · **Actions** `POST /me/library/loans/{id}/renew`, `…/fine-reference`, `POST /me/library/reservations`. · **Messages** "an overdue item is returned, not renewed"; "a copy is on the shelf; borrow it rather than reserving it".

> **Screenshot Required:** Library (student) — `/student/library` — loans and the catalogue search.

#### 4.18.15 Identity card (student)

```text
Services → Identity Card → /student/idcard
```
**URL** `/student/idcard` · **Purpose** The card as issued and the printable copy. · **Who** student, pgstudent. · **Layout** Status note; "Your identity card" (front and back preview; Card number, Valid to, Faculty, Department); "Open the printable copy" (ISSUED only); "Report it lost" (prompt); "Request a replacement" (→ Help & Requests); "Cards" (Card, Issued, Valid to, State). · **Actions** `POST /me/id-card/lost`; PDF `/student/idcard/pdf`. · **Messages** "A card is made after matriculation"; "Your card waits on the Bursary's clearance"; PDF 409 "No identity card issued".

> **Screenshot Required:** Identity card — `/student/idcard` — the preview and the Cards table.

#### 4.18.16 Health (student)

```text
Services → Health → /student/health
```
**URL** `/student/health` · **Purpose** Book or cancel an appointment, consent and restrict, read visits and the access log. · **Who** student, pgstudent. · **Layout** Appointment form and list; consent (blood group, genotype, allergies) and restrict; visits with outcomes and referrals; "who read your record". · **Actions** `POST /me/health/appointments`, cancel, `PUT /me/health/consent`, restrict. · **Messages** "choose a time ahead"; "an appointment already stands; cancel it before booking another".

> **Screenshot Required:** Health — `/student/health` — the booking form and visit list.

#### 4.18.17 Help & Requests (student)

```text
Services → Help & Requests → /student/support
```
**URL** `/student/support` · **Purpose** A request to one of eight offices with documents. · **Who** student, pgstudent. · **Layout** "Your requests" (Reference, Subject, Office, Raised, Documents, Status); "Raise a new request" (office pills; "What is the problem?"; "Anything more the office should know"; "Supporting documents" PDF/JPEG/PNG ≤ 2 MB, up to six; "Submit request"). · **Actions** `POST /me/requests` (+ `…/{id}/documents`). · **Messages** "Request SR-… is with {office} — N document(s) attached"; "five requests are open already".

> **Screenshot Required:** Help & Requests — `/student/support` — the office pills and the form.

#### 4.18.18 Profile, Biodata, Notifications

```text
Account → Profile → /student/profile ; Biodata → /student/biodata ; Notifications → /student/notifications
```
**URLs** `/student/profile?change=`, `/student/biodata`, `/student/notifications` · **Purpose** Contact and password; biodata sections; notices. · **Who** student, pgstudent. · **Layout** Profile: Phone, Personal email, Contact address; Current/New password; read-only Registry fields ("On the register since" always "—"); Biodata: the shared component (open fields save; locked refused); Notifications: list and "How we reach you" (channels always on). · **Actions** `PUT /me/contact`; `POST /student-auth/change-password`; `PUT /me/biodata/{field}`. · **Messages** "Choose your own password before you go on"; `STU_PHONE` "A Nigerian mobile number is eleven digits beginning with a zero."; `STU_FIELD_LOCKED`.

> **Screenshot Required:** Profile — `/student/profile` — the contact form and password fields.

#### 4.18.19 Graduation & Clearance (student)

```text
Graduation → Graduation & Clearance → /student/graduation   (UG: dashboard tile)
```
**URL** `/student/graduation` · **Purpose** The steps to the certificate and the eight-unit convocation clearance. · **Who** student, pgstudent. · **Layout** Steps (audit → Senate → cleared by every unit → certificate printed → collected); tiles; award panel; "Clearance for convocation" table; certificate panel. · **Actions** None.

> **Screenshot Required:** Graduation — `/student/graduation` — the steps and the clearance table.

#### 4.18.20 Course Registration & Results, Academic Progress, Research & Thesis (postgraduate)

```text
Academic → Course Registration & Results → /student/pg-courses ; Academic Progress → /student/pg-progress ; Research → Research & Thesis → /student/research
```
**URLs** `/student/pg-courses`, `/student/pg-progress`, `/student/research` · **Purpose** PG registration and results; eligibility checklist; the research record and documents. · **Who** student (POSTGRADUATE). · **Layout** Coursework: Session text box, Semester; "Results" (GPA/CGPA, Units passed, Standing); "Course registration" (checkboxes, Mode Full-time/Part-time, "Register these courses / Update registration"). Progress: tiles Units earned / Courses passed / CGPA / Graduation; meter; "Graduation eligibility" checklist (MET / PENDING / NOT_MET) — advisory. Research: progress steps; Supervision; Panel; Viva note; "Topic & proposal" (Research topic, Save topic, Submit proposal); "Documents" (kind, PDF/.docx ≤ 25 MB, Note, Submit Document); Milestones. · **Actions** `POST /pg/coursework/register`; `POST /pg/research/me/proposal`, `…/me/documents`. · **Messages** "Your registration is endorsed… Write to the department to change it."; "No courses listed for this semester yet"; "The topic can no longer be changed here once the proposal is approved."; "The draft is submitted for examination once your title is registered."

> **Screenshot Required:** Research & Thesis — `/student/research` — the progress steps and the documents panel.

### 4.19 Reports, registers and statistics

#### 4.19.1 Reports & returns

```text
Reports → Reports & Returns → /reports
```
**URL** `/reports?session=` · **Purpose** The due register, registers, kept copies, standard reports, trends. · **Who** seventeen offices (menu); readers per §3.54 (dean, facultyofficer, hod refused for the due register and snapshots). · **Layout** Tiles Overdue / Due within 30 days / Kept copies / Filed; "Due register" (Return, Owner, Frequency, Last due, Next due, State, Run/Open); "Session" (Reporting session); "Registers — view all"; "Kept copies" (Return, Period, Rows, Taken · by, Code, Filed, Open); "Standard reports"; Trends; "Enrolment by faculty". · **Actions** Run → `/reports/{slug}/view`; Open kept copy → `/reports/snapshots/{id}`. · **Messages** State pills "Overdue · n days", "Due today", "Due in n days", "Kept · not filed", "Filed", "On demand".

> **Screenshot Required:** Reports & returns — `/reports` — the due register.

#### 4.19.2 A return view (twelve slugs)

```text
/reports → Run → /reports/{admissions|enrolment|registration|carryovers|staff-ratio|postgraduate|revenue|funding|expenditure|income-expenditure|students|staff}/view
```
**URL** `/reports/{slug}/view?session=&sem=&due=` · **Purpose** The return as a branded document. · **Who** The slug's readers (`ENROLMENT_READERS`, `REVENUE_READERS`, `PG_READERS`, `STAFF_RATIO_READERS`; registers' readers), cut to scope. · **Layout** `ReportDoc` outside the Shell: crest, University name, title, subtitle (scope label), session, table with totals, footing note, "Issued by the portal on <date> · <office>", serial `MOAUM/RPT/yyyymmdd/hhmmss`; toolbar "← All returns", "Keep a copy", "Download Excel", "Print / Save as PDF". · **Actions** Keep a copy → `POST /reports/snapshots` ("Copy kept · verification code XXXX · open the kept copy"); Download Excel (crest-branded workbook built in the browser); Print. · **Messages** "Your office reads this return; the office that owns it keeps and files the copy."; the registration return's footing changes when no clearance scheme is in force.

> **Screenshot Required:** A return view — `/reports/enrolment/view` — the document with the toolbar.

#### 4.19.3 Kept copy

```text
/reports → Kept copies → Open → /reports/snapshots/{id}
```
**URL** `/reports/snapshots/{id}` · **Purpose** The snapshot as taken; filing; emailing. · **Who** snapshot `READERS`. · **Layout** The document ("Kept copy · taken <date> by <name> (<office>) · filed with <body> on <date> / not yet filed. Verification code <code> — check it at /verify/report/<code>"; serial `MOAUM/RPT/<code>`); toolbar "← All returns", status line, "Mark as filed" (modal "Filed with" with a datalist NUC / JAMB / Council / State treasury / Senate / Management / School Board; Note), "Email this return" (To — comma-separated; Message), "Download Excel", "Print / Save as PDF"; dispatch list. · **Actions** `POST /reports/snapshots/{id}/file`; `POST /reports/snapshots/[id]/email` (frontend builds the PDF and workbook) → `POST /api/v1/reports/snapshots/{id}/email`. · **Messages** "This snapshot is already filed, or does not exist"; "Give at least one email address"; "At most twenty recipients at a time".

> **Screenshot Required:** Kept copy — `/reports/snapshots/{id}` — the document header and toolbar.

#### 4.19.4 Student register and Staff register

```text
Reports → Student Register → /reports/students ; Staff Register → /reports/staff
```
**URLs** `/reports/students?…`, `/reports/staff?…` (print views `/reports/students/view`, `/reports/staff/view`) · **Purpose** Whole-register views, filterable, paged, exportable. · **Who** seventeen offices; registers `READERS` (scope cut for dean, facultyofficer, hod). · **Layout** Filter panel (students: Faculty, Department, Programme, Level, Sex, Status, Entry mode, Entry session; staff: Faculty, Department, Rank, Category, Status, Office held) and Search; buttons Search, Clear filters, "Download Excel (n rows)", "Print / Save as PDF"; tiles; table paged 100 (Previous/Next); rows open the student/staff modals. · **Actions** `GET /reports/registers/{kind}?…&page&size=100`; Excel fetches every row 500 at a time (`students-register-<date>.xlsx` / `staff-register-<date>.xlsx`, 16 staff columns); print view caps at 5 000 rows (PARTIAL beyond). · **Messages** "The export stopped after…"; "No member of staff on the register matches these filters."

> **Screenshot Required:** Student register — `/reports/students` — filters, tiles and the paged table.

#### 4.19.5 Student Statistics and the students behind a figure

```text
Overview → Student Statistics → /stats → (any figure) → /stats/students?which=
```
**URLs** `/stats?session=&semester=&fac=&dept=&prog=&level=&status=&degree=`, `/stats/students?which=&q=&page=` · **Purpose** The V257 engine and its drill-down. · **Who** fourteen offices (menu); stats `READERS`; amounts for `MONEY` offices. · **Layout** Stats: PageHead "Student Statistics" with actions Paid Not Registered / Not Paid / All Students; scope filter bar; StatTiles; donuts Payment status (with the registration-closes date) and Registration status; bar panels by faculty, department, programme, degree type; tables By faculty / department / programme / degree type; "Quick actions". Detail: breadcrumb; PageHead with Export Excel / Export PDF / Back to Statistics; Search and Figure select; table (S/N, Student, Programme, Level, Fees pill, [Payable, Paid, Outstanding], Last payment + reference, Registration pill, Registered date, Open); 50 per page. · **Actions** Exports (`brandedXlsx`/`brandedPrint`, serial `MOAUM/STAT/…`, S/N first, names A–Z). · **Messages** "No students found".

> **Screenshot Required:** Student Statistics — `/stats` — the tiles and the two donuts.

### 4.20 Public verification pages

#### 4.20.1 Verify a payment (landing) and receipt verification

```text
/login → Verify a payment or receipt → /verify → /verify/receipt/{reference}?c=
```
**URLs** `/verify`, `/verify/receipt/{reference}` · **Purpose** Check a receipt against the Bursary's ledger. · **Who** Public. · **Layout** `/verify`: fields Reference or receipt number (placeholder "e.g. MOAUM-FEE-370000-6912 or RCT-2025-00001") and Check code (placeholder "e.g. 185A1F24C8C3"); "Verify payment"; camera Scanner ("That QR is not a MOAUM verification code."). Receipt page: "Receipt verification" card — green "Genuine — this receipt is on the Bursary's ledger" with photo and a table (Received from, Matriculation number, Programme, Level, Being payment for, Session, Semester, Amount, Channel, Confirmed on, Receipt number) or red "Not verified — No confirmed receipt matches this code…". · **Endpoint** `GET /api/v1/verify/receipt/{reference}?c=`.

> **Screenshot Required:** Receipt verification — `/verify/receipt/{reference}?c=` — the genuine card.

#### 4.20.2 Examination card, registration and results verification

```text
(QR on the card / course form / statement) → /verify/exam ; /verify/registration ; /verify/results   (?m=&s=&sem=&c=)
```
**URLs** as above · **Purpose** Genuine examination card (name, photo, programme, level, cleared, courses), course form (APPROVED/LOCKED registration with courses and units), statement of results (published grades, GPA, CGPA, class of standing, Senate minute). · **Who** Public with the SHA-256 check code. · **Layout** The shared card ("Genuine statement — this is the University's record" / "Not verified"). · **Endpoints** `GET /api/v1/verify/exam|registration|results`.

> **Screenshot Required:** Results verification — `/verify/results?m=&s=&sem=&c=` — the genuine card with grades.

#### 4.20.3 Kept-return verification

```text
(footing of a kept copy) → /verify/report/{code}
```
**URL** `/verify/report/{code}` · **Purpose** A kept return: title, scope, period, taken when and by which office, rows, totals, filed. · **Who** Public. · **Endpoint** `GET /api/v1/verify/report/{code}`.

> **Screenshot Required:** Kept-return verification — `/verify/report/{code}` — the card with the return's rows.

#### 4.20.4 Post-UTME slip verification

```text
(QR on the slip) → /verify/putme/{token}
```
**URL** `/verify/putme/{token}` · **Purpose** "Post-UTME examination slip verification". · **Who** Public. · **Layout** Green "Genuine slip — this is the University's record" (photo, name, application/JAMB numbers, programme, exam, Batch, Day, Time, Centre, Room, Seat, Attendance, "Checked in at …"); red "Genuine slip — but the batch is postponed/cancelled"; red "Not verified — No published examination slip matches this code". · **Security** No rate limit.

> **Screenshot Required:** Slip verification — `/verify/putme/{token}` — the genuine card.

#### 4.20.5 Hostel allocation verification

```text
(QR on the allocation letter / clearance certificate) → /verify/hostel/{ref}
```
**URL** `/verify/hostel/{ref}` · **Purpose** "Hostel allocation verification" for the porter. · **Who** Public. · **Layout** Green "Genuine — this is the University's record" with photograph and cells Hostel, Block · floor, Room, Bed, State, Stay, Checked in, Clearance; or red "Not verified — No hostel allocation matches this reference. Treat the letter as not genuine." · **Security** No check token and no throttle over a sequential reference.

> **Screenshot Required:** Hostel verification — `/verify/hostel/{ref}` — the genuine card.

#### 4.20.6 University document verification

```text
/student/documents → Verify a document / Documents office → Public verification page → /verify/document?key= ; /verify/document/{key}
```
**URLs** `/verify/document`, `/verify/document/{key}` · **Purpose** Verify a certificate, transcript or statement by code or number. · **Who** Public (40 lookups / 15 min per IP). · **Layout** Field "Verification reference or document number"; "Verify document"; answers "VALID DOCUMENT — authentic and currently valid" / "REVOKED — this document was officially revoked" (date, instrument) / "REPLACED — a later version of this document is the official one" / "NOT FOUND — no document bears this reference" / "INVALID — the document could not be validated"; Document type, Number, Status, Issued on, Version, Issued by, Issuing institution and the policy's public fields; footer "Only fields the University has approved for public disclosure are shown." · **Endpoint** `GET /api/v1/verify/document[?key=|/{key}]`. · **Messages** "Too many verifications from this source; try again in a few minutes."

> **Screenshot Required:** Document verification — `/verify/document/{key}` — a VALID DOCUMENT answer.

---

## 5 Dashboards and KPIs

Every tile is computed on request from the modules' own tables (a *read model*); nothing is stored separately. Tiles marked **hard-coded** or **placeholder** do not read data. "Who sees it" names the office whose home renders the dashboard; the API guard of the underlying endpoint is given where it is narrower.

### 5.1 Home dashboards at `/`

| Dashboard | Metric | Definition | Data source | Who sees it |
|---|---|---|---|---|
| Platform | The service | up/down and the running commit | `GET /platform/status` (public) | ict, super |
| Platform | The database | reachable, migrations applied, latest migration | `platform/status` | ict, super |
| Platform | 2025/2026 admission settings | state of that session's admission settings — **hard-coded label** | `platform/status.admissionSettings2025_2026` | ict, super |
| Platform | Acting as | the acting office | `iam/me` | ict, super |
| Platform | Course-structure coverage | totals, by faculty, pending programmes | `GET /catalogue/upload-coverage` | ict, super (also admin, academic, registrar, dregistrar, dvc, vc, hod, dean by guard) |
| Platform | People and access | people on record, with a sign-in, live grants, grants ending within 30 days | `iam/persons`, `iam/office-assignments` | ict, admin, super, registrar, dregistrar |
| Platform | The outbox | email/SMS provider wired (relay URLs only), waiting / sent / failed / sent in the last day, recent 50 | `GET /platform/notices` | ict, super |
| Registrar | Students on the register | `people.student` rows in scope | `GET /student/students` | registrar |
| Registrar | Staff on the register | persons with a staff number, and with accounts | `GET /iam/persons` | registrar |
| Registrar | Senate business | score sheets in workflow | `GET /results/sheets` | registrar |
| Registrar | Credentials in hand | issued credentials | `credentials` reads | registrar |
| Registrar | Registry business table | admissions cycle, matriculation, convocation; "name of the University" — **static row** | admissions, matriculation, graduation reads | registrar |
| Registrar | Council and Senate table | "—" / "No sitting recorded" — **placeholder** | none | registrar |
| Registrar | NDPA return due 31 March | **static note** | none | registrar |
| Academic | Committed admission list | committed CAPS rows | admissions cycle | academic, dregistrar, records, dvc |
| Academic | Registration, by faculty | registered per faculty; "Blocked at the Bursary" column is "—" (**placeholder**) | registration reads | same |
| Academic | Credentials in hand | issued documents; "Public verification arrives with its module" row is **stale** | credentials reads | same |
| Bursar | Collected this session | confirmed school-fee references of the session | `GET /finance/bursary` `fees_collected` | bursar |
| Bursar | Collected today | today's confirmations and count | `finance/bursary.today`, `today_count` | bursar |
| Bursar | Exceptions open | unresolved gateway exceptions; hanging count | `GET /payments/bursary` | bursar |
| Bursar | Gateways live | wired gateways with mode | `payments/bursary` | bursar |
| Bursar | Collection by faculty | students, paid students, collected, due per faculty | `finance.collection_by_faculty(session)` | bursar |
| Bursar | The desk table | fee schedule and scheme, references awaiting confirmation, hanging, bank credits; **NELFUND and Held scripts pills always "Open" (hard-coded)** | mixed | bursar |
| Bursar | Recent confirmations | last seven days of the day book | `finance/bursary.recent` | bursar |
| Lecturer | Sheets, spaces, SIWES students | own sheets by stage, own course spaces, assigned SIWES students | `results/mine`, `lms/teaching`, `siwes/mine` | lecturer |
| HOD | Registrations to approve | SUBMITTED registrations of the department | `GET /hod/dashboard` | hod |
| HOD | Courses without a Lecturer | offerings with no lead | `hod/dashboard` | hod |
| HOD | SIWES without a supervisor | registered SIWES students unassigned | `hod/dashboard` | hod |
| HOD | Result sheets in progress | sheets not PUBLISHED | `hod/dashboard` | hod |
| HOD | Students / Courses / Result queries / Student requests | department counts | `hod/dashboard` | hod |
| HOD | Cleared for registration / owing | students by `finance.semester_cleared`, with downloadable lists | `GET /hod/fees?which=cleared|owing` | hod |
| HOD | At-risk students | PROBATION standing | `hod/dashboard` | hod |
| HOD | Lecturers' loads; allocation history | per lecturer | `hod/dashboard`, `allocation/history?scope=department` | hod |
| Dean | Registration by department; result pipeline; unallocated offerings; at-risk students | faculty-scoped counts | `GET /dean/dashboard` | dean, facultyofficer |
| Exams | Sheets at VERIFICATION and the monitor | scope counts | `results` reads | exams, facultyexams |
| HR | Staff on the establishment | ACTIVE employments | `GET /hr/dashboard` | hrm |
| HR | Leave to decide | REQUESTED leave | `hr/dashboard` | hrm |
| HR | Instruments to issue | APPROVED movements | `hr/dashboard` | hrm |
| HR | Open vacancies (n shortlisted) | OPEN vacancies | `hr/dashboard` | hrm |
| HR | Latest pay run footer | period, state, staff, net | `hr/dashboard` | hrm |
| Housing | Beds, occupancy, applications, waiting at the desk | as §5.2 Hostel | `hostel/sessions/{s}/dashboard` | housing |
| Clinic | Encounters today / Awaiting triage / Referrals this month / Fitness recorded | `health.visit`, `appointment`, `profile` | `GET /health/desk` | services |
| Security | Posture tiles | as `/security` | `GET /governance/security` | security |
| Audit | Posture tiles + recent activity (12 rows) | as `/security` + `audit/entries?limit=12` | `governance/security`, `audit/entries` | audit, deputyaudit |
| SIWES | Students / Supervisors assigned / Score sheet / Course | current SIWES offering | `siwes/offerings` | siwes |
| PG School | Applications / Awaiting the School / Offered / To admit / PG students; pipeline Active students / On research / Awaiting defence / Finishing / Graduation eligible / Graduated; latest applications; by programme | `admissions.pg_*` | `GET /pg/dashboard` | pgschool |
| PG Secretary | To register / Fees to confirm / Exams pending / Clearances; the three lists | PG tables | `GET /pg/secretary/dashboard` | pgsecretary |
| Generic Office | Session 2026/2027 — **hard-coded placeholder** | none | none | any office without a dashboard |
| Every management dashboard | StatsPanel (All students / School fees paid / Course registered / Paid but not registered / Not paid / No charge stated / Not registered) | `reporting.student_positions` | `GET /stats/students/summary` (stats `READERS`; amounts for `MONEY`) | Platform, Registrar, Academic, Bursar, HOD, PG dashboards, Overview, College dashboard |

### 5.2 Module dashboards

| Screen | Metric | Definition | Data source | Who sees it |
|---|---|---|---|---|
| `/admin` | Students / Result sets past Senate / Collected this session / Fees outstanding (per scope) | `people.student` ACTIVE; PUBLISHED sheets over expected; `finance.collection_by_faculty` | `GET /reporting/overview` | admin (`MANAGEMENT`) |
| `/admin` | Academic pipeline donut; Money table; By faculty bars | approved / in chain / never submitted; ledger links | same | admin |
| `/overview` | Students on the register; Result sets expected; Past Senate (%); Never submitted | `ReportingController.overview`: expected = MAIN sheets, submitted = stage ≠ ENTRY, approved = PUBLISHED | `reporting/overview` | vc, dvc, registrar, admin |
| `/overview` | Returns overdue / Returns due within 30 days | `reports.due_register` | `GET /reports/due` | same (snapshot `READERS`) |
| `/overview` | Donuts, results by faculty, week by week, students by faculty, grade spread A–F | weekly cumulative `submitted_at`/`published_at`; grades banded on `grace_total` at 70/60/50/45/40 on PUBLISHED sheets | `reporting/overview` | same |
| `/people` | Accounts / Staff accounts / Holding two offices / Grants expiring in 30 days | `iam.credential`, `iam.office_assignment` | `iam/persons`, `iam/office-assignments` | super, ict, admin |
| `/notices` | Waiting / Sent today / Failed / Sent, all time | `platform.notice.state` | `platform/notices` | ict, super (+ admin, registrar by guard) |
| `/api-keys` | Consumers / Live keys / Due for rotation | `apimgmt.*` | `apimgmt/consumers` | ict, admin, super |
| `/audit` | Entries on the record / Today / Actors today / Refusals today | `audit.entries` + sign-in events; refusals = action ILIKE '%REFUS%' + failed sign-ins | `audit/entries`, `audit/facets` | `OVERSIGHT` |
| `/security` | Audit entries (shards) / Unattached tables / Failed sign-ins 7 days / Last audit entry | `audit.chain_head`, `audit.unattached()`, `iam.sign_in_event` | `governance/security` | as guard |
| `/governance` | Processing activities / DPIAs outstanding / Open subject requests / Overdue requests | `governance.*` | `governance/register`, `dsr` | `READERS` |
| `/disaster-recovery` | Last restore verification / Last full DR drill / Drills on record / Failed drills | `governance.dr_drill` | `governance/dr` | ict, super |
| `/readiness` | Ready / Blocking / To review / Total checks | eleven gates | `platform/readiness` | as guard |
| `/calendar` | Current session / Current semester / Registration / Score sheets due | `policy.*` | `calendar` | any |
| `/catalogue` | Courses owned / Live / Awaiting approval / Live, no lecturer | `catalogue.course`, `offering` | `catalogue/courses?dept=` | `OWNERS`/`READERS` |
| `/catalogue/structure` | Courses bound / Levels / Borrowed / Without a semester | `catalogue.course_offer` | `catalogue/structure?prog=` | same |
| `/allocate` | Courses / Unassigned / No second examiner / Lecturers | `catalogue.offering` | `allocation?dept=` | `ALLOCATORS` |
| `/registration/class-list` | Registered / owning department / Other programmes / Cleared to sit | roll + `clearance.is_clear(…,'EXAMINATION')` | `registration/class-list` | `READERS` |
| `/lms/{offering}` | Materials published / Assignments / Submissions / Never opened the space | `lms.*` | `lms/offerings/{id}` | `TEACHERS` |
| `/library/circulation` | Copies in stock / On loan / Overdue / Fines unpaid | `library.*` | `library/desk` | `DESK`/readers |
| `/siwes` | Students / Supervisors assigned / Score sheet / Course | `assessment.siwes_supervisor`, `score_sheet` | `siwes/offerings` | `ASSIGNERS` |
| `/admissions` | Applications / Screened / Offers issued / Accepted | `admissions.application`, `candidate` | `admissions/sessions/{s}/cycle` | `READERS` |
| `/admissions` (desk) | Admitted applicants / References open / Documents to review / Decisions entered | applications | `…/applicants` | `READERS` |
| `/admissions/putme` | Eligibility counts, batches, checked in; validation errors/warnings | `putme_*`, `screening_*` | `…/putme` | `READERS` |
| `/pg/portal` | Programme / Application fee / Documents n/7 / Stage | own application | `pg/me` | applicant |
| `/admissions/postgraduate` | Applications / Submitted / Dept recommended / Faculty recommended / Offered / Admitted | `pg_application.state` | `pg/applications?session=` | `READERS` |
| `/admissions/postgraduate/students` | PG students / PGD / Master's / Doctoral / On probation | register + `pg_cgpa` (probation < 2.50) | `pg/students` | `READERS` |
| `/admissions/postgraduate/research` | In the pipeline / Supervision / Proposal / Seminar & title / Examination / Awarded | `pg_research.stage` | `pg/research` | `SCHOOL` |
| `/admissions/postgraduate/board` | Awaiting the Board / With Senate / Awarded | CLEARED / AWARD_RECOMMENDED / AWARDED | `pg/research` | `SCHOOL` |
| Secretary desks | To register / Registered / Part-time / Lapsed; Courses sat / Results recorded / Results awaited / Candidates; To Senate / Awarded / Coursework results / Pending computation | PG tables | `pg/secretary/*` | `READERS` |
| `/examiners` | Examiners (active · awaiting activation) / Assigned projects / Pending reviews / Submitted (locked · avg days) | `extexam.*` within reach | `examiners/dashboard` | `DESK` |
| `/examiners/assignments` | Assignments shown / Pending / Overdue / Submitted (locked) | `extexam.assignment` | `examiners/assignments` | `DESK` |
| `/examiner` | Assigned projects / Pending reviews (not started · in review) / Submitted / Overdue | own assignments | `examiners/me` | extexaminer |
| `/students` | Migrated: On the register / Cleared everywhere / Not yet cleared; Voluntary withdrawals: Due now / Closed so far | `student/students/migrated`, `voluntary-withdrawals` | as named | academic, registrar, dregistrar, ict, super |
| `/students/biodata-changes` | Awaiting evidence / Approved / Refused / Self-service changes | `people.biodata_change` (always empty) | `student/biodata-changes` | readers |
| `/matriculation` | Registered students / Confirmed by Faculty Officers / Faculties outstanding / Numbers issued | `people.faculty_list_rows`, runs | `matriculation/sessions/{s}` | `READERS` |
| `/matriculation/config` | Series / Programmes with a code / Carrying none / Numbers issued on record | `people.matric_series`, `ref.programme`, `matric_history` | `matriculation/config` | `READERS` |
| `/deferments` | Total / Pending / Under review / Approved / Rejected / Active deferments / Returning / Overdue returns | `people.deferment` within bound | `deferments/dashboard` | `DESK` |
| `/student/transfer`, `/transfers` | Your department / Processing fee / Applications; four desk counts | `people.transfer_application` | `me/transfer`, `transfers` | student; readers |
| `/clearance` | Candidates for clearance / Fully cleared / Outstanding at one unit / Outstanding at two or more | `clearance.position` | `clearance` | readers |
| `/graduation` | Finalists / Audit passed / Outstanding requirement / Awaiting clearance | `records.graduand`, clearance | `graduation/sessions/{s}` | readers |
| `/alumni` | On the register / Graduating sessions / Latest cohort / Showing | APPROVED graduands | `alumni` | readers |
| `/examinations/sessions` | Open sessions / Courses examined / Candidates / Sheets due; submission monitor | `assessment.exam_session`, `score_sheet` | `results/exam-sessions`, `…/monitor` | `READERS` |
| `/results/sheets/history` | Sheets on record / Published / In approval / Still with you | own sheets | `results/mine` | lecturer |
| `/results/desk` | On this desk now / Not yet arrived / Sent on / Published | sheets by stage in scope | `results/sheets` | `DESKS` |
| `/results/approvals` | Expected sheets / Senate approved / In workflow / Not submitted | sheets in scope | `results/sheets` | `DESKS` |
| `/results/chain` | Course / Students / Fail rate / Stage N of 6 | one sheet | `results/sheets/{id}` | `READERS` |
| `/results/broadsheet` | Candidates / Mean GPA / Passed every course / Carrying over | computed | `results/broadsheet` | `READERS` |
| `/results/senate`, `/results/publish` | Sets / Candidates / At Senate / Published / Outstanding per faculty | sheets at SENATE | `results/senate` | `READERS` |
| `/results/queries` | Open / Shown / Corrected / Upheld | `assessment.result_query` | `results/queries` | `DEPARTMENT` |
| `/exams/question-bank` | Course / Active questions (retired) / Topics / Marks available; blueprint | `assessment.question` | `cbt/questions` | `READERS` |
| `/finance/held-scripts` | Students / Scripts held / Still owing / Closing within 14 days | `assessment.held_scripts_owing()` + `finance.position` | `results/held/owing` | owing readers |
| `/college/dashboard` | Students / Years open / Awaiting the Board / Postings this session; the session by level; the rotation; fees this session | `college.*`, `finance.semester_cleared` | `college/dashboard`, `college/exams/summary` | provost, collegesecretary (financecontroller sees the Payment Report) |
| `/college/coordinator` | Level / Cohorts running / Students at the level / Awaiting the Board; results by subject | level-bound | `college/coordinator` | mbbscoordinator |
| `/college/examinations` | Cohort / Subject results / Decisions / Ready for Senate | `college.exam_result`, `progression_decision` | `college/exams/{code}/…` | `READERS` |
| `/college/payments` | Payment position tiles | `finance.payment_position` | `college/payments` | `PAYMENT_READERS` |
| `/finance/fees` | Items stated / Charge to everybody / Confirmed this session / References waiting | `finance.fee_schedule`, `payment_reference` | schedule, references | finance readers |
| `/finance/payments` | Payments matched / Total collected / Showing / Scope | confirmed references | `finance/payments` | finance readers |
| `/finance/gateways` | Gateways live / Events today / Settled, all time / Exceptions open | `gateway_event`, `gateway_credential` | `payments/bursary` | `READERS` |
| `/finance/hanging` | Hanging now / Resolved without a person / Needs a person / The sweep (**static "Every 10 min"**) | attempts and events | `payments/bursary` | `may` |
| `/finance/exceptions` | Open / Proposed / Posted / Cash ceiling (**hard-coded ₦1,000**) | `finance.bank_credit` | `finance/bank-credits` | bursar, admin |
| `/finance/refunds` | Awaiting approval / Approved, to pay / Paid / All (**static "Newest 300"**) | `finance.refund` | `finance/refunds` | refunds readers |
| `/finance/nelfund` | Received this session / Allocated to students / Unallocated / Reversed to the Fund; Applied / Approved / Not approved / Still with the Fund; Funded / Applied to school fees / Withdrawn / Held in wallets | `nelfund_*`, `wallet_entry`, `funding_summary` | `nelfund/sessions/{s}`, `funding/sessions/{s}/report` | `READERS` |
| `/finance/reconcile` | Gateway settled / Matched / Exceptions / Hanging; Confirmed in the window / Matched to the bank / Discrepancies / Not yet checked | events; `payment_reconciliation` | `payments/bursary`, `finance/reconciliation` | readers |
| `/finance/ledger` | Collected / By card / By bank / From the wallet | `finance.day_book` | `finance/ledger` | readers |
| `/finance/accounting` | Cash & bank on the books / Income this year / Expenditure this year / Surplus (deficit) | `finance.gl_*` (accounts 1010/1020/1050) | `finance/accounting/overview` | readers |
| `/finance/budget` | Budget / Committed / Spent / Over budget | `expenditure.budget`, vouchers CLEARED/PAID | `expenditure/budget` | readers |
| `/finance/tenders` | Open tenders / Awarded / All / (**empty placeholder tile**) | `expenditure.tender` | `expenditure/tenders` | readers |
| `/finance/requisitions` | Awaiting approval / Approved / PO / Value awaiting / Requisitions | `expenditure.requisition` | `expenditure/requisitions` | readers |
| `/vouchers` | On the audit desk / Queries open / Cleared to pay / All | `expenditure.voucher`, `voucher_query` | `expenditure/vouchers` | readers |
| `/stores` | Inventory items / Below reorder / Fixed assets / Not verified in a year | `expenditure.store_item`, `asset` | `stores/items`, `stores/assets` | readers |
| `/audit/revenue` | Fees collected / Confirmed today / Still owed / Open exceptions (session **hard-coded 2026/2027**) | `finance/bursary`, `reports/revenue` | as named | audit |
| `/audit/staff` | On the establishment / Academic / Monthly gross / Last payroll paid | `hrm.employment`, `pay_run` | `payroll/staff`, `payroll/runs` | audit |
| `/audit/assets` | Assets on the register / Book value / Never verified / Overdue verification | `expenditure.asset` | `stores/assets` | audit |
| `/payroll` | Runs / Awaiting approval / Approved, to pay / Last net paid | `hrm.pay_run` | `payroll/runs` | readers |
| `/payroll/variance` | Joined / Left / Changed / Net change | `hrm.payslip` two runs | `payroll/variance` | readers |
| `/staff` | On the roll / Academic / Non-academic / Monthly gross | `hrm.employment` | `payroll/staff` | readers |
| `/hr/leave` | Awaiting decision / On leave today / Approved / Requests | `hrm.leave_request` | `hr/leave` | approvers |
| `/hr/movements` | Awaiting approval / Approved no letter / Implemented / Movements | `hrm.movement` | `hr/movements` | readers |
| `/hr/recruitment` | Open vacancies / Applications / Shortlisted / Posts | `hrm.vacancy`, `applicant` | `hr/vacancies` | `may` |
| `/hr/appraisal` | On the establishment / Meet the years rule / Appraised this cycle / Academic | `hrm.promotion_view` | `hr/appraisal` | readers |
| `/me` | Leave taken (**30 − balance, hard-coded 30**) / Leave remaining / Last payslip / Appraisal (**"—" placeholder**) | `hrm.leave_balance`, `payslip` | `me/leave`, `me/payslips` | any staff |
| `/hod/staff` | Staff on the establishment / Hold a teaching office / Professors | `hrm.staff_record`, offices | `hod/staff` | hod |
| `/hostel` | Total beds, Occupied, Reserved, Available, Under maintenance, Students accommodated, Applications, Allocated, Waitlisted, Checked out, Pending clearance, Open maintenance; waiting-at-desk counts; seven charts | `hostel.*` bed board and applications | `hostel/sessions/{s}/dashboard` | `READERS` |
| `/hostel/inventory` | Beds / Occupied / Reserved / Available / Maintenance | `hostel.bed`, allocations | `hostel/inventory` | `READERS` |
| `/helpdesk` | Total tickets / New / Opened / In progress / Unassigned / High priority / Overdue / Average resolution; agent workload; by category | `helpdesk.ticket`, SLA | `helpdesk/stats` | `AGENTS` (director panels `DIRECTOR`) |
| `/helpdesk/reports` | Tickets / Overdue / Average first response / Average resolution; monthly volume; breakdowns | same | `helpdesk/stats?…` | `DIRECTOR` |
| `/tickets` | Open / Awaiting your confirmation / Closed / All | own tickets | `helpdesk/my/tickets` | requester |
| `/support` | Open (oldest age) / Answered still open / Resolved / All | `platform.service_request` | `support/requests` | `OFFICES` |
| `/clinic` | Encounters today / Awaiting triage / Referrals this month / Fitness recorded | `health.*` | `health/desk` | `CLINIC` |
| `/credentials/documents` | New requests / Payment pending / Held at clearance / Processing / Quality check / Awaiting release / Ready for delivery / Delivered / Breaching SLA / Certificates issued / Transcripts issued / Revoked · reissued · flagged; charts; revenue by month; suspected forgeries | `credentials.*` | `documents/dashboard` | `READERS` |
| `/credentials/transcripts` | Open requests / Held at clearance / Breaching SLA / Average turnaround | legacy queue | `credentials/transcript-requests` | readers |
| `/credentials/certificates` | Graduands {year} / Certificates printed / Collected / Security stock left | `credentials.certificate`, `stationery_batch` | `credentials/certificates` | readers |
| `/credentials/idcards` | Waiting for a card / Live cards / Lost or replaced / Issued today | `credentials.identity_card` | `credentials/identity-cards` | `READERS` |
| `/student/documents` | Certificates / Transcripts & statements / Pending requests / Available downloads | own documents | `me/documents` | student |
| `/student/fees` | Session charge / Paid / Outstanding | `finance.charges`, `position` | `me/fees` | student |
| `/student/wallet` | Wallet balance / Funded / Applied to your invoices / Outstanding on your account | `finance.wallet_entry`, position | `me/wallet` | student |
| `/student/results` | This semester / Cumulative / Standing / Units this semester | `assessment.student_gpa`, `policy.class_of` | `me/results` | student |
| `/student/query` | Window / Your queries / Answered / Marks corrected | `assessment.result_query` | `me/queries` | student |
| `/student/registration-history` | Registrations / Courses registered / Carryovers / Identifier | `registration.*` | `me/registration-history` | student |
| `/student/pg-progress` | Units earned / Courses passed / CGPA / Graduation | `pg/coursework/summary` | same | PG student |
| `/applicant` | Application number / Programme applied for / UTME score / Stage n of 10 | `application_stage` | `applicant/me` | applicant |
| `/reports` | Overdue / Due within 30 days / Kept copies / Filed | `reports.due_register`, `snapshot` | `reports/due`, `reports/snapshots` | snapshot `READERS` |
| `/reports/students`, `/reports/staff` | Matched / Active / Female–Male / Postgraduate; Matched / Academic / Active / Female–Male | register rows | `reports/registers/{kind}` | registers `READERS` |
| `/stats` | All students / School fees paid / Course registered / Paid but not registered / Not paid / No charge stated / Not registered; donuts; bars | `reporting.student_positions` (ACTIVE, PROBATION, ADMITTED) | `stats/students/summary` | stats `READERS` |

---

## 6 Reports and exports catalogue

**S/N rule:** every export that goes through `frontend/src/lib/exportbrand.ts` (`brandedXlsx`, `brandedPrint`) puts **S/N** as the first column, generated at export time, prints the University's name and crest, a serial `MOAUM/<TAG>/yyyymmdd/hhmmss[-rr]`, and sorts names A–Z. Exports built with the plain `buildXlsx`, the `csv/download` helpers or a hand-built print window do **not** follow the S/N rule unless stated.

| Report | Module | Offices | Filters | PDF | Excel | CSV | Description | S/N rule |
|---|---|---|---|---|---|---|---|---|
| Admissions cycle return | Reports | `ENROLMENT_READERS` | session | Print | Branded workbook | — | Applications, screened, offered, accepted per programme | No (ReportDoc + `buildXlsx`) |
| Enrolment by faculty/programme/level | Reports | `ENROLMENT_READERS` (scope-cut) | session | Print | Branded workbook | — | Students by entry session, split M/F/unstated | No |
| Registration cause | Reports | `ENROLMENT_READERS` | session, semester | Print | Branded workbook | — | expected, registered, not registered, fee-blocked, cleared idle per programme | No |
| Carryovers | Reports | `ENROLMENT_READERS` | session (as at today) | Print | Branded workbook | — | Failed non-elective courses per faculty/programme/course | No |
| Staff–student ratio | Reports | `STAFF_RATIO_READERS` | — | Print | Branded workbook | — | academic staff by rank bucket, students, ratio per department | No |
| Postgraduate return | Reports | `PG_READERS` | session | Print | Branded workbook | — | applications → offered → accepted → admitted; register; researching; awarded | No |
| Revenue by category | Reports | `REVENUE_READERS` | session | Print | Branded workbook | — | confirmed references by purpose + applicant fees | No |
| Funding report | Reports/Wallet | `REVENUE_READERS`, wallet readers | session | Print | Branded workbook | — | by source, cash-flow reconciliation | No |
| Expenditure (budget performance) | Reports/Expenditure | `REVENUE_READERS` | year | Print | Branded workbook | — | budget, committed, spent, available per cost centre | No |
| Income & expenditure | Reports/GL | `REVENUE_READERS` | year | Print | Branded workbook | — | GL income/expense with surplus and budget block | No |
| Student register | Reports | registers `READERS` (scope-cut) | faculty, department, programme, level, sex, status, entry mode, entry session, search | Print view (≤ 5 000 rows, PARTIAL beyond) | `students-register-<date>.xlsx` (all rows, 500 at a time) | — | Every `people.student` | Crest-branded; no S/N column |
| Staff register | Reports | registers `READERS` | faculty, department, rank, category, status, office held, search | Print view | `staff-register-<date>.xlsx` (16 columns) | — | Every person with a staff number | Crest-branded; no S/N column |
| Kept copy (snapshot) | Reports | snapshot `READERS` | — | Server PDF for email; print | Workbook | — | A return as taken, with verification code; emailed with both attached | As its return |
| Trends | Reports | readers except dean, facultyofficer, hod | — | — | — | — | Last three sessions and six months (on screen) | — |
| Student statistics detail | Statistics | stats `READERS` | session, semester, faculty, department, programme, level, status, degree, figure, search | `brandedPrint` | `brandedXlsx` | — | Students behind a figure with fee and registration position | **Yes** (serial STAT) |
| Payments query | Finance | finance readers | session, faculty, department, programme, level, category, channel, dates | `brandedPrint` | `brandedXlsx` (rows loaded on the page only) | — | Confirmed payments with breakdowns | **Yes** (PAY) |
| Day book / journal export | Finance | finance readers | from, to | — | Branded xlsx (named `.csv` in code) | — | Confirmed references in the window | Branded; no S/N |
| Fee schedule | Finance | finance readers | faculty, semester, spillover | Hand-built print window | Plain `buildXlsx` | — | The session's lines | No |
| Student Payment Report / Summary / by Programme | College | `PAYMENT_READERS` | session, period, department, programme, level, status, search | `brandedPrint` | `brandedXlsx` | — | Payment position of College students | **Yes** (CHSPAY) |
| Computed Post-UTME | Admissions | academic, super | session | `brandedPrint` | `brandedXlsx` | — | Non-index and DE candidates scored from O'Level + UTME | **Yes** (CPU) |
| Screened pool (summary, detail, all O'Level) | Admissions | `READERS` | session, programme | Print | Excel | — | Applied, screened, quota, cut-off; per-candidate detail | Branded where through `exportbrand` |
| Screening register non-index scores | Admissions | `READERS` | session | — | — | CSV | key, score pairs | No |
| Awaiting scores; score template; migration template and problem rows | Admissions | uploaders | — | — | Template xlsx | CSV | Working files | No |
| JAMB admission template | Admissions | `LOADERS` | programme or all | — | Five-sheet workbook in JAMB's layout | — | Admission_Summary, Merit_List, Other_Qualified_Cases, Non_Qualified_Cases, Ranked_sheet | No (JAMB layout) |
| Hall list (legacy batch) | Admissions | `READERS` | batch | Print | — | — | Seats with photographs | No |
| CBT batches | Admissions | `READERS` | session | `brandedPrint` | `brandedXlsx` | — | Batch, day, time, centre · room, capacity, assigned, checked in, state | **Yes** (CBT) |
| CBT candidates | Admissions | `READERS` | standing, faculty, department, programme, batch, centre, search | PDF | Excel | — | Every candidate's standing and seat | **Yes** |
| CBT attendance sheet (per batch) | Admissions | `READERS` | batch | Print | Excel | — | Photograph, attendance, signature line | Yes |
| Postgraduate applications | PG admissions | `READERS` | session | — | `brandedXlsx` | — | Application number, applicant, programme, award, department, faculty, level, session, fee, status, submitted | **Yes** (PGAPP) |
| PG course template | PG coursework | `DESK` | — | — | Template | — | Programme, Course Code, Title, Units, Kind, Semester | No |
| Examiner reports (8 kinds) | External examiners | `DESK` | session, faculty, department, programme, examiner, status, dates | — | — | CSV (three-line header) | Examiner, workload, department, programme, assessments, pending, overdue, submitted | No |
| Faculty list (matriculation) | Matriculation | `OFFICERS` | session, faculty | — | — | CSV | Admission number, Name, Department, Units, State | No |
| Matriculation Number Configuration | Matriculation | `READERS` | faculty, search | `brandedPrint` | `brandedXlsx` | — | S/N, Faculty, Programme, Programme Ref, Faculty Segment, Programme Code, Carries Code, Series, Next Number, Problem | **Yes** (MAT) |
| Deferments desk list | Deferments | `DESK` | session, semester, type, status, unit, search | `brandedPrint` | `brandedXlsx` | — | Deferment Number, Student ID, Student Name, Faculty, Department, Programme, Type, Session, Semester, Status, Request Date, Approval Date, Expected Return | **Yes** (DEF) |
| Held list | Clearance | readers | purpose, scope | — | — | CSV | Matriculation number, Name, Programme, unit states | No |
| Class list / Attendance register / Examination roll | Registration | `READERS` | course, session, semester | — | — | CSV | The offering's roll | No |
| Faculties / Departments / Programmes | Structure | ict | — | `brandedPrint` | `brandedXlsx` | — | Code, name, counts | **Yes** (FAC / DEP / PRG) |
| Courses offered to a programme; whole catalogue | Catalogue | ict | programme, curriculum | `brandedPrint` | `brandedXlsx` | — | Faculty, Programme Code, Programme, Level, Semester, Course Code, Title, Units, Kind, Basis, Curriculum | **Yes** (CRS / CAT) |
| Score-sheet template | Results | `ENTRY` | sheet | — | xlsx (also csv) | csv | S/N, Matriculation number, Name, Programme, Level, CA, Exam, Outcome with validations | Yes (S/N in the roll) |
| Marked sheet | Results | `READERS` | sheet | Landscape PDF | xlsx | — | Marks plus a performance summary; "The record is the register, not this print." | Yes |
| Upload validation report | Results | `ENTRY` | — | — | — | CSV | Line, Refused because | No |
| Held-scripts template | Results | `ENTRY` | — | — | xlsx | — | 30 blank lines | Yes |
| Broadsheet (Examination reporting sheet) | Results | `READERS` (programme bound) | programme, level, session, semester | Print window | Two-sheet workbook | — | Summary and Broadsheet with Senate lists | Serial BRD; S/N in the sheet |
| College score sheet / marked sheet | College | `EXAMINERS` | cohort, level | — | xlsx | — | Per-subject CA/Exam/Clinical/Attendance; marked with decisions — **wrong letterhead** | S/N present; letterhead defect |
| College results and decisions | College | `READERS` | exam, session | — | — | CSV | Candidates' results and decisions | No |
| Hostel Occupancy by Hall; Inventory; Bed Inventory; Applications (17 columns); Bed Board / Occupancy — Students; Clearance; Checkout Requests; Transfer Requests | Hostel | `READERS` | per screen | `brandedPrint` | `brandedXlsx` | — | As named | **Yes** (HST) |
| ICT support report | Help desk | `DIRECTOR` | dates, category, priority, agent, faculty, department | — | — | CSV | Report, Item, Tickets, Open, Done, Overdue, Average resolution (h) | No |
| Graduates Awaiting Certificate; Document Requests (16 columns); Issued Documents (14 columns); Document Verifications | Documents | `READERS` | per screen | `brandedPrint` | `brandedXlsx` (verifications PDF only) | — | As named | **Yes** (DOC) |
| Teaching staff template; Non-academic staff template | Identity | loaders | — | — | Template | — | PNO, Full Names, Sex, Date of 1st Appt, Department, Present Rank, Phone No, CONUASS/CONTISS | No |
| Payment history template; Old fees history template; NELFUND remittance template | Finance | bursar | — | — | Template | — | Working files with sample rows | No |
| Any DTable | every screen | as the screen | the table's own search | Iframe print (panel title, University name, date) | — | — | Whatever the table shows | No |

> **Note:** No export exists for: the audit trail, the outbox, the NELFUND tabs, the Bursary held-scripts list, payroll (no payslip PDF or bank schedule), vouchers, requisitions, tenders, budget, stores, the Senate schedule, the alumni register, the records workbench, the register list on `/students`, PG registrations/results/register/pipeline, or the examiner assessments (CSV summaries only).

---

## 7 Generated documents catalogue

All PDFs are drawn by Next.js route handlers with `frontend/src/lib/pdf-write.ts` and the crest header; the passport is embedded only as JPEG. "Verification" names the public page the QR or code opens.

| Document | Route | Who generates | When available | Contents | Verification | Versioning | Security |
|---|---|---|---|---|---|---|---|
| Application form | `/applicant/apply/pdf` | Applicant | Any time (says "Not yet submitted" before submission) | Passport, 11 biodata rows, O'Level sittings, submitted date, footer with APP number | None | None | Applicant's own token |
| Post-UTME examination slip | `/applicant/screening/slip` | Applicant | Once seated in a PUBLISHED batch (409 "No examination slip yet" before) | Exam name and session, passport, name, APP/JAMB, programme, POSTPONED/CANCELLED banner, Batch, Date, Report by, Examination, Centre, Room, Seat, Workstation, address, QR, instructions, what to bring | `/verify/putme/{token}` (public, unthrottled) | Token fixed per application | Photo and personal data on the public page |
| Admission letter | `/applicant/status/letter` | Applicant | After OFFERED released **and** accepted (409 "No offer to print" / "Accept your offer first") | "Office of the Registrar · Academic Affairs", Our ref, "OFFER OF PROVISIONAL ADMISSION" with level, programme, faculty, session, basis, provisional terms, "As screened" box, "Registrar / For: Vice-Chancellor" | None | None | — |
| PG application summary | `/pg/summary/pdf` | PG applicant | Any time | APPLICATION (passport), APPLICANT, QUALIFICATIONS, RESEARCH PROPOSAL, REFEREES, "Documents on file" | None | None | — |
| PG confirmation of offer of admission | `/pg/offer/pdf` | PG applicant | After the acceptance fee is confirmed (409 "Offer letter not available yet") | "(Office of the Registrar)", DATE, APPLICANT'S NAME, APPLICATION NUMBER, "CONFIRMATION OF OFFER OF ADMISSION", COURSE/PROGRAMME/FACULTY/LEVEL/DURATION, six notes, signed "Ajuma Isaac Ugbabe, Secretary, Postgraduate School" (hard-coded), QR text `MOAUM PG {applicationNo}` | **None** (QR is decorative) | None | — |
| PG merged documents | `GET /api/v1/pg/applications/{id}/documents.pdf` | PG admissions desk | Once documents exist | Every uploaded PDF concatenated plus the passport page | None | None | `READERS` |
| Course registration form | `/student/form/pdf` | Student | Registration APPROVED/LOCKED | Brand header, passport, name/matric/programme/level/session/semester/date, CODE · COURSE TITLE · UNIT · TYPE (carryovers red, first), total units, signature lines "Head of Department / Level Coordinator", "Dean of Faculty", registration id prefix | `/verify/registration?m&s&sem&c` (SHA-256 check code) | None | Public page only with the code |
| Examination card | `/student/exams/card/pdf?session&semester` | Student | Approved registration and cleared for examinations (409 otherwise) | Crest watermark, matric watermarks, photo, candidate block, COURSE CODE · TITLE · UNIT · SIGN/INVIGILATOR, 8 instructions, 14 regulations | `/verify/exam?m&s&sem&c` | None | Check code |
| Semester Results (statement) | `/student/results/{session}/{semester}/pdf` | Student | A published semester and results not withheld (409 "Withheld" / "Nothing published") | "Semester Results · Exams & Records", COURSE / UNIT / SCORE / GRADE / POINTS, totals, Semester GPA / Cumulative GPA / Class of standing, SUMMARY line, GRADING key (**hard-coded**), "Approved by Senate on … · minute X" | `/verify/results?m&s&sem&c` + "Check code" | None | Check code |
| Result broadsheet (student) | `/student/broadsheet/pdf` | Student | Any published semester (409 "Withheld") | Per semester COURSE/TITLE/UNIT/CA/EXAM/TOTAL/GRADE/PT and the summary line | None | None | — |
| Payment receipt | `/student/receipt/{reference}/pdf` | Student | Reference confirmed (409 "Not confirmed") | "Official Payment Receipt · Bursary Department", passport, receipt no, date, payer block, BEING PAYMENT FOR/AMOUNT, TOTAL RECEIVED, channel, teller ref, microtext band, "SCAN TO VERIFY" | `/verify/receipt/{ref}?c=` (first 12 hex of SHA-256(reference‖receiptNo)) | None | Token-gated |
| Student identity card (printable copy) | `/student/idcard/pdf` | Student | A card ISSUED (409 "No identity card issued") | FRONT: name, matric, STUDENT tag, Faculty, Level, Programme, Blood group "—", Admitted, Graduates "—", session, valid to, serial; BACK: Code-128 barcode of the matric number, conditions, QR text `MOAUM ID {serial}`, emergency phone, "Registrar" | **None** | Card number | Not a verification URL |
| Staff identity card | `/staff/idcard/pdf[?id=]` | Staff member (own) or an office for another | Person has a staff number (409 "No staff number") | Name, staff number, Rank, Category, Department/Unit, Faculty, Appointed, Office, "Valid to" (31 Dec + 3 years, computed), serial `STF-…-{year}` (computed), JPEG photo only | None | **Nothing stored** | — |
| Deferment approval letter | `/student/deferment/letter/{id}`; `/deferments/{id}/letter` | Student (own); desk within bound | APPROVED / ACTIVE / COMPLETED (409 "The letter is issued once the deferment is approved.") | Crest, "P.M.B 102119, Makurdi", REF/DATE, "DEFERMENT APPROVAL LETTER", student block, period, effective from, expected return, approved on/by, remarks, four notes, "Registrar" | QR/URL `/verify/deferment/{reference}` — **route does not exist** | None | Dead verification link |
| Inter-departmental transfer approval letter | `/student/transfer/letter/{id}` (printable page) | Student | After EFFECTED | Letter citing Senate/SAIC and a **hard-coded ₦10,000**, signed "Deputy Registrar, Academic Office for: Registrar" | None | None | Wording does not match the pipeline path |
| Transfer memo | `/transfers/memo?type=` | Office | Any time | "Recommended List of Inter-Departmental Transfer Candidates" / "Non-Recommended / Withdrawn…" for the DVC (Academic) / Chairman, SAIC | None | None | — |
| Hostel allocation letter | `/student/hostel/letter?session=` | Student | Fee confirmed (409 "No allocation letter" while HELD/LAPSED/DECLINED/CANCELLED) | "HOSTEL ALLOCATION LETTER", reference, Student…Fee columns, terms, instructions, rules (version, first 2600 chars), signature "Deputy Registrar (Housing, Welfare and Passages)" | `/verify/hostel/{reference_no}` (**no token, no throttle**) | Rules version printed | Enumerable reference |
| Hostel clearance certificate | `/student/hostel/clearance?session=` | Student | Clearance CLEARED (409 "No clearance certificate") | Student, programme, session, placing, checked in/out, each requirement with state and remarks, certifying paragraph | `/verify/hostel/{allocation ref}` | None | As above |
| Degree certificate (digital) | `/student/documents/{id}/pdf`; `/credentials/documents/register/{id}/pdf`; `/documents/d/{token}/pdf` | Signers issue; student, office, recipient download | GRADUATED + Senate APPROVED + convocation cleared | The University's own layout: crest, number, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY / MAKURDI, BENUE STATE, NIGERIA", "This is to certify that", holder, award, class, seal and date, two signatories, QR and "Verify this certificate" with the code | `/verify/document/{code}` (throttled, logged) | Version n; REPLACED / REVOKED watermark | Hash-only integrity (no signing key); every download logged |
| Official full / sessional / mini transcript; Statement of academic record | same routes | Office pipeline; free kinds at once | Per policy (fee, clearance, published results) | Multi-page: matriculation number, programme, sessions and semesters with code, title, units, grade, points, GPA/CGPA, "GRADING SCALE", class of degree, footer "Not valid without the verification reference.", signatory, QR | `/verify/document/{code}` | Versioned; template version kept | As above |
| Kept return (snapshot) PDF | server-built in `POST /reports/snapshots/[id]/email` | Reports desk | When emailing a kept copy | The return as taken with the verification code | `/verify/report/{code}` | Snapshot is write-once | — |
| Return / register print views | `/reports/{slug}/view`, `/reports/students/view`, `/reports/staff/view` | Readers | Any time | Branded ReportDoc; registers capped at 5 000 rows (PARTIAL) | Kept copies only | — | — |
| Marked score sheet PDF | `/results/sheets/{id}/marked?format=pdf` | Results readers | Once anything is entered | Landscape A4 marks and performance summary; "The record is the register, not this print." | None | — | — |
| Broadsheet PDF | print window on `/results/broadsheet` | Readers | Any time | "Examination Reporting Sheet" cover and lists; serial BRD | None | — | — |
| Fee schedule PDF | print window on `/finance/fees` | Finance readers | Any time | Heading, subtitle, Item / Applies to / Amount | None | — | — |
| Any DTable print | every table | Any viewer | Any time | The table with the panel title, University name and date | None | — | — |

> **Planned / Not Yet Implemented:** payslip PDF, voucher PDF, purchase order, appointment or promotion letter, external-examiner appointment letter or assessment PDF, College transcript, result slip or Board schedule, ticket printout, identity-card verification page, deferment-letter verification page.

---

## 8 Notifications catalogue

Every notice is a `platform.notice` row queued by `platform.queue_notice` and dispatched by `NoticeDispatcher` (§3.3). Email goes by SMTP (Mail Server), an HTTP relay, or not at all; SMS by eBulkSMS or a relay. Recipient "student" means the addresses from `people.student_reach` (student contact, else the applicant account); "applicant" the applicant account's email and phone; "desk" the current holders of the named offices. Subjects are quoted as written in the code.

| Event | Trigger | Recipient | Channel | Subject | Module |
|---|---|---|---|---|---|
| Password reset requested | `PasswordResetService.forgot` | account holder | Email + SMS | "Reset your MOAUM password" | Sign-in |
| Applicant account created | `ApplicantService.register` | applicant | Email + SMS | "Your MOAUM applicant account" / "MOAUM applicant account" | Applicant portal |
| Applicant password reset asked | `ApplicantService.forgot` | applicant | Email + SMS | "Reset your MOAUM application password" | Applicant portal |
| Application / acceptance fee confirmed | `admissions.confirm_fee` | applicant | Email + SMS | "Your payment receipt · RCT-…" | Applicant portal |
| Seated in a legacy screening batch | `admissions.assign_screening` | applicant | Email + SMS | "Your screening slip is ready" | Admissions |
| CBT schedule published | `putme_publish` | each candidate in a DRAFT batch | Email + SMS | "Your Post-UTME examination schedule" | Admissions (CBT) |
| CBT seating moved (published batch) | `putme_move` | candidate | Email + SMS | "Your Post-UTME schedule has changed" | Admissions (CBT) |
| CBT seating withdrawn | `putme_unschedule` | candidate | Email + SMS | "Your Post-UTME seating has been withdrawn" | Admissions (CBT) |
| CBT batch postponed / cancelled | `putme_batch_state` | every candidate of a published batch | Email + SMS | "Your Post-UTME batch has been postponed/cancelled" | Admissions (CBT) |
| Screening scores released | `release_scores` | applicant | Email + SMS | "Your screening result is released" | Admissions |
| Decision released | `release_decisions` | applicant | Email + SMS | "You have been offered provisional admission" / "You are on the waiting list" / "The admission decision on your application" | Admissions |
| Acceptance settled | `settle_acceptance` | applicant | Email + SMS | "Your place is held" | Applicant portal |
| Clearance query | `clear_document` (QUERY) | applicant | Email + SMS | "A query on your clearance documents" | Admissions |
| Cleared (6/6) | `clear_document` | applicant | Email + SMS | "You are cleared" | Admissions |
| Reconsideration suggestion | `ApplicantsController.suggestOne` / `notifySuggestions` | applicant | Email | "Your {session} admission — a suggested programme" | Admissions |
| PG application received | `pg_application_trail` (insert) | PG applicant | Email | "Your MOAUM postgraduate application has been received" | PG admissions |
| PG DRAFT → SUBMITTED (legacy path) | trail | PG applicant | Email | "Your MOAUM postgraduate application has been submitted" | PG admissions |
| PG application fee confirmed | trail | PG applicant | Email | "Your application fee is confirmed" | PG admissions |
| PG School decided | `PgAdmissionsController.spgsDecision` | PG applicant | Email | "A decision on your MOAUM postgraduate application" | PG admissions |
| PG checking fee confirmed | trail | PG applicant | Email | "Your admission decision is ready to view" | PG admissions |
| PG accepted | trail | PG applicant | Email | "Your offer of admission is accepted" | PG admissions |
| PG admitted | trail | PG applicant | Email | "You are admitted — your student record is open" | PG admissions |
| PG referee named | `PgPortalController.referees` | referee | Email | "Reference request — {applicant} (MOAUM Postgraduate)" | PG admissions |
| PG reference received | `pg_referee_trail` | PG applicant | Email | "A reference has been received" | PG admissions |
| PG summary requested | `emailSummary` | PG applicant | Email | "Your MOAUM postgraduate application summary" | PG admissions |
| PG research stage changed | `admissions.pg_research_trail` | PG student | Email | "Your research: {stage words}" | PG research |
| Examiner invitation / resend | `ExaminersController.invite` | examiner | Email | "External Examiner Appointment — {University}" | External examiners |
| Examiner account activated | `activate` | inviter + every `academic` holder | Email | "External examiner account activated — {name}" | External examiners |
| Examiner appointment recorded | `appoint` | examiner | Email | "External Examiner Appointment — …" | External examiners |
| Project assigned / reassigned to | `assign`, `reassign` | new examiner | Email | "New Project Assigned for Review — …" | External examiners |
| Project reassigned away / withdrawn | `reassign`, `withdraw` | old examiner / examiner | Email | "Project Assignment Withdrawn — …" | External examiners |
| Review deadline changed | `deadline` | examiner | Email | "Review Deadline Changed — …" | External examiners |
| Review reminder (≤ 3 days) | `ExaminerReminders` (07:15 Lagos) | examiner | Email | "Reminder: Project Review Deadline — …" | External examiners |
| Review overdue | `ExaminerReminders` | examiner; assigner + academic | Email | "Project Review Overdue — …" / "External examiner review overdue — {number}" | External examiners |
| Assessment submitted / resubmitted | `submit` | assigner + academic; examiner | Email | "External Examiner Assessment Submitted — {number}" / "Assessment Received — …" | External examiners |
| Assessment reopened | `reopen` | examiner | Email | "Assessment Reopened for Revision — …" | External examiners |
| Assessment locked | `lock` | examiner | Email | "Assessment Approved and Locked — …" | External examiners |
| Matriculation number issued | `people.matric_tell` | student | Email + SMS | "Your matriculation number" | Matriculation |
| Deferment submitted | `deferment_submit` | student; department `hod` | Email + SMS; Email | "Your deferment request has been received"; "A deferment request awaits the department" | Deferments |
| Department recommended | `deferment_decide RECOMMEND` | student; faculty `dean` | as above | "Your deferment request is recommended by the department"; "A deferment request awaits the faculty" | Deferments |
| Faculty recommended | `FAC_RECOMMEND` | student; `academic` | as above | "Your deferment request is recommended by the faculty"; "A deferment request awaits approval" | Deferments |
| Deferment approved | `APPROVE` | student | Email + SMS | "Your deferment request DEF-… has been approved" | Deferments |
| Deferment rejected | `REJECT` | student | Email + SMS | "Your deferment request has been rejected" | Deferments |
| Correction requested | `CORRECTION` | student | Email + SMS | "Your deferment request requires correction" | Deferments |
| Deferment cancelled | `CANCEL` | student | Email + SMS | "Your deferment request has been cancelled" | Deferments |
| Deferment in force | `deferments_tick` (06:20 Lagos) | student | Email + SMS | "Your deferment is now in force" | Deferments |
| Return approaching | `deferments_tick` | student; `hod` | Email + SMS; Email | "Your deferment is ending soon"; "A student is due to return from deferment" | Deferments |
| Return confirmed | `deferment_confirm_return` | student | Email + SMS | "Welcome back — your return from deferment is confirmed" | Deferments |
| Award approved by Senate | `records.approve_awards` | each graduand | Email + SMS | "Senate has approved your award" | Graduation |
| Script held | `HeldScriptsController.tellStudents` | student | Email + SMS | "Your {code} script is held until you register" | Held scripts |
| Result query answered | `assessment.answer_query` | student | Email; SMS | "Your result query {ref} is answered"; "Your result query is answered" | Result queries |
| Payment confirmed (every path) | `finance.confirm_payment` | student | Email; SMS | "Your payment is confirmed"; "MOAUM: payment {ref} confirmed, receipt {no}." | Payments |
| Kept return emailed | `SnapshotsController.email` | each address typed | Email (+ PDF and workbook) | "<title> · <period> — Rev. Fr. Moses Orshio Adasu University" | Reports |
| Hostel window created / opened | `HostelLifecycleController.window` (≤ 5 000 eligible) | every eligible student | Email + SMS | "Hostel applications are open" | Hostel |
| Hostel application received | `hostel.apply` | student | Email + SMS | "Your hostel application is in" | Hostel |
| Application awaits review | `hostel.apply` (requires_review) | desk (housing, services) | Email | "A hostel application awaits review" | Hostel |
| Review decided | `hostel.review` | student | Email + SMS | "Your hostel application is approved" / "…was not approved" / "…is on the waiting list" / "…needs a correction" | Hostel |
| Bed allocated | `hostel.draw`, `hostel.allocate` | student | Email + SMS | "You have been allocated a bed" | Hostel |
| Waitlisted by the draw | `hostel.draw` | student | Email + SMS | "Your hostel application is on the waiting list" | Hostel |
| Hold lapsed | `hostel.lapse_holds` (hourly) | student | Email + SMS | "Your hostel hold has lapsed" | Hostel |
| Bed offered from the list | `hostel.lapse_holds` | next student | Email + SMS | "A hostel bed has been offered to you" | Hostel |
| Hostel fee confirmed | `hostel.confirm_by_reference` | desk | Email | "A hostel fee has been confirmed" | Hostel |
| Allocation accepted | `hostel.accept` | student | Email + SMS | "Your hostel allocation is accepted" | Hostel |
| Allocation declined | `hostel.decline` | desk; student | Email; Email + SMS | "A hostel allocation was declined"; "Your hostel allocation is declined" | Hostel |
| Checked in | `hostel.checkin` | student | Email + SMS | "You are checked in" | Hostel |
| Transferred | `hostel.transfer` | student | Email + SMS | "Your hostel room has changed" | Hostel |
| Transfer requested | `hostel.request_transfer` | desk; student | Email; Email + SMS | "A room transfer is requested"; "Your transfer request is in" | Hostel |
| Transfer refused | `hostel.decide_transfer` | student | Email + SMS | "Your transfer request was not approved" | Hostel |
| Checkout requested | `hostel.request_checkout` | desk; student | Email; Email + SMS | "A checkout is requested"; "Your checkout request is in" | Hostel |
| Clearance started | `hostel.start_clearance` | student | Email + SMS | "Your hostel clearance has started" | Hostel |
| Damage charge | `hostel.charge` (> 0) | student | Email + SMS | "A hostel damage charge stands against you" | Hostel |
| Clearance complete / outstanding | `hostel.complete_clearance` | student | Email + SMS | "Your hostel clearance is complete" / "Your hostel clearance has outstanding items" | Hostel |
| Allocation cancelled by the desk | `hostel.cancel` | student | Email + SMS | "Your hostel allocation is cancelled" | Hostel |
| Maintenance raised | `HostelLifecycleController.raise` | desk | Email | "A hostel maintenance request" | Hostel |
| Maintenance fixed / closed | `HostelLifecycleController.maintenance` | student | Email + SMS | "Your maintenance request is fixed|closed" | Hostel |
| Ticket submitted | `TicketNotifier.submitted` | requester; every agent + Director (if `notify_agents_on_new`) | Email | "ICT Support Ticket Received — {n}"; "New ICT support ticket {n} — {category}" | Help desk |
| Ticket opened / status changed | `statusChanged` | requester | Email | "Update on your ICT support ticket {n}" | Help desk |
| Ticket assigned / reassigned | `assigned` | the agent | Email | "Ticket assigned to you — {n}" / "Ticket reassigned to you — {n}" | Help desk |
| Ticket escalated | `escalated` | person escalated to | Email | "Ticket escalated to you — {n}" | Help desk |
| Ticket resolved | `resolved` | requester | Email | "Your ICT support ticket is resolved — {n}" | Help desk |
| Ticket closed (any actor, incl. auto-close) | `closed` | requester | Email | "Your ICT support ticket is closed — {n}" | Help desk |
| Ticket reopened | `reopened` | assigned agent, else every agent | Email | "Ticket reopened — {n}" | Help desk |
| Agent update (non-internal) | `agentUpdate` | requester | Email | "The ICT desk has an update on {n}" | Help desk |
| Requester update | `requesterUpdate` | assigned agent or the desk | Email | "Update from the requester — {n}" | Help desk |
| Service request answered | `platform.answer_request` | student | Email + SMS | "Your request {ref} is resolved" / "Your request {ref} has an answer" (SMS "Your request {ref}") | Help & Requests |
| Document request submitted | `credentials.request_document` | student; desk (free, non-self-service) | Email + SMS; Email | "Document request {ref} submitted"; "A document request awaits" | Documents |
| Processing started | `start_processing` | student | Email + SMS | "Document request {ref} is being processed" | Documents |
| Document generated | `produce_transcript` | student | Email + SMS | "Document request {ref}: document generated" | Documents |
| QC approved / correction / rejected | `qc_transcript` | student | Email + SMS | "Document request {ref} approved" / "…: correction in hand" / "… rejected" | Documents |
| Released | `release_transcript` | student; recipient email | Email + SMS; Email (secure link) | "Document request {ref}: your document is ready"; "An official document from Rev. Fr. Moses Orshio Adasu University" | Documents |
| Delivery failed / returned | `mark_delivery` | student; desk | Email + SMS; Email | "Delivery of {ref} failed"; "A document delivery failed" | Documents |
| All deliveries done | `mark_delivery` | student | Email + SMS | "Document request {ref} delivered" | Documents |
| Request cancelled | `cancel_request` | student | Email + SMS | "Document request {ref} cancelled" | Documents |
| Certificate issued | `issue_certificate` | student | Email + SMS | "Your digital certificate has been issued" | Documents |
| Document revoked | `revoke_document` | student | Email + SMS | "A document of yours has been revoked" | Documents |
| Document reissued | `reissue_document` | student | Email + SMS | "A document of yours has been reissued" | Documents |
| Document flagged | `flag_documents` | desk (records, academic) | Email | "An issued document may need review" | Documents |
| Secure link resent | `DocumentsController.resend` | recipient | Email | "An official document … (resent)" | Documents |

### 8.1 Events that send nothing

The following acts queue no notice, although several screens or hints imply otherwise:

- **Sign-in and accounts:** sign-in, lockout, password change, bootstrap; person created, credential set or reset (the first password is told out of band); office granted or ended.
- **Platform:** mail/SMS settings, outbox retry, readiness, data resets; governance DPIA and DSR acts; DR drills; API keys.
- **Calendar, structure and catalogue:** every act (session made current, roll-over, course created, bound, live, ended; registration opened).
- **Allocation:** allocating a lecturer; an overload ("reported to the Dean" is a HINT string only).
- **Registration:** submit, approve, return, add, drop; attendance; timetable slots. The student reads a return on the registration screen.
- **LMS:** material published, assignment set, submission marked, CA promoted.
- **Library:** issue, return, fine, waiver, reservation ready.
- **SIWES:** supervisor assigned, marks recorded.
- **Admissions:** JAMB status list upload (`load_jamb_admissions` releases decisions without notifying); offer decline; application submission; CAPS load/commit; settings in force; any notice to an office.
- **PG admissions and coursework:** new or advancing applications (nothing to the HOD, Dean or School); registration endorsement; scores; research document accepted/returned; anything to supervisors or panel members.
- **External examiners:** no SMS at all; nothing to the HOD or the PG School unless they assigned.
- **Student records:** status changes, level corrections, biodata decisions ("the student is notified" on the Biodata Changes screen is not implemented), voluntary withdrawals, migrated clearance.
- **Matriculation:** query, withdraw query, confirm, configuration changes.
- **Transfers:** every act (apply, fee, approvals, decline, effect).
- **Clearance:** clear, hold; "Notify held candidates" answers 202 "The notification module is not on the portal yet; nothing was sent."
- **Graduation:** the degree audit (only Senate approval notifies).
- **Results:** publication of a sheet (students are not told); Remind/escalate of a late lecturer (202, nothing sent); a raised query (the department is not told); returns and approvals in the chain.
- **College of Health Sciences:** registration, results, provisional or confirmed decisions, resit, repeat, withdrawal, graduation, postings, logbooks.
- **Finance:** fee schedule changes, bank credits, refunds, reconciliation, GL journals; imported legacy payments and payment history ("no student is notified" by design); NELFUND matching and reversals; withdrawals approved or paid.
- **Expenditure:** vouchers, queries, budgets, tenders, requisitions, stores, assets, grants.
- **HRM:** leave decisions, payslips, movements, instruments, recruitment, appraisal.
- **Hostel:** only the acts listed above notify; window edits after opening and inventory changes do not.
- **Help desk:** internal notes, priority changes, attachments; no SMS.
- **Help & Requests:** a raised request (the office is not told).
- **Clinic:** every act.
- **Documents:** payment confirmed on a request writes the trail only (the general payment confirmation covers it); identity cards, the printed certificate register and the legacy transcript queue send nothing.
- **Reports:** due or overdue returns (no reminder job).

> **Note:** All of the above hold whether or not a provider is configured. Where no SMTP, eBulkSMS or relay is configured, every notice in the first table also stays "Queued" in the outbox (§3.3).

---

*End of Volume 05. The implementation status of every item flagged here is consolidated in 09 Feature Status Report.*
