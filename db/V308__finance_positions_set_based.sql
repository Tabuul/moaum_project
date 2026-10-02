-- ═══════════════════════════════════════════════════════════════════════════
-- V308 — fee positions for a whole session in one pass
--
--   reporting.student_positions, finance.collection_by_faculty, the HOD and
--   College dashboards and the Records summary all asked a per-student question
--   (finance.payment_position, finance.charges, finance.clears, clearance.is_clear)
--   once for each of the University's 54,572 students. Each answer re-read the
--   fee schedule with every rule applied, and the arrears check re-read it again
--   for every past session. Production measured the analytics summary at 4 to 14
--   minutes a call and the collection-by-faculty report at 37 seconds.
--
--   A student's charge depends only on a PROFILE — programme, level, entry mode,
--   State of origin and whether they are in a spill-over year — and there are a
--   few thousand distinct profiles, not fifty thousand students. The functions
--   below compute the schedule once per profile, the payments once per student
--   in a single aggregate, and join. Every rule is the same rule as the
--   per-student function it stands beside (finance.due_for_semester,
--   finance.charges_as, finance.late_payment_applies,
--   finance.late_registration_applies, finance.position, policy.clears), and the
--   per-student functions are unchanged for the student's own portal. The
--   equivalence was checked row for row against a copy of production.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. the profile a student's charges depend on ──────────────────────────
CREATE OR REPLACE FUNCTION finance.fee_profiles()
RETURNS TABLE (student_id uuid, status text, programme_code text, faculty_code text, category text,
               current_level int, entry_mode text, state text, is_spill boolean, profile_key text)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.status, s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
           lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
           coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill,
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false)) AS profile_key
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
$$;
COMMENT ON FUNCTION finance.fee_profiles() IS
  'Every student with the attributes the fee schedule''s rules read (V308). profile_key names the distinct '
  'combination; students sharing it owe the same schedule. The same joins and expressions as finance.charges_of_as.';

-- ── 2. the schedule, summed once per profile ──────────────────────────────
-- due_before/due_upto are finance.due_for_semester(p_semester - 1) and (p_semester), as
-- finance.payment_position reads them; fee/late_* are finance.charges_of_as by kind, with the
-- open-semester cut-off that function applies.
CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester int)
RETURNS TABLE (profile_key text, due_before numeric, due_upto numeric, fee numeric, late_payment numeric, late_registration numeric)
LANGUAGE sql STABLE AS $$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_max AS (SELECT coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 3) AS n),
    prof AS (SELECT DISTINCT pr.profile_key, pr.programme_code, pr.faculty_code, pr.category, pr.current_level, pr.entry_mode, pr.state, pr.is_spill
               FROM finance.fee_profiles() pr),
    matched AS (
        SELECT pr.profile_key, f.kind, f.semester, f.amount
          FROM prof pr
          CROSS JOIN home
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (pr.is_spill OR f.level IS NULL OR f.level = pr.current_level)
           AND (f.entry_mode IS NULL OR f.entry_mode = pr.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code)
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (pr.state = home.home_state)))
    SELECT m.profile_key,
           CASE WHEN p_semester IS NULL OR p_semester <= 1 THEN 0
                ELSE coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= p_semester - 1), 0) END,
           CASE WHEN p_semester IS NULL THEN coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= 3), 0)
                ELSE coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= p_semester), 0) END,
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'FEE' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0),
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'LATE_PAYMENT' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0),
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'LATE_REGISTRATION' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0)
      FROM matched m
     GROUP BY m.profile_key
$$;

