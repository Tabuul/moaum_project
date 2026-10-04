import { test } from "node:test";
import assert from "node:assert/strict";

import { capsMatch, dobParse, examBody, examKey, examYear, jambNumFromName, olDuplicates, olParse, olSubject, seriesClass } from "./candidate-data.ts";

test("the number is found inside a filename, whatever is wrapped around it", () => {
  assert.deepEqual(jambNumFromName("202699168863AH_Face.jpg"), { num: "202699168863AH", how: "from 202699168863AH_Face.jpg" });
  assert.equal(jambNumFromName("C:\\downloads\\Copy of 202699307120BGU (1).jpg").num, "202699307120BGU");
  assert.deepEqual(jambNumFromName("202699176777GF.jpg"), { num: "202699176777GF", how: "" });
  assert.equal(jambNumFromName("IMG-20260904-WA0031.jpg").num, "");
});

test("a trailing space is trimmed on the way in, and counted", () => {
  const r = dobParse([["Reg. Number", "Surname", "FirstName", "MiddleName", "DateofBirth", "RegType"], ["202440000065EA ", "Akor", "Ernen", "", "31-08-2005", "UTME"]]);
  assert.ok("rows" in r);
  assert.equal(r.trimmed, 1);
  assert.equal(r.rows[0].num, "202440000065EA");
  assert.equal(r.rows[0].ambiguous, false);
  assert.equal(r.rows[0].reading, "31 August 2005");
});

test("a date whose day and month are both twelve or less is ambiguous, not guessed", () => {
  const r = dobParse([["Reg. Number", "DateofBirth"], ["202699711714BJ", "05-07-2002"]]);
  assert.ok("rows" in r);
  assert.equal(r.rows[0].ambiguous, true);
});

test("a file with no registration number column is refused by name", () => {
  const r = dobParse([["Surname", "DateofBirth"], ["Akor", "31-08-2005"]]);
  assert.ok("err" in r);
});

test("subject names are normalised before English and Mathematics can be found", () => {
  assert.equal(olSubject("English Lang."), "English Language");
  assert.equal(olSubject("Lit. English"), "Literature in English");
  assert.equal(olSubject("Mathematics"), "Mathematics");
  assert.equal(olSubject("Bible Knowled/Crk"), "Christian Religious Studies");
  assert.equal(olSubject("Princ. of Account"), "Financial Accounting");
});

test("one row per subject collapses to one candidate, and credits are A1 to C6", () => {
  const head = ["RegNum", "SubjectName", "Grade", "ExamSeries", "ExamYear", "ExamType", "ExamNumber"];
  const mk = (s: string, g: string) => ["202660881440FP", s, g, "School Exam", "2024", "WAEC Only", "4110229931"];
  const r = olParse([head, mk("English Lang.", "D7"), mk("Mathematics", "C6"), mk("Government", "C4"), mk("Bible Knowled/Crk", "B3"), mk("Lit. English", "C5"), mk("Civic Education", "C6")]);
  assert.ok("rows" in r);
  assert.equal(r.lines, 6);
  assert.equal(r.rows.length, 1);
  assert.equal(r.rows[0].credits, 5);
  assert.equal(r.rows[0].eng, "D7");
  assert.equal(r.rows[0].meets, false);
});

test("matching counts both ways", () => {
  const m = capsMatch([{ num: "A" }, { num: "Z" }], [{ num: "A", name: "ONE", list: "utme" }, { num: "B", name: "TWO", list: "de" }]);
  assert.equal(m.matched.length, 1);
  assert.equal(m.orphan[0].num, "Z");
  assert.equal(m.missing[0].num, "B");
});

test("two sittings are kept apart, and the best grade per subject is the one the credit check reads", () => {
  const head = ["RegNum", "SubjectName", "Grade", "ExamSeries", "ExamYear", "ExamType", "ExamNumber"];
  const w = (s: string, g: string) => ["202660881440FP", s, g, "School Exam", "2024", "WAEC Only", "4110229931"];
  const nc = (s: string, g: string) => ["202660881440FP", s, g, "School Exam", "2025", "NECO", "9920002"];
  const r = olParse([head, w("English Lang.", "D7"), w("Mathematics", "C6"), w("Physics", "C4"), w("Chemistry", "C5"), w("Biology", "A1"),
    nc("English Lang.", "B2"), nc("Physics", "D7"), nc("Agricultural Science", "B3")]);
  assert.ok("rows" in r);
  if (!("rows" in r)) return;
  assert.equal(r.rows.length, 1);
  const c = r.rows[0];
  assert.equal(c.sittings.length, 2);
  assert.deepEqual(c.sittings.map((s) => s.type), ["WAEC Only", "NECO"]);
  assert.equal(c.sittings[1].subjects.length, 3);
  assert.equal(c.eng, "B2");
  assert.equal(c.subjects.find((s) => s.subject === "Physics")?.grade, "C4");
  assert.equal(c.credits, 6);
  assert.equal(c.meets, true);
});


