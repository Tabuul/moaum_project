import { test } from "node:test";
import assert from "node:assert/strict";
import { categoryWords, courseCategory, courseStatus, inUniversityOrder, refusalCode, refusalText, searchQuery, unitsAfter, addedAsLabel } from "./course-order.ts";

test("the server's category is read as sent", () => {
  assert.equal(courseCategory({ category: "ELECTIVE", entryType: "CARRYOVER" }), "ELECTIVE");
});

test("an entry's category follows registration.entry_category", () => {
  assert.equal(courseCategory({ entryType: "CARRYOVER", kind: "Core" }), "CARRY_OVER");
  assert.equal(courseCategory({ entryType: "DEFERRED" }), "CARRY_OVER");
  assert.equal(courseCategory({ entryType: "CURRENT", kind: "GST" }), "GST");
  assert.equal(courseCategory({ entry_type: "CURRENT", gst_eps: true }), "GST");
  assert.equal(courseCategory({ entryType: "ELECTIVE", kind: "Core" }), "ELECTIVE");
  assert.equal(courseCategory({ entryType: "CURRENT", kind: "Elective" }), "CORE");
  assert.equal(courseCategory({ entryType: "BORROWED" }), "CORE");
  // the programme's basis decides core or elective, over the entry's type and the course's kind
  assert.equal(courseCategory({ basis: "Elective", kind: "Core" }), "ELECTIVE");
  assert.equal(courseCategory({ basis: "Core", kind: "Elective", entryType: "ELECTIVE" }), "CORE");
  assert.equal(courseCategory({ kind: "Elective" }), "ELECTIVE");
  assert.equal(courseCategory({ basis: "Carryover", kind: "Core" }), "CARRY_OVER");
});

test("carry-over, GST, core, elective — the server's order kept within each", () => {
  const rows = [
    { code: "ECO 211", entryType: "ELECTIVE" }, { code: "ECO 201", entryType: "CURRENT" }, { code: "GST 211", entryType: "GST" },
    { code: "ECO 101", entryType: "CARRYOVER" }, { code: "ECO 203", entryType: "CURRENT" }, { code: "BIO 101", entryType: "DEFERRED" },
  ];
  assert.deepEqual(inUniversityOrder(rows).map((r) => r.code), ["ECO 101", "BIO 101", "GST 211", "ECO 201", "ECO 203", "ECO 211"]);
});

test("a GST/EPS carry-over is listed under carry-over, named with its office", () => {
  assert.equal(categoryWords({ entryType: "CARRYOVER", kind: "GST", courseCode: "GST 301" }), "Carry-over · GST");
  assert.equal(categoryWords({ entryType: "CARRYOVER", kind: "GST", courseCode: "EPS 302" }), "Carry-over · EPS");
  assert.equal(categoryWords({ entryType: "CARRYOVER", kind: "Core", courseCode: "CSC 201" }), "Carry-over");
  assert.equal(categoryWords({ entryType: "GST", kind: "GST", courseCode: "GST 401" }), "GST");
  assert.equal(courseCategory({ entryType: "CARRYOVER", kind: "GST" }), "CARRY_OVER");
});

test("the engine's refusal is read without its code", () => {
  const r = "REG_HIGHER_LEVEL: ECO 301 is taken at 300 Level; you are at 200 Level";
  assert.equal(refusalCode(r), "REG_HIGHER_LEVEL");
  assert.equal(refusalText(r), "ECO 301 is taken at 300 Level; you are at 200 Level");
  assert.equal(refusalCode(null), null);
});

test("a found course's status", () => {
  assert.deepEqual(courseStatus({ refusal: null, on_registration: false }), { label: "Available", ok: true });
  assert.deepEqual(courseStatus({ refusal: null, on_registration: true }), { label: "Already added", ok: false });
  assert.equal(courseStatus({ refusal: "REG_ALREADY_PASSED: Course has already been successfully completed", on_registration: false }).label, "Already passed");
  assert.equal(courseStatus({ refusal: "REG_RESULT_AWAITED: Result pending", on_registration: false }).label, "Result pending");
  assert.equal(courseStatus({ refusal: "SOMETHING_NEW: words", on_registration: false }).label, "Not available");
  assert.deepEqual(courseStatus({ refusal: null, on_registration: false, recommended: true, category: "CARRY_OVER" }), { label: "Added automatically", ok: false });
  assert.deepEqual(courseStatus({ on_registration: false, recommended: true, category: "CORE" }), { label: "On your list", ok: true });
  // V512: a GST/EPS course, a carry-over too, waits for the GST fee
  assert.deepEqual(courseStatus({ on_registration: false, recommended: true, category: "CARRY_OVER", gstHeld: "GST_PAYMENT_REQUIRED: pay" }), { label: "GST/EPS payment required", ok: false });
});

test("the search asks with the term trimmed and capped", () => {
  const q = new URLSearchParams(searchQuery({ session: "2025/2026", semester: 1, q: "  eco   301 ", level: 300, category: "CORE" }));
  assert.equal(q.get("q"), "eco 301");
  assert.equal(q.get("level"), "300");
  assert.equal(q.get("category"), "CORE");
  assert.equal(q.get("dept"), null);
  assert.equal(new URLSearchParams(searchQuery({ session: "2025/2026", semester: 2, q: "x".repeat(90) })).get("q")!.length, 60);
});

test("units after an add", () => {
  assert.deepEqual(unitsAfter(20, 3, 24), { total: 23, over: false });
  assert.deepEqual(unitsAfter(22, 3, 24), { total: 25, over: true });
  assert.equal(addedAsLabel("UNIVERSITY_GST"), "University GST course");
  assert.equal(addedAsLabel(null), null);
});
