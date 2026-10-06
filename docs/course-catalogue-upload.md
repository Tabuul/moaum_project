# Course catalogue: owners, offerings and the upload (V338; the reset withdrawn by V340)

V338 added a course catalogue reset and a page for it, **Course Catalogue Reset & Upload** (`/catalogue/manage`). Both
were rolled back at the University's request, by V340 and the code changes alongside it. The rest of V338 stays.

## What stays from V338

- **Owners.** `catalogue.course.owner_programme` names the owning programme, which must belong to the owning department.
  **Change owner** on a course's page is for the Academic Office, the Registry and ICT. Every change of owner
  department or programme goes to `catalogue.course_owner_history` with the source (desk or upload), the reason, and
  who made it.
- **History keeps its title.** Each session offering keeps the title and units it was given (`catalogue.offering.title`,
  `.units`). A correction of the course reaches only offerings with no registration or score sheet. These read the
  offering's own title:
  - the student's results (`assessment.student_results`, which also feeds statements and transcripts);
  - result sheets and broadsheets;
  - registration slips and the registration history;
  - the records returns.
- **Prerequisites** are recorded on `catalogue.course_prerequisite`. They are not enforced at registration.
- **The All Courses list** shows the owner programme. It exports with S/N first and adds an **Offerings (Excel)** export,
  with one row per programme offering.
- **The owner/offering upload's API.** `POST /api/v1/catalogue/catalogue-import` (with `?commit=true`) and its history
  remain, for ICT, the Academic Office and Super. Each row is one offering, and all of a file's rows are judged against
  the register before anything is written. The file is committed only if no row is invalid; it then makes one course per
  code with an offering per programme. Its page went with the reset page, so for now it has no screen.
- **The existing Course Upload** (`/catalogue/upload`, the per-programme structure upload) is unchanged.

## The reset, withdrawn (V340)

| Removed | Where |
|---|---|
| The page **Course Catalogue Reset & Upload** | `frontend/src/app/catalogue/manage/` |
| Its route `t/coursecatalogue` and its menu item | ICT, Academic Office and Super menus |
| The reset endpoints | `GET /api/v1/catalogue/reset/preview`, `POST /api/v1/catalogue/reset`, `GET /api/v1/catalogue/reset/history`, `GET /api/v1/catalogue/reset/{id}` |
| The "archived by a course reset" notices | Department course list, course page |
| The reset's database functions | `catalogue.course_reset`, `catalogue.course_reset_preview`, `catalogue.reset_courses`, `catalogue.reset_scope`, and its helpers `catalogue.course_has_history`, `catalogue.offering_has_history` |

The reset added no permission of its own. Its endpoints used the existing offices: ICT, Academic Office and Super.

On the live database the reset was **never run**: no reset, no reset item, no course archived by one. No course,
offering, registration or result was touched by V338's reset, and V340 writes no row.

These are **kept on purpose, empty and unused**:

- the tables `catalogue.course_reset` and `catalogue.course_reset_item`;
- the column `catalogue.course.reset_batch_id`.

Both course uploads still read that column, and it now always stays NULL. Removing it would mean rewriting the existing
Course Upload for no gain.
