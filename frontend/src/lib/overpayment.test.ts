import { test } from "node:test";
import assert from "node:assert/strict";
import { overpaymentWords, refundAccountWords, type StudentOverpayment } from "./overpayment.ts";

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

test("a refund's account is shown by its last four digits only", () => {
  const r: StudentOverpayment = { ...carried, decision: "REFUND", to_session: null, reference: "RF-2026-0002", refund_state: "PROPOSED" };
  assert.equal(refundAccountWords(r), null);
  assert.equal(refundAccountWords(carried), null);
  assert.equal(refundAccountWords({ ...r, bank_name: "First Bank", account_name: "Invented Student", account_last4: "6789" }),
    "To be paid into First Bank, Invented Student, account ending 6789.");
});

test("a refund paid says when and with which transfer reference", () => {
  const r: StudentOverpayment = { ...carried, decision: "REFUND", to_session: null, reference: "RF-2026-0003", refund_state: "PAID", paid_on: "2026-10-17", paid_reference: "FT26290ABC" };
  assert.match(overpaymentWords(r).text, /has been paid to you on 17 October 2026 \(bank transfer reference FT26290ABC\)\./);
  assert.match(overpaymentWords({ ...r, paid_on: null, paid_reference: null }).text, /has been paid to you\./);
  assert.equal(refundAccountWords({ ...r, bank_name: "First Bank of Nigeria", account_name: "Ada", account_last4: "4579" }), "Paid into First Bank of Nigeria, Ada, account ending 4579.");
});
