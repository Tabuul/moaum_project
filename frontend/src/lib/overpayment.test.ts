import { test } from "node:test";
import assert from "node:assert/strict";
import { overpaymentWords, type StudentOverpayment } from "./overpayment.ts";

const carried: StudentOverpayment = { session: "2026/2027", amount: "20000.00", decision: "CARRY", to_session: "2027/2028",
  reference: "MOAUM-CF-X-2026-2027", refund_state: null, decided_at: "2026-10-17 09:00:00+01" };

test("an excess carried into the next session says where it counts", () => {
  const w = overpaymentWords(carried);
  assert.equal(w.title, "₦20,000 carried into 2027/2028");
  assert.match(w.text, /You paid ₦20,000 more than your 2026\/2027 school fees\. It counts as school fees already paid in 2027\/2028 \(reference MOAUM-CF-X-2026-2027\)\./);
});

test("a refund says how far it has gone", () => {
  const r: StudentOverpayment = { ...carried, decision: "REFUND", to_session: null, reference: "RF-2026-0001", amount: 15000.5, refund_state: "PROPOSED" };
  assert.equal(overpaymentWords(r).title, "Refund of ₦15,000.50 raised");
  assert.match(overpaymentWords(r).text, /waiting for the Bursary's approval/);
  assert.match(overpaymentWords({ ...r, refund_state: "APPROVED" }).text, /approved and waiting to be paid/);
  assert.equal(overpaymentWords({ ...r, refund_state: "PAID" }).title, "Refund of ₦15,000.50 paid");
  assert.match(overpaymentWords({ ...r, refund_state: "REJECTED" }).text, /will decide again/);
});
