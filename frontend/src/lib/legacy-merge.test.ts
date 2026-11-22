import { test } from "node:test";
import assert from "node:assert/strict";
import {
  courseKey, lineTone, lineWord, mergeChecks, newTitleCourses, plainDetail, round2, unitDifferences, unitsApplied, versionCounts,
  type CheckAnswer, type CourseFact, type LegacyLine,
} from "./legacy-merge.ts";

const course = (over: Partial<CourseFact>): CourseFact => ({
  courseCode: "GST 111", codeAsTaken: "GST 111", title: "Communication in English", units: 2, currentTitle: "Use of English", currentUnits: 3,
  session: "2023/2024", semester: 1, stream: "UG", match: "CODE_ONLY_NEW_TITLE", made: true, existed: false, matrics: ["A/1"], ...over,
});
const line = (over: Partial<LegacyLine>): LegacyLine => ({
  line: "2", matric: "A/1", course: "GST 111", session: "2023/2024", semester: 1, status: "ADDED", detail: null,
  uploadedCode: "GST111", uploadedTitle: "Communication in English", uploadedUnits: "2", category: "GST", matchedCourse: "GST 111",
  currentTitle: "Use of English", currentUnits: 3, version: "NEW", match: "CODE_AND_TITLE", action: null, ...over,
});

test("the counts of the batches add up; the semester is not a count", () => {
  const m = mergeChecks([{ rows: 400, results: 380, units_corrected: 5, semester: 1, preview: true, first_error: "x" },
    { rows: 120, results: 100, units_corrected: 1, semester: 2, versions_made: 3 }]);
  assert.deepEqual(m.totals, { rows: 520, results: 480, units_corrected: 6, versions_made: 3 });
});

test("a course as taken is one fact across the batches: its students united, made only where none was on record", () => {
  const m = mergeChecks([
    { courses: [course({ matrics: ["A/1", "A/2"] }), course({ courseCode: "CSC 101", codeAsTaken: "CSC 101", title: "Intro", units: 3, currentUnits: 3, made: false, existed: true, matrics: ["A/1"] })] },
    { courses: [course({ matrics: ["A/2", "A/3"] }), course({ courseCode: "CSC 101", codeAsTaken: "CSC 101", title: "Intro", units: 3, currentUnits: 3, made: true, existed: false, matrics: ["A/4"] }),
      course({ units: 3, matrics: ["A/5"] })] },
  ]);
  assert.equal(m.courses.length, 3);
  const gst2 = m.courses.find((c) => c.courseCode === "GST 111" && c.units === 2);
  assert.deepEqual(gst2?.matrics, ["A/1", "A/2", "A/3"]);
  assert.equal(gst2?.made, true);
  const csc = m.courses.find((c) => c.courseCode === "CSC 101");
  assert.equal(csc?.made, false);   // one batch found it on record
  assert.equal(csc?.existed, true);
  assert.deepEqual(csc?.matrics, ["A/1", "A/4"]);
  assert.notEqual(courseKey(course({})), courseKey(course({ units: 3 })));
  assert.notEqual(courseKey(course({})), courseKey(course({ session: "2024/2025" })));
});

test("the courses as taken are counted from the united facts, not by adding each batch's count", () => {
  // each batch of a check is undone, so a course new to the record is made again by every batch that names it: one course, not three
  const m = mergeChecks([
    { versions_made: 2, versions_reused: 1, courses: [course({ matrics: ["A/1"] }), course({ courseCode: "CSC 101", codeAsTaken: "CSC 101", title: "Intro", units: 3, made: false, existed: true })] },
    { versions_made: 1, courses: [course({ matrics: ["A/2"] })] },
    { versions_made: 2, courses: [course({ matrics: ["A/3"] }), course({ courseCode: "MTH 101", codeAsTaken: "MTH 101", title: "Algebra", units: 3, made: true, existed: false })] },
  ]);
  assert.deepEqual(versionCounts(m.courses), { made: 2, existed: 1 });
  assert.equal(m.totals.versions_made, 5);   // the batches' own counts still add up, but the tile reads the facts
  assert.deepEqual(versionCounts([]), { made: 0, existed: 0 });
  // a course one batch found on record and another (after an earlier batch's undo) made is on record, not new
  const both = mergeChecks([{ courses: [course({ made: true, existed: false })] }, { courses: [course({ made: false, existed: true })] }]);
  assert.deepEqual(versionCounts(both.courses), { made: 0, existed: 1 });
});

