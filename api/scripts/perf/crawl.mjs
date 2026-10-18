// node crawl.mjs <routes-offices.json> <out.jsonl> <base url> <token> [offices]
// [offices]: the offices the token holds, comma-separated (default: every staff office below)
// Every menu page opened once (server-rendered, as a browser's first load), as the widest office of ours whose menu has it;
// every office's home page too. Each page's status and time are written as a line; the database logs its slow statements.
import fs from "node:fs";

const [, , mapPath, outPath, base, token, officesArg] = process.argv;
const map = JSON.parse(fs.readFileSync(mapPath, "utf8"));
const HELD = (officesArg || "academic,admin,alumni,audit,bursar,cce,collegesecretary,dean,deputyaudit,dregistrar,dsa,dvc,eps,exams,facultyexams,facultyofficer,financecontroller,gst,helpdeskhead,hod,housing,hrm,ict,ictagent,jupeb,lecturer,library,pgschool,pgsecretary,prelim,provost,records,registrar,sandwich,security,services,siwes,super,vc").split(",");
const WIDE = ["registrar", "academic", "bursar", "super", "ict", "admin", "dvc", "vc", "dregistrar", "records", "audit", "deputyaudit", "pgschool", "cce", "gst", "eps", "hrm"];
const pick = (offices) => WIDE.find((o) => offices.includes(o)) ?? offices.find((o) => HELD.includes(o));

const jobs = [];
for (const [path, offices] of Object.entries(map)) {
  if (path === "/") continue;
  const o = pick(offices);
  if (o) jobs.push([path, o]);
}
for (const o of HELD) jobs.push(["/", o]);

const out = fs.createWriteStream(outPath, { flags: "w" });
let n = 0;
for (const [path, office] of jobs) {
  const t0 = Date.now();
  let status = 0, bytes = 0, err = null;
  try {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 240000);
    const r = await fetch(base + path, { headers: { cookie: `moaum_session=${token}; moaum_office=${office}` }, redirect: "manual", signal: ctl.signal });
    const body = await r.text();
    clearTimeout(timer);
    status = r.status; bytes = body.length;
    if (/QUERY_TOO_LONG|took longer than the portal allows/.test(body)) err = "QUERY_TOO_LONG shown";
  } catch (e) { err = String(e && e.name === "AbortError" ? "timeout 240 s" : e); }
  const ms = Date.now() - t0;
  out.write(JSON.stringify({ path, office, status, ms, bytes, err, at: new Date().toISOString() }) + "\n");
  n++;
  if (ms > 10000 || err) console.log(`${ms} ms ${status} ${office} ${path}${err ? " " + err : ""}`);
}
out.end();
console.log(`done ${n} pages`);
