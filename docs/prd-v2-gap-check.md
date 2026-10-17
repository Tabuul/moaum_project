# PRD v2.0 gap check

The Product Requirements Document v2.0 (12 October 2026, written against `main` at 204a7f43 with migrations V001–V401) checked
against `main` at 63a0045b with migrations to V503, on 16 October 2026. Updated 17 October 2026: items 1, 2, 4 and 5 of section A are
closed by V508–V511 (below).

The PRD marks every requirement not yet met as OPEN, PARTIAL or PLANNED, and lists them in its section 10.2. This note says where
each stands now, what else is still open from `docs/portal-gap-audit.md`, and where the PRD no longer describes the portal.

## A. The PRD's open items, today

| # | PRD item | Status on 16 Oct 2026 | What is missing | Effort |
|---|---|---|---|---|
| 1 | **FR-PLT-08** API keys are issued but not checked on incoming requests | **Closed by V511** (17 Oct): keys are checked on the integration door (`/api/integration/v1`, header `X-API-Key`) within the consumer's scopes (a list, `apimgmt.scope`) and daily quota; the first read is the student status lookup (`students:status`, minimal fields); every call is logged (`apimgmt.request_log`). Before: | `apimgmt/ApiKeysController` issues, hashes and lists keys; no filter reads a key on a request, so a key grants and denies nothing. Either wire a filter that admits a key to its scope (read-only integration endpoints), or stop issuing keys until it is. | Medium |
| 2 | **FR-HR-04** an employment record cannot be created from the portal | **Closed by V510** (17 Oct): Human Resources → New Appointments makes the employment record from a form or an Excel upload, each row checked first (`hrm.appointment_check`), and sets the salary grades it names (`hrm.set_grade`). Before: | `hrm.employment` is read by HR, payroll, identity cards and the HOD screen, but rows arrive only by import (or the demo). HR has no "new appointment" form or upload. | Medium |
| 3 | **FR-IAM-06** single sign-on (Keycloak, MFA) coded, not deployed | **Still partial** | A deployment decision for the University (a Keycloak realm and its settings), not code. | — (University) |
| 4 | **FR-PG-05** a PG supervisor cannot be ended or replaced, nor a panel member removed, from a screen | **Closed by V509** (17 Oct): the research desk ends or replaces a supervisor and removes a panel member, each on a date with a reason, the history kept; the candidate is told of a supervisor change. Before: | `PgResearchController` adds a supervisor and a panel member; nothing ends, replaces or removes one. | Small–medium |
| 5 | **FR-REG-07** overload approval and probation ceiling not configured; a registration created by an office has no screen | **Overload closed by V508** (17 Oct): the student asks on Course registration, the Head of Department of the student's department grants a ceiling (at most the Academic Office's extra, 6 by default) or refuses on Overload Requests, and `registration.unit_rule` reads the grant as the semester's maximum. The office-created registration has its screen since V516 (17 Oct): the Registry registers a student late on the student's behalf (Late Registration), only the window and add and drop set aside. The probation ceiling remains (a value for the University to set). Before: | The probation ceiling can be set per level on Session & Semester Setup (`probation_max_units`) but none is set. **No overload approval exists anywhere**, yet a registration above the maximum is refused with "obtain an overload approval from the Head of Department": a dead end for, say, a final-year student with carry-overs. The office-created registration endpoint (`POST /registration/course-registrations`) still has no screen; ICT Support's override (V346) covers additions made on a student's behalf. | Medium (overload) |
| 6 | **FR-GOV-04** cloud-residency and research-ethics screens are frameworks only | **Still planned** | `/cloud` and `/ethics` say so themselves; no live data behind them. | Low priority |

## B. Still open in the portal gap audit

| Gap | What | Status |
|---|---|---|
| GAP-011 | Three append-only logs (`credentials.download_log`, `lookup_miss`, `verification`) use integer auto-increment keys, against P7 | Open, accepted (LOW) |
| GAP-018 | Optional panels refused on otherwise usable pages (withdrawals on Students for HOD/Dean/Faculty Officer/Admin; returns, snapshots, trends and enrolment on Reports; payroll on Staff; grants on Research projects) | Open, accepted (LOW) |
| GAP-024 | Transcripts, certificates and admission letters also verify by their sequential document number, so the public fields can be listed by stepping numbers | **Needs the University's decision** |

## C. Where the PRD no longer describes the portal (for v2.1)

| PRD text | What the portal does now |
|---|---|
| FR-REG-02 "within the level's unit limits (18–24 by default)" | The minimum is the curriculum's — CCMAS 15, BMAS 18 — set by the Director of ICT per session and semester on Course Registration Settings; the maximum stays the level's (V495). |
| FR-REG-04 "The Head of Department approves or returns a registration" | Approval is set per session: Head of Department, or automatic approval of a registration that passes the rules, with the student's reset (V491). |
| FR-TCH-05 "the industrial-training semester is one course of six units outside the normal unit range" | Only the attachment semester (the SIWES course is the programme's only required course in it) is the SIWES course alone; a practicum beside required courses is an ordinary course (V503). |
| FR-CAT-06 / FR-CBT-10 "A BSU-/MOAU- pair, once linked by a person" | Codes are chosen by cohort and pairs are no longer linked (V402). |
| FR-REG-04 / FR-RES-01 "the course form and examination card are documents" | The examination card has its own rule (approved registration, fees not refused, released) and carries every registered course; the GST & EPS examination permit is a separate document (V492, V501). |
| FR-FIN-10 "Fee history from the old portal is imported once. Duplicates are skipped" | Old Fees History is the one way in, keyed by the old portal's payment number; Payment History Upload is retired; the reset reverses the ledger and keeps what it deleted (V498, V499). |
| FR-MAT-03 graduation | Finalists follow each programme's final level on the register (and the CCE route's); postgraduate graduands are judged by coursework and research (V493). |
| FR-MAT-04 identity cards | The Security Unit alone prints and issues identity cards (GAP-005, decided 16 Oct 2026). |
| Section 9 "241 properties", "80 integration-test classes" | check.sql asserts 343 properties; 126 integration-test classes. |
| Appendix A "41 offices" | The register now holds more (the Preliminary Science office, V446; the sandwich office, V469). |
| Basis V001–V401 | V503 (V490–V503 include the PAYDirect claims, the minimum load, the old-fees reset, the examination card rule). |

## D. Recommended next, in order

1. ~~**Overload approval (FR-REG-07).**~~ Done (V508). Students already meet the refusal that names it. A Head of Department grants a named student a
   higher maximum for one semester, with a reason, on the audit spine; the unit rule reads it.
2. ~~**PG supervisor and panel changes (FR-PG-05).**~~ Done (V509). End or replace a supervisor and remove a panel member, each with its date and
   reason, keeping the history.
3. ~~**A new appointment in HR (FR-HR-04).**~~ Done (V510). A form and an upload that create the employment record the rest of the portal reads.
4. ~~**API keys (FR-PLT-08).**~~ Done (V511). Wire the filter for a first read-only integration, or stop issuing keys until then.
5. **PRD v2.1.** Bring section C into the document.
6. **GAP-024.** The University's decision whether a document number alone should verify.
