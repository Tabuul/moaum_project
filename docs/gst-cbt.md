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

## J. V365 — JUPEB on the same engine

- **Candidates of two kinds.** `cbt_attempt.student_id` (a University student) or `jupeb_application_id` (a JUPEB student), exactly one;
  `candidate_id` is whichever it is, and every lookup (the active-attempt index, attempt counts, the monitor, the candidate record) uses it.
- **Subjects, not offerings.** A JUPEB Office examination names `jupeb_subject_id` in place of a course offering (`cbt_new_jupeb_exam`);
  a subject is examined by CBT only once the JUPEB Office allows it (`jupeb.subject.cbt_enabled`, `jupeb.set_subject_cbt`,
  `PUT /api/v1/cbt/catalogue/jupeb/{id}`). Its bank is on `assessment.question.jupeb_subject_id`, named `JUPEB:<code>` on the screens and the
  API, frozen by version as every bank is; only the JUPEB Office (and the Super Administrator) reads or writes it, and the JUPEB Office works
  in no other bank.
- **Eligibility** (`cbt_jupeb_eligibility`): admitted (state STUDENT), registered for the subject in the session, and the Bursary's share of
  the school fee for the semester paid (`jupeb.school_fees`: the first share for the first semester, the whole fee after) —
  `CBT_JUPEB_NOT_STUDENT`, `CBT_JUPEB_SUBJECT_NOT_REGISTERED`, `CBT_JUPEB_FEES`.
- **Results**: never the Board's mark. A JUPEB examination counts towards a part of the JUPEB continuous assessment the office set
  (`jupeb_ca_component_id`, sheet component CA) or nowhere; `cbt_to_jupeb_ca` writes each candidate's best approved percentage scaled to
  that part's maximum through `jupeb.ca_save`, so the registration, the range and the lock are judged where they always were.
- **Doors**: one candidate implementation (`CbtCandidateDoor`) behind the University student's `/api/v1/me/cbt` and the JUPEB student's
  `/api/v1/jupeb/me/cbt` (a JUPEB application's token; a temporary password writes nothing until changed). The same list and examination
  room: `/jupeb/portal?tab=cbt` and `/jupeb/portal/cbt/room/[attempt]`. The JUPEB Office's desk is `/jupeb/cbt` and `/jupeb/question-bank`.
- JUPEB's practice tests (V348) stay self-study, not examinations.
- Tests: `JupebCbtIT`, check.sql 209.

## K. The examination room made easier to work through, and the office's preview (V371)

- **The room on a wide screen** (de1e4e47): the question navigator takes about a third of the room (300 to 460px) and is never taller
  than the screen — its numbers scroll inside it, the current one kept in sight — and Previous, Next and the smaller actions stay pinned
  to the foot of the screen, as on a phone.
- **Long papers**: a navigator filter (all questions, the unanswered, the marked for review) and *Next unanswered*, which goes to the
  next question with no answer (round to the start where the paper allows going back). On a phone it sits in the Questions panel so the
  bar stays two rows.
- **Keyboard and text size**: on a computer A–E choose an option, ← and → move to the previous and next question (up and down are left
  to the browser, which moves between a question's options), M marks for review; nothing is taken while a warning is on screen or a key is
  held. A− / A+ change the question text size (0.9× to 1.5×), remembered on that browser only.
- **The office's preview**: *Preview as a candidate* on an examination's page (offices that manage it only) opens the examination room on
  the paper — `/cbt/preview/{id}`, from `GET /api/v1/cbt/exams/{id}/preview` and `assessment.cbt_preview_paper`, the pool at each
  question's current version, options in their written order, never a key or an explanation. No attempt is made; nothing is saved,
  reported or submitted; there is no camera or fullscreen; the screen says how a candidate's paper differs (drawn from the pool,
  questions or options shuffled).
- Tests: check.sql 216; `CbtExamIT` (the preview carries no key; the other office and reading offices are refused).

## L. Answers kept on the device, paper checks, question analysis (V372)

- **Answers kept on the device**: an answer not yet saved is kept in the browser's storage for that attempt (`cbt-unsaved:{attempt}`,
  with its save number) as well as in memory, and sent with the page as it closes. When the room reopens — after a crash, a dead battery
  or a reload while offline — the kept answers newer than the server's (by save number) are restored, shown and sent at once; the
  candidate is told. The copy is cleared when saved or when the attempt ends, and ignored after two days. A preview keeps nothing.
