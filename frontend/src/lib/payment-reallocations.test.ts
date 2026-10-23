import { test } from "node:test";
import assert from "node:assert/strict";
import {
  EMPTY_REALLOC_FILTERS, evidenceRefusal, periodSemesters, periodWords, readReallocFilters, reallocLine, reallocQuery, reasonOk, refusalParts, REALLOC_HEAD,
  type ReallocRow,
} from "./payment-reallocations.ts";

test("a refusal is read as its code and its words", () => {
  assert.deepEqual(refusalParts("REALLOC_GST_SHORT: the GST fee is paid in one"), { code: "REALLOC_GST_SHORT", words: "The GST fee is paid in one" });
  assert.deepEqual(refusalParts("no code here"), { code: "", words: "no code here" });
});

test("a reason says why, not a single word", () => {
  assert.equal(reasonOk("wrong"), false);
  assert.equal(reasonOk("reallocation"), false);
  assert.equal(reasonOk("short but real"), false);
  assert.equal(reasonOk("The student chose transfer instead of school fees"), true);
});

test("the filters read only what is well formed, and the query carries only what is set", () => {
  assert.deepEqual(readReallocFilters({ status: "completed", session: "2026/2027", purpose: "school_fees", q: " REA/2026/000001 ", from: "2026-10-01", to: "nope" }),
    { status: "COMPLETED", q: "REA/2026/000001", session: "2026/2027", purpose: "SCHOOL_FEES", from: "2026-10-01", to: "" });
  assert.deepEqual(readReallocFilters({ status: "MOVED", session: "2026", purpose: "1x" }), EMPTY_REALLOC_FILTERS);
  assert.equal(reallocQuery({ ...EMPTY_REALLOC_FILTERS, status: "RETURNED" }, { page: 2, all: false }), "status=RETURNED&page=2");
});

test("a period is said in words and a session's semesters read from the server", () => {
  assert.equal(periodWords("2026/2027", 1, 300), "2026/2027, first semester, 300 Level");
  assert.equal(periodWords("2026/2027", null, null), "2026/2027");
  assert.deepEqual(periodSemesters({ session: "2026/2027", semesters: "{1,2}" }), [1, 2]);
  assert.deepEqual(periodSemesters(undefined), []);
});

test("a correction is one row of the report, its columns in the report's order", () => {
  const r = {
    realloc_ref: "REA/2026/000087", reference: "PAY/2026/001234", name: "DOE, Jane", matric_no: "MOAU/AD/ACC/26/10001",
    from_purpose: "Inter-departmental transfer", to_purpose: "School fees 2026/2027 · first semester", from_session: "2026/2027", to_session: "2026/2027",
    from_semester: null, to_semester: 1, from_level: 300, to_level: 300, amount: 100000, destination_fee: 180000, balance_after: 80000,
    status: "COMPLETED", initiated_by: "Officer", decided_by: "Bursar", executed_at: "2026-10-23T10:31:00Z", initiated_at: "2026-10-23T10:20:00Z",
  } as unknown as ReallocRow;
  const line = reallocLine(r, () => "23 Oct 2026");
  assert.equal(line.length, REALLOC_HEAD.length);
  assert.equal(line[12], 100000);
  assert.equal(line[14], 80000);
  assert.equal(line[9], "First");
  assert.equal(line[15], "Completed");
});

test("evidence is a PDF, JPEG or PNG of 5 MB at most", () => {
  assert.equal(evidenceRefusal({ type: "application/pdf", size: 1000 }), null);
  assert.equal(evidenceRefusal({ type: "text/plain", size: 10 }), "Evidence is a PDF, JPEG or PNG file.");
  assert.equal(evidenceRefusal({ type: "image/png", size: 6 * 1024 * 1024 }), "Evidence is up to 5 MB.");
});
