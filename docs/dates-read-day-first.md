# Dates are read day first (V717)

JAMB, the old portal and every Nigerian document write a date as day, month, year: `12-09-2003` is 12 September 2003.
On 1 November 2026 a Post-UTME applicant's JAMB slip said 12 September 2003 and the portal showed 9 December 2003.

## Why

Two readers took the figures month first.

- PostgreSQL's `DateStyle` was the default `ISO, MDY`, so every `text::date` in the schema without an explicit day-first
  pattern read an ambiguous day-month-year the American way. The old-portal student, biography and postgraduate imports
  cast the `dob` column that way.
- The frontend's `day()` formatter and the clearance forms' date helpers passed the text to JavaScript's `Date`, which
  reads `12-09-2003` month first too. The application form PDF, the five screening forms and the ages on the applicants'
  desk were affected. The applicant's own screens (`dob()` in `lib/applicant.ts`) and the candidate-data desk already read
  day first.

## What stands now

- `platform.read_date(text)` is the one reader: ISO with or without a time, day/month/year in figures with `-`, `/`, `.` or
  a space and a two- or four-digit year, the month in words on either side (`12 Sep 2003`, `September 12, 2003`), an Excel
  day number. Month first only when the figures allow nothing else (`09-13-2003`). `NULL` when it cannot be read.
- `platform.date_misread(text)` says what the old reading made of a day-month-year text (`12-09-2003` → 9 December 2003),
  `NULL` when the text was never ambiguous. A misread on record is recognised exactly, never guessed.
- `DateStyle` is `ISO, DMY` on the database, on every `app_*` role and on every PL/pgSQL function that casts a JSON text to
  a date. Output stays ISO. ISO text is unaffected. check.sql asserts the session's reading.
- The Biodata form's date of birth is read with `platform.read_date` on its way to the record (V553 restated).
- The Post-UTME door's date-of-birth factor compares dates, so `12/09/2003`, `12-09-2003` and `2003-09-12` all open it.
- `finance.legacy_date` (old-portal fees) reads a two-digit year day first (`12/09/23`); `admissions.pg_legacy_ts` (old-portal
  postgraduate research dates) reads every day-month-year cell through `platform.read_date`. The live imports
  (`people.import_students_rows`, `import_biography_rows`, `import_postgraduate`, `finance.import_paydirect`) carry the
  function-level `DateStyle`; check.sql asserts it.
- The API pins `SET datestyle = 'ISO, DMY'` on every pooled connection (`spring.datasource.hikari.connection-init-sql`), so the
  reading does not depend on the database's own default.
- The Post-UTME door and the result check say how to write the date: as on the JAMB slip, e.g. `12/09/2003`.
- The application form PDF prints the date of birth through `dob()`; the records migration desk's Students tab normalises the
  date of birth day first like its other tabs.
- `readDate`, `isoDay` and `ageAt` in `frontend/src/lib/format.ts` do the same in the browser; `day()`, `dob()`, the
  screening forms and the ages read through them.

## What the sweep found and left alone

A sweep of every text-to-date site (SQL, Java, frontend) confirmed the readers above and found nothing else that reorders a
day-month-year text. Query filters that cast an ISO `from`/`to` text (`:from::date`) take `<input type="date">` values and are
covered by the `DateStyle` default; private formatters on `DATE` columns (postgraduate, JUPEB, student modal) are fed ISO.

## The register put right

`people.jamb_dates_of_birth(session, commit, reason)` reads every student linked to a candidate with a JAMB date-of-birth
file against the record:

| action | meaning | commit writes |
|---|---|---|
| AGREES | the record holds JAMB's date | the Biodata form, when empty |
| FILLED | the record held none | JAMB's date to the record and the form |
| CORRECTED | the record held exactly the old misreading | JAMB's date to the record and the form |
| DIFFERS | another date stands | nothing; listed for the Registry |
| UNREADABLE | JAMB's text is no date | nothing; listed |

Every write is on the audit spine with the reason. The migration ran it once over every session. The Academic Office, the
Registry, Records, the Director of ICT and super may run it again from Admissions › Candidate data › Dates of birth
(`GET`/`POST …/candidate-data/dates-of-birth[/reconcile]`); anyone who reads the desk may preview it.
