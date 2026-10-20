import { test } from "node:test";
import assert from "node:assert/strict";
import { progressWords, running, selectable, tickPage, toggle } from "./ticket-reset.ts";

test("only an eligible ticket, or one whose earlier reset failed, may be ticked; another category's never", () => {
  assert.equal(selectable("ELIGIBLE"), true);
  assert.equal(selectable("FAILED_BEFORE"), true);
  for (const s of ["IN_OPERATION", "RESET_DONE", "SETTLED", "NOT_STUDENT", null, undefined, "SOMETHING"]) assert.equal(selectable(s), false, String(s));
});

test("ticking the page takes its eligible rows only, and unticking leaves the rest of the selection", () => {
  const rows = [{ id: "a", reset_state: "ELIGIBLE" }, { id: "b", reset_state: "SETTLED" }, { id: "c", reset_state: null }, { id: "d", reset_state: "FAILED_BEFORE" }];
  const all = tickPage(new Set(["x"]), rows, true);
  assert.deepEqual([...all].sort(), ["a", "d", "x"]);
  assert.deepEqual([...tickPage(all, rows, false)], ["x"]);
  assert.deepEqual([...toggle(new Set(["a"]), "b", true)].sort(), ["a", "b"]);
  assert.deepEqual([...toggle(new Set(["a"]), "a", false)], []);
});

test("progress is said in students, and an operation is running while it starts or resets", () => {
  assert.equal(progressWords({ processed: 37, students: 100, succeeded: 35, failed: 2 }), "37 / 100 students · 35 reset · 2 not reset");
  assert.equal(running("PROCESSING"), true);
  assert.equal(running("AWAITING_APPROVAL"), false);
  assert.equal(running("COMPLETED"), false);
});
