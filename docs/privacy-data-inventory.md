# Personal-data inventory of the portal (October 2026)

The audit behind the Privacy Policy (V441): what personal data the portal actually holds, read from the schema and the
code on 13 October 2026, not from what a portal of this kind might hold. The policy's sections are written from this
table and must not claim more. "Where" names the table or module; "Who" names the offices that may read it through the
portal (every read goes through the office's own screens and scope — a department sees its own students, a faculty its
own departments; the Audit office and the Vice-Chancellor's office read the audit trail, not the records themselves).
"Store" is the database unless a file store is named: files (photographs, uploaded documents, question images) are
objects in `platform.file_object`, held in the database or in S3-compatible object storage when ICT configures one
(`moaum.files.provider`, region `af-south-1` by default). "Keep" is the retention stated in the governance register
(`governance.processing_activity`) or "while the record stands" where the register names none; the portal runs no
automatic deletion — records are ended, archived or superseded, never silently removed. Classification: **P** personal,
**S** sensitive (health, financial identifiers, national identity numbers), **C** confidential to the University.

## 1 · Identity and contact

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Full name, sex, date of birth, state of origin, entry mode/session/level, programme, status | `people.student` (admission, migration upload, Registry correction) | The student record itself | Registry, Academic Office, the student's department and faculty, Exams and Records, Bursary (name and number), Student Affairs, Library, the student | DB | Permanent (academic record) | JAMB list (origin of the admission) | P |
| Matriculation, admission and JAMB numbers | `people.student`, `admissions.candidate` | Identification across every module | As above; public verification pages answer a document number with the holder's name and award only | DB | Permanent | JAMB (the JAMB number is JAMB's) | P |
| Phone, e-mail, contact address | `people.student_contact` (the student, the Registry, biodata uploads) | Notices, reminders, password resets, the contact prompt | Registry, ICT Support (to reach the student), the Notification engine, the student | DB | While the record stands | eBulkSMS (phone, for SMS), the University's SMTP mail service (e-mail) | P |
| Passport photograph | `people.student_photo` (the student, once; the Registry) | ID card, slips, documents, CBT invigilation list | Registry, Security (ID cards), Exams (invigilation), the student | File store | While the record stands (replacements kept with the reason) | — | P |
| Next of kin | `admissions.application.next_of_kin` (the application form) | Emergency contact at admission | Admissions, Registry | DB | With the application | — | P |
| Biodata completion state (what is missing) | `people.biodata_status_snapshot` | The biodata gate and reminders (V423, V426) | ICT, Registry, the student | DB | Recomputed every 15 min | — | P |
| Staff number, names, e-mail, phone | `iam.person`, `hrm.staff_profile` | Sign-in, HR record, notices | HRM, the person, their head of unit; ICT (accounts) | DB | Duration of service + statutory | SMTP, eBulkSMS | P |
| Staff PNO, sex, first appointment, rank, step, salary scale, department | `hrm.staff_record` (HR upload) | The HR record, course allocation, workload | HRM, the person, Dean/HOD (names and ranks) | DB | Duration of service + statutory | — | C |
| Staff bank name, pension PIN, payslips | `hrm.employment`, `hrm.payslip` | Payroll | HRM, Bursary, the person (own payslips) | DB | Statutory | — | S |
| Staff photograph | `hrm.staff_photo` | Staff ID card | HRM, Security, the person | File store | Duration of service | — | P |
| Job applicants' names, e-mail, phone | `hrm.applicant` | Recruitment | HRM | DB | With the recruitment exercise | — | P |
| National Identification Number | `jupeb.application.nin` only (the JUPEB application form) | JUPEB registration with the Board | JUPEB office, the applicant | DB | With the application | JUPEB (Board registration) | S |
| Guardian / next of kin (JUPEB) | `jupeb.application` | Minors' guardians, emergency contact | JUPEB office | DB | With the application | — | P |

