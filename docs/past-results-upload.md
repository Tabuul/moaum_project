# Past results upload: the mark as the old portal states it, never posted twice (V614, Oct 2026)

**Where:** Student migration → **3 · Past results** (`POST /api/v1/results/legacy/results`, with its check
`/legacy/results/preview`; `assessment.legacy_semester_load`, V472). Results held for students not yet on the register (V204) post
through the same load, so the same rules apply to them. Since V771 (15 November 2026) this upload and **2 · Course registration**
record the course as the student took it, under a confirmed upload with its own record: see
[The course as taken](#the-course-as-taken-v771-15-november-2026).

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

## The course as taken (V771, 15 November 2026)

The user's master prompt of 15 November 2026 asked that a past result keep the course as it was taken: its code, title and credit
units, never today's catalogue. The University decided the rules the same day:

| Decision | What it says |
|---|---|
| D1 | Credit units are read only from a column that names them: **Credit Units**, Credit Unit or CU. The old portal's own **Units** column is a status code (1 GST, 2 core, 3 elective, 0 carry-over), so an undergraduate file whose only units column is a bare Units is stopped, with the reason, before any row is read. The postgraduate tabs keep reading their Units column. |
| D2 | Both undergraduate tabs, **2 · Course registration** and **3 · Past results**, carry **Course Title** and **Credit Units** on every row. A row without them, or with one that cannot be read, is refused and listed (`AS_TAKEN_MISSING`, `AS_TAKEN_INVALID`). Nothing is taken from today's catalogue in its place. |
| D3 | A Senate-approved graduate whose units a corrected file changes keeps the CGPA and class of degree the Senate approved. The upload lists them for the Registry. |
| D5 | Every row carries its **Category**: Core, Elective, GST or Carry-over (the old portal's 2, 3, 1, 0 are read too). It is recorded on the student's registration, so a failed elective is never owed as a carry-over. |

D4 belongs to the removal of a wrongly counted course: see [course-registration-correction.md](course-registration-correction.md).

### What was wrong

The loader never read the file's units or title:

- a new registration took the units the student's **current** programme takes the course at today (`catalogue.units_for`);
- a class the upload opened took today's title and units;
- a course already on record was never corrected (`UNITS_DIFFER` only compared it with today's catalogue);
- a renamed code reached every past class.

Every GPA, CGPA, broadsheet and transcript reads the units kept on the registration, so today's catalogue became history.

### The template

| Tab | Columns |
|---|---|
| 2 · Course registration | Matriculation Number, Course Code, Course Title, Credit Units, Category, Level, Session, Semester |
| 3 · Past results | Matriculation Number, Course Code, Course Title, Credit Units, Category, Level, Session, Semester, CA, Exam, Total, Outcome |

The screen reads the header before any row (`lib/legacy-columns`):

- a units column with no credit-units column beside it stops the file: "The file's Units column is not credit units." The detail
  explains the status code and asks for a Credit Units column with the units each course carried when the student took it;
- a file without a Course Code, Course Title, Credit Units or Category column stops: "The file has no … column(s)."

Credit units are a whole number from 0 to 12. The title is at most 200 characters, kept as written (trimmed, single spaces). The
screen sends `title`, `creditUnits` and `category` for each row, never `units`, and keeps each row's place in the spreadsheet so a
row set aside can be found. Before anything is sent it sets aside, with the reason, a row with no matriculation number, a Session
or Semester cell blank or unreadable, and a student's course stated twice: the first copy goes up when the copies agree, none when
they differ.

### The course as taken

`catalogue.course_as_taken` keeps a class (course, session, semester, stream) as its students took it:

- the code as the file wrote it: upper case, single spaces, ABC123 as ABC 123, an old portal's session-copy year ("CSC 301 (2019)")
  dropped. It stays when the course is later renamed;
- the title as written (a corrected spelling is a different title);
- the credit units;
- the programme it was first taken under, as information, not identity.

There is one row for each distinct class, code, title and units. A row is never updated and never deleted except with its class
(`AS_TAKEN_KEPT`); a different code, title or units is another version beside it. The student's registration entry points at its
version (`registration.entry.as_taken_id`), and the entry's units are always the version's.

- **The catalogue is never touched.** Changing a course's units in the catalogue (`catalogue.reflect_units` and its impact
  readers) leaves a course as taken alone, as it leaves closed, archived and cancelled sessions.
- **The Senate route wins, and history keeps both.** A Senate units amendment applied later moves the entry to the version with
  the Senate's units — found, else made (source AMENDMENT, with the amendment's reference); a version found keeps its own source,
  since a version is shared by every student of the class who took the same code, title and units. So whether the Senate set a
  student's units is read from the amendment and the programmes the student has held, never from the version
  (`assessment.entry_units_by_senate`). A move of the entry to its cohort's class moves it to a version on that class (MOVED); any
  other change of the entry's units makes a version too (CHANGED).
- **A class all of whose students took one version** reads as that version on its sheets: its heading title and units are set to
  it (`CLASS_HEADER_CORRECTED` in the upload's ledger).
- **Every reader prints the course as taken:** the student's results, statement and broadsheet, the transcript (the code as
  taken), the course form and its verification, Registration History, the full record, the ICT result viewer and a result's
  details, and the results broadsheet. A broadsheet column is headed by the units most of its students took it at; where students
  differ the units carry an asterisk, and a mark shows the student's own units.
- **Issued transcripts and statements** are flagged for review when the printed code or title of a course changes, as when its
  units do.

### How a course is identified

By its code **and** its title (`catalogue.course_for_as_taken`). The candidates are:

- the course the code resolves to;
- every course sharing its shown code (V646's separate courses under one code, such as CSC 401 and CSC 401 V2);
- every course that held the code before a rename (`catalogue.course_change`).

One candidate is the course. Several are told apart by the title: the course's current title, a title it had, or a title its
classes or versions carry. A code alone never decides between courses.

| Match (on the check) | Meaning |
|---|---|
| Code and title | the code names the course and the file's title is its current title |
| A title it had | the title is one the course had, or one its classes or versions carry |
| A code it had | the code is one the course held before a rename |
| Code only — new title | one course under the code, and the file's title differs from every title it has had: the check lists it, and the office ticks it before the file goes up |
| More than one course | several courses under the code and the title names none, or more than one: `COURSE_AMBIGUOUS`, not loaded. Write the course's own code (its BMAS or V2 code) in the file |

A code no course holds, now or before a rename, is `NO_COURSE`.

### What a re-upload corrects, and what it never overwrites

A course not on the student's registration is added with the file's code, title, units and category. A course on record is read
against the file: the code and title it prints, its units, its category.

- **The same:** `ALREADY_ON_RECORD`; nothing changes.
- **Different, and the uploading office is the Directorate of ICT's** (ict, super, or a Database Operator granted over the
  University: `assessment.past_results_may`): corrected to the file's. Units are `UNITS_CORRECTED`, code or title
  `AS_TAKEN_CORRECTED`, category `CATEGORY_CORRECTED`. The same in every way but not yet recorded as taken is `AS_TAKEN_LINKED`.
- **Different, and another migrating office uploads:** `AS_TAKEN_DIFFERS`, left as it is. The Directorate of ICT uploads the
  correction; another office's file only adds what is missing.

Never overwritten:

| Status | When |
|---|---|
| `UNITS_ON_PORTAL` | a result entered on the portal stands on the course: the file's course is not put over it. Amend it through Result amendments |
| `UNITS_BY_AMENDMENT` | an applied Senate units amendment set these units: the file's are not put over them. The Senate's units are the student's own fact: an applied amendment of the class at the entry's units for the programme the student is in or has held, so a programme change, transfer or merge does not lose it, and a student who was never in the amended programme is not held to it whatever version the entry points at (`assessment.entry_units_by_senate`) |
| `REMOVED_ON_RECORD` | the course was taken off the registration (a V702 duplicate resolution, or the Director of ICT's removal, V772): not brought back |
| `REMOVAL_PENDING` | a removal of the course awaits the Registry: nothing changes. Upload the row again after the decision |
| `COURSE_ON_RECORD_ELSEWHERE` | the registration holds the course under another course of the code (an earlier upload read the code alone): nothing is added. Take the other off through Course Registration Correction if it is wrong |
| `DUPLICATE_CONFLICT` | the same student and course appear more than once in the file with a different title, units, category or mark: none is loaded |

A dropped course stays dropped on a registration file (`DROPPED_ON_RECORD`). On a results file a result is still evidence the
course was taken: the entry is approved again, as the file states it where the office corrects the record — but never over a
result entered on the portal or over the Senate's units: there it is approved again as it stands on record, and the row says so
(`UNITS_ON_PORTAL`, `UNITS_BY_AMENDMENT`): units, code and title, and category alike (a file that differs only in the category
is told so too). A result goes on the class's main sitting, never a re-sit or special sheet.

A GST course reads GST whatever category the file gives it (the course's kind decides, as on every screen): filed as Core or
Elective it is left as it is, no category correction is recorded, and the row's detail says "the file's core is not taken — a
GST course counts as GST".

### The check

As before (V472), nothing goes up until the office has seen what the file does against the record. The loader runs each batch and
undoes it. A batch is cut between students, so a student's courses of a semester are checked, and later loaded, together. The
batches' answers are put together (`lib/legacy-merge`): counts added, courses and students united, and each student's CGPA moved by
every batch's difference.

Before this file goes up, the check shows:

- **Tiles:**
  - Rows read, and the rows set aside before the check;
  - New results (results) or Courses to add (registration);
  - Existing updated (results: earlier uploads' results replaced, dropped courses approved again by their result, the same result
    not posted again, portal results kept) or Already on record (registration);
  - Units corrected; Titles or codes corrected (and how many more are recorded as taken, nothing else changing); Categories
    corrected;
  - Courses as taken, to be recorded new / already on record;
  - Units differ from the catalogue (and the courses with a title new to the code);
  - Students whose CGPA changes; Senate-approved graduates;
  - Invalid, missing or ambiguous; Repeated in the file; Will not load;
  - Registration discrepancies: taken off and not brought back, held for the Registry, on record under another code, added to an
    open registration;
  - Left as on record: a portal result stands, the Senate's units, on record differently, dropped;
  - Held (results).
- **Notes:** the courses that go onto a registration the student made on the portal; the courses named by a code whose title is
  new to it; the Senate-approved graduates in the file; and "What the file corrects, and what it leaves".
- **Rows to look at:** every row except a plain addition, a posted result or a course already on record (and every code-only
  match). Each shows its row in the file, the matriculation number, the code, title, units and category uploaded, the session and
  semester, the status, the detail and what to do.
- **The courses as the file has them:**
  - the code as taken (and the course it matched);
  - the title in the file and the current title;
  - the units in the file, the current units, and the units applied (with how many rows are kept as on record);
  - the session, semester, students, version (New / On record) and match.
- **Students whose GPA or CGPA changes:** the CGPA before → after, the units counted before → after, and each semester whose GPA
  moves. A Senate-approved graduate is marked "the approved CGPA stays".
- **Download every row's status:** an Excel of every row with the code, title, credit units and category in the file, the matched
  course, the current title and units, the version, the match, the session, semester, status, detail and what to do.

### The confirmation

**Upload it** opens the confirmation (*Upload the past results* / *Upload the course registration*):

- the file name and its rows, "one upload on the record";
- where the file names a course by a code whose title is new to it: the courses listed (Code, Title in the file, Current title,
  Rows) and the tick **I have checked these titles**, required before the upload;
- **Why this file is loaded**: ten characters or more, on the upload's record with the officer's name.

**Upload it** then opens the upload (`POST /api/v1/results/legacy/uploads`), loads every batch under it (`uploadId`) and closes it
COMPLETE after the last batch. A batch that cannot be sent stops the run. **Resume from the failed batch** carries on under the same
upload, and **Stop here and close the upload** closes it INCOMPLETE. Choosing another file closes the one left behind INCOMPLETE.
After the upload, the note "Recorded as upload PRU-…" carries **Open the upload's report**.

### The upload record, its ledger and its report

`assessment.past_upload` is one confirmed upload, `PRU-YYYY-NNNNN`: its kind (RESULTS or REGISTRATION), the file name, the rows,
the reason, the officer and office, and its state:

| State | Meaning |
|---|---|
| RUNNING | opened; its batches are going up, or it stopped part way and was not closed |
| COMPLETE | every batch loaded; its counts are taken from its ledger |
| INCOMPLETE | stopped part way; what loaded stands and is in its ledger |
| REVERTED | rolled back from its ledger (below); who, when, why and what was undone are kept on it |

Only the officer who opened an upload loads under it or closes it. Refusals:

| Code | When |
|---|---|
| `LEGACY_UPLOAD_REQUIRED` | an import that names no upload (400; nothing is read) |
| `LEGACY_UPLOAD_OWN` | another officer's upload (403) |
| `LEGACY_UPLOAD_STATE` | the upload is closed, of the other kind, or not there |
| `LEGACY_UPLOAD_REASON` | a reason under ten characters |
| `PAST_RESULTS_OFFICE` | a results upload opened by an office other than the Directorate of ICT's |
| `LEGACY_REVERT_OFFICE` | a rollback by an office other than the Directorate of ICT, super, or a Database Operator granted over the University (403) |

- **The ledger, the backup** (`assessment.past_upload_change`). One row for each change the upload made, with what was there
  before and what the file put:
  - ENTRY_ADDED;
  - UNITS_CORRECTED, AS_TAKEN_CORRECTED, AS_TAKEN_LINKED, CATEGORY_CORRECTED;
  - ENTRY_REAPPROVED;
  - RESULT_POSTED and RESULT_REPLACED, with the score versions before and after;
  - CLASS_HEADER_CORRECTED;
  - REGISTRATION_ADDED: an approved course registration the upload made for a semester where the student had none, with its level;
  - ENROLMENT_ADDED: the session's enrolment the upload made for a student not enrolled in the session, with its level.

  The rows keep values, not keys, so they outlive renames and merges. A rollback marks each row it undid (`reverted_at`) and each
  it left as it was with why (`revert_note`); a RESULT_REPLACED it undid also names the mark it wrote to put the earlier marks
  back (`undo_score_version`).
- **The file's rows** (`assessment.past_upload_row`). Every row of the file sent under the upload and what became of it: its
  status and detail, and what the loader read of it (`facts`: the code, title, units and category in the file, the course it
  matched, the course's current title and units, the version, how it matched, the action to take, and `entryStatus`, what became
  of the course on the registration). A batch sent again never rewrites a row the upload loaded or changed; a held row posted
  later, or a refused row sent again, is updated. When the upload is closed its counts also hold `rows` and `byStatus`.
- **The reconciliation** (`assessment.past_upload_student`). Each student the upload changed, with their CGPA and units counted
  before its first change and after its last, the number of changes, and whether they are a Senate-approved graduate.
- **The report:** **Old Portal Uploads** (`/records/migration/uploads`; one upload at `?id=`). The list shows every confirmed
  upload, newest first, with its reference, what it was, the file, rows, state, changes, students, graduates, the reason, who loaded
  it and when. One upload's report has:
  - the upload itself;
  - tiles for changes, students (and how many whose CGPA moved), Senate-approved graduates, and each kind of change;
  - the **Senate-approved graduates** for the Registry: CGPA before, and the CGPA from the record now;
  - the **Students**, graduates first: CGPA and units counted before → after;
  - the **Changes**, in order, each with what it was and what it is now (a registration or session enrolment made, with its
    level), and once the upload is rolled back whether each was rolled back or left as it was, and why. The category on each
    side is the one the record read (`wasCategory`, `nowCategory`: the programme's basis first, a GST course always GST), so a
    correction that moved only the basis shows as elective → core; result rows carry it too. The course's kind is the one the
    ledger kept when the change was made (`course_kind`), so the report reads the same after a rename or a reclassification. A
    change undone by a later rollback says so under "Rolled back" (its note). **Excel** exports them
    branded (serial PRU), with the upload's reference, file, reason and officer;
  - the **Rows not loaded or left as they were**: tiles counting every row of the file by status, beside them tiles counting what
    became of the course on the registration where that is not the row's status (`byEntryStatus`), and the rows themselves by
    session, semester and line (the first 5,000), each with its status, the detail, the action to take and what the loader read
    of it. A row is listed when its status is not a plain load (ADDED, ALREADY_ON_RECORD, RESULT_POSTED,
    RESULT_ALREADY_ON_RECORD, ADDED_TO_OPEN_REGISTRATION), or when its course on the registration was not a plain load (its
    `entryStatus` is not ADDED, ADDED_TO_OPEN_REGISTRATION or ALREADY_ON_RECORD): a result posted on a course whose units were
    corrected, or kept as the portal or the Senate has them, is listed with both. **Excel** exports them.

  Read by the Directorate of ICT, the Database Operators, super, Exams & Records, the Academic Office, the Registrar and the
  Deputy Registrar. The officer who opened an upload left running closes it from its report (**Close as stopped part way**).

### Rolling an upload back

A confirmed upload (COMPLETE or INCOMPLETE) is rolled back from its report with **Roll back this upload**, by the Directorate of
ICT, super, or a Database Operator granted over the University (`assessment.revert_past_upload`). The confirmation says in plain
words what a rollback takes back and what it does not, and asks why (ten characters or more, kept on the upload with the
officer's name). A RUNNING upload is closed first; an upload is rolled back once.

**The rule.** The ledger is walked newest change first (class headings after the courses), and each change is undone only where
it is still the last word on what it changed (`assessment.revert_change`):

1. **no later change in the ledger stands on the same thing.** A later upload's change to the same course, result or class
   heading that has not itself been undone is a change made since, whatever the values read. A correction that a later file
   corrected back is left while that file stands;
2. **the record still reads what the change left there.** A result amendment, a mark entered on the portal, a course dropped or
   changed on the registration moved it since;
3. **no one has acted on it since in a way that leaves no mark on it:**
   - the Senate's units: an amendment applied at the very units the upload had put moves nothing on the entry, so the rollback
     asks as the loader does (`assessment.entry_units_by_senate`) and never writes other units over them. A dropped course it
     had approved again is dropped again, keeping the Senate's units;
   - a Course Registration Correction asked for, decided or undone on the course since the upload put it there or corrected it
     (`registration.entry_corrected_since`): the course the Director of ICT put back is not taken off by a rollback, nor are its
     units, code, title or category put back;
   - a class chosen to stand over its duplicate on the Duplicate results page since the upload put it there (V775);
   - a registration reset, decided on, reviewed, moved to another level (`registration.registration_acted_on`: every table that
     refers to the registration).

Otherwise it is put back as it was:

- **a course the upload added** is deleted from the registration, as if it had never been added; a mark posted on it stays on
  its result sheet as history and no longer counts (the result monitor passes over it), and a corrected file adds the course
  afresh;
- **a dropped course it approved again** goes back as it was;
- **a correction** (units, code or title, category, the link to the course as taken) is put back; the several corrections one row
  made are one change, undone together (the same upload, course and snapshot with nothing else done to the course between them
  in the ledger: a batch sent again after another change is a later change);
- **a result that replaced an earlier upload's** gives the earlier marks back as a new score version;
- **a class heading** it set is put back, unless courses of the class that the same upload put as the heading reads were left
  and every counted student of the class still carries the course so: the heading then stays with them. Where any student reads
  otherwise — put back to no version of their own, or on a later upload's — the heading is put back (a student without a version
  reads the heading), and a course that was left keeps its own version;
- **a registration it made** (REGISTRATION_ADDED) is taken off when nothing is left on it and nothing has been done to it since;
- **a session enrolment it made** (ENROLMENT_ADDED) is taken off when the student has no registration left in the session and its
  level stands;
- **the cached academic position** of each student whose registration or enrolment was taken off is refreshed
  (`people.refresh_academic_positions`): no trigger fires when those rows are deleted;
- **an issued transcript or statement** of a student whose course was taken off is flagged for review, once a student.

**A first result goes with its course.** A first result on a course that was already on the registration cannot be taken off
without the course, so it is listed for Result amendments. But when the course was itself put there by an upload — the Course
registration file, then the Past results file — and that upload is rolled back too, the result goes with the course: its change
is marked "taken back with its course when PRU-… was rolled back", in whichever order the two are rolled back. A first result of
an upload that still stands keeps the course. (A later standing upload that only found the same result already on record wrote
no change of its own, and does not keep the course.) A first result that stays because its course had to be left is told why:
"PRU-… is rolled back and had to leave the course (…), so the result stays with it; amend it through Result amendments" — said
only of a course as that upload put it: a result whose own upload approved the course again in between keeps that re-approval's
reason.

**Anything a rollback leaves is listed with why**, on the upload's report and in the answer.

**Uploads rolled back in any order end the same.** A mark is no change made since when a rollback undid the change that wrote it,
or when a rollback wrote it to put the earlier marks back (`assessment.score_undone`). After its own ledger, a rollback settles
what it has freed: a change an earlier rollback had to leave is tried again only when a later change on the very same course,
result, registration or class was undone just now (or was this upload's first result on that course) — never because the record
happens to read the same again, so an unrelated rollback never touches what was rightly left. The rounds repeat until one undoes
nothing. Each change so undone is noted "undone when PRU-… was rolled back", that upload's `revert_counts` follow its ledger, and
the answer counts them as `earlierUndone`.

**Held results.** Results the upload was still holding for students not yet on the register never post under it once it is
rolled back. Each goes back to the nearest earlier upload still standing that held the same row before it (the same file loaded
twice by mistake: rolling the second back leaves the first's results held, to post when the student is uploaded) — never to this
upload's own earlier hold — or is dropped; `heldDropped` counts them. Every row of the upload still reading HELD is closed then
(HELD_ROLLED_BACK, "Held, closed with the rollback"), in words that say what happened: dropped; gone back to PRU-…, which held
it before; or not posted before the rollback, PRU-… having taken the row over. No rolled-back upload's row promises a posting. A
row a later upload holds now, or has since posted, is that upload's and stays as it is.

The rollback answers `{ref, state: REVERTED, undone, left, heldDropped, earlierUndone, leftChanges: [{kind, courseCode, session,
semester, matric, note}]}`, every figure read from the ledger; the upload keeps who rolled it back, when, why, and `revert_counts
{undone, left, heldDropped, earlierUndone}`. "Nothing this upload put there is left" is said only when nothing was left. The
upload stays on the record with its report; the file goes up again only as a new upload. A Senate-approved graduate's approved
CGPA and class of degree stay as approved.

**A rollback whose answer never comes.** A large rollback can outlast the connection that asked for it. The database completes
it whole or not at all, so the Uploads screen never calls that a failure: it says the outcome is not known yet and reads the
upload's report again in the background, at once and then every 12 seconds for up to 15 minutes, until the report shows the
upload rolled back (the screen then shows what was undone and what was left, from the report) or the time runs out (the officer
is told the rollback has not gone through, or that the outcome is still not known, and may ask again: an upload already rolled
back refuses with LEGACY_UPLOAD_STATE). Only the API's own refusal — a problem with a title, or a bare 401 or 403 — is shown as a
refusal.

The result monitor, the Duplicate results page and Course Registration Correction pass over a mark only when it is the history of
a rolled-back upload: the first result the upload posted on that sheet, taken back with its course, nothing marked since and the
course not put back on the registration since (`assessment.result_rolled_back`). A mark that was there before the upload is
judged as it was before it — a mark with no registration is an exception again once the course a file added for it is taken off
— and a rolled-back upload's mark counts again when a corrected file with the same mark puts the course back.

### Senate-approved graduates (D3)

A graduate the Senate approved (`records.graduand.senate_state = 'APPROVED'`) is still corrected as the file has them: their
courses are recorded as taken. The CGPA, the class of degree and the award the Senate approved do not move:

- the check and the report mark them, and list them apart for the Registry;
- the graduation audit keeps an approved graduand's CGPA, award and unmet list (`GraduationRepository.upsert`); a graduand not
  yet approved is audited afresh.

### Held rows

A results row whose student is not on the register yet is HELD, as before. It now remembers how it came
(`assessment.legacy_result_holding.as_taken`, `upload_id`), and — when a later upload carries the same row and takes the hold over
— the hold it replaced (`prior`). When the student is loaded each upload still standing that held the row posts it in turn, in
the order they held it (the oldest hold first), under its own upload (`assessment.reconcile_legacy_holding`): as taken, corrected
only when the upload's office was the Directorate of ICT's. The later upload then replaces the earlier one's result, or finds the
same result on record, in its own ledger, exactly as for a student already on the register — so rolling the later one back gives
the earlier result back. A row held before V771 posts under the old rule.

The same happens when the student was put on the register by a route that did not run the reconcile and a results file is then
loaded for them: the loader first posts the held results of its batch's students (`assessment.reconcile_held`, the reconcile for
one semester's rows of some students), each under the upload that held it, and only then reads the file's rows. The check does
it too, and undoes it. The answer says so: `held_posted_first` counts the held results posted first (the check shows a note, the
import's sentence a clause), and its CGPA list, `students_affected` and `graduates` are read against the record as it stood
before they posted — what confirming the file does to the record the officer sees — so a student or a Senate-approved graduate
changed only by the held posting is listed too. Each upload's own ledger keeps its own before and after. A closed upload's counts
on the Uploads list are taken again whenever a held result posts under it (`assessment.past_upload_counts`), and written only
where they moved.

The reconcile takes the held rows it is about to post before it reads them (one order: session, semester, number, course), so a
second reconcile of the same rows — another batch carrying the student, or the whole reconcile after a student upload — waits and
then finds them posted, never posting again what a file has since replaced. Where two of these doors meet in a circle on those
locks (a batch holds its own upload's row and wants the held rows; the reconcile holds them and wants that upload's row; a
rollback holds its upload's row and wants its holds), PostgreSQL ends one whole and the API runs it again in a fresh transaction
(`DeadlockRetry`): the results import, its check, reconcile-results and the rollback.

V775 also put the rows written between V771 and itself under these rules, once: a hold standing under an upload already rolled
back was handed back to the nearest earlier holder still standing or dropped; every row of a rolled-back upload still reading
HELD was closed; rows closed with "held before it is held again" were reworded to what happened then; each closed upload's
stored counts were taken again; and the ledger's code and title of each change were read from the version the change names.

### Every row's status

| Status | On the screen | Meaning |
|---|---|---|
| `ADDED` | Added | not on the registration: added, approved, with the file's code, title, units and category (a new approved registration for the semester where there was none) |
| `ADDED_TO_OPEN_REGISTRATION` | Added to a registration open on the portal | the student has an unapproved registration for the semester on the portal: the course is added to it, approved |
| `ALREADY_ON_RECORD` | Already on record | on record as the file has it: nothing changes |
| `UNITS_CORRECTED` | Units corrected to the file's | on record at other units: corrected (Directorate of ICT only) |
| `AS_TAKEN_CORRECTED` | Code or title corrected to the file's | on record under another code or title: corrected (Directorate of ICT only) |
| `CATEGORY_CORRECTED` | Category corrected to the file's | on record in another category: corrected (Directorate of ICT only) |
| `AS_TAKEN_LINKED` | Recorded as taken — nothing else changed | on record the same; now linked to its course as taken |
| `UNITS_ON_PORTAL` | A result entered on the portal stands — left as it is | a portal result stands on the course |
| `UNITS_BY_AMENDMENT` | Units the Senate set — left as they are | the units come from an applied Senate amendment |
| `AS_TAKEN_DIFFERS` | On record differently — left as it is | another office's file; the Directorate of ICT uploads the correction |
| `REMOVED_ON_RECORD` | Taken off the registration — not brought back | a duplicate resolution or the Director of ICT's removal stands |
| `REMOVAL_PENDING` | A removal awaits the Registry — left as it is | upload the row again after the decision |
| `COURSE_ON_RECORD_ELSEWHERE` | On record under another course of the code | nothing added |
| `DROPPED_ON_RECORD` | Dropped on record — left as it is | a registration file leaves a dropped course dropped |
| `UNITS_DIFFER` | On record at other units — left as it is | the old rule only (a row held before V771) |
| `AS_TAKEN_MISSING` | Course title, credit units or category missing | the detail names which |
| `AS_TAKEN_INVALID` | Course title, credit units or category not readable | units not a whole number from 0 to 12, a category not one of the four, or a title over 200 characters |
| `COURSE_AMBIGUOUS` | The code is held by more than one course | write the course's own code |
| `NO_COURSE` | No such course | no course holds the code, now or before a rename |
| `NO_STUDENT` | No such student | a registration file's number no student holds |
| `HELD` | Held — student not loaded yet | a results file's number no student holds yet |
| `HELD_ROLLED_BACK` | Held, closed with the rollback | a held row its upload's rollback closed: dropped, back with an earlier upload that held it before, or taken over by another upload already — the row's detail says which |
| `DUPLICATE_IN_FILE` | Repeated in the file | the same student and course earlier in the file, with the same values: the first goes up |
| `DUPLICATE_CONFLICT` | Repeated in the file with other values | none goes up |
| `REFUSED` | Refused | the portal's rules refused the row; the detail says why |
| `RESULT_POSTED` | Result posted | |
| `RESULT_AS_TOTAL` | Result posted — the whole mark, of 100 | V614's readings |
| `RESULT_REPLACED` | Result posted over an earlier upload's | |
| `RESULT_ALREADY_ON_RECORD` | Same result already on record — not posted again | |
| `RESULT_ON_PORTAL` | A result entered on the portal is on record — kept | |
| `NO_MARK` | No mark, or a mark over 100 | |

A results row whose course was corrected but whose result is already on record reports the correction, with the result in its
detail. A results row whose course was kept as on record (UNITS_BY_AMENDMENT, UNITS_ON_PORTAL, AS_TAKEN_DIFFERS) or corrected
reads RESULT_POSTED when its result posts; its `entryStatus` says what became of the course, and the screens show both. On the
check each status reads in the future ("Will be added", "Units will be corrected to the file's").

### API

| Endpoint | Who | What it does |
|---|---|---|
| POST `/api/v1/results/legacy/uploads` `{kind, fileName, rows, reason}` | REGISTRATION: the migration desk's offices (`MIGRATE`); RESULTS: ict, dbops, super (and the database, `PAST_RESULTS_OFFICE`) | opens the upload, RUNNING (`assessment.past_upload_begin`) |
| POST `/legacy/registration`, `/legacy/results` `{session, semester, rows, uploadId}` | `MIGRATE` / `PAST_RESULTS` | one batch under the upload; `LEGACY_UPLOAD_REQUIRED` without `uploadId` |
| POST `/legacy/registration/preview`, `/legacy/results/preview` | `MIGRATE` / `PAST_RESULTS` | the check: nothing written |
| POST `/legacy/uploads/{id}/finish` `{complete}` | the officer who opened it | COMPLETE or INCOMPLETE, its counts from its ledger (`assessment.past_upload_finish`) |
| GET `/legacy/uploads?limit=` | ict, dbops, super, records, academic, registrar, dregistrar | the uploads, newest first (50 by default, 500 at most) |
| GET `/legacy/uploads/{id}` | the same | the report: the upload, the changes by kind, the students (graduates first, then by matriculation number), the graduates, the first 5,000 changes in order and their total, the first 5,000 rows not loaded or left as they were and their total (`rows`, `rowsTotal`), every row counted by status (`byStatus`) and by what became of its course where that differs (`byEntryStatus`); 404 for no such upload |
| POST `/legacy/uploads/{id}/revert` `{reason}` | ict, dbops, super (a Database Operator granted over the University; the database, `LEGACY_REVERT_OFFICE`) | rolls a closed upload back from its ledger (`assessment.revert_past_upload`): `{ref, state, undone, left, heldDropped, earlierUndone, leftChanges}` |

A Database Operator reaches these only when granted over the University.

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

V771:

- check.sql block "V771:" (made-up courses ZQH 101–401, sessions 9771/9772 to 9774/9775; it undoes its writes): an upload keeps
  the course as taken and the catalogue untouched, the transcript printing each version; the same file again changes nothing and
  a corrected one corrects the units once, with the before kept and each student's CGPA before and after, a Senate-approved
  graduate keeping the approved CGPA; an upload is its officer's own and required, and an office outside the Directorate adds only
  what is missing; the Senate's units and a portal result stand over a file; versions, students and rows are told right; a
  rollback undoes only what nothing has touched since (a later result keeps the course; a wrong session's upload leaves nothing
  behind, its registration and enrolment gone; held rows are dropped with it; a course approved again goes back with its result);
  a result held for a student not yet on the register posts as taken into its upload's ledger; the carry-over history headed by
  the course as the catalogue holds it now.
- check.sql, the second "V771:" block (made-up courses ZQV 101–106, session 9785/9786; it undoes its writes): two and three
  uploads replacing one another's result rolled back newest first leave nothing, and oldest first end the same (`earlierUndone`),
  the cached position following; a registration two files put courses on goes with the second rollback; a registration decided
  on since is kept with its decision; a mark with no registration is an exception again once the course a file added for it is
  rolled back, while a rolled-back upload's own mark is not one; the Senate's units outlive a programme change on an entry with
  no version, the other student's being corrected; a dropped course approved again keeps its units under a portal result
  (UNITS_ON_PORTAL); a held row a later upload took over is not dropped; a GST course filed as Core stays GST and is told so.
- check.sql block "V772:" (made-up courses ZQR 101–104, sessions 9781/9782 and 9782/9783): the Director of ICT's removal of a
  course from one registration, a removal that sticks, an upload reporting REMOVED_ON_RECORD and REMOVAL_PENDING, and a held
  result of a removed course waiting uncounted (see `docs/course-registration-correction.md`).
- `HistoricalCourseAsTakenIT`:
  - an invented programme, one course the catalogue holds at 4 units, the old portal's results of four students loaded at the 3
    units the file states; one student is a final-year graduate the Senate approved on a CGPA of 4.50;
  - a corrected template puts two of them at 2 units. The check says so row by row, with each student's units counted before and
    after and the graduate among the graduates, and writes nothing;
  - the upload corrects both under its reference, the catalogue untouched. The report lists the graduate first for the Registry,
    and the other student's units counted 3 before and 2 after;
  - the broadsheet heads the column at the 3 units most of its students took it at, and shows the student's own 2;
  - the graduation audit leaves the approved CGPA as the Senate approved it;
  - the uploads are confirmed, loaded, closed and read by their offices only: a results upload refused to Records, the Registrar
    and the Academic Office, a registration upload to a lecturer and the Bursary; a short reason, an import with no upload, another
    officer's upload, an upload of the other kind and a closed upload refused; an upload closed once, by the officer who opened it;
    the list and the report read by the Directorate of ICT, super, Records, the Academic Office and the Registry, refused to a
    lecturer and the Bursary;
  - a closed upload rolled back by the Directorate of ICT only (Records and the Registrar refused), never while it runs, with a
    reason, once: the corrected units back as first loaded, `heldDropped` 0, the report's rows (a row without its title listed
    as AS_TAKEN_MISSING), `byStatus` and `byEntryStatus`, and the rows still listed after it.
- `RegistrationHistoryUploadIT`, `SiwesRegistrationIT` and `DatabaseOperatorAcademicIT` now begin an upload, send the title, credit
  units and category, and load under it.
- `lib/legacy-columns.test.ts`: the columns read, the Units column stopped, the rows set aside. `lib/legacy-merge.test.ts`: the
  check's batches put together, and each row's status in words (HELD_ROLLED_BACK among them). `lib/carry-over.test.ts`: the
  carry-over history headed by the course as the catalogue holds it now, each attempt under its own code and title.