test("the examining body, series, number and year are read the way the database reads them", () => {
  assert.equal(examBody("WASSCE"), "WAEC");
  assert.equal(examBody("NECO (SSCE)"), "NECO");
  assert.equal(examBody("GCE"), "OTHER");
  assert.equal(seriesClass("WAEC GCE", ""), "EXTERNAL");
  assert.equal(seriesClass("WASSCE", "MAY/JUNE"), "INTERNAL");
  assert.equal(seriesClass("WAEC", "Nov/Dec"), "EXTERNAL");
  assert.equal(seriesClass("NECO", ""), "INTERNAL");
  assert.equal(examKey(" 4250-101/001 "), "4250101001");
  assert.equal(examYear("MAY/JUNE 2023"), "2023");
  assert.equal(examYear(""), "");
});

test("the file's own duplicates are found before anything is recorded", () => {
  const head = ["RegNum", "SubjectName", "Grade", "ExamSeries", "ExamYear", "ExamType", "ExamNumber"];
  const r = olParse([head,
    // one candidate: WAEC May/June 2023 under two numbers (V315: two sittings, nothing to say); the same number again, written
    // with spaces, under other grades (the one thing held); the GCE of 2023 (its own sitting); NECO under the same number twice as written
    ["202611111111AA", "English Language", "C6", "MAY/JUNE", "2023", "WASSCE", "4250101001"],
    ["202611111111AA", "Mathematics", "B3", "MAY/JUNE", "2023", "WASSCE", "4250101001"],
    ["202611111111AA", "Mathematics", "B3", "MAY/JUNE", "2023", "WASSCE", "4250101001"],
    ["202611111111AA", "English Language", "B2", "MAY/JUNE", "2023", "WASSCE", "4250101002"],
    ["202611111111AA", "English Language", "B2", "MAY/JUNE", "2023", "WAEC", "4250 101 001"],
    ["202611111111AA", "Biology", "C4", "NOV/DEC", "2023", "WAEC GCE", "4250999001"],
    ["202611111111AA", "Chemistry", "C4", "JUNE/JULY", "2023", "NECO", "1234567890"],
    ["202611111111AA", "Chemistry", "C4", "JUNE/JULY", "2023", "NECO (SSCE)", "1234 567 890"],
    // another candidate with the first candidate's WAEC number
    ["202622222222BB", "English Language", "A1", "MAY/JUNE", "2022", "WAEC", "4250-101-001"],
  ]);
  assert.ok("rows" in r);
  const d = olDuplicates(r.rows);
  assert.deepEqual(d.sameSitting, [{ num: "202611111111AA", body: "WAEC", year: "2023", series: "INTERNAL", numbers: ["4250101001", "4250 101 001"] }]);
  assert.equal(d.sameResult.length, 1);
  assert.equal(d.sameResult[0].body, "NECO");
  assert.deepEqual(d.sharedNumber, [{ body: "WAEC", exnum: "4250101001", nums: ["202611111111AA", "202622222222BB"] }]);
  assert.deepEqual(d.repeatedSubjects.map((x) => `${x.subject}×${x.times}`), ["Mathematics×2"]);
});

test("a file with nothing repeated has nothing to say", () => {
  const r = olParse([["RegNum", "SubjectName", "Grade", "ExamYear", "ExamType", "ExamNumber"],
    ["202611111111AA", "English Language", "C6", "2023", "WAEC", "1"], ["202611111111AA", "Physics", "C6", "2024", "NECO", "2"]]);
  assert.ok("rows" in r);
  const d = olDuplicates(r.rows);
  assert.equal(d.sameSitting.length + d.sameResult.length + d.sharedNumber.length + d.repeatedSubjects.length, 0);
});
