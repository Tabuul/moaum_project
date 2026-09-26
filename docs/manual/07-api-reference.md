# 07 — API Reference

**MOAUM Unified University Portal** — Rev. Fr. Moses Orshio Adasu University, Makurdi — Directorate of ICT

This volume describes the HTTP API of the portal as it is implemented in the repository: how a caller authenticates, which headers carry the acting office and the audit reason, how refusals are rendered, which endpoints are public, how the payment gateways call back, which jobs run on a timer, and the full catalogue of endpoints generated from the controllers. Everything stated here was read from the code; where a statement could not be confirmed it is marked "not verified". For the architecture and configuration around the API see *03 Technical Documentation*; for who holds which office see *04 Role and Permission Matrix*; for the tables the endpoints read and write see *08 Database Reference*.

## Table of contents

1. [Introduction](#1-introduction)
   1. [Base URL and versioning](#11-base-url-and-versioning)
   2. [The frontend's BFF path](#12-the-frontends-bff-path)
   3. [Authentication](#13-authentication)
   4. [The acting office](#14-the-acting-office)
   5. [The audit context](#15-the-audit-context)
   6. [Correlation id](#16-correlation-id)
   7. [Problem responses](#17-problem-responses)
   8. [Pagination and search](#18-pagination-and-search)
   9. [File uploads and downloads](#19-file-uploads-and-downloads)
   10. [Rate limits](#110-rate-limits)
   11. [Idempotency](#111-idempotency)
   12. [Public endpoints](#112-public-endpoints)
   13. [Payment webhooks](#113-payment-webhooks)
   14. [Scheduled jobs](#114-scheduled-jobs)
   15. [Health and status endpoints](#115-health-and-status-endpoints)
2. [Conventions for request and response bodies](#2-conventions-for-request-and-response-bodies)
   1. [General conventions](#21-general-conventions)
   2. [Worked example: staff sign-in](#22-worked-example-staff-sign-in)
   3. [Worked example: who am I](#23-worked-example-who-am-i)
   4. [Worked example: matriculate one student](#24-worked-example-matriculate-one-student)
   5. [Worked example: configure a programme's matriculation code](#25-worked-example-configure-a-programmes-matriculation-code)
   6. [Worked example: a student requests a document](#26-worked-example-a-student-requests-a-document)
   7. [Worked example: raise a help-desk ticket](#27-worked-example-raise-a-help-desk-ticket)
   8. [Worked example: open a payment checkout](#28-worked-example-open-a-payment-checkout)
   9. [Worked example: verify a document publicly](#29-worked-example-verify-a-document-publicly)
3. [Endpoint catalogue](#3-endpoint-catalogue)
4. [Endpoints without a screen](#4-endpoints-without-a-screen)
5. [Integration notes](#5-integration-notes)
   1. [Minting a development token](#51-minting-a-development-token)
   2. [Calling the API with curl](#52-calling-the-api-with-curl)
   3. [Reading a problem response](#53-reading-a-problem-response)
   4. [The API key register](#54-the-api-key-register)
   5. [Demo accounts](#55-demo-accounts)

---

## 1 Introduction

### 1.1 Base URL and versioning

The API is one Spring Boot service (`api/`, Java 21, Spring Boot 4.1, Spring Modulith) that listens on port **8081** (`server.port=${PORT:8081}` in `api/src/main/resources/application.properties`). Every route it serves is under the prefix **`/api/v1`**; there is no other version, no version header and no content negotiation by version. On the production platform (Railway) the service is named `moaum-api` and the Next.js frontend is a separate service, `moaum-portal`, on port 3000. The frontend reaches the API at `PORTAL_API_URL` (default `http://localhost:8081`, `frontend/src/lib/api.ts`).

```text
Browser ──► https://<portal host>/api/bff/api/v1/…   (Next.js BFF, same origin as the screens)
                 │  adds Authorization: Bearer <token from the httpOnly cookie>
                 ▼
            http://<api host>:8081/api/v1/…            (Spring Boot, portal-api)
                 │
                 ▼
            PostgreSQL (schemas admissions, people, finance, … — see 08 Database Reference)
```

Two things follow for an integrator:

- A browser never talks to the API directly and never holds the token. It talks to the portal origin, and the BFF forwards (see §1.2).
- A server-side integration (a script, a batch job, a test) calls `http://<api host>/api/v1/...` directly with a bearer token (see §1.3 and §5).

Responses are JSON (`application/json`) except where a handler declares otherwise: `GET /api/v1/payments/quickteller/start` answers `text/html`, and the `.../content`, `.../download` and `.../photo` handlers answer the stored bytes with their own `Content-Type` (see §1.9).

### 1.2 The frontend's BFF path

The file `frontend/src/app/api/bff/[...path]/route.ts` is the only route through which the browser reaches the API. Its behaviour, read from the code:

| Aspect | What the BFF does |
|---|---|
| Methods | `GET`, `POST`, `PUT`, `PATCH`, `DELETE` are exported; anything else is not routed. |
| Path | The browser calls `/api/bff/api/v1/<rest>`. The BFF requires the first two segments to be `api` and `v1`; anything else is answered `404` with a problem body `{"status":404,"title":"Not found","detail":"Only /api/v1/... is reachable through the BFF."}`. Each path segment is passed through `encodeURIComponent`; the query string is appended unchanged. |
| Headers forwarded | Only `content-type`, `accept`, `x-correlation-id`, `x-active-office`, `x-reason` and `idempotency-key`. Every other request header is dropped. |
| Token | `Authorization: Bearer <token>` is added from the `moaum_session` cookie (httpOnly, `SameSite=Lax`, `Secure` in production, `Path=/`, lifetime equal to the token's `expiresAt`). Outside production, when there is no cookie, the server-side variable `PORTAL_API_TOKEN` is used instead. |
| Acting office | If the browser did not send `X-Active-Office`, the BFF adds it from the `moaum_office` cookie (readable by the page's script; it is what the Shell's "Signed in as" selector writes). Outside production the fallback is `PORTAL_ACTIVE_OFFICE`. |
| Body | For every method other than `GET`/`HEAD` the request body is read as text and forwarded as-is. |
| Caching | `cache: "no-store"` on the upstream fetch. |
| Response | The upstream status is returned unchanged; of the upstream headers only `content-type`, `x-correlation-id` and `location` are passed back; the body is passed back byte for byte. |

A typical browser call, as the screens make it (`frontend/src/lib/documents.ts:87`, `hostel.ts:140` and many others):

```text
fetch(`/api/bff/api/v1${path}`, {
  method,
  headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
  body: JSON.stringify(body)
})
```

Server components and route handlers do not go through the BFF; they call `api()` in `frontend/src/lib/api.ts`, which reads the same cookies and adds the same headers (`Accept: application/json`, `Authorization`, `X-Active-Office`, `X-Reason`, `X-Correlation-Id`).

Sign-in is **not** a BFF call. `frontend/src/app/api/auth/sign-in/route.ts` is one door for everybody: it reads the identifier typed, decides which API door it belongs to by its shape, calls that door, then sets the two cookies:

| Identifier shape | API door called | Office cookie |
|---|---|---|
| `MOAU/…/YY/NNNN` or `MOAUM/…/YY/NNNN` (matriculation number, V263 or V064 form), `MOAUM/ADM/YY/NNNNNN` (admission number) | `POST /api/v1/student-auth/sign-in` `{matricNo, password}` | `student` |
| `PG/YY/NNNNNN` | `POST /api/v1/pg/sign-in` `{identifier, password}` | `applicant` |
| 12 digits + 2–3 letters (JAMB), `APP/YY/NNNNNN` | student door first; if refused, `POST /api/v1/applicant/sign-in` `{identifier, password}` | `student` or `applicant` |
| A legacy old-portal matriculation number (`BSU/…`, `MOAU/…`, two to six letters then segments then digits) | student door first, then the staff door | `student` or the staff office |
| Anything else (staff number or email) | `POST /api/v1/auth/sign-in` `{username, password, office}`; on a 422 with an email address, the applicant door and then the PG door are tried | the preferred office if the token carries it, else the first office |

The route answers `{kind, home, mustChange, name, office, offices}` and the page navigates to `home`. Sign-out (`/api/auth/sign-out`) calls `POST /api/v1/auth/sign-out` with the cookie's token and clears both cookies. The first account is created through `/api/auth/bootstrap`, which forwards to `POST /api/v1/auth/bootstrap` with the `X-Bootstrap-Secret` header (§1.12).

### 1.3 Authentication

Every non-public endpoint requires `Authorization: Bearer <JWT>`. The API is a stateless OAuth2 resource server (`SecurityConfig.java`: CSRF disabled, `SessionCreationPolicy.STATELESS`), and there are two ways it can verify a token, chosen at boot:

| Mode | Property / variable | How tokens are verified | Status |
|---|---|---|---|
| Shared secret (development, CI and the current deployment) | `moaum.auth.hmac-secret` = `MOAUM_AUTH_HMAC_SECRET` (at least 32 bytes, else the service refuses to start: "moaum.auth.hmac-secret must be at least 32 bytes") | HS256 with the secret (`NimbusJwtDecoder.withSecretKey`) | **IMPLEMENTED** |
| Identity provider (Keycloak) | `moaum.auth.issuer-uri` = `MOAUM_AUTH_ISSUER_URI` | `JwtDecoders.fromIssuerLocation(issuer)` — the realm's published keys | **CONFIGURED BUT UNUSED** — `api/README.md` records that no Keycloak is deployed |

If neither is set the service stops at boot with "no way to verify tokens: set MOAUM_AUTH_ISSUER_URI (Keycloak) or, for development only, MOAUM_AUTH_HMAC_SECRET". The secret takes precedence when both are set.

**Tokens the portal issues.** In shared-secret mode the sign-in endpoints mint their own tokens (`auth/TokenIssuer.java`, HS256 with the same secret). The claims are:

| Claim | Meaning |
|---|---|
| `sub` | the person's UUID (`iam.person.id`; for a student, `people.student.id`; for an applicant, the applicant account id). The audit filter refuses a token whose `sub` is not a UUID with `401` "The token's subject is not a person id." |
| `iat`, `exp` | issue and expiry; expiry is the session's end — **12 hours** after sign-in (`AuthService.SESSION_LENGTH = Duration.ofHours(12)`) |
| `offices` | the list of office codes the person holds live (e.g. `["academic","registrar"]`); a student token carries `["student"]`, an applicant token `["applicant"]` |
| `sid` | the server-side session id, 32 random bytes as 64 hex characters, a row of `platform.session` |
| `name` | display name ("SURNAME, Given names") |

No `iss` or `aud` claim is set on issued tokens. In issuer-URI mode `TokenIssuer` has no key and every password sign-in is refused with `422 AUTH_SIGN_IN_ELSEWHERE` ("This portal verifies tokens issued by the University's identity provider; sign in there.").

**From the token to authorities.** `SecurityConfig.authorities()` turns each entry of `offices` into a granted authority `OFFICE_<code>`; every `@PreAuthorize` in the controllers is written against those (`hasAnyAuthority('OFFICE_registrar', …)`). Scope — that a Head of Department acts for one department, a Lecturer for one course — is **not** in the token; it lives in `iam.office_assignment` and is enforced by the services that read it (deferments, PG admissions, clearance, registration and results throw `AccessDeniedException` with a message when the acting office is out of bounds).

**Sessions and the deploy floor.** A token with a `sid` is checked on every request by `platform/SessionGuard.java` against `platform.session`:

| Finding | Response |
|---|---|
| `sid` is not hexadecimal | `401` "The token names a session that cannot exist." |
| no such session row | `401` "The token names a session this portal does not hold. Sign in again." |
| `ended_at` is set (signed out, or ended by the Registrar) | `401` "This session was ended. Sign in again." |
| `absolute_end < now()` (the 12 hours are over) | `401` "This session reached its end. Sign in again." |
| `issued_at` is earlier than the moment this API instance started | `401` "The portal was updated. Sign in again." — the **deploy floor**: every deploy or restart of the API invalidates every session issued before it |
| otherwise | proceeds; `last_seen_at` is touched at most once a minute |

A token **without** a `sid` — the development token of §5.1 — skips the guard entirely and is valid until its `exp`.

**Account locking.** Five wrong passwords lock a staff account for fifteen minutes (`AuthService.LOCK_FOR = 15 min`); the refusal is `422 AUTH_LOCKED` naming the time. Student and applicant doors behave the same way (the remedy text of each says so); the postgraduate applicant door additionally throttles by connection (§1.10).

**Single sign-on.** `GET /api/v1/auth/sso` describes whether SSO is on (`{enabled, label, requireMfa, issuer}`); it is on only when `MOAUM_SSO_ISSUER`, `MOAUM_SSO_CLIENT_ID` and `MOAUM_SSO_CLIENT_SECRET` are all set. `GET /api/v1/auth/sso/start?redirectUri=` returns the authorisation URL; `POST /api/v1/auth/sso/callback` `{code, state, redirectUri}` exchanges the code, verifies the ID token (RS256 against the realm's JWKS, issuer, audience, expiry, nonce) and requires an MFA factor unless `MOAUM_SSO_REQUIRE_MFA=false`. It then mints a portal token through the same `TokenIssuer`. Status: **CONFIGURED BUT UNUSED** in the current deployment (no provider is configured).

### 1.4 The acting office

A person may hold several offices — a Dean who also lectures, a Registrar who is also a Super Administrator. The API needs one office per request, because every write is attributed to exactly one office.

`platform/AuditContextFilter.java` decides it, in this order:

1. If the request carries **`X-Active-Office`**, that office must be one of the token's `offices`. If it is not, the filter answers **`403`** before any controller runs, with the body `{"type":"about:blank","title":"Forbidden","status":403,"detail":"The office 'dean' is not one this token carries: [academic, registrar]."}`.
2. If the header is absent, the **first office in the token** is the acting office.
3. If the token carries no office at all, the request still proceeds. Reads work. Any write reaches the database's audit trigger, which refuses an unattributed change; the API renders that as **`403 NO_ACTING_OFFICE`** with the remedy "Send X-Active-Office with one of the offices your token carries." (office: Directorate of ICT).

The frontend always sends the header: the BFF fills it from the `moaum_office` cookie, and the Shell's office selector rewrites that cookie when the person switches office. `GET /api/v1/iam/me` reports the resolved `activeOffice`, so a client can confirm which office a call will be attributed to.

> **Note:** the 403 the filter writes is a minimal problem body — it has no `code`, `correlationId` or `remedy`. Only problems produced by `ProblemHandler` (§1.7) carry those.

### 1.5 The audit context

The context of every request is the record `shared/AuditContext.java`:

| Field | Source |
|---|---|
| `actorId` | the token's `sub` |
| `actorOffice` | the acting office of §1.4 (required — the record refuses a blank office) |
| `reason` | the **`X-Reason`** header, free text, optional |
| `correlationId` | the request's correlation id (§1.6) |
| `sourceIp` | `request.getRemoteAddr()` |

The platform places the context on every database transaction as transaction-local settings `moaum.actor_id`, `moaum.actor_office` and `moaum.reason` (`AttributedTransactionManager`, described in `api/README.md`). The audit trigger installed by migration V002 reads them back on every write to an attached table and refuses a write that carries none — which is why a request without an office can read but not change anything, and why a service that forgets the context cannot write at all. The trail itself is read through `GET /api/v1/audit/entries` and `/api/v1/audit/facets` (Director of Internal Audit, Deputy Director of Audit, Vice-Chancellor, Director of ICT, System Administrator, Super Administrator).

`X-Reason` is what an auditor later reads as the "why". Every state-changing call the screens make sends one (the `reasonHeader()` helper in `frontend/src/lib/reason.ts` makes it header-safe: typographic dashes and quotes become their plain forms, `₦` becomes `NGN`, any other character outside ISO-8859-1 is percent-encoded). A direct API caller should send it too; nothing refuses a write without a reason at the platform level, though some endpoints demand one in the body (for example `MAT_QUERY_SAYS_WHY`).

Scheduled jobs (§1.14) and the sign-in doors run under a system actor (UUID `00000000-0000-0000-0000-000000000000`) with an office of their own (`ict` at the door), so their writes are attributed too.

### 1.6 Correlation id

`platform/CorrelationIdFilter.java` runs first on every request. If the caller sends **`X-Correlation-Id`** and it parses as a UUID, that id is used; otherwise a fresh UUID is generated (a value that is not a UUID is not trusted and is replaced). The id is:

- set on the response header `X-Correlation-Id` — on every response, including errors;
- put in the logging context under `correlationId`;
- placed in every problem body as `correlationId` (§1.7);
- reported by `GET /api/v1/iam/me` as `correlationId`;
- carried in the audit context of the request.

When reporting a fault to the Directorate of ICT, quote the correlation id: it ties the screen's red box, the API log line and the audit row together.

### 1.7 Problem responses

Every refusal the API produces itself is an RFC 9457 problem (`Content-Type: application/problem+json`, `spring.mvc.problemdetails.enabled=true`), built by `platform/ProblemHandler.java`. The body:

| Member | Content |
|---|---|
| `type` | `about:blank`, or for a domain rule `https://api.moaum.edu.ng/problems/<code in kebab-case>` (for example `…/problems/pay-reference-expired`) |
| `title` | plain words for a person — from a fixed table for known codes, otherwise derived from the code (see below) |
| `status` | the HTTP status |
| `detail` | the sentence explaining this refusal |
| `instance` | the request URI |
| `code` | a stable machine-readable code, e.g. `AUTH_BAD_CREDENTIALS`, `NOT_FOUND`, `VALIDATION_FAILED`, `DATABASE_RULE_REFUSED` |
| `correlationId` | the request's correlation id |
| `remedy` | `{ "message": "<what to do>", "office": "<whose desk>" }` — present when the rule names one; `office` may be `null` when the action is the person's own |
| `violations` | on `400 VALIDATION_FAILED` only: `[{ "field": "username", "code": "INVALID", "message": "must not be blank" }, …]` |
| `sqlstate` | on `DATABASE_REFUSED` only: the PostgreSQL SQLSTATE |

The mapping from what went wrong to what is returned:

| Cause | Status | `code` | Notes |
|---|---|---|---|
| `DomainRuleViolation` thrown by a service or controller | `422` | the rule's own code (`PAY_ALREADY_CONFIRMED`, `MATRIC_NO_CODE`, `DOC_KIND`, …) | `title` from the table below or derived; `remedy` when the rule gives one |
| `NotFound` | `404` | `NOT_FOUND` | `detail` reads "<what> <id> not found" |
| Bean validation on a `@Valid @RequestBody` (`MethodArgumentNotValidException`) | `400` | `VALIDATION_FAILED` | `detail` "The request did not validate.", `violations` lists the fields |
| PostgreSQL SQLSTATE `23514` whose message starts "unattributed change" (the audit spine) | `403` | `NO_ACTING_OFFICE` | remedy: send `X-Active-Office` |
| SQLSTATE `23514` (CHECK / trigger refusal), `23502` (NOT NULL), `22P02` (bad text representation), `P0002` (no data found), `23P01` (exclusion constraint) | `422` | `DATABASE_RULE_REFUSED` | `detail` is the database's own message; `remedy.message` is the database HINT when one was written, with `remedy.office` "the office named in the rule" |
| SQLSTATE `23505` (unique violation) | `409` | `ALREADY_EXISTS` | |
| SQLSTATE `23503` (foreign key) | `409` | `REFERENCE_MISSING` | |
| SQLSTATE `42501` (insufficient privilege) | `403` | `DATABASE_PERMISSION` | |
| any other PostgreSQL error | `422` | `DATABASE_REFUSED` | the message is surfaced; `sqlstate` is included |
| a `DataAccessException` that is not a PostgreSQL error | rethrown | — | Spring's default `500` |
| missing, expired or unverifiable bearer token | `401` | — | answered by Spring Security's bearer-token entry point with **no body** (a `WWW-Authenticate: Bearer` header). The frontend's `api()` substitutes "You are not signed in". |
| a session refused by `SessionGuard`, a non-UUID subject, an office the token does not carry | `401` / `403` | — | minimal problem body written by `AuditContextFilter` (§1.4) |
| `@PreAuthorize` refuses the office; `AccessDeniedException` thrown by a service | `403` | — | no `ProblemHandler` mapping exists; Spring answers a bare `403`. Whether the service's message reaches the body is **not verified**. The frontend substitutes "You don't have access to this screen". |

**Titles.** `ProblemHandler.TITLES` fixes the title of these codes: `AUTH_BAD_CREDENTIALS` "Wrong username or password", `AUTH_LOCKED` "Account locked for now", `AUTH_THROTTLED` "Too many attempts", `AUTH_RESET_TOKEN` "That reset link is not valid", `AUTH_PASSWORD_SHORT` / `APP_PASSWORD_SHORT` "Password too short", `AUTH_PASSWORD_IS_USERNAME` "The password cannot be the username", `AUTH_USERNAME_TAKEN` "That username is taken", `AUTH_NO_STUDENT_ACCOUNT` "No student account yet", `AUTH_SIGN_IN_ELSEWHERE` "Sign in through the other door", `PAY_GATEWAY_UNREACHABLE` "The payment gateway is not reachable", `PAY_GATEWAY_REFUSED` "The payment was refused", `PAY_ALREADY_CONFIRMED` "That payment is already confirmed", `PAY_REFERENCE_EXPIRED` "That payment reference has expired", `REG_UNITS_OUT_OF_RANGE` "Units out of range", `REG_STUDENT_NOT_ELIGIBLE` "Not eligible to register", `COLLEGE_NOT_MEMBER` "Not a College student", `COLLEGE_YEAR_NOT_ENDED` "The year has not ended", `COLLEGE_NOT_YOUR_LEVEL` "Not your level", `COLLEGE_CA_RANGE` "CA out of range", `COLLEGE_EXAM_RANGE` "Examination mark out of range", `STUDENT_RECORD_CLOSED` "This record is closed", `IAM_NO_SUCH_OFFICE` "No such office", `IAM_GRANT_NEEDS_INSTRUMENT` "An instrument is needed". Any other code is turned into a sentence from its words after the module prefix; codes ending `_SAYS_WHY` read "A reason is needed", `_MINUTE_REQUIRED` "A minute is needed", `_ROWS` "The file's rows could not be read", `_RANGE` "<field> out of range", `_SIZE` "The file is too large", `_TYPE` "That file type is not accepted", `_ENCODING` "The file could not be read".

A full example (a domain rule):

```json
{
  "type": "https://api.moaum.edu.ng/problems/pay-reference-expired",
  "title": "That payment reference has expired",
  "status": 422,
  "detail": "This reference has expired.",
  "instance": "/api/v1/payments/checkout",
  "code": "PAY_REFERENCE_EXPIRED",
  "correlationId": "7f1c9c1e-3f0e-4b1e-9d2a-0f4d9e6a1c22",
  "remedy": { "message": "Generate a new one; it is free of charge.", "office": "You" }
}
```

And a database refusal passed through:

```json
{
  "type": "about:blank",
  "title": "Unprocessable Content",
  "status": 422,
  "detail": "student is not registered for 2025/2026",
  "instance": "/api/v1/matriculation/sessions/2025/2026/students/…/matriculate",
  "code": "DATABASE_RULE_REFUSED",
  "correlationId": "…",
  "remedy": { "message": "<the HINT written in the database function>", "office": "the office named in the rule" }
}
```

> **Note:** the exact `detail` and HINT of a database refusal are the wording of the PL/pgSQL function that raised it; the text above is illustrative, not a quotation.

### 1.8 Pagination and search

There is no portal-wide paging convention. Most list endpoints return the whole list (many with an internal `LIMIT`). The endpoints that page are:

| Endpoint | `page` | `size` (default / cap) | Search and filters | Response |
|---|---|---|---|---|
| `GET /api/v1/documents/requests` | 0-based, default 0 | 200 / 2000 | `q` (name, number, ref, document number, verification code), `stage` (`NEW`, `OPEN`, `PROCESSING`, `QUALITY_CHECK`, `BREACHING` or a stage name), `kind`, `payment`, `delivery`, `fac`, `dept`, `prog`, `session` | `{ total, page, size, rows, options }` |
| `GET /api/v1/helpdesk/tickets` | **1-based**, default 1 | 20 / 100 | `q`, `status`, `category`, `priority`, `agent`, `from`, `to`, `faculty`, `department`, `sort` (default `updated`), `dir` (default `desc`) | envelope of the queue (see the handler) |
| `GET /api/v1/admissions/sessions/{s}/{y}/putme/candidates` | 0-based | 200 | `batch`, `centre`, `q` | |
| `GET /api/v1/deferments` | 0-based | 100 | `kind`, `q` and desk filters | |
| `GET /api/v1/hostel/sessions/{s}/{y}/applications` | 0-based | 200 | `hall`, `q` | |
| `GET /api/v1/hostel/sessions/{s}/{y}/occupancy` | 0-based | 500 | `sex`, `q`, `view` | |
| `GET /api/v1/reports/registers/students` and `/staff` | **1-based**, default 1 | 100 / 500 | `q`, filters, `options=true` returns the filter options | |
| `GET /api/v1/stats/students` | 0-based | 50 | `which` (default `ALL`), `q` | rows sorted by name A–Z |
| `GET /api/v1/matriculation/config/history` | none | fixed `LIMIT 500` | `q` on the number or the name | list |

Where a `q` parameter exists it is a case-insensitive substring match (`lower(column) LIKE '%q%'`). Sorting is fixed by the handler except where `sort`/`dir` are listed.

### 1.9 File uploads and downloads

The API accepts **no multipart requests** (`MultipartFile` is used nowhere in `api/src/main/java`). A file travels inside the JSON body, base64-encoded:

| Endpoint (examples) | Body record | Limits in the code |
|---|---|---|
| `POST /api/v1/applicant/me/documents` | `{ kind, filename, contentType, contentBase64 }` | limits applied in the service (not verified at the controller) |
| `POST /api/v1/helpdesk/my/tickets/{id}/attachments`, `POST /api/v1/helpdesk/tickets/{id}/attachments` | `{ filename, contentType, contentBase64, internal }` | `contentBase64` ≤ 7,100,000 characters; decoded ≤ 5 MiB; types `application/pdf`, `image/jpeg`, `image/png` |
| `POST /api/v1/deferments/...` documents | `{ kind, filename, contentType, contentBase64 }` | `contentBase64` ≤ 7,200,000 characters |
| `POST /api/v1/me/requests/{id}/documents` (support) | `{ filename, contentType, contentBase64 }` | |
| LMS materials and submissions | `{ …, filename, contentType, contentBase64 }` alongside the text fields | |
| External examiners uploads, PG research documents | `{ kind, filename, contentType, contentBase64, note }` | `contentBase64` ≤ 36,000,000 characters |
| PG applicant documents, report snapshot files | `{ filename, contentType, base64, kind }` — note the field is named `base64` here | |
| `PUT /api/v1/staff/profile/photo` | base64 JPEG or PNG in a small JSON object | up to 2 MB |

Bulk data (a CAPS list, a course structure, a staff register, a PayDirect collections report, a NELFUND batch, an O'Level file) arrives as a JSON array of row objects — `{ "rows": [ {...}, {...} ] }` — parsed from the spreadsheet in the browser; 86 endpoints take a `rows` array. Large lists are sent in chunks that join the batch the first request opened (for example `POST /api/v1/admissions/caps-batches/{id}/rows`).

Downloads come back as bytes: handlers named `.../content`, `.../download`, `.../photo` and `.../image` set `Content-Type` from the stored type and, where a filename is known, `Content-Disposition: inline; filename="…"`. PDFs and branded Excel files are produced by the **frontend's** route handlers (`frontend/src/app/**/pdf/route.ts`, `…/template/route.ts`), not by the API; the API supplies the data. Every branded Excel/print export puts **S/N** as its first column, generated at export time, with names sorted A–Z.

### 1.10 Rate limits

Three in-memory counters exist. They are per API instance and reset when it restarts; they are not shared across replicas.

| Where | Limit | Key | Refusal |
|---|---|---|---|
| `GET /api/v1/verify/document`, `GET /api/v1/verify/document/{key}`, `GET /api/v1/verify/download/{token}` | **40 per 15 minutes** (`VERIFY_LIMIT`, `VERIFY_WINDOW_MS` in `DocumentsController`) | source address: first value of `X-Forwarded-For`, else the remote address | `422 VERIFY_THROTTLED` "Too many verifications from this source; try again in a few minutes." |
| `POST /api/v1/helpdesk/track` | **12 per 15 minutes** (`TRACK_LIMIT`) | counted twice — per source address and per email address | `422 HELPDESK_TRACK_SLOW_DOWN` "Too many lookups in a short time." |
| `POST /api/v1/pg/sign-in` | a run of failed sign-ins from one connection | source address | `422 AUTH_THROTTLED` "Too many failed sign-ins from this connection; try again in fifteen minutes." |

Everything else has **no rate limit**: the payment webhooks (dossier F records this explicitly), the other public verification endpoints (`/verify/receipt`, `/exam`, `/registration`, `/results`, `/report`, `/putme`, `/hostel` — these are gated instead by a check token or an unguessable reference, and answer `{"genuine": false}` otherwise), applicant registration, `POST /api/v1/pg/apply`, `GET /api/v1/pg/status`, the forgot-password doors (which answer identically whether or not the identifier names an account), and every authenticated endpoint. Password sign-in is protected by the account lock (five failures, fifteen minutes), not by a request counter. Throttling at the edge (Railway, a reverse proxy) is outside the repository and **not verified**.

### 1.11 Idempotency

**NOT IMPLEMENTED at the platform level.** The table `platform.idempotency_key` exists (migration V003) and the BFF forwards an `Idempotency-Key` header, but no Java code reads that header or that table. A repeated `POST` is therefore repeated work unless the database function behind it is written to be idempotent, which several are and say so: the applicant import (`admissions.import_applicant` — a number that already has an account counts as `exists`), CAPS rows appended to a batch, the lecturer import (`iam.import_lecturers`), the session roll-over, the postgraduate fee confirmation. Payment settlement is protected by the reference's own state (`ALREADY_SETTLED`, `PAY_ALREADY_CONFIRMED`), and the matriculation run by the series lock (a number issued is never issued again). Callers retrying anything else should first read the resource's state.

### 1.12 Public endpoints

`SecurityConfig.java` permits these paths without a token (`permitAll`); everything else is `authenticated()`:

| Path | Purpose |
|---|---|
| `/actuator/health`, `/actuator/health/**` | liveness and readiness probes |
| `GET /api/v1/platform/status` | service, commit, start time, database reachability |
| `POST /api/v1/auth/sign-in` | staff sign-in |
| `POST /api/v1/auth/bootstrap` | the first account, once, with `X-Bootstrap-Secret` equal to `MOAUM_AUTH_HMAC_SECRET` and an empty credential table |
| `GET /api/v1/auth/offices` | the office register for the sign-in page |
| `POST /api/v1/auth/forgot`, `POST /api/v1/auth/reset` | password reset (staff and students) |
| `GET /api/v1/auth/sso`, `GET /api/v1/auth/sso/start`, `POST /api/v1/auth/sso/callback` | single sign-on |
| `POST /api/v1/applicant/lookup`, `/register`, `/sign-in`, `/forgot`, `/reset` | the undergraduate applicant's door |
| `POST /api/v1/payments/webhook/paystack`, `/flutterwave`, `/quickteller` | gateway callbacks (§1.13) |
| `GET /api/v1/payments/quickteller/start?reference=` | the self-submitting form that posts a reference to Interswitch (HTML) |
| `POST /api/v1/student-auth/sign-in` | the student's door |
| `POST /api/v1/pg/apply`, `GET /api/v1/pg/programmes`, `GET /api/v1/pg/status`, `POST /api/v1/pg/sign-in`, `/api/v1/pg/referee/**` | postgraduate application, status check, sign-in, and the referee's link |
| `/api/v1/verify/**` | public verification of receipts, examination cards, registration forms, result statements, filed reports, Post-UTME slips, hostel letters and digital documents |
| `POST /api/v1/helpdesk/track` | a ticket's public status by number and email |
| `GET /api/v1/examiners/invitation/{token}`, `POST /api/v1/examiners/activate` | an external examiner's invitation and activation |

> **Note on the generated catalogue (§3):** the "Who may call" column is produced by a parser that reads each handler's own `@PreAuthorize` and marks a path *public* only when it is in the `permitAll` list above. The catalogue therefore lists 918 routes; handlers with no office guard and no `permitAll` entry read as "any signed-in user".

Forty endpoints require a token but name no office (`isAuthenticated()`): the `/me/*` desks of staff (`/api/v1/me/notices`, `/me/leave`, `/me/payslips`, `/me/teaching`), `GET /api/v1/iam/me`, `GET /api/v1/iam/offices`, `/api/v1/staff/me`, `/staff/profile`, `/staff/profile/photo`, `/staff/college/{code}`, `/api/v1/hr/staff/me`, `/api/v1/ref/structure`, `/ref/sessions`, `/ref/courses`, `/api/v1/allocation/departments`, `/api/v1/payments/gateways`, `/payments/verify`, `/api/v1/siwes/mine` and the requester side of the help desk (`/api/v1/helpdesk/my/*`, `/helpdesk/categories` — any signed-in person except an applicant).

### 1.13 Payment webhooks

The gateways call three public endpoints (`payments/PaymentsController.java`). A callback is never taken at its word: what it names is settled only for the amount the gateway confirms, and a callback whose signature does not verify is refused before its body is read.

| Gateway | Endpoint | Verification | Body read | Answer |
|---|---|---|---|---|
| Paystack | `POST /api/v1/payments/webhook/paystack` | header **`x-paystack-signature`** must equal the lower-case hex HMAC-SHA512 of the raw request body under the Paystack secret key (`MOAUM_PAYSTACK_SECRET`, or the key set encrypted from the Payment Gateways screen). A mismatch, a missing header, or Paystack not being wired → `401 {"outcome":"signature does not verify"}` and a `BAD_SIGNATURE` event on the record. | only `event = "charge.success"`; `data.reference`, `data.amount` (kobo, divided by 100), `data.status`, `data.id` | `200 {"outcome": …, "reference": …}`; anything but `charge.success` → `{"outcome":"ignored"}` |
| Flutterwave | `POST /api/v1/payments/webhook/flutterwave` | header **`verif-hash`** must equal the secret hash set on the Flutterwave dashboard and on the portal (`MOAUM_FLUTTERWAVE_HASH` or the dashboard key); compared in constant time. Mismatch → `401 {"outcome":"hash does not verify"}` and a `BAD_SIGNATURE` event. | `data.tx_ref`, `data.amount` (naira) | `200 {"outcome": …, "reference": …}` |
| Quickteller (Interswitch) | `POST /api/v1/payments/webhook/quickteller` | none — the notification is treated only as a hint | the reference it names is **re-queried** through Interswitch's requery API and settled on that answer alone | always `200` |

Outcomes recorded on `finance.gateway_event` (dossier F, `ck_ge_outcome`): `SETTLED`, `ALREADY_SETTLED`, `UNKNOWN_REFERENCE`, `SHORT_PAID`, `NOT_SUCCESSFUL`, `IGNORED`, `BAD_SIGNATURE`, `GATEWAY_ERROR`; sources `WEBHOOK`, `VERIFY`, `SWEEP`, `TEST`. A second callback for a reference already confirmed is answered `ALREADY_SETTLED` and changes nothing. The webhook address to register with each gateway is the API's origin plus the path (the Payment Gateways screen prints it). Keys are set by environment variable or by `PUT /api/v1/payments/gateways/{gateway}/key` (Director of ICT, System Administrator, Super Administrator); once set they are encrypted and never returned. Webhooks are tested end to end in `PaymentsIT` (a signed Paystack webhook confirms a fee once; an unsigned one is refused).

### 1.14 Scheduled jobs

Six pieces of work run on a timer inside the API (`@EnableScheduling` on `PortalApiApplication`). None is an endpoint; each runs under the system actor with an office, so its writes are on the audit trail.

| Job (class) | Schedule | What it does | Manual trigger |
|---|---|---|---|
| Notice dispatcher (`platform/NoticeDispatcher`) | every 60 s after a 15 s start delay (`MOAUM_NOTICES_EVERY_MS`, `MOAUM_NOTICES_INITIAL_MS`) | sends queued notices (email over SMTP from the Mail server screen or an HTTP provider; SMS through the configured provider). While no provider is configured notices stay `QUEUED` and the platform dashboard says so. | `POST /api/v1/platform/notices/{id}/retry`, `POST /api/v1/platform/notices/retry-failed` |
| Payments sweep (`payments/PaymentsService.sweep`) | every 10 minutes after a 2-minute start delay (`moaum.payments.sweep-every-ms`); skipped while no gateway is wired | asks each gateway about hanging attempts and settles a reference the gateway now says is paid, exactly as a webhook would | `POST /api/v1/payments/sweep` (Bursar, Director of ICT, System Administrator, Super Administrator) |
| Deferment clock (`deferments/DefermentClock`) | daily at 06:20 Africa/Lagos (`moaum.deferments.cron`, default `0 20 6 * * *`) | approved deferment periods that have begun come into force (status `DEFERRED`); approaching returns are reminded once | none |
| Hostel clock (`hostel/HostelClock`) | hourly at five past (`moaum.hostel.cron`, default `0 5 * * * *`, Africa/Lagos) | a hold that expired unpaid lapses and the bed passes to the next name on the waiting list | `POST /api/v1/hostel/lapse-all` |
| Examiner reminders (`examiners/ExaminerReminders`) | daily at 07:15 Africa/Lagos (fixed) | an external examiner whose deadline is three days off is reminded once; one whose deadline passed with nothing submitted is told once, as is the desk | none |
| Help-desk auto-closer (`helpdesk/AutoCloser`) | hourly after a 5-minute start delay | closes a resolved ticket the requester has not answered after the configured number of quiet days, and tells the requester; inert while `autoCloseDays` is unset (the shipped state) | none |

### 1.15 Health and status endpoints

| Endpoint | Auth | Answer |
|---|---|---|
| `GET /actuator/health` (and `/actuator/health/liveness`, `/actuator/health/readiness`) | none | Spring Boot health; details are never shown (`management.endpoint.health.show-details=never`). This is the health check in `api/railway.json`. |
| `GET /actuator/info` | bearer token (exposed, but not in the `permitAll` list) | Spring Boot info |
| `GET /api/v1/platform/status` | none | `{ "service": "portal-api", "commit": "<git sha or null>", "startedAt": "<ISO instant>", "database": { "reachable": true, "migrationsApplied": 263, "latestMigration": "V263__…", "admissionSettings2025_2026": "<state or 'absent'>" } }`; when the database is unreachable, `database.reachable` is `false` |
| `GET /api/v1/platform/readiness?session=` | Super Administrator, Director of ICT, System Administrator, Registrar, Deputy Registrar (Academic Affairs), Academic Officer, Bursar | the go-live gates for a session: `{ session, ready, blocking, warnings, checks: [{ key, label, status ok/warn/bad, detail, link }] }` — including whether a live gateway key, SMTP and SMS are configured |
| `GET /api/v1/platform/migrations` | Director of ICT, System Administrator, Super Administrator | the ledger `public.schema_migration` (filename, sha256, applied_at, applied_by) |
| `GET /healthz` (frontend) | none | `{ "status": "up", "service": "moaum-portal" }` |

---

## 2 Conventions for request and response bodies

### 2.1 General conventions

- **Request bodies** are JSON records declared inside each controller (`public record SignIn(...)`, `record RequestIn(...)`). Fields carry bean-validation constraints (`@NotBlank`, `@Size(max = …)`, `@Pattern`); a violation is a `400 VALIDATION_FAILED` naming the field. Unknown fields are ignored. Dates are ISO `yyyy-MM-dd`; instants are ISO-8601 with offset.
- **Response bodies** come in two styles and it matters which:
  - handlers that return a record or build a map by hand answer **camelCase** keys (`expiresAt`, `activeOffice`, `matricNo`);
  - handlers that return `jdbc.sql(...).query().listOfRows()` or `singleRow()` answer the **database column names as they are** — `snake_case` (`programme_code`, `issued_at`, `student_name`). The matriculation configuration, the documents office and most of the newer desks are in this style.
- `spring.jackson.default-property-inclusion=non_null`: a record field whose value is null is **omitted**, not written as `null`. Expect absent keys.
- Amounts are decimal numbers in naira (Paystack's kobo are converted at the boundary). Sessions are written `2025/2026`; in a path they are two segments, `/sessions/2025/2026`. Semesters are `1` or `2`. Levels are `100`–`600`.
- Identifiers are UUIDs unless the path says otherwise (a course `code`, a programme `code`, a matriculation number in a query parameter because it contains slashes).
- A successful write usually answers a small map describing what changed (`{"student": "…", "state": "QUERIED"}`); a create may answer `201` with a `Location` header (`POST /api/v1/iam/persons`, `POST /api/v1/iam/persons/{id}/office-assignments`).
- Every response carries `X-Correlation-Id`.

### 2.2 Worked example: staff sign-in

`POST /api/v1/auth/sign-in` — public. Record `AuthController.SignIn`.

Request:

```json
{ "username": "moaum/reg/0001", "password": "<password>", "office": "registrar" }
```

`username` and `password` are required (≤ 200 characters); `office` is optional and, when it names one of the person's offices, becomes the session's `active_office`. The username is lower-cased and trimmed before lookup.

Response `200` — `AuthService.SignedIn`:

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9.…",
  "expiresAt": "2026-09-26T22:14:03.118Z",
  "personId": "5f0c4a2e-4b1e-4c1e-9d2a-0f4d9e6a1c22",
  "surname": "ADAMU",
  "givenNames": "Terna Paul",
  "staffNumber": "MOAUM/REG/0001",
  "offices": [
    { "code": "registrar", "label": "Registrar", "scopeKind": "institution", "scopeId": "", "validTo": "" },
    { "code": "super", "label": "Super Administrator", "scopeKind": "platform", "scopeId": "", "validTo": "" }
  ],
  "mustChange": false
}
```

`expiresAt` is twelve hours after the sign-in. `mustChange` is `true` when the Registry set a first password; the frontend then routes to `/account/password`. Refusals: `400 VALIDATION_FAILED` (blank fields); `422 AUTH_BAD_CREDENTIALS` "That username and password do not match an account." (remedy: Registry — five failures lock the account for fifteen minutes); `422 AUTH_LOCKED` "This account is locked after repeated failures; try again after HH:MM:SS."; `422 AUTH_SIGN_IN_ELSEWHERE` when the API runs in issuer-URI mode.

The student door, `POST /api/v1/student-auth/sign-in` `{ "matricNo": "MOAU/TS/CSC/25/85632", "password": "…" }`, answers `{ token, expiresAt, studentId, matricNo, surname, otherNames, mustChange }`; the applicant door answers `{ token, expiresAt, accountId, applicationNo, surname, otherNames }`; the postgraduate door `{ token, expiresAt, applicantId, applicationNo, surname, otherNames }`.

### 2.3 Worked example: who am I

`GET /api/v1/iam/me` — any bearer token; no office required. Send `X-Active-Office` to see which office the call resolved to.

```text
GET /api/v1/iam/me
Authorization: Bearer <token>
X-Active-Office: academic
```

Response `200`:

```json
{
  "actorId": "5f0c4a2e-4b1e-4c1e-9d2a-0f4d9e6a1c22",
  "activeOffice": "academic",
  "offices": ["academic", "registrar"],
  "correlationId": "2d0f3e0a-9a7b-4f3c-8c1e-6b2a1d9e7f10",
  "name": "ADAMU, Terna Paul",
  "staffNumber": "MOAUM/REG/0001",
  "waiting": { "t/admissions": "12", "t/matriculation": "3", "t/clearance": "7" },
  "sessionId": "9c1e…(64 hex)"
}
```

`offices` is read from the token's authorities, `activeOffice` from the audit context (null when the token carries no office), `waiting` is a map from menu-item key to the count that waits on that desk (the Shell draws its badges from it and invents nothing), and `sessionId` is the token's `sid` (absent for a development token). For a token whose `sub` is not a known person, `name` and `staffNumber` are null. Without a token the answer is a bare `401` — the CI image job asserts exactly this.

### 2.4 Worked example: matriculate one student

`POST /api/v1/matriculation/sessions/{s}/{y}/students/{studentId}/matriculate` — Academic Officer (`academic`), Registrar (`registrar`), Deputy Registrar (Academic Affairs) (`dregistrar`). No body. Used for a straggler the batch run missed: a student who has since paid and registered.

```text
POST /api/v1/matriculation/sessions/2025/2026/students/0d6c1a2e-…/matriculate
Authorization: Bearer <token>
X-Active-Office: academic
X-Reason: Paid and registered after the run of 12 September
```

Response `200`:

```json
{ "student": "0d6c1a2e-…", "matricNo": "MOAU/TS/CSC/25/85632" }
```

The number is built by the database from the configuration of §2.5 — the University code, the faculty segment, the programme code where the programme carries one, the two-digit year of entry and the next number of the series the programme belongs to — and written to `people.matric_history` with its parts, the run and the officer. Nothing is typed. Refusals arrive as `422 DATABASE_RULE_REFUSED` with the function's message and HINT when the student is not admitted, not registered for the session, or still owing; `404 NOT_FOUND` for an unknown student. The batch equivalent is `POST /api/v1/matriculation/sessions/{s}/{y}/run`, which answers `{ "run": "<run ref>", "issued": <count> }` — one transaction, every number or none.

### 2.5 Worked example: configure a programme's matriculation code

`PUT /api/v1/matriculation/config/programmes/{code}` — Academic Officer, Registrar, Deputy Registrar (Academic Affairs), Super Administrator. Record `MatricFormatController.ProgrammeIn`.

Request:

```json
{ "matricCode": "CSC", "matricUsesCode": true, "matricFacultyCode": null, "matricSeries": null }
```

| Field | Meaning |
|---|---|
| `matricCode` | the programme's segment as the Registry's schedule prints it, 2–6 letters or digits; blank or null means none |
| `matricUsesCode` | whether the number carries the programme segment; when omitted it is `true` exactly when a code is given. `true` with no code is refused: `422 MATRIC_NO_CODE` "The programme is set to carry a code but none is given." — no code is ever invented |
| `matricFacultyCode` | a faculty segment of the programme's own (MBBS carries its own), else null to use the faculty's |
| `matricSeries` | the series the programme draws from (`ADMIN`, `COLLEGE`, `PHARMACY`, `ARCHITECTURE`, `GENERAL`, …), else null to use the faculty's |

Response `200` — one row of `people.matric_config_rows()`, in the database's column names:

```json
{
  "programme_code": "CSC",
  "programme": "Computer Science",
  "faculty_code": "TS",
  "faculty": "<faculty name>",
  "faculty_matric_code": "TS",
  "faculty_series": "GENERAL",
  "matric_code": "CSC",
  "matric_uses_code": true,
  "matric_faculty_code": null,
  "matric_series": null,
  "series_effective": "GENERAL",
  "sample": "MOAU/TS/CSC/26/85632",
  "problem": null,
  "students_admitted": 41,
  "archived": false,
  "category": "…"
}
```

`sample` is the number the programme would give next; `problem` reads "Configured to carry a code but has none" when that is the case. Other refusals: `422 MATRIC_CODE` (a code that is not 2–6 letters or digits), `404` for an unknown programme. The sibling endpoints follow the same shape: `PUT /config/format` (`{ universityCode, facultyCode, programmeCode, year, sequenceDigits, separator, note }`), `PUT /config/series/{code}` (`{ name, lastIssued, active, note }` — `lastIssued` may only move forward: `422 MATRIC_SERIES_BACK`), `PUT /config/faculties/{code}` (`{ matricCode, matricSeries }`), and `GET /config` returns `{ format, series, faculties, programmes, recent }`.

### 2.6 Worked example: a student requests a document

`POST /api/v1/me/documents/requests` — Student (`student`) only. Record `DocumentsController.RequestIn`.

Request:

```json
{
  "kind": "TRANSCRIPT",
  "session": null,
  "semester": null,
  "destination": "INSTITUTION",
  "destinationName": "University of Ibadan, Postgraduate School",
  "department": null,
  "recipientName": "The Secretary, Postgraduate School",
  "recipientEmail": "pgschool@example.edu.ng",
  "recipientAddress": "Ibadan, Oyo State",
  "recipientReference": "PG/2026/0417",
  "purpose": "Admission into M.Sc.",
  "delivery": "DIGITAL",
  "express": false,
  "international": false,
  "copies": 1
}
```

| Field | Rule |
|---|---|
| `kind` | required; one of `TRANSCRIPT`, `SESSIONAL_TRANSCRIPT`, `MINI_TRANSCRIPT`, `ACADEMIC_STATEMENT`. `DEGREE_CERTIFICATE` is refused with `422 DOC_KIND` "A degree certificate is issued by the Registry, not requested."; any other word is `422 DOC_KIND` |
| `session`, `semester` | for a sessional or mini transcript |
| `destination` | defaults to `SELF`; upper-cased |
| `delivery` | defaults to `DIGITAL`; `PHYSICAL` adds the physical fee |
| `express`, `international` | default `false`; each adds its fee from the policy |
| `copies` | default `1` |
| recipient fields | sizes 160/200/600/120; `purpose` ≤ 400 |

Response `200` — the row `credentials.request_document(...)` returns:

```json
{ "id": "3a7e…", "ref": "TRN-2026-00042", "fee": 5000.00, "reference": "MOAUM-…", "stage": "<the request's first stage>" }
```

`ref` is the request's own number (`TRN-YYYY-NNNNN`); `reference` is the payment reference raised for the fee (`finance.new_purpose_reference`, purpose "Transcript TRN-…"), which the student pays through §2.8; a free kind has no reference and starts further along. The student reads the request back with `GET /api/v1/me/documents/requests/{id}` (`{ …row…, events: [{action, from_state, to_state, note, at}], deliveries: [...] }`) and may cancel it with `POST …/{id}/cancel` `{ "reason": "…" }`. `GET /api/v1/me/documents` returns the library: `{ documents, requests, policies, sessions, student, counts }`.

### 2.7 Worked example: raise a help-desk ticket

`POST /api/v1/helpdesk/my/tickets` — any signed-in staff member or student (not an applicant). Record `HelpdeskController.Submit`.

Request:

```json
{
  "category": "PORTAL_ACCESS",
  "subject": "Cannot open the results screen",
  "description": "Since this morning the Results menu opens a blank page. Firefox 130, office Lecturer.",
  "email": null,
  "phone": "0803…",
  "details": { "session": "2025/2026", "semester": "1" }
}
```

`category` (≤ 40), `subject` (≤ 200) and `description` (≤ 8000) are required. `email` is used only when the account holds no address; `phone` overrides the account's. `details` is a map of the category's declared fields (`GET /api/v1/helpdesk/categories` lists them); undeclared keys are dropped, at most 30 are kept, each value trimmed to 500 characters.

Response `200`:

```json
{ "id": "b4c2…", "number": "TICK-2026-48213", "status": "SUBMITTED" }
```

The number is `TICK-<year in Africa/Lagos>-<five digits>`, drawn at random and retried on collision (V252). The requester is notified through the notices pipeline. Follow-ups: `POST …/my/tickets/{id}/comments` `{ "body": "…" }`; `POST …/my/tickets/{id}/attachments` `{ "filename", "contentType", "contentBase64" }` (PDF, JPEG or PNG, ≤ 5 MiB); `POST …/confirm`, `…/reopen`, `…/close`. The public status page uses `POST /api/v1/helpdesk/track` `{ "number": "TICK-2026-48213", "email": "…" }` and answers the ticket's status, times and a redacted timeline — never a name or an attachment.

### 2.8 Worked example: open a payment checkout

`POST /api/v1/payments/checkout` — Applicant (`applicant`) or Student (`student`). Record `PaymentsController.Checkout`.

Request:

```json
{ "reference": "MOAUM-APP-000123-7Q2K", "gateway": "paystack" }
```

`reference` is required and must be the caller's own (an applicant fee reference, a student fee reference or a postgraduate application reference); another person's reference is answered `404 NOT_FOUND` "fee reference … not found", never `403`. `gateway` is optional: when omitted the first wired gateway is used, in the order Paystack, Flutterwave, Quickteller; `GET /api/v1/payments/gateways` tells which are wired (`{ "paystack": true, "flutterwave": false, "quickteller": false, "paydirect": false }`).

Response `200`:

```json
{ "url": "https://checkout.paystack.com/…", "gateway": "paystack", "reference": "MOAUM-APP-000123-7Q2K" }
```

The browser is sent to `url`; the gateway returns it to the portal with `?paid=<reference>` and the webhook (§1.13) or the ten-minute sweep confirms the payment. For Quickteller the `url` is the portal's own `GET /api/v1/payments/quickteller/start?reference=…`, an HTML page that posts itself to Interswitch. For `"gateway": "paydirect"` the answer is an instruction rather than a redirect (`{ "gateway": "paydirect", "reference": …, "amount": …, … }` — pay the reference as a PRN on the biller). Refusals, all `422`: `PAY_ALREADY_CONFIRMED`, `PAY_REFERENCE_EXPIRED` ("Generate a new one; it is free of charge."), `PAY_NO_EMAIL` (a card checkout needs an email on the record), `PAY_GATEWAY_NOT_WIRED` (no secret set — pay by bank transfer against the reference), `PAY_GATEWAY_REFUSED` (the gateway did not open a checkout). A student or office may ask the gateway directly with `POST /api/v1/payments/verify` `{ "reference": "…" }`, which answers `{ "outcome": "SETTLED" | "already confirmed" | "not found at the gateway" | …, "reference": "…" }`.

### 2.9 Worked example: verify a document publicly

`GET /api/v1/verify/document?key=<verification code or document number>` — public, 40 calls per 15 minutes per source. A document number contains slashes, so the typed form goes in the query; the QR code's Crockford verification code may also go in the path: `GET /api/v1/verify/document/{key}`.

```text
GET /api/v1/verify/document?key=TRN-2026-000042
```

Response `200`:

```json
{ "result": "{\"status\":\"VALID\",\"kind\":\"TRANSCRIPT\",\"kindLabel\":\"Full transcript\",\"number\":\"TRN-2026-000042\",\"version\":1,\"issuedOn\":\"2026-09-20\",\"issuingInstitution\":\"…\",\"currentInstitutionName\":\"…\",\"issuingAuthority\":\"…\",\"verificationCode\":\"7K3M-…\",\"verifiedAt\":\"2026-09-26T…\"}" }
```

> **Note:** `result` is a JSON **string** — the handler returns the database's `jsonb` cast to text — so a client parses the outer object and then parses `result` again.

The inner object has `status` `VALID`, `REVOKED` (adds `revokedOn`, `revokedUnder`), `REPLACED` (adds `replacedBy`), `NOT_FOUND` (with a `remedy` and `verifiedAt`) or `INVALID` (a stored hash that no longer matches its content), plus the fields the document's policy marks public (`public_fields`). Every call is logged to `credentials.verification` with the source address and user agent; past the limit the answer is `422 VERIFY_THROTTLED`. The other verification doors answer a plain object with `"genuine": true|false` and the record's fields — for a receipt, `GET /api/v1/verify/receipt/{reference}?c=<12-hex check token>` gives `{ genuine, name, matricNo, programme, level, amount, purpose, session, term, channel, confirmedOn, receiptNo, passport }`; without the matching `c` it is `{ "genuine": false }` and nothing else.

---

## 3 Endpoint catalogue

The tables below are the generated catalogue (`inv/generated/api-reference.md`, produced by `parse_api.py` from every `@RestController` in `api/src/main/java/ng/edu/moaum/portal`), reproduced in full and unchanged: for each endpoint the method, the path, the purpose (the handler's Javadoc or comment, else its method name), the offices named in its `@PreAuthorize` guard, and the source file and line. Groups are in the generator's order and keep its unnumbered headings. A one-paragraph description drawn from the audit dossiers opens each group. Office codes are those of *04 Role and Permission Matrix* (`academic` Academic Officer, `dregistrar` Deputy Registrar (Academic Affairs), `records` Exams and Records, `ict` Director of ICT, `ictagent` ICT Support Agent, `housing` Deputy Registrar (Housing, Welfare, Passages), `services` Support Services, `pgschool` Dean of the Postgraduate School, `pgsecretary` its Secretary, `extexaminer` External Examiner, `super` Super Administrator, `admin` System Administrator). *any signed-in user* means a token with no office requirement; *public* means no token. Read the corrections of §1.12 before relying on the *Who may call* column of the `auth`, `platform`, `applicant` and `student-auth` rows, and ignore the five `ANY` rows whose path repeats itself.

Total endpoints: 918. Base URL: `https://<host>/api/v1`. All endpoints except those marked *public* require `Authorization: Bearer <token>`; state-changing calls made through the frontend also carry an `X-Reason` header that becomes the audit reason.

### API keys (`apimgmt`, 5 endpoints)

The register of external API consumers and the hashed, expiring keys issued to them (shown once). A register only: no request is authenticated by an API key, and scopes and quotas are stored but not enforced (see §5.4). Director of ICT, System Administrator and Super Administrator.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/apimgmt/consumers` | consumers, and the keys on each (metadata only — a key is never shown again after issue) | admin, ict, super | `apimgmt/ApiKeysController.java:42` |
| POST | `/api/v1/apimgmt/consumers` | register | admin, ict, super | `apimgmt/ApiKeysController.java:62` |
| POST | `/api/v1/apimgmt/consumers/{id}/deprecate` | deprecate | admin, ict, super | `apimgmt/ApiKeysController.java:90` |
| POST | `/api/v1/apimgmt/consumers/{id}/keys` | issue a key; the plaintext is returned here and never again | admin, ict, super | `apimgmt/ApiKeysController.java:73` |
| POST | `/api/v1/apimgmt/keys/{id}/revoke` | revoke | admin, ict, super | `apimgmt/ApiKeysController.java:82` |

### Academic calendar (`calendar`, 8 endpoints)

The University's academic calendar: sessions, their semesters, which session is current, and the unit limits per level. Written by the Academic Office, the Registry and ICT; `close`, `make-current`, `roll-over` (promote continuing students one level and enrol them) and `enrol-all` (enrol the current cohort without promotion) move the register from one session to the next. Every signed-in office reads it.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/calendar` | Every session, which one is current, the semesters of the session asked for, and the unit limits. | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:37` |
| PUT | `/api/v1/calendar/levels/{level}` | saveLevel | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:85` |
| PUT | `/api/v1/calendar/sessions/{session}/{year}` | saveSession | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:42` |
| POST | `/api/v1/calendar/sessions/{session}/{year}/close` | close | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:56` |
| POST | `/api/v1/calendar/sessions/{session}/{year}/enrol-all` | Enrol every currently-studying student into this session at their current level, without promoting anyone. The backfill that matches an already-loaded cohort to the session they are in now. | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:64` |
| POST | `/api/v1/calendar/sessions/{session}/{year}/make-current` | makeCurrent | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:49` |
| POST | `/api/v1/calendar/sessions/{session}/{year}/roll-over` | Roll the register into this session: promote continuing students one level and enrol them. | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:71` |
| PUT | `/api/v1/calendar/sessions/{session}/{year}/semesters/{number}` | saveSemester | academic, dregistrar, ict, registrar, super | `calendar/CalendarController.java:78` |

### Academic structure & courses (`catalogue`, 35 endpoints)

The academic structure — faculties, departments, programmes — and the course catalogue with each programme's structure by level. Creating, importing, archiving and deleting structure is the Director of ICT's alone; the course lifecycle (`BOARD`/`SENATE` → `LIVE` → ended, restore), CCMAS/BMAS curriculum tags, the CA/examination split of a course's hundred marks, duplicate clean-up and opening registration for a session belong to the Academic Office, the Registry, Deans and Heads of Department.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/catalogue/catalogue-export` | the whole uploaded catalogue — every course offered to every programme — for a download | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:538` |
| GET | `/api/v1/catalogue/courses` | every course a department owns, with the lecturer of its offering in the current session, if any | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:256` |
| POST | `/api/v1/catalogue/courses` | create | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:587` |
| POST | `/api/v1/catalogue/courses/live-all` | make every awaiting-approval course in a department Live in one action (optionally one level) | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:652` |
| GET | `/api/v1/catalogue/courses/search` | a course anywhere in the University, by code or title, for the structure's picker | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:393` |
| POST | `/api/v1/catalogue/courses/{code}/curriculum` | tag one course's curriculum (CCMAS / BMAS, or blank to clear) so registration shows it to the matching cohort only (V116/V160) | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:410` |
| GET | `/api/v1/catalogue/courses/{code}/eligibility` | who may register a course: the eligible programme-and-level set, assigned at creation, with how many are registered | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:556` |
| POST | `/api/v1/catalogue/courses/{code}/end` | end | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:599` |
| POST | `/api/v1/catalogue/courses/{code}/live` | make one course Live: a BOARD/SENATE course becomes LIVE (an uploaded, approved course) | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:638` |
| POST | `/api/v1/catalogue/courses/{code}/restore` | reverse an end: an ended course returns to LIVE and re-enters next session's registration | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:624` |
| POST | `/api/v1/catalogue/courses/{code}/split` | how one course's hundred marks split between continuous assessment and the examination (V239): the CA share; the examination is the rest | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:430` |
| POST | `/api/v1/catalogue/curriculum/bulk` | tag a whole department's live courses (optionally one level) with a curriculum in one action — e.g. set every 400 level course to BMAS for the outgoing cohort | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:462` |
| GET | `/api/v1/catalogue/departments` | departments | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:122` |
| POST | `/api/v1/catalogue/departments` | newDepartment | ict | `catalogue/CatalogueController.java:137` |
| POST | `/api/v1/catalogue/departments/import` | importDepartments | ict | `catalogue/CatalogueController.java:146` |
| DELETE | `/api/v1/catalogue/departments/{code}` | delete a department (only when it holds no programme and no course) | ict | `catalogue/CatalogueController.java:155` |
| GET | `/api/v1/catalogue/duplicates` | the duplicate courses in a department: each group's keeper and the codes that would be ended | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:498` |
| POST | `/api/v1/catalogue/duplicates/end` | end the duplicate courses in a department, keeping the cleanest code in each group | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:510` |
| GET | `/api/v1/catalogue/faculties` | faculties | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:90` |
| POST | `/api/v1/catalogue/faculties` | newFaculty | ict | `catalogue/CatalogueController.java:104` |
| POST | `/api/v1/catalogue/faculties/import` | importFaculties | ict | `catalogue/CatalogueController.java:112` |
| DELETE | `/api/v1/catalogue/faculties/{code}` | delete a faculty (only when it holds no programme and no course-bearing department) | ict | `catalogue/CatalogueController.java:221` |
| POST | `/api/v1/catalogue/import` | upload a programme's course structure (a CCMAS table): each course is created and offered at its level | ict | `catalogue/CatalogueController.java:230` |
| GET | `/api/v1/catalogue/offered` | every course offered to a programme, level by level — the view for the course-upload desk | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:523` |
| POST | `/api/v1/catalogue/open-registration` | open course registration for a session: create an offering for every offered course of that semester, so students see the real programme/level courses (not leftover demo offerings) | academic, admin, dean, dregistrar, hod, ict, registrar, super | `catalogue/CatalogueController.java:246` |
| GET | `/api/v1/catalogue/programmes` | programmes | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:165` |
| POST | `/api/v1/catalogue/programmes` | newProgramme | ict | `catalogue/CatalogueController.java:180` |
| POST | `/api/v1/catalogue/programmes/import` | importProgrammes | ict | `catalogue/CatalogueController.java:191` |
| DELETE | `/api/v1/catalogue/programmes/{code}` | hard-delete a programme (only when nothing hangs on it) | ict | `catalogue/CatalogueController.java:212` |
| POST | `/api/v1/catalogue/programmes/{code}/archive` | archive or restore a programme — the safe removal; it keeps its code | ict | `catalogue/CatalogueController.java:203` |
| POST | `/api/v1/catalogue/split/bulk` | the same split for a whole department's live courses, optionally one level | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:443` |
| GET | `/api/v1/catalogue/structure` | every course a programme offers, by level and semester, with the level's unit limits | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super, vc | `catalogue/CatalogueController.java:311` |
| DELETE | `/api/v1/catalogue/structure/bind` | unbind a course from a programme at a level — refused while a student of that programme and level is registered on it this session | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:365` |
| POST | `/api/v1/catalogue/structure/bind` | bind a course into a programme's structure at a level, on a basis, for a track (or every track) | academic, admin, dean, dregistrar, hod, registrar, super | `catalogue/CatalogueController.java:338` |
| GET | `/api/v1/catalogue/upload-coverage` | how far course-structure upload has got: programmes with a structure loaded vs. still to upload, the totals, the split by faculty, and the list still pending — for the ICT/management dashboard | academic, admin, dean, dregistrar, dvc, hod, ict, registrar, super, vc | `catalogue/CatalogueController.java:683` |

### Alumni (`alumni`, 1 endpoints)

One read: the alumni register for the Registry, the academic offices and audit.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/alumni` | alumni | academic, admin, audit, deputyaudit, dregistrar, dvc, records, registrar, super, vc | `alumni/AlumniController.java:26` |

### Applicant portal (`applicant`, 17 endpoints)

The undergraduate applicant's own portal: look up a JAMB number, register an account, sign in, biodata and next of kin, documents (base64 upload and download), fee references, submission with the declaration, acceptance of an offer with the undertaking, and password reset. Applicant-only except the public doors listed in §1.12.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| POST | `/api/v1/applicant/forgot` | always 202: whether or not the identifier names an account, the answer is the same | public | `applicant/ApplicantController.java:148` |
| POST | `/api/v1/applicant/lookup` | lookup | public | `applicant/ApplicantController.java:67` |
| GET | `/api/v1/applicant/me` | me | applicant | `applicant/ApplicantController.java:90` |
| POST | `/api/v1/applicant/me/accept` | accept | applicant | `applicant/ApplicantController.java:129` |
| POST | `/api/v1/applicant/me/decline` | decline | applicant | `applicant/ApplicantController.java:135` |
| POST | `/api/v1/applicant/me/documents` | upload | applicant | `applicant/ApplicantController.java:108` |
| GET | `/api/v1/applicant/me/documents/{id}/content` | content | applicant | `applicant/ApplicantController.java:114` |
| POST | `/api/v1/applicant/me/fee-references` | feeReference | applicant | `applicant/ApplicantController.java:102` |
| PUT | `/api/v1/applicant/me/next-of-kin` | nextOfKin | applicant | `applicant/ApplicantController.java:96` |
| POST | `/api/v1/applicant/me/submit` | submit | applicant | `applicant/ApplicantController.java:123` |
| GET | `/api/v1/applicant/me/eligibility` | the applicant's own current evaluation: verdict, reasons, the eligible alternatives, change requests, `canRequestChange`; `available` false before submission | applicant | `admissions/AdmissionEligibilityController.java:292` |
| POST | `/api/v1/applicant/me/eligibility/recalculate` | re-read the applicant's own record (APPLICANT) | applicant | `admissions/AdmissionEligibilityController.java:311` |
| POST | `/api/v1/applicant/me/eligibility/change` | request a change to a programme the current run found the applicant eligible for `{ programmeCode, note }`; otherwise 422 `ELIG_NOT_SUGGESTED` | applicant | `admissions/AdmissionEligibilityController.java:320` |
| POST | `/api/v1/applicant/register` | register | public | `applicant/ApplicantController.java:72` |
| POST | `/api/v1/applicant/reset` | reset | public | `applicant/ApplicantController.java:154` |
| POST | `/api/v1/applicant/sign-in` | signIn | public | `applicant/ApplicantController.java:77` |
| POST | `/api/v1/applicant/sign-out` | signOut | applicant | `applicant/ApplicantController.java:82` |

### Audit log (`auditlog`, 2 endpoints)

The audit spine read back: `entries` (filterable) and `facets` (the actions and offices present). Director of Internal Audit, Deputy Director of Audit, Vice-Chancellor, Director of ICT, System Administrator, Super Administrator.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/audit/entries` | entries | admin, audit, deputyaudit, ict, super, vc | `auditlog/AuditLogController.java:29` |
| GET | `/api/v1/audit/facets` | the actions and offices present, for the filters | admin, audit, deputyaudit, ict, super, vc | `auditlog/AuditLogController.java:92` |

### Authentication (`auth`, 12 endpoints)

Staff authentication: sign-in and sign-out, the caller's sessions, change of password, forgot/reset, single sign-on (describe, start, callback), the once-only bootstrap of the first account, and the office register for the sign-in page. See §1.3 and the correction to the *Who may call* column in §1.12: only the paths named there are public; `sign-out`, `change-password` and `sessions` need a token.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| POST | `/api/v1/auth/bootstrap` | The first account, once, with the secret the API already trusts. | public | `auth/AuthController.java:119` |
| POST | `/api/v1/auth/change-password` | change | any signed-in user | `auth/AuthController.java:112` |
| POST | `/api/v1/auth/forgot` | a staff member or student asks to reset a forgotten password; the answer is the same whether or not it names an account | public | `auth/AuthController.java:61` |
| GET | `/api/v1/auth/offices` | the office register, for the sign-in page's "Your office" | public | `auth/AuthController.java:127` |
| POST | `/api/v1/auth/reset` | reset | public | `auth/AuthController.java:67` |
| GET | `/api/v1/auth/sessions` | sessions | any signed-in user | `auth/AuthController.java:101` |
| POST | `/api/v1/auth/sessions/{id}/end` | end | any signed-in user | `auth/AuthController.java:106` |
| POST | `/api/v1/auth/sign-in` | signIn | public | `auth/AuthController.java:90` |
| POST | `/api/v1/auth/sign-out` | signOut | any signed-in user | `auth/AuthController.java:95` |
| GET | `/api/v1/auth/sso` | ssoDescribe | public | `auth/AuthController.java:75` |
| POST | `/api/v1/auth/sso/callback` | ssoCallback | public | `auth/AuthController.java:85` |
| GET | `/api/v1/auth/sso/start` | ssoStart | public | `auth/AuthController.java:80` |

### CBT question bank (`cbt`, 4 endpoints)

The question bank behind the Post-UTME computer-based test: the courses that carry questions, the questions themselves, adding one and switching it active or inactive. Lecturers, Examinations Officers, Heads of Department and Deans write; the Academic Office, the Registrar and faculty officers read.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/cbt/courses` | courses | academic, admin, dean, exams, facultyexams, hod, lecturer, registrar, super | `cbt/QuestionBankController.java:46` |
| GET | `/api/v1/cbt/questions` | questions | academic, admin, dean, exams, facultyexams, hod, lecturer, registrar, super | `cbt/QuestionBankController.java:56` |
| POST | `/api/v1/cbt/questions` | add | dean, exams, hod, lecturer, super | `cbt/QuestionBankController.java:75` |
| POST | `/api/v1/cbt/questions/{id}/active` | setActive | dean, exams, hod, lecturer, super | `cbt/QuestionBankController.java:99` |

### Clearance (`clearance`, 6 endpoints)

Final clearance by unit (Bursary, Department, Faculty, Library, Health, Hostel, Works and Maintenance, Alumni and Convocation): a student's position, a unit's clear or hold, the units, and the listing. `notify-held` is a placeholder that counts rather than sends.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/clearance` | listing | academic, admin, bursar, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, library, records, registrar, services, super, vc | `clearance/ClearanceController.java:38` |
| POST | `/api/v1/clearance/notify-held` | No notification module yet: the notice is counted, not sent, and the answer says so. | academic, bursar, dean, dregistrar, hod, housing, library, registrar, services | `clearance/ClearanceController.java:73` |
| GET | `/api/v1/clearance/students/{id}` | position | academic, admin, bursar, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, library, records, registrar, services, super, vc | `clearance/ClearanceController.java:54` |
| POST | `/api/v1/clearance/students/{id}/{unit}/clear` | clear | academic, bursar, dean, dregistrar, hod, housing, library, registrar, services | `clearance/ClearanceController.java:60` |
| POST | `/api/v1/clearance/students/{id}/{unit}/hold` | hold | academic, bursar, dean, dregistrar, hod, housing, library, registrar, services | `clearance/ClearanceController.java:66` |
| GET | `/api/v1/clearance/units` | units | academic, admin, bursar, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, library, records, registrar, services, super, vc | `clearance/ClearanceController.java:48` |

### College of Health Sciences (`college`, 40 endpoints)

The College of Health Sciences (MBBS): the College calendar and levels, the fee gate per session, typed attendance, continuous assessment and examination marks by level, provisional results with automatic application and Board confirmation, postings and rotations, professional examinations, and the College dashboard the Provost's desk opens. Provost, College Secretary, MBBS Coordinator, Finance Controller, the Registry and the Academic Office act; Deans and lecturers read.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| POST | `/api/v1/college/allocations` | allocate students to a posting for a session; a student already on it has their group, supervisor and dates set | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:172` |
| DELETE | `/api/v1/college/allocations/{id}` | withdraw an allocation made in error — only while it is still merely allocated | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:243` |
| PUT | `/api/v1/college/allocations/{id}` | change one allocation: its state (allocated, in progress, completed, incomplete), group, supervisor or dates | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:219` |
| POST | `/api/v1/college/allocations/{id}/attendance` | the student's attendance at a session of the posting — a lecture, a ward round, a clinic, a test | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:472` |
| POST | `/api/v1/college/allocations/{id}/cases` | a case the student clerked, verified by the supervisor | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:457` |
| POST | `/api/v1/college/allocations/{id}/events` | attendance at a mandatory event of the block — the Wednesday Grand Round | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:492` |
| GET | `/api/v1/college/allocations/{id}/logbook` | one student's logbook on one posting: requirements and what is logged, cases, attendance, the mandatory events | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:366` |
| POST | `/api/v1/college/allocations/{id}/procedures` | a procedure the student observed or performed; verified at once by the supervisor unless said otherwise | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:420` |
| PUT | `/api/v1/college/allocations/{id}/procedures/{log}/verify` | verify a procedure the student logged | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:442` |
| GET | `/api/v1/college/assessments` | the CA collected during a year — course tests, end-of-posting scores — kept as they happen, graded never; the examiner composes the year's CA from them | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:841` |
| POST | `/api/v1/college/assessments` | assess | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:862` |
| GET | `/api/v1/college/calendar` | the College's calendar for a session: each level's semesters, dated by the College (the prospectus gives lengths, never dates) | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:799` |
| PUT | `/api/v1/college/calendar` | one semester of one level dated for the session; cleared when both dates are blank | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:820` |
| GET | `/api/v1/college/coordinator` | the MBBS Coordinator's own summary: the level held, its examination, the cohorts with years open or closed, and what each waits on | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:945` |
| GET | `/api/v1/college/dashboard` | the College officers' dashboard: what waits on the College — decisions for the Board, results at the end of a year, cohorts not fully registered, undated calendars, appeals with Senate, levels without a coordinator — the | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:1143` |
| POST | `/api/v1/college/enrol` | the desk opens a student's College year for a cohort — a paper registration, a transfer — so the candidate list is complete | academic, admin, collegesecretary, dregistrar, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:785` |
| GET | `/api/v1/college/exams` | the CPE and the four Professionals, each with its subjects and their CA items | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:515` |
| GET | `/api/v1/college/exams/summary` | the five examinations in a session, each with its cohort's standing: enrolled, fully registered, with a result in every subject, decided provisionally, confirmed, and whether the year has reached its end — the desk's lan | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:1294` |
| POST | `/api/v1/college/exams/{code}/appeals` | Senate's approval of an appeal after the Final: the fourth and final attempt at 600 Level opens for the session named | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:769` |
| GET | `/api/v1/college/exams/{code}/candidates` | the candidates for an examination in a session — the College's students at its level — with each subject's results by attempt and the progression decision, if any | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:527` |
| POST | `/api/v1/college/exams/{code}/confirm` | the College Academic Board's act: every provisional decision of the examination in the session confirmed on its minute, and each student moved — the next level, the resit, the repeat year, the withdrawal, graduation with | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:756` |
| POST | `/api/v1/college/exams/{code}/decisions` | the progression decision after an examination: what the rule recommends is shown; the College Academic Board decides | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:644` |
| GET | `/api/v1/college/exams/{code}/recommend` | what the rule recommends for a candidate from their latest results: the next attempt, and the courses owed | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:680` |
| GET | `/api/v1/college/exams/{code}/reconciliation` | the reconciliation the crossing to Senate needs: every candidate accounted for in every subject, or named | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:699` |
| POST | `/api/v1/college/exams/{code}/results` | one subject's result for one candidate at one attempt, with the attendance the examiner types; the pass is judged by the rule, never typed (below the examination's minimum attendance the candidate is barred); once every  | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:570` |
| POST | `/api/v1/college/exams/{code}/results/bulk` | the level's score sheet, uploaded: every row a cohort member by number, every mark judged by the rule as it is saved, the rule's decision applied provisionally where a candidate's subjects are then all resulted; a row th | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:891` |
| GET | `/api/v1/college/exams/{code}/uploads` | the uploads of a cohort's score sheet, as the audit spine records them: when, by whom in which office, and how many marks each wrote or changed — every mark saved by hand on the desk is listed too, under its own reason | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:1315` |
| GET | `/api/v1/college/my-assessments` | the signed-in student's CA as recorded during the year — course tests, end-of-posting scores — graded never, kept as they happen | student | `college/CollegeController.java:276` |
| GET | `/api/v1/college/my-logbooks` | the signed-in student's own logbooks: for each posting allocated, what it asks and what stands verified | student | `college/CollegeController.java:258` |
| GET | `/api/v1/college/my-postings` | the signed-in student's own postings, every session, with the logbook standing of each | student | `college/CollegeController.java:290` |
| GET | `/api/v1/college/my-record` | myRecord | student | `college/CollegeController.java:1334` |
| GET | `/api/v1/college/my-supervision` | the postings the acting person supervises this session, each with its students and where each stands | academic, admin, collegesecretary, dregistrar, exams, hod, lecturer, provost, registrar, super | `college/CollegeController.java:340` |
| GET | `/api/v1/college/overview` | the College overview: every level with its students, open years and cohorts, its examination and where its decisions stand; the session's postings; the blocks — the live picture the College's officers open the module on | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:1097` |
| GET | `/api/v1/college/payments` | The Student Payment Report (V256): every College student's position for a session, or for one semester of it — amount payable, amount paid, amount outstanding, payment status, the last payment — with the totals and the s | academic, bursar, collegesecretary, dregistrar, dvc, financecontroller, provost, registrar, super, vc | `college/CollegeController.java:1003` |
| GET | `/api/v1/college/postings/{id}/allocations` | the allocations to one posting in a session | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:131` |
| POST | `/api/v1/college/register` | the student's act: the level's fixed curriculum registered for the session, once the fees are cleared | student | `college/CollegeController.java:1422` |
| GET | `/api/v1/college/requirements` | what the logbook asks, by posting and block, from the prospectus (V245): the procedures with their minimum counts and whether observed or performed, the cases to clerk, the attendance rules by phase and block, the mandat | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:1270` |
| GET | `/api/v1/college/structure` | the College's blocks with their postings, courses and rotation groups; and the levels with their phase | academic, admin, collegesecretary, dean, dregistrar, dvc, exams, financecontroller, hod, lecturer, mbbscoordinator, provost, records, registrar, super, vc | `college/CollegeController.java:85` |
| GET | `/api/v1/college/students` | the College's students at a level, each with their allocations for the session | academic, admin, collegesecretary, dregistrar, mbbscoordinator, provost, registrar, super | `college/CollegeController.java:105` |
| GET | `/api/v1/college/supervisors` | the College's academic staff who may supervise a posting: anyone holding a lecturer, HOD or examinations office scoped to a department of the College's faculties | academic, admin, collegesecretary, dregistrar, provost, registrar, super | `college/CollegeController.java:151` |

### Course allocation (`allocation`, 7 endpoints)

Teaching allocation: a department's offerings for a session and semester, the lecturers available with their load, assigning the lead lecturer and second examiner, adding and removing co-lecturers, and the history of who carried what. Heads of Department, Deans, the Academic Office and the Registry.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/allocation` | the department's offerings for a session and semester, with who is on each and how many are registered | academic, admin, dean, dregistrar, hod, registrar, super | `allocation/AllocationController.java:116` |
| GET | `/api/v1/allocation/departments` | the departments a lecturer can be allocated in (reference data, any signed-in staff) | any signed-in user | `allocation/AllocationController.java:104` |
| GET | `/api/v1/allocation/history` | The history of teaching allocation, every session on record: with scope=me, the courses the acting person has carried (as lecturer or co-lecturer); with scope=department, every course of the acting office's department —  | academic, admin, dean, dregistrar, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar, super | `allocation/AllocationController.java:54` |
| GET | `/api/v1/allocation/lecturers` | The lecturers a course can be allocated to, with their current teaching load. By default the department's own lecturers; with all=true, every lecturer in the University (each labelled with their home department) so a dep | academic, admin, dean, dregistrar, hod, registrar, super | `allocation/AllocationController.java:164` |
| POST | `/api/v1/allocation/{offering}` | assign the lead lecturer and a second examiner to an offering | academic, admin, dean, dregistrar, hod, registrar, super | `allocation/AllocationController.java:224` |
| POST | `/api/v1/allocation/{offering}/teachers` | add a co-lecturer who also teaches the course and enters scores on the shared sheet | academic, admin, dean, dregistrar, hod, registrar, super | `allocation/AllocationController.java:256` |
| DELETE | `/api/v1/allocation/{offering}/teachers/{lecturer}` | remove a co-lecturer (the lead is changed by re-assigning, not here) | academic, admin, dean, dregistrar, hod, registrar, super | `allocation/AllocationController.java:274` |

### Course registration (`registration`, 16 endpoints)

Course registration: the desk that lists, approves and returns students' registrations (a single HOD step), the class register (attendance by day), lecture slots and the examination slot beside a class list, plus direct upserts of courses, offers and offerings that no screen uses (§4).

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/registration/class-list` | The roll of an offering: approved registrations only, and all of them. | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `registration/RegistrationController.java:113` |
| GET | `/api/v1/registration/course-registrations` | the registrations students submitted, in a session and semester, for the department to approve or return | academic, dean, dregistrar, facultyofficer, hod, lecturer, registrar, super | `registration/DeskController.java:56` |
| POST | `/api/v1/registration/course-registrations` | create | academic, dregistrar, hod, lecturer, registrar, super | `registration/RegistrationController.java:68` |
| POST | `/api/v1/registration/course-registrations/{id}/approve` | approve | hod, super | `registration/RegistrationController.java:80` |
| POST | `/api/v1/registration/course-registrations/{id}/return` | giveBack | hod, super | `registration/RegistrationController.java:86` |
| POST | `/api/v1/registration/course-registrations/{id}/submit` | submit | academic, dregistrar, hod, lecturer, registrar, super | `registration/RegistrationController.java:74` |
| PUT | `/api/v1/registration/courses/{code}` | course | academic, dregistrar, hod, registrar, super | `registration/RegistrationController.java:40` |
| POST | `/api/v1/registration/courses/{code}/end` | end | academic, dregistrar, hod, registrar, super | `registration/RegistrationController.java:46` |
| PUT | `/api/v1/registration/courses/{code}/offers/{programme}/{level}` | offer | academic, dregistrar, hod, registrar, super | `registration/RegistrationController.java:54` |
| PUT | `/api/v1/registration/offerings` | offering | academic, dregistrar, hod, registrar, super | `registration/RegistrationController.java:62` |
| GET | `/api/v1/registration/offerings/{offeringId}/attendance` | attendanceOf | academic, dean, dregistrar, facultyofficer, hod, lecturer, registrar, super | `registration/DeskController.java:107` |
| POST | `/api/v1/registration/offerings/{offeringId}/attendance` | the register of one class on one day, over the class list; marking again on the same day replaces the day's register | dean, hod, lecturer, super | `registration/DeskController.java:98` |
| GET | `/api/v1/registration/offerings/{offeringId}/exam-slot` | the paper's slot on the examination timetable, read beside the class list | academic, dean, dregistrar, facultyofficer, hod, lecturer, registrar, super | `registration/DeskController.java:152` |
| GET | `/api/v1/registration/offerings/{offeringId}/slots` | slots | academic, dean, dregistrar, facultyofficer, hod, lecturer, registrar, super | `registration/DeskController.java:126` |
| POST | `/api/v1/registration/offerings/{offeringId}/slots` | addSlot | dean, hod, lecturer, super | `registration/DeskController.java:133` |
| POST | `/api/v1/registration/offerings/{offeringId}/slots/{slotId}/end` | endSlot | dean, hod, lecturer, super | `registration/DeskController.java:143` |

### Dean's desk (`dean`, 1 endpoints)

The Dean's dashboard figures for a faculty (Dean, Faculty Officer, Super Administrator).

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/dean/dashboard` | dashboard | dean, facultyofficer, super | `dean/DeanController.java:50` |

### Deferments (`deferments`, 16 endpoints)

Deferment of studies (V259): the student's request with reasons and documents, the desks that decide within their bounds (department, faculty, Registry, College), extensions, returns, the settings, and the queue with paging. The daily clock (§1.14) brings approved periods into force.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/deferments` | list | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:271` |
| GET | `/api/v1/deferments/dashboard` | dashboard | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:329` |
| GET | `/api/v1/deferments/returns` | returns | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:367` |
| POST | `/api/v1/deferments/tick` | the tick, callable by the Registry (the clock also runs it each morning) | academic, dregistrar, ict, registrar, super | `deferments/DefermentsController.java:469` |
| GET | `/api/v1/deferments/{id}` | deskOne | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:379` |
| POST | `/api/v1/deferments/{id}/action` | act | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:420` |
| GET | `/api/v1/deferments/{id}/documents/{doc}/content` | deskDocument | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:460` |
| POST | `/api/v1/deferments/{id}/return` | confirmReturn | academic, admin, collegesecretary, dean, dregistrar, facultyofficer, hod, pgschool, pgsecretary, provost, records, registrar, super | `deferments/DefermentsController.java:446` |
| GET | `/api/v1/me/deferments` | mine | student | `deferments/DefermentsController.java:114` |
| POST | `/api/v1/me/deferments` | open | student | `deferments/DefermentsController.java:136` |
| GET | `/api/v1/me/deferments/{id}` | myOne | student | `deferments/DefermentsController.java:158` |
| PUT | `/api/v1/me/deferments/{id}` | change | student | `deferments/DefermentsController.java:147` |
| POST | `/api/v1/me/deferments/{id}/cancel` | myCancel | student | `deferments/DefermentsController.java:176` |
| POST | `/api/v1/me/deferments/{id}/documents` | upload | student | `deferments/DefermentsController.java:189` |
| GET | `/api/v1/me/deferments/{id}/documents/{doc}/content` | myDocument | student | `deferments/DefermentsController.java:220` |
| POST | `/api/v1/me/deferments/{id}/submit` | submit | student | `deferments/DefermentsController.java:165` |

### Documents, certificates & ID cards (`credentials`, 48 endpoints)

Digital academic documents (V262) on the credential store: the student's library and requests, the documents office pipeline (queue, start, generate, quality check, release, deliveries, complete), the register of issued documents with revocation, reissue and flags, degree certificates one by one or in a run, policies and templates, the verification log; the legacy transcript queue under `/credentials`; staff and student identity cards; and the public verification doors `GET /api/v1/verify/document` and `/verify/download/{token}`.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/credentials/certificates` | certificates | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `credentials/CredentialsController.java:63` |
| POST | `/api/v1/credentials/certificates` | print | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:69` |
| POST | `/api/v1/credentials/certificates/{id}/collect` | collect | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:75` |
| POST | `/api/v1/credentials/certificates/{id}/hold` | hold | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:81` |
| POST | `/api/v1/credentials/certificates/{id}/reissue` | reissue | academic, dregistrar, registrar | `credentials/CredentialsController.java:87` |
| GET | `/api/v1/credentials/identity-cards` | desk | academic, dregistrar, ict, library, records, registrar, security, super | `credentials/IdentityCardController.java:44` |
| POST | `/api/v1/credentials/identity-cards/students/{studentId}/issue` | issue | library, security, super | `credentials/IdentityCardController.java:69` |
| POST | `/api/v1/credentials/identity-cards/students/{studentId}/lost` | lost | library, security, super | `credentials/IdentityCardController.java:78` |
| POST | `/api/v1/credentials/stationery` | batch | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:94` |
| POST | `/api/v1/credentials/stationery/{id}/return` | giveBack | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:106` |
| POST | `/api/v1/credentials/stationery/{id}/spoil` | spoil | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:100` |
| GET | `/api/v1/credentials/transcript-requests` | transcripts | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `credentials/CredentialsController.java:33` |
| POST | `/api/v1/credentials/transcript-requests` | request | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:39` |
| POST | `/api/v1/credentials/transcript-requests/{id}/mark-paid` | markPaid | academic, dregistrar, registrar | `credentials/CredentialsController.java:45` |
| POST | `/api/v1/credentials/transcript-requests/{id}/produce` | produce | academic, dregistrar, records, registrar | `credentials/CredentialsController.java:51` |
| POST | `/api/v1/credentials/transcript-requests/{id}/release` | release | academic, dregistrar, registrar | `credentials/CredentialsController.java:57` |
| POST | `/api/v1/documents/certificates` | issueCertificate | academic, dregistrar, registrar | `credentials/DocumentsController.java:466` |
| POST | `/api/v1/documents/certificates/bulk` | issueCertificates | academic, dregistrar, registrar | `credentials/DocumentsController.java:477` |
| GET | `/api/v1/documents/dashboard` | dashboard | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:239` |
| POST | `/api/v1/documents/deliveries/{id}` | delivery | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:363` |
| POST | `/api/v1/documents/deliveries/{id}/resend` | resend | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:371` |
| GET | `/api/v1/documents/issued` | issued | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:387` |
| GET | `/api/v1/documents/issued/{id}` | issuedOne | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:408` |
| POST | `/api/v1/documents/issued/{id}/clear-flag` | clearFlag | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:455` |
| GET | `/api/v1/documents/issued/{id}/download` | the office reads a document for its PDF; logged as an office download | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:426` |
| POST | `/api/v1/documents/issued/{id}/reissue` | reissue | academic, dregistrar, registrar | `credentials/DocumentsController.java:446` |
| POST | `/api/v1/documents/issued/{id}/revoke` | revoke | registrar, vc | `credentials/DocumentsController.java:438` |
| PUT | `/api/v1/documents/policies/{kind}` | policy | academic, dregistrar, registrar, super | `credentials/DocumentsController.java:505` |
| GET | `/api/v1/documents/requests` | requests | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:259` |
| GET | `/api/v1/documents/requests/{id}` | request | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:294` |
| POST | `/api/v1/documents/requests/{id}/cancel` | cancel | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:344` |
| POST | `/api/v1/documents/requests/{id}/complete` | complete | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:352` |
| POST | `/api/v1/documents/requests/{id}/generate` | generate | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:317` |
| POST | `/api/v1/documents/requests/{id}/qc` | qc | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:328` |
| POST | `/api/v1/documents/requests/{id}/release` | release | academic, dregistrar, registrar | `credentials/DocumentsController.java:336` |
| POST | `/api/v1/documents/requests/{id}/start` | start | academic, dregistrar, records, registrar | `credentials/DocumentsController.java:310` |
| GET | `/api/v1/documents/templates` | templates | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:524` |
| POST | `/api/v1/documents/templates` | a new template version: documents already issued stay under the version they were issued with | academic, dregistrar, registrar, super | `credentials/DocumentsController.java:535` |
| GET | `/api/v1/documents/verifications` | verifications | academic, admin, audit, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `credentials/DocumentsController.java:493` |
| GET | `/api/v1/me/documents` | mine | student | `credentials/DocumentsController.java:96` |
| POST | `/api/v1/me/documents/requests` | request | student | `credentials/DocumentsController.java:134` |
| GET | `/api/v1/me/documents/requests/{id}` | myRequest | student | `credentials/DocumentsController.java:150` |
| POST | `/api/v1/me/documents/requests/{id}/cancel` | cancelMine | student | `credentials/DocumentsController.java:165` |
| GET | `/api/v1/me/documents/{id}` | the student's own document, statement and all, for the portal's PDF; the download is logged | student | `credentials/DocumentsController.java:174` |
| POST | `/api/v1/me/documents/{id}/link` | myLink | student | `credentials/DocumentsController.java:197` |
| GET | `/api/v1/verify/document` | a document number carries slashes, which a path will not take; the typed form comes as a query, the QR's code as a path | public | `credentials/DocumentsController.java:208` |
| GET | `/api/v1/verify/document/{key}` | verify | public | `credentials/DocumentsController.java:214` |
| GET | `/api/v1/verify/download/{token}` | download | public | `credentials/DocumentsController.java:222` |

### Expenditure & stores (`expenditure`, 33 endpoints)

The Bursary's expenditure side: budget lines, requisitions and approvals, stores and issues, procurement, and research grants (`/api/v1/research/grants`, read and written by the *Research › My Projects* screen). Bursar, Director of Internal Audit, DVC, Vice-Chancellor, Registrar, Director of ICT.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/expenditure/budget` | performance | admin, audit, bursar, deputyaudit, dvc, super, vc | `expenditure/BudgetController.java:41` |
| POST | `/api/v1/expenditure/budget` | set | bursar, super | `expenditure/BudgetController.java:50` |
| GET | `/api/v1/expenditure/requisitions` | list | admin, audit, bursar, deputyaudit, dvc, ict, registrar, super, vc | `expenditure/RequisitionsController.java:45` |
| POST | `/api/v1/expenditure/requisitions` | raise | bursar, dean, hrm, ict, registrar, super | `expenditure/RequisitionsController.java:61` |
| POST | `/api/v1/expenditure/requisitions/{id}/approve` | approve | bursar, super | `expenditure/RequisitionsController.java:77` |
| POST | `/api/v1/expenditure/requisitions/{id}/close` | close | bursar, super | `expenditure/RequisitionsController.java:101` |
| POST | `/api/v1/expenditure/requisitions/{id}/po` | po | bursar, super | `expenditure/RequisitionsController.java:93` |
| POST | `/api/v1/expenditure/requisitions/{id}/reject` | reject | bursar, super | `expenditure/RequisitionsController.java:109` |
| GET | `/api/v1/expenditure/tenders` | list | admin, audit, bursar, deputyaudit, super, vc | `expenditure/TendersController.java:56` |
| POST | `/api/v1/expenditure/tenders` | open | bursar, super | `expenditure/TendersController.java:85` |
| POST | `/api/v1/expenditure/tenders/bids/{bid}/score` | score | bursar, super | `expenditure/TendersController.java:103` |
| GET | `/api/v1/expenditure/tenders/{id}` | bids | admin, audit, bursar, deputyaudit, super, vc | `expenditure/TendersController.java:73` |
| POST | `/api/v1/expenditure/tenders/{id}/award` | award | bursar, super | `expenditure/TendersController.java:113` |
| POST | `/api/v1/expenditure/tenders/{id}/bids` | addBid | bursar, super | `expenditure/TendersController.java:95` |
| POST | `/api/v1/expenditure/tenders/{id}/cancel` | cancel | bursar, super | `expenditure/TendersController.java:121` |
| GET | `/api/v1/expenditure/vouchers` | list | admin, audit, bursar, deputyaudit, super, vc | `expenditure/VouchersController.java:58` |
| POST | `/api/v1/expenditure/vouchers` | raise | bursar, super | `expenditure/VouchersController.java:98` |
| POST | `/api/v1/expenditure/vouchers/queries/{query}/answer` | answer | audit, bursar, deputyaudit, super | `expenditure/VouchersController.java:127` |
| GET | `/api/v1/expenditure/vouchers/{id}` | one | admin, audit, bursar, deputyaudit, super, vc | `expenditure/VouchersController.java:80` |
| POST | `/api/v1/expenditure/vouchers/{id}/advance` | advance | audit, deputyaudit, super | `expenditure/VouchersController.java:109` |
| POST | `/api/v1/expenditure/vouchers/{id}/pay` | pay | bursar, super | `expenditure/VouchersController.java:135` |
| POST | `/api/v1/expenditure/vouchers/{id}/query` | query | audit, deputyaudit, super | `expenditure/VouchersController.java:118` |
| POST | `/api/v1/expenditure/vouchers/{id}/reject` | reject | audit, deputyaudit, super | `expenditure/VouchersController.java:143` |
| GET | `/api/v1/research/grants` | list | admin, audit, bursar, deputyaudit, dvc, super, vc | `expenditure/ProjectsController.java:45` |
| POST | `/api/v1/research/grants` | add | bursar, dvc, super | `expenditure/ProjectsController.java:53` |
| POST | `/api/v1/research/grants/{id}/state` | state | bursar, dvc, super | `expenditure/ProjectsController.java:69` |
| GET | `/api/v1/stores/assets` | assets | admin, audit, bursar, deputyaudit, ict, super, vc | `expenditure/StoresController.java:85` |
| POST | `/api/v1/stores/assets` | addAsset | bursar, super | `expenditure/StoresController.java:92` |
| POST | `/api/v1/stores/assets/{id}/condition` | condition | bursar, super | `expenditure/StoresController.java:116` |
| POST | `/api/v1/stores/assets/{id}/verify` | verify | audit, bursar, deputyaudit, super | `expenditure/StoresController.java:108` |
| GET | `/api/v1/stores/items` | items | admin, audit, bursar, deputyaudit, ict, super, vc | `expenditure/StoresController.java:51` |
| POST | `/api/v1/stores/items` | addItem | bursar, super | `expenditure/StoresController.java:58` |
| POST | `/api/v1/stores/items/{id}/adjust` | adjust | bursar, super | `expenditure/StoresController.java:74` |

### External examiners (`examiners`, 46 endpoints)

External examiners: the appointment and invitation by token, activation of the account, assignments with deadlines, the examiner's own desk (scripts, uploads, assessments, submission and lock), the internal desk's review, the moderation feed (no screen, §4), and the daily reminders (§1.14). Invitation and activation are public; the examiner acts as `extexaminer`.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| POST | `/api/v1/examiners` | a new examiner: a person row without a staff number, and the record; invited at once when asked | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:223` |
| POST | `/api/v1/examiners/activate` | the account made live: the password set, the office granted, the examiner active; the desk told | public | `examiners/ExaminersController.java:1083` |
| GET | `/api/v1/examiners/appointments` | appointments | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:421` |
| POST | `/api/v1/examiners/appointments/{id}/end` | endAppointment | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:411` |
| POST | `/api/v1/examiners/assessments/{id}/lock` | lock | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:810` |
| POST | `/api/v1/examiners/assessments/{id}/reopen` | reopen | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:821` |
| GET | `/api/v1/examiners/assignments` | assignments | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:703` |
| POST | `/api/v1/examiners/assignments` | assign | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:665` |
| GET | `/api/v1/examiners/assignments/{id}` | the assignment with its assessment in full: the desk reads every score and comment | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:721` |
| POST | `/api/v1/examiners/assignments/{id}/deadline` | deadline | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:778` |
| POST | `/api/v1/examiners/assignments/{id}/reassign` | reassign | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:754` |
| POST | `/api/v1/examiners/assignments/{id}/withdraw` | withdraw | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:793` |
| PUT | `/api/v1/examiners/criteria/{id}` | editCriterion | academic, admin, dregistrar, pgschool, super | `examiners/ExaminersController.java:634` |
| GET | `/api/v1/examiners/dashboard` | dashboard | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:172` |
| GET | `/api/v1/examiners/invitation/{token}` | who the link invites, before anything is typed | public | `examiners/ExaminersController.java:1065` |
| GET | `/api/v1/examiners/list` | examiners | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:204` |
| GET | `/api/v1/examiners/me` | myWorkspace | extexaminer | `examiners/ExaminersController.java:900` |
| PUT | `/api/v1/examiners/me/profile` | profile | extexaminer | `examiners/ExaminersController.java:940` |
| GET | `/api/v1/examiners/me/projects` | myProjects | extexaminer | `examiners/ExaminersController.java:955` |
| GET | `/api/v1/examiners/me/projects/{id}` | the project opened: its details, the documents released, the examiner's own assessment; the first opening is recorded | extexaminer | `examiners/ExaminersController.java:965` |
| PUT | `/api/v1/examiners/me/projects/{id}/assessment` | the draft saved: the scores each checked against their maximum, the comments, the recommendation; the total computed | extexaminer | `examiners/ExaminersController.java:1022` |
| POST | `/api/v1/examiners/me/projects/{id}/assessment/start` | start | extexaminer | `examiners/ExaminersController.java:995` |
| POST | `/api/v1/examiners/me/projects/{id}/assessment/submit` | submit | extexaminer | `examiners/ExaminersController.java:1049` |
| GET | `/api/v1/examiners/me/projects/{id}/documents/{doc}/content` | myDocument | extexaminer | `examiners/ExaminersController.java:986` |
| GET | `/api/v1/examiners/moderation` | what moderation reads: every submitted or locked external assessment in a department for a session, beside the internal course result where one is recorded | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:881` |
| GET | `/api/v1/examiners/projects` | projects | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:451` |
| POST | `/api/v1/examiners/projects` | newProject | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:495` |
| GET | `/api/v1/examiners/projects/{id}` | project | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:515` |
| PUT | `/api/v1/examiners/projects/{id}` | editProject | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:527` |
| POST | `/api/v1/examiners/projects/{id}/documents` | releaseDocument | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:540` |
| PUT | `/api/v1/examiners/projects/{id}/documents/{doc}` | toggleDocument | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:559` |
| GET | `/api/v1/examiners/projects/{id}/documents/{doc}/content` | deskDocument | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:570` |
| GET | `/api/v1/examiners/reports` | reports | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:834` |
| GET | `/api/v1/examiners/rubrics` | rubrics | academic, admin, dean, dregistrar, exams, extexaminer, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:585` |
| POST | `/api/v1/examiners/rubrics` | newRubric | academic, admin, dregistrar, pgschool, super | `examiners/ExaminersController.java:599` |
| PUT | `/api/v1/examiners/rubrics/{id}` | editRubric | academic, admin, dregistrar, pgschool, super | `examiners/ExaminersController.java:610` |
| POST | `/api/v1/examiners/rubrics/{id}/criteria` | newCriterion | academic, admin, dregistrar, pgschool, super | `examiners/ExaminersController.java:623` |
| GET | `/api/v1/examiners/students` | the students a project can be registered for: finalists, and postgraduates with a research record, within reach | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:464` |
| GET | `/api/v1/examiners/supervisors` | internal staff who may supervise: the lecturers, for the supervisor picker | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:479` |
| GET | `/api/v1/examiners/{id}` | examiner | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:248` |
| PUT | `/api/v1/examiners/{id}` | edit | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:266` |
| POST | `/api/v1/examiners/{id}/appointments` | appoint | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:390` |
| POST | `/api/v1/examiners/{id}/files` | examinerFile | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:360` |
| GET | `/api/v1/examiners/{id}/files/{file}/content` | examinerFileContent | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:375` |
| POST | `/api/v1/examiners/{id}/invite` | the invitation: a token kept as a hash, a fortnight's life, spent once; the email carries the link | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:288` |
| POST | `/api/v1/examiners/{id}/status` | active, suspended or inactive; the office grant follows, so a suspended examiner cannot act | academic, admin, dean, dregistrar, exams, hod, pgschool, pgsecretary, registrar, super | `examiners/ExaminersController.java:325` |

### Finance & fees (`finance`, 43 endpoints)

Fees and the Bursary: fee schedules and rules per session, programme and level, students' fee references and receipts, confirmation against the bank's record, legacy fees carried over from the old portal, the general ledger and chart of accounts, and the Bursary's reports. Bursar, the audit directorate and ICT act; the Registry and the Vice-Chancellor's office read.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/finance/accounting/balance-sheet` | balanceSheet | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:132` |
| GET | `/api/v1/finance/accounting/chart` | chart | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:61` |
| GET | `/api/v1/finance/accounting/income-expenditure` | incomeExpenditure | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:122` |
| GET | `/api/v1/finance/accounting/journals` | the journal book: recent journals with their lines nested | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:142` |
| POST | `/api/v1/finance/accounting/journals` | a hand-entered balanced journal — opening balances, adjustments, corrections | bursar, super | `finance/AccountingController.java:174` |
| POST | `/api/v1/finance/accounting/journals/{id}/reverse` | reverse | bursar, super | `finance/AccountingController.java:219` |
| GET | `/api/v1/finance/accounting/ledger` | ledger | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:107` |
| GET | `/api/v1/finance/accounting/overview` | the desk at a glance: cash on the books, income/expenditure this year, and what is waiting to be posted | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:70` |
| POST | `/api/v1/finance/accounting/sync` | sweep every confirmed payment, paid refund and paid voucher not yet on the books into balanced journals | bursar, super | `finance/AccountingController.java:166` |
| GET | `/api/v1/finance/accounting/trial-balance` | trialBalance | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `finance/AccountingController.java:96` |
| GET | `/api/v1/finance/bank-credits` | bankCredits | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:427` |
| POST | `/api/v1/finance/bank-credits` | recordCredit | bursar, super | `finance/FinanceController.java:445` |
| POST | `/api/v1/finance/bank-credits/{id}/approve` | approve | bursar, super | `finance/FinanceController.java:462` |
| POST | `/api/v1/finance/bank-credits/{id}/propose` | propose | bursar, super | `finance/FinanceController.java:454` |
| POST | `/api/v1/finance/bank-credits/{id}/reject` | reject | bursar, super | `finance/FinanceController.java:470` |
| GET | `/api/v1/finance/bursary` | bursary | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:310` |
| POST | `/api/v1/finance/clearance-scheme` | scheme | bursar, super | `finance/FinanceController.java:260` |
| GET | `/api/v1/finance/fee-groups` | the fee groups a charge can be scoped to — data, not code, so the set can grow | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:144` |
| GET | `/api/v1/finance/fee-items` | the payment categories a charge can be named from — data, so the set can grow | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:152` |
| GET | `/api/v1/finance/ledger` | ledger | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:335` |
| POST | `/api/v1/finance/legacy-fees` | old students' school-fees history from the old portal — each row settles a past session (or semester) by amount paid, or in full against the fee schedule when the amount is left blank. | bursar, super | `finance/FinanceController.java:102` |
| GET | `/api/v1/finance/payments` | A well-defined payments query for the Bursary: confirmed student payments, newest first, sliced by session, faculty, department, programme, level, payment category and channel. Returns the page, the full-match count and  | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:348` |
| POST | `/api/v1/finance/payments/import` | bulk-load past students' confirmed payment (school-fees) history from the old portal (V120) | admin, bursar, ict, super | `finance/FinanceController.java:67` |
| GET | `/api/v1/finance/programmes` | every programme, for the fee-setup programme select | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:160` |
| GET | `/api/v1/finance/reconciliation` | reconciliation | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:406` |
| POST | `/api/v1/finance/reconciliation/{reference}/check` | reconcile | audit, bursar, deputyaudit, super | `finance/FinanceController.java:416` |
| GET | `/api/v1/finance/references` | references | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:271` |
| POST | `/api/v1/finance/references/{reference}/confirm` | confirm | bursar, super | `finance/FinanceController.java:285` |
| GET | `/api/v1/finance/refunds` | list | admin, audit, bursar, super | `finance/RefundsController.java:48` |
| POST | `/api/v1/finance/refunds` | propose | bursar, super | `finance/RefundsController.java:92` |
| GET | `/api/v1/finance/refunds/transaction` | look a transaction up by its reference, to raise a refund against it — payer, number, amount, purpose | admin, audit, bursar, super | `finance/RefundsController.java:69` |
| POST | `/api/v1/finance/refunds/{id}/approve` | approve | bursar, super | `finance/RefundsController.java:104` |
| POST | `/api/v1/finance/refunds/{id}/pay` | pay | bursar, super | `finance/RefundsController.java:120` |
| POST | `/api/v1/finance/refunds/{id}/reject` | reject | bursar, super | `finance/RefundsController.java:112` |
| GET | `/api/v1/finance/sessions/{session}/{year}/fee-structure` | feeStructure | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:93` |
| POST | `/api/v1/finance/sessions/{session}/{year}/fee-structure` | upload the approved fees structure for a session — one row per faculty/level/semester/indigeneship cell; it replaces the session's structure. | bursar, super | `finance/FinanceController.java:81` |
| GET | `/api/v1/finance/sessions/{session}/{year}/schedule` | schedule | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:116` |
| POST | `/api/v1/finance/sessions/{session}/{year}/schedule` | addItem | bursar, super | `finance/FinanceController.java:167` |
| POST | `/api/v1/finance/sessions/{session}/{year}/schedule/clear` | clear the whole schedule for a session — ends every standing line, so the Bursar can upload a clean structure (the same soft-end an upload does before it re-inserts). Charges ignore ended lines at once. | bursar, super | `finance/FinanceController.java:200` |
| PUT | `/api/v1/finance/sessions/{session}/{year}/schedule/{id}` | edit a standing fee line in place — its amount and the filters it carries | bursar, super | `finance/FinanceController.java:210` |
| POST | `/api/v1/finance/sessions/{session}/{year}/schedule/{id}/end` | endItem | bursar, super | `finance/FinanceController.java:189` |
| GET | `/api/v1/finance/transfer-fee` | transferFee | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `finance/FinanceController.java:238` |
| PUT | `/api/v1/finance/transfer-fee` | setTransferFee | bursar, super | `finance/FinanceController.java:250` |

### Governance (`governance`, 8 endpoints)

The governance registers: the processing register with DPIA marks, data-subject requests and their advancement, disaster-recovery drills, and the security posture summary. Registrar, Deputy Registrar (Academic Affairs), Director of ICT and Super Administrator record; audit and management read.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/governance/dr` | dr | admin, audit, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `governance/GovernanceController.java:102` |
| POST | `/api/v1/governance/dr` | recordDrill | ict, super | `governance/GovernanceController.java:110` |
| GET | `/api/v1/governance/dsr` | dsrList | admin, audit, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `governance/GovernanceController.java:68` |
| POST | `/api/v1/governance/dsr` | dsrRecord | dregistrar, ict, registrar, super | `governance/GovernanceController.java:76` |
| POST | `/api/v1/governance/dsr/{id}/advance` | dsrAdvance | dregistrar, ict, registrar, super | `governance/GovernanceController.java:91` |
| GET | `/api/v1/governance/register` | register | admin, audit, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `governance/GovernanceController.java:50` |
| POST | `/api/v1/governance/register/{id}/dpia` | dpia | dregistrar, ict, registrar, super | `governance/GovernanceController.java:58` |
| GET | `/api/v1/governance/security` | security | admin, audit, deputyaudit, dvc, ict, registrar, security, super, vc | `governance/GovernanceController.java:128` |

### Graduation (`graduation`, 3 endpoints)

Graduation for a session: the graduand view, the degree audit (published results and CGPA) and Senate approval. Academic Office, the Registry, Exams and Records.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/graduation/sessions/{s}/{y}` | view | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `graduation/GraduationController.java:32` |
| POST | `/api/v1/graduation/sessions/{s}/{y}/approve` | approve | academic, dregistrar, registrar | `graduation/GraduationController.java:46` |
| POST | `/api/v1/graduation/sessions/{s}/{y}/audit` | audit | academic, dregistrar, records, registrar | `graduation/GraduationController.java:40` |

### HOD's desk (`hod`, 3 endpoints)

The Head of Department's desk: the dashboard, the department's students cleared for registration or still owing (a download), and the department's academic staff by name and rank. Scoped to the acting HOD's own department.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/hod/dashboard` | dashboard | hod | `hod/HodController.java:34` |
| GET | `/api/v1/hod/fees` | the department's students cleared for registration this session, or still owing — the lists behind the dashboard's figures, for the Head of Department to download (matric, name, programme, level, charged, paid, balance) | hod | `hod/HodController.java:171` |
| GET | `/api/v1/hod/staff` | the department's academic staff, scoped to the acting HOD's own department — names and ranks only, no payroll. For the HOD to see who is on the establishment of their department. | hod | `hod/HodController.java:193` |

### Health centre (`health`, 9 endpoints)

The health centre: the student's own record, appointments, consent and restriction; the desk's visits (arrive, open, conclude). Support Services and Super Administrator act for the desk.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/health/desk` | desk | services, super | `health/HealthController.java:87` |
| POST | `/api/v1/health/visits` | arrive | services, super | `health/HealthController.java:93` |
| POST | `/api/v1/health/visits/{id}/conclude` | conclude | services, super | `health/HealthController.java:105` |
| POST | `/api/v1/health/visits/{id}/open` | open | services, super | `health/HealthController.java:99` |
| GET | `/api/v1/me/health` | mine | student | `health/HealthController.java:55` |
| POST | `/api/v1/me/health/appointments` | book | student | `health/HealthController.java:61` |
| POST | `/api/v1/me/health/appointments/{id}/cancel` | cancel | student | `health/HealthController.java:67` |
| PUT | `/api/v1/me/health/consent` | consent | student | `health/HealthController.java:73` |
| POST | `/api/v1/me/health/restrict` | restrict | student | `health/HealthController.java:79` |

### Hostel (`hostel`, 56 endpoints)

The hostel lifecycle (V261 on V030): halls, rooms and beds as rows, the application window and rules per session, applications with paging, review, hold → accept → check-in → transfer → inspection → charges → clearance, occupancy, the waiting list, `lapse-all`, and the student's own `/me/hostel`. Deputy Registrar (Housing, Welfare, Passages), Support Services, the Registrar and administrators act; the hourly clock lapses expired holds.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/hostel/allocations/{id}` | allocation | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:617` |
| POST | `/api/v1/hostel/allocations/{id}/cancel` | cancel | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:672` |
| POST | `/api/v1/hostel/allocations/{id}/charge` | charge | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:695` |
| POST | `/api/v1/hostel/allocations/{id}/checkin` | checkin | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:652` |
| POST | `/api/v1/hostel/allocations/{id}/clearance` | startClearance | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:711` |
| POST | `/api/v1/hostel/allocations/{id}/inspect` | inspect | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:683` |
| POST | `/api/v1/hostel/allocations/{id}/transfer` | transfer | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:664` |
| PUT | `/api/v1/hostel/assets` | asset | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:373` |
| PUT | `/api/v1/hostel/blocks` | block | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:301` |
| POST | `/api/v1/hostel/charges/{id}/waive` | waive | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:703` |
| POST | `/api/v1/hostel/clearance-items/{id}` | item | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:722` |
| POST | `/api/v1/hostel/clearances/{id}/complete` | complete | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:733` |
| POST | `/api/v1/hostel/clearances/{id}/reopen` | reopen | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:741` |
| POST | `/api/v1/hostel/close` | a hall, block, room or bed closed or reopened; the occupants it affects are named | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:392` |
| PUT | `/api/v1/hostel/halls` | hall | admin, housing, registrar, services, super | `hostel/HostelController.java:100` |
| PUT | `/api/v1/hostel/halls-full` | hall | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:282` |
| GET | `/api/v1/hostel/inventory` | inventory | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:231` |
| POST | `/api/v1/hostel/lapse-all` | lapseAll | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:844` |
| GET | `/api/v1/hostel/maintenance` | maintenanceList | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:817` |
| POST | `/api/v1/hostel/maintenance/{id}` | decide | admin, housing, registrar, services, super | `hostel/HostelController.java:124` |
| POST | `/api/v1/hostel/maintenance/{id}/update` | maintenance | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:796` |
| PUT | `/api/v1/hostel/rooms` | room | admin, housing, registrar, services, super | `hostel/HostelController.java:106` |
| PUT | `/api/v1/hostel/rooms-full` | room | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:317` |
| POST | `/api/v1/hostel/rooms/generate` | rooms generated in a run: A-101 … A-120, each with its beds | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:341` |
| GET | `/api/v1/hostel/rooms/{id}` | room | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:258` |
| PUT | `/api/v1/hostel/rooms/{id}/facilities` | facilities | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:357` |
| GET | `/api/v1/hostel/sessions/{s}/{y}` | desk | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelController.java:88` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/applications` | applications | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:480` |
| POST | `/api/v1/hostel/sessions/{s}/{y}/applications/review-bulk` | reviewBulk | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:532` |
| POST | `/api/v1/hostel/sessions/{s}/{y}/applications/{id}/allocate` | allocate | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:547` |
| POST | `/api/v1/hostel/sessions/{s}/{y}/applications/{id}/review` | review | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:521` |
| POST | `/api/v1/hostel/sessions/{s}/{y}/applications/{id}/withdraw` | withdrawByDesk | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:555` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/clearances` | clearances | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:749` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/dashboard` | dashboard | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:457` |
| POST | `/api/v1/hostel/sessions/{s}/{y}/draw` | draw | admin, housing, registrar, services, super | `hostel/HostelController.java:112` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/free-beds` | freeBeds | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:563` |
| POST | `/api/v1/hostel/sessions/{s}/{y}/lapse` | lapse | admin, housing, registrar, services, super | `hostel/HostelController.java:118` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/occupancy` | occupancy | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:578` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/preview` | preview | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:572` |
| PUT | `/api/v1/hostel/sessions/{s}/{y}/setting` | setting | admin, housing, registrar, services, super | `hostel/HostelController.java:94` |
| GET | `/api/v1/hostel/sessions/{s}/{y}/transfers` | transfers | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:768` |
| PUT | `/api/v1/hostel/sessions/{s}/{y}/window` | window | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:415` |
| GET | `/api/v1/hostel/students/{id}/history` | studentHistory | academic, admin, audit, bursar, dregistrar, dvc, housing, ict, registrar, services, super, vc | `hostel/HostelLifecycleController.java:829` |
| POST | `/api/v1/hostel/transfers/{id}` | decideTransfer | admin, housing, registrar, services, super | `hostel/HostelLifecycleController.java:783` |
| GET | `/api/v1/me/hostel` | mine | student | `hostel/HostelController.java:62` |
| POST | `/api/v1/me/hostel/accept` | accept | student | `hostel/HostelLifecycleController.java:161` |
| POST | `/api/v1/me/hostel/apply` | apply | student | `hostel/HostelController.java:68` |
| POST | `/api/v1/me/hostel/apply-full` | apply | student | `hostel/HostelLifecycleController.java:118` |
| POST | `/api/v1/me/hostel/checkout` | requestCheckout | student | `hostel/HostelLifecycleController.java:197` |
| POST | `/api/v1/me/hostel/decline` | decline | student | `hostel/HostelLifecycleController.java:171` |
| POST | `/api/v1/me/hostel/fee-reference` | feeReference | student | `hostel/HostelController.java:74` |
| GET | `/api/v1/me/hostel/full` | mine | student | `hostel/HostelLifecycleController.java:72` |
| POST | `/api/v1/me/hostel/maintenance` | raise | student | `hostel/HostelController.java:80` |
| POST | `/api/v1/me/hostel/maintenance-full` | raise | student | `hostel/HostelLifecycleController.java:209` |
| POST | `/api/v1/me/hostel/transfer` | requestTransfer | student | `hostel/HostelLifecycleController.java:184` |
| POST | `/api/v1/me/hostel/withdraw` | withdraw | student | `hostel/HostelLifecycleController.java:149` |

### Human resources (`hrm`, 33 endpoints)

Human resources: the staff register and profiles, grades and steps, appointments and movements, leave types and requests (`/me/leave`), payslips (`/me/payslips`), recruitment, and the imports of academic and non-academic staff. Director of Human Resource Management, the Registry and management; every employee reads their own `hr/staff/me`.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| POST | `/api/v1/hr/applicants/{id}/assess` | assess | hrm, registrar, super | `hrm/RecruitmentController.java:117` |
| GET | `/api/v1/hr/appraisal` | view | admin, audit, dean, dregistrar, dvc, hod, hrm, registrar, super, vc | `hrm/AppraisalController.java:49` |
| POST | `/api/v1/hr/appraisal` | record | dean, hod, hrm, registrar, super | `hrm/AppraisalController.java:64` |
| GET | `/api/v1/hr/dashboard` | dashboard | hrm, super | `hrm/HrController.java:26` |
| GET | `/api/v1/hr/leave` | list | admin, audit, dean, dregistrar, hod, hrm, registrar, super | `hrm/LeaveController.java:102` |
| POST | `/api/v1/hr/leave/{id}/decide` | decide | admin, audit, dean, dregistrar, hod, hrm, registrar, super | `hrm/LeaveController.java:118` |
| GET | `/api/v1/hr/movements` | list | admin, audit, deputyaudit, dregistrar, dvc, hrm, registrar, super, vc | `hrm/MovementController.java:55` |
| POST | `/api/v1/hr/movements` | raise | hrm, registrar, super | `hrm/MovementController.java:65` |
| POST | `/api/v1/hr/movements/{id}/approve` | approve | dregistrar, dvc, hrm, registrar, super, vc | `hrm/MovementController.java:78` |
| POST | `/api/v1/hr/movements/{id}/decline` | decline | dregistrar, dvc, hrm, registrar, super, vc | `hrm/MovementController.java:86` |
| POST | `/api/v1/hr/movements/{id}/issue` | issue | hrm, registrar, super | `hrm/MovementController.java:94` |
| GET | `/api/v1/hr/staff/me` | the acting person's own record — anyone signed in may read their own, for their identity card | any signed-in user | `hrm/StaffRecordController.java:45` |
| GET | `/api/v1/hr/staff/me/photo` | the acting person's own photograph | any signed-in user | `hrm/StaffRecordController.java:53` |
| GET | `/api/v1/hr/staff/{id}` | one | academic, admin, audit, bursar, dean, deputyaudit, dregistrar, dvc, facultyofficer, hod, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `hrm/StaffRecordController.java:60` |
| GET | `/api/v1/hr/staff/{id}/photo` | the photograph HR holds for the person (JPEG or PNG), else 404 | academic, admin, audit, bursar, dean, deputyaudit, dregistrar, dvc, facultyofficer, hod, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `hrm/StaffRecordController.java:131` |
| GET | `/api/v1/hr/vacancies` | vacancies | admin, audit, dregistrar, dvc, hrm, registrar, super, vc | `hrm/RecruitmentController.java:49` |
| POST | `/api/v1/hr/vacancies` | open | hrm, registrar, super | `hrm/RecruitmentController.java:64` |
| GET | `/api/v1/hr/vacancies/{id}/applicants` | applicants | admin, audit, dregistrar, dvc, hrm, registrar, super, vc | `hrm/RecruitmentController.java:88` |
| POST | `/api/v1/hr/vacancies/{id}/applicants` | record | hrm, registrar, super | `hrm/RecruitmentController.java:100` |
| POST | `/api/v1/hr/vacancies/{id}/state` | setState | hrm, registrar, super | `hrm/RecruitmentController.java:80` |
| GET | `/api/v1/me/leave` | mine | any signed-in user | `hrm/LeaveController.java:64` |
| POST | `/api/v1/me/leave` | request | any signed-in user | `hrm/LeaveController.java:76` |
| POST | `/api/v1/me/leave/{id}/cancel` | cancel | any signed-in user | `hrm/LeaveController.java:87` |
| GET | `/api/v1/me/payslips` | mine | any signed-in user | `hrm/PayrollController.java:162` |
| GET | `/api/v1/payroll/grades` | grades | admin, audit, bursar, deputyaudit, dvc, hrm, super, vc | `hrm/PayrollController.java:67` |
| GET | `/api/v1/payroll/runs` | runs | admin, audit, bursar, deputyaudit, dvc, hrm, super, vc | `hrm/PayrollController.java:76` |
| POST | `/api/v1/payroll/runs` | build | hrm, super | `hrm/PayrollController.java:118` |
| GET | `/api/v1/payroll/runs/{id}` | run | admin, audit, bursar, deputyaudit, dvc, hrm, super, vc | `hrm/PayrollController.java:93` |
| POST | `/api/v1/payroll/runs/{id}/approve` | approve | hrm, super | `hrm/PayrollController.java:127` |
| POST | `/api/v1/payroll/runs/{id}/cancel` | cancel | hrm, super | `hrm/PayrollController.java:143` |
| POST | `/api/v1/payroll/runs/{id}/pay` | pay | hrm, super | `hrm/PayrollController.java:135` |
| GET | `/api/v1/payroll/staff` | establishment | admin, audit, bursar, deputyaudit, dvc, hrm, super, vc | `hrm/PayrollController.java:52` |
| GET | `/api/v1/payroll/variance` | variance | admin, audit, bursar, deputyaudit, dvc, hrm, super, vc | `hrm/PayrollController.java:151` |

### ICT help desk (`helpdesk`, 30 endpoints)

The ICT help desk (V251/V252): the requester's tickets, comments, attachments, confirm/reopen/close; the agents' queue with paging, assignment, status, priority, escalation, resolution, internal notes; categories with declared fields, SLA settings and auto-close; statistics and activity; and the public `track` door (12 per 15 minutes). Requesters are any signed-in staff or student; agents are ICT Support Agents and the Directorate.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/helpdesk/activity` | what happened on the desk lately, across every ticket: the last acts, newest first | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:438` |
| GET | `/api/v1/helpdesk/admin/categories` | allCategories | admin, ict, super | `helpdesk/HelpdeskController.java:589` |
| POST | `/api/v1/helpdesk/admin/categories` | newCategory | admin, ict, super | `helpdesk/HelpdeskController.java:604` |
| PUT | `/api/v1/helpdesk/admin/categories/{id}` | editCategory | admin, ict, super | `helpdesk/HelpdeskController.java:621` |
| GET | `/api/v1/helpdesk/admin/settings` | settings | admin, ict, super | `helpdesk/HelpdeskController.java:668` |
| PUT | `/api/v1/helpdesk/admin/settings` | saveSettings | admin, ict, super | `helpdesk/HelpdeskController.java:683` |
| GET | `/api/v1/helpdesk/agents` | the people the desk can give a ticket to: agents and the Director, with their open load | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:451` |
| GET | `/api/v1/helpdesk/categories` | the categories open for a new ticket, each with the fields it asks for | any signed-in user | `helpdesk/HelpdeskController.java:156` |
| GET | `/api/v1/helpdesk/my/profile` | profile | any signed-in user | `helpdesk/HelpdeskController.java:141` |
| GET | `/api/v1/helpdesk/my/tickets` | mine | any signed-in user | `helpdesk/HelpdeskController.java:164` |
| POST | `/api/v1/helpdesk/my/tickets` | submit | any signed-in user | `helpdesk/HelpdeskController.java:177` |
| GET | `/api/v1/helpdesk/my/tickets/{id}` | myTicket | any signed-in user | `helpdesk/HelpdeskController.java:200` |
| POST | `/api/v1/helpdesk/my/tickets/{id}/attachments` | myAttach | any signed-in user | `helpdesk/HelpdeskController.java:227` |
| GET | `/api/v1/helpdesk/my/tickets/{id}/attachments/{att}/content` | myContent | any signed-in user | `helpdesk/HelpdeskController.java:236` |
| POST | `/api/v1/helpdesk/my/tickets/{id}/close` | the requester no longer needs it: any open status → CLOSED | any signed-in user | `helpdesk/HelpdeskController.java:279` |
| POST | `/api/v1/helpdesk/my/tickets/{id}/comments` | mySay | any signed-in user | `helpdesk/HelpdeskController.java:212` |
| POST | `/api/v1/helpdesk/my/tickets/{id}/confirm` | the requester is satisfied: RESOLVED → CLOSED | any signed-in user | `helpdesk/HelpdeskController.java:249` |
| POST | `/api/v1/helpdesk/my/tickets/{id}/reopen` | the requester is not satisfied: RESOLVED → REOPENED, on a reason | any signed-in user | `helpdesk/HelpdeskController.java:266` |
| GET | `/api/v1/helpdesk/stats` | the desk's figures and the Director's analytics, from the same filters as the queue | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:369` |
| GET | `/api/v1/helpdesk/tickets` | the queue: searched, filtered, sorted, paged on the server | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:294` |
| GET | `/api/v1/helpdesk/tickets/{id}` | the ticket in full; the first agent to read a submitted ticket opens it (§8), and that is recorded | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:467` |
| POST | `/api/v1/helpdesk/tickets/{id}/assign` | assign | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:480` |
| POST | `/api/v1/helpdesk/tickets/{id}/attachments` | deskAttach | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:571` |
| GET | `/api/v1/helpdesk/tickets/{id}/attachments/{att}/content` | deskContent | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:579` |
| POST | `/api/v1/helpdesk/tickets/{id}/comments` | an internal note the requester never sees, or an update they do | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:559` |
| POST | `/api/v1/helpdesk/tickets/{id}/escalate` | escalate | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:532` |
| POST | `/api/v1/helpdesk/tickets/{id}/priority` | priority | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:518` |
| POST | `/api/v1/helpdesk/tickets/{id}/resolve` | resolve | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:545` |
| POST | `/api/v1/helpdesk/tickets/{id}/status` | start work, close on a reason, reopen on a reason — the desk's transitions | admin, ict, ictagent, super | `helpdesk/HelpdeskController.java:495` |
| POST | `/api/v1/helpdesk/track` | a ticket number and the email it was raised with; nothing internal, no attachments, no names at all | public | `helpdesk/HelpdeskController.java:722` |

### Identity & accounts (`iam`, 17 endpoints)

Identity and accounts: `me` (§2.3), the office register, persons and their office assignments under an instrument, staff contact details and credentials set by the Registry, the lecturer import, and the student account desk. Registrar, Deputy Registrar (Academic Affairs), HRM, Director of ICT, System Administrator, Super Administrator (grants also by the Vice-Chancellor).

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/iam/lecturers` | the teaching staff on record — every person holding the lecturer office, with their home department, rank and whether a sign-in has been issued. Read after an upload to confirm it. | admin, audit, dregistrar, hrm, ict, registrar, super | `iam/AccountsController.java:166` |
| POST | `/api/v1/iam/lecturers/delete` | remove selected lecturers (person + sign-in + lecturer grants + establishment) when they carry no teaching history; one that already teaches an offering is kept. See iam.delete_lecturers (V138). | admin, dregistrar, ict, registrar, super | `iam/AccountsController.java:138` |
| POST | `/api/v1/iam/lecturers/import` | Bulk-onboard lecturers: each row becomes a person, a sign-in (username/password = staff number, must change) and the lecturer office scoped to the department code — the same three things Users & roles makes one at a time | admin, dregistrar, ict, registrar, super | `iam/AccountsController.java:69` |
| PUT | `/api/v1/iam/lecturers/{id}` | edit one lecturer: names, contact, sex, rank, CONUASS and home department. See iam.update_lecturer (V140). | admin, dregistrar, ict, registrar, super | `iam/AccountsController.java:151` |
| GET | `/api/v1/iam/me` | The current principal: who, acting as what, with which offices available. | any signed-in user | `iam/IamController.java:42` |
| GET | `/api/v1/iam/office-assignments` | every grant, newest first, as the prototype's table shows them | admin, audit, dregistrar, hrm, ict, registrar, super | `iam/AccountsController.java:209` |
| GET | `/api/v1/iam/offices` | offices | any signed-in user | `iam/AccountsController.java:239` |
| GET | `/api/v1/iam/persons` | persons | admin, audit, dregistrar, hrm, ict, registrar, super | `iam/AccountsController.java:194` |
| POST | `/api/v1/iam/persons` | create | admin, dregistrar, hrm, ict, registrar, super | `iam/IamController.java:86` |
| GET | `/api/v1/iam/persons/{id}` | person | admin, dregistrar, hrm, ict, registrar, super | `iam/IamController.java:69` |
| PUT | `/api/v1/iam/persons/{id}/contact` | the Registry sets a staff member's email and phone — where a reset and any notice are sent | admin, dregistrar, hrm, ict, registrar, super | `iam/IamController.java:97` |
| PUT | `/api/v1/iam/persons/{id}/credential` | credential | admin, dregistrar, ict, registrar, super | `iam/AccountsController.java:224` |
| POST | `/api/v1/iam/persons/{id}/office-assignments` | grant | admin, dregistrar, ict, registrar, super, vc | `iam/IamController.java:111` |
| POST | `/api/v1/iam/persons/{id}/office-assignments/{grant}/end` | end | admin, dregistrar, ict, registrar, super, vc | `iam/AccountsController.java:230` |
| GET | `/api/v1/iam/staff` | the non-academic staff on record, with where each is placed | admin, audit, dregistrar, hrm, ict, registrar, super | `iam/AccountsController.java:100` |
| POST | `/api/v1/iam/staff/import` | Bulk-load non-academic staff from the nominal roll (V253): the same sheet as the teaching staff with CONTISS in place of CONUASS and the unit as written. Each row becomes a person and an establishment record placed in it | admin, dregistrar, hrm, ict, registrar, super | `iam/AccountsController.java:91` |
| GET | `/api/v1/iam/units` | the unit register, with how many staff each holds | admin, audit, dregistrar, hrm, ict, registrar, super | `iam/AccountsController.java:123` |

### Learning materials (LMS) (`lms`, 17 endpoints)

Learning materials: a lecturer's courses (`/me/teaching`), materials by week (base64 files or links, published or not), assignments and submissions, and the student's view. Lecturers, Heads of Department, Deans, the Academic Office.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/lms/offerings/{offering}` | desk | academic, dean, hod, lecturer, super | `lms/LmsController.java:102` |
| POST | `/api/v1/lms/offerings/{offering}/assignments` | assignment | academic, dean, hod, lecturer, super | `lms/LmsController.java:133` |
| GET | `/api/v1/lms/offerings/{offering}/assignments/{id}/submissions` | submissions | academic, dean, hod, lecturer, super | `lms/LmsController.java:139` |
| POST | `/api/v1/lms/offerings/{offering}/assignments/{id}/submissions/{submission}/mark` | mark | academic, dean, hod, lecturer, super | `lms/LmsController.java:145` |
| POST | `/api/v1/lms/offerings/{offering}/materials` | material | academic, dean, hod, lecturer, super | `lms/LmsController.java:108` |
| GET | `/api/v1/lms/offerings/{offering}/materials/{id}/content` | materialContent | academic, dean, hod, lecturer, super | `lms/LmsController.java:127` |
| POST | `/api/v1/lms/offerings/{offering}/materials/{id}/end` | end | academic, dean, hod, lecturer, super | `lms/LmsController.java:121` |
| POST | `/api/v1/lms/offerings/{offering}/materials/{id}/publish` | publish | academic, dean, hod, lecturer, super | `lms/LmsController.java:115` |
| POST | `/api/v1/lms/offerings/{offering}/promote` | promote | academic, dean, hod, lecturer, super | `lms/LmsController.java:157` |
| GET | `/api/v1/lms/offerings/{offering}/submissions/{submission}/content` | submissionContent | academic, dean, hod, lecturer, super | `lms/LmsController.java:151` |
| GET | `/api/v1/lms/teaching` | teaching | academic, dean, hod, lecturer, super | `lms/LmsController.java:96` |
| GET | `/api/v1/me/courses` | mine | student | `lms/LmsController.java:64` |
| POST | `/api/v1/me/courses/assignments/{id}/submit` | submit | student | `lms/LmsController.java:88` |
| GET | `/api/v1/me/courses/materials/{id}/content` | read | student | `lms/LmsController.java:76` |
| POST | `/api/v1/me/courses/materials/{id}/read` | noteRead | student | `lms/LmsController.java:82` |
| GET | `/api/v1/me/courses/{offering}` | space | student | `lms/LmsController.java:70` |
| GET | `/api/v1/me/teaching` | teaching | any signed-in user | `lms/MeTeachingController.java:34` |

### Library (`library`, 11 endpoints)

The library desk: items, loans, returns, renewals, fine waivers, settings; and the student's own loans, renewals, reservations and fine references. Librarian, Support Services, administrators.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/library/desk` | desk | academic, admin, audit, bursar, dregistrar, ict, library, registrar, services, super | `library/LibraryController.java:87` |
| PUT | `/api/v1/library/items` | item | admin, library, services, super | `library/LibraryController.java:123` |
| POST | `/api/v1/library/loans` | issue | admin, library, services, super | `library/LibraryController.java:93` |
| POST | `/api/v1/library/loans/{id}/renew` | renewAtDesk | admin, library, services, super | `library/LibraryController.java:105` |
| POST | `/api/v1/library/loans/{id}/waive` | waive | library, super | `library/LibraryController.java:111` |
| POST | `/api/v1/library/returns` | giveBack | admin, library, services, super | `library/LibraryController.java:99` |
| PUT | `/api/v1/library/setting` | setting | library, super | `library/LibraryController.java:117` |
| GET | `/api/v1/me/library` | mine | student | `library/LibraryController.java:61` |
| POST | `/api/v1/me/library/loans/{id}/fine-reference` | fineReference | student | `library/LibraryController.java:73` |
| POST | `/api/v1/me/library/loans/{id}/renew` | renew | student | `library/LibraryController.java:67` |
| POST | `/api/v1/me/library/reservations` | reserve | student | `library/LibraryController.java:79` |

### Matriculation (`matriculation`, 30 endpoints)

Matriculation (V263): the session overview and faculty lists, queries on a name and their withdrawal, a faculty's confirmation, the run (every number or none), matriculating one straggler (§2.4), and the number-format configuration — the rule, the series, each faculty's segment and series, each programme's code with the number it would give next, the preview and the history (§2.5). Academic Office, Registrar, Deputy Registrar (Academic Affairs), Faculty Officers; management reads.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/matriculation/sessions/{s}/{y}/management` | the faculty view (V267): faculties, batches, and with `fac` the KPIs, programme groups, students (`prog`, `status`, `q`) and the open batch | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatriculationManagementController.java` |
| GET | `/api/v1/matriculation/sessions/{s}/{y}/management/overview` | every faculty: eligible, pending, prepared, valid, conflicts, issued, batch state; refused to a faculty office | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatriculationManagementController.java` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/management/faculties/{code}/generate` | propose and reserve numbers for the faculty's eligible students `{ programme? }` — preparation, nothing on the record | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationManagementController.java` |
| GET | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}` | one batch with its rows and corrections | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatriculationManagementController.java` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}/validate` | re-validate every row | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationManagementController.java` |
| PUT | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}/rows/{rowId}` | correct a proposed number `{ matricNo, reason }` — validated, recorded | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationManagementController.java` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}/rows/{rowId}/drop` | take a student off the batch `{ reason }` | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationManagementController.java` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}/ready` | mark the batch ready (zero conflicts) | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationManagementController.java` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}/issue` | the official act `{ confirm: true }`: one transaction — numbers, series, status, sign-in username, histories, notices; returns the result and the verification | academic, dregistrar, registrar | `matriculation/MatriculationManagementController.java` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/management/batches/{id}/cancel` | cancel a prepared batch `{ reason }`; never an issued one | academic, dregistrar, registrar | `matriculation/MatriculationManagementController.java` |
| GET | `/api/v1/matriculation/sessions/{s}/{y}/management/issued` | issued numbers (`fac`, `prog`, `q`, `batch`, `from`, `to`) with the previous username | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatriculationManagementController.java` |
| GET | `/api/v1/matriculation/sessions/{s}/{y}/management/pending` | admitted students not yet eligible, with the reason (`fac`) | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatriculationManagementController.java` |
| GET | `/api/v1/matriculation/students/{id}/record` | one student's matriculation before and after: number, date, batch, username and its history, proposals | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatriculationManagementController.java` |
| PUT | `/api/v1/matriculation/config/duties` | the separation of duties `{ separateDuties }` | academic, dregistrar, registrar | `matriculation/MatriculationManagementController.java` |
| GET | `/api/v1/matriculation/config` | config | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatricFormatController.java:55` |
| PUT | `/api/v1/matriculation/config/faculties/{code}` | faculty | academic, dregistrar, registrar, super | `matriculation/MatricFormatController.java:116` |
| PUT | `/api/v1/matriculation/config/format` | format | academic, dregistrar, registrar, super | `matriculation/MatricFormatController.java:78` |
| GET | `/api/v1/matriculation/config/history` | history | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatricFormatController.java:148` |
| GET | `/api/v1/matriculation/config/preview/{studentId}` | preview | academic, admin, dean, dregistrar, dvc, facultyofficer, ict, records, registrar, super, vc | `matriculation/MatricFormatController.java:142` |
| PUT | `/api/v1/matriculation/config/programmes/{code}` | a programme's code is never invented here: blank means none, and "carries a code" with none is refused | academic, dregistrar, registrar, super | `matriculation/MatricFormatController.java:129` |
| PUT | `/api/v1/matriculation/config/series/{code}` | a series' last number is moved only forward: a number issued is never reissued | academic, dregistrar, registrar, super | `matriculation/MatricFormatController.java:96` |
| GET | `/api/v1/matriculation/sessions/{s}/{y}` | overview | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, ict, records, registrar, super, vc | `matriculation/MatriculationController.java:37` |
| GET | `/api/v1/matriculation/sessions/{s}/{y}/faculties/{code}` | faculty | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, ict, records, registrar, super, vc | `matriculation/MatriculationController.java:61` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/faculties/{code}/confirm` | confirm | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationController.java:103` |
| PUT | `/api/v1/matriculation/sessions/{s}/{y}/faculties/{code}/queries/{studentId}` | query | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationController.java:72` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/faculties/{code}/queries/{studentId}/withdraw` | withdraw | academic, dregistrar, facultyofficer, registrar | `matriculation/MatriculationController.java:91` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/run` | One transaction, one sequence: every number, or none. | academic, dregistrar, registrar | `matriculation/MatriculationController.java:121` |
| POST | `/api/v1/matriculation/sessions/{s}/{y}/students/{studentId}/matriculate` | Matriculate one student who has since paid the fees and registered — a straggler the batch run missed. The database refuses, with the reason, anyone not admitted, not registered, or still owing; nothing is typed, the num | academic, dregistrar, registrar | `matriculation/MatriculationController.java:134` |

### Payment gateways (`payments`, 17 endpoints)

The payment gateways: checkout (§2.8), which gateways are wired, verification against the gateway, the three webhooks and the Quickteller start page (§1.13), the Bursary's view of events and hanging attempts, the sweep, test checkout, keys set encrypted and never read back, and the PayDirect billers and collections import.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/payments/bursary` | bursary | admin, audit, bursar, deputyaudit, dvc, ict, registrar, super, vc | `payments/PaymentsController.java:116` |
| POST | `/api/v1/payments/checkout` | checkout | applicant, student | `payments/PaymentsController.java:47` |
| POST | `/api/v1/payments/events/{id}/resolve` | resolve | admin, bursar, ict, super | `payments/PaymentsController.java:135` |
| GET | `/api/v1/payments/gateway-config` | gatewayConfig | admin, audit, bursar, deputyaudit, dvc, ict, registrar, super, vc | `payments/PaymentsController.java:146` |
| GET | `/api/v1/payments/gateways` | which gateways are wired: the applicant's button says so | any signed-in user | `payments/PaymentsController.java:41` |
| POST | `/api/v1/payments/gateways/{gateway}/clear-key` | clearKey | admin, ict, super | `payments/PaymentsController.java:158` |
| PUT | `/api/v1/payments/gateways/{gateway}/key` | setKey | admin, ict, super | `payments/PaymentsController.java:152` |
| GET | `/api/v1/payments/paydirect` | the billers, and the imported collections — the Bursary's PayDirect desk | admin, audit, bursar, deputyaudit, dvc, ict, registrar, super, vc | `payments/PaymentsController.java:173` |
| PUT | `/api/v1/payments/paydirect/billers/{scope}` | setBiller | admin, bursar, ict, super | `payments/PaymentsController.java:186` |
| POST | `/api/v1/payments/paydirect/import` | import the Quickteller/PayDirect collections report: each PRN matched to its reference and confirmed | admin, bursar, ict, super | `payments/PaymentsController.java:180` |
| GET | `/api/v1/payments/quickteller/start` | The Quickteller hosted page is reached by a form POST, not a link, so the checkout hands the browser this endpoint; it renders the self-submitting form that posts the payment to Interswitch. It reveals only what a payer  | public | `payments/PaymentsController.java:89` |
| POST | `/api/v1/payments/sweep` | sweep | admin, bursar, ict, super | `payments/PaymentsController.java:128` |
| POST | `/api/v1/payments/test-checkout` | testCheckout | admin, bursar, ict, super | `payments/PaymentsController.java:122` |
| POST | `/api/v1/payments/verify` | the gateway is asked what the reference settled for: the student's own, or any for an office | any signed-in user | `payments/PaymentsController.java:109` |
| POST | `/api/v1/payments/webhook/flutterwave` | flutterwave | public | `payments/PaymentsController.java:62` |
| POST | `/api/v1/payments/webhook/paystack` | paystack | public | `payments/PaymentsController.java:53` |
| POST | `/api/v1/payments/webhook/quickteller` | Quickteller's notification is only a hint: whatever it says, the portal asks Interswitch's requery API what the reference actually settled for and settles on that answer alone. So the notification is answered 200 and the | public | `payments/PaymentsController.java:78` |

### Platform, notices & mail (`platform`, 16 endpoints)

The platform itself: `status` (public), `readiness`, the migration ledger, the notices outbox with retry, the mail (SMTP) and SMS settings, the Super Administrator's reset and demo-removal actions, and `me/notices` for a staff member's own notices. Director of ICT, System Administrator, Super Administrator (the Registrar reads the outbox).

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/me/notices` | mine | any signed-in user | `platform/MeNoticesController.java:33` |
| GET | `/api/v1/platform/mail` | config | admin, ict, super | `platform/MailController.java:32` |
| PUT | `/api/v1/platform/mail` | save | admin, ict, super | `platform/MailController.java:38` |
| POST | `/api/v1/platform/mail/clear-password` | clearPassword | admin, ict, super | `platform/MailController.java:44` |
| GET | `/api/v1/platform/migrations` | the migration ledger: what has been applied to this database, in order | admin, ict, super | `platform/PlatformController.java:185` |
| GET | `/api/v1/platform/notices` | outbox | admin, ict, registrar, super | `platform/NoticesController.java:28` |
| POST | `/api/v1/platform/notices/retry-failed` | put every failed notice back in the queue | admin, ict, super | `platform/NoticesController.java:54` |
| POST | `/api/v1/platform/notices/{id}/retry` | put one failed notice back in the queue; the dispatcher tries it again within the minute | admin, ict, super | `platform/NoticesController.java:46` |
| GET | `/api/v1/platform/readiness` | Go-live readiness for a session: each configuration gate that silently blocks part of launch, checked live, so it is a screen and not a manual list. Read-only. | academic, admin, bursar, dregistrar, ict, registrar, super | `platform/PlatformController.java:103` |
| POST | `/api/v1/platform/remove-demo` | Remove only the demo (db/demo.sql) operational data — demo students, DMO courses and demo candidates — keeping the demo staff logins and every real upload. Guarded by the words REMOVE DEMO; the database function runs it  | ict, super | `platform/PlatformController.java:72` |
| POST | `/api/v1/platform/remove-demo-courses` | Remove only the demo courses left in the catalogue — those coded DMO/DMC or titled 'Demo …' — with their offerings, materials, score sheets and registration entries. Touches no student or candidate. Guarded by the words  | ict, super | `platform/PlatformController.java:83` |
| POST | `/api/v1/platform/reset-data` | The Super Administrator's clean slate: clears operational data (admissions, students, results, courses, fees, payments, wallets) while keeping reference data, configuration, staff logins and the audit trail. Guarded by t | ict, super | `platform/PlatformController.java:57` |
| GET | `/api/v1/platform/sms` | config | admin, ict, super | `platform/SmsController.java:32` |
| PUT | `/api/v1/platform/sms` | save | admin, ict, super | `platform/SmsController.java:38` |
| POST | `/api/v1/platform/sms/clear-key` | clearKey | admin, ict, super | `platform/SmsController.java:44` |
| GET | `/api/v1/platform/status` | status | public | `platform/PlatformController.java:174` |

### Postgraduate school (`pgadmissions`, 68 endpoints)

The School of Postgraduate Studies: the public application (`pg/apply`, `pg/programmes`, `pg/status`, `pg/sign-in`, referees by token), the PG applicant's portal (documents, fee, referees, offer), admissions decisions by department, faculty and School with their bounds, PG registration and scores, the research lifecycle (supervision, proposals, documents, review, defence, award → graduand), and the School's own calendar (V224). Dean and Secretary of the Postgraduate School, Heads of Department, Deans, the Registry, the Bursar.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/pg/applications` | the postgraduate applications for a session, newest submission first, with a per-state count | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:122` |
| GET | `/api/v1/pg/applications/{id}` | one application in full: the applicant, the first degree, the proposal, its referees and documents | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:411` |
| POST | `/api/v1/pg/applications/{id}/accept` | record the applicant's acceptance of the offer (they may also do this themselves once the portal is open) | pgschool, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:635` |
| POST | `/api/v1/pg/applications/{id}/admit` | admit the accepted applicant: create the student on the register (entry_mode POSTGRADUATE) | pgschool, pgsecretary, registrar, super | `pgadmissions/PgAdmissionsController.java:644` |
| POST | `/api/v1/pg/applications/{id}/confirm-fee` | confirm a postgraduate fee payment by its reference (a bank confirmation, or a gateway callback) | bursar, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:658` |
| POST | `/api/v1/pg/applications/{id}/dept-decision` | the department's postgraduate committee recommends (or declines) a submitted application | academic, hod, super | `pgadmissions/PgAdmissionsController.java:574` |
| GET | `/api/v1/pg/applications/{id}/documents.pdf` | every document the applicant uploaded, merged into one PDF for the School to read and keep — the PDF certificates concatenated, and the passport added as an image page. Scoped to the application. | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:517` |
| GET | `/api/v1/pg/applications/{id}/documents/{docId}` | the credentials document an applicant uploaded, streamed for the desk to read inline (the O'/A'Level and birth-certificate PDF). Scoped to its application, so an id alone cannot reach another's file. | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:493` |
| POST | `/api/v1/pg/applications/{id}/faculty-decision` | the faculty (the Dean) recommends (or declines) an application the department recommended | academic, dean, super | `pgadmissions/PgAdmissionsController.java:590` |
| POST | `/api/v1/pg/applications/{id}/spgs-decision` | the School of Postgraduate Studies offers (or refuses) admission | pgschool, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:606` |
| POST | `/api/v1/pg/apply` | apply: creates the applicant account and a submitted application, and returns the fee reference to pay | public | `pgadmissions/PgApplyController.java:82` |
| GET | `/api/v1/pg/calendar` | Every PG session, which one is current, and the semesters of the session asked for (else the current). | academic, bursar, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgCalendarController.java:67` |
| PUT | `/api/v1/pg/calendar/sessions/{session}/{year}` | saveSession | pgschool, pgsecretary, super | `pgadmissions/PgCalendarController.java:90` |
| POST | `/api/v1/pg/calendar/sessions/{session}/{year}/close` | close | pgschool, pgsecretary, super | `pgadmissions/PgCalendarController.java:128` |
| POST | `/api/v1/pg/calendar/sessions/{session}/{year}/make-current` | makeCurrent | pgschool, pgsecretary, super | `pgadmissions/PgCalendarController.java:115` |
| PUT | `/api/v1/pg/calendar/sessions/{session}/{year}/semesters/{number}` | saveSemester | pgschool, pgsecretary, super | `pgadmissions/PgCalendarController.java:139` |
| GET | `/api/v1/pg/coursework/courses` | the courses of a programme (desk) | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:204` |
| POST | `/api/v1/pg/coursework/courses` | add (or update) a course on a programme (desk) | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:235` |
| GET | `/api/v1/pg/coursework/courses/all` | every postgraduate course on record, with its programme — the whole catalogue for the desk | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:215` |
| POST | `/api/v1/pg/coursework/courses/import` | bulk-upload the postgraduate course catalogue from a spreadsheet (desk). Each row names the programme (its code or its name), the course code, the title, units, kind and semester; it upserts on (programme, code), so a re | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:263` |
| GET | `/api/v1/pg/coursework/me` | the signed-in PG student's programme courses, their registration and their results for a session/semester | student | `pgadmissions/PgCourseworkController.java:57` |
| POST | `/api/v1/pg/coursework/register` | the student registers (or updates) their courses for a session/semester (Policy 7) | student | `pgadmissions/PgCourseworkController.java:187` |
| GET | `/api/v1/pg/coursework/registrations` | the registrations for a session, optionally by programme (desk: to endorse and to enter scores) | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:325` |
| GET | `/api/v1/pg/coursework/registrations/{id}` | one registration's courses and scores (desk) | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:349` |
| POST | `/api/v1/pg/coursework/registrations/{id}/endorse` | endorse a registration (the Head of Department / School) | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:379` |
| POST | `/api/v1/pg/coursework/score` | record (or revise) a score; the grade is computed from the total (Policy 16) | academic, hod, pgschool, pgsecretary, super | `pgadmissions/PgCourseworkController.java:398` |
| GET | `/api/v1/pg/coursework/summary` | a compact summary for the PG student's dashboard: coursework standing, latest registration, research stage | student | `pgadmissions/PgCourseworkController.java:103` |
| GET | `/api/v1/pg/dashboard` | the School of Postgraduate Studies' home: what waits on the School, the register, and the pipeline by programme | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:179` |
| POST | `/api/v1/pg/documents` | the applicant uploads (or replaces) their combined credentials PDF (after payment) | applicant | `pgadmissions/PgPortalController.java:396` |
| DELETE | `/api/v1/pg/documents/{docId}` | the applicant removes one of their uploaded documents (not the passport) — after payment | applicant | `pgadmissions/PgPortalController.java:435` |
| GET | `/api/v1/pg/documents/{docId}/content` | one of the applicant's own documents, streamed back to them; scoped to their application | applicant | `pgadmissions/PgPortalController.java:354` |
| POST | `/api/v1/pg/email-summary` | email the applicant a link to sign in and download their application summary (PDF) | applicant | `pgadmissions/PgPortalController.java:518` |
| GET | `/api/v1/pg/examiners` | the external examiners of the School (Policy 18) | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:353` |
| POST | `/api/v1/pg/examiners` | appoint an external examiner (the School, on the Board's approval) | pgschool, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:369` |
| POST | `/api/v1/pg/fee-reference` | The reference to pay the application fee against, ready for checkout. A live unpaid reference is reused; a missing or expired one is minted afresh (the mint is an applicant-attributed write, since admissions.pg_fee_refer | applicant | `pgadmissions/PgPortalController.java:193` |
| POST | `/api/v1/pg/first-degree` | the applicant states (or amends) the first degree the admission rests on (after payment) | applicant | `pgadmissions/PgPortalController.java:550` |
| GET | `/api/v1/pg/me` | the signed-in applicant's own application, with the application fee and whether it is paid | applicant | `pgadmissions/PgPortalController.java:181` |
| POST | `/api/v1/pg/passport` | the applicant uploads (or replaces) their passport photograph (after payment) | applicant | `pgadmissions/PgPortalController.java:451` |
| GET | `/api/v1/pg/passport/image` | the applicant's own passport photograph, so it can be shown on their summary and printout | applicant | `pgadmissions/PgPortalController.java:481` |
| GET | `/api/v1/pg/programmes` | the postgraduate programmes to apply into, for the form's picker (public) | public | `pgadmissions/PgApplyController.java:53` |
| POST | `/api/v1/pg/qualifications` | the applicant states (or amends) their other qualifications — everything but the first degree (after payment) | applicant | `pgadmissions/PgPortalController.java:597` |
| GET | `/api/v1/pg/referee/{token}` | the reference request behind a token: who named the referee, for what, and whether it is done (public) | public | `pgadmissions/PgRefereeController.java:49` |
| POST | `/api/v1/pg/referee/{token}` | the referee submits their reference (public, once) | public | `pgadmissions/PgRefereeController.java:84` |
| POST | `/api/v1/pg/referees` | the applicant sets (or amends) their referees; each new referee with an email is sent a reference request (after payment) | applicant | `pgadmissions/PgPortalController.java:634` |
| GET | `/api/v1/pg/research` | the research pipeline, optionally filtered by stage, with per-stage counts (School desk) | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:111` |
| GET | `/api/v1/pg/research/me` | the signed-in postgraduate student's research record (created on first read) | student | `pgadmissions/PgResearchController.java:60` |
| POST | `/api/v1/pg/research/me/documents` | the candidate submits a document on their own research | student | `pgadmissions/PgResearchController.java:351` |
| GET | `/api/v1/pg/research/me/documents/{docId}/content` | the candidate reads one of their own documents back | student | `pgadmissions/PgResearchController.java:391` |
| POST | `/api/v1/pg/research/me/proposal` | the candidate submits the research proposal (topic required); moves to PROPOSAL_SUBMITTED | student | `pgadmissions/PgResearchController.java:91` |
| POST | `/api/v1/pg/research/me/topic` | the candidate states or revises the working topic (before the proposal is approved) | student | `pgadmissions/PgResearchController.java:73` |
| GET | `/api/v1/pg/research/{id}` | one candidate's research record in full (School desk) | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:146` |
| POST | `/api/v1/pg/research/{id}/action` | Advance a candidate through the pipeline. One endpoint, one action at a time, each setting its stage and milestone and writing the log. The actions follow the policy's stages; the School desk drives them. | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:232` |
| GET | `/api/v1/pg/research/{id}/documents/{docId}/content` | the desk reads a candidate's document | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:406` |
| POST | `/api/v1/pg/research/{id}/documents/{docId}/review` | the desk accepts or returns a document the candidate submitted; the version stays on the record either way | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:422` |
| POST | `/api/v1/pg/research/{id}/panel-member` | add a member to the panel of examiners (Policy 24.3): chair, external, supervisor(s), internal, PGSR, coordinator | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:185` |
| POST | `/api/v1/pg/research/{id}/supervisor` | assign a supervisor to a candidate; the first assignment moves REGISTERED → SUPERVISED (Policy 14) | pgschool, pgsecretary, super | `pgadmissions/PgResearchController.java:158` |
| GET | `/api/v1/pg/secretary/clearance` | thesis clearance: the final versions awaiting the Secretary's clearance before binding, and those cleared | academic, dregistrar, pgschool, pgsecretary, registrar, super | `pgadmissions/PgSecretaryController.java:127` |
| GET | `/api/v1/pg/secretary/dashboard` | The Secretary's home: what waits on the Secretary this session — students yet to register, fee references awaiting confirmation, registered courses awaiting a result, and theses awaiting the Secretary's clearance before  | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:247` |
| GET | `/api/v1/pg/secretary/examinations` | course examinations: the courses sat this semester and where their results stand | academic, dregistrar, pgschool, pgsecretary, registrar, super | `pgadmissions/PgSecretaryController.java:92` |
| GET | `/api/v1/pg/secretary/registration` | registration & matriculation: who is yet to register, who has, the part-time share, and who lapsed | academic, dregistrar, pgschool, pgsecretary, registrar, super | `pgadmissions/PgSecretaryController.java:35` |
| GET | `/api/v1/pg/secretary/senate` | the award of degrees: computed results with the Board for Senate, and those Senate has awarded this session | academic, dregistrar, pgschool, pgsecretary, registrar, super | `pgadmissions/PgSecretaryController.java:156` |
| GET | `/api/v1/pg/sessions/{session}/{year}/fees` | the postgraduate application and acceptance fees in force for a session (the stated ones, else the default) | bursar, pgschool, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:84` |
| PUT | `/api/v1/pg/sessions/{session}/{year}/fees` | the Bursary states the postgraduate fees for a session | bursar, pgschool, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:102` |
| POST | `/api/v1/pg/sign-in` | sign in on the email the applicant applied with, or their PG application number, and their password (public) | public | `pgadmissions/PgPortalController.java:117` |
| POST | `/api/v1/pg/sign-out` | signOut | applicant | `pgadmissions/PgPortalController.java:168` |
| GET | `/api/v1/pg/status` | check an application's status, by its number and the email it was made with (public). The admission decision and the School's note are released only once the checking fee is confirmed — the same mask the signed-in portal | public | `pgadmissions/PgApplyController.java:137` |
| GET | `/api/v1/pg/students` | the postgraduate register: every PG student with their coursework CGPA, academic standing and research stage | academic, dean, dregistrar, dvc, hod, pgschool, pgsecretary, registrar, super, vc | `pgadmissions/PgAdmissionsController.java:306` |
| POST | `/api/v1/pg/students/{id}/status` | defer, withdraw or reinstate a postgraduate student (Policy 19–20), on a cited instrument | pgschool, pgsecretary, super | `pgadmissions/PgAdmissionsController.java:389` |

### Provost's desk (`provost`, 1 endpoints)

The Provost's dashboard endpoint. No screen calls it (§4); the College dashboard under `college` is the Provost's home.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/provost/dashboard` | dashboard | collegesecretary, financecontroller, provost, super | `provost/ProvostController.java:64` |

### Public verification (`verify`, 7 endpoints)

The public verification doors, each gated by a check token or an unguessable reference and answering `genuine: true|false`: receipts, examination cards, course registration forms, semester result statements, filed report snapshots, Post-UTME slips and hostel letters. The digital-document verifier is listed under `credentials` (`/api/v1/verify/document`).

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/verify/exam` | Verify a student's examination card. The card's QR opens the public page, which asks this for the authoritative permit: the student's name and PHOTO (so the invigilator confirms the face — anti-impersonation), whether th | public | `verify/VerifyController.java:133` |
| GET | `/api/v1/verify/hostel/{ref}` | A hostel allocation letter or clearance certificate, by the allocation reference its QR carries (V261): the student's name and PHOTO, the hall, block, room and bed, the state of the stay and its clearance — so a forged o | public | `verify/VerifyController.java:369` |
| GET | `/api/v1/verify/putme/{token}` | A Post-UTME examination slip, by the token its QR carries (V260): the candidate's name and PHOTO, the batch, the day, the time, the centre, the room and the seat, and whether the candidate has been checked in — so a clon | public | `verify/VerifyController.java:324` |
| GET | `/api/v1/verify/receipt/{reference}` | receipt | public | `verify/VerifyController.java:49` |
| GET | `/api/v1/verify/registration` | Verify a course registration form. The form's QR opens the public page, which asks this for the University's own record: the student, the approved courses, the units and the approval date. The record is the truth; the pr | public | `verify/VerifyController.java:202` |
| GET | `/api/v1/verify/report/{code}` | A kept return, by the verification code its printed footing carries (V229): what it is, the period, when it was taken and by which office, how many rows, its totals, and whether it was filed — so the figures on a filed c | public | `verify/VerifyController.java:306` |
| GET | `/api/v1/verify/results` | Verify a semester results statement. The statement's QR opens the public page, which asks this for the University's own record: the published grades, the semester and cumulative GPA, the class of standing and the Senate  | public | `verify/VerifyController.java:251` |

### Reference data (`ref`, 3 endpoints)

Reference data every signed-in office may read: the structure ladder (colleges, faculties, departments, programmes), the sessions and the courses.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/ref/courses` | courses | any signed-in user | `ref/RefController.java:36` |
| GET | `/api/v1/ref/sessions` | sessions | any signed-in user | `ref/RefController.java:31` |
| GET | `/api/v1/ref/structure` | Colleges, faculties, departments and programmes — the scope bar's ladder. | any signed-in user | `ref/RefController.java:26` |

### Reporting (`reporting`, 1 endpoints)

One read: the session so far in figures — students, result sets and collections — for management, the Registry, the Bursary and audit.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/reporting/overview` | the session so far, in figures: students, result sets and collections | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `reporting/ReportingController.java:29` |

### Reports (`reports`, 18 endpoints)

Reports: the student and staff registers with paging and filters (§1.8), snapshots taken and filed with a verification code (`/verify/report/{code}`), attachments and email of a snapshot, and the returns each office files. Nearly every office acts within its scope.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/reports/carryovers` | Outstanding carryovers, as at now: for every active student, a course whose LATEST published attempt is an F is still carried; grouped by faculty, programme and course so the office sees the re-sit load. Set-based (one p | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, ict, records, registrar, super, vc | `reports/ReportsController.java:151` |
| GET | `/api/v1/reports/due` | the due register as at today (or the day asked for): one row per return | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:119` |
| GET | `/api/v1/reports/enrolment` | Enrolment for a session's cohort: students admitted that session, by faculty, programme and level, split by sex. | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, ict, records, registrar, super, vc | `reports/ReportsController.java:82` |
| GET | `/api/v1/reports/expenditure` | Expenditure for a financial year: budget, committed, spent and available by cost centre (V045). | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `reports/ReportsController.java:241` |
| GET | `/api/v1/reports/income-expenditure` | The income and expenditure statement for a financial year, read off the general ledger (V145): every income and expense account with its movement, the totals and the surplus or deficit, beside the year's expenditure budg | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `reports/ReportsController.java:261` |
| GET | `/api/v1/reports/postgraduate` | The postgraduate return for a session (V202, V211, V209): by programme, the applications the session drew and how far they went (offered, accepted, admitted), the candidates on the register by mode of study, and the rese | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/ReportsController.java:301` |
| GET | `/api/v1/reports/registers/staff` | the staff register, filtered and searched: every person with a staff number, with what HR holds on them | academic, admin, audit, bursar, dean, deputyaudit, dregistrar, dvc, facultyofficer, hod, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/RegistersController.java:158` |
| GET | `/api/v1/reports/registers/students` | the student register, filtered and searched | academic, admin, audit, bursar, dean, deputyaudit, dregistrar, dvc, facultyofficer, hod, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/RegistersController.java:69` |
| GET | `/api/v1/reports/registration-cause` | Registration cause: the not-registered students per faculty/programme split into fee-blocked (the Bursary has not cleared them) vs cleared-but-idle (cleared, not registered). Guides whether the fix is a payment plan or a | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, ict, records, registrar, super, vc | `reports/ReportsController.java:120` |
| GET | `/api/v1/reports/revenue` | Revenue confirmed for a session: student fees and applicant fees, by category. | academic, admin, audit, bursar, dregistrar, dvc, ict, registrar, super, vc | `reports/ReportsController.java:203` |
| GET | `/api/v1/reports/snapshots` | the snapshots kept, newest first — for one return, or all | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:199` |
| POST | `/api/v1/reports/snapshots` | keep a copy of a return as it was run: returns the snapshot id and its verification code | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:153` |
| GET | `/api/v1/reports/snapshots/{id}` | one snapshot, whole — headers, rows and totals as kept | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:218` |
| GET | `/api/v1/reports/snapshots/{id}/dispatches` | the emails a kept copy went out by, newest first | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:106` |
| POST | `/api/v1/reports/snapshots/{id}/email` | Email a kept return to the people it is for, with the files attached (the PDF and the Excel workbook the portal built from the kept rows). One notice per recipient, queued in this transaction against the snapshot, so the | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:71` |
| POST | `/api/v1/reports/snapshots/{id}/file` | record that a kept return was filed — with whom, and any note | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, hrm, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/SnapshotsController.java:240` |
| GET | `/api/v1/reports/staff-ratio` | Staff/student ratio by department, for the NUC accreditation return: the students on the books under each department's programmes against the academic staff whose home department it is (V137 staff record, holding the lec | academic, admin, dean, dregistrar, dvc, facultyofficer, hod, hrm, ict, records, registrar, super, vc | `reports/ReportsController.java:367` |
| GET | `/api/v1/reports/trends` | Period over period, for the returns desk: the last three sessions side by side (students admitted, applications and offers, postgraduate applications, carryovers) and the last six months (fees confirmed, vouchers paid).  | academic, admin, audit, bursar, dean, dregistrar, dvc, facultyofficer, hod, ict, pgschool, pgsecretary, records, registrar, super, vc | `reports/ReportsController.java:422` |

### Results & assessment (`results`, 37 endpoints)

Results and assessment: score sheets per offering (open, enter, submit, mark, lock), the results chain through department, faculty and Senate with publication, the grading policy in force, students' standing (probation and withdrawal, V246), result queries, the broadsheet and the semester statement. Lecturers, Examinations Officers, Heads of Department, Deans, Exams and Records, the Academic Office and the Registry act; management reads.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/results/broadsheet` | broadsheet | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:239` |
| GET | `/api/v1/results/exam-sessions` | examSessions | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:190` |
| POST | `/api/v1/results/exam-sessions` | create | academic, dregistrar, records, registrar | `results/ResultsController.java:196` |
| PUT | `/api/v1/results/exam-sessions/{id}` | editExamSession | academic, dregistrar, records, registrar | `results/ResultsController.java:202` |
| GET | `/api/v1/results/exam-sessions/{id}/monitor` | monitor | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:214` |
| POST | `/api/v1/results/exam-sessions/{id}/open` | open | academic, dregistrar, records, registrar | `results/ResultsController.java:208` |
| GET | `/api/v1/results/held/owing` | the students a held script is waiting on, with what they owe — the Bursary's list | academic, admin, bursar, dean, dregistrar, dvc, exams, hod, records, registrar, super, vc | `results/HeldScriptsController.java:149` |
| POST | `/api/v1/results/legacy/biodata` | the full student biography exported from the old portal — core, contact, biography and a sign-in account | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:57` |
| POST | `/api/v1/results/legacy/default-passwords` | set a first password (the student's own number) for migrated accounts still on the random import password; must_change stays on, so the student replaces it at first sign-in. Same offices as the rest of the migration desk | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:140` |
| POST | `/api/v1/results/legacy/jamb-numbers` | set students' JAMB registration numbers from a matric → JAMB upload, so passport photos named by the JAMB number can match a legacy student who carries no candidate. Same offices as the rest of the desk. | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:123` |
| POST | `/api/v1/results/legacy/passports` | bulk passport photos from the old portal, each named by the student's JAMB reg no; a photo whose number matches no candidate is skipped and reported. Same offices as the rest of the migration desk. | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:131` |
| POST | `/api/v1/results/legacy/pg-registration` | the postgraduate course registration of a past session/semester, into the postgraduate module (V214) | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:94` |
| POST | `/api/v1/results/legacy/pg-research` | the postgraduate research / thesis records exported from the old portal (V215) | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:115` |
| POST | `/api/v1/results/legacy/pg-results` | the postgraduate past results of a session/semester, graded on the postgraduate scale (V214) | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:101` |
| POST | `/api/v1/results/legacy/pg-students` | the postgraduate students exported from the old portal — kept at their postgraduate level (700/800/900) and school (S002), the programme created in the shared table when it is not yet there | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:65` |
| POST | `/api/v1/results/legacy/reconcile-pg-results` | post every past postgraduate result held for a student not on the register when uploaded (V214) | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:108` |
| POST | `/api/v1/results/legacy/reconcile-results` | post every past result held for a student who was not on the register when the results were uploaded, but has since been loaded — run after a student/biography upload (V204) | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:73` |
| POST | `/api/v1/results/legacy/registration` | the course registration of a past semester, from the old portal | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:80` |
| POST | `/api/v1/results/legacy/results` | the past results of a semester, imported as final under a legacy minute | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:87` |
| POST | `/api/v1/results/legacy/students` | the students exported from the old portal — the first migration step, so results and registration can match | academic, dean, dregistrar, exams, facultyexams, hod, ict, records, registrar, super | `results/ResultsController.java:50` |
| GET | `/api/v1/results/mine` | mine | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:226` |
| PUT | `/api/v1/results/offerings/{offeringId}/exam-slot` | the paper's slot: day, time and venue, which the docket carries | academic, exams, facultyexams, records, registrar, super | `results/QueriesController.java:94` |
| GET | `/api/v1/results/queries` | queries | academic, dean, exams, hod, lecturer, records, registrar, super | `results/QueriesController.java:56` |
| POST | `/api/v1/results/queries/{id}/answer` | answer | academic, dean, exams, hod, lecturer, records, registrar, super | `results/QueriesController.java:80` |
| GET | `/api/v1/results/senate` | senate | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:246` |
| POST | `/api/v1/results/senate/minute` | minute | dregistrar, registrar | `results/ResultsController.java:255` |
| GET | `/api/v1/results/sheets` | sheets | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:146` |
| GET | `/api/v1/results/sheets/{id}` | sheet | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:157` |
| POST | `/api/v1/results/sheets/{id}/advance` | advance | academic, dean, dregistrar, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar | `results/ResultsController.java:169` |
| GET | `/api/v1/results/sheets/{id}/held` | the sheet's held scripts, after any past the closing date have lapsed | academic, admin, bursar, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/HeldScriptsController.java:100` |
| POST | `/api/v1/results/sheets/{id}/held` | hold a script: the candidate by number, the two marks (or the outcome), a note | academic, exams, lecturer | `results/HeldScriptsController.java:109` |
| POST | `/api/v1/results/sheets/{id}/held/bulk` | hold many at once from the uploaded template: every line holds, or none does and each refusal is named | academic, exams, lecturer | `results/HeldScriptsController.java:126` |
| DELETE | `/api/v1/results/sheets/{id}/held/{held}` | withdraw a held script entered wrongly; only a script still held | academic, exams, lecturer | `results/HeldScriptsController.java:140` |
| POST | `/api/v1/results/sheets/{id}/remind` | No notification module yet: the reminder is counted, not sent, and says so. | academic, dean, dregistrar, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar | `results/ResultsController.java:182` |
| POST | `/api/v1/results/sheets/{id}/return` | giveBack | academic, dean, dregistrar, exams, facultyexams, facultyofficer, hod, lecturer, records, registrar | `results/ResultsController.java:175` |
| GET | `/api/v1/results/sheets/{id}/roll` | roll | academic, admin, dean, dregistrar, dvc, exams, facultyexams, facultyofficer, hod, ict, lecturer, records, registrar, super, vc | `results/ResultsController.java:233` |
| PUT | `/api/v1/results/sheets/{id}/scores` | scores | academic, exams, lecturer | `results/ResultsController.java:163` |

### SIWES (`siwes`, 7 endpoints)

SIWES: the offerings in scope, the students on each with their supervisor, the practical report mark out of 60 (coordinator) and the supervisor's assessment out of 40 (`siwes/mine`, any signed-in supervisor). SIWES Coordinators, Heads of Department, the Academic Office, the Registry.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/siwes/mine` | the acting supervisor's SIWES students, across offerings, with the sheet's stage and current mark | any signed-in user | `siwes/SiwesController.java:150` |
| PUT | `/api/v1/siwes/mine/students/{student}/score` | the acting supervisor records a student's assessment mark, out of 40 (the ca part) | any signed-in user | `siwes/SiwesController.java:178` |
| GET | `/api/v1/siwes/offerings` | the SIWES offerings in scope (a department office sees only its own department) | academic, admin, dregistrar, hod, registrar, siwes, super | `siwes/SiwesController.java:67` |
| GET | `/api/v1/siwes/offerings/{offering}/students` | the students on a SIWES offering, each with their supervisor and current mark | academic, admin, dregistrar, hod, registrar, siwes, super | `siwes/SiwesController.java:90` |
| PUT | `/api/v1/siwes/offerings/{offering}/students/{student}/practical` | the coordinator records a student's practical report mark, out of 60 (the exam part) | academic, admin, dregistrar, hod, registrar, siwes, super | `siwes/SiwesController.java:194` |
| PUT | `/api/v1/siwes/offerings/{offering}/students/{student}/supervisor` | assign (or move) a supervisor to a student on a SIWES offering | academic, admin, dregistrar, hod, registrar, siwes, super | `siwes/SiwesController.java:138` |
| GET | `/api/v1/siwes/offerings/{offering}/supervisors` | the department's lecturers, who may be assigned as supervisors | academic, admin, dregistrar, hod, registrar, siwes, super | `siwes/SiwesController.java:120` |

### Staff (`staff`, 6 endpoints)

The signed-in employee's own record: `staff/me` (the person and offices), the academic profile read and written whole, the photograph (base64, JPEG/PNG up to 2 MB), and the College tier a code belongs to. Any signed-in token, never another person's record.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/staff/college/{code}` | college | any signed-in user | `staff/StaffController.java:83` |
| GET | `/api/v1/staff/me` | The acting person and the offices they hold. Never another person's. | any signed-in user | `staff/StaffController.java:37` |
| GET | `/api/v1/staff/profile` | The acting person's own academic profile — their CV as the portal holds it. Never another person's. | any signed-in user | `staff/StaffController.java:43` |
| PUT | `/api/v1/staff/profile` | The acting person edits their own profile whole. The DB takes the person from the audit context. | any signed-in user | `staff/StaffController.java:49` |
| GET | `/api/v1/staff/profile/photo` | The acting person's photograph, base64 in a small object; 404 when none is set. | any signed-in user | `staff/StaffController.java:55` |
| PUT | `/api/v1/staff/profile/photo` | Upload or replace the acting person's photograph — JPEG or PNG, up to 2 MB, sent base64 in JSON. | any signed-in user | `staff/StaffController.java:64` |

### Statistics (`stats`, 2 endpoints)

The student statistics engine (V257): the figures in all and by faculty, department, programme and degree type, and the students behind a figure a page at a time, names A–Z, with the same filters. Management, the Registry, the Bursary, Deans, Heads of Department and the College offices read within their scope.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/stats/students` | the students behind a figure: the same rows, the same filters, a page at a time, names A–Z | academic, admin, bursar, collegesecretary, dean, dregistrar, dvc, exams, facultyofficer, financecontroller, hod, ict, pgschool, pgsecretary, provost, records, registrar, super, vc | `stats/StudentStatsController.java:229` |
| GET | `/api/v1/stats/students/summary` | the figures: in all, and by faculty, department, programme and degree type — one pass over the rows | academic, admin, bursar, collegesecretary, dean, dregistrar, dvc, exams, facultyofficer, financecontroller, hod, ict, pgschool, pgsecretary, provost, records, registrar, super, vc | `stats/StudentStatsController.java:126` |

### Student portal (`studentportal`, 26 endpoints)

The student's own desk under `/me`: sign-in, sign-out and change of password on the student door (`student-auth`), the dashboard, biodata, registration, results and GPA, fees and receipts, examination card, clearance, the legacy transcript request (unused, §4), and the Registry's opening of a student account.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/me` | contact | student | `MeController.java:49` |
| PUT | `/api/v1/me/contact` | contact | student | `MeController.java:54` |
| GET | `/api/v1/me/docket` | docket | student | `MeController.java:135` |
| GET | `/api/v1/me/fees` | fees | student | `MeController.java:59` |
| GET | `/api/v1/me/fees/receipts/{reference}` | receipt | student | `MeController.java:69` |
| POST | `/api/v1/me/fees/references` | reference | student | `MeController.java:64` |
| GET | `/api/v1/me/graduation` | graduation | student | `MeController.java:169` |
| GET | `/api/v1/me/id-card` | card | student | `MeController.java:145` |
| POST | `/api/v1/me/id-card/lost` | lost | student | `MeController.java:150` |
| GET | `/api/v1/me/passport` | the student's passport image — resolved from the document store or the JAMB/attachment store, so a migrated or JAMB-loaded photo also appears on the course form and identity documents. | student | `MeController.java:176` |
| GET | `/api/v1/me/queries` | queries | student | `MeController.java:125` |
| POST | `/api/v1/me/queries` | raise | student | `MeController.java:130` |
| GET | `/api/v1/me/registration` | registration | student | `MeController.java:74` |
| PUT | `/api/v1/me/registration` | choose | student | `MeController.java:84` |
| GET | `/api/v1/me/registration-history` | registrationHistory | student | `MeController.java:79` |
| POST | `/api/v1/me/registration/add` | add a course to a submitted/approved registration during the add/drop window | student | `MeController.java:98` |
| POST | `/api/v1/me/registration/drop` | drop a non-carryover course from a registration during the add/drop window | student | `MeController.java:104` |
| POST | `/api/v1/me/registration/submit` | submit | student | `MeController.java:89` |
| GET | `/api/v1/me/results` | results | student | `MeController.java:109` |
| GET | `/api/v1/me/timetable` | timetable | student | `MeController.java:140` |
| GET | `/api/v1/me/transcripts` | transcripts | student | `MeController.java:155` |
| POST | `/api/v1/me/transcripts` | requestTranscript | student | `MeController.java:160` |
| PUT | `/api/v1/student-auth/accounts/{studentId}` | the Registry opens or resets a student's portal account with a first password the student must change | academic, dregistrar, ict, records, registrar, super | `StudentAuthController.java:61` |
| POST | `/api/v1/student-auth/change-password` | changePassword | student | `StudentAuthController.java:54` |
| POST | `/api/v1/student-auth/sign-in` | signIn | public | `StudentAuthController.java:41` |
| POST | `/api/v1/student-auth/sign-out` | signOut | student | `StudentAuthController.java:46` |

### Student records (`student`, 20 endpoints)

Student records: the register, a student's record and biodata, the intake run that brings a session's admitted candidates onto the register (called by the Admissions page), biodata change requests (a queue nothing can currently feed — see *09 Feature Status Report*), and account actions. Registrar, Deputy Registrar (Academic Affairs), Academic Office, Exams and Records, Director of ICT.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/me/biodata` | mine | student | `student/MeBiodataController.java:35` |
| PUT | `/api/v1/me/biodata/{field}` | write | student | `student/MeBiodataController.java:41` |
| GET | `/api/v1/student/biodata-changes` | queue |  | `student/StudentController.java:172` |
| POST | `/api/v1/student/biodata-changes/{id}/approve` | approve | academic, dregistrar, registrar | `student/StudentController.java:178` |
| POST | `/api/v1/student/biodata-changes/{id}/ask-evidence` | askForEvidence | academic, dregistrar, registrar | `student/StudentController.java:190` |
| POST | `/api/v1/student/biodata-changes/{id}/refuse` | refuse | academic, dregistrar, registrar | `student/StudentController.java:184` |
| POST | `/api/v1/student/intake/{session}/{year}` | The intake run: the session's admitted candidates, brought onto the register. | academic, dregistrar, registrar | `student/StudentController.java:218` |
| GET | `/api/v1/student/records/{view}` | records |  | `student/StudentController.java:204` |
| GET | `/api/v1/student/search` | Every search with a term is written to the audit trail before it answers. |  | `student/StudentController.java:197` |
| GET | `/api/v1/student/students` | The register in a scope, and how many the University has on it altogether. |  | `student/StudentController.java:58` |
| GET | `/api/v1/student/students/migrated` | The students migrated from the old portal at these levels: how many, how many stand cleared at every unit, how many do not (V233). |  | `student/StudentController.java:71` |
| POST | `/api/v1/student/students/migrated/clear` | Clear the migrated students at these levels who still lack a unit's word — the old portal's clearance, carried over (V231/V233). | academic, dregistrar, ict, registrar, super | `student/StudentController.java:78` |
| GET | `/api/v1/student/students/voluntary-withdrawals` | Voluntary withdrawals (V247): the students four consecutive closed semesters without an approved registration have made due, named by the record, and how many records stand closed so far. | academic, dregistrar, ict, registrar, super | `student/StudentController.java:90` |
| POST | `/api/v1/student/students/voluntary-withdrawals/close` | The Registry's act: the students due (the ones named, or all) become VOLUNTARY_WITHDRAWAL on the regulation as the instrument. | academic, dregistrar, ict, registrar, super | `student/StudentController.java:105` |
| GET | `/api/v1/student/students/{id}` | One record entire. The session decides which registrations it shows. |  | `student/StudentController.java:125` |
| PUT | `/api/v1/student/students/{id}/biodata/{field}` | biodata | academic, dregistrar, registrar | `student/StudentController.java:151` |
| PUT | `/api/v1/student/students/{id}/level` | level | academic, dregistrar, registrar | `student/StudentController.java:165` |
| GET | `/api/v1/student/students/{id}/passport` | The student's passport photograph, from whichever store holds it (document, JAMB, attachment). |  | `student/StudentController.java:140` |
| GET | `/api/v1/student/students/{id}/portal` | The student's own portal view of themselves — fees, GPA and CGPA, standing, carryovers, this session's registration, graduation — read by an office for the record pop-up. The same figures the student sees. |  | `student/StudentController.java:133` |
| POST | `/api/v1/student/students/{id}/status` | status | academic, dregistrar, registrar | `student/StudentController.java:158` |

### Support services (`support`, 9 endpoints)

Support requests: a student raises a request to an office with supporting documents; the office's queue answers within its own scope, or the platform's across all. Academic Office, Bursar, Registry, Heads of Department, Housing, Library, ICT, Support Services.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/me/requests` | mine | student | `support/SupportController.java:72` |
| POST | `/api/v1/me/requests` | raise | student | `support/SupportController.java:79` |
| GET | `/api/v1/me/requests/{id}/documents` | the student lists the documents on their own request | student | `support/SupportController.java:92` |
| POST | `/api/v1/me/requests/{id}/documents` | the student attaches a supporting document to their own request | student | `support/SupportController.java:101` |
| GET | `/api/v1/me/requests/{id}/documents/{doc}/content` | myDocumentContent | student | `support/SupportController.java:109` |
| GET | `/api/v1/support/requests` | the office's queue: its own requests, the oldest open first — or every office's for the platform | academic, admin, bursar, dregistrar, hod, housing, ict, library, registrar, services, super | `support/SupportController.java:135` |
| POST | `/api/v1/support/requests/{id}/answer` | answer | academic, admin, bursar, dregistrar, hod, housing, ict, library, registrar, services, super | `support/SupportController.java:149` |
| GET | `/api/v1/support/requests/{id}/documents` | the office lists the documents on a request it handles | academic, admin, bursar, dregistrar, hod, housing, ict, library, registrar, services, super | `support/SupportController.java:118` |
| GET | `/api/v1/support/requests/{id}/documents/{doc}/content` | deskDocumentContent | academic, admin, bursar, dregistrar, hod, housing, ict, library, registrar, services, super | `support/SupportController.java:126` |

### Transfers (`transfers`, 12 endpoints)

Change of programme (transfers): the student's application and processing fee, the desks' approve/decline pipeline, recording a transfer for a student, the programmes a student may move to, and the committee path (review, Senate, withdraw, effect) that no screen drives (§4).

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/me/transfer` | mine | student | `transfers/TransferController.java:118` |
| POST | `/api/v1/me/transfer` | apply | student | `transfers/TransferController.java:144` |
| POST | `/api/v1/me/transfer/{id}/fee` | myFee | student | `transfers/TransferController.java:154` |
| GET | `/api/v1/transfers` | list | academic, admin, dregistrar, dvc, hod, ict, registrar, super, vc | `transfers/TransferController.java:169` |
| POST | `/api/v1/transfers` | record | academic, dregistrar, registrar, super | `transfers/TransferController.java:200` |
| GET | `/api/v1/transfers/programmes` | programmes | academic, admin, dregistrar, dvc, hod, ict, registrar, super, vc | `transfers/TransferController.java:193` |
| POST | `/api/v1/transfers/{id}/approve` | approve | academic, dregistrar, hod, registrar, super | `transfers/TransferController.java:230` |
| POST | `/api/v1/transfers/{id}/decline` | any desk currently holding the application may decline it, with the reason on the record (payment not required) | academic, dregistrar, hod, registrar, super | `transfers/TransferController.java:247` |
| POST | `/api/v1/transfers/{id}/effect` | effect | academic, dregistrar, ict, registrar, super | `transfers/TransferController.java:294` |
| POST | `/api/v1/transfers/{id}/review` | review | academic, dregistrar, dvc, registrar, super | `transfers/TransferController.java:263` |
| POST | `/api/v1/transfers/{id}/senate` | senate | dregistrar, dvc, registrar, super, vc | `transfers/TransferController.java:276` |
| POST | `/api/v1/transfers/{id}/withdraw` | withdraw | academic, dregistrar, registrar, super | `transfers/TransferController.java:286` |

### Undergraduate admissions (`admissions`, 124 endpoints)

Undergraduate admissions: CAPS batches loaded whole, reconciled and committed; programmes and their JAMB aliases; the merit list and offers within quota; Direct Entry awards and screening; O'Level grading and JAMB's own results; session policy, cut-offs and catchment; applicants, applications, documents, screening scores, decisions and their release; fee references and applicant fees; reconsiderations; candidate data (passports, dates of birth) and the JAMB admission template; the migration of paid applicants from the old portal; and the Post-UTME CBT (V260) — exam, centres, rooms, slots and days, batches with seating, publication and the slip. Academic Office, Registrar, Deputy Registrar (Academic Affairs), Exams and Records, Bursar and ICT act; management reads.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/admissions/applicants` | the applicants on committed admission lists — the admitted pool, and who has registered for post-UTME | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:63` |
| GET | `/api/v1/admissions/caps-batches` | list | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:50` |
| POST | `/api/v1/admissions/caps-batches` | load | academic, registrar | `admissions/AdmissionsController.java:36` |
| GET | `/api/v1/admissions/caps-batches/{id}` | get | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:56` |
| POST | `/api/v1/admissions/caps-batches/{id}/commit` | commit | academic, registrar | `admissions/AdmissionsController.java:178` |
| POST | `/api/v1/admissions/caps-batches/{id}/rows` | a large download arrives in several requests: the rows join the batch the first request opened | academic, registrar | `admissions/AdmissionsController.java:44` |
| POST | `/api/v1/admissions/caps-batches/{id}/withdraw` | A list loaded in error: kept as evidence, marked withdrawn for the reason given, and out of every count. | academic, registrar | `admissions/AdmissionsController.java:189` |
| GET | `/api/v1/admissions/de-awards` | the Direct Entry awards captured for a candidate — the basis and its subjects (V200) | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:125` |
| POST | `/api/v1/admissions/de-awards` | record (replace whole) a candidate's Direct Entry award and its subjects; returns the candidate's awards (V200) | academic, registrar | `admissions/AdmissionsController.java:145` |
| DELETE | `/api/v1/admissions/de-awards/{id}` | remove one Direct Entry award (V200) | academic, registrar | `admissions/AdmissionsController.java:155` |
| GET | `/api/v1/admissions/de-screening` | Direct Entry screening for a programme: the DE applicants with the subject gate's verdict (V200). Screening-only — separate from the UTME merit list and from the offer decision. | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:118` |
| GET | `/api/v1/admissions/merit` | the merit list for a programme: the eligible pool ranked, with the proposed offer that fills the quota | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:75` |
| POST | `/api/v1/admissions/merit/record` | recordMerit | academic, registrar | `admissions/AdmissionsController.java:100` |
| POST | `/api/v1/admissions/merit/record-many` | record the merit list for several programmes at once — all with a pool when none are named | academic, registrar | `admissions/AdmissionsController.java:110` |
| GET | `/api/v1/admissions/policies` | policies | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `admissions/AdmissionSettingsController.java:32` |
| GET | `/api/v1/admissions/post-utme-programmes` | the programmes registered for post-UTME and their score-upload status — which programmes' scores must be uploaded before the admission process proceeds | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:83` |
| GET | `/api/v1/admissions/programmes` | The programmes and their JAMB names, so a list can be resolved before it is loaded. | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:215` |
| PUT | `/api/v1/admissions/programmes/{code}` | The University's own words for a programme; the code is for ever, and JAMB's name is set separately. | academic, registrar | `admissions/AdmissionsController.java:238` |
| PUT | `/api/v1/admissions/programmes/{code}/jamb-alias` | What JAMB calls this programme — the name a CAPS download is matched on. | academic, registrar | `admissions/AdmissionsController.java:225` |
| GET | `/api/v1/admissions/reg-no` | {@code ?in=202699168863AH_Face.jpg} → the number the database reads out of it, or none. | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:245` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/applicant-fees` | the applicant fees for a session — the Post-UTME screening fee, the portal charge and the acceptance fee | academic, admin, bursar, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:419` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/applicant-fees` | fees | academic, admin, bursar, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:428` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/applicants` | applicants | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:99` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/applications/{id}` | application | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:200` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/applications/{id}/clearance/{item}` | clearance | academic, dregistrar, records, registrar | `admissions/ApplicantsController.java:1391` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/applications/{id}/decision` | decide | academic, dregistrar, registrar | `admissions/ApplicantsController.java:768` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/applications/{id}/documents/{documentId}/content` | content | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:480` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/applications/{id}/documents/{documentId}/review` | review | academic, dregistrar, registrar | `admissions/ApplicantsController.java:455` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/applications/{id}/screening-score` | score | academic, dregistrar, registrar | `admissions/ApplicantsController.java:518` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/attachments` | attachments | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:202` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/candidate-data` | state | academic, admin, dregistrar, ict, records, registrar, super | `admissions/CandidateDataController.java:68` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/candidate-data` | Records what was read, as it was read, then re-matches everything held. | academic, dregistrar, registrar | `admissions/CandidateDataController.java:129` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/candidate-data/passport/{candidateId}/image` | The candidate's screening passport as an image, decoded from the attachment payload — for the gallery and any &lt;img&gt;. Photographs over 64 KB were recorded by metadata only, so they have no stored image and this is a | academic, admin, dregistrar, ict, records, registrar, super | `admissions/CandidateDataController.java:99` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/candidate-data/{jambKey}/olevel` | A candidate's results as JAMB sent them, sitting by sitting, and — for the Academic Office — the score. | academic, admin, dregistrar, ict, records, registrar, super | `admissions/OlevelController.java:132` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/candidates/{jambKey}` | an admitted candidate who has not registered for Post-UTME — read from the committed CAPS list and the O'Level JAMB sent, with the O'Level score computed under the session's grading. | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:340` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/cycle` | cycle | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `admissions/AdmissionCycleController.java:30` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/decisions/release` | releaseDecisions | academic, dregistrar, registrar | `admissions/ApplicantsController.java:787` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/fee-references/{reference}/confirm` | confirm | academic, bursar, dregistrar, registrar | `admissions/ApplicantsController.java:443` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/import-applicants` | Import one chunk of paid applicants migrated from the old portal. Each row runs through admissions.import_applicant, which is idempotent — a number that already has an account is counted as 'exists', a bad row as 'skip:  | academic, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:228` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/import-applicants/link-caps` | link candidates to the authoritative JAMB CAPS row by registration number, so a migrated (or any unlinked) candidate takes its demographics/UTME/subjects from the CAPS data. Run after the CAPS list is uploaded and commit | academic, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:312` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/import-applicants/link-held` | Re-match everything held (passports, DOB, O'Level uploaded before their candidate existed) to the candidates the import created. Called once after the whole import, so the sweep runs a single time rather than on every ch | academic, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:300` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/import-applicants/reset-migrated` | Clear only the old-portal migration's records for a session — candidate, account, application — so the migration can be re-run against the CAPS list. Keeps the CAPS rows, O'Level and passports (a passport is unlinked, no | academic, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:330` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/jamb-admissions` | jambAdmissions | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:172` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/jamb-admissions` | The admission-status list downloaded from JAMB: matched by registration number; the accepted are offered and released here. | academic, registrar | `admissions/AdmissionsController.java:166` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/jamb-template` | The rows of JAMB's admission template for one programme (or all): the UTME subjects and score as CAPS sent them, the O'Level grades and points under the session's grading — English, Mathematics, then the three best relev | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:805` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/load-cutoff` | the general UTME cut-off the session loads its JAMB lists under (V024) | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `admissions/AdmissionSettingsController.java:155` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/load-cutoff` | stateLoadCutoff | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:161` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/olevel-grading` | grading | academic, admin, dregistrar, ict, records, registrar, super | `admissions/OlevelController.java:75` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/olevel-grading` | The Academic Office states the rule; every number is recorded against it. | academic, dregistrar, registrar | `admissions/OlevelController.java:83` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/policy` | The session's admission settings: the cut-offs that apply, and whether they are in force. | academic, admin, dean, dregistrar, dvc, hod, ict, records, registrar, super, vc | `admissions/AdmissionSettingsController.java:39` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy` | save | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:45` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/policy-findings` | policy | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:208` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/catchment` | the catchment local governments, for the Locality basis (V054) — replaces the set | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:142` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/criteria` | criteria | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:52` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/eligibility` | the eligibility register (V266): submitted applicants against the settings, with `q`, `fac`, `dept`, `prog`, `status`, `recommended`, `mode`, `page`, `size`; returns rows, stats, options, recommendable | academic, admin, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionEligibilityController.java:78` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/eligibility/stats` | the eligibility statistics for the session | academic, admin, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionEligibilityController.java:141` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/eligibility/{appId}` | one application's current evaluation (re-read when stale or the rules moved) — application, run, applied, alternatives, changes, events, O'Level and UTME on record; logs RECOMMENDATION_VIEWED | academic, admin, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionEligibilityController.java:149` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/eligibility/{appId}/recalculate` | re-evaluate one application (OFFICER) | academic, dregistrar, registrar, super | `admissions/AdmissionEligibilityController.java:198` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/eligibility/recalculate-all` | evaluate every submitted application, or with `onlyMissing=true` only those without a current evaluation (SYSTEM) | academic, dregistrar, registrar, super | `admissions/AdmissionEligibilityController.java:208` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/eligibility/{appId}/change` | request a change of programme on the applicant's behalf `{ programmeCode, note }` | academic, dregistrar, registrar, super | `admissions/AdmissionEligibilityController.java:229` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/eligibility/changes` | the programme-change requests, optionally `?state=` | academic, admin, bursar, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionEligibilityController.java:240` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/eligibility/changes/{id}/approve` | approve a change: eligibility re-read, programme changed, re-evaluated, applicant told `{ note }` | academic, dregistrar, registrar, super | `admissions/AdmissionEligibilityController.java:256` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/eligibility/changes/{id}/reject` | reject a change with its reason `{ note }` (required) | academic, dregistrar, registrar, super | `admissions/AdmissionEligibilityController.java:263` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/olevel-required` | the O'Level subjects the eligibility engine requires and their minimum grade `{ items, minGrade }` (V266) | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:143` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/screening` | the additional screening a programme requires beyond the academic rules `{ additionalScreening }` (V266) | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:153` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/equivalences` | the subject equivalences the engine honours `{ rows: [{ subject, equivalent, scope }] }` — replaces the set (V266) | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:163` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/faculties/{code}` | faculty | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:58` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/faculties/{code}/quota` | facultyQuota | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:85` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/nuc-quota` | nucQuota | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:79` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}` | programme | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:65` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/close` | closed for the session: not admitted into, needs no rule (V023) | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:168` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/cutoff` | a programme's own UTME cut-off, editable in force like its quota — the settings are by programme, not faculty | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:101` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/de-subjects` | a programme's required Direct Entry subjects the DE gate checks (V200), editable in force — a correction to which subjects the gate reads and how many of them a candidate must offer | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:132` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/olevel-subjects` | a programme's relevant O'Level subjects, editable in force — a correction to which subjects the screening counts, not the cut-off or weighting a candidate is ranked by | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:112` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/quota` | programmeQuota | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:91` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/reopen` | reopen | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:175` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/policy/programmes/{code}/utme-subjects` | a programme's required UTME subjects the merit list checks, editable in force — a correction to which subjects the gate reads, not the cut-off or weighting a candidate is ranked by | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:120` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/policy/put-in-force` | putInForce | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:181` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/policy/start-from/{fromSession}/{fromYear}` | startFrom | academic, dregistrar, registrar | `admissions/AdmissionSettingsController.java:188` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/post-utme-audit` | why a programme does or doesn't appear on the computed Post-UTME: per programme, whether it is exam-screened (index), and how many of its applicants are submitted and fee-confirmed. A programme is on the computed list on | academic, admin, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:161` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/post-utme-computed` | the Academic Office's computed Post-UTME for candidates who did not sit it (Direct Entry, non-exam programmes) | academic, super | `admissions/ApplicantsController.java:150` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme` | overview | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:74` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/attendance` | mark | academic, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:522` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/batches` | listBatches | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:408` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/batches/{id}` | batch | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:414` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/batches/{id}/state` | batchState | academic, dregistrar, registrar, super | `admissions/PutmeController.java:431` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/candidates` | candidates | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:323` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/candidates/{id}/confirm-schedule` | the desk confirms a seating flagged after a programme change | academic, dregistrar, registrar, super | `admissions/PutmeController.java:473` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/candidates/{id}/events` | candidateEvents | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:355` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/candidates/{id}/seatings` | seatings | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:366` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/centres` | saveCentre | academic, dregistrar, registrar, super | `admissions/PutmeController.java:208` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/centres/{centreId}/rooms` | saveRoom | academic, dregistrar, registrar, super | `admissions/PutmeController.java:225` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/checkin` | checkin | academic, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:507` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/putme/exam` | saveExam | academic, dregistrar, registrar, super | `admissions/PutmeController.java:154` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/putme/exam/centres` | examCentres | academic, dregistrar, registrar, super | `admissions/PutmeController.java:264` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/putme/exam/days` | examDays | academic, dregistrar, registrar, super | `admissions/PutmeController.java:281` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/putme/exam/slots` | examSlots | academic, dregistrar, registrar, super | `admissions/PutmeController.java:301` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/exam/state` | examState | academic, dregistrar, registrar, super | `admissions/PutmeController.java:187` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/generate` | generate | academic, dregistrar, registrar, super | `admissions/PutmeController.java:377` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/lookup` | the candidate found by the slip's QR token, the application number or the JAMB number | academic, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:488` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/move` | one candidate or many moved (or seated for the first time) into a batch: the same rule for each, the seat given in turn | academic, dregistrar, registrar, super | `admissions/PutmeController.java:446` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/publish` | publish | academic, dregistrar, registrar, super | `admissions/PutmeController.java:394` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/rooms/{roomId}/workstations` | workstations | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:242` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/putme/unschedule` | unschedule | academic, dregistrar, registrar, super | `admissions/PutmeController.java:464` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/putme/validate` | validate | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/PutmeController.java:388` |
| PUT | `/api/v1/admissions/sessions/{session}/{year}/putme/workstations/{id}` | workstation | academic, dregistrar, registrar, super | `admissions/PutmeController.java:251` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/reconciliation` | reconciliation | academic, admin, dregistrar, dvc, ict, records, registrar, super, vc | `admissions/AdmissionsController.java:196` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/reconsiderations` | non-qualified candidates who hold five O'Level credits and could be moved to an open programme, with the suggestions | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:1079` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/reconsiderations/notify` | email each movable candidate (not already told) their suggested programmes; the office triggers this | academic, dregistrar, registrar | `admissions/ApplicantsController.java:1121` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/reconsiderations/suggest` | the office chooses one programme for a movable candidate and suggests it: the candidate is emailed that programme (when an address is on file) and the choice is recorded. The programme must be one the candidate actually  | academic, dregistrar, registrar | `admissions/ApplicantsController.java:1167` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/reset-intake` | Clear a CAPS upload and start the intake again: deletes the JAMB list, candidates, O'Level and applicant intake for the session, keeps the admission config and every student on the register. | academic, registrar | `admissions/AdmissionsController.java:94` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/screened` | the screened candidates of one programme — the same population the overview counts: committed CAPS rows that carry a UTME aggregate. The criteria known at this stage: the UTME aggregate against the programme cut-off, the | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:1252` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/screened-summary` | the screened pool counted per programme — applied, screened (an aggregate on the CAPS row), quota and cut-off. One cheap query behind the Screened overview; the per-applicant criteria come from /jamb-template?programme=. | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:1227` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/screening-batches` | screeningBatches | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:491` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-batches` | newBatch | academic, dregistrar, registrar | `admissions/ApplicantsController.java:497` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-batches/{id}/assign` | assign | academic, dregistrar, registrar | `admissions/ApplicantsController.java:510` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/screening-batches/{id}/hall-list` | the hall list of one batch: every seat in order, with the photograph on file, for the invigilator at the door | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:1372` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/screening-register` | the whole screening register: every submitted candidate, the mark they were screened by and its source | academic, admin, bursar, dregistrar, ict, records, registrar, super | `admissions/ApplicantsController.java:184` |
| GET | `/api/v1/admissions/sessions/{session}/{year}/screening-scores/awaiting` | the applicants of an exam-screened programme whose Post-UTME score is still awaited — submitted, no score entered — so the office can see (and download) exactly who is missing a score. | academic, admin, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:540` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-scores/clear` | Clear uploaded Post-UTME scores for a session (optionally one programme) — for when scores were uploaded in error, so the register falls back to the O'Level+UTME computation. Nulls the score, its entry and its release. G | academic, dregistrar, registrar | `admissions/ApplicantsController.java:743` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-scores/from-olevel` | Enter the computed O'Level figure as the Post-UTME (screening) score for NON-index programmes, so those applicants (who never sit the Post-UTME) get a screening figure and enter the merit list. The figure is the session' | academic, admin, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:599` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-scores/release` | releaseScores | academic, dregistrar, registrar | `admissions/ApplicantsController.java:729` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-scores/upload` | A batch of Post-UTME scores, each keyed by JAMB registration number or application number, reconciled against the session's applicants: a matched candidate whose score is not yet released has it entered; the rest are rep | academic, admin, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:658` |
| POST | `/api/v1/admissions/sessions/{session}/{year}/screening-scores/zero-missing` | Score the remaining applicants who have no Post-UTME score as zero — the deliberate finalising step for the stragglers who never sat / whose score never came, so they are decided (not left in limbo). Only submitted, exam | academic, admin, dregistrar, ict, registrar, super | `admissions/ApplicantsController.java:563` |

### Wallet (`wallet`, 18 endpoints)

The student wallet and NELFUND (student loans): the student's balance, application, top-up reference and withdrawal request; the Bursary's NELFUND batches, matching, reversal, status, hand credits and resets; funding sources and the session's funding report. Bursar, System Administrator and Super Administrator act; the Registry and audit read.

| Method | Endpoint | Purpose | Who may call | Source |
|---|---|---|---|---|
| GET | `/api/v1/funding/sessions/{s}/{y}/report` | report | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `wallet/WalletController.java:169` |
| GET | `/api/v1/funding/sources` | sources | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `wallet/WalletController.java:157` |
| POST | `/api/v1/funding/sources` | upsertSource | admin, bursar, super | `wallet/WalletController.java:163` |
| POST | `/api/v1/funding/withdrawals/{id}/approve` | approveWithdrawal | admin, bursar, super | `wallet/WalletController.java:175` |
| POST | `/api/v1/funding/withdrawals/{id}/pay` | payWithdrawal | admin, bursar, super | `wallet/WalletController.java:187` |
| POST | `/api/v1/funding/withdrawals/{id}/reject` | rejectWithdrawal | admin, bursar, super | `wallet/WalletController.java:181` |
| GET | `/api/v1/me/wallet` | mine | student | `wallet/WalletController.java:75` |
| POST | `/api/v1/me/wallet/apply` | apply | student | `wallet/WalletController.java:81` |
| POST | `/api/v1/me/wallet/topup-reference` | topup | student | `wallet/WalletController.java:87` |
| POST | `/api/v1/me/wallet/withdrawal` | the student asks to withdraw the wallet balance to their own bank account (fees must be cleared) | student | `wallet/WalletController.java:94` |
| POST | `/api/v1/nelfund/batches` | load | admin, bursar, super | `wallet/WalletController.java:117` |
| POST | `/api/v1/nelfund/credit` | the Bursary credits a student's wallet by hand — a scholarship, a sponsor's off-gateway payment, a correction | admin, bursar, super | `wallet/WalletController.java:136` |
| POST | `/api/v1/nelfund/reset` | the Bursary wipes one student's wallet to zero — every entry and withdrawal — to start afresh | admin, bursar, super | `wallet/WalletController.java:149` |
| POST | `/api/v1/nelfund/rows/{id}/match` | match | academic, bursar, dregistrar, registrar, super | `wallet/WalletController.java:123` |
| POST | `/api/v1/nelfund/rows/{id}/reverse` | reverse | admin, bursar, super | `wallet/WalletController.java:129` |
| GET | `/api/v1/nelfund/sessions/{s}/{y}` | desk | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `wallet/WalletController.java:102` |
| POST | `/api/v1/nelfund/status` | status | admin, bursar, super | `wallet/WalletController.java:142` |
| GET | `/api/v1/nelfund/student/statement` | a student's wallet ledger, by matriculation or admission number — the Bursary's and the audit directorate's read. The number is a query parameter, not a path segment: a matriculation number carries slashes, and an encode | academic, admin, audit, bursar, deputyaudit, dregistrar, dvc, ict, registrar, super, vc | `wallet/WalletController.java:111` |

## 4 Endpoints without a screen

The endpoints below exist in the API, are guarded and work, but **no page in `frontend/src` calls them** (established by the audit dossiers and re-checked against the frontend source for this volume). Each is **PARTIALLY IMPLEMENTED (backend only)**: the rule is enforced and the data is written, but the desk that should use it has no button. They can be exercised with curl (§5) by an office the guard names.

| Module | Endpoint | Who may call | What it does | Source / dossier |
|---|---|---|---|---|
| Authentication | `GET /api/v1/auth/sessions` | any signed-in token (own sessions) | the caller's live sessions: `[{ id, activeOffice, issuedAt, lastSeenAt, absoluteEnd }]` | `auth/AuthController.java:101`; dossier A §A1 |
| Authentication | `POST /api/v1/auth/sessions/{id}/end` | any signed-in token (own sessions) | ends one of the caller's sessions by its hex id; answers `{ "ended": "<id>" }` | `auth/AuthController.java:106`; dossier A |
| Undergraduate admissions | `POST /api/v1/admissions/sessions/{s}/{y}/applications/{id}/documents/{documentId}/review` | Academic Officer, Deputy Registrar (Academic Affairs), Registrar | records an officer's `ACCEPTED`/`REJECTED` review of an applicant's uploaded document | `admissions/ApplicantsController.java:455`; dossier B |
| Undergraduate admissions | `PUT /api/v1/admissions/sessions/{s}/{y}/applications/{id}/clearance/{item}` | Academic Officer, Deputy Registrar (Academic Affairs), Exams and Records, Registrar | records the Registry's clearance of one checklist item; the applicant's own clearance view reads it, but stage 7 of the admissions flow cannot be reached from a screen | `ApplicantsController.java:1391`; dossier B |
| Undergraduate admissions | `POST /api/v1/admissions/sessions/{s}/{y}/fee-references/{reference}/confirm` | Academic Officer, Bursar, Deputy Registrar (Academic Affairs), Registrar | confirms an applicant's fee reference by hand; the live path is the gateway webhook and the desk note says "there is no confirmation step here" | `ApplicantsController.java:443`; dossier B |
| Undergraduate admissions | `POST /api/v1/admissions/sessions/{s}/{y}/reconsiderations/notify` | Academic Officer, Deputy Registrar (Academic Affairs), Registrar | emails every movable candidate not already told their suggested programmes; the Reconsiderations screen has *Suggest* but no *Notify all* button | `ApplicantsController.java:1121`; dossier B |
| Undergraduate admissions | `POST /api/v1/applicant/me/documents` (applicant document upload, five kinds) | Applicant | stores a base64 document against the application; no upload control exists in the applicant screens | `applicant/ApplicantController.java:108`; dossier B |
| External examiners | `GET /api/v1/examiners/moderation?session=&dept=` | Academic Officer, System Administrator, Dean, Deputy Registrar (Academic Affairs), Examinations Officer, Head of Department, Dean and Secretary of the Postgraduate School, Registrar, Super Administrator | the moderation feed: every submitted or locked external assessment in a department for a session, its average percentage, beside the internal course total | `examiners/ExaminersController.java:881`; dossier C |
| Course registration | `POST /api/v1/registration/course-registrations` (create/submit for a student) | Academic Officer, Deputy Registrar (Academic Affairs), Head of Department, Lecturer, Registrar, Super Administrator | an office creates a registration for a student; entries are inserted as given without the menu's validation | `registration/RegistrationController.java`; dossier D |
| Course registration | `PUT /api/v1/registration/courses/{code}`, `POST …/courses/{code}/end`, `PUT …/courses/{code}/offers/{programme}/{level}`, `PUT /api/v1/registration/offerings` | Academic Officer, Deputy Registrar (Academic Affairs), Head of Department, Registrar, Super Administrator | direct upserts of a course, an offer and an offering; the catalogue and allocation screens use the `catalogue` and `allocation` modules instead | `RegistrationController.java:40-62`; dossier D |
| Transfers | `POST /api/v1/transfers/{id}/review`, `…/senate`, `…/withdraw`, `…/effect` | review: Academic Officer, Deputy Registrar (Academic Affairs), DVC (Academic), Registrar, Super Administrator; senate: Deputy Registrar, DVC, Registrar, Super Administrator, Vice-Chancellor; withdraw: Academic Officer, Deputy Registrar, Registrar, Super Administrator; effect: those plus Director of ICT | the committee (SAIC) path of a transfer: `APPLIED → RECOMMENDED / NOT_RECOMMENDED → APPROVED / DECLINED → EFFECTED`, or `WITHDRAWN`; the memo page reports on these states but nothing drives them | `transfers/TransferController.java:263-294`; dossier D |
| Matriculation | `GET /api/v1/matriculation/config/preview/{studentId}` | the matriculation readers | the number one student would receive next (`people.matric_preview`) | `matriculation/MatricFormatController.java:142`; dossier D |
| Matriculation | `GET /api/v1/matriculation/config/history?q=` | the matriculation readers | the last 500 issues with their components and run reference, searchable; the screen shows only the 25 most recent from `GET /config` | `MatricFormatController.java:148`; dossier D |
| Student portal | `GET /api/v1/me/transcripts`, `POST /api/v1/me/transcripts` | Student | the legacy (V027) transcript request; superseded by `/api/v1/me/documents/requests` and its screen is no longer routed — **CONFIGURED BUT UNUSED** | `studentportal/MeController.java:155-160`; dossier D |
| College of Health Sciences | `GET /api/v1/provost/dashboard` | Provost, College Secretary, Finance Controller, Super Administrator | the Provost's figures (students, registration by department, sheet pipeline, offerings without a lecturer, probation and at-risk list); the Provost's home uses `GET /api/v1/college/dashboard` instead — **CONFIGURED BUT UNUSED** | `provost/ProvostController.java:64`; dossier E |
| Hostel | `POST /api/v1/hostel/lapse-all` | System Administrator, Deputy Registrar (Housing, Welfare, Passages), Registrar, Support Services, Super Administrator | lapses every expired unpaid hold at once — what the hourly hostel clock does on its own | `hostel/HostelLifecycleController.java:844`; dossier G |
| Clearance | `POST /api/v1/clearance/notify-held` | the clearing offices | counts, but does not send, a notice to students held at clearance ("No notification module yet") — **PLACEHOLDER** | `clearance/ClearanceController.java:73` |

Two candidates named by the dossiers turned out to have callers when the frontend was re-read for this volume, and are **not** listed above: `POST /api/v1/student/intake/{session}/{year}` (the intake run) is called by the *Admissions* page (`frontend/src/app/admissions/Admissions.tsx:49`), and `GET/POST /api/v1/research/grants` and `POST …/{id}/state` are read and written by *Research › My Projects* (`/research/projects`, in the Lecturer's, Dean's and Vice-Chancellor's menus). The dossiers D and F should be read with that correction; see *09 Feature Status Report*.

> **Planned / Not Yet Implemented:** API-key authentication (§5.4), platform idempotency (§1.11), and a problem body on `403` from `@PreAuthorize` are not implemented; none is on a timeline in the repository.

---

## 5 Integration notes

### 5.1 Minting a development token

In shared-secret mode (`MOAUM_AUTH_HMAC_SECRET` set), a token can be minted without any account or identity provider, exactly as `api/README.md` describes. `api/scripts/dev-token.mjs` has no dependencies beyond Node:

```text
node api/scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" --offices academic,registrar
node api/scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" --sub <person uuid> --offices ict --ttl 3600
```

| Option | Meaning |
|---|---|
| `--secret` | the API's secret (or set `MOAUM_AUTH_HMAC_SECRET` in the environment); at least 32 bytes or the script exits 2 |
| `--sub` | the subject UUID; a random one when omitted (then `/iam/me` has no `name`, and a write is attributed to a person id that exists in no table) |
| `--offices` | comma-separated office codes (default `academic`) |
| `--ttl` | seconds until expiry (default 3600) |

The token is printed to stdout; the subject, offices and lifetime go to stderr, so `TOKEN=$(node …)` captures only the token. A minted token has `sub`, `iat`, `exp` and `offices` — and **no `sid`**, so the session guard does not apply to it: it survives a deploy and cannot be ended, which is why it is for development and CI only. In production `MOAUM_AUTH_ISSUER_URI` would point at Keycloak and the secret would be unset; today the deployed API runs in shared-secret mode and sign-in mints tokens with a `sid`.

The frontend can be pointed at a minted token without signing in: set `PORTAL_API_TOKEN` and `PORTAL_ACTIVE_OFFICE` in the frontend's environment (read only when `NODE_ENV` is not `production`).

### 5.2 Calling the API with curl

Directly against the API (port 8081 locally; the `moaum-api` service in production):

```text
# public
curl -s http://localhost:8081/api/v1/platform/status

# with a token and an acting office
TOKEN=$(node api/scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" --offices academic,registrar)
curl -s -H "Authorization: Bearer $TOKEN" -H "X-Active-Office: academic" \
     http://localhost:8081/api/v1/iam/me

# a write: JSON body, a reason, a correlation id of your own
curl -s -X PUT http://localhost:8081/api/v1/matriculation/config/series/GENERAL \
     -H "Authorization: Bearer $TOKEN" -H "X-Active-Office: registrar" \
     -H "Content-Type: application/json" \
     -H "X-Reason: Series moved forward per Registry schedule of 12/09/2026" \
     -H "X-Correlation-Id: 0b6b6f6a-1c2d-4e3f-8a9b-0c1d2e3f4a5b" \
     -d '{"name":"General series","lastIssued":85631,"active":true}'

# a signed-in session instead of a minted token
curl -s -X POST http://localhost:8081/api/v1/auth/sign-in -H "Content-Type: application/json" \
     -d '{"username":"<staff number or email>","password":"<password>","office":"academic"}'
```

Through the portal origin (as the browser does): sign in at `/api/auth/sign-in` to obtain the `moaum_session` and `moaum_office` cookies, then call `/api/bff/api/v1/...` with the cookie jar. Remember that the BFF forwards only the six headers of §1.2.

```text
curl -s -c jar.txt -X POST https://<portal host>/api/auth/sign-in -H "Content-Type: application/json" \
     -d '{"identifier":"<staff number>","password":"<password>"}'
curl -s -b jar.txt -H "X-Active-Office: academic" https://<portal host>/api/bff/api/v1/iam/me
```

Rules of the road: always send `X-Active-Office` when the token holds more than one office; always send `X-Reason` on a write; read `X-Correlation-Id` off every response and keep it with your logs; never put a token, a matriculation number or any personal identifier in a URL you will log — the few endpoints that take a number as a query parameter (`/api/v1/nelfund/student/statement`, the `/verify/*` doors) are the exception, and they are designed for it.

### 5.3 Reading a problem response

A refusal is `application/problem+json` (§1.7). A client should:

1. Branch on the HTTP status first: `400` fix the request (read `violations`); `401` sign in again (the session may have been ended by a deploy); `403` switch office or ask for the office (`NO_ACTING_OFFICE` means the header was missing); `404` the id or the path is wrong, or the resource is not the caller's; `409` it already exists or a referenced row is missing; `422` a rule refused it — show `title`, `detail` and `remedy` to the person.
2. Branch on `code` for behaviour: `code` is stable across releases and wording changes; `title` and `detail` are for people.
3. Show `remedy.message` and, where present, `remedy.office`: every blocking condition names the desk that can lift it.
4. Log `correlationId` and quote it when escalating.
5. Expect **no body** on a bare `401`/`403` from the security layer and build your own words, as `frontend/src/lib/api.ts` does in `fallbackProblem()`.

The frontend's `Problem` type (`frontend/src/lib/api.ts`) is the shape to code against:

```text
interface Problem {
  type?: string; title?: string; status: number; detail?: string; instance?: string;
  code?: string; correlationId?: string;
  remedy?: { message: string; office: string };
  violations?: { field: string; code: string; message: string }[];
}
```

### 5.4 The API key register

The **Integrations** screen (`/api-keys`) and the `apimgmt` endpoints (`GET/POST /api/v1/apimgmt/consumers`, `POST …/consumers/{id}/keys`, `POST …/consumers/{id}/deprecate`, `POST /api/v1/apimgmt/keys/{id}/revoke`; Director of ICT, System Administrator, Super Administrator) register external consumers — name, owner, space-separated scopes, an optional daily quota — and issue them hashed keys that expire within a year and are shown once. That is all they do today.

**Keys are not accepted for authentication.** The security chain accepts bearer JWTs alone; no filter reads an `X-Api-Key` header and no Java code reads `apimgmt.key` (dossier A, §A6). Scopes and quotas are stored but never enforced, and the screen's words "rate-limited" describe an intent, not a mechanism. Status: register **IMPLEMENTED**; API-key authentication, scopes and quotas **NOT IMPLEMENTED**. An external system that must call the API today needs a person with an office and a token from a sign-in (or, in development, a minted token), and its calls are attributed to that person and office.

### 5.5 Demo accounts

`docs/demo-accounts.md` lists invented people — every surname DEMO, staff numbers `MOAUM/DEMO/nnn`, matriculation numbers in a range a real run never reaches — that `bash db/demo.sh` puts on a database, one per office, all with the same published password. They sign in at the one door (`/login`) and exercise every desk described in this volume without touching a real record. The password is printed in that file and is not repeated here.
