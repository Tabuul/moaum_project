# The JUPEB programme (V339)

The JUPEB module takes a candidate from application to admission, payment, studentship, subject registration, the
official JUPEB examination number and the published result. It uses the portal's existing services rather than new
copies of them.

| Who | Where | What they do |
|---|---|---|
| Applicant / student | `/jupeb/apply`, then `/jupeb/portal` | Apply, sign in, continue the biodata, enter the O'Level, upload documents, pay, submit, read the decision and letter, pay school fees, register subjects, see the exam number and results, raise support tickets |
| JUPEB Office (new office `jupeb`) | `/jupeb` and its menu | Review, return, decide eligibility, admit (one or in bulk after a preview), screening, classes, subjects and combinations, examination numbers, results, settings, payments (read only) |
| Bursary | `/finance/jupeb-fees`, `/jupeb/payments` | Set every JUPEB fee; confirm a bank payment from the teller |
| Director of ICT | Portal Windows → Application Registration Control | Open, close, schedule and extend the **JUPEB application** window and write its closure message |
| Super Administrator | the JUPEB group in its menu | Everything the JUPEB Office and the Bursar do |

## Implementation map

### Reused

| Concern | Existing piece | How JUPEB uses it |
|---|---|---|
| Sign-in | `/api/auth/sign-in` (one door), `TokenIssuer`, `platform.session` | `JUPEB/APP/YYYY/NNNNNN`, or the email, signs in at `/api/v1/jupeb/sign-in`. The token's office is `applicant` and its subject is the candidate's JUPEB application. |
| Payments | `PaymentsService` / `PaymentsRepository`: gateways, checkout, verify, webhooks, reconciler | `jupebReference`/`confirmJupeb` join the reference chain beside the PG one. Kinds `JUPEB_APPLICATION`, `JUPEB_SCHOOL_FIRST/SECOND/FULL`. The day book and reference state include JUPEB. |
| Windows | `policy.portal_window`, `window_state`, `window_act`, `ApplicationWindows`, the public windows endpoint | A new type, `JUPEB_APPLICATION`. It is **closed until the Director first opens it**, guarded in Java and by a trigger on `jupeb.application`. |
| Files | `FileObjects` (private object store, or bytes in the database) | Documents are private. No URL is stored. They are streamed only to their owner or the JUPEB Office, uncached and sandboxed. |
| Notices | `platform.queue_notice` (email, SMS) | Every step tells the candidate. |
| Audit | `audit.attach` and attribution | Every JUPEB table is on the spine, except the account and reset tokens (password hashes) and the document bytes. |
| Support | `helpdesk.submit/route`, `TicketNotifier` | New requester kind `JUPEB`, queue `JUPEB_SUPPORT` (office `jupeb`) and category `JUPEB`. The category is hidden from students and staff. |
| Register | `ref.faculty`, `ref.programme` | The faculties and programmes a combination leads to (for the office's information). |
| Documents | `PdfDocument` (letterhead, footer) | Admission letter, receipt, registration slip, statement of result, application summary at `/jupeb/pdf/{doc}`. |
| Exports | `brandedXlsx` | Every list exports with S/N first. |

### Kept apart, deliberately

- **A JUPEB candidate is not put on `people.student`.** The undergraduate register is tied to matriculation. A candidate
  on it would be drawn into fees by level, GPA, matriculation, graduation and the statistics. A single record,
  `jupeb.application`, carries the person from applicant to student to result.
- **JUPEB subjects are not catalogue courses.** Catalogue courses produce score sheets and course registrations, and the
  Board examines JUPEB subjects.
- **The O'Level is stored separately.** The undergraduate O'Level store is keyed on JAMB records, and JUPEB needs no JAMB.

## Rules (all on the server)

- **Application.** It is accepted only while the window is open. The short form asks for names, sex, date of birth,
  NIN, email, phone, password, and the programme: **Science or Arts** (V341). There is no programme list and no
  subject combination on the form. Nationality, state and LGA, addresses, home
  town, guardian and next of kin are completed on the dashboard. The number `JUPEB/APP/<year>/<6 digits>` is permanent;
  the prefix is a JUPEB setting.
- **Submission** needs all of the following:
  - the application fee paid;
  - the biodata;
  - an O'Level of five credits (A1–C6), with English Language and Mathematics, in at most two sittings;
  - every required document.

  An application is edited only while it is a draft or after it has been returned. After submission, a document can be
  replaced only when the office asks for it.
- **Decisions.**
  - Eligibility needs a reason when the answer is no.
  - A return needs what to correct.
  - Admission is Admitted, Not admitted or Pending, and is made only on an eligible application.
  - Bulk admission previews every row first; the commit decides the rows that can be decided and lists the rest.
  - An admission with a school fee paid against it is not withdrawn here.
- **Fees (the Bursary's).** The application fee defaults to ₦15,000. The school fee is chosen by the applicant's
  programme (Science pays the Science fee, Arts the other fee; V341) and indigene status (state of origin against the indigene state, Benue
  by default). The defaults are ₦180,000, ₦195,000, ₦200,000 and ₦215,000. The first semester pays the Bursary's
  percentage (70%) and the second pays the rest. Full payment is allowed when the Bursary allows it. The total is
  **frozen on the candidate when first charged**, so a later change reaches only new charges. The first share is paid
  before the second. A session takes its own rule or the default (`*`).
- **Activation.** A candidate becomes a student when the Bursary's threshold is met (the first instalment, or the full
  fee). Where screening is required, school fees open only after the candidate is cleared.
- **Subject registration.** Once active, the student chooses one of the approved combinations of their programme
  (Science: the Science and Engineering areas; Arts: every other area; a combination with no area is open to both) and
  registers exactly its three subjects (V341).
- **Examination numbers.**
  - Numbers are imported by **application number**, never by name alone.
  - A surname that disagrees puts the row on review, and it is not applied.
  - A row is invalid for any of these reasons: an unknown application, a number another candidate holds, a number
    twice in the file, or a candidate who is not an active student with registered subjects. One invalid row stops the
    whole commit.
  - A number already held changes only with a reason. Every change is kept in `jupeb.exam_no_change`.
- **Results.** Grades are A–F (A = 5 points … F = 0), one per registered subject, imported by exam number (or
  application number). A correction needs its reason and is kept in `jupeb.result_change`. Candidates see results only
  after **publication**, which marks them COMPLETED and tells them.

## API

- **Public:** `/api/v1/jupeb/options`, `/apply`, `/sign-in`, `/forgot`, `/reset`.
- **Candidate** (`OFFICE_applicant`, scoped to the token's application): `/api/v1/jupeb/me`, plus `/biodata`,
  `/choice`, `/olevel`, `/documents/{kind}` (with `/content`), `/fee-reference?kind=`, `/submit`, `/register-subjects`
  and `/support`.
- **JUPEB Office:** `/api/v1/jupeb/office/...`. Reads are for jupeb, super and admin; writes for jupeb and super.
- **Fees:** `/api/v1/jupeb/fees`. Reads are for bursar, jupeb, super, admin and audit; writes and bank confirmations
  for bursar and super.

## Tests

- `JupebIT` runs the whole journey: the window, applying, signing in, eligibility rules, the documents' type check and
  privacy, fees by category and indigene status, 70/30, freezing, activation, registration, examination numbers (review,
  invalid, corrections), results (a correction needs a reason, publication), the support queue, and RBAC.
- `check.sql` property 185 covers the rules on a brand-new database.

## Not done

- **No combination is seeded.** The University's 43 approved combinations must be entered or uploaded on
  `/jupeb/catalogue` before the window opens. The portal does not invent them.
- **Document uploads accept PDF, JPEG or PNG up to 5 MB.** A file whose contents don't match its type is refused.
  There is no virus scanning, as elsewhere on the portal.
- **Withdrawal and the move into 200 level are not built.** No act withdraws a candidate, and no act carries a JUPEB
  graduate into 200 level (direct entry). Both are decisions for the University.
