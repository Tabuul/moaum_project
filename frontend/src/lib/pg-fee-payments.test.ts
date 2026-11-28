import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PG_FEE_RESULT, pgFeeLeftWords, pgFeeMayUpload, pgFeePaymentRows, pgFeeSheet, pgFeeSummary, pgFeeWord, type PgFeeApiRow, type PgFeeReport,
} from "./pg-fee-payments.ts";
import { legacyFeeRows } from "./legacy-fees.ts";

/** the University's own sheet: the Old Fees History layout, one application fee, the rest of the sheet empty rows */
const HEADER = ["Matriculation Number", "Session", "Semester", "Level", "Amount", "Purpose/Payment Item", "Payment Date", "Channel", "Reference"];
const sheet = (...rows: string[][]): string[][] => [HEADER, ...rows];
const blank = () => ["", "", "", "", "", "", ""];

test("the University's own sheet reads to exactly one row for the server, with its row of the sheet", () => {
  const grid = sheet(
    ["PG/26/000310", "2026/2027", "", "", "20000", "PG APPLICATION", "2026-03-09", "Interswitch", "PR202609033502624"],
    blank(), blank(), blank(), blank(), [], blank(),
  );
  const r = pgFeePaymentRows(grid);
  assert.deepEqual(r.left, []);
  assert.deepEqual(r.rows, [{
    matric: "PG/26/000310", session: "2026/2027", semester: "", level: "", amount: "20000", purpose: "PG APPLICATION", paidOn: "2026-03-09",
    receiptNo: "PR202609033502624", channel: "Interswitch", note: "", row: 2,
  }]);
});

test("a payment date Excel stores as a day number goes to the server as it is read", () => {
  const r = pgFeePaymentRows(sheet(["PG/26/000310", "2026/2027", "", "", "20000", "PG APPLICATION", "46090", "Interswitch", "PR202609033502624"]));
  assert.equal(r.rows[0].paidOn, "46090");
});

test("the rows are the Old Fees History reader's own, row for row; each keeps its row of the sheet after the blank rows between", () => {
  const grid = sheet(
    ["PG/26/000310", "2026/2027", "", "", "20000", "PG APPLICATION", "2026-03-09", "Interswitch", "PR1"],
    blank(),
    ["pg/26/000311", "2026/2027", "First", "", "25,000", "PG APPLICATION", "2026-03-10", "Interswitch", "PR2"],
    ["PGOLD/2025/00872", "2025/2026", "", "", "20000", "PG APPLICATION", "", "Interswitch", "PR3"],
  );
  const r = pgFeePaymentRows(grid);
  assert.deepEqual(r.rows.map((x) => x.row), [2, 4, 5]);
  assert.deepEqual(r.rows.map((x) => { const o: Partial<PgFeeApiRow> = { ...x }; delete o.row; return o; }), legacyFeeRows(grid).rows, "no second reader: the same rows the Old Fees History upload reads");
  assert.equal(r.rows[1].matric, "pg/26/000311", "the number goes as written; the server reads it in any case");
  assert.equal(r.rows[1].amount, "25,000");
});

test("a row with no number is left out, and one with something written but not read is named, a blank row is neither", () => {
  const grid = sheet(
    ["", "2026/2027", "", "", "20000", "PG APPLICATION", "2026-03-09", "Interswitch", "PR1"],
    blank(),
    ["PG/26/000312", "", "", "", "20000", "PG APPLICATION", "2026-03-09", "Interswitch", "PR2"],
    ["PG/26/000313", "2026/2027", "", "", "20000", "PG APPLICATION", "2026-03-09", "Interswitch", "PR3"],
    ["   ", " ", "", "", "", "", ""],
  );
  const r = pgFeePaymentRows(grid);
  assert.deepEqual(r.rows.map((x) => [x.row, x.matric]), [[5, "PG/26/000313"]]);
  assert.deepEqual(r.left, [2, 4]);
  assert.match(pgFeeLeftWords(r.left), /^2 rows of the sheet were left out .* sheet rows 2, 4\.$/);
  assert.equal(pgFeeLeftWords([]), "");
  assert.match(pgFeeLeftWords([7]), /^1 row of the sheet was left out .* sheet row 7\.$/);
  assert.match(pgFeeLeftWords(Array.from({ length: 12 }, (_, i) => i + 2)), /sheet rows 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, and more\.$/);
});

