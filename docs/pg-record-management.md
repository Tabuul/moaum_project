# Postgraduate record management (V715)

The University's master prompt of 30 October 2026, "PG APPLICANT & PG STUDENT FULL EDIT MANAGEMENT": the School of Postgraduate
Studies and the Director of ICT search, open and correct postgraduate applicant and student records from one place, under explicit
permissions, every change validated, confirmed with a reason, saved in one transaction, kept with its old and new value and read
everywhere the record is read. Nothing was rebuilt: each part of the record stays with the workflow that owns it.

## Where it is

| Dashboard | Menu | Page |
|---|---|---|
| School of Postgraduate Studies, PG Secretary | PG Management → Applicants, PG Students, Applicant & Student Search, PG Applicant Edit, PG Student Edit, Programme Structure, Change History | `/admissions/postgraduate/records`, `…/records/history` |
| Director of ICT | Academic → PG Students, PG Record Management, PG Applicant & Student Edit, PG Change History (beside Postgraduate Admissions) | the same |

The **search** (`t/pgrecords`) reads applicants and students in one list on the server (`admissions.pg_record_search`): by this
portal's application number or the old portal's, a matriculation, admission or JAMB number, an e-mail, a phone or a name; narrowed
by kind, faculty, department, programme, qualification, session and state. Each row opens to **View** (the application desk, or the
student's full record) or **Edit**. The list exports to Excel and PDF with S/N first. The search lives in the address.

## One record, two pages

A person is an applicant until admission, then a student. The same person is found either way, and is corrected where their record is:

- **An applicant** on the **postgraduate record page** (`/admissions/postgraduate/applications/{id}/edit`), new in V715.
- **A student** on the **student edit page** (V642, `/students/{id}/edit`), opened to the School and the Director of ICT for
  postgraduate students. It already holds the identity, admission, academic placement (the programme swap), status, matriculation
  (the correction), registration and carry-overs, graduation and finance of any student, each by its own workflow, with the change
  history. For a postgraduate student it gains a **Postgraduate stage** section: the application (linked to its record page) and the
  stage and cycle (linked to the stages and restarts desk, V651, which validates a stage against the programme structure and keeps
  every cycle). Student 360 shows **Edit** to these offices for a postgraduate student.

## The applicant's record page

Sections: basic information, contact information, application and programme, previous education, documents and referees, screening
and admission, fees, change history.

- **Corrected here** (`admissions.pg_applicant_edit_apply`): surname, other names, sex, date of birth, state of origin, LGA,
  nationality; e-mail, phone, contact address; programme (faculty → department → programme → specialisation; the entry level follows
  the programme's qualification), session; the first degree and research proposal title; the previous degrees as one list
  (`admissions.pg_prior_degrees_set`).
- **Before a save**: the changes are reviewed (each field, old and new), a reason of fifteen characters and three words is given
  (the student edit's rule), and a critical change (the e-mail the applicant signs in with, the programme, the session) is confirmed.
- **Checked on the server**: the permission for each field; the value's form; an e-mail no other applicant holds; a phone in its
  0… form (+234… accepted); a postgraduate programme in use; a running specialisation of the programme; a session on the calendar.
  All fields are written together, or none. The version read must be the record's own — a save on an older reading is refused
  (`PG_EDIT_STALE`) and the page asks for a refresh.
- **Not here**: the application number never changes; the state, the decisions, a return, the acceptance and the admission are the
  application desk's; the screening is the screening desk's; the fees are read only (a wrong payment is the Bursary's reallocation);
  documents are the applicant's to upload and the migration desk's to attach, never deleted here. An applicant on the register has
  their names, programme and session corrected on the student edit page (`PG_EDIT_ON_REGISTER`); the programme is corrected before the
  School's decision, afterwards by the programme swap once on the register (`PG_EDIT_DECIDED`); the session not after a fee was paid
  for it (`PG_EDIT_SESSION_PAID`).
- **Kept**: each change is a row on `admissions.pg_applicant_edit` under PG-EDIT/YYYY/NNNNNN — the field, the value before and
  after, the reason, the evidence, how serious, who and when — never updated or deleted; and one RECORD_CORRECTED event on the
  application's history. The page's change history lists the corrections beside the application's own events.

## Who may do what

`admissions.pg_edit_grant`. **EDIT_PG_RECORD** is the major permission and carries the ordinary ones: VIEW_PG_APPLICANTS,
VIEW_PG_STUDENTS, EDIT_PG_APPLICANT, EDIT_PG_STUDENT, EDIT_PG_BIODATA, EDIT_PG_ADMISSION, EDIT_PG_PROGRAMME,
EDIT_PG_ACADEMIC_PLACEMENT, EDIT_PG_STAGE, EDIT_PG_STATUS, EDIT_PG_DOCUMENTS, VIEW_PG_CHANGE_HISTORY, EXPORT_PG_RECORDS. The sensitive
ones — EDIT_PG_ADMISSION_DECISION, EDIT_PG_MATRICULATION, EDIT_PG_FINANCIAL_RECORD, EDIT_PG_PUBLISHED_RESULT, EDIT_PG_GRADUATION — are
never carried; each is its own workflow's and only granted apart.

| Office | Grant |
|---|---|
| School of Postgraduate Studies, PG Secretary, Director of ICT, Super Administrator | EDIT_PG_RECORD |
| School of Postgraduate Studies, Super Administrator | EDIT_PG_ADMISSION_DECISION (the School decides on its desk already) |
| Academic Office, Registrar, Deputy Registrar, Records, Platform administration, Audit, Deputy Audit | VIEW_PG_CHANGE_HISTORY |

On the student edit page, `people.student_edit_permissions(office, student)`: for a postgraduate student, an office holding
EDIT_PG_STUDENT holds the page's ordinary permissions (biodata, admission, placement, programme, session, status, classification,
carry-overs, registration, the history) — never the matriculation number (the correction's own office rule), graduation, the level
desk (a postgraduate's level is a stage, the stages desk's) or the registration override. The API checks the office against the
grants on every call, and the student's reach; the screen hides what the office may not do, the server refuses it regardless. A
Head of Department or Dean, who reads their own applications on the admissions desk, holds no grant on these pages.

The Director of ICT now reads the postgraduate applications desk and register too.

## Finance, results, matriculation

Not changed from these pages. Payment amounts, references, receipts, refunds, wallets and the ledger stay the Bursary's (the
reallocation, V649; the student edit page's "report financial issue" ticket). Published results stay the result correction's
(V700). The matriculation number stays the matriculation correction's (V579), the programme of a student the programme swap's
(V578/V633), graduation the reconciliation's (V638).

## Checked

- check.sql V715: the grants; one save correcting a surname, e-mail (confirmed), phone and programme (level and specialisation
  follow) under PG-EDIT references and one event; a thin reason, an unconfirmed critical change, another applicant's e-mail, the old
  reading, a programme once decided, the names of an applicant on the register and an office without the grant all refused; the
  previous degrees replaced as one change; the search by new number, old number, e-mail and matriculation number, never an
  undergraduate; the student edit page's permissions for the Director of ICT and the School on a postgraduate and an undergraduate.
- `PgRecordEditIT`: the same through the API — the School searches and corrects, a Head of Department is refused, the Director of
  ICT corrects a postgraduate student on the student edit page, the School is refused an undergraduate's, the latest corrections
  list both.
