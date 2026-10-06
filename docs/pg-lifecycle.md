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
| Offer letter | Applicant | `/pg/offer/pdf` after the acceptance fee |
| Acceptance | Applicant | The acceptance fee accepts the offer (`pg_confirm_fee`) |
| Physical screening | School, Secretary, Academic Office, Registry | `admissions.pg_screening_policy` per session; `POST …/screening/schedule`, `POST …/screening/decision`; the desk at `GET /api/v1/pg/screening` |
| On the register | Automatic on clearance, or the School where the session does not screen | `admissions.pg_admit`: the student row (ADMITTED), the applicant's password as the student account, contact and address carried over |
| School fees | Student, Bursary | The student portal and the fee engine (`finance.new_reference`, the SCHOOL_FEES_PAYMENT window) |
| Course registration | Student, the desk endorses | `/api/v1/pg/coursework` (`admissions.pg_registration`) |
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
- **PG coursework keeps its own course list** (`admissions.pg_course`, V211). Moving it onto the canonical
  `catalogue.course` + `course_offer` would migrate every PG registration, score and GPA. That is a decision for the
  University, not part of this change.

## Not built

- A department recommending a different programme from the one applied for.
- A waiting list for postgraduate admission.
- An SMS channel for the PG notices. They go through `platform.queue_notice` by email, like the rest of the School's
  notices.
