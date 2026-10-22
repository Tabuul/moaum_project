# The JAMB list upload merges with the list already held (V629, 22 October 2026)

**Where:** Admissions → Upload Applicants and Candidates (`/admissions/caps`, `POST /api/v1/admissions/caps-batches` and
`…/caps-batches/{id}/rows`), and Admissions → Upload Passport, DOB & O'Level (`POST /api/v1/admissions/sessions/{session}/candidate-data`).

The University asked that the upload always skip candidates already uploaded, update one who changed on the JAMB portal (a new
course, for instance), and add the new ones on the list. The CAPS download is cumulative: each week's file repeats every candidate
already loaded. Loading it failed with *duplicate key value violates unique constraint "uq_caps_row_per_session"*, because the
database holds one live row per candidate per session.

## The JAMB list (UTME and Direct Entry)

Each candidate in a chunk is read against the session's live list first (`CapsIntakeService.insertRows`):

| On the live list? | What happens | Counted as |
|---|---|---|
| Yes, the same: course, aggregate, names, sex, state, LGA, subject scores | skipped | `rowsUnchanged` |
| Yes, changed by JAMB | updated in place, on the list it is on; its commitment is kept | `rowsUpdated` |
| Yes, but on the other list (UTME vs Direct Entry) | left as it is, named in `otherList` | — |
| No | added to the new list under the load cut-off, as before | `rowsLoaded` |
| Twice in the same file | the first stands | `rowsUnchanged` |

- **What a change records.** Each update writes `admissions.caps_row_change`: each field as it was and as it became
  (`{"course": {"from": "C00061", "to": "C35147"}}`), the upload that carried it, who and when.
- **Eligibility.** Updating the row's raw data or aggregate marks the candidate's eligibility run stale
  (`trg_eligibility_touched`), so screening re-reads it.
- **The candidate follows JAMB (V636).** A candidate already on the portal whose course JAMB changed follows it, unless a
  released offer stands: the candidate's programme becomes JAMB's, a programme change (reason *Course changed by JAMB on the CAPS
  list*) is written on the register approved as made, the applicant is told, and the eligibility engine reads the candidate again.
  The loader does this after every upload that changed a course (`admissions.follow_caps_course`), and the reconciliation panel
  offers **Apply JAMB's course changes** for candidates changed before V636. A candidate with a released offer is left as offered
  and counted apart ("Matched, programme differs from CAPS — admitted"): the admission is corrected on Programme Changes, or the
  row withdrawn. Only that finding still blocks the commit.
- **Batch counts.** Each batch keeps `rows_updated` and `rows_unchanged`; `rows_added` is the rows it put on the list. The upload
  history shows "N new · N updated · N unchanged".
- **The badge.** "N candidates loaded" now adds up the candidates on the list, not each file's rows.
- **After a load**, the screen names the updated candidates (at most 300 a request) with what changed.
- **The database rule stands.** It still refuses a second live row for one candidate (check.sql §29). The merge never makes one;
  it updates the row that is there.

## Passport, date of birth and O'Level

A file already held under the same name is compared with what is held:

| Kind | Compared on | The same | Changed |
|---|---|---|---|
| Date of birth | the date and the names read | skipped | recorded beside the first; the newest is read everywhere |
| Passport | size and dimensions, and the image itself where both carry it | skipped | recorded beside the first; the newest is shown |
| O'Level | the result (V298) | skipped | recorded beside it; each sitting is checked against the record — **an awaiting result (A/R) on record is replaced outright by the grades uploaded under the same exam number (V636)**; an uploaded A/R never replaces grades; a second set of real grades for the same examination is **held** for the Academic Office to keep or use (the O'Level duplicates review) |

Real grades are not replaced without the Office's decision; an awaiting result is (V636). The upload's answer counts `replaced`
(and the O'Level answer `REPLACED` and `AWAITING`), and the screen says how many changed since they were first recorded.

## Tests

- `check.sql` V629: the change table, an empty change refused, the batch counts, one live row a candidate.
- `CapsMergeIT`: a Direct Entry list, then the next download (one the same, one moved course, one new), then the same download
  again; a date of birth sent the same, then changed.
