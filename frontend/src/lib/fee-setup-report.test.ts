import { test } from "node:test";
import assert from "node:assert/strict";
import { feeGroups, feeSetupBodyHtml, feeSheetRows, sortFeeLines, type FeeLine } from "./fee-setup-report.ts";

const line = (o: Partial<FeeLine>): FeeLine => ({
  item: "School fees", amount: 1000, level: 100, entry_mode: "UTME", faculty_code: "SC", faculty_name: "SCIENCE", programme_code: null,
  programme_name: null, semester: 1, indigene: "INDIGENE", spillover: false, kind: "FEE", ord: 1, ...o,
});

const lines: FeeLine[] = [
  line({ faculty_code: "SC", faculty_name: "SCIENCE", semester: 2, level: 100, amount: 40 }),
  line({ faculty_code: "AR", faculty_name: "ARTS", semester: 2, level: 200, amount: 20 }),
  line({ faculty_code: "SC", faculty_name: "SCIENCE", semester: 1, level: 200, amount: 30 }),
  line({ faculty_code: "AR", faculty_name: "ARTS", semester: 1, level: 100, entry_mode: "TRANSFER", amount: 11 }),
  line({ faculty_code: "AR", faculty_name: "ARTS", semester: 1, level: 100, entry_mode: "UTME", indigene: "NON_INDIGENE", amount: 12 }),
  line({ faculty_code: "AR", faculty_name: "ARTS", semester: 1, level: 100, entry_mode: "UTME", amount: 10 }),
  line({ faculty_code: "AR", faculty_name: "ARTS", semester: 1, level: null, spillover: true, entry_mode: null, amount: 13 }),
  line({ faculty_code: "BAMS", faculty_name: "BASIC MEDICAL SCIENCES", programme_name: "MBBS", programme_code: "C00061", semester: 2, amount: 61 }),
  line({ faculty_code: "BAMS", faculty_name: "BASIC MEDICAL SCIENCES", programme_name: "B.Sc. HUMAN ANATOMY", programme_code: "C29132", semester: 1, amount: 51 }),
  line({ faculty_code: "BAMS", faculty_name: "BASIC MEDICAL SCIENCES", programme_name: "MBBS", programme_code: "C00061", semester: 1, amount: 60 }),
];

test("a faculty's first semester and second semester come together before the next faculty", () => {
  const order = sortFeeLines(lines).map((l) => `${l.faculty_code}${l.programme_code ? "/" + l.programme_code : ""} s${l.semester} ${l.amount}`);
  assert.deepEqual(order, [
    "AR s1 10", "AR s1 12", "AR s1 11", "AR s1 13", "AR s2 20",
    "BAMS/C29132 s1 51", "BAMS/C00061 s1 60", "BAMS/C00061 s2 61",
    "SC s1 30", "SC s2 40",
  ]);
});

test("within a semester: levels in order, spillover last; UTME before Transfer; indigene before non-indigene", () => {
  const ar1 = sortFeeLines(lines).filter((l) => l.faculty_code === "AR" && l.semester === 1);
  assert.deepEqual(ar1.map((l) => [l.spillover ? "SP" : l.level, l.entry_mode, l.indigene]), [
    [100, "UTME", "INDIGENE"], [100, "UTME", "NON_INDIGENE"], [100, "TRANSFER", "INDIGENE"], ["SP", null, "INDIGENE"],
  ]);
});

test("the sections: a faculty, or a programme within a faculty whose fees differ by programme", () => {
  assert.deepEqual(feeGroups(lines).map((g) => [g.faculty, g.programme, g.lines.length]), [
    ["Arts", null, 5], ["Basic Medical Sciences", "B.Sc. HUMAN ANATOMY", 1], ["Basic Medical Sciences", "MBBS", 2], ["Science", null, 2],
  ]);
});

test("the Excel rows lead with one serial number down the report", () => {
  const rows = feeSheetRows(lines);
  assert.deepEqual(rows.map((r) => r[0]), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.deepEqual(rows[0].slice(1), ["Arts", "All programmes", "First semester", "100 Level", "UTME", "Indigene", "School fees", 10]);
  assert.equal(rows[3][4], "Spillover");
});

test("the item is worded as the fees page words it", () => {
  const rows = feeSheetRows([line({ item: "School fees (semester 2)", semester: 2 }), line({ item: "Late payment fee" })]);
  assert.deepEqual(rows.map((r) => r[7]), ["Late payment fee", "School fees (Second Semester)"]);
});

test("the printed body: a heading for each section, the semesters in order inside it, the serial running on", () => {
  const html = feeSetupBodyHtml(lines);
  const at = (s: string) => html.indexOf(s);
  assert.ok(at(">Arts <") < at("Basic Medical Sciences") && at("Basic Medical Sciences") < at(">Science <"));
  const arts = html.slice(at(">Arts <"), at("Basic Medical Sciences"));
  assert.ok(arts.indexOf("First semester") < arts.indexOf("Second semester"));
  assert.ok(html.includes('<td class="sn">10</td>') && !html.includes('<td class="sn">11</td>'));
  assert.ok(!html.includes("Fee group"));
  assert.ok(feeSetupBodyHtml([]).includes("No fee line"));
});
