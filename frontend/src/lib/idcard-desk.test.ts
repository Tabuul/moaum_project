import { test } from "node:test";
import assert from "node:assert/strict";
import { actionsFor, cardStateWord, eligibilityWords, eventWord, reasonWord, BLOOD_GROUPS } from "./idcard-desk.ts";

test("the card's states and the replacement reasons read in words (V605)", () => {
  assert.deepEqual(cardStateWord(null), ["Not printed", "grey"]);
  assert.deepEqual(cardStateWord("PRINTED"), ["Printed — awaiting collection", "warn"]);
  assert.deepEqual(cardStateWord("ISSUED"), ["Issued — in force", "ok"]);
  assert.deepEqual(cardStateWord("SOMETHING"), ["Something", "grey"]);
  assert.equal(reasonWord("MATRIC_CORRECTION"), "Matriculation correction");
  assert.equal(reasonWord(null), "");
  assert.equal(eventWord({ action: "ID_CARD_PRINTED", from_state: null, to_state: "PRINTED", note: null, at: "", actor: null, actor_office: null }), "Printed");
});

test("the eligibility reading never names clearance, and the actions follow the state", () => {
  const ok = eligibilityWords({ eligible: true, reasons: [], fees: { session: "2025/2026", stated: true, released: true, earlier: [{ session: "2024/2025", due: 1, paid: 1, balance: 0, paid_in_full: true }], short: [] } });
  assert.equal(ok.title, "ID card eligible");
  // V699: the first card on the matriculation number alone; the photograph and the fees said, never held
  assert.deepEqual(ok.lines, ["Valid matriculation number", "First card: issued on the matriculation number"]);
  const warned = eligibilityWords({ eligible: true, reasons: [], warnings: ["Student photograph is missing: the card prints with a blank frame"] });
  assert.equal(warned.kind, "ok");
  assert.deepEqual(warned.warnings, ["Student photograph is missing: the card prints with a blank frame"]);
  const no = eligibilityWords({ eligible: false, reasons: ["Matriculation number not yet issued"] });
  assert.equal(no.kind, "bad");
  assert.deepEqual(no.lines, ["Matriculation number not yet issued"]);
  const repl = eligibilityWords({ eligible: true, reasons: [], replacement: { needed: true, fee: 2000, paid: false, payment: null, openReference: null, openAmount: null } });
  assert.equal(repl.kind, "bad");
  assert.equal(repl.lines[1], "Replacement fee of ₦2,000.00 not paid — the student pays it on their portal (Identity Card)");
  const paid = eligibilityWords({ eligible: true, reasons: [], replacement: { needed: true, fee: 2000, paid: true, payment: "MOAUM-FEE-1", openReference: null, openAmount: null } });
  assert.deepEqual([paid.kind, paid.lines[1]], ["ok", "Replacement fee paid (MOAUM-FEE-1)"]);
  assert.ok(!JSON.stringify(ok).toLowerCase().includes("clearance"));
  assert.deepEqual(actionsFor({ eligible: true, reasons: [] }, null, true), { print: true, collect: false, replace: false, end: false });
  assert.deepEqual(actionsFor({ eligible: true, reasons: [] }, { state: "PRINTED" }, true), { print: true, collect: true, replace: true, end: true });
  assert.deepEqual(actionsFor({ eligible: false, reasons: ["x"] }, { state: "ISSUED" }, true), { print: false, collect: false, replace: false, end: true });
  assert.deepEqual(actionsFor({ eligible: true, reasons: [] }, { state: "ISSUED" }, false), { print: false, collect: false, replace: false, end: false });
  // V699: a replacement waits on its fee; the live card printed again does not
  const unpaid = { needed: true, fee: 2000, paid: false, payment: null, openReference: null, openAmount: null };
  assert.deepEqual(actionsFor({ eligible: true, reasons: [], replacement: unpaid }, { state: "ISSUED" }, true), { print: true, collect: false, replace: false, end: true });
  assert.deepEqual(actionsFor({ eligible: true, reasons: [], replacement: unpaid }, null, true), { print: false, collect: false, replace: false, end: false });
  assert.deepEqual(actionsFor({ eligible: true, reasons: [], replacement: { ...unpaid, paid: true, payment: "MOAUM-FEE-1" } }, { state: "ISSUED" }, true), { print: true, collect: false, replace: true, end: true });
});

test("the blood groups the card prints (V622)", () => {
  assert.deepEqual([...BLOOD_GROUPS], ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]);
});
