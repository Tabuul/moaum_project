import { test } from "node:test";
import assert from "node:assert/strict";
import { isSummer, registrationSummer, semesterName, semesterText } from "./student-portal.ts";

test("V754: semester 3 of a session that had a Summer Semester is named Summer; any other keeps Third", () => {
  assert.equal(semesterName(3, true), "Summer");
  assert.equal(semesterName(3, false), "Third");
  assert.equal(semesterName(3), "Third");
  assert.equal(semesterName(1, true), "First");
  assert.equal(semesterName(2, true), "Second");
  assert.equal(semesterText(3), "Semester: Third");
});

test("V754: a semester is the Summer only as semester 3 of a session the results name among the Summer sessions", () => {
  const summers = ["2025/2026"];
  assert.equal(isSummer(summers, "2025/2026", 3), true);
  assert.equal(isSummer(summers, "2024/2025", 3), false);
  assert.equal(isSummer(summers, "2025/2026", 2), false);
  // an answer from before V754 names no Summer session
  assert.equal(isSummer(undefined, "2025/2026", 3), false);
  assert.equal(isSummer(null, "2025/2026", 3), false);
  assert.equal(semesterName(3, isSummer(summers, "2025/2026", 3)), "Summer");
  assert.equal(semesterName(3, isSummer(summers, "2023/2024", 3)), "Third");
});

test("V756: a registration is the Summer only where the API says so, on the answer or its registration, and only as semester 3", () => {
  assert.equal(registrationSummer({ semester: 3, summer: true }), true);
  assert.equal(registrationSummer({ semester: 3, registration: { summer: true } }), true);
  // a CCE or postgraduate third semester: the API answers false
  assert.equal(registrationSummer({ semester: 3, summer: false, registration: { summer: false } }), false);
  // an answer from before V756 names no Summer
  assert.equal(registrationSummer({ semester: 3 }), false);
  assert.equal(registrationSummer({ semester: 3, registration: null }), false);
  assert.equal(registrationSummer(null), false);
  assert.equal(registrationSummer(undefined), false);
  // never a first or second semester
  assert.equal(registrationSummer({ semester: 1, summer: true }), false);
  assert.equal(registrationSummer({ semester: 2, registration: { summer: true } }), false);
  assert.equal(semesterName(3, registrationSummer({ semester: 3, summer: true })), "Summer");
  assert.equal(semesterName(3, registrationSummer({ semester: 3, summer: false })), "Third");
});
