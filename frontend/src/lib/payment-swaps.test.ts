import { test } from "node:test";
import assert from "node:assert/strict";
import { evidenceRefusal, isOutstanding, movesWallet, outstandingWords, readSwapFilters, reasonOk, refusalParts, swapQuery, walletOwesAfter, EMPTY_SWAP_FILTERS, EVENT_WORDS, FLAG_WORDS, KIND_WORDS } from "./payment-swaps.ts";

test("an old-portal outstanding-fees payment is told apart from school fees (V660)", () => {
  assert.equal(isOutstanding({ kind: "OUTSTANDING_FEES" }), true);
  assert.equal(isOutstanding({ kind: "SCHOOL_FEES", purpose: "OUTSTANDING FEES (legacy) · semester 2" }), false);
  // a swap row has no kind: its purpose says it
  assert.equal(isOutstanding({ purpose: "OUTSTANDING FEES (legacy) · semester 2" }), true);
  assert.equal(isOutstanding({ purpose: "School fees (legacy) · semester 2" }), false);
  assert.equal(isOutstanding({}), false);
  // a swap row's kind is the swap's (SWAP or REVERSAL): its purpose decides
  assert.equal(isOutstanding({ kind: "SWAP", purpose: "OUTSTANDING FEES (legacy) · semester 2" }), true);
  assert.equal(isOutstanding({ kind: "REVERSAL", purpose: "School fees 2025/2026" }), false);
  assert.equal(KIND_WORDS.OUTSTANDING_FEES, "Old-portal outstanding fees");
});

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

test("V708: an outstanding-fees payment credited to the wallet moves its wallet credit; one verified moves its desk record", () => {
  assert.equal(movesWallet({ outstandingStatus: "CREDITED" }), true);
  assert.equal(movesWallet({ outstandingStatus: "VERIFIED" }), false);
  assert.equal(movesWallet({ outstandingStatus: "WAITING" }), false);
  assert.equal(movesWallet(null), false);
  assert.match(outstandingWords("CREDITED"), /wallet credit moves with it/);
  assert.match(outstandingWords("VERIFIED"), /record on the Outstanding fees payments desk moves with it/);
  assert.match(outstandingWords("WAITING"), /never against the session's school fees/);
  assert.equal(EVENT_WORDS.PAYMENT_WALLET_CREDIT_MOVED, "Wallet credit moved to the student it belongs to");
});

test("V710: a credited payment already used leaves the wallet owing; the swap says how much", () => {
  assert.equal(walletOwesAfter({ outstandingStatus: "CREDITED", walletCredit: { owesAfter: 1000 } }), 1000);
  assert.equal(walletOwesAfter({ outstandingStatus: "CREDITED", walletCredit: { owesAfter: 0 } }), 0);
  assert.equal(walletOwesAfter({ outstandingStatus: "VERIFIED", walletCredit: { owesAfter: 500 } }), 0);
  assert.equal(walletOwesAfter(null), 0);
  assert.match(FLAG_WORDS.FROM_WALLET_OWES, /their wallet now owes it/);
});
