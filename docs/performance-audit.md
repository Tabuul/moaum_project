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

## W. The audit trail screen on a large trail (21 October 2026, V623)

The University reported `/audit` failing with "This page couldn't load". Every visit read the whole trail. `audit.entries` had no
index on `occurred_at` and `iam.student_event` none on `at`, so finding the latest 200 sorted every entry and student sign-in.
"Entries on the record" counted every row, and the filters' counts grouped thirty days of entries. The Internal Audit home
dashboard's feed (`/audit/entries?limit=12`) paid the same. Production's audit log was already 4 GB on 2 October (see the introduction).

Measured on a scratch copy with made-up volumes (4 million entries, 400,000 of them today; 2 million student sign-ins; 200,000
staff sign-ins), local PostgreSQL 18, cold then warm:

| Read | Before | After (cold / warm) |
|---|---|---|
| Latest 200 entries | 13.0 s | 0.40 / 0.30 s |
| Latest 12 (Internal Audit home) | as above | 3 / 4 ms |
| "Entries on the record" | 4.7 s | 1.36 / 0.20 s |
| Today's three tiles | 4.7 s | 2.1 / 0.67 s |
| Filter counts (domains, offices) | 14.2 s | 0.21 / 0.07 s |
| A filter that matches nothing | (the whole trail) | 0.32 / 0.02 s |

