import { test } from "node:test";
import assert from "node:assert/strict";
import { DOUBLE_HEADERS, LEFT_HEADERS, MISLABELLED_HEADERS, OVERPAID_HEADERS, RECON_HEADERS, decideDone, doubleRow, leftRow, mislabelledRow, overpaidRow, reconRow, withdrawDone, type DoubleRow, type LeftRow, type OverpaidRow, type ReconRow } from "./old-fees.ts";

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
  assert.deepEqual(row, ["MOAU/AD/PUB/25/00001", "INVENTED, Student", "PUB", "SS", 200, 100000, 130000, 30000, "Not decided", "", "", "", "", "Yes"]);
  assert.deepEqual(overpaidRow({ ...o, decision: "CARRY", decided: "30000", reference: "MOAUM-CF-X-2025-2026", to_session: "2026/2027", decided_at: "2026-10-17 09:12:00+01" }).slice(8),
    ["Carried into the next session", "2026/2027", "MOAUM-CF-X-2025-2026", "", "2026-10-17", "Yes"]);
  assert.equal(overpaidRow({ ...o, old_portal: false })[13], "No");
  assert.equal(overpaidRow({ ...o, decision: "REFUND", refund_state: "PROPOSED" })[11], "PROPOSED");
});

test("deciding stops when nothing is left or nothing more can be decided", () => {
  assert.equal(decideDone({ carried: 2000, refunds: 0, remaining: 300 }), false);
  assert.equal(decideDone({ carried: 300, refunds: 0, remaining: 0 }), true);
  assert.equal(decideDone({ carried: 0, refunds: 0, remaining: 4 }), true);
});
