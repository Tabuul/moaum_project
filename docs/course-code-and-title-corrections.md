# Course code and title corrections (V713)

The University's brief of 30 October 2026: the Director of ICT and authorised ICT Support staff change a course's **code** and
**title** from Course Management, and the course stays the same course.

## What already stood

| The brief asks | Where it already was |
|---|---|
| One canonical course, its stable Course ID | `catalogue.course.id` (V332); the code is the key every record follows |
| A code change carries every record with it | `catalogue.rename_course` (V332/V333): 17 keyed tables follow the code (`ON UPDATE CASCADE`) — classes, registrations, carry-overs, results, score sheets, bindings, prerequisites, CBT examinations, questions, deferred courses, lecturer allocations |
| The same code under another title is allowed | V646: a separate course under a key of its own (`CSC 401 V2`, `CSC 401 BMAS`), shown as `CSC 401`; the same code and title is held once (`ux_course_shown_code_title`) |
| Usage before a change | `catalogue.course_usage` (V332) |
| Change history | `catalogue.course_history` from the audit spine (V445) |
| ICT Support within its scope, on a ticket | `StructureAccess` (V471, Oct 2026): EDIT_COURSES within the posting's faculties and departments; the change on the ticket's timeline |
| Merge kept separate | `catalogue.merge_course` (V386), the Academic Office and the Registry only |
| Server-side search, paging, Excel and PDF | All Courses (`/catalogue/all`, V445) |

## What V713 adds

- **The Director of ICT** corrects any course's code and title (`may.correctCode`, `may.correctTitle`). V460's rule stands
  otherwise: the Director keeps the structure and does not edit units, level or semester.
- **ICT Support capabilities.** A posting may carry `EDIT_COURSE_CODE` and `EDIT_COURSE_TITLE`; `EDIT_COURSES` carries both. The
  posting screen now offers the four structure capabilities (`VIEW_PROGRAMME_STRUCTURE`, `EDIT_COURSES`, `BIND_COURSES`,
  `MANAGE_PREREQUISITES`). The database's vocabulary had them since V471, but the API and the screen did not, so only the Head of
  the desk could edit courses. Each capability holds within the posting's faculties and departments. The Head works anywhere.
- **"Change code or title"** on the course page replaces "Rename the code". The plain Edit no longer changes the title
  (`COURSE_TITLE_BY_CORRECTION`). The correction:
  1. **Shows what would happen** (`POST /catalogue/courses/{code}/correction/check`, read-only): what hangs on the course
     (`catalogue.course_impact`: registrations and this session's, students, carry-overs, results and published results, score
     sheets, classes, lecturer allocations, programme bindings, CBT examinations, questions, deferred and old-portal results,
     broadsheet omissions, the GST/EPS office), the courses already under the new code, the courses of the same title (a possible
     duplicate has the same units, level and department), and why it would be refused.
  2. **Asks for a reason** from the University's list, with remarks; "Other" needs remarks.
  3. **Confirms** the current and new values, the impact and the reason.
  4. **Saves** (`POST /catalogue/courses/{code}/correction`, `catalogue.correct_course`) against the version the person read
     (`catalogue.course_version`). A course changed since is refused with `COURSE_CHANGED_SINCE` ("updated by another user;
     reload"), never overwritten. The code and the title change in one statement, in one transaction.
- **Refusals.** A code written differently from one held, a merged code or a session copy is refused as the pool's guard refuses
  them. The same code with the same title is the same course: refused (`COURSE_SAME_CODE_AND_TITLE`), because a correction never
  merges.
- **A code held under another title.** It no longer refuses the change ("a code is unique across the University"). The corrected
  course keeps its own record under that code (V646's separate course).
- **Titles on past classes.** A corrected title reaches every class of the course: results, broadsheets and transcripts read the
  class's title (V338). The person correcting may keep the old title on classes already registered or examined (a course renamed
  by the curriculum, not mistyped). Units never change by a correction.
- **The trail.** `catalogue.course_change` records every change of a code or title, whoever makes it:
  - a correction, with its reason, remarks, ticket and past-classes choice (source `CORRECTION`);
  - the department's desk, an upload or a merge (`EDIT`), or a migration (`MIGRATION`), with the request's reason;
  - changes before V713, copied from the audit spine (`AUDIT`).

  The trail is never altered or removed (`COURSE_CHANGE_KEPT`). `catalogue.course_history` now reads every code the course has
  had, so a renamed course keeps its history.
- **The report.** "Course Code & Title Changes" (`/catalogue/changes`, `GET /catalogue/course-changes`) lists every change and is
  searchable by old or new code, title, Course ID, ticket, department and remarks, by field, by how it was made and by date. It
  exports to Excel and PDF and is read by:
  - the Academic Office, the Registry, Records and Audit;
  - the Director of ICT and ICT Support.
- **Search.** All Courses finds a course by its Course ID and by a code it was held under before a correction.
- **Broadsheet omissions follow a rename** (`catalogue.follow_code`): the omissions V624 holds by code, beside the postings and the
  old-portal results that `rename_course` already carried.

## Not changed

- A course's identity is its id; its code stays the key the records follow (no re-keying).
- No financial record is touched.
- The department desk's one-click hyphen fixes (`/code-fixes`) and its rename keep working. They land on the trail as `EDIT`
  with the request's reason.

## Checked

- check.sql V713: a made-up course with a class, a carry-over and a broadsheet omission.
  - Retitled, with its registered class; units unchanged.
  - Refused against an old version.
  - Moved onto a code another course holds under another title: kept separate as `ZZJ 405 V2`, with the carry-over and the
    omission following.
  - Refused onto the same code and title.
  - A plain rename lands on the trail too.
  - The trail cannot be altered.
  - The history still reads the course's creation under its first code.
- `CourseCorrectionIT`, covering both the Director and ICT Support.
  - The Director: impact first; a reason required; a stale version refused; the title corrected with the past class retitled; a
    second person's older version refused; the plain edit refusing a title.
  - The code moved onto a code held under another title, keeping the registration, the single carry-over, the result, the
    lecturer, the binding and the question on the same Course ID.
  - The history reads the old code; the old code and the Course ID find the course.
  - The same code and title refused with nothing written; a GST course keeps its classification.
  - An agent: refused without a posting; with `EDIT_COURSE_TITLE` it may change the title only, on a ticket, keeping past classes'
    title; refused out of scope.
  - Another department's Head refused.
  - The report searchable by Course ID and old code; refused to a Head of Department.
- `CourseOfferingIT`, `PgProgrammeStructureIT` and `SupportCourseOwnerIT` now change titles through the correction.
- `lib/course-correction.test.ts`.
