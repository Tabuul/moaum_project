import { test } from "node:test";
import assert from "node:assert/strict";
import { ELIGIBILITY_WORD, mayRemind, remindWords } from "./gst.ts";

test("V691: the list of students registered without paying is one the desks offer", () => {
  assert.equal(ELIGIBILITY_WORD.UNPAID_REGISTERED, "Registered, GST fee unpaid");
});

test("V691: the office itself, the Bursary and super remind; the other office and the Registry do not", () => {
  assert.equal(mayRemind("gst", "GST"), true);
  assert.equal(mayRemind("GST", "GST"), true);
  assert.equal(mayRemind("eps", "EPS"), true);
  assert.equal(mayRemind("bursar", "GST"), true);
  assert.equal(mayRemind("bursar", "EPS"), true);
  assert.equal(mayRemind("super", "EPS"), true);
  assert.equal(mayRemind("eps", "GST"), false);
  assert.equal(mayRemind("gst", "EPS"), false);
  assert.equal(mayRemind("registrar", "GST"), false);
  assert.equal(mayRemind(null, "GST"), false);
});

test("V691: the answers of several reminder calls are added together, in words", () => {
  const w = remindWords([{ counts: { SENT: 3, ALREADY_TODAY: 1 } }, { counts: { SENT: 2, NOT_UNPAID: 1, FEE_NOT_STATED: 0 } }]);
  assert.equal(w.title, "5 reminded · 1 reminded already today · 1 paid since or no longer owing");
  assert.equal(w.kind, "warn");
  assert.equal(w.sent, 5);
});

test("V691: all told is ok; nobody told is bad", () => {
  assert.deepEqual(remindWords([{ counts: { SENT: 2 } }]), { title: "2 reminded", kind: "ok", sent: 2 });
  assert.equal(remindWords([{ counts: { ALREADY_TODAY: 4 } }]).kind, "bad");
  assert.deepEqual(remindWords([{ counts: {} }]), { title: "Nobody was reminded.", kind: "bad", sent: 0 });
});
