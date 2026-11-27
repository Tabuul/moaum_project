import assert from "node:assert/strict";
import test from "node:test";
import { orgFromFacets, orgFromStructure } from "./summer-org.ts";

test("the options the University's structure offers: faculties, their departments, their live programmes", () => {
  const structure = {
    faculties: [
      { code: "SCI", name: "Science", departments: [
        { code: "CSC", name: "Computer Science", programmes: [{ code: "C100", name: "B.Sc. Computer Science", archived: false }, { code: "C101", name: "Old", archived: true }] },
        { code: "BIO", name: "Biology", programmes: [] },
      ] },
      { code: "ART", name: "Arts", departments: [] },
    ],
  };
  const org = orgFromStructure(structure as never);
  assert.deepEqual(org.faculties, [{ code: "SCI", name: "Science" }, { code: "ART", name: "Arts" }]);
  assert.deepEqual(org.departments, [{ code: "CSC", name: "Computer Science", faculty: "SCI" }, { code: "BIO", name: "Biology", faculty: "SCI" }]);
  assert.deepEqual(org.programmes, [{ code: "C100", name: "B.Sc. Computer Science", faculty: "SCI", dept: "CSC" }]);
});

test("no structure (the call failed, or the office has none) is no options, never an error", () => {
  assert.deepEqual(orgFromStructure(null), { faculties: [], departments: [], programmes: [] });
  assert.deepEqual(orgFromStructure(undefined), { faculties: [], departments: [], programmes: [] });
  assert.deepEqual(orgFromStructure({ faculties: [{ code: "X", name: "X" }] } as never), { faculties: [{ code: "X", name: "X" }], departments: [], programmes: [] });
});

test("the options a queue's facets carry are used as they are", () => {
  const f = { faculties: [{ code: "SCI", name: "Science" }], departments: [{ code: "CSC", name: "Computer Science" }], programmes: [{ code: "C100", name: "B.Sc." }] };
  assert.deepEqual(orgFromFacets(f), f);
});
