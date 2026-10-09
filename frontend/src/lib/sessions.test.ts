import { test } from "node:test";
import assert from "node:assert/strict";
import { intakeSession } from "./sessions.ts";

const row = (name: string, state: string) => ({ name, state });

test("the intake is the first planned session after the current one", () => {
  assert.equal(intakeSession([row("2026/2027", "PLANNED"), row("2025/2026", "CURRENT"), row("2024/2025", "CLOSED")]), "2026/2027");
  // a later planned session is not the intake while the next one is still to come
  assert.equal(intakeSession([row("2027/2028", "PLANNED"), row("2026/2027", "PLANNED"), row("2025/2026", "CURRENT")]), "2026/2027");
  // a planned session older than the current one is not it either
  assert.equal(intakeSession([row("2025/2026", "CURRENT"), row("2023/2024", "PLANNED")]), "2025/2026");
});

test("with nothing planned after it, the current session is the intake", () => {
  assert.equal(intakeSession([row("2025/2026", "CURRENT"), row("2024/2025", "CLOSED")]), "2025/2026");
  // no session current: the latest that is not planned stands for it
  assert.equal(intakeSession([row("2026/2027", "PLANNED"), row("2025/2026", "CLOSED")]), "2026/2027");
  assert.equal(intakeSession([row("2026/2027", "PLANNED"), row("2025/2026", "PLANNED")]), "2026/2027");
  assert.equal(intakeSession([]), "2026/2027");
});
