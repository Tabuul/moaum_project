# GST CBT Examination Engine (V322)

General Studies examines by computer-based test from its own dashboard; Entrepreneurship Studies uses the same
engine the day it wants to. The engine sits on what the portal already had: the GST fee, entitlement and gate of
V314, the course registration engine, the question bank of V077, the results pipeline, the offices and RBAC,
the audit, the notice queue and the branded exports. Nothing was rebuilt and nothing was duplicated.

## A. Gap analysis — what existed, what was missing

| Area | Already there (reused) | Missing (added by V322) |
|---|---|---|
| GST fee, payment, entitlement | V314: `finance.gst_fee` stated by the Bursar per session, `finance.gst_entitlement` from confirmed references on `finance.payment_reference` net of refunds, one payment covers EPS | nothing |
| Registration gate | V314: `registration.gst_gate` raised by `student_choose / student_add / student_submit` | nothing |
| GST / EPS offices, dashboards, students, courses | V314: `ref.office` gst/eps, `/gst/*`, `/eps/*`, `finance.gst_population`, `gst_course_stats` | CBT figures on the dashboard (`/api/v1/cbt/summary`) |
| Question bank | V077: `assessment.question` with one correct option, topic, difficulty, marks; `/exams/question-bank` for lecturers | kinds MCQ / TRUE_FALSE / MULTI with the key as an array, explanation, author on record, edit, office scoping, the office's own screen |
| CBT | Post-UTME seating only (V260: centres, rooms, workstations, batches) — no attempt, no answers, no timer | the examination, paper, attempt, answers, events, result; eligibility; timer; scoring; policy; monitor; workflow |
| Results | `assessment.score_sheet / score`, the chain, `policy.grade_of` | the CBT result workflow and `cbt_to_sheet` writing the examination component onto the sheet |
| RBAC, audit, notices, exports | `OFFICE_<code>` authorities, `audit.attach`, `platform.queue_notice`, `brandedXlsx / brandedPrint` | nothing |
| Real-time | none (the BFF buffers responses; no SSE or WebSocket) | controlled polling with a cursor: counters plus only the changed attempts and events |

## B. Database (`db/V322__gst_cbt_examination_engine.sql`)

All keys are UUIDs; business identifiers (the examination reference `CBT/<session>/<n>`, matric numbers, course
codes) are separate columns.

| Object | What |
|---|---|
| `assessment.question` + `kind`, `answers int[]`, `explanation`, `updated_at/by`; trigger `question_key_check` | the three kinds; the key kept sorted whatever the kind; true/false has two options |
| `assessment.cbt_exam` | office, course, offering, session, semester, title, instructions, state, window, duration, size, selection FIXED/RANDOM, randomisation, pass mark (%), attempt limit, security mode STANDARD/SECURE, venue REMOTE/LAB, violation limit and action WARN/SUBMIT/TERMINATE, second-session policy CONTINUE/DENY, results state |
| `assessment.cbt_exam_question` | the fixed paper in order, or the pool a random paper draws from; marks overridable |
| `assessment.cbt_attempt` | one per student in progress (partial unique index); token; server end time; the paper drawn (`question_ids`, `seed`); score, percentage, grade, pass; violations; last activity; ip and agent; how it ended |
| `assessment.cbt_answer` | the chosen positions per question, replaced until finalised |
| `assessment.cbt_event` | STARTED, RESUMED, TAB_SWITCH, WINDOW_BLUR, FULLSCREEN_EXIT, NETWORK_DISCONNECT, RECONNECTED, MULTIPLE_LOGIN, SESSION_REPLACED, COPY_PASTE, CONTEXT_MENU, WARNING, FINAL_WARNING, AUTO_SUBMITTED, TERMINATED, SUBMITTED, TIME_EXPIRED, AMENDED |
| `assessment.cbt_result` | versions: v1 by the scoring, later ones amendments with a reason and author |
| `cbt_eligibility(exam, student)` | published · active student · registered on the offering (submitted registration) · `registration.gst_gate` quiet · paper ready · window open · attempts left; `'CODE: message'` or NULL |
| `cbt_start` | eligibility raised here (no path round it); the paper by seed; `ends_at = least(now + duration, window end)`; a second sign-in continues (token rotated, MULTIPLE_LOGIN + SESSION_REPLACED logged) or is refused, by policy; an advisory lock per student |
| `cbt_touch / cbt_save_answers / cbt_record_events` | the token checked on every call; an attempt past its end (15 s grace) finalised first; answers validated against the paper and the options; the violation policy applied and the warning level returned |
| `cbt_finalize` | one transaction: answers judged against the keys (a question earns its marks when the chosen set equals the key — all-or-nothing for MULTI), percentage, grade by `policy.grade_of`, pass/fail, result v1, event; idempotent |
| `cbt_sweep` | every attempt past its end finalised; run by `CbtClock` every 30 s under `JobLock`, one instance at a time |
| `cbt_exam_action` | schedule, publish (paper ready, candidates told), unpublish (no attempts), close (window ends now, running attempts submitted), complete (results → AUTO_SCORED), cancel (reason, attempts terminated, candidates told) |
| `cbt_results_action` | review → approve (examination completed) → publish (candidates told) → unpublish |
| `cbt_amend_result`, `cbt_terminate` | with a reason, as versions / events |
| `cbt_to_sheet` | best percentage per candidate × (100 − `ca_max`) as the examination component on the course's score sheet (stage ENTRY), a new version with the examination as its reason; CA kept, INCOMPLETE without one; idempotent |
| `cbt_candidates`, `cbt_monitor_counts`, `cbt_exam_stats`, `cbt_office_summary`, `cbt_student_exams` | set-based reads; the entitlement computed with the same logic as `gst_gate` over the session's payments |
| `platform.reset_operational_data` | restated with the six CBT tables cleared before the questions, offerings and students |

