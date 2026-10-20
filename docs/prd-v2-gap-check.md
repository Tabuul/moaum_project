# PRD v2.0 gap check

The Product Requirements Document v2.0 (12 October 2026, written against `main` at 204a7f43 with migrations V001–V401) checked
against `main` at 63a0045b with migrations to V503, on 16 October 2026. Updated 17 October 2026: items 1, 2, 4 and 5 of section A are
closed by V508–V511. **Checked again on 20 October 2026 against `main` with migrations to V588**: section A re-verified, section B
unchanged, and section C extended with every change from V504 to V588 that the PRD's text no longer describes.

The PRD marks every requirement not yet met as OPEN, PARTIAL or PLANNED, and lists them in its section 10.2. This note says where
each stands now, what else is still open from `docs/portal-gap-audit.md`, and where the PRD no longer describes the portal.

## A. The PRD's open items, today

| # | PRD item | Status on 20 Oct 2026 | What is missing | Effort |
|---|---|---|---|---|
| 1 | **FR-PLT-08** API keys are issued but not checked on incoming requests | **Closed by V511** (17 Oct): keys are checked on the integration door (`/api/integration/v1`, header `X-API-Key`) within the consumer's scopes (`apimgmt.scope`) and daily quota; the first read is the student status lookup (`students:status`); every call is logged (`apimgmt.request_log`). | — | — |
| 2 | **FR-HR-04** an employment record cannot be created from the portal | **Closed by V510** (17 Oct): Human Resources → New Appointments makes the employment record from a form or an Excel upload, each row checked first, and sets the salary grades it names. | — | — |
| 3 | **FR-IAM-06** single sign-on (Keycloak, MFA) coded, not deployed | **Still partial** | A deployment decision for the University (a Keycloak realm and its settings), not code. | — (University) |
| 4 | **FR-PG-05** a PG supervisor cannot be ended or replaced, nor a panel member removed, from a screen | **Closed by V509** (17 Oct): the research desk ends or replaces a supervisor and removes a panel member, each on a date with a reason, the history kept. | — | — |
| 5 | **FR-REG-07** overload approval and probation ceiling not configured; a registration created by an office has no screen | **Overload closed by V508**, the office-created registration by V516 (Late Registration). **The probation ceiling is still unset**: no level states `probation_max_units` on the live-shaped copy of 20 October 2026 (9 level limits, none with a ceiling). | A value for the University to set per level on Session & Semester Setup; nothing to build. | — (University) |
| 6 | **FR-GOV-04** cloud-residency and research-ethics screens are frameworks only | **Still planned** | `/cloud` and `/ethics` say so themselves; no live data behind them. | Low priority |

## B. Still open in the portal gap audit

| Gap | What | Status |
|---|---|---|
| GAP-011 | Three append-only logs (`credentials.download_log`, `lookup_miss`, `verification`) use integer auto-increment keys, against P7 | Open, accepted (LOW) |
| GAP-018 | Optional panels refused on otherwise usable pages (withdrawals on Students for HOD/Dean/Faculty Officer/Admin; returns, snapshots, trends and enrolment on Reports; payroll on Staff; grants on Research projects) | Open, accepted (LOW) |
| GAP-024 | Transcripts, certificates and admission letters also verify by their sequential document number, so the public fields can be listed by stepping numbers | **Needs the University's decision** |

## C. Where the PRD no longer describes the portal (for v2.1)

Rows marked *(16 Oct)* were in the first check; the rest are changes made since (V504–V588).

