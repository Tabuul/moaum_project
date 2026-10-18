# Student lifecycle reconciliation: graduation candidates, spillover and the maximum (V558)

The cohort engine (V331, restated by V463) already works out where every student stands: the effective cohort, the
programme's length, the expected completion, the sessions beyond it, and a classification with the rule and its
confidence. What it lacked was a controlled way to act on thousands of students at once without changing anybody
just because a calculation says so. V558 adds that layer. It does not add a second classification, a second graduation
system or a second statistics engine, and it never writes a matriculation number, a result, a registration or a payment.

This document is the implementation report for the brief *Student Academic Lifecycle, Graduation & Spillover
Reconciliation*.

## 1. What was there, and what V558 adds

| Need | Existing piece (kept, not rebuilt) | V558 |
|---|---|---|
| Cohort, length, expected completion, spillover years, merged sessions, deferments | `people.academic_position` from `people.academic_position_rows_of` (V331, V463), refreshed by triggers | read as it is |
| Spillover limit | `policy.progression_setting.max_spillover_years` (2) | read as it is |
| Programme length | `ref.programme.final_level` / `duration_years`, `finance.final_level`, the CCE route terms | the source is shown: programme, CCE route or University rule |
| Status changes with history | `people.change_status` → `people.status_change` | used for DORMANT / WITHDRAWN only |
| Decisions with the batch | `people.cohort_decision` | one row per reconciliation and per correction |
| Level raised, never lowered | `people.apply_level_corrections` (V475) | the same rule for a confirmed spillover |
| Graduation list and audit | `records.graduand`, `GraduationService` | `GraduationService.placeOnList` audits one student exactly as `audit(session)` does |
| Published results and courses owed | `assessment.student_results`, `registration.carryovers` | the completion check |
| Office scope | `OfficeScope.bound(...)` | every read and every act, and again in the database |

## 2. The completion check

`people.lifecycle_completion` holds, for each active student at or beyond the programme's length (the final year, or
spillover), what they have completed:

| Completion | Meaning |
|---|---|
| `COMPLETED` | every registered course passed and published, up to the programme's final level |
| `OUTSTANDING_COURSES` | a failed course not yet passed (`registration.carryovers`) |
| `AWAITING_RESULT` | a registered course with no published result — never read as a failure |
| `FINAL_LEVEL_NOT_REACHED` | registered only below the final level |
| `NO_PUBLISHED_RESULT` | nothing published to judge by |

It is checked on demand ("Refresh analysis", 1,000 students a step; the whole University on the live-shaped copy is
19,291 students in about 50 seconds) and again for each student at the moment they are reconciled. When it was last
checked is shown.

## 3. The recommendation

`people.lifecycle_recommendation` covers every ACTIVE or PROBATION student the engine has not already settled (a
graduated student, a Senate-approved award and every other official status stay out of it). The rules, in order:

1. Already audited onto the graduation list with nothing unmet (engine rule R5) → `ON_GRADUATION_LIST`.
2. No current session, no entry session, an entry session not on the calendar, or no programme length → `DATA_INCOMPLETE`.
   A length is never invented.
3. Too thin to judge (R6: no registration ever, within the length), an entry session after the current one, or a
   matriculation number another student holds → `REQUIRES_REVIEW`.
4. Beyond the length with everything completed → `GRADUATION_CANDIDATE` (basis `COMPLETED_BEYOND_LENGTH`).
5. Beyond the spillover limit → `MAXIMUM_SPILLOVER_REACHED`.
6. One, two … sessions beyond the length → `SPILLOVER_YEAR_1`, `SPILLOVER_YEAR_2` ….
7. Expected to complete in the current session → `GRADUATION_CANDIDATE` (basis `FINAL_YEAR`).
8. Otherwise → `WITHIN_NORMAL_DURATION`.

Only the CURRENT session counts: a planned next session moves nobody further into spillover (tested). The cohort is the
entry session — or the session it was merged into, or the cohort the Registry set — never the matriculation number
alone.

**Confidence** is HIGH, MEDIUM or LOW, with the reasons written out:

* LOW — no course registration on record; the matriculation number's year differs from the entry session; no
  matriculation number; the level on record differs from the computed level within the length; or a record to review or
  correct.
