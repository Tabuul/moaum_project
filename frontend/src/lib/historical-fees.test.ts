import { test } from "node:test";
import assert from "node:assert/strict";
import { bySession, clearanceRows, readComponents, reconRows, reportRows, statementRows, totals, waiverAmountProblem, type Period } from "./historical-fees.ts";

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
  assert.deepEqual(totals(periods), { assessed: 340000, waived: 0, paid: 290000, outstanding: 60000, credit: 0, review: 1, owing: ["2022/2023 second semester"] });
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
  assert.deepEqual(statementRows(periods).map((x) => x.slice(1, 8)), [
    ["2021/2022", "First semester", 100, 100000, 0, 100000, 0], ["2021/2022", "Second semester", 100, "Being assessed", 0, 10000, "—"],
    ["2022/2023", "First semester", 200, 120000, 0, 120000, 0], ["2022/2023", "Second semester", 200, 120000, 0, 60000, 60000],
  ]);
});

// V665: an approved waiver lowers what the period owes; the statement and the totals carry it
test("a waived period: the session's waived total, the statement's adjustment column, and the amount a waiver may be", () => {
  const w: Period[] = [{ session: "2023/2024", semester: 1, level: 300, assessed: "100000.00", waived: "15000.00", paid: "60000.00", outstanding: "25000.00", credit: 0, status: "PARTIALLY_PAID" }];
  assert.equal(bySession(w)[0].waived, 15000);
  assert.equal(totals(w).waived, 15000);
  assert.deepEqual(statementRows(w)[0].slice(4, 8), [100000, 15000, 60000, 25000]);
  assert.equal(waiverAmountProblem("", "25000"), "Enter the amount to waive.");
  assert.equal(waiverAmountProblem("30,000", "25000.00"), "At most what the period still owes (₦25,000).");
  assert.equal(waiverAmountProblem("₦25,000", "25000.00"), null);
});

test("a reconciliation run's rows: S/N first, the academic status in words, the amounts as numbers, the status in words", () => {
  const r = reconRows([{ student_id: "x", student: "DOE, Jane", matric_no: "M1", jamb_reg_no: null, faculty: "Science", department: "Physics", programme: "B.Sc. Physics",
    status: "PAYMENT_REVIEW", student_status: "ACTIVE", awaiting_graduation: true, graduation_session: "2024/2025", periods: 8, assessed: "800000.00", paid: "760000.00",
    waived: "15000.00", outstanding: "25000.00", credit: 0, owing: "2023/2024 First semester (₦25,000)", review_periods: null, pending_periods: null, other_payments: 1,
    other_amount: "5000.00", process_id: null, clearance_ref: "FCL/2026/000001", bursary_state: "WAITING" }]);
  assert.deepEqual(r[0], [1, "DOE, Jane", "M1", "", "Science", "Physics", "B.Sc. Physics", "2024/2025", "Award approved — awaiting final clearance", 800000, 760000, 15000,
    25000, "2023/2024 First semester (₦25,000)", "", 5000, "Owing — other payments to review", "FCL/2026/000001", "waiting"]);
});
