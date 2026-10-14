# Portal gap audit: register and production readiness (13 October 2026)

An audit of the MOAUM portal as it stands on `main`, with what was fixed in the same pass. The method was to check every item by
script where a script can check it, then trace the high-risk workflows by hand through the UI, API, service, database, rule,
authorisation, audit and notification. Numbers come from the code and from a live-shaped copy of the register (54,573 students,
65,951 registrations, 367,445 marks, 314,325 payment references), never from estimates.

## 1. What was swept, and what held

| Sweep | Scope | Result |
|---|---|---|
| Authorisation on every endpoint | 1,746 endpoints in 145 controllers | Every non-public endpoint carries a rule (`@PreAuthorize`, or a self-only door such as sign-out or `/iam/me`). None is unguarded. |
| Frontend ↔ API wiring | 1,816 API references in the frontend | Every reference resolves to a backend endpoint. No button calls a missing API. |
| Menus and links | 341 menu items, every internal link | Every routed menu item opens a page. One dead item and two broken links, fixed or noted below. |
| Scheduled jobs | 18 jobs | All take a PostgreSQL advisory lock (`JobLock`), so they are safe on several instances. None depends on memory. |
| Payment webhooks | Paystack, Flutterwave, Quickteller, PayDirect | Signatures are checked; gateway notifications are re-verified before posting. No module keeps its own "paid" flag outside Finance. |
| Secrets | the repository | None committed. Every key and password is read from the environment. |
| Placeholders | TODO, FIXME, "coming soon", mock data | None in shipped code. |
| CSS zoom | `zoom:` anywhere | None. |
| Identity duplicates (live copy) | matric, admission, JAMB, payments, registrations, beds, cards | No duplicate matric or admission numbers, payment references, registrations, bed allocations or live ID cards. Duplicate JAMB numbers found (GAP-002). |
| Primary keys | every table | Every table has one. Three append-only logs use integer keys (GAP-011). |
| Hostel clearance | the clearance workflows (V415) | The hostel stage applies only to a student who applied for or held a hostel (`HOSTEL_THIS_SESSION`, `HOSTEL_EVER_ALLOCATED`). Scenario 6 holds. |
| No result (V421, V422) | standing, CGPA, carryovers, broadsheet | No result is never a zero, an F, a carryover or probation. Scenario 5 holds. |
| CBT scores | the candidate door | Shown only once the office publishes, or at submission where the exam says so; the candidate's own attempt only; Post-UTME never through the exam door. |
| Biodata gate (V423) | the student portal | Server-side interceptor; the ICT Director's switch, off by default. Scenario 7 holds. |

## 2. The gap register

