/* ══════════════════════════════════════════════════════════════════════
   MOAUMPP — the service that serves the prototype.

   No dependencies, deliberately. This process serves one HTML file and
   answers a health check; every package it does not have is a package
   nobody has to patch, and a University portal's first deployment is not
   the place to acquire a supply chain.

   ── /healthz ──────────────────────────────────────────────────────────
   Reports what is actually true, not "ok". If the database is reachable
   it says which migrations are applied and whether the admission settings
   are in force; if it is not reachable it says so and STILL returns 200,
   because the prototype is servable without it and a health check that
   fails the whole service over a detail nobody is using is a health check
   that gets switched off. /readyz is the strict one.
   ══════════════════════════════════════════════════════════════════════ */
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");

const PORT = Number(process.env.PORT) || 8080;
const ROOT = path.join(__dirname, "..", "public");
const INDEX = path.join(ROOT, "index.html");

const STARTED = new Date();
const COMMIT = process.env.RAILWAY_GIT_COMMIT_SHA || process.env.GIT_COMMIT || "";

/* Read the file once at boot. It is 1.4 MB and it does not change while
   the process lives — re-reading it per request would be a slower answer
   to a question already answered. */
let PAGE = null;
let PAGE_ERR = "";
try {
  PAGE = fs.readFileSync(INDEX);
} catch (e) {
  PAGE_ERR = String(e.message || e);
}

const TYPES = {
  ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml",
  ".ico": "image/x-icon", ".webmanifest": "application/manifest+json"
};

/* Ask the database what it is. Uses psql, which is in the image because
   the migrations need it — one tool, not two. */
/* What a failed psql says is shown on a public URL. execFile puts the whole
   command line — the connection string, password included — into
   err.message, so only psql's own stderr is reported, and any connection
   string that appears anywhere in it is redacted. */
function redact(text) {
  const t = String(text || "")
    .replace(/postgres(?:ql)?:\/\/[^\s'"]+/g, "postgres://[redacted]")
    .replace(/^Command failed:.*$/m, "")
    .trim();
  return t || "psql failed";
}

function dbState(cb) {
  if (!process.env.DATABASE_URL) {
    return cb({ reachable: false, why: "DATABASE_URL is not set on this service" });
  }
  execFile("psql", [process.env.DATABASE_URL, "-tAq", "--no-psqlrc", "-c",
    "SELECT (SELECT count(*) FROM public.schema_migration) || '|' || " +
    "coalesce((SELECT max(filename) FROM public.schema_migration), '-') || '|' || " +
    "coalesce((SELECT state FROM admissions.session_policy WHERE session = '2025/2026'), '-')"],
    { timeout: 4000 }, function (err, out, stderr) {
      if (err) { return cb({ reachable: false, why: redact(stderr || err.message || err) }); }
      const p = String(out).trim().split("|");
      cb({ reachable: true, migrations: Number(p[0]) || 0, latest: p[1],
           admissionSettings2025_2026: p[2] });
    });
}

function send(res, code, type, body, extra) {
  const h = Object.assign({ "Content-Type": type, "Content-Length": Buffer.byteLength(body),
                            "X-Content-Type-Options": "nosniff" }, extra || {});
  res.writeHead(code, h);
  res.end(body);
}

const server = http.createServer(function (req, res) {
  const url = new URL(req.url, "http://x");
  const p = decodeURIComponent(url.pathname);

  if (p === "/healthz" || p === "/readyz") {
    return dbState(function (db) {
      const body = JSON.stringify({
        service: "moaumpp-portal",
        prototype: PAGE ? "served" : "MISSING: " + PAGE_ERR,
        started: STARTED.toISOString(),
        uptimeSeconds: Math.round(process.uptime()),
        commit: COMMIT ? COMMIT.slice(0, 12) : "unknown",
        database: db
      }, null, 2) + "\n";
      /* readyz is strict: it is not ready if it cannot serve the page, or
         if the database is attached but unreachable. */
      const strictBad = !PAGE || (process.env.DATABASE_URL && !db.reachable);
      const code = p === "/readyz" ? (strictBad ? 503 : 200) : (PAGE ? 200 : 503);
      send(res, code, "application/json; charset=utf-8", body,
           { "Cache-Control": "no-store" });
    });
  }

  if (p === "/" || p === "/index.html") {
    if (!PAGE) {
      return send(res, 503, "text/plain; charset=utf-8",
        "The prototype was not found in this build.\n\n" + PAGE_ERR + "\n\n" +
        "public/index.html is built from proto/part*.html by proto/build.py and is " +
        "committed to the repository. If it is missing, the build is incomplete.\n");
    }
    return send(res, 200, "text/html; charset=utf-8", PAGE, {
      "Cache-Control": "no-cache",
      /* The page is one self-contained file. The only thing it fetches from
         anywhere else is the typeface, from Google Fonts — which the strict
         policy blocked on the first run, and which is worth writing down
         rather than quietly allowing: it means this University's portal
         calls a third party on every page load, and it means the page
         renders in its fallback stack whenever that third party is
         unreachable from Makurdi. The fallback is real and the page is
         perfectly legible in it, so this is safe; but before production the
         two font files should be served from here instead. Everything else
         — scripts, frames, connections, forms — is refused outright. */
      "Content-Security-Policy":
        "default-src 'none'; img-src 'self' data:; " +
        "style-src 'unsafe-inline' https://fonts.googleapis.com; " +
        "script-src 'unsafe-inline'; " +
        "font-src data: https://fonts.gstatic.com; " +
        "connect-src 'none'; form-action 'none'; " +
        "frame-ancestors 'self'; base-uri 'none'",
      "Referrer-Policy": "no-referrer",
      "X-Frame-Options": "SAMEORIGIN"
    });
  }

  /* anything else under public/, with the path resolved and then checked
     to be inside it — a path is not safe because it looked safe */
  const want = path.normalize(path.join(ROOT, p));
  if (want.startsWith(ROOT + path.sep) && fs.existsSync(want) && fs.statSync(want).isFile()) {
    return send(res, 200, TYPES[path.extname(want)] || "application/octet-stream",
                fs.readFileSync(want), { "Cache-Control": "public, max-age=300" });
  }

  send(res, 404, "text/plain; charset=utf-8", "Not found: " + p + "\n");
});

server.listen(PORT, "0.0.0.0", function () {
  console.log("moaumpp-portal listening on " + PORT +
              (PAGE ? " — prototype " + (PAGE.length / 1024).toFixed(0) + " KB"
                    : " — WITHOUT the prototype: " + PAGE_ERR));
});

/* Railway stops a container with SIGTERM. Finish what is in flight. */
["SIGTERM", "SIGINT"].forEach(function (sig) {
  process.on(sig, function () {
    console.log(sig + " — closing");
    server.close(function () { process.exit(0); });
    setTimeout(function () { process.exit(0); }, 8000).unref();
  });
});
