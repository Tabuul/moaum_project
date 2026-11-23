import { test } from "node:test";
import assert from "node:assert/strict";
import { APPROVE_WORDS, CAUSES, CAUSE_WORDS, CREDIT_STATUS_WORDS, HOLDS, HOLD_WORDS, OVERPAID_DESK_HEADERS, REFUND_ONLY_WORDS, SKIP_TITLES, STATES, STATE_WORDS, SUGGESTED_WORDS,
  actBody, actWords, addUp, asOf, batchWords, canCredit, canRefund, causeWord, commonestHolds, count, creditRows, decideDone, holdRemedy, holdWord, holdWords, isPaidTwice, levelWords,
  levelsDiffer, naira, needsFeeSetupTick, overDecidedWords, overpaidExcelRow, overpaidHref, overpaidMay, paymentsWords, readyRows, refundDone, refundOnlyWord, requestDone, rowsQuery, selectable, selectionFor, skipTitle,
  whyNot, whyNotRequestable, type DecideAnswer, type OverpaidDeskRow, type RefundAnswer, type RequestAnswer } from "./overpaid.ts";

/** an invented student who paid the second semester twice on the portal: ₦66,745 + ₦28,605 + ₦28,605 against ₦95,350 */
const twice: OverpaidDeskRow = {
  student_id: "s1", number: "MOAU/AD/PUB/25/00001", name: "INVENTED, Student", programme_code: "PUB", dept_code: "PUB", faculty_code: "SS", level: 100, cohort_level: 100,
  status: "ACTIVE", due: "95350.00", paid: "123955.00", excess: "28605.00", decided: 0, remaining: "28605.00", cause: "PORTAL_TWICE", bulk: true, repeat_amount: "28605.00",
  n_payments: 3, payments: [{ amount: "66745.00", channel: "Legacy", on: "2026-03-12", kind: "OLD" }, { amount: "28605.00", channel: "Quickteller PayDirect", on: "2026-10-28", kind: "PORTAL" },
    { amount: "28605.00", channel: "Quickteller WEB", on: "2026-10-27", kind: "PORTAL" }],
  holds: [], suggested: "WALLET", state: "UNDECIDED",
};
/** an invented student paid above the fee line: no repeated payment, so decided alone with the fee setup confirmed */
const feeLine: OverpaidDeskRow = { ...twice, student_id: "s2", number: "MOAU/AD/PUB/25/00002", name: "INVENTED, Other", due: "100000", paid: "130000", excess: "30000", remaining: "30000",
  cause: "ABOVE_FEE_LINE", bulk: false, repeat_amount: null, n_payments: 1, payments: [{ amount: "130000", channel: "Legacy", on: "2026-02-02", kind: "OLD" }], suggested: "CHECK_FEE_SETUP" };

test("the five causes, the ten states, the refund-only and the suggested values each have their words", () => {
  assert.deepEqual(CAUSES, ["PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE", "PART_PAYMENTS", "ABOVE_FEE_LINE"]);
  assert.deepEqual(CAUSES.map((c) => CAUSE_WORDS[c]), ["Paid twice on the portal", "Paid on the old portal and the new", "Paid twice on the old portal",
    "Several payments above the charge", "Paid above the fee line"]);
  assert.deepEqual(CAUSES.map(isPaidTwice), [true, true, true, false, false]);
  assert.equal(causeWord("MIXED"), "several causes");
  assert.equal(causeWord("OLD_TWICE"), "Paid twice on the old portal");
  assert.equal(causeWord(null), "");
  assert.deepEqual(STATES, ["OVER_DECIDED", "UNDECIDED", "CREDIT_REQUESTED", "CREDIT_RETURNED", "CREDITED", "REFUND_RAISED", "REFUND_APPROVED", "REFUND_PAID", "REFUND_BY_HAND", "CARRIED"]);
  assert.deepEqual(STATES.map((s) => STATE_WORDS[s][0]), ["Decided above the excess", "Not decided", "Credit requested", "Credit returned for correction", "Credited to the wallet",
    "Refund raised", "Refund approved", "Refund paid", "Refunded on Refunds & Credits", "Carried into the next session"]);
  assert.deepEqual(REFUND_ONLY_WORDS, { DECEASED: "Deceased: refunded to the estate", GRADUATED: "Graduated", WITHDRAWN: "Withdrawn", LEFT: "No longer a student",
    AWARD_APPROVED: "Award approved: no further fees" });
  assert.equal(refundOnlyWord("LEFT"), "No longer a student");
  assert.equal(refundOnlyWord(null), "");
  assert.deepEqual(SUGGESTED_WORDS, { RECOVER: "Recover", WAIT: "Wait for the check", CHECK_FEE_SETUP: "Check the fee setup", REVIEW_PAYMENTS: "Look at the payments",
    REFUND: "Refund", WALLET: "Credit to the wallet" });
  assert.deepEqual(Object.keys(CREDIT_STATUS_WORDS), ["PENDING_BURSAR_APPROVAL", "RETURNED_FOR_CORRECTION", "CREDITED", "REJECTED", "WITHDRAWN"]);
});

