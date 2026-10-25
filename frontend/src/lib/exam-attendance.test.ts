import { test } from "node:test";
import assert from "node:assert/strict";
import { changedMarks, examDay, scopeWords, type MarkRow, type Sheet, type SheetStudent } from "./exam-attendance.ts";
import { LIST_COLUMNS, MANUAL_COLUMNS, attendanceSheetPages, attendanceSheetsPdf } from "./exam-attendance-pdf.ts";

const student = (i: number, eligible = true): SheetStudent => ({
  student: `s${i}`, matric: `MOAUM/CSC/23/${String(1000 + i)}`, jamb: null, name: `STUDENT, Number ${i}`, programme: "Computer Science", programmeCode: "C00061",
  level: 300, registration: "SUBMITTED", carryOver: i === 2, eligible, eligibility: eligible ? "CARD" : "NO_CARD",
});

const sheet = (students: number, manual: number, version = 1, latest?: string): Sheet => ({
  id: "x", reference: `ATT/CSC301/2025/00001/V${version}`, series: "ATT/CSC301/2025/00001", version, students, manual_lines: manual,
  list: Array.from({ length: students }, (_, i) => student(i + 1, i % 5 !== 4)),
  scope_fac: "SCI", scope_dept: "CSC", scope_prog: null, faculty: "Science", department: "Computer Science", programme: null,
  exam_on: "2026-11-09", starts_at: "09:00:00", ends_at: "12:00:00", venue: "Hall A", reason: version > 1 ? "Late registration of two students" : null,
  generated_office: "exams", generated_at: "2026-10-25T10:00:00Z", generated_by_name: "OKOH Joy", latest_reference: latest ?? `ATT/CSC301/2025/00001/V${version}`,
  offering: {
    offering_id: "o", session: "2025/2026", semester: 1, course_code: "CSC 301", shown_code: "CSC 301", course_title: "Data Structures", units: 3, level: 300,
    kind: "Core", general_office: null, course_dept: "CSC", course_department: "Computer Science", course_faculty: "SCI", course_faculty_name: "Science",
    exam_on: "2026-11-09", starts_at: "09:00:00", ends_at: "12:00:00", venue: "Hall A",
  },
});

const text = (p: { ops: string[] }) => p.ops.join("\n");

test("the columns fill the landscape page between its margins", () => {
  assert.equal(LIST_COLUMNS.reduce((a, [, w]) => a + w, 0), 770);
  assert.equal(MANUAL_COLUMNS.reduce((a, [, w]) => a + w, 0), 770);
});

test("a short sheet: the reference, the facts, the list, the manual rows and the signatures, Page X of Y", () => {
  const pages = attendanceSheetPages(sheet(3, 10));
  assert.equal(pages.length, 2);
  const t = pages.map(text).join("\n");
  assert.ok(pages.every((p) => p.size.w > p.size.h), "landscape");
  assert.ok(t.includes("(ATTENDANCE SHEET REFERENCE) Tj"));
  assert.ok(t.includes("(ATT/CSC301/2025/00001/V1) Tj"));
  assert.ok(t.includes("(STUDENT EXAMINATION ATTENDANCE SHEET) Tj"));
  for (const h of ["S/N", "MATRICULATION NUMBER", "STUDENT NAME", "SIGNATURE", "ATTENDANCE", "STATUS", "INVIGILATOR", "REMARKS"]) assert.ok(t.includes(`(${h}) Tj`), h);
  assert.ok(!t.includes("...) Tj"), "no heading or name cut");
  assert.ok(t.includes("(STUDENT, Number 1) Tj"));
  assert.ok(t.includes("(300 C/O) Tj"), "a carry-over marked");
  assert.ok(t.includes("(MANUAL / LATE REGISTRATION ATTENDANCE) Tj"));
  assert.ok(t.includes("(NAME WRITTEN BY STUDENT) Tj"));
  assert.ok(t.includes("(INVIGILATOR SIGNATURE:) Tj") && t.includes("(EXAM OFFICER:) Tj") && t.includes("(DATE:) Tj"));
  assert.ok(t.includes("(Page 1 of 2) Tj") && t.includes("(Page 2 of 2) Tj"));
  assert.ok(text(pages[1]).includes("(ATT/CSC301/2025/00001/V1) Tj"), "the reference on the continuation page");
  assert.ok(t.includes("(Monday, 9 November 2026) Tj"));
  assert.ok(!t.includes("SUPERSEDED"));
});

