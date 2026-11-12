import { test } from "node:test";
import assert from "node:assert/strict";
import {
  categoryWord, courseReasonWord, failedInWord, naira, nextStep, notEligibleWord, paymentStateWords, periodWords, selectionCost, semesterWord, sessionPath,
  type MySummer, type SummerPeriod,
} from "./summer.ts";

const PERIOD: SummerPeriod = {
  session: "2025/2026", state: "OPEN", registration_opens: "2026-07-01", registration_closes: "2026-07-21", exams_from: "2026-08-10", exams_to: "2026-08-20",
  results_due: "2026-09-01", categories: ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"], programmes: null, levels: null, open_now: true,
};
const FEE = { fee_id: "f1", programme_fee: "50000.00", course_fee: "5000.00" };
const ACCOUNT = { session: "2025/2026", programmeFee: null, programmeFeeState: null, coursesSelected: 0, coursesPaid: 0, courseFeesDue: "0", programmeFeeDue: "0", due: "0", paid: "0", openReference: null, registration: null };

test("the programme fee is charged once, with the first course; each course adds its fee", () => {
  assert.equal(selectionCost(2, ACCOUNT, FEE), 60000);
  assert.equal(selectionCost(1, { programmeFeeState: "PAID" }, FEE), 5000);
  assert.equal(selectionCost(3, { programmeFeeState: "DUE" }, FEE), 15000);
  assert.equal(selectionCost(0, ACCOUNT, FEE), 0);
  assert.equal(selectionCost(2, ACCOUNT, null), 0);
});

test("a course says where it was failed, or that the Academic Office named it", () => {
  assert.equal(failedInWord({ original_session: "2024/2025", original_semester: 2, basis: "CARRY_OVER" }), "Second semester, 2024/2025");
  assert.equal(failedInWord({ original_session: null, original_semester: null, basis: "AUTHORISED" }), "Named by the Academic Office");
  assert.equal(semesterWord(3), "Summer");
  assert.equal(courseReasonWord("RESULT_AWAITED"), "Its result this session is awaited");
});

test("the student's next step follows the server's account", () => {
  const base: MySummer = { session: "2025/2026", period: PERIOD, eligibility: { eligible: true, category: "FINAL_YEAR", outstanding: 3, reason: null }, courses: [
    { course_code: "CSC 401", title: "x", units: 3, course_semester: 1, both_semesters: false, original_session: "2024/2025", original_semester: 1, attempts: 1, basis: "CARRY_OVER", status: "OUTSTANDING", selectable: true, reason: null, course_fee: "5000" },
  ], fee: FEE, account: ACCOUNT };
  assert.equal(nextStep(base), "Select your outstanding courses, then pay.");
  assert.equal(nextStep({ ...base, account: { ...ACCOUNT, due: "60000" } }), "Pay ₦60,000 to register the courses you selected.");
  assert.equal(nextStep({ ...base, fee: null }), "The Bursary has not published the Summer Semester fees yet.");
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, state: "CLOSED" } }), "Registration is closed.");
  assert.equal(nextStep({ ...base, eligibility: { eligible: false, category: null, outstanding: 0, reason: "NOT_FINAL_OR_SPILLOVER" } }),
    notEligibleWord("NOT_FINAL_OR_SPILLOVER"));
  // after the close nothing more is taken: an unpaid selection is removed (V739)
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, state: "CLOSED" }, account: { ...ACCOUNT, due: "5000" } }),
    "Registration is closed: remove the course you selected and did not pay; nothing more is taken.");
  // an open Summer before its window says when it opens (V739)
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, registration_opens: "2026-12-01" } }, "2026-11-12"), "Registration opens on 1 December 2026.");
  assert.equal(nextStep({ ...base, period: { ...PERIOD, open_now: false, registration_closes: "2026-07-21" } }, "2026-11-12"), "Registration is closed.");
});

test("words for the desk", () => {
  assert.equal(categoryWord("BEYOND_DURATION"), "Beyond the programme's length");
  assert.deepEqual(paymentStateWords("PART_PAID"), ["Part paid", "warn"]);
  assert.deepEqual(periodWords({ ...PERIOD, open_now: false }), ["Open — outside its dates", "warn"]);
  assert.deepEqual(periodWords(null), ["Not set", "grey"]);
  assert.equal(naira("50000.00"), "₦50,000");
  assert.equal(sessionPath("2025/2026"), "2025/2026");
});
