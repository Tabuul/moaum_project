# Group B — Undergraduate admissions and the applicant portal

Audit basis: read-only reading of `api/`, `frontend/src`, `db/V*.sql` and the live function bodies in the local Postgres (`pg_get_functiondef`), plus the inventory files. Paths below are relative to `C:\Users\ajene\Documents\moaumpp`. Line numbers for the large TSX files come from grep and are exact; where a claim rests on a SQL function I name the function and the migration that last defined it (the live body was read from the database).

Three modules are covered, each with the full template:

1. **Applicant portal** — public Post-UTME registration, sign-in, the ten-stage application, slips, letters, acceptance.
2. **Undergraduate admissions office** — CAPS lists, candidate data, settings, screening/scores/merit/decisions, Direct Entry, JAMB status list, migration, intake to the register.
3. **Post-UTME CBT scheduling, check-in and slip verification** (V260) — exam setup, centres/rooms/slots, batches, publish, door, public QR verification.

A note first on scope: `frontend/src/app/eligibility/page.tsx` (`t/eligibility`, menus of dean and hod) is **not an admissions screen**. It reads `/api/v1/catalogue/courses/{code}/eligibility` — "who may register a course: the eligible programme-and-level set" (page.tsx:8). It belongs to the catalogue/registration group and is only listed here because the task named it. No admission eligibility rule lives there.

---

# 1. Applicant portal  (API module: applicant; schemas: admissions.applicant_account, application, fee_reference, application_document(+_blob), clearance_document, password_reset, applicant_event; pages: apply/**, applicant/**, api/auth/applicant/**)

## 1 Purpose
A candidate JAMB has admitted to the University registers on the portal with the JAMB registration number alone; the name and programme are read back from the committed CAPS list and never typed. The one account then carries the candidate through ten stages the database computes (`admissions.application_stage`, V021): account → application fee → submitted form → screening slip → released score → released decision → accepted offer → cleared documents → fees paid and courses registered → matriculated. Every screen renders from one read of `/api/v1/applicant/me`; every act posts to `/api/v1/applicant/me/...` and re-reads. The applicant never sees an unreleased score or decision and never sees the O'Level screening score (`ApplicantService.view`, `api/.../applicant/ApplicantService.java:433-562`).

## 2 Users and roles
- **Applicant** — the only actor. Guard `APPLICANT = "hasAuthority('OFFICE_applicant')"` (`ApplicantController.java:34`) on every `/me` route and sign-out. The token is issued by `TokenIssuer.issue(accountId, name, List.of("applicant"), sid, end)` (`ApplicantService.java:407`) for 12 hours (`SESSION_LENGTH`, line 202) and a `platform.session` row is opened with `active_office='applicant'` (`ApplicantRepository.java:749-752`).
- **Public (no token)** — `lookup`, `register`, `sign-in`, `forgot`, `reset` are permitAll in `api/.../platform/SecurityConfig.java:49-50`. (The api.md inventory marks lookup/register/sign-in as "applicant"; the controller has no guard on them and SecurityConfig opens them.)
- Scope: `applicationOf(account)` resolves the caller's own application (`ApplicantService.java:424`); `documentContent(documentId, applicationId)` filters by the caller's application (`ApplicantRepository.java:865-871`). There is no way for an applicant to name another application.

## 3 Navigation
Menu `applicant — Applicant (home a/dashboard)` (menus.md):
- **My application**: Overview `a/dashboard` → `/applicant`; Application Form `a/apply` → `/applicant/apply`; Application Fee `a/fee` → `/applicant/fee`
- **Screening**: Screening Slip `a/screening` → `/applicant/screening`; Screening Result `a/score` → `/applicant/score`
- **Admission**: Admission Status `a/status` → `/applicant/status`; Accept Your Offer `a/accept` → `/applicant/accept`; Document Clearance `a/clearance` → `/applicant/clearance`; Matriculation `a/matric` → `/applicant/matric`
- Not in a menu: `/apply` (public registration), `/login`, `/login/forgot`, `/login/reset`, PDF routes `/applicant/apply/pdf`, `/applicant/screening/slip`, `/applicant/status/letter`.
Titles (`frontend/src/lib/titles.ts:725-760`): "My application", "Application form", "Application fee", "Screening slip", "Screening result", "Admission status", "Accept your offer", "Document clearance", "Matriculation". Several subtitles are hard-coded prototype text ("Post-UTME · batch C · CBT Hall B", "B.Sc. Computer Science · 100 Level") — cosmetic, not data.

## 4 Screens

### 4.1 Post UTME Registration — `/apply` (public)
`frontend/src/app/apply/page.tsx` picks the session from `?session=YYYY/YYYY` or the CURRENT session from `/api/v1/ref/sessions`, else "2026/2027". `Register.tsx`:
- Layout: two-column login card. Left brand panel "Create your application account"; right form headed **"Post UTME Registration"** — "Your JAMB registration number first. Everything else follows from it."
- Field **JAMB registration number** (placeholder `202699176777GF`, maxLength 15). On every keystroke, once it matches `^\d{12}[A-Z]{2,3}$`, the page POSTs `/api/v1/applicant/lookup` (`Register.tsx:259`). States returned by `admissions.applicant_lookup` (V023): `nolist`, `none`, `found`, `registered`, `closed` (`idle` when the shape is wrong).
  - `nolist` → red note "Nobody can be verified yet, and so nobody is let through".
  - `none` → "That number is not on the list JAMB sent the University" (three causes; "Do not travel to the campus to resolve this").
  - `closed` → "The University is not admitting into {programme} this session".
  - `registered` → "An application account already exists for this number" with a **Sign in** link.
  - `found` → green note "Found on the UTME/Direct Entry list JAMB sent the University"; read-only **Surname and other names** and **Programme you chose**; then the fields open.
- Fields when found (all required): **Email address** (regex `^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$`, with a "Did you mean gmail.com?" typo hint, never refused), **Phone number** (read as 0803…, +234 803… or 803…, must become 11 digits starting 0), **Choose a password** / **Confirm password** (≥ 8 characters, must match, show/hide eye). Client errors are the literal strings at `Register.tsx:270-278`.
- **Continue** → POST `/api/auth/applicant/register` (Next handler `api/auth/applicant/register/route.ts`) which calls `/api/v1/applicant/register`, sets the session cookie and office cookie `applicant`, then `router.push("/applicant")`.
- Server-side rules (`ApplicantService.register`, lines 327-366 and `admissions.register_applicant`, V023) — see §6.

### 4.2 Sign-in, forgotten password, reset
Sign-in is the shared `/login` door (`frontend/src/app/login/Login.tsx`); `api/auth/sign-in/route.ts:49-83` routes a 12-digit+letters or `APP/YY/NNNNNN` identifier to `/api/v1/applicant/sign-in` (after first trying the student door, so a matriculated ex-applicant lands on the student side), and an email that fails the staff door is retried against the applicant door. Lockout: 5 failures → 15 minutes (`LOCK_AFTER`, `LOCK_FOR`, `ApplicantService.java:203-204`); error `AUTH_BAD_CREDENTIALS` "That number and password do not match an application account." and `AUTH_LOCKED`. Every attempt is written to `admissions.applicant_event` (outcomes `UNKNOWN`, `LOCKED`, `BAD_PASSWORD`, `SIGNED_IN`, `RESET_UNKNOWN`, `RESET_REQUESTED`, `RESET_DONE`). A migrated account whose hash is the sentinel `SET_ON_FIRST_LOGIN` signs in with the JAMB number as password (lines 388-393). Forgot/reset: `/login/forgot` → `/api/v1/applicant/forgot` (always 202), a 24-byte token hashed SHA-256 into `admissions.password_reset` valid one hour, emailed and SMSed with link `{portal-url}/login/reset?token=…`; `/api/v1/applicant/reset` sets the password and signs the applicant in (lines 243-287). Note `PasswordResetService` (auth module) also resets applicant passwords through `iam.password_reset` — two reset paths exist.

