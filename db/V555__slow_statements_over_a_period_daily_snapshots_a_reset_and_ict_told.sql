-- V555: Slow Statements over a period — daily snapshots, a reset for ICT, and ICT told when a statement turns slow.
--
-- pg_stat_statements keeps totals since its statistics were last reset: on a database that has run for months a statement that
-- has just become slow hides behind its history.
--   * platform.statement_snapshot: each day (the API's StatementSnapshots, 00:05 Lagos, and once now) every statement's calls,
--     total time and rows, kept 35 days; platform.take_statement_snapshot() takes one.
--   * platform.slow_statements(order, min_calls, limit, days): with days, each statement's calls, time and average over the last
--     day(s) — what ran since the snapshot of that many days ago (or the oldest kept); without, since the reset, as before (V546).
--     Statements are read once a statement (summed over the roles that ran it).
--   * platform.reset_statement_stats(): this database's statistics reset by ICT, kept in platform.statement_reset; refused, with
--     the reason, where the portal's role may not reset them (STATEMENTS_RESET_REFUSED).
--   * At each snapshot, a statement whose average over the last day is at least twice that of the week before (both run at least
--     20 times) and at least half a second is told to ICT (template STATEMENT_SLOWER; platform.statement_alert keeps what was told,
--     once a statement a day).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V555: Slow Statements over a period, a reset for ICT, ICT told of a statement turned slow', true);

CREATE TABLE platform.statement_snapshot (
    taken_at timestamptz NOT NULL,
    queryid  bigint NOT NULL,
    query    text NOT NULL,
    calls    bigint NOT NULL,
    total_ms numeric NOT NULL,
    rows     bigint NOT NULL,
    PRIMARY KEY (taken_at, queryid)
);
CREATE INDEX ix_statement_snapshot_query ON platform.statement_snapshot (queryid, taken_at);
COMMENT ON TABLE platform.statement_snapshot IS 'V555: each statement''s calls, total time and rows as pg_stat_statements held them at a moment; kept 35 days';

CREATE TABLE platform.statement_reset (
    reset_at timestamptz PRIMARY KEY DEFAULT clock_timestamp(),
    reset_by uuid,
    office   text,
    reason   text
);
COMMENT ON TABLE platform.statement_reset IS 'V555: when ICT reset this database''s statement statistics, and why';
SELECT audit.attach('platform.statement_reset');

CREATE TABLE platform.statement_alert (
    queryid   bigint NOT NULL,
    day       date NOT NULL,
    mean_ms   numeric NOT NULL,
    before_ms numeric NOT NULL,
    calls     bigint NOT NULL,
    told      integer NOT NULL DEFAULT 0,
    PRIMARY KEY (queryid, day)
);
COMMENT ON TABLE platform.statement_alert IS 'V555: a statement whose average over a day was at least twice the week before''s, as told to ICT';
INSERT INTO audit.exemption (relid, reason) VALUES
  ('platform.statement_snapshot'::regclass, 'V555: the database''s own statement statistics copied each night — machinery read by Slow Statements, not a decision'),
  ('platform.statement_alert'::regclass, 'V555: which statements turned slow and were told to ICT — derived from the snapshots, not a decision; the message is in the outbox');

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
  ('STATEMENT_SLOWER', 'Statements turned slow',
   'Sent to ICT after the nightly snapshot of the database''s statements when one ran, over the last day, at least twice as long on average as the week before.',
   '[COUNT] database statement(s) turned slow',
   E'Dear [FIRST_NAME],\n\nOver the last day [COUNT] of the portal''s database statements took at least twice as long on average as in the week before:\n\n[LIST]\n\nOpen Slow Statements (last day) on the portal to see them with the screens that issue them: [PORTAL_URL]\n\nMOAUM Portal',
   NULL,
   '[COUNT] statement(s) turned slow',
   'Over the last day [COUNT] database statement(s) took at least twice as long as the week before. Open Slow Statements, last day.',
   ARRAY['FIRST_NAME', 'COUNT', 'LIST', 'PORTAL_URL'], false, 'NORMAL');

-- the statements this database has run, slowest first: since the reset, or over the last days by the snapshots
DROP FUNCTION platform.slow_statements(text, integer, integer);
CREATE FUNCTION platform.slow_statements(p_order text DEFAULT 'MEAN', p_min_calls integer DEFAULT 5, p_limit integer DEFAULT 100, p_days integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_schema text; v_rows jsonb; v_since timestamptz; v_total numeric; v_hidden int; v_base timestamptz; v_period text;
        v_order text := CASE upper(coalesce(p_order, 'MEAN')) WHEN 'TOTAL' THEN 'total_ms' WHEN 'CALLS' THEN 'calls' WHEN 'MAX' THEN 'max_ms' ELSE 'mean_ms' END;
BEGIN
    SELECT n.nspname INTO v_schema FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_stat_statements';
    IF v_schema IS NULL THEN
        RETURN jsonb_build_object('available', false, 'reason', 'pg_stat_statements is not installed in this database', 'rows', '[]'::jsonb);
    END IF;
    IF p_days IS NOT NULL AND p_days > 0 THEN
        -- the snapshot of that many days ago, or the oldest kept
        SELECT coalesce((SELECT max(s.taken_at) FROM platform.statement_snapshot s WHERE s.taken_at <= now() - make_interval(days => p_days)),
                        (SELECT min(s.taken_at) FROM platform.statement_snapshot s))
          INTO v_base;
        v_period := CASE WHEN v_base IS NULL THEN 'RESET' ELSE 'DAYS' END;
    ELSE
        v_period := 'RESET';
    END IF;
    BEGIN
        EXECUTE format($q$
            WITH cur AS (
                SELECT x.queryid, min(x.query) AS query, sum(x.calls) AS calls, sum(x.total_exec_time) AS total_ms, max(x.max_exec_time) AS max_ms,
                       sum(x.rows) AS rows, bool_or(x.query = '<insufficient privilege>') AS hidden
                  FROM %1$I.pg_stat_statements x
                 WHERE x.dbid = (SELECT d.oid FROM pg_database d WHERE d.datname = current_database())
                 GROUP BY x.queryid),
            a AS (   -- over the period: what ran since the base snapshot; a statement reset since (fewer calls than then) counts from the reset
                SELECT c.queryid, c.query, c.max_ms, c.hidden,
                       CASE WHEN b.calls IS NULL OR c.calls < b.calls THEN c.calls ELSE c.calls - b.calls END AS calls,
                       CASE WHEN b.calls IS NULL OR c.calls < b.calls THEN c.total_ms ELSE c.total_ms - b.total_ms END AS total_ms,
                       CASE WHEN b.calls IS NULL OR c.calls < b.calls THEN c.rows ELSE c.rows - b.rows END AS rows
                  FROM cur c
                  LEFT JOIN platform.statement_snapshot b ON $3::timestamptz IS NOT NULL AND b.taken_at = $3 AND b.queryid = c.queryid),
            s AS (
                SELECT a.*, CASE WHEN a.calls > 0 THEN a.total_ms / a.calls END AS mean_ms FROM a
                 WHERE a.calls >= $1 AND NOT a.hidden
                   AND a.query ~* '^\s*(select|with|insert|update|delete|merge)\M'   -- what screens run, not migrations or DDL
                   AND a.query NOT ILIKE '%%platform.slow_statements%%'),
            whole AS (SELECT coalesce((SELECT sum(s.total_ms) FROM s), 0) AS t, (SELECT count(*) FROM a WHERE a.hidden) AS hidden),
            top AS (SELECT s.* FROM s ORDER BY s.%2$I DESC NULLS LAST LIMIT $2)
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'query', left(regexp_replace(t.query, '\s+', ' ', 'g'), 1200),
                       'calls', t.calls, 'mean_ms', round(t.mean_ms::numeric, 1), 'max_ms', round(t.max_ms::numeric, 1),
                       'total_ms', round(t.total_ms::numeric), 'rows', t.rows,
                       'share_pct', CASE WHEN w.t > 0 THEN round((100 * t.total_ms / w.t)::numeric, 1) END,
                       'functions', fx.names, 'screens', fx.screens)
                     ORDER BY t.%2$I DESC NULLS LAST), '[]'::jsonb),
                   (SELECT w.t FROM whole w), (SELECT w.hidden FROM whole w)
              FROM top t CROSS JOIN whole w
              LEFT JOIN LATERAL (
                  SELECT jsonb_agg(DISTINCT f.fn) AS names, jsonb_agg(DISTINCT ss.screens) FILTER (WHERE ss.screens IS NOT NULL) AS screens
                    FROM (SELECT lower(m[1] || '.' || m[2]) AS fn
                            FROM regexp_matches(t.query, '\m(admissions|assessment|catalogue|cbt|cce|college|finance|helpdesk|iam|jupeb|people|platform|policy|registration|reporting|attendance|graduation|clearance)\.([a-z_0-9]+)\s*\(', 'gi') m) f
                    LEFT JOIN platform.statement_screen ss ON ss.function_name = f.fn
                   WHERE EXISTS (SELECT 1 FROM pg_proc pr JOIN pg_namespace pn ON pn.oid = pr.pronamespace
                                  WHERE pn.nspname || '.' || pr.proname = f.fn)) fx ON true
            $q$, v_schema, v_order)
          INTO v_rows, v_total, v_hidden
          USING greatest(coalesce(p_min_calls, 1), 1), least(greatest(coalesce(p_limit, 100), 1), 500), v_base;
        BEGIN
            EXECUTE format('SELECT stats_reset FROM %I.pg_stat_statements_info', v_schema) INTO v_since;
        EXCEPTION WHEN OTHERS THEN v_since := NULL;
        END;
    EXCEPTION WHEN object_not_in_prerequisite_state OR undefined_function OR undefined_table OR undefined_column THEN
        RETURN jsonb_build_object('available', false, 'reason', 'pg_stat_statements is installed but not loaded by the server (shared_preload_libraries): ' || SQLERRM,
                                  'rows', '[]'::jsonb);
    END;
    -- ICT's reset is of this database alone, which the extension's own reset time does not show
    v_since := greatest(v_since, (SELECT max(r.reset_at) FROM platform.statement_reset r));
    RETURN jsonb_build_object('available', true,
                              'order', CASE v_order WHEN 'total_ms' THEN 'TOTAL' WHEN 'calls' THEN 'CALLS' WHEN 'max_ms' THEN 'MAX' ELSE 'MEAN' END,
                              'period', v_period, 'days', CASE WHEN v_period = 'DAYS' THEN p_days END,
                              'since', CASE WHEN v_period = 'DAYS' AND v_since IS NOT NULL AND v_since > v_base THEN v_since ELSE coalesce(v_base, v_since) END,
                              'reset_at', v_since,
                              'snapshots', (SELECT count(DISTINCT s.taken_at) FROM platform.statement_snapshot s),
                              'total_ms', round(coalesce(v_total, 0)), 'hidden', coalesce(v_hidden, 0) > 0, 'rows', v_rows);
