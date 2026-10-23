# Database Operations: the office, the Database Operator, and examination readiness (V640)

This is the implementation report for the brief *Database Operations Office, Database Operators, Student Classification and
Examination Readiness Reporting* (23 October 2026). Examinations start on Monday 26 October, so examination readiness came first.
Nothing was rebuilt. The student register, the classification engine, central finance, the registration engine, the programme
structure, the results and the RBAC all stay where they are; the new office reads them.

## 1. What was there

| Need in the brief | Existing piece, kept |
|---|---|
| Offices, grants, staff assignment, dashboards by office | `ref.office`, `iam.office_assignment` and its scope trigger, Users & Roles, the office menus and the home page |
| Permissions | each endpoint names the offices it admits (`@PreAuthorize`); the database checks the office again for every act |
| One classification engine | `people.student_classification` and `people.learner` (V469): programme type, admission route, study mode, centre, faculty, department, programme, level, status, spillover state |
| Student Query | `StudentQueryService` (V469): one parameterised WHERE clause for the list, the figures and the options |
| Paid and registered | `reporting.student_positions(session, semester)` (V257), the engine Student Statistics reads: the students in study, each with the fee obligation (`finance.session_positions`) and the registration across three registers |
| The examination card | `registration.exam_card_state` (V501, V567): a confirmed school-fees payment for the session, and a submitted registration with a course |
| SP1, SP2, beyond the maximum | the cohort engine, `people.academic_position` |
| Exports | `brandedXlsx` and `brandedPrint`: the University's heading and logo, the title, the filters, S/N first, the serial, the date and who generated it, page numbers |
| The export log | `platform.export_log` (V523) |

What was missing: an office for the work, examination readiness by course, department and faculty with drill-down, official
report references, saved and shared reports, a controlled query engine, a query log, and a data quality view.

## 2. The office and the Database Operator

* `ref.office` gains `dbops`, "Database Operator, Database Operations". It is assigned like any office, on Users & Roles, to the
  person already on the staff register. No duplicate staff record is made.
* A grant is held over the University, or bounded to a faculty, a department or a programme. `iam.dbops_scope` reads the live
  grant. `OfficeScope.bound` and `AnalyticsScope.bound` hold every request to it on the server. A request outside the scope is
  refused; a grant whose scope no longer resolves reads nothing. A programme-bounded operator reads the Database Operations
  screens for that programme; Student Query, whose grain is the department, reads nothing for them.
* The office is not a super administrator, and it never touches production with database credentials. Every read goes through
  the API, in a read-only transaction, under the API's statement timeout.

The portal has no permission table; its permissions are the offices each endpoint admits. The brief's permissions map to the
portal like this:

| Brief's permission | In the portal |
|---|---|
| `DATABASE_OPERATIONS_ACCESS` | the `dbops` office and its menu |
| `VIEW_STUDENT_DATABASE`, `QUERY_STUDENT_DATABASE`, `QUERY_ACADEMIC_DATABASE`, `QUERY_REGISTRATION_DATABASE` | Student Query, Student Records, Student Statistics, the query engine's register, registration, course, hostel, clearance, GST/EPS and results sources |
| `QUERY_FINANCIAL_DATABASE`, `VIEW_PAYMENT_REPORTS` | the School Fees Report, Payments Query, Spillover Students, the query engine's payments source, amounts on readiness lists |
| `VIEW_STUDENT_CLASSIFICATION` | Student Classification, read only |
| `VIEW_REGISTRATION_REPORTS`, `VIEW_EXAMINATION_READINESS_REPORTS`, `GENERATE_*`, `EXPORT_*` | Examination Readiness, the query engine, their Excel and PDF |
| `CREATE_DATABASE_QUERY`, `SAVE_DATABASE_QUERY`, `VIEW_SAVED_QUERIES`, `EXECUTE_SAVED_QUERIES`, `CREATE_REPORT`, `SAVE_REPORT`, `VIEW_REPORT_HISTORY` | the query builder, saved and shared reports, the query log |
| `VIEW_DATA_QUALITY`, `CREATE_DATA_QUALITY_REPORT`, `VIEW_RECONCILIATION_REPORTS` | Data Quality and its exports; Graduation Management and the lifecycle desk, read only |
| `VIEW_DATABASE_AUDIT` | everyone's query log and the whole register of official reports |

