# Flexible course registration: other courses, carry-overs and the order of courses (V504)

## What changed

A student is no longer held to the list the portal recommends for their level and semester. The recommended list stays as
it was: the programme's courses at the student's level that run in the semester, the carry-overs and the deferred courses
(`registration.student_menu`). Beside it, the student can now find and add another course themselves, when the University's
own structure allows it, without asking ICT Support.

The same registration engine does the work. There is no second registration system, no second course list and no new
course, programme, result or student table. A course the student adds is an ordinary entry on the semester's registration.

## What a student may add

The **Add Other Course** search on Course Registration opens on the student's own courses: their programme's courses at
every level that run in the session, the University GST/EPS courses and their carry-overs (V507). A level or a category
narrows them. Typing a code or title, or choosing a department, searches every course. The server judges each course it
finds, for that student and that semester (`registration.course_check`). It says the category the course would be
registered in and why it is allowed, or why it is not.

A course may be added when it is one of these:

| Added as | What it is |
|---|---|
| (recommended) | a course on the student's list |
| `PROGRAMME_OTHER_LEVEL` | a course of the student's own programme at another level, including an elective |
| `UNIVERSITY_GST` / `UNIVERSITY_EPS` | a University-wide GST or EPS course |
| `DEPARTMENT` / `FACULTY` | a course of the student's department or faculty, only where the rule allows it (below) |

A course is refused, with the reason shown to the student, when:

| Code | Reason |
|---|---|
| `REG_ALREADY_PASSED` | a published result shows the course was passed |
| `REG_RESULT_AWAITED` | the student registered it before and the result is not yet published ("Result pending"). It is not a carry-over, and it is not registered again. The department settles the result, or ICT Support adds the course on the student's ticket |
| `REG_ALREADY_ADDED` | the course is already on this registration |
| `REG_ALREADY_REGISTERED` | the course is on the registration for another semester of the session |
| `REG_NOT_OFFERED_SEMESTER` | the course runs in another semester of the session, which is named |
| `REG_NOT_OFFERED_SESSION` | the course has no class in the session yet |
| `REG_HIGHER_LEVEL` | the course is taken at a higher level than the student's, and the rule does not allow it |
| `REG_NOT_AVAILABLE` | the course is not part of the student's programme, department or faculty, as the rule allows |
| `REG_OTHER_CURRICULUM` | the course belongs to another curriculum (CCMAS or BMAS) |
| `REG_OTHER_CODE_FAMILY` | the student's cohort registers the course's BSU-/MOAU- twin instead (V402) |
| `REG_OTHER_CATEGORY` | a postgraduate course, for an undergraduate |
| `REG_SIWES_SEMESTER` | only the SIWES course is registered in the industrial-training semester |
| `REG_PREREQUISITE` | a prerequisite is not passed, where the Academic Office enforces prerequisites (V482) |
| `REG_COURSE_INACTIVE` | the course is no longer taught |
| `REG_OTHER_COURSES_OFF` | the Academic Office has closed adding courses beside the list |

While the student owes the GST fee, it holds every course they add, as it already holds every course on the list (V314).

The minimum and maximum units (V495), the registration window, the school fees gate and the submission's own checks apply
as before. The search shows the units the registration would reach and refuses an add past the maximum.

## Carry-overs

Carry-overs come only from published results (`registration.carryovers`). A published F or a recorded absence that has not
since been passed is a carry-over. A course with no result, or with a result still pending, is never a carry-over.

A carry-over that runs in the semester is put on the registration and cannot be removed, at whatever level it was failed,
as before. A carry-over that does not run in the semester is now listed too, under **Carry-over / outstanding courses**,
with the semester it runs in (`registration.outstanding_courses`).

### A GST or EPS carry-over waits for the GST fee (V512)

Being a carry-over does not pass the GST fee. While the student owes the GST fee and has not paid it, a carry-over that is
a GST or EPS course (`catalogue.course` kind GST) is held like any GST or EPS course (`registration.gst_course_hold`, which
reads `registration.gst_gate`):

- it is not put on the draft (`registration.student_draft`, and every save, `registration.student_choose`); one put on
  before comes off a draft while the fee is owed;
