import { test } from "node:test";
import assert from "node:assert/strict";
import { columnsFor, drill, filterLines, fullName, PACKAGE_PARTS, PRESETS, semWord, type ReadinessRow } from "./exam-readiness.ts";

const row = (over: Partial<ReadinessRow> = {}): ReadinessRow => ({
  student_id: "s1", matric_no: "MOAU/SC/CSC/22/10001", jamb_no: null, surname: "OKON", other_names: "Ada", sex: "F", status: "ACTIVE",
  academic_status: "ACTIVE", programme_type: "UNDERGRADUATE", admission_route: "UTME", study_mode: "FULL_TIME", faculty_code: "SC", faculty: "Science",
  dept_code: "CSC", department: "Computer Science", programme_code: "C00023", programme: "B.Sc. Computer Science", level: 300, entry_session: "2023/2024",
  fee_status: "FULLY_PAID", payable: 150000, paid_amount: 150000, outstanding: 0, last_paid_at: "2026-10-01T10:00:00Z", fully_paid: true,
  school_fees_paid: true, registration_stream: "UNIVERSITY", registration_status: "APPROVED", registration_level: 300, courses: 8, units: 22,
  carryovers: 1, course_registered: null, course_entry_type: null, course_expected: null, paid: true, registered: true, exam_card: true,
  readiness: "PAID_REGISTERED", exception: null, ...over,
});
const ctx = { session: "2026/2027", semester: 1 };

test("a figure opens its students and one grouping down (V640)", () => {
  assert.deepEqual(drill("faculty", "SC", "PAID_NOT_REGISTERED"), { cat: "PAID_NOT_REGISTERED", fac: "SC", by: "department" });
  assert.deepEqual(drill("department", "CSC", "NOT_PAID"), { cat: "NOT_PAID", dept: "CSC", by: "programme" });
  assert.deepEqual(drill("level", "300", "ALL"), { cat: "ALL", level: "300", by: "level" });
  assert.deepEqual(drill("faculty", "ALL", "NOT_PAID"), { cat: "NOT_PAID" });
  assert.deepEqual(drill("type", "UNCLASSIFIED", "ALL"), { cat: "ALL", type: "", by: "faculty" });
});

test("each report carries the University's columns, amounts only for the offices that read them", () => {
  const paidReg = columnsFor("PAID_REGISTERED", false, true).map(([h]) => h);
  assert.deepEqual(paidReg, ["Matric No", "Student Name", "Faculty", "Department", "Programme", "Level", "Session", "Semester", "Payment Status", "Registration Status", "Courses Registered", "Total CU"]);
  const notPaid = columnsFor("NOT_PAID", false, true).map(([h]) => h);
  assert.ok(notPaid.includes("Amount Required") && notPaid.includes("Outstanding"));
  assert.ok(!columnsFor("NOT_PAID", false, false).map(([h]) => h).includes("Outstanding"));
  const course = columnsFor("ALL", true, true);
  assert.deepEqual(course.map(([h]) => h).slice(-4), ["Course", "Fee Status", "Registration Status", "Examination Status"]);
  const cells = course.map(([, f]) => f(row({ course_registered: true, course_entry_type: "CARRYOVER" }), { ...ctx, course: "CSC 301" }));
  assert.equal(cells[6], "CSC 301");
  assert.equal(cells[8], "Registered (Carryover)");
  assert.equal(cells[9], "Paid + registered");
  assert.equal(columnsFor("PAID_REGISTERED", false, true)[7][1](row(), ctx), "First");
  assert.equal(fullName(row()), "OKON, Ada");
  assert.equal(semWord(2), "Second");
});

test("the package's six reports, the presets, and the filters in words", () => {
  assert.equal(PACKAGE_PARTS.length, 6);
  assert.deepEqual(PACKAGE_PARTS.map((p) => p.n), [1, 2, 3, 4, 5, 6]);
  assert.equal(PRESETS.length, 15);
  const lines = filterLines({ session: "2026/2027", semester: 1, programmeType: "UNDERGRADUATE", paidRule: "CARD" }, [{ code: "UNDERGRADUATE", label: "Undergraduate" }]);
  assert.deepEqual(lines[0], ["Session", "2026/2027"]);
  assert.deepEqual(lines[2], ["Programme type", "Undergraduate"]);
  assert.match(lines[3][1], /examination card's rule/);
});