* HIGH — registered or enrolled for the current session, and the programme's length set on the programme (or the CCE
  route).
* MEDIUM — everything else (registered before but not this session; the length from the University rule).

**The explanation** is written from the record, the same way every time, for example: *Entry session 2018/2019;
programme length 4 sessions to 400 Level; expected to complete in 2021/2022; current session 2025/2026; 4 sessions beyond
the programme's length (the limit is 2); last registered 2022/2023; 1 course still owed (GST 222).*

## 4. Review, preview, batch, reconcile, correct

| Step | What happens | Who |
|---|---|---|
| Review | `people.lifecycle_mark`: under review, verified, rejected or requires correction (a note for the last two), or back to pending. Kept for the session and the recommendation it was made on; when either changes the student is pending again. Only graduation candidates, spillover and the maximum are verified; a **low-confidence record is verified one at a time**, never in a group. | Academic Office, Registrar, Deputy Registrar, Records |
| Preview | `POST /preview` writes nothing: how many will be reconciled, what happens to each kind, the levels raised, who is already on the graduation list, the status changes, and who is left out and why. "You are about to reconcile 1,240 student records." | the same |
| Batch | `people.lifecycle_open_batch` issues `RECON/YYYY/NNNNNN` for the officer, with a description and the scope. | the same |
| Reconcile | 200 students a step, each all or nothing in its own savepoint: locked, the position and completion brought up to date, the recommendation compared with the one verified (a changed one is left out with the reason), never twice in a session. | the same |
| Correct | `people.lifecycle_correct`, one or a whole batch, on a reason: the status changed back (refused if it has moved since), a level it raised put back where nobody has changed it since, a graduation-list entry it added removed while the Senate has not acted (refused otherwise). The reconciliation stays, marked corrected; the student is under review again. | the same |

What reconciling does, by recommendation:

| Recommendation | Outcome | Status | Level |
|---|---|---|---|
| Spillover year 1, 2 … | `SPILLOVER_CONFIRMED` | stays ACTIVE (or PROBATION) | raised to the programme's final level where lower; never lowered |
| Maximum spillover reached | the officer chooses: `KEPT_ACTIVE_LIMIT_REACHED`, or `STATUS_CHANGED` to DORMANT or WITHDRAWN — never by default, never GRADUATED | kept, or changed through `people.change_status` with the reason | raised when kept active |
| Graduation candidate | `GRADUATION_LIST`: the student is put on the current session's graduation list and audited exactly as the Graduation screen's audit does (`GraduationService.placeOnList`); an entry already there is audited again, not duplicated | stays ACTIVE — the Senate approves the award, and nobody becomes GRADUATED here (a database constraint refuses it) | raised to the final level where lower |

Each reconciliation writes a `people.cohort_decision` (rule `LIFECYCLE_<recommendation>`, the batch, the officer, the
levels before and after) and a `people.lifecycle_reconciliation` with the recommendation, confidence, completion and
explanation as they stood. A later recommendation never rewrites it.

## 5. Who may do what

