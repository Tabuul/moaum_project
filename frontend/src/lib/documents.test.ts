import { test } from "node:test";
import assert from "node:assert/strict";
import { semesterName } from "./documents.ts";

test("V754: a transcript's semester 3 is the Summer semester only where the session had one", () => {
  assert.equal(semesterName(3, true), "Summer semester");
  assert.equal(semesterName(3, false), "Third semester");
  // a statement frozen before V754 carries no flag: the third, as it always read
  assert.equal(semesterName(3), "Third semester");
  assert.equal(semesterName(3, null), "Third semester");
});

test("V754: the first and second semesters are never the Summer", () => {
  assert.equal(semesterName(1, true), "First semester");
  assert.equal(semesterName(2, true), "Second semester");
  assert.equal(semesterName(1), "First semester");
  assert.equal(semesterName(2), "Second semester");
  assert.equal(semesterName(4), "Semester 4");
  assert.equal(semesterName(null), "");
  assert.equal(semesterName(undefined, true), "");
});