test("each of the fourteen holds is shown in the server's own sentence and says what clears it", () => {
  assert.deepEqual(HOLDS, ["PAST_SESSION", "CLOSED_FOR_FEES", "BANK_CHECK", "SAME_PAYMENT", "REVERSAL", "UNDER_REVIEW", "OPEN_CORRECTION", "SEMESTER_NOT_CHARGED",
    "SEMESTER_NOT_STATED", "SPILLOVER_SEMESTER", "LATE_FEE_POSSIBLE", "LATE_FEE_LAPSED", "EXCESS_UNCERTAIN", "MERGED_RECORD"]);
  // finance.overpaid_hold_word, word for word
  assert.deepEqual(HOLD_WORDS, {
    PAST_SESSION: "Not this student's current session — its charge is read as the student stands today",
    CLOSED_FOR_FEES: "Graduated: nothing is charged for this session — refund the payment on Refunds & Credits",
    BANK_CHECK: "Waiting for the bank check",
    SAME_PAYMENT: "One payment recorded twice — archive the duplicate",
    REVERSAL: "A PayDirect reversal is on record",
    UNDER_REVIEW: "A payment is archived for review",
    OPEN_CORRECTION: "A payment correction is open",
    SEMESTER_NOT_CHARGED: "A semester of this session is not yet charged",
    SEMESTER_NOT_STATED: "A semester's fees are not yet stated",
    SPILLOVER_SEMESTER: "Spillover: a semester still to be registered",
    LATE_FEE_POSSIBLE: "A late registration fee may still fall",
    LATE_FEE_LAPSED: "A late payment fee was due — it is not an overpayment",
    EXCESS_UNCERTAIN: "The student's own fee account reads a different excess",
    MERGED_RECORD: "A duplicate record — decide on the record kept",
  });
  for (const h of HOLDS) assert.ok(holdRemedy(h).length > 10, `${h} says what clears it`);
  assert.match(holdRemedy("BANK_CHECK"), /verdict/);
  assert.match(holdRemedy("PAST_SESSION"), /Historical Fees/);
  assert.match(holdRemedy("LATE_FEE_LAPSED"), /Refunds & Credits/);
  assert.equal(holdWord("SOMETHING_NEW"), "SOMETHING_NEW", "a hold the screen does not know shows its code");
  assert.equal(holdRemedy("SOMETHING_NEW"), "");
  assert.equal(holdWords(["BANK_CHECK", "REVERSAL"]), "Waiting for the bank check; A PayDirect reversal is on record");
  assert.equal(holdWords(null), "");
  assert.equal(commonestHolds({ REVERSAL: 1, BANK_CHECK: 79, SAME_PAYMENT: 4 }), "Waiting for the bank check (79) · One payment recorded twice — archive the duplicate (4)");
  assert.equal(commonestHolds({}), "");
  assert.equal(commonestHolds(null), "");
});

