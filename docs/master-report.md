# Master university report (V650)

One report of the University's students, money, GST, EPS, examination cards and permits, read once and drawn three ways: the
screen, the PDF and the Excel workbook. The University's brief of 23 October 2026: "one central reporting engine → one authoritative
dataset → PDF + Excel + dashboard".

Nothing new holds the figures. The report reads the engines the portal already runs, so a figure in the report is the figure the
desk that owns it shows:

| What | Engine it reads |
|---|---|
| Who is counted, their faculty, department, programme, level, gender, type | `reporting.student_positions` (V257), through `reporting.exam_readiness` (V640) |
| School fees: obligation, paid, outstanding, standing | the charge engine, as examination readiness reads it (`finance.position`) |
| Course registration | the registration engine (University, College and postgraduate registers) |
| GST: owed, registered, paid | `finance.gst_population` (V468), `finance.gst_entitlement` |
| EPS | `finance.gst_eps_rows_all`; the GST fee where the Bursar's setting says it covers EPS |
| Examination card | `registration.exam_card_issue` and the card's own rule (V501, V567) |
| GST & EPS permit | `registration.gst_eps_permit` (V589), a revoked permit not counted |
| Transactions | `reporting.payments` (V409), the one ledger of payments |
| Data quality | `reporting.data_quality` (V640) |

## The engine (db/V650)

- `reporting.master_rows(session, semester, filters)` — one row per student of the scope: who they are and where they sit, their
  school fees, registration, GST, EPS, card and permit. Every list and every figure is drawn from these rows.
- `reporting.master_summary(session, semester, filters)` — the rows counted once with `GROUPING SETS` into every dimension: the whole,
  faculty, department, programme, programme and level, level, gender, programme type, study mode, faculty by gender. A faculty is
  the sum of its departments by construction.
- `reporting.master_payments(session, from, to, filters)` — the period's payments, each with its status: SUCCESSFUL, PENDING,
  FAILED (expired unpaid), REVERSED, REFUNDED (refund paid in full); its net amount after refunds; the day, in Lagos time.
  Revenue is successful payments only, net of refunds.
- `reporting.issue_report('MASTER', …)` gives the report an `RPT/YYYY/NNNNNN` reference on the official report register, GENERATING
  until written; `reporting.finish_report(reference, status, formats, rows)` marks it COMPLETED, FAILED or CANCELLED, by the person
  who issued it only. Every other kind of report keeps its `DBO/…` reference.

The filters are a JSON object the API builds; every value is checked against a fixed list or a pattern before it reaches the
database, and every value is bound, never written into SQL. The faculty, department and programme are first held to the office's
own scope on the server (`OfficeScope`), so a filter can narrow the scope but never widen it.

## The screen

On the menus of:

| Office | Where |
|---|---|
| Database Operator | Database Query, first |
| Director of ICT | Database Reports, first |
| Bursar, Registrar, Deputy Registrar, VC, DVC, Dean, Head of Department, Students Account Officer | after Examination Readiness |
| Internal Audit, Deputy Audit | Reports, first |
| Finance Controller, GST and EPS offices | Overview, after the payments report |

Each office sees only its own scope: a Dean their faculty, a Head of Department their department, the College's Finance Controller
the College's faculty, a scoped Database Operator their grant. The scope bar is locked to that scope (the bound the API returns with
the options), so it never offers a faculty the API would refuse.

- The scope bar (faculty, department, programme, level, session, semester) and filters: programme type, gender, study mode, centre,
  school-fee standing, registration, GST, EPS, card, permit; for transactions the period (today, yesterday, this week, this month,
  this semester, this session, this year, a custom range), purpose, status and channel.
- The tiles: every headline figure, each opening the students behind it.
- Drill-down: faculty → department → programme → level → students.
- Every section of the report as a table, with its chart where a chart helps (bar, pie, line; two line charts for transaction count
  and revenue, never two scales on one chart).
