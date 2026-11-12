# The 2019/2020 session merged into 2020/2021 (V661)

The University's word of 26 October 2026: the 2019/2020 and 2020/2021 sessions were run as one. So students who entered in 2019
(matriculation numbers with `/19/`) are one spillover year behind what straight counting gives: in 2025/2026, those in four-year
programmes are **SP2**, not SP3, and those in five-year programmes are **SP1**.

## How the portal reads it

The portal has carried merged sessions since V331. On the Student Cohorts screen (Policy → Academic sessions), **Cancel and merge**
marks a session CANCELLED and merged into the session that carried its students. From then on:

- **Its entrants** are counted from the merged-into session (`policy.effective_session`): a 2019/2020 entrant's first counted session
  is 2020/2021.
- **Everyone in study across it** doesn't count it (`policy.session_after`, `policy.sessions_elapsed`). The University chose this for the
  2017/2018 and 2018/2019 entrants too.
- **Every student's position** is recomputed on the merger (`trg_position_session`). That covers the spillover year, the expected final
  year, the data-quality "beyond the maximum period" figure, and the spillover school-fee lines that follow the SP year.

## What V661 does

- **Adds the two sessions:** 2019/2020 and 2020/2021 are added to the calendar where missing, as past, closed sessions. The calendar
  had begun at 2021/2022.
- **Merges them:** 2019/2020 is merged into 2020/2021 through `policy.merge_session`, with the reason recorded.
- **Only on a calendar that has run:** it acts only where a session is current, closed or archived. A fresh build or a test database is
  left as it is, so its fallback current session stays its own.

## On the live-shaped copy

Students in study, before and after:

| | Before | After |
|---|---|---|
| /19/, four-year programmes | 2,375 past the limit | 2,349 SP2, 52 SP1, 9 in the final year |
| /19/, five-year programmes | 110 SP2, 639 SP1 | 607 SP1 |
| /19/, six-year programmes | | 83 in the final year |
| /19/, Direct Entry (three years of study) | 55 past the limit | 55 past the limit, as the University chose |
| 2017/2018 entrants | | 72 from past the limit to SP2 |
| 2018/2019 entrants | | 309 from past the limit to SP2, 79 from SP2 to SP1 |

## Undoing it

Student Cohorts → Policy → Academic sessions → **Undo merger** on 2019/2020 (`policy.unmerge_session`, with a reason). Positions are
recomputed again.

## Every level reader counts it the same way (V725)