## C. API

Office (`/api/v1/cbt`, readers = the V314 readers; managers = the office itself and super; stronger = registrar and super):

| Method and path | Who | What |
|---|---|---|
| `GET /summary?office=&session=` | readers | the dashboard's CBT figures and the next examinations |
| `GET /exams?office=&session=&semester=&state=` | readers | the examinations with counts; the offerings an examination can be made over |
| `POST /exams` · `GET /exams/{id}` · `PUT /exams/{id}` · `PUT /exams/{id}/paper` | managers (reads: readers) | create, read, configure, set the paper |
| `POST /exams/{id}/{schedule\|publish\|unpublish\|close\|complete\|cancel}` | managers | the lifecycle |
| `GET /exams/{id}/candidates?status=&fac=&dept=&prog=&level=&q=&page=&size=&sort=` | readers | paged, filtered |
| `GET /exams/{id}/monitor?since=` | readers | counters + the attempts and events changed since the cursor; never answers |
| `GET /exams/{id}/candidates/{student}` · `POST /exams/{id}/attempts/{attempt}/terminate` | readers / managers | one candidate's attempts, events, versions; an attempt ended with a reason |
| `GET /exams/{id}/results?…` · `GET /exams/{id}/analytics` | readers | results rows, stats, by faculty / department / programme / level / grade, score bands |
| `POST /exams/{id}/results/{review\|approve\|publish\|unpublish}` | managers (unpublish: stronger) | the workflow |
| `PUT /exams/{id}/attempts/{attempt}/result` | managers; stronger once published | an amendment with its reason |
| `POST /exams/{id}/results/to-sheet` | managers | the scores onto the score sheet |
| `GET /courses?office=` · `GET /questions?course=` · `POST /questions` · `PUT /questions/{id}` · `POST /questions/{id}/active` | bank readers / authors (gst and eps in their own courses) | the bank |

Candidate (`/api/v1/me/cbt`, the signed-in student only; every attempt call needs `X-Attempt-Token`):

