# ICT Support: student level management, the password reset for every agent, and the phone on tickets (V500)

## The Students Account Officer (V591)

The Bursary's Students Account Officer (V520) holds the level desk too: Student Level Management, Level Change History and
the student finder they need, every student (`SupportAccess.LEVEL_DESK`, the officer's reach "The University" with the
level capabilities only). `people.support_set_level` admits the office; its rules, its record on the cohort decision history
and the support ledger (under the office's own name) are unchanged. Nothing else of the ICT Support Desk opens to the office:
the support record, tickets, password resets, the student's portal and the support overrides stay `AGENTS`, and the screens
offer those links to ICT Support's offices only. See [students-account-officer.md](students-account-officer.md).

## What changed

ICT Support can now settle the common student problems at the desk instead of escalating each one. Two capabilities join
the **baseline**, the set every ICT support agent in service holds across the University (V453). An agent in service is
someone with the `ictagent` office who either was never posted or still has a live posting.

| Capability | What it allows |
|---|---|
| `RESET_PASSWORD` | reset a student's password to the default credential (V485) |
| `PROGRESS_LEVEL` | move a student to the programme's next level |
| `CORRECT_LEVEL` | correct a student's level to another of the programme's levels |
| `VIEW_LEVEL_HISTORY` | read the Level Change History |
| `VIEW_RESET_HISTORY` | read the Password Reset History |

The default credential is the matriculation number, which the student must change at the next sign-in. No e-mail is sent
and the password is never shown.

The Head of the ICT Support Desk, the Director of ICT, admin and super already held every desk capability.

The agent does not become an administrator. These stay outside the baseline:
- the whole support audit;
- exports of student lists;
- record edits;
- the registration override;
- results, fees, payments, admission and matriculation.

A posting may still carry each capability within its own faculty or department scope, as before. An agent taken off the
desk (every posting ended) holds nothing.

| Permission asked for | The portal's capability |
|---|---|
| `STUDENT_VIEW`, `STUDENT_LEVEL_VIEW` | `VIEW_STUDENT` |
| `STUDENT_LEVEL_PROGRESS` | `PROGRESS_LEVEL` |
| `STUDENT_LEVEL_CORRECTION` | `CORRECT_LEVEL` |
| `STUDENT_LEVEL_HISTORY_VIEW` | `VIEW_LEVEL_HISTORY` (or `VIEW_SUPPORT_AUDIT`) |
| `RESET_STUDENT_PASSWORD` | `RESET_PASSWORD` |
| `VIEW_PASSWORD_RESET_HISTORY` | `VIEW_RESET_HISTORY` (or `VIEW_SUPPORT_AUDIT`) |

## The level

**ICT Support Desk → Student Level Management** (`/helpdesk/levels`) works as follows:
- The agent finds the student with the desk's search (`components/support/StudentFinder`, shared with Student Password
  Reset). It searches by matriculation number, JAMB number, application number, name, phone or e-mail, on the server, within
  the agent's reach.
- The same screen opens from the student's support record (*Manage level*), and from a ticket it carries the ticket.

The screen shows:
- the student: name, matriculation and JAMB numbers, faculty, department, programme, programme type, admission session,
  current session, status, study mode and admission route;
- the level the record holds, the session and the semester;
- the programme's levels;
- the level the cohort engine computes, the spillover and graduation state (V331, V475);
- the level each registration carried;
- every earlier change, whoever made it: ICT Support, the Registry's decisions or the cohort corrections.

### The programme's levels

`people.level_options` reads the programme structure. Nothing is hard-coded and nothing is typed in:

| Student | Levels |
|---|---|
| Undergraduate | 100 to the programme's final level (`records.final_level_of`: the programme's configured final level, or the CCE route's where it has one) |
| Postgraduate | the programme's own level only (a Master's 800, a PhD 900, a PGD 700, V455). There is no progression. |

### The two acts, audited apart

