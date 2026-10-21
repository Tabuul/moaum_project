import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWord, loadKind, loadSummary, minimumBinds, minimumProblem, waivedWords } from "./registration-load.ts";

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


test("the minimum binds a registration with a current course of the programme, not carry-overs or GST/EPS courses alone (V597)", () => {
  assert.equal(loadKind([], 3), "CARRY_OVER");
  assert.equal(loadKind([], 5), "CARRY_OVER");
  assert.equal(loadKind([{ category: "GST" }], 0), "GST_EPS");
  assert.equal(loadKind([{ category: "GST" }], 3), "GST_EPS");
  assert.equal(loadKind([{ category: "CORE" }], 3), "NORMAL");
  assert.equal(loadKind([{ category: "ELECTIVE" }, { category: "GST" }], 0), "NORMAL");
  assert.equal(loadKind([], 0), "NORMAL");
  assert.equal(minimumBinds("NORMAL"), true);
  assert.equal(minimumBinds("CARRY_OVER"), false);
  // V615: a student in spillover, whatever the registration holds; one within the programme's length as before
  assert.equal(loadKind([{ category: "CORE" }], 0, "SPILLOVER_YEAR_1"), "SPILLOVER");
  assert.equal(loadKind([], 0, "SPILLOVER_LIMIT_REACHED"), "SPILLOVER");
  assert.equal(loadKind([{ category: "CORE" }], 0, "NORMAL"), "NORMAL");
  assert.equal(loadKind([{ category: "CORE" }], 0, null), "NORMAL");
  assert.equal(minimumBinds("SPILLOVER"), false);
  assert.match(waivedWords("SPILLOVER")?.hint ?? "", /^Spillover registration permitted/);
  assert.equal(minimumBinds("GST_EPS"), false);
});

test("the meter names the waiver and the summary keeps current courses and carry-overs apart", () => {
  assert.equal(waivedWords("NORMAL"), null);
  assert.equal(waivedWords("CARRY_OVER")?.label, "Carry-over registration");
  assert.match(waivedWords("CARRY_OVER")?.hint ?? "", /not to carry-overs alone/);
  assert.equal(waivedWords("GST_EPS")?.label, "GST/EPS registration");
  assert.equal(loadSummary(12, 3), "Current courses 12 CU · Carry-overs 3 CU");
  assert.equal(loadSummary(18, 0), "Current courses 18 CU");
});