test("every skip code has a short title, and an unknown code shows the code", () => {
  assert.deepEqual(SKIP_TITLES, {
    DECIDED: "Already decided", HELD: "Held", REFUND_ONLY: "Refund only", ONE_AT_A_TIME: "One at a time", FEE_SETUP_UNCHECKED: "Fee setup not confirmed",
    REQUEST_OPEN: "Request open", EXCESS_UNCERTAIN: "Figures differ", NOT_OVERPAID: "Not overpaid", LEGACY_CREDIT_SAME_OFFICER: "Your own request",
    LEGACY_CREDIT_STATE: "No longer waiting", LEGACY_CREDIT_EXCESS_CHANGED: "The excess changed", LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: "Bank check", OVERPAID_HELD: "Held",
    OVERPAID_WALLET_REFUSED: "Refund only", OVERPAID_EXCESS_UNCERTAIN: "Figures differ", LEGACY_CREDIT_STUDENT: "Merged record",
  });
  assert.equal(skipTitle("ONE_AT_A_TIME"), "One at a time");
  assert.equal(skipTitle("A_CODE_OF_LATER"), "A_CODE_OF_LATER");
  assert.equal(skipTitle(null), "");
});

test("a row that is not an exact repeat needs the fee-setup confirmation, and is the only one ticked", () => {
  assert.equal(needsFeeSetupTick(twice), false);
  assert.equal(needsFeeSetupTick(feeLine), true);
  const other = { ...twice, student_id: "s3" };
  assert.equal(selectable(twice, []), true);
  assert.equal(selectable(feeLine, []), true);
  assert.equal(selectable(other, [twice]), true, "exact repeats are decided together");
  assert.equal(selectable(feeLine, [twice]), false, "a fee-line row does not join a selection");
  assert.equal(selectable(twice, [feeLine]), false, "and nothing joins a fee-line row");
  assert.equal(selectable(feeLine, [feeLine]), true, "a ticked row may always be unticked");
  assert.equal(selectable({ ...twice, holds: ["BANK_CHECK"] }, []), false, "a held row is never ticked");
  assert.equal(selectable({ ...twice, state: "CREDITED" }, []), false);
});

test("a wallet credit and a refund are for a row not decided and not held; a refund-only student is refunded, never credited", () => {
  assert.equal(canCredit(twice), true);
  assert.equal(canRefund(twice), true);
  const graduate = { ...twice, refund_only: "GRADUATED" as const, suggested: "REFUND" as const };
  assert.equal(canCredit(graduate), false);
  assert.equal(canRefund(graduate), true);
  const held = { ...twice, holds: ["BANK_CHECK", "SAME_PAYMENT"] };
  assert.equal(canCredit(held), false);
  assert.equal(canRefund(held), false);
  assert.equal(canRefund({ ...twice, holds: null }), true, "no hold key is no hold");
  for (const state of ["OVER_DECIDED", "CREDIT_REQUESTED", "CREDIT_RETURNED", "CREDITED", "REFUND_RAISED", "REFUND_APPROVED", "REFUND_PAID", "REFUND_BY_HAND", "CARRIED"] as const) {
    assert.equal(canCredit({ ...twice, state }), false, state);
    assert.equal(canRefund({ ...twice, state }), false, state);
  }
});

