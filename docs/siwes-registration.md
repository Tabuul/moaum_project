# SIWES registration and the SIWES fee (V752, V777)

SIWES (the Students Industrial Work Experience Scheme) is registered and paid for on the portal from V752. **Every SIWES
course carries the ₦4,000 SIWES registration fee** (V777, the University's word of 22 November 2026): a student pays it once
a session, before a SIWES course is registered, whatever the programme, level or semester. A SIWES course is a course the
catalogue marks as one (`catalogue.course.industrial_training`, not ended).

Where the Academic Office has made a programme's 300 Level Second Semester the SIWES semester (V752), the student pays and
registers the SIWES course on the SIWES page, and that semester holds the course alone. Everywhere else the student pays on
the SIWES page and registers the course on Course Registration, with the courses beside it.

## Who it applies to

**The University's decisions of 12–13 November 2026** (V752):

- **SIWES registration at 300 Level, Second Semester**, for the programmes the Academic Office configures for a session. At
  deploy these are the seven whose 300 Level Second Semester is an attachment semester: Biochemistry, Biology, Chemistry,
  Computer Science, Physics, Plant Science and Zoology. Their students register the SIWES course alone, on the SIWES page
  (the *bound* shape, below).
  - V752 took this to be all of SIWES: Mass Communication (300 Level First Semester) and Environmental Management &
    Toxicology (400 Level Second Semester) were left out of it. **The decision of 22 November 2026 reversed that**: a SIWES
    course of theirs carries the fee once the catalogue marks it as a SIWES course, by its title or by the Academic Office on the
    SIWES courses panel (Mass Communication's Media Attachment does not say SIWES in its title: it is charged from the day the
    Academic Office adds it). They are not bound; they are registered on Course Registration.
- **A programme that is not configured keeps V503's rule** as before (the SIWES units, `REG_SIWES_SEMESTER`). Its SIWES course
  now carries the fee.
- **School fees still owed are still owed.** The semester's school fees must be cleared before the SIWES course can be
  registered, on the SIWES page or on Course Registration. The ₦4,000 is a separate payment, never a school-fee line.
- **An old-portal SIWES payment counts for its session.** A confirmed "SIWES (legacy)" payment, of any semester, settles that
  session's fee, for every SIWES course of the session.

**The decision of 22 November 2026 (V777): "yes charge every siwes course".** The Academic Office asked whether the
programmes whose SIWES course is in the First Semester or at 400 Level pay the ₦4,000, and the University said every SIWES
course does. **Every course the catalogue marks as SIWES carries the ₦4,000 SIWES registration fee, once a session for each
student, paid before the course is registered, whatever the programme, level or semester.** The same word gave four answers:

1. **Once a session, not once a course.** One ₦4,000 covers every SIWES course the student registers in the session: the
   course of each semester (Home Economics at 300 Level, and Human Kinetics and Urban & Regional Planning at 400 Level,
   carry SIWES courses in both), a carry-over beside the current course, a spillover student's carry-overs. A second payment
   of the session is a credit to be refunded, as it has been since V752. A new session is a new fee, asked only if the
   student registers a SIWES course in it.
2. **The students who registered a SIWES course in 2025/2026 unpaid are asked to pay.** On the live-shaped copy 176 students
   hold a SIWES course of 2025/2026 and 139 of them have no SIWES payment on record (₦556,000 if every one pays). They were
   never refused when they registered, and their registrations stand: nothing is dropped, returned or refused at approval (an
   approval of an entry already there is not a registration of it; the one exception is a student SIWES binds, one of the seven
   programmes at 300 Level Second Semester once the Academic Office has opened the period: V752's rule stands for the SIWES
   semester, so an entry not yet approved is approved when the fee is paid and refused until then). But they are in reach of the fee: their SIWES page asks
   it and they can pay it, and the Bursary has them on a list of the SIWES courses held with no SIWES payment
   (`registration.siwes_entries_unpaid`).
3. **The four SIWES-titled courses that are not the placement are charged as titled.** Nursing's Medical-Surgical Nursing
   Practicum II (SIWES), NSC 312; Radiography's Clinical Posting/SIWESS, RAD 416; and the two Urban & Regional Planning
   debrief topics, URP 431 and URP 435 (offered to Human Kinetics too). SIWES in the title makes it a SIWES course. The Academic
   Office takes one off with **Not a SIWES course** on the SIWES courses panel if it does not want it charged. The fee is once
   a session, so a student who has a SIWES course beside one of them pays no more.
4. **No fee published, no registration.** Until the Bursary has published the session's SIWES fee, a SIWES course cannot be
   registered (`SIWES_FEE_NOT_SET`). So that the Bursar only presses Publish, V777 states a ₦4,000 DRAFT fee for each
   planned session that has none.

### Three shapes, one fee

| Shape | Who | The course is registered | The semester holds | The fee |
|---|---|---|---|---|
| **Bound** (V752) | a student of a configured programme, the period not DRAFT, at 300 Level, in the Second Semester | on the SIWES page | the SIWES course alone | paid before the course, as V752 made it |
| **Attachment** (V503) | a student SIWES does not bind whose programme's semester carries a SIWES course and no other core or GST course | on Course Registration | exactly the SIWES course's units (V503's unit rule, unchanged) | paid before the course (V777) |
| **Everywhere else** | any other student who registers a SIWES course: one beside other required courses, in either semester, at any level, or a carry-over | on Course Registration, with the other courses | no | paid before the course (V777) |

On the live-shaped catalogue the attachment shape is Advertising, Public Relations, Broadcasting and Strategic Communications
at 300 Level First Semester, and the seven programmes above while their period is a DRAFT; Nursing's practicum, and Human
Kinetics and Urban & Regional Planning at 400 Level, are the third shape.

- The "alone" rule stays only where V503 or the Academic Office put it. The fee is asked everywhere.
- **While the period is a DRAFT, as it is today, the seven programmes read like every other.** Their students pay, then register
  the SIWES course on Course Registration (before V777 they registered it there free, under V503). Once the Academic Office
  opens the period they are bound exactly as V752 made them.
- The fee changes nothing else. School fees, the GST hold, the unit rule and the registration gate still run, and V503's exact
  units hold where they did. The fee stands in front of them.

### Who is charged, and when

A student is charged for **registering** a SIWES course, which means placing it on a registration, by any door: the student's
own registration, add and drop, the carry-over picker, add other course, ICT Support, Student edit, the Registry. Seeing the
course on the menu, or being offered it, charges nothing. The student must be

- an undergraduate in study (ACTIVE or PROBATION), not of the Centre for Continuing Education, not postgraduate; and
- in the session that is the student's current one, which is the one session a SIWES fee can be paid in.

A student is **in reach** of the fee, and is asked it, when the programme's structure carries a SIWES course (not ended) at the
student's level, or the student holds one on a registration of the session, or owes one as a carry-over, and has not already
passed it (a published pass of an earlier session makes it neither owed nor asked for). A student whose programme carries
none at the student's level, who holds or owes none, is not asked and cannot pay: no reference is drawn, and the gateway
refuses a payment. A SIWES course placed on such a student is refused `SIWES_NOT_IN_REACH` unless a SIWES payment stands (an
old-portal payer's does).

**Never charged:**

- a student who does not register a SIWES course; a plain course; a SIWES course that has ended (the catalogue state ENDED);
- a student of the Centre for Continuing Education, a postgraduate student, a student not in study (deferred, suspended,
  withdrawn);
- a session that is not the student's current one: a closed session, or a planned one, is never judged;
- the old portal's loaders (its registration history and results), which keep their override: a row they load is never
  refused. An entry they place for a student who has paid already is linked to the payment as it is placed; one placed with no
  payment is on the Bursary's list, and is linked when the student pays;
- an entry already standing: its approval, its class moved by a code correction (`catalogue.move_entry_to_own_code`), a
  proposal that finds its entry already there, a draft in progress at deploy that holds an unpaid SIWES carry-over.

An entry that comes back from DROPPED or WITHDRAWN, by any path (`assessment.revert_change`, the undoing of a duplicate
resolution, `registration.undo_entry_removal`), is judged as a new entry: a student who has paid nothing cannot have a withdrawn
SIWES course restored until the fee is paid. The Registry should know.

**The Summer** (semester 3) follows the same rule. No SIWES course runs there today: all of them are in semester 1 or 2.

### Which students SIWES binds

`registration.siwes_applies(student, session)` is the one test every reader uses for the bound shape: whether SIWES binds the
student's Second Semester. SIWES binds only a student who meets all of these:

- an undergraduate outside CCE;
- in study (ACTIVE or PROBATION; a deferred student is not bound);
- at 300 Level in that session;
- in a configured programme;
- in a session whose period is not a draft.

It does not bind a postgraduate, or a student who has already passed SIWES: the programme's SIWES course, or a 300 Level
Second Semester SIWES course (V776). The fee asks a different question (who is charged, above), and a student SIWES does not
bind is charged all the same.

## The student

The **SIWES** item is on the student's menu when the programme carries a SIWES course at the student's level, or the student
holds one on a registration of the current session; the dashboard shows a SIWES card, and **SIWES** (`/student/siwes`) walks
the student through the steps. (A student whose only SIWES course is a carry-over is led to it by the lock on Course
Registration.) The page has two modes, which `GET /api/v1/me/siwes` names in `mode`.

**A student SIWES binds** (`SEMESTER`, the bound shape: V752's steps, unchanged):

1. **Pay the SIWES registration fee.** This draws a reference for the fee in force and pays it through the usual checkout,
   then shows the receipt.
2. **Clear the Second Semester school fees**, if they are owed. The page says so and links to Fees & payments.
3. **Register the SIWES course.** The course registration is approved as it is made.

Carry-overs and deferred courses wait for a later semester. If the student's registration already holds other Second
Semester courses:

- while add and drop is open, the student removes them on Course Registration;
- otherwise the student uses the reset, which Course Registration offers in a SIWES semester, or asks the Academic Office.

Course Registration sends a student SIWES binds to the SIWES page. The course form, registration history and documents name
the SIWES course.

**Every other student in reach of the fee** (`COURSE`):

1. **Pay the SIWES registration fee**, once the Bursary has published it: the same reference, checkout and receipt. The page
   lists the SIWES courses that are the student's, each with its own level and semester and the reason it is theirs: in the
   programme's structure at the student's level, owed as a carry-over, or already held on a registration.
2. **Register the course on Course Registration**, with the semester's other courses, as any course is registered. Paying does
   not register it. The SIWES page does not offer to register the course for this student (`canRegister` is false, and the
   register door refuses with `SIWES_NOT_BOUND`), and says in which semester the course is.

Until the fee is paid, the course's row on Course Registration is **locked**, with the pill *SIWES fee required* and a note that
leads to the SIWES page, as a GST course is locked until the GST fee is paid. The carry-over picker shows the same. A SIWES
course the student holds from before the fee was asked stays registered, and the page asks the fee of the student.

- **A SIWES carry-over waits for the fee instead of breaking the draft.** The draft, and the registration form's save, leave an
  unpaid SIWES carry-over off, as they leave off an unpaid GST carry-over. The student adds it with the carry-over picker once
  the fee is paid.
- **A spillover student** registers carry-overs only. A SIWES carry-over is added by the picker like any other and charged as it
  is added; at a final level (Human Kinetics, for example) that is when the fee falls due.
- **A SIWES course of an ordinary registration is dropped as any course is**, while no mark is recorded. Dropping it frees its
  payment for the refund desk; the fee stays paid for the session unless it is refunded. The SIWES course of a bound semester is
  not dropped by the student (`SIWES_COURSE_KEPT`).

**What the student reads when a SIWES course is refused** (the first word is the code):

- `SIWES_UNPAID`: "the SIWES registration fee for *session* is not paid; *course* is registered once it is." The hint says to
  pay the fee on the SIWES page, then register the course.
- `SIWES_FEE_NOT_SET`: "the Bursary has not published the SIWES registration fee for *session*; *course* is registered once it
  is published and paid." The hint says the Bursary states and publishes the fee on Fee Setup.
- `SIWES_NOT_IN_REACH`: "*course* is a SIWES course and carries the SIWES registration fee for *session*, but your programme
  carries no SIWES course at your level, so the fee cannot be paid for it." The hint says the Academic Office adds the course to
  the programme, after which the fee is paid and the course registered. No office can register it first: every door meets the
  same gate.
- `SIWES_NOT_BOUND`, on the SIWES page's register button: "SIWES does not bind your Second Semester of *session*; your SIWES
  course is registered on Course Registration, not here."
- `SIWES_NOT_ELIGIBLE`, on the payment and the register button, in V752's words. A student with no SIWES course to pay for reads
  among its reasons that the programme carries no SIWES course at the student's level, and none is held or owed
  (`NO_SIWES_COURSE`).

The page's answer (`GET /api/v1/me/siwes`) keeps every V752 key, with its V752 value, for a student SIWES binds. It adds
`bound` (V752's `eligible`), `mode` (`SEMESTER`, `COURSE`, or none), `courses` (each with code, title, units, level, semester,
why it is the student's, held, passed) and `registerOn` (`SIWES_PAGE` or `COURSE_REGISTRATION`). `eligible` now means bound or
in reach; `canPay` means the student may pay, has paid nothing, and the fee is published; `canRegister` is still the SIWES
page's alone, so it is false for `COURSE`. For `COURSE` the keys `level`, `semester`, `course` and `semesterFees` are null and
`otherCourses` is empty: each course carries its own level and semester.

## The offices

**Academic Office — SIWES registration desk** (`/siwes/registration`; API `/api/v1/siwes/admin`).

- **Configuration** for each session:
  - the period, DRAFT, OPEN or CLOSED, with the registration and training dates;
  - the programmes whose students are on SIWES — a programme is added whether or not its SIWES course is known yet (V776);
  - the SIWES course of each programme and curriculum (BMAS or CCMAS): set here, or — where the programme's Second Semester is a
    SIWES semester — written down from its own structure as it is added; otherwise found and taken with one press;
  - the SIWES courses of the catalogue, which are the courses that carry the fee: adding a course starts charging it, and
    taking one off stops (V777).
- A course set for a programme is standing: courses are never tied to sessions. Each course shows its catalogue state, with a
  warning when it is not LIVE.
- A programme, course or period that students have paid or registered against on the portal cannot be removed or changed
  (`SIWES_PROGRAMME_IN_USE`, `SIWES_COURSE_IN_USE`, `SIWES_PERIOD_IN_USE`). Old-portal payers never lock it.
- **Students** has filters, search, an Excel export and print. **Statistics** counts eligible, paid and registered students
  by faculty, department and programme. Both are the bound cohort's: the 300 Level students of the configured programmes. A
  student of any other SIWES course is not on the desk's list; the Bursary's list of the SIWES courses held with no SIWES payment
  (below) is where they are counted.
- Readers are held to their scope: an HOD or SIWES coordinator to the department, a dean or faculty officer to the faculty.

**ICT Support and Student edit.** An office can drop an ordinary course in a SIWES semester with no override; the course
waits for a later semester. An office can also drop the SIWES course itself to undo a SIWES registration made in error, and
the fee can then be refunded. The student cannot drop the SIWES course of a bound semester (`SIWES_COURSE_KEPT`).

An office that registers a SIWES course for a student, in any semester, meets the same fee gate as the student: the course is
refused, in the database's words (`SIWES_UNPAID`, `SIWES_FEE_NOT_SET`, `SIWES_NOT_IN_REACH`), until the student has paid. ICT
Support's preview, and the record editors', tell the same before the act: a SIWES course of a student not bound by V752's
SIWES semester is a failing rule, **SIWES registration fee**, that cannot be overridden, in the database's words (the check of the
review of V777; the bound semester keeps V752's rule). Dropping a SIWES course of an ordinary registration frees its payment.

**HOD.** A standing SIWES registration of a bound semester is never returned or un-approved: `REG_RETURN_SIWES`,
`REG_STATUS_SIWES`. A registration that holds a SIWES course beside other courses is returned and approved like any other, and
its SIWES course stays on its payment while the entry stands, returned or not.

**Bursary.**
- *Fee Setup → SIWES fee* states and publishes the amount, with its history. A drawn reference keeps its amount until it
  expires. Every SIWES course of a session needs the session's fee published before it can be registered, so the Bursar
  publishes it in good time (V777 states a DRAFT of ₦4,000 for each planned session that has none; see At deploy).
- *SIWES Fee Payments* lists every confirmed SIWES payment, portal and old portal, with its source, gateway reference,
  receipt and bank-check state, and exports it.
- *The SIWES courses held with no SIWES payment* (V777; `GET /api/v1/siwes/admin/unpaid-entries`, from
  `registration.siwes_entries_unpaid`) lists, for a session, each SIWES course that stands on a registration of the session
  (not dropped or withdrawn) of a student the fee is asked of who has no SIWES payment standing: the matric number, the name,
  the programme and level, the course with its level and semester, the registration's status, and whether the SIWES page asks
  the student the fee now (the session is the student's current one). A student with two SIWES courses is listed twice and owes
  the fee once; the answer counts the students, and gives the fee in force. These are the students the University decided on 22
  November 2026 to ask to pay, the 139 of 2025/2026 among them, and any entry the old portal's loaders placed with no payment.
  A student who pays leaves the list. It is the **Unpaid courses** tab of the SIWES desk, and the SIWES fee panel on Fee Setup
  links to it. The Bursary reads it, with the offices that read the desk; a department or faculty office (the Head of
  Department and the SIWES Coordinator their department, the Dean and the Faculty Officer their faculty) reads its own unit's
  students only. The auditors do not read it: the desk has no screen for them.
- The *credits* panel lists second payments, which are money owed back to the student. From there the Bursar records a
  refund made by hand, reopens one recorded in error, or sends the payment to the refund desk.
- **A payment a SIWES course stands on is not refunded**, withdrawn, archived or moved while the course stands, whichever
  registration it is on (see The money rules). A course registered before V777 stands on the payment of a student who had
  paid (linked once by the migration) or, for a student who held it unpaid, on the payment that student pays afterwards (see How
  the fee is held, The link).

## SIWES courses, and a programme's SIWES course (V776, V777)

SIWES is not one course. Each department carries it under its own code and title — "SIWES", "Students Industrial Work Experience
Scheme", "Industrial Training", "Industrial Attachment".

- **A SIWES course** is a catalogue course marked as one (`catalogue.course.industrial_training`). A course whose title reads
  SIWES, Industrial Training, Industrial Attachment or Industrial Work Experience is marked as it is added to the catalogue or
  retitled (`catalogue.reads_as_siwes`), whatever its code; V776 marked the ones already there, the ended ones too (a course
  restored later is a SIWES course as it comes back). **Since V777 the mark is the switch for the fee**: every marked course
  that has not ended carries the ₦4,000, at any level and in any semester. Marking a course, or retitling one into SIWES,
  starts charging it at once; the students who hold it already are not judged again, but they are in reach of the fee, and
  those of them who have paid are linked to their payment as the course is marked (`registration.siwes_link_held_course`, from a
  trigger on the flag, so a retitle does the same): the refund, correction and archive desks then hold the payment.
- **The SIWES courses panel** on the desk lists them all: code and title, department, level and semester, state, the programmes
  whose structure carries each, the programmes each is the SIWES course of (set, or written down), and the programme semesters it
  makes an attachment semester (V503). A course set as a programme's SIWES course is listed too, though it is not marked. The
  Academic Office (or the Registry) **adds a course** to the list — an existing catalogue course, by its code — or takes one off
  with **Not a SIWES course** (`registration.siwes_mark_course`; API `PUT /api/v1/siwes/admin/siwes-courses`). A course taken
  off stays off while its title stands, and stops being charged. It is not taken off (`SIWES_COURSE_IN_USE`) while it is set for a
  programme on the desk, while students who have paid or registered read it, while a student holds it on a registration that
  stands on the SIWES registration fee in a session still to come or running (V777: the refusal counts the students and says
  that taking it off would stop charging it; they drop the course first, or ICT Support drops it for them; the entries of a
  session already closed hold nothing that can be dropped and do not block it, and their links stay), or while taking it off would end a programme's attachment
  semester in which students are registered (they could not submit that semester without it; an elective SIWES-titled course
  beside the real one does not). V776's own words win where they apply. A row that only came from the catalogue for a programme,
  where nobody has paid or registered, goes with it: that cohort waits for a course again.
- **A programme's SIWES course** is the row `registration.siwes_course` holds for it, for a curriculum or for every curriculum
  (`registration.siwes_course_of`, the one reading every part of the portal uses, unchanged since V752). It is the course that
  binds the programme's 300 Level students to the SIWES semester (the bound shape), so it is a 300 Level, Second Semester
  course: **Set course** refuses one the programme carries only at another level (`SIWES_COURSE_LEVEL`) or in the First Semester
  (`SIWES_COURSE_SEMESTER`). That row decides who is bound. It does not decide what is charged: since V777 the fee follows the
  marked courses, whether or not a programme's row names them.

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
  says what it binds) sets it. A programme whose SIWES course is a First Semester or a 400 Level course cannot have it set (it
  would be refused): it is not bound, and its course is registered on Course Registration — charged all the same, since V777.
  Saving the period changes nobody's binding. Nothing needs the press for a programme to be charged.

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
- **SIWES already passed**, for a student SIWES binds, is a published pass in the programme's own SIWES course, or in a SIWES
  course of 300 Level — not SIWES I at 200 Level or a seminar, now that every SIWES-titled course is marked
  (`registration.siwes_passed_among`). The fee reads a pass its own way: a SIWES course the student passed in an earlier session
  (a published pass) is neither owed nor asked for.
- **The fee is the same for every one of them**: whichever course it is, the ₦4,000 SIWES registration fee is paid before the
  student registers it. V776 did not yet cover a SIWES course of the First Semester or of 400 Level; V777 does (the decision of
  22 November 2026, above).

## How the fee is held (V777)

**One gate, where every registration entry passes.** The entry trigger `registration.entry_siwes_only`, which already held the
SIWES semester (V752), judges every SIWES course as it is placed on a registration, so no door goes round it: the student's own
registration, add and drop, the carry-over picker, add other course, ICT Support, Student edit, the Registry, the Summer's.

- **A student SIWES binds, in the Second Semester,** is judged by V752's own rule, its text untouched.
- **Any other SIWES course** of a student who is charged (above) is refused unless a SIWES payment stands (`finance.siwes_paid`:
  the portal's, or the old portal's of either semester). The refusal names the cause, in this order: the fee is not published
  (`SIWES_FEE_NOT_SET`); the student has no SIWES course to pay for (`SIWES_NOT_IN_REACH`); else the fee is unpaid
  (`SIWES_UNPAID`). The registration page asks the same question first (`registration.siwes_fee_gate_many`, the shape of the GST
  gate), so the course is locked before the student reaches the refusal.
- **Accepted, the entry stands on the payment.** It is written to `registration.siwes_course_entry`, on the payment that settles
  the fee. The database writes this link; the application never does.

**The link.** `registration.siwes_course_entry` holds a row for each SIWES course entry accepted on a payment: many for a student
in a session, and none of the SIWES semester's behaviours. (V752's `registration.siwes_registration` carries those, one row for a
student in a session: the Head cannot return it, the student cannot drop its course.) It has no foreign keys. The guards read it
through the live entry, so a row whose entry is gone stands for nothing. A course entry **stands** while its entry is not DROPPED
or WITHDRAWN. `finance.siwes_stands_on(payment)` is true while a SIWES registration or a SIWES course entry stands on that
payment, and every money guard reads it (The money rules).

**One lock order, the registration's** (V762's, extended): the registration's row, the student's row, the SIWES lock, and only
then the payment is read. So a SIWES course placed at the instant its payment's refund is approved goes one way or the other,
never both: the refund waits and is refused while the course stands, or the course waits and is refused because the payment was
given back. The registration's row is taken first so that two doors on one registration cannot wait on each other in a circle
(the review found that deadlock by reading, proved it on two real sessions, and the migration closes it). The student's own
doors are not run again by the API as the desks' are (`DeadlockRetry`); no cycle is known between two entry doors, and a student
who meets one presses the button again.

**A SIWES course placed before V777 is linked when its fee is paid.** The gate writes the link as an entry is accepted. An entry
already standing at deploy, and one the old portal's loaders place with no payment, has no row, and the money guards read only the
link, so the link is written for it by `registration.siwes_link_held(student, session)`: the standing entries of a SIWES course of a
judged student in the session, with no link, none of them V752's SIWES registration, on the payment that settles the fee
(`finance.siwes_paid`). It is called in two places, both under the student's SIWES lock. (1) **Once, by the migration**, for the
students who already have a SIWES payment standing (on the live-shaped copy, 37 of the 176): without it the old fees reset, which runs
from time to time, could delete the old-portal payment a student paid for a course they hold. (2) **Whenever a SIWES payment comes to
stand** (`finance.siwes_settling_follows_payment`: a portal reference confirmed, an old-portal record loaded, a payment set back and
confirmed again), for the students who held a SIWES course unpaid and pay afterwards, the 139 among them: their entry is linked to
the payment they pay, and from then on a refund of it is refused, the archive and correction desks leave it, and the old fees reset
keeps it. Until they pay, such a student stays on the Bursary's list and nothing stands under the entry. A second payment (a credit)
writes no second row and moves none.

## The money rules

- **One fee per session, all or nothing.** V777 keeps this exactly, and extends it: the one fee covers every SIWES course of the
  session.
  - The first confirmed payment settles the fee.
  - Any later SIWES payment of the same session is a credit, whether it came from the portal, from an old-portal row loaded
    later, or was already on record when V752 deployed (V752 backfills these).
  - The refund desk refunds a SIWES payment whole or not at all (`REFUND_SIWES_PART`). It never refunds one a SIWES
    registration, or a SIWES course on an ordinary registration, stands on (`REFUND_SIWES_REGISTERED`).
- **A payment a SIWES course stands on is held like one a SIWES registration rests on** (V777), by every guard:
  - the refund desk, a refund raised and a refund approved (read again under the lock): `REFUND_SIWES_REGISTERED`;
  - the payment correction desk (`REALLOC_LINKED`) and the archive desk (`PAR_LINKED`);
  - the withdrawal of a record as never received (`PAY_NOT_RECEIVED_SIWES_REGISTERED`);
  - the old fees reset, which keeps such a payment and counts it kept;
  - `finance.siwes_standing`, which reads such a payment as registered, so it is the one that settles the fee
    (`finance.siwes_paid`).

  A payment that leaves, because it is set back to unconfirmed, deleted, or found never received at the bank check, moves the
  entries standing on it to the payment that settles the fee (`finance.siwes_settling_follows_payment`,
  `finance.siwes_stand_again`). A dropped entry's row stays where it was. Dropping the course frees the payment.
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

## The data (V777)

- **Nothing is rewritten.** V777 changes no payment, credit, refund, reference, registration or entry row. Proved on made-up
  students through V752's and V762's own paths: the standing payments, the settling payment, the credits, the SIWES payments, the
  refunds, the SIWES registrations, the entries and the course registrations read the same line for line before V777 and after
  it. The seven programmes' rows (`siwes_programme`, `siwes_course`, the DRAFT `siwes_period`) are untouched, and so are the
  old portal's SIWES payments (on the live-shaped copy 179 of 2023/2024, 1,857 of 2024/2025 and 1,606 of 2025/2026, all ₦4,000,
  confirmed), each of which settles its session for every SIWES course, and the 20 open credits.
- **What is added:** the table `registration.siwes_course_entry` (audited; created empty, then filled once by the migration's
  link backfill, for the students who had paid: 37 on the live-shaped copy); the partial index `catalogue.ix_course_siwes_marked` on the
  marked, not ended, courses (a few dozen rows); new functions; the restated functions named in the migration's presence check;
  one trigger, `trg_course_links_siwes` on `catalogue.course`, which fires only when a course comes to be marked (its WHEN
  condition reads the two flags of the row).
- **The fee rows.** For each PLANNED session with no SIWES fee row, V777 states a **DRAFT** of ₦4,000 (note "V777: stated for the
  Bursar to publish — every SIWES course carries the SIWES registration fee"). A fee row that is published or drafted is left
  exactly as it is. On the live-shaped copy the current session's fee (2025/2026) is published already, and the planned
  session 2026/2027 has none, so it gets the draft.
- **The notice template.** A student is sent `SIWES_FEE_PAID` when the fee is confirmed. V752's words said "Register your SIWES
  course on the SIWES page", which would mislead a student SIWES does not bind. V777 rewords the portal body to "Your SIWES
  registration fee for [SESSION] is paid. Sign in and register your SIWES course: paying does not register it." and the email's
  sentence to "Sign in and register your SIWES course: paying does not register it." Each field is changed only where it still
  reads exactly as V752 wrote it: a template the Registry has re-worded since is left as it is. The SMS ("on the portal") is
  not changed.
- **The entries registered before V777** (176 students in 2025/2026 on the live-shaped copy, 139 of them with no SIWES payment)
  are not re-judged or refused: their registrations stand. The 37 who have paid are linked to their payment by the migration; the
  139 who have not are linked when they pay (The link). A draft in progress at deploy that holds an unpaid SIWES carry-over is not
  re-judged either: submitting or approving an entry already there is not registering it (except, for a student SIWES binds once
  the period is open, an entry not yet approved: V752's rule judges it).
- **Cost, measured on made-up rows:** a registration entry that is not a SIWES course costs two primary-key reads more (the
  offering and the course), about 0.2 ms an entry in the First Semester; the SIWES menu item costs about 0.3 ms more for a
  student whose programme carries no SIWES course; a SIWES course itself takes the lock and reads the payment.

## At deploy

**V752** does the following when it is applied:

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

**V777** writes no money and no registration (The data, above). What it asks of the offices:

- **The Bursar presses Publish.** The fee of the current session is published already. V777 states a ₦4,000 DRAFT for each
  planned session that has none (2026/2027 on the live-shaped copy). On *Fee Setup → SIWES fee* the Bursar checks the amount and
  presses **Publish** before that session's registration opens. Until it is published no SIWES course of the session can be
  registered or paid for (`SIWES_FEE_NOT_SET`), and the student is told why.
- **The Academic Office reviews the SIWES courses panel** before the session's registration opens. The panel lists every course
  that is charged (36 are in force on the live-shaped copy, 33 live and 3 at the faculty board).
  - The four SIWES-titled courses that are not the placement, NSC 312, RAD 416, URP 431 and URP 435, are charged as titled. If
    the University does not want one charged, the Academic Office takes it off with **Not a SIWES course** first. It cannot
    while students hold it in a session still to come or running on a registration that stands on the fee
    (`SIWES_COURSE_IN_USE`); the students of a closed session do not block it.
  - Courses that read like a placement but do not say SIWES in the title (Mass Communication's Media Attachment, Radiography's
    Clinical Posting, and the like) are not charged. Adding one to the panel charges it from that moment.
  - The seven programmes are not bound while the period is a DRAFT (Who it applies to): their students pay, then register on
    Course Registration. Opening the period binds them, so the V752 review of each programme's course still comes first.
- **The Bursary reads the list of the SIWES courses held with no SIWES payment** for 2025/2026. The SIWES page asks those students
  the fee, and the list shows who has not yet paid.

**Locks.** V777 creates a table and one small index on `catalogue.course` (held for a moment), and replaces functions
with `CREATE OR REPLACE`. Its one trigger, on `catalogue.course`, takes a lock on that table for a moment only; it alters no
table the portal writes, so it does not repeat V752's lock stretch.
It stops by name, before changing anything, if a function it restates is not as V752, V762 and V776 left it.

## Checks

- `db/check.sql` has a V752 block with one property, and V776 blocks: programmes added to an open period with no course set; a
  course marked by its title under its own code; each programme's course recognised in its structure or its department, or none;
  who is bound and which cohort waits; a course added to the SIWES courses and taken off, never one in use; the fee still paid
  before registering; a tie never guessed; the department rule shown, never written; a written course standing under students who
  have paid whatever the catalogue does; written only for a SIWES semester and for all curricula or none; saving the period or
  marking a course in a closed period changing nobody; the 300 Level refusal; SIWES already passed; V503's attachment semester.
- `db/check.sql` has five V777 blocks (65 properties), each undoing its writes. They were tried against deliberately broken copies of
  the functions (10 for the money layer, 11 for the gate, 7 for the marker, 11 for the link, 6 for the review's): every one fails at
  least one property.
  - **The money layer.** A payment a SIWES course entry of an ordinary registration stands on is held by every money guard as
    one a SIWES registration stands on: the refund desk (raised, approved on the desk, and approved bare on `finance.refund`),
    the payment correction desk, the archive desk, the withdrawal as never received, the old fees reset (it keeps such a payment
    and counts it kept, and deletes the one whose entry was dropped), and `finance.siwes_standing`, which reads it as registered
    so it settles the fee. A payment set back, deleted or found never received moves the standing entry to the payment that
    settles, and leaves a dropped entry's row. Each guard is asked while the entry stands and again once it is DROPPED, and the
    same questions are asked of a student whose registration stands on V752's table, whose answers are V752's.
  - **The gate and the pay chain.** An unpaid SIWES course is refused `SIWES_UNPAID` in the student's current session and never in
    a closed or a planned one, and a plain course never; the portal's payment, and the old portal's of either semester, accepts
    it, and the entry stands on that payment; not judged again: an approval, a class moved, a proposal that finds its entry, the
    old portal's override; judged: a dropped entry coming back; one payment covers both semesters, the second reference is
    refused and a second payment is a credit; a payment of another session settles nothing; the fee not published refuses
    `SIWES_FEE_NOT_SET` until it is; a student whose programme carries none, or who passed the course, cannot pay and is refused
    `SIWES_NOT_IN_REACH` unpaid and accepted paid; CCE, postgraduate and not in study are never judged; the draft and the form's
    save are made without an unpaid SIWES carry-over and with a paid one, and a spillover student's carry-over is judged; the gate
    names every unpaid SIWES course of a list; a student who holds a SIWES entry from before the rule is in reach, may pay, is
    listed for the Bursary and is not refused when an approval touches the entry; the lock is taken before the payment is read
    (read from the function's text, as V762's order is); the SIWES semester V752 binds is untouched: no course entry is written
    for it, its unpaid course is refused in V752's words, its page reads `SEMESTER`, and the register button is shut to a student
    SIWES does not bind.
  - **The marker.** Marking a course starts charging it and a plain course is free, a retitle into SIWES does the same, and the
    held entry is not judged again and is in reach; a code correction that moves entries
    (`catalogue.move_entry_to_own_code`) is refused neither for a student who paid (one link row follows, the same payment, still
    held from the refund desk) nor for one who held the course unpaid; taking a course off the SIWES courses is refused
    `SIWES_COURSE_IN_USE` while a student's entry stands on the fee, and accepted once it is dropped; the menu's cheap test reads
    the catalogue by index probes only, never by a scan.
  - **The link of the entries held before.** Standing entries of a SIWES course placed before the fee was asked (under the old
    portal's override, with nothing paid) are linked to the payment that settles the fee: once by the migration's statement for the
    students who had paid (a portal payer, an old-portal payer of either semester, a student with two entries, one row each), and
    whenever a SIWES payment comes to stand afterwards, for the students who paid later (the gateway's confirmation, an old-portal
    record loaded, one payment under two entries, a second payment writing and moving nothing). Never linked: an unpaid holder, a
    dropped or withdrawn entry, a session closed or planned, a CCE, postgraduate or not-in-study student, a plain or ended course, a
    payment of another session, a course V752's SIWES registration holds. Once linked, the old fees reset keeps the payment and the
    refund and archive desks refuse it. Run twice, the statement changes no row. An entry the old portal's loader places for a
    student who has paid is linked as it is placed.
  - **What the review of the application layer found.** The preview of an add by ICT Support or a record editor says what the
    entry trigger will; a course marked on, or retitled into SIWES, links the entries the paid students already hold; taking a
    course off the SIWES courses is refused only for a session still to come or running; the SIWES page says on which
    registration a held course is (a draft is not registered); the words of a student whose programme carries no SIWES course
    no longer promise an office registers it; a programme configured for a period that is still a draft (the shape of the seven
    seeded programmes) is charged and its student can pay.
- **Two blocks of earlier migrations move, for reasons that are V777's rule, not defects.** In V752's block, round 6 expected the
  SIWES menu item false for an old-portal payer of a programme whose structure carries a SIWES course at the student's level;
  under V777 it is true, because the menu item is that student's. In V776's second and third review blocks, one made-up unpaid
  student registers a SIWES course, which V777 refuses; each now gives that one student a made-up confirmed SIWES payment first.
  Every V776 message is unchanged, and nothing else bent.
- Nine races were run on two real sessions each, and kept in the review rather than in `check.sql`: a SIWES course placed at the
  instant its payment's refund is approved, the SIWES page's register button against an ordinary add of a SIWES course for the
  same student, two doors adding the same course, a gateway confirmation against an entry, two doors on one registration, and
  the gateway's confirmation of the fee of a student who holds a course unpaid against a door placing a second course (it waits,
  then registers on the payment) and against a refund raised on that payment (it waits, then is refused). One deadlock was found
  and fixed.
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
