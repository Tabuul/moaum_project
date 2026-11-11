import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ACCEPTANCE_HEAD, BANDS, EMPTY_ACCEPTANCE, acceptanceFileName, acceptanceLine, acceptanceMeta, acceptancePath, acceptanceQuery, acceptanceRecordHref, bandWord, naira,
  readAcceptanceFilters, stillOwing, withAcceptanceChange, type AcceptanceRow,
} from "./acceptance-fees.ts";

/** an applicant who paid ₦25,000 before the acceptance fee was revised to ₦35,000: a ₦10,000 balance, never the fee again */
const ROW: AcceptanceRow = {
  applicationId: "a1", applicationNo: "MOAU/UG/2026/0001", jambRegNo: "202660110469AJ", surname: "ABALIKE", otherNames: "Emmanuel",
  programme: "B.Sc. Computer Science", programmeCode: "CSC", facultyCode: "SC", entryMode: "UTME", feeDue: "35000.00", paidTotal: "25000.00", balance: "10000.00",
  excess: "0.00", payments: 1, firstAmount: "25000.00", firstPaidAt: "2026-10-01T10:00:00Z", lastPaidAt: "2026-10-01T10:00:00Z", openReference: null, openAmount: null,
  band: "PART_PAID", acceptedAt: "2026-10-01T10:00:00Z", studentId: null, admissionNo: null, lettersIssued: 0,
};

test("the address is read back only where each value has its shape", () => {
  const f = readAcceptanceFilters({ session: "2026/2027", band: "PART_PAID", faculty: "SC", programme: "CSC; DROP", entryMode: "TRANSFER", q: "  okoh  " });
  assert.equal(f.session, "2026/2027");
  assert.equal(f.band, "PART_PAID");
  assert.equal(f.faculty, "SC");
  assert.equal(f.programme, "");
  assert.equal(f.entryMode, "");
  assert.equal(f.q, "okoh");
  assert.equal(readAcceptanceFilters({ band: "PAID" }).band, "");
  // V724: the refund desk's band and the hand-confirmed one are filters too
  assert.equal(readAcceptanceFilters({ band: "OVERPAID" }).band, "OVERPAID");
  assert.equal(readAcceptanceFilters({ band: "CONFIRMED_WITHOUT_REFERENCE" }).band, "CONFIRMED_WITHOUT_REFERENCE");
  assert.equal(readAcceptanceFilters({ session: "2026-2027" }).session, "");
});

test("the API query leaves the session to the path; the address keeps it", () => {
  const f = { ...EMPTY_ACCEPTANCE, session: "2026/2027", band: "NOT_PAID", entryMode: "UTME" };
  assert.equal(acceptanceQuery(f, { page: 2, size: 50 }, false), "band=NOT_PAID&entryMode=UTME&page=2&size=50");
  assert.equal(acceptanceQuery(f), "session=2026%2F2027&band=NOT_PAID&entryMode=UTME");
  assert.equal(acceptancePath("2026/2027"), "/api/v1/admissions/sessions/2026/2027/acceptance-fees");
});

test("a faculty change clears the programme; a session change starts afresh", () => {
  const f = { ...EMPTY_ACCEPTANCE, session: "2026/2027", band: "PENDING", faculty: "SC", programme: "CSC" };
  assert.equal(withAcceptanceChange(f, "faculty", "EN").programme, "");
  const n = withAcceptanceChange(f, "session", "2027/2028");
  assert.deepEqual([n.band, n.faculty, n.programme], ["", "", ""]);
});

test("the row reads the balance after a revision, the band in words, and the money in naira", () => {
  const line = acceptanceLine(ROW);
  assert.equal(line.length, ACCEPTANCE_HEAD.length);
  assert.deepEqual(line.slice(5, 11), [35000, 25000, 10000, 0, 1, 25000]);
  assert.equal(line[11], "Paid the earlier fee — balance owing");
  assert.equal(bandWord("SETTLED_IN_PARTS"), "Paid the balance");
  assert.equal(naira("10000.00"), "₦10,000");
  assert.equal(naira(null), "—");
});

test("V724: an applicant who paid ₦40,000 of a ₦35,000 fee is for the refund desk; one confirmed by hand owes nothing", () => {
  assert.deepEqual(BANDS.slice(-2), ["OVERPAID", "CONFIRMED_WITHOUT_REFERENCE"]);
  const over = acceptanceLine({ ...ROW, paidTotal: "40000.00", balance: "0.00", excess: "5000.00", firstAmount: "40000.00", band: "OVERPAID" });
  assert.deepEqual(over.slice(6, 9), [40000, 0, 5000]);
  assert.equal(over[11], "Paid above the fee — for the refund desk");
  assert.equal(bandWord("CONFIRMED_WITHOUT_REFERENCE"), "Confirmed without a reference");
  // a server that does not send the excess reads none
  assert.equal(acceptanceLine({ ...ROW, excess: undefined })[8], 0);
});

test("V724: a row opens the student's record once the offer is on the register, else the applicant on the admissions desk", () => {
  assert.equal(acceptanceRecordHref({ ...ROW, studentId: "b2c4" }, "2026/2027"), "/students/b2c4");
  assert.equal(acceptanceRecordHref(ROW, "2026/2027"), "/admissions/applicants?session=2026%2F2027&q=202660110469AJ");
  assert.equal(acceptanceRecordHref({ ...ROW, jambRegNo: null }, "2026/2027"), "/admissions/applicants?session=2026%2F2027&q=ABALIKE");
  assert.equal(acceptanceRecordHref({ studentId: null, jambRegNo: null, surname: "" }, "2026/2027"), null);
});

test("still owing counts the offers whose acceptance is not yet met in full", () => {
  assert.equal(stillOwing({ notPaid: 3, pending: 2, partPaid: 4 }), 9);
});

test("the workbook's facts and file name follow the filters", () => {
  const f = { ...EMPTY_ACCEPTANCE, session: "2026/2027", band: "PART_PAID", faculty: "SC" };
  const meta = acceptanceMeta(f, { faculty: "Physical Sciences" }, 12, "11 Nov 2026");
  assert.equal(meta[1][1], "Standing: Paid the earlier fee — balance owing · Faculty: Physical Sciences");
  assert.equal(acceptanceFileName(f, "xlsx"), "acceptance-fees-2026-2027-sc-part-paid.xlsx");
});
