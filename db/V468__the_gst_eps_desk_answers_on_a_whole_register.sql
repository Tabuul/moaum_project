-- ═══════════════════════════════════════
-- V468 — The GST/EPS desk answers on a whole register
--
-- The GST and EPS offices' desk (dashboard, students, fee review) reads finance.gst_population, which runs the course engine
-- (finance.gst_eps_rows, V366/V422) over every undergraduate of the session. On the live-shaped copy that took about two
-- minutes (103,437 course rows for 51,121 students), and the desk asks for it twice a page, so the dashboard and the students
-- list never answered. The engine is right; its plan is not: the planner reads the 31 GST/EPS courses as one (kind = 'GST'
-- and general_office are taken as independent, though every course with an office is a GST course), every estimate after it
-- shrinks to a row or two, and the final joins become nested loops over unindexed intermediate results — 103,437 rows matched
-- against 13,169 passes and 2,020 carry-overs one by one.
--
-- finance.gst_eps_rows_all(session) is the same engine over the whole register, planned with nested loops off (a function
-- with its own setting is planned on its own): 103,437 rows in about 2.6 s, the same rows. finance.gst_population (restated
-- from V380, nothing else changed) reads it. The one-student engine — the registration menu, eligibility, a student's fees —
-- is untouched and still inlined where it is called.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V468: the GST/EPS desk answers on a whole register', true);

CREATE OR REPLACE FUNCTION finance.gst_eps_rows_all(p_session text)
 RETURNS TABLE(student_id uuid, course_code text, title text, units integer, office text, level integer, semesters integer[], offering_id uuid, source text, counts boolean, status text, registered boolean, failed_in text, last_grade text, passed_in text)
 LANGUAGE sql
 STABLE
 ROWS 100000
 SET enable_nestloop TO 'off'
AS $function$
    SELECT * FROM finance.gst_eps_rows(p_session, NULL)
$function$;

COMMENT ON FUNCTION finance.gst_eps_rows_all(text) IS
    'V468: finance.gst_eps_rows over every undergraduate of the session, planned without nested loops — the whole-register engine the GST/EPS desk reads (finance.gst_population). The one-student engine is finance.gst_eps_rows(session, student).';

-- V380's definition; only the engine it reads changes
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
            LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                  AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                LIMIT 1) fr ON true
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

COMMIT;
