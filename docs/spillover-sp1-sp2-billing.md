# SP1/SP2 billed as spillover, by semester (V637, 22 October 2026)

The University's brief asked for semester-based spillover school fees, SP1/SP2 billing and carry-over registration. Its rule:

> A spillover student does not pay school fees for the entire session again simply because the student is in SP1 or SP2. The student
> pays only for the semester(s) in which the student has outstanding carry-over courses.

## What already held

- **Semester billing (V616).** A spillover student owes a semester's spillover lines only once a course is registered in that semester. A whole-session spillover line falls due once any course is registered.
  - One semester registered means that semester's fee alone.
  - Both semesters registered means both semesters' fees.
  - Nothing registered means nothing owed.
- **Spillover fee lines (V613).** The Bursary states spillover lines on Fee Setup by programme, final level, SP year and semester. On the live-shaped copy every 2025/2026 spillover line names a semester: 42 for the first and 42 for the second.
- **Carry-overs.**
  - Carry-overs come from published results and are placed on the registration with **Register** buttons. A missing result is never a carry-over (V421).
  - A carry-over from the old portal can be declared (V611).
  - A registration of carry-overs alone, or of a spillover student, is never held to the minimum load (V597, V615).
- **Payments and windows.** Payments go through the one reference, gateway and verification path, and are matched by the server, never by the browser. The School Fees Payment window applies (V288).

## What was wrong

Who counts as spillover for fees. The Bursary's **LEVEL** basis (V571, in force) put a student in spillover only *above* the programme's final level, for example 500 on a four-year programme.

Since V628 the level desk sets SP1/SP2 differently. It keeps the record **at** the final level, 400, and pins the expected completion; the cohort engine then counts the spillover year. So an SP1 or SP2 student at 400 read as an ordinary final-year student, and owed the **full normal session** once they registered.

On the live-shaped copy that affected 564 students in study at their final level whom the cohort engine places in spillover: 503 SP1, 10 SP2 and 51 past the limit. They were billed ₦47.0m in full sessions for 2025/2026.

## What changed

**Who counts as spillover.** Under the LEVEL basis a student is in spillover:
- above the final level, as before; or
- **at the final level when the cohort engine places them in spillover** (SPILLOVER_YEAR_n, or past the limit).

**The SP year** is the level's distance above the final level. At the final level it is the cohort engine's spillover years (1–3). A student below the final level is never in spillover by level. The COHORT basis is unchanged.

The same rule is restated everywhere it is written: `finance.spill`, `finance.spill_year`, `finance.fee_profiles` (every fee position, report and gap list reads it), `finance.fee_gaps` and `finance.spill_basis_moves`.

**From 2025/2026, as the University chose.** On the live-shaped copy, 604 students are now billed as spillover. Of them, 208 had already paid ₦16.7m against the full-session charge. That money now reads as **paid above what is owed**, and the Bursar carries it into the next session or refunds it on the overpaid desk (V506).

## On the screens

- **Student Fees page and dashboard: the spillover card** (`finance.spillover_panel`).
  - It shows the SP year, each semester's spillover fee, whether a course is registered in it, and the carry-over courses grouped by the session and semester they were failed in.
  - It shows what is owed, paid and still to pay, with **Pay spillover fee** and **Add carry-over**, which opens Course registration.
  - Its heading names what is owed, for example "SP1 – First semester spillover fee", and never a full session.
  - Where the Bursary has stated no spillover fee for the programme, the card says so.
- **The reference and the receipt** read for example "School fees 2025/2026 · spillover (SP1) · first semester" (or second, or both semesters, by the amount).
  - It is still a school-fees payment to every reader (`LIKE 'School fees%'`), so nothing is double-counted.
  - The ledger reads its semester from the words.
- **Bursary → Spillover students** (`/finance/spillover`, `finance.spillover_students`).
  - It lists every spillover student in study for a session, with the SP year, the semesters registered, carry-overs, due, paid, owing and state: no course registered, no fee stated, owes, part paid, paid, or paid above what is owed.
  - Filters: session, faculty, department, SP year, state and search. Downloads: Excel and PDF.
  - It is open to the readers of the School Fees Report. A Dean, Head or the College Finance Controller sees only their own.
- **School Fees Report** gains a **Spillover** column and tile: the students charged the spillover lines, and what they paid and owe. These figures are already within the row's totals.

## Tests

- **check.sql V637**, on a made-up four-year student under the LEVEL basis:
  - at 400 in a normal year, the student is not spillover and owes the full ₦270,000;
  - as SP1, they are spillover (year 1, the same in the fee profile) and owe nothing before registering, while the card shows ₦70,000 and ₦60,000 per semester; as SP2 the year is 2;
  - at 300 the student is never spillover, and at 500 always;
  - the Bursary's list shows the SP1 student as not registered.
- **`SpilloverFinalLevelIT`**, through the API:
  - an SP1 student at 400 who registers in the first semester alone owes ₦70,000, never ₦270,000;
  - the Fees view shows SP1 and the registered semester;
  - the reference reads "· spillover (SP1) · first semester";
  - the Bursary's list shows the student owing ₦70,000, and the School Fees Report counts them as spillover;
  - a normal-year student at 400 owes ₦270,000 and has no card.
- **`lib/spillover.test.ts`** checks the card's wording; **`lib/fee-report.test.ts`** checks the new columns.