On 11 November 2026 the University reported the receipt of BSU/AR/REL/19/52222 (entered 2019/2020) for the first semester of
2022/2023 printing **400 Level**; it is **300 Level**, and the University added that students admitted before the merge were affected
too. V661 made the cohort engine count the merged session once, but four other readers of a session's level kept their own
arithmetic, used whenever the session holds no registration or enrolment of the student (most old-portal students' past sessions):

| Reader | Used by | Counted |
|---|---|---|
| `people.receipt_level` | every receipt: the student's, the Student 360°'s, ICT Support's, the public verify page | calendar years since entry |
| `people.level_in` | results statements, the results verify page, payment reallocation | the calendar's rows (and nothing for an entry before the calendar's first session: the record's level, often a stale 100) |
| `finance.historical_rows_read` | the past-session fee account (V720): its fee lines and spillover year | the calendar's index |
| `reporting.level_in_session` | the payments view: the Payments screen, analytics, the query engine | calendar years since entry |

V725 gives them one count, `people.counted_sessions(entry, session)` — `policy.sessions_elapsed` from the effective (merged-into) entry
session to the effective session, a malformed session name such as `2022/2024` read as the session starting in its first year. A
/19/ student is 100 Level in 2020/2021 and 300 in 2022/2023; a 2018/2019 entrant is 400 in 2022/2023 (500 before). The historical engine
works the count out once a pair of entry session and session, and the payments view from the cancelled years read once a query
(`policy.cancelled_years`), never once a row. The session roll-over's promotion ceiling, the College's minimum years and the
programme's timeline count the same way.

- **Stored levels were not wrong.** On a copy of live (late October), none of 2,614 old-portal registrations and enrolments of
  pre-merge students is a level high; a receipt stores no level, so every receipt, printed or verified, reads right at once, and
  printed check codes stay valid.
- **Reach on that copy.** About 8,900 confirmed payments of about 4,000 students printed one level high (2023/2024 most: about
  8,100); results statements and reallocation periods change for about 15,000 student-sessions of /19/ entrants, and about 19,800 of
  earlier entrants who fell to the record's stale level.
- **A merger now marks the historical summaries stale** (`finance.historical_bound`'s `MERGES` stream); V725 marks the students whose
  count changed once. The migration says how many historical assessments or payment reallocations name a level other than the new
  count; they are listed for the Bursary, not changed.
- **The set readers never count once a row.** The payments view, the old-fees reconciliation and the overpaid list join the cancelled
  years once a query (`CROSS JOIN policy.cancelled_years()`) and the old-fees import reads them once a call, so the 7-argument
  `reporting.level_in_session` is inlined: 0.12 s over 54,575 students, against 8.5 s for the 5-argument form called once a row.
- **A chain of mergers** (one session merged into another that is later merged in turn) is followed to its end by every reader, and a
  session name not written as the calendar writes it (`2022/2024`, `2022/23`) is read as the session starting in its year by all.
- **Unchanged, on purpose:** deferred sessions are not taken off these counts (the cohort engine's position does that), and a cohort
  override is not applied to past sessions.

## The admissions after it begin a session late (V738)

The University, 12 November 2026: a student admitted 2021/2022 was billed 100 Level fees for 2021/2022 (₦178,294.74) and one level
high after it. "Remember a session was merged … this outstanding should not affect student for that merged session."

- **What the record shows.** On the late-October copy of live (counts only), none of the 10,716 students admitted 2019/2020,
  2020/2021 or 2021/2022 holds a registration or an enrolment in their admission session. 2021/2022 admits registered 100 Level in
  2022/2023 and 300 Level in 2024/2025, the same as 2022/2023 admits. 2020/2021 admits registered 200 Level in 2022/2023 and 400 Level
  in 2024/2025, and 2019/2020 admits 300 Level in 2022/2023. Each of the three admissions began its first year the session after it
  was admitted in, and the calendar caught up at 2022/2023, which took two admissions at once. V661's merger was right for 2019/2020
  admits but counted 2020/2021 and 2021/2022 admits from their admission session.
- **The rule (the University's choice).** For admissions of 2019/2020, 2020/2021 and 2021/2022 the first year of study is the session
  after the admission session: nothing is assessed before it, and levels are counted from it. It is recorded as data,
  `policy.cohort_start` (admission session → first session, with its reason, audited), on a calendar that has run those sessions.
  A fresh or CI calendar of planned sessions is left alone, as V661 was.
- **Who reads it.** It is read through `people.first_session(admission, entry mode)` and
  `people.counted_from_entry(admission, entry mode, session)`. The readers are the outstanding-fees engine
  (`finance.historical_rows_read`: its first assessed session and its levels), `people.level_in`, `people.receipt_level`, the
  5-argument `reporting.level_in_session`, the payments view, the old-fees reconciliation, the overpaid list and the old-fees import.
  The set readers shift the admission session inline from `policy.cohort_starts()`, read once a query, so the 7-argument form stays
  inlined.
- **Exceptions.** A registration's or enrolment's own level stands. A postgraduate's and a CCE student's calendar is their own.
- **Stale accounts.** A change to the rule (insert, update, delete) marks the outstanding-fees account of every student admitted in
  that session stale.
- **Unchanged, on purpose.** These follow registrations, not the count, and are another decision: the cohort engine's effective
  cohort and spillover, the session roll-over's promotion ceiling, `people.align_level_reached`, the College's minimum years and a
  cohort override. `people.counted_sessions` is unchanged, because some of its callers pass a registration's session or an override's
  cohort, never an admission.

## The review of V738 (V740)

- **Money on the admission session.** A school-fee payment, an approved assessment or a waiver recorded on the session a student was admitted in (now before their first year) is kept on the outstanding-fees account. The session stands as a period with nothing assessed, so the money stands as a credit. An approved assessment, an officer's own act, still stands. The migration counts them and closes the open references drawn for those sessions.
- **The level before the first year.** A session admitted in and before the first year reads the entry level everywhere: the level in a session, receipts, the payments view and the set readers. A school-fee payment is not moved into it (`REALLOC_BEFORE_FIRST_YEAR`).
- **Names not written as the calendar writes them.** `2021/22` is read as 2021/2022 by every reader and by the trigger that marks accounts stale. Accounts whose admission session is written otherwise are marked to be read again.
- **The cohort engine** counts from the first year: its effective cohort is the first session, with cohort source `COHORT_START`, and the affected students' positions are recomputed. A 2021/2022 admit is in their final year in 2025/2026, not Spillover Year 1, and the current session is not billed spillover lines for them.
- **The programme timeline** (the deferment page and letter) counts completion from the first year.
- **The outstanding-fees card** decides "sessions before X are not yet assessed" from the first year.

## The review of V740 (V741)

- **The payments view and the set readers inline the level again.** V740's entry-level floor and name normalisation made each row call the level reader (about twenty times slower on Payments and Financial Analytics). The floor now sits inside the count, and an admission session is matched by its year, as `policy.session_normal` reads any name starting with a year.
- **A postgraduate's own level** is no longer floored at the entry level on the payments view, overpaid, reconciliation and the legacy import; receipts and these read alike.
- **Assessments and reallocations at the old count.** Historical assessments made before V738 at a level the first-year count now reads otherwise, and those being made on a session before the first year, are counted in the migration's notice for the Bursary (`V741: … historical assessments at a level the first-year count now reads otherwise, … being made on a session before the first year`). The Bursary corrects the first by a new assessment and rejects the second. V742 counts the payment reallocations recorded at such a level the same way, as V725 did for its own count (`V742: … payment reallocations of first-year-count students name a level other than the session's count now`); they are listed, not changed, and the payment-corrections desk still shows the level stored at the decision.
- **No assessment before the first year.** `finance.historical_assessment_save` and `finance.historical_assessment_decide` refuse a session before the first year (`HFA_BEFORE_FIRST_YEAR`), and the student's account no longer offers "Assess a different fee" on it.
- **Cohort source.** A 2019/2020 admission reads MERGED again (the merge outranks the rule beside it); the cohort, lifecycle and student screens name `COHORT_START` ("first year the session after admission"), and the lifecycle recommendation and graduation readers treat it as the entry.
