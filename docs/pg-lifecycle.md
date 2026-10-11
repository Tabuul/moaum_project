# The postgraduate lifecycle, application to matriculation (V337)

The School of Postgraduate Studies' pipeline was already built (V201–V228, V255, V336). V337 inspected it against the
University's full lifecycle and changed only what was missing or wrong. This page maps each stage to what runs it.

## The stages

| Stage | Who | What runs it |
|---|---|---|
| Apply, create the account | Applicant | `/pg/apply` → `POST /api/v1/pg/apply` (`admissions.pg_apply`), the POSTGRADUATE_APPLICATION window (V312) |
| Application fee | Applicant, Bursary | `admissions.pg_fee_reference` kind APPLICATION, paid at the gateway and verified server-side (`PaymentsRepository` → `admissions.pg_confirm_fee`) |
| Academic record, referees, documents, passport | Applicant | `/pg/portal`; editable only while the application waits on the department (SUBMITTED) or is RETURNED; documents and passport also while screening is under way (ACCEPTED) |
| Department review | Head of Department (own department only) | `GET /api/v1/pg/applications`, `POST …/dept-decision` (recommend / not recommend), `POST …/return` (to the applicant, with what to correct) |
| Faculty vetting | Dean (own faculty only) | `POST …/faculty-decision` on a department's recommendation |
| School's final decision | School, Secretary | `POST …/spgs-decision` on FAC_RECOMMENDED, FAC_DECLINED or DEPT_DECLINED; `POST …/return-to-department` sends a recommendation back |
| Admission status checking | Applicant, Director of ICT | The POSTGRADUATE_ADMISSION_STATUS_CHECKING window; `admissions.pg_status_checking` |
| Offer letter | Applicant; the student later | `/pg/offer/pdf` after the acceptance fee; once on the register, My Documents and the dashboard's next steps (`/student/pg-offer/pdf`, V389) |
| Acceptance | Applicant | The acceptance fee accepts the offer (`pg_confirm_fee`) |
| Physical screening | School, Secretary, Academic Office, Registry | `admissions.pg_screening_policy` per session; `POST …/screening/schedule`, `POST …/screening/decision`; the desk at `GET /api/v1/pg/screening` |
| On the register | Automatic on clearance, or the School where the session does not screen | `admissions.pg_admit`: the student row (ADMITTED), the applicant's password as the student account, contact and address carried over |
| School fees | Student, Bursary | The student portal and the fee engine (`finance.new_reference`), behind the PG_SCHOOL_FEES_PAYMENT window (V389); only the lines addressed to postgraduate students (V391) |
| Course registration | Student, the Head of Department approves | Course Registration (`/student/register`) on the School's classes, in the School's session, behind the PG_COURSE_REGISTRATION window (V389). Earlier registrations on `admissions.pg_registration` stay and are read |
| Matriculation | Academic Office | Matriculation Management (V267): batches per faculty, generate, validate, issue; the number becomes the username |

## The states

The application keeps its own states; the applicant reads a translation of them.

