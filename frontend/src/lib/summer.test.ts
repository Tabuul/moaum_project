import { test } from "node:test";
import assert from "node:assert/strict";
import {
  BASIS_WORD, CATEGORIES, CATEGORY_WORD, COURSE_REASON_WORD, DECISION_WORD, DESK_VIEWS, EVIDENCE_WORD, INCOMPLETE_RESULTS_WORD, NOT_ELIGIBLE_WORD, REGISTRATION_CATEGORY_WORD,
  VERIFICATIONS, VERIFICATION_WORD, VIA_WORD,
  asTakenWord, boxesOf, camelKeys, categoriesOf, categoryPill, categoryWord, chunk, countsLine, courseReasonWord, courseSemesterWord, courseStatusWords, cardTitle,
  decisionPreview, deskHref, deskReads, deskView, dispositionName, evidenceTone, evidenceWord, failedInWord, feeFormula, filterPool, groupByLevel, incompleteResultsNote,
  isOwed, lastSessions, maySetSummer, naira, nextStep, notEligibleRefusal, notEligibleWord, paymentStateWords, pickFilters, pageOf, periodForSentence, periodForWord, periodWords,
  plural, poolCounts, poolLevels, queryString, reasonOk, registrationCategoryWord, registrationStatusWord, reportRow, reportTotal, reviewReasonWord, scopeLine,
  selectionCost, selectionFormula, chargeLines, semesterWord, sessionPath, showSummerCard, verificationTone, verificationWord, verificationWords, viaWord,
  AUTHORISATION_GONE_WORD, creditItemWord, creditReopenable, creditSourceWords, isProgrammeCredit, isSummerSitting, summerSittingEdit,
  type MySummer, type SummerCourse, type SummerPeriod, type SummerSummary,
} from "./summer.ts";
import { bffResponseHeaders } from "./bff-headers.ts";

const PERIOD: SummerPeriod = {
  session: "2025/2026", state: "OPEN", registration_opens: "2026-07-01", registration_closes: "2026-07-21", exams_from: "2026-08-10", exams_to: "2026-08-20",
  results_due: "2026-09-01", categories: ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"], programmes: null, levels: null, open_now: true,
};
const FEE = { fee_id: "f1", programme_fee: "50000.00", course_fee: "5000.00" };
const ACCOUNT = { session: "2025/2026", programmeFee: null, programmeFeeState: null, coursesSelected: 0, coursesPaid: 0, courseFeesDue: "0", programmeFeeDue: "0", due: "0", paid: "0", openReference: null, registration: null };
const SUMMARY: SummerSummary = {
  selected: 0, pending: 0, confirmed: 0, notOutstanding: 0, rejected: 0, clarifications: 0, registered: 0, units: 0, unitsRegistered: 0, due: "0", paid: "0",
  paymentStatus: "NOT_STARTED", registrationStatus: "NOT_STARTED", reconcilable: false, lines: [], formula: { programme: "0", perCourse: "5000.00", courses: 0, total: "0" },
};

function course(code: string, o: Partial<SummerCourse> = {}): SummerCourse {
  return {
    course_code: code, title: `${code} title`, units: 3, course_semester: 1, both_semesters: false, level: 300, programme_basis: "Core", is_gst: false, source: "STRUCTURE",
    evidence: "NO_RESULT", attempts: 0, original_session: null, original_semester: null, original_source: null, as_taken_code: null, as_taken_title: null,
    as_taken_session: null, as_taken_semester: null, as_taken_units: null, basis: "STUDENT_SELECTED", status: "OUTSTANDING", selection_id: null, verification: null,
    verified_via: null, decision_reason: null, clarification_open: false, clarification_note: null, student_note: null, selectable: true, reason: null, course_fee: "5000.00", ...o,
  };
}

test("the programme fee is charged once, with the first course; each course adds its fee", () => {
  assert.equal(selectionCost(2, ACCOUNT, FEE), 60000);
  assert.equal(selectionCost(1, { programmeFeeState: "PAID" }, FEE), 5000);
  assert.equal(selectionCost(3, { programmeFeeState: "DUE" }, FEE), 15000);
  assert.equal(selectionCost(0, ACCOUNT, FEE), 0);
  assert.equal(selectionCost(2, ACCOUNT, null), 0);
});

test("selectionCost equals the server's own total once the call is made (a fixture of the server's summaries)", () => {
  // a fresh student selects four courses: the programme fee once and a fee a course, the server's total 70,000
  const after4: SummerSummary = { ...SUMMARY, selected: 4, due: "70000.00", formula: { programme: "50000.00", perCourse: "5000.00", courses: 4, total: "70000.00" } };
  assert.equal(selectionCost(4, ACCOUNT, FEE), 70000);
  assert.equal(selectionCost(4, ACCOUNT, FEE), Number(after4.formula?.total));
  // two are on the account already (programme fee charged), two more are selected: the server's total moves from 60,000 to 70,000
  const before2: SummerSummary = { ...SUMMARY, selected: 2, due: "60000.00", formula: { programme: "50000.00", perCourse: "5000.00", courses: 2, total: "60000.00" } };
  assert.equal(Number(before2.formula?.total) + selectionCost(2, { programmeFeeState: "DUE" }, FEE), Number(after4.formula?.total));
  // a Bursar's 60,000 and 4,000
  const bursar = { programme_fee: "60000", course_fee: "4000" };
  assert.equal(selectionCost(3, ACCOUNT, bursar), 72000);
});

test("the fee formula is the server's own sum, written out", () => {
  assert.equal(feeFormula({ programme: "50000.00", perCourse: "5000.00", courses: 4 }), "₦50,000 + 4 × ₦5,000 = ₦70,000");
  assert.equal(feeFormula({ programme: "60000", perCourse: "4000", courses: 3 }), "₦60,000 + 3 × ₦4,000 = ₦72,000");
  // from a summary: the server's total is the one printed
  assert.equal(feeFormula({ formula: { programme: "50000.00", perCourse: "5000.00", courses: 4, total: "70000.00" } }), "₦50,000 + 4 × ₦5,000 = ₦70,000");
  assert.equal(feeFormula({ ...SUMMARY, formula: { programme: 50000, perCourse: 5000, courses: 1, total: 55000 } }), "₦50,000 + 1 × ₦5,000 = ₦55,000");
  assert.equal(feeFormula({ formula: undefined }), "");
  assert.equal(feeFormula(null), "");
});

