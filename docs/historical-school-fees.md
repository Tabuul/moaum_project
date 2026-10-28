# Historical school fees and the graduate's financial clearance (V654)

The University's master prompt "HISTORICAL SCHOOL FEES ASSESSMENT, GRADUATED STUDENT CLEARANCE & SESSION/SEMESTER OUTSTANDING
BALANCE" (25 October 2026). Some students graduated without paying one or more semesters' school fees. When they return for
clearance, a transcript or a certificate, the University shows what they owe, session by session and semester by semester, at the
fees of that period. A graduate stays GRADUATED whatever they owe, and a debt is not erased by graduation.

## What stood before

- `finance.position` reads a session's fee lines for the student as they are now: today's level and today's spillover. That is right
  for the current session and wrong for a past one. A 400 Level graduate was read against 400 Level lines in their 100 Level year.
- The FINAL clearance's Bursary stage read `finance.position` for each enrolled session. It skipped a session with no fee stated, so a
  graduate could clear financially though a session's fees were never known.
- `finance.new_reference` refuses a past session (its payment window is closed). A graduate could not settle an old balance online.
- There was no assessment where a session's structure is missing, or where a student's fee was legitimately different.

## The historical account

`finance.historical_rows(students)` reads, for each student, every session and semester:

- **From:** the assessment start or the admission session, whichever is later.
- **To:** the graduation session for a graduate or approved graduand (`records.graduation_session`), or the session before the
  current one for a student still studying.
- **Left out:** a deferred session or semester (an approved, active or completed deferment), and cancelled or draft sessions.

For each period:

- **Level:** the student's level in that session, read as `people.level_in` reads it: the semester's course registration, else the
  session's, else the enrolment, else counted from admission (a postgraduate's own level).
- **Assessed:**
  - an approved assessment for the period; else
  - the session's fee lines matched to the student as they were then (the level of the session; spillover read from that level
    against the programme's final level; every other fact as the charge engine reads it — entry mode, faculty and the faculty
    charged as, programme, fee group, PG stage, indigeneship). Whole-session lines are due with the first semester, as
    `finance.due_for_semester` reads them. A session whose lines reach the student assesses a semester with no line of its own at
    ₦0; else
  - nothing: **REQUIRES_REVIEW**, or **PENDING_APPROVAL** while an assessment awaits the Bursar.
- **Paid:** the session's confirmed school-fee payments (`purpose LIKE 'School fees%'`, as `finance.position` counts them), allocated
  first semester first. What is left goes to the first semester not yet assessed, else stands as a credit on the session's last
  semester.
- **Outstanding:** assessed less paid, short by under ₦1 counted as paid (`finance.fee_owed`).
- **Status:** CLEARED, PARTIALLY_PAID, OUTSTANDING, CREDIT, REQUIRES_REVIEW or PENDING_APPROVAL.

A period for review or pending approval is never owed.

The account never reads another session's fees. Today's structure is never applied to an old session.

## Where assessment starts

`finance.historical_setting.assess_from` is the Bursar's choice (`finance.historical_set_start`). When none is set, it is the first
session the fee setup holds a line for — on the live copy, 2025/2026. The University answered on 25 October 2026 that nothing older
is assessed, or holds a clearance, until the Bursar moves the start back. That should follow stating the older sessions' fee
structures in School Fees Setup (the upload files for 2021/2022 to 2024/2025 already exist). Moving the start works out every
graduate again.

## Historical assessments

`finance.historical_assessment` (HFA/YYYY/NNNNNN) holds an amount for a student's session and semester. It is used where the
structure is missing, or where the student's fee was legitimately different (a concession, a special category). The global fee
structure is never changed to fix one student.

Each assessment carries:

- the amount, and optional components that add up to it;
- the source, from a fixed list: historical fee structure, historical fee structure version, cohort fee record, student-specific
  approved fee, official fee document, manual historical assessment, legacy migration, or other approved source;
- a supporting reference, required for a document, an approval or a cohort record;
- a reason of twenty characters or more, and remarks;
- evidence files: PDF, JPEG or PNG, up to 5 MB, kept in the file store.

The workflow:

1. The Students Account Officer (or the Bursar) creates the assessment (`finance.historical_assessment_save`) for a period of the
   record. One assessment is made at a time, and one is in force, per student, session and semester.
2. The officer submits it: **PENDING_BURSAR_APPROVAL**.
3. The Bursar approves, returns for correction or rejects it (`finance.historical_assessment_decide`). The officer who made or
   submitted it never decides it (`HFA_SAME_OFFICER`, and `ck_hfa_two_officers` on the table). Returning or rejecting needs a note.
