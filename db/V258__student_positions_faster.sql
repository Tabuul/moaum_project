-- ═══════════════════════════════════════════════════════════════════════════
-- V258 · The student positions counted in one pass
--
--   V257's positions called finance.payment_position for every student, and
--   that in turn asked finance.due_for_semester up to three times, each with
--   its own joins over the fee schedule; on the University's whole register
--   the home page waited on it. The same judgement is made here set-wise: the
--   fee schedule matched to every student once, the session's confirmed
--   payments summed once, the registrations read once. The figures are the
--   figures V257 defined; only the work is smaller.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION reporting.student_positions(p_session text, p_semester int)
RETURNS TABLE (
    student_id uuid, surname text, other_names text, number text,
    faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text,
    level int, status text, entry_mode text, is_pg boolean, is_chs boolean, college_code text, degree_type text,
    payable numeric, paid_amount numeric, outstanding numeric, pay_status text, paid boolean, last_paid_at timestamptz, last_reference text,
    registered boolean, registration_status text, registered_at timestamptz
)
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT lower(btrim(coalesce(home_state, ''))) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_sem AS (SELECT coalesce(p_semester, 3) AS upto),
    me AS (
        SELECT st.id, st.surname, st.other_names, coalesce(st.matric_no, st.admission_no) AS number,
               st.programme_code, st.current_level, st.entry_mode, st.status,
               lower(btrim(coalesce(st.state_of_origin, cr.state_of_origin, ''))) AS state,
               coalesce(st.current_level > finance.final_level(st.programme_code) AND st.status <> 'GRADUATED', false) AS is_spill,
               p.code AS p_code, p.name AS p_name, p.category, p.pg_award, p.faculty_code, p.dept_code,
               f.name AS f_name, coalesce(f.college_code, '') AS college, d.name AS d_name
          FROM people.student st
          JOIN ref.programme p ON p.code = st.programme_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN admissions.candidate c ON c.id = st.candidate_id
          LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
         WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED')
    ),
    -- the fee schedule matched to every student once: the charge up to the semester asked for, and up to the one before it
    sched AS (
        SELECT fs.*, g.applies_category
          FROM finance.fee_schedule fs LEFT JOIN ref.fee_group g ON g.code = fs.fee_group
         WHERE fs.session = p_session AND fs.ended_at IS NULL
    ),
    due AS (
        SELECT me.id,
               coalesce(sum(fs.amount) FILTER (WHERE fs.semester IS NULL OR fs.semester <= (SELECT upto FROM open_sem)), 0) AS upto,
               coalesce(sum(fs.amount) FILTER (WHERE p_semester IS NOT NULL AND p_semester > 1 AND (fs.semester IS NULL OR fs.semester <= p_semester - 1)), 0) AS before
          FROM me
          CROSS JOIN home
          LEFT JOIN sched fs
                 ON fs.spillover = me.is_spill
                AND (me.is_spill OR fs.level IS NULL OR fs.level = me.current_level)
                AND (fs.entry_mode IS NULL OR fs.entry_mode = me.entry_mode)
                AND (fs.faculty_code IS NULL OR fs.faculty_code = me.faculty_code)
                AND (fs.programme_code IS NULL OR fs.programme_code = me.programme_code)
                AND (fs.fee_group IS NULL OR fs.applies_category IS NULL OR fs.applies_category = me.category)
                AND (fs.indigene IS NULL OR (fs.indigene = 'INDIGENE') = (me.state = home.home_state))
         GROUP BY me.id
    ),
    -- the session's confirmed school-fee payments, summed once, with the last of them
    pay AS (
        SELECT r.student_id, sum(r.amount) AS total, max(r.confirmed_at) AS last_at
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id
    ),
    last_ref AS (
        SELECT DISTINCT ON (r.student_id) r.student_id, r.reference
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.student_id, r.confirmed_at DESC
    ),
    -- the registrations, each register read once
    ug AS (
        SELECT DISTINCT ON (x.student_id) x.student_id, (x.status IN ('SUBMITTED','APPROVED','LOCKED')) AS registered, x.status, coalesce(x.approved_at, x.submitted_at) AS at
          FROM registration.course_registration x
         WHERE x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
         ORDER BY x.student_id, (x.status IN ('SUBMITTED','APPROVED','LOCKED')) DESC, x.semester DESC
    ),
    pgr AS (
        SELECT DISTINCT ON (x.student_id) x.student_id, (x.state IN ('SUBMITTED','ENDORSED')) AS registered, x.state AS status, coalesce(x.endorsed_at, x.updated_at) AS at
          FROM admissions.pg_registration x
         WHERE x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
         ORDER BY x.student_id, (x.state IN ('SUBMITTED','ENDORSED')) DESC, x.semester DESC
    ),
    chs AS (
        SELECT DISTINCT ON (e.student_id) e.student_id,
               (e.registered_at IS NOT NULL OR (p_semester IS NOT NULL AND EXISTS (
                   SELECT 1 FROM college.enrolment_semester es WHERE es.enrolment_id = e.id AND es.ordinal = p_semester AND es.registered_at IS NOT NULL))) AS registered,
               CASE WHEN e.registered_at IS NOT NULL THEN 'REGISTERED' ELSE 'OPEN' END AS status,
               coalesce(e.registered_at, (SELECT max(es.registered_at) FROM college.enrolment_semester es WHERE es.enrolment_id = e.id)) AS at
          FROM college.enrolment e
         WHERE e.session = p_session AND e.state IN ('OPEN','RESIT','CLOSED')
         ORDER BY e.student_id, e.registered_at DESC NULLS LAST
    ),
    pos AS (
        SELECT me.*,
               greatest(due.upto - due.before, 0) AS payable,
               coalesce(pay.total, 0) AS paid_all,
               least(greatest(coalesce(pay.total, 0) - due.before, 0), greatest(due.upto - due.before, 0)) AS applied,
               pay.last_at, last_ref.reference,
               CASE WHEN me.entry_mode = 'POSTGRADUATE' THEN pgr.registered
                    WHEN me.college = 'CHS' AND me.current_level >= 200 THEN chs.registered
                    ELSE ug.registered END AS registered,
               CASE WHEN me.entry_mode = 'POSTGRADUATE' THEN pgr.status
                    WHEN me.college = 'CHS' AND me.current_level >= 200 THEN chs.status
                    ELSE ug.status END AS registration_status,
               CASE WHEN me.entry_mode = 'POSTGRADUATE' THEN pgr.at
                    WHEN me.college = 'CHS' AND me.current_level >= 200 THEN chs.at
                    ELSE ug.at END AS registered_at
          FROM me
          JOIN due ON due.id = me.id
          LEFT JOIN pay ON pay.student_id = me.id
          LEFT JOIN last_ref ON last_ref.student_id = me.id
          LEFT JOIN ug ON ug.student_id = me.id
          LEFT JOIN pgr ON pgr.student_id = me.id
          LEFT JOIN chs ON chs.student_id = me.id
    )
    SELECT pos.id, pos.surname, pos.other_names, pos.number,
           pos.faculty_code, pos.f_name, pos.dept_code, pos.d_name, pos.p_code, pos.p_name,
           pos.current_level, pos.status, pos.entry_mode,
           (pos.entry_mode = 'POSTGRADUATE' OR pos.category = 'POST GRADUATE'),
           (pos.college = 'CHS'), nullif(pos.college, ''),
           CASE WHEN pos.entry_mode = 'POSTGRADUATE' OR pos.category = 'POST GRADUATE'
                THEN CASE WHEN upper(coalesce(pos.pg_award, '')) = 'PHD' THEN 'PHD'
                          WHEN upper(coalesce(pos.pg_award, '')) = 'MPHIL' THEN 'MPHIL'
                          WHEN upper(coalesce(pos.pg_award, '')) = 'PGD' THEN 'PGD'
                          WHEN pos.pg_award IS NOT NULL AND pos.pg_award <> '' THEN 'MASTERS'
                          WHEN pos.current_level >= 900 THEN 'PHD' WHEN pos.current_level >= 800 THEN 'MASTERS' ELSE 'PGD' END
                ELSE NULL END,
           pos.payable,
           CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END,
           greatest(pos.payable - CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END, 0),
           CASE WHEN pos.payable = 0 THEN 'NO_CHARGE'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) >= pos.payable THEN 'FULLY_PAID'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           pos.payable > 0 AND (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) >= pos.payable,
           pos.last_at, pos.reference,
           coalesce(pos.registered, false), pos.registration_status, pos.registered_at
      FROM pos;
$$;

COMMIT;
