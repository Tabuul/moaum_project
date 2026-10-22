import { test } from "node:test";
import assert from "node:assert/strict";
import { confirmLines, listRow, reasonsOf, recBatchPath, recBatchState, recOutcome, timeline, type Candidate } from "./graduation-reconciliation.ts";

const c: Candidate = {
  student_id: "s1", matric_no: "MOAU/AD/BIO/18/12345", jamb_reg_no: null, surname: "ADEYEMI", other_names: "Ruth", status: "ACTIVE",
  programme_code: "C00023", programme: "B.Sc. Biology", dept_code: "BIO", department: "Biology", faculty_code: "SC", faculty: "Science",
  entry_session: "2018/2019", matric_year: 2018, effective_cohort: "2018/2019", cohort_source: "ENTRY", entry_level: 100, duration_years: 4,
  duration_source: "PROGRAMME", final_level: 400, current_level: 400, computed_level: 400, current_session: "2026/2027", deferred_sessions: 0,
  live_deferment: false, expected_completion: "2021/2022", sp1_session: "2022/2023", sp2_session: "2023/2024", max_spillover_years: 2,
  maximum_session: "2023/2024", spillover_years: 5, spillover_state: "SPILLOVER_LIMIT_REACHED", registered_current: false, enrolled_current: false,
  last_session: "2021/2022", completion: null, programme_moves: 0, pending_moves: null, issues: [], confidence: "MEDIUM",
  confidence_reasons: "MEDIUM: no course registration or enrolment on record; MEDIUM: the programme's length is the University rule, not set on the programme",
  recommendation: "GRADUATED",
};

test("the confirmation says identified, eligible and requiring review (V638)", () => {
  assert.deepEqual(confirmLines({ identified: 1250, eligible: 1100, review: 150 }), [
    "1,250 students identified outside the maximum academic period.",
    "1,100 eligible for automatic graduation.",
    "150 require manual review.",
  ]);
  assert.equal(confirmLines({ identified: 1, eligible: 0, review: 1 })[2], "1 requires manual review.");
});

test("the timeline reads the engine's counts in the rule's order, and the reasons lose their level prefix", () => {
  const t = new Map(timeline(c));
  assert.equal(t.get("Programme length"), "4 sessions to 400 Level");
  assert.equal(t.get("Expected completion"), "2021/2022");
  assert.equal(t.get("SP2"), "2023/2024");
  assert.equal(t.get("Maximum session permitted"), "2023/2024 (2 spillover sessions allowed)");
  assert.equal(t.get("Sessions beyond the expected completion"), "5");
  assert.deepEqual(reasonsOf(c.confidence_reasons), ["no course registration or enrolment on record", "the programme's length is the University rule, not set on the programme"]);
  assert.deepEqual(reasonsOf(null), []);
  const row = listRow(c);
  assert.equal(row[0], "ADEYEMI, Ruth");
  assert.equal(row[9], "Medium");
  assert.equal(row.length, 11);
});

test("batch references, standing and outcomes", () => {
  assert.equal(recBatchPath("GRAD-RECON/2026/000012"), "2026/000012");
  assert.deepEqual(recBatchState({ closed_at: null, executed_at: null, eligible: 3, graduated: 0, skipped: 0, refused: 0 }), ["Waiting", "warn"]);
  assert.deepEqual(recBatchState({ closed_at: null, executed_at: "2026-10-22T10:00:00Z", eligible: 3, graduated: 3, skipped: 0, refused: 0 }), ["Executed", "ok"]);
  assert.deepEqual(recBatchState({ closed_at: "2026-10-22T11:00:00Z", executed_at: "x", eligible: 3, graduated: 3, skipped: 0, refused: 0 }), ["Closed", "grey"]);
  assert.deepEqual(recOutcome({ outcome: "GRADUATED", verdict: "ELIGIBLE", note: null, corrected_at: null }), ["Graduated", "ok"]);
  assert.deepEqual(recOutcome({ outcome: "GRADUATED", verdict: "ELIGIBLE", note: null, corrected_at: "2026-10-23" }), ["Corrected", "info"]);
  assert.deepEqual(recOutcome({ outcome: null, verdict: "REVIEW", note: null, corrected_at: null }), ["Left for review", "warn"]);
  assert.deepEqual(recOutcome({ outcome: "REFUSED", verdict: "ELIGIBLE", note: "GRADRECON_NOT_OUTSIDE: changed", corrected_at: null }), ["Refused — GRADRECON_NOT_OUTSIDE: changed", "bad"]);
});