4. Approved, it is **in force**. The student's balance is worked out again, and the student is told (notice
   `HISTORICAL_FEES_ASSESSED`).
5. An approved assessment is never edited (`trg_hfa_kept`). A **correction** is a new assessment naming the one it replaces. Once
   approved, the old one is **SUPERSEDED**, and both stay on the record.
6. A draft, pending or returned assessment may be withdrawn by its maker or the Bursar.

Every act is on the timeline (`finance.historical_assessment_event`) and the audit spine.

## A cohort

`finance.historical_bulk_preview` lists, for a session and semester and a scope (faculty, department, programme, level in that
session), each graduate's verdict:

- **STRUCTURE_FOUND:** assessed from the setup; nothing to make.
- **ALREADY_ASSESSED**
- **PENDING**
- **REQUIRES_ASSESSMENT**

`finance.historical_bulk_create` assesses one amount for those that require it, under one batch (HFA-B/YYYY/NNNNNN). Each student
gets their own assessment, submitted for approval; every other student is skipped. The Bursar decides the batch together
(`finance.historical_batch_decide`), never its maker. Where a whole cohort lacks a session's structure, stating it in School Fees
Setup is preferred: it assesses everyone at once, and the session's payments reconcile against it.

## Paying online

`finance.historical_reference` gives a graduate (or approved graduand) a reference for a session's approved balance:

- outside the session's payment window;
- never more than is owed (`HFA_PAY_AMOUNT`);
- refused to a student still studying (`HFA_PAY_GRADUATES`);
- refused when the Bursar turns online payment off (`HFA_ONLINE_OFF`).

The payment is that session's school fees ("School fees 2021/2022 (historical)"), so the account, `finance.position`, the receipt
and every reader count it as that session's. No new current-session obligation is created. Graduates still never get a new
school-fee obligation for a session after graduation (V602).

## Financial clearance

The FINAL clearance's Bursary stage (`clearance.evidence`, `clearance.blocker`, restated) reads the historical account. It is never
cleared while any of these stands (since V665 the stage is last, and the Bursar's clearance of an approved award graduates the
student: see `graduation-at-final-clearance.md`):

- school fees are outstanding: "Not cleared — outstanding school fees: ₦… (2021/2022 Second semester …)";
- a period has no amount: "Historical fee review required …";
- an assessment awaits the Bursar.

The clearance desk shows each period. Once the stage is cleared, **Review fees** prints the **financial clearance certificate**
(`/finance/historical/certificate?student=…`, a PDF made on the server from the account the API returns to the office): the official
header, the student, the totals, the date the Bursary cleared it and the clearance's verify QR (`/verify/clearance/…?c=…`). Asked for a
student whose Bursary stage is not cleared, it answers 409 and prints nothing.

Academic status, financial status and clearance status stay separate. The financial status is one of FINANCIALLY_CLEARED,
FINANCIAL_OBLIGATION, FINANCIAL_CLEARANCE_PENDING or HISTORICAL_FEE_REVIEW_REQUIRED.

## The summary

`finance.historical_summary` keeps each graduate's totals and financial status, for the lists, dashboards and reports. It is worked
out again:

- for every graduate and approved graduand once, when V654 is applied;
- for the student, when a school-fee payment of a graduate is confirmed (triggers mark them in `finance.historical_stale`);
- for a student graduated since (no summary yet): the figures, lists and reports call `finance.historical_refresh_stale(500)`
  before they read, which works out the stale students first, then up to the rest of the 500 graduates with no summary;
- for the student, when an assessment is saved or decided, and when an officer opens the student's account;
- for everyone, on demand: "Work out every graduate", or `finance.historical_refresh(NULL)` — needed after a past session's fee
  lines change, which nothing marks stale.

On the live-shaped copy, 5,000 graduates are worked out in about 2.7 s; a read that picks up 500 new graduates adds about 0.3 s,
and one with nothing to pick up 15–45 ms.

## Who may

`finance.historical_grant` is checked by the API and by the functions:

| Office | May |
|---|---|
| Bursar's office, platform | Everything: approve, return, reject, set the start, approve financial clearance |
| Students Account Officer | View, create, edit, submit, review, correct (propose), process clearance, payments, reports, export, history |
| Internal Audit, Deputy Audit | View, financial clearance, payments, reports, export, history |
| Registry, Academic Office, Records, VC, DVC, ICT, admin | View, financial clearance, reports, history |

## Screens

