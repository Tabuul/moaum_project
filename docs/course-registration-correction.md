# Course registration correction (V772)

The user's master prompt of 15 November 2026, §5: some students are counted as registered for courses they never chose, electives
above all. The Director of ICT now takes one student's wrongly counted course off one registration, with a reason. The University
decided the same day that a course carrying a result is held for the Registry (D4).

## Why

How a course came to be counted that the student never chose:

| Cause | Where it is put right |
|---|---|
| An old-portal upload registered every row it carried | V771: the upload records each row's category; a course already on record under another course of its code is no longer added beside it ([past-results-upload.md](past-results-upload.md)). The courses already counted wrongly are taken off here |
| A dropped course was ticked again on a later save of the registration screen | The registration screen: a course dropped, or taken off by the Director of ICT (withdrawn), starts unticked, so a save never puts it back |
| An elective the record could not tell from a core course became an owed carry-over | V771's Category column (Core, Elective, GST, Carry-over) on every uploaded row; V689 for a failed elective ([failed-electives-not-carry-overs.md](failed-electives-not-carry-overs.md)) |
| No desk could take a course off a closed semester, or one with a mark | This desk. The support desk's and Student Edit's drop keep `SEMESTER_RECORDS` and `NO_MARK` as hard rules, and V702's duplicate resolution needs marks on two classes of one course |

## Who

| Office | May |
|---|---|
| Director of ICT (`ict`), super | find the student, read the registrations, take a course off, cancel a removal awaiting the Registry, undo an applied one |
| Registrar (`registrar`), Deputy Registrar (`dregistrar`), super | read; confirm or decline a removal held for a result |

The database checks the acting office again (`RCR_OFFICE`, `RCR_DECIDER`). The officer who asked for a removal never decides it,
under any office they hold (`RCR_SAME_PERSON`). Any other office (Records, a lecturer) is refused (403).

**Where:** Course Registration Correction, `/registration/corrections` (`?matric=` opens a student):

- the Director of ICT's menu, Academic group;
- the Registrar's menu, Academic group;
- the Deputy Registrar's menu, Students group.

The Registry opens on **Waiting for the Registry**; the Director of ICT and super on **Find a student**.

## The flow

1. **Find the student** by matriculation number, in any case (`GET /student?matric=`). The panel shows the name, matriculation
   number, programme, level and status. A Senate-approved graduate is marked: "Senate-approved graduate — the approved CGPA stays".
2. **Choose the session and semester** from the student's registrations, newest first (each with its level, status and courses
   counted).
