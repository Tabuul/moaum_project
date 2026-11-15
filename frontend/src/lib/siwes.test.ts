import { test } from "node:test";
import assert from "node:assert/strict";
import {
  apiStatus, bankCheckStateOf, bankHoldPill, byWords, clearsThemselves, configWarnings, courseRegistrationPage, courseStateWarning, courseStateWord, creditActions, creditBankCheck,
  creditRow, dropOthersWords, paymentBankCheck, paymentGivenBack, reopenedWords, settledWords, siwesCardShown, siwesDroppedWords, siwesElsewhere, siwesTiles, siwesUndone,
  OLD_FEES_PAGE, SIWES_DESK_READERS, SIWES_OFFICE_ADD_WORDS, emptyPeriodForm, feeChange, feeStanding, groupLine, historyLine, isSiwesPurpose,
  isSiwesRegistration, lagosToday, notEligibleWords, otherCoursesOf, paymentLine, paymentStanding, paymentSums, paymentTotals, periodProblems, periodWords,
  readSiwesFilters, reasonWords, rowState, schoolFeesOwed, scopeWords, shownStatus, siwesApplies, siwesClearing, siwesCourseOf, siwesFormRows, siwesInTheWay,
  schoolFeesWords, siwesNext, siwesQuery, siwesRefundHint, siwesSemesterWords, studentLine, trainingWords, unitName, unitOptions, waitsWords,
  BANK_CHECK_PILL, BANK_HOLD_PILL, FEES_PAGE, HISTORY_HEAD, SETTLED_KIND_WORD, SIWES_RESET_WORDS, STUDENT_HEAD, PAYMENT_HEAD, type MySiwes, type SiwesConfig, type SiwesCredit, type SiwesFeeView,
  type SiwesHistoryRow, type SiwesPaymentRow, type UnitTree,
} from "./siwes.ts";

const OPEN: MySiwes = {
  eligible: true, reasons: [], session: "2025/2026", level: 300, semester: 2,
  programme: { code: "CSC", name: "Computer Science" }, department: "Computer Science", faculty: { code: "SCI", name: "Faculty of Science" },
  course: { id: "c1", code: "CSC 399", title: "Students Industrial Work Experience", units: 6 },
  period: { state: "OPEN", registrationOpens: "2026-11-01", registrationCloses: "2026-12-15", trainingStarts: "2027-01-04", trainingEnds: "2027-06-30", durationMonths: 6 },
  registrationOpen: true, fee: { amount: "4000.00", state: "PUBLISHED" }, paid: null, openReference: null, registration: null, otherCourses: [],
};

test("a SIWES purpose is never a school fee: the portal's reference and the old portal's payment alike", () => {
  assert.equal(isSiwesPurpose("SIWES registration fee 2025/2026"), true);
  assert.equal(isSiwesPurpose("SIWES (legacy)"), true);
  assert.equal(isSiwesPurpose("siwes (legacy)"), true);
  assert.equal(isSiwesPurpose("School fees 2025/2026"), false);
  assert.equal(isSiwesPurpose("GST fee 2025/2026"), false);
  assert.equal(isSiwesPurpose("Summer semester fees, 2025/2026: CSC 301"), false);
  assert.equal(isSiwesPurpose(null), false);
});

test("the student's next step follows the server's answer, step by step", () => {
  const today = "2026-11-12";
  // eligible, open, nothing paid: pay the fee
  let n = siwesNext(OPEN, today);
  assert.equal(n.step, "PAY");
  assert.equal(n.pay, true);
  assert.equal(n.register, false);
  assert.equal(n.title, "Pay the SIWES registration fee of ₦4,000");
  // a reference already drawn: pay it, never a second one
  n = siwesNext({ ...OPEN, openReference: { reference: "MOAUM-SIW-1", amount: "4000", expiresAt: null } }, today);
  assert.equal(n.step, "PAY_REFERENCE");
  assert.match(n.words, /MOAUM-SIW-1/);
  // paid: register, and the receipt of a portal payment
  const paid = { ...OPEN, paid: { reference: "MOAUM-SIW-1", amount: "4000", receiptNo: "R1", at: "2026-11-12T10:00:00Z", source: "PORTAL" } };
  n = siwesNext(paid, today);
  assert.deepEqual([n.step, n.register, n.pay, n.receipt], ["REGISTER", true, false, true]);
  // paid with an ordinary course on the registration: the student removes it on Course Registration (their own drop door takes it), or
  // ICT Support or the Academic Office does — never "your department", which has no drop door
  n = siwesNext({ ...paid, otherCourses: ["CSC 302", "CSC 304"] }, today);
  assert.equal(n.step, "DROP_OTHERS");
  assert.equal(n.register, false);
  assert.equal(n.title, "Remove CSC 302, CSC 304 first");
  assert.equal(n.words, "In the SIWES semester you register CSC 399 alone. Remove CSC 302, CSC 304 from your Second Semester registration on Course Registration; "
    + "if you cannot, ask ICT Support or the Academic Office. Then register CSC 399 here.");
  assert.doesNotMatch(n.words, /department/);
  assert.equal(dropOthersWords(["CSC 302"]), "Remove CSC 302 from your Second Semester registration on Course Registration; if you cannot, ask ICT Support or the Academic Office");
  // registered: print the form; an old-portal payment has no portal receipt
  n = siwesNext({ ...paid, paid: { ...paid.paid, source: "OLD_PORTAL", receiptNo: null }, registration: { id: "r1", status: "APPROVED", at: "2026-11-12" } }, today);
  assert.deepEqual([n.step, n.print, n.receipt, n.register, n.pay], ["REGISTERED", true, false, false, false]);
});

test("ineligible students see why and are offered nothing", () => {
  const n = siwesNext({ ...OPEN, eligible: false, reasons: ["NOT_300_LEVEL"] }, "2026-11-12");
  assert.equal(n.step, "NOT_ELIGIBLE");
  assert.equal(n.pay || n.register || n.print, false);
  assert.equal(n.words, "SIWES registration is for 300 Level students, in the Second Semester.");
  assert.deepEqual(reasonWords(["NOT_UNDERGRADUATE", "SOMETHING_NEW"]), [
    "SIWES registration is for undergraduate students; postgraduate programmes are not part of it.", "something new"]);
  assert.equal(siwesNext({ ...OPEN, eligible: false, reasons: ["NO_PERIOD"], period: null }, "2026-11-12").step, "NO_PERIOD");
});

test("the window and the fee: nothing is paid before the fee is published or outside the dates", () => {
  assert.equal(siwesNext({ ...OPEN, fee: { amount: "4000", state: "DRAFT" } }).step, "FEE_NOT_SET");
  assert.equal(siwesNext({ ...OPEN, fee: null }).pay, false);
  const before = siwesNext({ ...OPEN, registrationOpen: false, period: { ...OPEN.period!, registrationOpens: "2026-12-01" } }, "2026-11-12");
  assert.deepEqual([before.step, before.title, before.pay], ["NOT_OPEN", "SIWES registration opens on 1 December 2026", false]);
  const after = siwesNext({ ...OPEN, registrationOpen: false, period: { ...OPEN.period!, state: "CLOSED" } }, "2026-12-20");
  assert.deepEqual([after.step, after.pay], ["CLOSED", false]);
  const paidClosed = siwesNext({ ...OPEN, registrationOpen: false, period: { ...OPEN.period!, state: "CLOSED" },
    paid: { reference: "X1", amount: 4000, receiptNo: "R", at: null, source: "PORTAL" } }, "2026-12-20");
  assert.deepEqual([paidClosed.step, paidClosed.register, paidClosed.receipt], ["PAID_CLOSED", false, true]);
});

test("whether the SIWES rule applies to the student's Second Semester: the server's applies, else registration.siwes_applies read from the reasons", () => {
  // the server's answer decides when it is sent, whatever the reasons
  assert.equal(siwesApplies({ ...OPEN, applies: false }), false);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NO_COURSE"], registration: null, applies: true }), true);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NOT_CONFIGURED"], registration: null, applies: false }), false);
  // without it: siwes_applies sets aside a student who passed SIWES, and (K22) a student not in study, as the roster and the eligibility do
  assert.equal(siwesApplies(OPEN), true);
  assert.equal(siwesApplies({ eligible: false, reasons: ["ALREADY_PASSED"], registration: null }), false);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NOT_IN_STUDY"], registration: null }), false);
  // a deferred student who registered SIWES before deferring: the registration keeps the page theirs
  assert.equal(siwesApplies({ eligible: false, reasons: ["NOT_IN_STUDY"], registration: { id: "r1", status: "APPROVED", at: null } }), true);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NO_COURSE"], registration: null }), true);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NOT_CONFIGURED"], registration: null }), false);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NOT_UNDERGRADUATE"], registration: null }), false);
  assert.equal(siwesApplies({ eligible: false, reasons: ["NO_PERIOD"], registration: null }), false);
  assert.equal(siwesApplies(null), false);
  const reg = { ...OPEN, registration: { id: "r1", status: "APPROVED", at: null } };
  assert.equal(isSiwesRegistration(reg, "2025/2026", 2), true);
  assert.equal(isSiwesRegistration(reg, "2025/2026", 1), false);
  assert.equal(isSiwesRegistration(reg, "2024/2025", 2), false);
  assert.equal(isSiwesRegistration(OPEN, "2025/2026", 2), false);
});

test("the training period and the form's SIWES rows", () => {
  assert.equal(trainingWords(OPEN.period), "4 January 2027 – 30 June 2027 (6 months)");
  assert.equal(trainingWords({ trainingStarts: null, trainingEnds: null, durationMonths: 6 }), "Not yet dated (6 months)");
  assert.equal(trainingWords(null), "Not yet dated");
  assert.deepEqual(siwesFormRows({ period: OPEN.period, paid: { reference: "MOAUM-SIW-1", amount: 4000, receiptNo: "R1", at: null, source: "PORTAL" } }), [
    ["Training period", "4 January 2027 – 30 June 2027 (6 months)"], ["SIWES fee reference", "MOAUM-SIW-1"], ["Receipt number", "R1"]]);
  assert.deepEqual(siwesFormRows(null), []);
  assert.equal(unitName({ code: "SCI", name: "Faculty of Science" }), "Faculty of Science");
  assert.equal(unitName("Computer Science"), "Computer Science");
  assert.equal(unitName(null), "");
});