test("a course says where it was failed, or that the Academic Office named it", () => {
  assert.equal(failedInWord({ original_session: "2024/2025", original_semester: 2, basis: "CARRY_OVER" }), "Second semester, 2024/2025");
  assert.equal(failedInWord({ original_session: null, original_semester: null, basis: "AUTHORISED" }), "Named by the Academic Office");
  assert.equal(failedInWord({ original_session: null, original_semester: null, basis: "STUDENT_SELECTED" }), "Not stated");
  assert.equal(failedInWord({ original_session: null, original_semester: 1, basis: "STUDENT_SELECTED" }), "First semester");
  assert.equal(failedInWord({ original_session: "2023/2024", original_semester: null, basis: "STUDENT_SELECTED" }), "2023/2024");
  assert.equal(semesterWord(3), "Summer");
  assert.equal(courseReasonWord("RESULT_AWAITED"), "Its result this session is awaited");
  assert.equal(courseSemesterWord({ both_semesters: true, course_semester: 1 }), "Both");
  assert.equal(courseSemesterWord({ both_semesters: false, course_semester: 2 }), "Second");
});

test("the course's reasons carry the words V779 adds, and the old ones", () => {
  assert.equal(COURSE_REASON_WORD.SIWES_OWN_PAGE, "SIWES is registered on its own page");
  assert.equal(COURSE_REASON_WORD.DECIDED_NOT_OUTSTANDING, "Found not outstanding by the Academic Office");
  assert.equal(COURSE_REASON_WORD.DECIDED_REJECTED, "Rejected by the Academic Office");
  // exactly the reasons registration.summer_selectable gives (its why-chain), each with a word; none the database never gives (F10)
  const emitted = ["COURSE_UNKNOWN", "COURSE_ENDED", "ALREADY_REGISTERED", "ALREADY_SELECTED", "DECIDED_NOT_OUTSTANDING", "DECIDED_REJECTED", "SIWES_OWN_PAGE", "PASSED", "RESULT_AWAITED"];
  for (const k of emitted) assert.ok(COURSE_REASON_WORD[k], k);
  assert.deepEqual(Object.keys(COURSE_REASON_WORD).sort(), [...emitted].sort());
  assert.equal(courseReasonWord(null), "");
  assert.equal(courseReasonWord("SOMETHING_NEW"), "SOMETHING_NEW");
});

