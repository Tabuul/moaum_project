# Student record support from the ICT Support Desk (V334, V346)

The report for the brief *CPO student record management, course registration support and controlled edit access*.
A Computer Programme Officer (an ICT Support Agent) resolves a student's problem from the record itself, within the
scope of their postings and within the capabilities the Head of the Support Desk granted them, through the services
the student and the offices already use. Nothing was rebuilt and nothing was duplicated.

## 1. What was found on inspection

| Need | What exists | Reused |
|---|---|---|
| The CPO role | `ictagent` office (V251); postings on queues within a scope — the University, a faculty, a college, a department, an office (`helpdesk.agent_assignment`, V328); `helpdesk.scope_covers` | The posting now carries capabilities; the same scope rule decides which students an agent reaches |
| Student profile | `StudentService.record` — the register row, biodata fields with their tier (open, approval, locked), documents, status history, enrolments, registrations, clearances, pending and decided changes; `StudentPortalService.me` — fees, standing, registration, cohort | Both are read as they are |
| Biodata editing | `ref.biodata_field` tiers; the student's own express write (`writeBiodata`); the Registry's change queue (`people.biodata_change`, Biodata Changes screen) | Open fields written through the same service; identity fields raised as a Registry request |
| Contact | `people.student_contact` and `people.student_reach` | Kept in step when a contact field changes |
| Photograph | one resolver (`passportImage`) over the admission document and the JAMB attachment | A replacement is kept in `people.student_photo` and read first by that resolver |
| Course registration | `registration.student_draft`, `student_choose`, `student_add`, `student_drop`, `student_submit`, `registration_gate`, `gst_gate`, `student_menu`; the student portal's `registrationView`, `choose`, `addCourse`, `dropCourse`, `submit` | The support desk calls the portal service; the engine's rules are the engine's |
| Payments | `finance.position`, `finance.payment_reference` | Read only |
| Documents | `people.document`, `credentials.issued`, receipts on `finance.payment_reference` | Read only |
| Tickets | `helpdesk.ticket` with the requester; `helpdesk.ticket_event` timeline | The student's tickets listed; a support act files an event on the ticket it was done for |
| Audit | the audit spine on every table; `audit.entries` by subject | The profile shows the student's entries; the desk's ledger sits beside them |
| Notifications | `platform.notice` through `NoticeRepository` | The student is told of every change |

Missing: a capability model on the posting; a scope test for students; a search within scope; a support-mode screen; a
ledger linking act, ticket and reason; a replacement photograph.

## 2. What V334 adds

- `helpdesk.agent_assignment.capabilities` — a text array checked against the desk's vocabulary: VIEW_STUDENT,
  EDIT_CONTACT, EDIT_PERSONAL, EDIT_FAMILY, EDIT_PHOTO, REQUEST_CHANGE, VIEW_PAYMENTS, VIEW_DOCUMENTS,
  MANAGE_REGISTRATION, EXPORT_STUDENTS. Empty by default. A person's capabilities are the union of their live postings'
  (`helpdesk.agent_capabilities`). The Head of the Support Desk, the Director of ICT, Admin and Super hold them all.
- `helpdesk.agent_may_see_student(person, student)` — a live posting whose scope covers the student's faculty and
  department; an office-scoped posting reaches no student. `helpdesk.agent_student_scope` gives the list filter and
  the scope in words.
- `helpdesk.support_action` — the ledger: student, agent, office, ticket, act, field, old value, new value, reason,
  session, semester, time. `helpdesk.record_support_action` refuses an act without a reason and files a
  `SUPPORT_…` event on the ticket named.
- `people.student_photo` — the replacement photograph, in the object store where one is on, else in the row.
- Indexes for the search on surname, JAMB number, admission number, contact phone and email.

## 3. The API (`/api/v1/helpdesk/support`)

