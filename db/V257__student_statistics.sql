-- ═══════════════════════════════════════════════════════════════════════════
-- V257 · Student statistics: one set of positions every dashboard reads
--
--   The Registrar, the Bursar, the Academic Office, the Directorate of ICT,
--   the Postgraduate School and the College of Health Sciences each asked, in
--   their own words, for the same figures: how many students are in study,
--   how many have paid their school fees, how many have registered their
--   courses, how many have paid but not registered, how many have not paid —
--   by faculty, department and programme, for a session or one of its
--   semesters, with the students behind each figure a click away.
--
--   Until now each desk judged "paid" and "registered" its own way. This
--   function is the one judgement: a student's fee position is the same
--   finance.payment_position the College's payment report reads (V256), and a
--   student is registered when their own register says so — the University
--   form for an undergraduate, the School's form for a postgraduate, the
--   College's enrolment for a clinical student. Every figure on every
--   dashboard is a count over these rows, and every list is a page of them.
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
           reg.registered, reg.registration_status, reg.registered_at
      FROM people.student st
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN ref.department d ON d.code = p.dept_code
      CROSS JOIN LATERAL finance.payment_position(st.id, p_session, p_semester) pos
      CROSS JOIN LATERAL (
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              -- a postgraduate registers on the School's form (V211)
              SELECT (x.state IN ('SUBMITTED','ENDORSED')) AS registered, x.state AS registration_status, coalesce(x.endorsed_at, x.updated_at) AS registered_at, 1 AS pick
                FROM admissions.pg_registration x
               WHERE st.entry_mode = 'POSTGRADUATE' AND x.student_id = st.id AND x.session = p_session AND (p_semester IS NULL OR x.semester = p_semester)
               ORDER BY (x.state IN ('SUBMITTED','ENDORSED')) DESC, x.semester DESC LIMIT 1
          ) r
          UNION ALL
          SELECT r.registered, r.registration_status, r.registered_at FROM (
              -- a clinical student of the College registers the year's semesters on its enrolment (V248/V249)
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
              -- everyone else registers on the University's course registration form (V013)
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

COMMENT ON FUNCTION reporting.student_positions(text, int) IS
  'Every student in study (ACTIVE, PROBATION, ADMITTED) with their fee position and registration for a session '
  '(semester NULL) or one semester of it: the one set of rows the student statistics count and list. Paid means '
  'the charge for the period is fully covered (finance.payment_position); registered means the student''s own '
  'register holds a submitted, approved, locked or endorsed registration for the period, or the College''s '
  'enrolment is registered. A student with no charge stated is neither paid nor unpaid; the count says so.';

COMMIT;
