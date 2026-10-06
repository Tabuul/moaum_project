# Course catalogue: the reset, and the upload with owners and offerings (V338)

The page is **Course Catalogue Reset & Upload** (`/catalogue/manage`). It is in the menu of the Directorate of ICT, the
Academic Office and Super. Both acts are central: no Head of Department, Dean or support officer can reset or upload.

## What the catalogue already was

These parts existed before V338 and are reused unchanged:

- **One record per course.** `catalogue.course` is keyed by its code, with a stable `id`. It is owned by one department.
- **Programme offerings.** `catalogue.course_offer` binds the course into each programme that offers it, at a level. It
  carries the **basis** (Core, Elective, Borrowed or GST). The basis belongs to the offering, not the course, so the same
  course can be Core for one programme and Elective for another.
- **Session offerings.** `catalogue.offering` is a course's instance in a session and semester. Registrations, score
  sheets, CBT and lecturers hang on it. Registration entries keep the units each student registered.
- **Registration.** A student's menu is built from the bindings into their programme and level, never from the bare
  course table.

## The upload

The upload takes one row per programme that offers a course. A course offered to five programmes is five rows that
name the same course, and they become **one course with five offerings**.

| Column | Meaning |
|---|---|
| S/N | Display only |
| Course Code, Course Title, Units, Level, Semester | The course. A new course needs its title, units and semester. |
| Course Type | Core, Required, Elective or GST: the course's own category, optional |
| Course Owner Faculty / Department / Programme | Who owns the course. The programme must belong to the department, and the department to the faculty. |
| Offering Faculty / Department / Programme | Who offers it. The programme is required; the department and faculty, when given, must match it. |
| Offering Type | CORE or ELECTIVE, for this programme |
| Status | ACTIVE (the default), or INACTIVE to skip the row |
| Academic Session | Optional. It is checked against the calendar. Offerings are curriculum-wide and are opened per session by Open Registration. |
| Description | Kept on the course |
| Prerequisite Course Code | One or more codes, separated by commas. Each must exist or be in the file. |
| GST/EPS Classification | GST or EPS: the course is offered as GST |
| Remarks | Kept with the upload's record |

A file may instead put several programmes in one cell ("Offering Programmes", with "Offering Types" in the same order).
Each is read as its own row; the raw list is never stored.

Every row is judged before anything is written. Faculties, departments and programmes are matched by code or name, and
nothing is created on the register. These are refused:

- an unknown or archived reference;
- a hierarchy that doesn't fit;
- an offering type other than CORE or ELECTIVE;
- the same course offered to the same programme and level twice;
- rows of one code that disagree on its title, units, semester or owner;
- a course ended on its department's desk;
- an unknown prerequisite.

The preview counts each of these, and the error report lists every row to correct. **Commit** writes only a file with no
invalid row. It runs in one transaction under one reference (COURSE-IMPORT-YYYY-NNNNN) and does the following:

- creates new courses;
- updates existing ones;
- brings a course archived by a reset back to LIVE as the same record;
- records owner changes;
- binds each offering;
- records prerequisites.

The older per-programme structure upload (`/catalogue/upload`) still works. It also brings a reset-archived course back.

## The reset

The reset applies to the whole catalogue, a faculty, a department or a programme:

- **Courses in scope.** Every active course owned by the scope's departments. For a programme, the courses of its
  department bound to that programme alone.
- **Programme offerings.** Every binding into the scope's programmes, and every binding of those courses. Each ends and
  is kept on `course_offer_history` and on the reset's items.
- **Session offerings.** One with nothing on it is removed. One with a registration, a score sheet, a timetable, a
  class, attendance, LMS work, a SIWES supervisor, a deferment, a CBT examination or a lecturer is kept.
- **Courses.** A course with nothing on it is removed, and its whole row is kept on the reset's items. A course that
  carries any history is archived: it becomes ENDED, marked with the reset, and is never deleted.
- **GST/EPS courses** belong to their office and are left alone.
- **Pending proposals** to or from the scope are cancelled.

The page shows the impact first. The reset then needs a reason and the typed words RESET COURSES. It is one transaction
under one reference (COURSE-RESET-YYYY-NNNNN). Uploads and resets take the same lock, so two can't run at once.
Registrations, results, scores, transcripts, CBT, payments and the audit spine are never touched.

## History keeps its title

Each session offering keeps the title and units it was given (`catalogue.offering.title`, `.units`). A correction of
the course reaches only offerings that carry no registration or score sheet. These read the offering's own title:

- the student's results (`assessment.student_results`, which also feeds statements and transcripts);
- result sheets and broadsheets;
- registration slips and the registration history;
- the records returns.

## Owners

`catalogue.course.owner_programme` names the owning programme, which must be one of the owning department's.

Every change of owner department or programme goes to `catalogue.course_owner_history`, with the source (desk, upload
or reset), the reason, and who made it. **Change owner** on a course's page is for the Academic Office, the Registry and
ICT.

## Not done

- **Prerequisites are not enforced.** They are recorded and shown, but registration doesn't refuse a course whose
  prerequisite is unpassed. Enforcing them would block students wherever the University's prerequisite data is
  incomplete, so that's a decision for the University.
- **No password re-entry for the reset.** The portal has no re-authentication step to reuse, so the typed confirmation
  and the reason stand instead.
