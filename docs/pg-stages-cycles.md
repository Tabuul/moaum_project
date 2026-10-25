# Postgraduate stages, cycles, extension, restart and stage-based fees (V651)

The University's master prompt "POSTGRADUATE SCHOOL LEVEL, EXTENSION, RESTART & FEE MANAGEMENT MODULE" asked that a postgraduate
student be read by the stage of their programme (700, 700 Extension; 800 A, 800 B, 800 C; 900 A to 900 E), charged by that stage,
moved on only by the PG School, given an extension only by the Dean, and restarted in a new cycle without losing the old one.

## The structure

`admissions.pg_qualification` holds each qualification with its level, its normal years and its extension years. `admissions.pg_stage`
holds its stages. Both are kept in the database and changed only by the Dean of the PG School (`admissions.pg_set_qualification`).

| Qualification | Level | Normal | Extension | Stages |
|---|---|---|---|---|
| Postgraduate Diploma (PGD) | 700 | 1 year | 1 year | 700 Level, 700 Extension |
| Masters | 800 | 2 years | 1 year | 800 A — Year 1, 800 B — Year 2, 800 C — Extension |
| PhD | 900 | 3 years | 2 years | 900 A — Year 1, 900 B — Year 2, 900 C — Year 3, 900 D — Extension 1, 900 E — Extension 2 |

A programme's qualification is read from its name as before (`people.pg_level_of`: Ph.D. 900, PGD 700, every other 800). Changing a
qualification's years relabels and adds stages; a stage a cycle or a fee line uses is never removed (`PG_STAGE_IN_USE`).

## Cycles: never overwritten

`people.pg_cycle` is a student's academic cycle: cycle 1 from admission, a later one only on an approved restart. One cycle is
ACTIVE at a time. A closed cycle (COMPLETED, GRADUATED, MAXIMUM_PERIOD_EXHAUSTED, CLOSED) keeps its stages and its payments.
`people.pg_cycle_stage` records the stage of each session in the cycle, with how it was recorded (reconciliation, progression,
extension, restart, correction), by whom and why. A correction rewrites the session's row; the audit trail keeps what it was.

## The stage of a session

`admissions.pg_stages_of(session, students)` reads each student's stage:

- the stage recorded for the session, if the PG School recorded one (official);
- otherwise the stage the calendar gives: the cycle's start session, counted forward in sessions (cancelled sessions skipped), from
  the last stage recorded (calculated).

It also says whether the student is **fresh** (the first stage of the cycle: 700 Level, 800 A, 900 A) or **returning** (any later
stage), whether the stage is an extension, whether the cycle is past its maximum period, and a recommendation: normal progress,
extension required, extension, maximum period reached, restart required, completed, closed, not yet begun, cannot be read.

A student with no cycle recorded yet is read as cycle 1 from the admission session until the PG School records it.

## Progression is never automatic

The calendar only calculates. The PG School records:

- `admissions.pg_progress(students, session, reason)`: records the calculated stage. A normal stage needs `MANAGE_PG_PROGRESSION`
  (the Dean or the Secretary). An extension stage needs `APPROVE_PG_EXTENSION` (the Dean alone): for the Secretary the student is
  answered `NEEDS_APPROVAL` and nothing is recorded.
- `admissions.pg_record_stage(cycle, session, stage, source, reason)`: a stage set by hand, kept in order (`PG_STAGE_ORDER`,
  `PG_STAGE_AHEAD`), with a reason of ten characters at least for a correction or an extension.
- `admissions.pg_close_cycle(cycle, status, reason)`: closes a cycle. MAXIMUM_PERIOD_EXHAUSTED is allowed only once the cycle is past
  its maximum period or at its last stage (`PG_CYCLE_NOT_EXHAUSTED`).

## Restart: a new cycle

1. The Head of Department (or the PG School) requests it: `admissions.pg_restart_request(student, start session, reason)` gives
   PG-RST/YYYY/NNNNNN, state REQUESTED.
2. The department recommends or declines it: `admissions.pg_restart_recommend` (UNDER_REVIEW, or REJECTED).
3. The Dean of the PG School approves or rejects it: `admissions.pg_restart_decide`. The officer who requested it may not decide it
   (`PG_RESTART_SAME_OFFICER`); the Secretary may not (`PG_NOT_PERMITTED`). On approval the old cycle, if still active, is closed as
   exhausted, and cycle n+1 opens at its first stage in the start session, so the student is **fresh** again.

An open request may be withdrawn (`admissions.pg_restart_cancel`). Once a restart is approved, the old cycle reads closed in the sessions before the new one begins: nothing more is needed.

