-- which functions a statement calls, how often and for how long (functions inlined into the plan are not listed):
-- psql -v q="<statement>" -f fnstats.sql ; the statement runs three times first, so the figures are a warm connection's
\set ON_ERROR_STOP 1
SET track_functions = 'all';
SELECT 1 FROM (:q) w LIMIT 0;
:q;
:q;
BEGIN;
\timing on
:q;
\timing off
SELECT f.schemaname || '.' || f.funcname AS function, f.calls, round(f.total_time::numeric) AS total_ms, round(f.self_time::numeric) AS self_ms
  FROM pg_stat_xact_user_functions f ORDER BY f.self_time DESC LIMIT 12;
ROLLBACK;
