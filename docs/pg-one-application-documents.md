# Postgraduate applications: one per person, documents tracked, the form printed (V694)

The University's word of 29 October 2026, on the Postgraduate applications desk:

> i want date of application to be displayed here, also a status field for completion of upload of document or still pending or
> not uploaded, the ones that paid for application but not uploaded yet should display, etc also some applicants applied twice or
> three times, they try to apply again, find a way to restrict them from applying twice … also give me a link to download their
> application form

## One application per person a session

An applicant account is one email, and it holds one application. A person who wanted to apply again opened a second account
under another email, and nothing tied the two together.

**The rule.** Two applications belong to the same person when **two of three** agree (`admissions.pg_same_person`):

* **The name.** Its words are compared in any order, ignoring case and punctuation (`pg_name_key`), so "Abata, Catherine Ema"
  is "EMA CATHERINE ABATA".
* **The date of birth.**
* **The phone.** 0…, 234… and +234… are read as one number (`pg_phone_key`).

A name alone never decides, because two people may share one.

**At the door.** `admissions.pg_apply` refuses a second application by the same person in the session, whatever the email
(**PG_APP_DUPLICATE**).
* The refusal names the email of the first application, masked (`c***a@example.com`), so the applicant can sign in with it
  and continue.
* It also says how to reset a forgotten password and that a change of programme goes to the School.
* Applications of a session are taken one at a time, so the same person applying twice at once cannot pass twice.
* The public form now asks for the date of birth (**PG_APPLY_DOB** at the API).
* A phone given as +234… is kept as 0….

**Applications made twice before V694** stay as they are; nothing is removed.
* The desk flags each of them as "Applied 2 times · also PG/26/000045".
* The **Applied more than once** filter lists them.
* Each application's page names the others: their programme, state, whether paid, and the email, masked.
* The School decides on one and declines the others with a note.
* Once one of them is paid, the others are issued no application-fee reference (**PG_APP_DUPLICATE_PAID**), so the fee is
  not paid twice.

The applications that came from the old portal (V675) are not refused at the door, since they never pass through it, but the
desk flags them by the same rule.

## Where the document upload stands

`admissions.pg_documents_required(level)` lists the documents the applicant is asked for, as the portal's upload list asks them:
* the passport photograph;
* the undergraduate certificate;
* the O'Level result;
* the birth certificate or declaration of age;
* the NYSC certificate;
* the LGA certificate;
* the higher degree, for an MPhil/PhD applicant only.

The change of name is asked only of someone whose name changed.

`admissions.pg_document_state(application)` reads each application as one of:

| State | On the desk | Meaning |
|---|---|---|
| COMPLETE | Complete | every document asked for is uploaded |
| PENDING | Pending · 3 of 6 | some are uploaded; the rest are named ("Missing: NYSC certificate, …") |
| NONE | Not uploaded | the fee is paid and nothing is uploaded |
| FEE_UNPAID | Fee unpaid | the upload opens once the application fee is confirmed |

The desk filters by each state on the server: **Documents complete**, **Documents pending**, **Paid, not uploaded** and **Fee
unpaid**, each with its count. The Excel holds the rows shown.

## On the desk

* **Applied.** Each row shows the day and time the application was made: the submission, or for a migrated application the
  old portal's date. The list can be ordered by it, newest first.
* **Documents.** A column shows where the upload stands, with what is missing.
* **Form.** Each row opens the applicant's **application form** as a PDF. This is the same document the applicant prints as
  their summary, headed APPLICATION FORM, with the passport photograph.
  * Its address is `/admissions/postgraduate/applications/{id}/form`.
  * The passport comes as a JPEG from `GET /api/v1/pg/applications/{id}/passport.jpg`.
  * A department or faculty office reaches only its own applications.
  * The application's page carries the same link beside the date it was made.
* **Excel.** It gains the date of application, the documents, the documents missing, the times applied and the other
  numbers.

## Tests

* `db/check.sql` V694.
* `PgOneApplicationIT`.
* `lib/pg-applications.test.ts`.
* PgFeeReferenceIT, PgLifecycleIT and PgLifecycleCompleteIT now apply as a person no run has made (`ItSupport.pgPerson`).
