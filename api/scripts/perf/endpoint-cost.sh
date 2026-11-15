#!/bin/bash
# The database's work for each endpoint alone: the statistics emptied, the endpoint called once for each person, the totals read.
#   COPY="<psql url of the copy>" API="http://…" bash endpoint-cost.sh <out.txt> < endpoints.txt
# endpoints.txt: one "<office>|<METHOD> <path>" a line, e.g. "student|GET /api/v1/me". Out: office|endpoint|statements|ms|pages|statuses.
# Needs pg_stat_statements loaded on the copy's server, and students.txt / applicants.txt from sample.sql.
cd "$(dirname "$0")" || exit 1
OUT="$1"; : > "$OUT"
psql "$COPY" -q -o /dev/null -f reset.sql
while IFS='|' read -r who spec; do
  [ -z "$who" ] && continue
  file=students.txt; [ "$who" = applicant ] && file=applicants.txt
  psql "$COPY" -q -o /dev/null -c "SELECT pg_stat_statements_reset(0, (SELECT oid FROM pg_database WHERE datname = current_database()), 0)"
  st=$(node one.mjs "$file" "$spec" "$who" "$API")
  tot=$(psql "$COPY" -t -A -F'|' -c "SELECT sum(calls), round(sum(total_exec_time)::numeric), sum(shared_blks_hit + shared_blks_read) FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database()) AND toplevel")
  echo "$who|$spec|$tot|$st" | tee -a "$OUT"
done
