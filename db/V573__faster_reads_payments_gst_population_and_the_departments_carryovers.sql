-- V573: four slow reads made faster, each returning the same rows (checked row for row on the live-shaped copy of 19 October 2026).
--
--   * finance.payments_query (Finance → Payments): the matching payments read narrow — reference, time, amount — for the count, the
--     total and the newest page; only the page's rows (500) joined to the student and the programme, not every match built in full
--     and sorted; payments confirmed at the same moment now in a stable order (by reference). Unfiltered 0.67 s to 0.54 s locally.
--   * finance.payments_breakdown: totalled once by category and faculty, each list summed from those groups; 0.66 s to 0.38 s.
--     Both work out each payment purpose's category once (some eighty purposes), not once a payment (some 264,000).
--   * finance.gst_population (the GST/EPS fee page and the GST and EPS student lists): the GST fee each (programme, faculty, level,
--     entry mode) is charged matched once a combination (some 600), not once a student (some 51,000). The rest of its time is the
--     GST/EPS engine over the whole register (V468), unchanged.
--   * registration.carryover_students(department): the department's current students owing a carryover, registration.carryovers'
--     rule read for the whole department at once — each sheet's latest scores once, assessment.course_final's choice of sitting, a
--     published F or recorded absence not passed since, never an elective — for the Head of Department's home, which called
--     registration.carryovers for each student: 12 s to under 1 s for the largest department (4,807 students), the same students
--     in every department.
--
-- Each function is restated from its current text with only that change.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V573: faster reads, the same rows', true);

