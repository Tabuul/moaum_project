# Export log (V523, V529)

Who took which report out of the portal, when, from which office, with which filters and how many rows.

## What is recorded

Every report handed to a signed-in person through the portal's export engine (`frontend/src/lib/exportbrand.ts`:
`brandedXlsx` for Excel, `brandedPrint` for print / PDF), every table's own Print button (`components/proto/DTable.tsx`, print or Save as PDF),
the results downloads (`lib/results.ts`) and the student and staff registers (`app/reports/RegisterDesk.tsx`). Each export is one row of `platform.export_log`:

| Column | What it holds |
|---|---|
| `at` | When the export was made |
| `person_id`, `office` | The person and the office they acted in, from the request's audit context (the token and the active office), never from what the screen says |
| `report` | The document's title |
| `format` | `XLSX` (an Excel workbook), `PRINT` (print / Save as PDF), or `PDF` / `CSV` for a file the portal's server builds (V529) |
| `row_count` | The rows in the document |
| `filters` | The labelled block above the table (Session, Faculty…), the subtitle and the screen's own query |
| `screen` | The page it was made on |
| `serial` | The serial printed on the document, so a copy found anywhere is traced to who made it |

The log is append-only: an update or a delete is refused (`EXPORT_LOG_APPEND_ONLY`). Each row is also on the audit spine
(`audit.entries`, subject type `platform.export_log`), which is hash-chained.

Since V529 the reports the portal's own server builds are recorded too: the paid Post-UTME applicants PDF, the JUPEB
examination-number list, a lecturer's score sheet and marked sheet (Excel, CSV or PDF), a kept report copy sent by e-mail
(`lib/export-log-server.ts` in the route handlers) and the CCE list load report (CSV, recorded by the API itself).

## Unusual exports (V529)

An export is unusual when it is large (at least `large_rows` rows, 1,000 by default) or when the same person makes
`burst_count` exports (15) within `burst_minutes` (60). `platform.export_watch` holds the three values and whether the watch is
on; Internal Audit or super set them on the Export Log screen, and each change is on the audit spine.

As an unusual export is recorded, the holders of `audit` and `deputyaudit` are told by e-mail and on the portal
(`EXPORT_UNUSUAL`): who, which office, the report, the format, the rows, the serial and why. A large export is told once; a burst
is told once, as the person reaches the limit. The person who made the export is never told, and nothing is stopped. If telling
fails, the export stays on the log (the trigger catches the failure). The list marks unusual exports and can show only them.

## How it is sent

The screen sends `POST /api/v1/exports` in the background (a keepalive request) as the document is made. It never holds up or
stops the export: if the record cannot be sent, the download still goes ahead. The database function `platform.log_export`
writes the row for the request's person and office and refuses an export with nobody signed in (`EXPORT_LOG_NO_ACTOR`) or in
another format (`EXPORT_LOG_FORMAT`).

## Who reads it

Internal Audit (`audit`), the Deputy Director of Audit (`deputyaudit`) and super, on **Export Log** (`/audit/exports`):
filters by date range, office, format and words in the report, person, number, screen or serial; exportable to Excel (that
export is itself on the log).

## Not covered

- Single-person documents (a receipt, an admission letter, an examination card, a student's own broadsheet or summary) are not
  reports and are not logged.
- Upload templates downloaded through the plain workbook builder are not logged.
- ICT Support viewing a student's portal read-only (V521) cannot write anything, the log included, so an export made in that view
  is not recorded.