test("a sheet without a matriculation-number column and a session column is not the layout", () => {
  const other = { name: "Codes", rows: [["pcode", "description"], ["10048", "SCHOOL FEES"]] };
  const pay = { name: "Payments", rows: sheet(["PG/26/000310", "2026/2027", "", "", "20000", "PG APPLICATION", "", "Interswitch", "PR1"]) };
  assert.equal(pgFeeSheet([other, pay]), pay, "the sheet that has them, wherever it stands in the workbook");
  assert.equal(pgFeeSheet([other]), null);
  assert.equal(pgFeeSheet([{ name: "Empty", rows: [] }]), null);
  assert.deepEqual(pgFeePaymentRows([]), { rows: [], left: [] });
});

test("every answer of the server has its words, future for a check and past for an upload, and its pill", () => {
  assert.deepEqual(pgFeeWord("CLEARED", false), ["Clears", "ok"]);
  assert.deepEqual(pgFeeWord("CLEARED", true), ["Cleared", "ok"]);
  assert.deepEqual(pgFeeWord("HELD", false), ["Held for an officer", "warn"]);
  assert.deepEqual(pgFeeWord("HELD", true), ["Held", "warn"]);
  assert.deepEqual(pgFeeWord("ALREADY", false), ["Already recorded", "grey"]);
  const refused: Record<string, string> = {
    NOT_APPLICATION_FEE: "Not an application fee", NO_REFERENCE: "No reference", NO_AMOUNT: "No amount", NOT_FOUND: "Number not found",
    IS_STUDENT: "A student's number", CONFLICT: "Reference used for another applicant", REJECTED: "Rejected before",
  };
  for (const [k, word] of Object.entries(refused)) {
    assert.deepEqual(pgFeeWord(k, false), [word, "bad"], k);
    assert.deepEqual(pgFeeWord(k, true), [word, "bad"], k);
  }
  assert.equal(Object.keys(PG_FEE_RESULT).length, 10, "the ten results of the server, no more");
  assert.deepEqual(pgFeeWord("SOMETHING_NEW", true), ["SOMETHING_NEW", "grey"], "an answer not listed is shown as it came");
});

const report = (o: Partial<PgFeeReport>): PgFeeReport => ({
  applied: false, batchId: null, batchReference: null, fileName: "p.xlsx", rows: 0, cleared: 0, held: 0, already: 0, refused: 0, results: [], ...o,
});

test("the report in a line: what will clear, be held, is recorded already and is refused; then what did", () => {
  const check = report({ rows: 5, cleared: 2, held: 1, already: 1, refused: 1 });
  assert.equal(pgFeeSummary(check), "5 rows: 2 will clear, 1 will be held, 1 already recorded, 1 refused");
  assert.equal(pgFeeSummary({ ...check, applied: true }), "5 rows: 2 cleared, 1 held, 1 already recorded, 1 refused");
  assert.equal(pgFeeSummary(report({ rows: 1, cleared: 1 })), "1 row: 1 will clear, 0 will be held, 0 already recorded, 0 refused");
  assert.equal(pgFeeSummary(report({ rows: 1200, cleared: 1200 })), "1,200 rows: 1,200 will clear, 0 will be held, 0 already recorded, 0 refused");
});

test("the Upload is offered only after a check that has a row to clear or hold", () => {
  assert.equal(pgFeeMayUpload(null), false, "nothing checked yet");
  assert.equal(pgFeeMayUpload(report({ rows: 2, cleared: 1 })), true);
  assert.equal(pgFeeMayUpload(report({ rows: 2, held: 2 })), true);
  assert.equal(pgFeeMayUpload(report({ rows: 3, already: 2, refused: 1 })), false, "nothing to record: the same file again changes nothing");
  assert.equal(pgFeeMayUpload(report({ rows: 2, cleared: 2, applied: true })), false, "uploaded already");
});
