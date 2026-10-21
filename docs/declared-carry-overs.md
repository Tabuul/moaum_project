# Carry-overs a student declares (V611, Oct 2026)

## The problem

- **Where carry-overs came from.** A carry-over (a course to repeat) came only from a published F on this portal
  (`registration.carryovers`).
- **The blocking rule.** A course the student registered before with no published result was refused when they tried to add it
  again (`REG_RESULT_AWAITED`, V504), in case a pass was on its way.
- **Where the results are.** The registrations of 2022/2023 to 2024/2025 came from the old portal, and their results stayed
  there. On the live-shaped copy:
  - 26,930 students hold 417,121 courses of 2024/2025, and only 508 score sheets of that session were ever published here;
  - the student in the report (BSU/AR/ENG/23/67049) held 35 earlier courses, none with a result of hers on the portal.
- **The effect.** Every earlier course read "result pending" for ever, so no carry-over could be added without ICT Support.

## What changes

- **Who may declare.** A course the student registered in an **earlier session** that holds **no result of the student on the
  portal** — no score sheet of it, or a published sheet the student is not on — and that they have not passed, is a carry-over the
  student may declare.
- **How it appears.**
  - It is listed among the student's carry-overs: **Course registration → Carry-over courses → + ADD CARRY-OVER COURSE**, or Add
    Other Course with the category Carry-over.
  - It is judged as a carry-over: the class of this semester, every carry-over rule, and the GST fee gate.
  - Once added it is registered as a CARRYOVER entry marked `added_as = CARRY_OVER_DECLARED` ("a carry-over you declared — no result
    on the portal"). The department, the Student 360° record and the registration show that the student declared it.
- **Undoing it.** A declared carry-over is the student's own, as a course added beside the list is:
  - saving the selection without it lets it go (`registration.student_choose`);
  - a reset clears it (`registration.student_reset`);
  - add and drop drops it (`registration.student_drop`).
  - A carry-over the results state stays, as before, and is never dropped.
- **What still waits for its result.**
  - a course whose score sheet is on the portal and not yet published;
  - a result held (withheld, malpractice);
  - a course registered earlier in the **same** session;
  - a published pass refuses the course as already passed.
- **What doesn't change.**
  - The menu still puts on the registration only the carry-overs the published results state.
  - The minimum load treats a declared carry-over as a carry-over, as the server does at submission (`registration.load_kind`).
  - Approval is unchanged (automatic while the session's rule says so).
- **The Carryover page** says that a course failed on the old portal is not listed there, and points to Course registration.

## Database

V611 restates five functions from their current definitions:
- `registration.course_context` (V504's), which puts the declarable courses in `carry` and takes them out of `awaited`;
- `registration.course_check` (V590's), which marks a carry-over with no published F as `CARRY_OVER_DECLARED` with its why;
- `registration.student_choose` (V518's), `registration.student_reset` (V491's) and `registration.student_drop` (V380's).

`registration.entry.added_as` now also admits `CARRY_OVER_DECLARED`.

## Tests

check.sql V611, `DeclaredCarryOverIT` (the student's own door), and the `lib/course-order` tests.

## Caveat

A student can declare a course they actually passed on the old portal. The entry is marked as declared so the department can see
it, and the department or ICT Support corrects it.
