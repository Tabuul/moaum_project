-- V546: the live database's own slowest statements, on a screen for ICT.
--
-- The slow screens of V537 and V541 were found on a copy of the live data on the development machine, whose PostgreSQL 18 on
-- Windows ran every statement about four times slower after a few heavy ones; the live portal runs PostgreSQL 17 on Linux. What
-- the live database itself records is the measure that counts: pg_stat_statements (loaded on Railway's PostgreSQL, used by the
-- performance audit of 2 October; on AWS RDS in the default parameter group) keeps, for each statement, how often it ran and how
-- long it took.
--   * platform.slow_statements(order, min_calls, limit): the statements of this database by mean or total time — calls, mean, worst
--     and total milliseconds, rows, its share of all statement time — with the portal's functions each calls and the screens known to
--     issue it; read-only. Where pg_stat_statements is not installed, not loaded, or the portal may not read other sessions' query
--     text, it says so instead of failing.
--   * platform.statement_screen: the screens known to call each of the portal's heavier functions (from the crawl of 18 Oct 2026;
--     ICT and super may add to it).
--   * The extension is created where the database allows it (a superuser or rds_superuser); nothing else changes.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V546: the live database''s slowest statements on an ICT screen', true);

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EXCEPTION WHEN insufficient_privilege OR undefined_file OR feature_not_supported THEN
    RAISE NOTICE 'V546: pg_stat_statements could not be created here (%); the screen will say it is not available', SQLERRM;
END $$;

