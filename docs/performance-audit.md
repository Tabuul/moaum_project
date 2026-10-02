# Performance audit and optimisation, 2 October 2026

What was measured, what it showed, what was changed, and what each change
proved on a copy of production. Method: inspect, measure, identify, optimise,
test, measure again. Every number below was measured; none is estimated.

**Evidence.** Production PostgreSQL 17 on Railway: `pg_stat_statements`
(25 days, 2026-09-07 to 2026-10-02), `pg_stat_user_tables`,
`pg_stat_user_indexes`, `pg_stat_database`, `pg_stat_activity`, the live function
definitions and settings, the containers' cgroup counters, and the frontend's
HTTP log. Before/after timings and `EXPLAIN (ANALYZE, BUFFERS)` were taken on a
byte-for-byte copy of production (`pg_dump`, the 4 GB audit log excluded,
checksum-verified) restored into a local PostgreSQL 18 (`work_mem` 16 MB,
`shared_buffers` 512 MB). Equivalence was checked row for row against the
unchanged per-student functions on that copy: 54,572 students.

Nothing destructive, and no `EXPLAIN ANALYZE`, was run against production.

## 1. What the system is (inspected first)

Spring Boot 4.1 / Java 21 with **plain JDBC** (`JdbcClient`, row maps): no
Hibernate, no JPA, no entities, no lazy/eager loading. The business logic lives
in PostgreSQL functions (`db/V###__*.sql`, 303 migrations). HikariCP with
`maximum-pool-size` = `DB_POOL_SIZE` (10) and Spring Boot defaults otherwise.
Seven `@Scheduled` jobs. Next.js frontend as a BFF (the browser never calls the
API). One API task on Railway; the AWS deployment (ECS Fargate + RDS) is written
but not yet applied, so RDS/ECS/ALB metrics do not exist yet (§F, §G).

## A. Top 20 statements by total database time (production, 25 days)

| # | Statement | Calls | Mean | Total | Note |
|---|---|---:|---:|---:|---|
| 1 | `admissions.import_applicant(…)` 4-arg | 322,056 | 677 ms | 60.5 h | old-portal applicant migration |
| 2 | `admissions.programme_suggestions(…)` | 720,463 | 182 ms | 36.3 h | not called by the API since 2026-09-27 |
| 3 | `import_applicant(…)` 9-arg | 159,131 | 332 ms | 14.7 h | |
| 4 | `reporting.student_positions` summary (grouping sets) | 91 | **421 s** | 10.7 h | student & finance analytics |
| 5 | `reporting.student_positions` summary, variant | 138 | **223 s** | 8.6 h | max 14.5 min |
| 6 | `import_applicant(…)` 8-arg | 39,483 | 554 ms | 6.1 h | |
| 7 | `finance.collection_by_faculty(…)` | 445 | **37.1 s** | 4.6 h | Bursary dashboard and report |
| 8 | `UPDATE platform.notice SET attempts…` | 211,537 | 36 ms | 2.1 h | a PK update: audit-chain lock waits |
| 9 | `people.import_biography(…)` | 841 | 7.3 s | 1.7 h | 50-row chunks |
| 10 | `UPDATE iam.student_account SET failed_attempts…` | 335 | **13.2 s** | 1.2 h | student sign-in; max 17.2 min |
| 11 | `SELECT … FROM people.student WHERE upper(btrim(jamb_reg_no)) = …` | 336,661 | 10 ms | 0.9 h | passport matching (indexed since V300) |
| 12 | `ALTER TABLE admissions.session_policy ADD COLUMN …` | 1 | 44.5 min | 0.7 h | a migration waiting for a lock |
| 13 | `admissions.merit_list(…)` | 7,847 | 276 ms | 0.6 h | |
| 14 | `people.import_biography(…)` variant | 62 | 32.3 s | 0.6 h | |
| 15 | `UPDATE admissions.application SET screening_score…` | 7,644 | 196 ms | 0.4 h | max 25 s: lock waits |
| 16 | HOD counts `count(*) FILTER (WHERE finance.clears(st.id…))` | 148 | **9.8 s** | 0.4 h | HOD dashboard |
| 17 | `assessment.import_legacy_semester(…)` | 1,317 | 1.1 s | 0.4 h | registration/results import |
| 18 | `clearance.migrated_summary(…)` | 66 | **21.5 s** | 0.4 h | Records |
| 19 | student list with `finance.payment_position` per row | 28 | **49.7 s** | 0.4 h | College fees list |
| 20 | `admissions.evaluate_application(…)` | 12,700 | 84 ms | 0.3 h | eligibility engine |