| Act | What it does |
|---|---|
| **PROGRESS TO NEXT LEVEL** | moves the student to the next of the programme's levels (`LEVEL_PROGRESS`) |
| **CHANGE/CORRECT LEVEL** | moves the student to another of the programme's levels, chosen from the list, to put a data problem right (`LEVEL_CORRECTION`) |

Both need a reason of ten characters or more, and the agent may name one of the student's open tickets.

### What `people.support_set_level` refuses

| Code | When |
|---|---|
| `LEVEL_STATUS` | the student is not in study (admitted, active or on probation), for example graduated, withdrawn, deferred or suspended |
| `LEVEL_MERGED_RECORD` | the record was merged into another |
| `LEVEL_NOT_IN_PROGRAMME` | the level is not one of the programme's |
| `LEVEL_AT_FINAL` | a progression past the final level (a further session there is a spillover year, not a new level) |
| `LEVEL_IN_SPILLOVER` | since V601, a progression of a student the cohort engine reads in spillover (SP1, SP2 or beyond the limit): the record belongs at the final level, by a correction |
| `LEVEL_PG_PROGRESSION` | a postgraduate progression |
| `LEVEL_UNCHANGED` | the level is the same |
| `LEVEL_SUPPORT_OFFICE` | an office other than ICT Support's or, since V591, the Students Account Officer's (the Registry's own level fix is V475's `apply_level_corrections`) |
| `LEVEL_CHANGED` | the screen showed a level the record no longer holds: someone else changed it meanwhile |

The student's row is locked while the change is written. A second click within a minute from the same agent is
recognised as the same change and does nothing.

### The registration

When the student already has a course registration for the session, the agent is warned before confirming. The warning
names the semester, its state, its level and its courses, and the server refuses until the agent confirms
(`LEVEL_REGISTRATION_ACK`).

The registration is never deleted, and its courses stay as they are. The courses the student may choose next follow the new
level through the programme structure.

**Since V641 a correction carries into the session.** The session's course registrations and enrolment still at the level
corrected from are set to the corrected level, so the examination card, the GST & EPS permit and the receipt print it. The
warning says so for a correction. A progression, and a spillover year, leave the registration's level as it was. See
*A correction carries into the session* below.

### What it never touches

A level change leaves these alone:
- the courses registered, results and scores;
- GPA and CGPA;
- transcripts of earlier sessions;
- matriculation and admission;
- the graduation status.

An examination card or a GST & EPS permit is drawn from the registration when it is printed, so neither is regenerated or
revoked here; after a correction it prints the corrected level.

### Where it is recorded

| Record | What it holds |
|---|---|
| `people.cohort_decision` | the level history the Registry already writes: previous and new level, rule, reason, officer, office; V500 adds the session, the semester and the ticket |
| the support ledger (`helpdesk.support_action`) | `LEVEL_PROGRESSED` or `LEVEL_CORRECTED`, in the module `ACADEMIC_LEVEL`, with the old and new value |
| the ticket's timeline | "Student academic level corrected from 300 to 400", with the reason |

No notice is sent, because no academic-level notice is configured on the notification engine.

**Level Change History** (`/helpdesk/levels/history`) lists every level change within the reader's reach:
- filters: made by ICT Support, progressed, corrected, the Registry's, a student or ticket, dates;
- export: a branded Excel workbook or PDF (S/N first and display only, the header frozen and filterable).

**Password Reset History** now exports in the same way. It shows RESET COMPLETED or ACCOUNT UNLOCKED, never a password.

## The phone on tickets

Every ticket row the desk and the offices read carries `student_phone`. This is the phone the University reaches the
student on (`people.student_reach`: the student's contact, else the admission account's), or a JUPEB candidate's
application phone.

Where it appears:

| Screen | What it shows |
|---|---|
| desk list and office lists | the phone under the requester |
| ticket view (desk and office) | the phone as a link that dials it; *Phone given on the ticket* as well when the ticket's own number differs |
| desk search | matches a ticket by either phone |