| Call | Capability | What it does |
|---|---|---|
| `GET /students?q&fac&dept&prog&level&status&session&page&size&export` | VIEW_STUDENT (EXPORT_STUDENTS for `export`) | Server-side search within the agent's reach by name, matriculation, JAMB or admission number, phone or email; paged; options for the filters |
| `GET /students/{id}?ticket` | VIEW_STUDENT | The record, the portal view (payments stripped without VIEW_PAYMENTS), contact, position, capabilities, the ticket opened from, the ledger, the tickets, the audit entries |
| `GET /students/{id}/passport` | VIEW_STUDENT | The photograph through the one resolver |
| `PUT /students/{id}/biodata/{field}` {value, reason, ticket} | EDIT_CONTACT / EDIT_PERSONAL / EDIT_FAMILY by section; REQUEST_CHANGE for nationality, country or state of origin and LGA | Open fields written through `StudentService.writeBiodata`; contact mirrored; identity fields raised as a `people.biodata_change` for the Registry; locked fields refused |
| `PUT /students/{id}/passport` {dataUrl, reason, ticket} | EDIT_PHOTO | JPEG or PNG up to 2 MB, stored and read first |
| `GET /students/{id}/registration?session&semester` | VIEW_STUDENT | The engine's own view: menu, registration, window, fees, limits; the history; whether the posting may manage |
| `POST /students/{id}/registration/choose|add|drop|submit` {session, semester, offering(s), reason, ticket} | MANAGE_REGISTRATION | Through `StudentPortalService` to the engine; a closed window, unpaid fees, a unit limit, a recorded mark, a locked registration are refused by the engine exactly as for the student |
| `GET /students/{id}/payments` | VIEW_PAYMENTS | The position and the references; read only |
| `GET /students/{id}/documents` | VIEW_DOCUMENTS | Admission documents, issued documents, receipts |
| `GET /students/{id}/tickets` | VIEW_STUDENT | The student's tickets |

Every call is guarded by the agent offices, then by reach (a student outside it is not found), then by the capability;
every write takes a reason, carries the ticket, lands on the audit spine and the ledger, and tells the student.
`/api/v1/helpdesk/admin/agents` takes and edits `capabilities` on a posting; an unknown capability is refused by the
server and by the database.

## 4. The screens

- **Student Support** (`/helpdesk/students`): the search within reach with searchable faculty, department and programme,
  level, status and entry session; S/N, name, matriculation, JAMB, faculty, department, programme, level, session, status,
  registration state, Open; Excel and PDF where the posting carries exports.
- **The student in support mode** (`/helpdesk/students/{id}?ticket=`): the banner (agent, student, ticket, reason for
  access, since when, scope); tabs Profile (photograph with Replace, academic, reach, every biodata section with Edit or
  Request a change where the posting allows, pending Registry requests, what the desk does not change), Course
  registration (status, window, fees, units; registered courses with Drop; the engine's eligible courses with Add;
  Submit; history; a reason field; read-only without the capability; the closed-window notice), Payments, Documents,
  History (the ledger, status history and Registry decisions, the audit trail), Tickets (Open, Work from it).
- **Ticket screen**: "Open the Student in Support Mode" and "Course Registration" carry the ticket into the profile.
- **Support Desk**: a Student Support link; **Agents, Queues and Routing**: the capabilities ticked on the posting.
- Menus: Student Support for the agent, the Head and the Director.

## 5. What stays with the offices

Name, date of birth, gender, JAMB and matriculation numbers, admission session, programme, department, faculty and
status are not editable from the desk: they are not biodata fields, or they are locked, or they route to the Registry
as a request. Results, grades, transcripts and every payment, invoice, refund or balance are not reachable from the
support endpoints at all; the desk reads the position and escalates the ticket to the Bursary or the Examinations
Office through the existing office escalation. A submitted registration is returned only by the department's level
adviser; the desk does not reopen it. No "log in as the student" exists or was added.

## 6. Tests

