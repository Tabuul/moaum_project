# The acceptance fee revised after part of it was paid, school fees before the student portal, and the student portal's fee gate (V724)

The University's brief of 11 November 2026 ("2026/2027 acceptance fee balance recovery, school fees configuration and student
portal access control"). The 2026/2027 acceptance fee was stated at ₦25,000 and is revised to ₦35,000: an applicant who paid
₦25,000 owes ₦10,000 and never ₦35,000 again; one who paid ₦35,000 owes nothing; one who paid nothing owes ₦35,000. The
admission letter waits for the balance. A newly admitted student pays the session's school fees from the applicant dashboard,
and the student portal opens only when the required payment is verified — never merely because an offer stands, the
acceptance is paid, a register row or an admission number exists, or the screening is complete.

Decisions the University took on 11 November 2026: the portal opens on the **first semester's** fees paid and verified (the
Bursar may switch the rule to the session in full); the revision and the gate apply to **UTME and Direct Entry** admissions
(CCE, preliminary and postgraduate admissions keep their own rules and doors); there is **no separate publish step** — a fee
line in force for the programme and level, with the session's school-fees payment window open, is "published"; the gate is
**on from deployment**.

## What stood before

- "Accepted" was a boolean: any confirmed `ACCEPTANCE` reference (`admissions.acceptance_entitlement.paid`), reporting the
  first reference's amount. `admissions.new_fee_reference` refused a second `ACCEPTANCE` reference outright once
  `acceptance_confirmed_at` was set, and fixed every reference at the whole stated fee. A restated fee could neither be owed
  nor paid.
- The admission letter (`admissions.issue_admission_letter`, both the applicant's and the student's door) followed
  `accepted_at` alone, and returned an already-issued letter before any guard.
- `admissions.applicant_fee` is one row a session, overwritten by the Bursary's restatement; history only on the audit spine.
- The register row (`people.student`, admission number) is created at acceptance, or at screening success where the session
  screens (`admissions.register_when_due` → `people.intake_one`), and the student door opened on that row alone
  (`StudentAuthService.continueFromApplicant`, sign-in on the admission or JAMB number). `admissions.admission_status`
  answered `SCHOOL_FEES_PENDING` with a link into the student portal whether or not a fee was stated.
- A fee line is live the moment the Bursary enters it; no draft or publish state exists.

## The database (V724)

- **`admissions.applicant_fee_revision`** — every statement of a session's applicant fees (the figures, the acceptance fee
  before, who, from which office, why), written by a trigger on `admissions.applicant_fee`; never changed or removed. A revision
  of the acceptance fee closes the session's open `ACCEPTANCE` references drawn at another figure. The rows before V724 are
  backfilled as stated.
- **`admissions.fee_reference.stated_fee`** — the acceptance fee stated when the reference was drawn.
- **`admissions.acceptance_fee_due(app)`** — the acceptance fee as stated now for the application's session (the route's for
  CCE, preliminary and proficiency; the Post-UTME figure otherwise).
- **`admissions.acceptance_entitlement(app)`** keeps its columns and adds `fee_due`, `paid_total` (confirmed references; a
  reversed confirmation has no `confirmed_at`), `balance`, `settled` (paid and nothing owed), `payments`, `balance_due` (a
  payment made through a reference short of the fee as stated now — what the letter waits for), `open_reference`,
  `open_amount`, `open_expires_at`. An acceptance confirmed with no reference behind it (by hand, or carried from the old
  portal) owes nothing, and a CCE, preliminary or proficiency acceptance paid once is paid, as before. `paid` is as it was:
  the place is held, the screening and the register follow.
- **`admissions.new_fee_reference(app, 'ACCEPTANCE')`** draws a reference for the balance (the whole fee before anything is
  confirmed), returns the one still open for that amount rather than a second (draws for one application are taken one at a
  time), closes one drawn for another figure, keeps the stated fee on the row, and refuses `ACCEPTANCE_SETTLED` once settled.
  UTME and Direct Entry; CCE as before.
