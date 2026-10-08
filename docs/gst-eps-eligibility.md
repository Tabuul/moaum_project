# GST & EPS owed only for a course the student must take (V366)

The brief: *"A student should never see a GST or EPS fee simply because they are a student."* The fee must follow
the student's actual GST/EPS course requirement for the session — the programme's own offerings at their level, a
carryover — and be enforced at the backend, not by hiding a card. This note is the implementation report the brief
asked for.

## 1. Root cause

`finance.gst_required` (V314) asked one question: *does the student's programme list any course of kind GST at
their current level?* It never asked whether that course runs in the session (`catalogue.offering`), whether the
student has already passed it, or whether they carry one over. Everything else read that answer:

| Symptom | Why |
|---|---|
| A student whose curriculum lists a GST/EPS course at their level owed the fee in a session that does not run it, or after passing it | the curriculum binding alone made them "required" |
| A 300/400-level student carrying GST 101 over read **NOT REQUIRED** on the dashboard, yet registration demanded the fee | the dashboard read `gst_required` (no GST at 300); the gate on the carryover entry did not ask `gst_required` at all |
| With the whole-registration rule on, misjudged students were held on **every** course | production has had `finance.gst_setting.required_for_all = true` since 6 Oct 2026 (set by the Bursar) |
| Any student could open a GST fee reference for themselves | `finance.new_gst_reference` never asked whether the fee was owed |
| The GST and EPS dashboards counted the same "required" students | one flag for both offices; the EPS desk counted GST-only students as its own |

There is no GST/EPS line in the school-fee schedule (`finance.fee_schedule`) on Railway, so the school-fee position
was not part of the problem.

## 2. Reused, not rebuilt

