import { test } from "node:test";
import assert from "node:assert/strict";
import { choicesOf, chunks, movedWords, orderedPairs, readMapping } from "./programme-merge.ts";

test("a mapping is read by its column names under a title, codes upper-cased, rows with no target or the same code left out", () => {
  const read = readMapping([
    ["Programme merge — proposed by the School"], [],
    ["Old code", "Old programme", "Students", "Merge into", "Into programme"],
    ["c00134", "MSC GEOGRAPHY", "19", "C00137", "MSC GEOGRAPHY"],
    ["C00137", "MSC GEOGRAPHY", "27", "c90088", "M.Sc. Geography"],
    ["C00144", "MA LANGUAGES AND LINGUISTICS", "55", "", ""],
    ["C00141", "MA HISTORY", "35", "C00141", ""],
  ]);
  assert.equal(read.problem, null);
  assert.deepEqual(read.pairs, [{ from: "C00134", to: "C00137" }, { from: "C00137", to: "C90088" }]);
});

test("a file without the two columns says so", () => {
  assert.match(String(readMapping([["Code", "Name"], ["C1", "x"]]).problem), /Old code/);
});

test("pairs run codes of one name first, then into the catalogue, then the twins; and go in chunks in that order", () => {
  const pairs = orderedPairs([{ step: 3, from: "C90108", to: "C90107" }, { step: 1, from: "C00134", to: "C00137" }, { step: 2, from: "C00137", to: "C90088" }]);
  assert.deepEqual(pairs.map((p) => p.from), ["C00134", "C00137", "C90108"]);
  assert.deepEqual(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
});

test("choices and moved rows read in words", () => {
  assert.deepEqual(choicesOf({ choices: '[{"code":"C90077","name":"M.Ed. Educational Management"}]' }), [{ code: "C90077", name: "M.Ed. Educational Management" }]);
  assert.deepEqual(choicesOf({ choices: null }), []);
  assert.equal(movedWords({ "people.student.programme_code": 1, "finance.fee_schedule.programme_code": 4 }), "1 student, 4 fee lines");
  assert.equal(movedWords({}), "nothing");
});
