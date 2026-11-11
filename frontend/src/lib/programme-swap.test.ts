import { test } from "node:test";
import assert from "node:assert/strict";
import { CONFLICT_WORDS, KIND_WORDS, PLAIN_KINDS, changeWords, conflictWords, mismatchRows, postgraduateStructure, programmeFacts, programmeLabel, refusalWords, reportRows, restoreWords, signalWords, swapsHref, type Faculty, type Mismatch, type RestoreCheck, type Swap } from "./programme-swap.ts";

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

test("V669: a transfer approved on the old portal is restored, never made as a plain swap; what restoring does, in words", () => {
  assert.ok(!PLAIN_KINDS.includes("APPROVED_TRANSFER_RESTORED"));
  assert.equal(KIND_WORDS.APPROVED_TRANSFER_RESTORED, "Approved transfer restored (old portal)");
  const base = {
    ok: true, refusals: [], warnings: [], change: "PROGRAMME_AND_LEVEL", session: "2026/2027",
    student: { id: "s", name: "Doe, Jane", matricNo: "MOAU/SC/MCB/24/75807", jambRegNo: null, admissionNo: null, status: "ACTIVE", entryMode: "UTME", studyMode: null, entrySession: "2024/2025" },
    from: { programme: "C1", programmeName: "B.Sc. Microbiology", dept: "MCB", department: null, faculty: "SC", facultyName: null, level: 200, category: null },
    to: { programme: "C2", programmeName: "B.Sc. Biochemistry", dept: "BCH", department: null, faculty: "SC", facultyName: null, level: 300, category: null },
    fees: null, registration: null, unchanged: [],
  };
  const moved: RestoreCheck = { ...base, restore: { fromProgramme: "C1", fromProgrammeName: "B.Sc. Microbiology", transferSession: "2025/2026", approvedOn: "2025-03-14",
    recordOnly: false, recordedAlready: null, openApplication: { id: "a", state: "REG_OK", toProgramme: "C2", appliedAt: "2026-10-01", withdrawn: true } } };
  assert.deepEqual(restoreWords(moved), [
    "B.Sc. Microbiology at 200 Level becomes B.Sc. Biochemistry at 300 Level.",
    "The transfer application waiting in the queue (reg ok) is withdrawn.",
    "No transfer application, transfer fee or transfer approval is made; the matriculation number stays MOAU/SC/MCB/24/75807.",
  ]);
  const recorded: RestoreCheck = { ...base, restore: { ...moved.restore!, recordOnly: true, openApplication: null } };
  assert.equal(restoreWords(recorded)[0], "The student is on B.Sc. Biochemistry at 300 Level already: the transfer approved on the old portal is recorded in the history, and nothing is moved.");
  assert.equal(restoreWords(recorded).length, 2);
});

test("V669: a placement conflict in a line", () => {
  assert.equal(conflictWords({ file_programme: "C1", file_programme_name: "B.Sc. Microbiology", file_level: 200, kept_programme: "C2", kept_programme_name: "B.Sc. Biochemistry",
    kept_level: 300, settled_by: "PSW/2026/000006" }), "The upload named B.Sc. Microbiology at 200 Level; the record kept B.Sc. Biochemistry at 300 Level, set by PSW/2026/000006");
  assert.equal(CONFLICT_WORDS.KEPT, "Recorded placement kept");
});

test("V719: a postgraduate student is moved among the postgraduate programmes alone, each named with its degree type, and the one chosen reads out in full", () => {
  const faculties: Faculty[] = [
    { code: "SC", name: "Science", departments: [
      { code: "MCS", name: "Mathematics and Computer Science", programmes: [
        { code: "C00023", name: "B.Sc. Computer Science", category: "UNDER GRADUATE", levels: [100, 200, 300, 400] },
        { code: "C97191", name: "M.Sc. Computer Science", category: "POST GRADUATE", levels: [700, 800, 900], award: "Master of Science" },
        { code: "C97192", name: "Ph.D. Computer Science (Ph.D.)", category: "POST GRADUATE", levels: [700, 800, 900], award: "Ph.D." },
      ] },
      { code: "PHY", name: "Physics", programmes: [{ code: "C00031", name: "B.Sc. Physics", category: "UNDER GRADUATE", levels: [100, 200, 300, 400] }] },
    ] },
    { code: "LAW", name: "Law", departments: [{ code: "PLW", name: "Public Law", programmes: [{ code: "C00040", name: "LL.B. Law", category: "UNDER GRADUATE", levels: [100, 200, 300, 400, 500] }] }] },
  ];
  const pg = postgraduateStructure(faculties);
  assert.deepEqual(pg.map((f) => f.code), ["SC"], "a faculty with no postgraduate programme is left out");
  assert.deepEqual(pg[0].departments.map((d) => d.code), ["MCS"], "so is a department");
  assert.deepEqual(pg[0].departments[0].programmes.map((p) => p.code), ["C97191", "C97192"]);
  assert.equal(programmeLabel({ name: "M.Sc. Computer Science", award: "Master of Science" }), "M.Sc. Computer Science · Master of Science");
  assert.equal(programmeLabel({ name: "Ph.D. Computer Science (Ph.D.)", award: "Ph.D." }), "Ph.D. Computer Science (Ph.D.)", "the degree already in the name is not said twice");
  assert.equal(programmeLabel({ name: "B.Sc. Physics" }), "B.Sc. Physics");
  assert.deepEqual(programmeFacts(faculties, "C97191"), { code: "C97191", name: "M.Sc. Computer Science", award: "Master of Science", department: "Mathematics and Computer Science", faculty: "Science", levels: [700, 800, 900], category: "POST GRADUATE" });
  assert.equal(programmeFacts(faculties, "C99999"), null);
});