Course catalogue and course offering (`catalogue.course`, `catalogue.course_offer`, `catalogue.offering`,
`catalogue.bind_offer`/`unbind_offer` with history), the registration engine (`registration.student_menu`,
`student_choose`, `student_add`, `student_submit`, `registration.carryovers_at`'s rule, `is_elective_for`), result
resolution (`assessment.course_final`, `assessment.latest_scores`), the GST fee and rule (`finance.gst_fee`,
`finance.gst_fee_for`, `finance.gst_setting`), the ledger (`finance.payment_reference`, refunds), the CBT engine
(`assessment.cbt_eligibility` → `registration.gst_gate`), the support desk (`SupportAccess`, `finance.entitlement_state`),
the audit spine and RBAC. No new table; no second fee, payment, registration or result engine.

## 3. Database changes (V366)

| Object | Change |
|---|---|
| `finance.gst_eps_rows(session, student)` | **new** — the engine: the GST-kind courses that concern each student in a session, with source, whether owed, status. One student, or the whole register when none is named. |
| `finance.gst_eps_reason(...)` | **new** — the reason code. |
| `finance.gst_eps_eligibility(student, session)` | **new** — one student's GST and EPS requirement, reasons, courses owed, carryovers, completed. |
| `finance.gst_eps_explain(student, session)` | **new** — "why is this student paying GST/EPS?" as JSON. |
| `finance.gst_required` | restated on the engine (signature unchanged, so `assessment.cbt_candidates` follows). |
| `finance.gst_entitlement` | `required` from the engine; new state `EXEMPT` (₦0 stated); `NOT_REQUIRED` before `NOT_STATED`; new columns `gst_required`, `eps_required`, `reason`, `gst_reason`, `eps_reason`, `review`. |
| `finance.new_gst_reference` | refuses `GST_NOT_REQUIRED`; `GST_EXEMPT` for a ₦0 fee. |
| `registration.gst_gate` | holds only a student the fee is owed by; the whole-registration rule never holds anyone else. |
| `registration.student_menu` | a GST-kind course of the programme at the level that the student already passed in an earlier session is not offered again. |
| `finance.gst_population` | rebuilt on the engine (one pass over the register): per-office requirement, reason, carryover, completed, courses owed, `review`; semester narrows "owed" to the courses run in it. |
| `finance.entitlement_state` | carries `gstRequired`, `epsRequired`, `gstFeeRequired`, `gstReason`, `gstReview` for the support desk. |

Identifiers stay UUIDs; nothing is stored, so there is no cache to invalidate: a change of programme, level,
offering, registration, result or payment is read the next time anything asks.

## 4. The eligibility algorithm

For each undergraduate in good standing (status ADMITTED, ACTIVE or PROBATION; programme category UNDER GRADUATE):

1. **Level in the session** — the current level for the current and later sessions (as the registration menu reads
   it); the level they registered at for an earlier session; never guessed.
2. **COURSE_OFFERING** — each GST-kind course `catalogue.course_offer` binds to the programme at that level (track
   and curriculum version as the menu reads them, course not ENDED).
3. **CARRYOVER** — each GST-kind course failed before the session (published, graded, 0 points), not passed since,
   and not an elective to the programme — the rule of `registration.carryovers_at`, whatever the student's level now.
4. **REGISTERED** — each GST-kind course on the student's registration for the session (not dropped).
5. Results are resolved exactly as `assessment.course_final` resolves them (a published special or re-sit the
   student sat over the main sitting), read set-based: each sheet's scores once.
6. A course is **owed this session** when it is on the registration, or it runs in the session
   (`catalogue.offering`) and is a carryover or a programme course not already passed.
7. **GST required** = some GST course owed; **EPS required** = some EPS course owed; the **GST fee is owed** when GST
   is required, or EPS is required and the GST payment covers EPS (`finance.gst_setting.covers_eps`). There is no EPS
   fee, as before.

Reason codes (per office): `…_REQUIRED_COURSE_OFFERING`, `…_REQUIRED_CARRYOVER`, `…_REQUIRED_REGISTERED`,
`…_ALREADY_COMPLETED`, `…_COURSE_NOT_OFFERED`, `…_NOT_APPLICABLE`; and `PROGRAMME_NOT_ELIGIBLE`,
`STUDENT_NOT_ACTIVE`, `EPS_NOT_COVERED_BY_GST_FEE`. Course status: OUTSTANDING, REGISTERED, COMPLETED, FAILED,
ALREADY_PASSED, NOT_OFFERED.

## 5. GST, EPS and carryovers

- **GST** follows the offerings: normally 100 and 200 level because that is where programmes bind GST courses; a 300+
  student owes GST only through a carryover or a binding at that level. No level is hard-coded.
- **EPS** follows its own bindings: a 300-level EPS course offered to selected programmes is owed by those programmes'
  300-level students alone. One canonical course, many bindings — no duplicate courses.
- **Carryovers** override the level: a 300- or 400-level student who failed GST 101 owes it (and the fee) in any
  session that runs it, until it is passed; once passed it is never owed again and the menu stops offering it.
- **Programme change** — read live from `people.student`, so the approved programme is the one used at once.

## 6. Payment entitlement

- **Not required** → state `NOT_REQUIRED`; no reference can be opened; no outstanding balance; no gate.
- **Required, ₦0 stated** → `EXEMPT`; nothing to pay; courses register.
- **Required, unpaid** → `NOT_PAID`/`PENDING`; the gate holds the GST/EPS courses (and the whole registration where the
  Bursar's rule says so).
- **Paid though not required** (programme changed, a passed course, a payment made before V366) → stays `PAID`,
  flagged `review` (only in a session this portal runs GST/EPS in). Nothing is deleted, nothing refunded here; the
  Bursary decides through the existing refund workflow.

## 7. Registration, CBT, results

- `registration.gst_gate` is the one gate, raised by `student_choose`, `student_add`, `student_submit` and the ICT
  Support add checks — so no path around the API registers an unpaid student, and no student is held who owes nothing.
- The menu offers GST/EPS courses only through the programme's bindings at the level, carryovers and deferrals, and no
  longer offers a GST/EPS course already passed.
- CBT eligibility for a GST/EPS examination is unchanged in shape: registered on the offering (which only an applicable
  student can be) and the gate open. The candidate list is the offering's registrations.
- Results stay on the one pipeline; only registered students have sheets.

## 8. Screens

- **Student dashboard** — the GST & EPS card appears only when a course requires the fee (or a payment stands); it says
  which courses ("GST 101 (carryover)"); never a ₦0 card.
- **Student GST & EPS page** — why the fee is owed or not, each course with its source (programme course / carryover with
  the failed grade, "re-register") and status; a payment no course requires says the Bursary reviews it.
- **GST/EPS office dashboards** — eligible, paid, unpaid, registered, not registered, carryover, completed, not
  applicable (never counted unpaid), revenue and outstanding; per office.
- **GST/EPS students list** — filter by Required / Carryover / Completed / Not applicable / Paid, not required; a
  requirement column with the reason; **View eligibility** opens the whole answer.
- **GST/EPS courses** — where each course is offered (faculty, department, programme, level, basis, since), GST
  bindings at 300+ marked for checking, ended bindings with their reason; taking a programme off a course goes through
  `catalogue.unbind_offer` (refused while a student of it is registered on it this session; kept on the history).
- **Bursary (Fee Setup)** — the standing: applicable, paid, owing, not applicable, paid-not-required with the list.
- **ICT Support / CPO** — the payment tab shows the same eligibility answer, read only. The desk cannot mark a fee paid
  or create an obligation; payments stay with the Bursary, bindings with the Academic and GST/EPS offices.

## 9. RBAC and audit

- `/api/v1/me/gst` and `/api/v1/me/gst/reference` read the student from the token alone (no id in the path); a student
  cannot read another's answer or open a reference they do not owe (`GST_NOT_REQUIRED`).
- The office explanation `GET /api/v1/gst/{office}/students/{id}` and `GET /api/v1/gst/fee/review` are for the GST/EPS
  offices, Bursary, Registry, Academic, Records, ICT and the University's officers; the GST office reads its own desk
  only, as before. The support desk reads it through `SupportAccess` (`VIEW_PAYMENTS`).
- Changes to bindings now go through `catalogue.bind_offer`/`unbind_offer`, audited and kept on
  `catalogue.course_offer_history`; the fee and the rule stay Bursar-only and audited (V314).
- No eligibility override was added: the University's governance has not asked for one, and a missing course is fixed
  where it belongs — the binding (Academic / GST office) or the registration (ICT Support override, V346).

## 10. Tests

- `db/check.sql` property 210 — the brief's cases 1–15 at the database: 100/200 level owed; 300/400 level with nothing
  owed; GST carryover at 300; both passed at 400; repeating 100 level with GST passed (not owed, not on the menu); EPS at
  300 for programme A only; EPS carryover at 400; programme change B→A recalculated; a payment no course requires kept,
  flagged, no refund; no reference and no gate for a student who owes nothing, even under the whole-registration rule;
  the EPS student held then freed by the one GST payment; covers_eps off; the offices' population equal to the
  per-student answer for every case; semester 2 narrowing. 210 of 210 properties hold.
- `GstEligibilityIT` (API): not-applicable student — NOT_REQUIRED, reference refused, ordinary course registered under
  the whole-registration rule, no GST on the form; carryover at 300 — owed with its reason, on the form as a carryover,
  reference opens, the office and the support desk read the same answer; EPS at 300 for one programme only; the office
  counts not applicable and never unpaid; Bursary standing; a student cannot read the office's door.
- Existing suites green on V366: GstEpsIT, LegacyGstIT, CbtEngineIT, CbtExamIT, QuestionImportIT, JupebCbtIT,
  SupportStudentsIT, SupportResolutionIT, DefermentIT, PortalWindowsIT, ResultPipelineIT, ResultsIT,
  AdmissionLifecycleIT, AllocationImportIT, ModularityTests; StudentPortalIT and FinancialAnalyticsIT pass on their own
  (together in one database they collide on each other's fixture rows, not on V366).
- Frontend: type check, lint, 84 unit tests; browser check of the student page (carryover / nothing owed), the
  dashboard, the student list's eligibility view, the course bindings, the Bursary standing and the support desk.

## 11. Production: what to check, and the reconciliation

Nothing stored changes, so there is no data migration: the requirement is computed live, payments and registrations
stay as they are. What Railway showed on 8 Oct 2026 (read before V366):

- GST fee 2025/2026: ₦4,000 (one live rule); none stated for 2026/2027.
- `required_for_gst_eps = true`, **`required_for_all = true`**, `covers_eps = true`.
- GST-kind courses — GST office: 19 at 100, 8 at 200, **2 at 300, 1 at 400**; EPS office: 3 at 200, 4 at 300, 1 at 400.
- Programme bindings — GST at 300: **36 programmes**; GST at 400: 6; EPS at 300: 61 programmes; EPS at 400: 5; an EPS
  course bound at 100 level in 2 programmes.

**Before the deploy reaches students**, check that the session's GST/EPS courses are offered on the portal
(`catalogue.offering`). V366 requires the course to run in the session: if the GST office has not opened the
2025/2026 offerings, no student owes the GST fee for 2025/2026 until it does. The read-only queries:

```sql
-- 1. the GST/EPS offerings of each session (the requirement needs them)
SELECT o.session, c.general_office, o.semester, count(*) AS courses
  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
 GROUP BY 1, 2, 3 ORDER BY 1 DESC, 2, 3;

-- 2. the GST bindings at 300 level and above, to confirm each is intended (EPS at 300 is expected for selected programmes)
SELECT co.course_code, c.title, co.level, co.programme_code, p.name
  FROM catalogue.course_offer co
  JOIN catalogue.course c ON c.code = co.course_code AND c.kind = 'GST' AND c.general_office = 'GST'
  JOIN ref.programme p ON p.code = co.programme_code
 WHERE co.level >= 300 ORDER BY 1, 4;

-- after the deploy: who owes the fee now, by level, and who paid though nothing requires it
SELECT level, count(*) FILTER (WHERE required) AS owe, count(*) FILTER (WHERE NOT required) AS not_applicable,
       count(*) FILTER (WHERE gst_carryover OR eps_carryover) AS carryover, count(*) FILTER (WHERE review) AS paid_not_required
  FROM finance.gst_population('2025/2026', NULL) GROUP BY level ORDER BY level;

-- open GST references of students no course now requires: they lapse on their own expiry; nothing to delete
SELECT r.reference, r.student_id, r.amount, r.expires_at
  FROM finance.payment_reference r
 WHERE r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()
   AND NOT finance.gst_required(r.student_id, r.session);
```

The "paid, not required" list is also on the Bursary's Fee Setup page and at `GET /api/v1/gst/fee/review`.