3. **Read the registration's courses** (`registration.correction_entries`). Each course shows:
   - the code as taken (and today's code where it differs) and its title;
   - its units and status (counted: approved or registered);
   - its category, with an Elective mark where the course is an elective for the student;
   - how it came onto the registration;
   - its result in words, or No result;
   - any removal and where it stands.
4. **Remove** (a counted course with no removal standing) opens the confirmation (below).
5. **Take it off** (no result) or **Ask the Registry** (a result).
   - Without a result the entry is withdrawn at once: APPLIED.
   - With a result it is held: PENDING. The course keeps counting until the Registrar or the Deputy Registrar decides.
   - The answer names the correction (`RCR-YYYY-NNNNN`) and each removal's state.
6. **Waiting for the Registry** lists every removal held for a decision: the student (a graduate marked), the course with its units
   and how it came, the session, the result, the reason, and who asked and when.
   - **Confirm:** the entry is withdrawn and the mark stays on its sheet as history. A note is optional.
   - **Decline:** the course keeps counting. A note of ten characters or more is required.
   - **Open** takes the officer to the student.
7. **Corrections of this student** lists every correction:
   - the reference (and the request it was made with);
   - the course, the session and level, what the entry was (status and units), how it came, the result and the state;
   - when it was asked and by whom; when it was decided, cancelled or put back, by whom and with what note;
   - the reason.

   The Director's **Undo** cancels a held removal or puts an applied one back, with a reason.

### The confirmation

Before a course is taken off, the confirmation shows:

| Field | |
|---|---|
| Student Name, Matriculation Number, Programme, Level | the student |
| Academic Session, Semester | the registration |
| Course Code, Course Title, Course Unit | the course as taken |
| Registration Status | the registration's status and the course's |
| How it came | read from the record (below) |
| Result | the result in words, or No result |

Then:

- a note: held for the Registrar or the Deputy Registrar ("another officer than you") when the course carries a result; withdrawn
  at once when it does not;
- for a Senate-approved graduate: the CGPA the Senate approved stays;
- **The same course on the student's other registrations**, each with its session, semester, units, type, status and result.
  - Tick one to take it off under the same reason: a carry-over this course's result gave rise to, say.
  - One that is not counted, or has a removal standing, cannot be ticked, and says why.
  - One with a result is held for the Registry too.
- **Why the course is taken off**: ten characters or more, on the record with the officer's name.

### How a course came onto the registration

Read from the entry and its first audit row (`registration.entry_came`), never guessed:

| Value | On the screen | When |
|---|---|---|
| STUDENT | Chosen by the student | the student added it on the portal |
| OFFICE | Added by an office | an office added it (an override, or an office's write) |
| REGISTRY_LATE | Late registration by the Registry | the Registry's late registration |
| OLD_PORTAL | Old portal upload | an old-portal upload added it (V771's ledger, the load's reason, or an imported mark on the class with no audit row) |
| CARRY_OVER | Carry-over the results state | placed because the results state it (not one the student declared) |
| DEFERRED | Deferred course | a deferred course |
| UNKNOWN | Not recorded | nothing on the record says |

## Where a removal stands

| State | On the screen | Moved by | What it means |
|---|---|---|---|
| PENDING | Held for the Registry | the Director of ICT's request, for a course with a result | the course keeps counting |
| APPLIED | Withdrawn | the Director of ICT's request (no result), or the Registrar's or Deputy Registrar's confirmation | the entry is WITHDRAWN |
| DECLINED | Declined by the Registry | the Registrar or the Deputy Registrar, with a note | the course keeps counting |
| CANCELLED | Cancelled | the Director of ICT's undo of a PENDING removal | the course keeps counting |
| UNDONE | Put back | the Director of ICT's undo of an APPLIED removal | the entry is back as it stood (its status before) |

A confirmation is refused when the course has changed on the registration since it was asked for (`RCR_STALE`: no longer counted, or
at other units). Decline it and ask again.

## D4: a course with a result is held for the Registry

A course carrying any result is held for the Registry: any mark on any sitting or version, F or ABS included. The Registrar or the
Deputy Registrar confirms it, never the officer who asked. Confirmed, the entry is withdrawn; the mark stays on its sheet as history
and every version is kept.

Two classes of one course both marked for the student in the semester (a BSU-/MOAU- twin, or a second course under the code) are
not decided here. They go to the Duplicate results page (V702): `RCR_USE_DUPLICATES`. A class that page shows withdrawn is no
second result, so it does not stop a removal: a class whose mark is only a rolled-back upload's history
(`assessment.result_rolled_back`), a class the Director of ICT has already taken off, or one a duplicate resolution withdrew.

## What stays untouched

- The course in the catalogue, the curriculum and the programme structure.
- Every other student's registration, and the student's other courses.
- The mark: it stays on its sheet, as history.
- The removal is recorded with a snapshot of the entry as it stood (`registration.entry_removal`): status, units, category, the
  course as taken, how it came, whether it carried a result (and the result in words), and whether the student is a Senate-approved
  graduate. What a correction recorded is never changed or deleted (`RCR_KEPT`).
- A Senate-approved graduate's approved CGPA, class of degree and award: the graduation audit keeps an approved graduand's figures
  (V771, D3). The CGPA read from the record moves, as the course no longer counts.

## How a removal sticks

Nothing puts the course back on that registration but the Director's undo:

- **The database** (`registration.entry_removal_holds`): while an applied removal stands, an entry's status cannot leave
  WITHDRAWN, nor can the entry be inserted again. A student's save, an office's add or a load is refused with `RCR_REMOVED`
  ("Only that removal's undo, on Course Registration Correction, puts it back").
- **The student's registration screen**: the course is shown removed — "Taken off your registration by the Directorate of ICT",
  pill Removed, its units struck through. It is never ticked, never counted and not offered again.
- **An old-portal upload** reports it `REMOVED_ON_RECORD`, or `REMOVAL_PENDING` while the Registry decides
  (`registration.entry_held_out`), and never brings it back.
- **An old-portal upload's rollback** (V771) leaves a course a correction has been recorded on since the upload put it there —
  asked for, decided or undone (`registration.entry_corrected_since`; the removal's times are clock time): a course the Director
  of ICT put back is not taken off by a rollback, and a registration with a removal on it is never deleted. The rollback lists
  it: "a Course Registration Correction has been recorded on this course since the upload; left as it is".
- **Duplicate results** (V702): a class with a removal pending or applied is not decided there (`DUP_REMOVAL`: "settle that
  first"). The duplicates list shows a class taken off as withdrawn.

## A removed course counts nowhere

- **Transcripts, statements, the CGPA, the broadsheet:** they read only counted entries; a withdrawn entry is not one.
- **The GST/EPS fee readers:**
  - `finance.gst_eps_rows`, `finance.gst_population`, `finance.gst_course_stats` and `finance.gst_unpaid_remind` no longer count a
    WITHDRAWN entry as registered;
  - neither do the GST and EPS offices' lists of a student's registered courses and their course filter (`GstController`);
  - V702's withdrawn twins are passed over too.
- **The ICT result monitor:** a class the Director of ICT took off is no longer an exception. Its kept mark is neither a result
  without a registration nor a duplicate result.

## Documents flagged

When a removal is applied, at once or on confirmation, the student's issued transcripts and statements are flagged for review
(TRANSCRIPT, SESSIONAL_TRANSCRIPT, MINI_TRANSCRIPT, ACADEMIC_STATEMENT) if the class was examined. The flag reads "A course was
taken off the student's registration (RCR-…)". Putting an applied removal back flags them again: "A course taken off the student's
registration was put back (RCR-…)".

## History

- The page's **Corrections of this student**, newest first, and **Waiting for the Registry**.
- The student's change history on Student Edit (`people.student_edit_history`) lists every removal:
  - type REGISTRATION, marked important, from "Course Registration Correction";
  - the course (as taken), session and semester, and what the entry was;
  - where it stands: Withdrawn, Held for the Registry, Declined by the Registry, Cancelled or Put back;
  - the reason, the person and the office.
- Every removal is on the audit spine (`registration.entry_removal` is attached), and every write carries its `X-Reason`.

## Refusals

| Code | When |
|---|---|
| `RCR_OFFICE` | a removal asked for, cancelled or undone by an office other than ict or super (403) |
| `RCR_DECIDER` | a decision by an office other than registrar, dregistrar or super (403) |
| `RCR_REASON` | a reason under ten characters (to take off, or to undo) |
| `RCR_NONE` | no course named |
| `RCR_NOT_FOUND` | no student with the matriculation number; the course is not on this student's registration; no such correction (404) |
| `RCR_NOT_COUNTED` | the course is dropped or withdrawn on the registration, not counted |
| `RCR_OPEN` | the course has a removal already, held or applied |
| `RCR_USE_DUPLICATES` | two classes of the course carry marks for the student in the semester: decide on the Duplicate results page |
| `RCR_SAME_PERSON` | the officer who asked for the removal decides it |
| `RCR_STALE` | the course changed on the registration since the removal was asked for: decline it and ask again |
| `RCR_NOTE` | a decline without a note of ten characters or more |
| `RCR_STATE` | the removal is not awaiting a decision (to decide), or is already closed (to undo) |
| `RCR_REMOVED` | anything but the undo putting a removed course back on the registration |
| `RCR_KEPT` | a correction altered or deleted |
| `RCR_SESSION`, `RCR_SEMESTER` | the courses asked for a session not written YYYY/YYYY, or a semester not 1, 2 or 3 |
| `RCR_LIST_STATE` | the list asked for a state other than PENDING, APPLIED, DECLINED, CANCELLED or UNDONE |
| `DUP_REMOVAL` | (Duplicate results) a class with a removal pending or applied |

## API (`RegistrationCorrectionController`, `/api/v1/registration/corrections`)

| Endpoint | Who | |
|---|---|---|
| GET `/student?matric=` | ict, super, registrar, dregistrar | the student, whether a Senate-approved graduate, and every registration with the courses counted on it; `RCR_NOT_FOUND` (404) when no student |
| GET `/entries?student&session&semester` | the same | one registration's courses (`registration.correction_entries`), each with the same course on the student's other registrations |
| POST `""` `{studentId, entries: [{registrationId, offeringId}], reason}` | ict, super | the removals under one reason (`registration.request_entry_removal`): `{groupRef, graduate, removals: [{id, ref, state, courseCode, session, semester}]}`; 50 courses at most |
| POST `/{id}/decide` `{confirm, note}` | registrar, dregistrar, super | APPLIED or DECLINED (`registration.decide_entry_removal`) |
| POST `/{id}/undo` `{reason}` | ict, super | CANCELLED or UNDONE (`registration.undo_entry_removal`) |
| GET `""?state&student` | ict, super, registrar, dregistrar | the corrections, newest first, 500 at most: of one state, of one student, or all |

Every rule is the database's; nothing in the controller writes an entry.

## Database

| Object | |
|---|---|
| `registration.entry_removal` | one removal: `RCR-YYYY-NNNNN`, the request it was made with (`group_ref`), the entry's snapshot, how it came, the result, the reason, the state, who asked, decided and undid it and when. One live removal (PENDING or APPLIED) for a course on a registration. Audited |
| `registration.request_entry_removal`, `decide_entry_removal`, `undo_entry_removal` | the three acts |
| `registration.correction_entries`, `entry_came`, `entry_result` | the reads |
| `registration.entry_removal_holds` (trigger on `registration.entry`), `entry_removal_kept` | a removal sticks; a correction is history |
| `registration.entry_held_out` | V771's guard for uploads, now reading the removals too |
| `assessment.result_exceptions`, `result_duplicates`, `resolve_duplicate`; the four GST/EPS readers; `people.student_edit_history` | changed in place as above |

## Tests

`RegistrationCorrectionIT`: a made-up student registered, in a session of the run's own, for an elective with no result and a core
course with a mark.

- The Director of ICT finds the student by the matriculation number in any case and reads the registration's courses: how each
  came on, its result. The Registry reads them too; a lecturer and Records do not.
- The elective is taken off at once (APPLIED: withdrawn, every other course untouched).
- The core course, carrying a result, is held for the Registry (PENDING), and asked for once only (`RCR_OPEN`).
- The officer who asked cannot decide it, under any office (`RCR_SAME_PERSON`). The Director of ICT is not a decider, and a decline
  needs its note (`RCR_NOTE`).
- The Registrar confirms it: withdrawn, the mark kept on its sheet. Nothing but the Director's undo puts it back.
- The list reads the Registry's queue and the student's history, newest first. The Director's undo puts the elective back as it
  stood.

`lib/registration-corrections.test.ts` covers the words, what may be asked and the request's body.
