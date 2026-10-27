import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ARCHIVE_HEAD, EMPTY_FILTERS, archiveLine, archiveQuery, fileRefusal, isOpen, proposalReadiness, readArchiveFilters, refusalParts, underReviewNote,
  verificationWords, type ArchiveRow, type EvidenceItem, type MyArchive,
} from "./payment-archive.ts";

const naira = (n: number) => `₦${n.toLocaleString("en-GB", { minimumFractionDigits: 2 })}`;

test("the verification status follows the archive's state", () => {
  assert.equal(verificationWords("ARCHIVED")[1], "NOT YET VERIFIED");
  assert.equal(verificationWords("UNDER_REVIEW")[1], "NOT YET VERIFIED");
  assert.equal(verificationWords("RETURNED")[1], "NOT YET VERIFIED");
  assert.equal(verificationWords("PENDING_BURSAR_APPROVAL")[1], "VERIFIED — READY FOR RECONCILIATION");
  assert.equal(verificationWords("RECONCILED")[1], "RECONCILED");
  assert.equal(isOpen("PENDING_BURSAR_APPROVAL"), true);
  assert.equal(isOpen("DUPLICATE_CONFIRMED"), false);
});

test("a proposal waits for the evidence it needs: a name alone never moves a payment, and the same amount and day prove no duplicate", () => {
  const name: EvidenceItem = { kind: "NAME", label: "Name", strength: "SUPPORTING", value: "Ada" };
  const payer: EvidenceItem = { kind: "GATEWAY_PAYER", label: "Payer", strength: "STRONG", value: "MOAU/1" };
  assert.match(proposalReadiness("REALLOCATE", [name], [], false) ?? "", /strong evidence/);
  assert.equal(proposalReadiness("REALLOCATE", [name, payer], [], false), null);
  assert.match(proposalReadiness("DUPLICATE", [], [], true) ?? "", /no proof/);
  assert.equal(proposalReadiness("DUPLICATE", [], ["SAME_GATEWAY_REFERENCE"], true), null);
  assert.match(proposalReadiness("DUPLICATE", [payer], [], false) ?? "", /names none/);
  assert.match(proposalReadiness("RESTORE", [], [], false) ?? "", /genuine/);
  assert.match(proposalReadiness("NOT_RECEIVED", [name], [], false) ?? "", /strong evidence/);
});

test("the filters read only what is well formed, and the query carries only what is set", () => {
  const f = readArchiveFilters({ state: "open", q: " PAR/2026/000001 ", session: "2025/2026", semester: "4", reason: "wrong_student", amount: "1e5", source: "x" });
  assert.equal(f.state, "OPEN");
  assert.equal(f.q, "PAR/2026/000001");
  assert.equal(f.semester, "");
  assert.equal(f.reason, "WRONG_STUDENT");
  assert.equal(f.amount, "");
  assert.equal(f.source, "");
  assert.equal(archiveQuery({ ...EMPTY_FILTERS, state: "OPEN", session: "2025/2026" }, { page: 2, all: false }), "state=OPEN&session=2025%2F2026&page=2");
});

test("a refusal is read as its code and its words", () => {
  assert.deepEqual(refusalParts("PAR_ALREADY: the payment is already in the payment archive"), { code: "PAR_ALREADY", words: "The payment is already in the payment archive" });
});

test("a row of the report puts every column in its place", () => {
  const r = {
    archive_ref: "PAR/2026/000001", reference: "MOAUM-FEE-1", legacy_payref: null, name: "ADA, Eze", number: "MOAU/1", jamb_reg_no: null, current_number: "MOAU/1",
    purpose: "School fees 2025/2026", session: "2025/2026", semester: 1, channel: "Interswitch", amount: 100000, payment_confirmed_at: "2026-10-01T09:00:00Z",
    reason: "Wrong student", source: "DESK", state: "PENDING_BURSAR_APPROVAL", outcome: "REALLOCATE", owner_number: "MOAU/2", related_reference: null,
    archived_by: "Officer", archived_at: "2026-10-20T09:00:00Z", decided_by: null, settled_at: null,
  } as unknown as ArchiveRow;
  const line = archiveLine(r, (iso) => (iso ? iso.slice(0, 10) : ""));
  assert.equal(line.length, ARCHIVE_HEAD.length);
  assert.equal(line[11], 100000);
  assert.equal(line[16], "VERIFIED — READY FOR RECONCILIATION");
  assert.equal(line[17], "Reallocate to its true owner");
});

test("the student is told what is under review, apart from the verified payments", () => {
  const row = (state: MyArchive["state"], counts: boolean, amount: number) => ({ archive_ref: "PAR", reference: "R", amount, purpose: "School fees", session: "2025/2026",
    paid_at: "2026-10-01", state, archived_at: "2026-10-02", counts }) as MyArchive;
  assert.equal(underReviewNote([row("RECONCILED", true, 5)], naira), null);
  assert.equal(underReviewNote([row("UNDER_REVIEW", false, 100000)], naira),
    "₦100,000.00 payment is currently under verification and is not included in your verified payment balance.");
  assert.match(underReviewNote([row("ARCHIVED", false, 1000), row("RETURNED", false, 2000)], naira) ?? "", /^2 payments of ₦3,000.00/);
});

test("an evidence file is a PDF, JPEG or PNG of at most 5 MB", () => {
  assert.equal(fileRefusal({ type: "image/png", size: 10 }), null);
  assert.match(fileRefusal({ type: "text/plain", size: 10 }) ?? "", /PDF/);
  assert.match(fileRefusal({ type: "application/pdf", size: 6 * 1024 * 1024 }) ?? "", /5 MB/);
});