- `db/check.sql` property 182: an unknown capability refused; an office-scoped posting reaches no student; a faculty
  posting reaches its own student and not another faculty's; capabilities are the union of live postings (an ended one
  counts for nothing); the scope in words; a support act without a reason refused and with it on the ledger; the
  replacement photograph kept. Suite: 182 properties green on a brand-new database.
- `SupportStudentsIT`: the search within reach and not beyond; export refused without the capability; the profile
  within reach and not found beyond it; payments hidden without the capability; a student token refused; the Head
  reaches every student; a contact edit with a reason on the record, the contact and the ledger; a malformed number and
  a blank reason refused; state of origin raised to the Registry and not written; a locked field refused; a family field
  refused without the capability; the registration read but not managed until granted; once granted, the engine's own
  refusal and nothing on the ledger; an unknown capability refused on the posting.

## 7. After deployment

The Head of the Support Desk opens Agents, Queues and Routing and ticks, on each posting, what that agent may do.
Until then every agent works tickets as before and sees no student record from the desk.

---

# Part II — Course registration corrections, password reset and payment resolution (V346)

The report for the brief *ICT Support: student account, course registration, password reset and payment issue
resolution*. ICT Support resolves a student's portal problem from the record, through the engines the University
already runs; it does not become the Registry, the Examinations Office or the Bursary.

## 8. What was found on inspection

