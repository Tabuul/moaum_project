import { test } from "node:test";
import assert from "node:assert/strict";
import {
  EMPTY_INTAKE, EXCEPTION_MAX_DAYS, GATE_EXCEPTORS, GATE_SETTERS, INTAKE_HEAD, PORTAL_STATES, basisWord, clearsOnWord, feeStateWord, intakeFileName, intakeLine, intakeMeta,
  intakePath, intakeQuery, portalStateWord, readIntakeFilters, withIntakeChange, type IntakeRow,
} from "./intake-fees.ts";

/** a fresher whose programme has no fee line yet: nothing charged at a guess, the portal held until the fees are stated */
const ROW: IntakeRow = {
  studentId: "s1", admissionNo: "MOAU/2026/0001", matricNo: null, surname: "ABALIKE", otherNames: "Emmanuel", programmeCode: "CSC", programme: "B.Sc. Computer Science",
  facultyCode: "SC", entryMode: "UTME", currentLevel: 100, status: "ADMITTED", feeStated: false, due: "0", dueFirstSemester: "0", paid: "0", balance: "0",
  paidInFull: false, firstSemesterCleared: false, openReference: null, feeState: "NOT_CONFIGURED", acceptanceBalance: "0", hasApplicantAccount: true,
  portalState: "HELD_FEES_NOT_AVAILABLE", accountOpened: false, lastSignedInAt: null,
};

test("the address is read back only where each value has its shape; the tab defaults to the fee configuration", () => {
  const f = readIntakeFilters({ session: "2026/2027", tab: "applicants", feeState: "PART_PAID", portalState: "HELD", faculty: "SC", programme: "CSC", entryMode: "DIRECT_ENTRY", q: " okoh " });
  assert.equal(f.session, "2026/2027");
  assert.equal(f.tab, "applicants");
  assert.equal(f.feeState, "PART_PAID");
  assert.equal(f.portalState, "");
  assert.equal(f.faculty, "SC");
  assert.equal(f.programme, "CSC");
  assert.equal(f.entryMode, "DIRECT_ENTRY");
  assert.equal(f.q, "okoh");
  assert.equal(readIntakeFilters({ tab: "other" }).tab, "coverage");
  assert.equal(readIntakeFilters({}).tab, "coverage");
  // V724: the acceptance balance is a state of the portal, and a door
  assert.equal(readIntakeFilters({ portalState: "HELD_ACCEPTANCE_BALANCE" }).portalState, "HELD_ACCEPTANCE_BALANCE");
});

test("the API query leaves the session and the tab out; the address keeps both", () => {
  const f = { ...EMPTY_INTAKE, session: "2026/2027", tab: "applicants" as const, portalState: "HELD_FEES_UNPAID" };
  assert.equal(intakeQuery(f, { page: 1, size: 50 }, true), "portalState=HELD_FEES_UNPAID&page=1&size=50");
  assert.equal(intakeQuery(f), "session=2026%2F2027&tab=applicants&portalState=HELD_FEES_UNPAID");
  assert.equal(intakePath("2026/2027"), "/api/v1/finance/sessions/2026/2027/intake-fees");
});

test("a faculty change clears the programme; a session change starts the filters afresh", () => {
  const f = { ...EMPTY_INTAKE, session: "2026/2027", feeState: "PAID", portalState: "CLEARED", faculty: "SC", programme: "CSC" };
  assert.equal(withIntakeChange(f, "faculty", "EN").programme, "");
  const n = withIntakeChange(f, "session", "2027/2028");
  assert.deepEqual([n.feeState, n.portalState, n.faculty, n.programme], ["", "", "", ""]);
});

test("the row says the fees are not stated and the portal held, in the words the screens use", () => {
  const line = intakeLine(ROW);
  assert.equal(line.length, INTAKE_HEAD.length);
  assert.equal(line[6], "No");
  assert.equal(line[11], "Fees not yet stated");
  assert.deepEqual(line.slice(12, 14), [0, "Yes"]);
  assert.equal(line[14], "Held — fees not yet stated");
  assert.equal(feeStateWord("PAYMENT_PENDING"), "Awaiting the bank");
  assert.equal(portalStateWord("EXCEPTION"), "Open by exception");
});

test("V724: a fresher who paid ₦25,000 of a ₦35,000 acceptance fee is held for the ₦10,000 before the school fees are read", () => {
  assert.equal(PORTAL_STATES[0], "HELD_ACCEPTANCE_BALANCE");
  assert.equal(portalStateWord("HELD_ACCEPTANCE_BALANCE"), "Held — acceptance balance owed");
  const line = intakeLine({ ...ROW, feeStated: true, due: "150000", dueFirstSemester: "75000", feeState: "AVAILABLE", acceptanceBalance: "10000.00", portalState: "HELD_ACCEPTANCE_BALANCE" });
  assert.deepEqual(line.slice(12, 15), [10000, "Yes", "Held — acceptance balance owed"]);
  // a record with no applicant account has no dashboard to pay on: the gate does not hold it
  const listed = intakeLine({ ...ROW, hasApplicantAccount: false, portalState: "OPEN" });
  assert.deepEqual(listed.slice(13, 15), ["None", "Open (gate does not apply)"]);
  assert.equal(INTAKE_HEAD[12], "Acceptance balance");
  assert.equal(INTAKE_HEAD[15], "Student account opened");
});

test("the gate's words and offices follow the database functions", () => {
  assert.equal(clearsOnWord("FIRST_SEMESTER"), "First semester's fees paid");
  assert.equal(clearsOnWord("PAID_IN_FULL"), "Session's fees paid in full");
  assert.equal(basisWord("INSTALMENT_POLICY"), "Approved instalment arrangement");
  assert.equal(EXCEPTION_MAX_DAYS, 200);
  assert.deepEqual(GATE_SETTERS, ["bursar", "ict", "admin", "super"]);
  assert.deepEqual(GATE_EXCEPTORS, ["bursar", "studentaccounts", "admin", "super"]);
});

test("the workbook's facts and file name follow the filters", () => {
  const f = { ...EMPTY_INTAKE, session: "2026/2027", tab: "applicants" as const, portalState: "HELD_FEES_UNPAID", programme: "CSC" };
  const meta = intakeMeta(f, { programme: "B.Sc. Computer Science" }, 7, "11 Nov 2026");
  assert.equal(meta[1][1], "Portal: Held — fees unpaid · Programme: B.Sc. Computer Science");
  assert.equal(intakeFileName(f, "xlsx"), "school-fees-readiness-2026-2027-csc-held-fees-unpaid.xlsx");
});
