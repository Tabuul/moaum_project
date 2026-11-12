import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bandWords, creditWords, isLive, isTransferPurpose, letterRoute, madeWords, naira, nextActionWords, openForBalance, overpaidWords, owedNow, payLabel,
  showTransferCard, sourceWord, type TransferPayment,
} from "./transfer-fee.ts";

/** a student who paid ₦10,000 on the old portal toward a ₦20,000 fee, the application with the new department: ₦10,000 owed */
const PART: TransferPayment = {
  applicationId: "a1", state: "FROM_OK", stageLabel: "With new department", feeDue: 20000, portalPaid: 0, oldPortalPaid: 10000, paidTotal: 10000,
  balance: 10000, excess: 0, payments: 1, settled: false, pending: false, openReference: null, openAmount: null, openExpiresAt: null,
  band: "PART_PAID", nextAction: "PAY_BALANCE",
};
const NONE_PAID: TransferPayment = { ...PART, state: "APPLIED", stageLabel: "Awaiting payment", oldPortalPaid: 0, paidTotal: 0, balance: 20000, payments: 0, band: "NOT_PAID", nextAction: "PAY_NOW" };
const FULL: TransferPayment = { ...PART, state: "REG_OK", portalPaid: 10000, paidTotal: 20000, balance: 0, payments: 2, settled: true, band: "SETTLED_IN_PARTS", nextAction: "AWAIT_APPROVAL" };
/** one of the above, changed */
const as = (base: TransferPayment, x: Partial<TransferPayment>): TransferPayment => ({ ...base, ...x });

test("the button reads PAY NOW before anything is paid, PAY OUTSTANDING BALANCE after a part payment, nothing once paid", () => {
  assert.equal(payLabel(NONE_PAID), "PAY NOW");
  assert.equal(payLabel(PART), "PAY OUTSTANDING BALANCE");
  assert.equal(payLabel(FULL), null);
  // overpaid: nothing owed, no button
  assert.equal(payLabel(as(FULL, { paidTotal: 30000, excess: 10000, band: "OVERPAID" })), null);
  // the fee not stated: nothing to pay yet
  assert.equal(payLabel(as(NONE_PAID, { feeDue: null, balance: null, band: "FEE_NOT_STATED" })), null);
  // a declined or effected application takes no payment
  assert.equal(payLabel({ ...PART, state: "DECLINED" }), null);
  assert.equal(payLabel({ ...PART, state: "EFFECTED" }), null);
  // a closed application (declined, not recommended, withdrawn) owes nothing: no button, whatever it carries
  assert.equal(payLabel(as(NONE_PAID, { state: "DECLINED", balance: 0, band: "CLOSED", nextAction: "NONE" })), null);
  assert.equal(payLabel(as(PART, { state: "NOT_RECOMMENDED", band: "CLOSED" })), null);
  assert.equal(payLabel(as(PART, { band: "CLOSED" })), null);
  assert.equal(openForBalance(as(PART, { band: "CLOSED", openReference: "TRF-1", openAmount: 10000 })), null);
  // the Senate route is live too
  assert.equal(payLabel({ ...PART, state: "APPROVED" }), "PAY OUTSTANDING BALANCE");
  // money as the server sends it, numbers or strings
  assert.equal(payLabel({ ...PART, paidTotal: "10000.00", balance: "10000.00" }), "PAY OUTSTANDING BALANCE");
});

test("live includes RECOMMENDED and APPROVED; the closed states are not live", () => {
  for (const s of ["APPLIED", "FROM_OK", "TO_OK", "REG_OK", "RECOMMENDED", "APPROVED"]) assert.equal(isLive(s), true, s);
  for (const s of ["EFFECTED", "DECLINED", "WITHDRAWN", "NOT_RECOMMENDED", "", null, undefined]) assert.equal(isLive(s), false, String(s));
  assert.equal(owedNow({ state: "DECLINED", balance: 10000 }), 0);
  assert.equal(owedNow({ state: "TO_OK", balance: "10000.00" }), 10000);
  assert.equal(owedNow({ state: "TO_OK", balance: "10000.00", band: "CLOSED" }), 0);
});

test("an open reference is paid only while it is for what is owed now", () => {
  assert.deepEqual(openForBalance({ ...PART, openReference: "TRF-1", openAmount: "10000.00" }), { reference: "TRF-1", amount: 10000 });
  // drawn for the whole fee before the old-portal payment was linked: the button draws the one for the balance
  assert.equal(openForBalance({ ...PART, openReference: "TRF-1", openAmount: 20000 }), null);
  assert.equal(openForBalance({ ...FULL, openReference: "TRF-1", openAmount: 0 }), null);
});

