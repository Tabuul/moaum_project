# Student cohorts, sessions merged, spillover and reconciliation (V331)

Where every student stands — in study, graduated, beyond the programme's length, or for the Registry to decide — is
computed from the register and never typed over it. The matriculation number, the JAMB year, the admission session and
the level on record are read; none of them is rewritten to make the figures look right. This document is the
implementation report for the brief *Student Cohort Reconciliation, Current Students, Graduated Students & Spillover
Tracking*.

## 1. What was inspected first

The platform already carried every building block the brief asks for, so V331 composes them rather than adding a second
register:

| Need | Existing piece | Where |
|---|---|---|
| The student, their identifiers, entry session, entry level, current level and status | `people.student` (status is a CHECK list of thirteen values) | V026 onwards |
| Status changes with instrument, date, reason and officer | `people.status_change`, `people.change_status(...)` | V124 |
| Registrations and enrolments a session at a time | `registration.course_registration`, `people.enrolment` | V060, V026 |
| The Senate's award | `records.graduand` (`senate_state` AWAITING → APPROVED, `unmet`) and `records.approve_awards` | V168 |
| Deferments and the sessions they cost | `people.deferment`, `people.deferment_semesters(kind, session)` | V236 |
| The calendar | `policy.academic_session` (DRAFT → PLANNED → CURRENT → CLOSED → ARCHIVED) | V040 |
| The programme's end | the final-level rule in `finance.final_level` (MBBS 600, Law and Pharmacy 500, the rest 400) | V097 |
| Outstanding courses | `registration.carryovers(student)` | V129 |
| The JAMB year | `admissions.candidate.session` through `candidate_id`; the year inside a 14-character UTME number | V021 |
| Office scope for Deans, Heads and faculty officers | `OfficeScope.bound(...)` | V150 |
| Who may do what | `@PreAuthorize` over office authorities; the audit spine refuses an unattributed write | V001 |

The live register (Railway, October 2026) shaped the rules: about 54,500 students; entry sessions from 2007/2008 while
the calendar starts at 2021/2022; 48,300 active and 6,250 admitted; registrations for 3,900 students but enrolments for
29,800; 3,450 postgraduate students on 364 postgraduate programmes whose level (700, 800, 900) never advances; no
graduand yet; JAMB numbers in the 14-character form (year first) for 37,000 students and older shapes for the rest.

The gaps were real: no cohort concept distinct from the entry session, no session-merger model, no programme length a
Registrar could confirm, no spillover limit in policy, no computed standing a dashboard could page through, and no
reconciliation workflow with a preview, a decision and a batch reference.

## 2. The model

**A cancelled session is merged, not deleted.** `policy.academic_session` gains `merged_into`, `merged_reason`,
`merged_minute`, `merged_on`, `merged_by` and the state `CANCELLED`. `policy.merge_session(session, into, reason,
minute)` cancels a session that is not current; `policy.unmerge_session` restores it. A cancelled session can never be
made current again (`SESSION_CANCELLED`); the current session cannot be merged (`SESSION_MERGE_CURRENT`).
`policy.effective_session(name)` follows the chain, so 2021/2022 → 2022/2023 is configuration, not code.

**Sessions are counted by arithmetic on the name, the calendar consulted only for cancellations.** `policy.session_year`,
`policy.session_after(session, n)` and `policy.sessions_elapsed(from, to)` work for a 2007/2008 entrant whose session
predates the calendar and for a 2024/2025 entrant whose completion session is not yet on it; a cancelled session is
skipped, so a 2020/2021 cohort on a four-year programme with 2021/2022 cancelled completes in 2024/2025.

**The cohort is derived.** `effective_cohort` = the entry session's effective session, unless the Registry has set a
`people.cohort_override` for that student on evidence (a re-admission, a transfer in). The source is recorded as
`ENTRY`, `MERGED` or `OVERRIDE`. The entry session itself is never changed.

**The programme's length is configured, never guessed.** `ref.programme.final_level` is the last level of a level-based
programme; a student's length follows from their entry level ((final − entry)/100 + 1 sessions, so a direct-entry
student on a 400-level programme has three). `ref.programme.duration_years` is the length in sessions of a programme
whose level does not advance (a postgraduate programme), or an explicit override. Undergraduate programmes are seeded
from the rule that was already in force, with a note saying so; postgraduate programmes are seeded with nothing, so
their students carry `DURATION_NOT_CONFIGURED` and wait for review until the Registry sets the length — one programme
at a time, or every programme of an award (every PhD, every M.Sc.) in one act. `finance.final_level` reads the
configured value first, so fee classification and progression agree.

