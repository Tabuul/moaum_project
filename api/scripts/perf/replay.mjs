// Replays student (or applicant) page navigations against the measurement API on the live-shaped copy, the way the portal's frontend makes them:
// the proxy's session check, then the page's calls in their stages (calls in one stage run together, stages one after another).
// usage: node replay.mjs <people.txt> <pages.json> <navigations per person> <concurrency> <out.json> [office] [base]
// pages.json: { "<page>": { "weight": n, "stages": [["GET /api/v1/..."], ["GET ...", "GET ..."]] } } — {session} is filled in.
import { readFileSync, writeFileSync } from "node:fs";
import { token } from "./tok.mjs";

const [studentsFile, pagesFile, perStudentArg, concArg, outFile, officeArg, baseArg] = process.argv.slice(2);
const office = officeArg ?? "student";
const base = baseArg ?? "http://127.0.0.1:8764";
const students = readFileSync(studentsFile, "utf8").trim().split(/\r?\n/).map((l) => l.split("|"));
const pages = JSON.parse(readFileSync(pagesFile, "utf8"));
const perStudent = Number(perStudentArg ?? 5);
const conc = Number(concArg ?? 8);
const session = process.env.SESSION ?? "2025/2026";

// a fixed, seeded sequence of pages by weight, so a run before and a run after a change replay the same navigations
let seed = 7631;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const names = Object.keys(pages);
const total = names.reduce((a, n) => a + pages[n].weight, 0);
const pick = () => { let x = rnd() * total; for (const n of names) { x -= pages[n].weight; if (x < 0) return n; } return names[names.length - 1]; };

const jobs = [];
for (const [sub, sid] of students) for (let i = 0; i < perStudent; i++) jobs.push({ sub, sid, page: pick() });

const stats = { calls: 0, byStatus: {}, byPage: {}, byCall: {}, errors: [] };
async function call(spec, auth) {
  const [method, path] = spec.split(" ");
  const url = base + path.replaceAll("{session}", encodeURIComponent(session));
  const t0 = performance.now();
  let status = 0;
  try {
    const r = await fetch(url, { method, headers: { authorization: `Bearer ${auth}`, "x-active-office": office } });
    status = r.status; await r.arrayBuffer();
  } catch (e) { status = -1; if (stats.errors.length < 20) stats.errors.push(`${spec}: ${e.message}`); }
  const ms = performance.now() - t0;
  stats.calls++; stats.byStatus[status] = (stats.byStatus[status] ?? 0) + 1;
  const k = `${method} ${path.split("?")[0]}`;
  const c = (stats.byCall[k] ??= { n: 0, ms: 0, statuses: {} }); c.n++; c.ms += ms; c.statuses[status] = (c.statuses[status] ?? 0) + 1;
  return ms;
}

async function navigate(job) {
  const auth = token(job.sub, job.sid, [office]);
  const t0 = performance.now();
  for (const stage of [["GET /api/v1/iam/session"], ...pages[job.page].stages]) await Promise.all(stage.map((s) => call(s, auth)));
  const p = (stats.byPage[job.page] ??= { n: 0, ms: 0 }); p.n++; p.ms += performance.now() - t0;
}

const t0 = performance.now();
let next = 0;
await Promise.all(Array.from({ length: conc }, async () => { while (next < jobs.length) await navigate(jobs[next++]); }));
const seconds = (performance.now() - t0) / 1000;
const summary = { navigations: jobs.length, calls: stats.calls, seconds: Math.round(seconds), byStatus: stats.byStatus,
  byPage: Object.fromEntries(Object.entries(stats.byPage).map(([k, v]) => [k, { n: v.n, avgMs: Math.round(v.ms / v.n) }])),
  byCall: Object.fromEntries(Object.entries(stats.byCall).sort((a, b) => b[1].ms - a[1].ms).map(([k, v]) => [k, { n: v.n, avgMs: Math.round(v.ms / v.n), statuses: v.statuses }])),
  errors: stats.errors };
writeFileSync(outFile, JSON.stringify(summary, null, 1));
console.log(JSON.stringify({ navigations: summary.navigations, calls: summary.calls, seconds: summary.seconds, byStatus: summary.byStatus }));