The requester's own view and the public tracker never carry it.

## The support ledger's action list

V500 restates `ck_hd_sa_action` and `helpdesk.support_module` from V490's lists, which add `PAYMENT_RECEIPT_REPORTED`, so
V500 does not depend on V490 being applied first. V490 must carry the two level acts as well before it is committed. A
database applies a file it has never seen whatever its number, so a later V490 would otherwise drop them.

## Spillover on Level Management (19 Oct 2026)

A spillover student is not a level: the cohort engine (V331, V475) counts the sessions past the programme's length (SP1, SP2 …, then
the limit the policy allows, two by default) and puts the record at the programme's final level. Level Management now shows it:

- the student search: the level with an **SP1 / SP2 / SP limit** mark, and "should read 400" where the record is still lower;
- the level panel: **Spillover** (e.g. "Spillover year 2 (SP2)"), the expected completion and the graduation state; a note giving
  the sessions past the programme's length against the limit, what to do next, and the last session on record; the **courses
  still owed** (published failures not passed since, `registration.carryovers`);
- where the record reads a lower level (most old-portal spillover records read 100), **CORRECT TO 400 LEVEL (SP2)** opens the
  correction with the final level chosen (the same correction, reason and history as any other; many at once stay on Student
  Cohorts → Level corrections); in the correction the final level reads "400 Level (SP2)";
- **Progress to next level** is not offered to a spillover student: they are not moved one level at a time;
- at the limit, the note says the Registry decides on Student Cohorts → Reconciliation (kept active and flagged, dormant or
  withdrawn); otherwise that passing the courses owed makes the student a graduation candidate there.

The API: `GET /support/students/{id}/level` adds the position's final level, length, spillover years, elapsed sessions, last session,
the policy's limit, and `carryovers` for a spillover student; the support search adds `spillover_state` and `final_level`.

## The spillover years and the levels above 400 (22 October 2026, V628)

The University asked for levels above 400 on Level Management: SP1 and SP2 for four-year courses, 500 for Nursing and Urban and
Regional Planning, and 600 for MBBS.

- **The levels.** The level list runs from 100 to the programme's own final level (`finance.final_level`). That is 500 for
  Nursing (C35147) and Urban and Regional Planning (C30468) since V598, Industrial Chemistry (C22229) since V634, and 600 for
  MBBS (C00061). These were already offered.
- **The spillover years.** A spillover year is not a level. The record stays at the final level, and the cohort engine counts the
  sessions past the programme's length from the expected completion (V331, V595), which the Registry may pin (V612). The
  **Change/correct level** list now has a second group, *Spillover years (past the final level)*. Each choice pins a completion:
  - **SP1**: the completion is pinned to the session before this one;
  - **SP2**: the completion is pinned to two sessions before;
  - **the final year again**, for a student in spillover: the completion is pinned to this session.

  Each choice is offered for every undergraduate programme, past its own final level (400 on a four-year course, 500 on Nursing,
  600 on MBBS), when the session to pin is on the calendar and not before the cohort. The year the student is in now is not
  offered. A note under the list says which completion will be pinned.
- **`people.support_set_spillover(student, year, expected, reason, session, semester, ticket)`.**
  - Offices: ICT Support and the Students Account Officer, as for `support_set_level`.
  - It puts the record at the final level where it reads lower and pins the completion through `people.set_completion_override`.
  - It writes a `LEVEL_SPILLOVER_YEAR` decision on the history ("SP1 (expected completion pinned to 2024/2025): …") beside the
    Registry's `COMPLETION` row.
  - Refusals: another office; a year other than 0–2 (`LEVEL_SPILLOVER_YEAR`); a choice not offered now
    (`LEVEL_SPILLOVER_UNAVAILABLE`); a postgraduate student; a stale screen (`LEVEL_CHANGED`). A repeat within a minute does
    nothing.
