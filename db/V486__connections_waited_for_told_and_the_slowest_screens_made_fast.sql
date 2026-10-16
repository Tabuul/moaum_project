-- ═══════════════════════════════════════
-- V486 — Connections waited for told to ICT, and the slowest screens' reads made fast
--
-- Since V474/the pool watch the status page shows the database connections in use and waiting, and a screen's read stops at
-- 90 seconds. Two follow-ups:
--
--   platform.tell_pool_waiting(seconds, peak waiting, pool size)   while requests have waited for a database connection for a
--       minute or more (PoolWatch measures it), every Directorate of ICT office holder is told — e-mail, portal and text — at
--       most once an hour (template DB_POOL_WAITING). Waiting connections are what made Interswitch's PAYDirect calls time out.
--
--   Every menu page was opened on the live-shaped copy (13 October data) as an office that has it and the database's slow
--   statements logged. Three reads the screens make were over half a minute alone, each from the same mistake — a CTE
--   inlined into the caller, so a costly per-row value was worked out again for every column that read it:
--     admissions.non_sitter_post_utme (computed screening)      69 s → under 10 s
--     admissions.screening_register (screening)                 26 s → about 11 s
--     catalogue.review_summary (central course review)          28 s → under 5 s
--   Each is restated from its current definition with its CTEs MATERIALIZED and what depends only on the session or the
--   programme read once; the answers are the same, row for row (proved on the copy by md5 of every row).
--   clearance.migrated_summary (the Students page, about 39 s) reads every one of the 2.85 million clearance decisions; it is
--   left as it is, under the limit.
--
-- Nothing is written by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V486: connections waited for told to ICT; the slowest screens made fast', true);

CREATE FUNCTION platform.tell_pool_waiting(p_seconds integer, p_peak integer, p_max integer, p_at timestamptz DEFAULT now())
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE vars jsonb; r record; told int := 0;
BEGIN
    vars := jsonb_build_object(
        'SECONDS', p_seconds,
        'PEAK', p_peak,
        'POOL', p_max,
        'SINCE', to_char((p_at - make_interval(secs => p_seconds)) AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY, HH24:MI'),
        'STATUS', coalesce(platform.portal_url(), '') || '/api/v1/platform/status');
    FOR r IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
              WHERE a.office_code = 'ict' AND p.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        told := told + platform.tell_person(r.person_id, 'DB_POOL_WAITING', NULL, vars,
                                            'db-pool-waiting:' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'YYYYMMDDHH24'));
    END LOOP;
    RETURN told;
