import { test } from "node:test";
import assert from "node:assert/strict";
import { DOUBLE_HEADERS, MISLABELLED_HEADERS, RECON_HEADERS, doubleRow, mislabelledRow, reconRow, withdrawDone, type DoubleRow, type ReconRow } from "./old-fees.ts";

test("a reconciliation row reads in the order of its headers, amounts as numbers to the kobo", () => {
  const r: ReconRow = {
    student_id: "s", number: "MOAU/LAW/24/74545", name: "DOE, Jane", programme_code: "LAW", faculty_code: "LW", level: 200,
    due: "158150.00", paid: "120000.004", paid_old_s1: "110704", paid_old_s2: "9296", paid_old_session: 0, paid_payment_history: null as unknown as number,
    paid_portal: "0", old_payments: 3, difference: "-38150.00", state: "UNDER",
  };
  const row = reconRow(r);
  assert.equal(row.length, RECON_HEADERS.length);
  assert.deepEqual(row, ["MOAU/LAW/24/74545", "DOE, Jane", "LAW", "LW", 200, 158150, 120000, 110704, 9296, 0, 0, 0, 3, -38150, "Paid less than due"]);
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
