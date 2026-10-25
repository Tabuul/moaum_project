import { test } from "node:test";
import assert from "node:assert/strict";
import { EMPTY_FILTERS, cellText, filterLines, kpiText, kpis, lagos, masterQuery, presetPeriod, readFilters, semWord, type MasterSummary, type SummaryRow } from "./master-report.ts";
import { barChart, figure, lineChart, pieChart, reportCharts, stackedChart } from "./master-charts.ts";

test("the filters read only what is well formed", () => {
  const f = readFilters({ fee: "paid", reg: "paid_not_registered", sex: "f", from: "2026-10-01", to: "yesterday", channel: "Bank%_branch", purpose: "school fees!" });
  assert.equal(f.fee, "PAID");
  assert.equal(f.reg, "PAID_NOT_REGISTERED");
  assert.equal(f.sex, "F");
  assert.equal(f.from, "2026-10-01");
  assert.equal(f.to, "");
  assert.equal(f.channel, "Bankbranch");
  assert.equal(f.purpose, "");
  assert.equal(readFilters({ sex: "X" }).sex, "");
});

test("the query carries the scope and only the filters set", () => {
  const q = masterQuery({ session: "2026/2027", sem: "1", fac: "SCI", dept: "", prog: "", level: "300" }, { ...EMPTY_FILTERS, fee: "NOT_PAID" }, { page: 2, all: false });
  assert.equal(q, "session=2026%2F2027&semester=1&fac=SCI&level=300&fee=NOT_PAID&page=2");
  assert.equal(masterQuery({ session: "2026/2027", sem: "0" }, EMPTY_FILTERS), "session=2026%2F2027");
});

test("a preset names its days; this session and this semester need the calendar's dates", () => {
  const today = new Date(2026, 9, 23);   // a Friday
  assert.deepEqual(presetPeriod("TODAY", today), { from: "2026-10-23", to: "2026-10-23" });
  assert.deepEqual(presetPeriod("YESTERDAY", today), { from: "2026-10-22", to: "2026-10-22" });
  assert.deepEqual(presetPeriod("WEEK", today), { from: "2026-10-19", to: "2026-10-23" });
  assert.deepEqual(presetPeriod("MONTH", today), { from: "2026-10-01", to: "2026-10-23" });
  assert.deepEqual(presetPeriod("YEAR", today), { from: "2026-01-01", to: "2026-10-23" });
  assert.equal(presetPeriod("SESSION", today), null);
  assert.deepEqual(presetPeriod("SESSION", today, { sessionFrom: "2026-09-01" }), { from: "2026-09-01", to: "2026-10-23" });
});

test("cells read as their kind says, moments in Lagos time", () => {
  assert.equal(cellText(1234567, "INT"), "1,234,567");
  assert.equal(cellText(180000, "MONEY"), "180,000.00");
  assert.equal(cellText("2026-10-23T09:31:00Z", "DATETIME"), "2026-10-23 10:31");
  assert.equal(lagos("2026-10-23T23:30:00Z"), "2026-10-24 00:30");
  assert.equal(cellText(null, "TEXT"), "");
  assert.equal(semWord(2), "Second semester");
});

const row = (over: Partial<SummaryRow>): SummaryRow => ({
  dim: "ALL", faculty_code: null, faculty: null, dept_code: null, department: null, programme_code: null, programme: null, level: null, sex: null,
  programme_type: null, study_mode: null, departments: 2, programmes: 3, total: 100, male: 48, female: 50, sex_unknown: 2, fees_paid: 40, fees_part: 10,
  fees_not_paid: 30, no_fee: 20, any_payment: 50, paid_not_registered: 12, registered: 60, not_registered: 40, carryover_registered: 5, reg_approved: 30,
  reg_pending: 30, payable: 18000000, paid_amount: 9000000, outstanding: 9000000, gst_applicable: 70, gst_registered: 55, gst_paid: 45, gst_not_paid: 25,
  gst_paid_amount: 180000, gst_outstanding: 100000, eps_applicable: 20, eps_registered: 15, eps_paid: 12, eps_not_paid: 8, card_eligible: 45, card_issued: 30,
  card_not_issued: 15, card_not_eligible: 55, permit_eligible: 40, permit_generated: 25, permit_printed: 20, permit_not_printed: 20, registered_not_paid: 3,
  gst_registered_not_paid: 4, card_issued_not_eligible: 0, permit_generated_not_eligible: 0, ...over,
});

const summary: MasterSummary = {
  filters: {}, scope: "The University", money: "ALL", at: "2026-10-23T09:00:00Z", reconciliation: [], sections: [],
  summary: [row({}), row({ dim: "FACULTY", faculty_code: "SCI", faculty: "Science", total: 60 }), row({ dim: "FACULTY", faculty_code: "ART", faculty: "Arts", total: 40 }),
    row({ dim: "GENDER", sex: "M", total: 48 }), row({ dim: "GENDER", sex: "F", total: 50 }), row({ dim: "LEVEL", level: 100, total: 100 })],
  transactions: { byStatus: [], byPurpose: [{ code: "SCHOOL_FEES", label: "School fees", transactions: 3, students: 1, successful: 3, pending: 0, failed: 0, reversed: 0, refunded: 0, revenue: 300000 }],
    byDay: [{ day: "2026-10-22", transactions: 2, amount: 200000 }, { day: "2026-10-23", transactions: 1, amount: 100000 }], bySemester: [], byFaculty: [],
    total: { transactions: 3, students: 1, revenue: 300000, refunded: 0 } },
};

test("the tiles are the server's figures, each opening its own list", () => {
  const k = kpis(summary);
  assert.equal(k.find((x) => x.label === "School fees paid")?.value, 40);
  assert.deepEqual(k.find((x) => x.label === "Paid but not registered")?.open, { reg: "PAID_NOT_REGISTERED" });
  const revenue = k.find((x) => x.label === "Total revenue (₦)");
  assert.ok(revenue && revenue.money);
  assert.equal(kpiText(revenue!), "₦300,000");
  assert.equal(k.find((x) => x.label === "Total transactions")?.value, 3);
  assert.deepEqual(filterLines({ ...EMPTY_FILTERS, fee: "NOT_PAID", from: "2026-10-01" }, null),
    [["School fees", "Not paid"], ["Transactions from", "2026-10-01 to today"]]);
});

test("the charts draw the figures they are given, labelled, escaped and in the palette's order", () => {
  const bar = barChart("Students by <faculty>", [{ label: "Science & Tech", value: 60 }, { label: "Arts", value: 40 }]);
  assert.match(bar, /Students by &lt;faculty&gt;/);
  assert.match(bar, /Science &amp; Tech/);
  assert.match(bar, /<title>Arts: 40<\/title>/);
  const pie = pieChart("Paid", [{ label: "Paid", value: 3 }, { label: "Not paid", value: 1 }]);
  assert.match(pie, /75\.0%/);
  assert.match(pie, /#2a78d6/);
  assert.match(pie, /#eb6834/);
  assert.match(pieChart("Nothing", [{ label: "Paid", value: 0 }]), /Nothing to show/);
  assert.match(lineChart("Revenue", [{ label: "2026-10-22", value: 2 }], { money: true }), /<polyline/);
  assert.match(stackedChart("Fees by gender", ["Male"], [{ name: "Paid", values: [5] }]), /Male — Paid: 5/);
  assert.equal(figure(2500000, true, true), "₦2.5m");
  const charts = reportCharts(summary);
  assert.ok(charts.faculty[0].includes("Science"));
  assert.equal(charts.tx_daily.length, 2);   // two measures, two charts: never two scales on one
});
