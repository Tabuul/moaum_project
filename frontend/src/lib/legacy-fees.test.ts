import { test } from "node:test";
import assert from "node:assert/strict";
import { legacyFeeColumns, legacyFeeKind, legacyFeeRows } from "./legacy-fees.ts";

test("the old portal's export is read column by column, the payment item carried as the purpose", () => {
  const grid = [
    ["Matriculation Number", "Session", "Semester", "Level", "Amount", "Purpose/Payment Item", "Payment Date", "Channel", "Reference"],
    ["MOAU/SS/POL/25/84706", "2025/2026", "Session", 100, 2000, "GST FEES", 46064, "Interswitch", "2019470000000000"],
    ["BSU/SS/SOC/19/55565", "2024/2025", "Second", 400, 38800, "SCHOOL FEES", 45682, "Old Record", "2019470000000000XXX"],
    ["BSU/SS/SOC/19/55565", "", "First", 400, 38800, "SCHOOL FEES", 45682, "Old Record", "x"],
    ["", "2024/2025", "First", 400, 38800, "SCHOOL FEES", 45682, "Old Record", "x"],
  ];
  const { columns, rows } = legacyFeeRows(grid);
  assert.equal(columns.purpose, 5);
  assert.equal(columns.paidOn, 6);
  assert.equal(columns.receipt, 8);
  assert.equal(columns.channel, 7);
  assert.equal(rows.length, 2, "a row without a matriculation number or a session is left out");
  assert.deepEqual(rows[0], { matric: "MOAU/SS/POL/25/84706", session: "2025/2026", semester: "Session", level: "100", amount: "2000", purpose: "GST FEES", paidOn: "46064", receiptNo: "2019470000000000", channel: "Interswitch", note: "" });
  assert.equal(legacyFeeKind(rows[0]), "GST");
  assert.equal(legacyFeeKind(rows[1]), "SCHOOL");
});

test("the portal's own template reads as before: a Note names another purpose only when it says one", () => {
  const header = ["Matriculation Number", "Session", "Semester", "Level", "Amount Paid", "Purpose / Payment Item", "Paid On", "Receipt No", "Note"];
  const c = legacyFeeColumns(header);
  assert.equal(c.purpose, 5);
  assert.equal(c.paidOn, 6);
  assert.equal(c.receipt, 7);
  assert.equal(c.note, 8);
  assert.equal(c.channel, -1);
  const old = legacyFeeColumns(["Matriculation Number", "Session", "Semester", "Level", "Amount Paid", "Paid On", "Receipt No", "Note"]);
  assert.equal(old.purpose, -1);
  const base = { matric: "m", session: "2022/2023", semester: "", level: "", amount: "", purpose: "", paidOn: "", receiptNo: "", channel: "" };
  assert.equal(legacyFeeKind({ ...base, note: "GST payment" }), "GST");
  assert.equal(legacyFeeKind({ ...base, note: "paid in two instalments" }), "SCHOOL");
  assert.equal(legacyFeeKind({ ...base, note: "Hostel accommodation" }), "OTHER");
  assert.equal(legacyFeeKind({ ...base, purpose: "ADMISSION CHECKING", note: "" }), "OTHER");
  assert.equal(legacyFeeKind({ ...base, purpose: "SCHOOL FEES MAKE UP", note: "" }), "SCHOOL");
});