CREATE TABLE platform.statement_screen (
    function_name text PRIMARY KEY CHECK (function_name ~ '^[a-z_]+\.[a-z_0-9]+$'),
    screens       text NOT NULL,
    note          text,
    set_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform.statement_screen IS 'V546: the screens known to call each of the portal''s heavier functions, for naming a slow statement';
SELECT audit.attach('platform.statement_screen');

INSERT INTO platform.statement_screen (function_name, screens) VALUES
  ('finance.collection_by_faculty', 'Bursar''s dashboard · Registrar''s overview · Revenue (Internal Audit)'),
  ('finance.session_charges', 'Bursar''s dashboard · Revenue · Records & Queries (fees) · admissions pipeline'),
  ('finance.session_positions', 'College Payment Report · Student Statistics · Student Query'),
  ('finance.payment_position', 'College Payment Report (before V537) · deferments'),
  ('finance.fee_profiles', 'every fee list read at once (fee sums, charges, positions)'),
  ('finance.fee_sums', 'every fee list read at once'),
  ('finance.fee_gaps', 'Fee Setup and Schedule · Students with no school fee stated'),
  ('finance.session_fee_positions', 'fee positions of a whole register'),
  ('finance.position', 'a student''s fees page · deferments'),
  ('finance.charges', 'a student''s fees page'),
  ('finance.day_book', 'Day Book (Ledger)'),
  ('finance.payments_query', 'Payments Query'),
  ('finance.payments_breakdown', 'Payments Query'),
  ('finance.gst_population', 'GST Students · EPS Students'),
  ('finance.gst_eps_rows_all', 'GST Students · EPS Students'),
  ('admissions.pipeline_stats', 'Admissions'),
  ('admissions.putme_candidates', 'Post-UTME CBT Schedule'),
  ('admissions.putme_validate', 'Post-UTME CBT Schedule'),
  ('admissions.putme_preview', 'Post-UTME CBT Schedule'),
  ('admissions.status_checking_rows', 'Admission Status Checking'),
  ('admissions.screening_register', 'Admissions Screening'),
  ('admissions.non_sitter_post_utme', 'Computed Post-UTME'),
  ('admissions.olevel_scores', 'Admissions Screening · Computed Post-UTME'),
  ('admissions.olevel_score', 'Screened candidates · a candidate''s O''Level'),
  ('admissions.attachment_state', 'Candidate Data'),
  ('registration.voluntary_withdrawals_due', 'Student Records'),
  ('catalogue.review_summary', 'Course Ownership Review'),
  ('catalogue.course_issues_all', 'Course Ownership Review · All Courses'),
  ('catalogue.course_issues', 'All Courses (a course''s issues)'),
  ('catalogue.code_owners', 'All Courses'),
  ('assessment.scope_cgpa', 'Records & Queries (CGPA)'),
  ('people.record_issues', 'Records Check'),
  ('people.biodata_status_counts', 'Notification Templates (biodata counts)'),
  ('reporting.student_positions', 'Student Statistics'),
  ('reporting.payments', 'Financial Analytics');

-- the statements this database has run, slowest first
CREATE FUNCTION platform.slow_statements(p_order text DEFAULT 'MEAN', p_min_calls integer DEFAULT 5, p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_schema text; v_rows jsonb; v_since timestamptz; v_total numeric; v_hidden int;
        v_order text := CASE upper(coalesce(p_order, 'MEAN')) WHEN 'TOTAL' THEN 'total_exec_time' WHEN 'CALLS' THEN 'calls' WHEN 'MAX' THEN 'max_exec_time' ELSE 'mean_exec_time' END;
BEGIN
    SELECT n.nspname INTO v_schema FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_stat_statements';
    IF v_schema IS NULL THEN
        RETURN jsonb_build_object('available', false, 'reason', 'pg_stat_statements is not installed in this database', 'rows', '[]'::jsonb);
    END IF;
    BEGIN
        EXECUTE format($q$
            WITH a AS (
                SELECT x.query, x.calls, x.mean_exec_time, x.max_exec_time, x.total_exec_time, x.rows
                  FROM %1$I.pg_stat_statements x
                 WHERE x.dbid = (SELECT d.oid FROM pg_database d WHERE d.datname = current_database())
                   AND x.calls >= $1),
            s AS (
                SELECT a.* FROM a
                 WHERE a.query ~* '^\s*(select|with|insert|update|delete|merge)\M'   -- what screens run, not migrations or DDL
                   AND a.query NOT ILIKE '%%platform.slow_statements%%'),
            whole AS (SELECT coalesce((SELECT sum(s.total_exec_time) FROM s), 0) AS t,
                             (SELECT count(*) FROM a WHERE a.query = '<insufficient privilege>') AS hidden),
            top AS (SELECT s.* FROM s ORDER BY s.%2$I DESC NULLS LAST LIMIT $2)
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                       'query', left(regexp_replace(t.query, '\s+', ' ', 'g'), 1200),
                       'calls', t.calls, 'mean_ms', round(t.mean_exec_time::numeric, 1), 'max_ms', round(t.max_exec_time::numeric, 1),
                       'total_ms', round(t.total_exec_time::numeric), 'rows', t.rows,
                       'share_pct', CASE WHEN w.t > 0 THEN round((100 * t.total_exec_time / w.t)::numeric, 1) END,
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
          USING greatest(coalesce(p_min_calls, 1), 1), least(greatest(coalesce(p_limit, 100), 1), 500);
        BEGIN
            EXECUTE format('SELECT stats_reset FROM %I.pg_stat_statements_info', v_schema) INTO v_since;
        EXCEPTION WHEN OTHERS THEN v_since := NULL;
        END;
    EXCEPTION WHEN object_not_in_prerequisite_state OR undefined_function OR undefined_table OR undefined_column THEN
        RETURN jsonb_build_object('available', false, 'reason', 'pg_stat_statements is installed but not loaded by the server (shared_preload_libraries): ' || SQLERRM,
                                  'rows', '[]'::jsonb);
    END;
    RETURN jsonb_build_object('available', true, 'order', CASE v_order WHEN 'total_exec_time' THEN 'TOTAL' WHEN 'calls' THEN 'CALLS' WHEN 'max_exec_time' THEN 'MAX' ELSE 'MEAN' END, 'since', v_since, 'total_ms', round(coalesce(v_total, 0)),
                              'hidden', coalesce(v_hidden, 0) > 0, 'rows', v_rows);
END $fn$;
COMMENT ON FUNCTION platform.slow_statements(text, integer, integer) IS
  'V546: this database''s statements from pg_stat_statements, slowest first (MEAN, TOTAL, MAX or CALLS), with the portal functions each calls and the screens known to issue it; read-only';

COMMIT;