- **A correction below the final level lifts a pin.** If the completion was pinned to a session before this one, it is removed,
  because below the final level the student is not past the programme's length.
- **API.** `POST /support/students/{id}/level` takes `action: "SPILLOVER"` with `spilloverYear`, on the `CORRECT_LEVEL`
  capability. The support ledger records it as `LEVEL_CORRECTED`, naming the year and the completion. The student's level history
  and Level Change History show the `LEVEL_SPILLOVER_YEAR` rows; the history's *Made on the level desk* filter includes them.
- Student Cohorts → Level corrections: the *Level on record* filter now lists 600.

## A correction carries into the session (23 October 2026, V641)

The University reported a 100 Level student (entered 2025/2026 by UTME) whose GST & EPS permit card and payment receipt read
200 Level.

**Where the documents read the level.**
- The examination card and the GST & EPS permit print the level on the session's course registration.
- The receipt printed the session's enrolment level, else the arithmetic from the entry session.
- A registration takes the record's level when the student starts it (`registration.student_draft`).

**What went wrong.** Nothing wrote those levels again.
- A level corrected here, or by the Academic Office's level corrections, changed the record alone. The old warning sent the
  agent to Course Registration support, but no support path changes a registration's level (a reset keeps the row and its
  level).
- The session rollover (`people.roll_over_session`, V110) promoted every active, matriculated student below the final level who
  had no enrolment in the target session. Every fresh student here is matriculated at admission, so a rollover into the fresh
  students' own entry session moved them to 200 with a 200 Level enrolment.

**Now:**
- **`people.carry_level_to_session(student, from, to, session)`.** The session's course registrations and enrolment still at the
  level corrected from are set to the corrected level. Courses, results and fees are not touched. The cohort position and the
  CGPA follow through their own triggers.
- **The desk.** `people.support_set_level` carries a CORRECTION into the desk's session. The answer's `carried` gives the
  session and how many registrations and enrolments were set, and `registrationKept` is false. A progression carries nothing.
- **Level corrections.** `people.apply_level_corrections` carries each correction into the University's current session.
- **The rollover.** It never promotes a student into their entry session or one before it, nor past the level their entry
  reaches by the target session (entry level + 100 a session). Those it leaves are counted as `held`, and Session Setup says
  how many.
- **The put-right.** `people.repair_session_levels(session)` ran once for the current session; it is safe to run again. It sets
  two kinds of rows to the level on record:
  - a session's rows left at the level of a correction made in that session, where the record still holds the correction;
  - the rows of a student in their entry session whose record holds the entry level.
- **The receipt.** Every receipt (the student's, the Student Records view, the help desk) reads the session's course
  registration first, as the examination card and the permit do. Then it reads the enrolment, then the arithmetic from the
  entry session.

**For the student reported.** If her record still reads 200, correct it to 100 here (Correct level). Her second-semester
registration and her enrolment follow, and the permit, the examination card and the receipt then read 100 Level. If her record
already reads 100, the put-right has set them.

## A student who changed department is held a level behind (29 October 2026, V696; released by V730)

**Released on 12 November 2026 (V730).** Nothing below holds a student any more; it is kept as the history of the decisions V696
wrote. What stands now is in *A student who changed department continues from the level reached* below.

The University's word: a student who changes department usually steps down one level behind their entry cohort, and should never
read a level ahead of the level they stepped down to. The case reported: a student who entered Accounting in 2023/2024 (matric
…/ACC/23/…), now in B.Ed Guidance and Counselling, whose record read 200 Level and whose 2025/2026 receipt read 300.

**Why the receipt read 300.** The receipt prints the greater of the record and the session's registration, enrolment or the count
of sessions from entry (V672). With no 2025/2026 registration or enrolment, the count from 2023/2024 gave 300. `people.level_in`
falls back on the same count. Nothing on the portal knew she had changed department: the old portal's transfers kept the old matric
and were never migrated as transfers (V669).

**Who changed department** (`people.department_changed`). Either:
- the matric names a department (the third part of BSU/MS/ACC/23/…, a programme's matric code or a department's code) and the
  programme is in none of them; or
- a transfer to the programme from another department is recorded: a completed ACADEMIC_TRANSFER or APPROVED_TRANSFER_RESTORED
  swap, an old-portal transfer, or an effected transfer application.

A matric that names no department is no evidence either way.

**The hold** (`people.hold_department_change`). An active undergraduate (not CCE) who changed department and entered before the
current session:
- is given an effective cohort one session after the session they entered (the cohort desk's override; decision
  COHORT_DEPARTMENT_CHANGE). The academic position counts their expected level, completion and spillover from it, so the level
  desk proposes nothing above it;
- has their record lowered to the level that cohort reaches in the current session, if it is above it (decision
  LEVEL_DEPARTMENT_CHANGE), with the current session's registrations and enrolment (V641's carry).