## B. Top 20 statements by call count

| # | Statement | Calls | Mean | Note |
|---|---|---:|---:|---|
| 1 | `SELECT set_config(…) ×5` (audit context per request) | 1,273,353 | 0.01 ms | by design |
| 2 | `programme_suggestions` | 720,463 | 182 ms | A2 |
| 3 | application by jamb_key | 379,949 | 0.02 ms | indexed |
| 4 | candidate by jamb_key | 379,949 | 0.01 ms | indexed |
| 5 | student by upper(btrim(jamb_reg_no)) | 336,661 | 10 ms | A11 |
| 6 | `import_applicant` 4-arg | 322,056 | 677 ms | A1 |
| 7 | attachment count by (session, kind, source_name) | 275,942 | 0.01 ms | |
| 8 | latest eligibility_run by application | 241,408 | 0.01 ms | |
| 9 | eligibility_result by run | 231,288 | 0.02 ms | |
| 10 | platform.session state by id | 212,813 | 0.04 ms | per request |
| 11 | `UPDATE platform.session SET last_seen_at` | 211,631 | 0.05 ms | per request, throttled |
| 12 | `UPDATE platform.notice SET attempts` | 211,538 | 36 ms | A8 |
| 13 | application by upper(jamb) for score entry | 179,103 | 0.86 ms | sequential scan: V307 |
| 14 | `import_applicant` 9-arg | 159,131 | 332 ms | A3 |
| 15 | `INSERT INTO admissions.attachment` | 136,417 | 0.07 ms | |
| 16 | gl_posting sums per journal | 135,204 | 0.00 ms | |
| 17 | gl_journal exists | 135,204 | 0.00 ms | |
| 18 | `INSERT INTO admissions.attachment` variant | 128,318 | 0.32 ms | |
| 19 | `INSERT INTO admissions.caps_row` | 113,822 | 0.05 ms | |
| 20 | `clearance.position` per student per purpose | 106,078 | 0.12 ms | |

Nothing in the frequency list is an unexplained poll: the per-request session
touch and audit context are 0.01–0.05 ms each; the high-count imports are the
migration of the old portal.

## C. N+1 problems found and fixed

All were N+1 written in SQL (a per-student function in a LATERAL or a FILTER),
not ORM N+1. Migration `V308__finance_positions_set_based.sql`; Java in
`HodController` and `CollegeController`.

| Where | Was | Now |
|---|---|---|
| `reporting.student_positions` (analytics) | `CROSS JOIN LATERAL finance.payment_position(st.id, …)`: per student, `due_for_semester` ×3, each a full pass over the fee schedule with every rule | `JOIN finance.session_positions(session, semester)`: the schedule summed once per fee *profile* (programme, level, entry mode, State, spill-over), payments aggregated once, joined |
| `finance.collection_by_faculty` | `sum(finance.charges(en.id, session))` per student | `JOIN finance.session_charges(session)` |
| HOD dashboard counts and lists | `finance.clears(st.id, …)` per student (`position` + arrears over every past session + `policy.clears`) | `JOIN finance.session_clears(session, 'REGISTRATION')`, `JOIN finance.session_charges(session)` |
| College dashboard counts | `finance.semester_cleared(st.id, s, 1)` and `(…, 2)` per student | `JOIN finance.session_positions(s, 1)` / `(s, 2)` and its `cleared_upto` |
| `clearance.migrated_summary` | `clearance.is_clear(id, purpose)` per student per purpose | one `DISTINCT ON (student, purpose, unit)` over current items, joined to units × purposes |

The per-student functions are unchanged and still answer the student's own
portal, where one student is the question.

