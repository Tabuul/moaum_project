// node crawl-some.mjs <jobs.json [[path, office]...]> <out.jsonl> <base url> <token> [rounds]
// The pages named opened one at a time, each twice (the first load and a second), their status and time written as lines.
import fs from "node:fs";
const [, , jobsPath, outPath, base, token, roundsArg] = process.argv;
const jobs = JSON.parse(fs.readFileSync(jobsPath, "utf8"));
const rounds = Number(roundsArg || 2);
const out = fs.createWriteStream(outPath, { flags: "w" });
for (const [path, office] of jobs) {
  for (let round = 1; round <= rounds; round++) {
    const t0 = Date.now();
    let status = 0, err = null;
    try {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 240000);
      const r = await fetch(base + path, { headers: { cookie: `moaum_session=${token}; moaum_office=${office}` }, redirect: "manual", signal: ctl.signal });
      await r.text();
      clearTimeout(timer);
      status = r.status;
    } catch (e) { err = String(e && e.name === "AbortError" ? "timeout 240 s" : e); }
    const ms = Date.now() - t0;
    out.write(JSON.stringify({ path, office, round, status, ms, err, at: new Date().toISOString() }) + "\n");
    console.log(`${ms} ms ${status} ${office} ${path} (round ${round})${err ? " " + err : ""}`);
  }
}
out.end();
