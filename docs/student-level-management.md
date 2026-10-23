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
