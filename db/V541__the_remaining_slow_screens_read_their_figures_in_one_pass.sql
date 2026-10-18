-- V541: the remaining slow screens read their figures in one pass.
--
-- After V537 the screens still over a few seconds on the live-shaped copy each worked out a figure once for every candidate,
-- student or course: the O'Level score for each of 12,649 applicants (the screening register, the computed Post-UTME), the
-- semesters a student has not registered for for each of 54,573 students (the voluntary withdrawals due, on Students), every
-- course compared with every other for a possible duplicate (the catalogue review), the owner a course code names for each of
-- 4,662 courses (the code owners), and the programme a candidate's programme name reads for each applicant (eligibility,
-- screening review, the admissions funnel). Restated here, each giving the same rows as before (compared row by row on the copy
-- with EXCEPT ALL both ways):
--   admissions.olevel_scores(session)        new: every applicant's score at once — 38,847 (key, programme) pairs the same as
--                                            admissions.olevel_score for each
--   admissions.screening_register            2.91 s → 0.77 s   (13,189 rows the same)
--   admissions.non_sitter_post_utme          2.07 s → 0.76 s   (10,925 rows the same)
--   registration.voluntary_withdrawals_due   1.35 s → 0.46 s   (11,849 rows the same)
--   catalogue.course_issues_all()            new: every course's issues at once — 4,662 courses the same as course_issues
--   catalogue.review_summary                 1.67 s → 0.19 s   (the same counts)
--   catalogue.code_owners                    1.00 s → 0.07 s   (155 prefixes the same)
--   admissions.programme_by_name             new: the programme a name reads (as admissions.programme_code_of), joined once
--   finance.fee_gaps                         its programmes' final levels held: read once a programme, not once a student
-- (median of three fresh connections each; V537's readers measured the same way: the College payment report 14.5 s → 0.75 s,
-- the admissions pipeline 8.7 s → 0.49 s, the Post-UTME desk's counts 7.9 s → 0.11 s, the collection by faculty 2.7 s → 0.72 s.)
--
-- Two things measured on the development machine are not what the live portal sees, and V537's note overstated them: there,
-- PostgreSQL 18 on Windows runs everything about four times slower in a server process that has run two or three heavy
-- statements (every node of an unchanged plan; a new connection is fast again), and PostgreSQL 18 caches the plans of a SQL
-- function that is not inlined into its caller, using a generic plan from its sixth call (admissions.olevel_scores given an
-- array: 0.45 s five times, then 19 s). The live portal runs PostgreSQL 17 on Linux, which has neither; the functions here take
-- only what they can be planned with (the session) so that an upgrade to 18 does not bring the second. See api/scripts/perf.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'super', true);
SELECT set_config('moaum.reason', 'V541: the remaining slow screens read their figures in one pass', true);

-- ── the programme a name reads, as admissions.programme_code_of reads it: the live programme first, then the code ──
CREATE VIEW admissions.programme_by_name AS
    SELECT DISTINCT ON (p.name) p.name, p.code FROM ref.programme p ORDER BY p.name, p.archived, p.code;
COMMENT ON VIEW admissions.programme_by_name IS
  'V541: the programme each programme name reads (admissions.programme_code_of''s rule), for joining a list of candidates once rather than calling that function for each';

