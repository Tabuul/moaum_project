# Graduation management: graduated students reconciled in batches, and the graduated record closed (V602)

This is the implementation report for the brief *Graduated student reconciliation, academic graduation status, Bursary
clearance & post-graduation financial lock* (21 October 2026). Nothing was rebuilt: the brief's pieces existed, and V602 adds
the one layer that was missing — the Academic Office's controlled act of marking chosen students GRADUATED, previewed and
batched — and closes the graduated record to new school fees and course registration everywhere it could still be charged or
registered.

## 1. What was there

| Need in the brief | Existing piece, kept |
|---|---|
| Student status, GRADUATED as a terminal status with history | `people.student.status` (ADMITTED … GRADUATED … DECEASED), `people.change_status` on an instrument, `people.status_change` (V286) |
| Programme duration, final normal level (400 / 500 / 600) | `ref.programme.final_level` / `duration_years`, `records.final_level_of`, the CCE route terms; five-year programmes at 500 since V598 |
| Year of entry, matriculation year, cohort, SP1/SP2, deferments, programme changes | the cohort engine, `people.academic_position` (V331, V475, V595, V598) |
| Graduation eligibility — results published, CGPA, required coursework | the degree audit (`GraduationService.audit`, `records.graduand`, V029/V493) |
| Carry-overs, outstanding results, completion | `people.lifecycle_completion` from `registration.carryovers` and `assessment.student_results` (V558) |
| Recommendation, confidence, review, RECON batches, placing candidates on the list | the lifecycle reconciliation, Student Cohorts → Reconciliation (V558) |
| Senate approval → GRADUATED | `records.approve_awards` on the Graduation screen (V029) |
| Clearance by office, applicability, audit, certificates, the student's view | the clearance engine: the FINAL workflow (purpose CONVOCATION) with its eight units — Bursary first, clearing against `finance.position` — hostel only where ever allocated, overrides by a senior officer, documents, reminders, verification (V013, V415) |
| Bursary's workspace | Bursary → Financial Clearance (`/clearance`, workflow FINAL) |
| Statistics and query keep GRADUATED out of the current population | the student classification engine, `StudentQueryService.ENDED` (V469) |
| Full record | Student 360° (overview, clearance, documents, payments, results) |
| Notifications | the one outbox, `platform.notify` and templates (V425) |
| RBAC | office authorities on every endpoint, `OfficeScope` bounds |

What was missing: a way to graduate *chosen* students rather than a session's whole list at once, with a preview that says who is
eligible and why not; a reference for that act; the lock on the graduated record (a graduated student was still charged the fee
lines of later sessions, could still draw a school-fee reference, and the database would still make a registration draft for
them); a controlled reversal; the Bursary told; the graduation session, batch and clearance as query filters and on the record.

## 2. The batch

`records.graduation_batch` (GRAD/YYYY/NNNNNN; the session the awards are confirmed for, the Senate minute, what the batch is for, the
filters as words, the counts, who and when) and `records.graduation_batch_row` (each student's verdict, confidence, reason and
what the execution did). Both on the audit spine.

1. **Reconcile** (`POST /api/v1/graduation/batches/preview`) — the students a filter names within the office's bound (year of
   entry or entry session, current level, status, a number or a name; faculty, department, programme from the scope bar; or
   chosen ids; at most 5,000), each with a verdict. Nothing is written.
2. **Confirm** (`POST /api/v1/graduation/batches`) — the batch opened on the minute and the reason; the verdicts stored as they
   stand.
3. **Execute** (`POST /batches/{year}/{seq}/execute`, 200 students a step, by the officer who opened it) — each eligible student
   placed on the session's list by the degree audit (`GraduationService.placeOnList`, as the lifecycle reconciliation does) and
   graduated by `records.graduate_one`, all or nothing in its own transaction; a refusal is written on the row with its code.
   When nothing is left the batch is stamped executed and the Bursary and the Students Account Office are told
   (`GRADUATION_CLEARANCE_WAITING`).
4. **Close**, **list**, **detail** (`/batches`, `/batches/{year}/{seq}`), **verdict** of one student (`/students/{id}/verdict`).

Who: the Academic Office, the Registrar and the Deputy Registrar (`BATCHERS`); readers as for the graduation list.

## 3. The verdict

