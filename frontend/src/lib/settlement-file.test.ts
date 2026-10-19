import { test } from "node:test";
import assert from "node:assert/strict";
import { readSettlement } from "./settlement-file.ts";

test("Interswitch's columns are found under a title, each row read with its day, reference, Log Id, amount, fee and net", () => {
  const read = readSettlement([
    ["Settlement Report — MOAUM"], ["From 1 Oct 2026 to 15 Oct 2026"], [],
    ["S/N", "Transaction Date", "Settlement Date", "Customer Reference", "Payment Log Id", "Customer Name", "Amount", "Fee", "Settlement Amount", "Channel"],
    ["1", "14/10/2026", "15/10/2026", "MOAUM-FEE-123456-0001", "1234567", "DOE Jane (MOAU/CS/24/1)", "10,000.00", "100.00", "9,900.00", "WEB"],
    ["2", "14/10/2026", "15/10/2026", "MOAUM-FEE-123456-0002", "1234568", "DOE John", "NGN 5,000", "(75.00)", "4925", "BANK BRANCH"],
    ["", "", "", "", "", "", "", "", "", ""],
    ["Total", "", "", "", "", "", "", "", "", ""],
  ]);
  assert.equal(read.problem, null);
  assert.equal(read.rows.length, 2);
  assert.equal(read.skipped, 1);
  assert.deepEqual(read.rows[0], { settledOn: "2026-10-15", paidOn: "2026-10-14", reference: "MOAUM-FEE-123456-0001", txnRef: "", logId: "1234567", paymentRef: "",
    channel: "WEB", payer: "DOE Jane (MOAU/CS/24/1)", amount: "10000", fee: "100", net: "9900" });
  assert.equal(read.rows[1].fee, "75");
  assert.equal(read.rows[1].amount, "5000");
});

test("WebPAY's transaction reference is read, and a report with no settlement date takes the day given", () => {
  const grid = [["Txn Ref", "Amount", "Charge"], ["TXN0001A", "2000", "20"]];
  const none = readSettlement(grid);
  assert.equal(none.needsDay, true);
  assert.match(String(none.problem), /settlement date/);
  const given = readSettlement(grid, "2026-10-16");
  assert.equal(given.problem, null);
  assert.equal(given.rows[0].settledOn, "2026-10-16");
  assert.equal(given.rows[0].txnRef, "TXN0001A");
  assert.equal(given.rows[0].fee, "20");
});

test("a file with no recognisable header says so", () => {
  const read = readSettlement([["Name", "Phone"], ["A", "080"]]);
  assert.equal(read.rows.length, 0);
  assert.match(String(read.problem), /No header row/);
});