test("the period form says what the database will refuse", () => {
  const f = emptyPeriodForm(null);
  assert.equal(f.state, "DRAFT");
  assert.equal(f.durationMonths, "6");
  assert.deepEqual(periodProblems(f), []);
  assert.equal(periodProblems({ ...f, state: "OPEN" }).length, 2);
  assert.deepEqual(periodProblems({ ...f, state: "OPEN", registrationOpens: "2026-11-10", registrationCloses: "2026-11-01", trainingStarts: "2027-01-04", trainingEnds: "2027-01-04" }),
    ["Registration closes on or after the day it opens.", "Training ends after it starts."]);
  assert.deepEqual(periodProblems({ ...f, durationMonths: "13" }), ["The duration is a whole number of months, 1 to 12."]);
  assert.deepEqual(periodWords({ state: "OPEN" }, false), ["Open — outside its dates", "warn"]);
  assert.deepEqual(periodWords(null), ["Not set", "grey"]);
});

test("the desk's filters, rows and exports", () => {
  assert.deepEqual(readSiwesFilters({ session: "2025/2026", faculty: "SCI", status: "PAID", q: "  ada ", source: "OLD_PORTAL", programme: "x'; drop" }),
    { session: "2025/2026", faculty: "SCI", status: "PAID", q: "ada", source: "OLD_PORTAL" });
  assert.deepEqual(readSiwesFilters({ session: "2025", status: "WHATEVER" }), {});
  assert.equal(siwesQuery({ session: "2025/2026", faculty: "", status: "UNPAID" }, { page: 0, size: 50 }), "session=2025%2F2026&status=UNPAID&page=0&size=50");
  const line = studentLine({ studentId: "s1", matricNo: "MOAUM/CSC/23/1", name: "Ada Obi", programmeCode: "CSC", programme: "Computer Science", department: "Computer Science",
    faculty: "Science", level: 300, eligible: true, reasons: [], paid: true, paymentSource: "PORTAL", paymentReference: "MOAUM-SIW-1", paidAt: "2026-11-12T10:00:00Z", amount: "4000.00",
    registered: false, registeredAt: null, courseCode: "CSC 399" }, "2025/2026");
  assert.equal(line.length, STUDENT_HEAD.length);
  assert.deepEqual(line.slice(8, 17), ["CSC 399", "Paid, not registered", "Yes", 4000, "2026-11-12", "MOAUM-SIW-1", "Portal", "No", ""]);
  // an older answer without the API's counts: worked out from eligible
  assert.deepEqual(groupLine({ code: "SCI", name: "Science", eligible: 10, paid: 7, registered: 5 }), ["Science", "SCI", 10, 7, 3, 5, 5]);
});

test("a group's yet to pay and yet to register are the API's counts, the same as the tiles: a paid student no longer eligible is not subtracted", () => {
  // registration.siwes_stats' byProgramme row: A paid and registered, then suspended (paid, not eligible); B eligible and paid; C eligible, unpaid
  const g = { code: "C97521", name: "Computer Science", eligible: 2, paid: 2, registered: 1, unpaid: 1, notRegistered: 2 };
  assert.deepEqual(groupLine(g), ["Computer Science", "C97521", 2, 2, 1, 1, 2]);
  // eligible − paid would have said 0 yet to pay and 1 yet to register
  assert.deepEqual(groupLine({ ...g, unpaid: null, notRegistered: undefined }).slice(4), [0, 1, 1]);
  // a zero from the API is a count, not a missing one
  assert.deepEqual(groupLine({ code: "X", name: "X", eligible: 3, paid: 1, registered: 0, unpaid: 0, notRegistered: 0 }).slice(4), [0, 0, 0]);
});

test("the desk lists the eligible students by default, and every student of the programmes taking SIWES on request", () => {
  // the address names no status: the eligible students, ELIGIBLE sent to the API
  assert.equal(shownStatus(undefined), "ELIGIBLE");
  assert.equal(apiStatus(undefined), "ELIGIBLE");
  assert.equal(apiStatus("PAID"), "PAID");
  // ALL: no status sent, every student of the programmes (the ineligible with their reasons)
  assert.equal(shownStatus("ALL"), "ALL");
  assert.equal(apiStatus("ALL"), undefined);
  assert.equal(apiStatus("NONSENSE"), "ELIGIBLE");
  assert.deepEqual(readSiwesFilters({ status: "ALL" }), { status: "ALL" });
  assert.deepEqual(readSiwesFilters({ status: "ELIGIBLE" }), {});
});

test("an ineligible student is never shown as yet to pay: why not, on screen and in the export", () => {
  // a row as GET /api/v1/siwes/admin/students sends it (registration.siwes_roster): eligible and reasons beside the payment
  const row = { studentId: "s2", matricNo: "MOAUM/CHM/23/9", name: "EZE, NGOZI", programmeCode: "CHM", programme: "Chemistry", departmentCode: "CHM",
    department: "Chemistry", facultyCode: "SCI", faculty: "Faculty of Science", level: 300, curriculum: "CCMAS", eligible: false, reasons: ["NO_COURSE"],
    paid: false, paymentSource: null, paymentReference: null, receiptNo: null, paidAt: null, amount: null, registered: false, registeredAt: null,
    registrationStatus: null, courseCode: null };
  assert.deepEqual(rowState(row), ["Not eligible: No SIWES course set", "grey"]);
  assert.equal(studentLine(row, "2025/2026")[9], "Not eligible: No SIWES course set");
  assert.equal(notEligibleWords(["NOT_300_LEVEL", "ALREADY_PASSED"]), "Not eligible: Not 300 Level, SIWES already passed");
  assert.equal(notEligibleWords([]), "Not eligible");
  // eligible and unpaid: yet to pay; paid: paid, not registered — even when no longer eligible; registered: registered
  assert.deepEqual(rowState({ ...row, eligible: true, reasons: [] }), ["Yet to pay", "bad"]);
  assert.deepEqual(rowState({ ...row, paid: true }), ["Paid, not registered", "warn"]);
  assert.deepEqual(rowState({ paid: true, registered: true }), ["Registered", "ok"]);
  // an older answer without eligibility reads as before
  assert.deepEqual(rowState({ paid: false, registered: false }), ["Yet to pay", "bad"]);
});

test("the student's SIWES record on the desk: fixed columns, read from the API's nested rows", () => {
  // registration.siwes_student_detail's history[]: the paid object and the SIWES registration as siwes_registration_json builds it
  const rows: SiwesHistoryRow[] = [
    { session: "2025/2026",
      paid: { reference: "MOAUM-FEE-7A1B2C", amount: 4000.0, receiptNo: "RCT-0001", at: "2026-11-12T10:00:00+01:00", source: "PORTAL" },
      registration: { id: "4aade4a2-0d3e-4c1b-9a51-6f1b8e2c9d10", at: "2026-11-13T09:30:00+01:00", status: "APPROVED", courseCode: "ZZW 302",
        registeredAt: "2026-11-13T09:30:00+01:00" } },
    { session: "2024/2025", paid: { reference: "MOAUM-LEG-0042", amount: "4000.00", paidAt: "2025-05-02", source: "OLD_PORTAL" }, registration: null },
    { session: "2023/2024", paid: null, registration: { id: "x", at: "2024-04-01T08:00:00Z", status: "DROPPED", courseCode: "ZZW 302" } },
  ];
  assert.deepEqual(HISTORY_HEAD, ["Session", "Fee paid", "Registration"]);
  assert.deepEqual(historyLine(rows[0]), ["2025/2026", "MOAUM-FEE-7A1B2C · ₦4,000 · 12 November 2026", "ZZW 302 · Approved · 13 November 2026"]);
  assert.deepEqual(historyLine(rows[1]), ["2024/2025", "MOAUM-LEG-0042 · ₦4,000 · 2 May 2025 · old portal", "Not registered"]);
  assert.deepEqual(historyLine(rows[2]), ["2023/2024", "Not paid", "ZZW 302 · Dropped · 1 April 2024"]);
  // no cell is an object printed whole, and no id is shown
  for (const r of rows) for (const cell of historyLine(r)) assert.doesNotMatch(cell, /[{}]|4aade4a2/);
});

test("the fee panel: the fee in force and the draft waiting beside it, read from finance.siwes_fee_view", () => {
  // a restatement waiting: the published amount stays in force
  const view: SiwesFeeView = {
    session: "2025/2026", amount: 4000.0, state: "PUBLISHED", publishedAt: "2026-11-12T09:00:00+01:00",
    publishedBy: "00650de7-a3df-48a1-ba99-ba3171cb040b", publishedByName: "OKAFOR, Chidi",
    draft: { amount: 5000.0, note: "Council paper 14/2026", by: "11111111-2222-3333-4444-555555555555", byName: "EZE, Ngozi", at: "2026-11-13T10:00:00+01:00" },
    history: [
      { action: "STATED", amount: 5000.0, wasAmount: 4000.0, wasState: "PUBLISHED", note: "Council paper 14/2026",
        by: "11111111-2222-3333-4444-555555555555", byName: "EZE, Ngozi", office: "studentaccounts", at: "2026-11-13T10:00:00+01:00" },
      { action: "PUBLISHED", amount: 4000.0, wasAmount: null, wasState: null, note: "the University's master prompt of 12 November 2026",
        by: "00650de7-a3df-48a1-ba99-ba3171cb040b", byName: null, office: "bursar", at: "2026-11-12T09:00:00+01:00" },
    ],
  };
  const s = feeStanding(view);
  assert.deepEqual(s.inForce, { amount: 4000, at: "2026-11-12T09:00:00+01:00", byName: "OKAFOR, Chidi" });
  assert.equal(s.draft?.amount, 5000);
  assert.equal(s.draft?.byName, "EZE, Ngozi");
  // a fee never published is its draft alone
  const fresh = feeStanding({ session: "2026/2027", amount: null, state: "DRAFT", draft: { amount: 4000, note: null, by: "u", byName: null, at: null }, history: [] });
  assert.equal(fresh.inForce, null);
  assert.equal(fresh.draft?.amount, 4000);
  // published, nothing waiting
  assert.equal(feeStanding({ ...view, draft: null }).draft, null);
  // nothing stated
  assert.deepEqual(feeStanding({ session: "2027/2028", amount: null, state: null, draft: null, history: [] }), { inForce: null, draft: null });
  // the history names the person, else the office alone — never the person's id
  assert.deepEqual(feeChange(view.history[0]), { at: "2026-11-13T10:00:00+01:00", by: "EZE, Ngozi (studentaccounts)", what: "stated", amount: 5000, was: 4000, note: "Council paper 14/2026" });
  assert.equal(feeChange(view.history[1]).by, "bursar");
  for (const h of view.history) assert.doesNotMatch(feeChange(h).by, /[0-9a-f]{8}-/);
  assert.equal(byWords(null, null), "");
});

