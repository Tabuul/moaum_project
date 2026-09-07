# portal-api

The Spring Boot service — Java 21, Spring Boot 4.1, Spring Modulith 2.1, plain
JDBC against the PostgreSQL schema in `../db`. It is the shape ARC §7 describes,
built from the request path inward: the parts every module needs are here and
proven; the modules themselves are begun.

## What is here

| package | what it is |
|---|---|
| `shared` | The shared kernel: `AuditContext`, the two exception types every module throws. OPEN — the only package every module may import. |
| `platform` | The request path. Correlation id → JWT → the acting office → **the audit context on every transaction** → problem responses. And `/api/v1/platform/status`. |
| `iam` | Persons and the offices they hold, each grant under an instrument (`iam.office_assignment`). |
| `admissions` | CAPS intake: load a list whole, reconcile it, commit it; the attachments around it; the session's policy findings. |

Module boundaries are verified by a test (`PortalApiApplicationTests.moduleBoundariesHold`):
a module importing another's internals fails the build, not a code review (ADR-003).

## The one thing to understand

V002 makes attribution a property of the database: the audit trigger reads
`moaum.actor_id` and `moaum.actor_office` off the transaction and **refuses any
write that carries none**. `AttributedTransactionManager` is the other half — it
places the request's `AuditContext` on every transaction with `set_config(…, true)`
the moment it opens, local to that transaction, so nothing leaks into a pooled
connection's next borrower. A service that forgets the context cannot write.
`AuditSpineIT` proves both directions against a real database.

Where the context comes from, per request:

| | |
|---|---|
| actor | the token's `sub` (Keycloak issues a UUID) |
| offices held | the token's `offices` claim → one `OFFICE_<code>` authority each |
| acting office | `X-Active-Office`, which must be one the token carries (403 otherwise); else the first office held |
| reason | `X-Reason`, optional, recorded |
| correlation id | `X-Correlation-Id`, accepted and echoed, generated when absent |

A request with no office proceeds and may read; a write it attempts is refused
by the database and rendered as a 403 problem naming the remedy.

## Refusals

Every refusal is an RFC 9457 problem with a stable `code`, the `correlationId`,
and where a person can act on it, a `remedy` naming the office (NFR-USA-005).
The database's own refusals (SQLSTATE 23514 — the audit spine, the list-kind
trigger, a list that does not reconcile) pass through as 422 with the server's
HINT as the remedy, because that is where those rules live and that wording is
the wording that was reviewed.

## Running it

```bash
# a database the migrations have been applied to (see ../README.md)
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/moaumpp
bash ../db/migrate.sh

# development authentication: a shared secret instead of Keycloak
export MOAUM_AUTH_HMAC_SECRET='change-me-to-at-least-thirty-two-bytes-long'

./mvnw spring-boot:run            # http://localhost:8081
curl -s localhost:8081/api/v1/platform/status
```

`DATABASE_URL` in Railway's shape is understood directly; `JDBC_DATABASE_URL`,
`PGUSER` and `PGPASSWORD` are the alternative. This service **never runs the
migrations** — `db/migrate.sh` does, before it starts.

### Minting a development token

```bash
TOKEN=$(node scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" --offices academic,registrar)
curl -s -H "Authorization: Bearer $TOKEN" -H "X-Active-Office: academic" localhost:8081/api/v1/iam/me
```

In production `MOAUM_AUTH_ISSUER_URI` points at Keycloak and the secret is unset.

## Tests

```bash
./mvnw verify                      # unit tests + module boundaries; the *IT classes SKIP without DATABASE_URL
DATABASE_URL=postgres://… ./mvnw verify   # …and run against the real schema
```

`AuditSpineIT` — an unattributed write is refused; an attributed one is recorded
against the actor; nothing leaks between transactions.
`ApiIT` — the request path end to end: 401 without a token, an office the token
does not carry refused before any service runs, method security by office, a
person created and granted an office under an instrument, a CAPS list loaded
whole, a list-kind contradiction refused whole with the database's remedy, and
the registration number read out of JAMB's filename.

CI runs both against Postgres 17 with the migrations applied by `db/migrate.sh`.

## Endpoints so far

| method | path | office |
|---|---|---|
| GET | `/api/v1/platform/status` | public |
| GET | `/api/v1/iam/me` | any token |
| GET/POST | `/api/v1/iam/persons`, `/{id}` | registrar, dregistrar, hrm, ict, admin, super |
| POST | `/api/v1/iam/persons/{id}/office-assignments` | registrar, dregistrar, vc, super |
| GET/POST | `/api/v1/admissions/caps-batches`, `/{id}` | load: academic, registrar |
| POST | `/api/v1/admissions/caps-batches/{id}/commit` | academic, registrar |
| GET | `/api/v1/admissions/sessions/{yyyy}/{yyyy}/reconciliation` · `/attachments` · `/policy-findings` | admissions readers |
| GET | `/api/v1/admissions/reg-no?in=<filename>` | admissions readers |

## Not yet

Keycloak itself (the issuer is configurable; nothing is deployed), scope
checking against `iam.office_assignment` (the token says which offices; the
table says over what), the transactional outbox (ADR-005), and every module
after these two. Each lands as its own package with the same shape.
