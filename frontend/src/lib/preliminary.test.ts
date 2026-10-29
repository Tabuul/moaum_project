import { test } from "node:test";
import assert from "node:assert/strict";
import { EXAM_TYPES, PRELIM_SLUGS, examTypes, isPrelimRoute, monthsWords, prelimPage, prelimSerial, requirementWords } from "./preliminary-routes.ts";
import type { PrelimRules } from "./preliminary.ts";

const rules = (r: Partial<PrelimRules>): PrelimRules => ({
  kind: "OLEVEL_CREDITS", minCredits: 5, maxSittings: 2, minCoreCredits: 3, coreSubjects: ["Chemistry", "Physics", "Biology"], coreByTarget: false, requiredSubjects: [],
  creditGrade: "C6", completionCredits: 5, completionScope: "ANY", completionSubjects: [], awaitingAccepted: false, remediationTerms: null, qualifications: [], ...r,
});

test("V701: the three routes are the preliminary stack's, each with its own public page; any other route is not", () => {
  for (const r of ["PRELIMINARY_SCIENCE", "PRELIMINARY_TECHNOLOGY", "PROFICIENCY_CERTIFICATE"]) assert.equal(isPrelimRoute(r), true);
  for (const r of ["UTME", "CCE", null, undefined, ""]) assert.equal(isPrelimRoute(r), false);
  assert.equal(prelimPage("PRELIMINARY_TECHNOLOGY"), "/preliminary-technology");
  assert.equal(prelimPage("PROFICIENCY_CERTIFICATE"), "/proficiency-certificate");
  assert.equal(PRELIM_SLUGS["preliminary-science"], "PRELIMINARY_SCIENCE");
  assert.deepEqual([prelimSerial("PRELIMINARY_SCIENCE"), prelimSerial("PRELIMINARY_TECHNOLOGY"), prelimSerial("PROFICIENCY_CERTIFICATE")], ["PRESCI", "PRETECH", "PROFCERT"]);
});

test("V701: the entry requirement in words — Preliminary Science's one list, Technology's English and Mathematics plus the area's subjects, the proficiency courses' attempted certificate", () => {
  assert.equal(requirementWords({ rules: rules({}), groupWord: "group", entryRequirement: null }),
    "At least 5 O'Level credit passes (C6 or better), in at most 2 sittings; 3 of them in Chemistry, Physics, Biology. An awaiting result is not accepted.");
  assert.equal(requirementWords({ rules: rules({ requiredSubjects: ["English Language", "Mathematics"], coreByTarget: true, coreSubjects: [] }), groupWord: "area", entryRequirement: null }),
    "At least 5 O'Level credit passes (C6 or better), including English Language and Mathematics, in at most 2 sittings; 3 of them in the subjects of the area you choose. An awaiting result is not accepted.");
  assert.equal(requirementWords({ rules: rules({ kind: "ATTEMPTED_CERTIFICATE" }), groupWord: "category", entryRequirement: "An attempted SSCE, GCE or NTC." }), "An attempted SSCE, GCE or NTC.");
  assert.match(requirementWords({ rules: rules({ kind: "ATTEMPTED_CERTIFICATE" }), groupWord: "category", entryRequirement: null }), /attempted secondary school certificate/);
});

test("V701: the qualifications offered are the route's own, the school certificate list when it names none; a duration not set says so", () => {
  assert.deepEqual(examTypes(rules({ qualifications: [{ code: "SSCE", label: "SSCE" }, { code: "NTC", label: "NABTEB NTC" }] })), [["SSCE", "SSCE"], ["NTC", "NABTEB NTC"]]);
  assert.deepEqual(examTypes(rules({})), EXAM_TYPES);
  assert.deepEqual(examTypes(null), EXAM_TYPES);
  assert.equal(monthsWords(9), "9 months");
  assert.equal(monthsWords(1), "1 month");
  assert.equal(monthsWords(null), "Not configured");
});