- **Paper checks** (Paper tab, the managing office; `GET /api/v1/cbt/exams/{id}/checks`, `assessment.cbt_paper_checks`): the same
  question twice (stem and options), two options that read the same (to fix when only one is the key), a blank option, an option such as
  "all of the above" while options are shuffled, a multiple-select question with one key, and — without shuffling — half or more of the
  single-answer keys on one letter. Warnings only; the bank already refuses an impossible key. The preview names how many there are.
- **Question analysis** (new tab, the managing office, once the examination has ended — it shows the keys;
  `GET /api/v1/cbt/exams/{id}/items`, `assessment.cbt_item_analysis`): for each question as drawn (its frozen version and key), the
  share who got it right (facility), the top 27% against the bottom 27% by score (discrimination, from ten scored candidates up), every
  option chosen overall and by the top group, and flags: a possible wrong key (more of the top group chose one wrong option than the
  key), weaker candidates doing better, weak separation, very hard or very easy, nobody answering. The guides shown are the usual
  classical ones (facility 0.20 to 0.90, discrimination 0.20 or more). The Results tab warns before approval when a key looks wrong.
  Nothing is re-marked.
- Tests: check.sql 217; `CbtExamIT` (the analysis waits for the end, refuses the other office and reading offices; the checks are
  the office's).
- **Whose paper it is**: the examination screen names the candidate — name, the number named for what it is (Matric No., or
  Admission No. before matriculation, JUPEB No. or Application No.) and a student's level — in the header on a computer, in a strip
  beneath it on a phone, on the entry screen (with "check that these are yours before you enter") and on the review screen. The room's
  `candidate` carries `number_label` and `level`.

## M. Wrong keys corrected, sittings, extra time (V373)

- **Correcting a key** (Question analysis → *Correct the key*; `GET/POST /api/v1/cbt/exams/{id}/questions/{q}/key-correction`,
  `GET /api/v1/cbt/exams/{id}/key-corrections`): once the examination has ended, the office picks the right option(s) and a reason,
  reads the effect on every candidate who sat the question (score now and after, grade, pass or fail), then applies it. The correction is
  kept in `assessment.cbt_key_correction` (before and after, reason, who, when, how many scores changed); every reading of the
  attempts' keys takes the latest correction (`assessment.cbt_key`), and the question's frozen version is never rewritten. Each changed
  score becomes a new version of the result (`assessment.cbt_result`) naming the correction; the score moves by the difference the key
  makes, so an amendment made by hand stays; a void result is untouched. The bank's question is corrected too when asked, unless the
  bank has changed it since or a running examination draws it. Once the results are published, only the Registrar or the Super
  Administrator corrects a key. If the results were already sent to the score sheet, the office sends them again (while it is at entry).
- **Sittings** (Sittings tab; `/api/v1/cbt/exams/{id}/sittings…`, `/seats/{candidate}`): each sitting has a name, a venue, a time inside
  the examination's window (at least the paper's length) and seats. *Seat the … without a seat* seats every candidate by programme, name or
  matric number, sitting after sitting by time; a candidate is moved from the attendance list while they have not begun. Each sitting's
  attendance list (seat, matric number, name, level, programme, extra time, a signature column) prints or downloads. With sittings, a
  candidate starts only in their own sitting (`CBT_NOT_YOUR_SITTING`, `CBT_NO_SITTING`) and the attempt ends with the sitting at the
  latest. The student's CBT page and the entry screen show their sitting, venue, time and seat. A sitting nobody has begun in can be
  removed.
