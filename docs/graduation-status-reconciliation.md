# Graduation-status reconciliation: students outside the maximum academic period (V638)

This is the implementation report for the brief *Automatic graduation for students outside current session and spillover limit*
(22 October 2026). Nothing was rebuilt. The cohort engine already counts, for every student, the sessions since the expected
completion against the configured spillover limit; what was missing was the act that turns a student who is past that limit, and
is still kept in study, into a GRADUATED record — controlled, previewed, never repeated, and reversible only by the Registrar.

## 1. What was there, and what V638 adds

| Need in the brief | Existing piece, kept |
|---|---|
| Admission session, cohort, programme length (4, 5 or 6 sessions), deferments, transfers, the Registry's pin | the cohort engine, `people.academic_position` (V331, V475, V595, V598, V612, V628, V634) |
| SP1 and SP2, the configured maximum | `policy.progression_setting.max_spillover_years` (default 2), `spillover_state` up to `SPILLOVER_LIMIT_REACHED` |
| Session sequence, never the calendar year | `policy.academic_session`, `policy.session_after` |
| Recommendation and confidence, completion | the lifecycle desk, `people.lifecycle_recommendation` (V558) |
| GRADUATED with its history | `people.change_status`, `people.status_change`, `records.guard_graduated` (V602) |
| No new school fee, registration or carry-over after graduating | `records.graduation_session` and `finance.closed_for_fees`, the registration draft refusal (V602) |
| Final clearance and the Bursary | the FINAL clearance workflow (V415), `GRADUATION_CLEARANCE_WAITING` to the Bursary and the Students Account Office |
| Notices, audit, statistics | the one outbox (V425), the audit spine, the classification engine (V469) |
| The scheduler | the existing `@Scheduled` jobs and `JobLock` |

V638 adds:

* `people.graduation_candidates` — the students outside the maximum period with their timeline and a confidence for this rule.
* `GRAD-RECON/YYYY/NNNNNN` batches: `people.graduation_reconciliation_batch`, its rows, and `people.graduation_reconciliation`, the
  calculation kept for each graduated student.
* `people.graduation_reconcile` — the one act, run a step at a time by `people.graduation_reconciliation_run`.
* `policy.progression_setting.auto_graduation` (off) and the nightly run when it is on.
* `people.confirm_graduation_date` — the official date confirmed by the Academic Office.
* `records.graduation_session` reads the reconciliation; the cohort engine reads a reconciled graduate as validated; the Registrar's
  `records.correct_graduation` marks the reconciliation corrected.

No status was added: the student becomes GRADUATED. DORMANT, WITHDRAWN, DEFERRED, SUSPENDED, EXPELLED, DECEASED and the other
statuses outside study are never candidates.

## 2. The rule

A student is a candidate when all of these hold:

1. the status is ACTIVE or PROBATION, and the record is not a merged duplicate;
2. the cohort engine has a current session for the record;
3. the sessions since the expected completion are more than the configured maximum.

The expected completion is the engine's: the effective cohort plus the programme's length, moved by approved deferments, or the
later first final-level record, or the Registry's pin. The maximum session permitted is the expected completion plus the maximum
(`policy.session_after`), so with a four-year programme, entry 2018/2019 and two spillover sessions, the student completes in
2021/2022, SP1 is 2022/2023, SP2 is 2023/2024, and from 2024/2025 the student is outside the maximum.

The matriculation number's year is only a signal. When it disagrees with an entry session the engine took from the record itself,
the record reads LOW and is never graduated in bulk.

## 3. Confidence

| Confidence | When | What happens |
|---|---|---|
| HIGH | complete and consistent | graduated by an officer's batch, and by the nightly run when it is on |
| MEDIUM | migrated with gaps the engine resolves: no registration on record, the level on record behind the computed level, the length from the University rule, the matriculation year differs but the cohort was overridden or merged, a carry-over still on the record | graduated only when the officer ticks "include the medium-confidence records" after reading them |
| LOW | conflicting or incomplete: no or invalid entry session, the entry session ahead of the current one, no programme length, a duplicate or missing matriculation number, the matriculation year against an unresolved entry session, a deferment in force, a transfer, swap, inter-university transfer or change of programme pending, a registration or enrolment in the current session, the lifecycle desk reading data incomplete or requires review | left for review; never graduated by a batch |