Not granted: deleting records, dropping or altering tables, deleting or changing students, payments or results, refunds,
matriculation numbers, passwords, RBAC, approving payments, graduation, programme or level changes, transfers. The office is in
none of those endpoints' lists. `MANAGE_STUDENT_CLASSIFICATION` is not granted either. Deciding a classification stays with the
Academic Office and the Registry; Database Operations finds the unclassified record and sends it to them.

## 3. Examination readiness

`reporting.exam_readiness(session, semester, faculty, department, programme, level, programme type, course, rule)` gives one row
per student. It is built on `reporting.student_positions`, so it counts the same students Student Statistics counts.

* **Population.** In study (ACTIVE, PROBATION), fresh students of the session (ADMITTED with that entry session), and anyone with
  a registration or a school-fees payment for it. A student who has left (graduated, withdrawn, expelled, transferred out,
  deceased, progressed) is not in it. An admitted student of an earlier session who never came is not counted as owing.
* **Registered.** The registration engine's own verdict across its three registers: the School of Postgraduate Studies'
  (`admissions.pg_registration`), the College of Health Sciences' from 200 Level (`college.enrolment`), and the University course
  registration (`registration.course_registration`: submitted, approved or locked). Never a page visit, a draft or the browser.
* **Paid.** Rule CARD, the default: the examination card's own test. That is a school-fees payment confirmed for the session, of
  any amount, on any channel. A pending, expired, unconfirmed or failed reference is never paid. Rule FULL: school fees paid in
  full for the semester, the Bursary's position. The screen offers both.
* **The readiness:**

  | Category | Means |
  |---|---|
  | PAID_REGISTERED | paid and registered |
  | PAID_NOT_REGISTERED | paid, no registration |
  | NOT_PAID | a fee is charged and nothing is paid, registered or not |
  | NO_FEE_STATED | nothing charged and nothing paid; never counted as not paid |

* **The examination card** column is the card's own rule, and the check proves it agrees with `registration.exam_card_state` for
  every student. The card's rule was not changed.
* **Exceptions**, each its own figure: a registration not submitted, returned or without courses; registered and not paid;
  registered with no fee stated; fees settled with no school-fees payment on record (the card is withheld); a registration only
  submitted, which class lists and score sheets do not read yet; a part payment.
* **Carry-over and spillover.** A student registered only for carry-overs is registered. Units are never held to the minimum.
  SP1, SP2 and beyond the maximum come from the cohort engine as the academic status, next to the programme type.
