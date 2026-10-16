import { test } from "node:test";
import assert from "node:assert/strict";
import { FIGURES, isApproved, reasonWords, semesterWord, statusLine } from "./registration-approval.ts";

test("while approval is automatic the student never reads 'with your Head of Department'", () => {
  assert.equal(statusLine("SUBMITTED", "AUTO_APPROVAL", null), "Submitted");
  assert.equal(statusLine("SUBMITTED", "AUTO_APPROVAL", "REG_FEES_NOT_STATED: the school fees are not stated"), "Requires review");
  assert.equal(statusLine("SUBMITTED", "HOD_APPROVAL_REQUIRED", null), "Submitted, with your Head of Department");
  assert.equal(statusLine("APPROVED", "AUTO_APPROVAL", null), "Approved");
  assert.equal(statusLine("LOCKED", "HOD_APPROVAL_REQUIRED", null), "Approved");
  assert.equal(statusLine("DRAFT", "AUTO_APPROVAL", null), "Draft");
  assert.equal(statusLine(null, "AUTO_APPROVAL", null), "Not registered");
  assert.equal(isApproved("APPROVED"), true);
  assert.equal(isApproved("SUBMITTED"), false);
});

test("a server's reason is read without its code", () => {
  assert.equal(reasonWords("REG_COURSE_NOT_OFFERED: CSC 401 is not offered to this student's programme"), "CSC 401 is not offered to this student's programme");
  assert.equal(reasonWords("the 1st semester school fees are not fully paid"), "The 1st semester school fees are not fully paid");
  assert.equal(reasonWords(null), "");
});

test("every figure opens its own list", () => {
  assert.equal(new Set(FIGURES.map((f) => f.kind)).size, FIGURES.length);
  assert.deepEqual(FIGURES.map((f) => f.label), ["Total registered", "Auto-approved", "Approved by a Head", "Pending", "Requires review", "Reset", "Re-registered", "Exam cards printed or downloaded"]);
  assert.equal(semesterWord(2), "Second semester");
  assert.equal(semesterWord(null), "Every semester");
});
