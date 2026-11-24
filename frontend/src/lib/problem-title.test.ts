import { test } from "node:test";
import assert from "node:assert/strict";
import { CODE_WORDS, humanTitle, problemRemedy } from "./problem-title.ts";

test("V779: the two new Summer refusals read by their code, whatever title the server sent", () => {
  // the API's fallback title for an unknown code is its bare words: "Credit reinstated" says the opposite of what happened
  assert.equal(humanTitle("Credit reinstated", undefined, "SUMMER_CREDIT_REINSTATED"), "This credit pays the programme fee again");
  assert.equal(humanTitle("Exam identity", undefined, "SUMMER_EXAM_IDENTITY"), "The Summer's examination session keeps its place");
  assert.equal(humanTitle(null, undefined, "SUMMER_EXAM_IDENTITY"), "The Summer's examination session keeps its place");
  // any other code keeps the server's title, as before
  assert.equal(humanTitle("Not for your office", undefined, "SUMMER_OFFICE"), "Not for your office");
  assert.equal(humanTitle("AUTH_LOCKED"), "Account locked for now");
  assert.equal(humanTitle(""), "The request was refused");
});

test("V779: a refusal's remedy is its own, or the one its code carries here when it has none", () => {
  const own = { message: "Ask the Bursar.", office: "Bursary" };
  assert.deepEqual(problemRemedy({ code: "SUMMER_CREDIT_REINSTATED", remedy: own }), own);
  assert.equal(problemRemedy({ code: "SUMMER_CREDIT_REINSTATED" })?.office, "Bursary");
  assert.match(problemRemedy({ code: "SUMMER_CREDIT_REINSTATED" })!.message, /^Nothing is reopened: the money pays the student's Summer programme fee/);
  assert.equal(problemRemedy({ code: "SUMMER_EXAM_IDENTITY" })?.office, "Directorate of ICT");
  assert.match(problemRemedy({ code: "SUMMER_EXAM_IDENTITY" })!.message, /^Move the dates only/);
  assert.equal(problemRemedy({ code: "SUMMER_OFFICE" }), undefined);
  assert.equal(problemRemedy(null), undefined);
  assert.deepEqual(Object.keys(CODE_WORDS).sort(), ["SUMMER_CREDIT_REINSTATED", "SUMMER_EXAM_IDENTITY"]);
});
