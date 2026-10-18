import { test } from "node:test";
import assert from "node:assert/strict";
import { blockRows, parseFeeFlat, parseFeeMatrix, readBand, readFeeBlocks, readFeeWorkbook, suggestTargets, type Grid, type Target } from "./fee-matrix.ts";

/** the College of Health Sciences' PAGE 1 as the .xlsx reader gives it: strings, blank cells "", empty rows left out */
const head = ["", "", "", "", "", "", "", "", "", "", "", "", ""];
const ind = (n: number) => ["", ...Array.from({ length: n }, (_, i) => (i % 2 ? "Non-Indigene" : "Indigenes"))];
const page1: Grid = [
  ["COLLEGE OF HEALTH SCIENCES ", ...head.slice(1)],
  ["BENUE STATE UNIVERSITY, MAKURDI"],
  [" FEES STRUCTURE FOR 2025/2026 ACADEMIC SESSION"],
  ["MBBS", " 100L/200DE", "", "200L", "", "300L", "", "400L", "", "500L", "", "600L/SP", ""],
  ind(12),
  ["SEMESTER", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦"],
  ["1ST", "218657.116125", "272306.152125", "133200", "184260", "133200", "184260", "133200", "184260", "68520", "101700", "65700", "97500"],
  ["2ND", "145771.41075", "181537.43475", "88800", "122840", "88800", "122840", "88800", "122840", "45680", "67800", "43800", "65000"],
  ["TOTAL", "364428.526875", "453843.586875", "222000", "307100", "222000", "307100", "222000", "307100", "114200", "169500", "109500", "162500"],
  ["NURSING", " 100L/200DE", "", "200L", "", "300L", "", "400L", "", "500L/SP", ""],
  ind(10),
  ["", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦", "₦"],
  ["1ST", "199755.352125", "253445.842125", "115200", "166320", "115200", "166320", "68520", "101700", "68520", "101700"],
  ["2ND", "133170.23475", "168963.89475", "76800", "110880", "76800", "110880", "45680", "67800", "45680", "67800"],
  ["TOTAL", "332925.586875", "422409.736875", "192000", "277200", "192000", "277200", "114200", "169500", "114200", "169500"],
  ["Prepared By:", "", "Ikoamo Barnabas T."],
];
/** an itemised breakdown sheet of the same workbook: no block in it */
const breakdown: Grid = [
  ["PROPOSED BREAKDOWN OF  MBBS UNDERGRADUATE SCHOOL FEES FOR  2025/2026 SESSION"],
  ["S/NO", "DETAILS", " 2025/2026 sesssion"],
  ["", "", "INDIGENES", "NON-INDIGENES"],
  ["1", "REGISTARTION FEE", "116550", "174465.06"],
  ["2", "ACCREDITATION LEVY", "300000", "300000"],
  ["", "TOTAL", "364428.526875", "453843.586875"],
];

test("a band head: the level, Direct Entry's level and spillover; an amount or a session is not a band", () => {
  assert.deepEqual(readBand(" 100L/200DE", 1), { col: 1, head: "100L/200DE", level: 100, de: 200, spill: false });
  assert.deepEqual(readBand("600L/SP", 11), { col: 11, head: "600L/SP", level: 600, de: null, spill: true });
  assert.equal(readBand("200L", 3)?.level, 200);
  assert.equal(readBand("Spillover", 3)?.spill, true);
  assert.equal(readBand(" 2025/2026 sesssion", 2), null);
  assert.equal(readBand("300000", 2), null);
  assert.equal(readBand("Indigenes", 2), null);
});

test("the College's blocks: every band read with its entry modes, 72 lines for MBBS and 60 for Nursing", () => {
  const { blocks, mismatches } = readFeeBlocks(page1);
  assert.deepEqual(blocks.map((b) => [b.label, b.lines.length]), [["MBBS", 72], ["NURSING", 60]]);
  assert.equal(mismatches.length, 0);
  const mbbs = blocks[0].lines;
  const at = (level: number | null, mode: string | null, sem: number, ind: string, spill = false) =>
    mbbs.filter((l) => l.level === level && l.entryMode === mode && l.semester === sem && l.indigene === ind && l.spillover === spill).map((l) => l.amount);
  // "100L/200DE": level 100 for UTME and Transfer, level 200 for Direct Entry, the sheet's amounts to the kobo
  assert.deepEqual(at(100, "UTME", 1, "INDIGENE"), [218657.12]);
  // the second semester is the TOTAL less the first, so the two make it to the kobo (the sheet's own 2ND rounds to .43)
  assert.deepEqual(at(100, "TRANSFER", 2, "NON_INDIGENE"), [181537.44]);
  assert.deepEqual(at(200, "DIRECT_ENTRY", 1, "INDIGENE"), [218657.12]);
  // the 200L band: UTME and Transfer only, so a Direct Entry 200 Level student is charged once
  assert.deepEqual(at(200, "UTME", 1, "INDIGENE"), [133200]);
  assert.equal(mbbs.filter((l) => l.level === 200 && l.entryMode === "DIRECT_ENTRY").length, 4);
  // from 300 up, all three; "/SP" also the spillover line, no level and no entry mode
  assert.deepEqual(at(600, "DIRECT_ENTRY", 2, "NON_INDIGENE"), [65000]);
  assert.deepEqual(at(null, null, 1, "INDIGENE", true), [65700]);
  // the two semesters make the TOTAL to the kobo
  assert.equal(Math.round((at(100, "UTME", 1, "NON_INDIGENE")[0] + at(100, "UTME", 2, "NON_INDIGENE")[0]) * 100), 45384359);
});

test("a TOTAL the semesters do not make: the TOTAL stands, split by the sheet's own share, and it is told", () => {
  const grid: Grid = [
    ["ANATOMY", "100L/200DE", "", "400L/SP", ""],
    ind(4),
    ["1ST", "60000", "90000", "50000", "80000"],
    ["2ND", "40000", "60000", "30000", "50000"],
    ["TOTAL", "110000", "150000", "80000", "130000"],
  ];
  const { blocks, mismatches } = readFeeBlocks(grid);
  assert.equal(mismatches.length, 1);
  assert.deepEqual(mismatches[0], { label: "ANATOMY", band: "100L/200DE", indigene: "INDIGENE", first: 60000, second: 40000, total: 110000, used: [66000, 44000] });
  const amounts = blocks[0].lines.filter((l) => l.level === 100 && l.entryMode === "UTME" && l.indigene === "INDIGENE").map((l) => [l.semester, l.amount]);
  assert.deepEqual(amounts, [[1, 66000], [2, 44000]]);
});

test("a block's rows name the programme it was matched to; the spillover row has no level and no entry mode", () => {
  const { blocks } = readFeeBlocks(page1);
  const rows = blockRows(blocks[0], { programmeCode: "C00061" });
  assert.equal(rows.length, 72);
  assert.ok(rows.every((r) => r.programmeCode === "C00061" && !r.faculty));
  const sp = rows.filter((r) => r.spillover === "true");
  assert.equal(sp.length, 4);
  assert.ok(sp.every((r) => r.level === undefined && r.entryMode === undefined));
  assert.deepEqual(rows[0], { amount: "218657.12", indigene: "INDIGENE", programmeCode: "C00061", level: "100", entryMode: "UTME", semester: "1" });
});

test("the titles matched to the register: the College's names, the College's Biochemistry over Science's", () => {
  const T = (code: string, name: string, faculty_code: string): Target => ({ kind: "PROGRAMME", code, name, faculty_code });
  const targets: Target[] = [
    T("C00061", "MBBS", "BAMS"), T("C35147", "BACHELOR OF NURSING SCIENCES", "BAMS"), T("C29132", "B.Sc. HUMAN ANATOMY", "BAMS"),
    T("C18115", "B.Sc. HUMAN PHYSIOLOGY", "BAMS"), T("C49411", "B.Sc. RADIOGRAPHY AND RADIATION SCIENCE", "BAMS"),
    T("C64548", "B.Sc. BIOCHEMISTRY", "BAMS"), T("C00031", "B.Sc. BIOCHEMISTRY", "SC"),
    T("C49412", "BACHELOR OF MEDICAL LABORATORY SCIENCE (BMLS)", "BAMS"), T("C00023", "B.Sc. COMPUTER SCIENCE", "SC"),
    { kind: "FACULTY", code: "AR", name: "Arts" }, { kind: "FACULTY", code: "BAMS", name: "Basic and Applied Medical Sciences" },
  ];
  const got = suggestTargets(["MBBS", "NURSING", "ANATOMY", "PHYSIOLOGY", "RADIOGRAPHY SCIENCES", "BIOCHEM", "MEDICAL LAB SC. TECH", "ARTS", "VETERINARY MEDICINE"], targets);
  assert.deepEqual(got.map((t) => t?.code ?? null), ["C00061", "C35147", "C29132", "C18115", "C49411", "C64548", "C49412", "AR", null]);
});

test("the faculty cross-tab states its entry modes, so Direct Entry at 200 is one line, not two", () => {
  const grid: Grid = [
    ["FACULTY/SEMESTER", "100L/200DE", "", "200L", "", "SPILLOVER", ""],
    ["", "Indigene", "Non-indigene", "Indigene", "Non-indigene", "Indigene", "Non-indigene"],
    ["ARTS"],
    ["1st Semester", "50000", "70000", "40000", "60000", "30000", "45000"],
    ["2nd Semester", "30000", "50000", "20000", "40000", "", ""],
    ["Total", "80000", "120000", "60000", "100000", "30000", "45000"],
  ];
  const rows = parseFeeMatrix(grid);
  const de200 = rows.filter((r) => r.level === "200" && r.entryMode === "DIRECT_ENTRY" && r.semester === "1" && r.indigene === "INDIGENE");
  assert.deepEqual(de200.map((r) => r.amount), ["50000.00"]);
  assert.ok(rows.every((r) => r.entryMode || r.spillover === "true"));
  assert.deepEqual(rows.filter((r) => r.spillover === "true").map((r) => [r.semester, r.indigene, r.amount]), [["1", "INDIGENE", "30000.00"], ["1", "NON_INDIGENE", "45000.00"]]);
});

test("the workbook's layout: the College's pages are blocks, a breakdown sheet is none, a one-row-per-fee table is flat", () => {
  const read = readFeeWorkbook([page1, breakdown]);
  assert.equal(read.layout, "BLOCKS");
  assert.equal(read.layout === "BLOCKS" ? read.blocks.length : 0, 2);
  assert.equal(readFeeWorkbook([breakdown]).layout, "NONE");
  const flat: Grid = [
    ["Faculty", "Faculty code", "Programme code", "Programme", "Level", "Entry mode", "Semester", "Indigene", "Spillover", "Students", "Amount"],
    ["Basic Medical Sciences", "BAMS", "C00061", "MBBS", "100", "UTME", "1", "Indigene", "No", "", "218657.12"],
    ["Basic Medical Sciences", "BAMS", "C00061", "MBBS", "", "", "1", "Indigene", "Yes", "", "65700"],
  ];
  const f = readFeeWorkbook([flat]);
  assert.equal(f.layout, "FLAT");
  // the faculty's code is read where the sheet gives it, so the name the sheet spells its own way does not matter
  assert.deepEqual(parseFeeFlat(flat)[1], { amount: "65700", faculty: "BAMS", programmeCode: "C00061", semester: "1", indigene: "Indigene", spillover: "true" });
});
