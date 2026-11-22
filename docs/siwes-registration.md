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

It does not apply to a postgraduate, or to a student who has already passed SIWES: the programme's SIWES course, or a 300 Level
Second Semester SIWES course (V776).

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
  - the programmes whose students are on SIWES — a programme is added whether or not its SIWES course is known yet (V776);
  - the SIWES course of each programme and curriculum (BMAS or CCMAS): set here, or — where the programme's Second Semester is a
    SIWES semester — written down from its own structure as it is added; otherwise found and taken with one press;
  - the SIWES courses of the catalogue.
- A course set for a programme is standing: courses are never tied to sessions. Each course shows its catalogue state, with a
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

## SIWES courses, and a programme's SIWES course (V776)

SIWES is not one course. Each department carries it under its own code and title — "SIWES", "Students Industrial Work Experience
Scheme", "Industrial Training", "Industrial Attachment".

- **A SIWES course** is a catalogue course marked as one (`catalogue.course.industrial_training`). A course whose title reads
  SIWES, Industrial Training, Industrial Attachment or Industrial Work Experience is marked as it is added to the catalogue or
  retitled (`catalogue.reads_as_siwes`), whatever its code; V776 marked the ones already there, the ended ones too (a course
  restored later is a SIWES course as it comes back).
- **The SIWES courses panel** on the desk lists them all: code and title, department, level and semester, state, the programmes
  whose structure carries each, the programmes each is the SIWES course of (set, or written down), and the programme semesters it
  makes an attachment semester (V503). A course set as a programme's SIWES course is listed too, though it is not marked. The
  Academic Office (or the Registry) **adds a course** to the list — an existing catalogue course, by its code — or takes one off
  with **Not a SIWES course** (`registration.siwes_mark_course`; API `PUT /api/v1/siwes/admin/siwes-courses`). A course taken
  off stays off while its title stands. It is not taken off (`SIWES_COURSE_IN_USE`) while it is set for a programme on the desk,
  while students who have paid or registered read it, or while taking it off would end a programme's attachment semester in which
  students are registered (they could not submit that semester without it; an elective SIWES-titled course beside the real one
  does not). A row that only came from the catalogue for a programme, where nobody has paid or registered, goes with it: that
  cohort waits for a course again.
