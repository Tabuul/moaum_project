// The same endpoint for the same person from the old API (old code, old database functions) and the new one, the JSON compared:
// usage: OLD_API=http://… NEW_API=http://… node compare.mjs <people.txt> <office> <endpoint> [<endpoint> ...]   ({session} is filled in)
import { readFileSync } from "node:fs";
import { token } from "./tok.mjs";

const OLD = process.env.OLD_API ?? "http://127.0.0.1:8766", NEW = process.env.NEW_API ?? "http://127.0.0.1:8764";
const [file, office, ...endpoints] = process.argv.slice(2);
const people = readFileSync(file, "utf8").trim().split(/\r?\n/).map((l) => l.split("|"));
const VOLATILE = new Set(["correlationId"]);

function diffs(a, b, path, out) {
  if (out.length > 20) return;
  if (a === b) return;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== "object") { out.push(`${path}: ${JSON.stringify(a)?.slice(0, 80)} -> ${JSON.stringify(b)?.slice(0, 80)}`); return; }
  if (Array.isArray(a) !== Array.isArray(b)) { out.push(`${path}: array/object`); return; }
  if (Array.isArray(a)) {
    if (a.length !== b.length) out.push(`${path}: length ${a.length} -> ${b.length}`);
    for (let i = 0; i < Math.min(a.length, b.length); i++) diffs(a[i], b[i], `${path}[${i}]`, out);
    return;
  }
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (VOLATILE.has(k)) continue;
    if (!(k in a)) out.push(`${path}.${k}: added`); else if (!(k in b)) out.push(`${path}.${k}: removed`); else diffs(a[k], b[k], `${path}.${k}`, out);
  }
}

for (const ep of endpoints) {
  const path = ep.replaceAll("{session}", encodeURIComponent(process.env.SESSION ?? "2025/2026"));
  let same = 0, differ = 0, statusDiff = 0, refused = 0;
  const kinds = new Map();
  let i = 0;
  await Promise.all(Array.from({ length: 6 }, async () => {
    while (i < people.length) {
      const [sub, sid] = people[i++];
      const h = { authorization: `Bearer ${token(sub, sid, [office])}`, "x-active-office": office };
      const [ro, rn] = await Promise.all([fetch(OLD + path, { headers: h }), fetch(NEW + path, { headers: h })]);
      const [to, tn] = await Promise.all([ro.text(), rn.text()]);
      if (ro.status !== rn.status) { statusDiff++; kinds.set(`status ${ro.status}->${rn.status}`, (kinds.get(`status ${ro.status}->${rn.status}`) ?? 0) + 1); continue; }
      // both refused alike (a token the APIs do not take, a session gone idle): nothing was compared — said, never counted as the same
      if (ro.status >= 300) { refused++; kinds.set(`both ${ro.status}`, (kinds.get(`both ${ro.status}`) ?? 0) + 1); continue; }
      let a, b;
      try { a = JSON.parse(to); b = JSON.parse(tn); } catch { a = to; b = tn; }
      const out = [];
      diffs(a, b, "", out);
      if (out.length === 0) same++; else { differ++; for (const d of out) { const k = d.replace(/\[\d+\]/g, "[]").replace(/: .*/, ""); kinds.set(k, (kinds.get(k) ?? 0) + 1); } }
    }
  }));
  console.log(`${ep}  answered by both ${same + differ}: same ${same}, different ${differ} | status differs ${statusDiff} | both refused ${refused}`);
  if (same + differ === 0) console.log("    NOTHING COMPARED: no person got an answer from both APIs");
  for (const [k, n] of [...kinds.entries()].sort((x, y) => y[1] - x[1]).slice(0, 8)) console.log(`    ${n} × ${k}`);
}
