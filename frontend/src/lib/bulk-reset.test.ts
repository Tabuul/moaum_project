import { test } from "node:test";
import assert from "node:assert/strict";
import { linkable, needsApproval, notReset, partsOf, resultNote, resultWord, running, ticketsOf, whole, type OpItem } from "./bulk-reset.ts";

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

test("a request of more than 1,000 students is opened as parts of 1,000, read as a whole", () => {
  assert.deepEqual([1, 1000, 1001, 2500, 10000].map(partsOf), [1, 1, 2, 3, 10]);
  const series = [
    { id: "a", reference: "BPR/2026/000001", part: 1, status: "COMPLETED", total: 1000, succeeded: 990, failed: 10, processed: 1000, completed_at: "x" },
    { id: "b", reference: "BPR/2026/000002", part: 2, status: "PROCESSING", total: 1000, succeeded: 400, failed: 0, processed: 400, completed_at: null },
    { id: "c", reference: "BPR/2026/000003", part: 3, status: "PENDING", total: 500, succeeded: 0, failed: 0, processed: 0, completed_at: null },
  ];
  assert.deepEqual(whole({ status: "COMPLETED", total: 1000, succeeded: 990, failed: 10, processed: 1000, series }),
    { total: 2500, succeeded: 1390, failed: 10, processed: 1400, parts: 3, running: true, waiting: false });
  assert.equal(whole({ status: "COMPLETED", total: 4, succeeded: 4, failed: 0, processed: 4 }).running, false);
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
