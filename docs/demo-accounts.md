# Demo accounts

Invented people, for walking the portal. `bash db/demo.sh` puts them on a database
(run it from the Railway shell of the **moaum-api** service, once; a second run
changes nothing). Nobody here is real: every surname is DEMO, every staff number is
MOAUM/DEMO/nnn, the matriculation numbers sit at 9901–9906 so a real matriculation run
never meets them, and the demo courses carry the DMO prefix.

**Password for every account:** `Demo password 2026`

Everybody signs in at the one door, `/login`, with the number below. The portal reads
the number, signs the person in on their own side, and opens their dashboard.

## Students — one at every level

| Level | Sign in with           | Programme                | Name                    |
|-------|------------------------|--------------------------|-------------------------|
| 100   | `MOAUM/MTC/26/9901`    | B.Sc. Computer Science   | DEMO, Ayima (100 Level)   |
| 200   | `MOAUM/ACC/25/9902`    | B.Sc. Accounting         | DEMO, Terhide (200 Level) |
| 300   | `MOAUM/MTC/24/9903`    | B.Sc. Computer Science   | DEMO, Mwuese (300 Level)  |
| 400   | `MOAUM/ECO/23/9904`    | B.Sc. Economics          | DEMO, Sesugh (400 Level)  |
| 500   | `MOAUM/LAW/22/9905`    | LL.B (Law)               | DEMO, Doosuur (500 Level) |
| 600   | `MOAUM/MED/21/9906`    | MBBS                     | DEMO, Aondona (600 Level) |
| 200   | `MOAUM/MED/25/9907`    | MBBS — College of Health Sciences | DEMO, Terkimbi (200 Level) — the College student login gate routes them to the College dashboard |
| 200   | `MOAUM/MED/26/9908`    | MBBS — College of Health Sciences | DEMO, Sewuese (200 Level) — entered this session: the later 200 Level cohort, for walking two College years side by side |

The year in the matriculation number is the entry year, counted back from the current
session: for 2026/2027 the numbers are as shown; for another session they shift with it.
Sign in as the 300-level student to see the results path from the student's end.

## Staff — one per office

| Office                    | Sign in with              | Scope                        |
|---------------------------|---------------------------|------------------------------|
| Lecturer                  | `demo.lecturer`           | Mathematics and Computer Science (MTC) |
| Head of Department        | `demo.hod`                | MTC                          |
| Examinations Officer      | `demo.exams`              | MTC                          |
| Faculty Examinations      | `demo.facultyexams`       | Faculty of Science           |
| Faculty Officer           | `demo.facultyofficer`     | Faculty of Science           |
| Dean                      | `demo.dean`               | Faculty of Science           |
| Exams and Records         | `demo.records`            | The University               |
| Academic Office           | `demo.academic`           | The University               |
| Deputy Registrar          | `demo.dregistrar`         | The University               |
| Registrar                 | `demo.registrar`          | The University               |
| Deputy Vice-Chancellor    | `demo.dvc`                | The University               |
| Vice-Chancellor           | `demo.vc`                 | The University               |
| Bursar                    | `demo.bursar`             | The University               |
| Internal Audit            | `demo.audit`              | The University               |
| Deputy Audit              | `demo.deputyaudit`        | The University               |
| Human Resources           | `demo.hrm`                | The University               |
| Housing                   | `demo.housing`            | The University               |
| Provost                   | `demo.provost`            | The University               |
| College Secretary         | `demo.collegesecretary`   | The University               |
| MBBS Coordinator, 200 Level | `demo.mbbscoordinator` | A College lecturer (Human Anatomy) holding the 200 Level coordinatorship: the level's score sheet, results and cohorts |
| PG School (Dean)          | `demo.pgschool`           | School of Postgraduate Studies |
| PG School (Secretary)     | `demo.pgsecretary`        | School of Postgraduate Studies |
| Librarian                 | `demo.library`            | The University               |
| Security                  | `demo.security`           | The University               |
| Student Services          | `demo.services`           | The University               |
| ICT Directorate           | `demo.ict`                | The platform                 |
| ICT Support Agent         | `demo.ictagent`           | The ICT support desk (V251): the queue, the tickets, the notes |
| University Administrator  | `demo.admin`              | The platform                 |
| Super Administrator       | `demo.super`              | The platform                 |

## Applicant

| Sign in with                    | Also accepted                |
|---------------------------------|------------------------------|
| `20269999DM` (JAMB number)      | `demo.applicant@example.com` |

The applicant is registered on a demo CAPS list for B.Sc. Computer Science with a
UTME aggregate of 250, at the first stage: the application fee is not yet confirmed.

## What is already set up for the walk

- Five demo courses at 300 level (DMO 311 to DMO 351), offered this session in the
  first semester, taught by `demo.lecturer` with `demo.exams` as second examiner.
- The 300-level student is registered and approved on all five.
- The examination session is open, so five score sheets sit at entry with the lecturer.
- A fee schedule for the session and the recommended clearance scheme are in force,
  so the student screens have something to say.

## The lecturer's results path, desk by desk

1. `demo.lecturer` — Score sheets → open DMO 311 → enter CA and examination marks for the
   candidate → Submit and attest.
2. `demo.exams` — Result desk → verify the sheet.
3. `demo.hod` — Result desk → approve at the Departmental Board.
4. `demo.facultyexams` — scrutiny; `demo.facultyofficer` — compilation; `demo.dean` — Faculty Board.
5. `demo.records` — Exams and Records.
6. `demo.registrar` — Senate: record the minute and release.
7. `MOAUM/MTC/24/9903` — Results: the published sheet, and the query window.

No two consecutive desks may be taken by one person, so the walk needs the accounts
above, not one account holding every office.
