# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MOAUMPP — the MOAUM Unified University Portal (Rev. Fr. Moses Orshio Adasu University, Makurdi, Directorate of ICT). Three things live in one repository and deploy as separate Railway services from one Postgres database:

| | |
|---|---|
| `proto/` | The original prototype: many `partN.html` files concatenated by `build.py` into one self-contained HTML file. `part6.html` is **always last** — it closes the IIFE and calls `render()`. |
| `public/index.html` | That concatenated file, built and committed — this is what the prototype service serves. |
| `db/` | Postgres migrations (`V001__...sql`, `V002__...sql`, ...), `check.sql` (a large battery of self-asserting properties, writes to the DB), `verify.sql` (read-only, safe on production), `demo.sh`/`demo.sql` (invented demo accounts). |
| `web/server.js` | The prototype's server. No dependencies, deliberately. |
| `api/` | The Spring Boot service — Java 21, Spring Boot, Spring Modulith, plain JDBC (no ORM). One package per business module under `ng.edu.moaum.portal`. See `api/README.md`. |
| `frontend/` | The Next.js frontend — App Router, server-rendered, Tailwind. Talks to the API only from the server, as a BFF; the prototype's palette and typeface, self-hosted via `next/font`. |

**The root `README.md` and `api/README.md` describe the project near its start** (e.g. they say "ten migrations" and "two modules, iam and admissions"). The repository has grown far past that (hundreds of migrations, ~40 API module packages, dozens of frontend routes covering undergraduate and postgraduate admissions, registration, finance, HR, hostel, library, results, credentials, etc.) — treat the READMEs' *architecture and workflow* description as authoritative, but verify any specific count or "not yet built" claim against the actual code before relying on it.

## Commands

```bash
# the HTML prototype
npm run build                 # rebuild public/index.html from proto/part*.html (python3 proto/build.py)
npm start                     # serve it on :8080 (web/server.js)
node proto/runall.mjs         # rebuild + run every Playwright browser harness (needs playwright+chromium)

# the database
createdb moaumpp
export DATABASE_URL=postgres:///moaumpp
npm run migrate               # bash db/migrate.sh — applies pending V*.sql in order, then stops
npm run check:db              # psql -f db/check.sql — self-asserting properties; WRITES, use a throwaway database
psql "$DATABASE_URL" -f db/verify.sql   # read-only; safe to run against a real deployment

# the Spring Boot API (needs Java 21; wrapper included)
export MOAUM_AUTH_HMAC_SECRET='change-me-to-at-least-thirty-two-bytes-long'
(cd api && ./mvnw spring-boot:run)              # :8081
(cd api && ./mvnw -B -ntp verify)               # unit tests + module-boundary test; *IT classes SKIP without DATABASE_URL
DATABASE_URL=postgres://... (cd api && ./mvnw verify)   # ...and run the *IT classes against a real schema
# single test class: (cd api && ./mvnw test -Dtest=AuditSpineIT)

# the Next.js frontend (needs Node 22)
(cd frontend && cp .env.example .env.local && npm ci && npm run dev)   # :3000
(cd frontend && npm test)     # node --test over src/**/*.test.ts
(cd frontend && npm run lint)
(cd frontend && npm run build)
```

On Windows, `python` (not `python3`) is found automatically, and the build folds CRLF to LF so `public/index.html` is byte-identical to what CI produces.

### Minting a dev token for the API

```bash
node api/scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" --offices academic,registrar
curl -H "Authorization: Bearer $TOKEN" -H "X-Active-Office: academic" localhost:8081/api/v1/iam/me
```

## CI gates (`.github/workflows/ci.yml`)

Railway deploys only commits that pass CI. Jobs run in parallel then an `image` job builds and smoke-tests all three containers:

1. **`web`** — rebuilds `public/index.html` from `proto/part*.html` and diffs it byte-for-byte against the committed file; runs all Playwright harnesses (`proto/runall.mjs`).
2. **`db`** — applies migrations with `db/migrate.sh` against Postgres 17, asserts a second run is a no-op (`0 applied`), asserts editing an already-applied migration file **stops** the run, runs `db/check.sql` (must print `FOUNDATION GREEN`), then `db/verify.sql`, then applies `db/demo.sh` twice and re-verifies.
3. **`api`** — applies migrations, then `./mvnw -B -ntp verify` (module-boundary test + `*IT` integration tests against the real schema).
4. **`frontend`** — `npm test`, `npm run lint`, `npm run build`.
5. **`image`** — builds the prototype, API and frontend Docker images, runs migrations from inside the image, and smoke-tests each running container (health endpoints, a sign-in through the portal, office-scoped dashboards, a 401 without a token).

If you change one of `proto/`, `db/`, `api/`, or `frontend/`, run that piece's own check locally before assuming CI will pass — especially `npm run build` after touching any `proto/part*.html` (the build-reproducibility diff fails loudly and unhelpfully if forgotten) and `./mvnw verify` / `db/check.sql` after touching a migration.

## Database migrations (`db/`)

`db/migrate.sh` keeps a ledger in `public.schema_migration` (filename, SHA-256, when, by which role):

- already applied, unchanged → **skipped**
- never applied → **applied**, in its own transaction, in filename order
- **applied before and the file has since changed → the whole deployment stops, by name**

Never edit a migration that has already been applied (locally or in any deployed environment) — write a new `V<next>__description.sql` file instead. Migration filenames are `V<number>__<snake_case_description>.sql`; numbers are not zero-padded to a fixed width and are allocated sequentially by inspecting the highest existing `V*.sql`.

