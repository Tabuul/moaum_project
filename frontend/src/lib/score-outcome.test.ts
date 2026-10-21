import { test } from "node:test";
import assert from "node:assert/strict";
import { isAbsence, uploadedOutcome } from "./score-outcome.ts";

test("the old portal's ABS, in any of its spellings, is an absence", () => {
  for (const s of ["ABS", "abs", "AB", "Absent", "ABS (F)", "Abs.", " ABSENT "]) assert.equal(isAbsence(s), true, s);
  for (const s of ["", "A", "F", "45", "NR", "ABSTAIN", null, undefined]) assert.equal(isAbsence(s), false, String(s));
});

test("an uploaded row's outcome: the Outcome cell, else an ABS standing in for the mark", () => {
  assert.equal(uploadedOutcome("", "20", "45"), "GRADED");
  assert.equal(uploadedOutcome("ABS", "", ""), "ABSENT");
  assert.equal(uploadedOutcome("Abs (F)", "", ""), "ABSENT");
  assert.equal(uploadedOutcome("ABSENT", "", ""), "ABSENT");
  assert.equal(uploadedOutcome("", "", "ABS"), "ABSENT");
  assert.equal(uploadedOutcome("", "AB", ""), "ABSENT");
  // an AB in the CA column beside an exam score is no absence from the examination
  assert.equal(uploadedOutcome("", "AB", "45"), "GRADED");
  // the register's other outcomes pass as written, to be checked against them
  assert.equal(uploadedOutcome("withheld", "", ""), "WITHHELD");
  assert.equal(uploadedOutcome("NR", "", ""), "NR");
  assert.equal(uploadedOutcome("", "", ""), "GRADED");
});
