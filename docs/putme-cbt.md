# Post-UTME CBT on the one engine (V385)

The Post-UTME examination is sat on the University's CBT engine (V322–V376): the same tables, functions, question bank,
timer, monitoring, moderation and result workflow that examine GST, EPS, every CBT course and JUPEB. Nothing was
rebuilt. What V385 adds is a third kind of candidate, a controlled public door, two windows of the Director of ICT, and
the road the score takes from the engine to the admission.

## What is reused and what was added

| Area | Reused | Added by V385 |
|---|---|---|
| Engine | `assessment.cbt_exam / cbt_attempt / cbt_answer / cbt_event / cbt_result`, `cbt_start`, `cbt_touch`, `cbt_save_answers`, `cbt_record_events`, `cbt_finalize`, `cbt_sweep`, sittings, invigilation, key corrections, item analysis | office `POST_UTME`; `cbt_exam.putme_session` (the admission session examined) and `putme_verify` (the second factor at the door); `cbt_attempt.application_id` beside `student_id` and `jupeb_application_id` (`candidate_id` is whichever it is) |
| Question bank | `assessment.question`, versions, moderation, import from a spreadsheet, images, formulas | `question.putme_session`: a bank per admission session, named `PUTME:<session>` (`/ict/question-bank`); moderated question by question (no sampling); authored and moderated by the Directorate of ICT, never by the setter (`CBT_MODERATE_OWN` holds) |
| Candidates | `admissions.application` / `candidate` / `applicant_account` (V021), V260's `putme_eligibility` | no new candidate table; `cbt_candidates`, the monitor counts and the office summary list the session's submitted applicants |
| Eligibility | `admissions.putme_eligibility` (the programme screened by examination, the fee confirmed, the application submitted, not disqualified) | `assessment.cbt_putme_eligibility`: plus the Director's `POST_UTME_CBT` window, not already scored, the paper ready, the examination window, the attempt limit — judged at `cbt_start`, never by a page |
| Windows | `policy.portal_window`, `window_act`, `window_state`, the Application Registration Control screen | `POST_UTME_CBT` and `POST_UTME_RESULT_CHECKING`: session-wide, no semester, no late period, **closed until first opened**, with their own closure messages |
| Door | the throttle (V359), the token issuer, `platform.session` | `/post-utme/cbt`: JAMB registration number + the examination's second factor → a 6-hour session of the office `putmecbt`, whose token opens the examination and **no dashboard** |
| Room | `ExamRoom` (fullscreen, server clock, autosave, detectors, camera consent, images) | the same room at `/post-utme/cbt/room/[attempt]` behind `/api/v1/putme/cbt/*` |
| Results | `cbt_results_action` review → approve | `publish` **refused** for `POST_UTME`; `score_on_submit` refused; the examination door's `result` refused |
| Score file | branded spreadsheets | `admissions.putme_score_export` (+ `_row`, `_import`, `_history`): generated from approved results only, with a reference `PUTME-SCORE-<year>-<n>` and a SHA-256; sent through the portal; received, downloaded, previewed, imported |
| Admission | `admissions.application.screening_score`, `release_scores`, the merit list, the eligibility engine, the template | nothing changed: the import writes the same column the Academic Office's upload always wrote |

## The second factor

`cbt_exam.putme_verify` (set on the examination; the public page says which to enter):

| Value | What the candidate enters | Where it comes from |
|---|---|---|
| `APPLICATION_NO` (default) | the application number | `admissions.application.application_no` |
| `SLIP_TOKEN` | the code on the screening slip | `admissions.application.putme_token` (V260) |
| `PHONE` | the phone registered with (last 10 digits compared) | `admissions.applicant_account.phone` |
| `DATE_OF_BIRTH` | yyyy-mm-dd | the `DATE_OF_BIRTH` attachment the Academic Office uploaded (`payload.dob`) |

`admissions.putme_cbt_verify(session, jamb, proof)` returns the application or NULL — never which of the two was wrong.
The API answers every failure with the same words ("Candidate verification failed.") and counts it against the connection
(`Throttle.Door.APPLICANT_LOOKUP`; the result check uses `VERIFY`).

