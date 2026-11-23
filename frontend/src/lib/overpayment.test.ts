import { test } from "node:test";
import assert from "node:assert/strict";
import { excessCase, excessStaffWords, excessWords, overpaymentWords, refundAccountWords, type StudentExcess, type StudentOverpayment } from "./overpayment.ts";

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

test("an excess credited to the wallet is said as a wallet credit the student applies on the Wallet page, or asks to be refunded", () => {
  const w: StudentOverpayment = { ...carried, session: "2025/2026", amount: "28605.00", decision: "WALLET", to_session: null, reference: "LOR/2026/000007" };
  const words = overpaymentWords(w);
  assert.equal(words.title, "₦28,605 credited to your wallet");
  assert.equal(words.text, "You paid ₦28,605 more than your 2025/2026 school fees. The Bursary credited it to your wallet (reference LOR/2026/000007). "
    + "The Wallet page shows how much of it is still there and what it was used for.");
  assert.match(words.text, /Wallet page/);
  // a record of what was done: it stays true after the student has applied the money or had it refunded, so it never says the money is still there
  assert.doesNotMatch(words.text, /\bis on your wallet\b/);
  // nothing uses the money by itself: the student applies it
  assert.doesNotMatch(`${words.title} ${words.text}`, /automatic/i);
  assert.doesNotMatch(words.title, /Refund/, "a wallet credit is never worded as a refund");
  assert.equal(refundAccountWords({ ...w, bank_name: "First Bank", account_last4: "6789" }), null, "no bank account is asked for a wallet credit");
});

test("school fees paid above the charge and not yet decided are said by what the Bursary's list knows of them", () => {
  const f: StudentExcess = { session: "2025/2026", excess: "28605.00", excessDecided: 0, excessRemaining: "28605.00", excessRequested: 0 };
  // nothing left to decide: nothing is said
  assert.equal(excessWords({ session: "2025/2026" }), null);
  assert.equal(excessWords({ ...f, excessDecided: "28605.00", excessRemaining: 0 }), null);
  assert.equal(excessCase({ ...f, excessRemaining: "0.50" }), null, "an excess counts from one naira");
  // a semester of the session still to be charged, stated or registered: the money is that session's own
  for (const hold of ["SEMESTER_NOT_CHARGED", "SEMESTER_NOT_STATED", "SPILLOVER_SEMESTER"]) {
    const ahead = excessWords({ ...f, excessCause: "PORTAL_TWICE", excessHolds: [hold], excessRequested: "28605" });
    assert.equal(ahead?.title, "₦28,605 paid ahead", hold);
    assert.equal(ahead?.text, "You have paid ₦28,605 more than the fees charged to you so far for 2025/2026. It counts towards the rest of this session's fees when they are charged.");
  }
  // a late fee that may still count against it
  for (const hold of ["LATE_FEE_LAPSED", "LATE_FEE_POSSIBLE"]) {
    assert.deepEqual(excessWords({ ...f, excessCause: "PORTAL_TWICE", excessHolds: [hold] }),
      { kind: "info", title: "₦28,605 above the fees shown", text: "A late fee may count against it. The Bursary will tell you if any of it is to come back to you." }, hold);
  }
  assert.equal(excessCase({ ...f, excessHolds: ["LATE_FEE_POSSIBLE", "SEMESTER_NOT_STATED"] }), "AHEAD", "a semester still to be charged is said first");
  // a wallet credit requested
  assert.deepEqual(excessWords({ ...f, excessCause: "PORTAL_TWICE", excessRequested: "28605.00" }),
    { kind: "info", title: "₦28,605 paid above your fees", text: "The Bursary is crediting it to your wallet; you will be told when it is there." });
  // paid twice, nothing holding it
  for (const cause of ["PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE"]) {
    const twice = excessWords({ ...f, excessCause: cause, excessHolds: [] });
    assert.equal(twice?.title, "₦28,605 paid above your fees", cause);
    assert.equal(twice?.text, "You paid your 2025/2026 school fees more than once. The Bursary will credit ₦28,605 to your wallet for your next school fees, or refund it. "
      + "There is nothing for you to do until you are told.");
    assert.doesNotMatch(twice?.text ?? "", /automatic/i);
  }
  // any other cause or hold, or none known yet (a new overpayment the list has not worked out)
  const checking = { kind: "info", title: "₦28,605 paid above the fees stated", text: "The Bursary is checking it against your fees and will tell you what happens to it." };
  assert.deepEqual(excessWords(f), checking);
  assert.deepEqual(excessWords({ ...f, excessCause: "ABOVE_FEE_LINE" }), checking);
  assert.deepEqual(excessWords({ ...f, excessCause: "PART_PAYMENTS", excessHolds: [] }), checking);
  assert.deepEqual(excessWords({ ...f, excessCause: "PORTAL_TWICE", excessHolds: ["BANK_CHECK"] }), checking, "paid twice but held for the bank check");
  // the amount is what is left of the excess, never the whole of it
  assert.equal(excessWords({ ...f, excess: "57210", excessDecided: "28605", excessRemaining: "28605.50", excessCause: "PORTAL_TWICE" })?.title, "₦28,605.50 paid above your fees");
});

test("the staff pop-up says the same cases of an excess about the student and names the desk", () => {
  const f: StudentExcess = { session: "2025/2026", excess: "28605.00", excessDecided: 0, excessRemaining: "28605.00", excessRequested: 0 };
  assert.equal(excessStaffWords({ session: "2025/2026" }), null);
  assert.equal(excessStaffWords({ ...f, excessRemaining: 0 }), null);
  assert.equal(excessStaffWords({ ...f, excessCause: "PORTAL_TWICE", excessHolds: [] }), "Paid twice on the portal: the Bursary credits it to the wallet or refunds it — Overpaid school fees desk.");
  assert.equal(excessStaffWords({ ...f, excessCause: "OLD_TWICE" }), "Paid twice on the old portal: the Bursary credits it to the wallet or refunds it — Overpaid school fees desk.");
  assert.match(excessStaffWords({ ...f, excessCause: "PORTAL_TWICE", excessHolds: ["SEMESTER_NOT_STATED"] }) ?? "", /^Paid ahead/);
  assert.match(excessStaffWords({ ...f, excessHolds: ["LATE_FEE_POSSIBLE"] }) ?? "", /^A late fee may count against it/);
  assert.equal(excessStaffWords({ ...f, excessCause: "PORTAL_TWICE", excessRequested: 28605 }), "A wallet credit is requested: another Bursary officer approves it — Overpaid school fees desk.");
  assert.match(excessStaffWords({ ...f, excessCause: "ABOVE_FEE_LINE" }) ?? "", /^Not decided: the Bursary is checking/);
  assert.match(excessStaffWords(f) ?? "", /^Not decided/);
  for (const text of [excessStaffWords({ ...f, excessCause: "PORTAL_TWICE" }), excessStaffWords(f)]) assert.doesNotMatch(text ?? "", /automatic/i);
});
