import { test } from "node:test";
import assert from "node:assert/strict";
import { summerConfirmationPdf, ascii } from "./summer-confirmation.ts";
import { DEFAULT_INSTITUTION } from "./document/institution.ts";
import { primeInstitution } from "./document/institution-cache.ts";
import { confirmationRowWord, confirmationState, confirmationStatusWord, confirmationTitle, type SummerConfirmation, type SummerConfirmationRow } from "./summer.ts";

const inst = { ...DEFAULT_INSTITUTION, name: "Example University, Makurdi", shortName: "EXU" };

const row = (code: string, o: Partial<SummerConfirmationRow> = {}): SummerConfirmationRow => ({
  course_code: code, title: `${code} title`, units: 3, course_semester: 1, original_session: null, original_semester: null, category_label: "Student-selected course",
  registration_status: "REGISTERED", verification: "PENDING_VERIFICATION", verified_via: null, decision_reason: null, clarification_note: null, ...o,
});

function confirmation(o: Partial<SummerConfirmation> = {}): SummerConfirmation {
  return {
    session: "2025/2026", generatedAt: "2026-11-24T10:00:00Z", status: "REGISTERED",
    student: { name: "ZZSUMMER Ada", number: "ZZ/25/0001", programme: "Computer Science", department: "Computer Science", faculty: "Science", level: 400, category: "SPILLOVER" },
    period: { registration_opens: "2026-12-01", registration_closes: "2026-12-20", exams_from: null, exams_to: null, results_due: null, state: "OPEN" },
    rows: [
      row("CSC 401", { verification: "CONFIRMED_OUTSTANDING", verified_via: "RESULTS", category_label: "Carry-over", original_session: "2024/2025", original_semester: 1 }),
      row("CSC 402"),
      row("CSC 403", { verification: "REJECTED", registration_status: "TAKEN_OFF", decision_reason: "You passed this course in 2023/2024; it is not outstanding.", units: 2 }),
    ],
    totals: { courses: 2, units: 6, unitsRegistered: 6, programmeFee: "50000.00", courseFees: "10000.00", total: "60000.00", paid: "60000.00", due: "0.00" },
    payments: [{ reference: "ZZREF-0001", amount: "60000.00", receipt_no: "RCT-1", confirmed_at: "2026-12-02T09:00:00Z" }],
    notice: "Courses marked Pending verification are registered at your request and are not confirmed carry-overs until the Academic Office verifies them against your record. A course found not outstanding or rejected is taken off your registration and its fee is held for you as a Summer credit.",
    ...o,
  };
}

const text = (bytes: Uint8Array) => new TextDecoder("latin1").decode(bytes);
const QR = { matrix: { size: 21, dark: Array.from({ length: 441 }, (_, i) => i % 3 === 0) }, caption: "Summer Semester registration ZZ/25/0001 - check code ABC123" };

test("a registered student's confirmation is titled so, carries the QR, and prints each course with its verification", () => {
  primeInstitution(inst);
  const t = text(summerConfirmationPdf(confirmation(), inst, QR).finish());
  assert.ok(t.startsWith("%PDF-1.4"));
  assert.ok(t.includes("(SUMMER SEMESTER REGISTRATION CONFIRMATION) Tj"));
  assert.ok(t.includes("(SCAN TO VERIFY) Tj"), "the QR is printed when the registration stands");
  assert.ok(t.includes("(Registered) Tj"), "the status line");
  assert.ok(!t.includes("payment outstanding") && !t.includes("registration pending"));
  assert.ok(t.includes("(CSC 401) Tj") && t.includes("(CSC 402) Tj") && t.includes("(CSC 403) Tj"));
  assert.ok(t.includes("(Pending verification) Tj"), "a pending course reads Pending verification");
  assert.ok(t.includes("(Confirmed outstanding) Tj"));
  assert.ok(t.includes("(Rejected) Tj"));
  assert.ok(t.includes("(Student-selected) Tj"), "the category wraps inside its column and is not cut");
  assert.ok(t.includes("Reason: You passed this course in 2023/2024; it is not outstanding."), "a rejected course says why");
  assert.ok(t.includes("NGN 50,000 + 2 x NGN 5,000 = NGN 60,000"), "the server's total, written out as the formula");
  assert.ok(t.includes("(ZZREF-0001) Tj") && t.includes("(RCT-1) Tj"), "the payment and its receipt number");
  for (const w of ["Student selected - pending verification", "Academically confirmed outstanding", "Not outstanding - result verified", "Rejected - incorrect course selection"]) {
    assert.equal(t.split(w).length - 1, 1, `${w}: said once, in full`);
  }
});

