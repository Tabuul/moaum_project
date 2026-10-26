import { test } from "node:test";
import assert from "node:assert/strict";
import { SEMESTER_STATUS_WORDS, registeringWords, semesterLine, spilloverStatus, spilloverTitle, type SpilloverPanel, type SpilloverSemester } from "./spillover.ts";

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
  const toRegister = registeringWords(sem(2, { status: "NOT_REGISTERED", carryovers: 2 }));
  assert.equal(toRegister.pay, false);
  assert.equal(toRegister.body, "You have 2 second semester carry-over courses. Nothing is owed for the second semester until a course of it is saved on your registration; its spillover fee of ₦60,000.00 is then payable, and the registration is submitted once it is paid. A payment for another semester does not cover it.");
});