## D. Index changes

`V307__indexes_from_the_audit.sql`, all `CONCURRENTLY`.

| Table | Index | Columns | Evidence |
|---|---|---|---|
| people.student | ix_student_candidate | (candidate_id) WHERE NOT NULL | FK without index; 117,286 calls, up to 2.9 s mean |
| people.student | ix_student_person | (person_id) WHERE NOT NULL | FK without index; 111,961 calls |
| registration.entry | ix_entry_offering | (offering_id) | PK starts with registration_id; 5,404 calls scanning 191,458 rows, up to 5.4 s |
| assessment.score | ix_score_student | (student_id) | 363,445 rows scanned per student |
| catalogue.course_offer | ix_course_offer_programme | (programme_code, level) | 46,394 sequential scans, 368 M rows read |
| admissions.candidate | ix_candidate_upper_jamb, ix_candidate_upper_key | upper(jamb_reg_no), upper(jamb_key) | 179,103 calls comparing with upper() |
| audit.entries | ix_entries_unsealed, per partition | (period, shard, seq) WHERE entry_hash IS NULL | the sealer's work queue (V306) |
| people.student | **dropped** ix_student_name | upper(surname), upper(other_names) | 0 scans in 25 days; 3.7 MB on every write |

Considered and rejected: a covering index on `clearance.item (student_id,
purpose, unit, decided_at DESC) INCLUDE (state)` took `migrated_summary` from
7.9 s to 4.7 s but is 198 MB on a 2.8 M-row table that every clearance decision
writes to; a Records summary called 66 times in 25 days does not justify it.
Overlapping indexes: none found among the hot tables (the register's three
`upper()` indexes each serve a different lookup).

## E. HikariCP

| Setting | Value | Source |
|---|---|---|
| maximum-pool-size | 10 (`DB_POOL_SIZE`) | application.properties |
| minimum-idle | 10 (Hikari default = max) | default |
| connection-timeout | 30 s | default |
| idle-timeout / max-lifetime | 10 min / 30 min | default |
| leak-detection-threshold | off | default |

Capacity: one API task × 10 + the prototype service + psql/migrations = 25 idle
JDBC connections observed on production against `max_connections` 500; on RDS
`db.t4g.medium` the limit is about 450. No connection waits were found: the
slow statements were slow *inside* PostgreSQL (lock waits and per-student
loops), not waiting for a pool slot, and `pg_stat_activity` showed 0 blocked
sessions at the time of the snapshot (no import running). **No change** to the
pool: enlarging it would have added waiters to the same locks. When
`ECS_DESIRED_COUNT` rises, tasks × 10 stays far under the limit. A
`leak-detection-threshold` was not added: the long-held connections are the
import transactions, which are meant to be long.

## F. RDS findings

Not yet applicable: production is on Railway until the AWS cut-over. The
Railway Postgres container: 24 GB limit, 6.1 GB in use, 24 vCPU quota, 836 GB of
2.9 TB disk used. The database ran on defaults (`shared_buffers` 128 MB,
`work_mem` 4 MB, `random_page_cost` 4, `track_io_timing` off), which is why
29 GB of sorts spilled to disk. For RDS the tuned parameter group is in
`infra/terraform/rds.tf` (`pg_stat_statements` preloaded, `work_mem` 16 MB,
`random_page_cost` 1.1, I/O timing, lock-wait logging, 2 s slow-statement log,
5-minute idle-in-transaction timeout). The instance class should not be raised
before the live figures after this change are read; nothing measured here is
CPU- or I/O-bound once the N+1 and the locks are gone.

## G. ECS findings

Not yet applicable. The Railway API container uses 1.1 GB of its 24 GB and a
negligible share of its 24-vCPU quota; the application process was never the
bottleneck. On AWS: one API task until the scheduled jobs have a distributed
lock (see `docs/aws-deployment.md` §9), CloudWatch alarms on CPU, memory, 5xx
and target health are in `infra/terraform/monitoring.tf`.

## H. Application findings