### 4.3 Overview — `/applicant` (stage rail)
`Screens1.tsx Dashboard`: passport card (uploaded PASSPORT document, else JAMB's downloaded photo `jambPassport`, else "Your passport is not on record yet…"); tiles **Application number**, **Programme applied for**, **UTME score / Entry**, **Stage n of 10**; a "what next" note from `NEXT[stage]` (`lib/applicant.ts:119-130`) with a button to the right screen; the ten-step **Your application** rail (`STAGES`, lines 105-116); **Dates that matter** (reference expiry, screening date/batch/centre/room/reporting time, decision, acceptance, clearance); **Notices sent to you** — every `platform.notice` about the application with channel, recipient and state Sent / Not delivered / Waiting to be sent (`ApplicantRepository.notices`, line 887).

### 4.4 Application Form — `/applicant/apply`
`Screens1.tsx Apply`:
- Stage < 1: red note "The form opens when your application fee is confirmed" with **Pay the application fee**.
- Stage 1: pills "1 Biodata · 2 O'Level · 3 Review". **1 Biodata** — read-only from JAMB (name, date of birth from the DOB attachment, sex, state and LGA, JAMB number, UTME score or "Direct Entry"); one editable field **Next of kin — name and phone** (saved on blur via `PUT /me/next-of-kin`, reason "Next of kin given by the applicant"). **2 O'Level results** — sittings exactly as JAMB sent them (body, type, year, exam no., subject/grade table) or "No O'Level result has reached the University from JAMB yet". **3 Review and submit** — gate list ("Next of kin is missing"), declaration checkbox "I declare that the particulars I have given are true…", buttons **Save and come back later**, **Submit application** (`POST /me/submit {declaration:true}`).
- Stage ≥ 2: green note "Your application was submitted on …", panel **What you submitted** and **Print / Download (PDF)** → `/applicant/apply/pdf`.
- There is **no document-upload control** on any applicant screen (V056 removed documents as a condition of submitting; the passport comes from JAMB's download). The API `POST /me/documents` still exists (see §13).

### 4.5 Application Fee — `/applicant/fee`
`Screens1.tsx Fee`: table **Application and screening fee** — "Post-UTME screening fee" + "Portal and payment charge" = **Total payable** (from `admissions.applicant_fee_rule`); panel **Your payment reference** showing the open reference (`MOAUM-APP-NNNNNN-XXXX`, expires 24 h) or "No reference is open"; buttons **Generate a reference for ₦…** / **Generate a new reference** (`POST /me/fee-references {kind:"APPLICATION"}`) and **Pay ₦… by card or USSD** (`PayByCard` in `common.tsx:119-200`: lists enabled gateways from `/api/v1/payments/gateways`, opens `/api/v1/payments/checkout`, shows PayDirect PRN/USSD instructions and an **I've paid — check now** button that calls `/api/v1/payments/verify`); table **How you can pay** (card/USSD, bank transfer, bank branch). On return with `?paid=REF` the page server-side calls `/api/v1/payments/verify` before rendering (`fee/page.tsx:12-14`). Once confirmed: green "Payment confirmed — ₦… received" and a **Receipt** panel (reference, confirmed, channel, amount).

### 4.6 Screening Slip — `/applicant/screening`
`ScreeningSlip.tsx`: until seated in a **published** batch (a DRAFT batch is hidden: `ApplicantService.view` lines 438-440, 489) — "Your examination schedule has not been published yet". Then: note "Report at HH:MM on {day} with this slip and a valid identification document" (reporting time = batch start − exam `checkin_minutes`, default 30, `lib/applicant.ts:21-25`), or "You sat the examination on …", or red "Your batch has been postponed/cancelled"; panel with passport, name, application no, JAMB, programme, attendance pill (Not yet checked in / Checked in / Present / Absent / Disqualified), the QR (encodes `{origin}/verify/putme/{token}`), and fields Batch, Date, Report by, Examination time, Centre, Room, Seat, Workstation, Bring; **Examination instructions** (exam text); **What to bring, and what you may not**. **Download slip (PDF)** → `/applicant/screening/slip` (409 "No examination slip yet" before scheduling). **See your screening result** once stage ≥ 4.

### 4.7 Screening Result — `/applicant/score`
`Screens2.tsx Score`: before release — "Scores are released when every batch has been screened". After: tiles **UTME** (of 400, scaled), **Post-UTME screening** (source CBT / EXAM / OLEVEL / NONE with wording), **Aggregate** (green/red against cut-off), **Departmental cut-off**; note above/below cut-off or "No cut-off is stated for your programme yet"; **How your aggregate was calculated** (raw, of, scaled, weight, contribution); **Where you stand** (merit position of applied, places); "If you think this score is wrong" (remark within seven days at the Registry). Figures come from `admissions.screening_result` (V101).

### 4.8 Admission Status — `/applicant/status`
`Screens2.tsx Status`: before release — "Your application is with the Admissions Board" plus a table of the three outcomes. WAITING → "You are on the waiting list"; NOT_OFFERED → "You were not offered a place this session" (+ decision note). OFFERED → green card "Offer of provisional admission" (programme, faculty, level, session, released date; UTME/Screening/Aggregate/Merit position), then either "You accepted this offer on …" (→ **Clearance checklist**), "You declined this offer on …", or red "Accept your offer" (→ `/applicant/accept`). **Print Offer Letter** appears only after acceptance → `/applicant/status/letter`.

### 4.9 Accept Your Offer — `/applicant/accept`
`Screens3.tsx Accept`: opens only when decision OFFERED and released. Table **To accept, you must do both**: pay the acceptance fee (non-refundable; amount `acceptance_fee` + `checking_fee`) and sign the undertaking. **Undertaking** text with checkbox "I have read the undertaking and I accept it." Buttons: **Sign the undertaking** (`POST /me/accept {undertaking:true}`), **Generate a reference for ₦…** / **Generate a new reference** (`POST /me/fee-references {kind:"ACCEPTANCE"}`), **Decline this offer** (browser confirm "Decline this offer? A declined offer is not reinstated." → `POST /me/decline`), and the **PayByCard** block when a reference is open. `?paid=` return verifies the payment server-side (`accept/page.tsx:12-14`). Once both are done: "Offer accepted — ₦… received" and a **Receipt** panel with "Non-refundable: Yes".

### 4.10 Document Clearance — `/applicant/clearance`
`Screens3.tsx Clearance`: before acceptance — "Clearance opens when you have accepted your offer". Then a six-row **Documents** table from `CLEARANCE_ITEMS` (`lib/applicant.ts:140-147`): O'Level certificate or statement of result, Birth certificate or declaration of age, Local government identification, JAMB admission letter, Medical fitness certificate, Passport photographs (six copies) — each Not presented / Verified (with date) / Query (with the note). Header "n of 6 verified"; when all six are VERIFIED, "You are cleared" with **What happens next**. "Nothing is paid at clearance, to anyone." Read-only for the applicant: the Registry records each item via the office API (see module 2 §13 — no officer UI was found).

### 4.11 Matriculation — `/applicant/matric`
`Screens3.tsx Matric`: explains registration-before-matriculation; panel **What you carry now** shows the admission number (`people.student.admission_no`, "MOAUM/ADM/YY/NNNNNN") once the Academic Office runs the intake, else "Not issued yet."; **What you will be issued** (matric format table — note it shows `MOAUM / dept / YY / NNNN`, an older description than the V263 format); step list of which office does what. Once `matric_no` exists: "Matriculation number issued" card and "Your application account is now your student account".

### 4.12 PDFs (Next route handlers, `pdf-write.ts` + `brandHeader`)
- **Application form** `/applicant/apply/pdf/route.ts` — crest header "Application Form", passport (uploaded or JAMB data URL), 11 biodata rows, O'Level sittings, "Submitted on …/Not yet submitted", footer "Issued by the portal on … · APP no". No QR.
- **Examination slip** `/applicant/screening/slip/route.ts` — header with exam name and session, JPEG passport if on file, name/app no/JAMB/programme, "THIS BATCH IS POSTPONED/CANCELLED" banner when so, Batch/Date/Report by/Examination/Centre/Room/Seat/Workstation, centre address, **QR** built with `qrMatrix` pointing to `/verify/putme/{token}`, examination instructions, what to bring, anti-impersonation paragraph, footer.
- **Admission letter** `/applicant/status/letter/route.ts` — 409 "No offer to print" unless OFFERED and released; 409 "Accept your offer first" until `acceptedAt`. Header "Office of the Registrar · Academic Affairs", "Our ref: APP no", date of release, "OFFER OF PROVISIONAL ADMISSION" paragraph naming level, programme, faculty, session and the basis (NM → "National Merit" … OTHER → "the Board's decision"), provisional-terms paragraphs, "As screened" box (UTME/screening/aggregate/cut-off/merit position), signature "Registrar / For: Vice-Chancellor". No QR or verification code.

## 5 Workflow and statuses
Stage number (`admissions.application_stage`, V021; `lib/applicant.ts STAGES`):

| Stage | Meaning (milestone complete) | Set by |
|---|---|---|
| 0 | Account created; fee not confirmed | `register_applicant` |
| 1 | `fee_confirmed_at` | `confirm_fee` (Bursary/gateway) |
| 2 | `submitted_at` | `submit_application` (applicant) |
| 3 | `screening_batch_id` (and batch not DRAFT for the applicant's view) | desk `assign_screening` or CBT `putme_generate`/`putme_move` |
| 4 | `score_released_at` | `release_scores` (office) |
| 5 | `decision_released_at` | `release_decisions` / `load_jamb_admissions` |
| 6 | `accepted_at` | `settle_acceptance` when undertaking + acceptance fee both stand |
| 7 | `cleared_at` | `clear_document` when all 6 items VERIFIED |
| 8 | an APPROVED/LOCKED `registration.course_registration` for the session | registration module |
| 9 | `people.student.matric_no` | matriculation module |

Candidate `offer_state` (CHECK `ck_candidate_state`): `PROPOSED` (created at registration/import) → `ADMITTED` (release of an OFFERED decision, or JAMB list "Accept") → `ACCEPTED` (settle_acceptance) ; `DECLINED` (decline_offer from PROPOSED/ADMITTED); `WITHDRAWN` (CAPS batch withdrawn); `LAPSED` — allowed by the CHECK but **no function or controller ever sets it** (offers do not lapse automatically).

Decision (`ck_app_decision`): `OFFERED | WAITING | NOT_OFFERED`; basis (`ck_app_basis`): `NM | SM | ELG | LOCALITY | PLWD | OTHER`. Fee reference kind: `APPLICATION | ACCEPTANCE`. Document status: `PENDING | ACCEPTED | REJECTED` (kinds `OLEVEL_STATEMENT | BIRTH_CERT | LGA_ID | JAMB_SLIP | PASSPORT`). Clearance item state: `NOT_PRESENTED | VERIFIED | QUERY` (items `OLEVEL_ORIGINAL | BIRTH_CERT | LGA_ID | JAMB_LETTER | MEDICAL | PHOTOGRAPHS`).

Decline: `decline_offer` sets `declined_at`, candidate → DECLINED; refused if already accepted ("the offer was accepted on …; withdrawing is a change of status on the register"). Nothing is emailed on decline.

## 6 Business rules and validations (as written)
- Lookup/registration (`admissions.applicant_lookup`, `register_applicant`, V023): "nobody can be verified: no admission list is loaded for {session}" (23514); "the number {key} is not on the list JAMB sent the University for {session}"; "an application account already exists for {key}" (23505 → 409); "the University is not admitting into {programme} this session"; "the address {email} already belongs to an application account" (23505). The candidate row is created with `entry_level` 100 for UTME else 200 and `admitted_from` = the CAPS row. Application number `APP/YY/NNNNNN` from `platform.next_number('APPLICATION','UNIVERSITY',session)`.
- Controller shape checks (`ApplicantService.java:331-346`): `APP_NUMBER_SHAPE` "A JAMB registration number is twelve digits and then two or three letters."; `APP_EMAIL`; `APP_PHONE` "A Nigerian mobile number is eleven digits beginning with a zero."; `APP_PASSWORD_SHORT` "Eight characters at the very least." Password stored bcrypt cost 12 (`ck_applicant_hash` demands `$2?$12$…` or the migration sentinel).
- Fee reference (`new_fee_reference`, V148): "the application fee is already confirmed"; "there is no offer to accept" (acceptance before a released OFFERED decision); "the acceptance fee is already confirmed". Amount = application_fee + portal_charge, or acceptance_fee + checking_fee; reference `MOAUM-APP|ACC-{last 6 of APP no}-{4 random digits}`, expiry now + 24 h. Kind other than APPLICATION/ACCEPTANCE → `APP_FEE_KIND`.
- Confirmation (`confirm_fee`, V062): "no reference … was generated by this portal" (23503); "a payment is confirmed by a person" (needs an actor — the gateway path uses the all-zero NOBODY actor as office bursar, `PaymentsService.java:565`); idempotent "already confirmed"; receipt no `RCT-YYYY-NNNNN`; APPLICATION sets `fee_confirmed_at`, ACCEPTANCE sets `acceptance_confirmed_at` and calls `settle_acceptance`.
- Submit (`submit_application`, V056): "the form opens when the application fee is confirmed"; "the next of kin is not given"; documents are not a condition; `declaration_ip` recorded. `APP_DECLARATION` if the box is unticked. Next of kin cannot change after submission (`UPDATE … WHERE submitted_at IS NULL`, `ApplicantRepository.java:844`).
- Documents (`ApplicantService.document`, 595-624): after submission only PASSPORT may be replaced (`APP_SUBMITTED`); kind must be one of five; content type pdf/jpeg/png; 1 byte–2 MB (`APP_DOCUMENT_SIZE`, also `ck_doc_bytes`); a new upload supersedes the previous of that kind.
- Accept (`sign_undertaking`): "there is nothing to accept yet"; "this offer was declined on …". `settle_acceptance` requires `undertaking_at`, `acceptance_confirmed_at`, no `declined_at`.
- Clearance (`clear_document`): "clearance opens when the offer has been accepted"; 6 VERIFIED → `cleared_at`; any change below 6 clears `cleared_at` again; a QUERY must carry a note (`ck_cl_query_note`).
- View rules: score hidden until `score_released_at`; decision/basis/note hidden until `decision_released_at`; slip hidden while the batch is DRAFT; O'Level score never returned to the applicant.

## 7 Notifications (all through `admissions.notify_applicant` → `platform.queue_notice` EMAIL to account email and SMS to phone, `about_kind='application'`, unless stated)

| Event | Trigger | Recipient | Channel | Subject |
|---|---|---|---|---|
| Account created | `ApplicantService.register` | applicant | Email + SMS | "Your MOAUM applicant account" / "MOAUM applicant account" |
| Password reset asked | `ApplicantService.forgot` | applicant | Email + SMS | "Reset your MOAUM application password" |
| Fee confirmed (either kind) | `confirm_fee` | applicant | Email + SMS | "Your payment receipt · RCT-…" |
| Seated in a legacy screening batch | `assign_screening` | applicant | Email + SMS | "Your screening slip is ready" |
| CBT schedule published / moved / withdrawn / batch postponed or cancelled | `putme_publish`, `putme_move` (published batch), `putme_unschedule`, `putme_batch_state` | applicant | Email + SMS | "Your Post-UTME examination schedule", "Your Post-UTME schedule has changed", "Your Post-UTME seating has been withdrawn", "Your Post-UTME batch has been postponed/cancelled" |
| Scores released | `release_scores` | applicant | Email + SMS | "Your screening result is released" |
| Decision released | `release_decisions` | applicant | Email + SMS | "You have been offered provisional admission" / "You are on the waiting list" / "The admission decision on your application" |
| Acceptance settled | `settle_acceptance` | applicant | Email + SMS | "Your place is held" |
| Clearance query | `clear_document` (QUERY) | applicant | Email + SMS | "A query on your clearance documents" |
| Cleared | `clear_document` (6/6) | applicant | Email + SMS | "You are cleared" |
| Reconsideration suggestion | `ApplicantsController.notifySuggestions` / `suggestOne` | applicant (email only, skipped when none) | Email | "Your {session} admission — a suggested programme" |

No notice is sent on decline, on submission, or when a JAMB-list upload offers a place (`load_jamb_admissions` sets `decision_released_at` directly without notifying).

## 8 Reports, exports and documents
Application form PDF, examination slip PDF (QR-verified at `/verify/putme/{token}`), admission letter PDF (after acceptance, no verification code) — §4.12. Receipts are notices, not PDFs.

## 9 Configuration
Applicant fees per session: `admissions.applicant_fee` (application_fee, portal_charge, acceptance_fee, checking_fee), stated by the Bursary on **Fees → "Applicant · Post-UTME fees"** (`frontend/src/app/finance/fees/FeeSchedule.tsx:537-550`, `PUT /api/v1/admissions/sessions/{s}/{y}/applicant-fees`, guard FEESETTERS = academic, registrar, dregistrar, bursar, ict, admin, super). Default when unstated: 2,000 / 300 / 25,000 / 0 (`applicant_fee_rule`); local DB has 2026/2027 = 2,000 / 300 / 30,000 / 0. Portal URL for links: property `moaum.portal-url` (default `https://moaum-portal-production.up.railway.app`, `ApplicantService.java:224`).

## 10 Data
- `applicant_account` (session, candidate_id UNIQUE, jamb_key, email UNIQUE-ish by check in function, phone `^0\d{10}$`, password_hash, failed_attempts, locked_until, last_signed_in_at) — **not audit-attached**.
- `application` (one per account and per candidate; `application_no ^APP/\d{2}/\d{6}$`; all the timestamps of §5; `putme_token` 16-hex default, unique index; `schedule_review`) — audited.
- `fee_reference` (reference UNIQUE, receipt_no UNIQUE, `ck_fref_confirmed`) — audited. `application_document` + `_blob` — audited/blob not. `clearance_document` UNIQUE(application, item) — audited. `password_reset` (token_hash UNIQUE), `applicant_event` — not audited. `suggestion_sent` — not audited.
- Conversion: `people.student` gets `candidate_id`, `admission_no`, `jamb_reg_no` from the candidate via `people.intake` (module 2 §5); the student account later reuses the applicant's bcrypt hash (`StudentPortalRepository.applicantHash`).

## 11 Scheduled jobs and integrations
Payment gateways (Paystack, Flutterwave, Quickteller, PayDirect) confirm applicant references via signed webhooks and `/api/v1/payments/verify`; a reconciliation sweep exists but is run from `PaymentsController.sweep` (line 130), not a scheduler — I found no `@Scheduled` in the payments service. Notices are dispatched by `NoticeDispatcher`.

## 12 Security notes
Public: lookup, register, sign-in, forgot, reset (no rate limit found; lookup fires on every keystroke once shaped). 12-hour JWT; lockout 5/15 min; reset token hashed, one hour, single use; sessions ended on password reset. Documents served `inline` with the stored content type. The applicant's `platform.session` row uses the account id as `person_id` (not an `iam.person`).

## 13 Implementation status

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Public registration by JAMB number | IMPLEMENTED | `apply/Register.tsx`, `register_applicant` | |
| Sign-in / lockout / forgot / reset | IMPLEMENTED | `ApplicantService.java:243-413` | two reset paths (applicant + auth module) |
| Biodata + next of kin + submit | IMPLEMENTED | `Screens1.tsx Apply` | biodata read-only from CAPS/attachments |
| O'Level entry by applicant | NOT IMPLEMENTED (by design) | `Screens1.tsx:374` | shown as JAMB sent it; office uploads |
| Document upload (5 kinds) | PARTIALLY IMPLEMENTED | API `ApplicantController.java:108-121`; no upload control in any applicant TSX | backend only |
| Application / acceptance fee references + gateway pay | IMPLEMENTED | `Screens1.tsx Fee`, `Screens3.tsx Accept`, `common.tsx PayByCard` | |
| Screening slip (screen + PDF + QR) | IMPLEMENTED | `ScreeningSlip.tsx`, `screening/slip/route.ts` | |
| Screening result | IMPLEMENTED | `Screens2.tsx Score` | |
| Admission status + letter PDF | IMPLEMENTED | `Screens2.tsx Status`, `status/letter/route.ts` | letter only after acceptance |
| Accept / undertaking / decline | IMPLEMENTED | `Screens3.tsx Accept` | |
| Clearance checklist (applicant view) | IMPLEMENTED (read) | `Screens3.tsx Clearance` | officer recording endpoint exists without a screen (module 2) |
| Matriculation page | IMPLEMENTED (read) | `Screens3.tsx Matric` | matric format text outdated vs V263 |
| Offer lapse (`LAPSED`) | CONFIGURED BUT UNUSED | `ck_candidate_state`; no setter found | |
| In-app notices list | IMPLEMENTED | Dashboard "Notices sent to you" | |

## 14 Common problems and troubleshooting
- "Nobody can be verified…" on `/apply`: no committed-or-held CAPS row exists for the session (`caps_row_live` empty). Load the CAPS list (module 2).
- "That number is not on the list…": wrong digit, University not chosen on CAPS, or tranche not loaded; also true when the row was withdrawn with its batch.
- Form will not open: application fee reference unconfirmed — pay on the gateway (self-confirms) or have the Bursary confirm the reference.
- "Not confirmed yet" after PayDirect: collection not yet reached; use "I've paid — check now" or wait for the webhook.
- Slip page says schedule not published although the desk seated the candidate: the batch is DRAFT; publish from the CBT desk.
- Accept page shows nothing to pay / wrong amount: `applicant_fee` not stated for the session — defaults apply (25,000); Bursary sets it on Fees.
- Letter 409 "Accept your offer first": undertaking or acceptance fee outstanding.
- Sign-in on email says bad credentials though the applicant exists: the staff door is tried first; the same message is returned either way — use the JAMB or application number.

## 15 Glossary
**JAMB key** — `upper(btrim(jamb_reg_no))`, the generated column every match uses. **Application number** — `APP/YY/NNNNNN`. **Reference** — `MOAUM-APP-…` / `MOAUM-ACC-…`, 24-hour payment reference. **Stage** — the 0–9 milestone computed by `application_stage`. **Undertaking** — the electronic acceptance declaration. **Clearance** — Registry's in-person check of six originals. **Provisional admission** — an offer standing on JAMB-sent results until verified.

---

# 2. Undergraduate admissions office  (API module: admissions — AdmissionsController, ApplicantsController, CandidateDataController, OlevelController, AdmissionSettingsController, AdmissionCycleController; schemas: admissions (caps_*, candidate, attachment, olevel_*, session_policy & rules, screening_batch, jamb_admission, de_award*, suggestion_sent) and people.student via `people.intake`; pages: admissions/** except postgraduate and putme)

## 1 Purpose
The office side of the UTME/Direct Entry cycle. The Academic Office (or Registrar) states the session's admission settings (quota, weighting, criteria, faculty ratios, per-programme cut-off, O'Level/UTME/DE subject rules) and puts them in force citing a Central Admissions Committee minute; states the general load cut-off; uploads and commits JAMB's CAPS lists; records the other JAMB downloads (passports, dates of birth, O'Level); seats and scores the screening; computes the merit list and records the Board's decisions; releases scores and decisions; uploads the JAMB admission-status list; brings admitted candidates onto the student register (admission numbers). Nearly every rule is a SQL function; the controllers call them.

## 2 Users and roles (guard constants)
- `AdmissionsController.LOADERS` = academic, registrar — CAPS load/append/commit/withdraw, reset-intake, merit record, DE awards, JAMB list upload, programme names/aliases. `READERS` = academic, registrar, dregistrar, dvc, vc, records, ict, admin, super (`AdmissionsController.java:26-28`). The service additionally refuses a load unless the *acting* office is academic or registrar (`CapsIntakeService.requireUploadingOffice`, lines 84-90; CHECK `ck_batch_office`).
- `ApplicantsController` (`:55-59`, 212, 415, 535): `READERS` (+bursar, −dvc/vc); `OFFICE` = academic, registrar, dregistrar (decisions, releases, screening batches, scores, clear scores, reconsiderations); `CONFIRMERS` (+bursar) confirm a fee reference; `REGISTRY` (+records) record clearance; `IMPORTERS` (+ict, super) old-portal migration; `FEESETTERS` (+bursar, ict, admin, super); `SCORE_UPLOADERS` = academic, registrar, dregistrar, ict, admin, super (upload/zero-missing/from-olevel/awaiting). `/post-utme-computed` is academic + super only (line 151).
- `CandidateDataController` WRITERS = academic, registrar, dregistrar (`:340`). `OlevelController` SECRETARIAT same; the O'Level *score* is returned only when the acting office is `academic` (`SCORE_OFFICE`, lines 530, 646-657).
- `AdmissionSettingsController.SECRETARIAT` = academic, registrar, dregistrar; READERS add dean, hod, dvc, vc, records, ict, admin, super.
- `StudentController.WRITERS` = academic, registrar, dregistrar for `POST /api/v1/student/intake/{s}/{y}` (`student/StudentController.java:35, 218`).
- Scope: none by faculty/department; everything is by session.

## 3 Navigation (menus.md)
**academic — Admissions**: Admission Settings `/admissions/settings` (badge !), Upload Applicants and Candidates `/admissions/caps`, Upload Passport, DOB & O'Level `/admissions/candidate-data`, Migrate Old-Portal Applicants `/admissions/migrate`, Compute PUTME Score `/admissions/computed-screening`, Screening Register `/admissions/screening`, Post-UTME CBT Schedule `/admissions/putme`, Upload PUTME Score `/admissions/scores`, Merit List `/admissions/merit`, Direct Entry Screening `/admissions/de-screening`, Report on Post-UTME Registration `/admissions/applicants`, Report on Admissions `/admissions`.
**registrar — Admissions**: Post-UTME CBT Schedule, Admissions `/admissions`, Admitted List `/admissions/applicants`. **ict — Admissions**: Post-UTME CBT Schedule, Post-UTME Scores `/admissions/scores`. **admin — Admissions**: CBT Schedule, Post-UTME Scores, Admissions. **records / dregistrar / super — Academic**: Post-UTME CBT Schedule. Unlisted pages: `/admissions/screened`, `/admissions/screening/[batch]`. Note the Registrar's menu does not list settings, CAPS, scores or merit although the API admits that office.

## 4 Screens

### 4.1 Admission settings — `/admissions/settings` (`settings/AdmissionSettings.tsx`, `OlevelGrading.tsx`)
Session from `?session=` else "2026/2027". No settings yet → "No admission settings exist for {session}" with **Begin from {previous}** (`POST …/policy/start-from/{from}`) or a NUC quota box (placeholder 10198) and **Create the {session} settings** (`PUT …/policy` with defaults 70/30, 80:20, 60:40, ELG cap 50, dept share 80, index 6/2, MPF true, screening true). With settings: RoleLine; note "in force" or "a DRAFT, and nothing may be admitted under them"; tiles; panels **The aggregate score** (Paragraph 2.6), **The four selection criteria** (must total 100), **The ratios and the caps**, **Catchment local governments** (textarea → `PUT …/policy/catchment`), **NUC approved quota**, **Faculty UTME:Direct-Entry split**, **Every programme the University runs** (columns Programme, Faculty, Cut-off, O'Level requirement, UTME subjects, Direct Entry, Places; per row edit/State/close/reopen), the rule modal (**Cut-off of its own**, **Programme quota**, requirement texts, **Relevant O'Level subjects**, **Required UTME subjects (checked)** with syntax "comma = all, '/' = any-one-of, 'N of A/B/C'", **Direct Entry subjects (checked)**, **DE passes required**, **Compulsory-credit exceptions** checkboxes), **Findings** (from `policy_findings`), **Questions the guidelines raise**, and **Put the {session} settings in force** with the **Central Admissions Committee minute** field (placeholder CAC/2026/07) or a re-affirmation field when already in force. The **General UTME cut-off for loading the JAMB lists** panel (`LoadCutoff.tsx`, `PUT …/load-cutoff`, "of 400", red "No UTME list can be loaded until this is stated") and the **O'Level grading for the screening score** panel (points per grade A1–F9, subjects counted, one-/two-sitting bonus, "Programmes screened by examination" add/remove; `PUT …/olevel-grading`) sit on the same page.

### 4.2 JAMB admission lists (CAPS) — `/admissions/caps` (`caps/CapsIntake.tsx`, `AliasMapper.tsx`, `ProgrammeEditor.tsx`)
Two upload cards, **UTME** (100 Level) and **Direct Entry** (200 Level), each with **Choose the … file…** (.xlsx, parsed in the browser by `lib/caps.ts parseCaps`, both the raw CAPS layout `RG_NUM/CO_NAME…` and the office-built layout) and **Use the sample instead**. The parsed list shows tiles, blocking findings ("n rows cannot be accepted, so none of the file is written"), unresolved JAMB course names with the **AliasMapper** ("JAMB course names the alias list does not carry" → `PUT /programmes/{code}/jamb-alias`), **Under the cut-off — read, not loaded**, and the list table. **Load the {kind} list** (`POST /caps-batches` then `/rows` in chunks) is disabled unless the acting office may load, the file is not the sample, and — for UTME — settings are in force (`CapsIntake.tsx:572`). After loading: **Commit** (`POST /caps-batches/{id}/commit`). **Lists loaded for {session}** table (Kind, File, Rows, Downloaded, Loaded, By, State held/committed/withdrawn) with **Commit** and **Withdraw** (modal "Why the list is withdrawn", required). **Does the list reconcile?** (the five `reconcile` findings). **One course code, two names** (all programmes; edit modal: name, department, category, archived, reason). **Reset the JAMB list for {session}** (double confirm; `POST …/reset-intake`).

### 4.3 Passports, dates of birth and O'Level — `/admissions/candidate-data` (`candidate-data/CandidateData.tsx`, `OlevelView.tsx`)
Tabs/panels for the three downloads: **passports** (multiple images; the JAMB number is read from the filename by `reg_no_in` shape `\d{12}[A-Za-z]{2,3}`; files "Named, not guessed at" when unreadable; images ≤ 64 KB stored as data URL, larger by metadata only; a streamed upload variant), **date-of-birth file** (.xlsx; ambiguous dates flagged), **O'Level file** (.xlsx, one row per subject; credits/English/Maths/"Five credits" columns). Each **Record** posts `POST …/candidate-data {kind, items}`; the server skips already-recorded source names, parses O'Level sittings (`olevel_from_attachment`), and re-attaches everything held to committed candidates (`attach_pending`). Panels: "As the register stands" (`attachment_state` findings), passport gallery with search/programme filter, "Results recorded, and the screening score they carry" with an eye → **OlevelView** modal (sittings; the counted subjects, points, bonus and total shown to the Academic Office only).

### 4.4 Report on Admissions — `/admissions` (`Admissions.tsx`, `ApplicantsDesk.tsx`, `Reconsiderations.tsx`)
- **Admissions** (cycle from `/sessions/{s}/cycle`): tiles Applications / Screened (→ `/admissions/screened`) / Offers issued / Accepted; red note "n admitted candidates are not yet on the register" with **Bring n candidates onto the register** (`POST /api/v1/student/intake/{session}`); **Programmes — merit lists** table with **Record all programmes** (`POST /merit/record-many`, confirm text at `Admissions.tsx:58`); **JAMB reconciliation** table.
- **ApplicantsDesk** (`/sessions/{s}/applicants`): tiles Admitted applicants / References open / Documents to review / Decisions entered; note "Applicant fees are set by the Bursary and paid on the gateway" and red "The acceptance fee is not set for this session" when unstated; **Screening batches** (legacy: **New batch** modal — Batch label, Date, Starts, Ends, Venue, Capacity; **Seat the submitted** → `assign_screening`; **Hall list**; **Release scores**); **Applicants** table (Applicant, Programme, Stage, Seat, Score "·held", Decision "·held") with **Release decisions** (confirm when the acceptance fee is unset) and an eye opening the application modal: JAMB biodata, O'Level as sent, **CBT score, of 100** (`PUT …/screening-score`), **The Board's decision** (Decision, Basis, Note → `PUT …/decision`); for an admitted-but-unregistered candidate a read-only modal from `/candidates/{jambKey}`; **The list that goes back to JAMB** → **Download for JAMB** (five-sheet workbook, §8); **Admission status from JAMB** upload (`POST …/jamb-admissions` in chunks) with tiles loaded/matched/accepted/offered/unmatched and the row table.
- **Reconsiderations**: non-qualified candidates with five credits and an open programme they qualify for; a select of suggestions per row and **Suggest** (`POST …/reconsiderations/suggest`); "Told" column from `suggestion_sent`.

### 4.5 Post-UTME registration report / Admitted list — `/admissions/applicants` (`applicants/Applicants.tsx`)
Filters Faculty, Programme, Entry mode, Find an applicant (name or JAMB); tiles On the committed list / Registered for post-UTME / Not yet registered / Showing; **Admitted by programme** breakdown; **Applicants** table (first 200). Read-only.

### 4.6 Merit list — `/admissions/merit` (`merit/Merit.tsx`)
Programme type-ahead; tiles pool/eligible/proposed; table #, Candidate, JAMB, Entry, UTME, Post-UTME, Aggregate, Basis, Eligible (else "No Eng/Maths credit" / "Below cut-off" / "Not scored"), Proposed; **Record the merit list** (academic, registrar) → `POST /merit/record` (confirm at `Merit.tsx:83`).

### 4.7 Direct Entry screening — `/admissions/de-screening` (`de-screening/DeScreening.tsx`)
Programme type-ahead; table Candidate, JAMB, Level, Subjects (On file/None), Status (NO_RULE / UNVERIFIED / MET / SHORT from `de_screening`), **Enter subjects / Edit subjects** inline form: **Qualification (basis)** A_LEVEL | IJMB | JUPEB | NCE | ND | HND, **Year awarded**, **Awarding body / institution**, **Subjects offered** (one per line, grade after = : or ,), **Save/Update the record**, **Remove** (`POST/DELETE /de-awards`).

### 4.8 Upload Post-UTME scores — `/admissions/scores` (`scores/ScoreUpload.tsx`)
**Programmes whose Post-UTME scores must be uploaded** (exam-screened programmes: Registered/Scored/Released/Awaiting/Status; **Download all awaiting**, **Score remaining as zero**); **Post-UTME scores** textarea/CSV (`key, score`; key = JAMB or application number; **Download template**, **Load a CSV**, **Upload n scores** → `POST …/screening-scores/upload`, reconciliation table No applicant match / Score already released / Score out of 0–100); **Release the scores** (`…/release`, OFFICE); **Clear uploaded Post-UTME scores** (programme + type `CLEAR SCORES`).

### 4.9 Computed Post-UTME — `/admissions/computed-screening` (`ComputedPostUtme.tsx`)
`non_sitter_post_utme` rows (non-index programmes and Direct Entry): Candidate, JAMB, Programme, Mode, O'Level, UTME, Computed, Basis; **Enter O'Level as Post-UTME score** (`…/screening-scores/from-olevel`, academic/super/ict/admin/registrar/dregistrar), **Download Excel**, **Print / PDF**; audit table "Why a programme appears here — or does not" (Index (exam) vs Non-index, applications, submitted, paid).

### 4.10 Screening register — `/admissions/screening` (`ScreeningRegister.tsx`); Screened pool — `/admissions/screened` (`Screened.tsx`); Hall list — `/admissions/screening/[batch]` (`HallList.tsx`)
Register: every submitted candidate with UTME, O'Level /100, Post-UTME, Screening, Source (Post-UTME / Awaiting Post-UTME / O'Level + UTME / O'Level / UTME / none), plus a "Non-index Post-UTME scores" CSV button. Screened: per-faculty/course summary (Applied, Screened, Quota, Cut-off) with drill-down (RegNo, Name, Sex, State, UTME, Meets cut-off, O'Level uploaded, points, Compulsory (Eng & Maths) Met/Not met + missing), Excel/print of summary, detail and "O'Level screening — all programmes". Hall list: seats in order with photograph, **Print the hall list**.

### 4.11 Migrate old-portal applicants — `/admissions/migrate` (`MigrateApplicants.tsx`)
Requires the applicant fee to be stated; .xlsx/.csv of JAMB no / email / phone (name order option); **Import n applicants** in parallel chunks (`POST …/import-applicants`), then `link-held`; result tiles and "rows not imported" download; **Reset migrated applicants** (`…/reset-migrated`). Each imported row becomes candidate + account (`SET_ON_FIRST_LOGIN`) + application already fee-confirmed and submitted, with a fee reference on channel "Old-portal migration" (`import_applicant`, V179).

## 5 Workflow and statuses
1. **Settings**: `session_policy.state` `DRAFT` → `IN_FORCE` by `put_in_force(session, instrument)`; `SUPERSEDED` is allowed by the CHECK but nothing sets it. In force freezes weights, ratios, criteria, cut-offs and subject rules (`assertDraft`, `AdmissionSettingsService.java:338-346`); quotas (NUC, faculty, programme), catchment, relevant O'Level subjects, UTME/DE subject sets and closures remain editable. `put_in_force` refuses without a minute and while `policy_findings` returns anything.
2. **Load cut-off** (`load_cutoff`, V024) must be stated before a UTME list loads (`ADM_LOAD_CUTOFF_NOT_STATED`). Rows under it go to `caps_row_excluded` (reason `BELOW_CUTOFF`) — "read, not loaded". DE lists load without a cut-off and without programme-code resolution (`CapsIntakeService.java:94-121`).
3. **CAPS batch**: `held` (loaded, `committed_at` null) → `committed` (`commit_batch`) or `withdrawn` (`withdraw_batch`). Commit is refused while any `reconcile` finding other than "On the CAPS list, no candidate record" is non-zero; the pending count is stored in `committed_pending` (V048). Withdrawal needs a reason, an actor, and no student already admitted from the list; it sets candidates to `WITHDRAWN` and marks rows `withdrawn` (the `caps_row_live` view hides them). After a commit `attach_pending` re-matches held attachments. `list_kind` UTME | DIRECT_ENTRY; `source` CAPS_DOWNLOAD | CAPS_API.
4. **Candidate data**: `attachment.kind` PASSPORT | DATE_OF_BIRTH | OLEVEL; `read_as` EXACT | EMBEDDED | COLUMN | UNREADABLE; matched only to committed candidates (V038).
5. **Screening**: legacy batches (`screening_batch` with venue/capacity, `state` default PUBLISHED) seated by `assign_screening` in application-number order with seat `LABEL-NNN`; or CBT batches (module 3). Scores: entered per application (`PUT …/screening-score`, only when seated and unreleased), uploaded in bulk, zeroed for stragglers, or copied from the O'Level computation for non-index programmes; `release_scores` stamps `score_released_at` for every application seated or scored.
6. **Merit and decisions**: `merit_list` (V189) — see §6; `recordMerit` writes OFFERED (with basis) / WAITING / NOT_OFFERED (with reason) per application via `decide_application`, skipping released ones; or the desk enters one decision; `release_decisions` stamps `decision_released_at`, moves PROPOSED candidates with an OFFERED decision to ADMITTED and notifies. Alternatively `load_jamb_admissions` (JAMB's status file) offers and releases every "Accept…" row that has an application, basis from the JAMB category (`jamb_basis`: MERIT→NM, CATCH→LOCALITY, ELG/…LESS DEVELOP…→ELG, STATE→SM).
7. **Register**: `people.intake(session)` inserts a `people.student` for every candidate `ADMITTED` or `ACCEPTED` without one, admission number `MOAUM/ADM/YY/NNNNNN` (`platform.next_number('ADMISSION',…)`), entry mode/level from the candidate; refuses (23503) when the candidate's programme is not one the University runs. Note it runs on ADMITTED, i.e. before acceptance.
8. **Direct Entry path**: DE candidates register the same way (entry_level 200), are excluded from `merit_list` ("UTME only for now", V182) and from `recordMerit`, appear on the computed Post-UTME report, and are screened on the DE screen (`de_award` capture, `de_meets_combination` gate). Their offers are entered manually on the desk or arrive via the JAMB status list; `reconcile` flags "Direct Entry candidate entered at the wrong level".

## 6 Business rules and validations (verbatim where they raise)
- `policy_in_force`: "no admission settings are in force for … — nothing may be admitted, ranked or cut off until the Central Admissions Committee's settings for this session are in force".
- `policy_findings` (V097): "The selection criteria do not total 100%" (guidelines 10+35+30+25); "The programme quotas do not total the NUC approved quota"; "A faculty has no UTME cut-off"; "Equality of Local Government exceeds its ceiling".
- Settings service: `ADM_WEIGHTS` "The weighting does not total 100%", `ADM_RATIO_UTME_DE`, `ADM_RATIO_SCIENCE_ARTS`, `ADM_CRITERION_UNKNOWN/PERCENT`, `ADM_RATIO_PAIR` "…stated as both shares or neither", `ADM_RATIO_SUM` ("Education is 60:40; every other faculty is the session's 80:20"), `ADM_QUOTA`, `ADM_SETTINGS_EXIST`, `ADM_SETTINGS_IN_FORCE` "The {session} settings are in force under {minute} and are not edited.", `ADM_LOAD_CUTOFF` 0–400, `ADM_CLOSE_REASON`. CHECKs: weights/ratios sum to 100, `nuc_quota > 0`, cut-offs 1–400, `olevel_credits` 1–9, `choose ≥ 1`, group scope UTME | OLEVEL | DE.
- `cutoff_for`: programme rule cut-off, else faculty quota cut-off, else "no UTME cut-off is set for … — neither the programme nor its faculty carries one".
- CAPS load: `ADM_LIST_OFFICE`, `ADM_LOAD_CUTOFF_NOT_STATED`, `ADM_UNKNOWN_PROGRAMME` "Not a programme the University runs: …", `ADM_BATCH_COMMITTED`, `ADM_BATCH_WITHDRAWN`; `assert_row_matches_batch` trigger; `ck_row_code ^C\d{5}$`; aggregate 1–400; `commit_batch` "the admission list does not reconcile: …"; `withdraw_batch` "a list is withdrawn for a reason, and none was given", "n student(s) admitted from this list already hold an admission number".
- `reconcile` findings: "On the CAPS list, no candidate record" (non-blocking), "Admitted here, not on the CAPS list", "Matched, programme differs from CAPS", "JAMB course code the University does not run", "Direct Entry candidate entered at the wrong level".
- O'Level score (`olevel_score`, V154): points per grade from `olevel_grade_point` or defaults A1 6 … C6 1, D7–F9 0; best grade per subject across sittings; subjects ranked English/Mathematics first, then the programme's relevant (OLEVEL-scope) subjects, then others; top `subjects_counted` (default 5) summed plus bonus (one sitting 10, two 6); sittings counted by exam number or body|year|subject signature. Ceiling = counted × points(A1) + one-sitting bonus; scaled to 100 by `screening_component` when no exam score exists (source OLEVEL). Compulsory credits: `olevel_compulsory` per session, default English (`(?i)english`) and Mathematics (`(?i)^\s*math`), a credit is points ≥ 1; a programme may waive one via `programme_olevel_allowance`.
- UTME subject gate (`utme_meets_combination`, V192): reads the candidate's `subject1..4` from the raw CAPS row; rule items comma-separated are all required; "A/B" or "A or B" any-one; "N of A/B/C"; English always satisfied; no rule or no subject data → pass.
- DE gate (`de_meets_combination`, V200): same shape against `de_award_subject`; no rule or no captured subjects → pass.
- `merit_list` (V189): pool = submitted UTME applications of the programme whose CAPS row is live (exam-screened programmes also need a released score); aggregate = UTME/400×100×w_utme + screening×w_putme (screening = uploaded score, else scaled O'Level; falls back to whichever exists); `eligible` = programme not closed, aggregate present, `meets_cutoff` (UTME ≥ programme/faculty cut-off), compulsory credits, UTME combination; ranks by aggregate; fills the UTME share of the programme quota (quota × faculty UTME ratio) in basis order NM → SM (Benue) → ELG (round-robin by LGA among Benue) → LOCALITY (catchment LGAs), each up to its criterion percentage; `proposed_offer` = a basis was assigned; no quota → everyone eligible is NM.
- `decide_application` (V053): "the decision was released on … and stands"; "the screening score has not been released"; "an offer is made on a basis"; for OFFERED with O'Level on record, "a compulsory O'Level credit is missing: …". Controller: `APP_DECISION` (OFFERED/WAITING/NOT_OFFERED), `APP_DECISION_BASIS`.
- Scores: `APP_SCORE_LOCKED` "The score is entered for a seated candidate, and not after it is released."; upload rows out of 0–100 reported; `SCORES_CLEAR` "Type CLEAR SCORES to confirm…".
- Clearance: `APP_CLEARANCE_STATE`; review: `APP_REVIEW` "'x' is not a review outcome.", `APP_REVIEW_NOTE` "A rejection says what was wrong."
- Reconsiderations: `programme_suggestions` (V106) — UTME score on the live list, five credits including English and Maths, programme open, cut-off cleared or none, compulsory credits met, quota not yet filled by ADMITTED/ACCEPTED candidates, best five by cut-off; `ADM_SUGGEST_NOT_ELIGIBLE` "That programme is not one this candidate qualifies for."
- JAMB status list: "a JAMB admission list is uploaded by a person"; "the list is rows: registration number, name, course, admission status"; unmatched rows kept with why "Registration number not on the register — screened here?"; accepted-but-no-application rows why "…the applicant has not registered here".
- `reset_intake`: "the JAMB list is reset by a person"; deletes finance gateway events/attempts/reconciliation for the session's references, documents, fee references, clearance, resets, events, applications, accounts, screening batches, jamb_admission, O'Level, photos, attachments, candidates, caps rows/excluded/batches; detaches students (`candidate_id = NULL`).
- `programme_is_closed`: a closed programme blocks registration ("closed" lookup state) and eligibility.

## 7 Notifications
Office actions that notify the applicant are listed in module 1 §7 (`assign_screening`, `release_scores`, `release_decisions`, `confirm_fee`, `clear_document`, reconsideration emails). No notice goes to an office. `load_jamb_admissions` notifies nobody.

## 8 Reports, exports and documents
- **JAMB admission template** (`ApplicantsDesk.exportTemplate`, lines 120-198, data `GET …/jamb-template?programme=`): workbook `ADMISSION TEMPLATE {programme|ALL PROGRAMMES} {session}.xlsx` with crest, sheets `Admission_Summary` (Total/Registered/Qualified/Non-Qualified, Total Quota, UTME Quota (80%), Number On Merit List; QUOTA DISTRIBUTION per criterion; NATIONAL/STATE/LOCAL GOVERNMENT ANALYSIS), `Merit_List`, `Other_Qualified_Cases`, `Non_Qualified_Cases` (+ UTME REMARKS "Correct Combination"…, OL REMARKS), `Ranked_sheet`; 35 columns SN, REG_NO, NAME, GENDER, STATE, LGA, ENG, SUBJ2…SUBJ4 + scores, UTME SCORE, ENG/MATHS grade & point, SUBJ3–5 grade & point, SITINGS, OL/TEST TOTAL SCORE, sittings points, totals, ratios, remark (basis name / decision).
- **Computed Post-UTME** Excel/print (`brandedXlsx`, serial `CPU`); **Screened** summary/detail/all-O'Level Excel and print; **Screening register** non-index CSV; **Hall list** print; **Awaiting scores** download; **Score upload template**; **Migration template** and problem rows. CAPS parse CSV (`lib/caps.ts toCsv`). Excel exports use the S/N-first `brandedXlsx` convention where they go through `exportbrand.ts`; the JAMB template uses its own `xlsx` builder to match JAMB's layout.

## 9 Configuration (seeded, local DB)
- `session_policy` 2025/2026 DRAFT: nuc_quota 10198, weights 70/30, UTME:DE 80:20, Science:Arts 60:40, ELG cap 50, dept share 80, index 6/2, MPF and screening required; criteria NM 10, SM 35, ELG 30, LOCALITY 25 (V009). Faculty quotas: AC 180, AR 160, BAMS 180, CM 180, ED 160 (60:40), ES 160, LW 220, MS 160, PS 220, SC 160, SS 160, TI 160; no faculty cut-off. 64 programme rules (requirement texts, 5 credits, 2 sittings; no quota/cut-off), 63 OLEVEL subject groups, 4 UTME groups, 0 DE groups, 5 catchment LGAs, no closures, no allowances. No policy is IN_FORCE for a real session locally (2098/2099 is test residue). `olevel_grading`, `olevel_compulsory`, `load_cutoff`, `screening_exam_programme`: none for real sessions (defaults apply). `applicant_fee` 2026/2027 stated (§ module 1). `ref.jamb_alias` / `ref.jamb_alias_name` hold JAMB course names.

## 10 Data
`caps_batch` (audited) → `caps_row` (trigger `trg_row_matches_batch`, not audit-attached; `withdrawn` flag; view `caps_row_live`), `caps_row_excluded`; `candidate` (UNIQUE session+jamb_reg_no; `ck_candidate_needs_caps`: any state but PROPOSED needs `admitted_from`; `ck_candidate_level`; trigger `trg_putme_programme_change`); `attachment` (UNIQUE session/kind/source_name; `ck_att_matched`, `ck_att_read_key`), `candidate_photo`, `olevel_sitting` (WAEC | NECO | NABTEB | OTHER) → `olevel_grade`; `session_policy` (UNIQUE session) → `selection_criterion`, `faculty_quota`, `programme_rule` → `rule_subject_group` → `rule_subject`, `programme_olevel_allowance`, `programme_closed`, `catchment_lga`; `olevel_grading` → `olevel_grade_point`, `olevel_compulsory`, `load_cutoff`, `screening_exam_programme`, `applicant_fee`; `jamb_admission` (UNIQUE session+reg no); `de_award` (UNIQUE session/jamb_key/basis) → `de_award_subject`; `suggestion_sent`. Audit-attached: all except caps_row, caps_row_excluded, olevel_grade, olevel_sitting, rule_subject(_group), selection_criterion, suggestion_sent, applicant_account/event, password_reset, blobs. `link_candidates_to_caps` and `reset_migrated_applicants` are SECURITY DEFINER and temporarily disable audit triggers.

## 11 Scheduled jobs and integrations
None scheduled. Integrations are file uploads (CAPS .xlsx, JAMB status .xlsx, passports, DOB/O'Level sheets, score CSV); `caps_batch.source` admits `CAPS_API` but no API client exists.

## 12 Security notes
Every write needs an actor (functions check `moaum.actor_id` / `acting_person()`); the CAPS load additionally checks the acting office in code. Passports are returned to READERS via `…/candidate-data/passport/{id}/image` and `…/documents/{id}/content` (any application, `anyDocumentContent`). The O'Level score is withheld from every office but academic at the API. `reset-intake` is a destructive LOADERS action guarded only by browser confirms.

## 13 Implementation status

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Admission settings (draft, rules, findings, in force, start-from) | IMPLEMENTED | `AdmissionSettings*.java`, `settings/*.tsx` | `SUPERSEDED` state never set |
| Load cut-off; O'Level grading; exam-screened programmes | IMPLEMENTED | `LoadCutoff.tsx`, `OlevelGrading.tsx`, `OlevelController` | |
| CAPS upload/commit/withdraw/reconcile/alias/programme edit/reset | IMPLEMENTED | `CapsIntake*.java`, `caps/*.tsx` | `CAPS_API` source unused |
| Candidate data (passport/DOB/O'Level) | IMPLEMENTED | `CandidateDataController`, `CandidateData.tsx` | photos > 64 KB metadata only |
| Legacy screening batches + seating + hall list | IMPLEMENTED | `ApplicantsDesk.tsx:289-302`, `assign_screening` | parallel to V260 CBT desk |
| Score entry / bulk upload / zero / from O'Level / release / clear | IMPLEMENTED | `ApplicantsController.java:518-767`, `ScoreUpload.tsx`, `ComputedPostUtme.tsx` | |
| Merit list + record (one/all) | IMPLEMENTED (UTME only) | `merit_list` V182/V189, `Merit.tsx`, `Admissions.tsx` | DE excluded by design note "for now" |
| Board decision per application + release | IMPLEMENTED | desk modal, `decide_application`, `release_decisions` | |
| JAMB admission-status upload | IMPLEMENTED | `load_jamb_admissions`, `ApplicantsDesk.tsx:346-380` | no applicant notice |
| JAMB template export | IMPLEMENTED | `ApplicantsDesk.tsx:120-198` | |
| Reconsiderations (suggest / notify all) | IMPLEMENTED (suggest); notify-all endpoint has no button | `Reconsiderations.tsx`, `ApplicantsController.java:1121` | |
| Applicant document review (ACCEPTED/REJECTED) | PARTIALLY IMPLEMENTED | endpoint `:455`; no frontend caller found | backend only |
| Registry clearance recording | PARTIALLY IMPLEMENTED | `PUT …/clearance/{item}` `:1391`; no frontend caller found | applicant view exists; stage 7 unreachable from UI |
| Fee reference confirmation by office | PARTIALLY IMPLEMENTED | `POST …/fee-references/{ref}/confirm` `:443`; desk note says "there is no confirmation step here" | gateway path is the live one |
| Direct Entry screening + award capture | IMPLEMENTED | `DeScreening.tsx`, `de_screening` | offers for DE are manual/JAMB list |
| Post-UTME registration report / admitted list | IMPLEMENTED | `applicants/Applicants.tsx` | |
| Screening register / screened pool | IMPLEMENTED | `ScreeningRegister.tsx`, `Screened.tsx` | |
| Old-portal migration | IMPLEMENTED | `MigrateApplicants.tsx`, `import_applicant` | |
| Intake to register (admission numbers) | IMPLEMENTED | `people.intake`, `Admissions.tsx:77-93` | runs on ADMITTED, not only ACCEPTED |
| Offer lapse / waiting-list promotion | NOT IMPLEMENTED | no function moves WAITING → OFFERED or sets LAPSED | UI text promises it |
| Admission cycle read for deans/HODs | IMPLEMENTED (API) | `AdmissionCycleController` | consumed by `/reports/admissions/view` (reports group) |

## 14 Common problems and troubleshooting
- Load button disabled "No admission settings are in force": put the settings in force (needs a minute and zero findings) — UTME lists only.
- "No general UTME cut-off is stated for loading…": state it on the settings page first.
- "Not a programme the University runs: C…": the JAMB course name did not resolve — map it in **JAMB course names the alias list does not carry** or edit the programme; re-read the file (parsing re-runs against current aliases).
- Commit refused "the admission list does not reconcile": fix the named findings (ghost admissions, programme mismatch, unknown code, DE level); unregistered candidates do not block.
- Merit list empty or "Not scored": scores not released for an exam-screened programme, or candidates not submitted; for non-index programmes run "Enter O'Level as Post-UTME score" then release.
- Decision refused "an offer is made on a basis" / "a compulsory O'Level credit is missing": choose a basis; or record an allowance for the programme.
- Candidates admitted but "not yet on the register": run **Bring … onto the register**; a 23503 names a candidate whose programme name is not in `ref.programme`.
- Passports not attaching: the candidate's list is not committed (V038) or the filename carries no JAMB number.
- Migration says "not on the JAMB CAPS list": CAPS rows are under another session or the number format differs (the result shows `capsRows` and samples).

## 15 Glossary
**CAPS** — JAMB's Central Admissions Processing System download. **Held / committed / withdrawn** — batch states. **Load cut-off** — the one UTME score under which a CAPS row is not loaded. **In force / instrument** — settings frozen under a CAC minute. **NM / SM / ELG / LOCALITY / PLWD** — admission bases. **Index (exam-screened) programme** — a programme in `screening_exam_programme`, screened by the Post-UTME examination alone. **Screening component / source** — EXAM, CBT, OLEVEL, NONE. **Ceiling** — the maximum O'Level points used to scale to 100. **Relevant subjects** — OLEVEL-scope rule subjects counted first. **Reconsideration** — moving a non-qualified candidate to an open programme.

---

# 3. Post-UTME CBT scheduling, check-in and slip verification  (API: admissions.PutmeController, verify.VerifyController `/putme/{token}`; schemas: putme_exam, putme_day, putme_slot, putme_exam_centre, cbt_centre, cbt_room, cbt_workstation, screening_batch (V260 columns), screening_assignment, putme_event; pages: admissions/putme/**, verify/putme/[token])

## 1 Purpose
One examination event per session is set up with its days, time slots and CBT centres/rooms (workstations numbered "Computer 001…"); places = days × slots × rooms. Eligible candidates (paid, submitted, programme exam-screened) are batched into those places by a strategy, the schedule is validated and published — which tells every candidate and makes the slip visible — and the door checks candidates in by scanning the slip's QR. Every seating is kept (`screening_assignment` ACTIVE/SUPERSEDED/CANCELLED) and every act is on a write-once trail (`putme_event`).

## 2 Users and roles
`PutmeController.java:46-48`: `READERS` = academic, registrar, dregistrar, records, bursar, ict, admin, super; `OFFICE` = academic, registrar, dregistrar, super (setup, generate, publish, move, unschedule, batch state, confirm-schedule); `DOOR` = academic, registrar, dregistrar, records, ict, super (lookup, check-in, attendance). Public: `GET /api/v1/verify/putme/{token}` (SecurityConfig `/api/v1/verify/**`).

## 3 Navigation
"Post-UTME CBT Schedule" `t/putme-cbt` → `/admissions/putme` in the menus of academic, registrar, ict, admin (Admissions group) and records, dregistrar, super (Academic group). Sub-pages reached by buttons: `/admissions/putme/setup`, `/candidates`, `/batches/[id]`, `/checkin`. Public page `/verify/putme/{token}` from the slip's QR (also reachable from `/verify`).

## 4 Screens
- **Post-UTME CBT Schedule** (`putme/Dashboard.tsx`): session select; buttons **Setup**, **Candidates**, **Check-in Desk**; exam note with state pill and **Generate Batches / Generate again** (needs capacity), **Publish and notify** (disabled while validation errors stand), **Reopen for scheduling**, **Mark completed** (each via a modal with a **Note for the record**; `POST …/putme/generate|publish|exam/state`); "No programme is named as screened by examination this session, so nobody is eligible" when `screening_exam_programme` is empty; tiles; **Validation report** (errors/warnings from `putme_validate`); **Where the candidates stand** (status counts); by faculty, by examination day, by centre, by programme; **Batches** table (S/N, Batch, Day, Time, Centre · room, Capacity, Assigned, Checked in, State) with Excel/print.
- **Examination setup** (`setup/Setup.tsx`): **The examination** — Name (required), First day, Last day, Report before (minutes, 0–240), Sitting (minutes, 10–600), Buffer between batches, Registration deadline, Batching strategy (PROGRAMME | DEPARTMENT | FACULTY | ALPHABETICAL | APPLICATION_NO | BALANCED), Keep a programme together, Enquiries contact, Examination instructions, Venue instructions; **Create/Save the examination** (`PUT …/putme/exam`). **Programmes screened by examination** (read; named under Admission Settings). **CBT centres and rooms** — **Add a centre** modal (Code ≤ 12 `^[A-Z0-9-]{2,12}$`, Name, Location, Address, Contact person, Contact phone or email, State), rooms modal (Code, Name, Capacity 1–2000, Workstations ≤ capacity, State; workstations numbered on save by `cbt_room_workstations`), workstation toggle grid (`PUT …/workstations/{id}`). **Centres this examination uses**, **Examination days** (add/remove dates), **Time slots** (Code, From, To; auto-suggest from duration + buffer), **Places** table. Locked after publish ("Places cannot be changed under a published schedule").
- **Candidates** (`candidates/Candidates.tsx`): filters Standing (Everyone / Eligible / Ready, not seated / Scheduled / each status), Faculty, Department, Programme, Batch, Centre, Search; paged table with checkboxes for OFFICE, **Move n to a batch** (modal: Batch, Reason required) / **Unschedule n** (Reason), **Confirm** for `schedule_review` rows, **Trail** modal (seatings history and events); Excel/PDF.
- **Batch** (`batches/[id]/Batch.tsx`): header with state pill; **Move n to another batch**, **Postpone**, **Cancel batch** (Reason required → `POST …/batches/{id}/state`), **Attendance sheet (Excel)**, **Print attendance sheet**, **Check-in desk**; seats table with photograph, attendance, examination status, signature line, and **Mark** (DOOR) modal (Attendance, Examination, Remarks "Required for a disqualification"). Notes for DRAFT ("Candidates are not told and see no slip until the schedule is published") and postponed/cancelled batches.
- **Check-in desk** (`checkin/Checkin.tsx`): one autofocused box "Slip QR, application number or JAMB number" (a scanner types the verify URL; the token is extracted), **Find** (`GET …/putme/lookup?key=`); the record card with photo and status; verdicts: "Not seated in any batch", "Seated on {day}, not today", "Already checked in at … A second arrival on this slip is an impersonation", "Disqualified", or green "Seated today · batch B, seat NNN" with **Check in** (`POST …/putme/checkin`); then **Seated, started**, **Completed**, **Absent**, **Disqualify** (`POST …/putme/attendance`); "Sitting today" batch list.
- **Public verification** (`verify/putme/[token]/page.tsx`): crest card "Post-UTME examination slip verification"; green "Genuine slip — this is the University's record" with photo, name, application/JAMB numbers, programme, exam, Batch, Day, Time, Centre, Room, Seat, Attendance and "Checked in at …"; red "Genuine slip — but the batch is postponed/cancelled"; red "Not verified — No published examination slip matches this code" for unknown tokens or DRAFT batches.

## 5 Workflow and statuses
- `putme_exam.state`: DRAFT → CONFIGURING → OPEN_FOR_SCHEDULING → SCHEDULING_IN_PROGRESS (set by `putme_generate`) → SCHEDULED (set only by `putme_publish`; the state endpoint refuses SCHEDULED: "A schedule is published, not declared.") → ONGOING → COMPLETED; CANCELLED. Strategy CHECK as above; defaults check-in 30, duration 120, buffer 30, keep_programme true.
- Candidate eligibility (`putme_eligibility`): NOT_ELIGIBLE (candidate withdrawn/declined/lapsed; programme not exam-screened; no exam-screened programme named), DISQUALIFIED, EXAM_COMPLETED, ABSENT, RESCHEDULED, SCHEDULED, PAYMENT_PENDING, DOCUMENT_PENDING (not submitted), RESCHEDULE_REQUIRED (earlier seating ended with reason POSTPONED…), READY_FOR_SCHEDULING.
- `screening_batch.state`: DRAFT (generated) → PUBLISHED (publish) → POSTPONED | CANCELLED (`putme_batch_state`, unseats everyone with the reason, notifies if it was published).
- `screening_assignment.state` ACTIVE → SUPERSEDED (moved) | CANCELLED (unseated); `attendance` NOT_CHECKED_IN → CHECKED_IN → PRESENT | ABSENT | DISQUALIFIED; `exam_status` NOT_STARTED → IN_PROGRESS → COMPLETED | ABSENT | DISQUALIFIED. The trigger `screening_assignment_sync` on `application.screening_batch_id/seat` writes these rows and links the workstation by seat number; `reason` comes from the setting `moaum.putme_reason`.
- Generation: places from `putme_capacity` (active days × active slots × exam centres' active rooms; capacity = operational workstations else room capacity); candidates READY/RESCHEDULE_REQUIRED ordered by strategy; batches labelled `B001…` per place, seats `001…`; returns batches/seated/unseated. Publish requires zero validation errors and at least one live batch; notifies each candidate in a DRAFT batch, sets exam SCHEDULED and `published_at`.
- Programme change after seating (`trg_putme_programme_change`) sets `schedule_review`, logged PROGRAMME_CHANGED; the desk confirms or moves.

## 6 Business rules (verbatim)
`PUTME_NO_EXAM` "No Post-UTME examination is set up for {session}."; `PUTME_STRATEGY`; `PUTME_STATE`; `PUTME_PUBLISH`; `PUTME_SLOT` "Slot X ends before it starts."; `PUTME_ATTENDANCE`, `PUTME_EXAM_STATUS`. SQL: "the schedule of {exam} is {state}; candidates are moved one by one, or a batch postponed" (generate after SCHEDULED); "the examination has no place to seat anyone: name its dates, its slots and its centres with rooms first"; "the schedule cannot be published: {errors}" / "nothing to publish: generate the batches first"; `putme_move`: "a move carries its reason", "that batch is not open for seating", "the candidate is not eligible for seating: {why}", "ROOM CAPACITY EXCEEDED: batch B is full (n of n)", "no free seat in batch B"; `putme_unschedule` "unscheduling carries its reason"; `putme_batch_state` "a batch is postponed or cancelled", "say why the batch is postponed"; `putme_checkin` "the candidate is not seated in any batch", "batch B is draft; check-in is at a published batch", "already checked in at HH:MM", "the candidate is disqualified"; `putme_history_is_written_once` "the Post-UTME trail is written once". Validation codes: ERROR CAPACITY, DUPLICATE, ROOM_CLASH, INELIGIBLE, UNPAID, UNSUBMITTED, UNPLACED_BATCH; WARNING UNSCHEDULED, REVIEW, NO_WORKSTATION. CHECKs: `ck_pe_minutes`, `ck_pe_dates`, `ck_cr_capacity` (workstations ≤ capacity ≤ 2000), `ck_batch_capacity` 1–5000, `ck_batch_times`, UNIQUE (session,label), (exam,code) slots, (room,number) workstations.

## 7 Notifications
See module 1 §7 rows for publish/move/unschedule/postpone/cancel — all Email + SMS via `notify_applicant`, only when the batch is (or was) PUBLISHED.

## 8 Reports, exports and documents
Batches Excel/print (`brandedXlsx`, serial `CBT`), candidates Excel/PDF, per-batch **Attendance Sheet** Excel and print (photograph, attendance, signature line), slip PDF (module 1) with QR → public verification page returning name, photo, batch, day, time, centre, room, seat, attendance.

## 9 Configuration
`putme_exam` row per session (name UNIQUE per session); centres/rooms are University-wide (`cbt_centre.code` UNIQUE) and reused across sessions; days/slots/centres per exam; exam-screened programmes from Admission Settings (`screening_exam_programme`). Local DB has only test residue (seven "ICT CBT Centre NNNN" centres, one 2097/2098 exam).

## 10 Data
`putme_exam` → `putme_day` (exam_id, held_on, active), `putme_slot` (code, starts/ends, ord, active), `putme_exam_centre` (active); `cbt_centre` → `cbt_room` → `cbt_workstation` (operational; never deleted); `screening_batch` gains exam_id, centre_id, room_id, slot_id, state, ordinal, note; `screening_assignment` (application, batch, seat, workstation, state, reason, assigned/ended by, checked_in, attendance, exam_status, remarks); `putme_event` write-once (exam, batch, application, action, from/to, note, actor, office). All audit-attached. `application.putme_token` = the slip's QR token (16 hex, unique, generated at row creation by default).

## 11 Scheduled jobs and integrations
None. The check-in reads a QR scanner as keyboard input; no external CBT engine integration exists (scores are uploaded separately, module 2).

## 12 Security notes
`/api/v1/verify/putme/{token}` is public, unauthenticated and **not rate-limited** (no limiter found in `verify` or `platform`); it returns a photo and personal data for a valid 64-bit token, nothing for DRAFT batches. The door's lookup also accepts application or JAMB numbers, so a token is not required at the desk (DOOR guard applies). Every seating change requires a reason, kept on the assignment and the trail.

## 13 Implementation status

| Feature | Status | Evidence | Notes |
|---|---|---|---|
| Exam setup, centres, rooms, workstations, days, slots | IMPLEMENTED | `PutmeController.java:150-320`, `setup/Setup.tsx` | |
| Generate / validate / publish / reopen / complete | IMPLEMENTED | `putme_generate/validate/publish`, `Dashboard.tsx:70-73` | |
| Candidates list, move, unschedule, confirm review, trail | IMPLEMENTED | `candidates/Candidates.tsx` | |
| Batch page, postpone/cancel, attendance sheet, marking | IMPLEMENTED | `batches/[id]/Batch.tsx` | |
| Check-in desk (QR / number) | IMPLEMENTED | `checkin/Checkin.tsx`, `putme_checkin` | |
| Public slip verification | IMPLEMENTED | `VerifyController.java:324-362`, `verify/putme/[token]/page.tsx` | no rate limit |
| `keep_programme`, `registration_deadline`, `kind` fields | CONFIGURED BUT UNUSED | columns saved by `saveExam`; not read by `putme_generate` or eligibility | stored only |
| ONGOING state | PARTIALLY IMPLEMENTED | allowed and displayed; nothing moves an exam to ONGOING automatically | manual via state endpoint |

## 14 Common problems and troubleshooting
- "Generate" disabled / "has no place to seat anyone": add days, slots and at least one active centre with an active room to the exam.
- Everyone NOT_ELIGIBLE "No programme is named as screened by examination": add the programmes under Admission Settings → O'Level grading → Programmes screened by examination.
- Publish refused: read the validation report; CAPACITY often follows a room's workstation count being lowered after generation.
- Candidate sees no slip after generation: batches are DRAFT until **Publish and notify**.
- "check-in is at a published batch" / "Seated on …, not today": the batch is DRAFT/postponed or sits another day.
- "already checked in at …": treat as possible impersonation per the desk's note.
- Verification page says "Not verified" for a real slip: the batch is DRAFT, was cancelled and re-generated (token unchanged but no seat), or the token was mistyped.

## 15 Glossary
**Place** — one room in one slot on one day. **Batch** — the group seated in a place (`B001…`). **Seat / workstation** — `001…` and the numbered computer it maps to. **Strategy** — the order candidates are dealt into places. **Schedule review** — a seating flagged after the candidate's programme changed. **Trail** — `putme_event`, written once. **Slip token** — `application.putme_token`, what the QR carries.
