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
