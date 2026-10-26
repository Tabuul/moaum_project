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