Severity: CRITICAL, HIGH, MEDIUM, LOW. Status: **FIXED** (in this pass, tested), **OPEN** (recorded, not fixed here),
**CONFIRM** (needs the University's decision).

| ID | Module | Gap | Type | Severity | Impact | Fix | Status |
|---|---|---|---|---|---|---|---|
| GAP-001 | Authentication | A person's own number opened their account as the password: students' matriculation or admission number (47,916 of 48,327 accounts on the live copy), migrated applicants' JAMB number (12,647), lecturers' staff number P&lt;PNO&gt; from the teaching-staff upload (618, who can enter marks). | SECURITY_PROBLEM | CRITICAL | Anyone who knew a number could take the account, read results and records, pay, register, and as a lecturer enter marks. | V428: every door refuses the person's own number, given at the door or stored as a hash; the first password comes from the reset link to the email or phone on record, ICT Support's temporary password, or one the Registry sets. The migration desk's "default passwords" are retired; the lecturer upload gives a random password. **Changed by the University's decision of 13 Oct 2026:** until a password has been chosen (the account still must change), the own number opens it at the student, staff and applicant doors, and the change is forced at once; after that the number opens nothing, and it is never accepted as the password chosen. "First sign-in" is gone; "Forgot password" stays. | FIXED, then relaxed by decision |
| GAP-002 | Admissions → Student | Intake made a second student for a candidate already on the register under the same JAMB number (8 pairs for 2026/2027 on the live copy), because it matched only by the candidate link. 2 more pairs share every name, programme and entry session. | DATA_INTEGRITY | HIGH | Two admission numbers, two accounts, fees and registrations split between them. | V429: intake links the unlinked record instead of drawing a second number; one student per candidate; `people.duplicate_students` lists the pairs. V431: the Registry keeps one record and ends the other (Cohorts › Settings › Possible duplicate students): the ended record is withdrawn, points at the kept one, opens no sign-in, is never taken by intake, and is refused when it carries a matriculation number, registration, fee reference or mark. Nothing is deleted. | FIXED; the 10 live pairs are the Registry's to settle |
| GAP-003 | HR records | A Head of Department, Dean or Faculty Officer could open any staff member's HR record (contact, grade, step, employment) and photograph across the University. | RBAC_PROBLEM | HIGH | Personal and employment data beyond the office's need. | They now read staff of their own department or faculty: home department, a department office held there, or a course of theirs taught. University-wide offices are unchanged. | FIXED |
| GAP-004 | ID cards | Students could view a picture of their card and download a printable PDF; staff could print their own card. | DOCUMENT_PROBLEM | HIGH | A printable card outside the issuing office's control. | The student sees the status only: number, issued, valid to, lost, replaced and history. Self-printing refuses for students and staff; an office printing a colleague's card from the staff register is kept. | FIXED |
| GAP-005 | ID cards | The brief makes the Security Unit the authority for the card. Today the Library prints and Security hands over, and both may issue. | BUSINESS_RULE | MEDIUM | Responsibility is split. | Whether the Library keeps issuing rights. | CONFIRM |
| GAP-006 | Navigation | "My Profile" in the Dean of Student Affairs menu (`t/profile`) has no route, so it goes nowhere. | BROKEN_FUNCTIONALITY | LOW | Dead menu item. | `t/myprofile`, as the other staff menus. | FIXED |
| GAP-007 | Navigation | The hostel finance breadcrumb linked to `/finance`, and the college student page to `/student/registration`; neither page exists. | BROKEN_FUNCTIONALITY | LOW | 404. | Breadcrumb as text; link to `/student/register`. | FIXED |
| GAP-008 | UX | Long lists as plain dropdowns: programmes (4), departments (3), lecturers (2), in transfers, CCE progression, GST/EPS courses, ICT postings, deferments, screening and the admissions export. | UX_PROBLEM | MEDIUM | Scrolling through 100+ entries. | Swapped for the searchable control (`SearchSelect`). Short lists (faculties, halls, statuses) stay plain. | FIXED |
| GAP-009 | Reports and exports | Report exports without the University's branding or S/N: CCE classes, timetable, registrations, attendance, exams, progression, fees collected and admission list, and the fee schedule. The HOD fee download wrote the University's name into the code. | REPORTING_PROBLEM | MEDIUM | Unofficial-looking files; a name that would not follow the institution profile. | All use the branded workbook (`brandedSheet` / `brandedXlsx`): logo and name from the profile, title, date, serial, S/N first. Upload templates stay plain so they read back. | FIXED |
| GAP-010 | Notifications | The template preview filled `SESSION` with the literal `2026/2027`. | CONFIGURATION_PROBLEM | LOW | A preview naming the wrong session later. | The preview reads `policy.university_current_session()`. The status page's `admissionSettings2025_2026` probe still names a year; it is kept, as deploy checks may read that key. | FIXED |
| GAP-011 | Database | Three append-only logs (`credentials.download_log`, `lookup_miss`, `verification`) use integer auto-increment keys. | DATABASE_PROBLEM | LOW | None in practice; they are never referenced from outside. | Accepted. A later migration may move them to UUIDs. | OPEN |
| GAP-012 | Performance | 352 of 758 foreign keys have no index starting with the referencing column. | PERFORMANCE_PROBLEM | MEDIUM | Slower reads by those columns on the large tables. | Measured on the live-shaped copy, eight keys on tables over 20,000 rows and the four named candidates. V432 indexes the three that pay: removing an orphaned file object 83 ms → 7 ms (`admissions.attachment.object_id`), the calendar's students per session 31 ms → 5 ms (`people.enrolment.session`), a session's registrations 5–8 ms → 0.1 ms (`registration.course_registration.session`). The rest are read another way, are empty, or saved under a millisecond. | FIXED |
| GAP-013 | Tests | `NotificationsIT` fails on the nightly second pass over one database. | PRODUCTION_READINESS | MEDIUM | The nightly suite is red. | Reported to the session that owns it, which made the test safe to re-run (3240d812). | FIXED |
| GAP-014 | Dead code | `POST /api/v1/results/legacy/default-passwords` only refused (GAP-001) and no screen called it. | DEAD_CODE | LOW | None. | Removed, with its service and repository methods; the database function still refuses. | FIXED |
| GAP-015 | Authentication | Two live records under one JAMB number made the student sign-in lookup throw (it expected one row): a 500 at the door for those students. | BROKEN_FUNCTIONALITY | HIGH | The 8 same-JAMB pairs could not sign in with their JAMB number. | The lookup skips ended duplicates (V431) and refuses two live records by name (`STUDENT_NUMBER_SHARED`: sign in with the admission number); the reset link's lookup also skips ended duplicates. | FIXED |
| GAP-016 | RBAC ↔ menus | Signed in as each office, every page of its menu was opened (960 pages, 41 menus) and every API read checked: 44 pages make a read the office is refused. Missing from rules that plainly serve the menu: the Deputy Director of Audit on the finance, records and analytics reads the Audit office has; ICT on the faculty, department and programme lists it uploads; the MBBS coordinator on the College's supervisors and their own postings. Menu items for pages the office can never use: College examinations, postings and logbooks for the College Finance Controller; the ICT agents' desk for the JUPEB office (it would show every ICT ticket); the alumni register for Services. | RBAC_PROBLEM | MEDIUM | A menu item opening an empty page; an office without a read its work needs. | Those offices added to those reads; those items removed (JUPEB's becomes Support Escalations, the office-escalation desk). Every page still loads; no read failed with a server error. | FIXED |
| GAP-017 | RBAC ↔ menus | Pages that menus offer and the finance or expenditure rules refuse: stores (Library, Services), tenders (Services), requisitions (Dean, HOD, Services), budget (Dean), fee setup (College Finance Controller, PG Secretary), graduation (PG School, PG Secretary), the audit trail (Dean of Student Affairs; the manual binds it too). | BUSINESS_RULE | MEDIUM | The page opens empty for those offices. | Whether each office reads that module, or the item leaves its menu. Unchanged here: finance is the Bursary's to grant. | CONFIRM |
| GAP-018 | RBAC ↔ menus | Optional panels refused on otherwise usable pages: voluntary withdrawals on Students (HOD, Dean, Faculty Officer, Admin), the due returns, snapshots, trends and enrolment panels on Reports, payroll on Staff, grants on Research projects. | UX_PROBLEM | LOW | A 403 in the log; the panel is empty. | Accepted; the page works. | OPEN |
| GAP-019 | Accessibility | axe-core (WCAG 2 A and AA) on 29 of the most used pages: donut charts whose slices are buttons drawn as a picture (every staff dashboard); links told from text by colour only (student home, fees, hostel, dashboards, verification); the hostel session list with no name; the University's name in amber at 3.6:1 on the public pages; a table that scrolls sideways out of the keyboard's reach. | ACCESSIBILITY | MEDIUM | Screen-reader and keyboard users, low vision. | The chart is a group of buttons; plain and `.lnk` links in running text, cards and notices are underlined; the list is labelled; the darker amber (6:1); every table wrapper can be reached and scrolled from the keyboard. | FIXED |
| GAP-020 | Mobile | Every page in every office's menu (288 pages, each opened as an office that has it) at 360 and 390 px: two pages scrolled sideways — the staff register and course allocation, where a tab strip in a panel's header would not shrink. | UX_PROBLEM | LOW | A page wider than the phone. | A panel header's right-hand slot shrinks to the card on a phone and the tab strip in it scrolls inside itself. Now none of the 288 scrolls sideways. | FIXED |
| GAP-021 | Documents | The deferment approval letter was verified by its reference alone; the references run in sequence (DEF-2026-00001…), so anyone could read every student's deferment. | SECURITY_PROBLEM | HIGH | Name, number, programme and deferment of every student who deferred. | V435: a random check code per deferment, carried by the letter's QR; the page answers only with it and says nothing otherwise. Letters printed before are printed again. | FIXED |
| GAP-022 | Documents | The student identity card's QR carried only `MOAUM ID <serial>`: nothing to scan against, so a made-up card could not be told from a real one. | DOCUMENT_PROBLEM | HIGH | Cards checked by eye. | A check address signed over the card number (`/verify/idcard?no=…&c=…`): the guard sees the holder's name, number, programme and photograph for the card in force, and "lost", "replaced" or "expired" otherwise. The card desk now prints the card itself (Print on each live card), its QR carrying the address, from the card register and the photograph alone. | FIXED |
| GAP-023 | Documents | Staff identity cards carried `MOAUM ID STF-…`, a serial made up at print time, with no register behind it. | DOCUMENT_PROBLEM | MEDIUM | A staff card could not be checked or reported lost. | V439: a staff card register like the students' — a card number of its own (MOAUM/SID/YY/NNNNN), issued on the staff number by the card desk to a member of staff in office, one live card at a time, valid to 31 December three years on, ended when replaced or reported lost. The print is the card in the register and its QR carries `/verify/staffcard?no=…&c=…`, signed over the card number: the name, staff number, department and photograph for the card in force; "lost", "replaced", "expired" or "left" otherwise. | FIXED |
| GAP-024 | Documents | Transcripts, certificates and admission letters verify by their 25-character random code, and also by their document number, which runs in sequence; by number the page shows the fields the University's document policy makes public. | BUSINESS_RULE | LOW | The public fields of every document can be listed by stepping numbers (one connection is throttled). | Whether the number alone should verify. Receipts, examination cards, registration forms, results statements, PG offers and CBT slips use signed codes (V360); hostel and clearance papers random codes (V359, V415); JUPEB papers random codes (V343). | CONFIRM |
| GAP-025 | RBAC ↔ actions | The changes, office by office: every write each office's menu pages make (3,070 calls on the pages' code) checked against the API's rule. 265 are behind the page's own office check; of 40 that looked shown and refused, 39 are hidden by a permission the page works out (Academic Office only, the stage's own office, the Librarian, the central GST/EPS offices) or sit in a shared read-only piece; one was real: the migration desk's "Clear the migrated students" showed to every office that may use the desk (Records, Examinations, HODs, Deans), and only the Academic Office, the Registry and ICT may clear. Every write open to anyone signed in was read: the public doors (sign-in, apply, reset, payment webhooks — signature-checked), the CBT invigilators' acts (only an invigilator of the sitting or the office running the examination), the document issue log and the staff photograph (both the caller's own). | RBAC_PROBLEM | LOW | A button refused when pressed. | The desk shows the clear only to the offices that may clear; the others read the counts and who clears them. | FIXED |
| GAP-026 | Mobile, accessibility | The pages reached from inside the menu pages (a student's record, a result sheet, a hostel allocation, an application, an examiner, a course, the statistics, the CBT reports — 28 kinds, one of each, as the office that reached it): all fit at 360 and 390 px; the result sheet's marks and outcome had no names. | ACCESSIBILITY | LOW | A screen reader announced the mark boxes without the student. | Each is named by what it holds and the student's number ("CA — MOAUM/…"). | FIXED |

## 3. Items that need the University's confirmation

- **GAP-005**: whether the Library keeps the right to issue ID cards, or the Security Unit alone prints and issues them.
- **GAP-002**: which record of each duplicate pair to keep. The list shows what each record carries; the one a candidate stands
  behind is normally the one to keep, and the Registry now settles each pair from the list.
- **GAP-017**: for each of stores, tenders, requisitions, budget, fee setup, graduation and the audit trail, whether the offices whose
  menus show it read it, or the item leaves their menus.
- **GAP-022**: the Library (or the Security Unit, per GAP-005) encodes each card's check address in the card's QR when it prints.
- **GAP-024**: whether a transcript, certificate or admission letter may be verified by its number alone.
- **GAP-001, staff without contacts**: 30 lecturers on the live copy have neither email nor phone, so the reset link cannot reach
  them. The Registry or ICT gives each a first password on Users & roles.

## 4. Production readiness

The scores below are counts from the sweeps, not impressions. Areas this pass did not measure are marked as such rather than
guessed.

| Area | Basis | Score |
|---|---|---|
| Authorisation (RBAC) | 1,746 of 1,746 non-public endpoints carry a rule; 1 confirmed scope gap (GAP-003), fixed | 100% after fixes |
| Authentication | 3 doors that accepted the person's own number (GAP-001), fixed | after fixes, no known gap |
| Integration (frontend ↔ API) | 1,816 of 1,816 references resolve | 100% |
| Navigation | 341 of 341 menu items routed; 2 broken links fixed | 100% |
| Role-by-role (menus ↔ API) | 960 menu pages opened as their office: all load; 44 made a refused read: 16 fixed (GAP-016), the rest for confirmation (GAP-017) or harmless panels (GAP-018) | every page loads; 916 of 960 with no refused read before the fixes |
| Background jobs | 18 of 18 locked for multiple instances | 100% |
| Data integrity (identities) | 0 duplicate matric, admission, payment, registration, bed or card; 10 student pairs, each now settled from the duplicates list (GAP-002) | prevention and settlement in place |
| Reporting (exports) | 108 branded report exports before this pass; 11 unbranded report exports converted | all report exports branded |
| Performance | the 12 unindexed foreign keys on large tables or named as candidates measured; 3 indexed (GAP-012) | measured keys settled |
| Mobile | every menu page (288) at 360 and 390 px, as their users; 2 fixed (GAP-020) | 288 of 288 fit |
| Accessibility | axe-core WCAG 2 A/AA on the same 29 pages: 5 kinds of violation, fixed in shared components and the 23 hand-drawn table wrappers (GAP-019); then on all 288 menu pages: 16 more pages with controls unnamed (a control in a table cell is now named by its column and row, in DTable; the biodata labels name their fields; the filters name themselves), 4 with faint text, 1 with a scrolling grid out of the keyboard's reach — fixed; the re-run finds none | 288 of 288 with no violation |
| Document verification | every printed paper with a QR traced to its check: all checked by a signed or random code, after the three fixed here (GAP-021, GAP-022, GAP-023) | all |

## 5. Fixes completed in this pass

- V428: a person's own number is never their password, at the student, applicant and staff doors and in the reset link.
- V429: intake links an existing record instead of duplicating it; one student per candidate; the duplicates list for the Registry.
- HR records kept to the reader's own department or faculty.
- ID cards: status only for students; no self-printing.
- Broken links, searchable long lists, branded report exports.

How they were tested: a brand-new database in the CI order and one in the production order (main through V430 and V427 first, then V428 and V429),
each holding all 268 properties of `db/check.sql`; the demo data loaded twice; 18 integration test classes (39 tests, among them
the new `FirstSignInIT` and `PortalAuditIT`) passing twice on one database; the API unit tests and the 98 frontend tests; the
frontend type-checked and linted. In a browser against a local copy: the sign-in page refuses a student's own matriculation number
and points to the link, the student's ID card page shows its status with no printable card, the self-print routes refuse, the
Registry's duplicates panel lists a pair, and a searchable programme list filters and picks.

### The follow-up pass

- V431: the Registry settles a duplicate pair; the student door no longer breaks on a shared JAMB number.
- V432: the three foreign-key indexes that measured worth it.
- V435: the deferment letter verified by its check code; the student identity card by a code signed over its number.
- V439: the staff identity card register; the staff card's QR a signed check address.
- Role-by-role: missing offices added to reads their menus serve; items for pages an office can never use removed.
- Accessibility: five fixes in shared components. The DSA's "My Profile", the preview's session, the dead endpoint.

Tested on brand-new databases in both orders (275 properties, with main through V437), the demo data twice, the API unit tests, 25 integration test
classes twice on one database (among them `PortalAuditIT`, now covering the duplicate settlement, the shared-number door, the
deferment and identity card checks), the 98 frontend tests, type-check and lint; the phone and axe pass re-run on the final build; in a browser: the deferment and card checks with
no code, a wrong code and the right code, the card desk's address, and a duplicate pair settled from the Cohorts screen.

## 6. Not covered in this pass

The brief covers more than one pass can trace end to end. These were not audited here:

- Write actions pressed end to end (the writes were checked against the rules from the pages' code; they were not sent).
- Dialogs opened from a page (they were not opened by the sweep).
- Query timings beyond the keys measured.
- Notification delivery and retry, which the notification engine (V425, V426, V436) covers.
- The JUPEB, CCE, PG and sandwich lifecycles end to end.

Earlier passes covered parts of these: V421–V424 for results, V366–V370 for GST/EPS, V415–V416 for clearance, V423 for biodata.