test("the category words and pills", () => {
  assert.equal(categoryWord("FINAL_YEAR"), "Final-year student");
  assert.equal(categoryWord("SPILLOVER"), "Spillover student");
  assert.equal(categoryWord("BEYOND_DURATION"), "Spillover student");
  assert.equal(categoryWord("AUTHORISED"), "Authorised by the Academic Office");
  assert.equal(categoryWord(null), "—");
  assert.equal(categoryPill("FINAL_YEAR"), "FINAL-YEAR STUDENT");
  assert.equal(categoryPill("SPILLOVER"), "SPILLOVER STUDENT");
  assert.equal(categoryPill("AUTHORISED"), "AUTHORISED BY THE ACADEMIC OFFICE");
  assert.deepEqual([...CATEGORIES], ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"]);
  assert.equal(CATEGORY_WORD.BEYOND_DURATION, CATEGORY_WORD.SPILLOVER);
});

test("the period form shows three boxes; Spillover writes SPILLOVER and BEYOND_DURATION", () => {
  assert.deepEqual(categoriesOf(["FINAL_YEAR", "SPILLOVER"]), ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION"]);
  assert.deepEqual(categoriesOf(["SPILLOVER", "AUTHORISED", "FINAL_YEAR"]), ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"]);
  assert.deepEqual([...boxesOf(["BEYOND_DURATION"])], ["SPILLOVER"]);
  assert.deepEqual([...boxesOf(["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"])], ["FINAL_YEAR", "SPILLOVER", "AUTHORISED"]);
  assert.deepEqual([...boxesOf(null)], ["FINAL_YEAR", "SPILLOVER", "AUTHORISED"]);
  assert.equal(periodForWord(["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"]), "Final-year, Spillover, Authorised");
  assert.equal(periodForWord(["BEYOND_DURATION"]), "Spillover");
});

test("the four verification states, their tones and how each was confirmed", () => {
  assert.equal(VERIFICATION_WORD.PENDING_VERIFICATION, "Student selected – pending verification");
  assert.equal(VERIFICATION_WORD.CONFIRMED_OUTSTANDING, "Academically confirmed outstanding");
  assert.equal(VERIFICATION_WORD.NOT_OUTSTANDING, "Not outstanding – result verified");
  assert.equal(VERIFICATION_WORD.REJECTED, "Rejected – incorrect course selection");
  assert.deepEqual(VERIFICATIONS.map(verificationTone), ["warn", "ok", "grey", "bad"]);
  assert.deepEqual(verificationWords("PENDING_VERIFICATION"), ["Student selected – pending verification", "warn"]);
  assert.deepEqual(verificationWords(null), ["—", "grey"]);
  assert.equal(verificationWord(null), "");
  assert.equal(viaWord("RESULTS"), "Confirmed by your results");
  assert.equal(viaWord("AUTHORISATION"), "Named by the Academic Office");
  assert.equal(viaWord("OFFICER"), "Confirmed by the Academic Office");
  assert.equal(viaWord(null), "");
  assert.deepEqual(Object.keys(VIA_WORD), ["RESULTS", "AUTHORISATION", "OFFICER"]);
});

test("the evidence words, for each thing the results can say", () => {
  assert.equal(EVIDENCE_WORD.RESULT_FAILED, "Confirmed by results (failed)");
  assert.equal(EVIDENCE_WORD.RESULT_PASSED, "Result on record: passed");
  assert.equal(EVIDENCE_WORD.RESULT_AWAITED, "Result awaited");
  assert.equal(EVIDENCE_WORD.NO_RESULT, "No result on record");
  assert.equal(evidenceWord("NO_RESULT"), "No result on record");
  assert.equal(evidenceWord(null), "");
  assert.equal(evidenceTone("RESULT_PASSED"), "warn");
  assert.equal(evidenceTone("RESULT_FAILED"), "info");
});

test("a course the student selected is never called a carry-over", () => {
  assert.equal(REGISTRATION_CATEGORY_WORD.CARRY_OVER, "Carry-over");
  assert.equal(REGISTRATION_CATEGORY_WORD.AUTHORISED, "Authorised course");
  assert.equal(REGISTRATION_CATEGORY_WORD.STUDENT_SELECTED, "Student-selected course");
  assert.notEqual(REGISTRATION_CATEGORY_WORD.STUDENT_SELECTED, "Carry-over");
  assert.equal(registrationCategoryWord("STUDENT_SELECTED"), "Student-selected course");
  // no word a student reads for a student-selected course contains "carry-over", whatever its state
  const said = [registrationCategoryWord("STUDENT_SELECTED"), ...Object.values(VERIFICATION_WORD), ...Object.values(VIA_WORD), ...Object.values(EVIDENCE_WORD),
    registrationStatusWord("SELECTED"), registrationStatusWord("REGISTERED"), registrationStatusWord("TAKEN_OFF"), INCOMPLETE_RESULTS_WORD, ...Object.values(COURSE_REASON_WORD)];
  for (const s of said) assert.ok(!/carry-?over/i.test(s), s);
  for (const status of ["OUTSTANDING", "SELECTED", "REGISTERED", "TAKEN_OFF"] as const) {
    const w = courseStatusWords({ status, evidence: "NO_RESULT", basis: "STUDENT_SELECTED" });
    assert.ok(!w || !/carry-?over/i.test(w[0]));
  }
  assert.equal(BASIS_WORD.CARRY_OVER, "Carry-over");   // a staff screen may name the basis
});

test("the status pill says outstanding only of a course the results or the Office say is owed", () => {
  assert.equal(courseStatusWords({ status: "OUTSTANDING", evidence: "NO_RESULT", basis: "STUDENT_SELECTED" }), null);
  assert.deepEqual(courseStatusWords({ status: "OUTSTANDING", evidence: "RESULT_FAILED", basis: "STUDENT_SELECTED" }), ["Outstanding", "info"]);
  assert.deepEqual(courseStatusWords({ status: "OUTSTANDING", evidence: "NO_RESULT", basis: "CARRY_OVER" }), ["Outstanding", "info"]);
  assert.deepEqual(courseStatusWords({ status: "OUTSTANDING", evidence: "NO_RESULT", basis: "AUTHORISED" }), ["Outstanding", "info"]);
  assert.deepEqual(courseStatusWords({ status: "SELECTED", evidence: "NO_RESULT", basis: "STUDENT_SELECTED" }), ["Selected: unpaid", "warn"]);
  assert.deepEqual(courseStatusWords({ status: "REGISTERED", evidence: "NO_RESULT", basis: "STUDENT_SELECTED" }), ["Registered", "ok"]);
  assert.deepEqual(courseStatusWords({ status: "TAKEN_OFF", evidence: "RESULT_PASSED", basis: "STUDENT_SELECTED" }), ["Taken off", "grey"]);
  assert.equal(isOwed({ evidence: "RESULT_PASSED", basis: "STUDENT_SELECTED" }), false);
  assert.equal(reviewReasonWord("PASSED_ON_RECORD"), "A pass is on record: decide");
  assert.equal(reviewReasonWord("EVIDENCE_CHANGED"), "The result this rested on changed");
  assert.equal(reviewReasonWord(null), "");
});

test("the not-eligible words: no outstanding-course reason any more", () => {
  assert.equal("NO_OUTSTANDING_COURSE" in NOT_ELIGIBLE_WORD, false);
  assert.equal(notEligibleWord("NOT_FINAL_OR_SPILLOVER"), "The Summer Semester is for students in their final year or in spillover.");
  assert.equal(notEligibleWord("GRADUATED"), "Your award is approved; there is nothing left to take.");
  assert.equal(notEligibleWord(null), "You are not eligible for this Summer Semester.");
  assert.equal(notEligibleRefusal("GRADUATED"), "your award is approved");
  assert.equal(notEligibleRefusal("NOT_FINAL_OR_SPILLOVER"), "the Summer Semester is for final-year and spillover students");
  assert.equal(notEligibleRefusal("NOT_STUDYING"), "you are not eligible for the Summer Semester (NOT_STUDYING)");
});

const eligible = { eligible: true, category: "FINAL_YEAR", outstanding: 3, reason: null };

test("the student's next step follows the server's summary", () => {
  const base: MySummer = { session: "2025/2026", period: PERIOD, eligibility: eligible, courses: [course("CSC 401")], fee: FEE, account: ACCOUNT, summary: SUMMARY };
  // open, nothing selected
  assert.equal(nextStep(base), "Search your programme's courses and select the ones you believe you still owe, then pay. The Academic Office verifies each against your record.");
  // owing
  const owing = { ...SUMMARY, selected: 2, due: "60000.00" };
  assert.equal(nextStep({ ...base, summary: owing }), "Pay ₦60,000 to register the courses you selected.");
  assert.equal(nextStep({ ...base, summary: undefined, account: { ...ACCOUNT, due: "60000" } }), "Pay ₦60,000 to register the courses you selected.");
  assert.equal(nextStep({ ...base, fee: null }), "The Bursary has not published the Summer Semester fees yet.");
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, state: "CLOSED" } }), "Registration is closed.");
  assert.equal(nextStep({ ...base, eligibility: { eligible: false, category: null, outstanding: 0, reason: "NOT_FINAL_OR_SPILLOVER" } }), notEligibleWord("NOT_FINAL_OR_SPILLOVER"));
  assert.equal(nextStep({ ...base, period: null }), "No Summer Semester is set.");
  // after the close nothing more is taken: an unpaid selection is removed (V739)
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, state: "CLOSED" }, summary: { ...SUMMARY, selected: 1, due: "5000" } }),
    "Registration is closed: remove the course you selected and did not pay; nothing more is taken.");
  // an open Summer before its window says when it opens (V739)
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, registration_opens: "2026-12-01" } }, "2026-11-12"), "Registration opens on 1 December 2026.");
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, registration_closes: "2026-07-21" } }, "2026-11-12"), "Registration is closed.");
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, state: "PLANNED", registration_opens: null } }, "2026-11-12"), "Registration has not opened yet.");
});

test("some registered, some waiting for the Academic Office; nothing more to select", () => {
  const base: MySummer = { session: "2025/2026", period: PERIOD, eligibility: eligible, courses: [course("CSC 401")], fee: FEE, account: ACCOUNT, summary: SUMMARY };
  const reg = { ...SUMMARY, selected: 3, registered: 3, pending: 2, confirmed: 1, paid: "65000", due: "0" };
  assert.equal(nextStep({ ...base, summary: reg }), "3 courses registered, 2 waiting for the Academic Office to verify.");
  assert.equal(nextStep({ ...base, summary: { ...reg, selected: 1, registered: 1, pending: 1 } }), "1 course registered, 1 waiting for the Academic Office to verify.");
  // registered and all verified: the student may still select more while the window is open
  assert.equal(nextStep({ ...base, summary: { ...reg, pending: 0, confirmed: 3 } }), "3 courses registered. You may select more courses while registration is open.");
  // nothing left to select
  const none: MySummer = { ...base, courses: [course("CSC 401", { selectable: false, status: "REGISTERED", reason: "ALREADY_REGISTERED" })], summary: { ...reg, pending: 0, confirmed: 3 } };
  assert.equal(nextStep(none), "Nothing more can be selected now.");
});

