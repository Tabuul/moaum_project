import { test } from "node:test";
import assert from "node:assert/strict";
import { accountState, newPasswordProblem, reasonProblem, RESET_METHOD } from "./applicant-password.ts";

test("a new password is eight characters or more, typed twice alike", () => {
  assert.equal(newPasswordProblem("short", "short"), "A password is eight characters or more.");
  assert.equal(newPasswordProblem("long enough one", "long enough on"), "Type the new password twice, the same both times.");
  assert.equal(newPasswordProblem("long enough one", "long enough one"), null);
});

test("the desk says the account's state in words", () => {
  assert.deepEqual(accountState({ locked: true, must_change: true }), ["Locked (failed sign-ins)", "bad"]);
  assert.deepEqual(accountState({ locked: false, mustChange: true }), ["Temporary password, change pending", "warn"]);
  assert.deepEqual(accountState({ locked: false, firstSignIn: true }), ["First sign-in not yet made", "grey"]);
  assert.deepEqual(accountState({ locked: false }), ["Active", "ok"]);
});

test("a reset's reason is ten characters or more, and its method is said in words", () => {
  assert.equal(reasonProblem(" forgot "), "Say why the password is reset, in ten characters or more.");
  assert.equal(reasonProblem("Applicant forgot password; identity checked by phone"), null);
  assert.equal(RESET_METHOD.TEMPORARY_PASSWORD, "Temporary password");
});
