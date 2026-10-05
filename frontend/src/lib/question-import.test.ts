import { test } from "node:test";
import assert from "node:assert/strict";
import { detectQuestionMapping, questionHeaderRowIndex, questionRowsOf } from "./question-import.ts";

test("a question sheet's headings are matched by name: the question, lettered options, the key, the rest optional", () => {
  const map = detectQuestionMapping(["S/N", "Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer", "Difficulty", "Marks", "Explanation"]);
  assert.equal(map.topic, 1);
  assert.equal(map.stem, 2);
  assert.deepEqual([map.optionA, map.optionB, map.optionC, map.optionD], [3, 4, 5, 6]);
  assert.equal(map.answer, 7);
  assert.equal(map.difficulty, 8);
  assert.equal(map.marks, 9);
  assert.equal(map.explanation, 10);
  assert.equal(map.kind, undefined, "a column the file lacks is absent, never guessed");
});

test("bare A, B, C, D headings are the options, and a single Options column is read too", () => {
  const map = detectQuestionMapping(["Question", "A", "B", "C", "D", "Key"]);
  assert.deepEqual([map.optionA, map.optionB, map.optionC, map.optionD, map.answer], [1, 2, 3, 4, 5]);
  const one = detectQuestionMapping(["Question", "Options", "Answer", "Type"]);
  assert.deepEqual([one.stem, one.options, one.answer, one.kind], [0, 1, 2, 3]);
});

test("the header row is found below title lines, options come from the lettered columns or the one column split on | and ;, blanks are left out", () => {
  const cells = [["GST 101 question bank"], [""], ["Question", "Option A", "Option B", "Option C", "Answer"], ["Capital of Nigeria?", "Lagos", "Abuja", "Kano", "B"], ["", "", "", "", ""], ["Even numbers?", "1", "2", "4", "B, C"]];
  const h = questionHeaderRowIndex(cells);
  assert.equal(h, 2);
  const rows = questionRowsOf(cells, h, detectQuestionMapping(cells[h]));
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].row, rows[0].stem, rows[0].options, rows[0].answer], [4, "Capital of Nigeria?", ["Lagos", "Abuja", "Kano"], "B"]);
  assert.deepEqual([rows[1].row, rows[1].options, rows[1].answer], [6, ["1", "2", "4"], "B, C"]);
  const single = questionRowsOf([["Question", "Options", "Answer"], ["Sky is up", "True | False", "True"], ["Pick", "x; y; z", "z"]], 0, detectQuestionMapping(["Question", "Options", "Answer"]));
  assert.deepEqual(single[0].options, ["True", "False"]);
  assert.deepEqual(single[1].options, ["x", "y", "z"]);
});
