# GST & EPS Management Engine (V314)

General Studies (GST) and Entrepreneurship Studies (EPS) are two academic offices over the courses the
catalogue already carries as kind `GST`. **One GST payment covers both.** There is no EPS fee. The Bursar
states the GST fee; the offices never touch it. Nothing here is a second student, finance, registration or
result system.

## A. Existing systems reused

| Need | What is reused |
|---|---|
| Students | `people.student` — no GST/EPS student record exists |
| Courses | `catalogue.course` (kind `GST`), `catalogue.course_offer` (basis `GST`), `catalogue.offering` |
| Course registration | `registration.student_draft / student_choose / student_add / student_submit`, `registration.entry` (type `GST`) |
| Payments | `finance.payment_reference` (purpose `GST fee <session>`), `finance.new_purpose_reference`, `finance.confirm_payment`, the gateway, receipts, refunds |
| Payment category | `finance.payment_category` `GST` (pattern `^gst`, V304) for the ledger and finance reports |
| Results | `assessment.score_sheet / score / decision`, the sheet chain, the sheet page and its bulk upload |
| Offices and RBAC | `ref.office`, `iam.office_assignment`, `OFFICE_<code>` authorities, `@PreAuthorize` |
| Audit | `audit.attach` on every new table; score amendments are versions with reasons |
| Notifications | `platform.queue_notice` through `people.student_reach` |
| Exports | `brandedXlsx` / `brandedPrint` (S/N first, names A–Z, frozen header) |
| Charts | `components/proto/vz` (Donut, HBars, GroupBars) with drill-down |

## B. New components

- `db/V314__gst_eps_engine.sql`
- `api/.../gst/GstController.java` (module `gst`)
- Results module opened to the two offices (`ResultsController`, `ResultsService.own/sheets`, `Sheets.DESK`)
- Student portal: `GET /api/v1/me/gst`, `POST /api/v1/me/gst/reference`, `gst` + `gstLocked` on the registration view
- Frontend: `/gst/*`, `/eps/*` (shared `GstDashboard`, `GstStudents`, `GstCourses`), `/student/gst`, the GST panel on Fee Setup, the lock and the PAY GST FEE call on the registration form and the student dashboard

## C. Database changes

| Object | Kind | Notes |
|---|---|---|
| `ref.office` rows `gst`, `eps` | data | scope `unit` |
| `catalogue.course.general_office` | column | `GST` or `EPS` for kind-GST courses, derived by `catalogue.general_office_of` and kept by trigger; partial index |
| `finance.gst_setting` | table (id = 1) | `required_for_gst_eps` (true), `required_for_all` (false), `covers_eps` (true) |
| `finance.gst_fee` | table (uuid PK) | per session; optional level / entry mode / faculty / programme scope; `superseded_at`; index on live rules |
| `finance.state_gst_fee`, `end_gst_fee`, `gst_fee_for` | functions | state, withdraw, price one student (most specific live rule) |
| `finance.gst_required`, `gst_entitlement`, `new_gst_reference` | functions | required by the curriculum; entitled by confirmed references net of refunds; the reference |
| `registration.gst_gate` | function | the coded refusal `GST_PAYMENT_REQUIRED`, or NULL |
| `registration.student_choose / student_add / student_submit` | functions | call the gate |
| `trg_gst_payment_notice` on `finance.payment_reference` | trigger | email + SMS on confirmation |
| `finance.gst_population(session, semester)`, `gst_course_stats(session, semester, office)` | functions | the set-based sources of every figure |
| `ix_pref_gst_fee` | index | `(session, student_id) WHERE purpose LIKE 'GST fee %'`, created concurrently |

All keys are UUIDs (`gen_random_uuid()`); business identifiers (reference, receipt, matric, course code) stay separate.

## D. API endpoints

