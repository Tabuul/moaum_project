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
  NO_COURSE_FOUND, carriedByWords, courseCodeTyped, courseSourceWords, curriculumSourceWords, levelSemesterWords, noCourseAction, noCourseWords, notRecognisedWords,
  programmeAddedWords, programmeCourseLines, programmeNames, semesterWords, setForWords, siwesCourseAddedWords, siwesCourseKnownWords, siwesCourseOffWords, siwesCourseSetHereWords, siwesCoursesHint,
  unreachedLines, unreachedWords, type SiwesCatalogueCourse, type SiwesConfigProgramme, type SiwesCourse,
  NO_COURSE_YET, PROGRAMMES_HINT, RECOGNISED_STANDS, SIWES_COURSE_ADD_HINT, attachmentForWords, courseHint, courseHintWords, newlyRecognised, offeredCourseWords,
  onSiwesCourses, paidHeldWords, recognisedForWords, type SiwesUnreached,
  ON_COURSE_REGISTRATION, SIWES_COURSE_LEVEL_HINT, SIWES_FEE_STANDARD, confirmUseItWords, elsewhereWhere, elsewhereWords, foundInsteadWords, secondSemesterWords, type SiwesElsewhere,
  // V777: every SIWES course carries the fee — the COURSE shape, the lock on Course Registration's menu, the Bursary's list
  SIWES_LOCK_PILL, SIWES_LOCK_TITLE, UNPAID_HEAD, UNPAID_WORDS, courseSemesters, courseWhere, coursesToRegister, heldCourses, isCourseMode, ownCourseLine, ownCourseList, ownCourses,
  reasonsToSay, registerLinks, siwesFeeScopeWords, siwesLockKind, siwesLockNotes, siwesUnpaidRegisteredWords, unpaidEntries, unpaidEntry, unpaidLine, unpaidStanding, unpaidTotals,
  unpaidTotal, unpaidWhere, type SiwesOwnCourse, type SiwesUnpaidEntry,
  // V777, the review of the application layer: a held course by the registration that holds it, the shut payment window, the desk's draft period, the Unpaid tab
  heldAs, heldStanding, heldToSiwesRow, periodHolds, removeProgrammeWords, siwesPayShutWords, submitLinks, unpaidTabShown, type SiwesPeriod,
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

// ── V776: rows as registration.siwes_config answers them (made-up programmes and courses) ──────────────────────────────────────
const k = (code: string, title: string, state = "LIVE") => ({ id: `id-${code}`, code, title, state, units: 6 });
const ZZK399 = k("ZZK 399", "Industrial Training (check)");
const ZZK398 = k("ZZK 398", "Students Industrial Work Experience Scheme", "BOARD");
const ZZK397 = k("ZZK 397", "SIWES II (check)");
// recognised in the programme's own structure; nothing found; the department's one course; set here for one curriculum, read for the other
const STRUCTURE: SiwesConfigProgramme = { code: "C97761", name: "B.Sc. Check Structure", eligible: 1, course: ZZK399, source: "STRUCTURE",
  curricula: [{ curriculum: "CCMAS", mapped: false, course: ZZK399, source: "STRUCTURE" }] };
const NONE: SiwesConfigProgramme = { code: "C97762", name: "B.Sc. Check None", eligible: 0, course: null, source: null,
  curricula: [{ curriculum: "CCMAS", mapped: false, course: null, source: null }] };
const DEPARTMENT: SiwesConfigProgramme = { code: "C97763", name: "B.Sc. Check Department", eligible: 1, course: ZZK398, source: "DEPARTMENT", curricula: [] };
const SET: SiwesConfigProgramme = { code: "C97764", name: "B.Sc. Check Two", eligible: 1, course: ZZK397, source: "SET",
  curricula: [{ curriculum: "BMAS", mapped: true, course: ZZK397, source: "SET" }, { curriculum: "CCMAS", mapped: false, course: ZZK397, source: "SET" }] };

test("V776: a programme's row says how its SIWES course is known — set here, or recognised — for each curriculum, and where none is found", () => {
  assert.equal(courseSourceWords("SET"), "Set here");
  assert.equal(courseSourceWords("STRUCTURE"), "Written down from the programme's own structure");
  assert.equal(courseSourceWords("DEPARTMENT"), "Written down: its department's one SIWES course");
  // an older answer carries none, and a source not known here is never shown as its code
  for (const s of [null, undefined, "", "SOMETHING_NEW"]) assert.equal(courseSourceWords(s), "", String(s));
  assert.deepEqual(programmeCourseLines(STRUCTURE), [{ curriculum: "CCMAS", course: ZZK399, known: "Written down from the programme's own structure" }]);
  // no curriculum of its own on the row: the programme's course
  assert.deepEqual(programmeCourseLines(DEPARTMENT), [{ curriculum: null, course: ZZK398, known: "Written down: its department's one SIWES course" }]);
  // none found: the line says nothing of how, and the row says what is done about it
  assert.deepEqual(programmeCourseLines(NONE), [{ curriculum: "CCMAS", course: null, known: "" }]);
  assert.equal(NO_COURSE_FOUND, "No SIWES course found");
  assert.equal(noCourseWords(true), "No SIWES course found — set it, or add the course to the SIWES courses below");
  assert.equal(noCourseWords(false), "No SIWES course found — the Academic Office sets it, or adds the course to the SIWES courses");
  assert.equal(noCourseAction(true), "set it, or add the course to the SIWES courses below");
  // set here for BMAS; CCMAS reads the same course while every curriculum's courses are open (mapped false beside SET)
  assert.deepEqual(programmeCourseLines(SET).map((l) => [l.curriculum, l.course?.code, l.known]),
    [["BMAS", "ZZK 397", "Set here"], ["CCMAS", "ZZK 397", "Set here for BMAS, read for CCMAS too"]]);
  // set for every curriculum (the null row carries the mapping): each curriculum says so, and the null row is not a line of its own
  const every: SiwesConfigProgramme = { ...SET, curricula: [{ curriculum: null, mapped: true, course: ZZK397, source: "SET" }, { curriculum: "CCMAS", mapped: false, course: ZZK397, source: "SET" }] };
  assert.deepEqual(programmeCourseLines(every).map((l) => [l.curriculum, l.known]), [["CCMAS", "Set here for every curriculum"]]);
  assert.equal(curriculumSourceWords({ curricula: [] }, { curriculum: "CCMAS", mapped: false, course: ZZK397, source: "SET" }), "Set here");
  // one curriculum set, the other recognised, a third with nothing
  const mixed: SiwesConfigProgramme = { ...SET, curricula: [{ curriculum: "BMAS", mapped: true, course: ZZK397, source: "SET" },
    { curriculum: "CCMAS", mapped: false, course: ZZK399, source: "STRUCTURE" }] };
  assert.deepEqual(programmeCourseLines(mixed).map((l) => l.known), ["Set here", "Written down from the programme's own structure"]);
  // the catalogue's warning reads the same lines: a recognised course not yet live is warned of like a set one
  assert.deepEqual(configWarnings({ programmes: [STRUCTURE, NONE, DEPARTMENT, SET] }).map((w) => [w.programme, w.curriculum, w.course]), [["B.Sc. Check Department", null, "ZZK 398"]]);
});

test("V776: an older answer without the new keys reads as before — no source, no SIWES courses, nobody unreached", () => {
  const old: SiwesConfig = { session: "2025/2026", period: null, candidates: [], fee: null, sessions: [],
    programmes: [{ code: "C00022", name: "Chemistry", course: { code: "CHM 342", title: null, units: 6, state: "LIVE" }, curricula: [{ curriculum: "CCMAS", course: { code: "CHM 399", title: null, units: 6 } }] },
      { code: "C00099", name: "Not set", course: null }] };
  assert.deepEqual(programmeCourseLines(old.programmes[0]), [{ curriculum: "CCMAS", course: { code: "CHM 399", title: null, units: 6 }, known: "" }]);
  assert.deepEqual(programmeCourseLines(old.programmes[1]), [{ curriculum: null, course: null, known: "" }]);
  const nobody = { lines: [], students: 0, paid: 0, title: "", words: "" };
  assert.deepEqual(unreachedLines(old), nobody);
  assert.deepEqual(unreachedLines(null), nobody);
  assert.deepEqual(programmeNames(old), { C00022: "Chemistry", C00099: "Not set" });
  assert.deepEqual(programmeNames(null), {});
  // a course of an older list: on the SIWES courses (the list held no other), with nobody it was recognised for and no attachment semester
  const bare: SiwesCatalogueCourse = { code: "ZZK 300" };
  assert.deepEqual([levelSemesterWords(bare), siwesCourseKnownWords(bare), notRecognisedWords(bare), carriedByWords(bare), setForWords(bare)], ["—", "Added here", null, "", ""]);
  assert.deepEqual([onSiwesCourses(bare), recognisedForWords(bare), attachmentForWords(bare)], [true, "", ""]);
  // a row with no course and none of the newer keys: nothing found, as before
  assert.deepEqual(courseHint(programmeCourseLines(old.programmes[1])[0], true), { kind: "NONE", found: null, words: "No SIWES course found", action: "set it, or add the course to the SIWES courses below" });
});

// V777: what the cohorts no SIWES course reaches wait for — to be held to the SIWES course alone; the fee is every SIWES course's all the same
const UNREACHED_WAITS = "not held to the SIWES course alone until a SIWES course reaches them; a SIWES course their programme carries still asks them the SIWES fee when they register it, on Course Registration";
// V777: what a programme just added with no course set says of its 300 Level students
const ADDED_WAITS = "Its 300 Level students are not held to the SIWES course alone until one is set; they pay the SIWES fee when they register a SIWES course, on Course Registration.";

test("V776: the cohorts no SIWES course reaches are named with their numbers: not held to the SIWES course alone until one does", () => {
  // registration.siwes_config's unreached[], as an answer without the newer keys carries it: of each, no course is found
  const none = "No SIWES course found — set it, or add the course to the SIWES courses below";
  const u = unreachedLines({ unreached: [
    { programmeCode: "C97762", programme: "B.Sc. Check None", curriculum: "CCMAS", students: 2 },
    { programmeCode: "C97764", programme: "B.Sc. Check Two", curriculum: null, students: 1 },
    { programmeCode: "C97765", programme: null, curriculum: "BMAS", students: 1200 },
    { programmeCode: "C97766", programme: "Nobody waiting", curriculum: null, students: 0 },
  ] }, true);
  assert.equal(u.title, "No SIWES course reaches 1,203 students at 300 Level yet");
  assert.deepEqual([u.students, u.paid], [1203, 0]);
  assert.deepEqual(u.lines, [
    { key: "C97762|CCMAS", name: "B.Sc. Check None (CCMAS)", words: "2 students at 300 Level", course: none },
    { key: "C97764|", name: "B.Sc. Check Two", words: "1 student at 300 Level", course: none },
    { key: "C97765|BMAS", name: "C97765 (BMAS)", words: "1,200 students at 300 Level", course: none },
  ]);
  assert.equal(unreachedLines({ unreached: [{ programmeCode: "C97764", programme: "B.Sc. Check Two", students: 1 }] }).title, "No SIWES course reaches 1 student at 300 Level yet");
  assert.equal(u.words, `They are ${UNREACHED_WAITS}.`);
  assert.equal(unreachedWords(), u.words);
  // V777: never "not asked to pay": a SIWES course their programme carries asks them the fee, on Course Registration
  assert.doesNotMatch(u.words, /not asked/);
  // a reader is offered nothing to press: each line says the Academic Office does it
  assert.equal(unreachedLines({ unreached: [{ programmeCode: "C97764", students: 1 }] }).lines[0].course, "No SIWES course found — the Academic Office sets it, or adds the course to the SIWES courses");
  assert.equal(unreachedLines({ unreached: [] }).lines.length, 0);
});

test("V776: a programme added with no SIWES course found is said so, a warning; with one, the course is named", () => {
  // POST /programmes answers the session's configuration
  const config = { programmes: [STRUCTURE, NONE, DEPARTMENT, SET] };
  assert.deepEqual(programmeAddedWords(config, "C97762", "2025/2026"), { tone: "warn",
    words: `B.Sc. Check None takes SIWES in 2025/2026, but no SIWES course is found for it (CCMAS) yet: set it, or add the course to the SIWES courses. ${ADDED_WAITS}` });
  // no curriculum of its own: the programme whole
  assert.match(programmeAddedWords({ programmes: [{ ...NONE, curricula: [] }] }, "C97762", "2025/2026").words, /no SIWES course is found for it yet: set it/);
  // one curriculum found, the other not: still a warning, naming the one
  const half: SiwesConfigProgramme = { ...SET, curricula: [SET.curricula![0], { curriculum: "CCMAS", mapped: false, course: null, source: null }] };
  assert.deepEqual([programmeAddedWords({ programmes: [half] }, "C97764", "2025/2026").tone, /\(CCMAS\) yet/.test(programmeAddedWords({ programmes: [half] }, "C97764", "2025/2026").words)], ["warn", true]);
  // a course found: the success names it; two courses, each with its curriculum
  assert.deepEqual(programmeAddedWords(config, "C97761", "2025/2026"), { tone: "ok", words: "B.Sc. Check Structure takes SIWES in 2025/2026: its SIWES course is ZZK 399" });
  assert.deepEqual(programmeAddedWords(config, "C97764", "2025/2026"), { tone: "ok", words: "B.Sc. Check Two takes SIWES in 2025/2026: its SIWES course is ZZK 397" });
  const two: SiwesConfigProgramme = { ...SET, curricula: [SET.curricula![0], { curriculum: "CCMAS", mapped: false, course: ZZK399, source: "STRUCTURE" }] };
  assert.equal(programmeAddedWords({ programmes: [two] }, "C97764", "2025/2026").words, "B.Sc. Check Two takes SIWES in 2025/2026: its SIWES courses are ZZK 397 (BMAS), ZZK 399 (CCMAS)");
  // an answer that does not list the programme (or carries none): added, nothing more claimed
  for (const c of [config, { programmes: null }, {}, null, undefined]) assert.deepEqual(programmeAddedWords(c, "C00023", "2025/2026"), { tone: "ok", words: "C00023 takes SIWES in 2025/2026" });
});

