import { test } from "node:test";
import assert from "node:assert/strict";
import { BANK_GROUP_HEADERS, bankGroupRow, blcPath, cleanNumber, leftByHand, numbersIn, readBankList, type BankGroup } from "./bank-list.ts";

test("a gateway report: the title lines passed over, the payment number column read with its amount and day, each number once", () => {
  const r = readBankList([
    ["Interswitch collections report"],
    ["1 Mar 2026 to 5 Apr 2026"],
    [],
    ["S/N", "Payment Reference", "Customer Name", "Amount", "Payment Date"],
    ["1", "pr2026032643982", "Tersoo A.", "57,190.00", "26/03/2026"],
    ["2", "PR 2026032696124", "Tersoo A.", "57190", "2026-03-26"],
    ["3", "PR2026032643982", "Tersoo A.", "57,500.00", "27-Mar-2026"],
    ["4", "", "no number", "100", "01/03/2026"],
  ]);
  assert.equal(r.mode, "column");
  assert.equal(r.problem, null);
  assert.deepEqual(r.header, { number: "Payment Reference", amount: "Amount", date: "Payment Date" });
  assert.deepEqual(r.numbers, [{ n: "PR2026032643982", a: "57500" }, { n: "PR2026032696124", a: "57190" }]);
  assert.equal(r.rows, 4);
  assert.equal(r.from, "2026-03-01");
  assert.equal(r.to, "2026-03-27");
});

test("a list of numbers alone is read without amounts", () => {
  const r = readBankList([["Transaction Ref"], ["PR20260324060424158"], ["PR20260324060623304"]]);
  assert.deepEqual(r.numbers, [{ n: "PR20260324060424158" }, { n: "PR20260324060623304" }]);
  assert.equal(r.header.amount, null);
  assert.equal(r.from, null);
});

test("a bank statement without a number column: the numbers are found in the narration, words, dates and amounts left out", () => {
  const r = readBankList([
    ["Value Date", "Narration", "Credit"],
    ["26/03/2026", "WEB PMT PR2026032643982 MOAU SCHOOL FEES/TERSOO", "57,190.00"],
    ["26/03/2026", "TRF FROM AONDO PR2026032696124", "57,190.00"],
  ]);
  assert.equal(r.mode, "anywhere");
  assert.deepEqual(r.numbers.map((x) => x.n).filter((n) => n.startsWith("PR")), ["PR2026032643982", "PR2026032696124"]);
  assert.ok(r.numbers.every((x) => x.a === undefined));
  assert.ok(!r.numbers.some((x) => x.n === "SCHOOL" || x.n === "57"));
});

test("an empty file, or a number column with no number, is a problem", () => {
  assert.equal(readBankList([]).problem, "The file has no rows.");
  assert.match(readBankList([["Payment Reference", "Amount"], ["", "10"]]).problem ?? "", /holds no payment number/);
});

test("numbers are kept as the old portal keeps them", () => {
  assert.equal(cleanNumber(" pr 2026 0326 "), "PR20260326");
  assert.deepEqual(numbersIn("PMT pr2026032643982 on 26/03/2026 NGN57,190"), ["PR2026032643982"]);
});

test("a list reference is filed by year and number, and nothing else passes", () => {
  assert.equal(blcPath("BLC/2026/000014"), "2026/000014");
  assert.equal(blcPath("PNR/2026/000014"), null);
  assert.equal(blcPath("BLC/2026/14"), null);
});

test("what is left for a check by hand, and a judged group as an Excel row", () => {
  assert.equal(leftByHand({ RECEIVED: 4, NONE_FOUND: 2, AMOUNT_SHORT: 1, NO_NUMBER: 1, REFUSED: 1, CHECKED: 7 }), 5);
  const g: BankGroup = {
    student_id: "s", number: "BSU/AR/HIS/22/62034", name: "Tersoo, A", session: "2025/2026", purpose: "School fees (legacy) · semester 1", paid_on: "2026-03-26",
    amount: "57190", refs: ["R1", "R2"], payrefs: ["PR1", "PR2"], outcome: "NOT_RECEIVED", found: ["R1"], missing: ["R2"],
    withdrawals: [{ requestRef: "PNR/2026/000001", reference: "R2", state: "PROPOSED" }],
  };
  const row = bankGroupRow(g);
  assert.equal(row.length, BANK_GROUP_HEADERS.length);
  assert.deepEqual(row, ["BSU/AR/HIS/22/62034", "Tersoo, A", "2025/2026", "School fees (legacy) · semester 1", "2026-03-26", 57190, "R1, R2", "PR1, PR2", "R1", "R2",
    "Not all on the list", "PNR/2026/000001 proposed"]);
});
