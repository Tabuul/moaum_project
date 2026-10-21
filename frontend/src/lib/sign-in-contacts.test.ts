import { test } from "node:test";
import assert from "node:assert/strict";
import { contactSource, fieldWord, figureOk, figureValue, lookupState } from "./sign-in-contacts.ts";

test("an unconfirmed contact says where it came from; a confirmed one says nothing", () => {
  assert.equal(contactSource(true, true), "SIGN_IN");
  assert.equal(contactSource(true, false), "UPLOAD");
  assert.equal(contactSource(true, undefined), "UPLOAD");
  assert.equal(contactSource(false, true), null);
  assert.equal(contactSource(undefined, undefined), null);
});

test("the field in words", () => {
  assert.equal(fieldWord("EMAIL"), "e-mail address");
  assert.equal(fieldWord("PHONE"), "phone number");
});

test("a figure is empty for none or a whole number from 1 to 10,000", () => {
  for (const ok of ["", "  ", "1", "50", "200", "10000"]) assert.equal(figureOk(ok), true, ok);
  for (const bad of ["0", "10001", "-5", "2.5", "fifty", "1e3"]) assert.equal(figureOk(bad), false, bad);
  assert.equal(figureValue(""), null);
  assert.equal(figureValue(" 200 "), 200);
});

test("a connection's day: refused, told, near the alert figure, or quiet", () => {
  assert.equal(lookupState({ numbers: 300, told: true, refused: true }, 50), "REFUSED");
  assert.equal(lookupState({ numbers: 60, told: true, refused: false }, 50), "TOLD");
  assert.equal(lookupState({ numbers: 25, told: false, refused: false }, 50), "NEAR");
  assert.equal(lookupState({ numbers: 24, told: false, refused: false }, 50), "QUIET");
  assert.equal(lookupState({ numbers: 999, told: false, refused: false }, null), "QUIET");
});
