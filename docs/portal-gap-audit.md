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
| GAP-001 | Authentication | A person's own number opened their account as the password: students' matriculation or admission number (47,916 of 48,327 accounts on the live copy), migrated applicants' JAMB number (12,647), lecturers' staff number P&lt;PNO&gt; from the teaching-staff upload (618, who can enter marks). | SECURITY_PROBLEM | CRITICAL | Anyone who knew a number could take the account, read results and records, pay, register, and as a lecturer enter marks. | V428: every door refuses the person's own number, given at the door or stored as a hash; the first password comes from the reset link to the email or phone on record, ICT Support's temporary password, or one the Registry sets. The migration desk's "default passwords" are retired; the lecturer upload gives a random password. | FIXED |
| GAP-002 | Admissions → Student | Intake made a second student for a candidate already on the register under the same JAMB number (8 pairs for 2026/2027 on the live copy), because it matched only by the candidate link. 2 more pairs share every name, programme and entry session. | DATA_INTEGRITY | HIGH | Two admission numbers, two accounts, fees and registrations split between them. | V429: intake links the unlinked record instead of drawing a second number, and refuses if that record has a history on another programme; one student per candidate (unique index, made only where the data allows); `people.duplicate_students` lists the pairs for the Registry (Cohorts › Settings). Nothing is merged or deleted automatically. | FIXED; the existing 10 pairs await the Registry |
| GAP-003 | HR records | A Head of Department, Dean or Faculty Officer could open any staff member's HR record (contact, grade, step, employment) and photograph across the University. | RBAC_PROBLEM | HIGH | Personal and employment data beyond the office's need. | They now read staff of their own department or faculty: home department, a department office held there, or a course of theirs taught. University-wide offices are unchanged. | FIXED |
| GAP-004 | ID cards | Students could view a picture of their card and download a printable PDF; staff could print their own card. | DOCUMENT_PROBLEM | HIGH | A printable card outside the issuing office's control. | The student sees the status only: number, issued, valid to, lost, replaced and history. Self-printing refuses for students and staff; an office printing a colleague's card from the staff register is kept. | FIXED |
| GAP-005 | ID cards | The brief makes the Security Unit the authority for the card. Today the Library prints and Security hands over, and both may issue. | BUSINESS_RULE | MEDIUM | Responsibility is split. | Whether the Library keeps issuing rights. | CONFIRM |
| GAP-006 | Navigation | "My Profile" in the Dean of Student Affairs menu (`t/profile`) has no route, so it goes nowhere. | BROKEN_FUNCTIONALITY | LOW | Dead menu item. | Use `t/myprofile`, as the other staff menus do. Deferred while another session edits `menus.ts`. | OPEN |
| GAP-007 | Navigation | The hostel finance breadcrumb linked to `/finance`, and the college student page to `/student/registration`; neither page exists. | BROKEN_FUNCTIONALITY | LOW | 404. | Breadcrumb as text; link to `/student/register`. | FIXED |
| GAP-008 | UX | Long lists as plain dropdowns: programmes (4), departments (3), lecturers (2), in transfers, CCE progression, GST/EPS courses, ICT postings, deferments, screening and the admissions export. | UX_PROBLEM | MEDIUM | Scrolling through 100+ entries. | Swapped for the searchable control (`SearchSelect`). Short lists (faculties, halls, statuses) stay plain. | FIXED |
| GAP-009 | Reports and exports | Report exports without the University's branding or S/N: CCE classes, timetable, registrations, attendance, exams, progression, fees collected and admission list, and the fee schedule. The HOD fee download wrote the University's name into the code. | REPORTING_PROBLEM | MEDIUM | Unofficial-looking files; a name that would not follow the institution profile. | All use the branded workbook (`brandedSheet` / `brandedXlsx`): logo and name from the profile, title, date, serial, S/N first. Upload templates stay plain so they read back. | FIXED |
| GAP-010 | Notifications | The template preview fills `SESSION` with the literal `2026/2027` (`NoticeTemplatesController.java:138`). | CONFIGURATION_PROBLEM | LOW | A preview naming the wrong session later. | Read the current session (`policy.university_current_session()`). Owned by the session building the notification engine. The status page's `admissionSettings2025_2026` probe also names a year; it is kept, as deploy checks may read that key. | OPEN |
| GAP-011 | Database | Three append-only logs (`credentials.download_log`, `lookup_miss`, `verification`) use integer auto-increment keys. | DATABASE_PROBLEM | LOW | None in practice; they are never referenced from outside. | Accepted. A later migration may move them to UUIDs. | OPEN |
| GAP-012 | Performance | 352 of 758 foreign keys have no index starting with the referencing column. Most are on small reference tables or audit columns. | PERFORMANCE_PROBLEM | MEDIUM | Slower joins and cascades on the large tables. | Index only after measuring on the live copy. Candidates: `catalogue.offering.lecturer_id`, `assessment.result_query.sheet_id`, `people.status_change.student_id`, `credentials.certificate.student_id`. | OPEN |
| GAP-013 | Tests | `NotificationsIT` fails on the nightly second pass over one database. | PRODUCTION_READINESS | MEDIUM | The nightly suite is red. | Reported to the session that owns it, which made the test safe to re-run (3240d812). | FIXED |
| GAP-014 | Dead code | `POST /api/v1/results/legacy/default-passwords` now only refuses (GAP-001) and no screen calls it. | DEAD_CODE | LOW | None. | Remove with the migration desk's next change. | OPEN |

## 3. Items that need the University's confirmation

- **GAP-005**: whether the Library keeps the right to issue ID cards, or the Security Unit alone prints and issues them.
- **GAP-002**: which record of each duplicate pair to keep. The list shows what each record carries; the one a candidate stands
  behind is normally the one to keep.
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
| Navigation | 340 of 341 menu items routed (GAP-006); 2 broken links fixed | 99.7% |
| Background jobs | 18 of 18 locked for multiple instances | 100% |
| Data integrity (identities) | 0 duplicate matric, admission, payment, registration, bed or card; 10 student pairs to reconcile (GAP-002) | prevention fixed; reconciliation open |
| Reporting (exports) | 108 branded report exports before this pass; 11 unbranded report exports converted | all report exports branded |
| Performance | 352 foreign keys without an index, not yet measured | not scored |
| Mobile, accessibility | not swept in this pass | not scored |

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

## 6. Not covered in this pass

The brief covers more than one pass can trace end to end. These were not audited here:

- The full role-by-role matrix for every office.
- Mobile layouts at each width.
- Accessibility.
- Query timings beyond the functions touched.
- Notification delivery and retry, which the notification engine (V425, V426) is building now.
- Document QR verification.
- The JUPEB, CCE, PG and sandwich lifecycles end to end.

Earlier passes covered parts of these: V421–V424 for results, V366–V370 for GST/EPS, V415–V416 for clearance, V423 for biodata.