A student whose cohort is already set, or whose hold was taken off on the cohort desk, is left as they are. Sessions before the
current one keep what was registered.

**What reads it.** `people.cohort_cap` is the level a set effective cohort reaches, in the current session and after.
`people.receipt_level` and `people.level_in` never read above it. The rollover only ever adds one level, so a held student stays one
behind.

**When it runs.**
- Once in the migration, for every student (`people.hold_department_changes`, batch V696-DEPARTMENT-CHANGE). The Academic Office
  or the Registry may run it again; it is safe to run again.
- On every transfer to another department, as it is made (trigger `trg_student_department_change` on the programme), and when an
  old-portal transfer is recorded for a student already on the programme (`trg_prior_transfer_department_change`). A correction
  that puts a student back into the department their matric names is not held. A transfer still reports the level it was made at
  (Free N on the transfer desk says MOVED/200); the hold follows it. V686's check now expects the freed students at 100.

**On the live-shaped copy of 28 October 2026** (rolled back): 566 students held, 87 records lowered (200→100 ×46, 400→300 ×28,
300→200 ×8, 600→500 ×5), every reading of 2025/2026 within the hold. Spillover positions move a year later (SP2→SP1 ×101,
limit→SP2 ×46, SP1→the final year ×25). The 2025/2026 fees stated rise for 82 of them by ₦2.92M in all: the fee follows the record,
and 100 Level fees and a final year's fees are higher than 200 Level fees and spillover fees. 58 who entered before 2018/2019 were
not held: the session after their entry is not on the calendar, and none of them reads above the hold.

**To take a hold off** for one student, remove their cohort on the cohort desk, then correct the level here if it should be higher.

### Never above the hold (29 October 2026, V702; released by V730)

**Released on 12 November 2026 (V730).** The guard, the level desk's refusal, the roll-over's hold and the Bursary's Held Students'
Fees page are gone. The rows the guard wrote (LEVEL_HELD_DEPARTMENT_CHANGE) stay on the history.

V696 lowered the records once. V702 keeps them there, whatever writes a level afterwards:

- **The level desk** (`people.level_options`) gives `heldAt`, offers no level above it, and has no next level while the student is at
  it (LEVEL_HELD_DEPARTMENT_CHANGE). `people.support_set_level` refuses a correction above it with the same code.
- **Anything else** (an upload, a reconciliation, a record edit) that would raise the record above the hold is held at it by the
  trigger `trg_student_hold_level`. The attempt is written down as a decision LEVEL_HELD_DEPARTMENT_CHANGE, with the level asked for.
- **The roll-over** (`people.roll_over_session`) counts the hold in the session it rolls into, so a held student still moves up a
  level each session, one behind their entry cohort.

Only a hold the change of department set counts (`people.department_hold_of`). A cohort the desk set since for another reason is not
a hold. Taking the cohort off on the cohort desk lifts the hold.

**The fees.** A held student is charged the held level's fee (the University's word of 29 October 2026). The Bursary's page Held
Students' Fees (`/finance/department-change-fees`, `finance.department_change_fee_effect`) lists each held student with:
- the charge at the level held;
- what the session would charge without the hold (the cohort as entered, the record at the level V696 lowered it from);
- the difference.

