# Preliminary Science Programme (2026/2027)

Preliminary Science is a **preliminary / remedial programme**, full-time, for candidates seeking later admission into approved
science-based degree programmes. It is not an undergraduate degree. Choosing a target programme under it is an **intended
progression**, never admission into that degree.

It runs on the portal's existing applicant stack: one application system, one fee and gateway path, one O'Level record, one
document store, one notification engine, one programme register and one session model. V446 adds the route, its settings and
its review, and nothing else.

```
Preliminary Science = route PRELIMINARY_SCIENCE (policy.study_route, session 2026/2027, FULL_TIME, entry level 0)
                    + candidate entry_mode PRELIMINARY (no JAMB number)
                    + the Preliminary Science Office (office prelim) reviews; the Academic Office approves and publishes
```

---

## 1. Existing architecture inspected

| Area | What exists | What Preliminary Science uses |
|------|-------------|-------------------------------|
| Preliminary / remedial programmes | Nothing built. V409 has a `PRELIMINARY` programme type with no entry modes ("mapped when the University runs one"). V253 has the HR units PRELIMINARY SCIENCE OFFICE and PRELIMINARY VOCATIONAL & TECHNICAL EDUCATION. | The `PRELIMINARY` programme type now maps entry mode `PRELIMINARY`. Payments are classified to source `PRELIMINARY_SCIENCE`, office `prelim`. |
| Application / applicant | `admissions.candidate` → `applicant_account` → `application` (APP/yy/nnnnnn from `platform.next_number`), sign-in by application number or email, the applicant portal `/applicant/*`. | Reused. The candidate has `entry_mode = 'PRELIMINARY'` and no JAMB number, and gets an ordinary application number. |
| O'Level | `admissions.screening_olevel` (sittings, exam body, number, year, subject, grade), graded with `admissions.grade_rank` and matched with `admissions.subject_same` (the session's subject equivalences). | Reused for one or two sittings. Added: the examination type (SSCE / GCE). |
| Admission | `application.decision`, `decision_released_at`, `candidate.offer_state`, status reading, admission letter (`credentials.issued`). CCE (V379) shows how to put an office review before the Academic Office publishes. | Same decision fields, same release, same letter. The review follows CCE's pattern. |
| Finance / gateway | `admissions.route_fee` (fees per route and session), `admissions.fee_reference`, `admissions.confirm_fee` (gateway-confirmed only), receipts, `reporting.payments` classification (V409). | Reused. The application fee is a `route_fee` row. The form opens only after `confirm_fee` has confirmed the payment, never because the applicant came back from the gateway. |
| Documents | `admissions.application_document` (upload, review PENDING/ACCEPTED/REJECTED, served only to its owner or an authorised desk). | Reused. Added: the kind `PASSPORT_2`, plus a per-route list of required kinds (`prelim_document`). |
| Notifications | One outbox (V425): templates, EMAIL/SMS/PORTAL channels, `platform.tell_applicant`, event-key dedupe, closing reminders (V444). | Reused. Nine `PRELIMINARY_SCIENCE*` templates and a closing-reminder template. |
| Programme hierarchy | `ref.faculty` → `ref.department` → `ref.programme` (`C#####`, category UNDER GRADUATE / POST GRADUATE). | Targets are existing `ref.programme` codes. No programme was created or renamed. |
| Academic session | `policy.academic_session`, `policy.study_route` with a per-route session (`policy.route_session`, V379). | The route's own session is 2026/2027, named by the Academic Office (a route override, not a literal year in code). |
| Portal windows | `policy.portal_window` + `window_act` (Director of ICT), `application_window_guard`, public window list. | New window type `PRELIMINARY_SCIENCE_APPLICATION`. The guard checks each route's own window. |
| Student management | `people.intake_one` puts an admitted candidate on the student register. | **Not used yet.** A Preliminary Science admission does not put anyone on the student register (see 24). |
| RBAC | Offices (`ref.office`, authority `OFFICE_<code>`), `OfficeScope` for Head of Department / Dean, office checks in the database functions. | New office `prelim` (Preliminary Science Office). Every action is checked in the controller **and** in the database function. |
| Audit | `audit.attach` spine on every state table, `moaum.reason` / actor / office from `AuditContextHolder`. | All five new tables are on the spine. Review steps also go to a write-once history. |
| Reporting | Desk lists, branded XLSX/print exports, `reporting.payments`. | Desk figures, filtered lists and reports, scoped for Heads and Deans. |

