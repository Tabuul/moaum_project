import { test } from "node:test";
import assert from "node:assert/strict";
import { arity, cell, complete, definition, opsFor, QUERY_PRESETS, type QSource } from "./dbops.ts";

const src: QSource = { key: "EXAM_READINESS", label: "Examination readiness", note: "", period: true, columns: ["name", "matric_no"], sort: "name", sortDir: "asc", required: null,
  fields: [{ key: "name", label: "Student name", type: "TEXT", money: false }, { key: "level", label: "Level", type: "INT", money: false }] };

test("the operators each type takes, and what each takes (V640)", () => {
  assert.deepEqual(opsFor("BOOL"), ["is"]);
  assert.ok(opsFor("TEXT").includes("contains") && !opsFor("TEXT").includes("gt"));
  assert.ok(opsFor("INT").includes("between"));
  assert.equal(arity("empty"), 0);
  assert.equal(arity("between"), 2);
  assert.equal(arity("in"), "list");
  assert.equal(complete({ field: "level", op: "between", value: "100" }), false);
  assert.equal(complete({ field: "level", op: "between", value: "100", value2: "300" }), true);
});

test("the definition sent carries complete conditions only, the period for a source that needs it, never SQL", () => {
  const d = definition(src, { session: "2026/2027", semester: 1, filters: [
    { field: "level", op: "in", value: "200, 300" }, { field: "name", op: "contains", value: "" }, { field: "name", op: "empty" }] });
  assert.deepEqual(d.filters, [{ field: "level", op: "in", values: ["200", "300"] }, { field: "name", op: "empty" }]);
  assert.equal(d.session, "2026/2027");
  assert.equal(d.rule, "CARD");
  assert.deepEqual(d.columns, ["name", "matric_no"]);
  assert.equal(d.group, null);
  assert.equal(JSON.stringify(d).includes("SELECT"), false);
  assert.equal(QUERY_PRESETS.payments.source, "PAYMENTS");
  assert.equal(cell(true, "BOOL"), "Yes");
  assert.equal(cell("2026-10-23T08:00:00Z", "DATE"), "2026-10-23");
  assert.equal(cell("12", "INT"), 12);
});
