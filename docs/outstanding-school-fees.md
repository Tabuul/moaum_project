# Outstanding school fees of past sessions, shown to and paid by every student (V720)

The University's brief of 11 November 2026: undergraduate and postgraduate students, studying or graduated, must see every
outstanding school fee from past sessions and semesters on their dashboard and pay each through the existing gateway. The brief
said detected outstanding payments "are not consistently displayed on students' dashboards, particularly for graduated students",
and asked for the root cause first.

## What was investigated, and what stood

The portal holds two engines that say what a student owes.

- **The current-session engine** — `finance.position`, `finance.charges`, `finance.due_for_semester`, `finance.session_positions`
  — reads a session's fee lines for the student *as they are now* (the level today). It is right for the current session and wrong
  for a past one: a 300 Level student owing their 100 Level session finds no 300 Level line in it and reads "nothing due".
- **The historical engine** (V654, V665, V683, V693) — `finance.historical_rows_read` → `finance.historical_rows` →
  `finance.historical_account` — reads every session of the record from the Bursar's assessment start, each at the level the
  student had then (a postgraduate student's stage lines; an approved assessment; approved waivers), allocates a session's payments
  first semester first, and gives each period a status. **It reads any student, undergraduate or postgraduate, studying or graduated,
  and on controlled records it was right for every one of the brief's twelve scenarios** (a graduate owing a whole session, one who
  paid the first semester only, several sessions, an active student's arrears, a partial payment, everything paid, a pending gateway
  reference never counted as paid, and the postgraduate cases). It is the authority for past periods and is not rebuilt.

## Root causes

1. **The dashboards never read the historical engine.** `GET /api/v1/me` carried one session's `finance.position` and a yes/no
   `hasArrears`; neither the undergraduate home (`Screens1.tsx`) nor the postgraduate home (`PgDashboard.tsx`) fetched
   `/me/historical-fees`. A graduated undergraduate record's home said "School fees and course registration are closed on this
   record".
2. **The fees page threw the rows away for anyone not graduated.** `/me/historical-fees` returned every student's past periods;
   `fees/page.tsx` rendered them only when `graduated`.
3. **A student still studying had no pay door for a past session.** `finance.historical_reference` refused anyone not graduated
   (`HFA_PAY_GRADUATES`, "a student still studying pays from the fees page"); the fees page priced the past session at today's
   level, behind that session's payment window.
4. **The desk's lists were graduate-only** because `finance.historical_refresh` / `historical_refresh_stale` kept a summary
   (`finance.historical_summary`) for graduates and approved graduands alone, and the payment trigger marked stale only students
   who already had one.
5. **A postgraduate student's "past" was bounded by the University's calendar**, not the School of Postgraduate Studies' — their own
   current session could be read as history when the two calendars differ.
6. **The biodata gate** could keep a graduated student off the fees pages: `/me/fees` and `/me/historical-fees` were not on its open list.

## What V720 changes

- **Database (`db/V720__…`).**
  - `finance.historical_rows_read`: a student's past ends before the current session of *their* calendar (`finance.session_before`
    of the University's, the School's or the Centre's session), as `people.student_current_session` reads it.
  - `finance.historical_reference`: any student whose historical account lists the session with a balance may pay it — online
    payment on, never more than owed; an open, unexpired reference for the same session and amount is handed back rather than a
    second one minted. The current session is not on the account and is refused (`HFA_NOTHING_OWED`): it is paid on the fees page.
  - `finance.historical_population(status, id, entry_session)`: ACTIVE, PROBATION, GRADUATED or an approved graduand, with an entry
    session. `historical_refresh(NULL)` and `historical_refresh_stale` cover it; the payment trigger marks any of them stale; the
    migration works the population out once in batches of 2,000.
  - `finance.historical_summary` gains `whole_sessions` (sessions owed with nothing paid) and `part_sessions` (something paid, a
    balance left).
  - The School of Postgraduate Studies (`pgschool`, `pgsecretary`) gets the desk's read grants.
