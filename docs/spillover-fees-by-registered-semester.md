# A spillover student pays a semester's school fees only when they register a course in it (V616, 21 October 2026)

The University's rule, in the Bursar's words: "only when a spillover student chooses to register a course per semester do they
pay". Until V616 a student in spillover was charged every spillover line of the session's open semesters (V088, V571, V613), so a
student with an outstanding course in the second semester alone still owed the first semester's line.

## 1. The rule

For a student in spillover, on the basis the Bursary set (V571: the cohort engine's count, or the level above the programme's
final one):

- a fee line naming a semester applies once a course registration of theirs for that session and semester holds a course, in any
  state short of dropped — a draft counts: the choice is the charge;
- a line for the whole session applies once any semester of the session is so registered;
- a student not in spillover is charged exactly as before.

`finance.reg_semesters(student, session)` lists the semesters registered; `finance.spill_line_applies(is_spill, line_semester,
reg_sems)` states the rule once.

## 2. Where it is read

| Reader | What changed |
|---|---|
| `finance.charges_of_as` (what a student owes), `finance.due_for_semester` | apply the rule; `charges_of_as(…, true)` gives the lines that could apply, registered or not |
| `finance.fee_stated`, `finance.fee_unstated_semesters` | read the lines that could apply, so the register opens before the first course is chosen and no semester reads "not stated" |
| `finance.fee_profiles(session)` | a spillover student's registered semesters are part of the profile and its key (NULL for everyone else); `fee_profiles()` reads the University's current session |
| `fee_sums`, `session_positions`, `session_charges`, `fee_positions_of`, `registrations_without_fees` | read the profiles for the session asked; the per-student keys now carry the spillover year (V613) and the registered semesters, so two spillover students of one level and year are told apart |
| `registration.student_add` | no longer holds a spillover student's course for the Bursary's clearance — the choice is what makes the fee due; the submission still waits for the semester's fees (`registration.submit_checks`, unchanged) |

Fee Setup, the gap report, the copies and every line stated are untouched.

## 3. What the student sees

- Fees & payments: "In spillover, you pay for the semesters you register" — nothing is charged until a course is registered; the
  charge then appears and the registration is submitted once it is paid. A payment made for a semester never registered is an
  overpayment the Bursary carries or refunds (V506, V519).
- The register: courses are chosen first; the meter and "Pay now" follow once the semester's fee is due.

## 4. Tests

`SpilloverSemesterFeesIT`: a student at 500 Level on a four-year programme with 400 Level (SP1) lines for both semesters and a
whole-session line owes nothing, is stated and cleared until a course is chosen; a second-semester course makes 65,000 due (the
semester's 60,000 and the whole-session 5,000), never the first semester's 70,000; the fees page says so; the submission waits for
the payment and goes through once paid; the profile readers agree; a final-year student not in spillover owes the level's 270,000
as before. `check.sql` V616 does the same in the database alone.
`FeeLinesIT` and `check.sql`'s V613 block register a course in both semesters for their spillover students before reading what is
due, and the fees-import check reads the lines that could apply (`charges_of_as(…, true)`): under V616 a spillover student with no
registration owes nothing.