**The spillover limit is policy.** `policy.progression_setting.max_spillover_years` (default 2) is set by
`policy.set_max_spillover(n)` from the Policy and sessions tab. Spillover is a classification of an active student,
not a status: the student stays `ACTIVE`, registers and pays as the fee rules already derive (`finance.is_spillover`).

**The position is a table, not a query.** `people.academic_position` holds one computed row a student: JAMB year,
matriculation year, entry session, effective cohort and its source, entry level, programme, final level and length,
the current session, the level on record and the level the cohort implies, expected completion, deferred and elapsed
sessions, spillover years and state, whether registered or enrolled this session, the last session on record, the
graduation state and session, the existing status, the classification, the proposed status, the rule that decided it,
the confidence and the issues. It is audit-exempt (derived) and recomputed by `people.refresh_academic_position` — one
student on every event that touches them (student, enrolment, registration, graduand, deferment, override), everyone
when the calendar, a programme's length or the policy changes; a bulk load under `moaum.maintenance = on` recomputes
afterwards in one pass. Nothing is computed on page load.

## 3. The rules, in the order they are tried

| Rule | Condition | Classification | Proposed status | Confidence |
|---|---|---|---|---|
| R1 | the Senate approved the award, or the record already says GRADUATED | GRADUATED | GRADUATED | VALIDATED (`APPROVED_NOT_GRADUATED` where the record still says ACTIVE; REVIEW where GRADUATED without an approved award) |
| R2 | an official status stands: WITHDRAWN, VOLUNTARY_WITHDRAWAL, EXPELLED, DECEASED, TRANSFERRED_OUT, RUSTICATED, SUSPENDED, DORMANT, DEFERRED, ADMITTED | that status | unchanged | VALIDATED (`DEFERRED_WITHOUT_LIVE_DEFERMENT` where no live deferment backs it) |
| R6 | the record is too thin: no entry session, an entry session that is not a session name, no programme length, no current session | REQUIRES_REVIEW | unchanged | REVIEW |
| R5 | audited on a graduation list with nothing unmet, Senate not yet sat | GRADUATION_ELIGIBLE | ACTIVE | VALIDATED |
| R4L | beyond the programme's length by more than the policy allows | SPILLOVER_LIMIT_REACHED | ACTIVE | REVIEW |
| R4 | beyond the programme's length, within the limit | SPILLOVER | ACTIVE | VALIDATED if registered or enrolled this session, else LIKELY |
| R3 | registered or enrolled in the current session | ACTIVE | ACTIVE | VALIDATED (REVIEW where the level on record differs from the cohort's) |
| R6 | within the length, not registered this session, and no registration or enrolment ever | REQUIRES_REVIEW | unchanged | REVIEW |
| R3L | within the programme's length, not yet registered this session | ACTIVE | ACTIVE | LIKELY |

Expected completion = cohort + (length − 1) + sessions deferred, cancelled sessions skipped — or, since V595, the first
session the register shows the student at the programme's final level where that is later (§18). Spillover years = sessions
elapsed beyond expected completion, never counting a deferred session against the student. The level the cohort
implies = entry level + 100 a session elapsed (less deferments), capped at the final level; for a postgraduate
programme it stays the entry level.

The issues array carries every finding, not only the deciding one: `MISSING_ENTRY_SESSION`, `ENTRY_SESSION_INVALID`,
`ENTRY_SESSION_AHEAD`, `MISSING_MATRIC`, `MISSING_JAMB`, `DURATION_NOT_CONFIGURED`, `DUPLICATE_MATRIC`,
`LEVEL_CONFLICT` (the level on record differs from the one the cohort implies), `NO_CURRENT_REGISTRATION`,
`NO_REGISTRATION_HISTORY` (no registration or enrolment ever), `GRADUATED_WITHOUT_APPROVAL`, `APPROVED_NOT_GRADUATED`,
`DEFERRED_WITHOUT_LIVE_DEFERMENT`, `SPILLOVER_LIMIT_REACHED`, `BEYOND_PROGRAMME_LENGTH`.

## 4. What the Registry can do, and who

| Act | Function | Offices | Record |
|---|---|---|---|
| Decide one student's standing on evidence | `people.decide_cohort(student, status, reason, batch)` | Academic Affairs, Registrar, Deputy Registrar, Academic Records | `people.cohort_decision` (previous and new status, cohort, rule, confidence, reason, officer, office, time, source, batch) and a `people.status_change` where the status moves |
| Graduate a student | refused: `COHORT_GRADUATION_SENATE` unless a `records.graduand` row is APPROVED | — | the Graduation screen and Senate's approval remain the only road |
| Reconcile the Senate's awards in bulk | `people.apply_cohort_rule('R1', reason, batch, dry_run)` | the same four | counted first (dry run), then one decision row a student under one batch reference; idempotent — a second run moves nobody |
| Correct a cohort | `people.set_cohort_override(student, session, reason)` and its removal | the same four | `people.cohort_override` plus a COHORT decision row |
| Set the spillover limit, a programme's length (one, or every programme of an award), merge or restore a session | `policy.set_max_spillover`, `ref.set_programme_length`, `ref.set_programme_length_by_award`, `policy.merge_session`, `policy.unmerge_session` | Registrar, Deputy Registrar, Academic Affairs, Super Admin | the audit spine, with the reason header on every call |

Only R1 may be applied in bulk. Every other rule is a proposal; the officer decides a student at a time with the
lifecycle in front of them. Support agents and CPOs have no authority here: the ICT office reads the Student Cohorts
screen but cannot decide, override or set policy; a student token is refused outright.

## 5. The API

`/api/v1/cohorts`: `GET /summary` (totals, by cohort with JAMB year, by faculty, by level, by spillover state, by
issue, the policy), `GET /students` (filters: faculty, department, programme, classification incl. the pseudo-groups
`HISTORICAL` and `REVIEW`, cohort, entry session, JAMB year, level, length, status, graduation state, spillover state,
confidence, issue, sex, entry mode and free text; sort by name, matric, cohort, JAMB year, level, expected completion,
spillover, programme or classification; page and size up to 2000; scope-bound for Deans, Heads and faculty officers),
`GET /students/{id}` (the position, status history, enrolments, registrations, graduation records, deferments,
programme changes, decisions, matriculation history, outstanding courses, the override and the sessions),
`POST /students/{id}/decision`, `POST /students/{id}/cohort`, `POST /apply`, `POST /refresh`, `GET /settings`
(policy, sessions with entrants and cohort size, programmes with their length and source, postgraduate awards),
`PUT /settings`, `PUT /programmes/{code}` {finalLevel, years, note}, `POST /programmes/by-award` {award, years,
note}, `POST /sessions/{a}/{b}/merge`, `POST /sessions/{a}/{b}/unmerge`. Every key is a UUID.

The student's own portal (`GET /api/v1/student/me`) now carries the JAMB year, the effective cohort and its source,
the programme length, expected completion, spillover state and classification, so the dashboard shows the cohort
where it differs from the entry session, a Spillover pill where it applies, and the expected completion session.

## 6. The screens

**Student Cohorts** (`/cohorts`; Academic Affairs, Registrar, Deputy Registrar, Academic Records, DVC, VC, Deans,
Heads, faculty officers, ICT, Admin, Super Admin) — tabs: Overview (tiles, by cohort, by faculty, by level, by
spillover year), Current, Graduated, Spillover, Review, All, Data quality, Policy & sessions. The filter bar covers
faculty, department, cohort, JAMB year, level, programme length, status, spillover, confidence, issue and search; the
list is the server's page, S/N first, with Review and Record on every row; Excel and PDF exports follow the
University's standard (logo, title, serial, generation date, S/N numeric). The Review tab counts the Senate's awards
awaiting reconciliation before applying them under a batch reference. The student modal shows the lifecycle and takes
the decision or the cohort correction with a reason. The Data quality tab lists each finding with its count and opens
the filtered list. Policy & sessions sets the spillover limit, merges or restores a session, sets the length of every
programme of a postgraduate award in one act, and each programme's length (programmes without one listed first).

**Student dashboard** — Cohort and Spillover pills in the header; Entry / JAMB year, Current session and Expected
completion in the profile grid.

## 7. Idempotence, performance, safety

The position is recomputed in place (`INSERT … ON CONFLICT DO UPDATE`); a full refresh is one set-based statement
over the register and the migration runs it once. A decision that changes nothing still records the decision but
writes no status change. Bulk application is counted before it runs and runs once. Every write needs an actor and an
office, carries the reason header, and lands on the audit spine; the position table is the only new table exempt from
it, being derived. `people.academic_position` cascades on the student, so the operational reset still clears cleanly
(property V292).

## 8. Tests

- `db/check.sql` property 179: sessions merged and the chain followed, the current session refused for merger, a
  cancelled session refused as current; a student from the merged session carried at 400 in the merged cohort beside
  one who entered the merged-into session; the Senate's award graduating one student in a counted bulk act; spillover
  year 1 validated; beyond the limit for review once the limit is lowered; graduation by hand refused; a decision and
  a cohort correction recorded; every matriculation number and entry session unchanged. Suite: 179 properties green on
  a brand-new database.
- `CohortIT`: the position computed on insert; summary, list and one student's lifecycle read by the Registrar;
  a student token refused; a blank reason refused; GRADUATED by hand refused with `COHORT_GRADUATION_SENATE`; a
  decision recorded under a batch; identifiers untouched; the policy set by Academic Affairs and refused to a Head;
  the dry run and the refusal of any bulk rule but R1.

## 9. What the Registry does after deployment

1. Open **Student Cohorts → Policy & sessions**: confirm the spillover limit; set the length of each postgraduate
   award (PhD, M.Sc., M.A., M.Ed., PGD, LL.M., MBA …) so their 3,450 students leave review; confirm the undergraduate
   lengths seeded from the rule; merge 2021/2022 into 2022/2023 (or whichever sessions the Senate merged), citing the
   minute.
2. Read the **Data quality** tab and fix the findings on the Students screen (missing matriculation and JAMB numbers,
   duplicate matriculation numbers, levels that disagree with the cohort).
3. On the **Review** tab, count and apply the Senate's approved awards, then decide the remaining REVIEW rows one at a
   time with the lifecycle in front of you — the students admitted years ago at 100 Level with no enrolment since are
   the first candidates for DORMANT or WITHDRAWN, on the evidence.
4. Export the Current, Graduated and Spillover lists for the Faculties.

Nothing in these steps edits a JAMB year, an admission session, a matriculation number or a level: those are corrected,
if at all, on the student's own record with the instrument that justifies it, and the position follows.

## 10. Levels brought to the cohort (V475)

The engine's level is not copied onto the record by itself, so a student who came over from the old portal at 100 Level
stayed at 100 Level on every screen, list, registration menu and level-based fee line, even two sessions into spillover.
On the live-shaped copy of 15 October 2026 that was 10,748 spillover students (most at 100 Level, computed 400–600),
8 others whose own latest registration is at the computed level, and 537 whose level only the count of sessions supports.

**Student Cohorts → Level corrections** lists every record in study below the computed level, with its basis:

| Basis | Meaning | Applied |
|---|---|---|
| Spillover | past the programme's length, so at its final level | by default |
| Own registration | the student's latest registration is at the computed level, or was one level below in the session just before (V476) | by default |
| Sessions counted only | the count of sessions alone (a repeated year or a gap reads the same) | only when chosen, after review |

The Academic Office, the Registry or the platform corrects them on one reason, in batches of 500. No level is ever
lowered (a record above its computed level is never listed), and each change is on the student's cohort decision history
(`LEVEL_SPILLOVER`, `LEVEL_REGISTRATION` or `LEVEL_ARITHMETIC`, previous and new level, batch) and on the audit spine.
Postgraduate students, whose level does not advance, are left out.

Spillover is named where a level is read: the student record's header ("400 Level (SP2)" and a "Spillover year 2 (SP2)"
mark), the student register and the Student Query list. SP1 and SP2 are each a session of both semesters; the limit is
the policy's (two sessions by default), and an approved deferment pushes the expected completion on by the sessions
deferred.