- registering it is refused with `GST_PAYMENT_REQUIRED`, naming it a carry-over;
- the screen lists it under **Carry-over / outstanding courses** with **GST/EPS PAYMENT REQUIRED** and **PAY GST/EPS FEE**,
  which opens the existing GST & EPS payment page. It is not counted in the units.

Only a confirmed payment counts (`finance.gst_entitlement`: a reference confirmed by the gateway or the Bursary, less
refunds). A reference generated, a payment page opened or an unconfirmed gateway answer does not. One payment covers GST
and EPS where the Bursary's setting says so. Once it is confirmed, the carry-over goes on at the next save, or the student
presses **REGISTER** beside it. No ICT Support is needed.

The student's other courses go on as the Bursary's setting allows (`finance.gst_setting`):

| Setting | Effect while the GST fee is owed |
|---|---|
| `required_for_gst_eps` | GST and EPS courses, carry-overs included, are held |
| `required_for_all` | the whole registration is held, and the submission refuses it |

Whatever the screen does, the submission still refuses a registration carrying an unpaid GST/EPS course
(`registration.submit_checks`).

A registered GST/EPS carry-over is listed under carry-over, named **Carry-over · GST** (or EPS). It is never listed again
under GST. Its classification stays on the course for the fee, the GST & EPS permit (which carries every GST/EPS course on
the approved registration) and the reports.

`registration.gst_course_event` logs, once each:

| Event | Written when |
|---|---|
| `GST_` or `EPS_PAYMENT_REQUIRED_FOR_REGISTRATION` | a GST/EPS course the student asked for was held on the fee |
| `GST_` or `EPS_PAYMENT_VERIFIED` | the registration first read the confirmed payment, per student and session |
| `GST_` or `EPS_CARRY_OVER_REGISTRATION_ATTEMPTED` | the student asked to register a GST/EPS carry-over |
| `GST_` or `EPS_CARRY_OVER_REGISTRATION_BLOCKED` | that request was held on the fee |
| `GST_` or `EPS_CARRY_OVER_REGISTERED` | the carry-over went on the registration |

The attempt and the hold are written in their own transaction, so they stay recorded when the request is refused. The entry
itself and the payment's confirmation are on the audit spine as before.

## The order of courses

Every list of a registration's courses follows the University's order:

1. carry-over and outstanding courses (deferred courses with them);
2. GST and EPS courses;
3. core courses;
4. elective courses.

The server holds the order (`registration.entry_rank`, `registration.entry_category`) and sends the courses in it, with
each entry's category. The registration screen, the selected-courses summary, the registered courses, the course form,
the examination card and their PDFs all follow it, numbered 1, 2, 3 … without a break.

Core or elective is decided by the programme's own setup (`catalogue.course_offer.basis`), as `registration.is_elective_for`
already decides it. A course the programme takes as core is core here, even when its own department offers it as an
elective. Saving the registration now records the entry's type in the same way.

## Saving, submitting and approval

Adding a course writes it to the semester's draft at once (`registration.student_add_other`), creating the draft if there
is none. Saving the draft keeps every added course that the selection names, and judges it again. A course that no longer
passes the check stops the save with its reason. Once the registration is submitted or approved, a course is added by add
and drop (`registration.student_add`), which now accepts the same courses on the same check.

The automatic approval (V491) approves an added course only while it still passes the check. Otherwise the registration is
held for review (`REG_COURSE_NOT_OFFERED`), never approved blindly. Where the Head of Department approves, nothing changes.

Each added entry records that the student added it (`registration.entry.student_added_at`) and what it was added as
(`added_as`). The registration's audit trail records the change, as for every entry.

## The minimum and the kind of load (V597)

The minimum credit load (the curriculum's, CCMAS 15 or BMAS 18 — V495 — or the level's) bound every submission, so a student
with one 3-unit carry-over and nothing else to register was refused `REG_UNITS_BELOW_MINIMUM`, and so was one with only GST/EPS
courses to sit; with no submitted registration there was no examination card and no GST & EPS permit for them. The
University's brief (20 October 2026): carry-over registration is a path of its own, exempt from the minimum; so is the GST & EPS
permit. Now:

| Kind (`registration.load_kind`) | When | The minimum |
|---|---|---|
| `NORMAL` | a live entry is a current course of the programme — not a carry-over, a deferred or a repeated course, not a GST/EPS course | binds, carry-overs counted in as before |
| `GST_EPS` | no such course; a live entry is a current GST/EPS course | does not bind |
| `CARRY_OVER` | carry-overs and deferred courses alone | does not bind |

