import { test } from "node:test";
import assert from "node:assert/strict";
import { levelsFor, previewWords, reasonReady } from "./fee-setup.ts";
import { FEE_SHEET_HEADERS_WITH_STATUS, feeSheetRows, type FeeLine } from "./fee-setup-report.ts";

const programmes = [
  { code: "IC", faculty_code: "SC", levels: [100, 200, 300, 400, 500] },
  { code: "CS", faculty_code: "SC", levels: [100, 200, 300, 400] },
  { code: "MBBS", faculty_code: "BAMS", levels: [100, 200, 300, 400, 500, 600] },
  { code: "MSC", faculty_code: "SC", levels: [700, 800, 900] },
];

test("the levels come from the programme structure: the programmes ticked, else the faculty's, else every programme's", () => {
  assert.deepEqual(levelsFor(programmes, "SC", ["IC"]), [100, 200, 300, 400, 500]);
  assert.deepEqual(levelsFor(programmes, "SC", ["CS"]), [100, 200, 300, 400]);
  assert.deepEqual(levelsFor(programmes, "SC", []), [100, 200, 300, 400, 500, 700, 800, 900]);
  assert.deepEqual(levelsFor(programmes, "", []), [100, 200, 300, 400, 500, 600, 700, 800, 900]);
  assert.ok(!levelsFor(programmes, "SC", ["IC"]).includes(600), "Industrial Chemistry has no 600 Level");
  // an older programme list without levels: every level, as before
  assert.deepEqual(levelsFor([{ code: "X", faculty_code: "F" }], "F", []), [100, 200, 300, 400, 500, 600, 700, 800, 900]);
});

test("a reason is chosen, and Other is described", () => {
  assert.equal(reasonReady("", ""), false);
  assert.equal(reasonReady("WRONG_LEVEL", ""), true);
  assert.equal(reasonReady("OTHER", "typo"), false);
  assert.equal(reasonReady("OTHER", "Stated twice by the upload"), true);
});

test("the bulk confirmation reads what each line will be", () => {
  assert.deepEqual(previewWords({ selected: 3, REMOVED: 2, ARCHIVED: 1, CANNOT_REMOVE: 0, ALREADY_ARCHIVED: 0, NOT_FOUND: 0 }), [
    "3 fee structures selected", "2 can be removed", "1 has financial dependencies or charges students and will be archived instead",
  ]);
  assert.deepEqual(previewWords({ selected: 1, REMOVED: 0, ARCHIVED: 0, CANNOT_REMOVE: 1, ALREADY_ARCHIVED: 0, NOT_FOUND: 0 }), [
    "1 fee structure selected", "1 cannot be removed (used by financial records)",
  ]);
});

test("a report of archived and removed lines says which each is", () => {
  const l = (o: Partial<FeeLine>): FeeLine => ({ item: "School fees", amount: 1000, level: 600, entry_mode: null, faculty_code: "SC", faculty_name: "SCIENCE",
    programme_code: "IC", programme_name: "INDUSTRIAL CHEMISTRY", semester: 1, indigene: null, spillover: false, ...o });
  const rows = feeSheetRows([l({ status: "ACTIVE" }), l({ status: "ARCHIVED", level: 500 }), l({ status: "REMOVED", level: 400 })], true);
  assert.equal(FEE_SHEET_HEADERS_WITH_STATUS.at(-1), "Status");
  assert.deepEqual(rows.map((r) => [r[4], r.at(-1)]), [["400 Level", "Removed"], ["500 Level", "Archived"], ["600 Level", "Active"]]);
  assert.equal(feeSheetRows([l({})])[0].length, 9, "without the status column unless asked");
});
