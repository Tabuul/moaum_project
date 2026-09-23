# Go-Live Readiness — MOAUM Portal

Rev. Fr. Moses Orshio Adasu University, Makurdi.

Everything that must be set before the portal opens to students, staff and applicants — **in the order it has to happen**. A later phase depends on the ones above it. An interactive version of this checklist is published as an artifact (link shared separately); this file is the versioned copy.

> **One session current, one semester open.** Nothing registers, examines or classifies until a session exists, is made current under a Senate minute, and its semester windows are set.

## Sharp edges — read before launch day

- **The transfer fee has no default.** Until the Bursary sets it on `/finance/fees`, a student can apply to transfer but cannot pay — so no transfer proceeds.
- **The exam session opens over _approved_ registrations only.** A student sees a paper only for a course on their approved registration; an unapproved add shows nothing to sit.
- **Only the Main sitting is supported.** Re-sit and Special sittings are refused for now — the create form offers Main only. (Full second-sitting support is a separate, larger change.)
- **Catchment LGAs drive the Locality quota.** If you are not admitting on catchment, clear the LGAs or that quota admits from them.
- **English is counted automatically in UTME subjects.** Never list it; use `N of A/B/C` for "any N of a set" (e.g. `Biology, 2 of Chemistry/Mathematics/Physics`).
- **A course added during add/drop on an approved registration is examinable at once** — it lands on the lecturer's score sheet immediately.

---

## 1 · Calendar & session — *Academic Office*
The spine everything else hangs on.

- [ ] Create the academic session and make it current under a Senate minute — `/calendar` · **done when** the Current session tile names the session
- [ ] State each semester's windows — lectures, registration open/close, late registration, examinations, results due, query window — `/calendar` · **done when** the Semesters table shows the open semester with every date set
- [ ] Roll the register into the session (promote continuing students), or Enrol all to match a re-uploaded cohort — `/calendar` · **done when** continuing students are enrolled at their level in the new session

## 2 · Structure — *Registry / ICT*
Faculties, departments, programmes on the register.

- [ ] Upload faculties and departments — `/structure/faculties` · **done when** every department shows under its faculty
- [ ] Upload programmes, each bound to its faculty and department — `/structure/programmes` · **done when** the programmes list is complete and none is archived by mistake

## 3 · Admission policy — *Admissions*
The rules the merit engine applies.

- [ ] State each programme's relevant O'Level subjects and any credit-pass allowances — `/admissions/settings`
- [ ] Configure required UTME subjects per programme (comma = all; `/` = any one; `N of A/B/C` = any N) — `/admissions/settings` · **done when** each programme shows its UTME subjects (blank = not checked)
- [ ] State the O'Level grading scheme for the session — `/admissions/settings`
- [ ] State the general UTME cut-off for loading the lists — `/admissions` · **[policy]**

## 4 · CAPS intake & admission — *Admissions*
From the JAMB list to names on the register.

- [ ] Upload the JAMB / CAPS list for the session — `/admissions/caps`
- [ ] Map any JAMB programme aliases to your programme codes — `/admissions/caps` · **done when** no candidate is stranded on an unmapped programme
- [ ] Upload Post-UTME screening scores and release them — `/admissions/scores`
- [ ] Record the merit list per programme, release offers, bring the admitted onto the register — `/admissions/merit` · **[critical]** · **done when** admitted candidates have an admission number

## 5 · Courses & offerings — *Registry / Departments*
So registration shows real courses, not demo data.

- [ ] Upload the course catalogue with each course's Core / Elective basis per programme — `/catalogue/upload` · **done when** a borrowed elective reads as Elective, not Core
- [ ] Open the session to turn every uploaded course into an offering for the semester — `/catalogue/upload` · **done when** a student's My courses shows their real programme and level courses

## 6 · Lecturer allocation — *Departments*
A score sheet is generated only for an offering that has a lecturer.

- [ ] Allocate a lecturer to every offering for the semester — `/allocate` · **done when** offerings without a lecturer = 0 when the exam session is opened

## 7 · Fees & clearance — *Bursary*
What a payment costs, and what it releases.

- [ ] Upload the Council-approved fee structure for the session — `/finance/fees`
- [ ] Put the clearance scheme in force under a minute — `/finance/fees` · **[critical]** · **done when** a payment actually releases registration, the exam and results
- [ ] State the applicant and Post-UTME fees (screening, portal charge, acceptance, checking) — `/finance/fees`
- [ ] Set the inter-departmental transfer processing fee — there is no default — `/finance/fees` · **done when** the panel reads "Set by the Bursary", not "Not set yet"
- [ ] Wire and test the payment gateway — `/finance/gateways` · **done when** a card / USSD checkout opens against a live reference

## 8 · Photos & records — *ICT Directorate*
Returning students' identity on file.

- [ ] Bulk-upload returning students' passports, named by JAMB number — `/records/migration` · **done when** a student's photo appears on the ID card, receipt, course form and exam card
- [ ] Import biodata and JAMB numbers for returning students — `/records/migration`

## 9 · Accounts & access — *ICT / Registry*
Who can act, and as which office.

- [ ] Confirm staff accounts and offices, and grant the ICT / migration role where needed — `/people`
- [ ] Test one sign-in for each kind — student, staff, applicant — `login` · **done when** each lands on their own side of the portal

## 10 · Dry run — *All offices*
Walk the chain end to end on launch eve.

- [ ] Applicant: apply from a JAMB number, pay Post-UTME, appear for screening — `/apply`
- [ ] Student: sign in, register courses, HOD approves, pay fees, clear — `login`
- [ ] Examinations: open the Main exam session and confirm score sheets generate — `/examinations/sessions` · **done when** the count of generated score sheets matches the offerings
- [ ] Verify: scan a receipt or exam-card QR and confirm it reads genuine — `/verify`

---

*Verify pages are public — scan any receipt or card QR to open `/verify`.*
