-- Before a measured run on the copy: the sample's sessions open again, the copy's statement statistics emptied (this database's alone)
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', false), set_config('moaum.actor_office', 'ict', false),
       set_config('moaum.reason', 'perf measurement copy', false);
UPDATE platform.session s SET last_seen_at = now(), ended_at = NULL, ended_reason = NULL, absolute_end = now() + interval '30 days'
  FROM public.zz_perf_sample z WHERE s.id = z.sid;
UPDATE platform.session s SET last_seen_at = now(), ended_at = NULL, ended_reason = NULL, absolute_end = now() + interval '30 days'
  FROM public.zz_perf_applicants z WHERE s.id = z.sid;
SELECT pg_stat_statements_reset(0, (SELECT oid FROM pg_database WHERE datname = current_database()), 0);