test("a payment that does not settle the fee says what it is held as, on screen and in the export", () => {
  // rows as GET /api/v1/finance/siwes/payments sends them (finance.siwes_payments)
  const base = { studentId: "s1", matricNo: "M1", name: "Ada", programme: "CSC", department: "CS", faculty: "SCI", gateway: "INTERSWITCH",
    gatewayReference: "FBN|123", receiptNo: "R1", confirmedAt: "2026-11-12T10:00:00Z", source: "PORTAL" };
  const settles = { ...base, reference: "MOAUM-FEE-1", amount: 4000, settles: true, creditState: null };
  const open = { ...base, reference: "MOAUM-FEE-2", amount: "4000.00", settles: false, creditState: "OPEN" };
  const refunded = { ...base, reference: "MOAUM-FEE-3", amount: 4000, settles: false, creditState: "REFUNDED" };
  assert.deepEqual(paymentStanding(settles), ["Settles the fee", "ok"]);
  assert.deepEqual(paymentStanding(open), ["Held as a credit — open", "warn"]);
  assert.deepEqual(paymentStanding(refunded), ["Held as a credit — refunded", "grey"]);
  assert.deepEqual(paymentStanding({ settles: false, creditState: "APPLIED" }), ["Held as a credit — applied", "grey"]);
  assert.deepEqual(paymentStanding({ settles: false, creditState: null }), ["Does not settle the fee", "warn"]);
  assert.equal(paymentStanding({}), null);
  const pay = paymentLine(open);
  assert.equal(pay.length, PAYMENT_HEAD.length);
  assert.equal(pay[10], "2026-11-12");
  assert.equal(pay[12], "Held as a credit — open");
  assert.equal(pay[13], "");
  assert.equal(paymentLine(settles)[12], "Settles the fee");
});

test("the payments' totals are the API's on the tiles and in the export; summed from the rows the same way only when the answer carries none", () => {
  const base = { studentId: "s1", matricNo: "M1", name: "Ada", programme: "CSC", department: "CS", faculty: "SCI", gateway: "INTERSWITCH",
    gatewayReference: "FBN|123", receiptNo: "R1", confirmedAt: "2026-11-12T10:00:00Z", source: "PORTAL" };
  const settles = { ...base, reference: "MOAUM-FEE-1", amount: 4000, settles: true, creditState: null, refunded: 0 };
  const open = { ...base, reference: "MOAUM-FEE-2", amount: "4000.00", settles: false, creditState: "OPEN", refunded: 0 };
  // a credit recorded refunded: the API gives its refunded; an answer without it is read from the credit's state
  const creditRefunded = { ...base, reference: "MOAUM-FEE-3", amount: 4000, settles: false, creditState: "REFUNDED", refunded: 4000 };
  const creditRefundedOld = { ...creditRefunded, refunded: undefined };
  // the settling payment refunded on the refund desk: it settles nothing now, no credit row
  const deskRefunded = { ...base, reference: "MOAUM-FEE-4", amount: 4000, settles: false, creditState: null, refunded: "4000.00" };
  // an old-portal SIWES payment made twice: no credit row, settles nothing — held, never left out (review [2.3])
  const duplicate = { ...base, reference: "LEGACY-77", amount: 4000, settles: false, creditState: null, source: "OLD_PORTAL", gateway: null, gatewayReference: null };
  assert.deepEqual(paymentStanding(deskRefunded), ["Refunded on the refund desk", "grey"]);
  assert.deepEqual(paymentStanding(duplicate), ["Does not settle the fee", "warn"]);
  assert.equal(paymentLine(deskRefunded)[13], 4000);
  // every row that does not settle and is not refunded is held: settling + held + refunded = amount
  const rows = [settles, open, creditRefunded, deskRefunded, duplicate];
  assert.deepEqual(paymentSums(rows), { amount: 20000, settling: 4000, credits: 8000, refunded: 8000 });
  assert.deepEqual(paymentSums([creditRefundedOld]), { amount: 4000, settling: 0, credits: 0, refunded: 4000 });
  // a part given back: the rest is held
  assert.deepEqual(paymentSums([{ amount: 4000, settles: false, creditState: null, refunded: 1000 }]), { amount: 4000, settling: 0, credits: 3000, refunded: 1000 });
  // the API's totals (finance.siwes_payments over every payment the filters select) win over the page's rows
  const page = { total: 120, amount: "480000.00", amountSettling: "440000.00", amountCredits: "24000.00", amountRefunded: "16000.00", rows };
  assert.deepEqual(paymentTotals(page), { amount: 480000, settling: 440000, credits: 24000, refunded: 16000, fromRows: false });
  // an answer without them: the rows, summed as above, and said to be so
  assert.deepEqual(paymentTotals({ amount: 20000, rows }), { amount: 20000, settling: 4000, credits: 8000, refunded: 8000, fromRows: true });
  assert.equal(paymentTotals({ ...page, amountRefunded: undefined }).fromRows, true);
});

test("the credits list, read from the API's names, and which may be reopened", () => {
  // as the API lists them today (finance.siwes_credits' own columns) ...
  const db = creditRow({ id: "c1", student_id: "s1", matric_no: "M1", name: "OBI, ADA", session: "2025/2026", reference: "MOAUM-FEE-2", amount: 4000.0,
    reason: "The SIWES registration fee of 2025/2026 was already paid by MOAUM-FEE-1 (receipt R1)", state: "OPEN", created_at: "2026-11-12T11:00:00+01:00",
    settled_at: null, settled_note: null });
  assert.deepEqual(db, { id: "c1", studentId: "s1", name: "OBI, ADA", matricNo: "M1", session: "2025/2026", reference: "MOAUM-FEE-2", amount: 4000, state: "OPEN",
    reason: "The SIWES registration fee of 2025/2026 was already paid by MOAUM-FEE-1 (receipt R1)", settledNote: null, paidAt: "2026-11-12T11:00:00+01:00",
    settledAt: null, settledByName: null, automatic: false, settles: false, canRefund: false, canReopen: false, bankCheck: null, bankCheckState: null, settledKind: null });
  // no flag from the database, no action offered
  assert.deepEqual(creditActions(db), { refund: false, reopen: false, settlesNow: false });
  // ... and by the names of the contract
  const k6 = creditRow({ id: "c2", student: "EZE, NGOZI", matric: "M2", reference: "MOAUM-FEE-9", amount: "4000.00", state: "REFUNDED", note: "Voucher PV/2026/118 paid back",
    paidAt: "2026-11-10T09:00:00Z", settledAt: "2026-11-12T09:00:00Z", settledByName: "OKAFOR, Chidi" });
  assert.deepEqual([k6.name, k6.matricNo, k6.settledNote, k6.paidAt, k6.settledByName], ["EZE, NGOZI", "M2", "Voucher PV/2026/118 paid back", "2026-11-10T09:00:00Z", "OKAFOR, Chidi"]);
  // a student given by id is never shown as the name
  assert.equal(creditRow({ id: "c3", student: "00650de7-a3df-48a1-ba99-ba3171cb040b", reference: "R", amount: 1, state: "OPEN" }).name, "");
  // settled by hand: the Bursar's note; moved by the payment correction desk: the database's, reopened only by moving the payment back
  assert.equal(k6.automatic, false);
  // K19: how it was settled comes from the API (settledKind, or the database's settled_kind), never from the note
  assert.equal(creditRow({ id: "c4", reference: "R", amount: 1, state: "APPLIED", settled_kind: "MOVED", settled_note: "Voucher" }).settledKind, "MOVED");
  assert.equal(creditRow({ id: "c4", reference: "R", amount: 1, state: "APPLIED", settledKind: "MOVED" }).automatic, true);
});

test("the credits panel offers what the database says passes: Refund on canRefund, Reopen on canReopen, nothing on a note the database wrote", () => {
  // GET /api/v1/finance/siwes/credits (K6'): camelCase, with the database's own tests
  const row = { id: "c9", studentId: "s9", student: "OBI, ADA", matric: "M9", reference: "MOAUM-FEE-9", amount: "4000.00", reason: "Paid again for 2025/2026",
    paidAt: "2026-11-12T11:00:00+01:00", settledAt: null, settledByName: null, note: null, automatic: false, settles: false };
  // an open credit the Bursar may refund
  const open = creditRow({ ...row, state: "OPEN", canRefund: true, canReopen: false });
  assert.deepEqual([open.name, open.matricNo, open.canRefund, open.canReopen], ["OBI, ADA", "M9", true, false]);
  assert.deepEqual(creditActions(open), { refund: true, reopen: false, settlesNow: false });
  // refunded by hand with a voucher: the database lets it be reopened
  const byHand = creditRow({ ...row, state: "REFUNDED", note: "Voucher PV/2026/118 paid back", settledByName: "OKAFOR, Chidi", canRefund: false, canReopen: true });
  assert.equal(byHand.automatic, false);
  assert.deepEqual(creditActions(byHand), { refund: false, reopen: true, settlesNow: false });
  // an open credit whose payment now settles the fee (the settling payment was refunded on the refund desk): "Settles the fee now", no Refund
  const settles = creditRow({ ...row, state: "OPEN", settles: true, canRefund: false, canReopen: false });
  assert.deepEqual(creditActions(settles), { refund: false, reopen: false, settlesNow: true });
  // even a flag sent in error offers nothing on a credit that settles the fee
  assert.deepEqual(creditActions({ ...settles, canRefund: true }), { refund: false, reopen: false, settlesNow: true });
  // each kind the database settles itself (K19: settled_kind, written by what settled it): automatic, its note shown, no action — read
  // from the API's flag, or from the kind when no flag is sent; never from the note
  const kinds: [string, string, string][] = [
    ["MOVED", "APPLIED", "Moved by a payment correction: the payment now counts as School fees 2025/2026 (2025/2026)"],
    ["SETTLES", "APPLIED", "Settles the SIWES fee: MOAUM-FEE-1 no longer settles 2025/2026"],
    ["DESK_REFUND", "REFUNDED", "Refunded on the refund desk: RF-2026-0042"],
  ];
  for (const [kind, state, note] of kinds) {
    const flagged = creditRow({ ...row, state, note, settledKind: kind, automatic: true, canRefund: false, canReopen: false });
    assert.deepEqual([flagged.automatic, flagged.settledNote, flagged.settledKind], [true, note, kind]);
    assert.deepEqual(creditActions(flagged), { refund: false, reopen: false, settlesNow: false }, kind);
    // no automatic flag from an older answer: the kind says so, and a stray canReopen offers nothing
    const noFlag: Record<string, unknown> = { ...row };
    delete noFlag.automatic;
    const read = creditRow({ ...noFlag, state, note, settledKind: kind, canReopen: true });
    assert.equal(read.automatic, true, kind);
    assert.deepEqual(creditActions(read), { refund: false, reopen: false, settlesNow: false }, kind);
  }
  // K19 (d4-money-2): a Bursar's hand refund whose free-text note reads like the database's own is the Bursar's still — reopened as the
  // database allows it, never taken for automatic by its note
  const noFlag: Record<string, unknown> = { ...row };
  delete noFlag.automatic;
  for (const note of kinds.map(([, , n]) => n)) {
    const hand = creditRow({ ...noFlag, state: "REFUNDED", note, settledKind: "HAND_REFUND", settledByName: "OKAFOR, Chidi", canReopen: true });
    assert.equal(hand.automatic, false, note);
    assert.deepEqual(creditActions(hand), { refund: false, reopen: true, settlesNow: false }, note);
  }
  // an answer with neither the flag nor the kind: the Bursar's (nothing read from the note)
  assert.equal(creditRow({ ...noFlag, state: "APPLIED", note: kinds[0][2] }).automatic, false);
});

