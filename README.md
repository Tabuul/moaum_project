# MOAUMPP

**MOAUM Unified University Portal** — Rev. Fr. Moses Orshio Adasu University, Makurdi
Directorate of ICT

---

## What is in here

| | |
|---|---|
| `proto/` | The working prototype: 56 parts, concatenated by `build.py` into one self-contained HTML file. `part6.html` is **always last** — it closes the IIFE and calls `render()`. |
| `public/index.html` | That file, built and committed. It is what gets served. |
| `db/` | Ten migrations, a read-only deployment verification, and `check.sql` — 63 properties the schema asserts about itself. |
| `web/server.js` | The service. No dependencies, deliberately. |
| `Dockerfile` | node:22-slim plus the postgresql client, because the migrations are psql scripts. |
| `railway.json` | Build, start, pre-deploy and health check. |
| `.github/workflows/ci.yml` | The three gates below. |

## Running it locally

```bash
# the page
npm run build                 # rebuild public/index.html from proto/part*.html
npm start                     # serve it on :8080

# the database
createdb moaumpp
export DATABASE_URL=postgres:///moaumpp
npm run migrate               # applies V001–V010, then verify.sql
npm run check:db              # the 63 properties — WRITES, use a throwaway database

# the browser harnesses (needs playwright + chromium)
node proto/runall.mjs
```

## What CI enforces

Railway is set to deploy only what has passed. Three gates:

**1 · The build is reproducible.** `public/index.html` is rebuilt from the parts and compared byte for byte. Without this, somebody edits the built file, the harnesses pass against the parts, and the thing deployed is a file nobody tested.

**2 · Eleven browser harnesses.** 600+ screen loads, every office, every route, five viewport widths, and every control checked for being bound to something. They have caught, among other things: a route enumeration that missed collapsed navigation groups; a table that stacked at the wrong width; and a refusal that was rendered nowhere at all.

**3 · The database properties.** A real Postgres 17, the migrations applied by the same runner Railway uses, then `check.sql`. It reports **how many checks RAN** as well as how many failed — because a `DO` block that errors never reaches its assertion and would otherwise be counted as a pass. CI additionally proves that a second migration run is a no-op, and that a migration edited after it was applied **stops the deployment**.

Seven checks are **skipped** unless `MOAUM_FIXTURES` points at the real JAMB sample files. Those files carry real candidates' names, registration numbers, scores and local governments, and are not in this repository and never will be. The skip is printed and counted; a check that quietly does not run is worse than one that fails.

## The migration runner

`db/migrate.sh` keeps a ledger in `public.schema_migration`: filename, SHA-256, when, and by which role.

- already applied, unchanged → skipped
- never applied → applied, in its own transaction
- **applied before and the file has since changed → the deployment stops, by name**

That last one is the point. A migration edited after it has been applied leaves production and the repository describing two different databases, and nothing anywhere says so. Corrections go in a new file.

`check.sql` is **not** run on deployment. It creates people, policies and credentials and deliberately tampers with an audit row; it belongs in CI against a throwaway database. What runs after a real deployment is `db/verify.sql`, which only reads — and which asserts, on every deploy, that no application role holds `DELETE` anywhere, that nothing may write to `audit.*`, and that **an unattributed write is still refused**. That last property is the one the whole design rests on, so it is checked rather than assumed to have survived.

## Getting this onto GitHub

The repository lives at **https://github.com/Tabuul/moaum_project**.

From a clone of the bundle:

```bash
git clone moaumpp.bundle moaum_project
cd moaum_project
git remote set-url origin https://github.com/Tabuul/moaum_project.git
git push -u origin main
```

If GitHub created the repository with a README or a licence, that first push is
rejected because the two histories are unrelated. The repository is new and the
only thing in it is GitHub's own generated file, so the honest fix is to replace
it:

```bash
git push -u origin main --force
```

Use `--force` **only** on this first push, and only while the repository holds
nothing but GitHub's generated files. After that it would discard somebody's work.

## Deploying on Railway

Two services in one project.

**1 · Postgres.** Add it from Railway's catalogue. Nothing else to configure.

**2 · The portal.** Deploy from this repository.

- Railway reads `railway.json`: Dockerfile build, `bash db/migrate.sh` as the **pre-deploy command**, `node web/server.js` to start, `/healthz` as the health check.
- The migrations run as a pre-deploy command rather than at container start, so a crash-looping container cannot run them over and over.
- **Variables → add a reference to the Postgres service's `DATABASE_URL`.** Without it the service still serves the page and `/healthz` says the database is not attached; `/readyz` returns 503.
- Generate a domain under Settings → Networking.

Then, so that only green commits deploy: **Settings → Deploy → wait for CI to pass** (Railway calls it *Check Suites* / *Wait for CI*). Point it at the `CI` workflow. Without that setting Railway deploys every push to `main` regardless of the gates above.

### Health

| | |
|---|---|
| `/healthz` | Always 200 while the page can be served. Reports migrations applied, the latest one, and whether the 2025/2026 admission settings are a draft or in force. A health check that fails the whole service over a detail nobody is using is a health check that gets switched off. |
| `/readyz` | Strict: 503 if the page is missing, or if `DATABASE_URL` is set and the database cannot be reached. |

### About the Postgres role

`V001` creates one `app_*` role per module. Railway's Postgres gives you a superuser, so this works — but if you point this at a managed database where you are not a superuser, role creation will fail and the deployment will stop there rather than half-applying. That is the intended behaviour.

## Two things to know before this URL is shared

**The sample photographs are generated, not real.** Two real JAMB passports were embedded while the passport-matching screen was being built. They are photographs of two identifiable nineteen-year-olds, and this file is served from a public URL, so they are gone — replaced by drawn images at exactly the size JAMB sends (132 × 151 px, about 4 KB), because the *size* was the point and the faces never were. Everything else in the samples is invented for the same reason: no real name, registration number or result appears anywhere in this repository.

**The typeface comes from Google Fonts.** The content security policy allows `fonts.googleapis.com` and `fonts.gstatic.com` and nothing else. It means the portal calls a third party on every page load, and that the page falls back to system fonts whenever that third party is unreachable from Makurdi. The fallback is real and the page is perfectly legible in it — but before production, serve the two font files from here instead.

## What this is not, yet

The Spring Boot application. It is not in this repository because it has not been built: Maven Central was unreachable from the environment this was developed in. The deployment shape here — a service that migrates before it serves, behind a gate that will not let an untested build through — is the shape it will slot into.