`check.sql` is **not** run on deployment — it creates people, policies and credentials and deliberately tampers with an audit row, so it only ever runs in CI or by hand against a throwaway database. `db/verify.sql` is what runs after a real deployment: it only reads, and it asserts (among other things) that no application role holds `DELETE` anywhere, nothing may write to `audit.*` directly, and an unattributed write is still refused.

## The audit spine (the one thing to understand about the API)

`V002` makes attribution a property of the database itself: an audit trigger reads `moaum.actor_id` and `moaum.actor_office` off the current transaction and **refuses any write that carries neither**. `AttributedTransactionManager` (`api/.../platform/AttributedTransactionManager.java`) is the other half — it places the request's `AuditContext` onto every transaction via `set_config(..., true)` (transaction-local) the moment the transaction opens, so nothing leaks into a pooled connection's next borrower. A service method that forgets to route through this cannot write; `AuditSpineIT` proves both directions against a real database.

Per request, the context is built as:

| | source |
|---|---|
| actor | the token's `sub` |
| offices held | the token's `offices` claim → one `OFFICE_<code>` Spring authority each |
| acting office | `X-Active-Office` header, must be one the token carries (403 otherwise), else the first office held |
| reason | `X-Reason`, optional, recorded |
| correlation id | `X-Correlation-Id`, accepted and echoed, generated when absent |

Every refusal is an RFC 9457 problem body with a stable `code`, the `correlationId`, and — where a person can act on it — a `remedy` naming the responsible office. Database-level refusals (SQLSTATE 23514 from the audit spine, list-kind triggers, reconciliation checks) pass through as 422 with the server's HINT text as the remedy, because that's where those rules live.

## API structure (`api/src/main/java/ng/edu/moaum/portal/`)

Spring Modulith: one top-level package per business module (`admissions`, `pgadmissions`, `iam`, `finance`, `hrm`, `hostel`, `library`, `student`, `studentportal`, `credentials`, `results`, `registration`, `matriculation`, `graduation`, `catalogue`, `calendar`, `cbt`, `governance`, `payments`, `wallet`, `verify`, `apimgmt`, and more). Two packages are special:

- `shared` — the shared kernel: `AuditContext`, `OfficeScope`, the exception types every module throws (`DomainRuleViolation`, `NotFound`). Marked `Type.OPEN` — it is the **only** package every other module may import.
- `platform` — the cross-cutting request path: correlation id, JWT verification, acting-office resolution, `AttributedTransactionManager`, `ProblemHandler`, plus a few standalone endpoints (`/api/v1/platform/status`, mail, SMS, notices).

A module may only depend on another module's exported API, never its internals. This is checked structurally by `ModularityTests.moduleBoundariesHold()` (`api/src/test/java/.../ModularityTests.java`) using `ApplicationModules.verify()` — a boundary violation **fails the build**, not a code review. No Spring context or database is needed to run this test.

Plain JDBC throughout, no JPA/Hibernate. `*IT` classes (`AuditSpineIT`, `ApiIT`, `AuthIT`, `CalendarIT`, `CandidateDataIT`, ...) are real integration tests against Postgres and are skipped automatically when `DATABASE_URL` is unset.

`DATABASE_URL` in Railway's form is understood directly; `JDBC_DATABASE_URL` + `PGUSER` + `PGPASSWORD` is the alternative. **The API never runs migrations** — `db/migrate.sh` does, as the pre-deploy step, before the API starts.

## Frontend structure (`frontend/src/`)

App Router, one directory per screen area under `src/app/` (`admissions/`, `applicant/`, `hrm/`, `finance/`, `hostel/`, `library/`, `student/`, `studentportal/`, etc.), each typically a `page.tsx` plus a co-located client component doing the actual work.

**BFF pattern (ARC §8 / ADR-007):** the browser only ever talks to the Next.js origin. Two ways server code reaches the API:

- `frontend/src/lib/api.ts` — the `api<T>()` helper, called from server components/actions. Attaches the session token (from the session cookie, or `PORTAL_API_TOKEN` in dev before Keycloak exists) and the acting office (from the office cookie, or `PORTAL_ACTIVE_OFFICE`) as `Authorization` / `X-Active-Office`, and unwraps RFC 9457 problem responses into a typed `Problem`.
- `frontend/src/app/api/bff/[...path]/route.ts` — a catch-all proxy for client-side fetches, used when a screen needs to call the API directly from the browser. Only forwards to `/api/v1/...` (anything else is refused with 404) and only forwards a fixed allowlist of headers; it injects the same session/office cookies as `authorization`/`x-active-office` server-side so the token never reaches the browser.

Session/auth routes live under `frontend/src/app/api/auth/` (staff sign-in, applicant sign-in/register/forgot/reset, student sign-in, SSO start/callback, bootstrap, change-password) — these are Next.js route handlers that call the API and set the session cookie, not pass-throughs.

The frontend renders the prototype's palette/typeface itself (IBM Plex via `next/font`, self-hosted — no runtime call to Google Fonts, unlike the HTML prototype).

`frontend/AGENTS.md` / `frontend/CLAUDE.md` point at `node_modules/next/dist/docs/` — this project pins a Next.js version that may differ from training-data conventions; when editing routing, server actions, or config in `frontend/`, check that directory first rather than assuming familiar Next.js behavior.

## Deploying (Railway)

One project, four services built from the repository root (so each image can carry `db/`): `Postgres`, `moaum-api` (owns the schema — its pre-deploy runs `bash db/migrate.sh`), `moaum-portal` (the Next.js frontend; gets the public domain), `moaum-prototype` (the HTML prototype, until the frontend covers its screens). There is deliberately no root-level `railway.json` — each service has its own (`api/railway.json`, `frontend/railway.json`, `web/railway.json`) so Railway doesn't apply one config to every service. Full variable list and per-service settings are in the root `README.md` under "Deploying on Railway".
