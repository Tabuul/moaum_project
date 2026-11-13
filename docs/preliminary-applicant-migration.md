# Old-portal preliminary applicants migrated, their fees held for the Bursary, and the programme corrected by ICT (V737, V745, V755)

The University's master prompt of 12 November 2026 covers the two preliminary programmes: **Preliminary Technology & Industrial
Studies** (route `PRELIMINARY_TECHNOLOGY`) and **Preliminary Science** (route `PRELIMINARY_SCIENCE`). It asks for three things:

- the old portal's applicants are brought into each programme's dashboard from an Excel file;
- the application fees they paid there are kept, without counting them as paid until checked;
- an applicant's programme can be corrected from one preliminary programme to the other.

Nothing new was built beside the preliminary stack of V446 and V701. A migrated applicant is an ordinary preliminary applicant:

- an `admissions.candidate`, an `applicant_account`, an `application` with this portal's `APP/yy/nnnnnn` number, and a
  `prelim_review` on its route;
- biodata in `screening_answer`, results in `screening_olevel`, a fee in `fee_reference`.

The upload pipeline is the one the postgraduate migration (V675) proved: stage, check, preview, confirm, import.

The University's decisions of 12 November 2026:

1. **Numbers.** Every migrated applicant gets this portal's `APP/yy/nnnnnn` number. The old-portal number is kept beside it. It
   is unique, searchable on the desk, shown on the record, and it signs the applicant in.
2. **Admitted on the old portal.** These applicants come in admitted. The old portal's decision is published here, dated, and
   noted "Decided on the old portal", with no second review. "Accepted" comes in accepted, and "Not admitted" comes in not
   admitted, published the same way.
3. **Correction after a decision.** It is refused:
   - A decided but unpublished application (approved, not admitted or rejected) is first reopened by the Academic Office.
   - A published outcome stands, as the desk already rules (`PRELIM_PUBLISHED`), so it cannot be corrected.
4. **Who uploads.** The Director of ICT; ICT Support agents the Director authorises; the Academic Office; and Database Operators
   whose grant covers the whole University. Only the Bursary verifies old-portal fees, and never the officer who uploaded them.

The University's decisions on the independent review of V737 (12 November 2026, applied by V745):

5. **The Head of ICT Support has no right of office** to upload or to correct a programme. The head acts only through an agent
   posting carrying the capability, like any agent. `super` keeps its access, as on every other desk.
6. **Only the Director of ICT (or `super`) grants** either capability on a posting. The Head of ICT Support and Admin may keep or
   take away what a posting carries. They may never add either capability, bring back an ended posting that carries one, or keep
   it beyond the date the Director gave (403 `HELPDESK_GRANT_DIRECTOR`).
7. **The programme moves stay the fixed pair**, Technology ↔ Science. No setting is built.

## The desk

**Preliminary applicant data migration** at `/admissions/preliminary/migration` (route `t/prelimmigration`) has four tabs:
Upload, Import history, Old-portal fees and Programme corrections.

| Who | What |
|---|---|
| Director of ICT (`ict`), Academic Office (`academic`), Database Operators (`dbops`, University-wide grant only: `SCOPE_UNIVERSITY` otherwise), `super` | Upload, check, import, set a batch aside, confirm a possible duplicate as new |
| ICT Support agent (`ictagent`) and Head of ICT Support (`helpdeskhead`) | The same, but only with the posting capability **Upload old-portal preliminary applicants** (`MIGRATE_PRELIM_APPLICANTS`) on a University-wide posting. Without it, 403 `PRELIMMIG_CAPABILITY`. One holding only the programme-correction capability reads no batch and no fee; it finds applicants on the corrections tab |
| Bursary (`bursar`), `super` | Verify or refuse old-portal fees (never the uploader: `PRELIMMIG_SAME_OFFICER`) |
| Registry (`registrar`, `dregistrar`) | Read |
| Preliminary Science Office (`prelim`), Preliminary Vocational and Technical Education Office (`prelimtech`) | Read their own programme's batches, fees and corrections only (their search is limited to their programme before the 50-row page is cut) |