* **Read** (within the office's scope, enforced on the server): Academic Office, Registrar, Deputy Registrar, Records,
  DVC, VC, Deans, Heads of Department, Faculty Officers, ICT, Administrator, Super Administrator. A Head of Department sees
  only their department's students, batches counted within it, and gets 404 for a student outside it.
* **Review, reconcile, correct**: Academic Office, Registrar, Deputy Registrar, Records — checked by `@PreAuthorize` and
  again in the database (`LIFECYCLE_OFFICE`, `LIFECYCLE_SCOPE`). ICT reads and supports; it does not approve a standing.
* A batch is reconciled by the officer who opened it (`LIFECYCLE_BATCH_OWNER`).

## 6. The API (`/api/v1/cohorts/lifecycle`)

| Method | Path | Does |
|---|---|---|
| GET | `/summary` | figures by recommendation (with confidence and review state), completion, cohort, faculty, department, programme; last checked and computed |
| GET | `/students` | the students behind a figure, paged, names A–Z; filters `rec` (`SPILLOVER` = any year), `state`, `conf`, `basis`, `completion`, `cohort`, `entry`, `matricYear`, `level`, `status`, `batch`, `fac`, `dept`, `prog`, `q` |
| GET | `/students/{id}` | one student's recommendation, explanation and every reconciliation |
| POST | `/refresh` | the next 1,000 students' completion checked (`after`, scope) |
| POST | `/mark` | review states for chosen students or a whole filter (at most 5,000) |
| POST | `/preview` | what a batch would do, nothing written |
| POST | `/batches` | a batch opened |
| POST | `/batches/{year}/{seq}/reconcile` | one step of up to 200 students; the ones left out with their reasons |
| POST | `/batches/{year}/{seq}/close` | the batch closed |
| GET | `/batches`, `/history` | the batches with what each did; every reconciliation (batch, outcome, corrected), names A–Z |
| POST | `/reconciliations/{id}/correct`, `/batches/{year}/{seq}/correct` | corrections |

## 7. The screen

Student Cohorts → **Reconciliation** (`/cohorts?tab=lifecycle`):

* **Figures** — graduation candidates (final year / completed beyond the length), spillover year 1 and 2, the maximum,
  requires review, data incomplete, on the graduation list, within normal duration; pending, verified, reconciled,
  requires correction; a cohort table and a faculty → department → programme drill-down. Every count opens its students.
  The completion panel shows what was checked and when, with "Refresh analysis".
* **Students** — filters, ticking or "Choose all", Under review / Verify / Requires correction / Reject / Back to pending,
  Reconcile… (preview, the choice at the maximum, description and reason, progress, then the students left out with an
  Excel of them); Explain shows the explanation, the confidence reasons, the completion and the student's reconciliations
  with Correct…; Excel and PDF of the whole filtered list, S/N first, names A–Z.
* **Batches and history** — every batch with what it did and "Correct the batch…"; the history with Correct… per row;
  Excel and PDF.

The Overview's "Expected to complete" figure now opens the final-year graduation candidates.

## 8. On the live-shaped copy (18 Oct 2026, current session 2025/2026)

| Recommendation | Students | High | Medium | Low |
|---|---|---|---|---|
| Graduation candidate | 6,261 (6,220 final year, 41 completed beyond the length) | 5,949 | 69 | 243 |
| Spillover year 1 | 2,039 | 1,742 | 207 | 90 |
| Spillover year 2 | 5,543 | 149 | 4,535 | 859 |
| Maximum spillover reached | 5,448 | 15 | 776 | 4,657 |
| Requires review | 9,459 | | | 9,459 |
| Data incomplete | 3,448 | | | 3,448 |
| Within normal duration | 16,122 | | | |

Completion of the 19,291 at or beyond the length: 18,184 no published result on the portal (the old results are not
loaded), 460 courses outstanding, 324 result awaited, 280 final level not reached, 43 completed. The low-confidence
maximum-spillover students (4,657) have no course registration on record at all; they are verified one at a time.

Timings on the copy: figures for the whole University 1.8 s, within a faculty 0.8 s; a department's list 0.1 s after
the scoped read was restructured (0.9 s before); 1,742 spillover-year-1 records verified in one act in 2.9 s, their
preview in 1.0 s, and a reconciliation step of 200 in 6.5 s (well inside the 30-second limit in front of the API).

## 9. Tests

* `LifecycleReconciliationIT` — the whole path over the API with a current session made for the test (and put back):
  recommendations and explanation; a planned session moves nobody; scope for a Head of Department elsewhere; only the
  Registry acts (ICT and HOD 403); a note required to reject; bulk verify holds back the low-confidence record, which is
  then verified on its own; the preview writes nothing and needs the choice at the maximum; a batch whose student changed
  after verification leaves them out (`LIFECYCLE_CHANGED`); another officer cannot use the batch; spillover confirmed with
  the level raised and the decision recorded; the maximum kept ACTIVE, and in a second batch made DORMANT with the status
  history; the final-year student on the graduation list (audited, AWAITING) and still ACTIVE; never twice; no
  matriculation number moved; history and batches; corrections put the status, level and list entry back, once.
* `check.sql` V558 — the same properties in the database alone, undone at the end.
* `lib/lifecycle.test.ts` — the words, the confirmation sentence, the steps, the batch reference, the cross-tabs.