-- ── every applicants OLevel score at once ──
-- V541: every applicant's O'Level score for a session at once — admissions.olevel_score's rule for each application's JAMB key
-- and the programme its candidate applied for (the code its name reads, as the screening functions read it). It takes only the
-- session, so it is planned with the query that reads it: on PostgreSQL 18 a SQL function that is not (an array of keys built
-- by a subquery is enough) keeps its plans in the plan cache, and from its sixth call the generic plan took 19 s, not 0.45 s
CREATE OR REPLACE FUNCTION admissions.olevel_scores(p_session text)
RETURNS TABLE (jamb_key text, programme_code text, sittings integer, relevant_known boolean, points integer, bonus integer, total integer)
LANGUAGE sql STABLE AS $$
    WITH named AS MATERIALIZED (SELECT DISTINCT ON (pp.name) pp.name, pp.code FROM ref.programme pp ORDER BY pp.name, pp.archived, pp.code),
    pairs AS MATERIALIZED (
        SELECT DISTINCT c.jamb_key AS raw_key, upper(btrim(c.jamb_key)) AS key, nm.code AS programme
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN named nm ON nm.name = c.programme
         WHERE a.session = p_session AND c.jamb_key IS NOT NULL),
    keys AS MATERIALIZED (SELECT DISTINCT key FROM pairs),
    rule AS MATERIALIZED (SELECT * FROM admissions.olevel_rule(p_session)),
    graded AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM admissions.olevel_grading g WHERE g.session = p_session) AS own),
    gp AS MATERIALIZED (SELECT x.grade, x.points FROM admissions.olevel_grade_point x WHERE x.session = p_session),
    sittings AS MATERIALIZED (
        SELECT st.id, st.jamb_key AS key, st.exam_number, st.exam_body, st.exam_year
          FROM admissions.olevel_sitting st JOIN keys k ON k.key = st.jamb_key
         WHERE st.session = p_session),
    -- the points of a grade as admissions.olevel_points reads them: the session's own table where it has one, else A1 6 … C6 1
    sat AS MATERIALIZED (
        SELECT s.key, gr.subject, gr.grade,
               CASE WHEN gd.own THEN coalesce(gp.points, 0)
                    ELSE CASE upper(btrim(gr.grade)) WHEN 'A1' THEN 6 WHEN 'B2' THEN 5 WHEN 'B3' THEN 4
                                                     WHEN 'C4' THEN 3 WHEN 'C5' THEN 2 WHEN 'C6' THEN 1 ELSE 0 END END AS pts
          FROM sittings s
          JOIN admissions.olevel_grade gr ON gr.sitting_id = s.id
          CROSS JOIN graded gd
          LEFT JOIN gp ON gp.grade = upper(btrim(gr.grade))),
    sigs AS (
        SELECT s.key,
               coalesce(nullif(upper(btrim(s.exam_number)), ''),
                        s.exam_body || '|' || coalesce(s.exam_year, '') || '|' ||
                        coalesce((SELECT string_agg(g.subject || '=' || g.grade, ',' ORDER BY g.subject, g.grade)
                                    FROM admissions.olevel_grade g WHERE g.sitting_id = s.id), '')) AS sig
          FROM sittings s),
    n AS (SELECT sg.key, count(DISTINCT sg.sig)::int AS sittings FROM sigs sg GROUP BY sg.key),
    best AS MATERIALIZED (
        SELECT s.key, s.subject, max(s.pts) AS pts, (array_agg(s.grade ORDER BY s.pts DESC, s.grade))[1] AS grade
          FROM sat s GROUP BY s.key, s.subject),
    relevant AS MATERIALIZED (
        SELECT DISTINCT g.programme_code, rs.subject
          FROM admissions.rule_subject rs
          JOIN admissions.rule_subject_group g ON g.id = rs.group_id AND g.scope = 'OLEVEL'
          JOIN admissions.session_policy p ON p.id = g.policy_id
         WHERE p.session = p_session),
    relevant_key AS MATERIALIZED (SELECT DISTINCT r.programme_code, lower(btrim(r.subject)) AS subject FROM relevant r),
    ranked AS (
        SELECT pr.raw_key, pr.programme, b.subject, b.pts,
               CASE WHEN b.subject ILIKE 'english%'
                      OR (b.subject ILIKE 'math%' AND b.subject NOT ILIKE 'further%') THEN 0
                    WHEN EXISTS (SELECT 1 FROM relevant_key rk WHERE rk.programme_code = pr.programme AND rk.subject = lower(btrim(b.subject))) THEN 1
                    ELSE 2 END AS pri
          FROM pairs pr JOIN best b ON b.key = pr.key),
    top AS (
        SELECT r.raw_key, r.programme, sum(r.pts) AS points
          FROM (SELECT x.*, row_number() OVER (PARTITION BY x.raw_key, x.programme ORDER BY x.pri, x.pts DESC, x.subject) AS rn FROM ranked x) r
         WHERE r.rn <= coalesce((SELECT rr.subjects_counted FROM rule rr), 2147483647)
         GROUP BY r.raw_key, r.programme)
    SELECT pr.raw_key, pr.programme, coalesce(n.sittings, 0),
           EXISTS (SELECT 1 FROM relevant r WHERE r.programme_code = pr.programme),
           coalesce(t.points, 0)::int,
           (CASE WHEN coalesce(n.sittings, 0) = 0 THEN 0 WHEN n.sittings = 1 THEN ru.bonus_one_sitting ELSE ru.bonus_two_sittings END)::int,
           (coalesce(t.points, 0)
              + CASE WHEN coalesce(n.sittings, 0) = 0 THEN 0 WHEN n.sittings = 1 THEN ru.bonus_one_sitting ELSE ru.bonus_two_sittings END)::int
      FROM pairs pr
      CROSS JOIN rule ru
      LEFT JOIN n ON n.key = pr.key
      LEFT JOIN top t ON t.raw_key = pr.raw_key AND t.programme IS NOT DISTINCT FROM pr.programme
