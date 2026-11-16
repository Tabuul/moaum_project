import { test } from "node:test";
import assert from "node:assert/strict";
import {
  answerLines, cameWord, codeTaken, decideProblem, heldCount, heldWords, includable, mayDecide, mayRequest, notIncludable, onRecord, reasonProblem, removable,
  removalBody, semesterChoices, semesterWord, stateWord, studentNumber, takenOff, type StudentRegistration,
} from "./registration-corrections.ts";

test("the student is known by the matriculation number, else by the admission number while there is none", () => {
  assert.deepEqual(studentNumber({ matric: "MOAU/SC/CSC/24/1", matricNo: "MOAU/SC/CSC/24/1", admissionNo: "202412345678AB" }), ["Matriculation number", "MOAU/SC/CSC/24/1"]);
  assert.deepEqual(studentNumber({ matric: "202412345678AB", matricNo: null, admissionNo: "202412345678AB" }), ["Admission number", "202412345678AB"]);
  assert.deepEqual(studentNumber({ matric: "MOAU/SC/CSC/24/1" }), ["Matriculation number", "MOAU/SC/CSC/24/1"]);
  assert.deepEqual(studentNumber({ matric: null }), ["Matriculation number", "—"]);
});

test("the Director of ICT asks, the Registrar or the Deputy Registrar decides, the Super Administrator does both", () => {
  assert.equal(mayRequest("ict"), true);
  assert.equal(mayRequest("super"), true);
  assert.equal(mayRequest("registrar"), false);
  assert.equal(mayRequest(null), false);
  assert.equal(mayDecide("registrar"), true);
  assert.equal(mayDecide("dregistrar"), true);
  assert.equal(mayDecide("super"), true);
  assert.equal(mayDecide("ict"), false);
});

test("how a course came on and where a removal stands, in words; a value the screen does not know is never blank", () => {
  assert.equal(cameWord("STUDENT"), "Chosen by the student");
  assert.equal(cameWord("REGISTRY_LATE"), "Late registration by the Registry");
  assert.equal(cameWord("OLD_PORTAL"), "Old portal upload");
  assert.equal(cameWord("CARRY_OVER"), "Carry-over the results state");
  assert.equal(cameWord(null), "Not recorded");
  assert.equal(cameWord("SOMETHING_NEW"), "Not recorded");
  assert.deepEqual(stateWord("PENDING"), ["Held for the Registry", "warn"]);
  assert.deepEqual(stateWord("APPLIED"), ["Withdrawn", "ok"]);
  assert.deepEqual(stateWord("UNDONE"), ["Put back", "grey"]);
  assert.deepEqual(stateWord("ODD"), ["Odd", "grey"]);
});

test("a course is taken off only while it is counted and no removal stands on it; the same course elsewhere likewise", () => {
  assert.equal(removable({ status: "APPROVED", removalState: null }), true);
  assert.equal(removable({ status: "REGISTERED", removalState: "DECLINED" }), true);
  assert.equal(removable({ status: "APPROVED", removalState: "PENDING" }), false);
  assert.equal(removable({ status: "WITHDRAWN", removalState: "APPLIED" }), false);
  assert.equal(removable({ status: "DROPPED", removalState: null }), false);
  assert.equal(includable({ status: "APPROVED", removalRef: null }), true);
  assert.equal(includable({ status: "APPROVED", removalRef: "RCR-2026-00004" }), false);
  assert.equal(notIncludable({ status: "APPROVED", removalRef: "RCR-2026-00004" }), "RCR-2026-00004 stands on it");
  assert.equal(notIncludable({ status: "DROPPED", removalRef: null }), "dropped on that registration");
  assert.equal(notIncludable({ status: "REGISTERED", removalRef: null }), null);
});

