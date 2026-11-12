import { test } from "node:test";
import assert from "node:assert/strict";
import {
  AWAITINGS, BANDS, CHECK_WORDS, EMPTY_TRANSFER_FEES, LEGACY_STATUSES, LEGACY_STATUS_WORDS, TRANSFER_FEE_HEAD, awaitingWord, bandKind, bandWord, countBy, deskStanding, headerKey,
  leftOut, legacyRow, naira,
  readLegacyTransferSheet, readTransferFeeFilters, snakeKeys, stillOwing, summaryTotal, transferFeeFileName, transferFeeLine, transferFeeMeta, transferFeeQuery,
  withTransferFeeChange, type TransferFeeRow,
} from "./transfer-fees.ts";

/** a student who paid ₦10,000 on the old portal toward a fee the Bursary now states at ₦20,000: ₦10,000 owed, never the fee again */
const ROW: TransferFeeRow = {
  application_id: "a1", student_id: "s1", matric_no: "MOAU/SC/CSC/23/0001", name: "ABALIKE, Emmanuel", session: "2026/2027",
  from_programme: "B.Sc. Physics", to_programme: "B.Sc. Computer Science", faculty_code: "SC", from_dept: "PHY", to_dept: "CSC", state: "FROM_OK",
  awaiting: "NEW_HOD", legacy_ref: "IDT/2025/0142", fee_due: "20000.00", portal_paid: "0.00", old_portal_paid: "10000.00", paid_total: "10000.00",
  balance: "10000.00", excess: "0.00", payments: 1, pending: false, band: "PART_PAID", applied_at: "2025-10-02T09:00:00Z",
};

test("the address is read back only where each value has its shape", () => {
  const f = readTransferFeeFilters({ session: "2026/2027", band: "PART_PAID", awaiting: "ACADEMIC_OFFICE", faculty: "SC", dept: "CSC; DROP", search: "  okoh  " });
  assert.equal(f.session, "2026/2027");
  assert.equal(f.band, "PART_PAID");
  assert.equal(f.awaiting, "ACADEMIC_OFFICE");
  assert.equal(f.faculty, "SC");
  assert.equal(f.dept, "");
  assert.equal(f.search, "okoh");
  assert.equal(readTransferFeeFilters({ band: "PAID" }).band, "");
  assert.equal(readTransferFeeFilters({ band: "AWAITING_APPLICATION", awaiting: "APPLICATION" }).awaiting, "APPLICATION");
  assert.equal(readTransferFeeFilters({ awaiting: "DEAN" }).awaiting, "");
  assert.equal(readTransferFeeFilters({ session: "2026-2027" }).session, "");
  // every session, as the API reads it
  assert.equal(readTransferFeeFilters({ session: "ALL", awaiting: "DECLINED" }).session, "ALL");
  assert.equal(readTransferFeeFilters({ awaiting: "DECLINED" }).awaiting, "DECLINED");
});

test("the filters go to the address and the API under the same keys; a faculty change clears the department", () => {
  const f = { ...EMPTY_TRANSFER_FEES, session: "2026/2027", band: "NOT_PAID", awaiting: "PAYMENT", search: "okoh" };
  assert.equal(transferFeeQuery(f), "session=2026%2F2027&band=NOT_PAID&awaiting=PAYMENT&search=okoh");
  assert.equal(transferFeeQuery({ ...EMPTY_TRANSFER_FEES }, { page: 0, size: "" }), "page=0");
  const n = withTransferFeeChange({ ...f, faculty: "SC", dept: "CSC" }, "faculty", "EN");
  assert.deepEqual([n.faculty, n.dept, n.band], ["EN", "", "NOT_PAID"]);
});

test("every band and every desk has its words", () => {
  for (const b of BANDS) assert.notEqual(bandWord(b), b);
  for (const a of AWAITINGS) assert.notEqual(awaitingWord(a), a);
  assert.equal(bandWord("PART_PAID"), "Part paid — balance owed");
  // a declined, not recommended or withdrawn application owes nothing more
  assert.equal(bandWord("CLOSED"), "Closed — nothing owed");
  assert.equal(bandKind("CLOSED"), "grey");
  assert.equal(readTransferFeeFilters({ band: "CLOSED" }).band, "CLOSED");
  assert.equal(awaitingWord(null), "Declined");
  assert.equal(awaitingWord("ACADEMIC_OFFICE"), "Academic Office — final approval");
});