test("K19: how a credit was settled, in words — the kind, and the Bursar's name for a refund by hand", () => {
  const base = { state: "REFUNDED", settledAt: "2026-11-13T10:00:00+01:00", settledByName: "OKAFOR, Chidi", automatic: false };
  assert.equal(settledWords({ ...base, settledKind: "HAND_REFUND" }), "13 November 2026 · refunded by the Bursar · OKAFOR, Chidi");
  assert.equal(settledWords({ ...base, settledKind: "DESK_REFUND", automatic: true }), "13 November 2026 · refunded on the refund desk");
  assert.equal(settledWords({ ...base, state: "APPLIED", settledKind: "MOVED", automatic: true }), "13 November 2026 · moved by a payment correction");
  assert.equal(settledWords({ ...base, state: "APPLIED", settledKind: "SETTLES", automatic: true }), "13 November 2026 · settles the fee in its place (the portal)");
  assert.deepEqual(Object.keys(SETTLED_KIND_WORD).sort(), ["DESK_REFUND", "HAND_REFUND", "MOVED", "SETTLES"]);
  // an open credit was settled by nothing; an older answer without the kind says what it can
  assert.equal(settledWords({ ...base, state: "OPEN", settledKind: null }), "");
  assert.equal(settledWords({ ...base, settledKind: null, automatic: true }), "13 November 2026 · by the portal");
  assert.equal(settledWords({ ...base, settledKind: null }), "13 November 2026 · OKAFOR, Chidi");
});

test("the student's SIWES course once registered is the course registered, whatever the programme is mapped to since (K7)", () => {
  // A registered ZZW 302; the Academic Office then mapped the programme to ZZW 306
  const remapped: MySiwes = {
    ...OPEN, course: { id: "c306", code: "ZZW 306", title: "Industrial Attachment II", units: 6 },
    paid: { reference: "MOAUM-FEE-1", amount: 4000, receiptNo: "R1", at: "2026-11-12T10:00:00Z", source: "PORTAL" },
    registration: { id: "x1", status: "APPROVED", at: "2026-11-13T09:00:00+01:00", courseCode: "ZZW 302", registeredAt: "2026-11-13T09:00:00+01:00" },
    otherCourses: [],
  };
  assert.deepEqual(siwesCourseOf(remapped), { code: "ZZW 302", title: null, units: null });
  const n = siwesNext(remapped, "2026-11-13");
  assert.equal(n.step, "REGISTERED");
  assert.match(n.words, /^ZZW 302 is your Second Semester registration for 2025\/2026\./);
  assert.doesNotMatch(n.words, /ZZW 306/);
  assert.equal(siwesSemesterWords(remapped, "2025/2026").words, "Your SIWES course ZZW 302 is registered; print it on the SIWES page.");
  // the course registered is never one to remove, even from an answer that lists it among the others (as siwes_eligibility did when it
  // compared with today's mapping: otherCourses ["ZZW 302"])
  const entries = [{ offeringId: "o302", courseCode: "ZZW 302", status: "APPROVED", entryType: "CURRENT" }];
  assert.deepEqual(otherCoursesOf({ ...remapped, otherCourses: ["ZZW 302"] }), []);
  assert.deepEqual(otherCoursesOf({ ...remapped, otherCourses: ["ZZW 302", "ZZW 304"] }), ["ZZW 304"]);
  assert.deepEqual(siwesInTheWay(entries, { ...remapped, otherCourses: ["ZZW 302"] }), { ordinary: [], waiting: [] });
  assert.equal(siwesNext({ ...remapped, otherCourses: ["ZZW 302"] }, "2026-11-13").step, "REGISTERED");
  // the same course as mapped today: its title and units are known
  const same = { ...remapped, course: { id: "c302", code: "ZZW 302", title: "SIWES", units: 6 } };
  assert.deepEqual(siwesCourseOf(same), same.course);
  // before registration: the programme's course as mapped today
  assert.equal(siwesCourseOf({ ...remapped, registration: null })?.code, "ZZW 306");
  assert.equal(siwesNext({ ...remapped, registration: null }, "2026-11-13").title, "Fee paid: register ZZW 306");
  // an older answer without courseCode: today's mapping
  assert.equal(siwesCourseOf({ ...remapped, registration: { id: "x1", status: "APPROVED", at: null } })?.code, "ZZW 306");
  assert.equal(siwesCourseOf(null), null);
});

test("Course Registration's SIWES note: the words follow where the student stands, and carry-overs and deferred courses wait apart (K9)", () => {
  const paid = { reference: "MOAUM-FEE-1", amount: 4000, receiptNo: "R1", at: null, source: "PORTAL" };
  const notPaid = siwesSemesterWords(OPEN, "2025/2026");
  assert.match(notPaid.words, /^In 2025\/2026 you register the SIWES course CSC 399 — Students Industrial Work Experience \(6 units\) alone/);
  assert.match(notPaid.words, /Pay the SIWES registration fee/);
  const paidWords = siwesSemesterWords({ ...OPEN, paid }, "2025/2026");
  assert.equal(paidWords.title, "Your SIWES registration fee is paid");
  assert.match(paidWords.words, /^Register your SIWES course CSC 399/);
  assert.doesNotMatch(paidWords.words, /Pay the SIWES/);
  const registered = siwesSemesterWords({ ...OPEN, paid, registration: { id: "x", status: "APPROVED", at: null, courseCode: "CSC 399" } }, "2025/2026");
  assert.deepEqual([registered.tone, registered.words], ["ok", "Your SIWES course CSC 399 is registered; print it on the SIWES page."]);
  // the registration as Course Registration reads it, and the courses the server counts as in the way
  const entries = [
    { offeringId: "o1", courseCode: "CSC 302", status: "REGISTERED", entryType: "CURRENT" },
    { offeringId: "o2", courseCode: "CSC 204", status: "REGISTERED", entryType: "CARRYOVER" },
    { offeringId: "o3", courseCode: "GST 112", status: "REGISTERED", entryType: "DEFERRED" },
    { offeringId: "o4", courseCode: "CSC 306", status: "DROPPED", entryType: "CURRENT" },
    { offeringId: "o5", courseCode: "CSC 399", status: "REGISTERED", entryType: "CURRENT" },
  ];
  const way = siwesInTheWay(entries, { ...OPEN, otherCourses: ["CSC 302", "CSC 204", "GST 112", "CSC 399"] });
  assert.deepEqual(way.ordinary.map((e) => e.courseCode), ["CSC 302"]);
  assert.deepEqual(way.waiting.map((e) => e.courseCode), ["CSC 204", "GST 112"]);
  // a course the server does not count is not offered, and nothing when it counts none
  assert.deepEqual(siwesInTheWay(entries, { ...OPEN, otherCourses: ["CSC 204"] }).ordinary, []);
  assert.deepEqual(siwesInTheWay(entries, OPEN), { ordinary: [], waiting: [] });
  assert.deepEqual(siwesInTheWay(null, OPEN), { ordinary: [], waiting: [] });
  assert.equal(waitsWords("CSC 204"), "CSC 204 waits for a later semester: the SIWES semester holds the SIWES course alone.");
});

test("a paid student who owes the Second Semester school fees pays them first, on Fees & payments, and is offered no Register (K10)", () => {
  const today = "2026-11-12";
  const paid = { reference: "MOAUM-FEE-1", amount: 4000, receiptNo: "R1", at: null, source: "PORTAL" };
  const owes: MySiwes = { ...OPEN, paid, semesterFees: { cleared: false, outstanding: 100000 }, canRegister: false };
  let n = siwesNext(owes, today);
  assert.equal(n.step, "PAY_SCHOOL_FEES");
  assert.equal(n.title, "Pay the Second Semester school fees, then register your SIWES course");
  assert.deepEqual([n.register, n.pay, n.receipt, n.print], [false, false, true, false]);
  assert.deepEqual(n.link, { href: "/student/fees", label: "Fees & payments" });
  assert.equal(n.link?.href, FEES_PAGE.href);
  assert.match(n.words, /school fees for 2025\/2026 are not fully paid: ₦100,000 outstanding/);
  assert.match(n.words, /then register CSC 399 here\.$/);
  // no amount named by the server: no amount said
  assert.doesNotMatch(siwesNext({ ...owes, semesterFees: { cleared: false, outstanding: null } }, today).words, /outstanding/);
  // cleared: Register, and no other page to go to
  n = siwesNext({ ...owes, semesterFees: { cleared: true, outstanding: 0 }, canRegister: true }, today);
  assert.deepEqual([n.step, n.register, n.link], ["REGISTER", true, null]);
  // an older answer that says nothing of the school fees: Register as before
  n = siwesNext({ ...OPEN, paid }, today);
  assert.deepEqual([n.step, n.register], ["REGISTER", true]);
  // the server's canRegister false never offers a Register the database would refuse
  n = siwesNext({ ...OPEN, paid, semesterFees: { cleared: true, outstanding: null }, canRegister: false }, today);
  assert.deepEqual([n.step, n.register], ["REGISTER", false]);
  assert.equal(n.words, "Your SIWES registration fee is paid, but CSC 399 cannot be registered yet; ask the Academic Office.");
  // siwes_register refuses the other courses first: they are named first, the school fees beside them
  n = siwesNext({ ...owes, otherCourses: ["CSC 302"] }, today);
  assert.equal(n.step, "DROP_OTHERS");
  assert.match(n.words, /The Second Semester school fees for 2025\/2026 are not fully paid: ₦100,000 outstanding; they are paid on Fees & payments\. Then register CSC 399 here\.$/);
  // fees the Bursary has not stated yet hold it too (semesterFees.stated, which canRegister waits on)
  const unstated: MySiwes = { ...owes, semesterFees: { cleared: true, outstanding: null, stated: false } };
  n = siwesNext(unstated, today);
  assert.deepEqual([n.step, n.register, n.link?.href], ["PAY_SCHOOL_FEES", false, "/student/fees"]);
  assert.match(n.words, /but the Bursary has not yet stated the Second Semester school fees for 2025\/2026\./);
  assert.equal(schoolFeesWords({ semesterFees: { cleared: false, outstanding: "2500.50" } }, "2025/2026"), "the Second Semester school fees for 2025/2026 are not fully paid: ₦2,500.5 outstanding");
  // not yet paid: the SIWES fee comes first; registered: the step is the registration
  assert.equal(siwesNext({ ...OPEN, semesterFees: { cleared: false, outstanding: 100000 } }, today).step, "PAY");
  assert.equal(siwesNext({ ...owes, registration: { id: "x", status: "APPROVED", at: null, courseCode: "CSC 399" } }, today).step, "REGISTERED");
  // only an explicit false holds it
  assert.equal(schoolFeesOwed(owes), true);
  assert.equal(schoolFeesOwed(unstated), true);
  assert.equal(schoolFeesOwed({ semesterFees: { cleared: true, outstanding: 0, stated: true } }), false);
  assert.equal(schoolFeesOwed({ semesterFees: { cleared: true, outstanding: 0 } }), false);
  assert.equal(schoolFeesOwed({}), false);
  assert.equal(schoolFeesOwed(null), false);
  // Course Registration's SIWES note says the same
  const w = siwesSemesterWords(owes, "2025/2026");
  assert.equal(w.title, "Pay the Second Semester school fees, then register your SIWES course");
  assert.match(w.words, /^Your SIWES registration fee is paid\. The Second Semester school fees for 2025\/2026 are not fully paid: ₦100,000 outstanding; pay them on Fees & payments, then register your SIWES course CSC 399/);
  assert.match(siwesSemesterWords(unstated, "2025/2026").words, /^Your SIWES registration fee is paid\. The Bursary has not yet stated the Second Semester school fees for 2025\/2026; pay them/);
  assert.equal(siwesSemesterWords({ ...owes, semesterFees: { cleared: true, outstanding: 0 } }, "2025/2026").title, "Your SIWES registration fee is paid");
});