| Method and path | Who | What |
|---|---|---|
| `GET /api/v1/gst/fee?session=` | readers | live rules, history, the rule, what was paid |
| `PUT /api/v1/gst/fee` | Bursar | state a fee (supersedes the same scope) |
| `POST /api/v1/gst/fee/{id}/end` | Bursar | withdraw a rule |
| `PUT /api/v1/gst/setting` | Bursar | the rule the payment enforces |
| `GET /api/v1/gst/{GST\|EPS}/dashboard` | readers | totals, by level/faculty/department/programme/gender, courses, results, options |
| `GET /api/v1/gst/{office}/students` | readers | paged, searched rows (size ≤ 500) |
| `GET /api/v1/gst/{office}/students/{id}` | readers | one student's standing |
| `GET /api/v1/gst/{office}/courses` | readers | catalogue, offerings, departments, programmes, lecturers |
| `POST/PUT /api/v1/gst/{office}/courses[/{code}]` | the office | create, edit |
| `POST /api/v1/gst/{office}/courses/{code}/activate\|deactivate` | the office | state |
| `PUT /api/v1/gst/{office}/courses/{code}/offers` | the office | programmes offered to, at a level |
| `POST /api/v1/gst/{office}/offerings` | the office | offer in a session and semester |
| `PUT /api/v1/gst/{office}/offerings/{id}/lecturer` | the office | lecturer through `catalogue.allocate_offering` |
| `GET /api/v1/results/sheets…`, `PUT …/scores`, `POST …/advance` | + gst, eps | their own courses' sheets only |
| `GET /api/v1/me/gst`, `POST /api/v1/me/gst/reference` | student | the fee, the entitlement, the reference |

A course code on a path carries its space as an underscore (`GST_101`).

## E. RBAC

- **Bursar** (`bursar`, `super`): states and withdraws the GST fee, sets the rule, reads both desks.
- **GST office** (`gst`): reads the GST desk, manages GST courses, enters and submits GST sheets. Refused the EPS desk, EPS courses, EPS sheets, and the fee (403).
- **EPS office** (`eps`): the mirror image.
- **Student**: reads their own GST standing, generates the reference, registers GST/EPS courses once entitled.
- **Readers** (registrar, deputy registrar, DVC, VC, academic, records, ICT, admin, super, finance controller): both desks.

## F. Payment flow

1. The Bursar states the fee for the session (Fee Setup → GST fee).
2. The student opens GST & EPS, sees the fee and `NOT PAID`, and clicks PAY GST FEE. `finance.new_gst_reference` refuses when no fee is stated or the fee is paid, returns an open reference again rather than doubling it, and otherwise generates one through `finance.new_purpose_reference` with purpose `GST fee <session>`.
3. The reference is paid on the gateway or at the bank and confirmed by `finance.confirm_payment`, exactly as school fees.
4. `finance.gst_entitlement` reads confirmed references of that purpose, net of approved or paid refunds, and answers `entitled` when a confirmed reference stands — the fee as it was when generated; a later change of the fee does not unmake a payment. The trigger tells the student by email and SMS. EPS is covered by the same answer (`covers_eps`).

Entitlement never comes from an invoice or a page. A refund approved or paid takes it away again.

## G. Registration flow

`registration.gst_gate(student, session, course)` returns `GST_PAYMENT_REQUIRED: …` when the fee is stated and
unpaid and the course is a GST/EPS course (`required_for_gst_eps`), or for any course when `required_for_all`
is on and the student is required. `student_choose`, `student_add` and `student_submit` raise it, so a direct
API call cannot bypass the block. With no fee stated there is nothing to pay and no gate. The registration form
shows the locked courses, the reason and a PAY GST FEE button; the API refuses with the code and the message.

## H. Dashboard queries

- `finance.gst_population` — one pass over the undergraduates: fee rule by LATERAL on a few rules, payments
  aggregated once through `ix_pref_gst_fee`, registrations aggregated once through `ix_entry_offering`.
- The controller counts with one `GROUPING SETS` query (totals, faculty, department, programme, level, gender),
  lists with `LIMIT/OFFSET`, and never loads the register into Java.
- `finance.gst_course_stats` — one row per offering with its registrations and sheet.

## I. Tests

- `GstEpsIT`: the fee is the Bursar's; an unpaid student is refused GST and EPS at the API and in the database
  and not another course; the reference, the confirmation, the entitlement, the registration, the notice; the
  dashboards and their scoping; course management and sheet access per office.
- `db/check.sql` property 159: the gate, the payment, the lift, the notice, the population.

## J. Security review

Backend authorisation on every endpoint; payment verification on the ledger only; the two offices separated
in the API and in the results module; the fee and the rule Bursar-only; every table audited; score changes are
versions with reasons.

## K. V366 — owed only for a course the student must take

The full implementation report (root cause, the eligibility algorithm, what changed in each part, the tests, the
production reconciliation) is in [gst-eps-eligibility.md](gst-eps-eligibility.md). In one line: the GST fee is
owed only when a GST or EPS course requires it of the student in the session — the programme's offering at their
level that runs in the session and they have not passed, a carryover that runs in the session, or a course on their
registration — read live by `finance.gst_eps_rows`, and every door (the fee, the reference, the gate, the menu,
the dashboards, CBT, the support desk) reads that one answer.
