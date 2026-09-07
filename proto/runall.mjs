/* ══════════════════════════════════════════════════════════════════════
   Every browser harness, in one run, with one exit code.

   Two things this does that a plain `for` loop would not:

   · it REBUILDS the prototype from its parts first, and refuses to run if
     the committed public/index.html differs from what the parts produce.
     Otherwise somebody hand-edits the built file, the harnesses pass
     against the parts, and the thing actually deployed is a file nobody
     tested.

   · it counts SKIPS and prints them in the summary. The two harnesses
     that read real JAMB files skip those checks when MOAUM_FIXTURES is
     unset — which is right, because the real files carry real
     candidates and are not in the repository — but a check that quietly
     does not run is worse than one that fails.
   ══════════════════════════════════════════════════════════════════════ */
import { execFileSync, execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HARNESSES = ["acheck", "ccheck", "echeck", "wcheck", "vcheck", "pmob",
                   "capsfile", "cdcheck", "regcheck", "admcheck", "sq"];

const HERE = path.dirname(fileURLToPath(import.meta.url));
process.chdir(HERE);

/* ── 1 · the build is reproducible ──────────────────────────────────── */
console.log("── rebuilding from the parts ──────────────────────────────────");
/* python3 on Linux and macOS; on Windows the interpreter is usually just python */
const PY = ["python3", "python"].find(function (p) {
  try { return /Python 3/.test(execFileSync(p, ["--version"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })); }
  catch (e) { return false; }
});
if (!PY) { console.error("!! no Python 3 interpreter found (tried python3, python)"); process.exit(2); }
execSync(PY + " build.py", { stdio: "inherit" });

const built = "moaum-portal-prototype.html";
const committed = path.join(HERE, "..", "public", "index.html");
if (fs.existsSync(committed)) {
  const a = fs.readFileSync(built), b = fs.readFileSync(committed);
  if (!a.equals(b)) {
    console.error(
      "\n!! public/index.html is NOT what the parts build.\n" +
      "   built from parts: " + a.length + " bytes\n" +
      "   committed:        " + b.length + " bytes\n\n" +
      "   The file that would be deployed is not the file these harnesses\n" +
      "   test. Run `npm run build` and commit the result.\n");
    process.exit(2);
  }
  console.log("   public/index.html matches the parts (" +
              (a.length / 1024).toFixed(0) + " KB)\n");
} else {
  console.log("   no public/index.html to compare against — skipping that check\n");
}

/* ── 2 · every harness ──────────────────────────────────────────────── */
let failed = [], skipped = 0;

for (const h of HARNESSES) {
  process.stdout.write("── " + h + " ");
  let out = "";
  try {
    out = execFileSync("node", [h + ".mjs"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    const m = /(\d+) skipped/.exec(out);
    if (m) { skipped += Number(m[1]); }
    const last = out.trim().split("\n").pop();
    console.log("· " + last.trim());
  } catch (e) {
    failed.push(h);
    console.log("· FAILED");
    console.log((e.stdout || "") + (e.stderr || ""));
  }
}

console.log("\n═══════════════════════════════════════════════════════════════");
if (failed.length) {
  console.log(failed.length + " of " + HARNESSES.length + " harnesses FAILED: " + failed.join(", "));
} else {
  console.log("all " + HARNESSES.length + " harnesses green" +
              (skipped ? " — " + skipped + " checks skipped, needing the real JAMB " +
                         "files (set MOAUM_FIXTURES)" : ""));
}
process.exit(failed.length ? 1 : 0);
