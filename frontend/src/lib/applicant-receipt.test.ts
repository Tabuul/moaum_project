import { test } from "node:test";
import assert from "node:assert/strict";
import { applicantFeeName, applicantReceiptTitle, applicantReceiptVerifyPath } from "./applicant-receipt.ts";

test("the application fee's receipt is the Post-UTME application receipt, whichever JAMB route", () => {
  for (const route of ["UTME", "DIRECT_ENTRY", "TRANSFER", null, undefined]) {
    assert.equal(applicantReceiptTitle("APPLICATION", route), "Post-UTME application receipt");
    assert.equal(applicantFeeName("APPLICATION", route), "Post-UTME application fee");
  }
});

test("the CCE and Preliminary Science routes name their own fee; the admission fees keep theirs", () => {
  assert.equal(applicantReceiptTitle("APPLICATION", "CCE"), "CCE application receipt");
  assert.equal(applicantReceiptTitle("APPLICATION", "PRELIMINARY"), "Preliminary Science application receipt");
  assert.equal(applicantReceiptTitle("CHECKING", "UTME"), "Admission checking fee receipt");
  assert.equal(applicantReceiptTitle("ACCEPTANCE", "CCE"), "CCE acceptance fee receipt");
  assert.equal(applicantFeeName("ACCEPTANCE", "UTME"), "Acceptance fee");
});

test("the QR opens the public verification page with the signed code", () => {
  assert.equal(applicantReceiptVerifyPath("MOAUM-APP-006995-3918", "0A1B2C3D4E5F"), "/verify/receipt/MOAUM-APP-006995-3918?c=0A1B2C3D4E5F");
  assert.equal(applicantReceiptVerifyPath("A/B", "C D"), "/verify/receipt/A%2FB?c=C%20D");
});
