-- The people a replay signs in as, on a COPY of the live data (never the live database): 400 active students and 200 applicants of
-- the admission session, each with a portal session of their own (platform.session), the first-password and S3-passport steps
-- cleared for them on the copy. psql "$COPY" -v session='2026/2027' -f sample.sql writes students.txt and applicants.txt here,
-- one <id>|<session id in hex> a line, for replay.mjs, one.mjs and compare.mjs.
\set ON_ERROR_STOP 1
CREATE TABLE IF NOT EXISTS public.zz_perf_sample (student_id uuid PRIMARY KEY, sid bytea NOT NULL);
CREATE TABLE IF NOT EXISTS public.zz_perf_applicants (account_id uuid PRIMARY KEY, sid bytea NOT NULL);
DELETE FROM platform.session s USING public.zz_perf_sample z WHERE s.id = z.sid;
DELETE FROM platform.session s USING public.zz_perf_applicants z WHERE s.id = z.sid;
TRUNCATE public.zz_perf_sample, public.zz_perf_applicants;
INSERT INTO public.zz_perf_sample (student_id, sid)
SELECT s.id, gen_random_bytes(32) FROM people.student s JOIN iam.student_account a ON a.student_id = s.id
 WHERE s.duplicate_of IS NULL AND s.status = 'ACTIVE' AND s.matric_no IS NOT NULL AND s.surname NOT ILIKE 'DEMO%'
 ORDER BY md5(s.id::text || 'v-perf') LIMIT 400;
INSERT INTO public.zz_perf_applicants (account_id, sid)
SELECT a.id, gen_random_bytes(32) FROM admissions.applicant_account a WHERE a.session = :'session' AND a.candidate_id IS NOT NULL
 ORDER BY md5(a.id::text || 'v-perf') LIMIT 200;
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true), set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'perf measurement copy', true);
UPDATE iam.student_account a SET must_change = false FROM public.zz_perf_sample z WHERE a.student_id = z.student_id AND a.must_change;
UPDATE admissions.applicant_account a SET must_change_password = false FROM public.zz_perf_applicants z WHERE a.id = z.account_id AND a.must_change_password;
-- a passport kept in S3 cannot be read without the bucket: the copy shows none instead
UPDATE admissions.attachment t SET object_id = NULL FROM public.zz_perf_applicants z JOIN admissions.applicant_account a ON a.id = z.account_id
 WHERE t.session = a.session AND t.jamb_key = a.jamb_key AND t.object_id IS NOT NULL;
-- the copy's own idle limit, at its longest, so a long replay is not signed out between a person's pages
UPDATE platform.session_policy SET idle_seconds = 28800 WHERE idle_seconds <> 28800;
COMMIT;
INSERT INTO platform.session (id, person_id, active_office, absolute_end)
SELECT z.sid, z.student_id, 'student', now() + interval '30 days' FROM public.zz_perf_sample z;
INSERT INTO platform.session (id, person_id, active_office, absolute_end)
SELECT z.sid, z.account_id, 'applicant', now() + interval '30 days' FROM public.zz_perf_applicants z;
\pset tuples_only on
\pset format unaligned
\o students.txt
SELECT z.student_id || '|' || encode(z.sid, 'hex') FROM public.zz_perf_sample z;
\o applicants.txt
SELECT z.account_id || '|' || encode(z.sid, 'hex') FROM public.zz_perf_applicants z;
\o