- **API.**
  - `GET /api/v1/me/outstanding-fees` (`StudentPortalService.outstandingFees`): every past period from the historical account
    (with V683's review flags) and the current session from the fees position by semester — each with session, period, level, due,
    paid, balance, a status in the brief's words (UNPAID, PARTIALLY_PAID, PAYMENT_PENDING, PAID, plus CREDIT and BEING_ASSESSED),
    the open reference that pays it, whether it is payable and by which door; a summary (sessions and periods owed, items, total,
    what open references await, what is paid); whether sessions before the assessment start are unlisted.
  - `POST /api/v1/me/outstanding-fees/references {session, amount}`: a past session through `finance.historical_reference`, the
    current session through `newReference` (its window, its position). The student is the token's; no id is taken from the request.
  - The historical desk (`HistoricalFeesController`): `/students` takes `scope` (GRADUATES, ACTIVE, ALL), `type` (UG, PG), `level`
    and the filters `ACTIVE_OWING`, `WHOLE_SESSION`, `PART_SESSION`; `/figures` adds `population` (standing × programme type);
    `/report` and `/clearance-report` take `scope` and `type` and carry academic status and programme type. The School of
    Postgraduate Studies reads postgraduate students only, whatever the screen asks.
  - The biodata gate's open list gains the fee reads, the reference doors and the payment checkout, so a balance never waits on a form.
- **Screens.**
  - `OutstandingFeesCard` (`app/student/OutstandingFees.tsx`): the summary tiles, the rows owed (session, period, level, fee, due,
    paid, balance, status, Pay now), the pending reference with pay-by-card, the settled rows on request, Excel and PDF; the button
    is disabled while a reference is made; the historical door's rule is said ("a session's payments settle its first semester first").
  - The undergraduate and postgraduate homes render it whenever something is owed, pending or being assessed; the graduated note no
    longer says fees are closed when a balance stands; the fees tile and the PG "Outstanding fees" tile read the cross-session total;
    the PG eligibility "School fees settled" is not met while any session owes.
  - The fees page renders the card and the historical breakdown for every student with periods.
  - The desk: Standing, Programme type and Level filters, a Standing column, three new doors; the reports take standing and programme
    type and print them; the Bursar's and the Students Account Officer's dashboards show the population tiles.

## V723: what the review of V720 found, and what changed

An adversarial review of V720 (four finders, two refuters a finding; fifteen findings stood) led to V723, the same day.

- **A departed student read as owing sessions never attended.** `finance.historical_rows_read` bounded every student not graduated
  by the session before their calendar's current one, so a student WITHDRAWN, EXPELLED, TRANSFERRED_OUT, RUSTICATED, DORMANT,
  DECEASED or on VOLUNTARY_WITHDRAWAL years ago read as owing every session since; V720's payment trigger kept a summary for them and
  the pay door would have taken their money for those sessions. A student who has left (or was admitted and never came) is now
  bounded by the last session they enrolled or registered in, as `records.graduation_session` falls back — never past the calendar's
  bound; with no such session, no past at all. ACTIVE, PROBATION, DEFERRED and SUSPENDED keep the calendar's bound. The pay door
  follows the account and is not changed.
- **The summary is kept for the population alone, and follows the student's standing.** The payment trigger marks only students
  of `finance.historical_population`; `historical_refresh` given names outside it removes their summary and mark;
  `finance.historical_mark` — called by a trigger on `people.student` (status, entry session) and one on `records.graduand` (an
  approved award given, withdrawn or moved; an entry awaiting the Senate changes nothing) — marks a student of the population stale,
  an existing summary too (a corrected entry session moves the first session, a graduation by reconciliation the last), and removes
  summary and mark for one outside it; summaries and marks outside the population were removed once.
- **A calendar's move marks its studying students.** When a session is made current on the University's, the School's or the
  Centre's calendar, every studying student's past ends one session on. The end last seen on each calendar is kept
  (`finance.historical_bound`); a statement on `policy.academic_session`, `admissions.pg_academic_session` or `policy.study_route`
  that moves it marks that calendar's studying students stale (`finance.historical_bounds_moved`). The desk then works them out
  500 a read, or the Bursar's full refresh does it at once. Opening a student's record on the desk refreshes their summary for any
  student of the population, not graduates alone.
- **A postgraduate student's bound read `admissions.pg_current_session()`**, whose literal fallback ('2025/2026') is reached when the
  School has no CURRENT row and the University is between sessions: their last finished session dropped off the account. The
  School's own CURRENT row is read directly, the University's session when it has none. The postgraduate population was marked
  stale once for the new bound.
- **`/me/outstanding-fees`.** A graduate (or approved graduand) whose award is of the session the University stands in read that
  session twice, as the past and as the current; it is read once, as the past. Only the newest open reference of a session was
  attached and counted: every open reference of a session is now attached to one owed row of it (the row whose balance it
  matches first, else the next owed row, oldest first) and `summary.pending` sums the references shown on rows (a leftover
  reference of a settled session counts for nothing). A current session charged for the
  first semester alone (a spillover student's semester, a second semester not yet stated) was labelled "Entire session"; it is
  the first semester, and "Entire session" is kept for a whole-session structure. A past session takes one Pay now, on its first
  owed period (the historical door's payments settle the first semester first); the row also offers the session's whole balance
  (`sessionBalance`), and the later rows say they are paid from the first (`payNote`). `POST /me/outstanding-fees/references`
  routes by the same rule: a session on the historical account goes through the historical door (the graduate of the current
  session too), the current session otherwise through the fees page's door.
- **The School of Postgraduate Studies read any student by id.** `/students/{id}`, an assessment, a waiver, payment evidence and
  their files are not found for the School when the student is not postgraduate; the assessment, waiver, evidence, reconciliation
  and quality lists, the figures (assessments, evidence, waivers, batches pending, ready to graduate), the cohort batches, the
  reconciliation runs (listed when they hold postgraduate students, counted over them) and the evidence search carry the same
  bound (`pgOnly()`, `PG_ONLY_WHERE`, `PG_BATCH`, `PG_RUN_COUNTS`); so do a payment-evidence record's candidate payments (an
  undergraduate payer is not shown to the School) and its old-portal holds (not shown to the School).
- **Screens.** The card resyncs from the server's read (a reference minted on the fees page's historical form is seen by the card
  before the next Pay now), keeping the note on a reference just made while the rows still carry it; each row shows its own
  reference, never one session-wide; the postgraduate "Outstanding fees" tile
  reads "—" with "N fee periods being assessed" while a period is assessed and "Not yet stated" while the charge is unstated,
  never "₦0 · Nothing owed"; the progress page grades "School fees settled" across every session, as the dashboard does; the
  graduated note's punctuation.
- **Reports and tests.** `/report` takes `admission` (the entry session) so an integration test's students are never cut by the
  3,000-student cap; `HistoricalFeesIT` gains the departed student, the two references on one session (and a leftover reference
  of a settled session counted for nothing), the graduate of the current session (read once, and paid through the historical
  door), the postgraduate bound with no School row, the School's 404 on an undergraduate, an undergraduate's assessment, cohort
  batch and reconciliation run seen by the Bursary and not by the School, and the report's admission filter; the V720 test drains
  the queue before reading the desk. check.sql gains V723 (EXPECTED 550): the departed student, the stale and summary rules, the
  calendar's move, the corrected entry session, the graduation list awaiting the Senate and an approved award, and the postgraduate
  bound with no School row.
- **CI** (its own commit, before V723). The runners' apt mirror list, led by azure.archive.ubuntu.com, stopped resolving on
  11 November 2026. The image already ships PostgreSQL 16's client and Chromium's libraries, so those steps no longer need apt.
- **V723 reviewed in turn** (three finders, two refuters a finding: five stood, seven refuted) — the stale mark on an existing
  summary, the door for the graduate of the current session, pending from the rows, the School's remaining reads and the card's
  note are the five, fixed above. Those fixes were verified (all five resolved) and the verification's own findings — the
  calendar's move, the graduation list's unapproved entries, the evidence record's candidates, the tests asserting the School's
  bounds with data — are fixed above too.
- **Not changed from the review:** V720's `ALTER TABLE` and backfill ran in one transaction (the lock held through the backfill);
  the migration has run and is not rewritten — a later migration that adds a column and backfills should commit the DDL first.

## V725: a past period's level counts the merged session once

A past period with no registration or enrolment is charged at the level the cohort engine counts (`people.counted_sessions`): a /19/
student's 2022/2023 is 300 Level's line, not 400 Level's, and their final year 2023/2024 is the final year, not a spillover year. See
`docs/session-2019-2020-merged.md`.

## V738: admissions of 2019/2020 to 2021/2022 are assessed from the session after admission

The University, 12 November 2026, over a student admitted 2021/2022 who was billed 100 Level fees for 2021/2022 and one level high
after it: those admissions began their first year in the session after they were admitted (the merged session; the calendar caught up
at 2022/2023). The engine now assesses nothing before the first year and counts a period's level from it (`people.first_session`,
`policy.cohort_start`). A 2021/2022 admit's account starts at 2022/2023 at 100 Level, and 2023/2024 is 200 Level. A registration's or
enrolment's own level still stands. See `docs/session-2019-2020-merged.md`. V740 keeps money recorded on the admission session as a credit
on a period with nothing assessed, and reads the card's "not yet assessed" note from the first year.