test("a row that cannot be acted on says why", () => {
  assert.equal(whyNot(twice), null);
  assert.equal(whyNot({ ...twice, holds: ["BANK_CHECK", "REVERSAL"] }), "Held: Waiting for the bank check; A PayDirect reversal is on record.");
  assert.equal(whyNot({ ...twice, state: "CREDIT_REQUESTED", request: { id: "q", ref: "LOR/2026/000007", amount: 28605, status: "PENDING_BURSAR_APPROVAL" } }),
    "A wallet credit request (LOR/2026/000007) is open for this student.");
  assert.match(whyNot({ ...twice, state: "CREDIT_RETURNED", request: { id: "q", ref: "LOR/2026/000007", amount: 28605, status: "RETURNED_FOR_CORRECTION" } }) ?? "",
    /LOR\/2026\/000007 was returned for correction: its requester withdraws it first/);
  assert.equal(whyNot({ ...twice, state: "CREDITED" }), "Nothing is left to decide: credited to the wallet.");
  assert.equal(whyNot({ ...twice, state: "REFUND_BY_HAND" }), "Nothing is left to decide: refunded on refunds & credits.");
  // decided above the excess: what is owed back is named, and kept back from refunds — nothing here says the wallet pays it by itself
  const over = whyNot({ ...twice, state: "OVER_DECIDED", over_decided: "8605.00" }) ?? "";
  assert.equal(over, "Decided for more than is now paid above the charge: ₦8,605 is owed back to the session's fees. What the wallet still holds of it is kept back from refunds.");
  assert.doesNotMatch(over, /makes it up|automatic/i);
  // a graduate's excess is refunded: the Bursar may tick the row, an officer who only requests credits may not
  const graduate = { ...twice, refund_only: "GRADUATED" as const };
  assert.equal(whyNot(graduate), null);
  assert.match(whyNot(graduate, { credit: true, refund: false }) ?? "", /^Graduated: the excess is refunded, not credited to a wallet/);
  assert.match(whyNot(twice, { credit: false, refund: false }) ?? "", /Your office reads this list/);
});

test("the payments behind a row read in one line, and the level says both where they differ", () => {
  assert.equal(paymentsWords(twice), "3 payments: ₦66,745 · Legacy · 12 Mar 2026; ₦28,605 · Quickteller PayDirect · 28 Oct 2026; ₦28,605 · Quickteller WEB · 27 Oct 2026");
  assert.equal(paymentsWords(feeLine), "1 payment: ₦130,000 · Legacy · 2 Feb 2026");
  assert.equal(paymentsWords({ payments: [], n_payments: 2 }), "2 payments");
  assert.equal(paymentsWords({ payments: null, n_payments: 0 }), "No payment on the list");
  assert.equal(paymentsWords({ payments: [{ amount: 20000.5, channel: null, on: null, kind: "CARRIED" }], n_payments: 0 }), "1 payment: ₦20,000.50 · Carried in");
  assert.equal(levelWords(twice), "100 Level");
  assert.equal(levelWords({ level: 100, cohort_level: 300 }), "Charged at 100 Level · 300 Level by entry year");
  assert.equal(levelWords({ level: 200 }), "200 Level", "no level by entry year on the answer");
  assert.equal(levelWords({ level: null, cohort_level: null }), "—");
  assert.equal(levelsDiffer(twice), false);
  assert.equal(levelsDiffer({ level: 100, cohort_level: 300 }), true);
  assert.equal(levelsDiffer({ level: 100 }), false);
});

