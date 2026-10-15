# Student classification and the Student Query (V469)

Every learner the portal holds is classified once, from structured fields, and every student list, figure and export reads
that one classification.

## Where each dimension comes from

| Dimension | Source | Configured by |
|---|---|---|
| Programme type | an office's decision (`people.classification_decision`), else the entry mode, else the programme's category — the order `finance.programme_type_for` has used for payments since V409 | `finance.programme_type` (code, label = name, description, active, ord = display order, uuid `id`, `entry_modes`, `programme_categories`, `allowed_categories`, `default_centre`, `offices`) |
| Admission route | the entry mode the record carries (`ref.admission_route.entry_mode`), or the decision's route | `ref.admission_route` |
| Study mode | the student's own `people.student.study_mode` (FULL_TIME, PART_TIME, SANDWICH, EVENING, WEEKEND, DISTANCE_LEARNING, OTHER) | the Academic Office or the Registry, with a reason |
| Centre | `people.student.centre_code` when recorded, else the programme type's `default_centre` | `ref.centre` (MAIN_CAMPUS, CCE, SANDWICH_CENTRE, ADIKPO, OTHER) |

Nothing is read from a programme or department name, a matriculation or JAMB number, a username or an admission year.

A register student nothing claims (**UNCLASSIFIED**), or whose type does not admit the programme's category (**CONFLICTING**
— a POSTGRADUATE entry mode on an undergraduate programme, say), **requires classification**: it is counted in no type and
waits on *Student Classification* for the Academic Office, the Deputy Registrar, the Registrar or the platform to decide.
On the live-shaped copy (15 Oct 2026) that is three records: two MBBS students and one B.Sc. Accounting student whose entry
mode reads POSTGRADUATE.

## The learners

`people.learner` is every learner in one shape, without a second student table:

- the register (`people.student`, merged duplicates left out), with its classification and academic position;
- the JUPEB learners (`jupeb.application`, from admission on — ADMITTED, STUDENT, COMPLETED, DEFERRED, or WITHDRAWN after
  activation), type JUPEB, no faculty or department;
- the admitted Preliminary learners (`admissions.prelim_review` ADMITTED), typed by their programme's own `programme_type`
  and shown under their target programme — never as undergraduates.

A JUPEB or Preliminary learner who later joins the register keeps the earlier record: the office records the progression on
the student's record (*Record progression*), the event (`PRELIMINARY_TO_UNDERGRADUATE`, `JUPEB_TO_UNDERGRADUATE`) goes on
`people.programme_type_event` and the earlier row reads PROGRESSED. A correction is an event there too; every decision is
kept, a later one superseding an earlier.

## Who sees what

The scope is the server's (`StudentQueryService.scope`), never the request's: a filter outside the scope returns nothing.

| Office | Scope |
|---|---|
| Registrar, Deputy Registrar, Academic Office, Exams and Records, Director of ICT, VC, DVC, Bursar, Super Administrator, System Administrator | the University |
| Dean, Faculty Officer | their faculty |
| Head of Department, Examinations Officer | their department |
| Provost, College Secretary, Finance Controller | the College of Health Sciences |
| School of Postgraduate Studies (Dean, Secretary) | POSTGRADUATE |
| Centre for Continuing Education | CCE |
| JUPEB Office | JUPEB |
| Preliminary Science Office | PRELIMINARY |
| Sandwich Programme Office (new office, V469) | SANDWICH |

The fee filter is for the offices that read a student's school fees (the record's own list, V360). The GST and EPS offices,
the hostel and the ICT Support Desk keep their own screens, each limited to what it serves.

## Screens

- **Student Query** (`/student-query`): student type first (the cards apply it), then admission route → centre → faculty →
  department → programme → session → level → status, and each type's own filters (PG type, Preliminary type and target,
  JUPEB combination and subject); quick queries; the filters applied, each removable, and Clear all; a server-side search as
  one types (name, matric, JAMB, application number, student ID); Excel and PDF headed `STUDENT TYPE: …` with the filters.
- **Student Classification** (`/student-query/classification`): the data-quality report and the learners to be decided.
- **Student population** cards on the Registrar's, Academic Office's, ICT, VC, Dean's, Head's and PG School's dashboards.
- **Student Statistics** gains the student-type filter and a by-type table; the student record shows the type and its history.

## Not done here

- Inter-departmental transfer is a route an office may set by decision; the register keeps no entry mode for it.
- No sandwich students, Adikpo centre records or study modes beyond full- and part-time exist on the live copy yet.