test("a summary of an unpaid selection is titled so and carries no QR, even when a QR is offered", () => {
  primeInstitution(inst);
  const c = confirmation({ status: "SELECTED_UNPAID", rows: [row("CSC 402", { registration_status: "SELECTED" })], totals: { courses: 1, units: 3, unitsRegistered: 0, programmeFee: "50000.00", courseFees: "5000.00", total: "55000.00", paid: "0.00", due: "55000.00" }, payments: [] });
  const t = text(summerConfirmationPdf(c, inst, QR).finish());
  assert.ok(t.includes("(SUMMER SEMESTER SELECTION SUMMARY \\(PAYMENT OUTSTANDING\\)) Tj"), "the title of a summary, its brackets escaped as the writer escapes them");
  assert.ok(!t.includes("SCAN TO VERIFY"), "nothing is paid, so the public check would answer not genuine: no QR");
  assert.ok(!t.includes("(SUMMER SEMESTER REGISTRATION CONFIRMATION) Tj"));
  assert.ok(t.includes("(Selected: unpaid) Tj"));
  assert.ok(t.includes("(Selected, payment outstanding) Tj"), "the status line of an unpaid selection");
});

test("a student who has paid but whose registration has not taken the courses is not told the payment is outstanding (F23)", () => {
  primeInstitution(inst);
  // registration.summer_confirmation for a paid student with no semester-3 entry (a summer_issue): status SELECTED_UNPAID, each paid row
  // REGISTERED (its charge's PAID), paid 60,000, owed 0, the payment with its receipt
  const c = confirmation({
    status: "SELECTED_UNPAID",
    rows: [row("ZZV 201"), row("ZZV 301")],
    totals: { courses: 2, units: 6, unitsRegistered: 0, programmeFee: "50000.00", courseFees: "10000.00", total: "60000.00", paid: "60000.00", due: "0.00" },
  });
  assert.equal(confirmationState(c), "PAID_PENDING");
  const t = text(summerConfirmationPdf(c, inst, QR).finish());
  assert.ok(t.includes("(SUMMER SEMESTER SELECTION SUMMARY \\(REGISTRATION PENDING\\)) Tj"), "the title says what it waits for");
  assert.ok(t.includes("(Paid, registration pending) Tj"), "the status line says it is paid");
  assert.ok(!/payment outstanding/i.test(t), "never 'payment outstanding' for a paid student");
  assert.ok(!t.includes("(Registered) Tj"), "a paid course the registration has not taken is not called registered");
  assert.ok(t.includes("(Paid, not yet) Tj") && t.includes("(registered) Tj"), "its row says paid, not yet registered (wrapped in its column)");
  assert.ok(!t.includes("SCAN TO VERIFY"), "the registration does not stand, so no QR");
  assert.ok(t.includes("(RCT-1) Tj"), "the payment and its receipt are listed");
});