## The candidate's way

1. `/post-utme/cbt` — closed message while the Director's window is not open; otherwise the form.
2. Verify → the server shows name, JAMB number, application number, programme, the examination, its rules and the
   instructions; the candidate confirms and starts.
3. The room: the server's clock (`ends_at` on the attempt), autosave with the unsaved kept on the device (V372), the
   detectors the examination names, a second screen refused or recorded by the examination's `second_session`.
4. Submit → "EXAM SUBMITTED SUCCESSFULLY. Your result will be processed and released by the University." No score,
   no key, no percentage anywhere in the answer.
5. `/post-utme/results` — only while `POST_UTME_RESULT_CHECKING` is open, only a score the Academic Office **released**
   (`admissions.release_scores`, as before): `admissions.putme_result_check` says CLOSED / NOT_VERIFIED / NOT_RELEASED /
   RELEASED.

## The Director of ICT's way

- `/ict/question-bank` — the session's bank (`PUTME:2026/2027`), authored or imported from a spreadsheet, moderated.
- `/ict/cbt` — create the examination for the admission session (random paper, shuffled options, lab, one screen by
  default), set the second factor, publish (refused until the admission settings name a programme screened by
  examination: `CBT_PUTME_NO_PROGRAMME`); candidates are told by e-mail and SMS how to open the page.
- `/ict/applications` — open `POST_UTME_CBT` for the sitting and `POST_UTME_RESULT_CHECKING` when results may be read;
  the closure messages the public reads.
- `/ict/cbt/{id}/monitor` — the live monitor (candidates by JAMB number); terminate, extra time, incidents as for any
  examination.
- Results: review → approve on the examination; then `/ict/putme-scores`: every applicant's best approved attempt,
  **Generate official score file** (refused while any examination with attempts has results not approved:
  `PUTME_EXPORT_UNAPPROVED`), download the branded spreadsheet (S/N, JAMB number, name, application number, faculty,
  department, programme, session, examination, questions, attempted, marks, score, percentage, date, status; the
  file's hash in its meta), **Send to Academic Office** (its officers are e-mailed), cancel before import.

## The Academic Office's way

`/admissions/putme-scores`: the files sent, each with its reference, hash and history. Confirm receipt, download
(recorded), **Preview & import**: each line is NEW / SAME / DIFFERENT / RELEASED / NOT_FOUND / OUT_OF_RANGE. The import
(`admissions.putme_import_scores`) enters new scores, leaves the same alone, keeps a different one (default) or replaces
it with a reason — the previous value on `putme_score_history` — and **never touches a released score**. Idempotent: a
file imported twice enters nothing twice. Then the scores are released as always (`/admissions/scores`), and the merit
list, the eligibility engine and the template read them as they did.

## Security

- The JAMB number alone opens nothing; the second factor is the examination's; failures are indistinguishable and
  throttled; every verification (`PUTME_CBT_VERIFIED` / `PUTME_CBT_VERIFY_FAILED`) is on `admissions.applicant_event`.
- The examination token's office is `putmecbt`: `OFFICE_applicant`, `OFFICE_student` and every office door refuse it;
  an applicant's ordinary sign-in cannot open the examination door.
- The attempt must be the application's (`own()`), and the screen must hold the attempt's token (`X-Attempt-Token`).
- The key never leaves the server (`cbt_candidate_paper`); images only inside the running attempt (V376).
- The score is in the engine's audited attempt and result; the file's rows are a snapshot with a hash; every state
  change of a file and every import are audited; nothing is deleted.
- Multi-instance: nothing authoritative is in memory — the attempt, its clock and its answers are PostgreSQL's; the sweep
  runs under `JobLock` (V322). The throttle counts per instance (V359), as before.

## Tests

- `db/check.sql` property "V385: Post-UTME on the one CBT engine …" (the whole chain, undone).
- `PutmeCbtIT` (the API end to end: the door, the room, the no-score answers, the file, the import, the release, the
  result check, the doors that refuse).
- `docs/application-windows.md` lists the two new windows.
