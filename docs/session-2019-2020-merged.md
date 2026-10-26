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
