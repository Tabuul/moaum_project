import { test } from "node:test";
import assert from "node:assert/strict";
import { evidenceProblem, kindWord, narrow, normalNo, partsLine, prepareBlock, type Place } from "./matric-correction.ts";

test("a number is read as the register keeps it, and its parts in reading order", () => {
  assert.equal(normalNo(" moau/sc/csc/25/ 12939 "), "MOAU/SC/CSC/25/12939");
  assert.equal(partsLine({ university: "MOAU", faculty: "SC", programme: "CSC", year: "25", sequence: 12939 }), "MOAU · SC · CSC · 25 · 12939");
  assert.equal(partsLine({ university: "MOAU", faculty: "MD", programme: null, year: "25", sequence: 7 }), "MOAU · MD · 25 · 7");
  assert.equal(kindWord("FACULTY_CODE"), "Wrong faculty code");
});

test("the faculty narrows the departments and the department the programmes", () => {
  const places: Place[] = [
    { code: "C1", name: "B.Sc. Computer Science", deptCode: "CSC", department: "Computer Science", facultyCode: "SC", faculty: "Science", category: "UNDER GRADUATE" },
    { code: "C2", name: "B.Sc. Physics", deptCode: "PHY", department: "Physics", facultyCode: "SC", faculty: "Science", category: "UNDER GRADUATE" },
    { code: "C3", name: "B.Sc. Business Administration", deptCode: "BUS", department: "Business Administration", facultyCode: "AD", faculty: "Administration", category: "UNDER GRADUATE" },
  ];
  const all = narrow(places, "", "");
  assert.deepEqual(all.faculties.map((f) => f.code), ["AD", "SC"]);
  const sc = narrow(places, "SC", "");
  assert.deepEqual(sc.departments.map((d) => d.code), ["CSC", "PHY"]);
  assert.deepEqual(narrow(places, "SC", "PHY").programmes.map((p) => p.code), ["C2"]);
});

test("a correction is prepared only when the check finds no problem, the kind is said and the reason is given", () => {
  assert.match(String(prepareBlock(null, "", "")), /wait for the check/);
  assert.equal(prepareBlock({ ok: false, problems: [{ code: "TAKEN", message: "MATRICULATION NUMBER ALREADY ASSIGNED: x" }], points: [] }, "DATA_ENTRY", "a reason long enough"),
    "MATRICULATION NUMBER ALREADY ASSIGNED: x");
  assert.match(String(prepareBlock({ ok: true, problems: [], points: [] }, "", "a reason long enough")), /what was wrong/);
  assert.match(String(prepareBlock({ ok: true, problems: [], points: [] }, "DATA_ENTRY", "short")), /ten characters/);
  assert.equal(prepareBlock({ ok: true, problems: [], points: [] }, "DATA_ENTRY", "Imported with the wrong faculty code"), null);
});

test("evidence is a PDF, JPEG or PNG up to 5 MB", () => {
  assert.equal(evidenceProblem({ name: "memo.pdf", size: 1000, type: "application/pdf" }), null);
  assert.match(String(evidenceProblem({ name: "memo.docx", size: 1000, type: "application/msword" })), /PDF, JPEG or PNG/);
  assert.match(String(evidenceProblem({ name: "big.png", size: 6 * 1024 * 1024, type: "image/png" })), /5 MB/);
});