test("the students, graduates and new registrations are sets", () => {
  const m = mergeChecks([{ students_affected: ["B/1", "A/1"], graduates: ["A/1"], registrations_new: ["A/1|2023/2024|1"] },
    { students_affected: ["A/1", "C/1"], graduates: ["A/1", "C/1"], registrations_new: ["A/1|2023/2024|1", "C/1|2023/2024|2"] }]);
  assert.deepEqual(m.studentsAffected, ["A/1", "B/1", "C/1"]);
  assert.deepEqual(m.graduates, ["A/1", "C/1"]);
  assert.deepEqual(m.registrationsNew, ["A/1|2023/2024|1", "C/1|2023/2024|2"]);
});

test("a student's CGPA: the record's before, every batch's difference added, the CGPA after the points over the units", () => {
  const before = { tcr: 100, twgp: 350, cgpa: 3.5, sem: { "2023/2024|1": 3.4, "2023/2024|2": 3.6 } };
  const answers: CheckAnswer[] = [
    // the first semester: GST 111 from 3 units to 2 (an A, 5 points): 1 unit and 5 points fewer
    { gpa: [{ matric: "A/1", name: "Doe, Ada", before, after: { tcr: 99, twgp: 345, cgpa: 3.48, sem: { "2023/2024|1": 3.3, "2023/2024|2": 3.6 } } }] },
    // the second semester, checked against the record as it stands: a new 3-unit course with a C (3 points)
    { gpa: [{ matric: "A/1", name: "Doe, Ada", before, after: { tcr: 103, twgp: 359, cgpa: 3.49, sem: { "2023/2024|1": 3.4, "2023/2024|2": 3.55 } } },
      { matric: "B/1", name: "Roe, Ben", before: { tcr: 0, twgp: 0, cgpa: null, sem: {} }, after: { tcr: 3, twgp: 12, cgpa: 4, sem: { "2024/2025|1": 4 } } }] },
  ];
  const m = mergeChecks(answers);
  const a = m.gpa.find((g) => g.matric === "A/1");
  assert.ok(a);
  assert.equal(a.tcrBefore, 100);
  assert.equal(a.tcrAfter, 102);
  assert.equal(a.twgpAfter, 354);
  assert.equal(a.cgpaBefore, 3.5);
  assert.equal(a.cgpaAfter, round2(354 / 102));
  assert.equal(a.cgpaAfter, 3.47);
  assert.deepEqual(a.semesters, [
    { key: "2023/2024|1", session: "2023/2024", semester: 1, before: 3.4, after: 3.3 },
    { key: "2023/2024|2", session: "2023/2024", semester: 2, before: 3.6, after: 3.55 },
  ]);
  const b = m.gpa.find((g) => g.matric === "B/1");
  assert.equal(b?.cgpaBefore, null);
  assert.equal(b?.cgpaAfter, 4);
  assert.deepEqual(b?.semesters.map((s) => [s.key, s.before, s.after]), [["2024/2025|1", null, 4]]);
});

test("a student whose figures do not move is not listed; a semester put back where it was is not a change", () => {
  const before = { tcr: 60, twgp: 240, cgpa: 4, sem: { "2023/2024|1": 4 } };
  const m = mergeChecks([
    // a registration-only semester: the loader lists the student, nothing moves
    { gpa: [{ matric: "C/1", name: "Coe, Cy", before, after: { ...before, sem: { ...before.sem } } }] },
    // two batches whose differences cancel: 3 units and 12 points on, then off again
    { gpa: [{ matric: "D/1", name: "Doe, Di", before, after: { tcr: 63, twgp: 252, cgpa: 4, sem: { "2023/2024|1": 4.1 } } }] },
    { gpa: [{ matric: "D/1", name: "Doe, Di", before, after: { tcr: 57, twgp: 228, cgpa: 4, sem: { "2023/2024|1": 3.9 } } }] },
    // the units and points stay, one semester's GPA moves (a course's grade points moved between semesters)
    { gpa: [{ matric: "E/1", name: "Eke, Em", before: { tcr: 60, twgp: 240, cgpa: 4, sem: { "2023/2024|1": 4, "2023/2024|2": 4 } },
      after: { tcr: 60, twgp: 240, cgpa: 4, sem: { "2023/2024|1": 4.2, "2023/2024|2": 3.8 } } }] },
  ]);
  assert.deepEqual(m.gpa.map((g) => g.matric), ["E/1"]);
  assert.deepEqual(m.gpa[0].semesters.map((s) => [s.key, s.before, s.after]), [["2023/2024|1", 4, 4.2], ["2023/2024|2", 4, 3.8]]);
});

test("figures as the record rounds them", () => {
  assert.equal(round2(3.125), 3.13);
  assert.equal(round2(354 / 102), 3.47);
  assert.equal(round2(2), 2);
});

