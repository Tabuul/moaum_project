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
- **Results.** Summer results are released by the Summer's payment (`finance.results_cleared` for semester 3 asks only that no Summer charge is DUE). The broadsheet lists only those who registered.
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

- **Academic standing.** Standing is not pronounced on a Summer alone (`assessment.standing_of` answers nothing for semester 3).
- **CGPA.** CGPA counts every attempt, as the portal's rule already does. No replacement rule was invented for a Summer pass.
- **Approval of the registration.** A paid Summer registration is approved by the payment. The courses are the student's own outstanding ones, checked by the database. If the Academic Office wants a desk approval as well, it is one rule to add.
- **The GST & EPS examination permit.** The permit was not adapted for semester 3.
- **The "Third" semester wording.** Results and transcripts that print a semester name read semester 3 as "Third". The student's Summer page, the examination card and the allocation desks say "Summer".
