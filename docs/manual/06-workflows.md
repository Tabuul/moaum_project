# 06 — Business Workflows

**MOAUM Unified University Portal · Rev. Fr. Moses Orshio Adasu University, Makurdi · Directorate of ICT**

This volume describes every end-to-end business workflow the portal runs today, exactly as the code runs it: the stages, the office that acts at each, the rule that admits or refuses the act (with the message the actor sees), the data written, the status that changes, the notice sent, the document produced, and what happens on rejection, return or lapse. It is built from the audit dossiers of the portal at commit `8c2b6fa` (migrations to V263). Where a workflow has a stage the code does not yet perform, the stage is marked and listed under *What is not implemented*; nothing here is presented as working unless it does.

## How to read this volume

- Each workflow opens with a flow diagram in a `text` block using the real status and stage names as the database holds them, then a **stage table** with eight columns: Stage · Who starts/acts · Precondition / validation (rule and message) · Data created/changed · Status change · Notification · Document generated · On rejection / return / lapse.
- Offices are named by title with the office code in backticks on first use, e.g. Registrar (`registrar`), Deputy Registrar (Academic Affairs) (`dregistrar`), Academic Officer / Academic Office (`academic`), Director of ICT (`ict`), Bursar (`bursar`), Head of Department (`hod`), Dean (`dean`), Faculty Officer (`facultyofficer`), Examinations Officer (`exams`), Exams & Records (`records`), Lecturer (`lecturer`), Student (`student`), Applicant (`applicant`), Super Administrator (`super`), System Administrator (`admin`).
- Messages in quotation marks are the exact texts raised by the SQL functions or the Java services. A SQL refusal (SQLSTATE 23514) reaches the screen as HTTP 422 with the text as written; a Java `DomainRuleViolation` carries a code such as `REG_UNITS_OUT_OF_RANGE` and a remedy.
- Every state table named is attached to the audit spine: a write with no acting person is refused by the database, and every write carries the `X-Reason` header the screen sends. See *03 Technical Documentation* for the spine and *08 Database Reference* for the tables.
- Notices are rows in `platform.notice` (channel EMAIL or SMS, state QUEUED → SENT | FAILED) queued by `platform.queue_notice` and dispatched by `NoticeDispatcher` every minute once a mail or SMS provider is configured (see *02 Administrator Manual*). "Email + SMS" in a table means both rows are queued; delivery depends on the provider configuration.
- Implementation status tags: **IMPLEMENTED**, **PARTIALLY IMPLEMENTED**, **CONFIGURED BUT UNUSED**, **PLACEHOLDER**, **NOT IMPLEMENTED**.
- Screens are named by their menu label or page title with the URL in backticks. Navigation paths appear as `text` blocks. Exports: the branded Excel and print exports put **S/N** as the first column, generated at export time; names sort A–Z.
- Cross-references: *01 User Manual*, *02 Administrator Manual*, *03 Technical Documentation*, *04 Role & Permission Matrix*, *05 Module & Navigation Guide*, *07 API Reference*, *08 Database Reference*, *09 Feature Status Report*.

## Table of contents

