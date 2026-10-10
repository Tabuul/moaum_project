# One course, offered to many programmes across departments (V332)

The report for the brief *Enhance existing HOD Course Management with cross-department and multi-programme course
binding*. Nothing was rebuilt: the catalogue already carried the canonical model, and V332 adds the course-side
workflow, its safeguards and the screens.

## 1. What was found on inspection

| Question | Answer |
|---|---|
| Is there one canonical course record? | Yes. `catalogue.course` is keyed by the code, owned by one department (`dept_code`), with title, units, semester, level, kind, state (LIVE → ENDED; a course the department adds is LIVE at once, as an uploaded or GST course is — BOARD and SENATE remain only on courses added before that), curriculum, CA split, GST/EPS office. |
| Is there a course-to-programme relationship? | Yes. `catalogue.course_offer (course_code, programme_code, level, basis, track)` — one row an offer, basis Core, Elective, Borrowed or GST, for a track or every track. Department is derived from the programme. |
| Does anything duplicate a course per programme? | No. On Railway: 4,662 courses, 10,138 offers, 4,518 of them to a programme of a department other than the owner's. `GST 101` is one course offered to 76 programmes. |
| How does registration find courses? | `registration.student_menu` reads `course_offer` by the student's programme, level, track and curriculum, then the session's `catalogue.offering`. A binding is visible to that programme's students and to nobody else. |
| Results, allocation, GST/EPS, CBT? | All reference `catalogue.course` by code or the session's `catalogue.offering`: score sheets per offering, co-lecturers on `offering_teacher`, GST/EPS offers on `course_offer` with basis GST, CBT examinations and question banks by `course_code`. |
| What did the HOD "+ New Course" do? | Created the course under the HOD's department and stopped; the programme-side desk (Programme Structure) bound it, and the structure upload bound it. A course could not be offered from its own side, and a course of another department could not be requested — only bound directly by the programme's own Head. |
| Did the upload duplicate courses? | No: `import_courses_rows` upserts by code and binds. But it rewrote the existing course's title, units, level and kind from the uploading programme's row, even when another department owned it. |
| Were there gaps? | No course identity beside the code; no edit or rename; no duplicate detection on create; no approval path across departments; a binding removed vanished without record; no all-courses list; no programme group on a co-lecturer. |

## 2. What V332 adds

**A stable identity.** `catalogue.course.id` (uuid, unique, generated for every existing course). The code remains the
key the portal references; six foreign keys now follow a renamed code (`ON UPDATE CASCADE`), and
`catalogue.rename_course(old, new)` also moves the three holdings that carry a code without a constraint. An edit of
the title, units, semester, level or kind (`catalogue.update_course`) and a rename never make a second course.

**A binding with provenance and a record when it ends.** `course_offer` gains `added_at`, `added_by`, `source`
(COURSE, STRUCTURE, IMPORT, PROPOSAL, GST). `catalogue.unbind_offer` refuses while a student of that programme and
level is registered on the course this session, otherwise moves the binding to `catalogue.course_offer_history` with
how many registrations it had carried. The registrations, results and transcripts themselves hang on the offerings
and are not touched.

**A proposal across departments.** `catalogue.offer_proposal` (PENDING → APPROVED / REJECTED / CANCELLED, unique per
course, programme and level while pending). `catalogue.propose_offer` refuses what is already offered or already
proposed; `catalogue.decide_offer_proposal` binds on approval with source PROPOSAL; `catalogue.cancel_offer_proposal`
withdraws. Every table is on the audit spine.

**One road to bind.** `catalogue.bind_offer` validates the course (live), the programme (active, its department live),
the basis, the level and the track, and upserts the offer. The structure upload now binds an existing course owned by
another department as Borrowed (or GST, or Elective as the row says) without rewriting it, and reports those rows as
`existing`.

**A co-lecturer's group.** `offering_teacher.programme_code` names the programme whose students the co-lecturer
teaches on the offering, or NULL for all; the programme must offer the course. The score sheet stays the offering's.

**What carries a course.** `catalogue.course_usage(code)` counts registrations, scores, offerings, CBT examinations,
questions, deferred courses and old-portal results, so every edit and rename is made knowing it.

## 3. Who may do what (the existing offices; nothing new is granted)

| Act | Who |
|---|---|
| Create a course under a department | the department's Head; the Dean; Academic Office, Registry, Admin, Super (as before) |
| Bind a course into a programme | the programme's department (its Head), its Dean, or a central office — exactly the rule the Programme Structure desk already applied |
| Offer a course to another department's programme | its owner (that department's Head or Dean) or a central office proposes; the programme's department decides |
| Decide a proposal | the programme's Head, its Dean, or a central office; never the proposer's department |
| Withdraw a proposal | the department that made it, the course's owner, or a central office |
| Edit, rename, end or restore a course | its owning department (Head), its Dean, or a central office |
| Remove a binding | the programme's department, its Dean, or a central office; refused while students are registered on it this session |
| Read the all-courses list and a course's details | every catalogue reader; a department office sees courses it owns or carries, a faculty office its faculty, a student is refused |

