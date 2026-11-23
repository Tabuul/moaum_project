import { test } from "node:test";
import assert from "node:assert/strict";
import { DECISION, DOUBLE_HEADERS, LEFT_HEADERS, MISLABELLED_HEADERS, OVERPAID_HEADERS, RECON_HEADERS, decideDone, decideLeft, doubleRow, leftRow, mislabelledRow, overpaidRow, reconRow, undecided, withdrawDone, type DoubleRow, type LeftRow, type OverpaidRow, type ReconRow } from "./old-fees.ts";

test("a reconciliation row reads in the order of its headers, amounts as numbers to the kobo", () => {
  const r: ReconRow = {
    student_id: "s", number: "MOAU/LAW/24/74545", name: "DOE, Jane", programme_code: "LAW", faculty_code: "LW", level: 200,
    due: "158150.00", paid: "120000.004", paid_old_s1: "110704", paid_old_s2: "9296", paid_old_session: 0, paid_payment_history: null as unknown as number,
    paid_portal: "0", old_payments: 3, difference: "-38150.00", state: "UNDER",
  };
  const row = reconRow(r);
  assert.equal(row.length, RECON_HEADERS.length);
  assert.deepEqual(row, ["MOAU/LAW/24/74545", "DOE, Jane", "LAW", "LW", 200, 158150, 120000, 110704, 9296, 0, 0, 0, 3, -38150, "Paid less than due", 0, 0, ""]);
  const settled = reconRow({ ...r, paid: "178150", difference: "20000", state: "OVER_SETTLED", carried_in: "5000", settled: "20000", decision: "CARRY" });
  assert.deepEqual(settled.slice(14), ["Overpaid: carried or refunded", 5000, 20000, "Carried into the next session"]);
});

test("a payment on record twice says why and what was kept", () => {
  const d: DoubleRow = {
    double_reference: "MOAUM-LEG-X-2025-2026", double_kind: "WHOLE_SESSION", kept_reference: "MOAUM-LEG-X-2025-2026-S1", kept_kind: "OLD_FEES_HISTORY",
    number: "MOAU/SS/LIS/24/77225", name: "ROE, Ann", session: "2025/2026", amount: "36555.80", paid_on: "2026-08-13",
    purpose: "School fees (legacy)", kept_purpose: "School fees (legacy) · semester 2", linked: null,
  };
  const row = doubleRow(d);
  assert.equal(row.length, DOUBLE_HEADERS.length);
  assert.equal(row[4], 36555.8);
  assert.match(String(row[7]), /semester record keeps the payment number/);
  assert.equal(row[10], "");
  assert.equal(doubleRow({ ...d, double_kind: "PAYMENT_HISTORY", linked: "REFUND" })[10], "A refund names it");
});

test("the withdrawal stops when nothing is left or nothing more can go", () => {
  assert.equal(withdrawDone({ withdrawn: 5000, remaining: 1200 }), false);
  assert.equal(withdrawDone({ withdrawn: 1200, remaining: 0 }), true);
  assert.equal(withdrawDone({ withdrawn: 0, remaining: 40 }), true, "only linked ones are left");
});

test("a record under a code says what it is and what putting it right does", () => {
  const row = mislabelledRow({
    reference: "MOAUM-LEG-MOAUADPUB2500001-2025-2026-S1-10048", number: "MOAU/AD/PUB/25/00001", name: "DOE, Jane", session: "2025/2026",
    amount: "156338.00", paid_on: "2026-02-16", stored_purpose: "10048 (legacy) · semester 1", item: "SCHOOL FEES",
    target_reference: "MOAUM-LEG-MOAUADPUB2500001-2025-2026-S1", target_purpose: "School fees (legacy) · semester 1", action: "RENAME",
  });
  assert.equal(row.length, MISLABELLED_HEADERS.length);
  assert.deepEqual(row.slice(4, 11), [156338, "10048 (legacy) · semester 1", "MOAUM-LEG-MOAUADPUB2500001-2025-2026-S1-10048", "SCHOOL FEES",
    "School fees (legacy) · semester 1", "MOAUM-LEG-MOAUADPUB2500001-2025-2026-S1", "Recorded as what it is"]);
});

test("a record the retired screen made, matched by nothing, says the day its number carries and what it counts as", () => {
  const l: LeftRow = { reference: "PR202604040000005", number: "MOAU/AD/PUB/25/00001", name: "INVENTED, Student", session: "2025/2026",
    amount: "4500.00", paid_on: "2026-10-16", number_day: "2026-04-04", purpose: "GST fee 2025/2026", counts_as: "GST" };
  const row = leftRow(l);
  assert.equal(row.length, LEFT_HEADERS.length);
  assert.deepEqual(row, ["MOAU/AD/PUB/25/00001", "INVENTED, Student", "2025/2026", "2026-10-16", "2026-04-04", 4500, "PR202604040000005", "GST fee 2025/2026", "The GST fee"]);
  assert.equal(leftRow({ ...l, number_day: null, counts_as: "SCHOOL_FEES" })[4], "");
  assert.equal(leftRow({ ...l, counts_as: "SCHOOL_FEES" })[8], "School fees");
});