| Method and path | What |
|---|---|
| `GET ?session=` · `GET /exams/{id}` | the examinations on the registered courses, eligibility, attempt, published result |
| `POST /exams/{id}/start` | the attempt and its token (404 for an examination not the student's) |
| `GET /attempts/{id}` | the paper in the attempt's order, options in its order, answers so far — **no key, no explanation** |
| `PUT /attempts/{id}/answers` · `POST /attempts/{id}/ping` · `POST /attempts/{id}/events` · `POST /attempts/{id}/submit` | autosave, heartbeat, the browser's reports, submission |
| `GET /attempts/{id}/result` | only once published (`CBT_RESULT_NOT_PUBLISHED` otherwise) |

Coded refusals come from the database (`'CODE: message'`, SQLSTATE 23514) and the existing `ProblemHandler` turns
them into 422 with the code: `CBT_EXAM_NOT_OPEN`, `CBT_COURSE_NOT_REGISTERED`, `GST_PAYMENT_REQUIRED`,
`CBT_EXAM_NOT_STARTED`, `CBT_EXAM_ENDED`, `CBT_ATTEMPT_LIMIT`, `CBT_SECOND_SESSION_DENIED`, `CBT_SESSION_REPLACED`,
`CBT_ATTEMPT_CLOSED`, `CBT_QUESTION_NOT_ON_PAPER`, `CBT_PAPER_EMPTY`, `CBT_STATE`, `CBT_RESULTS_STATE`,
`CBT_REASON_REQUIRED`, `CBT_QUESTION_SAT`, …

## D. Screens

- Office (`/gst/...`, `/eps/...` on the same components): **CBT Examinations** (list, create), one examination
  (setup and lifecycle, paper from the course's bank, candidates with filters and a candidate's record, results
  and analytics with the workflow, amendments, score-sheet hand-off, Excel/PDF exports), **Live monitor**
  (counters, candidate table with filters All / Writing / Submitted / Not started / Disconnected / Warning /
  Violation / Terminated / Time expired, search, events feed, candidate detail, terminate), **Question bank**
  (three kinds, edit, retire). The dashboard carries the CBT figures and links.
- Student: **GST CBT Examinations** (state, eligibility and why, instructions acknowledged, start / continue,
  published result) and the **examination room** outside the shell: fullscreen requested on entry, the server's
  clock ticking locally and submitting at zero, answers saved 1.2 s after a change in batches and retried,
  heartbeat every 30 s, the tab hidden / window blurred / fullscreen exited / connection lost / copy and paste /
  context menu reported, the warning and final-warning dialogs, a second-sign-in screen, the ended screen.

### Partial credit (V324)

Each examination says how a multiple-select question is marked. **All or nothing** (the default, and how every
paper set before V324 scores): the marks only when the chosen options are exactly the key. **Partial credit**:
each correctly chosen option earns marks ÷ |key|, each wrongly chosen option costs the same, and the question
never scores below zero, so partial knowledge counts and selecting everything earns nothing. The rule is one
pure function, `assessment.cbt_marks_for`, read by `cbt_finalize` from the examination; the office sets it on
the examination's setup, the student reads it in the instructions and on each multiple-select question.

### The bank from a spreadsheet

On a course's bank, **Import questions from a spreadsheet**: a template with worked examples (Topic, Question,
Option A … H or one Options column split on `|` or `;`, Correct Answer, Kind, Difficulty, Marks, Explanation),
the file's columns mapped by name, every row judged on the server (`POST /api/v1/cbt/questions/import`):
the key read as a letter, a 1-based number, several letters for a multiple-select question, or the option's own
text; the kind as given or implied (several keys → MULTI, True/False alone → TRUE_FALSE, else MCQ); errors
named per row (`STEM_REQUIRED`, `OPTIONS_TOO_FEW`, `OPTIONS_REPEAT`, `ANSWER_REQUIRED`, `ANSWER_INVALID`,
`KIND_INVALID`, `TRUE_FALSE_OPTIONS`, `DIFFICULTY_INVALID`, `MARKS_INVALID`); the same question twice in the
file and a question already in the bank (by its text) skipped, never added twice. "Check the file" writes
nothing; "Import" writes only the valid rows, in the author's name, and the error report carries the original
row numbers. The GST and EPS offices import into their own courses only (`QuestionImportIT`).

## E. Security boundary — stated plainly

Standard browser CBT monitoring can detect many browser-level events, but a normal web application cannot
guarantee that a student cannot switch to another operating-system application or use another device. The
portal records what the page can see and applies the office's policy; it does not claim more. For true lockdown
the examination is created in **Secure CBT / kiosk** mode and sat in a secure exam browser, a kiosk, or the
University's managed CBT laboratory; the examination says which it needs and the student's screen says so.

What is enforced on the server regardless of the browser: authorisation (office, student, attempt ownership),
eligibility at the start, the attempt token on every call, the timer, the scoring, the answer validation
(question on the paper, option in range, attempt running), one attempt in progress per student, the violation
policy, the audit on every table, and the keys never leaving the server (the paper query selects neither
`answer`, `answers` nor `explanation`; the integration test asserts it).