test("the row reads the balance against the fee as stated now, the old portal's payment beside this portal's", () => {
  const line = transferFeeLine(ROW);
  assert.equal(line.length, TRANSFER_FEE_HEAD.length);
  assert.deepEqual(line.slice(6, 13), [20000, 0, 10000, 10000, 10000, 0, 1]);
  assert.equal(line[13], "Part paid — balance owed");
  assert.equal(line[14], "New HOD");
  assert.equal(line[15], "2025-10-02");
  assert.equal(naira("10000.00"), "₦10,000");
  assert.equal(naira(null), "—");
  // a fee the Bursary has not stated is no balance, never a figure from here
  // a row sent in camelCase reads the same
  assert.deepEqual(transferFeeLine(snakeKeys<TransferFeeRow>({ ...ROW, feeDue: "20000.00", oldPortalPaid: "10000.00", fee_due: undefined, old_portal_paid: undefined })).slice(6, 9),
    [20000, 0, 10000]);
  const unstated = transferFeeLine({ ...ROW, fee_due: null, balance: null, band: "FEE_NOT_STATED" });
  assert.deepEqual([unstated[6], unstated[10]], ["—", "—"]);
  // an old-portal credit with no application yet
  const credit = transferFeeLine({ ...ROW, application_id: null, session: null, to_programme: null, awaiting: "APPLICATION", band: "AWAITING_APPLICATION", applied_at: null });
  assert.deepEqual([credit[2], credit[4], credit[14], credit[15]], ["—", "—", "The student's application", "—"]);
});

test("the summary's totals come from its bands", () => {
  const s = { bands: { NOT_PAID: 3, PENDING: 1, PART_PAID: 4, PAID_IN_FULL: 6, AWAITING_APPLICATION: 2 } };
  assert.equal(summaryTotal(s), 16);
  assert.equal(stillOwing(s), 8);
  assert.equal(stillOwing({ bands: {} }), 0);
  // a closed application owes nothing: never among those still owing, nor not paid
  assert.equal(stillOwing({ bands: { NOT_PAID: 3, CLOSED: 5 } }), 3);
  assert.equal(summaryTotal({ bands: { NOT_PAID: 3, CLOSED: 5 } }), 8);
});

test("the desk: nothing paid awaits payment at whatever desk; a part payment owes the balance; the final approval waits for the whole fee", () => {
  assert.equal(deskStanding({ state: "APPLIED", paid_total: "0", balance: "20000" }), "AWAITING_PAYMENT");
  // an old-portal application loaded at a later stage, with nothing paid, awaits payment too — never "part paid"
  assert.equal(deskStanding({ state: "FROM_OK", paid_total: "0", balance: "20000" }), "AWAITING_PAYMENT");
  assert.equal(deskStanding({ state: "TO_OK", paid_total: null, balance: "20000" }), "AWAITING_PAYMENT");
  assert.equal(deskStanding({ state: "REG_OK", paid_total: "0.00", balance: "20000.00", pending: true }), "AWAITING_PAYMENT");
  assert.equal(deskStanding({ state: "APPLIED", paid_total: "10000", balance: "10000" }), "BALANCE_OWED");
  assert.equal(deskStanding({ state: "FROM_OK", paid_total: "10000.00", balance: "10000.00" }), "BALANCE_OWED");
  assert.equal(deskStanding({ state: "TO_OK", paid_total: "20000", balance: "0" }), "WITH_DESKS");
  assert.equal(deskStanding({ state: "REG_OK", paid_total: "10000", balance: "10000" }), "BALANCE_OWED");
  assert.equal(deskStanding({ state: "REG_OK", paid_total: "20000", balance: "0", pending: false }), "READY");
  // the fee not stated: paid, but nothing is ready for the final approval
  assert.equal(deskStanding({ state: "REG_OK", paid_total: "10000", balance: null }), "WITH_DESKS");
  assert.equal(deskStanding({ state: "EFFECTED", paid_total: "20000", balance: "0" }), null);
  assert.equal(deskStanding({ state: "DECLINED", paid_total: "0", balance: "20000" }), null);
  // a closed application is never counted as owing
  assert.equal(deskStanding({ state: "DECLINED", paid_total: "0", balance: "0", band: "CLOSED" }), null);
  assert.equal(deskStanding({ state: "NOT_RECOMMENDED", paid_total: "10000", balance: "0", band: "CLOSED" }), null);
  assert.equal(deskStanding({ state: "APPLIED", paid_total: "0", balance: "0", band: "CLOSED" }), null);
});