## 11. Lifecycle reconciliation (V558)

The positions above are now acted on in a controlled way: graduation candidates (final year, or beyond the length with
everything completed), spillover year 1 and 2 and the maximum spillover are reviewed, verified and reconciled in batches
(`RECON/YYYY/NNNNNN`) — a spillover stays ACTIVE with the level raised, the maximum only on the officer's choice, a
candidate goes on the graduation list for the Senate — with a deterministic explanation, a confidence, a preview, a
history and corrections. See [student-lifecycle-reconciliation.md](student-lifecycle-reconciliation.md).

## 12. Spillover fees by the cohort, when the Bursary chooses (V571)

The fee rule (V088) charges a student the spillover fee lines when the record's level is above the programme's final level
(a four-year programme's student at 500). The engine puts a spillover student **at** the final level, so once the levels
above are corrected those students are charged as final-year students. On the live-shaped copy of 19 October 2026 the fee
rule found 252 spillover students and the engine about 13,000 (SP1 2,039, SP2 5,543, the limit 5,489).

- **The basis is the Bursary's** (`finance.fee_setting.spillover_basis`): **By level** (V088's rule, the default, so nothing
  changes until the Bursary decides) or **By cohort** (the engine's spillover: SP1, SP2 … and the limit reached; never a
  graduate). It is changed with a reason, and who, when and why are kept (`finance.set_spill_basis`;
  `FEE_SPILL_BASIS`, `FEE_SPILL_REASON`).
