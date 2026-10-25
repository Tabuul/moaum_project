import { test } from "node:test";
import assert from "node:assert/strict";
import { bySession, clearanceRows, readComponents, reportRows, statementRows, totals, type Period } from "./historical-fees.ts";

// V654: the historical account as the screens group it — by session with its totals — and as the reports write it
const periods: Period[] = [
  { session: "2022/2023", semester: 2, level: 200, assessed: "120000.00", paid: "60000.00", outstanding: "60000.00", credit: 0, status: "PARTIALLY_PAID" },
  { session: "2022/2023", semester: 1, level: 200, assessed: "120000.00", paid: "120000.00", outstanding: 0, credit: 0, status: "CLEARED" },
  { session: "2021/2022", semester: 2, level: 100, assessed: null, paid: "10000.00", outstanding: null, credit: 0, status: "REQUIRES_REVIEW" },
  { session: "2021/2022", semester: 1, level: 100, assessed: "100000.00", paid: "100000.00", outstanding: 0, credit: 0, status: "CLEARED" },
];

test("the periods grouped by session, in order, with each session's totals; a period for review owes nothing yet", () => {
  const g = bySession(periods);
  assert.deepEqual(g.map((x) => [x.session, x.periods.map((p) => p.semester), x.assessed, x.paid, x.outstanding, x.review]), [
    ["2021/2022", [1, 2], 100000, 110000, 0, 1],
    ["2022/2023", [1, 2], 240000, 180000, 60000, 0],
  ]);
  assert.deepEqual(totals(periods), { assessed: 340000, paid: 290000, outstanding: 60000, credit: 0, review: 1, owing: ["2022/2023 second semester"] });
});

test("the components typed on the form: blank rows left out, the amount read as naira", () => {
  assert.deepEqual(readComponents([{ item: "Tuition", amount: "₦70,000" }, { item: "", amount: "" }, { item: " Levies ", amount: "20000" }]),
    [{ item: "Tuition", amount: 70000 }, { item: "Levies", amount: 20000 }]);
});

test("the report and statement rows: S/N first and numeric, numbers as text, amounts as numbers, the source and the status in words", () => {
  const r = reportRows([{ student: "DOE, John", matric_no: "MOAUM/SC/20/0001", jamb_reg_no: "20123456AB", faculty: "Science", department: "Computer Science",
    programme: "B.Sc. Computer Science", graduation_session: "2024/2025", session: "2022/2023", semester: 2, level: 200, assessed: "120000.00", paid: "60000.00",
    outstanding: "60000.00", credit: 0, source: "ASSESSMENT", source_ref: "HFA/2026/000001", status: "PARTIALLY_PAID", assessment_state: "APPROVED",
    financial_status: "FINANCIAL_OBLIGATION", bursary_clearance: null, dated: "2026-10-25T09:00:00Z" }]);
  assert.deepEqual(r[0], [1, "DOE, John", "MOAUM/SC/20/0001", "20123456AB", "Science", "Computer Science", "B.Sc. Computer Science", "2024/2025", "2022/2023",
    "Second semester", 200, 120000, 60000, 60000, "Approved assessment HFA/2026/000001", "Partially paid", "Financial obligation", "Approved — in force", "2026-10-25"]);
  const c = clearanceRows([{ student: "DOE, John", matric_no: "M1", jamb_reg_no: null, faculty: null, department: null, programme: "P", graduation_session: "2024/2025",
    owing: "2022/2023 S2", assessed: 340000, paid: 280000, outstanding: 60000, credit: 0, financial_status: "FINANCIAL_OBLIGATION", last_payment_at: null,
    bursary_clearance: "NOT_CLEARED", bursary_officer: null, bursary_at: null }]);
  assert.equal(c[0][0], 1);
  assert.equal(c[0][13], "not cleared");
  assert.deepEqual(statementRows(periods).map((x) => x.slice(1, 7)), [
    ["2021/2022", "First semester", 100, 100000, 100000, 0], ["2021/2022", "Second semester", 100, "Being assessed", 10000, "—"],
    ["2022/2023", "First semester", 200, 120000, 120000, 0], ["2022/2023", "Second semester", 200, 120000, 60000, 60000],
  ]);
});