END $fn$;
COMMENT ON FUNCTION platform.tell_pool_waiting(integer, integer, integer, timestamptz) IS
  'V486: while requests wait for a database connection (PoolWatch), each Directorate of ICT office holder told — e-mail, portal and text — at most once an hour (the event key).';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('DB_POOL_WAITING', 'Database connections waited for',
 'To the Directorate of ICT, at most once an hour, while requests have waited for a database connection for a minute or more',
 'Portal busy: requests waiting for a database connection for [SECONDS] seconds',
 E'Dear [FIRST_NAME],

Since [SINCE], requests to the portal have waited for a database connection: every one of the [POOL] connections was in use, and up to [PEAK] request(s) at a time waited for one. A request that waits too long fails, and Interswitch''s PAYDirect calls time out (they wait about fifty seconds).

The status page shows the connections now and the busiest of the last hour: [STATUS]

Look in the API''s log for "database pool busy" and Hikari''s leak warnings, which name the code holding a connection longest; a screen''s read is stopped at ninety seconds. If the University''s use has outgrown the pool, raise DB_POOL_SIZE on the API service.

MOAUM Portal',
 'MOAUM Portal: requests waited [SECONDS]s for a database connection (all [POOL] in use, [PEAK] waiting). See the status page.',
 'Database connections waited for',
 'For [SECONDS] seconds every one of the [POOL] database connections was in use and up to [PEAK] request(s) waited. See the status page and the API log.',
 ARRAY['FIRST_NAME','SECONDS','PEAK','POOL','SINCE','STATUS','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH');

CREATE OR REPLACE FUNCTION admissions.non_sitter_post_utme(p_session text)
 RETURNS TABLE(jamb_reg_no text, name text, programme text, entry_mode text, olevel_total integer, olevel_ceiling integer, olevel_scaled numeric, utme integer, computed numeric, source text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V486: what depends only on the session (the O'Level ceiling, the weights) or on the programme (its code, whether it
    -- screens by examination) is read once, and each candidate's O'Level score once (MATERIALIZED): inlined, the CTEs worked
    -- the score out again for every column that read it — over a minute for a session's twelve thousand applications
    WITH k AS MATERIALIZED (
        SELECT (SELECT (r.subjects_counted * greatest(admissions.olevel_points(p_session, 'A1'), 1) + r.bonus_one_sitting)
                  FROM admissions.olevel_rule(p_session) r) AS ceiling,
               coalesce((SELECT weight_utme FROM admissions.session_policy WHERE session = p_session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 70) AS wu,
               coalesce((SELECT weight_putme FROM admissions.session_policy WHERE session = p_session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 30) AS wp),
    apps AS MATERIALIZED (
        SELECT a.id AS app_id, a.session, a.screening_score, c.jamb_key, c.jamb_reg_no,
               c.surname || ', ' || c.other_names AS cand_name, c.programme AS prog_name,
               coalesce(x.entry_mode, c.entry_mode) AS mode, coalesce(x.aggregate, c.utme_aggregate) AS utme_agg
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session AND a.submitted_at IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
    ),
    progs AS MATERIALIZED (
        SELECT n.prog_name, n.code, admissions.screened_by_exam(p_session, n.code) AS by_exam
          FROM (SELECT d.prog_name,
                       (SELECT p.code FROM ref.programme p WHERE p.name = d.prog_name ORDER BY p.archived, p.code LIMIT 1) AS code
                  FROM (SELECT DISTINCT ap.prog_name FROM apps ap) d) n
    ),
    scored AS MATERIALIZED (
        SELECT ap.*, pr.code, pr.by_exam, k.ceiling, k.wu, k.wp,
               (SELECT s.total FROM admissions.olevel_score(ap.session, ap.jamb_key, pr.code) s) AS ol_total
          FROM apps ap
          LEFT JOIN progs pr ON pr.prog_name IS NOT DISTINCT FROM ap.prog_name
          CROSS JOIN k
         WHERE NOT pr.by_exam OR ap.mode = 'DIRECT_ENTRY'
    )
    SELECT jamb_reg_no, cand_name, prog_name, mode, ol_total, ceiling,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) ELSE 0 END,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                     THEN round((utme_agg / 400.0 * 100) * wu / 100.0 + (ol_total::numeric / ceiling * 100) * wp / 100.0, 2)
                WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
                WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
                ELSE NULL END,
           CASE WHEN utme_agg IS NOT NULL AND ol_total > 0 THEN 'O''Level + UTME'
                WHEN ol_total > 0 THEN 'O''Level'
                WHEN utme_agg IS NOT NULL THEN 'UTME'
                ELSE 'none' END
      FROM scored
     ORDER BY 9 DESC NULLS LAST, 2;
$function$;

CREATE OR REPLACE FUNCTION admissions.screening_register(p_session text)
 RETURNS TABLE(jamb_reg_no text, name text, programme text, programme_code text, entry_mode text, utme integer, olevel_scaled numeric, post_utme numeric, screening numeric, source text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V486: as admissions.non_sitter_post_utme — the session's and the programme's figures read once, each candidate's
    -- O'Level score once (MATERIALIZED)
    WITH k AS MATERIALIZED (
        SELECT (SELECT (r.subjects_counted * greatest(admissions.olevel_points(p_session, 'A1'), 1) + r.bonus_one_sitting)
                  FROM admissions.olevel_rule(p_session) r) AS ceiling,
               coalesce((SELECT weight_utme FROM admissions.session_policy WHERE session = p_session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 70) AS wu,
               coalesce((SELECT weight_putme FROM admissions.session_policy WHERE session = p_session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 30) AS wp),
    apps AS MATERIALIZED (
        SELECT a.session, a.screening_score, c.jamb_key, c.jamb_reg_no,
               c.surname || ', ' || c.other_names AS cand_name, c.programme AS prog_name,
               coalesce(x.entry_mode, c.entry_mode) AS mode, coalesce(x.aggregate, c.utme_aggregate) AS utme_agg
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session AND a.submitted_at IS NOT NULL
    ),
    progs AS MATERIALIZED (
        SELECT n.prog_name, n.code, admissions.screened_by_exam(p_session, n.code) AS by_exam
          FROM (SELECT d.prog_name,
                       (SELECT p.code FROM ref.programme p WHERE p.name = d.prog_name ORDER BY p.archived, p.code LIMIT 1) AS code
                  FROM (SELECT DISTINCT ap.prog_name FROM apps ap) d) n
    ),
    scored AS MATERIALIZED (
        SELECT ap.*, pr.code, pr.by_exam, k.ceiling, k.wu, k.wp,
               (SELECT s.total FROM admissions.olevel_score(ap.session, ap.jamb_key, pr.code) s) AS ol_total
          FROM apps ap
          LEFT JOIN progs pr ON pr.prog_name IS NOT DISTINCT FROM ap.prog_name
          CROSS JOIN k
    )
    SELECT jamb_reg_no, cand_name, prog_name, code, mode,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) END AS olevel_scaled,
           screening_score::numeric AS post_utme,
           CASE
             WHEN screening_score IS NOT NULL THEN screening_score::numeric
             WHEN by_exam THEN NULL
             WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                  THEN round((utme_agg / 400.0 * 100) * wu / 100.0 + (ol_total::numeric / ceiling * 100) * wp / 100.0, 2)
             WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
             WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
             ELSE NULL END AS screening,
           CASE
             WHEN screening_score IS NOT NULL THEN 'Post-UTME'
             WHEN by_exam THEN 'Awaiting Post-UTME'
             WHEN ol_total > 0 AND utme_agg IS NOT NULL THEN 'O''Level + UTME'
             WHEN ol_total > 0 THEN 'O''Level'
             WHEN utme_agg IS NOT NULL THEN 'UTME'
             ELSE 'none' END AS source
      FROM scored
     ORDER BY prog_name, screening DESC NULLS LAST, cand_name;
$function$;

CREATE OR REPLACE FUNCTION catalogue.review_summary()
 RETURNS TABLE(total bigint, live bigint, ended bigint, not_reviewed bigint, reviewed bigint, correct bigint, incorrect_owner bigint, requires_review bigint, with_issues bigint, code_names_other bigint, owner_offers_nothing bigint, not_in_structure bigint, moved_by_rule bigint, possible_duplicates bigint, departments bigint)
 LANGUAGE sql
 STABLE
AS $function$
    -- V486: each course's issues worked out once (MATERIALIZED); inlined, catalogue.course_issues ran again for every count
    -- that reads them
    WITH c AS MATERIALIZED (SELECT code, state, review_status, dept_code, catalogue.course_issues(code) AS issues FROM catalogue.course WHERE code NOT LIKE 'DMO %')
    SELECT count(*), count(*) FILTER (WHERE state <> 'ENDED'), count(*) FILTER (WHERE state = 'ENDED'),
           count(*) FILTER (WHERE review_status = 'NOT_REVIEWED'), count(*) FILTER (WHERE review_status = 'REVIEWED'),
           count(*) FILTER (WHERE review_status = 'CORRECT'), count(*) FILTER (WHERE review_status = 'INCORRECT_OWNER'), count(*) FILTER (WHERE review_status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE cardinality(issues) > 0),
           count(*) FILTER (WHERE 'CODE_NAMES_OTHER' = ANY (issues)), count(*) FILTER (WHERE 'OWNER_OFFERS_NOTHING' = ANY (issues)),
           count(*) FILTER (WHERE 'NOT_IN_STRUCTURE' = ANY (issues)), count(*) FILTER (WHERE 'MOVED_BY_RULE' = ANY (issues)),
           count(*) FILTER (WHERE 'POSSIBLE_DUPLICATE' = ANY (issues)),
           count(DISTINCT dept_code)
      FROM c
$function$;

COMMIT;
