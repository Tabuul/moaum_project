import { test } from "node:test";
import assert from "node:assert/strict";
import { bankWatchGroups, type MissingPayment } from "./bank-watch.ts";

const pay = (reference: string, channel: string | null, day: string, amount: number): MissingPayment =>
  ({ reference, channel, day, amount, purpose: null, payer: null, number: null, confirmed_at: `${day}T10:00:00Z` });

test("the missing payments are grouped by day and channel, the oldest day first, amounts summed to the kobo", () => {
  const groups = bankWatchGroups([
    pay("A", "Card · Paystack", "2026-10-12", 1000.1), pay("B", "Bank transfer", "2026-10-11", 500),
    pay("C", "Card · Paystack", "2026-10-12", 2000.2), pay("D", null, "2026-10-12", 30),
  ]);
  assert.deepEqual(groups, [
    { channel: "Bank transfer", day: "2026-10-11", payments: 1, amount: 500 },
    { channel: "Card · Paystack", day: "2026-10-12", payments: 2, amount: 3000.3 },
    { channel: "No channel", day: "2026-10-12", payments: 1, amount: 30 },
  ]);
});

test("nothing missing is no group", () => {
  assert.deepEqual(bankWatchGroups([]), []);
});
