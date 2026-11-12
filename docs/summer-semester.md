# Summer semester for final-year and spillover students (V735)

The University's master prompt of 12 November 2026, "Introduction of Summer Semester for final-year and spillover students".

The Summer Semester is a third academic period of a session, beside the First and Second Semesters. It has its own registration window and dates. An eligible student registers outstanding courses from both semesters in one registration, pays for them, takes them, and a pass clears the carry-over.

## How it fits the portal

- **It is not a `policy.semester` row.** Opening semester 3 on the calendar would make it every regular student's current semester. About a dozen readers take the highest open semester, and a closed Summer would count as a missed semester toward voluntary withdrawal. So the period lives in `registration.summer_period`, and `academic_session.semesters` is left alone.
- **Its registrations, classes, examination session, score sheets and results are those of semester 3 of the session.** They are keyed by `(session, semester)` like everything else, so a Summer pass orders after the failure it replaces and clears it.
- **Outstanding courses are computed, never stored.** They come from `registration.carryovers`, with the session and semester of each failure from `registration.carryover_attempts`.
- **Summer fees are kept apart from school fees.** They live in `finance.summer_fee` and `registration.summer_charge`, and their payment references carry the purpose `Summer semester fees, <session>: …`. No school-fee reader counts them. They are classified under their own payment category, `SUMMER_SEMESTER` (pattern `^summer semester`), which also covers the old portal's Summer payments.

## Who may take it

`registration.summer_eligibility(student, session)` gives each student's answer:

| Category | Who |
|---|---|
| FINAL_YEAR | Current level at the programme's final level (`finance.final_level`, 400 when unset) |
| SPILLOVER | `finance.is_spillover` |
| BEYOND_DURATION | The academic position counts spillover years |
| AUTHORISED | Admitted by the Academic Office for an approved academic reason (`registration.summer_authorisation`), with any courses it names |

A student must be all of the following:

- an undergraduate of a regular programme (not CCE or postgraduate)
- ACTIVE or on PROBATION
- without an approved award
- within the period's categories, programmes and levels
- holding at least one outstanding course (an authorised student may have none)

When a student is not eligible, the page gives the reason: NO_SUMMER, NOT_UNDERGRADUATE, NOT_STUDYING, GRADUATED, PROGRAMME_NOT_IN_SUMMER, LEVEL_NOT_IN_SUMMER, NOT_FINAL_OR_SPILLOVER, CATEGORY_NOT_IN_SUMMER or NO_OUTSTANDING_COURSE.

A course can be selected unless:

- it is already passed
- its result for this session is awaited
- it has ended
- it is already selected or registered

## Fees

The Bursary states the fees for a session, either for every programme or for one programme:

- a **programme fee**, charged once per student per Summer with the first course (₦50,000 by default)
- a **fee per course** (₦5,000 by default)

A statement starts as a DRAFT, and a draft is never charged. Only the **Bursar** (or the Super Administrator) publishes it, which is the approval. A Student Accounts officer can state and delete drafts but cannot publish.

A published statement is never changed. The Bursary states a new one and withdraws the old one with a reason. A charge keeps the figure it was made at. A programme's own published statement takes precedence over the statement for every programme.

Adding a course later charges only that course's fee. The programme fee is never charged twice in a Summer.

## Payment

- The student selects courses, which creates DUE charges. They then draw one reference for everything owed (`registration.summer_reference`) and pay it through the gateways every fee uses: card or USSD, Quickteller, or PayDirect at a bank.
- A reference is drawn only while the Summer is open.
- A reference is payable only while it covers exactly what is owed now (`registration.summer_reference_payable`). This is checked at the checkout, on the Quickteller page and at PayDirect validation. If the selection changes, the earlier reference is expired at once, and the page draws one for the new figure.
- An expired reference that is regenerated from the payment button gives the reference for what is owed now, never the old figure (a `finance.renew_reference` branch). If nothing is owed, the student is told so.
- Confirmation from any lane goes through `finance.confirm_payment`. The trigger `trg_summer_reference_confirmed` marks the charges that reference was drawn for as PAID. A charge already paid by another reference is left as it is, so callbacks are idempotent.
- `registration.summer_materialize` then makes the registration and tells the student (SUMMER_REGISTERED). The registration is semester 3 of the session, each paid course in its Summer class (opened when first needed), with entry type CARRYOVER, approved by the payment itself (approval mode AUTO). A course paid later joins the same registration.
- In a session with a Summer, the regular course registration refuses semester 3: "The Summer Semester of … is registered on the Summer Semester page."