`records.graduation_verdict(student, session)` reads the register, the cohort engine's position and recommendation, the lifecycle
completion check (computed fresh for the student) and the session's list entry; the API adds the degree audit's own judgement
(every registered course published, the CGPA threshold or a postgraduate's required coursework) for the eligible.

| Verdict | Read from |
|---|---|
| `ALREADY_GRADUATED` | status GRADUATED |
| `DEFERRED`, `SUSPENDED` (suspended, rusticated), `WITHDRAWN` (withdrawn, voluntary withdrawal, transferred out), `DISCONTINUED` (expelled, dormant), `NOT_ELIGIBLE_STATUS` | the official status — never graduated by a batch |
| `REFERRED_BY_SENATE` | the list entry referred |
| `CARRY_OVER` | completion OUTSTANDING_COURSES (`registration.carryovers`) |
| `OUTSTANDING_RESULT` | completion AWAITING_RESULT |
| `NOT_FINAL_LEVEL` | registered only below the final level |
| `NO_RESULT` | nothing published on the record |
| `REQUIREMENT_UNMET` | the list entry's unmet requirement, or the degree audit's (CGPA below the threshold, coursework) |
| `DATA_INCOMPLETE` | no entry session, or the programme's final level not recorded |
| `REQUIRES_REVIEW` | the lifecycle desk's REQUIRES_REVIEW, or a LOW-confidence record — unless the Registry verified it on the lifecycle desk |
| `ELIGIBLE` | everything above passed |

Confidence is the lifecycle desk's where it judged the student (its own DATA_INCOMPLETE — no current session, say — is the
University's, not the student's, and is set aside), else HIGH for a complete record on the engine, LOW where the entry session or
final level is missing, MEDIUM otherwise. A LOW-confidence record is never graduated in bulk: it reads REQUIRES_REVIEW until
verified on its own on the lifecycle desk (V558), as the brief asks. Matriculation year is a signal the cohort engine already
weighs; it never graduates anyone by itself.

## 4. The one act: `records.graduate_one`