The backend holds every rule through `OfficeScope` (department and faculty bounds) and `OfferAuthority`; the screens
only show what the server allows.

## 4. The API (all under `/api/v1/catalogue`)

- `POST /courses` — unchanged fields, plus `offers: [{programme, level, basis?, track?, reason?}]`; returns `id`,
  `bound`, `proposed` and each offer's outcome.
- `GET /courses/exists?code&title&level&semester` — the course that carries the code however it is spaced, and live
  courses with the same title.
- `GET /courses/list` — server-side search, filters (faculty, department owning or offering, programme, level,
  semester, type, status, session offered, text), sort, page and size up to 2000, scope-bound.
- `GET /courses/{code}/detail` — the course with its id, owner, departments and programmes offering (with current and
  lifetime registrations), sessions offered with lecturers and co-lecturer groups, proposals, bindings ended, usage, and
  what the acting office may do.
- `POST /courses/{code}/offers` — bound or proposed; `DELETE /courses/{code}/offers?programme&level&reason`.
- `GET /offer-proposals?dept&state` — those to decide and those made; `POST /offer-proposals/{id}/approve|reject|cancel`.
- `PUT /courses/{code}` — title, units, semester, level, kind; `POST /courses/{code}/rename` — the new code.
- `GET /directory` — faculties, live departments, active programmes, tracks, for the pickers.
- `POST /allocation/{offering}/teachers` — gains `programme`; the allocation rows carry `programmes` and each
  co-lecturer's group.

## 5. The screens

- **Department Courses → + New course**: the same fields, the owner shown, the department's programmes pre-ticked,
  "+ Add Department / Programme" with the searchable department selector and that department's programmes, a reason
  for the other department's Head, and duplicate detection as the code or title is typed: an existing code blocks
  creation and offers "Open the course" or "Offer it to my programmes instead"; a same-title course is pointed out.
  Proposals to the department's programmes are decided at the top of the desk; the department's own proposals show
  their state. Every row has Details.
