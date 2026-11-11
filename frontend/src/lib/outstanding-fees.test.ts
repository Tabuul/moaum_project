import { test } from "node:test";
import assert from "node:assert/strict";
import { attentionRows, breakdownRows, payWords, settledRows, summaryWords, type OutstandingFees, type OutstandingRow } from "./outstanding-fees.ts";

const row = (patch: Partial<OutstandingRow>): OutstandingRow => ({
  kind: "PAST", session: "2021/2022", semester: 1, period: "First semester", level: 100, description: "School fees", due: 50000, paid: 0, balance: 50000,
  status: "UNPAID", reference: null, payable: true, payAmount: 50000, door: "HISTORICAL", ...patch,
});
const data = (rows: OutstandingRow[], patch: Partial<OutstandingFees> = {}): OutstandingFees => {
  const owed = rows.filter((r) => Number(r.balance ?? 0) > 0);
  return {
    session: "2026/2027", graduated: true, onlinePayment: true, windowOpen: true, assessedFrom: "2021/2022", entrySession: "2021/2022", unassessedBefore: false, rows,
    summary: { sessions: new Set(owed.map((r) => r.session)).size, periods: owed.length, items: owed.length, outstanding: owed.reduce((a, r) => a + Number(r.balance), 0), pending: 0, paid: rows.reduce((a, r) => a + Number(r.paid), 0) },
    ...patch,
  };
};

test("the rows shown first are what is owed, pending or being assessed; the settled ones are kept for the breakdown", () => {
  const rows = [row({}), row({ semester: 2, period: "Second semester", paid: 20000, balance: 0, status: "PAID", payable: false, payAmount: null }),
    row({ session: "2022/2023", status: "PAYMENT_PENDING", reference: { reference: "MOAUM-FEE-X-0001", session: "2022/2023", amount: 50000, expires_at: "2099-01-01T00:00:00Z" } }),
    row({ session: "2023/2024", due: null, balance: null, status: "BEING_ASSESSED", payable: false, payAmount: null })];
  assert.deepEqual(attentionRows(rows).map((r) => r.session + r.status), ["2021/2022UNPAID", "2022/2023PAYMENT_PENDING", "2023/2024BEING_ASSESSED"]);
  assert.deepEqual(settledRows(rows).map((r) => r.status), ["PAID"]);
});

test("the summary line counts sessions and periods, and says when nothing is owed", () => {
  assert.equal(summaryWords(data([row({}), row({ session: "2022/2023", semester: 2, period: "Second semester", due: 20000, balance: 20000, payAmount: 20000 })])),
    "₦70,000 outstanding across 2 sessions (2 fee periods).");
  assert.equal(summaryWords(data([row({ paid: 50000, balance: 0, status: "PAID" })])), "No outstanding school fees.");
  const d = data([row({ due: null, balance: null, status: "BEING_ASSESSED" })]);
  d.summary.beingAssessed = 1;
  assert.equal(summaryWords(d), "Nothing owed on what is assessed; 1 period still being assessed.");
  const p = data([row({})]);
  p.summary.pending = 50000;
  assert.equal(summaryWords(p), "₦50,000 outstanding across 1 session (1 fee period); ₦50,000 awaits a payment started.");
});

test("Pay now says what it settles, names the pending reference, and says why none can be made", () => {
  assert.equal(payWords(row({}), { onlinePayment: true, windowOpen: true }), "Pay ₦50,000");
  assert.equal(payWords(row({ status: "PAYMENT_PENDING", reference: { reference: "MOAUM-FEE-X-0001", session: "2021/2022", amount: 50000, expires_at: "2099-01-01T00:00:00Z" } }), { onlinePayment: true, windowOpen: true }), "Pay reference MOAUM-FEE-X-0001");
  assert.equal(payWords(row({ paid: 50000, balance: 0, status: "PAID" }), { onlinePayment: true, windowOpen: true }), null);
  assert.equal(payWords(row({ due: null, balance: null, status: "BEING_ASSESSED" }), { onlinePayment: true, windowOpen: true }), null);
  assert.equal(payWords(row({}), { onlinePayment: false, windowOpen: true }), "Settled with the Bursary");
  assert.equal(payWords(row({ kind: "CURRENT", door: "CURRENT", session: "2026/2027" }), { onlinePayment: true, windowOpen: false }), "Payment window closed");
});

test("the breakdown rows carry S/N first, amounts as numbers and the status words", () => {
  const r = breakdownRows([row({}), row({ semester: 2, period: "Second semester", due: 20000, paid: 5000, balance: 15000, status: "PARTIALLY_PAID" })]);
  assert.deepEqual(r[0], [1, "2021/2022", "First semester", 100, "School fees", 50000, 0, 50000, "Unpaid", ""]);
  assert.deepEqual(r[1].slice(5), [20000, 5000, 15000, "Partially paid", ""]);
});
