# Results are released by the semester paid for (V667, 26 October 2026)

## What happened

On 26 October 2026 the University asked about a student, BSU/AR/ENG/23/67165, who had paid his school fees but could see none of
his results: "check the conditions for this and release the student result for view".

The student's results page, the broadsheet and both result PDFs used to read one rule: the session's own
(`finance.clears(student, session, 'RESULTS')`). On the live portal that rule is **paid in full**, with a balance carried from an
earlier session blocking everything. Whenever the University's current session was not paid in full, the pages hid **every**
result.

On the live-shaped copy of mid-October, the student's 2025/2026 position was:

- First semester: ₦66,745.00 charged, ₦66,745.00 paid.
- Second semester: ₦28,605.00 charged, ₦14,000.00 paid.

The ₦14,605.00 left on the second semester withheld his 2023/2024 and 2024/2025 results and his 2025/2026 first-semester results.
Those of 315 of the 643 300 Level Arts students who had paid the first semester alone were withheld the same way.

## The rule now

`finance.results_cleared(student, session, semester)` releases a semester's results when:

1. the session's own RESULTS rule releases them, as before (`finance.clears`); or
2. the fees up to that semester are paid (`finance.semester_cleared`: stated, the cumulative due paid, and the semester's own fees
   stated).

Three things are unchanged:

- A balance carried from an earlier session still blocks everything, where the scheme says so (`arrears_block_all`).
- Results are never released where the session's fees are not stated (V361).
- `NEVER_GATED` releases them.

On the copy, the 643 300 Level Arts students had 210 sessions' results released before. Now 554 have their first semester of
2025/2026 released, and the second semester stays with the 210 who paid it.

## What the student sees

The API judges `/me/results` semester by semester. A withheld semester's marks, GPA and CGPA are still redacted on the server. It
is named in `withheldSemesters` with what is outstanding on it (`finance.semester_position`). `clearsResults` is true when nothing
published is withheld.

- **Results.** The page names the withheld semester, for example "Your 2025/2026 second semester results are withheld until its
  school fees are paid", with ₦14,605.00 outstanding and a Fees & payments link. Every other semester shows. A withheld course
  reads "Withheld · fees".
- **Broadsheet.** Every semester paid for is printed. A withheld semester reads "Withheld until the school fees up to the second
  semester are paid: ₦14,605.00 outstanding."
- **PDFs.**
  - The semester statement PDF refuses a withheld semester only.
  - The broadsheet PDF prints the semesters released.

## Tests

- **check.sql V667.** Under results on payment in full, with arrears blocking everything:
  - A student who paid ₦66,745 and ₦14,000 of ₦28,605 has the first semester released and the second withheld, with ₦14,605.00
    outstanding, until paid.
  - An earlier session paid for is released.
  - A balance carried from an earlier session blocks everything.
- **StudentPortalIT** `eachSemestersResultsAreReleasedOnceTheFeesUpToItArePaid`: the same through `/me/results`.
- **lib/results-withheld.test.ts** covers the wording.

## V685: nothing withheld from a student who owes nothing (28 October 2026)

The University's word, on a 300 Level B.A. English student's broadsheet that withheld both 2023/2024 semesters with no amount
outstanding named: "allow all the students that are not owing fee to view their results, no restriction for viewing of result if
the student is not owing anything".

**The cause.** V667 withheld a semester wherever the session's fees were not stated for the student, and read every session through
`finance.fee_stated`, `finance.due_for_semester` and `finance.position`, which match the fee lines to the student's **current**
level (V654's warning: never read a past session through them). While the setup held 2025/2026 alone, an earlier session counted as
"before the schedule" and was released. Once an earlier session's structure is on the setup (the historical school fees), a 300
Level student entered in 2023/2024 is matched to 2023/2024's 300 Level lines: none, so "not stated" and withheld though nothing is
owed (the screenshot); or a 300 Level line, so owing another cohort's fee.

Reproduced on the live-shaped copy with 2023/2024 lines at 100 and 200 Level only: V667 withheld both 2023/2024 semesters with
nothing outstanding; V685 releases them, and still does with a 300 Level line added.

**The rule now.** A semester's results are withheld only where the student owes:

- `finance.results_outstanding(student, session, semester)`: a session before the student's current one is read from the
  historical account (`finance.historical_rows`: that session's lines as the student was then, or an approved assessment, waivers
  netted off, payments allocated first semester first), the semester and those before it; nothing assessed (before the Bursar's
  start, or awaiting review) is nothing owed. The current session as before: its lines against its confirmed school-fee payments.
- `finance.results_arrears(student, session)`: a balance owed for an earlier session, read from the historical account.
- `finance.results_cleared`: never gated → released; for the current session, its RESULTS rule met → released; a balance owed for an
  earlier session blocks everything where the scheme says so (`arrears_block_all`), as before; otherwise released exactly when nothing
  is outstanding up to the semester. **Fees not stated no longer withhold anything.**

A withheld semester is named with `finance.results_outstanding`. A student who owes ₦12,400 for 2023/2024 at the level they were
then sees that semester withheld with ₦12,400.00 outstanding (and, with arrears blocking everything, the later semesters too).
Course registration, examinations and the fees page are not changed.

**Tests.** check.sql V685 (released past results with nothing stated at today's level and with a later level's line; the current
session paid released; fees not stated withhold nothing; owing ₦12,400 at the level then withheld with the amount named and the
current session blocked by arrears). V667's block and `StudentPortalIT` hold unchanged.
