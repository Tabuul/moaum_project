import { test } from "node:test";
import assert from "node:assert/strict";
import { confirmLabel, ddmmyyyy, deactivatedHolder, outcomeWord, reasonProblem, RESTORE_REASONS, summaryLine, tally, tiesText, type RemovalRow, type StaffChange } from "./staff-removal.ts";

const row = (outcome: string): RemovalRow => ({ person_id: outcome, staff_number: null, name: null, category: "ACADEMIC", ties: [], outcome, detail: null, applied: false, change_id: null });

test("a preview counts the deleted, the deactivated and the people left as they are", () => {
  const t = tally([row("REMOVE"), row("REMOVE"), row("DEACTIVATE"), row("HOLDS_OFFICE"), row("CANNOT_REMOVE")]);
  assert.deepEqual(t, { remove: 2, deactivate: 1, refused: 2 });
  assert.equal(summaryLine(t), "2 will be deleted permanently · 1 will be deactivated and kept · 2 cannot be changed");
  assert.equal(confirmLabel(t), "Delete 2 and deactivate 1");
  assert.equal(confirmLabel({ remove: 0, deactivate: 3 }), "Deactivate 3");
  assert.equal(confirmLabel({ remove: 1, deactivate: 0 }), "Delete 1 permanently");
  assert.equal(summaryLine({ remove: 0, deactivate: 0, refused: 0 }), "Nothing to change");
});

test("an outcome reads as what will happen, then as what did", () => {
  assert.equal(outcomeWord("REMOVE"), "Will be deleted permanently");
  assert.equal(outcomeWord("REMOVE", true), "Deleted permanently");
  assert.equal(outcomeWord("DEACTIVATE"), "Will be deactivated (kept on record)");
  assert.equal(outcomeWord("HOLDS_OFFICE"), "Holds another office");
  assert.equal(outcomeWord("SOMETHING_NEW"), "SOMETHING_NEW");
});

test("a reason is chosen, and Other is described", () => {
  assert.equal(reasonProblem("", ""), "Choose the reason.");
  assert.equal(reasonProblem("ADDED_IN_ERROR", ""), null);
  assert.equal(reasonProblem("OTHER", "short"), "Describe the reason in a few words.");
  assert.equal(reasonProblem("OTHER", "Transferred to the polytechnic"), null);
  assert.equal(reasonProblem("ADDED_IN_ERROR", "", RESTORE_REASONS), "Choose the reason.");   // not a restoration's reason
  assert.equal(reasonProblem("RETURNED_TO_SERVICE", "", RESTORE_REASONS), null);
});

test("ties read in a line, counts where they help", () => {
  assert.equal(tiesText([]), "No records");
  assert.equal(tiesText([{ kind: "catalogue.offering.lecturer_id", label: "Lecturer of a course class", n: 3 }, { kind: "SIGNED_IN", label: "Has signed in to the portal", n: 1 }]),
    "Lecturer of a course class (3) · Has signed in to the portal");
  assert.equal(tiesText([{ kind: "ACTED", label: "Changes made on the portal", n: 1000 }]), "Changes made on the portal");
  assert.equal(tiesText([{ kind: "hrm.payslip.person_id", label: "Payslips", n: 1000 }]), "Payslips (1,000+)");
});

test("a staff id that belongs to someone deactivated is found, so they are restored rather than added again", () => {
  const changes = [
    { id: "a", staff_number: "P539", restorable: true },
    { id: "b", staff_number: "P600", restorable: false },
  ] as StaffChange[];
  assert.equal(deactivatedHolder("539", changes)?.id, "a");
  assert.equal(deactivatedHolder("P539", changes)?.id, "a");
  assert.equal(deactivatedHolder("600", changes), null);
  assert.equal(deactivatedHolder("", changes), null);
});

test("a date field's day is written as the staff upload reads it", () => {
  assert.equal(ddmmyyyy("2001-01-04"), "04/01/2001");
  assert.equal(ddmmyyyy(""), "");
  assert.equal(ddmmyyyy("04/01/2001"), "");
});