- **One test** (`finance.spill`) is read by every fee function that held V088's test: `fee_profiles` (so `session_charges`
  and the summaries), `charges_of_as`, `due_for_semester`, `fee_stated`, `fee_gaps` and `is_spillover`. Each was restated
  from its current text with only that test changed; under By level the session's charges were checked identical on the
  live-shaped copy (54,573 students, the same checksum).
- **The preview.** Finance → Fee Schedule shows the basis and how many current students would be charged differently.
  **Preview the change** lists them (the first 200, an Excel of all) with the session's charges under each basis, read in
  one transaction with the other basis set for it (`moaum.spill_basis`), so nothing changes. On the copy, by the cohort
  12,819 students would move onto the spillover lines and none off; their 2025/2026 charges would fall from
  ₦2,021,129,559 to ₦996,179,250, and 277 would have no line stated (the 84 spillover lines are for 2025/2026 only).
- **API:** `GET /api/v1/finance/spillover-basis` and `/spillover-basis/preview?session=&all=` (the finance readers);
  `PUT /api/v1/finance/spillover-basis` `{basis, reason}` (the Bursar or the Super Administrator).
- **Tests:** `SpilloverFeeBasisIT`; check.sql's V571 block.

## 13. The spillover work told (V572)

On the copy, 10,748 spillover level corrections and 19,291 reconcilable recommendations were waiting, and Reconciliation had
never been run. Until they are done, those students are charged, registered and listed at the wrong level, and graduation
candidates do not reach the graduation list.