test("the courses in the way of the SIWES course: Remove only while add and drop is open, the reset when the reset door allows it, otherwise the offices (K11)", () => {
  assert.deepEqual(siwesClearing({ addDropOpen: true, resetAllowed: false, count: 2 }),
    { remove: true, reset: false, words: "Remove them below while add and drop is open; if you cannot, ask the Academic Office or ICT Support." });
  assert.deepEqual(siwesClearing({ addDropOpen: true, resetAllowed: true, count: 1 }),
    { remove: true, reset: true, words: "Remove it below while add and drop is open, or reset the registration below." });
  // add and drop closed while the SIWES window runs: the reset, never a Remove the drop door refuses
  assert.deepEqual(siwesClearing({ addDropOpen: false, resetAllowed: true, count: 2 }),
    { remove: false, reset: true, words: "Add and drop is not open, so they are not removed one by one: reset the registration below to clear them." });
  assert.match(siwesClearing({ addDropOpen: false, resetAllowed: true, count: 1 }).words, /so it is not removed one by one: reset the registration below to clear it\.$/);
  // neither: the Academic Office (or ICT Support, whose drop takes any course but the SIWES course there)
  assert.deepEqual(siwesClearing({ addDropOpen: false, resetAllowed: false, count: 1 }),
    { remove: false, reset: false, words: "Add and drop is not open and the registration cannot be reset now: ask the Academic Office or ICT Support to remove it." });
  // an answer that does not say offers nothing; nothing in the way, nothing offered
  assert.deepEqual(siwesClearing({ addDropOpen: undefined, resetAllowed: null, count: 3 }).remove, false);
  assert.deepEqual(siwesClearing({ addDropOpen: undefined, resetAllowed: null, count: 3 }).reset, false);
  assert.deepEqual(siwesClearing({ addDropOpen: true, resetAllowed: true, count: 0 }), { remove: false, reset: false, words: "" });
  assert.match(SIWES_RESET_WORDS, /the courses, carry-overs and deferred courses are cleared; carry-overs and deferred courses wait for a later semester\./);
});

test("the refund desk refunds a SIWES payment once, whole: the hint beside the amount, for a SIWES purpose only (K13, K36)", () => {
  assert.equal(siwesRefundHint("School fees 2025/2026", 100000, 50000), null);
  assert.equal(siwesRefundHint(null, 4000, 4000), null);
  assert.equal(siwesRefundHint("SIWES registration fee 2025/2026", null, 4000), null);
  assert.deepEqual(siwesRefundHint("SIWES registration fee 2025/2026", 4000, "4000"),
    { part: false, words: "A SIWES registration fee is refunded once, whole or not at all: the whole ₦4,000 of the payment." });
  assert.deepEqual(siwesRefundHint("SIWES (legacy)", "4000.00", "1000"),
    { part: true, words: "A SIWES registration fee is refunded once, whole or not at all: the whole ₦4,000 of the payment; a part is refused." });
  // V762 (K36): more than the payment is refused as more than was paid (REFUND_SIWES_GIVEN_BACK), never called a part
  assert.deepEqual(siwesRefundHint("SIWES registration fee 2025/2026", 4000, "8000"),
    { part: true, words: "A SIWES registration fee is refunded once, whole or not at all: the whole ₦4,000 of the payment; more than was paid is refused." });
  assert.equal(siwesRefundHint("SIWES (legacy)", 4000, "")?.part, false);
});

test("today is read in Lagos", () => {
  // 23:30 UTC on 12 November is already 13 November in Lagos (UTC+1)
  assert.equal(lagosToday(new Date("2026-11-12T23:30:00Z")), "2026-11-13");
});

test("the filters offer the office's own structure, narrowed by the faculty and department chosen, the programmes taking SIWES first", () => {
  const tree: UnitTree = { faculties: [
    { code: "SCI", name: "Science", departments: [
      { code: "CSC", name: "Computer Science", programmes: [{ code: "B001", name: "Computer Science" }, { code: "B009", name: "Old CS", archived: true }] },
      { code: "BCH", name: "Biochemistry", programmes: [{ code: "B002", name: "Biochemistry" }] },
    ] },
    { code: "ART", name: "Arts", departments: [{ code: "MAC", name: "Mass Communication", programmes: [{ code: "A001", name: "Mass Communication" }] }] },
  ] };
  const all = unitOptions(tree, {});
  assert.deepEqual(all.faculties, [["SCI", "Science"], ["ART", "Arts"]]);
  assert.deepEqual(all.programmes.map(([c]) => c), ["B001", "B002", "A001"]);
  const sci = unitOptions(tree, { faculty: "SCI" }, ["B001", "B002"]);
  assert.deepEqual(sci.departments.map(([c]) => c), ["CSC", "BCH"]);
  assert.deepEqual(sci.programmes, [["B001", "Computer Science"], ["B002", "Biochemistry"]]);
  assert.deepEqual(unitOptions(tree, { faculty: "SCI", department: "BCH" }, ["B001", "B002"]).programmes, [["B002", "Biochemistry"]]);
  // a configured list that names none of the department's programmes leaves the filter empty, never the whole University
  assert.deepEqual(unitOptions(tree, { faculty: "ART" }, ["B001"]).programmes, []);
  assert.equal(scopeWords({ session: "2025/2026", faculty: "SCI", programme: "B002" }, sci, ["Paid", null]), "2025/2026 · Science · Biochemistry · Paid");
  assert.equal(scopeWords({ session: "2025/2026", department: "ZZZ" }, sci), "2025/2026 · ZZZ");
});

test("K15: a credit held for the Bursary's bank check says why and where, and is offered no Refund", () => {
  const words = "payment MOAUM-LEG-X-S2-SIWES-PAYA2 may be a bank double charge: MOAUM-LEG-X-S2-SIWES, of the same day (19 Oct 2026) and amount, is under another "
    + "payment number; check them with the bank first (Old Fees History, possible double charges)";
  // the API's camelCase, and the database's own columns (K31: the code beside the words)
  const held = creditRow({ id: "c1", student: "OBI, ADA", reference: "MOAUM-LEG-X-S2-SIWES-PAYA2", amount: "4000.00", state: "OPEN", automatic: false, settles: false,
    canRefund: false, canReopen: false, bankCheck: words, bankCheckState: "UNCHECKED" });
  assert.deepEqual([held.bankCheck, held.bankCheckState], [words, "UNCHECKED"]);
  const fromDb = creditRow({ id: "c1", reference: "R", amount: 1, state: "OPEN", bank_check: words, bank_check_state: "UNCHECKED" });
  assert.deepEqual([fromDb.bankCheck, fromDb.bankCheckState], [words, "UNCHECKED"]);
  assert.deepEqual([creditRow({ id: "c1", reference: "R", amount: 1, state: "OPEN" }).bankCheck, creditRow({ id: "c1", reference: "R", amount: 1, state: "OPEN" }).bankCheckState], [null, null]);
  // no Refund on it, even from a flag sent in error
  assert.deepEqual(creditActions(held), { refund: false, reopen: false, settlesNow: false });
  assert.deepEqual(creditActions({ ...held, canRefund: true }), { refund: false, reopen: false, settlesNow: false });
  // the words, a sentence; Old Fees History linked for the offices whose menu carries it, the words alone for the auditors
  const bursar = creditBankCheck(held, "bursar");
  assert.equal(bursar?.words, `P${words.slice(1)}.`);
  assert.deepEqual([bursar?.state, bursar?.pill], ["UNCHECKED", ["Check with the bank first", "warn"]]);
  assert.deepEqual(bursar?.page, { href: "/finance/legacy-fees", label: "Old Fees History" });
  assert.deepEqual(OLD_FEES_PAGE, { href: "/finance/legacy-fees", label: "Old Fees History" });
  assert.equal(creditBankCheck(held, "studentaccounts")?.page?.href, "/finance/legacy-fees");
  assert.equal(creditBankCheck(held, "audit")?.page, null);
  assert.equal(creditBankCheck(held, null)?.page, null);
  // checked RECEIVED: the database sends neither, and the Refund is the database's to offer again
  const checked = { ...held, bankCheck: null, bankCheckState: null, canRefund: true };
  assert.equal(creditBankCheck(checked, "bursar"), null);
  assert.deepEqual(creditActions(checked), { refund: true, reopen: false, settlesNow: false });
  // a code with no words still holds the Refund back
  assert.deepEqual(creditActions({ ...checked, bankCheckState: "UNCHECKED" }), { refund: false, reopen: false, settlesNow: false });
  // a withdrawal waiting, in the database's words (already a sentence once it ends in a full stop)
  assert.equal(creditBankCheck({ ...held, bankCheckState: "PROPOSED", bankCheck: "the withdrawal of R2 as never received by the bank waits for a second Bursary officer (Payments not received); payment R1 is not refunded until it is decided." }, "bursar")?.words,
    "The withdrawal of R2 as never received by the bank waits for a second Bursary officer (Payments not received); payment R1 is not refunded until it is decided.");
  // a refunded credit waits on nothing; an open one does, and one that settles the fee meanwhile too, open or APPLIED (K20, K27: it
  // still says what it waits on)
  assert.equal(creditBankCheck({ ...held, state: "REFUNDED" }, "bursar"), null);
  const settling: SiwesCredit = { ...held, settles: true };
  assert.equal(creditBankCheck(settling, "bursar")?.state, "UNCHECKED");
  assert.equal(creditBankCheck({ ...settling, state: "APPLIED", bankCheckState: "NOT_RECEIVED_WAITING" }, "bursar")?.state, "NOT_RECEIVED_WAITING");
});