test("an overpaid student says the excess and what was decided, or that nothing was", () => {
  const o: OverpaidRow = { student_id: "s", number: "MOAU/AD/PUB/25/00001", name: "INVENTED, Student", programme_code: "PUB", faculty_code: "SS", level: 200,
    due: "100000.00", paid: "130000.00", excess: "30000.00", decision: null, decided: null, reference: null, to_session: null, decided_at: null, refund_state: null,
    old_portal: true };
  const row = overpaidRow(o);
  assert.equal(row.length, OVERPAID_HEADERS.length);
  assert.deepEqual(row, ["MOAU/AD/PUB/25/00001", "INVENTED, Student", "PUB", "SS", 200, 100000, 130000, 30000, "Not decided", "", "", "", "", "Yes", ""]);
  assert.deepEqual(overpaidRow({ ...o, decision: "CARRY", decided: "30000", reference: "MOAUM-CF-X-2025-2026", to_session: "2026/2027", decided_at: "2026-10-17 09:12:00+01" }).slice(8),
    ["Carried into the next session", "2026/2027", "MOAUM-CF-X-2025-2026", "", "2026-10-17", "Yes", ""]);
  assert.equal(overpaidRow({ ...o, old_portal: false })[13], "No");
  assert.equal(overpaidRow({ ...o, decision: "REFUND", refund_state: "PROPOSED" })[11], "PROPOSED");
  // V561: a possible bank double charge waiting for the Bursary's check
  assert.equal(overpaidRow({ ...o, double_charge: "CHECK_WITH_BANK" })[14], "Check with the bank");
});

test("a wallet credit is named as one, and a decided student who paid again still has something to decide", () => {
  // V781: a WALLET decision (V625) was read as a refund; the old panel's Excel list keeps its fifteen columns
  assert.equal(DECISION.WALLET, "Credited to the wallet");
  assert.deepEqual(OVERPAID_HEADERS, ["Matric/admission no.", "Name", "Programme", "Faculty", "Level", "Due by the fee setup (₦)", "Paid (₦)", "Excess (₦)", "Decision", "Into session",
    "Reference", "Refund state", "Decided on", "Old-portal payment among them", "Possible bank double charge"]);
  const o: OverpaidRow = { student_id: "s", number: "MOAU/AD/PUB/25/00001", name: "INVENTED, Student", programme_code: "PUB", faculty_code: "SS", level: 100,
    due: "95350.00", paid: "123955.00", excess: "28605.00", decision: "WALLET", decided: "28605.00", reference: "LOR/2026/000007", to_session: null, decided_at: "2026-11-16 09:12:00+01",
    refund_state: null, old_portal: true, remaining: 0, decision_count: 1, refunded_by_hand: 0 };
  assert.deepEqual(overpaidRow(o).slice(8, 13), ["Credited to the wallet", "", "LOR/2026/000007", "", "2026-11-16"]);
  assert.equal(reconRow({ student_id: "s", number: "N", name: "INVENTED, Student", programme_code: "PUB", faculty_code: "SS", level: 100, due: 1, paid: 2, paid_old_s1: 0, paid_old_s2: 0,
    paid_old_session: 0, paid_payment_history: 0, paid_portal: 2, old_payments: 0, difference: 1, state: "OVER_SETTLED", decision: "WALLET, CARRY" })[17], "Credited to the wallet, Carried into the next session");
  // what is left is the test, from one naira: a third payment after the credit leaves more to decide
  assert.equal(undecided(o), false);
  const again = { ...o, paid: "152560.00", excess: "57210.00", remaining: "28605.00" };
  assert.equal(undecided(again), true);
  assert.equal(overpaidRow(again)[8], "Credited to the wallet; ₦28,605 not yet decided");
  assert.equal(undecided({ decision: null, remaining: "0.40" }), false, "under one naira is nothing");
  assert.equal(undecided({ decision: null, remaining: "30000" }), true);
  // an answer without the figure is read as before: by whether a decision stands
  assert.equal(undecided({ decision: null }), true);
  assert.equal(undecided({ decision: "CARRY" }), false);
});

test("deciding stops when nothing is left or nothing more can be decided", () => {
  assert.equal(decideDone({ carried: 2000, refunds: 0, remaining: 300 }), false);
  assert.equal(decideDone({ carried: 300, refunds: 0, remaining: 0 }), true);
  assert.equal(decideDone({ carried: 0, refunds: 0, remaining: 4 }), true);
});

test("a bulk decision says why each student was left, and a hold is not always the bank's", () => {
  const none = { apart: 0, requested: 0, refundOnly: 0, uncertain: 0, unchecked: 0, held: 0 };
  assert.deepEqual(decideLeft(none, "CARRY", false), []);
  // every hold counts as held (a spillover semester, a past session, a late fee), and the line does not blame the bank alone
  const held = decideLeft({ ...none, held: 179 }, "REFUND", false);
  assert.equal(held.length, 1);
  assert.match(held[0], /^179 students were left: held/);
  assert.match(held[0], /spillover semester/);
  assert.match(held[0], /Overpaid school fees desk says what each one waits for/);
  assert.doesNotMatch(held[0], /checked with the bank/);
  assert.match(decideLeft({ ...none, held: 1 }, "REFUND", true)[0], /^1 student was left: held/);
  // carried: a refund-only student is left, refunded never carried; refunded: not mentioned
  assert.equal(decideLeft({ ...none, refundOnly: 2 }, "CARRY", false).length, 1);
  assert.deepEqual(decideLeft({ ...none, refundOnly: 2 }, "REFUND", false), []);
  assert.deepEqual(decideLeft({ ...none, unchecked: 3 }, "CARRY", true), ["Tick the confirmation first."]);
});