- **`admissions.fee_reversal_check`** (V420's) lets the Bursary reverse a balance reference confirmed in error — V420 held every
  `ACCEPTANCE` reference once the offer was accepted, and a balance is always paid after acceptance. The payment the acceptance
  rests on stays held.
- **`admissions.issue_admission_letter(app)`** refuses `ACCEPTANCE_BALANCE_DUE` while a balance is due — read before the
  letter already issued is returned, so a letter printed before the revision is not printed again on a balance. The
  undertaking, the screening and the register do not wait. The tracker's letter step follows.
- **`finance.school_fee_state(student, session)`** — `NOT_CONFIGURED` (no fee line in force reaches the student, or nothing is
  due: nothing is charged at a guess), `PAID`, `PAYMENT_PENDING` (a reference awaiting the bank), `NOT_OPEN` (the payment
  window), `PART_PAID`, `AVAILABLE`, with `finance.position`'s figures, whether the first semester's fees are cleared
  (`finance.semester_cleared`), the window and the open reference.
- **`admissions.admission_status`** answers `ACCEPTANCE_BALANCE_PENDING` first for an applicant who owes the balance (the
  Accept page). The school-fee statuses follow where the student stands at the gate: a record the gate does not hold is told
  as before V724 (`SCHOOL_FEES_PENDING`, `/student/fees`); one let through by the Bursary reads "Student portal opened by the
  Bursary"; one cleared reads `SCHOOL_FEES_PART_PAID`; a held one reads `SCHOOL_FEES_NOT_AVAILABLE` (the University's words),
  `SCHOOL_FEES_NOT_OPEN` (scheduled or closed) or `SCHOOL_FEES_PENDING` with `next_href /applicant/admission#fees`. The fees are
  read for the student's entry session.
- **`finance.portal_fee_gate`** — one row: `enabled`, `from_session`, `clears_on` (`FIRST_SEMESTER` | `PAID_IN_FULL`), who
  changed it and why; set by `finance.set_portal_fee_gate` (Bursar, Director of ICT, administrators). At migration it is ON,
  from the entry session of the newest cohort of admitted-but-not-matriculated UTME/DE freshers on the register (the intake
  session where the register holds none) — never a session written into the code.
- **`finance.portal_fee_gate_exception`** — a named fresh admit let through on an `INSTALMENT_POLICY`, a `WAIVER` or a
  `BURSARY_DECISION`, for at most 200 days, one at a time; granted and revoked by the Bursary (`grant_portal_fee_exception`,
  `revoke_portal_fee_exception`).
- **`finance.portal_access_state(student)`** — `OPEN` (the gate off, or not a fresh UTME/DE admit of a gated session with an
  applicant account to pay from: every matriculated or returning student, every earlier cohort, every record without a
  candidate or an applicant account, postgraduate and CCE are outside it), `EXCEPTION`, `HELD_ACCEPTANCE_BALANCE` (the
  acceptance balance comes first — the brief's "acceptance fee partially paid: no access"), `CLEARED` (the first semester's
  fees, or the session's in full, paid; a first semester with nothing charged in it does not clear), `HELD_FEES_NOT_AVAILABLE`,
  `HELD_FEES_UNPAID`. Read at the student doors and on every student request; never cached. Matriculation, the register and
  the admission number are untouched: the gate only reads them.
- **`finance.programme_fee_coverage(session)`** — every undergraduate programme with or without a fee line reaching a fresh
  UTME (100 Level) or Direct Entry (200 Level) entrant; **`admissions.acceptance_fee_monitor(session)`** — every released
  Post-UTME offer with the fee as stated now, what is confirmed, the balance and a band (`NOT_PAID`, `PENDING`, `PART_PAID`,
  `SETTLED_IN_PARTS`, `PAID_IN_FULL`); **`finance.intake_fee_monitor(session)`** — every fresher on the register with the
  school-fee state and where they stand at the gate, set-based.

## The API

- `GET /api/v1/applicant/me/admission` — `entitlement` carries the new columns. `GET /api/v1/applicant/me` adds `acceptance`
  `{feeDue, paidTotal, balance, settled, payments, balanceDue, openReference, openAmount, openExpiresAt}`.
- `GET /api/v1/applicant/me/school-fees` — the state, the figures (`due`, `dueFirstSemester`, `paid`, `balance`), the window,
  the open reference, the gate (`enabled`, `clearsOn`, `fromSession`) and `portalState`; `{onRegister: false, state:
  'REGISTER_PENDING'}` before the register. `POST /api/v1/applicant/me/school-fees/references {amount}` draws the student's
  school-fee reference (`finance.new_reference`, its own refusals); `APPLICANT_NOT_ON_REGISTER` without a register row.
- Checkout and verification (`PaymentsService`) accept the applicant token that owns the student for a school-fee reference.
- The student doors (`POST /api/v1/student-auth/continue`, the student sign-in on the admission or JAMB number) refuse
  `STUDENT_PORTAL_HELD_FEES` / `STUDENT_PORTAL_FEES_NOT_AVAILABLE` after the register row is found and before a token is
  issued; `SchoolFeesAccessGate` (an interceptor beside the biodata gate, before it) answers 403 `STUDENT_PORTAL_HELD_FEES` with
  `X-Portal-Access` on every student request but the allowed ones (`/api/v1/me`, notices, notifications, admission documents,
  password, the fee and payment paths), so a session opened before the gate turned, or a direct call, is held too.
- `GET|PUT /api/v1/finance/portal-gate`, `POST /api/v1/finance/portal-gate/exceptions`, `DELETE …/exceptions/{id}` — the gate
  and its exceptions, on Fee Setup.
- `GET /api/v1/admissions/sessions/{s}/{y}/acceptance-fees` (list, `/summary`, `/options`) — the acceptance fee monitor;
  `GET /api/v1/finance/sessions/{s}/{y}/intake-fees` (`/coverage`, `/summary`, list, `/options`) — the school-fee readiness
  monitor; `GET /api/v1/platform/readiness` gains the intake session's fee-schedule check; the Bursar dashboard gains the
  intake's programmes without fees and its cleared freshers.

## The pages

- The applicant's Accept screen and Admission page: **Acceptance fee payment** — the required fee, the amount previously paid,
  the outstanding balance, "PARTIALLY PAID", and **Pay outstanding balance**; the letter only once settled, else the balance
  note. **School fees** (`/applicant/admission#fees`): "<session> school fees not yet available" with the University's words
  and no button; the window's words; the breakdown with the first semester or the full balance to pay through the gateway,
  the open reference to resume, "School fees paid"; and the portal line — the hand-off when cleared, otherwise why not yet.
- The student side: a held student reaching `/student` is sent to `/applicant/admission#fees`.
- Fee Setup: the applicant fees' current figures with the gate panel — the switch, from which session, what clears it, the
  exceptions. `/admissions/acceptance-fees` and `/finance/intake-fees` for the Bursary, Admissions and ICT (menus
  t/acceptancefees, t/intakefees).

## Checks and tests

`db/check.sql` V724 (EXPECTED 550): the revision after a part payment (the balance, one reference at a time closed when the
figure changes, the letter withheld then the same letter, never the whole fee again, every statement kept, the monitor's
bands), and the gate (held while nothing is stated, payable, cleared on the first semester or in full, the exception, never an
earlier cohort or a matriculated student). `AcceptanceBalanceIT`, `PortalFeeGateIT`; `AdmissionLifecycleIT` and
`IntakeJourneyIT` adjusted where the hand-off now waits for the fees.

## Reading the live data

The queries the Bursary can run on the live database to list the affected applicants are in the hand-over note of
11 November 2026: the stated fee and its history (`admissions.applicant_fee`, `applicant_fee_revision`), the applicants who
paid ₦25,000 and owe ₦10,000 (`admissions.acceptance_fee_monitor('2026/2027') WHERE band = 'PART_PAID'`), the configuration
state (`finance.programme_fee_coverage('2026/2027')`) and where each fresher stands (`finance.intake_fee_monitor('2026/2027')`).
