import { test } from "node:test";
import assert from "node:assert/strict";
import { DOCUMENT_FILTERS, appliedOn, appliedTimes, desksHref, documentsPill, missingDocuments } from "./pg-applications.ts";

test("V694: where the document upload stands reads as complete, pending with its count, not uploaded or fee unpaid", () => {
  assert.deepEqual(documentsPill("COMPLETE", 6, 6), { kind: "ok", label: "Complete" });
  assert.deepEqual(documentsPill("PENDING", 3, 6), { kind: "warn", label: "Pending · 3 of 6" });
  assert.deepEqual(documentsPill("NONE", 0, 6), { kind: "bad", label: "Not uploaded" });
  assert.deepEqual(documentsPill("FEE_UNPAID", 0, 6), { kind: "grey", label: "Fee unpaid" });
  assert.equal(documentsPill(null).label, "—");
});

test("V694: the desk offers the paid applicants who have not uploaded as a filter of their own", () => {
  assert.deepEqual(DOCUMENT_FILTERS.map((f) => f.value), ["COMPLETE", "PENDING", "NONE", "FEE_UNPAID"]);
  assert.equal(DOCUMENT_FILTERS.find((f) => f.value === "NONE")?.label, "Paid, not uploaded");
});

test("V694: the documents missing are named, in the order given", () => {
  assert.equal(missingDocuments("NYSC,LGA_CERTIFICATE"), "NYSC certificate, LGA / indigene certificate");
  assert.equal(missingDocuments(null), "");
});

test("V694: an applicant who applied more than once says how many times and the other numbers; once says nothing", () => {
  assert.equal(appliedTimes(3, "PG/26/000045, PG/26/000061"), "Applied 3 times · also PG/26/000045, PG/26/000061");
  assert.equal(appliedTimes("2", "PG/26/000045"), "Applied 2 times · also PG/26/000045");
  assert.equal(appliedTimes(1, null), null);
  assert.equal(appliedTimes(null, null), null);
});

test("V694: the day an application was made, in Lagos time", () => {
  assert.deepEqual(appliedOn("2026-10-22T16:04:00Z"), { day: "22 Oct 2026", time: "17:04" });
  assert.deepEqual(appliedOn(null), { day: "—", time: "" });
});

test("V694: the desk's address keeps the session and carries only the narrowing chosen", () => {
  assert.equal(desksHref("2026/2027", {}), "/admissions/postgraduate?session=2026%2F2027");
  assert.equal(desksHref("2026/2027", { documents: "NONE", duplicates: true, sort: "applied" }),
    "/admissions/postgraduate?session=2026%2F2027&documents=NONE&duplicates=1&sort=applied");
});