## Not changed, on purpose

- Sessions before the Bursar's assessment start (`finance.historical_start()`) stay unassessed and unlisted — the University's word of
  25 October 2026; the card says so when the student entered before it.
- `finance.position.has_arrears` and the registration gates are untouched: the brief keeps academic restrictions as they are.
- `admissions.pg_current_session()`'s literal fallback ('2025/2026') is a separate defect.
- A refund or a carried overpayment still stands with the Refunds & Credits desk, not the historical account.

## Checked

- check.sql V720: the five made-up students (two studying, a graduate, a postgraduate studying and one graduated) read as owed by the
  engine; the summary kept for the students studying with the sessions owed in whole and in part; the student studying's reference
  (the same one the second time; the current session and more than the balance refused); a payment marks them stale and the next read
  refreshes; a postgraduate student's past moves with the School's calendar. The V654 check now expects `HFA_NOTHING_OWED` for the
  student still studying who owes nothing.
- `HistoricalFeesIT.outstandingFeesOfPastSessionsAreShownToAndPaidByEveryStudent`: the three students' `/me/outstanding-fees`,
  the past session paid through the historical door with the purpose naming the session, the same reference on a second click,
  PAYMENT_PENDING never counted as paid, more than the balance refused, the current session through its own door, the desk's
  scope/type filters, the School reading PG only, the figures' population and the report's scope.
- `lib/outstanding-fees.test.ts`; `lib/historical-fees.test.ts` (the report columns).
- `BiodataGateIT` now expects the fee reads and the reference doors open while the gate holds a student (the brief: a balance is seen
  and paid regardless); the other student pages stay held.
- Scratch copies made with `CREATE DATABASE … TEMPLATE` do not carry V717's per-database `DateStyle`; set it on a copy before running
  check.sql there, or its V717 block fails for that reason alone.