test("the workbook's facts and file name follow the filters", () => {
  const f = { ...EMPTY_TRANSFER_FEES, session: "2026/2027", band: "PART_PAID", faculty: "SC" };
  const meta = transferFeeMeta(f, { faculty: "Physical Sciences" }, "20000", 12, "12 Nov 2026");
  assert.equal(meta[1][1], "₦20,000");
  assert.equal(meta[2][1], "Standing: Part paid — balance owed · Faculty: Physical Sciences");
  assert.equal(transferFeeMeta(f, {}, null, 0, "")[1][1], "Not stated");
  assert.equal(transferFeeFileName(f, "xlsx"), "transfer-fees-2026-2027-sc-part-paid.xlsx");
  assert.equal(transferFeeFileName({ ...EMPTY_TRANSFER_FEES, session: "ALL" }, "xlsx"), "transfer-fees-all-sessions.xlsx");
  assert.equal(transferFeeMeta({ ...EMPTY_TRANSFER_FEES, session: "ALL" }, {}, "20000", 0, "")[0][1], "All sessions");
});

test("the old portal's export: headings become the API's keys, the header found under a title, empty rows left out", () => {
  assert.equal(headerKey("Matric No."), "matric_no");
  assert.equal(headerKey("MATRICULATION NUMBER"), "matric_no");
  assert.equal(headerKey("Application Ref"), "legacy_ref");
  assert.equal(headerKey("Date Applied"), "applied_on");
  assert.equal(headerKey("Payment Reference(s)"), "payrefs");
  assert.equal(headerKey("New Department"), "to_programme");
  assert.equal(headerKey("Status"), "stage");
  assert.equal(headerKey("Remarks"), "remarks");
  const read = readLegacyTransferSheet([
    ["INTER DEPARTMENTAL TRANSFER APPLICATIONS", "", ""],
    ["Reference", "Matric No", "New Programme", "Status", "Payment Ref", "Payment Ref"],
    ["IDT/0142", "MOAU/SC/PHY/23/0001", "CSC", "HOD", "PR123, PR124", ""],
    ["", "", "", "", "", ""],
    ["IDT/0143", "MOAU/SC/PHY/23/0002", "Computer Science", "", "", "PR200"],
  ]);
  assert.equal(read.problem, null);
  assert.deepEqual(read.lines, [3, 5]);
  assert.deepEqual(read.rows[0], { legacy_ref: "IDT/0142", matric_no: "MOAU/SC/PHY/23/0001", to_programme: "CSC", stage: "HOD", payrefs: "PR123, PR124" });
  assert.equal(read.rows[1].payrefs, "PR200");
  assert.match(readLegacyTransferSheet([["Name", "Amount"], ["A", "1"]]).problem ?? "", /No header/);
  assert.match(readLegacyTransferSheet([["Matric No", "Reference"]]).problem ?? "", /no row/);
});

test("the reconciliation's words and what a commit leaves out", () => {
  assert.equal(LEGACY_STATUS_WORDS.AWAITING_APPLICATION[0], "Awaiting an application");
  // every status the list filters by has its words; a payment used by a restored transfer among them
  for (const st of LEGACY_STATUSES) assert.ok(LEGACY_STATUS_WORDS[st], st);
  assert.ok((LEGACY_STATUSES as readonly string[]).includes("USED"));
  assert.equal(LEGACY_STATUS_WORDS.USED[0], "Used by a restored transfer");
  assert.equal(CHECK_WORDS.ATTACH[1], "ok");
  assert.equal(leftOut("NEW"), false);
  assert.equal(leftOut("EXISTS"), false);
  assert.equal(leftOut("CONFLICT"), true);
  assert.deepEqual(countBy([{ status: "NEW" }, { status: "NEW" }, { status: "INVALID" }]), { NEW: 2, INVALID: 1 });
});

test("a row of the list reads the student and the application whichever name the API gives them", () => {
  const base = { payment_id: "p1", status: "LINKED", item: "INTER DEPT. TRANSFER", item_kind: "TRANSFER", amount: "10000.00" };
  const a = legacyRow({ ...base, name: "OKOH, Ada", programme: "B.Sc. Physics", application_state: "FROM_OK" });
  assert.deepEqual([a.name, a.programme, a.application_state], ["OKOH, Ada", "B.Sc. Physics", "FROM_OK"]);
  const b = legacyRow({ ...base, studentName: "OKOH, Ada", programmeName: "B.Sc. Physics", state: "REG_OK", decidedOffice: "bursar" });
  assert.deepEqual([b.name, b.programme, b.application_state, b.decided_office], ["OKOH, Ada", "B.Sc. Physics", "REG_OK", "bursar"]);
  // the programme the application moves to, as the list names it, before the student's own
  assert.equal(legacyRow({ ...base, application_to_programme: "B.Sc. Computer Science", programme: "B.Sc. Physics" }).to_programme, "B.Sc. Computer Science");
  assert.equal(legacyRow(base).name, null);
});