A browser event is evidence, not a verdict: the office sees the record and decides under University policy,
unless the examination's policy is configured to submit or terminate automatically.

## F. Scale

- State lives in PostgreSQL only; any number of API tasks serve the same examination; a task restarting loses
  nothing, and the clock's sweep runs on one task at a time under the job lock and is idempotent.
- No timer tick touches the database: the browser counts down from the server's end time; the heartbeat is one
  small update every 30 s; answers are batched and debounced.
- The monitor sends the counters (one aggregate over the attempts, indexed on `(exam_id, status)`) and only the
  attempts changed since the cursor (indexed on `(exam_id, updated_at)`); the candidates who have not started are
  loaded once, paged by 500.
- Candidate lists, results and analytics are set-based (`cbt_candidates`, GROUPING SETS) with server-side
  pagination; nothing loads the register into memory.
- Indexes: `cbt_exam (office, session, semester, state)`, `cbt_exam (offering_id)`, `cbt_attempt (exam_id, status)`,
  `cbt_attempt (exam_id, updated_at)`, `cbt_attempt (student_id, exam_id)`, partial `cbt_attempt (ends_at) WHERE
  IN_PROGRESS`, the partial unique active-attempt index, `cbt_event (attempt_id, at)`, `cbt_event (exam_id, at)`,
  `cbt_exam_question (exam_id, ordinal)`; the registration side uses the existing `ix_entry_offering` and the GST
  payments the existing `ix_pref_gst_fee`.

### Load test

`api/scripts/cbt-load.mjs` seeds N registered and paid candidates with a 50-question paper in a scratch database,
runs them concurrently (start, paper, ten answer batches, two heartbeats, one event, submit) while an office
screen polls the monitor every two seconds, and reports p50 / p95 / p99 per call. Results on the development
machine (one API instance, PostgreSQL 18 on the same machine) are recorded in section H.

## G. Tests

- `CbtExamIT`: the office authors in three kinds in its own course and the other office and a lecturer are
  refused; an examination is created, cannot be published without a paper, is read by nobody else, is published
  and the registered candidates are told; eligibility — not registered (404), fee stated and unpaid
  (`GST_PAYMENT_REQUIRED`), paid, a future examination (`CBT_EXAM_NOT_STARTED`); the paper without a token, with
  another student's token, and with the token carrying no key; answers saved, a foreign question refused, the
  monitor without answers; the warning and the final warning; submission scored at once (percentage, grade,
  pass), hidden from the student, seen by the office with its events; the attempt limit; the result workflow
  (approve needs completion; review; an amendment by the other office refused, without a reason refused, with
  one a version 2; approve; to the score sheet with the scaled examination component and INCOMPLETE without a
  CA, idempotent; publish; the student's result; after publication the office is refused and the Registrar
  amends and withdraws); analytics; a sat question keeps its options; a second sign-in rotating the token and
  refusing the old screen, counted; the policy terminating over the limit, seen in the monitor and its delta;
  the clock finalising an abandoned attempt from the answers saved; status filters; DENY refusing a second
  screen; cancellation terminating attempts.
- `db/check.sql` properties 167–168: the whole flow in SQL, rolled back — eligibility codes, the key never in a
  paper, token rotation, the policy, atomic scoring once, hidden until published, amendment versions, the sweep.
- Frontend: type-check and lint of the screens; the existing node tests unchanged.

## H. Performance measurements

`cbt-load.mjs` on the development machine (Windows 11 laptop; one API instance from the jar; PostgreSQL 18 on
the same machine; Hikari at its default pool of 10). Every candidate starts within two seconds of the run
beginning — far harder than a real sitting, where candidates trickle in — reads a 50-question paper, saves ten
batches of five answers 50–200 ms apart, sends two heartbeats and one event, and submits; an office screen
polls the monitor every two seconds throughout. Latencies in milliseconds, measured at the client.