## Teaching, examinations and results

- **Classes.** `catalogue.open_class` lets any course run in semester 3 of a session that has a Summer. The allocation desks (the department's Teaching Allocation and the University's Course Allocation) show the Summer's classes under semester 3, labelled "Summer". Lecturers are allocated there as for any class.
- **Examinations.** Setting the examination dates on the period creates the examination session (session, 3, MAIN, REGULAR). The desk opens it and releases the score sheets. Score entry, approval and publication follow the existing chain.
- **Examination card.** The semester 3 card is issued once the Summer is paid. `registration.exam_card_state` and `registration.exam_cards_withheld` read the Summer's own payment for semester 3, not the session's school fees, and name the period "Summer semester".
- **Results.** A Summer result is released by the Summer itself: its courses are registered only once paid, so a course left selected and unpaid never withholds the paid ones. Where the Bursar's scheme lets a balance owed for an earlier session block everything, it blocks the Summer's results too (V739). The broadsheet lists only those who registered.
- **Results chain.** Approvals, the desk, the chain, the pipeline, the Senate schedule, the broadsheet and the class list offer "Summer semester" (semester 3) in their scope bar, and name it so. The Summer desk links each class to its class list and each student to their record.
- **CGPA.** CGPA reuses the existing rule, which counts every attempt.

## Desks

**Student: Summer Semester (`/student/summer`).** The menu item shows only where `registration.summer_area` says the Summer is for the student. The page shows:

- whether the student may take the Summer, and why
- the outstanding courses, each with its own semester and where it was failed
- the fees, what is owed and what is paid, with one Pay button
- the registration once paid, which can be printed as the Summer course form
- the payment references

The dashboard shows a card while the Summer is the student's.

**Academic Office: Summer Semester (`/summer`).** The Academic Office, the Registrar, the Deputy Registrar and the Super Administrator can:

- set the period: state, registration window, examination and results dates, categories, programmes and levels
- identify the eligible students, in tranches of 400 until none is left
- authorise or withdraw a student
- tell the eligible that the Summer is open, remind those not registered, and tell the registered the examination dates
- open the examinations and release the score sheets

Readers are the Registry, Heads of Department (their department's students and courses only), Deans (their faculty's), the Bursary, ICT, the VC and the DVC. They see:

- figures: eligible, begun, registered, courses registered, owing, paid, programme fees and course fees paid apart, results published, passed and failed, and students who cleared every outstanding course
- the students, filtered, searched and exported to CSV
- the classes, with lecturer, registered count, the semester each was failed in, and score sheet stage
- tables by faculty, department, programme and level

**Bursary: Summer Semester Fees (`/finance/summer-fees`).** Statements can be stated, published, withdrawn and deleted (drafts only). Collections for each session show programme fees and course fees apart.

## API

| Method and path | Who | What |
|---|---|---|
| GET `/api/v1/me/summer?session=` | student | Period, eligibility, courses, fee, account, registration, references |
| POST `/api/v1/me/summer/select` `{session, courses[]}` | student | Select courses (DUE charges) |
| POST `/api/v1/me/summer/unselect` `{session, course}` | student | Take back an unpaid course |
| POST `/api/v1/me/summer/reference` `{session}` | student | The reference for everything owed |
| GET `/api/v1/summer/periods` | readers | Every Summer set |
| PUT `/api/v1/summer/{s}/{y}` | Academic Office | Set the period |
| POST `/api/v1/summer/{s}/{y}/identify` `{since, limit}` | Academic Office | One tranche of identification |
| GET `/api/v1/summer/{s}/{y}/students` | readers (scoped) | Rows and figures |
| GET `/api/v1/summer/{s}/{y}/courses` | readers (scoped) | The Summer's classes |
| POST `/api/v1/summer/{s}/{y}/authorise` | Academic Office | Authorise or withdraw a student |
| POST `/api/v1/summer/{s}/{y}/tell` `{kind}` | Academic Office | OPEN, CLOSING or TIMETABLE notices |
| POST `/api/v1/summer/{s}/{y}/exams/{open\|release-sheets}` | Academic Office | The examination session |
| GET/POST `/api/v1/finance/summer-fees` | Bursary | Statements and collections; state a draft |
| POST `/api/v1/finance/summer-fees/{id}/publish` and `/withdraw` | Bursar | Approve; withdraw with a reason |
| DELETE `/api/v1/finance/summer-fees/{id}` | Bursary | Delete a draft |

