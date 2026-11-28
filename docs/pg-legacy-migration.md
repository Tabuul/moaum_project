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
- **Fees** paid on the old portal: a fee the old portal marked Verified is posted as it comes; an application fee only marked Paid is cleared by the portal itself when it can check it (V783); every other fee is verified by the Bursary or the PG Secretary only, never by the officer who uploaded it.
- **Application fee payments in the Old Fees History layout** (V786, 24 November 2026): the Old-portal fees tab takes the Bursary's payment sheet as it is and clears each PG application fee by the applicant's application number (see "Application fee payments uploaded in the Old Fees History layout" below). Seven offices upload: `pgschool`, `pgsecretary`, `academic`, `ict`, `dbops`, `super` and `bursar`, so the Bursar, who does not migrate, uploads payments; a Database Operator uploads only on a grant over the whole University, as everywhere on this desk. Any other office is refused (`PGFEES_OFFICE`).
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

  An old number a preliminary applicant brought from the old portal signs in with is a CONFLICT too
  (`LEGACY_NO_IS_PORTAL_NUMBER`, V755): one number never opens two accounts, and the postgraduate door is tried first at sign-in.
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
  - Since V712, an applicant admitted on the old portal is put on the register at the import, whatever is left of the acceptance
    fee and screening here (a not-cleared screening decided on this portal stands), to pay school fees; the old portal's payments
    are uploaded as history (docs/pg-admitted-on-old-portal-to-register.md).

  The applicant template refuses an admitted row, and the admitted template refuses one that is not.