test("one act's calls add up: a request and a refund keep the last call's list, an approval joins every call's", () => {
  // a request of 2,300 in three calls of the same batch: each call reads every row again, so the last call's skips are whole
  const req: RequestAnswer[] = [
    { batch: "OCR/2026/000004", requested: 1000, amount: 28605000, skipped: 2, skippedWhy: [{ student_id: "a", code: "HELD", why: "Held: Waiting for the bank check." }, { student_id: "b", code: "REFUND_ONLY", why: "The student is graduated: the excess is refunded, not credited to a wallet." }], remaining: 1300 },
    { batch: "OCR/2026/000004", requested: 1000, amount: 28605000, skipped: 2, skippedWhy: [{ student_id: "a", code: "HELD", why: "Held: Waiting for the bank check." }, { student_id: "b", code: "REFUND_ONLY", why: "The student is graduated: the excess is refunded, not credited to a wallet." }], remaining: 300 },
    { batch: "OCR/2026/000004", requested: 300, amount: 8581500.5, skipped: 1, skippedWhy: [{ student_id: "a", code: "HELD", why: "Held: Waiting for the bank check." }], remaining: 0 },
  ];
  const r = addUp(req);
  assert.equal(r.calls, 3);
  assert.equal(r.batch, "OCR/2026/000004");
  assert.equal(r.requested, 2300);
  assert.equal(r.amount, 65791500.5);
  assert.equal(r.skipped, 1);
  assert.deepEqual(r.skippedWhy.map((s) => s.student_id), ["a"]);
  assert.equal(r.remaining, 0);
  assert.deepEqual([requestDone(req[0]), requestDone(req[1]), requestDone(req[2])], [false, false, true]);
  assert.equal(requestDone({ requested: 0, amount: 0, skipped: 3, remaining: 5 }), true, "a call that requested nothing ends the act");

  // a refund: the refunds add up, what was left is the last call's
  const ref: RefundAnswer[] = [{ refunds: 2000, held: 4, apart: 6, requested: 1, uncertain: 0, unchecked: 0, remaining: 50 }, { refunds: 50, held: 4, apart: 6, requested: 1, uncertain: 2, unchecked: 0, remaining: 0 }];
  const f = addUp(ref);
  assert.deepEqual([f.refunds, f.held, f.apart, f.open, f.uncertain, f.unchecked, f.skipped, f.requested, f.remaining], [2050, 4, 6, 1, 2, 0, 13, 0, 0]);
  assert.deepEqual([refundDone(ref[0]), refundDone(ref[1]), refundDone({ refunds: 0, remaining: 9 })], [false, true, true]);

  // an approval pass: what a call left is marked and not tried again, so each call's are joined
  const dec: DecideAnswer[] = [
    { batch: "OCR/2026/000004", since: "2026-11-16T09:00:00+01:00", credited: 198, amount: 5663790, rejected: 0, returned: 0, skipped: 2, skippedWhy: [{ id: "q1", ref: "LOR/2026/000011", code: "OVERPAID_HELD", why: "The excess on 2025/2026 cannot be decided yet (Waiting for the bank check)" }, { id: "q2", ref: "LOR/2026/000012", code: "LEGACY_CREDIT_EXCESS_CHANGED", why: "The records now show less" }], remaining: 100 },
    { batch: "OCR/2026/000004", since: "2026-11-16T09:00:00+01:00", credited: 99, amount: 2831895, rejected: 0, returned: 0, skipped: 1, skippedWhy: [{ id: "q3", ref: "LOR/2026/000013", code: "LEGACY_CREDIT_SAME_OFFICER", why: "You initiated request LOR/2026/000013; another Bursar officer decides it" }], remaining: 0 },
  ];
  const d = addUp(dec);
  assert.deepEqual([d.credited, d.amount, d.skipped, d.remaining, d.batch], [297, 8495685, 3, 0, "OCR/2026/000004"]);
  assert.deepEqual(d.skippedWhy.map((s) => s.id), ["q1", "q2", "q3"]);
  assert.deepEqual([decideDone(dec[0]), decideDone(dec[1])], [false, true]);
  assert.equal(decideDone({ credited: 0, amount: 0, rejected: 0, returned: 0, skipped: 0, remaining: 40 }), true, "a call that tried nothing ends the pass");
  assert.equal(decideDone({ credited: 0, amount: 0, rejected: 0, returned: 0, skipped: 5, remaining: 40 }), false, "a call that only left requests still goes on");
  const none = addUp([]);
  assert.deepEqual([none.calls, none.batch, none.requested, none.credited, none.refunds, none.skippedWhy.length], [0, null, 0, 0, 0, 0]);
});

