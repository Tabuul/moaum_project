import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWord, minimumProblem } from "./registration-load.ts";

test("a minimum is a whole number from 1 to the lowest maximum", () => {
  assert.equal(minimumProblem("15", 24), null);
  assert.equal(minimumProblem(" 18 ", 24), null);
  assert.equal(minimumProblem("24", 24), null);
  assert.equal(minimumProblem("0", 24), "Minimum credit units must be greater than zero.");
  assert.equal(minimumProblem("-5", 24), "Minimum credit units must be greater than zero.");
  assert.equal(minimumProblem("abc", 24), "Minimum credit units must be a whole number.");
  assert.equal(minimumProblem("15.5", 24), "Minimum credit units must be a whole number.");
  assert.equal(minimumProblem("", 24), "Enter the minimum credit units.");
  assert.equal(minimumProblem("25", 24), "Minimum credit units cannot exceed the maximum of 24 credit units.");
  assert.equal(minimumProblem("40", null), null);
});

test("a change in the log reads in words", () => {
  assert.equal(changeWord("COURSE_REGISTRATION_MIN_CREDIT_CHANGED"), "Changed");
  assert.equal(changeWord("COURSE_REGISTRATION_MIN_CREDIT_SET"), "Set");
  assert.equal(changeWord("COURSE_REGISTRATION_MIN_CREDIT_REMOVED"), "Removed");
});