test("v4-3, K20, K31: the pill over a held credit follows the database's code for the wait, never the words; never 'check with the bank' once checked", () => {
  const waits = "the withdrawal of MOAUM-LEG-X-S2-SIWES as never received by the bank waits for a second Bursary officer (Payments not received); "
    + "payment MOAUM-LEG-X-S2-SIWES-PAYA2 is not refunded or moved until it is decided";
  const notReceived = "the bank check of 13 Nov 2026 (Old Fees History, possible double charges) found payment MOAUM-LEG-X-S2-SIWES never received; "
    + "until it is withdrawn (Payments not received), payment MOAUM-LEG-X-S2-SIWES-PAYA2 is not refunded or moved";
  const notChecked = "payment R2 may be a bank double charge: R1, of the same day (19 Oct 2026) and amount, is under another payment number; "
    + "check them with the bank first (Old Fees History, possible double charges)";
  // K27: the payment the bank received settles the fee meanwhile, its credit APPLIED (SETTLES), held all the same
  const base = { id: "c1", student: "OBI, ADA", reference: "MOAUM-LEG-X-S2-SIWES-PAYA2", amount: "4000.00", state: "APPLIED", settledKind: "SETTLES", automatic: true,
    canRefund: false, canReopen: false };
  // the API's bankCheckState: the database's code, passed through
  const w = creditBankCheck(creditRow({ ...base, settles: true, bankCheck: waits, bankCheckState: "PROPOSED" }), "bursar");
  assert.deepEqual([w?.state, w?.pill], ["PROPOSED", ["Withdrawal waiting", "warn"]]);
  assert.match(w?.words ?? "", /^The withdrawal of MOAUM-LEG-X-S2-SIWES as never received by the bank waits for a second Bursary officer/);
  // s5-1: the record the bank received, waiting on the other one's withdrawal, is never marked "Found never received" — though its words
  // name a record never received
  const nrw = creditBankCheck(creditRow({ ...base, settles: true, bankCheck: notReceived, bankCheckState: "NOT_RECEIVED_WAITING" }), "bursar");
  assert.deepEqual([nrw?.state, nrw?.pill], ["NOT_RECEIVED_WAITING", ["Waits on another record's withdrawal", "warn"]]);
  assert.deepEqual(nrw?.page, { href: "/finance/legacy-fees", label: "Old Fees History" });
  // the record never received itself (as the payments list carries it): the bad pill
  const nr = creditBankCheck(creditRow({ ...base, state: "OPEN", settles: false, bankCheck: notReceived, bankCheckState: "NOT_RECEIVED" }), "bursar");
  assert.deepEqual([nr?.state, nr?.pill], ["NOT_RECEIVED", ["Found never received", "bad"]]);
  // never read from the words: the database's own column, the codes alone; a round-5 word or none at all is no code here
  assert.equal(creditRow({ ...base, bank_check: notReceived, bank_check_state: "NOT_RECEIVED_WAITING" }).bankCheckState, "NOT_RECEIVED_WAITING");
  assert.equal(creditRow({ ...base, bank_check: notReceived }).bankCheckState, null);
  for (const old of ["WITHDRAWAL_WAITING", "NOT_CHECKED", "HELD", "", null]) assert.equal(bankCheckStateOf({ bankCheckState: old }), null, String(old));
  assert.equal(bankCheckStateOf({ bankCheckState: "UNCHECKED" }), "UNCHECKED");
  // words that come with no code known here: held, the words shown, no wait named from them
  for (const words of [waits, notReceived, notChecked]) {
    const plain = creditBankCheck(creditRow({ ...base, state: "OPEN", settles: false, bankCheck: words }), "bursar");
    assert.deepEqual([plain?.state, plain?.pill], [null, BANK_HOLD_PILL]);
    assert.ok((plain?.words ?? "").length > 0);
  }
  assert.deepEqual(bankHoldPill({ bankCheck: null, bankCheckState: null }), null);
  // the pill says "check with the bank" for a check not yet made alone, and "never received" for the record never received alone
  for (const [state, [word]] of Object.entries(BANK_CHECK_PILL)) {
    assert.equal(/check with the bank/i.test(word), state === "UNCHECKED", state);
    assert.equal(/never received/i.test(word), state === "NOT_RECEIVED", state);
  }
  assert.equal(/check with the bank|never received/i.test(BANK_HOLD_PILL[0]), false);
  // held: no Refund, however the flags read; the credit that settles the fee meanwhile says so beside the words
  assert.deepEqual(creditActions({ ...creditRow({ ...base, automatic: false, settles: true, bankCheck: notReceived, bankCheckState: "NOT_RECEIVED_WAITING" }), canRefund: true }),
    { refund: false, reopen: false, settlesNow: true });
});

test("K31: the Bursary's payments list carries the bank check's code and words, on screen and in the export", () => {
  const notReceived = "the bank check of 13 Nov 2026 (Old Fees History, possible double charges) found payment MOAUM-LEG-X-S2-SIWES never received; "
    + "until it is withdrawn (Payments not received), payment MOAUM-LEG-X-S2-SIWES-PAYA2 is not refunded or moved";
  const base = { studentId: "s1", matricNo: "M1", name: "Ada", programme: "CSC", department: "CS", faculty: "SCI", gateway: null, gatewayReference: null,
    receiptNo: "R1", confirmedAt: "2026-10-19T10:00:00Z", source: "OLD_PORTAL", amount: 4000, refunded: 0 };
  // as GET /api/v1/finance/siwes/payments sends them (finance.siwes_payments' bank_check and bank_check_state)
  const never = { ...base, reference: "MOAUM-LEG-X-S2-SIWES", settles: false, creditState: null, bankCheck: notReceived.replace("payment MOAUM-LEG-X-S2-SIWES-PAYA2", "payment MOAUM-LEG-X-S2-SIWES"), bankCheckState: "NOT_RECEIVED" };
  const received = { ...base, reference: "MOAUM-LEG-X-S2-SIWES-PAYA2", settles: true, creditState: "APPLIED", bankCheck: notReceived, bankCheckState: "NOT_RECEIVED_WAITING" };
  // a portal payment: the API leaves both out (null fields are not sent)
  const free: SiwesPaymentRow = { ...base, reference: "MOAUM-FEE-1", source: "PORTAL", settles: true, creditState: null };
  assert.deepEqual([paymentBankCheck(never, "bursar")?.state, paymentBankCheck(never, "bursar")?.pill], ["NOT_RECEIVED", ["Found never received", "bad"]]);
  // s5-1: the one the bank received is never marked never received
  assert.deepEqual([paymentBankCheck(received, "bursar")?.state, paymentBankCheck(received, "bursar")?.pill], ["NOT_RECEIVED_WAITING", ["Waits on another record's withdrawal", "warn"]]);
  assert.match(paymentBankCheck(received, "bursar")?.words ?? "", /^The bank check of 13 Nov 2026 .* is not refunded or moved\.$/);
  assert.deepEqual(paymentBankCheck(received, "bursar")?.page, { href: "/finance/legacy-fees", label: "Old Fees History" });
  assert.equal(paymentBankCheck(received, "audit")?.page, null);
  assert.equal(paymentBankCheck(free, "bursar"), null);
  assert.equal(paymentBankCheck({ ...received, bankCheck: null, bankCheckState: "UNCHECKED" }, "bursar")?.pill[0], "Check with the bank first");
  // the export: the pill's words in the last column, empty where nothing waits
  assert.equal(PAYMENT_HEAD.at(-1), "Bank Check");
  assert.equal(paymentLine(never).length, PAYMENT_HEAD.length);
  assert.equal(paymentLine(never).at(-1), "Found never received");
  assert.equal(paymentLine(received).at(-1), "Waits on another record's withdrawal");
  assert.equal(paymentLine(free).at(-1), "");
});

test("K35: a payment given back shows no bank-check hold on the payments list, by the credits list's rule", () => {
  const words = "the withdrawal of payment MOAUM-LEG-X-S2-SIWES as never received waits for a second Bursary officer (Payments not received); "
    + "until it is decided, payment MOAUM-LEG-X-S2-SIWES-PAYA2 is not refunded or moved";
  const base = { studentId: "s1", matricNo: "M1", name: "Ada", programme: "CSC", department: "CS", faculty: "SCI", gateway: null, gatewayReference: null,
    receiptNo: "R1", confirmedAt: "2026-10-19T10:00:00Z", source: "OLD_PORTAL", amount: 4000, reference: "MOAUM-LEG-X-S2-SIWES-PAYA2" };
  // its credit refunded by the Bursar's hand: given back, whatever an answer carries (the database sends no hold for it now)
  const handRefunded: SiwesPaymentRow = { ...base, settles: false, creditState: "REFUNDED", refunded: 4000, bankCheck: words, bankCheckState: "PROPOSED" };
  // refunded whole on the refund desk, with no credit (the payment that settled the fee)
  const deskRefunded: SiwesPaymentRow = { ...base, reference: "MOAUM-LEG-X-S2-SIWES", settles: false, creditState: null, refunded: 4000, bankCheck: words, bankCheckState: "PROPOSED" };
  for (const r of [handRefunded, deskRefunded]) {
    assert.equal(paymentGivenBack(r), true, r.reference);
    assert.equal(paymentBankCheck(r, "bursar"), null, r.reference);
    assert.equal(paymentLine(r).at(-1), "", r.reference);
    assert.ok(/refunded/i.test(paymentStanding(r)?.[0] ?? ""), r.reference);
  }
  // held still: a credit open or applied (even with part of its payment given back on the desk), and a payment that settles
  for (const r of [{ ...handRefunded, creditState: "OPEN", refunded: 0 }, { ...handRefunded, creditState: "APPLIED", settles: true, refunded: 0 },
    { ...handRefunded, creditState: "OPEN", refunded: 1000 }, { ...deskRefunded, refunded: 0, settles: true }]) {
    assert.equal(paymentGivenBack(r), false, JSON.stringify(r));
    assert.equal(paymentBankCheck(r, "bursar")?.state, "PROPOSED", JSON.stringify(r));
    assert.equal(paymentLine(r).at(-1), "Withdrawal waiting", JSON.stringify(r));
  }
  // as the credits list shows a refunded credit: no hold
  assert.equal(creditBankCheck({ state: "REFUNDED", bankCheck: words, bankCheckState: "PROPOSED" }, "bursar"), null);
});

