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
  **V348 (7 Oct 2026):** Railway runs with `MOAUM_FILES_PROVIDER=S3` and
  `MOAUM_FILES_MIGRATE=true`. The job's orphan sweep judged an object unused
  when none of the tables in its own hand-kept list pointed at it; the JUPEB
  documents (V339) were not on the list and had no foreign key, so all eleven
  JUPEB documents and passports were removed from the bucket an hour after
  upload. The sweep now asks `information_schema` for every `uuid` column named
  `object_id`; every such column references `platform.file_object` (check.sql
  property 193), so the database itself refuses to forget an object a row still
  shows. The lost documents are recorded in `jupeb.document_lost` (with the
  object id, from which the bucket key `jupeb/document/<application>/<object>`
  is rebuilt, should the bucket keep versions) and marked for re-upload. A new
  table that stores files must declare `object_id uuid REFERENCES
  platform.file_object(id)`.
- ~~`finance.reset_legacy_payments` privileges.~~ V309: `SECURITY DEFINER`
  with a fixed `search_path`, as the audit trigger.
- ~~**`GET /api/v1/admissions/sessions/{s}/candidate-data`** answered with
  62 MB.~~ Fixed: the screen used the 79,434-row attachment list only to count
  files per kind (all, matched, waiting, unreadable), so the endpoint now
  returns those four counts per kind instead of the rows (the 40 MB of O'Level
  sittings were never read). On the copy: **62.3 MB / 6.7 s → 3.4 MB / 1.8 s**.
  What remains is the 12,648-candidate list the screen's matcher needs; a
  server-side matcher would remove that too.
- ~~**The student portal's passport lookup scanned the attachment table.**~~
  V311: the lookup is `candidate_id = … OR jamb_key = …`; `ix_att_candidate`
  served the first branch and nothing the second, so every student dashboard
  scanned 52,744 passport rows (parallel seq scan, ~200 ms on the copy). A 1.6 MB
  partial index `(jamb_key) WHERE kind = 'PASSPORT'` turns it into a BitmapOr of
  two index scans, under a millisecond.
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

## N. The student profile statement timeout (13 October 2026)

`/api/v1/me` (the student dashboard, profile and fees page) began failing with
*canceling statement due to statement timeout*. Measured on a live-shaped copy
(a `pg_dump` taken inside the API container and restored on the scratch
cluster: 54,573 students, 538,147 registration entries, 367,445 scores on 1,042
sheets, 314,325 payment references):

- every results function the profile calls — `assessment.student_results`,
  `student_gpa`, `student_standing`, `registration.carryovers`,
  `records.student_graduation`, `finance.position` — finishes in under 200 ms
  for the heaviest student on the register (70 entries, sheets of up to 11,883
  scores);
- the student's payment references (`StudentPortalRepository.references`,
  also `reference`) took **70–84 s**, and 0.2 s without the V409 ledger join.

The cause: `LEFT JOIN reporting.payments v ON v.payment_id = pr.id`. The ledger
is a `UNION ALL` of four sources whose branches each join five tables and call
`finance.categorise`, `finance.programme_type_for` and `finance.payment_owner`
per row. PostgreSQL flattens a `UNION ALL` member only when it holds a single
relation, so a join condition never reaches the branches: the whole ledger was
classified on every dashboard load. A *constant* restriction is pushed into
every branch, so the fix reads the ledger for the one student first —
`(SELECT x.* FROM reporting.payments x WHERE x.source = 'STUDENT' AND
x.student_id = :s) v` joined by payment — and runs in 9–170 ms, generic plan
included (a `LATERAL` subquery is de-correlated into the same join and
`= ANY (subselect)` is not pushed either; both were measured and rejected).

Still open: the ledger itself costs about 70 s to classify in full on this data,
so every Bursary analytics screen that reads `reporting.payments` whole
(`FinancialAnalyticsController`) carries the same cost at scale. The remedy is a
classification computed once per payment (a table kept by trigger on
confirmation, or a materialized view refreshed on confirmation), which this
change does not attempt.

## O. The slowest screens, crawled and fixed (18 October 2026, V537)