## 2. Existing Preliminary Technology implementation reused

**None exists.** The codebase has no Preliminary Technology (or Preliminary Technology & Industrial Studies) module, route,
table or page. The only traces are the HR unit name PRELIMINARY VOCATIONAL & TECHNICAL EDUCATION (V253) and V409's empty
`PRELIMINARY` programme type. Nothing could be reused from it.

The nearest working precedent is the **CCE route** (V379, V404): a route with its own session, applicants without the
Post-UTME path, an office review, and an Academic Office publication. Preliminary Science follows that pattern. The target
"B.Sc Technology and Industrial Studies" is not on the programme register either (see 23).

## 3. Database entities reused

`admissions.candidate`, `applicant_account`, `application`, `screening_answer` (biodata), `screening_olevel`,
`application_document`, `fee_reference`, `route_fee`; `policy.study_route`, `portal_window`, `portal_window_message`,
`academic_session`; `ref.programme`, `ref.department`, `ref.faculty`, `ref.office`; `platform.notice_template`, `notice`,
`next_number`; `credentials.issued`; `finance.programme_type`, `payment_classification`; the audit spine.

## 4. Database entities added

| Entity | Purpose |
|--------|---------|
| `admissions.prelim_programme` | The programme's description, the completion statement, the application steps, and the O'Level rule as data: minimum credits (4), maximum sittings (2), minimum core credits (3), core subjects (Mathematics, Chemistry, Physics, Biology), lowest credit grade (C6), and the completion rule (5 credits including Mathematics, Physics, Chemistry and Biology). Versioned. |
| `admissions.prelim_target` | The target programmes, in the notice's groups and order. Each is an existing `ref.programme` code (state `MAPPED`) or recorded as `MISSING` with no code. A guard trigger refuses a non-undergraduate or ended programme. |
| `admissions.prelim_document` | The documents the route asks for, with labels and hints; the second O'Level statement is required only for two sittings. |
| `admissions.prelim_review` | One row per application: target, O'Level verification, the eligibility the backend works out (status, credits, core credits, sittings, checks, reasons), remediation (status, subjects, credits short), and the review steps with who/when. |
| `admissions.prelim_review_event` | The write-once history of every step: who, which office, from what state to what, and the note. |
| Columns | `admissions.candidate.sex` (no JAMB record carries it) and `admissions.screening_olevel.exam_type` (SSCE / GCE). |
| Office | `prelim` — Preliminary Science Office (institution scope). |

All primary keys are UUIDs (`gen_random_uuid()`). The business application number is the shared APPLICATION series
(APP/yy/nnnnnn), never a database sequence.

## 5. Migrations

- `db/V446__preliminary_science_programme_2026_2027_on_the_shared_applicant_stack.sql` adds the tables, the route-aware
  restatements of the shared functions (window state/guard/act, application session, fee references, `confirm_fee`,
  admission status, admission letter, status-checking exclusion), the `prelim_*` functions, and the seeds.
- `db/check.sql` adds a V446 block (284 properties). It covers registration without JAMB, the fee first, awaiting results
  refused, every eligibility case, target rules, the window, the four-eyes rule, publication, the letter, notices, Post-UTME
  exclusion and classification.
- `db/verify.sql` sets the office count to 43.

