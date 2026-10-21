import { test } from "node:test";
import assert from "node:assert/strict";
import { copyScope, levelWords, type CopyLine } from "./fee-copy.ts";

const line: CopyLine = {
  item: "School fees", kind: "FEE", amount: "150000.00", level: null, entry_mode: null, faculty_code: null, programme_code: null, fee_group: null,
  semester: null, indigene: null, spillover: false, ord: 0, target_amount: null, action: "COPY",
};

test("V613: a line's level in words — the spillover year with the programme's final level", () => {
  assert.equal(levelWords(200, false), "200 Level");
  assert.equal(levelWords(null, false), null);
  assert.equal(levelWords(400, true, 1), "400 Level (SP1)");
  assert.equal(levelWords(500, true, 2), "500 Level (SP2)");
  assert.equal(levelWords(400, true, null), "400 Level (spillover)");
  assert.equal(levelWords(null, true, 3), "Spillover (SP3)");
  assert.equal(levelWords(null, true), "Spillover");
});

test("a line with no filter charges every student", () => {
  assert.equal(copyScope(line), "Every student");
});

test("a line's scope reads in the order Fee Setup shows it", () => {
  assert.equal(copyScope({ ...line, level: 200, faculty_code: "SS", programme_code: "C00023", indigene: "NON_INDIGENE", semester: 1 }),
    "200 Level · Faculty SS · Programme C00023 · Non-indigene · First semester");
  assert.equal(copyScope({ ...line, kind: "LATE_PAYMENT", entry_mode: "CCE", spillover: true, level: 300 }), "Late payment · 300 Level (spillover) · CCE (part-time)");
  // V613: the spillover year, at the programme's final level or for every programme
  assert.equal(copyScope({ ...line, spillover: true, level: 400, spill_year: 1, semester: 1 }), "400 Level (SP1) · First semester");
  assert.equal(copyScope({ ...line, spillover: true, level: null, spill_year: 2 }), "Spillover (SP2)");
  assert.equal(copyScope({ ...line, spillover: true, level: null, spill_year: null }), "Spillover");
  assert.equal(copyScope({ ...line, fee_group: "PG", indigene: "INDIGENE" }), "Group PG · Indigene");
});