$$;

-- ── the screening register ──
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
               coalesce(os.total, 0) AS ol_total   -- V541: every applicant's score read in one pass, not olevel_score for each
          FROM apps ap
          LEFT JOIN progs pr ON pr.prog_name IS NOT DISTINCT FROM ap.prog_name
          LEFT JOIN admissions.olevel_scores(p_session) os ON os.jamb_key = ap.jamb_key AND os.programme_code IS NOT DISTINCT FROM pr.code
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

-- ── the computed Post-UTME of the candidates who do not sit it ──
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
               coalesce(os.total, 0) AS ol_total   -- V541: every applicant's score read in one pass, not olevel_score for each
          FROM apps ap
          LEFT JOIN progs pr ON pr.prog_name IS NOT DISTINCT FROM ap.prog_name
          LEFT JOIN admissions.olevel_scores(p_session) os ON os.jamb_key = ap.jamb_key AND os.programme_code IS NOT DISTINCT FROM pr.code
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

-- ── the voluntary withdrawals due ──
-- the students due a voluntary withdrawal — four or more closed semesters missed — read in one pass: the rule of
-- registration.semesters_unregistered for every student at once, not that function once a student
CREATE OR REPLACE FUNCTION registration.voluntary_withdrawals_due()
 RETURNS TABLE(student_id uuid, number text, surname text, other_names text, programme_code text, programme text, current_level integer, status text, semesters integer, last_registered text, first_missed text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS MATERIALIZED (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.programme_code, p.name AS programme,
               s.current_level, s.status, s.entry_session,
               CASE coalesce(s.entry_mode, '') WHEN 'CCE' THEN 'CCE' WHEN 'POSTGRADUATE' THEN 'PG' ELSE 'FT' END AS cal
          FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.status IN ('ADMITTED','ACTIVE','PROBATION','DORMANT')),
    -- the semesters each calendar has closed: the full-time calendar's, the School of Postgraduate Studies', the CCE's (V380, V389)
    closed AS MATERIALIZED (
        SELECT 'FT' AS cal, c.session, c.semester FROM registration.closed_semesters() c
        UNION ALL
        SELECT 'PG', ps.session, ps.number FROM admissions.pg_semester ps WHERE ps.state = 'CLOSED' OR ps.registration_closes < current_date
        UNION ALL
        SELECT 'CCE', rs.session, rs.number FROM policy.route_semester rs
         WHERE rs.route = 'CCE' AND (rs.state = 'CLOSED' OR coalesce(rs.late_registration_closes, rs.registration_closes) < current_date)),
    reg AS MATERIALIZED (
        SELECT r.student_id, r.session, r.semester FROM registration.course_registration r WHERE r.status IN ('APPROVED','LOCKED')
        UNION ALL   -- V389: and a postgraduate student's registration on the School's old coursework
        SELECT g.student_id, g.session, g.semester FROM admissions.pg_registration g WHERE g.state IN ('SUBMITTED', 'ENDORSED')),
    -- a closed semester is missed when no registration is at or after it: the latest registration with a semester decides,
    -- and one without a semester counts only for the sessions before its own (as the row comparison reads it)
    latest AS MATERIALIZED (
        SELECT DISTINCT ON (r.student_id) r.student_id, r.session, r.semester
          FROM reg r WHERE r.semester IS NOT NULL ORDER BY r.student_id, r.session DESC, r.semester DESC),
    latest_open AS MATERIALIZED (SELECT r.student_id, max(r.session) AS session FROM reg r WHERE r.semester IS NULL GROUP BY r.student_id),
    shown AS MATERIALIZED (   -- the last registration as the record words it
        SELECT DISTINCT ON (r.student_id) r.student_id, r.session, r.semester FROM reg r ORDER BY r.student_id, r.session DESC, r.semester DESC),
    missed AS (
        SELECT t.id, c.session, c.semester
          FROM st t
          JOIN closed c ON c.cal = t.cal
          LEFT JOIN latest l ON l.student_id = t.id
          LEFT JOIN latest_open lo ON lo.student_id = t.id
         WHERE c.session >= t.entry_session
           AND NOT ((l.session, l.semester) >= (c.session, c.semester) IS TRUE OR lo.session > c.session IS TRUE)
           -- a semester set aside by an approved deferment was not missed
           AND NOT EXISTS (SELECT 1 FROM people.deferment d WHERE d.student_id = t.id AND d.session = c.session
                             AND d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (d.kind = 'SESSION' OR d.semester = c.semester))),
    word AS (SELECT 1 AS n, 'first' AS w UNION ALL SELECT 2, 'second' UNION ALL SELECT 3, 'third'),
    tally AS (
        SELECT m.id, count(*)::int AS semesters,
               (array_agg(m.session || ' ' || coalesce(w.w, m.semester::text) || ' semester' ORDER BY m.session, m.semester))[1] AS first_missed
          FROM missed m LEFT JOIN word w ON w.n = m.semester
         GROUP BY m.id)
    SELECT t.id, t.number, t.surname, t.other_names, t.programme_code, t.programme, t.current_level, t.status, ty.semesters,
           sh.session || ' ' || coalesce(w.w, sh.semester::text) || ' semester', ty.first_missed
      FROM st t
      JOIN tally ty ON ty.id = t.id
      LEFT JOIN shown sh ON sh.student_id = t.id
      LEFT JOIN word w ON w.n = sh.semester
     WHERE ty.semesters >= 4
     ORDER BY t.programme_code, t.current_level, t.surname, t.other_names
$function$;

-- ── every courses issues at once ──
-- every course's issues at once — catalogue.course_issues' six tests by joins and counts: the owner the code names read once a
-- prefix, a possible duplicate found by counting the live courses that share the code's key or the title's key at the same level
-- and semester (each course compared with every other took the catalogue review 7–10 s)
CREATE OR REPLACE FUNCTION catalogue.course_issues_all()
RETURNS TABLE (code text, issues text[])
LANGUAGE sql STABLE AS $$
    WITH c AS MATERIALIZED (
        SELECT x.id, x.code, x.general_office, x.kind, x.dept_code, x.state, x.review_status, x.level, x.semester,
               catalogue.code_prefix(x.code) AS prefix, catalogue.code_key(x.code) AS ckey, catalogue.title_key(x.title) AS tkey,
               (x.code NOT LIKE 'DMO %' AND x.state <> 'ENDED') IS TRUE AS live
          FROM catalogue.course x),
    -- the department the code names, which depends on its prefix alone
    named AS MATERIALIZED (
        SELECT d.prefix, catalogue.course_owner_by_code(d.code) AS owner
          FROM (SELECT DISTINCT ON (c.prefix) c.prefix, c.code FROM c ORDER BY c.prefix, c.code) d),
    offered AS MATERIALIZED (
        SELECT co.course_code, bool_or(p.dept_code = cc.dept_code) AS own_dept
          FROM catalogue.course_offer co
          JOIN c cc ON cc.code = co.course_code
          LEFT JOIN ref.programme p ON p.code = co.programme_code
         GROUP BY co.course_code),
    moved AS MATERIALIZED (
        SELECT DISTINCT ON (h.course_id) h.course_id, h.source FROM catalogue.course_owner_history h ORDER BY h.course_id, h.changed_at DESC),
    by_code AS MATERIALIZED (SELECT c.ckey, count(*) AS n FROM c WHERE c.live GROUP BY c.ckey),
    by_title AS MATERIALIZED (
        SELECT c.tkey, c.level, c.semester, count(*) AS n FROM c
         WHERE c.live AND c.level IS NOT NULL AND c.semester IS NOT NULL GROUP BY c.tkey, c.level, c.semester)
    SELECT c.code, array_remove(ARRAY[
        CASE WHEN c.general_office IS NULL AND coalesce(c.kind, '') <> 'GST'
              AND nm.owner IS NOT NULL AND nm.owner <> c.dept_code THEN 'CODE_NAMES_OTHER' END,
        CASE WHEN c.general_office IS NULL AND o.course_code IS NOT NULL AND NOT coalesce(o.own_dept, false) THEN 'OWNER_OFFERS_NOTHING' END,
        CASE WHEN c.state <> 'ENDED' AND o.course_code IS NULL THEN 'NOT_IN_STRUCTURE' END,
        CASE WHEN m.source = 'CODE' AND c.review_status = 'NOT_REVIEWED' THEN 'MOVED_BY_RULE' END,
        CASE WHEN coalesce(bc.n, 0) - CASE WHEN c.live THEN 1 ELSE 0 END > 0
               OR coalesce(bt.n, 0) - CASE WHEN c.live AND c.level IS NOT NULL AND c.semester IS NOT NULL THEN 1 ELSE 0 END > 0 THEN 'POSSIBLE_DUPLICATE' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.dept_code AND d.ended_on IS NULL) THEN 'OWNER_NOT_LIVE' END
    ], NULL)
      FROM c
      LEFT JOIN named nm ON nm.prefix IS NOT DISTINCT FROM c.prefix
      LEFT JOIN offered o ON o.course_code = c.code
      LEFT JOIN moved m ON m.course_id = c.id
      LEFT JOIN by_code bc ON bc.ckey = c.ckey
      LEFT JOIN by_title bt ON bt.tkey = c.tkey AND bt.level = c.level AND bt.semester = c.semester
