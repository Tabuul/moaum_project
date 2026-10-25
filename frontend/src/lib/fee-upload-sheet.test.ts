import { test } from "node:test";
import assert from "node:assert/strict";
import { parseFeeFlat, type Grid } from "./fee-matrix.ts";
import { UPLOAD_SHEET_HEADERS, uploadSheetRows, type UploadLine } from "./fee-upload-sheet.ts";

// V653: the one-row-per-fee sheet reads a PG stage and fresh or returning, and a University-wide row the sheet says is one
test("a PG stage row and a fresh/returning row are read; an All-faculties row is University-wide; a row naming nothing is left out", () => {
  const grid: Grid = [
    ["Faculty", "Programme code", "Level", "PG stage", "Fresh or returning", "Semester", "Amount"],
    ["All faculties", "", "800", "800 B — Year 2", "", "1", "55000"],
    ["", "", "", "", "Fresh", "", "3000"],
    ["", "C90090", "", "900A", "", "1", "70000"],
    ["All faculties", "All programmes", "100", "", "", "", "1500"],
    ["", "", "100", "", "", "", "9"],
  ];
  assert.deepEqual(parseFeeFlat(grid), [
    { amount: "55000", level: "800", semester: "1", pgStage: "800 B — Year 2" },
    { amount: "3000", feeCategory: "Fresh" },
    { amount: "70000", programmeCode: "C90090", semester: "1", pgStage: "900A" },
    { amount: "1500", level: "100" },
  ]);
});

test("the session's lines downloaded as an upload sheet read back as the same lines; an archived line is left out", () => {
  const base = { programme_name: null, fee_group: null, semester: null, indigene: null, spillover: false, spill_year: null, kind: "FEE", pg_stage: null, pg_stage_label: null, fee_category: null };
  const lines: UploadLine[] = [
    { ...base, item: "School fees (semester 1)", amount: 91000, level: 100, entry_mode: "UTME", faculty_code: "SC", programme_code: null, semester: 1, indigene: "INDIGENE" },
    { ...base, item: "Tuition", amount: 55000, level: 800, entry_mode: null, faculty_code: null, programme_code: null, pg_stage: "800B", pg_stage_label: "800 B — Year 2", fee_category: "RETURNING" },
    { ...base, item: "Bench fee", amount: "3000.00", level: 800, entry_mode: null, faculty_code: "ES", programme_code: "C90090", programme_name: "M.Sc. Environmental Management", fee_category: "FRESH" },
    { ...base, item: "School fees (spillover SP2)", amount: 40000, level: 400, entry_mode: null, faculty_code: "SC", programme_code: "C00023", spillover: true, spill_year: 2 },
    { ...base, item: "Late payment fee", amount: 5000, level: null, entry_mode: null, faculty_code: null, programme_code: null, kind: "LATE_PAYMENT", fee_group: "UG" },
    { ...base, item: "Old line", amount: 1, level: 100, entry_mode: null, faculty_code: "SC", programme_code: null, status: "ARCHIVED" },
  ];
  const rows = uploadSheetRows(lines);
  assert.equal(rows.length, 5);
  const grid: Grid = [["School fees to upload"], ["Academic session", "2026/2027"], UPLOAD_SHEET_HEADERS, ...rows];
  const read = parseFeeFlat(grid);
  const byItem = Object.fromEntries(read.map((r) => [r.item, r]));
  assert.deepEqual(byItem["Tuition"], { amount: "55000", level: "800", item: "Tuition", pgStage: "800 B — Year 2" });
  assert.deepEqual(byItem["Bench fee"], { amount: "3000", faculty: "ES", programmeCode: "C90090", level: "800", item: "Bench fee", feeCategory: "Fresh" });
  assert.deepEqual(byItem["School fees (semester 1)"], { amount: "91000", faculty: "SC", level: "100", entryMode: "UTME", semester: "1", indigene: "Indigene", item: "School fees (semester 1)" });
  assert.deepEqual(byItem["School fees (spillover SP2)"], { amount: "40000", faculty: "SC", programmeCode: "C00023", level: "400", item: "School fees (spillover SP2)", spillover: "true", spillYear: "2" });
  assert.deepEqual(byItem["Late payment fee"], { amount: "5000", item: "Late payment fee", kind: "Late payment", feeGroup: "UG" });
  assert.equal(byItem["Old line"], undefined);
});