- **Extra time** (Candidates → *Extra time*; `PUT /api/v1/cbt/exams/{id}/candidates/{student}/extra-time`): minutes beyond the paper's
  time for a named candidate, with a reason, on the record (`assessment.cbt_extra_time`; 0 withdraws it). Applied at the start, and to an
  attempt already running (its clock follows within the half-minute heartbeat; an `EXTRA_TIME` event is logged). Shown to the candidate.
- Tests: check.sql 218; `CbtExamIT` (sittings, extra time and a key correction through the API).

## N. Questions moderated, an invigilator's screen, late entry, and a full hall measured (V374)

- **Moderation** (question bank → *Moderation* column; `POST /api/v1/cbt/questions/{id}/moderation`, `POST /api/v1/cbt/questions/moderation`
  for several, `GET /api/v1/cbt/questions/{id}/moderation`): a question written, imported or changed (a new version: wording, options,
  key, kind, marks or explanation) waits for moderation. Someone other than the person who set that version — a Head of Department, an
  Examinations Officer, a Dean, or the GST, EPS or JUPEB office in its own banks — approves it or returns it with a note; the database
  refuses the setter (`CBT_MODERATE_OWN`), a return without a note (`CBT_REASON_REQUIRED`), and a return of a question an open
  examination is drawing. Every decision is kept (`assessment.question_moderation`: version, decision, note, who, when); the version now
  records who made it. Only approved questions go on a paper: the paper is refused with one that is not (`CBT_NOT_MODERATED`), an
  examination holding one is neither published nor opened, the paper checks name it (HIGH) and count what the bank still has waiting,
  and a whole-bank draw takes approved questions only. The questions already in the banks before V374 are taken as approved
  ("in the bank before moderation"). The bank's courses list and tiles show how many wait; *Approve n awaiting* decides the ones the
  signed-in moderator did not set.
- **Invigilators** (Sittings tab → *Invigilators*; staff found by name or staff number among those holding an office today,
  `GET /api/v1/cbt/staff?q=`, `POST /api/v1/cbt/exams/{id}/sittings/{sitting}/invigilators`, `…/invigilators/{person}/remove`): the office
  names each sitting's invigilators, one of them chief if it wishes; each is told by email (or a text when the record has no email). Nobody
  invigilates two overlapping sittings (`CBT_INVIGILATOR_BUSY`); only staff (`CBT_INVIGILATOR_NOT_STAFF`).
- **The invigilator's screen** (menu *Invigilation* → `/cbt/invigilate`, `/cbt/invigilate/{sitting}`; `GET /api/v1/cbt/invigilation`,
  `GET /api/v1/cbt/sittings/{sitting}/board`): seat by seat — not come, absent, admitted late, writing (answered of total, minutes
  left), not heard from (silent a minute), time up, submitted, time expired, terminated — with counts, a filter and a search, read again
  every fifteen seconds; it prints as an attendance sheet. No answers or scores appear. Read by the sitting's invigilators, the office
  running the examination, and (read only) the offices that read examinations. Photographs: the portal holds no student photograph to
  show, so the seat shows the name, number and level.
- **Attendance** (`POST /api/v1/cbt/sittings/{sitting}/candidates/{candidate}/absent | late | clear`, `…/rest-absent`): an invigilator of
  the sitting, or the office, marks a candidate absent once the sitting has begun and never after they started (`CBT_ABSENT_BEGUN`), or
  admits one who came late with up to the minutes they lost given back (`CBT_LATE_MINUTES` beyond that; more is the office's extra
  time). A candidate marked absent does not start (`CBT_MARKED_ABSENT`); a mark is undone while the candidate has not started; a
  sitting with marks in it is kept (`CBT_SITTING_MARKED`). Kept in `assessment.cbt_attendance`, audited.
- **Late entry** (Sittings tab → *Late entry*; `PUT /api/v1/cbt/exams/{id}/late-entry`): when the office sets it, a candidate may start on
  their own until that many minutes after their sitting begins; later, only once admitted (`CBT_LATE_ENTRY`). Not set, there is no limit
  — none is assumed. The student's CBT page shows the time entry closes, and an absent mark or a late admission.