## Fees by stage

`finance.fee_schedule` gains `pg_stage` and `fee_category` (FRESH or RETURNING):

- a line for a stage reaches only the students read at that stage; its level is the stage's level, it is never a spillover line, its
  programme must be a postgraduate programme of the stage's qualification (`FEE_PG_STAGE_LEVEL`, `FEE_PG_STAGE_SPILLOVER`,
  `FEE_PG_STAGE_PROGRAMME`), and its category is set by the stage (`FEE_PG_STAGE_CATEGORY`);
- a line for fresh or returning students without a stage reaches the postgraduate students of that category (`FEE_PG_CATEGORY` for an
  undergraduate line);
- a line for the whole level, as before, reaches every stage of it.

Every fee function that matches a line to a student reads the stage and category beside the other facts (`finance.charges_of_as`,
`fee_stated`, `due_for_semester`, `session_fee_total`, `fee_profiles`, `fee_sums`, `fee_positions_of`, `fee_line_usage`,
`fee_line_same_scope`, the session and faculty copies, `pg_unstated`, `edit_fee_line`). So the student's own charge, the bulk
positions and the Bursary's reports agree.

`finance.payment_pg_context` records, when a school-fees reference is generated, the cycle, stage and category it was raised under.

## Reconciliation of existing students

`admissions.pg_cycle_scan(session)` previews the students with no cycle yet: the cycle and stage each would get, with a confidence
(HIGH, MEDIUM, LOW) and notes. `admissions.pg_cycle_commit(students, session, reason)` records them: cycle 1 ACTIVE with the
session's stage, or MAXIMUM_PERIOD_EXHAUSTED for one past the maximum, or GRADUATED for a graduated student. LOW confidence is
skipped. Nothing is changed by the preview.

`admissions.pg_data_quality(session)` lists the problems: no qualification, a level not the qualification's, no admission session,
no cycle recorded, past the maximum period, restart required, a stage calculated but not recorded.

## Who may

`admissions.pg_grant` by office, checked by the API (`admissions.pg_permissions`) and by the functions (`admissions.pg_require`):

| Office | May |
|---|---|
| Dean, School of Postgraduate Studies (`pgschool`), Super Administrator | Everything: the structure, progression, extensions, cycles, restarts |
| Secretary (`pgsecretary`) | Progression (not extensions), cycles, reconciliation, restart requests and recommendations; not the structure, not an approval |
| Head of Department (`hod`) | Read the department's students; request and recommend a restart |
| Academic Office, Registry, Deans, VC, DVC, ICT, Records | Read |
| Bursar, Students Account Officer, Internal and Deputy Audit | Read the structure and the history |

A Head of Department or a faculty Dean acts on their own students only.

## Screens

- **Stages & Cycles** (`/admissions/postgraduate/stages`; the Dean's and the Secretary's menus; "PG Stages & Restarts" for the Head
  of Department): the stage counts, the students by stage (progress, close as exhausted, history), restart requests, the
  reconciliation, data quality and the stage setup (changed by the Dean).
- **PG School dashboard**: fresh, returning, on extension and past the maximum period, and a link per stage.
- **Student full record**, Progression tab: the postgraduate academic history (every cycle, its stages, restarts, the school fees by
  cycle and stage).
- **Fee Setup** (`/finance/fees`): a fee line's Postgraduate stage and Fresh or returning; the **Postgraduate fee structure** panel
  states a stage's components (qualification, programme or all, stage, semester or the whole session, components, total) in one
  step, all or none (`POST /api/v1/finance/sessions/{session}/pg-fee-structure`).
- **The student's fees page**: the stage and whether fresh or returning.

## API

`/api/v1/pg/academic`: `GET /config`, `PUT /config/{code}`, `GET /counts`, `GET /students`, `GET /students/{id}/history`,
`POST /progress`, `POST /stage`, `POST /cycles/{id}/close`, `POST /close-exhausted`, `GET /restarts`, `POST /restarts`,
`POST /restarts/{year}/{seq}/recommend|decide|cancel`, `GET /reconciliation`, `POST /reconciliation/commit`, `GET /quality`.
`/api/v1/finance`: `GET /pg-stages`, `POST /sessions/{session}/pg-fee-structure`; the schedule's lines carry `pg_stage`,
`pg_stage_label` and `fee_category`.

## Not yet

Course registration and the registration menus still read the level, not the stage. Transcripts are not split by cycle. A payment
reallocation (V649) does not read cycles. The fee spreadsheet upload carries a stage since V653 (docs/fee-uploads.md).
