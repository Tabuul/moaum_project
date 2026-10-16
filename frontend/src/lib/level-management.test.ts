import { test } from "node:test";
import assert from "node:assert/strict";
import { levelBody, levelPath, reasonOk, refusalWords, registrationWarning, ruleWord, type LevelState } from "./level-management.ts";

const state = (over: Partial<LevelState> = {}): LevelState => ({
  student: { id: "s", full_name: "DOE, John", matric_no: "MOAU/SC/CSC/24/12345", jamb_reg_no: null, application_no: null, faculty: null, department: null, programme: null,
    programme_type: null, admission_session: "2024/2025", current_level: 300, status: "ACTIVE", study_mode: null, admission_route: null, entry_mode: "UTME", entry_level: 100 },
  session: "2026/2027", semester: 1,
  options: { currentLevel: 300, entryLevel: 100, finalLevel: 400, postgraduate: false, levels: [100, 200, 300, 400], otherLevels: [100, 200, 400], nextLevel: 400,
    status: "ACTIVE", progressRefusal: null, correctRefusal: null },
  position: null, registrations: [], history: [], mayProgress: true, mayCorrect: true, scope: "The University",
  ...over,
});

test("a refusal reads without its code, and a reason needs ten characters", () => {
  assert.equal(refusalWords("LEVEL_AT_FINAL: the student is at the programme's final level (400)"), "The student is at the programme's final level (400)");
  assert.equal(refusalWords(null), "");
  assert.equal(reasonOk("too short"), false);
  assert.equal(reasonOk("Left at 300 after promotion"), true);
});

test("progress sends the next level the server named; a correction the level chosen; both the level the screen showed", () => {
  assert.deepEqual(levelBody("PROGRESS", state(), null, " Left at 300 after promotion ", "t1", false),
    { action: "PROGRESS", level: 400, expected: 300, reason: "Left at 300 after promotion", ticket: "t1", acknowledgeRegistration: false });
  assert.deepEqual(levelBody("CORRECTION", state(), 200, "Uploaded at the wrong level", "", true),
    { action: "CORRECTION", level: 200, expected: 300, reason: "Uploaded at the wrong level", ticket: null, acknowledgeRegistration: true });
});

test("the session's registration is warned of, never another session's", () => {
  assert.equal(registrationWarning(state({ registrations: [{ session: "2025/2026", semester: 2, level: 300, status: "APPROVED", courses: 9 }] })), null);
  const w = registrationWarning(state({ registrations: [{ session: "2026/2027", semester: 1, level: 300, status: "APPROVED", courses: 9 }] }));
  assert.match(w ?? "", /^This student currently has a course registration for 2026\/2027 First Semester \(approved, 300 Level, 9 courses\)/);
  assert.match(w ?? "", /not deleted or changed/);
});

test("the levels on the record run one per session, and each change is named by how it came about", () => {
  assert.deepEqual(levelPath([
    { session: "2025/2026", semester: 2, level: 300, status: "APPROVED", courses: 8 },
    { session: "2024/2025", semester: 1, level: 200, status: "LOCKED", courses: 9 },
    { session: "2025/2026", semester: 1, level: 300, status: "APPROVED", courses: 9 },
  ]), [{ session: "2024/2025", level: 200 }, { session: "2025/2026", level: 300 }]);
  assert.equal(ruleWord("LEVEL_PROGRESS"), "Progressed (ICT Support)");
  assert.equal(ruleWord("LEVEL_SPILLOVER"), "Spillover correction");
  assert.equal(ruleWord("PROMOTE"), "Registry decision");
});