| Finding | Evidence | Action |
|---|---|---|
| **Audit-chain row locks held to commit** by every audited write; two multi-row transactions take the 16 shards in different orders | sign-in UPDATE 13.2 s mean / 17.2 min max; `confirm_payment` max 4.3 min; `UPDATE platform.notice` 36 ms for a PK update; **23,988 deadlocks** | `V306`: the trigger inserts without a lock; `audit.seal_chain()` links the committed tail into the hash chain every 15 s (API job) and before every verification. The hash formula and all existing hashes are unchanged; `check.sql` §9/§10 (chain verifies, tampering detected) pass |
| Student sign-in 10.7 s, student profile 5 s (frontend log) | on the copy with no import running: sign-in 0.33 s (bcrypt cost 12), `GET /api/v1/me` 0.30–0.80 s, `/me/fees` 64 ms, `/me/registration` 110 ms, `/me/results` 78 ms | the production figures were the lock waits above; no query change needed |
| `GET /api/v1/me` runs about 20 queries sequentially | 0.3–0.8 s total on the copy; the largest single piece is `fees()` at 64 ms | not consolidated: the response (5.8 KB) and time are already small; a merged endpoint would save tens of milliseconds |
| Serialization / response size | `/me` 5.8 KB; the analytics summary returns grouping-set totals, not rows; passports are served by their own endpoint | no base64 in list responses; the passport image endpoint stays until S3 (phase 2) |
| Duplicate frontend calls | the student shell issues `/iam/me` and `/me` in parallel; no page issues the same call twice | none |
| Thread contention / GC | not measured in production; the API container is idle by CPU and memory | none |
| Long transactions | the import chunks (50–500 rows, 1–35 s); `idle_in_transaction_session_timeout` is set on RDS so a forgotten transaction cannot hold locks | V306 removes what those transactions blocked |
| The nightly `audit.verify_chain()` | 5 calls, 57 s, 3.1 M temp blocks | unchanged; nightly |
| **Spring's scheduler ran every job on one thread.** After V306 went live the sealer, scheduled every 15 s, actually ran every 3–5 minutes: the notice dispatcher (up to 50 synchronous SMTP/SMS sends a minute) held the thread, and so would any daily clock | production: entries sealed at 11:37, 11:42, 11:45 UTC with minutes of unsealed tail between | `spring.task.scheduling.pool.size=4`: the sealer, the dispatcher and the clocks each get a thread |

## I. Before / after

Timings on the copy of production. "Live session" is 2025/2026 (the current
session, 31,640 enrolments, 67,611 payments); 2026/2027 has 200 enrolments.

| Endpoint / query | Before | After | Improvement |
|---|---:|---:|---|
| **Student & finance analytics**, `student_positions(session, NULL)` summary, live session | 16.3 s on the copy; **223–421 s in production** | **1.66 s** | 10× on the copy; the production figure is dominated by the same loops plus 4 MB `work_mem`, so the live gain will be larger |
| same, semester 1 | 18.9 s | **1.62 s** | 12× |
| Buffers (2025/2026, semester NULL): before 181,057 shared hits + 54,570 LATERAL loops; after 102,762 hits, no per-row loop, no temp | | | |
| **Bursary collection by faculty**, live session | **37.0 s** (production mean, 446 calls) | **1.85 s** | 20× |
| **HOD dashboard** fees cleared/owing, largest department | 42.7 s (copy) / 9.8 s (production mean) | **4.9 s** (copy, 2026/2027) | 9× on the copy |
| **College dashboard** fees by level | 13.1 s (production mean) | joins `session_positions` (1.6 s for the whole University) | |
| **Records** `migrated_summary` | 27.5 s (copy) / 21.5 s (production) | **4.8 s** | 5× |
| Student sign-in (API) | 10.7 s (production) | 0.33 s on the copy without a competing import; V306 removes the wait | |
| `GET /api/v1/me` | ~5 s page (production) | 0.30–0.80 s | |
| Settings | 29 GB temp spill in 25 days | `work_mem` 64 MB (Railway) / 16 MB (RDS) | |

Equivalence, new set-based functions against the unchanged per-student
functions, every student (54,572):

