# The JUPEB programme (V339, V341–V345, V347–V349)

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
- **Practice tests are the JUPEB module's own (V347).** The University's CBT engine (V322) is bound to `people.student`
  and the catalogue's course offerings, which a JUPEB candidate does not have; reusing it would mean putting candidates on
  the undergraduate register. `jupeb.practice_*` is a small engine of its own: never a result, never an examination.
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
- **Students registered on the old portal (V345).** JUPEB → Old-Portal Students (or the button on Applications) reads the
  old portal's export (App No, First/Middle Name, Surname, Sex, LGA, Phone No, State, Date of Birth, NIN, Email; Programme
  and Combination when present). Every row is judged first and nothing is written on the preview: App No, names and a valid,
  unused email are required (a row to correct is skipped and exported for correction); an unreadable phone, NIN, sex or
  date is left blank and said; a student already on the portal is skipped, so the same file can be uploaded again. Dates are
  read day/month/year unless the office says otherwise (upload the file as the old portal gave it: Excel may turn 9/1/2004
  into 1 September). Each student becomes an active JUPEB student of the session chosen, with the old App No as the
  application number and username, marked as from the old portal; a **temporary password** is generated for each, shown to
  the office once in a downloadable login sheet (never stored readable, never emailed), and must be changed at first sign-in;
  each student can also be emailed a seven-day link to set their own password. Nothing else is announced while the records
  are written; no fee reminder reaches them (what they paid on the old portal is the Bursary's), and the Payments tab says
  so. Their programme is set by the combination they register.
- **The list for examination numbers (V345).** JUPEB → Examination Numbers → *List for the Board*: the active students whose
  three subjects are registered (without a number, or everyone), downloadable in **Excel** (columns Application Number,
  Surname, …, JUPEB Examination Number — the very columns the examination-number upload reads, so the Board's returned list
  is uploaded as it is) and **PDF** (landscape, on the letterhead, with signature lines). Students not yet registered are
  counted, not listed.
- **Documents viewed in a pop-up.** On the office's record and the candidate's own pages an uploaded document opens over the
  page (previous/next, rotate and actual size for photos, download, open in a new tab, and the office's Verify / Problem).
- **Acting on the attendance minimum (V344).** The JUPEB Office's policy (Attendance → Minimum attendance) has the minimum,
  an optional **warning band** (a student above the minimum by fewer than so many points is *close to the minimum*) and the
  **classes counted before a warning** (default 3, so one early absence is not a 0%). `attendance.jupeb_standing(session)` gives
  every student's rate per subject and semester against it. A student below the minimum sees it on their dashboard; the
  office sees it on the Standing tab (below / close / everyone, with export), on the record and as a dashboard tile; and the
  student is warned by email on the reminder **Attendance below the minimum** (its own start, spacing, cap and SMS; at most one
  reminder a day), or at once from the Standing tab. With no minimum set nobody is below it or warned. What a shortfall means
  for the examination is the University's decision; the portal only reports and warns.
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

- **ICT Support on JUPEB records (V347).** The same desk, capabilities and support ledger as the students' (V346). An agent
  reaches JUPEB records through a live posting on the JUPEB Support queue, a University-wide posting, or a posting on the JUPEB
  Office (`helpdesk.agent_reaches_jupeb`), and does only what those postings carry (`helpdesk.agent_jupeb_capabilities`; the
  Head of the desk, the Director of ICT, admin and super have all). An agent without that reach gets *not found*. The acts:
  read the record (the documents and fees only with their capabilities); correct the contact details with a reason; reset the
  password — the JUPEB portal's own one-hour link, or, on the candidate's own ticket only, a random 12-character temporary
  password (bcrypt, never recorded, shown once) that works for one sign-in within 24 hours and is changed at it (a second sign-in
  with it is refused `AUTH_TEMP_PASSWORD_SPENT`); ask the gateway again about a JUPEB payment through `PaymentsService.verify`
  (never a payment created or marked paid); re-apply the activation a confirmed school fee earns (`jupeb.activate_if_due`);
  raise a ticket for the candidate; escalate to the JUPEB Office, the Bursary or the Director of ICT. Every act is a row of
  `helpdesk.support_action` with `jupeb_application_id` (and no `student_id`), on the ticket's timeline when there is one; the
  candidate is told. The ticket screen's "send password reset" is refused for a JUPEB ticket (`SUPPORT_JUPEB_RESET`): it is
  the University's own reset and must not reach another account through a shared email.
- **Old-portal payments (V347).** The old JUPEB portal's payment export — App No, reference, purpose (or a semester column),
  amount, date, status — is judged row by row (a preview writes nothing), then each successful payment of a student found by
  the old App No (never by name) is posted once as a confirmed `jupeb.fee_reference` on the channel `Old portal`, with its old
  reference kept in `jupeb.legacy_payment` (unique). A failed or pending row, an unreadable amount or date, an unknown App No,
  a repeated reference, or a fee already paid is listed and never posted. "School fees" naming no instalment is the full fee
  only when the amount covers the student's school fee; otherwise it is listed for the office to say which. The amount is the
  old portal's receipt; the Bursary's fee settings are not changed. Once a student's old payments are on the record the daily
  fee reminders resume for what is still owed, and the student's Payments page shows the balance and the pay buttons. The
  second instalment is charged as the balance the Bursary's fee leaves owing (`jupeb.new_fee_reference`): for a first share
  paid here that is exactly the second share; for an old-portal instalment of another amount it is what remains, so no
  balance is ever left without a way to pay it (and none is charged once the fee is paid).
- **The student's own details (V347).** Phone, contact and permanent addresses, guardian and next of kin are the student's to
  update from My Profile (the phone is never blanked; each change on the trail as `CONTACT_UPDATED`). Name, sex, date of birth,
  NIN, nationality, state of origin and LGA are asked of the JUPEB Office as a `CORRECT_DETAILS` change request — each field
  with its present and corrected value — and applied only when the Office approves; a school fee already charged stays as it
  was charged.
- **Timetable (V347).** Weekly slots of a subject in a session and semester, for one class or every class; a class is never
  booked twice in the same hour (`JUPEB_SLOT_CLASH`); the lecturer shown is the instructor assigned on Attendance. The student
  sees the slots of their own subjects and class, and prints them.
- **Practice tests (V347).** A test of one subject with a question bank uploaded from Excel or CSV (question, options A–E,
  answer, explanation — each row checked), opened only with questions. An attempt draws its questions at random, is timed and
  marked by the server (an attempt past its time is marked on the next read); the answer key and explanations reach the student
  only after submission and only where the test shows them; attempts are limited per student. Never a result.
- **Reports (V347).** For a session: applications by state, programme, combination, state of origin and class; confirmed fees by
  kind and month (old-portal payments counted apart) and the school-fee position; attendance and results by subject; practice.
  Each table in Excel and PDF. Read only — the Bursary's figures are not changed.

- **Documents kept (V348).** The file migration job's orphan sweep had removed every JUPEB document and passport from the
  bucket an hour after upload (the JUPEB table was not on its list and had no foreign key). The sweep now asks the catalogue
  for every `object_id` column, every such column references `platform.file_object`, and the eleven documents lost are in
  `jupeb.document_lost` and marked for re-upload; a submitted candidate replaces a document marked for replacement from
  Documents.
- **Announcements (V349).** The JUPEB Office publishes a notice to a session's candidates — everyone, those not yet admitted,
  the admitted, the active students, one class, one combination or one programme — after seeing how many it will reach. It
  shows on each reached candidate's dashboard at once (pinned first, until it expires), with an unread count in the side menu,
  and is emailed and texted (the title and a pointer to the portal) when the Office asks. A withdrawn application is reached by
  nothing. A notice is withdrawn with a reason, never deleted; an email or a text already sent is not called back.
- **Practice questions with formulas and images (V349).** Formulas are written between dollar signs (`$x^2$`, `$H_2O$`,
  `$\frac{1}{2}mv^2$`, `$\sqrt{b^2-4ac}$`, `$\alpha$`, `$\to$`, `$30^\circ$`) in the question, the options and the
  explanation, and drawn by the portal's own elements (`lib/mathtext.ts`, `MathText`) — never as HTML; the exports write them
  plainly (x², H₂O, 1/2mv²). A question may carry one PNG or JPEG of up to 1 MB, kept privately like the documents and shown to
  the office and to a student only inside an attempt that drew the question. The office types a question one at a time with
  a live preview, or uploads a bank as before. A question already answered is never rewritten: an edit makes a new version
  (taking the image along) and the attempts that used the old one keep it.
- **The identity card (V349).** An active student with a passport photograph on file has a card — the University's card design,
  marked JUPEB — whose QR carries a code issued like the other papers (`ID_CARD`) and verified at `/verify/jupeb/{code}`; the
  verification shows the name, the application number, the session, the programme and the combination, never the NIN, the date
  of birth or a contact. The examination number is printed but is not part of what the code states, so its arrival does not void
  a card. The student sees their card; the JUPEB Office issues and prints cards for a class or those chosen (true to size, front
  and back), and replaces a lost card — the old code is revoked with the reason and stops verifying.
- **Report charts (V349).** The Reports page opens on a Dashboard of charts: the session's applications by stage, the programmes,
  the largest combinations and states of origin, fees confirmed by month, the school-fee position, attendance and grades by
  subject, and the practice scores.

## API

- **Public:** `/api/v1/jupeb/options`, `/apply`, `/sign-in`, `/forgot`, `/reset`.
- **Candidate** (`OFFICE_applicant`, scoped to the token's application): `/api/v1/jupeb/me`, plus `/biodata`,
  `/choice` (programme and combination), `/olevel`, `/documents/{kind}?sitting=` (with `/content`),
  `/fee-reference?kind=`, `/submit`, `/register-subjects`, `/attendance`, `/papers`, `/requests` (with `/{id}/cancel`),
  `/support`, and (V347) `/contact`, `/corrections`, `/timetable`, `/practice` (with `/{test}/start`, `/attempts/{id}`,
  `/attempts/{id}/answers/{question}`, `/attempts/{id}/submit`), and (V349) `/announcements` (with `/{id}/read`),
  `/practice/attempts/{id}/questions/{question}/image`, `/id-card`.
- **Public verification:** `/api/v1/verify/jupeb/{code}`.
- **JUPEB Office:** `/api/v1/jupeb/office/...`, including `/subjects/offered`, `/combinations/offered`,
  `/subjects/{code}/units`, `/applications/{id}/papers`, `/papers/{code}/revoke`, `/requests`, `/applications/{id}/requests`,
  `/requests/{id}/decide`, `/applications/{id}/resume`, `/reminders` (with `/due`, `/run`, `/{kind}`), and (V347)
  `/old-portal-payments` (with `/import`), `/timetable` (with `/{id}`, `/{id}/remove`), `/practice-tests` (with `/{id}`,
  `/{id}/questions`, `/{id}/questions/{q}/remove`) and `/reports?session=`, and (V349) `/announcements` (with `/reach`,
  `/{id}/withdraw`), `/practice-tests/{id}/questions/add`, `/practice-tests/{id}/questions/{q}` (PUT), `.../{q}/image` (with
  `/remove`), `/id-cards` (with `/issue`, `/{id}/replace`). Reads are for jupeb, super and admin; writes for jupeb and super.
- **ICT Support (V347):** `/api/v1/helpdesk/support/jupeb` (search), `/{id}?ticket=`, `/{id}/contact`, `/{id}/password`,
  `/{id}/payments/{reference}/verify`, `/{id}/refresh`, `/{id}/tickets`, `/{id}/escalate` — for agents whose postings reach
  JUPEB records.
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
- `JupebAttendanceIT` also covers V344: the policy's band and classes, the standing list (office and admin only), the warning
  sent once and not again the same day, and the student's own standing.
- `JupebIT.oldPortalStudentsAreUploadedWithLogins` covers the old-portal upload (preview, bad email, the login once, sign-in
  on the old App No, the forced password change, re-upload skipped, no fee reminder); `applicationToResult` the Board list.
- `JupebIT.supportOldPaymentsSelfServiceTimetablePracticeAndReports` covers V347: the student's contact details (and the phone
  kept), a correction asked and approved, the old portal's payments (Bursary refused, preview, a failed row, an ambiguous
  "school fees", posted once, not twice, then the second instalment charged as the balance it leaves), a slot and its clash, a practice test (opened only with questions, no key before
  submission, scored, attempts limited, no result written), the reports (Bursary refused), and ICT Support on the record (no
  reach → not found, the contact correction on the ledger, a capability not granted refused, the temporary password only on
  the candidate's ticket, one sign-in, never recorded).
- `JupebIT.announcementsPracticeImagesAndIdentityCard` covers V349: a notice refused to the Bursary, its reach told first and
  matched, a class notice not reaching another class, the unread count and its reading, a withdrawn notice gone; a typed
  question with a formula, a refused question and a refused fake PNG, the image seen by the office and by the student only in
  their attempt, an answered question versioned with its image and the past attempt unchanged; the card refused without a
  photograph, the same code twice, verified without the NIN or contacts, the office's list and issue, a replaced card no longer
  verifying. `FileSweepIT` covers V348.
- `check.sql` properties 185–194 cover the rules on a brand-new database.

## Not done

- **Document uploads accept PDF, JPEG or PNG up to 5 MB.** There is no virus scanning, as elsewhere on the portal.
- **The move into 200 level (direct entry) is not built.** It is a decision for the University.
