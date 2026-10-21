# School-fee lines by spillover year (V613, 21 October 2026)

The Bursary asked for fee lines such as *400 Level (SP1) First semester*, *400 Level (SP1) Second semester*, *400 Level (SP2) First
semester*, *500 Level (SP1) First semester* and so on. A spillover line used to say only "Spillover": it reached every student in
spillover, whatever their programme's final level and whatever their spillover year.

## 1. The line

`finance.fee_schedule` gains `spill_year` — 1 (SP1), 2 (SP2) or 3 (SP3 and beyond) — beside the level and the semester; NULL means
any spillover year, which is what every line stated before V613 means. On a spillover line the **level now names the programme's
final level**: 400 for a four-year programme, 500 for a five-year one, NULL for every programme. No spillover line stated before
V613 carries a level, so nothing already stated changes meaning.

A student's spillover year is read on the basis the Bursary set (V571): by the cohort engine's count (SP1, SP2; the limit reached
reads as 3), or by the level (one year per level above the programme's final one). `finance.spill_year(student, level, programme,
status)` is the twin of `finance.spill`.

## 2. Where the year is read

Every matcher reads it, so what a student owes, whether a session is stated for them, the semester's due, the reports and the gap
sheet agree: `charges_of_as`, `fee_stated`, `due_for_semester`, `fee_sums` with `fee_profiles` (the year is part of a fee profile),
`fee_gaps` (a group of spillover students is one per year, and the report names the year and the final level) and `watch_fee_gaps`.
`fee_line_same_scope` keeps SP1 and SP2 apart, so the duplicate check, the copies between sessions and faculties and the upload
preview all carry the year.

## 3. Stating the lines

- **Fee Setup → State the item**: the Spillover field — no; any spillover year; SP1; SP2; SP3 — with the level then the programme's
  final level (the hint says so). The API door takes `spillover` and `spillYear` (`POST/PUT …/schedule`), refuses a year outside 1–3
  (`FEE_SPILL_YEAR`) and a second line of the same scope (`FEE_LINE_DUPLICATE`).
- **The fees-to-state sheet** (Fee watch): the Spillover cell reads "SP1", "SP2", "SP3" or "Yes"; the sheet the portal downloads
  for a spillover group names the year and puts the programme's final level in the Level cell. A `spillYear` column is read too.
- **The structure upload**: a band or row such as "400L/SP1" or "400 Level (SP1)" is that year's spillover line alone, at the final
  level the band names; "600L/SP" stays what it was (the level band plus the any-year spillover line).
- **Copies**: a session's lines copied into another, a faculty's into another, and the spillover lines copied on their own (V580)
  carry the year.

## 4. Reading them

The schedule shows "400 Level (SP1) · First semester" and a pill "Spillover SP1"; the copy preview and the upload preview say the
same; the gap report's level column reads "400 Level (SP2)" for a spillover group with no line for its year.

## 5. Tests

`FeeLinesIT`: the sheet states the four lines once; a student at 500 Level on a four-year programme (SP1 by the level) is charged
the SP1 line and the any-year line, one at 600 the SP2 line, one at 400 the level's own line; the form's spillover levy, its
duplicate and a bad year; the copy carries the year; the gap report names the year and the final level. `check.sql` V613 does the
same in the database alone. `lib/fee-copy` and `lib/fee-matrix` tests cover the words and the bands.
