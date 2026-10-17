import { test } from "node:test";
import assert from "node:assert/strict";
import { evidenceRefusal, readSwapFilters, reasonOk, refusalParts, swapQuery, EMPTY_SWAP_FILTERS } from "./payment-swaps.ts";

test("a refusal is read as its code and its words", () => {
  assert.deepEqual(refusalParts("SWAP_SAME_STUDENT: Original and target student cannot be the same."), { code: "SWAP_SAME_STUDENT", words: "Original and target student cannot be the same." });
  assert.deepEqual(refusalParts("SWAP_NOT_VERIFIED: the payment is not confirmed"), { code: "SWAP_NOT_VERIFIED", words: "The payment is not confirmed" });
  assert.deepEqual(refusalParts("no code here"), { code: "", words: "no code here" });
});

test("a reason says why, not a single word", () => {
  assert.equal(reasonOk("wrong"), false);
  assert.equal(reasonOk("swap"), false);
  assert.equal(reasonOk("   fix   "), false);
  assert.equal(reasonOk("Paid on a classmate's matric number"), true);
  assert.equal(reasonOk("short reason"), false);
});

test("the filters are checked and only what is set is sent", () => {
  assert.deepEqual(readSwapFilters({ status: "completed", session: "2025/2026", from: "2026-10-01", to: "yesterday", q: " 12939 " }),
    { status: "COMPLETED", q: "12939", session: "2025/2026", from: "2026-10-01", to: "" });
  assert.deepEqual(readSwapFilters({ status: "DELETED", session: "2025" }), EMPTY_SWAP_FILTERS);
  assert.equal(swapQuery({ ...EMPTY_SWAP_FILTERS, status: "PENDING_APPROVAL" }, { page: 2, all: false }), "status=PENDING_APPROVAL&page=2");
});

test("evidence is a PDF, JPEG or PNG of up to 5 MB", () => {
  assert.equal(evidenceRefusal({ type: "application/pdf", size: 1000 }), null);
  assert.equal(evidenceRefusal({ type: "image/png", size: 6 * 1024 * 1024 }), "Evidence is up to 5 MB.");
  assert.equal(evidenceRefusal({ type: "application/msword", size: 10 }), "Evidence is a PDF, JPEG or PNG file.");
});