- **Fees.**
  - An application or acceptance fee marked **Verified** is posted as a confirmed `pg_fee_reference` under its old reference, with channel "Old portal". An acceptance fee accepts the offer, as the gateway's confirmation does.
  - **Since V783 (the University's word of 24 November 2026), an APPLICATION fee only marked Paid clears on its own** at the import, and the ones already held were cleared once when V783 was applied (`admissions.pg_legacy_fees_autoclear_held`, with the email). `admissions.pg_legacy_fee_autoclear` posts it exactly as a verification would (`admissions.pg_mig_post_fee`: a confirmed `pg_fee_reference`, channel "Old portal", the application's fee read as paid) when `admissions.pg_application_fee_hold` — one predicate, read by the import, the check and the desk's list — finds nothing against it: the old portal's own status word says it was paid (Paid, Successful, Success, Completed, Yes — the template offers Paid; a status of Not verified, Unverified, Pending or Awaiting verification or Requires review is held); the amount reaches the application fee of the application's session (`admissions.pg_fee_rule`; a part payment is held); the old reference is no other fee's (a postgraduate fee reference or another old-portal fee, V675's clash), was not rejected by an officer on another application, and is on none of the portal's other ledgers (an applicant's fee reference or receipt, a preliminary applicant's old-portal fee, an inter-university transfer fee, a JUPEB fee, a student's payment or receipt); the applicant has not paid the application fee on another application of theirs in the session (V694's two of name, date of birth and phone, looked for through the date of birth and phone first so an import chunk stays fast; the check reads it for a new applicant from the row's own name, date of birth and phone); and no application fee is confirmed on this portal for the application already. The row reads decided by "system" with the University's word as its note, the application gets an OLD_PORTAL_FEE_CLEARED event, the import's row note says "application fee cleared on its own" (or "application fee held: <why>"), the applicant's own once-only migration notice says the fee is recorded, and a fee cleared after the import emails the applicant once (the event key an officer's verification uses, so never twice). The check warns (FEE_UNDER_REVIEW) only of a fee that will be held, and says why. An acceptance fee is never cleared on its own, and a fee marked Verified is posted exactly as before (no amount or reference test: the uploader's word). No posted postgraduate fee has a reversal door, as before.
  - **Since V786, an application fee payment can also come from a sheet in the Old Fees History layout** (below): it is recorded as an old-portal application fee stated Paid and goes through the same clearing, so the rules above are the rules of that upload too.
  - A fee that fails a check, or an acceptance fee only **Paid**, is held (`admissions.pg_legacy_fee`, REQUIRES_REVIEW), the desk's Old-portal fees tab giving the reason of an application fee (`hold_reason`). The applicant is not asked to pay it again: `admissions.pg_new_fee_reference` refuses with PG_FEE_UNDER_REVIEW, and the portal says why.
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

## Application fee payments uploaded in the Old Fees History layout (V786)

The University's word of 24 November 2026, with a sheet in the Bursary's Old Fees History layout whose rows are PG applicants' application fee payments: "I want to upload those payments in this format to solve my issue". The desk's **Old-portal fees** tab takes that sheet as it is (`admissions.pg_old_fees_upload`; `POST /api/v1/pg/migration/fees/payments`).

The Old Fees History upload cannot do it. It finds the payer among the students (by matriculation number, an old one a correction replaced, or the admission number), and a PG applicant is not a student, so it holds the applicant's row as "no student" and clears nothing. V783's clearing was reached only through the migration template, whose required columns (the old application number, the names, the email, the session, the programme) a payment sheet does not carry.

**Who uploads.** The seven offices named under "The desk": `pgschool`, `pgsecretary`, `academic`, `ict`, `dbops`, `super` and `bursar`. The database refuses any other (`PGFEES_OFFICE`).

**The sheet.** The Old Fees History layout, read in the browser by the reader the Bursary's upload uses (`legacyFeeRows`, `frontend/src/lib/legacy-fees.ts`), so a heading is found by its words: Matriculation Number, Session, Semester, Level, Amount, Purpose/Payment Item, Payment Date, Channel, Reference. One row is one payment. A blank row, or a heading row repeated in the sheet, is passed over and not counted.

| Column | What this upload reads |
|---|---|
| Matriculation Number (the first column) | The applicant's PG application number on this portal (`PG/YY/NNNNNN`) or the number the old portal gave the application (`admissions.pg_legacy_application`), capitals or not. An old number that more than one application carries is not guessed between: write this portal's number. |
| Session | Informational. The fee is judged against the application's own session, never the file's; when the two differ the row's note says "the file says 2026/2027, the application is in 2025/2026" and the row is read all the same. As in the Old Fees History upload, the reader takes a row only when its session is written like 2026/2027. |
| Semester, Level, Channel | Read with the sheet and not used. A cleared fee carries the channel "Old portal". |
| Amount | Required. Digits and a decimal point are read; the naira sign and commas are ignored. |
| Purpose/Payment Item | Must read **PG APPLICATION**: an item that says application and does not say acceptance. When the Purpose is empty the Note column is read in its place. |
| Payment Date | Recorded as the fee's date of payment when it can be read. |
| Reference | Required. The old payment reference (an Interswitch reference, for example). It is kept as the fee's old reference, tells one payment from another and is checked against the portal's other ledgers. |

**Check, then Upload.**

- A **Check** (`apply` false) does everything an Upload does inside a unit of work the database then undoes: no batch is made, no fee is recorded, no event is written and no email is sent. It answers each row as the Upload will, so the officer sees what will clear and what will be held before anything is written. The screen runs the Check as soon as the file is chosen.
- The screen offers **Upload and clear** only after a Check of the same file, and only when the Check found a payment that will clear or be held. A tick box, on unless it is cleared, tells each applicant whose fee clears that it is recorded (`notify`).
- A file is an Excel workbook (`.xlsx`) of at most 15 MB and 2,000 payments; a longer one is split. A row with something written in it but no number, or no session written like 2026/2027, is left out and named on the screen.
- An **Upload** (`apply` true) writes one batch of kind FEES, COMPLETED, in the PG migration history with the other batches: its reference `PG-MIG/YYYY/NNNNNN`, the file name, the file's SHA-256 when it is sent, the number of rows sent, and the uploader's office. The batch stages no migration rows: the payments are its old-portal fees. Each payment that is neither refused nor already recorded is recorded as an old-portal application fee (`admissions.pg_legacy_fee`, kind APPLICATION, stated Paid, in the application's own session, with the date paid) and the clearing is run on it.
- The report counts the rows read, cleared, held, already recorded and refused, and lists each row: the sheet's row number, the number, the application number and the applicant, the reference, the amount, the result, the reason and the note.

**The result of each row.** A row that fails several tests is answered by the first of them, in this order: the item, the reference, the amount, the number.

| Result | What it means |
|---|---|
| CLEARED | The fee is posted, exactly as V783 posts a Paid application fee: a confirmed fee reference with the channel "Old portal", the application reads its fee as paid and the applicant is not asked for it. The row reads decided by "system" and the application's trail says OLD_PORTAL_FEE_CLEARED. |
| HELD | The payment is recorded but not posted. It waits on the Old-portal fees tab, with its reason, for the Bursary or the PG Secretary to verify or reject; the officer who uploaded it cannot (`PGMIG_SAME_OFFICER`). The applicant is not asked to pay it again meanwhile (`PG_FEE_UNDER_REVIEW`). |
| ALREADY | The same payment (this reference, on this application) is already recorded and posted. Nothing is written. |
| NOT_APPLICATION_FEE | The item is not a PG application fee: it names an acceptance fee, school fees or anything else, or the row names no item. Written nowhere. |
| NO_REFERENCE | The row has no payment reference. Written nowhere. |
| NO_AMOUNT | The row has no amount, or none above zero. Written nowhere. |
| NOT_FOUND | No PG application has the number, neither on this portal nor on the old portal; or more than one application has that old number. Written nowhere. |
| IS_STUDENT | No application has the number but a student does. A student's payments are recorded by the Bursary's Old Fees History upload. Written nowhere. |
| CONFLICT | The reference is already recorded for another applicant. Written nowhere. |
| REJECTED | An officer rejected this payment on this very application. An upload does not put it back. Written nowhere. |

The last seven are refused and counted together as refused. The screen says the ten in words, in the order above: Clears (Cleared once uploaded), Held for an officer (Held), Already recorded, Not an application fee, No reference, No amount, Number not found, A student's number, Reference used for another applicant and Rejected before.

**The rules.**

- **One predicate.** The upload records each payment as Paid and calls the same `admissions.pg_legacy_fee_autoclear` that V783's import calls, which reads `admissions.pg_application_fee_hold`. A payment is therefore HELD, with that predicate's reason, when its amount is below the application fee of the application's session (or the session states none); when its reference is another fee's, is on another ledger of the portal (an applicant's fee reference, a preliminary applicant's old-portal fee, an inter-university transfer fee, a JUPEB fee, a student's payment) or was rejected by an officer on another application; when the applicant has paid the application fee on another application of theirs in the session; or when an application fee is already confirmed on this portal for the application. The old portal's status test cannot hold an uploaded payment, because the upload records every payment as Paid.
- **A rejection stands.** A payment an officer rejected on an application is REJECTED when the same sheet brings it for that application, and is not recorded again. One rejected on another application and brought for this one is HELD with that reason.
- **One reference, one applicant.** A reference recorded for another applicant is a CONFLICT and nothing is written. A reference repeated for the same application, in one file or in two, is recorded once.
- **The same file again.** A payment already posted is ALREADY and changes nothing. One held before is not recorded a second time; its clearing is tried once more, because what held it (the session's application fee, a reference on another ledger, another application of the applicant) may have changed, and it is then CLEARED or HELD again.
- **A student's number.** The sheet's first column is read among PG applications only. A student's number is refused as IS_STUDENT: the Bursary's Old Fees History upload records students' payments, and it finds the payer among the students only, which is why a PG applicant's row is held there as "no student".
- **The applicant is told.** An applicant whose fee clears is emailed once, with the notice an officer's verification sends ("Your application fee paid on the old portal is recorded", its event key `pg-fee-verified:` followed by the fee's id), so never twice. A held payment is told when an officer verifies it. A Check sends nothing, and the email is left out when the tick box is cleared (`notify` false).
- **Not changed.** V783's rules, the PG migration template and the Old Fees History upload.

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
- `check.sql` V783 (12 properties): a Paid application fee clearing at the import and in one pass over the held ones, every reason a fee is held, the clearing silent and the import's flag put back, the check and the import agreeing, an officer's verification still working; `PgMigrationIT` (a Paid fee clears on its own, a short one is held with its reason and the Bursar verifies it).
- `PgMigrationIT`.
- `lib/pg-migration.test.ts`.

Timing on a scratch database (10,000 admitted rows): staging about 1.5 s, the check about 4–8 s for every 2,000 rows, and the import about 25–40 ms a row. Most of the import's time is the audit trail on every write.
