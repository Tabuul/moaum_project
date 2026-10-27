# The records left at 100 Level corrected (V676)

The University's word of 27 October 2026: "correct the 100 level records".

The old portal's students came over at 100 Level and most were never raised. On the live-shaped copy of 21 October 2026, 10,454
active undergraduate records held 100 Level below the level the cohort engine (V331) computes — entered from 2007/2008 to 2024/2025,
5,238 of them registered above 100 since. Every document, fee line, gate and receipt that reads the record read 100 for a student in
their final year or in spillover.

## What V676 does

`people.correct_levels_from(level, reason, batch)` runs V475's correction — `people.apply_level_corrections`, the same one behind
Student Cohorts → Level corrections — on every record at the level named, a batch of 500 at a time, on all three bases:

| Basis | The level | On the copy |
|---|---|---|
| SPILLOVER | the programme's final level (past its length: SP1, SP2, the limit reached) | 10,317 |
| REGISTRATION | the level the student's own registrations reach | 15 |
| ARITHMETIC | the count of sessions from the entry | 122 |

A level is never lowered. Each change is on the cohort decision history (`people.cohort_decision`, rule `LEVEL_<basis>`, batch
`V676-LEVELS-100`, the reason) and is carried into the current session's registration and enrolment at the level corrected from (V641).
Then the current session's registrations below the level on record are raised (V673), and the courses on a registration of a student
now in spillover, in their current session, become carry-overs they declared (V674). V676 runs it once for 100 Level; it is safe to
run again.

Nothing else changes: status, programme, matriculation number and entry stay as recorded. A student past the spillover limit stays as
the Registry leaves them (V558).

## What follows from it

- **Fees.** The session's fees follow the level. On the copy, 195 of 200 corrected students drawn at random were charged 2025/2026
  school fees at 100 Level (₦34,423,027.66 between them) and are charged ₦537,150.00 once corrected: in spillover a student owes a
  semester's spillover fee only when they register a course in it (V616). The 2025/2026 outstanding figures fall accordingly.
- **Documents.** Receipts, the examination card, the permit and the course form print the corrected level.
- **Registration.** A student now in spillover registers carry-overs only (V674).

On the copy the run takes 83 seconds (21 batches).

## Tests

`db/check.sql` V676.