| Need | What existed | What V346 did |
|---|---|---|
| Student search by name, matric, JAMB, admission number, phone, email | V334 search | Added the application number (through the candidate) and the student ID; the scope is now that of the postings carrying VIEW_STUDENT, read once per query |
| Course add/drop | V334 called the student portal's add/drop — the engine refused, but the desk could not show *which* rule, and had no recorded exception | `registration.support_add_checks` / `support_drop_checks` judge every engine rule by the engine's own functions; `support_add` / `support_drop` / `support_submit` act through `student_draft`, `student_choose`, `student_add`, `student_drop`, `student_submit` |
| A recorded exception | none | The **support override**: only the registration window and the engine's menu may be set aside, only by a posting carrying OVERRIDE_REGISTRATION, only on the student's own ticket with a description and a reason; the entry is marked (`registration.entry.support_override_*`) so the student's own form keeps it |
| Password reset | `iam.password_reset` (one-hour, single-use link) and the ticket screen's reset by identifier; the Registry's first password | `PasswordResetService.forStudent` (the same link, for the student named by the record); a temporary password issued by `StudentAuthService.issueTemporary` — random, hashed, 24 hours, one sign-in, forced change; the matriculation-number first password never opens an account while one stands |
| Payment verification | `PaymentsService.verify` (the reconciler's gateway requery); `finance.confirm_payment`; live entitlement (`finance.position`, `clears`, `semester_cleared`, `gst_entitlement`); `people.refresh_academic_position` | Payment Support search and diagnosis read these; Verify calls `PaymentsService.verify`; `finance.refresh_entitlement` re-applies a **confirmed** payment's effects (hostel, library, transcript) and recomputes the academic position — never a payment, never a credit |
| Ticket linking | `helpdesk.record_support_action` filed `SUPPORT_…` events — **but the timeline's check constraint refused them**, so every act done from a ticket failed | The constraint now takes `SUPPORT_[A-Z_]+`; the event says "Action taken: …", and for an override "NORMAL RULE: Registration blocked because … / SUPPORT ACTION: Override approved because …" |
| Capabilities | the union of all live postings, whatever their scope | `helpdesk.agent_capabilities_for(person, student)`: only postings whose scope covers the student count — a capability on a faculty posting no longer reaches another faculty through a wider posting |

## 9. The capability vocabulary

V334's ten stay as they are (no rename, so no live posting changes meaning). V346 adds eight. The brief's suggested names
map onto them:

| Brief | Capability |
|---|---|
| VIEW_STUDENT_DETAILS, VIEW_COURSE_REGISTRATION | VIEW_STUDENT |
| EDIT_STUDENT_CONTACT / EDIT_STUDENT_BIODATA / EDIT_STUDENT_PHOTO | EDIT_CONTACT / EDIT_PERSONAL, EDIT_FAMILY, REQUEST_CHANGE / EDIT_PHOTO |
| MANAGE_COURSE_REGISTRATION, ADD_STUDENT_COURSE, DROP_STUDENT_COURSE | MANAGE_REGISTRATION |
| OVERRIDE_COURSE_REGISTRATION | OVERRIDE_REGISTRATION (new) |
| RESET_STUDENT_PASSWORD | RESET_PASSWORD (new) |
| VIEW_PAYMENT_SUPPORT / INVESTIGATE_PAYMENT | VIEW_PAYMENTS / INVESTIGATE_PAYMENT (new) |
| VERIFY_PAYMENT_SUPPORT / SYNC_PAYMENT_ENTITLEMENT / REGENERATE_PAYMENT_RECEIPT | VERIFY_PAYMENT / SYNC_ENTITLEMENT / REGENERATE_RECEIPT (new) |
| VIEW_STUDENT_DOCUMENTS | VIEW_DOCUMENTS |
| CREATE_SUPPORT_TICKET | CREATE_TICKET (new) |
| UPDATE_SUPPORT_TICKET, ESCALATE_SUPPORT_TICKET | the desk's existing ticket rights on a ticket the agent's postings reach (`helpdesk.can_view`) |
| VIEW_SUPPORT_AUDIT, EXPORT_SUPPORT_REPORTS | VIEW_SUPPORT_AUDIT (new), EXPORT_STUDENTS |

EDIT_RESULTS, DELETE_RESULTS, APPROVE_REFUND, CHANGE_FEES, CHANGE_PAYMENT_AMOUNT, ISSUE_MATRICULATION and
CHANGE_ADMISSION_DECISION are not in the vocabulary: the API and the database (`ck_hd_aa_capabilities`) refuse them on
a posting. The Head of the Support Desk, the Director of ICT, Admin and Super hold the desk's capabilities and only
those. Queue specialisation stays the posting: a posting on COURSE_REGISTRATION_SUPPORT carries the registration
capabilities, one on BURSARY_SUPPORT the payment ones — the Head ticks them per posting.

## 10. The registration rules, and what an override may set aside

`support_add_checks` returns sixteen rules, each with *passed*, *overridable* and *advisory*:

| Rule | Override may set aside? |
|---|---|
| Student is active (admitted, active, probation) | never |
| The session exists; the semester is not CLOSED or ARCHIVED | never |
| The course offering exists; it is offered in this registration's session and semester; the course has not ended | never |
| The registration is not LOCKED; the course is not already on it | never |
| **Offered to the student's programme and level (the engine's menu)** | **yes** — a course missing or mapped wrongly |
| Maximum credit load (`policy.level_limit`) | never — an overload is the Head of Department's |
| **Registration window and late registration (`registration_gate`)**; **add and drop (`add_drop_open`)** | **yes** — a portal fault, an interrupted registration |
| Payment requirement (`finance.clears` … `REGISTRATION` for a submitted registration; advisory on a draft, as the engine does) | never — the payment is verified or its entitlement refreshed instead |
| GST/EPS (`gst_gate`) | never |
| Prerequisites | advisory — recorded on the course; the engine shows them and does not refuse on them |
| Core or elective | advisory |

Dropping: a lock, a closed semester, a carry-over, a deferred course and **a recorded mark** refuse it; the window and
the add/drop period are the only rules an override sets aside. A drop marks the entry DROPPED — never deleted — and a
dropped course can be restored. Earlier sessions are reached only through the CLOSED-semester rule, which refuses.

## 11. The API added (`/api/v1/helpdesk/support`)