test("V776: the SIWES courses: where each stands in the catalogue, how it is known, who carries it and who it is set for", () => {
  // registration.siwes_course_list's rows
  const base = { units: 6, state: "LIVE", curriculum: null, departmentCode: "ZD7762", department: "Check Department Two" };
  const byTitle: SiwesCatalogueCourse = { ...base, id: "a", code: "ZZK 397", title: "SIWES II (check)", level: 300, semester: "SECOND", byTitle: true, recognised: true,
    programmes: [], setFor: [{ code: "C97764", curriculum: "BMAS" }, { code: "C97769", curriculum: null }] };
  const added: SiwesCatalogueCourse = { ...base, id: "b", code: "ZZK 301", title: "Check field course", level: 300, semester: "SECOND", byTitle: false, recognised: true,
    programmes: [{ code: "C97762", name: "B.Sc. Check None", level: 300 }], setFor: [] };
  const fourth: SiwesCatalogueCourse = { ...base, id: "c", code: "ZZK 499", title: "Industrial Work Experience IV (check)", level: 400, semester: "FIRST", byTitle: true, recognised: false,
    programmes: [{ code: "C97762", name: "B.Sc. Check None", level: 400 }], setFor: [] };
  assert.equal(siwesCourseKnownWords(byTitle), "By its title");
  assert.equal(siwesCourseKnownWords(added), "Added here");
  assert.equal(levelSemesterWords(byTitle), "300 Level · Second Semester");
  assert.equal(levelSemesterWords({ level: 300, semester: "BOTH", curriculum: "CCMAS" }), "300 Level · Both semesters · CCMAS");
  assert.deepEqual(["FIRST", "SECOND", "BOTH", "3", "9", null].map(semesterWords), ["First Semester", "Second Semester", "Both semesters", "Third Semester", "Semester 9", ""]);
  // the programmes whose structure carries it, by name; one that carries it at another level says so; many are counted
  assert.equal(carriedByWords(added), "B.Sc. Check None");
  assert.equal(carriedByWords(fourth), "B.Sc. Check None (at 400 Level)");
  assert.equal(carriedByWords(byTitle), "");
  const many = { programmes: Array.from({ length: 9 }, (_, i) => ({ code: `P${i}`, name: `Programme ${i}`, level: 300 })) };
  assert.equal(carriedByWords(many, 2), "Programme 0; Programme 1; and 7 more");
  assert.equal(carriedByWords(many, Infinity).split("; ").length, 9);
  // set for: the programme's name where the configuration knows it, its code otherwise; the curriculum when it is for one alone
  const names = programmeNames({ programmes: [SET], candidates: [{ code: "C97768", name: "B.Sc. Candidate" }], siwesCourses: [added] });
  assert.deepEqual(names, { C97762: "B.Sc. Check None", C97768: "B.Sc. Candidate", C97764: "B.Sc. Check Two" });
  assert.equal(setForWords(byTitle, names), "B.Sc. Check Two (BMAS); C97769");
  assert.equal(setForWords(added, names), "");
});

test("V776: a SIWES course no programme comes by on its own says why, from its own fields", () => {
  const c = (o: Partial<SiwesCatalogueCourse>): SiwesCatalogueCourse => ({ code: "ZZK 499", title: "Industrial Training", level: 300, semester: "SECOND", state: "LIVE", recognised: false, ...o });
  // V777: no programme comes by it on its own, and it carries the SIWES fee all the same — said, so that the one is never read as the other
  const charged = " Students who register it pay the SIWES fee all the same.";
  // a Second Semester course in force at another level: still a programme's course where it is set for it (registration.siwes_set_course)
  assert.equal(notRecognisedWords(c({ level: 400 })),
    `No programme comes by it on its own: it is a 400 Level course, not 300 Level. It is a programme's SIWES course only where it is set for the programme.${charged}`);
  // First Semester: never a programme's SIWES course (the SIWES course is a Second Semester course), so no such tail
  assert.equal(notRecognisedWords(c({ semester: "FIRST" })), `No programme comes by it on its own: it is taught in the First Semester, not the Second.${charged}`);
  assert.equal(notRecognisedWords(c({ level: 400, semester: "FIRST" })),
    `No programme comes by it on its own: it is a 400 Level course, not 300 Level; it is taught in the First Semester, not the Second.${charged}`);
  assert.equal(notRecognisedWords(c({ semester: "3" })), `No programme comes by it on its own: it is taught in the Third Semester, not the Second.${charged}`);
  // an ended course carries no fee: nothing is said of it
  assert.equal(notRecognisedWords(c({ state: "ENDED" })), "No programme comes by it on its own: it has ended in the catalogue.");
  assert.equal(notRecognisedWords(c({ state: "ENDED", level: 200 })), "No programme comes by it on its own: it has ended in the catalogue; it is a 200 Level course, not 300 Level.");
  // the server's word alone decides: a course it recognises, or an answer that does not say, carries no reason — whatever its fields
  assert.equal(notRecognisedWords(c({ recognised: true, level: 400 })), null);
  assert.equal(notRecognisedWords(c({ recognised: undefined, level: 400 })), null);
  assert.equal(notRecognisedWords(c({ recognised: null, semester: "FIRST" })), null);
  // not recognised with nothing in its fields to say why: said plainly, no reason made up
  assert.equal(notRecognisedWords(c({})), `No programme comes by it on its own: it is not a 300 Level, Second Semester course in force.${charged}`);
  assert.equal(notRecognisedWords(c({ semester: "BOTH", level: undefined })), `No programme comes by it on its own: it is not a 300 Level, Second Semester course in force.${charged}`);
  // no code of the database's is shown
  for (const o of [{ level: 400 }, { semester: "FIRST" }, { state: "ENDED" }, {}]) assert.doesNotMatch(notRecognisedWords(c(o)) ?? "", /FIRST|SECOND|ENDED|recognised/);
});

