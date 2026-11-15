// calls one endpoint once for each person in the list, 8 at a time: node one.mjs <people.txt> "<METHOD> <path>" <office> <api base>
import { readFileSync } from "node:fs";
import { token } from "./tok.mjs";
const [file, spec, office, base] = process.argv.slice(2);
const people = readFileSync(file, "utf8").trim().split(/\r?\n/).map((l) => l.split("|"));
const [method, path] = spec.split(" ");
const statuses = {};
let i = 0;
await Promise.all(Array.from({ length: 8 }, async () => {
  while (i < people.length) {
    const [sub, sid] = people[i++];
    const r = await fetch(base + path.replaceAll("{session}", encodeURIComponent(process.env.SESSION ?? "2025/2026")), { method, headers: { authorization: `Bearer ${token(sub, sid, [office])}`, "x-active-office": office } });
    await r.arrayBuffer(); statuses[r.status] = (statuses[r.status] ?? 0) + 1;
  }
}));
console.log(JSON.stringify(statuses));