-- ── 3. the session's school-fees payments, once per student ───────────────
CREATE OR REPLACE FUNCTION finance.session_payments(p_session text)
RETURNS TABLE (student_id uuid, total numeric, n int, last_paid_at timestamptz, last_reference text, last_channel text)
LANGUAGE sql STABLE AS $$
    WITH p AS (
        SELECT r.student_id, r.amount, r.confirmed_at, r.reference, r.channel
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
    agg AS (SELECT p.student_id, sum(p.amount) AS total, count(*)::int AS n FROM p GROUP BY p.student_id),
    last AS (SELECT DISTINCT ON (p.student_id) p.student_id, p.confirmed_at, p.reference, p.channel FROM p ORDER BY p.student_id, p.confirmed_at DESC)
    SELECT agg.student_id, agg.total, agg.n, last.confirmed_at, last.reference, last.channel
      FROM agg JOIN last ON last.student_id = agg.student_id
$$;

-- ── 4. finance.payment_position for every student of a session ────────────
CREATE OR REPLACE FUNCTION finance.session_positions(p_session text, p_semester int)
RETURNS TABLE (student_id uuid, payable numeric, paid numeric, outstanding numeric, status text,
               last_paid_at timestamptz, last_reference text, last_channel text, payments int, cleared_upto boolean)
LANGUAGE sql STABLE AS $$
    WITH pos AS (
        SELECT pr.student_id,
               greatest(coalesce(s.due_upto, 0) - coalesce(s.due_before, 0), 0) AS payable,
               least(greatest(coalesce(pay.total, 0) - coalesce(s.due_before, 0), 0),
                     greatest(coalesce(s.due_upto, 0) - coalesce(s.due_before, 0), 0)) AS applied,
               coalesce(pay.total, 0) AS paid_all, coalesce(pay.n, 0) AS n,
               coalesce(s.due_upto, 0) AS upto,
               pay.last_paid_at, pay.last_reference, pay.last_channel
          FROM finance.fee_profiles() pr
          LEFT JOIN finance.fee_sums(p_session, p_semester) s ON s.profile_key = pr.profile_key
          LEFT JOIN finance.session_payments(p_session) pay ON pay.student_id = pr.student_id)
    SELECT pos.student_id, pos.payable,
           CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END,
           greatest(pos.payable - CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END, 0),
           CASE WHEN pos.payable = 0 THEN 'NO_CHARGE'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) >= pos.payable THEN 'FULLY_PAID'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           pos.last_paid_at, pos.last_reference, pos.last_channel, pos.n,
           pos.paid_all >= pos.upto
      FROM pos
$$;
COMMENT ON FUNCTION finance.session_positions(text, int) IS
  'finance.payment_position(student, session, semester) for every student at once (V308); cleared_upto is '
  'finance.semester_cleared(student, session, semester): the session''s payments cover everything due up to that semester.';

-- ── 5. sum(finance.charges(student, session)) for every student ───────────
CREATE OR REPLACE FUNCTION finance.session_charges(p_session text)
RETURNS TABLE (student_id uuid, fee numeric, late_payment boolean, late_registration boolean, total numeric)
LANGUAGE sql STABLE AS $$
    WITH w AS (SELECT * FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL)),
    reg_windows AS (
        SELECT sem, rw.phase, rw.closes_at
          FROM generate_series(1, 3) sem
          CROSS JOIN LATERAL policy.window_state('COURSE_REGISTRATION', p_session, sem) rw
         WHERE rw.configured AND rw.late_fee_enabled),
    paid_in_time AS (
        SELECT r.student_id, sum(r.amount) AS total
          FROM finance.payment_reference r CROSS JOIN w
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
           AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)
         GROUP BY r.student_id),
    each AS (
        SELECT pr.student_id, coalesce(s.fee, 0) AS fee, coalesce(s.late_payment, 0) AS lp, coalesce(s.late_registration, 0) AS lr,
               (SELECT w.late_fee_enabled AND w.phase = 'LATE' FROM w) AND coalesce(pit.total, 0) < coalesce(s.fee, 0) AS late_payment,
               EXISTS (
                   SELECT 1 FROM reg_windows rw
                    WHERE (rw.phase = 'LATE' AND NOT EXISTS (
                               SELECT 1 FROM registration.course_registration cr
                                WHERE cr.student_id = pr.student_id AND cr.session = p_session AND cr.semester = rw.sem
                                  AND cr.submitted_at IS NOT NULL AND (rw.closes_at IS NULL OR cr.submitted_at <= rw.closes_at))
                          OR EXISTS (
                               SELECT 1 FROM registration.course_registration cr
                                WHERE cr.student_id = pr.student_id AND cr.session = p_session AND cr.semester = rw.sem
                                  AND cr.submitted_at IS NOT NULL AND rw.closes_at IS NOT NULL AND cr.submitted_at > rw.closes_at))) AS late_registration
          FROM finance.fee_profiles() pr
          LEFT JOIN finance.fee_sums(p_session, NULL) s ON s.profile_key = pr.profile_key
          LEFT JOIN paid_in_time pit ON pit.student_id = pr.student_id)
    SELECT e.student_id, e.fee, coalesce(e.late_payment, false), e.late_registration,
           e.fee + CASE WHEN coalesce(e.late_payment, false) THEN e.lp ELSE 0 END + CASE WHEN e.late_registration THEN e.lr ELSE 0 END
      FROM each e
$$;
COMMENT ON FUNCTION finance.session_charges(text) IS
  'The sum of finance.charges(student, session) for every student at once (V308): the FEE items, plus the late-payment '
  'and late-registration items exactly when finance.late_payment_applies / late_registration_applies say so.';

