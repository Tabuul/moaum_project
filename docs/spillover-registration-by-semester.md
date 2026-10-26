# A spillover student's registration is held to the fee of the semester it is for (V664, 26 October 2026)

The University's master prompt of 26 October 2026 ("Semester-sensitive spillover payment, carry-over detection & course
registration") reported this. A spillover student paid the first semester's spillover fee and registered first-semester
carry-overs. They then registered second-semester courses without paying the second semester's fee.

## 1. What already held

- **Charged per registered semester (V616).** A spillover student owes a semester's spillover lines only once a course of that
  semester is on a registration of theirs. A whole-session line is owed once any semester is. No semester is charged for being SP1
  or SP2.
- **Payments count once against a running total.** The registration gate compares the session's confirmed school-fee payments
  with the amount due up to the semester (`finance.due_for_semester`, `finance.semester_cleared`). So the first semester's
  ₦70,000 covers the second semester only if more than ₦70,000 was paid. A GST payment, or any payment that isn't school fees,
  counts for nothing.
- **Submitting waits for the semester's fees.** `registration.submit_checks` does this for everyone.
- **Carry-overs by semester.** Carry-overs are found from the results, by the session and semester they were failed in, and are
  added with ADD CARRY-OVER (V663). The minimum load doesn't hold a spillover student or a registration of carry-overs alone
  (V597, V615).
- **The Fees page.** It shows each semester's spillover fee (V637).

## 2. The hole: two doors

1. **Adding to a registration already submitted or approved.** V616 stopped `registration.student_add` holding a spillover
   student's course for the fee. That is right on a draft, because the submission waits for the fee. But a course added to a
   registration that is already submitted or approved (in add and drop, through the carry-over picker, or by ICT Support on a
   ticket) is registered at once. No submission comes after it.
2. **Submitting an empty registration.** A spillover student could submit a registration with no course on it, because the minimum
   doesn't hold them. With no course of the semester on it, nothing of the semester was owed. So the second semester was approved
   empty, and its courses came later, in add and drop, unpaid.

## 3. What V664 does

| Piece | What it does |
|---|---|
| `finance.semester_position(student, session, semester, registering)` | Gives due up to the semester, paid, outstanding (nothing under ₦1) and cleared: the gate's own figures. With `registering`, it reads the semester as it stands once a course of it is on the registration. It does this through `finance.reg_semesters`, which reads the `moaum.registering` setting for that one call and puts it back before returning. |
| `registration.semester_fee_gate` | Holds a spillover student's course on a submitted or approved registration until the semester is cleared. The refusals are `REG_SEMESTER_FEES_DUE` with what is outstanding, due and paid, or `REG_FEES_NOT_STATED` / `REG_SEMESTER_FEES_NOT_STATED` when nothing is stated. |
| `registration.student_add` (restated) | Reads the gate for every add path: add and drop, the carry-over picker, ICT Support. A draft is handled as before: the choice makes the fee due, and the submission waits for it. A student not in spillover is held by the Bursary's clearance, as before. |
| `registration.submit_checks` (restated) | The refusal names the figures, for example: "the second semester school fees for 2025/2026 are not fully paid: ₦60,000.00 outstanding (₦130,000.00 due up to the second semester, ₦70,000.00 paid). Second semester registration requires payment of the second semester spillover fee; a payment for another semester does not cover it". A registration with no course on it is not submitted where no minimum would stop it (`REG_NO_COURSES`). |
| `registration.support_add_checks` (restated) | The offices' preview reads the same semester fee. |
| `finance.spillover_panel` (restated) | For each semester: its own fee (`owed`), the payments applied to it (`paid`), what is left (`outstanding`), what is still to pay for it to clear (`toClear`, which includes anything earlier left unpaid), whether it is `cleared`, and its `status`. The whole-session item is paid first (`sessionOwed`, `sessionPaid`), then the first semester, then the second: the order the gate reads them in. |
| Data | A spillover student's registration that was submitted or approved with no course on it, in a semester not closed, becomes a draft again. A reset record (Academic Office, with the reason) keeps what it was. Its courses now wait for the semester's fee. |

The semester states are:

- `PAID`: ready for registration.
- `PART_PAID` and `PAYMENT_REQUIRED`: payment required, with exactly what is left.
- `NOT_STATED`: no line of the semester's own and no whole-session item.
- `NOT_REGISTERED`: there are carry-overs from the semester but nothing is registered yet. Nothing is owed until a course is saved.
- `NOTHING_OWED`: no carry-over and nothing registered.

## 4. What the student sees

- **Course Registration.**
  - It shows the semester being registered on its own, for example "SECOND SEMESTER PAYMENT REQUIRED", with the second semester's
    spillover fee, what is paid, what is outstanding, and **PAY NOW ₦…**.
  - Before a course of the semester is saved, it says nothing is owed for the semester until one is, and what the fee will be.
  - Once paid, it says "SECOND SEMESTER SPILLOVER FEE PAID".
  - A spillover student whose semester fee is unpaid keeps the registration page, so the draft can still be changed, instead of a
    page that hides the draft.
- **Fees & payments and the dashboard.** The spillover card lists each semester's fee, paid, outstanding and state. Its Pay button
  names the semester and the amount ("Pay second semester fee ₦60,000.00"). It also says each semester is paid for itself.
- **A refused add or submission** (add and drop, the carry-over picker, ICT Support) says the amount.

## 5. Unchanged

- A whole-session spillover line, where the Bursary states one, is owed once any semester is registered and covers the session.
- Nothing is charged for a semester the student registers nothing in.
- Payments remain one school-fees account for the session. A payment the Bursary finds against the wrong session or purpose is put
  right with Payment Reallocation (V649), never by editing the payment.
- GST and EPS courses, the exam card, the minimum-load exceptions, and how students not in spillover are charged and held are all
  unchanged.

## 6. Tests

- **check.sql V664.** A made-up student at 500 Level (SP1 by level), with ₦70,000 and ₦60,000 semester lines:
  - The first semester is paid. A GST payment of ₦60,000 counts for nothing.
  - The second semester, approved empty, refuses a course with ₦60,000.00 outstanding (₦130,000.00 due, ₦70,000.00 paid). The
    offices' preview agrees, and the setting is put back.
  - An empty registration is refused `REG_NO_COURSES`.
  - The draft is refused with the figures. Part paid, it reads `PART_PAID` with ₦30,000.00 left. Paid, it clears and the course
    is added.
  - The panel reads each semester's figures.
  - A whole-session ₦150,000 line, paid once, covers both semesters.
- **SpilloverSemesterRegistrationIT** follows the same story through the API: `/me/registration`, `/me/registration/add`,
  `/me/registration/submit` and `/me/fees`. A second press adds and submits nothing twice.
- **lib/spillover.test.ts** covers the wording: a semester's own payment, part paid, and nothing owed.
