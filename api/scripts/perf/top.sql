\pset format unaligned
\pset fieldsep '|'
\pset footer off
WITH s AS (
  SELECT queryid, calls, total_exec_time::numeric AS t, (shared_blks_hit + shared_blks_read)::numeric AS blks, rows, regexp_replace(query, '\s+', ' ', 'g') AS q
    FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database()) AND toplevel
)
SELECT round(100 * t / sum(t) OVER (), 1) AS pct_time, calls, round(t) AS total_ms, round(t / calls, 2) AS ms_per_call,
       round(blks / calls) AS blks_per_call, round(100 * blks / nullif(sum(blks) OVER (), 0), 1) AS pct_blks, queryid, left(q, 300) AS query
  FROM s ORDER BY t DESC LIMIT :lim;
SELECT 'TOTAL', sum(calls), round(sum(total_exec_time)::numeric), sum(shared_blks_hit + shared_blks_read)
  FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database()) AND toplevel;
