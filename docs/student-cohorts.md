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

Expected completion = cohort + (length − 1) + sessions deferred, cancelled sessions skipped. Spillover years = sessions
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