1. [The student lifecycle end to end](#1-the-student-lifecycle-end-to-end)
2. [Undergraduate admission workflow](#2-undergraduate-admission-workflow)
   - 2.1 Admission settings and the load cut-off
   - 2.2 CAPS lists: load, reconcile, commit, withdraw
   - 2.3 Applicant registration, fee and form
   - 2.4 Screening seating: legacy batches and the V260 CBT desk
   - 2.5 Check-in and attendance
   - 2.6 Scores, merit list, decisions and releases
   - 2.7 Undertaking, acceptance and decline
   - 2.8 Clearance items and intake to the register
   - 2.9 The Direct Entry variant
   - 2.10 The JAMB admission-status upload path
   - 2.11 What is not implemented
   - 2.12 Programme eligibility and course suggestions (V266)
   - 2.13 The admission lifecycle after the offer: acceptance, online screening, change of programme, fees, registration, matriculation (V269)
3. [Postgraduate admission, research and external examiners](#3-postgraduate-admission-research-and-external-examiners)
   - 3.1 Postgraduate admission
   - 3.2 Coursework registration and results
   - 3.3 The research lifecycle (sixteen stages)
   - 3.4 External examiners
   - 3.5 What is not implemented
4. [Matriculation with the V263 number format](#4-matriculation-with-the-v263-number-format)
   - 4.1 The issue workflow
   - 4.2 How the number is built
   - 4.3 Refusal conditions
   - 4.4 The configuration workflow
   - 4.5 What is not implemented
   - 4.6 Matriculation Management: prepared, reviewed, issued (V267)
5. [Academic workflow: structure, registration, results](#5-academic-workflow-structure-registration-results)
   - 5.1 Structure upload, curriculum binding and course allocation
   - 5.2 Session and semester opening; course registration
   - 5.3 Score sheets and the approval chain
   - 5.4 Publication, result queries, held scripts
   - 5.5 GPA, CGPA, standing and broadsheets
   - 5.6 The College of Health Sciences variant
   - 5.7 What is not implemented
6. [Finance workflow](#6-finance-workflow)
   - 6.1 Fee schedule to charges
   - 6.2 Reference, payment, confirmation, receipt
   - 6.3 Position and gates
   - 6.4 Other purposes: applicant, postgraduate, hostel, document, transcript, library, transfer, wallet
   - 6.5 Bank credits, refunds, reconciliation, general ledger
   - 6.6 What is not implemented
7. [Deferment, transfer, biodata change and status changes](#7-deferment-transfer-biodata-change-and-status-changes)
8. [Graduation and documents workflow](#8-graduation-and-documents-workflow)
9. [Hostel workflow](#9-hostel-workflow)
10. [ICT help desk, Help & Requests, clinic visit](#10-ict-help-desk-help--requests-clinic-visit)
11. [Human resources and expenditure workflows](#11-human-resources-and-expenditure-workflows)
12. [Identity workflows](#12-identity-workflows)
13. [Consolidated list of gaps across workflows](#13-consolidated-list-of-gaps-across-workflows)

---

## 1. The student lifecycle end to end

The lifecycle is stitched from five modules that each own a part of the record: admissions (`admissions.*`), the student register (`people.student`), registration (`registration.*`), assessment (`assessment.*`), records and credentials (`records.graduand`, `credentials.*`). One person carries three numbers in turn — the JAMB registration number, the admission number `MOAUM/ADM/YY/NNNNNN`, and the permanent matriculation number — and one account: the applicant's password becomes the student's password at first sign-in.

```text
Applicant (JAMB number on the committed CAPS list)
 → application account (stage 0)  APP/YY/NNNNNN
 → application fee confirmed (stage 1)
 → form submitted (stage 2)
 → seated for screening (stage 3)      Post-UTME slip · QR
 → score released (stage 4)
 → decision released (stage 5)          OFFERED | WAITING | NOT_OFFERED
 → undertaking signed + acceptance fee (stage 6)   candidate ACCEPTED
 → six clearance items VERIFIED (stage 7)
 → intake to the register                people.student · status ADMITTED · admission number
 → school fees (first semester) → course registration APPROVED (stage 8)
 → matriculation run / single issue      matric_no · status ACTIVE · MAT/YYYY/NNN (stage 9)
 → academic record: registrations per semester · score sheets → PUBLISHED on a Senate minute
 → GPA / CGPA · standing GOOD | PROBATION | ADVISED_TO_WITHDRAW
 → degree audit → graduand AWAITING → Senate approval → status GRADUATED
 → convocation clearance (8 units) → digital certificate · transcripts
 → alumni register
```

### 1.1 Stage table

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Applicant registers | Applicant, public page `/apply` | JAMB number must be on the committed (or held) CAPS list for the session; `admissions.applicant_lookup` states `nolist`, `none`, `found`, `registered`, `closed` | `admissions.applicant_account`, `application` (number `APP/YY/NNNNNN` from `platform.next_number('APPLICATION',…)`), `candidate` PROPOSED with `entry_level` 100 (UTME) or 200 (DE) | application stage 0 | Email + SMS "Your MOAUM applicant account" | — | "the number … is not on the list JAMB sent the University for {session}"; "an application account already exists for {key}" |
| Application fee | Applicant generates a reference; gateway or Bursary confirms | `new_fee_reference`: "the application fee is already confirmed"; reference lives 24 h | `admissions.fee_reference` `MOAUM-APP-…`; `confirm_fee` sets `fee_confirmed_at`, receipt `RCT-YYYY-NNNNN` | stage 1 | Email + SMS "Your payment receipt · RCT-…" | Receipt (notice text; the applicant screen shows a Receipt panel) | An unpaid reference expires after 24 h; generate a new one |
| Form submitted | Applicant | "the form opens when the application fee is confirmed"; "the next of kin is not given"; declaration ticked (`APP_DECLARATION`) | `application.submitted_at`, `declaration_ip` | stage 2 | none | Application form PDF `/applicant/apply/pdf` | Next of kin cannot change after submission |
| Screening seat | Academic Office / Registrar (legacy desk or CBT desk) | see §2.4 | `application.screening_batch_id`, `seat`; V260 `screening_assignment` | stage 3 (slip visible only when the batch is PUBLISHED) | Email + SMS "Your screening slip is ready" / "Your Post-UTME examination schedule" | Examination slip PDF with QR → `/verify/putme/{token}` | Batch POSTPONED/CANCELLED unseats and tells the candidate |
| Score released | Academic Office (`release_scores`) | score entered or uploaded; `APP_SCORE_LOCKED` after release | `application.score_released_at`; `admissions.screening_result` | stage 4 | Email + SMS "Your screening result is released" | — | "Clear uploaded Post-UTME scores" (type `CLEAR SCORES`) before release only |
| Decision released | Academic Office / Registrar / Deputy Registrar (`release_decisions`) or JAMB status upload | `decide_application`: "an offer is made on a basis"; "a compulsory O'Level credit is missing: …" | `application.decision`, `basis`, `decision_released_at`; candidate PROPOSED → ADMITTED on OFFERED | stage 5 | Email + SMS "You have been offered provisional admission" / "You are on the waiting list" / "The admission decision on your application" (none on the JAMB-upload path) | Admission letter PDF only after acceptance | WAITING and NOT_OFFERED are terminal in code; no promotion from the waiting list exists |
| Acceptance | Applicant signs the undertaking and pays the acceptance fee | `sign_undertaking`: "there is nothing to accept yet"; "this offer was declined on …"; `settle_acceptance` needs both | `undertaking_at`, `acceptance_confirmed_at`, `accepted_at`; candidate → ACCEPTED | stage 6 | Email + SMS "Your place is held" | Offer letter `/applicant/status/letter` (409 "Accept your offer first" until then) | Decline → candidate DECLINED (no notice; not reinstated) |
| Document clearance | Registry (API only; no officer screen) | "clearance opens when the offer has been accepted"; a QUERY carries a note | `admissions.clearance_document` per item; six VERIFIED → `cleared_at` | stage 7 | Email + SMS "A query on your clearance documents" / "You are cleared" | — | Any item back below VERIFIED clears `cleared_at` |
| Intake to the register | Academic Office / Registrar / Deputy Registrar, button "Bring N candidates onto the register" on Report on Admissions `/admissions` | `people.intake(session)`: every candidate ADMITTED or ACCEPTED not yet on the register; refuses (23503) when the programme is not one the University runs | `people.student` (admission number `MOAUM/ADM/YY/NNNNNN`, entry mode/level/session, `curriculum_track` by trigger) | student status ADMITTED | none | — | Runs on ADMITTED, i.e. before acceptance; a candidate whose programme name is unknown stops the run |
| School fees | Student, on School Fees `/student/fees` | `finance.new_reference`: "no charge is stated for {session} yet"; amount ≤ balance | `finance.payment_reference` `MOAUM-FEE-…`; `confirm_payment` → receipt | — | Email + SMS "Your payment is confirmed" | Receipt PDF with QR → `/verify/receipt/{ref}?c=` | Reference expires after 24 h |
| Course registration | Student drafts and submits; HOD approves | `student_submit`: semester fees cleared in full; units within `policy.level_limit`; no approved deferment covering the period | `registration.course_registration`, `entry` | DRAFT → SUBMITTED → APPROVED (or RETURNED) | none | Course form PDF with QR → `/verify/registration` | RETURNED with the HOD's reason; the student edits and resubmits |
| Matriculation | Faculty Officers confirm lists; Academic Office / Registrar / Deputy Registrar run | see §4 | `people.matric_history`, `matriculation_run`; `people.student.matric_no`, `matriculated_at` | ADMITTED → ACTIVE, instrument `MAT/YYYY/NNN` | Email + SMS "Your matriculation number" | — | Queried names are held back; the whole run rolls back on a build error |
| Academic record | Lecturers, desks, Senate | see §5 | `assessment.score_sheet`, `score`, `decision` | sheet ENTRY → … → PUBLISHED | none on publication | Statement of results PDF, broadsheets | Return to ENTRY with a reason |
| Standing | computed | `assessment.standing_of` on the latest published semester | none (computed) | GOOD / PROBATION / ADVISED_TO_WITHDRAW pronounced on screen and on the broadsheet | none | Broadsheet lists | Voluntary withdrawal after four consecutive closed semesters unregistered (Registry closes it) |
| Graduation | Academic Office / Registrar / Deputy Registrar / Records audit; Registrar / Deputy Registrar / Academic Office approve | `records.approve_awards`: minute required | `records.graduand` AWAITING → APPROVED; `people.change_status(GRADUATED)` | ACTIVE → GRADUATED | Email + SMS "Senate has approved your award" | — | Unmet requirement keeps the row AWAITING |
| Certificate and transcripts | Signers issue the certificate; the student requests transcripts | `assert_issuable`: GRADUATED, Senate-approved, convocation clearance complete | `credentials.issued`, `transcript_request` | document ACTIVE | Email + SMS "Your digital certificate has been issued" | Degree certificate PDF; transcript PDFs with QR + code | Revoke (Registrar / VC on a minute) → REVOKED; reissue → REPLACED |
| Alumni | read-only | `records.graduand.senate_state = APPROVED` | none | — | none | — | — |

### 1.2 Notes on the whole

- The applicant's `platform.session` and password carry over: at the student's first sign-in with the admission or matriculation number, `StudentAuthService` verifies the applicant's bcrypt hash and copies it (`CARRIED_OVER`). A student with no applicant account behind them (migrated or postgraduate) has an account opened by the Registry from Student 360 → **Portal account**, which forces a password change.
- The application stage numbers 0–9 are computed by `admissions.application_stage` from the timestamps on `admissions.application`; nothing stores a stage. Stage 8 is "an APPROVED/LOCKED `registration.course_registration` for the session" and stage 9 is `people.student.matric_no`.
- Candidate `offer_state` values: PROPOSED → ADMITTED → ACCEPTED; DECLINED; WITHDRAWN (with the CAPS batch); LAPSED is allowed by the CHECK but nothing sets it.
- The Post-UTME computer-based test itself is not delivered by the portal: the V260 desk schedules, seats and checks candidates in; scores are uploaded (§2.6). The CBT question bank under `/exams/question-bank` is a bank only (§5.7).

> **Planned / Not Yet Implemented:** offer lapse and waiting-list promotion; an officer screen to record the six clearance items; a notice to the applicant when a place is offered by the JAMB status upload; a notice on publication of results; a notice on registration approval or return.

---

## 2. Undergraduate admission workflow

The office side of the UTME / Direct Entry cycle is run by the Academic Office and the Registrar; the Deputy Registrar (Academic Affairs) shares the decision, release and screening desks. Nearly every rule is a SQL function in the `admissions` schema; the controllers call them.

```text
Navigation (academic — Admissions)
 → Admission Settings                 /admissions/settings
 → Upload Applicants and Candidates   /admissions/caps
 → Upload Passport, DOB & O'Level     /admissions/candidate-data
 → Screening Register                 /admissions/screening
 → Post-UTME CBT Schedule             /admissions/putme
 → Upload PUTME Score                 /admissions/scores
 → Compute PUTME Score                /admissions/computed-screening
 → Merit List                        /admissions/merit
 → Direct Entry Screening             /admissions/de-screening
 → Report on Admissions               /admissions
```

```text
session_policy DRAFT ──put_in_force(minute)──▶ IN_FORCE
load_cutoff stated
caps_batch held ──commit_batch──▶ committed        (or ──withdraw_batch──▶ withdrawn)
candidate PROPOSED ──release of OFFERED──▶ ADMITTED ──settle_acceptance──▶ ACCEPTED
                   ──decline_offer──▶ DECLINED
application: fee → submit → seat → score released → decision released → accepted → cleared
screening_batch (V260) DRAFT ──putme_publish──▶ PUBLISHED ──▶ POSTPONED | CANCELLED
putme_exam DRAFT → CONFIGURING → OPEN_FOR_SCHEDULING → SCHEDULING_IN_PROGRESS → SCHEDULED → ONGOING → COMPLETED (CANCELLED)
people.intake ──▶ people.student ADMITTED
```

### 2.1 Admission settings and the load cut-off

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Create the session's settings | Academic Office, Registrar, Deputy Registrar (`AdmissionSettingsController.SECRETARIAT`) on Admission Settings `/admissions/settings` | "Begin from {previous}" copies the earlier session; or create with defaults (weights 70/30, UTME:DE 80:20, Science:Arts 60:40, ELG cap 50, criteria NM 10 / SM 35 / ELG 30 / LOCALITY 25) | `admissions.session_policy`, `selection_criterion`, `faculty_quota`, `programme_rule`, `rule_subject_group`, `catchment_lga` | `session_policy.state` DRAFT | none | — | `ADM_SETTINGS_EXIST` when the session already has settings |
| Edit rules | same | `ADM_WEIGHTS` "The weighting does not total 100%"; `ADM_RATIO_SUM` ("Education is 60:40; every other faculty is the session's 80:20"); cut-offs 1–400; `olevel_credits` 1–9 | rule rows; UTME / DE subject sets (syntax: comma = all, "/" = any one, "N of A/B/C") | — | none | — | In force: weights, ratios, criteria, cut-offs and subject rules are frozen (`ADM_SETTINGS_IN_FORCE` "The {session} settings are in force under {minute} and are not edited."); quotas, catchment and closures stay editable |
| Put in force | same, field "Central Admissions Committee minute" | `put_in_force` refuses without a minute and while `policy_findings` returns anything: "The selection criteria do not total 100%", "The programme quotas do not total the NUC approved quota", "A faculty has no UTME cut-off", "Equality of Local Government exceeds its ceiling" | `session_policy.instrument`, `state` | DRAFT → IN_FORCE | none | — | `policy_in_force` guards every later act: "no admission settings are in force for … — nothing may be admitted, ranked or cut off until the Central Admissions Committee's settings for this session are in force" |
| State the general load cut-off | same, panel "General UTME cut-off for loading the JAMB lists" | 0–400 (`ADM_LOAD_CUTOFF`) | `admissions.load_cutoff` | — | none | — | A UTME list cannot load until stated (`ADM_LOAD_CUTOFF_NOT_STATED`); rows under it go to `caps_row_excluded` "read, not loaded" |
| O'Level grading and exam-screened programmes | same, panel "O'Level grading for the screening score" | points per grade, subjects counted, sitting bonuses; "Programmes screened by examination" | `olevel_grading`, `olevel_grade_point`, `screening_exam_programme` | — | none | — | Defaults apply when unstated (A1 6 … C6 1; five subjects; bonus 10 / 6) |

`SUPERSEDED` is allowed by the CHECK on `session_policy.state` but nothing sets it.

### 2.2 CAPS lists: load, reconcile, commit, withdraw

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Parse the file | Academic Office / Registrar on Upload Applicants and Candidates `/admissions/caps` (UTME card or Direct Entry card) | `.xlsx` parsed in the browser (`lib/caps.ts`); unresolved JAMB course names must be mapped in the **AliasMapper** (`PUT /programmes/{code}/jamb-alias`); blocking findings: "n rows cannot be accepted, so none of the file is written" | none until loaded | — | none | CAPS parse CSV | "Not a programme the University runs: C…" (`ADM_UNKNOWN_PROGRAMME`) |
| Load | same; the *acting* office must be academic or registrar (`CapsIntakeService.requireUploadingOffice`, `ADM_LIST_OFFICE`) | UTME: settings IN_FORCE and load cut-off stated; DE: no cut-off, no programme-code resolution; `ck_row_code ^C\d{5}$`; aggregate 1–400 | `admissions.caps_batch` (`list_kind` UTME / DIRECT_ENTRY, `source` CAPS_DOWNLOAD), `caps_row` in chunks, `caps_row_excluded` (BELOW_CUTOFF) | batch `held` | none | — | `ADM_BATCH_COMMITTED`, `ADM_BATCH_WITHDRAWN` on a re-load of a closed batch |
| Reconcile | anyone reading the page ("Does the list reconcile?") | `reconcile` findings: "On the CAPS list, no candidate record" (non-blocking); "Admitted here, not on the CAPS list"; "Matched, programme differs from CAPS"; "JAMB course code the University does not run"; "Direct Entry candidate entered at the wrong level" | none | — | none | — | — |
| Commit | Academic Office / Registrar (`commit_batch`) | refused while any blocking finding is non-zero: "the admission list does not reconcile: …" | `committed_at`, `committed_pending` (the count of unregistered rows); `attach_pending` re-matches held passports, dates of birth and O'Level | held → committed | none | — | Lookup on `/apply` answers `found` only for a live row |
| Withdraw | same, modal "Why the list is withdrawn" | reason required ("a list is withdrawn for a reason, and none was given"); no student admitted from it ("n student(s) admitted from this list already hold an admission number") | rows flagged `withdrawn` (hidden by the view `caps_row_live`); candidates → WITHDRAWN | committed / held → withdrawn | none | — | — |
| Reset the JAMB list | same, double browser confirm | "the JAMB list is reset by a person" | deletes the session's gateway events, documents, fee references, clearance, applications, accounts, screening batches, `jamb_admission`, O'Level, photos, attachments, candidates, caps rows / excluded / batches; detaches students (`candidate_id = NULL`) | — | none | — | Destructive; guarded only by browser confirms |

### 2.3 Applicant registration, fee and form

Covered stage by stage in §1.1 (rows "Applicant registers", "Application fee", "Form submitted"). Particulars worth repeating for the office:

- Controller shape checks on registration: `APP_NUMBER_SHAPE` "A JAMB registration number is twelve digits and then two or three letters."; `APP_PHONE` "A Nigerian mobile number is eleven digits beginning with a zero."; `APP_PASSWORD_SHORT` "Eight characters at the very least."; the email must not already belong to an account.
- Fees per session are stated by the Bursary on Fee Setup and Schedule `/finance/fees` → "Applicant · Post-UTME fees" (`admissions.applicant_fee`: application fee, portal charge, acceptance fee, checking fee; defaults 2,000 / 300 / 25,000 / 0 when unstated).
- Migration of old-portal applicants (`/admissions/migrate`, `import_applicant`) creates candidate + account (password sentinel `SET_ON_FIRST_LOGIN`, so the JAMB number is the first password) + an application already fee-confirmed and submitted, on channel "Old-portal migration".
- Passports, dates of birth and O'Level results are uploaded by the office on Upload Passport, DOB & O'Level `/admissions/candidate-data`; the applicant never types O'Level results and has no document-upload control (the API `POST /me/documents` exists without a screen — **PARTIALLY IMPLEMENTED**).

### 2.4 Screening seating: legacy batches and the V260 CBT desk

Two seating paths coexist. Both set `application.screening_batch_id` and `seat`; only the V260 path keeps a seating history and publishes.

**Legacy batches** (Report on Admissions → ApplicantsDesk "Screening batches"):

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| New batch | Academic Office / Registrar / Deputy Registrar | Batch label, Date, Starts, Ends, Venue, Capacity | `admissions.screening_batch` (state default PUBLISHED) | — | none | — | — |
| Seat the submitted | same (`assign_screening`) | submitted applications, in application-number order; seat `LABEL-NNN` | `application.screening_batch_id`, `seat` | stage 3 | Email + SMS "Your screening slip is ready" | Hall list `/admissions/screening/{batch}` (print); slip PDF | — |

**V260 CBT desk** (Post-UTME CBT Schedule `/admissions/putme`; OFFICE = academic, registrar, dregistrar, super):

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Set up the examination | OFFICE on Examination setup `/admissions/putme/setup` | Name required; report-before 0–240 min; sitting 10–600 min; strategy PROGRAMME / DEPARTMENT / FACULTY / ALPHABETICAL / APPLICATION_NO / BALANCED; centres `^[A-Z0-9-]{2,12}$`; room capacity 1–2000, workstations ≤ capacity; slot "Slot X ends before it starts." (`PUTME_SLOT`) | `putme_exam`, `putme_day`, `putme_slot`, `putme_exam_centre`, `cbt_centre`, `cbt_room`, `cbt_workstation` | exam DRAFT → CONFIGURING → OPEN_FOR_SCHEDULING (manual state endpoint) | none | — | "No programme is named as screened by examination this session, so nobody is eligible" until `screening_exam_programme` has rows |
| Generate batches | OFFICE, modal with "Note for the record" | `putme_capacity` > 0 else "the examination has no place to seat anyone: name its dates, its slots and its centres with rooms first"; candidates READY_FOR_SCHEDULING / RESCHEDULE_REQUIRED (paid, submitted, exam-screened programme); after SCHEDULED: "the schedule of {exam} is {state}; candidates are moved one by one, or a batch postponed" | `screening_batch` rows `B001…` per place (day × slot × room), seats `001…`, `screening_assignment` ACTIVE, `putme_event` | exam → SCHEDULING_IN_PROGRESS; batches DRAFT | none (candidates are not told and see no slip while DRAFT) | — | Generate again supersedes seatings (SUPERSEDED) while unpublished |
| Validate | automatic on the dashboard (`putme_validate`) | ERRORs CAPACITY, DUPLICATE, ROOM_CLASH, INELIGIBLE, UNPAID, UNSUBMITTED, UNPLACED_BATCH; WARNINGs UNSCHEDULED, REVIEW, NO_WORKSTATION | none | — | none | Validation report on screen | Publish is disabled while an ERROR stands |
| Publish and notify | OFFICE | zero errors and at least one live batch ("the schedule cannot be published: {errors}" / "nothing to publish: generate the batches first") | `published_at`; batches PUBLISHED | exam → SCHEDULED (the state endpoint refuses SCHEDULED: "A schedule is published, not declared.") | Email + SMS "Your Post-UTME examination schedule" to every candidate in a DRAFT batch | Slip PDF now visible; QR → `/verify/putme/{token}` | — |
| Move / unschedule / confirm review | OFFICE on Candidates `/admissions/putme/candidates` | "a move carries its reason"; "that batch is not open for seating"; "ROOM CAPACITY EXCEEDED: batch B is full (n of n)"; "no free seat in batch B"; "unscheduling carries its reason"; a programme change after seating sets `schedule_review` (event PROGRAMME_CHANGED) | `screening_assignment` old → SUPERSEDED / CANCELLED, new ACTIVE; `putme_event` | — | Email + SMS "Your Post-UTME schedule has changed" / "Your Post-UTME seating has been withdrawn" (published batches only) | — | — |
| Postpone / cancel a batch | OFFICE on the Batch page | "a batch is postponed or cancelled"; "say why the batch is postponed" | unseats everyone with the reason | batch → POSTPONED / CANCELLED | Email + SMS "Your Post-UTME batch has been postponed/cancelled" if it was published | Slip prints "THIS BATCH IS POSTPONED/CANCELLED" | Candidates return to RESCHEDULE_REQUIRED |
| Reopen / mark completed | OFFICE | state endpoint with a note | `putme_exam.state` | SCHEDULED → OPEN_FOR_SCHEDULING; → COMPLETED | none | — | ONGOING is displayed but nothing sets it automatically (**PARTIALLY IMPLEMENTED**) |

The columns `keep_programme`, `registration_deadline` and `kind` on `putme_exam` are saved but not read by generation or eligibility (**CONFIGURED BUT UNUSED**).

### 2.5 Check-in and attendance

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Find the candidate | DOOR offices (academic, registrar, dregistrar, records, ict, super) on Check-in desk `/admissions/putme/checkin` | one box takes the slip QR (a scanner types the verify URL), the application number or the JAMB number | none | — | none | — | "Not seated in any batch"; "Seated on {day}, not today"; "Disqualified" |
| Check in | DOOR (`putme_checkin`) | "the candidate is not seated in any batch"; "batch B is draft; check-in is at a published batch"; "already checked in at HH:MM" (treated as possible impersonation); "the candidate is disqualified" | `screening_assignment.checked_in`, `attendance` | attendance NOT_CHECKED_IN → CHECKED_IN | none | Attendance sheet per batch (Excel / print) | — |
| Attendance and examination status | DOOR on the Batch page or the desk (`PUTME_ATTENDANCE`, `PUTME_EXAM_STATUS`) | Remarks "Required for a disqualification" | `attendance` → PRESENT / ABSENT / DISQUALIFIED; `exam_status` NOT_STARTED → IN_PROGRESS → COMPLETED / ABSENT / DISQUALIFIED | as stated | none | — | — |
| Public verification | anyone, `/verify/putme/{token}` | token on the slip; nothing for DRAFT batches | logged nowhere (no rate limit) | — | none | — | "Not verified — No published examination slip matches this code" |

### 2.6 Scores, merit list, decisions and releases

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Enter one score | Academic Office / Registrar / Deputy Registrar, application modal "CBT score, of 100" | `APP_SCORE_LOCKED` "The score is entered for a seated candidate, and not after it is released." | `application.screening_score` | — | none | — | — |
| Upload scores | `SCORE_UPLOADERS` (academic, registrar, dregistrar, ict, admin, super) on Upload PUTME Score `/admissions/scores` | CSV `key, score` (key = JAMB or application number); rows out of 0–100, "No applicant match", "Score already released" are reported | scores per application | — | none | Awaiting-scores download; score template | "Score remaining as zero" for stragglers of exam-screened programmes |
| Compute non-sitters | academic / super / ict / admin / registrar / dregistrar on Compute PUTME Score `/admissions/computed-screening` | non-index programmes and Direct Entry: O'Level points scaled to 100 by `screening_component` (source OLEVEL) | screening score from `olevel_score` | — | none | Excel (serial `CPU`) / print | — |
| Release scores | Academic Office / Registrar / Deputy Registrar (`release_scores`) | every application seated or scored | `score_released_at`; `admissions.screening_result` visible to the applicant | stage 4 | Email + SMS "Your screening result is released" | — | "Clear uploaded Post-UTME scores" only before release |
| Merit list | Academic Office / Registrar on Merit List `/admissions/merit` ("Record the merit list") or "Record all programmes" on `/admissions` | `merit_list` (V189): submitted UTME applications on a live CAPS row (exam-screened programmes need a released score); aggregate = UTME/400×100×w_utme + screening×w_putme; eligible = programme open, aggregate present, UTME ≥ programme/faculty cut-off, compulsory credits (English, Mathematics), UTME combination; ranked and filled into the UTME share of the quota in basis order NM → SM → ELG → LOCALITY | `decide_application` per application: OFFERED with basis / WAITING / NOT_OFFERED, skipping released ones | decision held (not released) | none | JAMB admission template workbook (five sheets) | "Not scored" / "Below cut-off" / "No Eng/Maths credit" shown per row |
| Board decision, one at a time | Academic Office / Registrar / Deputy Registrar, application modal "The Board's decision" | `APP_DECISION` (OFFERED / WAITING / NOT_OFFERED); `APP_DECISION_BASIS`; "the decision was released on … and stands"; "the screening score has not been released"; "an offer is made on a basis"; "a compulsory O'Level credit is missing: …" | `decision`, `basis`, `decision_note` | decision held | none | — | — |
| Release decisions | same (`release_decisions`) | confirm when the acceptance fee is unset for the session | `decision_released_at`; candidates with OFFERED PROPOSED → ADMITTED | stage 5 | Email + SMS per outcome | Offer letter after acceptance | — |
| Reconsideration | Academic Office on Report on Admissions → Reconsiderations | `programme_suggestions`: five credits including English and Mathematics, programme open, cut-off cleared, quota not filled; `ADM_SUGGEST_NOT_ELIGIBLE` "That programme is not one this candidate qualifies for." | `suggestion_sent` | — | Email "Your {session} admission — a suggested programme" | — | The notify-all endpoint has no button |

### 2.7 Undertaking, acceptance and decline

See §1.1 "Acceptance". The acceptance reference is `MOAUM-ACC-…` for acceptance fee + checking fee ("there is no offer to accept" before a released OFFERED decision; "the acceptance fee is already confirmed"). `settle_acceptance` runs from `confirm_fee` and from `sign_undertaking`, whichever completes the pair. Decline is a browser confirm "Decline this offer? A declined offer is not reinstated." → `decline_offer` (refused after acceptance: "the offer was accepted on …; withdrawing is a change of status on the register"). Nothing is emailed on decline.

### 2.8 Clearance items and intake to the register

The six clearance items (`OLEVEL_ORIGINAL`, `BIRTH_CERT`, `LGA_ID`, `JAMB_LETTER`, `MEDICAL`, `PHOTOGRAPHS`) are recorded by the Registry through `PUT …/clearance/{item}` (state `NOT_PRESENTED` / `VERIFIED` / `QUERY`, a QUERY must carry a note — `ck_cl_query_note`). The applicant reads the checklist on Document Clearance `/applicant/clearance` ("n of 6 verified"; "Nothing is paid at clearance, to anyone."). **No officer screen calls the endpoint** (**PARTIALLY IMPLEMENTED**), so stage 7 is reachable from the API only.

Intake (`people.intake(session)`) is run from Report on Admissions `/admissions` by the "Bring N candidates onto the register" button (Academic Office, Registrar, Deputy Registrar). It inserts a `people.student` for every candidate ADMITTED or ACCEPTED not yet on the register, issues the admission number `MOAUM/ADM/YY/NNNNNN` from `platform.next_number('ADMISSION',…)`, copies entry mode and level, and resolves the programme by name or code ("the programme "%" for candidate % is not one the University runs…" stops the run). The applicant's Matriculation page then shows the admission number under "What you carry now".

### 2.9 The Direct Entry variant

| Difference | How the code treats it |
|---|---|
| Registration | Same public page; `entry_level` 200; the form shows "Direct Entry" in place of a UTME score |
| CAPS load | The Direct Entry card loads without the load cut-off and without programme-code resolution |
| Merit list | Excluded ("UTME only for now", V182) and skipped by "Record the merit list" |
| Screening score | Appears on Compute PUTME Score (O'Level computed); a DE candidate may also sit the CBT if the programme is exam-screened |
| Qualification capture | Direct Entry Screening `/admissions/de-screening`: basis A_LEVEL / IJMB / JUPEB / NCE / ND / HND, year, awarding body, subjects with grades (`de_award`, `de_award_subject`); status NO_RULE / UNVERIFIED / MET / SHORT from `de_screening`; gate `de_meets_combination` (no rule or no subjects → pass) |
| Offer | Entered manually on the desk ("The Board's decision") or arrives through the JAMB status list |
| Reconcile | "Direct Entry candidate entered at the wrong level" blocks a commit |

### 2.10 The JAMB admission-status upload path

On Report on Admissions → "Admission status from JAMB", the Academic Office or Registrar uploads JAMB's status file (`POST …/jamb-admissions` in chunks; "a JAMB admission list is uploaded by a person"; "the list is rows: registration number, name, course, admission status"). `load_jamb_admissions` offers and **releases at once** every "Accept…" row that has an application, with the basis mapped from JAMB's category (`jamb_basis`: MERIT → NM, CATCH → LOCALITY, ELG / "LESS DEVELOP…" → ELG, STATE → SM); candidates move to ADMITTED. Unmatched rows are kept with the reason "Registration number not on the register — screened here?"; accepted rows without an application carry "…the applicant has not registered here". **No notice is sent to the applicant on this path.** The tiles show loaded / matched / accepted / offered / unmatched.

### 2.11 What is not implemented

| Item | Status |
|---|---|
| Offer lapse (`LAPSED`) and waiting-list promotion (WAITING → OFFERED) | NOT IMPLEMENTED — the CHECK allows LAPSED; no function sets it; screen text promises promotion |
| Officer screen for the six clearance items | PARTIALLY IMPLEMENTED — endpoint only |
| Applicant document review (ACCEPTED / REJECTED) | PARTIALLY IMPLEMENTED — endpoint only; no upload control on the applicant side either |
| Office confirmation of an applicant fee reference | PARTIALLY IMPLEMENTED — endpoint exists; the desk note says "there is no confirmation step here"; the gateway path is the live one |
| Notice to the applicant on a JAMB-upload offer, on decline, on submission | NOT IMPLEMENTED |
| `SUPERSEDED` settings state; `CAPS_API` source | CONFIGURED BUT UNUSED |
| Rate limit on `/apply` lookup and on `/verify/putme/{token}` | NOT IMPLEMENTED |
| `ONGOING` exam state moved automatically; `keep_programme`, `registration_deadline` honoured | PARTIALLY IMPLEMENTED / CONFIGURED BUT UNUSED |

> **Screenshot Required:** Report on Admissions — `/admissions` — the red note "n admitted candidates are not yet on the register" with the button "Bring n candidates onto the register".

### 2.12 Programme eligibility and course suggestions (V266)

Rule-based, explainable, configurable and audited; it neither admits nor changes a programme by itself.

| Step | Actor | Screen / function | What happens |
|---|---|---|---|
| 1 | Secretariat | Admission Settings → programme rule modal, Subject equivalencies | States per programme the required O'Level subjects and grade, the UTME (or DE) subject set, the cut-off, the credits and sittings, any additional screening; states equivalencies. Each change moves `session_policy.rules_version` (`admissions.rules_touched`). |
| 2 | Applicant / system | `POST /applicant/me/submit` → `admissions.evaluate_application(app, 'SUBMISSION')` | On submission the applied programme is evaluated (`evaluate_programme`: active · stated · open · places · sittings · compulsory credits · required subjects · credit count · UTME combination with equivalences · score against greatest(programme or faculty cut-off, load cut-off) · DE subjects · screening). Verdict ELIGIBLE / ELIGIBLE_SCREENING / NOT_ELIGIBLE / UNVERIFIED with `checks` (requirement · candidate · status) and `reasons`. |
| 3 | System | same | Only when NOT_ELIGIBLE: every other active, stated, open programme is evaluated and stored as an ALTERNATIVE, ordered eligible → screening → unverified → not, same faculty first. `eligibility_run` (one current per application; earlier runs superseded) and `eligibility_result` rows; EVALUATED and RECOMMENDATION_GENERATED on `eligibility_event`; the applicant told once per change of verdict. |
| 4 | Applicant | Overview / Admission Status → Programme eligibility | Reads the verdict and reasons (`GET /applicant/me/eligibility` → `eligibility_current`, which re-evaluates when none stands, the record changed or the rules version moved), the eligible alternatives only, View eligibility details, Recalculate. |
| 5 | Applicant | Request Change | `POST /applicant/me/eligibility/change` — refused (`ELIG_NOT_SUGGESTED`) unless the programme is an eligible alternative on the current run; `request_programme_change` refuses a second open request, the applied programme, an inactive programme or an application whose decision is released; PROGRAMME_CHANGE_REQUESTED on the trail. |
| 6 | Admissions Office | Programme Eligibility register | Searches and filters on the server; View Matching Details (RECOMMENDATION_VIEWED logged); Recalculate one (OFFICER) / Evaluate the unevaluated (SYSTEM) / Recalculate all (OFFICER); may itself request a change for an applicant. |
| 7 | Admissions Office | Programme change requests → Approve / Reject | `decide_programme_change`: APPROVE re-reads eligibility for the target at that moment, sets `candidate.programme`, re-evaluates under PROGRAMME_CHANGE, notifies; REJECT needs a reason and notifies. |
| 8 | System | triggers `eligibility_touched` on `olevel_sitting`, `olevel_grade`, `caps_row`, `de_award(_subject)`, `candidate.programme / entry_mode` | Marks the current run stale; the next opening re-evaluates (DATA_CHANGE); a rules-version change re-evaluates as POLICY_CHANGE. |
| 9 | Admissions Office | Reports | Register, Candidates not eligible, Alternative programme suggestions, Statistics — Excel and PDF, S/N first, names A–Z. |

Tested end to end by `AdmissionEligibilityIT` (seven methods covering the ten acceptance cases: eligible; not eligible with alternatives; explained; no alternatives and closed / unstated programmes never suggested; one-versus-two sittings with automatic re-evaluation on the rule change; equivalence honoured only when stated and additional screening; the register's search, filters and statistics; the applicant's own view, the refused request, the approved change; the stale record re-read; the doors).

### 2.13 The admission lifecycle after the offer: acceptance, online screening, change of programme, fees, registration, matriculation (V269)

| Step | Actor | Screen / function | What happens |
|---|---|---|---|
| 1 | Office | JAMB list upload (V081) → offer → release | As before: the candidate matched on RG_NUM, the offer released, the applicant told. `admission_status` = ADMITTED. |
| 2 | Applicant | Admission Progress / Accept Your Offer | The congratulations and the details; the undertaking and the acceptance fee (`fee_reference` ACCEPTANCE, confirmed by the Bursary or the gateway; a second one refused). `settle_acceptance` sets `accepted_at`; the letter opens. `acceptance_entitlement` = paid, for the admission. |
| 3 | Applicant | Online Screening | `screening_open` on acceptance (where `screening_policy` requires it); `screening_save` (answers on `ref.biodata_field`, institutions, O'Level rows, membership), documents on `application_document`; `screening_submit` (declaration, `screening_missing` empty) → SUBMITTED, notices. |
| 4 | Screening officer | Screening Review | `screening_start_review`; `screening_decide`: SUCCESSFUL (application `cleared_at`, answers → `people.biodata`, notice), UNSUCCESSFUL (reason; `evaluate_application` lists alternatives; notice), RETURNED (note; the applicant resubmits as version n+1). |
| 5a | Applicant / student | student portal | PATH A: `screening_ok` → `finance.new_reference` opens, course registration opens (gates), `matric_candidates` no longer pending on the screening; `admission_status` SCHOOL_FEES_PENDING → COURSE_REGISTRATION_PENDING → MATRICULATION_PENDING. |
| 5b | Applicant | Online Screening → Programmes you may be eligible for → Request Change | PATH B: `request_programme_change` after the Board's decision (only after an unsuccessful screening, once); Programme Eligibility queue. |
| 6b | Admissions Office | Programme Eligibility → Approve | `decide_programme_change`: eligibility re-read; `candidate.programme` and `people.student.programme_code` (unmatriculated) moved; application cleared; the applicant told the acceptance fee is not charged again. `screening_ok` true; the gates open. |
| 7 | Academic Office | Matriculation Management (V267) | Generate → review → ready → Confirm & Issue: number, ACTIVE, the sign-in username, histories, notice; **Broadcast** to the batch. `admission_status` MATRICULATED. |

Tested end to end by `AdmissionLifecycleIT` (both paths, the gates, the entitlement, the readiness, the pipeline, the doors) and the broadcast by `MatriculationManagementIT`.

---
## 3. Postgraduate admission, research and external examiners

The School of Postgraduate Studies (SPGS) runs its own admission (no JAMB number), its own calendar of sessions and semesters (`admissions.pg_academic_session`, `pg_semester`), its own course catalogue and results, and a research record per candidate. The offices are Postgraduate School (`pgschool`), PG Secretary (`pgsecretary`), Head of Department, Dean, Academic Office, Registrar and Bursar for fees.

### 3.1 Postgraduate admission

```text
Navigation
 Applicant:   /pg/apply (public) → /pg/portal (signed in) → /pg/summary/pdf · /pg/offer/pdf
 Referee:     /pg/referee/{token} (public)
 Desks:       pgschool / pgsecretary / hod / dean / academic — Admissions → PG Admissions  /admissions/postgraduate
 Calendar:    pgschool / pgsecretary — Academic → Calendar  /admissions/postgraduate/calendar
 Fees:        bursar / pgsecretary — Fee Setup and Schedule  /finance/fees (PG card)
```

```text
pg_application
 SUBMITTED ──application fee──▶ (portal steps unlock)
 SUBMITTED ──pg_dept_decide──▶ DEPT_RECOMMENDED | DEPT_DECLINED
 DEPT_RECOMMENDED ──pg_faculty_decide──▶ FAC_RECOMMENDED | FAC_DECLINED
 FAC_RECOMMENDED ──pg_spgs_decide──▶ OFFERED | NOT_OFFERED   (shown as DECISION_LOCKED until the checking fee)
 OFFERED ──acceptance fee (pg_confirm_fee) or pg_accept──▶ ACCEPTED
 ACCEPTED ──pg_admit──▶ ADMITTED  → people.student (POSTGRADUATE, status ADMITTED) + iam.student_account
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Apply | Applicant, public `/pg/apply` (three-step wizard) | programme `category = 'POST GRADUATE'` ("that programme is not a postgraduate programme"); surname, other names, email, password ≥ 6 chars; `PG_APP_EXISTS` "An application already exists for this email." | `admissions.pg_applicant`, `pg_application` (`PG/YY/NNNNNN`), `pg_referee` rows, `pg_prior_degree`, APPLICATION fee reference `MOAUM-PGAPP-NNNNNN` (24 h); trail CREATED, SUBMITTED | SUBMITTED | Email "Your MOAUM postgraduate application has been received" | — | A declined applicant cannot apply again on the same email |
| Application fee | Applicant pays on the gateway (`PayByCard`) or the PG Secretary / Bursar confirms on the Secretary's home (`POST /pg/applications/{id}/confirm-fee`, channel "bank") | reference must belong to the application (`PG_FEE_REF_MISMATCH`); `PG_FEE_PAID` "That fee is already confirmed for this application." | `fee_confirmed_at`; trail APPLICATION_FEE_CONFIRMED | — | Email "Your application fee is confirmed" | — | Steps show "Pay the application fee first" until then (`PG_FEE_UNPAID` "Pay the application fee before uploading your documents.") |
| Complete the record | Applicant on `/pg/portal` | first degree, other qualifications, referees (≤ 5), documents (PDF only, ≤ 8 MB, one per kind except HIGHER_DEGREE), passport (JPEG/PNG ≤ 4 MB) | `pg_prior_degree`, `pg_referee` (token per row), `pg_document` | — | Referee: Email "Reference request — {applicant} (MOAUM Postgraduate)" | Application summary PDF `/pg/summary/pdf` (also emailed on request) | Re-saving referees deletes unsent rows and mints new tokens (old links 404) |
| Reference | Referee, public `/pg/referee/{token}` | relationship, duration, attestation, verdict RECOMMEND / RECOMMEND_WITH_RESERVATION / DO_NOT_RECOMMEND; `PG_REF_DONE` "This reference has already been submitted." | `pg_referee.submitted_at`, attestation | — | Email to the applicant "A reference has been received" | — | Invalid token → 404 "This reference link is not valid." |
| Department decision | HOD (own department by `OfficeScope.actingHod`), Academic Office, super — buttons "Department: recommend / Decline" | "the department decides a submitted application, not one at %" | `dept_decided_*`, `dept_note`; trail | SUBMITTED → DEPT_RECOMMENDED / DEPT_DECLINED | none | — | DEPT_DECLINED is terminal; no reopen or appeal endpoint |
| Faculty decision | Dean (own faculty), Academic Office, super | "the faculty decides after the department recommends, not on an application at %" | `fac_*`; trail | DEPT_RECOMMENDED → FAC_RECOMMENDED / FAC_DECLINED | none | — | terminal on decline |
| School decision | pgschool, pgsecretary, super — "Offer a place / Refuse" | "the School decides after the faculty, not on an application at %" | `spgs_*`; trail | FAC_RECOMMENDED → OFFERED / NOT_OFFERED (masked as DECISION_LOCKED to the applicant) | Email "A decision on your MOAUM postgraduate application" (pay the checking fee) | — | NOT_OFFERED terminal |
| Checking fee | Applicant (reference CHECKING prepared only after `spgs_decided_at`: `PG_FEE_NOT_YET` "The checking fee is paid once the School has decided on the application.") | as above | `checking_confirmed_at`; trail CHECKING_FEE_CONFIRMED | mask lifts; desk notes become readable | Email "Your admission decision is ready to view" | — | — |
| Acceptance | Applicant pays ACCEPTANCE ("The acceptance fee is paid once a place is offered and the decision has been read."), or SPGS "Record acceptance" | "only an offer can be accepted (state is %)" | `acceptance_confirmed_at`, `accepted_at`; trail ACCEPTANCE_FEE_CONFIRMED / ACCEPTED | OFFERED → ACCEPTED | Email "Your offer of admission is accepted" | Confirmation of offer PDF `/pg/offer/pdf` — 409 "Offer letter not available yet" until `acceptanceConfirmedAt` (a desk-recorded acceptance without the fee does not unlock it) | — |
| Admit | pgschool, pgsecretary, registrar, super — "Admit onto the register" | "only an accepted offer is admitted (state is %)"; idempotent | `people.student` (admission number `MOAUM/ADM/YY/NNNNNN`, `entry_mode = POSTGRADUATE`, level 700 PGD / 800 Master's / 900 MPhil-PhD, school S002, status ADMITTED), `people.student_contact`, `iam.student_account` with the applicant's hash | ACCEPTED → ADMITTED | Email "You are admitted — your student record is open" | — | — |

Fees: `admissions.pg_fee` per session (defaults ₦20,000 application / ₦50,000 acceptance / ₦3,000 checking when unstated), set on `/finance/fees`. The offer PDF's QR encodes `MOAUM PG {applicationNo}` and **has no verifier** (no `/verify` route for it). Nothing notifies the HOD, Dean or School when an application arrives or advances.

### 3.2 Coursework registration and results

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Catalogue | hod, academic, pgschool, pgsecretary, super on Courses `/admissions/postgraduate/courses` (add or upload) | units 0–12; kind CORE / ELECTIVE / DEFICIENCY / RESEARCH; semester 1–2; programme must be postgraduate | `admissions.pg_course` (unique programme + code) | — | none | Course template xlsx | Rows whose programme does not match are counted, not written |
| Register | Postgraduate student on Course Registration & Results `/student/pg-courses` | active courses of the student's programme; `trg_deferment_gate_pg_registration`: "REGISTRATION UNAVAILABLE: your deferment for % is approved; you cannot register for the deferred period"; scored entries are kept | `pg_registration` (mode FULL_TIME / PART_TIME), `pg_registration_entry` | upsert at SUBMITTED | none | — | The PG calendar's registration windows are **not enforced** |
| Endorse | DESK on Course Results `/admissions/postgraduate/results` | no precondition in code | `endorsed_by/at` | SUBMITTED → ENDORSED | none | — | Student sees "Your registration is endorsed… Write to the department to change it." |
| Score | DESK, per course CA + Exam | `ck_pg_score_total` 0–100 (no check that the registration is endorsed) | `pg_score` (total, grade A ≥ 70 / B / C / F < 50; points 5/4/3/0; DEFICIENCY earns none) | — | none | — | — |
| Standing | computed | `pg_gpa`, `pg_cgpa`; PROBATION below 2.50 once any score exists, NEW before | none | — | none | — | — |
| Status change | pgschool, pgsecretary, super on PG Students `/admissions/postgraduate/students` (Defer / Withdraw / Reinstate / Readmit) | `PG_STATUS` DEFERRED / WITHDRAWN / ACTIVE; instrument prompted | `people.change_status` | as chosen | none | — | — |

### 3.3 The research lifecycle (sixteen stages)

The record (`admissions.pg_research`, one per student) is created on the student's first read of Research & Thesis `/student/research` (`pg_research_ensure`). The School acts on Research Desk `/admissions/postgraduate/research`; the Secretary clears on Thesis Clearance `/admissions/postgraduate/clearance`; the Board recommends and records the award on School Board `/admissions/postgraduate/board`.

```text
REGISTERED → SUPERVISED → PROPOSAL_SUBMITTED → PROPOSAL_APPROVED → SEMINAR_HELD → TITLE_REGISTERED
 → PANEL_CONSTITUTED → DRAFT_SUBMITTED → VIVA_HELD → (CORRECTIONS ⇄ VIVA_HELD) → FINAL_SUBMITTED
 → CLEARED → AWARD_RECOMMENDED → AWARDED          any stage → WITHDRAWN (terminal)
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Supervisor assigned | School (`POST /pg/research/{id}/supervisor`: name, role FIRST / SECOND / CO, external flag) | `PG_SUP_ROLE` | `pg_research_supervisor` (free-text name; `person_id` never set) | REGISTERED → SUPERVISED on the first supervisor | Email "Your research: …" ("A supervisor has been assigned to you…") | — | No end/replace action (`ended_at` never set) |
| Proposal | Student saves the topic and "Submit proposal" (`/me/proposal`), or School SUBMIT_PROPOSAL | topic required | `topic`, milestone | → PROPOSAL_SUBMITTED | Email | Student uploads PROPOSAL document (PDF/.docx ≤ 25 MB) | — |
| Approve proposal | School APPROVE_PROPOSAL | from PROPOSAL_SUBMITTED | milestone | → PROPOSAL_APPROVED; topic locked (`PG_TOPIC_LOCKED`) | Email | — | Out of order: `PG_STAGE_ORDER` "This record is at 'x'; y follows 'z'." |
| Seminar | School SEMINAR (+ PGSR name) | from PROPOSAL_APPROVED | `pgsr` | → SEMINAR_HELD | Email | Student may upload SEMINAR_PAPER | — |
| Register title | School REGISTER_TITLE (+ originality %) | `PG_PLAGIARISM` "Record the plagiarism-check originality before registering the title." (75–85 % advisory only) | `plagiarism_pct` | → TITLE_REGISTERED | Email | PLAGIARISM_REPORT document kind | — |
| Panel | School PANEL; members via `/panel-member` (Chair / HOD, External examiner, Supervisor, Co-supervisor, Internal examiner, PGSR, PG Coordinator) | `PG_PANEL_ROLE`; "six for a Master's, seven for a PhD (Policy 24.3)" is guidance text only | `pg_research_panel` (free names) | → PANEL_CONSTITUTED | Email | — | No remove-member action |
| Draft | School DRAFT, or the student's DRAFT document | `PG_DRAFT_EARLY` "The draft is submitted for examination once your title is registered." | `pg_research_document` v n | → DRAFT_SUBMITTED | Email | Draft for examination | Desk **Accept / Return** ("What must the candidate correct?") keeps the version, logs the review |
| Viva | School VIVA (+ score %, outcome PASS_CLEAN / PASS_MINOR / PASS_MAJOR / SECOND_ORAL / FAIL) | `PG_VIVA` "Record the viva score and outcome." | `viva_*`, grade A/B/C/F at 70/60/50 | → VIVA_HELD | Email | — | A second oral re-enters from CORRECTIONS |
| Corrections | School CORRECTIONS (+ due date) | from VIVA_HELD | `corrections_due` | → CORRECTIONS | Email | Student submits CORRECTED copies (`PG_CORRECTED_EARLY` otherwise) | — |
| Final submission | School FINAL, or the student's FINAL document | `PG_FINAL_EARLY` "The final copy is submitted after the oral examination." | document | → FINAL_SUBMITTED | Email | Final copy | — |
| Clear for binding | PG Secretary / School on Thesis Clearance | from FINAL_SUBMITTED | note "Cleared by the Secretary before binding" | → CLEARED | Email | — | — |
| Recommend | School Board page | from CLEARED | milestone | → AWARD_RECOMMENDED | Email | — | — |
| Senate award | School Board page with the "Senate minute" typed (`AWARD`) | `pg_award`: "an award is recorded on a Senate minute, and none was cited"; "an award is recorded for a matriculated student; % has no matriculation number" | `records.graduand` APPROVED on the minute; `people.change_status(GRADUATED)`; event "Award of {award} approved by Senate under minute …" | → AWARDED; student GRADUATED | Email "Senate has approved your award. Congratulations…" | — | The Research Desk's own "Record Senate award" button sends no minute and always fails with `PG_AWARD_MINUTE` |
| Withdraw | School, browser confirm | any stage | — | → WITHDRAWN | Email | — | terminal; no reinstatement |

Documents: `pg_research_document.status` SUBMITTED → ACCEPTED / RETURNED; every submission is a new version; type sniffed (`%PDF-` or `PK`), ≤ 25 MB. No notice goes to supervisors or panel members at any stage.

### 3.4 External examiners

The `extexam` schema (V254) records scholars from other institutions, invites them by an emailed link, appoints them, registers final-year projects (undergraduate, or a postgraduate's research record), releases documents, assigns examiners on an assessment form and collects the scored assessment. The desk offices are `DESK` = academic, dregistrar, registrar, exams, hod, dean, pgschool, pgsecretary, admin, super; forms (rubrics) are edited by `FORM` = academic, dregistrar, pgschool, admin, super; the examiner acts as `extexaminer`.

```text
Navigation (Academic group of hod, dean, exams, academic, dregistrar, registrar, admin, pgschool, pgsecretary, super)
 → External Examiners        /examiners
 → Examiner Appointments     /examiners/appointments
 → Project Assignments       /examiners/projects
 → Assessments               /examiners/assignments
 → Examiner Reports          /examiners/reports
 Examiner: Dashboard /examiner · My Projects /examiner/projects · My Profile /examiner/profile · activation /login/activate?token=
```

```text
examiner: INVITED → PENDING_ACTIVATION → ACTIVE ⇄ SUSPENDED | INACTIVE
appointment: ACTIVE → ENDED
assignment: ASSIGNED → IN_REVIEW → SUBMITTED → LOCKED ; SUBMITTED|LOCKED → REOPENED → SUBMITTED ; live → REASSIGNED | WITHDRAWN
assessment: DRAFT → SUBMITTED → LOCKED ; → REOPENED (version + 1)
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Record the examiner | DESK, "New External Examiner" on `/examiners` | `EXAMINER_EXISTS` "An examiner with that email is on the register already."; institution required; experience 0–70 | `extexam.examiner`; event EXAMINER_CREATED | INVITED (or PENDING_ACTIVATION when "Send the invitation email now" is ticked) | Email "External Examiner Appointment — {University}" with the link | — | — |
| Invite / resend | DESK on the record | `EXAMINER_NOT_INVITABLE` "A suspended or inactive examiner is not invited."; the token (32 bytes, SHA-256 stored) works once and for fourteen days | `extexam.invitation`; event EXAMINER_INVITED / INVITATION_RESENT | → PENDING_ACTIVATION | Email as above | — | A newer invitation supersedes the older link |
| Activate | Examiner, public `/login/activate?token=` | hash matches, unused, unexpired, not SUSPENDED/INACTIVE; password ≥ 10 chars not containing the email (`AUTH_WEAK_PASSWORD`); `EXAMINER_USERNAME_TAKEN` | `iam.credential` (username = email), `iam.office_assignment` office `extexaminer`; `activated_at`; event ACCOUNT_ACTIVATED | → ACTIVE | Email to the inviter and every `academic` holder "External examiner account activated — {name}" | — | `EXAMINER_INVITE_TOKEN` "This invitation link has expired or was already used." |
| Appointment | DESK, "Record an Appointment" (session, semester, period, faculty, department, programme, dates, letter or minute) | `EXAMINER_REACH` outside the desk's department; `ends_on ≥ starts_on` | `extexam.appointment`; event APPOINTED | ACTIVE; "End" → ENDED (clips `ends_on` to today) | Email "External Examiner Appointment — …" | — | SUSPENDED appointment status is never set |
| Register the project | DESK, "Register a Project" on `/examiners/projects` | candidate = finalist at or above `finance.final_level` or a postgraduate, ACTIVE / PROBATION, within reach; one project per (student, session) | `extexam.project` (kind POSTGRADUATE links `pg_research_id`) | — | none | — | — |
| Release documents | DESK on the project page (Kind: proposal, final report, source code, presentation, supporting; PDF/DOCX/PPTX/ZIP ≤ 25 MB) | "Only what is released here reaches an examiner" | `project_document.released`; events DOCUMENT_RELEASED / WITHDRAWN | — | none | — | Withheld files never reach the examiner |
| Assign | DESK, "Assign" (examiner, assessment form, review deadline, examination date) | `EXAMINER_NOT_ACTIVE` "A project is assigned to an examiner whose account is active."; `ASSIGNMENT_DEADLINE` "The review deadline is today or later."; `ASSIGNMENT_RUBRIC` "No active assessment form exists for this kind of project."; `ASSIGNMENT_EXISTS` "This project is with that examiner already." | `extexam.assignment` (appointment auto-matched by session + department) | ASSIGNED | Email to the examiner "New Project Assigned for Review — …" | — | — |
| Review | Examiner on `/examiner/projects/{id}` | first open records `first_viewed_at` (PROJECT_VIEWED); scores per criterion ≤ maximum ("% is marked out of %"); Save Draft | `extexam.assessment` DRAFT, `assessment_score`; `compute` sets total, percentage and grade (`policy.grade_of`, the University's undergraduate scheme, for both UG and PG forms) | ASSIGNED → IN_REVIEW | Reminder ≤ 3 days before the deadline "Reminder: Project Review Deadline — …"; overdue "Project Review Overdue — …" to examiner and desk (daily 07:15 Lagos) | — | — |
| Submit | Examiner, "Submit Assessment" | "every criterion is scored before submission; still unscored: …"; "a final recommendation is given before submission" (PASS / PASS_WITH_CORRECTIONS / REASSESSMENT / FAIL); "the general comments say something about the work" (≥ 20 chars) | `submitted_at`, total, recommendation | → SUBMITTED | Desk "External Examiner Assessment Submitted — {number}"; examiner "Assessment Received — …" | — | "the assessment is submitted already"; "this assignment has ended" |
| Lock | DESK, "Approve and Lock" | "only a submitted assessment is locked; this one is …" | event ASSESSMENT_LOCKED | → LOCKED | Email "Assessment Approved and Locked — …" | — | — |
| Reopen | DESK, reason ≥ 5 chars | "only a submitted or locked assessment is reopened"; "reopening an assessment records the reason" | version + 1; `submitted_at`, `locked` cleared | → REOPENED (then SUBMITTED again on resubmission) | Email "Assessment Reopened for Revision — …" | — | — |
| Extend / reassign / withdraw | DESK on `/examiners/assignments` | `ASSIGNMENT_LOCKED` "A locked assessment is not reassigned." / "…not withdrawn."; `ASSIGNMENT_REASON` | deadline (resets `reminded_at`/`overdue_told_at`); old row REASSIGNED with `replaced_by` + new ASSIGNED; or WITHDRAWN | as stated | "Review Deadline Changed — …"; "Project Assignment Withdrawn — …" (old examiner); "New Project Assigned…" (new) | — | — |
| Suspend / deactivate / reactivate | DESK on the record | `EXAMINER_STATUS_REASON` "Suspending or deactivating an examiner records the reason."; `EXAMINER_NOT_ACTIVATED` before a first activation | `iam.end_grant` on suspension; re-grant on reactivation; event EXAMINER_STATUS | ACTIVE → SUSPENDED / INACTIVE → ACTIVE | none | — | The examiner is refused at once with `EXAMINER_NOT_ACTIVE` "Your examiner appointment is not active." |

Reports: eight kinds on `/examiners/reports` downloaded as plain CSV (not the branded Excel). `GET /examiners/moderation` (external averages beside the internal course total) has no screen. No PDF (appointment letter, assessment report) is produced. Every act is in `extexam.event`, written once.

### 3.5 What is not implemented

| Item | Status |
|---|---|
| Reopening a declined PG application; appeal | NOT IMPLEMENTED |
| Notices to HOD / Dean / School on PG application arrival or advance; to supervisors or panel on research stages; on endorsement, score or document review | NOT IMPLEMENTED |
| Verifier for the PG offer-letter QR | NOT IMPLEMENTED (QR decorative) |
| End / replace a supervisor; remove a panel member; edit or end a School-roster examiner (`pg_examiner.active`) | PARTIALLY IMPLEMENTED (add only) |
| Research Desk "Record Senate award" (no minute field) | defect — use the School Board page |
| PG calendar registration windows enforced on `pg_register` | NOT IMPLEMENTED (informational) |
| Excel exports from the coursework and research desks | NOT IMPLEMENTED (the admissions desk has one) |
| Extexam assessment feeding `pg_research.viva_*` or the PG desk showing it | PARTIALLY IMPLEMENTED (link stored; no display, no feed) |
| Moderation feed screen; appointment letter / assessment PDF | PARTIALLY IMPLEMENTED / NOT IMPLEMENTED |
| Menu entries for HOD / Academic Office to the PG courses and results desks (API admits them) | NOT IMPLEMENTED |

---

## 4. Matriculation with the V263 number format

Matriculation turns an ADMITTED student into an ACTIVE one by issuing the permanent matriculation number. Since V263 the number is built from a configured rule — `MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}` — from named series whose counters only move forward, and every issue is written once to `people.matric_history`.

```text
Navigation
 academic (badge) / registrar / dregistrar — Students → Matriculation            /matriculation?session=
 facultyofficer                            — Registered Students                  /matriculation
 academic / registrar / dregistrar         — Matriculation Number Format          /matriculation/config
 Faculty list                                                                     /matriculation/faculty/{code}?session=
```

```text
people.student ADMITTED + registration APPROVED (entry session)
 → faculty_list_rows(session, faculty)  (generated, never typed)
 → Faculty Officer: query names (reason + who clears) | confirm     faculty_list DRAFT → CONFIRMED
 → every faculty with rows CONFIRMED
 → RUN  people.matriculate(session)             one transaction, MAT/YYYY/NNN
      for each un-queried row with finance.position(...).paid_in_full
        → people.next_matric(student, run, reason)
             matric_components → series FOR UPDATE → next free sequence → format_matric → ck_student_matric_shape
             → matric_history (write-once) · matric_series.last_issued moved forward
        → student.matric_no, matriculated_at, matriculation_run, status ACTIVE
        → status_change ADMITTED→ACTIVE, instrument MAT/YYYY/NNN, reason "Matriculated"
        → matric_tell → EMAIL + SMS "Your matriculation number"
 or SINGLE ISSUE  people.matriculate_student(student)  (a straggler who has since paid and registered)
```

### 4.1 The issue workflow

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Faculty list generated | nobody types it: `people.faculty_list_rows(session, faculty)` computes ADMITTED students of the faculty whose registration for the session is APPROVED (or LOCKED), joined to any un-withdrawn query | student status ADMITTED; `registration.course_registration.status IN ('APPROVED','LOCKED')` | none | — | none | Faculty list CSV ("Export the list": Admission number, Name, Department, Units, State) | A student who has not registered is simply absent from the list |
| Query a name | Faculty Officer, Academic Office, Registrar, Deputy Registrar on the faculty list — modal Reason + "Who clears it" (Faculty Officer / Bursary / Head of Department / Academic Office) | reason non-blank | `people.faculty_list_query` (upsert) | row state "Query" | none | — | "Withdraw query" sets `withdrawn_at`; a queried student is held back from the run |
| Confirm the list | same offices, "Confirm N students to the Academic Office" | `MAT_ALREADY_CONFIRMED` "The X list for S is already confirmed." | `people.faculty_list` (UNIQUE session + faculty) with `confirmed_at`, `confirmed_by` | DRAFT → CONFIRMED | none | — | No faculty scope is enforced in code: a Faculty Officer can open and confirm any faculty's list by URL |
| Run | Academic Office, Registrar, Deputy Registrar — "Run matriculation for N students" on `/matriculation` (disabled while a faculty is outstanding or nobody is confirmed) | every faculty with rows must be CONFIRMED: "the run cannot start: {faculty} has not confirmed its list" (HINT "A run with a faculty outstanding would leave its students unmatriculated after their classmates… Confirm every list first."); per row: no query and `finance.position(student, session).paid_in_full`; if nobody qualifies: "nobody on a confirmed list has both paid the fees and registered for {session}; there is nothing to matriculate" | `people.matriculation_run` (ref `MAT/{YYYY}/{NNN}` from `platform.next_number('MATRIC_RUN','UNIVERSITY',session)`), rows ordered by department, surname, other names; per student a `matric_history` row, `matric_series.last_issued`, `people.student.matric_no / matriculated_at / matriculation_run`, a `people.status_change` | ADMITTED → ACTIVE, instrument = the run ref, reason "Matriculated" | Email + SMS "Your matriculation number" (`people.matric_tell`; recipient from `people.student_reach`: contact email/phone, else the applicant account) | — | One transaction: every number or none. A build error on any student ("the matriculation number cannot be built: …") rolls the whole run back |
| Single issue | same offices, "Issue number" on the faculty list (`POST …/students/{id}/matriculate`) | returns the existing number if any; status ADMITTED ("only an admitted student is matriculated; this one is {status}"); an APPROVED/LOCKED registration for the entry session ("the student has not registered courses for {entry_session}"); `finance.position(entry_session).paid_in_full` ("the school fees for {entry_session} are not settled"); both with HINT "A matriculation number is issued once the school fees are paid and the courses are registered." | a one-student run `MAT/YYYY/NNN` (issued = 1); the same writes as above with reason "Matriculated on fees and registration" | ADMITTED → ACTIVE | Email + SMS as above | — | — |

After the run the screen shows a sample of five allocations and the tiles Registered students / Confirmed by Faculty Officers / Faculties outstanding / Numbers issued. The faculty list's **Fees** column renders "—" (**PLACEHOLDER**) although the run itself checks `finance.position`; a student left without a number after a run was either under query or not `paid_in_full`.

### 4.2 How the number is built

`people.matric_components(student)` reads the single format row `people.matric_format WHERE id = 'UNIVERSITY'` and the student's programme and faculty:

| Component | Source | Rule |
|---|---|---|
| University code | `matric_format.university_code` (seeded `MOAU`; `^[A-Z]{2,6}$`) | always present |
| Faculty segment | when `format.faculty_code` is on: `coalesce(programme.matric_faculty_code, faculty.matric_code, faculty.code)` | a programme may carry its own faculty segment (MBBS → `MBBS`; Biochemistry → `SC`); otherwise the faculty's configured segment (Management → `AD`, Basic Medical → `BM`, Pharmaceutical → `PHRM`, Communication → `CS`, Law → `LAW`, Technology → `TS`), else the faculty code |
| Programme segment | when `format.programme_code` is on **and** `programme.matric_uses_code` is true: `programme.matric_code` | appears only for a programme configured to carry a code (e.g. ACC, CMP, MTH); Medicine and Surgery, Pharmacy and Law carry none; a programme the Registry's schedule does not name carries none until the Registry gives it one — no code is inferred or invented |
| Year of entry | when `format.year` is on: `substr(student.entry_session, 3, 2)` | falls back to the current year only when `entry_session` is null |
| Series | `coalesce(programme.matric_series, faculty.matric_series, 'GENERAL')` | programme → faculty → GENERAL |
| Sequence | the series' next free number | see below |

`people.next_matric(student, run, reason)`:

1. Raises "the matriculation number cannot be built: {problem}" (HINT "The Registry configures the faculty, the programme and the series under Matriculation number format.") when the student has no programme, when the programme is configured to carry a code but `matric_code` is null ("Programme % is configured to carry a code but has none; give it one or set it to carry none"), when the faculty segment is null, or when the series is not active ("The series % is not active").
2. Locks the series row `FOR UPDATE` and tries `last_issued + 1, + 2, …`; a number already on `people.student.matric_no` or in `people.matric_history` (by number, or by series + sequence) is passed over — "the sequence is spent, never reused"; after a thousand tries: "no free number in series % after a thousand tries".
3. Formats with `people.format_matric`: the segments are joined by the configured separator ("/" or "-") with empty segments removed, so there is never an empty separator; the sequence is left-padded to `sequence_digits` when that is greater than 0 (seeded 0 = no padding).
4. Moves `matric_series.last_issued` forward to the sequence used and inserts `people.matric_history` (student, number, series, sequence, `components` JSON {university, faculty, programme, usesCode, year, sequence, programmeCode, facultyCode}, run, issued_by, actor office, reason).
5. The caller writes the number on the student; `people.student.ck_student_matric_shape` accepts the new shape `PREFIX(/SEG){1,4}/NNN…` beside the old `MOAUM/DEPT/YY/NNNN`; `people.matric_is_immutable` refuses any later change ("the matriculation number % is permanent and is not changed", HINT "BR-007…"); `people.matric_history_is_written_once` refuses any UPDATE of the history ("the matriculation history is written once; a number issued is never edited or reused").

Seeded series counters (`db/V263__matriculation_format.sql`, lines 40–45): **ADMIN** "Administration and Management series" 13556 (Faculty of Management Sciences); **COLLEGE** "College series" 6093 (Basic and Applied Medical Sciences, and Medicine and Surgery); **PHARMACY** 198; **ARCHITECTURE** 76; **GENERAL** "Every other faculty" 85631. Faculty defaults: MS → ADMIN, BAMS → COLLEGE, PS → PHARMACY, AC → ARCHITECTURE, every other faculty → GENERAL. Sample numbers issued in the local database: `MOAU/MBBS/20/6095`, `MOAU/AD/ACC/99/13567`, `MOAU/PHRM/99/199`, `MOAU/LAW/99/85632`.

### 4.3 Refusal conditions

| Condition | Where it stops | Message |
|---|---|---|
| A faculty with registered ADMITTED students has not confirmed its list | the run | "the run cannot start: {faculty} has not confirmed its list" |
| The student is under an un-withdrawn query | the run (row skipped) | none — held back; listed under "Held back from this run" |
| School fees for the session not paid in full (`finance.position(...).paid_in_full` false) | the run (row skipped); the single issue | "the school fees for {session} are not settled" (single issue) |
| No APPROVED/LOCKED registration for the entry session | absent from the list; the single issue | "the student has not registered courses for {session}" |
| Status other than ADMITTED | the single issue | "only an admitted student is matriculated; this one is {status}" |
| Programme configured to carry a code but none given | `next_matric` (whole run rolls back) | "the matriculation number cannot be built: Programme … is configured to carry a code but has none; give it one or set it to carry none" |
| Series inactive | `next_matric` | "the matriculation number cannot be built: The series … is not active" |
| No programme / no faculty segment | `next_matric` | "the matriculation number cannot be built: …" |
| Nobody qualifies | the run | "nobody on a confirmed list has both paid the fees and registered for {session}; there is nothing to matriculate" |

### 4.4 The configuration workflow

Matriculation Number Format `/matriculation/config` is read by the matriculation readers and edited by `MatricFormatController.CONFIG` = Academic Office, Registrar, Deputy Registrar, super. Others see the screen read-only.

| Act | Who | Validation | Data | Notes |
|---|---|---|---|---|
| Save the rule (University code, separator, sequence padding, Faculty code / Programme code / Year of entry on or off; Sequence fixed on; Note) | CONFIG | `MATRIC_UNIVERSITY` letters only; `ck_mf_sep` "/" or "-"; `ck_mf_digits` 0–8; `ck_mf_one` single row; `ck_mf_seq` | `people.matric_format` | Live samples are shown; every number already issued keeps its form |
| Add / edit a series (Code, Name, Last number issued, Note, Active) | CONFIG | `MATRIC_SERIES` code `[A-Z][A-Z0-9_]{1,20}`; `MATRIC_SERIES_BACK` "Series % has issued up to %; it does not go back."; `ck_ms_last ≥ 0` | `people.matric_series` | A counter is only ever moved forward; an inactive series stops every issue that depends on it |
| Edit a faculty (Segment, Series) | CONFIG | segment `[A-Z0-9]{2,6}` (`MATRIC_CODE`) | `ref.faculty.matric_code`, `matric_series` | |
| Edit a programme ("This programme carries a programme code in the number", Programme code, Own faculty segment, Series) | CONFIG | `MATRIC_NO_CODE` "The programme is set to carry a code but none is given."; code `[A-Z0-9]{2,6}` | `ref.programme.matric_uses_code`, `matric_code`, `matric_faculty_code`, `matric_series` | The warning "N programme(s) are set to carry a code and have none" and a per-programme problem pill flag what would stop a run; codes are never invented by the system |
| Read | readers | — | `people.matric_config_rows()` (every programme with the number it would give next), the last 25 history rows | Excel / PDF "Matriculation Number Configuration" (serial `MAT`, S/N first: Faculty, Programme, Programme Ref, Faculty Segment, Programme Code, Carries Code, Series, Next Number, Problem) |

No notice is sent on a configuration change; every change is on the audit spine with its `X-Reason`.

### 4.5 What is not implemented

| Item | Status |
|---|---|
| Preview of one student's next number (`GET /matriculation/config/preview/{studentId}`) | PARTIALLY IMPLEMENTED — endpoint, no screen |
| History search (`GET /matriculation/config/history?q=`, last 500) | PARTIALLY IMPLEMENTED — the screen shows the last 25 only |
| "Fees" column on the faculty list | PLACEHOLDER ("—") |
| Faculty scope on list query / confirm | NOT IMPLEMENTED in code |
| "What the run does" text on `/matriculation` and the applicant's Matriculation page | stale — describe the pre-V263 per-department sequence |
| Notice on query, confirm or configuration change | none by design |

> **Screenshot Required:** Matriculation Number Format — `/matriculation/config` — the rule panel with the live pattern, the Series table and the Programmes table with the "Next number or problem" pill.

### 4.6 Matriculation Management: prepared, reviewed, issued (V267)

| Step | Actor | Screen / function | What happens |
|---|---|---|---|
| 1 | Registry / Academic Office / Faculty Officer | Matriculation Management → session, faculty → Load Students | `people.matric_candidates`: the faculty's admitted students of the session, eligible (registered, fees settled, not under query, number buildable) or pending with the reason; grouped by programme. |
| 2 | Preparer | Generate Matriculation Numbers | `matric_batch_generate`: the faculty's one open batch (`MAT/YYYY/NNN`), the series locked, the next free sequence past the last issued and the batches' reservations, a row per student, a reservation per number. Nothing on the student record. |
| 3 | Preparer | review table · Validate · Fix / Edit · Drop | `matric_batch_validate` on every act; `matric_batch_edit_row` (shape, the student's segments, free sequence, reason; `matric_batch_edit` history); `matric_batch_drop_row` (reason; reservation released). |
| 4 | Preparer | Mark ready for issuance | `matric_batch_ready`: zero conflicts, at least one student → READY_FOR_ISSUANCE with the reviewer stamped. |
| 5 | Registry | All faculties tab | `matric_overview`: prepared, valid, conflicts, issued per faculty; the final review totals. |
| 6 | Issuer | Final review → Confirm & Issue | `matric_batch_issue` (READY only; separation of duties honoured; re-validated): per student the history, the series forward, `matric_no` + `matriculated_at` + `matriculation_run`, status ADMITTED → ACTIVE and its `status_change`, `student_username_change` (admission number → matriculation number), reservation released, `matric_tell`. One transaction; a failure issues nothing. `matric_batch_verify` afterwards. |
| 7 | Student | Sign-in | The matriculation number opens the portal on the same account and password; the admission number no longer does once the number is issued (`StudentPortalRepository.byMatric`). |
| 8 | Issuer | Cancel batch | `matric_batch_cancel`: reason required, reservations released, rows dropped; never on an issued batch. Issued numbers are permanent (V263's write-once history). |

Tested end to end by `MatriculationManagementIT`: grouping and the pending reason; generation without writing to the record; another faculty's batch on its own series; a correction refused without the student's segments, a reason or a free number and recorded when right; a duplicate detected and issuance refused; ready; the all-faculties view refused to a faculty officer; issuance refused without confirmation, before ready and to the preparer under separated duties; the issue with its verification, series, histories, status change and notice; the new sign-in and the old one refused on the same account; the registers and the before-and-after; the cancelled batch releasing its numbers.

---
## 5. Academic workflow: structure, registration, results

```text
ICT uploads structure → HOD binds courses and allocates teaching → session/semester OPEN → registration opened
 → student DRAFT → SUBMITTED → HOD APPROVED (or RETURNED)
 → examination session OPEN → score sheets → ENTRY → VERIFICATION → DEPT_BOARD → FACULTY_SCRUTINY
   → FACULTY_COMPILATION → FACULTY_BOARD → RECORDS → SENATE → PUBLISHED (Senate minute)
 → GPA / CGPA / standing computed → broadsheets → result queries (7 days) → carry-overs on the next registration
```

### 5.1 Structure upload, curriculum binding and course allocation

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Faculties, departments, programmes | Director of ICT only (`UPLOADERS = ict`) on Faculties `/structure/faculties`, Departments `/structure/departments`, Programmes `/structure/programmes` (form or `.xlsx`) | programme code `^C[0-9]{5}$`; category UNDER GRADUATE / POST GRADUATE; delete only when nothing hangs on it (`ref.delete_*`) | `ref.faculty`, `ref.department`, `ref.programme` | archive keeps the code (`archived`) | none | Excel/PDF FAC / DEP / PRG (S/N first) | Other offices see "This desk is for the Directorate of ICT…" |
| Course structure upload | Director of ICT on Upload course structure `/catalogue/upload` (CCMAS `.docx` parsed by headings and tables, or `.xlsx` by column names, many programmes at once) | `import_courses_rows`: "no programme is coded or named %"; department must exist; codes normalised; units capped at 12; levels 100–600; status letter C/R/E/G → kind; each row in a savepoint (bad rows counted, `first_error`) | `catalogue.course` (written LIVE; BOARD/SENATE lifted to LIVE), `catalogue.course_offer` with the curriculum track (CCMAS_BSU / CCMAS_MOAU / BMAS / null) | course state LIVE | none | Templates; "All courses" Excel/PDF (serial CAT); per-programme list (CRS) | Programmes not on the register are held back and listed ("Download the list") |
| Department courses | HOD (own department, `CAT_DEPT`), Dean, Academic Office, Registrar, Deputy Registrar, admin, super on Department Courses `/catalogue` | `create_course`: code "three letters, a space and three digits, like CSC 311"; units 0–12; unique code; `make_course_live`: "no course % awaiting approval to make live" / "course % has ended; restore it instead of making it live" | `catalogue.course` BOARD → LIVE → ENDED → LIVE (restore); curriculum tag (`CAT_CURRICULUM`); CA split `ca_max` 0–100 (default 40) | as stated (SENATE is in the CHECK; nothing writes it — **CONFIGURED BUT UNUSED**) | none | — | Making live or restoring also creates the current session's offering when a `course_offer` exists |
| Bind into a programme structure | same owners on Programme Structure `/catalogue/structure` | basis Core / Elective / Borrowed / GST (`CAT_BASIS`); an ENDED course refused (`CAT_ENDED`); unbind refused while students are registered on it this session (`CAT_BOUND_IN_USE`) | `catalogue.course_offer` (course, programme, level, basis, track) | — | none | — | A course bound nowhere shows "Not bound to any programme — no student sees it at registration" |
| Teaching allocation | HOD (own department, `ALLOC_DEPT`), Dean, Academic Office, Deputy Registrar, Registrar, admin, super on Teaching Allocation `/allocate` | `catalogue.allocate_offering`: "an allocation names the lecturer who teaches it"; "the second examiner cannot be the lecturer"; "this assignment puts the lecturer at N units, over the approved maximum of 12" unless saved as an overload; `ALLOC_ENDED` | `catalogue.offering.lecturer_id`, `second_examiner_id`, `allocated_on`; co-lecturers in `catalogue.offering_teacher`; an `assessment.score_sheet` is created at once when an examination session for the semester is OPEN | — | none ("reported to the Dean" for overloads is a hint only — **NOT IMPLEMENTED**) | — | `ALLOC_BUSY` after an 8-second lock wait |

### 5.2 Session and semester opening; course registration

The academic calendar (`policy.academic_session` CURRENT / PLANNED / CLOSED, `policy.semester` state OPEN with `registration_closes` and `late_registration_closes`) is kept by the Registry on Calendar `/calendar` (see *02 Administrator Manual*). Opening registration for a session (`registration.open_course_registration(session, semester)`, button on `/catalogue/upload`; `OPENERS` = ict, super, admin, hod, dean, academic, registrar, dregistrar) inserts an offering for every non-ended course of that semester bound to some programme ("no academic session % on the calendar — open the session first"); it is idempotent.

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Draft | Student on Course Registration `/student/register?session&semester` | status ADMITTED / ACTIVE / PROBATION (`REG_STUDENT_NOT_ELIGIBLE` "A student who is … does not register."); the fee gate card "You cannot register yet" until `finance.semester_cleared` | `registration.course_registration` at the current level; every carryover from `registration.student_menu` inserted as CARRYOVER entries | DRAFT | none | — | — |
| Choose | Student ("Save the draft") | `student_choose`: only DRAFT or RETURNED ("this registration is %; it is not edited", HINT "A submitted registration is changed by the level adviser returning it."); "that course is not offered to your programme at your level this semester"; a SIWES semester offers exactly the SIWES units | `registration.entry` (type CURRENT / ELECTIVE / GST / BORROWED / CARRYOVER) | DRAFT | none | — | — |
| Submit | Student ("Submit for approval") | `student_submit`: "the first/second semester school fees for {session} are not fully paid" (HINT "Course registration for a semester opens when that semester's school fees are cleared in full…"); units within `policy.level_limit` ("the registration carries % units; at % level the range is % to %", HINT "…or obtain an overload approval from the Head of Department" — no overload mechanism exists); on PROBATION with a `probation_max_units` ceiling the ceiling applies (all ceilings are NULL — **CONFIGURED BUT UNUSED**); trigger `people.deferment_gate_course_registration`: "REGISTRATION UNAVAILABLE: your deferment for % is approved; you cannot register for the deferred period" | `submitted_at` | DRAFT / RETURNED → SUBMITTED | none | — | — |
| Approve | HOD of the department (or super) on Departmental Approvals `/results/approvals` | `RegistrationService.approve`: status ADMITTED / ACTIVE / PROBATION ("(I-STU-2)"); SIWES semester carries exactly the SIWES units; else the level range (`REG_UNITS_OUT_OF_RANGE`); `REG_OTHER_DEPT` "This registration is in another department." | `approved_at`, `approved_by`; entries REGISTERED → APPROVED; triggers release held scripts | SUBMITTED → APPROVED | none (**NOT IMPLEMENTED**) | Course form PDF `/student/form` with QR → `/verify/registration?m&s&sem&c` | — |
| Return | HOD / super | `REG_RETURN_SAYS_WHY` "A registration is returned with the reason on the record." | `returned_comment` | SUBMITTED → RETURNED | none; the student reads "Returned to you" with the reason on the registration screen | — | The student edits and resubmits |
| Add / drop after submission | Student, panel "Add or drop courses" | `registration.add_drop_open` (semester OPEN and today ≤ late deadline: "add and drop is not open for {session} semester {n}"); `finance.clears(…,'REGISTRATION')`; add: "adding this course puts you at % units, over the maximum of % at % level"; drop: "a carryover cannot be dropped; it must be repeated"; "a mark is already recorded in this course; it cannot be dropped" | entry added (APPROVED at once on an APPROVED registration) or → DROPPED | — | none | — | — |
| LOCKED | — | `LOCKED` is in `ck_reg_status` but **no code sets it**; every "APPROVED/LOCKED" test is effectively APPROVED | — | — | — | — | — |

Class lists, attendance registers and examination rolls are read on Registered Students `/registration/class-list` (plain CSV, not the branded export); the roll's Clearance column reads `clearance.is_clear(student,'EXAMINATION')`. An office-created registration (`POST /registration/course-registrations`, `APPROVERS`) exists without a screen and inserts entries as given without menu validation.

### 5.3 Score sheets and the approval chain

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Examination session | `EXAMS` = records, academic, registrar, dregistrar on Examination Sessions `/examinations/sessions` (type MAIN / RESIT / SPECIAL; dates; score sheets due) | `EXAM_DATES` "The examinations end before they begin." / "The score sheets are due before the examinations end."; `EXAM_DUPLICATE`; `EXAM_HAS_SHEETS` (only dates change once sheets exist) | `assessment.exam_session`; opening generates one `assessment.score_sheet` per allocated offering (RESIT/SPECIAL only where the MAIN sheet is PUBLISHED); "N score sheets generated; M courses have no lecturer and generated none." | DRAFT → OPEN (CLOSED is in the CHECK; nothing sets it) | none | — | — |
| Score entry | Lecturer (lead, second examiner or co-lecturer — `own`), Examinations Officer, Academic Office on Score Sheets `/results/sheets/{id}` (typed, or upload of the template) | `RES_SHEET_NOT_AT_ENTRY` "The sheet is at {stage}; a mark changes by amendment with a reason, not by entry."; trigger `score_within_split`: "continuous assessment in {code} is out of {caMax}, not {n}" / "the examination in {code} is out of {examMax}, not {n}"; `RES_MARK_ON_RECORD` "A saved mark is on the record; the lecturer does not change it on their own." unless the latest decision is a RETURN; `RES_AMENDMENT_SAYS_WHY`; an upload with any refused line writes nothing ("{file} was not accepted — N lines refused, nothing written") | `assessment.score` versions (never overwritten); total, grade, points computed (`grace_total`: 39 → 40) | ENTRY | none | Template xlsx/CSV; marked sheet Excel/PDF; validation report CSV | Candidates on an upload but not on the roll may be held (§5.4) |
| Promote CA from the course space | Lecturer on the course space `/lms/{offering}` | `lms.promote_ca`: MAIN sheet at ENTRY ("the score sheet has left the lecturer; the gradebook is not promoted into it") | new `assessment.score` version with `ca = least(40, round(total))`, reason "Promoted from the course space gradebook…" | ENTRY | none | — | — |
| Submit and attest | Lecturer ("I attest these marks") | `assessment.advance`: every candidate of `sheet_candidates` has a mark or an outcome ("N registered candidate(s) on this sheet have no mark and no outcome", HINT "…A blank is not an outcome.") | `assessment.decision` kind SUBMIT | ENTRY → VERIFICATION | none | — | — |
| Desks: VERIFICATION → DEPT_BOARD → FACULTY_SCRUTINY → FACULTY_COMPILATION → FACULTY_BOARD → RECORDS → SENATE | UI map `Sheets.DESK`: exams → hod → facultyexams → facultyofficer → dean → records → registrar/dregistrar, on Result Desk `/results/desk`, Approvals `/results/approvals`, Approval Chain `/results/chain?sheet=` | **BR-006**: "you approved the previous stage of this sheet; another desk must approve this one" when the last SUBMIT/ADVANCE actor is the same person; a fail rate above 50 % is a UI caution only (Approve hidden behind Review; excluded from bulk forwarding) — the API does not block it | `assessment.decision` kind ADVANCE per move | one stage forward (`assessment.stage_after`) | none | — | **Return**: any stage except ENTRY and PUBLISHED, back to ENTRY with a reason (`RES_RETURN_SAYS_WHY` "A sheet is returned with the reason on the record."; `ck_decision_return_says_why`); `returned_times` + 1; every mark opens for amendment with a reason; resubmission re-enters at VERIFICATION |
| Senate minute → PUBLISHED | Registrar / Deputy Registrar on Senate Schedule `/results/senate` or Publication `/results/publish` ("Record the minute and release", every sheet at SENATE in scope, each in its own transaction); or a single sheet from the Chain screen | "a result reaches a student on the Senate minute that approved it, and none was cited" (`RES_MINUTE_REQUIRED`); BR-006 refusals are listed by sheet ("N sets published under {minute}, M refused") | `senate_minute`, `published_at`, `engine_version = 'GpaCalculator 2.1'` | SENATE → PUBLISHED | **none — publication does not notify students** | Statement of results PDF becomes available to the student; broadsheets | "this sheet is published; there is no stage after publication" |

The stage-to-office map is enforced only in the UI (`mayAct`); `assessment.advance` enforces completeness, the minute and "not the same person twice in a row", so any `DESKS` office can advance any stage through the API. The reminder / escalation button for a late sheet returns 202 "The notification module is not on the portal yet; nothing was sent." (**PLACEHOLDER**).

### 5.4 Publication, result queries, held scripts

**Result queries** (`assessment.result_query`, ref `QRY-YYYY-NNNNN`):

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Raise | Student on Result Query `/student/query` (course, part EXAM / CA / ABSENT, "What you say is wrong") | `assessment.query_window_open` = PUBLISHED and `published_at + 7 days > now()` ("the query window for this course is not open" — the HINT says "five working days" although the window is seven calendar days); "no mark of yours is on this sheet"; "a query on this mark is already open" (409); `RES_QUERY_PART`, `RES_QUERY_SAID` | `result_query` routed to the department that owns the course | RAISED | none — the department is not told (a count appears on `/results/mine`) | — | — |
| Answer | hod, lecturer, exams, dean, records, academic, registrar, super on Result Queries `/results/queries` (finding Upheld / Corrected / Closed, answer text) | "a query is answered in words"; "this query was answered on {date}"; `RES_QUERY_STATE` | `answer`, `answered_at/by` | RAISED → UPHELD / CORRECTED / CLOSED | Email "Your result query {ref} is answered" + SMS "Your result query is answered" | — | **CORRECTED has no mechanical effect**: `return_sheet` refuses PUBLISHED and `scores` refuses a sheet not at ENTRY; the Chain screen's "Raise an amendment" button has no handler — no correction path exists for a published mark (**NOT IMPLEMENTED**) |

**Held scripts** (`assessment.held_script`): a mark from a candidate not on the roll is held by matriculation number from the panel under the score sheet (lecturer, exams, academic; no ownership check on the sheet). `hold_script`: "no student on the register is numbered X"; "X is on the roll of {code}; enter the mark on the sheet"; "late registration for this semester closed on {date}; a script can no longer be held for {code}"; "a script is already held for X on {code}". The student is told at once (Email + SMS "Your {code} script is held until you register"). States: HELD → RELEASED (trigger when the registration or entry becomes APPROVED — a new score version, even on a sheet past ENTRY), HELD → LAPSED (lazily at every read once `policy.semester.late_registration_closes` has passed; if no date is set, held scripts never lapse), HELD → WITHDRAWN ("only a script still held is withdrawn"). The Bursar reads the students a held script is waiting on with what they owe at Held Scripts `/finance/held-scripts` (no export).

**Publication has no notice.** The only results-related notices are the query answer and the held-script notice. A result changed after a document was issued flags the student's active transcripts and statements (`trg_score_flags_documents`, §8).

### 5.5 GPA, CGPA, standing and broadsheets

Nothing is typed: `assessment.latest_scores` (latest version, grace mark, grade and points from `policy.grade_of` at `current_date` — not at publication; only the SEN/2015/44 scheme is seeded: A 70–100 = 5, B 60–69 = 4, C 50–59 = 3, D 45–49 = 2, E 40–44 = 1, F 0–39 = 0); `assessment.course_final` (a PUBLISHED SPECIAL over a PUBLISHED RESIT over the MAIN; a passed re-sit is recorded at 40, grade E); `assessment.student_results` (a missing score or ABSENT on a published sheet counts as F, 0 points); `assessment.student_gpa` (CUR, CUE, WGP, GPA; running TCR, TCE, TWGP, CGPA, LCGPA; WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED do not count in units); `registration.carryovers_at` (non-elective courses failed on a published sheet and not later passed); `assessment.standing_of` (NULL when CGPA ≥ 1.0; first semester → PROBATION from 200 level unless a Direct-Entry student's 200 level; second semester → ADVISED_TO_WITHDRAW when level ≥ 200 and the previous CGPA was also < 1.0, otherwise PROBATION); `assessment.student_standing` → GOOD / PROBATION / ADVISED_TO_WITHDRAW on the latest published semester. `policy.class_of` has no band under 1.00, so the class of standing prints "—" for a CGPA under 1.0. The student's statement PDF hard-codes the grading key rather than reading the policy table.

The broadsheet (Broadsheet `/results/broadsheet`, by programme, level, session, semester) computes every candidate across courses with CURRENT and CUMULATIVE figures and REMARKS in Senate's wording: "CO: {core courses owed}", "Fail: {electives failed}", "TO GO ON PROBATION", "ADVISED TO WITHDRAW", "PENDING" (a set still in the chain), "PASS", "DID NOT REGISTER FOR THIS SEMESTER"; a mark counts once its set is at RECORDS, SENATE or PUBLISHED. From 200 level it lists the class, "DIRECT ENTRY STUDENTS", then the "PROBATION LIST" (first semester) or "ADVISED TO WITHDRAW" (second). Exports: Excel (sheets Summary and Broadsheet, serial BRD) and a print-window PDF of the Examination Reporting Sheet; no QR. The results fee gate withholds marks server-side per session when the clearance scheme's RESULTS rule is not met (`withheld: true`, GPA nulled).

Voluntary withdrawal: `registration.voluntary_withdrawals_due()` names ADMITTED / ACTIVE / PROBATION / DORMANT students with four or more consecutive closed semesters without an APPROVED registration (semesters covered by an approved deferment are skipped); the Registry closes them from Students `/students` ("Close all N due" / "Close") with the instrument "University regulation: four consecutive semesters without course registration" → status VOLUNTARY_WITHDRAWAL; the portal then refuses the student at `/api/v1/me` with `STUDENT_RECORD_CLOSED`. No notice is sent.

### 5.6 The College of Health Sciences variant

From 200 Level a College (MB;BS, programme C00061) student runs on the College's own years rather than the University's semester GPA. Desk offices: Provost (`provost`), College Secretary (`collegesecretary`), Academic Office, Registrar, Deputy Registrar, admin, super; the MBBS Coordinator (`mbbscoordinator`) is bound to one level (`COLLEGE_NOT_YOUR_LEVEL` "The MBBS Coordinator acts at N Level; this is M Level."); examiners add lecturer, hod, exams of the College's own departments (`COLLEGE_NOT_EXAMINER`).

```text
100 Level (University courses, judged by college.decide_100: every non-GST course ≥ 50, else advice to withdraw — read-only)
 → 200 Level year: register semester 1 on semester-1 fees → semester 2 on semester-2 fees (college.register_level / register_semester)
 → the year reaches its final dated semester → CPE results per subject (CA 30 + Exam 70 [+ clinical], attendance %, pass 50)
 → provisional decision (college.apply_provisional → college.decide)  PROMOTE | RESIT | REPEAT | WITHDRAW_ADVISED | WITHDRAW_REQUIRED | APPEAL | GRADUATE
 → College Academic Board confirms on a minute (college.confirm_decisions)
      PROMOTE → current_level + 100 · RESIT → enrolment RESIT · REPEAT → year CLOSED, new REPEAT year
      WITHDRAW_* → people.change_status(WITHDRAWN, "College Academic Board minute …")
      GRADUATE (600) → people.change_status(GRADUATED …) with Honours when a distinction (≥ 70) stands in each of PE1–PE4
 → 400+: postings ALLOCATED → IN_PROGRESS → COMPLETED | INCOMPLETE with logbooks
 → PE4 APPEAL → Senate minute (college.grant_appeal) → APPEAL enrolment (4th attempt)
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Open the year / register | Student ("Register {semester}" on `/college/student`) or the desk / coordinator ("Open the year for a student") | `register_level`: "100 Level registers on the University's form, by semester"; "the N Level year is still open; it closes by the Board's decision before M Level opens"; "the N Level fees for {session} are not yet cleared" (HINT "Registration opens the moment the session's first semester fees are confirmed; the second semester's are due before its results."); `register_semester`: "the earlier semester is registered first"; the College's 100 Level rule refuses 200 under WITHDRAW_ADVISED ("the College's 100 Level rule does not promote: {courses} below 50"); deferment triggers refuse a deferred student | `college.enrolment` (kind REGULAR / REPEAT / APPEAL), `enrolment_semester` | enrolment OPEN | none | — | — |
| Calendar | DESK on College Calendar `/college/calendar` | `COLLEGE_CALENDAR` "A semester ends after it starts." | `college.semester` (the one editable configuration) | — | none | — | An undated level counts as "year reached final" (results can be entered any time) |
| Postings and logbooks | DESK allocates on Postings `/college/postings`; supervisors write logbooks on Logbooks `/college/supervision` | `COLLEGE_DATES` "A posting ends after it starts."; `COLLEGE_NOT_MEMBER`; `COLLEGE_NOT_SUPERVISOR` "This posting is supervised by someone else…"; `COLLEGE_ALLOC_STARTED` (withdraw only while ALLOCATED) | `posting_allocation`, `procedure_log`, `case_clerking`, `attendance_record`, `event_attendance` | ALLOCATED → IN_PROGRESS → COMPLETED / INCOMPLETE | none | — | — |
| Results | EXAMINERS on Professional Examinations `/college/examinations` (per subject) or Score Sheet `/college/scoresheets` (bulk upload with preview) | `COLLEGE_YEAR_NOT_ENDED` "The N Level year for {session} has not reached its final semester; the College's students sit once, at the end of the year."; `COLLEGE_CA_RANGE` "{subject}: CA is out of 30."; `COLLEGE_EXAM_RANGE`; `COLLEGE_ATTENDANCE`; `COLLEGE_CLINICAL`; attempt FIRST / RESIT / REPEAT / SENATE_APPEAL | `college.exam_result` (`college.judge`: passed = total ≥ 50 and clinical minimum, unless attendance < minimum → barred); `apply_provisional` after every save | provisional decision PROVISIONAL once all subjects are resulted | none | Score sheet template and marked sheet (xlsx) — the letterhead constant names another university (defect); results-and-decisions CSV | A partly refused bulk sheet still saves the good rows |
| Board override | DESK ("Change the provisional decision", minute) | `COLLEGE_CONFIRMED` "The Board has confirmed this candidate's decision; it is not changed here."; `COLLEGE_UNDECIDED` | `progression_decision` | PROVISIONAL | none | — | — |
| Confirm | DESK ("Confirm N decisions", Board minute) | `confirm_decisions`: "the Board confirms on a minute, and none was cited" | decisions CONFIRMED; enrolment RESIT or CLOSED; level, status changes as in the diagram | as in the diagram | none (**NOT IMPLEMENTED** — no College notice at all) | — | A confirmed RESIT is re-opened for the Board by the resit's results |
| Appeal | DESK ("Record Senate's approval of the appeal") | `grant_appeal`: "no appeal stands for this student: the last confirmed decision at 600 Level is …"; "Senate's approval is recorded on its minute, and none was cited"; `COLLEGE_NO_APPEAL` "{exam} carries no appeal to Senate." | APPEAL enrolment (4th attempt) | — | none | — | — |

Seeded rules: CPE (200; no resit; attendance 75 %), PE1 (300; resit; no resit if all failed; 75 %), PE2 (400; 70 %), PE3 (500; 70 %), PE4 (600; appeal to Senate; no attendance minimum); every subject CA 30 / exam 70 / pass 50. No screen edits the examination, subject or posting configuration (**NOT IMPLEMENTED**). Nothing "crosses" a College result to the University results chain; the reconciliation "ready for Senate" is a read. The Finance Controller's Student Payment Report `/college/payments` reads `finance.payment_position` (FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE).

### 5.7 What is not implemented

| Item | Status |
|---|---|
| Notice to students on publication; on registration approval / return; to the department on a new query; to College students on a decision | NOT IMPLEMENTED |
| Correction of a published mark after a CORRECTED query; "Raise an amendment" / "View as a student" buttons | NOT IMPLEMENTED / PLACEHOLDER |
| Reminder / escalation of a late score sheet | PLACEHOLDER (202 "nothing was sent") |
| Office-per-stage enforcement in the database; ownership check for holding scripts | NOT IMPLEMENTED |
| HOD overload approval; probation unit ceiling; LOCKED registration; SENATE course state; CLOSED examination session | NOT IMPLEMENTED / CONFIGURED BUT UNUSED |
| Second examiner acting at VERIFICATION (the `exams` office holds that desk; the second examiner gains read access only) | PARTIALLY IMPLEMENTED |
| CBT examinations (paper assembly, delivery, scoring) — the question bank `/exams/question-bank` is a bank only | NOT IMPLEMENTED |
| Editing exam / subject / posting configuration of the College; `college.carry_over`, `college.project`; Provost dashboard endpoint screen | NOT IMPLEMENTED / CONFIGURED BUT UNUSED |
| "Withheld set" wording on the Senate screen; "Print the Senate schedule" | NOT IMPLEMENTED |

---

## 6. Finance workflow

```text
Bursar states the fee schedule (lines with filters) → finance.charges(student, session) computed per student
 → student mints a reference MOAUM-FEE-… (24 h) → pays: card/USSD gateway | PayDirect PRN | bank branch | wallet | legacy import
 → webhook / verify / sweep / Bursary confirm → finance.confirm_payment → receipt RCT-YYYY-NNNNN (idempotent)
 → finance.position (due, paid, balance, instalments, arrears) · finance.semester_cleared
 → gates: registration (per semester, paid in full) · examination · results · transcript · hostel · ID card (clearance scheme)
 → refunds (maker–checker) · bank credits (maker–checker) · reconciliation · GL sync (manual) · reports
```

### 6.1 Fee schedule to charges

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| State the schedule | Bursar / super (`BURSARY`) on Fee Setup and Schedule `/finance/fees` (add, edit, end, clear a line; or the approved-fees bulk upload) | item ≤ 120 chars, amount ≥ 0, "A level is 100 to 900 (700–900 are postgraduate).", "A semester is 1 or 2.", "That fee line is not on the current schedule."; the bulk upload replaces the session's structure ("The structure has no rows to read.") | `finance.fee_schedule` (session, item, amount, level, entry mode, faculty, programme, fee group, semester, indigene, spillover, ord); a line is live while `ended_at IS NULL` | — | none | — | Ending a line removes it from every charge at once |
| Charges computed | nobody — `finance.charges(student, session)` at every read | a line applies when every filter it carries is blank or matches: level (ignored for a spillover student), entry mode, faculty, programme, fee group (by programme category), indigene (state of origin vs `fee_setting.home_state`, default Benue), spillover (past `finance.final_level`: 900 PG, 600 Medicine, 500 LL.B / Pharmacy, else 400, and not GRADUATED), and semester ≤ the highest OPEN semester (3 when none is open) | none | — | none | — | A student with due = 0 matches no line, or the lines are semester-tagged and no semester is OPEN |
| Clearance scheme | Bursar (`POST /finance/clearance-scheme {instrument, from}`) | two schemes may not overlap | `policy.version(kind='clearance')` with rules REGISTRATION / ID_CARD / LIBRARY → INSTALMENT_1, HOSTEL → NEVER_GATED, EXAMINATION / RESULTS / TRANSCRIPT / CONVOCATION → PAID_IN_FULL | — | none | — | Without a scheme `finance.clears` fails closed: "no clearance scheme in force for UNIVERSITY on <date> — D-Q4 is unanswered" |

### 6.2 Reference, payment, confirmation, receipt

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Mint a reference | Student on School Fees `/student/fees` ("First semester · ₦x", "Full session", "Second semester", or an amount) | `finance.new_reference`: "no charge is stated for {session} yet" (HINT the Bursar states the schedule first); "a payment is for an amount"; "the amount X is more than the balance of Y" (HINT "Pay the balance, or part of it; nothing is taken beyond what is owed.") | `finance.payment_reference` `MOAUM-FEE-<last 7 of the number>-<4 digits>`, `expires_at = now() + 24 h` | OPEN (derived: unconfirmed and unexpired) | none | — | EXPIRED after 24 h — "This reference has expired." (remedy "Generate a new one; it is free of charge.") |
| Pay by card / USSD | Student or applicant (`POST /payments/checkout {reference, gateway}`) | `PAY_ALREADY_CONFIRMED`; `PAY_REFERENCE_EXPIRED`; `PAY_NO_EMAIL` for card gateways; `PAY_GATEWAY_NOT_WIRED` "Card and USSD payment arrive when a payment gateway is wired to the portal." | `finance.gateway_attempt`; hosted page on Paystack / Flutterwave / Quickteller, or a PayDirect PRN instruction (`*723*<biller>*<amount>#`) | — | none | — | Return URLs `/student/fees?paid=REF`, `/applicant/fee`, `/applicant/accept`, `/pg/portal` trigger a server-side verify |
| Webhook / verify / sweep | gateway webhook (signature checked before parsing: Paystack HMAC-SHA512, Flutterwave `verif-hash`, Quickteller re-queried); "I've paid — check now" (`POST /payments/verify`); the sweep every 10 minutes for attempts older than 5 minutes with < 12 checks | `settle`: UNKNOWN_REFERENCE, NOT_SUCCESSFUL, SHORT_PAID (nothing confirmed), else confirm; every outcome logged in `finance.gateway_event` (SETTLED, ALREADY_SETTLED, BAD_SIGNATURE, GATEWAY_ERROR, IGNORED) | confirmation with channel "Card · Paystack|Flutterwave|Quickteller" or "Quickteller PayDirect", actor NOBODY office `bursar` | — | (see confirm) | — | A bad signature answers 401 and is logged; the Bursar reads exceptions on Hanging Payments `/finance/hanging` |
| Bank branch / PayDirect report / manual | Bursar: bank credit maker–checker (§6.5) with channel "Bank branch"; PayDirect collections import (PRN = reference; unknown PRNs stored UNMATCHED); `POST /finance/references/{reference}/confirm` with a typed channel | "no reference X was generated by this portal" (23503, HINT money sent elsewhere did not reach the University); "a payment is confirmed by a person" | as confirm | — | — | — | A manual confirm always confirms the reference amount — it cannot short-pay |
| Confirm | `finance.confirm_payment(reference, channel, note)` — the single point every path reaches | idempotent ("already confirmed"); `ck_pref_confirmed` requires confirmed_by, channel and receipt_no | `confirmed_at/by`, `channel`, `receipt_no = RCT-<first 4 of session>-<5-digit RECEIPT series>`; side effects by purpose (§6.4) | CONFIRMED | Email "Your payment is confirmed" (amount, reference, receipt, a purpose sentence, "Sign in to download the receipt.") + SMS "MOAUM: payment <ref> confirmed, receipt <no>." | Receipt `/student/receipt/{reference}` and PDF with QR → `/verify/receipt/{ref}?c=` (public answer only with the 12-hex check code) | — |

### 6.3 Position and gates

`finance.position(student, session)`: due = Σ charges; paid = Σ confirmed references of the session whose purpose is `School fees%`; balance = max(due − paid, 0); `instalments_paid` = 2 when due = 0 or paid ≥ due, 1 when paid × 2 ≥ due, else 0; `paid_in_full`; `has_arrears` = an earlier session with a live schedule whose charges exceed its payments. `finance.semester_cleared(student, session, n)` = confirmed school-fee payments ≥ the charge up to and including semester n.

| Gate | Rule | Where it bites |
|---|---|---|
| Course registration | `semester_cleared` for the semester (paid in full) | `student_submit`; the College's `register_level` / `register_semester` |
| Add / drop, hostel maintenance | `finance.clears(…,'REGISTRATION')` (INSTALMENT_1 under the recommended scheme) | `student_add` |
| Examination docket / card | `clears(…,'EXAMINATION')` (PAID_IN_FULL) | `/student/exams`, exam card PDF (409 "Not cleared for examinations"), class-list Clearance column |
| Results | `clears(…,'RESULTS')` — marks nulled server-side per session | `/student/results`, statement PDF (409 "Withheld") |
| Transcript | `clears(…,'TRANSCRIPT')` and the TRANSCRIPT clearance units | document requests HELD_AT_CLEARANCE |
| Identity card | `clears(…,'ID_CARD')` (INSTALMENT_1) | `credentials.issue_identity_card`: "the Bursary has not cleared this student for the identity card in {session}" |
| Hostel | NEVER_GATED by the scheme; the bed itself is held until its own reference is confirmed | `hostel.confirm_by_reference` |
| Matriculation | `position(...).paid_in_full` | the run and the single issue (§4) |
| Documents (convocation) | `clears(…,'CONVOCATION')` PAID_IN_FULL plus the eight clearance units | certificate issue (§8) |

### 6.4 Other purposes: applicant, postgraduate, hostel, document, transcript, library, transfer, wallet

| Purpose | Reference and minting function | Confirmed by | Side effect on confirmation |
|---|---|---|---|
| Applicant application / acceptance | `admissions.fee_reference` `MOAUM-APP-…` / `MOAUM-ACC-…` (`new_fee_reference`) | gateway → `admissions.confirm_fee`; office endpoint exists without a screen | `fee_confirmed_at` / `acceptance_confirmed_at` → `settle_acceptance`; Email + SMS "Your payment receipt · RCT-…" |
| PG application / checking / acceptance | `admissions.pg_fee_reference` `MOAUM-PGAPP-|PGCHK-|PGACC-NNNNNN` | gateway → `pg_confirm_fee`; PG Secretary / Bursar desk (channel "bank") | unlocks the portal steps; lifts DECISION_LOCKED; OFFERED → ACCEPTED; Email per step |
| Hostel accommodation, hostel damage charge | `finance.new_purpose_reference` "Hostel accommodation …" / "Hostel accommodation damage {ref} {id}" | `finance.confirm_payment` → `hostel.confirm_by_reference` | allocation HELD → CONFIRMED (or "the hold on this bed lapsed before the payment arrived, and the bed went to the next name on the draw"); DAMAGE_CHARGES_SETTLED item CLEARED; desk email "A hostel fee has been confirmed" |
| Document / transcript request | "Transcript {ref}" via `credentials.request_document` | `finance.confirm_payment` sets `paid_at` → trigger `credentials.request_paid` | request AWAITING_PAYMENT → READY or HELD_AT_CLEARANCE; `sla_due_on` stamped |
| Library fine | "Library fine {loan id}" (`library.fine_reference`) | `finance.confirm_payment` → `library.settle_by_reference` | fine settled |
| Inter-departmental transfer | "Inter-departmental transfer to {programme}" (`people.transfer_fee_reference`; refused until `finance.fee_setting.transfer_fee` is set) | `finance.confirm_payment` | the current department may approve; the Academic Office effects only on a confirmed fee |
| Wallet top-up | "Wallet top-up …" (`POST /me/wallet/topup-reference`) | `finance.confirm_payment` | TOPUP wallet entry ("Your wallet is credited.") |
| Wallet applied to fees | `finance.apply_wallet` mints a school-fee reference for min(asked, balance, fees balance) and confirms it at once, channel "NELFUND wallet" | immediate | APPLIED wallet entry; the §6.2 notice |

Wallet and NELFUND: an append-only ledger (`finance.wallet_entry` kinds CREDIT / TOPUP add; APPLIED / REVERSED / REFUND subtract) fed by remittance batches the Bursary loads and matches on Sources & Wallets `/finance/nelfund` (rows MATCHED / UNMATCHED with owner Registry or Bursary / REVERSED), Fund statuses APPROVED / NOT_APPROVED / PENDING, and withdrawals REQUESTED → APPROVED → PAID by a different officer ("the officer who approved a withdrawal does not also pay it") — the payout is recorded, not executed.

### 6.5 Bank credits, refunds, reconciliation, general ledger

| Workflow | States and actors | Rules (messages as written) | Notices |
|---|---|---|---|
| Bank credit (Payment Investigation `/finance/exceptions`) | UNMATCHED → PROPOSED (one Bursary officer names a portal reference and why) → POSTED (a *different* officer approves; runs `confirm_payment` / `admissions.confirm_fee` with channel "Bank branch"); reject → back to UNMATCHED with `rejected_why`; REVERSED in the CHECK, never set | "Money against a settled reference is a duplicate: raise a credit for the student, not a second posting."; "A part payment is applied against a reference for the part; generate one for the amount received."; "the officer who proposed a posting does not approve it" (`ck_bc_two_people`) | the §6.2 payment notice on posting; nothing else |
| Refund (Refunds & Credits `/finance/refunds`) | PROPOSED → APPROVED (second person) → PAID; PROPOSED → REJECTED (why); reference `RF-YYYY-NNNN` | amount > 0, payer and reason required; against a source reference: portal-issued, confirmed, "a refund of NGN X exceeds the NGN Y paid on Z"; "the officer who raised a refund does not approve it" (`ck_rf_two_people`); pay only when APPROVED | none; the payout is recorded, not executed |
| Reconciliation (Reconciliation `/finance/reconcile`) | append-only rows per confirmed reference: MATCHED or DISCREPANCY (note mandatory) by bursar, audit, deputyaudit, super | — | none |
| General ledger (Accounting & Books `/finance/accounting`) | `POST /finance/accounting/sync` (manual; no scheduler) maps payment categories to income accounts 4010–4090 and voucher kinds to expense accounts; manual journals POSTED → REVERSED by a reversing journal; a source transaction posts at most once | "A journal needs at least two lines."; "Each line is a debit or a credit, and positive."; "The journal does not balance: debits X ≠ credits Y."; "A line names an account that is not on the chart."; deferred trigger `gl_balance` | none |
| Reports | Payments Query `/finance/payments` (Excel / print with totals and breakdowns), day book `/finance/ledger`, Bursary dashboard tiles, College Student Payment Report (Excel / PDF, serial CHSPAY), `/audit/revenue`, trial balance, income & expenditure, balance sheet | — | — |

### 6.6 What is not implemented

| Item | Status |
|---|---|
| Scheduled GL sync; accrual accounts | NOT IMPLEMENTED (manual sync; 0 journals locally) |
| Bank-credit REVERSED state | NOT IMPLEMENTED |
| Refund / withdrawal payout executed by the portal | RECORD ONLY |
| Quickteller hosted page and PayDirect query API against live merchant settings | IMPLEMENTED, UNVERIFIED AGAINST LIVE ("confirm on onboarding") |
| Fee-setup access for the Finance Controller and PG Secretary (menu present; `finance/*` guards exclude them) | PARTIALLY IMPLEMENTED |
| Notices on bank credits, refunds, reconciliation, schedule changes | none by design |
| Export from the NELFUND / wallet desk; Student 360 Finance card ("NOT YET SERVED"); Records & queries "fees" tab | NOT IMPLEMENTED / PLACEHOLDER |

---
## 7. Deferment, transfer, biodata change and status changes

### 7.1 Deferment (V259, revised by V264 and V265)

A matriculated student pays the **deferment application fee** (₦10,000 by default; the Bursary states it on Fee Setup) through the University's own payment reference; only a **confirmed** payment opens the application form. The application then passes five desks in a fixed order — Bursary, Head of Department, Faculty, Academic Office (forwarding), Deputy Vice-Chancellor (Academic) with a comment — and the **DVC's approval is final**: it applies the **academic effect**: the courses of the deferred period are marked DEFERRED (never failed, no grade, no units attempted, no quality points), the GPA and CGPA are untouched, the expected completion moves by exactly the period deferred, the entry session and the matriculation number never change. A daily clock brings the period into force; the return is confirmed; the deferred courses then become due on the registration form under their own heading. Every turn, and every reading and download by a desk, is on a write-once trail (`people.deferment_event`) and tells the student by email and SMS.

```text
Student: /student/deferment      Desks: /deferments · /deferments/{id} · /deferments/returns · /deferments/batches
PAY FEE (PENDING → CONFIRMED) → DRAFT → SUBMITTED (WAITING BURSARY ACTION) → BURSARY_APPROVED (WAITING HOD ACTION)
   → DEPT_RECOMMENDED (WAITING FACULTY ACTION) → FAC_RECOMMENDED (WAITING ACADEMIC OFFICE ACTION)
   → FORWARDED_TO_DVC (WAITING DVC ACTION; batch DEF-DVC-YYYY-NNNNN) → APPROVED (the DVC's approval is final) → ACTIVE → COMPLETED
   side exits at any review stage: CORRECTION_REQUIRED (resubmits to the desk that returned it) · REJECTED · CANCELLED
return status: UPCOMING → DUE (within reminder_days) → OVERDUE (past return_on + overdue_after_days) → RETURNED
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Pay the fee | Student (**Pay ₦10,000 Deferment Fee** on `/student/deferment`; card/USSD through the gateways or a bank branch quoting the reference) | eligibility as before (`people.deferment_eligibility`); `people.deferment_fee_start` reuses a live PENDING or unspent CONFIRMED reference | `finance.payment_reference` (purpose "Deferment application fee", 24 h) + `people.deferment_fee` (PENDING) | fee PENDING → CONFIRMED by `finance.confirm_payment` (trigger `deferment_fee_confirmed`) | Student "Your payment is confirmed" and "Your deferment application fee is confirmed" (Email + SMS) | Receipt `RCT-…` (`/student/receipt/{reference}` and `/pdf`) | An expired reference is replaced by a new one; the fee is not refunded; the form stays closed: "the deferment application fee of NGN … is paid before the application form opens" |
| Open / edit | Student (wizard step 1; identity, programme, level and current period read from the record) | a CONFIRMED, unspent fee; the V259 rules (past session, allowance, one live request) | `people.deferment` (`DEF-YYYY-NNNNN`, `fee_id`); events FEE_PAID, CREATED / UPDATED; the fee marked `used_by` | DRAFT | none | — | Editing only in DRAFT / CORRECTION_REQUIRED |
| Documents | Student (step 2; PDF/JPEG/PNG ≤ 5 MB, at most six) | magic bytes, size, count, `DEF_DOC_CLOSED` (DRAFT / CORRECTION_REQUIRED / SUBMITTED only) | `deferment_document` + blob | — | none | — | A desk opens a document **in a modal viewer on the same page** through the authorised door (`…/documents/{doc}/content`, no public URL); each viewing is logged DOCUMENT_VIEWED |
| Submit | Student (step 3, declaration) | reason words, required document, declaration, fee confirmed | `deferment_submit` | DRAFT → SUBMITTED | Student "Your deferment request has been received" (with the Bursary); Bursary email "A deferment request awaits financial verification" | — | — |
| Bursary approves | Bursar (`bursar`; `super`) — **Approve (financial verification done)** | `SUBMITTED` only; office checked in SQL (`people.deferment_office_may`) and at the door | `people.deferment_financials` snapshot recorded: last school-fee payment (amount, reference, date, session), balance and session, officer, note | SUBMITTED → BURSARY_APPROVED | Student "…passed financial verification"; HOD email | — | REJECT (reason required) → REJECTED; CORRECTION (note required) → CORRECTION_REQUIRED; the student's resubmission returns to the Bursary |
| HOD approves | Head of the student's department — **Approve and send to the Faculty** | `BURSARY_APPROVED` only; bound (403 outside) | `dept_at/by/note` | → DEPT_RECOMMENDED | Student; Dean email | — | as above; a correction from here resubmits to the HOD, not the Bursary |
| Faculty approves | Dean or Faculty Officer — **Approve and send to the Academic Office** | `DEPT_RECOMMENDED` only | `fac_at/by/note` | → FAC_RECOMMENDED | Student; Academic Office email "A faculty-approved deferment request is ready to forward" | The application becomes **downloadable** by the Academic Office (`GET /deferments/{id}/application`; before this the API answers 422 `DEF_NOT_DOWNLOADABLE`, the button is absent) | as above |
| Academic Office forwards | Academic Office (`academic`, `registrar`, `dregistrar`, `super`) — **Forward Approved Applications to DVC** (whole list or ticked) | `FAC_RECOMMENDED` members only; "no faculty-approved request is waiting to be forwarded" otherwise; nothing forwarded twice | `people.deferment_batch` (`DEF-DVC-YYYY-NNNNN`, session, semester, date, officer, note, count); `batch_id`, `forwarded_at/by`; event FORWARD | → FORWARDED_TO_DVC | Student "…forwarded to the Deputy Vice-Chancellor"; DVC email "Deferment batch … awaits your decision" | Application PDF (desk copy) | The Academic Office cannot approve on behalf of any desk (`DEF_NOT_YOUR_STAGE`) |
| DVC decides — **final approval** | Deputy Vice-Chancellor (Academic) — **Approve with comment (final approval)** | `FORWARDED_TO_DVC` only; a comment is **required** (`DEF_DVC_COMMENT`) | `dvc_at/by/note` and `decided_at/by/note`; **`people.deferment_apply_effect`** in the same transaction: entries of the period → `status = 'DEFERRED'`, `people.deferred_course` rows (from the registration, else the curriculum's core and GST courses for the level and semester), `extension_semesters` (1 per semester, the session's semesters for a session), `courses_affected`, event EFFECT_APPLIED; then `deferments_tick` | → APPROVED (→ ACTIVE at once if the period has begun) | Student "DEFERMENT APPROVED · DEF-…" with the DVC's comment, the period, the duration, the expected return, the courses affected, the timeline extension and the CGPA guarantee; Registry email "A deferment has been approved by the DVC" | Approval letter PDF | REJECT / CORRECTION as above; if the academic update fails the approval is rolled back with it |
| In force | the clock `DefermentClock` 06:20 Africa/Lagos or `POST /deferments/tick` | APPROVED with `period_from` reached | `prior_status`; status DEFERRED; registration gates hold the period | APPROVED → ACTIVE | Student "Your deferment is now in force" | — | as V259 |
| Confirm return / resumption | HOD, Dean, Faculty Officer or Registry from **Students Due to Resume** (`/deferments/returns`, searched and filtered on the server) | ACTIVE or APPROVED | status restored; event RETURNED naming the deferred courses now due | → COMPLETED | Student "Welcome back…" naming how many deferred courses appear on the form | — | — |
| Deferred courses become due | the registration form (`registration.student_menu`, basis **Deferred**, `deferred = true`, `deferred_from`) | the deferment COMPLETED (or ACTIVE past its return date); the course offered in a later semester; not yet passed | on the draft: `registration.entry` with `entry_type = 'DEFERRED'` (fixed like a carry-over, never called failed; not droppable) | `people.deferred_courses` status DEFERRED → REGISTERED → COMPLETED | — | — | Prerequisites and unit limits apply as to any course; the grade enters the GPA only when a result is published |

**Timeline (`people.programme_timeline`).** Original duration = years from the entry level to the programme's final level × the session's semesters (never overwritten); approved extension = the sum over APPROVED / ACTIVE / COMPLETED deferments; adjusted completion session and semester computed from the entry session; dates from the calendar (`people.period_end`). Rejected, cancelled and unapproved requests extend nothing. Shown to the student, on the review, on the application PDF and in the approval notice.

**Settings.** `people.deferment_setting.fee` is stated by the Bursary on Fee Setup (`PUT /api/v1/deferments/settings`, `bursar`/`super`); the limits (`max_sessions`, `allow_extension`, `reminder_days`, `overdue_after_days`) by the Registry through the same endpoint (no screen yet). Desk exports: branded Excel / PDF (serial DEF, S/N first, names A–Z); the Academic Office's export contains faculty-approved applications only.

> **Planned / Not Yet Implemented:** the approval letter's QR still points to `/verify/deferment/{reference}`, which does not exist; progression beyond the deferred courses being due (level promotion withheld by outstanding deferred courses) is not computed — the roll-over promotes by status, and a student whose deferment is in force is not promoted.

### 7.2 Inter-departmental transfer

Two paths coexist in code; only the four-desk pipeline has screens.

```text
Student /student/transfer → Office /transfers (tabs Current dept / New dept / Registrar / Academic / Completed / Declined)
APPLIED ──fee confirmed + HOD of from_dept──▶ FROM_OK ──HOD of to_dept──▶ TO_OK ──Registrar/Deputy Registrar──▶ REG_OK
 ──Academic Office (fee confirmed)──▶ EFFECTED  (programme_code and level changed on the register; matric number unchanged)
any pending desk ──decline (reason)──▶ DECLINED
legacy committee path (API only): APPLIED → RECOMMENDED | NOT_RECOMMENDED → APPROVED | DECLINED → EFFECTED ; → WITHDRAWN
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Apply | Student ("Apply to transfer": programme, reason, optional UTME score), or Academic Office / Registrar / Deputy Registrar / super "Record an application" for a paper case | `apply_transfer`: "only a matriculated, active student may apply to transfer" (ACTIVE / PROBATION); reason non-blank; target exists, not archived, not the student's own; "a transfer application is already in progress for this student" (23505); the screen shows "Transfers are not open yet" until the Bursary sets `finance.fee_setting.transfer_fee` | `people.transfer_application` (session, from/to programme, level, CGPA from `assessment.student_gpa`, mode of entry) | APPLIED | none | — | — |
| Fee | Student ("Pay the fee online") | `transfer_fee_reference`: "the inter-departmental transfer fee has not been set by the Bursary" (HINT "The Bursary sets it on Finance → Fees…"); the existing reference is reused | `finance.payment_reference` purpose "Inter-departmental transfer to {programme}" | — | the §6.2 payment notice | Receipt | — |
| Current department | HOD of `from_dept` (or super) — "Approve" / "Decline" | `approve_transfer`: "the non-refundable processing fee has not been paid" ("This application is not ready at your desk. Awaiting payment."); `TR_NOT_YOUR_STAGE` | `from_dept_at/by` | APPLIED → FROM_OK | none (**NOT IMPLEMENTED**) | — | Decline with a reason → DECLINED (no payment required to decline) |
| New department | HOD of `to_dept` | stage check | `to_dept_*` | FROM_OK → TO_OK | none | — | decline |
| Registrar | Registrar / Deputy Registrar | stage check | `reg_*` | TO_OK → REG_OK | none | — | decline |
| Academic Office effects | Academic Office | fee confirmed; "application % has no approval pending at this stage (%)" otherwise | `people.student.programme_code`, `current_level = coalesce(recommended_level, current_level)`; `acad_at`, `effected_at/by` | REG_OK → EFFECTED (the student stays ACTIVE; TRANSFERRED_OUT is never set by the pipeline) | none | Approval letter `/student/transfer/letter/{id}` — prints a hard-coded ₦10,000 and Senate/SAIC wording (**PARTIALLY IMPLEMENTED**) | The student's course menu follows the new programme from the next opened registration |

Memo `/transfers/memo?type=recommended|withdrawn` reports on the legacy committee states (`review_transfer`, `senate_transfer`, `withdraw_transfer`, `effect_transfer` — endpoints only, no screen).

### 7.3 Biodata change

`people.biodata_change` runs PENDING → EVIDENCE_ASKED → APPROVED | REFUSED on Biodata Changes `/students/biodata-changes` (Academic Office, Registrar, Deputy Registrar decide with "Approve with evidence", "Refuse" — decision text required, `STU_DECISION_REQUIRED` — and "Ask for evidence"; deciding twice is refused, `STU_CHANGE_DECIDED`; approval writes the value onto `people.biodata`). **The state is unusable: nothing can create a request.** `ref.biodata_field` holds only `open` and `locked` tiers (no `approval` tier), `StudentService.writeBiodata` writes open fields at once and refuses locked ones (`STU_FIELD_LOCKED`), and `StudentRepository.askForChange` is never called, so the queue is always empty (**CONFIGURED BUT UNUSED**). The screen text "the student is notified" is not implemented. Students edit their own open fields on Biodata `/student/biodata`; the Registry edits any open field on Student 360.

### 7.4 Status changes on the register

`people.student.status` (CHECK): ADMITTED, ACTIVE, PROBATION, DEFERRED, SUSPENDED, RUSTICATED, WITHDRAWN, EXPELLED, TRANSFERRED_OUT, GRADUATED, DECEASED, DORMANT, VOLUNTARY_WITHDRAWAL. Every change goes through `people.change_status(student, to, instrument, effective, reason)`, which appends `people.status_change` and refuses a blank instrument: "a change of status is made on an instrument — the Senate minute, the letter, the Registrar's decision — and none was cited". `ck_student_active_has_matric` requires a matriculation number for any status other than ADMITTED, so ADMITTED → ACTIVE cannot be done by hand ("matriculate instead").

| Transition | Made by | Instrument |
|---|---|---|
| ADMITTED → ACTIVE | matriculation run / single issue (§4) | `MAT/YYYY/NNN` |
| → DEFERRED and back | the deferment clock and the return confirmation (§7.1) | `DEF-YYYY-NNNNN` |
| → GRADUATED | `records.approve_awards` (§8), `pg_award` (§3.3), the College Board (§5.6) | the Senate / Board minute |
| → VOLUNTARY_WITHDRAWAL | the Registry's close on `/students` (§5.5) | "University regulation: four consecutive semesters without course registration" |
| → WITHDRAWN | the College Board (§5.6); the PG desk (§3.2) | Board minute / prompted instrument |
| any → any allowed | Academic Office / Registrar / Deputy Registrar, Student 360 → **Change status** (To, Instrument required, Reason) | typed |
| TRANSFERRED_OUT | manual only | typed |

Level correction (Student 360 → **Correct level**, 100–600, reason required) is a plain UPDATE; it writes no `status_change` row. No status change sends a notice.

> **Planned / Not Yet Implemented:** a `/verify/deferment` route for the approval letter's QR; a settings screen for deferment limits and reasons; transfer notices; the transfer letter's fee and wording read from the record; a producer for biodata change requests.

---

## 8. Graduation and documents workflow

```text
Degree audit (finalists) → records.graduand AWAITING (unmet named) → "Send the list to Senate" (minute) → APPROVED · student GRADUATED
 → convocation clearance: 8 units × CLEARED | HELD → clearance.is_clear(student, 'CONVOCATION')
 → digital degree certificate issued (one or in a run) → credentials.issued ACTIVE · CERT/YYYY/NNNNNN
 → transcript / statement requests: wizard → AWAITING_PAYMENT | HELD_AT_CLEARANCE | READY → PROCESSING → GENERATED
   → VERIFIED | CORRECTION | REJECTED → RELEASED (second officer) → DELIVERED → COMPLETED   (CANCELLED early)
 → revoke (REVOKED) · reissue (new version; old REPLACED) · flags on a result or award change
 → public verification VALID | REVOKED | REPLACED | NOT FOUND (| INVALID on a hash mismatch)
```

### 8.1 Degree audit, clearance units and Senate approval

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Run the degree audit | Academic Office, Registrar, Deputy Registrar, Records on Graduation `/graduation` ("Run the degree audit for S") | finalists = `people.enrolment` rows of the session at the final level (600 MBBS; 500 for LL.B / Pharmacy; else 400 — hard-coded); standing from `assessment.course_final` at PUBLISHED | `records.graduand` upsert with `cgpa`, `award` (programme name), `unmet`: "{course} not graded" / "No published result on the record" / "CGPA x — below pass threshold" (< 1.00) | AWAITING | none | Classification summary on screen | Only "every registered course published" and CGPA ≥ 1.00 are checked; the curriculum rules the screen names (core courses, credit minima, GST, project) are **not implemented** |
| Clearance units | eight units sign CLEARED or HELD (naming the item) on Clearance `/clearance?purpose=CONVOCATION`: BURSARY (`bursar`), DEPARTMENT (`hod`), FACULTY (`dean`), LIBRARY (`library`), HEALTH (`services`), HOSTEL (`services`; `housing` also signs, and the hostel clearance writes it automatically — §9), WORKS "Works and Maintenance" (`services`), ALUMNI "Alumni and Convocation" (`registrar`); `registrar`, `dregistrar`, `academic` sign any unit | `unitFor`: "the X clears against its own record; Y does not sign for it"; `CLR_HOLD_NAMES_ITEM` "A hold names the specific item outstanding." | `clearance.item` appended (never updated); `clearance.position` takes the latest per unit | position per unit | none — "Notify held candidates" returns 202 "The notification module is not on the portal yet; nothing was sent." (**PLACEHOLDER**) | Held list CSV | Library and Bursary standing do not sign automatically (**NOT IMPLEMENTED**) |
| Send the list to Senate | Registrar, Deputy Registrar, Academic Office (modal "Senate minute") | `records.approve_awards`: "the graduation list is approved on a Senate minute, and none was cited"; only rows with no `unmet` and a CGPA | `senate_state`, `senate_minute`; `people.change_status(GRADUATED, minute, 'Award approved by Senate')` | AWAITING → APPROVED; student → GRADUATED | Email + SMS "Senate has approved your award" (award, minute, CGPA, class; "Your certificate is printed once every unit has cleared you for convocation…") | — | REFERRED is in the CHECK; nothing sets it; a graduand with an unmet requirement stays AWAITING |
| Alumni | readers on Alumni `/alumni` | `senate_state = APPROVED` | none | — | none | — | The `services` menu lists Alumni but the API denies that office |

### 8.2 Certificate issue

The Documents Office `/credentials/documents` panel "Graduates awaiting a digital certificate" lists graduated, Senate-approved students with no active certificate; **Issue** (single) and **Issue N certificate(s)** (bulk) are for `SIGNERS` = registrar, dregistrar, academic. `credentials.issue_certificate` → `assert_issuable`: "the student record is not GRADUATED", "the award is not Senate-approved", "clearance is incomplete" (HINT "BR-001. No office may clear another office's item."); "an active degree certificate already stands; revoke or reissue it". The bulk run rolls back entirely on the first refusal ("One that fails the checks stops the run"). The issue writes `credentials.issued` (number `CERT/YYYY/NNNNNN`, version 1, Crockford verification code, statement JSON, `content_hash` SHA-256, template version) and tells the student (Email + SMS "Your digital certificate has been issued"). The PDF follows the University's own certificate layout with a QR to `/verify/document/{code}`. A degree certificate cannot be requested by a student ("A degree certificate is issued by the Registry, not requested.").

The printed certificate register (`/credentials/certificates`, numbers `MOAUM/C/YY/NNNNN`, stationery batches, PRINTED → COLLECTED | HELD, REISSUED on a duplicate) is the older V027 register and is kept alongside.

### 8.3 Transcript and statement requests

Policies (`credentials.document_policy`, seeded): DEGREE_CERTIFICATE (CERT, Registry-issued, graduates only); TRANSCRIPT "Official full transcript" (TRN, billable at `finance.transcript_fee(session)`, SLA 5 days); SESSIONAL_TRANSCRIPT (STR, ₦2,000, 3 days); MINI_TRANSCRIPT (MTR, free, self-service, 1 day); ACADEMIC_STATEMENT (ASR, free, self-service, 1 day). Config offices (registrar, dregistrar, academic, super) edit them and put template versions in force on Policies & templates `/credentials/documents/settings`.

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Request (wizard) | Student on My Documents `/student/documents` (document, session/semester, delivery Digital / Physical / Both, copies 1–10, urgent, international, recipient, address, purpose) | `request_document`: "a document is issued against a matriculation number; the record has none yet" (HINT "Matriculation comes first."); "{label} is issued to a graduated student"; "a sessional transcript names its session"; "no published result stands for {session}"; "name the recipient"; "a physical delivery needs an address"; "the same request was made within the day and is still in hand" | `credentials.transcript_request` (ref `TRN-YYYY-NNNNN`, fee = policy fee × copies + urgent + physical + international); a fee > 0 mints the payment reference "Transcript {ref}" | AWAITING_PAYMENT (fee > 0) · HELD_AT_CLEARANCE (full transcript, TRANSCRIPT clearance not clear) · READY | Student Email + SMS "Document request {ref} submitted"; desk email "A document request awaits" (free, non-self-service) | A free self-service kind is generated and RELEASED at once inside the request | Cancel (student or desk) while AWAITING_PAYMENT / READY / HELD_AT_CLEARANCE: "request % is %; it is past cancelling" → CANCELLED, "Document request {ref} cancelled" |
| Payment | Student pays the reference (§6.2) | `finance.confirm_payment` sets `paid_at` → trigger `credentials.request_paid` stamps `sla_due_on` | trail PAID | AWAITING_PAYMENT → READY / HELD_AT_CLEARANCE | (payment notice only) | Receipt | An expired reference shows "Unpaid" |
| Validate | `OFFICE` = academic, registrar, dregistrar, records — "Validate the record" on `/credentials/documents/requests/{id}` | `start_processing`: "request % is not paid; processing begins at payment"; `validate_record` ERRORs (no matric number; programme not on the list; EXPELLED / RUSTICATED; no published result; certificate: not GRADUATED / no Senate award / convocation clearance incomplete; transcript: TRANSCRIPT clearance incomplete) and WARNINGs (unpublished registered courses "issued without them"; not yet graduated; award not APPROVED) | `validation` JSON, `started_at` | READY → PROCESSING | Student "Document request {ref} is being processed" | — | "request % is held at clearance" (HINT a unit holds the candidate) — the desk cannot generate until clear |
| Generate | OFFICE — "Generate the document" (disabled unpaid or with ERROR findings) | `produce_transcript`: "the record does not validate: {errors}" | `credentials.issued` version n (statement from `assessment.student_results` / `student_gpa`, or PG tables), number `PREFIX/YYYY/NNNNNN` | PROCESSING → GENERATED | Student "Document request {ref}: document generated" | Document PDF | — |
| Quality check | OFFICE — Approve / Request correction / Reject (note) | "the quality check approves, asks for a correction or rejects"; "say why"; "request % is %; the quality check is of a generated document" | `qc_*` | GENERATED → VERIFIED / CORRECTION (regenerate → GENERATED as a new version) / REJECTED (closed) | Student "Document request {ref} approved" / "…: correction in hand" / "… rejected" | — | — |
| Authorise and release | SIGNERS other than the producer — "Authorise and release" (disabled for the producer: "The officer who produced a document does not release it") | `release_transcript`: "request % has not been produced and verified"; "the officer who produced a transcript does not sign it" (BR-006) | `released_by/at`; deliveries opened: STUDENT token (50 uses, 30 days), RECIPIENT token (10 uses, 30 days) by email, physical PROCESSING | VERIFIED → RELEASED | Student "Document request {ref}: your document is ready"; recipient "An official document from Rev. Fr. Moses Orshio Adasu University" (secure link `/documents/d/{token}`) | Signed PDF available in the library, to the recipient and to the office | — |
| Deliver | OFFICE updates physical deliveries (DISPATCHED / IN_TRANSIT / DELIVERED / RETURNED with courier and tracking); tokens mark DELIVERED when spent; "Resend link" (`DOC_RESEND` "Only a digital delivery to an email address is resent.") | — | `credentials.delivery`, `download_token`, `download_log` | RELEASED → DELIVERED when every delivery is DELIVERED or the student's token is spent | "Document request {ref} delivered"; on FAILED / RETURNED: student "Delivery of {ref} failed" and desk "A document delivery failed"; "(resent)" to the recipient | — | An exhausted or expired link: the student makes a new secure link (20 uses, 1–90 days) or the desk resends |
| Complete | OFFICE — "Mark completed" | "request % is %" | `completed_at` | RELEASED / DELIVERED → COMPLETED | none | — | — |

The legacy transcript queue (`/credentials/transcripts`) still moves READY → GENERATED → VERIFIED in one click ("Produce & verify") and then "Sign & release" by a signer; its "View verification" button does nothing, and raising a request on a student's behalf has an endpoint without a screen.

### 8.4 Revoke, reissue, flags

| Act | Who | Rule | Effect | Notice |
|---|---|---|---|---|
| Revoke | `REVOKERS` = registrar, vc, on Issued documents `/credentials/documents/register` (Reason and Instrument required; `ck_revoke_office`) | "document % is already revoked" | `credentials.revocation`; document ACTIVE → REVOKED; every token revoked; the PDF prints a diagonal REVOKED watermark | Student Email + SMS "A document of yours has been revoked" |
| Reissue | SIGNERS (reason) | "a reissue carries its reason"; "document % has already been replaced" | a new version with the same number (`uq_issued_number` on number + version); old row → REPLACED (verifies REPLACED, prints REPLACED); its flag cleared, tokens revoked; the request's `issued_id` moves to the new version | Student "A document of yours has been reissued" |
| Flag on a result change | trigger `trg_score_flags_documents` on `assessment.score` INSERT/UPDATE | flags the student's active transcripts and statements "A result of the student changed after issue" | `flagged_at`, `flagged_reason` | desk email "An issued document may need review" |
| Flag on an award change | trigger `trg_graduand_flags_documents` on `records.graduand` (cgpa, award, session) | "The award on the record changed after issue" on certificates and transcripts | as above | as above |
| Clear the flag | OFFICE | — | `flagged_at` cleared | none |

### 8.5 Public verification

`/verify/document?key=` or `/verify/document/{key}` (public; 40 lookups per 15 minutes per IP — `VERIFY_THROTTLED` "Too many verifications from this source; try again in a few minutes."): the key is matched first as a verification code, then as a document number (latest version). Answers: **VALID DOCUMENT — authentic and currently valid**; **REVOKED — this document was officially revoked** (date, instrument); **REPLACED — a later version of this document is the official one**; **NOT FOUND — no document bears this reference**; **INVALID — the document could not be validated** (the stored SHA-256 hash no longer matches the statement). Only the policy's `public_fields` are shown ("Never shown: date of birth, address, phone, email, finances, internal identifiers. Results are never on the public page."). Every lookup is logged (`credentials.verification`); NOT_FOUND keys are counted as suspected forgeries after three lookups in 30 days. The secure link `/documents/d/{token}` spends a use on the page and again on the PDF, and answers "This link has expired" / "…used the permitted number of times" / "The document is revoked|replaced" / "This link is not valid".

> **Note:** the document "signature" is a SHA-256 hash of the statement — the University holds no signing key (`credentials.signing_key` is empty). A document is tamper-evident against the University's own store only; there is no offline cryptographic verification.

### 8.6 Identity cards

`credentials.issue_identity_card` (Library and Security, `ISSUERS`, on Card Printing / Card Collection `/credentials/idcards`): "an identity card is keyed on the matriculation number, and % has none yet" (HINT "The card is made after matriculation."); "the Bursary has not cleared this student for the identity card in {session}" (HINT "The scheme releases the card at the first instalment."); number `MOAUM/ID/YY/NNNNN`, valid four years; ISSUED → LOST (report) | REPLACED; one live card per student. The student prints the card from Identity Card `/student/idcard` (PDF, barcode, no QR; blood group and "Graduates" print "—"). No collection record and no card verification exist ("Verify a Card" is a menu item with no URL — **PLACEHOLDER**). The staff card PDF is stateless (nothing is stored).

### 8.7 What is not implemented

| Item | Status |
|---|---|
| Curriculum rules in the degree audit; configurable final level | PARTIALLY IMPLEMENTED |
| REFERRED graduand state | CONFIGURED BUT UNUSED |
| "Notify held candidates" on clearance; automatic clearance from Library / Bursary standing | PLACEHOLDER / NOT IMPLEMENTED |
| Cryptographic signing and offline verification | NOT IMPLEMENTED |
| Legacy queue "View verification"; screen to raise a transcript request on a student's behalf; stationery "return" button; printed certificate REVOKED status | PLACEHOLDER / PARTIALLY IMPLEMENTED |
| Identity card collection record and verification page | NOT IMPLEMENTED |
| Courier integration (tracking is typed) | NOT IMPLEMENTED |

---

## 9. Hostel workflow

```text
Navigation: housing — Students → Hostel Dashboard /hostel · Application Window & Rules /hostel/window · Hostel Inventory /hostel/inventory
            · Applications & Waitlist /hostel/applications · Occupancy & Check-in /hostel/occupancy · Checkout & Clearance /hostel/clearance
            services — Hostel Accommodation /hostel ;  student — Services → Hostel /student/hostel ;  public /verify/hostel/{ref}

window:      DRAFT → OPEN → CLOSED → ALLOCATED
application: APPLIED → ALLOCATED → CONFIRMED | LAPSED | UNSUCCESSFUL | WITHDRAWN | REJECTED
allocation:  HELD (fee > 0) | CONFIRMED (fee = 0) → CONFIRMED → ACCEPTED → CHECKED_IN → CHECKED_OUT
             side exits DECLINED · LAPSED · CANCELLED · TRANSFERRED (old row on a move)
transfer request: SUBMITTED → UNDER_REVIEW → APPROVED | REJECTED → COMPLETED
clearance:   PENDING → CLEARED | NOT_CLEARED (→ PENDING on reopen)
maintenance: RAISED → ASSIGNED → FIXED → CLOSED
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Inventory | `OFFICE` = services, housing, registrar, admin, super on `/hostel/inventory` | hall code `^[A-Z0-9]{2,8}$`; room beds 1–12 (beds numbered on save; surplus beds OUT_OF_SERVICE); "Generate at most five hundred rooms in a run…"; closing needs a reason ("say why it is closed") and lists affected occupants | `hostel.hall`, `block`, `room`, `bed` (a bed is a row), `asset`, `room_facility` | hall/block ACTIVE / CLOSED; room AVAILABLE / MAINTENANCE / CLOSED / RESERVED | none | Excel / PDF Hostel Inventory, Bed list (serial HST) | No hall is seeded |
| Window and rules | OFFICE on `/hostel/window` | "State the accommodation fee for the session." ("Zero is a fee; blank is not."); hold hours 1–720 (default 72); method BALLOT / FIRST_COME / LEVEL / FACULTY / PROGRAMME / SPECIAL_NEEDS / MANUAL; eligibility (statuses, levels, faculties, hall kinds, registration submitted, no hostel debt); a rules-text change makes a new `rules_version` | `hostel.session_setting` | DRAFT → OPEN → CLOSED | Every eligible student Email + SMS "Hostel applications are open" (when ≤ 5,000 eligible) | — | — |
| Apply | Student on `/student/hostel` (hall, room type, block, priority category with what it rests on, special need, roommate) | `hostel.eligibility` reasons ("A student whose status is {x} is not eligible"; "{L} Level is not eligible this session"; "Course registration for {s} has not been submitted"; "An unsettled hostel damage charge of NGN {x} stands"; "A previous stay was not cleared"; "The student is still checked in to a room of another session"); "applications for % are draft|closed"; "the draw for % has been run; applications are closed"; "an application for % already stands"; "the application window for % is full"; roommate checks (`HOSTEL_ROOMMATE` "No student carries the number X.") | `hostel.application` (`HST-YYYY-NNNNN`); `review = 'APPROVED'` at once when the window does not require review | APPLIED | Student "Your hostel application is in"; desk "A hostel application awaits review" (when review is required) | — | Withdraw (reason) → WITHDRAWN; "a student checked in leaves by checkout, not by withdrawing the application" |
| Review | OFFICE on `/hostel/applications` (Approve / Reject / Waitlist / Correction, singly or in bulk) | "a review approves, rejects, waitlists or asks for a correction"; "say why" (REJECTED / CORRECTION); "application % is %; the review is over" | `review`, `review_note` | REJECTED ends it; WAITLISTED → UNSUCCESSFUL; CORRECTION keeps APPLIED | Student "Your hostel application is approved" / "…was not approved" / "…is on the waiting list" / "…needs a correction" | Excel / PDF Hostel Applications (17 columns) | A REJECTED application cannot be seated ("application % was rejected at review"); after CORRECTION the student withdraws and applies again |
| Allocation run | OFFICE — "Generate Allocation" (modal; BALLOT needs a published seed ≥ 6 chars) | "allocation for % is manual: seat each student from the applications desk"; "the draw runs from a published seed of at least six characters"; "the draw for % was run on % from seed %" (runs once); "no bed is free to allocate"; unreviewed applications are not seated when review is required | priority categories first, then the method's order; `pick_bed` prefers hall, room type and block asked for; `hostel.allocation` (`ALC-YYYY-NNNNN`, basis PRIORITY / BALLOT / RESERVE, `held_until`); losers UNSUCCESSFUL with a draw position | window → ALLOCATED; application → ALLOCATED; allocation HELD (or CONFIRMED when the fee is 0) | Student "You have been allocated a bed" / "Your hostel application is on the waiting list" | — | — |
| Manual seating | OFFICE — "Allocate" (free bed, reason) | `hostel.hold`: "application % has not been approved at review"; "bed % of room % is already taken"; "hall % is not for this student"; "the student already holds a bed for %"; "a manual allocation carries its reason" | as above | as above | "You have been allocated a bed" | — | — |
| Hold and lapse | the clock `HostelClock` hourly at minute 5 (`moaum.hostel.cron`), or "Lapse expired holds" | `held_until = allocated + hold_hours` passed | `hostel.lapse_holds`: allocation LAPSED; with `waitlist` on, the bed is offered as RESERVE to the next UNSUCCESSFUL applicant of a compatible sex by draw position | HELD → LAPSED; next applicant → ALLOCATED / HELD | "Your hostel hold has lapsed"; next student "A hostel bed has been offered to you" | — | An ineligible reserve is skipped silently |
| Fee | Student "Pay ₦… now" (`hostel.new_fee_reference`), confirmed through `finance.confirm_payment` → `hostel.confirm_by_reference` | "no bed is held against this application"; "this allocation is already paid and confirmed"; "the hold on this bed expired at %"; on late money: "the hold on this bed lapsed before the payment arrived, and the bed went to the next name on the draw" (HINT the Bursary refunds or applies it) | `allocation.reference`, `confirmed_at` | HELD → CONFIRMED; application → CONFIRMED | Payment notice (§6.2); desk "A hostel fee has been confirmed" | Receipt | — |
| Accept under the rules | Student ("Accept allocation" with the rules acknowledgement; needed only when rules text exists) | "the accommodation fee is paid before the allocation is accepted"; "the hostel rules (version %) are acknowledged before the allocation is accepted" | `accepted_at`, `rules_version` | CONFIRMED → ACCEPTED | "Your hostel allocation is accepted" | Allocation letter PDF `/student/hostel/letter` (409 "The letter is issued once the accommodation fee is confirmed." while HELD) with QR → `/verify/hostel/{ref}` | Decline (reason) from HELD / CONFIRMED / ACCEPTED → DECLINED; desk "A hostel allocation was declined", student "Your hostel allocation is declined" |
| Check-in | OFFICE on the allocation page (condition, remarks) | "the accommodation fee is not confirmed; nobody checks in on a hold"; "the student accepts the allocation under the hostel rules before checking in" | CHECKIN inspection; `checked_in_at` | → CHECKED_IN | "You are checked in" | Porter verifies the letter at `/verify/hostel/{ref}` (photo, placing, state) — no token and no rate limit | Cancel (desk, reason) from any live state not CHECKED_IN → CANCELLED, "Your hostel allocation is cancelled" |
| Transfer | Desk move ("Transfer": free bed, reason) or student request (hall, room type, reason) decided by the desk ("Approve and move" with a bed / "Reject" with a reason) | "a transfer carries its reason"; "that is the bed the student already holds"; "a transfer is asked for from a confirmed room"; "a transfer request is already waiting"; "name the bed the student moves to"; "say why the transfer is refused" | old row TRANSFERRED; new row with `moved_from` carrying payment, acceptance and check-in state | request SUBMITTED → APPROVED → COMPLETED / REJECTED | "Your hostel room has changed"; desk "A room transfer is requested"; "Your transfer request was not approved" | — | CANCELLED request state is never set |
| Maintenance | Student raises (category, urgency, what is wrong); desk updates (RAISED / ASSIGNED / FIXED / CLOSED, assigned-to free text, note) | "No room stands against you this session." / "The bed is held, not yet yours; pay the fee first."; "A request is raised, assigned, fixed or closed." | `hostel.maintenance_request` | as stated | desk "A hostel maintenance request"; student "Your maintenance request is fixed|closed" | — | — |
| Checkout inspection and damage charge | Student "Request checkout" (date, reason); OFFICE "Checkout inspection" (condition, cleanliness, keys, access card, damages) and "Raise a damage charge" (asset, damage, costs, charge) | "checkout follows check-in; the student is %"; "say what was damaged"; "a charge is an amount, zero or more" | CHECKOUT inspection opens the clearance (`HCL-YYYY-NNNNN`) with KEY / ACCESS CARD / ROOM / BED / ASSETS / NO_DAMAGE pre-answered; a charge > 0 mints a payment reference "Hostel accommodation damage {ref} {id}" and marks the asset DAMAGED; zero is settled at once; waiver needs a reason | clearance PENDING | "Your hostel clearance has started"; "A hostel damage charge stands against you"; desk "A checkout is requested" | — | "the charge is already settled" on a second waiver |
| Clearance | OFFICE decides each of the nine requirements (Clear / Hold / Waive / N/A; remarks for NOT_CLEARED / WAIVED); "Complete clearance" | "% requirement(s) still pending"; FEES_SETTLED and DAMAGE_CHARGES_SETTLED pre-answered from payments (a paid damage charge marks its item CLEARED) | on CLEARED: allocation → CHECKED_OUT, bed released, a CLEARED HOSTEL item written to `clearance.item` for CONVOCATION; on NOT_CLEARED: a HELD HOSTEL item naming the outstanding requirements | PENDING → CLEARED / NOT_CLEARED; "Reopen" ("only a clearance found wanting is reopened") → PENDING | "Your hostel clearance is complete" / "Your hostel clearance has outstanding items" | Clearance certificate PDF `/student/hostel/clearance` (409 until CLEARED) with QR | — |

Every act is in `hostel.event` (written once: "the accommodation trail is written once; it is not edited"). Officers act University-wide; there is no hall scope.

> **Warning:** `/api/v1/verify/hostel/{ref}` is public, carries no check token and no rate limit, and the `ALC-YYYY-NNNNN` reference is sequential — names, photographs and room numbers can be enumerated. See *03 Technical Documentation*.

> **Planned / Not Yet Implemented:** verification of a claimed priority category against a rule (the desk reviews it by hand); an artisan register for maintenance assignment; the CANCELLED transfer state; a button for `POST /api/v1/hostel/lapse-all`.

---
## 10. ICT help desk, Help & Requests, clinic visit

### 10.1 ICT Support Desk tickets (V251)

```text
Navigation: student / pgstudent — Services → ICT Support Tickets /tickets ; every staff office — Me → ICT Support Tickets /tickets
            ictagent — ICT Support Desk /helpdesk (home) ; ict / admin / super — ICT Support Desk · ICT Support Reports · ICT Support Settings
            public — Track an ICT Support Ticket /track

SUBMITTED ──first read by an agent──▶ OPENED ──Start Work──▶ IN_PROGRESS ──Resolve (summary + details)──▶ RESOLVED
RESOLVED ──requester confirms | agent "Close as Resolved" | auto-close after N quiet days──▶ CLOSED
RESOLVED | CLOSED ──reopen (reason)──▶ REOPENED ──Start Work──▶ IN_PROGRESS
any open ──requester withdraws | agent "Close on a Reason"──▶ CLOSED
```

| Stage | Who starts / acts | Precondition / validation | Data created / changed | Status change | Notification | Document generated | On rejection / return / lapse |
|---|---|---|---|---|---|---|---|
| Create | any signed-in student or member of staff (applicants excluded) on Submit a ticket `/tickets/new` (category with its own fields, subject, description, up to five attachments at submission) | `helpdesk.submit`: "that category is not open for new tickets"; "a ticket has a subject"; "a ticket describes the problem"; "a ticket carries an email address the desk can reach"; "{label} is required for a {category} ticket"; "ten tickets are open already"; `HELPDESK_NOT_A_MEMBER` "Tickets are raised by students and members of staff signed in to the portal."; attachments PDF/JPEG/PNG ≤ 5 MB, sniffed (`HELPDESK_FILE_TYPE`) | `helpdesk.ticket` (number `TICK-YYYY-NNNNN`, five random digits, never reused; priority = the category's suggested priority; requester kind STUDENT / STAFF with contact as the account holds it), `ticket_attachment`, event SUBMITTED | SUBMITTED | Requester Email "ICT Support Ticket Received — {n}"; every agent + Director "New ICT support ticket {n} — {category}" when `notify_agents_on_new` | — | — |
| Open on read | the first agent (`AGENTS` = ictagent, ict, admin, super) to open `/helpdesk/tickets/{id}` | — | `opened_at/by`; event OPENED | SUBMITTED → OPENED | Requester "Update on your ICT support ticket {n}" | — | — |
| Assign / take / reassign | agent ("Take" from the queue, "Accept the Ticket", "Assign to an Agent") | "a closed ticket is not assigned" (HINT "Reopen it first."); "only an ICT Support Agent or the Director of ICT takes a ticket" (`helpdesk.is_agent`); "the ticket is with that agent already" | `assigned_to`; event ASSIGNED / REASSIGNED | unchanged | Agent "Ticket assigned to you — {n}" / "Ticket reassigned to you — {n}" | — | — |
| Notes and updates | agent ("Internal Note" / "Update to the Requester", attachments marked internal); requester ("Add an update for the desk") | "an update says something"; "a closed ticket takes no more updates" (requester); ≤ 10 attachments ("ten attachments are on the ticket already") | `ticket_comment` (internal only for AGENT), events INTERNAL_NOTE / UPDATE / ATTACHMENT; `first_response_at` on the first non-internal agent comment | unchanged | Requester "The ICT desk has an update on {n}"; agent / desk "Update from the requester — {n}" | — | Requesters never see internal notes or internal files |
| Start work | agent | OPENED / REOPENED → IN_PROGRESS only ("a ticket does not go from {a} to {b} this way") | `in_progress_at`; `first_response_at` if unset | → IN_PROGRESS | Requester "Update on your ICT support ticket {n}" | — | — |
| Escalate / priority | agent ("Escalate to" another agent, Director first; reason ≥ 5) ; priority select | "a closed ticket is not escalated"; "a ticket is escalated to an ICT Support Agent or the Director of ICT"; "a ticket is escalated to someone else"; "an escalation says why"; `HELPDESK_PRIORITY` "A priority is low, normal, high or urgent." | `escalated_to/at/why`; events ESCALATED / PRIORITY_CHANGED (escalation records a person; it does not change assignment) | unchanged | The person escalated to "Ticket escalated to you — {n}" | — | — |
| Resolve | agent ("Resolve": summary 5–300 chars, details 20–8000) | `helpdesk.resolve`: "a ticket is resolved from in progress; this one is …" (HINT "Start work on it first."); "a resolution says what was done" | `resolution_summary/details`, `resolved_at/by`; event RESOLUTION | IN_PROGRESS → RESOLVED | Requester "Your ICT support ticket is resolved — {n}" | — | — |
| Confirm / reopen | requester ("Confirm Resolution" / "Reopen Ticket" with a reason ≥ 5); agent may reopen RESOLVED or CLOSED with a reason | `HELPDESK_NOT_RESOLVED` "Only a resolved ticket is confirmed."; "reopening a ticket says what is still wrong" | `closed_at/by/by_kind = REQUESTER`, reason "The requester confirmed the resolution"; or `reopen_count + 1`, event REOPENED | RESOLVED → CLOSED; RESOLVED / CLOSED → REOPENED | Closed: requester "Your ICT support ticket is closed — {n}"; reopened: assigned agent (else every agent) "Ticket reopened — {n}" | — | — |
| Close by the desk / withdraw | agent ("Close as Resolved" from RESOLVED; "Close on a Reason" from any open state, reason ≥ 5); requester ("Close This Ticket", "Withdrawn by the requester") | "a closure by the desk records its reason" | `closed_*`, `by_kind` AGENT / REQUESTER; event CLOSED | → CLOSED | Requester "Your ICT support ticket is closed — {n}" | — | — |
| Auto-close | `AutoCloser` (every hour after a 5-minute start delay; ≤ 200 tickets a run; audit office `ict`) | only when the Director sets "Close a resolved ticket automatically after N days" (1–90) on ICT Support Settings `/helpdesk/settings`; **shipped default NULL = off** | reason "Closed automatically: N day(s) passed after the resolution with no reply from the requester"; `by_kind` SYSTEM | RESOLVED → CLOSED | Requester "Your ICT support ticket is closed — {n}" | — | — |
| Track (public) | anyone on `/track` (ticket number + email) | exact number and case-insensitive email; 12 lookups per 15 minutes per IP and per email (`HELPDESK_TRACK_SLOW_DOWN` "Too many lookups in a short time…"); 404 "No ticket with that number was raised with that email address." | none | — | none | — | returns no names, attachments, internal events, assignment or priority events |

SLA (`helpdesk.sla`, editable by the Director): LOW 72 h first response / 240 h resolution; NORMAL 24 / 120; HIGH 8 / 48; URGENT 2 / 24 ("The resolution time is at least the first-response time."). The desk flags "Overdue" and "No response yet"; ICT Support Reports `/helpdesk/reports` downloads a plain CSV (not the branded Excel). Categories (11 seeded: PAYMENT, LOGIN, REGISTRATION, RESULTS, EXAMINATIONS, PORTAL, EMAIL, ACCOUNT, NETWORK, GENERAL, OTHER) are deactivated, never deleted; the history is written once ("the ticket history is written once; nothing on it is changed or removed"). All notices are email only. A satisfaction rating is **NOT IMPLEMENTED** — the requester's choice to confirm or reopen is the only feedback.

### 10.2 Help & Requests (service requests to an office)

A student's one-line request to one of eight offices — Registry, Bursary, ICT, Library, Student Services, Academic Office, "My department" (`hod`), Housing — with optional detail and up to six documents (PDF/JPEG/PNG ≤ 2 MB), raised on Help & Requests `/student/support` and answered on the office desk `/support` (which appears in **no office menu**; open it by URL — **PARTIALLY IMPLEMENTED**).

| Stage | Who | Rule | Status | Notice |
|---|---|---|---|---|
| Raise | Student | `platform.raise_request`: office in the eight codes; "say what the problem is, in one line"; "five requests are open already; wait for an answer before raising another"; reference `SR-YYYY-NNNNN`; documents "a request carries at most six documents" | OPEN | none to the office |
| Answer | the addressed office (registrar, bursar, ict, library, services, academic, hod, housing; admin, super and ict see every office's) — "Answer and resolve" / "Answer, keep open" | `platform.answer_request`: "an answer says something" | OPEN → RESOLVED, or WITH_OFFICE (answered, left open) | Student Email + SMS "Your request {ref} is resolved" / "Your request {ref} has an answer" |

CLOSED is in the CHECK but nothing sets it; there is no student reply ("The student may write back" is label text — **NOT IMPLEMENTED**); an HOD sees every request addressed to "hod", not only their department's; nothing reminds an office of an unanswered request.

### 10.3 Clinic visit (University Health Services)

The clinic desk `/clinic` is worked by Support Services (`services`) and super; there is no dedicated clinician office.

```text
appointment: BOOKED ──arrival──▶ SEEN | CANCELLED (student)   (MISSED never set)
visit:       WAITING ──"See now"──▶ IN_CONSULTATION ──"Conclude the visit"──▶ DONE   (LEFT never set)
```

| Stage | Who | Rule | Data | Notice |
|---|---|---|---|---|
| Book | Student on Health `/student/health` | "say why you want to be seen"; "choose a time ahead"; "an appointment already stands; cancel it before booking another" | `health.appointment` BOOKED | none |
| Arrive / walk in | Clinic ("Patient arrives": number, presenting complaint, triage URGENT / STANDARD / ROUTINE; or "Arrived" on a booking) | `HLT_NO_PATIENT` "No student carries the number X."; "the patient is already on the waiting list"; `HLT_TRIAGE` | `health.visit` WAITING; a booking becomes SEEN | none |
| See | Clinic ("See now") | "visit % is not waiting"; the opening is logged against the clinician in `health.record_access` and shown to the patient | visit IN_CONSULTATION | none |
| Conclude | Clinic (Outcome required — what the patient sees; Referred to; Fitness FIT / UNFIT / FIT_WITH_CONDITIONS; Clinical note — never leaves the clinic) | "a visit is concluded with its outcome"; "visit % is not open"; `HLT_FITNESS` | visit DONE; `health.profile.fitness` upserted (read by the Registry through `health.fitness_of`) | none |

Consent to blood group, genotype and allergies is given or restricted by the student. Pharmacy stock, dispensing, prescriptions, laboratory, medical certificates, notices and exports are **NOT IMPLEMENTED** (the desk says so: "Pharmacy stock is not on the portal").

---

## 11. Human resources and expenditure workflows

These modules are engines with maker–checker rules and audited trails, but several lack the data feed that would make them operational. Each carries its PARTIAL note.

### 11.1 Staff movements

```text
hrm.movement: REQUESTED ──approve (second person)──▶ APPROVED ──issue──▶ IMPLEMENTED      REQUESTED ──decline (why)──▶ DECLINED
```

| Stage | Who | Rule | Data / effect | Notice |
|---|---|---|---|---|
| Raise | HRM (`hrm`), Registrar, super on Open a Movement `/hr/movements` (staff number, kind — 17 kinds from APPOINTMENT to DISMISSAL — effective date, what changes, reason, new grade/step) | "no employment on record for this person" — so an APPOINTMENT movement cannot create a new employee | `hrm.movement` REQUESTED | none |
| Approve / decline | hrm, registrar, dregistrar, vc, dvc, super | a second person; decline with why | APPROVED / DECLINED | none |
| Issue | hrm, registrar, super | instrument `MOAUM/R/ACA/YYYY/NNNN` minted on issue | PROMOTION / UPGRADING / CONVERSION change grade and step; RETIREMENT / RESIGNATION / DISENGAGEMENT / DISMISSAL end the employment; SUSPENSION suspends; REINSTATEMENT reactivates → IMPLEMENTED | none; no letter document is generated (the instrument is a reference string) |

RETURNED is in the CHECK; nothing sets it. **PARTIAL:** nothing in the API or migrations inserts `hrm.employment` — only the demo seed — so real staff are on the establishment only if seeded; the non-academic upload creates person + `staff_record`, not an employment.

### 11.2 Leave

`hrm.leave_request`: REQUESTED → APPROVED | DECLINED (note required) by hrm, hod (own department by `staff_record.home_department`), dean, dregistrar, registrar, audit, admin, super on Leave Requests `/hr/leave`; REQUESTED / APPROVED → CANCELLED by the requester only, on Leave & Payslip `/me`. Rules: "only a serving member of staff may request leave" (an ACTIVE employment); "a leave request is already awaiting a decision"; "ANNUAL allows at most 30 day(s); this request is N day(s)"; "the annual-leave balance does not cover N days" (entitlement derived, never stored; types seeded ANNUAL 30, CASUAL 7, SICK 14, MATERNITY 112, PATERNITY 14, COMPASSIONATE 7, EXAMINATION 14, STUDY_PAID 1095, LEAVE_ABSENCE 365). No notice on any decision. **PARTIAL:** an HOD's list is empty until `staff_record.home_department` is populated by the teaching-staff import.

### 11.3 Pay run

```text
hrm.pay_run: DRAFT ──approve (a different HRM officer)──▶ APPROVED ──pay──▶ PAID      DRAFT | APPROVED ──cancel (why)──▶ CANCELLED
```

| Stage | Who | Rule | Data | Notice / document |
|---|---|---|---|---|
| Build | hrm, super on Payroll `/payroll` (period `YYYY-MM`, note) | "a pay run for {Month YYYY} already exists" (one non-cancelled run per month); only ACTIVE employments are paid | `hrm.pay_run` DRAFT, `payslip` snapshots: gross = basic + housing + transport + other; pension 8 % of (basic + housing + transport); PAYE monthly through the bands (7/11/15/19/21 %, then 24 %) after pension and CRA; net = gross − pension − PAYE; other deductions always 0 | none |
| Approve | a different hrm / super officer | "the officer who built a pay run does not approve it" | APPROVED | none |
| Pay | hrm, super | from APPROVED | PAID; payslips visible to staff on `/me` (`GET /me/payslips`, APPROVED / PAID runs only) | no payslip PDF exists |
| Variance | readers on Payroll Variance `/payroll/variance` | — | JOINED / LEFT / CHANGED / SAME rows | — |

**PARTIAL:** no screen adds staff to the establishment, sets bank details or edits grades (`hrm.grade` is seeded: CONTISS 6/7/9/13/15, CONUASS 1/3/5/7); no loans or union dues; no payslip PDF. Recruitment (vacancies OPEN … CLOSED, applicants APPLIED … APPOINTED) has free-form states and no link from APPOINTED to an employment; appraisal (SELF / SUPERVISOR / MODERATED per cycle, promotion eligibility ≥ 3 years on grade) is recorded per person and cycle.

### 11.4 Payment vouchers (BR-006)

```text
expenditure.voucher: WITH_DIRECTOR ──audit──▶ WITH_DEPUTY ──deputyaudit──▶ WITH_AUDITOR ──audit | deputyaudit──▶ CLEARED ──Bursary pays──▶ PAID
                     any non-final ──reject (why)──▶ REJECTED ;  an open query blocks advance and pay
```

| Stage | Who | Rule | Data | Notice |
|---|---|---|---|---|
| Raise | Bursar / super on Payment Vouchers `/vouchers` (title, kind, source, cost centre, payee, amount) | — | `expenditure.voucher` `PV/YYYY/NNNN` WITH_DIRECTOR | none |
| Advance | the desk's office (SQL check: WITH_DIRECTOR needs `audit`, WITH_DEPUTY `deputyaudit`, WITH_AUDITOR `audit` or `deputyaudit`; super bypasses) | "no person acts twice on a voucher (BR-006)" — the raiser and anyone already in `voucher_act` cannot advance; "this desk is signed by audit , not by <office>"; "a query stands against PV/… and it cannot move until answered" | `voucher_act` appended | none |
| Query / answer | audit, deputyaudit, super raise (finding, sent to); bursar, audit, deputyaudit, super answer | — | `voucher_query` | none |
| Pay | Bursar / super | only when CLEARED ("a voucher is paid by the Bursary") | PAID; budget: committed at clearance, spent at payment | none |
| Reject | audit, deputyaudit, super | why required; not from PAID / REJECTED | REJECTED | none |

### 11.5 Requisitions, tenders, stores

- **Requisition** (`RQ-YYYY-NNNN`): RAISED (bursar, ict, registrar, hrm, dean, super) → APPROVED by a different person (`ck_rq_two_people`; "This requisition cannot be approved by you." — remedy "A requisition is approved by a second officer, and only while it is raised.") → PO_RAISED → CLOSED; RAISED → REJECTED (why). The procurement method follows the value: QUOTATION < ₦2.5m, RESTRICTED_TENDER ≤ ₦25m, else OPEN_BIDDING. No purchase-order document is produced. **PARTIAL:** hod and services are routed to `/finance/requisitions` by their menus but are in neither RAISERS nor READERS (403 on the data calls).
- **Tender** (`TN/YYYY/NNNN`): ADVERTISED → EVALUATED (first bid scored) → AWARDED; ADVERTISED / EVALUATED → CANCELLED (why). A bid is responsive when its technical score meets the threshold (default 70) unless overridden with a reason ("a bid found not responsive carries the reason it failed"); award only to a responsive bid; "a lower responsive bid exists; the award records why it is not taken". Bursar / super write; no notices.
- **Stores and assets** (`/stores`, `/audit/assets`): items with reorder levels and signed adjustments (quantity ≥ 0 by CHECK); assets with condition GOOD / FAIR / POOR / DISPOSED and a verification date stamped by bursar, audit, deputyaudit, super. **PARTIAL:** library and services are routed to Stores by their menus but are not in the stores READERS; the audit Assets Register page is table-only although the verify endpoint exists.
- **Research grants** (`expenditure.research_grant`, PROPOSED / ACTIVE / COMPLETED / CLOSED / SUSPENDED): endpoints only — no page calls them (**PARTIALLY IMPLEMENTED**).

No expenditure or HR workflow queues a notice.

---

## 12. Identity workflows

### 12.1 Account creation and office grant (staff)

```text
Users & roles /people (super, ict, admin; grants also registrar, dregistrar, vc)
 New person ──▶ iam.person ──Create account──▶ iam.credential (must_change) ──Grant an office──▶ iam.office_assignment (instrument, scope, dates)
 ──End (date, reason)──▶ valid_to set (never deleted)
```

| Stage | Who | Rule | Data | Notice |
|---|---|---|---|---|
| New person | registrar, dregistrar, hrm, ict, admin, super ("+ New person": surname, given names, optional staff number `MOAUM/STF/…`, email, phone) | `iam.person.staff_number` UNIQUE (409 `ALREADY_EXISTS`) | `iam.person` | none |
| Contact | same ("Contact": email, phone) | — | `iam.person.email / phone` — where a reset link and notices go | none |
| Create / reset credential | registrar, dregistrar, ict, admin, super ("Create account" / "Reset password": username = staff number or email, first password ≥ 10) | `AUTH_USERNAME` "A username is the staff number or an email address."; `AUTH_USERNAME_TAKEN` "'x' already signs somebody else in."; `AUTH_PASSWORD_SHORT` (≥ 10); `AUTH_PASSWORD_IS_USERNAME` | `iam.credential` (bcrypt cost 12, `must_change = true`), `credential_event` SET / RESET; a reset clears the lockout | none — the first password is told to the person out of band |
| Grant an office | registrar, dregistrar, vc, super, ict, admin ("Grant an office": office, "Bounded to" from `ref.office.scope_kind`, "Which one", From, To, "Authority for the grant") | `IAM_NO_SUCH_OFFICE`; `IAM_GRANT_NEEDS_INSTRUMENT` "An office is held under a letter or minute; none was given."; scope kind in institution / college / faculty / department / programme / course / unit / platform / level; `ck_grant_dates`; the MBBS Coordinator guard ("the MBBS Coordinator is held by level: 200, 300, 400, 500 or 600"; the person must already hold a lecturer office in a College department) | `iam.office_assignment` (grantor = the acting person) | none; the grant takes effect at the person's next sign-in |
| End a grant | same ("End": date, reason) | `iam.end_grant`: "an office is ended with the reason on the record, and none was given"; "no live grant <id>" | `valid_to` set; never deleted | none |
| Bulk onboarding | super, ict, admin on Upload Lecturers `/people/lecturers` (person + sign-in `P<PNO>` as username and first password + lecturer office at the home department + establishment record; idempotent); registrar, dregistrar, hrm, ict, admin, super on Upload Non-Academic Staff `/people/staff` (dry run, then load; person + `staff_record` only — no sign-in, no office) | "That file needs PNO, Full Names and Department columns."; departments must exist ("Create these departments first, then re-upload"); unplaced unit spellings reported | as stated | none |

Scope is not in the token; `shared/OfficeScope` binds department offices (hod, exams, siwes, lecturer) and faculty offices (dean, facultyofficer) per request from the grant's scope, else the lecturer grant's department, else `hrm.staff_record.home_department`. Any of the six grantor offices may grant any office, including `super` and `ict` — there is no two-person rule. Ending a person (`iam.person.ended_on`) has no screen (**NOT IMPLEMENTED**).

### 12.2 Sign-in, password reset, session end, deploy floor

| Workflow | Steps and rules | Data | Notice |
|---|---|---|---|
| Staff sign-in | one door `/login`; the handler routes by the identifier's shape (matric / admission → student door; `PG/YY/NNNNNN` → PG door; JAMB or `APP/…` → student then applicant; else staff, and an email that fails staff is retried against the applicant and PG doors); `AuthService.signIn`: `AUTH_BAD_CREDENTIALS` "That username and password do not match an account." (unknown, ended person or wrong password); 5 failures → `locked_until = now() + 15 min` (`AUTH_LOCKED` "This account is locked after repeated failures; try again after HH:MM."); the failure event is written before the refusal so the counter survives | `platform.session` (`absolute_end = now() + 12 h`, `active_office` set once), `iam.sign_in_event`, JWT (`sub`, `offices`, `sid`, `name`, `exp`) in the httpOnly cookie `moaum_session`; acting office in the readable cookie `moaum_office` | none |
| Forced first-password change | `must_change` sends staff to Your password `/account/password` (student to `/student/profile?change=1`); new password ≥ 10, not containing the username | `iam.credential` rewritten, `credential_event` CHANGED | none |
| Forgot / reset | `/login/forgot` (always "If that names an account, a reset link is on its way"); identifier resolved STAFF → STUDENT → APPLICANT → PGAPPLICANT; a 32-byte token, SHA-256 kept in `iam.password_reset`, one hour, single use; `/login/reset?token=` sets ≥ 8 characters, clears the lockout and `must_change`, ends existing sessions | `iam.password_reset` | Email "Reset your MOAUM password" (link `<portal-url>/login/reset?token=…`) + SMS "MOAUM: reset your password within the hour at <link>" — delivery needs a configured provider |
| Every request | `AuditContextFilter` + `SessionGuard`: 401 "The token names a session this portal does not hold. Sign in again." / "This session was ended. Sign in again." / "This session reached its end. Sign in again." / "The portal was updated. Sign in again."; `X-Active-Office` must be one of the token's offices (403 "The office 'x' is not one this token carries: […]"); `last_seen_at` touched at most once a minute | `platform.session.last_seen_at` | — |
| Session end | Sign-out (nav foot) → `/api/v1/auth/sign-out` sets `ended_at`, clears both cookies; `GET /api/v1/auth/sessions` and `POST /api/v1/auth/sessions/{id}/end` let a person end their own sessions — **no screen calls them**; the Registrar cannot end another person's session (**NOT IMPLEMENTED**) | `platform.session.ended_at`, `ended_reason` | none |
| Deploy floor | a session issued before the running API instance started is refused with "The portal was updated. Sign in again." (`SessionGuard`); the frontend proxy clears the cookies and redirects to `/login?next=…` | — | none |
| Bootstrap | `/login/first` once: `X-Bootstrap-Secret` must equal `MOAUM_AUTH_HMAC_SECRET` and `iam.credential` must be empty ("The portal already has accounts; the first one is made once."); creates the person and grants registrar, academic, ict, super under "Bootstrap of the portal, Directorate of ICT" | as stated | none |
| Single sign-on | Keycloak OIDC with MFA (`amr` / `acr` checked) when `MOAUM_SSO_*` are set; matches the person by staff-number claim or username/email; `AUTH_SSO_UNKNOWN` "The University's sign-on knows this person, but the portal's register does not." | same session and token as a password sign-in | none — **IMPLEMENTED (code), NOT DEPLOYED** |

No rate limit exists on sign-in, forgot or reset (the `AUTH_THROTTLED` title exists; nothing raises it).

### 12.3 Applicant, student and postgraduate account creation

| Account | Created by | Sign-in identifier | First password | Notes |
|---|---|---|---|---|
| Undergraduate applicant | the applicant on `/apply` (`register_applicant`); or the old-portal migration (`import_applicant`, sentinel `SET_ON_FIRST_LOGIN`) | JAMB number or `APP/YY/NNNNNN` (email also tried) | chosen (≥ 8); migrated: the JAMB number | `admissions.applicant_account`; 12-hour session; lockout 5 / 15 min; events in `admissions.applicant_event`; two reset paths (applicant module and the shared `PasswordResetService`) |
| Student | none is created at intake: at the first sign-in with the admission or matriculation number, `StudentAuthService` verifies the applicant's hash and carries it over (`CARRIED_OVER`); otherwise the Registry opens one from Student 360 → **Portal account** (`PUT /student-auth/accounts/{id}`, first password ≥ 8, `must_change`; registrar, dregistrar, academic, records, ict, super; a matriculation number is required by the screen) | matriculation number, admission number (or JAMB number) | carried over, or set by the Registry; a migrated account with `must_change` accepts the student's own number | `iam.student_account`, `iam.student_event` (UNKNOWN, NO_ACCOUNT, BAD_PASSWORD, CARRIED_OVER, LOCKED, SIGNED_IN, PASSWORD_CHANGED, OPENED_BY_REGISTRY); "No portal account has been opened for this number yet." (`AUTH_NO_STUDENT_ACCOUNT`); a VOLUNTARY_WITHDRAWAL record is refused at `/api/v1/me` (`STUDENT_RECORD_CLOSED`) |
| Postgraduate applicant | the applicant on `/pg/apply` (`pg_apply`) | email or `PG/YY/NNNNNN` | chosen (≥ 6) | `admissions.pg_applicant`; lockout 5 / 15 min; 20 failures from one connection in 15 minutes throttle the source; reset with subject kind PGAPPLICANT |
| Postgraduate student | `pg_admit` writes `people.student` and `iam.student_account` with the applicant's hash | admission number (then the matriculation number) | the applicant's password | the student shell shows the `pgstudent` menu |
| External examiner | activation of an invitation (§3.4) | email | chosen (≥ 10, not containing the email) | `iam.credential` + office `extexaminer`; suspension ends the grant |

---

## 13. Consolidated list of gaps across workflows

The items below are the stages that a reader of the screens might take for working but which the code does not perform. Each is expanded in its section; the full status matrix is *09 Feature Status Report*.

| Area | Gap | Status |
|---|---|---|
| Admissions | Offer lapse and waiting-list promotion; officer screen for clearance items; applicant document upload/review; notices on decline, submission and JAMB-upload offers | NOT IMPLEMENTED / PARTIALLY IMPLEMENTED |
| Postgraduate | Appeal or reopen of a declined application; desk notices; offer-letter QR verifier; supervisor / panel / roster edits; Research Desk award button without a minute | NOT IMPLEMENTED / PARTIALLY IMPLEMENTED / defect |
| Matriculation | Preview and history-search screens; faculty scope on the list; "Fees" column; stale run text | PARTIALLY IMPLEMENTED / PLACEHOLDER |
| Registration | Notices on approve / return; HOD overload; probation unit ceiling; LOCKED status; office-created registration UI | NOT IMPLEMENTED / CONFIGURED BUT UNUSED |
| Results | Publication notice; correction path after a CORRECTED query; late-sheet reminders; office-per-stage enforcement in SQL; held-script ownership; CBT delivery; College notices and configuration screens | NOT IMPLEMENTED / PLACEHOLDER |
| Finance | Scheduled GL sync; bank-credit REVERSED; executed refund / withdrawal payouts; Quickteller / PayDirect live verification; Finance Controller and PG Secretary access to fee setup; Student 360 finance card | NOT IMPLEMENTED / PARTIALLY IMPLEMENTED / PLACEHOLDER |
| Deferment / transfer / biodata | `/verify/deferment` route; deferment settings screen; transfer notices; transfer letter fee and wording; biodata-change producer | NOT IMPLEMENTED / CONFIGURED BUT UNUSED |
| Graduation / documents | Curriculum rules in the audit; REFERRED state; clearance notices; automatic clearance from standing; cryptographic signing; identity-card collection and verification; courier integration | PARTIALLY IMPLEMENTED / PLACEHOLDER / NOT IMPLEMENTED |
| Hostel | Priority-category verification; artisan register; CANCELLED transfer state; public verify endpoint without token or throttle | NOT IMPLEMENTED (security note) |
| Help desk / requests / clinic | Satisfaction rating; office menu for `/support`; student reply; reminders; pharmacy, prescriptions, certificates | NOT IMPLEMENTED / PARTIALLY IMPLEMENTED |
| HR / expenditure | Establishment data entry; payslip PDF; movement letters; recruitment → employment link; menu/guard mismatches for requisitions and stores; research-grants page | PARTIALLY IMPLEMENTED |
| Identity | Rate limits on sign-in / forgot; Registrar ending another's session; sessions screen; ending a person; SSO deployment | NOT IMPLEMENTED / PARTIALLY IMPLEMENTED |

> **Note:** demo sign-ins for every office exist for training and walkthroughs; the roster is in `docs/demo-accounts.md` in the repository (the password is printed there, not here).
