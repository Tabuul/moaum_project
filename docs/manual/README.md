# MOAUM Unified University Portal — Documentation Package

**Rev. Fr. Moses Orshio Adasu University, Makurdi · Directorate of ICT**

| | |
|---|---|
| **Version** | 1.1 |
| **Date** | 26 September 2026 |
| **Basis** | An audit of the source code, the database schema (migrations `V001`–`V263` applied) and the user interface of the portal as at commit `8c2b6fa` on `main` |
| **Nature** | Documentation only. Nothing in the portal — code, schema, configuration or data — was changed to produce this package |
| **Prepared by** | Directorate of ICT (prepared with Claude Code) |

The package describes what the portal does today. Where a feature is unfinished, every volume says so in the same words (**PARTIALLY IMPLEMENTED**, **CONFIGURED BUT UNUSED**, **PLACEHOLDER**, **NOT IMPLEMENTED**) and *09 Feature Status Report* is the control document that settles any disagreement between a screen's text and the code behind it.

## Contents of this index

1. [Package contents](#1-package-contents)
   - 1.1 [The ten files](#11-the-ten-files)
   - 1.2 [Reading paths by audience](#12-reading-paths-by-audience)
2. [Master table of contents](#2-master-table-of-contents)
3. [Glossary](#3-glossary)
4. [Documentation change history](#4-documentation-change-history)
5. [Conventions used in the package](#5-conventions-used-in-the-package)
6. [Keeping the package current](#6-keeping-the-package-current)

---

## 1 Package contents

### 1.1 The ten files

All files are GitHub-flavoured Markdown in `docs/manual/`. Each volume opens with a numbered table of contents and cross-references the others by file name.

| File | Title | Audience | What it contains |
|---|---|---|---|
| `README.md` | Package index | Everyone | This index: the files, reading paths, the master table of contents mapping the University's 42 chapters to the volumes, the glossary, change history and conventions. Start here. |
| `01-user-manual.md` | User Manual | Students, applicants (UG and PG), lecturers, external examiners, general staff office holders (HOD, Dean, Examinations Officer, Faculty Officer, SIWES Coordinator, Librarian, CSO, Support Services) | Screen-by-screen guidance for every non-administrative role, with the notices each event sends, the documents that can be downloaded and verified, troubleshooting, FAQ, quick starts and role cards. Every unfinished control is marked. |
| `02-administrator-manual.md` | Administrator Manual | Super and System Administrator, Directorate of ICT, Registrar and Deputy Registrars, Academic Office, Exams and Records, Bursary, Internal Audit, HRM, Postgraduate School, College of Health Sciences, Housing, documents office, VC and DVC | The administration model (offices, grants, scope, instruments, the audit spine, maker–checker), the initial setup guide in order, daily administration by office, periodic administration (new session, admission cycle, matriculation, results calendar, graduation), the configuration guide, audit and compliance, the reports catalogue, troubleshooting and quick starts. |
| `03-technical-documentation.md` | Technical Documentation | Developers, ICT operations | Architecture and module boundaries, backend and frontend developer guides, the design system, security (with the numbered gaps S-1…S-18), configuration and environment variables, deployment and CI, integrations (gateways, mail and SMS, Keycloak, JAMB/CAPS, PayDirect, NELFUND, legacy import) and the known technical debt. |
| `04-role-permission-matrix.md` | Role and Permission Matrix | Registry, ICT, auditors, anyone deciding who may do what | How authorisation works, the office register (34 offices), the generated module × office matrix from every API guard, finer rules by module, the known mismatches between menus and guards, user creation and role assignment, precedence, and the guard constants. |
| `05-module-navigation-guide.md` | Module and Navigation Guide | All users; trainers | The complete navigation map, role-specific navigation, the module catalogue on a common template, screen-by-screen documentation, dashboards and KPIs, the reports and exports catalogue, the generated-documents catalogue and the notifications catalogue. |
| `06-workflows.md` | Business Workflows | Management, process owners, trainers, developers | End-to-end workflows with statuses, actors, data, notifications, documents and rejection paths: the student lifecycle, UG and PG admission, matriculation (V263), academic and results, finance, deferment and transfer, graduation and documents, hostel, help desk and clinic, HR and expenditure, identity; and the consolidated list of gaps. |
| `07-api-reference.md` | API Reference | Developers, integrators | Authentication, headers, the acting office, problem responses, public endpoints and webhooks; worked examples; the generated catalogue of all 919 endpoints in 47 modules with their guards; the endpoints without a screen; integration notes. |
| `08-database-reference.md` | Database Reference | Developers, DBAs, auditors | The migration model, schema-per-domain layout, the audit spine, naming and reference numbers, status columns, where the business logic lives, triggers; entity-relationship overviews by domain; the important status fields; operational notes; and the generated catalogue of 331 tables with their columns and CHECK vocabularies. |
| `09-feature-status-report.md` | Feature Status Report | Management, project board, ICT, developers | The control document: method, executive summary with counts, the top 25 gaps by user impact, the complete 490-row status matrix, the inventories of unused, unwired, placeholder and stale surfaces, the security findings with severities, and a remediation order. |

Two supporting folders travel with the package: `docs/manual/audit/` holds the seven module dossiers (A–G) the volumes were written from, each citing the code by file and line; `docs/manual/tools/` holds the inventory scripts that regenerate the mechanical references (§6).

### 1.2 Reading paths by audience

| Audience | Read in this order | Then keep to hand |
|---|---|---|
| **Management** (Vice-Chancellor, DVC, Registrar, Bursar, Provost, Council and Senate committees) | *09* §2 (executive summary and the top 25 gaps) → *06* §1 (the student lifecycle) and §13 (gaps across workflows) → *02* §1 (the administration model) → *04* §2 (the office register) | *09* §6 (remediation order); *02* §7 (reports catalogue) |
| **Registrar / Academic Office / Exams and Records** | *02* §1–§2 (model and setup) → *02* §3.1–§3.3 and §4 (daily and periodic administration) → *06* §2, §4, §5, §7, §8 → *04* §7.1–§7.2 | *02* §8 (troubleshooting); *01* §6 (what HODs and Deans see); *09* §4.3 (menu items that refuse) |
| **Bursary and Internal Audit** | *02* §2.8–§2.9 and §3.4–§3.5 → *06* §6 (finance workflow) → *02* §6 (audit trail and compliance) → *04* §7.3 | *01* §3.3–§3.4 (what students see); *09* §3.38–§3.41; *03* §10.1 (gateways) |
| **Directorate of ICT** (Director, System Administrator, Support Desk) | *02* §2 (initial setup, in order) and §3.11–§3.12 → *03* §6–§7 (configuration, deployment, CI) → *02* §2.16 and §3.11 (help desk) → *03* §5 (security) → *09* §5 | *03* §11 (technical debt); *07* §1; *08* §1.2 and §4; *04* §4 |
| **Lecturers, HODs, Deans, Examinations Officers** | *01* §2 (getting started) → *01* §5 (lecturer manual) → *01* §6 (office holders) → *06* §5.3–§5.5 (score sheets to publication) | *01* §7 (notices) and §9 (troubleshooting); *05* (navigation and screens) |
| **Students and applicants** | *01* §2 → *01* §3 (student manual) or §4 (applicant manual) → *01* §8 (documents you can download) → *01* §9–§11 | *01* §7.2 (events that send nothing — check the screen instead) |
| **Developers** | *03* §1–§3 (architecture and developer guides) → *08* §1 (migrations, spine, conventions) → *07* §1–§2 → *04* §1 and §8 → *09* §3–§4 (before touching any area) | *03* §11; `docs/manual/audit/` (the dossiers); `docs/manual/tools/` |

---

## 2 Master table of contents

The University asked for forty-two chapters. Each is documented in the volumes and sections below; no chapter has a volume of its own unless the table says so. Section numbers are those printed in each volume's table of contents; for *05* the section is named, since that volume's sections are titled by function.

| # | Chapter | Where it is documented |
|---|---|---|
| 1 | Introduction | *README* (this index); *01* §1 Introduction and about the portal; *09* §1 Method |
| 2 | About the portal | *01* §1.1–§1.3 (what it is, who uses it, one sign-in door); *03* §1.1–§1.3 (the deployables, architecture, the request path) |
| 3 | System overview | *03* §1 System overview and architecture (§1.2 diagram, §1.4 module boundaries, §1.5 technology inventory); *05* Module catalogue; *08* §1.3 schema-per-domain layout |
| 4 | Getting started | *01* §2 Getting started; *01* §11 Quick starts; *02* §9 Quick start (administrators, ICT officers) |
| 5 | Login & authentication | *01* §2.1–§2.5; *02* §2.2 (bootstrap), §2.3; *03* §5.1 Authentication, §3.7–§3.9 (proxy, sign-in handlers, cookies); *04* §1.2–§1.3 (the token, the acting office), §5.8; *06* §12.2; *07* §1.3–§1.4 |
| 6 | Dashboard | *01* §3.1 (student), §5.1 (lecturer), §6 (HOD, Dean); *02* §3 (office homes); *05* Dashboards and KPIs; *09* §3.8 |
| 7 | Navigation | *01* §2.7 How the screen is organised; *05* Complete navigation map and Role-specific navigation; *03* §3.4 Menus, routes and titles, §4.12 Sidebar and top bar |
| 8 | User roles | *04* §1 How authorisation works, §2 Role catalogue (§2.1 the office register), §6 Precedence, §7 Quick reference by office group; *02* §1.1–§1.3 |
| 9 | User management | *04* §5 User creation and role assignment (§5.1–§5.9); *02* §2.3 People, sign-ins and offices; *06* §12.1, §12.3; *09* §3.2 |
| 10 | Admissions | *01* §4.1 (UG applicant, ten stages), §4.2 (PG applicant); *02* §2.13 Admission settings and the Post-UTME examination, §3.2, §4.3 Admission cycle; *06* §2 UG admission workflow, §3.1 PG admission; *07* `admissions`, `applicant`, `pgadmissions`; *08* §2.3–§2.4; *09* §3.11–§3.14 |
| 11 | Student management | *02* §3.1–§3.3 (Registry, Academic Office, Exams and Records); *06* §1 The student lifecycle, §7 Deferment, transfer, biodata and status changes; *07* `student`, `deferments`, `transfers`; *08* §2.2 People and students; *09* §3.17, §3.21–§3.22 |
| 12 | Matriculation | *01* §3.6 The matriculation number; *02* §2.12 Matriculation number format, §4.4 Matriculation; *06* §4 Matriculation with the V263 number format; *07* `matriculation`; *09* §3.19 |
| 13 | Academic management | *02* §2.4 Sessions and semesters, §2.5 Faculties, departments and programmes, §2.6 Courses and course structures, §2.7 Grading policy; *06* §5.1; *07* `calendar`, `catalogue`, `allocation`; *09* §3.7, §3.23, §3.29 |
| 14 | Course registration | *01* §3.5 (student), §5.3 (lecturer: registered students, attendance), §6.1 (HOD approvals); *06* §5.2; *07* `registration`; *08* §2.5; *09* §3.20 |
| 15 | Results | *01* §3.9–§3.10 (student), §5.4–§5.5 (score sheets, after attestation), §6.3–§6.4 (examinations officers); *02* §3.3, §4.5 Results processing calendar; *06* §5.3–§5.5; *07* `results`; *08* §2.6; *09* §3.30–§3.35 |
| 16 | Examination | *01* §3.11 Docket and examination card, §5.4; *02* §2.13 (Post-UTME CBT scheduling); *06* §2.4–§2.5 (screening seating and check-in), §5.6 (the College's professional examinations); *07* `cbt`; *09* §3.13, §3.36 (the CBT module is a question bank only), §3.37 |
| 17 | Finance | *01* §3.3 School fees and payments, §3.4 Wallet and funding; *02* §2.8 Fee schedules, §2.9 Payment gateways, §3.4 Bursary; *06* §6 Finance workflow; *07* `finance`, `payments`, `wallet`, `expenditure`; *08* §2.7; *09* §3.38–§3.41 |
| 18 | Staff management | *01* §5.10 My Profile, Leave & Payslip; *02* §3.6 Human Resource Management; *06* §11.1–§11.3 (movements, leave, pay run); *07* `hrm`, `staff`; *08* §2.11; *09* §3.42–§3.43 |
| 19 | ICT help desk | *01* §3.19 Help & Requests and ICT Support Tickets; *02* §2.16 Help desk categories, SLA and auto-close, §3.11 ICT Directorate; *06* §10.1–§10.2; *07* `helpdesk`, `support`; *08* §2.10; *09* §3.45–§3.46 |
| 20 | Communication | *01* §2.6 Where notifications are, §7 Notifications you can expect; *02* §2.10 Mail server, SMS provider and relays, §2.11 The notice pipeline; *03* §2.10 Notifications, §10.2 Email and SMS; *05* Notifications catalogue; *09* §3.3 |
| 21 | Hostel | *01* §3.15 Hostel accommodation; *02* §2.15 Hostel inventory, window and rules, §3.9 Housing, §4.7; *06* §9 Hostel workflow; *07* `hostel`; *08* §2.9; *09* §3.44 |
| 22 | Postgraduate school | *01* §3.23 Postgraduate students, §4.2 Postgraduate applicants; *02* §3.7 School of Postgraduate Studies; *06* §3.1–§3.3; *07* `pgadmissions`; *08* §2.4; *09* §3.14–§3.15 |
| 23 | Research & projects | *06* §3.3 The research lifecycle (sixteen stages); *01* §3.23; *09* §3.15 (PG research), §3.41 (research grants register — `/research/projects`), §3.24 (course spaces); *07* `pgadmissions` (research), `expenditure` (grants) |
| 24 | External examination | *01* §5.11 External examiner manual; *06* §3.4 External examiners; *07* `examiners`; *08* §2.4 (`extexam`); *09* §3.16 |
| 25 | Graduation | *01* §3.21 Graduation and clearance; *02* §4.6 Graduation and certificates, §2.17 Clearance units and purposes; *06* §8.1 Degree audit, clearance units and Senate approval; *07* `graduation`, `clearance`, `alumni`; *09* §3.27–§3.28 |
| 26 | Certificates | *01* §3.20 My Documents; *02* §2.14 Document policies and templates, §3.10 Documents office; *06* §8.2 Certificate issue, §8.4 Revoke, reissue, flags; *07* `credentials`; *08* §2.8; *09* §3.48 |
| 27 | Transcripts | *01* §3.20; *02* §3.10; *06* §8.3 Transcript and statement requests; *07* `credentials` (document requests); *09* §3.48 (the legacy transcript queue is kept; the V027 student request is superseded) |
| 28 | Document verification | *01* §8 Documents you can download (the verification column); *06* §8.5 Public verification; *07* §1.12 Public endpoints, `verify`; *09* §3.49 Public verification surface, §5 S-1 |
| 29 | Reports | *02* §7 Reports catalogue for administrators, §4.8 Statistics and the returns due register; *05* Reports and exports catalogue; *01* §8; *07* `reports`, `stats`, `reporting`; *09* §3.9 |
| 30 | Notifications | *01* §7.1 Events that send a notice, §7.2 Events that send nothing, §3.22; *05* Notifications catalogue; *03* §2.10; *02* §2.11; *09* §2.3 items 1, 19 |
| 31 | Profile & account settings | *01* §2.3 Changing your password, §2.4 The office switcher, §3.2 Profile, password and biodata, §5.10 My Profile; *04* §5.8 |
| 32 | System administration | *02* §2 Initial setup guide, §3.11–§3.12 (ICT, Super and System Administrator), §5 Configuration guide, §2.20 Go-live readiness; *03* §6 Configuration and environment, §7 Deployment and CI/CD; *09* §3.3 |
| 33 | Security | *03* §5 Security (§5.1–§5.13 controls, §5.14 gaps); *04* §1 (guards, scope, the acting office); *02* §1.6 What the Super Administrator can and cannot do; *09* §5 Security findings summary |
| 34 | Audit trail | *02* §6 Audit trail and compliance; *03* §5.9 Audit logging; *04* §1.6 The audit spine and the acting office; *08* §1.5 The audit spine; *09* §3.4 |
| 35 | Troubleshooting | *01* §9 Troubleshooting (sign-in, registration, payment, documents, results, matriculation, hostel, tickets); *02* §8 Administrator troubleshooting (problem codes and remedies); *03* §2.11 Error handling and problem details; *07* §1.7, §5.3 |
| 36 | FAQ | *01* §10 Frequently asked questions; *01* §12 Role quick-reference cards |
| 37 | Glossary | *README* §3 (this index); the dossiers' §15 in `docs/manual/audit/` for module-specific terms |
| 38 | Technical documentation | *03* Technical Documentation (whole volume); *08* §1 Introduction; *07* §1–§2 |
| 39 | API documentation | *07* API Reference (whole volume): §1 introduction, §2 conventions and worked examples, §3 endpoint catalogue, §4 endpoints without a screen, §5 integration notes |
| 40 | Database documentation | *08* Database Reference (whole volume): §1 introduction, §2 entity-relationship overview, §3 important status fields, §4 operational notes, §5 generated catalogue |
| 41 | Feature status | *09* Feature Status Report (whole volume); *06* §13; *04* §4; *03* §11; *07* §4; *08* §4.5 |
| 42 | Appendix | *04* §8 Guard constants; *01* §12 Role quick-reference cards; *07* §5 Integration notes and §5.5 demo accounts; *08* §5 Generated catalogue; `docs/manual/audit/` (dossiers A–G); `docs/manual/tools/` (inventory scripts); `docs/demo-accounts.md` in the repository (the demo sign-in roster — the password is printed there, not in this package) |

---

## 3 Glossary

Terms as the portal uses them, in alphabetical order. Codes in backticks are the values the database or the API uses. Module-specific vocabulary beyond this list is in each dossier's §15 (`docs/manual/audit/`).

| Term | Meaning in the portal |
|---|---|
| **Academic session** | The University year, `YYYY/YYYY`, a row of `policy.academic_session`; one is CURRENT under a Senate minute and registration, fees and results run in it. The School of Postgraduate Studies keeps its own calendar (`admissions.pg_academic_session`). |
| **Acceptance fee** | The fee whose confirmation accepts an offer of admission (undergraduate `MOAUM-ACC-…`; postgraduate through `pg_confirm_fee`). |
| **Acting office** | The office a request is made in, sent as `X-Active-Office` and chosen in the sidebar's "Signed in as"; one of the offices the token carries. Every write is attributed to it. |
| **Admission** | The state of a candidate from CAPS load through offer, acceptance and intake to the student register (`admissions.candidate.offer_state`, `application_stage` 0–9). |
| **Admission number** | `MOAUM/ADM/YY/NNNNNN`, issued at intake; the student signs in with it until matriculation, when it is retired (never deleted). |
| **Allocation** | (Hostel) A bed assigned to a student for a session, reference `ALC-YYYY-NNNNN`, moving HELD → CONFIRMED → ACCEPTED → CHECKED_IN and on to clearance. (Teaching) A lecturer assigned to an offering (`catalogue.allocate_offering`). |
| **Alumni** | Graduated students on the alumni register (`/alumni`), read by the Registry, Academic Office, Records and oversight offices. |
| **Applicant** | A person with an applicant account (undergraduate, by JAMB number; postgraduate, by application) signing in through the applicant door; sign-in code `applicant`. |
| **Arrears** | The part of an earlier session's charge that its payments do not cover; a registration gate. |
| **Audit spine** | The trigger-and-chain that records every attributed change to every state table in `audit.record`, refuses a write with no actor context, and hash-chains rows in sixteen shards a month. Tables kept off it are exempted with a written reason. |
| **Auto-close** | The help-desk job that closes a RESOLVED ticket after a quiet spell of configured days; off by default. |
| **Award** | Senate's approval of a degree (`records.approve_awards`, PG `pg_award`), which makes a graduand and sets the student GRADUATED. |
| **BR-006** | The rule that no two consecutive stages of a chain (score sheet, voucher) may be acted by the same person; enforced in SQL. |
| **Broadsheet** | The computed sheet of every student's results in a programme and session, with Senate lists and remarks; exported as Excel or print; the student's own broadsheet is a PDF of their whole history. |
| **Bursary** | The Bursar's office (`bursar`): fee schedules, confirmations, bank credits, refunds, reconciliation, the general ledger, NELFUND and the wallet. |
| **CAC** | The committee whose minute puts admission settings in force (recorded as the instrument on `admissions.session_policy`). |
| **CAPS** | JAMB's Central Admissions Processing System; the downloaded list the admissions office loads, reconciles, commits or withdraws. |
| **Carry-over** | A failed core course automatically added to the next registration of that semester (`registration.carryovers_at`); electives are excluded. |
| **Certificate** | The degree certificate, issued digitally by the Registry (V262) as a versioned document with a hash, a verification code and number `CERT-YYYY-NNNNNN`; a printed certificate register with stationery serials also exists. |
| **CGPA** | Cumulative grade point average across every published semester (`assessment.student_cumulative`); the class of degree is read from `policy.class_of`. |
| **Checking fee** | The postgraduate fee (default ₦3,000) that releases the School's decision to the applicant (`DECISION_LOCKED` until paid). |
| **CHS** | The College of Health Sciences; its MB;BS programme runs on the `college` schema with its own years, postings, logbook and professional examinations. |
| **Class of degree** | First Class, Second Class Upper and so on, from the classification band in force for the CGPA. |
| **Clearance** | (Graduation) Sign-off by each clearance unit (Bursary, Library, department, hostel and others) for a purpose such as CONVOCATION or TRANSCRIPT. (Admission) The Registry's in-person check of an applicant's originals. (Hostel) The checkout inspection and certificate. |
| **Council** | The University's governing council; referenced by minutes and instruments, not modelled as a workflow. |
| **Course** | A unit of study with a code, title and credit units (`catalogue.course`), in state BOARD, LIVE or ENDED. |
| **Course form** | The approved registration as a document with a QR and check code; verifiable at `/verify/registration`. |
| **Credit unit** | The weight of a course; per-level minimum and maximum units per semester are set on `policy.level_limit`. |
| **Deferment** | A student's approved break from studies for a semester or session (`DEF-YYYY-NNNNN`), decided by three desks, put in force by the clock, and gating registration until return. |
| **Deploy floor** | The API instance's start time; any session issued before it is refused ("The portal was updated. Sign in again."). |
| **Department** | A unit of a faculty (`ref.department`) owning courses, students and a Head of Department scope. |
| **Direct Entry** | Admission by a prior qualification rather than UTME; screened on the DE desk with award capture; merit lists exclude it. |
| **Docket** | The student's examination timetable for the session, with the examination card. |
| **Entry mode** | UTME, Direct Entry or another mode on the student record; a fee-schedule filter. |
| **Escalation** | (Help desk) Recording a named person a ticket is escalated to without changing its assignment. (Results) A button that today sends nothing. |
| **Exam card** | The examination card PDF issued to a student with an approved registration who is cleared under the scheme; verifiable at `/verify/exam`. |
| **Exam session** | The container for a sitting (MAIN, RESIT, SPECIAL) with dates and the sheets due; opening it generates the score sheets. |
| **External Examiner** | An outside academic invited, activated and appointed to assess project documents against a rubric; office `extexaminer`. |
| **Faculty** | A grouping of departments (`ref.faculty`) with a Dean, a Faculty Officer and a Faculty Examinations Officer; a segment of the matriculation number. |
| **Fee group** | A classification a fee-schedule line may be restricted to (with level, entry mode, faculty, programme, semester, indigene status and spillover). |
| **Gateway** | Paystack, Flutterwave or Quickteller (card and USSD) and PayDirect (bank); each confirms a reference by a signed webhook or a verification call. |
| **GPA** | Grade point average for one semester (`assessment.student_gpa`). |
| **Graduand** | A student whose award Senate has approved and who is on the graduation list (`records.graduand`). |
| **Held script** | A script withheld from marking because the student had not registered; released when the registration is approved, lapsed at the late-registration date; the student is told. |
| **Help Desk** | The ICT Support Desk (`helpdesk`): tickets, queue, SLA, reports, public tracking. Distinct from *Help & Requests*, which are service requests to an office. |
| **Hold** | (Hostel) A bed reserved unpaid until `held_until` (72 hours); it lapses to the waiting list. (Clearance) A unit's refusal to clear. |
| **Hostel window** | The session's application settings — dates, capacity, rules version, eligibility — opened by the housing desk. |
| **ICT** | The Directorate of ICT; office `ict` (Director) and `ictagent` (support agent). |
| **Instalment** | Half or the whole of a session's charge; the first-semester gate needs the first instalment settled in full. |
| **Instrument** | The letter, minute or memo under which an office is held or a status is changed; free text recorded with the act. |
| **JAMB** | The Joint Admissions and Matriculation Board; its registration number (`upper(btrim(jamb_reg_no))`) keys every applicant match. |
| **Kept copy** | A saved snapshot of a return with a verification code, checkable at `/verify/report/{code}`. |
| **Keycloak** | The single sign-on provider the portal can federate with (with MFA); coded, not deployed. |
| **Level** | 100–600 for undergraduates, 700–900 for postgraduates; the year of study on the student record. |
| **Maker–checker** | Two officers for one act: proposer and approver on bank credits, refunds and withdrawals; second officer on document release; BR-006 on chains. |
| **Matriculation number** | The permanent number issued by the matriculation run under the V263 format `MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}`; the programme segment appears only where configured; the sequence comes from a series. |
| **Matriculation series** | A named counter (Administration, College, Pharmacy, Architecture, General) a faculty or programme draws its sequence from; only ever moves forward. |
| **MB;BS** | Bachelor of Medicine, Bachelor of Surgery — the College of Health Sciences programme. |
| **Minute** | The Senate or Board citation recorded when a session is made current, results are published, an award is approved, a document is revoked. |
| **NELFUND** | The Nigerian Education Loan Fund; its remittance batches are loaded, matched to students and credited to wallets. |
| **Notice** | A row of `platform.notice` — the outbox — sent by email or SMS by the configured provider and shown on the recipient's Notifications page. |
| **Offering** | A course offered in a session and semester (`catalogue.offering`), with its lecturers, class list, slots and score sheet. |
| **Office** | A role on the portal (`ref.office`, 34 codes) held by a person under a grant with a scope; guards on the API name offices, not people. |
| **Panel** | The per-candidate examiners of a postgraduate research project (`pg_research_panel`), distinct from the School's roster and from the external examiner workspace. |
| **PayDirect** | Interswitch's bank-branch collection channel; the portal issues a PRN instruction and imports the collections report. |
| **Pay run** | A month's payroll built from the establishment, approved and paid, with payslip snapshots and a variance view. |
| **Position** | A student's financial standing for a session: charged, paid, instalments, arrears (`finance.position`). |
| **Post-UTME** | The University's own screening of UTME candidates: a fee, a CBT seating with a slip, scores, and the screening result. |
| **Probation** | The standing pronounced for a low CGPA (`assessment.standing_of`, V246), followed by advised-to-withdraw; the probation unit ceiling is configured but unused. |
| **Programme** | A degree course of study in a department (`ref.programme`), with a curriculum track and, where configured, a matriculation code and series. |
| **Provost** | Head of the College of Health Sciences; office `provost`. |
| **RBAC** | Role-based access control — here, office-based: guards name offices; scope binds them to a department, faculty, programme, level or course. |
| **Reason** | The `X-Reason` header every write carries, stored on the audit row. |
| **Receipt** | `RCT-YYYY-NNNNN`, issued when a reference is confirmed; the PDF verifies at `/verify/receipt`. |
| **Referee** | A person a postgraduate applicant names, who receives an email link and attests. |
| **Reference (payment)** | A portal-minted payment reference (`MOAUM-FEE-…`, `-APP-`, `-ACC-` and others) valid for 24 hours, confirmed by a gateway, the bank or the Bursary. |
| **Registry** | The Registrar's offices (`registrar`, `dregistrar`, `housing`): people and offices, status changes, matriculation format, documents, admissions oversight. |
| **Relay** | An HTTP endpoint the outbox can hand email or SMS to instead of SMTP or eBulkSMS. |
| **Requisition** | A request for goods or services in the expenditure module, approved by a second person, raised to a purchase order and closed. |
| **Result query** | A student's challenge to a published mark within seven days, answered UPHELD, CORRECTED or CLOSED; the student is told. A CORRECTED answer has no correction path on the portal today. |
| **Schedule line** | One line of the session's fee schedule (`finance.fee_line`), with its filters; charges are computed from lines, never typed. |
| **Scope** | The bound of a grant — institution, faculty, department, programme, level, course, unit, college or platform — enforced by the controllers that call `OfficeScope`. |
| **Score sheet** | One offering × one sitting: CA and exam marks per candidate, versioned, moving through the nine-stage approval chain to PUBLISHED. |
| **Screening slip** | The Post-UTME candidate's examination slip with batch, day, centre, seat and a QR verifiable at `/verify/putme/{token}`. |
| **Semester** | FIRST or SECOND (a third exists in the schedule filter), with dated registration and add/drop windows on `policy.semester`. |
| **Seminar** | A stage of the postgraduate research lifecycle (proposal seminar, progress seminar) before the viva. |
| **Senate** | The University's academic authority; its minute publishes results, makes a session current and approves awards. |
| **Senate minute** | The citation itself, stored with the act (see *Minute*). |
| **Session (sign-in)** | A row of `platform.session` behind a JWT: twelve hours absolute, refused below the deploy floor; a person may list and end their own by API only. |
| **SPGS** | The School of Postgraduate Studies; offices `pgschool` (Dean) and `pgsecretary` (Secretary). |
| **SSO** | Single sign-on through Keycloak (see *Keycloak*). |
| **Statement of record** | The statement of academic record (`ASR-…`) and the semester statement of results (PDF with QR), both from the published record. |
| **Stay** | A student's occupancy of a bed from check-in to checkout (`hostel` lifecycle). |
| **Ticket** | An ICT Support Desk request (`TICK…`), SUBMITTED → OPEN → RESOLVED → CLOSED, with updates, internal notes, SLA and public tracking. |
| **Transcript** | Full, sessional or mini transcript (`TRN-`, `STR-`, `MTR-`), requested, paid, validated, generated, checked, released and delivered under a policy (V262). |
| **Transfer** | Inter-departmental transfer of a student, applied and paid for by the student and approved by four desks; the committee (SAIC) path exists in the API only. |
| **Undertaking** | The electronic acceptance declaration an admitted undergraduate signs before paying the acceptance fee. |
| **UTME** | The Unified Tertiary Matriculation Examination; its score and JAMB registration number come with the CAPS list. |
| **Verification code** | The Crockford base-32 code (5 × 5) printed on a digital document; `/verify/document/{code}` answers VALID, REVOKED, REPLACED or NOT FOUND. Receipts, forms and cards carry a SHA-256 check code instead. |
| **Viva** | The oral examination of a postgraduate research project, a stage of the research lifecycle. |
| **Voucher** | A payment voucher in the expenditure module moving through desks under BR-006 with queries. |
| **Wallet** | A student's credit balance (`WalletController`), funded by NELFUND, top-ups or the Bursary, applied to references, withdrawable under two officers. |
| **Webhook** | The gateway's signed callback that confirms a payment; bad signatures are logged and refused. |
| **Withdrawal** | (Standing) Advised to withdraw after probation. (Voluntary) Four consecutive closed semesters unregistered (V247). (Wallet) A student's request to take money out, approved and marked paid by two officers. (Application) A student withdrawing a deferment, transfer or hostel application. |

---

## 4 Documentation change history

| Version | Date | Change | By |
|---|---|---|---|
| 1.0 | 26 September 2026 | Initial complete portal documentation: ten volumes, seven audit dossiers and the inventory tools, as at commit `8c2b6fa` on `main` | Directorate of ICT (prepared with Claude Code) |
| 1.1 | 26 September 2026 | Deferment revised (V264): application fee before the form, six-desk chain Bursary → HOD → Faculty → Academic Office → DVC → SBC, forwarding batches, document viewer, academic effect (DEFERRED courses, no CGPA effect, timeline extension) — volumes 01 §3.13, 02 §3.1.5, 05 §3.25, 06 §7.1 and 09 §3.21 updated | Directorate of ICT (prepared with Claude Code) |

---

## 5 Conventions used in the package

- **Markdown**, GitHub-flavoured; every volume opens with a numbered table of contents linking to its headings; headings are numbered `1`, `1.1`, `1.1.1`.
- **Tables** carry fields, actions, statuses and permissions; **numbered steps** carry procedures; fenced `text` blocks carry navigation paths and flow diagrams with `→` and `↓`.
- **Screens** are named by their real menu labels and page titles with the URL path in backticks (`/matriculation/config`). **Offices** are named by their titles with the code in backticks on first use (Deputy Registrar (Academic Affairs) `dregistrar`).
- **Implementation status** is one of five words wherever it matters: **IMPLEMENTED**, **PARTIALLY IMPLEMENTED**, **CONFIGURED BUT UNUSED**, **PLACEHOLDER**, **NOT IMPLEMENTED** (defined in *09* §1.2). Unfinished functionality is never described as complete; the call-outs `> **Note:**`, `> **Warning:**`, `> **Tip:**` and `> **Planned / Not Yet Implemented:**` mark the exceptions in the narrative volumes.
- **Screenshots** are not fabricated. Where one belongs the volume prints `> **Screenshot Required:** <Page name> — <URL> — <what it should show>` for the Directorate to capture from the live portal.
- **Evidence** is cited as `file:line` at commit `8c2b6fa` (Java under `api/src/main/java/ng/edu/moaum/portal/`, TSX under `frontend/src/app/`, SQL as `db/Vnnn`), or as a function, trigger or generated-inventory name. Where a dossier and the code disagreed, the code won; where a claim could not be verified the text says "not verified".
- **Exports.** Branded Excel and print exports put **S/N** as the first column, generated at export time, and sort names A–Z; plain CSV exports (class lists, faculty list, examiner and help-desk reports) do not.
- **Secrets** are never printed: no passwords, tokens or keys; environment variable *names* are given. Demo accounts exist for training and their roster is `docs/demo-accounts.md` in the repository; the password is printed there and nowhere in this package.
- **Register.** Plain professional English in the Nigerian university register (matriculation number, session, semester, level, Senate, Bursary, Registry); short sentences; no marketing language.
- **Cross-references** name the volume by file name and section: "see *03 Technical Documentation*, §5".

## 6 Keeping the package current

The package has two kinds of content and each is kept current differently.

**Generated references.** The module × office matrix (*04* §3.2), the endpoint catalogue (*07* §3) and the database catalogue (*08* §5) are produced mechanically from the code and a database with every migration applied, by the scripts in `docs/manual/tools/` (`tools/README.md` gives the exact commands):

1. Dump the catalogue of a fully migrated database with `psql` into `tools/out/` (tables, columns, functions, triggers, constraints, indexes, offices).
2. `python docs/manual/tools/parse_api.py` — every HTTP endpoint with its resolved guard (`out/api.md`, `out/api.json`).
3. `python docs/manual/tools/parse_front.py` — menus per office, routes and pages, the API calls each page makes, exports and PDFs (`out/menus.md`, `out/routes.md`, `out/routes.json`).
4. `python docs/manual/tools/gen_refs.py` — the permission matrix, the API catalogue and the database catalogue (`out/generated/*.md`).

After a release, re-run the four steps, diff `out/generated/*.md` against the copies embedded in *04*, *07* and *08*, and replace the embedded sections. Python 3.11+ and `psql` are the only requirements.

**Narrative volumes.** *01*, *02*, *03*, *05*, *06* and *09* were written from the seven module dossiers in `docs/manual/audit/` (A platform and identity; B undergraduate admissions; C postgraduate and external examiners; D students and academics; E results and the College; F finance and human resources; G services and documents). Each dossier follows one template per module — purpose, users, navigation, screens, workflow and statuses, business rules, notifications, reports and documents, configuration, data, jobs and integrations, security notes, implementation status, common problems, glossary — and cites the code by file and line. The dossier method is the way to keep the narrative true:

1. When a module changes, re-audit it against the template: open the controller, the SQL functions, the pages and the menu; check the five layers of *09* §1.1 (UI, backend, permission, workflow, database).
2. Update the dossier's §13 status table and §12 security notes first, with the new `file:line` evidence.
3. Carry the change into *09* §3 (the row), §2.1 (the counts) and, if it removes a gap, §2.3 and §6.2; then into the narrative volume that describes the screen, and into *06* if a workflow stage changed.
4. Add a line to §4 of this index with the new version number and date.

A feature is described as working in any volume only after its row in *09* reads **IMPLEMENTED**.

---

*End of the package index.*
