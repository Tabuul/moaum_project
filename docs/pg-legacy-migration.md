# Old-portal postgraduate applicants migrated (V675)

The University's master prompt of 27 October 2026: postgraduate applicants of the old portal, and those it had admitted, are
brought into this portal's PG workflow. They are migrated, never made to apply again. Each keeps the old application number
beside this portal's own, and an applicant admitted on the old portal comes in admitted. Nobody, no admission, no student and no
payment is made twice, and the old portal stays traceable.

Nothing was rebuilt. A migrated applicant is an `admissions.pg_applicant` with one `admissions.pg_application`, numbered from
this portal's own series. Its state is the application's own state. A fee is an `admissions.pg_fee_reference`. Admission to the
register goes through `admissions.pg_admit`. A student already on the register, loaded by the old-portal PG students upload
(V203, which keeps the old number in `people.biodata` as `legacy_appno`), is linked and never made again.

## The desk

**Legacy Migration** at `/admissions/postgraduate/migration` (route `t/pgmigration`):

- **Migrate:** the Dean and the Secretary of the School, the Academic Office, and (V679, 27 October 2026) the Director of ICT and
  the Database Operators (`pgschool`, `pgsecretary`, `academic`, `ict`, `dbops`; `super`). A Database Operator works the desk only
  on a grant over the whole University; one held to a faculty, department or programme is refused (`SCOPE_UNIVERSITY`).
- **Read:** those offices, plus `registrar`, `dregistrar` and `bursar`.
- **Where:** the School's, the Secretary's and the Academic Office's Admissions menus; the Director of ICT's and the Database
  Operators' Academic menus (PG Legacy Migration), with the Legacy PG migration figures on their dashboards and a button among
  the Database Operators' quick actions; the Bursar's Finance menu (Old PG Application Fees).
- **Fees** paid on the old portal are verified by the Bursary or the PG Secretary only, never by the officer who uploaded them.
- **ICT Support** (`ictagent`) has no access.

| Step | What happens |
|---|---|
| Download the template | Two templates: PG applicants (not admitted on the old portal) and admitted PG applicants (with the admission, acceptance, screening and school fees). The columns come from `admissions.pg_migration_columns(kind)`: the PG application's own fields, nothing invented. Required columns are marked \*. Drop-downs and reference sheets hold this portal's faculties, departments, PG programmes, specialisations and sessions, and the old portal's status words. A Guide sheet has a made-up example. No database id is a column. |
| Upload | Excel (.xlsx) only, up to 20,000 rows. The file is read in the browser and matched to the template's keys by its headers (old exports' common headers too). Its SHA-256 is kept. The server opens a batch (`PG-MIG/YYYY/NNNNNN`) and takes the rows 500 at a time (`admissions.pg_migration_stage`). Only the template's keys are kept, as text, without control characters, at most 1,000 characters each. |
| Check (the dry run) | `admissions.pg_migration_check`, 1,000 rows a call. Every rule is applied and nothing is written but each row's verdict: READY, WARNING, DUPLICATE_IN_FILE, CONFLICT, REQUIRES_REVIEW or ERROR. Each row also gets its match (new applicant, existing applicant, already a student), its proposed action (Create new, Update existing, Reconcile, Link to the student), and every problem with what to correct. The preview's figures come from `admissions.pg_migration_summary`. |
| Correct | Download the error report (Excel: row, sheet row, applicant, old number, status, error type, message, suggested correction; a value that would run as a formula is written as text). Correct the file and upload it again as a new batch, or map an old programme and check again. |
| Import | `admissions.pg_migration_import`, 250 rows a call, with real counts. Each row is checked again as it is imported. A row that fails is undone alone and says why (FAILED); the rest go on. Finish marks the batch COMPLETED. |
| Set aside | ABANDONED, with a reason. What was imported stays. |

A batch and its rows are never deleted (a trigger refuses it). A row's values are written once.

## The rules

- **Numbers.** Every new application takes this portal's number, `PG/YY/NNNNNN`, from its own series, never the old number or a
  row count. The old number goes into `admissions.pg_legacy_application`, which is unique, searchable and holds the source and
  session. Both numbers find the applicant: Find an applicant (`admissions.pg_legacy_find`, which also searches by matriculation,
  admission or JAMB number, email, phone or name), the PG desk's list and export, the applicant portal, the applicant's sign-in
  and "Forgot password".
