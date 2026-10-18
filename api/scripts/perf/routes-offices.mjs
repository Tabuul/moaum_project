// node --experimental-strip-types routes_offices.mjs <out.json>  (run from frontend/): each menu path → the offices whose menu reaches it
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const { MENUS } = await import(pathToFileURL(process.cwd() + "/src/lib/menus.ts").href);
const shell = fs.readFileSync("src/components/proto/Shell.tsx", "utf8");
const start = shell.indexOf("export const ROUTES");
const block = shell.slice(start, shell.indexOf("};", start));
const ROUTES = Object.fromEntries([...block.matchAll(/^\s*"([^"]+)":\s*"([^"]+)",?$/gm)].map((m) => [m[1], m[2]]));
const byPath = {};
for (const [office, menu] of Object.entries(MENUS)) {
  for (const g of menu.groups) for (const it of g.items) {
    const p = it.id === menu.home ? "/" : ROUTES[it.id];
    if (!p) continue;
    (byPath[p.split("?")[0]] ??= new Set()).add(office);
  }
}
const out = Object.fromEntries(Object.entries(byPath).map(([p, s]) => [p, [...s]]));
fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 1));
console.log("paths", Object.keys(out).length, "offices", Object.keys(MENUS).length);