**Method.** Every menu page (295 loads: each page as the widest office whose menu has it, and every office's dashboard) was
opened through a production build of the frontend against the API on the live-shaped copy (54,573 students, 13,200
applications), with `log_min_duration_statement = 1000`; the pages over 2 s were opened again, twice each, with nothing else
running, and each page's slow statements were matched to it by time. Before/after below are the second load (the warm one).

**Finding.** Each of the worst pages spent its time in a function called once for every row of a large set, or in a set
planned into another so that it ran once per row. The cure was to remove the per-row calls: a per-programme CTE, joins,
`MATERIALIZED` parts.

**Correction (V541).** The page times below were taken through the API, whose pooled connections had each run many statements,
on PostgreSQL 18 on the Windows development machine. There a server process that has run two or three heavy statements runs
*everything* about four times slower (every node of an unchanged plan; a new connection is fast again), so these "before"
figures are overstated for the live portal, which runs PostgreSQL 17 on Linux. The same readers timed on fresh connections
(three each, median) — the fair comparison:

| Reader | Before | After |
|---|---:|---:|
| College payment report (each student's position) | 14.5 s | 0.75 s |
| `admissions.pipeline_stats` | 8.7 s | 0.49 s |
| Post-UTME desk's three counts | 7.9 s | 0.11 s |
| `finance.collection_by_faculty` | 2.7 s | 0.72 s |
| `finance.session_positions` | 1.7 s | 0.80 s |
| `admissions.status_checking_rows` | 1.1 s | 0.21 s |
| the programmes' JAMB and candidate counts | 1.7 s | 0.03 s |

The second effect is real on PostgreSQL 18 on any system but not on 17: 18 caches the plans of a SQL function that is not
inlined into its caller and may use a generic plan from its sixth call (`admissions.olevel_scores` given an array built by a
subquery: 0.45 s five times, then 19 s). The functions of V537 and V541 take only constants or parameters, so they are inlined.
The tools and the method are in `api/scripts/perf`.

The page timings as first measured (pooled connections on the development machine):

| Page | Before | After | What it was |
|---|---:|---:|---|
| /admissions (Registrar) | 37.7 s | 4.2 s | `admissions.pipeline_stats`: `finance.position` for each admitted student; the programme counts as 456 correlated subqueries |
| /admissions/putme | 37.1 s | 0.9 s | `admissions.putme_candidates`: a plpgsql eligibility for each of 12,649 applicants, read four times |
| /college/payments | 29.0 s | 4.3 s | `finance.payment_position` for each of the College's 8,193 students |
| /ict/admission-checking | 18.5 s | 2.2 s | `admissions.status_checking_rows`: a programme-name lookup for each applicant, read five times |
| Bursar's dashboard, Registrar's overview, /audit/revenue | 16–18 s | 3.9–4.3 s | `finance.collection_by_faculty` → `session_charges`: the registration windows re-read for every student; `final_level` twice a student |
| Registrar's dashboard | 7.0 s | 1.5 s | the programme counts |
| /admissions/candidate-data | 11.9 s | 2.7 s | (reads the restated functions) |
| /stats (first load) | 15.1 s | — | `reporting.student_positions` → `finance.session_positions` 10 s → 1.4–2.3 s |

Every restated function was compared row by row with the one it replaces on the copy (`EXCEPT ALL` both ways): fee profiles
54,573 rows, session charges 109,146 rows (two sessions), Post-UTME candidates 13,200 rows (three sessions), status checking
12,649 rows, the pipeline figures and the collection by faculty — all the same. `finance.session_positions` was compared with
`finance.payment_position` for 6,000 students × two sessions × three ways of asking: every amount, status and count the same; it
lacked V454's under-one-naira rule, now added, and its "last reference" differed only where two payments were confirmed at the
same moment, now broken the same way in both (the later reference).

**Still over 5 s (not changed here).** /admissions/screening 13.8 s and /admissions/computed-screening 11.5 s
(`admissions.olevel_score` for each candidate — a rewrite reading the grade points once was no faster and once took 536 s),
/records 12.6 s (the student list with each CGPA), /finance/ledger 12.5 s, /admissions/eligibility 8.8 s, /finance/payments
8.7 s, /catalogue/review 7–10 s (`catalogue.course_issues` for each course), /catalogue/all 7.5 s (`catalogue.code_owners`),
/gst/students 7.3 s and /eps/students 6.9 s, /students 6.4 s (`registration.voluntary_withdrawals_due`: the semesters
unregistered for each of 54,573 students), /finance/fees 6.2 s, /student-query/classification 5.1 s.

## P. The remaining slow screens (18 October 2026, V541)

Fresh connections, three each, median; every reader compared row by row with the one it replaces on the live-shaped copy:

| Reader | Before | After | What it was |
|---|---:|---:|---|
| `admissions.screening_register` (Admissions screening) | 2.91 s | 0.77 s | `admissions.olevel_score` for each applicant → `admissions.olevel_scores(session)`, all at once (38,847 pairs the same) |
| `admissions.non_sitter_post_utme` (computed Post-UTME) | 2.07 s | 0.76 s | the same |
| `registration.voluntary_withdrawals_due` (Students) | 1.35 s | 0.46 s | `registration.semesters_unregistered` for each of 54,573 students |
| `catalogue.review_summary` (Course review) | 1.67 s | 0.19 s | every course compared with every other for a duplicate → `catalogue.course_issues_all()` by counts |
| `catalogue.code_owners` (All courses) | 1.00 s | 0.07 s | the owner a code names read for each course → once a prefix |
| `finance.fee_gaps` (Students with no fee stated) | 0.50 s | 0.13 s | `finance.final_level` for each student → once a programme |
| `people.record_issues` (Records check) | — | — | the same, found by the new property |

In the API: the eligibility list, the screening review, the applicant screening lists and the admissions funnel join
`admissions.programme_by_name` instead of calling `admissions.programme_code_of` for each applicant; the course list's issue filter
reads `catalogue.course_issues_all()` once; the Records & Queries student list hands `assessment.scope_cgpa` its students as one
parameter (an `ARRAY(SELECT …)` kept it from being inlined); and the day book (/finance/ledger) sends its totals and the newest
500 of its confirmations — thirty days of the copy are 18,037 rows (4 MB), which the screen took 12 s to draw — the journal's
export fetching every one.

The property `V541` in `db/check.sql` runs the main readers over 1,000 invented students and fails if any calls a function as
often as once a student; it found `people.record_issues` and `finance.fee_gaps` doing so with `finance.final_level`.

Still a few seconds on the copy: the Records & Queries CGPA for the whole University (about 5 s of work over 538,000 registration
entries), the payments query and its breakdown, the GST and EPS student lists (`finance.gst_eps_rows_all`).

## Q. The live database's own figures, the CGPA kept, and the calls that keep a function from being inlined (18 October 2026, V546–V550)

**The live database's slowest statements (V546).** The screens of §O and §P were found on a copy on the development machine.
The live portal's own database keeps, in `pg_stat_statements`, how often each statement ran and how long it took; ICT (and the
administrator, read-only) now see them on **Slow Statements** (`/platform/slow-statements`): by mean, worst, total time or calls,
each with the portal functions it calls and the screens known to call them (`platform.statement_screen`, which ICT may add to).
Where the extension is not loaded (a database without `shared_preload_libraries = pg_stat_statements`), the screen says so; where
the portal's role may not read other roles' statement text, it says that the statements are hidden and how to grant
`pg_read_all_stats`. This is the measure to act on before restating anything else.

Fresh connections, three each, median, on the live-shaped copy:

| Reader | Before | After | What was done |
|---|---:|---:|---|
| Records & Queries CGPA, every live student | 5.8 s | 0.30 s | `assessment.cgpa_kept`, made stale by what changes a CGPA (V549) |
| Payments query (`finance.payments_query`) | 0.1–0.2 s | — | already fast on a fresh connection; the "3 s" was the development machine's slowdown |
| Payments breakdown (`finance.payments_breakdown`) | 0.55–1.0 s | — | restated to name each purpose once: the same rows, no faster (the cost is reading 284,181 payments) — left as it is |
| The payments screen's filter options | 0.76 s | 0.29 s | three passes over the confirmed payments and a category for each → one pass, a category for each of 80 purposes |
| GST/EPS rows (`finance.gst_eps_rows_all`) | 0.99 s | 0.97 s | its entries and sheets read through the class index: the same 103,436 rows, no faster — left as it is |
| GST/EPS population (`finance.gst_population`, what the screens read) | 0.35–0.42 s | — | already fast on a fresh connection |
| Biodata counts (`people.biodata_status_counts`) | 2.1 s | 1.5 s | the students handed to `people.biodata_statuses` as one value (V550) |

**The kept CGPA (V549).** `assessment.cgpa_kept` holds each student's CGPA as `assessment.scope_cgpa` works it out, with two
counters: `stale_gen`, raised by a statement trigger on every table a CGPA is read from (`assessment.score`,
`assessment.score_sheet`, `assessment.exam_session`, `registration.entry`, `registration.course_registration`, a grading
`policy.version`, `policy.grade_band`), and `kept_gen`, the generation the kept figure was worked out at. A kept CGPA is used only
while the two agree; `assessment.kept_cgpa(students)` works out the rest at once, so the register is never behind the results.
The API's `CgpaKeeper` works out the stale ones every minute (batches of 2,000, each its own transaction, at most 20 s a tick)
and makes every one stale at 01:30 each night, for a grading version that comes into force on a date with no write. On the copy
the whole register is worked out in about 60 s the first time; the kept CGPA equals `scope_cgpa` for all 10,290 students who have
one. A statement trigger adds no measurable time to a row written one at a time (2,000 entry updates: the same time with or
without it).

**The calls that keep a function from being inlined (V550).** `api/scripts/perf/scan-calls.py` lists every call of a SQL function
whose arguments hold a subquery: 47 calls of 22 functions in the API and the database's functions, 17 of them calls of 7
functions returning rows. Handing the list
over as a value instead was measured for each that a screen or a job reads:

| Call | Subquery | Value | Kept |
|---|---:|---:|---|
| `people.biodata_status_counts` → `biodata_statuses` | 2.1 s | 1.5 s | restated (V550) |
| `people.biodata_requirement_impact` → `biodata_completion` | 1.3 s | 2.3 s | left as it is |
| `people.refresh_biodata_snapshot` → `biodata_statuses` | 4.0 s | 4.8 s | left as it is |
| Records & Queries clearance → `clearance.unit_states` | 8.9 s | 8.2 s | left: the function's own reading is the cost |
| Graduation → `clearance.cleared_many` | 0.85 s | 0.80 s | left |
| Clearance desk → `clearance.stage_rows` | 0.14 s | 0.06 s | left: a second round trip to read the students first costs as much |
| CCE classes → `finance.fee_positions_of` | 0.29 s | 0.19 s | left (no CCE student on the copy) |

Only five SQL functions returning rows cannot be inlined however they are called: four volatile ones that write
(`audit.unattached`, `finance.gl_sync`, `finance.import_fee_structure`, `people.repair_postgraduate_levels`) and
`finance.gst_eps_rows_all`, which turns nested loops off on purpose (V468). A scalar SQL function whose body reads a table is
never inlined, whatever its arguments, so the subquery arguments of the scalar calls change nothing.

Still a few seconds on the copy: the Records & Queries clearance for the whole University (`clearance.unit_states`, about 8 s for
54,573 students) and the payments breakdown with no filter (about 1 s). Slow Statements will say whether the live portal finds
them slow.

## R. Over a period, and one read left as it is (18 October 2026, V554 released, V555)

**Slow Statements over a period (V555).** Each night (00:05 Lagos) every statement's calls, time and rows are kept
(`platform.statement_snapshot`, 35 days), and Slow Statements reads the last day, 7 or 30 days as what ran since that snapshot — a
statement that has just turned slow no longer hides behind months of totals. ICT may reset this database's statistics with a
reason (`platform.reset_statement_stats`, kept in `platform.statement_reset`). After each snapshot, a statement whose average over
the last day is at least twice the week before's (20 runs each, at least half a second) is told to ICT (STATEMENT_SLOWER) and listed
on the screen.

**The Records & Queries clearance for the whole University (`clearance.unit_states`).** About 3 s for 54,573 students on fresh
connections: each student's latest decision of each of the 8 convocation units is looked up through the index — 436,568 lookups of
some 0.004 ms. Two restatements in one pass gave the same 436,568 rows (and the same 327,426 of the fresh clearance) but were slower:
the latest decision of every unit sorted once, 3.95 s against 2.84 s; read in the index's order, 5.1 s against 4.4 s. It is left as
it is; it runs only when the clearance view of the register is opened. Reading fewer students (those convocation concerns) would be
the saving, and is the Registry's call.

## S. Every menu page crawled again on a fresh live-shaped copy (19 October 2026, V565)

- **The copy.** The older copies (`lvcrawl`, `lv515`) had drifted from the migrations: lv515 lacked V506's table yet held later objects. So a fresh dump was taken inside the API container and restored as `live565`: 54,573 students, production at V564, with V565 applied by migrate.sh against main's files. The API and the production build were made from the commit's own tree.
- **The crawl.** 299 menu pages were opened, each as the widest office whose menu has it, with every office's home page. There were no errors; the 9 redirects were home pages that send on. Pages were then re-timed one at a time, twice each, on an idle machine:

| Page | Office | Seconds (first, second) |
|---|---|---|
| Home (Head of Department) | hod | 9.7, 9.5 → **3.3, 3.6 after the fix below** |
| /finance/payments | bursar | 4.9, 4.8 |
| /gst/students, /eps/students | gst, eps | 4.7, 4.1 · 4.6, 4.2 |
| /stats | registrar | 4.6, 0.13 (cached) |
| /admissions/candidate-data | academic | 4.4, 4.3 |
| /finance/fees | bursar | 4.1, 4.2 |
| /admissions/computed-screening | academic | 3.9, 3.9 |
| /admissions | registrar | 3.4, 3.0 |
| /catalogue/all | registrar | 3.0, 1.9 |
| /college/payments | bursar | 2.6, 2.7 |
| /helpdesk/reach (new, V565) | super, ictagent | 1.5, 1.5 |
| /helpdesk/password-reset/bulk (new) | super | 0.4 |

- **The Head of Department's home was the outlier.**
  - Its fees figure and its owing list joined `finance.session_clears`, which works out clearance for every student in the University, and then kept one department.
  - They now ask `finance.session_clears_for` for that department's students only. The rows are the same (the list's checksum is unchanged): the count went from 2.0 s to 0.6 s and the list from 4.1 s to 1.1 s on a fresh connection. Through the API's pooled connections the count had taken 9 s.
  - Its carry-over count (1.8 s, kept a few minutes by FigureCache) is left as it is.