-- ── 6. finance.position for every student: due, paid, instalments, arrears ─
CREATE OR REPLACE FUNCTION finance.session_fee_positions(p_session text)
RETURNS TABLE (student_id uuid, due numeric, paid numeric, balance numeric, instalments_paid int, paid_in_full boolean, has_arrears boolean)
LANGUAGE sql STABLE AS $$
    WITH past AS (SELECT DISTINCT f.session FROM finance.fee_schedule f WHERE f.session < p_session AND f.ended_at IS NULL),
    past_paid AS (
        SELECT r.student_id, r.session, sum(r.amount) AS total
          FROM finance.payment_reference r JOIN past ON past.session = r.session
         WHERE r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id, r.session),
    arrears AS (
        SELECT DISTINCT c.student_id
          FROM past CROSS JOIN LATERAL finance.session_charges(past.session) c
          LEFT JOIN past_paid pp ON pp.student_id = c.student_id AND pp.session = past.session
         WHERE c.total > coalesce(pp.total, 0)),
    now_ AS (
        SELECT c.student_id, c.total AS due, coalesce(pay.total, 0) AS paid
          FROM finance.session_charges(p_session) c
          LEFT JOIN finance.session_payments(p_session) pay ON pay.student_id = c.student_id)
    SELECT n.student_id, n.due, n.paid, greatest(n.due - n.paid, 0),
           CASE WHEN n.due = 0 THEN 2 WHEN n.paid >= n.due THEN 2 WHEN n.paid * 2 >= n.due THEN 1 ELSE 0 END,
           n.due = 0 OR n.paid >= n.due,
           EXISTS (SELECT 1 FROM arrears a WHERE a.student_id = n.student_id)
      FROM now_ n
$$;

-- ── 7. finance.clears(student, session, purpose) for every student ────────
CREATE OR REPLACE FUNCTION finance.session_clears(p_session text, p_purpose text)
RETURNS TABLE (student_id uuid, clears boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_version uuid; v_at text; v_arrears boolean;
BEGIN
    -- the same refusals as policy.clears, from policy.clears itself: no scheme in force, no rule for the purpose
    PERFORM policy.clears(p_purpose, 0, false, false, current_date, 'UNIVERSITY');
    v_version := policy.in_force('clearance', 'UNIVERSITY', current_date);
    SELECT r.releases_at, s.arrears_block_all INTO v_at, v_arrears
      FROM policy.clearance_rule r JOIN policy.clearance_scheme s ON s.version_id = r.version_id
     WHERE r.version_id = v_version AND r.purpose = p_purpose;

    RETURN QUERY
    SELECT p.student_id,
           CASE WHEN v_at = 'NEVER_GATED' THEN true
                WHEN v_arrears AND p.has_arrears THEN false
                ELSE CASE v_at WHEN 'INSTALMENT_1' THEN p.instalments_paid >= 1
                               WHEN 'INSTALMENT_2' THEN p.instalments_paid >= 2
                               WHEN 'PAID_IN_FULL' THEN p.paid_in_full END END
      FROM finance.session_fee_positions(p_session) p;
END $$;

-- ── 8. the consumers: the same output, one pass ───────────────────────────
CREATE OR REPLACE FUNCTION reporting.student_positions(p_session text, p_semester integer)
RETURNS TABLE(student_id uuid, surname text, other_names text, number text, faculty_code text, faculty text, dept_code text, department text,
              programme_code text, programme text, level integer, status text, entry_mode text, is_pg boolean, is_chs boolean, college_code text,
              degree_type text, payable numeric, paid_amount numeric, outstanding numeric, pay_status text, paid boolean,
              last_paid_at timestamptz, last_reference text, registered boolean, registration_status text, registered_at timestamptz,
              sex text, entry_session text, matriculated_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT st.id, st.surname, st.other_names, coalesce(st.matric_no, st.admission_no),
           f.code, f.name, d.code, d.name, p.code, p.name,
           st.current_level, st.status, st.entry_mode,
           (st.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE'),
           (coalesce(f.college_code, '') = 'CHS'), f.college_code,
           CASE WHEN st.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE'
                THEN CASE WHEN upper(coalesce(p.pg_award, '')) IN ('PHD') THEN 'PHD'
                          WHEN upper(coalesce(p.pg_award, '')) IN ('MPHIL') THEN 'MPHIL'
                          WHEN upper(coalesce(p.pg_award, '')) = 'PGD' THEN 'PGD'
                          WHEN p.pg_award IS NOT NULL AND p.pg_award <> '' THEN 'MASTERS'
                          WHEN st.current_level >= 900 THEN 'PHD' WHEN st.current_level >= 800 THEN 'MASTERS' ELSE 'PGD' END
                ELSE NULL END,
           pos.payable, pos.paid, pos.outstanding, pos.status, pos.status = 'FULLY_PAID', pos.last_paid_at, pos.last_reference,
           reg.registered, reg.registration_status, reg.registered_at,
           st.sex, st.entry_session, st.matriculated_at
      FROM people.student st
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN ref.department d ON d.code = p.dept_code
      JOIN finance.session_positions(p_session, p_semester) pos ON pos.student_id = st.id
      CROSS JOIN LATERAL (
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              SELECT (x.state IN ('SUBMITTED','ENDORSED')) AS registered, x.state AS registration_status, coalesce(x.endorsed_at, x.updated_at) AS registered_at, 1 AS pick
                FROM admissions.pg_registration x
               WHERE st.entry_mode = 'POSTGRADUATE' AND x.student_id = st.id AND x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
               ORDER BY (x.state IN ('SUBMITTED','ENDORSED')) DESC, x.semester DESC LIMIT 1
          ) r
          UNION ALL
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              SELECT (e.registered_at IS NOT NULL OR (p_semester IS NOT NULL AND EXISTS (
                          SELECT 1 FROM college.enrolment_semester es WHERE es.enrolment_id = e.id AND es.ordinal = p_semester AND es.registered_at IS NOT NULL))) AS registered,
                     CASE WHEN e.registered_at IS NOT NULL THEN 'REGISTERED' ELSE 'OPEN' END AS registration_status,
                     coalesce(e.registered_at, (SELECT max(es.registered_at) FROM college.enrolment_semester es WHERE es.enrolment_id = e.id)) AS registered_at, 2 AS pick
                FROM college.enrolment e
               WHERE st.entry_mode <> 'POSTGRADUATE' AND coalesce(f.college_code, '') = 'CHS' AND st.current_level >= 200
                 AND e.student_id = st.id AND e.session = p_session AND e.state IN ('OPEN','RESIT','CLOSED')
               ORDER BY e.registered_at DESC NULLS LAST LIMIT 1
          ) r
          UNION ALL
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              SELECT (x.status IN ('SUBMITTED','APPROVED','LOCKED')) AS registered, x.status AS registration_status,
                     coalesce(x.approved_at, x.submitted_at) AS registered_at, 3 AS pick
                FROM registration.course_registration x
               WHERE st.entry_mode <> 'POSTGRADUATE' AND NOT (coalesce(f.college_code, '') = 'CHS' AND st.current_level >= 200)
                 AND x.student_id = st.id AND x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
               ORDER BY (x.status IN ('SUBMITTED','APPROVED','LOCKED')) DESC, x.semester DESC LIMIT 1
          ) r
          UNION ALL
          SELECT false, NULL::text, NULL::timestamptz
          ORDER BY registered DESC NULLS LAST LIMIT 1
      ) reg
     WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED');
