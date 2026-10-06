# The JUPEB programme (V339, V341, V342, V343)

The JUPEB module takes a candidate from application to admission, payment, studentship, subject registration, the
official JUPEB examination number and the published result. It uses the portal's existing services rather than new
copies of them.

| Who | Where | What they do |
|---|---|---|
| Applicant / student | `/jupeb/apply`, then `/jupeb/portal` | Apply, sign in, complete the guided application (personal, O'Level, documents, programme and subject combination, review and submit), pay the application fee, check the admission status, accept, pay school fees, register subjects, see attendance, the exam number and results, download documents, raise support tickets |
| JUPEB Office (office `jupeb`) | `/jupeb` and its menu | Review, return, decide eligibility, admit (one or in bulk after a preview), screening, classes, subjects and combinations (disable and reactivate what the University does not offer), course units, examination numbers, results, attendance (registers, instructors, minimum), settings, payments (read only) |
| Lecturer | Lecturer menu → JUPEB Attendance | Take attendance for the JUPEB subjects and classes the JUPEB Office assigned them, and nothing else |
| Bursary | `/finance/jupeb-fees`, `/jupeb/payments` | Set every JUPEB fee (application, status checking, acceptance, school fees); confirm a bank payment from the teller |
| Director of ICT | Portal Windows → Application Registration Control | Open, close, schedule and extend the **JUPEB application** window and the **JUPEB admission status checking** window |
| Super Administrator | the JUPEB group in its menu | Everything the JUPEB Office and the Bursar do |

## Implementation map

### Reused

| Concern | Existing piece | How JUPEB uses it |
|---|---|---|
| Sign-in | `/api/auth/sign-in` (one door), `TokenIssuer`, `platform.session` | `JUPEB/APP/YYYY/NNNNNN`, or the email, signs in at `/api/v1/jupeb/sign-in`. The token's office is `applicant` and its subject is the candidate's JUPEB application. |
| Payments | `PaymentsService` / `PaymentsRepository`: gateways, checkout, verify, webhooks, reconciler | `jupebReference`/`confirmJupeb` join the reference chain beside the PG one. Kinds `JUPEB_APPLICATION`, `JUPEB_STATUS_CHECKING`, `JUPEB_ACCEPTANCE`, `JUPEB_SCHOOL_FIRST/SECOND/FULL`. An entitlement is the confirmed reference itself, never a flag the page sets. |
| Windows | `policy.portal_window`, `window_state`, `window_act`, `ApplicationWindows` | Types `JUPEB_APPLICATION` and `JUPEB_ADMISSION_STATUS_CHECKING` (V342). Both are **closed until the Director first opens them**. |
| Files | `FileObjects` (private object store, or bytes in the database) | Documents are private. No URL is stored. They are streamed only to their owner, the JUPEB Office, or (the passport only) an instructor of a subject the student takes; uncached and sandboxed. `?format=jpeg` converts a PNG passport for the PDFs. |
| Notices | `platform.queue_notice` (email, SMS) | Every step tells the candidate — without revealing the admission decision before it may be read. |
| Audit | `audit.attach` and attribution | Every JUPEB and attendance table is on the spine, except the account and reset tokens (password hashes) and the document bytes. |
| Support | `helpdesk.submit/route`, `TicketNotifier` | Requester kind `JUPEB`, queue `JUPEB_SUPPORT` (office `jupeb`) and category `JUPEB`. |
| Documents | `PdfDocument` (letterhead, footer, passport slot) | `/jupeb/pdf/{doc}`: acknowledgement, summary, status slip, admission letter, acceptance letter, school fees invoice, receipts, registration slip, statement of result — each with the passport at the top right. |
| Exports | `brandedXlsx` | Every list exports with S/N first. |

### Kept apart, deliberately

- **A JUPEB candidate is not put on `people.student`.** The undergraduate register is tied to matriculation. A single
  record, `jupeb.application`, carries the person from applicant to student to result.
- **JUPEB subjects are not catalogue courses.** The Board examines JUPEB subjects; the units printed on the statement
  (BIO 001 …) are `jupeb.subject_unit`.
- **The O'Level is stored separately.** The undergraduate O'Level store is keyed on JAMB records.
- **Attendance is a new engine (schema `attendance`).** The University's register (`registration.attendance`) records
  only present/absent for undergraduate offerings. The engine is shaped by context (JUPEB now) for later reuse.

## Rules (all on the server)

- **Application.** Accepted only while the window is open. The short form asks for names, sex, date of birth, NIN,
  email, phone, password, and the programme: **Science or Non-Science** (V341 wrote Arts; V342 carried those over). The
  number `JUPEB/APP/<year>/<6 digits>` is permanent.
- **The guided application (V342).** Five steps — personal information, O'Level, documents, programme and subject
  combination, review and submit — judged by `jupeb.step_status`, field by field. Save & Continue saves the step and
  moves on only when it is complete; the candidate resumes at the first incomplete step.
- **O'Level sittings.** The candidate declares one or two sittings. Each sitting has its examination body, number and
  year; the same result is not entered twice; combined, five credits (A1–C6) with English and Mathematics. **Each sitting's
  result is its own document, and both are required.**
- **Programme and subject combination.** The candidate chooses Science or Non-Science and one **offered** combination
  of it (Science: the Science and Engineering areas; Non-Science: every other; no area suits both). The application is
  complete only with one while any is offered for the programme. The student registers it — or another offered one
  of the programme — after activation, and only its three subjects.
- **What is offered.** The Board's 46 combinations (SC-001 to SC-046, 2026) and their 17 subjects are seeded. A
  combination is offered while it and its three subjects are active. The JUPEB Office disables a subject or a combination
  the University does not offer and reactivates it later, singly or several at once, with an optional reason kept on the
  audit spine (`POST /office/{subjects|combinations}/offered`, `jupeb.set_offered`). Nothing is deleted. A candidate
  holding a combination that stops being offered, before registering, is told to choose another; registered subjects
  are kept.
- **Submission** needs every step complete, including the application fee.
- **Decisions.** Eligibility needs a reason when the answer is no; a return needs what to correct; admission is
  Admitted, Not admitted or Pending; bulk admission previews every row first. An admission that is accepted or has a
  school fee paid is not withdrawn (`JUPEB_ADMISSION_PAID`).
- **Admission status checking (V342).** Closed until the Director of ICT opens it. A submitted applicant whose fee is
  confirmed pays the status checking fee (the Bursary's, ₦1,000 by default) **once** while it is open, then reads the
  status as often as they like: ADMITTED, NOT ADMITTED, PENDING, PROCESSING or REQUIRES REVIEW. Until then the
  candidate's record masks the decision (state shows as under review; letters and fees are not issued).
- **Acceptance (V342).** An applicant whose checked status is ADMITTED pays the acceptance fee (₦15,000 by default). The
  acceptance letter is issued only on its confirmed reference; school fees open only after it.
- **Fees (the Bursary's).** Application ₦15,000; status checking ₦1,000; acceptance ₦15,000; school fee by programme
  (Science pays the Science fee, Non-Science the other) and indigene status (Benue by default): ₦180,000, ₦195,000,
  ₦200,000, ₦215,000; 70% then 30%; frozen on the candidate when first charged. The JUPEB Office sees the amounts and
  cannot change them. A payment reference carries the session's year (`MOAUM-JUPEBAPP-2026-000001`, V342): the count
  restarts each session, and V339's form (`MOAUM-JUPEBAPP-000001`) would collide with the next session's.
- **Activation.** A candidate becomes a student when the Bursary's threshold is met; where screening is required,
  school fees open only after the candidate is cleared.
- **Examination numbers.** Imported by application number, never by name alone; a surname that disagrees is held for
  review; one invalid row stops the commit; a number already held changes only with a reason.
- **Results and the statement of result.** Grades A–F (5 … 0), with X (absent), Q (cancelled) and W (withheld) at 0.
  The grade point is out of 3 × 5 + 1 = 16: one point is added when all three subjects are passed (A–E). The statement
  follows the Board's sample: name (surname first), examination number, examination month and year (a JUPEB setting),
  "<year> JUPEB EXAM (A-Level Equivalent)", subject / grade letter / grade point, Grade Point = n/16, the key, the
  alteration warning, the authorised signature, and a note of each subject's course units. Candidates see results only
  after publication.
- **Attendance (V342).** A register is a subject (and class) on a day, for a session and semester; its class list is
  the active students registered for the subject (in the class). Marks are PRESENT, ABSENT, LATE or EXCUSED with a time
  and remark; mark all present; one save. A saved mark is corrected only with a reason (`attendance.mark_change`); a
  locked register only by the JUPEB Office, whose unlock needs a reason. A lecturer sees only what they are assigned
  (`attendance.instructor`), checked on every call. The rate is (present + late) ÷ (classes − excused). A minimum
  percentage is the JUPEB Office's setting; **while none is set, nobody is judged.** Students see their own attendance
  only.
- **Verifiable papers (V343).** The acknowledgement, admission status slip, admission and acceptance letters, registration
  slip, statement of result and receipts carry a QR and a code (`XXXX-XXXX-XXXX`, 60 random bits) issued by the server for
  the record as it stands (`jupeb.issue_paper`); the same paper printed again for an unchanged record keeps its code. The
  public page `/verify/jupeb/{code}` (and `/verify/jupeb` to type one) shows what the paper printed and whether the record
  still says it: **genuine and current**, **genuine but superseded** (a corrected grade, a changed combination, a withdrawn
  admission — the record now is shown), or **not genuine** (unknown, or revoked by the JUPEB Office with a reason). Only what
  the paper itself shows is disclosed — never the NIN, date of birth, email or phone. An unpublished statement carries no code.
- **Change requests after submission (V343).** The candidate (or the JUPEB Office at the desk) asks — never changes — to
  **withdraw**, **defer** an accepted, not yet activated admission to one of the next two sessions, **change the combination**
  (until the Board's examination number or a result exists; registered subjects follow the new combination), or **change the
  programme** (until a school fee is charged). A reason of at least ten characters; one request open at a time; the candidate
  may cancel it. The JUPEB Office approves (the change is judged again on the record as it then stands) or declines with a
  note the candidate reads. Withdrawal sets WITHDRAWN (record kept; refunds are the Bursary's own decision); deferment sets
  DEFERRED until the office resumes it in the later session, where the candidate is admitted again with what they paid.
  Every step is on the trail and emailed.
- **Reminders (V343).** Each morning at 10:00 (Africa/Lagos) the portal reminds a candidate with an unfinished step — the
  application fee unpaid, paid but not submitted (or a correction not resubmitted), no passport photograph, admission status
  not checked while checking is open, acceptance fee unpaid, school fee unpaid or a balance outstanding — at most one reminder a
  day, each kind on the JUPEB Office's rule (days after it began, every how many days, at most how many times, and SMS too or
  not). Application-step reminders only while the application window is open. Every reminder is logged; JUPEB settings show
  the rules, who is due now, and "send due reminders now".

## API

- **Public:** `/api/v1/jupeb/options`, `/apply`, `/sign-in`, `/forgot`, `/reset`.
- **Candidate** (`OFFICE_applicant`, scoped to the token's application): `/api/v1/jupeb/me`, plus `/biodata`,
  `/choice` (programme and combination), `/olevel`, `/documents/{kind}?sitting=` (with `/content`),
  `/fee-reference?kind=`, `/submit`, `/register-subjects`, `/attendance`, `/papers`, `/requests` (with `/{id}/cancel`) and
  `/support`.
- **Public verification:** `/api/v1/verify/jupeb/{code}`.
- **JUPEB Office:** `/api/v1/jupeb/office/...`, including `/subjects/offered`, `/combinations/offered`,
  `/subjects/{code}/units`, `/applications/{id}/papers`, `/papers/{code}/revoke`, `/requests`, `/applications/{id}/requests`,
  `/requests/{id}/decide`, `/applications/{id}/resume`, `/reminders` (with `/due`, `/run`, `/{kind}`). Reads are for jupeb,
  super and admin; writes for jupeb and super.
- **Attendance:** `/api/v1/attendance/jupeb/...` — options, registers, marks, lock/unlock, changes, photo, reports,
  instructors, policy. Lecturers are scoped by assignment.
- **Fees:** `/api/v1/jupeb/fees`. Reads for bursar, jupeb, super, admin and audit; writes and bank confirmations for
  bursar and super.

## Tests

- `JupebIT` runs the journey: windows, applying, signing in, the guided steps, two sittings with their own documents,
  the passport as JPEG, choosing an offered combination (and refusing one disabled or of the other programme), the
  office disabling and reactivating subjects and combinations, status checking (masked, closed, ₦1,000 once), acceptance
  (₦15,000, before school fees), fees, activation, registration, examination numbers, results, support, and RBAC.
- `JupebAttendanceIT`: a lecturer's scope, the class list, marking, corrections with reasons, locking, the office's
  override, photographs, the student's own attendance, reports and the minimum.
- `JupebIT` also covers V343: the acknowledgement's code and its public verification, change requests (reason, one at a time,
  declined with a note, cancelled), the statement of result superseded after a correction, a revoked slip, and the reminder
  rules, preview and run.
- `check.sql` properties 185–188 cover the rules on a brand-new database.

## Not done

- **Document uploads accept PDF, JPEG or PNG up to 5 MB.** There is no virus scanning, as elsewhere on the portal.
- **The move into 200 level (direct entry) is not built.** It is a decision for the University.