test("V776: a course added to the SIWES courses, or taken off them: what the desk says and asks", () => {
  assert.equal(courseCodeTyped("  zzk   301 "), "ZZK 301");
  assert.equal(courseCodeTyped(null), "");
  // PUT /siwes-courses answers the list: the course as the catalogue holds it
  const list: SiwesCatalogueCourse[] = [
    { code: "ZZK 301", title: "Check field course", level: 300, semester: "SECOND", state: "LIVE", byTitle: false, recognised: true, programmes: [], setFor: [] },
    { code: "ZZK 499", title: "Field attachment", level: 400, semester: "SECOND", state: "LIVE", byTitle: false, recognised: false, programmes: [], setFor: [] },
  ];
  // V777: marking a course starts charging it, and the notice says so
  assert.deepEqual(siwesCourseAddedWords(list, "zzk  301"), { tone: "ok", words: "ZZK 301 is now a SIWES course, and carries the SIWES registration fee" });
  assert.deepEqual(siwesCourseAddedWords(list, "ZZK 499"), { tone: "warn",
    words: "ZZK 499 is now a SIWES course. No programme comes by it on its own: it is a 400 Level course, not 300 Level. It is a programme's SIWES course only where it is set for the programme. Students who register it pay the SIWES fee all the same." });
  // an answer without the list, or one that holds the course under another code: added, nothing more claimed
  for (const l of [null, undefined, [], [list[1]]]) assert.deepEqual(siwesCourseAddedWords(l, "ZZK 301"), { tone: "ok", words: "ZZK 301 is now a SIWES course, and carries the SIWES registration fee" });
  // "Not a SIWES course" says what it does before it is done, and what the database refuses
  const off = siwesCourseOffWords({ code: "ZZK 396", title: "Industrial Attachment (check)" });
  assert.match(off, /^Take ZZK 396 — Industrial Attachment \(check\) off the SIWES courses\?/);
  assert.match(off, /no programme comes by it as its SIWES course/);
  // V777: taking it off stops charging it
  assert.match(off, /it stops charging the SIWES registration fee, and no programme comes by it as its SIWES course\./);
  assert.match(off, /It stays off while its title stands, until it is added here again\./);
  assert.match(off, /refused while the course is set here as a programme's SIWES course, while a student holds it, in a session still to come or running, on a registration that stands on the SIWES fee, while students who have paid or registered for SIWES are reached by it, or while students are registered in an attachment semester it makes\.$/);
  assert.match(siwesCourseOffWords({ code: "ZZK 396", title: null }), /^Take ZZK 396 off the SIWES courses\?/);
  assert.doesNotMatch(off, /SIWES_COURSE_IN_USE|industrial_training/);
  // a course nobody was recognised by and no attachment semester rests on: neither is spoken of
  assert.doesNotMatch(off, /written down for|attachment semester —/);
});

test("V776, V777: the sentence under the SIWES courses says which listed courses carry the fee (those not ended), naming it only once the Bursary has published it", () => {
  assert.equal(siwesCoursesHint({ amount: "4000.00", state: "PUBLISHED" }),
    "Each department carries SIWES under its own course code and title; a course whose title reads SIWES or Industrial Training is listed as it is added to the catalogue. "
    + "Every course listed here that has not ended carries the ₦4,000 SIWES registration fee: a student pays it once a session, before registering any of them, whatever the programme, level or semester. "
    + "A course listed only because it is set as a programme's SIWES course is charged to the students that programme holds to SIWES alone, and an ended course is not charged while it stays ended. "
    + "Adding a course here starts charging it; taking one off stops.");
  // a draft, or no fee stated: the fee is paid first all the same, its amount not yet the Bursary's word
  for (const fee of [{ amount: 5000, state: "DRAFT" }, { amount: null, state: "PUBLISHED" }, null, undefined]) {
    assert.match(siwesCoursesHint(fee), /Every course listed here that has not ended carries the SIWES registration fee: a student pays it once a session, before registering any of them, whatever the programme, level or semester\./);
    assert.doesNotMatch(siwesCoursesHint(fee), /₦/);
    // never the blanket "every course listed" (an ended course, or one set for a programme and not added, is not charged outside its cohort)
    assert.doesNotMatch(siwesCoursesHint(fee), /Every course listed here carries/);
  }
  // V777: no sentence says the First Semester or another level is "not covered yet"
  for (const fee of [{ amount: "4000.00", state: "PUBLISHED" }, null]) assert.doesNotMatch(siwesCoursesHint(fee), /not covered|Second Semester of 300 Level/);
});

// ── V776, the recognition written down: the answers of registration.siwes_config and siwes_mark_course on a scratch database with the
//    migration applied (made-up programmes and courses), as the API sends them — a key with nothing in it is left out ──────────────────
const q = (code: string, title: string, units = 6, state = "LIVE") => ({ id: `id-${code}`, code, state, title, units });
const ZZQ399 = q("ZZQ 399", "Industrial Training (made up)");
const ZZQ397 = q("ZZQ 397", "SIWES (made up found)");
const ZZQ396 = q("ZZQ 396", "Industrial Attachment A (made up)");
const ZZQ395 = q("ZZQ 395", "Industrial Attachment B (made up)");
const ZZQ393 = q("ZZQ 393", "SIWES (made up head)");
const ZZQ392 = q("ZZQ 392", "SIWES report (made up)", 1);
const ZZQ391 = q("ZZQ 391", "Industrial Training BMAS (made up)");
const ZZQ390 = q("ZZQ 390", "Industrial Training CCMAS (made up)", 6, "BOARD");
const ZZQ302 = q("ZZQ 302", "Made-up elective", 3);
const unit = { faculty: "Education", facultyCode: "ED" };
// recognised in its structure as it was added: one row written down for every curriculum (sent without the key), read for CCMAS
const R_STRUCTURE: SiwesConfigProgramme = { ...unit, code: "C98761", name: "B.Sc. Made-up Structure", course: ZZQ399, source: "STRUCTURE", eligible: 2,
  curricula: [{ course: ZZQ399, mapped: true, source: "STRUCTURE" }, { course: ZZQ399, mapped: false, source: "STRUCTURE", curriculum: "CCMAS" }] };
// its structure came to carry a SIWES course after it was added: found, the one choice
const R_FOUND: SiwesConfigProgramme = { ...unit, code: "C98763", name: "B.Sc. Made-up Found", found: ZZQ397, choices: [ZZQ397], eligible: 0,
  curricula: [{ found: ZZQ397, mapped: false, choices: [ZZQ397], curriculum: "CCMAS" }] };
// a 6-unit course and a 1-unit report: the one at the head is found, both are choices
const R_HEAD: SiwesConfigProgramme = { ...unit, code: "C98768", name: "B.Sc. Made-up Head of several", found: ZZQ393, choices: [ZZQ392, ZZQ393], eligible: 0,
  curricula: [{ found: ZZQ393, mapped: false, choices: [ZZQ392, ZZQ393], curriculum: "CCMAS" }] };
const R_NONE: SiwesConfigProgramme = { ...unit, code: "C98762", name: "B.Sc. Made-up None", eligible: 0, curricula: [{ mapped: false, curriculum: "CCMAS" }] };
// two of equal standing: none found, never a guess
const R_SEVERAL: SiwesConfigProgramme = { ...unit, code: "C98764", name: "B.Sc. Made-up Several", choices: [ZZQ395, ZZQ396], eligible: 0,
  curricula: [{ mapped: false, choices: [ZZQ395, ZZQ396], curriculum: "CCMAS" }] };
// the programme whole reads the live BMAS course, its CCMAS students their own curriculum's (still before the Board)
const R_CURRICULA: SiwesConfigProgramme = { ...unit, code: "C98769", name: "B.Sc. Made-up Two curricula", found: ZZQ391, choices: [ZZQ390, ZZQ391], eligible: 0,
  curricula: [{ found: ZZQ390, mapped: false, choices: [ZZQ390, ZZQ391], curriculum: "CCMAS" }] };

test("V776: a row with no SIWES course says what the catalogue offers now — one found to use, several to choose from, or nothing", () => {
  // the row's line carries the offer of its own curriculum; a line with a course carries none
  assert.deepEqual(programmeCourseLines(R_FOUND), [{ curriculum: "CCMAS", course: null, known: "", found: ZZQ397, choices: [ZZQ397] }]);
  assert.deepEqual(programmeCourseLines(R_NONE), [{ curriculum: "CCMAS", course: null, known: "" }]);
  assert.deepEqual(programmeCourseLines(R_STRUCTURE), [{ curriculum: "CCMAS", course: ZZQ399, known: "Written down from the programme's own structure" }]);
  // beside a course written down from the catalogue, the course the catalogue would now give is carried (found, never the choices);
  // beside a course set on the desk, never
  assert.deepEqual(programmeCourseLines({ ...R_STRUCTURE, found: ZZQ397, choices: [ZZQ397], curricula: [] }),
    [{ curriculum: null, course: ZZQ399, known: "Written down from the programme's own structure", found: ZZQ397 }]);
  assert.deepEqual(programmeCourseLines({ ...R_STRUCTURE, source: "SET", found: ZZQ397, curricula: [] }), [{ curriculum: null, course: ZZQ399, known: "Set here" }]);
  // the same course found as the one written down is no offer
  assert.deepEqual(programmeCourseLines({ ...R_STRUCTURE, found: ZZQ399, curricula: [] }), [{ curriculum: null, course: ZZQ399, known: "Written down from the programme's own structure" }]);
  // no curriculum of its own on the row: the programme's own offer
  assert.deepEqual(programmeCourseLines({ ...R_FOUND, curricula: [] }), [{ curriculum: null, course: null, known: "", found: ZZQ397, choices: [ZZQ397] }]);
  assert.equal(programmeCourseLines(R_CURRICULA)[0].found, ZZQ390);
  // found: the course by its code, title and units; the offices that set press "Use it" on the row, and the note and a reader are told who sets it
  const found = courseHint(programmeCourseLines(R_FOUND)[0], true);
  assert.deepEqual(found, { kind: "FOUND", found: ZZQ397, words: "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units)", action: "set it as the programme's course above" });
  assert.equal(courseHint(programmeCourseLines(R_FOUND)[0], false).action, "the Academic Office sets it");
  assert.equal(courseHintWords(found), "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — set it as the programme's course above");
  // the head of several is the one found: the 6-unit course, never the 1-unit report beside it
  assert.equal(courseHint(programmeCourseLines(R_HEAD)[0], true).words, "Found in the catalogue: ZZQ 393 SIWES (made up head) (6 units)");
  assert.equal(offeredCourseWords(ZZQ392), "ZZQ 392 SIWES report (made up) (1 unit)");
  assert.equal(offeredCourseWords({ code: "ZZQ 300", title: null, units: null }), "ZZQ 300");
  // several of equal standing: listed, and the one the students register is set — by the Academic Office, a reader is told
  const several = courseHint(programmeCourseLines(R_SEVERAL)[0], true);
  assert.deepEqual(several, { kind: "CHOICES", found: null,
    words: "Several SIWES courses found: ZZQ 395 Industrial Attachment B (made up) (6 units); ZZQ 396 Industrial Attachment A (made up) (6 units)",
    action: "set the one the programme's students register" });
  assert.equal(courseHint(programmeCourseLines(R_SEVERAL)[0], false).action, "the Academic Office sets the one the programme's students register");
  // one choice and nothing found (not an answer the database gives): said as it is, never taken as found
  assert.deepEqual(courseHint({ choices: [ZZQ397] }, true), { kind: "CHOICES", found: null, words: "A SIWES course found: ZZQ 397 SIWES (made up found) (6 units)",
    action: "set it, if it is the one the programme's students register" });
  // nothing: as before
  for (const o of [programmeCourseLines(R_NONE)[0], {}, { found: null, choices: [] }, null, undefined]) {
    assert.deepEqual(courseHint(o, true), { kind: "NONE", found: null, words: NO_COURSE_FOUND, action: noCourseAction(true) });
  }
  assert.equal(courseHintWords(courseHint(null, false)), noCourseWords(false));
  assert.equal(NO_COURSE_YET, "No SIWES course yet");
});

test("V776: a course written down stands — the desk says it, never that it is read afresh, and never that saving the period or adding a programme takes every course", () => {
  assert.equal(RECOGNISED_STANDS, "A course written down stands until the Academic Office sets another; the catalogue changing later does not move it.");
  assert.ok(PROGRAMMES_HINT.includes(RECOGNISED_STANDS));
  // V777: first, that the fee is every SIWES course's whether or not its programme is listed; then what listing a programme does
  assert.match(PROGRAMMES_HINT, /^Every SIWES course carries the SIWES registration fee, whether or not its programme is listed here: a student who registers one pays it first, once a session, and registers the course on Course Registration\. /);
  assert.match(PROGRAMMES_HINT, /A programme listed here is also held to SIWES alone in its 300 Level Second Semester, registered on the SIWES page once the period is open; a programme not listed keeps its Second Semester as before\. A programme's SIWES course is the one set here\. /);
  assert.doesNotMatch(PROGRAMMES_HINT, /not asked|not covered/);
  // written down when the programme is added, only where its Second Semester is the SIWES semester, or when a course is added to the SIWES courses; otherwise the officer takes what is found
  assert.match(PROGRAMMES_HINT, /is written down as its course when the programme is added — only where its Second Semester is the SIWES semester, the SIWES course alone — /);
  assert.match(PROGRAMMES_HINT, /or when a course is added to the SIWES courses that gives a waiting programme its own structure's course; otherwise the row says what the catalogue offers and the Academic Office takes the course\. /);
  assert.doesNotMatch(PROGRAMMES_HINT, /the period saved|recognis/);
  assert.match(SIWES_COURSE_ADD_HINT, /a programme still waiting for a SIWES course whose own 300 Level structure carries it, and whose Second Semester is the SIWES semester, is given it as its course; /);
  assert.match(SIWES_COURSE_ADD_HINT, /every other programme is left as it is, its row saying what is found\. A course already set or written down for a programme is not moved\.$/);
  assert.doesNotMatch(SIWES_COURSE_ADD_HINT, /recognis/);
  // how each is known stays as it was
  assert.deepEqual(["STRUCTURE", "DEPARTMENT"].map(courseSourceWords), ["Written down from the programme's own structure", "Written down: its department's one SIWES course"]);
});

test("V776: of a cohort no SIWES course reaches, those who have paid or registered stay held to SIWES — never said to be left out of the fee", () => {
  // registration.siwes_config's unreached[] once the course a programme was recognised by had ended with one of its two students paid
  const rows: SiwesUnreached[] = [
    { paid: 0, found: ZZQ397, choices: [ZZQ397], students: 1, programme: "B.Sc. Made-up Found", curriculum: "CCMAS", programmeCode: "C98763" },
    { paid: 0, students: 1, programme: "B.Sc. Made-up None", curriculum: "CCMAS", programmeCode: "C98762" },
    { paid: 0, choices: [ZZQ395, ZZQ396], students: 1, programme: "B.Sc. Made-up Several", curriculum: "CCMAS", programmeCode: "C98764" },
    { paid: 1, students: 2, programme: "B.Sc. Made-up Structure", curriculum: "CCMAS", programmeCode: "C98761" },
  ];
  const u = unreachedLines({ unreached: rows }, true);
  assert.deepEqual([u.title, u.students, u.paid], ["No SIWES course reaches 5 students at 300 Level yet", 5, 1]);
  assert.deepEqual(u.lines, [
    { key: "C98763|CCMAS", name: "B.Sc. Made-up Found (CCMAS)", words: "1 student at 300 Level",
      course: "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — set it as the programme's course above" },
    { key: "C98762|CCMAS", name: "B.Sc. Made-up None (CCMAS)", words: "1 student at 300 Level", course: "No SIWES course found — set it, or add the course to the SIWES courses below" },
    { key: "C98764|CCMAS", name: "B.Sc. Made-up Several (CCMAS)", words: "1 student at 300 Level",
      course: "Several SIWES courses found: ZZQ 395 Industrial Attachment B (made up) (6 units); ZZQ 396 Industrial Attachment A (made up) (6 units) — set the one the programme's students register" },
    { key: "C98761|CCMAS", name: "B.Sc. Made-up Structure (CCMAS)",
      words: "2 students at 300 Level; 1 of them has paid or registered — held to SIWES, and cannot register until the course is set",
      course: "No SIWES course found — set it, or add the course to the SIWES courses below" },
  ]);
  // what holds them, with some paid: the paid apart from the others
  assert.equal(u.words, `Those who have paid or registered stay held to SIWES, and cannot register until the course is set; the others are ${UNREACHED_WAITS}.`);
  assert.doesNotMatch(u.lines[3].words, /not asked to pay/);
  // a reader: the Academic Office sets it
  assert.deepEqual(unreachedLines({ unreached: rows }).lines.map((l) => l.course.split(" — ")[1]), ["the Academic Office sets it",
    "the Academic Office sets it, or adds the course to the SIWES courses", "the Academic Office sets the one the programme's students register",
    "the Academic Office sets it, or adds the course to the SIWES courses"]);
  // once a course is added to the SIWES courses, the catalogue offers the ended programme's cohort one: found beside the paid student
  const after = unreachedLines({ unreached: [{ ...rows[3], found: ZZQ302, choices: [ZZQ302] }] }, true);
  assert.equal(after.lines[0].course, "Found in the catalogue: ZZQ 302 Made-up elective (3 units) — set it as the programme's course above");
  // how many: some, one of one, all, and never more than the cohort; none, or an answer that does not say: nothing
  const held = "held to SIWES, and cannot register until the course is set";
  assert.equal(paidHeldWords(2, 37), `2 of them have paid or registered — ${held}`);
  assert.equal(paidHeldWords(1, 1), `the student has paid or registered — ${held}`);
  assert.equal(paidHeldWords(3, 3), `all of them have paid or registered — ${held}`);
  assert.equal(paidHeldWords(5, 2), `all of them have paid or registered — ${held}`);
  for (const [p, s] of [[0, 2], [null, 2], [undefined, 2], [1, 0]] as const) assert.equal(paidHeldWords(p, s), "", `${p} of ${s}`);
  // every student of the cohorts paid: nobody is "not asked to pay"
  const all = unreachedLines({ unreached: [{ paid: 2, students: 2, programmeCode: "C98761" }] });
  assert.deepEqual([all.paid, all.words], [2, "They have paid or registered: they stay held to SIWES, and cannot register until the course is set."]);
  assert.equal(unreachedWords(2, 2), all.words);
  assert.equal(unreachedWords(0, 5), `They are ${UNREACHED_WAITS}.`);
});

test("V776: a programme added with its SIWES course not yet written down says what the catalogue offers it", () => {
  // POST /programmes answers the session's configuration
  const config = { programmes: [R_STRUCTURE, R_FOUND, R_NONE, R_SEVERAL] };
  assert.deepEqual(programmeAddedWords(config, "C98764", "2025/2026"), { tone: "warn",
    words: "B.Sc. Made-up Several takes SIWES in 2025/2026, but its SIWES course (CCMAS) is not set yet. "
      + "Several SIWES courses found: ZZQ 395 Industrial Attachment B (made up) (6 units); ZZQ 396 Industrial Attachment A (made up) (6 units) — set the one the programme's students register. "
      + ADDED_WAITS });
  assert.deepEqual(programmeAddedWords(config, "C98763", "2025/2026"), { tone: "warn",
    words: "B.Sc. Made-up Found takes SIWES in 2025/2026, but its SIWES course (CCMAS) is not set yet. "
      + "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — use it on the programme's row, or set another. "
      + ADDED_WAITS });
  // nothing offered, and a course recognised as it was added: as before
  assert.match(programmeAddedWords(config, "C98762", "2025/2026").words, /, but no SIWES course is found for it \(CCMAS\) yet: set it, or add the course to the SIWES courses\. /);
  assert.deepEqual(programmeAddedWords(config, "C98761", "2025/2026"), { tone: "ok", words: "B.Sc. Made-up Structure takes SIWES in 2025/2026: its SIWES course is ZZQ 399" });
});

// registration.siwes_course_list's rows, as the configuration and PUT /siwes-courses carry them
const row = (c: { code: string; title: string; units: number; state: string }, o: Partial<SiwesCatalogueCourse>): SiwesCatalogueCourse => ({
  id: `id-${c.code}`, code: c.code, level: 300, state: c.state, title: c.title, units: c.units, marked: true, setFor: [], byTitle: true, semester: "SECOND",
  programmes: [], recognised: true, attachmentFor: [], ...o });
// recognised for the programme whose structure carries it, whose attachment semester rests on it
const L_STRUCTURE = row(ZZQ399, { department: "Made-up Department 1", departmentCode: "ZE8761", setFor: [{ code: "C98761", source: "STRUCTURE" }],
  programmes: [{ code: "C98761", name: "B.Sc. Made-up Structure", level: 300 }], attachmentFor: [{ code: "C98761", name: "B.Sc. Made-up Structure", level: 300, semester: 2 }] });
// its department's one course, in no structure
const L_DEPARTMENT = row(q("ZZQ 398", "Students Industrial Work Experience Scheme (made up)"), { department: "Made-up Department 5", departmentCode: "ZE8765",
  setFor: [{ code: "C98765", source: "DEPARTMENT" }] });
// not on the SIWES courses: listed because it is set as a programme's SIWES course on the desk
const L_SET = row(q("ZZQ 301", "Made-up field course"), { department: "Made-up Department 6", departmentCode: "ZE8766", marked: false, byTitle: false, setFor: [{ code: "C98766", source: "SET" }] });
// on the SIWES courses, written down for nobody yet
const L_WAITING = row(ZZQ397, { department: "Made-up Department 3", departmentCode: "ZE8763", programmes: [{ code: "C98763", name: "B.Sc. Made-up Found", level: 300 }],
  attachmentFor: [{ code: "C98763", name: "B.Sc. Made-up Found", level: 300, semester: 2 }] });

test("V776: the SIWES courses say whose course each is — set here or recognised — and a course only set for a programme is not on them", () => {
  const names = programmeNames({ programmes: [R_STRUCTURE, R_FOUND, { code: "C98765", name: "B.Sc. Made-up Department" }, { code: "C98766", name: "B.Sc. Made-up Set" }], candidates: [], siwesCourses: [L_STRUCTURE] });
  // marked false: how it is known is that it is set as a programme's course — not "added here" — and there is nothing to take off
  assert.deepEqual([siwesCourseKnownWords(L_SET), onSiwesCourses(L_SET)], ["Set as a programme's SIWES course", false]);
  assert.deepEqual([siwesCourseKnownWords(L_STRUCTURE), onSiwesCourses(L_STRUCTURE)], ["By its title", true]);
  assert.deepEqual([siwesCourseKnownWords({ ...L_SET, marked: true }), onSiwesCourses({ ...L_SET, marked: null })], ["Added here", true]);
  // a course taken off the SIWES courses whose title still reads SIWES, set for a programme: set, not "by its title"
  assert.equal(siwesCourseKnownWords({ marked: false, byTitle: true }), "Set as a programme's SIWES course");
  // set for, and recognised for, apart: by the source of each
  assert.deepEqual([setForWords(L_SET, names), recognisedForWords(L_SET, names)], ["B.Sc. Made-up Set", ""]);
  assert.deepEqual([setForWords(L_STRUCTURE, names), recognisedForWords(L_STRUCTURE, names)], ["", "B.Sc. Made-up Structure"]);
  assert.deepEqual([setForWords(L_DEPARTMENT, names), recognisedForWords(L_DEPARTMENT, names)], ["", "B.Sc. Made-up Department"]);
  assert.deepEqual([setForWords(L_WAITING, names), recognisedForWords(L_WAITING, names)], ["", ""]);
  const mixed = { setFor: [{ code: "C98766", curriculum: "BMAS", source: "SET" }, { code: "C98761", source: "STRUCTURE" }, { code: "C98799", curriculum: "CCMAS", source: "DEPARTMENT" }] };
  assert.deepEqual([setForWords(mixed, names), recognisedForWords(mixed, names)], ["B.Sc. Made-up Set (BMAS)", "B.Sc. Made-up Structure; C98799 (CCMAS)"]);
  // the attachment semesters that rest on a course, with level and semester; none on one that is not on the SIWES courses
  assert.equal(attachmentForWords(L_STRUCTURE), "B.Sc. Made-up Structure (300 Level, Second Semester)");
  assert.equal(attachmentForWords(L_DEPARTMENT), "");
  const two = { attachmentFor: [{ code: "C98761", name: "B.Sc. Made-up Structure", level: 300, semester: 2 }, { code: "C98770", level: 400, semester: 1 }] };
  assert.equal(attachmentForWords(two), "B.Sc. Made-up Structure (300 Level, Second Semester); C98770 (400 Level, First Semester)");
  assert.equal(attachmentForWords({ ...two, marked: false }), "");
  assert.equal(attachmentForWords(two, 1), "B.Sc. Made-up Structure (300 Level, Second Semester); and 1 more");
  // the names the screen knows include those the attachment semesters carry
  assert.equal(programmeNames({ programmes: [], candidates: [], siwesCourses: [L_WAITING] }).C98763, "B.Sc. Made-up Found");
});

test("V776: taking a course off the SIWES courses names the programmes left waiting and the attachment semesters it ends", () => {
  const names = { C98761: "B.Sc. Made-up Structure", C98765: "B.Sc. Made-up Department" };
  const off = siwesCourseOffWords(L_STRUCTURE, names);
  assert.match(off, /^Take ZZQ 399 — Industrial Training \(made up\) off the SIWES courses\?\n\nThe portal then reads it as an ordinary course: it stops charging the SIWES registration fee, and no programme comes by it as its SIWES course\. /);
  assert.match(off, /The programme it was written down for \(B\.Sc\. Made-up Structure\) waits for a SIWES course again: its 300 Level students are not held to the SIWES course alone until one is set or written down\. /);
  // V777: the programmes it was written down for lose only the binding; the fee is a course's, and goes with the course
  assert.doesNotMatch(off, /not asked to pay/);
  assert.match(off, /\n\nTaking it off also ends the attachment semester — the semester that holds the SIWES course alone — of B\.Sc\. Made-up Structure \(300 Level, Second Semester\)\.\n\n/);
  assert.match(off, /or while students are registered in an attachment semester it makes\.$/);
  // recognised for several; no attachment semester: not spoken of
  const dept = siwesCourseOffWords({ ...L_DEPARTMENT, setFor: [{ code: "C98765", source: "DEPARTMENT" }, { code: "C98761", curriculum: "BMAS", source: "STRUCTURE" }] }, names);
  assert.match(dept, /The programmes it was written down for \(B\.Sc\. Made-up Department; B\.Sc\. Made-up Structure \(BMAS\)\) wait for a SIWES course again: their 300 Level students are not held to the SIWES course alone/);
  assert.doesNotMatch(dept, /attachment semester —/);
  // written down for nobody: nobody is left waiting, and its attachment semester is named still
  const waiting = siwesCourseOffWords(L_WAITING, names);
  assert.doesNotMatch(waiting, /written down for/);
  assert.match(waiting, /of B\.Sc\. Made-up Found \(300 Level, Second Semester\)\./);
  // no code of the database's is shown
  for (const w of [off, dept, waiting]) assert.doesNotMatch(w, /STRUCTURE|DEPARTMENT|SIWES_COURSE_IN_USE|industrial_training|origin/);
});

test("V776: a course added to the SIWES courses has the waiting programmes recognised again — the notice names those that came by their course", () => {
  // the list before the act (the configuration's) and PUT /siwes-courses' answer to ZZQ 302 added
  const before = [L_STRUCTURE, L_WAITING, row(ZZQ393, { programmes: [{ code: "C98768", name: "B.Sc. Made-up Head of several", level: 300 }] }), row(ZZQ390, { curriculum: "CCMAS" }), L_DEPARTMENT, L_SET];
  const after = [row(ZZQ302, { byTitle: false }), L_STRUCTURE, { ...L_WAITING, setFor: [{ code: "C98763", source: "STRUCTURE" }] },
    { ...before[2], setFor: [{ code: "C98768", source: "STRUCTURE" }] }, { ...before[3], setFor: [{ code: "C98769", source: "STRUCTURE" }] }, L_DEPARTMENT, L_SET];
  assert.deepEqual(newlyRecognised(before, after), [{ code: "C98763", curriculum: null, course: "ZZQ 397" }, { code: "C98768", curriculum: null, course: "ZZQ 393" },
    { code: "C98769", curriculum: null, course: "ZZQ 390" }]);
  const names = { C98763: "B.Sc. Made-up Found", C98768: "B.Sc. Made-up Head of several" };
  assert.deepEqual(siwesCourseAddedWords(after, "zzq 302", before, names), { tone: "ok",
    words: "ZZQ 302 is now a SIWES course, and carries the SIWES registration fee. Now written down as the course of: B.Sc. Made-up Found — ZZQ 397; B.Sc. Made-up Head of several — ZZQ 393; C98769 — ZZQ 390." });
  // nobody came by a course: the bare success; and nothing is claimed without the list as it stood before
  assert.deepEqual(siwesCourseAddedWords(before, "ZZQ 302", before, names), { tone: "ok", words: "ZZQ 302 is now a SIWES course, and carries the SIWES registration fee" });
  for (const b of [undefined, null]) assert.deepEqual(siwesCourseAddedWords(after, "ZZQ 302", b, names), { tone: "ok", words: "ZZQ 302 is now a SIWES course, and carries the SIWES registration fee" });
  assert.deepEqual(newlyRecognised(null, null), []);
  // a course set on the desk since is not "recognised"; one recognised for a curriculum names it; more than four are counted
  assert.deepEqual(newlyRecognised([], [{ ...L_SET }, { ...L_WAITING, setFor: [{ code: "C98763", curriculum: "BMAS", source: "DEPARTMENT" }] }]), [{ code: "C98763", curriculum: "BMAS", course: "ZZQ 397" }]);
  const many = [{ ...L_WAITING, setFor: Array.from({ length: 6 }, (_, i) => ({ code: `P${i}`, source: "STRUCTURE" })) }];
  assert.match(siwesCourseAddedWords(many, "ZZQ 397", [], {}).words, /Now written down as the course of: P0 — ZZQ 397; P1 — ZZQ 397; P2 — ZZQ 397; P3 — ZZQ 397; and 2 more\.$/);
  // a course no programme comes by on its own is a warning still, with whoever was recognised by the act after it
  const fourth = row(q("ZZQ 499", "Field attachment"), { level: 400, byTitle: false, recognised: false });
  assert.deepEqual(siwesCourseAddedWords([fourth, after[2]], "ZZQ 499", [L_WAITING], names), { tone: "warn",
    words: "ZZQ 499 is now a SIWES course. No programme comes by it on its own: it is a 400 Level course, not 300 Level. "
      + "It is a programme's SIWES course only where it is set for the programme. Students who register it pay the SIWES fee all the same. "
      + "Now written down as the course of: B.Sc. Made-up Found — ZZQ 397." });
});

// ── V776 round 3: what a programme's 300 Level Second Semester is, the SIWES course carried where SIWES registration does not reach,
//    a course written down beside what the catalogue now offers — the answers of registration.siwes_config on a scratch database with the
//    migration applied (made-up programmes and courses), as the API sends them: a key with nothing in it is left out ────────────────────
const ZZQ389 = q("ZZQ 389", "SIWES (made up moved)");
const ZZQ388 = q("ZZQ 388", "SIWES (made up, the larger)", 8);
const E_FIRST: SiwesElsewhere = { code: "ZZQ 387", title: "Industrial Training I (made up first semester)", level: 300, semester: "FIRST" };
const E_FOURTH: SiwesElsewhere = { code: "ZZQ 386", title: "Industrial Training IV (made up fourth year)", level: 400, semester: "SECOND" };
const NO_OTHER = { units: 0, courses: 0 };
// its structure carries a SIWES course and another course of 300 Level Second Semester: the semester is not the SIWES semester
const X_FOUND: SiwesConfigProgramme = { ...unit, code: "C98763", name: "B.Sc. Made-up Found", found: ZZQ397, choices: [ZZQ397], eligible: 0, attachment: false, otherRequired: { units: 5, courses: 2 },
  curricula: [{ found: ZZQ397, mapped: false, choices: [ZZQ397], curriculum: "CCMAS" }] };
// two of equal standing, the semester the SIWES semester
const X_SEVERAL: SiwesConfigProgramme = { ...unit, code: "C98764", name: "B.Sc. Made-up Several", choices: [ZZQ395, ZZQ396], eligible: 0, attachment: true, otherRequired: NO_OTHER,
  curricula: [{ mapped: false, choices: [ZZQ395, ZZQ396], curriculum: "CCMAS" }] };
// its SIWES course is a First Semester course of 300 Level; another's, a 400 Level course
const X_FIRST: SiwesConfigProgramme = { ...unit, code: "C98765", name: "B.Sc. Made-up First semester", eligible: 0, attachment: false, otherRequired: NO_OTHER, elsewhere: [E_FIRST],
  curricula: [{ mapped: false, elsewhere: [E_FIRST], curriculum: "CCMAS" }] };
const X_FOURTH: SiwesConfigProgramme = { ...unit, code: "C98766", name: "B.Sc. Made-up Fourth year", eligible: 0, attachment: false, otherRequired: NO_OTHER, elsewhere: [E_FOURTH],
  curricula: [{ mapped: false, elsewhere: [E_FOURTH], curriculum: "CCMAS" }] };
const X_NONE: SiwesConfigProgramme = { ...unit, code: "C98762", name: "B.Sc. Made-up None", eligible: 0, attachment: false, otherRequired: NO_OTHER, curricula: [{ mapped: false, curriculum: "CCMAS" }] };
// written down from its structure as it was added; the catalogue came to hold a larger SIWES course since: found beside the course
const X_MOVED: SiwesConfigProgramme = { ...unit, code: "C98767", name: "B.Sc. Made-up Moved", course: ZZQ389, source: "STRUCTURE", found: ZZQ388, eligible: 1, attachment: true, otherRequired: NO_OTHER,
  curricula: [{ course: ZZQ389, found: ZZQ388, mapped: true, source: "STRUCTURE" }, { course: ZZQ389, found: ZZQ388, mapped: false, source: "STRUCTURE", curriculum: "CCMAS" }] };
// its course ended: the cohort is unreached, no other offered
const ZZQ399_ENDED = { ...ZZQ399, state: "ENDED" };
const X_ENDED: SiwesConfigProgramme = { ...unit, code: "C98761", name: "B.Sc. Made-up Structure", course: ZZQ399_ENDED, source: "STRUCTURE", eligible: 0, attachment: false, otherRequired: NO_OTHER,
  curricula: [{ course: ZZQ399_ENDED, mapped: true, source: "STRUCTURE" }, { course: ZZQ399_ENDED, mapped: false, source: "STRUCTURE", curriculum: "CCMAS" }] };
const X_CURRICULA: SiwesConfigProgramme = { ...unit, code: "C98769", name: "B.Sc. Made-up Two curricula", found: ZZQ391, choices: [ZZQ390, ZZQ391], eligible: 0, attachment: false, otherRequired: { units: 4, courses: 1 },
  curricula: [{ found: ZZQ390, mapped: false, choices: [ZZQ390, ZZQ391], curriculum: "CCMAS" }] };
const FIRST_SENTENCE = "Its SIWES course ZZQ 387 Industrial Training I (made up first semester) is a First Semester course (300 Level)";
const FOURTH_SENTENCE = "Its SIWES course ZZQ 386 Industrial Training IV (made up fourth year) is a 400 Level course";
// V777: such a course is charged all the same — its students pay the fee when they register it on Course Registration; nothing to set
const NOT_ASKED = "Its students pay the SIWES fee when they register it, on Course Registration";

test("V776 round 3: where a course is found the row says what the programme's Second Semester is — the SIWES semester, or one that also carries required courses", () => {
  assert.equal(secondSemesterWords(X_SEVERAL), "Its Second Semester is the SIWES semester: students register the SIWES course alone");
  assert.equal(secondSemesterWords(X_FOUND), "Its Second Semester also carries 2 required courses (5 units), which students bound to SIWES could no longer register");
  assert.equal(secondSemesterWords(X_CURRICULA), "Its Second Semester also carries 1 required course (4 units), which students bound to SIWES could no longer register");
  assert.equal(secondSemesterWords({ attachment: false, otherRequired: { courses: 1, units: 1 } }), "Its Second Semester also carries 1 required course (1 unit), which students bound to SIWES could no longer register");
  // not the SIWES semester and no other required course: nothing to say; the answer that does not say: nothing claimed
  for (const p of [X_NONE, X_FIRST, null, undefined, {}, { attachment: null }, { otherRequired: { courses: 3, units: 9 } }, { attachment: false, otherRequired: null }]) assert.equal(secondSemesterWords(p), "", JSON.stringify(p));
  // no code of the database's is shown
  for (const p of [X_SEVERAL, X_FOUND]) assert.doesNotMatch(secondSemesterWords(p), /attachment|otherRequired|true|false/);
});

test("V776 round 3: \"Use it\" on a programme whose Second Semester is not the SIWES semester asks first, in the officer's words, with the published fee", () => {
  const published = { amount: "4000.00", state: "PUBLISHED" };
  assert.equal(confirmUseItWords(X_FOUND, ZZQ397, published),
    "Its 300 Level Second Semester also carries 2 required courses (5 units). SIWES registration holds its 300 Level students to the SIWES course alone in that semester and asks them ₦4,000 first. "
    + "Use ZZQ 397 SIWES (made up found) as the programme's SIWES course?");
  // the fee the Bursary published, when there is one; otherwise the SIWES fee of ₦4,000
  assert.match(confirmUseItWords(X_FOUND, ZZQ397, { amount: 5000, state: "PUBLISHED" }) ?? "", /asks them ₦5,000 first\./);
  for (const fee of [{ amount: 9000, state: "DRAFT" }, { amount: null, state: "PUBLISHED" }, { amount: 0, state: "PUBLISHED" }, null, undefined]) {
    assert.match(confirmUseItWords(X_FOUND, ZZQ397, fee) ?? "", /asks them ₦4,000 first\./, JSON.stringify(fee));
  }
  assert.equal(SIWES_FEE_STANDARD, 4000);
  assert.match(confirmUseItWords(X_CURRICULA, ZZQ391, published) ?? "", /^Its 300 Level Second Semester also carries 1 required course \(4 units\)\. /);
  // not the SIWES semester but no other required course: what the press binds is still told, without a count
  assert.equal(confirmUseItWords({ attachment: false, otherRequired: NO_OTHER }, { code: "ZZQ 397", title: null }, published),
    "SIWES registration holds its 300 Level students to the SIWES course alone in that semester and asks them ₦4,000 first. Use ZZQ 397 as the programme's SIWES course?");
  // the SIWES semester: no confirmation; an answer that does not say: none, as before
  for (const p of [X_SEVERAL, X_MOVED, null, undefined, {}, { attachment: null }, { otherRequired: { courses: 2, units: 5 } }]) assert.equal(confirmUseItWords(p, ZZQ397, published), null, JSON.stringify(p));
});

test("V776 round 3: a programme whose SIWES course is carried where SIWES registration does not reach is told so plainly — nothing to set, no Use it", () => {
  // the line carries what the answer carries
  assert.deepEqual(programmeCourseLines(X_FIRST), [{ curriculum: "CCMAS", course: null, known: "", elsewhere: [E_FIRST] }]);
  assert.deepEqual(programmeCourseLines({ ...X_FIRST, curricula: [] }), [{ curriculum: null, course: null, known: "", elsewhere: [E_FIRST] }]);
  const first = courseHint(programmeCourseLines(X_FIRST)[0], true);
  assert.deepEqual(first, { kind: "ELSEWHERE", found: null, words: FIRST_SENTENCE, action: NOT_ASKED });
  assert.equal(courseHintWords(first), `${FIRST_SENTENCE}. ${NOT_ASKED}`);
  const fourth = courseHint(programmeCourseLines(X_FOURTH)[0], true);
  assert.deepEqual(fourth, { kind: "ELSEWHERE", found: null, words: FOURTH_SENTENCE, action: NOT_ASKED });
  // a reader is told the same; nobody is invited to set a course the database would refuse
  assert.deepEqual(courseHint(programmeCourseLines(X_FIRST)[0], false), first);
  for (const h of [first, fourth]) assert.doesNotMatch(courseHintWords(h), /set it|Use it|add the course|the Academic Office sets/);
  // V777: never "not covered yet" or "cannot be set": the course is charged, on Course Registration — a dead end no more
  for (const h of [first, fourth]) assert.doesNotMatch(courseHintWords(h), /not covered|cannot|only for now|not asked/);
  assert.equal(ON_COURSE_REGISTRATION, "Registered on Course Registration");
  // where it stands: a course of another level is that level's; a First Semester one says its level in brackets; an answer short of either says what it can
  assert.equal(elsewhereWhere({ level: 400, semester: "FIRST" }), "a 400 Level course");
  assert.equal(elsewhereWhere({ level: 400, semester: "BOTH" }), "a 400 Level course");
  assert.equal(elsewhereWhere({ level: 200, semester: null }), "a 200 Level course");
  assert.equal(elsewhereWhere({ level: 300, semester: "FIRST" }), "a First Semester course (300 Level)");
  assert.equal(elsewhereWhere({ level: null, semester: "FIRST" }), "a First Semester course");
  assert.equal(elsewhereWhere({ level: 300, semester: null }), "a course outside the Second Semester of 300 Level");
  assert.equal(elsewhereWhere({ level: undefined, semester: "BOTH" }), "a course outside the Second Semester of 300 Level");
  // several: each with where it stands, the first few named and the rest counted; its title left out where the answer has none
  assert.deepEqual(elsewhereWords([E_FIRST, E_FOURTH]), { action: NOT_ASKED.replace("when they register it", "when they register one of them"),
    words: "Its SIWES courses are ZZQ 387 Industrial Training I (made up first semester) (300 Level, First Semester); ZZQ 386 Industrial Training IV (made up fourth year) (400 Level)" });
  assert.equal(elsewhereWords([E_FIRST, E_FOURTH, { code: "ZZQ 385", level: 400, semester: "FIRST" }, { code: "ZZQ 384", level: 200, semester: "SECOND" }])?.words.endsWith("; ZZQ 385 (400 Level, First Semester); and 1 more"), true);
  assert.equal(elsewhereWords([{ code: "ZZQ 385", level: 400 }])?.words, "Its SIWES course ZZQ 385 is a 400 Level course");
  for (const none of [[], null, undefined, [{ code: "" }]]) assert.equal(elsewhereWords(none as SiwesElsewhere[] | null | undefined), null);
  // found and choices come first: one offered beside what is carried elsewhere is the offer; the generic words stay for neither
  const both = { found: ZZQ397, choices: [ZZQ397], elsewhere: [E_FIRST] };
  assert.equal(courseHint(both, true).kind, "FOUND");
  assert.equal(courseHint({ choices: [ZZQ397], elsewhere: [E_FIRST] }, true).kind, "CHOICES");
  assert.equal(courseHint({ elsewhere: [] }, true).kind, "NONE");
  assert.equal(courseHint(programmeCourseLines(X_NONE)[0], true).words, NO_COURSE_FOUND);
  assert.equal(courseHintWords(courseHint(null, true)), noCourseWords(true));
  // the programme just added says so as a warning, never a bare success and never "set it"
  const config = { programmes: [X_FIRST, X_FOURTH, X_NONE] };
  assert.deepEqual(programmeAddedWords(config, "C98765", "2025/2026"), { tone: "warn", words: `B.Sc. Made-up First semester takes SIWES in 2025/2026. ${FIRST_SENTENCE}. ${NOT_ASKED}.` });
  assert.deepEqual(programmeAddedWords(config, "C98766", "2025/2026"), { tone: "warn", words: `B.Sc. Made-up Fourth year takes SIWES in 2025/2026. ${FOURTH_SENTENCE}. ${NOT_ASKED}.` });
  assert.match(programmeAddedWords(config, "C98762", "2025/2026").words, /, but no SIWES course is found for it \(CCMAS\) yet: set it, or add the course to the SIWES courses\. /);
});

test("V776 round 3: the cohorts no SIWES course reaches — each says what is carried elsewhere, or what the programme's Second Semester is where a course is offered", () => {
  const rows: SiwesUnreached[] = [
    { paid: 0, students: 1, elsewhere: [E_FIRST], programme: "B.Sc. Made-up First semester", curriculum: "CCMAS", programmeCode: "C98765" },
    { paid: 0, found: ZZQ397, choices: [ZZQ397], students: 2, programme: "B.Sc. Made-up Found", curriculum: "CCMAS", programmeCode: "C98763" },
    { paid: 0, students: 1, elsewhere: [E_FOURTH], programme: "B.Sc. Made-up Fourth year", curriculum: "CCMAS", programmeCode: "C98766" },
    { paid: 0, students: 1, programme: "B.Sc. Made-up None", curriculum: "CCMAS", programmeCode: "C98762" },
    { paid: 0, choices: [ZZQ395, ZZQ396], students: 1, programme: "B.Sc. Made-up Several", curriculum: "CCMAS", programmeCode: "C98764" },
    { paid: 1, students: 2, programme: "B.Sc. Made-up Structure", curriculum: "CCMAS", programmeCode: "C98761" },
  ];
  const programmes = [X_FIRST, X_FOUND, X_FOURTH, X_NONE, X_SEVERAL, X_ENDED];
  const u = unreachedLines({ unreached: rows, programmes }, true);
  assert.deepEqual([u.title, u.students, u.paid], ["No SIWES course reaches 8 students at 300 Level yet", 8, 1]);
  assert.deepEqual(u.lines, [
    { key: "C98765|CCMAS", name: "B.Sc. Made-up First semester (CCMAS)", words: "1 student at 300 Level", course: `${FIRST_SENTENCE}. ${NOT_ASKED}` },
    { key: "C98763|CCMAS", name: "B.Sc. Made-up Found (CCMAS)", words: "2 students at 300 Level",
      course: "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — set it as the programme's course above",
      semester: "Its Second Semester also carries 2 required courses (5 units), which students bound to SIWES could no longer register" },
    { key: "C98766|CCMAS", name: "B.Sc. Made-up Fourth year (CCMAS)", words: "1 student at 300 Level", course: `${FOURTH_SENTENCE}. ${NOT_ASKED}` },
    { key: "C98762|CCMAS", name: "B.Sc. Made-up None (CCMAS)", words: "1 student at 300 Level", course: "No SIWES course found — set it, or add the course to the SIWES courses below" },
    { key: "C98764|CCMAS", name: "B.Sc. Made-up Several (CCMAS)", words: "1 student at 300 Level",
      course: "Several SIWES courses found: ZZQ 395 Industrial Attachment B (made up) (6 units); ZZQ 396 Industrial Attachment A (made up) (6 units) — set the one the programme's students register",
      semester: "Its Second Semester is the SIWES semester: students register the SIWES course alone" },
    { key: "C98761|CCMAS", name: "B.Sc. Made-up Structure (CCMAS)",
      words: "2 students at 300 Level; 1 of them has paid or registered — held to SIWES, and cannot register until the course is set",
      // the course written down for the programme has ended (X_ENDED): said first
      course: "ZZQ 399 has ended. No SIWES course found — set it, or add the course to the SIWES courses below" },
  ]);
  // the semester is said only where a course is offered; a reader is told who sets it
  assert.deepEqual(u.lines.map((l) => l.semester !== undefined), [false, true, false, false, true, false]);
  assert.equal(unreachedLines({ unreached: rows, programmes }).lines[1].course, "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — the Academic Office sets it");
  // the programme not on the answer, and an older answer without the keys, say nothing of the semester
  assert.equal(unreachedLines({ unreached: [rows[1]], programmes: [] }).lines[0].semester, undefined);
  assert.equal(unreachedLines({ unreached: [rows[1]] }).lines[0].semester, undefined);
  assert.equal(unreachedLines({ unreached: [rows[1]], programmes: [{ code: "C98763", name: "B.Sc. Made-up Found" }] }).lines[0].semester, undefined);
});

test("V776 round 3: a course written down from the catalogue beside what the catalogue now offers — another course, or the course has ended — and never beside a course set on the desk", () => {
  // the row's lines: the course written down, and the course the catalogue would now give
  assert.deepEqual(programmeCourseLines(X_MOVED), [{ curriculum: "CCMAS", course: ZZQ389, known: "Written down from the programme's own structure", found: ZZQ388 }]);
  assert.deepEqual(programmeCourseLines({ ...X_MOVED, curricula: [] }), [{ curriculum: null, course: ZZQ389, known: "Written down from the programme's own structure", found: ZZQ388 }]);
  assert.deepEqual(programmeCourseLines({ ...X_MOVED, source: "SET", curricula: [{ ...X_MOVED.curricula![1], source: "SET" }] }), [{ curriculum: "CCMAS", course: ZZQ389, known: "Set here" }]);
  // the course the catalogue offers, by its code, title and units; another's, or the course ended
  assert.equal(foundInsteadWords(ZZQ389, ZZQ388), "The catalogue now offers ZZQ 388 SIWES (made up, the larger) (8 units) instead");
  assert.equal(foundInsteadWords(ZZQ399_ENDED, ZZQ388), "ZZQ 399 has ended; the catalogue now offers ZZQ 388 SIWES (made up, the larger) (8 units) instead");
  assert.equal(foundInsteadWords({ code: "ZZQ 399" }, { code: "ZZQ 388", title: null, units: null }), "The catalogue now offers ZZQ 388 instead");
  // the pressing of "Use it" on such a row asks as it does on any: the semester is the SIWES semester here, so nothing is asked
  assert.equal(confirmUseItWords(X_MOVED, ZZQ388, { amount: "4000.00", state: "PUBLISHED" }), null);
  assert.equal(secondSemesterWords(X_MOVED), "Its Second Semester is the SIWES semester: students register the SIWES course alone");
  // a course that ended and nothing offered: the course stays on the row, with the catalogue's warning as before, no offer made up
  assert.deepEqual(programmeCourseLines(X_ENDED), [{ curriculum: "CCMAS", course: ZZQ399_ENDED, known: "Written down from the programme's own structure" }]);
  assert.deepEqual(configWarnings({ programmes: [X_ENDED, X_MOVED] }).map((w) => [w.programme, w.course, w.ended]), [["B.Sc. Made-up Structure", "ZZQ 399", true]]);
  // a programme added whose course was written down from its structure: the notice names the course, as before
  assert.deepEqual(programmeAddedWords({ programmes: [X_MOVED] }, "C98767", "2025/2026"), { tone: "ok", words: "B.Sc. Made-up Moved takes SIWES in 2025/2026: its SIWES course is ZZQ 389" });
});

test("V776 round 3: a programme added with a course found, or several offered, is told what its Second Semester is", () => {
  const config = { programmes: [X_FOUND, X_SEVERAL, X_CURRICULA] };
  assert.deepEqual(programmeAddedWords(config, "C98763", "2025/2026"), { tone: "warn",
    words: "B.Sc. Made-up Found takes SIWES in 2025/2026, but its SIWES course (CCMAS) is not set yet. "
      + "Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — use it on the programme's row, or set another. "
      + "Its Second Semester also carries 2 required courses (5 units), which students bound to SIWES could no longer register. "
      + ADDED_WAITS });
  assert.deepEqual(programmeAddedWords(config, "C98764", "2025/2026"), { tone: "warn",
    words: "B.Sc. Made-up Several takes SIWES in 2025/2026, but its SIWES course (CCMAS) is not set yet. "
      + "Several SIWES courses found: ZZQ 395 Industrial Attachment B (made up) (6 units); ZZQ 396 Industrial Attachment A (made up) (6 units) — set the one the programme's students register. "
      + "Its Second Semester is the SIWES semester: students register the SIWES course alone. "
      + ADDED_WAITS });
  assert.match(programmeAddedWords(config, "C98769", "2025/2026").words, /Its Second Semester also carries 1 required course \(4 units\), which students bound to SIWES could no longer register\. Its 300 Level students /);
});

test("V776 round 3, V777: the Set course form keeps the rule — a 300 Level, Second Semester course — and says the others are charged all the same", () => {
  assert.equal(SIWES_COURSE_LEVEL_HINT, "Set course names the programme's course for the semester SIWES holds alone: a 300 Level course, taught in the Second Semester. "
    + "A SIWES course at another level or in the First Semester is not set here; its students pay the SIWES fee when they register it, on Course Registration.");
  // never the claim that every SIWES course is a 300 Level one
  assert.doesNotMatch(SIWES_COURSE_LEVEL_HINT, /^A programme's SIWES course is a 300 Level course/);
});

test("V776 round 3: an older answer without the new keys renders as before — no semester, nothing carried elsewhere, no confirmation", () => {
  const old: SiwesConfigProgramme = { code: "C00099", name: "Not set", course: null, curricula: [{ curriculum: "CCMAS", mapped: false }] };
  const oldFound: SiwesConfigProgramme = { code: "C00098", name: "Found", found: ZZQ397, choices: [ZZQ397], curricula: [{ curriculum: "CCMAS", mapped: false, found: ZZQ397, choices: [ZZQ397] }] };
  assert.deepEqual(programmeCourseLines(old), [{ curriculum: "CCMAS", course: null, known: "" }]);
  assert.equal(courseHint(programmeCourseLines(old)[0], true).kind, "NONE");
  assert.equal(secondSemesterWords(oldFound), "");
  assert.equal(confirmUseItWords(oldFound, ZZQ397, null), null);
  assert.deepEqual(programmeAddedWords({ programmes: [oldFound] }, "C00098", "2025/2026"), { tone: "warn",
    words: "Found takes SIWES in 2025/2026, but its SIWES course (CCMAS) is not set yet. Found in the catalogue: ZZQ 397 SIWES (made up found) (6 units) — use it on the programme's row, or set another. "
      + ADDED_WAITS });
  const u = unreachedLines({ unreached: [{ programmeCode: "C00098", programme: "Found", curriculum: "CCMAS", students: 1, found: ZZQ397 }], programmes: [oldFound] }, true);
  assert.equal(u.lines[0].semester, undefined);
  // a course written down on a row of an older answer carries no offer
  const oldSet: SiwesConfigProgramme = { code: "C00097", name: "Old", course: ZZQ399, curricula: [{ curriculum: "CCMAS", course: ZZQ399, mapped: true }] };
  assert.deepEqual(programmeCourseLines(oldSet), [{ curriculum: "CCMAS", course: ZZQ399, known: "" }]);
});

test("V776: a course set here as a programme's SIWES course is not asked about taking off: the programme is named, and another course first", () => {
  const names = { C97761: "B.Sc. Made-up Structure" };
  assert.equal(siwesCourseSetHereWords({ code: "ZZK 399", setFor: [{ code: "C97761", curriculum: null, source: "SET" }] }, names),
    "ZZK 399 is set here as the SIWES course of B.Sc. Made-up Structure: set another course for it first, and then it can be taken off.");
  assert.match(siwesCourseSetHereWords({ code: "ZZK 399", setFor: [{ code: "C97761", curriculum: "CCMAS", source: "SET" }, { code: "C97762", curriculum: null, source: "SET" }] }, names), /set another course for them first/);
  // a course only written down from the catalogue, or set for nobody, is asked about as before
  assert.equal(siwesCourseSetHereWords({ code: "ZZK 399", setFor: [{ code: "C97761", curriculum: null, source: "STRUCTURE" }] }, names), "");
  assert.equal(siwesCourseSetHereWords({ code: "ZZK 399", setFor: [] }, names), "");
  assert.equal(siwesCourseSetHereWords({ code: "ZZK 399" }, names), "");
});

test("V776: a cohort of a programme whose written course has ended is told so first, beside what the catalogue offers", () => {
  const ended: SiwesCourse = { id: "i1", code: "ZZR 301", title: "Industrial Training (ended)", state: "ENDED", units: 6 };
  const config = {
    programmes: [{ code: "C99801", name: "B.Sc. Made-up Ended", course: ended, source: "STRUCTURE", curricula: [] } as unknown as SiwesConfigProgramme],
    unreached: [{ programmeCode: "C99801", programme: "B.Sc. Made-up Ended", curriculum: null, students: 2, paid: 1,
                  elsewhere: [{ code: "ZZR 401", title: "SIWES II", level: 400, semester: "SECOND" }] } as SiwesUnreached],
  };
  const u = unreachedLines(config, true);
  assert.match(u.lines[0].course, /^ZZR 301 has ended\. /);
  // a programme whose course stands is spoken of as before
  const live = unreachedLines({ ...config, programmes: [{ ...config.programmes[0], course: { ...ended, state: "LIVE" } }] }, true);
  assert.doesNotMatch(live.lines[0].course, /has ended/);
  // an older answer without the programme row: as before
  assert.doesNotMatch(unreachedLines({ unreached: config.unreached }, true).lines[0].course, /has ended/);
});

// ── V777: every SIWES course carries the fee — the answers of registration.siwes_eligibility, siwes_fee_gate_many and
//    siwes_entries_unpaid on a scratch database with the migration applied (made-up programmes and courses), as the API sends them ──────
const PERIOD_777 = { state: "OPEN", registrationOpens: "2026-11-21", registrationCloses: "2026-12-02", trainingStarts: "2026-12-22", trainingEnds: "2027-06-20", durationMonths: 6 };
const own = (code: string, o: Partial<SiwesOwnCourse> = {}): SiwesOwnCourse => ({ code, title: `Made-up SIWES ${code.slice(-3)}`, units: 6, level: 300, semester: 1, basis: "Core", state: "LIVE",
  why: "STRUCTURE", held: false, passed: false, ...o });
const G301 = own("ZZG 301");
const G302 = own("ZZG 302", { semester: 2, units: 3 });
const G311 = own("ZZG 311", { semester: 1, units: 3 });
const G312 = own("ZZG 312", { semester: 2, units: 3 });
const G402 = own("ZZG 402", { level: 400, semester: 2 });
// a student of a programme SIWES does not bind, whose programme's structure carries a SIWES course at their level: mode COURSE
const COURSE: MySiwes = {
  eligible: true, applies: false, mode: "COURSE", bound: false, registerOn: "COURSE_REGISTRATION", canPay: true, canRegister: false, reasons: [], session: "2025/2026",
  level: null, semester: null, programme: { code: "C97791", name: "B.Sc. Made-up Attachment" }, department: "Arts and Social Sciences Education", faculty: "Education",
  course: null, courses: [G301], period: PERIOD_777, registrationOpen: true, fee: { amount: 4000, state: "PUBLISHED" }, paid: null, openReference: null, registration: null,
  otherCourses: [], semesterFees: null,
};
const PAID_777 = { reference: "MOAUM-FEE-9", amount: 4000, receiptNo: "R9", at: "2026-11-22T10:00:00Z", source: "PORTAL" };

test("V777: a SIWES course among the ordinary courses — the fee is paid first, then the course is registered on Course Registration, never here", () => {
  const today = "2026-11-22";
  assert.equal(isCourseMode(COURSE), true);
  assert.equal(isCourseMode(OPEN), false);
  // unpaid: pay the fee, once a session; nothing says "alone", nothing is "in the way", the Second Semester is nowhere
  let n = siwesNext(COURSE, today);
  assert.deepEqual([n.step, n.tone, n.pay, n.register, n.print, n.receipt, n.link], ["PAY", "info", true, false, false, false, null]);
  assert.equal(n.title, "Pay the SIWES registration fee of ₦4,000");
  assert.equal(n.words, "Every SIWES course carries the fee, paid once a session. Pay it, then register ZZG 301 (300 Level, First Semester) on Course Registration.");
  for (const w of [n.title, n.words]) assert.doesNotMatch(w, /alone|Second Semester|drop|Remove|SIWES page|other courses/);
  // a reference already drawn is paid, never a second one
  n = siwesNext({ ...COURSE, openReference: { reference: "MOAUM-SIW-7", amount: "4000", expiresAt: null } }, today);
  assert.deepEqual([n.step, n.pay], ["PAY_REFERENCE", true]);
  assert.equal(n.title, "Pay ₦4,000 to register ZZG 301");
  assert.equal(n.words, "Pay the SIWES registration fee against reference MOAUM-SIW-7, then register ZZG 301 (300 Level, First Semester) on Course Registration.");
  // no fee published, no registration: nothing to pay yet, said so
  n = siwesNext({ ...COURSE, fee: { amount: "4000", state: "DRAFT" }, canPay: false }, today);
  assert.deepEqual([n.step, n.pay], ["FEE_NOT_SET", false]);
  assert.equal(n.words, "The Bursary publishes the SIWES registration fee; ZZG 301 (300 Level, First Semester) is registered only once it is published and paid.");
  assert.equal(siwesNext({ ...COURSE, fee: null }, today).step, "FEE_NOT_SET");
  // the server's canPay false never offers a Pay the database would refuse
  assert.equal(siwesNext({ ...COURSE, canPay: false }, today).pay, false);
  // paid: register the course on Course Registration, the semester it is taught in; paying does not register it; the receipt of a portal payment
  n = siwesNext({ ...COURSE, paid: PAID_777 }, today);
  assert.deepEqual([n.step, n.tone, n.register, n.pay, n.print, n.receipt], ["REGISTER_COURSE", "info", false, false, false, true]);
  assert.equal(n.title, "Fee paid: register ZZG 301 on Course Registration");
  assert.equal(n.words, "Your SIWES registration fee for 2025/2026 is paid: it covers every SIWES course you register in the session. Register ZZG 301 (300 Level, First Semester) on Course Registration. Paying does not register it.");
  assert.doesNotMatch(n.words, /other courses/);
  assert.deepEqual(n.link, { href: "/student/register?session=2025%2F2026&semester=1", label: "Course Registration" });
  // an old-portal payment settles it all the same, with no portal receipt
  assert.deepEqual([siwesNext({ ...COURSE, paid: { ...PAID_777, source: "OLD_PORTAL", receiptNo: null } }, today).step, siwesNext({ ...COURSE, paid: { ...PAID_777, source: "OLD_PORTAL" } }, today).receipt], ["REGISTER_COURSE", false]);
  // the course is on the registration and the fee paid: registered, nothing more to do here
  n = siwesNext({ ...COURSE, paid: PAID_777, courses: [{ ...G301, why: "HELD", held: true }] }, today);
  assert.deepEqual([n.step, n.tone, n.link, n.register, n.print], ["REGISTERED", "ok", null, false, false]);
  assert.equal(n.words, "ZZG 301 is on your registration for 2025/2026, and the SIWES registration fee is paid.");
  // the registration's status as the answer carries it: an approved or locked one registers the course, as an answer without it did
  for (const registrationStatus of ["APPROVED", "LOCKED", null, undefined]) {
    n = siwesNext({ ...COURSE, paid: PAID_777, courses: [{ ...G301, why: "HELD", held: true, registrationStatus }] }, today);
    assert.deepEqual([n.step, n.tone, n.link], ["REGISTERED", "ok", null]);
  }
  // a SIWES course already passed is neither owed nor asked for
  assert.deepEqual(ownCourses({ courses: [G301, { ...G302, passed: true }] }).map((c) => c.code), ["ZZG 301"]);
  assert.match(siwesNext({ ...COURSE, courses: [G301, { ...G302, passed: true }] }, today).words, /ZZG 301 \(300 Level, First Semester\) on Course Registration/);
  assert.doesNotMatch(siwesNext({ ...COURSE, courses: [G301, { ...G302, passed: true }] }, today).words, /ZZG 302/);
});

test("V777: a student who holds an unpaid SIWES course from before the rule is told so, and asked the fee now", () => {
  const today = "2026-11-22";
  // the 139 of 2025/2026: registered (an approved registration), no SIWES payment — HELD, in reach, may pay
  const held: MySiwes = { ...COURSE, courses: [{ ...G302, why: "HELD", held: true }] };
  let n = siwesNext(held, today);
  assert.deepEqual([n.step, n.tone, n.pay, n.register], ["PAY_HELD", "bad", true, false]);
  assert.equal(n.title, "Pay the SIWES registration fee of ₦4,000");
  assert.equal(n.words, "You registered ZZG 302 (300 Level, Second Semester) for 2025/2026 before every SIWES course carried the SIWES registration fee. It is asked of every student who registers one, once a session, so you have to pay it now.");
  assert.match(n.words, /before every SIWES course carried the SIWES registration fee/);
  assert.match(n.words, /you have to pay it now/);
  // a held course and another still to register: pay, then register the other
  n = siwesNext({ ...held, courses: [{ ...G311, why: "HELD", held: true }, G312] }, today);
  assert.equal(n.step, "PAY_HELD");
  assert.match(n.words, /^You registered ZZG 311 \(300 Level, First Semester\) for 2025\/2026 before /);
  assert.match(n.words, /so you have to pay it now; then register ZZG 312 \(300 Level, Second Semester\) on Course Registration\.$/);
  // a reference already drawn is paid
  assert.equal(siwesNext({ ...held, openReference: { reference: "MOAUM-SIW-8", amount: 4000, expiresAt: null } }, today).step, "PAY_REFERENCE");
  // paid at last: every course held, registered
  assert.equal(siwesNext({ ...held, paid: PAID_777 }, today).step, "REGISTERED");
  // the fee not yet published: said, not asked
  n = siwesNext({ ...held, fee: null, canPay: false }, today);
  assert.deepEqual([n.step, n.pay], ["FEE_NOT_SET", false]);
  assert.equal(n.words, "ZZG 302 (300 Level, Second Semester) is on your registration. The Bursary publishes the SIWES registration fee; you pay it here once it does.");
  // two held: the plural
  assert.match(siwesNext({ ...COURSE, courses: [{ ...G311, held: true }, { ...G312, held: true }], paid: PAID_777 }, today).words, /^ZZG 311 and ZZG 312 are on your registration for 2025\/2026/);
});

test("V777: the courses of a student carry their own level and semester — one payment, a link to Course Registration for each semester", () => {
  const two: MySiwes = { ...COURSE, courses: [G311, G312], paid: PAID_777 };
  assert.deepEqual([courseWhere(G311), courseWhere(G402), courseWhere(G311, " · "), courseWhere({}), courseWhere({ level: 400 }), courseWhere({ semester: 2 })],
    ["300 Level, First Semester", "400 Level, Second Semester", "300 Level · First Semester", "", "400 Level", "Second Semester"]);
  assert.equal(ownCourseList([G311, G312]), "ZZG 311 (300 Level, First Semester) and ZZG 312 (300 Level, Second Semester)");
  assert.equal(ownCourseList([G311, G312, G402]), "ZZG 311 (300 Level, First Semester), ZZG 312 (300 Level, Second Semester) and ZZG 402 (400 Level, Second Semester)");
  assert.equal(ownCourseList([{ code: "ZZG 400" }]), "ZZG 400");
  assert.equal(ownCourseList([]), "");
  assert.equal(ownCourseLine(G301), "ZZG 301 — Made-up SIWES 301 (6 units) · 300 Level · First Semester");
  assert.deepEqual(courseSemesters([G312, G311, G402]), [1, 2]);
  assert.deepEqual(registerLinks(two), [
    { href: "/student/register?session=2025%2F2026&semester=1", label: "Course Registration, First Semester" },
    { href: "/student/register?session=2025%2F2026&semester=2", label: "Course Registration, Second Semester" }]);
  // one semester: one link, plainly named; nothing to register: none
  assert.deepEqual(registerLinks({ ...two, courses: [G402] }), [{ href: "/student/register?session=2025%2F2026&semester=2", label: "Course Registration" }]);
  assert.deepEqual(registerLinks({ ...two, courses: [{ ...G402, held: true }] }), []);
  assert.deepEqual([heldCourses(two).length, coursesToRegister(two).length], [0, 2]);
  // the step names both, the first semester's link
  const n = siwesNext(two, "2026-11-22");
  assert.equal(n.step, "REGISTER_COURSE");
  assert.equal(n.title, "Fee paid: register ZZG 311 and ZZG 312 on Course Registration");
  assert.equal(n.link?.href, "/student/register?session=2025%2F2026&semester=1");
  // the Course Registration link keeps its default for the SIWES semester (V752): the Second Semester
  assert.equal(courseRegistrationPage("2025/2026").href, "/student/register?session=2025%2F2026&semester=2");
  assert.equal(courseRegistrationPage("2025/2026", 1).href, "/student/register?session=2025%2F2026&semester=1");
  assert.equal(courseRegistrationPage(null, null).href, "/student/register?semester=2");
});

test("V777: the COURSE shape's tiles and card — the courses with where each is taught, never 300 Level, Second Semester; no training dates as the student's", () => {
  const n = siwesNext(COURSE, "2026-11-22");
  assert.deepEqual(siwesTiles(COURSE, n.step), [
    ["SIWES session", "2025/2026", "300 Level · First Semester"],
    ["You", "Eligible", "B.Sc. Made-up Attachment"],
    ["SIWES fee", "₦4,000", "Not paid"],
    ["SIWES courses", "1", "ZZG 301"],
  ]);
  // two courses in two semesters: counted, never one semester's name for both
  const two = { ...COURSE, courses: [G311, G402] };
  assert.deepEqual(siwesTiles(two, "PAY").map((t) => t[2]), ["2 courses", "B.Sc. Made-up Attachment", "Not paid", "ZZG 311, ZZG 402"]);
  // paid; registered
  assert.deepEqual(siwesTiles({ ...COURSE, paid: PAID_777 }, "REGISTER_COURSE")[2], ["SIWES fee", "Paid", "₦4,000 · 22 November 2026"]);
  assert.deepEqual(siwesTiles({ ...COURSE, paid: PAID_777, courses: [{ ...G301, held: true }] }, "REGISTERED")[1], ["You", "Registered", "B.Sc. Made-up Attachment"]);
  // the fee not published
  assert.deepEqual(siwesTiles({ ...COURSE, fee: null }, "FEE_NOT_SET")[2], ["SIWES fee", "—", "Not published yet"]);
  for (const t of siwesTiles(COURSE, n.step)) assert.doesNotMatch(t.join(" "), /Second Semester|January|Training/);
  // the dashboard card is shown while a SIWES course is theirs to pay for: the SIWES semester's rule does not bind them
  assert.equal(siwesApplies(COURSE), false);
  // the COURSE guard stands on its own: whatever `applies` says (true, when a portal payment or a SIWES registration stands) or lacks
  // (an older answer: the reasons would read this eligible student as bound), a COURSE answer is never read as the SIWES semester's
  assert.equal(siwesApplies({ ...COURSE, applies: true }), false);
  assert.equal(siwesApplies({ ...COURSE, applies: undefined }), false);
  assert.equal(siwesApplies({ ...COURSE, applies: null }), false);
  assert.equal(siwesApplies({ ...COURSE, applies: undefined, registration: { id: "r1", status: "APPROVED", at: null } }), false);
  // and the same answer without its mode is read from `applies` and the reasons, as before
  assert.equal(siwesApplies({ ...COURSE, mode: null, applies: true }), true);
  assert.equal(siwesApplies({ ...COURSE, mode: undefined, applies: undefined }), true);
  assert.equal(siwesCardShown(COURSE), true);
  assert.equal(siwesCardShown({ ...COURSE, mode: null, eligible: false, reasons: ["NO_SIWES_COURSE"] }), false);
  // a student of the SIWES semester is as ever: V752's shape, key for key
  const bound: MySiwes = { ...OPEN, mode: "SEMESTER", bound: true, registerOn: "SIWES_PAGE", courses: [{ ...own("CSC 399", { semester: 2 }) }] };
  assert.equal(siwesNext(bound, "2026-11-12").step, "PAY");
  assert.equal(siwesNext(bound, "2026-11-12").title, "Pay the SIWES registration fee of ₦4,000");
  assert.deepEqual(siwesTiles(bound, "PAY")[0], ["SIWES session", "2025/2026", "300 Level · Second Semester"]);
  assert.equal(siwesApplies(bound), true);
});

test("V777: a student whose programme carries no SIWES course at their level is told that one reason — never the configuration's", () => {
  // registration.siwes_eligibility for a student of a programme with none: V752's reasons, plus NO_SIWES_COURSE
  const none: MySiwes = { ...OPEN, eligible: false, applies: false, mode: null, bound: false, registerOn: null, canPay: false, courses: [], level: 300, semester: 2, course: null,
    reasons: ["NOT_CONFIGURED", "NO_COURSE", "NO_SIWES_COURSE"] };
  assert.deepEqual(reasonsToSay(none.reasons), ["NO_SIWES_COURSE"]);
  assert.deepEqual(reasonWords(none.reasons), ["Your programme carries no SIWES course at your level, and you hold or owe none: no SIWES fee is asked of you."]);
  assert.equal(notEligibleWords(none.reasons), "Not eligible: No SIWES course at the level");
  // beside the other reasons that stand (not in study, say), the configuration's still fall away
  assert.deepEqual(reasonsToSay(["NOT_IN_STUDY", "NOT_300_LEVEL", "NO_PERIOD", "NO_SIWES_COURSE"]), ["NOT_IN_STUDY", "NO_SIWES_COURSE"]);
  // without it, every reason is said as before
  assert.deepEqual(reasonsToSay(["NOT_300_LEVEL", "NOT_CONFIGURED"]), ["NOT_300_LEVEL", "NOT_CONFIGURED"]);
  assert.deepEqual(reasonsToSay(null), []);
  // the page: nothing to pay for, said in one sentence — never "not set for this session", whether or not a period is set
  for (const period of [OPEN.period, null]) {
    const n = siwesNext({ ...none, period }, "2026-11-22");
    assert.deepEqual([n.step, n.tone, n.title, n.pay, n.register], ["NOT_ELIGIBLE", "info", "No SIWES fee is asked of you", false, false]);
    assert.equal(n.words, "Your programme carries no SIWES course at your level, and you hold or owe none: no SIWES fee is asked of you.");
  }
  assert.equal(siwesApplies({ eligible: false, reasons: ["NO_SIWES_COURSE"], registration: null }), false);
  assert.equal(siwesCardShown(none), false);
  // V752's reasons for the bound shape stay as they were
  assert.equal(reasonWords(["NOT_300_LEVEL"])[0], "SIWES registration is for 300 Level students, in the Second Semester.");
  assert.equal(rowState({ paid: false, registered: false, eligible: false, reasons: ["NOT_300_LEVEL", "NO_SIWES_COURSE"] })[0], "Not eligible: No SIWES course at the level");
});

test("V777: a SIWES course locked on Course Registration's menu while its fee is unpaid, as a GST/EPS course is — what holds it, and what is done", () => {
  // the gate's words as registration.siwes_fee_gate_many sends them: the first word is the code, never shown
  const unpaid = "SIWES_UNPAID: the SIWES registration fee for 2025/2026 is not paid; ZZG 301 is registered once it is";
  const unset = "SIWES_FEE_NOT_SET: the Bursary has not published the SIWES registration fee for 2025/2026; ZZG 302 is registered once it is published and paid";
  const noReach = "SIWES_NOT_IN_REACH: ZZG 303 is a SIWES course and carries the SIWES registration fee for 2025/2026, but your programme carries no SIWES course at your level, so the fee cannot be paid for it";
  assert.deepEqual([unpaid, unset, noReach, "", null, undefined, "SOMETHING_NEW: words"].map(siwesLockKind), ["UNPAID", "FEE_NOT_SET", "NOT_IN_REACH", "UNPAID", "UNPAID", "UNPAID", "UNPAID"]);
  assert.deepEqual(SIWES_LOCK_PILL, { UNPAID: "SIWES fee required", FEE_NOT_SET: "SIWES fee not published", NOT_IN_REACH: "Not open to you" });
  assert.equal(SIWES_LOCK_TITLE.UNPAID, "Locked until the SIWES fee is paid");
  for (const t of [...Object.values(SIWES_LOCK_PILL), ...Object.values(SIWES_LOCK_TITLE)]) assert.doesNotMatch(t, /SIWES_[A-Z_]+/);
  // the notes over the form: the fee unpaid first, with the amount only when the Bursary has published it
  const notes = siwesLockNotes([{ code: "ZZG 301", gate: unpaid }, { code: "ZZG 311", gate: unpaid }, { code: "ZZG 301", gate: unpaid }, { code: "ZZG 302", gate: unset }, { code: "ZZG 303", gate: noReach }], "2025/2026", 4000);
  assert.deepEqual(notes.map((x) => [x.kind, x.title, x.pay]), [["bad", "SIWES fee required", true], ["info", "SIWES fee not published yet", false], ["info", "SIWES course not open to you", false]]);
  assert.equal(notes[0].words, "Pay the SIWES registration fee of ₦4,000 for 2025/2026 to register ZZG 301 and ZZG 311. It is paid once a session, whichever SIWES course you register: pay it on the SIWES page, then register the course here.");
  assert.equal(notes[1].words, "The Bursary has not published the SIWES registration fee for 2025/2026; ZZG 302 is registered once it is published and paid.");
  assert.equal(notes[2].words, "ZZG 303 is a SIWES course, but your programme carries no SIWES course at your level, so the fee cannot be paid for it: ask the Academic Office.");
  // no amount before one is published; nothing locked, no note
  assert.doesNotMatch(siwesLockNotes([{ code: "ZZG 301", gate: unpaid }], "2025/2026")[0].words, /₦/);
  assert.deepEqual(siwesLockNotes([], "2025/2026", 4000), []);
  for (const x of notes) assert.doesNotMatch(x.words, /SIWES_[A-Z_]+/);
  // a SIWES course already on the registration with the fee unpaid (registered before the rule): the note asks the fee now
  assert.equal(siwesUnpaidRegisteredWords(["ZZG 302"], "2025/2026", 4000),
    "ZZG 302 is on your registration, but the SIWES registration fee of ₦4,000 for 2025/2026 is not paid. You registered it before every SIWES course carried the fee; "
    + "it is asked of every student who registers one, once a session, so you have to pay it now, on the SIWES page.");
  assert.match(siwesUnpaidRegisteredWords(["ZZG 311", "ZZG 312"], "2025/2026"),/^ZZG 311 and ZZG 312 are on your registration, but the SIWES registration fee for 2025\/2026 is not paid\. You registered them before /);
});

test("V777: a SIWES course only on a draft (or returned) registration is on the registration, not registered — the student submits it; a submitted one waits for approval", () => {
  const today = "2026-11-22";
  const heldOn = (registrationStatus: string | null, c: SiwesOwnCourse = G301): SiwesOwnCourse => ({ ...c, why: "HELD", held: true, registrationStatus });
  assert.deepEqual(["DRAFT", "RETURNED", "SUBMITTED", "APPROVED", "LOCKED", null, undefined].map((registrationStatus) => heldStanding({ registrationStatus })),
    ["UNSENT", "UNSENT", "AWAITING", "REGISTERED", "REGISTERED", "REGISTERED", "REGISTERED"]);
  assert.equal(heldStanding({}), "REGISTERED");
  // the fee paid, the course held on a draft or a returned registration: submit the registration — never the green "registered"
  for (const status of ["DRAFT", "RETURNED"]) {
    const d: MySiwes = { ...COURSE, paid: PAID_777, courses: [heldOn(status)] };
    const n = siwesNext(d, today);
    assert.deepEqual([n.step, n.tone, n.register, n.pay, n.receipt], ["SUBMIT_REGISTRATION", "info", false, false, true], status);
    assert.equal(n.title, "Submit your registration to register ZZG 301");
    assert.equal(n.words, "The SIWES registration fee for 2025/2026 is paid. ZZG 301 (300 Level, First Semester) is on your registration, not yet submitted: "
      + "a SIWES course is registered only once the registration that holds it is submitted and approved. Submit your registration on Course Registration.");
    assert.deepEqual(n.link, { href: "/student/register?session=2025%2F2026&semester=1", label: "Course Registration" });
    assert.notEqual(n.title, "SIWES course registered");
    assert.deepEqual(siwesTiles(d, n.step)[1], ["You", "Not submitted", "B.Sc. Made-up Attachment"]);
    assert.deepEqual(heldAs(d, "UNSENT").map((c) => c.code), ["ZZG 301"]);
    assert.deepEqual(heldAs(d, "REGISTERED"), []);
    // the link to submit it, for the semester the course is taught in
    assert.deepEqual(submitLinks(d), [{ href: "/student/register?session=2025%2F2026&semester=1", label: "Course Registration" }]);
  }
  // submitted: waiting for its approval, nothing for the student to do here
  const waiting: MySiwes = { ...COURSE, paid: PAID_777, courses: [heldOn("SUBMITTED")] };
  const w = siwesNext(waiting, today);
  assert.deepEqual([w.step, w.tone, w.link, w.register, w.pay], ["AWAITING_APPROVAL", "info", null, false, false]);
  assert.equal(w.title, "ZZG 301 is waiting for approval");
  assert.equal(w.words, "The SIWES registration fee for 2025/2026 is paid. ZZG 301 (300 Level, First Semester) is on your registration, waiting for approval: "
    + "a SIWES course is registered once the registration that holds it is approved.");
  assert.deepEqual(siwesTiles(waiting, w.step)[1], ["You", "Awaiting approval", "B.Sc. Made-up Attachment"]);
  assert.deepEqual(submitLinks(waiting), []);
  // approved or locked: registered, as ever
  for (const status of ["APPROVED", "LOCKED"]) {
    const d: MySiwes = { ...COURSE, paid: PAID_777, courses: [heldOn(status)] };
    assert.equal(siwesNext(d, today).step, "REGISTERED");
    assert.deepEqual(siwesTiles(d, "REGISTERED")[1], ["You", "Registered", "B.Sc. Made-up Attachment"]);
    assert.deepEqual(submitLinks(d), []);
  }
  // two held courses, one approved and one only a draft: the draft is the one to submit, in its own semester
  const mixed: MySiwes = { ...COURSE, paid: PAID_777, courses: [heldOn("APPROVED", G311), heldOn("DRAFT", G312)] };
  const m = siwesNext(mixed, today);
  assert.deepEqual([m.step, m.title], ["SUBMIT_REGISTRATION", "Submit your registration to register ZZG 312"]);
  assert.equal(m.words, "The SIWES registration fee for 2025/2026 is paid. ZZG 311 (300 Level, First Semester) is already on your registration; "
    + "ZZG 312 (300 Level, Second Semester) is on your registration, not yet submitted: a SIWES course is registered only once the registration that holds it is submitted and approved. Submit your registration on Course Registration.");
  assert.equal(m.link?.href, "/student/register?session=2025%2F2026&semester=2");
  // a course to register beside one held on a draft: register it; the held one is named as it stands
  const beside: MySiwes = { ...COURSE, paid: PAID_777, courses: [heldOn("DRAFT", G311), G312] };
  const b = siwesNext(beside, today);
  assert.equal(b.step, "REGISTER_COURSE");
  assert.equal(b.words, "Your SIWES registration fee for 2025/2026 is paid: it covers every SIWES course you register in the session. Register ZZG 312 (300 Level, Second Semester) on Course Registration; "
    + "ZZG 311 (300 Level, First Semester) is on your registration, not yet submitted. Paying does not register it. A course is registered only once the registration that holds it is submitted.");
  assert.deepEqual(siwesTiles(beside, b.step)[1], ["You", "Eligible", "B.Sc. Made-up Attachment"]);
  // its semester has the course to register already: one link, the register link; the submit link is for the other semester only
  assert.deepEqual(registerLinks(beside).map((l) => l.href), ["/student/register?session=2025%2F2026&semester=2"]);
  assert.deepEqual(submitLinks(beside).map((l) => l.href), ["/student/register?session=2025%2F2026&semester=1"]);
  assert.deepEqual(submitLinks({ ...beside, courses: [heldOn("DRAFT", G311), own("ZZG 321", { semester: 1 })] }), []);
  assert.deepEqual(submitLinks({ ...COURSE, courses: [heldOn("DRAFT", G311), heldOn("RETURNED", G402)] }).map((l) => l.label), ["Course Registration, First Semester", "Course Registration, Second Semester"]);
  // the fee unpaid, the course held on a draft: the fee is asked first, as for any held course
  assert.equal(siwesNext({ ...COURSE, courses: [heldOn("DRAFT")] }, today).step, "PAY_HELD");
  // an older answer that does not say: registered, as before
  assert.equal(siwesNext({ ...COURSE, paid: PAID_777, courses: [{ ...G301, why: "HELD", held: true }] }, today).step, "REGISTERED");
});

test("V777: the codes in the SIWES words are shown without a curriculum mark, as on the rest of the portal; the key stays the raw code", () => {
  const today = "2026-11-22";
  const bmas = own("MAC 399 BMAS", { semester: 1, title: "SIWES (made up)" });
  assert.equal(ownCourseList([bmas]), "MAC 399 (300 Level, First Semester)");
  assert.equal(ownCourseList([bmas, G312]), "MAC 399 (300 Level, First Semester) and ZZG 312 (300 Level, Second Semester)");
  assert.equal(ownCourseLine(bmas), "MAC 399 — SIWES (made up) (6 units) · 300 Level · First Semester");
  const d: MySiwes = { ...COURSE, courses: [bmas] };
  assert.equal(siwesNext(d, today).words, "Every SIWES course carries the fee, paid once a session. Pay it, then register MAC 399 (300 Level, First Semester) on Course Registration.");
  assert.equal(siwesNext({ ...d, openReference: { reference: "MOAUM-SIW-7", amount: 4000, expiresAt: null } }, today).title, "Pay ₦4,000 to register MAC 399");
  assert.equal(siwesNext({ ...d, paid: PAID_777 }, today).title, "Fee paid: register MAC 399 on Course Registration");
  assert.equal(siwesNext({ ...d, paid: PAID_777, courses: [{ ...bmas, held: true }] }, today).words, "MAC 399 is on your registration for 2025/2026, and the SIWES registration fee is paid.");
  assert.deepEqual(siwesTiles(d, "PAY")[3], ["SIWES courses", "1", "MAC 399"]);
  // the notes over the form say it the same way, the code however it reaches them
  const unpaid = "SIWES_UNPAID: the SIWES registration fee for 2025/2026 is not paid; MAC 399 BMAS is registered once it is";
  assert.match(siwesLockNotes([{ code: "MAC 399 BMAS", gate: unpaid }], "2025/2026", 4000)[0].words, /to register MAC 399\. /);
  assert.equal(siwesLockNotes([{ code: "MAC 399 BMAS", gate: unpaid }, { code: "MAC 399", gate: unpaid }], "2025/2026")[0].words.includes("BMAS"), false);
  // the course is still told by its key
  assert.equal(ownCourses(d)[0].code, "MAC 399 BMAS");
  assert.deepEqual(courseSemesters(ownCourses(d)), [1]);
});

test("V777: a student SIWES binds, whose First or Third Semester holds a SIWES course while the SIWES window is not open, is told when the fee can be paid — no payment link", () => {
  const today = "2026-11-22";
  const period = (p: Partial<SiwesPeriod>): SiwesPeriod => ({ ...PERIOD_777, state: "OPEN", ...p });
  // V752's student (SEMESTER), the fee published and unpaid, the window not open: the server's canPay is false
  const bound = (p: SiwesPeriod | null): MySiwes => ({ ...OPEN, mode: "SEMESTER", bound: true, applies: true, canPay: false, registrationOpen: false, period: p });
  const before = bound(period({ registrationOpens: "2026-11-28", registrationCloses: "2026-12-02" }));
  assert.equal(siwesPayShutWords(before, today), "SIWES registration opens on 28 November 2026: the SIWES registration fee cannot be paid before then. Pay it once SIWES registration opens, then register the course here.");
  assert.equal(siwesPayShutWords(bound(period({ registrationOpens: "2026-11-01", registrationCloses: "2026-11-15", state: "CLOSED" })), today),
    "SIWES registration is closed, so the SIWES registration fee cannot be paid now: ask the Academic Office.");
  assert.equal(siwesPayShutWords(bound(period({ state: "DRAFT", registrationOpens: null, registrationCloses: null })), today),
    "SIWES registration has not opened yet: the SIWES registration fee cannot be paid before then. Pay it once SIWES registration opens, then register the course here.");
  assert.match(siwesPayShutWords(bound(null), today) ?? "", /^SIWES registration is closed, so /);
  // nothing is said where the fee can be paid, or nothing says it cannot be: the form links to the SIWES page as ever
  for (const d of [{ ...before, canPay: true }, { ...before, canPay: null }, { ...before, canPay: undefined }, { ...before, registrationOpen: true }, { ...before, paid: PAID_777 },
    { ...before, fee: { amount: 4000, state: "DRAFT" } }, { ...before, fee: null }, { ...COURSE, canPay: false, registrationOpen: false }, null, undefined]) {
    assert.equal(siwesPayShutWords(d, today), null);
  }
  // the notes over the form: the fee unpaid said without a payment link, and when the fee can be paid; the others as they were
  const shut = siwesPayShutWords(before, today)!;
  const unpaid = "SIWES_UNPAID: the SIWES registration fee for 2025/2026 is not paid; ZZG 311 is registered once it is";
  const unset = "SIWES_FEE_NOT_SET: the Bursary has not published the SIWES registration fee for 2025/2026; ZZG 302 is registered once it is published and paid";
  const notes = siwesLockNotes([{ code: "ZZG 311", gate: unpaid }, { code: "ZZG 312", gate: unpaid }, { code: "ZZG 302", gate: unset }], "2025/2026", 4000, shut);
  assert.deepEqual(notes.map((x) => [x.kind, x.title, x.pay]), [["bad", "SIWES fee required", false], ["info", "SIWES fee not published yet", false]]);
  assert.equal(notes[0].words, `ZZG 311 and ZZG 312 carry the SIWES registration fee of ₦4,000 for 2025/2026, paid once a session before they are registered. ${shut}`);
  assert.equal(siwesLockNotes([{ code: "ZZG 311", gate: unpaid }], "2025/2026", undefined, shut)[0].words,
    `ZZG 311 carries the SIWES registration fee for 2025/2026, paid once a session before it is registered. ${shut}`);
  assert.doesNotMatch(notes[0].words, /pay it on the SIWES page/);
  // without the words, or with none, the note is as it was
  for (const none of [undefined, null, ""]) {
    const n = siwesLockNotes([{ code: "ZZG 311", gate: unpaid }], "2025/2026", 4000, none);
    assert.deepEqual([n[0].pay, n[0].words], [true, "Pay the SIWES registration fee of ₦4,000 for 2025/2026 to register ZZG 311. It is paid once a session, whichever SIWES course you register: pay it on the SIWES page, then register the course here."]);
  }
  // a course already on the registration: the fee is asked, and when it can be paid
  assert.equal(siwesUnpaidRegisteredWords(["ZZG 302"], "2025/2026", 4000, shut),
    "ZZG 302 is on your registration, but the SIWES registration fee of ₦4,000 for 2025/2026 is not paid. You registered it before every SIWES course carried the fee; "
    + `it is asked of every student who registers one, once a session. ${shut}`);
  assert.doesNotMatch(siwesUnpaidRegisteredWords(["ZZG 302"], "2025/2026", 4000, shut), /pay it now, on the SIWES page/);
  assert.match(siwesUnpaidRegisteredWords(["ZZG 302"], "2025/2026", 4000, null), /so you have to pay it now, on the SIWES page\.$/);
});

test("V777: the desk's first panel holds nobody to SIWES alone while the period is a draft; the question before a programme is taken out says the same", () => {
  assert.deepEqual([periodHolds({ state: "OPEN" }), periodHolds({ state: "CLOSED" }), periodHolds({ state: "DRAFT" }), periodHolds(null), periodHolds(undefined)], [true, true, false, false, false]);
  // an opened period holds the programmes below: stated as a fact
  for (const state of ["OPEN", "CLOSED"]) assert.deepEqual(heldToSiwesRow({ state }), ["Held to SIWES alone", "300 Level · Second Semester of the programmes below"]);
  // a draft or no period: nobody yet, and what their students do meanwhile
  for (const p of [{ state: "DRAFT" }, null, undefined]) {
    const [label, value] = heldToSiwesRow(p);
    assert.equal(label, "Held to SIWES alone");
    assert.match(value, /^Nobody yet: once the period is opened, the 300 Level · Second Semester of the programmes below\. /);
    assert.match(value, /their students pay the SIWES fee and register the course on Course Registration, like every other student\.$/);
  }
  const fee = "they register the Second Semester as before, and still pay the SIWES fee when they register a SIWES course.";
  assert.equal(removeProgrammeWords("B.Sc. Made-up", "C97761", "2025/2026", { state: "OPEN" }),
    `Take B.Sc. Made-up (C97761) out of SIWES for 2025/2026? Its 300 Level students are then no longer held to the SIWES course alone: ${fee}`);
  for (const p of [{ state: "DRAFT" }, null]) {
    const w = removeProgrammeWords("B.Sc. Made-up", "C97761", "2025/2026", p);
    assert.equal(w, `Take B.Sc. Made-up (C97761) out of SIWES for 2025/2026? Its 300 Level students will not be held to the SIWES course alone when the period is opened: ${fee}`);
    assert.doesNotMatch(w, /no longer held/);
  }
});

test("V777: the desk's Unpaid courses tab stays when its read failed, unless the office is refused it", () => {
  const row = {} as SiwesUnpaidEntry;
  assert.equal(unpaidTabShown([row], null), true);
  assert.equal(unpaidTabShown([], null), true);
  // a timeout or a server error: the tab is kept, to say so
  for (const status of [500, 502, 503, 504, 401, 404]) assert.equal(unpaidTabShown(null, { status }), true, String(status));
  assert.equal(unpaidTabShown(null, {}), true);
  // a refusal: the office does not read the list, so the tab is not theirs; nothing read and nothing wrong: no tab
  assert.equal(unpaidTabShown(null, { status: 403 }), false);
  assert.equal(unpaidTabShown(null, null), false);
  assert.equal(unpaidTabShown(undefined, undefined), false);
});

test("V777: the Bursary's list of SIWES courses held without the fee, read from the API's names and counted by student", () => {
  // registration.siwes_entries_unpaid's rows, in the database's names and in the API's
  const db = { student_id: "s1", matric_no: "MOAU/ZSG/97/7903", name: "ZZGATE, G3", programme_code: "C97792", programme: "B.Sc. Made-up Beside", current_level: 300,
    course_code: "ZZG 302", course_title: "Made-up SIWES 302", level: 300, semester: 2, registration_status: "APPROVED", payable: true };
  const api = { studentId: "s2", matricNo: "MOAU/ZSG/97/7904", name: "ZZGATE, G4", programme: "B.Sc. Made-up Beside", currentLevel: 400, courseCode: "ZZG 402", courseTitle: null,
    level: 400, semester: 1, registrationStatus: "DRAFT", payable: false };
  const rows = unpaidEntries([db, api, null, 5, { ...db, course_code: "ZZG 303", semester: "1", payable: "yes" }]);
  assert.equal(rows.length, 3);
  assert.deepEqual(rows[0], { studentId: "s1", matricNo: "MOAU/ZSG/97/7903", name: "ZZGATE, G3", programme: "B.Sc. Made-up Beside", currentLevel: 300, courseCode: "ZZG 302",
    courseTitle: "Made-up SIWES 302", level: 300, semester: 2, registrationStatus: "APPROVED", payable: true });
  assert.deepEqual([rows[1].studentId, rows[1].courseTitle, rows[1].payable, rows[1].currentLevel], ["s2", null, false, 400]);
  // a number from a string; only an explicit true is payable
  assert.deepEqual([rows[2].semester, rows[2].payable], [1, false]);
  // a page ({rows}), an answer that is neither: nothing
  assert.equal(unpaidEntries({ rows: [db] }).length, 1);
  for (const none of [null, undefined, "x", {}, 3]) assert.deepEqual(unpaidEntries(none), []);
  // GET /siwes/admin/unpaid-entries pages the list as the desk's students are paged: rows, how many in all, the students holding them
  const page = { session: "2025/2026", total: 3, students: 2, fee: 4000, page: 0, size: 2, rows: [
    { studentId: "s1", matricNo: "M1", name: "A", programmeCode: "C1", programme: "P", departmentCode: "D", department: "Dept", facultyCode: "F", faculty: "Fac",
      currentLevel: 300, courseCode: "ZZG 302", courseTitle: "T", level: 300, semester: 2, registrationStatus: "APPROVED", payable: true }] };
  assert.equal(unpaidEntries(page)[0].courseCode, "ZZG 302");
  assert.deepEqual([unpaidTotal(page), unpaidTotal({ total: "7" }), unpaidTotal({ total: 0 }), unpaidTotal([db]), unpaidTotal({ rows: [] }), unpaidTotal(null), unpaidTotal({ total: "x" })], [3, 7, 0, null, null, null, null]);
  assert.equal(unpaidEntry({}).courseCode, "");
  // where it stands, the course's place, the words
  assert.deepEqual([unpaidStanding(rows[0]), unpaidStanding(rows[1])], [["Asked to pay now", "bad"], ["Not asked in this session", "grey"]]);
  assert.deepEqual([unpaidWhere(rows[0]), unpaidWhere(rows[1]), unpaidWhere({ level: null, semester: null })], ["300 Level, Second Semester", "400 Level, First Semester", ""]);
  assert.equal(unpaidLine(rows[0]).length, UNPAID_HEAD.length);
  assert.deepEqual(unpaidLine(rows[0]), ["MOAU/ZSG/97/7903", "ZZGATE, G3", "B.Sc. Made-up Beside", 300, "ZZG 302", "Made-up SIWES 302", 300, "Second Semester", "Approved", "Asked to pay now"]);
  assert.deepEqual(unpaidLine(rows[1]).slice(5, 9), ["", 400, "First Semester", "Draft"]);
  // the figures: courses, students (each once), those asked now, and what they owe at the fee in force — none before one is published
  const more = [...rows, { ...rows[0], courseCode: "ZZG 312" }];
  assert.deepEqual(unpaidTotals(more, 4000), { entries: 4, students: 2, payable: 1, owed: 4000 });
  assert.deepEqual(unpaidTotals(more, "4000.00"), { entries: 4, students: 2, payable: 1, owed: 4000 });
  assert.deepEqual(unpaidTotals(more, null), { entries: 4, students: 2, payable: 1, owed: null });
  assert.deepEqual(unpaidTotals([], 4000), { entries: 0, students: 0, payable: 0, owed: 0 });
  assert.match(UNPAID_WORDS, /^Students who hold a SIWES course on a registration of the session and have paid no SIWES fee for it\./);
  assert.match(UNPAID_WORDS, /Nothing here changes a registration\.$/);
  const typed: SiwesUnpaidEntry = rows[0];
  assert.equal(typed.registrationStatus, "APPROVED");
});

test("V777: the Bursary's fee panel says every SIWES course carries the fee, naming the amount only once it is published", () => {
  assert.equal(siwesFeeScopeWords(4000),
    "Every SIWES course carries the SIWES registration fee of ₦4,000: it is paid once a session by every student who registers one, whatever the programme, level or semester, "
    + "before the course is registered. A student who registers several SIWES courses in a session pays it once.");
  for (const none of [null, undefined, "", 0]) {
    const w = siwesFeeScopeWords(none);
    assert.match(w, /^Every SIWES course carries the SIWES registration fee: it is paid once a session by every student who registers one/);
    assert.doesNotMatch(w, /₦/);
  }
  // never the old scope
  assert.doesNotMatch(siwesFeeScopeWords(4000), /300 Level students of the programmes|Second Semester/);
});