The Director of ICT grants the two capabilities on **Support Agents & Queues** (decision 6). They are not part of the baseline
every agent holds. The Head of ICT Support and Admin do not hold them by office either. The menus carry the desk for ict and dbops (Academic and Admissions), academic, super, helpdeskhead, ictagent, bursar ("Old
Preliminary Application Fees" opens the fees tab) and the two preliminary offices. The Director of ICT also gets the preliminary
desk (`/preliminary`) to read both programmes' dashboards.

## Upload, check, preview, import

Each programme has its own card, template and target. Before a file is used, the upload section's route is checked against the
programme configuration (`prelim_programme`). The "Programme" cell of the file is never trusted:

- a row naming the other preliminary programme is a CONFLICT (`PROGRAMME_MISMATCH`);
- a row whose target is one of the other programme's own targets is the same CONFLICT, whatever its Programme cell says (V745);
- a row naming neither is a warning.

The browser also refuses the other programme's template before anything is sent. The template's letterhead carries its
`Template code`, and a template downloaded before V745 is recognised by its title. A file in which every row's Programme names
the other programme is refused too. An upload for one programme can never write into the other.

| Step | What happens |
|---|---|
| Download the template | `PRELIMINARY_TECHNOLOGY_INDUSTRIAL_STUDIES_APPLICANTS_TEMPLATE.xlsx` or `PRELIMINARY_SCIENCES_APPLICANTS_TEMPLATE.xlsx`. See the template section below. |
| Select the file | Excel (.xlsx) only, up to 15 MB and 20,000 rows. The file is read in the browser. The headers are matched to the template's (case, spacing and common aliases tolerated; the S/N column dropped); unknown and missing required headers are reported. The file's SHA-256 is kept. The Applicants sheet is read when it has applicant rows; otherwise the one sheet that does is read. If several other sheets have applicant rows, the file is refused as ambiguous. After the upload, the batch shows which sheet was read, any other sheets with applicant rows that were not read, and the columns that were not read (in the same browser tab only). |
| Upload and validate | The server opens a batch (`PRELIM-MIG/YYYY/NNNNNN`). Only the officer who opened it sends its rows (`PRELIMMIG_NOT_YOURS`), so the uploader of every row is the officer the Bursary's rule excludes. It takes the rows 500 at a time (`admissions.prelim_migration_stage`) and checks them 1,000 at a time (`prelim_migration_check`). **Nothing is written to any applicant.** Each row gets a verdict (READY, WARNING, DUPLICATE_IN_FILE, CONFLICT, REQUIRES_REVIEW, ERROR), its match (new or existing applicant), its action (create, update, reconcile, none) and every problem with what to correct. Since V745 the rows of one file are compared with each other, as the import will compare them. A later row that may be the same person as an earlier one (same surname and phone; same surname, first name and birth date; or the same JAMB number) is held for review. A payment or gateway reference already given by another row is a duplicate (`FEE_REFERENCE_IN_FILE`). |
| Preview | The figures: total rows, valid, invalid, existing applicants, potential duplicates (those still to review), new applicants ready, fees to hold for the Bursary (the rows that will import with a fee held, not every row marked "Paid"), and programme conflicts. The rows can be filtered. **Download error report** (Excel) lists every row with a problem: row, sheet row, applicant, old number, status, error type, message and suggested correction. A possible duplicate can be confirmed as a new applicant with a reason. |
| Confirm the import | A dialog names the target programme, the new applicants, the existing applicants to update, the skipped rows and the invalid rows. For an import already begun, it counts only the rows still to do and shows what was already imported separately. Existing applicants are updated only if "fill in missing details of applicants already here" was ticked when the file went up, and then only empty fields are filled. Without it, an application made on this portal and found by its email only gets the old number kept beside it: no outcome is published, no state is moved and no fee is held. The check and the result say so (`OLD_NUMBER_ONLY`). The import runs only on an explicit confirmation. |
| Import | Each call takes up to 1,000 rows and commits them 10 at a time (V745), so the APPLICATION number series is held only briefly, never for a whole chunk. Each row is checked again as it goes in. A row that fails is undone on its own and reported FAILED with the reason, and the rest go on. Steps already committed stay. A row already done is never done twice. **Finish** marks the batch COMPLETED. A row the import skipped for review can still be confirmed as a new applicant afterwards, and is then imported at once (never in a batch that was set aside). |
| Import report | **Download import report** (Excel), from the batch panel and from Import history, lists every row (`/report?scope=all`): its result in words; this portal's application number, where the row created or matched one; the old-portal fee it brought (held for the Bursary, verified, or not verified); the note; and the problems. |
| Set aside | ABANDONED, with a reason. What was imported stays. |

A batch and its rows are never deleted (`PRELIMMIG_KEPT`), and a row's data is frozen once checked. The same file uploaded again
opens a new batch that names the earlier ones (`importedBefore`). Its rows come out UNCHANGED or SKIPPED, and no applicant, fee
or result is written twice.

## The template

The template is built from `admissions.prelim_migration_columns(route)`, which is also the only source for staging. Every column
has a destination in the database:

- **Applicant:** application number (the old portal's)\*, JAMB registration number, surname\*, first name\*, other names,
  gender\*, date of birth\*.
- **Contact:** email, phone\*, state of origin, LGA, nationality, residential address, next of kin (name, relationship, phone).
- **Programme:** programme (as the old portal named it), intended programme (Science: a target; Technology: the area),
  specialisation (Technology only), examination number.
- **O'Level:** one column group per sitting, up to the route's maximum (two): examination type (WAEC, NECO, NABTEB, other),
  qualification (the route's own list), year, examination number, and subjects and grades written as
  `Mathematics:B3; English Language:C4`, or one `Subject:Grade` per line in the cell. Two sittings are never forced into one
  cell. An O'Level heading with no sitting number (as the old portal's exports name them) is read as the first sitting.
- **Payment:** application date, payment reference, gateway transaction reference, application fee paid, payment date, payment
  status.
- **Status:** application status\*, admission status.

\* required. The workbook has:

- the **Applicants** sheet: a letterhead, then the headings (required ones marked \*), then 2,000 rows with drop-downs for gender,
  examination type, qualification, intended programme, specialisation, payment status, application status and admission status;
- **Instructions:** do not change the headings, the date formats accepted (DD/MM/YYYY, YYYY-MM-DD or an Excel date), multiple
  sittings, required and optional columns, the programme set by the upload section, and "Paid" checked by the Bursary. The date,
  phone, number and reference columns are formatted as Text, so pasting values only keeps a leading zero or a long number whole;
- **Sample Data**, clearly marked illustrative (made-up values);
- **Data Dictionary**;
- reference sheets: targets, specialisations, subjects and qualifications. The Targets sheet, the sample and the Data Dictionary
  use the same words as the drop-down: each target's requested name, beside the register's name for it.

The S/N column is for presentation only and never becomes a key. Every cell written from data goes through `safeCell`, so a value
starting `=`, `+`, `-` or `@` is never a formula.

## The rules of a row

- **Formats.**
  - Dates are read day first (DD/MM/YYYY), as ISO, or as an Excel serial.
  - The email and the phone (`0XXXXXXXXXX`) are checked, and so is the gender (Male/Female).
  - A JAMB number in the wrong shape is a warning. It is never compared with another row or applicant, so a placeholder never
    links two people. That covers "N/A" or "NIL" (V745), and since V755 also one digit repeated ("0000000000") and a phone
    number written in the JAMB column (`admissions.prelim_mig_jamb_key`, the one test every JAMB check reads).
  - A status word not in `admissions.prelim_legacy_status` is an error. The words are seeded; there is no screen to add one.
- **O'Level.**
  - Each subject must be on the list the preliminary form offers (`admissions.prelim_olevel_subjects()`); Maths, Agric and CRK are
    read.
  - Grades are A1–F9. An awaiting result is refused, as the route refuses it.
  - No more sittings than the route allows.
  - The same sitting (body, year, number) twice in the file is a duplicate. One already on another live application of the route
    and session is a conflict.
- **Matching.** Only strong identifiers match an applicant: this portal's application number, the old number
  (`prelim_legacy_application`), or the email. A name or a phone never merges anyone.
  - The old number and the email pointing to two applications is `IDENTITY_SPLIT`.
  - An applicant already on the other preliminary programme is `PROGRAMME_CONFLICT`: correct the programme instead.
  - An email used by a non-preliminary account is `EMAIL_ELSEWHERE`.
  - A record found by its email alone must agree on the first name and the sex. If either differs, the row is a conflict
    (`FIRST_NAME_DIFFERS`, `SEX_DIFFERS`) and is never imported onto that application (it may be a parent's or a twin's email).
  - A record matched by email that already carries a different old number is `LEGACY_NUMBER_DIFFERS`.
  - A record matched whose surname, date of birth or session differs is also a conflict.
  - A possible same person (the same surname, first name and date of birth, or the same surname and phone, on either programme) is
    REQUIRES_REVIEW until an officer confirms them as new with a reason (`prelim_migration_row_new`).
  - A JAMB number on another applicant is a warning, never a merge. A new applicant whose JAMB number an earlier migration
    brought is held for review.
  - An old number shaped like this portal's own APP number, or (since V755) its postgraduate (`PG/yy/nnnnnn`) or JUPEB
    (`JUPEB/APP/yyyy/nnnnnn`) numbers, is an error: it would one day be a new applicant's number, and that door is tried first
    at sign-in. One an account here already signs in with (a JAMB key) is a conflict (`LEGACY_NO_IS_PORTAL_NUMBER`): one
    identifier never opens two accounts. Since V745 this also covers a postgraduate applicant's old number and a JUPEB
    application's number or old reference, in both directions. Since V755 the postgraduate dry run shows such a row as a
    conflict, and the JUPEB old-portal preview marks it INVALID; the rest of the JUPEB file still imports. Should a later
    account take an old number as its JAMB key, the portal's own identifiers win at sign-in and at "Forgot password".
- **States.** Applications only move forward:
  - A new applicant comes in at the old portal's application status: not submitted, submitted or under review.
  - An old-portal admission comes in published: admitted, accepted or not admitted (decision 2).
  - An applicant already here is never moved back, never withdrawn by a file, and a published outcome here is never changed.
  - A status contradiction in the file is an error, for example admitted but never submitted.
- **Creating.** A new applicant is written as `prelim_register` writes one, without its window check and without its "application
  created" notice. The application date becomes the application's date. The account's first password is the application number
  (`SET_ON_FIRST_LOGIN`, with `must_change_password`). An applicant with no email gets a placeholder that is never written to.

## Fees and the Bursary's reconciliation

- **An Excel "Paid" is never proof.** Every old-portal application fee comes in **held** (`admissions.prelim_legacy_fee`,
  REQUIRES_REVIEW). It keeps the original amount, reference, gateway reference, payment date and the status the file gave.
- **While a fee is held, the applicant is not charged again.** A new application-fee reference is refused
  (`PRELIM_FEE_UNDER_REVIEW`). The applicant's page shows no pay button: it says the Bursary is verifying the old-portal payment,
  and the form opens once it is verified. The desk's "still needs" line says the same (`prelim_problems`, restated).
- **Missing or inconsistent payment information is flagged:**
  - a payment marked paid with no reference is held, and the Bursary must find the reference;
  - an amount that differs from the programme's stated fee is a warning;
  - a payment marked paid with no amount is still held, with the amount for the Bursary to confirm (`AMOUNT_MISSING`, a
    warning); an amount that cannot be read is an error;
  - a reference already on another fee, here or on the PG migration, is a conflict;
  - a reference or amount on a row marked unpaid is an error;
  - an applicant already paid here gets nothing held.
- **Verifying.** The Bursary verifies on the Old-portal fees tab (`prelim_legacy_fee_decide`). Only `bursar` or `super` may, and
  never the officer who uploaded the batch. A note is required. For a fee the file gave no amount for, the Bursary enters the
  amount the statement shows; if left blank, the fee is posted at the programme's stated fee. An amount other than the one the
  file gave is refused (`PRELIMMIG_FEE_AMOUNT`).
  - Verifying posts **one** application-fee record under the **old** reference, or under the reference the Bursary found when the
    file had none. A fee with no reference at all is never posted, and no reference is invented.
  - The record is posted on the paid date with channel "Old portal" and the portal's next receipt number. The application is then
    paid.
  - Refusing it lets the applicant pay here, and they are told. When the fee was meanwhile paid here, the old payment is not
    counted and the applicant is not told to pay; the Bursary sees that outcome.
  - A refused claim is not held again by a later file, with "fill in missing details" ticked or not. Only a row bringing another,
    non-blank reference is held again.
  - If the Bursary reverses the posting (the house reversal, V420), the old-portal fee returns to refused
    (`OLD_FEE_REVERSED` in the history), the application is unpaid again and the applicant may pay here.
- **Reconciliation figures** (`prelim_legacy_fee_figures`), per programme:
  - migrated applicants, with a reference, verified, unverified, rejected and no payment record;
  - duplicate references, counted from every batch whose old number is not yet migrated, whatever the batch's state;
  - for review: unverified, no payment record and duplicate references together;
  - amounts to confirm, and the amounts held and verified.

## Programme correction

**CHANGE APPLICATION PROGRAMME** sits on an applicant's record: on the preliminary desk's detail, and on the Programme
corrections tab, which finds an applicant by APP number, old number, name or email.

**Who.** The Director of ICT, `super`, and ICT Support agents (including the Head of ICT Support, decision 5) with the
capability **Change a preliminary applicant's programme** (`CHANGE_PRELIM_PROGRAMME`, University-wide). Without it the answer
is 403 `PRELIM_CHANGE_CAPABILITY`. The move is always to the other preliminary programme (decision 7).

**The dialog.** It shows the applicant, the application number (and the old one), the current and the new programme, the payment
status and original reference, and what will happen. A reason is required, then a confirmation.

**The checks** (`prelim_change_route_check`). The change is refused when:

- the application's outcome is published, or decided and not yet reopened;
- the application is withdrawn;
- the same person already applied for the new programme (`PRELIM_CHANGE_DUPLICATE`, naming the number);
- the new programme charges more than the fee paid or held (`PRELIM_CHANGE_FEE_SHORT`). A fee the Bursary settled or holds
  carries across to a programme that charges no more. Both programmes charge the same fee today.

**The change** (`prelim_change_route`) happens in one transaction, on the one application:

- the route moves, so the applicant leaves the old programme's dashboard, queue and figures and joins the new one's;
- `candidate.programme` takes the new name, so the applicant's dashboard and notices name it;
- the target and specialisation of the old programme are cleared, since the targets are per programme;
- an application already submitted goes back to the new programme's office:
  - with a correction request listing what the new programme needs and is missing (its target, a specialisation, a qualification
    it does not accept, a document);
  - if nothing is missing, as submitted;
  - an application the Office had already sent back stays with the applicant. The programme's note is added after the Office's
    own note, which still stands;
- the eligibility is worked out again under the new programme's rule, and a remediation decision the old programme's office
  recorded is set aside (kept in the history), so the new programme's own subjects to make up are asked for.

The application number, the old number, the biodata, the documents, the O'Level, the paid or held fee and its receipts, and the
history are untouched. No second record and no second fee are made, and an admission is never given or taken.

**The history.** Each correction is written once in `admissions.prelim_route_change` (`PRELIM-CHG/YYYY/NNNNNN`). The row holds the
previous and new programme, the target given up, the states before and after, the reason, the fee status and references, the
officer and the time. A refused attempt is kept too, with its refusal, so the Director of ICT reviews every correction and every
refusal. The applicant is told.

## Dashboards and figures

- **The preliminary desk** (`/preliminary`) adds these figures:
  - new this week, counted by the day of the application. For a migrated applicant that is the old portal's Application Date;
    if no file gave one, the applicant is not counted, and the import day is never used;
  - accepted;
  - outstanding requirements: an open application with the fee not settled, a required document missing or rejected, no
    target, the eligibility waiting, or a correction asked for;
  - fee held for the Bursary;
  - from the old portal.

  Its new filters are application number (the old one too), name, payment (paid, held, unpaid), applied from/to, admission status
  and old portal. The detail shows the old-portal facts, the fee hold, the outstanding requirements and the programme changes.
  The Excel and PDF reports carry the old application number, and show the payment as Paid, Held for the Bursary or Not paid.
- **The General Admissions dashboard** gains a **Preliminary programmes** panel with each programme's figures.
- **Counted once, in the right place.** The UTME figures (offers, accepted, on the register, the admission pipeline) no longer
  count preliminary or proficiency candidates, which have their own panel. A route is one column, so a corrected applicant is
  counted under one programme only.
- **Intake fix.** The register intake skips preliminary candidates. Bringing the admitted onto the register used to stop on the
  first published preliminary admission: such a candidate's programme is the route's name, which is no register programme.

## Sign-in

A migrated applicant signs in with the APP number, the old number, or the email (when the file gave one), on the ordinary sign-in
page: an identifier of no known shape, and a slash-shaped old number, also try the applicant door. Until they choose a password,
either number is the first password, and they must then choose their own. Once chosen, neither number signs them in.
"Forgot password" finds the account by the old number too. So does the ICT applicant password desk, which shows the old
number. A new password, whether set at the first sign-in, through "Forgot password" or changed later, may never be the APP
number or the old number, whatever its case or spacing (422 `AUTH_PASSWORD_IS_NUMBER`).

## Notices

These go through the central templates, on the account's real channels only, and never with a password:

- `<ROUTE>:MIGRATED`: once per applicant, with both numbers and how to sign in (the first password for a new account; for an
  account already here, its own password);
- `<ROUTE>:PAYMENT_SUCCESSFUL`: when the Bursary verifies the old-portal fee;
- `<ROUTE>:OLD_FEE_NOT_VERIFIED`: when it does not, and the fee is not already paid here;
- `<ROUTE>:PROGRAMME_CHANGED`: after a correction.

## Not in this build

- Old-portal documents (passport, results) are not fetched. The applicant uploads them as any applicant does.
- The status words are seeded by the migration, with no screen to add one.
- A correction to a programme with a higher fee is refused, not charged the difference (both programmes charge ₦5,000 today).
- A verified old-portal fee below the programme's fee settles it: the Bursary decides on the amount it verifies, and no balance is
  asked for.
- A published outcome cannot be corrected (decision 3), including an old-portal admission brought across. The upload's own check
  catches a wrong programme before the import.
- The programme moves are the fixed pair, with no setting (decision 7).
- The sheet a file was read from is kept in the browser tab that uploaded it, not on the batch. A batch reopened from Import
  history in another tab does not name its sheet.

## Tests

- `check.sql` V737 (one property, 565). It covers:
  - a Technology and a Science batch, and every verdict;
  - the import, the old number kept, and the held fee blocking a new reference;
  - the uploader refused and another Bursary officer verifying;
  - the same file again;
  - an old-portal admission;
  - the correction and its refusals;
  - an ICT Support agent without the capability refused;
  - batch deletion refused;
  - a refused fee not held again by a re-upload, a reversed posting refusing the fee, the first-password flag, the search limited
    to a programme, and an APP-shaped old number refused.
- `PrelimMigrationIT` (the API, both programmes' desks, the fee, the correction, sign-in on the old number with the password to
  change, a refused fee not held again, each office finding its own applicants, an agent with only the correction capability
  reading no batch, "Forgot password" by the old number).
- `lib/prelim-migration.test.ts` (template, reading back, formula-safe reports). V745 adds: the template code, results one
  subject per line, Text columns, the drop-down's words, unnumbered headings, the sheet read, the import report and the rows
  still to do.
- V745 in `check.sql`: two properties, V745 and V745 (2). They cover:
  - the rows of one file compared with each other, and a failed row leaving nothing;
  - an email match checked on first name and sex;
  - the old number only, without "fill in missing details";
  - PG and JUPEB old numbers held back in both directions;
  - a Paid row with no amount, and the held fee in the applicant's status;
  - duplicate references counted, and the Office's correction kept;
  - the day of the application, including when a later upload gives it;
  - the Head and a faculty's operator refused;
  - placeholder JAMB values, and a target of the other programme.
- V755 in `check.sql`: one property. It covers a JAMB cell of zeros or a phone number, old numbers shaped like this portal's PG
  and JUPEB numbers, the PG dry run and the JUPEB preview and upload naming a preliminary applicant's old number, and an
  application made here whose number is a preliminary old number (not refused).
- `PrelimMigrationFollowUpIT`:
  - the import a few rows at a time;
  - the document kept through a correction;
  - the old number never the password;
  - the Head acting only on a posting the Director grants, and never reviving or extending one;
  - siblings in one file.