| PRD text | What the portal does now |
|---|---|
| FR-IAM-01 / Appendix A "41 offices" | The register holds 45 offices: since the PRD, the Preliminary Science office (V446), the sandwich office (V469) and the Students Account Officer (V520, the school fees set-up and binding beside the Bursary) among them. |
| FR-IAM-05 / FR-SUP-03 "a temporary password or a reset link is the only way support can help" | Also: a reset to the matriculation number that must be changed at the next sign-in, enforced on the server (V485); bulk resets in parts of 1,000, a large one approved by another Head (V559, V563, V565); resets driven by support tickets (V582); no hourly limit at the desk (V526). A reset link goes only to a contact the student has confirmed (V575). |
| FR-CAL-03 "by the clock on the configured date when the readiness checks pass" | The readiness also says what the session's spillover students are charged (SPILLOVER_FEE_LINES, V580); it holds the automatic start only when the Bursar chooses (V585). A week before an automatic start, and the day before while a check is not met, the Registrar's and the Bursar's offices are told what the readiness shows (V585). |
| FR-REC-03 cohorts | The lifecycle is reconciled in batches on the cohort engine (spillover stays active; the officer decides at the maximum; candidates go onto the graduation list, V558). Levels below the engine's are corrected by basis, with the fee effect of every waiting correction worked out first and the fee lines it would leave missing stated in one step (V475, V576, V580, V584). The spillover fee lines are charged by the level or by the cohort, the Bursar's choice (V571). |
| FR-REC-06 / FR-REC-07 programme changes | The inter-departmental transfer is also made in bulk from a department's template (V587), and a student transfers in from or out to another university (V588). Besides the transfer, duplicate programme codes are merged with their students by the Registry or the School of Postgraduate Studies (V574), and a migrated student's placement is corrected by a programme swap prepared by one officer and decided by another, the old placement kept in the programme history (V578). |
| FR-REC-07 contacts | The Registry and the departments upload students' phones and e-mails, filling only what a student lacks (V572). An uploaded contact is held until the student confirms it with a code or the desk confirms it with them; a contact the student refuses is emptied and the uploader told; the uploader is reminded weekly of an upload a month old that still waits, and sees each upload's students (V575, V580, V584). |
| FR-REG-02 "within the level's unit limits (18–24 by default)" *(16 Oct)* | The minimum is the curriculum's — CCMAS 15, BMAS 18 — set by the Director of ICT per session and semester on Course Registration Settings; the maximum stays the level's (V495). A student adds courses outside the menu through Add Other Course, judged by the same rules, carry-overs first (V504). |
| FR-REG-04 "The Head of Department approves or returns a registration" *(16 Oct)* | Approval is set per session: Head of Department, or automatic approval of a registration that passes the rules, with the student's reset (V491). A load below the minimum is accepted or returned with a reason (V505). |
| FR-REG-04 / FR-RES-01 "the course form and examination card are documents" *(16 Oct, revised)* | The examination card has its own rule: the session's fees paid and the semester registered (V567; earlier V501's approval and release tests were dropped), and it carries every registered course; the GST & EPS examination permit is a separate document (V492). |
| FR-TCH-05 "the industrial-training semester is one course of six units outside the normal unit range" *(16 Oct)* | Only the attachment semester (the SIWES course is the programme's only required course in it) is the SIWES course alone; a practicum beside required courses is an ordinary course (V503). |
| FR-CAT-06 / FR-CBT-10 "A BSU-/MOAU- pair, once linked by a person" *(16 Oct)* | Codes are chosen by cohort and pairs are no longer linked (V402). |
| FR-MAT-02 "corrections" | A matriculation number, otherwise permanent, is corrected only by a correction prepared by one officer and decided by another; the old number stays a former number the register, the search and the sign-in still resolve, and is never issued again (V579). |
| FR-MAT-03 graduation *(16 Oct)* | Finalists follow each programme's final level on the register (and the CCE route's); postgraduate graduands are judged by coursework and research (V493). |
| FR-MAT-04 identity cards *(16 Oct)* | The Security Unit alone prints and issues identity cards (GAP-005, decided 16 Oct 2026). |
| FR-FIN-01 fee schedule | The approved structure upload reads the College workbook as it is and replaces only what it names (V535). A session's lines are copied from another (V506), its spillover lines on their own (V580), and a programme's lines at one level from another programme or level (V584). |
| FR-FIN-06 reconciliation | Bank statements are loaded and matched (V545, V546, V552); the bank reconciliation statement is signed by a second officer (V557); a bank double charge or a payment never received is checked with the bank before anything is carried or refunded (V561); a signed month is closed on the ledger (V562). |
| FR-FIN-07 refunds | An overpayment is carried to the next session or refunded, and the student told (V506, V519); a refund is paid into the student's checked account (NUBAN check digit) with the payment's reference and date as evidence (V528, V533, V534); a payment made on the wrong student is moved only inside an approved swap (V527). |
| FR-FIN-08 wallet | The wallet is on the general ledger (V545) and the old portal's e-wallet is reconciled and posted by two Bursary officers (V583). |
| FR-FIN-10 "Fee history from the old portal is imported once. Duplicates are skipped" *(16 Oct)* | Old Fees History is the one way in, keyed by the old portal's payment number; Payment History Upload is retired; the reset reverses the ledger and keeps what it deleted (V498, V499, V502). |
| FR-SUP-04 support tools | An agent may open the student's portal read-only (V521); a ticket from a student with no e-mail is answered by SMS (V565). |
| Section 9 "241 properties", "80 integration-test classes" | check.sql asserts 420 properties; 168 integration-test classes (20 October 2026). |
| Basis V001–V401 | V588. |

## D. Recommended next, in order

1. **PRD v2.1.** Bring section C into the document; it has grown from 11 rows to 22 since 16 October.
2. **GAP-024.** The University's decision whether a document number alone should verify.
3. **The probation ceiling (FR-REG-07).** The University sets a value per level on Session & Semester Setup; until then a student on probation registers up to the level's maximum.
4. **Single sign-on (FR-IAM-06).** A deployment decision: a Keycloak realm, its multi-factor settings and the cut-over date.
5. **Cloud residency and research ethics (FR-GOV-04).** Wire the two framework screens to live data when the University wants them; low priority.

Done since the first check: overload approval (V508), PG supervisor and panel changes (V509), a new appointment in HR (V510), API keys
on the integration door (V511), the office-created registration (V516).