The reading lifts the hold and undoes it, so nothing on a record changes.

## A student who changed department continues from the level reached (12 November 2026, V730)

The University's word of 12 November 2026: release the hold of V696. Most students who change department continue from the level
they had reached in the other department. Those who step down are the ones whose results were not good enough to continue in the
former department. Its decisions the same day:
- every automatic hold is released, and what it lowered is put back;
- a student who changed department reads the level their record shows: the level reached, as the old portal or an office recorded
  it. No rule lowers it, and the count from entry never adds a year above it;
- a step down for weak results is an office's decision, made with a reason, and every reader follows it.

**What was released.**
- The triggers `trg_student_department_change`, `trg_prior_transfer_department_change` and `trg_student_hold_level` are dropped,
  with `people.hold_department_change(s)`, `people.hold_on_department_change`, `people.hold_on_prior_transfer` and
  `people.hold_level_guard`. `people.department_hold_of` is kept but answers no hold for everyone: the roll-over and the MBBS
  own-session roll-over (V733, which edits the roll-over in place) still ask it. A transfer, a swap, a bulk transfer or a restored
  old-portal transfer leaves the student at the level the office gave.
- `people.level_options` no longer returns `heldAt` or the LEVEL_HELD_DEPARTMENT_CHANGE refusal, and `people.support_set_level` no
  longer refuses a level above a hold. The level desk offers every level of the programme again.
- `people.roll_over_session` (not restated) promotes a student who changed department like any other: a level a session, never
  past the level their entry reaches.
- The Bursary's Held Students' Fees page (`/finance/department-change-fees`), its endpoint and
  `finance.department_change_fee_effect` are removed. The session's fee follows the record, so a student once held is charged
  their own level's fee again. On the copy of 21 October, 85 students were charged ₦3.01m more for 2025/2026 under the hold; 66 of
  the 72 who paid had paid their own level's fee.
- Free from the queue (`people.free_old_portal_transfers`, V686) moves a student at the level the Senate Admissions Committee
  recommended, where it did, else at their level.