- **On the homes of the Academic Office and the Registrar**, a notice gives the level corrections (spillover and other), the
  recommendations to reconcile (graduation candidates, the limit reached, the spillover years) and when Reconciliation last
  ran. Each figure opens Level corrections or Reconciliation. Nothing is shown while nothing waits.
- **Each Monday at 08:30 (Lagos)**, while any of the work waits, the holders of the Academic Office and the Registrar are
  told (template `SPILLOVER_WORK_WAITING`, once a week each; ICT may switch the template off; cron
  `moaum.cohorts.spillover-work-cron`).
- `people.spillover_work()` counts it; `GET /api/v1/cohorts/spillover-work` reads it, kept five minutes.

## 14. Fee lines ready for the cohort basis, and the fee effect of a level change (V576)

- **Readiness.** Under "Who is charged the spillover lines", the Bursary sees two things for the current and the next session: the
  spillover lines stated, and the spillover students with no line by the level and by the cohort (`finance.spill_readiness`,
  `GET /api/v1/finance/spillover-basis/readiness`). On the copy of 20 October 2026:

  | Session | No line, by the level | No line, by the cohort |
  |---|---|---|
  | 2025/2026 | 81 | 358 |
  | 2026/2027 | 249 | 13,068 |

  No spillover line is stated yet for 2026/2027. The session copy already carries spillover lines: `finance.fee_line_same_scope`
  tells a spillover line from an ordinary one.
- **The fee effect, before a level changes.** Level corrections (in the dialog, for the first batch of 500) and Reconciliation's
  preview (for the levels it raises, the first 1,000) show the effect on the current session's charges: now, after, how many owe
  more, less or the same, and how many would have no fee line at their new level. `finance.level_fee_effect` raises the levels in a
  sub-transaction that is always undone, so nothing changes. On the copy, the first 500 spillover corrections are charged
  ₦83.6m now and ₦44.0m after: 491 owe less and 8 would have no line.
  API: `POST /api/v1/cohorts/levels/fee-effect` (the Apply body), `POST /api/v1/cohorts/lifecycle/preview/fees` (the preview body).
- **Tests:** `SpilloverReadinessKeptPopulationIT`; check.sql's V576 block.

## 15. The fee effect of every waiting correction, and the spillover lines copied (V580)

