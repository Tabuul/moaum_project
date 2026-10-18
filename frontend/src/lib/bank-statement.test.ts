import { test } from "node:test";
import assert from "node:assert/strict";
import { readAmount, readDate, readStatement } from "./bank-statement.ts";

test("dates as banks write them", () => {
  assert.equal(readDate("17/10/2026"), "2026-10-17");
  assert.equal(readDate("7-10-26"), "2026-10-07");
  assert.equal(readDate("17-Oct-2026"), "2026-10-17");
  assert.equal(readDate("17 October 2026"), "2026-10-17");
  assert.equal(readDate("2026-10-17 09:12"), "2026-10-17");
  assert.equal(readDate("46312"), "2026-10-17", "an Excel day number");
  assert.equal(readDate("yesterday"), "");
});

test("amounts as banks write them", () => {
  assert.equal(readAmount("1,250.00"), "1250");
  assert.equal(readAmount("(1,250.50)"), "-1250.5");
  assert.equal(readAmount("-300"), "-300");
  assert.equal(readAmount("NGN 2,000"), "2000");
  assert.equal(readAmount(""), "");
});

test("a statement with a preamble, debit and credit columns", () => {
  const read = readStatement([
    ["MOAUM DISBURSEMENT ACCOUNT"], ["Statement period", "01/10/2026 - 17/10/2026"], [],
    ["Trans Date", "Reference", "Narration", "Debit", "Credit", "Balance"],
    ["15/10/2026", "FT26291AAA", "TRF TO DEMO TERHIDE", "4,000.00", "", "96,000.00"],
    ["16/10/2026", "", "INWARD TRANSFER", "", "50,000.00", "146,000.00"],
    ["", "", "Opening balance", "", "", "100,000.00"],
  ]);
  assert.equal(read.problem, null);
  assert.deepEqual(read.lines, [
    { date: "2026-10-15", description: "TRF TO DEMO TERHIDE", reference: "FT26291AAA", debit: "4000", credit: "" },
    { date: "2026-10-16", description: "INWARD TRANSFER", reference: "", debit: "", credit: "50000" },
  ]);
  assert.equal(read.skipped, 1);
});

test("one signed amount column: money out is negative", () => {
  const read = readStatement([["Date", "Details", "Amount"], ["2026-10-17", "TRF FT-X-1", "-2,500"], ["2026-10-17", "DEPOSIT", "900"]]);
  assert.deepEqual(read.lines.map((l) => `${l.debit}|${l.credit}`), ["2500|", "|900"]);
});

test("no header names a date and a debit", () => {
  assert.match(readStatement([["a", "b"], ["1", "2"]]).problem ?? "", /No header row/);
});
