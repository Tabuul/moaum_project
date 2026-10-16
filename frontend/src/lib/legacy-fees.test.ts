import { test } from "node:test";
import assert from "node:assert/strict";
import { itemCodes, legacyFeeColumns, legacyFeeKind, legacyFeeRows, withItemNames } from "./legacy-fees.ts";

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

test("V498: the old portal's raw payment download reads as it is — matno, payref, payment_item, treatedby", () => {
  const grid = [
    ["payref", "amount", "date", "matno", "payment_item", "semester", "session", "level", "treatedby"],
    ["PR202604146965246", 100204, 46163, "MOAU/AD/MAR/24/12056", "SCHOOL FEES", "First", "2025/2026", 200, "Interswitch"],
    ["PR2026041477173", 56400.005, 46177, "BSU/MBBS/17/771", "SCHOOLFEES MAKE UP", "First", "2023/2024", 600, "Interswitch"],
  ];
  const { columns, rows } = legacyFeeRows(grid);
  assert.deepEqual([columns.matric, columns.receipt, columns.purpose, columns.channel, columns.paidOn, columns.amount], [3, 0, 4, 8, 2, 1]);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].receiptNo, "PR202604146965246");
  assert.equal(rows[1].purpose, "SCHOOLFEES MAKE UP");
  assert.equal(legacyFeeKind(rows[1]), "SCHOOL", "a make-up is school fees: its own payment number keeps it beside the first");
});

test("V498: the payment_type sheet names each code, and a row carrying a code is read as the item it names", () => {
  const codes = itemCodes([
    ["pcode", "description", "amount", "school", "visibility"],
    [10048, "SCHOOL FEES", 0, "S001", 1],
    [10144, "GST FEES", 4000, "S001", 1],
    ["", "nothing", 0, "", 0],
  ]);
  assert.deepEqual(codes, [{ code: "10048", description: "SCHOOL FEES", school: "S001" }, { code: "10144", description: "GST FEES", school: "S001" }]);
  assert.deepEqual(itemCodes([["payref", "amount"], ["PR1", 5]]), [], "a sheet without codes has none");
  const { rows } = legacyFeeRows([
    ["payref", "amount", "date", "matno", "payment_item", "semester", "session", "level", "treatedby"],
    ["PR1", 156338, 46069, "MOAU/AD/PUB/25/00001", "10048", "First", "2025/2026", 100, "Interswitch"],
    ["PR2", 4000, 46076, "MOAU/AD/PUB/25/00001", "10144", "First", "2025/2026", 100, "Interswitch"],
    ["PR3", 500, 46076, "MOAU/AD/PUB/25/00001", "77777", "First", "2025/2026", 100, "Interswitch"],
  ]);
  const named = withItemNames(rows, codes);
  assert.equal(named.named, 2);
  assert.deepEqual(named.rows.map((r) => r.purpose), ["SCHOOL FEES", "GST FEES", "77777"]);
  assert.equal(legacyFeeKind(named.rows[0]), "SCHOOL");
  assert.equal(legacyFeeKind(named.rows[1]), "GST");
});