The database checks every act again: who may set a period, that a selection is the student's own outstanding course, and that the fee is published. Every table is attached to the audit trail.

## Notices

The notices use the notification engine's templates, one message per student per event:

- SUMMER_OPEN, to the eligible
- SUMMER_CLOSING, to the eligible who have not paid
- SUMMER_REGISTERED, sent on payment
- SUMMER_TIMETABLE, to the registered

## Opening the first Summer

1. Academic Office: on Summer Semester, choose the session, set the period to PLANNED (or OPEN) with its dates, and save.
2. Bursary: on Summer Semester Fees, state the fees for the session. The Bursar publishes them.
3. Academic Office: run Identify the eligible, then Tell the eligible it is open, and set the period OPEN within its dates.
4. Students select and pay. Payment registers them.
5. Heads of Department allocate lecturers to the Summer classes (Teaching Allocation, semester: Summer).
6. Academic Office: date the examinations, tell the registered, open the examinations and release the score sheets. Results follow the existing chain.

## Flagged, not invented

These questions are for the Academic Office to decide:

- **Academic standing.** A student's standing is read from their last regular semester; a Summer does not change it (V739: `assessment.student_standing` leaves the Summer out), and no standing is pronounced on a Summer alone: the Summer broadsheet prints none (V741). Before V739 a Summer read GOOD and let a student on probation escape the probation unit limit.
- **CGPA.** CGPA counts every attempt, as the portal's rule already does. No replacement rule was invented for a Summer pass.
- **Approval of the registration.** A paid Summer registration is approved by the payment. The courses are the student's own outstanding ones, checked by the database. If the Academic Office wants a desk approval as well, it is one rule to add.
- **The GST & EPS examination permit.** The permit was not adapted for semester 3.
- **The "Third" semester wording.** Transcripts and results statements that print a semester name read semester 3 as "Third". The student's Summer page, the examination card, the allocation desks and the results chain say "Summer".
- **Old-portal carry-overs.** A course registered before with no result on this portal (its result is on the old portal) is not an outstanding course for the Summer: most past results are on the old portal, and counting them would make nearly every final-year student eligible for courses they passed. The Academic Office authorises such a student for the courses it names.
- **A fee withdrawn after a selection.** The charge keeps the figure it was made at (a charge keeps its figure); the student may take the course back and select it again at the published fee.

## The review of V735 (V739)

An adversarial review confirmed 31 defects; V739 and the same change answer them.

- **Money.** A payment confirmed after its selection changed now pays, in order:
  1. the charges it was drawn for that are still owed;
  2. those taken back since, where nothing stands in their place and the course is still outstanding;
  3. the student's other charges still owed, programme fee first and never a course before it.

  Anything left is an unapplied Summer credit (`registration.summer_credit`), listed on Summer Semester Fees for the Bursar to record as applied or refunded. The programme fee is never paid twice, and the other open references of the Summer are closed. An open reference is shown only when it may be paid, at its own amount.
- **A registration that fails never undoes a payment.** Courses are registered one by one. A course the registration cannot take (for example one ended since it was chosen) is recorded (`registration.summer_issue`) and listed on the desk as "Paid, not yet registered", with Retry. A Summer class already open is reused.
- **Drawing a reference** takes back a course no longer outstanding or no longer taught. A reference that still holds an ended course is not taken to a gateway.
- **A paid Summer payment** is neither moved by a payment correction nor archived while it pays registered courses (`REALLOC_LINKED`, `PAR_LINKED`).
- **Closing a Summer** takes back what was selected and not paid and closes its open references. An unpaid course may be removed after the close. The student's page says registration has closed, or when it opens.
- **School fees.** A Summer registration is no school-fees semester (`finance.reg_semesters`, `finance.registrations_without_fees`), so a spillover student who takes only the Summer owes no whole-session spillover line because of it.
- **Eligibility.** Every category a student falls in is read, and the first the period admits is reported.
- **Units.** Summer entries carry the programme's own units (`catalogue.units_for`).
- **Identification.** Each run re-reads every student identified before. Authorising a student, or withdrawing it, re-reads them at once.
- **The desk.** It is held to the active office's unit, whatever other offices the token carries, and refused in an office that does not read it. Notices are refused before their dates are set or after the Summer closes, and a changed window or timetable is told again.