test("the incomplete-results sentence is for an eligible student whose results show nothing owed", () => {
  assert.equal(incompleteResultsNote({ eligibility: { eligible: true, category: "SPILLOVER", outstanding: 0, reason: null } }), INCOMPLETE_RESULTS_WORD);
  assert.equal(incompleteResultsNote({ eligibility: eligible }), null);
  assert.equal(incompleteResultsNote({ eligibility: { eligible: false, category: null, outstanding: 0, reason: "NOT_FINAL_OR_SPILLOVER" } }), null);
  assert.equal(INCOMPLETE_RESULTS_WORD, "Your earlier results may not all be on the portal yet. Select the courses you believe you still owe; the Academic Office will verify them. Nothing here says you owe nothing.");
});

test("the dashboard card: who it is for, its title and its counts", () => {
  const sel: SummerSummary = { ...SUMMARY, selected: 4, pending: 3, confirmed: 1, notOutstanding: 1, rejected: 1, registered: 2, units: 12, due: "20000.00", paid: "30000" };
  assert.equal(countsLine(sel), "Selected 4 · pending verification 3 · confirmed 1 · not outstanding or rejected 2 · registered 2 · units 12 · payable ₦20,000");
  assert.equal(countsLine(null), "");
  const d = { session: "2025/2026", period: PERIOD, eligibility: { eligible: true, category: "SPILLOVER", outstanding: 0, reason: null }, fee: FEE, summary: sel };
  assert.equal(cardTitle(d), "Summer Semester 2025/2026 · SPILLOVER STUDENT");
  assert.equal(showSummerCard(d), true);
  assert.equal(showSummerCard({ ...d, summary: SUMMARY }), true);                                                                   // eligible, window set
  assert.equal(showSummerCard({ ...d, eligibility: { eligible: false, category: null, outstanding: 0, reason: "NOT_FINAL_OR_SPILLOVER" }, summary: SUMMARY }), false);
  assert.equal(showSummerCard({ ...d, period: { ...PERIOD, state: "CLOSED" }, summary: SUMMARY }), false);                          // closed and nothing in it
  assert.equal(showSummerCard({ ...d, period: { ...PERIOD, state: "CLOSED" }, summary: { ...SUMMARY, registered: 1 } }), true);      // closed, registered: the print stays
  assert.equal(showSummerCard({ ...d, eligibility: { eligible: false, category: null, outstanding: 0, reason: "NOT_STUDYING" }, summary: { ...SUMMARY, rejected: 1 } }), true);
  assert.equal(showSummerCard({ ...d, period: null }), false);
  assert.equal(showSummerCard(null), false);
});

test("words for the desk", () => {
  assert.equal(categoryWord("BEYOND_DURATION"), "Spillover student");
  assert.deepEqual(paymentStateWords("PART_PAID"), ["Part paid", "warn"]);
  assert.deepEqual(periodWords({ ...PERIOD, open_now: false }), ["Open — outside its dates", "warn"]);
  assert.deepEqual(periodWords(null), ["Not set", "grey"]);
  assert.equal(naira("50000.00"), "₦50,000");
  assert.equal(sessionPath("2025/2026"), "2025/2026");
  assert.equal(plural(1, "course"), "1 course");
  assert.equal(plural(0, "course"), "0 courses");
});

test("the pool: search by code, title and the code the course was taken as", () => {
  const pool = [
    course("CSC 301", { title: "Data structures", level: 300 }),
    course("CSC 305", { title: "Operating systems", level: 300, as_taken_code: "CSC 303", as_taken_title: "Operating system principles", as_taken_units: 3 }),
    course("MTH 401", { title: "Real analysis", level: 400, course_semester: 2 }),
  ];
  assert.deepEqual(filterPool(pool, { q: "csc 301" }).map((c) => c.course_code), ["CSC 301"]);
  assert.deepEqual(filterPool(pool, { q: "csc301" }).map((c) => c.course_code), ["CSC 301"]);
  assert.deepEqual(filterPool(pool, { q: "OPERATING" }).map((c) => c.course_code), ["CSC 305"]);
  assert.deepEqual(filterPool(pool, { q: "CSC 303" }).map((c) => c.course_code), ["CSC 305"]);           // the code it was taken as
  assert.deepEqual(filterPool(pool, { q: "principles" }).map((c) => c.course_code), ["CSC 305"]);          // the title it was taken under
  assert.deepEqual(filterPool(pool, { q: "analysis" }).map((c) => c.course_code), ["MTH 401"]);
  assert.deepEqual(filterPool(pool, { q: "  " }).map((c) => c.course_code), ["CSC 301", "CSC 305", "MTH 401"]);
  assert.deepEqual(filterPool(pool, { q: "nothing here" }), []);
});

test("the pool: level, semester and scope filters", () => {
  const pool = [
    course("A 100", { level: 100, course_semester: 1 }),
    course("B 200", { level: 200, course_semester: 2 }),
    course("C 300", { level: 300, course_semester: 1, both_semesters: true }),
    course("D 400", { level: 400, course_semester: 2, evidence: "RESULT_FAILED" }),
    course("E 400", { level: 400, course_semester: 1, basis: "CARRY_OVER", source: "CARRY_OVER" }),
    course("F 400", { level: 400, course_semester: 2, status: "SELECTED", selectable: false, reason: "ALREADY_SELECTED" }),
    course("G 400", { level: 400, course_semester: 2, status: "TAKEN_OFF", selectable: false, verification: "REJECTED" }),
  ];
  const codes = (f: Parameters<typeof filterPool>[1]) => filterPool(pool, f).map((c) => c.course_code);
  assert.deepEqual(codes({ level: 400 }), ["D 400", "E 400", "F 400", "G 400"]);
  assert.deepEqual(codes({ level: "all" }), ["A 100", "B 200", "C 300", "D 400", "E 400", "F 400", "G 400"]);
  assert.deepEqual(codes({ semester: 1 }), ["A 100", "C 300", "E 400"]);                      // C is taught in both
  assert.deepEqual(codes({ semester: 2 }), ["B 200", "C 300", "D 400", "F 400", "G 400"]);
  assert.deepEqual(codes({ semester: "all" }), ["A 100", "B 200", "C 300", "D 400", "E 400", "F 400", "G 400"]);
  assert.deepEqual(codes({ scope: "outstanding" }), ["D 400", "E 400"]);                      // failed by the results, or a carry-over
  assert.deepEqual(codes({ scope: "selected" }), ["F 400", "G 400"]);
  assert.deepEqual(codes({ level: 400, semester: 2, scope: "outstanding" }), ["D 400"]);
});

