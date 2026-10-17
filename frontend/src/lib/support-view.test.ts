import { test } from "node:test";
import assert from "node:assert/strict";
import { readSupportView, safeBack, timeLeft } from "./support-view.ts";

const state = { viewId: "v1", studentId: "s1", name: "DOE, John", matricNo: "MOAU/SC/CSC/24/1", endsAt: "2026-10-17T12:30:00Z", back: "/helpdesk/students/s1" };

test("the view's particulars are read however deep the cookie encoded them", () => {
  assert.deepEqual(readSupportView(JSON.stringify(state)), state);
  assert.deepEqual(readSupportView(encodeURIComponent(JSON.stringify(state))), state);
  assert.deepEqual(readSupportView(encodeURIComponent(encodeURIComponent(JSON.stringify(state)))), state);
  assert.equal(readSupportView(""), null);
  assert.equal(readSupportView("not json"), null);
  assert.equal(readSupportView(JSON.stringify({ name: "no ids" })), null);
});

test("the way back stays on this portal", () => {
  assert.equal(safeBack("/helpdesk/students/s1", "/helpdesk"), "/helpdesk/students/s1");
  assert.equal(safeBack("https://evil.example", "/helpdesk"), "/helpdesk");
  assert.equal(safeBack("//evil.example", "/helpdesk"), "/helpdesk");
  assert.equal(safeBack(null, "/helpdesk"), "/helpdesk");
});

test("the time left, in minutes and seconds", () => {
  const ends = "2026-10-17T12:30:00Z";
  assert.equal(timeLeft(ends, Date.parse("2026-10-17T12:00:00Z")), "30:00");
  assert.equal(timeLeft(ends, Date.parse("2026-10-17T12:29:05Z")), "0:55");
  assert.equal(timeLeft(ends, Date.parse("2026-10-17T12:31:00Z")), "0:00");
});
