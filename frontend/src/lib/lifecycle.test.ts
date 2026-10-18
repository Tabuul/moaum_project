import { test } from "node:test";
import assert from "node:assert/strict";
import { aboutToReconcile, actionable, batchPath, chunks, crossTab, reasonOk, recWord, spillColumns } from "./lifecycle.ts";

test("every recommendation has its words, a further spillover year included", () => {
  assert.equal(recWord("GRADUATION_CANDIDATE"), "Graduation candidate");
  assert.equal(recWord("SPILLOVER_YEAR_2"), "Spillover year 2");
  assert.equal(recWord("SPILLOVER_YEAR_3"), "Spillover year 3");
  assert.equal(recWord("MAXIMUM_SPILLOVER_REACHED"), "Maximum spillover reached");
});

test("only graduation candidates, spillover years and the maximum are reconciled", () => {
  assert.equal(actionable("GRADUATION_CANDIDATE"), true);
  assert.equal(actionable("SPILLOVER_YEAR_1"), true);
  assert.equal(actionable("SPILLOVER_YEAR_4"), true);
  assert.equal(actionable("MAXIMUM_SPILLOVER_REACHED"), true);
  assert.equal(actionable("REQUIRES_REVIEW"), false);
  assert.equal(actionable("DATA_INCOMPLETE"), false);
  assert.equal(actionable("ON_GRADUATION_LIST"), false);
  assert.equal(actionable("WITHIN_NORMAL_DURATION"), false);
});

test("the confirmation counts the records", () => {
  assert.equal(aboutToReconcile(1), "You are about to reconcile 1 student record.");
  assert.equal(aboutToReconcile(1240), "You are about to reconcile 1,240 student records.");
});

test("a batch goes in steps, the last one shorter", () => {
  assert.deepEqual(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepEqual(chunks([], 200), []);
  assert.equal(chunks(Array.from({ length: 450 }, (_, i) => i), 200).map((c) => c.length).join(","), "200,200,50");
});

test("a batch reference is filed by year and number, and nothing else passes", () => {
  assert.equal(batchPath("RECON/2026/000014"), "2026/000014");
  assert.equal(batchPath(" RECON/2026/000014 "), "2026/000014");
  assert.equal(batchPath("RECON/2026/14"), null);
  assert.equal(batchPath("../2026/000014"), null);
});

test("the figures are cross-tabbed by the row they belong to", () => {
  const t = crossTab([
    { cohort: "2020/2021", recommendation: "SPILLOVER_YEAR_1", n: 3 },
    { cohort: "2020/2021", recommendation: "GRADUATION_CANDIDATE", n: 2 },
    { cohort: "2021/2022", recommendation: "GRADUATION_CANDIDATE", n: 5 },
  ], (r) => r.cohort);
  assert.equal(t.length, 2);
  assert.deepEqual(t[0].by, { SPILLOVER_YEAR_1: 3, GRADUATION_CANDIDATE: 2 });
  assert.equal(t[0].n, 5);
  assert.equal(t[1].n, 5);
});

test("the spillover columns are year 1 and 2, and a further year only where the limit allows one with students", () => {
  assert.deepEqual(spillColumns([]), ["SPILLOVER_YEAR_1", "SPILLOVER_YEAR_2"]);
  assert.deepEqual(spillColumns(["SPILLOVER_YEAR_1", "GRADUATION_CANDIDATE"]), ["SPILLOVER_YEAR_1", "SPILLOVER_YEAR_2"]);
  assert.deepEqual(spillColumns(["SPILLOVER_YEAR_3"]), ["SPILLOVER_YEAR_1", "SPILLOVER_YEAR_2", "SPILLOVER_YEAR_3"]);
});

test("a reason is a few words, never one", () => {
  assert.equal(reasonOk("reconcile"), false);
  assert.equal(reasonOk("spillover confirmed"), false);
  assert.equal(reasonOk("Registry review of the 2025/2026 registrations"), true);
});
