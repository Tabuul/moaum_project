# Flexible carry-over selection (V663)

The University's master prompt of 26 October 2026, "Flexible student carry-over course selection & registration".

## What stood, and what stood in the way

Most of the prompt was already the portal's:

- **Published fails:** a course failed on a published result is a carry-over at whatever level (`registration.carryovers`). Where the semester holds its class, it goes on the draft by itself.
- **No result on the portal:** a course registered in an earlier session with no result here is a carry-over the student declares (V611).
- **No class yet:** such a course is registered all the same, and its class opens as it is added (V655).
- **Minimum units:** a registration of carry-overs alone is submitted below the minimum (V597, `registration.load_kind`).
- **SP1/SP2:** carry-overs are never tied to spillover status.

Two things stood in the way:

1. **Courses with no record here.** A course of the programme below the student's level with no record on the portal at all (the history before 2022 is on the old portal) was not owed. Added through Add Other Course, it came in as a course of another level and counted against the minimum.
2. **One search at a time.** A student found carry-overs one search at a time, behind a grey "+ ADD CARRY-OVER COURSE".

## What V663 does

### The engine

`registration.course_context` gains a declare switch. Where the carry-over picker declares, it owes, beside the published fail and the declared course, a course that:

- the programme binds below the student's level, and not below the level they entered at (a direct-entry student owes nothing beneath it);
- is core, required, borrowed or GST/EPS (never an elective they did not choose);
- is of their track and specialisation;
- has no registration and no result of the student on the portal, nor any for its BSU-/MOAU- twin.

`registration.course_check` judges such a course a carry-over (`CARRY_OVER`) and marks it `CARRY_OVER_DECLARED`, saying "no record of your taking". The University answered that such a course is selectable as declared.

Without the switch (Add Other Course, saving the draft, approval), the same course is a course of another level, as V504 reads it. Once added as a carry-over it stays one.

Nothing places a no-record course on a draft by itself: the menu, and the classes opened when the page is read, use `registration.carryovers` alone.

### The candidates list

`registration.carry_over_candidates(student, session, semester)` lists every earlier course of the student. That is:

- those registered before;
- those the programme binds below their level;
- those owed.

Each course comes with:

- its status (below);
- its level, semester and units;
- the session it was last registered in, and the last grade;
- whether it can be added, with the reason in words.

The other code family's twin is left out, and so is an elective never taken.

| Status | Meaning | Selectable |
|---|---|---|
| `OUTSTANDING` | failed on a published result, not since passed | yes |
| `NO_RESULT` | registered in an earlier session, no result on the portal | yes (declared) |
| `NO_RECORD` | bound below the level, no record on the portal | yes (declared) |
| `AWAITED` | a result is on its way here (a sheet not yet published) | no |
| `CLEARED` | passed on a published result | no |
| `ALREADY_REGISTERED` | on this session's registration | no |
| `NOT_OWED` | registered before, not owed | no |

A selectable status can still be refused by the engine. The common case is a course that runs in the other semester ("it runs in the second semester"): it is listed with that reason and can't be ticked.

### The API

- **`GET /api/v1/me/registration/carry-overs`** returns the student's details and the rows above.
- **`POST /api/v1/me/registration/carry-overs`** takes `{session, semester, courses: [course id…]}`, up to 60 courses.
  - **Identity:** each course is named by its id, never by its code, since a code may hold several courses (V646).
  - **Ownership:** a course that isn't among the student's earlier courses is refused (`CARRY_NOT_YOURS`). One cleared or already registered is refused with its status (`CARRY_CLEARED`, `CARRY_ALREADY_REGISTERED`, …).
  - **The draft first:** the semester's draft is made before anything is added, as the page makes it. A carry-over that the draft places by itself is answered as added.
  - **One at a time:** each course is added through the engine in its own transaction, with the declare switch on and the reason on the audit trail ("Carry-over … added by the student (last registered …) — status"). Any refusal (the GST fee, the unit ceiling, the window) is answered for that course and leaves the others added.
  - **The answer:** the registration as it now stands, `results` (one per course: added, or the code and message), `addedCount` and `refusedCount`.
- Both endpoints are the signed-in student's own (`OFFICE_student`, the student id from the token). An officer is refused.

### The screens

- **Course Registration.** The CARRY-OVER COURSES section has a red ADD CARRY-OVER button and the line "Select courses from previous levels that you have not cleared". It shows the carry-over summary: courses, units, how many from each level, payment status and registration status. The button is also on add and drop.
- **ADD CARRY-OVER COURSES** (`app/student/CarryOverPicker.tsx`):
  - the student's name, matriculation number, programme, level, session and semester;
  - ONLY OUTSTANDING or ALL PREVIOUS COURSES. It opens on all previous courses when no published result shows an outstanding course;
  - search by code, title, level or semester; filters for level (the student's own levels only), semester, and GST, EPS or other;
  - the courses grouped by level, each level opening and closing, with first and second semester under it;
  - a checkbox only where a course can be added, each row with its status and reason;
  - a running "Selected Carry-Over Courses: n · Total Units: x CU";
  - ADD SELECTED CARRY-OVERS, which shows "ADDING CARRY-OVER COURSES..." and can't be pressed twice;
  - the answer: "n carry-over courses have been added successfully", or which were added and which were not and why, with VIEW REGISTERED COURSES and CLOSE.
- **Selected courses.** The table has a Type column: CURRENT, CARRY-OVER or DEFERRED.
- **Student dashboard.** A CARRY-OVER COURSES section with the outstanding count, the registered count and ADD CARRY-OVER, which opens the picker (`/student/register?carry=1`). The carry-over page points to the same place.
  - The picker opens only where a course can still be added: before submission, or in add and drop. On a registration submitted or approved outside add and drop, the link shows a note saying a carry-over is added when add and drop opens, and offers the reset where it is allowed.
- **Staff.** The Head's approval desk shows a CARRY-OVER badge.
- **Course Registration Report.** It reads a Type (CURRENT or CARRY_OVER) beside the category, so CARRY-OVER and GST can be read together (`reporting.course_registration_rows`, restated from V652).

## Payment

There is no separate carry-over fee. The existing gate applies:

- the school fees (or a spillover student's semester fees, V616) before course selection;
- the GST fee for a GST/EPS carry-over (V512), whose refusal is answered on that course.

The summary says whether the payment is VERIFIED.

## Tests

- **check.sql V663:**
  - every status read, and the elective left out;
  - the no-record course owed only where declared, judged and marked as a declared carry-over;
  - without the switch it is a course of another level (V504);
  - two added as carry-overs, then read as already registered;
  - a load of carry-overs alone;
  - the report by type;
  - a direct-entry student owing nothing below their entry level.
- **CarryOverPickerIT:**
  - the list through the API;
  - three added at once, the passed one and another programme's course refused;
  - a second click adding nothing;
  - the carry-over-only registration submitted and approved below the minimum;
  - the report's type;
  - an officer refused.
- **`lib/carry-over.test.ts`:** the views, the search, the filters, the grouping, the selection, the answers and the summary.