`registration.submit_checks` asks the minimum of a `NORMAL` registration only; the maximum, the probation ceiling, the SIWES
semester, the fees and the GST fee bind every kind. A registration with a current course of the programme is judged exactly
as before, so 3 units of current course beside a 3-unit carry-over (6 of 15) is still refused. The Academic Office's
below-minimum list (`registration.below_minimum`, V505) leaves the waived kinds out: they are not below any minimum. The
student's screen counts current courses and carry-overs apart, says "Carry-over registration permitted" (or "GST/EPS
registration permitted") instead of "Minimum not met" where the minimum does not bind, and the API says the saved
registration's kind (`loadKind`). Nothing is stored: the kind is read from the entries, and carry-overs still come only from
published results and go on the draft at every level, SP1 and SP2 included — a carry-over never makes a student SP1 (that is the
cohort engine's, §10 of student-cohorts.md). Tests: `CarryOverRegistrationIT`, check.sql's V597 block.

## The rule

**Course Registration Options** (`/registration/options`) holds the rule. It is set by the Academic Office, the Registry,
the Directorate of ICT or super, with a reason, on the audit trail (`registration.flex_policy`,
`registration.set_flex_policy`).

| Setting | Default | Meaning |
|---|---|---|
| Allow students to add other courses | On | Off: students register only the recommended list |
| Courses a student may add | Programme | Programme: the programme's other levels and electives, and the University GST/EPS courses. Department or Faculty: also the department's or faculty's courses |
| Allow a course of a higher level | Off | On: a course above the student's level may be added |
| Every curriculum's courses open to every student (V590) | On | Off: each student sees and registers only their own cohort's curriculum, as before V590 |

Whatever is set, the engine judges every course a student adds.

### Every curriculum open (V590)

*Oct 2026.* A student's list used to read the programme's structure through the student's cohort:
- a course bound to the programme at a level for one curriculum track (BMAS, CCMAS_BSU, CCMAS_MOAU) was listed only to the
  students of that track;
- a course of one curriculum was listed only to the students of that curriculum, and refused when added beside the list
  (`REG_OTHER_CURRICULUM`);
- a class was opened for a track's courses only where the programme still had a live student of that track.

Where a programme's structure is bound under one track while its students sit in another, whole levels saw few or none of their
courses. With **every curriculum open** (`registration.flex_policy.curriculum_open`, On from V590):
- every student sees and registers the programme's courses at their level, BMAS or CCMAS, whatever their cohort;
- a course added beside the list is judged without the curriculum test;
- the class openers (`registration.open_course_registration`, `catalogue.open_classes_for_courses`, and the CCE and postgraduate
  openers) open the classes for every track's courses.

Nothing else changes: the stream (CCE, postgraduate), the specialisation, the GST/EPS courses already passed, the BSU-/MOAU- code
family of the cohort (one course taught once, registered under one code), carry-overs and deferred courses, the minimum and
maximum load (still by the student's own curriculum), the fee and GST gates, and the approval rule. What a student owes for
GST/EPS (`finance.gst_eps_rows`) is not touched. Turning the switch off (`registration.set_curriculum_open`, with a reason) keeps
the curricula apart again.

## API

| Call | Who | What |
|---|---|---|
| `GET /api/v1/me/registration` | the student | now also carries `outstanding` and `flex`; entries carry `category`, `addedAs`, `studentAdded`, in the University's order |
| `GET /api/v1/me/registration/courses?session&semester&q&level&dept&faculty&category&page` | the student | the search, 20 a page, each course judged |
| `GET /api/v1/me/registration/courses/filters` | the student | the departments and faculties to narrow by |
| `POST /api/v1/me/registration/courses` `{session, semester, offering}` | the student | add a course; the engine refuses with its reason |
| `GET /api/v1/registration/flex` | registration offices | the rule in force |
| `PUT /api/v1/registration/flex` | Academic Office, Registry, ICT, super | set the rule with a reason |
| `PUT /api/v1/registration/flex/curriculum` `{open, reason}` | Academic Office, Registry, ICT, super | every curriculum open, or kept apart (V590) |

The student is always the signed-in student. No student, programme, level, unit or payment is taken from the browser.