- **Every waiting correction at once.** §14's effect reads one batch. Under "What correcting every waiting level does to the fees",
  on the Bursar's fee page and below the Level corrections list, a run reads every correction waiting. By default it reads the
  spillover and own-registration bases; the records only the count of sessions supports can be added.
  - The run takes the corrections as they stand when it begins (`people.start_level_fee_effect`, one run at a time).
  - It reads them 1,000 at a time behind the screens, holding the basis in force when it began (`people.level_fee_effect_step`).
    Each step is its own transaction in the starter's name. A run an API restart left open is taken up again within a minute; one
    still open after an hour is let go.
  - Each student's charges now and after are kept (`people.level_fee_effect_row`) and summed for the University, each faculty and
    each programme (`people.level_fee_effect_report`). An Excel gives the sums, and another gives every student.
  - Nothing on a record changes. A level corrected after the run is not in its figures: work it out again.
  - Started by the Bursary, the Students Account Officer, the Academic Office or the Registry. Read by them, Records, Audit, ICT
    and the Vice-Chancellor's offices. API: `GET /api/v1/finance/level-fee-effect`, `POST /api/v1/finance/level-fee-effect`
    (`bases`), `GET /api/v1/finance/level-fee-effect/{id}/rows`.
  - On the live-shaped copy of 20 October 2026, the 10,834 spillover and own-registration corrections took 45 s. They are charged
    ₦1.854bn for 2025/2026 now and ₦968m after: 10,663 owe less, 171 the same, and 166 would have no fee line at their new level.