- **Course details** (`/catalogue/course?code=`): the record and its Course ID, owner, departments offering, sessions
  offered, programmes offering with Remove where allowed, "+ Add Department / Programme" (bound at once within the
  office's authority, proposed otherwise), proposals with Approve, Reject or Withdraw, bindings ended, Edit, Rename,
  End and Restore with the usage warning.
- **All Courses** (`/catalogue/all`): S/N, code, title, units, level, semester, type, owner, programmes offering
  (three shown, "+N more" opens the course), last session, status, Details; Excel and PDF to the University standard.
- **Teaching allocation**: a co-lecturer may be added "for" one programme's group where the course is offered to more
  than one programme.
- **Programme Structure** (the programme-side addition) is unchanged: search any course and bind it; its track picker
  reads the track's label (a column name fixed in passing).
- **Upload or Create Courses**: the result says how many rows named another department's course and bound it as it is.

## 6. Safety

- Every write needs an actor and an office, carries the reason header, and lands on the audit spine; the new tables
  are attached to it.
- No financial field anywhere near the model; fees are derived from the course by the Bursary's own rules as before.
- A binding is never deleted while students of that programme and level are registered on it this session; ended
  bindings are kept with what they carried.
- A code is unique across the University; a rename to an existing code is refused; a new code must be in the standard
  form; the renamed course keeps its id and every reference.
- Duplicates already on the register are untouched: the per-department duplicate desk (V329) stays the reconciliation
  path, and the new detection stops new ones being created.

## 7. Tests

- `db/check.sql` property 180: the owner's programme bound at once; another department's by approval, a repeat
  proposal and a proposal of what is offered refused; the course edited and renamed with the identity and both
  bindings kept; a binding ended kept on the record; an ended course refused; a structure upload binding another
  department's course as Borrowed without rewriting it. Suite: 180 properties green on a brand-new database.
- `CourseOfferingIT`: the Head creates a course with an own-programme offer and a cross-department proposal; the code
  is detected as existing when typed `zzo901`; the proposing Head cannot approve, the programme's Head can; one course,
  two departments, two programmes; the other Head cannot edit it; edit and rename keep the id and the bindings; the
  owner cannot remove the other programme's binding, that programme's Head can and it is kept on the record; the list
  is the office's scope; a student token is refused; the Academic Office binds across departments without a proposal.

## 8. After deployment

Nothing changes on the day: every course keeps its code, every binding stays, every existing course gets an id. Heads
of Department will see "+ Add Department / Programme" on the new-course form and Details on every course; proposals
begin to flow when a Head offers a course beyond their department. Departments that have been creating a second code
for a course another department owns should instead open the existing course and add their programme, and may fold
the duplicates they already carry through the duplicate desk.

## 9. Codes written without the hyphen (V333)

The old portal's uploads carried the University's prefixed codes with the hyphen dropped: MOAUCHM 101 for MOAU-CHM 101,
BSUGEO 413 for BSU-GEO 413. The Department Courses desk now lists them under "Codes written without the hyphen" with
the code each should read, what the wrong code carries, and a Rename on each row; "Fix N codes" corrects every one
whose corrected code is free in one act. A rename is V332's: the course keeps its identity and every registration,
result, offering and binding follows the new code. Where the corrected code is already another course, the two are the
same course under two codes and the row says so: the wrong one is ended or removed on the duplicates desk, never merged
blindly. `catalogue.rename_course` now accepts every form the catalogue keys (CSC 311; MOAU-CHM 101), normalising case
and spacing; a prefix is known when the catalogue already carries it hyphenated or it is one of the University's own
(MOAU, MOAUM, MOUA, BSU, FBSU). Property 181 and `CourseOfferingIT` cover it. Railway carried one such code at the time
(BSUGEO 413); the AWS portal, fed by uploads, is where the rest are expected.

## 10. One course held once, whatever the session (V386)

**What was found.** The pool already followed the rule: `catalogue.course` holds a course once (its code, a stable id, no
session); `catalogue.course_offer` binds it to programmes and levels with no session and is reused every session; a session's
class (`catalogue.offering`) carries the session, semester and lecturer, and registrations, score sheets, results, allocations
and CBT examinations hang from the class. The All courses page needs no session (its "Offered in session" filter is optional
history). Three gaps were closed.

**1 · The structure upload matches the pool.** `catalogue.resolve_course_code` is the one rule: the code as written if it is
a course; its normal form (CSC101 → CSC 101); a code merged into another; the one course written the same way (CSC-101); the
course a session copy copies ("CSC 101 2025/2026" → CSC 101); else the normal form of a new course. The programme-structure
upload (`import_courses_rows`) and the catalogue upload (`import_catalogue_rows`, and its prerequisites) both use it.

**2 · Both semesters.** `catalogue.course.both_semesters` (first and second; never with the third — `CAT_SEMESTER_BOTH`).
Opening registration, the CCE classes, the GST/EPS gaps, SIWES units, deferment and the current-session class for a course
made live all open or count it in each semester (`catalogue.runs_in`); the course list's semester filter finds it in either.
A student registers it once a session (`REGISTRATION_ONCE_A_SESSION`). The uploads read "Both", "B", "1 & 2", "First and
Second"; the course page's edit and the new-course form take it.

**3 · Duplicates.** The pool refuses a new code (or a rename) that is a course written differently (`COURSE_DUPLICATE_CODE`),
a copy of a course for a session (`COURSE_SESSION_COPY`) or a merged code (`COURSE_CODE_MERGED`); a rename onto a code taken
is refused by the key as before. The twins already held are listed (`catalogue.duplicate_codes`, on All courses: "The same
course under two codes") with the code to keep — the University's form, then the live one, then the one more used. A merge
(`catalogue.merge_course`) is previewed by anyone who may edit courses and made by the Academic Office or the Registry with a
reason: every class (with its registrations, sheets and results), binding, prerequisite, CBT examination, question, deferral,
offer proposal and held old-portal result moves to the course kept; a binding or prerequisite the course kept already holds
stays as it is; the merged code becomes an alias (`catalogue.course_alias`, with the merged record as it was, what moved and
why) and answers for the course kept in every upload and on the course page. Refused: two courses that are not one by code
or by title, level, semester and owner (`MERGE_NOT_SAME`); a BSU- code and its MOAU- twin (`MERGE_FAMILY`); a BMAS course and
its CCMAS counterpart (`MERGE_CURRICULUM`); two general-studies offices; an ended course kept; and two classes in the same
session and semester (`MERGE_CLASS_CLASH` — two classes are not joined by a merge). The department duplicates desk offers
"Merge into …" beside Remove and End. Issued documents keep the code they were issued with.

**API.** `GET /duplicate-codes`, `POST /courses/merge/preview`, `POST /courses/merge`; `PUT /courses/{code}` and
`POST /courses` take `bothSemesters`; `GET /courses/{code}/detail` resolves a merged or differently written code and lists
the aliases.

**Tests.** check.sql — the V386 property (both semesters opened and registered once, resolution, the guard, the upload, the
twins listed, the dry run, the merge, the alias, the family refusal; 228); the V333 property makes its deliberate twin with
the guard off, as the old data was. `CourseMergeIT` through the API.