* **A course.** Registered for the course on the University course registration, or expected by the programme structure
  (`catalogue.course_offer` for the student's programme and level, never an elective). The College's and the School of
  Postgraduate Studies' courses are registered in their own registers and are not read here.
* `reporting.exam_readiness_summary` counts it by faculty, department, programme, level, programme type or academic status.
* `reporting.course_readiness_summary` lists each course a department or faculty offers in the semester: registered, of them paid
  and not paid, expected by the structure, and of them not registered (and paid).

Every number on the screen is a link to its students, and a grouping opens the next one down: faculty to department to programme
to level.

### The package and its reference

**GENERATE EXAMINATION READINESS REPORT** issues one reference, `DBO/EXAM/YYYY/NNNNNN`, from `reporting.issue_report`: a counter
per kind and year, never a table's own key. It records the filters, the scope, the figures and who issued it in
`reporting.official_report`. The package has six reports, each exported to Excel or PDF with the same reference, filters and
issue time:

1. Paid and registered
2. Paid but not registered
3. Not paid
4. Course-level registration
5. Department summary
6. Faculty summary

## 4. The query engine

A query is a definition, never SQL: a source, conditions, columns, a sort or a grouping. `QueryEngine` fixes every source, every
field and its SQL expression, and every operator. A definition that names anything else is refused (QUERY_SOURCE, QUERY_FIELD,
QUERY_OPERATOR, QUERY_VALUE). Every value is parsed in Java for its type and then bound as a parameter. The statement runs in a
read-only transaction, so PostgreSQL itself refuses any write. It is held to the office's scope and read a page at a time, or up
to 50,000 rows for an export.

| Source | Reads |
|---|---|
| Students | the register and the classification, the academic status, contact |
| Course registrations | a session and semester's registration, its courses, units and carry-overs |
| Courses registered | each course on each registration |
| Payments | `reporting.payments`, the central finance's references and confirmations; for the offices that open individual payments |
| Examination readiness | the readiness for a session and semester |
| Hostel allocations, Clearance, GST and EPS permits | their own tables |
| Published results | the result system, for a programme, a department and level, or a student |

Natural-language querying was not built, because the portal had none to integrate.

## 5. Saved and shared reports, the log, the references

* `reporting.saved_query` keeps a definition (or a readiness report's filters), never SQL or a credential. Only the owner changes,
  shares or archives it; the database refuses anyone else. Nothing is deleted. It is shared with offices on the register, and each
  office reads it within its own scope.
* `reporting.query_log` is append-only. It records every run, export, print, save, share, archive and official reference issued,
  with who did it, as which office, the source, the filters, the scope, the number of rows, the reference and the format. The
  export log (V523) keeps its own line for every export as before.
* The Database Operations office, ICT and the auditors read everyone's log and the whole register of references. Every other office
  reads its own.

## 6. Data quality

`reporting.data_quality_rows` and `reporting.data_quality` report, for the scope:

* a programme that is not valid, or has no faculty or department;
* a missing or invalid entry session;
* an invalid level, or the level on record against the computed one (SP1 and SP2);
* in study with no matriculation number;
* a duplicate matriculation or JAMB number;
* an unclassified record;
* conflicting statuses;
* an award approved while the record is still kept in study;
* a student beyond the maximum academic period;
* for the session and semester, paid and not registered, and registered and not paid.

Each figure opens its records and says which office puts it right on which screen. Database Operations identifies, reports and
recommends; the change follows that office's own permissions and workflow.

## 7. Screens and menus

* **Database Operator:** a home with the students by programme type, the readiness of the semester, data quality and the quick
  actions. The menu has Student Classification (Student Query, Classification, Statistics, Spillover, Graduated), Examination
  Readiness, Student Reporting (School Fees Report, Payments Query, Student Records), Database Query, and Data Quality.
* **ICT:** a new Reports group with Examination Readiness, Database Query and Reports, and Data Quality. The duplicate Graduation
  Management line in ICT's menu was removed.
* **Examination Readiness** is also on the Academic Office's, the Registry's, Records', the examinations officers', the Deans', the
  Heads', the Bursary's, the Students Account Officer's, the VC's and the DVC's menus. An examinations officer reads the readiness
  without amounts.
* **Exports:** every report and list exports to Excel and PDF with S/N first (display only, never an id), names A to Z, payments
  newest first, the filters, the scope, the generation date and who generated it, and the reference.

## 8. On the live-shaped copy (19 Oct snapshot, 2025/2026 first semester)

| Read | Time |
|---|---|
| Every student's readiness (48,323 students) | 4.4 s |
| The summary by faculty | 4.8 s |
| A course | 5.3 s |
| `reporting.student_positions` alone | 0.9 s |
| The school-fees payers | 1.0 s |

The function was created in a transaction and rolled back, because the copy predates V578. On that copy the counts were 3,054 paid
and registered, 29,521 paid and not registered, 12,711 not paid, and 3,037 with no fee stated. Most 2025/2026 registrations were
made on the old portal. The screens read live, with the time they were read and a Refresh. Only the operator's home figures are
kept for a few minutes, with their time shown.

## 9. Tests

* `check.sql` V640, plus the office register count raised to 46 (with `verify.sql`). The block covers:
  * paid and registered, paid not registered, registered not paid, neither, a programme with no fee, a draft registration and a
    pending reference, each in its category, and a graduate in none;
  * a part payment paid by the card rule and not paid by the Bursary rule;
  * the card agreeing with `exam_card_state`;
  * the summary, the course and the course summary;
  * the references in turn;
  * the saved query guarded and the query log kept;
  * the office and an operator's scope;
  * data quality.
* `DatabaseOperationsIT` covers the same over the API: an operator over the University, ICT, an examinations officer without
  amounts, a lecturer refused, the package and its reference, the query engine (a field it does not offer, an unknown operator and
  an injected value refused or bound), saving and sharing, an operator held to another department, no writes, data quality, the
  home, Student Query and the query log.
* `lib/exam-readiness.test.ts` and `lib/dbops.test.ts`.
