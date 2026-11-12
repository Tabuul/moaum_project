import { test } from "node:test";
import assert from "node:assert/strict";
import { decisionWord, levelReachedCohort, type CohortStudent } from "./cohorts.ts";

type Decision = CohortStudent["decisions"][number];
const decision = (over: Partial<Decision>): Decision => ({
  id: "d", previous_status: "ACTIVE", proposed_status: "ACTIVE", final_status: "ACTIVE", classification: null, previous_cohort: "2022/2023",
  effective_cohort: "2022/2023", rule: null, reason: "r", officer: null, actor_office: null, batch_ref: null, decided_at: "2026-11-12T09:00:00Z", ...over,
});

test("a decision reads as its cohort, its level rule or its standing", () => {
  assert.equal(decisionWord(decision({ rule: "COHORT", effective_cohort: "2023/2024" })), "Cohort 2022/2023 → 2023/2024");
  assert.equal(decisionWord(decision({ rule: "COMPLETION" })), "Expected completion");
  assert.equal(decisionWord(decision({ rule: "R3", final_status: "PROBATION" })), "Active → Probation");
  assert.equal(decisionWord(decision({ rule: "LEVEL_CORRECTION" })), "Corrected (level desk)");
});

test("V730: the hold, its release and the level reached are named on the cohort desk", () => {
  assert.equal(decisionWord(decision({ rule: "COHORT_DEPARTMENT_CHANGE", effective_cohort: "2023/2024" })), "Cohort a session later (changed department): cohort 2023/2024");
  assert.equal(decisionWord(decision({ rule: "COHORT_LEVEL_REACHED", effective_cohort: "2023/2024" })), "Continues at the level reached: cohort 2023/2024");
  assert.equal(decisionWord(decision({ rule: "COHORT_DEPARTMENT_CHANGE_RELEASED" })), "Hold released: the entry cohort, 2022/2023");
  assert.equal(decisionWord(decision({ rule: "COHORT_LEVEL_REACHED_LIFTED" })), "Level reached cohort lifted: the entry cohort, 2022/2023");
  assert.equal(decisionWord(decision({ rule: "LEVEL_DEPARTMENT_CHANGE_RELEASED" })), "Hold released: level put back");
  assert.equal(decisionWord(decision({ rule: "LEVEL_HELD_RELEASED" })), "Hold released: the level asked for made");
});

test("V730: a cohort is the level reached's only while its cohort and reason are a level-reached decision's; the desk's own is the desk's", () => {
  const why = "Changed department: continues at the level reached, 200 Level in 2025/2026 (V730)";
  const override = { effective_cohort: "2024/2025", reason: why, set_by: null, set_at: "2026-11-12T09:00:00Z" };
  const reached = decision({ rule: "COHORT_LEVEL_REACHED", effective_cohort: "2024/2025", reason: why });
  assert.equal(levelReachedCohort({ override, decisions: [reached] }), true);
  assert.equal(levelReachedCohort({ override: { ...override, reason: "Re-entry after withdrawal, Senate minute 14" }, decisions: [reached] }), false);
  assert.equal(levelReachedCohort({ override: { ...override, effective_cohort: "2023/2024" }, decisions: [reached] }), false);
  assert.equal(levelReachedCohort({ override: null, decisions: [reached] }), false);
  assert.equal(levelReachedCohort({ override, decisions: [{ ...reached, rule: "COHORT" }] }), false);
});
