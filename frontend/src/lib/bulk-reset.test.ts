import { test } from "node:test";
import assert from "node:assert/strict";
import { linkable, needsApproval, notReset, resultNote, resultWord, running, ticketsOf, type OpItem } from "./bulk-reset.ts";

const item = (over: Partial<OpItem>): OpItem => ({
  student_id: "s", name: "ZZ, Student", number: null, programme: null, faculty: null, level: 100, status: "RESET", failure_code: null, failure_words: null,
  ticket_number: null, ...over,
});

test("an operation waits for approval only above the figure, and never when there is none", () => {
  assert.equal(needsApproval(201, 200), true);
  assert.equal(needsApproval(200, 200), false);
  assert.equal(needsApproval(5000, null), false);
  assert.equal(needsApproval(5000, undefined), false);
});

test("only a pending or processing operation is still running", () => {
  assert.deepEqual(["AWAITING_APPROVAL", "PENDING", "PROCESSING", "COMPLETED", "REJECTED"].map(running), [false, true, true, false, false]);
});

test("the link goes to the students refused for want of a matriculation number, once", () => {
  const items = [
    item({ student_id: "a", status: "FAILED", failure_code: "RESET_NO_MATRIC" }),
    item({ student_id: "b", status: "FAILED", failure_code: "RESET_NO_MATRIC", link_sent_at: "2026-10-19T10:00:00Z", link_to: "j***@mail.com" }),
    item({ student_id: "c", status: "FAILED", failure_code: "OUT_OF_SCOPE" }),
    item({ student_id: "d" }),
  ];
  assert.deepEqual(linkable(items).map((i) => i.student_id), ["a"]);
  // a student sent a link is not tried again
  assert.deepEqual(notReset(items).map((i) => i.student_id), ["a", "c"]);
});

test("a retry keeps each student's login ticket", () => {
  assert.deepEqual(ticketsOf([item({ student_id: "a", ticket_id: "t1" }), item({ student_id: "b" })]), { a: "t1" });
});

test("a result reads in words, with what was done since", () => {
  assert.equal(resultWord(item({})), "Reset");
  assert.equal(resultWord(item({ status: "FAILED", failure_code: "RESET_NO_MATRIC", link_sent_at: "x" })), "Reset link sent");
  assert.equal(resultNote(item({ status: "FAILED", failure_words: "MATRICULATION NUMBER NOT AVAILABLE", link_failure: "NO E-MAIL OR PHONE ON RECORD" })),
    "MATRICULATION NUMBER NOT AVAILABLE · No link sent: NO E-MAIL OR PHONE ON RECORD");
  assert.equal(resultNote(item({ ticket_resolved_at: "x" })), "Ticket resolved");
});
