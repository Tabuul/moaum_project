# Spillover students: no automatic GST fee, and electives allowed (V711)

The University's word of 30 October 2026, with a 400 Level spillover student's dashboard (B.Sc. (Ed) Computer Science, entered
2019/2020; GST & EPS: "Required for EPS 302 in 2025/2026", NOT PAID, PAY GST FEE):

- "spill over student should not automatically see gst fee to pay except they are having carry over from the uploaded results, free
  all spill over student from auto gst fee payment unless they add it as carry over";
- "also allow spill over students to add elective courses".

## Why the fee was asked

The GST/EPS engine (`finance.gst_eps_rows`) owes a student the GST fee for any of three reasons:

- a GST/EPS course failed on their record (a carry-over);
- the programme's GST/EPS course at their level, not yet passed;
- a GST/EPS course on this session's registration.

A spillover student sits at the final level (SP1/SP2) or above it. Where the programme binds a GST/EPS course at that level (EPS 302
at 400 Level, for many programmes), the second reason owed them the fee for a course they never chose. The dashboard and the GST page
then asked for it (`finance.gst_payable_courses` shows the level's courses too).

## What changed

- **Not owed in spillover.** For a student in spillover in the session they are at now (`finance.spill`'s rule: the cohort engine's
  spillover state on the cohort basis; on the level basis, above the final level or at it in SP1/SP2), the programme's GST/EPS course
  at their level is not owed. Its status reads `NOT_OWED_SPILLOVER` ("Not owed in spillover — add it as a carry-over to take it"),
  and the reason reads `SPILLOVER_NOT_OWED`, on the student's GST page and on the GST and EPS desks.
- **Still owed:** a GST/EPS carry-over from their results, as before, and a GST/EPS course they add to their registration (then
  read as owed for being on the registration).
- **Nothing shown to pay for.** A spillover student is shown no GST/EPS course to pay for, so the dashboard's GST card does not
  appear. The courses of their own level join the ones below as courses they may add as a carry-over (`finance.gst_carry_payable`):
  the GST page offers the payment, the carry-over picker holds such a course until the fee is paid, and the fee is taken for it.
  They pay when they add one, never before.
- **Electives.** V674 made every course a spillover student registers a carry-over. An elective now stays an elective
  (`registration.entry_spillover_carry`): a fresh course of their choice, never a carry-over (a failed elective is an F: V689).
  The registration page shows a spillover student the programme's electives beside ADD CARRY-OVER. Core courses of their level are
  still carry-overs.
- Everything that reads the engine follows: eligibility, the registration gate, the GST fee's reference, the desks' lists and
  dashboards, the master report.

## Speed

The desks read the engine over the whole register. Asked student by student, the spillover test cost the whole-register read
about a second, and joining it into the engine's own reads changed their plan. So the spillover students are worked out once,
apart from the engine's reads: the basis and each programme's final level read once, the spillover state looked up only for a
student it can decide (7,728 index reads, about 0.3 s, on the live copy of 21 October 2026).

## Checked

- check.sql V711:
  - A made-up four-year programme binds an EPS course at 400 Level. A student at 400 Level in SP1 does not owe it: shown nothing to
    pay for, offered it as a carry-over. A student at 400 Level within the programme's years owes it as before.
  - Added to the spillover student's registration, the course is owed, for being registered.
  - An elective the spillover student chooses stays an elective; a core course beside it becomes a carry-over.
  - On the cohort basis, a student in a spillover state below the final level is in spillover too.
- On the live copy of 21 October 2026 (rolled back): of 103,440 rows, the only ones changed were four spillover students' EPS 302,
  now not owed; nothing else changed. That copy predates V637's SP1/SP2 reading, so on the live database today more spillover
  students at the final level are freed.
- `SpilloverSemesterRegistrationIT.aSpilloverStudentOwesNoGstUntilAddedAndMayAddAnElective`: the GST page through the API
  (not required, nothing payable, offered as a carry-over, the course's status and the reason); the elective saved as an
  elective and the core course as a carry-over.