- **Matching.** An applicant is matched by:
  - the new application number;
  - the old number;
  - the email (the applicant's sign-in);
  - a matriculation number;
  - an old number a student already carries.

  If these keys point to different applications or students, the row is a CONFLICT. So is a name, programme, decision or old number that differs from the record. A possible same person under another email (the same surname with the same phone or birth date, or a PG student of the same name) is REQUIRES_REVIEW. It is imported once the file gives the number, or once the School confirms a new applicant with a reason (`admissions.pg_migration_row_new`). A repeat in the file (the same old number, or the same email for another number) is DUPLICATE_IN_FILE.
- **Programmes.** A programme is read, in this order:
  1. the School's mapping (`admissions.pg_legacy_programme`, with a reason; withdrawn, never deleted);
  2. this portal's code;
  3. the exact name among the running PG programmes, its faculty and department checked.

  A programme is never created, and never inferred from a number or a name. An old programme not found is PROGRAMME_NOT_MAPPED; once it is mapped, every later import reads the mapping. A merge (V574) carries the mapping to the programme kept.
- **States.** The old portal's words are read through `admissions.pg_legacy_status`. A word not in that table, such as Withdrawn or Cancelled, is held for review. An application only moves forward, never back:
  - Submitted, recommended or not admitted come in as they stood.
  - Admitted comes in as the School's offer, its decision dated and noted "On the old portal".
  - Accepted takes a verified acceptance payment.
  - On the register follows the old portal's screening.

  The applicant template refuses an admitted row, and the admitted template refuses one that is not.
- **Fees.**
  - An application or acceptance fee marked **Verified** is posted as a confirmed `pg_fee_reference` under its old reference, with channel "Old portal". An acceptance fee accepts the offer, as the gateway's confirmation does.
  - A fee only **Paid** is held (`admissions.pg_legacy_fee`, REQUIRES_REVIEW). The applicant is not asked to pay it again: `admissions.pg_new_fee_reference` refuses with PG_FEE_UNDER_REVIEW, and the portal says why.
  - The Bursary or the PG Secretary verifies or rejects a held fee (`admissions.pg_legacy_fee_decide`). The officer who uploaded it cannot (PGMIG_SAME_OFFICER). A verified acceptance applies the old portal's screening.
  - A fee already paid on this portal is held, never posted twice.
  - One old reference is one fee: a reference used elsewhere is a CONFLICT.
  - School fees are never posted here. They are listed for the Bursary's old-portal payments upload and read as on record once the payment is.
- **Screening.** A screening decided on the old portal is recorded with `source = OLD_PORTAL` (historical, completed). Cleared, it
  admits the applicant through `admissions.pg_admit`, once. If the session's policy requires screening and the old portal did not
  screen, the screening opens on this portal as for anyone (currently required).
- **Already a student.** The student is linked and the old number recorded on their biodata. They are never admitted, numbered or
  matriculated again, and their programme is never moved by a migration (V669: the register's placement stands; the programme swap
  corrects it).
- **Status checking.** An admission decided on the old portal is read without the checking fee (`admissions.pg_status_checking`).
  The applicant pays the acceptance fee on this portal only if the old portal did not take it.
- **Documents.** Each document named in the file becomes a reference in `admissions.pg_legacy_document`, reading
  MIGRATION_DOCUMENT_MISSING until **Attach file** stores the file as the application's `pg_document`: a PDF, or a JPEG or PNG for
  the passport, up to 8 MB, checked by its bytes. Documents are never public.
- **Notices.** The pipeline's own notices are silent inside a migration (`admissions.pg_tell_applicant`). Each migrated applicant
  is told once (`told_at`; event key `pg-migrated:<application>`), by email and SMS. The notice gives the new and old numbers and
  says how to sign in. A new applicant's stored password is a sealed cost-12 hash of a secret nobody holds, but since V709 they
  sign in on the old number, the new number or the email, with either number as the first password, and choose their own at once;
  an admitted one opens the student portal on the admission number first (docs/pg-migrated-applicant-first-sign-in.md). An
  applicant the migration links keeps their own password and is told to use "Forgot password" if they have not set one.

## Figures

The dashboard figures come from `admissions.pg_legacy_figures()`. They appear on the PG School and Secretary dashboards in the **Legacy PG migration** panel and at the top of the desk. Each one opens its records (`admissions.pg_legacy_list`):

- total legacy applicants;
- migrated;
- pending;
- admitted;
- accepted;
- screened;
- active PG students;
- duplicates, conflicts, requires review and errors (an old number not yet on this portal, at its latest row: `admissions.pg_migration_outstanding`);
- missing documents;
- unmapped programmes.

## Not in this build

- Old-portal document files are not fetched from the old portal; each is attached by hand.
- Old-portal sessions are normalised (2025/2026, 2025-2026, 2025/26). There is no table of other session names.
- The status words are seeded by the migration; there is no screen to add one.
- WITHDRAWN and CANCELLED have no state on this portal.
- A student's application and acceptance fees are not migrated: a linked student has no application here to post them to.

## Tests

- `check.sql` V675: both files, the dry run, the mapping, both numbers, the fees and their verification, the same file again, history kept.
- `PgMigrationIT`.
- `lib/pg-migration.test.ts`.

Timing on a scratch database (10,000 admitted rows): staging about 1.5 s, the check about 4–8 s for every 2,000 rows, and the import about 25–40 ms a row. Most of the import's time is the audit trail on every write.
