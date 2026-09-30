import { test } from "node:test";
import assert from "node:assert/strict";
import { amountInLink, collectionRows, interswitchLink, isQuicktellerCheckout, quicktellerLink } from "./quickteller.ts";

test("the link carries the portal's own reference in cid, and the amount in Interswitch's form", () => {
  assert.equal(quicktellerLink("https://quickteller.com/bsum", "MOAUM-FEE-CSC21001-0042", 51000, true),
    "https://quickteller.com/bsum?cid=MOAUM-FEE-CSC21001-0042&amount=51000");
  assert.equal(quicktellerLink("https://quickteller.com/bsum", "MOAUM-APP-000123-0042", "2300.00", false),
    "https://quickteller.com/bsum?cid=MOAUM-APP-000123-0042");
  assert.equal(quicktellerLink("https://quickteller.com/chsbsu", "MOAUM-FEE-MED21001-0007", "48000.50", true),
    "https://quickteller.com/chsbsu?cid=MOAUM-FEE-MED21001-0007&amount=48000.50");
});

test("an amount is whole naira without decimals, else two places — as the server writes it", () => {
  assert.equal(amountInLink(51000), "51000");
  assert.equal(amountInLink("51000.00"), "51000");
  assert.equal(amountInLink("48000.5"), "48000.50");
  assert.equal(amountInLink("x"), "");
});

test("a pay link is an Interswitch page and nothing else", () => {
  assert.equal(interswitchLink("https://quickteller.com/bsum"), "https://quickteller.com/bsum");
  assert.equal(interswitchLink("HTTPS://Quickteller.com/bsum/"), "https://quickteller.com/bsum");
  assert.equal(interswitchLink("https://www.quickteller.com/chsbsu"), "https://www.quickteller.com/chsbsu");
  for (const bad of ["http://quickteller.com/bsum", "https://quickteller.com.evil.ng/bsum", "https://evilquickteller.com/bsum",
    "https://quickteller.com/bsum?cid=1", "https://pay.example.com/bsum", "javascript:alert(1)", "", null]) {
    assert.equal(interswitchLink(bad), null, String(bad));
  }
});

test("the checkout's answer for Quickteller is told apart from a card gateway's", () => {
  assert.equal(isQuicktellerCheckout({ gateway: "paydirect", url: "https://quickteller.com/bsum?cid=X", reference: "X", amount: 1 }), true);
  assert.equal(isQuicktellerCheckout({ gateway: "paystack", url: "https://checkout.paystack.com/x" }), false);
  assert.equal(isQuicktellerCheckout(null), false);
});

test("the collections report is read with Interswitch's own headers", () => {
  const rows = collectionRows([
    "Payment Log Id,Customer Reference,Payment Reference,Amount,Payment Date,Channel,Customer Name",
    "1234567,moaum-fee-csc21001-0042,FBN|WEB|MX1|30-09-2026|000001,\"51,000.00\",09/30/2026 15:00,WEB,\"Okeke, Chidi\"",
    "1234568,,FBN|WEB|MX1|30-09-2026|000002,100.00,09/30/2026 15:01,WEB,Nobody",
  ].join("\n"));
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0], { prn: "MOAUM-FEE-CSC21001-0042", amount: "51000.00", rrn: "1234567", paidAt: "09/30/2026 15:00", channel: "WEB", payer: "Okeke, Chidi" });
});

test("the collections report is read without a header, in the column order the screen names", () => {
  const rows = collectionRows("MOAUM-APP-000123-0042\t₦2,300\tRRN-1\n\nMOAUM-APP-000124-0043,2300,RRN-2,2026-09-30,Bank Branch,Ada");
  assert.deepEqual(rows.map((r) => [r.prn, r.amount, r.rrn, r.channel, r.payer]), [
    ["MOAUM-APP-000123-0042", "2300", "RRN-1", "", ""],
    ["MOAUM-APP-000124-0043", "2300", "RRN-2", "Bank Branch", "Ada"],
  ]);
  assert.deepEqual(collectionRows("   \n  "), []);
});