| Call | Capability | |
|---|---|---|
| `GET /students/{id}/registration` | VIEW_STUDENT | adds `current` (code, title, units, type, core/elective, level, semester, status, date registered, override, marked), `issues`, `override` |
| `GET /students/{id}/registration/checks?session&semester&offering&verb` | VIEW_STUDENT | the rules judged now — what the confirmation dialog shows |
| `GET /students/{id}/registration/offerings?session&semester&q` | MANAGE_REGISTRATION | courses offered beyond the menu, for an override |
| `POST /students/{id}/registration/add|drop|restore|submit` {…, override, description, ticket} | MANAGE_REGISTRATION (+ OVERRIDE_REGISTRATION and the ticket for an override) | through the engine; before and after on the ledger |
| `POST /students/{id}/password` {method LINK or TEMPORARY, reason, ticket} | RESET_PASSWORD (TEMPORARY on a ticket) | the link's addresses come back masked; a temporary password comes back once |
| `POST /students/{id}/tickets` | CREATE_TICKET | `helpdesk.submit` and `helpdesk.route` with the student as requester; an internal note names the agent |
| `POST /students/{id}/escalate` {ticket, office, reason} | the ticket in reach | to the Bursary, the Director of ICT, Examinations and Records, the Academic Office or the Registry |
| `GET /actions?module&action&agent&from&to&overrides&export` | VIEW_SUPPORT_AUDIT | the desk's own audit within scope |
| `GET /payments?q&state` | INVESTIGATE_PAYMENT | by payment reference (the portal's invoice), receipt, gateway or transaction reference, matric, JAMB or application number, student ID, surname |
| `GET /payments/{reference}` | INVESTIGATE_PAYMENT | the diagnosis: gateway, finance, entitlement, verification, current; attempts, events (no payloads), refunds, related references, advice, allowed acts |
| `POST /payments/{reference}/investigate|verify|refresh|receipt` | INVESTIGATE / VERIFY_PAYMENT / SYNC_ENTITLEMENT / REGENERATE_RECEIPT | each on the ledger and the ticket |
| `GET /payments/{reference}/receipt` | VIEW_PAYMENTS or INVESTIGATE_PAYMENT | the receipt's facts; the desk prints the student's own receipt (`/helpdesk/payments/{ref}/receipt`, the same drawing function) |

The ticket screen's own password reset now resets the student named by the record (not an identifier), needs
RESET_PASSWORD on a posting covering the student, and goes on the ledger. `/api/v1/helpdesk/counts` adds the open
registration, payment and password tickets.

## 12. The screens

- **Student support profile**: the Support Action Center (only the permitted acts); application number and current
  semester; a payment summary; *Manage course registration* — current registration, outstanding issues, the engine's
  menu with **Add course**, **Drop course** and **Restore**, each opening the dialog that shows the student, course,
  session, semester and units, every rule judged, the reason and the ticket — and, where only the window or the menu
  blocks and the posting carries it, **Apply support override** with the normal rule shown; a search for a course
  missing from the menu; **Submit**; the registration history (now read correctly). **Reset password** (link, or a
  temporary password on a ticket, shown once). **Create support ticket**, **Escalate**, **Resolve ticket** (the summary
  drafted from the acts done on it). **Support history**: date, agent, module, action, ticket, reason, result.
- **Payment Support** (`/helpdesk/payments`, `/helpdesk/payments/{reference}`): the search; the diagnosis in five words
  (current, gateway, finance, entitlement, verification) and the advice with its one act; Verify, Recheck/re-sync,
  Refresh entitlement, View receipt, Regenerate receipt, Escalate to Bursary, Escalate to ICT Director — there is no
  "mark as paid".
- **Support Action History** (`/helpdesk/audit`): every support act within scope, filters, overrides only, Excel.
- **Support Desk**: below the tickets (the ticket-first order is unchanged), a *Student support* section — the student
  search, course registration issues, payment issues, password reset requests, escalated issues, and links to Payment
  Support and the Support Action History.

## 13. Notifications

Through the existing notice queue, to the address the University reaches the student at: "Your course CSC 101 has been
added to your current course registration by ICT Support", "…removed from…", "Your portal password reset has been
initiated by ICT Support. Follow the secure instructions to create a new password" (with the link, for the link
method), "Your payment issue has been resolved. Your verified payment has been synchronized with your student portal",
"Your receipt is ready". No password, no amount, no account detail.