## The review of V739 (V741)

A review of those fixes confirmed 13 more; V741 and the same change answer them.

- **School fees, in the bulk readers too.** `finance.fee_profiles`, which feeds the School Fees Report, the Spillover desk, Student Accounts and the College and HOD views, leaves a Summer registration out, as `finance.reg_semesters` does.
- **No standing on a Summer.** V739 let `assessment.standing_of` speak for semester 3, so the Summer broadsheet printed probation or advice to withdraw on the Summer alone. It is silent again; the student's standing stays that of the last regular semester.
- **A credit follows its payment.** A credit whose payment is archived, or no longer stands as a Summer payment, is not shown as the student's nor listed on Summer Semester Fees. (V741 also refused to move or archive such a payment until the credit was settled; V742 replaced that refusal, below.) "Applied" records where the money went (the voucher, the reference or the desk that moved it); it moves no money itself.
- **Drawing a reference after a take-back.** When every chosen course is taken back (passed since, or no longer taught), the take-back stands and the student is told nothing more is owed. A course passed since it was chosen is taken back even when the Academic Office authorised it.
- **A late payment** never revives a passed course, nor the programme fee alone with no course: the money stands as a Summer credit.
- **The results chain's scope bar** shows a Summer chosen elsewhere as the Third semester on screens that do not offer the Summer, instead of "Both semesters".
- **The desk's class-list links** are offered only to the offices that may open a class list; the Bursary offices see the course code.

## The review of V741 (V742)

A review of those fixes confirmed four more; V742 and the same change answer them.

- **A passed course is never paid for.** A reference that holds a course no longer outstanding (passed since it was chosen, an authorised one too, or no longer in the student's pool) is not payable: the student's page drops it and Pay takes the course back. A payment confirmed anyway, made at a bank before the pass, pays no such course. The course is taken back first, along with the programme fee when no course stands beside it, and the money stands as a Summer credit (`registration.summer_course_outstanding`).
- **The credit follows its payment instead of holding it.** A payment with an open Summer credit may be moved or archived like any other.
  - Moved off the Summer (another purpose, session or student), the credit is settled as applied, with the move as its note. Moved back, it is open again.
  - Archived, the credit stays open and out of sight until the payment is restored.
  - The Bursar records applied or refunded only while the payment stands as the student's Summer payment.
- **The check of the bulk readers** now uses a spillover student who registers only in the Summer, and fails if `finance.fee_profiles` counts the Summer again.

## The review of V742 (V743)

- **A passed course is not outstanding, however else the pool describes it.** The pool names an ended or unknown course before a passed one. So a course the Academic Office authorised, passed since and then ended, read as outstanding, and a payment confirmed anyway paid for it. `registration.summer_course_outstanding` now tests the pass itself, as the pool does. An ended course that is not passed stays outstanding: once paid, it is the desk's issue (V739).
- **The payable test is quick.** Testing whether a course is still outstanding reads the student's pool and results. It is declared at that cost, and payable tests only the reference's own course charges, so checkout and the gateways' validation never test every Summer charge in the table. One payable test with 48 charges in the table took 1.9 s before this and takes 0.3 s now.
- **The check of the bulk and per-student readers** states a spillover school-fee line for the student's programme, so a Summer counted again shows as a charge the bulk reader owes and the per-student reader does not.

## Findings left open by the reviews of V742 and V743 (V746)

- **An authorisation follows its course.** The Academic Office's authorisation names its courses by code. A code corrected (`catalogue.correct_course`, `rename_course`) or merged away (`catalogue.merge_course`) left the authorisation naming a dead code, so the student's paid course was taken back into credit and could not be chosen again. Every authorisation naming a code now follows it to the new code (triggers on the course's code and on the merge's alias). Authorisations that already named a dead code were put right from the merge aliases and the code-change trail; the migration's notice counts them.
- **A settled credit holds its payment.** Once the Bursar records a Summer credit as refunded, or as applied somewhere else, that money is spent. The payment it names is then neither moved by a payment correction nor archived (`REALLOC_LINKED`, `PAR_LINKED`), as a payment that paid registered Summer courses is not. A credit still open follows its payment, as V742 made it.
