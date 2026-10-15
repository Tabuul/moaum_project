import { test } from "node:test";
import assert from "node:assert/strict";
import { EMPTY_QUERY, PRESETS, activeFilters, applyPreset, exportHeading, levelWord, queryString, readQueryFilters, spilloverWord, withChange, type QueryOptions } from "./student-query.ts";

const OPTIONS: QueryOptions = {
  scope: { kind: "UNIVERSITY", label: "University", programmeType: null }, currentSession: "2025/2026", type: null,
  types: [{ id: "1", code: "UNDERGRADUATE", name: "Undergraduate", description: null, display_order: 10, active: true },
    { id: "2", code: "POSTGRADUATE", name: "Postgraduate", description: null, display_order: 20, active: true }],
  routes: [{ code: "UTME", name: "UTME" }], centres: [{ code: "MAIN_CAMPUS", name: "Main Campus" }], studyModes: ["FULL_TIME"], statuses: ["ACTIVE"],
  levels: [100, 400], admissionSessions: ["2025/2026"],
  programmes: [{ faculty_code: "SC", faculty: "Science", dept_code: "MTC", department: "Computer Science", programme_code: "C00023", programme: "B.Sc. Computer Science" }],
  pgAwards: [], prelimRoutes: [], jupebCombinations: [], jupebSubjects: [], sessions: ["2025/2026"], learnerSessions: [], semesters: [1, 2], fees: true, classifies: true,
};

test("the address is read back only where each value has its shape", () => {
  const f = readQueryFilters({ type: "UNDERGRADUATE", fac: "SC", level: "400", status: "ACTIVE", session: "2025/2026", sex: "X", fees: "SOMETIMES",
    jupebCombination: "not-a-uuid", entryYear: "1066", q: "  okoh  ", route: "utme; DROP" });
  assert.equal(f.type, "UNDERGRADUATE");
  assert.equal(f.fac, "SC");
  assert.equal(f.level, "400");
  assert.equal(f.session, "2025/2026");
  assert.equal(f.sex, "");
  assert.equal(f.fees, "");
  assert.equal(f.jupebCombination, "");
  assert.equal(f.entryYear, "");
  assert.equal(f.q, "okoh");
  assert.equal(f.route, "");
  assert.equal(readQueryFilters({ type: "ALL" }).type, "");
});

test("the filters round-trip through the query string, empty ones left out", () => {
  const f = { ...EMPTY_QUERY, type: "POSTGRADUATE", dept: "MTC", q: "ada obi" };
  const qs = queryString(f, { page: 2, group: undefined });
  assert.equal(qs, "type=POSTGRADUATE&dept=MTC&q=ada+obi&page=2");
  assert.deepEqual(readQueryFilters(Object.fromEntries(new URLSearchParams(qs))), f);
});

test("a change clears what depended on it: type → route … programme; faculty → department → programme", () => {
  const f = { ...EMPTY_QUERY, type: "UNDERGRADUATE", route: "UTME", fac: "SC", dept: "MTC", prog: "C00023", level: "400", status: "ACTIVE" };
  const t = withChange(f, "type", "POSTGRADUATE");
  assert.equal(t.type, "POSTGRADUATE");
  assert.equal(t.route + t.fac + t.dept + t.prog + t.level, "");
  assert.equal(t.status, "ACTIVE");
  const d = withChange(f, "fac", "MS");
  assert.equal(d.fac, "MS");
  assert.equal(d.dept + d.prog, "");
  assert.equal(d.type, "UNDERGRADUATE");
});

test("a preset only sets filters, keeping the student type and the session", () => {
  const f = { ...EMPTY_QUERY, type: "CCE", session: "2024/2025", fac: "SC", level: "300" };
  const finalYear = applyPreset(f, PRESETS.find((p) => p.key === "FINAL_YEAR")!);
  assert.deepEqual(finalYear, { ...EMPTY_QUERY, type: "CCE", session: "2024/2025", status: "CURRENT", finalYear: "YES" });
  assert.ok(PRESETS.filter((p) => p.fees).every((p) => p.filters.fees));
});

test("the applied filters read in words and head the export with the student type", () => {
  const f = { ...EMPTY_QUERY, type: "UNDERGRADUATE", fac: "SC", level: "400", status: "ACTIVE" };
  assert.deepEqual(activeFilters(f, OPTIONS).map((x) => `${x.label}: ${x.value}`), ["Programme type: Undergraduate", "Faculty: Science", "Level: 400 Level", "Status: Active"]);
  const h = exportHeading(f, OPTIONS);
  assert.equal(h.title, "STUDENT TYPE: UNDERGRADUATE");
  assert.equal(h.sub, "Faculty: Science · Level: 400 Level · Status: Active");
  assert.equal(exportHeading(EMPTY_QUERY, OPTIONS).title, "STUDENT TYPE: ALL STUDENT TYPES");
});

test("a Preliminary learner's level reads Preliminary, a JUPEB learner's a dash", () => {
  assert.equal(levelWord({ source: "REGISTER", level: 300 }), "300");
  assert.equal(levelWord({ source: "PRELIMINARY", level: null }), "Preliminary");
  assert.equal(levelWord({ source: "JUPEB", level: null }), "—");
});

test("a spillover reads SP1, SP2 or the limit reached; within the programme's length nothing", () => {
  assert.deepEqual(spilloverWord("SPILLOVER_YEAR_1"), { short: "SP1", long: "Spillover year 1 (SP1)" });
  assert.equal(spilloverWord("SPILLOVER_YEAR_2")?.short, "SP2");
  assert.equal(spilloverWord("SPILLOVER_LIMIT_REACHED")?.long, "Spillover limit reached");
  assert.equal(spilloverWord("NORMAL"), null);
  assert.equal(spilloverWord("NOT_APPLICABLE"), null);
  assert.equal(spilloverWord(null), null);
});
