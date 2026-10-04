import { test } from "node:test";
import assert from "node:assert/strict";
import { detectMapping, headerRowIndex, rowsOf } from "./allocation-import.ts";

test("a file's headings are matched to the fields by name, whatever their order, each column once", () => {
  const map = detectMapping(["Course Code *", "Staff ID *", "Lecturer Name", "Department", "Session *", "Semester *", "Role", "Cross-department"]);
  assert.equal(map.courseCode, 0);
  assert.equal(map.staffId, 1);
  assert.equal(map.lecturerName, 2);
  assert.equal(map.lecturerDept, 3, "a bare Department heading is the lecturer's department");
  assert.equal(map.session, 4);
  assert.equal(map.semester, 5);
  assert.equal(map.role, 6);
  assert.equal(map.crossDepartment, 7);
  assert.equal(map.courseTitle, undefined, "a field the file lacks is absent, never guessed");
});

test("an exact heading wins over a heading that merely contains an alias, and the template's own headings map completely", () => {
  const map = detectMapping(["PNO", "Full Names", "Lecturer Department", "Course Code", "Course Title", "Course Department", "Programme Code", "Level", "Academic Session", "Semester", "Teaching Role", "Cross Department"]);
  assert.deepEqual(Object.keys(map).sort(), ["courseCode", "courseDept", "courseTitle", "crossDepartment", "lecturerDept", "lecturerName", "level", "programme", "role", "semester", "session", "staffId"]);
  assert.equal(map.lecturerDept, 2);
  assert.equal(map.courseDept, 5);
});

test("the header row is found below title lines, rows are numbered as the sheet numbers them, blanks are left out and the bar fills a missing session", () => {
  const cells = [["Course allocation 2026/2027"], [""], ["Staff ID", "Course Code", "Session", "Semester"], ["STF001", "ACC 401", "", ""], ["", "", "", ""], ["STF002", "ECO 301", "2026/2027", "Second"]];
  const h = headerRowIndex(cells);
  assert.equal(h, 2);
  const rows = rowsOf(cells, h, detectMapping(cells[h]), { session: "2026/2027", semester: "1" });
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].row, rows[0].staffId, rows[0].courseCode, rows[0].session, rows[0].semester], [4, "STF001", "ACC 401", "2026/2027", "1"]);
  assert.deepEqual([rows[1].row, rows[1].session, rows[1].semester], [6, "2026/2027", "Second"]);
});