test("what an act did is said in one title and one line; an approval says the student applies the credit, never that it pays fees", () => {
  const req = actWords("request", addUp([{ batch: "OCR/2026/000004", requested: 2, amount: 57210, skipped: 1, skippedWhy: [{ student_id: "a", code: "HELD", why: "Held: Waiting for the bank check." }], remaining: 0 }]));
  assert.deepEqual(req, { title: "2 wallet credits of ₦57,210 requested (batch OCR/2026/000004)", text: "Nothing is credited yet: another Bursary officer approves. 1 was left as it was.", tone: "ok" });
  assert.deepEqual(actWords("request", addUp([{ requested: 0, amount: 0, skipped: 3, remaining: 0 }])), { title: "No wallet credit was requested", text: "3 were left as they were.", tone: "info" });
  const ok = actWords("approve", addUp([{ batch: "OCR/2026/000004", since: "2026-11-16T09:00:00+01:00", credited: 1, amount: 28605, rejected: 0, returned: 0, skipped: 0, remaining: 0 }]));
  assert.equal(ok.title, "1 wallet credited with ₦28,605");
  assert.equal(ok.text, "Each student is told. The student applies it to school fees on the Wallet page, or asks there for a refund.");
  assert.doesNotMatch(`${ok.title} ${ok.text} ${APPROVE_WORDS}`, /automatic|within the next|pays them/i);
  assert.match(APPROVE_WORDS, /Wallet page/);
  assert.match(APPROVE_WORDS, /This approval pays no fees\.$/);
  assert.deepEqual(actWords("approve", addUp([{ credited: 0, amount: 0, rejected: 0, returned: 0, skipped: 2, remaining: 0 }])), { title: "No wallet was credited", text: "2 were left as they were.", tone: "info" });
  assert.equal(actWords("reject", addUp([{ credited: 0, amount: 0, rejected: 3, returned: 0, skipped: 0, remaining: 0 }])).title, "3 requests rejected");
  assert.match(actWords("reject", addUp([{ credited: 0, amount: 0, rejected: 3, returned: 0, skipped: 0, remaining: 0 }])).text, /no student was told/);
  assert.equal(actWords("return", addUp([{ credited: 0, amount: 0, rejected: 0, returned: 1, skipped: 0, remaining: 0 }])).title, "1 request returned for correction");
  const ref = actWords("refund", addUp([{ refunds: 2, held: 1, apart: 3, requested: 0, uncertain: 0, unchecked: 1, remaining: 0 }]));
  assert.equal(ref.title, "2 refunds raised on Refunds & Credits");
  assert.equal(ref.text, "Another officer approves each, and it is paid there with the transfer reference and date. Left: 1 held for a check; "
    + "3 not an exact repeated payment (decided one student at a time); 1 waiting for the fee-setup confirmation.");
  assert.deepEqual(actWords("refund", addUp([{ refunds: 0, unchecked: 1, remaining: 0 }])), { title: "No refund was raised", text: "Left: 1 waiting for the fee-setup confirmation.", tone: "info" });
});

test("a row of the desk reads as an Excel row in the order of its headers", () => {
  const row = overpaidExcelRow(twice);
  assert.equal(row.length, OVERPAID_DESK_HEADERS.length);
  assert.equal(OVERPAID_DESK_HEADERS.length, 22);
  assert.deepEqual(row, ["MOAU/AD/PUB/25/00001", "INVENTED, Student", "PUB", "SS", "PUB", 100, 100, 95350, 123955, 28605, 0, 0, 28605, "Paid twice on the portal", "Yes", 28605,
    "3 payments: ₦66,745 · Legacy · 12 Mar 2026; ₦28,605 · Quickteller PayDirect · 28 Oct 2026; ₦28,605 · Quickteller WEB · 27 Oct 2026", "", "Credit to the wallet", "Not decided", "", ""]);
  const decided = overpaidExcelRow({ ...feeLine, cohort_level: 300, state: "REFUND_RAISED", decided: "10000", refunded_by_hand: "4000", remaining: "20000", holds: ["BANK_CHECK"],
    decisions: [{ decision: "REFUND", amount: "6000", reference: "RF-2026-0009", refund_state: "PROPOSED" }, { decision: "CARRY", amount: "500", reference: "MOAUM-CF-X-2025-2026", to_session: "2026/2027" }],
    request: { id: "q", ref: "LOR/2026/000007", amount: "20000", status: "PENDING_BURSAR_APPROVAL", by: "INVENTED, Officer", skip: "Held: Waiting for the bank check." } });
  assert.deepEqual(decided.slice(5, 7), [100, 300]);
  assert.deepEqual(decided.slice(10, 16), [10000, 4000, 20000, "Paid above the fee line", "No", ""]);
  assert.equal(decided[17], "Waiting for the bank check");
  assert.equal(decided[18], "Check the fee setup");
  assert.equal(decided[19], "Refund raised");
  assert.equal(decided[20], "LOR/2026/000007 · Waiting for the Bursar · ₦20,000 · by INVENTED, Officer · Held: Waiting for the bank check.");
  assert.equal(decided[21], "Refund proposed ₦6,000 (RF-2026-0009); Carried into 2026/2027 ₦500 (MOAUM-CF-X-2025-2026)");
  assert.equal(overpaidExcelRow({ ...twice, state: "OVER_DECIDED", over_decided: "8605" })[19], "Decided above the excess: ₦8,605 to recover");
  // a row kept only because a decision stands has no cause
  assert.equal(overpaidExcelRow({ ...twice, cause: null, state: "OVER_DECIDED" })[13], "");
});