test("the pool grouped by level, in order, a course outside the structure last", () => {
  const pool = [
    course("Z 300", { level: 300, course_semester: 2 }), course("A 300", { level: 300, course_semester: 2 }), course("B 300", { level: 300, course_semester: 1 }),
    course("X 100", { level: 100 }), course("OUT 1", { level: null, source: "AUTHORISED" }), course("Y 400", { level: 400 }),
  ];
  const g = groupByLevel(pool);
  assert.deepEqual(g.map((x) => x.label), ["100 Level", "300 Level", "400 Level", "Other courses"]);
  assert.deepEqual(g[1].courses.map((c) => c.course_code), ["B 300", "A 300", "Z 300"]);        // semester, then code
  assert.deepEqual(g.map((x) => x.level), [100, 300, 400, null]);
  assert.deepEqual(groupByLevel([]), []);
  assert.deepEqual(poolLevels(pool), [100, 300, 400]);
});

test("the pool's counts, for the filters", () => {
  const pool = [course("A 1"), course("B 1", { evidence: "RESULT_FAILED" }), course("C 1", { status: "SELECTED", selectable: false }),
    course("D 1", { status: "REGISTERED", selectable: false }), course("E 1", { status: "TAKEN_OFF", selectable: false, verification: "NOT_OUTSTANDING" })];
  assert.deepEqual(poolCounts(pool), { total: 5, selectable: 2, outstanding: 1, selected: 1, registered: 1, decided: 1, inSelected: 3 });
  assert.deepEqual(poolCounts([]), { total: 0, selectable: 0, outstanding: 0, selected: 0, registered: 0, decided: 0, inSelected: 0 });
});

test("the Selected filter's count is the number of courses it shows, a course decided before it was paid included in neither (F3)", () => {
  // as registration.summer_selectable gives them: a course decided while unpaid stays OUTSTANDING with its reason; one taken off after
  // payment is TAKEN_OFF; one still selected or registered is SELECTED or REGISTERED
  const pool = [
    course("ZZV 101", { status: "OUTSTANDING", verification: "REJECTED", selectable: false, reason: "DECIDED_REJECTED" }),
    course("ZZV 102", { status: "OUTSTANDING", verification: "NOT_OUTSTANDING", selectable: false, reason: "DECIDED_NOT_OUTSTANDING" }),
    course("ZZV 201", { status: "SELECTED", verification: "PENDING_VERIFICATION", selectable: false, reason: "ALREADY_SELECTED" }),
    course("ZZV 202", { status: "REGISTERED", verification: "CONFIRMED_OUTSTANDING", selectable: false, reason: "ALREADY_REGISTERED" }),
    course("ZZV 203", { status: "TAKEN_OFF", verification: "REJECTED", selectable: false, reason: "DECIDED_REJECTED" }),
    course("ZZV 301"),
  ];
  const shown = filterPool(pool, { scope: "selected" }).map((c) => c.course_code);
  assert.deepEqual(shown, ["ZZV 201", "ZZV 202", "ZZV 203"]);
  assert.equal(poolCounts(pool).inSelected, shown.length, "the label says the number the list opens with");
  // the reviewer's case: the old label (selected + registered + decided) said 3 for a list of 1
  const two = [pool[0], pool[1], pool[2]];
  assert.equal(poolCounts(two).inSelected, filterPool(two, { scope: "selected" }).length);
  assert.equal(poolCounts(two).inSelected, 1);
  // the two decided-unpaid courses stay on the page, under All courses, with their reasons
  assert.deepEqual(filterPool(pool, { scope: "all" }).filter((c) => c.reason?.startsWith("DECIDED_")).map((c) => c.course_code), ["ZZV 101", "ZZV 102", "ZZV 203"]);
});

test("the sessions offered for where a course was owed: the last six, up to the Summer's own", () => {
  const names = ["2018/2019", "2019/2020", "2020/2021", "2021/2022", "2022/2023", "2023/2024", "2024/2025", "2025/2026", "2026/2027"];
  assert.deepEqual(lastSessions(names, "2025/2026"), ["2025/2026", "2024/2025", "2023/2024", "2022/2023", "2021/2022", "2020/2021"]);
  assert.deepEqual(lastSessions(["2024/2025", "2025/2026"], "2025/2026"), ["2025/2026", "2024/2025"]);
  assert.deepEqual(lastSessions([], "2025/2026"), []);
});

test("the course as it was taken, when it differs", () => {
  assert.equal(asTakenWord(course("CSC 305", { title: "Operating systems", as_taken_code: "CSC 303", as_taken_title: "Operating system principles", as_taken_units: 3 })),
    "Taken as CSC 303, Operating system principles, 3 units");
  assert.equal(asTakenWord(course("CSC 305", { title: "Operating systems", as_taken_code: "CSC 305", as_taken_title: "Operating systems" })), null);
  assert.equal(asTakenWord(course("CSC 305")), null);
  assert.equal(asTakenWord(course("CSC 305", { title: "OS", as_taken_code: "CSC 303", as_taken_title: null, as_taken_units: 1 })), "Taken as CSC 303, OS, 1 unit");
});

test("the desk: its view follows the address, else the office's work", () => {
  assert.deepEqual(DESK_VIEWS.map((v) => v.id), ["review", "students", "reports", "courses", "period"]);
  assert.equal(deskView(undefined, true), "review");
  assert.equal(deskView(undefined, false), "students");
  assert.equal(deskView("reports", false), "reports");
  assert.equal(deskView("nonsense", true), "review");
  assert.equal(deskView(["students"], true), "review");
  assert.equal(maySetSummer("academic"), true);
  assert.equal(maySetSummer("registrar"), true);
  assert.equal(maySetSummer("hod"), false);
  assert.equal(maySetSummer(null), false);
});

test("the desk for a session with no Summer yet: the Period and acts tab is built for an office that may set one, so its form can set it (F1)", () => {
  // the "Set a new Summer…" control and the empty-state note both send the Office to ?session=<new>&view=period
  assert.equal(deskHref("2026/2027", "period"), "/summer?session=2026%2F2027&view=period");
  assert.equal(deskReads("period", false, true), "new-period", "built with no period, nothing of it read: the form 'Set the Summer Semester of 2026/2027' shows");
  for (const v of ["review", "students", "reports", "courses"] as const) assert.equal(deskReads(v, false, true), "none", `${v}: nothing to read; the note sends the Office to the Period and acts tab`);
  for (const v of DESK_VIEWS.map((x) => x.id)) assert.equal(deskReads(v, false, false), "none", `${v}: an office that only reads is told the Academic Office sets it`);
  for (const v of DESK_VIEWS.map((x) => x.id)) {
    assert.equal(deskReads(v, true, true), "view");
    assert.equal(deskReads(v, true, false), "view");
  }
});

