# A spillover student registers carry-overs only (V674)

The University's word of 27 October 2026: spillover students "add only carry over … all the selected courses or chosen courses
should be all carry over and not register as fresh courses … once they add any course it should automatically be carry over course".

A spillover student (SP1/SP2 at the final level, or above it — `finance.is_spillover`) has finished the programme's years and is back
only for what they still owe. Every course they register is a carry-over.

## The rule, in the database

- `registration.spillover_registration(student, session)` — the student is in spillover and the session is the one they are in now
  (`people.student_current_session`, else `policy.university_current_session`) or a later one.
- A trigger on `registration.entry` (`trg_entry_spillover_carry`): any course entered on such a registration — chosen on the draft,
  added, put on by ICT Support, or loaded from the old portal — is `entry_type = CARRYOVER`, `added_as = CARRY_OVER_DECLARED` (the
  student's choice: removable before submission, droppable in add and drop, V611). A carry-over the published results state, a
  deferred and a repeated course are left as they are. Units, status and class are as entered.
- A course already entered as a fresh course on a spillover student's registration of their current session was turned into a
  carry-over when V674 ran.
- An earlier session, and a student not in spillover, are as before.

## The carry-over picker

The picker (V663) listed only the levels below the student's. For a spillover student it now lists the courses of their own level
too (`registration.course_context`, `registration.carry_over_candidates`): a course passed on a published result is "Cleared", one
registered earlier with no result here is "No result", one with no record here is "No record — add it only if you did not pass it".

## The screens

- Course registration (`/student/register`): for a spillover student (`GET /me/registration` → `carryOnly: true`) there is no list
  of the level's core, elective or GST courses and no "Add other course"; a note says every course they register is a carry-over,
  and ADD CARRY-OVER is how a course goes on. The courses added are listed under Carry-over courses, each with Remove.
- Fees & payments: the spillover card's Add carry-over opens the picker (`/student/register?carry=1`); each semester shows the
  courses registered in it (`finance.spillover_panel` → `registeredCourses`). A semester's spillover fee is owed once a course is
  registered in it (V616), and the semester is paid for itself (V664).

## The support desk

ICT Support's drop checks (`registration.support_drop_checks`) let a declared carry-over be dropped, as the student may; one a
published result states is still repeated, not dropped.

## Tests

`db/check.sql` V674; `SpilloverSemesterRegistrationIT.aSpilloverStudentRegistersCarryOversOnly`.

## Only the carry-overs they add, and the semester's fee as they pick (V682)

The University's word of 28 October 2026: a spillover student "should never see list of courses to register, they should only see a
button to add carry overs … all the courses they are adding should carry a status carry over … once a course is selected they must see
the amount they are supposed to pay for that semester". Asked whether the carry-overs their results state should still go on by
themselves, the University chose: the student picks each one.

- **Nothing goes on by itself.** For a spillover registration, `registration.student_draft` makes the registration empty, and a save
  (`registration.student_choose`) places no carry-over either. Before, the draft put every course the published results show failed
  for the semester on the registration as soon as it was made, so adding one course through ADD CARRY-OVER brought all of them, and
  none could be taken off.
- **Each removable before submission.** A save takes off any course the student no longer chooses, a carry-over the results state
  among them; a reset (`registration.student_reset`) clears them all. ICT Support's ticketed additions stay, as for everyone. In add
  and drop, a carry-over the results state is still repeated, not dropped.
- **The page.** Course registration shows no list of courses: the spillover note with ADD CARRY-OVER, and under Carry-over courses the
  courses added, each marked carry-over with Remove. The picker lists the courses the results show failed first (Only outstanding).
- **The fee.** `finance.spillover_semester_quote(student, session, semester)` says what registering a course in the semester costs:
  the semester's own spillover fee, the whole-session spillover item where no semester is registered yet, and — the semester read as
  registered, as the registration gate reads it (V664) — what is still to pay for it. `GET /me/registration/carry-overs` carries it
  as `fee`; once a course is ticked the picker shows the semester's fee and what is to pay (its foot line and a note). If a course of
  the semester is already on the registration, it says the fee is owed already and adding more costs nothing more; in add and drop it
  says to pay first, as the gate requires.
- A spillover draft made before V682 keeps what is on it; the student can now take a course off it.

Tests: `db/check.sql` V682; `SpilloverSemesterRegistrationIT.aSpilloverStudentPicksEachCarryOverAndSeesTheSemesterFee`;
`lib/spillover.test.ts` (the picker's fee words).