test("K33: a reopened credit says what it became, from the database's answer", () => {
  // the credit as finance.siwes_credit_reopen returns it (the table's names): nothing else settles the fee, so it settles it
  assert.equal(reopenedWords({ id: "c1", state: "APPLIED", settled_kind: "SETTLES", settled_note: "the refund of X recorded by hand was reopened" }),
    "Reopened: it now settles the student's fee, as no other payment does");
  assert.equal(reopenedWords({ state: "APPLIED", settledKind: "SETTLES" }), "Reopened: it now settles the student's fee, as no other payment does");
  // another payment settles: an open credit again, the Bursar's to refund
  assert.equal(reopenedWords({ id: "c1", state: "OPEN", settled_kind: null }), "Reopened: an open credit again");
  // an answer that does not say (none, or one not known here): reopened, nothing more claimed
  for (const raw of [null, undefined, "x", {}, { state: "APPLIED", settled_kind: "MOVED" }]) assert.equal(reopenedWords(raw), "Reopened", JSON.stringify(raw));
});

test("K30: a session's SIWES wholly undone is said so on the SIWES page, never 'not in SIWES registration'", () => {
  const today = "2026-11-13";
  // A after K12: the level corrected to 200, the SIWES course dropped by the Academic Office, the fee given back — nothing of A's SIWES
  // stands in 2025/2026 (GET /me/siwes: registration and paid null; the history keeps the session with the registration DROPPED)
  const undone: MySiwes = { ...OPEN, eligible: false, applies: false, reasons: ["NOT_300_LEVEL"], level: 200, canRegister: false,
    history: [{ session: "2025/2026", paid: null, registration: { id: "x", status: "DROPPED", courseCode: "CSC 399", at: "2026-11-10T10:00:00Z" } }] };
  assert.equal(siwesUndone(undone)?.session, "2025/2026");
  const n = siwesNext(undone, today);
  assert.deepEqual([n.step, n.tone, n.pay, n.register, n.print, n.receipt], ["UNDONE", "info", false, false, false, false]);
  assert.equal(n.title, "Your SIWES of 2025/2026 was undone");
  assert.match(n.words, /^Your SIWES course CSC 399 of 2025\/2026 was dropped by the Academic Office or ICT Support, and no SIWES payment of yours stands for the session\./);
  assert.equal(siwesCardShown(undone), false);
  assert.deepEqual(siwesTiles(undone, n.step)[1], ["You", "SIWES undone", "SIWES registration is for 300 Level students, in the Second Semester."]);
  assert.deepEqual(siwesTiles(undone, n.step)[2], ["SIWES fee", "Nothing owed", "SIWES is not yours in 2025/2026"]);
  // withdrawn alike
  assert.equal(siwesNext({ ...undone, history: [{ ...undone.history![0], registration: { status: "WITHDRAWN" } }] }, today).step, "UNDONE");
  // the payment still standing: not undone (the history's paid; GET /me/siwes then sends paid too)
  const paidStill = { ...undone, history: [{ ...undone.history![0], paid: { reference: "R1", amount: 4000, source: "PORTAL" } }] };
  assert.equal(siwesUndone(paidStill), null);
  // still bound (dropped by an office, the fee given back): the steps of a bound student, to pay and register again
  assert.equal(siwesNext({ ...undone, eligible: true, applies: true, reasons: [], level: 300 }, today).step, "PAY");
  // an undone past session, the current one shown: not eligible for this one, as before (v4-4)
  assert.equal(siwesNext({ ...undone, history: [{ ...undone.history![0], session: "2024/2025" }] }, today).step, "NOT_ELIGIBLE");
});

test("s4-1: a student SIWES no longer binds sees no dashboard card, and the SIWES page names the sessions their SIWES is in", () => {
  const today = "2026-11-13";
  // registered SIWES in 2024/2025 at 300 Level; at 400 Level in 2025/2026, where the period is OPEN (probe review6/p2)
  const past: MySiwes = { ...OPEN, eligible: false, applies: false, reasons: ["NOT_300_LEVEL"], level: 400, canRegister: false,
    history: [
      { session: "2025/2026", paid: null, registration: null },
      { session: "2024/2025", paid: { reference: "MOAUM-SIW-24", amount: 4000, at: "2025-03-01T10:00:00Z", source: "PORTAL" },
        registration: { id: "x", status: "APPROVED", courseCode: "CSC 399", at: "2025-03-02T10:00:00Z" } },
    ] };
  assert.equal(siwesCardShown(past), false);
  const n = siwesNext(past, today);
  assert.deepEqual([n.step, n.tone, n.pay, n.register, n.print], ["ELSEWHERE", "info", false, false, false]);
  assert.equal(n.title, "Your SIWES is in 2024/2025");
  assert.match(n.words, /^SIWES is not part of your registration for 2025\/2026\. Your SIWES of 2024\/2025/);
  assert.deepEqual(siwesElsewhere(past).map((h) => h.session), ["2024/2025"]);
  // a draft period (applies false): no card, whatever the period says
  assert.equal(siwesCardShown({ ...OPEN, eligible: false, applies: false, reasons: ["NO_PERIOD"], period: { ...OPEN.period!, state: "DRAFT" } }), false);
  // the card while SIWES binds, or once paid or registered
  assert.equal(siwesCardShown(OPEN), true);
  assert.equal(siwesCardShown({ ...OPEN, eligible: false, applies: true, reasons: ["NO_COURSE"] }), true);
  assert.equal(siwesCardShown({ ...past, paid: { reference: "R", amount: 4000, receiptNo: null, at: null, source: "OLD_PORTAL" } }), true);
  assert.equal(siwesCardShown(null), false);
  // nothing elsewhere: not eligible, as before; the session shown is never listed as elsewhere
  assert.equal(siwesNext({ ...past, history: [] }, today).step, "NOT_ELIGIBLE");
  assert.equal(siwesNext({ ...past, history: undefined }, today).step, "NOT_ELIGIBLE");
  assert.deepEqual(siwesElsewhere({ session: "2024/2025", history: past.history }), []);
  // v4-4: a past SIWES wholly undone (its registration dropped, no payment standing) is not the student's SIWES: not elsewhere
  const undone: MySiwes = { ...past, history: [{ session: "2024/2025", paid: null, registration: { id: "x", status: "DROPPED", courseCode: "CSC 399", at: null } }] };
  assert.deepEqual(siwesElsewhere(undone), []);
  assert.equal(siwesNext(undone, today).step, "NOT_ELIGIBLE");
  // dropped with its payment standing: the payment keeps that session the student's
  const paidDropped: MySiwes = { ...undone, history: [{ ...undone.history![0], paid: { reference: "R24", amount: 4000, source: "PORTAL" } }] };
  assert.deepEqual(siwesElsewhere(paidDropped).map((h) => h.session), ["2024/2025"]);
  assert.deepEqual(siwesElsewhere({ ...undone, history: [{ ...undone.history![0], registration: { status: "WITHDRAWN" } }] }), []);
  // the past session itself, opened with ?session=: the registration there, printed as ever
  const there = siwesNext({ ...past, session: "2024/2025", eligible: true, applies: true, reasons: [], level: 300,
    paid: { reference: "MOAUM-SIW-24", amount: 4000, receiptNo: "R24", at: null, source: "PORTAL" },
    registration: { id: "x", status: "APPROVED", at: null, courseCode: "CSC 399" } }, today);
  assert.deepEqual([there.step, there.print, there.receipt], ["REGISTERED", true, true]);
  // a bound student who registered SIWES once before still sees this session's steps
  assert.equal(siwesNext({ ...OPEN, history: past.history }, today).step, "PAY");
});

test("s4-4: Course Registration's SIWES note follows the SIWES window, as the SIWES page does", () => {
  const closed = { ...OPEN, registrationOpen: false, period: { ...OPEN.period!, state: "CLOSED" } };
  let w = siwesSemesterWords(closed, "2025/2026", "2026-12-20");
  assert.deepEqual([w.tone, w.title], ["bad", "SIWES registration is closed"]);
  assert.match(w.words, /^In 2025\/2026 your Second Semester holds the SIWES course CSC 399 — Students Industrial Work Experience \(6 units\) alone: no other course and no carry-over\./);
  assert.match(w.words, /No SIWES payment is taken and no SIWES course is registered now; ask the Academic Office\.$/);
  assert.doesNotMatch(w.words, /Pay the SIWES registration fee/);
  // the SIWES page says the same of that answer
  assert.equal(siwesNext(closed, "2026-12-20").step, "CLOSED");
  // paid, closed: nothing registered now
  w = siwesSemesterWords({ ...closed, paid: { reference: "R1", amount: 4000, receiptNo: null, at: null, source: "PORTAL" } }, "2025/2026", "2026-12-20");
  assert.match(w.words, /Your SIWES registration fee is paid, but no SIWES course is registered now; ask the Academic Office\.$/);
  // OPEN but outside its dates: closed after them; before them, the day it opens
  w = siwesSemesterWords({ ...OPEN, registrationOpen: false }, "2025/2026", "2026-12-20");
  assert.equal(w.title, "SIWES registration is closed");
  w = siwesSemesterWords({ ...OPEN, registrationOpen: false, period: { ...OPEN.period!, registrationOpens: "2026-12-01" } }, "2025/2026", "2026-11-13");
  assert.deepEqual([w.tone, w.title], ["info", "SIWES registration opens on 1 December 2026"]);
  assert.match(w.words, /Pay the SIWES registration fee and register the course on the SIWES page once registration opens\./);
  // the fee not yet published: nothing to pay yet
  w = siwesSemesterWords({ ...OPEN, fee: { amount: "4000", state: "DRAFT" } }, "2025/2026");
  assert.match(w.words, /The Bursary has not published the SIWES registration fee yet; pay it and register the course on the SIWES page once it does\./);
  // open, published, unpaid: as before
  assert.match(siwesSemesterWords(OPEN, "2025/2026").words, /Pay the SIWES registration fee and register the course on the SIWES page/);
  // registered: registered, whatever the window
  assert.equal(siwesSemesterWords({ ...closed, registration: { id: "x", status: "APPROVED", at: null, courseCode: "CSC 399" } }, "2025/2026").tone, "ok");
});