test("the desk's filters keep only what the API takes", () => {
  const f = pickFilters({ state: "PENDING_VERIFICATION", evidence: "NO_RESULT", flag: "x", basis: "STUDENT_SELECTED", paid: "PAID", level: "400", q: "  ada  ", faculty: "SCI", dept: "<script>", ignored: "1" },
    ["faculty", "dept", "programme", "level", "state", "evidence", "flag", "basis", "paid", "q"]);
  assert.deepEqual(f, { faculty: "SCI", level: "400", state: "PENDING_VERIFICATION", evidence: "NO_RESULT", basis: "STUDENT_SELECTED", paid: "PAID", q: "ada" });
  assert.deepEqual(pickFilters({ level: "four", state: ["ANY"] }, ["level", "state"]), {});
  assert.deepEqual(pickFilters({ scope: "ALL", pay: "PART_PAID", reg: "REGISTERED", category: "SPILLOVER", group: "FACULTY" }, ["scope", "pay", "reg", "category", "group"]),
    { scope: "ALL", pay: "PART_PAID", reg: "REGISTERED", category: "SPILLOVER", group: "FACULTY" });
  assert.deepEqual(pickFilters({ category: "BEYOND_DURATION" }, ["category"]), {});
  assert.equal(pageOf("3"), 3);
  assert.equal(pageOf("0"), 1);
  assert.equal(pageOf("abc"), 1);
  assert.equal(pageOf(undefined), 1);
  assert.equal(queryString({ a: "1", b: "", c: null, d: 0, e: undefined }), "a=1&d=0");
  assert.equal(deskHref("2025/2026", "review", { state: "ANY", q: "ada" }, 3), "/summer?session=2025%2F2026&view=review&state=ANY&q=ada&page=3");
  assert.equal(deskHref(null, "students"), "/summer?view=students");
});

test("a decision shows what it holds before it is made", () => {
  const rows = [{ charge_state: "PAID", charge_amount: "5000.00" }, { charge_state: "PAID", charge_amount: 5000 }, { charge_state: "DUE" }];
  const p = decisionPreview(rows);
  assert.equal(p.count, 3);
  assert.equal(p.paid, 2);
  assert.equal(p.amount, 10000);
  assert.equal(p.sentence, "3 courses, 2 paid: ₦10,000 will be held as Summer credit and the entries withdrawn.");
  // a paid row that does not say its amount: the sum is not guessed
  const q = decisionPreview([{ charge_state: "PAID" }, { charge_state: "DUE" }]);
  assert.equal(q.amount, null);
  assert.equal(q.sentence, "2 courses, 1 paid: the fee of each paid course will be held as Summer credit and its entry withdrawn.");
  assert.equal(decisionPreview([{ charge_state: "DUE" }]).sentence, "1 course, 0 paid: nothing has been paid, so nothing is held.");
});

test("the queue's charge columns give the sum a decision holds, the programme fee included when it takes a student's last course (F2)", () => {
  // the queue's rows as registration.summer_queue gives them: charge_amount, programme_fee_paid, courses_standing (numeric columns as strings)
  const row = (student: string, o: { charge_state: string | null; charge_amount?: string | null; programme_fee_paid?: string | null; courses_standing?: number | null }) => ({ student_id: student, ...o });
  // check.sql's S: one paid course (₦5,000) and the paid programme fee (₦50,000); rejecting it credits 5000.00 and 50000.00
  const s = decisionPreview([row("S", { charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 1 })]);
  assert.equal(s.amount, 55000);
  assert.equal(s.programme, 50000);
  assert.equal(s.programmeStudents, 1);
  assert.equal(s.sentence, "1 course, 1 paid: ₦55,000 will be held as Summer credit and the entries withdrawn. That includes the programme fee of 1 student whose last Summer course it takes (₦50,000).");
  // two such students decided together: rejected 2 / 110000.00
  const two = decisionPreview([
    row("S", { charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 1 }),
    row("T", { charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 1 }),
  ]);
  assert.equal(two.amount, 110000);
  assert.equal(two.programmeStudents, 2);
  assert.match(two.sentence, /^2 courses, 2 paid: ₦110,000 will be held as Summer credit and the entries withdrawn\. That includes the programme fee of 2 students/);
  // one course of two that stand: the other stays, so the programme fee stays charged
  const one = decisionPreview([row("U", { charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 2 })]);
  assert.equal(one.amount, 5000);
  assert.equal(one.programme, 0);
  assert.equal(one.sentence, "1 course, 1 paid: ₦5,000 will be held as Summer credit and the entries withdrawn.");
  // both of them ticked: the last goes with the decision, and the programme fee with it (counted once for the student)
  const both = decisionPreview([
    row("U", { charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 2 }),
    row("U", { charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 2 }),
  ]);
  assert.equal(both.amount, 60000);
  assert.equal(both.programmeStudents, 1);
  // an unpaid last course of a student whose programme fee is paid: nothing of the course is held, the programme fee is
  const due = decisionPreview([row("V", { charge_state: "DUE", charge_amount: "5000.00", programme_fee_paid: "50000.00", courses_standing: 1 })]);
  assert.equal(due.paid, 0);
  assert.equal(due.amount, 50000);
  assert.equal(due.sentence, "1 course, 0 paid: ₦50,000 will be held as Summer credit: the programme fee of 1 student whose last Summer course it takes (₦50,000).");
  // no programme fee paid: only the courses' fees, whatever stands
  const none = decisionPreview([row("W", { charge_state: "PAID", charge_amount: "4000.00", programme_fee_paid: null, courses_standing: 1 }), row("W", { charge_state: "DUE", charge_amount: "4000.00", programme_fee_paid: null, courses_standing: 1 })]);
  assert.equal(none.amount, 4000);
  assert.equal(decisionPreview([row("W", { charge_state: "DUE", charge_amount: "4000.00", programme_fee_paid: null, courses_standing: 1 })]).sentence, "1 course, 0 paid: nothing has been paid, so nothing is held.");
  // a decided row (its charge cancelled: none live) neither counts nor holds anything
  assert.equal(decisionPreview([row("X", { charge_state: "CANCELLED", charge_amount: null, programme_fee_paid: null, courses_standing: 0 })]).sentence, "1 course, 0 paid: nothing has been paid, so nothing is held.");
});