test("the desk's address and the list's query carry the session and the filters; money, counts and the list's time read plainly", () => {
  assert.equal(overpaidHref({}), "/finance/overpaid");
  assert.equal(overpaidHref({ session: "2025/2026", state: "UNDECIDED", held: "false", bulk: "true" }), "/finance/overpaid?session=2025%2F2026&state=UNDECIDED&held=false&bulk=true");
  assert.equal(overpaidHref({ session: "2025/2026", tab: "approvals", cause: "", q: null }), "/finance/overpaid?session=2025%2F2026&tab=approvals");
  // the list is asked without the tab; the Excel list is the whole filtered list, never one page of it
  assert.equal(rowsQuery({ session: "2025/2026", tab: "students", cause: "OLD_TWICE", page: "2" }), "session=2025%2F2026&cause=OLD_TWICE&page=2&size=100");
  assert.equal(rowsQuery({ session: "2025/2026", cause: "OLD_TWICE", page: "2" }, 100, true), "session=2025%2F2026&cause=OLD_TWICE&size=100000&export=true");
  assert.equal(naira("28605.00"), "₦28,605");
  assert.equal(naira(20000.5), "₦20,000.50");
  assert.equal(naira(null), "₦0");
  assert.equal(count(1, "student"), "1 student");
  assert.equal(count(2300, "student"), "2,300 students");
  assert.equal(count(2, "batch", "batches"), "2 batches");
  assert.equal(asOf("2026-11-16T08:05:00Z"), "16 Nov 2026, 09:05");
  assert.equal(asOf(null), "");
  assert.equal(asOf("not a time"), "");
});

test("a batch reads in one line, a /credits answer gives its rows, and a decision above the excess is said without a promise", () => {
  assert.equal(batchWords({ batch: "OCR/2026/000004", cause: "OLD_TWICE", requestedBy: "INVENTED, Officer", requestedAt: "2026-11-16T08:05:00Z", count: 34, amount: 2500220, pending: 34, returned: 0,
    skipped: 0, mine: false }), "OCR/2026/000004 · Paid twice on the old portal · 34 students · ₦2,500,220 · requested by INVENTED, Officer, 16 Nov 2026, 09:05");
  assert.equal(batchWords({ batch: "OCR/2026/000005", cause: "MIXED", requestedBy: null, requestedAt: null, count: 1, amount: 28605, pending: 1, returned: 0, skipped: 1, mine: true }),
    "OCR/2026/000005 · several causes · 1 student · ₦28,605 · requested by an officer · 1 left by an earlier approval");
  assert.deepEqual(creditRows([{ id: "q1" }]), [{ id: "q1" }]);
  assert.deepEqual(creditRows({ rows: [{ id: "q2" }] }), [{ id: "q2" }]);
  assert.deepEqual(creditRows(null), []);
  assert.equal(overDecidedWords(0, 0), "");
  assert.equal(overDecidedWords(1, 8605), "1 student was decided for ₦8,605 more than is now paid above their charge. What their wallets still hold of it is kept back from refunds; see the desk.");
  assert.match(overDecidedWords(3, "20000.50"), /^3 students were decided for ₦20,000\.50 more/);
  assert.doesNotMatch(overDecidedWords(3, 20000), /makes it up|automatic/i);
});

