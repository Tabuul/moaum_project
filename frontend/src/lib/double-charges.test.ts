import { test } from "node:test";
import assert from "node:assert/strict";
import { DOUBLE_CHARGE_HEADERS, atStake, doubleChargeRow, notReceivedOk, payrefOf, pnrPath, verdictWord, type DoubleCharge } from "./double-charges.ts";

const g: DoubleCharge = {
  student_id: "s", number: "MOAU/AR/THA/24/72627", name: "Aondokator, Justice Katyo", programme_code: "C00066", session: "2025/2026",
  purpose: "School fees (legacy) · semester 1", paid_on: "2026-03-23", amount: "85294", payments: 2,
  refs: ["MOAUM-LEG-MOAUARTHA2472627-2025-2026-S1", "MOAUM-LEG-MOAUARTHA2472627-2025-2026-S1-PR20260323062528751"],
  payrefs: ["PR20260323061111111", "PR20260323062528751"], check_id: null, verdict: null, evidence: null, checked_by: null, checked_at: null, open_requests: 0,
};

test("a withdrawal reference is filed by year and number, and nothing else passes", () => {
  assert.equal(pnrPath("PNR/2026/000014"), "2026/000014");
  assert.equal(pnrPath("PNR/2026/14"), null);
  assert.equal(pnrPath("RECON/2026/000014"), null);
});

test("the records named as never received are some of the group, never all", () => {
  assert.equal(notReceivedOk([g.refs[1]], g.refs), true);
  assert.equal(notReceivedOk([], g.refs), false);
  assert.equal(notReceivedOk(g.refs, g.refs), false);
  assert.equal(notReceivedOk(["MOAUM-LEG-OTHER"], g.refs), false);
});

test("what is at stake is every payment beyond the first", () => {
  assert.equal(atStake(g), 85294);
  assert.equal(atStake({ amount: 1000, payments: 3 }), 2000);
});

test("an unchecked group is said so; each record shows its payment number", () => {
  assert.equal(verdictWord(null)[0], "Not checked with the bank");
  assert.equal(verdictWord("RECEIVED")[1], "ok");
  assert.equal(payrefOf(g, g.refs[1]), "PR20260323062528751");
  assert.equal(payrefOf({ refs: ["A"], payrefs: [""] }, "A"), "—");
});

test("the Excel row follows its headers", () => {
  const row = doubleChargeRow(g);
  assert.equal(row.length, DOUBLE_CHARGE_HEADERS.length);
  assert.equal(row[5], 85294);
  assert.equal(row[9], "Not checked with the bank");
});
