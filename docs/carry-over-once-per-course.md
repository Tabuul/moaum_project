# A carry-over once per course (V666)

The University's master prompt of 26 October 2026, "Carry-over deduplication, result clearance & single course-semester registration".

## What was wrong

A carry-over is not stored. `registration.carryovers` reads it from the published results each time. A course is owed when it has:

- a failure on a published sheet (a graded F, or a recorded absence, V422);
- of a course the programme does not hold as an elective;
- with no pass published after it.

It returned one row per failed attempt. A course failed in 2024/2025 and again in 2025/2026 was therefore owed twice. It showed twice on:

- the dashboard and the carry-over page;
- the full record;
- the registration page's carry-over list.

It also counted twice in:

- the completion check behind graduation (`people.lifecycle_completion_rows`);
- the Bursary's spillover list (`finance.spillover_students`).

On the live-shaped copy of 21 October 2026, 274 students had 394 courses shown twice. None had a course failed three times yet.

## What already held

Most of the brief already held, because nothing is stored and everything is read from the results:

- **Only an authoritative result counts.** A result counts once its sheet is published. A sheet still on its way through the chain clears nothing and fails no one. No result is not a failure.
- **Corrections apply.** The latest version of a score is the one read. A result corrected through the amendment chain (V358) clears a carry-over, or brings it back, as soon as the new version stands. Nothing has to be cleared by hand.
- **Uploading twice changes nothing.** The same result uploaded twice is not posted twice (`RESULT_ALREADY_ON_RECORD`, V614). A replaced import is a new version, so nothing is duplicated.
- **A course is registered once a semester.** `registration.entry` is keyed on registration and class, and a registration is unique per student, session and semester. The same course cannot be on one registration twice, however fast the button is pressed. The draft places menu carry-overs with `ON CONFLICT DO NOTHING`.
- **A course is identified by its own code.** A code shared by separate courses (V646) is held under each course's own catalogue code, so they never merge. BSU-/MOAU- twins stay separate courses, as the University decided (V402).
- **Payment.** No fee is charged per carry-over. The spillover fee is per semester registered (V616), and the GST fee per GST/EPS course (V512).

## What V666 does

- **`registration.carryover_attempts(student)`** returns each failed attempt still owed, with the session and semester it was failed in. This is the old reading, kept for the report that needs every attempt (`assessment.absence_carryovers`).
- **`registration.carryovers(student)`** returns one row per course:
  - `failed_in`: the last failure;
  - `attempts`: the failed attempts owed;
  - `first_failed_in`: the first failure.

  The existing columns stay first and in place, so every reader carries on and now reads each course once. That covers the dashboard, the carry-over page, the registration menu and class opening, the full record, the HOD, support and student-edit views, the cohort desk, the completion check, and the spillover panel and list.
- **`registration.carryover_history(student)`** returns every attempt of each course failed on a published result, with:
  - its result: `PASSED`, `FAILED`, `AWAITED` (a sheet on its way), `NO_RESULT` (a published sheet without them) or `REGISTERED` (no sheet yet);
  - whether the course is owed now.

Nothing is deleted or rewritten. Registrations, sheets and scores stay as they are, and the history is read from them.

## The screens

- **Carryover page (student).** Each course carried shows once, with "Failed 2 times: first …, last …" and every previous attempt. A "Cleared since" panel lists the courses failed before and passed since. The data comes from `GET /api/v1/me/carryovers/history`.
- **Dashboard.** Shows "CSC 301 (2025/2026 semester 1, failed 2 times)".
- **Student full record (staff).** "Courses still owed" gains Attempts. A new "Carry-over history" panel shows every attempt of each course, CARRY-OVER or CLEARED. Both are in the Excel download.
- **Carry-over report.** It counted the latest graded attempt of each student and course. It now reads the same rule as the engine: a recorded absence is a failure, and an elective is not owed.

## Not changed

- **Old-portal registrations in both semesters.** On the 21 October copy, 2,259 first-semester courses were registered in both semesters of 2024/2025. These are history from the old portal, not carry-overs. They are left as they are.
- **No reconciliation desk.** No duplicate carry-over record exists to merge, because none is stored.

## Tests

- **check.sql V666:**
  - a course failed in two sessions is owed once, with both attempts and the last failure;
  - a pass published after a failure clears it;
  - an unpublished sheet clears nothing, and once published it clears;
  - a correction to a pass clears it, and a correction back to a fail owes it once again;
  - the second semester and the two courses of one code stay apart;
  - every attempt stays in the history;
  - the registration menu and the completion count read each course once.
- **CarryOverOnceIT:**
  - the dashboard, the results page, the history and the staff's full record each give the twice-failed course once with its attempts;
  - the absence is owed, and the passed course and the elective are not;
  - the carry-over report counts the student once per course owed.
- **`lib/carry-over.test.ts`:** the attempts in words and the history by course.