END $fn$;
COMMENT ON FUNCTION platform.slow_statements(text, integer, integer, integer) IS
  'V546/V555: this database''s statements from pg_stat_statements, slowest first (MEAN, TOTAL, MAX or CALLS), since the reset or over the last p_days by the daily snapshots, with the portal functions each calls and the screens known to issue it; read-only';

-- a statement whose average over the last day is at least twice the week before's, told to ICT once a day
CREATE FUNCTION platform.tell_slower_statements(p_at timestamptz)
RETURNS integer
LANGUAGE plpgsql AS $fn$
DECLARE v_day timestamptz; v_week timestamptz; v_list text; v_count int; v_told int := 0; p record; v_today date := (p_at AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT max(s.taken_at) INTO v_day FROM platform.statement_snapshot s WHERE s.taken_at <= p_at - interval '20 hours';
    IF v_day IS NULL THEN RETURN 0; END IF;
    SELECT max(s.taken_at) INTO v_week FROM platform.statement_snapshot s WHERE s.taken_at <= v_day - interval '6 days';
    IF v_week IS NULL THEN RETURN 0; END IF;   -- a week of history first
    WITH d AS (
        SELECT n.queryid, n.query, n.calls - o.calls AS calls, (n.total_ms - o.total_ms) / nullif(n.calls - o.calls, 0) AS mean_ms
          FROM platform.statement_snapshot n JOIN platform.statement_snapshot o ON o.queryid = n.queryid AND o.taken_at = v_day
         WHERE n.taken_at = p_at AND n.calls - o.calls >= 20),
    w AS (
        SELECT n.queryid, (n.total_ms - o.total_ms) / nullif(n.calls - o.calls, 0) AS mean_ms
          FROM platform.statement_snapshot n JOIN platform.statement_snapshot o ON o.queryid = n.queryid AND o.taken_at = v_week
         WHERE n.taken_at = v_day AND n.calls - o.calls >= 20),
    slower AS (
        INSERT INTO platform.statement_alert (queryid, day, mean_ms, before_ms, calls)
        SELECT d.queryid, v_today, round(d.mean_ms, 1), round(w.mean_ms, 1), d.calls
          FROM d JOIN w ON w.queryid = d.queryid
         WHERE d.mean_ms >= 500 AND w.mean_ms > 0 AND d.mean_ms >= 2 * w.mean_ms
        ON CONFLICT (queryid, day) DO NOTHING
        RETURNING queryid, mean_ms, before_ms)
    SELECT count(*), string_agg(format('%s s on average, %s s the week before: %s', round(sl.mean_ms / 1000, 2), round(sl.before_ms / 1000, 2),
                                       left(regexp_replace(sn.query, '\s+', ' ', 'g'), 160)), E'\n' ORDER BY sl.mean_ms DESC)
      INTO v_count, v_list
      FROM slower sl JOIN platform.statement_snapshot sn ON sn.queryid = sl.queryid AND sn.taken_at = p_at;
    IF coalesce(v_count, 0) = 0 THEN RETURN 0; END IF;
    FOR p IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
              WHERE a.office_code = 'ict' AND pe.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        v_told := v_told + platform.tell_person(p.person_id, 'STATEMENT_SLOWER', NULL, jsonb_build_object('COUNT', v_count, 'LIST', v_list),
                                                'statements-slower:' || v_today, ARRAY['EMAIL', 'PORTAL']);
    END LOOP;
    UPDATE platform.statement_alert SET told = v_told WHERE day = v_today AND told = 0;
    RETURN v_count;
END $fn$;
COMMENT ON FUNCTION platform.tell_slower_statements(timestamptz) IS
  'V555: the statements whose average over the day before the snapshot at p_at is at least twice the week before''s (20 runs each, at least 0.5 s), kept in platform.statement_alert and told to ICT; how many';

-- the day's snapshot: every statement's calls, time and rows now; older than 35 days removed; ICT told of the slower
CREATE FUNCTION platform.take_statement_snapshot()
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE v_schema text; v_at timestamptz := clock_timestamp(); n int; v_slower int;
BEGIN
    SELECT ns.nspname INTO v_schema FROM pg_extension e JOIN pg_namespace ns ON ns.oid = e.extnamespace WHERE e.extname = 'pg_stat_statements';
    IF v_schema IS NULL THEN RETURN jsonb_build_object('available', false, 'reason', 'pg_stat_statements is not installed in this database'); END IF;
    BEGIN
        EXECUTE format($q$
            INSERT INTO platform.statement_snapshot (taken_at, queryid, query, calls, total_ms, rows)
            SELECT $1, x.queryid, left(min(x.query), 1200), sum(x.calls), sum(x.total_exec_time), sum(x.rows)
              FROM %I.pg_stat_statements x
             WHERE x.dbid = (SELECT d.oid FROM pg_database d WHERE d.datname = current_database()) AND x.queryid IS NOT NULL
               AND x.query <> '<insufficient privilege>'
             GROUP BY x.queryid
            $q$, v_schema) USING v_at;
        GET DIAGNOSTICS n = ROW_COUNT;
    EXCEPTION WHEN object_not_in_prerequisite_state OR undefined_function OR undefined_table OR undefined_column THEN
        RETURN jsonb_build_object('available', false, 'reason', 'pg_stat_statements is installed but not loaded by the server: ' || SQLERRM);
    END;
    DELETE FROM platform.statement_snapshot WHERE taken_at < v_at - interval '35 days';
    DELETE FROM platform.statement_alert WHERE day < (v_at AT TIME ZONE 'Africa/Lagos')::date - 60;
    v_slower := platform.tell_slower_statements(v_at);
    RETURN jsonb_build_object('available', true, 'taken_at', v_at, 'statements', n, 'slower', v_slower);
END $fn$;
COMMENT ON FUNCTION platform.take_statement_snapshot() IS
  'V555: every statement''s calls, total time and rows of this database kept as at now (platform.statement_snapshot, 35 days), and ICT told of those turned slow';

-- this database's statement statistics reset by ICT, with the reason
CREATE FUNCTION platform.reset_statement_stats(p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE v_schema text; v_at timestamptz;
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN
        RAISE EXCEPTION 'STATEMENTS_RESET_REASON: say why the statistics are reset' USING ERRCODE = '23514';
    END IF;
    SELECT ns.nspname INTO v_schema FROM pg_extension e JOIN pg_namespace ns ON ns.oid = e.extnamespace WHERE e.extname = 'pg_stat_statements';
    IF v_schema IS NULL THEN
        RAISE EXCEPTION 'STATEMENTS_NOT_KEPT: this database keeps no statement statistics (pg_stat_statements is not installed)' USING ERRCODE = '23514';
    END IF;
    BEGIN
        EXECUTE format('SELECT %I.pg_stat_statements_reset(0, (SELECT d.oid FROM pg_database d WHERE d.datname = current_database()), 0)', v_schema) INTO v_at;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE EXCEPTION 'STATEMENTS_RESET_REFUSED: the portal''s database role may not reset the statistics (%); the database administrator resets them, or grants it EXECUTE on pg_stat_statements_reset', SQLERRM
            USING ERRCODE = '42501';
    WHEN object_not_in_prerequisite_state OR undefined_function THEN
        RAISE EXCEPTION 'STATEMENTS_NOT_KEPT: the statistics are not kept here: %', SQLERRM USING ERRCODE = '23514';
    END;
    INSERT INTO platform.statement_reset (reset_at, reset_by, office, reason)
    VALUES (clock_timestamp(), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), btrim(p_reason));
    RETURN jsonb_build_object('reset_at', coalesce(v_at, clock_timestamp()));
END $fn$;
COMMENT ON FUNCTION platform.reset_statement_stats(text) IS
  'V555: this database''s pg_stat_statements statistics reset, with the reason (platform.statement_reset); refused where the role may not';

-- the first snapshot, so the last day reads from tomorrow
DO $$
DECLARE r jsonb;
BEGIN
    r := platform.take_statement_snapshot();
    RAISE NOTICE 'V555: first statement snapshot: %', r;
END $$;

COMMIT;