Verified on a database shaped like the commit (HEAD's V431–V445 + V446): **FOUNDATION GREEN — 284 properties**, and
`verify.sql` passes.

## 6. APIs reused

`POST /api/v1/applicant/sign-in` / `sign-out` / `forgot` / `reset`, `GET /api/v1/applicant/me`,
`POST /api/v1/applicant/me/fee-references` (application fee reference), the existing gateway confirmation (WebPAY/PAYDirect →
`admissions.confirm_fee`), `GET /api/v1/applicant/me/receipts/{reference}`, `POST /api/v1/applicant/me/documents` and
`GET /api/v1/applicant/me/documents/{id}/content`, `POST /api/v1/applicant/me/submit` (which takes a Preliminary Science
application into `prelim_submit`), the ICT window endpoints (`PortalWindowController`), and the notification outbox.

## 7. APIs added

Applicant (`PrelimApplicantController`):

| Method | Path | |
|--------|------|-|
| GET | `/api/v1/public/preliminary-science` | Public: programme, targets, documents, fee as the Bursary stated it, window state |
| POST | `/api/v1/applicant/preliminary/register` | Public, window-guarded: start an application (no JAMB number) |
| GET | `/api/v1/applicant/me/preliminary` | The applicant's form, eligibility and status |
| PUT | `/api/v1/applicant/me/preliminary/biodata` · `/olevel` · `/target` | Save the form (fee confirmed first) |
| POST | `/api/v1/applicant/me/preliminary/withdraw` | Withdraw before a decision |

Desk (`PrelimDeskController`, `/api/v1/admissions/preliminary`): `GET summary`, `GET applications` (paged, filtered,
searched on the server), `GET applications/{id}`, `GET applications/{id}/documents/{documentId}/content`,
`POST applications/{id}/act`, `POST applications/{id}/verify-olevel`, `POST applications/{id}/documents/{documentId}/review`,
`POST applications/{id}/target`, `POST applications/{id}/remediation`, `POST publish`, `GET payments`, `GET analysis`,
`GET config`, `PUT config/rules`, `POST config/targets`, `POST config/targets/{id}`, `PUT config/documents/{kind}`,
`PUT config/fee`, `GET programmes`.

## 8. Frontend pages and components

| Route | Who | File |
|-------|-----|------|
| `/preliminary-science` | Public | `app/preliminary-science/page.tsx` — description, targets by group, O'Level requirement, completion rule, documents, fee (from the API), window state, Apply |
| `/preliminary-science/apply` | Public | `PrelimRegister.tsx` — start an application; the BFF route `app/api/auth/applicant/preliminary-register` signs the applicant in |
| `/applicant/preliminary` | Applicant | `PrelimApplicantForm.tsx` — fee, biodata, O'Level (one or two sittings), target (searchable), documents, eligibility as the server worked it out, submit, status, withdraw |
| `/applicant/preliminary/pdf/form`, `/pdf/letter` | Applicant / desk | Application form (with passport) and admission letter through `lib/document` |
| `/preliminary` | prelim, academic, registrar, HOD, Dean | `PrelimDesk.tsx` + `PrelimDetail.tsx` — figures that filter the list, filters, paging, export, the review modal |
| `/preliminary/config` | academic (rules/targets/documents), bursar (fee), readers | `PrelimConfig.tsx` |
| `/preliminary/reports` | Desk readers | `PrelimReports.tsx` — analysis by target, eligibility, remediation, sittings, sex, state of origin; payments |

Menus: `prelim` and `prelimapplicant` menus. Entries are on the Academic Office, Registrar, Bursary (fees), Head of
Department and Dean menus. The existing applicant pages (`/applicant`, `/applicant/apply`, `/applicant/fee`, the status
letter) send a Preliminary Science applicant to their own form.

## 9. Preliminary Science configuration

Route `PRELIMINARY_SCIENCE`: "Preliminary Science Programme", FULL_TIME, entry level 0, session 2026/2027 named by the
Academic Office. Programme type `PRELIMINARY` (V409). The rule, the targets and the documents are data in
`prelim_programme` / `prelim_target` / `prelim_document`. The Academic Office changes them on `/preliminary/config` with a
reason, and every change is on the audit spine. The duration on the route row (1 year) is a placeholder that is never
printed (see 24).

## 10. Target programme mappings

Mapped by exact name, after case and punctuation are normalised, to existing undergraduate programmes. No programme was
created or renamed.

| Group | Notice name | Code | Register name |
|-------|-------------|------|---------------|
| Health / Medical | Medicine and Surgery (M.B.B.S) | C00061 | MBBS |
| | Bachelor of Medical Laboratory Science (BMLS) | C49412 | BACHELOR OF MEDICAL LABORATORY SCIENCE (BMLS) |
| | B. Nursing Science | C35147 | BACHELOR OF NURSING SCIENCES |
| | B.Sc Anatomy | C29132 | B.Sc. HUMAN ANATOMY |
| | B.Sc Radiography & Radiation Science | C49411 | B.Sc. RADIOGRAPHY AND RADIATION SCIENCE |
| | B.Sc Doctor of Pharmacy (Pharm.D) | C73770 | DOCTOR OF PHARMACY |
| | B.Sc Physiology | C18115 | B.Sc. HUMAN PHYSIOLOGY |
| Science / Technology | B.Sc Environmental Management & Toxicology | C52395 | B.Sc. ENVIRONMENTAL MANAGEMENT AND TOXICOLOGY |
| | B.Sc Computer Science | C00023 | B.Sc. COMPUTER SCIENCE |
| | B.Sc Statistics | C56345 | B.Sc. STATISTICS |
| | B.Sc Mathematics | C00028 | B.Sc. MATHEMATICS |
| | B.Sc Physics | C00029 | B.Sc. PHYSICS |
| | B.Sc Chemistry | C00022 | B.Sc. CHEMISTRY |
| | B.INDCHM. Industrial Chemistry (shown as "B.Sc Industrial Chemistry") | C22229 | B.Sc INDUSTRIAL CHEMISTRY |
| | B.Sc Biology | C00060 | B.Sc. BIOLOGY |
| | B.Sc Plant Science and Biotechnology | C82347 | B.Sc. PLANT SCIENCE AND BIOTECHNOLOGY |
| | B.Sc Microbiology | C52295 | B.Sc. MICROBIOLOGY |
| | B.Sc Zoology | C49638 | B.Sc. ZOOLOGY |
| | **B.Sc Technology and Industrial Studies** | — | **MISSING TARGET PROGRAMME** |
| Built Environment / Design | B.Sc Architecture | C51900 | B. Sc. ARCHITECTURE |
| | B.Sc Landscape Architecture | C72222 | B. Sc. LANDSCAPE ARCHITECTURE |
| | B.Sc Interior Design | C40831 | B. Sc. INTERIOR DESIGN |
| Science Education | B.Sc Ed. Computer Science | C67895 | B.Sc. (ED) COMPUTER SCIENCE |
| | B.Sc Ed. Integrated Science | C44826 | B.Sc. (ED) INTEGRATED SCIENCE |
| | B.Sc Ed. Chemistry | C00014 | B.Sc. (ED) CHEMISTRY |
| | B.Sc Ed. Mathematics | C00016 | B.Sc. (ED) MATHEMATICS |
| | B.Sc Ed. Biology | C00012 | B.Sc. (ED) BIOLOGY |
| | B.Sc Ed. Physics | C00017 | B.Sc. (ED) PHYSICS |

27 mapped, 1 missing. A missing target is listed for the Academic Office and is never offered to applicants. An applicant
can only pick a mapped, active, undergraduate target; free text is refused. A Head of Department or Dean sees only the
applications aimed at their own programmes.

## 11. O'Level eligibility rules

Worked out only by the backend (`admissions.prelim_evaluate`), on every save and at submission; the frontend displays it.

- at least **4** credit passes (A1–C6), with the lowest credit grade configurable;
- at most **2** sittings, each kept apart (body, type, number, year). The better grade of a subject counts once;
- at least **3** credits among Mathematics, Chemistry, Physics and Biology, matched through the session's subject equivalences;
- **an awaiting result is not eligible.** An awaiting sitting or an `AR` grade is refused when saved, and no result means
  `RESULT_REQUIRED`;
- an O'Level the Office marks INVALID becomes `INVALID_RESULT`.

Statuses: `ELIGIBLE`, `ELIGIBLE_WITH_REMEDIATION`, `NOT_ELIGIBLE`, `RESULT_REQUIRED`, `INVALID_RESULT` (plus the column's
`PENDING_REVIEW` / `REQUIRES_VERIFICATION`). Meeting the minimum does not admit anyone: the Office reviews, someone else
approves, and the Academic Office publishes.

## 12. Remediation rules

Only the completion rule the notice states: **five credits including Mathematics, Physics, Chemistry and Biology** before
completing the programme. An eligible applicant who falls short becomes `ELIGIBLE_WITH_REMEDIATION`, with the missing
subjects and the credits short recorded (for example "Physics"). The remediation status is `NOT_REQUIRED`, `REQUIRED`,
`IN_PROGRESS`, `COMPLETED`, `NOT_COMPLETED` or `REQUIRES_REVIEW`. The Office records changes with a note, and each change
goes to the history.

**Not invented:** remediation examinations, dates, number of attempts, pass marks, certificate rules, automatic
progression.

## 13. Application fee configuration

`admissions.route_fee` for 2026/2027: application fee **₦5,000** (from the notice, stored as data and stated by the Bursary),
portal charge ₦0. The acceptance and checking fees are **empty**, so the Bursary sees **FEE NOT CONFIGURED** and no such
reference can be raised. The Bursary changes the fee on `/preliminary/config` (`PUT config/fee`, Bursary/super only). The
frontend shows whatever amount the API returns; ₦5,000 appears nowhere in frontend code. The form opens only after
`confirm_fee` has a gateway-confirmed payment. School fees, acceptance fees, course registration fees, late fees and other
charges are not stated.

## 14. Application window

`policy.portal_window` `PRELIMINARY_SCIENCE_APPLICATION`, session 2026/2027, **opens 20 July 2026 00:00 WAT** (stored as
configuration), **no closing date**. The Director of ICT opens, closes, extends or reschedules it on the existing windows
screen.

> **On deploy the window is OPEN.** 20 July 2026 has passed, so applications are accepted from the moment V446 runs until ICT
> sets a closing date or closes it.

The backend enforces the window: `prelim_register` and the applicant-account guard refuse with `APPLICATION_CLOSED`, and
a first submission is refused after closing. Resubmitting a correction the Office asked for is still allowed. Closing
reminders go to drafts through the V444 engine.

## 15. Admission workflow

```
DRAFT ─submit→ SUBMITTED ─START→ UNDER_REVIEW ─REQUEST_CORRECTION→ CORRECTION_REQUIRED ─resubmit→ UNDER_REVIEW
UNDER_REVIEW ─RECOMMEND (prelim)→ RECOMMENDED ─APPROVE (academic, not the recommender)→ APPROVED ─publish (academic)→ ADMITTED
any open state ─NOT_ADMIT / REJECT→ NOT_ADMITTED / REJECTED (released on publish) · REOPEN (academic) · WITHDRAWN (applicant)
```

A recommendation needs every required document accepted, the O'Level verified, and an eligible record. Approval is refused
to the person who recommended (`PRELIM_APPROVE_OWN`). Publication writes the ordinary `application.decision` /
`decision_released_at` / `offer_state`. The status reads "Admitted into the Preliminary Science Programme", and the target
stays an intended progression. The student's programme is never set to the target. Nobody is put on the student register,
and no matriculation series is consumed. Preliminary Science applications stay out of Post-UTME screening, CBT, status
checking and their reminders.

## 16. Documents

Required kinds (all configurable): PASSPORT and PASSPORT_2 (two recent passport photographs), OLEVEL_STATEMENT, OLEVEL_STATEMENT_2
(required only for two sittings), LGA_ID (indigene certificate), and BIRTH_CERT (birth certificate or declaration of age). The
**payment receipt** is the portal's own receipt, not an upload. Each document is reviewed as ACCEPTED or REJECTED with a reason.
Content is served only to its owner or an authorised desk reader within scope. The application form PDF (with the passport)
and the admission letter PDF come from `lib/document`. The letter states the route, the type (Preliminary / Remedial), the
target as an intended progression, and any remediation.

## 17. Notifications

Through the one outbox (`platform.tell_applicant`): `PRELIMINARY_SCIENCE:APPLICATION_CREATED`, `PAYMENT_SUCCESSFUL`,
`APPLICATION_SUBMITTED`, `CORRECTION_REQUIRED`, `REMEDIATION_REQUIRED`, `ADMISSION_OFFERED`, `ADMISSION_NOT_OFFERED`, the
`PRELIMINARY_SCIENCE` fallback, and `WINDOW_CLOSING:PRELIMINARY_SCIENCE_APPLICATION`. They go by EMAIL, SMS and PORTAL with
event-key dedupe. No password or document content appears in any message.

## 18. RBAC

| Action | Offices (controller **and** database) |
|--------|---------------------------------------|
| Read desk, list, detail, analysis | prelim, academic, registrar, dregistrar, super, admin; **hod / dean scoped** to their own targets' department/faculty, without contact details |
| Payments list | the central readers above (not hod/dean) |
| Start review, request correction, review documents, verify O'Level, change target, record remediation | prelim, academic, super |
| Recommend | prelim, super |
| Approve, not admit, reopen, publish | academic, super (never the recommender) |
| Rules, targets, documents | academic, super |
| Fee | bursar, super |
| Applicant endpoints | the applicant's own application only (token subject); other applicants' documents return 404 |

One new office (`prelim`), no new roles.

## 19. Audit

All five new tables are attached to the audit spine with actor, office, reason and correlation id. Every review step is also
written once to `prelim_review_event`; an update or delete is refused unless the application itself is removed by the
go-live data reset, which cascades as CCE's does. Configuration changes need a reason.

## 20. Reports

Desk figures (total, paid, submitted, incomplete, pending review, under review, correction, eligible, not eligible,
remediation required, admitted, not admitted, withdrawn), each a filter of the list. Lists can be filtered by target,
sittings, eligibility, remediation, state, payment, sex, state of origin, LGA and dates, sorted, and exported (branded
XLSX/print). The analysis covers target, eligibility, remediation subjects, sittings and sex, and the payments list
covers the route. All of it respects the Head/Dean scope.

## 21. Security testing

`PreliminaryScienceIT` (API) and the V446 `check.sql` block (database) prove:

- the desk is refused to a lecturer, the Bursary and an applicant (403);
- a Head of Department of another department gets 404 for an application they do not own, and 403 on acting;
- the Bursary cannot act on applications or change the rules (403), and the Academic Office cannot set the fee (403);
- a rules change without a reason gets 400;
- another applicant cannot read the first applicant's document (404, so applications cannot be enumerated);
- the applicant reads no unpublished step;
- the recommender cannot approve their own recommendation;
- publishing is refused to the Office (403);
- a non-undergraduate, duplicate or unoffered target is refused;
- registration and submission are refused outside the window;
- the form is refused before the fee is confirmed;
- an awaiting result and a third sitting are refused.

Regression ITs passed with V446: AdmissionLifecycleIT, AdmissionStatusCheckingIT, AdmissionEligibilityIT, ApplicantIT,
ApplicantDeadlinesIT, ApplicationWindowsIT, CceIT, ClosingRemindersIT, PortalWindowsIT, PutmeIT, PutmeCbtIT,
SmsCostAndApplicationDeadlinesIT, PaymentClassificationIT, FinancialAnalyticsIT, ModularityTests.

## 22. Performance testing

A scratch copy was seeded with **5,000** synthetic applications through the real functions (register → fee → O'Level →
target, about 40 ms each). The desk was then timed on the local API (median of 5 after a warm-up):

| Call | Median | Max |
|------|--------|-----|
| summary (figures) | 87 ms | 122 ms |
| applications, page 1 of 5,002 | 183 ms | 194 ms |
| applications, page 41 | 205 ms | 208 ms |
| search by name | 129 ms | 139 ms |
| eligibility filter, sorted by name | 111 ms | 133 ms |
| target + paid filter | 19 ms | 33 ms |
| analysis | 99 ms | 141 ms |
| payments | 60 ms | 75 ms |

Paging, search, filters and counts run in one SQL statement on the server (window count, `LIMIT/OFFSET`), with indexes on
review state, target and eligibility. The list never loads all applications, O'Levels or documents into memory.

## 23. Missing undergraduate target programmes

- **B.Sc Technology and Industrial Studies**: no programme of that name is on the register. Recorded as `MISSING`, not offered.
  The Academic Office links it to an existing programme on `/preliminary/config` once the University names it.

## 24. University information requiring confirmation

1. **Acceptance fee, school fees, course registration, late fees and other charges**: none stated, all show FEE NOT CONFIGURED.
2. **Programme duration**: the route row holds a 1-year placeholder that is never printed.
3. **Remediation**: the examinations, dates, attempts, pass marks and certificate rules.
4. **After admission**: the identity number of a Preliminary Science student and the move onto the student register. No
   intake is built, so admitted candidates stay applicants with a published admission. The undergraduate matriculation
   series is not touched.
5. **Preliminary Science courses, timetable and results**: none created.
6. **Staffing of the Preliminary Science Office**: who is posted to office `prelim`. The Academic Office can take up
   reviews, verify documents and O'Levels and ask for corrections. Only `prelim` (or super) can **recommend**, and the
   approver must be someone else, so at least one person must hold `prelim` before anyone can be admitted.
7. **Closing date of the application window**: none given, so the window stays open until ICT closes it.
8. **Target names that differ from the register**: Anatomy → Human Anatomy, Physiology → Human Physiology, "B.Sc Doctor of
   Pharmacy" → Doctor of Pharmacy, B. Nursing Science → Bachelor of Nursing Sciences, "B.INDCHM. Industrial Chemistry" →
   B.Sc Industrial Chemistry. These were mapped, never renamed.
9. **Two passport photographs**: whether both must be uploaded or only presented physically (both are required uploads now).
10. **Physical submission**: where and by when the printed form and photocopies go (the steps say "where the University asks").
11. **NIN**: not collected, because the shared applicant biodata has no NIN field. Collecting it means adding it there for every route.
12. **Failed-payment message**: no `PAYMENT_FAILED` notice. The gateway path reports only confirmed payments to applicants.
13. **Admission letter number**: the letter takes its reference from the shared admission-letter series (ADM/yyyy/nnnnnn),
    which is a letter reference, not a matriculation number. Confirm the University is content with that.
