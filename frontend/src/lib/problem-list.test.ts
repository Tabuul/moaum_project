import { test } from "node:test";
import assert from "node:assert/strict";
import { listedProblem } from "./problem-list.ts";

// V681: the PG fee refusal names every programme at once; the window lists them one a line
test("a refusal naming several programmes reads as its lead, one entry a programme and its tail", () => {
  const detail = "the postgraduate rows do not agree with their stages (24 rows of 2 programmes) — "
    + "C12916 MSC/PH.D MANAGEMENT (its name reads as Masters) — rows 641–652 (900 C, 900 D, 900 E): these are not stages of the programme's qualification; "
    + "C93757 MSC/PH.D MARKETING (its name reads as Masters) — rows 669–680 (900 C, 900 D, 900 E): these are not stages of the programme's qualification; "
    + "every faculty — row 700 (800B): 800 B — Year 2 is a 800 Level stage, not 700 Level; nothing was changed";
  const l = listedProblem(detail);
  assert.ok(l);
  assert.equal(l.lead, "the postgraduate rows do not agree with their stages (24 rows of 2 programmes)");
  assert.equal(l.items.length, 3);
  assert.ok(l.items[0].startsWith("C12916 MSC/PH.D MANAGEMENT"));
  assert.ok(l.items[1].startsWith("C93757 "));
  assert.equal(l.items[2], "every faculty — row 700 (800B): 800 B — Year 2 is a 800 Level stage, not 700 Level");
  assert.equal(l.tail, "nothing was changed");
});

test("a detail not written as a list is left as it is", () => {
  assert.equal(listedProblem("the file names programme C00140 that the portal does not hold"), null);
  assert.equal(listedProblem(undefined), null);
  assert.equal(listedProblem("a lead — ; nothing was changed"), null);
});
