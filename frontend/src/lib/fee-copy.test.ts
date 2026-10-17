import { test } from "node:test";
import assert from "node:assert/strict";
import { copyScope, type CopyLine } from "./fee-copy.ts";

const line: CopyLine = {
  item: "School fees", kind: "FEE", amount: "150000.00", level: null, entry_mode: null, faculty_code: null, programme_code: null, fee_group: null,
  semester: null, indigene: null, spillover: false, ord: 0, target_amount: null, action: "COPY",
};

test("a line with no filter charges every student", () => {
  assert.equal(copyScope(line), "Every student");
});

test("a line's scope reads in the order Fee Setup shows it", () => {
  assert.equal(copyScope({ ...line, level: 200, faculty_code: "SS", programme_code: "C00023", indigene: "NON_INDIGENE", semester: 1 }),
    "200 Level · Faculty SS · Programme C00023 · Non-indigene · First semester");
  assert.equal(copyScope({ ...line, kind: "LATE_PAYMENT", entry_mode: "CCE", spillover: true, level: 300 }), "Late payment · Spillover · CCE (part-time)");
  assert.equal(copyScope({ ...line, fee_group: "PG", indigene: "INDIGENE" }), "Group PG · Indigene");
});
