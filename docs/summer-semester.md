# Summer semester for final-year and spillover students (V735, V779)

The University's master prompt of 12 November 2026, "Introduction of Summer Semester for final-year and spillover students" (V735), and its prompts of 23 November 2026 (V779), which opened the Summer to every final-year and every spillover student, made the courses a student still owes the student's to select, and made verifying them the Academic Office's.

The Summer Semester is a third academic period of a session, beside the First and Second Semesters. It has its own registration window and dates. A final-year or spillover student selects the courses they believe they still owe, from the First and the Second Semester together, pays for them, and is registered in one registration. The Academic Office verifies each selection against the student's record. The student takes the courses, and a pass clears the carry-over.

> **Figures in this document.** Counts and times quoted below were read on 24 November 2026 on a copy of the 22 October 2026 live-shaped database (`lv643pre`) migrated to main (V782) and then V779 through `db/migrate.sh` (PostgreSQL 18.6, no JIT): 48,322 studying students, of whom 44,871 are undergraduates of the regular programmes. A figure read only on the 22 October copy before V779 (ledger at V637) says so where it stands, and one that was not read again is labelled **not re-measured**. The timings are in `docs/performance-audit.md`.

## What V779 changed

| Until V779 (V735 to V756) | From V779 |
|---|---|
| A student was eligible only with a detected outstanding course (the carry-over reader) or the Academic Office's authorisation. On the copy before V779 was applied, the old rule read 18,558 students in 24 s and admitted 454 (344 BEYOND_DURATION, 110 FINAL_YEAR). | Every final-year and every spillover student is eligible, by their academic status: 18,588 on the copy migrated to main (7,867 FINAL_YEAR, 10,721 SPILLOVER). The 454 stay eligible (the 344 now read SPILLOVER). There is no outstanding-course test. |
| A missing result left a student with nothing to select: most past results are on the old portal. | A missing result is never read as a pass and never as proof that nothing is owed. The student selects what they believe they owe. |
| The pool was the detected carry-overs and the authorised courses. | The pool is the programme's own structure up to its final level, the detected carry-overs and the authorised courses, checked on the server. |
| Every course a student could select was a detected carry-over or one the Office had named, so none needed an officer to check it. | Each selection is verified by the Academic Office, in one of four states the student sees, with the reason where the Office decides against it. A detected failure and a course the Office named confirm themselves. |
| Money for a course taken back stood as a credit of its payment, and the Academic Office had no act that took a paid Summer course off a registration. | A paid selection found not outstanding or rejected is taken off the registration and becomes a Summer credit, which the Bursar settles. Nothing is refunded automatically. |
| The desk's students list read every row in the browser. | The desk is paged, filtered and exported by the server, with a verification queue, a roster and reports. |

## How it fits the portal

- **It is not a `policy.semester` row.** Opening semester 3 on the calendar would make it every regular student's current semester. About a dozen readers take the highest open semester, and a closed Summer would count as a missed semester toward voluntary withdrawal. So the period lives in `registration.summer_period`, and `academic_session.semesters` is left alone.
- **Its registrations, classes, examination session, score sheets and results are those of semester 3 of the session.** They are keyed by `(session, semester)` like everything else, so a Summer pass orders after the failure it replaces and clears it.
- **The evidence is computed; the selection is stored.** What a student may select, and what the results say of each course, is read from the programme's structure and the results on the portal (`registration.summer_selectable`). What a student selects is stored, one row for each student, session and course (`registration.summer_selection`), and keeps its verification state for ever. Whether a selection is live is read from its course charge: it is *selected* while the charge is DUE or PAID. The row is never deleted.
- **Summer fees are kept apart from school fees.** They live in `finance.summer_fee` and `registration.summer_charge`, and their payment references carry the purpose `Summer semester fees, <session>: …`. No school-fee reader counts them. They are classified under their own payment category, `SUMMER_SEMESTER` (pattern `^summer semester`), which also covers the old portal's Summer payments.
- **One predicate says "passed".** `registration.summer_passed(student, course, session)`: a published pass of the course, or of a live twin of it (`catalogue.course_twin`), in a session strictly before the Summer of that session. Selecting, the evidence, the take-back at the draw, the examination gate and the reconcile all read it. A result of the selection's own Summer class, or of a later one, never counts for or against that selection.
- **A page read never writes.** The student page and the dashboard card are read-only (ICT Support's view of a student's portal is a read-only transaction). The stored state is brought up to date by a separate call the Summer page makes after it renders (§Reconcile).

## Who may take it

`registration.summer_eligibility_of(session, students[])` is the one place the rule lives. It is set-based and reads no results. `registration.summer_eligibility(student, session)` is its per-student wrapper, for the student's own page. A student's category comes from their academic status, the level on record and the academic position the engine keeps (`people.academic_position`). It never comes from a matriculation-number pattern, and never from level alone.

| Category | Who | Shown to the student as |
|---|---|---|
| SPILLOVER | `spillover_years > 0`, or the engine's spillover state reads `SPILLOVER…`, or `finance.is_spillover` | Spillover student |
| FINAL_YEAR | The level on record is at or above the programme's final level (`finance.final_level`, 400 when unset), **or** the engine says final (`computed_level >= final_level`). A student recorded below their final level whom the engine puts there is final-year too | Final-year student |
| BEYOND_DURATION | A name kept in old periods and rows. Where a period lists it, it admits an engine-spillover student exactly as SPILLOVER does | Spillover student |
| AUTHORISED | Admitted by the Academic Office for an approved academic reason (`registration.summer_authorisation`), with any courses it names | Authorised by the Academic Office |

A student who is both spillover and final-year is read as SPILLOVER first, then FINAL_YEAR. The category reported is the first the period admits. An authorised student keeps their natural category where the period admits one, and AUTHORISED otherwise.

The tests run in this order, and the first that applies decides:

| Reason | When | Said to the student |
|---|---|---|
| `NO_STUDENT` | no such student | "Your record could not be read." |
| `NO_SUMMER` | no Summer is set for the session | "No Summer Semester is set for this session." |
| `NOT_UNDERGRADUATE` | CCE, postgraduate, or a programme that is not undergraduate | "The Summer Semester is for undergraduate students of the regular programmes." |
| `NOT_STUDYING` | status other than ACTIVE or PROBATION | "Your record is not active." |
| `GRADUATED` | a Senate-approved graduand | "Your award is approved; there is nothing left to take." |
| *an authorised student is eligible here* | An unrevoked authorisation of the session, in a period that lists AUTHORISED, admits the student at this point; none of the tests below is asked of them | |
| `PROGRAMME_NOT_IN_SUMMER` | the period names programmes and the student's is not one | "Your programme is not among those this Summer Semester runs for." |
| `LEVEL_NOT_IN_SUMMER` | the period names levels and the student's **Summer level** is not one | "Your level is not among those this Summer Semester runs for." |
| `NOT_FINAL_OR_SPILLOVER` | neither final-year nor spillover | "The Summer Semester is for students in their final year or in spillover." The refusal's remedy: "The Academic Office may authorise a student for an approved academic reason." |
| `CATEGORY_NOT_IN_SUMMER` | the period admits none of the student's categories | "This Summer Semester is not open to students in your position." |

`NO_OUTSTANDING_COURSE` no longer exists. Students identified before V779 keep it on the desk until the next identification reads them again.

A student must be all of the following:

- an undergraduate of a regular programme (not CCE or postgraduate)
- ACTIVE or on PROBATION
- without a Senate-approved award
- a final-year or spillover student, or authorised by the Academic Office
- within the period's categories, programmes and levels

**The period's limits** are the Academic Office's, all optional:

- **Categories.** The period form shows three boxes: Final-year, Spillover (it writes SPILLOVER and BEYOND_DURATION together) and Authorised.
- **Programmes.** Where set, only these programmes' students. This is how the Office keeps a programme out (the College programmes, Left out below).
- **Levels.** Compared with the student's **Summer level**, `registration.summer_level(student)`, the greater of the level on record and the engine's computed level. A spillover student recorded at 100 Level whom the engine puts at 400 is not shut out of a period limited to 400. On the 22 October copy before V779, 10,334 engine-spillover students were recorded at 100 Level (not re-measured on the migrated copy).
- **A course ceiling** (`max_courses`, 1 to 60, none by default). It counts the courses a student holds live in the Summer, cumulatively over every call. A ceiling set below what a student holds never takes a course away; it stops further selecting.

The Summer level serves the period's level limit, the roster and the queue filters. It is not the level of the student's Summer registration, which keeps the level on record (`people.student.current_level`): the receipts, the historical fee assessments, the reallocation checks and the transcripts read a session's registration level first, and a Summer-only registration at another level would change the student's level for that session everywhere.

## Selecting courses

A student may select a course that is in their **pool**, which is the union of three sources, one row for each course, the first source that holds it winning:

| Source | What it holds |
|---|---|
| CARRY_OVER | The courses the carry-over reader reports the student owes (`registration.carryovers`), of any basis |
| AUTHORISED | The codes the Academic Office's unrevoked authorisation names, not already carry-overs |
| STRUCTURE | The courses the student's programme offers (`catalogue.course_offer`) from the student's entry level (100 where none is recorded) **up to the programme's final level**, whatever level the student is recorded at, with the same track and specialisation filters the carry-over reader uses. Elective, Deficiency and Research courses are not in it (an elective is never owed); an ended course is not; nor a course whose code begins `DMO ` |

On the 22 October copy before V779, a student's structure pool averaged 105 courses, with a median of 107 and a largest of 324 (not re-measured on the migrated copy; there, the 20 students whose pool was timed had pools of 35 to 207 courses). The student searches; nobody is shown a page of 105 checkboxes to read through.

A course is shown in the pool, but cannot be selected, in these cases, each with its reason:

| Reason | Said to the student | Meaning |
|---|---|---|
| `COURSE_UNKNOWN` | Not in the course catalogue | |
| `COURSE_ENDED` | The course has ended; ask your department | |
| `ALREADY_REGISTERED` | Registered | A PAID charge stands |
| `ALREADY_SELECTED` | Selected — pay to register | A DUE charge stands |
| `DECIDED_NOT_OUTSTANDING` | Found not outstanding by the Academic Office | The decision stays in the list, with its reason |
| `DECIDED_REJECTED` | Rejected by the Academic Office | The same |
| `SIWES_OWN_PAGE` | SIWES is registered on its own page | A SIWES course, from any source, is not offered in the Summer (Left out, Q1) |
| `PASSED` | Passed | A published pass of the course or of its twin, before this Summer |

