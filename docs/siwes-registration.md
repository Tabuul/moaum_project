# SIWES registration and the SIWES fee (V752)

SIWES (the Students Industrial Work Experience Scheme) is registered and paid for on the portal from V752. A student whose
programme takes SIWES in 300 Level Second Semester pays a ₦4,000 SIWES registration fee and registers the programme's SIWES
course. That semester holds the SIWES course alone.

## Who it applies to

The University's decisions of 12–13 November 2026:

- **300 Level, Second Semester only**, for the programmes the Academic Office configures for a session. At deploy these are
  the seven whose 300 Level Second Semester is an attachment semester: Biochemistry, Biology, Chemistry, Computer Science,
  Physics, Plant Science and Zoology.
  - Mass Communication (300 Level First Semester) and Environmental Management & Toxicology (400 Level Second Semester) are
    not part of it.
- **A programme that is not configured keeps V503's rule** as before (the SIWES units, `REG_SIWES_SEMESTER`).
- **School fees still owed are still owed.** The Second Semester school fees must be cleared before the SIWES course can be
  registered. The ₦4,000 is a separate payment, never a school-fee line.
- **An old-portal SIWES payment counts for its session.** A confirmed "SIWES (legacy)" payment, of any semester, settles that
  session's fee.

`registration.siwes_applies(student, session)` is the one test every reader uses. SIWES applies only to a student who meets
all of these:

- an undergraduate outside CCE;
- in study (ACTIVE or PROBATION; a deferred student is not bound);
- at 300 Level in that session;
- in a configured programme;
- in a session whose period is not a draft.

It does not apply to a postgraduate, or to a student who has already passed a SIWES course.

## The student

The dashboard shows a SIWES card, and **SIWES** (`/student/siwes`) walks the student through the steps.

1. **Pay the SIWES registration fee.** This draws a reference for the fee in force and pays it through the usual checkout,
   then shows the receipt.
2. **Clear the Second Semester school fees**, if they are owed. The page says so and links to Fees & payments.
3. **Register the SIWES course.** The course registration is approved as it is made.

Carry-overs and deferred courses wait for a later semester. If the student's registration already holds other Second
Semester courses:

- while add and drop is open, the student removes them on Course Registration;
- otherwise the student uses the reset, which Course Registration offers in a SIWES semester, or asks the Academic Office.

Course Registration sends a SIWES student to the SIWES page. The course form, registration history and documents name the
SIWES course.

## The offices

**Academic Office — SIWES registration desk** (`/siwes/registration`; API `/api/v1/siwes/admin`).

- **Configuration** for each session:
  - the period, DRAFT, OPEN or CLOSED, with the registration and training dates;
  - the programmes;
  - the SIWES course of each programme and curriculum (BMAS or CCMAS).
- Course mappings are standing: courses are never tied to sessions. Each mapped course shows its catalogue state, with a
  warning when it is not LIVE.
- A programme, course or period that students have paid or registered against on the portal cannot be removed or changed
  (`SIWES_PROGRAMME_IN_USE`, `SIWES_COURSE_IN_USE`, `SIWES_PERIOD_IN_USE`). Old-portal payers never lock it.
- **Students** has filters, search, an Excel export and print. **Statistics** counts eligible, paid and registered students
  by faculty, department and programme.
- Readers are held to their scope: an HOD or SIWES coordinator to the department, a dean or faculty officer to the faculty.

**ICT Support and Student edit.** An office can drop an ordinary course in a SIWES semester with no override; the course
waits for a later semester. An office can also drop the SIWES course itself to undo a SIWES registration made in error, and
the fee can then be refunded. The student cannot drop the SIWES course (`SIWES_COURSE_KEPT`).

**HOD.** A standing SIWES registration is never returned or un-approved: `REG_RETURN_SIWES`, `REG_STATUS_SIWES`.

**Bursary.**
- *Fee Setup → SIWES fee* states and publishes the amount, with its history. A drawn reference keeps its amount until it
  expires.
