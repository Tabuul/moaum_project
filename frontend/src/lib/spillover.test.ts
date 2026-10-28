import { test } from "node:test";
import assert from "node:assert/strict";
import { SEMESTER_STATUS_WORDS, quoteWords, registeringWords, semesterLine, spilloverStatus, spilloverTitle, type SpilloverPanel, type SpilloverQuote, type SpilloverSemester } from "./spillover.ts";

const sem = (n: number, o: Partial<SpilloverSemester> = {}): SpilloverSemester => ({ semester: n, fee: n === 1 ? 70000 : 60000, registered: false, carryovers: 0, courses: [], ...o });
const panel = (o: Partial<SpilloverPanel> = {}): SpilloverPanel => ({
  session: "2025/2026", state: "SPILLOVER_YEAR_1", year: 1, label: "SP1", registeredSemesters: [], semesters: [sem(1), sem(2)],
  sessionFee: 0, due: 0, paid: 0, balance: 0, ...o,
});

test("one semester registered: that semester's spillover fee alone, never a full session", () => {
  const sp = panel({ semesters: [sem(1, { registered: true, carryovers: 2 }), sem(2)], due: 70000, balance: 70000 });
  assert.equal(spilloverTitle(sp), "SP1 – First semester spillover fee");
  assert.equal(spilloverStatus(sp), "PAYMENT_REQUIRED");
  assert.equal(semesterLine(sp.semesters[0]), "2 carry-over courses from this semester. A course is registered in it, so its spillover fee is owed.");
  assert.equal(semesterLine(sp.semesters[1]), "Nothing is owed for it unless you register a course in it; its spillover fee is then owed.");
  const second = panel({ year: 2, label: "SP2", semesters: [sem(1), sem(2, { registered: true })], due: 60000, balance: 0, paid: 60000 });
  assert.equal(spilloverTitle(second), "SP2 – Second semester spillover fee");
  assert.equal(spilloverStatus(second), "PAYMENT_VERIFIED");
});

test("both semesters registered: both semesters' fees", () => {
  const sp = panel({ semesters: [sem(1, { registered: true }), sem(2, { registered: true })], due: 130000, balance: 60000, paid: 70000 });
  assert.equal(spilloverTitle(sp), "SP1 – First & Second semester spillover fees");
  assert.equal(spilloverStatus(sp), "PAYMENT_REQUIRED");
});

test("nothing registered: nothing to pay yet; a registered semester with no fee stated says so", () => {
  assert.equal(spilloverStatus(panel()), "NOTHING_YET");
  assert.equal(spilloverTitle(panel()), "SP1 · spillover");
  const unstated = panel({ semesters: [sem(1, { registered: true, fee: 0 }), sem(2, { fee: 0 })] });
  assert.equal(spilloverStatus(unstated), "NOT_STATED");
  assert.equal(semesterLine(unstated.semesters[0]), "A course is registered in it; no spillover fee is stated for your programme yet.");
});

test("V664: each semester stands on its own fee — the first paid does not make the second ready", () => {
  const first = sem(1, { registered: true, owed: 70000, paid: 70000, outstanding: 0, toClear: 0, status: "PAID", cleared: true });
  const second = sem(2, { registered: true, owed: 60000, paid: 0, outstanding: 60000, toClear: 60000, status: "PAYMENT_REQUIRED", cleared: false, carryovers: 2 });
  assert.equal(semesterLine(first), "A course is registered in it and its spillover fee is paid.");
  assert.equal(semesterLine(second), "2 carry-over courses from this semester. A course is registered in it: ₦60,000.00 of its spillover fee is still to pay. A payment for another semester does not cover it.");
  const w = registeringWords(second);
  assert.equal(w.title, "SECOND SEMESTER PAYMENT REQUIRED");
  assert.equal(w.pay, true);
  assert.equal(w.amount, 60000);
  assert.equal(w.body, "Second semester registration requires payment of the second semester spillover fee: ₦60,000.00 due, ₦0.00 paid, ₦60,000.00 outstanding. A payment for another semester does not cover it. Pay it, then submit; your courses stay on the draft meanwhile.");
  assert.deepEqual(SEMESTER_STATUS_WORDS[second.status!], ["Payment required", "bad"]);
  const ready = registeringWords(first);
  assert.equal(ready.title, "FIRST SEMESTER SPILLOVER FEE PAID");
  assert.equal(ready.pay, false);
});