| Application state | The applicant reads |
|---|---|
| SUBMITTED | Submitted, with the department (the department sees it only once the fee is confirmed) |
| RETURNED | Returned for correction, with the department's note and a Resubmit button |
| DEPT_RECOMMENDED, DEPT_DECLINED, FAC_RECOMMENDED, FAC_DECLINED | Under review (a recommendation is internal and never the applicant's answer) |
| OFFERED, NOT_OFFERED | The status, once it may be checked; until then "decided: check your status" |
| ACCEPTED | Offer accepted; the screening panel where the session screens |
| ADMITTED | On the register: the admission number, the student portal, school fees |

Admission status checking returns ADMITTED (OFFERED, ACCEPTED, ADMITTED), NOT_ADMITTED (NOT_OFFERED) or PENDING
(anything before the School's decision). The department's and faculty's notes are never shown to the applicant. The
School's note is shown with the status.

## What V337 changed

1. **Department isolation, everywhere.** The list, the record, the documents and the decisions were already held to
   the Head of Department's department. These were not, and now are:
   - the School's dashboard;
   - the register of postgraduate students;
   - the coursework desk (courses, registrations, endorsement, scores and the course upload).

   The Secretary's dashboard is now for the School-wide offices only. A department or faculty sees an application only
   once its fee is confirmed.
2. **Correction.** The department returns an application to the applicant with what to correct, and the applicant
   resubmits it. The School returns a recommendation to the department, which decides again. A decision once made
   cannot be changed until it is returned.
3. **The School's word is final.** A department's or faculty's "not recommended" now reaches the School for the final
   decision. It used to end the application without one.
4. **Admission status checking in its own window.** Any valid applicant may pay the checking fee once, before or
   after the decision, while the window is open. They then check as often as they like. The window is OPEN until the
   Director of ICT first configures it, so today's behaviour continues. An applicant whose offer is accepted continues
   whatever the window. It is on the ICT Application Registration Control page.
5. **Physical screening.** It is configured per session: required or not, the venue, the dates, the instructions and
   the documents to bring. The officer works on the record the applicant already gave and records the outcome:
   - documents verified and missing;
   - issues and remarks;
   - the decision: CLEARED, NOT_CLEARED or CORRECTION_REQUIRED (the last two need a reason the applicant reads).

   CLEARED admits the applicant to the register in the same transaction. `pg_admit` refuses anyone screening has not
   cleared. Applicants accepted before a session's policy was first stated are not held.
6. **Matriculation counts postgraduate registration.** Matriculation Management counted only the undergraduate
   registration, so a postgraduate could never be eligible. An ENDORSED `admissions.pg_registration` of the session
   now counts. The screening gate (`admissions.screening_ok_student`) includes the postgraduate screening.
7. The admitted student carries the applicant's state of origin and contact address.

## Kept as it is, on purpose

- **Faculty vetting** between the department and the School (V226) is the University's existing workflow.
- **The student record is created on admission, before school fees.** The fee engine charges a student row, and the
  undergraduate intake works the same way. The applicant's identity and password carry over, with no second account.
  "Matriculation pending" is the student's ADMITTED status, until a number is issued.
- **The password at matriculation is not reset.** Issuing a number changes the username and records the old one
  (`people.student_username_change`). The password the applicant chose is kept, as for every student.
- **Registration before matriculation.** Matriculation Management requires an approved registration for every student
  (V064, V267). That is existing University policy, not one V337 invented.
- ~~PG coursework keeps its own course list~~: moved onto the University's engines by V389 (below), without migrating
  a single past registration or score.

## Not built

- A department recommending a different programme from the one applied for.
- A waiting list for postgraduate admission.
- ~~An SMS channel for the PG notices~~: V389 sends the applicant's notices by SMS as well as email.

## Coursework on the University's engines (V389)

A postgraduate student is now a stream of the one portal, as the Centre for Continuing Education's students are (V380).
Nothing of the School's own coursework was deleted or rewritten: past registrations, scores, GPAs and endorsements stay
where they are and are read alongside the new results.

| Part | What runs it |
|---|---|
| Courses | Every PG course is a course of the University's pool (`catalogue.course`), held once whatever the number of programmes that take it, bound to each programme at its award level (`catalogue.course_offer`, source PG; a deficiency course as Deficiency, a research course as Research). A course the School adds on its desk goes into the pool by trigger (`catalogue.pg_bind_course`). Each `admissions.pg_course` row now names its course (`course_code`); rows whose code is not a valid course are listed on the desk (`admissions.pg_course_unmapped`) until corrected. |
| Session and calendar | The School's own session and semesters (`admissions.pg_academic_session`, `admissions.pg_semester`), read by `people.student_current_session` and `registration.calendar_semester` for a PG student. The University's current session is not used for them. |
| Classes | The stream PG. The School (School, Secretary, Academic Office) opens the semester's classes (`catalogue.pg_open_classes`: every course bound to a programme with live PG students, plus carry-overs) or one class (`catalogue.pg_add_class`) on Postgraduate courses. A Head of Department cannot open them. The Head of Department allocates the lecturer as for any class. |
| Registration | Course Registration, on the University's registration engine, with its rules unchanged (units, prerequisites, approval). The gate (`registration.pg_gate_of`) is: the School's classes set up, the School's semester open and within its dates, and the PG_COURSE_REGISTRATION window open where the Directorate of ICT holds one. The old endpoint refuses new registrations with PG_REGISTRATION_MOVED. |
| Windows | PG_COURSE_REGISTRATION and PG_SCHOOL_FEES_PAYMENT on ICT window management (`/ict/windows`), with the same open / close / extend / reopen actions and audit as every window. |
| Examinations and results | ICT sets PG examination sessions (stream PG); score sheets move on the one results chain; the broadsheet and Senate desks have a Postgraduate tab. A PG class is graded on the School's scale, kept as policy version `grading` scope POSTGRADUATE (A 70, B 60, C 50, F below 50), the scale `admissions.pg_grade` applied. |
| GPA, statement, transcript | `admissions.pg_course_results` reads the old coursework and the published results together; `pg_gpa`, `pg_cgpa` and the statement of result read it. A deficiency course earns no credit. |
| Notices | `admissions.pg_tell_registration`, hourly (`PgRegistrationClock`): PG students are told by email and SMS when registration opens on the School's calendar (only where no PG window is configured, since ICT's window sends its own) and, three days before it closes, those not yet registered. Each notice is sent once per semester (`admissions.pg_registration_notice`). No password or fee detail is in a notice. |
| Document centre | My Documents: the offer of admission (`/student/pg-offer/pdf`, from the student's own application) and the documents submitted with the application (`GET /api/v1/pg/student/documents/{id}/content`, held to the student's own application). Certificates and transcripts as for every student. |
| Next steps | `admissions.pg_next_steps(student)` works out the dashboard's next steps from the record: offer letter, school fees (from `finance.fee_stated` and `finance.position`, never from the page), registration, examination card, results, matriculation. |

The student's menu: Course Registration, Results by semester (both sources), Academic progress, Timetable, Attendance,
Examinations, CBT Examinations, Deferment, My Documents.

## Fees and matriculation (V391)

- **A PG student owes only the School's fee lines.** A line of the fee schedule that names no level, no entry mode, no
  programme and no postgraduate fee group is the full-time students' line. Before V391 it reached postgraduate students
  too, so a PG student was charged the undergraduate school fees and portal charge. A line now reaches a PG student
  (entry mode POSTGRADUATE, or a programme of category POST GRADUATE) only when it names a postgraduate level (700, 800,
  900), the POSTGRADUATE entry mode, the student's programme, or the Bursary's Postgraduate fee group. One rule
  (`finance.pg_line`) is read by the charges, the session total, the semester's due, the stated test and the Bursary's
  bulk positions. Until the Bursary states PG lines for a session, a PG student reads "not yet stated", and Course
  Registration refuses on the fee gate (V361) as it does for every student. Payments already made are not touched.
- **Matriculation.** A PG student is matriculated in the session they registered in, the School's: the candidate list
  already counts an approved registration of the session chosen. Matriculation Management now names the School's session,
  with how many PG students registered in it wait for a number, and opens it in one click.