A student registered at the final level in the current session is not a candidate at all: the engine reads that registration as
the final year, so the expected completion moves to the current session.

## 4. The act

`people.graduation_reconcile(batch, student, reason)` does, for one student, all or nothing:

1. the batch is open and the caller opened it (`GRADRECON_BATCH_OWNER` otherwise);
2. the student is locked; a GRADUATED student is skipped (`SKIPPED`, never changed twice); any other status outside study is refused;
3. the record is revalidated now: still outside the maximum, the confidence still allowed by the batch;
4. a cohort decision is written (rule `GRADUATION_RECONCILIATION`, classification `OUTSIDE_MAXIMUM_PERIOD`);
5. `people.change_status(student, 'GRADUATED', 'Graduation reconciliation GRAD-RECON/…', today, reason)` — the status history;
6. the calculation is kept on `people.graduation_reconciliation`: previous status, matriculation number, entry session, cohort and
   its source, programme, length, final level, current level, deferments, expected completion, maximum, the maximum session, the
   current session, the sessions beyond, the confidence and its reasons, the graduation session, the reason, who and when;
7. the graduation session is the maximum session permitted, a session of the University's own sequence, never a calendar year;
8. final clearance is started where none is under way (a refusal of the clearance engine is recorded, never fatal);
9. the position is recomputed, and the student is told (`STUDENT_GRADUATED_RECONCILED`).

The official graduation date is not today's date. It stays unconfirmed until the Academic Office records it with
`people.confirm_graduation_date` (the date, and the session if it differs). Once a batch is done, the Bursary and the Students
Account Office are told that graduates wait for financial clearance.

Nothing is deleted: registrations, results, the CGPA, payments, school fees, GST and EPS records, the matriculation number, the
admission, programme, faculty, department, transfer and deferment history, documents and clearance records all stay. Results are
never written, and "no result" is never read as a fail.

## 5. After graduating

* **Fees.** `records.graduation_session` now reads the reconciliation where there is no approved award, so
  `finance.closed_for_fees` refuses any normal school-fee charge or reference for a session after the graduation session
  (`SCHOOL_FEES_CLOSED_GRADUATED`). A balance owed for the sessions up to it stays owed and payable.
* **Registration and carry-over.** The registration draft refuses a student not in study (`REG_STUDENT_NOT_ELIGIBLE`).
* **Clearance.** Clearance is not a condition of the status. It starts after it.
* **The record.** Student Full Record shows the reconciliation on the Lifecycle panel: the batch, the reason in figures, the
  graduation session, the official date or that it awaits the Academic Office, the confidence and the status before.
* **Statistics.** Every count reads the status, so the graduate leaves the current population on the next read.

## 6. Correction

The Registrar's correction (`records.correct_graduation`, V602, on a reason and evidence) puts the status back to ACTIVE with its
history. V638 marks the reconciliation corrected with who, when and why, counts it on the batch, and recomputes the position. The
corrected reconciliation is kept, never deleted, and a later reconciliation of the same student is a new row.

## 7. Automatic reconciliation

`policy.progression_setting.auto_graduation` is off. The Directorate of ICT or the Registrar switches it on or off
(`policy.set_auto_graduation`; the database checks the office too). When it is on, the existing scheduler runs
`GraduationReconciliationController.nightly` at 02:50 Lagos time (`moaum.graduation.reconciliation-cron`), under the job lock
`graduation-reconciliation`. The run opens an AUTOMATIC batch of every candidate, graduates HIGH confidence alone in steps, and
closes the batch. It opens nothing when no HIGH-confidence student is outside the maximum, and a student already graduated is never
a candidate, so a second run graduates nobody.

## 8. Who may do what

| Act | Offices |
|---|---|
| Read the figures, the list, a student's review, batches, reports | Academic Office, Registrar, Deputy Registrar, Records, DVC, VC, Dean and HOD (their scope), ICT, Admin |
| Preview, open and run a batch, confirm the official date | Academic Office, Registrar, Deputy Registrar |
| Run a batch | only the officer who opened it |
| Switch the nightly run | Directorate of ICT, Registrar, Deputy Registrar |
| Correct a graduation | Registrar, Deputy Registrar |

