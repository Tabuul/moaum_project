import { test } from "node:test";
import assert from "node:assert/strict";
import { codeVariant, courseLabel, shownCode, titleChoiceKey } from "./course-code.ts";

test("V646: a separate course under a code is shown under the code", () => {
  assert.equal(shownCode("CSC 401 BMAS"), "CSC 401");
  assert.equal(shownCode("CSC 401 CCMAS2"), "CSC 401");
  assert.equal(shownCode("CSC 401 V2"), "CSC 401");
  assert.equal(shownCode("BSU-PHY 106"), "BSU-PHY 106");
  assert.equal(shownCode("CSC 401"), "CSC 401");
  assert.equal(shownCode(null), "");
});

test("V646: the mark of a separate course, none for the first", () => {
  assert.equal(codeVariant("CSC 401 BMAS"), "BMAS");
  assert.equal(codeVariant("CSC 401 CCMAS2"), "CCMAS2");
  assert.equal(codeVariant("CSC 401 V2"), "V2");
  assert.equal(codeVariant("CSC 401"), null);
});

test("V646: the label tells two courses under one code apart by title, and the curriculum of the separate one", () => {
  assert.equal(courseLabel("CSC 401", "Computer Networks"), "CSC 401 — Computer Networks");
  assert.equal(courseLabel("CSC 401 BMAS", "Advanced Computer Systems", "BMAS"), "CSC 401 — Advanced Computer Systems (BMAS)");
  assert.equal(courseLabel("CSC 401 CCMAS2", "Computer Architecture"), "CSC 401 — Computer Architecture (CCMAS)");
  assert.equal(courseLabel("CSC 401 V2", "Computer Architecture"), "CSC 401 — Computer Architecture");
});

test("V646: a structure row's choice is found whatever the spacing of its code or the case of its title", () => {
  assert.equal(titleChoiceKey("CSC401", "Computer Networks"), titleChoiceKey("csc 401", "computer  networks"));
  assert.notEqual(titleChoiceKey("CSC 401", "Computer Networks"), titleChoiceKey("CSC 401", "Advanced Computer Systems"));
});
