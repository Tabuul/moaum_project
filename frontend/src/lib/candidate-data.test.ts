import { test } from "node:test";
import assert from "node:assert/strict";

import { capsMatch, dobParse, jambNumFromName, olParse, olSubject } from "./candidate-data.ts";

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
