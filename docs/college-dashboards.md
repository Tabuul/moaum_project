# College of Health Sciences: the student dashboard and the Finance Controller (V603)

## The student's dashboard

The College's own student area (`/college/student`) is for MBBS students only. It shows the MBBS ladder, the Professional
examinations, postings and logbooks. Every other student of the College uses the University's student portal (`/student`), as
students of the main University do. This covers Nursing, Medical Laboratory Science, Radiography, Biochemistry, Anatomy,
Physiology and MSc Anatomy.

- **What decides it.** The programme on the student's record. A programme the College runs on its own machinery has a
  `college.programme_rule` row (V245: MB.BS, `C00061`); `college.runs_programme(code)` reads that row. No programme name or code
  is written in the code.
- **Where the student lands.** `people.student_dashboard(student)` answers:
  - `COLLEGE` for a programme the College runs, from 200 Level;
  - `UNIVERSITY` for every other student.

  MBBS at 100 Level registers on the University's form, as before. The API gives it as `dashboard` on `GET /api/v1/me`, and the
  login gate sends the student there.
- **Enforced on the server.** The College's student doors refuse any other student with `COLLEGE_NOT_MBBS`:
  - `GET /api/v1/college/my-record`, `/my-logbooks`, `/my-assessments` and `/my-postings`;
  - `POST /api/v1/college/register`.

  `college.register_level` refuses them in the database too. A student who opens `/college/student` by its address is sent to
  `/student`.
- **A programme change.** A programme swap or transfer changes the dashboard with the record. Nothing is stored.
- **The College's scope stays.** A College student who is not MBBS is still the College's in every College report, finance
  figure and desk.

Before V603 the gate read the faculty's college in the browser. On the live-shaped copy of 19 October 2026 it sent 3,359 College
students who are not MBBS (11 of them MSc Anatomy) to the MBBS area, beside the 653 MBBS students it is for.

## The Finance Controller

The office is `financecontroller` (V227), the Bursar within the College.

- **Home.** `/college/dashboard` shows the College's fees position for the session and its figures by programme, read from
  `GET /api/v1/college/payments?summary=true`, which returns the totals and programmes without the students. Below them are the
  College student statistics and the College financial analytics; both are analytics panels already held to the College.
  The Student Payment Report (`/college/payments`) with every student is a click away.
- **Why it did not open.** The home used to be the whole Student Payment Report, after reading the College's academic dashboard
  and throwing its answer away. On the live-shaped copy the page waited 10–18 s and sent 4.3 MB to the browser, every one of
  8,193 students, to show twenty. It now waits about 3 s and sends 48 KB.
- **Held to the College.** `OfficeScope` holds the office to the faculties of the college its live grant names (scope kind
  `college`), else the College of Health Sciences. The grant is read on the server, never from the request.
  - Every desk that reads the office's bound applies it: the student register, records, cohorts, clearance, results and others.
    Another faculty, department or programme named is refused (`SCOPE_COLLEGE`).
  - A student's record (`StudentReach`) opens for the College's students alone, graduated or not (403 otherwise).
  - The search finds the College's students alone.
  - The analytics (student statistics, Student Query, financial analytics, the admission funnel) were already held to the
    College (`AnalyticsScope`).
- **Not the University's money.** These desks read or act on the whole University and have no College scope, so they no longer
  admit the office:
  - old GST payments;
  - old NELFUND payments;
  - the old e-wallet;
  - registrations without fees;
  - the GST & EPS desk and its permits;
  - the CBT examination and invigilation reads;
  - the hostel finance desk.

  The Bursar and the Students Account Officer keep them as before.

## V606: the report, the College's own figures, the menu link, unconfirmed sign-in contacts

- **The Student Payment Report a page at a time.** `/college/payments` answers the students a page at a time (`page`, `size` up
  to 200), with `total`, the number the filters find. The totals and the figures by programme are always of the whole filtered
  set. `export=true` answers every student, and the Excel and the PDF read it when asked. The live-shaped copy has 8,193 College
  students; the whole list was 3.8 MB on every visit.
  - A programme's **Students** button now filters the report on the server.
  - **Students** chooses the current students (active, on probation, admitted: the default), the graduated, or both, so a
    graduated student's fees for a session stay on the report.
- **MBBS counted apart from the College.** The College's levels, examinations, years, postings and 100 Level rule are MBBS
  machinery. The overview and the dashboard count MBBS students (`college.runs_programme`), with the whole College beside them
  (`college_students`). The dashboard's fees by level and its clinical rotation count MBBS alone, as do the posting allocation
  list and the 100 Level list.
  - The fees by level read each MBBS student's cleared semesters (`finance.semester_cleared`) instead of two passes over every
    student of the University; the dashboard took 6 s for that on the live-shaped copy.
  - Three College functions are now held to the programmes the College runs:
    - `college.open_enrolment`;
    - `college.confirm_100`, the Board's 100 Level act. It would have promoted, or marked advised to withdraw, every College
      entrant at 100 Level by the MBBS rule.
    - `college.confirm_decisions`.

    No College year or decision was recorded yet on the live-shaped copy.
- **The MBBS student's menu.** A menu item may say when it shows (`MenuItem.when`), and the Shell shows it only to a person whose
  `flags` carry it. The student menu's **College (MBBS)** item (`s/college` → `/college/student`) carries `when: "college"`. An
  MBBS student's loader sets that flag from `collegeArea` on `GET /api/v1/me`, which is true for an MBBS student at every level.
- **Students We Cannot Reach.** A contact the sign-in help saved and nobody has confirmed reaches no notice (V599), so the list
  and its faculty figures (`helpdesk.reach_gaps`) count it as no contact until it is confirmed.

## Tests

`CollegeStudentDashboardIT`, `FinanceControllerScopeIT`, `CollegeMbbsCountsIT`, `SignInContactsIT` (the reach list), and
check.sql's V603 and V606 blocks.
