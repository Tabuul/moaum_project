-- ═══════════════════════════════════════
-- V697 — A spillover payment made for a semester pays that semester only
--
--   The University's word of 29 October 2026: "SPILL OVER STUDENTS WHO ARE TO PAY FOR SECOND SEMESTER SPILL TWO IS SHOWING THEY
--   ALREADY PAID FROM THE LEGACY DATA, THIS IS WRONG, CHECK THE SESSION THEY PAID AND THE CURRENT AND RECONCILE THIS … THIS WAS LAST
--   SESSION SPILL ONE SECOND SEMESTER, PAYMENT IT SHOULD NOT BE APPLIED TO SECOND SEMESTER SPILL TWO".
--
--   A spillover student is charged a semester's spillover fee only for a semester they register a course in (V616), and the
--   session's school-fee payments are applied to the whole-session item, then the first semester, then the second (V664). A
--   spillover student who took and paid the first semester on the old portal (a payment the Old Fees History upload records as
--   "School fees (legacy) · semester 1") has no registration of it on this portal, so the first semester was not charged: its
--   payment went to the second semester, which then read paid — ₦52,150 paid for the first semester against the second
--   semester's ₦22,350 — while nothing had been paid for the second semester. The session read overpaid, and the overpaid desk
--   listed the payment as money to carry or refund. Each reader takes only the session's own payments, so a payment of the
--   session before (spill one's second semester) is not counted in this one; a payment of this session for the first semester was.
--   On the copy of 21 October 2026: 1,046 spillover students paid a semester of 2025/2026 that way with no course registered on
--   the portal, 741 of them read as overpaid.
--
--   V697: a semester the student paid school fees for in the session — the payment naming it (finance.purpose_semester, V649: the
--   old portal's "· semester 1", a spillover reference's "first semester") — is charged as one registered (finance.reg_semesters,
--   finance.fee_profiles): its payment pays it, and the second semester's fee is owed until it is paid itself. The payments are
--   counted by the session they were made for, as before; one made for the whole session or for both semesters is applied in order,
--   as before. A semester charged this way at its spillover line, paid less on the old portal than the line, owes the rest, as it would
--   once registered here. The spillover panel says a semester was charged because it was paid for (paidFor). Nothing is removed,
--   moved or refunded.
-- ═══════════════════════════════════════
BEGIN;

-- ── 1 · the semesters charged: those registered, and those paid for ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.reg_semesters(p_student uuid, p_session text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(array_agg(DISTINCT x.semester ORDER BY x.semester), '{}'::int[])
      FROM (SELECT cr.semester
              FROM registration.course_registration cr
             WHERE cr.student_id = p_student AND cr.session = p_session
               AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
            UNION ALL
            -- V697: a semester the student paid school fees for in the session — the payment names it (the old portal's "· semester 1",
            -- a spillover reference's "first semester") — is charged as one registered: its payment pays it, and never another semester
            SELECT finance.purpose_semester(r.purpose)
              FROM finance.payment_reference r
             WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
               AND r.purpose LIKE 'School fees%' AND finance.purpose_semester(r.purpose) IS NOT NULL
            UNION ALL
            -- V664: the semester finance.semester_position reads as registered, for the length of that one call
            SELECT split_part(g.v, '|', 3)::int
              FROM (SELECT current_setting('moaum.registering', true) AS v) g
             WHERE g.v ~ '^[0-9a-f-]{36}\|[0-9]{4}/[0-9]{4}\|[0-9]$'
               AND split_part(g.v, '|', 1) = p_student::text AND split_part(g.v, '|', 2) = p_session) x
$function$;

-- ── 2 · the fee profiles read the same semesters, once over the session ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.fee_profiles(p_session text)
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, spill_year integer, final_level integer, reg_sems integer[], pg_stage text, pg_category text, profile_key text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V537: each programme's final level read once (456 calls), not twice for every student: on a connection the portal has
    -- used a while, PostgreSQL 18 reads finance.final_level by a cached generic plan that costs about seven times as much a call
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    -- V571: the Bursary's basis for the spillover lines, read once (LEVEL: above the final level; COHORT: the cohort engine's spillover)
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),
    -- V616: the semesters each student has registered a course in, for the session asked — read once over the session's registrations
    -- V697: and each semester they paid school fees for in it (the payment names it), charged as one registered, as finance.reg_semesters
    regs AS MATERIALIZED (
        SELECT x.student_id, array_agg(DISTINCT x.semester ORDER BY x.semester) AS sems
          FROM (SELECT cr.student_id, cr.semester
                  FROM registration.course_registration cr
                 WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
                UNION ALL
                SELECT r.student_id, finance.purpose_semester(r.purpose)
                  FROM finance.payment_reference r
                 WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
                   AND finance.purpose_semester(r.purpose) IS NOT NULL) x
         GROUP BY x.student_id),
    -- V651: each PG student's stage and fresh/returning in the session, read once for all
    pgs AS MATERIALIZED (SELECT x.student_id, x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, NULL) x)
    SELECT s.id, s.status, s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
           lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
           (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END) AS is_spill,
           CASE WHEN s.status = 'GRADUATED' THEN NULL
                WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3)
                     WHEN s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END AS spill_year,   -- V613
           fl.final AS final_level,   -- V613
           CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                    ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END
                THEN coalesce(rg.sems, '{}'::int[]) END AS reg_sems,   -- V616: NULL for a student not in spillover
           pgs.stage_code AS pg_stage, pgs.category AS pg_category,   -- V651
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END),
                     CASE WHEN s.status = 'GRADUATED' THEN NULL
                          WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                          WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3)
                     WHEN s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END,
                     CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                              ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END
                          THEN coalesce(rg.sems, '{}'::int[])::text END,
                     pgs.stage_code, pgs.category) AS profile_key   -- V613: the spillover year, V616: the registered semesters, are part of a spillover profile
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN fl ON fl.code = s.programme_code
      CROSS JOIN basis
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN regs rg ON rg.student_id = s.id
      LEFT JOIN pgs ON pgs.student_id = s.id