- **The local caveat, seen again.** The same prepared count, run repeatedly in one PG18 connection on Windows, took 2.1, 6.2, 8.7, 8.7 … s, and 29.9 s with custom plans forced. Compare fresh connections, as recorded before. Production is PG17 on Linux.

## T. The slow screens of §S taken in turn (19 October 2026, V573)

Each read below was timed on the live-shaped copy on fresh connections, the old and the new alternating (the median of
three), and checked to return the same rows.

| Read (screen) | Before | After | How |
|---|---|---|---|
| `registration.carryover_students` (Head of Department's home, carry-over count) | 12.0 s, largest department (4,807 students) | 0.5–0.9 s | the department's results read at once, below |
| Post-UTME audit (`/admissions/computed-screening`) | 1.6–1.7 s | 0.06–0.08 s | counted by programme first; each programme's code and screening read once (some hundred), not once an application (12,649) |
| `finance.payments_breakdown` (`/finance/payments`) | 0.66 s | 0.38 s | totalled once by category and faculty, each list summed from those groups |
| `finance.payments_query` (`/finance/payments`) | 0.67 s | 0.54 s | the matches read narrow (reference, time, amount) for the count, total and newest page; only the page's 500 rows joined to the student |
| `finance.gst_population` (`/gst/students`, `/eps/students`, the GST fee page) | 1.82 s | 1.72 s | the GST fee matched once a (programme, faculty, level, entry mode), not once a student |

- **The carry-over count.**
  - The home called `registration.carryovers` for each student, and that reads the student's results twice.
  - `registration.carryover_students(department)` reads the department at once: each sheet's latest scores once,
    `assessment.course_final`'s choice of sitting, then each course's last failure against its last pass in one pass.
  - A first version compared every failure with every pass through a nested loop the planner chose (60 million
    comparisons, 28 s) before it was restated.
  - In all 45 departments it finds the same 6,842 students as the old way (30.7 s for the whole register against 98.7 s).
- **What is left.**
  - The GST/EPS pages spend about 1.2 s of their 1.7 s in the GST/EPS engine over the whole register (V468), which is left
    as it is.
  - Candidate data (`admissions.attachment_state` 0.7 s, the candidate list 0.5 s) is left as it is. Its passport test
    reads no image (the payloads hold 112 kB in all).
  - `clearance.migrated_summary`, warmed at the API's start, took 59 s on the copy. It is noted for its owner.
- **Payments confirmed at the same moment** (an old-portal load) are now listed in a stable order, by reference. Before, 43
  payments sharing the time at the 2,000-row cut came in whatever order the plan gave.
- **The local caveat again.** Through the API's pooled connections the same reads took 4–7 s; on fresh connections, 0.5–2 s.

## U. The GST/EPS population kept, the migrated summary, Candidate data (20 October 2026, V577)

| Read (screen) | Before | After |
|---|---|---|
| GST students list, through the API | 5.7–6.9 s | 0.5–0.6 s (the first read of a session works the population out: 7.9 s locally) |
| EPS students list | 5.4–5.7 s | 0.27 s |
| GST fee page standing (`/gst/fee`) | 4.9 s | 0.19 s |
| `clearance.migrated_summary` (worked out at the API's start) | 25–58 s | 16–18 s, and five minutes after the start |
| `admissions.attachment_state` (Candidate data) | 1.3 s | 0.3 s |
| Candidate data's candidate list | 0.7–2.2 s | 0.3–0.55 s |

- **The GST/EPS population is kept** (`finance.gst_population_kept`).
  - It is worked out once per session and semester, and again behind the screens once five minutes old
    (`GstPopulationKeeper`, `moaum.gst.population-fresh-seconds`).
  - A change to the GST fee, its setting or a payment review marks it out of date (statement triggers), and Refresh works it out
    at once. The screens say "Figures as of …".
  - A student's own GST/EPS standing (the permit, registration, the fee gate) still reads the engine live.
  - The kept rows are the live function's, row for row (51,121 for 2025/2026).
  - A GST write answers from its own transaction without working the population out there, because that would wait on its own
    lock.
- **The migrated summary.**
  - The old version crossed 44,497 students with 64 gate pairs. The new one reads each pair's latest decision once, with the
    memory to sort them in, and counts the CLEARED pairs each student holds. The figures are the same in every range tried.
  - The 2.85 million decisions are still read either way. A per-student index scan (43 s) and a covering index (16 s to build,
    upkeep on every decision) were both measured and set aside.
  - The warm-up now runs five minutes after the start (`moaum.figures.migrated-warm-delay-seconds`), not during the first
    health checks.
- **Candidate data.** The session's committed numbers are read once (`admissions.candidate_is_committed`'s rule), and each
  candidate's files are read once.
- **Left as it is.** Computed screening's `admissions.non_sitter_post_utme` (about 2 s): its O'Level scoring was tuned in
  V486/V541.
- **One connection per GST read (V580).** The GST fee page, its review list, and the GST and EPS dashboards and lists used to
  open their read-only transaction first and then work the population out in a transaction of its own. The request held two
  connections, and a pool under load could run short. Now the population is worked out first, and the read opens its own
  transaction afterwards (`GstController`, a read-only `TransactionTemplate`).

## V. The migrated students' clearance figures kept (20 October 2026, V585)

| Read | Before | After |
|---|---|---|
| `clearance.migrated_summary(100, 400)` on the live-shaped copy | 13–19 s (V577's one pass over 2.85 million decisions) | 0.11–0.32 s |

- Each student's count of gate pairs whose latest decision reads CLEARED is kept in `clearance.gate_pairs_kept`.
- Statement triggers on `clearance.item` count again only the students a write touches: 4 ms for one student, 0.2–1.6 s for
  2,000 in one statement. The students' kept rows are locked first, so two officers deciding on the same student are both
  counted. A change to the gate purposes or the units counts everyone again (about 16 s on the copy; a rare act).
- The summary reads the register and the kept counts. Its figures are the old function's in every level range tried: 100–400,
  100–100, 200–300, 100–900 and 500–600.
- Not for a test: deleting clearance items is slow. The self-reference `superseded_by` has no index, so each deleted item scans
  the table. The portal never deletes decisions.
