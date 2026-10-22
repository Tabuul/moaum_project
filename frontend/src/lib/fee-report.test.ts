import { test } from "node:test";
import assert from "node:assert/strict";
import { FEE_REPORT_HEADERS, feeReportHref, feeReportRows, naira, sumLines, type FeeReportLine } from "./fee-report.ts";

const line = (o: Partial<FeeReportLine>): FeeReportLine => ({
  faculty_code: "AR", faculty: "ARTS", dept_code: "THA", department: "THEATRE ARTS", level: 200, students: 10, paid_students: 4, owing_students: 6,
  part_paid: 2, no_fee: 0, amount_due: "1218498.00", amount_paid: "800000.50", amount_owing: "418497.50",
  spill_students: 1, spill_due: "60000.00", spill_paid: "60000.00", spill_owing: "0", ...o,
});

test("each line follows the headers, S/N first, and the grand total closes the download unnumbered", () => {
  const rows = feeReportRows({ session: "2025/2026", rows: [line({}), line({ level: 300, paid_students: 1, owing_students: 2 })],
    total: { students: 20, paid_students: 5, owing_students: 8, part_paid: 4, no_fee: 0, amount_due: 0, amount_paid: "1600001.00", amount_owing: "836995.00",
      spill_students: 2, spill_due: "120000.00", spill_paid: "60000.00", spill_owing: "60000.00" } });
  assert.equal(rows.length, 3);
  assert.equal(rows[0].length, FEE_REPORT_HEADERS.length);
  assert.deepEqual(rows[0], [1, "2025/2026", "ARTS", "THEATRE ARTS", 200, 4, 6, 800000.5, 418497.5, 1, 60000, 0]);
  assert.deepEqual(rows[2], ["", "", "Grand total", "", "", 5, 8, 1600001, 836995, 2, 60000, 60000]);
});

test("the totals of the lines add up, to the kobo", () => {
  const t = sumLines([line({}), line({ amount_paid: "0.25", amount_owing: "0.30", paid_students: 1, owing_students: 1 })]);
  assert.equal(t.paid_students, 5);
  assert.equal(t.owing_students, 7);
  assert.equal(t.amount_paid, 800000.75);
  assert.equal(t.amount_owing, 418497.8);
  assert.equal(naira("121849.8"), 121849.8);
});

test("the link to share names only what is chosen", () => {
  assert.equal(feeReportHref("2025/2026", "", ""), "/finance/fee-report?session=2025%2F2026");
  assert.equal(feeReportHref("2025/2026", "AR", "THA"), "/finance/fee-report?session=2025%2F2026&fac=AR&dept=THA");
  assert.equal(feeReportHref("", "", ""), "/finance/fee-report");
});