## 14. Tests

- `db/check.sql` property 191: the ticket timeline takes a support act; the menu and the window set aside only by an
  override, written with its rule, refused without a ticket; another semester's course, unpaid fees, the unit ceiling and
  a closed semester never set aside; a drop keeps the entry as DROPPED; the entitlement refreshed only for a confirmed
  payment and without a new one; no password on the ledger; a temporary password always forces a change; a capability
  reaches only the students its posting covers; EDIT_RESULTS refused. Suite: 191 properties green on a brand-new database.
- `SupportResolutionIT` (the brief's 37 scenarios): registration read and rules listed; an eligible course added and a
  current one dropped through the engine, on the ledger and the ticket; an unknown course, a course outside the
  programme, another semester's course, the unit ceiling, the fees and the window refused; the override authorised,
  refused without the capability or the ticket, recorded with the normal rule; a closed semester's registration and its
  result untouched; the student told. Password: refused without the capability; the link through `iam.password_reset`;
  no hash or password in any response; the temporary password random, hashed, time-limited, one sign-in, forced change,
  the matriculation number refused while it stands; both resets on the ledger without the password. Payments: found by
  reference and matric number; diagnosed; no refresh and no "confirm" for an unconfirmed payment; verified through the
  payment service; the entitlement refreshed without a new payment; the receipt; every act audited; the student told
  without the amount; escalation to the Bursary. Security: another faculty's student not found by changing the id — read,
  registration, password, payment; results, refunds, fees and admission decisions refused with 403; the seven forbidden
  capabilities refused on a posting; the Action Center offers only what the posting carries.
- `SupportDeskIT`: the ticket screen's reset refused without RESET_PASSWORD, then sent and on the ledger once granted.

## 15. After deployment

The Head of the Support Desk ticks the new capabilities on the postings that need them (Agents, Queues and Routing).
Until then nothing new is reachable: an agent whose posting carries no RESET_PASSWORD can no longer send a student's
reset from the ticket screen (the Head and the Director still can).

# Part III — JUPEB records (V347)

ICT Support reaches the JUPEB programme's candidates and students with the same capabilities and the same ledger. The
JUPEB module already depended on the helpdesk (its candidates' tickets), so the support screens for JUPEB records live in
the JUPEB package (`JupebSupportController`, `/api/v1/helpdesk/support/jupeb`) and write the ledger through
`helpdesk.record_jupeb_support_action`; the helpdesk never imports JUPEB code (no module cycle).

- **Reach.** A JUPEB record is reached through a live posting on the `JUPEB_SUPPORT` queue, a `GLOBAL` posting, or a
  posting scoped to the JUPEB Office; the capabilities are those postings' (`helpdesk.agent_jupeb_capabilities`). Without
  reach, the search says so (`SUPPORT_JUPEB_SCOPE`) and a record is *not found*.
- **The ledger.** `helpdesk.support_action` names exactly one subject: `student_id` or `jupeb_application_id`
  (`ck_hd_sa_subject`). A JUPEB act on a ticket must be on that candidate's own ticket (`SUPPORT_TICKET`).
- **The acts.** View (VIEW_STUDENT; documents with VIEW_DOCUMENTS; payments with VIEW_PAYMENTS or INVESTIGATE_PAYMENT),
  contact correction (EDIT_CONTACT), password reset (RESET_PASSWORD: the JUPEB portal's one-hour link, or a temporary
  password on the ticket — one sign-in within 24 hours, changed at it), gateway verification (VERIFY_PAYMENT, through
  `PaymentsService.verify`), activation refresh (SYNC_ENTITLEMENT, `jupeb.activate_if_due`), a ticket raised for the
  candidate (CREATE_TICKET), escalation to the JUPEB Office, the Bursary or the Director of ICT. Identity details stay the
  JUPEB Office's (the candidate's `CORRECT_DETAILS` request); no admission, grade, fee, refund or "mark as paid" exists here.
- **The screens.** Menu → *JUPEB Student Support* (`/helpdesk/jupeb`, `/helpdesk/jupeb/{id}?ticket=`); the ticket screen of
  a JUPEB ticket links to it, and no longer offers the University's own reset there (`SUPPORT_JUPEB_RESET`).
- **The audit.** The Support Action History lists JUPEB acts to the Head and to agents whose JUPEB postings carry
  VIEW_SUPPORT_AUDIT.
- **Tests.** `JupebIT.supportOldPaymentsSelfServiceTimetablePracticeAndReports` (reach, ledger, capabilities, the
  temporary password once) and `check.sql` property 192.
- **After deployment.** The Head of the Support Desk posts the agents who serve JUPEB candidates on the JUPEB Support queue
  with the capabilities they need. Until then only the Head, the Director of ICT, admin and super reach JUPEB records.

## 16. Students the desk cannot reach (V565)

On the live-shaped copy (19 Oct 2026), 13,866 of 48,320 active students (29%) had no e-mail on record, and about 13,560 of them had no phone either. The desk could not raise a ticket for any of them ("The record holds no email address for the ticket's updates"). A reset link or a ticket update could not reach them.

- **A ticket raised at the desk with the contact the student gives.**
  - When the record holds no e-mail, **Create support ticket** asks for the student's e-mail, and their phone where there is none either.
  - With contact editing (EDIT_CONTACT), the agent may **Save it to the student's record**. This is the same edit as Edit student record: written to the record, kept in step with `people.student_contact`, on the ledger, and the student is told.
  - Without contact editing, the contact serves this ticket only, and asking to save it is refused (`SUPPORT_CAPABILITY`).
  - With neither on record nor given, the ticket is refused (`SUPPORT_TICKET_CONTACT`).
  - Phones are kept as 0 and ten digits; +234 is read as 0.
- **A student's ticket by phone alone.**
  - `helpdesk.submit` (restated) takes a STUDENT ticket with a phone and no e-mail. Its updates go by SMS in a line: "MOAUM ICT Support: <the update>. Sign in to the portal to read it: Support, My Tickets." (`TicketNotifier.toRequester`).
  - A ticket raised from the sign-in page or by staff still needs the e-mail its tracking page reads.
- **Students We Cannot Reach** (`/helpdesk/reach`, menu id `t/supportreach`, every agent with VIEW_STUDENT, within their reach):
  - covers the current students (active, on probation, admitted, deferred) with no e-mail and no phone, no e-mail, or no phone on record. These are read as `people.student_reach` reads them: the contact the student gave, otherwise the applicant account's;
  - counts are shown by faculty (`helpdesk.reach_gaps`), with a page of students to open and put right;
  - the list can be filtered by faculty, level, name or number;
  - Excel export needs EXPORT_STUDENTS;
  - API: `GET /api/v1/helpdesk/support/reach?kind=NEITHER|NO_EMAIL|NO_PHONE`.
- **Tests.**
  - `SupportReachIT`: refused, saved, the SMS, off the list.
  - check.sql's V565 block: the phone-only ticket, the counts.

## 17. Contacts uploaded by the Registry and the departments (V572)

The desk takes a contact one ticket at a time; the Registry and the departments hold class lists with the numbers. On the
copy, 13,576 current students had neither a phone nor an e-mail on record, and 31,185 lacked one or the other.

- **Student Contacts Upload** (`/student-contacts`, menu id `t/contactupload`): the Registrar, the Deputy Registrar, Records,
  the Academic Office and the Super Administrator for the University; a Dean or Faculty Officer for their faculty; a Head of
  Department for their department (held on the server, whatever the request names).
- **The template** lists the current students (active, on probation, admitted, deferred) missing a contact, either everyone
  missing one or only those with neither, with what is missing and empty Phone and E-mail columns
  (`people.contacts_missing`).
- **The upload** (.xlsx or .csv; the header row is found under the template's crest) is previewed row by row, with nothing
  written, then loaded (`people.load_contacts`):
  - Each row is matched to one student by matriculation, admission or JAMB number, in any case.
  - A field is **filled only where the student holds none** (the contact they gave, otherwise their applicant account's, as
    `people.student_reach` reads it). A contact the student holds is **kept**, never overwritten.
  - **Refused:**
    - a phone or e-mail another student holds, or one an earlier row of the file gives to another student (a reset link sent
      there would reach someone else);
    - a malformed one (a phone is 0 and ten digits; +234, and a number Excel stripped of its leading 0, are read as such);
    - a student outside the uploader's reach;
    - a number matching no student, or more than one;
    - a second row for the same student;
    - a row with no number or no contact.
  - One upload holds up to 20,000 rows; 5,000 load in about 1.4 s on the copy.
- **Each upload is kept** (`people.contact_upload`, audited) with the office, the reach, the file, the rows, the students,
  phones and e-mails filled, the rows not written and the reason, and is listed on the page.
- **API:** `GET /api/v1/student-contacts`, `GET /api/v1/student-contacts/missing?neitherOnly=`, `POST /upload/preview` and
  `POST /upload` `{fileName, rows: [{number, phone, email}]}`.
- **Tests:** `StudentContactUploadIT`; check.sql's V572 block; `lib/contact-upload.test.ts`.

## 18. Uploaded contacts confirmed by the student (V575)

A phone or e-mail a department uploads (§17) could be mistyped. Until V575, that student's password reset link would then have
gone to someone else.

- **Held unconfirmed.** `people.student_contact.email_pending` and `phone_pending` are set, with the upload named, when an upload
  fills the field. Notices and announcements reach the contact at once. A password reset link does not
  (`people.student_reset_reach`).
- **Kept only on the write that set it.** A trigger clears the mark when anyone else changes the value: the student's own save, or
  the desk's edit.
- **The student confirms on the first screen** ("Is this yours?", `/iam/me` → `contactConfirm`). A six-digit code is sent to the
  contact (at most three an hour, each valid for fifteen minutes, five tries) and entered while signed in. Or the student says it
  is not theirs, and the field is emptied. API: `GET /api/v1/me/contact/pending`, `POST /api/v1/me/contact/confirm/code`,
  `POST /api/v1/me/contact/confirm`, `POST /api/v1/me/contact/not-mine`. The code is kept only as a hash.
- **The desk confirms it after checking with the student.** The student's Reach panel marks the contact "From an upload — not
  confirmed". An agent with contact editing records how it was checked; this goes on the history as a contact edit
  (`POST /api/v1/helpdesk/support/students/{id}/contact/confirm`).
- **Reset links.** The forgotten-password door sends no link to an unconfirmed contact (its answer is the same as ever). The desk's
  reset link, including a bulk reset's, is refused with `AUTH_CONTACT_UNCONFIRMED`: confirm the contact first, or issue a temporary
  password.
- **Outcomes per upload.** Each upload counts its contacts awaiting the student, confirmed (by the student or the desk) and not
  the student's (`people.contact_upload_outcomes`). Uploads made since V572 were marked unconfirmed from the audit trail.
- **Tests:** `ContactConfirmIT`; check.sql's V575 block.
- **The uploader told (V580).** The person who uploaded a contact is told:
  - At once, when the student says it is not theirs: the student, the contact, the file and its date
    (`CONTACT_UPLOAD_REJECTED`, from `people.contact_refuse`), so the class list is put right.
  - Each Monday at 08:45, for an upload at least 30 days old whose contacts still wait for the students: how many wait
    (`CONTACT_UPLOAD_WAITING`, `people.chase_unconfirmed_contacts`, once a week per upload). Settings:
    `moaum.contacts.chase-cron`, `moaum.contacts.chase-after-days`.
  - ICT can switch either notice off under the notice templates. Tests: `LevelFeeEffectSpilloverCopyIT`; check.sql's second V580
    block.