test("a course on the record is neither dropped nor withdrawn; a withdrawn one is taken off", () => {
  assert.equal(onRecord({ status: "APPROVED" }), true);
  assert.equal(onRecord({ status: "REGISTERED" }), true);
  assert.equal(onRecord({ status: "DROPPED" }), false);
  assert.equal(onRecord({ status: "WITHDRAWN" }), false);
  assert.equal(takenOff({ status: "WITHDRAWN" }), true);
  assert.equal(takenOff({ status: "DROPPED" }), false);
});

test("a past course is shown under the code it was taken under, else its own code as the catalogue shows it", () => {
  assert.equal(codeTaken("CSC 201", "CMP 201"), "CMP 201");
  assert.equal(codeTaken("CSC 401 BMAS", null), "CSC 401");
  assert.equal(codeTaken("CSC 401 BMAS", ""), "CSC 401");
  assert.equal(codeTaken("CSC 201"), "CSC 201");
});

test("the registrations to choose from: newest session first, its later semester first, one choice each", () => {
  const regs: StudentRegistration[] = [
    { registrationId: "a", session: "2023/2024", semester: 1, level: 100, status: "APPROVED", courses: 8 },
    { registrationId: "b", session: "2024/2025", semester: 1, level: 200, status: "APPROVED", courses: 9 },
    { registrationId: "c", session: "2024/2025", semester: 2, level: 200, status: "SUBMITTED", courses: 7 },
    { registrationId: "d", session: "2024/2025", semester: 2, level: 200, status: "SUBMITTED", courses: 7 },
  ];
  assert.deepEqual(semesterChoices(regs).map((r) => r.registrationId), ["c", "b", "a"]);
  assert.equal(semesterWord(1), "First semester");
  assert.equal(semesterWord(3), "Third semester");
  assert.equal(semesterWord(5), "Semester 5");
});

test("the request names the course and the ticked courses elsewhere once each, under the reason as typed without its spaces", () => {
  const entry = { registrationId: "r1", offeringId: "o1" };
  assert.deepEqual(removalBody("s1", entry, [{ registrationId: "r2", offeringId: "o2" }, { registrationId: "r1", offeringId: "o1" }], "  wrongly counted elective  "),
    { studentId: "s1", entries: [{ registrationId: "r1", offeringId: "o1" }, { registrationId: "r2", offeringId: "o2" }], reason: "wrongly counted elective" });
  assert.match(String(reasonProblem("too short")), /ten characters or more/);
  assert.equal(reasonProblem("never chosen by the student"), null);
  assert.equal(heldCount({ hasResult: true }, [{ hasResult: true }, { hasResult: false }]), 2);
  assert.equal(heldCount({ hasResult: false }, []), 0);
  assert.equal(heldWords(0, 2), "The 2 courses named carry no result: each is withdrawn at once.");
  assert.equal(heldWords(2, 2), "Each of the 2 courses named carries a result: each is held for the Registry.");
  assert.equal(heldWords(1, 3), "1 of the 3 courses named carries a result and is held for the Registry; the others are withdrawn at once.");
  assert.equal(heldWords(2, 3), "2 of the 3 courses named carry a result and are held for the Registry; the others are withdrawn at once.");
});

test("a decline needs its note; a confirmation does not", () => {
  assert.equal(decideProblem(true, ""), null);
  assert.match(String(decideProblem(false, "no")), /ten characters/);
  assert.equal(decideProblem(false, "the student chose it on the form"), null);
});

test("what was done is said a removal a line, with its reference", () => {
  assert.deepEqual(answerLines({ groupRef: "RCR-2026-00001", graduate: false, removals: [
    { id: "1", ref: "RCR-2026-00001", state: "APPLIED", courseCode: "CSC 201", session: "2024/2025", semester: 1 },
    { id: "2", ref: "RCR-2026-00002", state: "PENDING", courseCode: "CSC 201 BMAS", session: "2025/2026", semester: 1 },
  ] }), [
    "RCR-2026-00001 · CSC 201, 2024/2025 First semester: withdrawn",
    "RCR-2026-00002 · CSC 201, 2025/2026 First semester: held for the Registrar or the Deputy Registrar",
  ]);
});