CREATE OR REPLACE FUNCTION finance.payments_query(p_session text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text, p_dept text DEFAULT NULL::text, p_programme text DEFAULT NULL::text, p_level integer DEFAULT NULL::integer, p_category text DEFAULT NULL::text, p_channel text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 500)
 RETURNS TABLE(reference text, confirmed_at timestamp with time zone, payer text, number text, programme_code text, programme text, dept_code text, dept text, faculty_code text, faculty text, level integer, purpose text, category text, channel text, amount numeric, receipt_no text, session text, match_count bigint, match_total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    -- V573: each purpose's category worked out once (some eighty), not once a confirmed payment (some 264,000)
    WITH cat AS MATERIALIZED (SELECT x.purpose, finance.payment_category(x.purpose) AS category
                                FROM (SELECT DISTINCT r.purpose FROM finance.payment_reference r WHERE r.confirmed_at IS NOT NULL) x)
    -- V573: the payments matching, read narrow (reference, time, amount); the count and the total from them, and only the page's
    -- rows (500 by default) joined to the student and the programme — not every match built in full and sorted for the newest
    , hit AS MATERIALIZED (
        SELECT r.reference, r.confirmed_at, r.amount, coalesce(cat.category, 'Other') AS category
          FROM finance.payment_reference r
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN cat ON cat.purpose = r.purpose
         WHERE r.confirmed_at IS NOT NULL
           AND (p_session   IS NULL OR r.session = p_session)
           AND (p_faculty   IS NULL OR f.code = p_faculty)
           AND (p_dept      IS NULL OR d.code = p_dept)
           AND (p_programme IS NULL OR p.code = p_programme)
           AND (p_level     IS NULL OR s.current_level = p_level)
           AND (p_channel   IS NULL OR r.channel = p_channel)
           AND (p_category  IS NULL OR coalesce(cat.category, 'Other') = p_category)
           AND (p_from      IS NULL OR r.confirmed_at::date >= p_from)
           AND (p_to        IS NULL OR r.confirmed_at::date <= p_to)),
    tot AS (SELECT count(*) AS n, coalesce(sum(h.amount), 0) AS total FROM hit h),
    -- the newest first; payments confirmed at the same moment (an old-portal load) in a stable order
    top AS (SELECT h.reference, h.confirmed_at, h.category FROM hit h
             ORDER BY h.confirmed_at DESC, h.reference DESC
             LIMIT greatest(1, least(coalesce(p_limit, 500), 2000)))
    SELECT r.reference, r.confirmed_at,
           s.surname || ', ' || s.other_names AS payer,
           coalesce(s.matric_no, s.admission_no) AS number,
           p.code, p.name, d.code, d.name, f.code, f.name, s.current_level,
           r.purpose, t.category, r.channel, r.amount, r.receipt_no, r.session,
           tot.n AS match_count, tot.total AS match_total
      FROM top t
      JOIN finance.payment_reference r ON r.reference = t.reference
      JOIN people.student s ON s.id = r.student_id
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN ref.department d ON d.code = p.dept_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      CROSS JOIN tot
     ORDER BY t.confirmed_at DESC, t.reference DESC
$function$;

CREATE OR REPLACE FUNCTION finance.payments_breakdown(p_session text DEFAULT NULL::text, p_faculty text DEFAULT NULL::text, p_dept text DEFAULT NULL::text, p_programme text DEFAULT NULL::text, p_level integer DEFAULT NULL::integer, p_category text DEFAULT NULL::text, p_channel text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(dim text, label text, cnt bigint, total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    -- V573: each purpose's category worked out once (some eighty), not once a confirmed payment (some 264,000)
    WITH cat AS MATERIALIZED (SELECT x.purpose, finance.payment_category(x.purpose) AS category
                                FROM (SELECT DISTINCT r.purpose FROM finance.payment_reference r WHERE r.confirmed_at IS NOT NULL) x)
    -- V573: the matches totalled once by category and faculty (a few hundred groups), each list summed from those
    , base AS MATERIALIZED (
        SELECT coalesce(cat.category, 'Other') AS category, f.name AS faculty, count(*) AS n, sum(r.amount) AS amount
          FROM finance.payment_reference r
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN cat ON cat.purpose = r.purpose
         WHERE r.confirmed_at IS NOT NULL
           AND (p_session   IS NULL OR r.session = p_session)
           AND (p_faculty   IS NULL OR f.code = p_faculty)
           AND (p_dept      IS NULL OR d.code = p_dept)
           AND (p_programme IS NULL OR p.code = p_programme)
           AND (p_level     IS NULL OR s.current_level = p_level)
           AND (p_channel   IS NULL OR r.channel = p_channel)
           AND (p_category  IS NULL OR coalesce(cat.category, 'Other') = p_category)
           AND (p_from      IS NULL OR r.confirmed_at::date >= p_from)
           AND (p_to        IS NULL OR r.confirmed_at::date <= p_to)
         GROUP BY 1, 2)
    SELECT 'category', category, sum(n)::bigint, coalesce(sum(amount), 0) FROM base GROUP BY category
    UNION ALL
    SELECT 'faculty', faculty, sum(n)::bigint, coalesce(sum(amount), 0) FROM base GROUP BY faculty
    ORDER BY 1, 4 DESC
$function$;

CREATE OR REPLACE FUNCTION finance.gst_population(p_session text, p_semester integer)
 RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, status text, entry_mode text, required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamp with time zone, gst_registered boolean, eps_registered boolean, gst_courses integer, eps_courses integer, registered_at timestamp with time zone, pay_source text, gst_required boolean, eps_required boolean, gst_reason text, eps_reason text, gst_carryover boolean, eps_carryover boolean, gst_completed boolean, eps_completed boolean, gst_owed text, eps_owed text, review boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH base AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex,
               p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.programme_code, p.name AS programme,
               s.current_level AS level, s.status, s.entry_mode
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = d.faculty_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND s.entry_mode IS DISTINCT FROM 'CCE'),   -- V380
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session AND o.stream = 'REGULAR') AS gst_run),
    -- the engine over the whole register at once; a semester asked for narrows what is owed to the courses run in it
    eng AS (SELECT r.student_id, r.office, r.source, r.status, r.course_code,
                   (r.counts AND (p_semester IS NULL OR p_semester = ANY (r.semesters))) AS due
              FROM finance.gst_eps_rows_all(p_session) r),   -- V468: the whole register, planned without nested loops
    req AS (SELECT x.student_id,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'GST'), false) AS g_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'GST'), false) AS g_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'GST'), false) AS g_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'GST'), false) AS g_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'GST'), false) AS g_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'GST' AND x.due), false) AS g_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'GST' AND x.due) AS g_owed,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'EPS'), false) AS e_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'EPS'), false) AS e_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'EPS'), false) AS e_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'EPS'), false) AS e_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'EPS'), false) AS e_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'EPS' AND x.due), false) AS e_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'EPS' AND x.due) AS e_owed
              FROM eng x GROUP BY x.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM finance.gst_fee f WHERE f.session = p_session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    -- V573: the fee each (programme, faculty, level, entry mode) is charged, matched once a combination (some 600) rather than once a
    -- student (some 51,000): the same lateral match, read by key
    fkeys AS MATERIALIZED (
        SELECT k.programme_code, k.faculty_code, k.level, k.entry_mode, fr.id, fr.amount
          FROM (SELECT DISTINCT s.programme_code, p.faculty_code, s.current_level AS level, s.entry_mode
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
                 WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND s.entry_mode IS DISTINCT FROM 'CCE') k
          LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                              WHERE (f.programme_code IS NULL OR f.programme_code = k.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = k.faculty_code)
                                AND (f.level IS NULL OR f.level = k.level) AND (f.entry_mode IS NULL OR f.entry_mode = k.entry_mode)
                              ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                              LIMIT 1) fr ON true),
    -- V367: net of the refunds approved or paid against each payment; a payment refunded in full no longer counts
    refunded AS (SELECT rf.source_reference AS reference, sum(rf.amount) AS amount FROM finance.refund rf
                  WHERE rf.state IN ('APPROVED', 'PAID') AND rf.source_reference IS NOT NULL GROUP BY rf.source_reference),
    net AS (SELECT r.student_id, r.reference, r.channel, r.confirmed_at, r.amount - coalesce(x.amount, 0) AS amount
              FROM finance.payment_reference r LEFT JOIN refunded x ON x.reference = r.reference
             WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.amount > coalesce(x.amount, 0)),
    pays AS (SELECT r.student_id, sum(r.amount) AS paid, max(r.confirmed_at) AS paid_at, count(*) AS n,
                    (array_agg(r.reference ORDER BY r.confirmed_at DESC))[1] AS reference,
                    (array_agg(r.channel ORDER BY r.confirmed_at DESC))[1] AS channel
               FROM net r
              GROUP BY r.student_id),
    -- V367: a payment no course requires stays in review until the Bursary decides it
    undecided AS (SELECT DISTINCT r.student_id FROM net r
                   WHERE NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                                      WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED'))),
    pend AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()),
    regs AS (SELECT cr.student_id,
                    count(*) FILTER (WHERE c.general_office = 'GST') AS gst_courses,
                    count(*) FILTER (WHERE c.general_office = 'EPS') AS eps_courses,
                    min(cr.submitted_at) AS registered_at
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
               JOIN catalogue.offering o ON o.id = e.offering_id
               JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
              WHERE cr.session = p_session AND (p_semester IS NULL OR cr.semester = p_semester)
              GROUP BY cr.student_id),
    j AS (SELECT b.*, coalesce(q.g_req, false) AS g_req, coalesce(q.e_req, false) AS e_req,
                 (coalesce(q.g_req, false) OR (coalesce(q.e_req, false) AND cfg.covers_eps)) AS req,
                 q.g_off, q.g_carry, q.g_reg, q.g_done, q.g_none, q.g_complete, q.g_owed,
                 q.e_off, q.e_carry, q.e_reg, q.e_done, q.e_none, q.e_complete, q.e_owed,
                 fr.id AS fee_id, fr.amount AS fee_amount, py.paid, py.paid_at, py.n, py.reference, py.channel, pd.student_id AS pending,
                 rg.gst_courses, rg.eps_courses, rg.registered_at, run.gst_run AS run_on, (ud.student_id IS NOT NULL) AS undecided
            FROM base b
            CROSS JOIN cfg CROSS JOIN run
            LEFT JOIN req q ON q.student_id = b.id
            LEFT JOIN fkeys fr ON fr.programme_code = b.programme_code AND coalesce(fr.faculty_code, '') = coalesce(b.faculty_code, '')
                              AND coalesce(fr.level, -1) = coalesce(b.level, -1) AND coalesce(fr.entry_mode, '') = coalesce(b.entry_mode, '')
            LEFT JOIN pays py ON py.student_id = b.id
            LEFT JOIN pend pd ON pd.student_id = b.id
            LEFT JOIN regs rg ON rg.student_id = b.id
            LEFT JOIN undecided ud ON ud.student_id = b.id)
    SELECT j.id, j.number, j.surname, j.other_names, j.sex, j.faculty_code, j.faculty, j.dept_code, j.department, j.programme_code, j.programme,
           j.level, j.status, j.entry_mode,
           j.req,
           coalesce(j.fee_amount, 0), (j.fee_id IS NOT NULL),
           coalesce(j.paid, 0),
           (coalesce(j.n, 0) > 0 OR (j.fee_id IS NOT NULL AND j.fee_amount = 0)),
           CASE WHEN coalesce(j.n, 0) > 0 THEN 'PAID'
                WHEN NOT j.req THEN 'NOT_REQUIRED'
                WHEN j.fee_id IS NOT NULL AND j.fee_amount = 0 THEN 'EXEMPT'
                WHEN j.fee_id IS NULL THEN 'NOT_STATED'
                WHEN j.pending IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           j.reference, j.paid_at,
           coalesce(j.gst_courses, 0) > 0, coalesce(j.eps_courses, 0) > 0, coalesce(j.gst_courses, 0)::int, coalesce(j.eps_courses, 0)::int, j.registered_at,
           CASE WHEN j.n IS NULL THEN NULL WHEN j.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           j.g_req, j.e_req,
           finance.gst_eps_reason('GST', coalesce(j.g_off, false), coalesce(j.g_carry, false), coalesce(j.g_reg, false), coalesce(j.g_done, false), coalesce(j.g_none, false)),
           finance.gst_eps_reason('EPS', coalesce(j.e_off, false), coalesce(j.e_carry, false), coalesce(j.e_reg, false), coalesce(j.e_done, false), coalesce(j.e_none, false)),
           coalesce(j.g_carry, false), coalesce(j.e_carry, false), coalesce(j.g_complete, false), coalesce(j.e_complete, false),
           j.g_owed, j.e_owed,
           (coalesce(j.n, 0) > 0 AND NOT j.req AND j.run_on AND j.undecided)
      FROM j