Every rule is checked again in the database. A dean of another faculty reading a student gets 404.

## 9. The API (`/api/v1/graduation/reconciliation`)

| Call | What it does |
|---|---|
| `GET /figures?fac&dept&prog` | the cards |
| `GET /candidates?fac&dept&prog&q&confidence&page&size` | the list, names A to Z, paged |
| `GET /students/{id}` | one student's review: the candidate row, the engine's position, the reconciliations, the status history, registrations, deferments, programme history |
| `POST /preview` | nothing written: identified, eligible, requiring review, and each row's verdict |
| `POST /batches` | open a MANUAL batch of the students chosen, or of the whole scope |
| `POST /batches/{year}/{seq}/run` | one step of 100 |
| `POST /batches/{year}/{seq}/close` | close |
| `GET /batches`, `GET /batches/{year}/{seq}` | the batches; one batch with its rows |
| `POST /students/{id}/graduation-date` | the official date and session |
| `GET /report?by=faculty|department|programme|entry|session|spillover|batch` | the reconciled graduates grouped |
| `GET /setting`, `POST /setting` | the nightly run's switch |

## 10. The screen

Graduation Management gains the panel "Students outside the maximum academic period", below the existing figures. ICT now has
Graduation Management under Students, for the switch.

* **Cards:** active students, current session, SP1, SP2, outside maximum period, graduation candidates, graduated (by
  reconciliation and automatically), requires review, data incomplete, eligible now, high and medium confidence. The outside
  maximum, requires review and confidence cards open the list. Every figure comes from the engines.
* **The list:** S/N for display only, the student, programme, admission session, expected completion, maximum session, sessions
  beyond, confidence and why, and Review. It is searchable, filtered by confidence, paged, and exported to Excel and PDF with S/N
  first.
* **MARK AS GRADUATED** acts on the students ticked, and **RECONCILE ACADEMIC STATUS** on the whole scope. Both preview first,
  saying "N students identified outside the maximum academic period. M eligible for automatic graduation. K require manual
  review." The officer can include the medium-confidence records, and has CANCEL, VIEW REVIEW LIST and CONFIRM GRADUATION.
  Progress shows step by step.
* **Review:** the timeline, the confidence and its reasons, the reconciliation, and the official date form.
* **Batches** and **Reconciled graduates**, the report, with Excel and PDF.

## 11. On the live-shaped copy (19 Oct 2026 snapshot, current session 2025/2026, maximum two sessions)

The live-shaped copy predates V578, so `people.graduation_candidates` and the figures were created on it inside a transaction
with empty stand-ins for the later tables, timed, and rolled back:

| Read | Time |
|---|---|
| every candidate (5,078 students outside the maximum) | 0.27 s |
| the figures for the University | 0.45 s |
| one student revalidated, in a loop | 23 ms |

All 5,078 read MEDIUM. On that copy, 4,657 have no registration on the new portal, and most of them show 100 Level on record
against a computed 400, 500 or 600. None would be graduated by the nightly run. The Academic Office reads them and includes the
medium-confidence records in a batch.

## 12. Tests

* `check.sql` V638 — the rule in the database alone, undone at the end. It covers HIGH, MEDIUM and LOW (a deferment in force); a
  student registered at the final level this session and one within the length are not candidates; the batch is run by its opener
  only; two graduated with history, notice, the reconciliation row, the graduation session at the maximum, closed to fees after
  it and not for it, the registration draft refused, and the engine reading the record validated; never twice; the report; the
  official date; the nightly batch refused while off and HIGH-only when on; and the Registrar's correction recorded.
* `GraduationReconciliationIT` — the same over the API, with ICT refused the act, a dean of another faculty refused the student,
  the Full Record carrying the reconciliation, the switch for ICT and not for the Academic Office, and the nightly run doing
  nothing while off.
* `lib/graduation-reconciliation.test.ts` — the confirmation words, the timeline, the reasons, the batch reference and the outcomes.
