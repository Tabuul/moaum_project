# One course code, different titles: separate courses (V646)

The University's master prompt of 23 October 2026 asked that the same course code may carry different courses. For example,
CSC 401 *Computer Networks* under CCMAS and CSC 401 *Advanced Computer Systems* under BMAS. Each is its own course: never
merged, and one title never written over the other.

The University's answers:
- **Separate courses.** Each course has its own record, class, lecturer, score sheet and results.
- **Existing courses.** Those whose titles may have been written over are reported for review; nothing changes on its own.

## What held before

- **The code was the key.** `catalogue.course.code` is the pool's key. Classes, programme bindings, registrations (through the
  class), results, CBT papers, questions, prerequisites and deferrals all point at it, so a code was one course.
- **Uploads wrote titles over.** The structure upload (`catalogue.import_courses_rows`) wrote the file's title over the course's.
  A department that uploaded its BMAS structure and then its CCMAS one left CSC 401 with the second file's title. Both
  curricula's students were then in one class and on one result sheet.
- **A held code could not be reused.** Creating a course under a code already held was refused.

## What holds now

### A separate course under a code

- **Its own key.** A second course under a code gets the code plus its curriculum: CSC 401 BMAS, CSC 401 CCMAS2, or CSC 401 V2
  for one of no curriculum. Everything already keyed by the first course stays exactly as it is, and the new course has its own
  classes, bindings, registrations, results, sheets, examinations and carry-overs.
- **Course ID.** `catalogue.course.id` is still the Course ID; it is shown on the course page.
- **Shown code.** `catalogue.shown_code(key)` is the code shown and searched (CSC 401). `catalogue.code_variant(key)` is the mark
  (BMAS). In the frontend, `lib/course-code.ts` provides `shownCode`, `codeVariant` and `courseLabel` ("CSC 401 — Advanced
  Computer Systems (BMAS)").
- **A code and a title are held once.** The index `ux_course_shown_code_title` covers the code shown and `catalogue.title_key(title)`,
  which ignores case, spacing and punctuation and reads Intro as Introduction. The same code with the same title is the same
  course, whatever its curriculum.

### Creating a course

- `catalogue.create_course` takes a curriculum. A code held under another title gives a separate course under it; the same code
  and title is refused as before.
- On the New course form, the check (`GET /catalogue/courses/exists`) now returns:
  - `byCode`: the course under the code **with the title typed**. This is the same course, so the form offers to add the
    programme to it.
  - `underCode`: every course the code carries. With another title, the form says it makes a separate course and asks for the
    curriculum.

### The structure upload

- **No title is written over**, and a course keeps the curriculum it has.
- **Same code, different title.** A row whose code the pool holds under another title is refused (`COURSE_TITLE_DIFFERS`)
  until the row says one of:
  - **SAME**: it is the same course. It is bound to that course and keeps the pool's title; `sameAs` names which course where
    the code carries more than one.
  - **SEPARATE**: it is a separate course. It is created under the code with the file's title and the upload's curriculum.
- **A matching title** (case, spacing and punctuation aside) binds without asking.
- **The upload screen.** It previews these rows (`POST /catalogue/import/titles`, `catalogue.structure_title_choices`) in a
  "Same code, different title" panel. Each row gets a choice of "The same course as …" or "A separate course under …", with
  buttons to set every row one way. Load stays disabled until every row is decided.

### The Duplicate course code report

All Courses has a **One code, different titles** panel (`GET /catalogue/same-code`, `catalogue.same_code_courses()`). It lists
every code held more than once, and every course whose title was changed after it was created. Title changes come from the
audit trail, with the earlier titles and the date of the last change.

For each course the panel shows:
- the Course ID;
- the curriculum, owner, faculty, level, semester, kind and state;
- the programmes it is bound to.

The panel filters by code or title, by kind (shared codes or changed titles) and by curriculum, and exports to Excel.

**Separate course** (the Academic Office or the Registry, with a reason; `POST /catalogue/courses/{code}/separate`,
`catalogue.separate_course`):
- makes a separate course under the code, with its own title and curriculum and the course's units, semester, level, owner and
  settings;
- moves the ticked programme bindings to it, and opens its classes for the sessions open.

Classes, registrations and results already made stay with the course they were made under.

### Registration, allocation, results and documents

- **Students see both.** A student whose programme binds two courses under one code at their level sees both on the
  registration page and may register both, since each has its own class.
- **No class twice.** The same class is never registered twice: the entry's key is the registration and the class.
- **Showing the code.** Registration, Add other course, results, carry-overs, attendance, the course form, the examination card,
  the GST & EPS permit (screen and PDF), the results and broadsheet PDFs, All Courses, the course page and the allocation desk
  show the code without the mark. The title, and the curriculum where the course is a separate one, tell them apart.
- **Unchanged.** Allocation, results and carry-overs already go by the class and the course key, so they needed no change.

### BMAS and CCMAS at 400 and 500 Level

This already held since V590. With the curricula open (`registration.flex_policy.curriculum_open`, on), a student sees every
course bound to their programme at their level, BMAS or CCMAS. A course added beside the list is judged without the curriculum
test. V646's check proves that a 500 Level BMAS student sees a CCMAS course bound at 500.

## Tests

| Test | What it covers |
|---|---|
| `check.sql` V646 (EXPECTED 472) | a second course under a code created with its own key, and the exact course refused (by the function and by the index); the upload refused until it says, previewed, SEPARATE creating the course, SAME keeping the title and curriculum, a same-title row bound without asking; a 400 Level student seeing and registering both, the same class never twice; a 500 Level BMAS student seeing the CCMAS course; the report; a separate course taking the programme moved to it |
| `SameCodeCoursesIT` | through the API: the exists check, create with curriculum, the exact course refused, the titles preview, the upload refused then separate, the report, the course list, separate by the Registry and refused to a Head of Department |
| `lib/course-code.test.ts` | the code shown, the mark, the label, the row-choice key |