test("the confirmation's state, title, status line and row words for each state (F23)", () => {
  const registered = confirmation();
  const unpaid = confirmation({ status: "SELECTED_UNPAID", rows: [row("CSC 402", { registration_status: "SELECTED" })], totals: { ...registered.totals, paid: "0.00", due: "55000.00" } });
  const paid = confirmation({ status: "SELECTED_UNPAID", rows: [row("CSC 402")], totals: { ...registered.totals, paid: "55000.00", due: "0.00" } });
  const part = confirmation({ status: "SELECTED_UNPAID", rows: [row("CSC 402"), row("CSC 404", { registration_status: "SELECTED" })], totals: { ...registered.totals, paid: "55000.00", due: "5000.00" } });
  // a programme fee still paid while every paid course was taken off and a new one is unpaid: nothing selected is paid
  const programmeOnly = confirmation({ status: "SELECTED_UNPAID", rows: [row("CSC 403", { registration_status: "TAKEN_OFF", verification: "REJECTED" }), row("CSC 404", { registration_status: "SELECTED" })], totals: { ...registered.totals, paid: "50000.00", due: "5000.00" } });
  assert.deepEqual([registered, unpaid, paid, part, programmeOnly].map(confirmationState), ["REGISTERED", "UNPAID", "PAID_PENDING", "PAID_PENDING", "UNPAID"]);
  assert.deepEqual([registered, unpaid, paid, part, programmeOnly].map(confirmationStatusWord),
    ["Registered", "Selected, payment outstanding", "Paid, registration pending", "Paid in part, registration pending", "Selected, payment outstanding"]);
  assert.equal(confirmationTitle("REGISTERED"), "Summer Semester Registration Confirmation");
  assert.equal(confirmationTitle("PAID_PENDING"), "Summer Semester Selection Summary (registration pending)");
  assert.equal(confirmationTitle("UNPAID"), "Summer Semester Selection Summary (payment outstanding)");
  assert.equal(confirmationTitle("SELECTED_UNPAID"), "Summer Semester Selection Summary (payment outstanding)", "the server's status, read as before");
  assert.equal(confirmationRowWord("PAID_PENDING", "REGISTERED"), "Paid, not yet registered");
  assert.equal(confirmationRowWord("PAID_PENDING", "SELECTED"), "Selected: unpaid");
  assert.equal(confirmationRowWord("REGISTERED", "REGISTERED"), "Registered");
  assert.equal(confirmationRowWord("UNPAID", "TAKEN_OFF"), "Taken off");
});

test("a student-selected course is never called a carry-over on the sheet", () => {
  primeInstitution(inst);
  const c = confirmation({ rows: [row("CSC 402"), row("CSC 404")] });
  const t = text(summerConfirmationPdf(c, inst, QR).finish());
  const lines = t.split("\n").filter((l) => l.includes(" Tj"));
  // the rows' own cells say Student-selected course; the only "carry-over" the sheet may print is the server's notice, which says what a pending course is not
  const cells = lines.filter((l) => /\((CSC 40[24]|Student-selected|Pending verification)\) Tj/.test(l));
  assert.ok(cells.length >= 4);
  assert.ok(cells.every((l) => !/carry-?over/i.test(l)));
});

test("a long list runs onto a second page with the table header again", () => {
  primeInstitution(inst);
  const rows = Array.from({ length: 70 }, (_, i) => row(`CSC ${String(100 + i)}`, { title: `Course number ${i}` }));
  const doc = summerConfirmationPdf(confirmation({ rows }), inst, QR);
  assert.ok(doc.pages.length >= 2, `70 courses need more than a page, got ${doc.pages.length}`);
  const t = text(doc.finish());
  assert.ok((t.match(/\(COURSE TITLE\) Tj/g) ?? []).length >= 2, "the header of the table repeats on the next page");
  assert.ok(t.includes(`(Page 1 of ${doc.pages.length}) Tj`));
});

test("text is set in the characters the document's fonts have", () => {
  assert.equal(ascii("₦50,000 + 4 × ₦5,000"), "NGN 50,000 + 4 x NGN 5,000");
  assert.equal(ascii("Not outstanding – result verified"), "Not outstanding - result verified");
  assert.equal(ascii("Second semester · 2024/2025"), "Second semester - 2024/2025");
  assert.equal(ascii(null), "");
});

test("a course found not outstanding or rejected is struck out; a pending or confirmed one is not", () => {
  primeInstitution(inst);
  const strikes = (c: SummerConfirmation) => summerConfirmationPdf(c, inst, QR).pages.flatMap((p) => p.ops).filter((o) => o.startsWith("0.35 G 0.7 w")).length;
  assert.equal(strikes(confirmation()), 1, "one rejected course, one strike");
  assert.equal(strikes(confirmation({ rows: [row("CSC 402"), row("CSC 401", { verification: "CONFIRMED_OUTSTANDING" })] })), 0);
  assert.equal(strikes(confirmation({ rows: [row("A 1", { verification: "NOT_OUTSTANDING", registration_status: "TAKEN_OFF", decision_reason: "A pass is on record: 2023/2024 first semester" }), row("B 2", { verification: "REJECTED", registration_status: "TAKEN_OFF", decision_reason: "Not a course of your programme" })] })), 2);
});