test("the decision's preview keeps its words without a figure when a row does not say what it needs (F2)", () => {
  // a paid row without its amount: no sum is guessed; the programme fee that does follow is still said
  const a = decisionPreview([{ student_id: "S", charge_state: "PAID", charge_amount: null, programme_fee_paid: "50000.00", courses_standing: 1 }]);
  assert.equal(a.amount, null);
  assert.equal(a.sentence, "1 course, 1 paid: the fee of each paid course will be held as Summer credit and its entry withdrawn. So is the programme fee of 1 student whose last Summer course it takes (₦50,000).");
  const b = decisionPreview([{ student_id: "S", charge_state: "PAID" }, { student_id: "S", charge_state: "DUE" }]);
  assert.equal(b.sentence, "2 courses, 1 paid: the fee of each paid course will be held as Summer credit and its entry withdrawn.");
  // a paid programme fee without the count of courses that stand: whether it goes is not guessed
  const c = decisionPreview([{ student_id: "S", charge_state: "PAID", charge_amount: "5000.00", programme_fee_paid: "50000.00" }]);
  assert.equal(c.amount, null);
  assert.equal(c.sentence, "1 course, 1 paid: the fee of each paid course will be held as Summer credit and its entry withdrawn. A paid programme fee is held too when the decision takes a student's last Summer course.");
  const d = decisionPreview([{ student_id: "S", charge_state: "DUE", charge_amount: "5000.00", programme_fee_paid: "50000.00" }]);
  assert.equal(d.sentence, "1 course, 0 paid: no course has been paid. A paid programme fee is held too when the decision takes a student's last Summer course.");
});

test("a decision's reason is ten characters or more; the ids go in chunks of 200", () => {
  assert.equal(reasonOk("short"), false);
  assert.equal(reasonOk("   short    "), false);
  assert.equal(reasonOk("ten chars!"), true);
  assert.equal(reasonOk(null), false);
  const ids = Array.from({ length: 450 }, (_, i) => `id${i}`);
  assert.deepEqual(chunk(ids).map((c) => c.length), [200, 200, 50]);
  assert.deepEqual(chunk([], 200), []);
  assert.deepEqual(chunk(["a", "b", "c"], 2), [["a", "b"], ["c"]]);
  assert.equal(DECISION_WORD.NOT_OUTSTANDING.needsReason, true);
  assert.equal(DECISION_WORD.CONFIRM.needsReason, false);
});

test("a download keeps the name the server gave it", () => {
  assert.equal(dispositionName('attachment; filename="summer-2025-2026-selections.csv"', "x.csv"), "summer-2025-2026-selections.csv");
  // through the BFF, as saveFile's fetch reads it (F4): the API's header reaches the script, and the name is the server's, not the fallback
  const through = new Headers(bffResponseHeaders(new Headers({ "content-type": "text/csv", "content-disposition": 'attachment; filename="summer-2025-2026-report.csv"' }), new Headers({ "sec-fetch-mode": "cors" })));
  assert.equal(dispositionName(through.get("content-disposition"), "fallback.csv"), "summer-2025-2026-report.csv");
  assert.equal(dispositionName(null, "x.csv"), "x.csv");
  assert.equal(dispositionName('attachment; filename="../../etc/passwd"', "x.csv"), "..-..-etc-passwd");
});

test("a report row reads the same whichever spelling the API used; a total adds a column", () => {
  const a = reportRow({ group_code: "SCI", group_name: "Science", eligible: "10", eligible_final_year: 6, students_part_paid: 2, fees_paid: "50000.00", credits_open: 0 });
  const b = reportRow({ groupCode: "SCI", groupName: "Science", eligible: 10, eligibleFinalYear: 6, studentsPartPaid: 2, feesPaid: "50000.00", creditsOpen: 0 });
  assert.deepEqual(a, b);
  assert.equal(a.eligible, 10);
  assert.equal(a.studentsPaid, 0);                       // a figure the API left out is nothing
  assert.equal(a.feesPaid, "50000.00");
  const rows = [a, reportRow({ group_code: "ENG", group_name: "Engineering", eligible: 5, fees_paid: "20000", fees_due: "5000" })];
  assert.equal(reportTotal(rows, "eligible"), 15);
  assert.equal(reportTotal(rows, "feesPaid"), 70000);
  assert.equal(reportTotal(rows, "feesDue"), 5000);
  assert.deepEqual(camelKeys({ a_b_c: 1, d: 2 }), { aBC: 1, d: 2 });
  assert.equal(scopeLine({ office: "hod", faculty: "SCI", dept: "CSC" }), "Your office sees the department CSC only.");
  assert.equal(scopeLine({ office: "dean", faculty: "SCI", dept: null }), "Your office sees the faculty SCI only.");
  assert.equal(scopeLine({ office: "academic", faculty: null, dept: null }), null);
  assert.equal(scopeLine(null), null);
});

test("the stored values are the database's: four states, each said once", () => {
  assert.deepEqual([...VERIFICATIONS], ["PENDING_VERIFICATION", "CONFIRMED_OUTSTANDING", "NOT_OUTSTANDING", "REJECTED"]);
  assert.equal(new Set(Object.values(VERIFICATION_WORD)).size, 4);
  assert.equal(registrationStatusWord("OUTSTANDING"), "Not registered");
});

test("the sticky bar's sum is selectionCost, written out", () => {
  assert.equal(selectionFormula(4, ACCOUNT, FEE), "₦50,000 + 4 × ₦5,000 = ₦70,000");
  assert.equal(selectionFormula(4, ACCOUNT, FEE), `${feeFormula({ programme: "50000.00", perCourse: "5000.00", courses: 4 })}`);
  assert.equal(selectionFormula(2, { programmeFeeState: "PAID" }, FEE), "2 × ₦5,000 = ₦10,000");
  assert.equal(selectionFormula(0, ACCOUNT, FEE), "");
  assert.equal(selectionFormula(2, ACCOUNT, null), "");
  for (const n of [1, 2, 7, 30]) assert.equal(selectionFormula(n, { programmeFeeState: "DUE" }, FEE).endsWith(naira(selectionCost(n, { programmeFeeState: "DUE" }, FEE))), true);
});

test("the itemised charges: the server's lines, else the account's and the selected courses", () => {
  const lines = [{ kind: "PROGRAMME" as const, code: null, title: "Programme fee", amount: "50000.00", state: "PAID" }, { kind: "COURSE" as const, code: "CSC 401", title: "x", amount: "5000.00", state: "DUE", verification: "PENDING_VERIFICATION" as const }];
  assert.deepEqual(chargeLines({ summary: { ...SUMMARY, lines } }), lines);
  const built = chargeLines({ account: { ...ACCOUNT, programmeFeeState: "DUE", programmeFee: "50000" }, courses: [course("CSC 401", { status: "SELECTED" }), course("CSC 402", { status: "REGISTERED" }), course("CSC 403")] });
  assert.deepEqual(built.map((l) => [l.kind, l.code, l.state]), [["PROGRAMME", null, "DUE"], ["COURSE", "CSC 401", "DUE"], ["COURSE", "CSC 402", "PAID"]]);
  assert.deepEqual(chargeLines({}), []);
});