These eight are the only reasons `registration.summer_selectable` gives. A course whose result of this session is still awaited (registered in the First or Second Semester, no published result) is **not** among them: since V787 it is selectable like any other course of the pool (the University's word of 27 November 2026: no restriction on what a student picks), and its evidence reads *Result awaited*. `ALREADY_REGISTERED` and `ALREADY_SELECTED` come before `SIWES_OWN_PAGE`, so a SIWES course an older Summer charged reads as registered.

**A course taught in both semesters and failed in the First Semester of this session is selectable**, and its Summer entry registers. The portal's once-a-session rule for such a course (`registration.entry_once_a_session`, V386) lets semester 3 through since V735, so the Summer may repeat a course of the session. While the course's result of this session is not published it reads `RESULT_AWAITED`, and once a pass is published it reads `PASSED`.

**What each course shows.** The code and title (and, where the student took it under another code or title, "Taken as CSC 305, Operating systems, 3 units": the course as taken, V771), the units (**the programme's own units**, `catalogue.units_for`, in what is shown, what is charged against and what is registered), the level and the programme's basis (Core, Required, Borrowed, GST), the semester (First, Second or Both), the fee, and the **result evidence**:

| Evidence | Word | Means |
|---|---|---|
| `RESULT_PASSED` | Result on record: passed | A published pass before this Summer. The course is not selectable. Where it is already selected, the portal takes it back (§Reconcile) |
| `RESULT_AWAITED` | Result awaited | Registered this session, no published result. The course is selectable (V787); the selection waits for the Academic Office like any a result does not confirm, and is taken back or flagged if the result then publishes as a pass |
| `RESULT_FAILED` | Confirmed by results (failed) | A published F or absence the carry-over reader counts (never an elective) |
| `NO_RESULT` | No result on record | The portal holds nothing for the course. This is not a pass and not proof of nothing owed |

The precedence is PASSED, then AWAITED, then FAILED, then NO_RESULT. Only PASSED keeps a course from being selected.

**How a student selects (Summer Semester `/student/summer`).** The picker has a search box (code, title, the as-taken code and title), filters for Level, Semester and Show (All courses, My outstanding, Selected), and groups the rows under "NNN Level" headings. A student ticks courses of both semesters at once. Each ticked course may carry an answer to "Where did you owe it?", the session (from the last six, or "Not sure") and the semester (First, Second, or "Not sure"), which is kept as the course's original semester and session and printed on the confirmation. The sticky bar says "N selected · U units · ₦ formula" and **Select N courses**.

**What the server decides.** Nothing in the page decides eligibility or the pool. `registration.summer_select(student, session, courses[], origins)` reads the pool once and:

- refuses a code outside the pool with `SUMMER_COURSE_NOT_AVAILABLE` ("… is not a course you may register in the Summer Semester (it is not in your programme's structure, nor among your outstanding or authorised courses)");
- refuses a course that is in the pool and cannot be selected with `SUMMER_COURSE_REFUSED` and the reason in lower case ("… cannot be registered (passed)");
- takes a code written twice in one call as one selection, and writes each code in capitals with single spaces;
- takes **at most 30 different courses in one call** (`SUMMER_TOO_MANY`), and refuses a call that would take the student above the period's ceiling (`SUMMER_CEILING`). A student who owes more selects the rest afterwards. The request itself carries at most 200 entries of 20 characters (a course code may be 20 characters, `ck_course_code`, V776), so the database, not the form's validation, says "too many";
- refuses an origin whose session is not a session or whose semester is not 1 or 2 (`SUMMER_ORIGIN_INVALID`).

The same course selected again is refused (`SUMMER_COURSE_REFUSED`, already selected), so a double click costs nothing.

## Verification

Every selection is a row in `registration.summer_selection` with one of **four states**. The student sees the state and, where the Academic Office decides against a course, the reason, on the Summer page and on the printed confirmation; the dashboard card states the counts and sends the student to the page for the reasons.

| State | The student reads | How a selection comes to be in it |
|---|---|---|
| `PENDING_VERIFICATION` | Student selected – pending verification | The course is not a detected failure and not named by the Office: the student's own selection, which no record confirms |
| `CONFIRMED_OUTSTANDING` | Academically confirmed outstanding | Confirmed by results, by the Office's naming of the course, or by an officer |
| `NOT_OUTSTANDING` | Not outstanding – result verified | A pass is on record, or an officer found the course not owed |
| `REJECTED` | Rejected – incorrect course selection | An officer found the selection wrong (not a course the student owes) |

(The University's prompt writes the four in capitals: "Student Selected – Pending Verification", "Academically Confirmed Outstanding", "Not Outstanding – Result Verified", "Rejected – Incorrect Course Selection". The screens carry them in sentence case.)

**Who or what confirmed it** is kept apart from the state, as `verified_via`:

| `verified_via` | The student reads | When |
|---|---|---|
| `RESULTS` | Confirmed by your results | A detected failed course is confirmed by the system when it is selected: `CONFIRMED_OUTSTANDING`, no officer, recorded in the history as SYSTEM. A pass on record found later also makes `NOT_OUTSTANDING` by RESULTS |
| `AUTHORISATION` | Named by the Academic Office | A course the Office's authorisation names, confirmed when it is selected |
| `OFFICER` | Confirmed by the Academic Office | An officer decided it. A `REJECTED` selection is always `OFFICER` |

A `PENDING_VERIFICATION` selection has no `verified_via`. The Academic Office's effort is therefore only on the selections no record can confirm. On the old portal's three sessions of Summer payments, 1,061 students made 1,103 payments, of whom only 75 had a detected carry-over, so a Summer is likely to leave about 3,000 selections to verify. That is an estimate from the old portal's payers, not a measurement: no copy can count selections before a Summer has run.

**The registration category** a course is printed with follows how it came in, never its state: **Carry-over** (`CARRY_OVER`), **Authorised course** (`AUTHORISED`), **Student-selected course** (`STUDENT_SELECTED`). A course the student chose is never called a carry-over on a student screen, whatever its state, until a pass or an officer settles it.

**Who verifies.** The Academic Office (`academic`), the Registrar (`registrar`), the Deputy Registrar (Academic Affairs) (`dregistrar`) and the Super Administrator (`super`). The database checks the office again (`SUMMER_OFFICE`, 403). The Head of Department (the department), the Dean (the faculty), the Bursary (`bursar`, `studentaccounts`), the Director of ICT, the Vice-Chancellor and the Deputy Vice-Chancellor read the queue within their scope and decide nothing.

**The acts** (`registration.summer_verify`; **Confirm**, **Not outstanding…**, **Reject…**, **Reopen** on the queue):

| From | Confirm | Not outstanding | Reject | Reopen |
|---|---|---|---|---|
| Pending verification | to Confirmed (OFFICER) | to Not outstanding | to Rejected | nothing to do |
| Confirmed outstanding | nothing to do; an `EVIDENCE_CHANGED` flag is cleared | to Not outstanding | to Rejected | to Pending (clears `verified_via`) |
| Not outstanding or Rejected | to Confirmed, **only** where no removal and no decision credit stand on it | nothing to do, or to the other state under the same condition | the same | to Pending, under the same condition |

- A call decides at most **200** selections (`SUMMER_BATCH_TOO_BIG`); the desk's "Select all N matching" fetches the ids of the queue (the first 5,000) and decides in calls of 200, showing progress and what was refused.
- **Not outstanding** and **Reject** need a reason of **ten characters or more** (`SUMMER_REASON`: "say why, in ten characters or more: the student is shown it"). The student reads `decision_reason` as written. A staff-only note may go with any decision; the student never sees it.
- **Confirm** is refused for a selection whose results show a pass (`SUMMER_PASSED_CONFIRM`: "a pass is on record for this course; decide Not outstanding or Rejected, or leave it flagged"). The portal takes such a course back, so a confirmation could never stand. A flag of another cause (`EVIDENCE_CHANGED`) is cleared by Confirm.
- A selection flagged `ENTRY_REMOVED` accepts only Not outstanding and Reject (`SUMMER_ENTRY_REMOVED`).
- Repeating a decision changes nothing: the call counts it `unchanged`, writes no second history row and sends no second notice.
- One batch reference `SVB-YYYY-NNNNN` goes to every call. One refusal does not stop the rest of the call; the refused ids come back with their reasons (`refused`).
- A decision on a **paid** course is final in V779 (`SUMMER_DECIDED_PAID`: "the course was paid and has been taken off the registration; its fee is a Summer credit for the Bursar"). A decision on an unpaid selection can be reopened or reversed freely.

**The history.** Every state change, flag and clarification writes a row to `registration.summer_selection_review` (write-once: `SUMMER_REVIEW_KEPT` refuses an update or a delete): the batch, the action, from and to, who (or SYSTEM), the evidence, the reason, the staff note, and the money effect (NONE, CHARGE_CANCELLED, CREDITED). The detail drawer on the queue shows it.

**Flags: a selection that needs a person.** The portal never decides a paid course by itself. A selection is marked `needs_review` with one of three flags, and the exam gate counts it until the Office decides it. The desk words them "A pass is on record: decide", "The result this rested on changed" (or, for a selection the authorisation brought in, "The authorisation it rested on no longer stands: decide") and "The course was taken off the registration: decide".

| Flag | Raised when | Leaves by |
|---|---|---|
| `PASSED_ON_RECORD` | A published pass appears for a PAID selection. Its state is unchanged and nothing is withdrawn | Not outstanding or Reject, an override at the gate, or the pass no longer standing (the flag then clears itself) |
| `EVIDENCE_CHANGED` | A selection confirmed by results (`RESULTS`) loses its evidence (a result rolled back, a carry-over cleared): it goes back to Pending, flagged. A selection the Office's authorisation brought in (basis `AUTHORISED`) whose authorisation no longer stands (withdrawn, or no longer naming the course) and which the Office has not decided since: flagged, and one confirmed by that authorisation goes back to Pending (§Reconcile, rule f). A confirmation by an officer is never reverted | Confirm, or Not outstanding or Reject (every decision clears a flag) |
| `ENTRY_REMOVED` | The Director of ICT took a paid course off the registration without a mark (§Money after a decision) | Not outstanding or Reject; or, once the Director has undone the removal, the next reconcile (the student's Summer page or the desk's **Reconcile with results**), which finds the entry live again. The undo alone does not clear the flag, and until a reconcile runs the gate still counts the selection |

**Asking the student.** The Office may ask a clarification (`registration.summer_clarify`: 10 to 500 characters, `SUMMER_NOTE`; not on a decided selection, `SUMMER_DECIDED`). The student is told, and sees the question on the selection. The student may answer with a plain note of at most 500 characters (`SUMMER_NOTE_LONG`; only on their own selection, `SUMMER_NOT_YOURS`). The answer does not change the state: it is a note on the selection, and where a question is open it is also written to the history. A question is cleared by any decision. A clarification is a flag, not a fifth state.

**The type of the registered entry follows the state.** A registered Summer entry is typed `CARRYOVER` while its selection is Confirmed outstanding and `CURRENT` while it is Pending verification, written in one place (`registration.summer_selection_move`) whatever moves the state: an officer, a result, a take-back. `registration.entry_category` therefore calls a pending entry the programme's own Core or GST course, never a carry-over, on the course form, the registration history, the check page and the reports. The portal's rule that forces every course of a spillover student's registration to be a declared carry-over (`registration.entry_spillover_carry`, V674 and V711) leaves semester 3 of a Summer student as entered. For every other registration of a spillover student, and for a CCE or postgraduate student's third semester, it is as it was.

## Fees

The Bursary states the fees for a session, either for every programme or for one programme:

- a **programme fee**, charged once per student per Summer with the first course (₦50,000 by default)
- a **fee per course** (₦5,000 by default)

A statement starts as a DRAFT, and a draft is never charged. Only the **Bursar** (or the Super Administrator) publishes it, which is the approval. A Student Accounts officer can state and delete drafts but cannot publish.

A published statement is never changed. The Bursary states a new one and withdraws the old one with a reason. A charge keeps the figure it was made at. A programme's own published statement takes precedence over the statement for every programme.

Adding a course later charges only that course's fee. The programme fee is never charged twice in a Summer, and nothing in the portal holds the figures: a Bursary statement with other figures changes the next selection and no other. Until a statement is published nothing can be selected (`SUMMER_FEE_NOT_PUBLISHED`, the first test of a selection after the window and eligibility).

**The calculation is itemised.** The student's page shows one row for the programme fee (amount, owed or paid), one row for each selected course (code, title, amount, state), and the formula "₦50,000 + 4 × ₦5,000 = ₦70,000" with the total owed and the total paid. The formula and its total are the server's own (`registration.summer_summary`, `formula.total`, the sum of the student's non-cancelled charges); the browser adds nothing. With a Bursary statement of ₦60,000 and ₦4,000, three courses read "₦60,000 + 3 × ₦4,000 = ₦72,000". A course added after payment costs its fee alone.

**The programme fee follows the last course, whatever takes it.** Whenever the last course charge of a student's Summer stops being DUE or PAID, by any route (for example: the student takes back an unpaid course; the registration closes and takes back what was not paid; the draw of a reference, a payment's confirmation or the reconcile takes back a course whose pass is on record; the Academic Office decides against it), a **PAID** programme fee is cancelled and its money becomes **one OPEN Summer credit** for the Bursar to settle (§Money after a decision), never a refund by itself; a **DUE** programme fee is only cancelled. A programme fee is therefore never left paid for a Summer with no course in it. The rule is one trigger on the charges (`trg_summer_programme_follows`, whatever cancels the course charge), so no route can miss it; its credit's note reads "Programme fee: no Summer course remains after <course> was taken off", and a decision writes the programme fee's credit itself, in its own words.

**A student who selects again in the same window is not charged the programme fee twice.** If the student selects a course again while that credit is still OPEN, the paid programme fee is reinstated from the same payment (the credit is closed as applied: "Reinstated as the programme fee: the student selected a course again in the same Summer"). Once the Bursar has settled the credit, a new programme fee is charged. A credit a reinstatement closed **cannot be reopened** by the Bursar (`SUMMER_CREDIT_REINSTATED`): its money pays the programme fee again, and reopening it would make the same payment both a paid charge and an open credit. **A reinstated programme fee that is cancelled again** (the student's last course goes once more, by any route) **is credited again**, as a new open credit for the Bursar. The money is never lost or counted twice: at every step, the student's paid charges plus open credits equal their confirmed Summer payments.

## Payment

- The student selects courses, which creates DUE charges. They then draw one reference for everything owed (`registration.summer_reference`) and pay it through the gateways every fee uses: card or USSD, Quickteller, or PayDirect at a bank.
- **A student registers and pays before verification.** A selection is registered once it is paid, whatever its state: the Academic Office verifies it afterwards, and the examination gate (§Teaching, examinations and results) holds the examinations until it has.
- A reference is drawn only while the Summer is open.
- A reference is payable only while it covers exactly what is owed now (`registration.summer_reference_payable`). This is checked at the checkout, on the Quickteller page and at PayDirect validation. If the selection changes, the earlier reference is expired at once, and the page draws one for the new figure.
- An expired reference that is regenerated from the payment button gives the reference for what is owed now, never the old figure (a `finance.renew_reference` branch). If nothing is owed, the student is told so.
- Confirmation from any lane goes through `finance.confirm_payment`. The trigger `trg_summer_reference_confirmed` marks the charges that reference was drawn for as PAID. A charge already paid by another reference is left as it is, so callbacks are idempotent.
- `registration.summer_materialize` then makes the registration and tells the student (SUMMER_REGISTERED). The registration is semester 3 of the session, each paid course in its Summer class (opened when first needed), approved by the payment itself (approval mode AUTO). A course paid later joins the same registration. Each entry takes the programme's units, and its type follows the selection (§Verification): `CARRYOVER` once confirmed, `CURRENT` while pending.
- **A selection the student made themselves is not taken back at the draw.** Drawing a reference cancels a DUE course charge whose course is no longer owed. Until V779 "owed" meant "in the carry-over reader's list", which would have cancelled a course the student chose as soon as they drew a reference. `registration.summer_course_outstanding` now keeps an undecided selection standing, whatever its basis, until a published pass, the end of the course or a decision ends it. A carry-over that a later rule clears, or an authorisation withdrawn between selecting and paying, no longer silently cancels a DUE charge, and does not leave it silent either: the reconcile flags the selection for the Office (`EVIDENCE_CHANGED`) and sends a confirmed one back to Pending (§Reconcile), an unpaid one keeps its DUE charge until the Office decides it, and the examination gate holds a paid one. A decided (not outstanding or rejected) selection is never outstanding, so a late confirmation can never revive its cancelled charge. Only a charge with no selection row falls back to the V743 pool test.
- A course the registration cannot take (for example one that ended after it was selected) is recorded as before (`registration.summer_issue`, "Paid, not yet registered", with Retry): the payment stands, and the Office retries it once the cause is put right or decides it (Not outstanding or Reject: the fee is credited). A both-semesters course the student already holds in the First or Second Semester of the session is not such a course: its Summer entry registers (§Selecting courses).
- After the Summer's examinations are open, a payment confirmed late still registers the course (the payment must be honoured). It shows in the desk's live unverified count and in the queue.
- In a session with a Summer, the regular course registration refuses semester 3: "The Summer Semester of … is registered on the Summer Semester page."

## Money after a decision

The University's decision of 23 November 2026: a paid selection later found Not outstanding or Rejected is **taken off the registration, never deleted, and the money becomes a Summer credit the Bursar settles. Nothing is refunded automatically.**

When the Academic Office decides Not outstanding or Reject on a selection:

| The selection | What the portal does |
|---|---|
| **Unpaid** (a DUE charge) | The course charge is cancelled. No credit for the course |
| **Paid** | The course charge is cancelled and a **Summer credit** (`registration.summer_credit`, source `DECISION`, OPEN) is made for its amount, one for each cancelled paid charge (a second attempt on the same cancellation writes no second credit). The entry is **WITHDRAWN** through the removal route below |

In both cases, when the decision takes the student's last standing course, the programme fee goes with it as §Fees says: a PAID one is cancelled and credited, as its own OPEN credit; a DUE one is only cancelled. The same rule applies when the last course goes by any other route, so a programme fee left paid by an earlier decision (because another course was still selected then) is credited when that other course goes.

- **The removal route is the Director of ICT's** (`registration.entry_removal`, V772): the entry is withdrawn, not deleted, with an `RCR-YYYY-NNNNN` reference and the note "Summer Semester course verification", and `trg_entry_removal_holds` guarantees nothing puts it back. The selection records that reference (`removal_ref`). The Academic Office's decision does not go through the Director's office gate; the same record is written.
- **A course that carries a mark** is refused (`SUMMER_HAS_RESULT`): the Director of ICT requests its removal on Course Registration Correction, the Registrar or the Deputy Registrar confirms (V772), and the Academic Office then records its decision on the already-withdrawn entry. The selection takes that removal's reference, so the guard below protects it.
- **A paid charge with no payment on the record** (the payment row gone) is refused (`SUMMER_CHARGE_NO_PAYMENT`: "the payment of this course is not on the record; the Bursary checks it").
- **The credit is shown to the student** on their Summer page as a credit while its payment stands as a Summer payment, and is listed on Summer Semester Fees `/finance/summer-fees` for the Bursar with its source (PAYMENT or DECISION), the reason, the course and the selection's state.
- **How the Bursar settles it** (`registration.summer_credit_settle`, V739, V751; unchanged): **Refunded** at any time, through the existing refund process; **Applied** by hand while another PAID charge still stands on that payment (a part of the payment); a credit that is the whole of its payment is applied by moving the payment on the payment correction desk, whose trigger settles it as applied with the move as its note (`SUMMER_CREDIT_MOVE_IT` when "Applied" is pressed for it by hand). Once the last paid charge of a payment has gone and its credit is OPEN, nothing holds the payment: a Bursary correction may move it, and that is the designed way to apply a whole-payment credit, recorded with the move.
- **Reopen** (`registration.summer_credit_reopen`) puts a credit the Bursar settled by hand in error back to OPEN, with a reason. It is refused for a credit that a reinstatement of the programme fee closed (`SUMMER_CREDIT_REINSTATED`: its money pays the reinstated programme fee), and, as before, for a credit the Bursar did not settle by hand or whose payment no longer stands as the Summer payment (`SUMMER_CREDIT_NOT_REOPENED`).
- **"Applied to the next Summer" is the Bursary's accounting step.** The next Summer's charges are not credit-aware, as V739's credits were not: an applied credit does not by itself reduce the next Summer's fee (Left out, below).
- **A decision on a paid course is final in V779.** The entry has been withdrawn and the credit made. The Office does not reopen it; the Bursar refunds or applies the credit, and the Academic Office authorises the student for the course in a later Summer (Q3).
- **An ICT undo of a Summer decision's removal is refused** (`SUMMER_REMOVAL_HELD`: "this removal was made by a Summer Semester decision (RCR-…); the entry, the charge and the credit stand as that decision left them"), for a removal the decision made or adopted.
- **The Director of ICT may take a paid Summer course off the registration on their own, without a mark.** The removal is applied at once, as for any course, and the selection is **flagged `ENTRY_REMOVED`** for the Office, so a paid course is never silently dropped. The Office decides it (Not outstanding or Reject adopts the removal and credits the money), or the Director undoes the removal and the next reconcile clears the flag (§Reconcile, rule e): the undo alone leaves the flag, so the Office presses **Reconcile with results** before an examination act.
- **A payment is held while a Summer charge stands on it.** A payment correction or an archive refuses a payment while a PAID Summer charge stands on it, and once the Bursar has settled a credit on it (`REALLOC_LINKED`, `PAR_LINKED`: V739, V746, V751; unchanged). A payment that holds only an OPEN decision credit is not held (Left out).

**What the checks hold the money to.** After each decision, and after every other route that takes a course away (an unselect, the window's close, the draw, the reconcile), for the student: paid charges plus open credits equal the confirmed payments; a PAID charge always has an entry; an entry is never WITHDRAWN while its charge is PAID; the programme fee stays PAID while any course stands, and is never PAID with no course charge DUE or PAID beside it; and a credit a reinstatement closed stays closed.

## Teaching, examinations and results

- **Classes.** `catalogue.open_class` lets any course run in semester 3 of a session that has a Summer. The allocation desks (the department's Teaching Allocation and the University's Course Allocation) show the Summer's classes under semester 3, labelled "Summer". Lecturers are allocated there as for any class.
- **Examinations.** Setting the examination dates on the period creates the examination session (session, 3, MAIN, REGULAR). The desk opens it and releases the score sheets. Score entry, approval and publication follow the existing chain.
- **Examination card.** The semester 3 card is issued once the Summer is paid. `registration.exam_card_state` and `registration.exam_cards_withheld` read the Summer's own payment for semester 3, not the session's school fees, and name the period "Summer semester".
- **Results.** A Summer result is released by the Summer itself: its courses are registered only once paid, so a course left selected and unpaid never withholds the paid ones. Where the Bursar's scheme lets a balance owed for an earlier session block everything, it blocks the Summer's results too (V739). The broadsheet lists only those who registered.
- **Results chain.** Approvals, the desk, the chain, the pipeline, the Senate schedule, the broadsheet and the class list offer "Summer semester" (semester 3) in their scope bar, and name it so. The Summer desk links each class to its class list and each student to their record.
- **CGPA.** CGPA reuses the existing rule, which counts every attempt.

### The examination gate

**The examinations are not opened, and the score sheets not released, while a paid course is unverified.** A student who sits a course they already passed gets a lower new attempt, and every attempt counts in the CGPA. The gate is a trigger on the examination session of the Summer (`assessment.exam_session`: session, semester 3, MAIN, REGULAR; `trg_summer_exam_gate`), so it binds both acts whichever desk starts them, the Summer desk or the general examinations desk, and no other sitting (CCE, postgraduate, another semester) is touched.

- **What it counts** (`registration.summer_unverified(session)`): selections with a PAID course charge and a live entry (not DROPPED or WITHDRAWN) in the student's semester-3 registration that are Pending verification, or flagged `needs_review`, or confirmed by an authorisation that no longer stands, or **whose pass is on record now**. The pass, and whether the authorisation stands, are read at the moment of the act: the count never trusts the cache the queue filters on, and the act needs no reconcile before it. An unpaid Pending selection and a withdrawn entry are never counted.
- **When it refuses.** Opening the examinations (DRAFT to OPEN) or releasing the sheets, while the count is above zero: `SUMMER_VERIFICATION_PENDING` ("N paid Summer course(s) are not verified yet; a student who sits a course they already passed gets a lower new attempt, and every attempt counts in the CGPA"; hint: "Verify them on the Summer desk, or record why the examinations may go ahead."). The number is in the message.
- **The sitting cannot be renamed around the gate.** What makes an examination session the Summer's is its identity: session, semester 3, kind MAIN, stream REGULAR, of a session that has a Summer. An edit on the examinations desk (`PUT /api/v1/results/exam-sessions/{id}`, or any other writer: the gate's trigger also fires on a change of `session`, `semester`, `kind` or `stream`) that changes the identity of the Summer's examination session once it has been opened (any state but DRAFT) or its sheets released, or that moves another row into the Summer's identity once that row has been opened or released, is refused (`SUMMER_EXAM_IDENTITY`; hint: "Edit only the dates of an opened Summer examination session."). Otherwise a row could be opened under another kind and given back the Summer's afterwards. A row of any other sitting is edited as before.
- **Opening is also refused while the registration window is open** (`SUMMER_REGISTRATION_OPEN`: "the Summer registration is still open; a payment after the examinations open would put an unverified course on the score sheets"; hint: "Close the Summer registration, or wait for its closing date, first.").
- **An override is a recorded reason for one kind of act** (`registration.summer_exam_override_set`: the Academic Office, the Registrar, the Deputy Registrar or the Super Administrator; ten characters or more, `SUMMER_REASON`). It is kept for the session and the act (OPEN, or RELEASE) with the count at the time, and lets that act through while the unverified count has not grown since. If a late payment adds a course, the gate refuses again, and its message gives the count now and the count at the override.
- **After the act** the live count stays on the desk, with a warning band while the examinations are open, because a late confirmation registers its course and shows in the count and the queue.
- **A flagged selection leaves the count** when the Office decides it (a paid selection whose authorisation was withdrawn is among them, flagged `EVIDENCE_CHANGED` by the reconcile): Confirm for `EVIDENCE_CHANGED`; Not outstanding or Reject for `PASSED_ON_RECORD` or `ENTRY_REMOVED`; or an override. An `ENTRY_REMOVED` selection whose removal the Director undid leaves it at the next reconcile, which clears the flag.
- **A paid, unverified course also holds the student off the graduation queue** until it is decided or its result publishes (it counts as awaiting in `people.lifecycle_completion`, which the graduation readers use). Withdrawing the entry, by a decision, releases the student at once.

The desk's **Reconcile with results** is its own request, run before the act: a refusal rolls the act's transaction back, so a reconcile run inside it would be undone with it.

## Reconcile

Results are uploaded and published while selections stand. **Reconcile** reads each selection's evidence again and settles what the results settle. It runs from the student's own Summer page (once, after it renders, only when a selection of the session is Pending or Confirmed) and from the desk's **Reconcile with results** (tranches of up to 2,000 students, repeated until none is left). A page read never reconciles.

| Evidence found | Selection | What follows |
|---|---|---|
| A published **pass** (a) | unpaid | Taken back: Not outstanding by results, the DUE charge cancelled (and the DUE programme fee with the last course), the student told once |
| | paid | Flagged `PASSED_ON_RECORD`; state unchanged; the entry is **never** withdrawn by the portal |
| | not live (unselected earlier) | Not outstanding by results, with no money and no notice |
| A published **failure** on a Pending selection (b) | | Confirmed by results; a `PASSED_ON_RECORD` flag clears when the pass no longer stands |
| **No result** on a selection confirmed by results (c) | | Back to Pending, flagged `EVIDENCE_CHANGED` (a confirmation that rested on results does not outlive them). A confirmation by an officer is never touched; one by authorisation follows rule (f) |
| Awaited, or no result, otherwise (d) | | Only the evidence cache is stored |
| The entry is live again after the Director's undo (e) | | The `ENTRY_REMOVED` flag clears (the undo itself leaves it; this rule is what clears it) |
| **The authorisation no longer stands** (withdrawn, or no longer naming the course) on a live selection of basis `AUTHORISED` that the Office has not decided since (f) | confirmed by the authorisation | Back to Pending by the system (a `REOPENED` row of history, counted `reverted`) and flagged `EVIDENCE_CHANGED` (a `FLAGGED` row); a registered entry is typed `CURRENT` again |
| | pending, or confirmed by an officer before the withdrawal | Flagged `EVIDENCE_CHANGED` (a `FLAGGED` row, counted `flagged`); the state stays |
| | unpaid | Its DUE charge stays: the portal does not cancel it on its own, and the flag tells the Office why it is asked to decide |
| | paid | Stays registered; the examination gate counts it until the Office decides it |
| | already flagged for another cause | Keeps that flag; no other rule is applied to it until the Office decides it |

- A selection whose own Summer class carries a published result for the student has been **sat**: reconcile skips it, and its stored evidence stays as it was. A later pass, or an F, in the Summer itself never confirms, takes back or flags the selection it settles.
- Each rule leaves a fixed point: a second run changes nothing and writes no history row.
- The student's form returns `{"changed": n}`; the desk's tranche returns `read`, `left`, `confirmed`, `takenBack`, `flagged`, `reverted`, `cleared` (flags cleared: a pass no longer on record, or a removed entry live again), `unchanged` and `batch` (the `SVB-…` reference of the tranche's history rows), and the API adds `since`. The Summer page reads itself again only when something changed.
- The evidence is cached in its own table (`registration.summer_selection_evidence`, not audited) so that the queue filters on it without reading results for each row, and a page read writes no audit row. Decisions and the gate act on a live read, never on the cache.
- **Rule A (the carry-over clearance) is not part of V779.** It will reach the Summer through `registration.carryover_attempts`, which the evidence reads for every failed course: no second copy of the failure logic exists for it to find.

## Who does what

| Office | What it does in the Summer |
|---|---|
| Student | Selects courses from the pool, removes an unpaid one, draws the reference and pays, answers the Office's question, prints the confirmation. Cannot decide eligibility or the pool |
| Academic Office, Registrar, Deputy Registrar (Academic Affairs), Super Administrator (the **setters**) | Set the period and the course ceiling; identify; authorise; tell; reconcile with results; **verify** (Confirm, Not outstanding, Reject, Reopen) and ask the student; open the Summer's examinations and release its sheets; record an override; retry a paid course the registration could not take |
| Registrar, Deputy Registrar | Also confirm or decline the Director of ICT's removal of a Summer course that carries a mark (Course Registration Correction, V772) |
| Bursar, Super Administrator | Publish and withdraw the Summer fees; settle the Summer credits (Refunded, Applied) and reopen one settled by hand in error (never one a reinstatement closed) |
| Students Account Officer | States and deletes draft fees; reads the Summer desk (the menu item is new in V779) and the fees and credits; settles nothing |
| Head of Department | Reads their department's roster, queue, report and classes, and exports them; decides and sets nothing |
| Dean | The same for the faculty |
| Director of ICT | Reads the Summer desk. Takes a paid Summer course off a registration on Course Registration Correction: without a mark the selection is flagged for the Academic Office; an undo of a removal a Summer decision made is refused. Support Agents see a student's Summer page read-only |
| Vice-Chancellor, Deputy Vice-Chancellor | Read the desk |

## Desks

**Student: Summer Semester (`/student/summer`).** The menu item shows only where `registration.summer_area` says the Summer is for the student. Since V779 that includes a student the engine puts at their final level whose level on record is lower. A CCE or postgraduate student does not see it. The page shows, in this order:

1. **Tiles**: the Summer and its period; **You** (category pill and word); **Selected** ("N courses · U units"); **Owed now** (amount, and "₦X paid").
2. The **next step**, in words: "Pay ₦X to register the courses you selected."; "Search your programme's courses and select the ones you believe you still owe, then pay. The Academic Office verifies each against your record."; "N course(s) registered, M waiting for the Academic Office to verify."; "Nothing more can be selected now."; "The Bursary has not published the Summer Semester fees yet."; and, where the window has not opened or has closed, its dates or "Registration is closed."
3. For an eligible student with no detected carry-over: "Your earlier results may not all be on the portal yet. Select the courses you believe you still owe; the Academic Office will verify them. Nothing here says you owe nothing."
4. The **period**, the **fees and itemised calculation** (the programme fee row, a row per selected course, the formula, the total owed and paid, and the Pay button with the reference as before), the **picker** ("Select your courses"), **My selections**, the registration and its confirmation, and the payments.
5. **My selections** lists each selected, registered or taken-off course with its code, title, units, **original semester and session** (or "Not stated"), registration category, registration status (Selected: unpaid, Registered, Taken off), **verification status** (the pill, with "Confirmed by your results", "Named by the Academic Office" or "Confirmed by the Academic Office" beneath, or the evidence word), the **reason** the Office gave for Not outstanding or Rejected (in full), the Office's question with a reply box, and **Remove** for an unpaid course. A totals row gives courses, units and the amount payable.
6. **Print.** A student with a selection prints the **Summer Semester Registration Confirmation** (below).

The **dashboard** shows a Summer card when the student is eligible or has anything selected: "Summer Semester 2025/2026 · SPILLOVER STUDENT" (or FINAL-YEAR STUDENT), the next step, and the counts line "Selected N · pending verification P · confirmed C · not outstanding or rejected R · registered G · units U · payable ₦X", with **Print** (once the student has selected a course) and **Open**; the card says how many courses were rejected and sends the student to the page for the reasons. It reads a slim read-only endpoint (`GET /me/summer/card`), never the whole page.

**The printed confirmation** (`/student/summer/confirmation/pdf`). Titled "Summer Semester Registration Confirmation" once the registration stands (a paid course has its entry on the approved Summer registration), "Summer Semester Selection Summary (registration pending)" while a course is paid but the registration has not taken it (its row reads "Paid, not yet registered"; the Office puts right what stopped it), and "Summer Semester Selection Summary (payment outstanding)" while nothing selected is paid. It prints the student with their category, the period, the courses (S/N, code, title, units, original semester, registration category, registration status, verification status), the totals and the itemised formula, the payments with their receipt numbers, and this notice: "Courses marked Pending verification are registered at your request and are not confirmed carry-overs until the Academic Office verifies them against your record. A course found not outstanding or rejected is taken off your registration and its fee is held for you as a Summer credit." A course the Office decided against is shown struck out with its reason. A course reads "Student-selected course", "Carry-over" or "Authorised course", never "Carry-over" for one the student chose. The **QR** is printed only when the registration is paid: it is the registration check for semester 3 (`/verify/registration`), which answers genuine only for an approved registration, and on that page each course of a Summer student carries its verification word ("Pending verification", "Confirmed outstanding"), never "carry-over" for a pending one.

**Academic Office: Summer Semester (`/summer`).** One page with five views, chosen by `?view=`: **Verification** (the default for the offices that verify), **Students** (the default for the readers), **Reports**, **Courses** and **Period and acts**. The session buttons stay at the top.

- **Period and acts** (the Academic Office, the Registrar, the Deputy Registrar and the Super Administrator):
  - set the period: state, registration window, examination and results dates, categories (three boxes), programmes and levels, and the **course ceiling** with its reason
  - **identify** the eligible students, in tranches of up to 2,000 until none is left (a student's selection writes no candidate row, so the roster's "As identified" date, `identifiedAt`, the latest evaluation of a candidate, and the report's Missing historical results move only with an identification, or with an authorisation or its withdrawal, which re-reads that one student at once as V739 made it; a student who selected before any identification shows a category on the roster from the next one, and a student an authorisation re-read is read again, results and all, by the next identification) (each answer gives the students read, those left and the eligible; its `results` figure, shown as "with results counted", equals the students read, because every student read has their published results counted; how many hold no published result is the report's **Missing historical results**); an identification re-reads every student identified before it, and the first after V779 reads them all
  - authorise or withdraw a student (with the courses it names)
  - **tell** the eligible that the Summer is open, remind those not registered, and tell the registered the examination dates, in tranches walked by a cursor (§Notices)
  - the **examinations** (open; release the score sheets), with the live unverified count and any override shown before the act (the view reads them from `GET /api/v1/summer/{s}/{y}/period`), the warning band while the examinations are open, and the **Override** dialog when the gate refuses
  - the "Paid, not yet registered" panel (with Retry) and the authorisations to look at again
- **Verification** (the queue). Filters: faculty, department, programme, level (the Summer level), status (Pending, Confirmed, Not outstanding, Rejected, Any), evidence, flag (Needs review, Clarification asked), basis, payment (paid or unpaid) and a search; the chips show the counts. A server-paged table of 50: number, name (a link to the record), programme and level, category, course, units, original semester and session, registration category, evidence, status, payment, flag. For the verifiers, a bulk bar: **Confirm**, **Not outstanding…** and **Reject…** (a reason of ten characters or more and an optional staff note, with a preview "N courses, M paid: ₦X will be held as Summer credit and the entries withdrawn"), **Reopen**, **Select all N matching**, and **Reconcile with results** (read, confirmed, taken back, flagged). A detail drawer shows the evidence rows (the student's results of the course and of its twin), the history, the student's other selections and the **Ask the student** box.
  - **What the preview counts.** Each queue row carries three money figures (`registration.summer_queue`): `charge_amount`, the amount of the selection's own live course charge (DUE or PAID; empty when it has none); `programme_fee_paid`, the student's PAID programme fee of the session (empty when none is paid); and `courses_standing`, how many of the student's selections of the session hold a course charge that is DUE or PAID. For the rows ticked, ₦X is the `charge_amount` of every ticked row whose charge is PAID, plus the student's `programme_fee_paid` once for each student whose ticked rows with a live charge number `courses_standing`: the decision then takes that student's last standing course, and the database credits the programme fee with it (§Money after a decision). Where the sum includes a programme fee, the dialog says so. **Select all N matching** has the ids only, so its dialog states the rule in words, without a figure. Offices that only read see the table without the bars. A Head of Department sees only their department's, a Dean only their faculty's: a selection outside the reader's scope is not found.
- **Students** (the roster). Filters: faculty, department, programme, level (the Summer level, with the level on record beside it), category, payment (not started, unpaid, part paid, paid), registration (registered, not registered), scope (**Selected**, the default; **Eligible**; **Everyone**) and a search by matriculation number, name or programme; server-paged; **Export CSV**; and a strip of the figures. Each row carries the counts of the student's selections by state, the programme and course fees due and paid, the payment state, the registration status and the results published, passed and failed.
- **Reports**: §Reports.
- **Courses**: the Summer's classes, with lecturer, registered count, the semester each was failed in, and score sheet stage, as before.

Readers are the Registry, Heads of Department (their department's students and courses only), Deans (their faculty's), the Bursary (the Bursar and the Students Account Officer, who gains the menu item in V779), ICT, the VC and the DVC. Within their scope they see what the Academic Office sees, and they decide and set nothing.

**Bursary: Summer Semester Fees (`/finance/summer-fees`).** Statements can be stated, published, withdrawn and deleted (drafts only). Collections for each session show programme fees and course fees apart. **Credits** lists each Summer credit with its source (the payment, or the Office's decision), the reason, the course and the selection's state, for the Bursar to settle. A programme fee's credit reads "Programme fee" in the Course column and "PROGRAMME FEE" as its source, with its note ("No Summer course of the student remains" when it has none), since it is made whenever the last course goes, by a decision or not. A credit a reinstatement closed offers no **Reopen**: it reads "Pays the programme fee: not reopened".

## Reports

Reports are SQL, set-based and paged, scoped on the server (a Head of Department to the department, a Dean or Faculty Officer to the faculty, a College office to its College; the browser never names the scope), for the Academic Office, Faculty, Department, Bursary and ICT.

`GET /api/v1/summer/{session}/{year}/report` groups by **overall, faculty, department, programme, level or category**, and filters by faculty, department, programme, level, category, selection state, payment state and registration status. Each row gives:

| Figure | Counts |
|---|---|
| Eligible (and the part that is final-year, spillover or authorised) | Students identified as eligible |
| Missing historical results | Eligible or selecting students for whom the portal held no published result when identified |
| Students selected, courses selected | Students and courses with a live selection (a DUE or PAID course charge) |
| Pending, confirmed | Live selections by state |
| Not outstanding, rejected | Selections in those states, live or not |
| Clarifications, flagged | Selections with an open question; selections needing a person |
| Registered students, registered courses | Live PAID charges with a live entry |
| Units selected | The units of the live selections |
| Students not started, unpaid, part paid, paid | The students counted, by payment state |
| Fees paid | Paid charges |
| Outstanding Summer payments | DUE charges |
| Credits open | OPEN Summer credits |
| Selections with no result | Selections whose evidence is "No result on record" |

The unfiltered figures of the Overall report equal the sum of the faculty rows. The level in a filter or a group is the Summer level.

**Exports.** The Verification queue, the Students roster and the Report each download as CSV (`text/csv`, UTF-8 with a byte-order mark, at most 100,000 rows), produced by the server, never assembled in the browser, with the same filters and the same scope as the screen. A cell that begins `=`, `+`, `-` or `@` is written with a leading `'`. Each download is **recorded on the export log** in the same transaction (`platform.log_export`), so Internal Audit's export watch sees it. The selections CSV carries: Matriculation number, Name, Faculty, Department, Programme, Level, Category, Course, Title, Units, Course semester, Original session, Original semester, Registration category, Verification status, Verified by, Result evidence, Needs review, Clarification, Payment, Reason, Decided on.

## Refusals

A refusal raised in SQL reads `CODE: words`. A business rule is HTTP 422 with the code; a refusal the database raises as a permission (`SUMMER_OFFICE` from a verification, the ceiling, an override, a clarification, a reconcile, an identification or a notice, and `SUMMER_CREDIT_OFFICE`) is 403. The remedy shown is the hint where there is one. A write made in ICT Support's read-only view of a student's portal is refused 403 `SUPPORT_VIEW_READ_ONLY`. The codes marked (API) are raised by the controllers before the database is asked; every other code is the database's. This table lists every `SUMMER_*` code a request can receive.

| Code | When |
|---|---|
| `SUMMER_CLOSED` | The Summer is not open for registration (a selection, or a reference drawn) |
| `SUMMER_NOT_ELIGIBLE` | Not eligible. The words: GRADUATED "your award is approved"; NOT_FINAL_OR_SPILLOVER "the Summer Semester is for final-year and spillover students" (hint: "The Academic Office may authorise a student for an approved academic reason."); any other reason "you are not eligible for the Summer Semester (<reason>)" |
| `SUMMER_FEE_NOT_PUBLISHED` | The Bursary has not published the fees of the session (a selection). On Summer Semester Fees (API), withdrawing a statement that is not published |
| `SUMMER_NO_COURSE` | "choose at least one course" |
| `SUMMER_TOO_MANY` | More than 30 different courses in one call |
| `SUMMER_CEILING` | "the Summer allows at most N courses" |
| `SUMMER_COURSE_NOT_AVAILABLE` | A code outside the student's pool |
| `SUMMER_COURSE_REFUSED` | A course in the pool that cannot be selected; the reason follows in words |
| `SUMMER_ORIGIN_INVALID` | An origin whose session is not a session, or whose semester is not 1 or 2 |
| `SUMMER_NOT_SELECTED` | Taking back a course that is not a selected, unpaid course of the student's Summer |
| `SUMMER_NOTHING_DUE` | A reference drawn for nothing |
| `SUMMER_REFERENCE_STALE` | A reference taken to a gateway after what it was drawn for changed, or after registration closed |
| `SUMMER_OFFICE` (403) | A verification, ceiling, override, clarification, reconcile, identification (`registration.summer_identify`) or notice (`registration.summer_tell`) by an office that is not the Academic Office, the Registrar, the Deputy Registrar or the Super Administrator; setting the period, authorising a student or retrying an issue raise it as a rule (422), as they did before V779. The API refuses any other office with 403 before the database is asked, so the code reaches only a person who holds one of those offices but acts in another |
| `SUMMER_SESSION` | Setting a period for a session that is not on the calendar or holds no classes |
| `NO_SUMMER` | An act on a session that has no Summer: identify, reconcile, the ceiling, authorise, an override, tell (API for tell). `GET …/period` answers 404 instead |
| `SUMMER_COURSE_UNKNOWN` | An authorisation naming a course that is not taught |
| `SUMMER_ISSUE_UNKNOWN` | Retrying a "Paid, not yet registered" issue that does not exist |
| `SUMMER_NOT_TO_TELL` (API) | A notice the period cannot carry: OPEN or CLOSING for a Summer that is closed or whose registration window is not dated; CLOSING while the Summer is not OPEN; TIMETABLE before the examinations are dated from and to |
| `SUMMER_EXAMS_NOT_DATED` (API) | Opening the examinations or releasing the sheets before the examinations are dated (no examination session exists yet) |
| `SUMMER_DECISION` | A decision other than Confirm, Not outstanding, Reject or Reopen |
| `SUMMER_NO_SELECTION` | A decision on no selection at all. The API refuses an empty list with 400 before the database is asked |
| `SUMMER_SELECTION_UNKNOWN` | A selection that does not exist. In a decision it comes back in `refused[]` with its id and the rest of the call stands; a question about it is refused |
| `SUMMER_BATCH_TOO_BIG` | More than 200 selections in one call |
| `SUMMER_REASON` | A reason of fewer than ten characters (a decision, an override, a ceiling, an authorisation) |
| `SUMMER_PASSED_CONFIRM` | Confirming a course with a pass on record |
| `SUMMER_ENTRY_REMOVED` | Confirming or reopening a selection whose entry the Director of ICT removed |
| `SUMMER_DECIDED_PAID` | Changing a decision on a course that was paid |
| `SUMMER_HAS_RESULT` | Deciding against a paid course whose class holds a mark of the student, while its entry is not withdrawn |
| `SUMMER_CHARGE_NO_PAYMENT` | A paid charge with no payment on the record |
| `SUMMER_CREDIT_EXISTS` | Cancelling a paid charge whose money, from the same payment, is already a Summer credit: the Bursary checks it. From a decision it comes back in `refused[]`; it can also refuse the act that takes a student's last course while the paid programme fee's money is already a credit |
| `SUMMER_REMOVAL_HELD` | Undoing or cancelling a removal a Summer decision made or adopted |
| `SUMMER_REVIEW_KEPT` | Changing or deleting a verification history row |
| `SUMMER_VERIFICATION_PENDING` | Opening the examinations or releasing the sheets with paid courses unverified |
| `SUMMER_REGISTRATION_OPEN` | Opening the examinations while the registration window is open |
| `SUMMER_EXAM_IDENTITY` | Changing the session, semester, kind or stream of the Summer's examination session once it has been opened or its sheets released, or moving another opened or released row into the Summer's identity (on the examinations desk) |
| `SUMMER_CEILING_RANGE` | A ceiling that is not 1 to 60 or none |
| `SUMMER_NOTE` | A question to the student that is not 10 to 500 characters |
| `SUMMER_DECIDED` | Asking about a selection that is decided |
| `SUMMER_NOTE_LONG` | A student's note of more than 500 characters |
| `SUMMER_NOT_YOURS` | A note on a selection that is not the student's |
| `SUMMER_REPORT_GROUP` (API) | A report grouped by anything but ALL, FACULTY, DEPARTMENT, PROGRAMME, LEVEL or CATEGORY |
| `SUMMER_FEE_NOT_DRAFT` (API) | Publishing or deleting a fee statement that is not a draft |
| `SUMMER_FEE_KEPT` | Deleting or changing a published fee statement (the database's guard behind the API's own checks) |
| `SUMMER_CREDIT_OFFICE` (403) | Settling or reopening a Summer credit in an office other than the Bursar's or the Super Administrator's |
| `SUMMER_CREDIT_NOTE` | Settling with a state other than Applied or Refunded, or a note under ten characters (the API refuses a shorter note with 400 first) |
| `SUMMER_CREDIT_UNKNOWN` | Settling or reopening a credit that does not exist |
| `SUMMER_CREDIT_SETTLED` | Settling a credit already settled, or one whose payment is archived or no longer a Summer payment |
| `SUMMER_CREDIT_MOVE_IT` | "Applied" by hand on a credit that is the whole of its payment: the payment is moved on the payment correction desk, which records the credit applied |
| `SUMMER_CREDIT_REASON` | Reopening a credit without a reason of ten characters or more (the API refuses a shorter one with 400 first) |
| `SUMMER_CREDIT_NOT_REOPENED` | Reopening a credit the Bursar did not settle by hand, or one whose payment no longer stands as the Summer payment |
| `SUMMER_CREDIT_REINSTATED` | Reopening a credit a reinstatement of the programme fee closed: its money pays the reinstated programme fee |

Five more codes guard internal steps and are never reached from a request: `SUMMER_ACT` and `SUMMER_KIND` (the API checks the act and the kind of notice first: an unknown act is 404, an unknown kind 400), and `SUMMER_MOVE`, `SUMMER_FLAG` and `SUMMER_CHARGE_UNKNOWN` (the helpers that move a selection, flag it and credit a charge).

Retired by V779: the reason `NO_OUTSTANDING_COURSE` and the refusal `SUMMER_COURSE_NOT_OUTSTANDING`.

## API

| Method and path | Who | What |
|---|---|---|
| GET `/api/v1/me/summer?session=` | student | Period, eligibility, the pool (`courses[]`, each with its evidence and verification), fee, account, summary, registered courses (with their verification), payments. **Writes nothing** |
| GET `/api/v1/me/summer/card?session=` | student | The dashboard's card: session, period, eligibility, fee, summary. Writes nothing |
| POST `/api/v1/me/summer/select` `{session, courses[], origins[]}` | student | Select courses (DUE charges; at most 30 different in one call); answers as the page does |
| POST `/api/v1/me/summer/unselect` `{session, course}` | student | Take back an unpaid course |
| POST `/api/v1/me/summer/reference` `{session}` | student | The reference for everything owed |
| POST `/api/v1/me/summer/note` `{session, course, note}` | student | A note on the student's own selection, or the answer to a question |
| POST `/api/v1/me/summer/reconcile` `{session}` | student | Read the student's evidence again; `{changed}` |
| GET `/api/v1/me/summer/confirmation?session=` | student | The printable confirmation's data; 404 when the student has no live selection |
| GET `/api/v1/summer/periods` | readers | Every Summer set, each with its gate overrides; `unverified` is null in this list |
| GET `/api/v1/summer/{s}/{y}/period` | readers | One Summer as the desk's Period and acts view reads it: the period, `unverified` (the live count of paid courses not yet verified, `registration.summer_unverified`; 0 without reading results when no course charge of the Summer is PAID) and `overrides`; 404 for a session with no Summer |
| PUT `/api/v1/summer/{s}/{y}` | Academic Office | Set the period; answers as GET `…/period` |
| PUT `/api/v1/summer/{s}/{y}/ceiling` `{maxCourses, reason}` | Academic Office | The course ceiling |
| POST `/api/v1/summer/{s}/{y}/identify` `{since, limit}` | Academic Office | One tranche of identification (the desk sends 2,000) |
| GET `/api/v1/summer/{s}/{y}/students` | readers (scoped) | One page of the roster, with the figures |
| GET `/api/v1/summer/{s}/{y}/students/export` | readers (scoped) | The roster as CSV |
| GET `/api/v1/summer/{s}/{y}/report` and `/report/export` | readers (scoped) | The figures by group, as JSON and as CSV |
| GET `/api/v1/summer/{s}/{y}/selections` | readers (scoped) | One page of the verification queue, with its facets and counts |
| GET `/api/v1/summer/{s}/{y}/selections/ids` | readers (scoped) | The ids of the queue (the first 5,000) and the total |
| GET `/api/v1/summer/{s}/{y}/selections/{id}` | readers (scoped) | One selection with the student, evidence, history and the student's other selections; 404 outside the reader's scope |
| POST `/api/v1/summer/{s}/{y}/selections/decide` `{ids[], decision, reason, note}` | Academic Office | Confirm, Not outstanding, Reject or Reopen up to 200 selections |
| POST `/api/v1/summer/{s}/{y}/selections/{id}/clarify` `{note}` | Academic Office | Ask the student |
| POST `/api/v1/summer/{s}/{y}/reconcile` `{since, limit}` | Academic Office | One tranche of the reconcile |
| GET `/api/v1/summer/{s}/{y}/selections/export` | readers (scoped) | The queue as CSV |
| GET `/api/v1/summer/{s}/{y}/courses` | readers (scoped) | The Summer's classes |
| POST `/api/v1/summer/{s}/{y}/authorise` | Academic Office | Authorise or withdraw a student |
| GET `/api/v1/summer/{s}/{y}/authorisations` | Academic Office | The authorisations to look at again |
| POST `/api/v1/summer/{s}/{y}/tell` `{kind, limit, after}` | Academic Office | OPEN, CLOSING or TIMETABLE notices, one tranche |
| POST `/api/v1/summer/{s}/{y}/exams/{open\|release-sheets}` | Academic Office | The examination session (refused by the gate) |
| POST `/api/v1/summer/{s}/{y}/exams/{open\|release-sheets}/override` `{reason}` | Academic Office | Record why the act may go ahead; `{unverified}` |
| POST `/api/v1/summer/issues/{id}/retry` | Academic Office | Retry a paid course the registration could not take |
| GET/POST `/api/v1/finance/summer-fees` | Bursary | Statements and collections (the credits now carry source, reason, course and selection state); state a draft |
| POST `/api/v1/finance/summer-fees/{id}/publish` and `/withdraw` | Bursar | Approve; withdraw with a reason |
| DELETE `/api/v1/finance/summer-fees/{id}` | Bursary | Delete a draft |
| POST `/api/v1/finance/summer-credits/{id}/settle` and `/reopen` | Bursar | Record a credit as applied or refunded; reopen one settled in error |

"Academic Office" in the Who column means the Academic Office, the Registrar, the Deputy Registrar and the Super Administrator (the setters). "Readers" are those and the Head of Department, the Dean, the Bursary (the Bursar and the Students Account Officer), ICT, the VC and the DVC, **held to their scope on every read**: the scope is the active office's own (a Head of Department's department, a Dean's or Faculty Officer's faculty, a College office's College), taken by the server and never from what the client sends. A value the client names outside it is refused with its own scope refusal.

Deciding, reconciling and identifying each run in a transaction of their own, which the portal runs again as a whole if it loses a deadlock to a late payment's confirmation. The database checks every act again: who may set a period, identify, tell or verify (the office acting, not every office the token carries), that a selection is the student's own, that the course is in the pool, and that the fee is published. Every table is attached to the audit trail, except the evidence cache.

## Notices

The notices use the notification engine's templates, one message per student per event:

- **SUMMER_OPEN**, to the eligible. Reworded by V779 (the students it reaches are all final-year and spillover students, not those with a detected carry-over): "The Summer Semester of [SESSION] is open for registration from [OPENS] to [CLOSES]. If you are in your final year or in spillover, you may select the courses you still owe, from the first and the second semester together, even where your earlier results are not yet on the portal. The Academic Office verifies each course against your record." The `[OUTSTANDING]` count is no longer in the seed text. A body an officer has edited by hand is left as it is, and the migration names it in a notice.
- **SUMMER_CLOSING**, to the eligible who have not paid
- **SUMMER_REGISTERED**, sent on payment
- **SUMMER_TIMETABLE**, to the registered
- **SUMMER_COURSE_REVIEWED** (new, V779), to the student when the Academic Office decides, or the results settle, courses of their selection, or asks them something. The subject is "Your Summer Semester courses of [SESSION] were reviewed"; the body lists each course on a line ("CSC 401: academically confirmed outstanding"; "CSC 402: not outstanding, <reason>"; "CSC 403: rejected, <reason>"; "CSC 404: taken off because a pass is on record") and, where money is held, "N of what you paid is held as a Summer credit; the Bursary applies it to your next Summer or refunds it. Nothing is refunded automatically." It is mandatory. **One notice goes to a student for each decision batch, not for each course.** A question to the student uses the same template, worded as a question.

**The two broadcasts go at low priority.** SUMMER_OPEN and SUMMER_CLOSING are queued at the template priority LOW. The dispatcher sends by priority and then by age, so a broadcast to the 18,588 eligible students of the migrated copy never waits ahead of a payment receipt or a password reset.

**Tranches and the cursor.** `registration.summer_tell(session, kind, limit, after)` tells one tranche of the audience, in student order after the student last taken, and answers how many were told, how many were visited, the last student taken (`next`) and how many remain. The desk repeats with `after = next` until `next` is empty; a tranche is of 1 to 2,000 students (500 by default). A cursor walks the audience and not the absence of a notice: a student with no usable address while portal delivery is off, or a template with no portal body, receives no notice row, and would otherwise be picked again by every tranche and hide the students who can be told. The event key makes a repeated send send nothing.

**The pace.** The mailbox's pace is 30 a minute and 10,000 a day by default (`docs/mail-sending.md`). The first identification on the migrated copy found 18,588 eligible students; at 30 a minute the mailbox could send 43,200 a day, so the daily cap of 10,000 is what binds, and the 18,588 e-mails take two days to leave, in the dispatcher's order, whatever the desk does. The desk sends in tranches because one HTTP request of 18,588 `tell_student` calls would hold the request for minutes, not because of the pace.

## Opening the first Summer

1. Academic Office: on Summer Semester, choose the session, set the period to PLANNED (or OPEN) with its dates, and save. Tick the categories (Final-year, Spillover, Authorised), name programmes or levels only where the Summer is to be limited, and set a course ceiling if the Office wants one.
2. Bursary: on Summer Semester Fees, state the fees for the session. The Bursar publishes them. Until then nothing can be selected.
3. Academic Office: run **Identify the eligible** (in calls of 2,000 until none is left; the desk shows the students read, those left and the eligible, and how many students had their results counted, which is every student read), then **Tell the eligible** that it is open, and set the period OPEN within its dates.
4. Students select and pay. Payment registers them. Detected failures confirm themselves; every other selection waits for the Office.
5. Heads of Department allocate lecturers to the Summer classes (Teaching Allocation, semester: Summer).
6. Academic Office, during and after registration: **Reconcile with results** so the results uploaded since are read, then work the **Verification** queue (Confirm, Not outstanding, Reject; ask the student where the record cannot decide). **Close the registration** (set the period CLOSED, which takes back what was selected and not paid, or let its closing date pass): the examinations cannot be opened before.
7. Academic Office: date the examinations, tell the registered, and **open the examinations**. The gate refuses while a paid course is unverified: verify what is left, or record why the examinations may go ahead (**Override**). Release the score sheets (the gate asks again). Results follow the existing chain.
8. Bursary: settle the Summer credits the decisions made (refund, or apply), on Summer Semester Fees.

## Flagged, not invented

These questions are for the Academic Office to decide:

- **Academic standing.** A student's standing is read from their last regular semester; a Summer does not change it (V739: `assessment.student_standing` leaves the Summer out), and no standing is pronounced on a Summer alone: the Summer broadsheet prints none (V741). Before V739 a Summer read GOOD and let a student on probation escape the probation unit limit.
- **CGPA.** CGPA counts every attempt, as the portal's rule already does. No replacement rule was invented for a Summer pass.
- **Approval of the registration.** A paid Summer registration is approved by the payment. Since V779 the Academic Office verifies each course afterwards instead of before, and the examination gate holds the examinations until it has. If the Office wants a desk approval before payment as well, it is one rule to add.
- **The GST & EPS examination permit.** Decided by the University on 13 November 2026 (V754): a GST or EPS course registered in the Summer has its permit on the Summer payment alone, with no separate GST fee and no school fees for semester 3.
- **The "Third" semester wording.** Decided by the University on 13 November 2026 (V754): semester 3 of a session that had a Summer Semester is named the Summer semester on transcripts, results statements, the student's results and broadsheet, the office broadsheet, the full record and the check pages; any other semester 3 keeps "Third". From V756 this is the Summer only for the students it admits: a CCE or postgraduate student's semester 3 keeps "Third".
- **Old-portal results and carry-overs.** Most past results are on the old portal. A missing result is **never read as a pass**, and **never as proof that nothing is owed**. A final-year or spillover student selects the courses they believe they still owe whether or not the portal holds their result, and the Academic Office verifies the selection against the record it can see. A result the portal does hold decides it: a pass takes the course back (an unpaid one, with the student told) or flags it (a paid one); a failure confirms it. Before V779 the portal treated such a course as not outstanding and the Academic Office had to authorise the student for it by name.
- **A fee withdrawn after a selection.** The charge keeps the figure it was made at (a charge keeps its figure); the student may take the course back and select it again at the published fee.

## Left out / for the owner

**Defaults taken** (listed by the review of the University's prompts of 23 November 2026 and adopted by the build; each stands until the University answers):

- A student is **final-year** when the level on record is at or above the programme's final level **or** the engine says so; **spillover** by the engine's state or the spillover rule; the portal shows "Spillover student" for both spillover names. Authorisation by the Academic Office stays as the exception.
- **Every** spillover student has access, except a Senate-approved graduand and a student whose status is not studying.
- The fees stay ₦50,000 once and ₦5,000 a course, set by the Bursary, itemised and never charged twice.
- A student **registers and pays before verification**; the examination gate and its reasoned override protect the examinations.
- Four stored states; the Office, the Registry and the Super Administrator verify; the Head of Department, the Dean, the Bursary and ICT read within their scope.
- Reconciliation with results is **lazy**: on the student's page after it renders, and by a desk action. Nothing a page read does writes.
- The pool is the structure, the detected carry-overs and the authorised courses, validated on the server.
- The limit of **30 courses in one call** stays as it was, with an **optional cumulative ceiling** per period. A student who owes more selects the rest in a later call.
- The period's programme, level and category limits stay optional.
- Notices go to **every** eligible student, in tranches (§Notices).
- CCE and postgraduate students stay out of the Summer.

**Questions the University has not answered** (the default stands):

- **Q1. May a failed SIWES course be re-sat in the Summer?** *Default: no.* SIWES courses are excluded from every source of the pool, a detected failed one too (SIWES has its own page, its own ₦4,000 fee and its own semester rule: `docs/siwes-registration.md`). Before V779 a failed SIWES course was selectable.
- **Q2. Do College programmes belong in the Summer at all?** (MBBS, C00061, and the College of Health Sciences.) *Default: as today.* They are undergraduate, so they are in. The period's programme limit is how the Academic Office keeps them out.
- **Q3. Who may correct a wrong decision on a paid course?** *Default: nobody in V779.* The Bursar refunds the credit or applies it, and the Academic Office authorises the student for the course in a later Summer.

**Not built, said plainly:**

- **An applied credit does not by itself reduce the next Summer's fee.** The credit is settled by the existing mechanics (§Money after a decision): refunded at any time; applied by hand while another paid charge stands on the payment; a whole-payment credit applied by moving the payment on the payment correction desk. "Applied to the next Summer" is the Bursary's accounting step, and the next Summer's charges are not credit-aware.
- **A hold on a payment that has only an open decision credit left** is not added. It would restate `finance.payment_reallocation_check` and `finance.payment_archive_refusals`, which V777 and V781 also restate. It is an option the University may take after the merge.
- **A decision on a paid course is not reversed in V779** (Q3).
- **Electives and Deficiency courses are not offered** in the pool (an elective is never owed, V689). An elective or other course the Office wants a student to take is named in an authorisation, which also makes it confirmed.
- **The limit of 30 courses in one call** (above).
- **The old selection of a SIWES course** that an older Summer charged stays: it reads as registered, and its selection row is written by the migration.
- **Charges made before V779.** The migration gives every non-cancelled course charge a selection row, confirmed, so type and state agree. Pre-V779 Summer entries of spillover students (typed `CARRYOVER`, declared) are left as they are.
- **Rule A, the carry-over clearance,** comes after the Summer and is not part of V779.

## The reviews of V735 to V756, as built

The sections below are the record of what V739 to V756 answered, written when each was built. Where V779 changes one of those rules, the sections above say so and are the ones that hold now. The changes that touch the record below:

- **Eligibility** no longer tests for an outstanding course (V739's "Eligibility" bullet: every category a student falls in is read, and the first the period admits is reported, still holds).
- **`registration.summer_course_outstanding`** (V742, V743) keeps an undecided selection standing whatever its basis, and tests the pass with `registration.summer_passed`; `registration.summer_courses` (the evidence pool the V735 to V743 checks pin) is untouched.
- **The Summer entry's type** is `CURRENT` while its selection is pending and `CARRYOVER` once confirmed (V739's "with entry type CARRYOVER" is now the confirmed case).
- **`registration.summer_candidate.outstanding`** is stored as 0 from the first identification after V779, and the desk no longer shows it.

## The review of V735 (V739)

An adversarial review confirmed 31 defects; V739 and the same change answer them.

- **Money.** A payment confirmed after its selection changed now pays, in order:
  1. the charges it was drawn for that are still owed;
  2. those taken back since, where nothing stands in their place and the course is still outstanding;
  3. the student's other charges still owed, programme fee first and never a course before it.

  Anything left is an unapplied Summer credit (`registration.summer_credit`), listed on Summer Semester Fees for the Bursar to record as applied or refunded. The programme fee is never paid twice, and the other open references of the Summer are closed. An open reference is shown only when it may be paid, at its own amount.
- **A registration that fails never undoes a payment.** Courses are registered one by one. A course the registration cannot take (for example one ended since it was chosen) is recorded (`registration.summer_issue`) and listed on the desk as "Paid, not yet registered", with Retry. A Summer class already open is reused.
- **Drawing a reference** takes back a course no longer outstanding or no longer taught. A reference that still holds an ended course is not taken to a gateway.
- **A paid Summer payment** is neither moved by a payment correction nor archived while it pays registered courses (`REALLOC_LINKED`, `PAR_LINKED`).
- **Closing a Summer** takes back what was selected and not paid and closes its open references. An unpaid course may be removed after the close. The student's page says registration has closed, or when it opens.
- **School fees.** A Summer registration is no school-fees semester (`finance.reg_semesters`, `finance.registrations_without_fees`), so a spillover student who takes only the Summer owes no whole-session spillover line because of it.
- **Eligibility.** Every category a student falls in is read, and the first the period admits is reported.
- **Units.** Summer entries carry the programme's own units (`catalogue.units_for`).
- **Identification.** Each run re-reads every student identified before. Authorising a student, or withdrawing it, re-reads them at once.
- **The desk.** It is held to the active office's unit, whatever other offices the token carries, and refused in an office that does not read it. Notices are refused before their dates are set or after the Summer closes, and a changed window or timetable is told again.

## The review of V739 (V741)

A review of those fixes confirmed 13 more; V741 and the same change answer them.

- **School fees, in the bulk readers too.** `finance.fee_profiles`, which feeds the School Fees Report, the Spillover desk, Student Accounts and the College and HOD views, leaves a Summer registration out, as `finance.reg_semesters` does.
- **No standing on a Summer.** V739 let `assessment.standing_of` speak for semester 3, so the Summer broadsheet printed probation or advice to withdraw on the Summer alone. It is silent again; the student's standing stays that of the last regular semester.
- **A credit follows its payment.** A credit whose payment is archived, or no longer stands as a Summer payment, is not shown as the student's nor listed on Summer Semester Fees. (V741 also refused to move or archive such a payment until the credit was settled; V742 replaced that refusal, below.) "Applied" records where the money went (the voucher, the reference or the desk that moved it); it moves no money itself.
- **Drawing a reference after a take-back.** When every chosen course is taken back (passed since, or no longer taught), the take-back stands and the student is told nothing more is owed. A course passed since it was chosen is taken back even when the Academic Office authorised it.
- **A late payment** never revives a passed course, nor the programme fee alone with no course: the money stands as a Summer credit.
- **The results chain's scope bar** shows a Summer chosen elsewhere as the Third semester on screens that do not offer the Summer, instead of "Both semesters". (Superseded by V756, below: the bar names semester 3 by session and stream on every page.)
- **The desk's class-list links** are offered only to the offices that may open a class list; the Bursary offices see the course code.

## The review of V741 (V742)

A review of those fixes confirmed four more; V742 and the same change answer them.

- **A passed course is never paid for.** A reference that holds a course no longer outstanding (passed since it was chosen, an authorised one too, or no longer in the student's pool) is not payable: the student's page drops it and Pay takes the course back. A payment confirmed anyway, made at a bank before the pass, pays no such course. The course is taken back first, along with the programme fee when no course stands beside it, and the money stands as a Summer credit (`registration.summer_course_outstanding`).
- **The credit follows its payment instead of holding it.** A payment with an open Summer credit may be moved or archived like any other.
  - Moved off the Summer (another purpose, session or student), the credit is settled as applied, with the move as its note. Moved back, it is open again.
  - Archived, the credit stays open and out of sight until the payment is restored.
  - The Bursar records applied or refunded only while the payment stands as the student's Summer payment.
- **The check of the bulk readers** now uses a spillover student who registers only in the Summer, and fails if `finance.fee_profiles` counts the Summer again.

## The review of V742 (V743)

- **A passed course is not outstanding, however else the pool describes it.** The pool names an ended or unknown course before a passed one. So a course the Academic Office authorised, passed since and then ended, read as outstanding, and a payment confirmed anyway paid for it. `registration.summer_course_outstanding` now tests the pass itself, as the pool does. An ended course that is not passed stays outstanding: once paid, it is the desk's issue (V739).
- **The payable test is quick.** Testing whether a course is still outstanding reads the student's pool and results. It is declared at that cost, and payable tests only the reference's own course charges, so checkout and the gateways' validation never test every Summer charge in the table. One payable test with 48 charges in the table took 1.9 s before this and takes 0.3 s now.
- **The check of the bulk and per-student readers** states a spillover school-fee line for the student's programme, so a Summer counted again shows as a charge the bulk reader owes and the per-student reader does not.

## Findings left open by the reviews of V742 and V743 (V746)

- **An authorisation follows its course.** The Academic Office's authorisation names its courses by code. A code corrected (`catalogue.correct_course`, `rename_course`) or merged away (`catalogue.merge_course`) left the authorisation naming a dead code, so the student's paid course was taken back into credit and could not be chosen again. Every authorisation naming a code now follows it to the new code (triggers on the course's code and on the merge's alias). Authorisations that already named a dead code were put right from the merge aliases and the code-change trail; the migration's notice counts them.
- **A settled credit holds its payment.** Once the Bursar records a Summer credit as refunded, or as applied somewhere else, that money is spent. The payment it names is then neither moved by a payment correction nor archived (`REALLOC_LINKED`, `PAR_LINKED`), as a payment that paid registered Summer courses is not. A credit still open follows its payment, as V742 made it.

## The review of V746 (V751)

- **A settled credit holds its payment only while the payment stands as the Summer payment.** A payment moved before V746 after its credit was refunded can be moved back or archived, so the double count V746's notice counts can be undone on the correction or archive desk.
- **A credit that is the whole of its payment is applied by moving the payment** on the payment correction desk; the move records it (`SUMMER_CREDIT_MOVE_IT` when "Applied" is recorded by hand). A credit settled by hand in error is reopened by the Bursar with a reason, on Summer Semester Fees (*Reopen*; `POST /api/v1/finance/summer-credits/{id}/reopen`, `registration.summer_credit_reopen`), while its payment stands as the Summer payment. Settling goes through `registration.summer_credit_settle`, which checks it all again.
- **A course code followed from the grant.** `registration.summer_code_after(code, since)` follows a code forward from the date an authorisation was granted, through renames and merges in the order they happened, and never to a later course that took the old code.
  - Authorisations still naming a dead code are put right with it, including a code renamed and then merged.
  - Those V746's one-off repair rewrote to another course than this gives are counted in the migration's notice for the Academic Office, and not changed.

## The review of V751 (V753)

- **The course is followed, not its code.** `registration.summer_code_after` follows the course an authorisation named, by its id, through its renames and through a merge to the course kept. A newcomer that took one of its old codes is never chosen (before, a course renamed twice whose middle code was then reused went to the newcomer).
- **The repair re-runs, each authorisation once.** Authorisations still naming a dead code are put right again with it.
- **The notice counts authorisations.** V746's and V751's choices are brought forward to today before they are compared with the trail from the grant. The migration's notice counts authorisations either rewrote otherwise, for the Academic Office (not changed).

## Follow-ups (V754, 13 November 2026)

- **The GST & EPS permit in the Summer.** `registration.gst_eps_permit_state` reads a Summer registration (`registration.is_summer`) on its own terms:
  - the permit is available once the Summer is paid, with no GST fee and no school fees asked;
  - before the Summer registration exists, it says to select on the Summer Semester page;
  - its JSON, and the examination card's, carry `summer`, so the screens, the PDFs and the check pages name it the Summer semester.
- **"Summer semester" on results documents.** Transcripts (`credentials.build_statement`'s semester blocks carry `summer`; an issued document's frozen statement without it keeps "Third"), the statement of results, the student broadsheet, the Results screen, the office broadsheet and the full record name semester 3 of a Summer session the Summer semester — for an undergraduate outside CCE (V756).
- **Authorisations to look at again.** The Summer desk lists, for the Academic Office (`registration.summer_authorisations_to_review`, `GET /api/v1/summer/{session}/{year}/authorisations`), authorisations naming a course no longer on the catalogue and those a one-off repair (V746, V751, V753) rewrote otherwise than the trail from the grant gives. Nothing is changed: the Office re-authorises with the Authorise form. The list exports to Excel.

## The Summer for the students who take it (V756, 13 November 2026)

The Summer Semester is semester 3 of its session for an undergraduate outside CCE: the students `registration.summer_eligibility` admits. CCE and postgraduate students have a third semester of their own, and in a session that also had a Summer it stays their third semester. `registration.is_summer_for(student, session, semester)` answers this for a student. These read it:

- the examination card and its withheld list (`registration.exam_card_state`, `registration.exam_cards_withheld`). A CCE or postgraduate student's semester-3 card asks for their own fees, not a Summer payment;
- the release of results (`finance.results_cleared`) and the academic standing (`assessment.student_standing`);
- the semesters registered for school fees and the registrations-without-fees list (`finance.reg_semesters`, `finance.fee_profiles`, `finance.registrations_without_fees`);
- the course registration gate, the student's Summer menu entry (`registration.summer_area`), the GST & EPS permit, and the transcript's and statement's `summer` flag;
- in the API, `summerSessions` on the student's results and the full record (now per student), the results check page, and the office broadsheet (`summer` only on a regular sheet).

A class opened for semester 3 still runs any course (`catalogue.open_class`), because a class is not a student. The GST and EPS offices' permit roster still says "Third" for semester 3: one roster can mix Summer students with CCE or postgraduate students.

From the review of V754 and V756:

- **Standing.** A CCE or postgraduate third semester now counts towards the standing, read by the end-of-session rule (the rule of a second semester). `assessment.standing_of` gives nothing for a semester 3, which now only the Summer is. On the broadsheet, a CCE or postgraduate sheet's semester 3 gets the same rule.
- **Session-wide reports.** These test `semester = 3` first, so only semester-3 rows ask `registration.is_summer_for`.
- **The student's result status.** The Summer is in progress until its results are due (the end of its examinations where no date is set), and the status names it the Summer semester. A withdrawn or restored Summer permit's message names it too.
- **The Summer's examination notice.** It goes only to the Summer's own students. A broadsheet leaves out its DID NOT REGISTER rows only on the Summer's own sheet (regular stream, a session with a Summer).
- **Authorisations to look at again** read a rewritten authorisation as it stands now. It leaves the list once revoked, once re-authorised after the repair, or once it names the course the trail gives. A course a repair took is listed once, and the desk counts each student's authorisation once.
- **The scope bar** names semester 3 by session and stream on every page. On a page of one stream (the broadsheet, Senate, the class list, which reads a course's regular class) it reads "Summer semester" for the regular stream of a session with a Summer, and "Third semester" otherwise. Any other page lists every stream, or names none: there it reads "Summer and third semester" in a session with a Summer (the pipeline, approvals, the desk, choosing a sheet, the reports). With no session chosen it reads "Summer or third semester". The Course Allocation and Teaching Allocation desks title a Summer session's semester 3 "Summer and third semester" and mark each class Summer or third semester. The lecturers' score-sheet list says "Summer or third".
- **Names on screens.** The Summer is named on the results-chain screens, the course form and its check, the registration history, the examinations page and the full record's level table, wherever the regular stream of a session with a Summer is meant. The examination card check reads the card's own payment (the Summer payment for a Summer card).

