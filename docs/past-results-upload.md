# Past results upload: the mark as the old portal states it, never posted twice (V614, Oct 2026)

**Where:** Student migration → **3 · Past results** (`POST /api/v1/results/legacy/results`, with its check
`/legacy/results/preview`; `assessment.legacy_semester_load`, V472). Results held for students not yet on the register (V204) post
through the same load, so the same rules apply to them.

**Who (21 October 2026):** the Directorate of ICT alone (and the super administrator). Past results go onto the record as final with
no approval chain, because they were approved on the old portal, so the University keeps the upload to one office.
`/legacy/results`, its check `/legacy/results/preview` and `/legacy/pg-results` answer 403 to any other office, and the migration
screen shows them neither tab. The other migration steps (students, registration, JAMB numbers, photos, clearance) stay with the
offices that had them. So does posting results already uploaded and held for a student not yet loaded (`/legacy/reconcile-results`,
run after every student upload): it brings in no new result.

Since V627 the database holds the same rule. `assessment.legacy_semester_load` and `admissions.import_legacy_pg_semester`, asked to
load results or preview them, refuse an acting office other than ict or super with `PAST_RESULTS_OFFICE` (403). A load with no
acting office (the database's own maintenance, the demo data) is not an office's act and passes. The two reconcile functions mark
their own transaction (`moaum.legacy_reconcile`) while they post held results, so posting stays open to every migrating office. The
fixtures in check.sql and demo.sql load results as ict.

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

### Absent: the old portal's ABS (V619)

The old portal marks a candidate who did not sit **ABS** (or AB, ABSENT, ABS (F)), in the Outcome, Remark or Grade column or in place
of the mark itself. Until V619 the upload knew only the word ABSENT: any other outcome was read as graded and a mark cell's letters were
stripped, so the row had "No mark", was not posted, and the broadsheet showed the candidate **NR** (no result) where the old portal says
ABS (21 October 2026, Environmental Management and Toxicology, 100 Level). Now such a row posts the candidate **ABSENT** — F, counted
and owed, as a recorded absence always is (V422) — with "ABS … read as absent (F)" in its detail and the count `absent_from_abs`
("ABS read as absent (F)" on the screen). A mark cell reads as the absence only when no mark cell of the row carries a number: an AB
in the CA column beside an exam score is no absence from the examination. Uploading the same file again posts the absences it once
left out; nothing else is posted twice.

The score sheet upload (a course's Score Entry, and Held scripts) reads ABS the same way (`lib/score-outcome`): an Outcome cell of
ABS, or ABS in place of the CA and exam, is ABSENT; it no longer refuses the file ("outcome ABS is not one the register knows").

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

check.sql V619 covers Exam "ABS", Outcome "ABS", Total "AB" and Outcome "Abs (F)" posted ABSENT/F and counted, an AB beside an exam
score graded, an empty row still "No mark", and the same upload again posting nothing new; `lib/score-outcome.test.ts` the score
sheet upload's reading.