- **A programme's SIWES course** is the row `registration.siwes_course` holds for it, for a curriculum or for every curriculum
  (`registration.siwes_course_of`, the one reading every part of the portal uses, unchanged since V752). A course is a 300 Level
  course: **Set course** refuses one the programme carries only at another level (`SIWES_COURSE_LEVEL`) — SIWES registration, its
  fee and its Second Semester are the 300 Level students'.

  **The desk shows what the catalogue offers, and the Academic Office decides.** The catalogue's answer for a programme and
  curriculum (`registration.siwes_course_recognised`) is:
  - a SIWES course the programme's own structure carries at 300 Level, taught in the Second Semester — the curriculum's own
    first, a live one first, then the one of most units (a 1-unit SIWES report beside the 6-unit course is never the SIWES
    course), the programme's own department's first among equal units;
  - else, only for a programme whose structure carries no SIWES course at any level: the one such course of its department that
    no programme's structure carries and no other programme owns;
  - several of equal standing, or none: no answer — it is never a guess; the desk lists the several (**choices**).

  **It is written down by itself in one situation only**, as a programme is added to a session's SIWES (or when a course is added
  to the SIWES courses that gives a waiting programme its own structure's course): where the programme's 300 Level Second Semester
  **is** a SIWES attachment semester — the SIWES course alone, no other required course (V503) — the course comes from its own
  structure, and every waiting curriculum of the programme has one (`registration.siwes_pin_courses`). A programme that takes part
  in a planned or current session whose SIWES period is **closed** is never written down this way, whichever session the act is on
  (the row is the programme's for every session: its cohort would be bound when nobody can pay or register). A programme whose
  curricula have different courses (a BMAS course and a CCMAS course) is written down when the last of them is marked. That is the case of the seven programmes V752 was written for: adding one binds its 300 Level
  students to its SIWES course at once, as a course set by hand would.

  **Everywhere else the desk only shows it.** A programme whose Second Semester also carries required courses (a nursing
  practicum, a SIWES course beside a full load), whose course is the department's, whose curricula do not agree, or whose
  catalogue changes later, is added with no course: its row shows the course **found**, the **choices**, and what the semester
  is (the required courses a bound cohort could no longer register), and one press (**Use it**, which asks for a confirmation that
  says what it binds) sets it. A programme whose SIWES course is a First Semester or a 400 Level course says so — SIWES
  registration and its fee cover the Second Semester of 300 Level only — instead of inviting a Set course that would be refused.
  Saving the period changes nobody's binding.

  **What is written down stands.** A row from the catalogue is held exactly as a set one: it is replaced on the desk, never taken
  away while students have paid or registered (`SIWES_COURSE_IN_USE`), and nothing the catalogue does afterwards — a draft
  course, a structure upload, another course marked or retitled — moves it under students who have paid or releases a cohort
  that has not; where the catalogue would now give another (or the course has ended) the row shows it as **found**. Among a
  structure's SIWES courses the one of most units leads (a 1-unit report is never the SIWES course): where a course labelled for the
  student's curriculum is not also the course of most units, nothing is chosen and the desk lists the several.
- **A programme is added to a session's SIWES before its course is known**, and the period opens with programmes still waiting
  (before V776 both were refused, `SIWES_COURSE_MISSING`, and the desk could set a course only on a programme already added). A
  cohort no SIWES course reaches is not asked to pay or to register until one does; the desk lists it with its number of
  students, and how many of them have paid or registered (those stay bound and wait for the course to be set).
- **SIWES already passed** is a published pass in the programme's own SIWES course, or in a SIWES course of 300 Level — not
  SIWES I at 200 Level or a seminar, now that every SIWES-titled course is marked (`registration.siwes_passed_among`).
- **The fee is unchanged**: whichever course it is, the ₦4,000 SIWES registration fee is paid before the student registers it.

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

**Before opening the period**, the Academic Office should confirm each programme's SIWES course on the desk. Six students of
the seven programmes already hold approved 2025/2026 Second Semester registrations, and the opened period treats them as
SIWES-bound. Since V776 the same care is due when a programme is added to an open period: where its Second Semester is a SIWES
semester, its own structure's course is written down as it is added and its 300 Level students are bound from that moment, so read
the row the desk shows for it; any other programme is added with no course until the Academic Office takes the one found.

**Locks.** V752 takes its locks without waiting, retrying until the deploy's lock timeout (90 s). It blocks writers to the
13 tables it alters for about one second, never longer.
- If writes never pause for that long, it stops with `V752_LOCKS_BUSY` and names who held the tables. Nothing is half-applied.
- The next deploy runs it again, so deploy at a quieter hour.

Rehearsed on the live-shaped copy as one deploy of V749, V752, V758 and V759: it applies cleanly and `verify.sql` passes.

## Checks

- `db/check.sql` has a V752 block with one property, and V776 blocks: programmes added to an open period with no course set; a
  course marked by its title under its own code; each programme's course recognised in its structure or its department, or none;
  who is bound and which cohort waits; a course added to the SIWES courses and taken off, never one in use; the fee still paid
  before registering; a tie never guessed; the department rule shown, never written; a written course standing under students who
  have paid whatever the catalogue does; written only for a SIWES semester and for all curricula or none; saving the period or
  marking a course in a closed period changing nobody; the 300 Level refusal; SIWES already passed; V503's attachment semester.
- `SiwesRegistrationIT` runs the brief's 14 acceptance scenarios through the API, with access and scope.
- `frontend/src/lib/siwes.test.ts` tests the student page's steps and words.

## The last review's findings (V762)

V762 fixes what the last review of V752 found. V752 itself is not changed: V762 replaces the functions involved.

- **One SIWES payment is refunded once.** Two refunds of one payment raised at the same moment (a double submit, or two
  officers) could both go through, giving back ₦8,000 for ₦4,000. Now the refund desk waits for the student's SIWES lock
  before it reads anything of the payment, so the second request sees the first.
  - A refund for more than is left on a SIWES payment is refused, whether it is raised or approved
    (`REFUND_SIWES_GIVEN_BACK`).
  - A refund raised on the desk and the same credit refunded by hand are never both made: the hand refund takes the same
    lock.
- **A registration never rests on money given back or withdrawn.** A student registering at the moment the Bursary approved
  the refund of the payment could end up with both. Every door that refuses because a SIWES registration stands now reads
  that refusal under the student's SIWES lock: the refund desk (`REFUND_SIWES_REGISTERED`) and the withdrawal of a record as
  never received, raised or decided (`PAY_NOT_RECEIVED_SIWES_REGISTERED`). An approved refund is checked again under the lock.
- **One lock order, the registration's.** The refund, withdrawal, archive and payment correction desks take the student's
  record, then the student's SIWES lock, then the payment, in the order the student's registration takes them. In V752 a
  registration and a withdrawal or archiving of its payment could deadlock, and one of the two failed. Now whichever comes
  second waits for the first and then sees what it did. The student's SIWES lock itself takes the student's record first,
  whoever takes it, so a gateway confirming a second SIWES payment (which writes the student's credit) no longer deadlocks
  with the student registering.
- **When a deadlock can still happen, the portal tries again.** A few writes change a SIWES payment's record before they
  take the student's SIWES lock: the old fees reset, an old fees upload, a gateway confirmation. An old fees upload also takes
  several students' SIWES locks in the order of its file. If one of them and a desk act on the same payment at the same moment,
  the database stops one of the two and keeps nothing of it. The desks (the bank check, the bank list and the decision of its
  withdrawals, and a withdrawal raised, decided or cancelled, among them), the student's SIWES registration, the old fees
  upload and reset (and their approvals), and the withdrawal of old-portal doubles then try again: up to four tries in all
  (the first and three more), each in a fresh transaction (`DeadlockRetry`). The officer sees the answer, not an error.
  - What is tried again: a deadlock, a serialization failure, and a lock not had in time. A statement stopped for running too
    long, and a refusal, are never retried.
  - A confirmation of a payment (by a gateway, or by the Bursary by hand) is not tried again by the portal. One that is
    stopped keeps nothing, and the payment waits unconfirmed until it is confirmed again.
  - Inside the bank list, and inside the decision of its withdrawals, a deadlock stops the whole list or decision, which is
    then tried again. Before, it was recorded as a group or a withdrawal refused ("deadlock detected"), and the rest was
    kept.
- **An open credit that comes back settles the fee when nothing else does.** A payment restored from the archive, or moved
  back by a reversed correction, could leave the fee paid by an open credit. Now the oldest open credit settles it, as
  everywhere else.
- **A group the bank check holds stays together.** For an old-portal SIWES record the bank check holds with its day's group:
  - An old-fees upload no longer moves the record to another day. It keeps the day, as it keeps an archived record's. A
    payment number the file gives is still attached to the record; a row without one is reported as already on record.
    The record the bank received stays held while its partner waits, and the Bursary can check that day with the bank
    again.
  - The old fees reset keeps the record, so a reload never gives the reference the check names to the other payment, and a
    waiting withdrawal can still be decided.
  - A record is held this way when a check found it never received, when it shares the day of such a record not yet
    withdrawn, or when a withdrawal of its day waits or was rejected.
  - An upload that moves a record and the Bursary's bank check of that record's day, made at the same moment, are decided
    one after the other: both take the student's SIWES lock first. Either the check sees the record on its new day, or
    the upload sees the check and keeps the day.
  - The same holds for the Bursary's bank list. Before it reads the possible double charges of its days, the list takes the
    SIWES locks of the students whose SIWES groups it will judge, one after another in a fixed order (by student, then
    session). If a record is moved into its days while it waits, it takes that student's lock too and reads again.
  - The decision of the withdrawals a list raised first locks every one of them that still waits, in the order of their
    numbers (the order it decides them in). A withdrawal decided or cancelled by itself locks the withdrawal first and the
    student's SIWES lock after it, so the list takes them in the same order, and the two never wait on each other in a
    circle. Then the decision takes the students' SIWES locks, by student, then session, before it decides any, whether it
    approves, rejects or cancels them. These are the locks each withdrawal takes as it is decided: its own student's, and,
    for an approval, its payment's (the same one unless the payment was moved after the withdrawal was raised). (V762's
    third review found that approving a list's withdrawals while one of them was cancelled by itself could end in a
    deadlock, and the cancel did not try again, so the officer saw the error. The cancel now tries again too.)
  - Recording a list and deciding a list's withdrawals now take several students' SIWES locks in that one order. Before
    V762's fourth review, a rejection or a cancellation took each student's lock only as it reached that student's
    withdrawal, in the order of the withdrawals' numbers, which follows the students' names. So two lists over the same
    two students, one approved or recorded while the other was rejected or cancelled, could wait on each other. The
    database stopped one and the portal tried it again, so nothing was lost, but the clash was needless. An old fees
    upload still takes its students' locks in the order of its file; if it meets a list that way, it is tried again.
  - `db/check.sql` holds this order: the withdrawals locked, then the SIWES locks taken, neither under a condition, before
    any withdrawal is decided.
- **The newer check decides.** When the check that named a record never received and the check of its current day disagree
  (a record moved before V762), the newer one decides. A newer check that found the record received releases it, and the
  other record of its old day no longer waits on it.

**At deploy.** V762 only replaces functions and adds two. It locks no table, and no writer waits on it: on a copy of the
live-shaped database it applied in 0.4 s while a payment write and a student's SIWES lock were held open, and other
writers waited no longer than usual.

`db/check.sql` has a V762 block with one property. `SiwesRegistrationIT` checks it through the API: two refunds of one credit raised
at one moment, two approvals at one moment, a third refund of the payment given back, and a hand refund racing a refund raised on the
desk. Each time one goes through and the other is refused with its code. On the refund desk, the hint beside the amount now says that
a SIWES fee is refunded once, and that more than was paid is refused. `DeadlockRetryTest` checks the retry: a deadlock is run
again until it goes through; when all four tries meet one, the last clash is reported; and a refusal is never run again. It
also reads each error as the portal's database layer reports it: a deadlock, a serialization failure and a lock not had in
time are run again, and a statement stopped or a refusal is not. `DoubleChargeIT` meets a deadlock in the bank list, in the
decision of its withdrawals and in the cancelling of a withdrawal through the API: each is run again, the group is checked, its
withdrawal approved or cancelled, and nothing is recorded refused. The check.sql block raises a deadlock, a serialization failure
and a lock not had in time inside the bank list's loop and inside the decision's (a trigger of its own, undone with it): each
ends the whole call with its code, while any other error is still recorded as a refusal.