**The release** (`people.release_department_holds(reason, batch)`). The migration runs it once, as batch
V730-DEPARTMENT-CHANGE-RELEASED. The Academic Office, the Registry or super may run it again with a reason; a second run changes
nothing. A level an office has set since the hold (a progression or correction on the level desk, a spillover year, a cohort the
desk set) is not undone.
- A record V696 lowered, and still at the lowered level, is put back to the level before it, with the session's registrations and
  enrolment it lowered (V641's carry). Decision LEVEL_DEPARTMENT_CHANGE_RELEASED.
- A raise the guard refused, where the record is still at the level it was held at, is made: the level asked for, read from the
  guard's row. Decision LEVEL_HELD_RELEASED.
- Every hold is then lifted where the record reaches the level the entry cohort reaches (COHORT_DEPARTMENT_CHANGE_RELEASED), or
  turned into the level reached where the record is behind it (COHORT_LEVEL_REACHED, below).
- The run is counted in `people.department_hold_release`. V696's and V702's decisions stay on the history.

**The level reached** (`people.align_level_reached`). Some students who changed department have a record behind their entry cohort,
because the old portal stepped them down. With no cohort set, the receipt and `people.level_in` count from entry in a session with
no registration or enrolment (V672), and print a year above the record: the complaint of 29 October. So a student who changed
department, whose record is below the level the entry cohort reaches this session, is given the effective cohort that reaches
exactly the record (`people.cohort_override`, decision COHORT_LEVEL_REACHED, reason "Changed department: continues at the level
reached, …"). The receipt, the level in a session, the academic position, spillover and the level desk then read the record. A
record at or above that level needs none.
- **At the final level** the record cannot tell a first final year from a spillover year (and many final-level records were set by
  V676's count from entry). There the register says when the final level was reached: the first session with a registration or
  enrolment at it, else a level a session on from the last session the register shows below it (never later than the record's
  session). If that is behind the entry cohort, the cohort reaches the final level in that session (reason "Changed department:
  reached the final level, …"), so spillover is counted from it, never from entry. With no register at all, the student is read as
  every spillover student is.
- **The session is kept.** The cohort caps the current session only; once a session closes it is read from its own rows. So where
  the student has no enrolment for the current session, one is written at the record's level (as the calendar's enrol-all does).
- **It follows the record.** The trigger `trg_student_level_reached` aligns the cohort again whenever the level, the programme,
  the entry level or session, the matric or the status changes: a correction on the level desk, a transfer, a swap, the roll-over,
  an edit of the entry. An old-portal transfer recorded for a student already on the programme (V669, V686) aligns too
  (`trg_prior_transfer_level_reached`). The session the level is for is the one the roll-over rolls into or a progression is for
  (V673: a progression is the next session's level), else the latest session the student is enrolled in after the current one,
  else the current session. When the level reached meets its entry cohort's level the cohort is lifted (COHORT_LEVEL_REACHED_LIFTED).
  The record itself is never changed by it.
- **A cohort the desk set by hand is the desk's.** It is never aligned or lifted. `people.level_reached_cohort_of` tells the two
  apart by the cohort and reason of the decision that set it.

**How an office steps a student down.** A step down is an office's decision, with a reason:
- the level desk (ICT Support, the Students Account Officer, the Academic Office, the Registry), or the Academic Office's student
  edit page: **Change/correct level** to the lower level, with the reason and the ticket;
- the transfer committee's recommended level (the Senate Admissions Committee's review), which the transfer's approval and its
  effecting write on the record, and which Free from the queue now honours;
- the level of a programme swap or a bulk transfer (a lower level there needs the row's reason, V587).

For a student who changed department, the step down sets the level-reached cohort where the record falls behind the entry cohort,
so the receipt and the results never print the year above. Nothing needs setting on the cohort desk as well.

**On the screens.**
- The level history and Level Change History name the release: "Hold released: level put back" and "Hold released: the level asked
  for made". V702's guard rows read "Raise held after a change of department (V696)".
- Student Cohorts → the student: the effective cohort reads "(the level reached)" for such a cohort. *Correct the cohort* says that
  it follows the level on the record, that a cohort set there replaces it and stays as set, and that removing it counts the level
  from the entry session again. Its hint says a step down after a change of department is made on the level desk. *Decisions taken*
  names each rule ("Continues at the level reached: cohort …", "Hold released: the entry cohort, …", "Hold released: level put
  back") where it read "Active → Active". A corrected cohort in the lists reads "cohort corrected", not "set by the Registry".
- The student's dashboard: the cohort's note says the record is read with that cohort and the entry session stays.
- Student 360°: **Correct level** announces the level the record reads afterwards, as the server returned it.

### On the live copy

From the migration's notice (`V730 department-change hold released on …`) and `people.department_hold_release`, on a copy of the
University's data with payments to 21 October 2026, at main with V725–V729 (the migration ran in 72 seconds):

| | Count |
|---|---|
| Holds standing | 566 |
| Records put back | 87 (100→200 ×46, 200→300 ×8, 300→400 ×28, 500→600 ×5) |
| Session rows put back (registrations and enrolments) | 80 |
| Raises made | 0 (the guard had refused none on the copy; the live portal may have some) |
| Holds lifted | 197 |
| At the level reached | 369: 244 below the final level (their record), 125 at it (the register's first final year) |
| Left as they were | 0 |
| 2025/2026 enrolments written to keep the level reached | 152 |

What follows for the 566, compared with the same data before V730:

- **Receipts and the level in 2025/2026:** 279 change. 82 follow a record put back (100→200, 200→300, 300→400); 34 whose record
  stands two or more levels behind their entry cohort read the record instead of one level behind the cohort (300→200 ×16,
  400→300 ×7, 500→300 ×8, 500→200 ×3); 87 at the final level read it (500→400) because the register shows this as their first
  final year; 69 at the final level with no register read the count from entry, as every spillover student does (500→600); 7
  whose record stands above the programme's final level read the final level (600→400 ×6, 600→500 ×1).
- **2025/2026 fees:** 107 change — 81 fall (₦2,856,053.72 less in all, mostly the records put back) and 26 rise to the normal
  final-year fee (₦477,650 more in all: the register shows their first final year, where V696 had them in spillover); 25 of those
  26 had already paid that fee (12 in full, 13 the 70% first instalment). Net, ₦2,378,403.72 less. A student who paid at the held level's fee shows as having
  paid more, through the usual overpaid reading.
- **Spillover:** 152 positions move: SP1→normal ×40 (a first final year by the register, or a record two levels behind), SP1→SP2
  ×64 and SP2→limit reached ×46 (at the final level, the register showing no later final year: counted from entry, as before V696),
  normal→SP1 ×2.
- The Registry should look at the 34 records two or more levels behind their entry cohort (some may be stale), and the 46 now at
  the spillover limit; a level or a spillover year is set on the level desk.

## Tests

| Test | What it covers |
|---|---|
| `StudentLevelSupportIT` | an agent in service reads, progresses (once) and corrects a level on the student's ticket; the refusals (outside the programme, a stale screen, a short reason, a withdrawn student, off the desk, another office); the registration kept; the history, ledger and timeline; the reset without a posting; the reset history by its own capability; the phone on the ticket and in the search, not in the student's view |
| `SupportBaselineIT`, `SupportDeskIT` | updated: the reset is in the baseline |
| `check.sql` V500 | two properties (EXPECTED 338) |
| `check.sql` V628 | the levels to 500 (Nursing, URP) and 600 (MBBS); SP1 → SP2 → the final year on a made-up student, as the engine reads them; the choice the student is in not offered; a correction below the final level lifts the pin; the refusals |
| `StudentLevelSupportIT` (V628) | the desk sets SP1 through the API: the record at 400, the engine's SP1, the history row, the ledger |
| `StudentLevelSupportIT` (V641) | a student at 200, registered, enrolled and billed for the session: the receipt reads 200; the warning says a correction carries; corrected to 100, the registration and enrolment read 100 (`carried` 1/1, `registrationKept` false) and so does the receipt; a progression leaves the registration as it is |
| `check.sql` V641 | the desk's correction carries (record, registration, enrolment and `people.level_in` at 100), a progression does not; the put-right sets a fresh student's rows left at 200 and finds none the second time; the rollover into the fresh students' entry session promotes the continuing student and holds the fresh one (EXPECTED 467) |
| `level-management.test.ts` (V641) | the warning for a correction says the registration and enrolment follow; for a progression and a spillover year, that the registration stays |
| `check.sql` V696 | replaced by V730's block below |
| `check.sql` V702 | the hold's part restated for V730: a student once held offered and set the level by the desk, an upload's level standing, the roll-over taking them on |
| `ResultMonitorIT` (V702) | the held students' fees part removed with the page (V730) |
| `level-management.test.ts` (V696) | the two decisions in words |
| `check.sql` V730 | made-up students left as V696 and V702 left them: a record the hold lowered put back with the session's registration and enrolment, a refused raise made, the hold lifted or turned into the level reached (the record, never a year above it), a cohort the desk set left, a second run the same, the Bursary refused; then an office's raise lifts the cohort, a transfer at the level reached sets nothing, a step down after a change of department sets it |
| `level-management.test.ts` (V730) | V702's guard rows and the release's decisions in words, none read as a Registry decision |
| `cohorts.test.ts` (V730) | the cohort desk's decisions in words (the hold, its release, the level reached); a cohort is the level reached's only while its cohort and reason are a level-reached decision's |
