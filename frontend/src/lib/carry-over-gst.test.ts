import { test } from "node:test";
import assert from "node:assert/strict";
import { gstHeld, selection, tickable, type CarryRow } from "./carry-over.ts";

const row = (code: string, extra: Partial<CarryRow> = {}): CarryRow => ({
  course_id: `id-${code}`, course_code: code, shown_code: code, title: `Title ${code}`, units: 2, level: 200, course_semester: 2, both_semesters: false,
  course_group: code.startsWith("EPS") ? "EPS" : code.startsWith("GST") ? "GST" : "OTHER", status: "NO_RECORD", origin_session: null, origin_semester: null,
  last_grade: null, offering_id: null, selectable: true, reason: "", ...extra,
});

test("V691: a GST/EPS course the GST fee holds is flagged and cannot be ticked; the others can", () => {
  const eps = row("EPS 202", { gst_held: true, gst_to_pay: 4000 });
  const csc = row("CSC 201");
  const cleared = row("GST 211", { selectable: false, status: "CLEARED" });
  assert.equal(tickable(eps), false);
  assert.equal(tickable(csc), true);
  assert.equal(tickable(cleared), false);
  assert.equal(tickable(row("GST 212", { gst_held: false })), true);
});

test("V691: the fee is named once for every held course (one payment covers GST and EPS)", () => {
  assert.deepEqual(gstHeld([row("EPS 202", { gst_held: true, gst_to_pay: 4000 }), row("GST 212", { gst_held: true, gst_to_pay: 4000 }), row("CSC 201")]), { count: 2, toPay: 4000 });
  assert.deepEqual(gstHeld([row("EPS 202", { gst_held: true, gst_to_pay: null })]), { count: 1, toPay: null });
  assert.equal(gstHeld([row("CSC 201"), row("GST 212", { gst_held: false })]), null);
});

test("V691: a held course picked before the fee was asked is not counted in what is ticked", () => {
  const rows = [row("EPS 202", { gst_held: true, gst_to_pay: 4000 }), row("CSC 201")];
  const s = selection(rows, new Set(["id-EPS 202", "id-CSC 201"]));
  assert.equal(s.count, 1);
  assert.equal(s.units, 2);
});