test("each office does on the desk what the API lets it: the Bursary decides, the Students Account Officer requests, the rest read", () => {
  assert.deepEqual(overpaidMay("bursar"), { credit: true, refund: true, decide: true, refresh: true });
  assert.deepEqual(overpaidMay("super"), { credit: true, refund: true, decide: true, refresh: true });
  assert.deepEqual(overpaidMay("studentaccounts"), { credit: true, refund: false, decide: false, refresh: true });
  for (const office of ["audit", "registrar", "ict", "vc", "", null, undefined]) assert.deepEqual(overpaidMay(office), { credit: false, refund: false, decide: false, refresh: false }, String(office));
});

test("a selection comes to the rows that may be credited or refunded; a refund-only student is left out of a credit and named", () => {
  const other = { ...twice, student_id: "s3", remaining: "10000.50" };
  const graduate = { ...twice, student_id: "s4", refund_only: "GRADUATED" as const, remaining: "5000" };
  const held = { ...twice, student_id: "s5", holds: ["BANK_CHECK"] };
  const credit = selectionFor("credit", [twice, other, graduate, held]);
  assert.deepEqual([credit.ids, credit.count, credit.amount, credit.leftOut.map((r) => r.student_id), credit.needsTick], [["s1", "s3"], 2, 38605.5, ["s4"], false]);
  const refund = selectionFor("refund", [twice, other, graduate, held]);
  assert.deepEqual([refund.ids, refund.count, refund.amount, refund.leftOut.length], [["s1", "s3", "s4"], 3, 43605.5, 0]);
  // the tick for the fee setup is asked of one row that is not an exact repeat, never of several
  assert.equal(selectionFor("credit", [feeLine]).needsTick, true);
  assert.equal(selectionFor("credit", [twice]).needsTick, false);
  assert.equal(selectionFor("credit", []).count, 0);
  // select all ready: an exact repeat, not decided, not held
  assert.deepEqual(readyRows([twice, feeLine, held, graduate, { ...twice, student_id: "s6", state: "CREDITED" as const }]).map((r) => r.student_id), ["s1", "s4"]);
});

test("a request and a refund are sent as the officer confirmed them", () => {
  assert.deepEqual(actBody({ session: "2025/2026", students: ["s1", "s2"], reason: "  Paid twice, checked.  ", batch: null }),
    { session: "2025/2026", students: ["s1", "s2"], reason: "Paid twice, checked.", confirmed: true });
  // a paid-twice cause as a whole names no student; the batch the first answer gave goes back with the next call
  assert.deepEqual(actBody({ session: "2025/2026", cause: "OLD_TWICE", reason: "Paid twice, checked.", batch: "OCR/2026/000004", limit: 1000 }),
    { session: "2025/2026", cause: "OLD_TWICE", reason: "Paid twice, checked.", confirmed: true, batch: "OCR/2026/000004", limit: 1000 });
  // named students win over a cause, and the fee-setup confirmation is sent only when it was given
  assert.deepEqual(actBody({ session: "2025/2026", students: ["s2"], cause: "ABOVE_FEE_LINE", reason: "Fee setup looked at.", feeSetupChecked: true }),
    { session: "2025/2026", students: ["s2"], reason: "Fee setup looked at.", confirmed: true, feeSetupChecked: true });
  assert.equal("feeSetupChecked" in actBody({ session: "2025/2026", students: ["s2"], reason: "Fee setup looked at.", feeSetupChecked: false }), false);
});

test("a student's session says why it cannot be requested for a wallet credit", () => {
  assert.equal(whyNotRequestable(null), null);
  assert.equal(whyNotRequestable({ holds: [], refund_only: null }), null);
  assert.equal(whyNotRequestable({ holds: ["BANK_CHECK", "REVERSAL"] }),
    "Held: Waiting for the bank check; A PayDirect reversal is on record. The Overpaid school fees desk says what each one waits for.");
  assert.equal(whyNotRequestable({ refund_only: "GRADUATED" }),
    "Graduated: the excess is refunded, not credited to a wallet. Raise a refund on the Overpaid school fees desk.");
});