- **A full hall measured** (`cbt-load.mjs --mode hall`): every candidate seated in one sitting with an invigilator; all start within five
  seconds; each saves an answer every ~5 s (several times a real candidate's pace) with the room's 30-second heartbeat for two or three
  minutes; then time is up and every screen submits within 1.5 s; the live monitor is read every 2 s and the board every 15 s. Development
  machine (12 cores; API, PostgreSQL 18 and the load generator on the same machine; pool of 10; `synchronous_commit` off). Client-side
  milliseconds, p95 (p99), after the two fixes below; no errors in any run:

  | Hall | start | save | heartbeat | submit at time up | monitor p50 | board p50 | calls/s |
  |---|---|---|---|---|---|---|---|
  | 300 | 41 (178) | 28 (34) | 20 (31) | 89 (106) | 37 | 70 | 74 |
  | 500 | 56 (183) | 25 (29) | 17 (94) | 148 (191) | 39 | 50 | 121 |
  | 1,000 | 277 (403) | 25 (31) | 16 (21) | 504 (681) | 56 | 83 | 244 |
  | 2,000 | 407 (619) | 28 (238) | 16 (22) | 2,605 (2,724) | 86 | 154 | 476 |

  The stress mode (500 candidates answering the whole paper as fast as the network allows) peaked at ~950 calls a second with no
  errors (saves p95 0.5 s at saturation). Doubling the pool to 20 made no difference: the limit on one machine is CPU, not connections.
  **Capacity**: up to 1,000 candidates in one sitting with every step under about half a second; 2,000 works without error but the
  time-up rush takes 2–3 s. Railway's processors, `synchronous_commit` on and the network between the API and the database will move
  these figures; run the same script against a staging copy before relying on more than 500 per sitting there.
- **Fixed from the load test**: (1) every answer saved and every heartbeat wrote the whole attempt (its question lists included) to the
  audit trail, before and after — 44,188 audit entries for a 3-minute, 500-candidate hall; an update that moves only an attempt's
  `last_activity_at`, `answered` and `updated_at` is no longer audited (3,607 entries for the same hall), every other change is, and the
  answers are kept as before in `assessment.cbt_answer`. (2) The live monitor judged every candidate's eligibility (fees and all) on each
  two-second read; that read (`assessment.cbt_monitor_live_counts`) now leaves it out, and the screen reads it on opening and once a minute.
  Together, for a 2,000-candidate hall, they took start p95 from 1.3 s to 0.4 s, the time-up rush from 4.1 s to 2.6 s, saves p99 from 1.1 s
  to 0.24 s and the monitor p50 from 287 ms to 86 ms.
- Tests: check.sql 219; `CbtExamIT` (moderation through the API — the setter refused, a lecturer refused, return with a note, the paper
  refused then accepted, several decided at once — and a sitting run by an invigilator: late entry, admission, absence, the board for
  the invigilator, the office and a reader, a lecturer and a candidate refused).

## O. Check-in at the door, the sitting report, moderation told and by sample (V375)

- **The CBT slip** (student's CBT page and the JUPEB portal → *Print your CBT slip*; `GET /api/v1/me/cbt/exams/{id}/slip`,
  `GET /api/v1/jupeb/me/cbt/exams/{id}/slip`; the office prints a whole sitting's from the Sittings tab, `GET
  /api/v1/cbt/exams/{id}/sittings/{sitting}/slips`): the candidate, the examination, the sitting, the seat and the late-entry time, with a QR
  of the portal's check-in page carrying `<examination>.<candidate>.<code>` — the code signed by the API under the check-code key
  (`CheckCodes.Kind.CBT_SLIP`). Issued once the candidate has a seat. The slip proves nothing on paper; the portal checks the code.
- **Check-in** (`/cbt/checkin?t=…`, `GET /api/v1/cbt/check-in?t=`, `POST /api/v1/cbt/sittings/{sitting}/candidates/{candidate}/check-in`): an
  invigilator scans the slip with the phone's own camera — or with *Scan a slip* on the board where the browser reads QR codes itself — and
  the portal shows the candidate's photograph from the record (the replaced photo, the admission passport or the JAMB photo; for a JUPEB
  candidate, their JUPEB passport), name, number, level, sitting and seat; *The face matches — check in*. A forged or altered code is
  refused (`CBT_SLIP_NOT_GENUINE`), as is a slip scanned for another candidate (`CBT_SLIP_MISMATCH`). The check-in is also made by hand from
  the board's seat panel. Recorded in `assessment.cbt_attendance` (PRESENT, with when, by whom and how: SCAN, MANUAL, or ADMITTED for a late
  admission). A candidate marked absent is not checked in until the mark is undone (`CBT_CHECK_IN_ABSENT`). Only the examination's
  invigilators and its office look a slip up; a candidate never does.
- **Check-in required** (Sittings tab → *Require it*; `PUT /api/v1/cbt/exams/{id}/check-in`): a candidate in a sitting then starts only once
  checked in or admitted late (`CBT_NOT_CHECKED_IN`). Off unless the office says so. A candidate checked in at the door within the late-entry
  limit is not late, however long they take to start.
- **Incidents** (board → *Record an incident*, or from a seat; `POST /api/v1/cbt/sittings/{sitting}/incidents`): power, network, equipment,
  suspected malpractice, illness, a disturbance, a question of identity, other — for the hall or for one candidate (their attempt linked),
  with when and, for an outage, the minutes lost. Recording an outage changes nobody's clock; time lost is given back by the office as extra
  time. They appear in the office's candidate view (*Incidents in the sitting*). After the report is filed, only the office adds one, marked so.
- **The sitting report** (board → *Sitting report*, `/cbt/invigilate/{sitting}/report`; `GET/POST /api/v1/cbt/sittings/{sitting}/report`,
  `POST …/report/addendum`): filed by the chief invigilator (any invigilator where none is chief, or the office) once nobody is writing or
  the sitting's time is over (`CBT_SITTING_RUNNING`), naming only the sitting's invigilators as present, once (`CBT_REPORT_FILED`): when it
  really began and ended, the remarks, and the counts as they stood (seated, checked in, started, absent, not come, admitted late,
  finished, incidents, minutes lost). Not changed after filing; the office adds an addendum. Printed with a signature line per
  invigilator. **Sitting reports** on each office's CBT examinations list (`/cbt/reports?office=…`, `GET /api/v1/cbt/sitting-reports`) lists
  every sitting — filed, report due, running, to come — within the office's scope.
- **Moderation told** (`assessment.notify_moderation`, run every ten minutes by `ModerationNotices`): each setter gets one notice per bank of
  the decisions at least five minutes old — how many approved, how many returned. No question and no note goes in a notice; they are read in
  the bank.
- **The moderator's queue** (menu *Question Moderation* → `/cbt/moderation`; `GET /api/v1/cbt/moderation/queue`): the banks with questions
  waiting, within the acting office's scope, with how many the signed-in person may decide (they did not set them), how many were returned
  (and to them), and theirs waiting.
- **Moderation by sample** (question bank → *Moderate by sample*; `GET/POST /api/v1/cbt/questions/samples`, `POST …/samples/{id}/close |
  withdraw`): the moderator chooses how many of the waiting questions they did not set to read; the server draws them at random and keeps
  the rest as they stood (each at its version). Every sampled question approved — the rest are approved with it, each decision naming the
  sample; one returned — the sample fails and the rest wait to be moderated one by one; a question changed or decided since the draw is
  left as it is. One open sample per bank per moderator.
- Tests: check.sql 220; `CbtExamIT` (a slip, the check-in rule, a forged code, the wrong candidate's slip, a lecturer and a candidate refused,
  slips for the office, incidents, the report refused while writing and to a lecturer, filed by the chief, the addendum the office's, the
  list; a sample drawn, refused unfinished, closed approving the rest, the setter's queue and their one notice with no question in it).
