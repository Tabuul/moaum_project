import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWords, mismatchRows, refusalWords, reportRows, signalWords, swapsHref, type Mismatch, type Swap } from "./programme-swap.ts";

const swap = (o: Partial<Swap> = {}): Swap => ({
  id: "1", swap_ref: "PSW/2026/000001", student_id: "s", student: "Doe, John", matric_no: "MOAU/AD/BAM/24/1234", jamb_reg_no: "202410001AA",
  kind: "LEGACY_MIGRATION_CORRECTION", change: "PROGRAMME", status: "COMPLETED",
  from_programme: "C1", from_programme_name: "B.Sc. Business Administration", from_dept: "BAM", from_department: "Business Administration", from_faculty: "AD",
  from_faculty_name: "Administration", from_level: 300,
  to_programme: "C2", to_programme_name: "B.Sc. Computer Science", to_dept: "CSC", to_department: "Computer Science", to_faculty: "SC", to_faculty_name: "Science", to_level: 300,
  effective_session: "2026/2027", reason: "Legacy record kept the old programme", review: [], batch_id: null, prepared_by: "Officer, One", prepared_office: "academic",
  prepared_at: "2026-10-20T10:00:00Z", decided_by: "Officer, Two", decided_office: "registrar", decided_at: "2026-10-20T11:00:00Z", decision_note: null,
  executed_at: "2026-10-20T11:00:00Z", failure: null, impact: null, evidence: 0, ...o,
});

test("the change is said by what differs: faculty, department, programme, level", () => {
  assert.equal(changeWords(swap()), "faculty, department, programme");
  assert.equal(changeWords(swap({ to_programme: "C1", to_dept: "BAM", to_faculty: "AD", to_level: 200 })), "level 300 → 200");
  assert.equal(changeWords(swap({ to_programme: "C1", to_dept: "BAM", to_faculty: "AD" })), "nothing");
  assert.equal(refusalWords("PSW_SAME: the student is on that programme already"), "the student is on that programme already");
  assert.equal(refusalWords("no code here"), "no code here");
});

test("the report follows its headers, S/N first, the approver named only on a completed swap", () => {
  const rows = reportRows([swap(), swap({ status: "REJECTED", decided_by: "Officer, Two", executed_at: null })]);
  assert.equal(rows[0].length, 19);
  assert.equal(rows[0][0], 1);
  assert.equal(rows[0][6], "B.Sc. Business Administration");
  assert.equal(rows[0][10], "B.Sc. Computer Science");
  assert.equal(rows[0][13], "Legacy migration correction");
  assert.equal(rows[0][17], "Officer, Two");
  assert.equal(rows[1][15], "Rejected");
  assert.equal(rows[1][17], "");
});

test("why a record is flagged reads from its signals, and the list numbers its rows", () => {
  const m: Mismatch = {
    student_id: "s", surname: "Doe", other_names: "John", matric_no: "BSU/SC/MCB/23/69581", jamb_reg_no: null, status: "ACTIVE", entry_mode: "UTME",
    entry_session: "2023/2024", current_level: 300, programme_code: "C4", programme: "B.Sc. (ED) Human Kinetics", dept_code: "PHE", department: "Human Kinetics",
    faculty_code: "ED", faculty: "Education", matric_segment: "MCB", programme_segment: "PHE", registration_dept: "BIO", registration_dept_name: "Biological Sciences",
    registration_share: "0.64", admitted_programme: null, admitted_programme_name: null, classification: "REQUIRES_REVIEW", suggested_dept: "BIO",
    suggested_programme: "C9", suggested_programme_name: "B.Sc. Microbiology", review_status: "NOT_REVIEWED", review_note: null, reviewed_at: null,
  };
  assert.deepEqual(signalWords(m), ["Matriculation number names MCB; the programme's students carry PHE", "Latest registration is mostly Biological Sciences courses (64% of the courses)"]);
  const rows = mismatchRows([m]);
  assert.equal(rows[0][0], 1);
  assert.equal(rows[0][8], "Requires review");
  assert.equal(rows[0][11], "B.Sc. Microbiology");
  assert.equal(signalWords({ ...m, matric_segment: "PHE", registration_dept: "PHE", admitted_programme: "C1", admitted_programme_name: "B.Sc. Biology" }).join(), "Admitted to B.Sc. Biology");
});

test("the address names only the filters chosen", () => {
  assert.equal(swapsHref("desk", { fac: "", class: "CONFIRMED" }), "/programme-swap?class=CONFIRMED");
  assert.equal(swapsHref("swaps", { status: "PENDING_APPROVAL" }), "/programme-swap?tab=swaps&status=PENDING_APPROVAL");
});
