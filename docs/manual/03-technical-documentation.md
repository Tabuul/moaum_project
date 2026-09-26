# MOAUM Unified University Portal — 03 Technical Documentation

Rev. Fr. Moses Orshio Adasu University, Makurdi · Directorate of ICT

**Audience:** developers, DevOps engineers, database administrators and the ICT Directorate.
**Scope:** the system as it is in the repository `moaumpp` at migration V263. Every claim below was checked against the source files named beside it. Where a claim could not be confirmed it is marked *not verified*. Nothing in this volume describes an intended design as if it were built.

**Companion volumes:** *01 User Manual*, *02 Administrator Manual*, *04 Role & Permission Matrix*, *05 Module Navigation Guide*, *06 Workflows*, *07 API Reference*, *08 Database Reference*, *09 Feature Status Report*, *README* (package index and glossary).

---

## Table of contents

1. [System overview and architecture](#1-system-overview-and-architecture)
   1.1 [The deployables](#11-the-deployables)
   1.2 [Architecture diagram](#12-architecture-diagram)
   1.3 [The request path in one paragraph](#13-the-request-path-in-one-paragraph)
   1.4 [Spring Modulith module boundaries](#14-spring-modulith-module-boundaries)
   1.5 [Technology inventory](#15-technology-inventory)
2. [Backend developer guide](#2-backend-developer-guide)
   2.1 [Project layout](#21-project-layout)
   2.2 [Conventions](#22-conventions)
   2.3 [How a request flows](#23-how-a-request-flows)
   2.4 [Adding an endpoint, a migration and a screen](#24-adding-an-endpoint-a-migration-and-a-screen)
   2.5 [Testing](#25-testing)
   2.6 [Scheduled jobs](#26-scheduled-jobs)
   2.7 [File and document handling](#27-file-and-document-handling)
   2.8 [PDF generation](#28-pdf-generation)
   2.9 [Excel and print exports](#29-excel-and-print-exports)
   2.10 [Notifications](#210-notifications)
   2.11 [Error handling and problem details](#211-error-handling-and-problem-details)
   2.12 [Logging and the correlation id](#212-logging-and-the-correlation-id)
   2.13 [Health endpoints](#213-health-endpoints)
3. [Frontend developer guide](#3-frontend-developer-guide)
   3.1 [App Router layout](#31-app-router-layout)
   3.2 [Server pages and client screens](#32-server-pages-and-client-screens)
   3.3 [The design kit](#33-the-design-kit)
   3.4 [Menus, routes and titles](#34-menus-routes-and-titles)
   3.5 [Navigation, toasts and the reason header](#35-navigation-toasts-and-the-reason-header)
   3.6 [Lint rules that CI enforces](#36-lint-rules-that-ci-enforces)
   3.7 [The proxy and its OPEN list](#37-the-proxy-and-its-open-list)
   3.8 [Sign-in handlers per identity](#38-sign-in-handlers-per-identity)
   3.9 [Cookies](#39-cookies)
   3.10 [Fonts](#310-fonts)
4. [Design system](#4-design-system)
   4.1 [Visual philosophy](#41-visual-philosophy)
   4.2 [Colour tokens](#42-colour-tokens)
   4.3 [Typography](#43-typography)
   4.4 [Spacing, radius and shadow](#44-spacing-radius-and-shadow)
   4.5 [Buttons](#45-buttons)
   4.6 [Cards, panels and tiles](#46-cards-panels-and-tiles)
   4.7 [Tables and DTable behaviour](#47-tables-and-dtable-behaviour)
   4.8 [Forms](#48-forms)
   4.9 [Modals](#49-modals)
   4.10 [Pills and notes](#410-pills-and-notes)
   4.11 [Icons](#411-icons)
   4.12 [Navigation: sidebar and top bar](#412-navigation-sidebar-and-top-bar)
   4.13 [Responsive breakpoints](#413-responsive-breakpoints)
   4.14 [Print styles and documents](#414-print-styles-and-documents)
   4.15 [Charts](#415-charts)
5. [Security](#5-security)
   5.1 [Authentication](#51-authentication)
   5.2 [Authorisation](#52-authorisation)
   5.3 [CSRF](#53-csrf)
   5.4 [Cross-site scripting](#54-cross-site-scripting)
   5.5 [SQL injection](#55-sql-injection)
   5.6 [File upload validation](#56-file-upload-validation)
   5.7 [Object-level access (IDOR)](#57-object-level-access-idor)
   5.8 [Rate limiting](#58-rate-limiting)
   5.9 [Audit logging](#59-audit-logging)
   5.10 [Data privacy](#510-data-privacy)
   5.11 [Document security](#511-document-security)
   5.12 [Secrets handling](#512-secrets-handling)
   5.13 [HTTP response headers](#513-http-response-headers)
   5.14 [Security gaps](#514-security-gaps)
6. [Configuration and environment](#6-configuration-and-environment)
   6.1 [API service variables](#61-api-service-variables)
   6.2 [Frontend service variables](#62-frontend-service-variables)
   6.3 [Prototype service variables](#63-prototype-service-variables)
   6.4 [Railway services](#64-railway-services)
   6.5 [Ports, health checks and the database pool](#65-ports-health-checks-and-the-database-pool)
7. [Deployment and CI/CD](#7-deployment-and-cicd)
   7.1 [The CI gates](#71-the-ci-gates)
   7.2 [Deploy on green](#72-deploy-on-green)
   7.3 [The migration ledger](#73-the-migration-ledger)
   7.4 [Rollback reality](#74-rollback-reality)
   7.5 [Local development setup](#75-local-development-setup)
8. [Database architecture summary](#8-database-architecture-summary)
9. [API architecture summary](#9-api-architecture-summary)
10. [Integrations](#10-integrations)
    10.1 [Payment gateways](#101-payment-gateways)
    10.2 [Email and SMS](#102-email-and-sms)
    10.3 [Keycloak single sign-on](#103-keycloak-single-sign-on)
    10.4 [JAMB and CAPS files](#104-jamb-and-caps-files)
    10.5 [PayDirect](#105-paydirect)
    10.6 [NELFUND files](#106-nelfund-files)
    10.7 [Legacy portal import](#107-legacy-portal-import)
11. [Known technical debt and stale surfaces](#11-known-technical-debt-and-stale-surfaces)

---

## 1 System overview and architecture

### 1.1 The deployables

The repository builds three services and expects one PostgreSQL database.

| Deployable | Directory | Runtime | Image | Purpose | Status |
|---|---|---|---|---|---|
| **Prototype** | `proto/` (56 HTML parts), `public/index.html` (the built page), `web/server.js` | Node 22, no dependencies | root `Dockerfile` (node:22-slim + `postgresql-client`) | The original single-file HTML prototype and a tiny static server with `/healthz` and `/readyz`. Kept as the reference design; the harnesses in CI still run against it. It no longer migrates the database. | IMPLEMENTED, legacy |
| **API** | `api/` | Java 21, Spring Boot 4.1.1, Spring Modulith 2.1.1, plain JDBC (`JdbcClient`) | `api/Dockerfile` (Temurin 21 JDK build stage → Temurin 21 JRE runtime + `postgresql-client`) | The whole business surface: 918 endpoints under `/api/v1` (per the generated reference), method security by office, the audit context on every transaction, the notice dispatcher and five other scheduled jobs. **Owns the schema**: its Railway pre-deploy command runs `bash db/migrate.sh`. | IMPLEMENTED |
| **Frontend** | `frontend/` | Node 22, Next.js 16.3.4 (App Router, `output: "standalone"`), React 19.2.8 | `frontend/Dockerfile` (node:22-alpine, runs `server.js` as user `portal`) | The portal people use. Server components call the API with the session token; a backend-for-frontend route (`/api/bff/[...path]`) forwards client calls; a proxy gate keeps every screen behind a session. Generates PDFs and Excel workbooks in route handlers. | IMPLEMENTED |
| **PostgreSQL** | `db/` (V001–V263, `verify.sql`, `check.sql`, `migrate.sh`, `demo.sql`, `demo.sh`) | Postgres 17 in CI; Railway's Postgres in production | Railway-managed | 331 tables in 26 schemas, 261 migration files, the audit spine, business rules as SQL functions and triggers. | IMPLEMENTED |

The prototype is not part of the portal's request path. Its only production role is a health endpoint and a reference page; README still calls it "the HTML prototype, until the frontend covers its screens", which is now historical (see §11).

### 1.2 Architecture diagram

```text
 User
  │
  ▼
 Browser ──── cookies: moaum_session (httpOnly, SameSite=Lax, Secure in production)
  │                    moaum_office  (readable by the page; the acting office)
  │
  ▼
 Next.js frontend (moaum-portal, :3000)
  ├─ proxy.ts ........... every request except the OPEN list needs moaum_session;
  │                       page navigations are checked against GET /api/v1/iam/me;
  │                       a 401 clears both cookies and redirects to /login?next=…
  ├─ server components .. call api() (lib/api.ts) on the server with
  │                       Authorization: Bearer <cookie>, X-Active-Office, X-Reason
  ├─ /api/bff/[...path] . forwards browser calls to the API; adds the Bearer token
  │                       and the office; forwards only content-type, accept,
  │                       x-correlation-id, x-active-office, x-reason, idempotency-key
  ├─ /api/auth/* ........ sign-in doors, bootstrap, forgot/reset, sign-out, SSO
  └─ route handlers ..... PDFs (pdf-write), workbooks (xlsx-write), emailed returns
  │
  │  private network (Railway): http://moaum-api.railway.internal:8081
  ▼
 Spring Boot API (moaum-api, :8081)
  ├─ CorrelationIdFilter ....... X-Correlation-Id accepted/echoed/generated; MDC
  ├─ BearerTokenAuthenticationFilter (Spring Security) ... HS256 JWT by shared
  │                              secret, or RS256 by issuer URI; offices claim →
  │                              OFFICE_<code> authorities
  ├─ AuditContextFilter ........ subject must be a UUID; sid → SessionGuard
  │                              (ended / expired / pre-deploy floor); X-Active-Office
  │                              must be an office the token carries → AuditContext
  ├─ @PreAuthorize guards ...... hasAnyAuthority('OFFICE_…') on every controller
  ├─ OfficeScope ............... department/faculty offices held to their unit
  ├─ services / repositories ... JdbcClient, records as DTOs
  ├─ AttributedTransactionManager  set_config('moaum.actor_id' | 'actor_office' |
  │                              'reason' | 'correlation_id' | 'source_ip', …, true)
  │                              on every transaction
  ├─ ProblemHandler ............ RFC 9457 problems; SQLSTATE → status/code
  └─ @Scheduled jobs ........... NoticeDispatcher, DefermentClock, ExaminerReminders,
                                 AutoCloser, HostelClock, payments sweep
  │
  ▼
 PostgreSQL (Postgres schemas: iam, platform, audit, people, admissions, finance, …)
  ├─ business rules as functions (e.g. admissions.register_applicant,
  │  finance.confirm_payment, assessment.advance, platform.queue_notice)
  ├─ triggers (audit.record on every attached table; deferment gates; guards)
  └─ audit spine: audit.entries (monthly partitions × 16 hash-chained shards),
     refuses any write without moaum.actor_id / moaum.actor_office

 External systems (all optional; each is off until configured)
  ├─ SMTP (Microsoft 365 defaults) ─ eBulkSMS ─ generic / Termii / Resend HTTP relays
  ├─ Paystack ─ Flutterwave ─ Quickteller (Interswitch) ─ PayDirect query API
  └─ Keycloak (OpenID Connect, RS256, MFA) — coded, NOT deployed
```

### 1.3 The request path in one paragraph

A person signs in at the one door (`/login`). The frontend's sign-in handler works out from the shape of the identifier which API door to call, receives a JWT bound to a server-side session row, and stores it in the `moaum_session` cookie the browser cannot read. From then on every page render and every browser call reaches the API with `Authorization: Bearer`, `X-Active-Office` (from the `moaum_office` cookie) and, on writes, `X-Reason`. The API turns the token into `OFFICE_<code>` authorities and an `AuditContext`; the transaction manager places that context on the database transaction as transaction-local settings; the audit trigger reads them back and refuses any write to an attached table when they are absent. Every refusal comes back as an RFC 9457 problem with a stable code, the correlation id and, where somebody can act on it, a remedy naming the office.

### 1.4 Spring Modulith module boundaries

The API is one Spring Boot application whose top-level packages under `ng.edu.moaum.portal` are Spring Modulith application modules. There are 48 packages: `shared` (the OPEN kernel) and 47 modules. Forty of them declare `@ApplicationModule` in a `package-info.java` with a display name; the other eight (`dean`, `deferments`, `hod`, `pgadmissions`, `provost`, `siwes`, `stats`, `verify`) are picked up implicitly as direct sub-packages of the application class.

| Package | Display name (from `package-info.java`) | What it owns |
|---|---|---|
| `shared` | (OPEN kernel) | `AuditContext`, `AuditContextHolder`, `DomainRuleViolation`, `NotFound`, `OfficeScope`. The only package every other module may import. |
| `platform` | Platform | The request path: `SecurityConfig`, `CorrelationIdFilter`, `AuditContextFilter`, `SessionGuard`, `AttributedTransactionManager`, `PlatformConfig`, `DatabaseUrlConfig`, `ProblemHandler`, `SqlArrayJson`; `/api/v1/platform/*` (status, migrations, readiness, reset actions); the notice outbox (`NoticeRepository`, `NoticeDispatcher`, `SmtpMailer`, `EbulkSmsSender`, `MailService`, `SmsService`, their controllers, `MeNoticesController`). |
| `auth` | Authentication | Staff sign-in, sessions, bootstrap, forgot/reset (`PasswordResetService`), SSO (`SsoService`, `OidcVerifier`), `TokenIssuer`. |
| `iam` | IAM | Persons, credentials, office assignments (grants under an instrument), `GET /iam/me` with the waiting counts, lecturer and non-academic staff loaders. |
| `admissions` | Admissions | CAPS intake, candidate data, admission policy, screening, merit, decisions, Post-UTME CBT scheduling, migration of old-portal applicants. |
| `applicant` | Applicant | The applicant's own side: lookup, register, sign-in, fee, form, documents, slip, decision, acceptance, clearance. |
| `pgadmissions` | (implicit) | Postgraduate applications, PG portal, coursework, research lifecycle, PG calendar and fees. |
| `examiners` | External examiners | Appointments, invitations, activation, assignments, assessments, reminders. |
| `calendar` | Calendar | Sessions, semesters, level unit limits, roll-over, enrol-all. |
| `ref` | Reference | Colleges, faculties, departments, programmes, sessions, courses; pruned to the caller's scope. |
| `catalogue` | Course catalogue | Courses, structure uploads (ICT), curriculum tags, eligibility. |
| `registration` | Registration | Offerings and course registrations; the HOD desk. |
| `allocation` | Teaching allocation | Lecturer and second-examiner assignment per offering. |
| `results` | Results | Score sheets and the approval chain, examination sessions, held scripts, result queries, legacy result import. |
| `cbt` | CBT | The question bank (no test engine). |
| `college` | College | College of Health Sciences: MBBS years, professional examinations, postings, logbooks, attendance. |
| `student` | Student | The register, the 360 record, biodata, search (logged), status changes, intake. |
| `studentportal` | Student portal | Student sign-in and everything under `/me/*`. |
| `matriculation` | Matriculation | Faculty lists, queries, the run, the number format (V263). |
| `deferments` | (implicit) | Deferment requests, desks, the morning clock. |
| `transfers` | Transfers | Inter-departmental transfer pipeline and memos. |
| `clearance` | Clearance | Unit sign-offs and holds. |
| `graduation` | Graduation | Degree audit, classification, Senate list. |
| `alumni` | Alumni | Read-only register of graduands. |
| `credentials` | Credentials | Digital documents (V262), transcripts, certificates, stationery, identity cards, public document verification. |
| `verify` | (implicit) | Public verification of receipts, exam cards, registration forms, results, kept returns, Post-UTME slips, hostel allocations. |
| `finance` | Finance | Fee schedules, clearance scheme, references, confirmations, receipts, day book, bank credits, refunds. |
| `payments` | Payments | Gateway checkouts, webhooks, verification, sweep, gateway keys, PayDirect. |
| `wallet` | NELFUND wallet | Remittances, wallet ledger, decision lists, funding report. |
| `expenditure` | Payment vouchers | Vouchers, requisitions, stores, assets, research grants. |
| `hrm` | Payroll | Salary structure, establishment, pay runs, payslips, leave. |
| `staff` | Staff | `GET /staff/me`, profile, photo, College tier. |
| `hod`, `dean`, `provost`, `siwes` | (implicit) | Office dashboards and desks for the Head of Department, Dean, Provost and SIWES Coordinator. |
| `lms` | Course spaces | Materials, assignments, submissions, gradebook promotion into CA. |
| `library` | Library | Catalogue, loans, fines, reservations, patron standing. |
| `hostel` | Hostel | Inventory, windows, applications, holds, allocations, stays, clearance, the hourly clock. |
| `health` | Health | Clinic appointments, visits, fitness status, access log. |
| `helpdesk` | ICT support tickets | Tickets, agents, SLAs, public tracking, auto-close. |
| `support` | Help and requests | Student service requests to offices. |
| `reporting` | Reporting | The institutional overview read model. |
| `reports` | Reports | Returns, due register, kept copies (snapshots), registers. |
| `stats` | (implicit) | Student statistics (V257). |
| `auditlog` | Audit trail | Read over `audit.entries` and sign-in events. |
| `governance` | Governance | NDPA register, DSR log, DR drills, security posture. |
| `apimgmt` | API management | Consumers and hashed keys (register only; nothing authenticates by key). |

**The boundary test.** `ModularityTests.moduleBoundariesHold()` (`api/src/test/java/ng/edu/moaum/portal/ModularityTests.java`) calls `ApplicationModules.of(PortalApiApplication.class).verify()`. A module that imports another module's non-public type fails the build, not a code review. The test needs neither a Spring context nor a database and runs in every `./mvnw verify`. The convention the modules follow to stay inside the rule is stated in several `package-info` files: a module that needs another's data reads the tables through its own SQL rather than importing the other module's types (for example `hrm`, `staff` and `transfers`).

### 1.5 Technology inventory

| Layer | Component | Version / detail | Source |
|---|---|---|---|
| API | Spring Boot | 4.1.1 (parent POM) | `api/pom.xml` |
| API | Spring Modulith | 2.1.1 (`spring-modulith-starter-core`, `-actuator`, `-starter-test`) | `api/pom.xml` |
| API | Java | 21 | `api/pom.xml`, `api/Dockerfile` |
| API | Starters | actuator, jdbc, mail, security, oauth2-resource-server, validation, webmvc | `api/pom.xml` |
| API | PostgreSQL JDBC driver | compile scope (the problem handler reads the server HINT off `PSQLException`) | `api/pom.xml` |
| API | Apache PDFBox | 3.0.3 — merges an applicant's uploaded documents into one PDF for the School | `api/pom.xml` |
| API | Nimbus JOSE | transitively through Spring Security; used directly by `TokenIssuer` and `TestTokens` | `auth/TokenIssuer.java` |
| API | Password hashing | `BCryptPasswordEncoder(12)` in every door; database CHECKs demand `$2…$12$` | §5.1 |
| API | Build | Maven wrapper; `maven-failsafe-plugin` runs `*IT` classes in `verify` | `api/pom.xml` |
| Frontend | Next.js | 16.3.4, App Router, `output: "standalone"` | `frontend/package.json`, `next.config.ts` |
| Frontend | React | 19.2.8 | `frontend/package.json` |
| Frontend | TypeScript | ^5; ESLint ^9 with `eslint-config-next` (core-web-vitals + typescript) | `frontend/package.json`, `eslint.config.mjs` |
| Frontend | Tailwind CSS | ^4 with `@tailwindcss/postcss` as a dev dependency; the portal's own stylesheet is `styles/prototype.css` (1 891 lines) | `frontend/package.json`, `app/globals.css` |
| Frontend | `qrcode` ^1.5.4 (QR generation on the server), `jsqr` ^1.4.0 (camera scanner on `/verify`) | `frontend/package.json` |
| Frontend | Tests | `node --test --experimental-strip-types "src/**/*.test.ts"` — five unit test files (`candidate-data`, `caps`, `pdf-write`, `reason`, `xlsx-write`) | `frontend/package.json` |
| Database | PostgreSQL | 17 in CI (`postgres:17`); Railway-managed in production; `pgcrypto` for bcrypt (`crypt`/`gen_salt('bf', 12)`) and `pgp_sym_encrypt` | `.github/workflows/ci.yml`, `db/V039__gateway_credentials.sql` |
| Size | API: 242 Java files (≈37 800 lines); migrations ≈37 500 lines of SQL; frontend: 629 TypeScript/TSX files, 261 `page.tsx`, 37 `route.ts` | counted in the repository |

---

## 2 Backend developer guide

### 2.1 Project layout

```text
api/
├── pom.xml                      Spring Boot 4.1.1 parent, Modulith BOM, failsafe
├── Dockerfile                   two-stage build; runtime carries db/ for the pre-deploy migrate
├── railway.json                 preDeployCommand: bash db/migrate.sh; health /actuator/health
├── scripts/dev-token.mjs        mints an HS256 development token (no dependencies)
└── src/
    ├── main/java/ng/edu/moaum/portal/
    │   ├── PortalApiApplication.java   @SpringBootApplication @EnableScheduling
    │   ├── shared/                     the OPEN kernel
    │   ├── platform/                   the request path and the outbox
    │   ├── auth/  iam/  admissions/ …  one package per module (see §1.4)
    │   └── <module>/package-info.java  @ApplicationModule(displayName = "…")
    ├── main/resources/application.properties
    └── test/java/ng/edu/moaum/portal/
        ├── ModularityTests.java        module boundaries (no context, no DB)
        ├── PortalApiApplicationTests.java  context loads without a database
        ├── OidcVerifierTest.java       SSO verifier against a generated key
        ├── ItSupport.java, TestTokens.java  helpers for the journey tests
        └── *IT.java                    29 integration tests, gated on DATABASE_URL
```

Inside a module the files are named by role: `XxxController` (HTTP, guards, bean validation), `XxxService` (rules that are not the database's), `XxxRepository` (SQL through `JdbcClient`), records for request and response bodies, and occasionally a `XxxNotifier` (queues notices) or a clock/job class. Small modules keep the SQL in the controller.

### 2.2 Conventions

**Controllers carry their guards as constants.** Every controller declares the office lists it checks as `private static final String` SpEL fragments and applies them with `@PreAuthorize`. For example `DocumentsController` (`credentials/DocumentsController.java:43-48`) declares `STUDENT`, `READERS`, `OFFICE`, `SIGNERS`, `REVOKERS` and `CONFIG`. The generated *07 API Reference* reads these constants to fill its "Who may call" column, and *04 Role & Permission Matrix* is derived from them, so a guard that is not a named constant will not appear correctly in either.

**Records are the DTOs.** Request bodies are Java records annotated with Jakarta Validation (`@NotBlank`, `@Size`, `@Valid`), for example `PgPortalController.SignIn(@NotBlank @Size(max = 160) String identifier, @NotBlank @Size(max = 100) String password)`. Responses are records or `Map<String, Object>` built from `JdbcClient.query().listOfRows()`. Jackson is set to omit nulls (`spring.jackson.default-property-inclusion=non_null`). A Postgres array column is serialised as a plain JSON array by `SqlArrayJson` (`platform/SqlArrayJson.java`), because Jackson would otherwise serialise a `PgArray` as a bean and cut the response part-way through.

**Repositories use `JdbcClient` with named parameters.** SQL is written as text blocks with `:name` parameters and mapped to records (`query(Credential.class)`) or rows. Typed nulls are passed with `java.sql.Types` (`Types.VARCHAR`, `Types.OTHER`, `Types.BINARY`, `Types.TIMESTAMP_WITH_TIMEZONE`). Business rules live in SQL functions wherever a rule must hold whoever calls it; the Java side calls `SELECT schema.function(:a, :b)` and lets the database refuse.

**Two exceptions, one handler.** A rule the Java side enforces throws `DomainRuleViolation(code, detail, Remedy(message, office))` (→ 422). A missing resource throws `NotFound(what, id)` (→ 404). Everything else that the database refuses arrives as a `DataAccessException` wrapping a `PSQLException`, and `ProblemHandler` maps its SQLSTATE (§2.11).

**The acting office is bound, not trusted.** `OfficeScope` (`shared/OfficeScope.java`) resolves the department of a department office (`hod`, `exams`, `siwes`, `lecturer`) from its grant's scope, else the person's `lecturer` grant, else `hrm.staff_record.home_department`; and the faculty of a faculty office (`dean`, `facultyofficer`) from its grant, else the staff record's department's faculty. `bound(fac, dept, prog)` refuses a parameter outside the office's unit with `SCOPE_DEPARTMENT` / `SCOPE_FACULTY` ("That department is not in your faculty.") and fills in an absent one. An office that resolves to nothing is bound to the sentinel `__none__`, which matches no row. `reportScope()` gives the faculty or department a return is cut to. Scope is applied only where a controller calls it; §5.7 lists the endpoints where the dossiers found it missing.

**The audit context is the actor.** Services never take an actor id from a request body. The acting person and office come from `AuditContextHolder.current()`, placed by `AuditContextFilter`. Batch jobs and unauthenticated doors set a context explicitly, for example `AuditContextHolder.with(new AuditContext(NOBODY, "ict", "notice dispatch", null, null), …)` in `NoticeDispatcher`, where `NOBODY` is `00000000-0000-0000-0000-000000000000`.

**The reason header.** `X-Reason` is optional, recorded on the audit row (`moaum.reason`) and read by the trail. Frontend screens send it on every write; `lib/reason.ts` makes the value header-safe (typographic punctuation to plain forms, other non-Latin-1 characters percent-encoded) because a browser refuses to send a header outside ISO-8859-1.

### 2.3 How a request flows

The sequence for `POST /api/v1/iam/persons/{id}/office-assignments` made from the Users & roles screen:

1. The browser calls `POST /api/bff/api/v1/iam/persons/{id}/office-assignments` with a JSON body and `X-Reason`.
2. `proxy.ts` sees the path is not in the OPEN list, finds the `moaum_session` cookie, and — because the path starts with `/api/` — lets it through without the `/iam/me` check.
3. `app/api/bff/[...path]/route.ts` refuses anything that is not `api/v1/...`, copies the six forwarded headers, adds `Authorization: Bearer <cookie>` and `X-Active-Office: <moaum_office cookie>` when the browser did not send one, and calls `${PORTAL_API_URL}/api/v1/iam/persons/{id}/office-assignments` with `cache: "no-store"`.
4. `CorrelationIdFilter` (highest precedence) reads `X-Correlation-Id`; a missing or non-UUID value is replaced by a fresh UUID; the id is set as a request attribute, echoed in the response header and put in the SLF4J MDC as `correlationId`.
5. Spring Security's `BearerTokenAuthenticationFilter` decodes the JWT with the `JwtDecoder` bean — `NimbusJwtDecoder.withSecretKey(HmacSHA256)` when `MOAUM_AUTH_HMAC_SECRET` is set, else `JwtDecoders.fromIssuerLocation(MOAUM_AUTH_ISSUER_URI)`. The `offices` claim becomes `OFFICE_<code>` authorities (`SecurityConfig.authenticationConverter()`). The session policy is `STATELESS` and CSRF is disabled.
6. `AuditContextFilter`: the subject must parse as a UUID (else 401 "The token's subject is not a person id."); when the token has a `sid`, `SessionGuard.refuse` looks the session up — not hex, unknown, ended, past `absolute_end`, or issued before this API instance started each give a 401 with its own sentence; `last_seen_at` is touched at most once a minute. `X-Active-Office` must be one of the token's offices, else 403 "The office 'x' is not one this token carries: […]". The filter then sets `AuditContext(actor, office, X-Reason, correlationId, remoteAddr)` on the thread and clears it in `finally`.
7. `@PreAuthorize("hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_super','OFFICE_ict','OFFICE_admin')")` on `IamController.grant` is evaluated by method security (`@EnableMethodSecurity`). A miss is a bare 403 from Spring Security with no problem body; the frontend's `fallbackProblem()` gives it words.
8. Bean validation runs on the `@Valid @RequestBody` record; a failure is a 400 `VALIDATION_FAILED` with `violations[]`.
9. The service opens a transaction (`@Transactional`). `AttributedTransactionManager.doBegin` runs `SELECT set_config('moaum.actor_id', ?, true), set_config('moaum.actor_office', ?, true), set_config('moaum.reason', ?, true), set_config('moaum.correlation_id', ?, true), set_config('moaum.source_ip', ?, true)` on the connection. The third argument `true` makes the settings transaction-local, so they cannot leak into the pooled connection's next borrower.
10. The repository inserts into `iam.office_assignment`. The `AFTER INSERT` trigger `audit.record` reads the settings, computes the subject key, locks the chain head for `(period, shard)`, and writes the hash-chained entry. Had the settings been absent it would have raised SQLSTATE 23514 "unattributed change to iam.office_assignment", which `ProblemHandler` renders as 403 `NO_ACTING_OFFICE`.
11. The response record is serialised; the BFF copies back `content-type`, `x-correlation-id` and `location` and returns the upstream status and body to the browser.

A read follows the same path without step 9's write and without any need for an office: a token with no offices still reads, and the database refuses any write it attempts.

### 2.4 Adding an endpoint, a migration and a screen

**A migration.**
1. Create `db/V264__<short_name>.sql`. Never edit a file that has been applied anywhere: the ledger stores each file's SHA-256 and `migrate.sh` stops the deployment by name when an applied file differs (§7.3). Corrections go in a new file.
2. Wrap the file in `BEGIN; … COMMIT;`.
3. For every new state table add a primary key and `SELECT audit.attach('schema.table');` (or `audit.exempt('schema.table', '<reason longer than 20 characters>')` for a blob, telemetry or derived read model). `check.sql` lists unattached tables through `audit.unattached()`; `verify.sql` re-checks on every deploy that an unattributed write is still refused.
4. If the migration inserts into an attached table it must set the context first: `SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true); SELECT set_config('moaum.actor_office', 'academic', true); SELECT set_config('moaum.reason', '<what> (V264)', true);` (as V227, V229 and V250 do).
5. If it adds a row to `ref.office`, raise the exact count `verify.sql` asserts (34 at V263: 32 staff offices, the applicant and the student), or the deploy stops at "Apply the migrations".
6. Put a rule that must hold for every caller in a SQL function or trigger with a message and a `HINT` written for a person; the API passes both through as the problem's detail and remedy.
7. Run it locally against a migrated database before pushing (§7.5).

**An endpoint.**
1. Add the guard constant to the module's controller (or a new controller in the module), for example `private static final String DESK = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar')";`.
2. Declare the request body as a record with validation annotations; declare the response as a record or a row map.
3. Annotate the method with `@PostMapping("/api/v1/<module>/…")`, `@PreAuthorize(DESK)` and `@Transactional` when it writes.
4. Apply `OfficeScope` when the office is a department or faculty office and the resource belongs to a unit: `scope.bound(fac, dept, prog)`, `scope.deptWithin(dept)`, `scope.assertCourseInScope(code)`.
5. Call the SQL function or write the SQL with `jdbc.sql("…").param(…)`. Throw `DomainRuleViolation` for a rule the Java side owns, with a `Remedy` naming the office. Throw `NotFound` for a missing id.
6. Queue any notice inside the same transaction with `platform.queue_notice(channel, recipient, subject, body, about_kind, about_id)` (or `NoticeRepository.queueEmail` when attachments ride along).
7. Add a `TITLES` entry in `ProblemHandler` for any new code whose generated title would read badly.
8. Extend the module's `*IT` journey test (or add one, gated with `@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")`).
9. Re-run `./mvnw verify` so `ModularityTests` proves the module imported nothing it should not.

**A screen.**
1. Add `frontend/src/app/<path>/page.tsx` as an async server component: read `searchParams`, call `api<T>()` for `/api/v1/iam/me` and the screen's data in a `Promise.all`, render `<Shell route="t/…" me={…}>` around either `<ProblemNotice problem={…}/>` or the client screen. Export `const dynamic = "force-dynamic"`.
2. Write the client screen (`"use client"`) beside it using the kit (§3.3); no inline styles, no hex colours (§4).
3. Give the route an id in `lib/menus.ts` under the right office and section, a title in `lib/titles.ts` (or in `OVERRIDES` in `Shell.tsx`), and a URL in `ROUTES` in `Shell.tsx`.
4. Client writes go through `fetch("/api/bff/api/v1/…", { method, headers: { "content-type": "application/json", "X-Reason": reasonHeader(text) }, body })`; show the result with `notify` / `notifyProblem`.
5. Any same-page filter, pager or picker that changes only the query must navigate with `useQueryNav()` (§3.5).
6. Run `cd frontend && npx tsc --noEmit -p . && npx eslint <files>` before committing; CI runs `npm test`, `npm run lint`, `npm run build`.

### 2.5 Testing

| Kind | Class | Needs | What it proves |
|---|---|---|---|
| Structural | `ModularityTests` | nothing | `ApplicationModules.verify()` — a module imports only another module's published API. |
| Context | `PortalApiApplicationTests` | nothing (pool connects lazily) | The context starts without a database in reach, so a service that cannot reach its database can still report that. Runs with `moaum.auth.hmac-secret` set to `TestTokens.SECRET`. |
| Unit | `OidcVerifierTest` | nothing | The SSO verifier refuses a wrong key, audience, expiry, nonce and issuer, and does not read a password alone as a second factor. |
| Integration | 29 `*IT` classes: `ApiIT`, `ApplicantIT`, `AuditSpineIT`, `AuthIT`, `CalendarIT`, `CandidateDataIT`, `CollegePaymentsIT`, `CredentialsIT`, `CutoffIT`, `DefermentIT`, `DocumentsIT`, `ExaminersIT`, `GraduationIT`, `HelpdeskIT`, `HostelIT`, `MatricFormatIT`, `MatriculationIT`, `PaymentsIT`, `PgLifecycleIT`, `PutmeIT`, `ReconsiderationsIT`, `ResultsIT`, `SettingsIT`, `StaffProfileIT`, `StudentIT`, `StudentPortalIT`, `StudentStatsIT` (and the two helpers) | `DATABASE_URL` pointing at a database the migrations have been applied to | Each drives a journey end to end through the HTTP API on a random port. Every class is annotated `@SpringBootTest(webEnvironment = RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)` and `@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")`, so without the variable they are **skipped, not failed**. |

`TestTokens.token(subject, offices)` mints an HS256 JWT with `sub`, `iat`, `exp` (+600 s) and `offices` — no `sid`, so `SessionGuard` is not consulted. `ItSupport` wraps a `RestClient` (`call`, `get`, `callList`, `getList`, `anon`) that sends `X-Reason: integration test`, and `db(Supplier)` runs an attributed write straight into the database as office `ict` for rows the API has no door for; it also seeds far-future sessions, invented students (surname given, other names "Invented") and persons.

`AuditSpineIT` proves the property the design rests on from the application side: a transaction without a context cannot write to an attached table; one with a context leaves an audit row naming the actor; nothing leaks between transactions. `ApiIT` drives the request path: 401 without a token, an office the token does not carry refused before any service runs, method security by office, a person created and granted, a CAPS list loaded whole and a list-kind contradiction refused whole with the database's own remedy.

**How CI runs them.** The `api` job starts `postgres:17`, applies the migrations with `bash db/migrate.sh`, then runs `./mvnw -B -ntp verify` with `DATABASE_URL=postgres://postgres:ci@localhost:5432/moaumpp` in the environment, so every `*IT` runs (`maven-failsafe-plugin` binds `integration-test` and `verify`). Locally, `./mvnw verify` without the variable runs only the three database-free tests.

> **Note:** the integration tests leave rows behind (far-future sessions, invented persons, `public.*` scratch tables). `audit.unattached()` on a developer database therefore lists test residue; on production it should be empty. Several memory notes in this repository record the reset steps the ITs expect (see *09 Feature Status Report* for the list).

### 2.6 Scheduled jobs

`PortalApiApplication` carries `@EnableScheduling`. No `TaskScheduler` bean or `SchedulingConfigurer` is defined, so Spring's default single-threaded scheduler runs the six jobs one at a time; a long dispatch delays the next clock. Each job sets its own `AuditContext` (actor `NOBODY`, an office, a reason) and runs its work in a `TransactionTemplate`.

| Job | Class | Schedule | Property | Zone | What it does |
|---|---|---|---|---|---|
| Notice dispatcher | `platform/NoticeDispatcher.dispatch()` | fixed delay 60 000 ms, first run after 15 000 ms | `moaum.notices.every-ms`, `moaum.notices.initial-ms` (`MOAUM_NOTICES_EVERY_MS`, `MOAUM_NOTICES_INITIAL_MS`) | server | Sends up to 50 `QUEUED` notices with `attempts < 5` (§2.10). Returns at once, logging once, when no SMTP account, eBulkSMS account or relay is configured. |
| Deferment clock | `deferments/DefermentClock` | cron `0 20 6 * * *` (06:20 daily) | `moaum.deferments.cron` | Africa/Lagos | Approved deferment periods that have begun come into force (status `DEFERRED`); returns approaching are reminded once. The database functions do the work. |
| Examiner reminders | `examiners/ExaminerReminders` | cron `0 15 7 * * *` (07:15 daily) | fixed in code | Africa/Lagos | An examiner whose deadline is three days off or nearer is reminded once; one past the deadline with nothing submitted is told once, and so is the desk. Marks on the assignment stop repeats; a later deadline clears them. |
| Help-desk auto-closer | `helpdesk/AutoCloser` | initial delay 5 min, fixed delay 1 h | fixed in code | server | When the Director of ICT has set a quiet period in days, a `RESOLVED` ticket the requester has not answered closes itself after it, on the record, and the requester is told. Does nothing while the setting is empty (the shipped state). |
| Hostel clock | `hostel/HostelClock` | cron `0 5 * * * *` (five past every hour) | `moaum.hostel.cron` | Africa/Lagos | An expired unpaid hold lapses and the bed passes to the next name on the waiting list. |
| Payments sweep | `payments/PaymentsService.sweep()` | fixed delay 600 000 ms (10 min), first run after 120 000 ms | `moaum.payments.sweep-every-ms` | server | Re-verifies hanging gateway attempts on the channel they were opened on (Paystack verify, Flutterwave verify-by-reference, Quickteller requery, PayDirect query when its credentials are set). Skips attempts younger than 5 minutes or already checked 12 times. Returns at once when no gateway is on. A reference the gateway now says is paid is settled exactly as a webhook would settle it. |

There is no nightly audit-chain verification job (the Security screen's wording notwithstanding — `audit.verify_chain` is called only from `db/check.sql`), no due-return reminder, and no offer-lapse job (see §11).

### 2.7 File and document handling

**Transport.** No endpoint uses `MultipartFile`; uploads arrive as JSON bodies carrying base64 content with a declared content type and filename, and are decoded, sized and sniffed in the controller. Downloads are served as byte arrays with `Content-Type`, `Content-Disposition` and, in the newer modules, `X-Content-Type-Options: nosniff` and `Content-Security-Policy: sandbox`.

**Blob tables.** Binary content is kept in dedicated tables that are audit-exempt (a hash-chained JSON copy of a file would be pointless), beside an attached metadata table: `admissions.application_document_blob`, `admissions.pg_document`, `admissions.pg_research_document_blob`, `extexam.project_document_blob`, `extexam.examiner_file_blob`, `helpdesk.ticket_attachment_blob`, `hrm.staff_photo`, `lms.material_blob`, `platform.notice_attachment`, the candidate photograph/attachment tables (`admissions.attachment`, `candidate_photo`) and `credentials.issued` (the statement bytes and their hash). Seventy-three `bytea` columns exist in all, including the audit spine's own hashes and session ids.

**Limits and sniffing by module** (from the controllers):

| Module | Accepted types | Size limit | Magic-byte check | Served with |
|---|---|---|---|---|
| Applicant documents (`applicant/ApplicantService`) | `application/pdf`, `image/jpeg`, `image/png` | 1 byte – 2 MB (`MAX_DOCUMENT`; also `ck_doc_bytes`) | declared type only (no sniff) | inline with the stored type |
| Support requests (`support/SupportController`) | as declared | ≤ 2 097 152 bytes | no | inline, no `nosniff`/sandbox |
| Deferment documents (`deferments/DefermentsController`) | pdf, jpeg, png (`image/jpg` normalised) | 5 MB (`DOC_MAX`) | yes — `%PDF-`, PNG signature, JPEG `FF D8 FF`; `DEF_DOC_TYPE` when the bytes disagree with the name | `nosniff` + `sandbox` |
| Help-desk attachments (`helpdesk/HelpdeskController`) | pdf, jpeg, png | 5 MB (`MAX_BYTES`), non-empty | yes (full 8-byte PNG signature) | `nosniff` |
| LMS materials (`lms/LmsService`) | pdf, jpeg, png, text/plain, text/csv and others in `TYPES` | 5 MB (`MAX_FILE`) | not verified | inline with stored type and a sanitised filename (dossier D) |
| PG applicant documents and photo (`pgadmissions/PgPortalController`) | documents as declared; photo jpeg/png | 8 MB documents (`MAX_DOC`), 4 MB images (`MAX_IMG`) | not verified | `nosniff` + `sandbox` |
| PG research documents (`pgadmissions/PgResearchController`) | as declared | 25 MB (`DOC_MAX`) | dossier C: sandbox on serve | `sandbox` |
| External examiner files (`examiners/ExaminersController`) | project documents 25 MB (`MAX_DOC`); private files pdf/jpeg/png 5 MB (`MAX_PRIVATE`) | as stated | yes — pdf, png, jpeg, and `PK` for Word/PowerPoint/ZIP | `nosniff` + `sandbox`, `Content-Disposition` |
| Staff profile photo (`staff`) | JPEG/PNG | 2 MB (dossier A) | not verified | — |
| Candidate passports (`admissions/CandidateDataController`) | data URLs; default `image/jpeg` | ≤ 64 KB stored as a data URL, larger by metadata only | no | data URL |
| Notice attachments (`platform.notice_attachment`) | any | ≤ 15 MB per attachment (V230); ≤ 15 MB in all for an emailed return | no | as email attachments |

The uneven coverage (sniffing and safe-serving headers in the modules written after V251, declared-type trust in the older ones) is listed as a gap in §5.14.

### 2.8 PDF generation

PDFs are produced **in the frontend**, in Next.js route handlers, not by the API. The API's PDFBox dependency is used only to merge an applicant's uploaded documents for the School.

- `lib/pdf-write.ts` is a dependency-free PDF writer: A4 pages (`595.28 × 841.89` pt, landscape when a page asks), Helvetica (`F1`), Helvetica-Bold (`F2`) and Times-Bold (`F3`), text with colour and letter-spacing, wrapped paragraphs, rules, boxes, rounded rectangles and clipping, JPEG images placed as they are (`jpegSize()` reads the dimensions; PNG is not embedded), faint images through the `GS5`/`GSW` graphics states (5 % and 6 % alpha) for watermarks, and `pdf(pages, title)` that assembles the objects and the cross-reference table. Text is WinAnsi; characters outside it are replaced. Its behaviour is covered by `pdf-write.test.ts`.
- `lib/pdf-crest.ts`: `crestImage()` reads the crest as a JPEG from `public/` once (a document still prints without it) and `brandHeader(page, left, subtitle)` draws the crest, the University's name and a rule, returning the y to continue from.
- `lib/qr.ts` (server-only) builds QR matrices with the `qrcode` package and the stateless check tokens: `receiptToken` = SHA-256(`reference|receiptNo`) truncated, `examToken` = SHA-256(`EXAM|matric|session|semester`), and the corresponding `/verify/...` paths. A route reads the public origin from `x-forwarded-host`/`x-forwarded-proto` so the QR opens a real address.
- Route handlers that produce PDFs: `app/applicant/apply/pdf`, `app/applicant/screening/slip`, `app/applicant/status/letter`, `app/pg/offer/pdf`, `app/pg/summary/pdf`, `app/staff/idcard/pdf`, `app/student/broadsheet/pdf`, `app/student/exams/card/pdf`, `app/student/form/pdf`, `app/student/hostel/clearance`, `app/student/hostel/letter`, `app/student/idcard/pdf`, `app/student/receipt/[reference]/pdf`, `app/student/results/[session]/[semester]/pdf`; plus the libraries `lib/deferment-letter.ts`, `lib/document-pdf.ts` (digital documents: certificate and transcripts; a REVOKED document carries a diagonal "REVOKED" watermark, a REPLACED one "REPLACED"), `lib/idcard-pdf.ts`, `lib/marked-sheet.ts` and `lib/report-pdf.ts` (a kept return across landscape pages, footed with its verification code).
- Each handler runs with the caller's session (`api()` and `sessionToken()`), fetches the facts from the API, refuses with a 409 problem when the document is not yet issuable ("A receipt is issued when the payment is confirmed."), and returns `application/pdf`.

Browser-side "Print / Save as PDF" uses `window.print()` on standalone documents (`ReportDoc`, the `.rpt*` classes) or `lib/print.ts`'s `printNode()`, which clones the element into a hidden same-origin iframe because the print stylesheet hides the whole `.shell`.

### 2.9 Excel and print exports

- `lib/xlsx-write.ts` writes an `.xlsx` with no library: a stored (uncompressed) ZIP of OOXML parts, shared cell styles, header-row styling, merges, centred columns, an optional crest image floating over the top-left of every sheet, and `colName()`/`crc32()` helpers. The column-header row is recognised as the first row whose first cell is `SN` or `S/N`. Covered by `xlsx-write.test.ts`.
- `lib/xlsx.ts` reads the first worksheet of an `.xlsx` in the browser (stored and deflated entries via `DecompressionStream`, shared and inline strings, numbers; not ZIP64, not dates) — this is how CAPS lists, staff rolls and score sheets are parsed before anything is sent to the API. `lib/docx.ts` reads a `.docx` in document order for the course-structure importer.
- `lib/exportbrand.ts` is the branding contract every office export follows: `SCHOOL` = "Rev. Fr. Moses Orshio Adasu University, Makurdi"; `docSerial(prefix)` = `MOAUM/<PREFIX>/YYYYMMDD/HHMMSS-RR`; `brandedXlsx(title, headers, rows, opts)` puts school, title, generation date and serial above the table with the crest; `brandedPrint(...)` opens a print window with the same header and a footer naming the school, serial and date; `downloadBlob()`.
- **S/N first.** Branded exports carry **S/N** as the first column, generated at export time, and names are sorted A–Z before numbering. Exports that reproduce an external layout (the JAMB admission template, `ApplicantsDesk.exportTemplate`) use their own `xlsx` builder and follow that layout instead.
- `lib/crest-server.ts` reads `public/crest.png` on the server (checking the PNG signature) for workbooks built in route handlers, such as the emailed return.
- `DTable`'s own Print button prints one table in a hidden iframe with a small print stylesheet and a heading line "Rev. Fr. Moses Orshio Adasu University, Makurdi · printed <date>".

### 2.10 Notifications

The portal has one transactional outbox. Nothing sends directly.

```text
 module transaction ──► platform.queue_notice(channel, recipient, subject, body, about_kind, about_id)
                          │  blank recipient → NULL, nothing queued
                          ▼
                     platform.notice (state QUEUED, attempts 0)
                     platform.notice_attachment (optional files, V230)
                          │
      every 60 s          ▼
 NoticeDispatcher.dispatch() ── takes 50 QUEUED rows with attempts < 5, oldest first
      │
      ├─ EMAIL, Mail-server settings complete ──► SmtpMailer (JavaMail; STARTTLS or SSL;
      │       connect 15 s, read/write 20 s; multipart text + branded HTML with the crest
      │       from MOAUM_PORTAL_URL/crest.png; attachments)
      ├─ SMS, eBulkSMS enabled and keyed ─────► EbulkSmsSender (POST https://api.ebulksms.com/sendsms.json;
      │       numbers normalised to 234XXXXXXXXXX; the body must say SUCCESS)
      └─ otherwise the HTTP relay for the channel (MOAUM_NOTICES_EMAIL_URL / _SMS_URL, bearer
              MOAUM_NOTICES_TOKEN; 20 s timeout), payload by format:
                generic  {to, subject, body, channel, id, attachments[]}
                termii   {api_key, to (234…), from, sms, type: plain, channel: generic}
                resend   {from, to: [..], subject, text, attachments[]}
      │
      ▼  outcome written in its own transaction (actor NOBODY, office ict, reason "notice dispatch")
   success → SENT, sent_at, provider_ref (first 200 chars of the provider's answer / "smtp <host>" / "ebulksms …")
   failure → attempts + 1, last_error (≤ 400 chars); FAILED when this was the fifth failure
      │
      ▼
   readers: staff at /me/notices (rows about them or addressed to their email/phone);
            students on the student portal; the outbox at /notices; requeue puts FAILED rows
            back to QUEUED with attempts 0 (single or "Put all n failed back in the queue")
```

Constraints on `platform.notice`: channel `EMAIL|SMS`, state `QUEUED|SENT|FAILED`, `SENT` requires `sent_at`. When nothing is configured the dispatcher logs once ("notices: no email account (Mail server screen), SMS account (SMS settings screen) or relay configured; the outbox holds them") and every notice stays `QUEUED` — which is the state of the local database (1 398 rows, all queued, at audit time). A notice whose channel has no sender while the other channel has one is skipped (`continue`) and stays `QUEUED` without an attempt.

> **Warning:** the `/notices` screen's "Email provider / SMS provider" indicator reads only the relay URLs (`NoticesController` uses `emailConfigured()`/`smsConfigured()`), so it can say "No provider is wired" while SMTP or eBulkSMS delivery is in fact working. The Mail Server screen's footer note that SMTP sending "arrives with the mail transport" is also stale; `SmtpMailer` is live.

### 2.11 Error handling and problem details

`ProblemHandler` (`@RestControllerAdvice`) renders every refusal as RFC 9457 `application/problem+json` (`spring.mvc.problemdetails.enabled=true`). Every problem carries `status`, `detail`, `instance` (the request URI) and `correlationId`; most carry `code`; a `DomainRuleViolation` also carries `type` (`https://api.moaum.edu.ng/problems/<code-in-kebab-case>`), a human `title` and, when given, `remedy {message, office}` (the office may be null — "You" and the like are passed as text).

| Cause | Status | `code` | Detail / remedy |
|---|---|---|---|
| `DomainRuleViolation` | 422 | the violation's code (e.g. `AUTH_LOCKED`, `PAY_REFERENCE_EXPIRED`, `SCOPE_DEPARTMENT`) | the message; remedy from the exception. Title from `TITLES` (e.g. `AUTH_LOCKED` → "Account locked for now") or derived from the code's words (`…_SAYS_WHY` → "A reason is needed", `…_MINUTE_REQUIRED` → "A minute is needed", `…_SIZE` → "The file is too large", `…_TYPE` → "That file type is not accepted", `…_RANGE` → "<value> out of range"). |
| `NotFound` | 404 | `NOT_FOUND` | "<what> <id> not found" |
| `MethodArgumentNotValidException` | 400 | `VALIDATION_FAILED` | "The request did not validate." + `violations[{field, code: INVALID, message}]` |
| SQLSTATE 23514 whose message starts "unattributed change" | 403 | `NO_ACTING_OFFICE` | "This request names no acting office, so it may read but not change anything." — remedy "Send X-Active-Office with one of the offices your token carries." (Directorate of ICT) |
| SQLSTATE 23514 (other CHECK), 23502 (not null), 22P02 (bad text representation), P0002 (no data found), 23P01 (exclusion) | 422 | `DATABASE_RULE_REFUSED` | the server message; remedy = the server `HINT` when present, office "the office named in the rule" |
| 23505 (unique) | 409 | `ALREADY_EXISTS` | the server message |
| 23503 (foreign key) | 409 | `REFERENCE_MISSING` | the server message |
| 42501 (insufficient privilege) | 403 | `DATABASE_PERMISSION` | the server message |
| any other `PSQLException` | 422 | `DATABASE_REFUSED` + `sqlstate` | the server message, or "The database refused this request." |
| `DataAccessException` with no `PSQLException` in its cause chain | rethrown (500) | — | — |
| Refusals inside `AuditContextFilter` (bad subject, session refused, office not carried) | 401 / 403 | — | a hand-written problem body with `type: about:blank`, the reason phrase as title and the sentence as detail (no `code`, no `correlationId` in the body; the header still carries the id) |
| `@PreAuthorize` miss | 403 | — | no body from the API; the frontend's `fallbackProblem()` supplies "You don't have access to this screen" with a remedy |

On the frontend, `lib/api.ts` returns `{ok, data}` or `{ok: false, problem}`; a 2xx with a non-JSON body is turned into a 502 problem ("The portal API answered with an unreadable body") rather than `null` data; an unreachable API is a 503 `API_UNREACHABLE`. `ProblemNotice` shows title (humanised by `lib/problem-title.ts`), detail, "What to do: <remedy> — <office>" and field violations; `notifyProblem` maps statuses to toasts (§3.5).

### 2.12 Logging and the correlation id

`CorrelationIdFilter` is a `@Component` with `@Order(Ordered.HIGHEST_PRECEDENCE)`, so Boot registers it ahead of the security chain for every request. It accepts `X-Correlation-Id` only when it is a UUID (anything else is replaced, not trusted), sets it as a request attribute, echoes it in the response header, and puts it in the MDC under `correlationId` for the life of the request. The same id is placed on the transaction (`moaum.correlation_id`) and stored on every audit row, and `ProblemHandler` writes it into every problem body — so one id ties a log line, an audit entry and the error a person saw. Logging is Spring Boot's default (console, Logback); there is no custom pattern in `application.properties`, so the MDC key is available to a pattern but not printed by default (*not verified* whether Railway's log format shows it). The frontend does not generate correlation ids itself; a screen may pass one through `ApiOptions.correlationId`.

### 2.13 Health endpoints

| Service | Path | Auth | Answers |
|---|---|---|---|
| API | `GET /actuator/health` (and `/actuator/health/**`) | public | Spring Boot health with probes enabled and `show-details=never`; only `health` and `info` are exposed (`management.endpoints.web.exposure.include=health,info`). Railway's health check for `moaum-api` (`api/railway.json`, timeout 300 s). |
| API | `GET /api/v1/platform/status` | public | `{service, commit, startedAt, database{reachable, migrationsApplied, latestMigration, admissionSettings2025_2026}}`. Reports the commit from `MOAUM_COMMIT` / `RAILWAY_GIT_COMMIT_SHA`. The 2025/2026 label is fixed text carried from the prototype health check. |
| Frontend | `GET /healthz` | public (in the OPEN list) | `{status: "up", service: "moaum-portal"}`. Railway's check for `moaum-portal` is `/` (timeout 120 s); `proxy.ts` lets a request whose user-agent contains `RailwayHealthCheck` or whose host is `healthcheck.railway.app` through without a session. |
| Prototype | `GET /healthz` | public | Always 200 while the page can be served; reports migrations applied, the latest, and the 2025/2026 admission settings state when `DATABASE_URL` is set (it shells out to `psql`). |
| Prototype | `GET /readyz` | public | Strict: 503 if the page is missing or `DATABASE_URL` is set and the database cannot be reached. CI's `image` job polls it. |

---

## 3 Frontend developer guide

### 3.1 App Router layout

```text
frontend/
├── next.config.ts            output: "standalone" — nothing else (no headers, no rewrites)
├── package.json              next 16.3.4 · react 19.2.8 · qrcode · jsqr; tailwind/postcss (dev)
├── eslint.config.mjs         eslint-config-next core-web-vitals + typescript
├── .env.example              PORTAL_API_URL, PORTAL_API_TOKEN, PORTAL_ACTIVE_OFFICE
├── Dockerfile                node:22-alpine, npm ci → npm run build → standalone server.js as user portal
├── railway.json              health /
├── public/                   crest.png, fonts/ (IBM Plex woff2)
└── src/
    ├── proxy.ts              the session gate (Next 16's proxy, formerly middleware)
    ├── app/
    │   ├── layout.tsx        <html lang="en"><body><div id="app">{children}</div><ToastHost/>
    │   ├── globals.css       imports fonts.css and ../styles/prototype.css; report (.rpt*) styles
    │   ├── page.tsx          the home router: office → dashboard or redirect
    │   ├── api/auth/**       13 route handlers (doors, bootstrap, forgot/reset, SSO, sign-out)
    │   ├── api/bff/[...path] the BFF forwarder (GET/POST/PUT/PATCH/DELETE)
    │   ├── healthz/          {status: up}
    │   ├── login/, apply/, pg/apply, verify/**, track/, documents/d/[token]   public surfaces
    │   ├── dashboards/       one component per office dashboard
    │   └── <area>/…/page.tsx 261 pages: students, admissions, finance, results, college, hostel,
    │                         credentials, reports, people, calendar, platform, governance, …
    ├── components/
    │   ├── proto/            Shell, ui (kit), blocks, DTable, Toast, vz (charts)
    │   ├── ProblemNotice.tsx
    │   └── stats/, …         feature components shared by several pages
    ├── lib/                  api, session, offices, menus, titles, reason, query-nav,
    │                         pdf-write, pdf-crest, qr, xlsx, xlsx-write, docx, exportbrand,
    │                         print, problem-title, report, and per-module data helpers
    └── styles/prototype.css  the one stylesheet (1 891 lines)
```

There is no `middleware.ts`; Next 16's `proxy.ts` plays that role with `matcher: ["/((?!_next/static|_next/image).*)"]`.

### 3.2 Server pages and client screens

Every screen is two files. The **page** is an async server component: it awaits `searchParams`, calls `api<T>()` (server-only; `import "server-only"`) for `/api/v1/iam/me` and its data — usually in one `Promise.all` — and renders `<Shell route="t/…" me={me.ok ? me.data : null}>`. Inside the Shell it renders `<ProblemNotice problem={…}/>` when the main read failed, else the **client screen** (`"use client"`), passing the data as props. Pages export `const dynamic = "force-dynamic"` so nothing is cached between users. `app/people/page.tsx` is the canonical example.

`api()` (`lib/api.ts`) adds `Authorization: Bearer` from `sessionToken()` (the cookie, or `PORTAL_API_TOKEN` outside production), `X-Active-Office` from the option, the `moaum_office` cookie or `PORTAL_ACTIVE_OFFICE`, `X-Reason` through `reasonHeader()`, and `X-Correlation-Id` when given; it always fetches with `cache: "no-store"`. It returns `ApiResult<T>`: `{ok: true, data, status}` or `{ok: false, problem}`.

Client screens call the API only through `/api/bff/api/v1/...` with `fetch`. The BFF refuses any other prefix ("Only /api/v1/... is reachable through the BFF."), forwards `content-type`, `accept`, `x-correlation-id`, `x-active-office`, `x-reason` and `idempotency-key`, and copies back `content-type`, `x-correlation-id` and `location`. (`Idempotency-Key` is forwarded but no API code reads it — `platform.idempotency_key` is CONFIGURED BUT UNUSED.)

The `Me` shape the Shell consumes (`components/proto/Shell.tsx`): `actorId`, `activeOffice`, `offices[]`, `name`, `staffNumber`, `sessionId`, `unit`, `waiting` (badge counts by menu item id, or `"!"`), `menu` (an alternative menu id, used for a postgraduate student who reads the School's sidebar).

### 3.3 The design kit

All kit components live in `components/proto/ui.tsx` and `blocks.tsx`, with `DTable.tsx`, `Toast.tsx` and `vz.tsx` beside them. They emit the prototype's class names so `prototype.css` styles them.

| Component | File | Signature (essentials) | Notes |
|---|---|---|---|
| `PageHead` | ui | `{title, description?, actions?, eyebrow?}` | In-content title block with an action row. |
| `Tabs` | ui | `{items, value, onChange, look = "segmented" \| "line", label?}` with counts | Segmented pill tabs or an underline row. |
| `Note` | ui | `{kind: "info" \| "ok" \| "bad", title, children?, action?}` | The `.notice` box. Only three kinds — there is no `warn` Note. |
| `Btn` | ui | `kind: primary \| secondary \| ghost \| go \| urgent`, `size: sm \| md`, `disabled`, `title` | Emits `.btn .btn--<kind> .btn--<size>`. |
| `LinkBtn` | ui | same classes on a Next `Link` (`href`, `prefetch`) | Default `ghost` / `sm`. |
| `IcoBtn` | ui | icon-only button with `aria-label`; `.btn--icon`, `is-danger` | |
| `RoleLine` | ui | who may act: "You may act — <office>" / "Signed in as <office> · view only" | Cosmetic; the API enforces the guard (§5.2). |
| `Pil` | ui | `kind: grey \| info \| ok \| bad \| warn` | Status pills. |
| `Two` | ui | `{a, b}` bold line + sub line | |
| `Tiles` | ui | `items: [eyebrow, figure, caption, extra?, href?][]`, `cls = "grid--4"` | KPI tiles; the fifth element makes the tile a link. |
| `Panel` / `PBody` | ui | `{title, right?, children}` / `{children, className?}` | `.card`, `.card__head`, `.card__title`, `.card__body`. |
| `KvGrid` | ui | `pairs: [key, value][]` | Key–value grid. |
| `Ico`, `Tick`, `WarnIcon` | ui | inline SVG glyph set by name | See §4.11. |
| `Step`/`Steps`, `Gate`/`Gates` | blocks | `state: done \| now \| todo` (gates: done \| todo) | Progress rails and checklists. |
| `Row`, `Bar`, `TwoCol`, `Num` | blocks | key/value row, a meter (`pct`, colour), two-column layout, numeric text | |
| `Passport` | blocks | `{w, h, radius, src, alt}` | Photo with a silhouette fallback. |
| `Modal` | blocks | `.mdl` scrim, `.mdl__box` (max 560 px; `is-wide` 860 px), head/body/foot, Escape and backdrop close | |
| `Field` | blocks | label, control, hint, `required` asterisk, `error` line and `.is-error` | Wraps `.field`. |
| `money`, `day` | blocks (re-exported from `lib/format`) | formatters | |
| `DTable` | DTable | `{cols, rows, texts?, title?, noPrint?, pageSize?}` | See §4.7. |
| `notify`, `toast.*`, `notifyProblem`, `ToastHost` | Toast | see §3.5 | One host in `layout.tsx`. |
| `Donut`, `HBars`, `VBars`, `Stack`, `Line`, `GroupBars`, `Legend`, `VZ`, `vzNum` | vz | SVG charts | See §4.15. |
| scope bar | per screen (`lib/scope.ts`, `lib/scope-data.ts`) | faculty → department → programme → level → session selects pruned to the office | The structure comes from `/api/v1/ref/structure`. |

### 3.4 Menus, routes and titles

- `lib/menus.ts` (`MENUS: Record<office, Menu>`) holds every office's sidebar: `label`, `home` (a route id) and `groups[{name, items[{id, icon, label, badge?}]}]`. Staff offices use the ten sections Overview · Academic · Students · Admissions · Finance · Staff · Services · Reports · Administration · Me; students and applicants keep journey menus. The file is regenerated by a script (its header says "edit the script, not the file"). A few badges in it are static prototype fixtures ("7" on Hanging payments, "12" on Reconciliation, "!" on Gateways, "2" on Governance and API Management) — live counts come only from `me.waiting`.
- `ROUTES` in `Shell.tsx` maps a route id (`t/users`, `r/academic`, `s/pay`, `a/accept`, `x/projects`, `pg/…`) to a URL. An item with no route renders as a button that shows "<label> is still the prototype's screen".
- `lib/titles.ts` (`TITLES`, generated from the prototype) gives every route id a `[title, subtitle]`; `OVERRIDES` in `Shell.tsx` replaces the prototype's invented subtitles; a page can pass live `title`/`sub` to the Shell. Some subtitles remain prototype text ("2026/2027 session" on Fees & payments, "Financial year 2026" on budget).
- `lib/offices.ts` holds `OFFICE_LABELS` (the database labels) and `ROLE_LABELS` (prototype label and unit) with `roleLabel()`/`roleUnit()`.
- The Shell chooses the menu as `MENUS[me.menu] ?? MENUS[activeOffice] ?? FALLBACK` (a minimal "Office" menu: Search, Dashboard, Leave & Payslip). Group badges sum `waiting`; the breadcrumb is group › item when the item label differs from the page title.

### 3.5 Navigation, toasts and the reason header

**`useQueryNav()`** (`lib/query-nav.ts`) returns `(url) => { router.push(url); router.refresh(); }`. In this Next 16 application a `router.push` that changes only the search parameters is served from the client router cache, so the address changes and the server page does not re-render. Every same-page picker, search form and pager uses this hook; a push to a different page may use `router.push` alone.

**Toasts** (`components/proto/Toast.tsx`): `notify(message, kind = "ok", ms?)` and `toast.ok|bad|info|warn(title, detail?)`. Time-to-live by kind: ok 4 s, info 5 s, warn 6 s, bad 7 s; at most 5 visible; a duplicate within 2.5 s is dropped; network and server errors are sticky. `notifyProblem(problem, fallbackTitle)` maps status: 0/502/503/504 → sticky "The portal could not reach the server"; 401 → warn "You are signed out"; 403 → warn (title or "You do not have access to that"); 404 → bad "Not found"; 400 or any `violations[]` → warn "Please check the form"; 409/422 → bad with the refusal's own title and detail + remedy; ≥ 500 → sticky "The portal could not complete that".

**`reasonHeader(text)`** (`lib/reason.ts`): normalises to NFC, replaces control characters with spaces, keeps Latin-1, maps typographic punctuation (em/en dashes, curly quotes, ellipsis, `₦` → "NGN ", `→` → "->") and percent-encodes anything else, then collapses whitespace. `api()` applies it to `options.reason`; client screens call it before setting `X-Reason`. Covered by `reason.test.ts`.

### 3.6 Lint rules that CI enforces

CI's `frontend` job runs `npm test`, `npm run lint` (ESLint 9, `eslint-config-next` core-web-vitals + typescript) and `npm run build` (which type-checks). The rules that have failed builds in this repository, and the fix each one needs:

| Rule | What it refuses | Do this instead |
|---|---|---|
| `react-hooks/set-state-in-effect` | a synchronous `setState` inside `useEffect` | load through an async IIFE or an on-demand loader |
| `react-hooks/static-components` | a component defined inside another component's render | hoist it to module level |
| `react-hooks/purity` | `Date.now()` (and similar) in a component body | compute it in a module-level helper or an effect |
| `react/no-unescaped-entities` | a bare `'` in JSX text | `&rsquo;` |
| `jsx-a11y` | a combobox without `aria-controls` | add the attribute |
| `@typescript-eslint/no-unused-vars` | unused imports and variables (errors) | remove them |

Run `cd frontend && npx tsc --noEmit -p . && npx eslint <touched files>` chained with `&&` before every commit; never pipe `tsc` through `tail`, which masks the exit code.

### 3.7 The proxy and its OPEN list

`proxy.ts` runs on every request except `_next/static` and `_next/image`.

1. A Railway health check (user-agent containing `RailwayHealthCheck`, or host `healthcheck.railway.app`) passes.
2. Paths in `OPEN_EXACT` pass: `/api/bff/api/v1/pg/programmes`, `/api/bff/api/v1/pg/apply`, `/api/bff/api/v1/pg/status`, `/api/bff/api/v1/pg/sign-in` (matched exactly so the prefix does not also open the authenticated PG desks).
3. Paths equal to, or under, an `OPEN` prefix pass: `/login`, `/apply`, `/pg/apply`, `/api/auth/`, `/api/bff/api/v1/applicant/lookup`, `/verify`, `/healthz`, `/crest.png`, `/favicon.ico`, `/api/bff/api/v1/examiners/invitation/`, `/api/bff/api/v1/examiners/activate`, `/pg/referee/`, `/api/bff/api/v1/pg/referee/`, `/documents/d/`.
4. With a `moaum_session` cookie: a page navigation (not `/api/*`, not a prefetch — `next-router-prefetch: 1` or `purpose: prefetch`) is validated with `GET ${PORTAL_API_URL}/api/v1/iam/me`; a 401 clears both cookies and redirects to `/login?next=<path+search>`; an unreachable API lets the request through ("the page's own call decides").
5. Without a cookie: outside production, `PORTAL_API_TOKEN` set in the environment lets the request through (a development bypass); otherwise redirect to `/login` with `next` set unless the path is `/`.

> **Note:** the `OPEN` match uses `pathname.startsWith(p)` as well as `p + "/"`, so `/verify` also opens `/verifyanything` and `/login` opens `/login-…`. No such route exists today; keep it in mind when naming new pages.

### 3.8 Sign-in handlers per identity

All thirteen handlers live under `app/api/auth/`. They call the API directly with `fetch` (not through the BFF), forward `x-forwarded-for`, and set the cookies on success.

| Handler | Calls | Cookie office | Answer |
|---|---|---|---|
| `sign-in` (the one door) | picks the API door by identifier shape: `MOAUM?/FAC[/PROG]/YY/SEQ` (V263 or V064 matric) or `MOAUM/ADM/YY/NNNNNN` → `/student-auth/sign-in`; `PG/YY/NNNNNN` → `/pg/sign-in`; 12 digits + 2–3 letters or `APP/YY/NNNNNN` → student door first, then `/applicant/sign-in`; a legacy `XX/…/digits` shape → student door, falling back to `/auth/sign-in`; anything else → `/auth/sign-in`, and on a 422 with an `@` in the identifier the applicant door, then the PG applicant door | `student` / `applicant` (also for PG applicants) / the preferred or first staff office | `{kind, home, mustChange, name, office, offices}`; staff `mustChange` → `/account/password`, student → `/student/profile?change=1`, PG applicant → `/pg/portal` |
| `student/sign-in` | `/api/v1/student-auth/sign-in` | `student` | `{matricNo, name, mustChange}` |
| `applicant/sign-in`, `applicant/register`, `applicant/reset` | `/api/v1/applicant/sign-in` · `/register` · `/reset` (all three sign the applicant in) | `applicant` | `{applicationNo, name}` |
| `applicant/forgot`, `forgot`, `reset` | `/api/v1/applicant/forgot` · `/api/v1/auth/forgot` · `/api/v1/auth/reset` | — | pass the API's answer through (forgot always 202) |
| `bootstrap` | `/api/v1/auth/bootstrap` with the secret moved from the body to `X-Bootstrap-Secret` | `registrar` | `{name, offices}` |
| `change-password` | `/api/v1/auth/change-password` with the session's Bearer and `x-reason: password changed by the person` | — | pass-through |
| `sign-out` | `/api/v1/auth/sign-out` with the Bearer, then clears both cookies | — | `{signedOut: true}` |
| `sso/start` | `GET /api/v1/auth/sso/start?redirectUri=<origin>/api/auth/sso/callback` → redirects the browser to the provider; a failure redirects to `/login?sso=<why>` | — | redirect |
| `sso/callback` | `POST /api/v1/auth/sso/callback {code, state, redirectUri}` → cookies → redirect to `/` | first office in the answer | redirect |

The cookie's `maxAge` is computed from the token's `expiresAt` (minimum 60 s), so the browser drops it when the 12-hour session ends.

### 3.9 Cookies

| Cookie | Set by | Attributes (`lib/session.ts cookieOptions`) | Read by |
|---|---|---|---|
| `moaum_session` | the sign-in handlers, bootstrap, applicant register/reset, SSO callback | `httpOnly: true`, `sameSite: "lax"`, `secure` only when `NODE_ENV === "production"`, `path: "/"`, `maxAge` = seconds to `expiresAt` | `proxy.ts`, `sessionToken()` in `api()`, the BFF, the PDF routes; cleared by sign-out and by the proxy on a 401 |
| `moaum_office` | the same handlers (`httpOnly: false`); rewritten by the Shell's office selector as `document.cookie = "moaum_office=<code>; path=/; max-age=31536000; samesite=lax"` followed by `router.refresh()` | readable by the page by design | `api()` and the BFF as `X-Active-Office` |

Switching office changes only the cookie; `platform.session.active_office` keeps the office chosen at sign-in. The API refuses an office the token does not carry, so a tampered cookie yields a 403, not a privilege.

### 3.10 Fonts

IBM Plex is self-hosted. `app/fonts.css` declares five `@font-face` rules over `public/fonts/`: `ibm-plex-sans-latin.woff2` and `ibm-plex-sans-italic-latin.woff2` (variable, weight 400–700), and `ibm-plex-serif-400/600/700-latin.woff2`, each with `font-display: swap` and the Latin `unicode-range`. Neither the build nor a browser reaches Google Fonts (the README's warning about Google Fonts applies to the prototype only). `--sans`, `--serif` and `--mono` fall back to Segoe UI / system-ui, Georgia / Times New Roman and ui-monospace / Menlo / Consolas; no Plex Mono file is shipped, so `--mono` always uses the fallback stack.

---

## 4 Design system

Source of truth: `frontend/src/styles/prototype.css` (imported by `app/globals.css`, which adds the report document styles and a few hardening rules). The values below are copied from that file; a value not in the file is not in the system.

### 4.1 Visual philosophy

The palette is sampled from the University crest — red `#ED1B23`, blue `#2CAAE1`, green `#0CA54E`, charcoal `#221F20` — with a deep teal-blue "chrome" for the sidebar and primary actions. The tone is institutional: white surfaces on a cool grey ground, thin lines, dense tabular data with tabular numerals, uppercase eyebrows, and one accent colour (the crest red) used for rules, badges and danger. Documents (returns, receipts, certificates, the login heading, the brand block) use the serif face; everything else is sans. The crest appears on every generated document, workbook header, email and the sign-in brand panel. There is no dark mode. The sign-in page alone is re-coloured to the University website's navy, red and gold, scoped to `.login-wrap`.

### 4.2 Colour tokens

| Token | Value | Use |
|---|---|---|
| `--chrome` | `#0E3F55` | sidebar, primary buttons, links, table header of documents |
| `--chrome-2` | `#1B5A76` | sidebar dividers, active nav item, office select |
| `--chrome-ink` | `#A8CFE2` | nav item text |
| `--chrome-dim` | `#7FB2CA` | nav group headings, brand subtitle |
| `--chrome-deep` | `#0B3345` | primary button hover (alias) |
| `--sky` | `#2CAAE1` | focus ring, info accent |
| `--sky-bg` / `--sky-line` | `#E8F5FB` / `#B6DDF0` | info notices and pills, secondary buttons |
| `--sky-ink` | `#1F7FA8` | alias for info text |
| `--red` | `#ED1B23` | accent, badges, danger left border, avatar |
| `--red-ink` / `--red-deep` | `#B01218` / `#8E1015` | danger text / deeper hover |
| `--red-bg` / `--red-line` / `--red-wash` | `#FDEAEB` / `#F6BCBF` / `#FFF7F7` | danger notices and pills |
| `--green` | `#0CA54E` | ok accent |
| `--green-ink` | `#0A7A3B` | ok text, `.btn--go` ground |
| `--green-bg` / `--green-line` | `#E6F6ED` / `#A9E0C1` | ok notices and pills |
| `--amber` | `#B7791F` | warn accent (the one colour the crest did not give) |
| `--amber-ink` / `--amber-bg` / `--amber-line` / `--amber-wash` | `#8A5A12` / `#FBF3E2` / `#EFD9A6` / `#FFFBF2` | warn pills and changed fields |
| `--ink` | `#221F20` | body text |
| `--muted` | `#5C6570` | secondary text, table headers |
| `--faint` | `#656E79` | eyebrows, field labels, hints (darkened from `#8A939E` to clear 4.5:1 contrast) |
| `--bg` | `#F4F6F8` | page ground, table header ground |
| `--surface` | `#FFFFFF` | cards, tiles, inputs |
| `--line` / `--line-2` | `#DEE3E8` / `#ECEFF2` | borders / lighter dividers |
| `--field` | `#C3CBD3` | input borders |
| `--disabled` | `#E2E7EC` | disabled controls, tab strip ground |
| `--sunk` | `#F1F4F6` | hovered table row |
| `--scrim` | `rgba(11,51,69,.35)` | (declared for the drawer scrim; the drawer rule itself uses `rgba(20,30,36,.45)`) |
| aliases | `--slate`=`--muted`, `--body`=`--ink`, `--rule`=`--line`, `--panel`=`--surface`, `--panel-2`=`--line-2`, `--tint`=`--sky-bg`, `--chip`=`--bg`, `--ink-3`=`--faint`, `--red-soft`=`--red-bg`, `--link`=`--chrome-2`, `--blue-ink`=`--chrome` | names screens reached for; never a new colour |
| login only | `--u-navy-1 #16305a`, `--u-navy-2 #0d1e3c`, `--u-gold #e2a92f` | scoped to `.login-wrap` |

### 4.3 Typography

| Token / rule | Value |
|---|---|
| `--sans` | `"IBM Plex Sans", "Segoe UI", system-ui, sans-serif` |
| `--serif` | `"IBM Plex Serif", Georgia, "Times New Roman", serif` |
| `--mono` | `"IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` |
| `body` | 14 px / 1.5, `-webkit-font-smoothing: antialiased`, colour `--ink`, ground `--bg` |
| scale | `--t-xs 11.5px`, `--t-sm 12.5px`, `--t-base 14px`, `--t-md 15px`, `--t-lg 17px`, `--t-xl 20px`, `--t-2xl 24px`, `--t-3xl 28px` |
| top bar `h1` | 19 px, weight 700, letter-spacing −0.3 px (harmonised to `--t-xl`); subtitle 12.5 px `--muted` |
| card title | 13.5 px / 700; eyebrow 11 px / 700 / uppercase / `.45px` tracking / `--faint` |
| table header | 10.8 px / 700 / uppercase / `.4px` tracking / `--muted`; cells 13 px |
| tile figure | 29 px / 700 / −0.8 px (24 px under 760 px) |
| login heading | serif, `clamp(26px, 3.4vw, 38px)` / 700 |
| `.tnum` | `font-variant-numeric: tabular-nums` — applied to every identifier and figure |
| phone type floor | nothing below 11.5 px under 760 px (nav group names, brand subtitle raised to 11.5 px) |
| links | `--chrome`, red on hover; inside cards/notices/cells `--link` with underline on hover |
| focus | `outline: 2px solid var(--sky); outline-offset: 2px` |
| motion | `prefers-reduced-motion: reduce` disables every animation and transition |

### 4.4 Spacing, radius and shadow

| Group | Tokens |
|---|---|
| spacing | `--s-1 4px`, `--s-2 8px`, `--s-3 12px`, `--s-4 16px`, `--s-5 20px`, `--s-6 24px`, `--s-7 32px`, `--s-8 40px` |
| radius | `--r-sm 4px`, `--r 6px`, `--r-md 8px`, `--r-lg 12px`, `--r-xl 16px`, `--r-pill 999px` |
| shadow | `--sh-1: 0 1px 2px rgba(14,63,85,.06)`, `--sh-2: 0 4px 14px rgba(14,63,85,.08)`, `--sh-3: 0 12px 32px rgba(14,63,85,.16)` |
| grids | `.grid` gap 14 px; `.grid--2` auto-fit min 280 px, `.grid--3` 240 px, `.grid--4` 190 px, `.grid--5` 160 px, `.grid--fill` auto-fill 200 px |
| content | `.content` padding `22px 24px 40px`, column gap 18 px; `.content--narrow` max 760 px |

Utilities added in the September 2026 harmonisation: `.row` (+ `--tight --top --end --base --right --between --inline`), `.stack`, `.grow`, `.ml-auto`, `.m-0`, `.mt-1..4`, `.mb-1..3`, `.ink-red/.ink-green/.ink-chrome/.ink-muted/.ink-faint`, `.b600 .b700`, `.t-xs..t-lg`, `.hr`, `.eyebrow--gap`, `.sr-only`, `.skeleton`, `.is-loading`.

### 4.5 Buttons

`.btn`: inline-flex, gap 8 px, padding `13px 18px`, radius 8 px, 15 px / 600, min-height 48 px, transition 0.14 s.

| Class | Ground | Text | Hover | Use |
|---|---|---|---|---|
| `.btn--primary` | `--chrome` | white | `#0B3345` | the one main action |
| `.btn--secondary` | `--sky-bg`, border `--sky-line` | `--chrome` | `#DDEFF8`, border `--chrome-dim` | supporting action |
| `.btn--ghost` | `--surface`, border `--field` | `--chrome` | border `--chrome`, ground `--bg` | default for links and table actions |
| `.btn--go` | `--green-ink` | white | `#086A32` | approve / release |
| `.btn--urgent` | `#D6151C` (a shade deeper than the crest red to clear AA under white text) | white | `#B81217` | destructive / urgent |
| `.btn--sm` | padding `8px 13px`, min-height 36 px, 13 px, radius 6 px | | | the size `Btn` emits by default; 44 px under 760 px |
| `.btn--md` | padding `12px 18px`, min-height 44 px, `--t-md`, radius `--r-md` | | | |
| `.btn--icon` | padding `8px 10px`, min-width 38 px; `.is-danger` text `--red-ink` | | | `IcoBtn` |
| `.btn[disabled]` | `--disabled` ground, `--muted` text, `not-allowed` cursor | | | |
| `.btn[aria-disabled="true"]`, `.btn.is-held` | opacity .5, `help` cursor (explains why in `title`) | | | |
| `.btn--block` | full width | | | |

### 4.6 Cards, panels and tiles

- `.card`: `--surface`, 1 px `--line`, radius `--r-lg` (12 px), shadow `--sh-1`. `.card__head` padding `--s-3 --s-4` with a `--line-2` bottom border; `.card__title` 13.5 px / 700; `.card__body` padding `--s-4`, flex column, gap 12 px; `.card__body--row` for a wrapped row; `.card__head--doc` a 2 px chrome rule.
- `.tile`: same surface, radius `--r-lg`, shadow `--sh-1`, padding `16px 17px`, gap 5 px; `.n` the figure, `.c` the caption (12 px `--muted`). Long figures wrap (`overflow-wrap: anywhere`); `Tiles` shrinks the font for long strings.
- `.eyebrow` labels section heads and tile headings.
- The Shell's `.main` is a flex column; `.content` is the scrolling column of cards.

### 4.7 Tables and DTable behaviour

Plain tables: `border-collapse`, full width, `table-layout: auto`; `th` uppercase 10.8 px on `--bg` with a `--line` bottom border, padding `10px 12px`; `td` 13 px, padding `11px 12px`, `--line-2` dividers, middle-aligned, `overflow-wrap: break-word`; the last row has no border; hover ground `--sunk` on `.tbl--data`. Under 1180 px padding tightens to `9px 8px`, fonts to 10.2/12.4 px and long tokens may break anywhere. `.tablewrap` scrolls sideways only as a last resort; the design intent stated in the CSS is that no table scrolls sideways — under 760 px a row becomes a stacked record card with each value under its column name (`data-l` labels, `.tbl--stack`).

`DTable` (`components/proto/DTable.tsx`):
- `cols` are `"Header|num|mid"` strings — the suffix sets `.num` (right-aligned) or `.mid` (centred); the label feeds the stacked layout.
- A search box (`.tsrch`, placed **above** the table) appears when there are more than 8 rows **and** `texts` (one searchable string per row) is given; terms are matched case-insensitively against `texts[i]`. With no match: "Nothing matches *q* in these N rows. Clear".
- Paging: a page size selector 10 / 25 / 50 / 100 / All; the footer (`.tfoot`) shows the count and page controls (`.pg`, `.pg__b`); `pageSize={0}` shows every row (used for server-paged lists that carry their own Previous/Next).
- Sorting: DTable does not sort; rows arrive in the order the page or the API gave them (exports sort names A–Z before numbering).
- A **Print** button (`.tfoot__x`) prints the whole table — hidden rows included — in a hidden iframe with a heading taken from the enclosing card title, the University's name and the date; `noPrint` removes it for tables that are controls inside dialogs.
- Auto-stacking when the table is wider than its wrap.

### 4.8 Forms

- `.field`: flex column, gap 6 px. Inputs, selects and textareas: `font: inherit`, padding `12px 13px`, 1.5 px `--field` border, radius `--r-md`, min-height 46 px; hover border `--muted`; focus border `--chrome` with a 3 px `--sky-bg` ring; `readonly` on `--bg` in `--muted`; disabled styled from `--disabled`. Labels 10.5 px / 700 / `.5px` tracking (11.5 px on phones). `.hint` 12 px `--faint`. `.req` (the required asterisk) `--red-ink`. `.is-error` gives a `--red` border and a `--red-bg` ring.
- `.ctl` is the standalone control class (scope bars, inline selects): the same border and focus rules; `.ctl--ro` a read-only display with an icon; `.ctl.is-changed` an amber border and ring for an edited-but-unsaved value.
- `globals.css` caps a labelled single-line input at 460 px and a `.tnum` numeric input at 200 px so fields do not stretch across a wide panel; textareas, selects and checkboxes keep their width. `.pchk` is a native 16 px checkbox that survives the `.field input` rules; `.chk` a 20 px checkbox on phones.
- Every single-line input, button and pill control is at least 44 px tall under 760 px.

### 4.9 Modals

`.mdl` is a fixed full-screen scrim (`rgba(8,26,36,.62)`, z-index 70, top-aligned, padding `24px 14px 44px`, scrolls). `.mdl__box`: `--surface`, radius 12 px, max-width 560 px (`is-wide` 860 px), shadow `--sh-3` plus `0 24px 60px rgba(6,20,28,.4)`, max-height `calc(100vh - 68px)`, flex column. `.mdl__head` (title 16.5 px / 700, `.mdl__sub` 12.3 px, `.mdl__x` 24 px close), `.mdl__body` (padding `16px 18px`, gap 14 px, scrolls; a `.tablewrap` inside does not shrink), `.mdl__foot` (on `--bg`, radius bottom 12 px). Wizard steps: `.mdl__steps` / `.mdl__st` pills with `.is-on` (sky) and `.is-done` (green) states and a numbered `.mdl__sn` disc. The `Modal` component closes on Escape and on a backdrop click and takes focus.

### 4.10 Pills and notes

`.pill`: inline-flex, gap 6 px, padding `3px 9px`, radius 5 px, 11.5 px / 700; adjacent pills get a 6 px gap.

| Pill | Ground | Border | Text |
|---|---|---|---|
| `.pill--ok` | `--green-bg` | `--green-line` | `--green-ink` |
| `.pill--bad` | `--red-bg` | `--red-line` | `--red-ink` |
| `.pill--info` | `--sky-bg` | `--sky-line` | `--chrome` |
| `.pill--grey` | `--bg` | `--line` | `--muted` |
| `.pill--warn` | `--amber-bg` | `--amber-line` | `--amber-ink` |

`.notice`: radius `--r-lg`, padding `14px 16px`, flex with an 11 px gap and the icon first; `.notice__t` bold title; `p` 13 px / 1.55; `.notice__a` an action row 11 px below. Kinds: `.notice--info` (`--sky-bg`, `--sky-line`, title `--chrome`, text `#124A63`), `.notice--ok` (`--green-bg`, `--green-line`, text `--green-ink`), `.notice--bad` (`--red-bg`, `--red-line`, a 4 px `--red` left border, text `--red-deep`). `.dot` is a 7 px status dot. The `Note` component exposes exactly these three kinds.

### 4.11 Icons

`Ico` renders a 24-unit viewBox SVG with `stroke="currentColor"`, `strokeWidth 1.9`, round caps and joins, default size 17 px. The glyph paths are a static map `I` in `ui.tsx` (home, user, doc, shield, server, scale, eye, eyeoff, edit, trash, swap and the rest of the prototype's set); an unknown name falls back to `doc`. The map is inlined with `dangerouslySetInnerHTML`; its content is compile-time constant, never user data (§5.4). `Tick` and `WarnIcon` are the two coloured status glyphs used in gates and notices. Menu items name their icon by the same key.

### 4.12 Navigation: sidebar and top bar

- `.shell` is a flex row of `.nav` and `.main`, min-height 100 vh.
- `.nav`: 244 px, `--chrome` ground, white text, sticky, 100 vh, its own thin scrollbar (`globals.css`). `.nav__brand` (crest + serif title 14 px + subtitle 10.5 px `--chrome-dim`), `.ws` the "Signed in as" office `<select>` (`.ws__select`, `--chrome-2` ground, custom chevron), `.nav__gh` group disclosure headers (10.6 px uppercase; only the group in use stands open; a red `.gcount` badge sums the group's waiting counts), `.nav__item` (13.5 px, `--chrome-ink`, 42 px, current item on `--chrome-2` in white / 600), `.nav__badge` (red, 10.5 px), `.nav__foot` (avatar — a 34 px red disc with initials —, `.nav__who` name, `.nav__sub` unit, sign-out).
- Collapsed sidebar: `body.nav-slim` narrows `.nav` to 62 px, hides labels, centres icons and floats badges; the toggle is `.nav__slim`. Not applied under 900 px.
- `.topbar`: `--surface`, 1 px `--line` bottom border, padding `12px 24px`, sticky (z-index 20), wraps; holds the `.menu-btn` (hidden on desktop), `.crumb` (group › item, `--t-xs` uppercase `--faint`), `h1` + `.sub`, the identity chip `.topbar__me` (pill with name 12.5 px / 600 and role 11 px, each clipped at 200 px) and the "Search records ⌘/" button (`.topsrch`; the `/` key opens `/search`).

### 4.13 Responsive breakpoints

| Width | What changes |
|---|---|
| ≤ 1180 px | table padding and type tighten; long tokens may break anywhere; the identity chip loses its text (`.topbar__who` hidden) |
| ≤ 900 px | the sidebar becomes an off-canvas drawer (`position: fixed`, slides in under `body.nav-open`, scrim `rgba(20,30,36,.45)`, closes on navigation); `.menu-btn` appears (40 px); the top bar goes static with 16 px padding and loses the chip and breadcrumb; the collapse toggle is hidden and `nav-slim` is undone; content padding `16px 16px 40px`; the login page drops to one column (the two-column grid applies from 900 px up) |
| ≤ 760 px | every `.btn`/`.btn--sm`/menu button/pill control at least 44 px; nav items 46 px; the type floor 11.5 px; tiles two-up (`grid--4` → 2 columns, `grid--2/3` → 1), figure 24 px, padding `13px 14px`; `h1` 17 px; content gap 14 px; `.card__body` and the report paper scroll horizontally as a safety net; rows become stacked record cards; bottom tab bars (`body.has-tabs`) add 96–152 px of bottom padding |
| ≤ 660 px / ≤ 640 px | modal padding `10px 8px 24px`; flow action buttons full width; timelines (`.tl`) narrow to a 72 px label column |
| ≤ 560 px | document key/value grids (`.docsheet .kvs`) go single column |
| ≤ 400 px | `grid--4` becomes one column |

`img { max-width: 100% }` and `.content, .main, .tablewrap { max-width: 100% }` stop any page forcing a horizontal page scroll.

### 4.14 Print styles and documents

`@media print` hides `.shell, .topbar, .nav, .scrim, .login-wrap, .doc-bar` — which is why in-shell printing goes through `printNode()` or DTable's iframe rather than `window.print()`. The document sheet (`.docsheet`) prints at 10.5 pt without shadows or radius; `.rpt` (returns) drops its margins and borders, and table header/zebra colours are forced with `print-color-adjust: exact`. `.no-print` hides toolbars.

Report documents (`.rpt*`, `globals.css`): a 900 px paper with 40/44 px padding; a crest (58 × 60 px) beside the University's serif name (19 px `--chrome`) over a 3 px chrome rule; a serif title (24 px); a table at 12.5 px with white-on-chrome uppercase 11 px headers, zebra rows on `--bg`, a 2 px chrome rule above the totals; a footing note and an "Issued by the portal" line (11 px `--faint`) carrying the serial.

### 4.15 Charts

`components/proto/vz.tsx` ports the prototype's SVG primitives: `Donut` (with a centre caption and click-to-pick), `HBars`, `VBars`, `Stack` (stacked bars with a `Legend`), `Line` (series over labelled x with a y maximum) and `GroupBars`. Charts sit above their own table and read as shape, not as a substitute for figures. Series colours are fixed in `VZ`: `s1 #2a78d6`, `s2 #eb6834`, `s3 #1baf7a`, `s4 #eda100`, `s5 #e87ba4`; status `good #0ca30c`, `warn #fab219`, `crit #d03b3b`; `seq #2a78d6`; `grid #E7EBEF`; `axis #8A939E`. Text uses the text tokens rather than the series colour; arcs are separated by a 2 px surface gap. Styling is `.vz__*` in `prototype.css`.

---

## 5 Security

### 5.1 Authentication

**Password hashing.** Every door hashes with bcrypt at cost 12: `new BCryptPasswordEncoder(12)` in `auth/AuthService`, `auth/PasswordResetService`, `studentportal/StudentAuthService`, `applicant/ApplicantService`, `pgadmissions/PgApplyController`, `pgadmissions/PgPortalController` and `examiners/ExaminersController`. Database-side loaders use `pgcrypto`'s `crypt(…, gen_salt('bf', 12))` (`iam.import_lecturers`, the biography and applicant importers, `db/demo.sql`). CHECK constraints on `iam.credential` and `iam.student_account` require `password_hash LIKE '$2%$12$%'`; the applicant table also admits the migration sentinel `SET_ON_FIRST_LOGIN`. One migration (V176) lowered an importer to cost 10 and the next (V177) restored 12.

**Token issuance.** A sign-in returns an HS256 JWT minted by `auth/TokenIssuer` with the same `MOAUM_AUTH_HMAC_SECRET` the API verifies with (≥ 32 bytes or the API refuses to start). Claims: `sub` (person id, or the applicant/student account id), `iat`, `exp`, `offices` (codes), `sid` (hex of a 32-byte session id), `name`. When the API is instead configured with `MOAUM_AUTH_ISSUER_URI` (Keycloak, RS256 through the issuer's JWKS), `TokenIssuer` has no key and every password door refuses with `AUTH_SIGN_IN_ELSEWHERE`; because the SSO callback also mints its token through `TokenIssuer`, that mode cannot currently sign anyone in (dossier A). The deployed configuration keeps the HMAC secret. Development tokens (`api/scripts/dev-token.mjs`, `TestTokens`) carry no `sid` and are accepted without a session check.

**Sessions and the deploy floor.** `platform.session` (id `bytea` 32 bytes, person, `active_office`, `issued_at`, `last_seen_at`, `absolute_end` = sign-in + 12 h, `ended_at`, `ended_reason`). `SessionGuard.refuse` answers 401 for a session that does not exist, was ended, passed `absolute_end`, or was issued before this API instance started — so every deploy or restart signs everybody out, by design. `GET /api/v1/auth/sessions` and `POST /api/v1/auth/sessions/{hex}/end` let a person list and end their own sessions; no screen calls them, and no endpoint lets the Registrar end another person's session.

**Lockout.** Staff (`AuthService`): `LOCK_AFTER = 5`, `LOCK_FOR = 15 min`; the failure event is written before the refusal in its own transaction so the counter survives the rollback. Students, applicants and PG applicants follow the same 5/15 rule in their own services; the PG door additionally throttles a source after twenty failures in fifteen minutes (`AUTH_THROTTLED`). The failure and success outcomes are logged in `iam.sign_in_event` (staff, with IP), `iam.student_event`, `admissions.applicant_event`.

**Password rules.** Staff: at least 10 characters and not containing the username (`AUTH_PASSWORD_SHORT`, `AUTH_PASSWORD_IS_USERNAME`); a Registry-set credential carries `must_change` and the person is sent to `/account/password`. Student and reset: at least 8. Applicant: at least 8. PG applicant: at least 6 (`PgApplyController`). External examiner activation: at least 10 and not containing the email.

**Reset tokens.** `PasswordResetService` generates a 32-byte token, stores only its SHA-256 in `iam.password_reset` with `expires_at = now() + 1 hour`, resolves the identifier in the order STAFF → STUDENT → APPLICANT → PGAPPLICANT, queues the link by email and SMS, and consumes the token once (`used_at`), clearing the lockout and `must_change`. The applicant module has its own older reset path (`admissions.password_reset`, 24-byte token, one hour) — two reset paths coexist. Forgot always answers 202 so the page cannot enumerate accounts.

**Doors.** Staff (`/api/v1/auth/sign-in`), student (`/api/v1/student-auth/sign-in`: matric or admission number; an applicant account's hash is carried over on first sign-in; a migrated account with `must_change` and no matching hash accepts the student's own number as the password), applicant (`/api/v1/applicant/sign-in`: JAMB number, application number or email), PG applicant (`/api/v1/pg/sign-in`: email or `PG/YY/NNNNNN`), examiner activation (`/api/v1/examiners/activate`, single-use 14-day token). The bootstrap door (`/api/v1/auth/bootstrap`) works once, when `iam.credential` is empty, and requires `X-Bootstrap-Secret` equal to the HMAC secret.

**Keycloak SSO** (`SsoService`, `OidcVerifier`): enabled only when issuer, client id and client secret are all set; signed state (`epoch.nonce.hmac`, 10-minute window); ID token verified against the realm's JWKS (RS256, issuer, audience, expiry, nonce); an `amr` factor among `mfa, otp, hwk, swk, sms, webauthn, fido, totp` or an `acr` level in `MOAUM_SSO_MFA_ACR` is required unless `MOAUM_SSO_REQUIRE_MFA=false`; the person is matched by the `staff_number` claim, else by an existing credential's username/email; an unknown or ended person is refused by name. Coded and unit-tested; **not deployed** (§10.3).

### 5.2 Authorisation

- The token's `offices` claim becomes one `OFFICE_<code>` authority per office. Every controller method is guarded with `@PreAuthorize("hasAnyAuthority('OFFICE_…', …)")` or `isAuthenticated()`. `SecurityConfig` permits only the public list in §9 without a token; everything else is `authenticated()`.
- The acting office (`X-Active-Office`) must be one the token carries; otherwise 403 before any service runs. A request with no office reads and cannot write.
- `OfficeScope` (§2.2) binds department and faculty offices to their unit **where a controller calls it**. It is not in the token and not in the database.
- Grants (`iam.office_assignment`) take effect at the next sign-in; a token carries the offices as of sign-in. Ending a grant does not end an existing token — the examiner module compensates by re-checking `examinerOf()` on each request; other modules do not.
- Any of the six grantor offices (registrar, dregistrar, vc, super, ict, admin) may grant **any** office, including `super` and `ict`, under a free-text instrument; there is no two-person rule.
- `RoleLine` and the `may`/`mayAct` lists in screens are cosmetic: they hide buttons; the API's guard is the control. Where the two disagree, the API wins (the Registrar's "Audit Trail" menu item opens a screen the API refuses; the results chain's stage-to-office map drives only `mayAct`, and any `DESKS` office can advance any stage through the API — dossiers A and E).
- API keys (`apimgmt`) are a register only: nothing authenticates a request by key, and scopes and quotas are never enforced.

### 5.3 CSRF

The API is stateless (`SessionCreationPolicy.STATELESS`) with CSRF protection disabled (`http.csrf(csrf -> csrf.disable())`); it authenticates only by the `Authorization: Bearer` header, which a cross-site form cannot set. The browser never holds the token: it is in the `moaum_session` cookie, which the frontend's route handlers read and forward. What protects the cookie-based BFF and `/api/auth/*` handlers against cross-site requests is therefore the cookie's attributes — `sameSite: "lax"` and `httpOnly: true` (`lib/session.ts`) — not a CSRF token: a cross-origin `POST` from another site does not carry a Lax cookie, and a top-level GET navigation, which does carry it, cannot reach a state-changing handler because the BFF forwards GETs as GETs. There is no anti-CSRF token, no Origin/Referer check, and `SameSite=Strict` is not used. The `moaum_office` cookie is client-writable by design; the API rejects an office the token does not carry. `secure` is set only when `NODE_ENV === "production"`.

### 5.4 Cross-site scripting

React escapes every interpolated value. A grep of `frontend/src` finds exactly one `dangerouslySetInnerHTML`: the `Ico` glyph map in `components/proto/ui.tsx:60`, whose content is a compile-time constant keyed by icon name (`I[name] ?? I.doc`) — no user data can reach it. Server-side HTML is assembled in three places, each escaping its inputs: `SmtpMailer.html()` (`esc()` on subject and body), `DTable`'s print iframe (`esc()` on the heading; the cloned table is DOM the page already rendered), and `exportbrand.brandedPrint()` (`esc()` on every string). The Quickteller start page is server-rendered HTML in the API (`PaymentsService`, *not verified* here for escaping). Uploaded files are served with `Content-Security-Policy: sandbox` and `X-Content-Type-Options: nosniff` in the deferment, help-desk, examiner and PG modules, but inline with the stored content type and without those headers for applicant documents, support-request documents and LMS materials (§2.7) — an HTML or SVG file that slipped past a declared-type check there would render in the portal's origin.

### 5.5 SQL injection

Every repository uses `JdbcClient` with named parameters; values never enter SQL text. A search for string concatenation around `WHERE`/`AND`/`ORDER` finds only fragments assembled from **constants chosen by code**, never from a request value:

| Site | What is concatenated | Verdict |
|---|---|---|
| `admissions/PutmeController.java:332-343` | `stPred`, one of four fixed predicate strings chosen by comparing the `st` parameter to literals; the free-form branch binds `:st` as a parameter | safe |
| `deferments/DefermentsController.java:251-294` | `WITHIN` (a constant) and a `stPred` chosen the same way | safe |
| `allocation/AllocationController.java:76-79` | one of two fixed `WHERE` clauses with `:d` / `:me` parameters | safe |
| `admissions/CapsRepository.java:31-38`, `credentials/CredentialsRepository.java:35-39`, `applicant/ApplicantRepository.java:49-54`, `deferments/DefermentsController.java:91-121` | a constant column list or SELECT prefix plus a constant suffix | safe |
| `credentials/CredentialsRepository.java:131` `"UPDATE credentials.stationery_batch SET " + column + " = " + column + " + :n"` | the column name; its only caller (`CredentialsService.java:241`) passes `"spoiled"` or `"returned"` from a ternary | safe today; would become unsafe if a caller ever passed request input |
| `reports/ReportsController.java:186-191` | a Postgres array literal built from programme names for the carry-over query (dossier A notes it is quoted/escaped) | safe as written; fragile |

No `String.format`/`formatted` SQL was found in repositories. `migrate.sh` interpolates the migration filename into a psql `-c` string, but the names are the repository's own files.

### 5.6 File upload validation

Summarised from §2.7: size limits exist on every upload path (2 MB applicant/support, 4 MB PG photo, 5 MB deferment/help-desk/LMS/examiner private, 8 MB PG document, 25 MB research and examiner project documents). Magic-byte sniffing that must agree with the declared type exists in the deferment, help-desk and examiner modules; the applicant, support and LMS paths trust the declared content type (the applicant path at least restricts it to PDF/JPEG/PNG). Filenames are sanitised where files are served with `Content-Disposition`. Candidate passports are stored as data URLs only up to 64 KB.

### 5.7 Object-level access (IDOR)

Ownership is checked in most student-facing and desk endpoints: every `/me/*` handler keys on the token subject; students reach only their own loans, deferments, tickets, hostel records and documents; the results lecturer endpoints check `own(sheet)`; deferment, SIWES, PG record and examiner reads apply `inBound`/`myAssignment`. The dossiers found these places where it is missing:

| Endpoint / screen | Finding | Source |
|---|---|---|
| `results/HeldScriptsController` — `hold`, `holdBulk`, `withdraw` | no `own`/`teaches` check: any lecturer can hold a script on any sheet id, and a release can add a score to a sheet already past ENTRY | dossier E §C |
| `GET /api/v1/student/students/{id}` and `/{id}/portal` | readable by every READER office for any student id; no `OfficeScope` bound | dossier D |
| `GET /api/v1/student/records/{view}` | scope built from request parameters only (`Scope.of(fac, dept, …)`), unlike `/students` which forces `OfficeScope.bound`; a HOD can read another department's rows by editing the URL | dossier D |
| `GET /api/v1/verify/hostel/{ref}` | public, no check token, no throttle; `ALC-YYYY-NNNNN` is sequential, so names, photographs and room numbers can be enumerated | dossier G |
| `results/*/advance` | any `DESKS` office may advance any stage (the stage→office map is UI-only); a `DESKS` office may publish a single sheet by passing a minute at SENATE | dossier E |
| `pgadmissions/PgCourseworkController` | no HOD department scope; a HOD may endorse/score any PG registration | dossier C |
| `GET /api/v1/college/exams/{code}/assessments` | only `assertLevel`; any EXAMINERS office may read the CA of any College student | dossier E |
| `POST /api/v1/registration/course-registrations` | an APPROVER may create/submit a registration for any student, without menu validation (no UI) | dossier D |
| transfers office list | University-wide for every reader including HOD (server re-checks the stage on write) | dossier D |
| `/api/v1/payments/quickteller/start` | public; reveals reference, amount and payer contact in hidden fields to whoever holds the reference | dossier F |

### 5.8 Rate limiting

In-memory, per API instance, keyed by source IP (`X-Forwarded-For` first hop, else the remote address):

| Door | Limit | Code |
|---|---|---|
| `GET /api/v1/verify/document*`, `/verify/download/{token}` | 40 lookups per 15 minutes per source (`DocumentsController.VERIFY_LIMIT`, `VERIFY_WINDOW_MS`) | `VERIFY_THROTTLED` |
| `POST /api/v1/helpdesk/track` | 12 lookups per 15 minutes per IP and per email (`HelpdeskController.TRACK_LIMIT`) | `HELPDESK_TRACK_SLOW_DOWN` |
| `POST /api/v1/pg/sign-in` | 20 failures per source in 15 minutes | `AUTH_THROTTLED` |

Nothing else is throttled: not the staff, student or applicant sign-in doors, not `/auth/forgot` and `/auth/reset` (the `AUTH_THROTTLED` title exists in `ProblemHandler` but nothing in those doors raises it), not `/applicant/lookup` (which the registration page fires on every keystroke once the number is shaped), not the receipt/exam/registration/results/report/Post-UTME verification endpoints (protected by their check tokens, or in the hostel and Post-UTME cases by nothing), not the payment webhooks. The counters are lost on restart and are not shared across replicas (`numReplicas` is 1).

### 5.9 Audit logging

- **The spine.** 258 of 331 tables are attached to `audit.record`, an `AFTER INSERT OR UPDATE OR DELETE` trigger that refuses a write without `moaum.actor_id`/`moaum.actor_office` (SQLSTATE 23514, HINT "SET LOCAL moaum.actor_id and moaum.actor_office before writing…"), captures `before_state`/`after_state` as JSONB, derives a subject id, and appends to `audit.entries` — partitioned by month (`audit.entries_YYYYMM`, pre-created through 2028-08) and hash-chained per `(period, shard)` with `shard = hashtext(subject) % 16`; `entry_hash = sha256(canonical(entry) || prev_hash)`; `audit.chain_head` holds the last hash and sequence under a row lock. The 47 exempt tables (blobs, credentials, sessions, sign-in events, settings with secrets, the `reporting` schema) each carry a written reason in `audit.exemption` (≥ 20 characters).
- **What verify.sql asserts on every deploy:** no `app_*` role holds DELETE anywhere; no application role can write to `audit.*`; an unattributed insert into `iam.person` is still refused.
- **What is recorded per entry:** actor, acting office, action (the trigger argument or `TG_OP`, domain-prefixed where `audit.attach(table, action)` named one), subject type and id, before/after, reason (`X-Reason`), correlation id, source IP.
- **Sign-in events** are separate logs (`iam.sign_in_event`, `iam.student_event`, `admissions.applicant_event`) and appear on the Audit Trail screen as `auth:<outcome>` rows.
- **Limits.** A refused write is rolled back and leaves no entry (the Audit Trail screen's closing note claims otherwise); only explicit "REFUS…" actions and failed sign-ins appear. `audit.verify_chain(period)` exists but no job runs it — the Security screen's "verified nightly" text is unfounded. `before_state`/`after_state` hold full row JSON (including emails and phones) and are not shown on screen but are readable by the six OVERSIGHT offices through `/api/v1/audit/entries`. Every search for a person writes `people.search_log`; every opening of a clinic record writes the health access log.

### 5.10 Data privacy

- **NDPA register** (`governance` module): `governance.processing_activity` (seven seeded activities with DPIA states; no endpoint adds or edits one), `governance.dsr` (data-subject requests with 30-day due dates; the REFUSED state is unreachable from the screen), `governance.dr_drill`. See *02 Administrator Manual*.
- **Money columns stripped.** `StudentStatsController` removes `payable`, `paid_amount`, `outstanding` and `last_reference` for offices outside its `MONEY` list before answering; return views are cut to the office's scope by `OfficeScope.reportScope()`.
- **Public fields per policy.** Public document verification copies out only the policy's `public_fields` (`credentials.verify_document`); the public answers for receipts, exam cards, registration forms and results return what the endpoint states and no more; helpdesk tracking returns no names.
- **O'Level screening scores** are withheld from every office but the Academic Office; the applicant never sees them.
- **Clinical notes** never leave the health module; other offices see only a fitness status.
- **What is exposed.** `/api/v1/platform/status` (public) discloses the commit, start time, migration count and latest migration filename. `GET /iam/persons` exposes username, lock state and last sign-in to seven reader offices including Internal Audit. The sample data in the repository is invented (README: no real name, registration number, photograph or result appears; the JAMB fixtures with real candidates are outside the repository and their seven checks are skipped when absent).

### 5.11 Document security

- A digital document (`credentials.issued`, V262) keeps its statement byte for byte with a **SHA-256 hash, not a cryptographic signature** — the migration itself says the University has no signing key in custody; `credentials.signing_key` is empty and `signed_with` nullable. Verification recomputes the hash and answers `INVALID` when it no longer matches.
- Every document carries a Crockford verification code and a number `CERT/TRN/STR/MTR/ASR-YYYY-NNNNNN`; the public door answers `VALID`, `REVOKED`, `REPLACED` or `NOT_FOUND` with public fields only, logs every lookup with IP and user agent, and tracks suspected forgeries (three misses in 30 days).
- Secure links (`/documents/d/{token}`) spend a 192-bit token with an expiry and a use limit; a re-sent link expires in 30 days.
- Revocation is by the Registrar or the Vice-Chancellor citing a minute; reissue creates a new version and the old verifies `REPLACED`; a REVOKED or REPLACED PDF prints with a diagonal watermark; a result or award change after issue flags the document.
- QR check codes on receipts, exam cards, registration forms, results statements and kept returns are stateless truncated SHA-256 tokens over the record's identifiers; without the code the public pages answer `genuine: false`. Two QR codes point at nothing: the PG offer letter's (`MOAUM PG {applicationNo}`, no endpoint) and the deferment letter's `/verify/deferment` (dossiers C and D).

### 5.12 Secrets handling

- Secrets reach the API only as environment variables (§6.1); none is in `application.properties` beyond empty defaults, and the frontend has no secret other than the optional development token.
- Gateway keys, the mail password and the eBulkSMS key set from the dashboard are encrypted at rest with `pgp_sym_encrypt` under `MOAUM_CONFIG_KEY` (falling back to `MOAUM_AUTH_HMAC_SECRET`) by the SQL functions in V039/V052/V057/V065; the reader functions decrypt inside the database only for the dispatcher and the payments service; every screen learns only "set / not set" and the last four characters. Their tables are audit-exempt so the trail never carries a secret; the SET/ROTATED/CLEARED events are on the spine.
- API keys (`apimgmt.key`) store `sha256(key)` and `last4`; the plaintext `mk_<48 hex>` is shown once.
- Reset and activation tokens are stored hashed. Session ids are random 32-byte values.
- The bootstrap secret is the HMAC secret itself, sent once in a header and never stored.
- The demo password is printed in `docs/demo-accounts.md` and by `db/demo.sh`; the demo data is meant to be removed before go-live ("Remove demo data only" on the platform dashboard; the Readiness screen checks for it).

### 5.13 HTTP response headers

`next.config.ts` sets no `headers()`; no security headers (`Content-Security-Policy`, `Strict-Transport-Security`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`) are emitted by the frontend, and a grep of `frontend/src` finds none set by hand. The API sets `X-Correlation-Id` on every response and, per endpoint, `X-Content-Type-Options: nosniff` and `Content-Security-Policy: sandbox` on the file downloads listed in §2.7. Spring Security's defaults for a resource server (cache-control, `X-Content-Type-Options`, `X-Frame-Options: DENY` on API responses) apply to the API only and are *not verified* here against the running service. Railway terminates TLS in front of both services; HSTS at the edge is Railway's setting, not the repository's (*not verified*).

### 5.14 Security gaps

| # | Gap | Where | Severity (assessed) | Suggested remedy |
|---|---|---|---|---|
| 1 | Public hostel verification enumerable: sequential `ALC-` reference, no token, no throttle; returns name, photo, room | `verify/VerifyController.java:369-394` | High | add a check token to the QR (as receipts do) and throttle |
| 2 | No rate limit on staff/student/applicant sign-in, forgot, reset, `applicant/lookup`, Post-UTME slip verification, webhooks | `auth`, `studentportal`, `applicant`, `verify` | High | a per-source limiter like `DocumentsController`'s; ideally at the edge |
| 3 | Held scripts: no ownership check; release can bypass the approval chain | `results/HeldScriptsController` | High | call `own(sheet)`; refuse release past ENTRY |
| 4 | `/students/{id}`, `/students/{id}/portal`, `/student/records/{view}` not office-bound | `student/StudentController` | Medium | apply `OfficeScope.bound` as `/students` does |
| 5 | Approval-chain stage→office rule enforced only in the UI | `results` | Medium | enforce `Sheets.DESK` in the controller or `assessment.advance` |
| 6 | Uploaded files trusted by declared type and served inline without `nosniff`/sandbox (applicant, support, LMS) | `applicant`, `support`, `lms` | Medium | sniff as the deferment module does; add the two headers |
| 7 | No frontend security headers (CSP, HSTS, frame, referrer) | `next.config.ts` | Medium | add `headers()` |
| 8 | Any grantor may grant any office (incl. `super`, `ict`); no two-person rule | `iam` | Medium | policy decision; at least alert on platform grants |
| 9 | Grants and suspensions do not affect existing tokens for up to 12 h (except examiners) | `SecurityConfig`, `AuditContextFilter` | Medium | re-read `iam.live_offices` on each request or shorten sessions |
| 10 | Document "signature" is a hash; no signing key | `credentials` (V262) | Medium | acquire and integrate a signing key |
| 11 | Development bypass (`PORTAL_API_TOKEN`) honoured whenever `NODE_ENV !== "production"` | `proxy.ts`, `lib/session.ts`, BFF | Low | fine in Railway (production build); never run a non-production build on a public host |
| 12 | Predictable first passwords for imported lecturers (`P<PNO>`) and migrated students (own number) until changed | `iam.import_lecturers`, `iam.set_migrated_default_passwords` | Low–Medium | force change on first sign-in (done) and communicate; expire unused defaults |
| 13 | Sessions list/end has no UI; Registrar cannot end another's session | `auth` | Low | build the screen; add a Registrar endpoint |
| 14 | Nightly chain verification claimed but not scheduled | `governance` screen text | Low | schedule `audit.verify_chain` or remove the claim |
| 15 | In-memory throttles vanish on restart and do not span replicas | `DocumentsController`, `HelpdeskController`, `PgPortalController` | Low | move to the database or the edge if replicas grow |
| 16 | Issuer-URI mode (Keycloak-only) cannot issue portal tokens | `TokenIssuer` | Low (mode unused) | issue with a portal key independent of the verifier |
| 17 | `/api/v1/platform/status` public disclosure of commit and migration name | `platform` | Low | accept, or guard behind a token |
| 18 | `platform.session.active_office` not updated on office switch | `Shell.tsx` | Info | audit still uses the header; cosmetic |

---

## 6 Configuration and environment

### 6.1 API service variables

Read through `application.properties` placeholders or `@Value` defaults. Spring's relaxed binding maps a property `moaum.x.y-z` to the environment variable `MOAUM_X_YZ` as well as the spelt-out forms shown; the names below are the ones the code and documentation use.

| Variable | Property | Default | Purpose |
|---|---|---|---|
| `PORT` | `server.port` | `8081` | listening port; Railway sets it (the README fixes it at 8081 so the frontend finds it on the private network) |
| `DATABASE_URL` | parsed by `DatabaseUrlConfig` into `JdbcConnectionDetails` | — | `postgres://user:pass@host:port/db` in Railway's shape; takes precedence over the three below; required by `db/migrate.sh` |
| `JDBC_DATABASE_URL` | `spring.datasource.url` | `jdbc:postgresql://localhost:5432/moaumpp` | alternative to `DATABASE_URL` |
| `PGUSER` / `PGPASSWORD` | `spring.datasource.username` / `password` | `postgres` / `postgres` | with `JDBC_DATABASE_URL` |
| `DB_POOL_SIZE` | `spring.datasource.hikari.maximum-pool-size` | `10` | Hikari pool size |
| `MOAUM_AUTH_HMAC_SECRET` | `moaum.auth.hmac-secret` | empty | ≥ 32 bytes; verifies and issues HS256 tokens; the bootstrap secret; the SSO state key; the fallback config key. One of this or the issuer URI is mandatory |
| `MOAUM_AUTH_ISSUER_URI` | `moaum.auth.issuer-uri` | empty | Keycloak issuer for RS256 verification (see §5.1 caveat) |
| `MOAUM_CONFIG_KEY` | `moaum.config.key` (default `${moaum.auth.hmac-secret}`) | the HMAC secret | passphrase for `pgp_sym_encrypt` of gateway keys, mail password, SMS key |
| `MOAUM_PORTAL_URL` | `moaum.portal-url` | `https://moaum-portal-production.up.railway.app` | links in notices, the crest in emails, verification URLs |
| `MOAUM_API_URL` (*relaxed name not verified*; property `moaum.api-url`) | `moaum.api-url` | empty | the API's public address for gateway callbacks (`PaymentsService`) |
| `MOAUM_COMMIT` / `RAILWAY_GIT_COMMIT_SHA` | `moaum.commit` | — | shown on `/api/v1/platform/status` and the platform dashboard |
| `MOAUM_NOTICES_EMAIL_URL` | `moaum.notices.email-url` | empty | HTTP relay for email (fallback to SMTP settings) |
| `MOAUM_NOTICES_SMS_URL` | `moaum.notices.sms-url` | empty | HTTP relay for SMS (fallback to eBulkSMS settings) |
| `MOAUM_NOTICES_TOKEN` | `moaum.notices.token` | empty | bearer for the relays; the `api_key` in the Termii payload |
| `MOAUM_NOTICES_SMS_FORMAT` | `moaum.notices.sms-format` | `generic` | `generic` or `termii` |
| `MOAUM_NOTICES_SMS_FROM` | `moaum.notices.sms-from` | `MOAUM` | Termii sender id |
| `MOAUM_NOTICES_EMAIL_FORMAT` | `moaum.notices.email-format` | `generic` | `generic` or `resend` |
| `MOAUM_NOTICES_EMAIL_FROM` | `moaum.notices.email-from` | `MOAUM Portal <portal@moaum.edu.ng>` | Resend from address (SMTP uses the Mail-server screen's From) |
| `MOAUM_NOTICES_EVERY_MS` | `moaum.notices.every-ms` | `60000` | dispatcher cadence |
| `MOAUM_NOTICES_INITIAL_MS` | `moaum.notices.initial-ms` | `15000` | first dispatch after start |
| `MOAUM_SSO_ISSUER` | `moaum.sso.issuer` | empty | Keycloak realm address; SSO is off until issuer, client id and secret are all set |
| `MOAUM_SSO_CLIENT_ID` | `moaum.sso.client-id` | empty | e.g. `moaum-portal` |
| `MOAUM_SSO_CLIENT_SECRET` | `moaum.sso.client-secret` | empty | confidential client secret |
| `MOAUM_SSO_REQUIRE_MFA` | `moaum.sso.require-mfa` | `true` | refuse a sign-on without a second factor |
| `MOAUM_SSO_MFA_ACR` | `moaum.sso.mfa-acr` | `mfa,otp,2fa,gold,silver` | ACR levels accepted as a second factor; also requested as `acr_values` |
| `MOAUM_SSO_STAFF_CLAIM` | `moaum.sso.staff-claim` | `staff_number` | claim matched to `iam.person.staff_number` |
| `MOAUM_SSO_LABEL` | `moaum.sso.label` | `Sign in with the University's single sign-on` | the button's wording |
| `MOAUM_PAYSTACK_SECRET` | `moaum.payments.paystack-secret` | empty | Paystack secret key (a dashboard-set key wins) |
| `MOAUM_FLUTTERWAVE_SECRET` | `moaum.payments.flutterwave-secret` | empty | Flutterwave secret key |
| `MOAUM_FLUTTERWAVE_HASH` | `moaum.payments.flutterwave-hash` | empty | the webhook `verif-hash` |
| (property only) | `moaum.payments.quickteller-config` | empty | JSON `{clientId, clientSecret, merchantCode, payItemId, sandbox}`; normally set from the dashboard |
| (property only) | `moaum.payments.sweep-every-ms` | `600000` | payments sweep cadence |
| (property only) | `moaum.deferments.cron` | `0 20 6 * * *` | deferment clock |
| (property only) | `moaum.hostel.cron` | `0 5 * * * *` | hostel clock |
| `JAVA_TOOL_OPTIONS` | (JVM) | `-XX:MaxRAMPercentage=75 -XX:+UseSerialGC -Djava.security.egd=file:/dev/./urandom` (set in `api/Dockerfile`) | sizes the JVM to the container |

Fixed observability settings: `management.endpoints.web.exposure.include=health,info`, `management.endpoint.health.probes.enabled=true`, `management.endpoint.health.show-details=never`, `spring.jackson.default-property-inclusion=non_null`, `spring.mvc.problemdetails.enabled=true`.

### 6.2 Frontend service variables

| Variable | Default | Purpose |
|---|---|---|
| `PORTAL_API_URL` | `http://localhost:8081` | where the API is; server-side only; on Railway `http://moaum-api.railway.internal:8081` (private network, IPv6 — hence `HOSTNAME="::"` in the image) |
| `PORTAL_API_TOKEN` | empty | development only: a token minted with `dev-token.mjs`; used when there is no session cookie and `NODE_ENV !== "production"`; also lets `proxy.ts` through without a cookie in that case |
| `PORTAL_ACTIVE_OFFICE` | `academic` in `.env.example` | development only: the office when no cookie names one |
| `PORT` | `3000` (image) | listening port |
| `HOSTNAME` | `::` (image) | bind both stacks |
| `NODE_ENV` | `production` (image) | switches on `secure` cookies and switches off the development bypass |
| `NEXT_TELEMETRY_DISABLED` | `1` (image) | |

There is no `NEXT_PUBLIC_*` variable; nothing about the API's address reaches the browser.

### 6.3 Prototype service variables

`PORT` (8080 in the image) and, optionally, `DATABASE_URL` for `/healthz` and `/readyz` only; the prototype's pre-deploy command must be empty (it no longer migrates).

### 6.4 Railway services

One project, four services, each built from the repository root with its own config file (README "Deploying on Railway"). There is deliberately no `railway.json` at the root.

| Service | Config | Image | Pre-deploy | Health check | Restart | Variables (by reference where possible) |
|---|---|---|---|---|---|---|
| `Postgres` | — | Railway's | — | — | — | — |
| `moaum-api` | `api/railway.json` | `api/Dockerfile` | `bash db/migrate.sh` (**the only service that migrates**) | `/actuator/health`, timeout 300 s | ON_FAILURE × 5, 1 replica | `DATABASE_URL=${{Postgres.DATABASE_URL}}`, `PORT=8081`, `MOAUM_AUTH_HMAC_SECRET` (sealed), the `MOAUM_*` settings above |
| `moaum-portal` | `frontend/railway.json` | `frontend/Dockerfile` | — | `/`, timeout 120 s | ON_FAILURE × 5, 1 replica | `PORTAL_API_URL=http://moaum-api.railway.internal:8081` (README also lists `PORTAL_API_TOKEN` and `PORTAL_ACTIVE_OFFICE` from the pre-session era; in a production build they are ignored) |
| `moaum-prototype` | `web/railway.json` | root `Dockerfile` | empty | `/healthz`, timeout 60 s | ON_FAILURE × 5, 1 replica | `DATABASE_URL` for the health check only |

Settings per service: Config-as-code path set to the file above, Root Directory empty, watch paths (`api/**` and `db/**`; `frontend/**`; `proto/**`, `public/**`, `web/**`), and **Wait for CI** on. Where the config-file setting does not take, `RAILWAY_DOCKERFILE_PATH` chooses the image. A reference points at a service by id: recreate the references if a service is deleted and recreated. The API service needs a superuser-capable Postgres because V001 creates the `app_*` roles.

### 6.5 Ports, health checks and the database pool

| Service | Port | Health | Pool |
|---|---|---|---|
| API | 8081 | `/actuator/health` (Railway), `/api/v1/platform/status` (dashboard) | Hikari, maximum `DB_POOL_SIZE` (10); the pool connects lazily so the context starts without a database |
| Frontend | 3000 | `/` (Railway), `/healthz` (a JSON pulse) | none (HTTP to the API) |
| Prototype | 8080 | `/healthz` lenient, `/readyz` strict | none (shells out to `psql`) |
| Postgres | 5432 | Railway | — |

The migrations and `verify.sql` run through `psql` from inside the API image, not through the JVM's pool.

---

## 7 Deployment and CI/CD

### 7.1 The CI gates

`.github/workflows/ci.yml` runs on every push and pull request to `main` and on manual dispatch, with per-ref concurrency (a newer run cancels the older). Five jobs:

| Job | Name in the workflow | Steps | What a failure means |
|---|---|---|---|
| `web` | "Prototype — build reproducible, 11 harnesses green" | Node 22, Python 3.12, Playwright 1.49.1 + Chromium; `node proto/runall.mjs` (rebuild from the 56 parts and run the eleven browser harnesses: 600+ screen loads, every office, every route, five viewport widths, every control bound); then `python3 proto/build.py` and a byte-for-byte `diff` of `proto/moaum-portal-prototype.html` against `public/index.html` | someone edited the built page, or a harness found a screen defect |
| `db` | "Database — migrations apply, 63 properties hold" | `postgres:17` service; `bash db/migrate.sh`; a second run must print `0 applied`; append a line to `V009` and the runner must **refuse**; `psql -f db/check.sql` must print `FOUNDATION GREEN`; `psql -v ON_ERROR_STOP=1 -f db/verify.sql`; `bash db/demo.sh` twice then `verify.sql` again | a migration does not apply, the ledger is not holding, the demo data is not idempotent, or the read-only verification raises |
| `api` | "API — compiles, module boundaries hold, integration tests green" | Temurin 21 (Maven cache); `bash db/migrate.sh`; `./mvnw -B -ntp verify` with `DATABASE_URL` set (unit tests, `ModularityTests`, all `*IT`) | a compile error, a module boundary crossed, or a journey test failing against the real schema |
| `frontend` | "Frontend — reads a spreadsheet, lints, type-checks, builds" | Node 22 (npm cache); `npm ci`; `npm test`, `npm run lint`, `npm run build` with `PORTAL_API_URL=http://localhost:8081` | a unit test, a lint rule (§3.6), a type error or a build failure |
| `image` | "Containers — the three images build, migrate, serve, answer" (needs `web`, `db`, `api`) | build the prototype image, migrate from inside it, start it, poll `/readyz` for `"reachable": true` and `GET /` for `MOAUM`; build the API image, run `migrate.sh` from inside it (must say `0 applied`), start it with a CI secret, poll `/actuator/health`, read `/api/v1/platform/status` (`"reachable":true`), assert `/api/v1/iam/me` → 401 without a token; build the frontend image, start it against the API, assert `GET /` → 307/302 and `/login` renders "Sign in", bootstrap `ci-boot` through `/api/v1/auth/bootstrap`, sign in through `/api/auth/sign-in` as `ict`, assert the platform dashboard ("What is actually true"), the Registrar dashboard with `moaum_office=registrar` ("Registry business"), and that the latest `db/V*.sql` filename is rendered | an image does not build, the runner misbehaves inside the image, or the three services do not talk to each other |

The `frontend` job is not a prerequisite of `image`; all five must pass for the commit to count as green.

> **Warning:** the `db` job's `FOUNDATION GREEN` grep is vacuous today. Three `DO` blocks in `db/check.sql` end with `END $;` instead of `END $$;`, so from the fifteenth block the file is mis-parsed, most assertions never run, the verdict `SELECT` errors, and psql's echo of the failing statement contains the words the grep looks for. On a fresh local cluster only 14 assertions PASS and the office-register property FAILs (`n = 31` against 34 offices). The `\set EXPECTED 149` count is therefore not what runs. Treat `check.sql` as **not gating** until it is repaired (fix the three terminators, work through the properties that then really run, correct `EXPECTED`, and make the CI step test the verdict line itself). `verify.sql`, which is what protects a real deployment, is unaffected.

### 7.2 Deploy on green

Railway's **Wait for CI** setting on each service means a push to `main` deploys only after the workflow passes. A deployment then builds the image from its Dockerfile, runs the pre-deploy command (for the API, `bash db/migrate.sh`, which also runs `verify.sql`), starts the container and waits for the health check within its timeout. A failed deployment leaves the previous one serving: a service that looks unchanged from outside may have a failed deployment behind it — the Deployments tab is where the truth is. Because every API restart moves the session floor, a deploy signs every staff member and student out ("The portal was updated. Sign in again.").

### 7.3 The migration ledger

`db/migrate.sh` keeps `public.schema_migration (filename PK, sha256, applied_at, applied_by)`. For each `db/V*.sql` in name order: already recorded with the same SHA-256 → skipped; never recorded → applied with `psql -v ON_ERROR_STOP=1` in its own transaction and recorded; **recorded with a different SHA-256 → the script prints both hashes and exits 1, stopping the deployment by name**. It then runs `verify.sql`. The rule for developers is therefore absolute: a `V*.sql` that has been pushed is immutable; a correction is a new file with the next number. (Verified in practice in this repository when an edit to V224 blocked every deploy until the file was restored and the fix moved to V228.) Migration numbering has gaps (V014, V015 are absent; 261 files up to V263), which the ledger tolerates because it keys on filename. The Data Migration screen (`/migrations`) shows the ledger read-only.

### 7.4 Rollback reality

There are **no down migrations**. A migration cannot be reversed by the runner; the only way back is a new forward migration that undoes the change, or a database restore. Application images can be rolled back in Railway to a previous deployment, but the schema stays at whatever the last successful `migrate.sh` left it, so a rolled-back API must be compatible with a newer schema (the additive style of most migrations helps; a column drop or rename would not). Backups are Railway's; the portal records DR drills (`/disaster-recovery`) but has no backup telemetry, and the RPO/RTO figures on that screen are typed targets, not measurements. Before a risky migration, take a Railway database snapshot and rehearse the file on the local cluster (§7.5).

### 7.5 Local development setup

From `README.md` and `api/README.md`:

```bash
# the prototype page
npm run build                 # rebuild public/index.html from proto/part*.html (python build.py)
npm start                     # serve it on :8080

# the database (any Postgres 17/18; the runner needs psql on PATH)
createdb moaumpp
export DATABASE_URL=postgres:///moaumpp
npm run migrate               # bash db/migrate.sh — applies V001…V263, then verify.sql
npm run check:db              # db/check.sql — WRITES; use a throwaway database
bash db/demo.sh               # the invented demo accounts (docs/demo-accounts.md)

# the browser harnesses (needs playwright + chromium)
node proto/runall.mjs

# the API (Java 21; Maven comes with the wrapper)
export MOAUM_AUTH_HMAC_SECRET='change-me-to-at-least-thirty-two-bytes-long'
(cd api && ./mvnw spring-boot:run)          # :8081
curl -s localhost:8081/api/v1/platform/status
TOKEN=$(node api/scripts/dev-token.mjs --secret "$MOAUM_AUTH_HMAC_SECRET" --offices academic,registrar)
curl -s -H "Authorization: Bearer $TOKEN" -H "X-Active-Office: academic" localhost:8081/api/v1/iam/me
(cd api && ./mvnw verify)                   # unit + boundary tests; *IT skip without DATABASE_URL
(cd api && DATABASE_URL=postgres://… ./mvnw verify)   # …and the journey tests

# the frontend (Node 22)
(cd frontend && cp .env.example .env.local && npm ci && npm run dev)   # :3000
(cd frontend && npx tsc --noEmit -p . && npx eslint src)             # what CI will run
```

On Windows, `python` is found automatically and the prototype build folds CRLF to LF so the page is byte-identical to CI's. Where the machine's Postgres password is unknown, a private trust-auth cluster on another port reproduces CI's `db` job (initdb with `--auth=trust`, `port = 5433`, `createdb moaumpp`, then `migrate.sh`, `check.sql`, `verify.sql`, `demo.sh` against `postgres://postgres@localhost:5433/moaumpp`). Run every new migration there before pushing: CI logs need a GitHub sign-in to read, so a blind push costs a round trip per guess.

With `.env.local` holding a `PORTAL_API_TOKEN`, the frontend acts as the token's person and `PORTAL_ACTIVE_OFFICE` without signing in; with the variable empty, sign in at `/login` with a demo account (the roster is `docs/demo-accounts.md`; the password is printed there and not repeated in this manual) or bootstrap the first account at `/login/first` with the HMAC secret.

---

## 8 Database architecture summary

The full catalogue is *08 Database Reference* (331 tables, 26 schemas, status columns, columns). The shape, for orientation:

- **Schemas.** `admissions` (67 tables: CAPS, applicants, screening, Post-UTME CBT, PG applications and research), `apimgmt` (2), `assessment` (10: scores, sheets, results, GPA, standing), `audit` (27: the spine and its partitions), `catalogue` (5), `clearance` (2), `college` (28: MB;BS), `credentials` (15), `expenditure` (10), `extexam` (14), `finance` (21), `governance` (3), `health` (5), `helpdesk` (8), `hostel` (20), `hrm` (13), `iam` (8), `library` (5), `lms` (6), `people` (21: students, contacts, status changes, matriculation, deferments, transfers), `platform` (13: notices, numbering, settings), `policy` (9: sessions, grading, progression), `records` (1), `ref` (13), `registration` (3), `reports` (2); plus `public` for the migration ledger and legacy import staging.
- **Roles.** V001 creates one `app_*` role per module; `verify.sql` asserts on every deploy that none holds DELETE anywhere and none can write to `audit.*`. Nothing in the system deletes; a correction is a new version with a reason. (The API connects as the Railway superuser today; the role grants are a stated boundary rather than the connection's identity — *not verified* which role the pool uses in production.)
- **The audit spine.** 258 attached tables, 47 exempt with written reasons, one trigger (`audit.record`), monthly partitions × 16 hash-chained shards, `audit.chain_head`, `audit.verify_chain`, `audit.unattached()`, `audit.exemption`. See §5.9.
- **Functions as business logic.** Rules that must hold for every caller are SQL functions and triggers, with messages and HINTs written for a person: `admissions.applicant_lookup`/`register_applicant`, `admissions.application_stage`, `finance.confirm_payment`, `finance.payment_position`, `policy.clears`/`policy.in_force`, `assessment.advance`, `people.roll_over_session`, `platform.queue_notice`, `platform.next_number`, `platform.reset_operational_data`, `credentials.verify_document`, `iam.live_offices`, `iam.end_grant`, `reports.due_register`, `reporting.student_positions`, the deferment gate triggers, and many more. The API passes their refusals through as 422 `DATABASE_RULE_REFUSED`.
- **Write-once tables.** Event and history tables are append-only by trigger or by grant: `iam.credential_event`, `iam.sign_in_event`, the matriculation issue history (V263), `putme_event`, `pg_application_event`, `pg_research_event`, ticket histories, `finance.gateway_event` (append with a resolve), `reports.snapshot` (write-once except the filing columns), `credentials.issued` (versioned, never overwritten), `audit.entries`.
- **Numbering.** `platform.number_series` and `platform.next_number(kind, scope, session)` hand out application numbers (`APP/YY/NNNNNN`), PG application numbers (`PG/YY/NNNNNN`), receipts (`RCT-YYYY-NNNNN`), transcripts (`TRN-YYYY-NNNNN`), DSR references (`DSR-YYYY-NNNN`), document numbers (`CERT/TRN/STR/MTR/ASR-YYYY-NNNNNN`), hostel allocations (`ALC-YYYY-NNNNN`) and the matriculation series (V263: `MOAU/{FACULTY}[/{PROGRAMME}]/{YY}/{SEQUENCE}` from a named series the faculty or programme belongs to, locked for the issue, never reused). Payment references are `MOAUM-FEE-<7 chars>-<4 digits>` generated with collision retry.
- **Status columns.** State machines are CHECK constraints (`ck_*_state`) listed per table in *08 Database Reference*; several allowed states have no writer (see §11).

---

## 9 API architecture summary

The full table of endpoints is *07 API Reference* (918 endpoints grouped by module, with the guard constants as "Who may call"). The conventions:

- **Base and versioning.** Everything is under `/api/v1/...`; the BFF forwards only that prefix. There is no OpenAPI document in the repository; the reference is generated from the controllers.
- **Authentication.** `Authorization: Bearer <JWT>`; `X-Active-Office` chooses the acting office among the token's; `X-Reason` is recorded; `X-Correlation-Id` is accepted, echoed and generated; `Idempotency-Key` is forwarded by the BFF but not consumed.
- **Problem format.** RFC 9457 `application/problem+json` with `status`, `title`, `detail`, `instance`, `correlationId`, `code`, optional `remedy {message, office}`, optional `violations[]`, optional `sqlstate` (§2.11).
- **Public endpoints** (`SecurityConfig.permitAll`): `/actuator/health`, `/actuator/health/**`, `/api/v1/platform/status`, `/api/v1/auth/sign-in`, `/bootstrap`, `/offices`, `/forgot`, `/reset`, `/sso`, `/sso/start`, `/sso/callback`, `/api/v1/applicant/lookup`, `/register`, `/sign-in`, `/forgot`, `/reset`, `/api/v1/payments/webhook/paystack`, `/webhook/flutterwave`, `/webhook/quickteller`, `/api/v1/payments/quickteller/start`, `/api/v1/student-auth/sign-in`, `/api/v1/pg/apply`, `/pg/programmes`, `/pg/status`, `/pg/sign-in`, `/pg/referee/**`, `/api/v1/verify/**`, `/api/v1/helpdesk/track`, `/api/v1/examiners/invitation/*`, `/api/v1/examiners/activate`. Public writes run under an explicit `AuditContext` with actor `NOBODY` and an office such as `applicant` or `bursar`.
- **Webhooks.** Paystack: HMAC-SHA512 of the raw body with the secret must equal `x-paystack-signature`, else 401 and a `BAD_SIGNATURE` event; only `charge.success` is read. Flutterwave: `verif-hash` must equal the configured hash. Quickteller: the notification is never trusted; the reference is re-queried. Every callback is a hint; settlement happens only on a verified amount at least equal to what is owed, through the same `confirm_*` functions the Bursary uses.
- **Reads and writes.** Reads need a token and (where guarded) an office; writes additionally need an acting office or the database refuses them. Lists that can be large are paged server-side (`LIMIT :n OFFSET :o`, sizes ≤ 500) or capped (`LIMIT 2000`, `LIMIT 600`).
- **Money.** Amounts are numeric in naira; the statistics endpoints strip money columns for non-money offices.

---

## 10 Integrations

Every integration is off until configured, and the portal says so on screen rather than pretending.

### 10.1 Payment gateways

Module `payments` (`PaymentsService`, `PaymentsController`, `PaymentsRepository`); keys in `finance.gateway_credential` (encrypted, dashboard-set; a service variable is the fallback).

| Gateway | Hosts in code | Checkout | Confirmation paths | Status |
|---|---|---|---|---|
| **Paystack** | `https://api.paystack.co/transaction/initialize`, `…/transaction/verify/{ref}` | hosted page; amount in kobo; needs the payer's email | webhook (HMAC-SHA512 signature), verify on request, the 10-minute sweep | IMPLEMENTED and tested (`PaymentsIT`: a signed webhook confirms once, an unsigned one is refused) |
| **Flutterwave** | `https://api.flutterwave.com/v3/payments`, `…/v3/transactions/verify_by_reference?tx_ref=` | hosted page | webhook (`verif-hash`), verify, sweep | IMPLEMENTED; hash and unknown-reference paths tested |
| **Quickteller Business (Interswitch)** | pay: `https://newwebpay.interswitchng.com/collections/w/pay` (sandbox `newwebpay.qa.…`); requery: `https://webpay.interswitchng.com/collections/api/v1/gettransaction.json` (sandbox `qa.interswitchng.com/…`) | a server-rendered start page (`/api/v1/payments/quickteller/start`) posts to the hosted page; hash = SHA-512(clientId + reference + clientSecret) | notification re-queried, verify, sweep | IMPLEMENTED, **unverified against live**: code comments say the hash inputs and hosts must be **confirmed on merchant onboarding** |
| **Quickteller PayDirect** | query: `https://webpay.interswitchng.com/paydirect/api/v1/gettransaction.json` (sandbox `qa.interswitchng.com/…`) | not a checkout: the student receives a PRN instruction (`{prn, billerCode, billerName, payLink, ussd:"*723*<biller>*<amount>#"}`) and pays at a bank, ATM or USSD | the Bursary imports the collections report; the sweep polls the query API when its credentials are set | import IMPLEMENTED; query API PARTIALLY (endpoint unconfirmed on onboarding) |

Common rules: the reference must belong to the caller (else 404); `PAY_ALREADY_CONFIRMED`, `PAY_REFERENCE_EXPIRED` (24-hour references), `PAY_NO_EMAIL` for card gateways, `PAY_GATEWAY_NOT_WIRED` when no secret is set; every callback is logged in `finance.gateway_event` with an outcome among `SETTLED, ALREADY_SETTLED, UNKNOWN_REFERENCE, SHORT_PAID, NOT_SUCCESSFUL, IGNORED, BAD_SIGNATURE, GATEWAY_ERROR` and a source among `WEBHOOK, VERIFY, SWEEP, TEST`; settlement is by `finance.confirm_payment` / `admissions.confirm_fee` / `admissions.pg_confirm_fee` under actor `NOBODY`, office `bursar`, channel "Card · <Gateway>" or "Quickteller PayDirect"; a confirmed payment queues the receipt notice by email and SMS. Biller routing: a programme whose faculty's `college_code = 'CHS'` pays biller CHS `04263001`, everyone else MAIN `04255101` (seeded with the former University's names and `quickteller.com/bsum` / `chsbsu` links — to be re-confirmed by the Bursary). The gateway keys page shows the webhook address as the portal URL with `moaum-portal` replaced by `moaum-api`.

### 10.2 Email and SMS

See §2.10 for the pipeline. Configuration lives in two places:

| Channel | Where configured | Details |
|---|---|---|
| SMTP | Mail Server screen (`/platform/mail`, `platform.mail_settings`, singleton, password encrypted under the config key) | defaults `smtp.office365.com:587 STARTTLS` (IMAP `outlook.office365.com:993 SSL`, POP 995 SSL are stored but unused by the dispatcher); username = the mailbox; a From address; a fresh `JavaMailSenderImpl` per send so changes apply without a restart |
| eBulkSMS | SMS Gateway screen (`/platform/sms`, `platform.sms_settings`, provider fixed `EBULKSMS`, key encrypted) | username, sender id ≤ 11 characters, enabled flag; `POST https://api.ebulksms.com/sendsms.json` with `{SMS:{auth:{username, apikey}, message:{sender, messagetext, flash:"0"}, recipients:{gsm:[{msidn, msgid}]}}}`; numbers normalised to `234…`; the answer must contain `SUCCESS` |
| HTTP relays | `MOAUM_NOTICES_EMAIL_URL`, `MOAUM_NOTICES_SMS_URL`, `MOAUM_NOTICES_TOKEN`, formats `generic` / `termii` (SMS) / `resend` (email) | a fallback for either channel when the account above is not set |

The Go-Live Readiness screen counts "Email (SMTP) configured" and "SMS configured" among its gates. No provider is configured on the local database; on production the outbox screen and the platform dashboard show what is wired.

### 10.3 Keycloak single sign-on

Coded (`auth/SsoService`, `auth/OidcVerifier`, the two frontend routes), unit-tested (`OidcVerifierTest`), **not deployed** — `docs/keycloak.md` says nothing is deployed and the README's "In production `MOAUM_AUTH_ISSUER_URI` points at Keycloak" describes an intention. The setup the document prescribes: realm `moaum`; confidential client `moaum-portal` with the standard flow, redirect URI `<portal>/api/auth/sso/callback`, web origin the portal's; a `staff_number` user-attribute mapper on the ID token; an `amr` (Authentication Method Reference) mapper, or ACR levels listed in `MOAUM_SSO_MFA_ACR`; OTP or WebAuthn required in the browser flow. The seven `MOAUM_SSO_*` variables are in §6.1; `MOAUM_AUTH_HMAC_SECRET` stays set because it signs the state and issues the portal's own token. The password door remains open beside the button until the Registry ends staff credentials from Users & roles.

### 10.4 JAMB and CAPS files

All JAMB integration is by file; `caps_batch.source` admits `CAPS_API` but no API client exists.

| File | Format | Where | Notes |
|---|---|---|---|
| CAPS admission list (UTME and Direct Entry) | `.xlsx`; the raw CAPS layout (`RG_NUM`, `CO_NAME`, …) or the office-built layout; parsed in the browser by `lib/caps.ts parseCaps` | `/admissions/caps` → `POST /caps-batches` + `/rows` in chunks, `commit`, `withdraw`, `reset-intake` | the whole list is kept as sent (`admissions.caps_row`); a list with blocking findings is refused whole; JAMB course names resolve through `ref.jamb_alias`; rows under the load cut-off are kept in `caps_row_excluded` |
| Passports | image files named by JAMB number (`\d{12}[A-Za-z]{2,3}` read from the filename); ≤ 64 KB stored as a data URL, larger by metadata; a streamed variant | `/admissions/candidate-data` → `POST …/candidate-data {kind, items}` | attached to committed candidates by `attach_pending` |
| Date-of-birth file | `.xlsx` | same | ambiguous dates flagged |
| O'Level file | `.xlsx`, one row per subject | same | parsed into sittings by `olevel_from_attachment`; the screening score is computed under the session's grading |
| JAMB admission-status list | `.xlsx` rows: registration number, name, course, admission status | `POST …/jamb-admissions` in chunks | "Accept…" rows offer and release; unmatched rows kept with a reason |
| Post-UTME scores | CSV `key, score` (JAMB or application number) | `POST …/screening-scores/upload` | reconciliation table for no match / already released / out of range |
| Return to JAMB | five-sheet workbook `ADMISSION TEMPLATE <programme> <session>.xlsx` (Admission_Summary, Merit_List, Other_Qualified_Cases, Non_Qualified_Cases, Ranked_sheet; 35 columns) | `ApplicantsDesk.exportTemplate` | follows JAMB's layout, not the S/N convention |
| Real JAMB fixtures | outside the repository (`MOAUM_FIXTURES`); seven CI checks are skipped and counted when absent | `proto/runall.mjs` | they carry real candidates' data and are never committed |

### 10.5 PayDirect

The PRN instruction and biller routing are in §10.1. The collections report is pasted or uploaded on the Payment Gateways screen with headers `prn, amount, rrn, paidat, channel, payer` (`parseRows` in `lib/bursary.ts`) and sent as `POST /api/v1/payments/paydirect/import {rows:[{prn, amount, rrn, paidAt, channel, payer}]}`. Each PRN matching a portal reference is confirmed with channel "Quickteller PayDirect"; duplicates by `(biller, RRN)` are skipped; unknown PRNs are stored `UNMATCHED` with the reason "No reference matching this PRN was generated by the portal" (`db/V080`). Billers are edited with `PUT /api/v1/payments/paydirect/billers/{MAIN|CHS}` (Bursar, ICT, admin, super). The optional query-API credentials let the sweep poll Interswitch.

### 10.6 NELFUND files

Module `wallet`, screen `/finance/nelfund`. Two pasted or uploaded CSV/XLSX shapes, both parsed in the browser by `lib/wallet.ts parseRows`:

| File | Headers | Endpoint | Effect |
|---|---|---|---|
| Remittance | `matric, name, amount` (template "NELFUND remittance template.xlsx": Matriculation Number, Name, Amount) | `POST /api/v1/nelfund/batches {ref ≤ 60, session, receivedOn, note, rows}` | rows matched to students credit the wallet; unmatched rows wait for the Registry or Bursary to match (`POST /nelfund/rows/{id}/match`) or reverse to the Fund |
| Decision list | `number, name, state, reason` | `POST /api/v1/nelfund/status {session, rows}` | the Fund's approved / not approved / pending / correctable states shown to the student before registration |

The wallet is append-only; applying it to the session charge settles a reference through the ordinary confirmation with channel "NELFUND wallet"; the funding report reads `finance.funding_summary`.

### 10.7 Legacy portal import

There is no live connection to the old portal; everything is a file or a SQL loader.

| Import | Mechanism | Notes |
|---|---|---|
| Returning students' biodata and JAMB numbers, passports named by JAMB number | `/records/migration` (ICT, Exams and Records); the biography importers V098/V111/V117/V188 and the PG importer V203/V221 create `iam.student_account` rows with a random bcrypt hash and `must_change`; V122/V125 then set the default password to the student's own number | the "Migrated from the old portal" panel on `/students` clears migrated students in every clearance unit (`clearance.clear_migrated(100,400)`, audit trigger disabled for the bulk insert) |
| Old-portal applicants who had paid | `/admissions/migration`: `.xlsx`/`.csv` of JAMB number / email / phone → `POST …/import-applicants` in parallel chunks, then `link-held`; `import_applicant` (V179) creates candidate + account (`SET_ON_FIRST_LOGIN`) + a fee-confirmed, submitted application on channel "Old-portal migration" | "Reset migrated applicants" undoes it |
| Legacy results and fee history | `/api/v1/results/legacy/*` (`MIGRATE` guard) and the payment-history / old-fees uploads on the finance screens | documented in *02 Administrator Manual* |
| Legacy matriculation numbers | the sign-in door accepts `BSU/…`, `MOAU/…` and similar shapes and tries the student door first | the V263 format coexists with V064 numbers |
| Data-migration console | `/migrations` shows only the schema ledger; its note says no legacy data migration is shown "because none has been run" | PLACEHOLDER for a legacy migration log |

---

## 11 Known technical debt and stale surfaces

Collected from the seven audit dossiers and the repository. Each row is something a developer should know before touching the area; none is presented elsewhere in the package as working.

### 11.1 Stale documentation and text

| Item | Where | What is wrong |
|---|---|---|
| README "What this is not, yet" and `api/README.md` "Endpoints so far" / "Not yet" | `README.md`, `api/README.md` | describe two modules and a handful of endpoints; 47 modules and 918 endpoints exist; scope checking and the outbox are built |
| README says `db/` holds "Ten migrations" and `check.sql` "63 properties" | `README.md`, `.github/workflows/ci.yml` job name | 261 files to V263; `check.sql` declares `EXPECTED 149` (and does not gate — §7.1) |
| README's Google Fonts warning | `README.md` | applies to the prototype only; the frontend self-hosts IBM Plex |
| README frontend variables `PORTAL_API_TOKEN`, `PORTAL_ACTIVE_OFFICE` on `moaum-portal` | `README.md` | ignored by a production build since the session cookie arrived |
| Mail Server screen footer ("once the SMTP transport is enabled on the API") | `MailSettings.tsx` | `SmtpMailer` is live |
| Outbox screen "No provider is wired" | `NoticesController.java:37-38` | reads relay URLs only, not SMTP/eBulkSMS settings |
| Security screen "verified nightly across every shard" | `Security.tsx` | no such job |
| Audit Trail closing note (refused writes on the trail) | `AuditTrail.tsx` | a rolled-back write leaves no entry |
| Records & queries "fees" / "attendance" not-served sentences | `RecordsService.FEES_NOT_SERVED`, `ATTENDANCE_NOT_SERVED` | finance and College attendance exist elsewhere |
| Student results "Official transcript" button ("Arrives with the credentials module") | `Screens4.tsx:70` | transcripts are under My Documents (V262) |
| Academic dashboard "Public verification arrives with its module" | `Academic.tsx` | verification exists |
| Matriculation run "What the run does" text | `MatriculationScreen.tsx` | describes per-department sequences (pre-V263) |
| Course-upload note naming HODs | structure upload screen | uploads are ICT-only since the last commit on `main` |
| Sign-in hint regex for matriculation numbers | `Login.tsx:16` | narrower than the handler's; a V263 number is labelled as a staff number in the hint while still being routed correctly |
| Search page "The course screens are not on the portal yet" / "Verification is not on the portal yet" | `Search.tsx:75,87` | disabled buttons with stale titles |
| Transfer approval letter | `TransferLetter.tsx` | hard-coded ₦10,000 fee and Senate/SAIC wording; code comment vs screen copy contradict on a default fee |
| API-keys screen "rate-limited" | `ApiKeys.tsx` | keys are not checked anywhere |

### 11.2 Hard-coded values

| Item | Where |
|---|---|
| Session fallback `2026/2027` | `app/page.tsx:64`, `Office.tsx:22`, `PlatformController.readiness` (line 107), `/audit/revenue`, `matriculation/page.tsx` and the faculty list, `fees/page.tsx:18`, admission settings default, the Fees & payments subtitle in `titles.ts` |
| `admissionSettings2025_2026` label on `/api/v1/platform/status` and the platform dashboard tile | `PlatformController.java:207`, `Platform.tsx` |
| Final levels for the degree audit (600 for MBBS `C00061`, 500 for names starting "LL.B" or containing "PHARMACY", else 400) | `GraduationRepository.finalists`, `records.student_graduation` |
| PG probation threshold 2.50 | `PgAdmissionsController.students`, `PgCourseworkController.summary` |
| Grading key on the semester results PDF ("A 70-100 (5) … F 0-39 (0)") | `student/results/[session]/[semester]/pdf/route.ts:122` — not read from `policy` |
| Level selects 100–600 (the database allows 700–900) | `SemesterLevelForms.tsx:18`, `Payments.tsx:32`, Student 360 level modal |
| Demo student `MOAUM/MTC/24/9903` prefilled in the gateway test form | `Gateways.tsx:25` |
| Cash ceiling ₦1,000 tile | `Exceptions.tsx:54` |
| Leave entitlement 30 days | `me/Self.tsx` |
| DR objectives (RPO ≤ 15 min, RTO ≤ 4 h, …) | `DisasterRecovery.tsx:62-68` |
| PG offer letter signatory name | `pg/offer/pdf/route.ts` |
| Login brand stats "12 faculties · 1 college · 1992 established" | `Login.tsx:74-76` |
| Registrar dashboard NDPA-return note "due on 31 March" | `Registrar.tsx:35` |
| Static menu badges ("7" Hanging, "12" Reconciliation, "!" Gateways / Payment Investigation, "2" Governance / API Management) | `lib/menus.ts` |
| **Wrong letterhead** `UNI = "Moshood Abiola University of Science and Technology, Abeokuta"` on the College score-sheet template and marked sheet | `app/college/scoresheets/ScoreSheets.tsx:18` |
| PayDirect billers seeded with the former University's names and links | `db/V080` |

### 11.3 Placeholder pages and controls

| Item | Where | Status |
|---|---|---|
| `/cloud`, `/release`, `/ethics` | static text; call only `/iam/me` | PLACEHOLDER |
| Generic `OfficeDashboard` for an office without a dashboard | `dashboards/Office.tsx` | PLACEHOLDER by design |
| Registrar dashboard "Council and Senate" sittings | `Registrar.tsx:64-68` | PLACEHOLDER rows |
| Student 360 Finance card "NOT YET SERVED"; CGPA "—" | `Student360.tsx` | PLACEHOLDER although `/students/{id}/portal` returns fees and `student_gpa` exists |
| `/me` Appraisal / Appointment / Next increment tiles | `Self.tsx` | PLACEHOLDER ("Staff module, not yet on the portal") |
| Results chain "Raise an amendment" / "View as a student" | `Chain.tsx:91` | buttons with no handler |
| Remind / escalate a late lecturer | `ResultsController.java:181-188` | 202 "nothing was sent" |
| "Notify held candidates" (clearance) | `ClearanceController.notifyHeld` | 202 stub |
| Faculty matriculation list "Fees" column | `FacultyListScreen.tsx` | renders "—" |
| Tenders fourth tile with an empty label | `Tenders.tsx:69` | leftover |
| Menu items with no route (`t/platform`, `t/setup`, `t/mgmt`, `pg/home`, `t/pgsupervision`, `t/pgproposals`, `t/pgtheses`) | `Shell.tsx`, `menus.ts` | announced as "still the prototype's screen" |
| Identity-card verification ("Verify a Card" in the CSO menu) | menus | no page |
| Data Migration console legacy log | `Migrations.tsx:41-43` | text only |

### 11.4 Tables, columns and states with no writer (CONFIGURED BUT UNUSED)

`platform.idempotency_key`, `platform.processed_event`; `credentials.signing_key` (empty; documents are hashed, not signed); `apimgmt` scopes and quotas (stored, never enforced); `college.carry_over`, `college.project`, `college.department_unit` (seed only); `registration.course_registration.status = 'LOCKED'` (checked in V139/V195, never set — every "APPROVED/LOCKED" test is effectively APPROVED); course state `SENATE` (courses go BOARD → LIVE); candidate `offer_state = 'LAPSED'` (offers never lapse); graduation `REFERRED`; library reservation expiry/cancel states; `policy.level_limit.probation_max_units` (all NULL — the probation ceiling logic in `student_submit` never fires); `putme_exam.keep_programme`, `registration_deadline`, `kind`; `iam.sign_in_event` outcomes `MUST_CHANGE`/`ENDED` and `credential_event` kinds `LOCKED`/`UNLOCKED`; deferment `verified_at/by`; the biodata "Needs approval" tier and the Biodata Changes queue (`ChangeService`, `askForChange` never called — nothing can create a request); the legacy `/me/transcripts` request (superseded by V262); the "industrial training" course flag (seed only); `caps_batch.source = 'CAPS_API'`.

### 11.5 Endpoints without a screen (backend without UI)

`GET /api/v1/auth/sessions` and `POST /auth/sessions/{id}/end`; `POST /api/v1/registration/course-registrations` and the course/offer/offering upserts under `/registration/courses…`; transfer `review`, `senate`, `withdraw`, `effect` (the committee path; the memo page reports on them); `GET /api/v1/matriculation/config/preview/{id}` and `/config/history` search; `GET /api/v1/examiners/moderation`; `GET /api/v1/provost/dashboard` (the Provost's home uses `/college/dashboard`); `GET /api/v1/research/grants` (the research grants register has a page under `/research/projects` for lecturers/deans but no Bursary UI per dossier F); the legacy `/me/transcripts`; `PUT /student-auth/accounts/{id}` is reached only from the Student 360 prompt.

### 11.6 Screens or menu items without a working endpoint or authority

The Registrar's "Audit Trail" menu item (the API's `OVERSIGHT` guard omits `registrar`); Deans/Faculty Officers/HODs' "Keep a copy" on returns (403 by guard; the toolbar explains); the calendar screen is in the academic and super menus only although registrar, dregistrar and ict may write; the DSR `REFUSED` state has no button; the processing register has no add/edit endpoint; the PG offer letter and deferment letter QR codes point at no verification endpoint.

### 11.7 Process and tooling debt

- `db/check.sql` does not gate CI (§7.1); its office-count property is `n = 31` against 34 offices; repairing it is a separate task.
- Migration numbering has gaps (V014, V015); harmless, but a new file must take the next unused number after V263.
- `lib/menus.ts` and `lib/titles.ts` are generated by a script that is not in the repository, so a regeneration needs the script recovered or the file edited by hand against its header's advice.
- `lib/report.ts` duplicates `reports.catalogue` (titles, owners, offices) and must be kept in step by hand.
- Two password-reset paths (auth module and applicant module) and two generations of the credentials store (V005/V013/V027 and V262) coexist.
- The integration tests leave residue (sessions `2090/2091 … 9999/0000`, `public.*` scratch tables) that shows up in `audit.unattached()` and the Security screen on developer databases.
- Frontend bugs recorded by dossier F: `ReconcileLedger.tsx:45` fires the error toast on every successful load; `Hanging.tsx:74` shows nothing when "Resolve" fails; several finance actions have no confirmation dialog or success toast; fee-line editing keeps only the first ticked programme.
- Results are graded under the scheme in force at `current_date`, not at publication; only one scheme (SEN/2015/44) is seeded; the classification table has no band under 1.00.
- The CBT module is a question bank only; no test engine exists.
- The office switch does not update `platform.session.active_office`.

---

*End of 03 Technical Documentation.*