- `audit.ix_entries_recent (occurred_at DESC)` is on every monthly partition, built `CONCURRENTLY` so no write waits (as V306
  built the sealer's index). A partition made later inherits it. `iam.ix_student_event_recent (at DESC)` covers student sign-ins.
- The total is `audit.entry_count()`: `chain_head.last_seq` is the number of entries sealed in each (period, shard), so their sum
  plus the unsealed entries (the sealer's partial index) is every entry, read in one snapshot. check.sql V623 holds it equal to
  `count(*)` before and after sealing.
- The filters and the counts beside them read the latest 50,000 entries of the trail (`AuditLogController.FILTER_WINDOW`), not
  thirty days. The screen says so when a filter is on. The window is taken in time order from the three sources and stops at the
  200th match.
- Today's tiles still read today's entries. On a day of 400,000 audited writes that is about 2 s cold.

### The follow-ups (21 October 2026, V626)

- **Security posture** (`/governance/security`: the `/security` screen and the home dashboards of the Security Unit, Internal Audit
  and Deputy Audit) counted every audit entry, as `/audit` did before V623. It now reads `audit.entry_count()`. `max(occurred_at)`
  now comes from the end of V623's index.
- **"Today" starts at midnight in Lagos.** The tiles counted from the database's midnight, which is UTC (01:00 in Lagos), so an
  entry between 00:00 and 01:00 Lagos time was left out. They now count from `(now() AT TIME ZONE 'Africa/Lagos')::date` at
  midnight in Lagos (V539's rule), and the comparison still reads from the end of the indexes.
- **One kind of record, newest first** (the session policy's history, the biodata gate's, a session's fee schedule changes, the
  College's trails). Until now these were served by `ix_entries_subject (subject_type, subject_id, occurred_at)`, which reads every
  entry of the type and sorts them, or by V623's time index, which walks back through every type until it has enough. On the copy
  of §W, with a made-up type of 200,000 entries whose latest is two weeks behind the end of the trail, the planner took V623's index:
  665–740 ms for the newest 100. With `audit.ix_entries_type_recent (subject_type, occurred_at DESC)` on every partition (V626,
  built `CONCURRENTLY`), it takes 0.6–1.4 ms. A type of a million entries went from 15 ms to 2 ms, and types of a few thousand were
  already fast. Each audited write keeps one more index entry.
- The times above are execution times. Planning a query over the 24 monthly partitions took about 450 ms more on the local
  PostgreSQL 18 (Windows), whose backends are slower than production's; it is the same with or without the index.

### Searching the trail by date and by person, the tiles kept a minute (21 October 2026, V627)

- Since V623 the filters read the latest 50,000 entries, which on live is a day or two. The audit screen now takes a date range
  (`from`, `to`: days in Lagos) and a **who**: a staff number, matriculation number, name or id, naming at most 10 people (staff
  first). Each source is read from the end of its own index within those limits:
  - `audit.entries` by time (V623) or by actor (`ix_entries_actor`, V002);
  - the sign-ins by time, or by person through V627's `iam.ix_sign_in_person (person_id, at DESC)` and
    `iam.ix_student_event_student (student_id, at DESC)`.

  A person is read one at a time (LATERAL), each newest first, then merged. The domain and office filters, and their counts, read
  the latest 50,000 entries within the range and the person. The answer names the people a "who" matched.
- The four tiles are kept for a minute (`AuditTilesCache`, `moaum.audit.tiles-seconds`, default 60) and shared by everyone who
  opens the screen or the Internal Audit home. One request works them out at a time; the others are given the kept figures.
- `.card__body.row` now lays out as a row. `.card__body` is a flex column and `.row` never set a direction, so on about 16
  screens (export log, record views, eligibility, readiness, results sheets, the overview, NELFUND and others) the filters stood
  stacked down the right edge of their card. One rule in `prototype.css` puts them side by side.

## X. The register intake in one pass, and in tranches (11 November 2026, V722)

- The Admissions dashboard's **Bring N candidates onto the register** stopped with "This took longer than the portal allows a
  screen to read" on 11 November 2026, with 2,359 admitted candidates waiting. `people.intake` (V278) brought them on one by one,
  and each `people.student` it inserted fired `trg_position_student_insert` → `people.position_touch` →
  `people.refresh_academic_position` for that one student. Profiled on the live-shaped copy (`track_functions = all`, 200 invented
  candidates, rolled back): 125 ms a candidate, 117 ms of it that refresh — 2,359 candidates were some five minutes of one
  statement. The API's own 90 s limit is on read-only transactions alone (this is a write; run locally with a 3 s limit, the intake
  of 200 took 33 s and completed), so the cut came from outside the API: a `statement_timeout` on the server, the database or the
  role, or `options=-c statement_timeout=` in the `DATABASE_URL`'s query (which `DatabaseUrlConfig` passes through), or a cancel
  request — SQLSTATE 57014 is the same for all of them, and `ProblemHandler` drops the server's message. The database's log line
  names the cause: "canceling statement due to statement timeout" against "canceling statement due to user request".
- `people.intake_tranche(session, limit)` (V722) runs the intake the way V463 runs a register upload: `people.defer_positions()`
  first, so the triggers note each student instead of refreshing, then `people.refresh_deferred_positions()` once — the run's
  students computed together in one statement (measured for V722 on the same copy: the positions of 2,400 students in 0.7–1.6 s).
  It takes a per-session advisory lock first, so a second run of the session (another officer, another tab, a resent request)
  waits for the first to commit and then takes what is still off the register instead of racing it onto `ux_student_candidate`.
  It brings on at most `limit` candidates (by surname; null or under one: all) and answers how many it brought and how many
  remain. `people.intake(session)` is the same run with no limit. On the copy, 200 candidates: 21 s before, 1.7 s after.
- `POST /api/v1/student/intake/{session}?limit=` answers `{session, broughtOnto, remaining}`; the dashboard calls it in tranches
  of 300 until none remain, the button counting them on ("Bringing them on… 600 of 2,359"), so no single request outlasts what
  a screen — or a proxy — allows. Each tranche is its own transaction: a candidate the run cannot take (a programme the University
  does not run, 23503 → 409; a JAMB number already on the register with a history, 23514 → 422) refuses that tranche, which rolls
  back, while the tranches already committed stay; the page then re-reads the count and the notice says how many were brought on
  before the run stopped, and the next press continues from there.

### What stopped it, named on the answer and kept for ICT (11 November 2026, after V722)

- The answer to SQLSTATE 57014 used to say, for every stopped statement, "This took longer than the portal allows a screen to
  read" — also for the intake, a write the portal never limits. It now names the cause from the database's own words and the
  portal's limit that was on the failing statement: `PORTAL_READ_LIMIT` (a screen's read cut at
  `moaum.db.request-read-timeout-ms`), `PAYDIRECT_DOOR_LIMIT` (the PAYDirect door's own pool, whose connections carry
  `moaum.paydirect.statement-timeout-ms`), `DATABASE_STATEMENT_TIMEOUT` (a statement timeout other than the portal's own: the
  server's configuration, the database, the role, every role, or the connection's options), `CANCEL_REQUEST`
  (`pg_cancel_backend`, or a client's query timeout) or `OTHER`. The code stays `QUERY_TOO_LONG` for a time limit and is
  `QUERY_CANCELLED` otherwise; the title and detail say which, with how long the request had run.
- The portal's limit is noted where the statement failed, not read afterwards from the request: `StoppedStatement.Translator`
  sits on the portal's JdbcTemplate (behind the JdbcClient every module injects; PlatformConfig) and on the PAYDirect door's,
  and turns each 57014 into a `StoppedStatement` carrying the transaction it ran in and the limit on it. A statement that ran on
  a pool thread (FigureCache, FinanceSummaryCache, ReadinessSnapshot) had no portal limit on its connection, whatever the
  request's own transaction was; an outer transaction's statement after an inner one ended is judged by its own transaction. The
  request's note of its latest transaction (`AttributedTransactionManager`) is the fallback for a statement that did not pass
  the portal's JdbcTemplate.
- The error toast no longer reads a 503 carrying either code as "The portal could not reach the server … nothing was saved":
  the server answered, and its words are shown. Seven screens that threw the answer away and passed the status alone now pass
  the answer (Lifecycle, Lifecycle history, Above final, Level corrections, Level fee effect, CCE applications, Old fees uploads).
- Each stopped statement is logged once at WARN (cause, the database's words, the transaction, the limit, how long the request
  had run, the method and route pattern, the office the request acted as, the reference) and kept in memory: the last fifty
  stopped on a request this API instance answered, since it started (`QueryCancellations`: the route pattern, never the address,
  which can carry a student's id). Each instance keeps its own list and a redeploy empties it; a scheduled job's or background
  work's stopped statements are in the server's logs alone. Only statement timeouts and cancels (57014) are listed: a lock wait
  (55P03) is answered as a refusal, and a transaction or idle limit closes the connection.
- `GET /api/v1/platform/database-limits` (ICT, admin, super) reads, on a connection outside any transaction so the portal's own
  read limit is not taken for the database's: `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`,
  `transaction_timeout` and `idle_session_timeout` from `pg_settings` with their source; the defaults stated on the database,
  the role and every role (`pg_db_role_setting`, the time limits alone); the portal's own limits (the read limit, a transaction
  or query timeout if one is configured, the PAYDirect door's statement and lock limits, the connection's `options` alone, never
  the rest of the address); sentences saying whether the database stops the portal's statements, after how long and set where,
  that a screen's read runs under the portal's own limit instead (its `set_config` replaces the database's for that read), what
  limits a write, and any other limit the database places on the portal's transactions and connections; and the stopped
  statements, newest first, with the database's own words. ICT's Slow statements page (`/platform/slow-statements`) shows it
  above the statements as "Time limits and stopped statements".
- Tested for real in `StatementStoppedIT` with a 1.5 s read limit: a screen's read waits on a table the test holds locked and is
  cut at the limit; the intake waits on the session's intake lock (V722) the test holds and is stopped by `pg_cancel_backend`;
  ICT reads both by their routes; every wait is bounded and every lock released on every path. `StatementStoppedTest` covers the
  translator on a request's thread, a pool thread, a write, outside a transaction and on the door's pool; the answer per cause;
  the office from the audit context; the fifty kept; the read-out's sentences.

## Y. The database's load from page traffic, for a smaller database (15 November 2026, V767)

The AWS cost report of 7 November 2026 found the portal's database at the 4xlarge size it was given on 26 October, using 3.5% of
it on average and 25% in the busiest five minutes, at about 100 requests a second (11:00–13:00 WAT). What sizes the database is the
sum of every request, not the slowest screen, so this section measures the requests page traffic makes, weighted by how often.

- **The method** (`api/scripts/perf/replay.mjs`, `endpoint-cost.sh`, `compare.mjs`; §5 of its README). A copy of the live data
  (Railway, 22 October; 54,575 students, 538,180 course registrations) migrated to main and restored into a PostgreSQL cluster of
  its own with `pg_stat_statements` loaded (the shared scratch cluster cannot be restarted to load it). 400 real students and 200
  applicants of 2026/2027 sampled, each given a session of the portal's own kind (`platform.session`) and a token naming it, so the
  session check and the student gates run as in production. Each page load is replayed as the frontend makes it: the proxy's
  `iam/session`, then the page's calls in their stages (`loadStudent`'s `iam/me`, `me`, `me/biodata/completion` together, then the
  page's own). The mix of a November week: the dashboard (30%, half through `/`), fees 20%, course registration 15%, results 10%,
  then courses, examinations, profile, notifications, timetable; the applicant's home, status and admission pages. 3,000 page
  loads (the students eight at a time, the applicants four); then each endpoint alone, once per person.
- **What it found.** 1,958 s of database time and 31.7 million pages read for the 3,000 loads (about 0.65 s a page):
  - 53.5%: one statement, `StudentPortalRepository.sessionsWithChargesFor` — the sessions a postgraduate, CCE or MBBS student has
    fees in, read inside `fees()` on every screen of theirs (`me`). Written `FROM (SELECT DISTINCT session …) x WHERE
    finance.fee_stated(:s, x.session)`, the planner pushed the stable function below the DISTINCT: `finance.fee_stated` (which
    works out the student's spillover, final level, faculty rule and postgraduate stage) ran once for each of the 851 fee lines,
    not the two sessions — about 4 s a call. Listed first (`WITH x AS MATERIALIZED`), it runs twice.
  - 8.0% + 6.7% + 6.1%: the GST/EPS engine, `finance.gst_eps_rows(session, student)`, behind the dashboard's GST & EPS panel
    (`me/gst`, which also worked out the whole `finance.gst_eps_explain` to keep only its eligibility), the registration page's gate
    (`registration.gst_gate`, asked once for every GST/EPS course on the menu) and the entitlement and payable courses. Written
    for the whole register and one student at once (`p_student IS NULL OR …`), a plan made for any student — inside another SQL
    function, a plpgsql body, a kept plan — read every student, joined every GST registration entry of the register (about 50,000)
    and every score on the student's GST sheets (about 13,000) for one student's rows: about 350 ms a call. V767 makes the
    register and the student two branches, one skipped at once (a one-time filter on the parameter): the student's registrations
    by their key, their own latest scores alone — about 9 ms. The register's rows (68,534) and 60 students' were compared row for
    row, old against new: the same; `finance.gst_eps_rows_all` (§U) is unchanged in what it gives (V468's check).
  - 2.3%: `iam/me` counted the University's nine queues (`WaitingRepository.waiting`, over the whole register) and read the staff
    record on every screen of every student and applicant, whose screens show neither. They are not read for those two offices
    now; a student keeps the bell (their own unread notices on `s/notifications`, which the transfer, password and manual pages
    show from this answer).
- **After V767** (the same replay): 350 s of database time (−82%), 17.8 million pages (−44%); the students' 2,000 page loads took
  101 s instead of 300. Each endpoint alone, per call: `me` 258 → 32 ms, `me/outstanding-fees` 261 → 52 ms, `me/fees` 192 → 38 ms,
  `iam/me` (student) 13 → 0.7 ms; `me/gst` and `me/registration` lose most of their GST work. Every student's and applicant's
  answers from the changed endpoints were compared, old code and database against new, on the copy (`compare.mjs`): identical,
  but for `iam/me`'s `waiting`, which no longer carries the University's queues for the two offices.
- **PostgreSQL 17 and 18.** The live databases run PostgreSQL 17; the measuring cluster ran 18. 17 plans a non-inlined SQL
  function's body afresh at every call with its parameters unknown (a generic plan, every time); 18 keeps the plan, custom for
  the first five calls. The changes cut execution, not planning, and do not add to the planning (`gst_eps_rows` plans in 9–14 ms
  warm before and after), so they hold on both; on 18 the GST functions' kept plan is re-planned each call (the register branch
  makes the generic plan look costly), still faster than before. A measurement on 17 itself is the check still to make.
- **What remains** (by share of the 350 s): the historical fees read twice per dashboard and fees page (`finance.historical_rows`
  through `historical_account` and `historical_review`, 14%, nothing found on the copy, whose `historical_start` is the current
  session); `admissions.admission_tracker` (8%); and `fees()` — `finance.position`, `charges`, `semester_cleared`,
  `spillover_panel`, `fee_unstated_semesters`, `due_for_semester` — about 31%, more than half of it from `me` on every student
  screen, which the student shell reads only for the name, number, entry mode and menu flags. A slimmer `me` for the shell is the
  next step; the staff dashboards that read the whole University (§S, the HOD's fees and results pipeline, the registration
  approval cards) are the step after.

## Z. The student's record without the dashboard's panels (15 November 2026)

§Y left `fees()` as about 31% of the database's time from page traffic, more than half of it from `GET /api/v1/me`: every student
screen read the student's whole record through `loadStudent` (app/student/load.ts), and the record carried the dashboard's panels —
the school fees (`fees()`: `finance.position`, `charges`, `semester_cleared`, `spillover_panel`, `fee_unstated_semesters`,
`due_for_semester`), the portal's windows, the results and the standing, the carry-overs, the registration, the notices, the
graduation and the pre-resumption steps — which only the dashboard shows.

- **The change.** `GET /api/v1/me?view=core` gives the record without the panels: the same fields as the full record, in the same
  order and with the same values, the panels left out (`StudentPortalService.me(id, full)`). `loadStudent` reads it unless the page
  asks for the full record (`loadStudent({ full: true })`: the dashboard, and the postgraduate progress page, whose eligibility
  reads the school fees); the sign-in's landing (app/page.tsx), the manual and the five PDF routes that print the student's name
  and number read it too. The TypeScript types say which is which (`MeCore`, `Me extends MeCore`): a screen that loads the record
  through `loadStudent` and reads a panel without `full` does not compile; a direct `api<…>(ME_CORE)` read names its own type,
  which the compiler does not tie to the view, so it must read only the record's own fields. The notifications page, which listed the e-mails and SMS from the record's notices,
  reads them at `GET /api/v1/me/notifications/sent` (under both gates' open paths, as `/me/notifications` is). The same path keeps
  the biodata and fee gates' rule (they match the path, not the query): a held student still reads the record and its
  `portalAccess`. The offices' views of a student's portal (`/students/{id}/portal`, ICT Support's profile and payments) keep the
  full record.
- **Each call alone** (`endpoint-cost.sh`, 400 students, twice): the full record 51 statements, 28–43 ms and about 2,200 pages of
  the database's a call; the core 20 statements, 1.2–1.4 ms and about 106 pages; the sent list 0.35 ms.
- **The replay** (§Y's 3,000 page loads, the page mix as the frontend now calls): of the students' 2,335 reads of the record, 1,660
  take the core and 675 (the dashboard's) the full record; `finance.position` and `charges` run 2,531 times instead of 4,191,
  `semester_cleared` 2,904 instead of 4,564; the statements fall from 391,900 to 340,600 and the pages read from 17.7–19.5 million
  to 14.6–16.0 million. The database time, on a machine other work shared, ran 271–378 s for main and 233–295 s with the change;
  the switch saves about 40–70 s of it (44–70 s by the per-call costs, about 40–60 s by the replays' own statement figures),
  some 15% of main's run.
- **The answers.** For each of the 400 students, the core record is the full record less the panels (the fields, their order,
  their values), the sent list is the full record's notices, and the full record is the same byte for byte from main's API and
  the new one; the one student of the copy with a notice about them (a portal one) gives the same. `StudentRecordCoreIT` holds the
  same for an invented student with an e-mail, an SMS, a portal notice and a confirmation code (filed, never listed), and the
  gates' tests read the core record of a held student. The notifications page says so when the list cannot be read, rather than
  that nothing was sent.
- **What remains**: the dashboard reads the full record and `/me/outstanding-fees`, both working out the session's fees; the
  historical fees read twice per dashboard and fees page (§Y); `admissions.admission_tracker`; the staff dashboards that read the
  whole University.

## Overpaid school fees (V781, 22 November 2026)

Read on `lv643pre`, the live-shaped copy of 22 October 2026, session 2025/2026 (PostgreSQL 18, read only; counts and naira only):

| Read | Time |
|---|---|
| `finance.overpaid` (1,136 students, ₦22,446,080) | 1.8 s idle; 3.5 s, 7.5 s and 11.9 s with other sessions loading the same server |
| the causes on top of it | about 0.4 s more |
| the whole live read (overpaid, payments, causes, holds) | 6.2 s under the same load |
| `finance.session_charges` 2.4 s · `finance.possible_double_charges` 0.45–2.1 s · `finance.fee_profiles` 0.25 s · `finance.fee_sums` 0.6 s | |
| `finance.position` for one student | 3.1 ms warm; 25 ms on a connection's second call; 308 ms its very first |

So the session's live read cannot sit on the Bursar's dashboard or behind each page of the desk. The dashboard panel, the desk and
the figures read a **kept list** in the database (`finance.overpaid_snapshot`, one row a student and session): the dear part (charge,
payments, cause, holds) is kept and refreshed by a job every ten minutes for the current session (when a school-fees payment was
confirmed, uploaded or archived since, or after an hour), once a night for the others, and by Refresh on the desk; the state of each
row (decisions, requests, refunds) is read live at every read; and **every act reads the session live**, with the student's own
`finance.position` read under the student's lock as the second witness. A request or an approval of many students is run in calls of
a bounded size, the second call passing the first's batch or `since`, so no call holds locks for a whole session. The panel is a
server read after the rest of the dashboard is drawn.

Targets the build is held to: the figures and a filtered page of the desk under 50 ms; "is a refresh due" under 5 ms; the two
triggers the migration ends with, to their commit, under one second.

**Measured on 1,200 invented overpaid students** (22 November 2026, PostgreSQL 18 on the Windows development machine with other sessions
loading it, so every figure is an upper bound; one made-up session, inside a transaction that was rolled back, so the planner had no
statistics for them): `finance.overpaid` 1.2 s; `finance.overpaid_read` about 20 s; `finance.overpaid_refresh` 18.7 s;
`finance.overpaid_desk` 25 ms; `finance.overpaid_figures` 1.0 s; one request of 1,000 students 31 s.

**Measured on the live-shaped copy migrated to V775** (22 November 2026, the same machine and server, other sessions loading it; session
2025/2026; counts and naira only):

| Read | Result |
|---|---|
| the list | 1,312 students, ₦27,543,694 — the same 1,312 rows with the same charge, payments and excess as `finance.overpaid` at V773; all 1,136 rows (₦22,446,080) of the V637 reading stand with the same figures, and 176 more (₦5,097,614, all above the fee line: 400 to 600 Level students admitted 2017/2018 to 2020/2021, whom the level and spillover rules of V638 to V773 now charge) are listed |
| by cause | paid twice on the portal 0 · old portal and portal 3 (₦119,891) · twice on the old portal 81 (₦4,346,565; 33 exact and at the level by entry year, ₦2,433,475; the 34th is exact at ₦66,745 but its level differs) · part payments 34 (₦1,299,072) · above the fee line 1,194 (₦21,778,166) |
| holds | bank check 79 students (₦4,297,788) · spillover semester still to register 100 (₦2,747,278) · none of the other twelve; 179 students held, none by two holds |
| ready to credit in bulk | 5 students, ₦202,790 (the 3 and 2 of the two causes above that carry no hold); 31 more once the bank check of the twice-on-the-old-portal group is cleared (₦2,350,576) |
| two levels shown (level on record differs from the level by entry year) | 131 students (₦3,754,698); 7 of them among the 1,136 |
| `finance.overpaid_refresh` | 20 to 30 s (seven runs); 23.8 s after the reads were cut to the students asked for (below) |
| `finance.overpaid_read`, whole session | 19 to 30 s when first measured (`finance.overpaid` 5 s, `finance.fee_semesters_unstated` for the 1,312 students 6.3 s, the holds' set read once for every listed row, a nested loop over a materialized set, about 5.5 s, and the double-charge, profile and fee-sum reads about 7 s); 37 to 49 s in four runs of the review (the machine loaded); 20.6, 20.8 and 30.0 s once the pairs of one amount, the amounts that make up an excess and the repeats were found in one pass each, and the holds' own reads (the charge profiles read once for the listed students, not four times for the session) were cut to the listed students |
| `finance.overpaid_read`, one student or a few | the same 23 to 29 s as the whole session before the review: every part of it read the whole session (54,575 students on this copy) and the rows were cut at the end, so every act on one student (a request, an approval, a refund, a carry, the Legacy desk's picture of a student) paid the session once a call and the picture once for every session the student paid in. Now every part is cut to the students asked for (section 5a of the migration: `finance.fee_profiles_of`, `fee_sums_of`, `session_charges_of`, `session_payments_of`, `possible_double_charges_of`, `overpaid_of`, each its original's text with its rows cut): one student 0.16 s on average over 190 students (largest 0.46 s; the first call on a connection 1.4 s), 5 students 0.31 s, 31 students 0.53 s, 190 together 1.7 s, a student the list has no row for 0.09 s; `finance.legacy_credit_excess` 0.27 s. The rows are the same column for column: 1,312 rows of the whole session (the same md5 over every column), each of 190 students alone, the 190 together and 60 students with no row, 0 differences either way; each cut function equals its original for every student (54,575) and for 1,194 students that include 300 postgraduate and 300 spillover ones |
| `finance.overpaid_figures` | 108 to 146 ms warm (867 ms the first call on a connection) when first measured; 1.1 to 1.4 s on the review's runs, 0.25 to 0.31 s once the desk reads what is decided and requested for the session in one pass (the same figures, byte for byte) |
| `finance.overpaid_desk`, first page of 100 | 66 to 77 ms warm when first measured (`finance.overpayment_decided` for each of the 1,312 rows, about 25 ms, and the open-request lookup); 360 to 430 ms on the review's runs; 14 to 23 ms now that the decisions that stand, the refunds raised by hand and the open requests are each read once for the session and joined to the kept rows (the same 1,312 rows, 0 differences either way); filtered by cause and hold 1 to 6 ms |
| `finance.overpaid_refresh_due` | 0.7 to 1.7 ms warm (the first call on a connection about 35 to 140 ms); written as one SQL function over the run row's column it read the whole payment table three times, 120 to 240 ms, and is now a function that reads the cut-off first and plans the three probes for it |
| a request of the 31 and of the 5 | 21 to 37 s a call (one live read) when first measured; the read of the 31 is now 0.53 s and of the 5 0.31 s, and a call pays them and the per-student second witness; an approval of the 31 and of the 5 in one call each, 13 to 20 s when first measured, the same reads |
| the migration | V781 applied in about 0.9 s on this copy; its two triggers, first `CREATE TRIGGER` to `COMMIT`, 114 ms cold and 1.4 ms warm (the wallet holds 2 rows here) |

The refresh and the requests are the dear acts and run in a job and in calls of a bounded size. The figures and the unfiltered first
page of the desk are two to three times the 50 ms the build was aimed at on this data; they are one read each after the rest of the
dashboard or the page is drawn.
