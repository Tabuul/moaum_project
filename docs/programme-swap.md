# Programme swap (V578, V633)

*20 Oct 2026; one officer since 22 Oct 2026 (V633).* Students who changed programme before or during the migration from the old portal arrived under the programme
they had left, so the register, the statistics, the fee lines and the class lists still read them in the old department. The
programme swap is the office's correction of a student's **current** placement — faculty, department, programme and level —
with the old placement kept. **Academic Office → Programme Swap** and **Director of ICT → Programme Swap** (`/programme-swap`);
the Registrar, the Deputy Registrar and the Super Administrator have it too.

It is not a transfer (the student's own application, with a fee, both departments, the Registry and the Senate — V070), not the
record move (a postgraduate record off an undergraduate programme — V548), and not a new admission. It changes
`people.student.programme_code` and `current_level` and nothing else.

## How it works

1. **Mismatches.** `people.programme_mismatches` reads the live register and flags the records whose placement looks wrong,
   from what the record itself says:
   - the department segment of the matriculation number (`MOAU/SC/CSC/26/12345` → `CSC`) against the programme's
     (`ref.programme.matric_code`, or the segment most of that programme's own students carry);
   - the department that owns most of the courses on the latest approved registration against the programme's department;
   - the programme the JAMB candidate was admitted to against the current one.

   Two signals agreeing on another department: **CONFIRMED**. One: **POSSIBLE**. Two that disagree: **REQUIRES REVIEW**. Nothing
   is changed by a finding. An officer records what they made of it (`people.programme_mismatch_review`: under review,
   confirmed, requires documentation, no action required); a swap sets *swap required* and *swapped*. The detector reads the
   whole register in a few seconds, so the desk reads it through the figure cache (five minutes) with **Run the detector again**.

2. **Check.** `people.programme_swap_check(student, programme, level, session)` says, before anything is written, what the
   swap would do and what stands in its way. Refused: a record that is not live; a programme not on the register or archived; a
   programme of another category (a postgraduate record onto a postgraduate programme is the V548 record move); a level the
   programme does not have (`people.programme_levels`); a session the University does not have; a transfer under way; a swap
   already pending; a change of programme requested at the admission desk; the same placement. To look at (the deciding officer
   sees them): a level below one the student has an approved registration at; a level the cohort engine reads differently; a
   jump of more than a year; a change of faculty; the CCE route. Also shown: the session's fee lines under each programme (nothing
   charged), and the session's registered courses the new programme does not offer and its core courses not registered.

3. **Make the swap.** `people.prepare_programme_swap` — the Academic Office, the Registry, the Director of ICT or super, with the
   kind (legacy migration correction, programme correction, academic transfer recorded) and a reason of ten characters or more.
   The check must pass. The swap gets a reference `PSW/YYYY/NNNNNN` and is decided at once by the same officer (V633, the
   University's word of 22 October 2026: no second level of approval — the officer who initiates the swap moves the student):
   the check runs again on the record as it stands, the programme and level are set, the student row before and after and the
   registration impact are kept on the swap, the finding reads *swapped*, and the student is told (`PROGRAMME_SWAP_COMPLETED`:
   the new placement and whom to ask, no migration detail). The swap is `COMPLETED` when the call returns, with the officer as
   its preparer and its decider. Evidence (PDF, JPEG, PNG up to 5 MB) is kept with the swap, before or after it is made, in the
   file store where there is one. **Bulk:** many students onto one programme and level, each checked and made on its own, at
   once; those refused are listed with the reason.

4. **A swap left pending from before V633.** `people.decide_programme_swap` — approved and executed at once, or rejected with a
   note — by any officer who may make a swap, the one who prepared it included (the two-officer rule and the constraint
   `ck_programme_swap_other_officer` are gone; the Director of ICT decides any kind). The check runs again on the record as it
   stands: a record that changed since fails the swap (`FAILED`, nothing written; make it again). The officer who prepared it,
   the Academic Office or the Registry cancels it while pending. A batch of such swaps is decided at once or swap by swap.

## What stays

The matriculation number (immutable by trigger), the JAMB and admission numbers, the account, the registrations and their
courses, the results, the payments and receipts, the documents and the support history keep their rows. The cohort position
refreshes by its own trigger. The register, the statistics, the query engine, the class lists, the fee lines and the examination
card read the new placement because they read `people.student`. The registration is never pruned: the Academic Office reviews
it with the impact the swap recorded.

## Where the old placement shows

`people.programme_history(student)` reads every placement a record has had — the original admission (the candidate's programme,
or the programme the record held before its first recorded move), transfers effected, record moves, swaps completed, and any
other change of programme the audit chain holds — oldest first, the current one marked. The full record (Student 360°) shows it
on the Admission tab, with the original admission programme on the Overview where the record has moved since; the swap desk
shows it on every student and every swap. The swap report (Swaps tab) filters by old programme, so a student is found under the
programme they left.

## API

`/api/v1/programme-swaps`: `GET /summary`, `GET /mismatches` (scope, class, review, q, level, status, page), `POST
/mismatches/{student}/review`, `GET /structure`, `GET /students/{id}`, `POST /check`, `POST /` (prepare), `POST /bulk`, `GET /`
(filters: status, session, fac, dept, from, to, level, kind, fromDate, toDate, q), `GET /{id}`, `POST /{id}/evidence`, `GET
/{id}/evidence/{e}`, `POST /{id}/decide`, `POST /{id}/cancel`, `POST /batches/{batch}/decide`. Every student named is held to the
office's bound (`StudentReach`); a Head of Department or Dean elsewhere, and a student, are refused.

## Tests

`ProgrammeSwapIT`, `TransferBatchIT`; `lib/programme-swap.test.ts`; check.sql V578 and V587 (as V633 has them), V633.