test("the band and the payments in words", () => {
  assert.deepEqual(bandWords("PART_PAID"), ["Part paid", "warn"]);
  assert.deepEqual(bandWords("OVERPAID"), ["Overpaid", "info"]);
  assert.deepEqual(bandWords("CLOSED"), ["Closed — nothing owed", "grey"]);
  assert.equal(bandWords("PAID_IN_FULL")[1], "ok");
  assert.equal(bandWords("NOT_PAID")[1], "bad");
  assert.equal(bandWords("SOMETHING_NEW")[0], "something new");
  assert.equal(bandWords(null)[0], "—");
  assert.deepEqual(madeWords("AWAITING_BANK"), ["Awaiting the bank", "info"]);
  assert.deepEqual(madeWords("LINKED"), ["Counted", "ok"]);
  assert.deepEqual(madeWords("USED"), ["Used by a restored transfer", "info"]);
  assert.equal(sourceWord("OLD_PORTAL"), "Old portal");
  assert.equal(sourceWord("PORTAL"), "This portal");
});

test("the next action says what to pay and what follows", () => {
  assert.equal(nextActionWords(NONE_PAID), "Pay the transfer fee of ₦20,000. Your current department acts once a payment is confirmed.");
  assert.equal(nextActionWords(PART), "Pay the outstanding balance of ₦10,000. The Academic Office gives its final approval once the whole fee is paid.");
  assert.equal(nextActionWords(as(PART, { nextAction: "COMPLETE_PAYMENT", pending: true, openReference: "TRF-1", openAmount: 10000 })),
    "Pay reference TRF-1 (₦10,000), or wait while the bank confirms a payment you have made.");
  assert.equal(nextActionWords(FULL), "Nothing to pay: the offices are considering your application.");
  assert.match(nextActionWords({ ...PART, nextAction: "AWAIT_APPROVAL" }), /Pay the ₦10,000 balance before the final approval/);
  assert.equal(nextActionWords({ ...FULL, state: "EFFECTED", nextAction: "NONE" }), "None: the transfer is complete.");
  // a closed application: nothing to do and nothing owed
  assert.equal(nextActionWords(as(NONE_PAID, { state: "DECLINED", balance: 0, band: "CLOSED", nextAction: "NONE" })), "None: the application was declined; nothing is owed.");
  assert.equal(nextActionWords(as(PART, { state: "NOT_RECOMMENDED", balance: 0, band: "CLOSED", nextAction: "NONE" })), "None: the application was not recommended; nothing is owed.");
  assert.match(nextActionWords({ ...PART, state: "APPROVED" }), /given effect on the register once the whole fee is paid/);
});

test("an overpayment is said without a refund promised", () => {
  assert.equal(overpaidWords({ excess: 5000 }), "You paid ₦5,000 more than the fee; the Bursary will contact you.");
  assert.equal(overpaidWords({ excess: 0 }), null);
  assert.doesNotMatch(overpaidWords({ excess: "5000.00" }) ?? "", /refund/i);
});

test("old-portal credit before an application", () => {
  assert.equal(creditWords({ total: 10000 }, "below"), "You paid ₦10,000 on the old portal toward a transfer — apply below; it counts toward the fee.");
  assert.match(creditWords({ total: "10000.00" }, "page") ?? "", /apply on the transfer page/);
  assert.match(creditWords({ total: 10000 }, "later") ?? "", /once you apply/);
  assert.equal(creditWords({ total: 0 }, "below"), null);
  assert.equal(creditWords(null, "below"), null);
});

test("the dashboard card: a live application, credit, or one closed this session", () => {
  const apps = [{ id: "a1", state: "FROM_OK", session: "2026/2027" }];
  assert.equal(showTransferCard(null, "2026/2027"), false);
  assert.equal(showTransferCard({ applications: [], fee: 20000, payment: null, credit: null }, "2026/2027"), false);
  assert.equal(showTransferCard({ applications: apps, fee: 20000, payment: PART, credit: null }, "2026/2027"), true);
  assert.equal(showTransferCard({ applications: [], fee: 20000, payment: null, credit: { total: 10000, payments: [] } }, "2026/2027"), true);
  const done = { ...FULL, state: "EFFECTED", nextAction: "NONE" };
  assert.equal(showTransferCard({ applications: [{ id: "a1", state: "EFFECTED", session: "2026/2027" }], fee: 20000, payment: done }, "2026/2027"), true);
  assert.equal(showTransferCard({ applications: [{ id: "a1", state: "EFFECTED", session: "2024/2025" }], fee: 20000, payment: done }, "2026/2027"), false);
});

test("a transfer reference is told from a school-fee one; the letter follows the route taken", () => {
  assert.equal(isTransferPurpose("Inter-departmental transfer to B.Sc. Computer Science"), true);
  assert.equal(isTransferPurpose("School fees 2026/2027"), false);
  assert.equal(isTransferPurpose("GST fee 2026/2027"), false);
  assert.equal(isTransferPurpose(null), false);
  assert.equal(letterRoute({ acad_at: "2026-11-01T10:00:00Z" }), "DESKS");
  assert.equal(letterRoute({ acad_at: null }), "SENATE");
  assert.equal(naira("20000.00"), "₦20,000");
});

test("the fee not yet stated: nothing to pay, and said so", () => {
  const unstated = as(NONE_PAID, { feeDue: null, balance: null, band: "FEE_NOT_STATED" });
  assert.equal(nextActionWords(unstated), "Wait for the Bursary to state the transfer fee; you pay it then.");
  assert.equal(openForBalance(as(unstated, { openReference: "TRF-1", openAmount: 0 })), null);
});