- **Spillover lines copied on their own.** For each session under "Who is charged the spillover lines", the last earlier session
  that states spillover lines is named, with how many of its lines this one lacks. The Bursary (or the Students Account Officer)
  copies them from there after a preview (`finance.copy_spillover_lines`: the session copy's rule, spillover lines only). A line
  the session already states for the same students is kept. On the copy, 2026/2027 is offered 2025/2026's 84 spillover lines.
  API: `GET`/`POST /api/v1/finance/sessions/{session}/schedule/copy-spillover` (`from`).
- **Readiness of the next session.** The calendar's transition readiness has a line `SPILLOVER_FEE_LINES`: how many spillover
  students the session's fees charge nothing, by the basis in force, and how many spillover lines are stated. It reports only.
  It never holds the transition, nor the automatic clock (which a line not met would hold), like the line for the current
  session's open semesters.
- **Tests:** `LevelFeeEffectSpilloverCopyIT`; check.sql's two V580 blocks.

## 16. Missing fee lines stated, levels corrected by programme, the start warned of (V584, V585)

- **The lines a correction leaves missing.** Below the run's table, "Fee lines missing at the corrected level" groups the students
  charged nothing after by programme and corrected level (`people.level_fee_effect_gaps`). For each group it says whether the
  programme states no line in the session at all, or none at that level.
  - Each group offers the lines it could be stated from, nearest first: what applies to the programme at the nearest other level
    this session (the level below first), what applied to it at that level in the last session that states any, then another
    programme of the department, then of the faculty, stating its own lines at that level.
  - What applies to a programme at a level (`finance.programme_level_lines`) is its own lines, else its faculty's, else the
    University's: the most specific stated. On the live-shaped copy 544 of 2025/2026's 756 ordinary lines are faculty-wide by
    level, so a structure kept faculty by faculty is offered as readily as one kept programme by programme.
  - "See the lines" previews the copy (`finance.copy_programme_lines`): those lines, not the spillover ones, as the target
    programme's own at its level, so no student is charged twice. A line already stated for the same students is kept; the
    preview writes nothing. The Bursary or the Students Account Officer states them; the amounts are adjusted afterwards on the
    charges.
  - On the live-shaped copy of 20 October 2026 the 166 are three College programmes that state no 2025/2026 line at all (B.Sc.
    Biochemistry, Radiography, Medical Laboratory Science; 2,223 students on them), each offered B.Sc. Human Anatomy's or
    Human Physiology's 400 Level lines.
  - API: `GET /api/v1/finance/level-fee-effect` (`gaps`), `GET`/`POST /api/v1/finance/level-fee-effect/gap-lines`.
- **Corrected programme by programme.** The run's report counts, for each faculty and programme, the students brought to their
  level since the run. The Academic Office or the Registry corrects one programme's waiting corrections from its row ("Correct",
  with a reason, on the run's bases), its fee effect beside it.
- **The start of a session warned of.** A week before a planned session's automatic transition date the Registrar's and the
  Bursar's offices are told whether it will start on its own, every check not met, and what its fees and spillover lines stand at
  (`policy.tell_session_start` from the nightly session clock, template SESSION_START_READINESS); again the day before while a
  check is still not met. Under "Who is charged the spillover lines" the Bursar chooses whether spillover students with no line
  hold the automatic start (`finance.fee_setting.spill_lines_hold_start`, off by default;
  `PUT /api/v1/finance/spillover-basis/hold-start`). A person may still make the session current.
- **Tests:** `FeeGapsKeptClearanceStartWarningIT`; check.sql's V584 and V585 blocks.

## 17. Corrected by the level a student should be at; the positions in Statistics and Student Query (V593)

The level, spillover and graduation reconciliation the University asked for in October 2026 was already this engine: the
cohort, the programme's own length (4, 5, 6 years; never guessed), merged sessions, deferments and the spillover limit
(`people.academic_position`), the corrections that bring a record to its level and never lower it (§10), and the lifecycle
reconciliation of graduation candidates, SP1, SP2 and the maximum, with batches, preview, history and correction (§11). V593
adds what was missing to act on it a level at a time, and to see it everywhere from the same engine:

- **Level corrections by the level a student should be at.** Student Cohorts → Level corrections finds the records by
  *Should be at* (100–600 Level) and by *Spillover* (SP1, SP2, beyond the limit, or within the programme's length), with the
  counts of each as buttons; *Choose all on this page*; and *Correct every one found*. The latter counts first (a dry run of
  `people.apply_level_corrections` with the same filters — now also `p_to_level`, `p_spillover`, `p_q`): how many are found,
  how many go by spillover and by their own registration, and how many only the count of sessions supports, which are left for
  review unless included. Each batch of 500 is read again from the engine when it is applied, so a record changed since, or no
  longer below its level, is left alone; no level is lowered; each change goes on the cohort decision history with the reason.
  API: `GET /api/v1/cohorts/levels?level=&spillover=` (with `byLevel`, `bySpillover`), `POST /levels/apply`
  `{toLevel, spillover, q, …}`.
- **Student Statistics by academic position.** For the current session the figures carry *By academic position*: SP1, SP2,
  beyond the spillover limit and graduation candidates, as the lifecycle reconciliation recommends them
  (`people.lifecycle_recommendation`), each figure opening its students; the filter *Academic position* narrows every figure
  (`GET /api/v1/stats/students/summary?position=SP1|SP2|SP_LIMIT|GRADUATION_CANDIDATE`, `byPosition`).
- **Student Query.** *More filters* gains *Expected level* (the engine's), *Level on record* (below the expected level, or at or
  above it), *Programme length* (the programme's own: its stated length, else its final level ÷ 100), *Reconciliation* (the
  lifecycle recommendation) and *Completion (as last analysed)* (`people.lifecycle_completion`; run *Refresh analysis* on the
  Reconciliation tab first). Each is joined only when asked for.

Not changed, by the University's earlier decisions: a spillover student stays ACTIVE with the SP mark (no SPILLOVER status);
nobody becomes GRADUATED except by the Senate's approval (a graduation candidate goes on the graduation list); the maximum is the
officer's choice; a record above its computed level is never lowered and a graduated one never touched.

- **Tests:** `LevelCorrectionsIT.everyOneFoundByTheLevelTheyShouldBeAtIsCorrectedAfterACount`; check.sql's V593 block.

## 18. Spillover counted from the final year as the register shows it (V595)

The engine counted spillover from the admission session alone, so a student admitted in 2020/2021 to a four-year programme
read "spillover year 2 (SP2)" in 2025/2026 whatever the register showed. The register showed thousands of them at 400 Level for
the first time in 2024/2025 — the 2020 set lost a year to the closures, others repeated a level or came over with a thin record
— and the University reads them as SP1: on the live-shaped copy, 4,598 of the 5,543 students called SP2 first registered at the
final level in 2024/2025. The University's instruction (20 October 2026): the student is SP1, not SP2; correct every student so
affected.

**The rule now.** The final year is the later of

- the year the count of sessions gives (cohort + length − 1 + deferments, cancelled sessions skipped), and
- the first session the register shows the student at the programme's final level: a course registration submitted, approved or
  locked at that level, or the old portal's enrolment history (`people.enrolment`) at that level.

Spillover years are the sessions elapsed beyond that final year. An approved deferment after the final year still pushes the
completion on. Nothing is counted from before the counted year, so a wrong level on an early registration cannot make a spillover
student. A student with no registration or enrolment at the final level is counted exactly as before. The level the cohort
implies, the rules (R4, R4L), the limit, the fees by the cohort basis (§12), the lifecycle reconciliation (§11) and the level
corrections (§10, §17) all read the position and follow.

**On the live-shaped copy** (54,573 positions): SP1 2,039 → 5,308; SP2 5,543 → 934; beyond the limit 5,489 → 5,078; 1,751
students are no longer in spillover at all (at the final level for the first time this session). Every position is recomputed by
the migration in one set-based pass; the triggers keep them from there.

- **Tests:** check.sql's V595 block (late final year SP1, enrolment-only SP2, no final-level record as before, final year now
  NORMAL, an early wrong level ignored, a deferment after the final year counted); `SpilloverFinalYearIT`.

## 19. Five-year programmes at 500, and level corrections by the level on record (V598)

Every level-dependent part of the portal already reads the programme's own final level (`ref.programme.final_level`):

- the levels Level Management offers (100 up to the final level, never beyond) and the next level it progresses to;
- the session rollover (`people.roll_over_session` stops at the final level);
- the cohort engine's expected completion and SP1/SP2, which start only after the programme's whole length and never because
  of a carry-over;
- graduation candidates at the final level;
- the fee classification (`finance.final_level`).

At V331 the lengths were seeded from the rule then in force: four years unless Law, Pharmacy or Medicine. On the Academic
Office's word (21 October 2026) six programmes the University runs over five years now end at 500: Nursing (C35147), Urban and
Regional Planning (C30468), Radiography and Radiation Science (C49411), Medical Laboratory Science (C49412), Architecture
(C51900) and Environmental Management and Toxicology (C52395). They are set in one statement, so every position is recomputed
once.

On the live-shaped copy, the engine then places 359 Nursing, 293 Environmental Management and Toxicology, 128 Radiography,
79 URP and 31 Medical Laboratory Science students at 500, and many spillover students a year later (a 2020/2021 entrant on a
five-year programme finished in 2024/2025 and is SP1 in 2025/2026). The records below the computed level are corrected on
Level corrections, which now also filters by **Level on record** ("at 400, should be at 500").

The Bursary states the 500-level fee lines these programmes lack; the run's "Fee lines missing at the corrected level" (§16)
lists them.

Other lengths are set on Policy & sessions → programme length (`ref.set_programme_length`) by the Registry.

- **Tests:** check.sql's V598 block; `LevelCorrectionsIT` (by the level on record).

## 20. Records above the final level brought to it; spillover not progressed a level at a time (V601)

A level above the programme's last one (500 or 600 on a four-year programme) is not a level the programme has. Most such records
came from the old portal. Level corrections (V475, V593, V598) never lower a level, so nothing listed them; on the live-shaped copy there
were 37 once V598 set the five-year programmes at 500.

**Student Cohorts → Level corrections → Records above the programme's final level** lists every student in study (not
postgraduate) whose level on record is above the final level as the cohort engine reads it (`people.academic_position.final_level`:
the programme's, or the CCE route's). Each row shows:

- the level on record and the final level;
- the level the engine computes and the spillover position;
- the latest registration, and whether the student holds a registration above the final level in the current session.

The Academic Office or the Registry brings them to the final level — never below it — with **Bring every one found to the final
level** (the faculty, department and search on the screen) or **Bring the chosen**:

- a dry run counts first; the fee effect of the first batch can be read before anything changes;
- a reason is required and kept on each student's cohort history (rule `LEVEL_ABOVE_FINAL`, the levels before and after, the batch);
- the changes run in batches of 500;
- a student registered above the final level this session is left for review unless included in so many words. The registration
  keeps its level; Course Registration support puts it right.

Where the engine's own level is lower than the final level (a student at 600 who should be at 300), that is a separate
correction: the list shows the computed level beside the final one.

- **API:** `GET /api/v1/cohorts/levels/above-final?fac&dept&prog&q&page&size` (counts, `byShape`, rows);
  `POST /api/v1/cohorts/levels/above-final/apply` `{studentIds | fac, dept, prog, q, reason, batch, limit, includeRegistered, dryRun}`;
  `POST /api/v1/cohorts/levels/above-final/fee-effect` (same body).
- **Database:** `people.level_above_final` (view); `people.lower_to_final_level(...)` returns selected, corrected,
  registered_now and remaining.

**Level Management at the ICT desk (V500)** progressed a spillover student a level at a time — a spillover record at 100 could be
moved to 200 — though the screen offered the correction to the final level instead. `people.level_options` now refuses the
progression on the server too (`LEVEL_IN_SPILLOVER`): a student past the programme's length belongs at its final level, by a
correction. The next level is still shown, and `spilloverState` is returned for the screen.

- **Tests:** check.sql's V601 block; `LevelCorrectionsIT` (records above the final level); `StudentLevelSupportIT` (a spillover
  student not progressed).
