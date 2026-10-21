# Old Fees History: upload history (V609)

Finance → **Old Fees History** → **Upload history** lists every upload of old-portal fees in one place, and lets the desk query
them.

## What is listed

| How | What it is | States |
|---|---|---|
| Loaded by the Bursary | The Bursary's own file, loaded straight onto the records in parts of 500 rows | Loading, Stopped part-way, Loaded |
| For the Bursar's approval | The Students Account Officer's upload (V607), listed once it is sent | Waiting for the Bursar, Being loaded, Approved and loaded, Rejected, Withdrawn |
| Start over | A reset ("Start over" on the same page, V499) that deleted imported payments | Payments deleted |

For each upload the list shows:

- the reference (OFL-YYYY-NNNNN for the Bursary's loads and the start overs, OFU-… for the officer's uploads);
- when it began and ended, the file's name, and who made it from which office;
- the rows in the file, and the payments recorded and skipped (already on record, no such student, nothing to settle);
- the students and sessions, and the amount (recorded, deleted or, for the officer's upload, stated in the file).

## Who reads it

The Bursar, the Students Account Officer, the Audit and Deputy Audit offices, and super. Only the Bursary (bursar, super) loads a
file directly. The officer's file still waits for the Bursar's approval (V607).

## Querying

- **Filters:** from and to (Lagos dates), how, state, by (the person), office, session (an upload that covers it), and a reference,
  file name or person's name.
- **Paging:** ten uploads a page by default; Rows sets 10, 25, 50, 100 or All.
- **View all:** each figure (Loaded by the Bursary, For the Bursar's approval, Start over) lists every upload of its kind on one
  page. **Back to ten a page** returns.
- **Excel:** every upload the filters find, S/N first, under the University's header.
- **Opening an upload:** shows all its counts and its parts (the rows each covered, when, what each did, and any part sent again).
  - For a Bursary load, it also lists the payments it recorded that are still on record, ten a page, with Excel.
  - For a start over, it lists the payments it deleted.
  - An officer's upload is read under **Uploads for the Bursar's approval** on the same page.

## How a load is logged

- **Opening the upload.** The page opens an upload with the file's name and what the file states: its rows, students, sessions and
  the amount stated (`POST /api/v1/finance/legacy-fees/loads`).
- **Each part.** The page then sends each part with its first row (`POST /loads/{id}/rows`). The import is unchanged
  (`finance.import_legacy_payments`); what each part did is kept on the part and added to the upload.
- **A part sent again** after a lost answer is the same part: only what it newly records is added. The import never records a
  payment twice.
- **The old door** (`POST /api/v1/finance/legacy-fees`) still works and still logs. Its parts are gathered into one upload while they
  keep coming (two minutes apart at most), with no file named.
- **Who loads the parts.** Only the person who opened an upload loads its parts. The database refuses another officer
  (LEGACY_LOAD_OWN), and refuses an office other than the Bursary's (LEGACY_LOAD_OFFICE).
- **Start overs** are logged as they delete, by a trigger on `finance.legacy_payment_reset`: one entry for a person's run of batches.
- **Nothing is removed.** The history is never deleted (LEGACY_LOAD_KEPT).

The payments of an upload are read back exactly: the payments a part records carry the part's moment as `generated_at` (indexed
for Legacy payments).

## Before the history was kept

V609 rebuilt the earlier history from the records:

- **Uploads** are rebuilt from the payments on record. Each moment the import recorded payments is a part, and one person's parts
  two minutes apart or less are one upload. What a V607 approval loaded is left out.
- **Start overs** are rebuilt from what the reset kept: batches ten minutes apart or less are one start over.
- **Gaps:** a rebuilt upload has no file name, and no count of rows read or skipped, because those were not kept then.
- **An upload whose payments a start over deleted** before V609 shows only as that start over.

On the live-shaped copy (21 Oct 2026) the rebuild gives three entries:

- one start over on 16 Oct, 16:11–16:20, which deleted 284,058 payments;
- two loads on 16 Oct, 16:21–16:27 and 23:00–23:03, which recorded 190,767 and 73,379 payments. Together that is all 264,146 on
  record.

V609 takes about 2.5 s there.

## The page's other lists

Since this change every list on Old Fees History opens at ten rows a page, with Rows for 25, 50, 100 or All: overpaid, double
charges, payments not received, recorded under a code, doubles, Payment History left, and the officer's uploads. The
reconciliation with the fee setup pages on the server, ten students a page, and each of its figures has View all.

## Database and API

- **Tables:** `finance.legacy_fee_load` (one row an upload or start over), `finance.legacy_fee_load_part` (its parts, with their
  moments) and `finance.legacy_fee_load_student` (the students; derived, audit-exempt).
- **View:** `finance.legacy_upload_history` (every upload with V607's).
- **Functions:**
  - `finance.legacy_load_open(file, rows, students, sessions, amount)`
  - `finance.legacy_load_part(load, from_row, rows)`, which returns the import's counts with `load_ref`, `rows_loaded` and `resent`
  - `finance.legacy_load_payments(load)`
- **Endpoints:**
  - `GET /api/v1/finance/legacy-fees/history?from&to&kind&state&person&office&session&q&page&size` (size up to 100,000)
  - `GET /history/{id}` (with `part_list`)
  - `GET /history/{id}/payments?page&size` (size up to 200,000 for the Excel)
- **Tests:** `OldFeesUploadHistoryIT`; check.sql V609; `lib/old-fees-history` tests.
