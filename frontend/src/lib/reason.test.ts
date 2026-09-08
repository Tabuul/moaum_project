import { test } from "node:test";
import assert from "node:assert/strict";
import { reasonHeader } from "./reason.ts";

test("plain text is left alone, and Latin-1 letters survive", () => {
  assert.equal(reasonHeader('JAMB calls C101 "Medicine & Surgery"'), 'JAMB calls C101 "Medicine & Surgery"');
  assert.equal(reasonHeader("Approved by the Dean, José"), "Approved by the Dean, José");
});

test("typographic punctuation becomes its plain form", () => {
  assert.equal(reasonHeader("Mapped — from the CAPS download"), "Mapped - from the CAPS download");
  assert.equal(reasonHeader("Senate’s minute “S/2026/4”…"), "Senate's minute \"S/2026/4\"...");
});

test("what is left outside ISO-8859-1 is percent-encoded, not dropped", () => {
  assert.equal(reasonHeader("Fee of ₦5,000 waived"), "Fee of NGN 5,000 waived");
  assert.equal(reasonHeader("Note 你好"), "Note %E4%BD%A0%E5%A5%BD");
  for (const ch of reasonHeader("— ’ ₦ 你 → \n")) assert.ok((ch.codePointAt(0) ?? 0) <= 0xff, `not header-safe: ${ch}`);
});