$function$;

-- the department's current students (active, on probation) owing at least one carryover — registration.carryovers' rule read for the
-- whole department at once: each sheet's latest scores read once (not once a student), assessment.course_final's choice of sitting
-- (a published special or re-sit the student sat supersedes the Main), a published F or recorded absence not passed since, never an
-- elective for the student's programme
CREATE FUNCTION registration.carryover_students(p_dept text)
RETURNS TABLE (student_id uuid)
LANGUAGE sql STABLE AS $fn$
    WITH st AS MATERIALIZED (
        SELECT s.id, s.programme_code FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE p.dept_code = p_dept AND s.status IN ('ACTIVE', 'PROBATION')),
    -- the entries assessment.student_results reads: approved or locked registrations, registered or approved entries
    ent AS MATERIALIZED (
        SELECT st.id AS student_id, r.session, r.semester, o.id AS offering_id, o.course_code
          FROM st
          JOIN registration.course_registration r ON r.student_id = st.id AND r.status IN ('APPROVED', 'LOCKED')
          JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code),
    sheets AS MATERIALIZED (
        SELECT sh.id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
          FROM assessment.score_sheet sh
          LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
         WHERE sh.offering_id IN (SELECT x.offering_id FROM ent x)),
    scores AS MATERIALIZED (
        SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome
          FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls
         WHERE ls.student_id IN (SELECT st.id FROM st)),
    sitting AS (
        SELECT x.student_id, x.session, x.semester, x.offering_id, x.course_code, sh.stage, sh.kind, sc.points, sc.outcome,
               CASE sh.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
          FROM ent x
          JOIN sheets sh ON sh.offering_id = x.offering_id
          LEFT JOIN scores sc ON sc.sheet_id = sh.id AND sc.student_id = x.student_id),
    fin AS (
        SELECT DISTINCT ON (x.student_id, x.offering_id, x.session, x.semester) x.*
          FROM sitting x
         WHERE (x.kind IN ('SPECIAL', 'RESIT') AND x.stage = 'PUBLISHED' AND x.outcome IS NOT NULL) OR x.kind = 'MAIN'
         ORDER BY x.student_id, x.offering_id, x.session, x.semester, x.pr),
    res AS (
        SELECT f.student_id, f.course_code, f.session, f.semester,
               coalesce(f.stage = 'PUBLISHED' AND (f.outcome = 'ABSENT' OR (f.outcome = 'GRADED' AND f.points = 0)), false) AS failed,
               coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points > 0, false) AS passed
          FROM fin f),
    -- each course's last failure and last pass, in order ('2024/2025:02'): a failure is owed when no pass comes after it, so the
    -- course is owed when its last failure is not followed by a pass
    agg AS (SELECT r.student_id, r.course_code,
                   max(r.session || ':' || lpad(r.semester::text, 2, '0')) FILTER (WHERE r.failed) AS last_fail,
                   max(r.session || ':' || lpad(r.semester::text, 2, '0')) FILTER (WHERE r.passed) AS last_pass
              FROM res r GROUP BY r.student_id, r.course_code)
    SELECT DISTINCT a.student_id
      FROM agg a
      JOIN st ON st.id = a.student_id
     WHERE a.last_fail IS NOT NULL AND (a.last_pass IS NULL OR a.last_pass <= a.last_fail)
       AND NOT coalesce((SELECT bool_or(co.basis = 'Elective') FROM catalogue.course_offer co
                          WHERE co.course_code = a.course_code AND co.programme_code = st.programme_code),
                        (SELECT c.kind = 'Elective' FROM catalogue.course c WHERE c.code = a.course_code), false)
$fn$;
COMMENT ON FUNCTION registration.carryover_students(text) IS
  'V573: a department''s current students owing a carryover, registration.carryovers'' rule read for the whole department at once';

COMMIT;