| Candidates | Calls | Calls/s | Wall | start p95 / p99 | paper p95 / p99 | save p95 / p99 | ping p95 / p99 | submit p95 / p99 | Errors | DB connections |
|---|---|---|---|---|---|---|---|---|---|---|
| 100 | 1,554 | 382 | 4.1 s | 79 / 128 | 66 / 120 | 95 / 130 | 73 / 106 | 106 / 140 | 0 | 11 |
| 500 | 7,956 | 886 | 9.0 s | 561 / 1,002 | 980 / 1,047 | 506 / 794 | 502 / 530 | 280 / 336 | 0 | 11 |
| 1,000 | 15,957 | 1,176 | 13.6 s | 1,502 / 1,547 | 2,097 / 2,243 | 793 / 1,234 | 741 / 767 | 719 / 781 | 0 | 11 |

Every attempt was scored; the monitor answered in 90 ms (100), 375–649 ms (500) and 647–1,189 ms (1,000)
while the whole cohort was writing. The latency at 1,000 is queueing on the single instance's thread and
connection pools, not the database: the connection count never exceeded the pool, and the per-call work is
one or two indexed statements. On ECS the same examination spreads across tasks (the state is in PostgreSQL;
the clock runs under the job lock), and a real sitting spreads its starts over minutes rather than seconds.
The queries to watch under `pg_stat_statements` on RDS are `cbt_start` (eligibility: the registration, the
GST references, the paper), `cbt_save_answers` (one upsert per answer), `cbt_monitor_counts` and the monitor's
delta; all read through the indexes listed in section F.

## I. V364 — one engine for every CBT-enabled course

- **Courses.** `catalogue.course.cbt_enabled`: no course is a CBT course until the Academic Office, the Registry or Examinations and
  Records allows it (`/exams/cbt-courses`, `catalogue.set_cbt_enabled`); General Studies courses start allowed. Creation, publication
  and eligibility all refuse a course that is not allowed (`CBT_COURSE_NOT_ENABLED`); a course with an examination still to be completed
  cannot be withdrawn (`CBT_COURSE_IN_USE`).
- **Offices.** `EXAMS` beside GST and EPS: a department's Examinations Officer for the department's courses, a Faculty Examinations
  Officer for the faculty's, Examinations and Records for any (`/exams/cbt`; scope through `OfficeScope.assertCourseInScope`). Its
  candidates are judged by `finance.clears(student, session, 'EXAMINATION')` (`CBT_FEES_NOT_CLEARED`); GST and EPS keep the GST gate.
- **Frozen papers.** `assessment.question_version` (written by trigger on every change of wording, options, key, kind, marks or
  explanation); `cbt_attempt.question_versions` and `question_marks` fixed at the start; the paper (`cbt_candidate_paper`) and the
  scoring (`cbt_attempt_questions`) read the snapshot, never the live bank. A sat question can be corrected (a new version), but not while
  an examination drawing it is published (`CBT_QUESTION_IN_LIVE_EXAM`).
- **Blueprint.** `assessment.cbt_blueprint` by DIFFICULTY or TOPIC for a random paper; refused on setting and on publication when the
  pool cannot satisfy it, naming what is short (`CBT_BLUEPRINT_SHORT: Hard needs 10, the pool holds 6`). The seed comes from
  `gen_random_uuid()`, never the browser.
- **Settings** (`cbt_configure`): kind, negative marking (total floored at nought), back navigation, mark for review, fullscreen,
  detectors, counted events, warning / final-warning thresholds, minutes out of contact before submission (`cbt_sweep`), camera
  proctoring by consent (`cbt_camera`; signals only, no video, no microphone, no identity matching), score on submission (default off),
  and where the result goes on the score sheet (EXAM, CA or NONE).
- **Answers** carry the screen's sequence number (a late retry never overwrites a newer answer) and a review flag; a cleared answer is
  kept as an empty set. **Events** carry a severity (a reading aid, never a verdict), the question number and the duration.
- **Archive**: completed or cancelled examinations, and questions, are archived, never deleted.
- **Import**: Course Code and Status columns, the brief's tallies, all-or-nothing by default (the officer may choose the valid rows only).
- **Room**: mobile-first (`ExamRoom.module.css`): sticky clock, large targets, two-row controls on a phone, a navigator drawer, a final
  review screen, and the University's words on submission. Face signals use the browser's own `FaceDetector` where it exists; head-pose
  signals need a proctoring library and are not claimed.
- Tests: `CbtEngineIT`, `CbtExamIT` (a sat question corrected as a new version), `QuestionImportIT` (blocked batch), check.sql 208.
