# Graduation at the Bursar's final clearance, approved waivers, and clearance reconciliation runs (V665, 26 October 2026)

The University's master prompt of 26 October 2026, "Comprehensive graduation clearance, school fees reconciliation and outstanding
balance engine", with its two answers:

- **When does a student become GRADUATED?** At the Bursar's final clearance. Senate approves the award and the final clearance
  begins; the record reads GRADUATED when every office has cleared the student and the Bursar confirms the clearance, last, with
  nothing owed.
- **Waivers?** Yes: approved waivers and adjustments reduce what a student owes, proposed by one officer and approved by another of
  the Bursar's office. Nothing is ever "marked paid".

## 1. What stood before

Most of the engine was already there and is reused, not rebuilt:

- Each graduate's and graduand's school fees by session and semester, at the fees of the period and the level the student was at
  then. A period with no fee structure is held for review and settled by a historical assessment the Bursar approves (V654).
- The verified school-fee payments, including payments made under a JAMB number (V647) and reallocated payments (V649), allocated
  first semester first. The student sees their own balance and can pay it online.
- The final clearance's Bursary stage reads that account when the decision is made, and refuses while anything is owed, for review,
  or pending (V654 on V415).
- Graduation batches and the session's whole-list approval (V602), and the record closed to later fees and registration once
  graduated.

What was missing: the student became GRADUATED when Senate approved the award, before any office had cleared them. There was no
waiver, and no way to read a whole population's financial clearance at once.

## 2. The award approved, the final clearance begun

`records.graduate_one` (a graduation batch, or the session's list approved by `records.approve_awards`) and `admissions.pg_award`
(a postgraduate award) now:

- approve the list entry on the Senate minute (`records.graduand.approved_at`, `approved_by`, the batch, the final level and so on);
- start the FINAL clearance where none is under way (an engine refusal is recorded, never fatal);
- tell the student on the new `STUDENT_AWARD_APPROVED` template: the award, the minute, and that the record reads GRADUATED once the
  Bursar confirms the final clearance;
- **leave the status as it is** (ACTIVE or PROBATION).

The batch's outcome for that student is `APPROVED` (counted in the batch's total as before). Asked again, an approved award returns
`AWAITING_FINAL_CLEARANCE` and its clearance is made sure of; a graduated student returns `ALREADY_GRADUATED`.

An approved graduand awaiting final clearance (`records.awaiting_final_clearance`) is already closed to a later session:

