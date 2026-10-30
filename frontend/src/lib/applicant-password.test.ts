import { test } from "node:test";
import assert from "node:assert/strict";
import { accountState, BULK_OUTCOME, bulkNumbers, bulkProblem, defaultNumberWords, newPasswordProblem, pgAccountState, PG_RESET_METHOD, reasonProblem, RESET_METHOD } from "./applicant-password.ts";

test("a new password is eight characters or more, typed twice alike", () => {
  assert.equal(newPasswordProblem("short", "short"), "A password is eight characters or more.");
  assert.equal(newPasswordProblem("long enough one", "long enough on"), "Type the new password twice, the same both times.");
  assert.equal(newPasswordProblem("long enough one", "long enough one"), null);
});

test("the desk says the account's state in words", () => {
  assert.deepEqual(accountState({ locked: true, must_change: true }), ["Locked (failed sign-ins)", "bad"]);
  assert.deepEqual(accountState({ locked: false, mustChange: true }), ["Change pending at the next sign-in", "warn"]);
  assert.deepEqual(accountState({ locked: false, firstSignIn: true }), ["First sign-in not yet made", "grey"]);
  assert.deepEqual(accountState({ locked: false }), ["Active", "ok"]);
});

test("V706: an account reset to its number says so, in the search's rows and in the account alike", () => {
  assert.deepEqual(accountState({ locked: false, must_change: true, on_default: true }), ["Reset to the number, change pending", "warn"]);
  assert.deepEqual(accountState({ locked: false, mustChange: true, firstSignIn: true }), ["Reset to the number, change pending", "warn"]);
  assert.deepEqual(accountState({ locked: false, must_change: false, on_default: true }), ["First sign-in not yet made", "grey"]);
  assert.equal(defaultNumberWords("JAMB"), "JAMB number");
  assert.equal(defaultNumberWords("APPLICATION"), "application number");
  assert.equal(defaultNumberWords(null), "JAMB number");
});

test("V706: the postgraduate desk says the account's state and the reset's method in words", () => {
  assert.deepEqual(pgAccountState({ locked: true, must_change: true }), ["Locked (failed sign-ins)", "bad"]);
  assert.deepEqual(pgAccountState({ locked: false, mustChange: true }), ["Reset to the application number, change pending", "warn"]);
  assert.deepEqual(pgAccountState({ locked: false }), ["Active", "ok"]);
  assert.equal(PG_RESET_METHOD.DEFAULT_NUMBER, "Back to the application number");
});

test("a reset's reason is ten characters or more, and its method is said in words", () => {
  assert.equal(reasonProblem(" forgot "), "Say why the password is reset, in ten characters or more.");
  assert.equal(reasonProblem("Applicant forgot password; identity checked by phone"), null);
  assert.equal(RESET_METHOD.TEMPORARY_PASSWORD, "Temporary password");
  assert.equal(RESET_METHOD.DEFAULT_NUMBER, "Back to the JAMB or application number");
});

test("V710: a pasted list gives its numbers one each, and is checked for size", () => {
  assert.deepEqual(bulkNumbers("97109990001AB\r\n  APP/97/710012 \n\n one@example.test, two@example.test;PG/26/000001\tS00220260204082731"),
    ["97109990001AB", "APP/97/710012", "one@example.test", "two@example.test", "PG/26/000001", "S00220260204082731"]);
  assert.deepEqual(bulkNumbers("  \n "), []);
  assert.equal(bulkProblem([]), "Paste the numbers to reset, one to a line.");
  assert.equal(bulkProblem(["a"]), null);
  assert.equal(bulkProblem(Array.from({ length: 2001 }, (_, i) => String(i))), "At most 2,000 numbers at a time; this list has 2,001.");
  assert.deepEqual(BULK_OUTCOME.AMBIGUOUS, ["More than one applicant", "warn"]);
  assert.equal(PG_RESET_METHOD.RESET_LINK, "Reset link sent");
});
