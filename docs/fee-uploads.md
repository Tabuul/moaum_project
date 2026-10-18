# Fee uploads: what they replace, and what they would change (V535)

Two uploads state a session's school fees, both on **Fee Setup and Schedule** (`/finance/fees`), both the Bursar's and the
Students Account Officer's:

| Upload | Where | What it does |
|---|---|---|
| The approved fees structure | "Upload the approved fees structure" | Replaces lines: only those of the faculties and programmes the file names, or the whole session's full-time (or CCE) structure on purpose |
| The fees to state | "Students with no school fee stated" → Upload the filled sheet | Adds lines beside the structure; never ends one |

## Nothing changes before it is seen

Either upload is first applied and undone on the server (`finance.fee_upload_effect`, `POST …/fee-structure/preview`,
`POST …/fee-lines/preview`) and the window shows:

- for each faculty, and each programme with lines of its own: the lines **new**, **changed** (amount), **the same** and **ended**;
- any faculty or programme that would be **left with no fee** for the session;
- every amount that changes, from what is in force to what the file states;
- the live undergraduates with **no fee stated**, now and after the upload, with the groups still left.

Only then does **Replace only what the file names** / **Replace the whole structure** / **Add the lines** apply it.

## Only what the file names (the default)

A file is read as stating the fees of the faculties and programmes in it. The upload ends, of its kind (full-time or CCE):

- for a row naming a **programme**: that programme's lines;
- for a row naming a **faculty**: that faculty's own lines (not its programmes' lines of their own);
- for a row naming neither: the University-wide lines.

Every other line of the session stands. So the College of Health Sciences' sheet replaces the College's programme lines and
leaves the eleven other faculties as they are.

## The whole session, on purpose

Chosen on the window, the structure replaces every line of its kind for the session, as every upload did before V535. When the
file states no fee for a faculty that has lines in force, the window names it ("left with no fee") and the upload is refused
(`FEE_STRUCTURE_PARTIAL`) until the Bursar ticks that those faculties' lines end. An upload that does not say what it replaces
(the API without `scope`) is read as the whole session, unconfirmed — refused the same way.

## A name the portal does not hold

A faculty or programme the file names that is not on the register refuses the whole upload (`FEE_STRUCTURE_UNKNOWN`, naming it):
nothing is changed. Before V535 such a row became a line with no faculty, charged to every student of the University.

## The layouts read

All sheets of the workbook are read (`lib/fee-matrix.ts`, tested):

- **One row per fee** — Faculty (or Faculty code, or Programme code), Level, Entry mode, Semester, Indigene, Amount; Item, Spillover,
  Kind, Fee group, Order optional. The "fees to state" sheet reads this way too.
- **The faculty cross-tab** — a FACULTY/SEMESTER header with a column pair per level band, a block per faculty with 1st and 2nd
  Semester rows.
- **The College's blocks** — a block per programme whose title row carries its level bands ("MBBS | 100L/200DE | 200L | … | 600L/SP"),
  the Indigenes / Non-Indigene row, then 1ST, 2ND and TOTAL rows. Each block's title is matched to a programme or faculty on the
  register ("BIOCHEM" → B.Sc. Biochemistry of the faculty most other blocks fall in; "MEDICAL LAB SC. TECH" → Bachelor of Medical
  Laboratory Science) and the Bursar confirms or changes each match, or leaves a block out. The itemised breakdown sheets beside
  them are not read.

Entry modes are stated on every line so a student is reached once: **100L/200DE** is 100 Level for UTME and Transfer and 200 Level
for Direct Entry; **200L** is UTME and Transfer where the block has a Direct Entry band (all three where it has none); **300L and up**
is all three; **/SP** also gives the spillover line (no level, no entry mode). A CCE structure is entry mode CCE throughout.

Where a TOTAL row is given the two semesters are made to add up to it to the kobo — the first semester to the kobo, the second the
TOTAL less the first. Where the sheet's 1ST and 2ND do not make its TOTAL (by more than ₦1) the TOTAL stands, shared between the
semesters as the sheet shares them, and the window names each such cell.

## The College of Health Sciences' 2025/2026 fees (V543)

The College's approved workbook ("FEES STRUCTURE FOR 2025/2026", Office of the Finance Controller) was loaded by migration as the
upload reads it — 364 lines for MBBS, Nursing, Human Anatomy, Human Physiology, Radiography, Biochemistry and Medical Laboratory
Science — only on a database with live students of the College and only where nothing of the College's was stated for 2025/2026;
otherwise the migration wrote nothing and said why. Radiography 500 Level has no amount on the workbook and has no line until the
Bursary states it (81 students on the live-shaped copy).
