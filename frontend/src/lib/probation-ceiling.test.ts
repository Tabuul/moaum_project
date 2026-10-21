import { test } from "node:test";
import assert from "node:assert/strict";
import { levelsWords, probationUnset } from "./probation-ceiling.ts";

test("the undergraduate levels with no probation ceiling, in order; postgraduate levels are not asked", () => {
  const limits = [
    { level: 300, probationMaxUnits: null }, { level: 100 }, { level: 200, probationMaxUnits: 15 }, { level: 600, probationMaxUnits: undefined },
    { level: 700, probationMaxUnits: null }, { level: 900 }, { level: 400, probationMaxUnits: 0 },
  ];
  assert.deepEqual(probationUnset(limits), [100, 300, 600]);
  assert.deepEqual(probationUnset([]), []);
  assert.deepEqual(probationUnset([{ level: 100, probationMaxUnits: 12 }]), []);
});

test("the levels in words", () => {
  assert.equal(levelsWords([]), "");
  assert.equal(levelsWords([300]), "300 Level");
  assert.equal(levelsWords([100, 200]), "100 and 200 Level");
  assert.equal(levelsWords([100, 200, 300, 400, 500, 600]), "100, 200, 300, 400, 500 and 600 Level");
});