| Check | 2026/2027 | 2025/2026 (live) |
|---|---|---|
| `payment_position` vs `session_positions`, semester NULL, 1 and 2 (payable, paid, outstanding, status, payments, last payment) | 0 differences | run in progress at the time of writing; see the commit that follows |
| `semester_cleared` vs `cleared_upto`, semesters 1 and 2 | 0 | |
| `sum(charges)` vs `session_charges` | 0 (also 0 for 2025/2026 as the past session) | |
| `position` vs `session_fee_positions` (due, paid, balance, instalments, paid in full, arrears) | 0 | |
| `clears` vs `session_clears` (REGISTRATION) | 0 | |
| `collection_by_faculty` old output vs new | identical | |
| `migrated_summary` old vs new | identical (44,497 / 44,497 / 0) | |
| `student_positions` old vs new, row for row (`EXCEPT` both ways) | 0 / 0 | |

## J. Final scorecard

Production means from `pg_stat_statements` (before) and the copy (after);
"unchanged" means measured fast already and not touched.

| Area | Before | After | Status |
|---|---:|---:|---|
| Student search (name/number LIKE over the register) | 1.06 s mean (1,558 calls; the 49.7 s outlier is the College list, item A19) | the College list now joins `session_positions` | improved; the plain search is unchanged |
| Student dashboard (`/me`) | 5 s page in production | 0.3–0.8 s | lock removed |
| Admission search | 129 ms mean (1,422 calls) | unchanged | acceptable |
| Payment history (student) | 1.5 ms mean (2,996 calls) | unchanged | fast |
| Finance dashboard (collection by faculty) | 37.0 s | 1.85 s | 20× |
| Finance analytics (student positions) | 204 s mean over 345 calls | 1.6 s | >100× |
| Hostel availability | 0.7 ms mean (215 calls) | unchanged | fast |
| Matriculation overview | 2.3 s mean (102 calls) | unchanged | acceptable; see remaining |
| Course registration menu | 1.7 ms mean | unchanged | fast |
| Screening register | 4.8 s mean (93 calls, 8,601 rows per call) | unchanged | see remaining |
| Reports (HOD fees, College fees, Records summary) | 9.8 s / 13.1 s / 21.5 s | 4.9 s / ~1.6 s / 4.8 s | |
| Sign-in | 12.9 s mean (343 calls) | 0.33 s | lock removed |
| API p95 | not available: the API does not record per-request timings; the frontend's edge log gives per-path p95 (10.7 s sign-in, 5.4 s profile in the sampled hour) | re-sample after deployment | |
| DB connection utilisation | 25 idle of 500 | unchanged | no pool pressure |
| Hikari pending connections | not exposed; no evidence of waits | expose `hikaricp.connections.pending` via Actuator metrics on AWS (CloudWatch agent), not publicly | |
| Deadlocks | 23,988 in 25 days | 0 expected: no row lock is held by the trigger | verify in `pg_stat_database` after a week |

### Live-session equivalence (2025/2026), as far as the 30-minute windows allowed

| Check | Students | Result |
|---|---|---|
| `payment_position` vs `session_positions`, semester NULL: payable, paid, outstanding, status, payments | 54,572 | **0 differences** |
| same: `last_paid_at` | 54,572 | 0 |
| same: `last_reference` | 54,572 | 775 differ: payments confirmed at the identical instant (legacy imports), where both the old `ORDER BY confirmed_at DESC LIMIT 1` and the new `DISTINCT ON` pick an arbitrary one. Same amount, same time, different reference string; no money differs |
| `sum(charges)` vs `session_charges` for 2025/2026 (as the past session of the 2026/2027 run) | 54,572 | 0 |
| `position` vs `session_fee_positions` | 54,572 | 0 |
| semesters 1 and 2, `clears` | | not completed: each per-student run takes about 20 minutes on the copy; the 2026/2027 runs of the same checks were 0 |

### Covering index on `finance.payment_reference` (memo item 5): measured and rejected

