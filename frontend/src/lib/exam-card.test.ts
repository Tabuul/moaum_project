import { test } from "node:test";
import assert from "node:assert/strict";
import { examCardStatusLabel, examCardSummary } from "./exam-card.ts";

test("the card's summary counts every paper and names the GST/EPS ones among them", () => {
  assert.equal(examCardSummary({ count: 6, units: 18, gstEpsCount: 2 }), "6 papers · 18 credit units · including 2 GST/EPS");
  assert.equal(examCardSummary({ count: 1, units: 3, gstEpsCount: 0 }), "1 paper · 3 credit units");
});

test("the card's state reads in a word", () => {
  assert.equal(examCardStatusLabel({ available: true, code: null }), "Available");
  assert.equal(examCardStatusLabel({ available: false, code: "EXAM_CARD_NOT_PAID" }), "Fees not paid");
  assert.equal(examCardStatusLabel({ available: false, code: "EXAM_CARD_NOT_SUBMITTED" }), "Register your courses");
  assert.equal(examCardStatusLabel({ available: false, code: "EXAM_CARD_NO_COURSES" }), "Not available");
});
