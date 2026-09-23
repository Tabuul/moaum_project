# Running this locally on Windows

How to get all three pieces — the database, the Spring Boot API and the Next.js
frontend — running on a Windows machine. It assumes Java 21 and Node 22 are
already installed (see the root `README.md` for the general requirements);
this page fills in the Windows-specific gap, which is Postgres.

## 1. Install PostgreSQL

CI and Railway run Postgres 17, but nothing in the migrations or `check.sql`/
`verify.sql` needs anything newer than PG13 (no `MERGE`, no `JSON_TABLE`,
nothing version-gated) — PG15 or any recent Postgres works fine for local
dev. The only requirement is `psql` on `PATH`. Via winget, in PowerShell:

```powershell
winget install PostgreSQL.PostgreSQL.17
```

(swap the id for whatever version you already have, e.g. `PostgreSQL.PostgreSQL.15`
— or skip this step if `psql` already resolves.)

Open a **new** terminal afterwards and confirm:

```powershell
psql --version
```

If it's not found, add `C:\Program Files\PostgreSQL\17\bin` to `PATH`.

## 2. Create the database

The migration and demo scripts are bash scripts, so run them from **Git Bash**,
not PowerShell. Open Git Bash in the repository root:

```bash
createdb -U postgres moaumpp   # prompts for the password set during install
export DATABASE_URL=postgres://postgres:<your-password>@localhost:5432/moaumpp

npm run migrate                # applies db/V*.sql in order
bash db/demo.sh                # optional but recommended: adds ready-made login accounts
```

`demo.sh` prints where to find the account list — it's also at
[demo-accounts.md](demo-accounts.md). The password for every demo account is
`Demo password 2026`.

## 3. Run the Spring Boot API (port 8081)

Same Git Bash terminal (or a new one, with `DATABASE_URL` exported again):

```bash
export MOAUM_AUTH_HMAC_SECRET='change-me-to-at-least-thirty-two-bytes-long'
cd api
./mvnw spring-boot:run
```

Leave it running. Verify with `http://localhost:8081/api/v1/platform/status` —
it should return JSON.

## 4. Run the Next.js frontend (port 3000)

In a **new** terminal (PowerShell is fine here):

```powershell
cd frontend
Copy-Item .env.example .env.local
npm ci
npm run dev
```

Open `http://localhost:3000` — it should redirect to `/login`.

## 5. Sign in

Use one of the demo accounts from step 2:

- **Student example:** username `MOAUM/MTC/24/9903`, password `Demo password 2026`
- **Staff example:** username `demo.academic`, password `Demo password 2026`

Full table in [demo-accounts.md](demo-accounts.md).

## Optional: the older HTML prototype (port 8080)

Not required for the main app, but if you want it too, in Git Bash:

```bash
npm run build
npm start
```

Needs Python 3 on `PATH` as `python` (already the case on Windows — the build
script looks for it under that name automatically).

## If you skip the demo accounts

Without `bash db/demo.sh` there are no accounts to sign in with. Instead, hit
the API's `/api/v1/auth/bootstrap` endpoint with `X-Bootstrap-Secret` set to
your `MOAUM_AUTH_HMAC_SECRET` to create a first account — see the `image` job
in `.github/workflows/ci.yml` for the exact request shape. The demo accounts
are simpler for local development.
