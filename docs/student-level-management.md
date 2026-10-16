# ICT Support: student level management, the password reset for every agent, and the phone on tickets (V500)

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
| `LEVEL_PG_PROGRESSION` | a postgraduate progression |
| `LEVEL_UNCHANGED` | the level is the same |
| `LEVEL_SUPPORT_OFFICE` | an office other than ICT Support's (the Registry's own level fix is V475's `apply_level_corrections`) |
| `LEVEL_CHANGED` | the screen showed a level the record no longer holds: someone else changed it meanwhile |

The student's row is locked while the change is written. A second click within a minute from the same agent is
recognised as the same change and does nothing.

### The registration

When the student already has a course registration for the session, the agent is warned before confirming. The warning
names the semester, its state, its level and its courses, and the server refuses until the agent confirms
(`LEVEL_REGISTRATION_ACK`).

The registration is never deleted or changed. The courses the student may choose next follow the new level through the
programme structure. If the registration must change, the agent uses the existing Course Registration support.

### What it never touches

A level change leaves these alone:
- registrations, results and scores;
- GPA and CGPA;
- transcripts and earlier sessions;
- matriculation and admission;
- the graduation status.

An examination card or a GST & EPS permit is drawn from the registration, so neither is regenerated or revoked here.

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

## Tests

| Test | What it covers |
|---|---|
| `StudentLevelSupportIT` | an agent in service reads, progresses (once) and corrects a level on the student's ticket; the refusals (outside the programme, a stale screen, a short reason, a withdrawn student, off the desk, another office); the registration kept; the history, ledger and timeline; the reset without a posting; the reset history by its own capability; the phone on the ticket and in the search, not in the student's view |
| `SupportBaselineIT`, `SupportDeskIT` | updated: the reset is in the baseline |
| `check.sql` V500 | two properties (EXPECTED 338) |
