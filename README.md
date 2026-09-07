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
| `web/server.js` | The prototype's server. No dependencies, deliberately. |
| `api/` | **The Spring Boot service** — Java 21, Spring Boot 4.1, Spring Modulith, plain JDBC. The request path (correlation id → token → acting office → the audit context on every transaction → problem responses), then `iam` and `admissions` begun. See `api/README.md`. |
| `frontend/` | **The Next.js frontend** — App Router, server-rendered, Tailwind; talks to the API only from the server (a BFF), with the prototype's palette and typeface, self-hosted. |
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

# the Spring Boot service (needs Java 21; Maven comes with the wrapper)
export MOAUM_AUTH_HMAC_SECRET='change-me-to-at-least-thirty-two-bytes-long'
(cd api && ./mvnw spring-boot:run)          # :8081 — see api/README.md for tokens and tests

# the Next.js frontend (needs Node 22)
(cd frontend && cp .env.example .env.local && npm ci && npm run dev)   # :3000
```

On Windows, `python` rather than `python3` is found automatically, and the
build folds CRLF to LF so the page it produces is byte-identical to CI's.

## What CI enforces

Railway is set to deploy only what has passed. Five gates:

**1 · The build is reproducible.** `public/index.html` is rebuilt from the parts and compared byte for byte. Without this, somebody edits the built file, the harnesses pass against the parts, and the thing deployed is a file nobody tested.

**2 · Eleven browser harnesses.** 600+ screen loads, every office, every route, five viewport widths, and every control checked for being bound to something. They have caught, among other things: a route enumeration that missed collapsed navigation groups; a table that stacked at the wrong width; and a refusal that was rendered nowhere at all.

**3 · The database properties.** A real Postgres 17, the migrations applied by the same runner Railway uses, then `check.sql`. It reports **how many checks RAN** as well as how many failed — because a `DO` block that errors never reaches its assertion and would otherwise be counted as a pass. CI additionally proves that a second migration run is a no-op, and that a migration edited after it was applied **stops the deployment**.

**4 · The API.** Compiles; the Spring Modulith boundary test holds; and against the same Postgres 17 with the migrations applied, `AuditSpineIT` proves an unattributed write is refused and an attributed one recorded, and `ApiIT` drives the request path end to end — a token refused, an office the token does not carry refused, a CAPS list loaded whole and a list-kind contradiction refused whole with the database's own remedy.

**5 · The frontend.** Lints, type-checks and builds.

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

One project, four services. Each service has its own config file and is built
from the repository root, so that an image can carry `db/` as well as its own
code. Railway reads the config file named in the service's settings. There is
deliberately no `railway.json` at the repository root: Railway would apply it
to every service that has not named its own, and every one of them would
build the prototype. Where the config-file setting does not take, the
service variable `RAILWAY_DOCKERFILE_PATH` (e.g. `frontend/Dockerfile`)
chooses the image, and the deploy settings are typed into the UI.

| service | config | image | what it is |
|---|---|---|---|
| `Postgres` | — | Railway's | the one database, many schemas |
| `moaum-api` | `api/railway.json` | `api/Dockerfile` | the Spring Boot service. **Owns the schema: its pre-deploy command runs `bash db/migrate.sh`.** |
| `moaum-portal` | `frontend/railway.json` | `frontend/Dockerfile` | the Next.js frontend. This is what gets the public domain. |
| `moaum-prototype` | `web/railway.json` | `Dockerfile` | the HTML prototype, until the frontend covers its screens |

**Creating a service from this repository.** Create → GitHub Repo → this
repository; then in the service's Settings: rename it; under *Config-as-code*
set the config file path (e.g. `api/railway.json`); leave *Root Directory*
empty; under *Build* set watch paths so only its own changes rebuild it
(`api/**` and `db/**` for the API, `frontend/**` for the portal,
`proto/**`, `public/**`, `web/**` for the prototype); under *Deploy* turn
on **Wait for CI** so only green commits deploy.

**Variables, by reference wherever possible.**

| service | variable | value |
|---|---|---|
| moaum-api | `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
| moaum-api | `PORT` | `8081` — fixed, so the frontend can find it on the private network |
| moaum-api | `MOAUM_AUTH_HMAC_SECRET` | a random string of at least 32 bytes, sealed — until Keycloak, when `MOAUM_AUTH_ISSUER_URI` replaces it |
| moaum-portal | `PORTAL_API_URL` | `http://moaum-api.railway.internal:8081` — private networking; API traffic never leaves Railway |
| moaum-portal | `PORTAL_API_TOKEN` | a token minted with the API's secret: `node api/scripts/dev-token.mjs --secret … --offices academic,registrar --ttl 7776000` |
| moaum-portal | `PORTAL_ACTIVE_OFFICE` | `academic` |
| moaum-prototype | `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (for `/healthz` only; it no longer migrates) |

A reference points at a service by id, not by name: if a service is ever
deleted and recreated, re-add the references that pointed at it.

**Exactly one service migrates.** The API's pre-deploy runs
`bash db/migrate.sh`; the prototype's must be empty. A deployment that
fails leaves the previous one serving, so a service that looks unchanged
from outside may have a failed deployment behind it — the Deployments tab
is where the truth is.

### Health

| | |
|---|---|
| `/healthz` | Always 200 while the page can be served. Reports migrations applied, the latest one, and whether the 2025/2026 admission settings are a draft or in force. A health check that fails the whole service over a detail nobody is using is a health check that gets switched off. |
| `/readyz` | Strict: 503 if the page is missing, or if `DATABASE_URL` is set and the database cannot be reached. |

### About the Postgres role

`V001` creates one `app_*` role per module. Railway's Postgres gives you a superuser, so this works — but if you point this at a managed database where you are not a superuser, role creation will fail and the deployment will stop there rather than half-applying. That is the intended behaviour.

## Two things to know before this URL is shared

**The sample photographs are generated, not real.** Two real JAMB passports were embedded while the passport-matching screen was being built. They are photographs of two identifiable nineteen-year-olds, and this file is served from a public URL, so they are gone — replaced by drawn images at exactly the size JAMB sends (132 × 151 px, about 4 KB), because the *size* was the point and the faces never were. Everything else in the samples is invented for the same reason: no real name, registration number or result appears anywhere in this repository.

**The typeface comes from Google Fonts.** The content security policy allows `fonts.googleapis.com` and `fonts.gstatic.com` and nothing else. It means the portal calls a third party on every page load, and that the page falls back to system fonts whenever that third party is unreachable from Makurdi. The fallback is real and the page is perfectly legible in it — but before production, serve the two font files from here instead. The Next.js frontend already does: `next/font` downloads IBM Plex at build time and serves it from the portal's own origin.

## What this is not, yet

The Spring Boot application is **begun**, not finished: the request path is
built and proven, and two of the twenty-seven modules — `iam` and `admissions`
intake — have their first endpoints. Keycloak is configurable but not deployed;
development uses a shared secret and `api/scripts/dev-token.mjs`. Scope checking
against `iam.office_assignment`, the transactional outbox, and every other
module are still to come, each as its own package with the same shape. The
frontend renders the service's status and the admission-list screen from the
API; the rest of the prototype's screens are still the prototype's.

The deployment shape here — a service that migrates before it serves, behind a
gate that will not let an untested build through — is the shape both slot into.