- *SIWES Fee Payments* lists every confirmed SIWES payment, portal and old portal, with its source, gateway reference,
  receipt and bank-check state, and exports it.
- The *credits* panel lists second payments, which are money owed back to the student. From there the Bursar records a
  refund made by hand, reopens one recorded in error, or sends the payment to the refund desk.

## The money rules

- **One fee per session, all or nothing.**
  - The first confirmed payment settles the fee.
  - Any later SIWES payment of the same session is a credit, whether it came from the portal, from an old-portal row loaded
    later, or was already on record when V752 deployed (V752 backfills these).
  - The refund desk refunds a SIWES payment whole or not at all (`REFUND_SIWES_PART`). It never refunds one a SIWES
    registration rests on (`REFUND_SIWES_REGISTERED`).
- **Possible bank double charges (V561).** Two old-portal SIWES payments of one student, session, purpose, Lagos day and
  amount under different payment numbers are held until the Bursary checks with the bank on Old Fees History.
  - While held, the refund desk refuses them (`REFUND_SIWES_CHECK_BANK`), and so do the hand refund
    (`SIWES_CREDIT_CHECK_BANK`) and the payment correction desk (`REALLOC_SIWES_CHECK_BANK`).
  - A record found never received is withdrawn by V561's flow and never settles a fee.
  - The whole day stays held until that withdrawal is approved.
  - A refunded payment is never withdrawn as never received (`PAY_NOT_RECEIVED_SIWES_REFUNDED`), and neither is the only
    payment a registration rests on (`PAY_NOT_RECEIVED_SIWES_REGISTERED`).
- **How a credit was settled is recorded, never read from its note.** It is `finance.siwes_credit.settled_kind`: SETTLES,
  MOVED, DESK_REFUND or HAND_REFUND.
  - The old fees reset keeps a payment whose credit was refunded by hand.
  - It deletes an open or automatic credit with its payment.
  - The reload rebuilds the credit by the same rule.
- **After every bank verdict and withdrawal decision, the rule is applied again** (`finance.siwes_stand_again`), so the
  standing payments and the credits always agree.

## At deploy

V752 does the following when it is applied:

- It moves the old portal's "SIWES (legacy)" payments from category OTHER to SIWES.
- It seeds the current session's period as a DRAFT, so nothing changes for students until the Academic Office opens it.
- It configures the seven programmes, mapped to the course their 300 Level students registered under V503.
  - On the live-shaped copy that gives BCH 300 for Biochemistry (BMAS and CCMAS) and BIO 314 for Biology.
  - BCH 399 and BIO 300, which await board approval, are not used.
- It sets the fee at ₦4,000 and publishes it.
- It credits the second payments already on record. On the live-shaped copy that is 20 student-sessions, 5 of them held for
  the bank check.

**Before opening the period**, the Academic Office should confirm the course mappings on the desk. Six students of the seven
programmes already hold approved 2025/2026 Second Semester registrations, and the opened period treats them as SIWES-bound.

**Locks.** V752 takes its locks without waiting, retrying until the deploy's lock timeout (90 s). It blocks writers to the
13 tables it alters for about one second, never longer.
- If writes never pause for that long, it stops with `V752_LOCKS_BUSY` and names who held the tables. Nothing is half-applied.
- The next deploy runs it again, so deploy at a quieter hour.

Rehearsed on the live-shaped copy as one deploy of V749, V752, V758 and V759: it applies cleanly and `verify.sql` passes.

## Checks

- `db/check.sql` has a V752 block with one property.
- `SiwesRegistrationIT` runs the brief's 14 acceptance scenarios through the API, with access and scope.
- `frontend/src/lib/siwes.test.ts` tests the student page's steps and words.

## Still to come (V762)

The last review found these, to be fixed in V762:

- two refunds of one SIWES payment raised at the same moment can both go through (medium);
- a registration racing a refund approval, or a never-received withdrawal, can both succeed;
- an open credit restored from the archive does not re-apply the rule;
- an old-fees re-upload can move a record of a held pair to another day;
- the reset can split a held pair.