test("who a period is open to, as a sentence", () => {
  assert.equal(periodForSentence(["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"]), "Open to final-year and spillover students, and to students the Academic Office authorises.");
  assert.equal(periodForSentence(["FINAL_YEAR"]), "Open to final-year students.");
  assert.equal(periodForSentence(["BEYOND_DURATION"]), "Open to spillover students.");
  assert.equal(periodForSentence(["AUTHORISED"]), "Open to students the Academic Office authorises.");
  assert.equal(periodForSentence(null), "Open to final-year and spillover students, and to students the Academic Office authorises.");
});

test("V779 (B3): EVIDENCE_CHANGED on an authorised selection says the authorisation no longer stands, not that a result changed", () => {
  assert.equal(reviewReasonWord("EVIDENCE_CHANGED", "AUTHORISED"), AUTHORISATION_GONE_WORD);
  assert.equal(AUTHORISATION_GONE_WORD, "The authorisation it rested on no longer stands: decide");
  assert.equal(reviewReasonWord("EVIDENCE_CHANGED", "CARRY_OVER"), "The result this rested on changed");
  assert.equal(reviewReasonWord("EVIDENCE_CHANGED", "STUDENT_SELECTED"), "The result this rested on changed");
  assert.equal(reviewReasonWord("EVIDENCE_CHANGED"), "The result this rested on changed");
  // the other flags read the same whatever the basis
  assert.equal(reviewReasonWord("PASSED_ON_RECORD", "AUTHORISED"), "A pass is on record: decide");
  assert.equal(reviewReasonWord("ENTRY_REMOVED", "AUTHORISED"), "The course was taken off the registration: decide");
  assert.equal(reviewReasonWord(null, "AUTHORISED"), "");
});

test("V779 (B1): a programme fee credit made when the last course went reads as the programme fee, not as a decision on a course", () => {
  // the shape GET /finance/summer-fees gives: source DECISION, the PROGRAMME charge's kind, no course, no selection, the note saying how
  const b1 = { state: "OPEN" as const, settled_note: null, source: "DECISION" as const, note: "Programme fee: no Summer course remains after ZZV 401 was unselected",
    course_code: null, charge_kind: "PROGRAMME" as const, selection_state: null };
  assert.equal(isProgrammeCredit(b1), true);
  assert.equal(creditItemWord(b1), "Programme fee");
  assert.deepEqual(creditSourceWords(b1), { pill: "PROGRAMME FEE", line: "Programme fee: no Summer course remains after ZZV 401 was unselected" });
  // no note: the words still say why it is held; without the kind (an older API) a DECISION credit with no course is the programme fee
  assert.deepEqual(creditSourceWords({ ...b1, note: null }), { pill: "PROGRAMME FEE", line: "No Summer course of the student remains" });
  assert.equal(creditItemWord({ source: "DECISION", course_code: null }), "Programme fee");
  // a course's decision credit and money beyond its charges read as before
  const course = { state: "OPEN" as const, settled_note: null, source: "DECISION" as const, note: "Course ZZV 301 found not outstanding: passed in 2024/2025",
    course_code: "ZZV 301", charge_kind: "COURSE" as const, selection_state: "NOT_OUTSTANDING" as const };
  assert.equal(creditItemWord(course), "ZZV 301");
  assert.deepEqual(creditSourceWords(course), { pill: "DECISION", line: `${verificationWord("NOT_OUTSTANDING")} · Course ZZV 301 found not outstanding: passed in 2024/2025` });
  assert.deepEqual(creditSourceWords({ ...course, selection_state: null, note: null }), { pill: "DECISION", line: "Found not outstanding or rejected" });
  const beyond = { state: "OPEN" as const, settled_note: null, source: "PAYMENT" as const, note: null, course_code: null, charge_kind: null, selection_state: null };
  assert.equal(isProgrammeCredit(beyond), false);
  assert.equal(creditItemWord(beyond), "—");
  assert.deepEqual(creditSourceWords(beyond), { pill: null, line: "Payment beyond its charges" });
});

test("V779 (B2): Reopen is offered on a credit settled by hand, never on one a reinstatement or a payment correction settled", () => {
  assert.equal(creditReopenable({ state: "APPLIED", settled_note: "Applied to the 2026/2027 Summer by voucher AV-0001" }), true);
  assert.equal(creditReopenable({ state: "REFUNDED", settled_note: "Refunded through the refund desk" }), true);
  assert.equal(creditReopenable({ state: "APPLIED", settled_note: null }), true);
  // the note registration.summer_select writes when the student's new selection pays the programme fee again from the credit
  assert.equal(creditReopenable({ state: "APPLIED", settled_note: "Reinstated as the programme fee: the student selected a course again in the same Summer" }), false);
  assert.equal(creditReopenable({ state: "APPLIED", settled_note: "Moved by a payment correction: SWAP-1" }), false);
  assert.equal(creditReopenable({ state: "OPEN", settled_note: null }), false);
});

test("V779 (B4): the examinations desk's edit keeps the Summer's sitting in its place while it is open or released", () => {
  const summer = { semester: 3, kind: "MAIN", stream: "REGULAR" as const, state: "OPEN", sheetsReleasedAt: null };
  assert.equal(isSummerSitting(summer), true);
  assert.equal(isSummerSitting({ semester: "3", kind: "MAIN" }), true);   // the edit form's own string semester; no stream is full-time
  assert.equal(isSummerSitting({ semester: 3, kind: "RESIT", stream: "REGULAR" }), false);
  assert.equal(isSummerSitting({ semester: 3, kind: "MAIN", stream: "CCE" }), false);
  assert.equal(isSummerSitting({ semester: 2, kind: "MAIN", stream: "REGULAR" }), false);
  // the reviewer's repro: the open Summer row switched to RESIT — fixed whatever the form now holds
  assert.equal(summerSittingEdit(summer, { semester: "3", kind: "RESIT", stream: "REGULAR" }), "summer-fixed");
  assert.equal(summerSittingEdit({ ...summer, state: "CLOSED", sheetsReleasedAt: "2027-08-01T10:00:00Z" }, summer), "summer-fixed");
  // a draft Summer row moves freely (the gate holds its opening)
  assert.equal(summerSittingEdit({ ...summer, state: "DRAFT" }, { semester: "3", kind: "RESIT" }), null);
  // an open row of another sitting moved into the Summer's place is warned of; moved elsewhere it is not the Summer's concern
  const second = { semester: 2, kind: "MAIN", stream: "REGULAR" as const, state: "OPEN", sheetsReleasedAt: null };
  assert.equal(summerSittingEdit(second, { semester: "3", kind: "MAIN", stream: "REGULAR" }), "into-summer");
  assert.equal(summerSittingEdit(second, { semester: "1", kind: "MAIN", stream: "REGULAR" }), null);
  assert.equal(summerSittingEdit({ ...second, state: "DRAFT" }, { semester: "3", kind: "MAIN", stream: "REGULAR" }), null);
});