Revalidated in the database before anything changes: the student in study (ACTIVE or PROBATION; a GRADUATED student returns
`ALREADY_GRADUATED` and is never graduated twice), on the session's list with nothing unmet and a CGPA (or already Senate-approved),
not referred, no carry-over owed, no result awaited, a minute cited. Then: the list entry approved with the minute, the batch, the
moment, the officer, the final level, the programme's length and the spillover state the student graduated from (the SP1 → graduated
and SP2 → graduated figures); `people.change_status(… 'GRADUATED', minute …)` with its history and its notice; final clearance
started where none is under way (`clearance.start('FINAL', …, 'ELIGIBLE')` — the Bursary's stage first); the student told on
`STUDENT_GRADUATED` (award, programme, faculty, department, minute, session, matriculation number, clearance; no financial
detail). `records.approve_awards` — the Graduation screen's "Approve the awards" for a whole session — now graduates each
audited graduand by this same act, so both doors behave alike.

## 5. The lock

- `finance.closed_for_fees(student, session)`: a GRADUATED record owes nothing for a session after its graduation session
  (`records.graduation_session`: the approved list entry's, else the last session the record shows the student in study).
  `finance.charges_as` — which every figure of what a student owes reads (`finance.charges`, `finance.position`, the readiness,
  the fee report, the Bursary's clearance evidence) — returns no line for such a session, so no fee, late fee or late-registration
  fee is generated for it on any path (there are no invoices in this portal; what is owed is computed from the stated lines).
  `finance.new_reference` refuses a school-fee reference for such a session with
  `SCHOOL_FEES_CLOSED_GRADUATED: This academic record has been marked as graduated. New school-fee payments are not available
  for this academic enrollment.` — before any reference or gateway call. Sessions up to graduation keep their history and may
  still be settled; transcript, certificate and every other purpose payment (`finance.new_purpose_reference`) is untouched.
- `registration.student_draft` refuses a graduated record (`REG_STUDENT_NOT_ELIGIBLE: Course registration is unavailable because
  this academic record has been graduated.`; V604 — V602 had refused every status outside study, which broke the deferment
  engine's own draft for the semester a deferment leaves open; a deferred, suspended or dormant student is judged at the
  student's doors in the API as before), so no path — the student's save, add, add-other, submit, ICT Support's add — makes a
  registration or a carry-over entry for a graduated record. The API's register view for a graduated student says `closed` with
  the words, sends no menu and no carry-over (`outstanding` empty), and reads the semester's registration, if any, as history; the
  course search is refused the same way. The student's screens read "You have graduated" with the history, Documents and
  Graduation & clearance; "Pay now" and "Register courses" are not offered.
- Historical registrations, results, payments, receipts, refunds, swaps, NELFUND and e-wallet records, clearance and level history
  are untouched: graduation changes the current status, never the record.

## 6. The correction

GRADUATED is permanent on the register: `records.guard_graduated` refuses any change of status away from GRADUATED except inside
`records.correct_graduation(student, reason, evidence)` — the Registrar's or Deputy Registrar's act (`POST
/api/v1/graduation/students/{id}/correct`), on a reason of at least ten characters and the evidence (the minute, the letter, the
decision), refused while a degree certificate stands unrevoked. It puts the status back to ACTIVE through `people.change_status`
(history and notice), returns the list entry to awaiting with the correction as its unmet requirement — approved again only after the degree audit has run again, never by the next batch or whole-list approval blindly (the minute and the batch kept as history) — and records the impact — documents issued, transcript
requests, the final clearance's state — in `records.graduation_correction`.

## 7. Multiple enrolments

A person admitted again (a graduate of a first degree admitted to a postgraduate programme, say) holds a second student record with
its own number, its own status and its own sign-in (V429: one record per candidature). Graduating the first record locks that
record only; the second is ACTIVE and its portal, fees and registration are untouched. Nothing is done to the person's account.

## 8. Screens and reports

- **Academic Office / Registry → Graduation Management** (`/graduation/manage`): the figures — students reviewed, graduation
  eligible (by confidence), already graduated in the session, not eligible (SP1, SP2, at the limit), carry-over, outstanding
  result, deferred, requires review, data incomplete, on the list (met / unmet / referred), awards approved, clearance pending and
  completed — with links to the lifecycle desk, the Graduation screen, the Student Query (graduated students of the session) and
  the final clearance desk; **Graduation batch** (filter → RECONCILE GRADUATION STATUS → the verdicts with confidence and reason,
  the tally, the sentence "You are about to confirm the award of N students…" → the minute and the reason → CONFIRM & GRADUATE →
  progress → the batch's rows and outcomes); **Batches** (state, counts, Open); the Registrar's **Correct…** on a graduated row;
  **Graduation reports** by faculty, department, programme, year of entry, matriculation year, graduation session or the spillover
  state graduated from — graduated, from SP1, from SP2, cleared, clearance pending, not started, by batch — as Excel and PDF with
  S/N first and the University heading.
- **Student Query** gains *Graduation session* and *Graduation batch* beside *Graduation*; **Student 360°**'s overview names the
  batch, the final level, the length and the spillover state graduated from beside the session and the Senate state.
- **Bursary → Financial Clearance** is the Bursary's graduation clearance workspace (unchanged): the FINAL workflow's processes of
  the session, the student's sessions with what was stated, paid and outstanding, cleared or not cleared with a reason, never a
  payment deleted; the batch tells the office.

## 9. Tests

- `GraduationBatchIT` — the preview's verdicts and that it writes nothing; ICT refused a batch; a batch without a minute refused;
  the batch executed by its officer only, graduating the eligible student (status, history, list entry with the batch and the
  final level, final clearance, the notice) and leaving the other two with their reasons; executed again graduates nobody twice;
  the later session charges nothing, a reference and a registration are refused, the register view closed with no menu and no
  carry-over, the search refused, the old registration and the results readable; the report; the verdict after; the correction
  (refused to the Academic Office, a short reason refused) with the impact and the list entry awaiting a fresh audit, after which the later session is charged again.
- `check.sql` V602 — the same in the database alone, with `records.approve_awards` graduating by the same act, the plain status
  change refused (`GRAD_PERMANENT`), and the tally; undone at the end.
- `lib/graduation-batch.test.ts` — the words, the tally, the confirmation sentence, the batch reference, the batch's state.

## 10. Not built, and why

- A second status such as GRADUATION_ELIGIBLE or ALUMNI: eligibility is computed (the verdict, the lifecycle recommendation); the
  Alumni stage of the final clearance and `clearance.alumni_profile` already hold alumni membership beside the academic status.
- A graduation-eligibility service of its own: the degree audit and the lifecycle completion check are the eligibility engine; the
  verdict reads them.
- Office clearance workspaces: every unit's desk exists on the clearance engine.

## 11. Students outside the maximum academic period (V638)

A student still kept in study after the programme's length plus the permitted spillover is graduated by status reconciliation,
not by a batch on the Senate's minute: GRAD-RECON/YYYY/NNNNNN batches on the same screen, the graduation session the last session
permitted, the same lock on fees and registration from the session after it, and the same correction by the Registrar. See
[graduation-status-reconciliation.md](graduation-status-reconciliation.md).
