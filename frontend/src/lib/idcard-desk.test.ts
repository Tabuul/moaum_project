import { test } from "node:test";
import assert from "node:assert/strict";
import { actionsFor, cardStateWord, eligibilityWords, eventWord, reasonWord } from "./idcard-desk.ts";

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
  assert.match(ok.lines[2], /released by the scheme in force; 1 earlier session paid in full/);
  const no = eligibilityWords({ eligible: false, reasons: ["Student photograph is missing"] });
  assert.equal(no.kind, "bad");
  assert.deepEqual(no.lines, ["Student photograph is missing"]);
  assert.ok(!JSON.stringify(ok).toLowerCase().includes("clearance"));
  assert.deepEqual(actionsFor({ eligible: true, reasons: [] }, null, true), { print: true, collect: false, replace: false, end: false });
  assert.deepEqual(actionsFor({ eligible: true, reasons: [] }, { state: "PRINTED" }, true), { print: true, collect: true, replace: true, end: true });
  assert.deepEqual(actionsFor({ eligible: false, reasons: ["x"] }, { state: "ISSUED" }, true), { print: false, collect: false, replace: false, end: true });
  assert.deepEqual(actionsFor({ eligible: true, reasons: [] }, { state: "ISSUED" }, false), { print: false, collect: false, replace: false, end: false });
});
