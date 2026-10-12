import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { MENUS } from "./menus.ts";
import { byCategory, menuIds, menuItem, pieces, plain, search, unresolved, type Procedure } from "./manual.ts";
import { manualHtml } from "./manual-html.ts";

const here = import.meta.dirname ?? ".";
const shell = readFileSync(join(here, "../components/proto/Shell.tsx"), "utf8");
const ROUTES: Record<string, string> = Object.fromEntries([...shell.matchAll(/^\s*"([^"]+)":\s*"([^"]+)",?$/gm)].map((m) => [m[1], m[2]]));

const proc = (over: Partial<Procedure>): Procedure => ({
  id: "x", slug: "x", title: "X", purpose: "P", category: "ACADEMICS", offices: ["student"], capabilities: [], menu_id: null, route: null,
  steps: [], expected: "E", sort_order: 1, state: "PUBLISHED", version: 1, ...over,
});

test("a step's {menu:id} resolves to the sidebar's own label and page, and a control stays as the screen names it", () => {
  const ps = pieces("Open {menu:s/register}; click `Register courses`.", ["student"], ROUTES);
  assert.deepEqual(ps.map((p) => p.kind), ["text", "menu", "text", "control", "text"]);
  const m = ps[1]; assert.equal(m.kind, "menu"); if (m.kind === "menu") { assert.equal(m.label, "Course Registration"); assert.equal(m.href, "/student/register"); assert.equal(m.missing, false); }
  assert.equal(plain("Open {menu:s/register}; click `Register courses`.", ["student"]), "Open Course Registration; click `Register courses`.");
});

test("the label is the reader's own sidebar's first: the Faculty Exams Officer's Scrutiny Desk is the Head's Result Desk", () => {
  assert.equal(menuItem("t/resultdesk", ["facultyexams"])?.label, "Scrutiny Desk");
  assert.equal(menuItem("t/resultdesk", ["hod"])?.label, "Result Desk");
  assert.equal(menuItem("t/nothing-of-the-kind", ["hod"]), null);
  const ps = pieces("Open {menu:t/nothing-of-the-kind}.", ["hod"], ROUTES);
  assert.equal(ps[1].kind, "menu"); if (ps[1].kind === "menu") assert.equal(ps[1].missing, true);
});

test("the search reads the resolved labels, and the categories keep the manual's order", () => {
  const rows = [proc({ slug: "a", title: "Register courses", category: "ACADEMICS", steps: ["Open {menu:s/register}."] }), proc({ slug: "b", title: "Pay school fees", category: "PAYMENTS", steps: ["Open {menu:s/fees}."] })];
  assert.deepEqual(search(rows, "course registration", ["student"]).map((r) => r.slug), ["a"]);
  assert.deepEqual(search(rows, "fees", ["student"]).map((r) => r.slug), ["b"]);
  assert.deepEqual(byCategory(rows).map((g) => g.category), ["PAYMENTS", "ACADEMICS"]);
});

test("Manual Management's validation names a reference the office's menu does not carry", () => {
  assert.deepEqual(unresolved(proc({ offices: ["student"], steps: ["Open {menu:s/register}."] }), ROUTES), []);
  assert.deepEqual(unresolved(proc({ offices: ["bursar"], steps: ["Open {menu:s/register}."] }), ROUTES), [{ id: "s/register", where: "not on the bursar menu" }]);
  assert.deepEqual(unresolved(proc({ offices: ["everyone"], steps: ["Open {menu:zz/none}."] }), ROUTES), [{ id: "zz/none", where: "no page" }]);
  assert.deepEqual(menuIds(proc({ menu_id: "s/fees", route: "s/dashboard", steps: ["{menu:s/fees} and {menu:s/results}"] })), ["s/fees", "s/dashboard", "s/results"]);
});

test("the printed sheet carries purpose, numbered steps with the portal's labels, and the expected result", () => {
  const html = manualHtml([proc({ title: "Register courses", steps: ["Open {menu:s/register}; click `Register courses`."] })], ["student"]);
  assert.match(html, /<h3[^>]*>Register courses<\/h3>/);
  assert.match(html, /<li>Open <b>Course Registration<\/b>; click <code>Register courses<\/code>\.<\/li>/);
  assert.match(html, /Expected result:<\/b> E/);
});

test("every {menu:…} the manual's migrations seed (V387, V411…) or revise names a menu item the bound offices carry, and every office named is one the portal knows", () => {
  const dbDir = join(here, "../../../db");
  const files = readdirSync(dbDir).filter((f) => /^V\d+__.*\.sql$/.test(f)).sort((a, b) => parseInt(a.slice(1), 10) - parseInt(b.slice(1), 10));
  assert.ok(files.some((f) => f.startsWith("V387__")), "the V387 migration is in db/");
  const SEED = /SELECT manual\.seed\('([^']+)', '(?:[^']|'')*', '[A-Z]+', ARRAY\[([^\]]+)\]::text\[\], (NULL|'[^']+'), (NULL|'[^']+'),\s*'(?:[^']|'')*',\s*ARRAY\[([\s\S]*?)\],\s*'(?:[^']|'')*'/g;
  // V411: a first-edition procedure revised in place keeps its offices; its new steps are checked against them
  const REVISE = /SELECT pg_temp\.manual_revise\('([^']+)', '(?:[^']|'')*',\s*'(?:[^']|'')*',\s*ARRAY\[([\s\S]*?)\],\s*'(?:[^']|'')*'\);/g;
  const offices = new Map<string, string[]>();
  const refs: { slug: string; ids: Set<string> }[] = [];
  let first = 0;
  for (const f of files) {
    const sql = readFileSync(join(dbDir, f), "utf8");
    if (!sql.includes("manual.seed(") && !sql.includes("pg_temp.manual_revise(")) continue;
    for (const c of sql.matchAll(SEED)) {
      if (f.startsWith("V387__")) first++;
      if (!offices.has(c[1])) offices.set(c[1], [...c[2].matchAll(/'([^']+)'/g)].map((m) => m[1]));
      const ids = new Set<string>();
      if (c[3] !== "NULL") ids.add(c[3].slice(1, -1));
      if (c[4] !== "NULL") ids.add(c[4].slice(1, -1));
      for (const m of c[5].matchAll(/\{menu:([^}]+)\}/g)) ids.add(m[1].trim());
      refs.push({ slug: c[1], ids });
    }
    for (const c of sql.matchAll(REVISE)) {
      assert.ok(offices.has(c[1]), `${f}: ${c[1]} revises a procedure no earlier migration seeds`);
      refs.push({ slug: c[1], ids: new Set([...c[2].matchAll(/\{menu:([^}]+)\}/g)].map((m) => m[1].trim())) });
    }
  }
  assert.ok(first >= 200, `the first edition has ${first} procedures`);
  const sidebars = new Set(Object.keys(MENUS));
  const problems: string[] = [];
  for (const { slug, ids } of refs) {
    for (const id of ids) {
      if (!ROUTES[id]) problems.push(`${slug}: ${id} has no page`);
      for (const o of offices.get(slug) ?? []) {
        if (o === "everyone" || !sidebars.has(o)) continue;
        if (!MENUS[o].groups.some((g) => g.items.some((it) => it.id === id))) problems.push(`${slug}: ${id} is not on the ${o} menu`);
      }
    }
  }
  assert.deepEqual(problems, []);
});
