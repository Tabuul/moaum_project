import { test } from "node:test";
import assert from "node:assert/strict";
import { exportBody, exportFilters } from "./export-log.ts";

test("the filters are the labelled block, the subtitle and the screen's own query, the block first", () => {
  const f = exportFilters({ meta: [["Session", "2025/2026"], ["Faculty", " Science "], ["Empty", "  "]], sub: "100 Level" }, "?session=2024%2F2025&dept=BIO&q=");
  assert.deepEqual(f, { Session: "2025/2026", Faculty: "Science", Subtitle: "100 Level", session: "2024/2025", dept: "BIO" });
});

test("the body names the report, the format, the rows, the screen and the serial, and never a negative or fractional count", () => {
  const b = JSON.parse(exportBody({ report: "  Payments  ", format: "XLSX", rows: -3, serial: "MOAUM/PAY/20261017/101500-07" }, "/finance/payments", "?session=2025%2F2026"));
  assert.equal(b.report, "Payments");
  assert.equal(b.format, "XLSX");
  assert.equal(b.rows, 0);
  assert.equal(b.screen, "/finance/payments?session=2025%2F2026");
  assert.equal(b.serial, "MOAUM/PAY/20261017/101500-07");
  assert.deepEqual(b.filters, { session: "2025/2026" });
  assert.equal(JSON.parse(exportBody({ report: "", format: "PRINT", rows: 12.7 }, "/x", "")).rows, 12);
  assert.equal(JSON.parse(exportBody({ report: "", format: "PRINT", rows: 1 }, "/x", "")).report, "Untitled report");
});

test("a long filter value is cut to what the log keeps", () => {
  const f = exportFilters({ meta: [["Programmes", "x".repeat(500)]] }, "");
  assert.equal(f.Programmes.length, 300);
});