test("s4-5: the SIWES page's courses in the way say what Course Registration offers now (K11)", () => {
  const today = "2026-11-13";
  const paid: MySiwes = { ...OPEN, paid: { reference: "R1", amount: 4000, receiptNo: "R", at: null, source: "PORTAL" }, otherCourses: ["CSC 204", "CSC 206", "CSC 304"] };
  // add and drop closed, the reset refused (probe review6/p3: REG_RESET_OFF): the offices, never a Remove Course Registration does not offer
  let n = siwesNext({ ...paid, clearing: { addDropOpen: false, resetAllowed: false, resetWhy: "REG_RESET_OFF: student resets are off" } }, today);
  assert.equal(n.step, "DROP_OTHERS");
  assert.equal(n.title, "Ask the Academic Office or ICT Support to remove CSC 204, CSC 206, CSC 304");
  assert.equal(n.words, "In the SIWES semester you register CSC 399 alone. Add and drop is not open and your Second Semester registration cannot be reset now: "
    + "ask the Academic Office or ICT Support to remove CSC 204, CSC 206, CSC 304. Then register CSC 399 here.");
  assert.equal(n.link, null);
  assert.doesNotMatch(n.words, /Remove CSC/);
  // the reset allowed: reset it on Course Registration, linked
  n = siwesNext({ ...paid, clearing: { addDropOpen: false, resetAllowed: true } }, today);
  assert.equal(n.title, "Reset your Second Semester registration first");
  assert.match(n.words, /Add and drop is not open, so CSC 204, CSC 206, CSC 304 are not removed one by one: reset your Second Semester registration on Course Registration to clear them\./);
  assert.deepEqual(n.link, { href: "/student/register?session=2025%2F2026&semester=2", label: "Course Registration" });
  // add and drop open: Remove there
  n = siwesNext({ ...paid, otherCourses: ["CSC 304"], clearing: { addDropOpen: true, resetAllowed: false } }, today);
  assert.equal(n.title, "Remove CSC 304 first");
  assert.match(n.words, /Remove CSC 304 from your Second Semester registration on Course Registration while add and drop is open; if you cannot, ask the Academic Office or ICT Support\./);
  assert.equal(n.link?.label, "Course Registration");
  assert.equal(dropOthersWords(["CSC 304"], { addDropOpen: true, resetAllowed: true }),
    "Remove CSC 304 from your Second Semester registration on Course Registration while add and drop is open, or reset the registration there");
  assert.equal(dropOthersWords(["CSC 304"], { addDropOpen: false, resetAllowed: true }),
    "Add and drop is not open, so CSC 304 is not removed one by one: reset your Second Semester registration on Course Registration to clear it");
  // an answer without clearing: the words of before, no link
  n = siwesNext(paid, today);
  assert.deepEqual([n.title, n.link], ["Remove CSC 204, CSC 206, CSC 304 first", null]);
  assert.equal(clearsThemselves(undefined), true);
  assert.equal(clearsThemselves({ addDropOpen: false, resetAllowed: false }), false);
  assert.equal(clearsThemselves({ addDropOpen: false, resetAllowed: true }), true);
  assert.equal(courseRegistrationPage(null).href, "/student/register?semester=2");
});

test("s4-3, s4-6: an office's menu in a SIWES semester offers no Add; the desk's figures are linked for its readers alone", () => {
  assert.equal(SIWES_OFFICE_ADD_WORDS, "Registered on the student's SIWES page once its fee is paid");
  for (const o of ["academic", "registrar", "dregistrar", "super", "hod", "siwes", "dean", "facultyofficer", "bursar", "studentaccounts", "ict", "vc", "dvc"]) {
    assert.equal(SIWES_DESK_READERS.includes(o), true, o);
  }
  assert.equal(SIWES_DESK_READERS.includes("audit"), false);
  assert.equal(SIWES_DESK_READERS.includes("deputyaudit"), false);
});

test("v4-1: an office's table names why a dropped course is not restored in a SIWES semester, in place of Restore", () => {
  assert.equal(siwesDroppedWords("CARRYOVER"), "Waits for a later semester: the SIWES semester holds the SIWES course alone");
  assert.equal(siwesDroppedWords("DEFERRED"), "Waits for a later semester: the SIWES semester holds the SIWES course alone");
  // an ordinary course, or the SIWES course itself (registered on the student's SIWES page), is not put back
  for (const t of ["CURRENT", null, undefined, ""]) {
    assert.equal(siwesDroppedWords(t), "Not restored: the SIWES semester holds the SIWES course alone, registered on the student's SIWES page", String(t));
  }
});

test("v4-2: the SIWES page's tiles never present a session that is not the student's SIWES as theirs", () => {
  const today = "2026-11-13";
  // registered SIWES in 2024/2025; at 400 Level in 2025/2026, where the period is OPEN and the fee published
  const past: MySiwes = { ...OPEN, eligible: false, applies: false, reasons: ["NOT_300_LEVEL"], level: 400,
    history: [{ session: "2024/2025", paid: { reference: "R24", amount: 4000, source: "PORTAL" }, registration: { status: "APPROVED", courseCode: "CSC 399" } }] };
  const n = siwesNext(past, today);
  assert.equal(n.step, "ELSEWHERE");
  const t = siwesTiles(past, n.step);
  assert.deepEqual(t, [
    ["Your SIWES", "2024/2025", "300 Level · Second Semester"],
    ["You", "Not this session", "SIWES is not part of your 2025/2026 registration"],
    ["SIWES fee", "Nothing owed", "for 2025/2026"],
  ]);
  // never this session's fee as unpaid, nor its training dates
  assert.equal(t.some(([, v, sub]) => /Not paid|₦4,000|January 2027/.test(`${v} ${sub}`)), false);
  // not eligible, SIWES not theirs this session, nothing elsewhere: nothing owed, the reason beside them
  const outside: MySiwes = { ...OPEN, eligible: false, applies: false, reasons: ["NOT_CONFIGURED"] };
  const o = siwesTiles(outside, siwesNext(outside, today).step);
  assert.deepEqual(o[1], ["You", "Not eligible", "Your programme is not among those taking SIWES this session."]);
  assert.deepEqual(o[2], ["SIWES fee", "Nothing owed", "SIWES is not yours in 2025/2026"]);
  // a draft period binds nobody: nothing owed while no SIWES registration is open
  const draft: MySiwes = { ...OPEN, eligible: false, applies: false, reasons: ["NO_PERIOD"], period: { ...OPEN.period!, state: "DRAFT" } };
  assert.deepEqual(siwesTiles(draft, siwesNext(draft, today).step)[2], ["SIWES fee", "Nothing owed", "No SIWES registration is open for 2025/2026"]);
  // bound and unpaid: the fee owed, the training of the session
  const bound = siwesTiles(OPEN, siwesNext(OPEN, today).step);
  assert.deepEqual(bound[0], ["SIWES session", "2025/2026", "300 Level · Second Semester"]);
  assert.deepEqual(bound[1], ["You", "Eligible", "Computer Science"]);
  assert.deepEqual(bound[2], ["SIWES fee", "₦4,000", "Not paid"]);
  assert.deepEqual(bound[3], ["Training", "6 months", "4 January 2027 – 30 June 2027 (6 months)"]);
  // bound but not yet able to register (no course set): the fee is still theirs to pay once it can be
  assert.deepEqual(siwesTiles({ ...OPEN, eligible: false, applies: true, reasons: ["NO_COURSE"] }, "NOT_ELIGIBLE")[2], ["SIWES fee", "₦4,000", "Not paid"]);
  // paid: the payment
  const paid = siwesTiles({ ...OPEN, paid: { reference: "R1", amount: 4000, receiptNo: "X", at: "2026-11-12T10:00:00Z", source: "PORTAL" } }, "REGISTER");
  assert.deepEqual(paid[2], ["SIWES fee", "Paid", "₦4,000 · 12 November 2026"]);
});

test("K25: the desk shows each mapped course's catalogue state and warns of one not LIVE", () => {
  assert.deepEqual(courseStateWord({ state: "LIVE" }), ["Live", "ok"]);
  assert.deepEqual(courseStateWord({ state: "BOARD" }), ["Not yet live (Board)", "warn"]);
  assert.deepEqual(courseStateWord({ state: "SENATE" }), ["Not yet live (Senate)", "warn"]);
  assert.deepEqual(courseStateWord({ state: "ENDED" }), ["Ended", "bad"]);
  assert.equal(courseStateWord({ state: null }), null);
  assert.equal(courseStateWord(null), null);
  assert.equal(courseStateWarning({ code: "BCH 300", state: "LIVE" }), null);
  assert.equal(courseStateWarning({ code: "BCH 300" }), null);
  assert.equal(courseStateWarning({ code: "BCH 399", state: "BOARD" }),
    "BCH 399 is not yet live in the catalogue (still before the Board). Check that it is the course the programme's 300 Level students take for SIWES, or set a live course.");
  assert.match(courseStateWarning({ code: "BIO 300", state: "SENATE" }) ?? "", /^BIO 300 is not yet live in the catalogue \(still before Senate\)\./);
  assert.equal(courseStateWarning({ code: "ZZW 308", state: "ENDED" }), "ZZW 308 has ended in the catalogue: no student registers it (SIWES_COURSE_MISSING). Set another course.");
  // the configuration: each programme's course, or each curriculum's where the programme's curricula carry their own
  const course = (code: string, state: string) => ({ code, title: null, units: 6, state });
  const config: Pick<SiwesConfig, "programmes"> = { programmes: [
    { code: "C64548", name: "Biochemistry", course: course("BCH 300", "LIVE"),
      curricula: [{ curriculum: "BMAS", course: course("BCH 300", "LIVE") }, { curriculum: "CCMAS", course: course("BCH 399", "BOARD") }] },
    { code: "C00060", name: "Biology", course: course("BIO 300", "BOARD"), curricula: [] },
    { code: "C00022", name: "Chemistry", course: course("CHM 342", "LIVE") },
    { code: "C00099", name: "Not set", course: null },
  ] };
  assert.deepEqual(configWarnings(config).map((x) => [x.programme, x.curriculum, x.course, x.ended]), [["Biochemistry", "CCMAS", "BCH 399", false], ["Biology", null, "BIO 300", false]]);
  assert.equal(configWarnings({ programmes: [{ code: "M", name: "M", course: course("ZZW 308", "ENDED") }] })[0].ended, true);
  assert.deepEqual(configWarnings(null), []);
});
