import { test } from "node:test";
import assert from "node:assert/strict";

import { ACTION_WORDS, dobFileRows, pendingOf } from "./dob-file.ts";

test("V721: the old portal's file is read by its headers — a number column and a date-of-birth column, the date as written", () => {
  const r = dobFileRows([["Matric No", "Surname", "DOB"], ["MOAU/SC/CSC/19/0001", "Ada", "12-09-2003"], ["", "", ""], ["MOAU/SC/CSC/19/0002 ", "Bem", "05/07/2001"]]);
  assert.ok("rows" in r);
  assert.deepEqual(r.rows, [{ row: 2, matric: "MOAU/SC/CSC/19/0001", jamb: "", dob: "12-09-2003" }, { row: 4, matric: "MOAU/SC/CSC/19/0002", jamb: "", dob: "05/07/2001" }]);
  assert.equal(r.empty, 0);
  const j = dobFileRows([["JAMB Reg Number", "Date of Birth"], ["20261234567AB", "2003-09-12"]]);
  assert.ok("rows" in j && j.rows[0].jamb === "20261234567AB" && j.rows[0].matric === "");
  assert.ok("err" in dobFileRows([["Surname", "Date of Birth"], ["Ada", "12-09-2003"]]), "no number column");
  assert.ok("err" in dobFileRows([["Matric", "Surname"], ["MOAU/1", "Ada"]]), "no date column");
  assert.ok("err" in dobFileRows([]));
});

test("V721: what a run would write is the filled and the corrected", () => {
  assert.equal(pendingOf({ applied: false, total: 5, counts: { AGREES: 1, FILLED: 2, CORRECTED: 1, DIFFERS: 1 }, rows: [] }), 3);
  assert.equal(ACTION_WORDS.CORRECTED.done, "Corrected");
});