$$;

-- ── the catalogue review summary and the code owners ──
CREATE OR REPLACE FUNCTION catalogue.review_summary()
 RETURNS TABLE(total bigint, live bigint, ended bigint, not_reviewed bigint, reviewed bigint, correct bigint, incorrect_owner bigint, requires_review bigint, with_issues bigint, code_names_other bigint, owner_offers_nothing bigint, not_in_structure bigint, moved_by_rule bigint, possible_duplicates bigint, departments bigint)
 LANGUAGE sql
 STABLE
AS $function$
    -- V486: each course's issues worked out once (MATERIALIZED); inlined, catalogue.course_issues ran again for every count
    -- that reads them
    -- V541: every course's issues read at once (catalogue.course_issues_all), not catalogue.course_issues for each course
    WITH c AS MATERIALIZED (SELECT x.code, x.state, x.review_status, x.dept_code, ci.issues
                              FROM catalogue.course x JOIN catalogue.course_issues_all() ci ON ci.code = x.code WHERE x.code NOT LIKE 'DMO %')
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

CREATE OR REPLACE FUNCTION catalogue.code_owners()
 RETURNS TABLE(prefix text, courses bigint, live_courses bigint, is_department boolean, mapped_dept text, owner_by_code text, owner_name text, owners_now text, astray bigint, note text, set_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH c AS MATERIALIZED (
        SELECT catalogue.code_prefix(code) AS prefix, code, dept_code, state, general_office, kind
          FROM catalogue.course WHERE code NOT LIKE 'DMO %'
    ),
    -- V541: the department a prefix names read once a prefix, not catalogue.course_owner_by_code for every course of it
    own AS MATERIALIZED (
        SELECT p.prefix, catalogue.course_owner_by_code(p.prefix || ' 000') AS owner FROM (SELECT DISTINCT c.prefix FROM c WHERE c.prefix IS NOT NULL) p)
    SELECT c.prefix, count(*), count(*) FILTER (WHERE c.state <> 'ENDED'),
           EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.prefix AND d.ended_on IS NULL),
           x.dept_code,
           ow.owner,
           (SELECT d.name FROM ref.department d WHERE d.code = ow.owner),
           string_agg(DISTINCT c.dept_code, ', ' ORDER BY c.dept_code),
           count(*) FILTER (WHERE c.state <> 'ENDED' AND c.general_office IS NULL AND coalesce(c.kind, '') <> 'GST'
                              AND ow.owner IS NOT NULL
                              AND c.dept_code <> ow.owner),
           x.note, x.set_at
      FROM c JOIN own ow ON ow.prefix = c.prefix LEFT JOIN ref.course_prefix x ON x.prefix = c.prefix
     WHERE c.prefix IS NOT NULL
     GROUP BY c.prefix, x.dept_code, x.note, x.set_at, ow.owner
     ORDER BY c.prefix