test("V664: part paid says exactly what is left; an earlier item unpaid adds to what is to pay", () => {
  const part = registeringWords(sem(2, { registered: true, owed: 60000, paid: 30000, outstanding: 30000, toClear: 30000, status: "PART_PAID" }));
  assert.equal(part.amount, 30000);
  assert.match(part.body, /₦60,000\.00 due, ₦30,000\.00 paid, ₦30,000\.00 outstanding\. A payment/);
  const behind = registeringWords(sem(2, { registered: true, owed: 60000, paid: 0, outstanding: 60000, toClear: 65000, status: "PAYMENT_REQUIRED" }));
  assert.equal(behind.amount, 65000);
  assert.match(behind.body, /With what is still owed before it, ₦65,000\.00 is to pay\./);
});

test("V664: nothing is charged for a semester with nothing registered", () => {
  const none = registeringWords(sem(2, { status: "NOTHING_OWED" }));
  assert.equal(none.title, "NOTHING OWED FOR THE SECOND SEMESTER YET");
  assert.equal(none.pay, false);
  // V674: no talk of "no carry-over course": every course a spillover student registers is one
  assert.equal(none.body, "Nothing is owed for the second semester until you register a course in it; its spillover fee of ₦60,000.00 is then payable. Every course you register in spillover is a carry-over.");
  const toRegister = registeringWords(sem(2, { status: "NOT_REGISTERED", carryovers: 2 }));
  assert.equal(toRegister.pay, false);
  assert.equal(toRegister.body, "You have 2 second semester carry-over courses. Nothing is owed for the second semester until a course of it is saved on your registration; its spillover fee of ₦60,000.00 is then payable, and the registration is submitted once it is paid. A payment for another semester does not cover it.");
});

// V682: the carry-over picker's words once a course is ticked
const quote = (o: Partial<SpilloverQuote> = {}): SpilloverQuote => ({
  session: "2025/2026", semester: 1, label: "SP1", registered: false, stated: true, cleared: false,
  fee: 70000, sessionFee: 0, charge: 70000, due: 70000, paid: 0, toPay: 70000, ...o,
});

test("a course ticked in a semester not yet registered: its spillover fee and what is to pay", () => {
  const w = quoteWords(quote(), 2);
  assert.equal(w.title, "FIRST SEMESTER SPILLOVER FEE: ₦70,000.00");
  assert.equal(w.toPay, 70000);
  assert.equal(w.tone, "bad");
  assert.equal(w.body, "Adding these courses makes the first semester spillover fee of ₦70,000.00 payable — once for the first semester, however many carry-overs you add in it. To pay for the first semester: ₦70,000.00. Your courses stay on the draft meanwhile; submit once it is paid.");
  // the whole-session item with the first semester registered, and what is still owed before it
  const s = quoteWords(quote({ semester: 2, fee: 60000, sessionFee: 20000, charge: 80000, toPay: 150000 }), 1, true);
  assert.equal(s.title, "SECOND SEMESTER SPILLOVER FEE: ₦80,000.00");
  assert.equal(s.body, "Adding this course makes the second semester spillover fee of ₦60,000.00 payable, with the session's spillover item of ₦20,000.00 — once for the second semester, however many carry-overs you add in it. To pay for the second semester: ₦150,000.00 (with what is still owed before it). Pay it on Fees & payments first; this course can be added once the payment is confirmed.");
});

test("a semester already registered costs nothing more; paid, not stated", () => {
  const owed = quoteWords(quote({ registered: true, toPay: 30000, paid: 40000 }), 1);
  assert.equal(owed.title, "FIRST SEMESTER SPILLOVER FEE: ₦70,000.00");
  assert.equal(owed.body, "A course of the first semester is already on your registration, so its spillover fee is owed already; adding this course costs nothing more. ₦30,000.00 is still to pay. Your courses stay on the draft meanwhile; submit once it is paid.");
  const paid = quoteWords(quote({ registered: true, toPay: 0, paid: 70000, cleared: true }), 3);
  assert.equal(paid.tone, "ok");
  assert.match(paid.body, /costs nothing more\. It is paid\.$/);
  const covered = quoteWords(quote({ toPay: 0, paid: 70000 }), 1);
  assert.match(covered.body, /Your payments already cover it\.$/);
  const none = quoteWords(quote({ stated: false, fee: 0, charge: 0, toPay: 0 }), 1);
  assert.equal(none.title, "FIRST SEMESTER SPILLOVER FEE NOT YET STATED");
  assert.equal(none.tone, "info");
});