- no school-fee charge or reference for a session after the graduation session (`finance.closed_for_fees`);
- no course registration for it (`registration.student_draft`, and the API's view, add, choose and search), with the code
  `REG_STUDENT_AWARD_APPROVED` on the registration view ("Your award is approved").

The data-quality check "graduated, still active" no longer counts a graduand whose final clearance is under way, and "beyond the
maximum period" leaves out an approved graduand awaiting it.

## 3. The Bursar's confirmation graduates the student

The FINAL clearance's **Bursary stage is now last**: Department, Faculty, Library, Health, Hostel (where it applies), Works, Alumni,
then the Bursary. It opens only when the others have cleared.

For a student whose award is approved and whose record is not yet GRADUATED, the Bursary's own CLEARED (`clearance.decide`):

- is the Bursar's alone (`CLR_BURSAR_ONLY`, 403 to any other office);
- is refused while another office is still to clear (`CLR_STAGE_WAITING`, and `CLR_BURSARY_LAST` as a second guard);
- is refused while anything is owed, for review or pending (`CLR_OUTSTANDING`, as before, read again at that moment);
- is refused if the academic record no longer holds (a carry-over owed, a result awaited: `GRAD_ACADEMIC`);
- is accepted on a clearance that is already complete (for instance one where the Bursary was cleared before V665);
- in the same transaction, graduates the student (`records.graduate_on_final_clearance`): GRADUATED on the award's minute with the
  clearance reference and the Bursar in the reason, the moment and the officer on the list entry and the batch row, the historical
  summary marked to be worked out again, and the student told on `STUDENT_GRADUATED` ("Final clearance: complete — every office has
  cleared you").

If any step fails, nothing changes. A Registry override of the Bursary stage clears the stage as before but graduates nobody: the
Bursar's own confirmation, afterwards, does.

`clearance.final_check(process)` says all of it before the Bursar confirms: whether it graduates, the account (assessed, paid, waived,
outstanding, the periods not settled), waivers pending, payments outside school fees in an owing session, the offices still to
clear, the academic record, and the blockers in words. `ready` is true when there are none.

No reconciliation graduates an approved award: `people.decide_cohort` refuses it (`COHORT_GRADUATION_CLEARANCE`) and the cohort
engine's bulk act on R1 leaves such students out.

A student graduated before V665 stays graduated; their final clearance works as it did.

## 4. Waivers and adjustments

`finance.historical_waiver` (HFW/YYYY/NNNNNN), one row per proposal:

- **Kind**: WAIVER (the University forgoes the amount: a scholarship, a Council concession) or ADJUSTMENT (the amount assessed was too
  high and is put right short of a new assessment).
- **Proposed** for one session and semester by an office holding `CREATE_HISTORICAL_FEE_ASSESSMENT` (the Students Account Officer or
  the Bursar), with a reason (20 characters at least), the approval it rests on (a letter, a minute, an award) and, optionally,
  evidence files (PDF, JPEG or PNG, up to 5 MB). Only an assessed period, for more than nothing and no more than it still owes
  (`HFW_AMOUNT`). One proposal at a time per period (`HFW_PENDING`).
- **Approved or rejected** by another officer of the Bursar's office (`HFW_SAME_OFFICER`; the database and the two-officer constraint
  both hold it). The amount is read again at approval. The student is told on `HISTORICAL_FEES_ADJUSTED`.
- **Withdrawn** while pending, by its proposer or the Bursar.
- **Revoked** by the Bursar's office with a reason (20 characters at least): the amount is owed again. A graduated student stays
  graduated.
- Never edited once decided (`HFW_KEPT`).

`finance.historical_rows` gains the column `waived` (last): the period is owed on the amount assessed less its approved waivers,
never below nothing, before the payments are allocated. The summary carries the waived total. Everything that reads the account
(the student's fees page, the account on the desk, the Bursary stage's evidence and blocker, the statement, the reports) reads the
net figure; the account shows the waiver in its own **Adjustment** column.

## 5. Clearance reconciliation runs

`finance.clearance_recon_start(scope)` writes a run CLEARANCE-RECON/YYYY/NNNNNN:

- **Population**: the approved graduands awaiting final clearance (the default), the students under final clearance, the graduates,
  or all of them; narrowed by faculty, department, programme, admission session and graduation session. At most 5,000 students a
  run (the run says when it was capped).
- Each student's account is read afresh and kept as a row: assessed, paid, waived, outstanding, credit, the periods owing, for review
  or pending, the payments outside school fees in an owing session, the final clearance and its Bursary stage, and a status:
  CLEARED, OWING, PAYMENT_REVIEW (owing, with such a payment to look at), REQUIRES_REVIEW, PENDING_APPROVAL or NO_PERIOD.
- Payments outside school fees are those that read like fees (`finance.historical_other_payments`): the old portal's outstanding-fees
  payments (V631, with their desk status) and payments named for tuition or JAMB. They are never counted as school fees by
  themselves; the run points the Bursary to them.
- A run changes nothing in the money. Run by an office holding `PROCESS_FINANCIAL_CLEARANCE`; read by the offices holding
  `VIEW_FINANCIAL_CLEARANCE`.

## 6. Screens

- **The clearance desk** (`/clearance`): on a final clearance whose award is approved, the panel says so; with the Bursary stage and
  **Cleared** chosen, the button reads **Clear student…** and opens **Confirm clearance & graduate**: the award, the account of every
  session and semester (assessed, paid, waived, outstanding), the offices, the academic record, payments outside school fees, and the
  blockers, read afresh. **CONFIRM CLEARANCE & GRADUATE** waits until nothing is in the way; while it works it reads "Processing
  clearance...", and on success "Student cleared and graduation status updated successfully." Clearing several at once on the
  Bursary's final stage asks first, saying that approved awards are graduated as they are cleared, each on its own fresh reading.
- **Historical Fees & Clearance** (`/finance/historical`): new tabs **Waivers and adjustments** (the Bursar's queue, each waiver with
  the period's account, approve, reject, withdraw, revoke) and **Reconciliation runs** (run, open a run, filter by status, Excel and
  PDF). The overview gains "Awaiting final clearance" and "Waivers awaiting the Bursar". The student's account offers **Waive or
  adjust** on an owing period, lists the waivers, and lists the payments outside school fees in an owing session.
- **The student's fees page and registration page**: the Adjustment column; "Your award is approved — final clearance under way".

## 7. Tests

- `check.sql` V665: a made-up finalist with ₦100,000 assessed and ₦60,000 paid — the award approved (status ACTIVE, clearance started,
  told), approved again (AWAITING_FINAL_CLEARANCE), closed to a later session; the Bursary last and waiting; the Registrar refused
  (CLR_BURSAR_ONLY) and the Bursar refused over ₦40,000 (CLR_OUTSTANDING); a waiver above the debt refused, the proposer's own
  approval refused, another officer's approval (₦25,000 owed), kept, revoked (₦40,000), proposed by the officer and approved again; a
  run reading PAYMENT_REVIEW; paid in full, the Bursar's clearance graduating in the same act; a second word refused (CLR_COMPLETED).
- Existing checks restated: V029 (the list's approval approves, five notices, no status change), V331 (no reconciliation graduates C),
  V415 (the gate's order), V416 (the Department chased, the Bursary now waiting), V602 (the batch approves; the Bursar's confirmation
  graduates; the whole-list approval approves).
- ITs: GraduationBatchIT (the batch approves; the record closed while awaiting; the Bursar's stage waiting, refused to the Registrar,
  and graduating), HistoricalFeesIT (a waiver refused above the debt, refused to the officer, approved by the Bursar; a run; the
  Bursar refused over the balance, then graduating; the student's own view), GraduationIT, PgLifecycleIT, ClearanceWorkflowIT.
- Unit: `lib/clearance.test.ts` (which word graduates), `lib/historical-fees.test.ts` (waived totals, the statement's column, the
  amount a waiver may be, a run's rows).

## 8. Not changed

- The College of Health's progression (V606), the status reconciliation of students outside the maximum period (V638) and the
  Registrar's student edit still set GRADUATED by their own acts; none rests on a Senate award.
- The cohort engine still proposes GRADUATED for an approved award (R1); only the act is refused.