$function$;

-- ── the students with no fee stated: each programme's final level read once ──
CREATE OR REPLACE FUNCTION finance.fee_gaps(p_session text)
 RETURNS TABLE(faculty_code text, faculty text, programme_code text, programme text, level integer, entry_mode text, indigene boolean, spillover boolean, students bigint, charged_as text, stated boolean, missing integer[])
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_sem AS (SELECT coalesce(array_agg(sm.number ORDER BY sm.number), '{}'::int[]) AS nums
                   FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'),
    -- V541/V542: held, so the final level is read once a programme; inlined, it was read for every student joined to it
    fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    live AS (
        SELECT s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               coalesce(s.current_level > fl.final, false) AS is_spill
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN fl ON fl.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND s.entry_mode IS DISTINCT FROM 'CCE'
           AND NOT people.is_postgraduate(s.entry_mode, p.category)
           AND p_session >= coalesce(finance.schedule_from(), p_session)),
    src AS (SELECT x.faculty_code, x.source_code FROM finance.fee_sources(p_session) x),
    grp AS (
        -- the faculty a group is charged as is read once per group, before the lines are matched
        SELECT a.*, fs.source_code AS src
          FROM (SELECT l.programme_code, l.faculty_code, l.category, l.current_level, l.entry_mode, l.indigene, l.is_spill, count(*) AS students
                  FROM live l
                 GROUP BY l.programme_code, l.faculty_code, l.category, l.current_level, l.entry_mode, l.indigene, l.is_spill) a
          LEFT JOIN src fs ON fs.faculty_code = a.faculty_code),
    matched AS (
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, g.is_spill, f.semester
          FROM grp g
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
          LEFT JOIN ref.fee_group fg ON fg.code = f.fee_group
         WHERE f.spillover = g.is_spill
           AND (g.is_spill OR f.level IS NULL OR f.level = g.current_level)
           AND ((f.entry_mode IS NULL AND g.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = g.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = g.faculty_code OR (f.faculty_code = g.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = g.programme_code)
           AND (f.fee_group IS NULL OR fg.applies_category IS NULL OR fg.applies_category = g.category)
           AND finance.pg_line(g.entry_mode = 'POSTGRADUATE' OR g.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, fg.applies_category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = g.indigene)),
    stated AS (
        SELECT m.programme_code, m.current_level, m.entry_mode, m.indigene, m.is_spill,
               bool_or(m.semester IS NULL) AS whole,
               coalesce(array_agg(DISTINCT m.semester) FILTER (WHERE m.semester IS NOT NULL), '{}'::int[]) AS sems
          FROM matched m
         GROUP BY m.programme_code, m.current_level, m.entry_mode, m.indigene, m.is_spill),
    judged AS (
        SELECT g.programme_code, g.faculty_code, g.current_level, g.entry_mode, g.indigene, g.is_spill, g.students, g.src,
               st.programme_code IS NOT NULL AS has_line,
               CASE WHEN st.programme_code IS NULL THEN NULL::int[]
                    WHEN st.whole THEN '{}'::int[]
                    ELSE coalesce((SELECT array_agg(n ORDER BY n) FROM unnest((SELECT o.nums FROM open_sem o)) n
                                    WHERE NOT n = ANY (st.sems)), '{}'::int[]) END AS missing
          FROM grp g
          LEFT JOIN stated st ON st.programme_code = g.programme_code
                             AND st.current_level IS NOT DISTINCT FROM g.current_level
                             AND st.entry_mode IS NOT DISTINCT FROM g.entry_mode
                             AND st.indigene IS NOT DISTINCT FROM g.indigene
                             AND st.is_spill = g.is_spill)
    SELECT j.faculty_code, fa.name, j.programme_code, p.name, j.current_level, j.entry_mode, j.indigene, j.is_spill, j.students,
           j.src, j.has_line, j.missing
      FROM judged j
      JOIN ref.programme p ON p.code = j.programme_code
      LEFT JOIN ref.faculty fa ON fa.code = j.faculty_code
     WHERE NOT j.has_line OR cardinality(j.missing) > 0
     ORDER BY j.faculty_code, j.programme_code, j.current_level, j.entry_mode, j.indigene, j.is_spill
$function$;

COMMIT;