$function$;

-- ── 3 · the spillover panel says a semester was charged because it was paid for ─────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.spillover_panel(p_student uuid, p_session text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH s AS (
        SELECT st.id, finance.spill(st.id, st.current_level, st.programme_code, st.status) AS spill,
               finance.spill_year(st.id, st.current_level, st.programme_code, st.status) AS yr
          FROM people.student st WHERE st.id = p_student),
    ap AS (SELECT a.spillover_state FROM people.academic_position a WHERE a.student_id = p_student),
    rs AS (SELECT coalesce(finance.reg_semesters(p_student, p_session), '{}'::int[]) AS sems),
    -- each semester's spillover lines as they would apply once a course is registered in it (V616: p_any_semester)
    lines AS (
        SELECT f.semester, sum(c.amount) AS amount
          FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], NULL, true) c
          JOIN finance.fee_schedule f ON f.id = c.id
         GROUP BY f.semester),
    -- the carry-overs the published results state, by the session and semester they were failed in
    co AS (
        SELECT split_part(c.failed_in, ' semester ', 1) AS session, nullif(split_part(c.failed_in, ' semester ', 2), '')::int AS semester,
               c.course_code, c.title, c.units
          FROM registration.carryovers(p_student) c),
    pos AS (SELECT * FROM finance.position(p_student, p_session)),
    -- V664: what the registration gate reads — the session's confirmed school-fee payments against the cumulative due: the whole-session
    -- item (semester 0) first, then the first semester, then the second; each semester's own amount is its step in that sum
    paid AS (SELECT coalesce(sum(r.amount), 0) AS p FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
    cum AS (SELECT n, finance.due_for_semester(p_student, p_session, n) AS c FROM unnest(ARRAY[0, 1, 2]) n),
    sem AS (
        SELECT k.n, c1.c - c0.c AS owed,
               least(greatest(paid.p - c0.c, 0), c1.c - c0.c) AS applied,
               CASE WHEN finance.fee_short(c1.c, paid.p) THEN (c1.c - c0.c) - least(greatest(paid.p - c0.c, 0), c1.c - c0.c) ELSE 0 END AS left_over,
               -- what is still to pay for the semester to be cleared: anything earlier left unpaid, and its own
               CASE WHEN finance.fee_short(c1.c, paid.p) THEN c1.c - paid.p ELSE 0 END AS to_clear
          FROM unnest(ARRAY[1, 2]) AS k(n)
          JOIN cum c1 ON c1.n = k.n
          JOIN cum c0 ON c0.n = k.n - 1
          CROSS JOIN paid)
    SELECT CASE WHEN NOT s.spill THEN NULL ELSE jsonb_build_object(
        'session', p_session,
        'state', (SELECT ap.spillover_state FROM ap),
        'year', s.yr,
        'label', CASE WHEN s.yr IS NOT NULL THEN 'SP' || s.yr ELSE 'Spillover' END,
        'registeredSemesters', to_jsonb(rs.sems),
        'semesters', (SELECT jsonb_agg(jsonb_build_object(
                          'semester', x.n,
                          'fee', coalesce((SELECT l.amount FROM lines l WHERE l.semester = x.n), 0),
                          'registered', x.n = ANY (rs.sems),
                          -- V697: charged because a school-fee payment of the session was made for it (the old portal's, often), course or not
                          'paidFor', EXISTS (SELECT 1 FROM finance.payment_reference r
                                              WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                                                AND r.purpose LIKE 'School fees%' AND finance.purpose_semester(r.purpose) = x.n),
                          'carryovers', (SELECT count(*) FROM co WHERE co.semester = x.n),
                          -- V674: the carry-over courses on the semester's registration this session (every course a spillover student registers)
                          'registeredCourses', (SELECT count(*) FROM registration.course_registration cr
                                                  JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                                                 WHERE cr.student_id = p_student AND cr.session = p_session AND cr.semester = x.n),
                          'courses', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', co.course_code, 'title', co.title, 'units', co.units, 'session', co.session)
                                                                ORDER BY co.session, co.course_code), '[]'::jsonb) FROM co WHERE co.semester = x.n),
                          -- V664: the semester's own obligation, the payments applied to it, what is left, and where it stands
                          'owed', CASE WHEN x.n = ANY (rs.sems) THEN x.owed ELSE 0 END,
                          'paid', CASE WHEN x.n = ANY (rs.sems) THEN x.applied ELSE 0 END,
                          'outstanding', CASE WHEN x.n = ANY (rs.sems) THEN x.left_over ELSE 0 END,
                          'toClear', CASE WHEN x.n = ANY (rs.sems) THEN x.to_clear ELSE 0 END,
                          'cleared', CASE WHEN x.n = ANY (rs.sems) THEN finance.semester_cleared(p_student, p_session, x.n) ELSE true END,
                          -- registered: ready only when the gate clears it (a whole-session item unpaid holds every semester); a semester
                          -- with no line of its own and no whole-session item is not stated
                          'status', CASE WHEN x.n = ANY (rs.sems) THEN
                                             CASE WHEN x.owed <= 0 AND coalesce((SELECT l.amount FROM lines l WHERE l.semester = x.n), 0) <= 0
                                                       AND coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0) <= 0 THEN 'NOT_STATED'
                                                  WHEN finance.semester_cleared(p_student, p_session, x.n) THEN 'PAID'
                                                  WHEN x.applied > 0 THEN 'PART_PAID'
                                                  ELSE 'PAYMENT_REQUIRED' END
                                         WHEN (SELECT count(*) FROM co WHERE co.semester = x.n) > 0 THEN 'NOT_REGISTERED'
                                         ELSE 'NOTHING_OWED' END)
                          ORDER BY x.n) FROM sem x),
        'sessionFee', coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0),
        'sessionOwed', (SELECT c FROM cum WHERE n = 0),
        'sessionPaid', least((SELECT p FROM paid), (SELECT c FROM cum WHERE n = 0)),
        'due', pos.due, 'paid', pos.paid, 'balance', greatest(pos.balance, 0)) END
      FROM s CROSS JOIN rs CROSS JOIN pos
$function$;

-- how many spillover students of the current session now have a semester charged because they paid for it
DO $$
DECLARE v_ses text := policy.university_current_session(); n int; m int;
BEGIN
    IF v_ses IS NULL THEN RETURN; END IF;
    SELECT count(*), count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = x.student_id AND cr.session = v_ses))
      INTO n, m
      FROM (SELECT DISTINCT r.student_id FROM finance.payment_reference r
             WHERE r.session = v_ses AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
               AND finance.purpose_semester(r.purpose) IS NOT NULL) x
      JOIN finance.fee_profiles(v_ses) fp ON fp.student_id = x.student_id AND fp.is_spill;
    RAISE NOTICE 'V697: % spillover student(s) of % paid school fees for a named semester; % of them have no registration of the session on the portal', n, v_ses, m;
END $$;

COMMIT;