- Generate PDF, Generate Excel or both, with the steps shown as they happen: the reference issued, the data read, the charts, the
  PDF, the workbook, completed (or failed, recorded as FAILED).
- The report history: the master reports issued, with status, formats, rows, who and when. The Bursar and the auditing offices see
  everyone's; every other office its own.

## The PDF

Drawn in the browser from the package the API returns (`GET /api/v1/reports/master/package`) and saved with the browser's "Save as
PDF", like every report of the portal. A4 landscape. A cover page (crest, University, scope, title, session and semester, when, the
period, who, the reference); then on every page the heading with the crest and a footer with the reference, who and when, and
"Page X of Y"; the sections numbered in order, each table with S/N first and running on across pages, the charts beside their
tables; the definitions; the filters and the report's record last. A list in the PDF stops at 2,500 rows and says so; the Excel
holds every row.

## The Excel workbook

Streamed from the database by the API (`GET /api/v1/reports/master/workbook`), a few thousand rows at a time, so a whole session's
transactions never sit in memory. A cover sheet, then a sheet for every section and every list. On every sheet: the crest, the
University, the title and the facts (session, semester, scope, reference, when, who), the header row frozen, filters on, wide sheets
landscape. S/N is a number written by the workbook, never a database ID. Counts and money are numbers (`#,##0`, `#,##0.00`), dates
are dates (`dd/mm/yyyy`, `dd/mm/yyyy hh:mm`, Lagos time), and references, matriculation and JAMB numbers are text.

## Who reads what

| Office | Reads |
|---|---|
| Database Operator, Director of ICT, Academic Office, Registrar, Deputy Registrar, Records, Dean, Faculty Officer, Head of Department, Bursar, Students Account Officer, VC, DVC, Admin, Super Admin, Finance Controller, Internal Audit, Deputy Audit | every figure and amount, within their scope |
| GST and EPS offices | every figure; the GST and EPS fees and payments, no school-fee amount |
| Examinations offices | every figure, no amount; no transactions (`MASTER_MONEY`) |
| Any other office (a lecturer, a student) | nothing (403) |

The API enforces all of it: the reader list on every endpoint, the money by office (amounts removed before the answer leaves the
server), the scope on every query. The screen only follows.

## Reconciliation

The report checks itself and prints the result: the faculties and the levels each add up to the total; male, female and not stated
add up to the total; paid in full, part paid, not paid and no fee stated add up to the total; each faculty is the sum of its
departments, each department of its programmes, each programme of its levels; the revenue by purpose equals the period's revenue;
the transactions by status equal the period's transactions.

## What the figures mean

The Definitions section of every report says it in full. In short: "paid" is the school-fee obligation met in full; "no fee stated"
is never counted as not paid; "paid but not registered" uses the examination card's test (any verified school-fees payment); GST
registration and GST payment are counted apart; an examination card is "issued" when the student drew it from the portal (the
portal cannot see a printer); a permit is "printed" when its own record counts a print.

## Speed

On the live-shaped copy (48,325 students): the summary over the whole University 6–11 seconds; one session's transactions about
1.2 seconds. The page shows the scope bar and filters at once and streams the figures in when they are read.

## Checked by

- `db/check.sql` V650 (EXPECTED 478): two students of a made-up programme, one paid, registered, GST paid, card drawn and permit
  printed, one owing everything; every dimension, the departments the whole, the payments by status (successful, pending, failed,
  refunded) and revenue net of refunds, the RPT reference generating then completed, other kinds still DBO.
- `MasterReportIT`: the options, the summary and its reconciliation, the students behind a figure, the transactions by status, the
  reference, the PDF package with its lists, the workbook opened as a real workbook (sheets, frozen header, filter), the history,
  the query log; the Examinations Officer without amounts or transactions; the GST office with its own fee only; a Head of another
  department refused; the College's Finance Controller refused a programme outside the College and held to the College's faculty;
  a lecturer refused; another officer unable to finish someone else's report.
- `frontend/src/lib/master-report.test.ts`: filters, query, date presets, cell formats, tiles, charts.