$$;

CREATE OR REPLACE FUNCTION finance.collection_by_faculty(p_session text)
RETURNS TABLE(faculty_code text, faculty_name text, students bigint, paid_students bigint, collected numeric, due numeric)
LANGUAGE sql STABLE AS $$
    WITH enrolled AS (
        SELECT s.id, p.faculty_code FROM people.enrolment e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
         WHERE e.session = p_session),
    paid AS (
        SELECT r.student_id, sum(r.amount) AS amount FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%' GROUP BY r.student_id),
    charged AS (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c)
    SELECT f.code, f.name, count(en.id), count(pd.student_id), coalesce(sum(pd.amount), 0), coalesce(sum(coalesce(ch.total, 0)), 0)
      FROM ref.faculty f LEFT JOIN enrolled en ON en.faculty_code = f.code LEFT JOIN paid pd ON pd.student_id = en.id
      LEFT JOIN charged ch ON ch.student_id = en.id
     GROUP BY f.code, f.name HAVING count(en.id) > 0 ORDER BY f.name
$$;

-- ── 9. clearance.migrated_summary: the latest decision per unit, once ──────
CREATE OR REPLACE FUNCTION clearance.migrated_summary(p_from integer DEFAULT 100, p_to integer DEFAULT 400)
RETURNS TABLE(migrated bigint, cleared bigint, uncleared bigint)
LANGUAGE sql STABLE AS $$
    WITH m AS (
        SELECT s.id FROM people.student s
         WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
           AND s.current_level BETWEEN p_from AND p_to
           AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
    ),
    latest AS (
        SELECT DISTINCT ON (c.student_id, c.purpose, c.unit) c.student_id, c.purpose, c.unit, c.state
          FROM clearance.item c JOIN m ON m.id = c.student_id
         WHERE c.superseded_by IS NULL
         ORDER BY c.student_id, c.purpose, c.unit, c.decided_at DESC
    ),
    not_clear AS (
        SELECT DISTINCT m.id
          FROM m
          CROSS JOIN ref.clearance_purpose pu
          CROSS JOIN clearance.unit u
          LEFT JOIN latest l ON l.student_id = m.id AND l.purpose = pu.code AND l.unit = u.code
         WHERE coalesce(l.state, 'HELD') <> 'CLEARED'
    )
    SELECT count(*), count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM not_clear n WHERE n.id = m.id)),
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM not_clear n WHERE n.id = m.id))
      FROM m
$$;

COMMIT;
