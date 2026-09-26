# 08 — Database Reference

**MOAUM Unified University Portal** — Rev. Fr. Moses Orshio Adasu University, Makurdi — Directorate of ICT

This volume describes the PostgreSQL database behind the portal as it is actually built by the migrations in `db/`. Part 1 explains how the database is organised and governed (migrations, schemas, roles, the audit spine, naming, where the business rules live). Part 2 draws the core relationships of each domain. Part 3 gathers the status columns that carry the University's workflows. Part 4 covers operation (verification, local development, demo data, data hygiene). Part 5 is the generated table catalogue — every schema, table, column, key, trigger and audit status — produced from the live schema and included in full.

Everything here was checked against the migration files (`db/V001` … `db/V263`), the schema inventories (`tables.psv`, `columns.psv`, `constraints.psv`, `functions.psv`, `triggers.psv`, `indexes.psv`) and the audit dossiers. Where a fact could not be confirmed it is marked **not verified**. Nothing in this volume prints a secret; environment variables are named, never valued.

Cross-references: the API that reads and writes these tables is in *07 API Reference*; the request path, deployment and CI are in *03 Technical Documentation*; the workflows the status columns serve are in *06 Workflows*; who may act on what is in *04 Role & Permission Matrix*.

## Table of contents

1. [Introduction](#1-introduction)
   1. [Engine, version and extensions](#11-engine-version-and-extensions)
   2. [The migration model](#12-the-migration-model)
   3. [Schema-per-domain layout](#13-schema-per-domain-layout)
   4. [Module roles and grants](#14-module-roles-and-grants)
   5. [The audit spine](#15-the-audit-spine)
   6. [Write-once event tables](#16-write-once-event-tables)
   7. [Naming conventions and reference numbers](#17-naming-conventions-and-reference-numbers)
   8. [Status columns as CHECK constraints](#18-status-columns-as-check-constraints)
   9. [Where the business logic lives — SQL functions](#19-where-the-business-logic-lives--sql-functions)
   10. [Triggers](#110-triggers)
   11. [The reporting schema and saved reports](#111-the-reporting-schema-and-saved-reports)
2. [Entity-relationship overview by domain](#2-entity-relationship-overview-by-domain)
   1. [Identity and access](#21-identity-and-access)
   2. [People and students](#22-people-and-students)
   3. [Undergraduate admissions](#23-undergraduate-admissions)
   4. [Postgraduate admissions, coursework and research](#24-postgraduate-admissions-coursework-and-research)
   5. [Catalogue and course registration](#25-catalogue-and-course-registration)
   6. [Assessment and results](#26-assessment-and-results)
   7. [Finance and payments](#27-finance-and-payments)
   8. [Credentials and documents](#28-credentials-and-documents)
   9. [Hostel](#29-hostel)
   10. [ICT help desk](#210-ict-help-desk)
   11. [Human resources and expenditure](#211-human-resources-and-expenditure)
   12. [Platform, audit and governance](#212-platform-audit-and-governance)
3. [Important status fields](#3-important-status-fields)
4. [Operational notes](#4-operational-notes)
   1. [Backups and disaster recovery](#41-backups-and-disaster-recovery)
   2. [Deployment verification](#42-deployment-verification)
   3. [Local development cluster](#43-local-development-cluster)
   4. [Demo data — db/demo.sh](#44-demo-data--dbdemosh)
   5. [Data hygiene — configured but unused](#45-data-hygiene--configured-but-unused)
5. [Generated catalogue](#5-generated-catalogue)

---

# 1 Introduction

## 1.1 Engine, version and extensions

| Item | Value | Where established |
|---|---|---|
| Engine | PostgreSQL | `db/*.sql` are psql scripts; `db/migrate.sh` runs them with `psql` |
| Version used in CI | **PostgreSQL 17** (`image: postgres:17` in every database-backed job) | `.github/workflows/ci.yml` |
| Production | Railway's managed Postgres service, one database, many schemas | `README.md` "Deploying on Railway" — the server version in production is **not verified** here |
| Extension `pgcrypto` | `gen_random_uuid()`, `digest()` for the audit hash chain, `crypt()`/`gen_salt()` for bcrypt hashes | `db/V001__schemas_and_roles.sql` |
| Extension `btree_gist` | Exclusion constraints on effective-dated policy (no two schemes overlap) | `db/V004__policy.sql` |
| Client | Plain JDBC from the Spring Boot API; the Next.js frontend never touches the database | `README.md`, *03 Technical Documentation* |

> **Note:** Only the API service connects to the database. The frontend calls the API over Railway's private network; the HTML prototype's server reads `DATABASE_URL` for its `/healthz` line only and no longer migrates.

## 1.2 The migration model

### 1.2.1 The V-files

The schema is built entirely by numbered SQL files in `db/`, named `V<nnn>__<subject>.sql`. There are **261 files numbered V001 to V263** (V014 and V015 were never issued). The first ten lay the foundation — schemas and roles (V001), the audit spine (V002), identity and platform (V003), policy (V004), credentials (V005), admissions intake (V006–V009), the ledger's own exemption (V010) — and each later file adds one capability, from the student record spine (V013) to the matriculation number format (V263). A file is a plain psql script: DDL, seed rows, `CREATE OR REPLACE FUNCTION`, `SELECT audit.attach(...)`, comments.

### 1.2.2 The runner — `db/migrate.sh`

`db/migrate.sh` applies the files once each, in name order, against `DATABASE_URL` with `ON_ERROR_STOP=1`. It keeps a ledger:

```text
public.schema_migration
  filename    text PRIMARY KEY
  sha256      text NOT NULL          -- SHA-256 of the file as applied
  applied_at  timestamptz NOT NULL   -- default now()
  applied_by  text NOT NULL          -- default current_user
```

For every `V*.sql` the runner computes the file's SHA-256 and consults the ledger:

| Ledger state | What the runner does |
|---|---|
| Not in the ledger | Applies the file (`psql -f`), then inserts filename + hash |
| In the ledger, same hash | Skips it |
| In the ledger, **different hash** | Prints both hashes and **exits 1 — the deployment stops** |

It then prints `N applied, M already in place` and, if `db/verify.sql` exists, runs it. It never runs `check.sql`.

> **Warning:** Never edit a migration that has been applied anywhere. The runner will refuse it by name on the next deployment, and until a new file corrects it nothing deploys. Corrections go in a **new** V-file. CI proves this property on every run: it appends a comment to `V009`, expects `migrate.sh` to fail, and restores the file.

The API's Railway service owns the schema: its pre-deploy command is `bash db/migrate.sh`. CI additionally proves that a second run reports `0 applied` (idempotence) and that the same runner works from inside both the API image and the prototype image (*03 Technical Documentation*, §Deployment).

### 1.2.3 Read-only verification — `db/verify.sql`

`db/verify.sql` runs after every migration run and on every deployment. It only reads (one deliberate insert is rolled back by design) and it **raises** rather than reports, so a database the application cannot safely use never serves traffic. It asserts:

| # | Property asserted | Failure message (abridged) |
|---|---|---|
| 1 | No application role (`app_%`) holds `DELETE` on any table | "N application-role DELETE grants exist. Nothing in this system deletes." |
| 2 | No application role holds `INSERT`, `UPDATE` or `DELETE` on any `audit.*` table | "write grants on audit.* to application roles" |
| 3 | An unattributed insert into `iam.person` is still refused by the spine (the insert is attempted with no `moaum.actor_id`; a `check_violation` is the pass) | "an unattributed write to iam.person SUCCEEDED. The audit spine is not enforcing." |
| 4 | `ref.office` holds exactly **34** rows (32 staff offices, the applicant and the student) | "expected 34" |
| 5 | `ref.programme` holds at least 92 rows | "expected at least 92" |
| 6 | An `admissions.session_policy` row exists for 2025/2026 | "no 2025/2026 admission settings" |

It ends with one line for the deployment log: `schema: N migrations applied, latest V263__matriculation_format.sql`.

### 1.2.4 The property suite — `db/check.sql`

`db/check.sql` is the full property suite. It **writes**: it creates people, policies, credentials and an admission list, and deliberately tampers with an audit row to prove the chain detects it. It therefore belongs in CI against a throwaway database and must never be run against University data. It cleans up exactly what it made before it starts, sets `moaum.maintenance = on` for the one maintenance act that removes write-once history, and prints `PASS`/`FAIL` per property plus a count of how many checks **ran** (a `DO` block that errors never reaches its assertion, so "N of M checks RAN" is part of the verdict). The suite currently declares `\set EXPECTED 149` properties; the CI job name and the README still say 63.

> **Warning:** The suite's final verdict is known to be unreliable: three `DO` blocks end with `END $;` (a typo that aborts the block), and the CI gate greps for the string `FOUNDATION GREEN`, which psql also echoes as part of the script text. The suite does not currently gate a deployment on its own. See *09 Feature Status Report*.

## 1.3 Schema-per-domain layout

Each module owns a PostgreSQL schema (ADR-006, quoted in `V001`). The migrations create **28 schemas**; with `public` (the ledger) the database has 29 namespaces. Twenty-six hold tables today; `notify`, `payments` and `reporting` are created and granted but hold no table (notices live in `platform.notice`; gateway tables live in `finance`; the reporting schema holds one function). The inventory counts **331 tables**, of which 24 are monthly partitions of `audit.entries`, so there are 307 logical tables.

| Schema | Tables | Purpose | Created in |
|---|---|---|---|
| `iam` | 8 | Persons, staff credentials, office assignments, staff and student sign-in events, student portal accounts | V001 |
| `people` | 21 | The student record: students, contacts, biodata, status changes, enrolments, matriculation (lists, runs, format, series, history), deferments, transfers | V001 |
| `admissions` | 67 | Undergraduate intake (CAPS lists, candidates, attachments, O'Level, policy and rules, applicant portal, screening, Post-UTME CBT, JAMB lists) and the postgraduate school (applications, fees, calendar, coursework, research) | V001 |
| `catalogue` | 5 | Courses, programme–course bindings, offerings, co-teachers, class slots | V001 |
| `registration` | 3 | Course registrations, entries, attendance | V001 |
| `assessment` | 10 | Examination sessions, score sheets, scores, approval decisions, held scripts, result queries, exam timetable, CBT question bank, SIWES supervisors, legacy holding | V001 |
| `records` | 1 | Graduands and Senate approval of awards | V001 |
| `credentials` | 15 | Document policies and templates, issued documents, requests, deliveries, tokens, revocations, printed certificates, identity cards, verification logs, signing keys | V001 |
| `clearance` | 2 | Clearance units and items | V001 |
| `finance` | 21 | Fee schedule and settings, payment references, gateway events and credentials, bank credits, refunds, reconciliation, general ledger, wallet, NELFUND, PayDirect | V001 |
| `payments` | 0 | Created for the payments module; no table (gateway tables are in `finance`) | V001 |
| `expenditure` | 10 | Vouchers and their acts and queries, budgets, tenders and bids, requisitions, stores, assets, research grants | V001 |
| `notify` | 0 | Created for the notification module; no table (the outbox is `platform.notice`) | V001 |
| `governance` | 3 | NDPA processing register, data-subject requests, DR drill log | V001 |
| `reporting` | 0 | Read models; holds `reporting.student_positions()` only; exempt from audit wholesale | V001 |
| `apimgmt` | 2 | API consumers and keys | V001 |
| `ref` | 13 | Shared reference data: offices, colleges, faculties, departments, programmes, units and aliases, JAMB aliases, fee groups and items, clearance purposes, biodata fields | V001 |
| `policy` | 9 | Academic sessions and semesters, level limits, curriculum tracks, policy versions with grade, classification and clearance bands | V001 |
| `platform` | 13 | Sessions, notices and attachments, number series, mail/SMS settings and their events, service requests and documents, idempotency keys, processed events | V001 |
| `audit` | 27 | The spine: `entries` (24 monthly partitions), `chain_head`, `subject_key`, `exemption` | V001 |
| `hostel` | 20 | Halls, blocks, rooms, beds, facilities, assets, session window, applications, allocations, inspections, charges, clearance, transfers, maintenance, events | V030 |
| `library` | 5 | Items, copies, loans, reservations, settings | V031 |
| `health` | 5 | Profiles, appointments, visits, notes, record access | V032 |
| `lms` | 6 | Materials, assignments, submissions (with blobs), access log | V035 |
| `hrm` | 13 | Grades, employments, pay runs, payslips, leave, movements, vacancies, applicants, appraisals, staff record/profile/photo | V069 |
| `reports` | 2 | Report catalogue and kept snapshots | V229 |
| `college` | 28 | College of Health Sciences (MB;BS): levels, semesters, enrolments, professional examinations, results, decisions, postings, attendance, procedures | V245 |
| `helpdesk` | 8 | ICT support tickets, comments, attachments, events, categories, SLA, settings | V251 |
| `extexam` | 14 | External examiners, appointments, projects, rubrics, assignments, assessments, events | V254 |
| `public` | 1 | `schema_migration` — the deployment ledger (not counted in the 331) | `migrate.sh` |

Two rules from `V001` explain the layout. The schema name is not the Java package name — the mapping is a lookup (`student`→`people`, `results`→`assessment`, `credentials`→`credentials`+`clearance`, `registration`→`catalogue`+`registration`). And `ref` and `policy` are the two schemas every module may read; `policy` is the one shared schema a foreign key may point at (`policy.academic_session`, `policy.curriculum_track`, `policy.version`).

## 1.4 Module roles and grants

`V001` creates one `NOLOGIN` role per module and grants it, on its own schema(s) only: `USAGE` on the schema; `SELECT, INSERT, UPDATE` on tables (as default privileges); `USAGE, SELECT` on sequences; and read-only `SELECT` on `ref` and `policy`. **No application role holds `DELETE` anywhere** (D11: nothing is deleted; a record is ended with a date and a reason). `verify.sql` re-asserts this on every deployment.

| Role | Schema(s) | Notes |
|---|---|---|
| `app_iam` | `iam` | |
| `app_student` | `people` | later also `USAGE` on `hostel`, `library`, `health`, `lms`, `college` |
| `app_admissions` | `admissions` | |
| `app_registration` | `catalogue`, `registration` | later also `college` |
| `app_results` | `assessment` | later also `lms`, `college` |
| `app_acrecords` | `records` | |
| `app_credentials` | `credentials`, `clearance` | |
| `app_finance` | `finance` | later also `hostel`, `library` |
| `app_payments` | `payments` | schema is empty |
| `app_expenditure` | `expenditure` | |
| `app_notification` | `notify` | schema is empty |
| `app_governance` | `governance` | |
| `app_reporting` | `reporting` | |
| `app_apimgmt` | `apimgmt` | |
| `app_platform` | `platform` | |
| `app_auditor` | read-only `SELECT` everywhere it is granted, plus `EXECUTE` on `audit.verify_chain` and `audit.unattached` | Internal Audit's scope is what it may read |
| `app_retention` | the only role in the estate meant to hold `DELETE`, "on a schedule" | created in `V001`; **no migration grants it anything** (verified by grep) — CONFIGURED BUT UNUSED |

> **Note:** The deployed API connects with the single role in `DATABASE_URL` (a superuser on Railway's Postgres, as the README states). A search of `api/src/main` finds no `SET ROLE` and no reference to any `app_*` role, so in the deployed shape the per-module boundary is enforced by Spring Modulith's package rules and by the audit spine, not by the connection role. The roles remain the mechanism `V001` describes for a hardened deployment. *(verified: grep of `api/src/main` and `db/`)*

## 1.5 The audit spine

The audit spine (`db/V002__audit_spine.sql`) is the property the whole design rests on: **there is no unattributed state change**. It is a trigger, not an application aspect, so it cannot be bypassed by a repository call written outside a command service.

### 1.5.1 What a row records

```text
audit.entries  (PARTITION BY RANGE (occurred_at))
  id              uuid          the entry
  occurred_at     timestamptz   clock_timestamp() at the write
  period          date          first day of the month
  shard           smallint      0–15, hashtext(subject_id) % 16
  seq             bigint        position within (period, shard)
  actor_id        uuid          the person acting        ← moaum.actor_id
  actor_office    text          the capacity acted in    ← moaum.actor_office (must exist in ref.office)
  action          text          the trigger argument, else INSERT / UPDATE / DELETE
  subject_type    text          'schema.table'
  subject_id      uuid          the row's id, or an md5-derived uuid over its PK columns
  before_state    jsonb         to_jsonb(OLD) on UPDATE/DELETE
  after_state     jsonb         to_jsonb(NEW) on INSERT/UPDATE
  reason          text          ← moaum.reason
  correlation_id  uuid          ← moaum.correlation_id (X-Correlation-Id)
  source_ip       inet          ← moaum.source_ip
  prev_hash       bytea         the previous entry's hash in this chain (genesis '\x00')
  entry_hash      bytea         sha256(canonical(entry) || prev_hash)
  PRIMARY KEY (occurred_at, id)
```

`audit.canonical(e)` renders the entry as `id|timestamp(UTC, µs)|seq|actor|office|action|subject_type|subject_id|before|after|reason|correlation_id`; jsonb's sorted keys make the text reproducible years later by someone without this code.

### 1.5.2 The functions

| Function | Role |
|---|---|
| `audit.record()` | The trigger function (`SECURITY DEFINER`). Reads the transaction-local settings; **refuses** with SQLSTATE `23514` "unattributed change to schema.table — no audit context on this transaction" when `moaum.actor_id` or `moaum.actor_office` is absent, and "no such office" when the office is not in `ref.office`; computes subject, period and shard; locks the `(period, shard)` chain head `FOR UPDATE`; inserts the entry with its hash; advances the head |
| `audit.attach(table, action?)` | Resolves the table's primary key once into `audit.subject_key`, then creates `trg_audit_<schema>_<table>` `AFTER INSERT OR UPDATE OR DELETE … FOR EACH ROW`. A table without a primary key cannot be attached ("A row with no identity cannot be the subject of an audit entry") |
| `audit.exempt(table, reason)` | Records a written exemption in `audit.exemption`; the reason must be longer than 20 characters (`ck_exemption_reason`) |
| `audit.unattached()` | Lists tables outside `audit`/`reporting` with neither an exemption row nor a `trg_audit_%` trigger — "a table is on the spine, or it is exempt for a written reason, or it is a defect" |
| `audit.verify_chain(period?)` | Walks every `(period, shard)` chain from `audit.genesis()` and reports `entries`, `ok`, `first_break`, `broke_at` |
| `audit.genesis()` | The shared genesis link `'\x00'` — named once so writer and verifier agree |
| `audit.ensure_partition(at)` | Creates `audit.entries_YYYYMM` for the month if missing (24 months from 2026-09 are pre-created) and revokes `PUBLIC` |
| `audit.canonical(e)` | The byte string a hash is taken over |

### 1.5.3 Session settings and the application

The API sets the context on every transaction. `AttributedTransactionManager` (api, `platform` package) runs `set_config('moaum.actor_id', …, true)`, `moaum.actor_office`, `moaum.reason`, `moaum.correlation_id` and `moaum.source_ip` — the third argument `true` makes them **transaction-local** (`SET LOCAL` semantics). A request that names no acting office (no `X-Active-Office` / office cookie) may read but any write is refused by the trigger, which `ProblemHandler` turns into **403 `NO_ACTING_OFFICE`** — "This request names no acting office, so it may read but not change anything." A batch job or SQL function that forgets the context fails on its first write; there is no exemption. Scheduled jobs (deferment clock, hostel clock, help-desk auto-closer, gateway settle) run under a synthetic all-zero actor and a named office (`registrar`, `housing`, `ict`, `bursar`).

**"Unattributed change"** therefore means exactly this: a write to an attached table in a transaction with no actor or office. It is the error text of the refusal, and its absence is asserted by `verify.sql` §3 on every deploy.

### 1.5.4 Partitioning, sharding and the chain

Entries are partitioned by month (`audit.entries_202609` … `entries_202808` exist today; `ensure_partition` makes more as needed). Within a month there are **sixteen chains**, one per shard, so 8,000 concurrent registrations do not serialise through one head row. Each entry links to its predecessor's hash; a break anywhere is found by `verify_chain`. Detection, not prevention, is the goal against a database superuser (ADR-018).

> **Planned / Not Yet Implemented:** The Security screen says the chain is "verified nightly across every shard". No such job exists: `audit.verify_chain` is called only from `db/check.sql`. See *09 Feature Status Report*.

### 1.5.5 Permissions

`REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM PUBLIC`; every `app_%` role gets `USAGE` on the schema (so the `SECURITY DEFINER` call resolves) and no table privilege; `app_auditor` gets `SELECT`; `UPDATE, DELETE ON audit.entries` are revoked from `PUBLIC`. Retention (7 years) is by partition, never row by row.

### 1.5.6 Audit-exempt tables and why

**258 tables are attached; 47 carry a written exemption** (`audit.exemption`). The reasons fall into five kinds:

| Kind | Tables (examples) | Reason recorded |
|---|---|---|
| Secrets and hashes | `iam.credential`, `iam.password_reset`, `admissions.password_reset`, `finance.gateway_credential`, `platform.mail_settings`, `platform.sms_settings` | A hash or key must not be copied into a second, longer-lived place; the *act* of setting it is audited on an event table instead |
| Blobs | `admissions.application_document_blob`, `pg_research_document_blob`, `extexam.examiner_file_blob`, `project_document_blob`, `helpdesk.ticket_attachment_blob`, `hrm.staff_photo`, `lms.material_blob`, `submission_blob`, `people.deferment_document_blob`, `platform.request_document_blob` | Bytes; the metadata row beside them is attached |
| Verbatim external input | `admissions.caps_row`, `caps_row_excluded`, `attachment`, `olevel_sitting`, `olevel_grade` | The file from JAMB as it arrived; the act of loading it is audited on `caps_batch` |
| Public or anonymous telemetry | `iam.sign_in_event`, `iam.student_event`, `credentials.verification`, `lookup_miss`, `download_log`, `people.search_log`*, `health.record_access`, `lms.access` | Written at request rate or by a stranger with no acting office; the log *is* the record |
| Machinery | `platform.session`, `platform.number_series`, `platform.idempotency_key`, `platform.processed_event`, `public.schema_migration`, `ref.biodata_field`, `admissions.rule_subject`, `rule_subject_group`, `selection_criterion`, `suggestion_sent`, `applicant_account`, `applicant_event`, `pg_applicant`, `pg_document`, `pg_legacy_holding`, `assessment.legacy_result_holding`, `extexam.invitation`, `health.note` | Counters, session touches, staging rows, or rows whose meaningful act is audited on the record that received the number |

\* `people.search_log` is attached in the current inventory; the list above is the exemption register as the migrations write it. The full per-table audit status is in the catalogue (§5, column *Audit*).

Two schemas are exempt wholesale, each for a stated reason: `audit` (the spine cannot audit itself; it is chained instead) and `reporting` (derived read models, refreshed from events already audited). This is why the reporting schema may not hold state.

## 1.6 Write-once event tables

Several modules keep a trail table beside the record, and protect it with a `BEFORE UPDATE` (or `BEFORE DELETE OR UPDATE`) trigger that raises SQLSTATE `23514`. Such a row can be inserted and read, never amended.

| Table | Trigger | Function | Escape hatch |
|---|---|---|---|
| `admissions.putme_event` | `trg_putme_event_written_once` (BEFORE DELETE OR UPDATE) | `admissions.putme_history_is_written_once` | none |
| `people.deferment_event` | `trg_deferment_event_written_once` (BEFORE DELETE OR UPDATE) | `people.deferment_history_is_written_once` | none |
| `people.matric_history` | `trg_matric_history_written_once` (BEFORE UPDATE) | `people.matric_history_is_written_once` | none |
| `credentials.event` | `trg_credentials_event_written_once` (BEFORE UPDATE) | `credentials.event_is_written_once` | none |
| `hostel.event` | `trg_hostel_event_written_once` (BEFORE UPDATE) | `hostel.event_is_written_once` | none |
| `helpdesk.ticket_event` | `trg_hd_event_written_once` (BEFORE DELETE OR UPDATE) | `helpdesk.history_is_written_once` | `moaum.maintenance = on` (set only by `check.sql`'s cleanup) |
| `extexam.event` | `trg_ee_event_written_once` (BEFORE DELETE OR UPDATE) | `extexam.history_is_written_once` | `moaum.maintenance = on` |

Other trails are write-once **by convention** rather than by trigger: `assessment.decision`, `assessment.score` (a change is a new version with a reason, `ck_score_amended`), `people.status_change`, `finance.payment_reconciliation`, `finance.gl_posting` (reversed, never edited), `finance.gateway_credential_event`, `expenditure.voucher_act`, `admissions.pg_application_event`, `pg_research_event`, `credentials.download_log`. Two record-level immutabilities are also triggers: `people.matric_is_immutable` ("the matriculation number is permanent and is not changed"; the admission number is retired, not changed) and the deferred constraint trigger `gl_balance` on `finance.gl_posting` (a journal must balance).

## 1.7 Naming conventions and reference numbers

### 1.7.1 Identifiers

| Convention | Rule as built |
|---|---|
| Primary keys | `uuid` named `id` on almost every state table (`gen_random_uuid()`); natural keys where the code *is* the identity: `ref.office.code`, `ref.programme.code`, `catalogue.course.code`, `hostel.hall.code`, `library.copy.accession`, `finance.gl_account.code`, `credentials.document_policy.kind`; composite keys on association rows (`registration.entry (registration_id, offering_id)`, `people.biodata (student_id, field)`, `audit.chain_head (period, shard)`) |
| Foreign keys | Column `<table>_id` (`student_id`, `offering_id`, `sheet_id`) or `<table>_code` for natural keys (`programme_code`, `dept_code`, `office_code`, `hall_code`) |
| Constraints | `ck_` CHECK (617 named so), `uq_` UNIQUE (21 constraints and 52 unique indexes), primary keys `<table>_pkey` |
| Indexes | `ix_<table>_<purpose>` (158), `uq_…` for unique indexes; the audit partitions carry `entries_…_subject` / `_actor` |
| Triggers | `trg_audit_<schema>_<table>` from `audit.attach`; `trg_<subject>` for business triggers; `*_written_once` for trails |
| Functions | `schema.verb_noun` (`people.matriculate`, `finance.confirm_payment`); predicates `is_…`/`…_of`; trigger functions `trg_…` or `…_is_written_once` |
| Session settings | `moaum.actor_id`, `moaum.actor_office`, `moaum.reason`, `moaum.correlation_id`, `moaum.source_ip`, `moaum.maintenance`, `moaum.deferment_override`, `moaum.putme_reason` |
| Timestamps | `*_at timestamptz` for instants, `*_on date` for dates, paired with `*_by uuid` for the actor; soft ends as `ended_at`/`ended_on` + `ended_reason` |
| Deletion | None. A row is ended, superseded, cancelled or revoked; no application role holds `DELETE` |

### 1.7.2 Reference numbers

Almost every human-facing number is drawn from **`platform.next_number(kind, scope, session)`** (`V013`): an upsert on `platform.number_series (kind, scope, session, next_value)` that returns the next integer for the series. A series is per kind, per scope (`'UNIVERSITY'` or a department code) and per session or year, so numbers continue across a year and never repeat within a series. The exception is the matriculation number, which since `V263` draws from `people.matric_series` (a named, locked sequence that only moves forward).

| Number | Format | Series (`kind`, scope) | Issued by |
|---|---|---|---|
| Admission number | `MOAUM/ADM/YY/NNNNNN` | `ADMISSION`, UNIVERSITY, per session | `people.intake` (UG), `admissions.pg_admit` (PG) |
| Matriculation number (V263) | `MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}` — programme segment only for a programme configured to carry a code; separator `/` or `-`; padding per `people.matric_format.sequence_digits` (0 = none) | `people.matric_series` (Administration, College, Pharmacy, Architecture, General …) per faculty or programme | `people.next_matric` inside `people.matriculate` / `matriculate_student`; history in `people.matric_history` |
| Matriculation number (pre-V263, legacy) | `MOAUM/{DEPT}/YY/NNNN` | `MATRIC`, department code, per session | `people.matriculate` before V263; legacy numbers are passed over, never reused |
| Matriculation run | `MAT/YYYY/NNN` | `MATRIC_RUN`, UNIVERSITY, per session | `people.matriculate` |
| Application number (UG) | `APP/YY/NNNNNN` | `APPLICATION`, UNIVERSITY, per session | `admissions.register_applicant` |
| Application number (PG) | `PG/YY/NNNNNN` | `PG_APPLICATION`, UNIVERSITY, per session | `admissions.pg_apply` |
| Payment reference (student) | `MOAUM-FEE-<last 7 alphanumerics of matric/admission no>-<4 random digits>` (24-hour expiry) | none — random suffix, retried on collision (V131) | `finance.new_reference`, `finance.new_purpose_reference` |
| Payment reference (applicant) | `MOAUM-APP-…` / `MOAUM-ACC-…` (24-hour expiry) | none — random suffix | `admissions.new_fee_reference` |
| Payment reference (PG) | `MOAUM-PGAPP-NNNNNN`, `MOAUM-PGCHK-NNNNNN`, `MOAUM-PGACC-NNNNNN` | `PG_FEEREF`, UNIVERSITY, per session | `admissions.pg_new_fee_reference` |
| Receipt number | `RCT-YYYY-NNNNN` (year = first four of the session, or the calendar year for applicants) | `RECEIPT`, UNIVERSITY, per session/year | `finance.confirm_payment`, `admissions.confirm_fee` |
| Legacy/migrated references | `MOAUM-LEG-<matric>-<YYYY-YYYY[-Sn]>`, `RCT-MIGR-…` | derived, idempotent | legacy fee and payment-history imports |
| Transcript / document request | `TRN-YYYY-NNNNN` | `TRANSCRIPT`, UNIVERSITY, per year | `credentials.student_transcript_request`, `credentials.request_document` |
| Issued document number | `CERT-YYYY-NNNNNN`, `TRN-YYYY-NNNNNN`, `STR-YYYY-NNNNNN`, `MTR-YYYY-NNNNNN`, `ASR-YYYY-NNNNNN` (prefix from `credentials.document_policy.number_prefix`) | per kind and year | `credentials.next_document_number` inside `credentials.issue` |
| Verification code | Crockford base-32, five groups of five | random | `credentials.new_code` |
| Identity card | `MOAUM/ID/YY/NNNNN` | `IDENTITY_CARD`, UNIVERSITY, per year | `credentials.issue_identity_card` |
| Hostel application | `HST-YYYY-NNNNN` | `HOSTEL_APPLICATION`, UNIVERSITY, per year | column default `hostel.next_ref` |
| Hostel allocation | `ALC-YYYY-NNNNN` | `HOSTEL_ALLOCATION`, UNIVERSITY, per year | column default `hostel.next_ref` |
| Help-desk ticket | `TICK-YYYY-NNNNN` (five random digits, re-drawn on collision, never reused) | none | `helpdesk.new_number` |
| Service request | `SR-YY-NNNNN` | `SERVICE_REQUEST`, UNIVERSITY, per year | `platform.raise_request` |
| Deferment | `DEF-YYYY-NNNNN` | `DEFERMENT`, UNIVERSITY | `people.deferment_save` |
| Result query | `QRY-YYYY-NNNNN` | `RESULT_QUERY`, UNIVERSITY, per year | `assessment.raise_query` |
| Payment voucher | `PV/YYYY/NNNN` | `VOUCHER`, UNIVERSITY, per year | `expenditure.raise_voucher` |
| Requisition / tender / refund | `RQ-YYYY-NNNN`, `TN/YYYY/NNNN`, `RF-YYYY-NNNN` | per year | `expenditure.*`, `finance.propose_refund` |
| Staff movement instrument | `MOAUM/R/ACA/YYYY/NNNN` | per year | `hrm.issue_movement_instrument` |
| Data-subject request | `DSR-YYYY-NNNN` | `DSR`, UNIVERSITY, per year | governance controller |

> **Note:** A Post-UTME batch is labelled `B001…` per exam and a legacy screening seat `LABEL-NNN`; neither is a University-wide series.

## 1.8 Status columns as CHECK constraints

Workflow state is a `text` column constrained by a named `CHECK … IN (…)`; there are **no PostgreSQL enum types**. `constraints.psv` lists 627 CHECK constraints, of which about 140 constrain a `status`, `state`, `stage`, `kind`, `outcome` or `mode` column. The choice is deliberate: a new value is one `ALTER TABLE … DROP CONSTRAINT / ADD CONSTRAINT` in a new V-file, with no type migration and no rewrite; and the set of values is visible in the catalogue. Many state machines are enforced in the SQL function that moves the row (for example `assessment.advance`, `helpdesk.transition`, `people.deferment_decide`), not merely by the CHECK — the CHECK bounds the vocabulary, the function bounds the transitions. Several CHECKs also couple a state to its evidence (`ck_sheet_published` needs `published_at` and `senate_minute`; `ck_pref_confirmed` needs `confirmed_by`, `channel`, `receipt_no`; `ck_grad_approved` needs a minute, no unmet items and a CGPA).

Where a status is derived rather than stored, the function is the definition: a payment reference is OPEN, EXPIRED or CONFIRMED by `finance.reference_state` (there is no status column); a document is ACTIVE, REVOKED or REPLACED by `credentials.document_status`; an applicant's stage 0–9 by `admissions.application_stage`; a deferment's return is UPCOMING/DUE/OVERDUE/RETURNED by `people.deferment_return_status`.

Part 3 tabulates the important status columns with the meaning of each value.

## 1.9 Where the business logic lives — SQL functions

The migrations define **562 functions** (`functions.psv`): 110 in `admissions`, 75 in `finance`, 59 in `people`, 44 in `hostel`, 41 in `credentials`, 33 in `assessment`, 21 each in `hrm` and `registration`, 19 in `college`, 17 in `helpdesk`, 16 each in `expenditure` and `platform`, 12 in `ref`, 10 each in `iam` and `extexam`, 9 in `health`, 8 each in `audit` and `library`, 7 in `catalogue`, 6 in `policy`, 5 each in `clearance` and `lms`, 4 in `apimgmt`, 3 in `reports`, 2 in `records`, 1 in `reporting`. The rule of the codebase is that an act that changes the University's record is a SQL function: it runs inside the caller's attributed transaction, raises with a plain-language message and often a `HINT` naming the remedy, and is exercised by `check.sql` and the API's integration tests. The Java service validates shape, applies office guards and scope, and calls the function.

The most important functions:

| Function | What it does |
|---|---|
| `people.matriculate(session)` / `people.matriculate_student(student, …)` | The matriculation run: refuses until every faculty list is CONFIRMED, opens a run `MAT/YYYY/NNN`, walks the confirmed lists and gives each student a number through `people.next_matric`, sets `status = 'ACTIVE'`, writes `people.status_change` and `people.matric_history`, and tells the student (`people.matric_tell`) |
| `people.next_matric(student, run, reason)` (V263) | Builds the number from `people.matric_components` and `people.format_matric`, locks the series `FOR UPDATE`, passes over any number already on the register or in the history, spends the sequence, writes the write-once history row |
| `people.intake(session)` | Brings every ADMITTED/ACCEPTED candidate onto the register with an admission number |
| `people.change_status(student, to, instrument, effective, reason)` | The only path a student status changes on; refuses without an instrument |
| `registration.student_submit(...)` | Submits a registration: the per-semester fee gate (`finance.semester_cleared`), unit range from `policy.level_limit`, the probation ceiling where set; the deferment gate trigger fires on the status change |
| `finance.charges(student, session)` | Computes what a student owes from `finance.fee_schedule` by matching every filter a line carries (level, entry mode, faculty, programme, fee group, semester, indigene, spillover) — "a student's charge is computed, never typed" |
| `finance.position(student, session)` | Due, paid, balance, instalments paid, paid in full, arrears |
| `finance.confirm_payment(reference, channel, note)` | Confirms a portal-generated reference, issues `RCT-…`, and performs the purpose's side effect (transcript READY, hostel bed CONFIRMED, library fine settled, wallet TOPUP), then queues the receipt email and SMS |
| `assessment.advance(sheet, …)` / `return_sheet` | Moves a score sheet along ENTRY → … → PUBLISHED, one desk per step (BR-006: the same person does not approve twice in a row), every candidate outcome present before leaving ENTRY, a Senate minute before PUBLISHED |
| `assessment.student_gpa` / `student_cumulative` / `standing_of` | GPA and CGPA from published scores and the grade bands in force; standing (GOOD / PROBATION / ADVISED_TO_WITHDRAW, per `policy`) |
| `credentials.issue(...)` / `issue_certificate` / `build_statement` | Builds the statement of record from the authoritative tables, stores it byte for byte with its SHA-256 and verification code, numbers it; the certificate is gated by `credentials.assert_issuable` (GRADUATED, Senate-approved, cleared) |
| `credentials.verify_document(code_or_number)` | The public answer VALID / REVOKED / REPLACED / NOT FOUND with public fields only; logs every lookup |
| `hostel.apply`, `hostel.draw`, `hostel.hold`, `hostel.accept`, `hostel.checkin`, `hostel.transfer`, `hostel.inspect`, `hostel.charge`, `hostel.complete_clearance`, `hostel.lapse_holds` | The bed lifecycle from application to clearance; `confirm_by_reference` is called by `finance.confirm_payment` |
| `admissions.application_stage(application)` | Derives the applicant's milestone 0–9 from the timestamps on the application, the registration and the student record |
| `admissions.merit_list(session, programme)` / `decide_application` / `release_decisions` | Ranks eligible applicants, fills the quota in basis order NM → SM → ELG → LOCALITY, records and releases decisions |
| `admissions.pg_apply`, `pg_dept_decide`, `pg_faculty_decide`, `pg_spgs_decide`, `pg_accept`, `pg_admit` | The postgraduate pipeline; `pg_admit` opens the student record and account |
| `admissions.putme_generate` / `putme_publish` / `putme_move` / `putme_checkin` | Post-UTME CBT seating, publication with notices, check-in |
| `people.deferment_save` / `deferment_submit` / `deferment_decide` / `deferments_tick` / `deferment_confirm_return` | Deferment lifecycle and the daily clock |
| `platform.queue_notice(...)` | The outbox: every email and SMS is queued in the transaction that wrote the fact it announces |
| `platform.next_number(kind, scope, session)` | Every reference series (§1.7.2) |
| `college.register_level` / `register_semester` / `decide` / `apply_provisional` / `confirm_decisions` / `grant_appeal` | The MB;BS year: fee-gated registration, provisional decisions after every result, Board confirmation on a minute |
| `helpdesk.submit` / `transition` / `resolve` / `auto_close` | Ticket lifecycle with SLA timestamps |
| `hrm.build_pay_run` / `approve_pay_run` / `pay_pay_run` | Payroll with maker–checker |
| `expenditure.raise_voucher` / `advance_voucher` / `pay_voucher` | Voucher chain with BR-006 |

## 1.10 Triggers

`triggers.psv` lists **288 triggers**:

| Category | Count | Examples |
|---|---|---|
| Audit spine (`audit.record`, AFTER INSERT OR UPDATE OR DELETE) | 258 | one per attached table |
| Write-once trails (`BEFORE UPDATE` / `BEFORE DELETE OR UPDATE`, raise 23514) | 7 | §1.6 |
| Record immutability | 1 | `people.matric_is_immutable` on `people.student` |
| Deferment gates (`people.deferment_refuse` when an APPROVED/ACTIVE deferment covers the period) | 4 | `registration.course_registration`, `admissions.pg_registration`, `college.enrolment`, `college.enrolment_semester` |
| Derivation on write | 3 | `people.fill_curriculum` (track and curriculum version), `finance.wallet_entry_source` (SELF / NELFUND), `hostel.room_before_write`/`room_after_write` (legacy `out_of_service` kept in step) |
| Validation on write | 3 | `admissions.assert_row_matches_batch` (a CAPS row belongs to its batch), `assessment.score_within_split` (CA ≤ `ca_max`, exam ≤ the rest), `iam.guard_coordinator_grant` (the MBBS Coordinator grant's scope) |
| Cross-module reactions (AFTER) | 6 | `assessment.trg_registration_releases_held` and `trg_entry_releases_held` (an approved registration releases held scripts), `credentials.score_changed` and `credentials.graduand_changed` (flag issued documents when a result or award changes), `credentials.request_paid` (stamp the SLA when a request is paid), `admissions.putme_flag_programme_change` (a programme change after seating asks for review) |
| Trails written by trigger (AFTER) | 4 | `admissions.pg_application_trail`, `pg_referee_trail`, `pg_research_trail` (event rows and the applicant's notices), `admissions.screening_assignment_sync` (seating history from `application.screening_batch_id/seat`) |
| Deferred constraint trigger | 1 | `finance.gl_balance` on `finance.gl_posting` |

> **Note:** Because `audit.record` is an `AFTER` trigger inside the same transaction, a write that is **refused** (rolled back) leaves no audit entry. Only actions a module records explicitly with a `REFUS…` action, and failed sign-ins in `iam.sign_in_event`, appear on the Audit Trail as refusals.

## 1.11 The reporting schema and saved reports

The `reporting` schema (`V001`) is reserved for derived read models and is exempt from the spine wholesale; it must never hold state that is not reproducible from audited events. Today it holds a single function, `reporting.student_positions()`, which computes a student's fee position across sessions for the student statistics engine (V257). The saved-report feature (V229) lives in `reports`, which **is** audited: `reports.catalogue` (slug, title, the due cadence of each return) and `reports.snapshot` (a kept copy of a report as run: parameters, rows as jsonb, who ran it, a verification code that the public `/verify/report` route answers). The reporting functions `reports.due_register`, `reports.due_around` and `reports.period_for` drive the due register on `/reports`. Student statistics (V257) read the live tables through functions in `people`, `finance` and `registration`, not through materialised views.

---

# 2 Entity-relationship overview by domain

Each diagram shows the core tables of a domain and the foreign keys that actually exist between them (from `tables.psv` *References*). An arrow `A ──child_col──▶ B` reads "A.child_col references B". Tables from other schemas are shown with their schema prefix. Columns named on the arrows are the referencing columns as they appear in `columns.psv`. Tables with no foreign key are shown standing alone.

## 2.1 Identity and access

```text
                     ┌──────────────┐
                     │  ref.office  │  code PK — the 34 offices
                     └──────▲───────┘
                            │ office_code
 ┌────────────────┐   ┌─────┴──────────────────┐   ┌───────────────────────┐
 │  iam.person    │◀──│  iam.office_assignment │   │  platform.session     │──active_office──▶ ref.office
 │  id PK         │   │  person_id, office_code│   │  person_id (no FK)    │   (staff sessions)
 │  staff_number  │   │  scope_kind, scope_id  │   └───────────────────────┘
 └───▲────▲───▲───┘   │  instrument, valid_from│
     │    │   │       └────────────────────────┘
     │    │   │ person_id
     │    │   └──────────────── iam.credential_event  (SET/RESET/CHANGED/LOCKED/UNLOCKED)
     │    │ person_id
     │    └──────────────────── iam.credential  (person_id PK; password hash; audit-exempt)
     │ person_id
     └───────────────────────── people.student.person_id  (a student who is also a person, PG)

 iam.student_account ──student_id──▶ people.student        (the student portal login; audit-exempt)
 iam.sign_in_event   (staff sign-ins; no FK; audit-exempt)
 iam.student_event   (student sign-ins; no FK; audit-exempt)
 iam.password_reset  (staff reset tokens; no FK; audit-exempt)
```

A person may hold several offices at once (`office_assignment` rows), each with a scope (`institution`, `college`, `faculty`, `department`, `programme`, `course`, `unit`, `platform`, `level`) and an instrument; a grant is ended (`iam.end_grant`), not deleted. The student's login is a separate table keyed on the student, not the person.

## 2.2 People and students

```text
 admissions.candidate ◀──candidate_id──┐        ┌──programme_code──▶ ref.programme ──▶ ref.department ──▶ ref.faculty ──▶ ref.college
 iam.person          ◀──person_id─────┤        │                         │ matric_series          │ matric_series
 policy.curriculum_track ◀─────────────┤        │                         ▼                        ▼
 people.matriculation_run ◀───────────┤        │                   people.matric_series ◀──series_code── people.matric_history
                                      │        │                                                          │ student_id, run_id
                             ┌────────┴────────┴──┐                                                       │
                             │   people.student   │◀──────────────────────────────────────────────────────┘
                             │ id PK              │
                             │ admission_no UQ    │◀──student_id── people.enrolment ──session──▶ policy.academic_session
                             │ matric_no UQ       │◀──student_id── people.student_contact (student_id PK)
                             │ status (CHECK)     │◀──student_id── people.status_change   (instrument required)
                             │ programme_code     │◀──student_id── people.biodata ──field──▶ ref.biodata_field
                             │ current_level      │◀──student_id── people.biodata_change
                             └──▲──────▲──────────┘◀──student_id── people.document
                                │      │
                 student_id     │      │ student_id
   people.deferment ────────────┘      └──────── people.transfer_application ──from/to_programme_code──▶ ref.programme
     ├─reason_code──▶ people.deferment_reason
     ├─extension_of──▶ people.deferment (self)
     ├─session──▶ policy.academic_session
     ├◀─deferment_id── people.deferment_document ──▶ people.deferment_document_blob
     └◀─deferment_id── people.deferment_event   (write-once)

 people.matriculation_run ──session──▶ policy.academic_session
 people.faculty_list ──▶ policy.academic_session, ref.faculty ◀──list_id── people.faculty_list_query ──student_id──▶ people.student
 people.matric_format   (single row 'UNIVERSITY': university code, components on/off, separator, padding)
```

`people.student` is the register. It is created by intake with an admission number and becomes ACTIVE with a matriculation number; both numbers are immutable by trigger. Every change of status is a `status_change` row with an instrument. Since V263 the faculty and programme carry the segment and series the matriculation number is built from: `ref.faculty.matric_code` and `matric_series`; `ref.programme.matric_code`, `matric_uses_code` (whether the programme segment appears at all), `matric_faculty_code` (a programme's own faculty segment, as for MB;BS) and `matric_series`.

## 2.3 Undergraduate admissions

```text
 ref.office ◀──uploaded_office── admissions.caps_batch  (the file from JAMB: list_kind UTME/DIRECT_ENTRY, sha256, committed_at)
                                        ▲ batch_id
                                admissions.caps_row  (verbatim rows; audit-exempt)       admissions.caps_row_excluded ──batch_id──▶ caps_batch
                                        ▲ admitted_from (caps_row)
                                admissions.candidate  (the University's record; offer_state CHECK)
                                  ▲ candidate_id      ▲ candidate_id           ▲ candidate_id
   admissions.applicant_account ──┘      admissions.attachment ──┘      admissions.jamb_admission ──┘
     (audit-exempt; jamb_key, email)        (PASSPORT / DATE_OF_BIRTH / OLEVEL; audit-exempt)
        ▲ account_id                            ▲ attachment_id
   admissions.application ──candidate_id──▶ candidate     admissions.olevel_sitting ──▶ olevel_grade (sitting_id, subject)
     │ application_no UQ, fee/submit/score/decision/accept/clear timestamps
     ├◀─application_id── admissions.fee_reference        (APPLICATION | ACCEPTANCE)
     ├◀─application_id── admissions.application_document ──▶ application_document_blob
     ├◀─application_id── admissions.clearance_document   (six items)
     ├◀─application_id── admissions.screening_assignment ──batch_id──▶ screening_batch, ──workstation_id──▶ cbt_workstation
     ├◀─application_id── admissions.putme_event          (write-once)
     └──screening_batch_id──▶ admissions.screening_batch ──▶ putme_exam, putme_slot, cbt_centre, cbt_room

 admissions.putme_exam ◀── putme_day, putme_slot, putme_exam_centre ──▶ cbt_centre ◀── cbt_room ◀── cbt_workstation

 admissions.session_policy  (DRAFT / IN_FORCE / SUPERSEDED)
   ◀──policy_id── programme_rule ──programme_code──▶ ref.programme   ◀──rule id── rule_subject_group ◀── rule_subject
   ◀──policy_id── faculty_quota ──▶ ref.faculty
   ◀──policy_id── programme_closed ──▶ ref.programme;  catchment_lga;  selection_criterion;  programme_olevel_allowance
 admissions.load_cutoff, olevel_grading ◀── olevel_grade_point, olevel_compulsory, screening_exam_programme, applicant_fee  (per session)
   ◀──policy_id── subject_equivalence  (V266; every rules table bumps session_policy.rules_version)

 admissions.application ◀──application_id── eligibility_run  (V266: one current per application; policy_id, rules_version, applied_result, alternatives, stale, superseded_at)
                                              ◀──run_id── eligibility_result  (APPLIED | ALTERNATIVE per programme; checks jsonb, reasons; audit-exempt)
                        ◀──application_id── eligibility_event  (write-once trail)   ◀──application_id── programme_change_request  (REQUESTED → APPROVED / REJECTED / CANCELLED)
```

The chain is *file → row → candidate → account → application*. The row from JAMB is kept verbatim and audit-exempt; the act of loading it is audited on the batch. Policy for a session hangs off `session_policy`, which is frozen once `IN_FORCE`.

## 2.4 Postgraduate admissions, coursework and research

```text
 admissions.pg_applicant  (email, phone, password hash; audit-exempt)
        ▲ applicant_id
 admissions.pg_application ──programme_code──▶ ref.programme (category POST GRADUATE)
   │ application_no PG/YY/NNNNNN, state CHECK, dept/fac/spgs decisions, fee timestamps
   ├──student_id──▶ people.student   (set by pg_admit)          ├──▶ iam.person (decider columns)
   ├◀─application_id── pg_referee        (token, verdict)
   ├◀─application_id── pg_fee_reference  (APPLICATION | CHECKING | ACCEPTANCE)
   ├◀─application_id── pg_document       (audit-exempt)
   ├◀─application_id── pg_prior_degree
   └◀─application_id── pg_application_event   (written by trigger)

 admissions.pg_academic_session ◀──session── pg_semester            admissions.pg_fee (per session)

 people.student ◀──student_id── admissions.pg_registration ──▶ iam.person (endorser)
                                   ▲ registration_id
                                admissions.pg_registration_entry ──course_id──▶ admissions.pg_course ──programme_code──▶ ref.programme
                                   ▲ entry_id
                                admissions.pg_score ──▶ iam.person (recorder)

 people.student ◀──student_id── admissions.pg_research  (stage CHECK, topic, viva)
                                   ├◀─research_id── pg_research_supervisor ──person_id──▶ iam.person
                                   ├◀─research_id── pg_research_panel
                                   ├◀─research_id── pg_research_document ──▶ pg_research_document_blob
                                   ├◀─research_id── pg_research_event ──▶ iam.person
                                   └◀─pg_research_id── extexam.project  (the external examiner reads it)
 admissions.pg_examiner ◀── extexam.examiner.pg_examiner_id
```

The postgraduate applicant is not an `iam.person`; on admission `pg_admit` creates the `people.student` row, its contact and its `iam.student_account`.

## 2.5 Catalogue and course registration

```text
 ref.department ◀──dept_code── catalogue.course  (code PK 'ABC 123'; units, semester, level, kind, state, ca_max, industrial_training)
                                   ▲ course_code                       ▲ course_code
   ref.programme ◀──programme_code── catalogue.course_offer            catalogue.offering ──session──▶ policy.academic_session
   policy.curriculum_track ◀──track──┘ (course_code, programme_code, level PK; basis)   │ lecturer_id, second_examiner_id ──▶ iam.person
                                                                                        ├◀─offering_id── catalogue.offering_teacher ──▶ iam.person
                                                                                        ├◀─offering_id── catalogue.class_slot
                                                                                        ├◀─offering_id── registration.attendance ──student_id──▶ people.student
                                                                                        ├◀─offering_id── registration.entry
                                                                                        │                    │ registration_id
 people.student ◀──student_id── registration.course_registration ──session──▶ policy.academic_session ◀────┘
                                  (student, session, semester UQ; status DRAFT/SUBMITTED/RETURNED/APPROVED/LOCKED)

 policy.academic_session ◀──session── policy.semester  (number, state, registration_closes, late_registration_closes, query_window)
 policy.level_limit  (level PK; min/max units; probation_max_units — null everywhere)
```

A course is bound to a programme at a level by `course_offer`; an `offering` is the course taught in a session and semester by a lecturer; the student's `entry` rows point at offerings. The menu a student may register from is computed by `registration.student_menu` over these tables.

## 2.6 Assessment and results

```text
 policy.academic_session ◀──session── assessment.exam_session  (MAIN / RESIT / SPECIAL; DRAFT / OPEN / CLOSED)
                                          ▲ exam_session_id
 catalogue.offering ◀──offering_id── assessment.score_sheet  (stage ENTRY … PUBLISHED; senate_minute; published_at)
                                          ▲ sheet_id                ▲ sheet_id              ▲ sheet_id                 ▲ sheet_id
                                 assessment.score            assessment.decision    assessment.held_script     assessment.result_query
                                 (sheet_id, student_id,      (SUBMIT/ADVANCE/RETURN; (HELD/RELEASED/LAPSED/    (RAISED/UPHELD/CORRECTED/CLOSED)
                                  version PK; ca, exam,       actor, comment)          WITHDRAWN)                ──routed_dept──▶ ref.department
                                  outcome, reason)                                     ──student_id──▶ people.student
                                 ──student_id──▶ people.student                                                  ──student_id──▶ people.student

 catalogue.offering ◀──offering_id── assessment.exam_timetable (offering_id PK)
 catalogue.offering ◀── assessment.siwes_supervisor ──▶ iam.person, people.student
 catalogue.course   ◀──course_code── assessment.question  (CBT question bank)

 policy.version ◀──version_id── policy.grade_band, policy.classification_band     (the scheme GPA and class are computed from)
 people.student ◀──student_id── records.graduand ──session──▶ policy.academic_session   (cgpa, award, senate_state, senate_minute)
```

A score is never overwritten: a change is a new `(sheet_id, student_id, version)` with a reason. GPA, CGPA, standing and class are functions over `score`, `entry` and the policy bands in force; nothing stores a computed GPA on the student.

## 2.7 Finance and payments

```text
 ref.faculty, ref.programme, ref.fee_group ◀── finance.fee_schedule  (session, item, amount + filters; ended_at)
 finance.fee_setting  (home_state, transfer_fee)         finance.funding_source (code PK)

 people.student ◀──student_id── finance.payment_reference  (reference UQ 'MOAUM-FEE-…', purpose, amount, expires_at,
                                    confirmed_at/by, channel, receipt_no UQ)   — no status column; state is derived
        (references are matched by text, not FK, from:)
        finance.gateway_attempt, finance.gateway_event (outcome CHECK), finance.bank_credit (UNMATCHED/PROPOSED/POSTED),
        finance.payment_reconciliation (MATCHED/DISCREPANCY), finance.paydirect_collection, hostel.allocation.reference,
        credentials.transcript_request.reference, admissions.fee_reference / pg_fee_reference (their own tables)

 people.student ◀──student_id── finance.refund  (PROPOSED/APPROVED/REJECTED/PAID)
 people.student ◀──student_id── finance.wallet_entry ──source_code──▶ finance.funding_source
                                    ▲ entry_id
 people.student ◀──student_id── finance.wallet_withdrawal  (REQUESTED/APPROVED/REJECTED/PAID)
 finance.nelfund_batch ◀──batch_id── finance.nelfund_row ──student_id──▶ people.student      finance.nelfund_status ──▶ people.student

 finance.gl_account (code PK, parent_code self) ◀──account── finance.gl_posting ──journal_id──▶ finance.gl_journal (reverses self)
 finance.gateway_credential (gateway PK; audit-exempt) ◀── gateway_credential_event (SET/ROTATED/CLEARED)     finance.paydirect_biller (scope PK)
```

The payment reference is the hub. Everything that can be paid — fees, hostel, transcript, library fine, wallet top-up, transfer fee — mints a reference with a purpose; the Bursary or a gateway confirms it; `confirm_payment` performs the purpose's side effect. Gateway rows refer to the reference by its text so that applicant, student and postgraduate references (three tables) can share one settlement path.

## 2.8 Credentials and documents

```text
 credentials.document_policy (kind PK: DEGREE_CERTIFICATE, TRANSCRIPT, SESSIONAL_TRANSCRIPT, MINI_TRANSCRIPT, ACADEMIC_STATEMENT)
        ▲ kind                                    ▲ kind
 credentials.document_template (version)     credentials.transcript_request  (ref TRN-YYYY-NNNNN; stage CHECK; fee; reference; paid_at; sla_due_on)
                                                 ├──student_id──▶ people.student
                                                 ├──issued_id──▶ credentials.issued
                                                 ├◀─request_id── credentials.delivery ──issued_id──▶ issued, ──token_id──▶ download_token
                                                 └◀─request_id── credentials.event  (write-once) ──▶ issued, people.student

 credentials.issued  (kind, number, version, verification_code UQ, statement jsonb, content_hash, supersedes → issued, flagged_at)
   ├──student_id──▶ people.student        ├──issued_office──▶ ref.office        ├──signed_with──▶ credentials.signing_key (empty)
   ├◀─issued_id── credentials.download_token (STUDENT / RECIPIENT; uses, expiry)
   ├◀─credential_id── credentials.revocation (PK; reason, instrument; ──▶ ref.office)
   └◀─issued_id── credentials.certificate  (printed: PRINTED/COLLECTED/HELD/REISSUED/REVOKED) ──batch_id──▶ stationery_batch, ──▶ people.student
 people.student ◀──student_id── credentials.identity_card  (card_no MOAUM/ID/YY/NNNNN; ISSUED/LOST/REPLACED/RETURNED)
 credentials.verification, lookup_miss, download_log   (public logs; no FK; audit-exempt)

 clearance.unit (code PK) ──office_code──▶ ref.office;  clearance.unit ◀──unit── clearance.item ──student_id──▶ people.student, ──purpose──▶ ref.clearance_purpose, ──superseded_by──▶ clearance.item
```

A document is issued once and kept byte for byte; a reissue is a new `issued` row whose `supersedes` points at the old one, which then verifies as REPLACED. The request table keeps its historical name `transcript_request` although it carries every document kind since V262.

## 2.9 Hostel

```text
 hostel.hall_kind ◀── hostel.hall (code PK; sex, campus, state) ◀──hall_code── hostel.block ◀──block_id── hostel.room ──room_type──▶ hostel.room_type
                                                                                                             │ hall_code ──▶ hall
                                                                                                             ├◀─room_id── hostel.bed (number, state)
                                                                                                             ├◀─room_id── hostel.room_facility ──▶ facility
                                                                                                             └◀─room_id── hostel.asset (also hall, block)
 policy.academic_session ◀──session── hostel.session_setting (window: DRAFT/OPEN/CLOSED/ALLOCATED; fee; rules)

 people.student ◀──student_id── hostel.application  (reference HST-YYYY-NNNNN; state CHECK; review) ──hall_code──▶ hall, ──▶ room_type, ──▶ academic_session
                                     ▲ application_id
 people.student ◀──student_id── hostel.allocation  (reference_no ALC-YYYY-NNNNN; state CHECK; held_until; reference = payment ref; dates)
                                     ├──room_id──▶ room, ──bed_id──▶ bed, ──moved_from──▶ allocation, ──▶ academic_session
                                     ├◀─allocation_id── hostel.inspection (CHECKIN/CHECKOUT) ◀──inspection_id── hostel.damage_charge ──asset_id──▶ asset
                                     ├◀─allocation_id── hostel.clearance (PENDING/CLEARED/NOT_CLEARED) ◀── hostel.clearance_item ──▶ clearance_requirement
                                     ├◀─allocation_id── hostel.transfer_request ──▶ hall, room_type, people.student
                                     └◀─allocation_id── hostel.event (write-once) ──▶ application, bed, room, people.student
 hostel.maintenance_request ──▶ asset, bed, room, people.student
```

A bed is a row, so occupancy is a query over live allocations. The allocation carries the payment reference by text; confirming that reference in finance confirms the bed.

## 2.10 ICT help desk

```text
 helpdesk.category (id PK; label, suggested priority, required detail keys, open)
        ▲ category_id
 helpdesk.ticket  (number UQ 'TICK-YYYY-NNNNN'; status CHECK; priority; requester_kind/id/name/number/email/phone copied in;
                   department_code, faculty_code; details jsonb; assigned/escalated; SLA timestamps; resolution; closure; reopen_count)
   ├──requester_id──▶ iam.person   (staff requester; students by number, no FK)
   ├◀─ticket_id── helpdesk.ticket_comment  (REQUESTER / AGENT / SYSTEM; internal flag) ──author_id──▶ iam.person (no FK)
   ├◀─ticket_id── helpdesk.ticket_attachment ──comment_id──▶ ticket_comment; ──▶ ticket_attachment_blob (audit-exempt)
   └◀─ticket_id── helpdesk.ticket_event  (write-once; action CHECK)
 helpdesk.sla (priority PK; response/resolution hours)      helpdesk.setting (row_no PK; auto_close_days)
```

## 2.11 Human resources and expenditure

```text
 iam.person ◀──person_id── hrm.employment ──(grade, step)──▶ hrm.grade   (staff_no UQ; status ACTIVE/SUSPENDED/ENDED; one live per person)
                               ▲ employment_id
      hrm.payslip ──run_id──▶ hrm.pay_run (DRAFT/APPROVED/PAID/CANCELLED; one per month)   (payslip also ──▶ iam.person)
      hrm.leave_request ──▶ hrm.leave_type, iam.person        (REQUESTED/APPROVED/DECLINED/CANCELLED)
      hrm.movement ──▶ hrm.grade, iam.person                    (17 kinds; REQUESTED/APPROVED/IMPLEMENTED/DECLINED/RETURNED)
      hrm.appraisal ──▶ iam.person                              (SELF/SUPERVISOR/MODERATED)
 iam.person ◀── hrm.staff_record ──▶ ref.faculty, ref.unit;  hrm.staff_profile (person_id PK);  hrm.staff_photo (blob, audit-exempt)
 hrm.vacancy ◀──vacancy_id── hrm.applicant

 expenditure.voucher  (reference PV/YYYY/NNNN; stage WITH_DIRECTOR → WITH_DEPUTY → WITH_AUDITOR → CLEARED → PAID | REJECTED)
   ├◀─voucher_id── expenditure.voucher_act   (append-only; BR-006 no person twice)
   └◀─voucher_id── expenditure.voucher_query (blocks advance until answered)
 expenditure.tender (ADVERTISED/EVALUATED/AWARDED/CANCELLED) ◀──tender_id── expenditure.bid
 expenditure.budget (cost_centre, financial_year PK)   expenditure.requisition   expenditure.store_item   expenditure.asset   expenditure.research_grant
```

> **Note:** Nothing in the API or the migrations inserts `hrm.employment`; the only writers are `db/demo.sql` and `check.sql`. Payroll therefore runs only over demo or test establishments today (dossier F §5.10).

## 2.12 Platform, audit and governance

```text
 platform.notice  (the outbox: channel EMAIL/SMS, to, subject, body, about_kind/about_id, state QUEUED/SENT/FAILED)
        ▲ notice_id
 platform.notice_attachment  (a file queued with a notice)
 platform.number_series  (kind, scope, session PK; next_value)          ← platform.next_number
 platform.session  (staff session tokens) ──active_office──▶ ref.office     (audit-exempt)
 platform.mail_settings, sms_settings (audit-exempt; secrets) ◀── mail_settings_event, sms_settings_event (SET/CLEARED)
 people.student ◀──student_id── platform.service_request ──office_code──▶ ref.office ◀──request_id── platform.request_document ──▶ request_document_blob
 platform.idempotency_key, platform.processed_event   (no FK; nothing reads or writes them)

 audit.entries (24 monthly partitions) ── prev_hash chain per (period, shard) ──▶ audit.chain_head (period, shard PK; last_hash, last_seq)
 audit.subject_key (relid PK; PK columns of each attached table)      audit.exemption (relid PK; reason)
 public.schema_migration (filename PK; sha256; applied_at; applied_by)

 governance.processing_activity (NDPA register; DPIA state)   governance.dsr (DSR-YYYY-NNNN; kind; state)   governance.dr_drill (kind; outcome; RPO/RTO)
 reports.catalogue (slug PK) ◀──report── reports.snapshot ──taken_by──▶ iam.person   (verification_code UQ; filed_to/filed_at when a copy is kept)
 apimgmt.consumer ◀──consumer_id── apimgmt.key
```

`audit.entries.actor_id` and `subject_id` are uuids without foreign keys — an audit row must survive the ending of the person or the table it names.

---

# 3 Important status fields

The table gives the stored values and their meaning as the SQL functions and the dossiers establish them. A value marked *(never set)* is allowed by the CHECK constraint but no function or endpoint writes it — it is **CONFIGURED BUT UNUSED**.

| Table | Column | Values | Meaning of each value |
|---|---|---|---|
| `people.student` | `status` | ADMITTED · ACTIVE · PROBATION · DEFERRED · SUSPENDED · RUSTICATED · WITHDRAWN · EXPELLED · TRANSFERRED_OUT · GRADUATED · DECEASED · DORMANT · VOLUNTARY_WITHDRAWAL | ADMITTED — on the register with an admission number, not yet matriculated (the only status allowed without a matric number). ACTIVE — matriculated and studying (set by the matriculation run). PROBATION — standing below the policy threshold (`assessment.standing_of`). DEFERRED — an approved deferment is in force (set by the deferment clock; `prior_status` kept). SUSPENDED / RUSTICATED / EXPELLED — disciplinary, set manually on an instrument. WITHDRAWN — withdrawn on a Board or Senate instrument (College WITHDRAW_* decisions set it). TRANSFERRED_OUT — manual only. GRADUATED — Senate approved the award (`records.approve_awards`, `pg_award`, College GRADUATE). DECEASED — manual. DORMANT — manual. VOLUNTARY_WITHDRAWAL — four consecutive closed semesters without an approved registration (`registration.effect_voluntary_withdrawals`). Every change is a `people.status_change` row with an instrument. |
| `registration.course_registration` | `status` | DRAFT · SUBMITTED · RETURNED · APPROVED · LOCKED | DRAFT — being built by the student. SUBMITTED — sent for the level adviser/HOD (fee gate and unit range passed). RETURNED — sent back with a comment; editable again. APPROVED — approved (`approved_at/by`); entries become APPROVED. LOCKED *(never set)* — every "APPROVED/LOCKED" test in code is effectively APPROVED. |
| `registration.entry` | `status` | REGISTERED · APPROVED · DROPPED · WITHDRAWN | REGISTERED — chosen. APPROVED — on approval of the registration (or at once when added to an approved one). DROPPED — dropped in the add/drop window. WITHDRAWN *(never set)*. |
| `admissions.application` | derived stage (`admissions.application_stage`) | 0 · 1 · 2 · 3 · 4 · 5 · 6 · 7 · 8 · 9 | 0 account created; 1 application fee confirmed; 2 submitted; 3 seated for screening; 4 score released; 5 decision released; 6 accepted (undertaking + acceptance fee); 7 cleared (six documents VERIFIED); 8 approved course registration for the session; 9 matriculation number on the student record. |
| `admissions.application` | `decision` | OFFERED · WAITING · NOT_OFFERED | The desk's or merit list's decision, hidden from the applicant until `decision_released_at`; basis NM / SM / ELG / LOCALITY / PLWD / OTHER. |
| `admissions.candidate` | `offer_state` | PROPOSED · ADMITTED · ACCEPTED · DECLINED · LAPSED · WITHDRAWN | PROPOSED — created at registration or import. ADMITTED — an OFFERED decision released, or JAMB's list says Accept. ACCEPTED — `settle_acceptance` (undertaking signed and acceptance fee confirmed). DECLINED — the applicant declined. WITHDRAWN — the CAPS list was withdrawn. LAPSED *(never set)* — offers do not lapse automatically. |
| `admissions.session_policy` | `state` | DRAFT · IN_FORCE · SUPERSEDED | DRAFT — editable. IN_FORCE — put in force on a minute; weights, ratios, criteria, cut-offs and subject rules frozen. SUPERSEDED *(never set)*. |
| `admissions.putme_exam` | `state` | DRAFT · CONFIGURING · OPEN_FOR_SCHEDULING · SCHEDULING_IN_PROGRESS · SCHEDULED · ONGOING · COMPLETED · CANCELLED | The examination event's life; SCHEDULING_IN_PROGRESS is set by `putme_generate`, SCHEDULED only by `putme_publish` ("A schedule is published, not declared."). |
| `admissions.screening_batch` | `state` | DRAFT · PUBLISHED · POSTPONED · CANCELLED | DRAFT — generated, invisible to applicants. PUBLISHED — slips available, applicants notified. POSTPONED / CANCELLED — everyone unseated with the reason. |
| `admissions.screening_assignment` | `state` / `attendance` / `exam_status` | ACTIVE · SUPERSEDED · CANCELLED / NOT_CHECKED_IN · CHECKED_IN · PRESENT · ABSENT · DISQUALIFIED / NOT_STARTED · IN_PROGRESS · COMPLETED · ABSENT · DISQUALIFIED | One ACTIVE seating per application; a move leaves SUPERSEDED, an unseating CANCELLED; attendance and examination status ride on the active row. |
| `admissions.pg_application` | `state` | DRAFT · SUBMITTED · DEPT_RECOMMENDED · DEPT_DECLINED · FAC_RECOMMENDED · FAC_DECLINED · OFFERED · NOT_OFFERED · ACCEPTED · ADMITTED | SUBMITTED on public apply (DRAFT survives only from the older `pg_register`); the department recommends or declines; the faculty likewise; the School offers or not; ACCEPTED on the acceptance fee (or the desk's `pg_accept`); ADMITTED when `pg_admit` opens the student record. Declines are terminal. Reported as DECISION_LOCKED to the applicant until the checking fee is paid. |
| `admissions.pg_registration` | `state` | DRAFT · SUBMITTED · ENDORSED | Coursework registration per semester; SUBMITTED on save, ENDORSED by the desk. |
| `admissions.pg_research` | `stage` | REGISTERED · SUPERVISED · PROPOSAL_SUBMITTED · PROPOSAL_APPROVED · SEMINAR_HELD · TITLE_REGISTERED · PANEL_CONSTITUTED · DRAFT_SUBMITTED · VIVA_HELD · CORRECTIONS · FINAL_SUBMITTED · CLEARED · AWARD_RECOMMENDED · AWARDED · WITHDRAWN | The research pipeline in order; a viva may re-enter from CORRECTIONS; AWARDED writes the graduand and GRADUATED; WITHDRAWN is terminal. |
| `admissions.pg_research_document` | `status` | SUBMITTED · ACCEPTED · RETURNED | Per version; a new version never replaces an old one. |
| `assessment.exam_session` | `state` | DRAFT · OPEN · CLOSED | DRAFT — created. OPEN — sheets made (`open_exam_session`). CLOSED *(never set)*. |
| `assessment.score_sheet` | `stage` | ENTRY · VERIFICATION · DEPT_BOARD · FACULTY_SCRUTINY · FACULTY_COMPILATION · FACULTY_BOARD · RECORDS · SENATE · PUBLISHED | The approval chain; each move is an `assessment.decision` (SUBMIT from ENTRY, ADVANCE, RETURN back to ENTRY with a comment); PUBLISHED needs `published_at` and `senate_minute`. |
| `assessment.score` | `outcome` | GRADED · ABSENT · WITHHELD · INCOMPLETE · MALPRACTICE · EXEMPTED | GRADED carries CA and exam; the others are outcomes without a mark. A blank is not an outcome. |
| `assessment.held_script` | `state` | HELD · RELEASED · LAPSED · WITHDRAWN | HELD — a mark from a candidate not on the roll. RELEASED — an approved registration released it into the sheet. LAPSED — late registration closed. WITHDRAWN — by the lecturer. |
| `assessment.result_query` | `state` | RAISED · UPHELD · CORRECTED · CLOSED | One answer; CORRECTED has no mechanical effect on the published sheet. |
| `records.graduand` | `senate_state` | AWAITING · APPROVED · REFERRED | APPROVED needs a minute, no unmet items and a CGPA; REFERRED *(never set)*. |
| `catalogue.course` | `state` | BOARD · SENATE · LIVE · ENDED | BOARD — created, awaiting approval. SENATE *(never set by a function)*. LIVE — offered. ENDED — ended with `ended_on`; restorable. |
| `policy.academic_session` / `policy.semester` | `state` | PLANNED · CURRENT · CLOSED / NOT_YET_OPEN · OPEN · CLOSED | The University calendar; one CURRENT session; a semester's dates govern registration and add/drop. |
| `finance.payment_reference` | derived (`finance.reference_state`) | OPEN · EXPIRED · CONFIRMED | OPEN — unconfirmed and within 24 hours. EXPIRED — unconfirmed past `expires_at`. CONFIRMED — `confirmed_at` set with `confirmed_by`, `channel`, `receipt_no`. |
| `finance.gateway_event` | `outcome` | SETTLED · ALREADY_SETTLED · UNKNOWN_REFERENCE · SHORT_PAID · NOT_SUCCESSFUL · IGNORED · BAD_SIGNATURE · GATEWAY_ERROR | Every webhook or verification outcome, logged whether or not it confirmed anything. |
| `finance.bank_credit` | `state` | UNMATCHED · PROPOSED · POSTED · REVERSED | UNMATCHED — recorded. PROPOSED — an officer names the reference. POSTED — a different officer approves and the payment is confirmed. REVERSED *(never set)*. |
| `finance.refund` | `state` | PROPOSED · APPROVED · REJECTED · PAID | Maker–checker; PAID records the payout, it does not execute it. |
| `finance.wallet_entry` | `kind` | CREDIT · TOPUP · APPLIED · REVERSED · REFUND | CREDIT and TOPUP add; APPLIED, REVERSED and REFUND subtract; the balance is the signed sum. |
| `finance.wallet_withdrawal` | `state` | REQUESTED · APPROVED · REJECTED · PAID | Approved by the Bursary, paid by a different officer. |
| `finance.nelfund_row` / `nelfund_status` | `state` | MATCHED · UNMATCHED · REVERSED / APPROVED · NOT_APPROVED · PENDING | A disbursement row matched to a studying student (credit posted), unmatched (owner Registry or Bursary), or reversed to the Fund; the Fund's own status per student. |
| `finance.gl_journal` | `status` | POSTED · REVERSED | A journal is reversed by another journal, never edited. |
| `credentials.transcript_request` | `stage` | AWAITING_PAYMENT · HELD_AT_CLEARANCE · READY · PROCESSING · GENERATED · CORRECTION · VERIFIED · RELEASED · DELIVERED · COMPLETED · REJECTED · CANCELLED | AWAITING_PAYMENT — fee due. HELD_AT_CLEARANCE — full transcript, TRANSCRIPT clearance not clear. READY — free or paid and clear. PROCESSING — validation started. GENERATED — document issued (a version). CORRECTION — QC asked for a regeneration. VERIFIED — QC approved. RELEASED — a second officer authorised release; deliveries opened. DELIVERED — every delivery delivered or the student's token spent. COMPLETED — closed by the desk. REJECTED — closed at QC. CANCELLED — by the student or desk before processing. |
| `credentials.issued` | derived (`credentials.document_status`) | ACTIVE · REVOKED · REPLACED | ACTIVE — verifies VALID. REVOKED — a `revocation` row exists (Registrar or Vice-Chancellor, citing the minute). REPLACED — a later version supersedes it. Flags (`flagged_at`) are orthogonal. |
| `credentials.delivery` | `state` | NOT_SENT · READY · SENT · DELIVERED · FAILED · EXPIRED · RESENT (digital) · PROCESSING · DISPATCHED · IN_TRANSIT · DELIVERED · RETURNED (physical) | Digital deliveries by token and email; physical by courier with tracking, the desk picking the state. |
| `credentials.certificate` (printed) | `status` | PRINTED · COLLECTED · HELD · REISSUED · REVOKED | The stationery register; REISSUED marks the original when a duplicate is printed; REVOKED *(never set)*. |
| `credentials.identity_card` | `state` | ISSUED · LOST · REPLACED · RETURNED | One live card per student; RETURNED *(never set)*. |
| `clearance.item` | `state` | HELD · CLEARED | A HELD row names the item outstanding; rows are appended and the latest by `decided_at` counts. |
| `hostel.session_setting` | `state` | DRAFT · OPEN · CLOSED · ALLOCATED | The application window; ALLOCATED after the draw. |
| `hostel.application` | `state` | APPLIED · ALLOCATED · CONFIRMED · LAPSED · UNSUCCESSFUL · WITHDRAWN · REJECTED | APPLIED — in the window. ALLOCATED — seated by the draw or by hand. CONFIRMED — fee confirmed. LAPSED — the hold expired. UNSUCCESSFUL — waitlisted. WITHDRAWN — by the student, the desk, a decline or a cancellation. REJECTED — at review. |
| `hostel.allocation` | `state` | HELD · CONFIRMED · ACCEPTED · CHECKED_IN · CHECKED_OUT · DECLINED · LAPSED · CANCELLED · TRANSFERRED | HELD — a bed held until `held_until` pending the fee. CONFIRMED — fee confirmed (or no fee). ACCEPTED — rules accepted by the student. CHECKED_IN — by the porter. CHECKED_OUT — clearance completed. DECLINED — by the student. LAPSED — by the clock. CANCELLED — by the desk. TRANSFERRED — the old row on a move. |
| `hostel.transfer_request` | `state` | SUBMITTED · UNDER_REVIEW · APPROVED · REJECTED · COMPLETED · CANCELLED | Approval with a bed goes straight to COMPLETED; CANCELLED *(never set)*. |
| `hostel.clearance` / `clearance_item` | `state` | PENDING · CLEARED · NOT_CLEARED / PENDING · CLEARED · NOT_CLEARED · WAIVED · NOT_APPLICABLE | Check-out clearance and its nine seeded items. |
| `helpdesk.ticket` | `status` | SUBMITTED · OPENED · IN_PROGRESS · RESOLVED · CLOSED · REOPENED | SUBMITTED — raised. OPENED — an agent opened it. IN_PROGRESS — being worked (first response stamped). RESOLVED — resolution summary and details recorded. CLOSED — confirmed by the requester, closed by an agent with a reason, or auto-closed after `auto_close_days`. REOPENED — from RESOLVED/CLOSED with a reason; `reopen_count` increments. |
| `platform.service_request` | `state` | OPEN · WITH_OFFICE · RESOLVED · CLOSED | OPEN — raised. WITH_OFFICE — answered but not resolved. RESOLVED — answered as resolved. CLOSED *(never set)*. |
| `people.deferment` | `state` | DRAFT · SUBMITTED · CORRECTION_REQUIRED · DEPT_RECOMMENDED · FAC_RECOMMENDED · APPROVED · ACTIVE · COMPLETED · REJECTED · CANCELLED | DRAFT — being written. SUBMITTED — with the department. CORRECTION_REQUIRED — back to the student. DEPT_RECOMMENDED / FAC_RECOMMENDED — recommended upward. APPROVED — by the Academic Office; awaiting its period. ACTIVE — in force (student DEFERRED). COMPLETED — the return confirmed. REJECTED / CANCELLED — closed with a note. Return status UPCOMING / DUE / OVERDUE / RETURNED is derived. |
| `people.transfer_application` | `state` | APPLIED · FROM_OK · TO_OK · REG_OK · EFFECTED · DECLINED · WITHDRAWN · RECOMMENDED · NOT_RECOMMENDED · APPROVED | Pipeline path: APPLIED (fee due) → FROM_OK (releasing department) → TO_OK (receiving department) → REG_OK (Registry) → EFFECTED (programme and level changed). DECLINED at any desk with a reason. Committee path (RECOMMENDED / NOT_RECOMMENDED / APPROVED / WITHDRAWN) exists in SQL but no screen calls it. |
| `people.biodata_change` | `state` | PENDING · EVIDENCE_ASKED · APPROVED · REFUSED | The change queue; no producer exists, so the table stays empty. |
| `college.enrolment` | `state` / `kind` | OPEN · RESIT · CLOSED / REGULAR · REPEAT · APPEAL | A College year: open until the Board confirms; RESIT while a resit is pending; the attempt kind. |
| `college.progression_decision` | `outcome` / `state` | PROMOTE · RESIT · REPEAT · WITHDRAW_ADVISED · WITHDRAW_REQUIRED · APPEAL · GRADUATE / PROVISIONAL · CONFIRMED | Computed provisionally after every result save; confirmed by the Board on a minute. |
| `college.posting_allocation` | `state` | ALLOCATED · IN_PROGRESS · COMPLETED · INCOMPLETE | A student's clinical posting. |
| `hrm.pay_run` | `state` | DRAFT · APPROVED · PAID · CANCELLED | Built, approved by a different officer, paid; cancelled with a reason; one non-cancelled run per month. |
| `hrm.employment` | `status` | ACTIVE · SUSPENDED · ENDED | One live employment per person; ENDED needs `ended_on`. |
| `hrm.leave_request` | `state` | REQUESTED · APPROVED · DECLINED · CANCELLED | Decided by HR with a note; cancelled by the requester. |
| `hrm.movement` | `state` | REQUESTED · APPROVED · IMPLEMENTED · DECLINED · RETURNED | Approved by a second person; IMPLEMENTED on issue of the instrument; RETURNED *(never set)*. |
| `hrm.vacancy` / `hrm.applicant` / `hrm.appraisal` | `state` | OPEN … CANCELLED / APPLIED … APPOINTED / SELF · SUPERVISOR · MODERATED | Free updates; no transition rules enforced. |
| `expenditure.voucher` | `stage` | WITH_DIRECTOR · WITH_DEPUTY · WITH_AUDITOR · CLEARED · PAID · REJECTED | The voucher chain; each advance is a `voucher_act`; an open query blocks; paid only when CLEARED by the Bursary. |
| `expenditure.requisition` / `tender` | `state` / `stage` | RAISED · APPROVED · PO_RAISED · CLOSED · REJECTED / ADVERTISED · EVALUATED · AWARDED · CANCELLED | Requisition approved by a different person; tender evaluated on the first scored bid and awarded to a responsive bid. |
| `extexam.examiner` / `appointment` / `assignment` / `assessment` | `status` / `status` / `status` / `state` | INVITED · PENDING_ACTIVATION · ACTIVE · SUSPENDED · INACTIVE / ACTIVE · ENDED · SUSPENDED / ASSIGNED · IN_REVIEW · SUBMITTED · LOCKED · REOPENED · REASSIGNED · WITHDRAWN / DRAFT · SUBMITTED · LOCKED · REOPENED | The external examiner's account, appointment, project assignment and assessment; appointment SUSPENDED *(never set)*. |
| `health.appointment` / `health.visit` | `state` | BOOKED · SEEN · CANCELLED · MISSED / WAITING · IN_CONSULTATION · DONE · LEFT | MISSED and LEFT *(never set)*. |
| `library.copy` / `library.reservation` | `state` | AVAILABLE · ON_LOAN · RESERVED · LOST · WITHDRAWN / WAITING · READY · FULFILLED · CANCELLED · EXPIRED | Reservation CANCELLED and EXPIRED *(never set)*. |
| `platform.notice` | `state` | QUEUED · SENT · FAILED | The outbox row's dispatch state. |
| `governance.dsr` | `state` | RECEIVED · IN_PROGRESS · COMPLETED · REFUSED | REFUSED is not reachable from the screen. |
| `iam.sign_in_event` | `outcome` | SIGNED_IN · BAD_PASSWORD · UNKNOWN · LOCKED · MUST_CHANGE · SIGNED_OUT · ENDED | MUST_CHANGE and ENDED *(never written)*. |

---

# 4 Operational notes

## 4.1 Backups and disaster recovery

What exists in the database and the portal for backup and recovery is a **log**, not a mechanism (dossier A §A5):

| Item | Status | Detail |
|---|---|---|
| Database backups | Provided by the hosting platform (Railway Postgres) — **not verified** from this repository | No backup, dump or restore script exists in `db/`; nothing in the portal takes or verifies a backup |
| `governance.dr_drill` | IMPLEMENTED (a log) | A drill on record: `kind` RESTORE_VERIFY / FULL_DR / FAILOVER / BACKUP, `ran_on`, `rpo_minutes`, `rto_minutes`, `outcome` PASSED / FAILED / PARTIAL, note. Written from *Disaster Recovery* (`/disaster-recovery`) by the Director of ICT (`ict`) or Super Administrator (`super`) |
| Recovery objectives (RPO ≤ 15 min, 5 min for results and finance; RTO ≤ 4 h; nightly restore verification; daily off-site replication; twice-yearly full drill) | PLACEHOLDER | Typed as literals in `DisasterRecovery.tsx`; not measured, not enforced |
| Backup telemetry, RPO/RTO measurement | NOT IMPLEMENTED | The screen itself says "Continuous backup telemetry is not wired into the portal yet" |
| Audit retention | Documented intent in `V002` | "audit is kept 7 years and archived by partition"; no archiving job exists |
| `app_retention` role | CONFIGURED BUT UNUSED | Created in `V001` as the one role that may delete on a schedule; no grant and no job |

> **Warning:** A restore has never been demonstrated by anything in this repository. Before go-live, the Directorate of ICT should take a platform backup, restore it to a scratch database, run `db/verify.sql` against the restore, and record the drill in `governance.dr_drill`. The migration ledger (`public.schema_migration`) restores with the data, so `migrate.sh` will recognise a restored database and apply only what is missing.

## 4.2 Deployment verification

After every deployment the API's pre-deploy runs `bash db/migrate.sh`, which applies new files and then runs `db/verify.sql` (§1.2.3). A failed pre-deploy leaves the previous deployment serving; the Deployments tab on Railway is where the truth is. The read-only status endpoints then report the schema: `/api/v1/platform/status` and the prototype's `/healthz` name the number of migrations applied and the latest file; the platform dashboard (Director of ICT) renders the same (*02 Administrator Manual*).

## 4.3 Local development cluster

From `README.md` ("Running it locally"):

```bash
# the database
createdb moaumpp
export DATABASE_URL=postgres:///moaumpp
npm run migrate               # bash db/migrate.sh — applies every V-file, then verify.sql
npm run check:db              # psql -f db/check.sql — the property suite; WRITES, use a throwaway database

# the Spring Boot service (Java 21; Maven wrapper)
export MOAUM_AUTH_HMAC_SECRET='<at least thirty-two bytes>'
(cd api && ./mvnw spring-boot:run)          # :8081

# the Next.js frontend (Node 22)
(cd frontend && cp .env.example .env.local && npm ci && npm run dev)   # :3000
```

Points that matter for a local database:

1. `V001` creates roles, so the connecting user must be able to `CREATE ROLE` (a superuser on a local cluster). On a managed database without that right the first migration stops, by design.
2. `migrate.sh` needs `psql` and `sha256sum` on the path (Git Bash on Windows provides both).
3. The API never migrates; run `npm run migrate` first. The API's integration tests (`./mvnw verify`) expect a migrated database at `DATABASE_URL` and leave scratch tables in `public` — the Security screen's "unattached tables" count on a developer database is that residue, not a product defect.
4. `check.sql` removes exactly what it created on its next run, but run it against a throwaway database all the same.
5. The README's "applies V001–V010" and "63 properties" wording predates the current 261 files and 149 declared properties.

> **Tip:** A trust-authentication cluster on a non-default port (for example 5433) keeps a throwaway database for `check.sql`, `demo.sh` and the integration tests apart from any database you care about.

## 4.4 Demo data — `db/demo.sh`

`db/demo.sh` runs `db/demo.sql` against `DATABASE_URL`. It is **not a migration** — `migrate.sh` never runs it — and it is idempotent: CI runs it twice and then `verify.sql`. Every person it makes is invented (surname DEMO, staff numbers `MOAUM/DEMO/nnn`, matriculation numbers at the top of their year so a real run never meets them, courses with the `DMO` prefix). Every write is attributed to a fixed demo actor acting as the office that would perform it. It seeds:

| Area | What is seeded |
|---|---|
| Staff and offices | One `iam.person` per office with an `office_assignment` and a credential (`demo.<office>` sign-ins); the MBBS Coordinator with a level-scoped grant; an ACTIVE external examiner with an appointment |
| Students | Demo students on `people.student` with enrolments and contacts; biodata rows; a payment reference confirmed by bank transfer; an identity card issued by the Library |
| Catalogue and registration | `DMO` courses bound to a programme, offerings with a lecturer and second examiner, an approved registration with entries |
| Assessment | An examination session and a score sheet |
| Finance | A fee schedule for the session and the recommended clearance scheme put in force ("DEMO — BUR/DEMO/1") |
| Admissions | Applicant fees, a CAPS batch and rows, applicant accounts with O'Level attachments, released scores, a merit offer released, an undertaking signed, an acceptance fee confirmed, a screening batch |
| HR and payroll | Demo employments on the establishment, a previous month's pay run approved and paid, the current month built; a leave request awaiting a decision and one approved; a promotion approved awaiting its instrument; an open vacancy with a scored shortlist; one APER appraisal |
| Transfers | One case awaiting the committee, one recommended awaiting Senate |
| Governance | A data-subject request and DR drills |
| Expenditure | A requisition, store items and assets |

The roster of demo accounts and the sign-in password are in `docs/demo-accounts.md` (the password is not reproduced in this manual). Demo rows are removed from a live system by the platform's "Remove demo data only" action (`platform.remove_demo_data`, `remove_demo_courses`); `platform.reset_operational_data` is the wider reset described in *02 Administrator Manual*.

> **Warning:** Do not run `demo.sh` against the University's live database. The runner prints this warning before it starts; it does not refuse.

## 4.5 Data hygiene — configured but unused

Tables, columns and states that exist in the schema and that nothing in the API or the migrations writes, collected from every dossier. They are safe to leave; they should not be relied on in reports.

| Object | Kind | Status | Evidence |
|---|---|---|---|
| `platform.idempotency_key`, `platform.processed_event` | tables | CONFIGURED BUT UNUSED | no Java code reads or writes them; the BFF forwards `Idempotency-Key` but nothing consumes it (A3) |
| `app_retention` role | role | CONFIGURED BUT UNUSED | created in V001; no grant, no job |
| `admissions.candidate.offer_state = LAPSED` | state | CONFIGURED BUT UNUSED | no setter (B) |
| `admissions.session_policy.state = SUPERSEDED` | state | CONFIGURED BUT UNUSED | nothing sets it (B) |
| `admissions.putme_exam.keep_programme`, `registration_deadline`, `kind` | columns | CONFIGURED BUT UNUSED | saved, never read by generation or eligibility (B) |
| `people.biodata_change` (whole queue) | table | CONFIGURED BUT UNUSED | screen and endpoints work but nothing can create a request; `ref.biodata_field` has no `approval` tier (D) |
| Legacy transcript request (`V027` path) | functions/screen | CONFIGURED BUT UNUSED | superseded by documents (V262) (D) |
| `policy.level_limit.probation_max_units` | column | CONFIGURED BUT UNUSED | NULL for every level; the ceiling logic in `student_submit` is inert (D, E) |
| `registration.course_registration.status = LOCKED`; `registration.entry.status = WITHDRAWN` | states | CONFIGURED BUT UNUSED | only refusal checks mention LOCKED; no UPDATE sets either (D) |
| `people.deferment_document.verified_at/verified_by` | columns | CONFIGURED BUT UNUSED | nothing sets them (D) |
| `catalogue.course.state = SENATE` | state | CONFIGURED BUT UNUSED | no function writes it; courses go BOARD → LIVE (D) |
| `library.reservation.state = CANCELLED / EXPIRED` | states | CONFIGURED BUT UNUSED | CHECK only (D) |
| `records.graduand.senate_state = REFERRED` | state | CONFIGURED BUT UNUSED | CHECK only (D) |
| `clearance.item.superseded_by` | column | CONFIGURED BUT UNUSED | nothing sets it; `position()` takes the latest by `decided_at` (D) |
| `assessment.exam_session.state = CLOSED` | state | CONFIGURED BUT UNUSED | no UPDATE to CLOSED (E) |
| `college.carry_over`, `college.project`, `college.department_unit` | tables | CONFIGURED BUT UNUSED | seed data only; no API writer; the decision's `carry_overs` text[] is not copied into `carry_over` (E) |
| Provost dashboard endpoint | backend | CONFIGURED BUT UNUSED | no frontend call (E) |
| `finance.bank_credit.state = REVERSED` | state | NOT IMPLEMENTED | no function (F) |
| General ledger (`finance.gl_*`) | tables | IMPLEMENTED, unused so far | 0 journals locally; manual sync only; accrual accounts exist (F) |
| `hrm.movement.state = RETURNED` | state | CONFIGURED BUT UNUSED | nothing sets it (F) |
| `hrm.employment` | table | no production writer | only `demo.sql` and `check.sql` insert it (F) |
| `hrm.staff_record` | table | written by imports only | `iam.import_lecturers`, `iam.import_staff`; 0 rows locally (F) |
| `credentials.signing_key` | table | empty | hash-only verification; no cryptographic signing (G) |
| `credentials.certificate.status = REVOKED`; `credentials.identity_card.state = RETURNED` | states | CONFIGURED BUT UNUSED | no code sets them (G) |
| `hostel.transfer_request.state = CANCELLED` | state | CONFIGURED BUT UNUSED | nothing sets it (G) |
| `platform.service_request.state = CLOSED` | state | CONFIGURED BUT UNUSED | nothing sets it (G) |
| `health.appointment.state = MISSED`, `health.visit.state = LEFT` | states | CONFIGURED BUT UNUSED | no code sets them (G) |
| `extexam.appointment.status = SUSPENDED` | state | CONFIGURED BUT UNUSED | never set by any endpoint (C) |
| `iam.sign_in_event.outcome = MUST_CHANGE / ENDED` | values | never written | code writes the other five (A) |
| `governance.dsr.state = REFUSED` | state | not reachable from the screen | (A5) |
| `payments`, `notify` schemas | schemas | empty | created and granted in V001; their tables live in `finance` and `platform` |
| `public.*` scratch tables on developer databases | tables | test residue | left by the integration tests; not present on a production database |

Other points of hygiene worth knowing:

- **Sessions that are test residue.** The local database carries policy rows for sessions such as 2097/2098 and 2098/2099 created by tests; a production database should hold only real sessions. Several dashboards fall back to a hard-coded `2026/2027` when no session is CURRENT (A8).
- **No session CURRENT in the postgraduate calendar** makes `admissions.pg_current_session()` fall back to the University's calendar (C).
- **Held scripts released past ENTRY.** `assessment.release_held_scripts` adds a score version to a sheet at any stage, including PUBLISHED (E §C) — a data pattern to expect when reconciling published results.
- **Audit exemptions are rows.** A new state table must be attached (`SELECT audit.attach('schema.table')`) or exempted with a reason in the migration that creates it; otherwise `audit.unattached()` lists it and `check.sql`'s "every state table is attached" property fails. The reporting schema is exempt wholesale, so state never goes there.

---

# 5 Generated catalogue

The catalogue below is generated from the live schema by the inventory tooling (`gen_refs.py` over `tables.psv`, `columns.psv`, `constraints.psv`, `triggers.psv` and the table comments in the migrations). It lists every schema and table with its purpose (the table's `COMMENT` or the migration's section heading where one exists; a short purpose supplied from the dossiers where it was verifiable; otherwise blank), primary key, referenced tables, column count, unique keys, business-trigger count (audit triggers excluded), audit status and the migration it first appears in; then the column detail of every table. The status-and-kind vocabulary is compiled in Part 3 of this volume and, in full, in the *Status and kind columns* section that follows the table catalogue.


## 5.1 Schema summary

Total tables: 331 across 26 schemas (the `public` schema holds only the deployment ledger `public.schema_migration`, described in Part 1, and is not catalogued here). Audit-attached tables: 258; audit-exempt (blobs, public telemetry, reporting): 47.

| Schema | Tables | Purpose |
|---|---|---|
| `admissions` | 67 | Undergraduate and postgraduate admissions: CAPS lists, applicants, screening, Post-UTME, offers, PG applications and research |
| `apimgmt` | 2 | API keys for integrations |
| `assessment` | 10 | Scores, score sheets, results, GPA, standing |
| `audit` | 27 | The audit spine: every attributed change, hash-chained |
| `catalogue` | 5 | Courses, offerings and curriculum |
| `clearance` | 2 | Clearance units and items |
| `college` | 28 | College of Health Sciences (MB;BS) specifics |
| `credentials` | 15 | Issued documents, certificates, transcripts, ID cards, verification |
| `expenditure` | 10 | Vouchers, requisitions, stores |
| `extexam` | 14 | External examiners |
| `finance` | 21 | Fee schedules, charges, payment references, positions |
| `governance` | 3 | Governance instruments |
| `health` | 5 | Health centre |
| `helpdesk` | 8 | ICT help desk tickets |
| `hostel` | 20 | Hostel inventory, applications, allocations, stays |
| `hrm` | 13 | Human resources |
| `iam` | 8 | Persons, accounts, office assignments, sessions |
| `library` | 5 | Library |
| `lms` | 6 | Learning materials |
| `people` | 21 | Students, contacts, status changes, matriculation, deferments, transfers |
| `platform` | 13 | Notices, numbering, settings, correlation |
| `policy` | 9 | Academic sessions, grading and progression policy |
| `records` | 1 | Graduands and records |
| `ref` | 13 | Reference data: faculties, departments, programmes, offices |
| `registration` | 3 | Course registration |
| `reports` | 2 | Saved reports |

## 5.2 Table catalogue by schema

### Schema `admissions` — Undergraduate and postgraduate admissions: CAPS lists, applicants, screening, Post-UTME, offers, PG applications and research

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `applicant_account` | ── the account ───────────────────────────────────────────────────────── | id | candidate | 11 | (candidate_id); (session, jamb_key) | 0 | exempt | V021 |
| `applicant_event` |  | id |  | 6 |  | 0 | exempt | V021 |
| `applicant_fee` | ── the fees, stated per session ──────────────────────────────────────── | session |  | 6 |  | 1 | attached | V021 |
| `application` | One application per applicant account: the fee, submission, screening seat, score, decision, acceptance and clearance timestamps that admissions.application_stage reads | id | applicant_account, candidate, screening_batch | 27 | (account_id); (application_no); (candidate_id) | 2 | attached | V021 |
| `application_document` | A document uploaded by the applicant (O'Level statement, birth certificate, LGA identification, JAMB slip, passport); a new upload of the same kind supersedes the earlier one | id | application | 12 |  | 1 | attached | V021 |
| `application_document_blob` | The bytes of an application document (audit-exempt blob) | document_id | application_document | 2 |  | 0 | exempt | V021 |
| `attachment` | ── everything that arrived, matched or not ──────────────────────────── | id | candidate | 14 | (session, kind, source_name) | 0 | exempt | V007 |
| `candidate` | ── the University's own record ─────────────────────────────────────────── | id | caps_row | 13 | (session, jamb_reg_no) | 2 | attached | V006 |
| `candidate_photo` | ── the current photograph ───────────────────────────────────────────── One per candidate at a time, and superseded rather than overwritten: a photograph replaced in November is still the photograph that screened the candidate in October, and somebody will ask | id | attachment, candidate | 5 |  | 1 | attached | V007 |
| `caps_batch` | ── the file, as it arrived ─────────────────────────────────────────────── | id | ref.office | 16 |  | 1 | attached | V006 |
| `caps_row` | Every row as CAPS gave it, unedited, for ever. The candidate record below is DERIVED from this; if the derivation is ever wrong, the evidence of what JAMB actually sent is still here. The same discipline as the score roll: the register is the thing, and the sc | id | caps_batch | 15 |  | 1 | exempt | V006 |
| `caps_row_excluded` | Rows of a CAPS list read with the batch and not loaded, with the cut-off that applied and the reason. Kept so that "why is my child not on the list" has an answer on record. | id | caps_batch | 11 | (batch_id, jamb_reg_no) | 0 | exempt | V011 |
| `catchment_lga` | The local governments in the University's immediate catchment, per policy. A candidate from one of these carries the Locality basis. Empty until the Office states it. | policy_id, lga | session_policy | 2 |  | 1 | attached | V054 |
| `cbt_centre` | A CBT centre, University-wide and reused across sessions | id |  | 9 | (code) | 1 | attached | V260 |
| `cbt_room` | A room of a CBT centre with its capacity | id | cbt_centre | 8 | (centre_id, code) | 1 | attached | V260 |
| `cbt_workstation` | A numbered workstation in a CBT room | id | cbt_room | 5 | (room_id, number) | 1 | attached | V260 |
| `clearance_document` | One of the six admission clearance items an applicant presents (NOT_PRESENTED / VERIFIED / QUERY) | id | application | 7 | (application_id, item) | 1 | attached | V021 |
| `de_award` | ── 2 · the DE candidate's prior qualification and its subjects ───────────── One award per basis a candidate holds (a few hold two, e.g. NCE and an 'A' Level). Unlike O'Level — which is read from the JAMB attachment and re-derived at will — a DE award is read  | id | iam.person | 8 | (session, jamb_key, basis) | 1 | attached | V200 |
| `de_award_subject` | A subject of a Direct Entry award, read by the DE combination gate | id | de_award | 4 | (award_id, subject) | 1 | attached | V200 |
| `faculty_quota` | ── 2.3 · the faculty quota, and 2.13 · the faculty cut-off ──────────── | policy_id, faculty_code | session_policy, ref.faculty | 6 |  | 1 | attached | V008 |
| `eligibility_event` | ── the trail of the course suggestion engine (V266) ──────────────────── write-once: EVALUATED, RECOMMENDATION_GENERATED, RECOMMENDATION_VIEWED, PROGRAMME_CHANGE_REQUESTED / APPROVED / REJECTED | id | application, eligibility_run | 10 |  | 0 | write-once | V266 |
| `eligibility_result` | one programme's reading within a run — APPLIED or ALTERNATIVE, the verdict, the checks (requirement · candidate · status · mandatory) and the reasons | id | eligibility_run, ref.programme | 12 |  | 0 | exempt | V266 |
| `eligibility_run` | ── one evaluation of one application (V266) ─────────────────────────── the applied programme's verdict, the count of eligible alternatives, the policy and its rules version, the trigger, stale and superseded_at; one current per application | id | application, candidate, session_policy | 20 |  | 1 | attached | V266 |
| `fee_reference` | An applicant's payment reference for the APPLICATION or ACCEPTANCE fee, valid 24 hours, confirmed by the Bursary or a gateway | id | application | 12 | (reference); (receipt_no) | 1 | attached | V021 |
| `jamb_admission` | A row of JAMB's admission status list, matched to a candidate where the registration number is on the register | id | candidate | 20 | (session, jamb_reg_no) | 1 | attached | V081 |
| `load_cutoff` | The one UTME cut-off a session loads its JAMB lists under, stated before the file is uploaded. Faculty and programme cut-offs are the screening's. | session |  | 3 |  | 1 | attached | V024 |
| `olevel_compulsory` | The O'Level subjects a credit is compulsory in, per session. A session that states nothing falls back to English Language and Mathematics. A pass is not a credit and never satisfies one of these. | session, subject |  | 4 |  | 1 | attached | V053 |
| `olevel_grade` | A subject and grade within an O'Level sitting (audit-exempt, derived from the JAMB attachment) | sitting_id, subject | olevel_sitting | 4 |  | 0 | exempt | V020 |
| `olevel_grade_point` | Points per O'Level grade for a session's grading rule | session, grade | olevel_grading | 3 |  | 1 | attached | V020 |
| `olevel_grading` | The Academic Office's rule for turning O'Level grades into a screening score, per session: how many subjects count and the bonus for one or two sittings. The points per grade sit beside it. A session that has stated nothing is read under the defaults the Office gave when the rule was first written down (A1 6 … C6 1, D7 to F9 nothing; 5 subjects; 10 and 6). | session |  | 5 |  | 1 | attached | V020 |
| `olevel_sitting` | ── the sittings, as JAMB sent them ───────────────────────────────────── | id | attachment | 9 | (attachment_id, ord) | 0 | exempt | V020 |
| `password_reset` | ── the password reset ────────────────────────────────────────────────── | id | applicant_account | 6 | (token_hash) | 0 | exempt | V025 |
| `pg_academic_session` | ── 1 · the PG School's sessions (one CURRENT at a time) ───────────────────── | name |  | 8 |  | 1 | attached | V224 |
| `pg_applicant` | ── 1 · the applicant account and the typed biodata (self-contained) ──────── Holds a password hash and the applicant's own biodata; excluded from the audit spine exactly as admissions.applicant_account (V021) is. | id |  | 15 |  | 0 | exempt | V202 |
| `pg_application` | ── 2 · the application, its first degree, proposal and state machine ──────── | id | pg_applicant, iam.person, people.student, ref.programme | 31 | (application_no); (applicant_id) | 2 | attached | V202 |
| `pg_application_event` | Every turn a postgraduate application takes — created, submitted, each fee confirmed, each desk's decision, each reference received, accepted, admitted — written by trigger from the application itself, with the actor. | id | pg_application | 7 |  | 1 | attached | V255 |
| `pg_course` | ── 1 · the course catalogue, per programme (Policy 11) ───────────────────── | id | ref.programme | 9 | (programme_code, code) | 1 | attached | V211 |
| `pg_document` | ── 4 · the uploaded documents (transcript, certificate, CV, proposal) ────── Holds file bytes; excluded from the spine like admissions.attachment (V007). | id | pg_application | 7 |  | 0 | exempt | V202 |
| `pg_examiner` | The postgraduate examiner roster | id |  | 8 |  | 1 | attached | V213 |
| `pg_fee` | ── 5 · the postgraduate application fee, per session ─────────────────────── | session |  | 4 |  | 1 | attached | V202 |
| `pg_fee_reference` | A postgraduate applicant's fee reference (APPLICATION, CHECKING or ACCEPTANCE), valid 24 hours | id | pg_application | 9 | (reference) | 1 | attached | V202 |
| `pg_legacy_holding` | Legacy postgraduate results parked for students not yet on the register | session, semester, matric, course_code |  | 6 |  | 0 | exempt | V214 |
| `pg_prior_degree` | ── 1 · the prior degree(s) the admission rests on ────────────────────────── | id | pg_application | 9 |  | 1 | attached | V210 |
| `pg_referee` | ── 3 · the referees ──────────────────────────────────────────────────────── | id | pg_application | 15 |  | 2 | attached | V202 |
| `pg_registration` | ── 2 · a student's registration for a session/semester (Policy 7) ────────── | id | iam.person, people.student | 10 | (student_id, session, semester) | 2 | attached | V211 |
| `pg_registration_entry` | ── 3 · the courses on a registration ─────────────────────────────────────── | id | pg_course, pg_registration | 4 | (registration_id, course_id) | 1 | attached | V211 |
| `pg_research` | ── 1 · the research record, one per postgraduate student ──────────────────── | id | people.student | 24 | (student_id) | 2 | attached | V209 |
| `pg_research_document` | Every document a candidate submits on their research — proposal, seminar paper, plagiarism report, draft, corrected draft, final copy — numbered by version within its kind. A new version never replaces an old one. | id | pg_research | 15 | (research_id, kind, version) | 1 | attached | V255 |
| `pg_research_document_blob` | The bytes of a research document (audit-exempt blob) | document_id | pg_research_document | 2 |  | 0 | exempt | V255 |
| `pg_research_event` | ── 3 · the milestone log: what happened, when, by whom ────────────────────── | id | pg_research, iam.person | 6 |  | 1 | attached | V209 |
| `pg_research_panel` | A member of a research candidate's examination panel | id | pg_research | 6 |  | 1 | attached | V212 |
| `pg_research_supervisor` | ── 2 · the supervisors assigned to a candidate (Policy 14) ────────────────── | id | pg_research, iam.person | 8 |  | 1 | attached | V209 |
| `pg_score` | ── 4 · the score for a registered course (CA + exam → total → grade) ──────── | id | pg_registration_entry, iam.person | 9 | (entry_id) | 1 | attached | V211 |
| `pg_semester` | ── 2 · the semester windows of each PG session ───────────────────────────── | session, number | pg_academic_session | 10 |  | 1 | attached | V224 |
| `programme_change_request` | a request to move an application to a programme the engine found the candidate eligible for; one open per application; decided by the Office with eligibility re-read at the decision | id | application, candidate, ref.programme, eligibility_run | 19 | (open per application) | 1 | attached | V266 |
| `programme_closed` | A programme closed for admission under a session's policy | policy_id, programme_code | session_policy, ref.programme | 4 |  | 1 | attached | V023 |
| `programme_olevel_allowance` | A per-programme exception to the compulsory O'Level credit: the programme accepts a pass in the named subject (or waives it). For the few programmes whose own requirements differ from the University's general rule. | policy_id, programme_code, subject | session_policy | 3 |  | 1 | attached | V053 |
| `programme_rule` | ── the programme rule ───────────────────────────────────────────────── One row per programme per session. A programme with no row cannot be admitted into: that is the point, not an omission to work around. | policy_id, programme_code | session_policy, ref.programme | 9 |  | 1 | attached | V008 |
| `putme_day` | A day on which a Post-UTME examination sits | exam_id, held_on | putme_exam | 3 |  | 1 | attached | V260 |
| `putme_event` | The Post-UTME trail, written once | id | application, putme_exam, screening_batch | 11 |  | 2 | attached | V260 |
| `putme_exam` | A Post-UTME examination event of a session: its dates, check-in, duration, strategy and state. | id |  | 19 | (session, name) | 1 | attached | V260 |
| `putme_exam_centre` | A CBT centre used by a Post-UTME examination | exam_id, centre_id | cbt_centre, putme_exam | 3 |  | 1 | attached | V260 |
| `putme_slot` | A time slot of a Post-UTME examination | id | putme_exam | 7 | (exam_id, code) | 1 | attached | V260 |
| `rule_subject` | A subject in a programme rule's subject group | group_id, subject | rule_subject_group | 2 |  | 0 | exempt | V008 |
| `rule_subject_group` | ── the subject combination, structured ──────────────────────────────── "Mathematics, Physics and any one of Chemistry, Geography, Fine Arts or Technical Drawing" is not a list. It is two mandatory subjects and a choice of one from four, and a system that stor | id | programme_rule | 6 |  | 0 | exempt | V008 |
| `screening_assignment` | Every seating of a candidate in a screening batch, kept: the one ACTIVE, the earlier SUPERSEDED or CANCELLED with the reason; the check-in, attendance and examination status ride on the active one. | id | application, cbt_workstation, screening_batch | 16 |  | 1 | attached | V260 |
| `screening_batch` | ── the application ───────────────────────────────────────────────────── | id | cbt_centre, cbt_room, putme_exam, putme_slot | 16 | (session, label) | 1 | attached | V021 |
| `screening_exam_programme` | The programmes a session screens by the post-UTME examination. Their screening component is the examination score alone; the O'Level grading is not applied to them. | session, programme_code | ref.programme | 3 |  | 1 | attached | V022 |
| `selection_criterion` | ── 2.4 · the four selection criteria ────────────────────────────────── | policy_id, criterion | session_policy | 3 |  | 0 | exempt | V008 |
| `session_policy` | ── the session's own settings ───────────────────────────────────────── | id |  | 18 | (session) | 1 | attached | V008 |
| `subject_equivalence` | a subject the Secretariat accepts in place of the one a rule names, for OLEVEL, UTME or ANY; nothing is inferred beyond these rows (V266) | id | session_policy | 6 | (policy, subject, equivalent, scope) | 1 | attached | V266 |
| `suggestion_sent` | the record that a candidate has been emailed their suggestions | application_id | application | 4 |  | 0 | exempt | V106 |

### Schema `apimgmt` — API keys for integrations

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `consumer` | An API consumer registered for integration (register only; no key authentication yet) | id |  | 8 |  | 1 | attached | V047 |
| `key` | A key issued to an API consumer | id | consumer | 8 |  | 1 | attached | V047 |

### Schema `assessment` — Scores, score sheets, results, GPA, standing

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `decision` | every decision on a sheet: who, at which desk, which way, and why | id | score_sheet | 9 |  | 1 | attached | V013 |
| `exam_session` | An examination session is the container everything else hangs in. Opening it generates every score sheet at once: one per offering with a lecturer, over the approved register at that moment. An offering with no lecturer generates no sheet, and is listed as suc | id | policy.academic_session | 9 | (session, semester, kind) | 1 | attached | V013 |
| `exam_timetable` | ── the examination timetable and the docket ──────────────────────────── | offering_id | catalogue.offering | 5 |  | 1 | attached | V027 |
| `held_script` | A mark from a candidate who sat the paper without being on the roll, held until an approved registration releases it into the sheet, or the late-registration date passes and it lapses. | id | score_sheet, people.student | 13 |  | 1 | attached | V240 |
| `legacy_result_holding` | Legacy results parked for students not yet on the register | session, semester, matric, course_code |  | 6 |  | 0 | exempt | V204 |
| `question` | A CBT question bank item, per course | id | catalogue.course | 11 |  | 1 | attached | V077 |
| `result_query` | ── the result query ──────────────────────────────────────────────────── | id | score_sheet, people.student, ref.department | 12 | (ref) | 1 | attached | V027 |
| `score` | A mark is never overwritten: an amendment writes a new version and keeps the old one, with the reason and the author (I-RES-5). | sheet_id, student_id, version | score_sheet, people.student | 10 |  | 3 | attached | V013 |
| `score_sheet` | The desks a sheet passes, finer than the spine a student sees (part28): ENTRY → VERIFICATION → DEPT_BOARD → FACULTY_SCRUTINY → FACULTY_COMPILATION → FACULTY_BOARD → RECORDS → SENATE → PUBLISHED | id | exam_session, catalogue.offering | 10 | (offering_id, exam_session_id) | 1 | attached | V013 |
| `siwes_supervisor` | 2. the student -> supervisor map, per SIWES offering | offering_id, student_id | catalogue.offering, iam.person, people.student | 5 |  | 1 | attached | V156 |

### Schema `audit` — The audit spine: every attributed change, hash-chained

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `chain_head` | The last hash and sequence of each (month, shard) chain | period, shard |  | 4 |  | 0 |  | V002 |
| `entries_202609` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202610` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202611` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202612` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202701` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202702` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202703` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202704` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202705` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202706` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202707` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202708` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202709` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202710` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202711` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202712` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202801` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202802` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202803` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202804` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202805` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202806` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202807` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `entries_202808` | Monthly partition of audit.entries (created by audit.ensure_partition) | occurred_at, id |  | 17 |  | 0 |  |  |
| `exemption` | Some tables genuinely should not be on the spine. The first version of this file expressed that as a hardcoded list of schemas, and the list silently swallowed `policy` the moment those tables were added — so a change to what a fee instalment unlocks went unre | relid |  | 2 |  | 0 |  | V002 |
| `subject_key` | The primary key of each attached table, resolved once at attach time rather than by a catalogue lookup on every row. The trigger originally assumed a column called `id`; the first table keyed on anything else (policy.grade_band, on (version_id, grade)) produce | relid |  | 2 |  | 0 |  | V002 |

### Schema `catalogue` — Courses, offerings and curriculum

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `class_slot` | ── the class timetable and the attendance register ───────────────────── | id | offering | 8 |  | 1 | attached | V027 |
| `course` | A course belongs to exactly one department. A new course is a curriculum change — the Faculty Board sees it and Senate approves it — and a course no longer taught is ENDED with a date and stays on every transcript that carries it. | code | ref.department | 14 |  | 1 | attached | V013 |
| `course_offer` | which programme-and-level pairs a course was made available to at creation | course_code, programme_code, level | course, policy.curriculum_track, ref.programme | 5 |  | 1 | attached | V013 |
| `offering` | a course, in a session and semester, in the name of the lecturer the department allocated. Assigning the lecturer is what opens the score sheet. | id | course, iam.person, policy.academic_session | 7 | (course_code, session, semester) | 1 | attached | V013 |
| `offering_teacher` | Co-lecturers of an offering | offering_id, lecturer_id | offering, iam.person | 4 |  | 1 | attached | V158 |

### Schema `clearance` — Clearance units and items

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `item` | A hold names the unit, the officer, the date and the specific item outstanding; a clearance names who signed. A hold with no item against it is visible as such to the Registrar, which is what stops clearance being used as leverage. | id | item, unit, people.student, ref.clearance_purpose | 10 |  | 1 | attached | V013 |
| `unit` | A clearance unit and the office that signs for it | code | ref.office | 7 |  | 1 | attached | V013 |

### Schema `college` — College of Health Sciences (MB;BS) specifics

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `assessment_item` | An assessment item of a posting or examination subject (course test, end-of-posting MCQ or clinical, supervisor evaluation, project, periodic test, OSCE) | id | exam_subject, posting | 9 |  | 1 | attached | V245 |
| `assessment_score` | A continuous-assessment score of a student on an item (UNIQUE student, item, attempt) | id | assessment_item, iam.person, people.student | 7 | (student_id, item_id, attempt_no) | 1 | attached | V245 |
| `attendance_record` | A student's attendance at a posting activity or timetable slot | id | posting, timetable_slot, iam.person, people.student | 8 |  | 1 | attached | V245 |
| `attendance_rule` | ── 8 · attendance: the rule, and the record it is judged on ──────────────── | id | block | 7 |  | 1 | attached | V245 |
| `block` | A clinical block of the College (COM, FAM, MED, OBG, PAE, PHT, PTH, SUG) | id | ref.department | 8 | (code) | 1 | attached | V245 |
| `carry_over` | a course owed across levels (EPS): carried until passed | student_id, code | people.student | 5 |  | 1 | attached | V248 |
| `case_clerking` | A case clerked by a student during a posting | id | posting, iam.person, people.student | 7 |  | 1 | attached | V245 |
| `department_unit` | A unit under a department, each headed by a consultant — Bacteriology, Virology, Parasitology, Immunology, Mycology under Medical Microbiology. | id | iam.person, ref.department | 4 | (dept_code, name) | 1 | attached | V245 |
| `enrolment` | A College student's year at a level: first attempt, repeat year or Senate-approved final attempt; registered once the fees are cleared; RESIT while a resit is pending; CLOSED by the Board's confirmation. | id | level, people.student, policy.academic_session | 13 | (student_id, level, session) | 2 | attached | V248 |
| `enrolment_semester` | A semester of a College year (the prospectus template), registered on its own fees; nothing is graded at its end — the one sitting is the year's. | id | enrolment | 8 | (enrolment_id, ordinal) | 2 | attached | V249 |
| `event_attendance` | A student's attendance at a mandatory event | event_id, student_id, held_on | mandatory_event, people.student | 4 |  | 1 | attached | V245 |
| `exam_result` | ── 10 · the result by attempt, and the progression decision ──────────────── | id | exam_subject, people.student, policy.academic_session | 13 | (student_id, subject_id, session, attempt) | 1 | attached | V245 |
| `exam_subject` | A subject of a professional examination with its CA/examination split and pass mark | id | professional_exam | 10 | (exam_id, name) | 1 | attached | V245 |
| `level` | ── 2 · levels and their phase ────────────────────────────────────────────── | level |  | 4 |  | 1 | attached | V245 |
| `mandatory_event` | A mandatory event of a block | id | block | 4 | (block_id, name) | 1 | attached | V245 |
| `posting` | A clinical posting under a block at a level | id | block, level | 11 | (block_id, code) | 1 | attached | V245 |
| `posting_allocation` | A student's allocation to a posting and rotation group in a session | id | posting, rotation_group, iam.person, people.student, policy.academic_session | 10 | (student_id, posting_id, session) | 1 | attached | V245 |
| `posting_course` | The courses a posting carries, by the prospectus' code; the catalogue is the owner of the course once it is loaded there. | posting_id, course_code | posting | 5 |  | 1 | attached | V245 |
| `procedure_log` | A procedure observed or performed by a student against a requirement | id | procedure_requirement, iam.person, people.student | 8 |  | 1 | attached | V245 |
| `procedure_requirement` | ── 7 · logbooks: procedures, cases, mandatory events ─────────────────────── | id | posting | 5 | (posting_id, name) | 1 | attached | V245 |
| `professional_exam` | ── 9 · the Professional examinations, their subjects, CA items and scores ── | id | level | 13 | (code) | 1 | attached | V245 |
| `programme_rule` | ── 1 · the programme's rule ──────────────────────────────────────────────── | programme_code | ref.programme | 11 |  | 1 | attached | V245 |
| `progression_decision` | The provisional or Board-confirmed progression decision of a student for an examination | id | level, people.student, policy.academic_session | 14 | (student_id, from_level, session) | 1 | attached | V245 |
| `project` | A student's College project (no API writer; seed only) | id | block, iam.person, people.student | 9 |  | 1 | attached | V245 |
| `rotation_group` | ── 5 · rotation groups and a student's allocation ────────────────────────── | id | posting | 3 | (posting_id, label) | 1 | attached | V245 |
| `semester` | A session's dated semester at a level — the prospectus gives lengths, never dates; the College enters them. | id | level, policy.academic_session | 7 | (session, level, ordinal) | 1 | attached | V245 |
| `semester_template` | ── 3 · semesters: the template the prospectus gives, and the session's own once the College dates it ── | level, ordinal | level | 5 |  | 1 | attached | V245 |
| `timetable_slot` | ── 6 · the timetable: Psychiatry's eight weeks are the only full data ────── | id | posting | 8 | (posting_id, week_no, weekday, starts_at) | 1 | attached | V245 |

### Schema `credentials` — Issued documents, certificates, transcripts, ID cards, verification

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `certificate` | A certificate cannot be printed before Senate approves the award, and the stationery serial is tracked from issue to collection, so a spoiled certificate is accounted for. Certificates awarded before 30 December 2024 were issued as Benue State University, Maku | id | certificate, issued, stationery_batch, people.student | 16 | (number) | 1 | attached | V013 |
| `delivery` | A delivery of an issued document: digital by token, or physical by courier with tracking | id | issued, transcript_request | 16 |  | 1 | attached | V262 |
| `document_policy` | The policy per document kind: billable, fees, SLA, self-service, number prefix, the fields a stranger may see | kind |  | 17 |  | 1 | attached | V262 |
| `document_template` | A versioned template of a document kind; every issued document stays under its version | id | document_policy | 13 | (kind, version) | 1 | attached | V262 |
| `download_log` | Downloads made with a token (audit-exempt; written on behalf of the holder) | id |  | 8 |  | 0 | exempt | V262 |
| `download_token` | An expiring, use-limited token to download an issued document (STUDENT or RECIPIENT) | id | issued | 10 | (token) | 1 | attached | V262 |
| `event` | The write-once trail of document requests and issued documents | id | issued, transcript_request, people.student | 11 |  | 2 | attached | V262 |
| `identity_card` | ── the identity card ─────────────────────────────────────────────────── | id | people.student | 9 | (card_no) | 1 | attached | V027 |
| `issued` | ── the credential ──────────────────────────────────────────────────────── | id | issued, signing_key, transcript_request, ref.office | 22 | (verification_code) | 1 | attached | V005 |
| `lookup_miss` | Failed public verification lookups (audit-exempt) | id |  | 3 |  | 0 | exempt | V005 |
| `revocation` | ── revocation, which is an act like any other ──────────────────────────── Everything consequential in this design carries its authority: an office assignment cites an instrument, a fee schedule a Council minute, a returned result set a reason that cannot be e | credential_id | issued, ref.office | 7 |  | 1 | attached | V005 |
| `signing_key` | Signing keys, effective-dated. A key stops signing and is never retired from verification: a 2027 certificate must verify in 2071 against the 2027 key. There is deliberately no column for a private key. | id |  | 8 |  | 1 | attached | V005 |
| `stationery_batch` | A batch of certificate stationery | id |  | 7 | (batch) | 1 | attached | V013 |
| `transcript_request` | A document request of any kind (transcript, statement, certificate) and its pipeline stage; the table keeps its historical name | id | document_policy, issued, people.student | 40 | (ref) | 2 | attached | V013 |
| `verification` | The public verification log (audit-exempt; a stranger has no acting office) | id |  | 8 |  | 0 | exempt | V262 |

### Schema `expenditure` — Vouchers, requisitions, stores

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `asset` | ── the fixed-asset register ── | id |  | 10 | (tag) | 1 | attached | V076 |
| `bid` | A bid on a tender with its technical and financial scores | id | tender | 8 |  | 1 | attached | V046 |
| `budget` | The budget per cost centre and financial year | cost_centre, financial_year |  | 5 |  | 1 | attached | V045 |
| `requisition` | ── procurement requisitions ── | id |  | 13 | (reference) | 1 | attached | V076 |
| `research_grant` | ── research grants ── | id |  | 11 | (reference) | 1 | attached | V076 |
| `store_item` | ── stores: consumable inventory ── | id |  | 8 | (code) | 1 | attached | V076 |
| `tender` | A procurement tender and its stage | id |  | 13 | (reference) | 1 | attached | V046 |
| `voucher` | A payment voucher and its approval stage | id |  | 14 | (reference) | 1 | attached | V044 |
| `voucher_act` | one row per act on a voucher; this is what BR-006 reads to refuse a second act by the same person | id | voucher | 9 |  | 1 | attached | V044 |
| `voucher_query` | A query raised against a voucher; it blocks advance and payment until answered | id | voucher | 9 |  | 1 | attached | V044 |

### Schema `extexam` — External examiners

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `appointment` | ── the appointment: a session, a unit, a period ───────────────────────────── | id | examiner, ref.department, ref.faculty, ref.programme | 14 |  | 1 | attached | V254 |
| `assessment` | ── the assessment: one per assignment, drafted, submitted, locked, reopened ── | id | assignment | 22 | (assignment_id) | 1 | attached | V254 |
| `assessment_score` | A score per criterion of an external examiner's assessment | assessment_id, criterion_id | assessment, criterion | 4 |  | 1 | attached | V254 |
| `assignment` | A project may go to more than one examiner; each assignment, and its assessment, stands on its own. A reassignment ends this row and names the one that replaced it. | id | appointment, assignment, examiner, project, rubric | 16 |  | 1 | attached | V254 |
| `criterion` | A line of the assessment form: its section, its maximum. A criterion is deactivated rather than deleted, so an assessment scored on it still reads. | id | rubric | 8 |  | 1 | attached | V254 |
| `event` | ── the module's own history, written once ─────────────────────────────────── | id | assignment, examiner, project | 12 |  | 2 | attached | V254 |
| `examiner` | An external examiner: their person row carries the name and the login; this row carries what the appointment letter needs. Deactivated, never deleted. | id | admissions.pg_examiner, iam.person | 21 | (email); (person_id) | 1 | attached | V254 |
| `examiner_file` | the examiner's CV or academic profile, kept apart from its record | id | examiner | 8 |  | 1 | attached | V254 |
| `examiner_file_blob` | The bytes of an examiner's CV or photograph (audit-exempt blob) | file_id | examiner_file | 2 |  | 0 | exempt | V254 |
| `invitation` | ── the invitation: a token kept only as a hash, good for a fortnight, spent once ── | id | examiner | 7 |  | 0 | exempt | V254 |
| `project` | One final-year project per student per session: the undergraduate project as the department registers it here, or the postgraduate research record (V209) referenced. What the examiner reads about the work. | id | admissions.pg_research, catalogue.course, iam.person, people.student | 16 | (student_id, session) | 1 | attached | V254 |
| `project_document` | the documents released for external examination — and only those | id | project | 9 |  | 1 | attached | V254 |
| `project_document_blob` | The bytes of a project document (audit-exempt blob) | document_id | project_document | 2 |  | 0 | exempt | V254 |
| `rubric` | ── the assessment form the University configures ──────────────────────────── | id |  | 8 | (code) | 1 | attached | V254 |

### Schema `finance` — Fee schedules, charges, payment references, positions

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `bank_credit` | A bank credit posted by the Bursary against a portal reference (proposed by one officer, approved by another) | id |  | 18 |  | 1 | attached | V037 |
| `fee_schedule` | The session's charges as the Bursar states them: an item applies to a student when every filter it carries — level, entry mode, faculty, programme — matches, or is blank. A student's charge is computed, never typed. | id | ref.faculty, ref.fee_group, ref.programme | 14 |  | 1 | attached | V026 |
| `fee_setting` | the University's own State: an indigene is of this State (a setting the Bursary can change) | id |  | 3 |  | 1 | attached | V083 |
| `funding_source` | ── 1 · the sources, as a setting ─────────────────────────────────────────── | code |  | 9 |  | 1 | attached | V079 |
| `gateway_attempt` | A checkout attempt at a payment gateway, with the number of verifications made | id |  | 8 |  | 1 | attached | V037 |
| `gateway_credential` | Gateway secrets (audit-exempt; the act of setting them is on gateway_credential_event) | gateway |  | 7 |  | 0 | exempt | V039 |
| `gateway_credential_event` | SET / ROTATED / CLEARED events of a gateway credential | id |  | 7 |  | 1 | attached | V039 |
| `gateway_event` | Every gateway webhook or verification outcome, logged whether or not it confirmed anything | id |  | 15 |  | 1 | attached | V037 |
| `gl_account` | Chart of accounts: assets, liabilities, fund, income and expenditure. | code | gl_account | 8 |  | 1 | attached | V145 |
| `gl_journal` | A general-ledger journal, POSTED or REVERSED by a later journal | id | gl_journal | 11 | (journal_no) | 1 | attached | V145 |
| `gl_posting` | ── the postings (the debit/credit lines) ────────────────────────────────── | id | gl_account, gl_journal | 9 |  | 2 | attached | V145 |
| `nelfund_batch` | A NELFUND disbursement file as loaded | id |  | 8 | (ref) | 1 | attached | V033 |
| `nelfund_row` | A row of a NELFUND batch: matched to a student, unmatched, or reversed | id | nelfund_batch, people.student | 10 |  | 1 | attached | V033 |
| `nelfund_status` | the Fund's decision on each applicant, as the Bursary receives the list | id | people.student | 9 |  | 1 | attached | V033 |
| `paydirect_biller` | ── 1 · the billers (routing + what the student is shown; not a secret) ────── | scope |  | 6 |  | 1 | attached | V080 |
| `paydirect_collection` | ── 2 · the collections report, imported and matched by PRN ────────────────── | id |  | 12 |  | 1 | attached | V080 |
| `payment_reconciliation` | Append-only reconciliation attestation per confirmed reference (MATCHED / DISCREPANCY) | id |  | 7 |  | 1 | attached | V068 |
| `payment_reference` | A student's payment reference: purpose, amount, 24-hour expiry, confirmation, channel and receipt number | id | people.student | 13 | (receipt_no); (reference) | 1 | attached | V026 |
| `refund` | A refund proposal, its approval by a second officer and its payment | id | people.student | 18 | (reference) | 1 | attached | V043 |
| `wallet_entry` | A signed wallet ledger entry (CREDIT and TOPUP add; APPLIED, REVERSED and REFUND subtract) | id | funding_source, people.student | 9 |  | 2 | attached | V033 |
| `wallet_withdrawal` | ── 3 · withdrawing the balance to a personal bank account ─────────────────── | id | wallet_entry, people.student | 17 |  | 1 | attached | V079 |

### Schema `governance` — Governance instruments

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `dr_drill` | A disaster-recovery drill on record with its RPO/RTO and outcome | id |  | 7 |  | 1 | attached | V075 |
| `dsr` | A data-subject rights request under the NDPA, with its statutory due date | id |  | 8 | (reference) | 1 | attached | V075 |
| `processing_activity` | The NDPA record of processing activities and DPIA state | id |  | 7 |  | 1 | attached | V075 |

### Schema `health` — Health centre

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `appointment` | A clinic appointment booked by a student | id | people.student | 7 |  | 1 | attached | V032 |
| `note` | Clinical notes of a visit (audit-exempt) | id | visit | 5 |  | 0 | exempt | V032 |
| `profile` | A student's health profile, consent and fitness | student_id | people.student | 9 |  | 1 | attached | V032 |
| `record_access` | Who opened a health record and when (audit-exempt) | id |  | 6 |  | 0 | exempt | V032 |
| `visit` | A clinic visit from waiting to concluded | id | appointment, iam.person, people.student | 12 |  | 1 | attached | V032 |

### Schema `helpdesk` — ICT help desk tickets

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `category` | ── the categories, each with the fields it asks for ───────────────────────── | id |  | 10 | (code) | 1 | attached | V251 |
| `setting` | Desk settings (auto-close days) | row_no |  | 3 |  | 1 | attached | V251 |
| `sla` | ── the SLA by priority, and the desk''s settings ───────────────────────────── | priority |  | 3 |  | 1 | attached | V251 |
| `ticket` | One report to the ICT desk. The number is what the requester quotes and the public page looks up; the id is the key. The requester's contact and unit are copied in at submission, so the ticket reads as it was raised. | id | category, iam.person | 38 | (number) | 1 | attached | V251 |
| `ticket_attachment` | ── the evidence: PDF, JPEG or PNG, at most 5 MB, at most ten a ticket ────── | id | ticket, ticket_comment | 11 |  | 1 | attached | V251 |
| `ticket_attachment_blob` | The bytes of a ticket attachment (audit-exempt blob) | attachment_id | ticket_attachment | 2 |  | 0 | exempt | V251 |
| `ticket_comment` | ── what was said: the requester''s updates, the agents'' updates and their internal notes ── | id | ticket | 8 |  | 1 | attached | V251 |
| `ticket_event` | The ticket's timeline. Written once: an update or delete is refused unless the session is in maintenance (db/check.sql's cleanup), which the application never sets. | id | ticket | 11 |  | 2 | attached | V251 |

### Schema `hostel` — Hostel inventory, applications, allocations, stays

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `allocation` | A bed allocation from hold to check-out: reference ALC-YYYY-NNNNN, the payment reference, and every date of the stay | id | allocation, application, bed, room, people.student, policy.academic_session | 33 |  | 1 | attached | V030 |
| `application` | ── applications, and the allocations drawn against them ──────────────── | id | hall, room_type, people.student, policy.academic_session | 21 |  | 1 | attached | V030 |
| `asset` | An inventory asset of a hall, block or room with its condition | id | block, hall, room | 13 | (tag) | 1 | attached | V261 |
| `bed` | A bed of a room; occupancy is derived from live allocations | id | room | 6 | (room_id, number) | 1 | attached | V261 |
| `block` | A block of a hall | id | hall | 8 | (hall_code, code) | 1 | attached | V261 |
| `clearance` | The check-out clearance of an allocation | id | allocation | 9 | (allocation_id); (reference) | 1 | attached | V261 |
| `clearance_item` | An item of a check-out clearance against a requirement | id | clearance, clearance_requirement | 7 | (clearance_id, requirement) | 1 | attached | V261 |
| `clearance_requirement` | The nine seeded check-out requirements | code |  | 4 |  | 1 | attached | V261 |
| `damage_charge` | A charge for damage found at inspection, payable by reference | id | allocation, asset, inspection | 15 |  | 1 | attached | V261 |
| `event` | The write-once hostel trail | id | allocation, application, bed, room, people.student | 14 |  | 2 | attached | V261 |
| `facility` | A kind of room facility | code |  | 3 |  | 1 | attached | V261 |
| `hall` | ── the inventory: a record, not a spreadsheet ────────────────────────── | code | hall_kind | 10 |  | 1 | attached | V030 |
| `hall_kind` | A kind of hall | code |  | 3 |  | 1 | attached | V261 |
| `inspection` | A check-in or check-out inspection of an allocation | id | allocation | 11 |  | 1 | attached | V261 |
| `maintenance_request` | A maintenance request on a room, bed or asset | id | asset, bed, room, people.student | 13 |  | 1 | attached | V030 |
| `room` | A room of a hall and block with its type, bed count and state | id | block, hall, room_type | 13 | (hall_code, block, room_no) | 3 | attached | V030 |
| `room_facility` | A facility present in a room | room_id, facility_code | facility, room | 3 |  | 1 | attached | V261 |
| `room_type` | A room type | code |  | 4 |  | 1 | attached | V261 |
| `session_setting` | ── the session: the fee, the hold window, the seed ───────────────────── | session | policy.academic_session | 24 |  | 1 | attached | V030 |
| `transfer_request` | A student's request to move hall or room | id | allocation, hall, room_type, people.student | 12 |  | 1 | attached | V261 |

### Schema `hrm` — Human resources

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `applicant` | An applicant to a vacancy with the shortlist score | id | vacancy | 12 |  | 1 | attached | V073 |
| `appraisal` | An APER appraisal per person and cycle | id | employment, iam.person | 11 | (person_id, cycle) | 1 | attached | V074 |
| `employment` | ── the establishment: one person's employment ── | id | grade, iam.person | 14 | (staff_no) | 1 | attached | V069 |
| `grade` | ── the salary structure: grade + step → monthly components (reference data) ── | grade, step |  | 7 |  | 1 | attached | V069 |
| `leave_request` | A leave request and its decision | id | employment, leave_type, iam.person | 15 |  | 1 | attached | V071 |
| `leave_type` | A leave type and its maximum days | code |  | 5 |  | 1 | attached | V071 |
| `movement` | A staff movement (appointment, promotion, transfer, retirement …) and its approval and instrument | id | employment, grade, iam.person | 18 |  | 1 | attached | V072 |
| `pay_run` | ── a monthly pay run, maker–checker controlled ── | id |  | 15 | (period) | 1 | attached | V069 |
| `payslip` | ── one payslip per staff per run: a snapshot of the components and deductions ── | id | employment, pay_run, iam.person | 18 | (run_id, employment_id) | 1 | attached | V069 |
| `staff_photo` | A recent photograph for the staff profile; the bytes sit here, up to 2 MB, in a table exempt from audit as every blob table is. | person_id | iam.person | 5 |  | 0 | exempt | V107 |
| `staff_profile` | A member of staff's own academic profile, one row per iam.person, written only through hrm.save_my_staff_profile by the person themselves. | person_id | iam.person | 21 |  | 1 | attached | V107 |
| `staff_record` | establishment facts from the teaching-staff sheet that iam.person has no room for | person_id | iam.person, ref.faculty, ref.unit | 14 |  | 1 | attached | V137 |
| `vacancy` | A vacancy and its recruitment stage | id |  | 10 |  | 1 | attached | V073 |

### Schema `iam` — Persons, accounts, office assignments, sessions

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `credential` | ── the credential ───────────────────────────────────────────────────────── One per person. The hash is bcrypt at cost 12 (FR-IAM-011); the username is the staff number or an email, lower-cased, and is what the person types. | person_id | person | 9 | (username) | 0 | exempt | V017 |
| `credential_event` | SET / RESET / CHANGED / LOCKED / UNLOCKED events of a person's credential | id | person | 6 |  | 1 | attached | V017 |
| `office_assignment` | An office granted to a person, with its scope and instrument; ended, never deleted | id | person, ref.office | 9 |  | 2 | attached | V003 |
| `password_reset` | Staff password reset tokens (audit-exempt) | id |  | 7 |  | 0 | exempt | V058 |
| `person` | A member of staff or other person known to the University; the login hangs off iam.credential | id |  | 8 | (staff_number) | 1 | attached | V003 |
| `sign_in_event` | ── every attempt, either way ────────────────────────────────────────────── Thirty-eight attempts against fourteen accounts from one address is a security alert only if the attempts were written down. | id |  | 7 |  | 0 | exempt | V017 |
| `student_account` | ── the account ───────────────────────────────────────────────────────── | id | people.student | 8 | (student_id) | 0 | exempt | V026 |
| `student_event` | Student portal sign-in events (audit-exempt) | id |  | 6 |  | 0 | exempt | V026 |

### Schema `library` — Library

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `copy` | A physical copy of an item, keyed on its accession number | accession | item | 6 |  | 1 | attached | V031 |
| `item` | A library item (book, journal, thesis, audiovisual, reference) | id |  | 9 |  | 1 | attached | V031 |
| `loan` | a patron is a student on the register or a member of staff; the loan names one of them | id | iam.person, copy, people.student | 13 |  | 1 | attached | V031 |
| `reservation` | A student's reservation of an item | id | item, people.student | 6 |  | 1 | attached | V031 |
| `setting` |  | row_no |  | 5 |  | 1 | attached | V031 |

### Schema `lms` — Learning materials

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `access` | A student's access to a material (audit-exempt log) | id | material, people.student | 4 |  | 0 | exempt | V035 |
| `assignment` | An assignment set on an offering | id | catalogue.offering | 14 |  | 1 | attached | V035 |
| `material` | A learning material of an offering | id | catalogue.offering | 14 |  | 1 | attached | V035 |
| `material_blob` | The bytes of a material (audit-exempt blob) | material_id | material | 2 |  | 0 | exempt | V035 |
| `submission` | A student's submission to an assignment | id | assignment, people.student | 13 | (assignment_id, student_id) | 1 | attached | V035 |
| `submission_blob` | The bytes of a submission (audit-exempt blob) | submission_id | submission | 2 |  | 0 | exempt | V035 |

### Schema `people` — Students, contacts, status changes, matriculation, deferments, transfers

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `biodata` | A student's biodata values, one row per field | student_id, field | student, ref.biodata_field | 3 |  | 1 | attached | V013 |
| `biodata_change` | A field that changes only on evidence is not changed by the person it describes: the request waits on the document, and the Registry decides. A refusal is as much a decision as an approval, and is recorded with its reason. | id | student | 12 |  | 1 | attached | V013 |
| `deferment` | A student's request to defer a semester or a session, the desks' words on it, the period it holds once approved and the return the calendar names. | id | iam.person, deferment, deferment_reason, student, policy.academic_session | 35 | (reference) | 1 | attached | V259 |
| `deferment_document` | A document supporting a deferment request | id | iam.person, deferment | 10 |  | 1 | attached | V259 |
| `deferment_document_blob` | The bytes of a deferment document (audit-exempt blob) | document_id | deferment_document | 2 |  | 0 | exempt | V259 |
| `deferment_event` | The write-once deferment trail | id | deferment | 9 |  | 2 | attached | V259 |
| `deferment_reason` | The reasons a deferment may cite and whether each needs a document | code |  | 6 |  | 1 | attached | V259 |
| `deferment_setting` | The single-row deferment policy (maximum sessions, extension, reminder and overdue days) | id |  | 5 |  | 1 | attached | V259 |
| `document` | the documents the Registry holds for a student | id | student | 8 |  | 1 | attached | V013 |
| `enrolment` | one enrolment per session (I-STU-6) | id | student, policy.academic_session | 7 | (student_id, session) | 1 | attached | V013 |
| `faculty_list` | The faculty list is GENERATED from approved registrations, never typed; a Faculty Officer confirms it, and names under query keep their registration and wait for the next run. | id | policy.academic_session, ref.faculty | 6 | (session, faculty_code) | 1 | attached | V013 |
| `faculty_list_query` | A query raised on a student of a faculty's matriculation list | list_id, student_id | faculty_list, student | 5 |  | 1 | attached | V013 |
| `matric_format` | The single-row matriculation number format: University code, components, separator, padding | id |  | 10 |  | 1 | attached | V263 |
| `matric_history` | Write-once history of every matriculation number issued, with the parts it was built from | id | matric_series, matriculation_run, student | 11 | (matric_no); (series_code, sequence) | 2 | attached | V263 |
| `matric_series` | A named sequence series the faculty or programme draws from; only ever moved forward | code |  | 6 |  | 1 | attached | V263 |
| `matriculation_run` | A matriculation run (MAT/YYYY/NNN) and how many numbers it issued | id | policy.academic_session | 5 | (ref) | 1 | attached | V013 |
| `search_log` | Looking somebody up is processing their personal data whether or not anything changes, so every search for a person is written down, and the Registrar reviews the log quarterly. | id |  | 5 |  | 1 | attached | V013 |
| `status_change` | every status change carries its instrument (I-STU-3, FR-SIM-006/012) | id | student | 8 |  | 1 | attached | V013 |
| `student` | A student exists on this register from the moment an admitted candidate is brought onto it with an ADMISSION NUMBER. The matriculation number comes later, in one run over the confirmed faculty lists, and once issued it is immutable (BR-007, I-STU-1). The admis | id | admissions.candidate, iam.person, matriculation_run, policy.curriculum_track, ref.programme | 22 | (admission_no); (matric_no) | 3 | attached | V013 |
| `student_contact` | what the student may change; everything else on the record is the Registry's | student_id | student | 5 |  | 1 | attached | V026 |
| `transfer_application` | An inter-departmental transfer application and its desks | id | student, ref.programme | 33 |  | 1 | attached | V070 |

### Schema `platform` — Notices, numbering, settings, correlation

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `idempotency_key` | NFR-AVA-007. A retried request must not do the thing twice. | key |  | 4 |  | 0 | exempt | V003 |
| `mail_settings` | SMTP settings (audit-exempt; the password is a secret) | id |  | 15 |  | 0 | exempt | V057 |
| `mail_settings_event` | SET / CLEARED events of the mail settings | id |  | 4 |  | 1 | attached | V057 |
| `notice` | The outbox: every notice the portal sends, queued in the transaction that wrote the fact it announces, and marked when a provider has taken it. | id |  | 13 |  | 1 | attached | V025 |
| `notice_attachment` | A file queued with a notice: taken by the dispatcher with the notice, sent as a mail attachment. | id | notice | 7 |  | 1 | attached | V230 |
| `number_series` | BR-007: a matriculation number is permanent and never reused, and a run allocates every number or none. One sequence per (kind, scope, session). | kind, scope, session |  | 4 |  | 0 | exempt | V003 |
| `processed_event` | Delivery is at-least-once (ADR-005), so every handler is idempotent AND records what it has already processed. The registry retries; this refuses the second application. | consumer, event_id |  | 3 |  | 0 | exempt | V003 |
| `request_document` | A document attached to a service request | id | service_request | 7 |  | 1 | attached | V040 |
| `request_document_blob` | The bytes of a request document (audit-exempt blob) | document_id | request_document | 2 |  | 0 | exempt | V040 |
| `service_request` | A student's request to an office (SR-YY-NNNNN) and its answer | id | people.student, ref.office | 11 | (ref) | 1 | attached | V036 |
| `session` | ADR-017: server-side sessions. Revocation is the requirement, and a JWT cannot be un-issued. The cookie carries a 256-bit opaque id and nothing else. | id | ref.office | 8 |  | 0 | exempt | V003 |
| `sms_settings` | SMS gateway settings (audit-exempt; the API key is a secret) | id |  | 8 |  | 0 | exempt | V065 |
| `sms_settings_event` | SET / CLEARED events of the SMS settings | id |  | 4 |  | 1 | attached | V065 |

### Schema `policy` — Academic sessions, grading and progression policy

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `academic_session` | ── the session, which policy hangs off ─────────────────────────────────── `policy` is the one shared schema a real foreign key may point at (DBD §4.2): every module reads it, only the owner writes it. | id |  | 7 | (name) | 1 | attached | V004 |
| `classification_band` | the classification table, versioned like the grading scheme it sits beside | version_id, class | version | 5 |  | 1 | attached | V013 |
| `clearance_rule` | The gate per clearance purpose within a clearance scheme | version_id, purpose | clearance_scheme, ref.clearance_purpose | 3 |  | 1 | attached | V004 |
| `clearance_scheme` | A clearance scheme, one per policy version | version_id | version | 2 |  | 1 | attached | V004 |
| `curriculum_track` | ── 1 · the tracks ─────────────────────────────────────────────────────────── | code |  | 9 |  | 1 | attached | V235 |
| `grade_band` | ── grading, to show the shape carries a second policy unchanged ────────── | version_id, grade | version | 5 |  | 1 | attached | V004 |
| `level_limit` | Per level: the minimum and maximum units a semester registration may carry. The figures are the prototype''s working defaults and are amended on the Session and semester screen; the Senate minute that fixes them is recorded there. | level |  | 7 |  | 1 | attached | V013 |
| `semester` | Every date here changes what a student can do today. Moving a closing date backwards after it has passed does not un-register anybody: registrations are records, and records are not deleted. | id | academic_session | 13 | (session, number) | 1 | attached | V013 |
| `version` | ── what a policy version looks like, whatever it holds ─────────────────── One shape for every effective-dated policy in the University, so the overlap rule is written once and cannot be forgotten on the sixth one. | id | ref.office | 7 |  | 1 | attached | V004 |

### Schema `records` — Graduands and records

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `graduand` | A graduand: CGPA, award, unmet items, Senate state and minute | id | people.student, policy.academic_session | 8 | (student_id, session) | 2 | attached | V013 |

### Schema `ref` — Reference data: faculties, departments, programmes, offices

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `biodata_field` | ── biodata: three kinds of field, and the difference matters ───────────── Most of the record is the student's own and changes freely; a few fields are read from JAMB and corrected with JAMB; a few more change only on evidence the Registry has seen. The field  | field |  | 7 |  | 0 | exempt | V013 |
| `clearance_purpose` | The purposes a clearance is asked for | code |  | 3 |  | 1 | attached | V004 |
| `college` | The College of Health Sciences sits above its faculties with officers of its own (REC-MOAUMPP-001 P4), and runs a separate academic system by decision of 6 September 2026 (CHS-MOAUMPP-001). What the portal needs is the fact of the tier, not the College's acade | code |  | 4 |  | 1 | attached | V013 |
| `department` | The departments the programme table already names by code. Named here from the programmes under each; the register (ICT/MOAUMPP/2026/01, Appendix A) is the authority when it disagrees. A code, once issued, is never reused — a department is ended, not deleted. | code | faculty | 4 |  | 1 | attached | V013 |
| `faculty` | A faculty, with its matriculation segment and series | code | people.matric_series, college | 5 |  | 1 | attached | V006 |
| `fee_group` | A fee group and the programme category it applies to | code |  | 4 |  | 1 | attached | V050 |
| `fee_item` | the payment categories, as data (seeded before the spine is attached, like ref.programme) | code |  | 3 |  | 1 | attached | V055 |
| `jamb_alias` | What JAMB calls each course. Deliberately NOT a foreign key to ref.programme: JAMB sends codes the University does not run — C99256, "MA RELIGION AND PEACE STUDIES", is a postgraduate code sitting in the undergraduate alias list — and the alias has to be able to name a code in order for the intake to explain why it was refused. | code |  | 2 |  | 1 | attached | V006 |
| `jamb_alias_name` | Every further name JAMB has used for a programme, beside the primary one in ref.jamb_alias. One name means one programme — the key is the name — but one programme may carry many names, because JAMB does. | jamb_key |  | 4 |  | 1 | attached | V018 |
| `office` | The twenty-five offices that sign in (ROL-MOAUMPP-001 v0.7 §1.1). An office is added to a person, never substituted: a Head of Department is still a lecturer, and keeps the lecturer grant alongside. | code |  | 3 |  | 1 | attached | V001 |
| `programme` | A programme with its category, minimum score, archive flag and matriculation code and series | code | people.matric_series, department, faculty | 13 |  | 1 | attached | V006 |
| `unit` | The University's non-academic units: offices, directorates, divisions, units, centres, schools, and the College's own offices and clinical departments. A unit is ended, never deleted. | code | college, unit | 6 |  | 1 | attached | V253 |
| `unit_alias` | A spelling the nominal roll uses for a unit, keyed on its letters and digits alone, and where it belongs. | alias_key | department, faculty, unit | 5 |  | 1 | attached | V253 |

### Schema `registration` — Course registration

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `attendance` | Attendance per offering, date and student | id | catalogue.offering, people.student | 7 | (offering_id, held_on, student_id) | 1 | attached | V027 |
| `course_registration` | one registration per student per semester; the class list, the attendance register, the examination roll and the broadsheet are all drawn from its APPROVED entries and nothing else. | id | people.student, policy.academic_session | 10 | (student_id, session, semester) | 3 | attached | V013 |
| `entry` | A course entry of a registration against an offering | registration_id, offering_id | catalogue.offering, course_registration | 5 |  | 2 | attached | V013 |

### Schema `reports` — Saved reports

| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |
|---|---|---|---|---|---|---|---|---|
| `catalogue` | ── 1 · the catalogue ──────────────────────────────────────────────────────── | slug |  | 11 |  | 1 | attached | V229 |
| `snapshot` | ── 2 · the snapshot ───────────────────────────────────────────────────────── | id | iam.person, catalogue | 20 | (verification_code) | 1 | attached | V229 |

## 5.3 Status and kind columns (from CHECK constraints)

Every column whose CHECK constraint enumerates its values, compiled from `constraints.psv` (the generator's own section was empty). The meaning of the important ones is in Part 3.

| Table | Column | Constraint | Values |
|---|---|---|---|
| `ref.office` | `scope_kind` | `ck_office_scope` | institution · college · faculty · department · programme · course · unit · platform · level |
| `iam.office_assignment` | `scope_kind` | `ck_grant_scope` | institution · college · faculty · department · programme · course · unit · platform · level |
| `policy.academic_session` | `state` | `ck_session_state` | PLANNED · CURRENT · CLOSED |
| `policy.clearance_rule` | `releases_at` | `ck_rule_releases` | INSTALMENT_1 · INSTALMENT_2 · PAID_IN_FULL · NEVER_GATED |
| `credentials.signing_key` | `algorithm` | `ck_key_alg` | Ed25519 · ECDSA-P256 |
| `credentials.issued` | `kind` | `ck_issued_kind` | DEGREE_CERTIFICATE · TRANSCRIPT · STATEMENT_OF_RESULT · MATRICULATION · SESSIONAL_TRANSCRIPT · MINI_TRANSCRIPT · ACADEMIC_STATEMENT |
| `credentials.revocation` | `revoked_office` | `ck_revoke_office` | registrar · vc |
| `ref.programme` | `category` | `ck_prog_cat` | UNDER GRADUATE · POST GRADUATE |
| `admissions.caps_batch` | `list_kind` | `ck_batch_kind` | UTME · DIRECT_ENTRY |
| `admissions.caps_batch` | `uploaded_office` | `ck_batch_office` | academic · registrar |
| `admissions.caps_batch` | `source` | `ck_batch_source` | CAPS_DOWNLOAD · CAPS_API |
| `admissions.caps_row` | `entry_mode` | `ck_row_entry` | UTME · DIRECT_ENTRY · TRANSFER |
| `admissions.candidate` | `entry_mode` | `ck_candidate_level` | DIRECT_ENTRY · TRANSFER |
| `admissions.candidate` | `offer_state` | `ck_candidate_state` | PROPOSED · ADMITTED · ACCEPTED · DECLINED · LAPSED · WITHDRAWN |
| `admissions.attachment` | `kind` | `ck_att_kind` | PASSPORT · DATE_OF_BIRTH · OLEVEL |
| `admissions.attachment` | `read_as` | `ck_att_read` | EXACT · EMBEDDED · COLUMN · UNREADABLE |
| `admissions.candidate_photo` | `purpose` | `ck_photo_purpose` | SCREENING · CARD · CERTIFICATE |
| `admissions.session_policy` | `state` | `ck_policy_state` | DRAFT · IN_FORCE · SUPERSEDED |
| `admissions.selection_criterion` | `criterion` | `ck_crit_name` | NATIONAL_MERIT · STATE_MERIT · ELG · LOCALITY |
| `admissions.rule_subject_group` | `scope` | `ck_grp_scope` | UTME · OLEVEL · DE |
| `policy.semester` | `state` | `ck_semester_state` | NOT_YET_OPEN · OPEN · CLOSED |
| `people.student` | `entry_mode` | `ck_student_entry` | UTME · DIRECT_ENTRY · TRANSFER · POSTGRADUATE · JUPEB · SANDWICH |
| `people.student` | `sex` | `ck_student_sex` | F · M |
| `people.student` | `status` | `ck_student_status` | ADMITTED · ACTIVE · PROBATION · DEFERRED · SUSPENDED · RUSTICATED · WITHDRAWN · EXPELLED · TRANSFERRED_OUT · GRADUATED · DECEASED · DORMANT · VOLUNTARY_WITHDRAWAL |
| `ref.biodata_field` | `section` | `ck_biodata_section` | personal · contact · origin · family · kin · health · bank |
| `ref.biodata_field` | `tier` | `ck_biodata_tier` | open · locked · approval |
| `people.biodata_change` | `state` | `ck_bio_change_decided` | PENDING · EVIDENCE_ASKED |
| `people.document` | `status` | `ck_document_status` | NOT_SUPPLIED · RECEIVED · ACCEPTED · VERIFIED · REFUSED · EXPIRED |
| `catalogue.course` | `curriculum` | `ck_course_curriculum` | CCMAS · BMAS |
| `catalogue.course` | `kind` | `ck_course_kind` | Core · Required · Elective · GST |
| `catalogue.course` | `state` | `ck_course_state` | BOARD · SENATE · LIVE · ENDED |
| `catalogue.course_offer` | `basis` | `ck_offer_basis` | Core · Elective · Borrowed · GST |
| `registration.course_registration` | `status` | `ck_reg_status` | DRAFT · SUBMITTED · RETURNED · APPROVED · LOCKED |
| `registration.entry` | `status` | `ck_entry_status` | REGISTERED · DROPPED · APPROVED · WITHDRAWN |
| `registration.entry` | `entry_type` | `ck_entry_type` | CURRENT · CARRYOVER · REPEAT · ELECTIVE · GST · BORROWED |
| `assessment.exam_session` | `kind` | `ck_exam_kind` | MAIN · RESIT · SPECIAL |
| `assessment.exam_session` | `state` | `ck_exam_state` | DRAFT · OPEN · CLOSED |
| `assessment.score_sheet` | `stage` | `ck_sheet_stage` | ENTRY · VERIFICATION · DEPT_BOARD · FACULTY_SCRUTINY · FACULTY_COMPILATION · FACULTY_BOARD · RECORDS · SENATE · PUBLISHED |
| `assessment.score` | `outcome` | `ck_score_outcome` | GRADED · ABSENT · WITHHELD · INCOMPLETE · MALPRACTICE · EXEMPTED |
| `assessment.decision` | `kind` | `ck_decision_kind` | SUBMIT · ADVANCE · RETURN |
| `clearance.item` | `state` | `ck_clr_state` | HELD · CLEARED |
| `people.faculty_list` | `state` | `ck_flist_state` | DRAFT · CONFIRMED |
| `credentials.transcript_request` | `delivery` | `ck_tr_delivery` | DIGITAL · PHYSICAL · BOTH |
| `credentials.transcript_request` | `destination` | `ck_tr_dest` | SELF · INSTITUTION · EMPLOYER · EMBASSY · PROFESSIONAL_BODY · OTHER |
| `credentials.transcript_request` | `mode` | `ck_tr_mode` | DIGITAL · SEALED |
| `credentials.transcript_request` | `stage` | `ck_tr_stage` | AWAITING_PAYMENT · HELD_AT_CLEARANCE · READY · PROCESSING · GENERATED · CORRECTION · VERIFIED · RELEASED · DELIVERED · COMPLETED · REJECTED · CANCELLED |
| `credentials.certificate` | `status` | `ck_cert_status` | PRINTED · COLLECTED · HELD · REISSUED · REVOKED |
| `records.graduand` | `senate_state` | `ck_grad_state` | AWAITING · APPROVED · REFERRED |
| `iam.credential_event` | `kind` | `ck_credential_event_kind` | SET · RESET · CHANGED · LOCKED · UNLOCKED |
| `iam.sign_in_event` | `outcome` | `ck_sign_in_outcome` | SIGNED_IN · BAD_PASSWORD · UNKNOWN · LOCKED · MUST_CHANGE · SIGNED_OUT · ENDED |
| `admissions.olevel_grade_point` | `grade` | `ck_olgp_grade` | A1 · B2 · B3 · C4 · C5 · C6 · D7 · E8 · F9 |
| `admissions.olevel_sitting` | `exam_body` | `ck_ols_body` | WAEC · NECO · NABTEB · OTHER |
| `admissions.screening_batch` | `state` | `ck_batch_state` | DRAFT · PUBLISHED · POSTPONED · CANCELLED |
| `admissions.application` | `decision_basis` | `ck_app_basis` | NM · SM · ELG · LOCALITY · PLWD · OTHER |
| `admissions.application` | `decision` | `ck_app_decision` | OFFERED · WAITING · NOT_OFFERED |
| `admissions.fee_reference` | `kind` | `ck_fref_kind` | APPLICATION · ACCEPTANCE |
| `admissions.application_document` | `kind` | `ck_doc_kind` | OLEVEL_STATEMENT · BIRTH_CERT · LGA_ID · JAMB_SLIP · PASSPORT |
| `admissions.application_document` | `status` | `ck_doc_status` | PENDING · ACCEPTED · REJECTED |
| `admissions.application_document` | `content_type` | `ck_doc_type` | application/pdf · image/jpeg · image/png |
| `admissions.clearance_document` | `item` | `ck_cl_item` | OLEVEL_ORIGINAL · BIRTH_CERT · LGA_ID · JAMB_LETTER · MEDICAL · PHOTOGRAPHS |
| `admissions.clearance_document` | `state` | `ck_cl_state` | NOT_PRESENTED · VERIFIED · QUERY |
| `platform.notice` | `channel` | `ck_notice_channel` | EMAIL · SMS |
| `platform.notice` | `state` | `ck_notice_state` | QUEUED · SENT · FAILED |
| `finance.fee_schedule` | `indigene` | `ck_fee_indigene` | INDIGENE · NON_INDIGENE |
| `assessment.result_query` | `part` | `ck_query_part` | EXAM · CA · ABSENT |
| `assessment.result_query` | `state` | `ck_query_state` | RAISED · UPHELD · CORRECTED · CLOSED |
| `catalogue.class_slot` | `kind` | `ck_slot_kind` | LECTURE · PRACTICAL · TUTORIAL |
| `credentials.identity_card` | `state` | `ck_card_state` | ISSUED · LOST · REPLACED · RETURNED |
| `hostel.hall` | `sex` | `ck_hall_sex` | F · M |
| `hostel.hall` | `state` | `ck_hall_state` | ACTIVE · CLOSED |
| `hostel.room` | `sex` | `ck_room_sex` | F · M |
| `hostel.room` | `state` | `ck_room_state` | AVAILABLE · MAINTENANCE · CLOSED · RESERVED |
| `hostel.session_setting` | `allocation_method` | `ck_hs_method` | BALLOT · FIRST_COME · LEVEL · FACULTY · PROGRAMME · SPECIAL_NEEDS · MANUAL |
| `hostel.session_setting` | `state` | `ck_hs_state` | DRAFT · OPEN · CLOSED · ALLOCATED |
| `hostel.application` | `category` | `ck_ha_category` | NONE · DISABILITY · MEDICAL · FRESHER · FINALIST · SPORTS · OTHER |
| `hostel.application` | `review` | `ck_ha_review` | APPROVED · REJECTED · WAITLISTED · CORRECTION |
| `hostel.application` | `state` | `ck_ha_state` | APPLIED · ALLOCATED · CONFIRMED · LAPSED · UNSUCCESSFUL · WITHDRAWN · REJECTED |
| `hostel.allocation` | `basis` | `ck_hal_basis` | PRIORITY · BALLOT · RESERVE |
| `hostel.allocation` | `state` | `ck_hal_state` | HELD · CONFIRMED · ACCEPTED · CHECKED_IN · CHECKED_OUT · DECLINED · LAPSED · CANCELLED · TRANSFERRED |
| `hostel.maintenance_request` | `category` | `ck_hm_category` | BED · FURNITURE · WATER · ELECTRICITY · PLUMBING · INTERNET · CLEANING · SECURITY · OTHER |
| `hostel.maintenance_request` | `priority` | `ck_hm_priority` | LOW · NORMAL · HIGH · URGENT |
| `hostel.maintenance_request` | `state` | `ck_hm_state` | RAISED · ASSIGNED · FIXED · CLOSED |
| `library.item` | `kind` | `ck_li_kind` | BOOK · JOURNAL · THESIS · AUDIOVISUAL · REFERENCE |
| `library.copy` | `state` | `ck_lc_state` | AVAILABLE · ON_LOAN · RESERVED · LOST · WITHDRAWN |
| `library.reservation` | `state` | `ck_lr_state` | WAITING · READY · FULFILLED · CANCELLED · EXPIRED |
| `health.profile` | `blood_group` | `ck_hp_blood` | O+ · O- · A+ · A- · B+ · B- · AB+ · AB- |
| `health.profile` | `fitness` | `ck_hp_fit` | PENDING · FIT · UNFIT · FIT_WITH_CONDITIONS |
| `health.profile` | `genotype` | `ck_hp_geno` | AA · AS · SS · AC · SC |
| `health.appointment` | `state` | `ck_ha_state` | BOOKED · SEEN · CANCELLED · MISSED |
| `health.visit` | `state` | `ck_hv_state` | WAITING · IN_CONSULTATION · DONE · LEFT |
| `health.visit` | `triage` | `ck_hv_triage` | URGENT · STANDARD · ROUTINE |
| `finance.wallet_entry` | `kind` | `ck_we_kind` | CREDIT · TOPUP · APPLIED · REVERSED · REFUND |
| `finance.nelfund_row` | `state` | `ck_nr_state` | MATCHED · UNMATCHED · REVERSED |
| `finance.nelfund_status` | `state` | `ck_ns_state` | APPROVED · NOT_APPROVED · PENDING |
| `lms.material` | `kind` | `ck_lm_kind` | NOTES · SLIDES · READING · VIDEO · AUDIO · OTHER |
| `lms.assignment` | `kind` | `ck_las_kind` | INDIVIDUAL · PAIRS · GROUP |
| `platform.service_request` | `state` | `ck_sr_state` | OPEN · WITH_OFFICE · RESOLVED · CLOSED |
| `finance.gateway_event` | `outcome` | `ck_ge_outcome` | SETTLED · ALREADY_SETTLED · UNKNOWN_REFERENCE · SHORT_PAID · NOT_SUCCESSFUL · IGNORED · BAD_SIGNATURE · GATEWAY_ERROR |
| `finance.gateway_event` | `source` | `ck_ge_source` | WEBHOOK · VERIFY · SWEEP · TEST |
| `finance.bank_credit` | `state` | `ck_bc_state` | UNMATCHED · PROPOSED · POSTED · REVERSED |
| `finance.gateway_credential` | `gateway` | `ck_gc_gateway` | paystack · flutterwave · quickteller · paydirect |
| `finance.gateway_credential` | `mode` | `ck_gc_mode` | TEST · LIVE |
| `finance.gateway_credential_event` | `kind` | `ck_gce_kind` | SET · ROTATED · CLEARED |
| `platform.request_document` | `content_type` | `ck_rd_type` | application/pdf · image/jpeg · image/png |
| `finance.refund` | `state` | `ck_rf_state` | PROPOSED · APPROVED · REJECTED · PAID |
| `expenditure.voucher` | `stage` | `ck_pv_stage` | WITH_DIRECTOR · WITH_DEPUTY · WITH_AUDITOR · CLEARED · PAID · REJECTED |
| `expenditure.tender` | `method` | `ck_tender_method` | QUOTATION · RESTRICTED · OPEN |
| `expenditure.tender` | `stage` | `ck_tender_stage` | ADVERTISED · EVALUATED · AWARDED · CANCELLED |
| `apimgmt.consumer` | `status` | `ck_consumer_status` | ACTIVE · DEPRECATED |
| `ref.fee_group` | `applies_category` | `ck_fee_group_cat` | UNDER GRADUATE · POST GRADUATE |
| `platform.mail_settings` | `imap_encryption` | `ck_mail_imap_enc` | SSL · STARTTLS · NONE |
| `platform.mail_settings` | `pop_encryption` | `ck_mail_pop_enc` | SSL · STARTTLS · NONE |
| `platform.mail_settings` | `smtp_encryption` | `ck_mail_smtp_enc` | STARTTLS · SSL · NONE |
| `platform.mail_settings_event` | `kind` | `ck_mse_kind` | SET · CLEARED |
| `iam.password_reset` | `subject_kind` | `ck_pwreset_kind` | STAFF · STUDENT · APPLICANT · PGAPPLICANT |
| `platform.sms_settings_event` | `kind` | `ck_sse_kind` | SET · CLEARED |
| `finance.payment_reconciliation` | `result` | `ck_precon_result` | MATCHED · DISCREPANCY |
| `hrm.grade` | `category` | `ck_grade_category` | ACADEMIC · NON_ACADEMIC |
| `hrm.employment` | `category` | `ck_emp_category` | ACADEMIC · NON_ACADEMIC |
| `hrm.employment` | `status` | `ck_emp_status` | ACTIVE · SUSPENDED · ENDED |
| `hrm.pay_run` | `state` | `ck_run_state` | DRAFT · APPROVED · PAID · CANCELLED |
| `people.transfer_application` | `state` | `ck_ta_state` | APPLIED · FROM_OK · TO_OK · REG_OK · APPROVED · EFFECTED · DECLINED · WITHDRAWN · RECOMMENDED · NOT_RECOMMENDED |
| `hrm.leave_request` | `state` | `ck_lr_state` | REQUESTED · APPROVED · DECLINED · CANCELLED |
| `hrm.movement` | `kind` | `ck_mv_kind` | APPOINTMENT · CONFIRMATION · PROMOTION · UPGRADING · CONVERSION · TRANSFER · SECONDMENT · ACTING · REDESIGNATION · LEAVE_OF_ABSENCE · SABBATICAL · SUSPENSION · REINSTATEMENT · RETIREMENT · RESIGNATION · DISENGAGEMENT · DISMISSAL |
| `hrm.movement` | `state` | `ck_mv_state` | REQUESTED · APPROVED · IMPLEMENTED · DECLINED · RETURNED |
| `hrm.vacancy` | `category` | `ck_vac_category` | ACADEMIC · NON_ACADEMIC |
| `hrm.vacancy` | `state` | `ck_vac_state` | OPEN · SHORTLISTING · INTERVIEW · OFFER · CLOSED · CANCELLED |
| `hrm.applicant` | `state` | `ck_app_state` | APPLIED · SHORTLISTED · RESERVE · REJECTED · INVITED · OFFERED · DECLINED · APPOINTED |
| `hrm.appraisal` | `aper_grade` | `ck_ap_grade` | A · B · C · D · E |
| `hrm.appraisal` | `state` | `ck_ap_state` | SELF · SUPERVISOR · MODERATED |
| `governance.processing_activity` | `dpia_state` | `ck_pa_dpia` | NOT_REQUIRED · OUTSTANDING · COMPLETE |
| `governance.dsr` | `kind` | `ck_dsr_kind` | ACCESS · RECTIFICATION · ERASURE · PORTABILITY · OBJECTION |
| `governance.dsr` | `state` | `ck_dsr_state` | RECEIVED · IN_PROGRESS · COMPLETED · REFUSED |
| `governance.dr_drill` | `kind` | `ck_drill_kind` | RESTORE_VERIFY · FULL_DR · FAILOVER · BACKUP |
| `governance.dr_drill` | `outcome` | `ck_drill_outcome` | PASSED · FAILED · PARTIAL |
| `expenditure.requisition` | `state` | `ck_rq_state` | RAISED · APPROVED · PO_RAISED · CLOSED · REJECTED |
| `expenditure.asset` | `condition` | `ck_as_condition` | GOOD · FAIR · POOR · DISPOSED |
| `expenditure.research_grant` | `state` | `ck_rg_state` | PROPOSED · ACTIVE · COMPLETED · CLOSED · SUSPENDED |
| `assessment.question` | `difficulty` | `ck_q_difficulty` | EASY · MEDIUM · HARD |
| `finance.funding_source` | `nature` | `ck_fsrc_nature` | LOAN · GRANT · SELF |
| `finance.wallet_withdrawal` | `state` | `ck_ww_state` | REQUESTED · APPROVED · REJECTED · PAID |
| `finance.paydirect_biller` | `scope` | `ck_pdb_scope` | MAIN · CHS |
| `finance.paydirect_collection` | `state` | `ck_pdc_state` | MATCHED · UNMATCHED · DUPLICATE |
| `hrm.staff_photo` | `content_type` | `ck_photo_type` | image/jpeg · image/png |
| `hrm.staff_record` | `category` | `ck_staffrec_category` | ACADEMIC · NON_ACADEMIC |
| `hrm.staff_record` | `salary_scale` | `ck_staffrec_scale` | CONUASS · CONTISS · CONUNASS · CONMESS · CONHESS · CONSOLIDATED |
| `hrm.staff_record` | `sex` | `ck_staffrec_sex` | M · F |
| `finance.gl_account` | `type` | `gl_account_type_check` | ASSET · LIABILITY · EQUITY · INCOME · EXPENSE |
| `finance.gl_journal` | `source` | `gl_journal_source_check` | MANUAL · AUTO |
| `finance.gl_journal` | `status` | `gl_journal_status_check` | POSTED · REVERSED |
| `admissions.de_award` | `basis` | `ck_de_basis` | A_LEVEL · IJMB · JUPEB · NCE · ND · HND |
| `admissions.pg_applicant` | `sex` | `ck_pgapplicant_sex` | F · M |
| `admissions.pg_application` | `state` | `ck_pg_app_state` | DRAFT · SUBMITTED · DEPT_RECOMMENDED · DEPT_DECLINED · FAC_RECOMMENDED · FAC_DECLINED · OFFERED · NOT_OFFERED · ACCEPTED · ADMITTED |
| `admissions.pg_referee` | `verdict` | `ck_pg_ref_verdict` | RECOMMEND · RECOMMEND_WITH_RESERVATION · DO_NOT_RECOMMEND |
| `admissions.pg_document` | `kind` | `ck_pg_doc_kind` | TRANSCRIPT · DEGREE_CERTIFICATE · CV · PROPOSAL · NYSC · CREDENTIALS · PASSPORT · OTHER · HIGHER_DEGREE · UNDERGRAD_CERT · OLEVEL · BIRTH_CERTIFICATE · LGA_CERTIFICATE · NAME_CHANGE |
| `admissions.pg_fee_reference` | `kind` | `ck_pg_feeref_kind` | APPLICATION · CHECKING · ACCEPTANCE |
| `admissions.pg_research` | `viva_grade` | `ck_pg_research_grade` | A · B · C · F |
| `admissions.pg_research` | `degree_kind` | `ck_pg_research_kind` | PROJECT · DISSERTATION · THESIS |
| `admissions.pg_research` | `stage` | `ck_pg_research_stage` | REGISTERED · SUPERVISED · PROPOSAL_SUBMITTED · PROPOSAL_APPROVED · SEMINAR_HELD · TITLE_REGISTERED · PANEL_CONSTITUTED · DRAFT_SUBMITTED · VIVA_HELD · CORRECTIONS · FINAL_SUBMITTED · CLEARED · AWARD_RECOMMENDED · AWARDED · WITHDRAWN |
| `admissions.pg_research` | `viva_outcome` | `ck_pg_research_viva` | PASS_CLEAN · PASS_MINOR · PASS_MAJOR · SECOND_ORAL · FAIL |
| `admissions.pg_research_supervisor` | `role` | `ck_pg_sup_role` | FIRST · SECOND · CO |
| `admissions.pg_prior_degree` | `kind` | `ck_pg_prior_kind` | NCE · ND · HND · FIRST · PGD · MASTERS · PHD · OTHER |
| `admissions.pg_course` | `kind` | `ck_pg_course_kind` | CORE · ELECTIVE · DEFICIENCY · RESEARCH |
| `admissions.pg_registration` | `mode` | `ck_pg_reg_mode` | FULL_TIME · PART_TIME |
| `admissions.pg_registration` | `state` | `ck_pg_reg_state` | DRAFT · SUBMITTED · ENDORSED |
| `admissions.pg_score` | `grade` | `ck_pg_score_grade` | A · B · C · F |
| `admissions.pg_research_panel` | `role` | `ck_pg_panel_role` | CHAIR · EXTERNAL · SUPERVISOR · CO_SUPERVISOR · INTERNAL · PGSR · COORDINATOR |
| `admissions.pg_academic_session` | `state` | `pg_academic_session_state_check` | PLANNED · CURRENT · CLOSED |
| `admissions.pg_semester` | `state` | `pg_semester_state_check` | NOT_YET_OPEN · OPEN · CLOSED |
| `reports.catalogue` | `frequency` | `ck_cat_due` | PER_SEMESTER · PER_SESSION |
| `policy.curriculum_track` | `framework` | `ck_track_framework` | CCMAS · BMAS |
| `assessment.held_script` | `outcome` | `ck_held_outcome` | GRADED · ABSENT · WITHHELD · INCOMPLETE · MALPRACTICE · EXEMPTED |
| `assessment.held_script` | `state` | `ck_held_state` | HELD · RELEASED · LAPSED · WITHDRAWN |
| `college.level` | `phase` | `ck_college_level_phase` | PREMEDICAL · PRECLINICAL · CLINICAL |
| `college.posting` | `tier` | `ck_college_posting_tier` | INTRO · JUNIOR · INTERMEDIATE · SENIOR · REVISION · LECTURES |
| `college.posting_allocation` | `state` | `ck_college_alloc_state` | ALLOCATED · IN_PROGRESS · COMPLETED · INCOMPLETE |
| `college.timetable_slot` | `slot_type` | `ck_college_slot_type` | LECTURE · WARD_ROUND · CLINIC · BEDSIDE · SEMINAR · DEPT_SEMINAR · CALL_DUTY · EXAM |
| `college.procedure_requirement` | `mode` | `ck_college_proc_mode` | OBSERVE · PERFORM · EITHER |
| `college.procedure_log` | `mode` | `ck_college_proclog_mode` | OBSERVE · PERFORM |
| `college.attendance_rule` | `phase` | `ck_college_att_phase` | PREMEDICAL · PRECLINICAL · CLINICAL |
| `college.attendance_rule` | `scope` | `ck_college_att_scope` | PHASE · BLOCK |
| `college.attendance_record` | `activity_type` | `ck_college_attrec_type` | LECTURE · PRACTICAL · CLINICAL · TUTORIAL · TEST · OTHER |
| `college.professional_exam` | `code` | `ck_college_exam_code` | CPE · PE1 · PE2 · PE3 · PE4 |
| `college.assessment_item` | `item_type` | `ck_college_item_type` | COURSE_TEST · END_OF_POSTING_MCQ · END_OF_POSTING_CLINICAL · SUPERVISOR_EVAL · ORAL · PROJECT · OSCE · PERIODIC_TEST |
| `college.exam_result` | `attempt` | `ck_college_result_attempt` | FIRST · RESIT · REPEAT · SENATE_APPEAL |
| `college.progression_decision` | `outcome` | `ck_college_decision` | PROMOTE · RESIT · REPEAT · WITHDRAW_ADVISED · WITHDRAW_REQUIRED · APPEAL · GRADUATE |
| `college.progression_decision` | `state` | `ck_college_decision_state` | PROVISIONAL · CONFIRMED |
| `college.enrolment` | `kind` | `ck_college_enrolment_kind` | REGULAR · REPEAT · APPEAL |
| `college.enrolment` | `state` | `ck_college_enrolment_state` | OPEN · RESIT · CLOSED |
| `helpdesk.category` | `suggested_priority` | `ck_hd_category_priority` | LOW · NORMAL · HIGH · URGENT |
| `helpdesk.sla` | `priority` | `ck_hd_sla_priority` | LOW · NORMAL · HIGH · URGENT |
| `helpdesk.ticket` | `closed_by_kind` | `ck_hd_ticket_closed` | REQUESTER · AGENT · SYSTEM |
| `helpdesk.ticket` | `priority` | `ck_hd_ticket_priority` | LOW · NORMAL · HIGH · URGENT |
| `helpdesk.ticket` | `requester_kind` | `ck_hd_ticket_requester` | STUDENT · STAFF |
| `helpdesk.ticket` | `status` | `ck_hd_ticket_status` | SUBMITTED · OPENED · IN_PROGRESS · RESOLVED · CLOSED · REOPENED |
| `helpdesk.ticket_comment` | `author_kind` | `ck_hd_comment_kind` | REQUESTER · AGENT · SYSTEM |
| `helpdesk.ticket_attachment` | `uploaded_kind` | `ck_hd_attachment_kind` | REQUESTER · AGENT |
| `helpdesk.ticket_attachment` | `content_type` | `ck_hd_attachment_type` | application/pdf · image/jpeg · image/png |
| `helpdesk.ticket_event` | `action` | `ck_hd_event_action` | SUBMITTED · OPENED · STATUS_CHANGED · ASSIGNED · REASSIGNED · ESCALATED · PRIORITY_CHANGED · INTERNAL_NOTE · UPDATE · RESOLUTION · REOPENED · CLOSED · ATTACHMENT |
| `helpdesk.ticket_event` | `actor_kind` | `ck_hd_event_kind` | REQUESTER · AGENT · SYSTEM |
| `ref.unit` | `kind` | `ck_unit_kind` | OFFICE · DIRECTORATE · DIVISION · UNIT · CENTRE · SCHOOL · FACULTY_OFFICE · DEPARTMENT |
| `extexam.examiner` | `status` | `ck_ee_status` | INVITED · PENDING_ACTIVATION · ACTIVE · SUSPENDED · INACTIVE |
| `extexam.examiner_file` | `kind` | `ck_ee_file_kind` | CV · PHOTO |
| `extexam.examiner_file` | `content_type` | `ck_ee_file_type` | application/pdf · image/jpeg · image/png |
| `extexam.appointment` | `status` | `ck_ee_appt_status` | ACTIVE · ENDED · SUSPENDED |
| `extexam.project` | `kind` | `ck_ee_project_kind` | UNDERGRADUATE · POSTGRADUATE |
| `extexam.project_document` | `kind` | `ck_ee_doc_kind` | PROPOSAL · REPORT · SOURCE · PRESENTATION · SUPPORTING |
| `extexam.project_document` | `content_type` | `ck_ee_doc_type` | application/pdf · application/vnd.openxmlformats-officedocument.wordprocessingml.document · application/vnd.openxmlformats-officedocument.presentationml.presentation · application/zip |
| `extexam.rubric` | `kind` | `ck_ee_rubric_kind` | UNDERGRADUATE · POSTGRADUATE |
| `extexam.criterion` | `section` | `ck_ee_criterion_section` | WRITTEN · DEFENCE |
| `extexam.assignment` | `status` | `ck_ee_asg_ended` | REASSIGNED · WITHDRAWN |
| `extexam.assessment` | `final_recommendation` | `ck_ee_ass_recommendation` | PASS · PASS_WITH_CORRECTIONS · REASSESSMENT · FAIL |
| `extexam.assessment` | `state` | `ck_ee_ass_state` | DRAFT · SUBMITTED · LOCKED · REOPENED |
| `extexam.event` | `action` | `ck_ee_event_action` | EXAMINER_CREATED · EXAMINER_EDITED · EXAMINER_INVITED · INVITATION_RESENT · ACCOUNT_ACTIVATED · EXAMINER_STATUS · APPOINTED · APPOINTMENT_ENDED · PROJECT_CREATED · PROJECT_EDITED · DOCUMENT_RELEASED · DOCUMENT_WITHDRAWN · PROJECT_ASSIGNED · PROJECT_REASSIGNED · ASSIGNMENT_WITHDRAWN · DEADLINE_CHANGED · PROJECT_VIEWED · ASSESSMENT_STARTED · ASSESSMENT_SAVED · ASSESSMENT_SUBMITTED · ASSESSMENT_LOCKED · ASSESSMENT_REOPENED · ASSESSMENT_RESUBMITTED |
| `admissions.pg_research_document` | `kind` | `ck_pg_rdoc_kind` | PROPOSAL · SEMINAR_PAPER · PLAGIARISM_REPORT · DRAFT · CORRECTED · FINAL · OTHER |
| `admissions.pg_research_document` | `status` | `ck_pg_rdoc_status` | SUBMITTED · ACCEPTED · RETURNED |
| `admissions.pg_research_document` | `content_type` | `ck_pg_rdoc_type` | application/pdf · application/vnd.openxmlformats-officedocument.wordprocessingml.document |
| `people.deferment` | `kind` | `ck_def_kind` | SEMESTER · SESSION |
| `people.deferment` | `state` | `ck_def_state` | DRAFT · SUBMITTED · CORRECTION_REQUIRED · DEPT_RECOMMENDED · FAC_RECOMMENDED · APPROVED · ACTIVE · COMPLETED · REJECTED · CANCELLED |
| `people.deferment_document` | `kind` | `ck_defdoc_kind` | MEDICAL · FINANCIAL · OFFICIAL_LETTER · EMPLOYER_LETTER · OTHER |
| `people.deferment_document` | `content_type` | `ck_defdoc_type` | application/pdf · image/jpeg · image/png |
| `admissions.putme_exam` | `state` | `ck_pe_state` | DRAFT · CONFIGURING · OPEN_FOR_SCHEDULING · SCHEDULING_IN_PROGRESS · SCHEDULED · ONGOING · COMPLETED · CANCELLED |
| `admissions.putme_exam` | `strategy` | `ck_pe_strategy` | PROGRAMME · DEPARTMENT · FACULTY · ALPHABETICAL · APPLICATION_NO · BALANCED |
| `admissions.cbt_centre` | `state` | `ck_cc_state` | ACTIVE · INACTIVE |
| `admissions.cbt_room` | `state` | `ck_cr_state` | ACTIVE · INACTIVE |
| `admissions.screening_assignment` | `attendance` | `ck_sa_attendance` | NOT_CHECKED_IN · CHECKED_IN · PRESENT · ABSENT · DISQUALIFIED |
| `admissions.screening_assignment` | `exam_status` | `ck_sa_exam` | NOT_STARTED · IN_PROGRESS · COMPLETED · ABSENT · DISQUALIFIED |
| `admissions.screening_assignment` | `state` | `ck_sa_state` | ACTIVE · SUPERSEDED · CANCELLED |
| `hostel.block` | `state` | `ck_block_state` | ACTIVE · CLOSED |
| `hostel.bed` | `state` | `ck_bed_state` | AVAILABLE · MAINTENANCE · OUT_OF_SERVICE |
| `hostel.asset` | `condition` | `ck_asset_condition` | NEW · GOOD · FAIR · DAMAGED · REPAIR_REQUIRED · REPLACED · DISPOSED |
| `hostel.asset` | `state` | `ck_asset_state` | ACTIVE · RETIRED |
| `hostel.inspection` | `cleanliness` | `ck_ins_clean` | CLEAN · ACCEPTABLE · DIRTY |
| `hostel.inspection` | `condition` | `ck_ins_condition` | GOOD · FAIR · DAMAGED |
| `hostel.inspection` | `kind` | `ck_ins_kind` | CHECKIN · CHECKOUT |
| `hostel.clearance` | `state` | `ck_hcl_state` | PENDING · CLEARED · NOT_CLEARED |
| `hostel.clearance_item` | `state` | `ck_hci_state` | PENDING · CLEARED · NOT_CLEARED · WAIVED · NOT_APPLICABLE |
| `hostel.transfer_request` | `state` | `ck_tr_state` | SUBMITTED · UNDER_REVIEW · APPROVED · REJECTED · COMPLETED · CANCELLED |
| `credentials.document_policy` | `includes` | `ck_dp_includes` | CURRENT_SEMESTER · SELECTED_SEMESTER · SELECTED_SESSION · CUMULATIVE |
| `credentials.document_policy` | `kind` | `ck_dp_kind` | DEGREE_CERTIFICATE · TRANSCRIPT · SESSIONAL_TRANSCRIPT · MINI_TRANSCRIPT · ACADEMIC_STATEMENT |
| `credentials.delivery` | `kind` | `ck_dl_kind` | DIGITAL · PHYSICAL |
| `credentials.delivery` | `state` | `ck_dl_state` | NOT_SENT · READY · SENT · DELIVERED · FAILED · EXPIRED · RESENT · PROCESSING · DISPATCHED · IN_TRANSIT · RETURNED |
| `credentials.download_token` | `for_kind` | `ck_dt_for` | STUDENT · RECIPIENT |
| `people.matric_format` | `separator` | `ck_mf_sep` | / · - |

## 5.4 Column detail

**`admissions.applicant_account`**: id `uuid` NOT NULL, session `text` NOT NULL, candidate_id `uuid` NOT NULL, jamb_key `text` NOT NULL, email `text` NOT NULL, phone `text` NOT NULL, password_hash `text` NOT NULL, failed_attempts `integer` NOT NULL, locked_until `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, last_signed_in_at `timestamp with time zone`

**`admissions.applicant_event`**: id `uuid` NOT NULL, account_id `uuid`, identifier `text` NOT NULL, outcome `text` NOT NULL, ip `text`, at `timestamp with time zone` NOT NULL

**`admissions.applicant_fee`**: session `text` NOT NULL, application_fee `numeric` NOT NULL, portal_charge `numeric` NOT NULL, acceptance_fee `numeric` NOT NULL, stated_at `timestamp with time zone` NOT NULL, checking_fee `numeric` NOT NULL

**`admissions.application`**: id `uuid` NOT NULL, account_id `uuid` NOT NULL, candidate_id `uuid` NOT NULL, session `text` NOT NULL, application_no `text` NOT NULL, next_of_kin `text`, fee_confirmed_at `timestamp with time zone`, submitted_at `timestamp with time zone`, declaration_ip `text`, screening_batch_id `uuid`, seat `text`, screening_score `numeric`, score_entered_at `timestamp with time zone`, score_released_at `timestamp with time zone`, decision `text`, decision_note `text`, decided_at `timestamp with time zone`, decision_released_at `timestamp with time zone`, undertaking_at `timestamp with time zone`, acceptance_confirmed_at `timestamp with time zone`, accepted_at `timestamp with time zone`, declined_at `timestamp with time zone`, cleared_at `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, decision_basis `text`, putme_token `text` NOT NULL, schedule_review `boolean` NOT NULL

**`admissions.application_document`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, kind `text` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, bytes `bigint` NOT NULL, uploaded_at `timestamp with time zone` NOT NULL, status `text` NOT NULL, reviewed_at `timestamp with time zone`, reviewed_by `uuid`, review_note `text`, superseded_at `timestamp with time zone`

**`admissions.application_document_blob`**: document_id `uuid` NOT NULL, content `bytea` NOT NULL

**`admissions.attachment`**: id `uuid` NOT NULL, session `text` NOT NULL, kind `text` NOT NULL, source_name `text` NOT NULL, jamb_key `text`, read_as `text` NOT NULL, candidate_id `uuid`, matched_at `timestamp with time zone`, payload `jsonb` NOT NULL, bytes `bigint`, width_px `integer`, height_px `integer`, object_key `text`, arrived_at `timestamp with time zone` NOT NULL

**`admissions.candidate`**: id `uuid` NOT NULL, session `text` NOT NULL, jamb_reg_no `text` NOT NULL, admission_no `text`, surname `text` NOT NULL, other_names `text` NOT NULL, programme `text` NOT NULL, entry_mode `text` NOT NULL, entry_level `integer` NOT NULL, offer_state `text` NOT NULL, admitted_from `uuid`, jamb_key `text`, utme_aggregate `integer`

**`admissions.candidate_photo`**: id `uuid` NOT NULL, candidate_id `uuid` NOT NULL, attachment_id `uuid` NOT NULL, purpose `text` NOT NULL, in_force `tstzrange` NOT NULL

**`admissions.caps_batch`**: id `uuid` NOT NULL, session `text` NOT NULL, source `text` NOT NULL, filename `text`, file_sha256 `bytea` NOT NULL, rows_read `integer` NOT NULL, list_kind `text` NOT NULL, downloaded_on `date` NOT NULL, uploaded_at `timestamp with time zone` NOT NULL, uploaded_by `uuid` NOT NULL, uploaded_office `text` NOT NULL, committed_at `timestamp with time zone`, withdrawn_at `timestamp with time zone`, withdrawn_by `uuid`, withdrawn_reason `text`, committed_pending `integer`

**`admissions.caps_row`**: id `uuid` NOT NULL, batch_id `uuid` NOT NULL, session `text` NOT NULL, jamb_reg_no `text` NOT NULL, raw `jsonb` NOT NULL, surname `text` NOT NULL, other_names `text` NOT NULL, jamb_code `text` NOT NULL, aggregate `integer`, sex `text`, state_of_origin `text`, lga `text`, entry_mode `text` NOT NULL, jamb_key `text`, withdrawn `boolean` NOT NULL

**`admissions.caps_row_excluded`**: id `uuid` NOT NULL, batch_id `uuid` NOT NULL, session `text` NOT NULL, jamb_reg_no `text` NOT NULL, jamb_code `text` NOT NULL, surname `text` NOT NULL, other_names `text` NOT NULL, aggregate `integer`, cutoff `integer` NOT NULL, reason `text` NOT NULL, raw `jsonb` NOT NULL

**`admissions.catchment_lga`**: policy_id `uuid` NOT NULL, lga `text` NOT NULL

**`admissions.cbt_centre`**: id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, location `text`, address `text`, contact_person `text`, contact_info `text`, state `text` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`admissions.cbt_room`**: id `uuid` NOT NULL, centre_id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, capacity `integer` NOT NULL, workstations `integer` NOT NULL, state `text` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`admissions.cbt_workstation`**: id `uuid` NOT NULL, room_id `uuid` NOT NULL, number `integer` NOT NULL, label `text` NOT NULL, operational `boolean` NOT NULL

**`admissions.clearance_document`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, item `text` NOT NULL, state `text` NOT NULL, note `text`, decided_at `timestamp with time zone`, decided_by `uuid`

**`admissions.de_award`**: id `uuid` NOT NULL, session `text` NOT NULL, jamb_key `text` NOT NULL, basis `text` NOT NULL, awarded_year `integer`, institution `text`, recorded_by `uuid`, recorded_at `timestamp with time zone` NOT NULL

**`admissions.de_award_subject`**: id `uuid` NOT NULL, award_id `uuid` NOT NULL, subject `text` NOT NULL, grade `text`

**`admissions.faculty_quota`**: policy_id `uuid` NOT NULL, faculty_code `text` NOT NULL, quota `integer`, cutoff `integer`, ratio_utme `integer`, ratio_de `integer`

**`admissions.fee_reference`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, kind `text` NOT NULL, reference `text` NOT NULL, amount `numeric` NOT NULL, generated_at `timestamp with time zone` NOT NULL, expires_at `timestamp with time zone` NOT NULL, confirmed_at `timestamp with time zone`, confirmed_by `uuid`, channel `text`, note `text`, receipt_no `text`

**`admissions.jamb_admission`**: id `uuid` NOT NULL, session `text` NOT NULL, jamb_reg_no `text` NOT NULL, name `text`, sex `text`, state_name `text`, lga_name `text`, course_name `text`, aggregate `integer`, putme_score `numeric`, status `text`, category `text`, jamb_component `numeric`, putme_component `numeric`, total `numeric`, candidate_id `uuid`, matched `boolean` NOT NULL, offered `boolean` NOT NULL, why `text`, loaded_at `timestamp with time zone` NOT NULL

**`admissions.load_cutoff`**: session `text` NOT NULL, cutoff `integer` NOT NULL, stated_at `timestamp with time zone` NOT NULL

**`admissions.olevel_compulsory`**: session `text` NOT NULL, subject `text` NOT NULL, pattern `text` NOT NULL, ord `integer` NOT NULL

**`admissions.olevel_grade`**: sitting_id `uuid` NOT NULL, subject `text` NOT NULL, grade `text` NOT NULL, raw_subject `text`

**`admissions.olevel_grade_point`**: session `text` NOT NULL, grade `text` NOT NULL, points `integer` NOT NULL

**`admissions.olevel_grading`**: session `text` NOT NULL, subjects_counted `integer` NOT NULL, bonus_one_sitting `integer` NOT NULL, bonus_two_sittings `integer` NOT NULL, stated_at `timestamp with time zone` NOT NULL

**`admissions.olevel_sitting`**: id `uuid` NOT NULL, attachment_id `uuid` NOT NULL, session `text` NOT NULL, jamb_key `text` NOT NULL, exam_body `text` NOT NULL, exam_type_raw `text`, exam_year `text`, exam_number `text`, ord `integer` NOT NULL

**`admissions.password_reset`**: id `uuid` NOT NULL, account_id `uuid` NOT NULL, token_hash `text` NOT NULL, created_at `timestamp with time zone` NOT NULL, expires_at `timestamp with time zone` NOT NULL, used_at `timestamp with time zone`

**`admissions.pg_academic_session`**: name `text` NOT NULL, starts_on `date`, ends_on `date`, semesters `integer` NOT NULL, state `text` NOT NULL, note `text`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`admissions.pg_applicant`**: id `uuid` NOT NULL, session `text` NOT NULL, surname `text` NOT NULL, other_names `text` NOT NULL, sex `text`, date_of_birth `date`, state_of_origin `text`, lga `text`, email `text` NOT NULL, phone `text`, password_hash `text` NOT NULL, failed_attempts `integer` NOT NULL, locked_until `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, last_signed_in_at `timestamp with time zone`

**`admissions.pg_application`**: id `uuid` NOT NULL, applicant_id `uuid` NOT NULL, session `text` NOT NULL, application_no `text` NOT NULL, programme_code `text` NOT NULL, entry_level `integer` NOT NULL, prior_institution `text`, prior_award `text`, prior_class `text`, prior_cgpa `numeric`, prior_year `integer`, proposal_title `text`, proposal_text `text`, state `text` NOT NULL, fee_confirmed_at `timestamp with time zone`, submitted_at `timestamp with time zone`, dept_decided_at `timestamp with time zone`, dept_decided_by `uuid`, dept_note `text`, spgs_decided_at `timestamp with time zone`, spgs_decided_by `uuid`, spgs_note `text`, accepted_at `timestamp with time zone`, admitted_at `timestamp with time zone`, student_id `uuid`, created_at `timestamp with time zone` NOT NULL, checking_confirmed_at `timestamp with time zone`, acceptance_confirmed_at `timestamp with time zone`, fac_decided_at `timestamp with time zone`, fac_decided_by `uuid`, fac_note `text`

**`admissions.pg_application_event`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, kind `text` NOT NULL, note `text`, actor_id `uuid`, actor_office `text`, at `timestamp with time zone` NOT NULL

**`admissions.pg_course`**: id `uuid` NOT NULL, programme_code `text` NOT NULL, code `text` NOT NULL, title `text` NOT NULL, units `integer` NOT NULL, kind `text` NOT NULL, semester `integer` NOT NULL, active `boolean` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`admissions.pg_document`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, kind `text` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, bytes `bytea` NOT NULL, uploaded_at `timestamp with time zone` NOT NULL

**`admissions.pg_examiner`**: id `uuid` NOT NULL, name `text` NOT NULL, institution `text` NOT NULL, field `text`, tenure_from `date`, tenure_to `date`, active `boolean` NOT NULL, appointed_at `timestamp with time zone` NOT NULL

**`admissions.pg_fee`**: session `text` NOT NULL, application_fee `numeric` NOT NULL, acceptance_fee `numeric` NOT NULL, checking_fee `numeric` NOT NULL

**`admissions.pg_fee_reference`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, kind `text` NOT NULL, reference `text` NOT NULL, amount `numeric` NOT NULL, generated_at `timestamp with time zone` NOT NULL, expires_at `timestamp with time zone` NOT NULL, confirmed_at `timestamp with time zone`, channel `text`

**`admissions.pg_legacy_holding`**: session `text` NOT NULL, semester `integer` NOT NULL, matric `text` NOT NULL, course_code `text` NOT NULL, raw `jsonb` NOT NULL, loaded_at `timestamp with time zone` NOT NULL

**`admissions.pg_prior_degree`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, kind `text` NOT NULL, institution `text`, award `text`, class_of_degree `text`, cgpa `numeric`, year `integer`, field `text`

**`admissions.pg_referee`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, name `text` NOT NULL, email `text`, institution `text`, position `text`, reference_text `text`, submitted_at `timestamp with time zone`, phone `text`, token `text` NOT NULL, relationship `text`, known_duration `text`, attestation `text`, recommendation `text`, verdict `text`

**`admissions.pg_registration`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, semester `integer` NOT NULL, mode `text` NOT NULL, state `text` NOT NULL, endorsed_by `uuid`, endorsed_at `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`admissions.pg_registration_entry`**: id `uuid` NOT NULL, registration_id `uuid` NOT NULL, course_id `uuid` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`admissions.pg_research`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, degree_kind `text` NOT NULL, stage `text` NOT NULL, topic `text`, proposal_submitted_at `timestamp with time zone`, proposal_approved_at `timestamp with time zone`, seminar_held_at `timestamp with time zone`, pgsr `text`, title_registered_at `timestamp with time zone`, plagiarism_pct `numeric`, panel_constituted_at `timestamp with time zone`, draft_submitted_at `timestamp with time zone`, viva_held_at `timestamp with time zone`, viva_score `numeric`, viva_grade `text`, viva_outcome `text`, corrections_due `date`, final_submitted_at `timestamp with time zone`, cleared_at `timestamp with time zone`, award_recommended_at `timestamp with time zone`, awarded_at `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`admissions.pg_research_document`**: id `uuid` NOT NULL, research_id `uuid` NOT NULL, kind `text` NOT NULL, version `integer` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, size_bytes `integer` NOT NULL, note `text`, status `text` NOT NULL, reviewer_note `text`, reviewed_by `uuid`, reviewed_at `timestamp with time zone`, by_candidate `boolean` NOT NULL, uploaded_by `uuid`, uploaded_at `timestamp with time zone` NOT NULL

**`admissions.pg_research_document_blob`**: document_id `uuid` NOT NULL, bytes `bytea` NOT NULL

**`admissions.pg_research_event`**: id `uuid` NOT NULL, research_id `uuid` NOT NULL, stage `text` NOT NULL, note `text`, by_person `uuid`, at `timestamp with time zone` NOT NULL

**`admissions.pg_research_panel`**: id `uuid` NOT NULL, research_id `uuid` NOT NULL, name `text` NOT NULL, role `text` NOT NULL, is_external `boolean` NOT NULL, added_at `timestamp with time zone` NOT NULL

**`admissions.pg_research_supervisor`**: id `uuid` NOT NULL, research_id `uuid` NOT NULL, person_id `uuid`, name `text` NOT NULL, role `text` NOT NULL, is_external `boolean` NOT NULL, assigned_at `timestamp with time zone` NOT NULL, ended_at `timestamp with time zone`

**`admissions.pg_score`**: id `uuid` NOT NULL, entry_id `uuid` NOT NULL, ca `numeric`, exam `numeric`, total `numeric` NOT NULL, grade `text` NOT NULL, points `numeric` NOT NULL, recorded_at `timestamp with time zone` NOT NULL, recorded_by `uuid`

**`admissions.pg_semester`**: session `text` NOT NULL, number `integer` NOT NULL, registration_opens `date`, registration_closes `date`, lectures_from `date`, lectures_to `date`, exams_from `date`, exams_to `date`, results_due `date`, state `text` NOT NULL

**`admissions.programme_closed`**: policy_id `uuid` NOT NULL, programme_code `text` NOT NULL, reason `text` NOT NULL, closed_at `timestamp with time zone` NOT NULL

**`admissions.programme_olevel_allowance`**: policy_id `uuid` NOT NULL, programme_code `text` NOT NULL, subject `text` NOT NULL

**`admissions.programme_rule`**: policy_id `uuid` NOT NULL, programme_code `text` NOT NULL, cutoff `integer`, olevel_credits `integer` NOT NULL, olevel_sittings `integer` NOT NULL, olevel_text `text` NOT NULL, utme_text `text` NOT NULL, de_text `text` NOT NULL, quota `integer`

**`admissions.putme_day`**: exam_id `uuid` NOT NULL, held_on `date` NOT NULL, active `boolean` NOT NULL

**`admissions.putme_event`**: id `uuid` NOT NULL, exam_id `uuid`, batch_id `uuid`, application_id `uuid`, action `text` NOT NULL, from_value `text`, to_value `text`, note `text`, actor_id `uuid`, actor_office `text`, at `timestamp with time zone` NOT NULL

**`admissions.putme_exam`**: id `uuid` NOT NULL, session `text` NOT NULL, name `text` NOT NULL, kind `text` NOT NULL, starts_on `date`, ends_on `date`, checkin_minutes `integer` NOT NULL, duration_minutes `integer` NOT NULL, buffer_minutes `integer` NOT NULL, registration_deadline `date`, state `text` NOT NULL, strategy `text` NOT NULL, keep_programme `boolean` NOT NULL, instructions `text`, venue_instructions `text`, contact `text`, published_at `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`admissions.putme_exam_centre`**: exam_id `uuid` NOT NULL, centre_id `uuid` NOT NULL, active `boolean` NOT NULL

**`admissions.putme_slot`**: id `uuid` NOT NULL, exam_id `uuid` NOT NULL, code `text` NOT NULL, starts_at `time without time zone` NOT NULL, ends_at `time without time zone` NOT NULL, ord `integer` NOT NULL, active `boolean` NOT NULL

**`admissions.rule_subject`**: group_id `uuid` NOT NULL, subject `text` NOT NULL

**`admissions.rule_subject_group`**: id `uuid` NOT NULL, policy_id `uuid` NOT NULL, programme_code `text` NOT NULL, scope `text` NOT NULL, choose `integer` NOT NULL, min_grade `text`

**`admissions.screening_assignment`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, batch_id `uuid` NOT NULL, seat `text` NOT NULL, workstation_id `uuid`, state `text` NOT NULL, reason `text`, assigned_at `timestamp with time zone` NOT NULL, assigned_by `uuid`, ended_at `timestamp with time zone`, ended_by `uuid`, checked_in_at `timestamp with time zone`, checked_in_by `uuid`, attendance `text` NOT NULL, exam_status `text` NOT NULL, remarks `text`

**`admissions.screening_batch`**: id `uuid` NOT NULL, session `text` NOT NULL, label `text` NOT NULL, held_on `date` NOT NULL, starts_at `time without time zone` NOT NULL, ends_at `time without time zone` NOT NULL, venue `text` NOT NULL, capacity `integer` NOT NULL, created_at `timestamp with time zone` NOT NULL, exam_id `uuid`, centre_id `uuid`, room_id `uuid`, slot_id `uuid`, state `text` NOT NULL, ordinal `integer`, note `text`

**`admissions.screening_exam_programme`**: session `text` NOT NULL, programme_code `text` NOT NULL, stated_at `timestamp with time zone` NOT NULL

**`admissions.selection_criterion`**: policy_id `uuid` NOT NULL, criterion `text` NOT NULL, percent `integer` NOT NULL

**`admissions.session_policy`**: id `uuid` NOT NULL, session `text` NOT NULL, nuc_quota `integer` NOT NULL, weight_utme `integer` NOT NULL, weight_putme `integer` NOT NULL, ratio_utme `integer` NOT NULL, ratio_de `integer` NOT NULL, ratio_science `integer` NOT NULL, ratio_arts `integer` NOT NULL, elg_cap_pct `integer` NOT NULL, dept_share_pct `integer` NOT NULL, index_prelim_places `integer` NOT NULL, index_per_zone `integer` NOT NULL, mpf_only `boolean` NOT NULL, screening_required `boolean` NOT NULL, instrument `text`, in_force `tstzrange`, state `text` NOT NULL

**`admissions.suggestion_sent`**: application_id `uuid` NOT NULL, programmes `text` NOT NULL, sent_at `timestamp with time zone` NOT NULL, sent_by `uuid`

**`apimgmt.consumer`**: id `uuid` NOT NULL, name `text` NOT NULL, owner `text` NOT NULL, scopes `text` NOT NULL, quota_day `integer`, status `text` NOT NULL, created_by `uuid` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`apimgmt.key`**: id `uuid` NOT NULL, consumer_id `uuid` NOT NULL, key_hash `bytea` NOT NULL, last4 `text` NOT NULL, issued_by `uuid` NOT NULL, issued_at `timestamp with time zone` NOT NULL, expires_at `timestamp with time zone` NOT NULL, revoked_at `timestamp with time zone`

**`assessment.decision`**: id `uuid` NOT NULL, sheet_id `uuid` NOT NULL, from_stage `text` NOT NULL, to_stage `text` NOT NULL, kind `text` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, comment `text`, decided_at `timestamp with time zone` NOT NULL

**`assessment.exam_session`**: id `uuid` NOT NULL, session `text` NOT NULL, semester `integer` NOT NULL, kind `text` NOT NULL, exams_from `date` NOT NULL, exams_to `date` NOT NULL, sheets_due `date` NOT NULL, state `text` NOT NULL, opened_at `timestamp with time zone`

**`assessment.exam_timetable`**: offering_id `uuid` NOT NULL, held_on `date` NOT NULL, starts_at `time without time zone` NOT NULL, ends_at `time without time zone` NOT NULL, venue `text` NOT NULL

**`assessment.held_script`**: id `uuid` NOT NULL, sheet_id `uuid` NOT NULL, student_id `uuid` NOT NULL, ca `integer`, exam `integer`, outcome `text` NOT NULL, note `text`, entered_by `uuid` NOT NULL, entered_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, released_at `timestamp with time zone`, lapsed_at `timestamp with time zone`, withdrawn_at `timestamp with time zone`

**`assessment.legacy_result_holding`**: session `text` NOT NULL, semester `integer` NOT NULL, matric `text` NOT NULL, course_code `text` NOT NULL, raw `jsonb` NOT NULL, loaded_at `timestamp with time zone` NOT NULL

**`assessment.question`**: id `uuid` NOT NULL, course_code `text` NOT NULL, topic `text`, stem `text` NOT NULL, options `jsonb` NOT NULL, answer `integer` NOT NULL, difficulty `text` NOT NULL, marks `integer` NOT NULL, active `boolean` NOT NULL, authored_at `timestamp with time zone` NOT NULL, authored_by `uuid`

**`assessment.result_query`**: id `uuid` NOT NULL, ref `text` NOT NULL, student_id `uuid` NOT NULL, sheet_id `uuid` NOT NULL, part `text` NOT NULL, said `text` NOT NULL, routed_dept `text` NOT NULL, raised_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, answer `text`, answered_at `timestamp with time zone`, answered_by `uuid`

**`assessment.score`**: sheet_id `uuid` NOT NULL, student_id `uuid` NOT NULL, version `integer` NOT NULL, ca `integer`, exam `integer`, outcome `text` NOT NULL, reason `text`, entered_at `timestamp with time zone` NOT NULL, total `integer`, imported `boolean` NOT NULL

**`assessment.score_sheet`**: id `uuid` NOT NULL, offering_id `uuid` NOT NULL, exam_session_id `uuid`, stage `text` NOT NULL, due_on `date`, submitted_at `timestamp with time zone`, returned_times `integer` NOT NULL, senate_minute `text`, published_at `timestamp with time zone`, engine_version `text`

**`assessment.siwes_supervisor`**: offering_id `uuid` NOT NULL, student_id `uuid` NOT NULL, supervisor_id `uuid` NOT NULL, assigned_by `uuid`, assigned_at `timestamp with time zone` NOT NULL

**`audit.chain_head`**: period `date` NOT NULL, shard `smallint` NOT NULL, last_hash `bytea` NOT NULL, last_seq `bigint` NOT NULL

**`audit.entries_202609`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202610`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202611`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202612`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202701`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202702`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202703`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202704`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202705`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202706`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202707`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202708`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202709`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202710`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202711`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202712`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202801`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202802`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202803`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202804`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202805`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202806`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202807`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.entries_202808`**: id `uuid` NOT NULL, occurred_at `timestamp with time zone` NOT NULL, period `date` NOT NULL, shard `smallint` NOT NULL, seq `bigint` NOT NULL, actor_id `uuid` NOT NULL, actor_office `text` NOT NULL, action `text` NOT NULL, subject_type `text` NOT NULL, subject_id `uuid` NOT NULL, before_state `jsonb`, after_state `jsonb`, reason `text`, correlation_id `uuid`, source_ip `inet`, prev_hash `bytea`, entry_hash `bytea` NOT NULL

**`audit.exemption`**: relid `oid` NOT NULL, reason `text` NOT NULL

**`audit.subject_key`**: relid `oid` NOT NULL, cols `ARRAY` NOT NULL

**`catalogue.class_slot`**: id `uuid` NOT NULL, offering_id `uuid` NOT NULL, weekday `integer` NOT NULL, starts_at `time without time zone` NOT NULL, ends_at `time without time zone` NOT NULL, venue `text` NOT NULL, kind `text` NOT NULL, ended_at `timestamp with time zone`

**`catalogue.course`**: code `text` NOT NULL, title `text` NOT NULL, units `integer` NOT NULL, semester `integer` NOT NULL, level `integer` NOT NULL, dept_code `text` NOT NULL, kind `text` NOT NULL, state `text` NOT NULL, ended_on `date`, lecture_hours `integer`, practical_hours `integer`, curriculum `text`, industrial_training `boolean` NOT NULL, ca_max `integer` NOT NULL

**`catalogue.course_offer`**: course_code `text` NOT NULL, programme_code `text` NOT NULL, level `integer` NOT NULL, basis `text` NOT NULL, track `text`

**`catalogue.offering`**: id `uuid` NOT NULL, course_code `text` NOT NULL, session `text` NOT NULL, semester `integer` NOT NULL, lecturer_id `uuid`, second_examiner_id `uuid`, allocated_on `date`

**`catalogue.offering_teacher`**: offering_id `uuid` NOT NULL, lecturer_id `uuid` NOT NULL, added_by `uuid`, added_at `timestamp with time zone` NOT NULL

**`clearance.item`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, purpose `text` NOT NULL, unit `text` NOT NULL, state `text` NOT NULL, item `text`, officer_id `uuid`, decided_at `timestamp with time zone` NOT NULL, note `text`, superseded_by `uuid`

**`clearance.unit`**: code `text` NOT NULL, label `text` NOT NULL, clears_against `text` NOT NULL, holds_for `text` NOT NULL, typical_reason `text` NOT NULL, office_code `text`, ord `integer` NOT NULL

**`college.assessment_item`**: id `uuid` NOT NULL, subject_id `uuid`, posting_id `uuid`, item_type `text` NOT NULL, name `text` NOT NULL, weight_within_ca `numeric`, max_score `numeric` NOT NULL, eligibility_gate `boolean` NOT NULL, note `text`

**`college.assessment_score`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, item_id `uuid` NOT NULL, attempt_no `integer` NOT NULL, score `numeric` NOT NULL, assessor_id `uuid`, scored_on `date` NOT NULL

**`college.attendance_record`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, activity_type `text` NOT NULL, posting_id `uuid`, slot_id `uuid`, held_on `date` NOT NULL, present `boolean` NOT NULL, recorded_by `uuid`

**`college.attendance_rule`**: id `uuid` NOT NULL, scope `text` NOT NULL, phase `text`, block_id `uuid`, min_pct `integer` NOT NULL, applies_to `text` NOT NULL, note `text`

**`college.block`**: id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, dept_code `text`, total_weeks `integer`, weeks_note `text`, ordinal `integer` NOT NULL, note `text`

**`college.carry_over`**: student_id `uuid` NOT NULL, code `text` NOT NULL, from_session `text` NOT NULL, note `text`, cleared_on `date`

**`college.case_clerking`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, posting_id `uuid` NOT NULL, done_on `date` NOT NULL, patient_ref `text`, presented `boolean` NOT NULL, verified_by `uuid`

**`college.department_unit`**: id `uuid` NOT NULL, dept_code `text` NOT NULL, name `text` NOT NULL, head_person_id `uuid`

**`college.enrolment`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, level `integer` NOT NULL, session `text` NOT NULL, attempt_no `integer` NOT NULL, kind `text` NOT NULL, state `text` NOT NULL, registered_at `timestamp with time zone`, registered_items `integer`, resit_subjects `ARRAY` NOT NULL, opened_on `date` NOT NULL, closed_on `date`, opened_by `uuid`

**`college.enrolment_semester`**: id `uuid` NOT NULL, enrolment_id `uuid` NOT NULL, ordinal `integer` NOT NULL, name `text` NOT NULL, length_weeks `integer`, subjects `text`, registered_at `timestamp with time zone`, registered_by `uuid`

**`college.event_attendance`**: event_id `uuid` NOT NULL, student_id `uuid` NOT NULL, held_on `date` NOT NULL, present `boolean` NOT NULL

**`college.exam_result`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, subject_id `uuid` NOT NULL, session `text` NOT NULL, attempt `text` NOT NULL, ca_score `numeric`, exam_score `numeric`, clinical_score `numeric`, total `numeric`, passed `boolean`, decided_on `date`, attendance_pct `numeric`, barred `boolean` NOT NULL

**`college.exam_subject`**: id `uuid` NOT NULL, exam_id `uuid` NOT NULL, name `text` NOT NULL, departments `text`, ca_weight `numeric` NOT NULL, exam_weight `numeric` NOT NULL, pass_mark `integer` NOT NULL, clinical_component_min `integer`, conflict_note `text`, ordinal `integer` NOT NULL

**`college.level`**: level `integer` NOT NULL, phase `text` NOT NULL, clinical_year `integer`, enrolment `text` NOT NULL

**`college.mandatory_event`**: id `uuid` NOT NULL, block_id `uuid`, name `text` NOT NULL, weekday `integer`

**`college.posting`**: id `uuid` NOT NULL, block_id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, tier `text` NOT NULL, level `integer`, level_note `text`, duration_weeks `numeric`, ordinal `integer` NOT NULL, min_cases `integer`, note `text`

**`college.posting_allocation`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, posting_id `uuid` NOT NULL, session `text` NOT NULL, group_id `uuid`, supervisor_id `uuid`, starts_on `date`, ends_on `date`, state `text` NOT NULL, allocated_at `timestamp with time zone` NOT NULL

**`college.posting_course`**: posting_id `uuid` NOT NULL, course_code `text` NOT NULL, title `text`, credit_units `integer`, contact_hours `integer`

**`college.procedure_log`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, requirement_id `uuid` NOT NULL, done_on `date` NOT NULL, patient_ref `text`, mode `text` NOT NULL, verified_by `uuid`, verified_at `timestamp with time zone`

**`college.procedure_requirement`**: id `uuid` NOT NULL, posting_id `uuid` NOT NULL, name `text` NOT NULL, min_count `integer` NOT NULL, mode `text` NOT NULL

**`college.professional_exam`**: id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, level `integer` NOT NULL, papers `ARRAY` NOT NULL, external_examiners `boolean` NOT NULL, resit_allowed `boolean` NOT NULL, resit_window_months `integer` NOT NULL, no_resit_if_all_failed `boolean` NOT NULL, appeal_to_senate `boolean` NOT NULL, min_attendance_pct `integer`, on_failure `text` NOT NULL, ordinal `integer` NOT NULL

**`college.programme_rule`**: programme_code `text` NOT NULL, degree `text` NOT NULL, min_years_utme `integer` NOT NULL, min_years_de `integer` NOT NULL, min_total_cu `integer` NOT NULL, regs_effective_from `date` NOT NULL, classified `boolean` NOT NULL, distinction_mark `integer` NOT NULL, resit_window_months `integer` NOT NULL, carry_over_note `text`, honours_rule `text`

**`college.progression_decision`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, from_level `integer` NOT NULL, session `text` NOT NULL, outcome `text` NOT NULL, carry_overs `ARRAY` NOT NULL, rule_ref `text`, minute `text`, decided_on `date` NOT NULL, state `text` NOT NULL, resit_subjects `ARRAY` NOT NULL, honours `boolean`, confirmed_on `date`, confirmed_by `uuid`

**`college.project`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, block_id `uuid`, topic `text` NOT NULL, supervisor_id `uuid`, copies_submitted `integer` NOT NULL, grade `numeric`, defended `boolean` NOT NULL, exam_prerequisite `boolean` NOT NULL

**`college.rotation_group`**: id `uuid` NOT NULL, posting_id `uuid` NOT NULL, label `text` NOT NULL

**`college.semester`**: id `uuid` NOT NULL, session `text` NOT NULL, level `integer` NOT NULL, ordinal `integer` NOT NULL, length_weeks `integer` NOT NULL, starts_on `date`, ends_on `date`

**`college.semester_template`**: level `integer` NOT NULL, ordinal `integer` NOT NULL, name `text` NOT NULL, length_weeks `integer` NOT NULL, subjects `text`

**`college.timetable_slot`**: id `uuid` NOT NULL, posting_id `uuid` NOT NULL, week_no `integer` NOT NULL, weekday `integer` NOT NULL, starts_at `time without time zone` NOT NULL, ends_at `time without time zone` NOT NULL, slot_type `text` NOT NULL, topic `text`

**`credentials.certificate`**: id `uuid` NOT NULL, number `text` NOT NULL, student_id `uuid` NOT NULL, award `text` NOT NULL, class_of_degree `text` NOT NULL, convocation `text` NOT NULL, serial `integer`, batch_id `uuid`, status `text` NOT NULL, printed_on `date` NOT NULL, collected_on `date`, collected_note `text`, held_reason `text`, issuing_name `text` NOT NULL, duplicate_of `uuid`, issued_id `uuid`

**`credentials.delivery`**: id `uuid` NOT NULL, request_id `uuid` NOT NULL, issued_id `uuid`, kind `text` NOT NULL, state `text` NOT NULL, recipient `text`, email `text`, address `text`, courier `text`, tracking_no `text`, dispatched_on `date`, delivered_on `date`, token_id `uuid`, note `text`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`credentials.document_policy`**: kind `text` NOT NULL, label `text` NOT NULL, billable `boolean` NOT NULL, fee `numeric`, urgent_fee `numeric` NOT NULL, physical_fee `numeric` NOT NULL, international_fee `numeric` NOT NULL, currency `text` NOT NULL, self_service `boolean` NOT NULL, sla_days `integer` NOT NULL, urgent_sla_days `integer` NOT NULL, includes `text` NOT NULL, number_prefix `text` NOT NULL, public_fields `ARRAY` NOT NULL, graduates_only `boolean` NOT NULL, active `boolean` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`credentials.document_template`**: id `uuid` NOT NULL, kind `text` NOT NULL, version `integer` NOT NULL, title `text` NOT NULL, subtitle `text`, signatory_name `text` NOT NULL, signatory_title `text` NOT NULL, second_name `text`, second_title `text`, footer `text`, remarks `text`, active `boolean` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`credentials.download_log`**: id `bigint` NOT NULL, issued_id `uuid` NOT NULL, token_id `uuid`, actor_id `uuid`, kind `text` NOT NULL, ip `text`, user_agent `text`, at `timestamp with time zone` NOT NULL

**`credentials.download_token`**: id `uuid` NOT NULL, issued_id `uuid` NOT NULL, token `text` NOT NULL, for_kind `text` NOT NULL, email `text`, expires_at `timestamp with time zone` NOT NULL, max_uses `integer` NOT NULL, uses `integer` NOT NULL, created_at `timestamp with time zone` NOT NULL, revoked_at `timestamp with time zone`

**`credentials.event`**: id `uuid` NOT NULL, request_id `uuid`, issued_id `uuid`, student_id `uuid`, action `text` NOT NULL, from_state `text`, to_state `text`, note `text`, actor_id `uuid`, actor_office `text`, at `timestamp with time zone` NOT NULL

**`credentials.identity_card`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, card_no `text` NOT NULL, issued_at `timestamp with time zone` NOT NULL, issued_by `uuid` NOT NULL, valid_to `date` NOT NULL, state `text` NOT NULL, ended_at `timestamp with time zone`, ended_reason `text`

**`credentials.issued`**: id `uuid` NOT NULL, kind `text` NOT NULL, student_id `uuid` NOT NULL, verification_code `text` NOT NULL, statement `jsonb` NOT NULL, signature `bytea` NOT NULL, signed_with `uuid`, issuing_name `text` NOT NULL, issued_on `date` NOT NULL, issued_by `uuid` NOT NULL, issued_office `text` NOT NULL, supersedes `uuid`, duplicate_of `uuid`, number `text`, version `integer` NOT NULL, template_version `integer`, content_hash `text`, request_id `uuid`, issued_at `timestamp with time zone` NOT NULL, flagged_at `timestamp with time zone`, flag_reason `text`, note `text`

**`credentials.lookup_miss`**: id `bigint` NOT NULL, code `text` NOT NULL, looked_up_at `timestamp with time zone` NOT NULL

**`credentials.revocation`**: credential_id `uuid` NOT NULL, revoked_on `date` NOT NULL, reason `text` NOT NULL, instrument `text` NOT NULL, revoked_by `uuid` NOT NULL, revoked_office `text` NOT NULL, recorded_at `timestamp with time zone` NOT NULL

**`credentials.signing_key`**: id `uuid` NOT NULL, algorithm `text` NOT NULL, public_key `bytea` NOT NULL, custody_ref `text` NOT NULL, validity `daterange` NOT NULL, instrument `text` NOT NULL, retired_on `date`, retired_why `text`

**`credentials.stationery_batch`**: id `uuid` NOT NULL, batch `text` NOT NULL, serial_from `integer` NOT NULL, serial_to `integer` NOT NULL, received_on `date` NOT NULL, spoiled `integer` NOT NULL, returned `integer` NOT NULL

**`credentials.transcript_request`**: id `uuid` NOT NULL, ref `text` NOT NULL, student_id `uuid` NOT NULL, destination `text` NOT NULL, destination_name `text`, mode `text` NOT NULL, express `boolean` NOT NULL, copies `integer` NOT NULL, requested_at `timestamp with time zone` NOT NULL, paid_at `timestamp with time zone`, stage `text` NOT NULL, produced_at `timestamp with time zone`, produced_by `uuid`, released_at `timestamp with time zone`, released_by `uuid`, issued_id `uuid`, kind `text` NOT NULL, session `text`, semester `integer`, delivery `text` NOT NULL, international `boolean` NOT NULL, recipient_department `text`, recipient_name `text`, recipient_email `text`, recipient_address `text`, recipient_reference `text`, purpose `text`, fee `numeric`, reference `text`, started_at `timestamp with time zone`, validated_at `timestamp with time zone`, validation `jsonb`, qc_at `timestamp with time zone`, qc_by `uuid`, qc_note `text`, delivered_at `timestamp with time zone`, completed_at `timestamp with time zone`, closed_at `timestamp with time zone`, closed_reason `text`, sla_due_on `date`

**`credentials.verification`**: id `bigint` NOT NULL, key `text` NOT NULL, issued_id `uuid`, kind `text`, status `text` NOT NULL, ip `text`, user_agent `text`, at `timestamp with time zone` NOT NULL

**`expenditure.asset`**: id `uuid` NOT NULL, tag `text` NOT NULL, name `text` NOT NULL, category `text`, location `text`, acquired_on `date`, cost `numeric`, condition `text` NOT NULL, last_verified_on `date`, note `text`

**`expenditure.bid`**: id `uuid` NOT NULL, tender_id `uuid` NOT NULL, bidder `text` NOT NULL, price `numeric` NOT NULL, technical_score `integer`, responsive `boolean`, reason `text`, submitted_at `timestamp with time zone` NOT NULL

**`expenditure.budget`**: cost_centre `text` NOT NULL, financial_year `integer` NOT NULL, amount `numeric` NOT NULL, set_by `uuid` NOT NULL, set_at `timestamp with time zone` NOT NULL

**`expenditure.requisition`**: id `uuid` NOT NULL, reference `text` NOT NULL, item `text` NOT NULL, description `text`, cost_centre `text` NOT NULL, value `numeric` NOT NULL, state `text` NOT NULL, note `text`, raised_by `uuid`, raised_at `timestamp with time zone` NOT NULL, decided_by `uuid`, decided_at `timestamp with time zone`, decision_note `text`

**`expenditure.research_grant`**: id `uuid` NOT NULL, reference `text` NOT NULL, title `text` NOT NULL, principal_investigator `text` NOT NULL, sponsor `text` NOT NULL, amount `numeric` NOT NULL, currency `text` NOT NULL, starts_on `date`, ends_on `date`, state `text` NOT NULL, note `text`

**`expenditure.store_item`**: id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, unit `text` NOT NULL, quantity `numeric` NOT NULL, reorder_level `numeric`, location `text`, note `text`

**`expenditure.tender`**: id `uuid` NOT NULL, reference `text` NOT NULL, subject `text` NOT NULL, cost_centre `text`, estimate `numeric` NOT NULL, method `text` NOT NULL, technical_threshold `integer` NOT NULL, stage `text` NOT NULL, opened_by `uuid` NOT NULL, opened_at `timestamp with time zone` NOT NULL, awarded_bid `uuid`, awarded_why `text`, cancelled_why `text`

**`expenditure.voucher`**: id `uuid` NOT NULL, reference `text` NOT NULL, title `text` NOT NULL, kind `text` NOT NULL, source `text` NOT NULL, cost_centre `text`, payee `text` NOT NULL, amount `numeric` NOT NULL, stage `text` NOT NULL, raised_by `uuid` NOT NULL, raised_at `timestamp with time zone` NOT NULL, paid_at `timestamp with time zone`, paid_by `uuid`, rejected_why `text`

**`expenditure.voucher_act`**: id `uuid` NOT NULL, voucher_id `uuid` NOT NULL, actor_id `uuid` NOT NULL, office `text` NOT NULL, act `text` NOT NULL, from_stage `text` NOT NULL, to_stage `text` NOT NULL, note `text`, at `timestamp with time zone` NOT NULL

**`expenditure.voucher_query`**: id `uuid` NOT NULL, voucher_id `uuid` NOT NULL, finding `text` NOT NULL, sent_to `text` NOT NULL, raised_by `uuid` NOT NULL, raised_at `timestamp with time zone` NOT NULL, answer `text`, answered_at `timestamp with time zone`, answered_by `uuid`

**`extexam.appointment`**: id `uuid` NOT NULL, examiner_id `uuid` NOT NULL, session `text` NOT NULL, semester `integer`, faculty_code `text` NOT NULL, dept_code `text` NOT NULL, programme_code `text`, period `text`, starts_on `date` NOT NULL, ends_on `date` NOT NULL, status `text` NOT NULL, instrument `text`, appointed_by `uuid`, appointed_at `timestamp with time zone` NOT NULL

**`extexam.assessment`**: id `uuid` NOT NULL, assignment_id `uuid` NOT NULL, state `text` NOT NULL, total `numeric`, max_total `numeric`, percentage `numeric`, grade `text`, general_comments `text`, strengths `text`, weaknesses `text`, recommendations `text`, corrections `text`, final_recommendation `text`, version `integer` NOT NULL, started_at `timestamp with time zone` NOT NULL, saved_at `timestamp with time zone` NOT NULL, submitted_at `timestamp with time zone`, locked_at `timestamp with time zone`, locked_by `uuid`, reopened_at `timestamp with time zone`, reopened_by `uuid`, reopen_reason `text`

**`extexam.assessment_score`**: assessment_id `uuid` NOT NULL, criterion_id `uuid` NOT NULL, score `numeric`, comment `text`

**`extexam.assignment`**: id `uuid` NOT NULL, project_id `uuid` NOT NULL, examiner_id `uuid` NOT NULL, appointment_id `uuid`, rubric_id `uuid` NOT NULL, deadline `date` NOT NULL, exam_date `date`, status `text` NOT NULL, assigned_by `uuid`, assigned_at `timestamp with time zone` NOT NULL, first_viewed_at `timestamp with time zone`, ended_at `timestamp with time zone`, ended_reason `text`, replaced_by `uuid`, reminded_at `timestamp with time zone`, overdue_told_at `timestamp with time zone`

**`extexam.criterion`**: id `uuid` NOT NULL, rubric_id `uuid` NOT NULL, section `text` NOT NULL, name `text` NOT NULL, guidance `text`, max_score `numeric` NOT NULL, ordinal `integer` NOT NULL, active `boolean` NOT NULL

**`extexam.event`**: id `uuid` NOT NULL, at `timestamp with time zone` NOT NULL, actor_id `uuid`, actor_office `text`, actor_name `text` NOT NULL, action `text` NOT NULL, examiner_id `uuid`, project_id `uuid`, assignment_id `uuid`, from_value `text`, to_value `text`, reason `text`

**`extexam.examiner`**: id `uuid` NOT NULL, person_id `uuid` NOT NULL, pg_examiner_id `uuid`, title `text`, email `text` NOT NULL, phone `text`, institution `text` NOT NULL, department `text`, rank `text`, specialization `text`, qualification `text`, professional `text`, experience_years `integer`, country `text`, region `text`, orcid `text`, status `text` NOT NULL, notes `text`, created_by `uuid`, created_at `timestamp with time zone` NOT NULL, activated_at `timestamp with time zone`

**`extexam.examiner_file`**: id `uuid` NOT NULL, examiner_id `uuid` NOT NULL, kind `text` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, bytes `bigint` NOT NULL, uploaded_by `uuid`, uploaded_at `timestamp with time zone` NOT NULL

**`extexam.examiner_file_blob`**: file_id `uuid` NOT NULL, content `bytea` NOT NULL

**`extexam.invitation`**: id `uuid` NOT NULL, examiner_id `uuid` NOT NULL, token_hash `text` NOT NULL, sent_by `uuid`, sent_at `timestamp with time zone` NOT NULL, expires_at `timestamp with time zone` NOT NULL, used_at `timestamp with time zone`

**`extexam.project`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, kind `text` NOT NULL, pg_research_id `uuid`, course_code `text`, session `text` NOT NULL, title `text` NOT NULL, abstract `text`, keywords `text`, project_type `text`, submitted_on `date`, supervisor_id `uuid`, supervisor_name `text`, co_supervisor `text`, created_by `uuid`, created_at `timestamp with time zone` NOT NULL

**`extexam.project_document`**: id `uuid` NOT NULL, project_id `uuid` NOT NULL, kind `text` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, bytes `bigint` NOT NULL, released `boolean` NOT NULL, uploaded_by `uuid`, uploaded_at `timestamp with time zone` NOT NULL

**`extexam.project_document_blob`**: document_id `uuid` NOT NULL, content `bytea` NOT NULL

**`extexam.rubric`**: id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, kind `text` NOT NULL, active `boolean` NOT NULL, has_defence `boolean` NOT NULL, note `text`, created_at `timestamp with time zone` NOT NULL

**`finance.bank_credit`**: id `uuid` NOT NULL, received_on `date` NOT NULL, bank `text` NOT NULL, instrument `text` NOT NULL, amount `numeric` NOT NULL, payer `text`, note `text`, recorded_by `uuid` NOT NULL, recorded_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, proposed_reference `text`, proposed_by `uuid`, proposed_why `text`, proposed_at `timestamp with time zone`, approved_by `uuid`, approved_at `timestamp with time zone`, posted_reference `text`, rejected_why `text`

**`finance.fee_schedule`**: id `uuid` NOT NULL, session `text` NOT NULL, item `text` NOT NULL, amount `numeric` NOT NULL, level `integer`, entry_mode `text`, faculty_code `text`, programme_code `text`, ord `integer` NOT NULL, ended_at `timestamp with time zone`, fee_group `text`, semester `integer`, indigene `text`, spillover `boolean` NOT NULL

**`finance.fee_setting`**: id `integer` NOT NULL, home_state `text` NOT NULL, transfer_fee `numeric`

**`finance.funding_source`**: code `text` NOT NULL, name `text` NOT NULL, nature `text` NOT NULL, sponsor `text`, account `text`, active `boolean` NOT NULL, note `text`, sort `integer` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`finance.gateway_attempt`**: id `uuid` NOT NULL, reference `text` NOT NULL, gateway `text` NOT NULL, kind `text` NOT NULL, account_id `uuid` NOT NULL, opened_at `timestamp with time zone` NOT NULL, checked_at `timestamp with time zone`, checks `integer` NOT NULL

**`finance.gateway_credential`**: gateway `text` NOT NULL, secret_enc `bytea`, hash_enc `bytea`, mode `text`, last4 `text`, set_by `uuid`, set_at `timestamp with time zone`

**`finance.gateway_credential_event`**: id `uuid` NOT NULL, gateway `text` NOT NULL, kind `text` NOT NULL, mode `text`, last4 `text`, by_person `uuid` NOT NULL, at `timestamp with time zone` NOT NULL

**`finance.gateway_event`**: id `uuid` NOT NULL, gateway `text` NOT NULL, source `text` NOT NULL, event `text`, reference `text`, gateway_ref `text`, amount `numeric`, status `text`, signature_ok `boolean` NOT NULL, outcome `text` NOT NULL, payload `jsonb`, received_at `timestamp with time zone` NOT NULL, resolved_at `timestamp with time zone`, resolved_by `uuid`, resolution `text`

**`finance.gl_account`**: code `text` NOT NULL, name `text` NOT NULL, type `text` NOT NULL, normal_side `character` NOT NULL, parent_code `text`, postable `boolean` NOT NULL, active `boolean` NOT NULL, ord `integer` NOT NULL

**`finance.gl_journal`**: id `uuid` NOT NULL, journal_no `bigint` NOT NULL, entry_date `date` NOT NULL, memo `text` NOT NULL, source `text` NOT NULL, source_type `text`, source_ref `text`, status `text` NOT NULL, reverses `uuid`, posted_by `uuid`, posted_at `timestamp with time zone` NOT NULL

**`finance.gl_posting`**: id `uuid` NOT NULL, journal_id `uuid` NOT NULL, line `integer` NOT NULL, account `text` NOT NULL, debit `numeric` NOT NULL, credit `numeric` NOT NULL, narration `text`, session `text`, fund `text`

**`finance.nelfund_batch`**: id `uuid` NOT NULL, ref `text` NOT NULL, session `text` NOT NULL, received_on `date` NOT NULL, amount `numeric` NOT NULL, rows_read `integer` NOT NULL, note `text`, loaded_at `timestamp with time zone` NOT NULL

**`finance.nelfund_row`**: id `uuid` NOT NULL, batch_id `uuid` NOT NULL, matric_no `text` NOT NULL, name_on_remit `text`, amount `numeric` NOT NULL, state `text` NOT NULL, student_id `uuid`, why `text`, owner `text`, decided_at `timestamp with time zone`

**`finance.nelfund_status`**: id `uuid` NOT NULL, session `text` NOT NULL, number `text` NOT NULL, name `text`, state `text` NOT NULL, reason `text`, correctable `boolean` NOT NULL, student_id `uuid`, loaded_at `timestamp with time zone` NOT NULL

**`finance.paydirect_biller`**: scope `text` NOT NULL, biller_code `text` NOT NULL, name `text` NOT NULL, pay_link `text`, active `boolean` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`finance.paydirect_collection`**: id `uuid` NOT NULL, biller_code `text`, prn `text` NOT NULL, amount `numeric`, paid_at `timestamp with time zone`, channel `text`, rrn `text`, payer `text`, state `text` NOT NULL, reference `text`, why `text`, imported_at `timestamp with time zone` NOT NULL

**`finance.payment_reconciliation`**: id `uuid` NOT NULL, reference `text` NOT NULL, result `text` NOT NULL, bank_reference `text`, note `text`, checked_by `uuid` NOT NULL, checked_at `timestamp with time zone` NOT NULL

**`finance.payment_reference`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, reference `text` NOT NULL, purpose `text` NOT NULL, amount `numeric` NOT NULL, generated_at `timestamp with time zone` NOT NULL, expires_at `timestamp with time zone` NOT NULL, confirmed_at `timestamp with time zone`, confirmed_by `uuid`, channel `text`, note `text`, receipt_no `text`

**`finance.refund`**: id `uuid` NOT NULL, reference `text` NOT NULL, student_id `uuid`, payer `text` NOT NULL, reason `text` NOT NULL, amount `numeric` NOT NULL, bank_name `text`, account_name `text`, account_last4 `text`, state `text` NOT NULL, proposed_by `uuid` NOT NULL, proposed_at `timestamp with time zone` NOT NULL, approved_by `uuid`, approved_at `timestamp with time zone`, rejected_why `text`, paid_at `timestamp with time zone`, paid_by `uuid`, source_reference `text`

**`finance.wallet_entry`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, kind `text` NOT NULL, amount `numeric` NOT NULL, reference `text`, note `text`, at `timestamp with time zone` NOT NULL, source_code `text`

**`finance.wallet_withdrawal`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, amount `numeric` NOT NULL, bank_name `text` NOT NULL, account_no `text` NOT NULL, account_name `text` NOT NULL, state `text` NOT NULL, reason `text`, requested_at `timestamp with time zone` NOT NULL, requested_by `uuid`, decided_at `timestamp with time zone`, decided_by `uuid`, paid_at `timestamp with time zone`, paid_by `uuid`, paid_ref `text`, entry_id `uuid`

**`governance.dr_drill`**: id `uuid` NOT NULL, kind `text` NOT NULL, ran_on `date` NOT NULL, rpo_minutes `integer`, rto_minutes `integer`, outcome `text` NOT NULL, note `text`

**`governance.dsr`**: id `uuid` NOT NULL, reference `text` NOT NULL, kind `text` NOT NULL, requester `text` NOT NULL, received_on `date` NOT NULL, due_on `date` NOT NULL, state `text` NOT NULL, note `text`

**`governance.processing_activity`**: id `uuid` NOT NULL, activity `text` NOT NULL, lawful_basis `text` NOT NULL, sensitive `boolean` NOT NULL, retention `text` NOT NULL, dpia_state `text` NOT NULL, note `text`

**`health.appointment`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, reason `text` NOT NULL, preferred_at `timestamp with time zone` NOT NULL, booked_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, cancelled_why `text`

**`health.note`**: id `uuid` NOT NULL, visit_id `uuid` NOT NULL, written_by `uuid` NOT NULL, written_at `timestamp with time zone` NOT NULL, note `text` NOT NULL

**`health.profile`**: student_id `uuid` NOT NULL, blood_group `text`, genotype `text`, allergies `text`, consented_at `timestamp with time zone`, restricted_at `timestamp with time zone`, fitness `text` NOT NULL, fitness_on `date`, fitness_by `uuid`

**`health.record_access`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, person_id `uuid` NOT NULL, office `text` NOT NULL, what `text` NOT NULL, at `timestamp with time zone` NOT NULL

**`health.visit`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, appointment_id `uuid`, arrived_at `timestamp with time zone` NOT NULL, presenting `text` NOT NULL, triage `text` NOT NULL, state `text` NOT NULL, seen_at `timestamp with time zone`, clinician_id `uuid`, outcome `text`, referred_to `text`, concluded_at `timestamp with time zone`

**`helpdesk.category`**: id `uuid` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, description `text`, active `boolean` NOT NULL, ordinal `integer` NOT NULL, suggested_priority `text` NOT NULL, fields `jsonb` NOT NULL, attachment_hint `text`, created_at `timestamp with time zone` NOT NULL

**`helpdesk.setting`**: row_no `boolean` NOT NULL, auto_close_days `integer`, notify_agents_on_new `boolean` NOT NULL

**`helpdesk.sla`**: priority `text` NOT NULL, first_response_hours `integer` NOT NULL, resolution_hours `integer` NOT NULL

**`helpdesk.ticket`**: id `uuid` NOT NULL, number `text` NOT NULL, category_id `uuid` NOT NULL, subject `text` NOT NULL, description `text` NOT NULL, priority `text` NOT NULL, status `text` NOT NULL, requester_kind `text` NOT NULL, requester_id `uuid` NOT NULL, requester_name `text` NOT NULL, requester_number `text`, requester_email `text`, requester_phone `text`, department_code `text`, faculty_code `text`, details `jsonb` NOT NULL, assigned_to `uuid`, assigned_by `uuid`, assigned_at `timestamp with time zone`, escalated_to `uuid`, escalated_by `uuid`, escalated_at `timestamp with time zone`, escalation_reason `text`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL, opened_at `timestamp with time zone`, opened_by `uuid`, first_response_at `timestamp with time zone`, in_progress_at `timestamp with time zone`, resolved_at `timestamp with time zone`, resolved_by `uuid`, resolution_summary `text`, resolution_details `text`, closed_at `timestamp with time zone`, closed_by `uuid`, closed_by_kind `text`, closure_reason `text`, reopen_count `integer` NOT NULL

**`helpdesk.ticket_attachment`**: id `uuid` NOT NULL, ticket_id `uuid` NOT NULL, comment_id `uuid`, uploaded_kind `text` NOT NULL, uploaded_by `uuid`, uploader_name `text` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, bytes `bigint` NOT NULL, internal `boolean` NOT NULL, uploaded_at `timestamp with time zone` NOT NULL

**`helpdesk.ticket_attachment_blob`**: attachment_id `uuid` NOT NULL, content `bytea` NOT NULL

**`helpdesk.ticket_comment`**: id `uuid` NOT NULL, ticket_id `uuid` NOT NULL, author_kind `text` NOT NULL, author_id `uuid`, author_name `text` NOT NULL, internal `boolean` NOT NULL, body `text` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`helpdesk.ticket_event`**: id `uuid` NOT NULL, ticket_id `uuid` NOT NULL, at `timestamp with time zone` NOT NULL, actor_kind `text` NOT NULL, actor_id `uuid`, actor_name `text` NOT NULL, action `text` NOT NULL, from_value `text`, to_value `text`, detail `text`, internal `boolean` NOT NULL

**`hostel.allocation`**: id `uuid` NOT NULL, application_id `uuid` NOT NULL, session `text` NOT NULL, room_id `uuid` NOT NULL, bed `integer` NOT NULL, basis `text` NOT NULL, draw_position `integer`, allocated_at `timestamp with time zone` NOT NULL, held_until `timestamp with time zone` NOT NULL, reference `text`, confirmed_at `timestamp with time zone`, lapsed_at `timestamp with time zone`, ended_at `timestamp with time zone`, ended_reason `text`, reference_no `text` NOT NULL, student_id `uuid` NOT NULL, bed_id `uuid`, state `text` NOT NULL, start_on `date`, end_on `date`, accepted_at `timestamp with time zone`, rules_version `integer`, declined_at `timestamp with time zone`, decline_reason `text`, checked_in_at `timestamp with time zone`, checked_in_by `uuid`, checkin_note `text`, checkout_requested_at `timestamp with time zone`, checkout_on `date`, checkout_reason `text`, checked_out_at `timestamp with time zone`, checked_out_by `uuid`, moved_from `uuid`

**`hostel.application`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, hall_code `text`, category `text` NOT NULL, category_note `text`, applied_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, draw_position `integer`, reference `text` NOT NULL, room_type_pref `text`, block_pref `text`, special_need `text`, roommate_id `uuid`, roommate_note `text`, review `text`, review_note `text`, reviewed_by `uuid`, reviewed_at `timestamp with time zone`, withdrawn_at `timestamp with time zone`, withdrawn_reason `text`

**`hostel.asset`**: id `uuid` NOT NULL, tag `text` NOT NULL, kind `text` NOT NULL, hall_code `text` NOT NULL, block_id `uuid`, room_id `uuid`, quantity `integer` NOT NULL, condition `text` NOT NULL, acquired_on `date`, value `numeric`, state `text` NOT NULL, note `text`, created_at `timestamp with time zone` NOT NULL

**`hostel.bed`**: id `uuid` NOT NULL, room_id `uuid` NOT NULL, number `integer` NOT NULL, label `text` NOT NULL, state `text` NOT NULL, state_reason `text`

**`hostel.block`**: id `uuid` NOT NULL, hall_code `text` NOT NULL, code `text` NOT NULL, name `text` NOT NULL, floors `integer` NOT NULL, state `text` NOT NULL, state_reason `text`, note `text`

**`hostel.clearance`**: id `uuid` NOT NULL, allocation_id `uuid` NOT NULL, reference `text` NOT NULL, state `text` NOT NULL, started_at `timestamp with time zone` NOT NULL, started_by `uuid`, completed_at `timestamp with time zone`, completed_by `uuid`, note `text`

**`hostel.clearance_item`**: id `uuid` NOT NULL, clearance_id `uuid` NOT NULL, requirement `text` NOT NULL, state `text` NOT NULL, officer_id `uuid`, decided_at `timestamp with time zone`, remarks `text`

**`hostel.clearance_requirement`**: code `text` NOT NULL, label `text` NOT NULL, ord `integer` NOT NULL, active `boolean` NOT NULL

**`hostel.damage_charge`**: id `uuid` NOT NULL, allocation_id `uuid` NOT NULL, inspection_id `uuid`, asset_id `uuid`, description `text` NOT NULL, repair_cost `numeric`, replacement_cost `numeric`, charge `numeric` NOT NULL, reference `text`, raised_by `uuid`, raised_at `timestamp with time zone` NOT NULL, settled_at `timestamp with time zone`, waived_at `timestamp with time zone`, waived_by `uuid`, waived_reason `text`

**`hostel.event`**: id `uuid` NOT NULL, application_id `uuid`, allocation_id `uuid`, student_id `uuid`, hall_code `text`, room_id `uuid`, bed_id `uuid`, action `text` NOT NULL, from_value `text`, to_value `text`, note `text`, actor_id `uuid`, actor_office `text`, at `timestamp with time zone` NOT NULL

**`hostel.facility`**: code `text` NOT NULL, label `text` NOT NULL, active `boolean` NOT NULL

**`hostel.hall`**: code `text` NOT NULL, name `text` NOT NULL, sex `text`, ended_on `date`, kind `text` NOT NULL, campus `text`, location `text`, description `text`, state `text` NOT NULL, state_reason `text`

**`hostel.hall_kind`**: code `text` NOT NULL, label `text` NOT NULL, active `boolean` NOT NULL

**`hostel.inspection`**: id `uuid` NOT NULL, allocation_id `uuid` NOT NULL, kind `text` NOT NULL, inspected_by `uuid`, inspected_at `timestamp with time zone` NOT NULL, condition `text` NOT NULL, cleanliness `text`, damages `text`, keys_returned `boolean`, card_returned `boolean`, remarks `text`

**`hostel.maintenance_request`**: id `uuid` NOT NULL, room_id `uuid` NOT NULL, raised_by `uuid` NOT NULL, issue `text` NOT NULL, raised_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, note `text`, decided_at `timestamp with time zone`, category `text` NOT NULL, priority `text` NOT NULL, bed_id `uuid`, asset_id `uuid`, assigned_to `text`

**`hostel.room`**: id `uuid` NOT NULL, hall_code `text` NOT NULL, block `text` NOT NULL, room_no `text` NOT NULL, beds `integer` NOT NULL, out_of_service `boolean` NOT NULL, note `text`, block_id `uuid`, floor `integer` NOT NULL, room_type `text`, sex `text`, state `text` NOT NULL, state_reason `text`

**`hostel.room_facility`**: room_id `uuid` NOT NULL, facility_code `text` NOT NULL, quantity `integer` NOT NULL

**`hostel.room_type`**: code `text` NOT NULL, label `text` NOT NULL, beds `integer` NOT NULL, active `boolean` NOT NULL

**`hostel.session_setting`**: session `text` NOT NULL, fee `numeric` NOT NULL, hold_hours `integer` NOT NULL, applications_close `date`, seed `text`, drawn_at `timestamp with time zone`, drawn_by `uuid`, applications_open `date`, allocation_method `text` NOT NULL, requires_review `boolean` NOT NULL, waitlist `boolean` NOT NULL, max_applications `integer`, eligible_statuses `ARRAY` NOT NULL, eligible_levels `ARRAY`, eligible_faculties `ARRAY`, eligible_kinds `ARRAY`, require_registration `boolean` NOT NULL, refuse_hostel_debt `boolean` NOT NULL, rules `text`, rules_version `integer` NOT NULL, stay_from `date`, stay_to `date`, state `text` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`hostel.transfer_request`**: id `uuid` NOT NULL, allocation_id `uuid` NOT NULL, student_id `uuid` NOT NULL, requested_hall `text`, requested_type `text`, reason `text` NOT NULL, state `text` NOT NULL, submitted_at `timestamp with time zone` NOT NULL, decided_by `uuid`, decided_at `timestamp with time zone`, decision_note `text`, new_allocation `uuid`

**`hrm.applicant`**: id `uuid` NOT NULL, vacancy_id `uuid` NOT NULL, name `text` NOT NULL, email `text`, phone `text`, qualification `text`, publications `integer`, teaching_years `numeric`, score `integer`, recommendation `text`, state `text` NOT NULL, applied_at `timestamp with time zone` NOT NULL

**`hrm.appraisal`**: id `uuid` NOT NULL, employment_id `uuid` NOT NULL, person_id `uuid` NOT NULL, cycle `text` NOT NULL, self_score `integer`, supervisor_score `integer`, aper_grade `text`, publications `integer`, note `text`, state `text` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`hrm.employment`**: id `uuid` NOT NULL, person_id `uuid` NOT NULL, staff_no `text` NOT NULL, grade `text` NOT NULL, step `integer` NOT NULL, category `text` NOT NULL, appointment_date `date` NOT NULL, status `text` NOT NULL, bank_name `text`, account_name `text`, account_last4 `text`, pension_pin `text`, ended_on `date`, ended_reason `text`

**`hrm.grade`**: grade `text` NOT NULL, step `integer` NOT NULL, category `text` NOT NULL, basic `numeric` NOT NULL, housing `numeric` NOT NULL, transport `numeric` NOT NULL, other_allowances `numeric` NOT NULL

**`hrm.leave_request`**: id `uuid` NOT NULL, employment_id `uuid` NOT NULL, person_id `uuid` NOT NULL, leave_type `text` NOT NULL, from_date `date` NOT NULL, to_date `date` NOT NULL, days `integer` NOT NULL, cover `text`, note `text`, state `text` NOT NULL, requested_at `timestamp with time zone` NOT NULL, requested_by `uuid`, decided_at `timestamp with time zone`, decided_by `uuid`, decision_note `text`

**`hrm.leave_type`**: code `text` NOT NULL, name `text` NOT NULL, max_days `integer` NOT NULL, paid `boolean` NOT NULL, annual `boolean` NOT NULL

**`hrm.movement`**: id `uuid` NOT NULL, employment_id `uuid` NOT NULL, person_id `uuid` NOT NULL, kind `text` NOT NULL, effective_date `date` NOT NULL, what_changes `text` NOT NULL, reason `text`, new_grade `text`, new_step `integer`, state `text` NOT NULL, requested_at `timestamp with time zone` NOT NULL, requested_by `uuid`, approved_at `timestamp with time zone`, approved_by `uuid`, decision_note `text`, instrument `text`, instrument_at `timestamp with time zone`, implemented_at `timestamp with time zone`

**`hrm.pay_run`**: id `uuid` NOT NULL, period `date` NOT NULL, state `text` NOT NULL, staff_count `integer` NOT NULL, gross_total `numeric` NOT NULL, deduction_total `numeric` NOT NULL, net_total `numeric` NOT NULL, note `text`, built_by `uuid` NOT NULL, built_at `timestamp with time zone` NOT NULL, approved_by `uuid`, approved_at `timestamp with time zone`, cancelled_why `text`, paid_by `uuid`, paid_at `timestamp with time zone`

**`hrm.payslip`**: id `uuid` NOT NULL, run_id `uuid` NOT NULL, employment_id `uuid` NOT NULL, person_id `uuid` NOT NULL, staff_no `text` NOT NULL, name `text` NOT NULL, grade `text` NOT NULL, step `integer` NOT NULL, category `text` NOT NULL, basic `numeric` NOT NULL, allowances `numeric` NOT NULL, gross `numeric` NOT NULL, pension `numeric` NOT NULL, paye `numeric` NOT NULL, other_deductions `numeric` NOT NULL, net `numeric` NOT NULL, bank_name `text`, account_last4 `text`

**`hrm.staff_photo`**: person_id `uuid` NOT NULL, content_type `text` NOT NULL, bytes `bigint` NOT NULL, content `bytea` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`hrm.staff_profile`**: person_id `uuid` NOT NULL, email `text`, phone `text`, department `text`, faculty `text`, responsibility `text`, scholar_url `text`, orcid `text`, research_interests `text`, masters_graduated `integer` NOT NULL, phd_graduated `integer` NOT NULL, publications `jsonb` NOT NULL, grants `jsonb` NOT NULL, collaborations `jsonb` NOT NULL, conferences `jsonb` NOT NULL, assignments `jsonb` NOT NULL, innovations `jsonb` NOT NULL, patents `jsonb` NOT NULL, achievements `jsonb` NOT NULL, contributions `jsonb` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`hrm.staff_record`**: person_id `uuid` NOT NULL, pno `text`, sex `text`, date_first_appointment `date`, present_rank `text`, conuass_step `integer`, home_department `text`, updated_at `timestamp with time zone` NOT NULL, category `text`, salary_scale `text`, contiss_step `integer`, home_unit `text`, home_faculty `text`, unit_as_given `text`

**`hrm.vacancy`**: id `uuid` NOT NULL, title `text` NOT NULL, department `text` NOT NULL, requirements `text` NOT NULL, grade `text`, category `text`, opened_on `date` NOT NULL, closes_on `date`, state `text` NOT NULL, note `text`

**`iam.credential`**: person_id `uuid` NOT NULL, username `text` NOT NULL, password_hash `text` NOT NULL, must_change `boolean` NOT NULL, failed_attempts `integer` NOT NULL, locked_until `timestamp with time zone`, set_at `timestamp with time zone` NOT NULL, set_by `uuid` NOT NULL, last_sign_in_at `timestamp with time zone`

**`iam.credential_event`**: id `uuid` NOT NULL, person_id `uuid` NOT NULL, kind `text` NOT NULL, at `timestamp with time zone` NOT NULL, by_person `uuid` NOT NULL, note `text`

**`iam.office_assignment`**: id `uuid` NOT NULL, person_id `uuid` NOT NULL, office_code `text` NOT NULL, scope_kind `text` NOT NULL, scope_id `text`, instrument `text` NOT NULL, granted_by `uuid` NOT NULL, valid_from `date` NOT NULL, valid_to `date`

**`iam.password_reset`**: id `uuid` NOT NULL, subject_kind `text` NOT NULL, subject_id `uuid` NOT NULL, token_hash `text` NOT NULL, expires_at `timestamp with time zone` NOT NULL, used_at `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL

**`iam.person`**: id `uuid` NOT NULL, staff_number `text`, surname `text` NOT NULL, given_names `text` NOT NULL, ended_on `date`, ended_reason `text`, email `text`, phone `text`

**`iam.sign_in_event`**: id `uuid` NOT NULL, at `timestamp with time zone` NOT NULL, username `text` NOT NULL, person_id `uuid`, outcome `text` NOT NULL, source_ip `inet`, session_id `bytea`

**`iam.student_account`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, password_hash `text` NOT NULL, must_change `boolean` NOT NULL, failed_attempts `integer` NOT NULL, locked_until `timestamp with time zone`, created_at `timestamp with time zone` NOT NULL, last_signed_in_at `timestamp with time zone`

**`iam.student_event`**: id `uuid` NOT NULL, student_id `uuid`, identifier `text` NOT NULL, outcome `text` NOT NULL, ip `text`, at `timestamp with time zone` NOT NULL

**`library.copy`**: accession `text` NOT NULL, item_id `uuid` NOT NULL, location `text`, state `text` NOT NULL, ended_on `date`, ended_reason `text`

**`library.item`**: id `uuid` NOT NULL, title `text` NOT NULL, author `text`, edition `text`, year `integer`, isbn `text`, subject `text`, kind `text` NOT NULL, ended_on `date`

**`library.loan`**: id `uuid` NOT NULL, accession `text` NOT NULL, student_id `uuid`, person_id `uuid`, issued_at `timestamp with time zone` NOT NULL, due_on `date` NOT NULL, renewals `integer` NOT NULL, returned_at `timestamp with time zone`, fine `numeric`, fine_reference `text`, fine_settled_at `timestamp with time zone`, fine_waived_at `timestamp with time zone`, fine_waived_why `text`

**`library.reservation`**: id `uuid` NOT NULL, item_id `uuid` NOT NULL, student_id `uuid` NOT NULL, reserved_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, decided_at `timestamp with time zone`

**`library.setting`**: row_no `integer` NOT NULL, loan_days `integer` NOT NULL, fine_per_day `numeric` NOT NULL, max_loans `integer` NOT NULL, max_renewals `integer` NOT NULL

**`lms.access`**: id `uuid` NOT NULL, material_id `uuid` NOT NULL, student_id `uuid` NOT NULL, at `timestamp with time zone` NOT NULL

**`lms.assignment`**: id `uuid` NOT NULL, offering_id `uuid` NOT NULL, title `text` NOT NULL, brief `text`, kind `text` NOT NULL, opens_at `timestamp with time zone` NOT NULL, closes_at `timestamp with time zone` NOT NULL, late_hours `integer` NOT NULL, late_penalty `integer` NOT NULL, weight `integer` NOT NULL, out_of `integer` NOT NULL, created_by `uuid` NOT NULL, created_at `timestamp with time zone` NOT NULL, ended_at `timestamp with time zone`

**`lms.material`**: id `uuid` NOT NULL, offering_id `uuid` NOT NULL, week `integer`, title `text` NOT NULL, kind `text` NOT NULL, description `text`, filename `text`, content_type `text`, bytes `bigint`, link `text`, published_at `timestamp with time zone`, published_by `uuid`, created_at `timestamp with time zone` NOT NULL, ended_at `timestamp with time zone`

**`lms.material_blob`**: material_id `uuid` NOT NULL, content `bytea` NOT NULL

**`lms.submission`**: id `uuid` NOT NULL, assignment_id `uuid` NOT NULL, student_id `uuid` NOT NULL, submitted_at `timestamp with time zone` NOT NULL, text `text`, filename `text`, content_type `text`, bytes `bigint`, late `boolean` NOT NULL, mark `numeric`, marked_at `timestamp with time zone`, marked_by `uuid`, feedback `text`

**`lms.submission_blob`**: submission_id `uuid` NOT NULL, content `bytea` NOT NULL

**`people.biodata`**: student_id `uuid` NOT NULL, field `text` NOT NULL, value `text` NOT NULL

**`people.biodata_change`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, field `text` NOT NULL, from_value `text`, to_value `text` NOT NULL, evidence `text`, evidence_ref `uuid`, requested_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, decided_at `timestamp with time zone`, decided_by `uuid`, decision `text`

**`people.deferment`**: id `uuid` NOT NULL, reference `text` NOT NULL, student_id `uuid` NOT NULL, kind `text` NOT NULL, session `text` NOT NULL, semester `integer`, reason_code `text` NOT NULL, explanation `text`, declared `boolean` NOT NULL, state `text` NOT NULL, extension_of `uuid`, period_from `date`, return_session `text`, return_semester `integer`, return_on `date`, submitted_at `timestamp with time zone`, dept_at `timestamp with time zone`, dept_by `uuid`, dept_note `text`, fac_at `timestamp with time zone`, fac_by `uuid`, fac_note `text`, decided_at `timestamp with time zone`, decided_by `uuid`, decision_note `text`, correction_note `text`, cancel_note `text`, prior_status `text`, activated_at `timestamp with time zone`, reminder_sent_at `timestamp with time zone`, returned_at `timestamp with time zone`, returned_by `uuid`, return_note `text`, created_at `timestamp with time zone` NOT NULL, updated_at `timestamp with time zone` NOT NULL

**`people.deferment_document`**: id `uuid` NOT NULL, deferment_id `uuid` NOT NULL, kind `text` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, size_bytes `integer` NOT NULL, uploaded_by `uuid`, uploaded_at `timestamp with time zone` NOT NULL, verified_at `timestamp with time zone`, verified_by `uuid`

**`people.deferment_document_blob`**: document_id `uuid` NOT NULL, bytes `bytea` NOT NULL

**`people.deferment_event`**: id `uuid` NOT NULL, deferment_id `uuid` NOT NULL, action `text` NOT NULL, from_state `text`, to_state `text`, actor_id `uuid`, actor_office `text`, note `text`, at `timestamp with time zone` NOT NULL

**`people.deferment_reason`**: code `text` NOT NULL, label `text` NOT NULL, needs_document `boolean` NOT NULL, needs_words `boolean` NOT NULL, ord `integer` NOT NULL, active `boolean` NOT NULL

**`people.deferment_setting`**: id `integer` NOT NULL, max_sessions `numeric` NOT NULL, allow_extension `boolean` NOT NULL, reminder_days `integer` NOT NULL, overdue_after_days `integer` NOT NULL

**`people.document`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, kind `text` NOT NULL, detail `text`, source `text` NOT NULL, received_on `date`, status `text` NOT NULL, attachment `uuid`

**`people.enrolment`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, level `integer` NOT NULL, mode `text` NOT NULL, fee_category `text`, enrolled_at `timestamp with time zone` NOT NULL

**`people.faculty_list`**: id `uuid` NOT NULL, session `text` NOT NULL, faculty_code `text` NOT NULL, state `text` NOT NULL, confirmed_at `timestamp with time zone`, confirmed_by `uuid`

**`people.faculty_list_query`**: list_id `uuid` NOT NULL, student_id `uuid` NOT NULL, reason `text` NOT NULL, office `text` NOT NULL, withdrawn_at `timestamp with time zone`

**`people.matric_format`**: id `text` NOT NULL, university_code `text` NOT NULL, faculty_code `boolean` NOT NULL, programme_code `boolean` NOT NULL, year `boolean` NOT NULL, sequence `boolean` NOT NULL, sequence_digits `integer` NOT NULL, separator `text` NOT NULL, note `text`, updated_at `timestamp with time zone` NOT NULL

**`people.matric_history`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, matric_no `text` NOT NULL, series_code `text` NOT NULL, sequence `bigint` NOT NULL, components `jsonb` NOT NULL, run_id `uuid`, issued_at `timestamp with time zone` NOT NULL, issued_by `uuid`, actor_office `text`, reason `text`

**`people.matric_series`**: code `text` NOT NULL, name `text` NOT NULL, last_issued `bigint` NOT NULL, active `boolean` NOT NULL, note `text`, updated_at `timestamp with time zone` NOT NULL

**`people.matriculation_run`**: id `uuid` NOT NULL, ref `text` NOT NULL, session `text` NOT NULL, run_at `timestamp with time zone` NOT NULL, issued `integer` NOT NULL

**`people.search_log`**: id `uuid` NOT NULL, searched_at `timestamp with time zone` NOT NULL, term `text` NOT NULL, kind `text` NOT NULL, hits `integer` NOT NULL

**`people.status_change`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, from_status `text` NOT NULL, to_status `text` NOT NULL, instrument `text` NOT NULL, effective_on `date` NOT NULL, expires_on `date`, reason `text`

**`people.student`**: id `uuid` NOT NULL, person_id `uuid`, candidate_id `uuid`, admission_no `text`, matric_no `text`, jamb_reg_no `text`, surname `text` NOT NULL, other_names `text` NOT NULL, sex `text`, date_of_birth `date`, programme_code `text` NOT NULL, entry_mode `text` NOT NULL, entry_session `text` NOT NULL, entry_level `integer` NOT NULL, current_level `integer` NOT NULL, curriculum_version `text`, status `text` NOT NULL, matriculated_at `timestamp with time zone`, matriculation_run `uuid`, state_of_origin `text`, school_id `text`, curriculum_track `text`

**`people.student_contact`**: student_id `uuid` NOT NULL, phone `text`, email `text`, address `text`, updated_at `timestamp with time zone` NOT NULL

**`people.transfer_application`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, from_programme_code `text` NOT NULL, from_level `integer` NOT NULL, to_programme_code `text` NOT NULL, reason `text` NOT NULL, mode_of_entry `text` NOT NULL, utme_score `integer`, cgpa `numeric`, state `text` NOT NULL, applied_at `timestamp with time zone` NOT NULL, applied_by `uuid`, recommended_level `integer`, committee_note `text`, reviewed_at `timestamp with time zone`, reviewed_by `uuid`, senate_at `timestamp with time zone`, senate_by `uuid`, senate_note `text`, fee_reference `text`, effected_at `timestamp with time zone`, effected_by `uuid`, withdrawn_why `text`, from_dept_at `timestamp with time zone`, from_dept_by `uuid`, to_dept_at `timestamp with time zone`, to_dept_by `uuid`, reg_at `timestamp with time zone`, reg_by `uuid`, acad_at `timestamp with time zone`, acad_by `uuid`, decline_note `text`

**`platform.idempotency_key`**: key `text` NOT NULL, scope `text` NOT NULL, response `jsonb`, created_at `timestamp with time zone` NOT NULL

**`platform.mail_settings`**: id `boolean` NOT NULL, smtp_host `text`, smtp_port `integer`, smtp_encryption `text`, imap_host `text`, imap_port `integer`, imap_encryption `text`, pop_host `text`, pop_port `integer`, pop_encryption `text`, username `text`, from_address `text`, password_enc `bytea`, set_by `uuid`, set_at `timestamp with time zone`

**`platform.mail_settings_event`**: id `uuid` NOT NULL, kind `text` NOT NULL, by_person `uuid` NOT NULL, at `timestamp with time zone` NOT NULL

**`platform.notice`**: id `uuid` NOT NULL, channel `text` NOT NULL, recipient `text` NOT NULL, subject `text` NOT NULL, body `text` NOT NULL, about_kind `text`, about_id `uuid`, created_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, attempts `integer` NOT NULL, sent_at `timestamp with time zone`, provider_ref `text`, last_error `text`

**`platform.notice_attachment`**: id `uuid` NOT NULL, notice_id `uuid` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, content `bytea` NOT NULL, size_bytes `integer` NOT NULL, created_at `timestamp with time zone` NOT NULL

**`platform.number_series`**: kind `text` NOT NULL, scope `text` NOT NULL, session `text` NOT NULL, next_value `bigint` NOT NULL

**`platform.processed_event`**: consumer `text` NOT NULL, event_id `uuid` NOT NULL, processed_at `timestamp with time zone` NOT NULL

**`platform.request_document`**: id `uuid` NOT NULL, request_id `uuid` NOT NULL, filename `text` NOT NULL, content_type `text` NOT NULL, bytes `bigint` NOT NULL, uploaded_at `timestamp with time zone` NOT NULL, uploaded_by `uuid`

**`platform.request_document_blob`**: document_id `uuid` NOT NULL, content `bytea` NOT NULL

**`platform.service_request`**: id `uuid` NOT NULL, ref `text` NOT NULL, student_id `uuid` NOT NULL, office_code `text` NOT NULL, subject `text` NOT NULL, detail `text`, raised_at `timestamp with time zone` NOT NULL, state `text` NOT NULL, answer `text`, answered_at `timestamp with time zone`, answered_by `uuid`

**`platform.session`**: id `bytea` NOT NULL, person_id `uuid` NOT NULL, active_office `text` NOT NULL, issued_at `timestamp with time zone` NOT NULL, last_seen_at `timestamp with time zone` NOT NULL, absolute_end `timestamp with time zone` NOT NULL, ended_at `timestamp with time zone`, ended_reason `text`

**`platform.sms_settings`**: id `boolean` NOT NULL, provider `text` NOT NULL, username `text`, sender `text`, api_key_enc `bytea`, enabled `boolean` NOT NULL, set_by `uuid`, set_at `timestamp with time zone`

**`platform.sms_settings_event`**: id `uuid` NOT NULL, kind `text` NOT NULL, by_person `uuid` NOT NULL, at `timestamp with time zone` NOT NULL

**`policy.academic_session`**: id `uuid` NOT NULL, name `text` NOT NULL, starts_on `date` NOT NULL, ends_on `date` NOT NULL, state `text` NOT NULL, senate_minute `text`, semesters `integer` NOT NULL

**`policy.classification_band`**: version_id `uuid` NOT NULL, class `text` NOT NULL, low `numeric` NOT NULL, high `numeric` NOT NULL, ord `integer` NOT NULL

**`policy.clearance_rule`**: version_id `uuid` NOT NULL, purpose `text` NOT NULL, releases_at `text` NOT NULL

**`policy.clearance_scheme`**: version_id `uuid` NOT NULL, arrears_block_all `boolean` NOT NULL

**`policy.curriculum_track`**: code `text` NOT NULL, framework `text` NOT NULL, label `text` NOT NULL, matric_prefix `text`, entry_from `text`, entry_to `text`, expected_end_session `text`, ord `integer` NOT NULL, note `text`

**`policy.grade_band`**: version_id `uuid` NOT NULL, grade `text` NOT NULL, low `integer` NOT NULL, high `integer` NOT NULL, points `numeric` NOT NULL

**`policy.level_limit`**: level `integer` NOT NULL, applies_to `text` NOT NULL, min_units `integer` NOT NULL, max_units `integer` NOT NULL, carryover_counts `boolean` NOT NULL, instrument `text`, probation_max_units `integer`

**`policy.semester`**: id `uuid` NOT NULL, session `text` NOT NULL, number `integer` NOT NULL, lectures_from `date`, lectures_to `date`, registration_opens `date`, registration_closes `date`, late_registration_closes `date`, exams_from `date`, exams_to `date`, results_due `date`, query_window `text`, state `text` NOT NULL

**`policy.version`**: id `uuid` NOT NULL, kind `text` NOT NULL, scope `text` NOT NULL, validity `daterange` NOT NULL, instrument `text` NOT NULL, decided_by `text` NOT NULL, recorded_at `timestamp with time zone` NOT NULL

**`records.graduand`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, cgpa `numeric`, award `text` NOT NULL, unmet `text`, senate_state `text` NOT NULL, senate_minute `text`

**`ref.biodata_field`**: field `text` NOT NULL, section `text` NOT NULL, label `text` NOT NULL, tier `text` NOT NULL, hint `text`, wide `boolean` NOT NULL, ord `integer` NOT NULL

**`ref.clearance_purpose`**: code `text` NOT NULL, label `text` NOT NULL, note `text`

**`ref.college`**: code `text` NOT NULL, name `text` NOT NULL, system `text`, url `text`

**`ref.department`**: code `text` NOT NULL, name `text` NOT NULL, faculty_code `text` NOT NULL, ended_on `date`

**`ref.faculty`**: code `text` NOT NULL, name `text` NOT NULL, college_code `text`, matric_code `text`, matric_series `text`

**`ref.fee_group`**: code `text` NOT NULL, name `text` NOT NULL, applies_category `text`, ord `integer` NOT NULL

**`ref.fee_item`**: code `text` NOT NULL, name `text` NOT NULL, ord `integer` NOT NULL

**`ref.jamb_alias`**: code `text` NOT NULL, jamb_name `text` NOT NULL

**`ref.jamb_alias_name`**: jamb_key `text` NOT NULL, jamb_name `text` NOT NULL, code `text` NOT NULL, added_at `timestamp with time zone` NOT NULL

**`ref.office`**: code `text` NOT NULL, label `text` NOT NULL, scope_kind `text` NOT NULL

**`ref.programme`**: code `text` NOT NULL, name `text` NOT NULL, dept_code `text` NOT NULL, faculty_code `text` NOT NULL, min_score `integer` NOT NULL, archived `boolean` NOT NULL, category `text` NOT NULL, pg_award `text`, pg_research `boolean` NOT NULL, matric_code `text`, matric_uses_code `boolean` NOT NULL, matric_faculty_code `text`, matric_series `text`

**`ref.unit`**: code `text` NOT NULL, name `text` NOT NULL, kind `text` NOT NULL, parent_code `text`, college_code `text`, ended_on `date`

**`ref.unit_alias`**: alias_key `text` NOT NULL, alias `text` NOT NULL, unit_code `text`, dept_code `text`, faculty_code `text`

**`registration.attendance`**: id `uuid` NOT NULL, offering_id `uuid` NOT NULL, held_on `date` NOT NULL, student_id `uuid` NOT NULL, present `boolean` NOT NULL, recorded_by `uuid` NOT NULL, recorded_at `timestamp with time zone` NOT NULL

**`registration.course_registration`**: id `uuid` NOT NULL, student_id `uuid` NOT NULL, session `text` NOT NULL, semester `integer` NOT NULL, level `integer` NOT NULL, status `text` NOT NULL, submitted_at `timestamp with time zone`, approved_at `timestamp with time zone`, approved_by `uuid`, returned_comment `text`

**`registration.entry`**: registration_id `uuid` NOT NULL, offering_id `uuid` NOT NULL, units `integer` NOT NULL, entry_type `text` NOT NULL, status `text` NOT NULL

**`reports.catalogue`**: slug `text` NOT NULL, title `text` NOT NULL, owner_office `text` NOT NULL, owner_label `text` NOT NULL, frequency `text` NOT NULL, purpose `text` NOT NULL, due_day `integer`, due_dates `ARRAY`, sort_order `integer` NOT NULL, active `boolean` NOT NULL, tracked_from `date` NOT NULL

**`reports.snapshot`**: id `uuid` NOT NULL, report `text` NOT NULL, title `text` NOT NULL, subtitle `text`, period `text` NOT NULL, parameters `jsonb` NOT NULL, due_on `date`, headers `jsonb` NOT NULL, rows `jsonb` NOT NULL, totals `jsonb`, row_count `integer` NOT NULL, note `text`, taken_at `timestamp with time zone` NOT NULL, taken_by `uuid`, taken_office `text`, verification_code `text` NOT NULL, filed_to `text`, filed_at `timestamp with time zone`, filed_by `uuid`, filed_note `text`
