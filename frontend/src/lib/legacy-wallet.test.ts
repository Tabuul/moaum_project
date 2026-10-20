import { test } from "node:test";
import assert from "node:assert/strict";
import { REPORT_HEADERS, balanceWords, legacyWalletHref, num, reportRows, type LegacyWalletRow } from "./legacy-wallet.ts";

const row = (o: Partial<LegacyWalletRow> = {}): LegacyWalletRow => ({
  id: "1", student_id: "s", student: "Doe, John", matric_no: "MOAU/SC/MCB/24/75807", jamb_reg_no: "202410001AA", student_status: "ACTIVE", programme: "B.Sc. Microbiology",
  dept_code: "MCB", department: "Microbiology", faculty_code: "SC", faculty: "Science",
  topups: "150000.00", topup_count: 2, used: "50000.00", used_count: 1, first_topup_at: "2025-01-10", last_topup_at: "2025-03-01", last_topup_ref: "MOAUM-LEG-X-EWALLETTOPUP",
  session: "2024/2025", stated_topups: null, stated_used: null, stated_refunds: null, stated_reversed: null, stated_balance: null, stated_source: null, stated_note: null,
  stated_by: null, stated_at: null, available: "100000.00", status: "POSTED", reason_code: null, reason: null, computed_at: "2026-10-20",
  verified_by: "Officer, One", verified_office: "studentaccounts", verified_at: "2026-10-20", verify_note: null, posted_by: "Officer, Two", posted_office: "bursar",
  posted_at: "2026-10-20", batch_ref: "LEGACY-WALLET/2026/000001", decided_by: null, decided_at: null, decision_note: null,
  wallet_reference: "EWALLET-LEG-ABC", applied: "100000.00", refunded: 0, remaining: "0.00", ...o,
});

test("the report follows its headers, S/N first, the migrated balance only once posted", () => {
  const rows = reportRows([row(), row({ status: "COMPUTED", wallet_reference: null, applied: 0, remaining: null, batch_ref: null, posted_by: null })]);
  assert.equal(rows[0].length, REPORT_HEADERS.length);
  assert.deepEqual(rows[0].slice(0, 11), [1, "Doe, John", "MOAU/SC/MCB/24/75807", "202410001AA", "EWALLET-LEG-ABC", 150000, 50000, 0, 100000, 100000, 0]);
  assert.equal(rows[0][11], "Posted to the wallet");
  assert.equal(rows[0][14], "LEGACY-WALLET/2026/000001");
  // not yet posted: nothing migrated, no current balance, the last top-up's reference stands in
  assert.equal(rows[1][4], "MOAUM-LEG-X-EWALLETTOPUP");
  assert.equal(rows[1][8], 0);
  assert.equal(rows[1][10], "");
  assert.equal(rows[1][11], "Computed: to verify");
});

test("the balance is explained from the figures, or from the old portal's statement where one governs", () => {
  assert.equal(balanceWords(row()), "Topped up ₦150,000.00 (2) − paid from it ₦50,000.00 (1)");
  assert.equal(balanceWords(row({ stated_balance: "120000", stated_source: "old portal wallet page" })), "As the old portal states it (old portal wallet page): ₦120,000.00");
  assert.equal(num("1234.567"), 1234.57);
});

test("the desk's address names only the filters chosen", () => {
  assert.equal(legacyWalletHref({ status: "", q: "" }), "/finance/legacy-wallet");
  assert.equal(legacyWalletHref({ status: "VERIFIED", fac: "SC" }), "/finance/legacy-wallet?status=VERIFIED&fac=SC");
});
