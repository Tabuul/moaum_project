import { test } from "node:test";
import assert from "node:assert/strict";
import { structureRowsFromDocx, looksLikeCode } from "./structure-docx.ts";
import type { DocxBlock } from "./docx.ts";

const p = (text: string): DocxBlock => ({ kind: "p", text });
const t = (rows: string[][]): DocxBlock => ({ kind: "table", rows });

test("the template's table under its level and semester headings", () => {
  const rows = structureRowsFromDocx([
    p("100 Level"), p("First Semester"),
    t([["Course Code", "Course Title", "Units", "Status", "LH", "PH"], ["CSC 101", "Introduction to Computing", "3", "C", "45", ""], ["", "Total", "3", "", "", ""]]),
  ]);
  assert.deepEqual(rows, [{ code: "CSC 101", title: "Introduction to Computing", units: "3", status: "C", level: 100, semester: 1, lh: "45", ph: "" }]);
});

test("a leading S/N column is passed over, by its heading and without one", () => {
  const withHead = structureRowsFromDocx([p("200 Level Second Semester"),
    t([["S/N", "Course Code", "Course Title", "Units", "Status"], ["1", "CSC 202", "Data Structures", "3", "C"], ["2", "CSC 204", "Logic", "2", "E"]])]);
  assert.deepEqual(withHead.map((r) => [r.code, r.units, r.status, r.level, r.semester]), [["CSC 202", "3", "C", 200, 2], ["CSC 204", "2", "E", 200, 2]]);
  const noHead = structureRowsFromDocx([t([["1", "GST 111", "Use of English", "2", "C"]])]);
  assert.deepEqual(noHead.map((r) => [r.code, r.title, r.units, r.status]), [["GST 111", "Use of English", "2", "C"]]);
});

test("columns in another order are read by their headings", () => {
  const rows = structureRowsFromDocx([t([["Course Title", "Course Code", "Status", "Credit Units"], ["Calculus", "MTH 101", "C", "3"]])]);
  assert.deepEqual(rows.map((r) => [r.code, r.title, r.units, r.status]), [["MTH 101", "Calculus", "3", "C"]]);
});

test("a table continued on the next page keeps the columns of the table before it", () => {
  const rows = structureRowsFromDocx([
    t([["S/N", "Course Code", "Course Title", "Status", "Units"], ["1", "BSU-SOC-101", "Introduction to Sociology", "C", "3"]]),
    t([["2", "BSU-SOC-103", "Social Problems", "E", "2"]]),
  ]);
  assert.deepEqual(rows.map((r) => [r.code, r.units, r.status]), [["BSU-SOC-101", "3", "C"], ["BSU-SOC-103", "2", "E"]]);
});

test("course codes as departments write them", () => {
  for (const c of ["CSC 201", "GST111", "BSU-SOC-101", "MOAU-CHM 101", "EPS 302A"]) assert.ok(looksLikeCode(c), c);
  for (const c of ["1", "Total", "Course Code", "Introduction"]) assert.ok(!looksLikeCode(c), c);
});
