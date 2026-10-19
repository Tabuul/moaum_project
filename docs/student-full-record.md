# The student's full record (Student 360°)

*Oct 2026.* The student record page (`/students/{id}`, Students → a student → **Open full record**) is the Student 360° view:
the existing header (photograph, number, programme, level, status, and the Registry's actions) and, beneath it, the whole record
in tabs. It is an aggregation view. Nothing is stored for it, and nothing is worked out afresh: each tab reads the module that
holds that part of the record, at the moment the tab is opened.

## Tabs and where each reads from

| Tab | Read from |
|---|---|
| Overview | `people.student`, `people.student_contact`, `people.academic_position` and `people.lifecycle_recommendation` (the cohort engine), `records.graduand`, `assessment.student_standing`, and this session's school fees from `finance.payment_position`. The existing panels follow: classification, matriculation, finance, standing, clearances, registration, record history |
| Biodata | the existing biodata panel, unchanged |
| Admission | `admissions.candidate` and its CAPS row, `admissions.application`, `admissions.fee_reference`, `admissions.programme_change_request`, `people.transfer_application`, `people.document` |
| Level progression | the level of each session from `people.enrolment` and `registration.course_registration`; every change of level, programme or status from the audit trail (`audit.entries`, which keeps the whole row before and after each change); `people.cohort_decision`; `people.status_change`; `people.deferment` |
| Course registration | every `registration.course_registration` with its courses, and every `registration.registration_reset`, which keeps each version a reset replaced |
| Results | `assessment.student_results`, `assessment.student_gpa`, `registration.carryovers` |
| Fees and payments | every `finance.payment_reference` (school fees and every other purpose) with the gateway's last word; each session's school fees from `finance.payment_position`; `finance.refund`, `finance.overpayment_decision`, `finance.old_payment_withdrawn`, `finance.wallet_entry`; the Bursary's payment reallocations (`/finance/payment-swaps/of/{id}`) |
| Hostel | `hostel.history`, `hostel.event` |
| Clearance | `clearance.process` with its items, and the per-purpose `clearance.item` rows |
| Documents | `credentials.issued` (with revocation), `credentials.transcript_request`, `credentials.identity_card`, `people.document` |
| ICT support | `helpdesk.ticket` (raised by the student) and `helpdesk.support_action` |
| Notifications | the existing messages panel (`/api/v1/students/{id}/messages`) |
| Activity | `audit.entries` for the record, its contact row and its course registrations; ICT support actions; matriculation numbers issued; payment reallocations; documents issued. Newest first, 500 at most |

The API is `GET /api/v1/student/students/{id}/full/{section}`: `overview`, `admission`, `progression`, `registrations`, `results`,
`finance`, `hostel`, `clearance`, `documents`, `support`, `audit`, and `receipts/{reference}`
(`StudentFullRecordController`). The page reads the overview with the record and every other tab when it is first opened. A
tab can be opened from the address, e.g. `/students/{id}?tab=finance`. The student quick view, opened from any list, links
straight to **Results** and **Payments**.

## What is never filled in

- **Levels.** A session is listed only when the record holds an enrolment or a course registration for it. When the two name
  different levels, both are shown, marked as a disagreement. No level is worked out to fill a gap.
- **Changes.** The timeline lists only what the audit trail, the cohort decisions, the instruments of a change of status and
  the deferments record. On a database whose audit trail began late (the Railway copy's begins on 13 Oct 2026), earlier
  changes are not shown, and the page says so.
- **Results.** A result is shown as published. A course with no sheet reads *Not yet submitted*; a sheet not yet through
  approval reads *Awaiting approval*; a published sheet the student is not on reads *No result*. A missing result is never
  shown as a zero or a fail, and an unpublished result prints no scores.

## Who reads what

Every section is held to the reader's bound on the student by the record's own rule (`StudentReach`, moved out of
`StudentController` unchanged). A Head of Department, Dean or Faculty Officer reads only the students of their department or
faculty. A lecturer reads only students on the courses they teach. The server refuses a section whatever the page shows.

| Office | Sections |
|---|---|
| Registry, academic offices, heads, platform, Vice-Chancellor and Deputy, College offices | all except those below |
| Fees and payments, receipts | only the fee readers of the record (`StudentController.FEE_READERS`): Bursary, Students Account Officer, Finance Controller, Registry, academic heads, Audit, ICT, Administrator, Super Administrator |
| ICT support | Registry, academic offices and heads, ICT, Administrator, Super Administrator, Vice-Chancellor and Deputy, Audit |
| Activity | Registry, Records, ICT, Administrator, Super Administrator, Audit |
| Lecturer | overview, course registration, results |
| Library | overview, clearance |
| Security | overview, clearance, documents |
| Housing | overview, hostel, clearance |
| HR | overview |

A lecturer, the Library, Security, Housing and HR are not sent the student's contact details on the overview. No student reads
any of it: the student has their own portal. Passwords, password hashes and tokens are on no tab.

## Receipts

**View receipt** on a paid payment opens the official receipt in a window. It is the student's own receipt:
`StudentPortalService.receipt` gives the facts and the existing receipt screen draws them. **Download PDF** uses the existing
receipt PDF (`lib/receipt-pdf`), and **Print** prints that PDF. The API serves a receipt only when all of these hold:

- the office reads fees;
- the student is within the office's reach;
- the reference belongs to this student. A reference of another student, asked for through this student's record, is not found;
- the payment is confirmed.

The page's routes (`/students/{id}/receipt/{reference}` and `…/pdf`) only call the API with the signed-in session. The QR opens
the existing public verification page and carries only the reference and the signed check code.

## Print and downloads

**Print full record** prints the chosen sections (only those the office reads) under the University's header, in landscape,
marked confidential. It is a document built from the data, not a screenshot. It goes on the export log. Each table has an
**Excel** button: a branded workbook with S/N first, also on the export log.

## Performance

On the live-shaped copy, each section answers in 0.02–0.4 s; the first overview after a start takes about 1.1 s. The finance
section reads one student's references. The overview reads only this session's position, never the payment history.

## Tests

- `StudentFullRecordIT`: sections, receipt IDOR, unconfirmed receipt, verification of the QR's code, per-office sections,
  Head of Department scope, lecturer, student refused, a level correction read back from the audit trail.
- `lib/full-record.test.ts`: tabs, result words, level history, timeline, tables, print escaping.
