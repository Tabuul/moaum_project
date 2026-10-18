# Finding the slow screens (V537, V541)

Tools for measuring the portal's screens against a **copy** of the live data — never against the live database. Each reads only
(the crawl opens pages; the timings run inside transactions that are rolled back).

## 1. Crawl every menu page

1. A copy of the live data in a local PostgreSQL (see `docs/performance-audit.md` for how the copy is made), migrated to the
   commit being measured. Have it log slow statements:
   `ALTER DATABASE <copy> SET log_min_duration_statement = 1000;`
2. The API on that copy, with the background jobs held off so they do not compete with the pages:
   `--moaum.notices.initial-ms=86400000 --moaum.notices.jobs-initial-ms=86400000 --moaum.paydirect.watch-initial-ms=86400000
   --moaum.paydirect.sweep-initial-ms=86400000 --moaum.providers.watch-initial-ms=86400000 "--moaum.overloads.remind-cron=0 0 0 1 1 *"
   --moaum.payments.sweep-every-ms=86400000`
3. A **production build** of the frontend (`next build`, `next start`) pointed at that API, with a dev token
   (`api/scripts/dev-token.mjs`) for a person holding every staff office. A dev server's compile time would swamp the figures.
4. The map of menu pages to offices: `cd frontend && node --experimental-strip-types ../api/scripts/perf/routes-offices.mjs out.json`
5. `node crawl.mjs out.json crawl.jsonl http://127.0.0.1:<port> <token>` opens each page once as the widest office whose menu has
   it, and each office's dashboard; `crawl-some.mjs <jobs.json> <out.jsonl> <base> <token> 2` opens a chosen list twice each.
6. `python -I slowlog.py <server log> <byte offset>` groups the slow statements logged since the crawl began;
   `python -I attribute.py <out.jsonl> <server log> <offset>` lists each slow page with the statements logged while it loaded.

Run nothing else on the database server while measuring: a test suite or a long query on another database of the same server
doubled or trebled the times recorded.

## 2. Time a statement the way the live portal runs it

`bash fresh-and-repeated.sh <copy url> "<statement>" 4` times the statement on four fresh connections and four times on one.

- **The fresh figures are the ones to compare.** On the development machine (PostgreSQL 18 on Windows) a server process that has
  run two or three heavy statements runs everything about four times slower — every node of an unchanged plan — and a new
  connection is fast again. The live portal runs PostgreSQL 17 on Linux (Railway, AWS RDS), where this was not seen; repeated
  runs on the development machine overstated the "before" of V537.
- **PostgreSQL 18 caches the plans of a SQL function that is not inlined** into the query calling it, and from its sixth call on a
  connection may use a generic plan: `admissions.olevel_scores` took 0.45 s five times, then 19 s. PostgreSQL 17 does not
  (production today); an upgrade to 18 would. A set-returning SQL function is inlined when its arguments are constants or
  parameters — an array built by a subquery (`ARRAY(SELECT …)`), or a call from plpgsql, keeps it out. Pass such a list as one
  parameter (`CAST(:ids AS uuid[])`), or give the function only what it can find itself (the session).

## 3. See which functions a statement calls

`psql -v q="<statement>" -f fnstats.sql` runs the statement three times, then once more with `track_functions = 'all'`, and lists
each function called outside the plan with its calls and time. A function called once for every student or applicant
(`finance.final_level`, `admissions.programme_code_of`, `finance.position`, `admissions.olevel_score`…) is what made the slowest
screens slow: read such a figure once for each programme, prefix or session in a CTE, or join to a set
(`admissions.programme_by_name`, `finance.session_positions`, `admissions.olevel_scores`, `catalogue.course_issues_all`).
Inlined functions are not listed — they cost nothing as calls.

The property `V541: the readers that screens open read in one pass` in `db/check.sql` holds the main readers to this: each is run
over 1,000 invented students and must call no function as often as once a student.

## 4. Find the calls that keep a function from being inlined

A SQL function that returns rows is inlined into the query that calls it only when its arguments hold no subquery; otherwise its
own statement is planned apart, without the arguments' values (PostgreSQL 17 every time; 18 from the sixth call on a connection,
by a cached generic plan). To list every such call in the API's statements and the database's own functions:

```bash
psql "$COPY" -Atc "SELECT n.nspname || '.' || p.proname || '|' || p.proretset::text || '|' || p.provolatile::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE p.prolang = (SELECT oid FROM pg_language WHERE lanname = 'sql') AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'public')" > sql-functions.txt
psql "$COPY" -Atc "SELECT n.nspname || '.' || p.proname || '@@' || replace(p.prosrc, chr(10), ' ') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'public') AND p.prolang IN (SELECT oid FROM pg_language WHERE lanname IN ('sql', 'plpgsql'))" > bodies.txt
python -I -X utf8 scan-calls.py sql-functions.txt bodies.txt ../../src/main/java
```

Measure before changing one: handing the list over as a value (`CAST(:ids AS uuid[])` from the API, a variable through
`EXECUTE … USING` in plpgsql) let the planner see the students, which was faster for `people.biodata_status_counts` (V550,
2.1 → 1.5 s) but slower for `people.biodata_requirement_impact` and `people.refresh_biodata_snapshot`, and made no difference
where the function's own reading is the cost (docs/performance-audit.md §Q). A scalar SQL function whose body reads a table is
never inlined, whatever its arguments.
