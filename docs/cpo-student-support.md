# Student record support from the ICT Support Desk (V334)

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
