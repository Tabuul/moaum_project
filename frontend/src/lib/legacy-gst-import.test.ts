import { test } from "node:test";
import assert from "node:assert/strict";
import { detectLegacyMapping, legacyHeaderRowIndex, legacyRowsOf } from "./legacy-gst-import.ts";

test("an old-portal export's headings are matched by name, exact first, each column once", () => {
  const map = detectLegacyMapping(["S/N", "Transaction ID", "RRR", "Matric No", "JAMB Reg No", "Full Name", "Fee Type", "Amount Paid", "Payment Date", "Session", "Status", "Gateway"]);
  assert.equal(map.transactionId, 1);
  assert.equal(map.reference, 2, "RRR is the payment reference");
  assert.equal(map.matric, 3);
  assert.equal(map.jamb, 4);
  assert.equal(map.name, 5);
  assert.equal(map.paymentType, 6);
  assert.equal(map.amount, 7);
  assert.equal(map.paidAt, 8);
  assert.equal(map.session, 9);
  assert.equal(map.status, 10);
  assert.equal(map.gateway, 11);
  assert.equal(map.semester, undefined, "a column the file lacks is absent, never guessed");
});

test("a bare 'Student ID' is the old portal's own id and 'Reference' is the payment reference, not the gateway's", () => {
  const map = detectLegacyMapping(["Student ID", "Reference", "Gateway Reference", "Amount", "Session", "Status"]);
  assert.equal(map.legacyStudentId, 0);
  assert.equal(map.reference, 1);
  assert.equal(map.gatewayReference, 2);
});

test("the header row is found below title lines, rows are numbered as the sheet numbers them, blanks are left out and the bar fills a missing session", () => {
  const cells = [["GST payments export"], [""], ["Transaction ID", "Matric No", "Amount", "Status", "Session"], ["TX1", "MOAUM/ACC/26/001", "20,000", "SUCCESS", ""], ["", "", "", "", ""], ["TX2", "MOAUM/ACC/26/002", "20000", "FAILED", "2025/2026"]];
  const h = legacyHeaderRowIndex(cells);
  assert.equal(h, 2);
  const rows = legacyRowsOf(cells, h, detectLegacyMapping(cells[h]), { session: "2026/2027" });
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].row, rows[0].transactionId, rows[0].matric, rows[0].amount, rows[0].session, rows[0].status], [4, "TX1", "MOAUM/ACC/26/001", "20,000", "2026/2027", "SUCCESS"]);
  assert.deepEqual([rows[1].row, rows[1].session, rows[1].status], [6, "2025/2026", "FAILED"]);
});