test("the lines of every batch, in order", () => {
  const m = mergeChecks([{ lines: [line({ line: "2" })] }, { lines: [line({ line: "3" }), line({ line: "4" })] }, {}]);
  assert.deepEqual(m.lines.map((l) => l.line), ["2", "3", "4"]);
});

test("the courses whose title is new to their code, each once, for the office to confirm", () => {
  const lines = [
    line({ match: "CODE_ONLY_NEW_TITLE", uploadedCode: "GST 111", uploadedTitle: "Communication in English" }),
    line({ line: "3", matric: "A/2", match: "CODE_ONLY_NEW_TITLE", uploadedCode: "GST 111", uploadedTitle: "Communication in English" }),
    line({ line: "4", matric: "A/3", match: "CODE_ONLY_NEW_TITLE", status: "NO_STUDENT" }),
    line({ line: "5", match: "CODE_AND_TITLE", uploadedCode: "CSC 101", uploadedTitle: "Intro", course: "CSC 101" }),
  ];
  assert.deepEqual(newTitleCourses(lines), [{ code: "GST 111", title: "Communication in English", currentTitle: "Use of English", matchedCourse: "GST 111", rows: 2 }]);
  assert.deepEqual(newTitleCourses([]), []);
});

test("the courses whose file units differ from the catalogue's, and how many rows take the file's units", () => {
  const c = course({});
  assert.deepEqual(unitDifferences([c, course({ units: 3 }), course({ currentUnits: null })]).map((x) => x.units), [2]);
  const lines = [line({}), line({ line: "3", status: "UNITS_CORRECTED" }), line({ line: "4", status: "UNITS_ON_PORTAL" }),
    line({ line: "5", status: "AS_TAKEN_DIFFERS" }), line({ line: "6", status: "DUPLICATE_CONFLICT" }), line({ line: "7", uploadedUnits: "3" }),
    line({ line: "8", session: "2024/2025" })];
  assert.deepEqual(unitsApplied([c, course({ units: 3 }), course({ courseCode: "CSC 101" })], lines), [{ applied: 2, kept: 2 }, { applied: 1, kept: 0 }, { applied: 0, kept: 0 }]);
});

test("a results row is read by what became of its entry: the result's own status never decides the units", () => {
  const c = course({});
  const lines = [
    line({ line: "2", status: "RESULT_POSTED", entryStatus: "ADDED" }),                          // applied: the course added with the file's units
    line({ line: "3", status: "RESULT_AS_TOTAL", entryStatus: "UNITS_CORRECTED" }),              // applied
    line({ line: "4", status: "RESULT_ON_PORTAL", entryStatus: "ALREADY_ON_RECORD" }),           // applied: on record as the file has it
    line({ line: "5", status: "NO_MARK", entryStatus: "ADDED" }),                                // applied: the course was still registered
    line({ line: "6", status: "RESULT_POSTED", entryStatus: "UNITS_ON_PORTAL" }),                // kept
    line({ line: "7", status: "RESULT_ALREADY_ON_RECORD", entryStatus: "UNITS_BY_AMENDMENT" }),  // kept
    line({ line: "8", status: "DROPPED_ON_RECORD", entryStatus: "DROPPED_ON_RECORD" }),          // kept
    line({ line: "9", status: "RESULT_POSTED", entryStatus: null }),                             // neither: no entry behind it
    line({ line: "10", status: "HELD", entryStatus: null }),                                     // neither
    line({ line: "11", status: "REFUSED", entryStatus: "ADDED" }),                               // neither: the row's writes were undone
    line({ line: "12", status: "REMOVED_ON_RECORD", entryStatus: "REMOVED_ON_RECORD" }),         // neither
    line({ line: "13", status: "COURSE_ON_RECORD_ELSEWHERE" }),                                  // neither
  ];
  assert.deepEqual(unitsApplied([c], lines), [{ applied: 4, kept: 3 }]);
});

test("a row's status in words, its tone, and a refusal without the portal's code", () => {
  assert.equal(lineWord("UNITS_CORRECTED", true), "Units will be corrected to the file's");
  assert.equal(lineWord("UNITS_CORRECTED", false), "Units corrected to the file's");
  assert.equal(lineWord("SOMETHING_NEW", false), "SOMETHING_NEW");
  assert.equal(lineWord("HELD_ROLLED_BACK", false), "Held, closed with the rollback");
  assert.equal(lineTone("ADDED"), "info");
  assert.equal(lineTone("UNITS_ON_PORTAL"), "warn");
  assert.equal(lineTone("AS_TAKEN_MISSING"), "bad");
  assert.equal(plainDetail("REGISTRATION_ONCE_A_SESSION: one a session"), "one a session");
  assert.equal(plainDetail(null), "");
});