test("a long list runs over pages, the table header on every page, Page X of Y counted for the sheet", () => {
  const pages = attendanceSheetPages(sheet(120, 15));
  assert.ok(pages.length >= 5, `pages ${pages.length}`);
  pages.forEach((p, i) => {
    const t = text(p);
    assert.ok(t.includes("(ATT/CSC301/2025/00001/V1) Tj"), `reference on page ${i + 1}`);
    assert.ok(t.includes(`(Page ${i + 1} of ${pages.length}) Tj`), `page number on page ${i + 1}`);
  });
  const all = pages.map(text).join("\n");
  assert.equal((all.match(/\(STUDENT, Number \d+\) Tj/g) ?? []).length, 120, "every student once");
  assert.ok(all.includes("(120) Tj"), "S/N runs on");
  // every page that carries students carries the list's header
  for (const p of pages) if (/\(STUDENT, Number \d+\) Tj/.test(text(p))) assert.ok(text(p).includes("(MATRICULATION NUMBER) Tj"));
  // the manual rows are numbered 1 to 15, never filled with students
  assert.ok(all.includes("(15) Tj"));
  assert.ok(!/NAME WRITTEN BY STUDENT[\s\S]*STUDENT, Number/.test(pages.slice(-1).map(text).join("\n")));
});

test("no manual lines asked: no manual section; an empty list still prints the manual rows", () => {
  assert.ok(!attendanceSheetPages(sheet(2, 0)).map(text).join("\n").includes("MANUAL / LATE REGISTRATION"));
  const empty = attendanceSheetPages(sheet(0, 5)).map(text).join("\n");
  assert.ok(empty.includes("No student is registered for this course in this scope"));
  assert.ok(empty.includes("(MANUAL / LATE REGISTRATION ATTENDANCE) Tj"));
});

test("a student without the card is marked; an earlier version prints superseded with the latest named", () => {
  const t = text(attendanceSheetPages(sheet(5, 5))[0]);
  assert.ok(t.includes("(NO CARD) Tj"));
  const old = text(attendanceSheetPages(sheet(3, 5, 1, "ATT/CSC301/2025/00001/V2"))[0]);
  assert.ok(old.includes("(SUPERSEDED BY ATT/CSC301/2025/00001/V2) Tj"));
  assert.ok(old.includes("SUPERSEDED"));
});

test("several sheets print as one document, each sheet with its own page numbers", () => {
  const bytes = attendanceSheetsPdf([sheet(3, 5), sheet(60, 10, 2)]);
  const t = new TextDecoder("latin1").decode(bytes);
  assert.ok(t.startsWith("%PDF-1.4"));
  const first = attendanceSheetPages(sheet(3, 5)).length, second = attendanceSheetPages(sheet(60, 10, 2)).length;
  assert.ok(second > first);
  assert.equal((t.match(/\(Page 1 of \d+\) Tj/g) ?? []).length, 2, "each sheet counts from 1");
  assert.ok(t.includes(`(Page ${first} of ${first}) Tj`) && t.includes(`(Page ${second} of ${second}) Tj`));
  assert.ok(t.includes(`/Count ${first + second}`));
});

test("the marks sent are only those chosen that differ from what is recorded", () => {
  const row = (id: string, attendance: string | null, reason: string | null = null) => ({ student_id: id, attendance, reason }) as MarkRow;
  const rows = [row("a", null), row("b", "PRESENT"), row("c", "ABSENT", "Sick"), row("d", null)];
  assert.deepEqual(changedMarks(rows, { a: "PRESENT", b: "PRESENT", c: "ABSENT" }, { c: "Sick" }), [{ student: "a", status: "PRESENT" }]);
  assert.deepEqual(changedMarks(rows, { b: "LATE", c: "ABSENT" }, { c: "Sick bay" }), [{ student: "b", status: "LATE" }, { student: "c", status: "ABSENT", reason: "Sick bay" }]);
});

test("words for the scope and the examination day", () => {
  assert.equal(scopeWords({ faculty: "Science", department: "Computer Science", programme: null }), "Department of Computer Science");
  assert.equal(scopeWords({ faculty: null, department: null, programme: null }), "The whole class");
  assert.equal(examDay("2026-11-09"), "Monday, 9 November 2026");
  assert.equal(examDay(null), "");
});
