import { test } from "node:test";
import assert from "node:assert/strict";
import { accountWord, failureWords, methodsFor, reasonOk, resetBody } from "./password-reset.ts";

test("a reason is ten characters or more, blanks not counted", () => {
  assert.equal(reasonOk("forgot"), false);
  assert.equal(reasonOk("          forgot   "), false);
  assert.equal(reasonOk("Student forgot portal password."), true);
});

test("the default credential only where the record allows it; a temporary password only on a ticket", () => {
  assert.deepEqual(methodsFor({ eligible: false }, false).map((m) => [m.method, m.enabled]), [["DEFAULT", false], ["LINK", true], ["TEMPORARY", false]]);
  assert.deepEqual(methodsFor({ eligible: true }, true).map((m) => [m.method, m.enabled]), [["DEFAULT", true], ["LINK", true], ["TEMPORARY", true]]);
});

test("the unlock choice travels only with the default credential", () => {
  assert.deepEqual(resetBody("DEFAULT", "  Student forgot portal password.  ", "t-1", false), { method: "DEFAULT", reason: "Student forgot portal password.", ticket: "t-1", unlock: false });
  assert.deepEqual(resetBody("LINK", "Student forgot portal password.", null, true), { method: "LINK", reason: "Student forgot portal password.", ticket: null });
});

test("a failure is said in the desk's words, the server's reason kept, never a stack trace", () => {
  assert.equal(failureWords({ status: 404 }), "STUDENT ACCOUNT NOT FOUND.");
  assert.equal(failureWords({ status: 403 }), "YOU ARE NOT AUTHORIZED TO RESET THIS STUDENT'S PASSWORD.");
  assert.equal(failureWords({ status: 422, code: "SUPPORT_CAPABILITY", detail: "Your posting does not carry resetting student passwords for this student." }),
    "YOU ARE NOT AUTHORIZED TO RESET THIS STUDENT'S PASSWORD.");
  assert.equal(failureWords({ status: 422, code: "RESET_NO_MATRIC", detail: "THIS STUDENT DOES NOT HAVE A VALID MATRICULATION NUMBER." }), "THIS STUDENT DOES NOT HAVE A VALID MATRICULATION NUMBER.");
  assert.equal(failureWords({ status: 500, detail: "java.lang.NullPointerException at ..." }), "PASSWORD RESET COULD NOT BE COMPLETED. PLEASE TRY AGAIN OR CONTACT THE ICT DIRECTOR.");
  assert.equal(failureWords(null), "PASSWORD RESET COULD NOT BE COMPLETED. PLEASE TRY AGAIN OR CONTACT THE ICT DIRECTOR.");
  // a database's own words never reach the desk
  assert.equal(failureWords({ status: 409, code: "DB_FOREIGN_KEY", detail: "insert or update on table \"support_action\" violates foreign key constraint" }),
    "PASSWORD RESET COULD NOT BE COMPLETED. PLEASE TRY AGAIN OR CONTACT THE ICT DIRECTOR.");
  assert.equal(failureWords({ status: 422, code: "SUPPORT_TICKET_REQUIRED", detail: "A temporary password is issued on the student's ticket." }), "A temporary password is issued on the student's ticket.");
  assert.equal(failureWords({ status: 400, title: "Bad Request" }), "SAY WHY THE PASSWORD IS RESET, IN TEN CHARACTERS OR MORE.");
});

test("the account in a few words", () => {
  assert.deepEqual(accountWord({ has_account: true, locked: true, status: "ACTIVE" }), ["LOCKED (failed sign-ins)", "bad"]);
  assert.deepEqual(accountWord({ has_account: false, locked: false, status: "ACTIVE" }), ["NOT YET OPENED", "grey"]);
  assert.deepEqual(accountWord({ has_account: true, locked: false, status: "ACTIVE" }), ["ACTIVE", "ok"]);
  assert.deepEqual(accountWord({ has_account: true, locked: false, status: "GRADUATED" }), ["GRADUATED", "info"]);
});