## 2 · Admission

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| JAMB registration number, UTME score, subjects, programme applied, sex, state, LGA | `admissions.caps_row` / `jamb_admission` (JAMB's lists uploaded by Admissions), `admissions.candidate` | Eligibility, screening, admission | Admissions, Academic Office, Registry, the applicant (own) | DB | 7 years (automated admission scoring) | JAMB (origin; admission lists are reconciled with CAPS) | P |
| Applicant account: e-mail, phone, password (bcrypt hash), sign-in events with IP | `admissions.applicant_account`, `admissions.applicant_event` | The applicant's own portal | ICT Support (never the password), the applicant | DB | With the application | — | P |
| O'Level results, screening form, documents uploaded (certificates, birth certificate, state of origin, passport) | `admissions.olevel_*`, `screening_form` (submitted IP), `application_document_blob` | Screening, clearance | Admissions, screening officers, Registry at clearance | File store | With the application | — | P |
| Declaration and undertaking timestamps, the IP at declaration | `admissions.application` | Proof of the applicant's own act | Admissions | DB | With the application | — | P |
| Post-UTME CBT attempt (score, events, IP, browser) | `assessment.cbt_attempt` (application_id) | Post-UTME examination | Exams, Admissions, ICT (the engine) | DB | 5 years (CBT session logging) | — | P |
| CCE candidates: DOB, e-mail, phone, LGA, nationality | `admissions.cce_candidate`, `cce_batch_row` | Part-time admission | CCE office, Academic Office | DB | With the application | JAMB CCE list | P |
| Postgraduate applicants: DOB, nationality, address, referees' e-mail and phone, documents | `admissions.pg_applicant`, `pg_referee`, `pg_document` | PG admission | School of Postgraduate Studies | DB / file store | With the application | Referees are e-mailed | P |
| JUPEB applicants: DOB, addresses, NIN, guardian, documents, payments | `jupeb.*` | JUPEB admission, Board registration | JUPEB office, Bursary (fees) | DB / file store | With the application | JUPEB Board | S |

## 3 · Academic

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Course registration, carry-overs, unit loads | `registration.*` | The registration engine | Student, department, faculty, Academic Office, Exams | DB | Permanent | — | P |
| Scores, grades, results, CGPA, standing, amendments | `assessment.*`, `results` chain | Results and transcripts | Lecturer (own course), HOD, Dean, Exams and Records, Senate stage, the student (published results) | DB | Permanent; never deleted | — | P |
| Attendance marks per lecture | `attendance.mark` | Attendance standing, exam eligibility where enabled | Lecturer, HOD, the student | DB | With the session | — | P |
| LMS material access, submissions | `lms.access`, `lms.submission` | Teaching | Lecturer, the student | DB / file store | With the session | — | P |
| CBT attempt: paper, answers, times, score, IP, browser, events (tab switch, window blur, fullscreen exit, network, copy/paste, multiple login), time back, violations | `assessment.cbt_attempt`, `cbt_answer`, `cbt_event` | The examination and its integrity | Exams, invigilators, moderation, the student (own result when released) | DB | 5 years | — | P |
| Camera at CBT (by consent): presence and face signals computed in the browser; **no video or image is kept** — only the consent/decline time and the signal events | `cbt_attempt.camera_consent_at`, `cbt_event` | Proctoring where the exam asks for it | Exams | DB | 5 years | — | P |
| Deferments, transfers, programme corrections (reasons, explanations, documents) | `people.deferment`, `people.deferment_document_blob` | Academic standing decisions | Department, faculty, Registry, Bursary (fee state), DVC | DB / file store | Permanent | — | P |
| Clearance (fresh, final) items and uploaded documents | `clearance.*` | Clearance decisions | The clearing units, Registry, the student | DB / file store | Permanent | — | P |
| Graduation, certificates, transcripts (holder, programme, award, class) | `credentials.issued`, `certificate`, `transcript_request` (recipient address/e-mail) | Credentials and their verification | Exams and Records, Registry, the student, the recipient named by the student; the public verification page confirms a document number with name, programme and award | DB | Permanent | Recipients named by the student (institutions, employers) | P |
| Alumni profile (residence, country, employment, employer, occupation, LinkedIn) | `clearance.alumni_profile` (the graduate) | Alumni relations | Alumni office, the graduate | DB | While the record stands | — | P |

## 4 · Financial

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Fee references, amounts, purpose, session, status, channel, the provider's transaction reference | `finance.*`, `reporting.payments` | Fees, receipts, clearance of windows | Bursary, Audit, the student/applicant (own), departments (paid/unpaid lists), ICT Support (diagnosis, never a status change) | DB | Statutory (tax) retention | Paystack, Flutterwave, Interswitch (Quickteller / WebPAY / PAYDirect) — whichever ICT has configured | P |
| Card or bank details | **Not held.** Card details are entered on the provider's own page (hosted checkout); PAYDirect pays at the bank | — | — | — | — | The provider | — |
| Refunds and wallet withdrawals: bank name, account number | `finance.refund`, `finance.wallet_withdrawal` | Paying money back | Bursary | DB | Statutory | The bank | S |
| NELFUND loan wallet imports | `finance.*` (NELFUND source) | Loan-funded fees | Bursary, the student | DB | Statutory | NELFUND (origin) | P |
| Staff payroll and expenditure | `hrm.payslip`, `expenditure.*` | Payroll, grants | HRM, Bursary | DB | Statutory | — | S |

## 5 · Health

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Blood group, genotype, allergies (the student consents to or restricts these) | `health.profile` (the student) | The clinic's care | University Health Services (office `services`); the student; nobody else | DB | 7 years after last contact | — | S |
| Appointments, visits, clinical notes, outcomes | `health.appointment`, `visit`, `note` | Care | University Health Services only; the student sees own outcomes, never the note | DB (the note is audit-exempt on purpose) | 7 years after last contact | — | S |
| Fitness status | `health.profile.fitness` | Registration/clearance where fitness is required | Registry and the department see the status only | DB | 7 years after last contact | — | S |
| Who opened a patient record | `health.record_access` | Shown to the patient on request | Clinic head, the patient on request | DB | 7 years | — | C |

## 6 · Accommodation, library, student affairs

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Hostel application, allocation (hall, room, bed), check-in/out, inspections, discipline | `hostel.*` | Accommodation | Housing, Student Affairs, hall wardens, Security (occupancy), Bursary (fees), the student | DB | While the record stands | — | P |
| Library loans, reservations, fines | `library.*` | Library services | Library, the student | DB | While the record stands | — | P |
| SIWES placements | `siwes` module | Industrial training | SIWES unit, department, the student | DB | With the session | Placement organisations named by the student | P |

## 7 · Identity cards and security

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Student and staff ID cards: card number, issue, validity, state, replacement | `credentials.identity_card`, stationery batches | Issuance and verification | Security (prints), Registry/HRM (records), the holder (status only — the printable card is the Security Unit's) | DB | While the card stands; ended cards kept | — | P |
| Signed check codes on cards, slips and letters | `credentials.*`, `platform.check_code_cutover` | Public verification without exposing the record | Anyone with the code sees validity and the public fields only | DB | Permanent | — | C |

## 8 · Support, notices, communication

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Support tickets: requester name/number/e-mail/phone, subject, description, attachments, actions (with source IP) | `helpdesk.*` | ICT Support and student support | The queue's agents (by posting scope), the escalated office, the requester | DB / file store | While the record stands | — | P |
| Notices sent: channel, recipient address, subject, body, delivery state, provider reference | `platform.notice`, `notice_receipt` | Every official message (admission, fees, registration, results, clearance, biodata reminders, security) | ICT (the outbox), the office that sent it, the recipient | DB | Kept; a cancelled message is marked, never deleted | eBulkSMS (SMS), SMTP mail service (e-mail) | P |
| Notification preferences | `platform.notice_preference` | The person's channel choices where the University allows a choice | The person, ICT | DB | While the record stands | — | P |
| Campaigns and announcements | `platform.notice_campaign` | Bulk notices from the record (Dean/HOD bound) | The sending office | DB | Kept | As above | P |

## 9 · Authentication, sessions, audit

| Element | Where collected | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Password hashes (bcrypt, cost 12) — never readable | `iam.credential`, `iam.student_account`, `admissions.applicant_account`, `jupeb.account` | Sign-in | Nobody reads them; ICT Support issues temporary passwords or reset links | DB | While the account stands | — | C |
| Sign-in events: username, outcome, source IP, session | `iam.sign_in_event`, `iam.student_event`, `admissions.applicant_event` | Security, lock-outs, throttles | ICT, Audit, Security (posture) | DB | Kept | — | P |
| Sessions: person, acting office, issued, last seen, ended and why (idle timeout V437) | `platform.session` | The server's authority over a signed-in session | ICT (monitor: names and offices only) | DB | Kept | — | P |
| Cookies: `moaum_session` (the session token; httpOnly, SameSite=Lax, Secure in production), `moaum_office` (the acting office), `moaum_jupeb` (the JUPEB applicant's session) — **essential only; no advertising or analytics cookies** | The browser | Keeping the person signed in and acting as one office | — | Browser | Session length | — | — |
| Browser storage (not sent to the server): idle-timeout clock, a CBT attempt's answers kept on the device until submitted, text size, recent searches, the session-policy cache | The browser | Convenience and resilience | — | Browser | Until cleared | — | — |
| Audit trail: actor, office, action, before/after state, reason, source IP, hash chain | `audit.entries` (monthly partitions) | Accountability; tamper-evident | Audit office, Deputy Audit, ICT, VC/DVC, Registrar (the audit log screen); an entry shows the record it concerns | DB | Kept per the audit retention (partitions prepared through 2028) | — | C |
| Website statistics | `website` module | Public figures (counts of programmes, students by category) — **no visitor tracking** | Public | DB | — | — | — |

## 10 · Files

| Element | Where | Purpose | Who | Store | Keep | Third party | Class |
|---|---|---|---|---|---|---|---|
| Uploaded documents and photographs: the object key, type, size, SHA-256 | `platform.file_object` and the owner tables (`*_blob`, `*_photo`) | Every document the modules hold | The owning module's offices and the person; never public | DB or S3-compatible object storage (`af-south-1` by default) | While the owning record stands; orphaned objects swept | The object-storage provider when configured | P |

## 11 · Governance records (the University's own)

`governance.processing_activity` (the register of processing: activity, lawful basis, sensitive, retention, DPIA state),
`governance.dsr` (data-subject requests with their due dates — the privacy request mechanism of the policy files into
it), `governance.dr_drill` (backup/restore drills). V441 restates the register's CBT row to what the engine does
(camera presence signals by consent, no video or image kept) and widens the request kinds with COMPLAINT and INQUIRY.

## Items the policy flags for the Data Protection Officer / legal confirmation

1. The compliance statement: the policy says the University processes personal data "in accordance with applicable data
   protection laws and regulations, including the Nigeria Data Protection Act 2023" and names no certification.
2. Lawful bases per activity: taken from the governance register as seeded (V075); the DPO confirms them.
3. Retention periods: those the register states; "while the record stands" elsewhere.
4. Third-party providers: the configured payment gateways, eBulkSMS and the mail service are read from the configuration
   at render time; hosting and object-storage providers are named by ICT in the policy's own section.
5. Processing outside Nigeria: object storage defaults to the `af-south-1` region (Cape Town) when S3 is configured, and
   hosting is on cloud infrastructure — the DPO confirms the safeguards wording.
6. Minors: applicants (JUPEB, UTME) may be under 18; guardian details are taken on the JUPEB form only.
7. The request-handling period: the governance log's default of 30 days from receipt.
8. The privacy contact (DPO name, office, e-mail, phone) must be entered before publication.