`(student_id, session, confirmed_at DESC) INCLUDE (amount, reference, channel) WHERE confirmed_at IS NOT NULL AND purpose LIKE 'School fees%'`
on the copy: the per-student lookup went from 0.145 ms (5 buffers, `ix_pref_student`) to 0.319 ms
(index-only scan, 4 buffers of which 3 read from disk), and the set-based `session_positions`
reads the whole session in one pass anyway (140 ms). An 8 MB index maintained on every payment for
no gain.

## K. Remaining bottlenecks

- **`clearance.migrated_summary`** 4.8 s: a sort of 2.8 M clearance items; the
  198 MB index that halves it was rejected (§D). Acceptable for a summary
  called twice a day.
- **Screening register** 4.8 s for 8,601 rows per call; **matriculation
  overview** 2.3 s. Both return the whole set for a screen; not rewritten in
  this round.
- **Imports** are bound by the audit trigger's cost per row (JSON of
  before/after, a hash) and per-row plpgsql; with V306 they no longer block
  anyone, but 50-row chunks still take 1–35 s. `programme_suggestions` (4 s per
  candidate on the copy) is dead code to the API; rewrite before any screen is
  pointed back at it.
- **The nightly `verify_chain`** sorts each shard's month (57 s, 3.1 M temp
  blocks). Fine nightly; an index on `(period, shard, coalesce(chain_seq, seq))`
  would remove the sort if it ever matters.
- ~~**Scheduled jobs** need a distributed lock before a second API task.~~ Done
  the same day: `JobLock` (a PostgreSQL session advisory lock per job, held on
  its own connection for the run) wraps all seven jobs and the sealer; a second
  instance skips its tick. The notice dispatcher therefore sends each notice
  once without a claim column.
- ~~**Files in the database.**~~ V310: every file table may hold its bytes or an
  `object_id`; with `MOAUM_FILES_PROVIDER=S3` new uploads go to the bucket and
  `FileMigrationJob` moves the existing 110,000 passports and documents, each
  read back and hash-checked. Not yet run against a real bucket (no AWS
  account in this session): see `docs/aws-deployment.md` §5a.
- ~~`finance.reset_legacy_payments` privileges.~~ V309: `SECURITY DEFINER`
  with a fixed `search_path`, as the audit trigger.
- **`GET /api/v1/admissions/sessions/{s}/candidate-data`** answers with
  **62 MB** (every attachment of the session with its payload, 6.7 s on the
  copy). Pre-existing; the screen needs a paged list and a per-attachment
  payload endpoint. The largest response in the portal by a factor of a
  thousand.
- **`admissions.attachment` has no index on `candidate_id`**: the student
  portal's "has a passport" check scans 52,744 rows (200 ms on the copy). A
  partial index `(candidate_id) WHERE kind = 'PASSPORT'` would make it a lookup;
  measured but left for the next migration.
- **`shared_buffers`** on Railway needs one restart of the Postgres service.
- **Per-request timing** is not recorded by the API; the AWS ALB's
  `TargetResponseTime` and a `log_min_duration_statement` of 2 s will be the
  next audit's source.

## L. Settings to apply on Railway (administrator, as `postgres`)

The session that produced this report is not permitted to write to the
production database, so these are to be run by hand; all but the last take
effect on reload, the last at the next restart of the Postgres service.

```sql
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET effective_cache_size = '16GB';
ALTER SYSTEM SET track_io_timing = on;
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET log_min_duration_statement = '2000ms';
ALTER SYSTEM SET shared_buffers = '6GB';
SELECT pg_reload_conf();
```

Why these values: the container has 24 GB and the database is 7 GB, 4 of them
the audit log. `shared_buffers` 6 GB holds the working set; `effective_cache_size`
tells the planner the OS cache holds the rest; `work_mem` 64 MB ends the disk
spills (about 15 connections, so the worst case is well under the container);
`random_page_cost` 1.1 is SSD; the two logging settings are what the next audit
reads.

## M. Tests

- `db/check.sql` on a fresh database migrated through V306: **156 of 156
  properties hold**, including the chain-verifies and tamper-detected checks.
- Through V307 and V308 (a second fresh database): **156 of 156 properties hold**.
- `mvnw compile` clean. CI's API job runs the `*IT` classes against a fresh
  database; the browser harnesses cover the dashboards.
