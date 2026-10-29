import { test } from "node:test";
import assert from "node:assert/strict";
import { differenceWords, heldCells, HELD_HEADERS, narrowHeld, type HeldFeeRow } from "./held-fees.ts";

const row = (n: string, d: number, spill: string | null = null): HeldFeeRow => ({
  studentId: n, number: "BSU/ED/GC/23/" + n, studentName: "TERUMBUR, Mary " + n, programmeCode: "C00412", programme: "B.Ed. Guidance and Counselling",
  deptCode: "GC", facultyCode: "ED", heldLevel: 200, unheldLevel: 300, heldSpillover: spill, chargedHeld: 60000 + d, chargedUnheld: 60000, difference: d,
});

test("V702: the held students' fees — the difference in words, the export row, the narrowing", () => {
  assert.equal(differenceWords(2500), "₦2,500 more held");
  assert.equal(differenceWords(-1000), "₦1,000 less held");
  assert.equal(differenceWords(0), "The same");
  const cells = heldCells(row("1", 2500, "SPILLOVER_YEAR_1"));
  assert.equal(cells.length, HELD_HEADERS.length);
  assert.deepEqual(cells.slice(3), [200, "SP1", 300, 62500, 60000, 2500]);
  const rows = [row("1", 2500), row("2", 0), row("3", -400)];
  assert.deepEqual(narrowHeld(rows, "", "changed").map((r) => r.studentId), ["1", "3"]);
  assert.deepEqual(narrowHeld(rows, "", "higher").map((r) => r.studentId), ["1"]);
  assert.deepEqual(narrowHeld(rows, "", "lower").map((r) => r.studentId), ["3"]);
  assert.deepEqual(narrowHeld(rows, "mary 2", "all").map((r) => r.studentId), ["2"]);
});