- **Historical Fees & Clearance** (`/finance/historical`), on the Bursar's, Students Account Officer's, Internal Audit's and Deputy
  Audit's menus:
  - Overview: figures, each opening its graduates.
  - Students: server-side search by name, matric, JAMB, admission or application number, or the record's id; filters for faculty,
    programme, admission and graduation session, and financial status. Each graduate's account opens from the list: totals, session
    rows that expand, assessments, payments with the number each was made under, payment reallocations, the final clearance, the
    statement print, and the certificate.
  - Bursar approval: the assessments by state.
  - Cohort assessment: preview, confirm, and batches.
  - Reports: historical fees by session and semester, and the graduates' financial clearance, each to Excel and PDF.
  - Data quality: no admission or graduation session, missing structure, pending approval, overpayment, programme changed, and
    unmatched old-portal payments.
  - Assessment start.
- **Student full record**, Finance tab: the historical school fees.
- **The graduate's fees page**: historical school fees with the official amounts only, and "Pay outstanding school fees".
- **The Bursar's and the Students Account Officer's dashboards**: historical financial clearance and historical fee review.
- **The clearance desk**: the Bursary stage's evidence lists each period.

## Payment evidence from the graduate (V683)

The University's master prompt of 28 October 2026 ("no receipt evidence must not automatically mean the student did not pay"). Asked
who uploads evidence, the University chose: the graduate submits it, the Bursary reviews it.

- **Submitting.** On their fees page a graduate gives evidence for a semester of their history that is not settled: the amount, the day,
  how it was paid (bank, old portal, online, otherwise), the receipt, teller or transaction number, a note and files (PDF, JPEG or PNG, up
  to 5 MB, ten at most). One evidence is open per semester at a time (`finance.historical_evidence_submit`, HPE/YYYY/NNNNNN). The
  graduate may add files while it is with the Bursary, or withdraw it.
- **Reviewing.** The Students Account Officer or the Bursar (`REVIEW_PAYMENT_EVIDENCE`) works through **Payment evidence** on
  Historical Fees & Clearance. Each evidence lists the confirmed payments on record it may be
  (`finance.historical_evidence_candidates`):
  - the payment whose reference or receipt number is the one on the evidence, whoever holds it;
  - the graduate's payments of the session, under any purpose;
  - the graduate's archived payments.
  A payment can also be found by another number. Old-portal records held because their number named no student are shown too; they
  are matched on School Fees History Reconciliation (V647) first.
- **Deciding** (`finance.historical_evidence_decide`):
  - **Verify against this** links the evidence to that payment. A payment backs one verified evidence only.
  - **Ask for more information** sends it back; the graduate adds what is asked and sends it again.
  - **Reject** closes it.
  Asking for more and rejecting need a reason (ten characters or more), which the graduate reads. The graduate is told at each step
  (notices `HISTORICAL_EVIDENCE_RECEIVED`, `_MORE_INFO`, `_VERIFIED`, `_REJECTED`).
- **Never paid by a document.** The evidence never counts by itself; the account is unchanged by it. Only the payment counts, once it is
  the graduate's confirmed school fees of the session. `finance.historical_evidence_payment_state` says where the linked payment stands
  and the desk that puts it right, each with its own approval:
  - **counted:** nothing more to do;
  - **archived:** the Payment Archive (V670);
  - **on another student's record:** a payment swap (V527);
  - **under another purpose or session:** a payment reallocation (V649).
  A payment not on the portal at all (paid on the old portal and never brought over) is recorded on Old-Portal Payments first, with its
  approval, and then linked.
- **Payment under review.** `finance.historical_review` marks a semester that is not settled **PAYMENT_UNDER_REVIEW** where any of these
  stands, so it is never read as plainly unpaid while a payment is checked:
  - the graduate's open evidence for it;
  - a school-fee payment of the session archived and not yet settled;
  - a payment of the session under another purpose that may be school fees (outstanding fees, tuition, JAMB-named; V665).
  What is owed is unchanged. The graduate's fees page, the desk's account and the full record show it beside the status.
- **Figures and data quality.** The overview counts **Payment verification required** (evidence awaiting the Bursary, and that awaiting
  the graduate) and **Archived school fees payments** (graduates with one under review, and its value). Data quality lists
  PAYMENT_EVIDENCE_SUBMITTED and ARCHIVED_SCHOOL_FEES.

## Not done

- The historical account reads earlier sessions on the programme the student holds now; a programme change is listed in data
  quality.
- A waiver was not introduced by V654. V665 adds approved waivers and adjustments (one officer proposes, another of the Bursar's
  office approves), netted off the account; see `graduation-at-final-clearance.md`.
- A refunded or Interswitch-reversed payment counts as `finance.position` counts it.
