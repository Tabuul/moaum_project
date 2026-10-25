import { test } from "node:test";
import assert from "node:assert/strict";
import { dimensionLabel, dimensionRows, drill, eligibilityWord, filterLines, manualLines, readFilters, regQuery, totalRow, NO_FILTERS, type SummaryRow } from "./course-registration-report.ts";

test("the filters read only what is well formed", () => {
  const f = readFilters({ category: "gst", curriculum: "bmas", sex: "x", reg: "approved", eligible: "no", course: "csc 401", offering: "not-a-uuid",
    from: "2026-10-01", to: "yesterday", q: "  Terhemba ", dropped: "1" });
  assert.equal(f.category, "GST");
  assert.equal(f.curriculum, "BMAS");
  assert.equal(f.sex, "");
  assert.equal(f.reg, "APPROVED");
  assert.equal(f.eligible, "NO");
  assert.equal(f.course, "CSC 401");
  assert.equal(f.offering, "");
  assert.equal(f.from, "2026-10-01");
  assert.equal(f.to, "");
  assert.equal(f.q, "Terhemba");
  assert.equal(f.dropped, true);
  assert.equal(readFilters({ category: "SOMETHING" }).category, "");
  assert.equal(readFilters({ offering: "65200000-0000-4000-8000-000000000011" }).offering, "65200000-0000-4000-8000-000000000011");
});

test("the query carries the scope and only the filters set; every semester leaves the semester out", () => {
  const q = regQuery({ session: "2025/2026", sem: "0", fac: "SCI", dept: "", prog: "", level: "300" }, { ...NO_FILTERS, category: "CARRY_OVER", dropped: true });
  assert.equal(q.toString(), "session=2025%2F2026&fac=SCI&level=300&category=CARRY_OVER&dropped=true");
  assert.equal(regQuery({ session: "", sem: "1", fac: "", dept: "CSC", prog: "", level: "" }, NO_FILTERS).toString(), "semester=1&dept=CSC");
});

test("the filters in words, for an export's facts", () => {
  assert.deepEqual(filterLines({ ...NO_FILTERS, category: "GST", sex: "F", eligible: "NO", from: "2026-10-01" }),
    [["Category", "GST courses"], ["Sex", "Female"], ["Card or permit", "Not held"], ["Registered", "2026-10-01 to …"]]);
});

test("eligibility is the permit for a general course and the card for any other", () => {
  assert.equal(eligibilityWord({ category: "GST", holds_card: true, holds_permit: false, eligible: false }), "No permit");
  assert.equal(eligibilityWord({ category: "EPS", holds_card: false, holds_permit: true, eligible: true }), "Permit");
  assert.equal(eligibilityWord({ category: "DEPARTMENTAL", holds_card: true, holds_permit: false, eligible: true }), "Card");
  assert.equal(eligibilityWord({ category: "OTHER", holds_card: false, holds_permit: true, eligible: false }), "No card");
});

test("manual lines: the presets, or a custom number from 0 to 60", () => {
  assert.equal(manualLines("15", ""), 15);
  assert.equal(manualLines("7", ""), null);
  assert.equal(manualLines("custom", "0"), 0);
  assert.equal(manualLines("custom", "60"), 60);
  assert.equal(manualLines("custom", "61"), null);
  assert.equal(manualLines("custom", "ten"), null);
});

test("a dimension's rows, the largest first; labels and the filter each opens", () => {
  const rows: SummaryRow[] = [
    { dimension: "TOTAL", key: "", label: "All", registrations: 9, students: 3, male: 1, female: 2, other_sex: 0, carry_over: 1, eligible: 4 },
    { dimension: "SEX", key: "F", label: "Female", registrations: 6, students: 2, male: 0, female: 2, other_sex: 0, carry_over: 1, eligible: 3 },
    { dimension: "SEX", key: "", label: "Not stated", registrations: 1, students: 1, male: 0, female: 0, other_sex: 1, carry_over: 0, eligible: 0 },
    { dimension: "LEVEL", key: "300", label: "300", registrations: 9, students: 3, male: 1, female: 2, other_sex: 0, carry_over: 1, eligible: 4 },
    { dimension: "COURSE", key: "65200000-0000-4000-8000-000000000011", label: "ZZA 652 — Check", registrations: 2, students: 2, male: 1, female: 1, other_sex: 0, carry_over: 1, eligible: 1 },
  ];
  assert.equal(totalRow(rows)?.registrations, 9);
  assert.deepEqual(dimensionRows(rows, "SEX").map((r) => r.key), ["F", ""]);
  assert.equal(dimensionLabel("SEX", rows[2]), "Not stated");
  assert.equal(dimensionLabel("LEVEL", rows[3]), "300 Level");
  assert.deepEqual(drill("SEX", ""), { sex: "U" });
  assert.deepEqual(drill("FACULTY", "SCI"), { fac: "SCI", dept: "", prog: "" });
  assert.deepEqual(drill("COURSE", rows[4].key), { offering: rows[4].key });
});
