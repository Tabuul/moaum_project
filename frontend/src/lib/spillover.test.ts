import { test } from "node:test";
import assert from "node:assert/strict";
import { semesterLine, spilloverStatus, spilloverTitle, type SpilloverPanel, type SpilloverSemester } from "./spillover.ts";

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
