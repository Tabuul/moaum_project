# Past results upload: the mark as the old portal states it, never posted twice (V614, Oct 2026)

**Where:** Student migration → **3 · Past results** (`POST /api/v1/results/legacy/results`, with its check
`/legacy/results/preview`; `assessment.legacy_semester_load`, V472). Results held for students not yet on the register (V204) post
through the same load, so the same rules apply to them.

## The mark

The upload used to refuse any mark whose CA was over 40 or exam over 60 ("No mark, or a mark out of range"). The old portal's export
often carries the whole mark in its exam column, with the CA already added in.

The mark is now taken as the old portal states it, and the 40/60 split never refuses it:

| The row | Read as |
|---|---|
| CA 0–40 and Exam 0–60 (and a Total, if any, that equals their sum) | CA and exam, as the record splits them — as before |
| A Total column (0–100) | the whole mark |
| An Exam over 60, with or without a CA beside it | the whole mark out of 100 — the CA already in it ("65 of 100") |
| An Exam with no CA beside it | the whole mark out of 100 |
| A CA over 40 with an Exam | CA and exam added, the whole mark out of 100 |
| A CA alone | the whole mark (as before) |
| A mark over 100 | refused: "The mark is over 100" |

A row read as the whole mark is posted with the status **Result posted — the whole mark, of 100**, and the reading is in its detail
("the exam column read as the whole mark: 65 of 100 (the CA of 25 already in it)"). The check before the upload lists these rows,
so the office sees how each was read before anything goes up.

## Never posted twice

Before posting, the student's result on record for that class is read:

- **The same result** (the same outcome and mark) is not posted again: **Same result already on record — not posted again**.
  Uploading a file a second time posts nothing.
- **A different result an earlier upload posted** is replaced by a new version, and the row says so: **Result posted over an earlier
  upload's** ("replaces 70 of 100 an earlier upload posted").
- **A result entered on the portal** is never loaded over: **A result entered on the portal is on record — kept**. It is amended
  through Result amendments.

Rows repeated within the same file are still set aside (**Repeated in the file**).

## On screen

- **The check before the upload** gains a figure, **Uploaded before**: the same results, those replaced, and the portal results kept.
- **Results to post** says how many are read as the whole mark.
- **After the upload**, the summary counts them too: `marks_as_total`, `results_same`, `results_replaced` and `results_on_portal`.

## Tests

check.sql V614 covers:
- every reading, and over 100 refused;
- the same upload again posting nothing;
- a changed mark replacing the earlier upload's;
- a portal result kept.

It was also checked in the browser on a copy of live data: a first upload, then the same file checked again.
