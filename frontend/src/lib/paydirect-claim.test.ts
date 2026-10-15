import { test } from "node:test";
import assert from "node:assert/strict";
import { ASK_HEADERS, askRows, claimBody, claimProblems, lagosToday, paidDay, type ClaimForm } from "./paydirect-claim.ts";

const form = (over: Partial<ClaimForm> = {}): ClaimForm => ({ paymentLogId: "PL-55001", paidOn: "2026-10-14", amount: "", channel: "", note: "", ...over });

test("today is the Lagos calendar day, which runs an hour ahead of UTC", () => {
  assert.equal(lagosToday(new Date("2026-10-14T23:30:00Z")), "2026-10-15");
  assert.equal(lagosToday(new Date("2026-10-14T22:30:00Z")), "2026-10-14");
});

test("a receipt is its Payment Log Id and the day paid; the amount, where and a note are optional", () => {
  assert.deepEqual(claimProblems(form(), "2026-10-15"), {});
  assert.deepEqual(Object.keys(claimProblems(form({ paymentLogId: " 12 " }), "2026-10-15")), ["paymentLogId"]);
  assert.deepEqual(Object.keys(claimProblems(form({ paymentLogId: "x".repeat(41) }), "2026-10-15")), ["paymentLogId"]);
  assert.deepEqual(Object.keys(claimProblems(form({ paidOn: "" }), "2026-10-15")), ["paidOn"]);
});

test("the day paid is today or in the last four months, as the database holds it", () => {
  assert.deepEqual(claimProblems(form({ paidOn: "2026-10-15" }), "2026-10-15"), {});
  assert.ok(claimProblems(form({ paidOn: "2026-10-16" }), "2026-10-15").paidOn);
  assert.deepEqual(claimProblems(form({ paidOn: "2026-06-17" }), "2026-10-15"), {});   // 120 days before
  assert.ok(claimProblems(form({ paidOn: "2026-06-16" }), "2026-10-15").paidOn);       // 121 days before
});

test("an amount, when given, is more than nothing; the naira sign and commas are allowed", () => {
  assert.deepEqual(claimProblems(form({ amount: "₦53,488.42" }), "2026-10-15"), {});
  assert.ok(claimProblems(form({ amount: "0" }), "2026-10-15").amount);
  assert.ok(claimProblems(form({ amount: "fifty" }), "2026-10-15").amount);
  assert.ok(claimProblems(form({ note: "n".repeat(501) }), "2026-10-15").note);
});

test("the body sent is trimmed, the amount a number, blanks sent as nothing", () => {
  assert.deepEqual(claimBody("MOAUM-FEE-990002-2222", form({ paymentLogId: " PL-55001 ", amount: "₦1,200.50", channel: "QUICKTELLER", note: "  " })), {
    reference: "MOAUM-FEE-990002-2222", paymentLogId: "PL-55001", paidOn: "2026-10-14", amount: 1200.5, channel: "QUICKTELLER", note: null,
  });
  assert.equal(claimBody("R", form()).amount, null);
  assert.equal(claimBody("R", form()).channel, null);
});

test("the ask list's rows follow its headers, with the receipt's details where the payer gave them", () => {
  const rows = askRows([
    { reference: "MOAUM-FEE-1", payer: "DOE, Jane", number: "BSU/22/1", due: "53488.42", opened_at: "2026-10-13T09:00:00Z", payment_log_id: "PL-1", paid_on: "2026-10-13", paid_amount: "53488.42", channel: "BANK" },
    { reference: "MOAUM-APP-2", payer: null, number: null, due: 2300, opened_at: null, payment_log_id: null, paid_on: null, paid_amount: null, channel: null },
  ]);
  assert.equal(rows[0].length, ASK_HEADERS.length);
  assert.deepEqual(rows[0].slice(0, 4), ["MOAUM-FEE-1", "DOE, Jane", "BSU/22/1", 53488.42]);
  assert.match(String(rows[0][4]), /13 Oct 2026, 10:00/);   // Lagos time
  assert.deepEqual(rows[0].slice(5), ["PL-1", "2026-10-13", 53488.42, "At a bank"]);
  assert.deepEqual(rows[1], ["MOAUM-APP-2", "", "", 2300, "", "", "", "", ""]);
});

test("the day paid reads as the receipt prints it, the same day in any time zone", () => {
  assert.equal(paidDay("2026-10-15"), "15 Oct 2026");
  assert.equal(paidDay("2026-01-01"), "1 Jan 2026");
  assert.equal(paidDay(null), "");
});
